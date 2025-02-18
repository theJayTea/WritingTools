import json
import logging
import os
import sys
from functools import partial

from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPlainTextEdit,
    QPushButton,
    QRadioButton,
    QVBoxLayout,
    QWidget,
)

from ui.UIUtils import ThemeBackground, colorMode

_ = lambda x: x

################################################################################
# Default `options.json` content to restore when the user presses "Reset"
################################################################################
DEFAULT_OPTIONS_JSON = r"""{
  "Proofread": {
    "prefix": "Proofread this:\n\n",
    "instruction": "You are a grammar proofreading assistant.\nOutput ONLY the corrected text without any additional comments.\nMaintain the original text structure and writing style.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is absolutely incompatible with this (e.g., totally random gibberish), output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/magnifying-glass",
    "open_in_window": false
  },
  "Rewrite": {
    "prefix": "Rewrite this:\n\n",
    "instruction": "You are a writing assistant.\nRewrite the text provided by the user to improve phrasing.\nOutput ONLY the rewritten text without additional comments.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is absolutely incompatible with proofreading (e.g., totally random gibberish), output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/rewrite",
    "open_in_window": false
  },
  "Friendly": {
    "prefix": "Make this more friendly:\n\n",
    "instruction": "You are a writing assistant.\nRewrite the text provided by the user to be more friendly.\nOutput ONLY the friendly text without additional comments.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is absolutely incompatible with rewriting (e.g., totally random gibberish), output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/smiley-face",
    "open_in_window": false
  },
  "Professional": {
    "prefix": "Make this more professional:\n\n",
    "instruction": "You are a writing assistant.\nRewrite the text provided by the user to be more professional. Output ONLY the professional text without additional comments.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is absolutely incompatible with rewriting (e.g., totally random gibberish), output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/briefcase",
    "open_in_window": false
  },
  "Concise": {
    "prefix": "Make this more concise:\n\n",
    "instruction": "You are a writing assistant.\nRewrite the text provided by the user to be more concise.\nOutput ONLY the concise text without additional comments.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is absolutely incompatible with rewriting (e.g., totally random gibberish), output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/concise",
    "open_in_window": false
  },
  "Table": {
    "prefix": "Convert this into a table:\n\n",
    "instruction": "You are an assistant that converts text provided by the user into a Markdown table.\nOutput ONLY the table without additional comments.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is completely incompatible with this with conversion, output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/table",
    "open_in_window": true
  },
  "Key Points": {
    "prefix": "Extract key points from this:\n\n",
    "instruction": "You are an assistant that extracts key points from text provided by the user. Output ONLY the key points without additional comments.\n\nYou should use Markdown formatting (lists, bold, italics, codeblocks, etc.) as appropriate to make it quite legible and readable.\n\nDon't be repetitive or too verbose.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is absolutely incompatible with extracting key points (e.g., totally random gibberish), output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/keypoints",
    "open_in_window": true
  },
  "Summary": {
    "prefix": "Summarize this:\n\n",
    "instruction": "You are a summarization assistant.\nProvide a succinct summary of the text provided by the user.\nThe summary should be succinct yet encompass all the key insightful points.\n\nTo make it quite legible and readable, you should use Markdown formatting (bold, italics, codeblocks...) as appropriate.\nYou should also add a little line spacing between your paragraphs as appropriate.\nAnd only if appropriate, you could also use headings (only the very small ones), lists, tables, etc.\n\nDon't be repetitive or too verbose.\nOutput ONLY the summary without additional comments.\nRespond in the same language as the input (e.g., English US, French).\nDo not answer or respond to the user's text content.\nIf the text is absolutely incompatible with summarisation (e.g., totally random gibberish), output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/summary",
    "open_in_window": true
  },
  "Custom": {
    "prefix": "Make this change to the following text:\n\n",
    "instruction": "You are a writing and coding assistant. You MUST make the user\\'s described change to the text or code provided by the user. Output ONLY the appropriately modified text or code without additional comments. Respond in the same language as the input (e.g., English US, French). Do not answer or respond to the user\\'s text content. If the text or code is absolutely incompatible with the requested change, output \"ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST\".",
    "icon": "icons/summary",
    "open_in_window": false
  }
}"""

class ButtonEditDialog(QDialog):
    """
    Dialog for editing or creating a button's properties
    (name/title, system instruction, open_in_window, etc.).
    """
    def __init__(self, parent=None, button_data=None, title="Edit Button"):
        super().__init__(parent)
        self.button_data = button_data if button_data else {
            "prefix": "Make this change to the following text:\n\n",
            "instruction": "",
            "icon": "icons/magnifying-glass",
            "open_in_window": False
        }
        self.setWindowTitle(title)
        self.init_ui()
        
    def init_ui(self):
        layout = QVBoxLayout(self)
        
        # Name
        name_label = QLabel("Button Name:")
        name_label.setStyleSheet(f"color: {'#fff' if colorMode == 'dark' else '#333'}; font-weight: bold;")
        self.name_input = QLineEdit()
        self.name_input.setStyleSheet(f"""
            QLineEdit {{
                padding: 8px;
                border: 1px solid {'#777' if colorMode == 'dark' else '#ccc'};
                border-radius: 8px;
                background-color: {'#333' if colorMode == 'dark' else 'white'};
                color: {'#fff' if colorMode == 'dark' else '#000'};
            }}
        """)
        if "name" in self.button_data:
            self.name_input.setText(self.button_data["name"])
        layout.addWidget(name_label)
        layout.addWidget(self.name_input)
        
        # Instruction (changed to a multiline QPlainTextEdit)
        instruction_label = QLabel("What should your AI do with your selected text? (System Instruction)")
        instruction_label.setStyleSheet(f"color: {'#fff' if colorMode == 'dark' else '#333'}; font-weight: bold;")
        self.instruction_input = QPlainTextEdit()
        self.instruction_input.setStyleSheet(f"""
            QPlainTextEdit {{
                padding: 8px;
                border: 1px solid {'#777' if colorMode == 'dark' else '#ccc'};
                border-radius: 8px;
                background-color: {'#333' if colorMode == 'dark' else 'white'};
                color: {'#fff' if colorMode == 'dark' else '#000'};
            }}
        """)
        self.instruction_input.setPlainText(self.button_data.get("instruction", ""))
        self.instruction_input.setMinimumHeight(100)
        self.instruction_input.setPlaceholderText("""Examples:
    - Fix / improve / explain this code.
    - Make it funny.
    - Add emojis!
    - Roast this!
    - Translate to English.
    - Make the text title case.
    - If it's all caps, make it all small, and vice-versa.
    - Write a reply to this.
    - Analyse potential biases in this news article.""")
        layout.addWidget(instruction_label)
        layout.addWidget(self.instruction_input)
        
        # open_in_window
        display_label = QLabel("How should your AI response be shown?")
        display_label.setStyleSheet(f"color: {'#fff' if colorMode == 'dark' else '#333'}; font-weight: bold;")
        layout.addWidget(display_label)
        
        radio_layout = QHBoxLayout()
        self.replace_radio = QRadioButton("Replace the selected text")
        self.window_radio = QRadioButton("In a pop-up window (with follow-up support)")
        for r in (self.replace_radio, self.window_radio):
            r.setStyleSheet(f"color: {'#fff' if colorMode == 'dark' else '#333'};")
        
        self.replace_radio.setChecked(not self.button_data.get("open_in_window", False))
        self.window_radio.setChecked(self.button_data.get("open_in_window", False))
        
        radio_layout.addWidget(self.replace_radio)
        radio_layout.addWidget(self.window_radio)
        layout.addLayout(radio_layout)
        
        # OK & Cancel
        btn_layout = QHBoxLayout()
        ok_button = QPushButton("OK")
        cancel_button = QPushButton("Cancel")
        for btn in (ok_button, cancel_button):
            btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: {'#444' if colorMode == 'dark' else '#f0f0f0'};
                    color: {'#fff' if colorMode == 'dark' else '#000'};
                    border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
                    border-radius: 5px;
                    padding: 8px;
                    min-width: 100px;
                }}
                QPushButton:hover {{
                    background-color: {'#555' if colorMode == 'dark' else '#e0e0e0'};
                }}
            """)
        btn_layout.addWidget(ok_button)
        btn_layout.addWidget(cancel_button)
        layout.addLayout(btn_layout)
        
        ok_button.clicked.connect(self.accept)
        cancel_button.clicked.connect(self.reject)
        
        self.setStyleSheet(f"""
            QDialog {{
                background-color: {'#222' if colorMode == 'dark' else '#f5f5f5'};
                border-radius: 10px;
            }}
        """)

    def get_button_data(self):
        return {
            "name": self.name_input.text(),
            "prefix": "Make this change to the following text:\n\n",
            # Retrieve multiline text
            "instruction": self.instruction_input.toPlainText(),
            "icon": "icons/custom",
            "open_in_window": self.window_radio.isChecked()
        }

class DraggableButton(QtWidgets.QPushButton):
    def __init__(self, parent_popup, key, text):
        super().__init__(text, parent_popup)
        self.popup = parent_popup
        self.key = key
        self.drag_start_position = None
        self.setAcceptDrops(True)
        self.icon_container = None

        # Enable mouse tracking and hover events, and styled background
        self.setMouseTracking(True)
        self.setAttribute(QtCore.Qt.WA_Hover, True)
        self.setAttribute(QtCore.Qt.WA_StyledBackground, True)

        # Use a dynamic property "hover" (default False)
        self.setProperty("hover", False)

        # Set fixed size (adjust as needed)
        self.setFixedSize(120, 40)

        # Define base style using the dynamic property instead of the :hover pseudo-class
        self.base_style = f"""
            QPushButton {{
                background-color: {"#444" if colorMode=="dark" else "white"};
                border: 1px solid {"#666" if colorMode=="dark" else "#ccc"};
                border-radius: 8px;
                padding: 10px;
                font-size: 14px;
                text-align: left;
                color: {"#fff" if colorMode=="dark" else "#000"};
            }}
            QPushButton[hover="true"] {{
                background-color: {"#555" if colorMode=="dark" else "#f0f0f0"};
            }}
        """
        self.setStyleSheet(self.base_style)
        logging.debug("DraggableButton initialized")

    def enterEvent(self, event):
        # Only update the hover property if NOT in edit mode.
        if not self.popup.edit_mode:
            self.setProperty("hover", True)
            self.style().unpolish(self)
            self.style().polish(self)
        super().enterEvent(event)

    def leaveEvent(self, event):
        if not self.popup.edit_mode:
            self.setProperty("hover", False)
            self.style().unpolish(self)
            self.style().polish(self)
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if event.button() == QtCore.Qt.LeftButton:
            if self.popup.edit_mode:
                self.drag_start_position = event.pos()
                event.accept()
                return
        super().mousePressEvent(event)
            
    def mouseMoveEvent(self, event):
        if not (event.buttons() & QtCore.Qt.LeftButton) or not self.drag_start_position:
            return

        distance = (event.pos() - self.drag_start_position).manhattanLength()
        if distance < QtWidgets.QApplication.startDragDistance():
            return

        if self.popup.edit_mode:
            drag = QtGui.QDrag(self)
            mime_data = QtCore.QMimeData()
            idx = self.popup.button_widgets.index(self)
            mime_data.setData("application/x-button-index", str(idx).encode())
            drag.setMimeData(mime_data)

            pixmap = self.grab()
            drag.setPixmap(pixmap)
            drag.setHotSpot(event.pos())

            self.drag_start_position = None
            drop_action = drag.exec_(QtCore.Qt.MoveAction)
            logging.debug(f"Drag completed with action: {drop_action}")

    def dragEnterEvent(self, event):
        if self.popup.edit_mode and event.mimeData().hasFormat("application/x-button-index"):
            event.acceptProposedAction()
            self.setStyleSheet(self.base_style + """
                QPushButton {
                    border: 2px dashed #666;
                }
            """)
        else:
            event.ignore()

    def dragLeaveEvent(self, event):
        self.setStyleSheet(self.base_style)
        event.accept()

    def dropEvent(self, event):
        if not self.popup.edit_mode or not event.mimeData().hasFormat("application/x-button-index"):
            event.ignore()
            return

        source_idx = int(event.mimeData().data("application/x-button-index").data().decode())
        target_idx = self.popup.button_widgets.index(self)

        if source_idx != target_idx:
            bw = self.popup.button_widgets
            bw[source_idx], bw[target_idx] = bw[target_idx], bw[source_idx]
            self.popup.rebuild_grid_layout()
            self.popup.update_json_from_grid()

        self.setStyleSheet(self.base_style)
        event.setDropAction(QtCore.Qt.MoveAction)
        event.acceptProposedAction()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.icon_container:
            self.icon_container.setGeometry(0, 0, self.width(), self.height())

class CustomPopupWindow(QtWidgets.QWidget):
    def __init__(self, app, selected_text):
        super().__init__()
        self.app = app
        self.selected_text = selected_text
        self.edit_mode = False
        self.has_text = bool(selected_text.strip())
        
        self.drag_label = None
        self.edit_button = None
        self.reset_button = None
        self.close_button = None
        self.custom_input = None
        self.input_area = None
        
        self.button_widgets = []

        logging.debug('Initializing CustomPopupWindow')
        self.init_ui()

    def init_ui(self):
        logging.debug('Setting up CustomPopupWindow UI')
        self.setWindowFlags(QtCore.Qt.WindowStaysOnTopHint | QtCore.Qt.FramelessWindowHint)
        self.setAttribute(QtCore.Qt.WA_TranslucentBackground)
        self.setWindowTitle("Writing Tools")
        
        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.setContentsMargins(0,0,0,0)
        
        self.background = ThemeBackground(
            self, 
            self.app.config.get('theme','gradient'),
            is_popup=True,
            border_radius=10
        )
        main_layout.addWidget(self.background)
        
        content_layout = QtWidgets.QVBoxLayout(self.background)
        # Margin Control
        content_layout.setContentsMargins(10, 4, 10, 10)
        content_layout.setSpacing(10)
        
        # TOP BAR LAYOUT & STYLE
        top_bar = QHBoxLayout()
        top_bar.setContentsMargins(0, 0, 0, 0)
        top_bar.setSpacing(0)

        # The "Edit"/"Done" button (left), same exact size as close button
        self.edit_button = QPushButton()
        pencil_icon = os.path.join(os.path.dirname(sys.argv[0]),
                                'icons',
                                'pencil' + ('_dark' if colorMode=='dark' else '_light') + '.png')
        if os.path.exists(pencil_icon):
            self.edit_button.setIcon(QtGui.QIcon(pencil_icon))
        # Reduced size to 24x24 to shrink top bar
        self.edit_button.setFixedSize(24, 24)
        self.edit_button.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                border: none;
                border-radius: 6px;
                padding: 0px;
                margin-top: 3px;
            }}
            QPushButton:hover {{
                background-color: {'#333' if colorMode=='dark' else '#ebebeb'};
            }}
        """)
        self.edit_button.clicked.connect(self.toggle_edit_mode)
        top_bar.addWidget(self.edit_button, 0, Qt.AlignLeft)

        # The label "Drag to rearrange" (BOLD as requested)
        self.drag_label = QLabel("Drag to rearrange")
        self.drag_label.setStyleSheet(f"""
            color: {'#fff' if colorMode=='dark' else '#333'};
            font-size: 14px;
            font-weight: bold; /* <--- BOLD TEXT */
        """)
        self.drag_label.setAlignment(Qt.AlignCenter)
        self.drag_label.hide()
        top_bar.addWidget(self.drag_label, 1, Qt.AlignVCenter | Qt.AlignHCenter)

        # The "Reset" button (edit-mode only) - also 24x24
        self.reset_button = QPushButton()
        reset_icon_path = os.path.join(os.path.dirname(sys.argv[0]), 'icons',
                                    'restore' + ('_dark' if colorMode=='dark' else '_light') + '.png')
        if os.path.exists(reset_icon_path):
            self.reset_button.setIcon(QtGui.QIcon(reset_icon_path))
        self.reset_button.setText("")
        self.reset_button.setFixedSize(24, 24)
        self.reset_button.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                border: none;
                border-radius: 6px;
                padding: 0px;
            }}
            QPushButton:hover {{
                background-color: {'#333' if colorMode=='dark' else '#ebebeb'};
            }}
        """)
        self.reset_button.clicked.connect(self.on_reset_clicked)
        self.reset_button.hide()
        top_bar.addWidget(self.reset_button, 0, Qt.AlignRight)

        # Close button block:
        self.close_button = QPushButton("×")
        self.close_button.setFixedSize(24, 24)
        self.close_button.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                color: {'#fff' if colorMode=='dark' else '#333'};
                font-size: 20px;   /* bigger text */
                font-weight: bold; /* bold text */
                border: none;
                border-radius: 6px;
                padding: 0px;
            }}
            QPushButton:hover {{
                background-color: {'#333' if colorMode=='dark' else '#ebebeb'};
            }}
        """)
        self.close_button.clicked.connect(self.close)
        top_bar.addWidget(self.close_button, 0, Qt.AlignRight)
        content_layout.addLayout(top_bar)

        
        # Input area (hidden in edit mode)
        self.input_area = QWidget()
        input_layout = QHBoxLayout(self.input_area)
        input_layout.setContentsMargins(0,0,0,0)
        
        self.custom_input = QLineEdit()
        self.custom_input.setPlaceholderText(_("Describe your change...") if self.has_text else _("Ask your AI..."))
        self.custom_input.setStyleSheet(f"""
            QLineEdit {{
                padding: 8px;
                border: 1px solid {'#777' if colorMode=='dark' else '#ccc'};
                border-radius: 8px;
                background-color: {'#333' if colorMode=='dark' else 'white'};
                color: {'#fff' if colorMode=='dark' else '#000'};
            }}
        """)
        self.custom_input.returnPressed.connect(self.on_custom_change)
        input_layout.addWidget(self.custom_input)
        
        send_btn = QPushButton()
        send_icon = os.path.join(os.path.dirname(sys.argv[0]),
                                'icons',
                                'send' + ('_dark' if colorMode=='dark' else '_light') + '.png')
        if os.path.exists(send_icon):
            send_btn.setIcon(QtGui.QIcon(send_icon))
        send_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: {'#2e7d32' if colorMode=='dark' else '#4CAF50'};
                border: none;
                border-radius: 8px;
                padding: 5px;
            }}
            QPushButton:hover {{
                background-color: {'#1b5e20' if colorMode=='dark' else '#45a049'};
            }}
        """)
        send_btn.setFixedSize(self.custom_input.sizeHint().height(),
                            self.custom_input.sizeHint().height())
        send_btn.clicked.connect(self.on_custom_change)
        input_layout.addWidget(send_btn)
        
        content_layout.addWidget(self.input_area)
        
        if self.has_text:
            self.build_buttons_list()
            self.rebuild_grid_layout(content_layout)
        else:
            # If no text, hide the edit button; user can only do custom instructions
            self.edit_button.hide()
            self.custom_input.setMinimumWidth(300)

        # show update notice if applicable
        if self.app.config.get("update_available", False):
            update_label = QLabel()
            update_label.setOpenExternalLinks(True)
            update_label.setText('<a href="https://github.com/theJayTea/WritingTools/releases" style="color:rgb(255, 0, 0); text-decoration: underline; font-weight: bold;">There\'s an update! :D Download now.</a>')
            update_label.setStyleSheet("margin-top: 10px;")
            content_layout.addWidget(update_label, alignment=QtCore.Qt.AlignCenter)
        
        logging.debug('CustomPopupWindow UI setup complete')
        self.installEventFilter(self)
        QtCore.QTimer.singleShot(250, lambda: self.custom_input.setFocus())

    @staticmethod
    def load_options():
        options_path = os.path.join(os.path.dirname(sys.argv[0]), 'options.json')
        if os.path.exists(options_path):
            with open(options_path, 'r') as f:
                data = json.load(f)
                logging.debug('Options loaded successfully')
        else:
            logging.debug('Options file not found')

        return data

    @staticmethod
    def save_options(options):
        options_path = os.path.join(os.path.dirname(sys.argv[0]), 'options.json')
        with open(options_path, 'w') as f:
            json.dump(options, f, indent=2)

    def build_buttons_list(self):
        """
        Reads options.json, creates DraggableButton for each (except "Custom"),
        storing them in self.button_widgets in the same order as the JSON file.
        """
        self.button_widgets.clear()
        data = self.load_options()

        for k,v in data.items():
            if k=="Custom":
                continue
            b = DraggableButton(self, k, k)
            icon_path = os.path.join(os.path.dirname(sys.argv[0]),
                                    v["icon"] + ('_dark' if colorMode=='dark' else '_light') + '.png')
            if os.path.exists(icon_path):
                b.setIcon(QtGui.QIcon(icon_path))
                
            if not self.edit_mode:
                b.clicked.connect(partial(self.on_generic_instruction, k))
            self.button_widgets.append(b)

    def rebuild_grid_layout(self, parent_layout=None):
        """Rebuild grid layout with consistent sizing and proper Add New button placement."""
        if not parent_layout:
            parent_layout = self.background.layout()

        # Remove existing grid and Add New button
        for i in reversed(range(parent_layout.count())):
            item = parent_layout.itemAt(i)
            if isinstance(item, QtWidgets.QGridLayout):
                grid = item
                for j in reversed(range(grid.count())):
                    w = grid.itemAt(j).widget()
                    if w:
                        grid.removeWidget(w)
                parent_layout.removeItem(grid)
            elif (item.widget() and isinstance(item.widget(), QPushButton) 
                and item.widget().text() == "+ Add New"):
                item.widget().deleteLater()

        # Create new grid with fixed column width
        grid = QtWidgets.QGridLayout()
        grid.setSpacing(10)  
        grid.setColumnMinimumWidth(0, 120)
        grid.setColumnMinimumWidth(1, 120)
        
        # Add buttons to grid
        row = 0
        col = 0
        for b in self.button_widgets:
            grid.addWidget(b, row, col)
            col += 1
            if col > 1:
                col = 0
                row += 1
        
        parent_layout.addLayout(grid)
        
        # Add New button (only in edit mode & only if we have text)
        if self.edit_mode and self.has_text:
            add_btn = QPushButton("+ Add New")
            add_btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: {'#333' if colorMode=='dark' else '#e0e0e0'};
                    border: 1px solid {'#666' if colorMode=='dark' else '#ccc'};
                    border-radius: 8px;
                    padding: 10px;
                    font-size: 14px;
                    text-align: center;
                    color: {'#fff' if colorMode=='dark' else '#000'};
                    margin-top: 10px;
                }}
                QPushButton:hover {{
                    background-color: {'#444' if colorMode=='dark' else '#d0d0d0'};
                }}
            """)
            add_btn.clicked.connect(self.add_new_button_clicked)
            parent_layout.addWidget(add_btn)

    def add_edit_delete_icons(self, btn):
        """Add edit/delete icons as overlays with proper spacing."""
        if hasattr(btn, 'icon_container') and btn.icon_container:
            btn.icon_container.deleteLater()
        
        btn.icon_container = QtWidgets.QWidget(btn)
        btn.icon_container.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, False)
        
        btn.icon_container.setGeometry(0, 0, btn.width(), btn.height())
        
        circle_style = f"""
            QPushButton {{
                background-color: {'#666' if colorMode=='dark' else '#999'};
                border-radius: 10px;
                min-width: 16px;
                min-height: 16px;
                max-width: 16px;
                max-height: 16px;
                padding: 1px;
                margin: 0px;
            }}
            QPushButton:hover {{
                background-color: {'#888' if colorMode=='dark' else '#bbb'};
            }}
        """
        
        # Create edit icon (top-left)
        edit_btn = QPushButton(btn.icon_container)
        edit_btn.setGeometry(3, 3, 16, 16)
        pencil_icon = os.path.join(os.path.dirname(sys.argv[0]),
                        'icons', 'pencil' + ('_dark' if colorMode=='dark' else '_light') + '.png')
        if os.path.exists(pencil_icon):
            edit_btn.setIcon(QtGui.QIcon(pencil_icon))
        edit_btn.setStyleSheet(circle_style)
        edit_btn.clicked.connect(partial(self.edit_button_clicked, btn))
        edit_btn.show()
        
        # Create delete icon (top-right)
        delete_btn = QPushButton(btn.icon_container)
        delete_btn.setGeometry(btn.width() - 23, 3, 16, 16)
        del_icon = os.path.join(os.path.dirname(sys.argv[0]),
                                'icons', 'cross' + ('_dark' if colorMode=='dark' else '_light') + '.png')
        if os.path.exists(del_icon):
            delete_btn.setIcon(QtGui.QIcon(del_icon))
        delete_btn.setStyleSheet(circle_style)
        delete_btn.clicked.connect(partial(self.delete_button_clicked, btn))
        delete_btn.show()
        
        btn.icon_container.raise_()
        btn.icon_container.show()

    def toggle_edit_mode(self):
        """Toggle edit mode with improved button labels and state handling."""
        self.edit_mode = not self.edit_mode
        logging.debug(f'Edit mode toggled: {self.edit_mode}')

        if self.edit_mode:
            # Switch to edit mode:
            icon_name = "check"
            # No text, just the check icon, a bit bigger:
            self.edit_button.setText("")
            self.edit_button.setFixedSize(36, 36)
            self.edit_button.setStyleSheet(f"""
                QPushButton {{
                    background-color: transparent;
                    border: none;
                    border-radius: 6px;
                    padding: 0px;
                }}
                QPushButton:hover {{
                    background-color: {'#333' if colorMode=='dark' else '#ebebeb'};
                }}
            """)
            # Hide close, show reset button & drag label
            self.close_button.hide()
            self.reset_button.show()
            self.drag_label.show()

        else:
            # Switch back to normal (non-edit) mode:
            icon_name = "pencil"
            self.edit_button.setText("")
            self.edit_button.setFixedSize(24, 24)  # Return to normal size
            # Show close, hide reset & drag label
            self.close_button.show()
            self.reset_button.hide()
            self.drag_label.hide()

            # Inform the user that the app will close to apply changes
            msg = QtWidgets.QMessageBox()
            msg.setWindowTitle("Quitting to apply changes...")
            msg.setText("Writing Tools needs to relaunch to apply your changes & will now quit.\nPlease relaunch Writing Tools.exe to see your changes.")
            msg.setStandardButtons(QtWidgets.QMessageBox.Ok)
            msg.exec_()

            self.app.load_options()
            self.close()
            # Instead of restarting, simply exit the app:
            QtCore.QTimer.singleShot(100, self.app.exit_app)
            return


        # Update the edit button icon now that icon_name is defined
        icon_path = os.path.join(
            os.path.dirname(sys.argv[0]),
            'icons',
            f"{icon_name}_{'dark' if colorMode=='dark' else 'light'}.png"
        )
        if os.path.exists(icon_path):
            self.edit_button.setIcon(QtGui.QIcon(icon_path))

        # Toggle the main input area
        self.input_area.setVisible(not self.edit_mode)

        # Update button overlays
        for btn in self.button_widgets:
            try:
                btn.clicked.disconnect()
            except:
                pass

            if not self.edit_mode:
                btn.clicked.connect(partial(self.on_generic_instruction, btn.key))
                if hasattr(btn, 'icon_container') and btn.icon_container:
                    btn.icon_container.deleteLater()
                    btn.icon_container = None
            else:
                self.add_edit_delete_icons(btn)

            btn.setStyleSheet(btn.base_style)

        # Rebuild grid layout
        self.rebuild_grid_layout()


    def on_reset_clicked(self):
        """
        Reset `options.json` to the DEFAULT_OPTIONS_JSON, then show message & restart.
        """
        confirm_box = QtWidgets.QMessageBox()
        confirm_box.setWindowTitle("Confirm Reset to Defaults & Quit?")
        confirm_box.setText("To reset the buttons to their original configuration, Writing Tools would need to quit, so you'd need to relaunch Writing Tools.exe.\nAre you sure you want to continue?")
        confirm_box.setStandardButtons(QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No)
        confirm_box.setDefaultButton(QtWidgets.QMessageBox.No)
        
        if confirm_box.exec_() == QtWidgets.QMessageBox.Yes:
            try:
                logging.debug('Resetting to default options.json')
                default_data = json.loads(DEFAULT_OPTIONS_JSON)
                self.save_options(default_data)

                # Save and quit
                self.app.load_options()
                self.close()
                QtCore.QTimer.singleShot(100, self.app.exit_app)
            
            except Exception as e:
                logging.error(f"Error resetting options.json: {e}")
                error_msg = QtWidgets.QMessageBox()
                error_msg.setWindowTitle("Error")
                error_msg.setText(f"An error occurred while resetting: {str(e)}")
                error_msg.exec_()

    def add_new_button_clicked(self):
        dialog = ButtonEditDialog(self, title="Add New Button")
        if dialog.exec_():
            bd = dialog.get_button_data()
            data = self.load_options()
            data[bd["name"]] = {
                "prefix": bd["prefix"],
                "instruction": bd["instruction"],
                "icon": bd["icon"],  # uses 'icons/custom'
                "open_in_window": bd["open_in_window"]
            }
            self.save_options(data)

            self.build_buttons_list()
            self.rebuild_grid_layout()

            self.hide()
            
            QtWidgets.QMessageBox.information(
                self, 
                "Quitting to apply button...",
                "Writing Tools needs to relaunch to apply your fancy button & will now quit.\nPlease relaunch Writing Tools.exe to see your new button."
            )

            self.app.load_options()
            self.close()
            QtCore.QTimer.singleShot(100, self.app.exit_app)


    def edit_button_clicked(self, btn):
        """User clicked the small pencil icon over a button."""
        key = btn.key
        data = self.load_options()
        bd = data[key]
        bd["name"] = key
        
        dialog = ButtonEditDialog(self, bd)
        if dialog.exec_():
            new_data = dialog.get_button_data()
            data = self.load_options()
            if new_data["name"] != key:
                del data[key]
            data[new_data["name"]] = {
                "prefix": new_data["prefix"],
                "instruction": new_data["instruction"],
                "icon": new_data["icon"],
                "open_in_window": new_data["open_in_window"]
            }
            self.save_options(data)

            self.build_buttons_list()
            self.rebuild_grid_layout()

            self.hide()

            # Show message about relaunch requirement
            QtWidgets.QMessageBox.information(
                self, 
                "Quitting to apply changes to this button...",
                "Writing Tools needs to relaunch to apply your changes & will now quit.\nPlease relaunch Writing Tools.exe to see your changes."
            )

            # Save and quit
            self.app.load_options()
            self.close()
            QtCore.QTimer.singleShot(100, self.app.exit_app)

    def delete_button_clicked(self, btn):
        """Handle deletion of a button."""
        key = btn.key
        confirm = QtWidgets.QMessageBox()
        confirm.setWindowTitle("Confirm Delete & Quit?")
        confirm.setText(f"To delete the '{key}' button, Writing Tools would need to quit, so you'd need to relaunch Writing Tools.exe.\nAre you sure you want to continue?")
        confirm.setStandardButtons(QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No)
        confirm.setDefaultButton(QtWidgets.QMessageBox.No)
        
        if confirm.exec_() == QtWidgets.QMessageBox.Yes:
            try:
                data = self.load_options()
                del data[key]
                self.save_options(data)

                # Clean up UI elements
                for btn_ in self.button_widgets[:]:
                    if btn_.key == key:
                        if hasattr(btn_, 'icon_container') and btn_.icon_container:
                            btn_.icon_container.deleteLater()
                        btn_.deleteLater()
                        self.button_widgets.remove(btn_)
                
                self.app.load_options()
                self.close()
                QtCore.QTimer.singleShot(100, self.app.exit_app)
                
            except Exception as e:
                logging.error(f"Error deleting button: {e}")
                error_msg = QtWidgets.QMessageBox()
                error_msg.setWindowTitle("Error")
                error_msg.setText(f"An error occurred while deleting the button: {str(e)}")
                error_msg.exec_()

    def update_json_from_grid(self):
        """
        Called after a drop reorder. Reflect the new order in options.json,
        so that user's custom arrangement persists.
        """
        data = self.load_options()
        new_data = {"Custom": data["Custom"]} if "Custom" in data else {}
        for b in self.button_widgets:
            new_data[b.key] = data[b.key]
        self.save_options(new_data)

    def on_custom_change(self):
        txt = self.custom_input.text().strip()
        if txt:
            self.app.process_option('Custom', self.selected_text, txt)
            self.close()

    def on_generic_instruction(self, instruction):
        if not self.edit_mode:
            self.app.process_option(instruction, self.selected_text)
            self.close()

    def eventFilter(self, obj, event):
        # Hide on deactivate only if NOT in edit mode
        if event.type()==QtCore.QEvent.WindowDeactivate:
            if not self.edit_mode:
                self.hide()
                return True
        return super().eventFilter(obj, event)

    def keyPressEvent(self, event):
        if event.key()==QtCore.Qt.Key_Escape:
            self.close()
        else:
            super().keyPressEvent(event)
