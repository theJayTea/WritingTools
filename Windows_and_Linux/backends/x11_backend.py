from .gui_backend import GUIBackend
import pyperclip
import time
from pynput import keyboard as pykeyboard
from Xlib import display, X


class X11Backend(GUIBackend):
    def get_active_window_title(self) -> str:
        dsp = display.Display()
        root = dsp.screen().root
        atom = dsp.intern_atom("_NET_ACTIVE_WINDOW")
        win_id = root.get_full_property(atom, X.AnyPropertyType).value[0]
        win = dsp.create_resource_object("window", win_id)
        return win.get_wm_name()

    def get_selected_text(self) -> str:
        """Simulate Ctrl+C and return selected text on X11."""
        backup = pyperclip.paste()
        pyperclip.copy("")
        kb = pykeyboard.Controller()
        kb.press(pykeyboard.Key.ctrl.value)
        kb.press("c")
        kb.release("c")
        kb.release(pykeyboard.Key.ctrl.value)
        time.sleep(0.2)
        text = pyperclip.paste()
        pyperclip.copy(backup)
        return text
