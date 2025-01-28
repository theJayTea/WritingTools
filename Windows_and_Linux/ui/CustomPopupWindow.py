import logging
import os
import sys
import json
from functools import partial

from PySide6 import QtCore, QtGui, QtWidgets

from ui.UIUtils import ThemeBackground, colorMode

_ = lambda x: x

class CustomPopupWindow(QtWidgets.QWidget):
    """
    A custom popup window that appears when the user activates the Writing Tools.
    """
    def __init__(self, app, selected_text):
        super().__init__()
        self.app = app
        self.selected_text = selected_text
        self.custom_input = None
        logging.debug('Initializing CustomPopupWindow')
        self.init_ui()

    def init_ui(self):
        """
        Initialize the user interface for the popup window.
        """
        logging.debug('Setting up CustomPopupWindow UI')
        self.setWindowFlags(QtCore.Qt.WindowType.FramelessWindowHint | QtCore.Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(QtCore.Qt.WA_TranslucentBackground)

        # Set the window title
        self.setWindowTitle("Writing Tools")

        # Main layout
        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)

        # Theme background
        self.background = ThemeBackground(self, self.app.config.get('theme', 'gradient'), is_popup=True, border_radius=10)
        main_layout.addWidget(self.background)

        # Content layout
        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(20, 0, 20, 20)
        content_layout.setSpacing(10)

        # Close button
        close_button = QtWidgets.QPushButton("×")
        close_button.setMinimumWidth(40)
        close_button.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                color: {'#ffffff' if colorMode == 'dark' else '#333333'};
                font-size: 20px;
                border: none;
                border-radius: 12px;
                padding: 0px;
            }}
            QPushButton:hover {{
                background-color: {'#333333' if colorMode == 'dark' else '#ebebeb'};
                color: {'#ffffff' if colorMode == 'dark' else '#333333'};
            }}
        """)
        close_button.clicked.connect(self.close)
        content_layout.addWidget(close_button, 0, QtCore.Qt.AlignmentFlag.AlignRight)

        # Custom change input and send button layout
        input_layout = QtWidgets.QHBoxLayout()

        has_text = not not self.selected_text.strip()

        self.custom_input = QtWidgets.QLineEdit()
        self.custom_input.setPlaceholderText(_("Describe your change...") if has_text else _("Ask your AI..."))
        self.custom_input.setStyleSheet(f"""
            QLineEdit {{
                padding: 8px;
                border: 1px solid {'#777' if colorMode == 'dark' else '#ccc'};
                border-radius: 8px;
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
                border-radius: 8px;
                padding: 5px;
            }}
            QPushButton:hover {{
                background-color: {'#1b5e20' if colorMode == 'dark' else '#45a049'};
            }}
        """)
        send_button.setFixedSize(self.custom_input.sizeHint().height(), self.custom_input.sizeHint().height())
        send_button.clicked.connect(self.on_custom_change)
        input_layout.addWidget(send_button)

        content_layout.addLayout(input_layout)

        if has_text:

            # Options grid
            options_grid = QtWidgets.QGridLayout()
            options_grid.setSpacing(10)

            with open('options.json', 'r') as file:
                data = json.load(file)
            options = []
            for key in data:
                if key != "Custom":
                    options.append(
                        (key,
                         data[key]["icon"] + ('_dark' if colorMode == 'dark' else '_light') + '.png',
                         partial(self.on_generic_instruction, key))
                    )

            for i, (label, icon_path, callback) in enumerate(options):
                button = QtWidgets.QPushButton(label)
                button.setStyleSheet(f"""
                    QPushButton {{
                        background-color: {'#444' if colorMode == 'dark' else 'white'};
                        border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
                        border-radius: 8px;
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
        else:
            self.custom_input.setMinimumWidth(300)
            
        # Add update notice if available
        if self.app.config.get("update_available", False):
            update_label = QtWidgets.QLabel()
            update_label.setOpenExternalLinks(True)
            update_label.setText('<a href="https://github.com/theJayTea/WritingTools/releases" style="color:rgb(255, 0, 0); text-decoration: underline; font-weight: bold;">There\'s an update! :D Download now.</a>')
            update_label.setStyleSheet("margin-top: 10px;")
            content_layout.addWidget(update_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        logging.debug('CustomPopupWindow UI setup complete')

        # Install event filter to handle focus out events
        self.installEventFilter(self)

        QtCore.QTimer.singleShot(250, lambda: self.custom_input.setFocus())

    def eventFilter(self, obj, event):
        """
        Event filter to handle focus out events.
        """
        if event.type() == QtCore.QEvent.Type.WindowDeactivate:
            self.hide()
            return True
        return super().eventFilter(obj, event)

    def showEvent(self, event):
        """
        Override the show event to log window geometry.
        """
        super().showEvent(event)
        logging.debug(f'CustomPopupWindow shown. Geometry: {self.geometry()}')

    def on_custom_change(self):
        """
        Handle the custom change request from the user.
        """
        custom_change = self.custom_input.text()
        if custom_change:
            self.app.process_option('Custom', self.selected_text, custom_change)
            self.close()

    def on_generic_instruction(self, instruction):
        """
        Handle a generic request.
        """
        self.app.process_option(instruction, self.selected_text)
        self.close()

    def keyPressEvent(self, event):
        """
        Handle key press events, specifically to close the window on Escape key press.
        """
        if event.key() == QtCore.Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)
