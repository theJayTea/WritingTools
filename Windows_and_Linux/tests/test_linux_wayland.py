"""
Tests for the Wayland helpers that don't need a running desktop.

Run from Windows_and_Linux/:  python -m unittest discover -s tests
"""

import os
import shutil
import subprocess
import tempfile
import threading
import time
import types
import unittest
from unittest import mock

from linux_wayland import desktop_entry, is_wayland_session, text_io, trigger_socket
from linux_wayland.hotkeys import to_portal_trigger
from linux_wayland import integration
from linux_wayland.integration import button_shortcut_id


class HotkeyConversionTests(unittest.TestCase):
    def test_default_hotkey(self):
        self.assertEqual(to_portal_trigger("ctrl+space"), "CTRL+space")

    def test_modifier_order_is_normalised(self):
        self.assertEqual(to_portal_trigger("shift+ctrl+p"), "CTRL+SHIFT+p")
        self.assertEqual(to_portal_trigger("Alt+Ctrl+J"), "CTRL+ALT+j")

    def test_super_aliases(self):
        for name in ("super", "win", "meta", "cmd"):
            self.assertEqual(to_portal_trigger(f"{name}+w"), "LOGO+w")

    def test_named_and_function_keys(self):
        self.assertEqual(to_portal_trigger("ctrl+alt+enter"), "CTRL+ALT+Return")
        self.assertEqual(to_portal_trigger("ctrl+f12"), "CTRL+F12")
        self.assertEqual(to_portal_trigger("ctrl+page_down"), "CTRL+Next")

    def test_punctuation(self):
        self.assertEqual(to_portal_trigger("ctrl+."), "CTRL+period")
        self.assertEqual(to_portal_trigger("ctrl+shift+/"), "CTRL+SHIFT+slash")

    def test_whitespace_is_ignored(self):
        self.assertEqual(to_portal_trigger("  ctrl + space "), "CTRL+space")

    def test_invalid_hotkeys(self):
        for bad in ("", "  ", "ctrl", "ctrl+shift", "ctrl+a+b", "ctrl+ctrl+a",
                    "ctrl++", "ctrl+banana", "ctrl+é"):
            with self.subTest(hotkey=bad), self.assertRaises(ValueError):
                to_portal_trigger(bad)


class SessionDetectionTests(unittest.TestCase):
    def test_detection(self):
        cases = [
            ({"XDG_SESSION_TYPE": "wayland"}, True),
            ({"WAYLAND_DISPLAY": "wayland-0"}, True),
            ({"XDG_SESSION_TYPE": "x11", "DISPLAY": ":0"}, False),
            ({"XDG_SESSION_TYPE": "wayland", "WRITING_TOOLS_FORCE_X11": "1"}, False),
        ]
        for env, expected in cases:
            with self.subTest(env=env), mock.patch.dict(os.environ, env, clear=True), \
                    mock.patch("sys.platform", "linux"):
                self.assertEqual(is_wayland_session(), expected)

    def test_never_wayland_off_linux(self):
        with mock.patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-0"}, clear=True), \
                mock.patch("sys.platform", "win32"):
            self.assertFalse(is_wayland_session())


class ShortcutIdTests(unittest.TestCase):
    def test_ids_are_stable_slugs(self):
        self.assertEqual(button_shortcut_id("Proofread"), "button-proofread")
        self.assertEqual(button_shortcut_id("Key Points"), "button-key-points")
        self.assertEqual(button_shortcut_id("  !!  "), "button-button")


class IntegrationDispatchTests(unittest.TestCase):
    """register() wiring: portal ids and trigger names reach the right callbacks."""

    def make(self):
        wi = integration.WaylandIntegration(base_dir="/tmp", notify=mock.Mock())
        wi.portal = mock.Mock()
        wi.portal.bind.return_value = {"open-writing-tools": "Ctrl+Alt+Space"}
        wi._portal_ready.set()
        return wi

    def test_dispatch(self):
        wi = self.make()
        hits = []
        wi.register("ctrl+alt+space", lambda: hits.append("main"), [
            ("Proofread", "ctrl+alt+p", lambda: hits.append("proofread")),
            ("Key Points", "", lambda: hits.append("key points")),
        ])
        wi._on_activated("open-writing-tools")
        wi._on_activated("button-proofread")
        wi._on_activated("button-unknown")
        wi._on_trigger("popup")
        wi._on_trigger("key points")   # trigger names are case-insensitive
        wi._on_trigger("nope")
        self.assertEqual(hits, ["main", "proofread", "main", "key points"])

    def test_only_buttons_with_hotkeys_go_to_the_portal(self):
        wi = self.make()
        wi.register("ctrl+alt+space", lambda: None, [
            ("Proofread", "ctrl+alt+p", lambda: None),
            ("Key Points", "", lambda: None),
        ])
        for _ in range(50):
            if wi.portal.bind.called:
                break
            time.sleep(0.02)
        requested = wi.portal.bind.call_args[0][0]
        self.assertEqual([r[0] for r in requested], ["open-writing-tools", "button-proofread"])
        self.assertEqual(requested[1][2], "CTRL+ALT+p")
        wi.notify.assert_not_called()

    def test_hotkey_change_opens_desktop_editor(self):
        wi = self.make()
        wi.register("ctrl+alt+space", lambda: None, [])
        time.sleep(0.1)
        wi.register("ctrl+alt+w", lambda: None, [])
        for _ in range(50):
            if wi.portal.configure.called:
                break
            time.sleep(0.02)
        wi.portal.configure.assert_called_once()

    def test_declined_bind_is_silent_while_closing(self):
        wi = self.make()
        wi.portal.bind.side_effect = integration.PortalError("the shortcut request was cancelled")
        portal = wi.portal
        wi._closing = True
        wi._bind([("open-writing-tools", "Open Writing Tools", "CTRL+space")], False)
        wi.notify.assert_not_called()
        wi._closing = False
        wi.portal = portal
        wi._bind([("open-writing-tools", "Open Writing Tools", "CTRL+space")], False)
        wi.notify.assert_called_once()


class TransactionTests(unittest.TestCase):
    """Overlapping actions: one capture at a time, stale pastes are dropped."""

    def make(self):
        wi = integration.WaylandIntegration(base_dir="/tmp", notify=mock.Mock())
        wi.text_io = mock.Mock()
        wi._wait_for_hotkey_release = lambda: True
        return wi

    def holder(self):
        return types.SimpleNamespace(text=None, ready=threading.Event())

    def test_second_capture_is_refused_while_first_runs(self):
        wi = self.make()
        gate = threading.Event()
        wi.text_io.capture_selection.side_effect = lambda **kw: (gate.wait(2), "text")[1]
        first, second = self.holder(), self.holder()
        self.assertTrue(wi.capture_async(first))
        self.assertFalse(wi.capture_async(second))
        gate.set()
        self.assertTrue(first.ready.wait(2))
        self.assertEqual(first.text, "text")
        self.assertFalse(second.ready.is_set())
        for _ in range(50):
            if not wi._capturing:
                break
            time.sleep(0.02)
        self.assertTrue(wi.capture_async(self.holder()), "capturing again works afterwards")

    def test_paste_from_an_earlier_action_is_dropped(self):
        wi = self.make()
        wi.text_io.capture_selection.return_value = "new selection"
        with wi._io_lock:                      # paste is queued behind another operation
            wi.paste_async("old result")
            time.sleep(0.05)
            with wi._state_lock:               # meanwhile the user starts a new action
                wi._generation += 1
        time.sleep(0.2)
        wi.text_io.paste_text.assert_not_called()

    def test_current_paste_runs(self):
        wi = self.make()
        wi.paste_async("result")
        for _ in range(50):
            if wi.text_io.paste_text.called:
                break
            time.sleep(0.02)
        wi.text_io.paste_text.assert_called_once_with("result")

    def test_held_modifiers_abort_the_capture(self):
        wi = self.make()
        wi._wait_for_hotkey_release = lambda: False
        copied = []

        def capture(before_copy=None):
            before_copy()          # raises: keys still held
            copied.append(True)    # Ctrl+C would go out here
            return "text"

        wi.text_io.capture_selection.side_effect = capture
        h = self.holder()
        wi.capture_async(h)
        self.assertTrue(h.ready.wait(2))
        self.assertEqual(h.text, "")
        self.assertEqual(copied, [], "no Ctrl+C while the hotkey is held")

    def test_release_wait_happens_inside_capture(self):
        # The clipboard is prepared while the user lets go of the hotkey.
        wi = self.make()
        wi.capture_async(self.holder())
        for _ in range(50):
            if wi.text_io.capture_selection.called:
                break
            time.sleep(0.02)
        kwargs = wi.text_io.capture_selection.call_args.kwargs
        self.assertEqual(kwargs["before_copy"], wi._require_hotkey_release)


class KeyboardCacheTests(unittest.TestCase):
    """Finding keyboards opens every input device; only redo it when devices change."""

    def setUp(self):
        integration._keyboard_cache = (None, ())
        self.addCleanup(setattr, integration, "_keyboard_cache", (None, ()))
        self.paths = ["/dev/input/event0", "/dev/input/event1"]
        self.queried = []

        test = self

        class Device:
            def __init__(self, path):
                self.path = path

            def capabilities(self):
                test.queried.append(self.path)
                return {1: [29, 30] if self.path.endswith("0") else [272]}  # event0 has Ctrl

            def close(self):
                pass

        fake = types.SimpleNamespace(
            list_devices=lambda: list(self.paths), InputDevice=Device,
            ecodes=types.SimpleNamespace(EV_KEY=1),
        )
        patcher = mock.patch.dict("sys.modules", {"evdev": fake})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_scans_once_then_reuses(self):
        first = integration._open_keyboards()
        self.assertEqual([d.path for d in first], ["/dev/input/event0"])
        self.assertEqual(len(self.queried), 2)
        again = integration._open_keyboards()
        self.assertEqual([d.path for d in again], ["/dev/input/event0"])
        self.assertEqual(len(self.queried), 2, "no rescan while the device list is unchanged")

    def test_rescans_when_a_device_is_plugged_in(self):
        integration._open_keyboards()
        self.paths.append("/dev/input/event2")
        integration._open_keyboards()
        self.assertEqual(len(self.queried), 5)


class FakeClipboard:
    """Stands in for wl-copy/wl-paste and the key injector."""

    def __init__(self, selection, initial="user clipboard", copy_works=True, drop_first_copies=0):
        self.content = initial
        self.selection = selection
        self.copy_works = copy_works
        self.drop_first_copies = drop_first_copies
        self.copy_presses = 0
        self.history = []
        self.pasted = []

    def read(self):
        return self.content

    def write(self, text, sensitive=False):
        self.content = text
        self.history.append((text, sensitive))

    def snapshot(self):
        if self.content is None:
            return text_io.ClipboardSnapshot()
        return text_io.ClipboardSnapshot("text/plain", self.content.encode())

    def restore(self, snap):
        if snap is None:
            return
        self.content = None if snap.mime is None else snap.data.decode()

    def copy(self):
        self.copy_presses += 1
        if self.copy_works and self.copy_presses > self.drop_first_copies:
            self.content = self.selection

    def paste(self):
        self.pasted.append(self.content)


class CaptureTests(unittest.TestCase):
    def make_io(self, clip):
        injector = mock.Mock()
        injector.copy.side_effect = clip.copy
        injector.paste.side_effect = clip.paste
        with mock.patch("shutil.which", return_value="/usr/bin/wl-copy"):
            io = text_io.WaylandTextIO(injector=injector)
        patches = [
            mock.patch.object(text_io, "read_clipboard", side_effect=clip.read),
            mock.patch.object(text_io, "write_clipboard", side_effect=clip.write),
            mock.patch.object(text_io, "snapshot_clipboard", side_effect=clip.snapshot),
            mock.patch.object(text_io, "restore_clipboard", side_effect=clip.restore),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        return io

    def test_capture_returns_selection_and_restores_clipboard(self):
        clip = FakeClipboard(selection="teh quick fox")
        io = self.make_io(clip)
        self.assertEqual(io.capture_selection(timeout=0.5), "teh quick fox")
        self.assertEqual(clip.content, "user clipboard")
        sentinel, sensitive = clip.history[0]
        self.assertTrue(sentinel.startswith("writing-tools-capture-"))
        self.assertTrue(sensitive, "sentinel must be marked sensitive for clipboard managers")

    def test_capture_detects_selection_equal_to_old_clipboard(self):
        # The old clear-and-poll approach can't tell these apart.
        clip = FakeClipboard(selection="same text", initial="same text")
        io = self.make_io(clip)
        self.assertEqual(io.capture_selection(timeout=0.5), "same text")

    def test_capture_retries_a_dropped_ctrl_c_once(self):
        clip = FakeClipboard(selection="teh quick fox", drop_first_copies=1)
        io = self.make_io(clip)
        self.assertEqual(io.capture_selection(timeout=1.5), "teh quick fox")
        self.assertEqual(clip.copy_presses, 2)

    def test_capture_presses_at_most_twice(self):
        clip = FakeClipboard(selection="", copy_works=False)
        io = self.make_io(clip)
        io.capture_selection(timeout=1.0)
        self.assertEqual(clip.copy_presses, 2)

    def test_capture_without_selection_times_out_empty(self):
        clip = FakeClipboard(selection="", copy_works=False)
        io = self.make_io(clip)
        start = time.monotonic()
        self.assertEqual(io.capture_selection(timeout=0.3), "")
        self.assertLess(time.monotonic() - start, 1.0)
        self.assertEqual(clip.content, "user clipboard")

    def test_before_copy_runs_after_sentinel_and_before_ctrl_c(self):
        clip = FakeClipboard(selection="teh quick fox")
        io = self.make_io(clip)
        seen = []
        before = lambda: seen.append((clip.content.startswith("writing-tools-capture-"), clip.copy_presses))
        self.assertEqual(io.capture_selection(timeout=0.5, before_copy=before), "teh quick fox")
        self.assertEqual(seen, [(True, 0)])

    def test_failing_before_copy_sends_no_key_and_restores(self):
        clip = FakeClipboard(selection="teh quick fox")
        io = self.make_io(clip)

        def before():
            raise text_io.TextIOError("keys still held")

        with self.assertRaises(text_io.TextIOError):
            io.capture_selection(timeout=0.5, before_copy=before)
        self.assertEqual(clip.copy_presses, 0)
        self.assertEqual(clip.content, "user clipboard")

    def test_nothing_selected_gives_up_within_a_second(self):
        clip = FakeClipboard(selection="", copy_works=False)
        io = self.make_io(clip)
        start = time.monotonic()
        self.assertEqual(io.capture_selection(), "")
        self.assertLess(time.monotonic() - start, 1.0)
        self.assertEqual(clip.copy_presses, 2)

    def test_empty_clipboard_is_left_empty(self):
        clip = FakeClipboard(selection="", copy_works=False, initial=None)
        io = self.make_io(clip)
        self.assertEqual(io.capture_selection(timeout=0.4), "")
        self.assertIsNone(clip.content, "the sentinel must not be left on the clipboard")

    def test_user_copy_during_paste_is_not_overwritten(self):
        clip = FakeClipboard(selection="")
        clip.paste = lambda: setattr(clip, "content", "copied by the user meanwhile")
        io = self.make_io(clip)
        io.paste_text("The quick fox", settle=0)
        self.assertEqual(clip.content, "copied by the user meanwhile")

    def test_paste_puts_text_then_restores(self):
        clip = FakeClipboard(selection="")
        io = self.make_io(clip)
        io.paste_text("The quick fox", settle=0)
        self.assertEqual(clip.pasted, ["The quick fox"])
        self.assertEqual(clip.content, "user clipboard")


@unittest.skipUnless(shutil.which("wl-copy") and os.environ.get("WAYLAND_DISPLAY"),
                     "needs a Wayland session with wl-clipboard")
class RealClipboardTests(unittest.TestCase):
    def setUp(self):
        self.backup = text_io.snapshot_clipboard()

    def tearDown(self):
        text_io.restore_clipboard(self.backup)

    def test_round_trip_unicode(self):
        sample = "Grüße — مرحبا 👋\nsecond line"
        text_io.write_clipboard(sample)
        time.sleep(0.1)
        self.assertEqual(text_io.read_clipboard(), sample)

    def test_snapshot_restores_binary_content(self):
        png = bytes.fromhex("89504e470d0a1a0a") + os.urandom(64)
        text_io.restore_clipboard(text_io.ClipboardSnapshot("image/png", png))
        time.sleep(0.1)
        snap = text_io.snapshot_clipboard()
        self.assertEqual((snap.mime, snap.data), ("image/png", png))
        text_io.write_clipboard("overwritten")
        text_io.restore_clipboard(snap)
        time.sleep(0.1)
        again = text_io.snapshot_clipboard()
        self.assertEqual((again.mime, again.data), ("image/png", png))

    def test_write_returns_quickly(self):
        start = time.monotonic()
        text_io.write_clipboard("speed check")
        self.assertLess(time.monotonic() - start, 1.0)


class KeyInjectorTests(unittest.TestCase):
    def test_custom_injector_must_be_executable(self):
        with self.assertRaises(text_io.TextIOError):
            text_io.KeyInjector("/nonexistent/injector")

    def test_custom_injector_receives_action(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = os.path.join(tmp, "log")
            script = os.path.join(tmp, "inject")
            with open(script, "w") as f:
                f.write(f"#!/bin/sh\necho \"$1\" >> {log}\n")
            os.chmod(script, 0o755)
            injector = text_io.KeyInjector(script)
            injector.copy()
            injector.paste()
            with open(log) as f:
                self.assertEqual(f.read().split(), ["copy", "paste"])

    def test_wtype_command_spaces_keys(self):
        with mock.patch("shutil.which", side_effect=lambda t: "/usr/bin/wtype" if t == "wtype" else None), \
                mock.patch("subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, b"", b"")
            text_io.KeyInjector("wtype").copy()
        self.assertEqual(run.call_args[0][0],
                         ["wtype", "-M", "ctrl", "-s", "12", "-k", "c", "-s", "12", "-m", "ctrl"])

    def test_ydotool_command(self):
        with mock.patch("shutil.which", return_value="/usr/bin/ydotool"), \
                mock.patch.object(text_io, "_ydotool_socket", return_value="/tmp/sock"), \
                mock.patch("subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, b"", b"")
            text_io.KeyInjector("ydotool").paste()
        args = run.call_args[0][0]
        self.assertEqual(args, ["ydotool", "key", "--key-delay", "12",
                                "29:1", "47:1", "47:0", "29:0"])
        self.assertEqual(run.call_args[1]["env"]["YDOTOOL_SOCKET"], "/tmp/sock")

    def test_injector_failure_raises_with_stderr(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = os.path.join(tmp, "inject")
            with open(script, "w") as f:
                f.write("#!/bin/sh\necho 'failed to connect socket' >&2\nexit 2\n")
            os.chmod(script, 0o755)
            with self.assertRaises(text_io.TextIOError) as ctx:
                text_io.KeyInjector(script).copy()
            self.assertIn("failed to connect socket", str(ctx.exception))

    def test_injector_that_leaves_a_background_child_returns(self):
        # Like wl-copy: a child that outlives the injector and keeps fds open.
        with tempfile.TemporaryDirectory() as tmp:
            script = os.path.join(tmp, "inject")
            with open(script, "w") as f:
                f.write("#!/bin/sh\nsleep 30 &\nexit 0\n")
            os.chmod(script, 0o755)
            start = time.monotonic()
            text_io.KeyInjector(script).paste()
            self.assertLess(time.monotonic() - start, 2.0)


class TriggerSocketTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        patcher = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.tmp})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_trigger_reaches_callback(self):
        received = []
        done = threading.Event()

        def on_trigger(action):
            received.append(action)
            done.set()

        server = trigger_socket.TriggerServer(on_trigger)
        server.start()
        self.addCleanup(server.stop)
        mode = os.stat(trigger_socket.socket_path()).st_mode & 0o777
        self.assertEqual(mode, 0o600)
        self.assertTrue(trigger_socket.send_trigger("Key Points"))
        self.assertTrue(done.wait(2))
        self.assertEqual(received, ["Key Points"])

    def test_no_server(self):
        self.assertFalse(trigger_socket.send_trigger())

    def test_stale_socket_is_replaced(self):
        import socket
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(trigger_socket.socket_path())
        stale.close()  # leaves the file behind with nobody listening
        server = trigger_socket.TriggerServer(lambda a: None)
        server.start()
        self.addCleanup(server.stop)
        self.assertTrue(trigger_socket.send_trigger())

    def test_stop_ends_the_listener_thread(self):
        server = trigger_socket.TriggerServer(lambda a: None)
        server.start()
        thread = server._thread
        server.stop()
        thread.join(2)
        self.assertFalse(thread.is_alive())
        self.assertFalse(os.path.exists(trigger_socket.socket_path()))

    def test_second_instance_refused_without_triggering_first(self):
        received = []
        first = trigger_socket.TriggerServer(received.append)
        first.start()
        self.addCleanup(first.stop)
        with self.assertRaises(OSError):
            trigger_socket.TriggerServer(lambda a: None).start()
        time.sleep(0.2)
        self.assertEqual(received, [], "the liveness probe must not fire an action")


class DesktopEntryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        patcher = mock.patch.dict(os.environ, {"XDG_DATA_HOME": self.tmp})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_creates_entry_with_quoted_paths(self):
        path = desktop_entry.ensure_desktop_entry("/opt/writing tools")
        assert path is not None
        with open(path) as f:
            content = f.read()
        self.assertIn('"/opt/writing tools/main.py"', content)
        self.assertTrue(path.endswith("io.github.thejaytea.WritingTools.desktop"))

    def test_leaves_foreign_entry_alone(self):
        path = os.path.join(self.tmp, "applications", "io.github.thejaytea.WritingTools.desktop")
        os.makedirs(os.path.dirname(path))
        with open(path, "w") as f:
            f.write("[Desktop Entry]\nName=Packaged\n")
        desktop_entry.ensure_desktop_entry("/somewhere")
        with open(path) as f:
            self.assertIn("Packaged", f.read())

    def test_updates_own_entry_when_moved(self):
        desktop_entry.ensure_desktop_entry("/old/place")
        path = desktop_entry.ensure_desktop_entry("/new/place")
        assert path is not None
        with open(path) as f:
            content = f.read()
        self.assertIn("/new/place/main.py", content)
        self.assertNotIn("/old/place", content)


if __name__ == "__main__":
    unittest.main()
