"""
Glue between WritingToolApp and the Wayland helpers.

WritingToolApp hands over its hotkeys and callbacks; this class decides how
they reach the desktop (portal and/or trigger socket) and runs the clipboard
round trips off the GUI thread.
"""

import logging
import os
import re
import threading
import time

from . import APP_ID
from . import portal_shortcuts
from .desktop_entry import ensure_desktop_entry
from .hotkeys import to_portal_trigger
from .portal_shortcuts import PortalError, PortalShortcuts
from .text_io import TextIOError, WaylandTextIO
from .trigger_socket import TriggerServer

MAIN_SHORTCUT_ID = "open-writing-tools"
POPUP_ACTION = "popup"

# Before sending Ctrl+C, wait for the user to let go of the hotkey: a modifier
# that is still held turns Ctrl+C into e.g. Ctrl+Alt+C, which can trigger an
# unrelated command in the focused app.
DEACTIVATED_TIMEOUT = 0.6   # wait for the portal's "shortcut released" signal
RELEASE_TIMEOUT = 2.0       # then, if key state is readable, for modifiers to lift
PORTAL_START_TIMEOUT = 15

_MODIFIER_CODES = (29, 97, 42, 54, 56, 100, 125, 126)  # ctrl, shift, alt, meta (left/right)


def button_shortcut_id(name):
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "button"
    return f"button-{slug}"


def _open_keyboards():
    """
    Open the keyboards through evdev to read which keys are held right now.
    Returns None when that isn't possible (evdev missing, or the user is not
    in the 'input' group). Nothing is grabbed; this only reads key state.
    """
    try:
        import evdev
    except ImportError:
        return None
    keyboards = []
    for path in evdev.list_devices():
        try:
            device = evdev.InputDevice(path)
        except OSError:
            continue
        keys = device.capabilities().get(evdev.ecodes.EV_KEY, [])
        if 29 in keys:  # has a Ctrl key: treat it as a keyboard
            keyboards.append(device)
        else:
            device.close()
    return keyboards or None


def _modifiers_held(keyboards):
    try:
        return any(
            code in _MODIFIER_CODES for device in keyboards for code in device.active_keys()
        )
    except OSError:
        return False


class WaylandIntegration:
    def __init__(self, base_dir, notify):
        """
        base_dir: folder holding main.py and icons/ (used for the .desktop file)
        notify:   thread-safe callable(title, message) for user-facing errors
        """
        self.base_dir = base_dir
        self.notify = notify
        self.portal = None
        self.trigger_server = None
        self.text_io = None
        self._shortcut_callbacks = {}
        self._actions = {}
        self._last_main_hotkey = None
        self._released = threading.Event()
        self._released.set()
        self._io_lock = threading.Lock()
        self._closing = False
        # One capture at a time; each new action bumps the generation so
        # results of an older action are never pasted into a newer one.
        self._state_lock = threading.Lock()
        self._capturing = False
        self._generation = 0
        self._portal_ready = threading.Event()

    # -- lifecycle ---------------------------------------------------------

    def start(self):
        try:
            self.text_io = WaylandTextIO()
        except TextIOError as e:
            logging.error(f"Wayland text capture unavailable: {e}")
            self.notify("Writing Tools: setup needed", str(e))

        ensure_desktop_entry(self.base_dir)

        try:
            self.trigger_server = TriggerServer(self._on_trigger)
            self.trigger_server.start()
        except OSError as e:
            logging.warning(f"Trigger socket disabled: {e}")
            self.trigger_server = None

        # Talking to the portal can block on D-Bus timeouts; keep it off the
        # GUI thread. register() waits for this before binding.
        threading.Thread(target=self._start_portal, name="portal-start", daemon=True).start()

    def _start_portal(self):
        try:
            if os.environ.get("WRITING_TOOLS_DISABLE_PORTAL"):
                logging.info("Global shortcuts portal disabled by WRITING_TOOLS_DISABLE_PORTAL")
            elif portal_shortcuts.is_available():
                portal = PortalShortcuts(APP_ID, self._on_activated, self._on_deactivated)
                try:
                    portal.start()
                except Exception as e:  # noqa: BLE001
                    logging.error(f"Global shortcuts portal failed: {e}")
                    portal.close()
                else:
                    if self._closing:
                        portal.close()
                    else:
                        self.portal = portal
            if self.portal is None:
                logging.warning(
                    "No global shortcuts portal. Bind a key in your desktop settings "
                    "to run: main.py --trigger"
                )
        finally:
            self._portal_ready.set()

    def close(self):
        self._closing = True
        if self.portal is not None:
            self.portal.close()
            self.portal = None
        if self.trigger_server is not None:
            self.trigger_server.stop()
            self.trigger_server = None

    # -- shortcuts ---------------------------------------------------------

    def register(self, main_hotkey, main_callback, buttons):
        """
        main_hotkey/main_callback: the hotkey that opens the popup.
        buttons: list of (button_name, hotkey or '', callback). Every button
        is reachable through the trigger socket; only the ones with a hotkey
        are registered with the portal.

        Portal binding runs in the background: the first time, the desktop
        may show a confirmation dialog and wait for the user.
        """
        self._actions = {POPUP_ACTION: main_callback}
        self._shortcut_callbacks = {MAIN_SHORTCUT_ID: main_callback}
        requested = [(MAIN_SHORTCUT_ID, "Open Writing Tools", self._trigger_or_none(main_hotkey))]

        for name, hotkey, callback in buttons:
            self._actions[name.lower()] = callback
            if not hotkey:
                continue
            sid = button_shortcut_id(name)
            if sid in self._shortcut_callbacks:
                logging.warning(f"Button '{name}' maps to an existing shortcut id; skipping")
                continue
            self._shortcut_callbacks[sid] = callback
            requested.append((sid, f"Writing Tools: {name}", self._trigger_or_none(hotkey)))

        hotkey_changed = self._last_main_hotkey not in (None, main_hotkey)
        self._last_main_hotkey = main_hotkey
        threading.Thread(
            target=self._bind, args=(requested, hotkey_changed),
            name="portal-bind", daemon=True,
        ).start()

    @staticmethod
    def _trigger_or_none(hotkey):
        try:
            return to_portal_trigger(hotkey)
        except ValueError as e:
            logging.error(f"Hotkey '{hotkey}' can't be sent to the desktop: {e}")
            return None

    def _bind(self, requested, hotkey_changed):
        self._portal_ready.wait(PORTAL_START_TIMEOUT)
        portal = self.portal
        if portal is None:  # no portal, or closed meanwhile
            return
        logging.info("Registering global shortcuts; the desktop may ask you to confirm them")
        try:
            assigned = portal.bind(requested)
        except PortalError as e:
            if self._closing:
                return  # the app is quitting; the pending request was dropped
            logging.error(f"Binding global shortcuts failed: {e}")
            self.notify(
                "Writing Tools: shortcut not registered",
                f"{e}.\n\nYou can still assign a shortcut to 'Writing Tools' "
                "in your desktop's keyboard shortcut settings.",
            )
            return
        for sid, trigger in assigned.items():
            logging.info(f"Global shortcut {sid}: {trigger or 'not assigned'}")
        if hotkey_changed:
            # The desktop keeps a shortcut's key once the user accepted it, so
            # a new hotkey typed into Settings has to be applied there.
            if not portal.configure():
                self.notify(
                    "Writing Tools: change the shortcut in your desktop settings",
                    "Your desktop manages global shortcuts on Wayland. Open its "
                    "keyboard shortcut settings and change 'Open Writing Tools'.",
                )
        elif not assigned.get(MAIN_SHORTCUT_ID):
            self.notify(
                "Writing Tools: no shortcut assigned",
                "The desktop did not assign a key to 'Open Writing Tools' "
                "(the request was declined or the key is taken). Set one in "
                "your desktop's keyboard shortcut settings.",
            )

    def _on_activated(self, shortcut_id):
        callback = self._shortcut_callbacks.get(shortcut_id)
        if callback is None:
            logging.debug(f"Activated for unknown shortcut '{shortcut_id}'")
            return
        self._released.clear()
        callback()

    def _on_deactivated(self, shortcut_id):
        self._released.set()

    def _on_trigger(self, action):
        callback = self._actions.get(action.lower())
        if callback is None:
            logging.warning(f"Trigger for unknown action '{action}'")
            return
        callback()

    # -- text --------------------------------------------------------------

    def _wait_for_hotkey_release(self):
        """
        Wait until the user has let go of the hotkey. Returns False if a
        modifier is still held after RELEASE_TIMEOUT; the caller must then
        not send Ctrl+C.

        The portal's Deactivated signal says the shortcut was released; evdev
        (when the user may read input devices) confirms no modifier is down.
        """
        self._released.wait(DEACTIVATED_TIMEOUT)
        keyboards = _open_keyboards()
        try:
            if keyboards is None:
                time.sleep(0.15)  # key state unreadable: give the user a moment
                return True
            deadline = time.monotonic() + RELEASE_TIMEOUT
            while _modifiers_held(keyboards):
                if time.monotonic() >= deadline:
                    return False
                time.sleep(0.03)
            return True
        finally:
            for device in keyboards or ():
                device.close()

    def capture_async(self, holder, on_done=None):
        """
        Fill holder.text with the current selection on a worker thread, then
        call on_done (from that thread).

        Returns False, and does nothing, while another capture is running:
        a second Ctrl+C could land in a popup opened by the first one.
        Starting a capture also cancels any paste still waiting to run.
        """
        with self._state_lock:
            if self._capturing:
                logging.info("Ignoring trigger: still capturing the previous selection")
                return False
            self._capturing = True
            self._generation += 1
            generation = self._generation

        def run():
            text = ""
            try:
                if self.text_io is None:
                    raise TextIOError("text capture is not set up")
                with self._io_lock:
                    if not self._wait_for_hotkey_release():
                        raise TextIOError(
                            "the shortcut keys were still held down, so no text was copied"
                        )
                    text = self.text_io.capture_selection()
                logging.debug(f"Captured selected text (len={len(text)})")
            except Exception as e:  # noqa: BLE001
                logging.error(f"Capturing the selection failed: {e}")
            finally:
                holder.text = text
                holder.ready.set()
                with self._state_lock:
                    self._capturing = False
                    current = generation == self._generation
                if on_done is not None and current and not self._closing:
                    on_done()

        threading.Thread(target=run, name="wayland-capture", daemon=True).start()
        return True

    def paste_async(self, text):
        """
        Paste `text` over the selection on a worker thread. Dropped if a new
        action starts before the paste gets to run.
        """
        with self._state_lock:
            generation = self._generation

        def run():
            try:
                if self.text_io is None:
                    raise TextIOError("text capture is not set up")
                with self._io_lock:
                    with self._state_lock:
                        stale = generation != self._generation
                    if stale or self._closing:
                        logging.info("Dropping a paste from an earlier action")
                        return
                    self.text_io.paste_text(text)
            except Exception as e:  # noqa: BLE001
                logging.error(f"Pasting the result failed: {e}")
                self.notify("Writing Tools: paste failed", str(e))

        threading.Thread(target=run, name="wayland-paste", daemon=True).start()
