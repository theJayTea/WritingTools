# 👨‍💻 To Run Writing Tools Directly from the Source Code

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
   python main.py
   # Tip: If you want Writing Tools to remain running even after you close your Terminal window, run `pythonw main.py` instead of `python main.py`.

   ```

- **Linux:**
   ```bash
   python3 main.py
   ```

### Linux on Wayland (KDE Plasma, GNOME, Sway, Hyprland…)

Writing Tools detects a Wayland session and switches to native Wayland support.
X11 sessions keep working exactly as before.

**Extra packages.** Install `wl-clipboard` plus a way to send key presses:
- `ydotool` works on every compositor. Its `ydotoold` service must be running,
  and your user needs access to `/dev/uinput` (usually the `input` group).
- `wtype` is enough on Sway, Hyprland and other wlroots compositors.

On Fedora: `sudo dnf install wl-clipboard ydotool`. On Debian/Ubuntu:
`sudo apt install wl-clipboard ydotool`.

**The global shortcut.** On desktops with the global shortcuts portal (KDE Plasma
5.27+, GNOME 48+, Hyprland), Writing Tools registers its shortcut there. The first
time, your desktop asks you to confirm it. You can change it later in your desktop's
keyboard shortcut settings, where it is listed under "Writing Tools".

On desktops without the portal, add a custom shortcut in your desktop settings that
runs:
```bash
python3 /path/to/Windows_and_Linux/main.py --trigger
```
`--trigger Proofread` (or any other button name) runs that button directly.

**Options** (environment variables):
- `WRITING_TOOLS_FORCE_X11=1`: use the X11 code path (only reaches XWayland apps).
- `WRITING_TOOLS_DISABLE_PORTAL=1`: don't register portal shortcuts; use `--trigger`.
- `WRITING_TOOLS_KEY_INJECTOR`: `ydotool`, `wtype`, or the path to your own
  executable, which receives `copy` or `paste` as its only argument.

**Tests:** `cd Windows_and_Linux && python3 -m unittest discover -s tests -t .`


### [**◀️ Back to main page**](https://github.com/theJayTea/WritingTools)
