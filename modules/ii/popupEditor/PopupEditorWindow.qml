pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.monitorPreview
import qs.services

// One monitor's live, real-scale editing surface. Every item (ticker,
// notifications, OSD) is always just a small icon here - the same
// PopupEditHandle/PopupPositionIndicator visual everywhere, on every
// monitor - never the real widget content. Positioning-only, on purpose:
// rendering actual widget content (a live Player, a real NotificationGroup)
// here made co-located items' shared pill background overflow around their
// much bigger real footprints, and it isn't needed to place things
// precisely anyway. To see exactly what will really render, use the
// "Preview" button in Settings, which triggers the real production paths
// (see InterfaceConfig.qml's previewAll(), in the Popup positions section).
//
// Only ONE monitor ever gets the real, interactive (draggable) handle for a
// given item at a time: for a "specific"-pinned item, that's its pinned
// monitor (dragging it onto another triggers the cross-monitor flow, see
// PopupEditHandle.qml); for a "follow active monitor" item, that's
// whichever monitor the cursor is actually on right now (see
// realHandleHere() below for why that's tracked via polling rather than
// Hyprland.focusedMonitor) - there's nothing to drag "across" to for that
// mode (dragging always stays local, clamped to
// this one monitor - see PopupEditHandle.qml's crossMonitorCapable). Every
// OTHER monitor still shows a small non-interactive PopupPositionIndicator
// for a "follow active monitor" item, so you can see where it'd sit if you
// were focused there, without it being draggable from here.
PanelWindow {
    id: window
    required property var overlay
    color: "transparent"
    WlrLayershell.namespace: "quickshell:popupEditor"
    WlrLayershell.layer: WlrLayer.Overlay
    // Only the monitor the cursor is actually on right now gets exclusive
    // keyboard focus - multiple simultaneous layer surfaces all claiming
    // Exclusive would fight each other (same reasoning as RegionSelector's
    // per-monitor keyboardFocusAllowed). Uses the overlay's polled cursor
    // position rather than Hyprland.focusedMonitor for the same staleness
    // reason as realHandleHere() above.
    WlrLayershell.keyboardFocus: window.overlay.currentTargetScreen?.name === window.screen?.name ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }

    readonly property real gridSize: 20

    // State for dragging a whole cluster pill (all its member icons) at
    // once - separate from the overlay's per-item dragging state, since a
    // pill drag moves several items together rather than one. Local to this
    // monitor only, same as an individual "follow active monitor" item's
    // drag - a pill only ever forms among items that are already "here" on
    // the SAME monitor, so there's nowhere to drag it "across" to.
    property bool pillDragging: false
    property string pillDragLeaderId: ""
    property real pillDragCenterX: 0
    property real pillDragCenterY: 0

    // The center a handle/indicator for itemId should actually render at:
    // the live pill-drag position while itemId's cluster is being dragged
    // as a group, otherwise its normal settled (or, for the actively-
    // dragged item itself, live-published individual-drag) position.
    function anchorCenterFor(itemId) {
        const info = window.clusterInfoFor(itemId)
        if (window.pillDragging && info.members.includes(window.pillDragLeaderId)) {
            return { x: window.pillDragCenterX, y: window.pillDragCenterY }
        }
        return { x: info.centerX, y: info.centerY }
    }

    // Whether itemId's own cluster is currently being moved as a group via
    // its shared pill - see PopupEditHandle.qml's pillGroupDragging doc
    // comment for why the handle itself needs to know this.
    function isPillGroupDragging(itemId) {
        return window.pillDragging && window.clusterInfoFor(itemId).members.includes(window.pillDragLeaderId)
    }

    function rectsOverlap(a, b) {
        return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }

    // Rough occupied-space rectangles for every icon and pill currently
    // showing on this monitor (real handles, read-only preview mirrors, and
    // cluster pills alike) - used only to keep the Save/Cancel controls
    // below out of their way, so a generous fixed size per icon is fine;
    // this doesn't need to be pixel-exact.
    function itemOccupiedRects() {
        const rects = []
        const consider = (itemId, realHere, previewHere) => {
            if (realHere) {
                const c = window.anchorCenterFor(itemId)
                rects.push({ x: c.x - 24, y: c.y - 24, width: 48, height: 48 })
            } else if (previewHere) {
                const c = window.previewCenterFor(itemId)
                rects.push({ x: c.x - 24, y: c.y - 24, width: 48, height: 48 })
            }
        }
        consider("ticker", window.tickerRealHere, window.tickerPreviewHere)
        consider("notifications", window.notificationsRealHere, window.notificationsPreviewHere)
        consider("osd", window.osdRealHere, window.osdPreviewHere)
        for (const id of ["ticker", "notifications", "osd"]) {
            if (!window.isClusterLeader(id)) continue
            const info = window.clusterInfoFor(id)
            const w = info.members.length * window.iconSpacing + 8
            rects.push({ x: info.centerX - w / 2, y: info.centerY - 14, width: w, height: 28 })
        }
        return rects
    }

    // Where the Save/Cancel controls should sit: top-center by default,
    // hopping to bottom-center instead whenever something dragged there
    // would otherwise sit underneath or overlapping them - so there's
    // always a clear, reachable spot to drop an item near the top of the
    // screen instead of the controls permanently claiming it.
    readonly property var buttonZoneCandidates: [
        { x: window.width / 2 - 70, y: 24, width: 140, height: 56 },
        { x: window.width / 2 - 70, y: window.height - 24 - 56, width: 140, height: 56 },
    ]
    readonly property var buttonsZone: {
        const occupied = window.itemOccupiedRects()
        for (const candidate of window.buttonZoneCandidates) {
            if (!occupied.some(r => window.rectsOverlap(r, candidate))) return candidate
        }
        return window.buttonZoneCandidates[window.buttonZoneCandidates.length - 1]
    }

    Rectangle {
        // Also the actual Escape-to-cancel handler - PanelWindow itself
        // can't take Keys (it isn't an Item), and a plain Item never gets
        // real key events without explicitly claiming focus - same fix
        // RegionSelection.qml uses for its own Esc handling.
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: window.overlay.cancel()
        color: "black"
        opacity: 0.35
    }

    Repeater {
        model: Math.ceil(window.width / window.gridSize)
        delegate: Rectangle {
            required property int index
            x: index * window.gridSize
            width: 1
            height: window.height
            color: Qt.rgba(1, 1, 1, 0.08)
        }
    }
    Repeater {
        model: Math.ceil(window.height / window.gridSize)
        delegate: Rectangle {
            required property int index
            y: index * window.gridSize
            width: window.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }
    }

    // THIS monitor's bar, resolved through its own per-monitor settings
    // (PopupPlacement.barInfoFor) rather than the global ones - side,
    // orientation and even whether a bar exists here at all can differ from
    // the next monitor's, so drawing the global bar on every screen would be
    // a lie on any monitor that overrides them.
    readonly property var barInfo: PopupPlacement.barInfoFor(window.screen)

    Rectangle {
        // Marks the strip the bar reserves, which is also exactly the strip
        // items can no longer be dragged or dropped into - the drag bounds
        // and the drop clamp both come from the same barInfoFor() call, so
        // what is drawn here and what is enforced cannot disagree.
        visible: window.barInfo.present
        x: window.barInfo.rect.x
        y: window.barInfo.rect.y
        width: window.barInfo.rect.width
        height: window.barInfo.rect.height
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.28)

        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("Bar")
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: Appearance.font.pixelSize.smaller
            rotation: window.barInfo.vertical ? -90 : 0
        }
    }

    // The one true monitor for this item right now, regardless of mode. A
    // pinned "specific" monitor always wins outright. Otherwise - both for
    // "follow active monitor" items, and as a fallback if a "specific"
    // item's pinned monitor is no longer valid - this uses the overlay's
    // continuously-polled real cursor position (overlay.currentTargetScreen)
    // rather than PopupPlacement.resolveScreen()'s usual Hyprland.focusedMonitor:
    // that property only updates on an actual Hyprland focus-change event,
    // so it can sit stale on whichever monitor was focused before the
    // editor even opened until one happens to fire - polling instead keeps
    // this always in sync with wherever the user is actually looking right
    // now. Real production components (the actual ticker/OSD/notifications)
    // are unaffected - they still resolve via Hyprland.focusedMonitor, as
    // always; this only changes which monitor the EDITOR treats as "here".
    function realHandleHere(monitorMode, monitorName) {
        if (monitorMode === "specific") {
            const specific = PopupPlacement.screenByName(monitorName)
            if (specific) return specific.name === window.screen?.name
        }
        return window.overlay.currentTargetScreen?.name === window.screen?.name
    }
    // "Follow active monitor" items get a passive preview on every OTHER
    // monitor too - "specific" items don't (they're not here at all until
    // dragged here, at which point the ghost below takes over instead).
    function readOnlyPreviewHere(monitorMode, monitorName) {
        return monitorMode !== "specific" && !window.realHandleHere(monitorMode, monitorName)
    }

    readonly property bool tickerRealHere: window.realHandleHere(Config.options.media.tickerMonitorMode, Config.options.media.tickerMonitorName)
    readonly property bool notificationsRealHere: window.realHandleHere(Config.options.notifications.monitorMode, Config.options.notifications.monitorName)
    readonly property bool osdRealHere: window.realHandleHere(Config.options.osd.monitorMode, Config.options.osd.monitorName)

    readonly property bool tickerPreviewHere: window.readOnlyPreviewHere(Config.options.media.tickerMonitorMode, Config.options.media.tickerMonitorName)
    readonly property bool notificationsPreviewHere: window.readOnlyPreviewHere(Config.options.notifications.monitorMode, Config.options.notifications.monitorName)
    readonly property bool osdPreviewHere: window.readOnlyPreviewHere(Config.options.osd.monitorMode, Config.options.osd.monitorName)

    readonly property bool tickerDragging: (window.overlay.dragging && window.overlay.draggingItemId === "ticker") || window.overlay.localDraggingItemId === "ticker"
    readonly property bool notificationsDragging: (window.overlay.dragging && window.overlay.draggingItemId === "notifications") || window.overlay.localDraggingItemId === "notifications"
    readonly property bool osdDragging: (window.overlay.dragging && window.overlay.draggingItemId === "osd") || window.overlay.localDraggingItemId === "osd"

    // A ghost is only needed for a "specific"-mode item being dragged onto a
    // monitor it doesn't already belong to - "follow active monitor" items
    // never migrate monitors via drag at all (see class comment), so they
    // never need one.
    readonly property bool showGhost: window.overlay.dragging
        && window.overlay.draggingItemId !== ""
        && window.overlay.currentTargetScreen?.name === window.screen?.name
        && !window.tickerRealHere && !window.notificationsRealHere && !window.osdRealHere

    // Which items (real handle, ghost, or read-only preview alike) share
    // this monitor with itemId at/near the same point right now, so they
    // can line up in a row within a shared pill instead of overlapping -
    // see the pill Rectangles below. Excludes whatever's currently being
    // cross-monitor dragged, since its position isn't the settled one right
    // now anyway (this is also what makes a pill automatically dissolve
    // back into a single icon the moment one of its members starts moving).
    function clusterInfoFor(itemId) {
        // Every item "here" gets its own real (fx, fy) computed up front,
        // REGARDLESS of whether it's currently dragging - dragging only
        // controls whether it's eligible to join a CLUSTER below, not
        // whether it has a valid position at all. Conflating the two used
        // to make a dragging item's own fallback (when it excludes itself
        // from clustering) collapse to (0, 0) instead of its real position -
        // since that fallback feeds directly into the icon's on-screen x/y,
        // the icon would visibly snap to the screen's top-left corner the
        // instant a "follow active monitor" drag started (before the drag
        // threshold even engaged), which only ever affected follow-mode
        // items since only local drags hit this exclusion path.
        const all = []
        const add = (id, mode, name, position, cx, cy, anchorMode, isDragging) => {
            const here = window.realHandleHere(mode, name) || window.readOnlyPreviewHere(mode, name)
            if (!here) return
            const rect = PopupPlacement.realRectFor(id, position, cx, cy, window.screen.width, window.screen.height, anchorMode, window.barInfo.usable)
            const footprint = PopupPlacement.footprintFor(id)
            const fx = (rect.x + footprint.width / 2) / window.screen.width
            // The footprint CENTRE fraction, for every item, custom or preset
            // alike - both for deciding what clusters and for where the icon
            // is actually drawn. One quantity, because an icon means one
            // thing: "the middle of this item is here".
            //
            // This used to draw "custom" items at their stored ANCHOR EDGE
            // instead, which put the icon half a footprint away from the item
            // it points at, and worse, made dropping one shift it every
            // single time: resolveDrop() reads the icon's centre and stores
            // centre - height/2, so re-rendering that stored edge AS a centre
            // moved the icon up by half a footprint (~50px) on release, and
            // dragging it back to where you wanted it moved it up again on
            // the next drop. Centre in, centre out - the conversion belongs
            // in resolveDrop() alone, and applying it a second time here was
            // simply doing it twice.
            //
            // Centre-based is also what makes clustering work: two items
            // dropped on the same point share a centre regardless of how big
            // each one is, but they do NOT share a top edge.
            const fy = (rect.y + footprint.height / 2) / window.screen.height
            all.push({ id, isDragging, fx, fy })
        }
        add("ticker", Config.options.media.tickerMonitorMode, Config.options.media.tickerMonitorName, Config.options.media.tickerPosition, Config.options.media.tickerCustomX, Config.options.media.tickerCustomY, Config.options.media.tickerCustomAnchor, window.tickerDragging)
        add("notifications", Config.options.notifications.monitorMode, Config.options.notifications.monitorName, Config.options.notifications.position, Config.options.notifications.customX, Config.options.notifications.customY, Config.options.notifications.customAnchor, window.notificationsDragging)
        add("osd", Config.options.osd.monitorMode, Config.options.osd.monitorName, Config.options.osd.position, Config.options.osd.customX, Config.options.osd.customY, Config.options.osd.customAnchor, window.osdDragging)

        const mine = all.find(c => c.id === itemId)
        if (!mine) return { members: [itemId], index: 0, centerX: 0, centerY: 0 }
        // Candidates for CLUSTER MEMBERSHIP exclude anything else currently
        // dragging (so a pill correctly dissolves the instant a DIFFERENT
        // member starts moving), but always include "mine" itself even
        // while IT'S the one dragging - using its stable, pre-drag Config
        // position, unaffected by the drag in progress. Excluding "mine"
        // here (the old approach) meant the instant you clicked something
        // that was part of a cluster, its query would revert from the
        // cluster's shared point to its own, visibly moving the icon on
        // PRESS, before you'd even moved the mouse.
        const candidates = all.filter(c => !c.isDragging || c.id === itemId)
        const members = candidates.filter(c => Math.hypot(c.fx - mine.fx, c.fy - mine.fy) < 0.06).map(c => c.id)
        // Every member of a cluster shares ONE reference point - the first
        // member's own real position (in canonical ticker/notifications/osd
        // order, same as isClusterLeader()) - rather than each item's own,
        // slightly different real center. Even "the same" preset resolves
        // to a few px difference per item, since corner/edge anchoring
        // depends on each item's own footprint size - without sharing one
        // reference, individual icons would still render at their own true
        // Y while the pill is only ever one row tall, leaking above/below
        // it.
        const leader = candidates.find(c => c.id === members[0])
        // Solo or clustered, the point is the same kind of quantity - a
        // footprint centre - so dragging a pill (which tracks the cursor as a
        // centre throughout) and dropping it commits and re-renders to
        // exactly where it was let go, with nothing to jump.
        return {
            members,
            index: members.indexOf(itemId),
            centerX: leader.fx * window.screen.width,
            centerY: leader.fy * window.screen.height,
        }
    }

    // Must exceed each icon's own clickable hit area (20px visual + 16px
    // padding = 36px, see PopupEditHandle.qml's dragArea) - otherwise
    // adjacent icons in the same pill have overlapping hit areas, and a
    // click near the boundary between two icons can grab the wrong one.
    readonly property real iconSpacing: 40

    function rowOffsetXFor(itemId) {
        const info = window.clusterInfoFor(itemId)
        return (info.index - (info.members.length - 1) / 2) * window.iconSpacing
    }

    // Only the first member of a multi-item cluster renders the shared pill
    // background behind the row of icons - see the pill Rectangles below.
    function isClusterLeader(itemId) {
        const info = window.clusterInfoFor(itemId)
        return info.members.length > 1 && info.members[0] === itemId
    }

    // Where a read-only preview mirror (on a monitor OTHER than wherever
    // itemId is actually real right now) should render. While itemId is
    // being actively (locally) dragged, this tracks the overlay's live
    // published fraction in real time instead of clusterInfoFor()'s
    // Config-based value, which only updates once the drag commits - see
    // PopupEditHandle.qml's publishLivePosition().
    function previewCenterFor(itemId) {
        if (window.overlay.localDraggingItemId === itemId) {
            // liveCustomY is already the exact anchored edge (see
            // PopupEditHandle.qml's publishLivePosition(), which computes
            // it the same anchor-aware way clusterInfoFor() does above) -
            // used directly here for the same reason: no footprint math to
            // approximate away.
            const footprint = PopupPlacement.footprintFor(itemId)
            const rect = PopupPlacement.realRectFor(itemId, "custom", window.overlay.liveCustomX, window.overlay.liveCustomY, window.screen.width, window.screen.height, window.overlay.customAnchorFor(itemId))
            return { x: rect.x + footprint.width / 2, y: window.overlay.liveCustomY * window.screen.height }
        }
        const info = window.clusterInfoFor(itemId)
        return { x: info.centerX, y: info.centerY }
    }

    // Shared pill background for a multi-item cluster - one per possible
    // leader (at most one of these three is ever actually visible, since
    // there are only 3 items total and a cluster needs one leader). Sits
    // behind the row of icons (z below their default), and - because
    // clusterInfoFor() excludes whatever's currently being dragged -
    // automatically shrinks/disappears the instant one of its members
    // starts moving, without any extra bookkeeping. Also draggable itself -
    // grabbing the pill body (rather than one of its member icons) moves
    // every member together, still grouped, to a new shared spot.
    component ClusterPill: Rectangle {
        id: pill
        required property string itemId
        readonly property var info: window.clusterInfoFor(itemId)
        readonly property bool isDraggingThis: window.pillDragging && window.pillDragLeaderId === itemId
        // Clamped to the LARGEST member's real footprint, not the pill's
        // own small size, so dragging the group can't push any member's
        // actual real content off this monitor's edge - same reasoning as
        // PopupEditHandle.qml's own dragMinX/dragMaxX.
        readonly property real maxFootprintHalfW: pill.info.members.length > 0
            ? Math.max(...pill.info.members.map(id => PopupPlacement.footprintFor(id).width / 2)) : 0
        readonly property real maxFootprintHalfH: pill.info.members.length > 0
            ? Math.max(...pill.info.members.map(id => PopupPlacement.footprintFor(id).height / 2)) : 0
        readonly property real dragMinX: Math.max(0, pill.maxFootprintHalfW - width / 2)
        readonly property real dragMaxX: window.screen.width - pill.maxFootprintHalfW - width / 2
        readonly property real dragMinY: Math.max(0, pill.maxFootprintHalfH - height / 2)
        readonly property real dragMaxY: window.screen.height - pill.maxFootprintHalfH - height / 2

        visible: window.isClusterLeader(itemId) || pill.isDraggingThis
        radius: height / 2
        color: MonitorThemes.shellColorForItem(parent, "colLayer0", Appearance.colors.colLayer0)
        border.width: pill.isDraggingThis ? 2 : 1
        border.color: pill.isDraggingThis ? MonitorThemes.shellColorForItem(parent, "colPrimary", Appearance.colors.colPrimary) : MonitorThemes.shellColorForItem(parent, "colOutlineVariant", Appearance.colors.colOutlineVariant)
        width: info.members.length * window.iconSpacing + 8
        height: 28
        z: pill.isDraggingThis ? 50 : 0
        scale: pill.isDraggingThis ? 1.05 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }

        function restoreBinding() {
            pill.x = Qt.binding(() => pill.info.centerX - pill.width / 2)
            pill.y = Qt.binding(() => pill.info.centerY - pill.height / 2)
        }
        Component.onCompleted: pill.restoreBinding()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pill.isDraggingThis ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: pill
            drag.minimumX: pill.dragMinX
            drag.maximumX: pill.dragMaxX
            drag.minimumY: pill.dragMinY
            drag.maximumY: pill.dragMaxY

            onPressed: {
                // Order matters: the live center is set FIRST, before
                // pillDragging/pillDragLeaderId flip on. anchorCenterFor()
                // switches to reading pillDragCenterX/Y the instant
                // pillDragging && members.includes(pillDragLeaderId) is
                // true - if those two flipped on first, every member would
                // briefly read whatever pillDragCenterX/Y was left over
                // from the LAST pill drag (or 0 on the very first ever),
                // not this press's actual position, visibly snapping there
                // before the correct value landed a statement later.
                window.pillDragCenterX = pill.info.centerX
                window.pillDragCenterY = pill.info.centerY
                window.pillDragging = true
                window.pillDragLeaderId = pill.itemId
            }
            onPositionChanged: {
                if (!pill.isDraggingThis) return
                window.pillDragCenterX = pill.x + pill.width / 2
                window.pillDragCenterY = pill.y + pill.height / 2
            }
            onReleased: {
                // Deliberately NOT PopupPlacement.resolveDrop() here, unlike
                // a single-icon drag - that resolves each item's OWN drop
                // point against ITS OWN preset hotzones using ITS OWN
                // footprint size, so with several different-sized members
                // sharing the SAME pill-center drop point, one could land
                // inside a preset's hotzone while another just misses it -
                // some members ending up on a named preset and others on
                // "custom" is exactly what made the group "fall apart"
                // instead of landing together where it was dropped. A group
                // drag always lands every member in "custom" instead,
                // computed directly from the SAME shared drop point - see
                // below for the per-axis rules.
                const dropX = pill.x + pill.width / 2
                const dropY = pill.y + pill.height / 2
                // The two axes deliberately use different rules, because the
                // two axes answer different questions.
                //
                // HORIZONTALLY every member converts the shared drop point
                // through its OWN half-width, so they end up sharing a
                // centre - narrower items sit centred inside wider ones,
                // which is what a *_center preset does too.
                //
                // VERTICALLY they share an anchor EDGE instead, derived once
                // from the biggest member (groupHalfH) rather than each from
                // its own size. Sharing a centre here looked tidier but broke
                // the thing anchors exist for: the anchored edge is the one
                // that stays put while an item grows, and notifications grow.
                // Pinning a centre-aligned group means each new notification
                // pushes the whole popup upward; pinning the top edge means
                // the stack grows downward from where it was dropped, exactly
                // as a top_* preset behaves. Same rule everywhere now -
                // top anchors align tops, bottom anchors align bottoms,
                // centre anchors align centres.
                const groupHalfH = pill.maxFootprintHalfH
                // Inferred ONCE for the whole group, from the shared drop
                // point, so every member grows the same way - inferring per
                // member would be identical anyway (they share dropY), but
                // deriving it once makes "the group is one thing" explicit.
                const anchorMode = PopupPlacement.inferCustomAnchor(dropY, window.screen.height)
                for (const memberId of pill.info.members) {
                    const footprint = PopupPlacement.footprintFor(memberId)
                    const newX = PopupPlacement.clampNormalized((dropX - footprint.width / 2) / window.screen.width, footprint.width / window.screen.width)
                    const newY = anchorMode === "bottom"
                        ? PopupPlacement.clampNormalizedFromEnd((dropY + groupHalfH) / window.screen.height, footprint.height / window.screen.height)
                        : PopupPlacement.clampNormalized((dropY - groupHalfH) / window.screen.height, footprint.height / window.screen.height)
                    window.overlay.commitPosition(memberId, window.screen.name, "custom", newX, newY, anchorMode)
                }
                window.pillDragging = false
                window.pillDragLeaderId = ""
                pill.restoreBinding()
            }

            StyledToolTip {
                extraVisibleCondition: false
                alternativeVisibleCondition: parent.containsMouse && !pill.isDraggingThis
                text: Translation.tr("Drag to move the whole group")
            }
        }
    }
    ClusterPill { itemId: "ticker" }
    ClusterPill { itemId: "notifications" }
    ClusterPill { itemId: "osd" }

    // Media ticker
    PopupEditHandle {
        id: tickerHandle
        visible: window.tickerRealHere
        itemId: "ticker"
        label: Translation.tr("Media ticker")
        iconName: "music_note"
        accentColor: MonitorThemes.shellColorForItem(parent, "colPrimary", Appearance.colors.colPrimary)
        screen: window.screen
        overlay: window.overlay
        monitorMode: Config.options.media.tickerMonitorMode
        supportsBar: true
        position: Config.options.media.tickerPosition
        customX: Config.options.media.tickerCustomX
        customY: Config.options.media.tickerCustomY
        customAnchor: Config.options.media.tickerCustomAnchor
        anchorCenterX: window.anchorCenterFor("ticker").x
        anchorCenterY: window.anchorCenterFor("ticker").y
        pillGroupDragging: window.isPillGroupDragging("ticker")
        rowOffsetX: window.rowOffsetXFor("ticker")
        onBoundaryHit: window.overlay.showBoundaryHint(window.screen.name)
    }

    PopupPositionIndicator {
        visible: window.tickerPreviewHere
        label: Translation.tr("Media ticker")
        iconName: "music_note"
        accentColor: MonitorThemes.shellColorForItem(parent, "colPrimary", Appearance.colors.colPrimary)
        readonly property var center: window.previewCenterFor("ticker")
        centerX: center.x
        centerY: center.y
        rowOffsetX: window.rowOffsetXFor("ticker")
    }

    // Notifications
    PopupEditHandle {
        id: notificationsHandle
        visible: window.notificationsRealHere
        itemId: "notifications"
        label: Translation.tr("Notifications")
        iconName: "notifications"
        accentColor: MonitorThemes.shellColorForItem(parent, "colTertiary", Appearance.colors.colTertiary)
        screen: window.screen
        overlay: window.overlay
        monitorMode: Config.options.notifications.monitorMode
        supportsBar: false
        position: Config.options.notifications.position
        customX: Config.options.notifications.customX
        customY: Config.options.notifications.customY
        customAnchor: Config.options.notifications.customAnchor
        anchorCenterX: window.anchorCenterFor("notifications").x
        anchorCenterY: window.anchorCenterFor("notifications").y
        pillGroupDragging: window.isPillGroupDragging("notifications")
        rowOffsetX: window.rowOffsetXFor("notifications")
        onBoundaryHit: window.overlay.showBoundaryHint(window.screen.name)
    }

    PopupPositionIndicator {
        visible: window.notificationsPreviewHere
        label: Translation.tr("Notifications")
        iconName: "notifications"
        accentColor: MonitorThemes.shellColorForItem(parent, "colTertiary", Appearance.colors.colTertiary)
        readonly property var center: window.previewCenterFor("notifications")
        centerX: center.x
        centerY: center.y
        rowOffsetX: window.rowOffsetXFor("notifications")
    }

    // On-screen display
    PopupEditHandle {
        id: osdHandle
        visible: window.osdRealHere
        itemId: "osd"
        label: Translation.tr("On-screen display")
        iconName: "tune"
        accentColor: MonitorThemes.shellColorForItem(parent, "colSecondary", Appearance.colors.colSecondary)
        screen: window.screen
        overlay: window.overlay
        monitorMode: Config.options.osd.monitorMode
        supportsBar: true
        position: Config.options.osd.position
        customX: Config.options.osd.customX
        customY: Config.options.osd.customY
        customAnchor: Config.options.osd.customAnchor
        anchorCenterX: window.anchorCenterFor("osd").x
        anchorCenterY: window.anchorCenterFor("osd").y
        pillGroupDragging: window.isPillGroupDragging("osd")
        rowOffsetX: window.rowOffsetXFor("osd")
        onBoundaryHit: window.overlay.showBoundaryHint(window.screen.name)
    }

    PopupPositionIndicator {
        visible: window.osdPreviewHere
        label: Translation.tr("On-screen display")
        iconName: "tune"
        accentColor: MonitorThemes.shellColorForItem(parent, "colSecondary", Appearance.colors.colSecondary)
        readonly property var center: window.previewCenterFor("osd")
        centerX: center.x
        centerY: center.y
        rowOffsetX: window.rowOffsetXFor("osd")
    }

    // Ghost handle for a "specific"-mode item being dragged in from a
    // different monitor - see showGhost's doc comment above. Same 20px icon
    // size as PopupEditHandle for a consistent look, and clamped to the
    // dragged item's real footprint (not just its own small icon bounds) so
    // it can't be dropped somewhere the real item would hang off this
    // monitor's edge.
    Rectangle {
        id: ghost
        visible: window.showGhost
        readonly property var ghostFootprint: PopupPlacement.footprintFor(window.overlay.draggingItemId)
        readonly property real minX: Math.max(0, ghost.ghostFootprint.width / 2 - ghost.width / 2)
        readonly property real maxX: (window.screen?.width ?? 0) - ghost.ghostFootprint.width / 2 - ghost.width / 2
        readonly property real minY: Math.max(0, ghost.ghostFootprint.height / 2 - ghost.height / 2)
        readonly property real maxY: (window.screen?.height ?? 0) - ghost.ghostFootprint.height / 2 - ghost.height / 2
        width: 20
        height: 20
        radius: width / 2
        color: window.overlay.draggingAccentColor
        border.width: 2
        border.color: MonitorThemes.shellColorForItem(parent, "colLayer0", Appearance.colors.colLayer0)
        x: Math.max(ghost.minX, Math.min(ghost.maxX, window.overlay.cursorGlobalX - (window.screen?.x ?? 0) - width / 2))
        y: Math.max(ghost.minY, Math.min(ghost.maxY, window.overlay.cursorGlobalY - (window.screen?.y ?? 0) - height / 2))
        z: 100

        MaterialSymbol {
            anchors.centerIn: parent
            text: window.overlay.draggingIconName
            iconSize: Appearance.font.pixelSize.small
            color: "white"
            fill: 1
        }
    }

    // Redundant release catcher for the cross-monitor drag - see
    // PopupEditorOverlay.qml's finishDragFallback() doc comment. Only
    // listens while a drag is actually in progress, and only for release
    // (not press), so it doesn't interfere with anything else.
    MouseArea {
        anchors.fill: parent
        enabled: window.overlay.dragging
        z: 99
        onReleased: window.overlay.finishDragFallback()
    }

    Rectangle {
        visible: window.overlay.boundaryHintScreenName === window.screen?.name
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 80
        radius: Appearance.rounding.normal
        color: MonitorThemes.shellColorForItem(parent, "colLayer0", Appearance.colors.colLayer0)
        implicitWidth: boundaryHintText.implicitWidth + 24
        implicitHeight: boundaryHintText.implicitHeight + 16
        z: 101

        StyledText {
            id: boundaryHintText
            anchors.centerIn: parent
            text: Translation.tr("Can't move to another monitor while \"Follow active monitor\" is on")
            color: MonitorThemes.shellColorForItem(parent, "colOnLayer0", Appearance.colors.colOnLayer0)
        }
    }

    // Same paired-FAB M3 styling RegionSelection.qml uses for its own
    // confirm/cancel controls when locking in a selection. Hops between
    // buttonsZone's candidate spots (see above) instead of sitting fixed at
    // the top, so it never permanently blocks part of the screen an item
    // needs to land on.
    Row {
        x: window.buttonsZone.x + window.buttonsZone.width / 2 - width / 2
        y: window.buttonsZone.y
        spacing: 8
        z: 102

        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        ToolbarPairedFab {
            iconText: "check"
            onClicked: window.overlay.save()
            StyledToolTip {
                text: Translation.tr("Save")
            }
        }
        ToolbarPairedFab {
            iconText: "close"
            onClicked: window.overlay.cancel()
            StyledToolTip {
                text: Translation.tr("Cancel")
            }
        }
    }
}
