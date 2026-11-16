"""
The desktop entry that identifies Writing Tools to the XDG portal.

Portals map an app id to a .desktop file of the same name. KDE uses it for
the app's name in the shortcut confirmation dialog and in System Settings,
and some portal versions refuse to register an id that has no desktop entry.
Packaged installs ship the file themselves; running from source or from a
PyInstaller build does not, so we write a user-level copy on first run.
"""

import logging
import os
import sys

from . import APP_ID

ENTRY_TEMPLATE = """[Desktop Entry]
Type=Application
Name=Writing Tools
Comment=Fix, rewrite and summarise selected text in any app
Exec={exec_line}
Icon={icon}
Terminal=false
Categories=Utility;TextTools;
StartupNotify=false
X-Writing-Tools-Generated=true
"""


def _applications_dir():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data_home, "applications")


def _quote(arg):
    """Quote an Exec argument as the desktop entry spec requires."""
    if not any(c in arg for c in ' \t\n"\'\\><~|&;$*?#()`'):
        return arg
    escaped = arg.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`").replace("$", "\\$")
    return f'"{escaped}"'


def _exec_line(base_dir):
    if getattr(sys, "frozen", False):
        return _quote(sys.executable)
    main_py = os.path.join(base_dir, "main.py")
    return f"{_quote(sys.executable)} {_quote(main_py)}"


def ensure_desktop_entry(base_dir):
    """
    Make sure ~/.local/share/applications/<APP_ID>.desktop exists.

    An entry we generated earlier is rewritten when the interpreter or
    install location changed; a hand-made or packaged entry is never touched.
    Returns the path of the entry, or None if it couldn't be written.
    """
    path = os.path.join(_applications_dir(), f"{APP_ID}.desktop")
    content = ENTRY_TEMPLATE.format(
        exec_line=_exec_line(base_dir),
        icon=os.path.join(base_dir, "icons", "app_icon.png"),
    )
    try:
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                current = f.read()
            if "X-Writing-Tools-Generated=true" not in current or current == content:
                return path
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = f"{path}.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, path)
        logging.info(f"Wrote desktop entry {path}")
        return path
    except OSError as e:
        logging.warning(f"Could not write desktop entry {path}: {e}")
        return None
