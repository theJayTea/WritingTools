"""
Native Wayland support for Writing Tools on Linux.

pynput and pyperclip were written for X11: under a Wayland compositor pynput
only sees XWayland windows, so the global hotkey never fires while a native
Wayland app has focus, and synthetic Ctrl+C / Ctrl+V never reach it either.

This package replaces those two pieces when the session is Wayland:

* hotkeys.py         - convert the user's hotkey strings to the XDG shortcut format
* portal_shortcuts.py - global shortcuts through org.freedesktop.portal.GlobalShortcuts
* text_io.py         - capture the selection and paste results with wl-clipboard + ydotool
* trigger_socket.py  - `main.py --trigger` for compositors without the portal
* desktop_entry.py   - the .desktop file the portal needs to identify the app

Nothing here is imported on Windows, macOS or X11 sessions.

Environment variables:
  WRITING_TOOLS_FORCE_X11=1        use the original pynput path (XWayland only)
  WRITING_TOOLS_DISABLE_PORTAL=1   don't register portal shortcuts; bind
                                   `main.py --trigger` in the desktop instead
  WRITING_TOOLS_KEY_INJECTOR=...   ydotool, wtype, or an executable that gets
                                   "copy" or "paste" as its argument
"""

import os
import sys

APP_ID = "io.github.thejaytea.WritingTools"


def is_wayland_session():
    """True when running under a Wayland compositor on Linux.

    WRITING_TOOLS_FORCE_X11=1 keeps the original pynput path, e.g. for users
    who run the app under XWayland on purpose.
    """
    if not sys.platform.startswith("linux"):
        return False
    if os.environ.get("WRITING_TOOLS_FORCE_X11"):
        return False
    if os.environ.get("XDG_SESSION_TYPE", "").lower() == "wayland":
        return True
    return bool(os.environ.get("WAYLAND_DISPLAY"))
