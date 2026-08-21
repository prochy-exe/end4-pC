import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Controls

/**
 * Does not include visual layout, but includes the easily neglected colors.
 */
TextInput {
    color: MonitorThemes.shellColorForItem(parent, "colOnLayer1", Appearance.colors.colOnLayer1)
    renderType: Text.NativeRendering
    selectedTextColor: MonitorThemes.colorForItem(parent, "on_secondary_container", Appearance.m3colors.m3onSecondaryContainer)
    selectionColor: MonitorThemes.shellColorForItem(parent, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
}
