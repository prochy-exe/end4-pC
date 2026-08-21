import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button

    property string buttonIcon
    property string buttonText
    property bool keyboardDown: false
    property real size: 120

    buttonRadius: (button.focus || button.down) ? size / 2 : Appearance.rounding.verylarge
    colBackground: button.keyboardDown ? MonitorThemes.shellColorForItem(parent, "colSecondaryContainerActive", Appearance.colors.colSecondaryContainerActive) : 
        button.focus ? MonitorThemes.shellColorForItem(parent, "colPrimary", Appearance.colors.colPrimary) : 
        MonitorThemes.shellColorForItem(parent, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
    colBackgroundHover: MonitorThemes.shellColorForItem(parent, "colPrimary", Appearance.colors.colPrimary)
    colRipple: MonitorThemes.shellColorForItem(parent, "colPrimaryActive", Appearance.colors.colPrimaryActive)
    property color colText: (button.down || button.keyboardDown || button.focus || button.hovered) ?
        MonitorThemes.colorForItem(parent, "on_primary", Appearance.m3colors.m3onPrimary) : MonitorThemes.shellColorForItem(parent, "colOnLayer0", Appearance.colors.colOnLayer0)

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    background.implicitHeight: size
    background.implicitWidth: size

    Behavior on buttonRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = true
            button.clicked()
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = false
            event.accepted = true;
        }
    }

    contentItem: MaterialSymbol {
        id: icon
        anchors.fill: parent
        color: button.colText
        horizontalAlignment: Text.AlignHCenter
        iconSize: 45
        text: buttonIcon
    }

    StyledToolTip {
        text: buttonText
    }

}
