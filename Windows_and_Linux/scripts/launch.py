#!/usr/bin/env python3
"""
Writing Tools - Development Launcher
Cross-platform development environment setup and launcher
"""

import os
import sys
import subprocess

try:
    from .utils import (
        get_project_root,
        setup_environment,
        terminate_existing_processes,
        get_activation_script,
        wait_for_user,
    )
except ImportError:
    from utils import (
        get_project_root,
        setup_environment,
        terminate_existing_processes,
        get_activation_script,
        wait_for_user,
    )


def launch_application(venv_path, script_name="main.py"):
    """Launch the main application using the virtual environment"""
    python_cmd = get_activation_script(venv_path)

    if not os.path.exists(python_cmd):
        print(f"Error: Python executable not found at {python_cmd}")
        return False

    # main.py should be in the current directory (Windows_and_Linux)
    if not os.path.exists(script_name):
        print(f"Error: Main script not found: {script_name}")
        return False

    print(f"Launching {script_name}...")
    try:
        # Launch the application
        subprocess.run([python_cmd, script_name], check=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to launch application: {e}")
        return False
    except KeyboardInterrupt:
        print("\nApplication interrupted by user.")
        return True


def main():
    """Main function"""
    print("===== Writing Tools - Development Launcher =====")
    print()

    try:
        # Setup project root
        get_project_root()

        # Setup environment (virtual env + dependencies)
        print("Setting up development environment...")
        success, _ = setup_environment()
        if not success:
            print("\nFailed to setup environment!")
            wait_for_user()
            return 1

        # Stop existing processes (both exe and script)
        terminate_existing_processes(
            exe_name="Writing Tools.exe", script_name="main.py"
        )

        # Launch application
        print()
        if not launch_application("myvenv"):
            print("\nFailed to launch application!")
            wait_for_user()
            return 1

        print("\n===== Application finished =====")
        return 0

    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        return 1
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        wait_for_user()
        return 1


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
