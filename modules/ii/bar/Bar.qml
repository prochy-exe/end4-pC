pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: bar

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            const enabledScreens = (!list || list.length === 0)
                ? screens
                : screens.filter(screen => list.includes(screen.name));
            return enabledScreens.filter(screen => !Config.getBarSetting(screen.name, ["vertical"], Config.options.bar.vertical));
        }
        LazyLoader {
            id: barLoader
            active: GlobalStates.barOpen && !GlobalStates.screenLocked && !GlobalStates.startupLockPending
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }

                property bool showCorners: !Config.options.bar.autoHide.enable || mustShow

                Timer {
                    id: cornerRevealTimer
                    interval: 65
                    onTriggered: barRoot.showCorners = true
                }

                onMustShowChanged: {
                    if (!Config.options.bar.autoHide.enable) return;
                    if (mustShow) {
                        cornerRevealTimer.restart()
                    } else {
                        cornerRevealTimer.stop()
                        barRoot.showCorners = false
                    }
                }
                property bool superShow: false
                property bool mustShow: hoverRegion.containsMouse || superShow
                property string currentMonitorName: barRoot.screen?.name ?? ""
                readonly property bool showBarBackground: Config.getBarSetting(currentMonitorName, ["showBackground"], Config.options.bar.showBackground)
                readonly property bool currentBottom: Config.getBarSetting(currentMonitorName, ["bottom"], Config.options.bar.bottom)
                readonly property int currentCornerStyle: Config.getBarSetting(currentMonitorName, ["cornerStyle"], Config.options.bar.cornerStyle)
                readonly property bool currentAutoHideEnable: Config.getBarSetting(currentMonitorName, ["autoHide", "enable"], Config.options.bar.autoHide.enable)
                readonly property bool currentAutoHidePushWindows: Config.getBarSetting(currentMonitorName, ["autoHide", "pushWindows"], Config.options.bar.autoHide.pushWindows)
                readonly property int currentAutoHideHoverRegionWidth: Config.getBarSetting(currentMonitorName, ["autoHide", "hoverRegionWidth"], Config.options.bar.autoHide.hoverRegionWidth)
                property var thisMonitorData: HyprlandData.monitors.find(m => m.name === barRoot.screen?.name)
                property bool monitorHasFullscreen: HyprlandData.workspaceById[thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false
                property bool monitorHasSpecialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: (currentAutoHideEnable && (!mustShow || !currentAutoHidePushWindows)) ? 0 : Appearance.sizes.baseBarHeight + (currentCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) + (currentCornerStyle === 2 ? -6 : 0)
                WlrLayershell.namespace: "quickshell:bar"
                // Overlay layer only while special workspace sits on top of a fullscreen window on this monitor,
                // else Top layer so fullscreen apps cover the bar as normal (Hyprland buries Top layer under fullscreen+special).
                WlrLayershell.layer: (monitorHasFullscreen && monitorHasSpecialOpen) ? WlrLayer.Overlay : WlrLayer.Top
                implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                // When Overlay-layer, bar shares a layer with the screen-corner click zones (ScreenCorners.qml)
                // and same-layer overlap is resolved by stacking, not layer priority - bar was winning and
                // swallowing the tiny corner-open hit rects. Carve them out of the bar's own mask so clicks
                // reach the corners underneath. Only relevant on the edge the bar and corners share.
                property bool cutOutCornerOpenZones: (monitorHasFullscreen && monitorHasSpecialOpen) && (currentBottom === Config.options.sidebar.cornerOpen.bottom)
                property int cornerOpenCutWidth: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionWidth : 0
                property int cornerOpenCutHeight: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionHeight : 0
                mask: Region {
                    item: hoverMaskRegion
                    Region {
                        intersection: Intersection.Subtract
                        x: 0
                        y: currentBottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                    Region {
                        intersection: Intersection.Subtract
                        x: barRoot.width - barRoot.cornerOpenCutWidth
                        y: currentBottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                }
                color: "transparent"

                // Positioning
                anchors {
                    top: !currentBottom
                    bottom: currentBottom
                    left: true
                    right: true
                }

                margins {
                    top: currentCornerStyle === 3 ? 5 : 0
                    right: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                    bottom: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1 || currentCornerStyle === 3 ? 5 : 0
                }

                // Include in focus grab
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(barRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            topMargin: -currentAutoHideHoverRegionWidth
                            bottomMargin: -currentAutoHideHoverRegionWidth
                        }
                    }

                    RoundCorner {
                        id: leftPillCorner
                        visible: barContent.centerOnly && showBarBackground && currentCornerStyle === 0
                        x: barContent.centerPillX - implicitSize
                        implicitSize: Appearance.rounding.screenRounding
                        color: MonitorThemes.shellColorForItem(barRoot, "colLayer0", Appearance.colors.colLayer0)
                        corner: RoundCorner.CornerEnum.TopRight

                        states: State {
                            name: "bottom"
                            when: currentBottom
                            AnchorChanges {
                                target: leftPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: leftPillCorner
                                corner: RoundCorner.CornerEnum.BottomRight
                            }
                        }
                        AnchorChanges {
                            target: leftPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }

                    BarContent {
                        id: barContent
                        monitorName: barRoot.currentMonitorName
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: (currentAutoHideEnable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                        }
                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: currentBottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: (currentAutoHideEnable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    RoundCorner {
                        id: rightPillCorner
                        visible: barContent.centerOnly && showBarBackground && currentCornerStyle === 0
                        x: barContent.centerPillX + barContent.centerPillWidth
                        implicitSize: Appearance.rounding.screenRounding
                        color: MonitorThemes.shellColorForItem(barRoot, "colLayer0", Appearance.colors.colLayer0)
                        corner: RoundCorner.CornerEnum.TopLeft

                        states: State {
                            name: "bottom"
                            when: currentBottom
                            AnchorChanges {
                                target: rightPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: rightPillCorner
                                corner: RoundCorner.CornerEnum.BottomLeft
                            }
                        }
                        AnchorChanges {
                            target: rightPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }
                    
                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: showBarBackground && currentCornerStyle === 0 && !barContent.centerOnly

                        states: State {
                            name: "bottom"
                            when: currentBottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding

                            readonly property color decoratorColor: showBarBackground
                                ? (Config.options.bar.followFrameColor && Config.options.bar.frameColor
                                    ? Appearance.getColorFromName(Config.options.bar.frameColor)
                                    : Appearance.colors.colLayer0)
                                : "transparent"

                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? MonitorThemes.shellColorForItem(barRoot, "colLayer0", Appearance.colors.colLayer0) : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: currentBottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    right: parent.right
                                    top: !currentBottom ? parent.top : undefined
                                    bottom: currentBottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? MonitorThemes.shellColorForItem(barRoot, "colLayer0", Appearance.colors.colLayer0) : "transparent"

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: currentBottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    CompositorGlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    CompositorGlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    CompositorGlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
