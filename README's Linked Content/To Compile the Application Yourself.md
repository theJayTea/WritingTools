# 👨‍💻 To compile the application yourself:

### Windows and Linux Version build instructions:
Here's how to compile it with PyInstaller and a virtual environment:

1. First, create and activate a virtual environment:
```bash
# Install virtualenv if you haven't already
pip install virtualenv

# Create a new virtual environment
virtualenv myvenv

# Activate it
# On Windows:
myvenv\Scripts\activate
# On Linux:
source myvenv/bin/activate
```

2. Once activated, install the required packages:

```bash
pip install -r requirements.txt
```

3. Build Writing Tools:
```bash
python pyinstaller-build-script.py
```

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