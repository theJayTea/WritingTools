# Writing Tools for macOS

This is a new, **native macOS port of Writing Tools**, created entirely by @Aryamirsepasi 🎉

Core functionality works well, and it is still an ongoing work in progress.

---

## Working Features
- All of the tools, including the new response windows and the manual chat option.
- Gemini Support.
- Initial Setup, Settings, and About pages.

---

## Not Yet Available
- OpenAI and Local LLM Integration.
- The Gradient Theme (Dark Mode and Light Mode are supported).
- More refined positioning logic for the popup window to follow the cursor correctly.

---

## System Requirements
Due to the accessibility features the app uses (e.g., automatically selecting the window containing the text and pasting the updated version), **the minimum macOS version required is 14.0**.

---

## How to Build This Project

Since the `.xcodeproj` file is excluded, you can still build the project manually by following these steps:

1. **Install Xcode**
   - Ensure you have Xcode installed on your macOS system.
   - Download it from the [Mac App Store](https://apps.apple.com/us/app/xcode/id497799835).

2. **Clone the Repository**
   - Clone this repository to your local machine:
     ```bash
     git clone https://github.com/Aryamirsepasi/writing-tools-mac.git
     cd writing-tools-mac
     ```

3. **Open the Project in Xcode**
   - Open Xcode.
   - Select **File > Open** from the menu bar.
   - Navigate to the `macOS` folder and select it.

4. **Generate the Project File**
   - Run the following command to generate the `.xcodeproj` file:
     ```bash
     swift package generate-xcodeproj
     ```

5. **Build the Project**
   - Select your target device as **My Mac** in Xcode.
   - Build the project by clicking the **Play** button (or pressing `Command + R`).

6. **Run the App**
   - After the build is successful, the app will launch automatically.

---

## Credits

The macOS port is being developed by **Aryamirsepasi**.

GitHub: [https://github.com/Aryamirsepasi](https://github.com/Aryamirsepasi)