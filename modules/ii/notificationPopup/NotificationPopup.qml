import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        property string monitorMode: Config.options.notifications.monitorMode ?? "primary"
        property string monitorName: Config.options.notifications.monitorName ?? ""

        screen: PopupPlacement.resolveScreen(root.monitorMode, root.monitorName)
        readonly property bool barVisibleOnScreen: PopupPlacement.barInfoFor(root.screen).present

        property string position: {
            const raw = Config.options.notifications.position ?? "top_right"
            if (raw === "top") return "top_right"
            if (raw === "bottom") return "bottom_right"
            return raw
        }
        // Only meaningful when position is "custom" - which edge (or
        // center) customX/Y name. See Config.qml's media.tickerCustomAnchor
        // doc comment for the full explanation of this convention.
        property string customAnchor: Config.options.notifications.customAnchor ?? "top"

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        // Named presets respect the bar's reserved exclusive zone (the
        // engine default, unset here - this was already "bar aware" before
        // the popup-position editor existed). "custom" explicitly opts out
        // (ExclusionMode.Ignore) - a freely-dragged position needs
        // pixel-exact placement matching the editor's dot; letting the
        // compositor silently push it away from the bar's reserved zone
        // put a real notification tens of px from wherever it was actually
        // dropped (confirmed by measuring a real screenshot - see
        // MediaControls.qml's tickerWindow.exclusionMode for the same fix
        // applied there and to OnScreenDisplay.qml).
        exclusionMode: root.position === "custom" || !root.barVisibleOnScreen
            ? ExclusionMode.Ignore
            : ExclusionMode.Normal

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: listview.contentItem
        }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth

        NotificationListView {
            id: listview
            width: Appearance.sizes.notificationPopupWidth
            popup: true

            // A real height, rather than the 0 a Flickable is left at
            // whenever nothing anchors it top AND bottom. Without this the
            // view is a zero-height box that its (unclipped) delegates merely
            // hang below, so every position that needs to know how tall this
            // is - anything bottom- or centre-aligned - was working off a
            // size of 0. It also keeps contentHeight honest: a zero-height
            // view only ever builds the delegates that fit in its viewport
            // plus cacheBuffer.
            height: Math.min(listview.contentHeight, root.screen.height * 0.75)

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: listview.width
                    height: listview.height
                    radius: Appearance.rounding.normal
                }
            }

            // ONE fixed anchor pair (top+left), for every position - preset,
            // custom, centered, all of it - with the entire placement
            // expressed as the two margins. Deliberately not the
            // "anchors.foo: flag ? parent.foo : undefined" pattern the ticker
            // and OSD use: those two move their whole PanelWindow, where the
            // "anchors" are layer-shell's and switching them is free, while
            // this is a real QML Item inside a full-screen window, where
            // switching anchor sets at runtime is destructive.
            //
            // Changing e.g. "center" -> "custom" makes QML apply the new
            // anchors.left while anchors.horizontalCenter is still set, and
            // an item anchored left AND horizontalCenter has an
            // anchor-DERIVED width (2 * (hcenter - left)) - which silently
            // overwrites the explicit width above and never gives it back,
            // even after the centre anchor clears. Measured live: switching
            // out of a centred position stretched this 410px view to 1510px
            // (= 2 * (960 - 205), from its own stale pre-switch x), and
            // 59px tall to 980px, wrong on both axes exactly as reported.
            // That same stretch is what made the margins read a size that the
            // margins themselves had just changed, which is the binding loop
            // Qt was reporting ("Binding loop detected for property
            // realMargins"). A fixed anchor pair has neither failure: nothing
            // but the two margins ever changes, so width stays 410 and height
            // stays contentHeight no matter what the position is switched to,
            // in any order, at runtime.
            //
            // anchoredRect() is the SAME shared function the editor and
            // preview place their dots with (via realRectFor()), so "where
            // the dot is" and "where the notification lands" cannot drift
            // apart. supportsBar:false - notifications have no "bar" preset.
            //
            // What gets placed is the SHADOW-PADDED box, not the card: the
            // size handed to anchoredRect() is the card grown by
            // notificationElevationPad on all four sides, and the card is
            // then drawn back inset by that same pad. See that property for
            // why - in short, it is what makes a notification sit level with
            // a ticker/OSD given the same position, in every mode at once
            // rather than presets only.
            readonly property real pad: PopupPlacement.notificationElevationPad
            readonly property var placement: PopupPlacement.anchoredRect(root.position,
                Config.options.notifications.customX, Config.options.notifications.customY,
                root.width, root.height,
                // The width CONSTANT, not listview.width: reading back the
                // property being positioned is what starts the loop above.
                Appearance.sizes.notificationPopupWidth + 2 * pad, listview.height + 2 * pad,
                PopupPlacement.hyprlandGapsOut, false, false, root.customAnchor,
                PopupPlacement.usableRectFor(root.screen))

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: placement.y + pad
            anchors.leftMargin: placement.x + pad

            // Real size -> popup editor, so a dragged custom position lands
            // on the notification instead of near it. Only while exactly ONE
            // notification is up: that is the case worth being exact about,
            // and the only one with a well-defined height (a stack is however
            // tall the stack is). Reports the same padded box that gets
            // positioned above, so the editor's centre-to-edge conversion
            // cancels exactly - see PopupPlacement.reportFootprint().
            function reportFootprint() {
                if (listview.count !== 1) return
                PopupPlacement.reportFootprint("notifications",
                    Appearance.sizes.notificationPopupWidth + 2 * listview.pad,
                    listview.contentHeight + 2 * listview.pad)
            }
            onContentHeightChanged: listview.reportFootprint()
            onCountChanged: listview.reportFootprint()


            // Purely a layout-direction question now that no anchor depends
            // on it: newest notification nearest whichever edge this hugs.
            readonly property var anchorFlags: PopupPlacement.barAnchors(root.position, false, false, root.customAnchor)

            // Subsumes the old isBottom/isCustomBottom split into one
            // check - anchorFlags.bottom is already true for EITHER a
            // "bottom_*" preset or "custom" with customAnchor "bottom".
            verticalLayoutDirection: anchorFlags.bottom ? ListView.BottomToTop : ListView.TopToBottom
        }
    }
}
