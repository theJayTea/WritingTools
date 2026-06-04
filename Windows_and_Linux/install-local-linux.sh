#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SOURCE="${SCRIPT_DIR}"
ENABLE_AUTOSTART=""

print_usage() {
  cat <<'USAGE'
Usage:
  bash install-local-linux.sh [--app-source <dir>] [--enable-autostart|--disable-autostart]

Installs Writing Tools for the current Linux user:
- App files: ~/.local/share/writingtools/app
- Launcher command: ~/.local/bin/writing-tools
- App menu entry: ~/.local/share/applications/writing-tools.desktop

Options:
  --app-source <dir>   Source directory containing app assets and dist output
  --enable-autostart   Create ~/.config/autostart/writing-tools.desktop
  --disable-autostart  Remove ~/.config/autostart/writing-tools.desktop
  -h, --help           Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-source)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --app-source requires a value"
        exit 1
      fi
      APP_SOURCE="$1"
      ;;
    --enable-autostart)
      ENABLE_AUTOSTART="yes"
      ;;
    --disable-autostart)
      ENABLE_AUTOSTART="no"
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      print_usage
      exit 1
      ;;
  esac
  shift
done

if [[ "${EUID}" -eq 0 ]]; then
  echo "ERROR: Please run this as your regular desktop user, not root."
  exit 1
fi

if [[ ! -d "${APP_SOURCE}" ]]; then
  echo "ERROR: App source directory not found: ${APP_SOURCE}"
  exit 1
fi

DIST_EXE=""
if [[ -x "${APP_SOURCE}/Writing Tools" ]]; then
  DIST_EXE="${APP_SOURCE}/Writing Tools"
elif [[ -x "${APP_SOURCE}/dist/Writing Tools" ]]; then
  DIST_EXE="${APP_SOURCE}/dist/Writing Tools"
else
  echo "ERROR: Compiled binary not found in ${APP_SOURCE}"
  echo "Build first with: python3 pyinstaller-build-script.py"
  exit 1
fi

for required_dir in icons locales; do
  if [[ ! -d "${APP_SOURCE}/${required_dir}" ]]; then
    echo "ERROR: Missing required directory: ${APP_SOURCE}/${required_dir}"
    exit 1
  fi
done

for required_file in background.png background_dark.png background_popup.png background_popup_dark.png Latest_Version_for_Update_Check.txt options.json; do
  if [[ ! -f "${APP_SOURCE}/${required_file}" ]]; then
    echo "ERROR: Missing required file: ${APP_SOURCE}/${required_file}"
    exit 1
  fi
done

DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
INSTALL_ROOT="${DATA_HOME}/writingtools"
APP_DIR="${INSTALL_ROOT}/app"
BIN_DIR="${HOME}/.local/bin"
APPS_DIR="${DATA_HOME}/applications"
AUTOSTART_DIR="${CONFIG_HOME}/autostart"
LAUNCHER_PATH="${BIN_DIR}/writing-tools"
DESKTOP_PATH="${APPS_DIR}/writing-tools.desktop"
AUTOSTART_PATH="${AUTOSTART_DIR}/writing-tools.desktop"

mkdir -p "${APP_DIR}" "${BIN_DIR}" "${APPS_DIR}" "${AUTOSTART_DIR}"

install -m 0755 "${DIST_EXE}" "${APP_DIR}/Writing Tools"

rm -rf "${APP_DIR}/icons" "${APP_DIR}/locales"
cp -a "${APP_SOURCE}/icons" "${APP_DIR}/icons"
cp -a "${APP_SOURCE}/locales" "${APP_DIR}/locales"

for file_name in background.png background_dark.png background_popup.png background_popup_dark.png Latest_Version_for_Update_Check.txt; do
  install -m 0644 "${APP_SOURCE}/${file_name}" "${APP_DIR}/${file_name}"
done

# Preserve user-customized options on upgrades.
if [[ ! -f "${APP_DIR}/options.json" ]]; then
  install -m 0644 "${APP_SOURCE}/options.json" "${APP_DIR}/options.json"
fi

cat > "${LAUNCHER_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/writingtools/app"
if [[ -d "${APP_DIR}/lib" ]]; then
  export LD_LIBRARY_PATH="${APP_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
if [[ -d "${APP_DIR}/bin" ]]; then
  export PATH="${APP_DIR}/bin:${PATH}"
fi
cd "${APP_DIR}"
exec "${APP_DIR}/Writing Tools" "$@"
EOF
chmod 0755 "${LAUNCHER_PATH}"

cat > "${DESKTOP_PATH}" <<EOF
[Desktop Entry]
Type=Application
Name=Writing Tools
Comment=AI-powered writing helper with global hotkey popup
Exec=${LAUNCHER_PATH}
Icon=${APP_DIR}/icons/app_icon.png
Terminal=false
Categories=Office;Utility;
StartupNotify=false
EOF
chmod 0644 "${DESKTOP_PATH}"

if [[ "${ENABLE_AUTOSTART}" == "yes" ]]; then
  cat > "${AUTOSTART_PATH}" <<EOF
[Desktop Entry]
Type=Application
Name=Writing Tools
Comment=Start Writing Tools in background at login
Exec=${LAUNCHER_PATH}
Icon=${APP_DIR}/icons/app_icon.png
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  chmod 0644 "${AUTOSTART_PATH}"
  echo "Autostart enabled at: ${AUTOSTART_PATH}"
elif [[ "${ENABLE_AUTOSTART}" == "no" ]]; then
  rm -f "${AUTOSTART_PATH}"
  echo "Autostart disabled."
fi

echo "Install complete for user: ${USER}"
echo "Launcher command: writing-tools"
echo "Desktop entry: ${DESKTOP_PATH}"

if ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1 && ! command -v wl-copy >/dev/null 2>&1; then
  echo "WARNING: No clipboard backend detected (xclip/xsel/wl-copy)."
  echo "         Install one to ensure copy/replace flow works."
fi

if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  echo "NOTICE: Running in Wayland session; global hotkey/focus behavior may be limited."
fi
