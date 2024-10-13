# Writing Tools

![Writing Tools Demo](demo.gif)


## 🚀 What is Writing Tools?

Writing Tools is an Apple Intelligence-inspired application for Windows that supercharges your writing with AI. It lets you fix up grammar and more with one  hotkey press, system wide. It's currently the world's most intelligent system-wide grammar assistant.

### 🌟 Why Choose Writing Tools?

- **Smarter AI**: Powered by Google's Gemini 1.5 Flash model, offering superior results compared to on-device models (such as the Apple Intelligence models).
- **System-wide Functionality**: Works instantly in any application where you can select text. Does not overwrite your clipboard. Bloat-free & uses pretty much 0% of your CPU.
- **Completely free and Open-source**: No subscriptions, no hidden costs.
- **Privacy-focused**: Your API key and data stay on YOUR device.
- **User-friendly Interface**: A blurry gradient design that's intuitive and beautiful. But hey, I may be biased, I made it :P
- **Customizable**: Set your own hotkey for quick access.

## ✨ Features

- **Proofread**: Catch and correct grammar and spelling errors.
- **Rewrite**: Rephrase your text for better clarity and impact.
- **Make Friendly/Professional**: Adjust the tone of your writing.
- **Summarize**: Create concise summaries of longer texts.
- **Extract Key Points**: Highlight the most important information.
- **Create Tables**: Convert text data into structured tables.
- **Custom Instructions**: Give specific directions for text modifications.

## 🛠 Installation

1. Go to the [Releases](https://github.com/theJayTea/WritingTools/releases) page and download the latest `Writing Tools for Windows.zip` file.
2. Extract it where you want *(e.g. Program Files > Writing Tools*), run `Writing Tools.exe`, and enjoy! :D
3. To let it automatically start when you boot your PC, add a shortcut of the `Writing Tools.exe` to the Windows Start-Up folder (Open Run and type `shell:startup` to get to this folder). 

## 🔧 Setup

1. Upon first launch, you'll be guided through a quick setup process.
2. You'll need a free Google Gemini API key. The app will provide a link to obtain one.
3. Enter your API key and choose a custom hotkey (default is Ctrl+Space).
4. You can always customise this later and exit the app from its **system tray icon**.

## 🖱 How to Use

1. Select any text in any application.
2. Press your hotkey (default: Ctrl+Space).
3. Choose an option from the popup menu or enter a custom instruction.
4. Watch as your text is magically improved!

## 💡 Tips

- Use "Proofread" for quick grammar and spelling checks. Better than Grammarly premium can ever be :)
- Try "Rewrite" when you want to improve the entire phrasing.
- "Summarize" is great for condensing long articles or documents.
- Experiment with custom instructions for specific writing needs.

## 🔒 Privacy

I believe strongly in protecting your privacy. Writing Tools:
- Only stores your API key locally on your device.
- Only sends text to Google (encrypted) when you *explicitly* use one of the options.
- Does not collect or store any of your writing data. It doesn't even collect general logs, so it's super light and privacy friendly.
- You can explore the source code yourself, and even compile it yourself :D

## 🤝 Contributing

I welcome contributions! If you'd like to improve Writing Tools, feel free to open a Pull Request.

## 👨‍💻 For Advanced Users

If you prefer to run from source:

1. Download the repository
2. Install dependencies (of course, you'll need Python installed!):
   ```
   pip install PySide6 google-generativeai keyboard pyperclip pywin32
   ```
3. Run `python main.py` in your terminal.

To compile the application yourself:

1. Ensure you have Nuitka installed: `pip install nuitka`
2. Run the build script: `python build_script.py`

## 📬 Contact

My email: jesaitarun@gmail.com

Made with ❤️ by a high school student. Check out my other AI app, [Bliss AI](https://play.google.com/store/apps/details?id=com.jesai.blissai), a novel AI tutor free on the Google Play Store!

## 📄 License

Distributed under the MIT License.

---

