import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
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
    property bool raisePulse: false
    readonly property bool targetHovered: hoverTarget && hoverTarget.containsMouse
    readonly property bool wantsVisible: targetHovered || (keepOpenWhileHovered && popupHovered)
    readonly property bool ownsHover: !keepOpenWhileHovered || targetHovered || PopupState.activeHoverPopup === root

    active: keepOpenWhileHovered
        ? (ownsHover && (wantsVisible || closeTimer.running) && !raisePulse)
        : targetHovered

    function raiseToFront() {
        if (root.raisePulse) return
        root.raisePulse = true
        Qt.callLater(() => root.raisePulse = false)
    }

    onTargetHoveredChanged: {
        if (targetHovered) {
            PopupState.activeHoverPopup = root
            root.raiseToFront()
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

    onActiveChanged: {
        if (!active) {
            popupHovered = false
            if (!root.raisePulse && PopupState.activeHoverPopup === root && !targetHovered)
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

    component: PanelWindow {
        id: popupWindow
        screen: root.targetScreen

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

        mask: Region {
            item: popupBackground
        }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        margins {
            left: {
                if (root.barEdge === "right") return 0
                if (root.barEdge === "left") return root.barThickness
                return centerOffsetX 
            }
            top: {
                if (root.barEdge === "bottom") return 0
                if (root.barEdge === "top") return root.barThickness
                return centerOffsetY
            }
            right: root.barEdge === "right" ? root.barThickness : 0
            bottom: root.barEdge === "bottom" ? root.barThickness : 0
        }
        WlrLayershell.namespace: "quickshell:popup"
        // Popup windows are separate layer-shell surfaces, so an ordinary QML
        // z value cannot raise the one currently being hovered above its
        // siblings. Promote only the active hover popup to the top layer.
        WlrLayershell.layer: PopupState.activeHoverPopup === root
            ? WlrLayer.Top
            : WlrLayer.Overlay
        WlrLayershell.aboveWindows: PopupState.activeHoverPopup === root

        StyledRectangularShadow {
            target: popupBackground
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

            color: Appearance.colors.colLayer1Base
            radius: Appearance.rounding.normal + 4
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            HoverHandler {
                enabled: root.keepOpenWhileHovered
                onHoveredChanged: {
                    root.popupHovered = hovered
                    if (hovered) {
                        PopupState.activeHoverPopup = root
                        root.raiseToFront()
                    }
                }
            }

            // Reparent content here once the window is ready
                Component.onCompleted: {
                    if (popupWindow.innerContent) {
                        popupWindow.innerContent.parent = popupBackground
                        popupWindow.innerContent.anchors.centerIn = popupBackground
                    }
                }

            }
    }
}
