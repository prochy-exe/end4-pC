import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions

ToolbarButton {
    colBackground: ColorUtils.transparentize(MonitorThemes.shellColorForItem(parent, "colPrimaryContainer", Appearance.colors.colPrimaryContainer))
    colBackgroundHover: MonitorThemes.shellColorForItem(parent, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover)
    colRipple: MonitorThemes.shellColorForItem(parent, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
}
