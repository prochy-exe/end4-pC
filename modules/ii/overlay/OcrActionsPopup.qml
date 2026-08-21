import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

Scope {
    id: root

    readonly property string ocrText: `${GlobalStates.lastOcrText ?? ""}`
    readonly property bool hasText: ocrText.trim().length > 0
    property real nowMs: Date.now()
    readonly property bool popupFresh: (root.nowMs - (GlobalStates.lastOcrCapturedMs ?? 0)) < 10000

    function screenByName(name) {
        if (!name || name.length === 0) return null
        return Quickshell.screens.find(s => s.name === name) ?? null
    }

    function closePopup() {
        GlobalStates.ocrActionsPopupOpen = false
    }

    function openPopup() {
        if (!root.hasText || !root.popupFresh) {
            root.closePopup()
            return
        }
        autoHideTimer.restart()
    }

    Component.onCompleted: {
        // Always start closed after shell restart/reload; only OCR success should open it.
        root.closePopup()
    }

    Connections {
        target: GlobalStates
        function onOcrActionsPopupOpenChanged() {
            if (GlobalStates.ocrActionsPopupOpen)
                root.openPopup()
            else
                autoHideTimer.stop()
        }
    }

    PanelWindow {
        id: popupWindow
        visible: GlobalStates.ocrActionsPopupOpen && root.hasText && root.popupFresh
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:ocrActionsPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        screen: {
            const focused = root.screenByName(Hyprland.focusedMonitor?.name ?? "")
            if (focused) return focused
            return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Column {
            id: popupColumn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 38
            spacing: 8

            Toolbar {
                id: actionToolbar
                enableShadow: true
                padding: 6
                radius: height / 2
                colBackground: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)

                ToolbarPairedFab {
                    iconText: "content_copy"
                    enableShadow: false
                    onClicked: {
                        Quickshell.clipboardText = root.ocrText
                        root.closePopup()
                    }
                    StyledToolTip { text: Translation.tr("Copy") }
                }

                ToolbarPairedFab {
                    iconText: "translate"
                    enableShadow: false
                    onClicked: {
                        GlobalStates.sidebarLeftRequestedTab = "translator"
                        GlobalStates.sidebarLeftTranslatorPrefill = root.ocrText
                        GlobalStates.sidebarLeftTranslatorPrefillNonce = (GlobalStates.sidebarLeftTranslatorPrefillNonce ?? 0) + 1
                        root.closePopup()
                    }
                    StyledToolTip { text: Translation.tr("Translate") }
                }

                ToolbarPairedFab {
                    iconText: "assignment_return"
                    enableShadow: false
                    onClicked: {
                        Cliphist.pasteText(root.ocrText)
                        root.closePopup()
                    }
                    StyledToolTip { text: Translation.tr("Replace") }
                }

                ToolbarPairedFab {
                    iconText: "close"
                    enableShadow: false
                    onClicked: root.closePopup()
                    StyledToolTip { text: Translation.tr("Dismiss") }
                }
            }
        }
    }

    Timer {
        id: freshnessTimer
        interval: 250
        repeat: true
        running: popupWindow.visible
        onTriggered: root.nowMs = Date.now()
    }

    Timer {
        id: autoHideTimer
        interval: 6000
        repeat: false
        onTriggered: root.closePopup()
    }
}
