"""Exercise the real Qt chat caller with scripted models and an MCP HTTP fixture.

Run from Windows_and_Linux:
QT_QPA_PLATFORM=offscreen PYNPUT_BACKEND=dummy python -m unittest discover -s tests -v
No live model credentials or network access are used by these tests.
"""

import asyncio
import copy
import json
import os
import threading
import time
import unittest
from unittest.mock import Mock, patch

import httpx
from PySide6 import QtCore, QtWidgets

from aiprovider import GeminiProvider, OllamaProvider, OpenAICompatibleProvider
from ui.ResponseWindow import MarkdownTextBrowser, ResponseWindow
from WritingToolApp import WritingToolApp
import web_search


SOURCES = "Example source\nhttps://example.com/source\nA useful current factual excerpt."
ANSWER = "A sourced answer: [Example source](https://example.com/source)."
REAL_ASYNC_CLIENT = httpx.AsyncClient


class ChatHarness(QtCore.QObject):
    show_message_signal = QtCore.Signal(str, str)

    def __init__(self):
        super().__init__()
        self.config = {"provider": "Saved local provider", "providers": {"saved": {"api_key": "saved-key"}}}
        self.current_provider = self.scripted_provider(OpenAICompatibleProvider)
        self.threads = []

    @staticmethod
    def scripted_provider(provider_class):
        provider = object.__new__(provider_class)
        provider.get_response = Mock(return_value=ANSWER)
        return provider

    def process_followup_question(self, window, question):
        self.threads.append(WritingToolApp.process_followup_question(self, window, question))

    def save_config(self, config):
        pass


class ChatSearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qt = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])

    def setUp(self):
        self.harness = ChatHarness()
        self.windows = []
        self.requests = []
        self.mode = "normal"
        self.started = threading.Event()
        self.install_client = patch(
            "web_search.httpx.AsyncClient",
            side_effect=lambda **kw: REAL_ASYNC_CLIENT(transport=httpx.MockTransport(self.respond), **kw),
        )
        self.install_client.start()
        self.ambient = patch.dict(os.environ, {"PARALLEL_API_KEY": "unused-ambient-key"})
        self.ambient.start()

    async def respond(self, request):
        payload = json.loads(request.content)
        self.requests.append((request, payload))
        if "id" not in payload:
            return httpx.Response(202)
        method = payload["method"]
        if method == "initialize":
            result = {
                "protocolVersion": payload["params"]["protocolVersion"],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fixture", "version": "1"},
            }
        elif method == "tools/list":
            names = [] if self.mode == "missing" else ["web_search", "web_fetch"]
            result = {"tools": [{"name": name, "inputSchema": {"type": "object"}} for name in names]}
        elif method == "tools/call":
            self.started.set()
            if self.mode == "timeout":
                raise httpx.ReadTimeout("fixture timeout", request=request)
            if self.mode == "http_error":
                return httpx.Response(503)
            if self.mode == "slow":
                await asyncio.sleep(10)
            result = {
                "content": [] if self.mode == "empty" else [{
                    "type": "text",
                    "text": "Free anonymous tier quota exhausted" if self.mode == "quota" else SOURCES,
                }],
                "isError": self.mode in ("error", "quota"),
            }
        else:
            raise AssertionError(method)
        return httpx.Response(200, json={"jsonrpc": "2.0", "id": payload["id"], "result": result})

    def tearDown(self):
        for window in self.windows:
            window.close()
        for thread in self.harness.threads:
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive(), "lookup worker did not stop")
        for window in self.windows:
            window.deleteLater()
        self.qt.sendPostedEvents(None, QtCore.QEvent.Type.DeferredDelete)
        self.qt.processEvents()
        self.install_client.stop()
        self.ambient.stop()

    def window(self):
        window = ResponseWindow(self.harness)
        window.chat_history = [
            {"role": "user", "content": "PRIVATE SELECTED TEXT"},
            {"role": "assistant", "content": "Previous summary"},
        ]
        self.windows.append(window)
        return window

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while not predicate() and time.monotonic() < deadline:
            self.qt.processEvents()
            time.sleep(0.005)
        self.qt.processEvents()
        self.assertTrue(predicate(), "chat worker did not finish")

    def send(self, window, question, enabled=True, wait=True):
        window.search_checkbox.setChecked(enabled)
        window.input_field.setText(question)
        window.send_message()
        if wait:
            self.wait_for(window.input_field.isEnabled)

    def calls(self):
        return [p["params"] for _, p in self.requests if p["method"] == "tools/call"]

    def visible_text(self, window):
        return "\n".join(item.toPlainText() for item in window.findChildren(MarkdownTextBrowser))

    def test_fresh_window_search_is_disabled_and_saved_settings_survive(self):
        window = self.window()
        saved = copy.deepcopy(self.harness.config)
        self.assertFalse(window.search_checkbox.isChecked())
        self.send(window, "Ordinary question", enabled=False)
        self.assertEqual(self.requests, [])
        self.assertEqual(self.harness.config, saved)
        messages = self.harness.current_provider.get_response.call_args.args[1]
        self.assertEqual(sum(m["content"] == "Ordinary question" for m in messages), 1)
        self.assertIn(ANSWER, window.chat_history[-1]["content"])

    def test_search_reaches_selected_model_and_display_without_leaking_history(self):
        window = self.window()
        self.send(window, "Current public question")
        call = self.calls()[0]
        self.assertEqual(call["name"], "web_search")
        self.assertEqual(call["arguments"]["objective"], "Current public question")
        self.assertNotIn("PRIVATE", json.dumps(self.calls()))
        for request, _ in self.requests:
            self.assertEqual(str(request.url), web_search.MCP_URL)
            self.assertEqual(request.headers["User-Agent"], web_search.USER_AGENT)
            self.assertNotIn("authorization", request.headers)
        system, messages = self.harness.current_provider.get_response.call_args.args
        self.assertIn("untrusted", system)
        self.assertIn(SOURCES, messages[-2]["content"])
        self.assertEqual(messages[-1]["content"], "Current public question")
        self.assertIn("Example source", self.visible_text(window))
        self.assertFalse(any(SOURCES in msg["content"] for msg in window.chat_history))

    def test_all_existing_provider_routes_consume_sources(self):
        for provider_class in (GeminiProvider, OllamaProvider, OpenAICompatibleProvider):
            with self.subTest(provider=provider_class.__name__):
                provider = self.harness.scripted_provider(provider_class)
                self.harness.current_provider = provider
                window = self.window()
                self.send(window, "Ground this question")
                provider.get_response.assert_called_once()
                self.assertIs(self.harness.current_provider, provider)
                args = provider.get_response.call_args
                self.assertTrue(args.kwargs["return_response"])
                self.assertIn(SOURCES, args.args[1][-2]["content"])
                self.assertIn(ANSWER, window.chat_history[-1]["content"])

    def test_search_fetch_followup_and_new_windows_own_their_session_ids(self):
        first = self.window()
        self.send(first, "First public search")
        self.send(first, "https://example.com/source")
        second = self.window()
        self.send(second, "Second conversation")
        self.send(first, "First conversation follow-up")
        calls = self.calls()
        ids = [c["arguments"]["session_id"] for c in calls]
        self.assertEqual(ids[0], ids[1])
        self.assertEqual(ids[0], ids[3])
        self.assertNotEqual(ids[0], ids[2])
        self.assertEqual(calls[1]["name"], "web_fetch")
        self.assertEqual(calls[1]["arguments"]["urls"], ["https://example.com/source"])
        first.close()
        fresh = self.window()
        self.assertNotEqual(fresh.web_search.session_id, ids[0])
        self.assertFalse(fresh.search_checkbox.isChecked())

    def test_interleaved_windows_do_not_exchange_responses_or_ids(self):
        first, second = self.window(), self.window()
        self.send(first, "One", wait=False)
        self.send(second, "Two", wait=False)
        self.wait_for(lambda: first.input_field.isEnabled() and second.input_field.isEnabled())
        self.assertEqual(len(self.calls()), 2)
        ids = {c["arguments"]["session_id"] for c in self.calls()}
        self.assertEqual(ids, {first.web_search.session_id, second.web_search.session_id})
        for window in (first, second):
            self.assertEqual(sum(m["content"] == ANSWER for m in window.chat_history), 1)

    def test_failed_lookup_does_not_generate_an_ungrounded_answer(self):
        window = self.window()
        original_id = window.web_search.session_id
        for mode in ("error", "quota", "empty", "missing", "timeout", "http_error"):
            with self.subTest(mode=mode):
                self.mode = mode
                self.send(window, "Question to retry")
                self.harness.current_provider.get_response.assert_not_called()
                self.assertNotEqual(window.chat_history[-1]["content"], ANSWER)
                self.assertEqual(window.web_search.session_id, original_id)
        self.mode = "normal"
        self.send(window, "Question to retry")
        self.assertEqual(self.calls()[-1]["arguments"]["session_id"], original_id)

    def test_total_deadline_and_close_cancel_the_actual_lookup(self):
        window = self.window()
        self.mode = "slow"
        with patch("web_search.LOOKUP_TIMEOUT", 0.05):
            self.send(window, "Slow question")
        self.assertIn("timed out", self.visible_text(window))
        self.harness.current_provider.get_response.assert_not_called()
        self.started.clear()
        self.send(window, "Close this question", wait=False)
        self.wait_for(self.started.is_set)
        window.close()
        self.wait_for(window.web_search.cancelled.is_set)
        self.harness.threads[-1].join(timeout=5)
        self.assertFalse(self.harness.threads[-1].is_alive())
        self.qt.processEvents()
        self.harness.current_provider.get_response.assert_not_called()
        self.assertEqual(window.chat_history, [])

    def test_invalid_url_does_not_reach_the_network(self):
        window = self.window()
        for value in ("file:///private/file", "https://user:password@example.com"):
            self.send(window, value)
        self.assertEqual(self.requests, [])
        self.harness.current_provider.get_response.assert_not_called()

    def test_disabling_search_after_use_prevents_further_lookup(self):
        window = self.window()
        self.send(window, "Public question")
        count = len(self.requests)
        self.send(window, "Private question", enabled=False)
        self.assertEqual(len(self.requests), count)
        self.assertEqual(self.harness.current_provider.get_response.call_count, 2)


if __name__ == "__main__":
    unittest.main()
