import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.bluetoothDevices
import Quickshell.Wayland

Item {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3

    implicitWidth: root.vertical ? 26 : flow.implicitWidth
    implicitHeight: root.vertical ? flow.implicitHeight : 26

    property string popupDialogName: ""

    function openPopupDialog(dialogName) {
        if (popupDialogName === dialogName) {
            popupDialogName = ""
            return
        }
        GlobalStates.sidebarRightOpen = false
        popupDialogName = dialogName
    }

    component StatusButton: UtilButton {
        property string dialogName: ""
        onClicked: root.openPopupDialog(dialogName)
    }

    Component {
        id: audioOutputDialog
        VolumeDialog { anchors.fill: parent; isSink: true; showScrim: false }
    }
    Component {
        id: audioInputDialog
        VolumeDialog { anchors.fill: parent; isSink: false; showScrim: false }
    }
    Component {
        id: bluetoothDialog
        BluetoothDialog { anchors.fill: parent; showScrim: false }
    }
    Component {
        id: wifiDialog
        WifiDialog { anchors.fill: parent; showScrim: false }
    }

    Loader {
        id: dialogPopupLoader
        active: root.popupDialogName.length > 0
        sourceComponent: PanelWindow {
            id: popupWindow
            screen: root.QsWindow.window?.screen
            color: "transparent"
            implicitWidth: 370
            implicitHeight: 620
            readonly property bool barAtBottom: Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom)

            anchors.left: !root.vertical
            anchors.right: root.vertical && barAtBottom
            anchors.top: root.vertical || !barAtBottom
            anchors.bottom: !root.vertical && barAtBottom
            margins {
                left: root.vertical ? (barAtBottom ? 0 : Appearance.sizes.verticalBarWidth) : Math.max(0, Math.min(
                    root.QsWindow.window.mapFromItem(root, (root.width - implicitWidth) / 2, 0).x,
                    screen.width - implicitWidth
                ))
                right: root.vertical && barAtBottom ? Appearance.sizes.verticalBarWidth : 0
                top: root.vertical ? Math.max(0, Math.min(
                    root.QsWindow.window.mapFromItem(root, 0, (root.height - implicitHeight) / 2).y,
                    screen.height - implicitHeight
                )) : (barAtBottom ? 0 : Appearance.sizes.barHeight)
                bottom: !root.vertical && barAtBottom ? Appearance.sizes.barHeight : 0
            }

            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:systemIconDialog"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Component.onCompleted: GlobalFocusGrab.addDismissable(popupWindow)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(popupWindow)

            Connections {
                target: GlobalFocusGrab
                function onDismissed() { root.popupDialogName = "" }
            }

            Loader {
                id: dialogLoader
                anchors.fill: parent
                sourceComponent: root.popupDialogName === "audioOutput" ? audioOutputDialog
                    : root.popupDialogName === "audioInput" ? audioInputDialog
                    : root.popupDialogName === "bluetooth" ? bluetoothDialog
                    : wifiDialog
                onLoaded: {
                    item.show = true
                    item.forceActiveFocus()
                }
                Connections {
                    target: dialogLoader.item
                    function onDismiss() { root.popupDialogName = "" }
                }
            }
        }
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
                UtilButton {
                    id: notificationButton
                    acceptedMouseButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (event) => {
                        if (event.button === Qt.RightButton)
                            Notifications.discardAllNotifications()
                        else
                            Notifications.replayAllNotifications()
                    }

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
