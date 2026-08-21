import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    property bool active: false

    horizontalPadding: Appearance.rounding.large
    verticalPadding: 12

    clip: true
    pointingHandCursor: !active    
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    colBackground: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colLayer3", Appearance.colors.colLayer3))
    colBackgroundHover: active ? colBackground : MonitorThemes.shellColorForItem(root, "colLayer3Hover", Appearance.colors.colLayer3Hover)
    colRipple: MonitorThemes.shellColorForItem(root, "colLayer3Active", Appearance.colors.colLayer3Active)
    buttonRadius: 0
}
