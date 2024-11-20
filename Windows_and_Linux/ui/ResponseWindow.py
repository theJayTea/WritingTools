import os
import sys

import markdown2
from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import Qt

from ui.UIUtils import UIUtils, colorMode


class MarkdownTextBrowser(QtWidgets.QTextBrowser):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setReadOnly(True)
        self.setOpenExternalLinks(True)
        self.zoom_factor = 1.0
        self.base_font_size = 14
        
    def wheelEvent(self, event):
        if event.modifiers() == Qt.KeyboardModifier.ControlModifier:
            delta = event.angleDelta().y()
            if delta > 0:
                self.zoom_in()
            else:
                self.zoom_out()
            event.accept()
        else:
            super().wheelEvent(event)
            
    def zoom_in(self):
        self.zoom_factor = min(3.0, self.zoom_factor * 1.1)
        self._apply_zoom()
        
    def zoom_out(self):
        self.zoom_factor = max(0.5, self.zoom_factor / 1.1)
        self._apply_zoom()
        
    def reset_zoom(self):
        self.zoom_factor = 1.0
        self._apply_zoom()
        
    def _apply_zoom(self):
        # Calculate new font size
        new_size = int(self.base_font_size * self.zoom_factor)
        
        # Update the stylesheet with the new font size
        self.setStyleSheet(f"""
            QTextBrowser {{
                background-color: {'#333' if colorMode == 'dark' else 'white'};
                color: {'#ffffff' if colorMode == 'dark' else '#000000'};
                border: 1px solid {'#555' if colorMode == 'dark' else '#ccc'};
                border-radius: 5px;
                padding: 10px;
                font-size: {new_size}px;
            }}
        """)

class ResponseWindow(QtWidgets.QWidget):
    def __init__(self, app, title="Response", parent=None):
        super().__init__(parent)
        self.app = app  # Store reference to main app
        self.original_title = title  # Store the original title
        self.setWindowTitle(title)
        self.option = title.replace(" Result", "")  # Store the option type (Summary/Key Points)
        self.selected_text = None  # Will store the selected text
        self.init_ui()
        
    def init_ui(self):
        self.setWindowFlags(QtCore.Qt.WindowType.Window | 
                          QtCore.Qt.WindowType.WindowCloseButtonHint | 
                          QtCore.Qt.WindowType.WindowMinimizeButtonHint |
                          QtCore.Qt.WindowType.WindowMaximizeButtonHint)
        
        self.setMinimumSize(400, 300)
        
        UIUtils.setup_window_and_layout(self)
        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(20, 20, 20, 20)
        content_layout.setSpacing(10)
        
        # Loading indicator
        self.loading_label = QtWidgets.QLabel("Loading response...")
        self.loading_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        self.loading_label.setStyleSheet(f"color: {'#ffffff' if colorMode == 'dark' else '#333333'}; font-size: 16px;")
        self.loading_label.setVisible(True)
        content_layout.addWidget(self.loading_label)
        
        # Markdown text display
        self.text_display = MarkdownTextBrowser()
        # Apply saved zoom if it exists
        saved_zoom = self.app.config.get('response_window_zoom', 1.0)
        self.text_display.zoom_factor = saved_zoom
        self.text_display._apply_zoom()
        self.text_display.setVisible(False)
        content_layout.addWidget(self.text_display)
        
        # Bottom layout for controls
        bottom_layout = QtWidgets.QHBoxLayout()
        
        # Regenerate button at bottom left
        self.regenerate_button = QtWidgets.QPushButton()
        self.regenerate_button.setIcon(QtGui.QIcon(os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'regenerate' + ('_dark' if colorMode == 'dark' else '_light') + '.png')))
        self.regenerate_button.setText(" Regenerate")
        self.regenerate_button.setStyleSheet(self.get_button_style())
        self.regenerate_button.setFixedHeight(30)  # Same height as zoom buttons
        self.regenerate_button.clicked.connect(self.regenerate_response)
        bottom_layout.addWidget(self.regenerate_button)
        
        # Stretch to push zoom controls to the right
        bottom_layout.addStretch()
        
        # Zoom controls
        zoom_label = QtWidgets.QLabel("Zoom:")
        zoom_label.setStyleSheet(f"color: {'#ffffff' if colorMode == 'dark' else '#333333'}; margin-right: 5px;")
        bottom_layout.addWidget(zoom_label)
        
        # Zoom buttons
        zoom_out_btn = QtWidgets.QPushButton()
        zoom_out_btn.setIcon(QtGui.QIcon(os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'minus' + ('_dark' if colorMode == 'dark' else '_light') + '.png')))
        zoom_out_btn.setStyleSheet(self.get_button_style())
        zoom_out_btn.clicked.connect(self.text_display.zoom_out)
        zoom_out_btn.setFixedSize(30, 30)
        bottom_layout.addWidget(zoom_out_btn)

        zoom_in_btn = QtWidgets.QPushButton()
        zoom_in_btn.setIcon(QtGui.QIcon(os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'plus' + ('_dark' if colorMode == 'dark' else '_light') + '.png')))
        zoom_in_btn.setStyleSheet(self.get_button_style())
        zoom_in_btn.clicked.connect(self.text_display.zoom_in)
        zoom_in_btn.setFixedSize(30, 30)
        bottom_layout.addWidget(zoom_in_btn)
        
        reset_zoom_btn = QtWidgets.QPushButton()
        reset_zoom_btn.setIcon(QtGui.QIcon(os.path.join(os.path.dirname(sys.argv[0]), 'icons', 'reset' + ('_dark' if colorMode == 'dark' else '_light') + '.png')))
        reset_zoom_btn.setStyleSheet(self.get_button_style())
        reset_zoom_btn.clicked.connect(self.text_display.reset_zoom)
        reset_zoom_btn.setFixedSize(30, 30)
        bottom_layout.addWidget(reset_zoom_btn)
        
        content_layout.addLayout(bottom_layout)
        
    def get_button_style(self):
        return f"""
            QPushButton {{
                background-color: {'#444' if colorMode == 'dark' else '#f0f0f0'};
                color: {'#ffffff' if colorMode == 'dark' else '#000000'};
                border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
                border-radius: 5px;
                padding: 8px;
                font-size: 14px;
            }}
            QPushButton:hover {{
                background-color: {'#555' if colorMode == 'dark' else '#e0e0e0'};
            }}
        """

    
    def set_text(self, text):
        self.loading_label.setVisible(False)
        self.text_display.setVisible(True)
        
        # Convert Markdown to HTML
        html = markdown2.markdown(text, extras=['tables', 'fenced-code-blocks'])
        
        # Apply dark mode styles if needed
        if colorMode == 'dark':
            html = f"""
                <style>
                    body {{ color: #ffffff; }}
                    code {{ background-color: #444; padding: 2px 4px; border-radius: 3px; }}
                    pre {{ background-color: #444; padding: 10px; border-radius: 5px; }}
                    table {{ border-collapse: collapse; }}
                    th, td {{ border: 1px solid #555; padding: 8px; }}
                    th {{ background-color: #444; }}
                </style>
                {html}
            """
        else:
            html = f"""
                <style>
                    code {{ background-color: #f5f5f5; padding: 2px 4px; border-radius: 3px; }}
                    pre {{ background-color: #f5f5f5; padding: 10px; border-radius: 5px; }}
                    table {{ border-collapse: collapse; }}
                    th, td {{ border: 1px solid #ddd; padding: 8px; }}
                    th {{ background-color: #f5f5f5; }}
                </style>
                {html}
            """
            
        self.text_display.setHtml(html)
        
        # Resize window appropriately based on content
        text_size = self.text_display.document().size()
        new_height = min(700, max(300, text_size.height() + 150))
        new_width = min(800, max(400, text_size.width() + 60))
        self.resize(new_width, new_height)
        
    def append_text(self, text):
        if not self.text_display.isVisible():
            self.loading_label.setVisible(False)
            self.text_display.setVisible(True)
        current_text = self.text_display.toPlainText()
        self.set_text(current_text + text)
        
    def regenerate_response(self):
        # Clear current text and show loading
        self.text_display.setVisible(False)
        self.loading_label.setVisible(True)
        self.text_display.clear()
        
        # Cancel any ongoing generation
        if self.app.current_provider:
            self.app.current_provider.cancel()
            
        # Process the option again
        self.app.process_option(self.option, self.selected_text)
        
def closeEvent(self, event):
    # Save zoom factor to main config
    self.app.config['response_window_zoom'] = self.text_display.zoom_factor
    self.app.save_config(self.app.config)
    # Remove the window reference from the app when closing
    if hasattr(self.app, 'current_response_window'):
        delattr(self.app, 'current_response_window')
    super().closeEvent(event)