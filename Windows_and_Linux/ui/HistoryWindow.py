import logging

from PySide6 import QtCore, QtGui, QtWidgets
from PySide6.QtCore import QSettings
from PySide6.QtGui import QCursor, QGuiApplication

from ui.UIUtils import UIUtils, colorMode

_ = lambda x: x

# Max characters of the input snippet shown as the clickable "title".
_TITLE_MAX_CHARS = 80
# Max characters of the secondary line (first line of the input, also used as
# fallback when no input is available).
_PREVIEW_SECONDARY_MAX_CHARS = 120


class HistoryEntryWidget(QtWidgets.QWidget):
    """
    Expandable widget for a single history entry.

    Renders the entry as a clickable "title" row (first line of the user's
    input, with timestamp/option as secondary metadata). Clicking the row
    expands the full conversation transcript. Expansion is coordinated by the
    owning HistoryWindow so only one entry is expanded at a time.
    """

    def __init__(self, entry, parent=None):
        super().__init__(parent)
        self.entry = entry or {}
        self.preview_button = None
        self.details_widget = None
        self.conversation_label = None
        self.conversation_text = None
        # Optional callback invoked whenever this entry's expanded state
        # changes. The owning HistoryWindow uses it to implement the
        # "one expanded at a time" accordion behavior.
        self.on_expanded_changed = None
        self._build_ui()
        self.set_entry(self.entry)

    def _build_ui(self):
        try:
            root_layout = QtWidgets.QVBoxLayout(self)
            root_layout.setContentsMargins(0, 0, 0, 0)
            root_layout.setSpacing(6)

            self.preview_button = QtWidgets.QToolButton()
            self.preview_button.setCheckable(True)
            self.preview_button.setChecked(False)
            self.preview_button.setArrowType(QtCore.Qt.ArrowType.RightArrow)
            self.preview_button.setToolButtonStyle(
                QtCore.Qt.ToolButtonStyle.ToolButtonTextOnly
            )
            self.preview_button.setSizePolicy(
                QtWidgets.QSizePolicy.Policy.Expanding,
                QtWidgets.QSizePolicy.Policy.Fixed,
            )
            self.preview_button.setStyleSheet(f"""
                QToolButton {{
                    text-align: left;
                    padding: 10px 12px;
                    border-radius: 6px;
                    background-color: {'#2f2f2f' if colorMode == 'dark' else '#f4f4f4'};
                    color: {'#ffffff' if colorMode == 'dark' else '#222222'};
                    border: 1px solid {'#4a4a4a' if colorMode == 'dark' else '#d0d0d0'};
                    font-size: 13px;
                }}
                QToolButton:hover {{
                    background-color: {'#3a3a3a' if colorMode == 'dark' else '#ececec'};
                }}
                QToolButton:checked {{
                    background-color: {'#3a3a3a' if colorMode == 'dark' else '#e6e6e6'};
                }}
            """)
            self.preview_button.toggled.connect(self._toggle_expanded)
            root_layout.addWidget(self.preview_button)

            self.details_widget = QtWidgets.QWidget()
            self.details_widget.setVisible(False)
            self.details_widget.setStyleSheet(f"""
                QWidget {{
                    border: 1px solid {'#4a4a4a' if colorMode == 'dark' else '#d6d6d6'};
                    border-radius: 6px;
                    background-color: {'#252525' if colorMode == 'dark' else '#ffffff'};
                }}
            """)

            details_layout = QtWidgets.QVBoxLayout(self.details_widget)
            details_layout.setContentsMargins(12, 12, 12, 12)
            details_layout.setSpacing(8)

            self.conversation_label = QtWidgets.QLabel(_("Conversation"))
            self.conversation_label.setStyleSheet(
                f"font-weight: bold; color: {'#ffffff' if colorMode == 'dark' else '#222222'};"
            )
            details_layout.addWidget(self.conversation_label)

            self.conversation_text = QtWidgets.QPlainTextEdit()
            self.conversation_text.setReadOnly(True)
            self.conversation_text.setMinimumHeight(160)
            self.conversation_text.setStyleSheet(f"""
                QPlainTextEdit {{
                    border: 1px solid {'#555555' if colorMode == 'dark' else '#d9d9d9'};
                    border-radius: 4px;
                    background-color: {'#1e1e1e' if colorMode == 'dark' else '#fafafa'};
                    color: {'#ffffff' if colorMode == 'dark' else '#222222'};
                    font-size: 13px;
                    padding: 6px;
                }}
            """)
            details_layout.addWidget(self.conversation_text)

            root_layout.addWidget(self.details_widget)
        except Exception as e:
            logging.error(f'HistoryEntryWidget._build_ui failed: {e}', exc_info=True)
            raise

    def _toggle_expanded(self, expanded):
        self.preview_button.setArrowType(
            QtCore.Qt.ArrowType.DownArrow if expanded else QtCore.Qt.ArrowType.RightArrow
        )
        self.details_widget.setVisible(expanded)
        if self.on_expanded_changed is not None:
            try:
                self.on_expanded_changed(self, expanded)
            except Exception as e:
                logging.error(f'on_expanded_changed callback failed: {e}', exc_info=True)

    def _truncate(self, text, limit):
        text = text.strip()
        if len(text) <= limit:
            return text
        return text[: max(0, limit - 3)].rstrip() + '...'

    def _build_title(self, entry):
        """
        Build the user-facing "title" line for the entry.

        Uses the first line of the user's input (or the first user turn in
        the conversation) as the primary title — this is what the user
        remembers the conversation by. Falls back to the first line of the
        output when no user input is available.
        """
        input_text = str(entry.get('input') or '').strip()
        if not input_text:
            conversation = entry.get('conversation') or []
            if isinstance(conversation, list):
                for turn in conversation:
                    if isinstance(turn, dict) and turn.get('role') == 'user':
                        input_text = str(turn.get('content') or '').strip()
                        if input_text:
                            break

        if not input_text:
            output_text = str(entry.get('output') or '').strip()
            if output_text:
                input_text = output_text

        if not input_text:
            return _("(No content)")

        first_line = input_text.splitlines()[0] if input_text else ''
        return self._truncate(first_line, _TITLE_MAX_CHARS)

    def _build_metadata(self, entry):
        timestamp = str(entry.get('timestamp') or '').strip()
        option = str(entry.get('option') or '').strip()
        parts = [p for p in (timestamp, option) if p]
        return '  •  '.join(parts)

    @staticmethod
    def _format_conversation(conversation):
        if not isinstance(conversation, list):
            return ''

        lines = []
        for turn in conversation:
            if not isinstance(turn, dict):
                continue
            role = 'Assistant' if turn.get('role') == 'assistant' else 'User'
            content = str(turn.get('content') or '').strip()
            if not content:
                continue
            lines.append(f"{role}:")
            lines.append(content)
            lines.append('')
        return '\n'.join(lines).strip()

    def set_entry(self, entry):
        try:
            self.entry = entry or {}

            title = self._build_title(self.entry)
            metadata = self._build_metadata(self.entry)
            if metadata:
                # Two-line title row: main title on the first line,
                # timestamp + option as small secondary text below.
                self.preview_button.setText(f"{title}\n{metadata}")
            else:
                self.preview_button.setText(title)

            conversation_text = self._format_conversation(self.entry.get('conversation', []))
            self.conversation_text.setPlainText(conversation_text)

            show_conversation = bool(conversation_text)
            self.conversation_label.setVisible(show_conversation)
            self.conversation_text.setVisible(show_conversation)
        except Exception as e:
            logging.error(f'HistoryEntryWidget.set_entry failed: {e}', exc_info=True)

    def retranslate_ui(self):
        self.set_entry(self.entry)


class HistoryWindow(QtWidgets.QWidget):
    """
    Standalone window for browsing the latest history entries.

    Renders a scrollable list of conversation titles. Clicking a title
    expands the full conversation in place. Only one entry can be expanded
    at a time (accordion).
    """

    def __init__(self):
        super().__init__()
        self.history_entries = []
        self.title_label = None
        self.subtitle_label = None
        self.empty_label = None
        self.scroll_area = None
        self.scroll_content = None
        self.entries_layout = None
        self.entry_widgets = []
        # Persist size/position between openings so the window reliably
        # re-appears where the user last left it (and not off-screen on
        # multi-monitor setups).
        self._settings = QSettings('WritingTools', 'HistoryWindow')
        self._build_ui()
        self._restore_geometry()
        # When the window closes, snapshot the current geometry for next time.
        self.destroyed.connect(self._save_geometry_on_destroy)

    # --- Geometry persistence -------------------------------------------------

    def _restore_geometry(self):
        try:
            size = self._settings.value('size')
            if size is not None:
                self.resize(size)
            pos = self._settings.value('pos')
            if pos is not None:
                self.move(pos)
        except Exception as e:
            logging.warning(f'Failed to restore HistoryWindow geometry: {e}')

    def _save_geometry(self):
        try:
            self._settings.setValue('size', self.size())
            self._settings.setValue('pos', self.pos())
        except Exception as e:
            logging.warning(f'Failed to save HistoryWindow geometry: {e}')

    def _save_geometry_on_destroy(self, *_args):
        self._save_geometry()

    def closeEvent(self, event):
        self._save_geometry()
        super().closeEvent(event)

    # --- UI construction ------------------------------------------------------

    def _build_ui(self):
        try:
            self.setWindowTitle(_("History"))
            self.setWindowFlag(QtCore.Qt.WindowType.Window, True)
            self.resize(820, 680)

            UIUtils.setup_window_and_layout(self)

            content_layout = QtWidgets.QVBoxLayout(self.background)
            content_layout.setContentsMargins(20, 20, 20, 20)
            content_layout.setSpacing(10)

            self.title_label = QtWidgets.QLabel(_("History"))
            self.title_label.setStyleSheet(
                f"font-size: 24px; font-weight: bold; color: {'#ffffff' if colorMode == 'dark' else '#222222'};"
            )
            content_layout.addWidget(self.title_label)

            self.subtitle_label = QtWidgets.QLabel(
                _("Click a title to expand the full conversation. Only one entry is open at a time.")
            )
            self.subtitle_label.setStyleSheet(
                f"font-size: 13px; color: {'#c0c0c0' if colorMode == 'dark' else '#555555'};"
            )
            self.subtitle_label.setWordWrap(True)
            content_layout.addWidget(self.subtitle_label)

            self.empty_label = QtWidgets.QLabel(_("No history yet."))
            self.empty_label.setStyleSheet(
                f"font-size: 14px; color: {'#d0d0d0' if colorMode == 'dark' else '#666666'};"
            )
            self.empty_label.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
            content_layout.addWidget(self.empty_label)

            self.scroll_area = QtWidgets.QScrollArea()
            self.scroll_area.setWidgetResizable(True)
            self.scroll_area.setFrameShape(QtWidgets.QFrame.Shape.NoFrame)
            self.scroll_area.setStyleSheet("QScrollArea { background: transparent; }")

            self.scroll_content = QtWidgets.QWidget()
            self.entries_layout = QtWidgets.QVBoxLayout(self.scroll_content)
            self.entries_layout.setContentsMargins(0, 0, 0, 0)
            self.entries_layout.setSpacing(8)
            self.entries_layout.addStretch()

            self.scroll_area.setWidget(self.scroll_content)
            content_layout.addWidget(self.scroll_area, 1)

            self._render_entries()
        except Exception as e:
            logging.error(f'HistoryWindow._build_ui failed: {e}', exc_info=True)
            raise

    # --- Data -----------------------------------------------------------------

    def set_history_entries(self, entries):
        self.history_entries = entries or []
        self._render_entries()

    def _render_entries(self):
        # Wipe any existing entry widgets.
        try:
            UIUtils.clear_layout(self.entries_layout)
        except Exception as e:
            logging.error(f'Failed to clear entries layout: {e}', exc_info=True)
        self.entry_widgets = []

        if not self.history_entries:
            self.empty_label.setVisible(True)
            # Re-add the trailing stretch that clear_layout removed.
            self.entries_layout.addStretch()
            return

        self.empty_label.setVisible(False)

        for entry in self.history_entries:
            entry_widget = HistoryEntryWidget(entry)
            # Wire the accordion: when this entry expands, collapse all
            # sibling entries that are currently expanded.
            entry_widget.on_expanded_changed = self._on_entry_expanded_changed
            self.entry_widgets.append(entry_widget)
            self.entries_layout.addWidget(entry_widget)

        self.entries_layout.addStretch()

    def _on_entry_expanded_changed(self, expanded_widget, expanded):
        """
        Accordion behavior: if `expanded_widget` just expanded, collapse any
        other entry that is currently expanded so only one is open at a time.
        """
        if not expanded:
            return
        for entry_widget in self.entry_widgets:
            if entry_widget is expanded_widget:
                continue
            if entry_widget.preview_button.isChecked():
                # Block signals so we don't recursively re-enter this handler.
                entry_widget.preview_button.blockSignals(True)
                try:
                    entry_widget.preview_button.setChecked(False)
                finally:
                    entry_widget.preview_button.blockSignals(False)
                # Manually update the arrow + details visibility, since
                # blocking signals suppresses the toggled() slot.
                entry_widget._toggle_expanded(False)

    def retranslate_ui(self):
        self.setWindowTitle(_("History"))
        self.title_label.setText(_("History"))
        self.subtitle_label.setText(
            _("Click a title to expand the full conversation. Only one entry is open at a time.")
        )
        self.empty_label.setText(_("No history yet."))

        for entry_widget in self.entry_widgets:
            entry_widget.retranslate_ui()


# --- Helpers used by HistoryManager.show_window ------------------------------

def position_window_on_active_screen(window):
    """
    Move `window` so it is fully visible on the screen containing the cursor.

    Falls back to the primary screen if the cursor's screen can't be
    determined. Used by HistoryManager.show_window to make sure the history
    window never opens off-screen.
    """
    try:
        cursor_pos = QCursor.pos()
        screen = QGuiApplication.screenAt(cursor_pos)
        if screen is None:
            screen = QGuiApplication.primaryScreen()
        if screen is None:
            return

        screen_geometry = screen.availableGeometry()
        window_size = window.sizeHint()
        # Use the current window size if sizeHint collapsed to (0, 0)
        # (which can happen for a freshly-constructed widget).
        if window_size.width() <= 0 or window_size.height() <= 0:
            window_size = window.size()

        # Default: center on the active screen.
        x = screen_geometry.x() + (screen_geometry.width() - window_size.width()) // 2
        y = screen_geometry.y() + (screen_geometry.height() - window_size.height()) // 4

        # Clamp to screen bounds (just in case the window is larger than the
        # screen or the centered position overshoots).
        x = max(screen_geometry.x(), min(x, screen_geometry.right() - window_size.width() + 1))
        y = max(screen_geometry.y(), min(y, screen_geometry.bottom() - window_size.height() + 1))

        window.move(x, y)
    except Exception as e:
        logging.warning(f'position_window_on_active_screen failed: {e}', exc_info=True)