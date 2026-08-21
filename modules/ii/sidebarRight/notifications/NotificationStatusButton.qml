import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

GroupButton {
    id: button
    property string buttonIcon: ""
    property string buttonText: ""

    baseHeight: 36
    baseWidth: content.implicitWidth + 46
    clickedWidth: baseWidth + 6

    buttonRadius: baseHeight / 2
    buttonRadiusPressed: Appearance.rounding.small
    colBackground: MonitorThemes.shellColorForItem(parent, "colLayer2", Appearance.colors.colLayer2)
    colBackgroundHover: MonitorThemes.shellColorForItem(parent, "colLayer2Hover", Appearance.colors.colLayer2Hover)
    colBackgroundActive: MonitorThemes.shellColorForItem(parent, "colLayer2Active", Appearance.colors.colLayer2Active)
    property color colText: toggled ? MonitorThemes.colorForItem(parent, "on_primary", Appearance.m3colors.m3onPrimary) : MonitorThemes.shellColorForItem(parent, "colOnLayer1", Appearance.colors.colOnLayer1)

    contentItem: Item {
        id: content
        anchors.fill: parent
        implicitWidth: contentRowLayout.implicitWidth
        implicitHeight: contentRowLayout.implicitHeight
        RowLayout {
            id: contentRowLayout
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                visible: buttonIcon !== ""
                text: buttonIcon
                iconSize: Appearance.font.pixelSize.huge
                color: button.colText
            }
            StyledText {
                visible: buttonText !== ""
                text: buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                color: button.colText
            }
        }
    }

}
