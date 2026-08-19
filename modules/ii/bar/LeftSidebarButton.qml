import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root
    property bool showPing: false
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    property real buttonPadding: 5

    visible: aiChatEnabled || translatorEnabled || animeEnabled

    implicitWidth: 32
    implicitHeight: 32

    buttonRadius: Appearance.rounding.full
    colBackground: isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : "transparent"
    colBackgroundHover: isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover) : MonitorThemes.shellColorForItem(root, "colLayer1Hover", Appearance.colors.colLayer1Hover)
    colRipple: isMaterial ? MonitorThemes.shellColorForItem(root, "colLayer1Active", Appearance.colors.colLayer1Active) : MonitorThemes.shellColorForItem(root, "colLayer1Active", Appearance.colors.colLayer1Active)
    colBackgroundToggled: MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
    colBackgroundToggledHover: MonitorThemes.shellColorForItem(root, "colSecondaryContainerHover", Appearance.colors.colSecondaryContainerHover)
    colRippleToggled: MonitorThemes.shellColorForItem(root, "colSecondaryContainerActive", Appearance.colors.colSecondaryContainerActive)
    toggled: GlobalStates.sidebarLeftOpen

    onPressed: {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }
    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    CustomIcon {
        id: distroIcon
        anchors.centerIn: parent
        width: root.isMaterial ? (root.vertical ? 24 : 22) : 19.5
        height: root.isMaterial ? (root.vertical ? 24 : 22) : 19.5
        source: Config.options.custom.distroIcon
        colorize: Config.options.custom.colorizeIcon
        color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: MonitorThemes.shellColorForItem(root, "colTertiary", Appearance.colors.colTertiary)
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}