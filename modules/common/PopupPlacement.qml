pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
import qs.services

// Shared monitor-resolution and position-preset helpers for OSD-style popups
// (media ticker, notifications, on-screen display) - see NotificationPopup.qml,
// which had the first version of resolveScreen() inline before this existed.
Singleton {
    id: root

    function screenByName(name) {
        if (!name || name.length === 0) return null
        return Quickshell.screens.find(s => s.name === name) ?? null
    }

    // mode: "specific" or anything else (including legacy "primary" values
    // from before this was simplified down to just two options) is treated
    // as "follow the focused monitor". "specific" tries monitorName first,
    // then falls through to focused too, so a stale/disconnected monitor
    // name doesn't strand the popup off-screen.
    function resolveScreen(mode, monitorName) {
        if (mode === "specific") {
            const specific = root.screenByName(monitorName)
            if (specific) return specific
        }
        const focused = root.screenByName(Hyprland.focusedMonitor?.name ?? "")
        if (focused) return focused
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    function availableMonitorNames() {
        return Quickshell.screens.map(s => s.name)
    }

    // Clamp a normalized (0-1) anchor so a footprint of the given normalized
    // size doesn't run off the far edge of whatever it's anchored within.
    function clampNormalized(norm, footprintNorm) {
        return Math.max(0, Math.min(norm, 1 - footprintNorm))
    }

    // Same, but for a normalized point representing the END (bottom/right)
    // of a footprint rather than its start (top/left) - keeps the footprint
    // from running off the NEAR edge instead of the far one.
    function clampNormalizedFromEnd(norm, footprintNorm) {
        return Math.max(footprintNorm, Math.min(1, norm))
    }

    // Which screen edge the bar hugs, and how thick it is - mirrors
    // MediaControls.qml's identically-named properties (the ticker's
    // original, horizontal-bar-first implementation of this), extracted here
    // so the OSD's new "bar" preset can reuse the exact same logic instead of
    // re-deriving a partial (horizontal-only) version.
    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
    readonly property real barGap: Config.options.bar.cornerStyle === 3 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property bool cornerStyleReducesGap: Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 2

    // PER-MONITOR bar geometry. The properties above (barVertical/barEdge/
    // barThickness) read the GLOBAL bar settings, which is wrong the moment a
    // monitor overrides any of them - and this config supports exactly that,
    // through Config.getBarSetting()/bar.monitorSettings, plus bar.screenList
    // deciding whether a monitor has a bar at all. Everything that needs to
    // know where the bar is - the preview, the live editor, and the clamp
    // that keeps popups off it - goes through here so one monitor's bar can
    // never be described using another's settings.
    //
    // "thickness" is the RESERVED strip (the bar's own exclusiveZone, mirrored
    // from Bar.qml/VerticalBar.qml), not the bar window's full height: the
    // window is taller by screenRounding, which is decoration that windows are
    // free to sit under. Auto-hide reserves nothing, exactly as those two
    // files do, so a popup may use the whole screen there - the same space a
    // preset-positioned popup already gets from the compositor.
    function barInfoFor(screen) {
        const empty = { present: false, vertical: false, edge: "top", thickness: 0,
            rect: { x: 0, y: 0, width: 0, height: 0 },
            usable: { x: 0, y: 0, width: screen?.width ?? 0, height: screen?.height ?? 0 } }
        if (!screen) return empty

        const name = screen.name
        const list = Config.options.bar.screenList ?? []
        if (list.length > 0 && !list.includes(name)) return empty

        // A normal fullscreen window buries the bar, so popups must use the
        // full monitor instead of reserving space for a bar the user cannot
        // see. Special workspaces keep the bar on the overlay layer.
        const monitor = HyprlandData.monitors.find(item => item.name === name)
        const workspace = HyprlandData.workspaceById[monitor?.activeWorkspace?.id]
        if (workspace?.hasfullscreen && !(monitor?.specialWorkspace?.name ?? "")) return empty

        const vertical = Config.getBarSetting(name, ["vertical"], Config.options.bar.vertical)
        const bottom = Config.getBarSetting(name, ["bottom"], Config.options.bar.bottom)
        const cornerStyle = Config.getBarSetting(name, ["cornerStyle"], Config.options.bar.cornerStyle)
        const autoHide = Config.getBarSetting(name, ["autoHide", "enable"], Config.options.bar.autoHide.enable)
        const pushWindows = Config.getBarSetting(name, ["autoHide", "pushWindows"], Config.options.bar.autoHide.pushWindows)

        let thickness = 0
        if (!(autoHide && !pushWindows)) {
            thickness = vertical
                ? Appearance.sizes.baseVerticalBarWidth
                    + (cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    + (cornerStyle === 3 ? (Config.options.hyprland.general.gapsOut || 5) : 0)
                : Appearance.sizes.baseBarHeight
                    + (cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    + (cornerStyle === 2 ? -6 : 0)
        }

        const edge = vertical ? (bottom ? "right" : "left") : (bottom ? "bottom" : "top")
        const w = screen.width
        const h = screen.height
        let rect, usable
        switch (edge) {
            case "top":
                rect = { x: 0, y: 0, width: w, height: thickness }
                usable = { x: 0, y: thickness, width: w, height: h - thickness }
                break
            case "bottom":
                rect = { x: 0, y: h - thickness, width: w, height: thickness }
                usable = { x: 0, y: 0, width: w, height: h - thickness }
                break
            case "left":
                rect = { x: 0, y: 0, width: thickness, height: h }
                usable = { x: thickness, y: 0, width: w - thickness, height: h }
                break
            default:
                rect = { x: w - thickness, y: 0, width: thickness, height: h }
                usable = { x: 0, y: 0, width: w - thickness, height: h }
                break
        }
        return { present: thickness > 0, vertical, edge, thickness, rect, usable }
    }

    // The area a popup may occupy on a monitor - the whole thing, minus
    // whatever strip its own bar reserves.
    function usableRectFor(screen) {
        return root.barInfoFor(screen).usable
    }

    readonly property var presetIds: ["top_left", "top_center", "top_right", "center_left", "center", "center_right", "bottom_left", "bottom_center", "bottom_right"]

    // Normalized (0-1) point within a monitor that a given preset id
    // corresponds to - only used as a cheap fallback (e.g. before a real
    // item size is known); prefer anchoredRect() below wherever an item's
    // real footprint is available, since this treats every preset as
    // flush against the literal screen edge with no margin at all, which
    // is NOT how any of the live popups actually render.
    function presetFraction(presetId) {
        if (presetId === "bar") {
            switch (root.barEdge) {
                case "top": return { x: 0.5, y: 0 }
                case "bottom": return { x: 0.5, y: 1 }
                case "left": return { x: 0, y: 0.5 }
                case "right": return { x: 1, y: 0.5 }
            }
        }
        const fractions = {
            top_left: { x: 0, y: 0 }, top_center: { x: 0.5, y: 0 }, top_right: { x: 1, y: 0 },
            center_left: { x: 0, y: 0.5 }, center: { x: 0.5, y: 0.5 }, center_right: { x: 1, y: 0.5 },
            bottom_left: { x: 0, y: 1 }, bottom_center: { x: 0.5, y: 1 }, bottom_right: { x: 1, y: 1 },
        }
        return fractions[presetId] ?? { x: 0.5, y: 0.5 }
    }

    // Real anchor flags for a "bar"-capable item (ticker/OSD), matching each
    // one's own tickerAnchorX/osdAnchorX properties exactly - single source
    // of truth so the live components and the editor/preview can't drift
    // apart the way they did before this existed. supportsVerticalBarHug is
    // false for the ticker (its "bar" preset has only ever hugged a
    // horizontal bar) and true for the OSD. customAnchor ("top" | "bottom")
    // only matters when position is "custom", and picks which edge the item
    // is actually anchored to (and therefore can never extend past), so a
    // bottom-anchored item grows upward instead of downward. Anything that
    // isn't "bottom" - including the removed "center" value still sitting in
    // an un-migrated config - is treated as "top".
    function barAnchors(position, supportsBar, supportsVerticalBarHug, customAnchor) {
        const isCustom = position === "custom"
        const isBar = supportsBar && position === "bar"
        if (isCustom) {
            return (customAnchor ?? "top") === "bottom"
                ? { top: false, bottom: true, left: true, right: false }
                : { top: true, bottom: false, left: true, right: false }
        }
        if (isBar) {
            if (supportsVerticalBarHug && root.barVertical) {
                return { top: false, bottom: false, left: !Config.options.bar.bottom, right: Config.options.bar.bottom }
            }
            return { top: !root.barVertical && !Config.options.bar.bottom, bottom: !root.barVertical && Config.options.bar.bottom, left: false, right: false }
        }
        return {
            top: position.startsWith("top"), bottom: position.startsWith("bottom"),
            left: position.endsWith("_left"), right: position.endsWith("_right"),
        }
    }

    // Real margins (screen pixels) for each anchored edge - edgeGap for a
    // plain corner/edge preset, barThickness+barGap for whichever edge(s)
    // the "bar" preset is actually hugging, or the custom fraction for
    // "custom" (always anchored top+left - see barAnchors() - so
    // margin.top/bottom + left double as its x/y position directly).
    //
    // customX is the item's LEFT edge and customY is whichever edge
    // customAnchor names, both as a fraction of the screen, measured from the
    // top-left in every mode - so neither needs converting, the edge IS the
    // value. itemW/itemH are read only by the clamp below.
    function barMargins(position, supportsBar, anchors, edgeGap, customX, customY, screenW, screenH, customAnchor, itemW, itemH, usable) {
        if (position === "custom") {
            // Render-time clamp, so nothing can end up drawn off-screen.
            // resolveDrop()/nudge() already clamp, but only at DRAG time and
            // only against the footprint as it was then - which says nothing
            // about an item that grows afterwards. The notification list is
            // exactly that: in "bottom" mode a tall enough stack runs past the
            // top edge. That used to be raw arithmetic that happily produced a
            // negative margin, and since the popup window is full-screen,
            // everything above y=0 was simply cut off.
            //
            // The area clamped WITHIN is the monitor minus its own bar's
            // reserved strip (see barInfoFor), not the raw monitor: "custom"
            // opts out of the compositor's exclusive zones on purpose, to keep
            // placement pixel-exact, which also means nothing else is keeping
            // it off the bar. Presets never needed this - ExclusionMode.Normal
            // does it for them - so a freely-dragged popup was the one thing
            // that could sit on top of the bar. Callers that pass no area get
            // the whole monitor, i.e. the old behaviour.
            const area = usable ?? { x: 0, y: 0, width: screenW, height: screenH }
            const maxLeft = Math.max(area.x, area.x + area.width - itemW)
            const maxTop = Math.max(area.y, area.y + area.height - itemH)
            const clampLeft = l => Math.max(area.x, Math.min(l, maxLeft))
            const clampTop = t => Math.max(area.y, Math.min(t, maxTop))

            if (anchors.bottom) {
                // Clamped as a TOP edge and converted back, so the clamp
                // means the same thing on both anchors - a bottom margin
                // clamped directly would still let the top run off-screen.
                const top = clampTop(customY * screenH - itemH)
                return { top: 0, bottom: screenH - (top + itemH), left: clampLeft(customX * screenW), right: 0 }
            }
            return { top: clampTop(customY * screenH), bottom: 0, left: clampLeft(customX * screenW), right: 0 }
        }
        // `usable` is the monitor area after subtracting the bar's currently
        // reserved strip. When fullscreen (or an auto-hidden bar) makes that
        // strip disappear, it is the full monitor and the popup must not add
        // the configured bar thickness just because the position is "bar".
        const barVisible = usable
            && (usable.width < screenW || usable.height < screenH)
        const isBar = supportsBar && position === "bar" && barVisible
        const barMargin = root.barThickness + root.barGap
        return {
            top: (isBar && anchors.top) ? barMargin : edgeGap,
            bottom: (isBar && anchors.bottom) ? barMargin : edgeGap,
            left: (isBar && anchors.left) ? barMargin : edgeGap,
            right: (isBar && anchors.right) ? barMargin : edgeGap,
        }
    }

    // Real top-left screen-pixel position a "bar"-capable item would
    // actually render at, given its real (or representative) footprint
    // size - accounts for the same anchor+margin logic barAnchors()/
    // barMargins() expose, so a caller that just wants "where does this
    // really end up" doesn't have to assemble it by hand.
    function anchoredRect(position, customX, customY, screenW, screenH, itemW, itemH, edgeGap, supportsBar, supportsVerticalBarHug, customAnchor, usable) {
        const anchors = root.barAnchors(position, supportsBar, supportsVerticalBarHug, customAnchor)
        const margins = root.barMargins(position, supportsBar, anchors, edgeGap, customX, customY, screenW, screenH, customAnchor, itemW, itemH, usable)
        let x, y
        if (anchors.left) x = margins.left
        else if (anchors.right) x = screenW - itemW - margins.right
        else x = (screenW - itemW) / 2
        if (anchors.top) y = margins.top
        else if (anchors.bottom) y = screenH - itemH - margins.bottom
        else y = (screenH - itemH) / 2
        return { x, y }
    }

    // Representative real-pixel footprint per item, shared by the static
    // preview canvas and the live editor so they agree on a size - and,
    // since the editor centers its draggable icon on this footprint (see
    // PopupEditHandle.qml's idleX/idleY), also what determines whether that
    // icon's center actually lines up with the real widget's center once it
    // renders. Verified against the real components directly:
    // - ticker: height 72 is exact (MediaControls.qml's tickerCardHeight).
    //   Width is genuinely content-dependent (clamped 180-420px based on
    //   track title/artist length) - 300 here is the midpoint of that
    //   range, not a measured constant, so this one specific axis can only
    //   ever be "usually close," never exact.
    // - notifications: width is exact - the real card width plus
    //   notificationElevationPad on each side, because every footprint here
    //   is the item's SHADOW-PADDED box, not its visible card (the ticker's
    //   72 and the OSD's 110 are their windows, which already contain that
    //   padding; a notification's has to be added). Height is unbounded - a group
    //   collapses to a single line (~80px) but expands with body
    //   text/images, and the popup stacks EVERY visible notification
    //   vertically, easily 200px+ with more than one queued - no static
    //   number can represent this. 80 is NotificationGroup.qml's own
    //   collapsed ceiling (its background is
    //   Math.min(80, row.implicitHeight + padding * 2) until expanded), so a
    //   single notification - by far the common case - is at most this tall
    //   and usually a little under. The old 120 was a guess at "a couple of
    //   typical notifications" and made every dragged custom position land
    //   ~30px above the dot it was dropped on, since the editor converts a
    //   dropped CENTER into a stored top edge using exactly this number.
    // - osd: width is an exact match. Height was measured directly against
    //   OsdValueIndicator.qml's real implicitHeight (slider + the
    //   always-present protection-message row, which occupies layout space
    //   even at zero opacity) - 110, not the old 64.
    readonly property var itemFootprints: ({
        ticker: { width: 300, height: 72 },
        notifications: {
            width: Appearance.sizes.notificationPopupWidth + 2 * root.notificationElevationPad,
            // A measured single notification, not the 80 ceiling: this is only
            // ever the pre-first-notification fallback, and a typical one
            // (title + one body line) renders 59 tall.
            height: 59 + 2 * root.notificationElevationPad,
        },
        osd: { width: Appearance.sizes.osdWidth + 4 * Appearance.sizes.elevationMargin + 80, height: 110 },
    })
    // Real, last-rendered padded-box size per item, reported by the live
    // widgets themselves (see reportFootprint() callers in MediaControls.qml,
    // OnScreenDisplay.qml and NotificationPopup.qml). itemFootprints above is
    // only the fallback for "this item hasn't rendered yet this session".
    //
    // This is what makes a dragged position land exactly, rather than close.
    // The editor drags a dot representing an item's CENTRE and stores an
    // EDGE, converting between the two with footprintFor() - so any gap
    // between that number and the item's real size becomes a permanent offset
    // between the dot and the popup, on whichever axis the guess was wrong.
    // With the real size the conversion cancels exactly: an item dropped with
    // its centre at C stores C - height/2, renders its box top there, and
    // puts its centre back at exactly C.
    //
    // Notifications report only while exactly ONE is on screen, which is both
    // the case worth being exact about and the only one with a well-defined
    // size - a stack of them is as tall as the stack happens to be.
    property var measuredFootprints: ({})

    function reportFootprint(itemId, w, h) {
        if (!(w > 0) || !(h > 0)) return
        const current = root.measuredFootprints[itemId]
        // Sub-pixel churn would otherwise republish this object (and re-run
        // every binding that reads it) on every frame of a size animation.
        if (current && Math.abs(current.width - w) < 0.5 && Math.abs(current.height - h) < 0.5) return
        const next = Object.assign({}, root.measuredFootprints)
        next[itemId] = { width: w, height: h }
        root.measuredFootprints = next
    }

    function footprintFor(itemId) {
        return root.measuredFootprints[itemId] ?? root.itemFootprints[itemId] ?? { width: 200, height: 60 }
    }

    // Real rendered top-left {x, y} for a given item - now a single call
    // through anchoredRect() for all three (notifications included).
    // Verified equivalent to the old, separately-maintained notificationRect():
    // with supportsBar:false, anchoredRect()'s "isBar" check is always
    // false, so its margins collapse to a flat edgeGap on every side
    // exactly like notifications' old always-4px model did, and its preset
    // anchor logic (position.startsWith/endsWith) was already byte-for-byte
    // the same formula notificationRect() had its own copy of. One real
    // formula per concern (anchors, margins) instead of three, each
    // independently prone to drifting out of sync with the others.
    function realRectFor(itemId, position, customX, customY, screenW, screenH, customAnchor, usable) {
        const footprint = root.footprintFor(itemId)
        const supportsBar = itemId !== "notifications"
        const supportsVerticalBarHug = itemId === "osd"
        const edgeGap = root.hyprlandGapsOut
        return root.anchoredRect(position, customX, customY, screenW, screenH, footprint.width, footprint.height, edgeGap, supportsBar, supportsVerticalBarHug, customAnchor, usable)
    }

    readonly property real hyprlandGapsOut: Appearance.sizes.hyprlandGapsOut

    // The padding a notification has to be positioned WITH, so that it lands
    // level with a ticker/OSD placed at the same point.
    //
    // Player.qml's (and OsdValueIndicator's) background shrinks by
    // elevationMargin on every side to leave room for its own shadow, so
    // every position those two are given names a box whose visible card is
    // already inset by that much. A notification card has no such inset - it
    // sits flush against its ListView's edge with the shadow spilling
    // outside - so placing the raw card at the same point leaves it high and
    // to the left by exactly this amount. Measured on real screenshots: 11px
    // (= 5 + 10 - 4) too high at a shared top_* preset, and (10, 10) off on
    // both axes at a shared "custom" point.
    //
    // Adding it to the edge gap alone would only ever fix the presets, since
    // "custom" never consults an edge gap. Notifications are therefore placed
    // as a box padded by this on all four sides - which is what the
    // ticker/OSD windows already are - and then drawn inset by it, so every
    // position mode is corrected by construction rather than one at a time.
    readonly property real notificationElevationPad: Appearance.sizes.elevationMargin

    // Which edge a freely-dropped item should anchor to, decided from where
    // it was dropped rather than from a setting the user has to reason about.
    // Drop it in the top half and it hangs from its top edge, growing
    // downward; drop it in the bottom half and it hangs from its bottom edge,
    // growing upward. That is what every notification daemon does, and it is
    // the only decision the old three-way "custom position anchor" option was
    // really making - the rest of it was asking the user which corner the
    // stored fraction happened to mean.
    //
    // Note this makes a drag across the midline change growth direction, not
    // just position. That is the intended behaviour: an item near the bottom
    // of the screen that grew downward would grow straight off it.
    function inferCustomAnchor(centerY, screenH) {
        return centerY > screenH / 2 ? "bottom" : "top"
    }

    // One-time migration off the removed "center" custom anchor. Its stored
    // customX/customY were the item's CENTRE, while every remaining mode
    // stores an edge - so without converting, a config carrying "center"
    // would put its popup half its own size away from where it used to be.
    // Anything still holding "center" after this (e.g. no screens yet at load
    // time) is read as "top" everywhere, so it degrades to that offset rather
    // than to anything broken.
    function migrateCenterAnchors() {
        const screen = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        if (!screen) return
        const toEdge = (itemId, centreX, centreY) => {
            const fp = root.footprintFor(itemId)
            return {
                x: root.clampNormalized(centreX - fp.width / 2 / screen.width, fp.width / screen.width),
                y: root.clampNormalized(centreY - fp.height / 2 / screen.height, fp.height / screen.height),
            }
        }
        const media = Config.options.media
        if (media.tickerCustomAnchor === "center") {
            const p = toEdge("ticker", media.tickerCustomX, media.tickerCustomY)
            media.tickerCustomX = p.x
            media.tickerCustomY = p.y
            media.tickerCustomAnchor = "top"
        }
        const notifications = Config.options.notifications
        if (notifications.customAnchor === "center") {
            const p = toEdge("notifications", notifications.customX, notifications.customY)
            notifications.customX = p.x
            notifications.customY = p.y
            notifications.customAnchor = "top"
        }
        const osd = Config.options.osd
        if (osd.customAnchor === "center") {
            const p = toEdge("osd", osd.customX, osd.customY)
            osd.customX = p.x
            osd.customY = p.y
            osd.customAnchor = "top"
        }
    }

    Component.onCompleted: if (Config.ready) root.migrateCenterAnchors()
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.migrateCenterAnchors()
        }
    }

    // Snap-to-preset algorithm for the live editor, shared (not a method on
    // a specific dragged handle instance) so a "redundant" release catcher
    // can resolve a drop without needing that instance - see
    // PopupEditorOverlay.qml's finishDragFallback() for why that redundancy
    // exists. dropX/dropY are real pixels relative to targetScreen. Compares
    // against each preset's REAL rendered center (via realRectFor), not a
    // naive corner/edge/center fraction, so the snap zones actually line up
    // with where things really render.
    //
    // Snapping to a named preset (the hot zones below) is the only snapping
    // left. Free drops used to also round to a 20px grid, which moved an item
    // up to 10px per axis away from where it was actually released - once the
    // footprints became real measurements, that rounding was the single
    // largest remaining gap between "where I dropped it" and "where it went".
    // Dragging a whole GROUP never snapped to that grid in the first place
    // (see PopupEditorWindow.qml's ClusterPill.onReleased), so removing it
    // also makes a single drop and a group drop behave the same way.
    function resolveDrop(itemId, supportsBar, dropX, dropY, targetScreen, customAnchor) {
        const hotZonePx = 48
        const barHugPx = 40
        const footprint = root.footprintFor(itemId)

        if (supportsBar) {
            const edge = root.barEdge
            const nearEdge =
                (edge === "top" && dropY < barHugPx) ||
                (edge === "bottom" && dropY > targetScreen.height - barHugPx) ||
                (edge === "left" && dropX < barHugPx) ||
                (edge === "right" && dropX > targetScreen.width - barHugPx)
            if (nearEdge) return { position: "bar" }
        }

        let best = null
        let bestDist = Infinity
        for (const id of root.presetIds) {
            const rect = root.realRectFor(itemId, id, 0, 0, targetScreen.width, targetScreen.height, undefined, root.usableRectFor(targetScreen))
            const cx = rect.x + footprint.width / 2
            const cy = rect.y + footprint.height / 2
            const dist = Math.hypot(dropX - cx, dropY - cy)
            if (dist < hotZonePx && dist < bestDist) { best = id; bestDist = dist }
        }
        if (best) return { position: best }

        // Convert the CENTER (what dropX/dropY represent) to the fraction
        // "custom" actually stores (see anchoredRect()'s custom branch) -
        // conflating a center point with an anchored edge was the bug behind
        // items reappearing nowhere near the drop point. customX is always
        // the left edge; customY is the top edge ("top", item grows down from
        // the dot) or the bottom edge ("bottom", item grows up from it).
        //
        // The conversion is only as exact as footprint.height is real, which
        // is why the live widgets now measure and report it (see
        // reportFootprint()) instead of a static guess being used here.
        const centerX = dropX
        const centerY = dropY
        const mode = root.inferCustomAnchor(centerY, targetScreen.height)
        const isBottomAnchored = mode === "bottom"

        // Clamped in real pixels against the bar-free area, then converted -
        // the stored fraction stays relative to the WHOLE monitor (that is
        // what the render side reads), but the box it describes is kept
        // inside the usable part of it. Clamping the fraction against the
        // whole screen, as this used to, is what let an item be dropped onto
        // the bar. The clamp uses the item's REAL footprint, so a wide ticker
        // can't be parked mostly off-screen either.
        const area = root.usableRectFor(targetScreen)
        const left = Math.max(area.x, Math.min(centerX - footprint.width / 2, area.x + area.width - footprint.width))
        const top = Math.max(area.y, Math.min(centerY - footprint.height / 2, area.y + area.height - footprint.height))
        return {
            position: "custom",
            customAnchor: mode,
            customX: left / targetScreen.width,
            // "bottom" stores the bottom edge, which is the clamped top plus
            // the item's own height - clamping the bottom edge directly would
            // leave the top free to run under the bar.
            customY: (isBottomAnchored ? top + footprint.height : top) / targetScreen.height,
        }
    }
}
