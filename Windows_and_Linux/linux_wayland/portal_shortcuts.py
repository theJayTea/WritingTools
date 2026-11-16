"""
Global shortcuts through the XDG desktop portal
(org.freedesktop.portal.GlobalShortcuts).

This is the only way an application can own a system-wide shortcut on a
Wayland compositor without root access to /dev/input. KDE Plasma 5.27+,
GNOME 48+ and Hyprland implement it.

Flow:
  1. Register our app id with the host registry (portal >= 1.19). Unsandboxed
     apps have no app id otherwise, and KDE refuses CreateSession without one.
     The id must match an installed .desktop file (see desktop_entry.py).
  2. CreateSession, then BindShortcuts with a description and a
     preferred_trigger for every action.
  3. Listen for the Activated signal and dispatch to a callback.

The desktop owns the final key binding. On KDE the shortcut shows up in
System Settings > Shortcuts under "Writing Tools", where the user can change
it. A trigger that was assigned once is kept across restarts, so changing the
hotkey in Writing Tools only affects the first registration; the
`configure()` method opens the desktop's own editor for later changes where
the portal supports it.

All D-Bus traffic runs on jeepney's background router thread, so nothing
here blocks the Qt event loop. Callbacks fire on that thread; callers must
bounce into the GUI thread themselves.
"""

import logging
import secrets
import threading
import time

try:
    from jeepney import DBusAddress, HeaderFields, MatchRule, new_method_call
    from jeepney.bus_messages import message_bus
    from jeepney.io.threading import Proxy, open_dbus_router
    from jeepney.wrappers import DBusErrorResponse, unwrap_msg
except ImportError:  # pragma: no cover - handled by is_available()
    open_dbus_router = None

PORTAL_BUS_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SHORTCUTS_IFACE = "org.freedesktop.portal.GlobalShortcuts"
REQUEST_IFACE = "org.freedesktop.portal.Request"
SESSION_IFACE = "org.freedesktop.portal.Session"
REGISTRY_IFACE = "org.freedesktop.host.portal.Registry"

# Request.Response codes, as defined by the portal spec.
RESPONSE_SUCCESS = 0
RESPONSE_CANCELLED = 1


class PortalError(Exception):
    """Raised when the portal is missing or refuses a request."""


def is_available():
    """True if jeepney is importable and the portal exposes GlobalShortcuts."""
    if open_dbus_router is None:
        return False
    try:
        with open_dbus_router(bus="SESSION") as router:
            msg = new_method_call(
                DBusAddress(PORTAL_PATH, PORTAL_BUS_NAME, "org.freedesktop.DBus.Properties"),
                "Get", "ss", (SHORTCUTS_IFACE, "version"),
            )
            reply = router.send_and_get_reply(msg, timeout=3)
            unwrap_msg(reply)
            return True
    except Exception as e:  # noqa: BLE001 - any failure means "not available"
        logging.info(f"GlobalShortcuts portal not available: {e}")
        return False


class PortalShortcuts:
    """
    Owns one GlobalShortcuts portal session.

    `bind()` replaces the full set of shortcuts and returns a dict mapping each
    shortcut id to the trigger the desktop actually assigned ('' when unset).
    """

    def __init__(self, app_id, on_activated, on_deactivated=None):
        if open_dbus_router is None:
            raise PortalError("the jeepney package is not installed")
        self.app_id = app_id
        self.on_activated = on_activated
        self.on_deactivated = on_deactivated
        self._router_cm = None
        self._router = None
        self._bound = False
        self._session = None
        self._listener = None
        self._stop = threading.Event()
        self._lock = threading.Lock()

    # -- lifecycle ---------------------------------------------------------

    def start(self):
        """Open the bus connection, register the app id and create a session."""
        self._router_cm = open_dbus_router(bus="SESSION")
        self._router = self._router_cm.__enter__()
        self._bus = Proxy(message_bus, self._router)
        self._register_app_id()
        self._session = self._create_session()
        self._start_listener()
        logging.info(f"GlobalShortcuts portal session: {self._session}")

    def close(self):
        """
        Close the portal session and the bus connection. Safe to call twice.

        Doesn't wait for a bind() that is still waiting on the user: closing
        the connection makes the portal drop that request and its dialog.
        """
        self._stop.set()
        got_lock = self._lock.acquire(timeout=1)
        try:
            if self._session and self._router:
                try:
                    msg = new_method_call(
                        DBusAddress(self._session, PORTAL_BUS_NAME, SESSION_IFACE), "Close"
                    )
                    self._router.send_and_get_reply(msg, timeout=2)
                except Exception as e:  # noqa: BLE001 - best effort on shutdown
                    logging.debug(f"Closing portal session failed: {e}")
            self._session = None
            if self._router_cm is not None:
                try:
                    self._router_cm.__exit__(None, None, None)
                except Exception:  # noqa: BLE001
                    pass
                self._router_cm = None
                self._router = None
        finally:
            if got_lock:
                self._lock.release()

    # -- public API --------------------------------------------------------

    def bind(self, shortcuts):
        """
        Bind shortcuts on the current session.

        `shortcuts` is a list of (shortcut_id, description, preferred_trigger)
        tuples; preferred_trigger may be None. Returns {id: assigned_trigger}.

        The portal spec allows a single BindShortcuts call per session, so a
        second call (e.g. after the user edited their hotkeys) opens a fresh
        session first.
        """
        with self._lock:
            if self._session is None:
                raise PortalError("portal session is not open")
            if self._bound:
                self._close_session_locked()
                self._session = self._create_session()
            # Any attempt uses up the session, even a declined or failed one.
            self._bound = True
            payload = []
            for sid, description, trigger in shortcuts:
                props = {"description": ("s", description)}
                if trigger:
                    props["preferred_trigger"] = ("s", trigger)
                payload.append((sid, props))

            code, results = self._request(
                "BindShortcuts", "oa(sa{sv})sa{sv}",
                lambda token: (self._session, payload, "", {"handle_token": ("s", token)}),
                # A first-time bind shows a confirmation dialog (KDE) that can
                # sit unnoticed on another monitor. Wait for as long as it is
                # open; close() ends the wait.
                timeout=None,
            )
            if code == RESPONSE_CANCELLED:
                raise PortalError("the shortcut request was cancelled")
            if code != RESPONSE_SUCCESS:
                raise PortalError(f"BindShortcuts failed with response code {code}")
            return self._parse_shortcuts(results)

    def list_shortcuts(self):
        """Return {id: trigger_description} for the shortcuts bound on this session."""
        with self._lock:
            code, results = self._request(
                "ListShortcuts", "oa{sv}",
                lambda token: (self._session, {"handle_token": ("s", token)}),
            )
            if code != RESPONSE_SUCCESS:
                raise PortalError(f"ListShortcuts failed with response code {code}")
            return self._parse_shortcuts(results)

    def configure(self):
        """
        Ask the desktop to show its shortcut editor for this app.

        ConfigureShortcuts is portal interface version 2. Returns False when the
        desktop doesn't support it, so the caller can fall back to instructions.
        """
        with self._lock:
            if self._session is None:
                return False
            try:
                msg = new_method_call(
                    self._portal(), "ConfigureShortcuts", "osa{sv}", (self._session, "", {})
                )
                unwrap_msg(self._router.send_and_get_reply(msg, timeout=5))
                return True
            except Exception as e:  # noqa: BLE001
                logging.info(f"ConfigureShortcuts not supported: {e}")
                return False

    # -- internals ---------------------------------------------------------

    def _portal(self):
        return DBusAddress(PORTAL_PATH, PORTAL_BUS_NAME, SHORTCUTS_IFACE)

    def _register_app_id(self):
        msg = new_method_call(
            DBusAddress(PORTAL_PATH, PORTAL_BUS_NAME, REGISTRY_IFACE),
            "Register", "sa{sv}", (self.app_id, {}),
        )
        try:
            unwrap_msg(self._router.send_and_get_reply(msg, timeout=5))
        except DBusErrorResponse as e:
            # Older portals (< 1.19) have no registry and derive the id from
            # the process instead. Anything else is a real problem: the
            # usual cause is a missing .desktop file for the app id.
            if "UnknownMethod" in str(e) or "UnknownInterface" in str(e):
                logging.info("Portal has no host registry; continuing without it")
                return
            raise PortalError(f"could not register app id '{self.app_id}': {e}") from e

    def _create_session(self):
        code, results = self._request(
            "CreateSession", "a{sv}",
            lambda token: ({
                "handle_token": ("s", token),
                "session_handle_token": ("s", "writingtools" + secrets.token_hex(4)),
            },),
        )
        if code != RESPONSE_SUCCESS:
            raise PortalError(f"CreateSession failed with response code {code}")
        self._bound = False
        return results["session_handle"][1]

    def _close_session_locked(self):
        try:
            msg = new_method_call(DBusAddress(self._session, PORTAL_BUS_NAME, SESSION_IFACE), "Close")
            self._router.send_and_get_reply(msg, timeout=2)
        except Exception as e:  # noqa: BLE001
            logging.debug(f"Closing old portal session failed: {e}")

    def _request(self, method, signature, body_for_token, timeout=10):
        """
        Call a portal method that answers through a Request object.

        The Response signal can arrive before the method reply, so we
        subscribe to the predictable request path *before* calling.
        """
        token = "writingtools" + secrets.token_hex(6)
        sender = self._router.unique_name.lstrip(":").replace(".", "_")
        path = f"{PORTAL_PATH}/request/{sender}/{token}"
        rule = MatchRule(type="signal", interface=REQUEST_IFACE, member="Response", path=path)
        self._bus.AddMatch(rule)
        try:
            with self._router.filter(rule) as queue:
                reply = self._router.send_and_get_reply(
                    new_method_call(self._portal(), method, signature, body_for_token(token)),
                    timeout=10,
                )
                unwrap_msg(reply)
                response = self._wait_response(queue, method, timeout)
                code, results = response.body
                return code, results
        finally:
            try:
                self._bus.RemoveMatch(rule)
            except Exception:  # noqa: BLE001
                pass

    def _wait_response(self, queue, method, timeout):
        """Wait for a Request.Response; timeout=None waits until close()."""
        deadline = None if timeout is None else time.monotonic() + timeout
        while True:
            if self._stop.is_set():
                raise PortalError(f"{method}: cancelled because the app is closing")
            step = 0.5 if deadline is None else min(0.5, deadline - time.monotonic())
            if step <= 0:
                raise PortalError(f"{method}: no response from the portal")
            try:
                return queue.get(timeout=step)
            except Exception:  # queue.Empty
                continue

    @staticmethod
    def _parse_shortcuts(results):
        out = {}
        for sid, props in results.get("shortcuts", ("a(sa{sv})", []))[1]:
            trigger = props.get("trigger_description", ("s", ""))[1]
            out[sid] = trigger
        return out

    def _start_listener(self):
        # Activated, Deactivated and ShortcutsChanged share one subscription.
        rule = MatchRule(type="signal", interface=SHORTCUTS_IFACE, path=PORTAL_PATH)
        self._bus.AddMatch(rule)
        self._signal_filter = self._router.filter(rule, bufsize=64)
        queue = self._signal_filter.__enter__()

        def listen():
            while not self._stop.is_set():
                try:
                    msg = queue.get(timeout=0.5)
                except Exception:  # queue.Empty
                    continue
                member = msg.header.fields.get(HeaderFields.member)
                if member == "Activated":
                    callback = self.on_activated
                elif member == "Deactivated":
                    callback = self.on_deactivated
                else:
                    continue
                session, shortcut_id = msg.body[0], msg.body[1]
                if callback is None or session != self._session:
                    continue
                try:
                    callback(shortcut_id)
                except Exception as e:  # noqa: BLE001 - never kill the listener
                    logging.error(f"Shortcut callback failed for '{shortcut_id}': {e}", exc_info=True)

        self._listener = threading.Thread(target=listen, name="portal-shortcuts", daemon=True)
        self._listener.start()
