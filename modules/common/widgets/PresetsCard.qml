import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Rectangle {
    id: root

    property string imageSource: ""
    property string title: ""
    property string description: ""
    property var onApply: () => {}
    property var onRemove: () => {}
    property var onOverwrite: () => {}
    property var onExportZip: () => {}

    implicitWidth: 293 
    implicitHeight: contentColumn.implicitHeight + 14
    radius: Appearance.rounding.normal
    color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)
    border.width: 1
    border.color: "transparent"

    ColumnLayout {
        id: contentColumn
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 0
        }
        spacing: 6

        // Header
        RowLayout{
            Layout.leftMargin: 10
            Layout.topMargin: 6
            spacing: 10
            MaterialShapeWrappedMaterialSymbol {
                id: avatarShape
                shape: MaterialShape.Shape.Circle 
                text: root.title.length > 0 ? root.title.charAt(0).toUpperCase() : "?"
                iconSize: Appearance.font.pixelSize.normal
                implicitSize: 36
                font: Appearance.font.family.main
                color: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
                colSymbol: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout{
                spacing: -4
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // Description
                StyledText {
                    Layout.fillWidth: true
                    visible: root.description.length > 0
                    text: root.description
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    elide: Text.ElideRight
                }
            }
            Item {
                Layout.alignment: Qt.AlignRight
                Layout.rightMargin: 8
                implicitWidth: 32
                implicitHeight: 32
                RippleButton {
                    id: menuBtn
                    anchors.centerIn: parent
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: menuPopup.visible = !menuPopup.visible
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "more_vert"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                }
                PresetPopup {
                    id: menuPopup
                    y: menuBtn.height + 4
                    x: menuBtn.width - width + 8
                    onOverwrite: root.onOverwrite
                    onExportZip: root.onExportZip
                }
            }
        }

        // Wall
        Rectangle {
            id: imageRect
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            implicitHeight: 130
            radius: 0
            color: MonitorThemes.shellColorForItem(root, "colLayer2", Appearance.colors.colLayer2)
            clip: true

            StyledImage {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: root.imageSource
                cache: false
                antialiasing: true
                sourceSize.width: imageRect.width * 2
                sourceSize.height: imageRect.height * 2
                visible: root.imageSource !== ""
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: imageRect.width
                        height: imageRect.height
                        radius: imageRect.radius
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.imageSource === ""
                text: "wallpaper"
                iconSize: Appearance.font.pixelSize.huge
                color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
            }
        }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 8
            Layout.bottomMargin: -4
            spacing: 8

            Item { Layout.fillWidth: true }

            GroupButton {
                id: removeBtn
                bounce: false
                toggled: false
                leftRadius: height / 2
                rightRadius: height / 2
                Layout.fillWidth: false
                Layout.fillHeight: false
                implicitHeight: 36
                horizontalPadding: 14
                verticalPadding: 8
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover), 0.8)
                colBackgroundActive: MonitorThemes.shellColorForItem(root, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
                contentItem: StyledText {
                    text: "Remove"
                    color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.onRemove()
            }

            GroupButton {
                id: applyBtn
                bounce: false
                toggled: false
                leftRadius: height / 2
                rightRadius: height / 2
                Layout.fillWidth: false
                Layout.fillHeight: false
                implicitHeight: 36
                horizontalPadding: 14
                verticalPadding: 8
                colBackground: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
                colBackgroundHover: MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover)
                colBackgroundActive: MonitorThemes.shellColorForItem(root, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
                contentItem: StyledText {
                    text: "Apply"
                    color: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.onApply()
            }
        }
    }
}
