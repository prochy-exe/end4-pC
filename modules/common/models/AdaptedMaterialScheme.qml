import qs.services
import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * Material color scheme adapted to a given color. It's incomplete but enough for what we need...
 */
QtObject {
    id: root
    required property color color
    readonly property bool colorIsDark: color.hslLightness < 0.5

    property color colLayer0: ColorUtils.mix(MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0), root.color, (colorIsDark && Appearance.m3colors.darkmode) ? 0.6 : 0.5)
    property color colLayer1: ColorUtils.mix(MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1), root.color, 0.5)
    property color colOnLayer0: ColorUtils.mix(MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0), root.color, 0.5)
    property color colOnLayer1: ColorUtils.mix(MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1), root.color, 0.5)
    property color colSubtext: ColorUtils.mix(MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1), root.color, 0.5)
    property color colPrimary: ColorUtils.mix(ColorUtils.adaptToAccent(MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary), root.color), root.color, 0.5)
    property color colPrimaryHover: ColorUtils.mix(ColorUtils.adaptToAccent(MonitorThemes.shellColorForItem(root, "colPrimaryHover", Appearance.colors.colPrimaryHover), root.color), root.color, 0.3)
    property color colPrimaryActive: ColorUtils.mix(ColorUtils.adaptToAccent(MonitorThemes.shellColorForItem(root, "colPrimaryActive", Appearance.colors.colPrimaryActive), root.color), root.color, 0.3)
    property color colSecondary: ColorUtils.mix(ColorUtils.adaptToAccent(MonitorThemes.shellColorForItem(root, "colSecondary", Appearance.colors.colSecondary), root.color), root.color, 0.5)
    property color colSecondaryContainer: ColorUtils.mix(MonitorThemes.colorForItem(root, "secondary_container", Appearance.m3colors.m3secondaryContainer), root.color, 0.15)
    property color colSecondaryContainerHover: ColorUtils.mix(MonitorThemes.shellColorForItem(root, "colSecondaryContainerHover", Appearance.colors.colSecondaryContainerHover), root.color, 0.3)
    property color colSecondaryContainerActive: ColorUtils.mix(MonitorThemes.shellColorForItem(root, "colSecondaryContainerActive", Appearance.colors.colSecondaryContainerActive), root.color, 0.5)
    property color colOnPrimary: ColorUtils.mix(ColorUtils.adaptToAccent(MonitorThemes.colorForItem(root, "on_primary", Appearance.m3colors.m3onPrimary), root.color), root.color, 0.5)
    property color colOnSecondaryContainer: ColorUtils.mix(MonitorThemes.colorForItem(root, "on_secondary_container", Appearance.m3colors.m3onSecondaryContainer), root.color, 0.5)
}
