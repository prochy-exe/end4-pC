import qs.services
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property string displayText
    property string url

    property real faviconSize: 20
    implicitHeight: 30
    leftPadding: (implicitHeight - faviconSize) / 2
    rightPadding: 10
    buttonRadius: Appearance.rounding.full
    colBackground: MonitorThemes.shellColorForItem(root, "colSurfaceContainerHighest", Appearance.colors.colSurfaceContainerHighest)
    colBackgroundHover: MonitorThemes.shellColorForItem(root, "colSurfaceContainerHighestHover", Appearance.colors.colSurfaceContainerHighestHover)
    colRipple: MonitorThemes.shellColorForItem(root, "colSurfaceContainerHighestActive", Appearance.colors.colSurfaceContainerHighestActive)

    PointingHandInteraction {}
    onClicked: {
        if (url) {
            Qt.openUrlExternally(url)
            GlobalStates.sidebarLeftOpen = false
        }
    }

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: rowLayout.implicitWidth
        implicitHeight: rowLayout.implicitHeight
        RowLayout {
            id: rowLayout
            anchors.fill: parent
            spacing: 5
            Favicon {
                url: root.url
                size: root.faviconSize
                displayText: root.displayText
            }
            StyledText {
                id: text
                horizontalAlignment: Text.AlignHCenter
                text: displayText
                color: MonitorThemes.colorForItem(root, "on_surface", Appearance.m3colors.m3onSurface)
            }
        }
    }
}
