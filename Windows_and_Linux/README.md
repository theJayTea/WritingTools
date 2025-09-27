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
sudo apt install wl-clipboard wlrctl kwin jq
```

#### Fedora/CentOS/RHEL
```bash
sudo dnf install wl-clipboard wlrctl kwin jq
```

#### Arch/Manjaro
```bash
sudo pacman -S wl-clipboard wlrctl kwin jq
```

#### openSUSE
```bash
sudo zypper install wl-clipboard wlrctl kwin jq
```

### GNOME Shell Extension Setup

For GNOME users, install the "Activate Window By Title" extension:

1. Go to https://extensions.gnome.org/extension/5021/activate-window-by-title/
2. Enable the extension
3. The extension will expose window information via D-Bus
