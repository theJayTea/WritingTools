import logging
import sys
import os

from WritingToolApp import WritingToolApp

# Set up logging to console
logging.basicConfig(
    level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s"
)


def terminate_existing_instances():
    """Terminate any existing Writing Tools instances before starting"""
    try:
        # Import the utility function
        scripts_dir = os.path.join(os.path.dirname(__file__), "scripts")
        if os.path.exists(scripts_dir):
            sys.path.insert(0, scripts_dir)
            from utils import terminate_existing_processes

            # Get current process ID to avoid terminating ourselves
            current_pid = os.getpid()

            # Only terminate exe instances, not script instances (to avoid self-termination)
            terminate_existing_processes(exe_name="Writing Tools.exe", script_name=None)
            sys.path.remove(scripts_dir)
    except Exception as e:
        # If termination fails, log but continue
        logging.warning(f"Could not terminate existing instances: {e}")


def main():
    """
    The main entry point of the application.
    """
    # Terminate any existing instances first
    terminate_existing_instances()

    app = WritingToolApp(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
