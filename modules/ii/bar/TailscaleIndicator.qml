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

    readonly property var status: TailscaleService.status
    readonly property bool connected: status.connected
    function countryFlagEmoji(code) {
        if (!code || code.length !== 2) return ""
        const first = code.toUpperCase().codePointAt(0) - 65
        const second = code.toUpperCase().codePointAt(1) - 65
        if (first < 0 || first > 25 || second < 0 || second > 25) return ""
        return String.fromCodePoint(0x1F1E6 + first) + String.fromCodePoint(0x1F1E6 + second)
    }
    readonly property color iconColor: root.connected
        ? MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
        : MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0) + 10
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    hoverEnabled: !Config.getBarSetting(root.monitorName, ["tooltips", "clickToShow"], Config.options.bar.tooltips.clickToShow)

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton) {
            TailscaleService.refresh()
            mouse.accepted = false
        }
    }

    // Tailscale's own mark: a 3x3 dot grid where the "on" state highlights
    // five dots tracing a T (top row + the two below its center column).
    // Disabled = every dot flat gray, no T; connected but no exit node = T
    // lit, other four dots dim. Small corner badges layer on top for
    // whatever's actually active: exit node (bottom-right - a country flag
    // for a Mullvad node, or a person icon for one of your own tailnet
    // devices), Shields Up (top-right), Tailscale SSH (bottom-left) -
    // top-left is left alone so the top of the T stays readable.
    component DotLogo: Item {
        id: dotLogo
        property bool connected: false
        property bool hasExitNode: false
        property bool exitNodeIsMullvad: false
        property string exitNodeFlag: ""
        property bool shieldsUp: false
        property bool sshEnabled: false
        property real dotSize: 3
        property real dotSpacing: 2
        readonly property var tShape: [true, true, true, false, true, false, false, true, false]
        readonly property real badgeSize: dotSize * 2.3

        implicitWidth: dotSize * 3 + dotSpacing * 2
        implicitHeight: dotSize * 3 + dotSpacing * 2

        Grid {
            anchors.centerIn: parent
            columns: 3
            spacing: dotLogo.dotSpacing

            Repeater {
                model: 9
                delegate: Rectangle {
                    required property int index
                    width: dotLogo.dotSize
                    height: dotLogo.dotSize
                    radius: width / 2
                    color: root.iconColor
                    opacity: !dotLogo.connected ? 0.3
                        : (dotLogo.tShape[index] ? 1 : 0.35)
                }
            }
        }

        StyledText {
            visible: dotLogo.connected && dotLogo.hasExitNode && dotLogo.exitNodeIsMullvad && dotLogo.exitNodeFlag !== ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -4
            anchors.bottomMargin: -5
            font.pixelSize: dotLogo.badgeSize
            text: dotLogo.exitNodeFlag
        }

        MaterialSymbol {
            visible: dotLogo.connected && dotLogo.hasExitNode && !dotLogo.exitNodeIsMullvad
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -3
            anchors.bottomMargin: -3
            fill: 1
            text: "person"
            iconSize: dotLogo.badgeSize
            color: root.iconColor
        }

        MaterialSymbol {
            visible: dotLogo.connected && dotLogo.shieldsUp
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -3
            anchors.topMargin: -3
            fill: 1
            text: "shield"
            iconSize: dotLogo.badgeSize
            color: root.iconColor
        }

        MaterialSymbol {
            visible: dotLogo.connected && dotLogo.sshEnabled
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: -3
            anchors.bottomMargin: -3
            fill: 1
            text: "terminal"
            iconSize: dotLogo.badgeSize
            color: root.iconColor
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

            DotLogo {
                Layout.alignment: Qt.AlignVCenter
                dotSize: 3.5
                dotSpacing: 2.5
                connected: root.connected
                hasExitNode: root.status.exit_node !== null
                exitNodeIsMullvad: root.status.exit_node?.is_mullvad ?? false
                exitNodeFlag: root.countryFlagEmoji(root.status.exit_node?.country_code ?? "")
                shieldsUp: root.status.prefs.shields_up
                sshEnabled: root.status.prefs.ssh
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 2

            DotLogo {
                Layout.alignment: Qt.AlignHCenter
                connected: root.connected
                hasExitNode: root.status.exit_node !== null
                exitNodeIsMullvad: root.status.exit_node?.is_mullvad ?? false
                exitNodeFlag: root.countryFlagEmoji(root.status.exit_node?.country_code ?? "")
                shieldsUp: root.status.prefs.shields_up
                sshEnabled: root.status.prefs.ssh
            }
        }
    }

    TailscalePopup {
        id: tailscalePopup
        hoverTarget: root
    }
}
