# 🚀 Development and Build Workflow

This project uses unified task runner scripts, `run.bat` (for Windows) and `run.sh` (for Linux/macOS), to simplify all common operations like running, testing, and building the application.

These scripts are the **recommended way** to interact with the project.

## Getting Started

1.  Navigate to the `Windows_and_Linux` directory in your terminal.
2.  Run the script for your operating system:
    -   **Windows:** `run.bat`
    -   **Linux/macOS:** `./run.sh`

This will automatically handle the creation of a virtual environment, installation of dependencies, and will present you with a menu of available tasks.

## Available Tasks

You can run tasks in two ways: through the interactive menu or by providing a command directly.

### Interactive Menu

If you run `run.bat` or `./run.sh` without any arguments, you will see this menu:

```
=================================
  Writing Tools - Task Runner
=================================

  1. Run Development Mode
     (Launched as script)

  2. Create Development Build
     (Faster compilation on subsequent runs, keeps your settings)

  3. Create Final Release Build
     (exe and files for production)

Enter your choice [1-3] (or any other key to exit):
```

Simply enter the number for the task you want to perform.

### Direct Commands

For a faster workflow, you can run tasks by passing a command as an argument.

-   **Run in Development Mode:**
    -   Windows: `run.bat dev`
    -   Linux/macOS: `./run.sh dev`
    -   *Note: This command automatically closes any running instances of the application before launching, ensuring a fresh start.*

-   **Create a Development Build:**
    -   Windows: `run.bat build-dev`
    -   Linux/macOS: `./run.sh build-dev`
    -   *Note: This command also closes running instances before launching the newly compiled application.*

-   **Create a Final Release Build:**
    -   Windows: `run.bat build-final`
    -   Linux/macOS: `./run.sh build-final`

-   **Show Help:**
    -   Windows: `run.bat help`
    -   Linux/macOS: `./run.sh help`

## Understanding the Builds

-   **Development Build (`build-dev`):** This is for your day-to-day testing. It compiles the application and copies all necessary assets (icons, backgrounds) into the `dist` folder to create a runnable test version. It's faster after the first run because it uses a cache and, crucially, it **preserves your existing `config.json` and `options.json`** so you don't lose your settings. It launches the app automatically after building.

-   **Final Release Build (`build-final`):** Use this only when you want to create a clean package for distribution. It wipes the `dist` and `build` folders to ensure a perfectly clean build from scratch. The final `dist` folder contains the executable and all necessary files, ready to be zipped and shared.

---

### A Note on "Start on Boot"

The "Start on Boot" feature works when running from source, but it's important to understand how.

-   **How it works:** When enabled in the app's settings while running from source, it uses the scripts located in `Windows_and_Linux/scripts/batch/`. This will cause a terminal/console window to appear on startup, which is normal. Closing this window will stop the application. This can be a useful way to debug the startup process.
-   **Switching Modes:** As the feature relies on specific file paths, the setting may not carry over correctly when you switch between a compiled `.exe` version and the source code version. It's good practice to **re-check the "Start on Boot" option** in the app's settings each time you switch modes.