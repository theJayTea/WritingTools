import os
import subprocess

def run_pyinstaller_build():
    pyinstaller_command = [
        "pyinstaller",
        "--onefile",
        "--windowed",
        "--icon=icons/app_icon.ico",
        "main.py"
    ]

    try:
        os.system("rmdir /s /q dist")

        subprocess.run(pyinstaller_command, check=True)
        print("Build completed successfully!")

        os.rename("dist/main.exe", "dist/Writing Tools.exe")

        os.system("mkdir dist\\icons")

        os.system("copy /Y *.png dist")
        os.system("copy /Y icons\\*.* dist\\icons")

        os.system("powershell Compress-Archive -Path dist -DestinationPath 'dist\\Writing Tools.zip'")

    except subprocess.CalledProcessError as e:
        print(f"Build failed with error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_pyinstaller_build()
