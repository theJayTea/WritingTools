#!/bin/bash

# ============================================================================
# Writing Tools - Task Runner
# This script provides a central place to run development and build tasks.
#
# Usage:
#   ./run.sh [command]
#
# Commands:
#   dev         - Run the application in development mode.
#   build-dev   - Create a development build (fast, for testing).
#   build-final - Create a final release build (clean, for distribution).
#   help        - Show this help message.
#
# If no command is provided, an interactive menu will be shown.
# ============================================================================

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
set -e

# Get the directory where this script is located and change to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Python Detection ---
detect_python() {
    if command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null && python --version 2>&1 | grep -q "Python 3"; then
        echo "python"
    else
        echo "[ERROR] Python 3 not found. Please install Python 3." >&2
        exit 1
    fi
}
PYTHON_CMD=$(detect_python)

# --- Task Functions ---
run_dev() {
    echo
    echo "[INFO] Starting application in Development Mode..."
    echo "-------------------------------------------------"
    $PYTHON_CMD "scripts/launch.py"
}

run_build_dev() {
    echo
    echo "[INFO] Starting Development Build..."
    echo "-----------------------------------"
    $PYTHON_CMD "scripts/dev-build.py"
}

run_build_final() {
    echo
    echo "[INFO] Starting Final Release Build..."
    echo "-----------------------------------"
    $PYTHON_CMD "scripts/final-build.py"
}

show_help() {
    echo
    echo "Usage: ./run.sh [command]"
    echo
    echo "Commands:"
    echo "  dev          - Run the application in development mode."
    echo "  build-dev    - Create a development build (fast, for testing)."
    echo "  build-final  - Create a final release build (clean, for distribution)."
    echo "  help         - Show this help message."
    echo
    echo "If no command is provided, an interactive menu will be shown."
}

# --- Argument Handling ---
COMMAND="$1"

if [ -n "$COMMAND" ]; then
    case "$COMMAND" in
        dev)
            run_dev
            ;;
        build-dev)
            run_build_dev
            ;;
        build-final)
            run_build_final
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "[ERROR] Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
    exit 0
fi

# --- Interactive Menu ---
while true; do
    clear
    echo "================================="
    echo "  Writing Tools - Task Runner"
    echo "================================="
    echo
    echo "  1. Run Development Mode"
    echo "     (Launched as script)"
    echo
    echo "  2. Create Development Build"
    echo "     (Faster compilation on subsequent runs, keeps your settings)"
    echo
    echo "  3. Create Final Release Build"
    echo "     (exe and files for production)"
    echo
    read -p "Enter your choice [1-3] (or any other key to exit): " choice

    case "$choice" in
        1)
            run_dev
            break
            ;;
        2)
            run_build_dev
            break
            ;;
        3)
            run_build_final
            break
            ;;
        *)
            # Any other input will exit the loop
            break
            ;;
    esac
done

echo
echo "[DONE] Task finished."