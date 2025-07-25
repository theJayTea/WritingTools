@echo off
setlocal enabledelayedexpansion

REM Get script directory and navigate to project root
set "SCRIPT_DIR=%~dp0"
set "PARENT_DIR=%SCRIPT_DIR%.."
set "PROJECT_ROOT=%PARENT_DIR%\.."

REM Change to project root directory so all relative paths work
cd "%PROJECT_ROOT%"

REM Find Python executable
set "PYTHON_CMD="
for %%p in (python py python3) do (
    where %%p >nul 2>&1
    if !errorlevel! equ 0 (
        %%p --version 2>&1 | findstr "Python 3" >nul
        if !errorlevel! equ 0 (
            set "PYTHON_CMD=%%p"
            goto :found_python
        )
    )
)

echo Error: Python 3 not found. Please install Python 3.
pause
exit /b 1

:found_python
echo Using Python: %PYTHON_CMD%

REM Launch the Python script
echo Launching Writing Tools...
%PYTHON_CMD% scripts\launch.py

REM Keep window open if there was an error
if errorlevel 1 (
    echo.
    echo An error occurred. Press any key to exit...
    pause >nul
)
