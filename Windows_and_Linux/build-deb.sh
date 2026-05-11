#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SCRIPT_DIR}/packaging"
STAGE_DIR="${PKG_DIR}/stage"
OUTPUT_DIR="${PKG_DIR}/dist"

DEFAULT_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/Latest_Version_for_Update_Check.txt")"
VERSION="${1:-${DEFAULT_VERSION}}"
ARCH_OVERRIDE="${2:-}"

if [[ -z "${VERSION}" ]]; then
  echo "ERROR: Package version is empty."
  echo "Provide a version as the first argument, e.g. ./build-deb.sh 8"
  exit 1
fi

if ! command -v nfpm >/dev/null 2>&1; then
  echo "ERROR: nfpm is required but was not found in PATH."
  echo "Install: https://nfpm.goreleaser.com/docs/install/"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to build the app binary."
  exit 1
fi

map_arch() {
  local machine
  machine="${1}"

  case "${machine}" in
    x86_64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l)
      echo "arm7"
      ;;
    i686|i386)
      echo "386"
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ -n "${ARCH_OVERRIDE}" ]]; then
  NFPM_ARCH="${ARCH_OVERRIDE}"
else
  if ! NFPM_ARCH="$(map_arch "$(uname -m)")"; then
    echo "ERROR: Unsupported architecture: $(uname -m)"
    echo "Pass nfpm arch manually as second argument (e.g. amd64, arm64)."
    exit 1
  fi
fi

export NFPM_VERSION="${VERSION}"
export NFPM_RELEASE="${NFPM_RELEASE:-1}"
export NFPM_ARCH

echo "[1/4] Building PyInstaller binary"
(
  cd "${SCRIPT_DIR}"
  python3 pyinstaller-build-script.py
)

DIST_EXE="${SCRIPT_DIR}/dist/Writing Tools"
if [[ ! -x "${DIST_EXE}" ]]; then
  echo "ERROR: Expected binary not found: ${DIST_EXE}"
  exit 1
fi

echo "[2/4] Staging package files"
rm -rf "${STAGE_DIR}" "${OUTPUT_DIR}"
mkdir -p \
  "${STAGE_DIR}/usr/bin" \
  "${STAGE_DIR}/usr/lib/writing-tools/payload" \
  "${STAGE_DIR}/usr/share/applications" \
  "${STAGE_DIR}/usr/share/icons/hicolor/256x256/apps" \
  "${OUTPUT_DIR}"

install -m 0755 "${DIST_EXE}" "${STAGE_DIR}/usr/lib/writing-tools/payload/Writing Tools"
install -m 0755 "${SCRIPT_DIR}/install-local-linux.sh" "${STAGE_DIR}/usr/lib/writing-tools/install-local-linux.sh"

cp -a "${SCRIPT_DIR}/icons" "${STAGE_DIR}/usr/lib/writing-tools/payload/icons"
cp -a "${SCRIPT_DIR}/locales" "${STAGE_DIR}/usr/lib/writing-tools/payload/locales"

for file_name in background.png background_dark.png background_popup.png background_popup_dark.png options.json Latest_Version_for_Update_Check.txt; do
  install -m 0644 "${SCRIPT_DIR}/${file_name}" "${STAGE_DIR}/usr/lib/writing-tools/payload/${file_name}"
done

install -m 0644 "${SCRIPT_DIR}/icons/app_icon.png" "${STAGE_DIR}/usr/share/icons/hicolor/256x256/apps/writing-tools.png"

cat > "${STAGE_DIR}/usr/share/applications/writing-tools.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Writing Tools
Comment=AI-powered writing helper with global hotkey popup
Exec=/usr/bin/writing-tools
Icon=writing-tools
Terminal=false
Categories=Office;Utility;
StartupNotify=false
EOF
chmod 0644 "${STAGE_DIR}/usr/share/applications/writing-tools.desktop"

cat > "${STAGE_DIR}/usr/bin/writing-tools" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

INSTALLER="/usr/lib/writing-tools/install-local-linux.sh"
PAYLOAD="/usr/lib/writing-tools/payload"
USER_LAUNCHER="${HOME}/.local/bin/writing-tools"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Please run writing-tools as a regular desktop user, not as root."
  echo "Example: sudo -u <username> writing-tools"
  exit 1
fi

if [[ ! -x "${USER_LAUNCHER}" ]]; then
  if [[ ! -x "${INSTALLER}" ]]; then
    echo "ERROR: Missing installer helper at ${INSTALLER}"
    exit 1
  fi

  if [[ ! -d "${PAYLOAD}" ]]; then
    echo "ERROR: Missing payload directory at ${PAYLOAD}"
    exit 1
  fi

  "${INSTALLER}" --package-mode --app-source "${PAYLOAD}" || true
fi

if [[ -x "${USER_LAUNCHER}" ]]; then
  exec "${USER_LAUNCHER}" "$@"
fi

echo "Writing Tools could not initialize your local profile automatically."
echo "Run this once as your user and try again:"
echo "  /usr/lib/writing-tools/install-local-linux.sh --package-mode --app-source /usr/lib/writing-tools/payload"
exit 1
EOF
chmod 0755 "${STAGE_DIR}/usr/bin/writing-tools"

echo "[3/4] Building .deb package with nfpm"
(
  cd "${SCRIPT_DIR}"
  nfpm pkg --packager deb --config "${PKG_DIR}/nfpm.yaml" --target "${OUTPUT_DIR}/"
)

echo "[4/4] Build completed"
ls -1 "${OUTPUT_DIR}"/*.deb
