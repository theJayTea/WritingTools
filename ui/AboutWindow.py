import webbrowser

from PySide6 import QtWidgets, QtCore

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
        self.setWindowTitle('About Writing Tools')
        self.setGeometry(300, 300, 400, 400)  # Increased height to accommodate new content
        UIUtils.setup_window_and_layout(self)

        content_layout = QtWidgets.QVBoxLayout(self.background)
        content_layout.setContentsMargins(30, 30, 30, 30)
        content_layout.setSpacing(20)

        title_label = QtWidgets.QLabel("About Writing Tools")
        title_label.setStyleSheet(f"font-size: 24px; font-weight: bold; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        content_layout.addWidget(title_label, alignment=QtCore.Qt.AlignmentFlag.AlignCenter)

        about_text = """
                <p style='text-align: center;'>
                <b>Writing Tools</b> is a free and lightweight application that helps you improve your writing with AI, similar to Apple's new Apple Intelligence feature.<br><br>
                It's completely free for you to use as you provide your own free Gemini API key.<br><br>
                The AI model used here, Gemini 1.5 Flash, offers significantly better performance than Apple's on-device model, resulting in more natural and less robotic text refinements.<br><br><br>
                </p>
                <p style='text-align: center;'>
                <b>Made with love by Jesai, a high school student.</b><br><br>
                Feel free to check out my other AI app, <a href="https://play.google.com/store/apps/details?id=com.jesai.blissai">Bliss AI</a>. It's a novel AI tutor that's free on the Google Play Store :)<br><br>
                </p>
                <p style='text-align: center;'>
                <b>Contributors:</b> <a href="https://github.com/Disneyhockey40">Disneyhockey40 (Soszust40)</a><br><br>
                </p>
                <p style='text-align: center;'>
                <b>Contact me:</b> jesaitarun@gmail.com<br><br>
                </p>
                <p style='text-align: center;'>
                <b>Version:</b> 2.0 (Codename: Enhanced_Elegance)
                </p>
                """

        about_label = QtWidgets.QLabel(about_text)
        about_label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        about_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        about_label.setWordWrap(True)
        about_label.setOpenExternalLinks(True)  # Allow opening hyperlinks
        content_layout.addWidget(about_label)

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
        update_button.clicked.connect(self.check_for_updates)
        content_layout.addWidget(update_button)

    def check_for_updates(self):
        """
        Open the GitHub releases page to check for updates.
        """
        webbrowser.open("https://github.com/CameronRedmore/WritingTools/releases")

    def original_app(self):
        """
        Open the original app GitHub page.
        """
        webbrowser.open("https://github.com/TheJayTea/WritingTools")
