"""
AI Provider Architecture for Writing Tools
----------------------------------------

This module handles different AI model providers (Gemini, OpenAI-compatible) and manages their interactions
with the main application. It uses an abstract base class pattern for provider implementations.

Key Components:
1. AIProviderSetting - Abstract base class for provider settings (API keys, model names etc)
   - TextSetting - For text input settings
   - DropdownSetting - For dropdown selection settings

2. AIProvider - Abstract base class that all providers must implement
   - Defines the interface for AI interactions
   - Handles configuration loading/saving
   - Manages provider-specific UI elements

3. The provider implementations are GeminiProvider (for Google's Gemini API) and OpenAICompatibleProvider (for any OpenAI-compatible API). Both of them:
      - Support both non-streaming and streaming (experimental; being worked on!) responses
      - Handle chat history (for the follow-up responses), with proper role formatting (user/model) according to their API requirements.
      
Response Flow:
1. Main app calls provider's get_response() with system instruction and prompt
2. Provider formats the request according to its API requirements
3. For direct text operations (Proofread etc):
   - Emits output via app.output_ready_signal for text replacement
4. For window-based operations (Summary etc):
   - Returns formatted response text
   - Supports chat history for follow-up questions

Chat/History Handling:
- Gemini: Uses 'user'/'model' roles with 'parts' containing messages
- OpenAI: Uses a standard OpenAI message format with 'system'/'user'/'assistant' roles
- Both maintain conversation context (until the Window is closed) for follow-up questions
"""

import logging
import webbrowser
from abc import ABC, abstractmethod
from typing import List

import google.generativeai as genai
from google.generativeai.types import HarmBlockThreshold, HarmCategory
from ollama import Client as OllamaClient
from openai import OpenAI
from PySide6 import QtWidgets
from PySide6.QtWidgets import QVBoxLayout
from ui.UIUtils import colorMode


class AIProviderSetting(ABC):
    def __init__(self, name: str, display_name: str = None, default_value: str = None, description: str = None):
        self.name = name
        self.display_name = display_name if display_name else name
        self.default_value = default_value if default_value else ""
        self.description = description if description else ""

    @abstractmethod
    def render_to_layout(self, layout: QVBoxLayout):
        pass

    @abstractmethod
    def set_value(self, value):
        pass

    @abstractmethod
    def get_value(self):
        pass

class TextSetting(AIProviderSetting):
    def __init__(self, name: str, display_name: str = None, default_value: str = None, description: str = None):
        super().__init__(name, display_name, default_value, description)

        self.internal_value = default_value
        self.input = None

    def render_to_layout(self, layout: QVBoxLayout):
        row_layout = QtWidgets.QHBoxLayout()
        label = QtWidgets.QLabel(self.display_name)
        label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        row_layout.addWidget(label)

        self.input = QtWidgets.QLineEdit(self.internal_value)
        self.input.setStyleSheet(f"""
            font-size: 16px;
            padding: 5px;
            background-color: {'#444' if colorMode == 'dark' else 'white'};
            color: {'#ffffff' if colorMode == 'dark' else '#000000'};
            border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
        """)

        self.input.setPlaceholderText(self.description)

        row_layout.addWidget(self.input)
        layout.addLayout(row_layout)

    def set_value(self, value):
        self.internal_value = value

    def get_value(self):
        return self.input.text()


class AIProvider(ABC):
    # settings: List[AIProviderSetting] is a list of AIProviderSetting objects that define the settings of the AI provider.
    def __init__(self, app, provider_name: str, settings: List[AIProviderSetting], description: str = "An unfinished AI provider!", logo: str = "generic", button_text: str = "Go to URL", button_action: callable = None):
        self.provider_name = provider_name
        self.settings = settings
        self.app = app
        self.description = description if description else "An unfinished AI provider!"

        self.logo = logo
        self.button_text = button_text
        self.button_action = button_action

    @abstractmethod
    def get_response(self, system_instruction: str, prompt: str) -> str:
        """
        Pass a system instruction and a prompt to the AI provider and return the response.
        """
        pass

    def load_config(self, config: dict):
        """
        Load the configuration into this provider's memory.
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
        Save the provider's memory to the config, and then save the config to disk.
        """
        config = {}
        for setting in self.settings:
            config[setting.name] = setting.get_value()

        self.app.config["providers"][self.provider_name] = config
        self.app.save_config(self.app.config)

    @abstractmethod
    def after_load(self):
        """
        A method to be overridden by subclasses that is called after the settings have been loaded.
        """
        pass

    @abstractmethod
    def before_load(self):
        """
        A method to be overridden by subclasses that is called before the settings have been loaded.
        Useful for performing cleanup etc.
        """
        pass

    @abstractmethod
    def cancel(self):
        """
        Cancel the current request.
        """
        pass

class GeminiProvider(AIProvider):
    def __init__(self, app):
        """
        Initialize the Gemini provider.
        """
        self.close_requested = False
        self.model = None

        settings = [
            TextSetting(name="api_key", display_name="API Key", description="Paste your Gemini API key here"),
            DropdownSetting(
                name="model_name",
                display_name="Model",
                default_value="gemini-2.0-flash",
                description="Select Gemini model to use",
                options=[
                    ("Gemini 2.0 Flash Lite (intelligent | very fast | 30 uses/min)", "gemini-2.0-flash-lite-preview-02-05"),
                    ("Gemini 2.0 Flash (very intelligent | fast | 15 uses/min)", "gemini-2.0-flash"),
                    ("Gemini 2.0 Flash Thinking (most intelligent | slow | 10 uses/min)", "gemini-2.0-flash-thinking-exp-01-21"),
                    ("Gemini 2.0 Pro (most intelligent | slow | 2 uses/min)", "gemini-2.0-pro-exp-02-05")
                ]
            )
        ]
        super().__init__(app, "Gemini (Recommended)", settings, "• Google\'s Gemini is a powerful AI model that\'s available for free!\n• Writing Tools needs an \"API key\" to connect to Gemini on your behalf.\n• Simply click Get API Key button below, copy your API key, and paste it below.\n• Note: With the free tier of the Gemini API, Google may anonymize & store the text that you send Writing Tools for Gemini\'s improvement.", "gemini", "Get API Key", lambda: webbrowser.open("https://aistudio.google.com/app/apikey"))

    def get_response(self, system_instruction: str, prompt: str, return_response: bool = False) -> str:
        """
        Pass a system instruction and a prompt to the AI provider and return the response.
        If return_response is True, returns the complete response instead of streaming it.
        """
        self.close_requested = False
        full_response = []

        response = self.model.generate_content(
            contents=[system_instruction, prompt],
            stream=self.app.config.get("streaming", False) and not return_response
        )

        # Check if the response was blocked
        if response.prompt_feedback.block_reason:
            logging.warning('Response was blocked due to safety settings')
            self.app.show_message_signal.emit('Content Blocked',
                                        'The generated content was blocked due to safety settings.')
            return ""

        try:
            if return_response or hasattr(self.app, 'current_response_window'):
                # For follow-up questions or window-based options, return complete response
                return response.text.rstrip('\n')
            else:
                # For normal operation, stream the response
                for chunk in response:
                    if self.close_requested:
                        break
                    else:
                        # Strip any trailing newlines from chunks
                        self.app.output_ready_signal.emit(chunk.text.rstrip('\n'))
        except Exception as e:
            logging.error(f"Error while streaming: {e}")
            self.app.output_ready_signal.emit("An error occurred while streaming.")
        finally:
            self.close_requested = False
            if not return_response:
                self.app.replace_text(True)
        
        return ""  # Default return for streaming mode

    def after_load(self):
        genai.configure(api_key=self.api_key)

        system_instruction = "You are a helpful AI assistant. Provide clear and direct responses, maintaining the same format and style as your previous responses. If appropriate, use Markdown formatting to make your response more readable."

        self.model = genai.GenerativeModel(
            model_name=self.model_name,
            generation_config=genai.types.GenerationConfig(
                candidate_count=1,
                max_output_tokens=1000,
                temperature=0.5
            ),
            safety_settings={
                HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_NONE,
                HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_NONE,
                HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_NONE,
                HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_NONE,
            }
        )

    def before_load(self):
        self.model = None

    def cancel(self):
        self.close_requested = True

class DropdownSetting(AIProviderSetting):
    def __init__(self, name: str, display_name: str = None, default_value: str = None, description: str = None, options: list = None):
        super().__init__(name, display_name, default_value, description)
        self.options = options if options else []
        self.internal_value = default_value
        self.dropdown = None

    def render_to_layout(self, layout: QVBoxLayout):
        row_layout = QtWidgets.QHBoxLayout()
        label = QtWidgets.QLabel(self.display_name)
        label.setStyleSheet(f"font-size: 16px; color: {'#ffffff' if colorMode == 'dark' else '#333333'};")
        row_layout.addWidget(label)

        self.dropdown = QtWidgets.QComboBox()
        self.dropdown.setStyleSheet(f"""
            font-size: 16px;
            padding: 5px;
            background-color: {'#444' if colorMode == 'dark' else 'white'};
            color: {'#ffffff' if colorMode == 'dark' else '#000000'};
            border: 1px solid {'#666' if colorMode == 'dark' else '#ccc'};
        """)
        
        for option, value in self.options:
            self.dropdown.addItem(option, value)

        # Set current value
        index = self.dropdown.findData(self.internal_value)
        if index != -1:
            self.dropdown.setCurrentIndex(index)

        row_layout.addWidget(self.dropdown)
        layout.addLayout(row_layout)

    def set_value(self, value):
        self.internal_value = value

    def get_value(self):
        return self.dropdown.currentData()


class OpenAICompatibleProvider(AIProvider):
    def __init__(self, app):
        """
        Initialize the OpenAI-compatible provider.
        """
        self.close_requested = None
        self.client = None

        settings = [
            TextSetting(name = "api_key", display_name = "API Key", description = "API key for the OpenAI-compatible API."),
            TextSetting("api_base", "API Base URL", "https://api.openai.com/v1", "Eg. https://api.openai.com/v1"),
            TextSetting("api_organisation", "API Organisation", "", "Leave blank if not applicable."),
            TextSetting("api_project", "API Project", "", "Leave blank if not applicable."),
            TextSetting("api_model", "API Model", "gpt-4o-mini", "Eg. gpt-4o-mini"),
        ]

        super().__init__(app, "OpenAI Compatible (For Experts)", settings,
            "• Connect to ANY Open-AI Compatible API (v1/chat/completions), such as OpenAI, Mistral AI, Anthropic, or locally hosted models via llama.cpp, KoboldCPP, TabbyAPI, vLLM, etc.\n• Note: You must adhere to the connected service's Terms of Service, and your text will be processed as per their Privacy Policies etc.",
            "openai", "Get OpenAI API Key", lambda: webbrowser.open("https://platform.openai.com/account/api-keys"))

    def get_response(self, system_instruction: str, prompt: str|list, return_response: bool = False) -> str:
        """
        Pass a system instruction and a prompt to the AI provider and return the response.
        """
        self.close_requested = False

        try:
            response = self.model.generate_content(
                contents=[system_instruction, prompt],
                stream=False  # Streaming deprecated
            )

            # Check if the response was blocked
            if response.prompt_feedback.block_reason:
                logging.warning('Response was blocked due to safety settings')
                self.app.show_message_signal.emit('Content Blocked',
                                        'The generated content was blocked due to safety settings.')
                return ""

            # Get complete response text
            response_text = response.text.rstrip('\n')

            # For direct text operations, emit the output
            if not return_response and not hasattr(self.app, 'current_response_window'):
                self.app.output_ready_signal.emit(response_text)
                self.app.replace_text(True)

            return response_text

        except Exception as e:
            error_str = str(e)
            logging.error(f"Error while generating content: {error_str}")
            
            if "Resource has been exhausted" in error_str:
                # Rate limit error handling
                self.app.show_message_signal.emit(
                    'Rate Limit Hit',
                    'Whoops! You\'ve hit the per-minute rate limit of the Gemini API. Please try again in a few moments.\n\n'
                    'If this happens often, simply switch to a Gemini model with a higher usage limit in Settings.'
                )
            else:
                # Generic error handling
                self.app.show_message_signal.emit('Error', f"An error occurred: {error_str}")
            
            return ""

    def after_load(self):
        self.client = OpenAI(api_key=self.api_key, base_url=self.api_base, organization=self.api_organisation, project=self.api_project)

    def before_load(self):
        self.client = None

    def cancel(self):
        self.close_requested = True


class OllamaProvider(AIProvider):
    def __init__(self, app):
        """
        Initialize the Local OpenAI-compatible provider.
        """
        self.close_requested = None
        self.client = None
        self.app = app
        settings = [
            TextSetting("api_base", "API Base URL", "http://localhost:11434", "Eg. http://localhost:11434"),
            TextSetting("api_model", "API Model", "llama3.1:8b", "Eg. llama3.1:8b"),
            TextSetting("keep_alive", "Time to keep the model loaded in memory in minutes", "5", "Eg. 5")
        ]
        super().__init__(app, "Ollama (For Experts)", settings, "• Connect to an Ollama server.", "ollama", "Ollama Set-up Instructions", lambda: webbrowser.open("https://github.com/theJayTea/WritingTools?tab=readme-ov-file#-optional-ollama-local-llm-instructions-for-windows-v7-onwards"))
    def get_response(self, system_instruction: str, prompt: str|list, return_response: bool = False):
        self.close_requested = False
        streaming = self.app.config.get("streaming", False) and not return_response

        if isinstance(prompt, list):
            messages = prompt
        else:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": prompt}
            ]

        if streaming:
            try:
                stream = self.client.chat(model=self.api_model, messages=messages, stream=streaming, keep_alive=f'{self.keep_alive}m')
                for chunk in stream:
                    if self.close_requested:
                        break
                    self.app.output_ready_signal.emit(chunk['message']['content'].rstrip('\n'))
            except Exception as e:
                logging.error(f"Error while streaming: {e}")
                self.app.output_ready_signal.emit("An error occurred while streaming.")
            finally:
                self.close_requested = True
                self.app.replace_text(True)
                return ""
        else:
            try:
                response = self.client.chat(model=self.api_model, messages=messages)
                response_text = response['message']['content'].strip()
                if not return_response and not hasattr(self.app, 'current_response_window'):
                    self.app.output_ready_signal.emit(response_text)
                return  response_text
            except Exception as e:
                logging.error(f"Error during Ollama chat: {e}")
    def after_load(self):
        self.client = OllamaClient(host=self.api_base)
    def before_load(self):
        self.client = None
    def cancel(self):
        self.close_requested = True

