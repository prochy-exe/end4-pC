import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledPopup {
    id: root
    keepOpenWhileHovered: true

    required property string label
    required property string iconName
    required property real usage
    required property string sublabel
    required property var detailRows
    readonly property string longestDetailLabel: detailRows.reduce((longest, row) => row.label.length > longest.length ? row.label : longest, "")
    readonly property string longestDetailValue: detailRows.reduce((longest, row) => row.value.length > longest.length ? row.value : longest, "")
    readonly property real desiredWidth: Math.max(300, Math.min(380,
        (longestDetailLabel.length + longestDetailValue.length) * Appearance.font.pixelSize.small * 0.6 + 60))

    ColumnLayout {
        implicitWidth: root.desiredWidth
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: root.desiredWidth
            Layout.preferredWidth: root.desiredWidth
            Layout.leftMargin: 3
            Layout.rightMargin: 5
            spacing: 7

            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.Circle
                text: root.iconName
                iconSize: Appearance.font.pixelSize.large
                implicitSize: 36
                color: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
                colSymbol: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -3

                StyledText {
                    text: root.label
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.sublabel
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    opacity: 0.6
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: usageContent.implicitHeight + 20
            radius: Appearance.rounding.small
            color: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)

            ColumnLayout {
                id: usageContent
                anchors {
                    fill: parent
                    margins: 10
                }
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    MaterialSymbol {
                        text: "monitoring"
                        iconSize: Appearance.font.pixelSize.normal
                        color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                    }

                    StyledText {
                        text: Translation.tr("Usage")
                        color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                    }

                    Item { Layout.fillWidth: true }
                }

                StyledText {
                    text: `${Math.round(root.usage * 100)}%`
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }

                StyledText {
                    text: root.sublabel
                    color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                    opacity: 0.6
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle {
            id: detailsCard
            visible: root.detailRows.length > 0
            Layout.fillWidth: true
            implicitHeight: detailColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)

            ColumnLayout {
                id: detailColumn
                anchors {
                    fill: parent
                    margins: 8
                }
                spacing: 2

                Repeater {
                    model: root.detailRows

                    ColumnLayout {
                        id: detailRow
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            visible: detailRow.modelData.section !== undefined
                                && (detailRow.index === 0 || root.detailRows[detailRow.index - 1].section !== detailRow.modelData.section)
                            text: detailRow.modelData.section
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                            opacity: 0.6
                            Layout.topMargin: detailRow.index === 0 ? 0 : 4
                        }

                        StyledPopupValueRow {
                            Layout.fillWidth: true
                            icon: detailRow.modelData.icon
                            label: detailRow.modelData.label
                            value: detailRow.modelData.value
                            elideLabel: false
                        }
                    }
                }
            }
        }
    }
}
