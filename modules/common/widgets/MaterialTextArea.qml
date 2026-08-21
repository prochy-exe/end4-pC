import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

/**
 * Material 3 styled TextArea (filled style)
 * https://m3.material.io/components/text-fields/overview
 * Note: We don't use NativeRendering because it makes the small placeholder text look weird
 */
TextArea {
    id: root
    Material.theme: Material.System
    Material.accent: MonitorThemes.colorForItem(root, "primary", Appearance.m3colors.m3primary)
    Material.primary: MonitorThemes.colorForItem(root, "primary", Appearance.m3colors.m3primary)
    Material.background: MonitorThemes.colorForItem(root, "surface", Appearance.m3colors.m3surface)
    Material.foreground: MonitorThemes.colorForItem(root, "on_surface", Appearance.m3colors.m3onSurface)
    Material.containerStyle: Material.Filled
    renderType: Text.QtRendering

    selectedTextColor: MonitorThemes.colorForItem(root, "on_secondary_container", Appearance.m3colors.m3onSecondaryContainer)
    selectionColor: MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
    placeholderTextColor: MonitorThemes.colorForItem(root, "outline", Appearance.m3colors.m3outline)

    background: Rectangle {
        implicitHeight: 56
        color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1) 
        topLeftRadius: 4
        topRightRadius: 4
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: root.focus ? MonitorThemes.colorForItem(root, "primary", Appearance.m3colors.m3primary) : 
                root.hovered ? MonitorThemes.colorForItem(root, "outline", Appearance.m3colors.m3outline) : MonitorThemes.colorForItem(root, "outline_variant", Appearance.m3colors.m3outlineVariant)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap
}
