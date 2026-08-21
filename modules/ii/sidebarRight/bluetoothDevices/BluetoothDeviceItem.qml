import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property var device
    property bool expanded: false
    pointingHandCursor: !expanded

    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded
    
    component ActionButton: DialogButton {
        colBackground: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
        colBackgroundHover: MonitorThemes.shellColorForItem(root, "colPrimaryHover", Appearance.colors.colPrimaryHover)
        colRipple: MonitorThemes.shellColorForItem(root, "colPrimaryActive", Appearance.colors.colPrimaryActive)
        colText: MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary)
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            // Name
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    elide: Text.ElideRight
                    text: root.device?.name || Translation.tr("Unknown device")
                    textFormat: Text.PlainText
                }
                StyledText {
                    visible: (root.device?.connected || root.device?.paired) ?? false
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    elide: Text.ElideRight
                    text: {
                        if (!root.device?.paired) return "";
                        let statusText = root.device?.connected ? Translation.tr("Connected") : Translation.tr("Paired");
                        if (!root.device?.batteryAvailable) return statusText;
                        statusText += ` • ${Math.round(root.device?.battery * 100)}%`;
                        return statusText;
                    }
                }
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: MonitorThemes.shellColorForItem(root, "colOnLayer3", Appearance.colors.colOnLayer3)
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.topMargin: 8
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                readonly property bool p: root.device?.paired ?? false
                colBackground: p ? MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError) : ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colLayer3", Appearance.colors.colLayer3), 1)
                colBackgroundHover: p ? Appearance.colors.colErrorHover : ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colLayer3", Appearance.colors.colLayer3), 1)
                colRipple: p ? Appearance.colors.colErrorActive : MonitorThemes.shellColorForItem(root, "colLayer3Hover", Appearance.colors.colLayer3Hover)
                colText: p ? MonitorThemes.shellColorForItem(root, "colOnError", Appearance.colors.colOnError) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)

                buttonText: p ? Translation.tr("Forget") : Translation.tr("Always connect")
                onClicked: {
                    if (root.device?.paired) {
                        root.device?.forget();
                    } else {
                        root.device?.pair();
                    }
                }
            }
            ActionButton {
                buttonText: root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")

                onClicked: {
                    if (root.device?.connected) {
                        root.device.disconnect();
                    } else {
                        root.device.connect();
                    }
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
