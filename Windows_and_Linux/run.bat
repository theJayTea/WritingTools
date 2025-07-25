@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM Writing Tools - Task Runner
REM This script provides a central place to run development and build tasks.
REM
REM Usage:
REM   run.bat [command]
REM
REM Commands:
REM   dev         - Run the application in development mode.
REM   build-dev   - Create a development build (fast, for testing).
REM   build-final - Create a final release build (clean, for distribution).
REM   help        - Show this help message.
REM
REM If no command is provided, an interactive menu will be shown.
REM ============================================================================

REM --- Script Setup ---
REM Get the directory where this batch file is located and change to it.
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

REM --- Python Detection ---
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
echo [ERROR] Python 3 not found. Please install Python 3 and ensure it's in your PATH.
pause
exit /b 1
:found_python

REM --- Argument Handling ---
set "COMMAND=%1"

if /i "%COMMAND%"=="dev"         goto :run_dev
if /i "%COMMAND%"=="build-dev"   goto :run_build_dev
if /i "%COMMAND%"=="build-final" goto :run_build_final
if /i "%COMMAND%"=="help"        goto :show_help
if /i "%COMMAND%"=="/?"          goto :show_help
if not "%COMMAND%"=="" (
    echo [ERROR] Unknown command: %COMMAND%
    goto :show_help
)

REM --- Interactive Menu ---
:menu
cls
echo =================================
echo  Writing Tools - Task Runner
echo =================================
echo.
echo   1. Run Development Mode
echo      (Launched as script)
echo.
echo   2. Create Development Build
echo      (Faster compilation on subsequent runs, keeps your settings)
echo.
echo   3. Create Final Release Build
echo      (exe and files for production)
echo.
set /p "CHOICE=Enter your choice [1-3] (or any other key to exit): "

if "%CHOICE%"=="1" goto :run_dev
if "%CHOICE%"=="2" goto :run_build_dev
if "%CHOICE%"=="3" goto :run_build_final
goto :exit_script

REM --- Task Definitions ---
:run_dev
echo.
echo [INFO] Starting application in Development Mode...
echo -------------------------------------------------
"%PYTHON_CMD%" "scripts/launch.py"
goto :end_script

:run_build_dev
echo.
echo [INFO] Starting Development Build...
echo -----------------------------------
"%PYTHON_CMD%" "scripts/dev-build.py"
goto :end_script

:run_build_final
echo.
echo [INFO] Starting Final Release Build...
echo -----------------------------------
"%PYTHON_CMD%" "scripts/final-build.py"
goto :end_script

:show_help
echo.
echo Usage: run.bat [command]
echo.
echo Commands:
echo   dev          - Run the application in development mode.
echo   build-dev    - Create a development build (fast, for testing).
echo   build-final  - Create a final release build (clean, for distribution).
echo   help         - Show this help message.
echo.
echo If no command is provided, an interactive menu will be shown.
goto :end_script

:end_script
echo.
if %errorlevel% neq 0 (
    echo [DONE] Task finished with errors.
    pause
) else (
    echo [DONE] Task finished successfully.
)

:exit_script
endlocal
exit /b %errorlevel%