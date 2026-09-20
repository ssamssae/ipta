import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ipta_win import oauth

class WorkspaceTests(unittest.TestCase):
    def test_cursor_trust_is_limited_to_fresh_empty_workspace(self):
        observed = []
        def run(argv, **kwargs):
            folder = Path(kwargs['cwd'])
            self.assertTrue(folder.is_dir())
            self.assertEqual(list(folder.iterdir()), [])
            self.assertEqual(argv[argv.index('--workspace') + 1], str(folder))
            self.assertIn('--trust', argv)
            self.assertNotIn('--force', argv)
            self.assertNotIn('--yolo', argv)
            self.assertEqual(argv[argv.index('--mode') + 1], 'ask')
            observed.append(folder)
            return '안녕하세요'
        with patch.object(oauth, 'run_cli', side_effect=run):
            text = oauth.polish_cursor(['agent', '-p', '--mode', 'ask', '안녕'], Path('/agent'))
        self.assertEqual(text, '안녕하세요')
        self.assertFalse(observed[0].exists())

    def test_wsl_trust_uses_generated_directory_and_quotes_input(self):
        prompt = "한글 & $(echo do-not-execute) '"
        with patch.object(oauth, 'wsl_exe', return_value='wsl.exe'), patch.object(oauth, 'run_cli', return_value='한글') as run:
            oauth.polish_cursor(['agent', '-p', '--mode', 'ask', prompt], None)
        command = run.call_args.args[0][-1]
        self.assertIn('mktemp -d /tmp/ipta-cursor.', command)
        self.assertIn('--workspace "$ipta_cursor_dir" --trust', command)
        self.assertIn(oauth.shlex.quote(prompt), command)
        self.assertNotIn('--workspace /tmp ', command)
        self.assertNotIn('--yolo', command)

    def test_windows_codex_uses_exe_not_shell_shim(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            exe = root/'npm/node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe'
            exe.parent.mkdir(parents=True)
            exe.write_bytes(b'MZ')
            with patch.dict(os.environ, {'APPDATA':str(root)}), patch.object(oauth.sys,'platform','win32'), patch.object(oauth, 'wsl_command_exists', return_value=False):
                self.assertEqual(oauth.binary('openai'),exe)

    def test_wsl_account_wins_over_native_installation(self):
        with patch.object(oauth.sys, 'platform', 'win32'), patch.object(oauth, 'wsl_command_exists', return_value=True):
            for provider in ('openai', 'cursor', 'grok'):
                self.assertIsNone(oauth.binary(provider))

    def test_codex_status_is_checked_inside_wsl(self):
        with patch.object(oauth, 'binary', return_value=None), patch.object(oauth, 'wsl_command_exists', return_value=True), patch.object(oauth, 'wsl_run', return_value='Logged in using ChatGPT') as call:
            self.assertTrue(oauth.probe('openai').ready)
            call.assert_called_once_with('codex', ['login', 'status'], timeout=8)

if __name__ == '__main__': unittest.main()
