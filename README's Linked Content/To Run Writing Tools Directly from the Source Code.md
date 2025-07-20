# 👨‍💻 To Run Writing Tools Directly from the Source Code

If you prefer to run the program directly from the `main.py` file, follow these OS-specific instructions.

**1. Download the Code**
- Click the green `<> Code ▼` button toward the very top of this page, and click `Download ZIP`.

**2.0 Automatic Method**
go to scripts `cd Windows_and_Linux/scripts/`
run `launch.bat` in Windows or `launch.sh` in Linux
This script can be used the first time. It will automatically create a virtual environment, activate it, install dependencies, and launch the program. 
You can still run it again later. It will check if the virtual environment already exists and activate it. If the dependencies have been installed, it will automatically launch the program.

**2.1 Manual Method**
- **Windows:**
   - Extract the downloaded ZIP file to a location of your choice.
   - Open your **Command Prompt** and navigate to the extracted folder.

**2. Create and Activate a Virtual Environment (recommanded)**  
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

**3. Install Dependencies**
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

**4. Run the Program**
- **Windows:**
   ```bash
   python main.py
   ```
- **Linux:**
   ```bash
   python3 main.py
   ```

**Note:** Remember to activate your virtual environment each time you want to run the program. If you close your terminal, you'll need to navigate back to the project directory and run the activation command again before running `main.py`.

### [**◀️ Back to main page**](https://github.com/theJayTea/WritingTools)