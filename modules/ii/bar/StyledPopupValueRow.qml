import QtQuick
import qs.services
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    required property string icon
    required property string label
    required property string value
    spacing: 4

    MaterialSymbol {
        text: root.icon
        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
        iconSize: Appearance.font.pixelSize.large
    }
    StyledText {
        text: root.label
        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
    }
    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        visible: root.value !== ""
        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
        text: root.value
    }
}
