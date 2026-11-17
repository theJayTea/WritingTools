import gettext
import json
import logging
import os
import shutil
import signal
import subprocess
import sys
import threading
import time

import darkdetect
import pyperclip
import ui.AboutWindow
import ui.CustomPopupWindow
import ui.OnboardingWindow
import ui.ResponseWindow
import ui.SettingsWindow
from aiprovider import (
    GeminiProvider,
    OllamaProvider,
    OpenAICompatibleProvider,
    obfuscate_api_key,
)
from pynput import keyboard as pykeyboard
from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import QLocale, Signal, Slot
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtWidgets import QApplication, QMessageBox
from update_checker import UpdateChecker

_ = gettext.gettext


class _SelectedTextHolder:
    """
    Carries the result of an async clipboard capture from `_show_popup` to
    `process_option_thread`. The capture thread sets `text` and signals
    `ready` once done.
    """

    __slots__ = ("text", "ready")

    def __init__(self):
        self.text = ""
        self.ready = threading.Event()


class WritingToolApp(QtWidgets.QApplication):
    """
    The main application class for Writing Tools.
    """

    output_ready_signal = Signal(str)
    show_message_signal = Signal(str, str)  # a signal for showing message boxes
    hotkey_triggered_signal = Signal()
    followup_response_signal = Signal(str)

    def __init__(self, argv):
        super().__init__(argv)
        self.current_response_window = None
        logging.debug("Initializing WritingToolApp")
        self.output_ready_signal.connect(self.replace_text)
        self.show_message_signal.connect(self.show_message_box)
        self.hotkey_triggered_signal.connect(self.on_hotkey_pressed)
        self.config = None
        self.config_path = None
        self.load_config()

        # Run any pending config migrations in a single pass (single restart).
        self._migrate_config()

        self.options = None
        self.options_path = None
        self.load_options()
        self.onboarding_window = None
        self.popup_window = None
        self.tray_icon = None
        self.tray_menu = None
        self.settings_window = None
        self.about_window = None
        self.registered_hotkey = None
        self.output_queue = ""
        self.last_replace = 0
        self.hotkey_listener = None
        self.paused = False
        self.toggle_action = None

        # Holder for the user's selected text. Populated asynchronously by a
        # background thread so the popup can show instantly — see `_show_popup`
        # and `_fire_ctrl_c_and_capture_async`. The lock serializes Ctrl+C
        # captures across rapid hotkey presses so two captures don't fight
        # over the clipboard at once.
        self.current_text_holder = None
        self._capture_lock = threading.Lock()
        # Window that was active when the hotkey fired. Used to re-activate
        # it before pasting an AI replacement (Wayland focus handling).
        self._source_window_id = None

        # PRIMARY (the Linux mouse selection) is sticky: KDE keeps the last
        # highlighted text around long after the highlight is gone, and it
        # survives restarts of this app. Remember what was selected at startup
        # (and after every capture) so leftover text (e.g. log lines selected
        # for a chat message) is never mistaken for a selection made for the
        # current hotkey press. Freshness is decided by comparing the live
        # selection against this remembered value at capture time, so no
        # background polling thread is needed.
        self._primary_selection_last_seen = self._read_primary_selection()
        self._last_captured_selection = None

        self._ = gettext.gettext

        # Initialize the ctrl+c hotkey listener
        self.ctrl_c_timer = None
        self.setup_ctrl_c_listener()

        # Setup available AI providers
        self.providers = [
            GeminiProvider(self),
            OpenAICompatibleProvider(self),
            OllamaProvider(self),
        ]

        if not self.config:
            logging.debug("No config found, showing onboarding")
            self.show_onboarding()
        else:
            logging.debug("Config found, setting up hotkey and tray icon")

            # Initialize the current provider, defaulting to Gemini
            provider_name = self.config.get("provider", "Gemini")

            self.current_provider = next(
                (
                    provider
                    for provider in self.providers
                    if provider.provider_name == provider_name
                ),
                None,
            )
            if not self.current_provider:
                logging.warning(
                    f"Provider {provider_name} not found. Using default provider."
                )
                self.current_provider = self.providers[0]

            self.current_provider.load_config(
                self.config.get("providers", {}).get(provider_name, {})
            )

            self.create_tray_icon()
            self.register_hotkey()

            try:
                lang = self.config["locale"]
            except KeyError:
                lang = None
            self.change_language(lang)

            # Initialize update checker
            self.update_checker = UpdateChecker(self)
            self.update_checker.check_updates_async()

        self.recent_triggers = []  # Track recent hotkey triggers
        self.TRIGGER_WINDOW = 1.5  # Time window in seconds
        self.MAX_TRIGGERS = 3  # Max allowed triggers in window

    def setup_translations(self, lang=None):
        if not lang:
            lang = QLocale.system().name().split("_")[0]

        try:
            translation = gettext.translation(
                "messages",
                localedir=os.path.join(os.path.dirname(__file__), "locales"),
                languages=[lang],
            )
        except FileNotFoundError:
            translation = gettext.NullTranslations()

        translation.install()
        # Update the translation function for all UI components.
        self._ = translation.gettext
        ui.AboutWindow._ = self._
        ui.SettingsWindow._ = self._
        ui.ResponseWindow._ = self._
        ui.OnboardingWindow._ = self._
        ui.CustomPopupWindow._ = self._

    def retranslate_ui(self):
        self.update_tray_menu()

    def change_language(self, lang):
        self.setup_translations(lang)
        self.retranslate_ui()

        # Update all other windows
        for widget in QApplication.topLevelWidgets():
            if widget != self and hasattr(widget, "retranslate_ui"):
                widget.retranslate_ui()

    def check_trigger_spam(self):
        """
        Check if hotkey is being triggered too frequently (3+ times in 1.5 seconds).
        Returns True if spam is detected.
        """
        current_time = time.time()

        # Add current trigger
        self.recent_triggers.append(current_time)

        # Remove old triggers outside the window
        self.recent_triggers = [
            t for t in self.recent_triggers if current_time - t <= self.TRIGGER_WINDOW
        ]

        # Check if we have too many triggers in the window
        return len(self.recent_triggers) >= self.MAX_TRIGGERS

    def load_config(self):
        """
        Load the configuration file.
        """
        self.config_path = os.path.join(os.path.dirname(sys.argv[0]), "config.json")
        logging.debug(f"Loading config from {self.config_path}")
        if os.path.exists(self.config_path):
            with open(self.config_path, "r") as f:
                self.config = json.load(f)
                logging.debug("Config loaded successfully")
        else:
            logging.debug("Config file not found")
            self.config = None

    def _migrate_config(self):
        """
        One-shot config migration. Catches any user up to the current schema
        (v9) regardless of where they started — v7, v8, or already current —
        in a single pass with at most one restart.

        Each version is gated on its own `is_config_file_updated_for_v{N}`
        flag, so re-running this is a no-op once everything's caught up.
        Bump CURRENT_CONFIG_VERSION and add a `# v{N}` block when adding a
        new migration step.

        v8 (introduced 2025):
          • Google removed Gemini 2.0 from the free API → bump model.
          • Obfuscate plaintext Gemini API keys (defeats Ctrl+F scanning).
          The custom-model input field didn't exist pre-v8, so any pre-v8
          model value is safe to overwrite — there's nothing custom to
          preserve.

        v9 (introduced 2026):
          • Google deprecated the Gemma 3 family. Migrate every v8 user on a
            now-deprecated preset to the new default (`gemini-flash-latest`)
            so they immediately land on the fast experience. They can opt
            into the unlimited-but-slow Gemma 4 options from the dropdown
            if they hit the 20/day Flash quota.
            Preserve custom model values (which DID exist by then) so a user
            who picked, say, `gemini-3.1-pro-preview` doesn't get reset.
          • SDK migration to `google-genai` is code-side only; nothing to
            do in config.
        """
        CURRENT_CONFIG_VERSION = 9
        # Default for new installs and migrating users.
        NEW_DEFAULT_MODEL = "gemini-flash-latest"
        # v8 -> v9 model mapping. Every retired preset is bumped to the new
        # default so users get the fast Flash-tier experience by default.
        V8_TO_V9_MAP = {
            "gemma-3-27b-it": NEW_DEFAULT_MODEL,
            "gemma-3-4b-it": NEW_DEFAULT_MODEL,
            "gemini-flash-lite-latest": NEW_DEFAULT_MODEL,
            # 'gemini-flash-latest' itself is already current — no entry needed.
        }

        # New user (no config yet) — onboarding will create a fresh, current
        # config; nothing to migrate.
        if not self.config:
            logging.debug("No config to migrate (new user)")
            return

        needs_v8 = not self.config.get("is_config_file_updated_for_v8", False)
        needs_v9 = not self.config.get("is_config_file_updated_for_v9", False)

        if not needs_v8 and not needs_v9:
            logging.debug("Config already up-to-date, no migration needed")
            return

        logging.info(
            f"Running config migration (needs_v8={needs_v8}, needs_v9={needs_v9})..."
        )

        config_changed = False
        gemini_config = self.config.get("providers", {}).get("Gemini (Recommended)")

        if gemini_config is not None:
            old_model = gemini_config.get("model_name", "")

            # v8: pre-v8 users didn't have a custom-model field, so we can
            # bump unconditionally. We skip the historical "v8 default of
            # gemma-3-27b-it" intermediate stop and jump straight to the
            # current default.
            if needs_v8:
                if old_model != NEW_DEFAULT_MODEL:
                    gemini_config["model_name"] = NEW_DEFAULT_MODEL
                    logging.info(
                        f'[v8] Bumped Gemini model "{old_model}" -> "{NEW_DEFAULT_MODEL}"'
                    )
                    config_changed = True

                # Obfuscate the API key. The helper is idempotent — already-
                # obfuscated keys (with the `enc:` prefix) pass through
                # unchanged.
                api_key = gemini_config.get("api_key", "")
                if api_key:
                    new_key = obfuscate_api_key(api_key)
                    if new_key != api_key:
                        gemini_config["api_key"] = new_key
                        logging.info("[v8] Obfuscated plaintext Gemini API key")
                        config_changed = True

            # v9: only runs for users coming from v8. Preserve tier choice via
            # the V8_TO_V9_MAP so an unlimited-tier user doesn't get silently
            # downgraded to a daily-quota model. Custom values (anything not
            # in the map) are left alone.
            elif needs_v9:
                new_model = V8_TO_V9_MAP.get(old_model)
                if new_model is not None and new_model != old_model:
                    gemini_config["model_name"] = new_model
                    logging.info(
                        f'[v9] Bumped Gemini model "{old_model}" -> "{new_model}"'
                    )
                    config_changed = True

        # Stamp every version flag up to current so we never re-run on
        # subsequent startups, even if no fields actually needed changing
        # (e.g., a v8 user who'd already picked a custom non-deprecated model).
        for n in range(8, CURRENT_CONFIG_VERSION + 1):
            self.config[f"is_config_file_updated_for_v{n}"] = True

        self.save_config(self.config)
        logging.info("Config migration complete")

        # Single restart popup, regardless of how many versions we jumped.
        if config_changed:
            # Use QMessageBox directly — signals aren't connected yet at this
            # point in __init__.
            QMessageBox.information(
                None,
                "Writing Tools Updated",
                "Writing Tools has just completed an internal update "
                "(your config.json was migrated to the current format).\n\n"
                "Please restart Writing Tools.",
            )
            sys.exit(0)

    def load_options(self):
        """
        Load the options file.
        """
        self.options_path = os.path.join(os.path.dirname(sys.argv[0]), "options.json")
        logging.debug(f"Loading options from {self.options_path}")
        if os.path.exists(self.options_path):
            with open(self.options_path, "r") as f:
                self.options = json.load(f)
                logging.debug("Options loaded successfully")
        else:
            logging.debug("Options file not found")
            self.options = None

    def save_config(self, config):
        """
        Save the configuration file.
        """
        with open(self.config_path, "w") as f:
            json.dump(config, f, indent=4)
            logging.debug("Config saved successfully")
        self.config = config

    def show_onboarding(self):
        """
        Show the onboarding window for first-time users.
        """
        logging.debug("Showing onboarding window")
        self.onboarding_window = ui.OnboardingWindow.OnboardingWindow(self)
        self.onboarding_window.close_signal.connect(self.exit_app)
        self.onboarding_window.show()

    @staticmethod
    def _to_pynput_hotkey(hotkey_str):
        """
        Convert a user-facing hotkey string ('ctrl+j', 'ctrl+alt+space') to
        pynput's `<ctrl>+j` / `<ctrl>+<alt>+<space>` format. Single-char keys
        stay as-is; multi-char keys (modifiers, named keys) get wrapped in <>.
        """
        return "+".join(
            f"{t}" if len(t) <= 1 else f"<{t}>" for t in hotkey_str.split("+")
        )

    def start_hotkey_listener(self):
        """
        Build a single `GlobalHotKeys` listener that handles both the main
        Writing Tools shortcut AND any per-button direct hotkeys defined in
        options.json. Per-button hotkeys fire the corresponding option
        immediately, skipping the popup.

        On conflict between a button hotkey and the global shortcut (or
        between two button hotkeys), the first registration wins and the
        later one is logged and skipped — the listener can't dispatch to
        two callbacks for the same combination anyway.
        """
        try:
            if self.hotkey_listener is not None:
                self.hotkey_listener.stop()
                self.hotkey_listener = None

            hotkey_map = {}

            # --- Global Writing Tools hotkey ----------------------------------
            orig_shortcut = self.config.get("shortcut", "ctrl+space")
            self.registered_hotkey = orig_shortcut
            try:
                global_parsed = self._to_pynput_hotkey(orig_shortcut)
                # Validate by parsing — raises if malformed.
                pykeyboard.HotKey.parse(global_parsed)

                def on_global_activate():
                    if self.paused:
                        return
                    logging.debug("triggered global hotkey")
                    self.hotkey_triggered_signal.emit()

                hotkey_map[global_parsed] = on_global_activate
                logging.debug(f"Registered global hotkey: {global_parsed}")
            except Exception as e:
                logging.error(f'Failed to parse global hotkey "{orig_shortcut}": {e}')

            # --- Per-button direct hotkeys ------------------------------------
            # Custom is excluded — it needs a typed instruction from the user,
            # so a "fire directly" hotkey doesn't make sense for it.
            if self.options:
                for button_name, button_cfg in self.options.items():
                    if button_name == "Custom":
                        continue
                    raw = (button_cfg.get("hotkey") or "").strip()
                    if not raw:
                        continue
                    try:
                        parsed = self._to_pynput_hotkey(raw)
                        # Same validation path as the global shortcut.
                        pykeyboard.HotKey.parse(parsed)
                    except Exception as e:
                        logging.error(
                            f'Invalid hotkey "{raw}" for button "{button_name}": {e}'
                        )
                        continue
                    if parsed in hotkey_map:
                        logging.warning(
                            f'Hotkey "{raw}" for button "{button_name}" '
                            f"conflicts with an already-registered binding; skipping"
                        )
                        continue
                    hotkey_map[parsed] = self._make_button_hotkey_callback(button_name)
                    logging.debug(
                        f"Registered button hotkey: {parsed} -> {button_name}"
                    )

            if not hotkey_map:
                logging.warning("No hotkeys to register")
                return

            self.hotkey_listener = pykeyboard.GlobalHotKeys(hotkey_map)
            self.hotkey_listener.start()
        except Exception as e:
            logging.error(f"Failed to register hotkey listener: {e}")

    def _make_button_hotkey_callback(self, button_name):
        """
        Build a callback that fires `button_name` directly, bypassing the
        popup. Closes over `button_name` so we can register many distinct
        callbacks in a single GlobalHotKeys map.

        The actual fire is bounced through the Qt event loop because pynput
        invokes callbacks on its listener thread; popup/clipboard work needs
        to happen on the main thread.
        """

        def callback():
            if self.paused:
                return
            logging.debug(f'Direct hotkey fired for button "{button_name}"')
            # Match the global hotkey's behaviour: cancel any in-flight
            # request so a new fire doesn't pile up on top of a previous one.
            if self.current_provider:
                self.current_provider.cancel()
                self.output_queue = ""
            # noinspection PyTypeChecker
            QtCore.QMetaObject.invokeMethod(
                self,
                "_fire_button_directly",
                QtCore.Qt.ConnectionType.QueuedConnection,
                QtCore.Q_ARG(str, button_name),
            )

        return callback

    @Slot(str)
    def _fire_button_directly(self, button_name):
        """
        Run a button's option without showing the popup — invoked by a
        per-button direct hotkey. Mirrors the relevant parts of
        `_show_popup`: set up the async clipboard capture, then hand off
        to the worker thread (`process_option`) which waits on the holder
        and dispatches the AI call.
        """
        logging.debug(f'Firing button "{button_name}" directly')

        # If the popup is currently visible (e.g., user opened it then
        # pressed a button hotkey), close it so it doesn't compete.
        if self.popup_window is not None and self.popup_window.isVisible():
            self.popup_window.close()

        # Sanity check: button must still exist in options. Could be stale
        # if options.json was edited externally between registration and
        # fire — skip gracefully rather than crash.
        if not self.options or button_name not in self.options:
            logging.warning(f'Button "{button_name}" no longer exists; ignoring hotkey')
            return

        self.current_text_holder = _SelectedTextHolder()
        self._fire_ctrl_c_and_capture_async(self.current_text_holder)

        # Keep the source window in sync for inline replacements via direct
        # hotkey (mirrors the main hotkey path in `on_hotkey_pressed`).
        self._capture_source_window()

        # Same worker path as a popup-button click. process_option_thread
        # waits on the holder, surfaces "Please select text…" if empty,
        # and routes window-mode options through the response window.
        self.process_option(button_name)

    def register_hotkey(self):
        """
        Register the global hotkey for activating Writing Tools.
        """
        logging.debug("Registering hotkey")
        self.start_hotkey_listener()
        logging.debug("Hotkey registered")

    def _capture_source_window(self):
        """
        Remember the window that currently has focus, so an inline
        replacement can return focus to it before pasting an AI
        replacement. Only meaningful on Linux/KDE, where kdotool can
        both read the active window and re-activate it. kdotool identifies
        windows by KWin UUID (`{xxxxxxxx-...-xxxxxxxxxxxx}`), not a
        decimal id, so the value is used verbatim.
        """
        if not (sys.platform.startswith("linux") and shutil.which("kdotool")):
            return
        try:
            result = subprocess.run(
                ["kdotool", "getactivewindow"],
                capture_output=True,
                text=True,
                timeout=3,
            )
        except Exception as e:
            logging.debug(f"Could not capture source window: {e}")
            return
        window_id = (result.stdout or "").strip()
        if result.returncode == 0 and window_id:
            self._source_window_id = window_id
            logging.debug(f"Captured source window: {window_id}")

    def on_hotkey_pressed(self):
        """
        Handle the hotkey press event.
        """
        logging.debug("Hotkey pressed")

        # Check for spam triggers
        if self.check_trigger_spam():
            logging.warning("Hotkey spam detected - quitting application")
            self.exit_app()
            return

        # Capture the active window ID on Wayland/Linux so we can return
        # focus there for the paste after the user selects an option.
        self._capture_source_window()

        # Original hotkey handling continues...
        if self.current_provider:
            logging.debug("Cancelling current provider's request")
            self.current_provider.cancel()
            self.output_queue = ""

        # noinspection PyTypeChecker
        QtCore.QMetaObject.invokeMethod(
            self, "_show_popup", QtCore.Qt.ConnectionType.QueuedConnection
        )

    @Slot()
    def _show_popup(self):
        """
        Show the popup window the moment the hotkey fires, and capture the
        user's selected text in parallel — popup display no longer waits on
        the clipboard. The old behaviour gated popup show on a 0.2-0.5s
        clipboard read, which on slower systems would time out and
        incorrectly fall back to the chat-only "Ask your AI" UI even when
        text *was* selected. We now assume text is always selected;
        `process_option_thread` waits on the holder before kicking off the
        AI request.
        """
        logging.debug("Showing popup window")

        # Fresh holder per popup. Fire Ctrl+C *before* we create the popup
        # so the keystroke is queued while focus is still on the user's
        # source app — the actual clipboard read happens in the background.
        self.current_text_holder = _SelectedTextHolder()
        self._fire_ctrl_c_and_capture_async(self.current_text_holder)

        try:
            if self.popup_window is not None:
                logging.debug("Existing popup window found")
                old_popup = self.popup_window
                if old_popup.isVisible():
                    logging.debug("Closing existing visible popup window")
                    old_popup.close()
                # A closed (or merely hidden) popup is never reused, so let
                # Qt actually destroy it instead of leaking one window per
                # hotkey press.
                old_popup.deleteLater()
                self.popup_window = None
            logging.debug("Creating new popup window")
            self.popup_window = ui.CustomPopupWindow.CustomPopupWindow(self)

            # Set the window icon
            icon_path = os.path.join(
                os.path.dirname(sys.argv[0]), "icons", "app_icon.png"
            )
            if os.path.exists(icon_path):
                self.setWindowIcon(QtGui.QIcon(icon_path))
            # Get the screen containing the cursor
            cursor_pos = QCursor.pos()
            screen = QGuiApplication.screenAt(cursor_pos)
            if screen is None:
                screen = QGuiApplication.primaryScreen()
            screen_geometry = screen.geometry()
            logging.debug(f"Cursor is on screen: {screen.name()}")
            logging.debug(f"Screen geometry: {screen_geometry}")
            # Show the popup to get its size
            self.popup_window.show()
            self.popup_window.adjustSize()
            # Ensure the popup it's focused, even on lower-end machines
            self.popup_window.activateWindow()
            QtCore.QTimer.singleShot(100, self.popup_window.custom_input.setFocus)

            popup_width = self.popup_window.width()
            popup_height = self.popup_window.height()
            # Calculate position
            x = cursor_pos.x()
            y = cursor_pos.y() + 20  # 20 pixels below cursor
            # Adjust if the popup would go off the right edge of the screen
            if x + popup_width > screen_geometry.right():
                x = screen_geometry.right() - popup_width
            # Adjust if the popup would go off the bottom edge of the screen
            if y + popup_height > screen_geometry.bottom():
                y = cursor_pos.y() - popup_height - 10  # 10 pixels above cursor
            self.popup_window.move(x, y)
            logging.debug(f"Popup window moved to position: ({x}, {y})")
        except Exception as e:
            logging.error(f"Error showing popup window: {e}", exc_info=True)

    @staticmethod
    def _read_primary_selection():
        """
        Return the current PRIMARY (mouse) selection on Linux, or '' if the
        platform doesn't have one / nothing is selected.

        This is the most reliable way to obtain "the text the user just
        selected": no keystroke injection and no clipboard round-trip.

        It matters most on Wayland, where `pynput`'s synthetic Ctrl+C only
        reaches XWayland clients — native Wayland apps never copy anything.
        The old fallback then read whatever was already in the clipboard
        (e.g. text copied minutes earlier) and happily sent that to the AI.
        """
        if not sys.platform.startswith("linux"):
            return ""

        commands = []
        # On a Wayland session `wl-paste` sees PRIMARY for both native clients
        # and XWayland apps (XWayland bridges the two), so there is no need to
        # also try xclip — and skipping it halves the number of processes the
        # change watcher spawns per poll.
        if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
            commands.append(["wl-paste", "-n", "-t", "text", "-p"])
        elif os.environ.get("DISPLAY") and shutil.which("xclip"):
            commands.append(["xclip", "-selection", "primary", "-o"])

        for command in commands:
            try:
                result = subprocess.run(
                    command, capture_output=True, text=True, timeout=1.0
                )
            except Exception as e:
                logging.debug(f"Primary selection read failed via {command[0]}: {e}")
                continue
            if result.returncode == 0 and result.stdout:
                return result.stdout
        return ""

    def _primary_selection_is_fresh(self, text):
        """
        Decide whether `text`, just read from PRIMARY, may be treated as the
        user's selection for the current hotkey press.

        Accepted when:
        - it is the selection captured last time (the user is re-running an
          option on the same text without re-selecting it), or
        - it differs from the selection seen at the last capture (or at
          startup) — i.e. the user highlighted something new.

        Rejected otherwise, forcing the clipboard path so leftover text
        (e.g. logs selected before the app launched) is never mistaken for
        the current selection. This is a direct comparison against the last
        value we acted on, so it does not depend on any sampling phase: a
        selection made a moment before the hotkey press is still accepted.
        """
        if not text.strip():
            return False
        if text == self._last_captured_selection:
            return True
        return text != self._primary_selection_last_seen

    @staticmethod
    def _press_ctrl(key):
        """
        Press Ctrl+<key> with pynput. Returns True when the events were sent.

        On Wayland this only reaches XWayland clients; use `_paste_shortcut`
        when the keystroke must work in native Wayland apps.
        """
        try:
            kbrd = pykeyboard.Controller()
            kbrd.press(pykeyboard.Key.ctrl.value)
            kbrd.press(key)
            kbrd.release(key)
            kbrd.release(pykeyboard.Key.ctrl.value)
            return True
        except Exception as e:
            logging.error(f"Error injecting Ctrl+{key}: {e}")
            return False

    @staticmethod
    def _ydotool_environment():
        """
        Return an environment pointing ydotool at a reachable ydotoold
        socket, or None if none exists.

        Distributions disagree on the socket path, and ydotool's compiled-in
        default (/run/user/$UID/.ydotool_socket) does not match a daemon
        started with `-s /tmp/.ydotool_socket`.
        """
        candidates = [os.environ.get("YDOTOOL_SOCKET")]
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
        if runtime_dir:
            candidates.append(os.path.join(runtime_dir, ".ydotool_socket"))
        candidates.append("/tmp/.ydotool_socket")
        for socket_path in candidates:
            if socket_path and os.path.exists(socket_path):
                env = dict(os.environ)
                env["YDOTOOL_SOCKET"] = socket_path
                return env
        return None

    @staticmethod
    def _inject_ctrl(pynput_key, key_name, keycode, allow_pynput=True):
        """
        Send Ctrl+<key_name> to the focused window.

        Returns True if an injector accepted the request. pynput cannot
        deliver synthetic keystrokes to native Wayland clients (compositors
        only accept injected input through privileged protocols), which is
        why both the replacement options and the Ctrl+Insert copy fallback
        silently did nothing under KDE Wayland. Use a dev-input injector
        there; pynput remains the path for X11 (and XWayland as a last
        resort).

        `pynput_key` is what pynput should press ('v' or
        `pykeyboard.Key.insert.value`); `key_name`/`keycode` are the
        equivalents for the command-line injectors.
        """
        on_wayland = bool(os.environ.get("WAYLAND_DISPLAY"))
        if sys.platform.startswith("linux") and on_wayland:
            # ydotool: writes through uinput via its daemon, so it works on
            # every compositor. 29 is the Linux keycode for Ctrl.
            if shutil.which("ydotool"):
                try:
                    result = subprocess.run(
                        [
                            "ydotool",
                            "key",
                            "29:1",
                            f"{keycode}:1",
                            f"{keycode}:0",
                            "29:0",
                        ],
                        env=WritingToolApp._ydotool_environment() or dict(os.environ),
                        capture_output=True,
                        text=True,
                        timeout=3,
                    )
                    if result.returncode == 0:
                        logging.debug(f"Injected Ctrl+{key_name} via ydotool")
                        return True
                    logging.debug(
                        f"ydotool Ctrl+{key_name} failed: {result.stderr.strip()}"
                    )
                except Exception as e:
                    logging.debug(f"ydotool Ctrl+{key_name} failed: {e}")

            # dotool: no daemon, writes straight to /dev/uinput.
            if shutil.which("dotool") and os.access("/dev/uinput", os.W_OK):
                try:
                    result = subprocess.run(
                        ["dotool"],
                        input=f"key ctrl+{key_name}\n",
                        capture_output=True,
                        text=True,
                        timeout=3,
                    )
                    if result.returncode == 0:
                        logging.debug(f"Injected Ctrl+{key_name} via dotool")
                        return True
                    logging.debug(
                        f"dotool Ctrl+{key_name} failed: {result.stderr.strip()}"
                    )
                except Exception as e:
                    logging.debug(f"dotool Ctrl+{key_name} failed: {e}")

            # wtype: virtual-keyboard protocol. Works on wlroots-based
            # compositors; KWin does not expose this protocol (Plasma 6.8).
            if shutil.which("wtype"):
                try:
                    result = subprocess.run(
                        ["wtype", "-M", "ctrl", "-k", key_name, "-m", "ctrl"],
                        capture_output=True,
                        text=True,
                        timeout=3,
                    )
                    if result.returncode == 0:
                        logging.debug(f"Injected Ctrl+{key_name} via wtype")
                        return True
                    logging.debug(
                        f"wtype Ctrl+{key_name} failed: {result.stderr.strip()}"
                    )
                except Exception as e:
                    logging.debug(f"wtype Ctrl+{key_name} failed: {e}")

        if allow_pynput and WritingToolApp._press_ctrl(pynput_key):
            logging.debug(f"Injected Ctrl+{key_name} via pynput")
            return True
        return False

    @staticmethod
    def _paste_shortcut():
        """
        Paste the clipboard into the focused window.

        On Wayland this deliberately does not fake success with pynput: the
        event never reaches a native app, and a silent no-op is worse than
        telling the user to paste manually.
        """
        return WritingToolApp._inject_ctrl(
            "v", "v", 47, allow_pynput=not os.environ.get("WAYLAND_DISPLAY")
        )

    @staticmethod
    def _read_clipboard(timeout=1.5):
        """
        Read the clipboard text without risking an indefinite block.

        `wl-paste` can wait forever when the selection owner has gone away
        (a crashed app, a killed wl-copy), and pyperclip has no timeout. The
        polling loop calls this every 50 ms, so a hang there would freeze the
        capture thread forever.
        """
        if (
            sys.platform.startswith("linux")
            and os.environ.get("WAYLAND_DISPLAY")
            and shutil.which("wl-paste")
        ):
            try:
                result = subprocess.run(
                    ["wl-paste", "-n", "-t", "text"],
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                )
            except Exception as e:
                logging.debug(f"Clipboard read timed out or failed: {e}")
                return ""
            return result.stdout if result.returncode == 0 else ""

        try:
            return pyperclip.paste() or ""
        except Exception as e:
            logging.debug(f"Clipboard read failed: {e}")
            return ""

    def _notify_result_in_clipboard(self):
        """Tell the user the result is on the clipboard (paste was blocked)."""
        message = (
            "Could not paste automatically.\n\n"
            "The result is in your clipboard — press Ctrl+V to insert it."
        )
        try:
            tray_icon = getattr(self, "tray_icon", None)
            if tray_icon is not None and tray_icon.isVisible():
                tray_icon.showMessage(
                    "WritingTools",
                    message,
                    QtWidgets.QSystemTrayIcon.MessageIcon.Information,
                    6000,
                )
                return
        except Exception as e:
            logging.debug(f"Could not show tray notification: {e}")
        self.show_message_signal.emit("WritingTools", message)

    @staticmethod
    def _restore_clipboard(text, pasted_text=None):
        """
        Put back whatever the user had on the clipboard before the paste.

        If `pasted_text` is given, only restore while the clipboard still
        contains it — the user (or another capture) may have put something
        else there in the meantime, and that must not be overwritten.
        """
        try:
            if (
                pasted_text is not None
                and WritingToolApp._read_clipboard() != pasted_text
            ):
                logging.debug("Clipboard changed since paste; not restoring it")
                return
            pyperclip.copy(text)
        except Exception as e:
            logging.error(f"Error restoring clipboard: {e}")

    def _paste_replacement(self, clipboard_backup, pasted_text):
        """
        Inject the paste for a replacement option and then put the user's own
        clipboard content back.
        """
        # Try to re-activate the window that was active when the hotkey fired,
        # so that the paste goes back to the application where the user selected
        # the text.
        if self._source_window_id:
            try:
                subprocess.run(
                    ["kdotool", "windowactivate", self._source_window_id],
                    capture_output=True,
                    text=True,
                    timeout=3,
                )
                # Give the window a moment to gain focus without blocking the
                # GUI thread; re-enter once it should be active.
                QtCore.QTimer.singleShot(
                    200,
                    lambda: self._finish_paste_replacement(
                        clipboard_backup, pasted_text
                    ),
                )
                return
            except Exception as e:
                logging.debug(f"Failed to re-activate source window: {e}")

        self._finish_paste_replacement(clipboard_backup, pasted_text)

    def _finish_paste_replacement(self, clipboard_backup, pasted_text):
        """Send the paste keystroke, then restore the user's own clipboard."""
        if self._paste_shortcut():
            # On Wayland the target app fetches clipboard data asynchronously
            # after the key event, so give it a moment before restoring.
            QtCore.QTimer.singleShot(
                1000, lambda: self._restore_clipboard(clipboard_backup, pasted_text)
            )
            return

        logging.warning(
            "Automatic paste failed; leaving the result in the clipboard for "
            "manual pasting"
        )
        self._notify_result_in_clipboard()

    def _fire_ctrl_c_and_capture_async(self, holder):
        """
        Capture the user's selected text.

        On Linux the PRIMARY selection is read directly (see
        `_read_primary_selection`), which works on X11 and Wayland alike and
        leaves the clipboard untouched. Only a *fresh* primary selection is
        used (see `_primary_selection_is_fresh`); leftover text from before
        the hotkey press falls through to the clipboard path.

        If there is no fresh primary selection (Windows, a stale selection,
        or an app that doesn't publish one), inject the copy shortcut and
        poll the clipboard.

        The PRIMARY read is a single quick subprocess. The clipboard fallback
        injects the copy shortcut synchronously (it must land while focus is
        still on the source app, before the popup opens) and then returns;
        the actual clipboard polling happens on a background thread.
        """
        primary_text = self._read_primary_selection()
        if self._primary_selection_is_fresh(primary_text):
            self._last_captured_selection = primary_text
            self._primary_selection_last_seen = primary_text
            holder.text = primary_text
            logging.debug(
                f"Captured primary selection (len={len(primary_text)}): "
                f"{primary_text[:80].replace(chr(10), ' ')!r}"
            )
            holder.ready.set()
            return
        if primary_text.strip():
            logging.warning(
                "Ignoring stale primary selection (unchanged since startup or "
                f"last capture, len={len(primary_text)}): "
                f"{primary_text[:80].replace(chr(10), ' ')!r}"
            )

        clipboard_backup = self._read_clipboard()

        self.clear_clipboard()

        # Ctrl+Insert is the traditional Unix "copy" shortcut. Prefer it over
        # Ctrl+C because Ctrl+C is SIGINT in terminals, and an injected Ctrl+C
        # into the terminal the user is selecting from would interrupt
        # whatever is running there.
        linux = sys.platform.startswith("linux")
        if linux:
            # Same policy as the paste path: pynput cannot reach native
            # Wayland clients, so don't report success for an event that goes
            # nowhere.
            injected = self._inject_ctrl(
                pykeyboard.Key.insert.value,
                "insert",
                110,
                allow_pynput=not os.environ.get("WAYLAND_DISPLAY"),
            )
            if not injected:
                logging.warning(
                    "No injector available to copy the selection "
                    "(install ydotool or dotool)"
                )
        else:
            injected = self._press_ctrl("c")
            if injected:
                logging.debug("Injected Ctrl+C to copy selection")

        if injected and linux and os.environ.get("WAYLAND_DISPLAY"):
            # The popup is created as soon as this returns and would take
            # keyboard focus. Give the compositor time to deliver the copy
            # to the source window first.
            time.sleep(0.1)

        def _poll_clipboard():
            # Lock so concurrent hotkey presses don't trample each other's
            # in-flight captures.
            with self._capture_lock:
                text = ""
                try:
                    deadline = time.time() + 2.0
                    cleared = False
                    while time.time() < deadline:
                        current = self._read_clipboard(1.0)
                        if current:
                            # Never accept pre-existing clipboard content.
                            # If the clear wasn't observed (clipboard managers
                            # can restore the previous entry) require the
                            # value to have actually changed; otherwise Ctrl+C
                            # failed and the old clipboard would masquerade as
                            # the user's selection.
                            if cleared or current != clipboard_backup:
                                text = current
                                break
                        else:
                            cleared = True
                        time.sleep(0.05)
                    holder.text = text
                    if text:
                        logging.debug(
                            f"Captured selected text (len={len(text)}): "
                            f"{text[:80].replace(chr(10), ' ')!r}"
                        )
                    else:
                        logging.warning(
                            "No new selected text detected (clipboard did not change)"
                        )
                finally:
                    try:
                        pyperclip.copy(clipboard_backup)
                    except Exception as e:
                        logging.error(f"Error restoring clipboard: {e}")
                    holder.ready.set()

        threading.Thread(target=_poll_clipboard, daemon=True).start()

    @staticmethod
    def clear_clipboard():
        """
        Clear the system clipboard.
        """
        try:
            pyperclip.copy("")
        except Exception as e:
            logging.error(f"Error clearing clipboard: {e}")

    def process_option(self, option, custom_change=None):
        """
        Spawn a worker thread that waits for the asynchronous clipboard
        capture and then runs the chosen option. Kept as a thin wrapper so
        the popup's click handler returns immediately and the GUI thread
        is never blocked on the clipboard read.
        """
        logging.debug(f"Processing option: {option}")

        # Drop the stale ref so a previous run's late-arriving response can't
        # land in a now-irrelevant window (and so `hasattr` keeps meaning
        # "an inline replacement is in progress" for the providers). The new
        # window, if any, is created by the worker via
        # `_setup_response_window` once the text is in.
        #
        # Close the old window explicitly instead of relying on refcount GC:
        # a window that is still referenced elsewhere (follow-up timer, Qt
        # signal connection, ...) would otherwise stay visible on top of the
        # new result and look like the new option did nothing.
        old_window = self.current_response_window
        self.current_response_window = None
        if old_window is not None:
            old_window.close()
            old_window.deleteLater()

        threading.Thread(
            target=self.process_option_thread, args=(option, custom_change), daemon=True
        ).start()

    @Slot(str, str)
    def _setup_response_window(self, option, selected_text):
        """
        Open the response window and seed its chat history. Called from
        `process_option_thread` via `BlockingQueuedConnection` so the
        worker can rely on the window existing before it dispatches the
        AI request.
        """
        self.current_response_window = self.show_response_window(option, selected_text)
        self.current_response_window.chat_history = [
            {
                "role": "user",
                "content": f"Original text to {option.lower()}:\n\n{selected_text}",
            }
        ]

    def process_option_thread(self, option, custom_change=None):
        """
        Worker: wait for the background clipboard capture to land, then
        either open a response window (for window-mode options) or set up
        for inline replacement, and finally run the AI request.
        """
        logging.debug(f"Starting processing thread for option: {option}")

        # Typically near-instant since the user took time to read the popup
        # and click. The 3s ceiling is a safety net for genuinely sluggish
        # systems; if the 2s polling deadline in the capture thread tripped
        # first, the event is already set and this returns immediately.
        holder = self.current_text_holder
        if holder is None or not holder.ready.wait(timeout=3.0):
            logging.warning("Timed out waiting for selected text capture")
        selected_text = (holder.text if holder else "") or ""

        if not selected_text.strip():
            # The chat-mode fallback that used to fire here was removed when
            # popup show became instant — we no longer have a way to detect
            # "user wants to chat" vs "capture failed", so we pick the safer
            # interpretation and surface the error.
            self.show_message_signal.emit(
                "Error",
                "No text selected.\n\n"
                "Select the text you want to use, then press the hotkey again.",
            )
            return

        response_window = None
        if self.options[option]["open_in_window"]:
            QtCore.QMetaObject.invokeMethod(
                self,
                "_setup_response_window",
                QtCore.Qt.ConnectionType.BlockingQueuedConnection,
                QtCore.Q_ARG(str, option),
                QtCore.Q_ARG(str, selected_text),
            )
            # Remember the window this request belongs to. Re-reading
            # `current_response_window` when the response arrives is racy:
            # if the user fires another option meanwhile, that attribute
            # points at a newer window and this request's answer would be
            # written into it.
            response_window = getattr(self, "current_response_window", None)

        try:
            selected_prompt = self.options.get(option, ("", ""))
            prompt_prefix = selected_prompt["prefix"]
            system_instruction = selected_prompt["instruction"]
            if option == "Custom":
                prompt = f"{prompt_prefix}Described change: {custom_change}\n\nText: {selected_text}"
            else:
                prompt = f"{prompt_prefix}{selected_text}"

            self.output_queue = ""

            logging.debug(f"Getting response from provider for option: {option}")

            if self.options[option]["open_in_window"]:
                logging.debug("Getting response for window display")
                response = self.current_provider.get_response(
                    system_instruction, prompt, return_response=True
                )
                logging.debug(
                    f"Got response of length: {len(response) if response else 0}"
                )

                if (
                    response_window is not None
                    and getattr(self, "current_response_window", None)
                    is response_window
                ):
                    # noinspection PyTypeChecker
                    QtCore.QMetaObject.invokeMethod(
                        response_window,
                        "set_text",
                        QtCore.Qt.ConnectionType.QueuedConnection,
                        QtCore.Q_ARG(str, response),
                    )
                    logging.debug("Invoked set_text on response window")
                else:
                    logging.debug(
                        "Response window was closed or replaced; discarding response"
                    )
            else:
                logging.debug("Getting response for direct replacement")
                self.current_provider.get_response(system_instruction, prompt)
                logging.debug("Response processed")

        except Exception as e:
            logging.error(f"An error occurred: {e}", exc_info=True)

            if "Resource has been exhausted" in str(e):
                self.show_message_signal.emit(
                    "Error - Rate Limit Hit",
                    "Whoops! You've hit the per-minute rate limit of the Gemini API. Please try again in a few moments.\n\nIf this happens often, simply switch to a Gemini model with a higher usage limit in Settings.",
                )
            else:
                self.show_message_signal.emit("Error", f"An error occurred: {e}")

    @Slot(str, str)
    def show_message_box(self, title, message):
        """
        Show a message box with the given title and message.
        """
        QMessageBox.warning(None, title, message)

    def show_response_window(self, option, text):
        """
        Show the response in a new window instead of pasting it.
        """
        response_window = ui.ResponseWindow.ResponseWindow(self, f"{option} Result")
        response_window.selected_text = text  # Store the text for regeneration
        response_window.bring_to_front()
        return response_window

    def replace_text(self, new_text):
        """
        Replaces the text by pasting in the LLM generated text. With "Key Points" and "Summary", invokes a window with the output instead.
        """
        error_message = "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"

        # Confirm new_text exists and is a string
        if new_text and isinstance(new_text, str):
            self.output_queue += new_text
            current_output = (
                self.output_queue.strip()
            )  # Strip whitespace for comparison

            # If the new text is the error message, show a message box
            if current_output == error_message:
                self.show_message_signal.emit(
                    "Error", "The text is incompatible with the requested change."
                )
                return

            # Check if we're building up to the error message (to prevent partial pasting)
            if len(current_output) <= len(error_message):
                clean_current = "".join(current_output.split())
                clean_error = "".join(error_message.split())
                if clean_current == clean_error[: len(clean_current)]:
                    return

            logging.debug("Processing output text")
            try:
                # For Summary and Key Points, show in response window
                if self.current_response_window:
                    self.current_response_window.append_text(new_text)

                    # If this is the initial response, add it to chat history
                    if (
                        len(self.current_response_window.chat_history) == 1
                    ):  # Only original text exists
                        self.current_response_window.chat_history.append(
                            {
                                "role": "assistant",
                                "content": self.output_queue.rstrip("\n"),
                            }
                        )
                else:
                    # For other options, paste the AI output over the
                    # selection in the focused app.
                    clipboard_backup = self._read_clipboard()
                    cleaned_text = self.output_queue.rstrip("\n")
                    pyperclip.copy(cleaned_text)

                    # wl-copy (pyperclip's Wayland backend) needs a moment to
                    # take ownership of the selection; injecting Ctrl+V
                    # immediately can reach the app while the clipboard is
                    # still empty.
                    QtCore.QTimer.singleShot(
                        150,
                        lambda text=clipboard_backup,
                        pasted=cleaned_text: self._paste_replacement(text, pasted),
                    )

                if self.current_response_window is None:
                    self.output_queue = ""

            except Exception as e:
                logging.error(f"Error processing output: {e}")
        else:
            logging.debug("No new text to process")

    def create_tray_icon(self):
        """
        Create the system tray icon for the application.
        """
        if self.tray_icon:
            logging.debug("Tray icon already exists")
            return

        logging.debug("Creating system tray icon")
        icon_path = os.path.join(os.path.dirname(sys.argv[0]), "icons", "app_icon.png")
        if not os.path.exists(icon_path):
            logging.warning(f"Tray icon not found at {icon_path}")
            # Use a default icon if not found
            self.tray_icon = QtWidgets.QSystemTrayIcon(self)
        else:
            self.tray_icon = QtWidgets.QSystemTrayIcon(QtGui.QIcon(icon_path), self)
        # Set the tooltip (hover name) for the tray icon
        self.tray_icon.setToolTip("WritingTools")
        self.tray_menu = QtWidgets.QMenu()
        self.tray_icon.setContextMenu(self.tray_menu)

        self.update_tray_menu()
        self.tray_icon.show()
        logging.debug("Tray icon displayed")

    def update_tray_menu(self):
        """
        Update the tray menu with all menu items, including pause functionality
        and proper translations.
        """
        self.tray_menu.clear()

        # Apply dark mode styles using darkdetect
        self.apply_dark_mode_styles(self.tray_menu)

        # Settings menu item
        settings_action = self.tray_menu.addAction(self._("Settings"))
        settings_action.triggered.connect(self.show_settings)

        # Pause/Resume toggle action
        self.toggle_action = self.tray_menu.addAction(
            self._("Resume") if self.paused else self._("Pause")
        )
        self.toggle_action.triggered.connect(self.toggle_paused)

        # About menu item
        about_action = self.tray_menu.addAction(self._("About"))
        about_action.triggered.connect(self.show_about)

        # Exit menu item
        exit_action = self.tray_menu.addAction(self._("Exit"))
        exit_action.triggered.connect(self.exit_app)

    def toggle_paused(self):
        """Toggle the paused state of the application."""
        logging.debug("Toggle paused state")
        self.paused = not self.paused
        self.toggle_action.setText(self._("Resume") if self.paused else self._("Pause"))
        logging.debug("App is paused" if self.paused else "App is resumed")

    @staticmethod
    def apply_dark_mode_styles(menu):
        """
        Apply styles to the tray menu based on system theme using darkdetect.
        """
        is_dark_mode = darkdetect.isDark()
        palette = menu.palette()

        if is_dark_mode:
            logging.debug("Tray icon dark")
            # Dark mode colors
            palette.setColor(
                QtGui.QPalette.Window, QtGui.QColor("#2d2d2d")
            )  # Dark background
            palette.setColor(
                QtGui.QPalette.WindowText, QtGui.QColor("#ffffff")
            )  # White text
        else:
            logging.debug("Tray icon light")
            # Light mode colors
            palette.setColor(
                QtGui.QPalette.Window, QtGui.QColor("#ffffff")
            )  # Light background
            palette.setColor(
                QtGui.QPalette.WindowText, QtGui.QColor("#000000")
            )  # Black text

        menu.setPalette(palette)

    """
    The function below (process_followup_question) processes follow-up questions in the chat interface for Summary, Key Points, and Table operations.

    This method handles the complex interaction between the UI, chat history, and AI providers:

    1. Chat History Management:
    - Maintains a list of all messages (original text, summary, follow-ups)
    - Properly formats roles (user/assistant) for each message
    - Preserves conversation context across multiple questions (until the Window is closed)

    2. Provider-Specific Handling:
    a) Gemini:
        - Converts internal roles to Gemini's user/model format
        - Uses chat sessions with proper history formatting
        - Maintains context through chat.send_message()
    
    b) OpenAI-compatible:
        - Uses standard OpenAI message array format
        - Includes system instruction and full conversation history
        - Properly maps internal roles to OpenAI roles

    3. Flow:
    a) User asks follow-up question
    b) Question is added to chat history
    c) Full history is formatted for the current provider
    d) Response is generated while maintaining context
    e) Response is displayed in chat UI
    f) New response is added to history for future context

    4. Threading:
    - Runs in a separate thread to prevent UI freezing
    - Uses signals to safely update UI from background thread
    - Handles errors too

    Args:
        response_window: The ResponseWindow instance managing the chat UI
        question: The follow-up question from the user

    This implementation is a bit convoluted, but it allows us to manage chat history & model roles across both providers! :3
    """

    def process_followup_question(self, response_window, question):
        """
        Process a follow-up question in the chat window.
        """
        logging.debug(f"Processing follow-up question: {question}")

        def process_thread():
            logging.debug("Starting follow-up processing thread")
            try:
                if not response_window.chat_history:
                    logging.error("No chat history found")
                    self.show_message_signal.emit("Error", "Chat history not found")
                    return

                # Add current question to chat history
                response_window.chat_history.append(
                    {"role": "user", "content": question}
                )

                # Get chat history
                history = response_window.chat_history.copy()

                # System instruction based on original option
                system_instruction = "You are a helpful AI assistant. Provide clear and direct responses, maintaining the same format and style as your previous responses. If appropriate, use Markdown formatting to make your response more readable."

                logging.debug("Sending request to AI provider")

                # Format conversation differently based on provider
                if isinstance(self.current_provider, GeminiProvider):
                    # Gemini takes the system instruction via its config object,
                    # not as an in-history message. We pass the raw chat history
                    # (user/assistant turns); GeminiProvider handles role mapping
                    # and drops any "system" entries internally.
                    response_text = self.current_provider.get_response(
                        system_instruction, history, return_response=True
                    )

                elif isinstance(self.current_provider, OllamaProvider):  #
                    # For Ollama, prepare messages with system instruction and history
                    messages = [{"role": "system", "content": system_instruction}]

                    for msg in history:
                        messages.append(
                            {"role": msg["role"], "content": msg["content"]}
                        )

                    # Get response from Ollama
                    response_text = self.current_provider.get_response(
                        system_instruction, messages, return_response=True
                    )

                else:
                    # For OpenAI/compatible providers, prepare messages array, add system message
                    messages = [{"role": "system", "content": system_instruction}]

                    # Add history messages (including latest question)
                    for msg in history:
                        # Convert 'assistant' role to 'assistant' for OpenAI
                        role = "assistant" if msg["role"] == "assistant" else "user"
                        messages.append({"role": role, "content": msg["content"]})

                    # Get response by passing the full messages array
                    response_text = self.current_provider.get_response(
                        system_instruction,
                        messages,  # Pass messages array directly
                        return_response=True,
                    )

                logging.debug(f"Got response of length: {len(response_text)}")

                # Add response to chat history
                response_window.chat_history.append(
                    {"role": "assistant", "content": response_text}
                )

                # Emit response via signal
                self.followup_response_signal.emit(response_text)

            except Exception as e:
                logging.error(
                    f"Error processing follow-up question: {e}", exc_info=True
                )

                if "Resource has been exhausted" in str(e):
                    self.show_message_signal.emit(
                        "Error - Rate Limit Hit",
                        "Whoops! You've hit the per-minute rate limit of the Gemini API. Please try again in a few moments.\n\nIf this happens often, simply switch to a Gemini model with a higher usage limit in Settings.",
                    )
                    self.followup_response_signal.emit(
                        "Sorry, an error occurred while processing your question."
                    )
                else:
                    self.show_message_signal.emit("Error", f"An error occurred: {e}")
                    self.followup_response_signal.emit(
                        "Sorry, an error occurred while processing your question."
                    )

        # Start the thread
        threading.Thread(target=process_thread, daemon=True).start()

    def show_settings(self, providers_only=False):
        """
        Show the settings window.
        """
        logging.debug("Showing settings window")
        # Always create a new settings window to handle providers_only correctly
        self.settings_window = ui.SettingsWindow.SettingsWindow(
            self, providers_only=providers_only
        )
        self.settings_window.close_signal.connect(self.exit_app)
        self.settings_window.retranslate_ui()
        self.settings_window.show()

    def show_about(self):
        """
        Show the about window.
        """
        logging.debug("Showing about window")
        if not self.about_window:
            self.about_window = ui.AboutWindow.AboutWindow()
        self.about_window.show()

    def setup_ctrl_c_listener(self):
        """
        Listener for Ctrl+C to exit the app.
        """
        signal.signal(
            signal.SIGINT, lambda signum, frame: self.handle_sigint(signum, frame)
        )
        # This empty timer is needed to make sure that the sigint handler gets checked inside the main loop:
        # without it, the sigint handle would trigger only when an event is triggered, either by a hotkey combination
        # or by another GUI event like spawning a new window. With this we trigger it every 100ms with an empy lambda
        # so that the signal handler gets checked regularly.
        self.ctrl_c_timer = QtCore.QTimer()
        self.ctrl_c_timer.start(100)
        self.ctrl_c_timer.timeout.connect(lambda: None)

    def handle_sigint(self, signum, frame):
        """
        Handle the SIGINT signal (Ctrl+C) to exit the app gracefully.
        """
        logging.info("Received SIGINT. Exiting...")
        self.exit_app()

    def exit_app(self):
        """
        Exit the application.
        """
        logging.debug("Stopping the listener")
        if self.hotkey_listener is not None:
            self.hotkey_listener.stop()
        logging.debug("Exiting application")
        self.quit()
