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
