import json
import logging
import os
import sys
import threading
import time

import darkdetect
import pyperclip
from aiprovider import GeminiProvider, OpenAICompatibleProvider
from pynput import keyboard as pykeyboard
from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import Signal, Slot
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtWidgets import QMessageBox
from ui.AboutWindow import AboutWindow
from ui.CustomPopupWindow import CustomPopupWindow
from ui.OnboardingWindow import OnboardingWindow
from ui.SettingsWindow import SettingsWindow
from update_checker import UpdateChecker


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
        logging.debug('Initializing WritingToolApp')
        self.output_ready_signal.connect(self.replace_text)
        self.show_message_signal.connect(self.show_message_box)
        self.hotkey_triggered_signal.connect(self.on_hotkey_pressed)
        self.config = None
        self.config_path = None
        self.load_config()
        self.onboarding_window = None
        self.popup_window = None
        self.tray_icon = None
        self.settings_window = None
        self.about_window = None
        self.registered_hotkey = None
        self.output_queue = ""
        self.last_replace = 0
        self.hotkey_listener = None

        # Setup available AI providers
        self.providers = [GeminiProvider(self), OpenAICompatibleProvider(self)]

        if not self.config:
            logging.debug('No config found, showing onboarding')
            self.show_onboarding()
        else:
            logging.debug('Config found, setting up hotkey and tray icon')

            # Initialize the current provider, defaulting to Gemini
            provider_name = self.config.get('provider', 'Gemini')

            self.current_provider = next((provider for provider in self.providers if provider.provider_name == provider_name), None)
            if not self.current_provider:
                logging.warning(f'Provider {provider_name} not found. Using default provider.')
                self.current_provider = self.providers[0]

            self.current_provider.load_config(self.config.get("providers", {}).get(provider_name, {}))

            self.create_tray_icon()
            self.register_hotkey()
            
            # Initialize update checker
            self.update_checker = UpdateChecker(self)
            self.update_checker.check_updates_async()

        self.recent_triggers = []  # Track recent hotkey triggers
        self.TRIGGER_WINDOW = 1.5  # Time window in seconds
        self.MAX_TRIGGERS = 3  # Max allowed triggers in window

    def check_trigger_spam(self):
        """
        Check if hotkey is being triggered too frequently (3+ times in 1.5 seconds).
        Returns True if spam is detected.
        """
        current_time = time.time()
        
        # Add current trigger
        self.recent_triggers.append(current_time)
        
        # Remove old triggers outside the window
        self.recent_triggers = [t for t in self.recent_triggers 
                            if current_time - t <= self.TRIGGER_WINDOW]
        
        # Check if we have too many triggers in the window
        return len(self.recent_triggers) >= self.MAX_TRIGGERS

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
            json.dump(config, f, indent=4)
            logging.debug('Config saved successfully')
        self.config = config

    def show_onboarding(self):
        """
        Show the onboarding window for first-time users.
        """
        logging.debug('Showing onboarding window')
        self.onboarding_window = OnboardingWindow(self)
        self.onboarding_window.close_signal.connect(self.exit_app)
        self.onboarding_window.show()

    def start_hotkey_listener(self):
        """
        Create listener for hotkeys on Linux/Mac.
        """
        orig_shortcut = self.config.get('shortcut', 'ctrl+space')
        # Parse the shortcut string, for example ctrl+alt+h -> <ctrl>+<alt>+h
        shortcut = '+'.join([f'{t}' if len(t) <= 1 else f'<{t}>' for t in orig_shortcut.split('+')])
        logging.debug(f'Registering global hotkey for shortcut: {shortcut}')
        try:
            if self.hotkey_listener is not None:
                self.hotkey_listener.stop()

            def on_activate():
                logging.debug('triggered hotkey')
                self.hotkey_triggered_signal.emit()  # Emit the signal when hotkey is pressed

            # Define the hotkey combination
            hotkey = pykeyboard.HotKey(
                pykeyboard.HotKey.parse(shortcut),
                on_activate
            )
            self.registered_hotkey = orig_shortcut

            # Helper function to standardize key event
            def for_canonical(f):
                return lambda k: f(self.hotkey_listener.canonical(k))

            # Create a listener and store it as an attribute to stop it later
            self.hotkey_listener = pykeyboard.Listener(
                on_press=for_canonical(hotkey.press),
                on_release=for_canonical(hotkey.release)
            )

            # Start the listener
            self.hotkey_listener.start()
        except Exception as e:
            logging.error(f'Failed to register hotkey: {e}')

    def register_hotkey(self):
        """
        Register the global hotkey for activating Writing Tools.
        """
        logging.debug('Registering hotkey')
        self.start_hotkey_listener()
        logging.debug('Hotkey registered')

    def on_hotkey_pressed(self):
        """
        Handle the hotkey press event.
        """
        logging.debug('Hotkey pressed')
        
        # Check for spam triggers
        if self.check_trigger_spam():
            logging.warning('Hotkey spam detected - quitting application')
            self.exit_app()
            return
            
        # Original hotkey handling continues...
        if self.current_provider:
            logging.debug("Cancelling current provider's request")
            self.current_provider.cancel()
            self.output_queue = ""

        QtCore.QMetaObject.invokeMethod(self, "_show_popup", QtCore.Qt.ConnectionType.QueuedConnection)

    @Slot()
    def _show_popup(self):
        """
        Show the popup window when the hotkey is pressed.
        """
        logging.debug('Showing popup window')
        # First attempt with default sleep
        selected_text = self.get_selected_text()

        # Retry with longer sleep if no text captured
        if not selected_text:
            logging.debug('No text captured, retrying with longer sleep')
            selected_text = self.get_selected_text(sleep_duration=0.5)

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
            logging.debug(f'Popup window moved to position: ({x}, {y})')
        except Exception as e:
            logging.error(f'Error showing popup window: {e}', exc_info=True)

    def get_selected_text(self, sleep_duration=0.2):
        """
        Get the currently selected text from any application.
        Args:
            sleep_duration (float): Time to wait for clipboard update
        """
        # Backup the clipboard
        clipboard_backup = pyperclip.paste()
        logging.debug(f'Clipboard backup: "{clipboard_backup}" (sleep: {sleep_duration}s)')

        # Clear the clipboard
        self.clear_clipboard()

        # Simulate Ctrl+C
        logging.debug('Simulating Ctrl+C')
        kbrd = pykeyboard.Controller()

        def press_ctrl_c():
            kbrd.press(pykeyboard.Key.ctrl.value)
            kbrd.press('c')
            kbrd.release('c')
            kbrd.release(pykeyboard.Key.ctrl.value)

        press_ctrl_c()

        # Wait for the clipboard to update
        time.sleep(sleep_duration)
        logging.debug(f'Waited {sleep_duration}s for clipboard')

        # Get the selected text
        selected_text = pyperclip.paste()
        logging.debug(f'Selected text: "{selected_text}"')

        # Restore the clipboard
        pyperclip.copy(clipboard_backup)

        return selected_text

    @staticmethod
    def clear_clipboard():
        """
        Clear the system clipboard.
        """
        try:
            pyperclip.copy('')
        except Exception as e:
            logging.error(f'Error clearing clipboard: {e}')

    def process_option(self, option, selected_text, custom_change=None):
        """
        Process the selected writing option in a separate thread.
        """
        logging.debug(f'Processing option: {option}')
        
        # For Summary, Key Points, Table, and empty text custom prompts, create response window
        if option in ['Summary', 'Key Points', 'Table'] or (option == 'Custom' and not selected_text.strip()):
            window_title = "Chat" if (option == 'Custom' and not selected_text.strip()) else option
            self.current_response_window = self.show_response_window(window_title, selected_text)
            
            # Initialize chat history with text/prompt
            if option == 'Custom' and not selected_text.strip():
                # For direct AI queries, don't include empty text
                self.current_response_window.chat_history = []
            else:
                # For other options, include the original text
                self.current_response_window.chat_history = [
                    {
                        "role": "user",
                        "content": f"Original text to {option.lower()}:\n\n{selected_text}"
                    }
                ]
        else:
            # Clear any existing response window reference for non-window options
            if hasattr(self, 'current_response_window'):
                delattr(self, 'current_response_window')
                
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
                        'You are a grammar proofreading assistant. Output ONLY the corrected text without any additional comments. Maintain the original text structure and writing style. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is absolutely incompatible with this (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Rewrite': (
                        'Rewrite this:\n\n',
                        'You are a writing assistant. Rewrite the text provided by the user to improve phrasing. Output ONLY the rewritten text without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is absolutely incompatible with proofreading (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Friendly': (
                        'Make this more friendly:\n\n',
                        'You are a writing assistant. Rewrite the text provided by the user to be more friendly. Output ONLY the friendly text without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is absolutely incompatible with rewriting (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Professional': (
                        'Make this more professional:\n\n',
                        'You are a writing assistant. Rewrite the text provided by the user to sound more professional. Output ONLY the professional text without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is absolutely incompatible with this (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Concise': (
                        'Make this more concise:\n\n',
                        'You are a writing assistant. Rewrite the text provided by the user to be slightly more concise in tone, thus making it just a bit shorter. Do not change the text too much or be too reductive. Output ONLY the concise version without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is absolutely incompatible with this (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Summary': (
                        'Summarize this:\n\n',
                        'You are a summarisation assistant. Provide a succinct summary of the text provided by the user. The summary should be succinct yet encompass all the key insightful points. To make it quite legible and readable, you MUST use Markdown formatting (bold, italics, underline...). You should add line spacing between your paragraphs/lines. Only if appropriate, you could also use headings (only the very small ones), lists, tables, etc. Don\'t be repetitive or too verbose. Output ONLY the summary without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is absolutely incompatible with summarisation (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Key Points': (
                        'Extract key points from this:\n\n',
                        'You are an assistant that extracts key points from text provided by the user. Output ONLY the key points without additional comments. You MUST use Markdown formatting (lists, bold, italics, underline, etc. as appropriate) to make it quite legible and readable. Don\'t be repetitive or too verbose. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is absolutely incompatible with extracting key points (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Table': (
                        'Convert this into a table:\n\n',
                        'You are an assistant that converts text provided by the user into a Markdown table. Output ONLY the table without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text is completely incompatible with this with conversion, output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    ),
                    'Custom': (
                        'Make the following change to this text:\n\n',
                        'You are a writing and coding assistant. You MUST make the user\'s described change to the text or code provided by the user. Output ONLY the appropriately modified text or code without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\'s text content. If the text or code is absolutely incompatible with the requested change, output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".'
                    )
                }

                if selected_text.strip() == '':
                    # No selected text
                    if option == 'Custom':
                        prompt = custom_change
                        system_instruction = "You are a helpful assistant to the user. The user cannot follow-up with you after your single response to them, so do not ask them questions."
                    else:
                        self.show_message_signal.emit('Error', 'Please select text to use this option.')
                        return
                else:
                    prompt_prefix, system_instruction = option_prompts.get(option, ('', ''))
                    if option == 'Custom':
                        prompt = f"{prompt_prefix}Described change: {custom_change}\n\nText: {selected_text}"
                    else:
                        prompt = f"{prompt_prefix}{selected_text}"

                self.output_queue = ""

                logging.debug(f'Getting response from provider for option: {option}')
                
                if option in ['Summary', 'Key Points', 'Table'] or (option == 'Custom' and not selected_text.strip()):
                    logging.debug('Getting response for window display')
                    response = self.current_provider.get_response(system_instruction, prompt, return_response=True)
                    logging.debug(f'Got response of length: {len(response) if response else 0}')
                    
                    # For custom prompts with no text, add question to chat history
                    if option == 'Custom' and not selected_text.strip():
                        self.current_response_window.chat_history.append({
                            "role": "user",
                            "content": custom_change
                        })
                    
                    # Set initial response using QMetaObject.invokeMethod to ensure thread safety
                    if hasattr(self, 'current_response_window'):
                        QtCore.QMetaObject.invokeMethod(
                            self.current_response_window,
                            'set_text',
                            QtCore.Qt.ConnectionType.QueuedConnection,
                            QtCore.Q_ARG(str, response)
                        )
                        logging.debug('Invoked set_text on response window')
                else:
                    logging.debug('Getting response for direct replacement')
                    self.current_provider.get_response(system_instruction, prompt)
                    logging.debug('Response processed')

            except Exception as e:
                logging.error(f'An error occurred: {e}', exc_info=True)
                self.show_message_signal.emit('Error', f'An error occurred: {e}')

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
        from ui.ResponseWindow import ResponseWindow
        response_window = ResponseWindow(self, f"{option} Result")
        response_window.selected_text = text  # Store the text for regeneration
        response_window.show()
        return response_window

    def replace_text(self, new_text):
        """
        Replaces the text by pasting in the LLM generated text. With "Key Points" and "Summary", invokes a window with the output instead.
        """
        error_message = 'ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST'

        # Confirm new_text exists and is a string
        if new_text and isinstance(new_text, str):
            self.output_queue += new_text
            current_output = self.output_queue.strip()  # Strip whitespace for comparison

            # If the new text is the error message, show a message box
            if current_output == error_message:
                self.show_message_signal.emit('Error', 'The text is incompatible with the requested change.')
                return

            # Check if we're building up to the error message (to prevent partial pasting)
            if len(current_output) <= len(error_message):
                clean_current = ''.join(current_output.split())
                clean_error = ''.join(error_message.split())
                if clean_current == clean_error[:len(clean_current)]:
                    return

            logging.debug('Processing output text')
            try:
                # For Summary and Key Points, show in response window
                if hasattr(self, 'current_response_window'):
                    self.current_response_window.append_text(new_text)
                    
                    # If this is the initial response, add it to chat history
                    if len(self.current_response_window.chat_history) == 1:  # Only original text exists
                        self.current_response_window.chat_history.append({
                            "role": "assistant",
                            "content": self.output_queue.rstrip('\n')
                        })
                else:
                    # For other options, use the original clipboard-based replacement
                    clipboard_backup = pyperclip.paste()
                    cleaned_text = self.output_queue.rstrip('\n')
                    pyperclip.copy(cleaned_text)
                    
                    kbrd = pykeyboard.Controller()
                    def press_ctrl_v():
                        kbrd.press(pykeyboard.Key.ctrl.value)
                        kbrd.press('v')
                        kbrd.release('v')
                        kbrd.release(pykeyboard.Key.ctrl.value)

                    press_ctrl_v()
                    time.sleep(0.2)
                    pyperclip.copy(clipboard_backup)

                if not hasattr(self, 'current_response_window'):
                    self.output_queue = ""

            except Exception as e:
                logging.error(f'Error processing output: {e}')
        else:
            logging.debug('No new text to process')

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

    @staticmethod
    def apply_dark_mode_styles(menu):
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
        logging.debug(f'Processing follow-up question: {question}')
        
        def process_thread():
            logging.debug('Starting follow-up processing thread')
            try:
                if not response_window.chat_history:
                    logging.error("No chat history found")
                    self.show_message_signal.emit('Error', 'Chat history not found')
                    return

                # Add current question to chat history
                response_window.chat_history.append({
                    "role": "user",
                    "content": question
                })
                
                # Get chat history
                history = response_window.chat_history.copy()
                
                # System instruction based on original option
                system_instruction = "You are a helpful AI assistant. Provide clear and direct responses, maintaining the same format and style as your previous responses. If appropriate, use Markdown formatting to make your response more readable."
                
                logging.debug('Sending request to AI provider')
                
                # Format conversation differently based on provider
                if isinstance(self.current_provider, GeminiProvider):
                    # For Gemini, use the proper history format with roles
                    chat_messages = []
                    
                    # Convert our roles to Gemini's expected roles
                    for msg in history:
                        gemini_role = "model" if msg["role"] == "assistant" else "user"
                        chat_messages.append({
                            "role": gemini_role,
                            "parts": msg["content"]
                        })
                    
                    # Start chat with history
                    chat = self.current_provider.model.start_chat(history=chat_messages)
                    
                    # Get response using the chat
                    response = chat.send_message(question)
                    response_text = response.text
                    
                else:
                    # For OpenAI/compatible providers, prepare messages array
                    messages = []
                    
                    # Add system message
                    messages.append({"role": "system", "content": system_instruction})
                    
                    # Add history messages (including latest question)
                    for msg in history:
                        # Convert 'assistant' role to 'assistant' for OpenAI
                        role = "assistant" if msg["role"] == "assistant" else "user"
                        messages.append({"role": role, "content": msg["content"]})
                    
                    # Get response by passing the full messages array
                    response_text = self.current_provider.get_response(
                        system_instruction,
                        messages,  # Pass messages array directly
                        return_response=True
                    )

                logging.debug(f'Got response of length: {len(response_text)}')
                
                # Add response to chat history
                response_window.chat_history.append({
                    "role": "assistant",
                    "content": response_text
                })
                
                # Emit response via signal
                self.followup_response_signal.emit(response_text)

            except Exception as e:
                logging.error(f'Error processing follow-up question: {e}', exc_info=True)
                self.show_message_signal.emit('Error', f'An error occurred: {e}')
                self.followup_response_signal.emit("An error occurred while processing your question.")
                
        # Start the thread
        threading.Thread(target=process_thread, daemon=True).start()

    def show_settings(self, providers_only=False):

        """
        Show the settings window.
        """
        logging.debug('Showing settings window')
        # Always create a new settings window to handle providers_only correctly
        self.settings_window = SettingsWindow(self, providers_only=providers_only)
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
        logging.debug('Stopping the listener')
        if self.hotkey_listener is not None:
            self.hotkey_listener.stop()
        logging.debug('Exiting application')
        self.quit()
