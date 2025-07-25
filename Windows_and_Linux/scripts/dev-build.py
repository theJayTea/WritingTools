#!/usr/bin/env python3
"""
Writing Tools - Development Build Script
Cross-platform development build with environment setup
"""

import os
import subprocess
import sys
import shutil

try:
    from .utils import (
        get_project_root,
        setup_environment,
        terminate_existing_processes,
        verify_requirements,
        wait_for_user,
        get_activation_script,
    )
except ImportError:
    from utils import (
        get_project_root,
        setup_environment,
        terminate_existing_processes,
        verify_requirements,
        wait_for_user,
        get_activation_script,
    )


def copy_required_files():
    """
    Copy required files for the development build.
    This includes assets and user-specific configurations from the local 'config' folder.
    """
    # --- Asset files (always copied) ---
    assets_to_copy = [
        ("icons", "dist/icons"),
        ("background_dark.png", "dist/background_dark.png"),
        ("background_popup_dark.png", "dist/background_popup_dark.png"),
        ("background_popup.png", "dist/background_popup.png"),
        ("background.png", "dist/background.png"),
        (
            "default-options.json",
            "dist/options.json",
        ),  # Copy default options as template
    ]

    # --- User-specific config files (copied only if they exist) ---
    # Source is the local, untracked 'config' directory
    user_config_files = [
        ("config/config.json", "dist/config.json"),
        (
            "config/options.json",
            "dist/options.json",
        ),  # User's custom options override default
    ]

    print("Copying required files for development build...")
    os.makedirs("dist", exist_ok=True)

    # --- Copy assets ---
    for src, dst in assets_to_copy:
        try:
            if not os.path.exists(src):
                print(f"Warning: Asset file/directory not found: {src}")
                continue

            if os.path.isdir(src):
                if os.path.exists(dst):
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
            else:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
            print(f"Copied asset: {src} -> {dst}")
        except Exception as e:
            print(f"Error copying asset {src}: {e}")
            return False

    # --- Copy user-specific configs if they exist ---
    for src, dst in user_config_files:
        try:
            if os.path.exists(src):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                print(f"Copied user config: {src} -> {dst}")
            else:
                print(f"Info: No user-specific config found at {src}, skipping.")
        except Exception as e:
            print(f"Error copying user config {src}: {e}")
            return False

    return True


def run_dev_build(venv_path="myvenv"):
    """Run PyInstaller build for development (faster, less cleanup)"""
    # Use the virtual environment's Python to run PyInstaller
    python_cmd = get_activation_script(venv_path)
    pyinstaller_command = [
        python_cmd,
        "-m",
        "PyInstaller",
        "--onefile",
        "--windowed",
        "--icon=icons/app_icon.ico",
        "--name=Writing Tools",
        "--noconfirm",  # Removed --clean for faster builds
        # Exclude unnecessary modules
        "--exclude-module",
        "tkinter",
        "--exclude-module",
        "unittest",
        "--exclude-module",
        "IPython",
        "--exclude-module",
        "jedi",
        "--exclude-module",
        "email_validator",
        "--exclude-module",
        "cryptography",
        "--exclude-module",
        "psutil",
        "--exclude-module",
        "pyzmq",
        "--exclude-module",
        "tornado",
        # Exclude modules related to PySide6 that are not used
        "--exclude-module",
        "PySide6.QtNetwork",
        "--exclude-module",
        "PySide6.QtXml",
        "--exclude-module",
        "PySide6.QtQml",
        "--exclude-module",
        "PySide6.QtQuick",
        "--exclude-module",
        "PySide6.QtQuickWidgets",
        "--exclude-module",
        "PySide6.QtPrintSupport",
        "--exclude-module",
        "PySide6.QtSql",
        "--exclude-module",
        "PySide6.QtTest",
        "--exclude-module",
        "PySide6.QtSvg",
        "--exclude-module",
        "PySide6.QtSvgWidgets",
        "--exclude-module",
        "PySide6.QtHelp",
        "--exclude-module",
        "PySide6.QtMultimedia",
        "--exclude-module",
        "PySide6.QtMultimediaWidgets",
        "--exclude-module",
        "PySide6.QtOpenGL",
        "--exclude-module",
        "PySide6.QtOpenGLWidgets",
        "--exclude-module",
        "PySide6.QtPositioning",
        "--exclude-module",
        "PySide6.QtLocation",
        "--exclude-module",
        "PySide6.QtSerialPort",
        "--exclude-module",
        "PySide6.QtWebChannel",
        "--exclude-module",
        "PySide6.QtWebSockets",
        "--exclude-module",
        "PySide6.QtWinExtras",
        "--exclude-module",
        "PySide6.QtNetworkAuth",
        "--exclude-module",
        "PySide6.QtRemoteObjects",
        "--exclude-module",
        "PySide6.QtTextToSpeech",
        "--exclude-module",
        "PySide6.QtWebEngineCore",
        "--exclude-module",
        "PySide6.QtWebEngineWidgets",
        "--exclude-module",
        "PySide6.QtWebEngine",
        "--exclude-module",
        "PySide6.QtBluetooth",
        "--exclude-module",
        "PySide6.QtNfc",
        "--exclude-module",
        "PySide6.QtWebView",
        "--exclude-module",
        "PySide6.QtCharts",
        "--exclude-module",
        "PySide6.QtDataVisualization",
        "--exclude-module",
        "PySide6.QtPdf",
        "--exclude-module",
        "PySide6.QtPdfWidgets",
        "--exclude-module",
        "PySide6.QtQuick3D",
        "--exclude-module",
        "PySide6.QtQuickControls2",
        "--exclude-module",
        "PySide6.QtQuickParticles",
        "--exclude-module",
        "PySide6.QtQuickTest",
        "--exclude-module",
        "PySide6.QtQuickWidgets",
        "--exclude-module",
        "PySide6.QtSensors",
        "--exclude-module",
        "PySide6.QtStateMachine",
        "--exclude-module",
        "PySide6.Qt3DCore",
        "--exclude-module",
        "PySide6.Qt3DRender",
        "--exclude-module",
        "PySide6.Qt3DInput",
        "--exclude-module",
        "PySide6.Qt3DLogic",
        "--exclude-module",
        "PySide6.Qt3DAnimation",
        "--exclude-module",
        "PySide6.Qt3DExtras",
        "main.py",
    ]

    try:
        print("Starting PyInstaller development build...")
        subprocess.run(pyinstaller_command, check=True)
        print("PyInstaller development build completed successfully!")
        return True

    except subprocess.CalledProcessError as e:
        print(f"Error: Build failed with error: {e}")
        return False
    except FileNotFoundError:
        print(
            "Error: PyInstaller not found. Please install it with: pip install pyinstaller"
        )
        return False


def launch_build():
    """Launch the built executable, killing any existing instance first."""
    if sys.platform.startswith("win"):
        exe_name = "Writing Tools.exe"
        exe_path = os.path.join("dist", exe_name)
    else:
        exe_name = "Writing Tools"
        exe_path = os.path.join("dist", exe_name)

    script_name = "main.py"

    if not os.path.exists(exe_path):
        print(f"Error: Built executable not found at {exe_path}")
        return False

    # Step 1: Kill any existing process
    terminate_existing_processes(exe_name=exe_name, script_name=script_name)

    # Step 2: Launch the new executable
    try:
        print(f"Relaunching {exe_path}...")
        # Use subprocess.Popen to launch without blocking
        if sys.platform.startswith("win"):
            subprocess.Popen([exe_path], creationflags=subprocess.CREATE_NEW_CONSOLE)
        else:
            subprocess.Popen([exe_path])
        print("Application successfully reloaded.")
        return True
    except Exception as e:
        print(f"Error: Failed to relaunch application: {e}")
        return False


def main():
    print("=== Writing Tools - Development Build Script ===")
    print("This script will create a development build preserving your settings.\n")

    try:
        # Setup project root
        project_root = get_project_root()

        # Terminate any existing instances of the app first
        print("Checking for running application instances...")
        terminate_existing_processes(
            exe_name="Writing Tools.exe", script_name="main.py"
        )
        print("Done.")

        # Change to the project root directory before proceeding
        os.chdir(project_root)

        # Setup environment (virtual env + dependencies)
        print("Setting up development environment...")
        success, _ = setup_environment()
        if not success:
            print("\nFailed to setup environment!")
            wait_for_user()
            return 1

        # Step 0: Verify requirements
        required_files = ["main.py", "icons/app_icon.ico"]
        if not verify_requirements(required_files):
            print("\nBuild aborted due to missing files!")
            wait_for_user()
            return 1

        # Step 1: Run PyInstaller (no clean for faster builds)
        if not run_dev_build("myvenv"):
            print("\nBuild failed!")
            wait_for_user()
            return 1

        # Step 2: Copy required files to dist folder (preserve configs)
        if not copy_required_files():
            print("\nFailed to copy required files!")
            wait_for_user()
            return 1

        print("\n" + "=" * 50)
        print("Development build completed successfully!")
        print("Development files are in the 'dist' folder")
        print("Your settings and configurations have been preserved!")
        print("=" * 50)

        # Step 3: Launch the build automatically
        launch_build()
        return 0

    except KeyboardInterrupt:
        print("\nBuild interrupted by user.")
        return 1
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        wait_for_user()
        return 1


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
