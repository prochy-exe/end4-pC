import qs.services
import qs.modules.common
import QtQuick

RippleButton {
    id: root

    buttonRadius: 0
    implicitHeight: 36
    implicitWidth: buttonTextWidget.implicitWidth + 14 * 2

    contentItem: StyledText {
        id: buttonTextWidget
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        text: root.buttonText
        horizontalAlignment: Text.AlignLeft
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.enabled ? MonitorThemes.colorForItem(root, "on_surface", Appearance.m3colors.m3onSurface) : MonitorThemes.colorForItem(root, "outline", Appearance.m3colors.m3outline)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
