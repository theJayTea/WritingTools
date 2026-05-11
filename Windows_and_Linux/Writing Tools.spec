# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[('locales', 'locales')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'unittest', 'IPython', 'jedi', 'email_validator', 'psutil', 'pyzmq', 'tornado', 'PySide6.QtNetwork', 'PySide6.QtXml', 'PySide6.QtQml', 'PySide6.QtQuick', 'PySide6.QtQuickWidgets', 'PySide6.QtPrintSupport', 'PySide6.QtSql', 'PySide6.QtTest', 'PySide6.QtSvg', 'PySide6.QtSvgWidgets', 'PySide6.QtHelp', 'PySide6.QtMultimedia', 'PySide6.QtMultimediaWidgets', 'PySide6.QtOpenGL', 'PySide6.QtOpenGLWidgets', 'PySide6.QtPositioning', 'PySide6.QtLocation', 'PySide6.QtSerialPort', 'PySide6.QtWebChannel', 'PySide6.QtWebSockets', 'PySide6.QtWinExtras', 'PySide6.QtNetworkAuth', 'PySide6.QtRemoteObjects', 'PySide6.QtTextToSpeech', 'PySide6.QtWebEngineCore', 'PySide6.QtWebEngineWidgets', 'PySide6.QtWebEngine', 'PySide6.QtBluetooth', 'PySide6.QtNfc', 'PySide6.QtWebView', 'PySide6.QtCharts', 'PySide6.QtDataVisualization', 'PySide6.QtPdf', 'PySide6.QtPdfWidgets', 'PySide6.QtQuick3D', 'PySide6.QtQuickControls2', 'PySide6.QtQuickParticles', 'PySide6.QtQuickTest', 'PySide6.QtQuickWidgets', 'PySide6.QtSensors', 'PySide6.QtStateMachine', 'PySide6.Qt3DCore', 'PySide6.Qt3DRender', 'PySide6.Qt3DInput', 'PySide6.Qt3DLogic', 'PySide6.Qt3DAnimation', 'PySide6.Qt3DExtras'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='Writing Tools',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['icons/app_icon.png'],
)
