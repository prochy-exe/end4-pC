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
    property bool elideLabel: true
    property var copyAction: null
    property bool copied: false
    spacing: 4

    MaterialSymbol {
        text: root.icon
        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
        iconSize: Appearance.font.pixelSize.large
    }
    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 1
        text: root.label
        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
        elide: root.elideLabel ? Text.ElideRight : Text.ElideNone
    }
    StyledText {
        Layout.minimumWidth: implicitWidth
        horizontalAlignment: Text.AlignRight
        visible: root.value !== ""
        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
        text: root.value
    }
    MaterialSymbol {
        visible: root.copyAction !== null
        text: root.copied ? "check" : "content_copy"
        iconSize: Appearance.font.pixelSize.normal
        color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.copyAction()
                root.copied = true
                copiedTimer.restart()
            }
        }
    }

    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: root.copied = false
    }
}
