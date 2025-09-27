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
        2. KDE Plasma via kwin5 CLI
        3. GNOME (Mutter) via D-Bus extension + cache file
        4. Fallback placeholder
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

        # 2) KDE Plasma: kwin5 CLI
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
            return title or "<Wayland>"
        except Exception:
            pass

        # 3) GNOME (Mutter): D-Bus extension + cache file
        try:
            title = asyncio.get_event_loop().run_until_complete(self._get_gnome_title())
            if title:
                return title
        except Exception:
            pass

        # 4) Fallback
        return "<Wayland>"

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
        """
        try:
            return subprocess.run(
                ["wl-paste", "--primary"], capture_output=True, text=True, check=True
            ).stdout
        except subprocess.CalledProcessError:
            return subprocess.run(
                ["wl-paste"], capture_output=True, text=True, check=True
            ).stdout
