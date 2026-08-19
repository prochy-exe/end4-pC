import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    required property string iconName
    required property double percentage
    property bool vertical: false
    property int warningThreshold: 100
    property bool shown: true
    clip: !vertical
    visible: shown
    implicitWidth: !shown ? 0 : (vertical ? Appearance.sizes.verticalBarWidth : resourceRowLayout.implicitWidth)
    implicitHeight: !shown ? 0 : (vertical ? resourceProgress.implicitHeight : Appearance.sizes.barHeight)
    property bool warning: percentage * 100 >= warningThreshold

    Component {
        id: outlineStyle
        ClippedOutlineCircularProgress {
            lineWidth: Appearance.rounding.unsharpen
            value: root.percentage
            implicitSize: vertical ? 20 : 20
            colPrimary: root.warning ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: Font.DemiBold
                    fill: 1
                    text: root.iconName
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    Component {
        id: filledStyle
        ClippedFilledCircularProgress {
            lineWidth: Appearance.rounding.unsharpen
            value: root.percentage
            implicitSize: 20
            colPrimary: root.warning ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
            accountForLightBleeding: !root.warning
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: vertical ? Font.Medium : Font.DemiBold
                    fill: 1
                    text: root.iconName
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }
    }

    // Vertical
    Loader {
        id: resourceProgress
        active: root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: Config.getBarSetting(root.monitorName, ["resources", "style"], Config.options.bar.resources.style) === "filled" ? filledStyle : outlineStyle
    }

    // Horizontal
    RowLayout {
        id: resourceRowLayout
        visible: !root.vertical
        spacing: 2
        x: shown ? 0 : -resourceRowLayout.width
        anchors.verticalCenter: parent.verticalCenter

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: !root.vertical
            visible: active
            sourceComponent: Config.getBarSetting(root.monitorName, ["resources", "style"], Config.options.bar.resources.style) === "filled" ? filledStyle : outlineStyle
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            visible: Config.getBarSetting(root.monitorName, ["resources", "showValue"], Config.options.bar.resources.showValue)
            implicitWidth: visible ? fullPercentageTextMetrics.width : 0
            implicitHeight: percentageText.implicitHeight
            TextMetrics {
                id: fullPercentageTextMetrics
                text: "100"
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                id: percentageText
                anchors.centerIn: parent
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                text: `${Math.round(root.percentage * 100).toString()}`
            }
        }

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        enabled: root.shown && root.visible
    }

    Behavior on implicitWidth {
        enabled: false
    }
}
