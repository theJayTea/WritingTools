import logging
import os
import sys

from aiprovider import AIProvider
from PySide6 import QtCore, QtWidgets
from PySide6.QtGui import QImage
from PySide6.QtWidgets import QHBoxLayout, QRadioButton

from ui.UIUtils import UIUtils, colorMode


class SettingsWindow(QtWidgets.QWidget):
    """
    The settings window for the application.
    """
    close_signal = QtCore.Signal()

    def __init__(self, app, providers_only=False):
        super().__init__()
        self.app = app
        self.current_provider_layout = None
        self.providers_only = providers_only
        self.init_ui()

    def init_provider_ui(self, provider: AIProvider, layout):
        """
        Initialize the user interface for the provider, including logo, name, description and all settings.
        """
        if self.current_provider_layout:
            self.current_provider_layout.setParent(None)
            UIUtils.clear_layout(self.current_provider_layout)
            self.current_provider_layout.deleteLater()

        self.current_provider_layout = QtWidgets.QVBoxLayout(self.background)

        # Create a horizontal layout for the logo and provider name
        provider_header_layout = QtWidgets.QHBoxLayout()
        provider_header_layout.setSpacing(10)
        provider_header_layout.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)

        if provider.logo:
            logo_path = os.path.join(os.path.dirname(sys.argv[0]), 'icons', f"provider_{provider.logo}.png")
            if os.path.exists(logo_path):
                # Adjust the size of the icon to be smaller
                targetPixmap = UIUtils.resize_and_round_image(QImage(logo_path), 30, 15)

                logo_label = QtWidgets.QLabel()
                logo_label.setPixmap(targetPixmap)
                logo_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignVCenter)

                provider_header_layout.addWidget(logo_label)

        provider_name_label = QtWidgets.QLabel(provider.provider_name)
        provider_name_label.setStyleSheet(f"font-size: 18px; font-weight: bold; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        provider_name_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignVCenter)
        provider_header_layout.addWidget(provider_name_label)

        self.current_provider_layout.addLayout(provider_header_layout)

        if provider.description:
            description_label = QtWidgets.QLabel(provider.description)

            description_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'}; text-align: center;")
            description_label.setWordWrap(True)

            self.current_provider_layout.addWidget(description_label)

        if provider.button_text:
            button = QtWidgets.QPushButton(provider.button_text)
            button.setStyleSheet(f"""
                QPushButton {{
                    background-color:
                    {'#4CAF50' if colorMode == 'dark' else '#008CBA'};
                    color: white;
                    padding: 10px;
                    font-size: 16px;
                    border: none;
                    border-radius: 5px;
                }}
                QPushButton:hover {{
                    background-color:
                    {'#45a049' if colorMode == 'dark' else '#007095'};
                }}
            """)
            button.clicked.connect(provider.button_action)
            self.current_provider_layout.addWidget(button, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        # If config["providers"] is not set, set it to an empty object
        if "providers" not in self.app.config:
            self.app.config["providers"] = {}

        # If the current provider is not in the list of providers, add it
        if provider.provider_name not in self.app.config["providers"]:
            self.app.config["providers"][provider.provider_name] = {}

        for setting in provider.settings:
            setting.set_value(self.app.config["providers"][provider.provider_name].get(setting.name, setting.default_value))

            setting.render_to_layout(self.current_provider_layout)

        layout.addLayout(self.current_provider_layout)


    def init_ui(self):
        """
        Initialize the user interface for the settings window.
        """
        self.setWindowTitle('Settings')
        self.setGeometry(300, 300, 400, 300)

        UIUtils.setup_window_and_layout(self)

        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(30, 30, 30, 30)
        content_layout.setSpacing(20)

        if not self.providers_only:
            title_label = QtWidgets.QLabel("Settings")
            title_label.setStyleSheet(f"font-size: 24px; font-weight: bold; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            content_layout.addWidget(title_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

            shortcut_label = QtWidgets.QLabel("Shortcut key:")
            shortcut_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            content_layout.addWidget(shortcut_label)

            self.shortcut_input = QtWidgets.QLineEdit(self.app.config.get('shortcut', 'ctrl+space'))
            self.shortcut_input.setStyleSheet(f"""
                font-size: 16px;
                padding: 5px;
                background-color: {'#444' if colorMode == 'dark' else 'white'};
                color: {'#ffffff' if colorMode == 'dark' else '#000000'};
                border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
            """)
            content_layout.addWidget(self.shortcut_input)

            theme_label = QtWidgets.QLabel("Theme:")
            theme_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            content_layout.addWidget(theme_label)

            theme_layout = QHBoxLayout()
            self.gradient_radio = QRadioButton("Blurry Gradient")
            self.plain_radio = QRadioButton("Plain")
            self.gradient_radio.setStyleSheet(f"color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            self.plain_radio.setStyleSheet(f"color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
            current_theme = self.app.config.get('theme', 'gradient')
            self.gradient_radio.setChecked(current_theme == 'gradient')
            self.plain_radio.setChecked(current_theme == 'plain')
            theme_layout.addWidget(self.gradient_radio)
            theme_layout.addWidget(self.plain_radio)
            content_layout.addLayout(theme_layout)

        # Checkbox for enabling streaming
        self.streaming_checkbox = QtWidgets.QCheckBox("Enable Response Streaming (experimental, not recommended)")
        self.streaming_checkbox.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        self.streaming_checkbox.setChecked(self.app.config.get('streaming', False))
        content_layout.addWidget(self.streaming_checkbox)

        # Setup dropdown to select provider
        provider_label = QtWidgets.QLabel("Choose AI Provider:")
        provider_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")

        self.provider_dropdown = QtWidgets.QComboBox()
        self.provider_dropdown.setStyleSheet(f"""
            font-size: 16px;
            padding: 5px;
            background-color: {'#444' if colorMode == 'dark' else 'white'};
            color: {'#ffffff' if colorMode == 'dark' else '#000000'};
            border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
        """)

        self.provider_dropdown.setInsertPolicy(QtWidgets.QComboBox.InsertPolicy.NoInsert)

        current_provider = self.app.config.get('provider', self.app.providers[0].provider_name)

        for provider in self.app.providers:
            self.provider_dropdown.addItem(provider.provider_name)

        self.provider_dropdown.setCurrentIndex(self.provider_dropdown.findText(current_provider))

        content_layout.addWidget(provider_label)
        content_layout.addWidget(self.provider_dropdown)

        provider_instance = self.app.providers[self.provider_dropdown.currentIndex()]

        # Initialise a layout for providers to go into.
        self.provider_container = QtWidgets.QVBoxLayout(self.background)

        # Add horizontal line
        line = QtWidgets.QFrame()
        line.setFrameShape(QtWidgets.QFrame.Shape.HLine)
        line.setFrameShadow(QtWidgets.QFrame.Shadow.Sunken)
        content_layout.addWidget(line)

        content_layout.addLayout(self.provider_container)

        line = QtWidgets.QFrame()
        line.setFrameShape(QtWidgets.QFrame.Shape.HLine)
        line.setFrameShadow(QtWidgets.QFrame.Shadow.Sunken)
        content_layout.addWidget(line)

        self.init_provider_ui(provider_instance, self.provider_container)

        # When provider is changed, run self.init_provider_ui(provider_instance, provider_container)
        self.provider_dropdown.currentIndexChanged.connect(lambda: (
            self.init_provider_ui(self.app.providers[self.provider_dropdown.currentIndex()], self.provider_container)
        ))

        save_button = QtWidgets.QPushButton("Finish AI Setup" if self.providers_only else "Save")
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

        if not self.providers_only:
            restart_text = """
            <p style='text-align: center;'>
            Please restart Writing Tools for changes to take effect.
            </p>
            """

            restart_notice = QtWidgets.QLabel(restart_text)
            restart_notice.setStyleSheet(f"font-size: 15px; color: {'#cccccc' if colorMode == 'dark' else '#555555'}; font-style: italic;")
            restart_notice.setWordWrap(True)
            content_layout.addWidget(restart_notice)

    def save_settings(self):
        """
        Save the current settings.
        """

        app = self.app

        if self.providers_only:
            app.create_tray_icon()
        else:
            new_shortcut = self.shortcut_input.text()
            new_theme = 'gradient' if self.gradient_radio.isChecked() else 'plain'

            app.config['shortcut'] = new_shortcut
            app.config['theme'] = new_theme

        app.config['streaming'] = self.streaming_checkbox.isChecked()
        app.config['provider'] = self.provider_dropdown.currentText()

        app.providers[self.provider_dropdown.currentIndex()].save_config()

        # Initialize the current provider, defaulting to Gemini 1.5 Flash
        provider_name = app.config.get('provider', 'Gemini 1.5 Flash')

        app.current_provider = next(
            (provider for provider in app.providers if provider.provider_name == provider_name), None)
        if not app.current_provider:
            logging.warning(f'Provider {provider_name} not found. Using default provider.')
            app.current_provider = self.providers[0]

        app.current_provider.load_config(app.config.get("providers", {}).get(provider_name, {}))

        app.register_hotkey()
        self.providers_only = False  # this way we don't stop the main program
        self.close()

    def closeEvent(self, event):
        # Emit the close signal
        if self.providers_only:
            self.close_signal.emit()
        super().closeEvent(event)
