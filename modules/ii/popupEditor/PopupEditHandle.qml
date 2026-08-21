import qs.services
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Draggable grab handle for one item (ticker/notifications/OSD) in the live
// on-screen editor. Only ever instantiated as the ONE real, interactive
// instance for a given item - PopupEditorWindow.qml decides which monitor
// that is (the item's pinned monitor if "specific", or whichever monitor is
// currently focused if "follow active monitor" - see its class comment) and
// renders a plain, non-interactive PopupPositionIndicator everywhere else.
//
// Drag behavior differs by mode:
// - "specific" (crossMonitorCapable): position while dragging is driven by
//   the shared overlay's polled global cursor position (see
//   PopupEditorOverlay.qml), which is what lets it continue smoothly across
//   a monitor boundary - once the global position is on a different
//   monitor, this handle's own x/y (in its own window's local space) simply
//   goes out of that window's bounds and stops rendering there, while
//   PopupEditorWindow.qml renders a matching ghost in whichever window IS
//   current.
// - "focused" (follow active monitor): there's only ever one instance, so
//   there's nowhere to drag "across" to - uses plain native MouseArea.drag
//   clamped to this monitor's own bounds instead, no polling involved.
Item {
    id: root
    required property string itemId
    required property string label
    required property string iconName
    required property color accentColor
    required property var screen
    required property var overlay
    required property string monitorMode
    property bool supportsBar: true
    property string position: "bar"
    property real customX: 0.5
    property real customY: 0.5
    // Only meaningful when position is "custom" - see
    // Config.qml's media.tickerCustomAnchor doc comment.
    property string customAnchor: "top"
    // Horizontal offset applied when 2+ items land at/near the same spot,
    // so they line up in a row within a shared pill instead of overlapping -
    // see PopupEditorWindow.qml's clusterInfoFor()/pill rendering.
    property real rowOffsetX: 0
    // The idle (non-dragging) center this handle renders at, in real screen
    // pixels - PopupEditorWindow.qml's clusterInfoFor(), which for a solo
    // item is just that item's own real center, but for a clustered item is
    // the WHOLE cluster's shared reference point (its first member's real
    // center) - see that function's doc comment for why sharing one point
    // instead of each item's own (slightly different, even for "the same"
    // preset) real center matters: without it, a clustered icon would still
    // render at its own true Y while the pill is only ever one row tall,
    // leaking above/below it.
    required property real anchorCenterX
    required property real anchorCenterY
    // True while THIS item's cluster (not necessarily this exact item) is
    // being moved as a group by dragging the shared pill rather than an
    // individual icon - see PopupEditorWindow.qml's ClusterPill. Distinct
    // from isDragging (which means THIS handle's own MouseArea is the one
    // being dragged): needed so a follower icon being pulled along by the
    // pill still snaps to anchorCenterX/Y instantly instead of smoothly
    // chasing it 150ms behind, and renders above the pill instead of
    // underneath it.
    property bool pillGroupDragging: false

    // Fired when a local (non-cross-monitor) drag hits this monitor's own
    // edge, so PopupEditorWindow.qml can show a brief explanatory hint.
    signal boundaryHit()

    readonly property bool crossMonitorCapable: root.monitorMode === "specific"
    readonly property bool isDragging: root.crossMonitorCapable
        ? (root.overlay.dragging && root.overlay.draggingItemId === root.itemId)
        : root.localDragging
    property bool localDragging: false

    readonly property var footprint: PopupPlacement.footprintFor(root.itemId)
    readonly property var realRect: PopupPlacement.realRectFor(root.itemId, root.position, root.customX, root.customY, root.screen.width, root.screen.height, root.customAnchor, root.usable)
    readonly property real idleX: root.anchorCenterX - width / 2 + root.rowOffsetX
    readonly property real idleY: root.anchorCenterY - height / 2

    // This monitor's bar-free area (see PopupPlacement.barInfoFor) - per
    // monitor, since bar side/orientation/presence can differ between them.
    readonly property var usable: PopupPlacement.usableRectFor(root.screen)

    // The icon's center always represents the real footprint's center (see
    // idleX/idleY above), so clamping the icon to these bounds - instead of
    // the icon's own tiny width/height - keeps the actual, much bigger real
    // item from ever being dragged off this monitor's edge, or onto its bar.
    readonly property real dragMinX: Math.max(0, root.usable.x + root.footprint.width / 2 - width / 2)
    readonly property real dragMaxX: root.usable.x + root.usable.width - root.footprint.width / 2 - width / 2
    readonly property real dragMinY: Math.max(0, root.usable.y + root.footprint.height / 2 - height / 2)
    readonly property real dragMaxY: root.usable.y + root.usable.height - root.footprint.height / 2 - height / 2

    readonly property real draggingX: Math.max(root.dragMinX, Math.min(root.dragMaxX, root.overlay.cursorGlobalX - root.screen.x - width / 2))
    readonly property real draggingY: Math.max(root.dragMinY, Math.min(root.dragMaxY, root.overlay.cursorGlobalY - root.screen.y - height / 2))

    // Same small-icon size as the read-only PopupPositionIndicator, for a
    // consistent look throughout the editor - the actual clickable area is
    // bigger (see the MouseArea below), just not visually.
    implicitWidth: 20
    implicitHeight: 20
    z: (root.isDragging || root.pillGroupDragging) ? 100 : 1

    function restoreBindings() {
        root.x = Qt.binding(() => root.crossMonitorCapable
            ? (root.isDragging ? root.draggingX : root.idleX)
            : root.idleX)
        root.y = Qt.binding(() => root.crossMonitorCapable
            ? (root.isDragging ? root.draggingY : root.idleY)
            : root.idleY)
    }
    Component.onCompleted: root.restoreBindings()

    Behavior on x { enabled: !root.isDragging && !root.pillGroupDragging; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !root.isDragging && !root.pillGroupDragging; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    activeFocusOnTab: true
    Keys.onPressed: event => {
        const step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
        if (event.key === Qt.Key_Left) { root.nudge(-step, 0); event.accepted = true }
        else if (event.key === Qt.Key_Right) { root.nudge(step, 0); event.accepted = true }
        else if (event.key === Qt.Key_Up) { root.nudge(0, -step); event.accepted = true }
        else if (event.key === Qt.Key_Down) { root.nudge(0, step); event.accepted = true }
    }

    // Publishes this handle's current drag position to the shared overlay
    // as a normalized "custom" fraction of this monitor, so PopupEditorWindow.qml's
    // read-only mirrors on OTHER monitors (for this same "follow active
    // monitor" item) can render at the live, still-in-progress position
    // instead of the stale, not-yet-committed Config value - see onPressed's
    // doc comment above.
    function publishLivePosition() {
        const cx = root.x + width / 2
        const cy = root.y + height / 2
        // Infers the anchor from the live position, exactly as the drop
        // itself will (PopupPlacement.resolveDrop) - so a mirror on another
        // monitor tracks the same edge the drag is actually going to commit,
        // including across the midline where the direction flips.
        const anchorMode = PopupPlacement.inferCustomAnchor(cy, root.screen.height)
        root.overlay.liveCustomX = PopupPlacement.clampNormalized((cx - root.footprint.width / 2) / root.screen.width, root.footprint.width / root.screen.width)
        root.overlay.liveCustomY = anchorMode === "bottom"
            ? PopupPlacement.clampNormalizedFromEnd((cy + root.footprint.height / 2) / root.screen.height, root.footprint.height / root.screen.height)
            : PopupPlacement.clampNormalized((cy - root.footprint.height / 2) / root.screen.height, root.footprint.height / root.screen.height)
    }

    function nudge(dxPx, dyPx) {
        // Nudging always lands in "custom" - a preset is a named point, not
        // a coordinate to nudge from - starting from the REAL current
        // top-left (whether that's a preset or already custom), so a nudge
        // from a preset moves relative to where it's actually rendering.
        //
        // Keeps whichever edge the item is ALREADY anchored to rather than
        // re-inferring from the nudged position: a 1px arrow-key step that
        // happened to cross the screen's midline would otherwise silently
        // flip the item's growth direction. Crossing over is a thing you do
        // by dragging, deliberately, not by nudging.
        const anchorMode = root.customAnchor === "bottom" ? "bottom" : "top"
        const newX = PopupPlacement.clampNormalized((root.realRect.x + dxPx) / root.screen.width, root.footprint.width / root.screen.width)
        const newY = anchorMode === "bottom"
            ? PopupPlacement.clampNormalizedFromEnd((root.realRect.y + root.footprint.height + dyPx) / root.screen.height, root.footprint.height / root.screen.height)
            : PopupPlacement.clampNormalized((root.realRect.y + dyPx) / root.screen.height, root.footprint.height / root.screen.height)
        root.overlay.commitPosition(root.itemId, root.screen.name, "custom", newX, newY, anchorMode)
    }

    Rectangle {
        // Selection ring - only visible once clicked (i.e. has keyboard
        // focus for arrow-key nudging).
        visible: root.activeFocus
        anchors.centerIn: parent
        width: parent.width + 8
        height: parent.height + 8
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.accentColor
        border.width: 2
        border.color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
        scale: root.isDragging ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.iconName
        iconSize: Appearance.font.pixelSize.small
        color: "white"
        fill: 1
    }

    StyledToolTip {
        extraVisibleCondition: false
        alternativeVisibleCondition: dragArea.containsMouse && !root.isDragging
        text: root.label
    }

    MouseArea {
        id: dragArea
        // Bigger than the visual icon (which stays small to match
        // PopupPositionIndicator's look) so it's still easy to grab.
        anchors.centerIn: parent
        width: parent.width + 16
        height: parent.height + 16
        hoverEnabled: true
        drag.target: root.crossMonitorCapable ? undefined : root
        drag.minimumX: root.dragMinX
        drag.maximumX: root.dragMaxX
        drag.minimumY: root.dragMinY
        drag.maximumY: root.dragMaxY
        cursorShape: root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: {
            root.forceActiveFocus()
            if (root.crossMonitorCapable) {
                root.overlay.startDrag(root.itemId, root.label, root.iconName, root.accentColor, root.supportsBar, root.screen.name)
            } else {
                // Deliberately NOT overlay.startDrag() - that also flips on
                // overlay.dragging, which enables the cross-monitor-only
                // fallback catcher and ghost on EVERY window (see
                // PopupEditorWindow.qml's showGhost and the full-screen
                // MouseArea near the bottom of that file). A local drag's
                // pointer can still drift past this monitor's edge even
                // though the icon itself stays clamped on-screen, handing
                // the Wayland grab to the ADJACENT monitor's window - if
                // that window's fallback catcher were enabled, its release
                // would commit a position computed against the WRONG
                // screen from a stale polled cursor value instead of this
                // handle's own precise native-drag position, which is
                // exactly what caused items to "fly to the other side" with
                // a bogus boundary-hint alongside it. localDraggingItemId
                // is a separate, narrower signal that only affects cluster
                // exclusion and the live cross-monitor preview mirror
                // below - never the cross-monitor drag machinery.
                //
                // Order matters here: localDraggingItemId is set FIRST,
                // before localDragging. Setting localDragging first would
                // disable the x/y Behavior (isDragging depends on it)
                // before clusterInfoFor() has a chance to react to this
                // item now excluding itself from its cluster - so the
                // resulting position change (from the cluster's shared
                // point to this item's own) would apply with the Behavior
                // already off, snapping instantly instead of sliding, which
                // read as an unwanted jump the moment you merely pressed
                // the icon, before dragging it anywhere.
                root.overlay.localDraggingItemId = root.itemId
                root.localDragging = true
                root.publishLivePosition()
            }
        }

        onPositionChanged: {
            if (root.crossMonitorCapable || !root.localDragging) return
            root.publishLivePosition()
            if (root.x <= 0 || root.x >= root.screen.width - root.width || root.y <= 0 || root.y >= root.screen.height - root.height) {
                root.boundaryHit()
            }
        }

        onReleased: {
            if (root.crossMonitorCapable) {
                // Shared with the redundant per-window fallback catcher
                // (see PopupEditorOverlay.qml's finishDragFallback()) so
                // whichever one actually receives the release - this
                // handle's own, or a fallback elsewhere - the result is the
                // same, and the overlay.dragging guard there makes it safe
                // if both somehow fire.
                root.overlay.finishDragFallback()
            } else {
                const result = PopupPlacement.resolveDrop(root.itemId, root.supportsBar, root.x + root.width / 2, root.y + root.height / 2, root.screen, root.customAnchor)
                root.overlay.commitPosition(root.itemId, root.screen.name, result.position,
                    result.customX ?? root.customX, result.customY ?? root.customY, result.customAnchor)
                root.localDragging = false
                root.overlay.localDraggingItemId = ""
            }
            root.restoreBindings()
        }
    }
}
