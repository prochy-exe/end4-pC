import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Controls

/**
 * Does not include visual layout, but includes the easily neglected colors.
 */
TextArea {
    renderType: Text.NativeRendering
    selectedTextColor: MonitorThemes.colorForItem(parent, "on_secondary_container", Appearance.m3colors.m3onSecondaryContainer)
    selectionColor: MonitorThemes.shellColorForItem(parent, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
    placeholderTextColor: MonitorThemes.colorForItem(parent, "outline", Appearance.m3colors.m3outline)
    color: MonitorThemes.shellColorForItem(parent, "colOnLayer0", Appearance.colors.colOnLayer0)
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
}
