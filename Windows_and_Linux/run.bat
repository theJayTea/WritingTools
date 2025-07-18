@echo off
setlocal

REM This script runs the PowerShell script that manages the creation of the environment,
REM installation of dependencies and execution of the application.
REM %~dp0 represents the path to the directory where this script is located.
echo Launching configuration and execution script...
powershell -ExecutionPolicy Bypass -File "%~dp0launch.ps1"

echo.
echo The script is finished. Press a key to close this window...
pause >nul
