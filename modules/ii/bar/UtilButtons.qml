import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool borderless: Config.getBarSetting(root.monitorName, ["borderless"], Config.options.bar.borderless)
    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3

    readonly property var knownActionOrder: [
        "screenSnip",
        "colorPicker",
        "screenRecord",
        "recordingIndicator",
        "keyboardToggle",
        "wallpaperToggle",
        "micToggle",
        "darkModeToggle",
        "performanceProfileToggle",
        "caffeineToggle"
    ]
    readonly property var configuredActionOrder: Config.getBarSetting(root.monitorName, ["utilButtons", "order"], Config.options.bar.utilButtons.order)

    function toArray(value) {
        if (Array.isArray(value)) return value.slice()
        if (value === undefined || value === null) return []
        if (typeof value.length === "number") {
            let out = []
            for (let i = 0; i < value.length; i++) out.push(value[i])
            return out
        }
        return []
    }

    readonly property var effectiveActionOrder: {
        const configured = root.toArray(configuredActionOrder)
        const filteredConfigured = configured.filter(actionId => knownActionOrder.includes(actionId))
        if (filteredConfigured.length > 0) {
            return filteredConfigured
        }

        // Legacy fallback for existing configs without utilButtons.order.
        let legacy = []
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showScreenSnip"], Config.options.bar.utilButtons.showScreenSnip)) legacy.push("screenSnip")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showColorPicker"], Config.options.bar.utilButtons.showColorPicker)) legacy.push("colorPicker")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showScreenRecord"], Config.options.bar.utilButtons.showScreenRecord)) legacy.push("screenRecord")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showScreenRecordingIndicator"], Config.options.bar.utilButtons.showScreenRecordingIndicator)) legacy.push("recordingIndicator")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showKeyboardToggle"], Config.options.bar.utilButtons.showKeyboardToggle)) legacy.push("keyboardToggle")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showWallpaperToggle"], Config.options.bar.utilButtons.showWallpaperToggle)) legacy.push("wallpaperToggle")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showMicToggle"], Config.options.bar.utilButtons.showMicToggle)) legacy.push("micToggle")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showDarkModeToggle"], Config.options.bar.utilButtons.showDarkModeToggle)) legacy.push("darkModeToggle")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showPerformanceProfileToggle"], Config.options.bar.utilButtons.showPerformanceProfileToggle)) legacy.push("performanceProfileToggle")
        if (Config.getBarSetting(root.monitorName, ["utilButtons", "showCaffeineToggle"], Config.options.bar.utilButtons.showCaffeineToggle)) legacy.push("caffeineToggle")
        return legacy
    }

    function componentForAction(actionId) {
        switch (actionId) {
            case "screenSnip":
                return screenSnipM3
            case "colorPicker":
                return colorPickerM3
            case "screenRecord":
                return screenRecordM3
            case "recordingIndicator":
                return recordingIndicatorM3
            case "keyboardToggle":
                return keyboardM3
            case "wallpaperToggle":
                return wallpaperM3
            case "micToggle":
                return micM3
            case "darkModeToggle":
                return darkModeM3
            case "performanceProfileToggle":
                return perfM3
            case "caffeineToggle":
                return caffeineM3
            default:
                return null
        }
    }

    function isActionVisible(actionId) {
        if (actionId === "recordingIndicator") {
            return Persistent.states.record.enable
        }
        return true
    }

    implicitWidth: isMaterial && !root.vertical ? flow.implicitWidth : root.vertical ? Appearance.sizes.verticalBarWidth - 14 : flow.implicitWidth + 4
    implicitHeight: isMaterial && root.vertical ? flow.implicitHeight: isMaterial ? 32 : root.vertical ? flow.implicitHeight + 4 : Appearance.sizes.barHeight

    Flow {
        id: flow
        anchors.centerIn: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        spacing: isMaterial ? 2 : 4

        Repeater {
            model: root.effectiveActionOrder
            delegate: Loader {
                required property string modelData
                active: root.isActionVisible(modelData)
                visible: active
                sourceComponent: root.componentForAction(modelData)
            }
        }

        Repeater {
            model: CustomBarResources.definitions
            delegate: UtilButton {
                id: customResourceButton
                required property var modelData
                iconText: CustomBarResources.isRunning(modelData.id) ? (modelData.iconOn || "check_circle") : (modelData.iconOff || "circle")
                isActive: CustomBarResources.isRunning(modelData.id)
                onClicked: CustomBarResources.toggle(modelData.id)
                StyledToolTip {
                    extraVisibleCondition: customResourceButton.hovered
                    text: modelData.name || Translation.tr("Custom resource")
                }
            }
        }

        Component {
            id: screenSnipM3
            UtilButton {
                iconText: "screenshot_region"
                onClicked: Quickshell.execDetached(["qs", "-n", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"])
            }
        }

        Component {
            id: legacyScreenSnip
            CircleUtilButton {
                onClicked: Quickshell.execDetached(["qs", "-n", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1; text: "screenshot_region"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                }
            }
        }

        Component {
            id: colorPickerM3
            UtilButton {
                iconText: "colorize"
                onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
            }
        }
        Component {
            id: legacyColorPicker
            CircleUtilButton {
                onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1; text: "colorize"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                }
            }
        }

        Component {
            id: legacyScreenRecord
            Item {
                id: recordingItem
                implicitWidth: btn.implicitWidth + timerRevealer.implicitWidth
                implicitHeight: btn.implicitHeight

                property bool isRecording: Persistent.states.record.enable
                property int elapsedSeconds: 0

                onIsRecordingChanged: {
                    if (!isRecording) elapsedSeconds = 0
                }

                function formatTime(s) {
                    return Math.floor(s / 60).toString().padStart(2, '0') + ":" + (s % 60).toString().padStart(2, '0')
                }

                Timer {
                    interval: 1000
                    repeat: true
                    running: recordingItem.isRecording
                    onTriggered: recordingItem.elapsedSeconds++
                }

                CircleUtilButton {
                    id: btn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    colBackground: recordingItem.isRecording ? MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : "transparent"
                    buttonRadius: recordingItem.isRecording ? Appearance.rounding.normal : implicitHeight / 2
                    onClicked: Quickshell.execDetached([Directories.recordScriptPath])

                    Behavior on colBackground { ColorAnimation { duration: 200 } }
                    Behavior on buttonRadius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    MaterialSymbol {
                        horizontalAlignment: Qt.AlignHCenter
                        fill: 1
                        text: recordingItem.isRecording ? "stop_circle" : "screen_record"
                        iconSize: Appearance.font.pixelSize.large
                        color: recordingItem.isRecording ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                Revealer {
                    id: timerRevealer
                    anchors.left: btn.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: btn.verticalCenter
                    reveal: recordingItem.isRecording && !root.vertical

                    StyledText {
                        width: implicitWidth
                        text: recordingItem.formatTime(recordingItem.elapsedSeconds)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.features: { "tnum": 1 }
                        font.letterSpacing: -0.3
                        color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                        rightPadding: 8
                        Component.onCompleted: width = implicitWidth
                    }
                }
            }
        }

        Component {
            id: screenRecordM3
            UtilButton {
                iconText: Persistent.states.record.enable ? "stop_circle" : "screen_record"
                isActive: Persistent.states.record.enable
                onClicked: Quickshell.execDetached([Directories.recordScriptPath])
            }
        }

        Component {
            id: recordingIndicatorM3
            UtilButton {
                iconText: "radio_button_checked"
                isActive: true
                onClicked: Quickshell.execDetached([Directories.recordScriptPath])
            }
        }

        Component {
            id: recordingIndicatorLegacy
            CircleUtilButton {
                colBackground: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
                onClicked: Quickshell.execDetached([Directories.recordScriptPath])

                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "radio_button_checked"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                }
            }
        }
        Component {
            id: keyboardM3
            UtilButton {
                iconText: "keyboard"
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
            }
        }
        Component {
            id: legacyKeyboard
            CircleUtilButton {
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0; text: "keyboard"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                }
            }
        }
        Component {
            id: wallpaperM3
            UtilButton {
                iconText: "imagesmode"
                onClicked: GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
            }
        }
        Component {
            id: legacyWallpaper
            CircleUtilButton {
                onClicked: GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0; text: "imagesmode"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                }
            }
        }
        Component {
            id: micM3
            UtilButton {
                iconText: Pipewire.defaultAudioSource?.audio?.muted ? "mic_off" : "mic"
                onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"])
            }
        }
        Component {
            id: legacyMic
            CircleUtilButton {
                onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: Pipewire.defaultAudioSource?.audio?.muted ? "mic_off" : "mic"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                }
            }
        }
        Component {
            id: darkModeM3
            UtilButton {
                iconText: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                onClicked: (e) => {
                    if (Appearance.m3colors.darkmode)
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode light --noswitch`])
                    else
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode dark --noswitch`])
                }
            }
        }
        Component {
            id: legacyDarkMode
            CircleUtilButton {
                onClicked: (e) => {
                    if (Appearance.m3colors.darkmode)
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode light --noswitch`])
                    else
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode dark --noswitch`])
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                }
            }
        }
        Component {
            id: perfM3
            UtilButton {
                iconText: switch(PowerProfiles.profile) {
                    case PowerProfile.PowerSaver: return "energy_savings_leaf"
                    case PowerProfile.Balanced: return "airwave"
                    case PowerProfile.Performance: return "local_fire_department"
                }
                onClicked: (e) => {
                    if (PowerProfiles.hasPerformanceProfile) {
                        switch(PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
                        }
                    } else {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                }
            }
        }

        Component {
            id: caffeineM3
            UtilButton {
                id: caffeineButton
                iconText: "coffee"
                isActive: Idle.inhibit
                onClicked: Idle.toggleInhibit()
                StyledToolTip {
                    extraVisibleCondition: caffeineButton.hovered
                    text: Translation.tr("Caffeine / Prevent idle suspend")
                }
            }
        }
        Component {
            id: legacyPerf
            CircleUtilButton {
                onClicked: (e) => {
                    if (PowerProfiles.hasPerformanceProfile) {
                        switch(PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
                        }
                    } else {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: switch(PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: return "energy_savings_leaf"
                        case PowerProfile.Balanced: return "airwave"
                        case PowerProfile.Performance: return "local_fire_department"
                    }
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer2", Appearance.colors.colOnLayer2)
                }
            }
        }
    }
}
