import webbrowser

from PySide6 import QtCore, QtWidgets, QtGui
from PySide6.QtCore import Qt

from ui.UIUtils import UIUtils, colorMode


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
        self.setWindowTitle(' ') # Hack to hide the title bar text. TODO: Find a better solution later.
        self.setGeometry(300, 300, 500, 490)  # Set the window size

        # Center the window on the screen. I'm not aware of any methods in UIUtils to do this, so I'll be doing it manually.
        screen = QtWidgets.QApplication.primaryScreen().geometry()
        x = (screen.width() - self.width()) // 2
        y = (screen.height() - self.height()) // 2
        self.move(x, y)

        UIUtils.setup_window_and_layout(self)

        # Disable minimize button and icon in title bar
        self.setWindowFlags(self.windowFlags() & ~QtCore.Qt.WindowMinimizeButtonHint & ~QtCore.Qt.WindowSystemMenuHint | QtCore.Qt.WindowCloseButtonHint | QtCore.Qt.WindowTitleHint)

        # Remove window icon. Has to be done after UIUtils.setup_window_and_layout().
        pixmap = QtGui.QPixmap(32, 32)
        pixmap.fill(QtCore.Qt.transparent)
        self.setWindowIcon(QtGui.QIcon(pixmap))

        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(30, 30, 30, 30)
        content_layout.setSpacing(20)

        title_label = QtWidgets.QLabel("About Writing Tools")
        title_label.setStyleSheet(f"font-size: 24px; font-weight: bold; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        content_layout.addWidget(title_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        about_text = """
                <p style='text-align: center;'>
                Writing Tools is a free & lightweight tool that helps you improve your writing with AI, similar to Apple's new Apple Intelligence feature. It works with an extensive range of AI LLMs, both online and locally run.<br>
                </p>
                <p style='text-align: center;'>
                <b>Created with care by Jesai, a high school student.</b><br><br>
                Feel free to check out my other AI app, <a href="https://play.google.com/store/apps/details?id=com.jesai.blissai"><b>Bliss AI</b></a>. It's a novel AI tutor that's free on the Google Play Store :)<br><br>
                <b>Contact me:</b> jesaitarun@gmail.com<br><br>
                </p>
                <p style='text-align: center;'>
                <b>⭐ Writing Tools would not be where it is today without its <u>amazing</u> contributors:</b><br>
                <b>1. <a href="https://github.com/CameronRedmore">Cameron Redmore (CameronRedmore)</a>:</b><br>
                Extensively refactored Writing Tools and added OpenAI Compatible API support, streamed responses, and the text generation mode when no text is selected.<br>
                <b>2. <a href="https://github.com/momokrono">momokrono</a>:</b><br>
                Added Linux support, and switched to the pynput API to improve Windows stability. Fixed misc. bugs, such as handling quitting onboarding without completing it.<br>
                <b>3. <a href="https://github.com/Disneyhockey40">Disneyhockey40 (Soszust40)</a>:</b><br>
                Helped add dark mode, the plain theme, tray menu fixes, and UI improvements.</b><br>
                <b>4. <a href="https://github.com/arsaboo">Alok Saboo (arsaboo)</a>:</b><br>
                Helped improve the reliability of text selection.</b><br>
                <b>5. <a href="https://github.com/raghavdhingra24">raghavdhingra24</a>:</b><br>
                Made the rounded corners anti-aliased & prettier.</b><br>
                </p>
                <p style='text-align: center;'>
                <b>Version:</b> 5.0 (Codename: Impressively Improved)
                </p>
                <p />
                """

        about_label = QtWidgets.QLabel(about_text)
        about_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        about_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        about_label.setWordWrap(True)
        about_label.setOpenExternalLinks(True)  # Allow opening hyperlinks

        scroll_area = QtWidgets.QScrollArea()
        scroll_area.setWidget(about_label)
        scroll_area.setWidgetResizable(True)
        scroll_area.setStyleSheet("background: transparent;")

        content_layout.addWidget(scroll_area)

        # Add "Check for updates" button
        update_button = QtWidgets.QPushButton('Check for updates')
        update_button.setStyleSheet("""
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
        update_button.mousePressEvent = self.disable_right_click
        update_button.clicked.connect(self.check_for_updates)
        content_layout.addWidget(update_button)

    def check_for_updates(self):
        """
        Open the GitHub releases page to check for updates.
        """
        webbrowser.open("https://github.com/theJayTea/WritingTools/releases")

    def original_app(self):
        """
        Open the original app GitHub page.
        """
        webbrowser.open("https://github.com/TheJayTea/WritingTools")

    def disable_right_click(self, event):
        if event.button() == Qt.RightButton:
            event.ignore()
        else:
            super(QtWidgets.QPushButton, self.update_button).mousePressEvent(event)
