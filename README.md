# Writing Tools

https://github.com/user-attachments/assets/0dd14cee-8307-4714-99f0-631fb6de1510

## 🚀 What is Writing Tools?

Writing Tools is an Apple Intelligence-inspired application for Windows that supercharges your writing with AI. It lets you fix up grammar and more with one  hotkey press, system wide. It's currently the world's most intelligent system-wide grammar assistant.

### 🌟 Why Choose Writing Tools?

Aside from being the only Windows program that works like Apple's Writing Tools:

- **Smarter AI**: Powered by Google's Gemini 1.5 Flash model, offering superior results compared to on-device models (such as the Apple Intelligence models).
- **System-wide Functionality**: Works instantly in any application where you can select text. Does not overwrite or mess with your clipboard. Bloat-free & uses pretty much 0% of your CPU.
- **Completely free and Open-source**: No subscriptions, no hidden costs.
- **Privacy-focused**: Your API key and config files stay on *your* device. NO logging, diagnostic collection, tracking, or ads. Invoked *only* on your command.
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

## 🖱 How to Use

1. Select any text in any application.
2. Press your hotkey (default: Ctrl+Space).
3. Choose an option from the popup menu or enter a custom instruction.
4. Watch as your text is magically improved!

## 🛠 Installation

1. Go to the [Releases](https://github.com/theJayTea/WritingTools/releases) page and download the latest `Writing_Tools.zip` file.
   
2. Extract it where you want, run `Writing Tools.exe`, and enjoy! :D
   
   (Note: If you extract Writing Tools into a protected system folder like Program Files, you'll need to run it as administrator on the first launch or it won't be able to create its config file in the same folder as the exe)
   
3. To let it automatically start when you boot your PC, add a shortcut of the `Writing Tools.exe` to the Windows Start-Up folder (Open Run and type `shell:startup` to get to this folder). 

## A Quick Note on Antivirus Detections

It turns out that some antivirus providers flag the compiled exe (on the releases page) as malware.

![image](https://github.com/user-attachments/assets/ee2260d2-cfb6-4823-881a-c560186185d1)

The Python to exe compiler I used is Nuitka, which is why it's getting flagged — it's a known issue.
It happens to obfuscate/minify the exe (to make it optimized and small as it works with its C compiler), making it look suspicious.

**In fact, the `main.py` file itself is safe to AVs ([here's its VirusTotal result](https://www.virustotal.com/gui/file/cc08cf4ffd25273f4248bb1747cf64189b623fd952a2df196a2707297d149231?nocache=1)) since the code isn't obfuscated with Nuitka's exe.**

If you're interested, feel free to explore the source code file yourself; it's well-documented. Writing Tools also never requires elevation ("Run as administrator").

You could easily run it directly from `main.py` with the instructions below :)

## 👨‍💻 To run Writing Tools directly from the code

If you prefer to run it directly from the `main.py` file:

1. Download the code by clicking this button above:
   ![image](https://github.com/user-attachments/assets/4c6cab79-4918-451c-9ad1-1bbcf8472275)

2. You'll only have to do this once: [Install Python](https://www.python.org/downloads/) if you don't already have it installed. Then, open the terminal, and type the below line to install the dependencies:
   ```
   pip install PySide6 google-generativeai keyboard pyperclip pywin32
   ```
   
3. Any time you want to run the program, just right-click the folder of the code you downloaded, click Open in Terminal, and type `python main.py` in your terminal. That's it! 🎉

## 🐞 Known Issues
On some devices, the hotkey detection sometimes acts up or does not work correctly.

To fix it, just restart Writing Tools (you can close it by right-clicking its taskbar tray icon and clicking Exit, or with Task Manager).

This issue is being investigated — it seems to be due to an unreliable hotkey detection API.


## 👨‍💻 To compile the application yourself:

The following are instructions on how to compile it with Nuitka. While it results in the most optimised (size-wise) exe from a Python file, a known issue is that it'll get flagged by antivirus software. Feel free to use any other exe compiler too such as PyInstaller.

1. Ensure you have Nuitka installed: `pip install nuitka`
2. Run the build script: `python build_script.py`

## 🔒 Privacy

I believe strongly in protecting your privacy. Writing Tools:
- Only stores your API key locally on your device.
- Does not collect or store any of your writing data by itself. It doesn't even collect general logs, so it's super light and privacy-friendly.
- Only sends text to Google (encrypted) when you *explicitly* use one of the options. If you have a paid API key, the text will never be used to train Gemini, but if you don't, Google may anonymise your text and use it to train their models.
- You can explore the source code yourself, and even compile it yourself :D

## 💡 Tips

- Use "Proofread" for quick grammar and spelling checks. Better than Grammarly premium can ever be :)
- Try "Rewrite" when you want to improve the entire phrasing.
- "Summarize" is great for condensing long articles or documents.
- Experiment with custom instructions for specific writing needs.

## 🤝 Contributing

I welcome contributions! If you'd like to improve Writing Tools, feel free to open a Pull Request.

## 📬 Contact

My email: jesaitarun@gmail.com

Made with ❤️ by a high school student. Check out my other AI app, [Bliss AI](https://play.google.com/store/apps/details?id=com.jesai.blissai), a novel AI tutor free on the Google Play Store!

## 📄 License

Distributed under the GNU General Public License v3.0.

---

