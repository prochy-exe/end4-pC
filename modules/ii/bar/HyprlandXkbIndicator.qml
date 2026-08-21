import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import Quickshell.Hyprland
import Quickshell.Wayland

UtilButton {
    id: root
    property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool vertical: false
    property bool layoutPickerOpen: false
    iconText: ""

    onClicked: layoutPickerOpen = !layoutPickerOpen

    function selectLayout(index) {
        console.log("[HyprlandXkbIndicator] Selecting layout", index)
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "current", String(index)])
        root.layoutPickerOpen = false
    }

    Loader {
        id: layoutPicker
        active: root.layoutPickerOpen
        sourceComponent: PanelWindow {
            id: popupWindow
            screen: root.QsWindow.window?.screen
            visible: true
            color: "transparent"
            implicitWidth: pickerCard.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: pickerCard.implicitHeight + Appearance.sizes.elevationMargin * 2

            readonly property bool barVertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
            readonly property string barEdge: {
                const bottom = Config.getBarSetting(root.monitorName, ["bottom"], Config.options.bar.bottom)
                if (!barVertical) return bottom ? "bottom" : "top"
                return bottom ? "right" : "left"
            }
            readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
            readonly property real centerOffsetX: {
                const base = root.QsWindow.window.mapFromItem(root, (root.width - pickerCard.implicitWidth) / 2, 0).x
                const margin = Appearance.sizes.elevationMargin
                const maxLeft = screen.width - pickerCard.implicitWidth - margin - 10
                return Math.max(margin, Math.min(base, maxLeft))
            }
            readonly property real centerOffsetY: {
                const base = root.QsWindow.window.mapFromItem(root, 0, (root.height - pickerCard.implicitHeight) / 2).y
                const margin = Appearance.sizes.elevationMargin
                const maxTop = screen.height - pickerCard.implicitHeight - margin - 15
                return Math.max(margin, Math.min(base, maxTop))
            }

            anchors.left: barEdge !== "right"
            anchors.right: barEdge === "right"
            anchors.top: barEdge !== "bottom"
            anchors.bottom: barEdge === "bottom"
            margins {
                left: {
                    if (barEdge === "right") return 0
                    if (barEdge === "left") return barThickness
                    return centerOffsetX
                }
                top: {
                    if (barEdge === "bottom") return 0
                    if (barEdge === "top") return barThickness
                    return centerOffsetY
                }
                right: barEdge === "right" ? barThickness : 0
                bottom: barEdge === "bottom" ? barThickness : 0
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:popup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Component.onCompleted: GlobalFocusGrab.addDismissable(popupWindow)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(popupWindow)

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    root.layoutPickerOpen = false
                }
            }

            StyledRectangularShadow {
                target: pickerCard
            }

            Rectangle {
                id: pickerCard
                anchors.centerIn: parent
                implicitWidth: pickerContent.implicitWidth + 16
                implicitHeight: pickerContent.implicitHeight + 16
                radius: Appearance.rounding.normal + 4
                color: MonitorThemes.shellColorForItem(root, "colLayer1Base", Appearance.colors.colLayer1Base)
                border.width: 1
                border.color: MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border)

                Item {
                    id: pickerContent
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    implicitWidth: 180
                    implicitHeight: pickerColumn.implicitHeight

                    Column {
                        id: pickerColumn
                        anchors.fill: parent
                        spacing: 2

                        Repeater {
                            model: HyprlandXkb.layoutCodes
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                width: pickerColumn.width
                                height: 32
                                radius: Appearance.rounding.small
                                color: modelData === HyprlandXkb.currentLayoutCode ? MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : "transparent"

                                StyledText {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: modelData === HyprlandXkb.currentLayoutCode ? MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) : MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: parent.color = modelData === HyprlandXkb.currentLayoutCode ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : MonitorThemes.shellColorForItem(root, "colLayer2Hover", Appearance.colors.colLayer2Hover)
                                    onExited: parent.color = modelData === HyprlandXkb.currentLayoutCode ? MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : "transparent"
                                    onPressed: root.selectLayout(index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        text: HyprlandXkb.displayedLayoutCode
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.highlighted ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
        animateChange: true
    }

}
