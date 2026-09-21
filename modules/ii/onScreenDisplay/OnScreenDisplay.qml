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
    // of the bar, "custom" is anchored top+left, or bottom+left if
    // osdCustomAnchor is "bottom", with free positioning expressed through
    // pixel margins alone. PopupPlacement.qml is the single source of truth
    // for this (also used by the popup editor/preview so they can't
    // silently drift from what actually renders); "true" here (unlike the
    // ticker) means the OSD's "bar" preset also hugs a vertical bar's edge,
    // not just a horizontal one.
    readonly property string osdPosition: Config.options.osd.position
    readonly property bool osdIsCustom: root.osdPosition === "custom"
    readonly property real osdEdgeGap: Appearance.sizes.hyprlandGapsOut
    readonly property string osdCustomAnchor: Config.options.osd.customAnchor
    readonly property var osdAnchors: PopupPlacement.barAnchors(root.osdPosition, true, true, root.osdCustomAnchor)

    property string currentIndicator: "volume"
    onCurrentIndicatorChanged: GlobalStates.osdIndicatorType = currentIndicator
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
                Config.options.osd.customX, Config.options.osd.customY,
                osdRoot.screen?.width ?? 0, osdRoot.screen?.height ?? 0,
                root.osdCustomAnchor, osdRoot.implicitWidth, osdRoot.implicitHeight,
                PopupPlacement.usableRectFor(osdRoot.screen))

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
            // "custom" ALSO ignores it, since a freely-dragged position
            // needs pixel-exact placement - letting the compositor silently
            // shift it away from the bar's reserved zone would put it
            // dozens of px from wherever it was actually dropped.
            exclusionMode: (root.osdPosition === "bar" || root.osdIsCustom || !osdRoot.barVisibleOnScreen)
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
            visible: osdLoader.active && !GlobalStates.dynamicIslandEnabled

            // Real size -> popup editor, so its dot sits on the real OSD
            // rather than on PopupPlacement's static estimate of it. See
            // PopupPlacement.reportFootprint() for why the estimate being a
            // little off turns into a permanently offset drag target.
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
                                radius: Appearance.rounding.normal

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
    CompositorGlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    CompositorGlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }
}
