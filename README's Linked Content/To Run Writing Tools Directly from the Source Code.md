# 👨‍💻 To Run Writing Tools Directly from the Source Code

If you prefer to run the program directly from the `main.py` file, follow these OS-specific instructions.

**1. Download the Code**
- Click the green `<> Code ▼` button toward the very top of this page, and click `Download ZIP`.

**2. Install Dependencies**  
After extracting the folder, open your **Terminal** (or **Command Prompt**) in the relevant directory.

- Windows:
   ```bash
   cd path\to\Windows_and_Linux
   py -m venv .venv
   .venv\Scripts\activate
   python -m pip install -r requirements.txt
   ```

- Linux:
   ```bash
   cd /path/to/Windows_and_Linux
   # Debian/Ubuntu only (one-time): install venv support
   sudo apt install -y python3-venv
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install -r requirements.txt
   ```
Of course, you'll need to have [Python installed](https://www.python.org/downloads/)!

**3. Run the Program**
- **Windows:**
   ```bash
   python main.py
   # Tip: If you want Writing Tools to remain running even after you close your Terminal window, run `pythonw main.py` instead of `python main.py`.

   ```

- **Linux:**
   ```bash
   python3 main.py
   ```

**Optional Linux desktop integration (manual/source install):**
```bash
cd /path/to/Windows_and_Linux
./install-local-linux.sh
```


### [**◀️ Back to main page**](https://github.com/theJayTea/WritingTools)
