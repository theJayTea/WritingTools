#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENABLE_AUTOSTART=""
PACKAGE_MODE="no"
TARGET_USER="${SUDO_USER:-${USER:-}}"
APP_SOURCE=""

TARGET_HOME=""
TARGET_UID=""
TARGET_GID=""
DIST_EXE=""

DATA_HOME=""
CONFIG_HOME=""
INSTALL_ROOT=""
APP_DIR=""
BIN_DIR=""
APPS_DIR=""
AUTOSTART_DIR=""

LAUNCHER_PATH=""
DESKTOP_PATH=""
AUTOSTART_PATH=""

print_usage() {
  cat <<'USAGE'
Usage:
  ./install-local-linux.sh [--enable-autostart|--disable-autostart]
  ./install-local-linux.sh --package-mode --target-user <user> --app-source <dir> [--enable-autostart|--disable-autostart]

Installs the compiled Writing Tools app for one Linux user:
- App files: ~/.local/share/writingtools/app
- Launcher command: ~/.local/bin/writing-tools
- App menu entry: ~/.local/share/applications/writing-tools.desktop

Options:
  --enable-autostart   Create ~/.config/autostart/writing-tools.desktop
  --disable-autostart  Remove ~/.config/autostart/writing-tools.desktop
  --package-mode       Enable package-managed behavior (skip local vendoring)
  --target-user <user> Target Linux username for provisioning (required when run as root in package mode)
  --app-source <dir>   Directory containing app payload files. If omitted, defaults to this script directory
  -h, --help           Show this help message
USAGE
}

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

resolve_target_user() {
  local current_uid
  current_uid="$(id -u)"

  if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
    local login_user
    login_user="$(logname 2>/dev/null || true)"
    if [[ -n "${login_user}" && "${login_user}" != "root" ]]; then
      TARGET_USER="${login_user}"
    fi
  fi

  if [[ "${current_uid}" -eq 0 ]]; then
    if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
      echo "ERROR: Could not determine a non-root target user."
      echo "       Re-run with: --target-user <linux-username>"
      exit 1
    fi

    TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
    if [[ -z "${TARGET_HOME}" ]]; then
      echo "ERROR: User '${TARGET_USER}' was not found on this system."
      exit 1
    fi

    TARGET_UID="$(id -u "${TARGET_USER}")"
    TARGET_GID="$(id -g "${TARGET_USER}")"

    DATA_HOME="${TARGET_HOME}/.local/share"
    CONFIG_HOME="${TARGET_HOME}/.config"
  else
    if [[ -n "${TARGET_USER}" && "${TARGET_USER}" != "${USER}" ]]; then
      echo "ERROR: --target-user only supports the current user when not running as root."
      exit 1
    fi

    TARGET_USER="${USER}"
    TARGET_HOME="${HOME}"
    TARGET_UID="$(id -u)"
    TARGET_GID="$(id -g)"

    DATA_HOME="${XDG_DATA_HOME:-${TARGET_HOME}/.local/share}"
    CONFIG_HOME="${XDG_CONFIG_HOME:-${TARGET_HOME}/.config}"
  fi

  INSTALL_ROOT="${DATA_HOME}/writingtools"
  APP_DIR="${INSTALL_ROOT}/app"
  BIN_DIR="${TARGET_HOME}/.local/bin"
  APPS_DIR="${DATA_HOME}/applications"
  AUTOSTART_DIR="${CONFIG_HOME}/autostart"

  LAUNCHER_PATH="${BIN_DIR}/writing-tools"
  DESKTOP_PATH="${APPS_DIR}/writing-tools.desktop"
  AUTOSTART_PATH="${AUTOSTART_DIR}/writing-tools.desktop"
}

resolve_app_source() {
  APP_SOURCE="${APP_SOURCE:-${SCRIPT_DIR}}"

  if [[ ! -d "${APP_SOURCE}" ]]; then
    echo "ERROR: App source directory not found: ${APP_SOURCE}"
    exit 1
  fi

  if [[ -x "${APP_SOURCE}/Writing Tools" ]]; then
    DIST_EXE="${APP_SOURCE}/Writing Tools"
  elif [[ -x "${APP_SOURCE}/dist/Writing Tools" ]]; then
    DIST_EXE="${APP_SOURCE}/dist/Writing Tools"
  else
    echo "ERROR: Compiled binary not found under app source: ${APP_SOURCE}"
    if [[ "${APP_SOURCE}" == "${SCRIPT_DIR}" ]]; then
      echo "Build first with: python3 pyinstaller-build-script.py"
    fi
    exit 1
  fi

  for required_dir in icons locales; do
    if [[ ! -d "${APP_SOURCE}/${required_dir}" ]]; then
      echo "ERROR: Missing required directory in app source: ${APP_SOURCE}/${required_dir}"
      exit 1
    fi
  done

  for required_file in background.png background_dark.png background_popup.png background_popup_dark.png Latest_Version_for_Update_Check.txt options.json; do
    if [[ ! -f "${APP_SOURCE}/${required_file}" ]]; then
      echo "ERROR: Missing required file in app source: ${APP_SOURCE}/${required_file}"
      exit 1
    fi
  done
}

chown_paths_if_needed() {
  if [[ "$(id -u)" -ne 0 ]]; then
    return 0
  fi

  for path in "${INSTALL_ROOT}" "${BIN_DIR}" "${APPS_DIR}" "${AUTOSTART_DIR}"; do
    if [[ -e "${path}" ]]; then
      chown -R "${TARGET_UID}:${TARGET_GID}" "${path}"
    fi
  done

  for file_path in "${LAUNCHER_PATH}" "${DESKTOP_PATH}" "${AUTOSTART_PATH}"; do
    if [[ -e "${file_path}" ]]; then
      chown "${TARGET_UID}:${TARGET_GID}" "${file_path}"
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enable-autostart)
      ENABLE_AUTOSTART="yes"
      ;;
    --disable-autostart)
      ENABLE_AUTOSTART="no"
      ;;
    --package-mode)
      PACKAGE_MODE="yes"
      ;;
    --target-user)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --target-user requires a value"
        exit 1
      fi
      TARGET_USER="$1"
      ;;
    --app-source)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --app-source requires a value"
        exit 1
      fi
      APP_SOURCE="$1"
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

resolve_target_user
resolve_app_source

mkdir -p "${APP_DIR}" "${BIN_DIR}" "${APPS_DIR}" "${AUTOSTART_DIR}"

install -m 0755 "${DIST_EXE}" "${APP_DIR}/Writing Tools"

# Runtime assets expected by current app code next to sys.argv[0].
rm -rf "${APP_DIR}/icons" "${APP_DIR}/locales"
cp -a "${APP_SOURCE}/icons" "${APP_DIR}/icons"
cp -a "${APP_SOURCE}/locales" "${APP_DIR}/locales"

for file_name in background.png background_dark.png background_popup.png background_popup_dark.png Latest_Version_for_Update_Check.txt; do
  install -m 0644 "${APP_SOURCE}/${file_name}" "${APP_DIR}/${file_name}"
done

# Preserve user's customized options if already present.
if [[ ! -f "${APP_DIR}/options.json" ]]; then
  install -m 0644 "${APP_SOURCE}/options.json" "${APP_DIR}/options.json"
fi

if [[ "${PACKAGE_MODE}" != "yes" ]]; then
  ensure_local_libxcb_cursor || true
  ensure_local_xclip || true
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

chown_paths_if_needed

echo "Install complete for user: ${TARGET_USER}"
echo "Launcher command: writing-tools"
echo "Desktop entry: ${DESKTOP_PATH}"

if ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1 && ! command -v wl-copy >/dev/null 2>&1; then
  if [[ "${PACKAGE_MODE}" == "yes" ]]; then
    echo "WARNING: No clipboard backend detected (xclip/xsel/wl-copy)."
    echo "         Install one with your package manager so copy/replace works."
  elif [[ -x "${APP_DIR}/bin/xclip" ]]; then
    echo "Clipboard backend provided via local xclip binary."
  else
    echo "WARNING: No clipboard backend detected for pyperclip (xclip/xsel/wl-copy)."
    echo "         Install one to ensure copy/replace flow works."
  fi
fi

if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  echo "NOTICE: Running in Wayland session; global hotkey/focus behavior may be limited."
fi
