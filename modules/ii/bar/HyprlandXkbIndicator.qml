import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import Quickshell.Hyprland

UtilButton {
    id: root
    property bool vertical: false
    property bool layoutPickerOpen: false
    iconText: ""

    onClicked: layoutPickerOpen = !layoutPickerOpen

    LazyLoader {
        id: layoutPicker
        active: root.layoutPickerOpen

        component: PopupWindow {
            visible: true
            anchor {
                window: root.QsWindow.window
                item: root
                edges: Edges.Bottom
                gravity: Edges.Top
            }
            color: "transparent"
            implicitWidth: 180
            implicitHeight: pickerColumn.implicitHeight + 16

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: Appearance.rounding.normal
                color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
                border.width: 1
                border.color: MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border)

                Column {
                    id: pickerColumn
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Repeater {
                        model: HyprlandXkb.layoutCodes
                        delegate: Rectangle {
                            required property string modelData
                            width: pickerColumn.width
                            height: 32
                            radius: Appearance.rounding.small
                            color: modelData === HyprlandXkb.currentLayoutCode ? Appearance.colors.colPrimaryContainer : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData
                                color: modelData === HyprlandXkb.currentLayoutCode ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: parent.color = Appearance.colors.colLayer2Hover
                                onExited: parent.color = modelData === HyprlandXkb.currentLayoutCode ? Appearance.colors.colPrimaryContainer : "transparent"
                                onClicked: {
                                    Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", String(index)])
                                    root.layoutPickerOpen = false
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
