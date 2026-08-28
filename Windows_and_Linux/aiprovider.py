"""
AI Provider Architecture for Writing Tools
--------------------------------------------

This module handles different AI model providers (Gemini, Ollama Cloud, OpenAI-compatible, Ollama local) and manages their interactions
with the main application. It uses an abstract base class pattern for provider implementations.

Key Components:
1. AIProviderSetting – Base class for provider settings (e.g. API keys, model names)
    • TextSetting      – A simple text input for settings
    • DropdownSetting  – A dropdown selection setting

2. AIProvider – Abstract base class that all providers implement.
   It defines the interface for:
      • Getting a response from the AI model
      • Loading and saving configuration settings
      • Cancelling an ongoing request

3. Provider Implementations:
    • GeminiProvider        – Uses Google’s Generative AI API (Gemini) to generate content.
    • OllamaCloudProvider   – Connects to Ollama Cloud (https://ollama.com) using the ollama Python client
                              with a Bearer API key. Free tier available — recommended for most users.
    • OpenAICompatibleProvider – Connects to any OpenAI-compatible API (v1/chat/completions)
    • OllamaProvider        – Connects to a locally running Ollama server (e.g. for llama.cpp). For Experts.

Response Flow:
   • The main app calls get_response() with a system instruction and a prompt.
   • The provider formats and sends the request to its API endpoint.
   • For operations that require a window (e.g. Summary, Key Points), the provider returns the full text.
   • For direct text replacement, the provider emits the full text via the output_ready_signal.
   • Conversation history (for follow-up questions) is maintained by the main app.

Note: Streaming has been fully removed throughout the code.
"""

import base64
import logging
import webbrowser
from abc import ABC, abstractmethod
from typing import List

# External libraries
from google import genai
from google.genai import types as genai_types
from ollama import Client as OllamaClient
from openai import OpenAI
from PySide6 import QtWidgets
from PySide6.QtWidgets import QVBoxLayout
from ui.UIUtils import colorMode

# Obfuscation prefix to identify encrypted API keys
_OBFUSCATION_PREFIX = "enc:"
_XOR_KEY = 0x5A  # Simple XOR key for obfuscation


def obfuscate_api_key(key: str) -> str:
    """
    Obfuscate an API key using XOR + Base64 encoding.
    Returns the obfuscated string with 'enc:' prefix.
    """
    if not key or key.startswith(_OBFUSCATION_PREFIX):
        return key  # Already obfuscated or empty
    xored = bytes([b ^ _XOR_KEY for b in key.encode("utf-8")])
    return _OBFUSCATION_PREFIX + base64.b64encode(xored).decode("ascii")


def deobfuscate_api_key(obfuscated: str) -> str:
    """
    Deobfuscate an API key that was obfuscated with obfuscate_api_key().
    If the key doesn't have the 'enc:' prefix, returns it as-is (plaintext).
    """
    if not obfuscated or not obfuscated.startswith(_OBFUSCATION_PREFIX):
        return obfuscated  # Not obfuscated, return as-is
    encoded = obfuscated[len(_OBFUSCATION_PREFIX) :]
    xored = base64.b64decode(encoded)
    return bytes([b ^ _XOR_KEY for b in xored]).decode("utf-8")


class AIProviderSetting(ABC):
    """
    Abstract base class for a provider setting (e.g., API key, model selection).
    """

    def __init__(
        self,
        name: str,
        display_name: str = None,
        default_value: str = None,
        description: str = None,
    ):
        self.name = name
        self.display_name = display_name if display_name else name
        self.default_value = default_value if default_value else ""
        self.description = description if description else ""

    @abstractmethod
    def render_to_layout(self, layout: QVBoxLayout):
        """Render the setting widget(s) into the provided layout."""
        pass

    @abstractmethod
    def set_value(self, value):
        """Set the internal value from configuration."""
        pass

    @abstractmethod
    def get_value(self):
        """Return the current value from the widget."""
        pass


class TextSetting(AIProviderSetting):
    """
    A text-based setting (for API keys, URLs, etc.).
    """

    def __init__(
        self,
        name: str,
        display_name: str = None,
        default_value: str = None,
        description: str = None,
    ):
        super().__init__(name, display_name, default_value, description)
        self.internal_value = default_value
        self.input = None

    def render_to_layout(self, layout: QVBoxLayout):
        row_layout = QtWidgets.QHBoxLayout()
        label = QtWidgets.QLabel(self.display_name)
        label.setStyleSheet(
            f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};"
        )
        row_layout.addWidget(label)
        self.input = QtWidgets.QLineEdit(self.internal_value)
        self.input.setStyleSheet(f"""
            font-size: 16px;
            padding: 5px;
            background-color: {"#444" if colorMode == "dark" else "white"};
            color: {"#ffffff" if colorMode == "dark" else "#000000"};
            border: 1px solid {"#666" if colorMode == "dark" else "#ccc"};
        """)
        self.input.setPlaceholderText(self.description)
        row_layout.addWidget(self.input)
        layout.addLayout(row_layout)

    def set_value(self, value):
        self.internal_value = value

    def get_value(self):
        return self.input.text()


class DropdownSetting(AIProviderSetting):
    """
    A dropdown setting (e.g., for selecting a model).

    Optionally supports a "Custom" option that reveals a text input for arbitrary values.
    When allow_custom=True, users can select "Custom" from the dropdown and enter any value.
    If the loaded config value doesn't match any preset option, "Custom" is auto-selected.
    """

    # Sentinel value used internally to identify the "Custom" dropdown option
    _CUSTOM_SENTINEL = "__custom__"

    def __init__(
        self,
        name: str,
        display_name: str = None,
        default_value: str = None,
        description: str = None,
        options: list = None,
        allow_custom: bool = False,
        custom_placeholder: str = "Enter custom value",
    ):
        super().__init__(name, display_name, default_value, description)
        self.options = options if options else []
        self.internal_value = default_value
        self.dropdown = None
        self.allow_custom = allow_custom
        self.custom_placeholder = custom_placeholder
        self.custom_input = None
        self.custom_input_container = None

    def render_to_layout(self, layout: QVBoxLayout):
        row_layout = QtWidgets.QHBoxLayout()
        label = QtWidgets.QLabel(self.display_name)
        label.setStyleSheet(
            f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};"
        )
        row_layout.addWidget(label)
        self.dropdown = QtWidgets.QComboBox()
        self.dropdown.setStyleSheet(f"""
            font-size: 16px;
            padding: 5px;
            background-color: {"#444" if colorMode == "dark" else "white"};
            color: {"#ffffff" if colorMode == "dark" else "#000000"};
            border: 1px solid {"#666" if colorMode == "dark" else "#ccc"};
        """)

        # Add preset options
        for option, value in self.options:
            self.dropdown.addItem(option, value)

        # Add "Custom" option if enabled
        if self.allow_custom:
            self.dropdown.addItem("🔧 Custom", self._CUSTOM_SENTINEL)

        # Set initial selection based on internal_value
        index = self.dropdown.findData(self.internal_value)
        if index != -1:
            # Value matches a preset option
            self.dropdown.setCurrentIndex(index)
        elif self.allow_custom and self.internal_value:
            # Value doesn't match any preset - it's a custom value, select "Custom"
            custom_index = self.dropdown.findData(self._CUSTOM_SENTINEL)
            if custom_index != -1:
                self.dropdown.setCurrentIndex(custom_index)

        row_layout.addWidget(self.dropdown)
        layout.addLayout(row_layout)

        # Create custom input row if allow_custom is enabled
        if self.allow_custom:
            self.custom_input_container = QtWidgets.QWidget()
            custom_row_layout = QtWidgets.QHBoxLayout(self.custom_input_container)
            custom_row_layout.setContentsMargins(0, 5, 0, 0)

            self.custom_input = QtWidgets.QLineEdit()
            self.custom_input.setPlaceholderText(self.custom_placeholder)
            self.custom_input.setStyleSheet(f"""
                font-size: 16px;
                padding: 5px;
                background-color: {"#444" if colorMode == "dark" else "white"};
                color: {"#ffffff" if colorMode == "dark" else "#000000"};
                border: 1px solid {"#666" if colorMode == "dark" else "#ccc"};
            """)

            # If current value is custom (not in presets), populate the input
            if (
                self.dropdown.currentData() == self._CUSTOM_SENTINEL
                and self.internal_value
            ):
                self.custom_input.setText(self.internal_value)

            custom_row_layout.addWidget(self.custom_input)
            layout.addWidget(self.custom_input_container)

            # Connect signal to show/hide custom input when dropdown changes
            self.dropdown.currentIndexChanged.connect(self._on_dropdown_changed)
            # Set initial visibility
            self._update_custom_input_visibility()

    def _on_dropdown_changed(self):
        """Handle dropdown selection change to show/hide custom input."""
        self._update_custom_input_visibility()

    def _update_custom_input_visibility(self):
        """Show or hide the custom input based on dropdown selection."""
        if self.custom_input_container:
            is_custom = self.dropdown.currentData() == self._CUSTOM_SENTINEL
            self.custom_input_container.setVisible(is_custom)
            # Focus the input when switching to Custom for better UX
            if is_custom and self.custom_input:
                self.custom_input.setFocus()

    def set_value(self, value):
        self.internal_value = value

    def get_value(self):
        # If "Custom" is selected, return the text input value (stripped of whitespace)
        if self.allow_custom and self.dropdown.currentData() == self._CUSTOM_SENTINEL:
            return self.custom_input.text().strip()
        return self.dropdown.currentData()


class AIProvider(ABC):
    """
    Abstract base class for AI providers.

    All providers must implement:
      • get_response(system_instruction, prompt) -> str
      • after_load() to create their client or model instance
      • before_load() to cleanup any existing client
      • cancel() to cancel an ongoing request
    """

    def __init__(
        self,
        app,
        provider_name: str,
        settings: List[AIProviderSetting],
        description: str = "An unfinished AI provider!",
        logo: str = "generic",
        button_text: str = "Go to URL",
        button_action: callable = None,
        secondary_button_text: str = None,
        secondary_button_action: callable = None,
    ):
        self.provider_name = provider_name
        self.settings = settings
        self.app = app
        self.description = description if description else "An unfinished AI provider!"
        self.logo = logo
        self.button_text = button_text
        self.button_action = button_action
        # Optional second button next to the primary one (used by Ollama Cloud
        # for "Get Free API Key" + "Open API Key Dashboard", and kept generic
        # for any future provider that needs a pair of CTAs). Both must be
        # provided for the button to render; if either is None we fall back to
        # the original single-button layout for backward compatibility.
        self.secondary_button_text = secondary_button_text
        self.secondary_button_action = secondary_button_action

    @abstractmethod
    def get_response(self, system_instruction: str, prompt: str) -> str:
        """
        Send the given system instruction and prompt to the AI provider and return the full response text.
        """
        pass

    def load_config(self, config: dict):
        """
        Load configuration settings into the provider.
        """
        for setting in self.settings:
            if setting.name in config:
                setattr(self, setting.name, config[setting.name])
                setting.set_value(config[setting.name])
            else:
                setattr(self, setting.name, setting.default_value)
        self.after_load()

    def save_config(self):
        """
        Save provider configuration settings into the main config file.
        """
        config = {}
        for setting in self.settings:
            config[setting.name] = setting.get_value()
        self.app.config["providers"][self.provider_name] = config
        self.app.save_config(self.app.config)

    @abstractmethod
    def after_load(self):
        """
        Called after configuration is loaded; create your API client here.
        """
        pass

    @abstractmethod
    def before_load(self):
        """
        Called before reloading configuration; cleanup your API client here.
        """
        pass

    @abstractmethod
    def cancel(self):
        """
        Cancel any ongoing API request.
        """
        pass


class GeminiProvider(AIProvider):
    """
    Provider for Google's Gemini API (using the new unified `google-genai` SDK).

    Uses `client.models.generate_content()` for single-shot generation. The same
    method is used for follow-up chat too — the entire conversation history is
    passed via `contents` as a list of `Content` objects, so we don't need the
    SDK's chat session abstraction.

    System instruction is passed via `GenerateContentConfig.system_instruction`
    (not concatenated into `contents`, as the legacy SDK required).

    Thinking is disabled (set to "minimal", the lowest level the API exposes)
    on Gemini 3-family models. Gemma models don't have a thinking process, so
    `thinking_config` is omitted for them — passing it could otherwise error.
    """

    # Disable safety filtering across all categories (best-effort; some models
    # may still soft-refuse). Defined once, reused per request.
    _SAFETY_SETTINGS = [
        genai_types.SafetySetting(
            category="HARM_CATEGORY_HARASSMENT", threshold="BLOCK_NONE"
        ),
        genai_types.SafetySetting(
            category="HARM_CATEGORY_HATE_SPEECH", threshold="BLOCK_NONE"
        ),
        genai_types.SafetySetting(
            category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="BLOCK_NONE"
        ),
        genai_types.SafetySetting(
            category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="BLOCK_NONE"
        ),
    ]

    def __init__(self, app):
        self.close_requested = False
        self.client = None

        settings = [
            TextSetting(
                name="api_key",
                display_name="API Key",
                description="Paste your Gemini API key here",
            ),
            DropdownSetting(
                name="model_name",
                display_name="Model",
                default_value="gemini-flash-latest",
                description="Select Gemini model to use",
                options=[
                    # `gemini-flash-latest` is a Google-managed alias that currently
                    # points to Gemini 3 Flash Preview — fast (~1–2s) and high
                    # quality. Capped at 20 free requests/day per the model's free
                    # tier.
                    (
                        "⭐ Gemini Flash Latest (very fast | only 20 free uses/day)",
                        "gemini-flash-latest",
                    ),
                    # Gemma 4 models are unlimited on the free tier but noticeably
                    # slower (8–15s typical) since they run on different
                    # infrastructure.
                    ("Gemma 4 31B (slow | unlimited free use)", "gemma-4-31b-it"),
                    (
                        "Gemma 4 26B A4B (slow | unlimited free use)",
                        "gemma-4-26b-a4b-it",
                    ),
                ],
                allow_custom=True,
                custom_placeholder="e.g., gemini-3.1-pro-preview",
            ),
        ]
        super().__init__(
            app,
            "Gemini (Recommended)",
            settings,
            "• Google's Gemini is a powerful AI model available for free!\n"
            "• An API key is required to connect to Gemini on your behalf.\n"
            "• Click the button below to get your API key.",
            "gemini",
            "Get API Key",
            lambda: webbrowser.open("https://aistudio.google.com/app/apikey"),
        )

    def _build_config(
        self, system_instruction: str
    ) -> "genai_types.GenerateContentConfig":
        """
        Build a per-call GenerateContentConfig.

        We don't override temperature: Gemini 3 docs explicitly recommend leaving
        it at the default of 1.0 (lower values can cause looping / degraded
        output on reasoning-heavy tasks). The old SDK code set it to 0.5; we drop
        that override here.
        """
        # Thinking is disabled across the board for Writing Tools (latency matters
        # more than reasoning depth for proofread/rewrite/summary flows).
        #
        # • Gemma 4 *is* capable of thinking, but is off by default. Per
        #   https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api#thinking,
        #   thinking on Gemma 4 is binary and "you enable it in the API by setting
        #   the thinking level to 'high'". So omitting thinking_config keeps
        #   Gemma 4 in its default-off state.
        # • Gemini 3 Flash / Flash-Lite cannot fully disable thinking. The
        #   lowest exposed level is "minimal", which the docs say "matches the
        #   'no thinking' setting for most queries".
        is_gemma = "gemma" in (self.model_name or "").lower()
        kwargs = {
            "system_instruction": system_instruction,
            "safety_settings": self._SAFETY_SETTINGS,
            "max_output_tokens": 1000,
        }
        if not is_gemma:
            kwargs["thinking_config"] = genai_types.ThinkingConfig(
                thinking_level="minimal"
            )
        return genai_types.GenerateContentConfig(**kwargs)

    @staticmethod
    def _messages_to_contents(messages: list) -> list:
        """
        Convert OpenAI-style chat history into google-genai `Content` objects.

        Maps roles: assistant → "model", everything else → "user". Any "system"
        entries are dropped because Gemini takes the system instruction via the
        config object instead of as an in-history message.
        """
        contents = []
        for m in messages:
            role = m.get("role")
            if role == "system":
                continue
            text = m.get("content", "")
            gemini_role = "model" if role == "assistant" else "user"
            contents.append(
                genai_types.Content(
                    role=gemini_role, parts=[genai_types.Part(text=text)]
                )
            )
        return contents

    def get_response(
        self, system_instruction: str, prompt, return_response: bool = False
    ) -> str:
        """
        Generate content using Gemini.

        `prompt` may be either a plain string (the typical inline-tool flow) or a
        list of OpenAI-style message dicts (the follow-up chat flow). In both
        cases we make a single-shot non-streaming request.

        Returns the response text when `return_response` is True; otherwise emits
        it via `output_ready_signal` for inline replacement.
        """
        self.close_requested = False

        try:
            contents = (
                self._messages_to_contents(prompt)
                if isinstance(prompt, list)
                else prompt
            )

            response = self.client.models.generate_content(
                model=self.model_name,
                contents=contents,
                config=self._build_config(system_instruction),
            )

            response_text = (response.text or "").rstrip("\n")

            if not return_response and not hasattr(self.app, "current_response_window"):
                self.app.output_ready_signal.emit(response_text)
                self.app.replace_text(True)
                return ""
            return response_text
        except Exception as e:
            logging.error(f"Error processing Gemini response: {e}")
            self.app.output_ready_signal.emit(
                "An error occurred while processing the response."
            )
            return ""
        finally:
            self.close_requested = False

    def load_config(self, config: dict):
        """
        Load configuration, deobfuscating the API key if needed.
        """
        # Deobfuscate API key before loading
        if "api_key" in config:
            config = config.copy()  # Don't modify the original
            config["api_key"] = deobfuscate_api_key(config["api_key"])
        super().load_config(config)

    def save_config(self):
        """
        Save configuration, obfuscating the API key for storage.
        """
        config = {}
        for setting in self.settings:
            value = setting.get_value()
            # Obfuscate API key before saving
            if setting.name == "api_key":
                value = obfuscate_api_key(value)
            config[setting.name] = value
        self.app.config["providers"][self.provider_name] = config
        self.app.save_config(self.app.config)

    def after_load(self):
        """
        Construct the new `google-genai` Client. The model and per-call options
        are passed at request time via `client.models.generate_content`, so we
        don't pre-instantiate a model here.
        """
        self.client = genai.Client(api_key=self.api_key)

    def before_load(self):
        self.client = None

    def cancel(self):
        self.close_requested = True


class OpenAICompatibleProvider(AIProvider):
    """
    Provider for OpenAI-compatible APIs.

    Uses self.client.chat.completions.create() to obtain a response.
    Streaming is fully removed.
    """

    def __init__(self, app):
        self.close_requested = None
        self.client = None

        settings = [
            TextSetting(
                name="api_key",
                display_name="API Key",
                description="API key for the OpenAI-compatible API.",
            ),
            TextSetting(
                "api_base",
                "API Base URL",
                "https://api.openai.com/v1",
                "E.g. https://api.openai.com/v1",
            ),
            TextSetting(
                "api_organisation",
                "API Organisation",
                "",
                "Leave blank if not applicable.",
            ),
            TextSetting(
                "api_project", "API Project", "", "Leave blank if not applicable."
            ),
            TextSetting("api_model", "API Model", "gpt-4o-mini", "E.g. gpt-4o-mini"),
        ]
        super().__init__(
            app,
            "OpenAI Compatible (For Experts)",
            settings,
            "• Connect to ANY OpenAI-compatible API (v1/chat/completions).\n"
            "• You must abide by the service's Terms of Service.",
            "openai",
            "Get OpenAI API Key",
            lambda: webbrowser.open("https://platform.openai.com/account/api-keys"),
        )

    def get_response(
        self, system_instruction: str, prompt: str | list, return_response: bool = False
    ) -> str:
        """
        Send a chat request to the OpenAI-compatible API.

        Always performs a non-streaming request.
        If prompt is not a list, builds a simple two-message conversation.
        Returns the response text if return_response is True,
        otherwise emits it via output_ready_signal.
        """
        self.close_requested = False

        if isinstance(prompt, list):
            messages = prompt
        else:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": prompt},
            ]

        try:
            response = self.client.chat.completions.create(
                model=self.api_model, messages=messages, temperature=0.5, stream=False
            )
            response_text = response.choices[0].message.content.strip()

            if not return_response and not hasattr(self.app, "current_response_window"):
                self.app.output_ready_signal.emit(response_text)
            return response_text

        except Exception as e:
            error_str = str(e)
            logging.error(f"Error while generating content: {error_str}")
            if "exceeded" in error_str or "rate limit" in error_str:
                self.app.show_message_signal.emit(
                    "Rate Limit Hit",
                    "It appears you have hit an API rate/usage limit. Please try again later or adjust your settings.",
                )
            else:
                self.app.show_message_signal.emit(
                    "Error", f"An error occurred: {error_str}"
                )
            return ""

    def after_load(self):
        self.client = OpenAI(
            api_key=self.api_key,
            base_url=self.api_base,
            organization=self.api_organisation,
            project=self.api_project,
        )

    def before_load(self):
        self.client = None

    def cancel(self):
        self.close_requested = True


class OllamaCloudProvider(AIProvider):
    """
    Provider for Ollama Cloud (https://ollama.com).

    Recommended for most users: no local install required, just sign in at
    ollama.com, generate a free API key, paste it here, and you're set. The
    free tier ships with a limited weekly usage budget — comparable in
    spirit to Gemini's daily quota but refreshed weekly.

    We use the same `ollama` Python client as the local provider, just
    pointing `host` at `https://ollama.com` and passing the API key in the
    `Authorization: Bearer ...` header (the `headers=` kwarg of
    `ollama.Client`). This means the request shape is identical to local
    Ollama — we reuse the same `client.chat(...)` call path, just with
    different endpoint and auth.

    References:
      • https://docs.ollama.com/cloud
      • https://docs.ollama.com/api/authentication
      • https://ollama.com/signin (sign up + free key)
      • https://ollama.com/settings/keys (manage / regenerate keys)
    """

    # Hostname of the Ollama Cloud API. Exposed as a class-level constant
    # so tests and tools (e.g. the Settings UI) can reference it without
    # hard-coding the string in multiple places.
    OLLAMA_CLOUD_HOST = "https://ollama.com"

    def __init__(self, app):
        self.close_requested = None
        self.client = None
        self.app = app

        settings = [
            TextSetting(
                name="api_key",
                display_name="API Key",
                description="Paste your Ollama Cloud API key here",
            ),
            DropdownSetting(
                name="api_model",
                display_name="Model",
                # Default to gemma4:31b — verified available on Ollama Cloud.
                # Users can switch via the dropdown at any time.
                default_value="gemma4:31b",
                description="Select an Ollama Cloud model to use",
                options=[
                    # Verified available models on Ollama Cloud (https://ollama.com/api/tags).
                    # (display label, exact model ID from the official catalog).
                    ("Gemma 4 (31B, very fast)", "gemma4:31b"),
                    ("GLM 5.3 Flash (18B active)", "glm-5.3-flash"),
                    ("DeepSeek V4 Flash (13B active, 0731)", "deepseek-v4-flash:0731"),
                    ("Nemotron 3 Nano (30B)", "nemotron-3-nano:30b"),
                ],
                allow_custom=True,
                # The cloud catalog evolves quickly; the Custom escape hatch
                # keeps the provider useful as new models land without
                # requiring a code update.
                custom_placeholder="e.g., gemma4:31b",
            ),
            DropdownSetting(
                name="reasoning_effort",
                display_name="Reasoning Effort",
                # "low" is the lowest string level the Ollama API accepts
                # (low/medium/high/max); "off" maps to think=False. Models
                # without thinking support ignore it harmlessly.
                default_value="off",
                description="How much thinking the model does before answering",
                options=[
                    ("Off (fastest)", "off"),
                    ("Low", "low"),
                    ("Medium", "medium"),
                    ("High", "high"),
                ],
            ),
            # num_ctx default 4096: matches the local Ollama provider.
            TextSetting(
                "num_ctx",
                "Context window size (num_ctx)",
                "4096",
                "E.g. 4096. Larger = more memory, but supports longer inputs.",
            ),
            # num_predict cap bounds latency on chatty cloud models.
            TextSetting(
                "num_predict",
                "Max output tokens (num_predict)",
                "1000",
                "E.g. 1000. Caps response length to bound latency.",
            ),
            # 0.4 is a good writing-assistant default — deterministic enough
            # for proofreading, not robotic for rewrites. Range 0.0–1.0.
            TextSetting(
                "temperature",
                "Temperature",
                "0.4",
                "0.0 = deterministic, 1.0 = creative. 0.4 is a good writing-assistant default.",
            ),
        ]

        super().__init__(
            app,
            "Ollama Cloud (Recommended, free tier)",
            settings,
            # Friendly description for the Settings panel. We mirror the
            # Gemini panel's "•"-bulleted style so the two recommended
            # providers feel visually consistent.
            "• Ollama Cloud lets you run powerful models (Gemma, Gemini, DeepSeek, Nemotron...) with no local install.\n"
            "• Sign up for free at ollama.com, generate an API key, and paste it below.\n"
            "• The free tier includes a limited amount of usage that refreshes weekly.\n"
            "• Click the button below to open your API key dashboard.",
            "ollama",
            # Single CTA: open the key dashboard directly. Users who need
            # to sign up can do so from the same page.
            "Open API Key Dashboard",
            lambda: webbrowser.open("https://ollama.com/settings/keys"),
        )

    def _safe_int(self, value, default):
        """Parse a TextSetting value as int, falling back to `default` on bad input."""
        try:
            return int(value) if str(value).strip() else default
        except (ValueError, TypeError):
            return default

    def _safe_float(self, value, default):
        """Parse a TextSetting value as float, falling back to `default` on bad input."""
        try:
            return float(value) if str(value).strip() else default
        except (ValueError, TypeError):
            return default

    def get_response(
        self, system_instruction: str, prompt, return_response: bool = False
    ) -> str:
        """
        Send a chat request to Ollama Cloud.

        Uses the same `/api/chat` schema and response shape as the local
        Ollama provider — only the endpoint and auth header differ. The
        cloud endpoint uses `Authorization: Bearer <api_key>`, passed via
        the `ollama.Client(headers=...)` kwarg.

        Always performs a non-streaming request.
        Returns the response text if return_response is True, otherwise
        emits it via output_ready_signal.
        """
        self.close_requested = False

        if isinstance(prompt, list):
            messages = prompt
        else:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": prompt},
            ]

        # Reasoning effort: "off" maps to think=False. Most models support
        # the boolean off (per models.dev), but thinking-only models — where
        # reasoning is always on (e.g. glm-5.3-flash, only low/high/max) —
        # fall back to "low", the lowest level they offer.
        _THINKING_ONLY_MODELS = ("glm-5.3-flash",)
        effort = (getattr(self, "reasoning_effort", None) or "off").lower()
        model = (self.api_model or "").lower()
        if effort == "off":
            if any(t in model for t in _THINKING_ONLY_MODELS):
                think_value = "low"
            else:
                think_value = False
        else:
            think_value = effort

        options = {
            "num_ctx": self._safe_int(getattr(self, "num_ctx", None), 4096),
            "num_predict": self._safe_int(getattr(self, "num_predict", None), 1000),
            "temperature": self._safe_float(getattr(self, "temperature", None), 0.4),
        }

        try:
            logging.debug(
                f"Ollama Cloud request: model={self.api_model}, options={options}"
            )
            response = self.client.chat(
                model=self.api_model,
                messages=messages,
                think=think_value,
                options=options,
            )
            response_text = response["message"]["content"].strip()
            if not return_response and not hasattr(self.app, "current_response_window"):
                self.app.output_ready_signal.emit(response_text)
            return response_text
        except Exception as e:
            error_str = str(e)
            logging.error(f"Error during Ollama Cloud chat: {e}")
            # Be a little more user-friendly than the local provider's
            # generic message: free-tier / quota hits are the most common
            # cloud failure mode, and the user can fix them by waiting or
            # upgrading at ollama.com — not by editing local config.
            if (
                "401" in error_str
                or "unauthorized" in error_str.lower()
                or "invalid api key" in error_str.lower()
            ):
                self.app.show_message_signal.emit(
                    "Invalid Ollama Cloud API Key",
                    "Your Ollama Cloud API key was rejected. "
                    "Open the API Key Dashboard (button above) to copy a valid key, "
                    "then paste it here and save again.",
                )
            elif (
                "402" in error_str
                or "quota" in error_str.lower()
                or "usage limit" in error_str.lower()
            ):
                self.app.show_message_signal.emit(
                    "Ollama Cloud Free Tier Limit",
                    "You've used up this week's free-tier quota on Ollama Cloud. "
                    "It will reset on a rolling weekly basis, or you can upgrade your plan at ollama.com.",
                )
            else:
                self.app.output_ready_signal.emit(
                    "An error occurred during Ollama Cloud chat."
                )
            return ""

    def after_load(self):
        """
        Build the Ollama Cloud client.

        The host is fixed to `https://ollama.com`; the API key is passed in
        the `Authorization: Bearer ...` header via the `headers=` kwarg
        (the official cloud-auth pattern documented at
        https://docs.ollama.com/api/authentication).
        """
        # Guard against an empty key at startup — `ollama.Client` would
        # happily build without one and only fail at request time. We
        # still build the client (so the rest of the provider's lifecycle
        # works) but tag it so we can short-circuit on send.
        headers = {"Authorization": f"Bearer {self.api_key}"} if self.api_key else {}
        self.client = OllamaClient(host=self.OLLAMA_CLOUD_HOST, headers=headers)

    def before_load(self):
        self.client = None

    def load_config(self, config: dict):
        """
        Load configuration, deobfuscating the API key if needed.
        Mirrors the Gemini provider's pattern so an existing user upgrading
        from plaintext storage (or migrating in from a different machine)
        still gets a working key.
        """
        if "api_key" in config:
            config = config.copy()  # Don't mutate the caller's dict
            config["api_key"] = deobfuscate_api_key(config["api_key"])
        super().load_config(config)

    def save_config(self):
        """
        Save configuration, obfuscating the API key for storage.
        Same XOR+base64 obfuscation Gemini uses — at-rest defence in
        depth only (anyone with the obfuscated blob can trivially reverse
        it on the same machine), but it stops a casual Ctrl+F in the
        config file from harvesting live keys.
        """
        config = {}
        for setting in self.settings:
            value = setting.get_value()
            if setting.name == "api_key":
                value = obfuscate_api_key(value)
            config[setting.name] = value
        self.app.config["providers"][self.provider_name] = config
        self.app.save_config(self.app.config)

    def cancel(self):
        self.close_requested = True


class OllamaProvider(AIProvider):
    """
    Provider for connecting to a LOCAL Ollama server.

    This is the "For Experts" option — it requires the user to install
    and run `ollama serve` on their own machine and to pull a model
    locally. If you just want to get up and running, use Ollama Cloud
    (the recommended provider listed above this one in Settings).

    Uses the /chat endpoint of the Ollama server to generate a response.
    Streaming is not used.

    Thinking is explicitly disabled (`think=False`) so reasoning-capable
    models like qwen3 / deepseek-r1 / gpt-oss don't burn latency on an
    internal chain-of-thought before answering. For GPT-OSS specifically,
    Ollama only accepts string levels ("low" / "medium" / "high") instead
    of a boolean, so we use "low" — the closest to "off" it offers.

    Reference: https://docs.ollama.com/capabilities/thinking
    """

    def __init__(self, app):
        self.close_requested = None
        self.client = None
        self.app = app
        settings = [
            TextSetting(
                "api_base",
                "API Base URL",
                "http://localhost:11434",
                "E.g. http://localhost:11434",
            ),
            TextSetting("api_model", "API Model", "llama3.1:8b", "E.g. llama3.1:8b"),
            TextSetting(
                "keep_alive",
                "Time to keep the model loaded in memory in minutes",
                "5",
                "E.g. 5",
            ),
            # num_ctx default 4096: Ollama's default of 2048 is too small for our
            # system prompt + long user input, which used to cause silent truncation.
            TextSetting(
                "num_ctx",
                "Context window size (num_ctx)",
                "4096",
                "E.g. 4096. Larger = more memory, but supports longer inputs.",
            ),
            # num_predict cap bounds latency and prevents runaway generation on local
            # models. Our responses (proofread/rewrite/summary) are short by design.
            TextSetting(
                "num_predict",
                "Max output tokens (num_predict)",
                "1000",
                "E.g. 1000. Caps response length to bound latency.",
            ),
            # 0.4 is a good writing-assistant default — deterministic enough for
            # proofreading, not robotic for rewrites. Range is 0.0–1.0.
            TextSetting(
                "temperature",
                "Temperature",
                "0.4",
                "0.0 = deterministic, 1.0 = creative. 0.4 is a good writing-assistant default.",
            ),
        ]
        super().__init__(
            app,
            "Ollama (For Experts)",
            settings,
            "• Connect to an Ollama server (local LLM).",
            "ollama",
            "Ollama Set-up Instructions",
            lambda: webbrowser.open(
                "https://github.com/theJayTea/WritingTools?tab=readme-ov-file#-optional-ollama-local-llm-instructions-for-windows-v7-onwards"
            ),
        )

    def _safe_int(self, value, default):
        """Parse a TextSetting value as int, falling back to `default` on bad input."""
        try:
            return int(value) if str(value).strip() else default
        except (ValueError, TypeError):
            return default

    def _safe_float(self, value, default):
        """Parse a TextSetting value as float, falling back to `default` on bad input."""
        try:
            return float(value) if str(value).strip() else default
        except (ValueError, TypeError):
            return default

    def get_response(
        self, system_instruction: str, prompt: str | list, return_response: bool = False
    ) -> str:
        """
        Send a chat request to the Ollama server.

        Always performs a non-streaming request.
        Returns the response text if return_response is True,
        otherwise emits it via output_ready_signal.
        """
        self.close_requested = False

        if isinstance(prompt, list):
            messages = prompt
        else:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": prompt},
            ]

        # GPT-OSS only accepts string think levels; everything else accepts bool.
        # "low" is the closest to "off" GPT-OSS offers.
        think_value = "low" if "gpt-oss" in (self.api_model or "").lower() else False

        options = {
            "num_ctx": self._safe_int(getattr(self, "num_ctx", None), 4096),
            "num_predict": self._safe_int(getattr(self, "num_predict", None), 1000),
            "temperature": self._safe_float(getattr(self, "temperature", None), 0.4),
        }

        try:
            response = self.client.chat(
                model=self.api_model,
                messages=messages,
                think=think_value,
                options=options,
            )
            response_text = response["message"]["content"].strip()
            if not return_response and not hasattr(self.app, "current_response_window"):
                self.app.output_ready_signal.emit(response_text)
            return response_text
        except Exception as e:
            logging.error(f"Error during Ollama chat: {e}")
            self.app.output_ready_signal.emit("An error occurred during Ollama chat.")
            return ""

    def after_load(self):
        self.client = OllamaClient(host=self.api_base)

    def before_load(self):
        self.client = None

    def cancel(self):
        self.close_requested = True
