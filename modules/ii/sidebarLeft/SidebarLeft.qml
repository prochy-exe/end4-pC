import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool detach: false
    property bool pin: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent
    property string pendingTabName: ""
    property string pendingTranslatorPrefill: ""
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical
    readonly property real barCenterOnlyOffset: (Config.options.bar.centerOnlyReserveFrame && root.centerOnly)
        ? Config.options.bar.frameThickness
        : Appearance.sizes.barHeight

    function forceTab(tabName) {
        const tab = `${tabName ?? ""}`.trim().toLowerCase()
        if (tab.length === 0 || !root.sidebarContent)
            return false
        if (typeof root.sidebarContent.tabIndexForRequest !== "function")
            return false
        const index = root.sidebarContent.tabIndexForRequest(tab)
        if (index < 0)
            return false
        root.sidebarContent.currentTabIndex = index
        return root.sidebarContent.currentTabIndex === index
    }

    function toggleDetach() {
        root.detach = !root.detach;
    }

    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    Timer {
        id: pendingTabApplyTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (!root.pendingTabName || root.pendingTabName.length === 0)
                return
            if (!root.forceTab(root.pendingTabName)) {
                // One extra retry for slow content/tab initialization paths.
                pendingTabApplyRetryTimer.restart()
                return
            }
            if (root.pendingTabName === "translator" && root.sidebarContent
                && typeof root.sidebarContent.forceTranslatorPrefill === "function") {
                if (root.sidebarContent.forceTranslatorPrefill(root.pendingTranslatorPrefill))
                    root.pendingTranslatorPrefill = ""
            }
            root.pendingTabName = ""
        }
    }

    Timer {
        id: pendingTabApplyRetryTimer
        interval: 260
        repeat: false
        onTriggered: {
            if (!root.pendingTabName || root.pendingTabName.length === 0)
                return
            if (root.forceTab(root.pendingTabName)) {
                if (root.pendingTabName === "translator" && root.sidebarContent
                    && typeof root.sidebarContent.forceTranslatorPrefill === "function") {
                    if (root.sidebarContent.forceTranslatorPrefill(root.pendingTranslatorPrefill))
                        root.pendingTranslatorPrefill = ""
                }
                root.pendingTabName = ""
            }
        }
    }

    function togglePin() {
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else root.pin = !root.pin;
    }

    Component.onCompleted: {
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
            "monitorName": Hyprland.focusedMonitor?.name ?? "",
        });
        sidebarLoader.item.contentParent.children = [root.sidebarContent];
    }

    onDetachChanged: {
        if (root.detach) {
            GlobalFocusGrab.removeDismissable(sidebarLoader.item) // Remove sidebar from the focus grab system
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            detachedSidebarLoader.item.contentParent.children = [sidebarContent];
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarLoader.item.contentParent.children = [sidebarContent];
        }
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: panelWindow
            readonly property bool animatedEntrance: WM.compositor !== "hyprland"
            visible: GlobalStates.sidebarLeftOpen
            property var targetScreen: Quickshell.screens[0]
            screen: targetScreen
            readonly property string monitorName: screen?.name ?? ""
            readonly property bool barVertical: Config.getBarSetting(monitorName, ["vertical"], Config.options.bar.vertical)
            readonly property bool barAtBottom: Config.getBarSetting(monitorName, ["bottom"], Config.options.bar.bottom)
            readonly property int currentCornerStyle: Config.getBarSetting(monitorName, ["cornerStyle"], Config.options.bar.cornerStyle)
            
            property bool extend: false
            property real sidebarWidth: panelWindow.extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.pin ? sidebarWidth : 0
            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Request keyboard focus only while visible to avoid stale focus state churn.
            WlrLayershell.keyboardFocus: GlobalStates.sidebarLeftOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
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

            mask: Region {
                item: panelWindow.animatedEntrance ? fullMaskArea : sidebarLeftBackground
            }

            onVisibleChanged: {
                if (visible)
                    targetScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
                if (visible) {
                    MonitorThemes.activateForSurface(this)
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

            // Content
            Item {
                id: fullMaskArea
                anchors.fill: parent
            }

            MouseArea {
                id: outsideClickArea
                anchors.fill: parent
                enabled: panelWindow.animatedEntrance
                visible: panelWindow.animatedEntrance
                onClicked: panelWindow.hide()
            }

            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
            }
            Rectangle {
                id: sidebarLeftBackground
                anchors.top: parent.top
                anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                color: MonitorThemes.shellColorForItem(panelWindow, "colLayer0", Appearance.colors.colLayer0)
                border.width: 1
                border.color: MonitorThemes.shellColorForItem(panelWindow, "colLayer0Border", Appearance.colors.colLayer0Border)
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                readonly property bool animatedEntrance: panelWindow.animatedEntrance
                readonly property bool sidebarOpen: GlobalStates.sidebarLeftOpen
                x: Appearance.sizes.hyprlandGapsOut - (animatedEntrance && !sidebarOpen ? width : 0)

                Behavior on x {
                    enabled: sidebarLeftBackground.animatedEntrance
                    NumberAnimation {
                        duration: sidebarLeftBackground.sidebarOpen
                            ? Appearance.animation.elementMoveEnter.duration
                            : Appearance.animation.elementMoveExit.duration
                        easing.type: sidebarLeftBackground.sidebarOpen
                            ? Appearance.animation.elementMoveEnter.type
                            : Appearance.animation.elementMoveExit.type
                        easing.bezierCurve: sidebarLeftBackground.sidebarOpen
                            ? Appearance.animation.elementMoveEnter.bezierCurve
                            : Appearance.animation.elementMoveExit.bezierCurve
                    }
                }

                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O) {
                            panelWindow.extend = !panelWindow.extend;
                        } else if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        } else if (event.key === Qt.Key_P) {
                            root.togglePin();
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            onVisibleChanged: {
                if (!visible) GlobalStates.sidebarLeftOpen = false;
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color: MonitorThemes.shellColorForItem(detachedSidebarRoot, "colLayer0", Appearance.colors.colLayer0)

                Keys.onPressed: (event) => {
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
            root.pendingTranslatorPrefill = ""
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }

        function openTab(tabName: string): void {
            const tab = `${tabName ?? ""}`.trim().toLowerCase()
            if (tab.length === 0) return
            GlobalStates.sidebarLeftRequestedTab = tab
            GlobalStates.sidebarLeftOpen = true
            root.pendingTabName = tab
            if (!root.forceTab(tab))
                pendingTabApplyTimer.restart()
        }

        function openTranslator(prefillText: string): void {
            let text = `${prefillText ?? ""}`
            if (text.trim().length === 0)
                text = `${GlobalStates.lastOcrText ?? ""}`
            if (text.trim().length === 0)
                text = `${Quickshell.clipboardText ?? ""}`
            GlobalStates.sidebarLeftRequestedTab = "translator"
            GlobalStates.sidebarLeftTranslatorPrefill = text
            GlobalStates.sidebarLeftOpen = true
            root.pendingTabName = "translator"
            root.pendingTranslatorPrefill = text
            const switched = root.forceTab("translator")
            if (root.sidebarContent && typeof root.sidebarContent.forceTranslatorPrefill === "function")
                if (root.sidebarContent.forceTranslatorPrefill(text))
                    root.pendingTranslatorPrefill = ""
            if (!switched)
                pendingTabApplyTimer.restart()
        }

        function openIntelligence(): void {
            GlobalStates.sidebarLeftRequestedTab = "intelligence"
            GlobalStates.sidebarLeftOpen = true
            root.pendingTabName = "intelligence"
            if (!root.forceTab("intelligence"))
                pendingTabApplyTimer.restart()
        }
    }

    CompositorGlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    CompositorGlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    CompositorGlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    CompositorGlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.detach = !root.detach;
        }
    }

}
