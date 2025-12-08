import logging
import threading
import time
from urllib.error import HTTPError
from urllib.request import URLError, urlopen

CURRENT_VERSION = 8
UPDATE_CHECK_URL = "https://raw.githubusercontent.com/theJayTea/WritingTools/main/Windows_and_Linux/Latest_Version_for_Update_Check.txt"
UPDATE_DOWNLOAD_URL = "https://github.com/theJayTea/WritingTools/releases"

class UpdateChecker:
    def __init__(self, app):
        self.app = app
        
    def _fetch_latest_version(self):
        """
        Fetch the latest version number from GitHub.
        Returns the version number or None if failed.
        """
        try:
            with urlopen(UPDATE_CHECK_URL, timeout=5) as response:
                data = response.read().decode('utf-8').strip()
                try:
                    return int(data)
                except ValueError:
                    logging.warning(f"Invalid version number format: {data}")
                    return None
        except (URLError, HTTPError) as e:
            logging.warning(f"Failed to fetch version info: {e}")
            return None
        except Exception as e:
            logging.error(f"Unexpected error checking for updates: {e}")
            return None

    def _retry_fetch_version(self):
        """
        Attempt to fetch version with one retry.
        """
        result = self._fetch_latest_version()
        if result is None:
            # Wait 2 seconds before retry
            time.sleep(2)
            result = self._fetch_latest_version()
        return result

    def check_updates(self):
        """
        Check if an update is available. 
        Always checks against cloud value and updates config accordingly.
        Returns True if an update is available.
        """
        latest_version = self._retry_fetch_version()
        
        if latest_version is None:
            return False
            
        update_available = latest_version > CURRENT_VERSION
        
        # Always update config with fresh status
        if "update_available" in self.app.config or update_available:
            self.app.config["update_available"] = update_available
            self.app.save_config(self.app.config)
            
        return update_available

    def check_updates_async(self):
        """
        Perform the update check in a background thread.
        """
        def check_thread():
            self.check_updates()
            
        thread = threading.Thread(target=check_thread, daemon=True)
        thread.start()