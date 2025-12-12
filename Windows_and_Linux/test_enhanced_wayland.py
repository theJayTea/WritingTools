#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, "/home/mypc/git-repos/WritingTools/Windows_and_Linux")

# Set up environment to simulate Wayland
os.environ["XDG_SESSION_TYPE"] = "wayland"
os.environ["XDG_CURRENT_DESKTOP"] = "KDE"

import subprocess
import time
import threading


def test_enhanced_wayland_tools():
    print("Testing enhanced Wayland input tools...")

    # Test ydotool availability
    print("\n1. Testing ydotool availability:")
    try:
        result = subprocess.run(["ydotool", "help"], capture_output=True, timeout=2)
        if result.returncode == 0:
            print("✓ ydotool is available")
        else:
            print("✗ ydotool help failed")
    except Exception as e:
        print(f"✗ ydotool check failed: {e}")

    # Test ydotool daemon
    print("\n2. Testing ydotool daemon:")
    try:
        # Check if daemon is running
        socket_path = f"/run/user/{os.getuid()}/.ydotool_socket"
        if os.path.exists(socket_path):
            print("✓ ydotool socket exists")

            # Test daemon responsiveness
            test_result = subprocess.run(
                ["ydotool", "debug"], capture_output=True, timeout=1
            )
            if test_result.returncode == 0:
                print("✓ ydotool daemon is responsive")
            else:
                print("✗ ydotool daemon not responsive")
        else:
            print("✗ ydotool socket not found")

            # Try to start daemon
            print("  Attempting to start ydotool daemon...")
            try:
                daemon_process = subprocess.Popen(
                    ["ydotoold"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                time.sleep(1)

                # Check if daemon started
                if os.path.exists(socket_path):
                    print("✓ ydotool daemon started successfully")
                else:
                    print("✗ ydotool daemon failed to start")
            except Exception as e:
                print(f"✗ Failed to start ydotool daemon: {e}")

    except Exception as e:
        print(f"✗ ydotool daemon test failed: {e}")

    # Test wtype
    print("\n3. Testing wtype:")
    try:
        result = subprocess.run(["wtype", "--help"], capture_output=True, timeout=2)
        if result.returncode == 0:
            print("✓ wtype is available")
        else:
            print("✗ wtype help failed")
    except Exception as e:
        print(f"✗ wtype check failed: {e}")

    # Test keyboard simulation with ydotool
    print("\n4. Testing ydotool keyboard simulation:")
    try:
        # Simple key test
        result = subprocess.run(
            ["ydotool", "key", "ctrl+v"], capture_output=True, timeout=3
        )
        if result.returncode == 0:
            print("✓ ydotool keyboard simulation works")
        else:
            error_msg = (
                result.stderr.decode().strip() if result.stderr else "unknown error"
            )
            print(f"✗ ydotool keyboard simulation failed: {error_msg}")

            # Check if it's a socket issue
            if "failed to connect socket" in error_msg:
                print("  This is likely a socket/daemon issue")
            elif "Compositor does not support" in error_msg:
                print("  Compositor doesn't support the required protocol")
            else:
                print("  Unknown error from ydotool")

    except Exception as e:
        print(f"✗ ydotool keyboard test failed: {e}")

    print("\nTest completed.")


if __name__ == "__main__":
    test_enhanced_wayland_tools()
