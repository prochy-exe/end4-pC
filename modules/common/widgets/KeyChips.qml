import qs.modules.common
import QtQuick

/**
 * Renders a Hyprland key-combo string (e.g. "SUPER + SHIFT + S") as a row of
 * KeyboardKey chips joined by "+". Used by the Keybinds settings page and the
 * cheatsheet so both show shortcuts identically.
 *
 * Flow (not RowLayout) so a long combo wraps onto a second line instead of
 * overflowing past whatever width it's given, when it's given one.
 */
Flow {
    id: root
    property string keyString: ""
    spacing: 4
    Repeater {
        model: root.keyString.split("+").map(s => s.trim()).filter(s => s.length > 0)
        delegate: Row {
            required property string modelData
            required property int index
            spacing: 4
            StyledText {
                visible: index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                color: Appearance.colors.colSubtext
            }
            KeyboardKey {
                anchors.verticalCenter: parent.verticalCenter
                key: modelData
            }
        }
    }
}
