from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import Mock, patch

from ipta_win import info, models
from ipta_win.app import AppState


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.target = Path(self.tmp.name) / 'Models' / 'model.bin'
        self.payload = b'model fixture' * 12000
        self.enterContext(patch.object(info, 'MODEL_BYTES', len(self.payload)))
        self.enterContext(patch.object(info, 'MODEL_SHA256', hashlib.sha256(self.payload).hexdigest()))

    def download(self, payload=None, **kwargs):
        opener = Mock(return_value=io.BytesIO(self.payload if payload is None else payload))
        return models.download(self.target, opener=opener, **kwargs)

    def test_progress_and_atomic_verified_install(self):
        progress = Mock()
        self.assertIsNone(self.download(on_progress=progress))
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertEqual(progress.call_args.args, (len(self.payload), len(self.payload)))
        self.assertFalse(self.target.with_suffix('.part').exists())

    def test_existing_verified_model_needs_no_network(self):
        self.assertIsNone(self.download())
        opener = Mock(side_effect=AssertionError('must stay offline'))
        self.assertIsNone(models.download(self.target, opener=opener))
        opener.assert_not_called()

    def test_offline_error_does_not_expose_connection_details(self):
        opener = Mock(side_effect=urllib.error.URLError('private-host/?secret=redacted'))
        err = models.download(self.target, opener=opener)
        self.assertIn('오프라인', err)
        self.assertNotIn('private-host', err)
        self.assertFalse(self.target.exists())

    def test_truncated_download_can_be_retried(self):
        self.assertIn('다시 받기', self.download(b'short'))
        self.assertFalse(self.target.with_suffix('.part').exists())
        self.assertIsNone(self.download())

    def test_corruption_keeps_old_target(self):
        self.target.parent.mkdir()
        self.target.write_bytes(b'old model')
        self.assertIn('손상', self.download(b'x' * len(self.payload)))
        self.assertEqual(self.target.read_bytes(), b'old model')
        self.assertFalse(self.target.with_suffix('.part').exists())

    def test_oversized_stream_rejected(self):
        self.assertIn('크기', self.download(self.payload + b'extra'))
        self.assertFalse(self.target.exists())
        self.assertFalse(self.target.with_suffix('.part').exists())

    def test_timeout_cleans_partial_file(self):
        stream = Mock()
        stream.__enter__ = Mock(return_value=stream)
        stream.__exit__ = Mock(return_value=False)
        stream.read.side_effect = [b'partial', TimeoutError()]
        err = models.download(self.target, opener=Mock(return_value=stream))
        self.assertIn('다시 받기', err)
        self.assertFalse(self.target.with_suffix('.part').exists())

    def test_directory_permission_failure_is_retryable(self):
        with patch.object(Path, 'mkdir', side_effect=PermissionError()):
            self.assertIn('폴더 권한', self.download())

    def test_default_path_creation_failure_is_retryable(self):
        with patch.object(info, 'model_path', side_effect=PermissionError()):
            self.assertIn('폴더 권한', models.download())
            self.assertFalse(models.size_looks_ready())

    def test_replace_failure_keeps_target_and_cleans_partial(self):
        self.target.parent.mkdir()
        self.target.write_bytes(b'old')
        with patch.object(Path, 'replace', side_effect=PermissionError()):
            self.assertIn('폴더 권한', self.download())
        self.assertEqual(self.target.read_bytes(), b'old')
        self.assertFalse(self.target.with_suffix('.part').exists())

    def test_untrusted_url_is_not_opened(self):
        opener = Mock()
        self.assertIsNotNone(models.download(self.target, url='http://example.com/model', opener=opener))
        opener.assert_not_called()


class DownloadStateTests(unittest.TestCase):
    def test_duplicate_download_and_cancel_do_not_unlock_worker(self):
        state = AppState()
        with patch('ipta_win.app.threading.Thread') as thread:
            state.download_model()
            state.cancel()
            state.download_model()
            self.assertEqual(state.phase, 'downloading')
            self.assertEqual(thread.call_count, 1)

    def test_recording_cannot_start_model_worker(self):
        for phase in ('recording', 'transcribing', 'polishing'):
            with self.subTest(phase=phase), patch('ipta_win.app.threading.Thread') as thread:
                AppState(phase=phase).download_model()
                thread.assert_not_called()

    def test_failure_retry_resets_errors_and_finishes(self):
        state = AppState(download_progress=0.8, last_error='old')
        with patch('ipta_win.app.threading.Thread') as thread:
            state.download_model()
            self.assertEqual(state.download_progress, 0)
            self.assertEqual(state.last_error, '')
            with patch.object(models, 'download', return_value='오프라인'):
                thread.call_args.kwargs['target']()
            self.assertTrue(state.download_failed)
            self.assertEqual(state.phase, 'error')
            self.assertFalse(state.model_ready)
            state.download_model()
            self.assertFalse(state.download_failed)
            def complete(on_progress):
                on_progress(10, 10)
                self.assertIn('무결성', state.status_line)
            with patch.object(models, 'download', side_effect=complete):
                thread.call_args.kwargs['target']()
            self.assertTrue(state.model_ready)
            self.assertEqual(state.phase, 'idle')
            self.assertEqual(state.download_progress, 1)
            self.assertEqual(state.last_error, '')


if __name__ == '__main__':
    unittest.main()
