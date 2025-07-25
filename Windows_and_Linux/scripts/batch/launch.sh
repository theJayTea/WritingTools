#!/bin/bash

set -e

# Get script directory and navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$PARENT_DIR")"

# Change to project root directory so all relative paths work
cd "$PROJECT_ROOT"

# Function to detect Python command
detect_python() {
    # Try python first (common on Windows)
    if command -v python >/dev/null 2>&1; then
        # Check if python points to Python 3
        if python --version 2>&1 | grep -q "Python 3"; then
            echo "python"
            return
        fi
    fi

    # Try python3 (common on Linux/macOS)
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
        return
    fi

    # Try py (Windows Python Launcher)
    if command -v py >/dev/null 2>&1; then
        if py --version 2>&1 | grep -q "Python 3"; then
            echo "py"
            return
        fi
    fi

    echo "Error: Python 3 not found. Please install Python 3." >&2
    exit 1
}

# Detect Python command
PYTHON_CMD=$(detect_python)
echo "Using Python: $PYTHON_CMD"

# Launch the Python script
echo "Launching Writing Tools..."
$PYTHON_CMD scripts/launch.py

# Check exit code
if [ $? -ne 0 ]; then
    echo ""
    echo "An error occurred. Press Enter to exit..."
    read
fi
