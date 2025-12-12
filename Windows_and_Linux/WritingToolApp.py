import gettext
import json
import logging
import os
import signal
import sys
import threading
import time
import sys

import darkdetect
import pyperclip
from pynput import keyboard as pykeyboard
from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import QLocale, Signal, Slot
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtWidgets import QApplication, QMessageBox

import ui.AboutWindow
import ui.CustomPopupWindow
import ui.OnboardingWindow
import ui.ResponseWindow
import ui.SettingsWindow
from aiprovider import GeminiProvider, OllamaProvider, OpenAICompatibleProvider
from update_checker import UpdateChecker


_ = gettext.gettext


def get_session_type() -> str:
    # XDG_SESSION_TYPE is 'x11' or 'wayland'
    return os.environ.get("XDG_SESSION_TYPE", "x11").lower()


SESSION_TYPE = get_session_type()

from backends.x11_backend import X11Backend
from backends.wayland_backend import WaylandBackend


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
        self.TRIGGER_WINDOW = 3.0  # Time window in seconds
        self.MAX_TRIGGERS = (
            3  # Max allowed triggers in window (increased for Wayland compatibility)
        )
        self.last_hotkey_time = 0  # Track last hotkey press time
        self.HOTKEY_DEBOUNCE_TIME = 0.5  # Minimum time between hotkey presses
        self.hotkey_processing = False  # Prevent concurrent hotkey processing

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
        Check if hotkey is being triggered too frequently.
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
        # Increased threshold for better Wayland compatibility
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

    def start_hotkey_listener(self):
        """
        Create listener for hotkeys on Linux/Mac.
        """
        orig_shortcut = self.config.get("shortcut", "ctrl+space")
        # Parse the shortcut string, for example ctrl+alt+h -> <ctrl>+<alt>+h
        shortcut = "+".join(
            [f"{t}" if len(t) <= 1 else f"<{t}>" for t in orig_shortcut.split("+")]
        )
        logging.debug(f"Registering global hotkey for shortcut: {shortcut}")
        try:
            if self.hotkey_listener is not None:
                self.hotkey_listener.stop()

            def on_activate():
                if self.paused:
                    return
                logging.debug("triggered hotkey")
                self.hotkey_triggered_signal.emit()  # Emit the signal when hotkey is pressed

            # Define the hotkey combination
            hotkey = pykeyboard.HotKey(pykeyboard.HotKey.parse(shortcut), on_activate)
            self.registered_hotkey = orig_shortcut

            # Helper function to standardize key event
            def for_canonical(f):
                return lambda k: f(self.hotkey_listener.canonical(k))

            # Create a listener and store it as an attribute to stop it later
            self.hotkey_listener = pykeyboard.Listener(
                on_press=for_canonical(hotkey.press),
                on_release=for_canonical(hotkey.release),
            )

            # Start the listener
            self.hotkey_listener.start()
        except Exception as e:
            logging.error(f"Failed to register hotkey: {e}")

    def register_hotkey(self):
        """
        Register the global hotkey for activating Writing Tools.
        """
        logging.debug("Registering hotkey")
        self.start_hotkey_listener()
        logging.debug("Hotkey registered")

    def on_hotkey_pressed(self):
        """Handle the hotkey and capture selected text."""
        logging.debug("Hotkey pressed")

        # Prevent concurrent hotkey processing
        if self.hotkey_processing:
            logging.debug("Hotkey already being processed, ignoring")
            return

        self.hotkey_processing = True

        # Check for rapid successive triggers (debouncing)
        current_time = time.time()
        if current_time - self.last_hotkey_time < self.HOTKEY_DEBOUNCE_TIME:
            logging.debug("Hotkey pressed too soon, ignoring")
            self.hotkey_processing = False
            return

        self.last_hotkey_time = current_time

        # Check for spam triggers
        if self.check_trigger_spam():
            logging.warning("Hotkey spam detected - quitting application")
            self.hotkey_processing = False
            self.exit_app()
            return

        # Cancel any ongoing requests
        if self.current_provider:
            logging.debug("Cancelling current provider's request")
            self.current_provider.cancel()
            self.output_queue = ""

        # Select backend based on session type
        if SESSION_TYPE == "wayland":
            backend = WaylandBackend()
        else:
            backend = X11Backend()

        # Capture window title and selected text
        try:
            title = backend.get_active_window_title()
            selected_text = backend.get_selected_text().strip()
        except Exception as e:
            logging.error(f"Error capturing text: {e}")
            self.hotkey_processing = False
            self.show_message_signal.emit("Error", f"Failed to capture text: {e}")
            return

        if not selected_text:
            self.hotkey_processing = False
            self.show_message_signal.emit("Error", "No text selected")
            return

        logging.debug(f"Captured from {title!r}: {selected_text!r}")

        # Continue with existing popup logic
        QtCore.QMetaObject.invokeMethod(
            self, "_show_popup", QtCore.Qt.ConnectionType.QueuedConnection
        )

        # Reset the hotkey processing flag
        self.hotkey_processing = False

    @Slot()
    def _show_popup(self):
        """
        Show the popup window when the hotkey is pressed.
        """
        logging.debug("Showing popup window")
        # First attempt with default sleep
        selected_text = self.get_selected_text()

        # Retry with longer sleep if no text captured
        if not selected_text:
            logging.debug("No text captured, retrying with longer sleep")
            selected_text = self.get_selected_text(sleep_duration=0.5)

        logging.debug(f'Selected text: "{selected_text}"')
        try:
            if self.popup_window is not None:
                logging.debug("Existing popup window found")
                if self.popup_window.isVisible():
                    logging.debug("Closing existing visible popup window")
                    self.popup_window.close()
                self.popup_window = None
            logging.debug("Creating new popup window")
            self.popup_window = ui.CustomPopupWindow.CustomPopupWindow(
                self, selected_text
            )

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

    def get_selected_text(self, sleep_duration=0.2):
        """
        Get the currently selected text using appropriate backend.
        """
        if SESSION_TYPE == "wayland":
            backend = WaylandBackend()
        else:
            backend = X11Backend()

        try:
            return backend.get_selected_text()
        except Exception as e:
            logging.error(f"Error getting selected text: {e}")
            return ""

    @staticmethod
    def clear_clipboard():
        """
        Clear the system clipboard.
        """
        try:
            pyperclip.copy("")
        except Exception as e:
            logging.error(f"Error clearing clipboard: {e}")

    def process_option(self, option, selected_text, custom_change=None):
        """
        Process the selected writing option in a separate thread.
        """
        logging.debug(f"Processing option: {option}")

        # For Summary, Key Points, Table, and empty text custom prompts, create response window
        if (option == "Custom" and not selected_text.strip()) or self.options[option][
            "open_in_window"
        ]:
            window_title = (
                "Chat" if (option == "Custom" and not selected_text.strip()) else option
            )
            self.current_response_window = self.show_response_window(
                window_title, selected_text
            )

            # Initialize chat history with text/prompt
            if option == "Custom" and not selected_text.strip():
                # For direct AI queries, don't include empty text
                self.current_response_window.chat_history = []
            else:
                # For other options, include the original text
                self.current_response_window.chat_history = [
                    {
                        "role": "user",
                        "content": f"Original text to {option.lower()}:\n\n{selected_text}",
                    }
                ]
        else:
            # Clear any existing response window reference for non-window options
            if hasattr(self, "current_response_window"):
                delattr(self, "current_response_window")

        threading.Thread(
            target=self.process_option_thread,
            args=(option, selected_text, custom_change),
            daemon=True,
        ).start()

    def process_option_thread(self, option, selected_text, custom_change=None):
        """
        Thread function to process the selected writing option using the AI model.
        """
        logging.debug(f"Starting processing thread for option: {option}")
        try:
            if selected_text.strip() == "":
                # No selected text
                if option == "Custom":
                    prompt = custom_change
                    system_instruction = "You are a friendly, helpful, compassionate, and endearing AI conversational assistant. Avoid making assumptions or generating harmful, biased, or inappropriate content. When in doubt, do not make up information. Ask the user for clarification if needed. Try not be unnecessarily repetitive in your response. You can, and should as appropriate, use Markdown formatting to make your response nicely readable."
                else:
                    self.show_message_signal.emit(
                        "Error", "Please select text to use this option."
                    )
                    return
            else:
                selected_prompt = self.options.get(option, ("", ""))
                prompt_prefix = selected_prompt["prefix"]
                system_instruction = selected_prompt["instruction"]
                if option == "Custom":
                    prompt = f"{prompt_prefix}Described change: {custom_change}\n\nText: {selected_text}"
                else:
                    prompt = f"{prompt_prefix}{selected_text}"

            self.output_queue = ""

            logging.debug(f"Getting response from provider for option: {option}")

            if (option == "Custom" and not selected_text.strip()) or self.options[
                option
            ]["open_in_window"]:
                logging.debug("Getting response for window display")
                response = self.current_provider.get_response(
                    system_instruction, prompt, return_response=True
                )
                logging.debug(
                    f"Got response of length: {len(response) if response else 0}"
                )

                # For custom prompts with no text, add question to chat history
                if option == "Custom" and not selected_text.strip():
                    self.current_response_window.chat_history.append(
                        {"role": "user", "content": custom_change}
                    )

                # Set initial response using QMetaObject.invokeMethod to ensure thread safety
                if hasattr(self, "current_response_window"):
                    # noinspection PyTypeChecker
                    QtCore.QMetaObject.invokeMethod(
                        self.current_response_window,
                        "set_text",
                        QtCore.Qt.ConnectionType.QueuedConnection,
                        QtCore.Q_ARG(str, response),
                    )
                    logging.debug("Invoked set_text on response window")
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
        response_window.show()
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
                if hasattr(self, "current_response_window"):
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
                    # For other options, use the original clipboard-based replacement
                    cleaned_text = self.output_queue.rstrip("\n")

                    if SESSION_TYPE == "wayland":
                        # Wayland-specific handling with robust fallback
                        self._handle_wayland_paste(cleaned_text)
                    else:
                        # Use X11 method
                        self._handle_x11_paste(cleaned_text)

                if not hasattr(self, "current_response_window"):
                    self.output_queue = ""

            except Exception as e:
                logging.error(f"Error processing output: {e}")
        else:
            logging.debug("No new text to process")

    def _handle_wayland_paste(self, text: str):
        """
        Handle paste operation on Wayland with robust error handling.
        Focuses on setting clipboard and attempting automatic paste.
        Uses comprehensive approach with window management and input simulation.
        """
        import threading
        import time
        import subprocess
        import os

        logging.debug("Handling Wayland paste operation")

        # Backup current clipboard (with timeout protection)
        clipboard_backup = ""
        try:

            def get_clipboard():
                nonlocal clipboard_backup
                try:
                    clipboard_backup = pyperclip.paste()
                except Exception:
                    pass

            # Try to get clipboard with timeout
            thread = threading.Thread(target=get_clipboard)
            thread.daemon = True
            thread.start()
            thread.join(timeout=2)

        except Exception as e:
            logging.debug(f"Clipboard backup failed: {e}")

        # Set the new text to clipboard using most reliable method
        clipboard_success = False
        try:
            # Method 1: Try wl-copy first (Wayland native)
            try:
                result = subprocess.run(
                    ["wl-copy"], input=text, text=True, capture_output=True, timeout=3
                )
                if result.returncode == 0:
                    clipboard_success = True
                    logging.debug("Clipboard set using wl-copy")
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass

            # Method 2: Fallback to pyperclip
            if not clipboard_success:
                pyperclip.copy(text)
                clipboard_success = True
                logging.debug("Clipboard set using pyperclip")

        except Exception as e:
            logging.error(f"Failed to set clipboard: {e}")

        if clipboard_success:
            time.sleep(0.5)  # Extra delay for Wayland clipboard sync
            logging.debug("Clipboard set successfully on Wayland")

            # Try comprehensive replacement with window management
            try:
                # Store original window information before showing popup
                if not hasattr(self, "_original_window"):
                    self._store_original_window()

                # Try comprehensive replacement
                replacement_success = self._try_comprehensive_replacement()

                if replacement_success:
                    logging.debug("Comprehensive text replacement succeeded!")
                    # Show success message
                    self.show_message_signal.emit(
                        "Success", "Text replaced automatically!"
                    )
                    return  # Success - we're done
            except Exception as e:
                logging.debug(f"Comprehensive replacement failed: {e}")

            # Fallback to regular paste simulation
            paste_success = self._try_comprehensive_paste()

            if paste_success:
                logging.debug("Automatic paste succeeded!")
                # Show success message
                self.show_message_signal.emit("Success", "Text replaced automatically!")
            else:
                logging.debug("Automatic paste failed, showing manual instruction")
                # Show manual instruction
                self.show_message_signal.emit(
                    "Info", "Text copied to clipboard! Press Ctrl+V to paste manually."
                )
        else:
            logging.error("Failed to set clipboard on Wayland")
            self.show_message_signal.emit(
                "Error", "Failed to copy text to clipboard. Please try again."
            )

        # Restore original clipboard content (best effort)
        try:
            if clipboard_backup:

                def restore_clipboard():
                    try:
                        pyperclip.copy(clipboard_backup)
                    except Exception:
                        pass

                thread = threading.Thread(target=restore_clipboard)
                thread.daemon = True
                thread.start()
                # Don't wait - this is best effort

        except Exception as e:
            logging.debug(f"Clipboard restore failed: {e}")

    def _store_original_window(self):
        """Store original window information before processing"""
        import subprocess

        try:
            # Get active window
            result = subprocess.run(
                ["kdotool", "getactivewindow"], capture_output=True, timeout=2
            )

            if result.returncode == 0:
                self._original_window = result.stdout.decode().strip()
                logging.debug(f"Stored original window: {self._original_window}")

                # Get window title for reference
                title_result = subprocess.run(
                    ["kdotool", "getwindowname", self._original_window],
                    capture_output=True,
                    timeout=2,
                    text=True,
                )
                if title_result.returncode == 0:
                    window_title = title_result.stdout.strip()
                    logging.debug(f"Original window title: {window_title}")

                return True
            else:
                logging.debug("No active window found")
                return False

        except Exception as e:
            logging.debug(f"Failed to store original window: {e}")
            return False

    def _try_comprehensive_replacement(self):
        """
        Comprehensive text replacement using kdotool for window management
        and ydotool for input simulation with proper focus handling.
        """
        import subprocess
        import time

        logging.debug("Attempting comprehensive text replacement")

        # Check if we have original window information
        if not hasattr(self, "_original_window") or not self._original_window:
            logging.debug("No original window stored, cannot proceed with replacement")
            return False

        # Get the text to replace (from the output queue)
        text_to_replace = (
            self.output_queue.strip() if hasattr(self, "output_queue") else ""
        )
        if not text_to_replace:
            logging.debug("No text to replace")
            return False

        try:
            # Step 1: Restore focus to original window
            logging.debug(f"Restoring focus to window: {self._original_window}")
            focus_result = subprocess.run(
                ["kdotool", "windowactivate", self._original_window],
                capture_output=True,
                timeout=3,
            )

            if focus_result.returncode != 0:
                logging.debug("Failed to restore window focus")
                return False

            # Add delay to ensure window is ready
            time.sleep(0.8)

            # Step 2: Try replacement methods
            replacement_methods = [
                # Method 1: Direct typing (most reliable for some apps)
                lambda: self._try_type_directly(text_to_replace),
                # Method 2: Select all (Ctrl+A) then paste (Ctrl+V)
                lambda: self._try_key_sequence(["ctrl+a", "ctrl+v"]),
                # Method 3: Just paste (Ctrl+V)
                lambda: self._try_key_sequence(["ctrl+v"]),
                # Method 4: Backspace then paste (for single line)
                lambda: self._try_key_sequence(["backspace", "ctrl+v"]),
                # Method 5: Delete then paste (more aggressive)
                lambda: self._try_key_sequence(["delete", "ctrl+v"]),
            ]

            for i, method in enumerate(replacement_methods):
                logging.debug(f"Trying replacement method {i + 1}")
                if method():
                    logging.debug(f"Replacement method {i + 1} succeeded!")
                    return True
                logging.debug(f"Replacement method {i + 1} failed")
                time.sleep(0.2)  # Small delay between attempts

            return False

        except Exception as e:
            logging.debug(f"Comprehensive replacement failed: {e}")
            return False

    def _try_type_directly(self, text):
        """Try typing text directly using ydotool type with chunking for long text"""
        import subprocess
        import time

        logging.debug("Trying direct typing with ydotool type")

        # Check if text is too long for single command
        max_length = 500  # Conservative limit for ydotool
        if len(text) > max_length:
            logging.debug(f"Text too long ({len(text)} chars), using chunked typing")
            return self._try_chunked_typing(text)

        try:
            # First try ydotool key command as it's more reliable than ydotool type
            # This avoids the 10-second timeout issue that causes partial text replacement
            # The key command uses raw keycodes for better control and consistency
            if self._try_ydotool_key_typing(text):
                logging.debug("ydotool key typing succeeded!")
                return True

            # Fallback to ydotool type if key method fails
            # This maintains backward compatibility
            result = subprocess.run(
                ["ydotool", "type", "--file", "-"],
                input=text,
                text=True,
                capture_output=True,
                timeout=10,  # Longer timeout for typing
            )

            if result.returncode == 0:
                logging.debug("Direct typing succeeded!")
                # Add delay based on text length
                time.sleep(0.1 * (len(text) / 50))  # Scale delay with length
                return True
            else:
                error_msg = (
                    result.stderr.decode().strip() if result.stderr else "unknown"
                )
                logging.debug(f"Direct typing failed: {error_msg}")
                return False

        except Exception as e:
            logging.debug(f"Direct typing failed: {e}")
            return False

    def _try_chunked_typing(self, text):
        """Try typing long text in chunks to avoid buffer limits"""
        import subprocess
        import time

        logging.debug("Trying chunked typing for long text")

        # Split text into chunks
        chunk_size = 200  # Conservative chunk size
        chunks = [text[i : i + chunk_size] for i in range(0, len(text), chunk_size)]

        try:
            for i, chunk in enumerate(chunks):
                logging.debug(f"Typing chunk {i + 1}/{len(chunks)}")

                result = subprocess.run(
                    ["ydotool", "type", "--file", "-"],
                    input=chunk,
                    text=True,
                    capture_output=True,
                    timeout=5,
                )

                if result.returncode != 0:
                    logging.debug(f"Chunk {i + 1} failed")
                    return False

                # Small delay between chunks
                time.sleep(0.2)

            logging.debug("Chunked typing succeeded!")
            time.sleep(0.5)  # Final delay
            return True

        except Exception as e:
            logging.debug(f"Chunked typing failed: {e}")
            return False

    def _try_key_sequence(self, keys):
        """Try a sequence of key presses with proper timing"""
        import subprocess
        import time

        try:
            for key in keys:
                cmd = ["ydotool", "key", key]
                logging.debug(f"Sending key: {key}")

                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode != 0:
                    logging.debug(f"Key {key} failed: {result.stderr.decode()[:100]}")
                    return False

                # Add small delay between keys
                time.sleep(0.15)

            # Add final delay after sequence
            time.sleep(0.4)
            return True

        except Exception as e:
            logging.debug(f"Key sequence failed: {e}")
            return False

    def _try_comprehensive_paste(self):
        """
        Comprehensive paste attempt with enhanced reliability.
        Uses all available methods with improved error handling.
        """
        import subprocess
        import time
        import os

        logging.debug("Attempting comprehensive paste with enhanced methods")

        # Determine if we're running on KDE
        is_kde = os.environ.get("XDG_CURRENT_DESKTOP", "").lower() == "kde"

        # Enhanced method list with better ordering
        methods = []

        if is_kde:
            methods = [
                lambda: self._try_ydotool_paste_enhanced(),  # Most reliable
                lambda: self._try_dotool_paste(),  # Alternative
                lambda: self._try_wtype_paste(),  # Virtual keyboard
                lambda: self._try_pykeyboard_paste(),  # Fallback
            ]
        else:
            methods = [
                lambda: self._try_ydotool_paste_enhanced(),  # Most reliable
                lambda: self._try_dotool_paste(),  # Alternative
                lambda: self._try_wtype_paste(),  # Virtual keyboard
                lambda: self._try_pykeyboard_paste(),  # Fallback
            ]

        # Try each method with enhanced error handling
        for i, method in enumerate(methods):
            try:
                logging.debug(f"Trying enhanced paste method {i + 1}")

                # Use threading with longer timeout for reliability
                import threading

                result_container = {"success": False}

                def run_method():
                    try:
                        result_container["success"] = method()
                    except Exception as e:
                        logging.debug(f"Method {i + 1} failed with exception: {e}")
                        result_container["success"] = False

                thread = threading.Thread(target=run_method)
                thread.daemon = True
                thread.start()
                thread.join(timeout=8)  # Longer timeout for reliability

                if result_container["success"]:
                    logging.debug(f"Enhanced paste method {i + 1} succeeded!")
                    time.sleep(0.5)  # Extra delay for reliability
                    return True
                else:
                    logging.debug(f"Enhanced paste method {i + 1} completed but failed")

            except Exception as e:
                logging.debug(f"Enhanced paste method {i + 1} failed: {e}")

        logging.debug("All enhanced paste methods completed")
        return False

    def _try_ydotool_paste_enhanced(self):
        """
        Enhanced ydotool paste with better error handling and reliability.
        """
        import subprocess
        import time
        import os

        logging.debug("Trying enhanced ydotool paste")

        # Check if ydotool is available
        try:
            result = subprocess.run(["ydotool", "help"], capture_output=True, timeout=2)
            if result.returncode != 0:
                logging.debug("ydotool not found")
                return False
        except Exception as e:
            logging.debug(f"ydotool check failed: {e}")
            return False

        # Ensure ydotool daemon is running
        socket_path = f"/run/user/{os.getuid()}/.ydotool_socket"
        daemon_running = False

        try:
            if os.path.exists(socket_path):
                test_result = subprocess.run(
                    ["ydotool", "debug"], capture_output=True, timeout=1
                )
                if test_result.returncode == 0:
                    daemon_running = True
        except Exception:
            pass

        if not daemon_running:
            try:
                subprocess.Popen(
                    ["ydotoold"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                time.sleep(1)  # Give daemon time to start
            except Exception as e:
                logging.debug(f"Failed to start ydotool daemon: {e}")
                return False

        # Enhanced ydotool methods with better parameters
        enhanced_methods = [
            # Method 1: Simple with delay
            ["ydotool", "key", "--delay", "100", "ctrl+v"],
            # Method 2: Individual keys with proper timing
            ["ydotool", "key", "ctrl:1", "v:1", "ctrl:0", "v:0"],
            # Method 3: Alternative syntax
            ["ydotool", "key", "ctrl+v"],
            # Method 4: With longer delay
            ["ydotool", "key", "--delay", "200", "ctrl+v"],
        ]

        for i, cmd in enumerate(enhanced_methods):
            try:
                logging.debug(
                    f"Trying enhanced ydotool method {i + 1}: {' '.join(cmd)}"
                )

                # Add focus verification
                try:
                    # Try to get active window to ensure focus
                    active_result = subprocess.run(
                        ["ydotool", "getactivewindow"], capture_output=True, timeout=1
                    )
                    if active_result.returncode != 0:
                        logging.debug("No active window, trying to focus")
                        # Try to focus the last active window
                        subprocess.run(
                            ["ydotool", "windowactivate", "%1"],
                            capture_output=True,
                            timeout=1,
                        )
                        time.sleep(0.2)
                except Exception:
                    pass

                # Execute the paste command
                result = subprocess.run(cmd, capture_output=True, timeout=5)

                if result.returncode == 0:
                    logging.debug(f"Enhanced ydotool method {i + 1} succeeded")
                    time.sleep(0.3)  # Extra delay for reliability
                    return True
                else:
                    error_msg = (
                        result.stderr.decode().strip() if result.stderr else "unknown"
                    )
                    logging.debug(
                        f"Enhanced ydotool method {i + 1} failed: {error_msg}"
                    )

                    # Handle daemon issues
                    if "failed to connect socket" in error_msg:
                        try:
                            subprocess.run(
                                ["pkill", "-f", "ydotoold"], capture_output=True
                            )
                            time.sleep(0.2)
                            subprocess.Popen(
                                ["ydotoold"],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                            )
                            time.sleep(1)
                        except Exception:
                            pass

            except subprocess.TimeoutExpired:
                logging.debug(f"Enhanced ydotool method {i + 1} timed out")
            except Exception as e:
                logging.debug(f"Enhanced ydotool method {i + 1} failed: {e}")

        return False

    def _handle_x11_paste(self, text: str):
        """
        Handle paste operation on X11 (traditional method).
        """
        try:
            clipboard_backup = pyperclip.paste()
            pyperclip.copy(text)

            kbrd = pykeyboard.Controller()

            def press_ctrl_v():
                kbrd.press(pykeyboard.Key.ctrl.value)
                kbrd.press("v")
                kbrd.release("v")
                kbrd.release(pykeyboard.Key.ctrl.value)

            press_ctrl_v()
            time.sleep(0.2)
            pyperclip.copy(clipboard_backup)

            logging.debug("X11 paste completed successfully")

        except Exception as e:
            logging.error(f"X11 paste failed: {e}")
            self.show_message_signal.emit("Error", f"Failed to paste text: {e}")

    def _try_paste_simulation(self):
        """
        Attempt to simulate paste using various Wayland-compatible methods.
        Uses kdotool, ydotool, dotool, wtype, and other Wayland input tools.
        Prioritizes KDE-specific tools on KDE Wayland.
        """
        import subprocess
        import threading
        import time
        import os

        logging.debug("Attempting paste simulation with Wayland tools")

        # Determine if we're running on KDE
        is_kde = os.environ.get("XDG_CURRENT_DESKTOP", "").lower() == "kde"

        # Define methods based on environment
        if is_kde:
            logging.debug("Running on KDE Wayland - using KDE-optimized method order")
            methods = [
                # Method 1: Try kdotool first (KDE-specific, most reliable on KDE)
                lambda: self._try_kdotool_paste(),
                # Method 2: Try ydotool (comprehensive Wayland tool)
                lambda: self._try_ydotool_paste(),
                # Method 3: Try dotool (alternative Wayland tool)
                lambda: self._try_dotool_paste(),
                # Method 4: Try wtype (may work on some KDE setups)
                lambda: self._try_wtype_paste(),
                # Method 5: Try ydot (another alternative)
                lambda: self._try_ydot_paste(),
                # Method 6: Try pykeyboard as final fallback
                lambda: self._try_pykeyboard_paste(),
            ]
        else:
            # Non-KDE Wayland compositors
            methods = [
                # Method 1: Try ydotool first (most comprehensive)
                lambda: self._try_ydotool_paste(),
                # Method 2: Try dotool (alternative)
                lambda: self._try_dotool_paste(),
                # Method 3: Try wtype (Wayland virtual keyboard)
                lambda: self._try_wtype_paste(),
                # Method 4: Try kdotool (just in case)
                lambda: self._try_kdotool_paste(),
                # Method 5: Try ydot (another alternative)
                lambda: self._try_ydot_paste(),
                # Method 6: Try pykeyboard as final fallback
                lambda: self._try_pykeyboard_paste(),
            ]

        # Try each method with timeout
        for i, method in enumerate(methods):
            try:
                thread = threading.Thread(target=method)
                thread.daemon = True
                thread.start()
                thread.join(timeout=5)  # Max 5 seconds per method

                if not thread.is_alive():
                    logging.debug(f"Paste method {i + 1} completed successfully")
                    time.sleep(0.4)  # Extra delay after successful attempt
                    return
                else:
                    logging.debug(f"Paste method {i + 1} timed out")

            except Exception as e:
                logging.debug(f"Paste method {i + 1} failed: {e}")

        logging.debug("All Wayland paste simulation methods completed")

    def _try_kdotool_paste(self):
        """
        Try kdotool for paste simulation - KDE-specific Wayland input tool.
        kdotool is designed specifically for KDE Wayland and may work better.
        """
        import subprocess
        import time

        logging.debug("Trying kdotool paste simulation (KDE-specific)")

        # Check if kdotool is available
        try:
            result = subprocess.run(
                ["kdotool", "--help"], capture_output=True, timeout=2
            )
            if result.returncode != 0:
                logging.debug("kdotool not found or not working")
                return False
        except Exception as e:
            logging.debug(f"kdotool check failed: {e}")
            return False

        # kdotool doesn't support keyboard simulation commands
        # It's primarily a window management tool for KDE
        logging.debug("kdotool is available but doesn't support keyboard simulation")
        logging.debug("kdotool is for window management (move, resize, focus, etc.)")
        logging.debug("Skipping kdotool for paste simulation")

        return False  # kdotool cannot be used for paste simulation

    def _try_ydotool_key_typing(self, text: str) -> bool:
        """
        Try typing text using ydotool key command with raw keycodes.

        This method is more reliable than ydotool type for some Wayland compositors
        because it avoids the 10-second timeout issue that can cause partial text replacement.

        The ydotool key command uses raw Linux input event codes (KEY_*) with the format:
        <keycode>:1 for key press and <keycode>:0 for key release.

        This approach provides:
        - Better control over individual key events
        - No timeout issues for long text
        - More consistent performance across different Wayland compositors
        - Fallback capability (still tries ydotool type if this fails)

        Note: This implementation uses US keyboard layout keycodes. For international
        layouts, additional mapping may be needed.
        """
        import subprocess
        import time

        logging.debug(f"Trying ydotool key typing for text length: {len(text)}")

        # Security and safety checks
        # 1. Input validation - prevent excessively long text
        max_length = 2000  # Reasonable limit to prevent abuse
        if len(text) > max_length:
            logging.warning(
                f"Text too long ({len(text)} chars), truncating to {max_length}"
            )
            text = text[:max_length]

        # 2. Validate text content - only allow printable characters
        import string

        safe_chars = (
            string.ascii_letters + string.digits + string.punctuation + " \t\n\r"
        )

        # Check for potentially dangerous characters
        for char in text:
            if (
                char not in safe_chars and ord(char) > 127
            ):  # Allow basic ASCII and common Unicode
                logging.warning(
                    f"Potentially unsafe character detected: {char} (U+{ord(char):04X})"
                )

        # Character to keycode mapping (US layout) - expanded for better coverage
        char_to_keycode = {
            # Lowercase letters
            "a": "30",
            "b": "48",
            "c": "46",
            "d": "32",
            "e": "18",
            "f": "33",
            "g": "34",
            "h": "35",
            "i": "23",
            "j": "36",
            "k": "37",
            "l": "38",
            "m": "50",
            "n": "49",
            "o": "24",
            "p": "25",
            "q": "16",
            "r": "19",
            "s": "31",
            "t": "20",
            "u": "22",
            "v": "47",
            "w": "17",
            "x": "45",
            "y": "21",
            "z": "44",
            # Uppercase letters (same keycodes as lowercase, but with shift)
            "A": "30",
            "B": "48",
            "C": "46",
            "D": "32",
            "E": "18",
            "F": "33",
            "G": "34",
            "H": "35",
            "I": "23",
            "J": "36",
            "K": "37",
            "L": "38",
            "M": "50",
            "N": "49",
            "O": "24",
            "P": "25",
            "Q": "16",
            "R": "19",
            "S": "31",
            "T": "20",
            "U": "22",
            "V": "47",
            "W": "17",
            "X": "45",
            "Y": "21",
            "Z": "44",
            # Numbers
            "0": "11",
            "1": "2",
            "2": "3",
            "3": "4",
            "4": "5",
            "5": "6",
            "6": "7",
            "7": "8",
            "8": "9",
            "9": "10",
            # Special characters
            " ": "57",  # space
            "\n": "28",  # enter
            "\t": "15",  # tab
            ".": "52",
            ",": "51",
            "/": "53",
            ";": "39",
            "'": "40",
            "[": "26",
            "]": "27",
            "\\": "43",
            "-": "12",
            "=": "13",
            "`": "41",
            # Common punctuation and symbols
            "!": "2",
            "@": "3",
            "#": "4",
            "$": "5",
            "%": "6",
            "^": "7",
            "&": "8",
            "*": "9",
            "(": "10",
            ")": "11",
            "_": "12",
            "+": "13",
            "{": "26",
            "}": "27",
            "|": "43",
            ":": "39",
            '"': "40",
            "<": "51",
            ">": "52",
            "?": "53",
            # Additional common characters
            "\r": "28",  # carriage return (same as enter)
        }

        # Build key sequence
        key_sequence = []
        for char in text:
            if char in char_to_keycode:
                keycode = char_to_keycode[char]
                # Format: keycode:1 keycode:0 (press and release)
                key_sequence.extend([f"{keycode}:1", f"{keycode}:0"])
            else:
                # Skip unsupported characters
                logging.debug(f"Skipping unsupported character: {char}")

        if not key_sequence:
            logging.debug("No valid key sequence generated")
            return False

        # Add small delays between characters to avoid overwhelming the system
        delayed_sequence = []
        max_sequence_length = 10000  # Prevent excessively long command lines

        for i, key_action in enumerate(key_sequence):
            delayed_sequence.append(key_action)
            # Add delay every few characters
            if i > 0 and i % 10 == 0:
                delayed_sequence.append("5")  # 5ms delay

            # Safety: Prevent excessively long sequences
            if len(delayed_sequence) > max_sequence_length:
                logging.warning(
                    f"Key sequence too long ({len(delayed_sequence)}), truncating"
                )
                break

        # Final safety check
        if len(delayed_sequence) > max_sequence_length:
            logging.error("Key sequence exceeds maximum allowed length")
            return False

        try:
            # Execute ydotool key command with security safeguards
            result = subprocess.run(
                ["ydotool", "key"] + delayed_sequence,
                capture_output=True,
                timeout=15,  # Slightly longer timeout for key sequences
                text=True,
                # Security: Don't allow shell injection
                shell=False,
                # Security: Limit environment inheritance to essential variables only
                env={
                    k: v
                    for k, v in os.environ.items()
                    if k
                    in ("PATH", "HOME", "USER", "LANG", "DISPLAY", "XDG_RUNTIME_DIR")
                },
            )

            if result.returncode == 0:
                # Add delay based on text length
                time.sleep(0.05 * (len(text) / 10))  # Scale delay with length
                return True
            else:
                error_msg = (
                    result.stderr.decode().strip() if result.stderr else "unknown"
                )
                logging.debug(f"ydotool key typing failed: {error_msg}")
                return False

        except subprocess.TimeoutExpired:
            logging.debug("ydotool key typing timed out")
            return False
        except Exception as e:
            logging.debug(f"ydotool key typing error: {e}")
            return False

    def _try_ydotool_paste(self):
        """
        Try ydotool for paste simulation - most comprehensive Wayland input tool.
        ydotool supports both keyboard and mouse input on Wayland.
        """
        import subprocess
        import time
        import os

        logging.debug("Trying ydotool paste simulation")

        # Check if ydotool is available
        try:
            result = subprocess.run(["ydotool", "help"], capture_output=True, timeout=2)
            if result.returncode != 0:
                logging.debug("ydotool not found or not working")
                return False
        except Exception as e:
            logging.debug(f"ydotool check failed: {e}")
            return False

        # Check if ydotool daemon is running, start it if not
        socket_path = "/run/user/{}/.ydotool_socket".format(os.getuid())
        daemon_running = False

        try:
            # Check if socket exists
            if os.path.exists(socket_path):
                # Test if daemon is responsive
                test_result = subprocess.run(
                    ["ydotool", "debug"], capture_output=True, timeout=1
                )
                if test_result.returncode == 0:
                    daemon_running = True
                    logging.debug("ydotool daemon is already running")
            else:
                logging.debug("ydotool daemon not running, attempting to start it")
        except Exception as e:
            logging.debug(f"ydotool daemon check failed: {e}")

        # Start ydotool daemon if not running
        if not daemon_running:
            try:
                # Start daemon in background
                daemon_process = subprocess.Popen(
                    ["ydotoold"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                # Give daemon time to start
                time.sleep(0.5)
                logging.debug("ydotool daemon started")
                daemon_running = True
            except Exception as e:
                logging.debug(f"Failed to start ydotool daemon: {e}")
                return False

        # Multiple ydotool approaches
        ydotool_methods = [
            # Method 1: Simple key sequence
            ["ydotool", "key", "ctrl+v"],
            # Method 2: Individual key presses with delays
            ["ydotool", "key", "ctrl:1", "v:1", "ctrl:0", "v:0"],
            # Method 3: With explicit delays
            ["ydotool", "key", "--delay", "50", "ctrl+v"],
            # Method 4: Alternative syntax using type
            ["ydotool", "type", "--key", "ctrl+v"],
            # Method 5: Direct key sequence
            ["ydotool", "key", "--key", "ctrl+v"],
        ]

        for i, cmd in enumerate(ydotool_methods):
            try:
                logging.debug(f"Trying ydotool method {i + 1}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode == 0:
                    logging.debug(f"ydotool method {i + 1} succeeded")
                    time.sleep(0.3)  # Extra delay for the paste to complete
                    return True
                else:
                    error_msg = (
                        result.stderr.decode().strip()
                        if result.stderr
                        else "unknown error"
                    )
                    logging.debug(f"ydotool method {i + 1} failed: {error_msg}")

                    # If daemon died, try to restart it once
                    if "failed to connect socket" in error_msg and i == 0:
                        logging.debug(
                            "ydotool daemon connection lost, attempting to restart"
                        )
                        try:
                            # Kill any existing daemon
                            subprocess.run(
                                ["pkill", "-f", "ydotoold"], capture_output=True
                            )
                            time.sleep(0.2)

                            # Start new daemon
                            subprocess.Popen(
                                ["ydotoold"],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                            )
                            time.sleep(0.5)
                            logging.debug("ydotool daemon restarted")
                        except Exception as e:
                            logging.debug(f"Failed to restart ydotool daemon: {e}")

            except subprocess.TimeoutExpired:
                logging.debug(f"ydotool method {i + 1} timed out")
            except Exception as e:
                logging.debug(f"ydotool method {i + 1} failed: {e}")

        return False

    def _try_dotool_paste(self):
        """
        Try dotool for paste simulation - alternative Wayland input tool.
        """
        import subprocess
        import time

        logging.debug("Trying dotool paste simulation")

        # Check if dotool is available
        try:
            result = subprocess.run(
                ["dotool", "--help"], capture_output=True, timeout=2
            )
            if result.returncode != 0:
                logging.debug("dotool not found")
                return False
        except Exception as e:
            logging.debug(f"dotool check failed: {e}")
            return False

        # Multiple dotool approaches
        dotool_methods = [
            # Method 1: Simple key sequence
            ["dotool", "key", "ctrl+v"],
            # Method 2: Individual keys
            ["dotool", "key", "ctrl", "v"],
            # Method 3: With delays
            ["dotool", "key", "--delay", "50", "ctrl+v"],
        ]

        for i, cmd in enumerate(dotool_methods):
            try:
                logging.debug(f"Trying dotool method {i + 1}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode == 0:
                    logging.debug(f"dotool method {i + 1} succeeded")
                    time.sleep(0.2)
                    return True
                else:
                    logging.debug(
                        f"dotool method {i + 1} failed: {result.stderr.decode()[:100]}"
                    )

            except subprocess.TimeoutExpired:
                logging.debug(f"dotool method {i + 1} timed out")
            except Exception as e:
                logging.debug(f"dotool method {i + 1} failed: {e}")

        return False

    def _try_ydot_paste(self):
        """
        Try ydot for paste simulation.
        """
        import subprocess
        import time

        logging.debug("Trying ydot paste simulation")

        try:
            result = subprocess.run(["ydot", "paste"], capture_output=True, timeout=3)
            if result.returncode == 0:
                logging.debug("ydot paste succeeded")
                time.sleep(0.2)
                return True
            else:
                logging.debug(f"ydot paste failed: {result.stderr.decode()[:100]}")
        except Exception as e:
            logging.debug(f"ydot paste failed: {e}")

        return False

    def _try_wtype_paste(self):
        """
        Try to use wtype for paste simulation with multiple approaches.
        wtype is a Wayland-native virtual keyboard tool that should work better.
        """
        import subprocess
        import time

        logging.debug("Trying wtype paste simulation")

        # First check if compositor supports virtual keyboard protocol
        try:
            result = subprocess.run(["wtype", "--help"], capture_output=True, timeout=2)
            # If wtype runs without error, compositor might support it
        except Exception as e:
            logging.debug(
                f"wtype not available or compositor doesn't support virtual keyboard: {e}"
            )
            return False

        # Multiple wtype approaches
        wtype_methods = [
            # Method 1: Simple ctrl+v
            ["wtype", "-P", "ctrl+v"],
            # Method 2: More explicit key sequence
            ["wtype", "-P", "ctrl", "v"],
            # Method 3: With delays between keys
            ["wtype", "-d", "50", "-P", "ctrl+v"],
            # Method 4: Individual key presses with delays
            ["wtype", "-d", "100", "ctrl_l", "v"],
        ]

        for i, cmd in enumerate(wtype_methods):
            try:
                logging.debug(f"Trying wtype method {i + 1}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode == 0:
                    logging.debug(f"wtype method {i + 1} succeeded")
                    time.sleep(0.2)  # Give time for the paste to complete
                    return True
                else:
                    logging.debug(
                        f"wtype method {i + 1} failed with return code {result.returncode}"
                    )
                    if result.stderr:
                        error_msg = result.stderr.decode().strip()
                        if "virtual keyboard protocol" in error_msg:
                            logging.debug(
                                "Compositor doesn't support virtual keyboard protocol"
                            )
                            return False

            except FileNotFoundError:
                logging.debug("wtype not found, skipping")
                break
            except subprocess.TimeoutExpired:
                logging.debug(f"wtype method {i + 1} timed out")
            except Exception as e:
                logging.debug(f"wtype method {i + 1} failed: {e}")

        return False

    def _try_pykeyboard_paste(self):
        """Try keyboard paste with minimal delays (best effort)."""
        try:
            kbrd = pykeyboard.Controller()

            # Quick paste sequence
            kbrd.press(pykeyboard.Key.ctrl.value)
            kbrd.press("v")
            time.sleep(0.05)
            kbrd.release("v")
            kbrd.release(pykeyboard.Key.ctrl.value)

        except Exception:
            pass  # Silently fail - this is best effort

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
                    # For Gemini, use the proper history format with roles
                    chat_messages = []

                    # Convert our roles to Gemini's expected roles
                    for msg in history:
                        gemini_role = "model" if msg["role"] == "assistant" else "user"
                        chat_messages.append(
                            {"role": gemini_role, "parts": msg["content"]}
                        )

                    # Start chat with history
                    chat = self.current_provider.model.start_chat(history=chat_messages)

                    # Get response using the chat
                    response = chat.send_message(question)
                    response_text = response.text

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
