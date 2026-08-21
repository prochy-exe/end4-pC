import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

TextField {
    id: filterField

    property alias colBackground: background.color

    Layout.fillHeight: true
    implicitWidth: 200
    padding: 10

    placeholderTextColor: MonitorThemes.shellColorForItem(parent, "colSubtext", Appearance.colors.colSubtext)
    color: MonitorThemes.shellColorForItem(parent, "colOnLayer1", Appearance.colors.colOnLayer1)
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: Text.NativeRendering
    selectedTextColor: MonitorThemes.shellColorForItem(parent, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
    selectionColor: MonitorThemes.shellColorForItem(parent, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)

    background: Rectangle {
        id: background
        color: MonitorThemes.shellColorForItem(parent, "colLayer1", Appearance.colors.colLayer1)
        radius: Appearance.rounding.full
    }
}
