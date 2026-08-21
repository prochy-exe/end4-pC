import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property string monitorName: ""
    property string infoText: ""
    readonly property string resolvedMonitorName: {
        if (root.monitorName) return root.monitorName
        let item = root.parent
        while (item) {
            if (item.monitorName) return item.monitorName
            if (item.screen?.name) return item.screen.name
            item = item.parent
        }
        return root.QsWindow?.window?.screen?.name ?? ""
    }
    property alias iconSize: iconWidget.iconSize
    colBackgroundHover: "transparent"

    Layout.fillWidth: true
    Layout.bottomMargin: 6 //Visually it works and I don't know why this should be handled by the parent.
    implicitHeight: contentItem.implicitHeight + 8 
    font.pixelSize: Appearance.font.pixelSize.small
    
    onClicked: checked = !checked

    contentItem: RowLayout {
        spacing: 10
        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
            iconColor: MonitorThemes.colorForItem(root, "on_secondary_container", Appearance.colors.colOnSecondaryContainer)
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            font: root.font
            color: MonitorThemes.colorForItem(root, "on_secondary_container", Appearance.colors.colOnSecondaryContainer)
        }
        Item {
            id: infoItem
            property bool hovered: infoMouse.containsMouse
            visible: root.infoText.length > 0
            implicitWidth: infoIcon.implicitWidth
            implicitHeight: infoIcon.implicitHeight
            MaterialSymbol {
                id: infoIcon
                anchors.centerIn: parent
                text: "info"
                iconSize: Appearance.font.pixelSize.small
                color: MonitorThemes.colorForItem(root, "on_secondary_container", Appearance.colors.colOnSecondaryContainer)
            }
            MouseArea {
                id: infoMouse
                anchors.fill: parent
                hoverEnabled: true
            }
            StyledToolTip {
                text: root.infoText
            }
        }
        StyledSwitch {
            id: switchWidget
            down: root.down
            Layout.fillWidth: false
            enabled: root.enabled
            checked: root.checked
            monitorName: root.resolvedMonitorName
            onClicked: root.clicked()
        }
    }
}
