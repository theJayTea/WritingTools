#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_EXE="${SCRIPT_DIR}/dist/Writing Tools"

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

ENABLE_AUTOSTART=""

download_deb() {
  local package_name="$1"
  local download_dir="$2"

  if ! command -v apt >/dev/null 2>&1; then
    return 1
  fi

  (
    cd "${download_dir}"
    apt download "${package_name}" >/dev/null 2>&1
  )
}

ensure_local_libxcb_cursor() {
  if ldconfig -p 2>/dev/null | grep -q 'libxcb-cursor.so.0'; then
    return 0
  fi

  if [[ -e "${APP_DIR}/lib/libxcb-cursor.so.0" ]]; then
    return 0
  fi

  if [[ -f "${APP_DIR}/lib/libxcb-cursor.so.0.0.0" ]]; then
    ln -s "libxcb-cursor.so.0.0.0" "${APP_DIR}/lib/libxcb-cursor.so.0"
    return 0
  fi

  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "WARNING: dpkg-deb not found; cannot vendor libxcb-cursor0 locally."
    return 1
  fi

  local temp_dir
  temp_dir="$(mktemp -d)"

  if ! download_deb "libxcb-cursor0" "${temp_dir}"; then
    echo "WARNING: Could not download libxcb-cursor0 package."
    rm -rf "${temp_dir}"
    return 1
  fi

  local deb_file
  deb_file="$(ls "${temp_dir}"/libxcb-cursor0_*.deb 2>/dev/null | head -n 1 || true)"
  if [[ -z "${deb_file}" ]]; then
    echo "WARNING: libxcb-cursor0 package download did not produce a .deb file."
    rm -rf "${temp_dir}"
    return 1
  fi

  dpkg-deb -x "${deb_file}" "${temp_dir}/pkg"
  mkdir -p "${APP_DIR}/lib"
  find "${temp_dir}/pkg" -type f -name 'libxcb-cursor.so.0*' -exec cp -a {} "${APP_DIR}/lib/" \;

  if [[ -f "${APP_DIR}/lib/libxcb-cursor.so.0.0.0" && ! -e "${APP_DIR}/lib/libxcb-cursor.so.0" ]]; then
    ln -s "libxcb-cursor.so.0.0.0" "${APP_DIR}/lib/libxcb-cursor.so.0"
  fi

  rm -rf "${temp_dir}"
  return 0
}

ensure_local_xclip() {
  if command -v xclip >/dev/null 2>&1; then
    return 0
  fi

  if [[ -x "${APP_DIR}/bin/xclip" ]]; then
    return 0
  fi

  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "WARNING: dpkg-deb not found; cannot vendor xclip locally."
    return 1
  fi

  local temp_dir
  temp_dir="$(mktemp -d)"

  if ! download_deb "xclip" "${temp_dir}"; then
    echo "WARNING: Could not download xclip package."
    rm -rf "${temp_dir}"
    return 1
  fi

  local deb_file
  deb_file="$(ls "${temp_dir}"/xclip_*.deb 2>/dev/null | head -n 1 || true)"
  if [[ -z "${deb_file}" ]]; then
    echo "WARNING: xclip package download did not produce a .deb file."
    rm -rf "${temp_dir}"
    return 1
  fi

  dpkg-deb -x "${deb_file}" "${temp_dir}/pkg"
  mkdir -p "${APP_DIR}/bin"

  if [[ -x "${temp_dir}/pkg/usr/bin/xclip" ]]; then
    install -m 0755 "${temp_dir}/pkg/usr/bin/xclip" "${APP_DIR}/bin/xclip"
  fi

  rm -rf "${temp_dir}"
  return 0
}

print_usage() {
  cat <<'EOF'
Usage: ./install-local-linux.sh [--enable-autostart|--disable-autostart]

Installs the compiled Writing Tools app for the current user:
- App files: ~/.local/share/writingtools/app
- Launcher command: ~/.local/bin/writing-tools
- App menu entry: ~/.local/share/applications/writing-tools.desktop

Optional flags:
  --enable-autostart   Create ~/.config/autostart/writing-tools.desktop
  --disable-autostart  Remove ~/.config/autostart/writing-tools.desktop
EOF
}

if [[ $# -gt 1 ]]; then
  print_usage
  exit 1
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --enable-autostart)
      ENABLE_AUTOSTART="yes"
      ;;
    --disable-autostart)
      ENABLE_AUTOSTART="no"
      ;;
    *)
      print_usage
      exit 1
      ;;
  esac
fi

if [[ ! -x "${DIST_EXE}" ]]; then
  echo "ERROR: Compiled binary not found at: ${DIST_EXE}"
  echo "Build first with: python3 pyinstaller-build-script.py"
  exit 1
fi

mkdir -p "${APP_DIR}" "${BIN_DIR}" "${APPS_DIR}" "${AUTOSTART_DIR}"

install -m 0755 "${DIST_EXE}" "${APP_DIR}/Writing Tools"

# Runtime assets expected by current app code next to sys.argv[0].
rm -rf "${APP_DIR}/icons" "${APP_DIR}/locales"
cp -a "${SCRIPT_DIR}/icons" "${APP_DIR}/icons"
cp -a "${SCRIPT_DIR}/locales" "${APP_DIR}/locales"

for file_name in background.png background_dark.png background_popup.png background_popup_dark.png Latest_Version_for_Update_Check.txt; do
  install -m 0644 "${SCRIPT_DIR}/${file_name}" "${APP_DIR}/${file_name}"
done

# Preserve user's customized options if already present.
if [[ ! -f "${APP_DIR}/options.json" ]]; then
  install -m 0644 "${SCRIPT_DIR}/options.json" "${APP_DIR}/options.json"
fi

ensure_local_libxcb_cursor || true
ensure_local_xclip || true

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

echo "Install complete."
echo "Launcher command: writing-tools"
echo "Desktop entry: ${DESKTOP_PATH}"

if ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1 && ! command -v wl-copy >/dev/null 2>&1; then
  if [[ -x "${APP_DIR}/bin/xclip" ]]; then
    echo "Clipboard backend provided via local xclip binary."
  else
    echo "WARNING: No clipboard backend detected for pyperclip (xclip/xsel/wl-copy)."
    echo "         Install one to ensure copy/replace flow works."
  fi
fi

if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  echo "NOTICE: Running in Wayland session; global hotkey/focus behavior may be limited."
fi
