#!/usr/bin/env python3
"""
Writing Tools - Final Build Script
Cross-platform final release build with environment setup
"""

import os
import subprocess
import sys
import shutil

try:
    from .utils import (
        get_project_root,
        setup_environment,
        verify_requirements,
        wait_for_user,
        get_activation_script,
    )
except ImportError:
    from utils import (
        get_project_root,
        setup_environment,
        verify_requirements,
        wait_for_user,
        get_activation_script,
    )


def copy_required_files():
    """Copy required files for final release build"""
    files_to_copy = [
        ("icons", "dist/icons"),
        ("background_dark.png", "dist/background_dark.png"),
        ("background_popup_dark.png", "dist/background_popup_dark.png"),
        ("background_popup.png", "dist/background_popup.png"),
        ("background.png", "dist/background.png"),
        # config.json is intentionally not included.
        # The application will generate a default config on first run.
        (
            "default-options.json",
            "dist/options.json",
        ),  # Copy default options as template
    ]

    print("Copying required files...")
    for src, dst in files_to_copy:
        try:
            if os.path.isdir(src):
                if os.path.exists(dst):
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
                print(f"Copied directory: {src} -> {dst}")
            else:
                # Ensure destination directory exists
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                print(f"Copied file: {src} -> {dst}")
        except Exception as e:
            print(f"Failed to copy {src}: {e}")
            return False

    return True


def clean_build_directories():
    """Remove build directories for clean final build"""
    dirs_to_clean = ["dist", "build", "__pycache__"]

    print("Cleaning build directories...")
    for dir_name in dirs_to_clean:
        if os.path.exists(dir_name):
            try:
                if sys.platform.startswith("win"):
                    os.system(f"rmdir /s /q {dir_name}")
                else:
                    shutil.rmtree(dir_name)
                print(f"Removed: {dir_name}")
            except Exception as e:
                print(f"Failed to remove {dir_name}: {e}")


def run_final_build(venv_path="myvenv"):
    """Run PyInstaller build for final release"""
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
        "--clean",
        "--noconfirm",
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
        print("Starting PyInstaller build...")
        subprocess.run(pyinstaller_command, check=True)
        print("PyInstaller build completed successfully!")
        return True

    except subprocess.CalledProcessError as e:
        print(f"Build failed with error: {e}")
        return False


def cleanup_after_build():
    """Clean up unnecessary files after build"""
    dirs_to_clean = ["build", "__pycache__"]

    print("Cleaning up after build...")
    for dir_name in dirs_to_clean:
        if os.path.exists(dir_name):
            try:
                if sys.platform.startswith("win"):
                    os.system(f"rmdir /s /q {dir_name}")
                else:
                    shutil.rmtree(dir_name)
                print(f"Cleaned up: {dir_name}")
            except Exception as e:
                print(f"Failed to clean {dir_name}: {e}")


def main():
    print("=== Writing Tools - Final Build Script ===")
    print("This script will create a complete release build with all required files.\n")

    try:
        # Setup project root
        project_root = get_project_root()

        # Change to the project root directory before proceeding
        os.chdir(project_root)

        # Setup environment (virtual env + dependencies)
        print("Setting up build environment...")
        success, _ = setup_environment()
        if not success:
            print("\nFailed to setup environment!")
            wait_for_user()
            return 1

        # Verify requirements
        required_files = ["main.py", "icons/app_icon.ico"]
        if not verify_requirements(required_files):
            print("\nBuild aborted due to missing files!")
            wait_for_user()
            return 1

        # Step 1: Clean everything for fresh build
        clean_build_directories()

        # Step 2: Run PyInstaller
        if not run_final_build("myvenv"):
            print("\nBuild failed!")
            wait_for_user()
            return 1

        # Step 3: Copy required files to dist folder
        if not copy_required_files():
            print("\nFailed to copy required files!")
            wait_for_user()
            return 1

        # Step 4: Clean up build artifacts
        cleanup_after_build()

        print("\nFinal build completed successfully!")
        print("Release files are in the 'dist' folder")
        print("Ready for distribution!")
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
