# 👨‍💻 To Run Writing Tools Directly from the Source Code

If you prefer to run the program directly from the `main.py` file, follow these OS-specific instructions.

**1. Download the Code**
Choose one of these methods:

- **ZIP Download:** Click the green `<> Code ▼` button toward the very top of this page, and click `Download ZIP`
- **Git Clone:** `git clone https://github.com/theJayTea/WritingTools.git`

**2. Launch Methods**

### **2.1 Recommended Method: The Task Runner**

The new, preferred way to run the application is by using the unified task runner script. This script handles everything for you, from setting up the environment to launching the app.

1.  Navigate to the `Windows_and_Linux` directory.
2.  Run the script for your OS:
    -   **Windows:** `run.bat`
    -   **Linux/macOS:** `./run.sh`

This will open an interactive menu. Just choose "Run Development Mode".

For a complete guide on using the task runner, including direct commands, **[see the new Development Workflow documentation.](./Development%20Workflow.md)**

---

### **2.2 Legacy Launch Methods**

Go to the scripts directory:

```bash
cd Windows_and_Linux/scripts/
```

Then run the unified Python launcher:

- **Windows:** `python launch.py` or double-click `launch.py`
- **Linux:** `python3 launch.py`

This script works on both Windows and Linux and will automatically:

- Create a virtual environment if needed
- Use the Python interpreter from the virtual environment
- Install/verify dependencies
- Launch the program

You can run it again later - it will check if the virtual environment already exists, activate it, verify dependencies, and launch the program automatically.

**Note:** This replaces the previous `launch.bat` and `launch.sh` scripts with a unified cross-platform Python solution.

### **2.3 Manual Method**

**Step 1: Extract and Navigate**

- **Windows:**
  - Extract the downloaded ZIP file to a location of your choice.
  - Open your **Command Prompt** and navigate to the extracted folder.
- **Linux:**
  - Extract the downloaded ZIP file to a location of your choice.
  - Open your **Terminal** and navigate to the extracted folder.

**Step 2: Create and Activate a Virtual Environment (Recommended)**  
After extracting the folder, open your **Terminal** (or **Command Prompt**) in the relevant directory.

- **Windows:**

  ```bash
  cd path\to\Windows_and_Linux

  # Install virtualenv if you haven't already
  pip install virtualenv

  # Create a new virtual environment
  virtualenv myvenv

  # Activate it
  myvenv\Scripts\activate
  ```

- **Linux:**

  ```bash
  cd /path/to/Windows_and_Linux

  # Install virtualenv if you haven't already (use pip3 on some systems)
  pip3 install virtualenv

  # Create a new virtual environment
  virtualenv myvenv

  # Activate it
  source myvenv/bin/activate
  ```

**Step 3: Install Dependencies**
Once the virtual environment is activated, install the required packages:

- **Windows:**

  ```bash
  pip install -r requirements.txt
  ```

- **Linux:**
  ```bash
  pip3 install -r requirements.txt
  ```

Of course, you'll need to have [Python installed](https://www.python.org/downloads/)!

**Step 4: Run the Program**

- **Windows:**
  ```bash
  python main.py
  ```
- **Linux:**
  ```bash
  python3 main.py
  ```

**Note:** Remember to activate your virtual environment each time you want to run the program. If you close your terminal, you'll need to navigate back to the project directory and run the activation command again before running `main.py`.

## **3. Start on Boot Feature**

When running from source code, you have access to the "**Start on boot**" option in the program's interface. When this option is checked:

- **Windows:** The `scripts/batch/launch.bat` script will automatically run at system startup
- **Linux:** The `scripts/batch/launch.sh` script will automatically run at system startup

These batch/shell scripts ensure Writing Tools starts automatically when your system boots, using the proper virtual environment setup. They call the main `launch.py` script with the correct working directory.

**Note:** When starting automatically, a console/terminal window will remain open during execution - this is normal behavior for source code execution. Closing this window will stop Writing Tools.

## **4. Troubleshooting**

**Common Issues:**

- **Virtual environment not found:** Re-run `python launch.py` or manually recreate the virtual environment
- **Dependencies missing:** Delete the `myvenv` folder and re-run `python launch.py`
- **Console window appears:** This is normal when running from source code, especially with "Start on boot" enabled
- **Python not found:** Make sure Python 3 is installed and accessible via `python` or `python3` command

**For Advanced Users:**
The AutostartManager is located at `Windows_and_Linux\ui\AutostartManager.py` and includes diagnostic tools for troubleshooting startup issues. You can run it directly to get debug information and test autostart functionality.
