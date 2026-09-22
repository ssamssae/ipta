"""Real Tk widget smoke on Windows CI; no recording, network or account access."""
from __future__ import annotations

import sys
import unittest
from unittest.mock import patch


@unittest.skipUnless(sys.platform == 'win32', 'Windows Tk smoke runs on Windows CI')
class OnboardingSmoke(unittest.TestCase):
    def setUp(self):
        from ipta_win import store
        from ipta_win.app import AppState
        from ipta_win.ui import IptaApp
        self.settings = {'unrelated': 'preserved'}
        self.enterContext(patch.object(store, 'load', side_effect=lambda: dict(self.settings)))
        self.save = self.enterContext(patch.object(store, 'save', side_effect=self.settings.update))
        self.state = AppState()
        self.app = IptaApp(self.state)
        self.addCleanup(lambda: self.app.root.destroy())

    def test_first_run_acknowledgment_and_reopen(self):
        from tkinter import ttk
        self.app.root.after(150, self.app.root.quit)
        self.app.root.mainloop()
        self.assertTrue(self.app.welcome.winfo_exists())
        self.app.welcome.destroy()  # Closing the window does not acknowledge it.
        self.save.assert_not_called()
        self.app.open_start_guide()
        buttons = [w for w in self.app.welcome.winfo_children() if isinstance(w, ttk.Button)]
        buttons[0].invoke()
        self.assertTrue(self.settings['windows_guide_seen'])
        self.assertEqual(self.settings['unrelated'], 'preserved')
        self.app.open_start_guide()
        self.assertTrue(self.app.welcome.winfo_exists())

    def test_acknowledged_guide_is_not_shown_on_next_launch(self):
        from ipta_win.ui import IptaApp
        self.settings['windows_guide_seen'] = True
        self.app.root.destroy()
        self.app = IptaApp(self.state)
        self.app.root.after(150, self.app.root.quit)
        self.app.root.mainloop()
        self.assertIsNone(self.app.welcome)

    def test_settings_wheel_over_child_controls_and_reopen(self):
        import tkinter as tk
        from tkinter import ttk
        for _ in range(2):
            self.app.open_settings()
            win = self.app.settings
            win.geometry('420x240')
            self.app.root.update()
            canvas = next(w for w in win.winfo_children() if isinstance(w, tk.Canvas))
            canvas.yview_moveto(0)
            self.app.settings_phase.event_generate('<MouseWheel>', delta=-120)
            self.app.root.update()
            self.assertGreater(canvas.yview()[0], 0)
            # Recreated provider controls are tagged as well.
            self.app._refresh_now()
            self.app.root.update()
            child = self.app.provider_frame.winfo_children()[0]
            self.assertTrue(any(tag.startswith('IptaWheel') for tag in child.bindtags()))
            canvas.yview_moveto(0)
            for _ in range(4):
                child.event_generate('<MouseWheel>', delta=-30)
            self.app.root.update()
            self.assertGreater(canvas.yview()[0], 0)
            self.assertFalse(any(tag.startswith('IptaWheel') for tag in self.app.toggle_btn.bindtags()))
            win.destroy()
            self.app.root.update()

    def test_progress_retry_and_ready_controls(self):
        self.state.phase = 'downloading'
        self.state.download_progress = 0.5
        self.app._refresh_now()
        self.assertEqual(float(self.app.model_progress['value']), 0.5)
        self.assertTrue(self.app.model_btn.instate(['disabled']))
        self.assertTrue(self.app.toggle_btn.instate(['disabled']))
        self.state.phase = 'error'
        self.state.download_failed = True
        self.app._refresh_now()
        self.assertEqual(self.app.model_btn['text'], '다시 받기')
        self.assertFalse(self.app.model_btn.instate(['disabled']))
        self.state.phase = 'idle'
        self.state.model_ready = True
        self.app._refresh_now()
        self.assertEqual(self.app.model_box.winfo_manager(), '')
        self.assertFalse(self.app.toggle_btn.instate(['disabled']))
        self.state.model_ready = False
        self.app._refresh_now()
        self.assertEqual(self.app.model_box.winfo_manager(), 'pack')


if __name__ == '__main__':
    unittest.main()
