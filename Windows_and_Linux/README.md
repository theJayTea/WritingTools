## ⚠ refer to main readme: still experimental ⚠

## Linux

### X11
- Captures text via synthetic Ctrl+C using `pynput` + `pyperclip`.

### Wayland
- Captures text via `wl-paste --primary` (requires `wl-clipboard`).
- Retrieves active window title from:
  1. **wlroots-based** (Sway, Hyprland, Labwc): `wlrctl toplevel list --json`
  2. **KDE Plasma**: `kwin5 activewindow` + `kwin5 windowtitle <ID>`
  3. **GNOME (Mutter)**: GNOME Shell Extension "Activate Window By Title"
  4. **Fallback**: `"<Wayland>"` placeholder

### Installing System Dependencies

#### Debian/Ubuntu
```bash
sudo apt update
sudo apt install wl-clipboard wlrctl kwin jq ydotool
```

#### Fedora/CentOS/RHEL
```bash
sudo dnf install wl-clipboard wlrctl kwin jq ydotool
```

#### Arch/Manjaro
```bash
sudo pacman -S wl-clipboard wlrctl kwin jq ydotool
```

#### openSUSE
```bash
sudo zypper install wl-clipboard wlrctl kwin jq ydotool
```

### ydotool Service Setup

**Note:** ydotool requires a running daemon service. The default installation creates a user service that may not work properly. Here's how to set it up correctly:

1. Move the service file from user to system location:
```bash
sudo mv /usr/lib/systemd/user/ydotool.service /usr/lib/systemd/system/ydotool.service
```

2. Edit the service file to use the correct socket path and permissions:
```bash
sudo nano /usr/lib/systemd/system/ydotool.service
```

Use this configuration (replace `1000:1000` with your actual user/group IDs from `echo "$(id -u):$(id -g)"`):

```ini
[Unit]
Description=Starts ydotoold service

[Service]
Type=simple
Restart=always
ExecStart=/usr/bin/ydotoold --socket-path="/run/user/1000/.ydotool_socket" --socket-own="1000:1000"
ExecReload=/usr/bin/kill -HUP $MAINPID
KillMode=process
TimeoutSec=180

[Install]
WantedBy=default.target
```

3. Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable ydotool.service
sudo systemctl start ydotool.service
```

4. Test that ydotool is working:
```bash
ydotool type "hello"
```

**Alternative approach:** Instead of moving the service file, you can also copy it:
```bash
sudo cp /usr/lib/systemd/user/ydotool.service /etc/systemd/system/ydotool.service
```

**Troubleshooting:** If you still have permission issues, you may need to add your user to the appropriate group or make the socket readable by all users.

### GNOME Shell Extension Setup

For GNOME users, install the "Activate Window By Title" extension:

1. Go to https://extensions.gnome.org/extension/5021/activate-window-by-title/
2. Enable the extension
3. The extension will expose window information via D-Bus
