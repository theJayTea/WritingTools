# Writing Tools

**Instantly proofread and optimize your writing system-wide with AI:**

https://github.com/user-attachments/assets/d3ce4694-b593-45ff-ae9a-892ce94b1dc8

**Summarize content (webpages, YouTube videos, documents...) in a click:**

https://github.com/user-attachments/assets/76d13eb9-168e-4459-ada4-62e0586ae58c

## ✨ What is Writing Tools?

Writing Tools is an **Apple Intelligence-inspired application for Windows, Linux, and macOS that supercharges your writing with an AI LLM** (cloud-based or local).

With one hotkey press system-wide, it lets you fix grammar, optimize text according to your instructions, summarize content (webpages, YouTube videos, etc.), and more.

It's currently the **world's most intelligent system-wide grammar assistant** and works in almost any language!

## ⚡ What can I do with it, exactly?

### 1️⃣ Hyper-intelligent Writing Tools:
- Select _any_ text on your PC and invoke Writing Tools with `ctrl+space`.
- Choose **Proofread**, **Rewrite**, **Friendly**, **Professional**, **Concise**, or even enter **custom instructions** (e.g., _"add comments to this code"_, _"make it title case"_, _"translate to French"_).
- Your text will instantly be replaced with the AI-optimized version. Use `ctrl+z` to revert.

### 2️⃣ Powerful content summarization that you can chat with:
- Select all text in any webpage, document, email, etc., with `ctrl+a`, or select the transcript of a YouTube video (from its description).
- Choose **Summary**, **Key Points**, or **Table** after invoking Writing Tools.
- Get a pop-up summary with clear and beautiful formatting (with Markdown rendering), saving you hours.
- Chat with the summary if you'd like to learn more or have questions.

### 3️⃣ Chat with an LLM anytime in a click:
- Press `ctrl+space` without selecting text to start a conversation with your LLM _(for privacy, chat history is deleted when you close the window)_.

## 🌟 Why Choose Writing Tools?

Aside from being the only Windows/Linux program like Apple's Writing Tools, and the only way to use them on an Intel Mac:

- **More intelligent than Apple's Writing Tools and Grammarly Premium:** Apple uses a tiny 3B parameter model, while Writing Tools lets you use much more advanced models for free (e.g., Gemini 2.0 Flash [~30B]). Grammarly's rule-based NLP can't compete with LLMs.
- **Completely free and open-source:** No subscriptions or hidden costs. Bloat-free and uses **0% of your CPU** when idle.
- **Versatile AI LLM support:** Jump in quickly with the **free Gemini API & Gemini 2.0**, or an extensive range of **local LLMs** (via Ollama [[instructions]](https://github.com/theJayTea/WritingTools?tab=readme-ov-file#-optional-ollama-local-llm-instructions), llama.cpp, KoboldCPP, TabbyAPI, vLLM, etc.) or **cloud-based LLMs** (ChatGPT, Mistral AI, etc.) through Writing Tools' OpenAI-API-compatibility.
- **Does not mess with your clipboard, and works system-wide.**
- **Privacy-focused**: Your API key and config files stay on *your* device. NO logging, diagnostic collection, tracking, or ads. Invoked *only* on your command. Local LLMs keep your data on your device & work without the internet.
- **Supports multiple languages:** Works with any language and translates text better than Google Translate (type "translate to [language]" in `Describe your change...`).
- **Code support:** Fix, improve, translate, or add comments to code with `Describe your change...`."
- **Themes, Dark Mode, & Customization**: Choose between **2 themes**: a blurry gradient theme and a plain theme that resembles the Windows + V pop-up! Also has full **dark mode** support. **Set your own hotkey** for quick access.

Writing Tools has been featured on [Beebom](https://beebom.com/high-schooler-app-brings-apple-inteligence-writing-tools-windows/), [XDA](https://www.xda-developers.com/windows-pc-can-now-deliver-instant-free-writing-help-across-all-apps/), [Neowin](https://www.neowin.net/news/this-small-app-brings-some-apple-intelligence-features-to-windows/), [and](https://www.windowscentral.com/software-apps/can-apple-catch-up-apple-intelligence-just-shipped-yet-free-apple-writing-tools-on-github-for-windows-and-linux-make-a-better-alternative) [numerous](https://tinhte.vn/thread/mang-apple-intelligence-len-windows-chay-gemini-1-5-flash-thong-minh-hon-ho-tro-san-tieng-viet.3840902/) [others](https://www.computer-wd.com/2024/10/new-computer-programs-to-try-now.html)!

## ✅ Installation

### Windows:
1. Go to the [Releases](https://github.com/theJayTea/WritingTools/releases) page and download the latest `Writing.Tools.zip` file.
2. Extract it to your desired location, run `Writing Tools.exe`, and enjoy! :D

*Note: Writing Tools is a portable app. If you extract it into a protected folder (e.g., Program Files), run it as administrator at least on first launch so it can create/edit its config file (in the same folder as its exe).*

**PS:** Go to Writing Tools' Settings (from its tray icon at the bottom right of the taskbar) to enable starting Writing Tools on boot.

### Linux:
Run it from the source code (instructions below).

### macOS (beta):
The macOS version is a **native Swift port**, developed by [Aryamirsepasi](https://github.com/Aryamirsepasi). View the [README inside the macOS folder](https://github.com/theJayTea/WritingTools/tree/main/macOS) to learn more.

To install it:
1. Go to the [Releases](https://github.com/theJayTea/WritingTools/releases) page and download the latest `.dmg` file.
2. Open the `.dmg` file and drag the `writing-tools.app` into the Applications folder. That's it!

## 👀 Tips

#### 1️⃣ Summarise a YouTube video from its transcript:

https://github.com/user-attachments/assets/dd4780d4-7cdb-4bdb-9a64-e93520ab61be

#### 2️⃣ Make Writing Tools work better in MS Word: the `ctrl+space` keyboard shortcut is mapped to "Clear Formatting", making you lose paragraph indentation. Here's how to improve this:
P.S.: Word's rich-text formatting (bold, italics, underline, colours...) will be lost on using Writing Tools. A Markdown editor such as [Obsidian](https://obsidian.md/) has no such issue.

https://github.com/user-attachments/assets/42a3d8c7-18ac-4282-9478-16aab935f35e

## ✨ Options Explained

- **Proofread:** The smartest grammar & spelling corrector. Sorry not sorry, Grammarly Premium.
- **Rewrite:** Improve the phrasing of your text.
- **Make Friendly/Professional:** Adjust the tone of your text.
- **Custom Instructions:** Tailor your request (e.g., "Translate to French") through `Describe your change...`.

The following options respond in a pop-up window (with markdown rendering, selectable text, and a zoom level that saves & applies on app restarts):
- **Summarize:** Create clear and concise summaries.
- **Extract Key Points:** Highlight the most important points.
- **Create Tables:** Convert text into a formatted table. PS: You can copy & paste the table into MS Word.

## 🔒 Privacy

I believe strongly in protecting your privacy. Writing Tools:
- Does not collect or store any of your writing data by itself. It doesn't even collect general logs, so it's super light and privacy-friendly.
- Lets you use local LLMs to process your text entirely on-device.
- Only sends text to the chosen AI provider (encrypted) when you *explicitly* use one of the options.
- Only stores your API key locally on your device.

Note: If you choose to use a cloud based LLM, refer to the AI provider's privacy policy and terms of service.

## 🦙 (Optional) Ollama Local LLM Instructions:
1. [Download](https://ollama.com/download) and install Ollama.
2. Choose an LLM from [here](https://ollama.com/library). Recommended: Llama 3.1 8B (~8GB RAM or VRAM required).
3. Run `ollama run llama3.1:8b` in your terminal to download and launch Llama 3.1.
4. In Writing Tools, set the `OpenAI-Compatible` provider with:
   - API Key: `ollama`
   - API Base URL: `http://localhost:11434/v1`
   - API Model: `llama3.1:8b`
5. That's it! Enjoy Writing Tools with _absolute_ privacy and no internet connection! 🎉 From now on, you'll simply need to launch Ollama and Writing Tools into the background for it to work.

## 🐞 Known Issues
1. (Being investigated) On some devices, Writing Tools does not work correctly with the default hotkey.
   
   To fix it, simply change the hotkey to **ctrl+`** or **ctrl+j** and restart Writing Tools. PS: If a hotkey is already in use by a program or background process, Writing Tools may not be able to intercept it. The above hotkeys are usually unused.

2. The initial launch of the `Writing Tools.exe` might take unusually long — this seems to be because AV software extensively scans this new executable before letting it run. Once it launches into the background in RAM, it works instantly as usual.

## 👨‍💻 To Run Writing Tools Directly from the Source Code

If you prefer to run the program directly from the `main.py` file, follow these OS-specific instructions.

**1. Download the Code**
- Click the green `<> Code ▼` button toward the very top of this page, and click `Download ZIP`.

**2. Install Dependencies**  
After extracting the folder, open your **Terminal** (or **Command Prompt**) in the relevant directory.

- Windows:
   ```bash
   cd path\to\Windows_and_Linux
   pip install -r requirements.txt
   ```

- Linux:
   ```bash
   cd /path/to/Windows_and_Linux
   pip3 install -r requirements.txt
   ```
Of course, you'll need to have [Python installed](https://www.python.org/downloads/)!

**3. Run the Program**
- **Windows:**
   ```bash
   pythonw main.py
   ```
- **Linux:**
   ```bash
   python3 main.py
   ```

## 👨‍💻 To compile the application yourself:

### Windows and Linux Version build instructions:
Here's how to compile it with PyInstaller and a virtual environment:

1. First, create and activate a virtual environment:
```bash
# Install virtualenv if you haven't already
pip install virtualenv

# Create a new virtual environment
virtualenv myvenv

# Activate it
# On Windows:
myvenv\Scripts\activate
# On Linux:
source myvenv/bin/activate
```

2. Once activated, install the required packages:

```bash
pip install -r requirements.txt
```

3. Build Writing Tools:
```bash
python pyinstaller-build-script.py
```

### macOS Version (by [Aryamirsepasi](https://github.com/Aryamirsepasi)) build instructions:

1. **Install Xcode**
- Ensure you have Xcode installed on your macOS system.
- Download it from the [Mac App Store](https://apps.apple.com/us/app/xcode/id497799835).  

2. **Clone the Repository to your local machine**
```bash
git clone https://github.com/theJayTea/WritingTools.git
cd WritingTools
 ```

3. **Open the Project in Xcode**
- Open Xcode.
- Select **File > Open** from the menu bar.
- Navigate to the `macOS` folder and select it.  

4. **Generate the Project File**
Run the following command to generate the `.xcodeproj` file:
```bash
swift package generate-xcodeproj
```

5. **Build the Project**
- Select your target device as **My Mac** in Xcode.
- Build the project by clicking the **Play** button (or pressing `Command + R`).  

6. **Run the App**
- After the build is successful, the app will launch automatically.


## 🌟 Contributors

Writing Tools would not be where it is today without its amazing contributors:

### Windows & Linux version:
**1. [Cameron Redmore (CameronRedmore)](https://github.com/CameronRedmore):**

Extensively refactored Writing Tools and added OpenAI Compatible API support, streamed responses, and the chat mode when no text is selected.

**2. [momokrono](https://github.com/momokrono):**

Added Linux support and switched to the pynput API to improve Windows stability. Fixed misc. bugs, such as handling quitting onboarding without completing it. @momokrono has been super kind and helpful, and I'm very grateful to have them as a contributor - Jesai.

**3. [Disneyhockey40 (Soszust40)](https://github.com/Disneyhockey40):**

Helped add dark mode, the plain theme, tray menu fixes, and UI improvements.

**4. [Alok Saboo (arsaboo)](https://github.com/arsaboo):**

Helped improve the reliability of text selection.

**5. [raghavdhingra24](https://github.com/raghavdhingra24):**

Made the rounded corners anti-aliased & prettier.

**6. [ErrorCatDev](https://github.com/ErrorCatDev):**

Significantly improved the About window, making it scrollable and cleaning things up. Also improved our .gitignore & requirements.txt.

**7. [Vadim Karpenko](https://github.com/Vadim-Karpenko):**

Helped add the start-on-boot setting!

### macOS version:
#### A native Swift port created entirely by **[Aryamirsepasi](https://github.com/Aryamirsepasi)**! This was a big endeavour and they've done an amazing job. We're grateful to have them as a contributor. 🫡

## 🤝 Contributing

I welcome contributions! :D

If you'd like to improve Writing Tools, please feel free to open a Pull Request or get in touch with me.

If there are major changes on your mind, it may be a good idea to get in touch before working on it.

## 📬 Contact

Email: jesaitarun@gmail.com

Made with ❤️ by a high school student. Check out my other app, [Bliss AI](https://play.google.com/store/apps/details?id=com.jesai.blissai), a free AI tutor!

## 📄 License

Distributed under the GNU General Public License v3.0.
