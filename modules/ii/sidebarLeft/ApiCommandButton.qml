import qs.modules.common
import qs.services
import qs.modules.common.widgets
import QtQuick

GroupButton {
    id: button
    property string buttonText

    horizontalPadding: 8
    verticalPadding: 6

    baseWidth: contentItem.implicitWidth + horizontalPadding * 2
    clickedWidth: baseWidth + 14
    baseHeight: contentItem.implicitHeight + verticalPadding * 2
    buttonRadius: down ? Appearance.rounding.verysmall : Appearance.rounding.small

        colBackground: MonitorThemes.shellColorForItem(root, "colLayer2", Appearance.colors.colLayer2)
        colBackgroundHover: MonitorThemes.shellColorForItem(root, "colLayer2Hover", Appearance.colors.colLayer2Hover)
        colBackgroundActive: MonitorThemes.shellColorForItem(root, "colLayer2Active", Appearance.colors.colLayer2Active)

    contentItem: StyledText {
        horizontalAlignment: Text.AlignHCenter
        text: buttonText
        color: MonitorThemes.colorForItem(root, "on_surface", Appearance.m3colors.m3onSurface)
    }
}
