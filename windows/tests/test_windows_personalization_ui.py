import sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch

@unittest.skipUnless(sys.platform=='win32','Windows Tk smoke')
class PersonalizationUI(unittest.TestCase):
    def test_tabs_show_and_history_is_opt_in(self):
        import tkinter as tk
        from tkinter import ttk
        from ipta_win.app import AppState
        from ipta_win.personalization import Personalization
        from ipta_win.personalization_ui import open_window
        with tempfile.TemporaryDirectory() as tmp:
            state=AppState(personal=Personalization(Path(tmp)/'personalization.json'))
            root=tk.Tk()
            try:
                win=open_window(root,state);root.update()
                book=next(w for w in win.winfo_children() if isinstance(w,ttk.Notebook))
                self.assertEqual(len(book.tabs()),3)
                self.assertFalse(state.personal.data['history_enabled'])
                for tab in book.tabs(): book.select(tab);root.update()
                self.assertTrue(win.winfo_exists())
            finally:root.destroy()

if __name__=='__main__':unittest.main()
