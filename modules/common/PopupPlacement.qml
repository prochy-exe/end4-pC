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
    // Style 3 (M3) floats the bar itself away from the screen edge via an
    // external window margin (see Bar.qml), not by baking that offset into
    // barHeight/verticalBarWidth the way style 1 (Float) does - so
    // barThickness above stops short of the bar's real bottom/right edge by
    // exactly one gapsOut. A popup hugging the bar needs that added back
    // just to reach the bar's real edge (flush, no visible gap) - which is
    // the right amount for the ticker/Super+M menu, since those read as
    // part of the bar itself. Popups that are NOT part of the bar (OSD,
    // audio bridge card) additionally want a visible gap beyond that - see
    // extraBarGap below.
    readonly property real barGap: Config.options.bar.cornerStyle === 3 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property bool cornerStyleReducesGap: Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 2
    // Style 3's painted pill (BarGroup.qml's `background`) is inset 4px top
    // and bottom within its baseBarHeight slot, not flush with it - measured
    // against the real rendered bar (see barMargins() below), not a guess.
    readonly property real materialPillInset: Config.options.bar.cornerStyle === 3 ? 4 : 0

    // PER-MONITOR bar geometry. The properties above (barVertical/barEdge/
    // barThickness) read the GLOBAL bar settings, which is wrong the moment a
    // monitor overrides any of them - and this config supports exactly that,
    // through Config.getBarSetting()/bar.monitorSettings, plus bar.screenList
    // deciding whether a monitor has a bar at all. Everything that needs to
    // know where the bar is - the preview and the clamp that keeps popups
    // off it - goes through here so one monitor's bar can never be
    // described using another's settings.
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
    // of truth so the live components and the preview can't drift apart the
    // way they did before this existed. supportsVerticalBarHug is false for
    // the ticker (its "bar" preset has only ever hugged a horizontal bar)
    // and true for the OSD.
    function barAnchors(position, supportsBar, supportsVerticalBarHug) {
        const isBar = supportsBar && position === "bar"
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
    // plain corner/edge preset, or barThickness+barGap for whichever edge(s)
    // the "bar" preset is actually hugging.
    //
    // extraBarGap: additional space beyond barGap for callers that are NOT
    // part of the bar itself (OSD, audio bridge card) and want a real visual
    // gap between themselves and the bar - as opposed to the ticker/Super+M
    // menu, which read as an extension of the bar and stay flush against it
    // (extraBarGap 0, the default). Only applies to the edge(s) actually
    // hugging the bar, same as barGap.
    function barMargins(position, supportsBar, anchors, edgeGap, screenW, screenH, usable, extraBarGap = 0) {
        // `usable` is the monitor area after subtracting the bar's currently
        // reserved strip. When fullscreen (or an auto-hidden bar) makes that
        // strip disappear, it is the full monitor and the popup must not add
        // the configured bar thickness just because the position is "bar".
        const barVisible = usable
            && (usable.width < screenW || usable.height < screenH)
        const isBar = supportsBar && position === "bar" && barVisible
        const barMargin = root.barThickness - root.materialPillInset + root.barGap + extraBarGap
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
    function anchoredRect(position, screenW, screenH, itemW, itemH, edgeGap, supportsBar, supportsVerticalBarHug, usable) {
        const anchors = root.barAnchors(position, supportsBar, supportsVerticalBarHug)
        const margins = root.barMargins(position, supportsBar, anchors, edgeGap, screenW, screenH, usable)
        let x, y
        if (anchors.left) x = margins.left
        else if (anchors.right) x = screenW - itemW - margins.right
        else x = (screenW - itemW) / 2
        if (anchors.top) y = margins.top
        else if (anchors.bottom) y = screenH - itemH - margins.bottom
        else y = (screenH - itemH) / 2
        return { x, y }
    }

    // Representative real-pixel footprint per item, used as a fallback for
    // the preview canvas before an item has rendered for real this session
    // (see measuredFootprints below). Verified against the real components
    // directly:
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
    //   and usually a little under.
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
    // only the fallback for "this item hasn't rendered yet this session" -
    // this is what the preview canvas actually shows once it has.
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
    function realRectFor(itemId, position, screenW, screenH, usable) {
        const footprint = root.footprintFor(itemId)
        const supportsBar = itemId !== "notifications"
        const supportsVerticalBarHug = itemId === "osd"
        const edgeGap = root.hyprlandGapsOut
        return root.anchoredRect(position, screenW, screenH, footprint.width, footprint.height, edgeGap, supportsBar, supportsVerticalBarHug, usable)
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
    // (= 5 + 10 - 4) too high at a shared top_* preset.
    //
    // Notifications are therefore placed as a box padded by this on all four
    // sides - which is what the ticker/OSD windows already are - and then
    // drawn inset by it, so every preset is corrected by construction rather
    // than one at a time.
    readonly property real notificationElevationPad: Appearance.sizes.elevationMargin
}
