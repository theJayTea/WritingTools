import logging
import sys
import os

if sys.platform.startswith("win32"):
    import winreg

class AutostartManager:
    """
    Manages the autostart functionality for Writing Tools.
    Handles setting/removing autostart registry entries on Windows and desktop files on Linux.
    """

    @staticmethod
    def is_compiled():
        """
        Check if we're running from a compiled exe or source.
        Enhanced detection for various compilation methods.
        """
        # PyInstaller detection
        if hasattr(sys, 'frozen') and hasattr(sys, '_MEIPASS'):
            return True
        
        # Alternative detection methods
        if getattr(sys, 'frozen', False):
            return True
            
        # Check if sys.executable points to a Python interpreter
        exe_name = os.path.basename(sys.executable).lower()
        if exe_name.startswith('python'):
            return False
            
        # If executable ends with .exe or doesn't contain "python", likely compiled
        if sys.executable.endswith('.exe') or 'python' not in exe_name:
            return True
            
        return False

    @staticmethod
    def is_script():
        """
        Detect if we're running from a .py script file.
        """
        import __main__
        if hasattr(__main__, '__file__') and __main__.__file__:
            return __main__.__file__.endswith('.py')
        return False

    @staticmethod
    def get_startup_path():
        """
        Get the path that should be used for autostart.
        Returns the appropriate path for Windows (exe or script) or Linux (script).
        """
        if sys.platform.startswith('win32'):
            if AutostartManager.is_compiled():
                # Compiled version - use executable path
                return sys.executable
            else:
                # Development version - use batch script for autostart
                script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                batch_path = os.path.join(script_dir, 'scripts', 'batch', 'launch.bat')
                if os.path.exists(batch_path):
                    return batch_path
                return None
                
        elif sys.platform.startswith('linux'):
            if AutostartManager.is_compiled():
                # Compiled version - use binary executable
                return sys.executable
            else:
                # Development version - use shell script for autostart
                script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                launch_script = os.path.join(script_dir, 'scripts', 'batch', 'launch.sh')
                if os.path.exists(launch_script):
                    # Make sure the script is executable
                    os.chmod(launch_script, 0o755)
                    return launch_script
                else:
                    # Fallback: direct python execution
                    main_py = os.path.join(script_dir, 'main.py')
                    if os.path.exists(main_py):
                        return f'bash -c "cd {script_dir} && python3 main.py"'
                return None
        else:
            return None

    @staticmethod
    def _get_linux_desktop_file_path():
        """
        Get the path for the Linux desktop file.
        """
        home = os.path.expanduser("~")
        autostart_dir = os.path.join(home, ".config", "autostart")
        return os.path.join(autostart_dir, "writing-tools.desktop")

    @staticmethod
    def set_autostart(enable: bool) -> bool:
        """
        Enable or disable autostart for Writing Tools.

        Args:
            enable: True to enable autostart, False to disable

        Returns:
            bool: True if operation succeeded, False if failed or unsupported
        """
        try:
            if sys.platform.startswith('win32'):
                startup_path = AutostartManager.get_startup_path()
                if not startup_path:
                    logging.error("Could not determine startup path for Windows")
                    return False
                return AutostartManager._set_windows_autostart(enable, startup_path)
                
            elif sys.platform.startswith('linux'):
                return AutostartManager._set_linux_autostart(enable)
            else:
                logging.warning(f"Autostart not supported on platform: {sys.platform}")
                return False

        except Exception as e:
            logging.error(f"Error managing autostart: {e}")
            return False

    @staticmethod
    def _set_windows_autostart(enable: bool, startup_path: str) -> bool:
        """
        Set Windows autostart using registry.
        """
        try:
            key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"

            if enable:
                # Open/create key and set value
                key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0,
                                   winreg.KEY_WRITE)
                winreg.SetValueEx(key, "WritingTools", 0, winreg.REG_SZ,
                                startup_path)
                logging.info(f"Windows autostart enabled with path: {startup_path}")
            else:
                # Open key and delete value if it exists
                key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0,
                                   winreg.KEY_WRITE)
                try:
                    winreg.DeleteValue(key, "WritingTools")
                    logging.info("Windows autostart disabled")
                except WindowsError:
                    # Value doesn't exist, that's fine
                    logging.info("Windows autostart was already disabled")

            winreg.CloseKey(key)
            return True

        except WindowsError as e:
            logging.error(f"Failed to modify autostart registry: {e}")
            return False

    @staticmethod
    def _set_linux_autostart(enable: bool) -> bool:
        """
        Set Linux autostart using desktop file.
        """
        try:
            desktop_file_path = AutostartManager._get_linux_desktop_file_path()
            
            if enable:
                # Create autostart directory if it doesn't exist
                autostart_dir = os.path.dirname(desktop_file_path)
                os.makedirs(autostart_dir, exist_ok=True)

                # Get the appropriate execution command
                if AutostartManager.is_compiled():
                    # For compiled binary
                    exec_command = sys.executable
                    working_dir = os.path.dirname(sys.executable)
                else:
                    # For development version with shell script
                    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                    launch_script = os.path.join(script_dir, 'scripts', 'batch', 'launch.sh')

                    if os.path.exists(launch_script):
                        # Make sure the script is executable
                        os.chmod(launch_script, 0o755)
                        exec_command = f'bash "{launch_script}"'
                        working_dir = script_dir
                    else:
                        # Fallback to direct python execution
                        main_py = os.path.join(script_dir, 'main.py')
                        if os.path.exists(main_py):
                            exec_command = f'bash -c "cd {script_dir} && python3 main.py"'
                            working_dir = script_dir
                        else:
                            logging.error("Could not find launch script or main.py for Linux autostart")
                            return False

                # Create desktop file content
                desktop_content = f"""[Desktop Entry]
Type=Application
Name=Writing Tools
Comment=AI-powered writing assistant
Exec={exec_command}
Path={working_dir}
Icon=text-editor
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
"""

                # Write desktop file
                with open(desktop_file_path, 'w') as f:
                    f.write(desktop_content)

                # Make it executable
                os.chmod(desktop_file_path, 0o755)
                logging.info(f"Linux autostart enabled with desktop file: {desktop_file_path}")

            else:
                # Remove desktop file if it exists
                if os.path.exists(desktop_file_path):
                    os.remove(desktop_file_path)
                    logging.info("Linux autostart disabled - desktop file removed")
                else:
                    logging.info("Linux autostart was already disabled")

            return True

        except Exception as e:
            logging.error(f"Failed to modify Linux autostart: {e}")
            return False

    @staticmethod
    def check_autostart() -> bool:
        """
        Check if Writing Tools is set to start automatically.

        Returns:
            bool: True if autostart is enabled, False if disabled or unsupported
        """
        try:
            if sys.platform.startswith('win32'):
                return AutostartManager._check_windows_autostart()
            elif sys.platform.startswith('linux'):
                return AutostartManager._check_linux_autostart()
            else:
                return False

        except Exception as e:
            logging.error(f"Error checking autostart status: {e}")
            return False

    @staticmethod
    def _check_windows_autostart() -> bool:
        """
        Check Windows autostart status.
        """
        try:
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                               r"Software\Microsoft\Windows\CurrentVersion\Run",
                               0, winreg.KEY_READ)
            value, _ = winreg.QueryValueEx(key, "WritingTools")
            winreg.CloseKey(key)

            # Get current startup path for comparison
            current_startup_path = AutostartManager.get_startup_path()
            if not current_startup_path:
                return False

            # Check if the stored path matches our current startup path
            return value.lower() == current_startup_path.lower()

        except WindowsError:
            # Key or value doesn't exist
            return False

    @staticmethod
    def _check_linux_autostart() -> bool:
        """
        Check Linux autostart status.
        """
        desktop_file_path = AutostartManager._get_linux_desktop_file_path()
        return os.path.exists(desktop_file_path)

    @staticmethod
    def get_debug_info():
        """
        Get debug information about the current environment.
        Useful for troubleshooting autostart issues.
        """
        info = {
            'platform': sys.platform,
            'is_compiled': AutostartManager.is_compiled(),
            'is_script': AutostartManager.is_script(),
            'sys_executable': sys.executable,
            'startup_path': AutostartManager.get_startup_path(),
            'autostart_enabled': AutostartManager.check_autostart(),
        }
        
        if sys.platform.startswith('linux'):
            info['desktop_file_path'] = AutostartManager._get_linux_desktop_file_path()
            
        return info


# Example usage
if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
    
    manager = AutostartManager()
    
    # Print debug information
    debug_info = manager.get_debug_info()
    print("=== AutostartManager Debug Info ===")
    for key, value in debug_info.items():
        print(f"{key}: {value}")
    
    print("\n=== Testing autostart functionality ===")
    
    # Test enabling autostart
    print("Enabling autostart...")
    if manager.set_autostart(True):
        print("Autostart enabled successfully")
    else:
        print("Failed to enable autostart")
    
    # Check status
    print(f"Autostart status: {'Enabled' if manager.check_autostart() else 'Disabled'}")