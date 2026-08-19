import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

// Spawns one full-screen PopupEditorWindow per monitor while the live
// on-screen editor is open, and holds the drag/session state shared across
// all of them - same Variants-wrapping-a-Scope shape ScreenCorners.qml
// already uses for per-monitor windows.
//
// Genuine continuous cross-monitor dragging needs a global cursor position,
// which neither Quickshell.Hyprland nor Hyprland's own event socket expose
// as a push/reactive value (confirmed by reading the Hyprland IPC source and
// every event name Hyprland's socket2 emits - no pointer-move event exists
// at all). modules/ii/regionSelector/RegionSelector.qml already solves this
// exact problem for its own cross-monitor drag-select, by polling
// `hyprctl cursorpos` on a timer - same technique here. Only "specific"
// monitor items ever need this - "follow active monitor" items only ever
// have one real, interactive handle at a time (see PopupEditorWindow.qml),
// so their dragging is local-only and doesn't touch any of this.
Scope {
    id: overlayRoot

    property bool dragging: false
    property string draggingItemId: ""
    property string draggingLabel: ""
    property string draggingIconName: ""
    property color draggingAccentColor: "white"
    property bool draggingSupportsBar: true
    property string draggingOriginScreenName: ""
    property real cursorGlobalX: 0
    property real cursorGlobalY: 0
    // Set (only) while a "follow active monitor" item is being LOCALLY
    // dragged - deliberately separate from dragging/draggingItemId above,
    // which also enable the cross-monitor-only fallback catcher and ghost
    // on every window (see PopupEditHandle.qml's onPressed doc comment for
    // why conflating the two broke local drags near a monitor edge). Used
    // only for cluster-exclusion and the live cross-monitor preview mirror.
    property string localDraggingItemId: ""
    // Normalized "custom" position of whichever item is currently being
    // LOCALLY dragged (a "follow active monitor" item, which never leaves
    // its own monitor - see PopupEditHandle.qml's publishLivePosition()),
    // continuously updated for the duration of that drag so its read-only
    // mirrors on every OTHER monitor can track it live instead of only
    // updating once the drop actually commits.
    property real liveCustomX: 0.5
    property real liveCustomY: 0.5

    // Snapshot of every item's position/monitor fields, captured the moment
    // the editor opens - restored verbatim on Cancel/Escape so live changes
    // made while dragging (position is committed to Config immediately, for
    // real-time WYSIWYG feedback) can still be discarded as a whole.
    property var snapshot: null
    property string boundaryHintScreenName: ""

    readonly property var currentTargetScreen: overlayRoot.screenContaining(overlayRoot.cursorGlobalX, overlayRoot.cursorGlobalY)

    function screenContaining(gx, gy) {
        for (const s of Quickshell.screens) {
            if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height) return s
        }
        return null
    }

    function startDrag(itemId, label, iconName, accentColor, supportsBar, originScreenName) {
        overlayRoot.draggingItemId = itemId
        overlayRoot.draggingLabel = label
        overlayRoot.draggingIconName = iconName
        overlayRoot.draggingAccentColor = accentColor
        overlayRoot.draggingSupportsBar = supportsBar
        overlayRoot.draggingOriginScreenName = originScreenName
        overlayRoot.dragging = true
    }

    function endDrag() {
        overlayRoot.dragging = false
        overlayRoot.draggingItemId = ""
    }

    // Redundant release path for the cross-monitor drag: normally the
    // originating handle's own onReleased fires reliably (a held mouse
    // button is expected to keep delivering events to the surface that
    // grabbed it), but empirically that doesn't always happen once the
    // cursor has moved onto a different monitor's surface - every window
    // ALSO offers a full-screen catch-all (see PopupEditorWindow.qml) that
    // calls this if the origin didn't. Guarded on `dragging` so it's safe
    // no matter which one fires first, or if - rarely - both do.
    function customAnchorFor(itemId) {
        if (itemId === "ticker") return Config.options.media.tickerCustomAnchor
        if (itemId === "notifications") return Config.options.notifications.customAnchor
        if (itemId === "osd") return Config.options.osd.customAnchor
        return "top"
    }

    function finishDragFallback() {
        if (!overlayRoot.dragging) return
        const targetScreen = overlayRoot.currentTargetScreen
        if (targetScreen) {
            const result = PopupPlacement.resolveDrop(overlayRoot.draggingItemId, overlayRoot.draggingSupportsBar,
                overlayRoot.cursorGlobalX - targetScreen.x, overlayRoot.cursorGlobalY - targetScreen.y, targetScreen,
                overlayRoot.customAnchorFor(overlayRoot.draggingItemId))
            overlayRoot.commitPosition(overlayRoot.draggingItemId, targetScreen.name, result.position,
                result.customX ?? 0.5, result.customY ?? 0.5, result.customAnchor)
        }
        overlayRoot.endDrag()
    }

    // customAnchor is optional: a drop that landed on a named preset (or on
    // the bar) has no anchor to report and leaves the stored one alone, since
    // it only means anything while the position is "custom". It is no longer
    // a user setting - see PopupPlacement.inferCustomAnchor(), which derives
    // it from where the item was dropped.
    function commitPosition(itemId, monitorName, position, customX, customY, customAnchor) {
        if (itemId === "ticker") {
            Config.options.media.tickerPosition = position
            Config.options.media.tickerCustomX = customX
            Config.options.media.tickerCustomY = customY
            if (customAnchor) Config.options.media.tickerCustomAnchor = customAnchor
            if (Config.options.media.tickerMonitorMode === "specific") {
                Config.options.media.tickerMonitorName = monitorName
            }
        } else if (itemId === "notifications") {
            Config.options.notifications.position = position
            Config.options.notifications.customX = customX
            Config.options.notifications.customY = customY
            if (customAnchor) Config.options.notifications.customAnchor = customAnchor
            if (Config.options.notifications.monitorMode === "specific") {
                Config.options.notifications.monitorName = monitorName
            }
        } else if (itemId === "osd") {
            Config.options.osd.position = position
            Config.options.osd.customX = customX
            Config.options.osd.customY = customY
            if (customAnchor) Config.options.osd.customAnchor = customAnchor
            if (Config.options.osd.monitorMode === "specific") {
                Config.options.osd.monitorName = monitorName
            }
        }
    }

    function showBoundaryHint(screenName) {
        overlayRoot.boundaryHintScreenName = screenName
        boundaryHintTimer.restart()
    }

    Timer {
        id: boundaryHintTimer
        interval: 1600
        onTriggered: overlayRoot.boundaryHintScreenName = ""
    }

    function captureSnapshot() {
        return {
            tickerPosition: Config.options.media.tickerPosition,
            tickerMonitorMode: Config.options.media.tickerMonitorMode,
            tickerMonitorName: Config.options.media.tickerMonitorName,
            tickerCustomX: Config.options.media.tickerCustomX,
            tickerCustomY: Config.options.media.tickerCustomY,
            notifPosition: Config.options.notifications.position,
            notifMonitorMode: Config.options.notifications.monitorMode,
            notifMonitorName: Config.options.notifications.monitorName,
            notifCustomX: Config.options.notifications.customX,
            notifCustomY: Config.options.notifications.customY,
            osdPosition: Config.options.osd.position,
            osdMonitorMode: Config.options.osd.monitorMode,
            osdMonitorName: Config.options.osd.monitorName,
            osdCustomX: Config.options.osd.customX,
            osdCustomY: Config.options.osd.customY,
        }
    }

    function restoreSnapshot(s) {
        if (!s) return
        Config.options.media.tickerPosition = s.tickerPosition
        Config.options.media.tickerMonitorMode = s.tickerMonitorMode
        Config.options.media.tickerMonitorName = s.tickerMonitorName
        Config.options.media.tickerCustomX = s.tickerCustomX
        Config.options.media.tickerCustomY = s.tickerCustomY
        Config.options.notifications.position = s.notifPosition
        Config.options.notifications.monitorMode = s.notifMonitorMode
        Config.options.notifications.monitorName = s.notifMonitorName
        Config.options.notifications.customX = s.notifCustomX
        Config.options.notifications.customY = s.notifCustomY
        Config.options.osd.position = s.osdPosition
        Config.options.osd.monitorMode = s.osdMonitorMode
        Config.options.osd.monitorName = s.osdMonitorName
        Config.options.osd.customX = s.osdCustomX
        Config.options.osd.customY = s.osdCustomY
    }

    function save() {
        GlobalStates.popupEditorOpen = false
    }

    function cancel() {
        overlayRoot.restoreSnapshot(overlayRoot.snapshot)
        GlobalStates.popupEditorOpen = false
    }

    Connections {
        target: GlobalStates
        function onPopupEditorOpenChanged() {
            if (GlobalStates.popupEditorOpen) {
                overlayRoot.snapshot = overlayRoot.captureSnapshot()
            }
        }
    }

    Process {
        id: cursorPosProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",")
                if (parts.length < 2) return
                const x = parseFloat(parts[0])
                const y = parseFloat(parts[1])
                if (Number.isNaN(x) || Number.isNaN(y)) return
                overlayRoot.cursorGlobalX = x
                overlayRoot.cursorGlobalY = y
            }
        }
    }

    // Runs continuously for the whole editing session, not just while
    // actively dragging - PopupEditorWindow.qml's realHandleHere() uses
    // currentTargetScreen (not Hyprland.focusedMonitor) to decide which
    // monitor gets a "follow active monitor" item's real, draggable icon
    // right now, since Hyprland.focusedMonitor only updates on an actual
    // Hyprland focus-change event and can sit stale on whichever monitor
    // was focused before the editor even opened until one happens to fire.
    Timer {
        interval: 40
        repeat: true
        triggeredOnStart: true
        running: GlobalStates.popupEditorOpen
        onTriggered: if (!cursorPosProc.running) cursorPosProc.running = true
    }

    Variants {
        model: GlobalStates.popupEditorOpen ? Quickshell.screens : []

        Scope {
            id: monitorScope
            required property var modelData
            PopupEditorWindow { screen: monitorScope.modelData; overlay: overlayRoot }
        }
    }
}
