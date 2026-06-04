import json
import logging
import os
import threading
import uuid
from datetime import datetime

from PySide6 import QtCore

import ui.HistoryWindow


class HistoryManager:
    """
    Handles history persistence, in-memory history state, and history window refresh.
    """

    def __init__(self, base_dir, on_updated=None):
        self.history_entries = []
        self.history_path = os.path.join(base_dir, 'history.json')
        self._history_lock = threading.Lock()
        self._pending_inline_history = None
        self._on_updated = on_updated
        self.history_window = None
        self.load_history()

    def set_translation_function(self, translate_func):
        ui.HistoryWindow._ = translate_func

    def _emit_updated(self):
        if callable(self._on_updated):
            try:
                self._on_updated()
            except Exception as e:
                logging.error(f'Failed to emit history update callback: {e}')

    def load_history(self):
        """
        Load history entries from history.json and keep only the latest 50.
        """
        logging.debug(f'Loading history from {self.history_path}')

        if not os.path.exists(self.history_path):
            self.history_entries = []
            self._save_history_entries()
            return

        try:
            with open(self.history_path, 'r') as f:
                data = json.load(f)
        except Exception as e:
            logging.error(f'Failed to load history: {e}')
            self.history_entries = []
            return

        if not isinstance(data, list):
            logging.warning('history.json is not a list. Resetting history.')
            self.history_entries = []
            self._save_history_entries()
            return

        normalized_entries = []
        for raw_entry in data:
            normalized = self._normalize_history_entry(raw_entry)
            if normalized is not None:
                normalized_entries.append(normalized)

        with self._history_lock:
            self.history_entries = normalized_entries[:50]

        self._save_history_entries()

    @staticmethod
    def _history_timestamp():
        """
        Build a human-readable local timestamp for history rows.
        """
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    @staticmethod
    def _sync_history_entry_fields(entry):
        """
        Keep input/output fields consistent with the conversation payload.
        """
        conversation = entry.get('conversation')
        if not isinstance(conversation, list):
            conversation = []

        cleaned_conversation = []
        for turn in conversation:
            if not isinstance(turn, dict):
                continue
            role = 'assistant' if turn.get('role') == 'assistant' else 'user'
            content = str(turn.get('content') or '')
            if content.strip():
                cleaned_conversation.append({'role': role, 'content': content})

        if not cleaned_conversation:
            input_text = str(entry.get('input') or '')
            output_text = str(entry.get('output') or '')
            if input_text:
                cleaned_conversation.append({'role': 'user', 'content': input_text})
            if output_text:
                cleaned_conversation.append({'role': 'assistant', 'content': output_text})

        input_text = str(entry.get('input') or '')
        if not input_text:
            for turn in cleaned_conversation:
                if turn['role'] == 'user':
                    input_text = turn['content']
                    break

        output_text = str(entry.get('output') or '')
        for turn in reversed(cleaned_conversation):
            if turn['role'] == 'assistant':
                output_text = turn['content']
                break

        entry['input'] = input_text
        entry['output'] = output_text
        entry['conversation'] = cleaned_conversation

    def _normalize_history_entry(self, entry):
        """
        Normalize a raw entry loaded from disk into the expected shape.
        """
        if not isinstance(entry, dict):
            return None

        normalized = {
            'id': str(entry.get('id') or uuid.uuid4()),
            'timestamp': str(entry.get('timestamp') or self._history_timestamp()),
            'option': str(entry.get('option') or ''),
            'input': str(entry.get('input') or ''),
            'output': str(entry.get('output') or ''),
            'conversation': entry.get('conversation') if isinstance(entry.get('conversation'), list) else []
        }
        self._sync_history_entry_fields(normalized)
        return normalized

    def _save_history_entries(self):
        """
        Persist the in-memory history list to history.json.
        """
        with self._history_lock:
            self.history_entries = self.history_entries[:50]
            history_copy = []
            for entry in self.history_entries:
                copied_entry = {
                    'id': str(entry.get('id') or ''),
                    'timestamp': str(entry.get('timestamp') or ''),
                    'option': str(entry.get('option') or ''),
                    'input': str(entry.get('input') or ''),
                    'output': str(entry.get('output') or ''),
                    'conversation': []
                }
                raw_conversation = entry.get('conversation', [])
                if isinstance(raw_conversation, list):
                    for turn in raw_conversation:
                        if not isinstance(turn, dict):
                            continue
                        role = 'assistant' if turn.get('role') == 'assistant' else 'user'
                        content = str(turn.get('content') or '')
                        if content.strip():
                            copied_entry['conversation'].append({'role': role, 'content': content})
                history_copy.append(copied_entry)

        try:
            with open(self.history_path, 'w') as f:
                json.dump(history_copy, f, indent=2)
        except Exception as e:
            logging.error(f'Failed to save history: {e}')

    def snapshot(self):
        """
        Return a copy for UI rendering without lock contention.
        """
        with self._history_lock:
            snapshot = []
            for entry in self.history_entries:
                copied = {
                    'id': str(entry.get('id') or ''),
                    'timestamp': str(entry.get('timestamp') or ''),
                    'option': str(entry.get('option') or ''),
                    'input': str(entry.get('input') or ''),
                    'output': str(entry.get('output') or ''),
                    'conversation': []
                }
                raw_conversation = entry.get('conversation', [])
                if isinstance(raw_conversation, list):
                    for turn in raw_conversation:
                        if not isinstance(turn, dict):
                            continue
                        copied['conversation'].append({
                            'role': 'assistant' if turn.get('role') == 'assistant' else 'user',
                            'content': str(turn.get('content') or '')
                        })
                snapshot.append(copied)
            return snapshot

    def record_entry(self, option, input_text, output_text, conversation=None, entry_id=None):
        """
        Insert a new history row at the top or update an existing row.
        """
        with self._history_lock:
            target_entry = None
            if entry_id:
                for existing_entry in self.history_entries:
                    if existing_entry.get('id') == entry_id:
                        target_entry = existing_entry
                        break

            if target_entry is None:
                target_entry = {
                    'id': str(entry_id or uuid.uuid4()),
                    'timestamp': self._history_timestamp(),
                    'option': str(option or ''),
                    'input': str(input_text or ''),
                    'output': str(output_text or ''),
                    'conversation': []
                }
                self.history_entries.insert(0, target_entry)
            else:
                if option is not None:
                    target_entry['option'] = str(option)
                if input_text is not None:
                    target_entry['input'] = str(input_text)
                if output_text is not None:
                    target_entry['output'] = str(output_text)

            if conversation is not None:
                cleaned_conversation = []
                for turn in conversation:
                    if not isinstance(turn, dict):
                        continue
                    role = 'assistant' if turn.get('role') == 'assistant' else 'user'
                    content = str(turn.get('content') or '')
                    if content.strip():
                        cleaned_conversation.append({'role': role, 'content': content})
                target_entry['conversation'] = cleaned_conversation

            self._sync_history_entry_fields(target_entry)
            self.history_entries = self.history_entries[:50]
            resolved_id = target_entry['id']

        self._save_history_entries()
        self._emit_updated()
        return resolved_id

    def append_turn(self, entry_id, role, content):
        """
        Append a single user/assistant turn to an existing history row.
        """
        content = str(content or '')
        if not entry_id or not content.strip():
            return

        with self._history_lock:
            target_entry = None
            for existing_entry in self.history_entries:
                if existing_entry.get('id') == entry_id:
                    target_entry = existing_entry
                    break

            if target_entry is None:
                return

            conversation = target_entry.get('conversation')
            if not isinstance(conversation, list):
                conversation = []

            conversation.append({
                'role': 'assistant' if role == 'assistant' else 'user',
                'content': content
            })
            target_entry['conversation'] = conversation
            self._sync_history_entry_fields(target_entry)

        self._save_history_entries()
        self._emit_updated()

    def set_pending_inline_history(self, option, input_text):
        """
        Cache inline request metadata until replacement output arrives.
        """
        with self._history_lock:
            self._pending_inline_history = {
                'option': str(option or ''),
                'input': str(input_text or '')
            }

    def clear_pending_inline_history(self):
        """
        Drop any stale inline history metadata.
        """
        with self._history_lock:
            self._pending_inline_history = None

    def consume_pending_inline_history(self, output_text):
        """
        Finalize an inline history entry once we have output text.
        """
        cleaned_output = str(output_text or '').rstrip('\n')
        if not cleaned_output.strip():
            self.clear_pending_inline_history()
            return

        with self._history_lock:
            pending = self._pending_inline_history
            self._pending_inline_history = None

        if not pending:
            return

        input_text = pending.get('input', '')
        self.record_entry(
            option=pending.get('option', ''),
            input_text=input_text,
            output_text=cleaned_output,
            conversation=[
                {'role': 'user', 'content': input_text},
                {'role': 'assistant', 'content': cleaned_output}
            ]
        )

    @staticmethod
    def attach_entry_to_response_window(response_window, entry_id):
        if response_window is not None:
            response_window.history_entry_id = entry_id

    def refresh_window(self):
        if self.history_window:
            self.history_window.set_history_entries(self.snapshot())

    def show_window(self, *_args):
        """
        Show (or focus) the history window.

        Defensive: any exception during construction or population is logged
        with a full traceback so silent failures (which previously made the
        window "never open") become visible in the application log.

        Positioning: the window is moved onto the screen containing the
        cursor before being shown, so it can't accidentally appear
        off-screen on multi-monitor setups.
        """
        logging.debug('Showing history window')
        try:
            if not self.history_window:
                self.history_window = ui.HistoryWindow.HistoryWindow()
            self.history_window.set_history_entries(self.snapshot())

            # Restore from minimized state if needed — `show()` alone won't
            # un-minimize a window on all platforms.
            if self.history_window.isMinimized():
                self.history_window.setWindowState(
                    self.history_window.windowState() & ~QtCore.Qt.WindowState.WindowMinimized
                )

            # Make sure the window lands on a visible screen. `restoreGeometry`
            # may have brought it back at an off-screen position if monitor
            # configuration changed between sessions.
            ui.HistoryWindow.position_window_on_active_screen(self.history_window)

            self.history_window.show()
            self.history_window.raise_()
            self.history_window.activateWindow()
            logging.debug('History window shown')
        except Exception as e:
            logging.error(f'Failed to show history window: {e}', exc_info=True)
