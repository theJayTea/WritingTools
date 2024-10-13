import subprocess
import sys


def run_nuitka_build():
    nuitka_command = [
        "python", "-m", "nuitka",
        "--standalone",
        "--onefile",
        "--windows-disable-console",
        "--include-data-dir=icons=icons",
        "--include-data-file=background.png=background.png",
        "--include-data-file=background_popup.png=background_popup.png",
        "--plugin-enable=pyside6",
        "--windows-icon-from-ico=icons/app_icon.ico",
        "--output-dir=build",
        "--remove-output",
        "--show-progress",
        "--show-memory",
        "--assume-yes-for-downloads",
        "--follow-imports",
        "main.py"
    ]

    try:
        subprocess.run(nuitka_command, check=True)
        print("Build completed successfully!")
    except subprocess.CalledProcessError as e:
        print(f"Build failed with error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_nuitka_build()