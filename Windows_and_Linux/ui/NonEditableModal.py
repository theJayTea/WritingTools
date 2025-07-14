import logging

import markdown2
import pyperclip
from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import Qt, Slot

from ui.UIUtils import colorMode

_ = lambda x: x

class NonEditableModal(QtWidgets.QDialog):
    """
    Modal window to display transformed text when pasting fails (non-editable page).
    Simple, clean interface that matches the app theme.
    """

    def __init__(self, app, transformed_text, original_text):
        super().__init__()
        self.app = app
        self.transformed_text = transformed_text
        self.original_text = original_text

        # No title, frameless window, always on top
        self.setWindowFlags(Qt.WindowType.Dialog | Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setModal(True)

        self.setup_ui()
        self.apply_styles()
        self.position_near_cursor()
        
    def setup_ui(self):
        """Setup the user interface - clean and minimal"""
        # Main layout with minimal margins
        layout = QtWidgets.QVBoxLayout(self)
        layout.setSpacing(0)
        layout.setContentsMargins(0, 0, 0, 0)

        # Container widget for content with padding
        container = QtWidgets.QWidget()
        container_layout = QtWidgets.QVBoxLayout(container)
        container_layout.setSpacing(12)
        container_layout.setContentsMargins(16, 16, 16, 16)

        # Text display area with markdown support
        self.text_display = QtWidgets.QTextBrowser()
        self.text_display.setReadOnly(True)
        self.text_display.setOpenExternalLinks(True)
        self.text_display.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.text_display.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        # Convert markdown to HTML
        html_content = markdown2.markdown(self.transformed_text, extras=['fenced-code-blocks', 'tables'])
        self.text_display.setHtml(html_content)

        # Set size for text display
        self.text_display.setMinimumHeight(300)
        self.text_display.setMinimumWidth(500)
        container_layout.addWidget(self.text_display)

        # Button container aligned to the right
        button_container = QtWidgets.QWidget()
        button_layout = QtWidgets.QHBoxLayout(button_container)
        button_layout.setContentsMargins(0, 8, 0, 0)
        button_layout.addStretch()  # Push buttons to the right

        # Copy button with custom icon
        self.copy_button = QtWidgets.QPushButton()
        self.copy_button.setFixedSize(36, 36)
        self.copy_button.clicked.connect(self.copy_text)
        self.copy_button.setDefault(True)
        self.copy_button.setToolTip(_("Copy text"))

        # Close button with X icon
        self.close_button = QtWidgets.QPushButton()
        self.close_button.setFixedSize(36, 36)
        self.close_button.clicked.connect(self.close)
        self.close_button.setToolTip(_("Close"))

        button_layout.addWidget(self.copy_button)
        button_layout.addSpacing(8)  # Small space between buttons
        button_layout.addWidget(self.close_button)
        container_layout.addWidget(button_container)

        layout.addWidget(container)

        # Set focus to copy button
        self.copy_button.setFocus()
        
    def apply_styles(self):
        """Apply dark/light mode styles matching the app theme"""
        is_dark_mode = colorMode == 'dark'

        if is_dark_mode:
            # Dark mode styles - matching the interface theme
            self.setStyleSheet("""
                QDialog {
                    background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                        stop:0 #2a2a2a, stop:1 #1e1e1e);
                    border: 1px solid #404040;
                    border-radius: 12px;
                }
                QTextBrowser {
                    background-color: rgba(45, 45, 45, 0.9);
                    color: #ffffff;
                    border: 1px solid #404040;
                    border-radius: 8px;
                    padding: 12px;
                    font-size: 14px;
                    line-height: 1.4;
                }
                QTextBrowser:focus {
                    border: 1px solid #0078d4;
                }
                QPushButton {
                    background-color: #404040;
                    border: 1px solid #555555;
                    border-radius: 8px;
                    color: #ffffff;
                }
                QPushButton:hover {
                    background-color: #4a9eff;
                    border-color: #4a9eff;
                }
                QPushButton:pressed {
                    background-color: #0066cc;
                }
            """)
        else:
            # Light mode styles - matching the interface theme
            self.setStyleSheet("""
                QDialog {
                    background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                        stop:0 #ffffff, stop:1 #f5f5f5);
                    border: 1px solid #d0d0d0;
                    border-radius: 12px;
                }
                QTextBrowser {
                    background-color: rgba(255, 255, 255, 0.9);
                    color: #000000;
                    border: 1px solid #d0d0d0;
                    border-radius: 8px;
                    padding: 12px;
                    font-size: 14px;
                    line-height: 1.4;
                }
                QTextBrowser:focus {
                    border: 1px solid #0078d4;
                }
                QPushButton {
                    background-color: #f0f0f0;
                    border: 1px solid #d0d0d0;
                    border-radius: 8px;
                    color: #000000;
                }
                QPushButton:hover {
                    background-color: #4a9eff;
                    border-color: #4a9eff;
                    color: #ffffff;
                }
                QPushButton:pressed {
                    background-color: #0066cc;
                    color: #ffffff;
                }
            """)

        # Create icons for buttons
        self.create_copy_icon()
        self.create_close_icon()

    def create_copy_icon(self):
        """Create a custom copy icon with two overlapping rounded squares"""
        is_dark_mode = colorMode == 'dark'

        # Create pixmap for the icon
        pixmap = QtGui.QPixmap(24, 24)
        pixmap.fill(QtCore.Qt.GlobalColor.transparent)

        painter = QtGui.QPainter(pixmap)
        painter.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)

        # Set colors based on theme
        if is_dark_mode:
            color = QtGui.QColor(255, 255, 255, 180)
        else:
            color = QtGui.QColor(0, 0, 0, 180)

        painter.setPen(QtGui.QPen(color, 1.5))
        painter.setBrush(QtCore.Qt.BrushStyle.NoBrush)

        # Draw back square (slightly offset)
        back_rect = QtCore.QRect(6, 6, 12, 12)
        painter.drawRoundedRect(back_rect, 2, 2)

        # Draw front square
        front_rect = QtCore.QRect(3, 3, 12, 12)
        painter.drawRoundedRect(front_rect, 2, 2)

        painter.end()

        # Set icon to button
        icon = QtGui.QIcon(pixmap)
        self.copy_button.setIcon(icon)

    def create_close_icon(self):
        """Create a custom close icon with X"""
        is_dark_mode = colorMode == 'dark'

        # Create pixmap for the icon
        pixmap = QtGui.QPixmap(24, 24)
        pixmap.fill(QtCore.Qt.GlobalColor.transparent)

        painter = QtGui.QPainter(pixmap)
        painter.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)

        # Set colors based on theme
        if is_dark_mode:
            color = QtGui.QColor(255, 255, 255, 180)
        else:
            color = QtGui.QColor(0, 0, 0, 180)

        painter.setPen(QtGui.QPen(color, 2))

        # Draw X (two diagonal lines)
        painter.drawLine(8, 8, 16, 16)
        painter.drawLine(16, 8, 8, 16)

        painter.end()

        # Set icon to button
        icon = QtGui.QIcon(pixmap)
        self.close_button.setIcon(icon)

    def position_near_cursor(self):
        """Position the window near the cursor with larger size"""
        try:
            # Get cursor position
            cursor_pos = QtGui.QCursor.pos()

            # Get screen containing cursor
            screen = QtWidgets.QApplication.screenAt(cursor_pos)
            if screen is None:
                screen = QtWidgets.QApplication.primaryScreen()

            screen_geometry = screen.geometry()

            # Set larger window size for better text display
            self.resize(600, 450)

            # Calculate position (offset from cursor)
            x = cursor_pos.x() + 20
            y = cursor_pos.y() + 20

            # Adjust if window would go off screen
            if x + self.width() > screen_geometry.right():
                x = screen_geometry.right() - self.width()
            if y + self.height() > screen_geometry.bottom():
                y = cursor_pos.y() - self.height() - 20

            # Ensure window stays on screen
            x = max(screen_geometry.left(), x)
            y = max(screen_geometry.top(), y)

            self.move(x, y)

        except Exception as e:
            logging.error(f"Error positioning modal window: {e}")
            # Fallback to center of screen
            self.resize(600, 450)
            frame_geometry = self.frameGeometry()
            screen_center = QtWidgets.QApplication.primaryScreen().geometry().center()
            frame_geometry.moveCenter(screen_center)
            self.move(frame_geometry.topLeft())
    
    @Slot()
    def copy_text(self):
        """Copy the transformed text to clipboard"""
        try:
            pyperclip.copy(self.transformed_text)

            # Show brief visual feedback by changing button style
            is_dark_mode = colorMode == 'dark'

            if is_dark_mode:
                feedback_style = """
                    QPushButton {
                        background-color: #28a745;
                        border-color: #28a745;
                        color: #ffffff;
                    }
                """
            else:
                feedback_style = """
                    QPushButton {
                        background-color: #28a745;
                        border-color: #28a745;
                        color: #ffffff;
                    }
                """

            self.copy_button.setStyleSheet(feedback_style)
            self.copy_button.setEnabled(False)

            # Reset button after 1 second
            QtCore.QTimer.singleShot(1000, lambda: (
                self.copy_button.setStyleSheet(""),
                self.copy_button.setEnabled(True)
            ))

        except Exception as e:
            logging.error(f"Error copying text: {e}")
    
    def keyPressEvent(self, event):
        """Handle key press events"""
        if event.key() == Qt.Key.Key_Escape:
            self.close()
        elif event.key() == Qt.Key.Key_Return or event.key() == Qt.Key.Key_Enter:
            if event.modifiers() == Qt.KeyboardModifier.ControlModifier:
                self.copy_text()
            else:
                self.close()
        else:
            super().keyPressEvent(event)

    def mousePressEvent(self, event):
        """Handle mouse press for window dragging"""
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_position = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
            event.accept()

    def mouseMoveEvent(self, event):
        """Handle mouse move for window dragging"""
        if event.buttons() == Qt.MouseButton.LeftButton and hasattr(self, 'drag_position'):
            self.move(event.globalPosition().toPoint() - self.drag_position)
            event.accept()
