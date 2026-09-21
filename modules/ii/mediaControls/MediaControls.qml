pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    // Snapshot of whichever player a media key/bind action was just performed
    // on (set from MprisController.actionPerformed) - the ticker shows this,
    // not the live activePlayer, since activePlayer can re-resolve to someone
    // else the instant the action changes playback state (see actionPerformed).
    property MprisPlayer tickerPlayer: null
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: MprisController.sortByPriority(filterDuplicatePlayers(realPlayers))
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.popupRounding

    // "bar" hugs whichever edge the bar is on (original behavior); the
    // explicit corner/edge presets are independent of the bar entirely.
    readonly property string tickerPosition: Config.options.media.tickerPosition
    readonly property real tickerEdgeGap: Appearance.sizes.hyprlandGapsOut
    // Real anchor flags for the ticker's position preset - PopupPlacement.qml
    // is the single source of truth for this, also used by the preview so
    // it can't silently drift from what actually renders (it did, before
    // this existed). The margins additionally need the resolved screen's
    // size, so those are computed on tickerWindow itself below, where
    // that's actually in scope.
    readonly property var tickerAnchors: PopupPlacement.barAnchors(root.tickerPosition, true, false)

    // The card's height is a fixed constant (Appearance.sizes.mediaControlsHeight),
    // not derived from content - the volume row needs its space added on top
    // of that explicitly, or it gets clipped by the card's rounded mask. Only
    // adds it when the row will actually render (toggle on AND this player
    // supports MPRIS volume), so players without it don't get empty space.
    function volumeBarExtraHeight(player) {
        if (!Config.options.media.menuElements.includes("volumeBar")) return 0
        if (!(player?.volumeSupported ?? false)) return 0
        return 46
    }

    readonly property string mediaPosition: {
        if (Config.options.bar.layouts.leftLayout.includes("media")) return "left"
        if (Config.options.bar.layouts.middleLayout.includes("media")) return "center"
        if (Config.options.bar.layouts.rightLayout.includes("media")) return "right"
        return "center"
    }

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    // Real bar-hugging thickness for this menu's own hand-rolled margin
    // formula below (barMargins() applies the same materialPillInset
    // subtraction internally, but this menu doesn't go through it).
    readonly property real barFlushThickness: PopupPlacement.barThickness - PopupPlacement.materialPillInset

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Find duplicates: either the same title, or two players mirroring
            // the same stream (same position and length).
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                const sameTitle = p1.trackTitle && p2.trackTitle
                    && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle));
                // These have to be absolute differences. Comparing the signed
                // difference to 2 is true for any player whose position and
                // length are merely *below* another's, so unrelated players got
                // merged and whichever had cover art swallowed the other - a
                // YouTube tab would vanish from the list while still showing in
                // the ticker, which reads activePlayer directly.
                //
                // Both lengths must be real, too: players that report none (live
                // streams say 0) would otherwise all collapse into one entry.
                const sameStream = p1.length > 0 && p2.length > 0
                    && Math.abs(p1.length - p2.length) <= 2
                    && Math.abs(p1.position - p2.position) <= 2;
                if (sameTitle || sameStream) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true
            screen: PopupPlacement.resolveScreen("focused", "")

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: playerColumnLayout.implicitHeight
            readonly property bool barVisibleOnScreen: PopupPlacement.barInfoFor(panelWindow.screen).present
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: true
                left: true
            }
            margins {
                top: {
                    if (root.barEdge === "top") return panelWindow.barVisibleOnScreen
                        ? root.barFlushThickness + (PopupPlacement.cornerStyleReducesGap ? -PopupPlacement.barGap -6 : PopupPlacement.barGap)
                        : PopupPlacement.barGap
                    if (root.barEdge === "bottom") return panelWindow.screen.height - (panelWindow.barVisibleOnScreen ? root.barFlushThickness : 0) - (PopupPlacement.cornerStyleReducesGap ? -PopupPlacement.barGap : PopupPlacement.barGap) - playerColumnLayout.implicitHeight
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.height - playerColumnLayout.implicitHeight - PopupPlacement.barGap
                    return (panelWindow.screen.height - playerColumnLayout.implicitHeight) / 2
                }
                left: {
                    if (root.barEdge === "left") return panelWindow.barVisibleOnScreen
                        ? root.barFlushThickness + (PopupPlacement.cornerStyleReducesGap ? -PopupPlacement.barGap : PopupPlacement.barGap)
                        : PopupPlacement.barGap
                    if (root.barEdge === "right") return panelWindow.screen.width - (panelWindow.barVisibleOnScreen ? root.barFlushThickness : 0) - (PopupPlacement.cornerStyleReducesGap ? -PopupPlacement.barGap : PopupPlacement.barGap) - root.widgetWidth
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.width - root.widgetWidth - PopupPlacement.barGap
                    return (panelWindow.screen.width - root.widgetWidth) / 2
                }
            }

            mask: Region {
                item: playerColumnLayout
            }

            Component.onCompleted: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (!Config.options.bar.media.alwaysVisible)
                        GlobalStates.mediaControlsOpen = false;
                }
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                // A quick pop-in on open, so clicking the ticker into the
                // full menu reads as an expansion rather than an instant
                // swap between two unrelated windows.
                opacity: 0
                scale: 0.92
                Component.onCompleted: {
                    playerColumnLayout.opacity = 1
                    playerColumnLayout.scale = 1
                }
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: Player {
                        id: playerCard
                        required property MprisPlayer modelData
                        player: modelData
                        // This card's own app, not the shared stream - two apps
                        // playing at once must not draw identical bars.
                        property AppAudioTap tap: AppAudioTap {
                            player: playerCard.modelData
                            active: GlobalStates.mediaControlsOpen
                        }
                        visualizerPoints: playerCard.tap.points
                        implicitWidth: root.widgetWidth
                        implicitHeight: showLyrics ? 290 : Appearance.sizes.mediaControlsHeight + root.volumeBarExtraHeight(modelData)
                        radius: root.popupRounding
                        controlElements: Config.options.media.menuElements
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    // Best-effort match: player.desktopEntry/identity (lowercased) against
    // open windows' class - close enough for the common case (a player's
    // desktopEntry is normally the same string apps set as their window
    // class), but not a guaranteed match for every player.
    function isPlayerWindowVisible(player) {
        if (!player) return false
        const ident = MprisController.playerIdentifier(player)
        if (!ident) return false
        return HyprlandData.windowList.some(win => {
            const cls = (win.class || "").toLowerCase()
            if (!cls) return false
            if (cls !== ident && !cls.includes(ident) && !ident.includes(cls)) return false
            return win.mapped !== false && win.visible !== false
        })
    }

    function triggerTicker(player) {
        if (GlobalStates.mediaControlsOpen || !Config.options.media.tickerEnabled) return
        if (Config.options.media.tickerHideIfPlayerVisible && root.isPlayerWindowVisible(player)) return
        root.tickerPlayer = player
        GlobalStates.mediaTickerOpen = true
        tickerTimeout.restart()
    }

    // Flashes a compact ticker when a media key/bind fires (routed through
    // MprisController, see its actionPerformed signal) - not when the full
    // menu's own buttons are clicked, since the menu is already visible then.
    Connections {
        target: MprisController
        function onActionPerformed(action, player) {
            root.triggerTicker(player)
        }
        // Opt-in: also flashes when a track changes with no key/bind press
        // involved at all (song ended and the next one started on its own).
        function onTrackAutoChanged(player) {
            if (!Config.options.media.tickerOnTrackChange) return
            root.triggerTicker(player)
        }
    }

    Timer {
        id: tickerTimeout
        interval: Config.options.media.tickerTimeout
        repeat: false
        onTriggered: GlobalStates.mediaTickerOpen = false
    }

    // Smaller text/margins than the full menu card (see PlayerControls.qml's
    // contentScale), and a width computed from the actual title/artist text
    // instead of a fixed one - a fixed width either wastes space or elides
    // the title, and shrinking the height alone can't fix that.
    readonly property real tickerContentScale: 0.85
    readonly property real tickerCardHeight: 72
    // Player.qml's own background Rectangle shrinks by this on every side
    // before PlayerControls.qml's own margins even start - missing this the
    // first time is why the title kept eliding despite the "dynamic" width.
    readonly property real tickerElevationMargin: Appearance.sizes.elevationMargin
    readonly property real tickerMargin: 13 * root.tickerContentScale
    readonly property real tickerSpacing: 15 * root.tickerContentScale
    readonly property real tickerArtSize: root.tickerCardHeight - 2 * root.tickerElevationMargin - 2 * root.tickerMargin
    // Same raw radius as the Super+M card (popupRounding), so the ticker
    // actually tracks the user's Hyprland rounding setting like every other
    // popup does. Still clamped defensively: the art thumbnail sits this far
    // from the card's edge, and if the radius exceeds that, the mask's curve
    // cuts into the (square) thumbnail's corner instead of just rounding the
    // card, distorting it into a lopsided/circular shape.
    readonly property real tickerRadius: Math.min(
        root.popupRounding,
        root.tickerElevationMargin + root.tickerMargin)
    readonly property real tickerTextWidth: Math.max(tickerTitleMetrics.width, tickerArtistMetrics.width)
    readonly property real tickerContentOverhead: 2 * root.tickerElevationMargin + 2 * root.tickerMargin + root.tickerArtSize + root.tickerSpacing
    readonly property real tickerCardWidth: Math.min(420, Math.max(root.osdWidth,
        root.tickerContentOverhead + root.tickerTextWidth + 12))

    // Tell the popup editor how big the ticker really is, so its dot lands on
    // the real card instead of on PopupPlacement's static guess (300 was the
    // midpoint of this width's 180-420 range - never actually right). Driven
    // by the compact card's own size rather than the live window's, so it
    // stays correct while the ticker isn't on screen at all, which is exactly
    // when the editor is being used. Deliberately not the EXPANDED size:
    // clicking the ticker open is a transient state, not where it lives.
    function reportTickerFootprint() {
        PopupPlacement.reportFootprint("ticker", root.tickerCardWidth, root.tickerCardHeight)
    }
    onTickerCardWidthChanged: root.reportTickerFootprint()
    Component.onCompleted: root.reportTickerFootprint()

    TextMetrics {
        id: tickerTitleMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.large * root.tickerContentScale
        text: StringUtils.cleanMusicTitle(root.tickerPlayer?.trackTitle) || Translation.tr("No media")
    }
    TextMetrics {
        id: tickerArtistMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smaller * root.tickerContentScale
        text: root.tickerPlayer?.trackArtist ?? ""
    }

    Loader {
        id: tickerLoader
        active: GlobalStates.mediaTickerOpen

        sourceComponent: PanelWindow {
            id: tickerWindow
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaTicker"
            WlrLayershell.layer: WlrLayer.Overlay
            screen: PopupPlacement.resolveScreen(Config.options.media.tickerMonitorMode, Config.options.media.tickerMonitorName)
            readonly property var tickerMargins: PopupPlacement.barMargins(root.tickerPosition, true, root.tickerAnchors, root.tickerEdgeGap,
                tickerWindow.screen?.width ?? 0, tickerWindow.screen?.height ?? 0,
                PopupPlacement.usableRectFor(tickerWindow.screen))

            anchors {
                top: root.tickerAnchors.top
                bottom: root.tickerAnchors.bottom
                left: root.tickerAnchors.left
                right: root.tickerAnchors.right
            }
            // "bar" ignores the bar's own reserved space on purpose - its
            // margin already precisely hugs the bar (barThickness+barGap),
            // and respecting the exclusive zone on top of that would push it
            // an extra, unwanted step further away. Named corner/edge
            // presets respect it instead (ExclusionMode.Normal, same as
            // SidebarLeft.qml), so a preset-placed ticker doesn't render
            // underneath the bar.
            exclusionMode: root.tickerPosition === "bar" ? ExclusionMode.Ignore : ExclusionMode.Normal
            exclusiveZone: 0
            margins {
                top: tickerWindow.tickerMargins.top
                bottom: tickerWindow.tickerMargins.bottom
                left: tickerWindow.tickerMargins.left
                right: tickerWindow.tickerMargins.right
            }

            mask: Region { item: tickerPlayerCard }
            implicitWidth: tickerPlayerCard.implicitWidth
            implicitHeight: tickerPlayerCard.implicitHeight

            // The ticker starts as a minimal Player card (no clickable
            // controls - a popup you can't reach without dismissing it has
            // no business offering buttons to press) and clicking it grows
            // it in place into the full card, same as the Super+M menu shows
            // for that player. Scrolling adjusts that player's own MPRIS
            // volume directly (not a PipeWire sink) in either state.
            Player {
                id: tickerPlayerCard
                property bool expanded: false
                anchors.horizontalCenter: parent.horizontalCenter
                player: root.tickerPlayer
                property AppAudioTap tap: AppAudioTap {
                    player: root.tickerPlayer
                    active: GlobalStates.mediaTickerOpen
                }
                visualizerPoints: tickerPlayerCard.tap.points
                implicitWidth: expanded ? root.widgetWidth : root.tickerCardWidth
                implicitHeight: expanded ? Appearance.sizes.mediaControlsHeight : root.tickerCardHeight
                // Same rounding as the Super+M menu card in both states now
                // - popupRounding already backs off the raw Hyprland
                // decoration.rounding setting a bit (see Appearance.qml).
                radius: expanded ? root.popupRounding : root.tickerRadius
                controlElements: expanded ? null : ["visualizer"]
                contentScale: expanded ? 1.0 : root.tickerContentScale
                showBlurredArt: expanded
                centerContent: !expanded
                // The ticker's window is always sized exactly to this card's
                // bounds (compact or expanded) - no room for the shadow to
                // bleed into without getting clipped unevenly by the mask.
                showShadow: false

                Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    // Once expanded, this needs to stop claiming clicks so
                    // they reach the card's own prev/next/playpause buttons
                    // underneath instead of just re-triggering here.
                    acceptedButtons: tickerPlayerCard.expanded ? Qt.NoButton : Qt.LeftButton
                    onEntered: tickerTimeout.stop()
                    onExited: tickerTimeout.restart()
                    onClicked: tickerPlayerCard.expanded = true
                    onWheel: event => {
                        if (!(root.tickerPlayer?.volumeSupported ?? false)) return
                        const step = 0.05
                        const current = root.tickerPlayer.volume ?? 0
                        root.tickerPlayer.volume = Math.max(0, Math.min(1, current + (event.angleDelta.y > 0 ? step : -step)))
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            mediaControlsLoader.active = !mediaControlsLoader.active;
            if (mediaControlsLoader.active)
                Notifications.timeoutAll();
        }

        function close(): void {
            mediaControlsLoader.active = false;
        }

        function open(): void {
            mediaControlsLoader.active = true;
            Notifications.timeoutAll();
        }
    }

    IpcHandler {
        target: "mediaTicker"

        function trigger(): void {
            root.triggerTicker(MprisController.activePlayer);
        }

        function hide(): void {
            GlobalStates.mediaTickerOpen = false;
        }
    }

    GlobalShortcut {
        name: "mediaTickerTrigger"
        description: "Shows the media ticker on press"

        onPressed: {
            root.triggerTicker(MprisController.activePlayer);
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }

    GlobalShortcut {
        name: "temporaryNotificationTest"
        description: "Sends a temporary test notification"

        onPressed: Quickshell.execDetached([
            "notify-send", "Quickshell test", "Temporary notification placement test", "-a", "Shell"
        ])
    }
}
