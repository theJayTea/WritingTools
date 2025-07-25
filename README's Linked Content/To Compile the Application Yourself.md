# 👨‍💻 To compile the application yourself:

### Windows and Linux Version build instructions:

### **Recommended Method: The Task Runner**

The new, preferred way to compile the application is by using the unified task runner script. This script handles everything for you, from setting up the environment to running the correct build process.

1.  Navigate to the `Windows_and_Linux` directory.
2.  Run the script for your OS:
    - **Windows:** `run.bat`
    - **Linux/macOS:** `./run.sh`
3.  From the interactive menu, choose either the "Development Build" or "Final Release Build".

Alternatively, you can run the build directly with a command:

- **Development Build:** `run.bat build-dev`
- **Final Build:** `run.bat build-final`

For a complete guide on using the task runner and the differences between the builds, **[see the new Development Workflow documentation.](./Development%20Workflow.md)**

---

### **Legacy Build Methods**

If you prefer to run the build steps manually, you can use the methods below.

**Direct Python Script Execution:**

Navigate to the `Windows_and_Linux` directory and run:

```bash
# For development build (faster, preserves settings)
python scripts/dev-build.py

# For final release build
python scripts/final-build.py
```

Both scripts automatically:

- Set up the virtual environment
- Install dependencies
- Build the application with PyInstaller
- Copy required files

**Key Differences:**

- **Development build**: Preserves your existing configuration files (config.json) and launches the app automatically
- **Final build**: Creates a clean release version without user configurations, ready for distribution

### macOS Version (by [Aryamirsepasi](https://github.com/Aryamirsepasi)) build instructions:

1. **Install Xcode**

   - Download and install Xcode from the App Store
   - Launch Xcode once installed and complete any additional component installations

2. **Clone the Repository**

   - Open Terminal and navigate to the directory where you want to store the project:

   ```bash
   git clone https://github.com/theJayTea/WritingTools.git
   ```

3. **Open in Xcode**

   - Open Xcode
   - Select "Open an existing project..." from the options.
   - Navigate to the macOS folder within the WritingTools directory that you cloned previously, and select "writing-tools.xcodeproj"

4. **Configure Project Settings**

   - In Xcode, select the project in the Navigator pane.
   - Under "Targets", select "writing-tools"
   - Set the following:
     - Deployment Target: macOS 14.0
     - Signing & Capabilities: Add your development team

5. **Build and Run**
   - In Xcode, select "My Mac" as the run destination
   - Click the Play button or press ⌘R to build and run

### [**◀️ Back to main page**](https://github.com/theJayTea/WritingTools)
