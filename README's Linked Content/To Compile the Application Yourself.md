# 👨‍💻 To compile the application yourself:

### Linux build instructions:

1. Open Terminal and enter the Linux app folder:
```bash
cd Windows_and_Linux
```

2. Build and install locally (recommended, creates launcher and app menu entry):
```bash
bash build-and-install-local-linux.sh
```

This creates a virtual environment, installs dependencies, builds with PyInstaller, and installs:
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

#### Linux system dependencies

The Python dependencies (in `requirements.txt`) are installed into the venv automatically. A few **system** packages are needed for the clipboard and keystroke-injection flow; which ones depend on your display server:

**X11 (Xorg) session:**
```bash
# Clipboard backend (one of):
sudo apt install xclip        # Debian/Ubuntu
sudo pacman -S xclip          # Arch/CachyOS
```
pynput (bundled via pip) handles keystroke injection on X11 via the XTest extension — no extra system tool needed.

**Wayland session (e.g. KDE Plasma Wayland, GNOME Wayland, Hyprland):**
pynput's injection and pyperclip's clipboard calls are unreliable on native Wayland. Writing Tools auto-detects a Wayland session and switches to native tools. Install:
```bash
# Arch / CachyOS:
sudo pacman -S wl-clipboard ydotool
# Debian / Ubuntu:
sudo apt install wl-clipboard ydotool
# Fedora:
sudo dnf install wl-clipboard ydotool
```
Then enable the ydotool daemon and grant input access:
```bash
# Enable the daemon (socket-activated; runs per-user)
systemctl --user enable --now ydotool

# Grant /dev/uinput access (required for keystroke injection)
sudo usermod -aG input "$USER"
# Log out and back in for the group change to take effect.
```
- `wl-clipboard` provides `wl-copy`/`wl-paste` for clipboard read/write.
- `ydotool` injects Ctrl+C / Ctrl+V at the kernel uinput layer, reaching both native Wayland and XWayland windows (pynput only reaches XWayland).

Without these tools on Wayland, the app falls back to the X11 path, which only works inside XWayland windows.

### Windows build instructions:
Here's how to compile it with PyInstaller and a virtual environment:

1. Open Command Prompt (or PowerShell) and enter the Windows app folder:
```bash
cd /path/to/WritingTools/Windows_and_Linux
```

2. Create and activate a virtual environment:
```bash
python -m venv .venv

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