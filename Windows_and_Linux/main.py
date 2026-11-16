import logging
import sys

from WritingToolApp import WritingToolApp

# Set up logging to console
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')


def main():
    """
    The main entry point of the application.

    `main.py --trigger [ACTION]` tells an already running instance to open the
    popup (default) or run the button named ACTION, then exits. It is meant for
    Wayland desktops without the global shortcuts portal, where the user binds
    a key to this command in the desktop's own settings.
    """
    if len(sys.argv) > 1 and sys.argv[1] == '--trigger':
        from linux_wayland.trigger_socket import send_trigger
        action = ' '.join(sys.argv[2:]) or 'popup'
        sys.exit(0 if send_trigger(action) else 1)

    app = WritingToolApp(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
