# 👨‍💻 To compile the application yourself:

### Windows and Linux Version build instructions:
Here's how to compile it with PyInstaller and a virtual environment:

1. Open Terminal (or Command Prompt) and enter the Windows/Linux app folder:
```bash
cd /path/to/WritingTools/Windows_and_Linux
```

2. Create and activate a virtual environment:
```bash
python3 -m venv .venv

# Linux:
source .venv/bin/activate

# Windows (PowerShell):
.venv\Scripts\Activate.ps1

# Windows (cmd):
.venv\Scripts\activate.bat
```

3. Install dependencies:
```bash
python -m pip install --upgrade pip
pip install -r requirements.txt
```

4. Build Writing Tools:
```bash
python pyinstaller-build-script.py
```

The compiled binary is written to: ~/Windows_and_Linux/dist/Writing Tools

5. Linux only (optional, recommended): install locally with launcher icon:
```bash
bash build-and-install-local-linux.sh
```

This creates:
- `~/.local/bin/writing-tools`
- `~/.local/share/applications/writing-tools.desktop`

Optional autostart:
```bash
bash build-and-install-local-linux.sh --enable-autostart
```

After local install, you can launch Writing Tools with:
```bash
writing-tools
```

No daily recompilation is needed unless you changed source code and want a newer build.

### macOS Version (by [Aryamirsepasi](https://github.com/Aryamirsepasi)) build instructions:

1. **Install Xcode**
   - Download and install Xcode from the App Store
   - Launch Xcode once installed and complete any additional component installations

2. **Clone the Repository**
   - Open Terminal and navigate to the directory where you want to store the project:
   ```bash
   git clone https://github.com/theJayTea/WritingTools.git
   ```

3. **Open in Xcode**
   - Open Xcode
   - Select "Open an existing project..." from the options.
   - Navigate to the macOS folder within the WritingTools directory that you cloned previously, and select "writing-tools.xcodeproj"

4. **Configure Project Settings**
   - In Xcode, select the project in the Navigator pane.
   - Under "Targets", select "writing-tools"
   - Set the following:
     - Deployment Target: macOS 14.0
     - Signing & Capabilities: Add your development team

5. **Build and Run**
   - In Xcode, select "My Mac" as the run destination
   - Click the Play button or press ⌘R to build and run

### [**◀️ Back to main page**](https://github.com/theJayTea/WritingTools)