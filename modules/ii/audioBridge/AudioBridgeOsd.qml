import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Its own dedicated OSD, deliberately separate from the shared
// OnScreenDisplay.qml system (volume/brightness/gamma) - that system
// dismisses on mouse hover (see its MouseArea's onEntered), which would
// fight against actually dragging a slider on it, and it only ever shows
// one indicator at a time, which doesn't suit combining an output change
// with the volume change it often causes into one merged card. This is a
// self-contained equivalent: bar-anchored the same way via
// PopupPlacement, auto-hides the same way, but stays open (and the
// auto-hide timer pauses) while the volume slider below is actually being
// interacted with.
Scope {
    id: root

    property bool osdOpen: false
    readonly property string osdPosition: "bar"
    readonly property real osdEdgeGap: Appearance.sizes.hyprlandGapsOut
    readonly property var osdAnchors: PopupPlacement.barAnchors(root.osdPosition, true, true)

    function trigger() {
        // The main popup (AudioBridge.qml) already shows live volume/output
        // state directly - this OSD exists for when that's closed, so
        // showing both at once is just a redundant second card.
        if (GlobalStates.audioBridgeOpen) return
        root.osdOpen = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: Config.options.osd.timeout
        repeat: false
        onTriggered: root.osdOpen = false
    }

    // Also close it if the main popup gets opened while it's already
    // showing, rather than leaving them briefly stacked.
    Connections {
        target: GlobalStates
        function onAudioBridgeOpenChanged() {
            if (GlobalStates.audioBridgeOpen) {
                hideTimer.stop()
                root.osdOpen = false
            }
        }
    }

    // Any volume/mute change on whichever device is currently the real
    // target (AudioBridgeRouter decides which - target rebinds
    // automatically when that changes) triggers this, regardless of
    // source: a keyboard shortcut, the main popup's own slider, or a
    // device push (e.g. its physical remote/knob).
    Connections {
        target: AudioBridgeRouter.activeBridge
        function onVolumePercentChanged() { root.trigger() }
        function onIsMutedChanged() { root.trigger() }
    }
    // The DX5 II's own output routing changing - always the DX5 II
    // regardless of which device volume actions are currently routed to.
    // Triggers the same merged card, so an output switch that also
    // changes the effective volume (different outputs often have
    // different remembered levels) shows as one consistent card instead
    // of two separately-timed ones racing/overwriting each other.
    Connections {
        target: Dx5iiBridge
        function onOutputTypeChanged() { root.trigger() }
    }

    Loader {
        id: osdLoader
        active: root.osdOpen

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"
            screen: PopupPlacement.resolveScreen(Config.options.osd.monitorMode, Config.options.osd.monitorName)
            readonly property bool barVisibleOnScreen: PopupPlacement.barInfoFor(osdRoot.screen).present
            readonly property var osdMargins: PopupPlacement.barMargins(root.osdPosition, true, root.osdAnchors, root.osdEdgeGap,
                osdRoot.screen?.width ?? 0, osdRoot.screen?.height ?? 0,
                PopupPlacement.usableRectFor(osdRoot.screen))

            WlrLayershell.namespace: "quickshell:audioBridgeOsd"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: root.osdAnchors.top
                bottom: root.osdAnchors.bottom
                left: root.osdAnchors.left
                right: root.osdAnchors.right
            }
            exclusionMode: (root.osdPosition === "bar" || !osdRoot.barVisibleOnScreen) ? ExclusionMode.Ignore : ExclusionMode.Normal
            exclusiveZone: 0
            margins {
                top: osdRoot.osdMargins.top
                bottom: osdRoot.osdMargins.bottom
                left: osdRoot.osdMargins.left
                right: osdRoot.osdMargins.right
            }

            implicitWidth: card.implicitWidth + 2 * Appearance.sizes.elevationMargin
            implicitHeight: card.implicitHeight + 2 * Appearance.sizes.elevationMargin
            visible: osdLoader.active
            mask: Region { item: card }

            StyledRectangularShadow {
                target: card
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                radius: Appearance.rounding.popupRounding
                color: MonitorThemes.shellColorForItem(osdRoot, "colLayer1", Appearance.colors.colBackgroundSurfaceContainer)
                implicitWidth: contentColumn.implicitWidth + 28
                implicitHeight: contentColumn.implicitHeight + 20

                // Staying inside the card resets the hide timer, same as
                // hovering the shared OSD system does for other indicators -
                // just without that one's dismiss-on-hover, since here
                // hovering is how you get to the slider at all.
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) hideTimer.stop()
                        else if (!volumeSlider.pressed) hideTimer.restart()
                    }
                }

                ColumnLayout {
                    id: contentColumn
                    anchors.centerIn: parent
                    spacing: 8

                    RowLayout {
                        spacing: 8

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: MonitorThemes.shellColorForItem(osdRoot, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "cable"
                                iconSize: 20
                                color: MonitorThemes.shellColorForItem(osdRoot, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
                            }
                        }

                        ColumnLayout {
                            spacing: 0

                            StyledText {
                                text: Translation.tr("Output")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: MonitorThemes.shellColorForItem(osdRoot, "colSubtext", Appearance.colors.colSubtext)
                            }
                            StyledText {
                                text: Dx5iiBridge.outputTypeName.length > 0 ? Dx5iiBridge.outputTypeName : "--"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: MonitorThemes.shellColorForItem(osdRoot, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            enabled: AudioBridgeRouter.activeBridge.relayConnected
                            onClicked: AudioBridgeRouter.toggleMute()

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: AudioBridgeRouter.activeBridge.isMuted ? "volume_off" : "volume_up"
                                iconSize: 18
                                color: MonitorThemes.shellColorForItem(osdRoot, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                        }

                        ThrottledVolumeSlider {
                            id: volumeSlider
                            Layout.preferredWidth: 160
                            bridge: AudioBridgeRouter.activeBridge
                            onUserInteracted: hideTimer.stop()
                            onPressedChanged: {
                                if (!pressed) hideTimer.restart()
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: 34
                            text: AudioBridgeRouter.activeBridge.hasVolume ? `${AudioBridgeRouter.activeBridge.volumePercent}%` : "--"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: MonitorThemes.shellColorForItem(osdRoot, "colOnLayer1", Appearance.colors.colOnLayer1)
                        }
                    }
                }
            }
        }
    }
}
