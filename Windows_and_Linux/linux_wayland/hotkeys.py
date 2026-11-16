"""
Convert Writing Tools hotkey strings ('ctrl+space', 'ctrl+shift+p') into the
trigger format of the XDG shortcuts spec ('CTRL+space', 'CTRL+SHIFT+p').

The spec uses the modifiers CTRL, ALT, SHIFT, NUM and LOGO, followed by one
xkb keysym name. Desktops treat the trigger as a suggestion only: the user
confirms or changes it in the desktop's own shortcut settings.
"""

MODIFIERS = {
    "ctrl": "CTRL",
    "control": "CTRL",
    "alt": "ALT",
    "shift": "SHIFT",
    "super": "LOGO",
    "win": "LOGO",
    "windows": "LOGO",
    "meta": "LOGO",
    "cmd": "LOGO",
}

# Writing Tools / pynput key names -> xkb keysym names.
NAMED_KEYS = {
    "space": "space",
    "enter": "Return",
    "return": "Return",
    "tab": "Tab",
    "esc": "Escape",
    "escape": "Escape",
    "backspace": "BackSpace",
    "delete": "Delete",
    "del": "Delete",
    "insert": "Insert",
    "home": "Home",
    "end": "End",
    "page_up": "Prior",
    "pageup": "Prior",
    "page_down": "Next",
    "pagedown": "Next",
    "up": "Up",
    "down": "Down",
    "left": "Left",
    "right": "Right",
    "print_screen": "Print",
    "pause": "Pause",
    "menu": "Menu",
}
NAMED_KEYS.update({f"f{n}": f"F{n}" for n in range(1, 25)})

# Punctuation pynput accepts as single characters, mapped to keysym names.
PUNCTUATION = {
    ",": "comma",
    ".": "period",
    "/": "slash",
    ";": "semicolon",
    "'": "apostrophe",
    "[": "bracketleft",
    "]": "bracketright",
    "\\": "backslash",
    "-": "minus",
    "=": "equal",
    "`": "grave",
}


def to_portal_trigger(hotkey):
    """
    Return the XDG trigger string for a Writing Tools hotkey.

    Raises ValueError for empty strings, unknown key names, repeated
    modifiers, or anything that isn't "modifiers + exactly one key".
    """
    if not hotkey or not hotkey.strip():
        raise ValueError("empty hotkey")

    parts = [p.strip().lower() for p in hotkey.strip().split("+")]
    # 'ctrl++' style input: a literal plus sign is not supported.
    if any(p == "" for p in parts):
        raise ValueError(f"'{hotkey}' has an empty key between '+' signs")

    modifiers = []
    key = None
    for part in parts:
        if part in MODIFIERS:
            mod = MODIFIERS[part]
            if mod in modifiers:
                raise ValueError(f"modifier '{part}' appears twice")
            modifiers.append(mod)
            continue
        if key is not None:
            raise ValueError(f"'{hotkey}' has more than one non-modifier key")
        if part in NAMED_KEYS:
            key = NAMED_KEYS[part]
        elif len(part) == 1 and (part.isalnum() and part.isascii()):
            key = part
        elif part in PUNCTUATION:
            key = PUNCTUATION[part]
        else:
            raise ValueError(f"unknown key '{part}'")

    if key is None:
        raise ValueError(f"'{hotkey}' has no key, only modifiers")

    # Keep a stable modifier order so the same hotkey always maps the same way.
    order = ["CTRL", "ALT", "SHIFT", "LOGO"]
    modifiers.sort(key=order.index)
    return "+".join(modifiers + [key])
