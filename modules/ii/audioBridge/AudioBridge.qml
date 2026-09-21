import qs
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Popup wrapper for the dx5ii-bridge/wamp-bridge control widget - both are
// external C daemons with their own WebSocket control APIs (see
// services/Dx5iiBridge.qml and services/WampBridge.qml, which are thin
// wrappers around those APIs, not reimplementations). This file only owns
// the popup chrome (open/close, positioning, dismiss-on-outside-click);
// AudioBridgeContent has the actual controls.
//
// Positioned and dismissed the same way OnScreenDisplay.qml/Overview.qml
// are, rather than Cheatsheet.qml's full-screen-overlay approach: the
// window only spans its own content (via PopupPlacement's bar-hugging
// anchors), and `mask` restricts its actual hit-testable region to that
// content. A full-screen transparent window (Cheatsheet's approach)
// captures every click anywhere on screen, so clicking on its own empty
// background never moves Hyprland's focus to another surface - the focus
// grab this used to use for outside-click dismissal would never see that
// as a "clear" event. Restricting the mask to just the content lets a
// click anywhere else genuinely reach the surface behind it (or the
// desktop), which is what actually triggers a focus-grab dismissal.
Scope {
    id: root

    readonly property string popupPosition: "bar"
    readonly property real popupEdgeGap: Appearance.sizes.hyprlandGapsOut
    readonly property var popupAnchors: PopupPlacement.barAnchors(root.popupPosition, true, true)

    Loader {
        id: popupLoader
        active: GlobalStates.audioBridgeOpen
        sourceComponent: PanelWindow {
            id: popupWindow
            color: "transparent"
            screen: PopupPlacement.resolveScreen("focused", "")

            readonly property bool barVisibleOnScreen: PopupPlacement.barInfoFor(popupWindow.screen).present
            readonly property var popupMargins: PopupPlacement.barMargins(root.popupPosition, true, root.popupAnchors,
                root.popupEdgeGap,
                popupWindow.screen?.width ?? 0, popupWindow.screen?.height ?? 0,
                PopupPlacement.usableRectFor(popupWindow.screen),
                // Unlike the ticker/Super+M menu, this popup is opened by
                // clicking rather than read as an extension of the bar
                // itself - wants a real gap below the bar, not just enough
                // margin to reach it. A single gapsOut (5px default) reads
                // as touching in practice: the gap, the pill's own edge
                // shading and the card's background are all dark, so there's
                // too little contrast for a single gapsOut to register as
                // visibly separate - doubled here so it reads clearly.
                Appearance.sizes.hyprlandGapsOut * 2)

            WlrLayershell.namespace: "quickshell:audioBridge"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                top: root.popupAnchors.top
                bottom: root.popupAnchors.bottom
                left: root.popupAnchors.left
                right: root.popupAnchors.right
            }
            // "bar" hugs the bar with an already-exact margin, matching
            // MediaControls.qml/OnScreenDisplay.qml's own reasoning for
            // this - it shouldn't also get pushed further by the bar's
            // exclusive zone.
            exclusionMode: (root.popupPosition === "bar" || !popupWindow.barVisibleOnScreen) ? ExclusionMode.Ignore : ExclusionMode.Normal
            exclusiveZone: 0
            margins {
                top: popupWindow.popupMargins.top
                bottom: popupWindow.popupMargins.bottom
                left: popupWindow.popupMargins.left
                right: popupWindow.popupMargins.right
            }

            implicitWidth: contentWrapper.implicitWidth
            implicitHeight: contentWrapper.implicitHeight
            visible: popupLoader.active

            mask: Region { item: contentWrapper }

            Component.onCompleted: {
                Dx5iiBridge.ensureStarted()
                WampBridge.ensureStarted()
                GlobalFocusGrab.addDismissable(popupWindow)
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(popupWindow)
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.audioBridgeOpen = false
                }
            }

            Shortcut {
                sequence: "Escape"
                onActivated: GlobalStates.audioBridgeOpen = false
            }

            Item {
                id: contentWrapper
                implicitWidth: bridgeContent.implicitWidth
                implicitHeight: bridgeContent.implicitHeight

                AudioBridgeContent {
                    id: bridgeContent
                }
            }
        }
    }

    IpcHandler {
        target: "audioBridge"

        function toggle(): void {
            GlobalStates.audioBridgeOpen = !GlobalStates.audioBridgeOpen;
        }
        function open(): void {
            GlobalStates.audioBridgeOpen = true;
        }
        function close(): void {
            GlobalStates.audioBridgeOpen = false;
        }

        // Meant for keyboard shortcuts (bind these via a Settings > Keybinds
        // custom bind, e.g. `qs ipc call audioBridge volumeUp 5`, or a
        // direct Hyprland bind) - these act headlessly, without opening the
        // popup. AudioBridgeRouter decides which device (DX5 II or WiiM) is
        // actually targeted, same logic the popup itself uses, so these
        // can't disagree with what the popup would show. The OSD reacts on
        // its own to whatever these end up changing (see
        // OnScreenDisplay.qml's audioBridge Connections), not something
        // these call directly.
        function volumeUp(step: int): void {
            AudioBridgeRouter.volumeUp(step);
        }
        function volumeDown(step: int): void {
            AudioBridgeRouter.volumeDown(step);
        }
        function muteToggle(): void {
            AudioBridgeRouter.toggleMute();
        }
        function outputNext(): void {
            AudioBridgeRouter.cycleOutput(1);
        }
        function outputPrev(): void {
            AudioBridgeRouter.cycleOutput(-1);
        }
    }

    GlobalShortcut {
        name: "audioBridgeToggle"
        description: "Toggles the DX5II/WiiM audio control popup"

        onPressed: {
            GlobalStates.audioBridgeOpen = !GlobalStates.audioBridgeOpen;
        }
    }
}
