import ctypes
import json
import logging
import os
import sys
import threading
import time
import webbrowser

import darkdetect
import google.generativeai as genai
import keyboard
import pyperclip
import win32clipboard
from google.generativeai.types import HarmBlockThreshold, HarmCategory
from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import QCoreApplication, Qt, Signal, Slot
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtWidgets import QMessageBox

# Set up logging to console
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

# Load user32.dll for Windows API calls
user32 = ctypes.windll.user32
colorMode = 'dark' if darkdetect.isDark() else 'light'

class GradientBackground(QtWidgets.QWidget):
    """
    A custom widget that creates a gradient background for the application.
    """
    def __init__(self, parent=None, background_image='background_light.png'):
        super().__init__(parent)
        self.setAttribute(QtCore.Qt.WA_StyledBackground, True)
        self.setAttribute(QtCore.Qt.WA_TranslucentBackground)

        if colorMode == 'dark':
            self.background_image = QtGui.QPixmap(os.path.join(os.path.dirname(sys.argv[0]), 'background_popup_dark.png'))
            self.gradient_color = QtGui.QColor(0, 0, 0, 80)
        else:
            self.background_image = QtGui.QPixmap(os.path.join(os.path.dirname(sys.argv[0]), 'background_popup_light.png'))
            self.gradient_color = QtGui.QColor(0, 0, 0, 80)

    def paintEvent(self, event):
        """
        Override the paint event to draw the gradient background.
        """
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.RenderHint.SmoothPixmapTransform)
        
        # Draw the background image
        painter.drawPixmap(self.rect(), self.background_image)

        gradient = QtGui.QLinearGradient(0, 0, 0, self.height())
        gradient.setColorAt(0, self.gradient_color)
        gradient.setColorAt(1, QtGui.QColor(0, 0, 0, 0))
        painter.fillRect(self.rect(), gradient)

class CustomPopupWindow(QtWidgets.QWidget):
    """
    A custom popup window that appears when the user activates the Writing Tools.
    """
    def __init__(self, app, selected_text):
        super().__init__()
        self.app = app
        self.selected_text = selected_text
        logging.debug('Initializing CustomPopupWindow')
        self.init_ui()

    def init_ui(self):
        """
        Initialize the user interface for the popup window.
        """
        logging.debug('Setting up CustomPopupWindow UI')
        self.setWindowFlags(QtCore.Qt.WindowType.FramelessWindowHint | QtCore.Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(QtCore.Qt.WA_TranslucentBackground)

        # Main layout
        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)

        # Gradient background
        if colorMode == 'dark':
            self.background = GradientBackground(self, 'background_popup_dark.png')
        else:
            self.background = GradientBackground(self, 'background_popup_light.png')

        main_layout.addWidget(self.background)

        # Content layout
        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(20, 20, 20, 20)
        content_layout.setSpacing(10)

        # Close button
        close_button = QtWidgets.QPushButton("×")
        close_button.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                color: {'#ffffff' if colorMode == 'dark' else '#333'};
                font-size: 20px;
                border: none;
            }}
            QPushButton:hover {{
                color: #e74c3c;
            }}
        """)
        close_button.clicked.connect(self.close)
        content_layout.addWidget(close_button, 0, QtCore.Qt.AlignmentFlag.AlignRight)

        # Custom change input and send button layout
        input_layout = QtWidgets.QHBoxLayout()
    
        self.custom_input = QtWidgets.QLineEdit()
        self.custom_input.setPlaceholderText("Describe your change...")
        self.custom_input.setStyleSheet(f"""
            QLineEdit {{
                padding: 8px;
                border: 1px solid {'#777' if colorMode == 'dark' else '#ccc'};
                border-radius: 4px;
                background-color: {'#333' if colorMode == 'dark' else 'white'};
                color: {'#ffffff' if colorMode == 'dark' else '#000000'};
            }}
        """)
        self.custom_input.returnPressed.connect(self.on_custom_change)
        input_layout.addWidget(self.custom_input)

        send_button = QtWidgets.QPushButton()
        send_button.setIcon(QtGui.QIcon(os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'send' + ('_dark' if colorMode == 'dark' else '_light') + '.png')))
        send_button.setStyleSheet(f"""
            QPushButton {{
                background-color: {'#2e7d32' if colorMode == 'dark' else '#4CAF50'};
                border: none;
                border-radius: 4px;
                padding: 5px;
            }}
            QPushButton:hover {{
                background-color: {'#2e7d32' if colorMode == 'dark' else '#45a049'};
            }}
        """)
        send_button.setFixedSize(self.custom_input.sizeHint().height(), self.custom_input.sizeHint().height())
        send_button.clicked.connect(self.on_custom_change)
        input_layout.addWidget(send_button)

        content_layout.addLayout(input_layout)

        # Options grid
        options_grid = QtWidgets.QGridLayout()
        options_grid.setSpacing(10)

        options = [
            ('Proofread', 'icons/magnifying-glass' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_proofread),
            ('Rewrite', 'icons/rotate-left' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_rewrite),
            ('Friendly', 'icons/smiley-face' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_friendly),
            ('Professional', 'icons/briefcase' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_professional),
            ('Concise', 'icons/concise' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_concise),
            ('Summary', 'icons/summary' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_summary),
            ('Key Points', 'icons/keypoints' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_keypoints),
            ('Table', 'icons/table' + ('_dark' if colorMode == 'dark' else '_light') + '.png', self.on_table)
        ]

        for i, (label, icon_path, callback) in enumerate(options):
            button = QtWidgets.QPushButton(label)
            button.setStyleSheet(f"""
                QPushButton {{
                    background-color: {'#444' if colorMode == 'dark' else 'white'};
                    border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
                    border-radius: 4px;
                    padding: 10px;
                    font-size: 14px;
                    text-align: left;
                    color: {'#ffffff' if colorMode == 'dark' else '#000000'};
                }}
                QPushButton:hover {{
                    background-color: {'#555' if colorMode == 'dark' else '#f0f0f0'};
                }}
            """)
            icon_full_path = os.path.join(os.path.dirname(sys.argv[0]), icon_path)
            if os.path.exists(icon_full_path):
                button.setIcon(QtGui.QIcon(icon_full_path))
            button.clicked.connect(callback)
            row = i // 2
            col = i % 2
            options_grid.addWidget(button, row, col)

        content_layout.addLayout(options_grid)
        logging.debug('CustomPopupWindow UI setup complete')

    def showEvent(self, event):
        """
        Override the show event to log window geometry.
        """
        super().showEvent(event)
        logging.debug(f'CustomPopupWindow shown. Geometry: {self.geometry()}')

    def paintEvent(self, event):
        """
        Override the paint event to create rounded corners for the window.
        """
        path = QtGui.QPainterPath()
        path.addRoundedRect(QtCore.QRectF(self.rect()), 10, 10)
        mask = QtGui.QRegion(path.toFillPolygon().toPolygon())
        self.setMask(mask)
        logging.debug(f'CustomPopupWindow paint event. Mask applied. Window visible: {self.isVisible()}')

    def on_custom_change(self):
        """
        Handle the custom change request from the user.
        """
        custom_change = self.custom_input.text()
        if custom_change:
            self.app.process_option('Custom', self.selected_text, custom_change)
            self.close()

    def on_proofread(self):
        """
        Handle the proofread request.
        """
        self.app.process_option('Proofread', self.selected_text)
        self.close()

    def on_rewrite(self):
        """
        Handle the rewrite request.
        """
        self.app.process_option('Rewrite', self.selected_text)
        self.close()

    def on_friendly(self):
        """
        Handle the make friendly request.
        """
        self.app.process_option('Friendly', self.selected_text)
        self.close()

    def on_professional(self):
        """
        Handle the make professional request.
        """
        self.app.process_option('Professional', self.selected_text)
        self.close()

    def on_concise(self):
        """
        Handle the make concise request.
        """
        self.app.process_option('Concise', self.selected_text)
        self.close()

    def on_summary(self):
        """
        Handle the summarize request.
        """
        self.app.process_option('Summary', self.selected_text)
        self.close()

    def on_keypoints(self):
        """
        Handle the extract key points request.
        """
        self.app.process_option('Key Points', self.selected_text)
        self.close()

    def on_table(self):
        """
        Handle the convert to table request.
        """
        self.app.process_option('Table', self.selected_text)
        self.close()

    def keyPressEvent(self, event):
        """
        Handle key press events, specifically to close the window on Escape key press.
        """
        if event.key() == QtCore.Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)

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

        if not self.config:
            logging.debug('No config found, showing onboarding')
            self.show_onboarding()
        else:
            logging.debug('Config found, setting up hotkey and tray icon')
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
            keyboard.add_hotkey(shortcut, self.on_hotkey_pressed)
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
        if selected_text.strip():
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
        else:
            logging.debug('No text selected')
            QtWidgets.QMessageBox.information(None, 'No text selected', 'Please select some text before pressing the shortcut key.')

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
        time.sleep(0.1)

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
                'Proofread': ('Proofread this:\n\n', 'You are a grammar proofreading assistant. Do not make significant changes to the text structure or writing style. Output ONLY the corrected text without any additional comments. If the text is incompatible with proofreading (e.g., completely random gibberish), output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Rewrite': ('Rewrite this:\n\n', 'You are a writing assistant. Rewrite the text provided by the user. Output ONLY their rewritten text without any additional comments. If the text is incompatible with rewriting (e.g., completely random gibberish), output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Friendly': ('Make this more friendly:\n\n', 'You are a writing assistant. Rewrite the text provided by the user to be more friendly. Output ONLY the rewritten text without any additional comments. If the text is completely incompatible with this request (e.g., completely random gibberish), output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Professional': ('Make this more professional:\n\n', 'You are a writing assistant. Rewrite the text provided by the user to be more professional. Output ONLY the rewritten text without any additional comments. If the text is completely incompatible with this request (e.g., completely random gibberish), output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Concise': ('Make this more concise:\n\n', 'You are a writing assistant. Rewrite the text provided by the user to be more concise. Output ONLY the rewritten concise text without any additional comments. If the text is completely incompatible with this request (e.g., completely random gibberish), output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Summary': ('Summarize this:\n\n', 'You are a summarization assistant. Provide a concise summary of the text provided by the user. Output ONLY the summary without any additional comments. If the text is completely incompatible with summarization (e.g., completely random gibberish), output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Key Points': ('Extract key points from this:\n\n', 'You are an assistant that extracts key points from text. Provide a list of key points from the text provided by the user. Output ONLY the key points without any additional comments. If the text is completely incompatible with extracting key points (e.g., completely random gibberish), output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Table': ('Convert this into a table:\n\n', 'You are an assistant that converts text into a table format. Convert the text provided by the user into a table. Output ONLY the table without any additional comments. If the text is completely incompatible with conversion to a table, output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'),
                'Custom': ('Make the following change to this text:\n\n', 'You are a writing assistant. Make the described change to the user\'s text. Output ONLY the appropriately changed text without any additional comments. If the text is completely incompatible with the requested change, output exactly "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".')
            }

            prompt_prefix, system_instruction = option_prompts.get(option, ('', ''))
            if option == 'Custom':
                prompt = f"{prompt_prefix}Described change: {custom_change}\n\nText: {selected_text}"
            else:
                prompt = f"{prompt_prefix}{selected_text}"

            genai.configure(api_key=self.config['api_key'])
            logging.debug('Configured genai with API key')

            model = genai.GenerativeModel(
                model_name='gemini-1.5-flash-latest',
                generation_config=genai.types.GenerationConfig(
                    candidate_count=1,
                    max_output_tokens=1000,
                    temperature=0.5
                ),
                safety_settings={
                    HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_NONE,
                }
            )
            logging.debug('Created generative model')

            response = model.generate_content(
                contents=[system_instruction, prompt],
            )
            logging.debug('Received response from model')

            # Check if the response was blocked
            if response.prompt_feedback.block_reason:
                logging.warning('Response was blocked due to safety settings')
                self.show_message_signal.emit('Content Blocked', 'The generated content was blocked due to safety settings.')
                return

            output_text = response.text.strip()
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

class OnboardingWindow(QtWidgets.QWidget):
    """
    The onboarding window shown to first-time users.
    """
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.init_ui()

    def init_ui(self):
        """
        Initialize the user interface for the onboarding window.
        """
        logging.debug('Initializing onboarding UI')
        self.setWindowTitle('Welcome to Writing Tools')
        self.resize(500, 400)
        
        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)

        self.background = GradientBackground(self)
        main_layout.addWidget(self.background)

        self.content_layout = QtWidgets.QVBoxLayout()
        self.content_layout.setContentsMargins(30, 30, 30, 30)
        self.content_layout.setSpacing(20)

        self.background.setLayout(self.content_layout)

        self.show_welcome_screen()

    def show_welcome_screen(self):
        """
        Show the welcome screen of the onboarding process.
        """
        self.clear_layout(self.content_layout)

        title_label = QtWidgets.QLabel("Welcome to Writing Tools!")
        title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #333;")
        self.content_layout.addWidget(title_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        features_text = """
        • Improves your writing with AI
        • Works in any application in just a click
        • MUCH more intelligent model than Apple's Writing Tools :)
        • Free and lightweight
        • Values your privacy
        """
        features_label = QtWidgets.QLabel(features_text)
        features_label.setStyleSheet("font-size: 16px; color: #333;")
        features_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignLeft)
        self.content_layout.addWidget(features_label)

        shortcut_label = QtWidgets.QLabel("Customize your shortcut key (default: ctrl+space):")
        shortcut_label.setStyleSheet("font-size: 16px; color: #333;")
        self.content_layout.addWidget(shortcut_label)

        self.shortcut_input = QtWidgets.QLineEdit('ctrl+space')
        self.shortcut_input.setStyleSheet("font-size: 16px; padding: 5px;")
        self.content_layout.addWidget(self.shortcut_input)

        self.next_button = QtWidgets.QPushButton('Next')
        self.next_button.setStyleSheet("""
            QPushButton {
                background-color: #4CAF50;
                color: white;
                padding: 10px;
                font-size: 16px;
                border: none;
                border-radius: 5px;
            }
            QPushButton:hover {
                background-color: #45a049;
            }
        """)
        self.next_button.clicked.connect(self.on_next_clicked)
        self.content_layout.addWidget(self.next_button)

    def on_next_clicked(self):
        """
        Handle the 'Next' button click in the welcome screen.
        """
        self.shortcut = self.shortcut_input.text()
        logging.debug(f'User selected shortcut: {self.shortcut}')
        self.show_api_key_input()

    def show_api_key_input(self):
        """
        Show the API key input screen of the onboarding process.
        """
        logging.debug('Showing API key input')
        self.clear_layout(self.content_layout)

        title_label = QtWidgets.QLabel("Almost there!")
        title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #333;")
        self.content_layout.addWidget(title_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        instructions = QtWidgets.QLabel("Writing Tools needs a free Google Gemini API key to work.")
        instructions.setStyleSheet("font-size: 16px; color: #333;")
        instructions.setWordWrap(True)
        self.content_layout.addWidget(instructions)

        get_api_key_button = QtWidgets.QPushButton("Get API Key")
        get_api_key_button.setStyleSheet("""
            QPushButton {
                background-color: #008CBA;
                color: white;
                padding: 10px;
                font-size: 16px;
                border: none;
                border-radius: 5px;
            }
            QPushButton:hover {
                background-color: #007B9A;
            }
        """)
        get_api_key_button.clicked.connect(lambda: webbrowser.open("https://aistudio.google.com/app/apikey"))
        self.content_layout.addWidget(get_api_key_button)

        self.api_key_input = QtWidgets.QLineEdit()
        self.api_key_input.setStyleSheet("font-size: 16px; padding: 5px;")
        self.api_key_input.setPlaceholderText("Enter your API key here")
        self.content_layout.addWidget(self.api_key_input)

        privacy_info = QtWidgets.QLabel("Your API key grants access to use Google's AI models. \nWriting Tools stores it locally ONLY on your device. \nWhen you use Writing Tools, on your invocation, it's sent encrypted to Google — SOLELY to improve your text with Gemini 1.5 Flash.")
        privacy_info.setStyleSheet("font-size: 14px; color: #555;")
        privacy_info.setWordWrap(True)
        self.content_layout.addWidget(privacy_info)

        self.finish_button = QtWidgets.QPushButton('Finish')
        self.finish_button.setStyleSheet("""
            QPushButton {
                background-color: #4CAF50;
                color: white;
                padding: 10px;
                font-size: 16px;
                border: none;
                border-radius: 5px;
            }
            QPushButton:hover {
                background-color: #45a049;
            }
        """)
        self.finish_button.clicked.connect(self.on_finish_clicked)
        self.content_layout.addWidget(self.finish_button)

    def clear_layout(self, layout):
        """
        Clear all widgets from the given layout.
        """
        while layout.count():
            child = layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()

    def on_finish_clicked(self):
        """
        Handle the 'Finish' button click in the API key input screen.
        """
        self.api_key = self.api_key_input.text()
        logging.debug('User entered API key')
        self.app.save_config({
            'shortcut': self.shortcut,
            'api_key': self.api_key
        })
        self.close()
        self.app.create_tray_icon()
        self.app.register_hotkey()

class SettingsWindow(QtWidgets.QWidget):
    """
    The settings window for the application.
    """
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.init_ui()

    def init_ui(self):
        """
        Initialize the user interface for the settings window.
        """
        self.setWindowTitle('Settings')
        self.setGeometry(300, 300, 400, 300)

        # Set the window icon
        icon_path = os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'app_icon.png')
        if os.path.exists(icon_path): self.setWindowIcon(QtGui.QIcon(icon_path))
        
        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)

        self.background = GradientBackground(self)
        main_layout.addWidget(self.background)

        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(30, 30, 30, 30)
        content_layout.setSpacing(20)

        title_label = QtWidgets.QLabel("Settings")

        if colorMode == 'dark':
            title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #ddd;")
        else:
            title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #333;")

        content_layout.addWidget(title_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        shortcut_label = QtWidgets.QLabel("Shortcut key:")

        if colorMode == 'dark':
            shortcut_label.setStyleSheet("font-size: 16px; color: #ddd;")
        else:
            shortcut_label.setStyleSheet("font-size: 16px; color: #333;")

        content_layout.addWidget(shortcut_label)

        self.shortcut_input = QtWidgets.QLineEdit(self.app.config.get('shortcut', 'ctrl+space'))
        self.shortcut_input.setStyleSheet("font-size: 16px; padding: 5px;")
        content_layout.addWidget(self.shortcut_input)

        api_key_label = QtWidgets.QLabel("API Key:")

        if colorMode == 'dark':
            api_key_label.setStyleSheet("font-size: 16px; color: #ddd;")
        else:
            api_key_label.setStyleSheet("font-size: 16px; color: #333;")

        content_layout.addWidget(api_key_label)

        self.api_key_input = QtWidgets.QLineEdit(self.app.config.get('api_key', ''))
        self.api_key_input.setStyleSheet("font-size: 16px; padding: 5px;")
        content_layout.addWidget(self.api_key_input)

        save_button = QtWidgets.QPushButton('Save')
        save_button.setStyleSheet("""
            QPushButton {
                background-color: #4CAF50;
                color: white;
                padding: 10px;
                font-size: 16px;
                border: none;
                border-radius: 5px;
            }
            QPushButton:hover {
                background-color: #45a049;
            }
        """)
        save_button.clicked.connect(self.save_settings)
        content_layout.addWidget(save_button)

        restart_text = """
        <p style='text-align: center;'>
        Please restart Writing Tools for changes to take effect.
        </p>
        """

        restart_notice = QtWidgets.QLabel(restart_text)

        if colorMode == 'dark':
            restart_notice.setStyleSheet("font-size: 15px; color: #ddd; font-style: italic;")
        else:
            restart_notice.setStyleSheet("font-size: 15px; color: #555; font-style: italic;")

        restart_notice.setWordWrap(True)
        content_layout.addWidget(restart_notice)

    def save_settings(self):
        """
        Save the current settings.
        """
        new_shortcut = self.shortcut_input.text()
        new_api_key = self.api_key_input.text()
        self.app.save_config({
            'shortcut': new_shortcut,
            'api_key': new_api_key
        })
        self.app.register_hotkey()
        self.close()

class AboutWindow(QtWidgets.QWidget):
    """
    The about window for the application.
    """
    def __init__(self):
        super().__init__()
        self.init_ui()

    def init_ui(self):
        """
        Initialize the user interface for the about window.
        """
        self.setWindowTitle('About Writing Tools')
        self.setGeometry(300, 300, 400, 300)
        
        # Set the window icon
        icon_path = os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'app_icon.png')
        if os.path.exists(icon_path): self.setWindowIcon(QtGui.QIcon(icon_path))

        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)

        self.background = GradientBackground(self)
        main_layout.addWidget(self.background)

        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(30, 30, 30, 30)
        content_layout.setSpacing(20)

        title_label = QtWidgets.QLabel("About Writing Tools")

        if colorMode == 'dark':
            title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #ddd;")
        else:
            title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #333;")

        content_layout.addWidget(title_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        about_text = """
        <p style='text-align: center;'>
        <b>Writing Tools</b> is a free and lightweight application that helps you improve your writing with AI, similar to Apple's new Apple Intelligence feature.<br><br>
        It's completely free for you to use as you provide your own free Gemini API key.<br><br>
        The AI model used here, Gemini 1.5 Flash, offers significantly better performance than Apple's on-device model, resulting in more natural and less robotic text refinements.<br><br><br>
  
        </p>
        <p style='text-align: center;'>
        <b>Made with love by Jesai, a high school student.</b><br><br>
        Feel free to check out my other AI app, <b>Bliss AI</b>. It's a novel AI tutor that's free on the Google Play Store :)<br><br>
        </p>
        <p style='text-align: center;'>
        <b>Contact me:</b> jesaitarun@gmail.com<br><br>
        </p>
        <p style='text-align: center;'>
        <b>Version:</b> 1.0 (Codename: Sorry_Apple)
        </p>
        """

        about_label = QtWidgets.QLabel(about_text)

        if colorMode == 'dark':
            about_label.setStyleSheet("font-size: 16px; color: #ddd;")
        else:
            about_label.setStyleSheet("font-size: 16px; color: #333;")

        about_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        about_label.setWordWrap(True)
        content_layout.addWidget(about_label)

def main():
    """
    The main entry point of the application.
    """
    
    app = WritingToolApp(sys.argv)
    
    app.setQuitOnLastWindowClosed(False)
    sys.exit(app.exec())

if __name__ == '__main__':
    main()