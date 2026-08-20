import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3

    implicitWidth: root.vertical ? 26 : flow.implicitWidth
    implicitHeight: root.vertical ? flow.implicitHeight : 26

    function openSidebarDialog(dialogName) {
        GlobalStates.sidebarRightRequestedDialog = dialogName
        GlobalStates.sidebarRightDialogRequest++
        GlobalStates.sidebarRightOpen = true
    }

    component StatusButton: UtilButton {
        property string dialogName: ""
        onClicked: root.openSidebarDialog(dialogName)
    }

    Flow {
        id: flow
        anchors.centerIn: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        spacing: root.isMaterial ? 2 : 4

        Revealer {
            reveal: true
            StatusButton {
                dialogName: "audioOutput"
                iconText: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
            }
        }

        Revealer {
            reveal: Audio.source?.audio?.muted ?? false
            StatusButton {
                dialogName: "audioInput"
                iconText: "mic_off"
            }
        }

        StatusButton {
            dialogName: "wifi"
            iconText: Network.materialSymbol
        }

        StatusButton {
            visible: BluetoothStatus.available
            dialogName: "bluetooth"
            iconText: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
        }

        Loader {
            active: Notifications.silent || Notifications.unread > 0
            visible: active
            sourceComponent: Component {
                StatusButton {
                    id: notificationButton
                    dialogName: "sidebar"

                    NotificationUnreadCount {
                        anchors.centerIn: parent
                        monitorName: root.monitorName
                        iconColor: notificationButton.highlighted ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                    }
                }
            }
        }
    }
}
