"""
Wayland-native clipboard + keystroke injection for WritingTools.

Why this exists: on KDE Plasma Wayland the original pynput+pyperclip flow breaks
for two independent reasons:

1. pyperclip shells out to `wl-copy` and blocks. wl-copy forks a background
   server to serve the selection and does not exit promptly, so
   subprocess.run(capture_output=True) hangs/times out. That breaks the
   clipboard clear (capture) and the clipboard write (paste-back): the app
   reads stale clipboard content and never lands the AI text where it
   should — it only surfaces as a secondary Klipper entry.

2. pynput's Linux backend is X11/XTest. On a Wayland session it only reaches
   XWayland windows; native Wayland apps never get the synthetic Ctrl+C/V.
   Even XWayland injection is unreliable under KWin.

This module provides a Wayland path used only when a Wayland session AND the
required tools (wl-clipboard, ydotool + ydotoold) are present. Windows and
X11 callers keep the original pyperclip + pynput path untouched.

Clipboard operations use wl-clipboard with a fork-and-detach pattern (no
capture_output that waits on the long-lived server). Keystroke injection uses
ydotool, which emits at the kernel uinput layer (verified: a "ydotoold virtual
device" with a kbd handler) and so reaches both native Wayland and XWayland
windows. Requires the ydotoold daemon running and the user in the `input`
group (for /dev/uinput access).
"""

import logging
import os
import shutil
import subprocess

# linux/input-event-codes.h raw keycodes (ydotool format "<code>:<pressed>").
# KEY_LEFTCTRL=29, KEY_C=46, KEY_V=47. Each token MUST be a separate argv
# element: ydotool 1.0.4 silently emits nothing when keycodes are passed as a
# single space-joined string argument.
_CTRL_C = ["29:1", "46:1", "46:0", "29:0"]
_CTRL_V = ["29:1", "47:1", "47:0", "29:0"]

_detection = None


def is_wayland_active():
    """True once per process if under Wayland with wl-clipboard AND ydotool.

    Cached so repeated calls are cheap. Returns False on Windows/X11 or if
    tools are missing, so callers fall back to the original path.
    """
    global _detection
    if _detection is not None:
        return _detection

    if os.environ.get(
        "XDG_SESSION_TYPE", ""
    ).lower() != "wayland" and not os.environ.get("WAYLAND_DISPLAY", ""):
        _detection = False
        return False

    have_wl = shutil.which("wl-copy") and shutil.which("wl-paste")
    have_yd = shutil.which("ydotool")
    if not (have_wl and have_yd):
        logging.warning(
            "Wayland session detected but native tools missing "
            f"(wl-clipboard={'yes' if have_wl else 'no'}, "
            f"ydotool={'yes' if have_yd else 'no'}); falling back to pynput/pyperclip. "
            "Install wl-clipboard and ydotool (and run ydotoold) for Wayland support."
        )
        _detection = False
        return False

    logging.info("Wayland native IO path active (wl-clipboard + ydotool)")
    _detection = True
    return True


def paste_text():
    """Read the Wayland clipboard as text. Returns '' on empty/error."""
    try:
        out = subprocess.run(
            ["wl-paste", "--no-newline"],
            capture_output=True,
            text=True,
            timeout=2.0,
            check=False,
        )
        if out.returncode != 0:
            # Empty clipboard prints "Nothing is copied" to stderr, exits 1.
            return ""
        return out.stdout
    except Exception as e:
        logging.error(f"wl-paste failed: {e}")
        return ""


def copy_text(text):
    """Write text to the Wayland clipboard (replaces contents).

    wl-copy forks a background server to serve the selection and does not
    exit promptly; we feed it via stdin and detach (DEVNULL + close_fds) so
    this returns immediately instead of hanging on the server's pipes.
    """
    try:
        subprocess.Popen(
            ["wl-copy"],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        ).communicate(input=text.encode("utf-8"), timeout=2.0)
    except Exception as e:
        logging.error(f"wl-copy failed: {e}")


def clear_clipboard():
    """Clear the Wayland clipboard. Forks and detaches like copy_text."""
    try:
        subprocess.Popen(
            ["wl-copy", "--clear"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
    except Exception as e:
        logging.error(f"wl-copy --clear failed: {e}")


def inject_ctrl_c():
    """Synthesize Ctrl+C at the uinput layer via ydotool."""
    try:
        subprocess.run(
            ["ydotool", "key", *_CTRL_C],
            capture_output=True,
            timeout=2.0,
            check=False,
        )
    except Exception as e:
        logging.error(f"ydotool Ctrl+C failed: {e}")


def inject_ctrl_v():
    """Synthesize Ctrl+V at the uinput layer via ydotool."""
    try:
        subprocess.run(
            ["ydotool", "key", *_CTRL_V],
            capture_output=True,
            timeout=2.0,
            check=False,
        )
    except Exception as e:
        logging.error(f"ydotool Ctrl+V failed: {e}")
