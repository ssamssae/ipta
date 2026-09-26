from __future__ import annotations
import ctypes
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ipta_win import oauth, paste, polish
from ipta_win.app import AppState

class RecoveryTests(unittest.TestCase):
    def test_silence_preserves_previous_result_and_raw(self):
        state = AppState()
        state.transcript, state.raw_transcript = 'previous result', 'previous raw'
        with patch('ipta_win.app.transcribe.transcribe', return_value='  '):
            state.finish_wav(Path('/unused-fixture.wav'), state._job)
        self.assertEqual((state.transcript,state.raw_transcript),('previous result','previous raw'))
        self.assertIn('이전 결과',state.status_line)

    def test_registered_spelling_changes_are_rejected(self):
        state = AppState(polish_enabled=True, polish_plan=polish.PolishPlan(tier='connected', provider='grok', auth_mode='oauth'))
        state.personal.data['vocabulary'] = [{'heard': '입 타', 'spelling': '입타'}]
        state.model_transform = Mock(return_value='다른앱을 써요')
        text, note, used = state.polish_text('입타를 써요')
        self.assertEqual(text, '입타를 써요')
        self.assertFalse(used)

    def test_numeric_changes_are_rejected(self):
        state = AppState(polish_enabled=True, polish_plan=polish.PolishPlan(tier='connected', provider='grok', auth_mode='oauth'))
        state.model_transform = Mock(return_value='금액은 29000원입니다')
        text, note, used = state.polish_text('금액은 19000원입니다')
        self.assertEqual(text,'금액은 19000원입니다')
        self.assertFalse(used)

    def test_failed_cli_output_is_never_inserted(self):
        with self.assertRaises(oauth.CliFailure) as caught:
            oauth.run_cli([sys.executable, '-c', 'import sys; print("not a result"); sys.exit(2)'], raise_errors=True)
        self.assertEqual(caught.exception.reason, 'execution')

    def test_timeout_is_not_authentication_failure(self):
        state = AppState(polish_enabled=True, polish_plan=polish.PolishPlan(tier='connected', provider='grok', auth_mode='oauth'))
        state.model_transform = Mock(side_effect=oauth.CliFailure('timeout'))
        text, note, used = state.polish_text('안녕하세요')
        self.assertEqual(text, '안녕하세요')
        self.assertFalse(used)
        self.assertIn('응답이 늦어', note)
        self.assertNotIn('로그인을 쓰지 못해', note)

    def test_grok_json_uses_only_final_text(self):
        with patch.object(oauth, 'probe', return_value=oauth.Probe(True, False, '')), patch.object(oauth, 'binary', return_value=Path('/grok')), patch.object(oauth, 'run_grok_stream', return_value=json.dumps({'text':'안녕하세요', 'thought':'private', 'usage':{}})) as run:
            self.assertEqual(oauth.polish_via_cli('grok', '다듬어', '안녕하세요'), '안녕하세요')
            args = run.call_args.args[0]
            self.assertEqual(args[args.index('--tools')+1], '')
            self.assertEqual(args[args.index('--reasoning-effort')+1], 'low')
            self.assertEqual(run.call_args.kwargs['timeout'], 15)

    def test_clipboard_transfers_full_pointer_and_ownership(self):
        handle, pointer, owner = 0x123456789ABC, 0x23456789ABCD, 555
        kernel = SimpleNamespace(GlobalAlloc=Mock(return_value=handle), GlobalLock=Mock(return_value=pointer), GlobalUnlock=Mock(), GlobalFree=Mock())
        user = SimpleNamespace(CreateWindowExW=Mock(return_value=owner), DestroyWindow=Mock(), OpenClipboard=Mock(return_value=True), EmptyClipboard=Mock(return_value=True), SetClipboardData=Mock(return_value=handle), CloseClipboard=Mock())
        with patch.object(paste, '_clipboard_api', return_value=(user, kernel)), patch.object(ctypes, 'memmove') as move:
            paste._win_clipboard('한글')
        move.assert_called_once_with(pointer, '한글'.encode('utf-16-le')+b'\0\0', 6)
        user.OpenClipboard.assert_called_once_with(owner)
        user.SetClipboardData.assert_called_once_with(13, handle)
        kernel.GlobalFree.assert_not_called()
        user.DestroyWindow.assert_called_once_with(owner)

    def test_failed_clipboard_transfer_frees_memory(self):
        kernel = SimpleNamespace(GlobalAlloc=Mock(return_value=123), GlobalLock=Mock(return_value=0), GlobalFree=Mock())
        user = SimpleNamespace(CreateWindowExW=Mock(return_value=555), DestroyWindow=Mock())
        with patch.object(paste, '_clipboard_api', return_value=(user,kernel)), self.assertRaises(RuntimeError):
            paste._win_clipboard('a')
        kernel.GlobalFree.assert_called_once_with(123)
        user.DestroyWindow.assert_called_once_with(555)

if __name__ == '__main__':
    unittest.main()
