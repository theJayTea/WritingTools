"""
Selection capture and paste-back on Wayland.

Wayland gives no client access to other windows' selections or keyboard, so
like every tool in this space we go through the clipboard:

  capture: put a unique sentinel on the clipboard, send Ctrl+C to the focused
           app, and wait until the clipboard holds something else.
  paste:   put the result on the clipboard, send Ctrl+V, then restore what
           the user had on the clipboard before.

Why a sentinel rather than "clear the clipboard and wait until it is
non-empty" (what the X11/Windows path does): clipboard managers such as
KDE's Klipper refill an emptied clipboard from their history straight away,
so the old approach reads stale history instead of the selection. The
sentinel is offered with `wl-copy --sensitive`, which tells clipboard
managers to keep it out of their history.

Clipboard access uses wl-clipboard (wl-copy / wl-paste). Key presses go
through ydotool (any compositor, needs the ydotoold daemon) or wtype
(wlroots compositors such as Sway and Hyprland). Set
WRITING_TOOLS_KEY_INJECTOR to "ydotool", "wtype", or the path of an
executable that receives "copy" or "paste" as its only argument.
"""

import logging
import os
import secrets
import shutil
import subprocess
import tempfile
import time

# Linux input event codes (linux/input-event-codes.h).
KEY_LEFTCTRL = 29
KEY_C = 46
KEY_V = 47

CLIPBOARD_TIMEOUT = 2.0  # seconds for one wl-paste/wl-copy call

# Gap between synthetic key events. Sent back to back, Ctrl+C often reaches a
# toolkit before it has applied the Ctrl modifier, so the app sees a plain "c"
# (or nothing). Measured in a nested KWin with a Qt text field: 2 of 12
# captures succeeded with no gap, 12 of 12 with a 12 ms gap.
KEY_DELAY_MS = 12

# Apps answer Ctrl+C quickly: in a nested KWin, a Qt text field, Chrome, Zen
# (Firefox), VS Code and Kate all filled the clipboard within 140 ms of the key
# press, 65 ms typically. Waiting longer only delays the popup when nothing is
# selected, which is when the full timeout is spent.
COPY_RETRY_AFTER = 0.25  # clipboard unchanged this long after Ctrl+C: press it again
CAPTURE_TIMEOUT = 0.8    # then give up: nothing is selected
POLL_INTERVAL = 0.015


class TextIOError(Exception):
    """Raised when a required tool is missing or misconfigured."""


# -- clipboard -------------------------------------------------------------


def read_clipboard():
    """Return the clipboard text, or None when it is empty or not text."""
    try:
        result = subprocess.run(
            ["wl-paste", "--no-newline", "--type", "text"],
            capture_output=True, timeout=CLIPBOARD_TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        logging.warning(f"wl-paste failed: {e}")
        return None
    if result.returncode != 0:
        # "Nothing is copied" or no text offer: both mean there is no text.
        return None
    return result.stdout.decode("utf-8", errors="replace")


def write_clipboard(text, sensitive=False):
    """Put `text` on the clipboard."""
    _wl_copy(["--type", "text/plain;charset=utf-8"], text.encode("utf-8"), sensitive)


def _wl_copy(args, data, sensitive=False):
    """
    Run wl-copy. It forks a background process that serves the selection
    until something else replaces it, so this returns as soon as the offer
    is up. stdout/stderr must not be pipes we wait on: the forked server
    inherits them and would keep the call from returning.
    """
    cmd = ["wl-copy", *args]
    if sensitive:
        cmd.append("--sensitive")
    try:
        subprocess.run(
            cmd, input=data, timeout=CLIPBOARD_TIMEOUT,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True,
        )
    except (OSError, subprocess.SubprocessError) as e:
        raise TextIOError(f"wl-copy failed: {e}") from e


# Clipboard managers (KDE Klipper, and others via the same convention) keep
# entries offered with this type out of their history.
PASSWORD_HINT = "x-kde-passwordManagerHint"
MAX_SNAPSHOT_BYTES = 64 * 1024 * 1024


class ClipboardSnapshot:
    """What the clipboard held before we used it. mime=None means empty."""

    def __init__(self, mime=None, data=b"", sensitive=False):
        self.mime = mime
        self.data = data
        self.sensitive = sensitive


def _pick_mime(offered):
    for prefix in ("text/plain;charset=utf-8", "text/plain", "image/png", "image/"):
        for mime in offered:
            if mime.startswith(prefix):
                return mime
    return offered[0]


def snapshot_clipboard():
    """
    Save the clipboard so it can be put back later: text, images and other
    single-type content, an empty clipboard, and the password-manager hint.
    Returns None when the clipboard can't be read at all; then nothing will
    be restored rather than restoring something wrong.
    """
    try:
        listed = subprocess.run(
            ["wl-paste", "--list-types"], capture_output=True, timeout=CLIPBOARD_TIMEOUT
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        logging.warning(f"wl-paste failed: {e}")
        return None
    if listed.returncode != 0:
        return ClipboardSnapshot()  # "Nothing is copied"
    offered = [t for t in listed.stdout.decode("utf-8", errors="replace").splitlines()
               if t and t != PASSWORD_HINT]
    sensitive = PASSWORD_HINT in listed.stdout.decode("utf-8", errors="replace")
    if not offered:
        return ClipboardSnapshot()
    mime = _pick_mime(offered)
    try:
        content = subprocess.run(
            ["wl-paste", "--no-newline", "--type", mime],
            capture_output=True, timeout=CLIPBOARD_TIMEOUT,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        logging.warning(f"wl-paste failed: {e}")
        return None
    if content.returncode != 0 or len(content.stdout) > MAX_SNAPSHOT_BYTES:
        return None
    return ClipboardSnapshot(mime, content.stdout, sensitive)


def restore_clipboard(snapshot):
    """Put a snapshot back. A None snapshot (unreadable) is left alone."""
    if snapshot is None:
        return
    if snapshot.mime is None:
        try:
            subprocess.run(["wl-copy", "--clear"], timeout=CLIPBOARD_TIMEOUT,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError) as e:
            raise TextIOError(f"wl-copy --clear failed: {e}") from e
        return
    _wl_copy(["--type", snapshot.mime], snapshot.data, snapshot.sensitive)


# -- key injection -----------------------------------------------------------


def _ydotool_socket():
    """Locate the ydotoold socket the same way the ydotool client does."""
    explicit = os.environ.get("YDOTOOL_SOCKET")
    if explicit:
        return explicit
    candidates = []
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        candidates.append(os.path.join(runtime, ".ydotool_socket"))
    candidates.append("/tmp/.ydotool_socket")
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


class KeyInjector:
    """Sends copy/paste shortcuts to whichever window has keyboard focus."""

    def __init__(self, choice=None):
        choice = choice or os.environ.get("WRITING_TOOLS_KEY_INJECTOR", "")
        self.kind, self.command = self._resolve(choice.strip())
        logging.info(f"Wayland key injector: {self.kind}")

    @staticmethod
    def _resolve(choice):
        if choice and choice not in ("ydotool", "wtype"):
            if not (os.path.isfile(choice) and os.access(choice, os.X_OK)):
                raise TextIOError(f"WRITING_TOOLS_KEY_INJECTOR '{choice}' is not an executable file")
            return "custom", choice
        if choice in ("", "ydotool") and shutil.which("ydotool") and _ydotool_socket():
            return "ydotool", "ydotool"
        if choice in ("", "wtype") and shutil.which("wtype"):
            return "wtype", "wtype"
        raise TextIOError(
            "No way to send key presses on Wayland. Install ydotool and start "
            "the ydotoold service (works on every compositor), or install wtype "
            "(Sway, Hyprland and other wlroots compositors)."
        )

    def _run(self, args, env=None):
        # stderr goes to a file, not a pipe: a custom injector may start
        # wl-copy, whose background server would hold a pipe open forever.
        with tempfile.TemporaryFile() as err:
            result = subprocess.run(
                args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=err, timeout=5, env=env,
            )
            if result.returncode != 0:
                err.seek(0)
                message = err.read().decode("utf-8", errors="replace").strip()
                raise TextIOError(f"{args[0]} failed ({result.returncode}): {message}")

    def _ctrl(self, key_code, letter, action):
        if self.kind == "custom":
            self._run([self.command, action])
        elif self.kind == "ydotool":
            env = dict(os.environ, YDOTOOL_SOCKET=_ydotool_socket() or "")
            self._run(
                ["ydotool", "key", "--key-delay", str(KEY_DELAY_MS),
                 f"{KEY_LEFTCTRL}:1", f"{key_code}:1", f"{key_code}:0", f"{KEY_LEFTCTRL}:0"],
                env=env,
            )
        else:
            gap = str(KEY_DELAY_MS)
            self._run(["wtype", "-M", "ctrl", "-s", gap, "-k", letter, "-s", gap, "-m", "ctrl"])

    def copy(self):
        self._ctrl(KEY_C, "c", "copy")

    def paste(self):
        self._ctrl(KEY_V, "v", "paste")


# -- high level --------------------------------------------------------------


class WaylandTextIO:
    """Capture the current selection and paste replacement text."""

    def __init__(self, injector=None):
        self.injector = injector or KeyInjector()
        missing = [tool for tool in ("wl-copy", "wl-paste") if not shutil.which(tool)]
        if missing:
            raise TextIOError(
                f"Missing {', '.join(missing)}. Install the wl-clipboard package."
            )

    def capture_selection(self, timeout=CAPTURE_TIMEOUT, before_copy=None):
        """
        Return the text selected in the focused app, or '' if nothing was
        copied within `timeout` seconds. The user's clipboard is restored.

        before_copy, if given, runs once the clipboard is prepared, right
        before Ctrl+C is sent (the caller waits there for the hotkey to be
        released, so the preparation overlaps with that). If it raises, no
        key is sent and the exception propagates.
        """
        backup = snapshot_clipboard()
        sentinel = f"writing-tools-capture-{secrets.token_hex(8)}"
        captured = None
        try:
            write_clipboard(sentinel, sensitive=True)
            if before_copy is not None:
                before_copy()
            self.injector.copy()
            start = time.monotonic()
            retried = False
            current = None
            while time.monotonic() - start < timeout:
                time.sleep(POLL_INTERVAL)
                current = read_clipboard()
                if current is not None and current != sentinel:
                    captured = current
                    return current
                if not retried and time.monotonic() - start >= COPY_RETRY_AFTER:
                    # A dropped key event is far more likely than an app
                    # needing longer than this to copy. Copying twice is
                    # harmless, so press Ctrl+C once more.
                    retried = True
                    logging.debug("Clipboard unchanged after Ctrl+C; pressing it again")
                    self.injector.copy()
            state = "still the sentinel" if current == sentinel else "empty"
            logging.info(f"Nothing was copied (clipboard {state}); is any text selected?")
            return ""
        finally:
            self._restore(backup, expected=(sentinel, captured))

    def paste_text(self, text, settle=0.5):
        """
        Replace the selection in the focused app with `text`, then restore
        the previous clipboard after `settle` seconds. Apps fetch pasted data
        asynchronously, so restoring too early can paste the old content.
        """
        backup = snapshot_clipboard()
        write_clipboard(text)
        try:
            self.injector.paste()
        finally:
            time.sleep(settle)
            self._restore(backup, expected=(text,))

    @staticmethod
    def _restore(backup, expected):
        """
        Restore `backup` unless the clipboard changed under us: if it holds
        something other than what we (or the copied selection) put there, the
        user copied something new in the meantime and that wins.
        """
        current = read_clipboard()
        if current is not None and current not in expected:
            logging.debug("Clipboard changed during the operation; not restoring")
            return
        try:
            restore_clipboard(backup)
        except TextIOError as e:
            logging.warning(f"Could not restore the clipboard: {e}")
