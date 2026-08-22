import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0

    property bool keepOpenWhileHovered: false
    property int hoverCloseDelay: 120
    property bool popupHovered: false
    // Set while a different popup is taking over, to force this one to close
    // immediately instead of waiting out closeTimer/hoverCloseDelay.
    property bool forceClosed: false
    readonly property bool targetHovered: !!hoverTarget && !!hoverTarget.containsMouse
    readonly property bool wantsVisible: targetHovered || (keepOpenWhileHovered && popupHovered)

    // Whether the popup should currently be on screen. closeImmediately() zeroes
    // this out right away instead of waiting for closeTimer.
    readonly property bool shouldShow: !forceClosed && (keepOpenWhileHovered
        ? (wantsVisible || closeTimer.running)
        : targetHovered)

    // Once shown, keep the underlying window alive forever (see `active` below)
    // and drive further show/hide purely through popupBackground.visible
    // instead of through LazyLoader.active. Destroying and recreating the
    // layer-shell surface on every hover transition isn't atomic at the
    // compositor level -- a newly hovered popup's surface could get mapped
    // before the previous popup's surface had actually been unmapped, which is
    // what let a new card render underneath a still-alive old one (confirmed
    // via `hyprctl layers` showing the outgoing surface as a pid=-1 zombie
    // while the new one was already mapped). Keeping the window itself always
    // mapped and only hiding its content avoids that create/destroy race
    // entirely for every hover after the first.
    property bool everShown: false
    active: shouldShow || everShown
    onActiveChanged: {
        if (active)
            everShown = true
    }

    function closeImmediately() {
        closeTimer.stop()
        forceClosed = true
    }

    onTargetHoveredChanged: {
        if (targetHovered) {
            if (PopupState.activeHoverPopup && PopupState.activeHoverPopup !== root)
                PopupState.activeHoverPopup.closeImmediately()
            forceClosed = false
            PopupState.activeHoverPopup = root
        }
    }

    onWantsVisibleChanged: {
        if (!keepOpenWhileHovered)
            return

        if (wantsVisible)
            closeTimer.stop()
        else
            closeTimer.restart()
    }

    onShouldShowChanged: {
        if (!shouldShow) {
            popupHovered = false
            if (PopupState.activeHoverPopup === root && !targetHovered)
                PopupState.activeHoverPopup = null
        }
    }

    property Timer closeTimer: Timer {
        interval: root.hoverCloseDelay
    }

    readonly property var targetScreen: hoverTarget?.QsWindow?.window?.screen
        ?? root.QsWindow?.window?.screen
        ?? null
    readonly property string popupMonitorName: targetScreen?.name ?? ""

    readonly property bool barVertical: Config.getBarSetting(popupMonitorName, ["vertical"], Config.options.bar.vertical)
    readonly property string barEdge: {
        const bottom = Config.getBarSetting(popupMonitorName, ["bottom"], Config.options.bar.bottom)
        if (!barVertical) return bottom ? "bottom" : "top"
        return bottom ? "right" : "left"
    }
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
    readonly property bool barVisibleOnScreen: PopupPlacement.barInfoFor(root.targetScreen).present

    component: PanelWindow {
        id: popupWindow
        screen: root.targetScreen
        // Deliberately NOT bound to root.shouldShow: toggling a layer-shell
        // window's visible property tears down and remaps the real Wayland
        // surface each time (confirmed via `hyprctl layers`, which showed the
        // outgoing surface briefly as a pid=-1 zombie while a new one was
        // already mapped) -- that's what actually caused the overlap, not any
        // QML-side timing. Instead the window stays mapped permanently once
        // created, and show/hide is done purely by hiding popupBackground
        // below, which never touches the native surface.
        visible: true

        // Bring contentItem reference into this scope
        property Item innerContent: root.contentItem

        color: "transparent"
        anchors.left: root.barEdge !== "right"
        anchors.right: root.barEdge === "right"
        anchors.top: root.barEdge !== "bottom"
        anchors.bottom: root.barEdge === "bottom"

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        readonly property real centerOffsetX: {
            const base = root.QsWindow?.mapFromItem(
                root.hoverTarget,
                (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
            ).x ?? 0
            const margin = Appearance.sizes.elevationMargin
            const maxLeft = popupWindow.screen.width - popupBackground.implicitWidth - margin - 10
            return Math.max(margin, Math.min(base, maxLeft))
        }
        readonly property real centerOffsetY: {
            const base = root.QsWindow?.mapFromItem(
                root.hoverTarget,
                0, (root.hoverTarget.height - popupBackground.implicitHeight) / 2
            ).y ?? 0
            const margin = Appearance.sizes.elevationMargin
            const maxTop = popupWindow.screen.height - popupBackground.implicitHeight - margin - 15
            return Math.max(margin, Math.min(base, maxTop))
        }

        // Explicit geometry instead of `item: popupBackground` so the mask can
        // collapse to zero size while hidden -- the window itself stays
        // permanently mapped (see the visible: true note above), so without
        // this the invisible popup would keep eating clicks/hover in its
        // would-be screen position.
        mask: Region {
            x: popupBackground.x
            y: popupBackground.y
            width: root.shouldShow ? popupBackground.width : 0
            height: root.shouldShow ? popupBackground.height : 0
        }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        margins {
            left: {
                if (root.barEdge === "right") return 0
                if (root.barEdge === "left") return root.barVisibleOnScreen ? root.barThickness : 0
                return centerOffsetX 
            }
            top: {
                if (root.barEdge === "bottom") return 0
                if (root.barEdge === "top") return root.barVisibleOnScreen ? root.barThickness : 0
                return centerOffsetY
            }
            right: root.barEdge === "right" && root.barVisibleOnScreen ? root.barThickness : 0
            bottom: root.barEdge === "bottom" && root.barVisibleOnScreen ? root.barThickness : 0
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        StyledRectangularShadow {
            target: popupBackground
            // It's a sibling of popupBackground, not a child, so it doesn't
            // automatically inherit popupBackground's visible: root.shouldShow --
            // without this it kept rendering its own dark blurred rectangle even
            // while the card itself was hidden.
            visible: root.shouldShow
        }

            Rectangle {
            id: popupBackground
            readonly property real margin: 8

            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }

            // Use local reference instead of crossing LazyLoader scope boundary
            implicitWidth: (popupWindow.innerContent?.implicitWidth ?? 0) + margin * 2
            implicitHeight: (popupWindow.innerContent?.implicitHeight ?? 0) + margin * 2

            color: MonitorThemes.shellColorForItem(popupWindow, "colLayer1Base", Appearance.colors.colLayer1Base)
            radius: Appearance.rounding.normal + 4
            border.width: 1
            border.color: MonitorThemes.shellColorForItem(popupWindow, "colLayer0Border", Appearance.colors.colLayer0Border)

            // The window (popupWindow) itself is always mapped; this item is what
            // actually shows/hides the popup, purely via a scene-graph property, so
            // it never touches the native surface.
            visible: root.shouldShow

            // Brief pop-in every time the popup becomes visible (not just on first
            // creation, since the window is now reused across hovers -- see
            // root.everShown above). Hiding is instant (visible flips straight to
            // false), so we only animate the entrance.
            opacity: 0
            scale: 0.94
            Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

            HoverHandler {
                enabled: root.keepOpenWhileHovered
                onHoveredChanged: {
                    root.popupHovered = hovered
                }
            }

            function playEntrance() {
                if (!root.shouldShow)
                    return
                popupBackground.opacity = 1
                popupBackground.scale = 1
            }

            Connections {
                target: root
                function onShouldShowChanged() {
                    if (root.shouldShow)
                        popupBackground.playEntrance()
                    else {
                        popupBackground.opacity = 0
                        popupBackground.scale = 0.94
                    }
                }
            }

            // Reparent content here once the window is ready
                Component.onCompleted: {
                    if (popupWindow.innerContent) {
                        popupWindow.innerContent.parent = popupBackground
                        popupWindow.innerContent.anchors.centerIn = popupBackground
                    }
                    popupBackground.playEntrance()
                }

            }
    }
}
