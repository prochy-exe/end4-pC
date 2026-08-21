import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

GroupButton {
    id: button
    property string buttonIcon
    property bool activated: false
    toggled: activated
    baseWidth: height
    colBackgroundHover: MonitorThemes.shellColorForItem(root, "colSecondaryContainerHover", Appearance.colors.colSecondaryContainerHover)
    colBackgroundActive: MonitorThemes.shellColorForItem(root, "colSecondaryContainerActive", Appearance.colors.colSecondaryContainerActive)

    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        iconSize: Appearance.font.pixelSize.larger
        text: buttonIcon
        color: button.activated ? MonitorThemes.colorForItem(root, "on_primary", Appearance.m3colors.m3onPrimary) :
            button.enabled ? MonitorThemes.colorForItem(root, "on_surface", Appearance.m3colors.m3onSurface) :
            MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1Inactive)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
