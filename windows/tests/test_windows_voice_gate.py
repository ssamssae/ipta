from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ipta_win import transcribe


class VoiceGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.binary = self.root / 'whisper-cli.exe'
        self.model = self.root / 'speech-model.bin'
        self.binary.touch(); self.model.touch()

    def test_missing_voice_detector_never_falls_back_to_unguarded_inference(self):
        with patch.object(transcribe, '_get_engine', side_effect=RuntimeError('worker failed')), patch.object(transcribe.subprocess, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, '말소리 확인'):
                transcribe.transcribe(self.root / 'silent.wav', self.model, self.binary)
        run.assert_not_called()

    def test_cli_fallback_has_voice_gate_and_empty_result_overrides_stdout(self):
        self.binary.with_name(transcribe.VAD_MODEL_NAME).touch()
        paths = []
        def invoke(args, **kwargs):
            self.assertIn('--vad', args)
            self.assertEqual(args[args.index('--vad-min-speech-duration-ms') + 1], '100')
            base = Path(args[args.index('-of') + 1]); paths.append(base)
            Path(str(base) + '.txt').write_text('')
            return SimpleNamespace(returncode=0, stdout=b'not a transcript', stderr=b'')
        with patch.object(transcribe.subprocess, 'run', side_effect=invoke):
            for _ in range(2):
                self.assertEqual(transcribe._cli_transcribe(self.root/'silent.wav', self.model, self.binary), '')
        self.assertNotEqual(paths[0], paths[1])
        self.assertTrue(all(not path.parent.exists() for path in paths))


if __name__ == '__main__':
    unittest.main()
