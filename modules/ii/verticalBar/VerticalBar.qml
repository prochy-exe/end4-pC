import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Scope {
    id: bar

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            const enabledScreens = (!list || list.length === 0)
                ? screens
                : screens.filter(screen => list.includes(screen.name));
            return enabledScreens.filter(screen => Config.getBarSetting(screen.name, ["vertical"], Config.options.bar.vertical));
        }
        LazyLoader {
            id: barLoader
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow {
                id: barRoot
                screen: barLoader.modelData

                property var brightnessMonitor: Brightness.getMonitorForScreen(barLoader.modelData)
                
                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: { barRoot.superShow = true }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else { showBarTimer.stop(); barRoot.superShow = false; }
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
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: (currentAutoHideEnable && (!mustShow || !currentAutoHidePushWindows)) ? 0 :
                    Appearance.sizes.baseVerticalBarWidth + (currentCornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    + (currentCornerStyle === 3 ? (Config.options.hyprland.general.gapsOut || 5) : 0)
                WlrLayershell.namespace: "quickshell:verticalBar"
                implicitWidth: Appearance.sizes.verticalBarWidth + Appearance.rounding.screenRounding
                    + (currentCornerStyle === 3 ? (Config.options.hyprland.general.gapsOut || 5) : 0)
                mask: Region { item: hoverMaskRegion }
                color: "transparent"

                anchors {
                    left: !currentBottom
                    right: currentBottom
                    top: true
                    bottom: true
                }

                Component.onCompleted: { GlobalFocusGrab.addPersistent(barRoot); }
                Component.onDestruction: { GlobalFocusGrab.removePersistent(barRoot); }

                MouseArea {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors.fill: parent

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            leftMargin: -currentAutoHideHoverRegionWidth
                            rightMargin: -currentAutoHideHoverRegionWidth
                        }
                    }

                    RoundCorner {
                        id: topPillCorner
                        visible: barContent.centerOnly && showBarBackground && currentCornerStyle === 0
                        y: barContent.centerPillY - implicitSize
                        implicitSize: Appearance.rounding.screenRounding
                        color: MonitorThemes.shellColorForItem(parent, "colLayer0", Appearance.colors.colLayer0)
                        corner: RoundCorner.CornerEnum.BottomLeft

                        states: State {
                            name: "right"
                            when: currentBottom
                            AnchorChanges {
                                target: topPillCorner
                                anchors.left: undefined
                                anchors.right: barContent.right
                            }
                            PropertyChanges {
                                target: topPillCorner
                                corner: RoundCorner.CornerEnum.BottomRight
                            }
                        }
                        AnchorChanges {
                            target: topPillCorner
                            anchors.left: barContent.right
                            anchors.right: undefined
                        }
                    }

                    RoundCorner {
                        id: bottomPillCorner
                        visible: barContent.centerOnly && showBarBackground && currentCornerStyle === 0
                        y: barContent.centerPillY + barContent.centerPillHeight
                        implicitSize: Appearance.rounding.screenRounding
                        color: MonitorThemes.shellColorForItem(parent, "colLayer0", Appearance.colors.colLayer0)
                        corner: RoundCorner.CornerEnum.TopLeft

                        states: State {
                            name: "right"
                            when: currentBottom
                            AnchorChanges {
                                target: bottomPillCorner
                                anchors.left: undefined
                                anchors.right: barContent.right
                            }
                            PropertyChanges {
                                target: bottomPillCorner
                                corner: RoundCorner.CornerEnum.TopRight
                            }
                        }
                        AnchorChanges {
                            target: bottomPillCorner
                            anchors.left: barContent.right
                            anchors.right: undefined
                        }
                    }

                    VerticalBarContent {
                        id: barContent
                        
                        implicitWidth: Appearance.sizes.verticalBarWidth
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: parent.left
                            right: undefined
                            leftMargin: (currentAutoHideEnable && !mustShow)
                                ? -Appearance.sizes.verticalBarWidth 
                                : (currentCornerStyle === 3 ? (Config.options.hyprland.general.gapsOut || 5) : 0)
                        }
                        Behavior on anchors.leftMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "right"
                            when: currentBottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: parent.right
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.rightMargin: (currentAutoHideEnable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: barContent.right
                            right: undefined
                        }
                        width: Appearance.rounding.screenRounding
                        active: showBarBackground && currentCornerStyle === 0 && !barContent.centerOnly

                        states: State {
                            name: "right"
                            when: currentBottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: barContent.left
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: topCorner
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? MonitorThemes.shellColorForItem(parent, "colLayer0", Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: currentBottom
                                    PropertyChanges { topCorner.corner: RoundCorner.CornerEnum.TopRight }
                                }
                            }
                            RoundCorner {
                                id: bottomCorner
                                anchors {
                                    bottom: parent.bottom
                                    left: !currentBottom ? parent.left : undefined
                                    right: currentBottom ? parent.right : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? MonitorThemes.shellColorForItem(parent, "colLayer0", Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.BottomLeft
                                states: State {
                                    name: "bottom"
                                    when: currentBottom
                                    PropertyChanges { bottomCorner.corner: RoundCorner.CornerEnum.BottomRight }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"
        onPressed: { GlobalStates.barOpen = !GlobalStates.barOpen; }
    }
    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"
        onPressed: { GlobalStates.barOpen = true; }
    }
    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"
        onPressed: { GlobalStates.barOpen = false; }
    }
}
