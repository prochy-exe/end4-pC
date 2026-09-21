import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical
    readonly property real barCenterOnlyOffset: (Config.options.bar.centerOnlyReserveFrame && root.centerOnly)
        ? Config.options.bar.frameThickness
        : Appearance.sizes.barHeight

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.sidebarRightOpen
        property var targetScreen: Quickshell.screens[0]
        screen: targetScreen
        readonly property string monitorName: screen?.name ?? ""
        readonly property bool barVertical: Config.getBarSetting(monitorName, ["vertical"], Config.options.bar.vertical)
        readonly property bool barAtBottom: Config.getBarSetting(monitorName, ["bottom"], Config.options.bar.bottom)
        readonly property int currentCornerStyle: Config.getBarSetting(monitorName, ["cornerStyle"], Config.options.bar.cornerStyle)

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
            left: animatedEntrance
        }

        margins {
            top: {
                if (!centerOnly)
                    return !barVertical && !barAtBottom ? Appearance.sizes.barHeight : 0;
                switch (panelWindow.currentCornerStyle) {
                    case 0: return -Appearance.sizes.barHeight;
                    case 1: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                    case 2: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                    case 3: return -Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut;
                    default: return 0;
                }
            }
            bottom: !centerOnly && !barVertical && barAtBottom ? Appearance.sizes.barHeight : 0
        }

        onVisibleChanged: {
            if (visible)
                targetScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            if (visible) {
                MonitorThemes.activateForSurface(panelWindow)
            }
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

            MouseArea {
                id: outsideClickArea
                anchors.fill: parent
                enabled: panelWindow.animatedEntrance
                visible: panelWindow.animatedEntrance
                onClicked: panelWindow.hide()
            }

            Item {
                id: entranceWrapper
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: sidebarWidth
                clip: true

                readonly property bool open: GlobalStates.sidebarRightOpen
                property real cachedParentWidth: sidebarWidth
                readonly property real restX: cachedParentWidth - width
                x: panelWindow.animatedEntrance ? (open ? restX : cachedParentWidth) : restX

                Connections {
                    target: entranceWrapper.parent
                    function onWidthChanged() {
                        if (entranceWrapper.parent.width > 0)
                            entranceWrapper.cachedParentWidth = entranceWrapper.parent.width;
                    }
                }

                Behavior on x {
                    enabled: panelWindow.animatedEntrance
                    NumberAnimation {
                        duration: entranceWrapper.open
                            ? Appearance.animation.sidebarSlideEnter.duration
                            : Appearance.animation.sidebarSlideExit.duration
                        easing.type: entranceWrapper.open
                            ? Appearance.animation.sidebarSlideEnter.type
                            : Appearance.animation.sidebarSlideExit.type
                        easing.bezierCurve: entranceWrapper.open
                            ? Appearance.animation.sidebarSlideEnter.bezierCurve
                            : Appearance.animation.sidebarSlideExit.bezierCurve
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                    z: -1
                }

                Loader {
                    id: sidebarContentLoader
                    active: panelWindow.reallyVisible || Config?.options.sidebar.keepRightSidebarLoaded
                    anchors {
                        fill: parent
                        margins: Appearance.sizes.hyprlandGapsOut
                        leftMargin: Appearance.sizes.elevationMargin
                    }
                    width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                    height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

                    focus: GlobalStates.sidebarRightOpen
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: SidebarRightContent {}
                }
            }
        }

            sourceComponent: SidebarRightContent { monitorName: panelWindow.monitorName }
        }
    }
}