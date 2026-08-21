import qs.services
import QtQuick
import QtQuick.Effects
import qs.modules.common

RectangularShadow {
    required property var target
    anchors.fill: target
    radius: target.radius
    blur: 0.9 * Appearance.sizes.elevationMargin
    offset: Qt.vector2d(0.0, 1.0)
    spread: 1
    color: MonitorThemes.shellColorForItem(parent, "colShadow", Appearance.colors.colShadow)
    cached: true
}
