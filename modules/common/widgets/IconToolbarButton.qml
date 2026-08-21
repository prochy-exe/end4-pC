import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.common

ToolbarButton {
    id: iconBtn
    implicitWidth: height

    colBackgroundToggled: MonitorThemes.shellColorForItem(parent, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
    colBackgroundToggledHover: MonitorThemes.shellColorForItem(parent, "colSecondaryContainerHover", Appearance.colors.colSecondaryContainerHover)
    colRippleToggled: MonitorThemes.shellColorForItem(parent, "colSecondaryContainerActive", Appearance.colors.colSecondaryContainerActive)
    property color colText: toggled ? MonitorThemes.shellColorForItem(parent, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer) : MonitorThemes.shellColorForItem(parent, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        iconSize: 22
        text: iconBtn.text
        color: iconBtn.colText
        animateChange: true
    }
}
