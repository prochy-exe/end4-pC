pragma Singleton
import QtQuick
import Quickshell

/**
 * Maps Qt key events to the key-name strings Hyprland's Lua bind() expects
 * (e.g. "S", "F5", "Left", "XF86AudioMute"), for the keybind recorder in
 * Settings > Keybinds.
 */
Singleton {
    id: root

    readonly property var _named: ({
        [Qt.Key_Escape]: "Escape",
        [Qt.Key_Tab]: "Tab",
        [Qt.Key_Space]: "Space",
        [Qt.Key_Return]: "Return",
        [Qt.Key_Enter]: "Return",
        [Qt.Key_Backspace]: "BackSpace",
        [Qt.Key_Delete]: "Delete",
        [Qt.Key_Insert]: "Insert",
        [Qt.Key_Home]: "Home",
        [Qt.Key_End]: "End",
        [Qt.Key_PageUp]: "Page_Up",
        [Qt.Key_PageDown]: "Page_Down",
        [Qt.Key_Left]: "Left",
        [Qt.Key_Right]: "Right",
        [Qt.Key_Up]: "Up",
        [Qt.Key_Down]: "Down",
        [Qt.Key_Print]: "Print",
        [Qt.Key_CapsLock]: "Caps_Lock",
        [Qt.Key_Slash]: "Slash",
        [Qt.Key_Backslash]: "Backslash",
        [Qt.Key_Period]: "Period",
        [Qt.Key_Comma]: "Comma",
        [Qt.Key_Minus]: "Minus",
        [Qt.Key_Equal]: "Equal",
        [Qt.Key_BracketLeft]: "BracketLeft",
        [Qt.Key_BracketRight]: "BracketRight",
        [Qt.Key_Semicolon]: "Semicolon",
        [Qt.Key_Apostrophe]: "Apostrophe",
        [Qt.Key_QuoteLeft]: "grave",
        [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp",
        [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown",
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume",
        [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute",
        [Qt.Key_MicMute]: "XF86AudioMicMute",
        [Qt.Key_MediaPlay]: "XF86AudioPlay",
        [Qt.Key_MediaPause]: "XF86AudioPause",
        [Qt.Key_MediaTogglePlayPause]: "XF86AudioPlay",
        [Qt.Key_MediaNext]: "XF86AudioNext",
        [Qt.Key_MediaPrevious]: "XF86AudioPrev",
        [Qt.Key_MediaStop]: "XF86AudioStop",
    })

    // Keys allowed to be bound with no modifier held at all (matches what's
    // already bound bare in hyprland/keybinds.lua: media keys, Print, ...).
    readonly property var _noModifierAllowed: new Set([
        "Print", "XF86MonBrightnessUp", "XF86MonBrightnessDown",
        "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
        "XF86AudioMicMute", "XF86AudioPlay", "XF86AudioPause",
        "XF86AudioNext", "XF86AudioPrev", "XF86AudioStop",
    ])

    function isModifierKey(key) {
        return key === Qt.Key_Shift || key === Qt.Key_Control
            || key === Qt.Key_Alt || key === Qt.Key_AltGr
            || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R
    }

    // Canonical order matches the cheatsheet's modMaskToStringList.
    function modifierList(modifiers) {
        const list = []
        if (modifiers & Qt.ControlModifier) list.push("CTRL")
        if (modifiers & Qt.MetaModifier) list.push("SUPER")
        if (modifiers & Qt.ShiftModifier) list.push("SHIFT")
        if (modifiers & Qt.AltModifier) list.push("ALT")
        return list
    }

    function keyName(key) {
        if (key in root._named) return root._named[key]
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + (key - Qt.Key_F1 + 1)
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
        return ""
    }

    // Qt's Wayland key-translation table doesn't cover every keysym (extended
    // function keys like F13+ are a common gap even though wev, reading the
    // XKB keysym directly, sees them fine) - when keyName() comes up empty,
    // fall back to the raw hardware scancode via Hyprland's own "code:NN"
    // bind syntax (already used in hyprland/keybinds.lua for numpad keys).
    // Qt's nativeScanCode on Linux is the XKB keycode (evdev + 8), matching
    // what Hyprland expects there.
    function resolveKey(key, nativeScanCode) {
        const named = root.keyName(key)
        if (named) return named
        if (nativeScanCode > 0) return "code:" + nativeScanCode
        return ""
    }

    function allowsNoModifier(name) {
        return root._noModifierAllowed.has(name) || name.startsWith("code:")
    }
}
