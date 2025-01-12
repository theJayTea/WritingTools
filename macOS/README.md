# Writing Tools for macOS

This is a new, **native macOS port of Writing Tools**, created entirely by @Aryamirsepasi 🎉

Core functionality works well, and it is still an ongoing work in progress.

---

## Working Features
- All of the tools, including the new response windows and the manual chat option.
- Input Window even when no text is selected
- Gemini, OpenAI and Local LLM Support.
- The Gradient Theme (Dark Mode and Light Mode are supported).
- Initial Setup, Settings, and About pages.

---

## Not Yet Available
- All of the original port's features are now available; however, more optimizations and improvements are coming soon.

---

## System Requirements
Due to the accessibility features the app uses (e.g., automatically selecting the window containing the text and pasting the updated version), **the minimum macOS version required is 14.0**.

---

## How to Build This Project

Since the `.xcodeproj` file is excluded, you can still build the project manually by following these steps:
This guide will help you properly set up the Writing Tools macOS project in Xcode.

## System Requirements
- macOS 14.0 or later
- Xcode 15.0 or later
- Git

## Manual Build Steps

1. **Install Xcode**
   - Download and install Xcode from the App Store
   - Launch Xcode once installed and complete any additional component installations

2. **Clone the Repository**
   - Open Terminal and navigate to a directory you want the project to be in:
   ```bash
   git clone https://github.com/theJayTea/WritingTools.git
   cd WritingTools
   ```

3. **Create Xcode Project**
   - Navigate to the project's macOS directory:
     ```bash
     cd macOS
     ```
   - Create a new Xcode project:
     ```bash
     xcodebuild -project writing-tools.xcodeproj
     ```

4. **Open in Xcode**
   - Double-click the generated `writing-tools.xcodeproj` file
   - Or open Xcode and select "Open a Project or File"
   - Navigate to the `WritingTools/macOS/writing-tools.xcodeproj` file

5. **Configure Project Settings**
   - In Xcode, select the project in the navigator
   - Under "Targets", select "writing-tools"
   - Set the following:
     - Deployment Target: macOS 14.0
     - Signing & Capabilities: Add your development team

6. **Install Dependencies**
   - In Terminal, run:
     ```bash
     cd macOS
     swift package resolve
     ```

7. **Build and Run**
   - In Xcode, select "My Mac" as the run destination
   - Click the Play button or press ⌘R to build and run

## Troubleshooting

If you encounter the "Could not open file" error:
1. Ensure you're opening the `.xcodeproj` file, not the folder
2. If the error persists, try:
   ```bash
   cd WritingTools/macOS
   rm -rf writing-tools.xcodeproj
   xcodebuild -project writing-tools.xcodeproj
   ```

## Additional Notes
- The project requires macOS 14.0+ due to accessibility features
- Make sure all required permissions are granted when first launching the app
- For development, ensure you have the latest Xcode Command Line Tools installed

---

## Credits

The macOS port is being developed by **Aryamirsepasi**.

GitHub: [https://github.com/Aryamirsepasi](https://github.com/Aryamirsepasi)

Special Thanks to @sindresorhus for developing an amazing and stable keyboard shortcuts package for Swift. 

GitHub: [https://github.com/sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)