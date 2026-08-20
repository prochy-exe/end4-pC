pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property string lastKeyInput: ""
    property string lastMouseInput: ""
    property string lastKeyDisplay: ""
    property string lastMouseDisplay: ""
    readonly property bool active: Persistent.states.record.enable && Config.options.screenRecord.showInputOverlay
    readonly property bool onlyShowChords: Config.options.screenRecord.onlyShowInputChords
    readonly property bool mouseInputEnabled: Config.options.screenRecord.showMouseInput && !root.onlyShowChords
    readonly property bool previewActive: GlobalStates.recordingInputOverlayPreview

    function showInput(input) {
        if (!root.active || input.length === 0)
            return
        if (root.onlyShowChords && !input.includes(" + "))
            return
        if (input.startsWith("Mouse ")) {
            if (!root.mouseInputEnabled)
                return
            root.lastMouseInput = input
            root.lastMouseDisplay = input
            hideMouseTimer.restart()
        } else {
            root.lastKeyInput = input
            root.lastKeyDisplay = input
            hideKeyTimer.restart()
        }
    }

    Process {
        id: inputEvents
        command: ["bash", Directories.recordingInputEventsScriptPath]
        running: root.active
        stdout: SplitParser {
            onRead: line => root.showInput(line.trim())
        }
    }

    Timer {
        id: hideKeyTimer
        interval: 1200
        onTriggered: root.lastKeyInput = ""
    }

    Timer {
        id: hideMouseTimer
        interval: 900
        onTriggered: root.lastMouseInput = ""
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: overlayWindow
            required property var modelData

            screen: modelData
            visible: root.active || root.previewActive
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:recording-input-overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // This is a visual-only full-screen layer. An empty mask keeps
            // both the card and its transparent area click-through.
            mask: Region { item: null }
            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            readonly property bool barVertical: Config.getBarSetting(modelData.name, ["vertical"], Config.options.bar.vertical)
            readonly property bool barBottom: Config.getBarSetting(modelData.name, ["bottom"], Config.options.bar.bottom)
            readonly property real bottomOffset: 32 + Config.options.screenRecord.inputOverlayVerticalOffset
                + (!barVertical && barBottom ? Appearance.sizes.barHeight : 0)

            Item {
                anchors.fill: parent

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: overlayWindow.bottomOffset
                    spacing: 10

                    Rectangle {
                        id: keyCard
                        visible: opacity > 0
                        implicitWidth: keyRow.implicitWidth + 32
                        implicitHeight: 48
                        radius: Appearance.rounding.full
                        color: Appearance.m3colors.m3surfaceContainerHighest
                        border.width: 1
                        border.color: Appearance.colors.colPrimary
                        opacity: root.lastKeyInput.length > 0 || root.previewActive ? 1 : 0
                        scale: root.lastKeyInput.length > 0 || root.previewActive ? 1 : 0.92

                        StyledRectangularShadow {
                            target: keyCard
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }

                        RowLayout {
                            id: keyRow
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: height / 2
                                color: Appearance.colors.colPrimaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "keyboard"
                                    iconSize: 18
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                            StyledText {
                                text: root.lastKeyInput.length > 0 ? root.lastKeyDisplay : "Ctrl + Shift + C"
                                color: Appearance.m3colors.m3onSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        id: mouseCard
                        visible: opacity > 0
                        implicitWidth: mouseRow.implicitWidth + 26
                        implicitHeight: 48
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        border.width: 1
                        border.color: Appearance.colors.colPrimary
                        opacity: root.mouseInputEnabled && (root.lastMouseInput.length > 0 || root.previewActive) ? 1 : 0
                        scale: root.mouseInputEnabled && (root.lastMouseInput.length > 0 || root.previewActive) ? 1 : 0.92

                        StyledRectangularShadow {
                            target: mouseCard
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        RowLayout {
                            id: mouseRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "mouse"
                                iconSize: 21
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            StyledText {
                                text: root.lastMouseInput.length > 0 ? root.lastMouseDisplay : "Mouse 1"
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

            }
        }
    }
}
