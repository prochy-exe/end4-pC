import qs
import qs.modules.common
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Loader {
        id: cheatsheetLoader
        active: GlobalStates.cheatsheetOpen
        sourceComponent: PanelWindow {
            id: cheatsheetWindow
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            visible: true
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            HyprlandFocusGrab {
                id: grab
                windows: [cheatsheetWindow]
                active: false
                onCleared: () => {
                    if (!active) GlobalStates.cheatsheetOpen = false;
                }
            }

            Connections {
                target: GlobalStates
                function onCheatsheetOpenChanged() {
                    delayedGrabTimer.restart();
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration
                onTriggered: {
                    grab.active = GlobalStates.cheatsheetOpen;
                }
            }

            Shortcut {
                sequence: "Escape"
                onActivated: GlobalStates.cheatsheetOpen = false
            }

            CheatsheetContent {
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen;
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles the keybind cheatsheet"

        onPressed: {
            GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen;
        }
    }
}
