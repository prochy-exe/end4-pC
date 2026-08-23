#pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)

    readonly property bool anyConnected: KeychronDevices.mouse.connected || KeychronDevices.keyboard.connected
    readonly property color iconColor: root.anyConnected
        ? MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
        : MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0) + 10
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    hoverEnabled: !Config.getBarSetting(root.monitorName, ["tooltips", "clickToShow"], Config.options.bar.tooltips.clickToShow)

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton) {
            KeychronDevices.refresh()
            mouse.accepted = false
        }
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? colContent : rowContent
    }

    Component {
        id: rowContent
        RowLayout {
            spacing: 4

            MaterialSymbol {
                fill: 0
                text: "mouse"
                iconSize: Appearance.font.pixelSize.large
                color: root.iconColor
                opacity: KeychronDevices.mouse.connected ? 1 : 0.4
            }
            StyledText {
                visible: KeychronDevices.mouse.connected && KeychronDevices.mouse.battery !== null
                text: `${KeychronDevices.mouse.battery}%${KeychronDevices.mouse.charging ? " ⚡" : ""}`
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.iconColor
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 2

            MaterialSymbol {
                fill: 0
                text: "mouse"
                iconSize: Appearance.font.pixelSize.normal
                color: root.iconColor
                opacity: KeychronDevices.mouse.connected ? 1 : 0.4
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    KeychronPopup {
        id: keychronPopup
        hoverTarget: root
    }
}
