#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, "/home/mypc/git-repos/WritingTools/Windows_and_Linux")

# Set up environment to simulate KDE Wayland
os.environ["XDG_SESSION_TYPE"] = "wayland"
os.environ["XDG_CURRENT_DESKTOP"] = "KDE"

import subprocess
import time


def test_comprehensive_wayland_tools():
    print("🔍 Testing Comprehensive Wayland Input Tools...")
    print(f"Environment: KDE Wayland")
    print(f"User: {os.getenv('USER', 'unknown')}")
    print()

    # Test all available tools
    tools = [
        ("kdotool", ["kdotool", "--version"]),
        ("ydotool", ["ydotool", "help"]),
        ("dotool", ["dotool", "--help"]),
        ("wtype", ["wtype", "--help"]),
    ]

    available_tools = []

    for name, cmd in tools:
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=3)
            if result.returncode == 0:
                print(f"✅ {name} is available")
                available_tools.append(name)
            else:
                print(f"❌ {name} failed: {result.stderr.decode()[:50]}")
        except Exception as e:
            print(f"❌ {name} check failed: {e}")

    print()
    print("📋 Available Tools:", ", ".join(available_tools))
    print()

    # Test ydotool daemon management
    print("🔧 Testing ydotool daemon management:")
    try:
        socket_path = f"/run/user/{os.getuid()}/.ydotool_socket"

        # Check if daemon is running
        if os.path.exists(socket_path):
            print("✅ ydotool socket exists")

            # Test daemon responsiveness
            test_result = subprocess.run(
                ["ydotool", "debug"], capture_output=True, timeout=1
            )
            if test_result.returncode == 0:
                print("✅ ydotool daemon is responsive")
            else:
                print("⚠️  ydotool daemon not responsive, restarting...")
                subprocess.run(["pkill", "-f", "ydotoold"], capture_output=True)
                time.sleep(0.2)
                subprocess.Popen(
                    ["ydotoold"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                time.sleep(0.5)
                print("🔄 ydotool daemon restarted")
        else:
            print("⚠️  ydotool daemon not running, starting...")
            daemon_process = subprocess.Popen(
                ["ydotoold"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            time.sleep(1)

            if os.path.exists(socket_path):
                print("✅ ydotool daemon started successfully")
            else:
                print("❌ ydotool daemon failed to start")
    except Exception as e:
        print(f"❌ ydotool daemon test failed: {e}")

    print()

    # Test keyboard simulation with all available methods
    print("⌨️  Testing keyboard simulation methods:")

    simulation_methods = []

    # Test kdotool (if available)
    if "kdotool" in available_tools:
        try:
            result = subprocess.run(
                ["kdotool", "key", "ctrl+v"], capture_output=True, timeout=3
            )
            if result.returncode == 0:
                print("✅ kdotool keyboard simulation works")
                simulation_methods.append("kdotool")
            else:
                print(
                    f"❌ kdotool keyboard simulation failed: {result.stderr.decode()[:50]}"
                )
        except Exception as e:
            print(f"❌ kdotool keyboard test failed: {e}")

    # Test ydotool (if available)
    if "ydotool" in available_tools:
        try:
            result = subprocess.run(
                ["ydotool", "key", "ctrl+v"], capture_output=True, timeout=3
            )
            if result.returncode == 0:
                print("✅ ydotool keyboard simulation works")
                simulation_methods.append("ydotool")
            else:
                error_msg = (
                    result.stderr.decode().strip() if result.stderr else "unknown"
                )
                print(f"❌ ydotool keyboard simulation failed: {error_msg}")
        except Exception as e:
            print(f"❌ ydotool keyboard test failed: {e}")

    # Test dotool (if available)
    if "dotool" in available_tools:
        try:
            result = subprocess.run(
                ["dotool", "key", "ctrl+v"], capture_output=True, timeout=3
            )
            if result.returncode == 0:
                print("✅ dotool keyboard simulation works")
                simulation_methods.append("dotool")
            else:
                error_msg = (
                    result.stderr.decode().strip() if result.stderr else "unknown"
                )
                print(f"❌ dotool keyboard simulation failed: {error_msg}")
        except Exception as e:
            print(f"❌ dotool keyboard test failed: {e}")

    # Test wtype (if available)
    if "wtype" in available_tools:
        try:
            result = subprocess.run(
                ["wtype", "-P", "ctrl+v"], capture_output=True, timeout=3
            )
            if result.returncode == 0:
                print("✅ wtype keyboard simulation works")
                simulation_methods.append("wtype")
            else:
                error_msg = (
                    result.stderr.decode().strip() if result.stderr else "unknown"
                )
                print(f"❌ wtype keyboard simulation failed: {error_msg}")
        except Exception as e:
            print(f"❌ wtype keyboard test failed: {e}")

    print()
    print(
        "🎯 Working Simulation Methods:",
        ", ".join(simulation_methods) if simulation_methods else "None",
    )
    print()

    # Summary and recommendations
    if simulation_methods:
        print("🎉 SUCCESS: Automatic paste should work!")
        print(f"   The application will use: {', '.join(simulation_methods)}")
        print("   in that order until one succeeds.")
    else:
        print("⚠️  WARNING: No automatic paste methods worked.")
        print("   The application will copy text to clipboard.")
        print("   You may need to press Ctrl+V manually.")
        print()
        print("   This could be due to:")
        print("   - Wayland compositor security restrictions")
        print("   - Missing permissions for input simulation")
        print("   - Specific KDE Wayland configuration")

    print()
    print("📝 Recommendations:")
    if "ydotool" in simulation_methods:
        print("   ✅ ydotool is working - this is the most reliable method")
    if "kdotool" in simulation_methods:
        print("   ✅ kdotool is working - great for KDE-specific features")
    if not simulation_methods:
        print("   ⚠️  Consider checking your Wayland compositor settings")
        print(
            "   ⚠️  Try running the application in an X11 session for full functionality"
        )

    print()
    print("🧪 Test completed successfully!")


if __name__ == "__main__":
    test_comprehensive_wayland_tools()
