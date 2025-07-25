#!/usr/bin/env python3
"""
Writing Tools - Utility Functions
Common functions shared across build and launch scripts
"""

import os
import sys
import subprocess
import hashlib
import shutil
from pathlib import Path


def get_project_root():
    """Get the Windows_and_Linux directory (the working directory for the project)"""
    script_dir = Path(__file__).parent.absolute()  # scripts/
    windows_linux_dir = script_dir.parent  # Windows_and_Linux/
    os.chdir(windows_linux_dir)
    return windows_linux_dir


def find_python_executable():
    """Find the best Python executable available"""
    python_candidates = ["python3", "python", "py"]

    for candidate in python_candidates:
        if shutil.which(candidate):
            try:
                # Test if it's Python 3
                result = subprocess.run(
                    [candidate, "--version"], capture_output=True, text=True
                )
                if result.returncode == 0 and "Python 3" in result.stdout:
                    return candidate
            except Exception:
                continue

    raise RuntimeError("Python 3 not found. Please install Python 3.")


def calculate_file_hash(file_path):
    """Calculate SHA256 hash of a file"""
    if not os.path.exists(file_path):
        return None

    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()


def create_virtual_environment(venv_path, python_cmd):
    """Create a virtual environment if it doesn't exist"""
    if os.path.exists(venv_path):
        print("Virtual environment already exists.")
        return True

    print("Creating virtual environment...")
    try:
        # Try using venv module first (preferred)
        subprocess.run([python_cmd, "-m", "venv", venv_path], check=True)
        print("Virtual environment created successfully.")
        return True
    except subprocess.CalledProcessError:
        try:
            # Fallback: try virtualenv
            print("Trying virtualenv as fallback...")
            subprocess.run(
                [python_cmd, "-m", "pip", "install", "virtualenv"], check=True
            )
            subprocess.run([python_cmd, "-m", "virtualenv", venv_path], check=True)
            print("Virtual environment created with virtualenv.")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error: Failed to create virtual environment: {e}")
            return False


def get_activation_script(venv_path):
    """Get the appropriate activation script path for the platform"""
    if sys.platform.startswith("win"):
        return os.path.abspath(os.path.join(venv_path, "Scripts", "python.exe"))
    else:
        return os.path.abspath(os.path.join(venv_path, "bin", "python"))


def get_pip_executable(venv_path):
    """Get the pip executable path for the virtual environment"""
    if sys.platform.startswith("win"):
        return os.path.abspath(os.path.join(venv_path, "Scripts", "pip.exe"))
    else:
        return os.path.abspath(os.path.join(venv_path, "bin", "pip"))


def install_dependencies(venv_path, requirements_path):
    """Install or update dependencies if needed"""
    hash_file = os.path.join(venv_path, "installed_requirements.hash")

    # Calculate current requirements hash
    current_hash = calculate_file_hash(requirements_path)
    if not current_hash:
        print("Warning: requirements.txt not found. Skipping dependency installation.")
        return True

    # Check if dependencies are already installed
    installed_hash = ""
    if os.path.exists(hash_file):
        try:
            with open(hash_file, "r", encoding="utf-8") as f:
                installed_hash = f.read().strip()
        except Exception:
            pass

    if current_hash != installed_hash:
        print("Installing/updating dependencies...")

        try:
            # Use python -m pip instead of direct pip executable to avoid path issues
            python_cmd = get_activation_script(venv_path)
            requirements_abs_path = os.path.abspath(requirements_path)
            cmd = [python_cmd, "-m", "pip", "install", "-r", requirements_abs_path]
            subprocess.run(cmd, check=True)

            # Save the hash
            with open(hash_file, "w", encoding="utf-8") as f:
                f.write(current_hash)

            print("Dependencies installed successfully.")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error: Failed to install dependencies: {e}")
            return False
    else:
        print("Dependencies already up to date.")
        return True


def kill_existing_exe_process(process_name):
    """Terminate an existing process by its name."""
    try:
        if sys.platform.startswith("win"):
            # Use taskkill to force termination of the process by its image name
            command = ["taskkill", "/F", "/IM", process_name]
            result = subprocess.run(command, capture_output=True, text=True)

            # A return code of 0 means success
            # A return code of 128 means the process was not found, which is okay
            if result.returncode == 0:
                print(f"Successfully terminated existing process: {process_name}")
            elif result.returncode == 128:
                print(f"No existing process found for: {process_name}")
            else:
                # For other errors, print the details
                print(
                    f"Warning: Could not terminate {process_name}. Exit code: {result.returncode}"
                )
                if result.stderr:
                    print(f"Stderr: {result.stderr.strip()}")

        else:
            # For Linux/macOS, use pkill
            command = ["pkill", "-f", process_name]
            result = subprocess.run(command, capture_output=True, text=True)
            # pkill returns 1 if no process is found, which is normal
            if result.returncode == 0:
                print(f"Successfully terminated existing process: {process_name}")
            else:
                print(f"No existing process found for: {process_name}")

    except Exception as e:
        print(f"Warning: Error while trying to kill process {process_name}: {e}")


def kill_python_script_process(script_name):
    """Terminate a Python script process by its command line."""
    try:
        if sys.platform.startswith("win"):
            # Use WMIC to find and terminate the specific Python script
            command = f"wmic process where \"name='python.exe' and commandline like '%%{script_name}%%'\" call terminate"
            result = subprocess.run(command, capture_output=True, text=True, shell=True)

            if "No instance(s) available" in result.stdout:
                print(f"No existing Python process found for: {script_name}")
            elif "Terminating" in result.stdout:
                print(f"Successfully terminated existing Python process: {script_name}")
            else:
                print(f"Finished checking for Python process: {script_name}")

        else:
            # For macOS and Linux, use pkill with a pattern that matches the script name
            command = ["pkill", "-f", f"python.*{script_name}"]
            result = subprocess.run(command, capture_output=True, text=True)
            if result.returncode == 0:
                print(f"Successfully terminated existing Python process: {script_name}")
            else:
                print(f"No existing Python process found for: {script_name}")

    except Exception as e:
        print(
            f"Warning: Error while trying to kill Python script process {script_name}: {e}"
        )


def terminate_existing_processes(exe_name=None, script_name=None):
    """Terminate any existing Writing Tools processes (both exe and script)"""
    print("Checking for and terminating any existing Writing Tools processes...")

    if exe_name:
        kill_existing_exe_process(exe_name)

    if script_name:
        kill_python_script_process(script_name)


def wait_for_user():
    """Wait for user input (cross-platform pause)"""
    try:
        input("Press Enter to continue...")
    except KeyboardInterrupt:
        print("\nExiting...")


def verify_requirements(required_files):
    """Verify that required files exist before building"""
    missing_files = []
    for file_path in required_files:
        if not os.path.exists(file_path):
            missing_files.append(file_path)

    if missing_files:
        print("Error: Missing required files:")
        for file_path in missing_files:
            print(f"  - {file_path}")
        return False

    return True


def setup_environment(venv_path="myvenv", requirements_path="requirements.txt"):
    """Setup virtual environment and install dependencies"""
    try:
        # Find Python executable
        python_cmd = find_python_executable()
        print(f"Using Python: {python_cmd}")

        # Create virtual environment
        if not create_virtual_environment(venv_path, python_cmd):
            print("\nFailed to create virtual environment!")
            return False, None

        # Install dependencies
        if not install_dependencies(venv_path, requirements_path):
            print("\nFailed to install dependencies!")
            return False, None

        return True, python_cmd

    except Exception as e:
        print(f"Error setting up environment: {e}")
        return False, None
