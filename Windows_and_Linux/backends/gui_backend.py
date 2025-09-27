from abc import ABC, abstractmethod


class GUIBackend(ABC):
    @abstractmethod
    def get_active_window_title(self) -> str:
        """
        Return the title of the currently focused window, or a placeholder.
        """
        pass

    @abstractmethod
    def get_selected_text(self) -> str:
        """
        Return the currently selected clipboard text.
        """
        pass
