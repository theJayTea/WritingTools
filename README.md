# Writing Tools

https://github.com/user-attachments/assets/d3ce4694-b593-45ff-ae9a-892ce94b1dc8

## 🚀 What is Writing Tools?

Writing Tools is an Apple Intelligence-inspired application for Windows, Linux, and macOS (alpha) that supercharges your writing with AI LLMs. It lets you fix up grammar and more with one hotkey press, system-wide. It's currently the world's most intelligent system-wide grammar assistant.

### 🌟 Why Choose Writing Tools?

Aside from being the only Windows/Linux program that works like Apple's Writing Tools:

- **Versatile AI LLM Support**: Jump in quickly with support for the **free Gemini API**, or use an extensive range of **local LLMs** (via Ollama *[instructions below]*, llama.cpp, KoboldCPP, TabbyAPI, vLLM, etc.) or **cloud-based LLMs** (ChatGPT, Mistral AI, etc.) with Writing Tools' OpenAI-API-Compatibility.
- **System-wide Functionality**: Works instantly in **any application** where you can select text. **Does not overwrite your clipboard**.
- **Completely free and Open-source**: No subscriptions, no hidden costs. Bloat-free & uses pretty much **0% of your CPU**.
- **Chat Mode**: Invoke Writing Tools with no text selected to enter a chat mode for quick queries and assistance.
- **Privacy-focused**: Your API key and config files stay on *your* device. NO logging, diagnostic collection, tracking, or ads. Invoked *only* on your command. Local LLMs keep your data on your device & work without the internet.
- **Supports Many Languages**: Works for any language! It can even *translate* text across languages better than Google Translate (type *"translate to [language]"* in "Describe your change...").
- **Code Support**: Select code and ask Writing Tools to work on it (fix, improve, convert languages) through "Describe your change...".
- **Themes, Dark Mode, & Customization**: Choose between **2 themes**: a blurry gradient theme and a plain theme that resembles the Windows + V pop-up! Also has full **dark mode** support. **Set your own hotkey** for quick access.

Writing Tools has been featured on [Beebom](https://beebom.com/high-schooler-app-brings-apple-inteligence-writing-tools-windows/), [XDA](https://www.xda-developers.com/windows-pc-can-now-deliver-instant-free-writing-help-across-all-apps/), [Neowin](https://www.neowin.net/news/this-small-app-brings-some-apple-intelligence-features-to-windows/), [and](https://tinhte.vn/thread/mang-apple-intelligence-len-windows-chay-gemini-1-5-flash-thong-minh-hon-ho-tro-san-tieng-viet.3840902/) [more](https://www.computer-wd.com/2024/10/new-computer-programs-to-try-now.html)!

## ✨ Features

- **Proofread**: The smartest grammar and spelling corrector. Sorry not sorry, Grammarly Premium.
- **Rewrite**: Improve the phrasing of your text.
- **Make Friendly/Professional**: Adjust the tone of your writing.
- **Summarize**: Create concise summaries of longer texts.
- **Extract Key Points**: Highlight the most important information.
- **Create Tables**: Convert text into a structured Markdown table (use [Obsidian](https://obsidian.md/) or [Markdown-to-Excel](https://tableconvert.com/markdown-to-excel) to work with the markdown table).
- **Custom Instructions**: Give specific directions for text modifications (e.g. `Translate to French`).

Invoke Writing Tools with no text selected to enter a chat mode.

## 🖱 How to Use

1. Select any text in any application (or don't select any text to use chat mode).
2. Press your hotkey (default: Ctrl+Space).
3. Choose an option from the popup menu or enter a custom instruction.
4. Watch as your text is magically improved!

## 🛠 Installation

1. Go to the [Releases](https://github.com/theJayTea/WritingTools/releases) page and download the latest `Writing.Tools.zip` file. For Linux and macOS, run it from source with the instructions further below.
   
2. Extract it where you want, run `Writing Tools.exe`, and enjoy! :D

   *Note: If you extract Writing Tools into a protected system folder like Program Files, you'll need to run it as administrator at least on the first launch or it won't be able to create/edit its config file (in the same folder as its exe).*
   
3. To let it automatically start when you boot your PC, add a shortcut of the `Writing Tools.exe` to the Windows Start-Up folder (Open Run and type `shell:startup` to get to this folder). 

## 🦙 (optional) Ollama Local LLM Instructions:
1. [Download](https://ollama.com/download) and install Ollama.
2. Choose the LLM you want to use form [here](https://ollama.com/library). Recommended: Llama 3.1 8B if you have ~8GB of RAM or VRAM. If instead you are below that, try Gemma2:2b.
3. Open your terminal, and type `ollama serve` to start the server. Don't close the terminal, leave `ollama` running in the background.
4. Download the model you want to use by running `ollama pull <model-name>` in another terminal, for example: `ollama pull llama3.1` or `ollama pull gemma2:2b`. This will download your model and make it available for use. That's it!
5. In Writing Tools, choose the `OpenAl Compatible` AI Provider, and set your API Key to `ollama`, your API Base URL to `http://localhost:11434/v1`, and your API Model to `llama3.1:latest`. Enjoy Writing Tools with _absolute_ privacy and no internet connection! 🎉

## 🖥️ (optional) Other Local OpenAI-compatible LLMs (for experts):
1. In Writing Tools, choose the `OpenAl Compatible` AI Provider and as API Base URL enter your local server address.
2. If your server provides an API key, like TabbyAPI, set it inside the API field. If it doesn't, like KoboldCpp, set the API key to a random string, even something like "a" will suffice.

## 🔒 Privacy

I believe strongly in protecting your privacy. Writing Tools:
- Only sends text to the chosen AI provider (encrypted) when you *explicitly* use one of the options.
- Only stores your API key locally on your device.
- Does not collect or store any of your writing data by itself. It doesn't even collect general logs, so it's super light and privacy-friendly.

Note: Privacy policies may vary depending on the AI provider you choose. Please review the terms of service for your selected provider.

## 🐞 Known Issues
1. (Being investigated) On some devices, Writing Tools does not work correctly with the default hotkey.
   To fix it, simply change the hotkey to **ctrl+`** or **ctrl+j** and restart Writing Tools.
   PS: If a hotkey is already in use by a program or background process, Writing Tools may not be able to intercept it. The above hotkeys are usualy unused.

2. (Fix almost ready!) On some devices, Writing Tools may not work in Microsoft Word.

3. The initial launch of the `Writing Tools.exe` might take unusually long — this seems to be because AV software extensively scans this new executable before letting it run. Once it launches into the background in RAM, it works instantly as usual.
 
## 👨‍💻 To Run Writing Tools Directly from the Source Code

If you prefer to run the program directly from the `main.py` file, follow these OS-specific instructions.

The code in the macOS folder is more outdated, but will work on macOS. The code in the Windows_and_Linux folder is slightly improved, and has been refactored to be cross-platform so it may work on macOS too!

**1. Download the Code**
- Click the download button:
   ![image](https://github.com/user-attachments/assets/4c6cab79-4918-451c-9ad1-1bbcf8472275)


**2. Install Dependencies**  
After extracting the folder, open your **Terminal** (or **Command Prompt**) in the relevant directory.

- Windows:
   ```bash
   cd path\to\Windows_and_Linux
   pip install -r requirements.txt
   ```

- macOS/Linux:
   ```bash
   cd /path/to/Windows_and_Linux
   pip3 install -r requirements.txt
   ```

Make sure [Python is installed](https://www.python.org/downloads/)!


**3. Run the Program**
- **Windows:**
   ```bash
   pythonw main.py
   ```
- **macOS/Linux:**
   ```bash
   python3 main.py
   ```


## 👨‍💻 To compile the application yourself:

Here's how to compile it with PyInstaller:

1. Install PyInstaller: `pip install pyinstaller`
2. Run the build script: `pyinstaller-build-script.py`

Ideally, run this in a Python venv.

## 🌟 Contributors

Writing Tools would not be where it is today without its amazing contributors:

**1. [Cameron Redmore (CameronRedmore)](https://github.com/CameronRedmore):**

Extensively refactored Writing Tools and added OpenAI Compatible API support, streamed responses, and the chat mode when no text is selected.

**2. [momokrono](https://github.com/momokrono):**

Added Linux support, and switched to the pynput API to improve Windows stability. Fixed misc. bugs, such as handling quitting onboarding without completing it.
                
**3. [Disneyhockey40 (Soszust40)](https://github.com/Disneyhockey40):**

Helped add dark mode, the plain theme, tray menu fixes, and UI improvements.

## 🤝 Contributing

I welcome contributions! :D
If you'd like to improve Writing Tools, feel free to open a Pull Request or get in touch with me.

## 📬 Contact

My email: jesaitarun@gmail.com

Made with ❤️ by a high school student. Check out my other AI app, [Bliss AI](https://play.google.com/store/apps/details?id=com.jesai.blissai), a novel AI tutor free on the Google Play Store!

## 📄 License

Distributed under the GNU General Public License v3.0.
