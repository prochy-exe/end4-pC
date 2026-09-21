pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function updateHoveredMonitorFromCursor() {
        const hoveredScreen = Quickshell.screens.find(s => {
            const mon = Hyprland.monitorFor(s)
            if (!mon) {
                return false
            }
            const monWidth = s.width
            const monHeight = s.height
            return root.cursorGlobalX >= mon.x
                && root.cursorGlobalX < mon.x + monWidth
                && root.cursorGlobalY >= mon.y
                && root.cursorGlobalY < mon.y + monHeight
        })
        if (!hoveredScreen) {
            return
        }
        root.hoveredMonitorName = hoveredScreen.name
        root.controlsMonitorName = hoveredScreen.name
    }

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
        root.postMode = false
        root.activeMonitorName = ""
    }

    function currentFocusedMonitorName() {
        const focusedName = Hyprland.focusedMonitor?.name
        return focusedName ?? Quickshell.screens[0]?.name ?? ""
    }

    function openSelector() {
        root.controlsMonitorName = root.currentFocusedMonitorName()
        root.hoveredMonitorName = root.controlsMonitorName
        console.warn(`[RegionSelector DEBUG] openSelector action=${root.action} selectionMode=${root.selectionMode} controlsMonitor=${root.controlsMonitorName} screens=${Quickshell.screens.map(s => s.name).join(",")}`)
        if (root.controlsMonitorName === "") {
            console.warn("[RegionSelector DEBUG] openSelector aborted: no controls monitor")
            return
        }
        GlobalStates.regionSelectorOpen = true
        console.warn(`[RegionSelector DEBUG] regionSelectorOpen=${GlobalStates.regionSelectorOpen}`)
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property bool recordSystemAudio: Config.options.screenRecord.recordSystemAudio
    property bool recordMicAudio: Config.options.screenRecord.recordMicAudio
    property bool showInputOverlay: Config.options.screenRecord.showInputOverlay
    property string controlsMonitorName: ""
    property string hoveredMonitorName: ""
    // Name of the monitor whose RegionSelection window currently has a locked
    // selection, if any - only that window should hold exclusive keyboard
    // focus while multiple per-monitor windows are open. Empty = unclaimed.
    property string activeMonitorName: ""
    // Bumped whenever any monitor's window catches Ctrl+C, so the one actually
    // holding the locked selection (which may not be the one that caught the
    // key) knows to confirm it. See RegionSelection.qml's confirmRequested.
    property int confirmSelectionSignal: 0
    property real cursorGlobalX: -1
    property real cursorGlobalY: -1
    property bool postMode: false

    function triggerSidebarTranslator(text) {
        const payload = `${text ?? ""}`
        if (payload.trim().length === 0)
            return
        Quickshell.execDetached(["bash", "-c",
            `pid=$(pgrep -x "qs|quickshell" | head -n1) && exec qs ipc --pid "$pid" call sidebarLeft openTranslator '${payload.replace(/'/g, "'\\''")}'`
        ])
    }

    Process {
        id: cursorPosProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",")
                if (parts.length < 2) {
                    return
                }
                const x = parseFloat(parts[0])
                const y = parseFloat(parts[1])
                if (Number.isNaN(x) || Number.isNaN(y)) {
                    return
                }
                root.cursorGlobalX = x
                root.cursorGlobalY = y
                root.updateHoveredMonitorFromCursor()
            }
        }
    }

    Timer {
        interval: 40
        repeat: true
        running: GlobalStates.regionSelectorOpen && !root.postMode
        onTriggered: {
            if (!cursorPosProc.running) {
                cursorPosProc.running = true
            }
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                Component.onCompleted: console.warn(`[RegionSelector DEBUG] RegionSelection created screen=${screen?.name ?? "null"} showControls=${showControls} size=${width}x${height}`)
                onDismiss: root.dismiss()
                onOcrTranslateRequested: text => root.triggerSidebarTranslator(text)
                onRecordingStarted: root.postMode = true
                onSelectionModeChanged: root.selectionMode = selectionMode
                onActionChanged: root.action = action
                onRecordSystemAudioChanged: root.recordSystemAudio = recordSystemAudio
                onRecordMicAudioChanged: root.recordMicAudio = recordMicAudio
                onShowInputOverlayChanged: root.showInputOverlay = showInputOverlay
                action: root.action
                selectionMode: root.selectionMode
                recordSystemAudio: root.recordSystemAudio
                recordMicAudio: root.recordMicAudio
                showInputOverlay: root.showInputOverlay
                showControls: regionSelectorLoader.modelData.name === root.controlsMonitorName
                onShowControlsChanged: console.warn(`[RegionSelector DEBUG] showControls changed screen=${screen?.name ?? "null"} showControls=${showControls} controlsMonitor=${root.controlsMonitorName}`)
                cursorGlobalX: root.cursorGlobalX
                cursorGlobalY: root.cursorGlobalY
                postMode: root.postMode
                keyboardFocusAllowed: root.activeMonitorName === "" || root.activeMonitorName === regionSelectorLoader.modelData.name
                isActiveMonitor: regionSelectorLoader.modelData.name === root.activeMonitorName
                anySelectionLocked: root.activeMonitorName !== ""
                confirmSelectionSignal: root.confirmSelectionSignal
                onConfirmRequested: root.confirmSelectionSignal++
                onSelectionLockedChanged: {
                    if (selectionLocked) {
                        root.activeMonitorName = regionSelectorLoader.modelData.name
                    } else if (root.activeMonitorName === regionSelectorLoader.modelData.name) {
                        root.activeMonitorName = ""
                    }
                }
            }
        }
    }

    function screenshot() {
        if (Persistent.states.record.enable) {
            const saveDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : "";
            if (saveDir !== "") {
                const cmd = `mkdir -p '${saveDir}' && filePath="${saveDir}/screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && grim -g "$(slurp)" "$filePath" && cat "$filePath" | wl-copy && notify-send "Screenshot Saved" "Saved to $filePath" -a "Screen Snip" -i "image-x-generic"`;
                Quickshell.execDetached(["bash", "-c", cmd]);
            } else {
                const cmd = `grim -g "$(slurp)" - | wl-copy && notify-send "Screenshot Copied" "Copied to clipboard" -a "Screen Snip" -i "image-x-generic"`;
                Quickshell.execDetached(["bash", "-c", cmd]);
            }
            return;
        }
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function screenshotOrStopRecording() {
        root.dismiss()
        Quickshell.execDetached([
            "bash",
            "-c",
            `if pgrep wf-recorder >/dev/null; then '${Directories.recordScriptPath}'; else pid=$(pgrep -x "qs|quickshell" | head -n1) && qs ipc --pid "$pid" call region screenshot; fi`
        ])
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        root.openSelector()
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function record() {
        if (Persistent.states.record.enable) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            return;
        }
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.recordSystemAudio = Config.options.screenRecord.recordSystemAudio
        root.recordMicAudio = Config.options.screenRecord.recordMicAudio
        root.showInputOverlay = Config.options.screenRecord.showInputOverlay
        // If already open then re-trigger to stop recording
        if (GlobalStates.regionSelectorOpen) GlobalStates.regionSelectorOpen = false
        root.openSelector()
    }

    function recordWithSound() {
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.recordSystemAudio = true
        root.recordMicAudio = false
        // If already open then re-trigger to stop recording
        if (GlobalStates.regionSelectorOpen) GlobalStates.regionSelectorOpen = false
        root.openSelector()
    }

    function recordWithOptions(systemAudio, micAudio) {
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.recordSystemAudio = systemAudio
        root.recordMicAudio = micAudio
        if (GlobalStates.regionSelectorOpen) GlobalStates.regionSelectorOpen = false
        root.openSelector()
    }

    function stopRecording() {
        root.dismiss()
        Quickshell.execDetached(["bash", "-c", `pgrep wf-recorder >/dev/null && '${Directories.recordScriptPath}'`])
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
        function recordWithOptions(systemAudio: bool, micAudio: bool): void {
            root.recordWithOptions(systemAudio, micAudio)
        }
        function stopRecording() {
            root.stopRecording()
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshotOrStopRecording()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
    GlobalShortcut {
        name: "regionStopRecording"
        description: "Stops active screen recording"
        onPressed: root.stopRecording()
    }
}
