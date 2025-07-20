#!/bin/bash

set -e

# Get script directory and parent directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Change to parent directory so all relative paths work
cd "$PARENT_DIR"

VENV_PATH="myvenv"
REQUIREMENTS_PATH="requirements.txt"
HASH_FILE="$VENV_PATH/installed_requirements.hash"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_PATH" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_PATH"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_PATH/bin/activate"

# Check if dependencies are already installed
CURRENT_HASH=$(sha256sum "$REQUIREMENTS_PATH" | cut -d' ' -f1)
INSTALLED_HASH=""

if [ -f "$HASH_FILE" ]; then
    INSTALLED_HASH=$(cat "$HASH_FILE")
fi

if [ "$CURRENT_HASH" != "$INSTALLED_HASH" ]; then
    echo "Installing/updating dependencies..."
    pip install -r "$REQUIREMENTS_PATH"
    echo "$CURRENT_HASH" > "$HASH_FILE"
else
    echo "Dependencies already up to date."
fi

# Run main script
echo "Launching Writing Tools..."
python main.py