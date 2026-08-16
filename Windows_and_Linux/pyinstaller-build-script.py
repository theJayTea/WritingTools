import shutil
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent
DIST_DIR = ROOT_DIR / 'dist'
BUILD_DIR = ROOT_DIR / 'build'
PYCACHE_DIR = ROOT_DIR / '__pycache__'


def remove_path(path: Path):
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def require_path(path: Path, description: str):
    if not path.exists():
        print(f"ERROR: Missing {description}: {path}")
        sys.exit(1)


def run_preflight_checks():
    require_path(ROOT_DIR / 'main.py', 'entrypoint file')
    require_path(ROOT_DIR / 'icons' / 'app_icon.ico', 'application icon')

    if shutil.which('pyinstaller') is None:
        print('ERROR: pyinstaller is not available in PATH.')
        print('Install dependencies first, then re-run this build script.')
        print('Example: pip install -r requirements.txt')
        sys.exit(1)


def run_pyinstaller_build():
    run_preflight_checks()

    pyinstaller_command = [
        "pyinstaller",
        "--onefile",
        "--windowed",
        "--icon=icons/app_icon.ico",
        "--name=Writing Tools",
        "--clean",
        "--noconfirm",
        # Exclude unnecessary modules
        "--exclude-module", "tkinter",
        "--exclude-module", "unittest",
        "--exclude-module", "IPython",
        "--exclude-module", "jedi",
        "--exclude-module", "email_validator",
        # NOTE: do NOT exclude `cryptography` — google-genai's auth chain pulls
        # it in heavily during `genai.Client()` construction. Excluding it
        # makes the compiled exe crash on startup.
        "--exclude-module", "psutil",
        "--exclude-module", "pyzmq",
        "--exclude-module", "tornado",
        # Exclude modules related to PySide6 that are not used
        "--exclude-module", "PySide6.QtNetwork",
        "--exclude-module", "PySide6.QtXml",
        "--exclude-module", "PySide6.QtQml",
        "--exclude-module", "PySide6.QtQuick",
        "--exclude-module", "PySide6.QtQuickWidgets",
        "--exclude-module", "PySide6.QtPrintSupport",
        "--exclude-module", "PySide6.QtSql",
        "--exclude-module", "PySide6.QtTest",
        "--exclude-module", "PySide6.QtSvg",
        "--exclude-module", "PySide6.QtSvgWidgets",
        "--exclude-module", "PySide6.QtHelp",
        "--exclude-module", "PySide6.QtMultimedia",
        "--exclude-module", "PySide6.QtMultimediaWidgets",
        "--exclude-module", "PySide6.QtOpenGL",
        "--exclude-module", "PySide6.QtOpenGLWidgets",
        "--exclude-module", "PySide6.QtPositioning",
        "--exclude-module", "PySide6.QtLocation",
        "--exclude-module", "PySide6.QtSerialPort",
        "--exclude-module", "PySide6.QtWebChannel",
        "--exclude-module", "PySide6.QtWebSockets",
        "--exclude-module", "PySide6.QtWinExtras",
        "--exclude-module", "PySide6.QtNetworkAuth",
        "--exclude-module", "PySide6.QtRemoteObjects",
        "--exclude-module", "PySide6.QtTextToSpeech",
        "--exclude-module", "PySide6.QtWebEngineCore",
        "--exclude-module", "PySide6.QtWebEngineWidgets",
        "--exclude-module", "PySide6.QtWebEngine",
        "--exclude-module", "PySide6.QtBluetooth",
        "--exclude-module", "PySide6.QtNfc",
        "--exclude-module", "PySide6.QtWebView",
        "--exclude-module", "PySide6.QtCharts",
        "--exclude-module", "PySide6.QtDataVisualization",
        "--exclude-module", "PySide6.QtPdf",
        "--exclude-module", "PySide6.QtPdfWidgets",
        "--exclude-module", "PySide6.QtQuick3D",
        "--exclude-module", "PySide6.QtQuickControls2",
        "--exclude-module", "PySide6.QtQuickParticles",
        "--exclude-module", "PySide6.QtQuickTest",
        "--exclude-module", "PySide6.QtQuickWidgets",
        "--exclude-module", "PySide6.QtSensors",
        "--exclude-module", "PySide6.QtStateMachine",
        "--exclude-module", "PySide6.Qt3DCore",
        "--exclude-module", "PySide6.Qt3DRender",
        "--exclude-module", "PySide6.Qt3DInput",
        "--exclude-module", "PySide6.Qt3DLogic",
        "--exclude-module", "PySide6.Qt3DAnimation",
        "--exclude-module", "PySide6.Qt3DExtras",
        "main.py"
    ]

    try:
        # Remove previous build directories
        remove_path(DIST_DIR)
        remove_path(BUILD_DIR)
        remove_path(PYCACHE_DIR)

        # Run PyInstaller
        subprocess.run(pyinstaller_command, check=True, cwd=ROOT_DIR)
        print(f"Build completed successfully! Output: {DIST_DIR / 'Writing Tools'}")

        # Clean up unnecessary files
        remove_path(BUILD_DIR)
        remove_path(PYCACHE_DIR)

        # No need to copy data files manually since they are included
        # in the executable using --add-data

    except subprocess.CalledProcessError as e:
        print(f"Build failed with error: {e}")
        sys.exit(e.returncode or 1)

    except OSError as e:
        print(f"Build failed with OS error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_pyinstaller_build()
