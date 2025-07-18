$ErrorActionPreference = "Stop"

# Create virtual environment if it doesn't exist
if (-not (Test-Path "myvenv")) {
    py -3 -m venv myvenv
}

# Activate virtual environment
& "myvenv\Scripts\activate"

# Install dependencies
pip install -r requirements.txt

# Run main script
python main.py