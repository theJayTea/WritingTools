from .gui_backend import GUIBackend
import subprocess
import json
import os
import asyncio
from dbus_next.aio import MessageBus
from dbus_next import BusType


class WaylandBackend(GUIBackend):
    def get_active_window_title(self) -> str:
        """
        Try compositor-specific methods in order:
        1. wlroots-based (Sway, Hyprland, Labwc) via wlrctl
        2. KDE Plasma via multiple KDE methods
        3. GNOME (Mutter) via D-Bus extension + cache file
        4. Cinnamon via D-Bus
        5. XFCE via xfconf-query (if running on Wayland)
        6. i3/Sway via swaymsg (alternative to wlrctl)
        7. River via riverctl
        8. Wayfire via wayfire socket
        9. Fallback placeholder
        """

        # 1) wlroots-based: wlrctl
        try:
            out = subprocess.run(
                ["wlrctl", "toplevel", "list", "--json"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            tops = json.loads(out)
            for t in tops:
                if t.get("state") == "activated":
                    return t.get("title", "<Wayland>")
        except Exception:
            pass

        # 2) KDE Plasma: Multiple methods
        kde_title = self._get_kde_title()
        if kde_title:
            return kde_title

        # 3) GNOME (Mutter): D-Bus extension + cache file
        try:
            title = asyncio.get_event_loop().run_until_complete(self._get_gnome_title())
            if title:
                return title
        except Exception:
            pass

        # 4) Cinnamon: D-Bus method
        cinnamon_title = self._get_cinnamon_title()
        if cinnamon_title:
            return cinnamon_title

        # 5) XFCE: Check if XFCE is running on Wayland
        xfce_title = self._get_xfce_title()
        if xfce_title:
            return xfce_title

        # 6) Sway/i3: swaymsg (alternative to wlrctl)
        sway_title = self._get_sway_title()
        if sway_title:
            return sway_title

        # 7) River: riverctl
        river_title = self._get_river_title()
        if river_title:
            return river_title

        # 8) Wayfire: wayfire socket
        wayfire_title = self._get_wayfire_title()
        if wayfire_title:
            return wayfire_title

        # 9) Fallback
        return "<Wayland>"

    def _get_kde_title(self) -> str:
        """Try multiple KDE methods"""
        # Method 1: kwin5 CLI
        try:
            win_id = subprocess.run(
                ["kwin5", "activewindow"], capture_output=True, text=True, check=True
            ).stdout.strip()
            title = subprocess.run(
                ["kwin5", "windowtitle", win_id],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            return title or None
        except Exception:
            pass

        # Method 2: qdbus KWin interface
        try:
            title = subprocess.run(
                ["qdbus", "org.kde.KWin", "/KWin", "org.kde.KWin.activeWindowTitle"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            return title or None
        except Exception:
            pass

        # Method 3: kwin_wayland D-Bus
        try:
            title = subprocess.run(
                ["qdbus", "org.kde.kwin", "/KWin", "activeWindowTitle"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            return title or None
        except Exception:
            pass

        return None

    def _get_cinnamon_title(self) -> str:
        """Cinnamon desktop environment"""
        try:
            # Check if Cinnamon is running
            if "cinnamon" not in os.environ.get("XDG_CURRENT_DESKTOP", "").lower():
                return None

            # Use D-Bus to get window info from Cinnamon
            result = subprocess.run(
                [
                    "gdbus",
                    "call",
                    "--session",
                    "--dest",
                    "org.Cinnamon",
                    "--object-path",
                    "/org/Cinnamon",
                    "--method",
                    "org.Cinnamon.GetActiveWindow",
                ],
                capture_output=True,
                text=True,
                check=True,
            )

            if result.stdout.strip():
                # Parse the result (usually returns window title)
                return result.stdout.strip().strip("()").strip("'\"") or None
        except Exception:
            pass
        return None

    def _get_xfce_title(self) -> str:
        """XFCE desktop environment"""
        try:
            # Check if XFCE is running
            desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
            if "xfce" not in desktop:
                return None

            # XFCE on Wayland is rare, but try xfconf-query
            result = subprocess.run(
                ["xfconf-query", "-c", "xfwm4", "-p", "/general/active_window_title"],
                capture_output=True,
                text=True,
                check=True,
            )

            return result.stdout.strip() or None
        except Exception:
            pass
        return None

    def _get_sway_title(self) -> str:
        """Sway window manager (alternative to wlrctl)"""
        try:
            result = subprocess.run(
                ["swaymsg", "-t", "get_tree"],
                capture_output=True,
                text=True,
                check=True,
            )
            tree = json.loads(result.stdout)

            def find_focused(node):
                if node.get("focused"):
                    return node
                for child in node.get("nodes", []) + node.get("floating_nodes", []):
                    found = find_focused(child)
                    if found:
                        return found
                return None

            focused = find_focused(tree)
            return focused.get("name") if focused else None
        except Exception:
            pass
        return None

    def _get_river_title(self) -> str:
        """River window manager"""
        try:
            # River uses riverctl for control
            result = subprocess.run(
                ["riverctl", "list-focused-tags"],
                capture_output=True,
                text=True,
                check=True,
            )

            # This is a simplified approach - River's API is more complex
            # You might need to implement a more sophisticated method
            if result.stdout.strip():
                return f"River-{result.stdout.strip()}"
        except Exception:
            pass
        return None

    def _get_wayfire_title(self) -> str:
        """Wayfire compositor"""
        try:
            # Wayfire has a socket-based API
            wayfire_socket = os.environ.get("WAYFIRE_SOCKET")
            if not wayfire_socket:
                return None

            # Use wayfire's IPC (if available)
            result = subprocess.run(
                ["wayfire-socket-client", "get-active-window"],
                capture_output=True,
                text=True,
                check=True,
            )

            return result.stdout.strip() or None
        except Exception:
            pass
        return None

    async def _get_gnome_title(self) -> str:
        """
        Call the 'Activate Window By Title' GNOME Shell extension to refresh
        the cache file, then read ~/.cache/active_window_title.
        """
        try:
            bus = await MessageBus(bus_type=BusType.SESSION).connect()
            proxy = await bus.get_proxy_object(
                "org.gnome.Shell",
                "/de/lucaswerkmeister/ActivateWindowByTitle",
                interface_names=["de.lucaswerkmeister.ActivateWindowByTitle"],
            )
            iface = proxy.get_interface("de.lucaswerkmeister.ActivateWindowByTitle")
            # Trigger an update by calling a no-op method
            await iface.call_activateBySubstring("")

            cache = os.path.expanduser("~/.cache/active_window_title")
            if os.path.exists(cache):
                with open(cache, "r", encoding="utf-8") as f:
                    return f.read().strip()
        except Exception:
            pass
        return ""

    def get_selected_text(self) -> str:
        """
        Capture highlighted text via wl-paste (primary selection) on Wayland.
        Works universally across all Wayland compositors.
        """
        try:
            return subprocess.run(
                ["wl-paste", "--primary"], capture_output=True, text=True, check=True
            ).stdout
        except subprocess.CalledProcessError:
            return subprocess.run(
                ["wl-paste"], capture_output=True, text=True, check=True
            ).stdout

    def paste_text(self, text: str) -> bool:
        """
        Paste text to the active window on Wayland.
        Uses multiple fallback methods since Wayland has security restrictions.
        Focuses on setting clipboard reliably and providing user feedback.
        """
        import pyperclip
        import time
        import threading
        import subprocess

        print(f"DEBUG: Starting Wayland paste for text length: {len(text)}")

        # Backup current clipboard
        try:
            clipboard_backup = pyperclip.paste()
        except Exception as e:
            print(f"DEBUG: Failed to backup clipboard: {e}")
            clipboard_backup = ""

        success = False

        try:
            # Primary method: Use pyperclip (most reliable cross-platform)
            print("DEBUG: Setting clipboard with pyperclip")
            pyperclip.copy(text)
            time.sleep(0.5)  # Extra delay for Wayland clipboard synchronization

            # Verify clipboard was set correctly
            try:
                current_clipboard = pyperclip.paste()
                if text in current_clipboard:
                    print("DEBUG: Clipboard set successfully")
                    success = True
                else:
                    print("DEBUG: Clipboard verification failed")
            except Exception as e:
                print(f"DEBUG: Clipboard verification error: {e}")
                success = True  # Assume it worked if we can't verify

            # Try to trigger paste using keyboard simulation (best effort)
            # This may not work on all Wayland compositors due to security restrictions
            try:
                self._simulate_paste_best_effort()
            except Exception as e:
                print(
                    f"DEBUG: Paste simulation failed (expected on some Wayland setups): {e}"
                )
                # This is expected on some Wayland setups, so don't fail the whole operation

        except Exception as e:
            print(f"DEBUG: Main paste method failed: {e}")

        finally:
            # Restore original clipboard content
            try:
                if clipboard_backup:
                    pyperclip.copy(clipboard_backup)
                    print("DEBUG: Restored clipboard backup")
            except Exception as e:
                print(f"DEBUG: Failed to restore clipboard: {e}")

        print(f"DEBUG: Wayland paste completed with success={success}")
        return success

    def _simulate_paste_best_effort(self):
        """
        Attempt paste simulation with multiple fallback methods.
        Designed to fail gracefully and not hang the application.
        """
        import subprocess
        import time
        import threading
        import os

        print("DEBUG: Attempting paste simulation (best effort)")

        # Determine method order based on desktop environment
        methods = []

        # Check if we're running on KDE
        if os.environ.get("XDG_CURRENT_DESKTOP", "").lower() == "kde":
            print("DEBUG: Running on KDE, prioritizing Wayland input tools")
            methods = [
                # Method 1: Try ydotool first (most comprehensive)
                lambda: self._try_ydotool_paste(),
                # Method 2: Try dotool (alternative)
                lambda: self._try_dotool_paste(),
                # Method 3: Try enhanced wtype methods
                lambda: self._try_enhanced_wtype_paste(),
                # Method 4: Try KDE-specific methods
                lambda: self._try_kde_specific_paste(),
                # Method 5: Try ydot (another Wayland input method)
                lambda: self._try_subprocess_command(["ydot", "paste"]),
                # Method 6: Try pykeyboard as final fallback
                lambda: self._try_pykeyboard_paste(),
            ]
        else:
            # Non-KDE Wayland compositors
            methods = [
                # Method 1: Try ydotool first (most comprehensive)
                lambda: self._try_ydotool_paste(),
                # Method 2: Try dotool (alternative)
                lambda: self._try_dotool_paste(),
                # Method 3: Try enhanced wtype methods
                lambda: self._try_enhanced_wtype_paste(),
                # Method 4: Try KDE-specific methods (just in case)
                lambda: self._try_kde_specific_paste(),
                # Method 5: Try ydot (another Wayland input method)
                lambda: self._try_subprocess_command(["ydot", "paste"]),
                # Method 6: Try pykeyboard as final fallback
                lambda: self._try_pykeyboard_paste(),
            ]

        # Try each method with timeout
        for i, method in enumerate(methods):
            print(f"DEBUG: Trying paste method {i + 1}")

            # Run method in thread with timeout to prevent hanging
            thread = threading.Thread(target=method)
            thread.daemon = True
            thread.start()
            thread.join(timeout=3)  # Max 3 seconds per method

            if not thread.is_alive():
                print(f"DEBUG: Paste method {i + 1} completed")
                time.sleep(0.3)  # Extra delay after successful attempt
                return
            else:
                print(f"DEBUG: Paste method {i + 1} timed out or hung")

        print("DEBUG: All paste methods completed (best effort)")

    def _try_enhanced_wtype_paste(self):
        """
        Try enhanced wtype methods with multiple approaches.
        """
        import subprocess
        import time

        print("DEBUG: Trying enhanced wtype paste")

        # First check if compositor supports virtual keyboard protocol
        try:
            result = subprocess.run(["wtype", "--help"], capture_output=True, timeout=2)
            # If wtype runs without error, compositor might support it
        except Exception as e:
            print(
                f"DEBUG: wtype not available or compositor doesn't support virtual keyboard: {e}"
            )
            return False

        # Multiple wtype approaches
        wtype_methods = [
            # Method 1: Simple ctrl+v
            ["wtype", "-P", "ctrl+v"],
            # Method 2: More explicit key sequence
            ["wtype", "-P", "ctrl", "v"],
            # Method 3: With delays between keys
            ["wtype", "-d", "50", "-P", "ctrl+v"],
            # Method 4: Individual key presses with delays
            ["wtype", "-d", "100", "ctrl_l", "v"],
            # Method 5: Alternative syntax
            ["wtype", "--paste", "ctrl+v"],
        ]

        for i, cmd in enumerate(wtype_methods):
            try:
                print(f"DEBUG: Trying wtype method {i + 1}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode == 0:
                    print(f"DEBUG: wtype method {i + 1} succeeded")
                    time.sleep(0.2)  # Give time for the paste to complete
                    return True
                else:
                    print(
                        f"DEBUG: wtype method {i + 1} failed with return code {result.returncode}"
                    )
                    if result.stderr:
                        error_msg = result.stderr.decode().strip()
                        print(f"DEBUG: wtype stderr: {error_msg}")
                        if "virtual keyboard protocol" in error_msg:
                            print(
                                "DEBUG: Compositor doesn't support virtual keyboard protocol"
                            )
                            return False

            except FileNotFoundError:
                print("DEBUG: wtype not found, skipping")
                break
            except subprocess.TimeoutExpired:
                print(f"DEBUG: wtype method {i + 1} timed out")
            except Exception as e:
                print(f"DEBUG: wtype method {i + 1} failed: {e}")

        return False

    def _try_ydotool_paste(self):
        """
        Try ydotool for paste simulation - most comprehensive Wayland input tool.
        """
        import subprocess
        import time
        import os

        print("DEBUG: Trying ydotool paste")

        # Check if ydotool is available
        try:
            result = subprocess.run(["ydotool", "help"], capture_output=True, timeout=2)
            if result.returncode != 0:
                print("DEBUG: ydotool not found or not working")
                return False
        except Exception as e:
            print(f"DEBUG: ydotool check failed: {e}")
            return False

        # Check if ydotool daemon is running, start it if not
        socket_path = "/run/user/{}/.ydotool_socket".format(os.getuid())
        daemon_running = False

        try:
            # Check if socket exists
            if os.path.exists(socket_path):
                # Test if daemon is responsive
                test_result = subprocess.run(
                    ["ydotool", "debug"], capture_output=True, timeout=1
                )
                if test_result.returncode == 0:
                    daemon_running = True
                    print("DEBUG: ydotool daemon is already running")
            else:
                print("DEBUG: ydotool daemon not running, attempting to start it")
        except Exception as e:
            print(f"DEBUG: ydotool daemon check failed: {e}")

        # Start ydotool daemon if not running
        if not daemon_running:
            try:
                # Start daemon in background
                daemon_process = subprocess.Popen(
                    ["ydotoold"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                # Give daemon time to start
                time.sleep(0.5)
                print("DEBUG: ydotool daemon started")
                daemon_running = True
            except Exception as e:
                print(f"DEBUG: Failed to start ydotool daemon: {e}")
                return False

        # Multiple ydotool approaches
        ydotool_methods = [
            # Method 1: Simple key sequence
            ["ydotool", "key", "ctrl+v"],
            # Method 2: Individual key presses with delays
            ["ydotool", "key", "ctrl:1", "v:1", "ctrl:0", "v:0"],
            # Method 3: With explicit delays
            ["ydotool", "key", "--delay", "50", "ctrl+v"],
            # Method 4: Alternative syntax using type
            ["ydotool", "type", "--key", "ctrl+v"],
            # Method 5: Direct key sequence
            ["ydotool", "key", "--key", "ctrl+v"],
        ]

        for i, cmd in enumerate(ydotool_methods):
            try:
                print(f"DEBUG: Trying ydotool method {i + 1}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode == 0:
                    print(f"DEBUG: ydotool method {i + 1} succeeded")
                    time.sleep(0.3)  # Extra delay for the paste to complete
                    return True
                else:
                    error_msg = (
                        result.stderr.decode().strip()
                        if result.stderr
                        else "unknown error"
                    )
                    print(f"DEBUG: ydotool method {i + 1} failed: {error_msg}")

                    # If daemon died, try to restart it once
                    if "failed to connect socket" in error_msg and i == 0:
                        print(
                            "DEBUG: ydotool daemon connection lost, attempting to restart"
                        )
                        try:
                            # Kill any existing daemon
                            subprocess.run(
                                ["pkill", "-f", "ydotoold"], capture_output=True
                            )
                            time.sleep(0.2)

                            # Start new daemon
                            subprocess.Popen(
                                ["ydotoold"],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                            )
                            time.sleep(0.5)
                            print("DEBUG: ydotool daemon restarted")
                        except Exception as e:
                            print(f"DEBUG: Failed to restart ydotool daemon: {e}")

            except subprocess.TimeoutExpired:
                print(f"DEBUG: ydotool method {i + 1} timed out")
            except Exception as e:
                print(f"DEBUG: ydotool method {i + 1} failed: {e}")

        return False

    def _try_dotool_paste(self):
        """
        Try dotool for paste simulation.
        """
        import subprocess
        import time

        print("DEBUG: Trying dotool paste")

        # Check if dotool is available
        try:
            result = subprocess.run(
                ["dotool", "--help"], capture_output=True, timeout=2
            )
            if result.returncode != 0:
                print("DEBUG: dotool not found")
                return False
        except Exception as e:
            print(f"DEBUG: dotool check failed: {e}")
            return False

        # Multiple dotool approaches
        dotool_methods = [
            # Method 1: Simple key sequence
            ["dotool", "key", "ctrl+v"],
            # Method 2: Individual keys
            ["dotool", "key", "ctrl", "v"],
            # Method 3: With delays
            ["dotool", "key", "--delay", "50", "ctrl+v"],
        ]

        for i, cmd in enumerate(dotool_methods):
            try:
                print(f"DEBUG: Trying dotool method {i + 1}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode == 0:
                    print(f"DEBUG: dotool method {i + 1} succeeded")
                    time.sleep(0.2)
                    return True
                else:
                    print(
                        f"DEBUG: dotool method {i + 1} failed: {result.stderr.decode()[:100]}"
                    )

            except subprocess.TimeoutExpired:
                print(f"DEBUG: dotool method {i + 1} timed out")
            except Exception as e:
                print(f"DEBUG: dotool method {i + 1} failed: {e}")

        return False

    def _try_kde_specific_paste(self):
        """
        Try KDE-specific paste methods for KDE Wayland.
        KDE has its own tools and protocols that might work better.
        """
        import subprocess
        import time
        import os

        print("DEBUG: Trying KDE-specific paste methods")

        # Check if we're running on KDE
        if os.environ.get("XDG_CURRENT_DESKTOP", "").lower() != "kde":
            print("DEBUG: Not running on KDE, skipping KDE-specific methods")
            return False

        kde_methods = [
            # Method 1: Try kdotool first (KDE-specific tool)
            lambda: self._try_kdotool_paste(),
            # Method 2: Try using kwin's D-Bus interface
            lambda: self._try_kwin_dbuss_paste(),
            # Method 3: Try using qdbus directly
            lambda: self._try_qdbus_paste(),
        ]

        for i, method in enumerate(kde_methods):
            try:
                print(f"DEBUG: Trying KDE method {i + 1}")
                if method():
                    print(f"DEBUG: KDE method {i + 1} succeeded")
                    time.sleep(0.3)
                    return True
                else:
                    print(f"DEBUG: KDE method {i + 1} failed")

            except Exception as e:
                print(f"DEBUG: KDE method {i + 1} failed: {e}")

        return False

    def _try_kdotool_paste(self):
        """
        Try kdotool for paste simulation - KDE-specific Wayland input tool.
        """
        import subprocess
        import time

        print("DEBUG: Trying kdotool paste (KDE-specific)")

        # Check if kdotool is available
        try:
            result = subprocess.run(
                ["kdotool", "--help"], capture_output=True, timeout=2
            )
            if result.returncode != 0:
                print("DEBUG: kdotool not found or not working")
                return False
        except Exception as e:
            print(f"DEBUG: kdotool check failed: {e}")
            return False

        # Multiple kdotool approaches
        kdotool_methods = [
            # Method 1: Simple key sequence
            ["kdotool", "key", "ctrl+v"],
            # Method 2: Individual key presses
            ["kdotool", "key", "ctrl", "v"],
            # Method 3: With delays
            ["kdotool", "key", "--delay", "50", "ctrl+v"],
            # Method 4: Alternative syntax
            ["kdotool", "type", "ctrl+v"],
        ]

        for i, cmd in enumerate(kdotool_methods):
            try:
                print(f"DEBUG: Trying kdotool method {i + 1}: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, timeout=3)

                if result.returncode == 0:
                    print(f"DEBUG: kdotool method {i + 1} succeeded")
                    time.sleep(0.3)  # Give time for the paste to complete
                    return True
                else:
                    error_msg = (
                        result.stderr.decode().strip()
                        if result.stderr
                        else "unknown error"
                    )
                    print(f"DEBUG: kdotool method {i + 1} failed: {error_msg}")

                    # Handle specific KDE errors
                    if "not supported" in error_msg or "permission" in error_msg:
                        print("DEBUG: kdotool operation not supported by compositor")
                        return False

            except subprocess.TimeoutExpired:
                print(f"DEBUG: kdotool method {i + 1} timed out")
            except Exception as e:
                print(f"DEBUG: kdotool method {i + 1} failed: {e}")

        return False

    def _try_kwin_dbuss_paste(self):
        """Try using kwin's D-Bus interface for paste."""
        try:
            import dbus

            bus = dbus.SessionBus()
            kwin = bus.get_object("org.kde.KWin", "/KWin")
            kwin_interface = dbus.Interface(kwin, "org.kde.KWin")

            # Try to simulate key press through KWin
            # Note: This may not work due to security restrictions
            print("DEBUG: Trying KWin D-Bus paste simulation")
            return False

        except Exception as e:
            print(f"DEBUG: KWin D-Bus paste failed: {e}")
            return False

    def _try_qdbus_paste(self):
        """Try using qdbus for paste simulation."""
        try:
            # Try to use qdbus to send key events
            # This is a best-effort approach that may not work
            print("DEBUG: Trying qdbus paste simulation")

            # Note: qdbus key simulation is very limited on Wayland
            # due to security restrictions
            return False

        except Exception as e:
            print(f"DEBUG: qdbus paste failed: {e}")
            return False

    def _try_subprocess_command(self, command):
        """Try a subprocess command with timeout."""
        try:
            result = subprocess.run(command, capture_output=True, timeout=2)
            return result.returncode == 0
        except Exception:
            return False

    def _try_pykeyboard_paste(self):
        """Try keyboard paste with minimal delays."""
        try:
            from pynput import keyboard as pykeyboard

            kbrd = pykeyboard.Controller()

            # Quick paste sequence
            kbrd.press(pykeyboard.Key.ctrl.value)
            kbrd.press("v")
            time.sleep(0.05)
            kbrd.release("v")
            kbrd.release(pykeyboard.Key.ctrl.value)

        except Exception:
            pass  # Silently fail - this is best effort
