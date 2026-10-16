"""Long speech must survive recording, cleanup, model limits and repeated stop keys."""
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ipta_win import audio, info, polish, speech, transcribe
from ipta_win.app import AppState


class LongDictationTests(unittest.TestCase):
    def test_preceding_sentences_and_negative_instruction_survive(self):
        text = '첫 번째 설정을 확인해 줘. 두 번째 기록도 확인해 줘. 수정은 말고 원인만 찾아줘.'
        self.assertEqual(speech.clean(text), text)
        for separator in ['아니', '아니야', '아냐', '아니라']:
            text = f'앞의 요청을 모두 기록해. {separator} 추가 요청도 뒤에 기록해.'
            self.assertEqual(speech.clean(text), text)
        self.assertEqual(speech.clean('수량은 10 10 20개야'), '수량은 10 10 20개야')

    def test_truncated_polish_keeps_complete_transcription(self):
        text = '첫 번째 설정을 확인하고 기록을 보존해 주세요. ' * 12 + '끝으로 마지막 요청도 반드시 남겨 주세요.'
        state = AppState(polish_enabled=True, polish_plan=polish.PolishPlan(tier='connected', provider='grok', auth_mode='oauth'))
        state.model_transform = lambda *args, **kwargs: text[:90]
        actual, _, used = state.polish_text(text)
        self.assertEqual(actual, text)
        self.assertFalse(used)

    def test_repeated_stop_does_not_cancel_processing(self):
        for phase in ['transcribing', 'polishing', 'downloading']:
            state = AppState(phase=phase, transcript='완성 중인 긴 문장', _job=7)
            with patch('ipta_win.app.transcribe.cancel') as cancel:
                state.toggle()
            self.assertEqual((state.phase, state._job, state.transcript), (phase, 7, '완성 중인 긴 문장'))
            cancel.assert_not_called()
        with patch('ipta_win.app.transcribe.cancel') as cancel:
            state.phase = 'transcribing'
            state.cancel()
        cancel.assert_called_once()

    def test_audio_continues_after_one_minute_until_user_stop(self):
        class Frames:
            def __init__(self, data): self.data = data
            def copy(self): return self
            def __mul__(self, other): return self
            def astype(self, kind): return self
            def tobytes(self): return self.data
        clock = [0.0]
        callback = [None]
        class Stream:
            def __init__(self, **kwargs): callback[0] = kwargs['callback']
            def __enter__(self): return self
            def __exit__(self, *args): return False
        def tick(_):
            callback[0](Frames(b'\0' * 32000), 16000, None, None)
            clock[0] += 1
        numpy = SimpleNamespace(concatenate=lambda frames, axis: Frames(b''.join(f.data for f in frames)), clip=lambda a, *args: a)
        with tempfile.TemporaryDirectory() as folder:
            wav = Path(folder) / 'record.wav'
            with patch.dict(sys.modules, numpy=numpy, sounddevice=SimpleNamespace(InputStream=Stream)), patch.object(sys, 'platform', 'win32'), patch.object(audio, 'list_devices', return_value=[('0', 'fixture')]), patch('time.monotonic', side_effect=lambda: clock[0]), patch('time.sleep', side_effect=tick):
                audio.record_wav(wav, info.MAX_SECONDS, should_stop=lambda: clock[0] >= 75)
            with wave.open(str(wav)) as recorded:
                self.assertEqual(recorded.getnframes() / recorded.getframerate(), 75)

    def test_long_audio_gets_time_to_finish_on_cpu(self):
        with tempfile.TemporaryDirectory() as folder:
            wav = Path(folder) / 'long.wav'
            with wave.open(str(wav), 'wb') as output:
                output.setnchannels(1); output.setsampwidth(2); output.setframerate(16000)
                output.writeframes(b'\0' * (16000 * 2 * 180))
            self.assertGreaterEqual(transcribe.request_timeout(wav), 390)
        self.assertEqual(transcribe.request_timeout(Path('/missing')), 90)

    def test_incomplete_api_responses_are_not_pasted(self):
        for provider in ['local', 'openai', 'grok']:
            partial = {'choices': [{'finish_reason': 'length', 'message': {'content': '문장의 앞부분'}}]}
            self.assertIsNone(polish.parse_text(provider, json.dumps(partial).encode()))
        self.assertIsNone(polish.parse_text('claude', json.dumps({'stop_reason':'max_tokens', 'content':[{'text':'문장의 앞부분'}]}).encode()))
        text = '긴 문장입니다. ' * 100
        request = polish.make_request('local', '', 'existing-model', 'preserve words', text)
        self.assertGreater(json.loads(request.data)['max_tokens'], 220)


if __name__ == '__main__':
    unittest.main()
