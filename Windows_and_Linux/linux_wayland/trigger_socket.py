"""
`python main.py --trigger [action]` for desktops without the shortcuts portal.

Older GNOME releases, Sway, and other wlroots compositors have no
GlobalShortcuts portal, but all of them let the user bind a key to a command
in their own settings. The running app listens on a Unix socket in
$XDG_RUNTIME_DIR; the --trigger command sends it one line naming the action
("popup" for the main window, or a button name for a direct hotkey) and
exits.
"""

import logging
import os
import socket
import threading

SOCKET_NAME = "writing-tools.sock"
MAX_MESSAGE = 256


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise OSError("XDG_RUNTIME_DIR is not set")
    return os.path.join(runtime, SOCKET_NAME)


def send_trigger(action="popup"):
    """Ask a running instance to perform `action`. Returns True on success."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(socket_path())
            s.sendall(action.encode("utf-8")[:MAX_MESSAGE] + b"\n")
            return s.recv(16).startswith(b"ok")
    except OSError as e:
        logging.error(f"Writing Tools is not running or not reachable: {e}")
        return False


class TriggerServer:
    """Accepts trigger messages and hands each action name to a callback."""

    def __init__(self, on_trigger):
        self.on_trigger = on_trigger
        self._sock = None
        self._thread = None

    def start(self):
        path = socket_path()
        # A socket left behind by a crashed instance blocks bind(); only
        # remove it once we know nothing is answering on it.
        if os.path.exists(path):
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
                    probe.settimeout(0.5)
                    probe.connect(path)
                raise OSError(f"another Writing Tools instance is listening on {path}")
            except (ConnectionRefusedError, FileNotFoundError):
                os.unlink(path)
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        old_umask = os.umask(0o177)  # owner-only socket
        try:
            self._sock.bind(path)
        finally:
            os.umask(old_umask)
        self._sock.listen(4)
        # accept() isn't woken by close() from another thread, so poll.
        self._sock.settimeout(0.5)
        self._stopping = threading.Event()
        self._thread = threading.Thread(target=self._serve, name="trigger-socket", daemon=True)
        self._thread.start()
        logging.info(f"Trigger socket listening on {path}")

    def stop(self):
        if self._sock is None:
            return
        self._stopping.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
        try:
            self._sock.close()
        finally:
            self._sock = None
            try:
                os.unlink(socket_path())
            except OSError:
                pass

    def _serve(self):
        sock = self._sock
        while not self._stopping.is_set():
            try:
                conn, _ = sock.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with conn:
                conn.settimeout(2)
                try:
                    data = conn.recv(MAX_MESSAGE + 1).decode("utf-8", errors="replace")
                    action = data.strip()
                    if not action:
                        # A liveness probe from a second instance (see start())
                        # connects and closes without sending anything.
                        continue
                    self.on_trigger(action)
                    conn.sendall(b"ok\n")
                except Exception as e:  # noqa: BLE001 - one bad client must not stop the server
                    logging.warning(f"Bad trigger message: {e}")
