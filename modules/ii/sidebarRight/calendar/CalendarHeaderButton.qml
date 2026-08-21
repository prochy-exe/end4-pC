import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button
    property string buttonText: ""
    property string tooltipText: ""
    property bool forceCircle: false

    implicitHeight: 30
    implicitWidth: forceCircle ? implicitHeight : (contentItem.implicitWidth + 10 * 2)
    Behavior on implicitWidth {
        SmoothedAnimation {
            velocity: Appearance.animation.elementMove.velocity
        }
    }

    background.anchors.fill: button
    buttonRadius: Appearance.rounding.full
    colBackground: MonitorThemes.shellColorForItem(parent, "colLayer2", Appearance.colors.colLayer2)
    colBackgroundHover: MonitorThemes.shellColorForItem(parent, "colLayer2Hover", Appearance.colors.colLayer2Hover)
    colRipple: MonitorThemes.shellColorForItem(parent, "colLayer2Active", Appearance.colors.colLayer2Active)

    contentItem: StyledText {
        text: buttonText
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.larger
        color: MonitorThemes.shellColorForItem(parent, "colOnLayer1", Appearance.colors.colOnLayer1)
    }

    StyledToolTip {
        text: tooltipText
        extraVisibleCondition: tooltipText.length > 0
    }
}
