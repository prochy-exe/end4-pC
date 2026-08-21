import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

ProgressBar {
    indeterminate: true
    Material.accent: MonitorThemes.shellColorForItem(parent, "colPrimary", Appearance.colors.colPrimary)
}
