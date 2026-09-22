from __future__ import annotations
import json, os, subprocess, sys, tempfile, threading, time, unittest
from pathlib import Path
from unittest.mock import Mock, patch
from ipta_win import personalization, selection, grok_stream, oauth, transcribe
from ipta_win.app import AppState
from ipta_win.warm_engine import WarmEngine


class PersonalizationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'personalization.json'
        self.p=personalization.Personalization(self.path);self.p.load()

    def test_words_boundaries_particles_longest_and_no_cascade(self):
        self.p.add_word('입 타','입타');self.p.add_word('입타','Ipta');self.p.add_word('입','mouth')
        self.assertEqual(self.p.apply('입 타는 입타 입 타워 입구'), '입타는 Ipta mouth 타워 입구')
        with self.assertRaises(ValueError): self.p.add_word('입 타','duplicate')
        with self.assertRaises(ValueError): self.p.add_word('', 'empty')
        self.p.remove_word('입');self.assertNotIn('mouth',self.p.apply('입'))

    def test_roundtrip_and_tone_removal(self):
        self.p.set_tone('CURSOR.EXE','technical')
        fresh=personalization.Personalization(self.path);fresh.load()
        self.assertIn('기술',fresh.instructions('cursor.exe','x'))
        self.assertEqual(fresh.instructions('notepad.exe','x'),'')
        fresh.set_tone('cursor.exe','original');self.assertEqual(fresh.data['tones'],{})

    def test_opt_in_bounded_history_disable_deletes(self):
        self.p.remember('raw','text','app');self.assertFalse(self.path.exists())
        self.p.set_history(True)
        for i in range(55): self.p.remember(str(i),str(i),'app')
        self.assertEqual(len(self.p.data['history']),50)
        self.assertEqual(self.p.data['history'][0]['text'],'54')
        self.p.set_history(False)
        self.assertEqual(json.loads(self.path.read_text())['history'],[])

    def test_corrupt_file_preserved(self):
        self.path.write_text('{broken')
        self.p.load();self.assertTrue(self.p.error)
        with self.assertRaises(ValueError):self.p.add_word('a','b')
        self.assertEqual(self.path.read_text(),'{broken')

    def test_failed_save_does_not_modify_memory(self):
        with patch.object(os,'replace',side_effect=PermissionError()),self.assertRaises(OSError): self.p.add_word('a','b')
        self.assertEqual(self.p.data['vocabulary'],[])

    def test_history_recovery_never_pastes_and_busy_rejected(self):
        self.p.set_history(True);self.p.remember('raw','result','app')
        state=AppState(personal=self.p)
        with patch('ipta_win.app.paste.paste_into_foreground') as paste:
            self.assertTrue(state.recover_history(self.p.data['history'][0]['id']))
            self.assertEqual(state.transcript,'result');paste.assert_not_called()
        state.phase='recording';self.assertFalse(state.recover_history(self.p.data['history'][0]['id']))

    def test_selection_commands_and_failed_edit_preserve_original(self):
        for command in ('존댓말로','절반으로 줄여','영어로 바꿔'):
            self.assertTrue(personalization.edit_instruction(command))
        self.assertIsNone(personalization.edit_instruction('영어로 바꿔 달라고 말했어요'))
        state=AppState(selected_text=selection.Selection(1,'원문','r',1,'p'))
        state.finish_selection_edit('영어로 바꿔','instruction',0)
        self.assertEqual(state.transcript,'원문')
        with patch('ipta_win.selection.capture',return_value=None),patch('ipta_win.paste.copy_text') as cp:
            self.assertFalse(selection.replace_if_unchanged(state.selected_text,'new'));cp.assert_not_called()

    def test_dictionary_survives_polish_disabled(self):
        self.p.add_word('입 타','입타'); self.p.add_word('입타','Ipta')
        state=AppState(personal=self.p)
        with patch.object(transcribe,'transcribe',return_value='입 타'),patch('ipta_win.app.paste.paste_into_foreground',return_value='mock'):
            state.finish_wav(Path('unused'),0)
        self.assertEqual(state.transcript,'입타')


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)

    def engine(self, body, **kwargs):
        script=self.root/'worker.py';script.write_text(body,encoding='utf-8')
        engine=WarmEngine(Path(sys.executable),self.root/'model',command=[sys.executable,'-u',str(script)],**kwargs)
        self.addCleanup(engine.cancel);return engine

    def test_warm_worker_reused_and_cancel_restarts(self):
        engine=self.engine('import os,sys,json\nprint(json.dumps({"ready":True}),flush=True)\nfor line in sys.stdin: print(json.dumps({"text":str(os.getpid())}),flush=True)')
        engine.prepare();one=engine.transcribe(Path('a'));two=engine.transcribe(Path('b'))
        self.assertEqual(one,two);engine.cancel();self.assertNotEqual(one,engine.transcribe(Path('c')))

    def test_idle_expiration_and_stale_timer(self):
        engine=self.engine('import os,sys,json\nprint(json.dumps({"ready":True}),flush=True)\nfor line in sys.stdin: print(json.dumps({"text":str(os.getpid())}),flush=True)',idle_timeout=.15)
        one=engine.transcribe(Path('a'));old=engine._idle_generation
        self.assertEqual(one,engine.transcribe(Path('b')));engine._expire(old)
        self.assertEqual(one,engine.transcribe(Path('c')))
        time.sleep(.25);self.assertNotEqual(one,engine.transcribe(Path('d')))

    def test_worker_timeout_and_cli_fallback(self):
        engine=self.engine('import time;time.sleep(10)',timeout=.15)
        with self.assertRaises(RuntimeError):engine.transcribe(Path('a'))
        self.assertIsNone(engine._proc)
        binary=self.root/'cli';binary.touch();model=self.root/'model';model.touch()
        with patch.object(transcribe,'_get_engine',side_effect=RuntimeError()),patch.object(transcribe,'_cli_transcribe',return_value='fallback'):
            self.assertEqual(transcribe.transcribe(Path('a'),model,binary),'fallback')

    def test_cancel_unblocks_active_inference(self):
        engine=self.engine('import sys,json,time\nprint(json.dumps({"ready":True}),flush=True)\nsys.stdin.readline();time.sleep(10)',timeout=3)
        engine.prepare();errors=[]
        def work():
            try:engine.transcribe(Path('a'))
            except RuntimeError:errors.append(True)
        thread=threading.Thread(target=work);thread.start();time.sleep(.1);engine.cancel();thread.join(1)
        self.assertFalse(thread.is_alive());self.assertEqual(errors,[True])

    def test_grok_returns_success_before_teardown_and_cleans_up(self):
        event=threading.Event()
        success=dict(type='result',subtype='success',is_error=False,stop_reason='end_turn',result='완성')
        script=self.root/'grok.py'
        script.write_text('import os,json,time\nos.write(2,b"x"*200000)\nprint('+repr(json.dumps(success))+',flush=True)\ntime.sleep(2.5)',encoding='utf-8')
        started=time.monotonic();raw=grok_stream.run([sys.executable,str(script)],timeout=3,cleanup=event.set)
        self.assertLess(time.monotonic()-started,1.8);self.assertEqual(json.loads(raw)['text'],'완성')
        self.assertTrue(event.wait(6))

    def test_grok_rejects_partial_error_truncated_and_timeout(self):
        for body in ['print("partial")','print(\'{"type":"result","subtype":"error"}\')','print(\'{"type":"result"\')','import time;time.sleep(3)']:
            with self.subTest(body=body):
                event=threading.Event()
                with self.assertRaises(oauth.CliFailure): grok_stream.run([sys.executable,'-c',body],timeout=.15,cleanup=event.set)
                self.assertTrue(event.wait(6))


if __name__=='__main__':unittest.main()
