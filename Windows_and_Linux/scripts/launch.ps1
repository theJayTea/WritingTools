$ErrorActionPreference = "Stop"

# Get script directory and parent directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $scriptDir

# Change to parent directory so all relative paths work
Set-Location $parentDir

# Create virtual environment if it doesn't exist
if (-not (Test-Path "myvenv")) {
    py -3 -m venv myvenv
}

# Activate virtual environment
& "myvenv\Scripts\activate"

# Check if dependencies are already installed
$requirementsPath = "requirements.txt"
$requirementsHash = Get-FileHash $requirementsPath
$hashFile = "myvenv\installed_requirements.hash"

if (-not (Test-Path $hashFile) -or (Get-Content $hashFile -ErrorAction SilentlyContinue) -ne $requirementsHash.Hash) {
    Write-Host "Installing/updating dependencies..."
    pip install -r $requirementsPath
    $requirementsHash.Hash | Out-File $hashFile
} else {
    Write-Host "Dependencies already up to date."
}

# Run main script
python main.py