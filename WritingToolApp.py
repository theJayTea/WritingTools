import json
import logging
import os
import sys
import threading
import time

import darkdetect
import keyboard
import pyperclip
import win32clipboard
from PySide6 import QtWidgets, QtCore, QtGui
from PySide6.QtCore import Signal, Slot
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtWidgets import QMessageBox

from aiprovider import Gemini15FlashProvider, OpenAICompatibleProvider
from ui.AboutWindow import AboutWindow
from ui.CustomPopupWindow import CustomPopupWindow
from ui.OnboardingWindow import OnboardingWindow
from ui.SettingsWindow import SettingsWindow


class WritingToolApp(QtWidgets.QApplication):
    """
    The main application class for Writing Tools.
    """
    output_ready_signal = Signal(str)
    show_message_signal = Signal(str, str)  # New signal for showing message boxes

    def __init__(self, argv):
        super().__init__(argv)
        logging.debug('Initializing WritingToolApp')
        self.output_ready_signal.connect(self.replace_selected_text)
        self.show_message_signal.connect(self.show_message_box)  # Connect new signal
        self.load_config()
        self.onboarding_window = None
        self.popup_window = None
        self.tray_icon = None
        self.settings_window = None
        self.about_window = None
        self.registered_hotkey = None

        # Setup available AI providers
        self.providers = [Gemini15FlashProvider(self), OpenAICompatibleProvider(self)]

        if not self.config:
            logging.debug('No config found, showing onboarding')
            self.show_onboarding()
        else:
            logging.debug('Config found, setting up hotkey and tray icon')

            # Initialize the current provider, defaulting to Gemini 1.5 Flash
            provider_name = self.config.get('provider', 'Gemini 1.5 Flash')

            self.current_provider = next((provider for provider in self.providers if provider.provider_name == provider_name), None)
            if not self.current_provider:
                logging.warning(f'Provider {provider_name} not found. Using default provider.')
                self.current_provider = self.providers[0]

            self.current_provider.load_config(self.config.get("providers", {}).get(provider_name, {}))

            self.create_tray_icon()
            self.register_hotkey()

    def load_config(self):
        """
        Load the configuration file.
        """
        self.config_path = os.path.join(os.path.dirname(sys.argv[0]), 'config.json')
        logging.debug(f'Loading config from {self.config_path}')
        if os.path.exists(self.config_path):
            with open(self.config_path, 'r') as f:
                self.config = json.load(f)
                logging.debug('Config loaded successfully')
        else:
            logging.debug('Config file not found')
            self.config = None

    def save_config(self, config):
        """
        Save the configuration file.
        """
        with open(self.config_path, 'w') as f:
            json.dump(config, f)
            logging.debug('Config saved successfully')
        self.config = config

    def show_onboarding(self):
        """
        Show the onboarding window for first-time users.
        """
        logging.debug('Showing onboarding window')
        self.onboarding_window = OnboardingWindow(self)
        self.onboarding_window.show()

    def register_hotkey(self):
        """
        Register the global hotkey for activating Writing Tools.
        """
        shortcut = self.config.get('shortcut', 'ctrl+space')
        logging.debug(f'Registering global hotkey for shortcut: {shortcut}')
        try:
            if self.registered_hotkey:
                keyboard.remove_hotkey(self.registered_hotkey)

            keyboard.add_hotkey(shortcut, self.on_hotkey_pressed)
            self.registered_hotkey = shortcut

            logging.debug('Hotkey registered successfully')
        except Exception as e:
            logging.error(f'Failed to register hotkey: {e}')

    def on_hotkey_pressed(self):
        """
        Handle the hotkey press event.
        """
        logging.debug('Hotkey pressed')
        QtCore.QMetaObject.invokeMethod(self, "_show_popup", QtCore.Qt.ConnectionType.QueuedConnection)

    @Slot()
    def _show_popup(self):
        """
        Show the popup window when the hotkey is pressed.
        """
        logging.debug('Showing popup window')
        selected_text = self.get_selected_text()

        logging.debug(f'Selected text: "{selected_text}"')
        try:
            if self.popup_window is not None:
                logging.debug('Existing popup window found')
                if self.popup_window.isVisible():
                    logging.debug('Closing existing visible popup window')
                    self.popup_window.close()
                self.popup_window = None
            logging.debug('Creating new popup window')
            self.popup_window = CustomPopupWindow(self, selected_text)

            # Set the window icon
            icon_path = os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'app_icon.png')
            if os.path.exists(icon_path): self.setWindowIcon(QtGui.QIcon(icon_path))
            # Get the screen containing the cursor
            cursor_pos = QCursor.pos()
            screen = QGuiApplication.screenAt(cursor_pos)
            if screen is None:
                screen = QGuiApplication.primaryScreen()
            screen_geometry = screen.geometry()
            logging.debug(f'Cursor is on screen: {screen.name()}')
            logging.debug(f'Screen geometry: {screen_geometry}')
            # Show the popup to get its size
            self.popup_window.show()
            self.popup_window.adjustSize()
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
            logging.debug(f'Popup window moved to position: ({x}, {y})')
        except Exception as e:
            logging.error(f'Error showing popup window: {e}', exc_info=True)

    def get_selected_text(self):
        """
        Get the currently selected text from any application.
        """
        # Backup the clipboard
        clipboard_backup = pyperclip.paste()
        logging.debug(f'Clipboard backup: "{clipboard_backup}"')

        # Clear the clipboard
        self.clear_clipboard()

        # Simulate Ctrl+C
        logging.debug('Simulating Ctrl+C')
        keyboard.press_and_release('ctrl+c')

        # Wait for the clipboard to update
        time.sleep(0.5)

        # Get the selected text
        selected_text = pyperclip.paste()
        logging.debug(f'Selected text: "{selected_text}"')

        # Restore the clipboard
        pyperclip.copy(clipboard_backup)

        return selected_text

    def clear_clipboard(self):
        """
        Clear the system clipboard.
        """
        try:
            win32clipboard.OpenClipboard()
            win32clipboard.EmptyClipboard()
        except Exception as e:
            logging.error(f'Error clearing clipboard: {e}')
        finally:
            win32clipboard.CloseClipboard()

    def process_option(self, option, selected_text, custom_change=None):
        """
        Process the selected writing option in a separate thread.
        """
        logging.debug(f'Processing option: {option}')
        threading.Thread(target=self.process_option_thread, args=(option, selected_text, custom_change), daemon=True).start()

    def process_option_thread(self, option, selected_text, custom_change=None):
        """
        Thread function to process the selected writing option using the AI model.
        """
        logging.debug(f'Starting processing thread for option: {option}')
        try:
            option_prompts = {
    'Proofread': (
        'Proofread this:\n\n',
        'You are a grammar proofreading assistant. Output ONLY the corrected text without any additional comments. Maintain the original text structure and writing style. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with this (e.g., random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Rewrite': (
        'Rewrite this:\n\n',
        'You are a writing assistant. Rewrite the text provided by the user to improve phrasing. Output ONLY the rewritten text without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with proofreading (e.g., random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Friendly': (
        'Make this more friendly:\n\n',
        'You are a writing assistant. Rewrite the text provided by the user to be more friendly. Output ONLY the revised text without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with rewriting (e.g., random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Professional': (
        'Make this more professional:\n\n',
        'You are a writing assistant. Rewrite the text provided by the user to sound more professional. Output ONLY the revised text without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with this (e.g., random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Concise': (
        'Make this more concise:\n\n',
        'You are a writing assistant. Rewrite the text provided by the user to be more concise. Output ONLY the concise version without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with this (e.g., random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Summary': (
        'Summarize this:\n\n',
        'You are a summarization assistant. Provide a concise summary of the text provided by the user. Output ONLY the summary without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with summarization (e.g., random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Key Points': (
        'Extract key points from this:\n\n',
        'You are an assistant that extracts key points from text provided by the user. Output ONLY the key points without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with with extracting key points (e.g., random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Table': (
        'Convert this into a table:\n\n',
        'You are an assistant that converts text provided by the user into a table. Output ONLY the table without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is incompatible with this with conversion, output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    ),
    'Custom': (
        'Make the following change to this text:\n\n',
        'You are a writing assistant. You MUST make the user\'s described change to the text provided by the user. Output ONLY the appropriately modified text without additional comments. Respond in the same language as the input (e.g., English US, French). If the text is completely incompatible with the requested change, output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
    )
}

            prompt_prefix, system_instruction = option_prompts.get(option, ('', ''))
            if option == 'Custom':
                prompt = f"{prompt_prefix}Described change: {custom_change}\n\nText: {selected_text}"
            else:
                prompt = f"{prompt_prefix}{selected_text}"

            output_text = self.current_provider.get_response(system_instruction, prompt)

            logging.debug(f'Output text: {output_text}')

            if output_text == "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST":
                self.show_message_signal.emit('Incompatible Request', 'Sorry, Writing Tools could not do that with this text.')
                return

            if output_text:  # Only emit if there's text to replace
                self.output_ready_signal.emit(output_text)

        except Exception as e:
            logging.error(f'An error occurred: {e}', exc_info=True)
            self.show_message_signal.emit('Error', f'An error occurred: {e}')

    @Slot(str, str)
    def show_message_box(self, title, message):
        """
        Show a message box with the given title and message.
        """
        QMessageBox.warning(None, title, message)

    def replace_selected_text(self, new_text):
        """
        Replace the selected text with the new text generated by the AI.
        """
        if new_text:
            logging.debug(f'Replacing selected text with: {new_text}')

            # Backup the clipboard
            clipboard_backup = pyperclip.paste()

            # Set the clipboard to the new text
            pyperclip.copy(new_text)

            # Simulate Ctrl+V
            logging.debug('Simulating Ctrl+V')
            keyboard.press_and_release('ctrl+v')

            # Wait for the paste operation to complete
            time.sleep(0.1)

            # Restore the clipboard
            pyperclip.copy(clipboard_backup)
        else:
            logging.debug('No new text to replace')

    def create_tray_icon(self):
        """
        Create the system tray icon for the application.
        """
        if self.tray_icon:
            logging.debug('Tray icon already exists')
            return

        logging.debug('Creating system tray icon')
        icon_path = os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'app_icon.png')
        if not os.path.exists(icon_path):
            logging.warning(f'Tray icon not found at {icon_path}')
            # Use a default icon if not found
            self.tray_icon = QtWidgets.QSystemTrayIcon(self)
        else:
            self.tray_icon = QtWidgets.QSystemTrayIcon(QtGui.QIcon(icon_path), self)
        # Set the tooltip (hover name) for the tray icon
        self.tray_icon.setToolTip("WritingTools")
        tray_menu = QtWidgets.QMenu()

        # Apply dark mode styles using darkdetect
        self.apply_dark_mode_styles(tray_menu)

        settings_action = tray_menu.addAction('Settings')
        settings_action.triggered.connect(self.show_settings)

        about_action = tray_menu.addAction('About')
        about_action.triggered.connect(self.show_about)

        exit_action = tray_menu.addAction('Exit')
        exit_action.triggered.connect(self.exit_app)

        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.show()
        logging.debug('Tray icon displayed')

    def apply_dark_mode_styles(self, menu):
        """
        Apply styles to the tray menu based on system theme using darkdetect.
        """
        is_dark_mode = darkdetect.isDark()
        palette = menu.palette()

        if is_dark_mode:
            logging.debug('Tray icon dark')
            # Dark mode colors
            palette.setColor(QtGui.QPalette.Window, QtGui.QColor("#2d2d2d"))  # Dark background
            palette.setColor(QtGui.QPalette.WindowText, QtGui.QColor("#ffffff"))  # White text
        else:
            logging.debug('Tray icon light')
            # Light mode colors
            palette.setColor(QtGui.QPalette.Window, QtGui.QColor("#ffffff"))  # Light background
            palette.setColor(QtGui.QPalette.WindowText, QtGui.QColor("#000000"))  # Black text

        menu.setPalette(palette)

    def show_settings(self):
        """
        Show the settings window.
        """
        logging.debug('Showing settings window')
        if not self.settings_window:
            self.settings_window = SettingsWindow(self)
        self.settings_window.show()

    def show_about(self):
        """
        Show the about window.
        """
        logging.debug('Showing about window')
        if not self.about_window:
            self.about_window = AboutWindow()
        self.about_window.show()

    def exit_app(self):
        """
        Exit the application.
        """
        logging.debug('Exiting application')
        self.quit()
