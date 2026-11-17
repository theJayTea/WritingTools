import logging
import sys

if sys.platform.startswith("win32"):
    import winreg

class AutostartManager:
    """
    Manages the autostart functionality for Writing Tools.
    Handles setting/removing autostart registry entries on Windows.
    """
    
    @staticmethod
    def is_compiled():
        """
        Check if we're running from a compiled exe or source.
        """
        return hasattr(sys, 'frozen') and hasattr(sys, '_MEIPASS')

    @staticmethod
    def get_startup_path():
        """
        Get the path that should be used for autostart.
        Returns None if running from source or on non-Windows.
        """
        if not sys.platform.startswith('win32'):
            return None
            
        if not AutostartManager.is_compiled():
            return None
            
        return sys.executable

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
            startup_path = AutostartManager.get_startup_path()
            if not startup_path:
                return False

            key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
            
            try:
                if enable:
                    # Open/create key and set value
                    key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, 
                                       winreg.KEY_WRITE)
                    winreg.SetValueEx(key, "WritingTools", 0, winreg.REG_SZ, 
                                    startup_path)
                else:
                    # Open key and delete value if it exists
                    key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0,
                                       winreg.KEY_WRITE)
                    try:
                        winreg.DeleteValue(key, "WritingTools")
                    except WindowsError:
                        # Value doesn't exist, that's fine
                        pass
                        
                winreg.CloseKey(key)
                return True
                
            except WindowsError as e:
                logging.error(f"Failed to modify autostart registry: {e}")
                return False
                
        except Exception as e:
            logging.error(f"Error managing autostart: {e}")
            return False

    @staticmethod
    def check_autostart() -> bool:
        """
        Check if Writing Tools is set to start automatically.
        
        Returns:
            bool: True if autostart is enabled, False if disabled or unsupported
        """
        try:
            startup_path = AutostartManager.get_startup_path()
            if not startup_path:
                return False

            try:
                key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, 
                                   r"Software\Microsoft\Windows\CurrentVersion\Run",
                                   0, winreg.KEY_READ)
                value, _ = winreg.QueryValueEx(key, "WritingTools")
                winreg.CloseKey(key)
                
                # Check if the stored path matches our current exe
                return value.lower() == startup_path.lower()
                
            except WindowsError:
                # Key or value doesn't exist
                return False
                
        except Exception as e:
            logging.error(f"Error checking autostart status: {e}")
            return False