import logging
import os
import sys

from PySide6 import QtWidgets, QtCore, QtGui

from ui.UIUtils import ThemeBackground, colorMode

class CustomPopupWindow(QtWidgets.QWidget):
    """
    A custom popup window that appears when the user activates the Writing Tools.
    """
    def __init__(self, app, selected_text):
        super().__init__()
        self.app = app
        self.app.close_popup_signal.connect(self.processing_done)
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

        # Set the window title
        self.setWindowTitle("Writing Tools")

        # Main layout
        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)

        # Theme background
        self.background = ThemeBackground(self, self.app.config.get('theme', 'gradient'), is_popup=True)
        main_layout.addWidget(self.background)

        # Content layout
        self.content_layout = QtWidgets.QVBoxLayout(self.background)
        self.content_layout.setContentsMargins(20, 0, 20, 20)
        self.content_layout.setSpacing(10)

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
        self.content_layout.addWidget(close_button, 0, QtCore.Qt.AlignmentFlag.AlignRight)

        # Loader layout
        self.loader_bar = QtWidgets.QProgressBar()
        self.loader_bar.setRange(0, 0)
        self.loader_bar.setVisible(False)
        self.content_layout.addWidget(self.loader_bar)

        # Custom change input and send button layout
        input_layout = QtWidgets.QHBoxLayout()

        has_text = not not self.selected_text.strip()

        self.custom_input = QtWidgets.QLineEdit()
        self.custom_input.setPlaceholderText("Describe your change..." if has_text else "Please enter an instruction...")
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

        self.send_button = QtWidgets.QPushButton()
        self.send_button.setIcon(QtGui.QIcon(os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'send' + ('_dark' if colorMode == 'dark' else '_light') + '.png')))
        self.send_button.setStyleSheet(f"""
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
        self.send_button.setFixedSize(self.custom_input.sizeHint().height(), self.custom_input.sizeHint().height())
        self.send_button.clicked.connect(self.on_custom_change)
        input_layout.addWidget(self.send_button)

        self.content_layout.addLayout(input_layout)

        self.options_grid = None
        if has_text:
            # Options grid
            self.options_grid = QtWidgets.QGridLayout()
            self.options_grid.setSpacing(10)

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
                self.options_grid.addWidget(button, row, col)

            self.content_layout.addLayout(self.options_grid)
        else:
            self.custom_input.setMinimumWidth(300)

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

    def paintEvent(self, event):
        """
        Override the paint event to create rounded corners for the window.
        """
        path = QtGui.QPainterPath()
        path.addRoundedRect(QtCore.QRectF(self.rect()), 10, 10)
        mask = QtGui.QRegion(path.toFillPolygon().toPolygon())
        self.setMask(mask)
        # logging.debug(f'CustomPopupWindow paint event. Mask applied. Window visible: {self.isVisible()}')

    def on_custom_change(self):
        """
        Handle the custom change request from the user.
        """
        custom_change = self.custom_input.text()
        if custom_change:
            self.app.process_option('Custom', self.selected_text, custom_change)

    def on_proofread(self):
        """
        Handle the proofread request.
        """
        self.app.process_option('Proofread', self.selected_text)

    def on_rewrite(self):
        """
        Handle the rewrite request.
        """
        self.app.process_option('Rewrite', self.selected_text)

    def on_friendly(self):
        """
        Handle the make friendly request.
        """
        self.app.process_option('Friendly', self.selected_text)

    def on_professional(self):
        """
        Handle the make professional request.
        """
        self.app.process_option('Professional', self.selected_text)

    def on_concise(self):
        """
        Handle the make concise request.
        """
        self.app.process_option('Concise', self.selected_text)

    def on_summary(self):
        """
        Handle the summarize request.
        """
        self.app.process_option('Summary', self.selected_text)

    def on_keypoints(self):
        """
        Handle the extract key points request.
        """
        self.app.process_option('Key Points', self.selected_text)

    def on_table(self):
        """
        Handle the convert to table request.
        """
        self.app.process_option('Table', self.selected_text)

    def keyPressEvent(self, event):
        """
        Handle key press events, specifically to close the window on Escape key press.
        """
        if event.key() == QtCore.Qt.Key.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)

    def processing_option(self):
        self.loader_bar.setVisible(True)
        self.custom_input.setEnabled(False)
        self.send_button.setEnabled(False)
        if self.options_grid is not None:
            for i in range(self.options_grid.count()):
                widget = self.options_grid.itemAt(i).widget()
                widget.setEnabled(False)

    def processing_done(self):
        logging.debug("processing done, closing")
        self.close()
