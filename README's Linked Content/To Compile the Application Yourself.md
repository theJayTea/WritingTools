# 👨‍💻 To compile the application yourself:

### Windows and Linux Version build instructions:
Here's how to compile it with PyInstaller and a virtual environment:

1. First, create and activate a virtual environment:
```bash
# Debian/Ubuntu only (one-time): install venv support
sudo apt install -y python3-venv

# Create a new virtual environment
python3 -m venv .venv

# Activate it
# On Windows:
.venv\Scripts\activate
# On Linux:
source .venv/bin/activate
```

2. Once activated, install the required packages:

```bash
python -m pip install -r requirements.txt
```

3. Build Writing Tools:
```bash
python pyinstaller-build-script.py
```

4. (Linux optional) Build a Debian package:

Install nFPM first (one-time) using the official installation instructions:
https://nfpm.goreleaser.com/docs/install/

```bash
# Build .deb (outputs to packaging/dist/)
./build-deb.sh

# Install it
sudo apt install ./packaging/dist/*.deb
```

5. (Linux optional) Manual source install without `.deb`:
```bash
./install-local-linux.sh
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