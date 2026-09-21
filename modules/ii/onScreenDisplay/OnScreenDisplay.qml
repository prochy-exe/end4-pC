import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string protectionMessage: ""

    // Same preset/anchor scheme as the media ticker (MediaControls.qml) -
    // "bar" hugs whichever edge the bar is on (default, matches the OSD's
    // original hardcoded look), corner/edge/center presets are independent
    // of the bar. PopupPlacement.qml is the single source of truth for this
    // (also used by the preview so it can't silently drift from what
    // actually renders); "true" here (unlike the ticker) means the OSD's
    // "bar" preset also hugs a vertical bar's edge, not just a horizontal
    // one.
    readonly property string osdPosition: Config.options.osd.position
    // OsdValueIndicator's card sits inset by elevationMargin inside this
    // window (room for its own drop shadow - see OsdValueIndicator.qml), so
    // anchoring the WINDOW at a plain gapsOut margin would leave the visible
    // card sitting elevationMargin further from the screen edge than an
    // actual tiled window at the same gap. Subtracting it here cancels that
    // inset out, so the card's real edge lands exactly at gapsOut like a
    // window's does; the now-oversized window can spill past the screen
    // edge, which is harmless since it's transparent and only its shadow
    // occupies that extra space (a real window's shadow gets clipped by the
    // screen edge the same way).
    readonly property real osdEdgeGap: Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
    readonly property var osdAnchors: PopupPlacement.barAnchors(root.osdPosition, true, true)

    property string currentIndicator: "volume"
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "gamma",
            sourceUrl: "indicators/GammaIndicator.qml"
        },
    ]

    function triggerOsd() {
        GlobalStates.osdVolumeOpen = true;
        osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            root.protectionMessage = "";
            root.currentIndicator = "gamma";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    // Audio bridge (dx5ii/wamp) volume and output changes get their own
    // dedicated OSD (modules/ii/audioBridge/AudioBridgeOsd.qml), not this
    // shared one - that one needs to be draggable/interactive, which this
    // system's hover-to-dismiss MouseArea below would fight against, and
    // combining an output-change with the volume-change it often triggers
    // into one merged card isn't something this single-indicator-at-a-time
    // system does cleanly.

    Connections {
        // Listen to protection triggers
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Loader {
        id: osdLoader
        active: GlobalStates.osdVolumeOpen

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"
            screen: PopupPlacement.resolveScreen(Config.options.osd.monitorMode, Config.options.osd.monitorName)
            readonly property bool barVisibleOnScreen: PopupPlacement.barInfoFor(osdRoot.screen).present
            readonly property var osdMargins: PopupPlacement.barMargins(root.osdPosition, true, root.osdAnchors, root.osdEdgeGap,
                osdRoot.screen?.width ?? 0, osdRoot.screen?.height ?? 0,
                PopupPlacement.usableRectFor(osdRoot.screen),
                // Unlike the ticker/Super+M menu, the OSD isn't part of the
                // bar - it wants a real gap between itself and the bar, not
                // just enough margin to reach it.
                Appearance.sizes.hyprlandGapsOut)

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: root.osdAnchors.top
                bottom: root.osdAnchors.bottom
                left: root.osdAnchors.left
                right: root.osdAnchors.right
            }
            mask: Region {
                item: osdValuesWrapper
            }

            // See MediaControls.qml's tickerWindow.exclusionMode for why
            // this is conditional: "bar" hugs the bar with an already-exact
            // margin and shouldn't also be pushed by its exclusive zone;
            // named presets should respect it, matching NotificationPopup.qml.
            exclusionMode: (root.osdPosition === "bar" || !osdRoot.barVisibleOnScreen)
                ? ExclusionMode.Ignore : ExclusionMode.Normal
            exclusiveZone: 0
            margins {
                top: osdRoot.osdMargins.top
                bottom: osdRoot.osdMargins.bottom
                left: osdRoot.osdMargins.left
                right: osdRoot.osdMargins.right
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight
            visible: osdLoader.active

            // Real size -> preview canvas, so its marker sits on the real
            // OSD rather than on PopupPlacement's static estimate of it.
            function reportFootprint() {
                PopupPlacement.reportFootprint("osd", osdRoot.implicitWidth, osdRoot.implicitHeight)
            }
            onImplicitWidthChanged: osdRoot.reportFootprint()
            onImplicitHeightChanged: osdRoot.reportFootprint()
            Component.onCompleted: osdRoot.reportFootprint()

            ColumnLayout {
                id: columnLayout
                anchors.horizontalCenter: parent.horizontalCenter

                Item {
                    id: osdValuesWrapper
                    // Extra space for shadow
                    implicitHeight: contentColumnLayout.implicitHeight
                    implicitWidth: contentColumnLayout.implicitWidth
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: GlobalStates.osdVolumeOpen = false
                    }

                    Column {
                        id: contentColumnLayout
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        spacing: 0

                        Loader {
                            id: osdIndicatorLoader
                            source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl
                        }

                        Item {
                            id: protectionMessageWrapper
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitHeight: protectionMessageBackground.implicitHeight
                            implicitWidth: protectionMessageBackground.implicitWidth
                            // visible (not just opacity) so an inactive
                            // protection message doesn't leave invisible
                            // padding below the real slider - Column still
                            // counts a zero-opacity child's full height, and
                            // that extra padding was silently pulling the
                            // OSD's "center" custom-anchor mode down by
                            // ~25px from its real visual center (found by
                            // measuring a real screenshot against the new
                            // center-mode math - the math was exact, the
                            // window just had hidden content below it).
                            // No opacity Behavior exists here to fade
                            // through, so flipping visible has no animation
                            // to interrupt.
                            visible: root.protectionMessage !== ""
                            opacity: root.protectionMessage !== "" ? 1 : 0

                            StyledRectangularShadow {
                                target: protectionMessageBackground
                            }
                            Rectangle {
                                id: protectionMessageBackground
                                anchors.centerIn: parent
                                color: MonitorThemes.colorForItem(root, "error", Appearance.m3colors.m3error)
                                property real padding: 10
                                implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                                implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                                radius: Appearance.rounding.popupRounding

                                RowLayout {
                                    id: protectionMessageRowLayout
                                    anchors.centerIn: parent
                                    MaterialSymbol {
                                        id: protectionMessageIcon
                                        text: "dangerous"
                                        iconSize: Appearance.font.pixelSize.hugeass
                                        color: MonitorThemes.colorForItem(root, "on_error", Appearance.m3colors.m3onError)
                                    }
                                    StyledText {
                                        id: protectionMessageTextWidget
                                        horizontalAlignment: Text.AlignHCenter
                                        color: MonitorThemes.colorForItem(root, "on_error", Appearance.m3colors.m3onError)
                                        wrapMode: Text.Wrap
                                        text: root.protectionMessage
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }

        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }
}
