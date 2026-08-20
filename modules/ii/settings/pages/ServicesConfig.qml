import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    //This was intended to go into the results more deeply but in the end I didn't like it but I left it just in case lol
    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "neurology"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("AI")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("System prompt")
                text: Config.options.ai.systemPrompt
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Qt.callLater(() => {
                        Config.options.ai.systemPrompt = text;
                    });
                }
            }
        }

        ContentSection {
            icon: "cell_tower"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Networking")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("User agent (for services that require it)")
                text: Config.options.networking.userAgent
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.networking.userAgent = text;
                }
            }
        }

        ContentSection {
            icon: "music_note"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Media")

            // "Super+M menu elements" moved to Interface (Settings > Interface
            // > Super+M Menu) - it's UI-surface config, not a service.
            MediaPriorityList {}
        }

        ContentSection {
            icon: "graphic_eq"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Audio analysis")

            GroupedList {
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "bolt"
                    text: Translation.tr("Keep audio analysis running")
                    checked: Config.options.background.effects.audio.autoStart
                    onClicked: Config.options.background.effects.audio.autoStart = !Config.options.background.effects.audio.autoStart
                }
                ConfigSlider {
                    text: Translation.tr("Beat sensitivity")
                    buttonIcon: "sensors"
                    usePercentTooltip: false
                    value: Config.options.background.effects.audio.beatSensitivity
                    from: 1.05
                    to: 3.0
                    onValueChanged: Config.options.background.effects.audio.beatSensitivity = value
                }
                ConfigSlider {
                    text: Translation.tr("Beat floor")
                    buttonIcon: "vertical_align_bottom"
                    value: Config.options.background.effects.audio.beatFloor
                    from: 0
                    to: 0.6
                    onValueChanged: Config.options.background.effects.audio.beatFloor = value
                }
                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Beat decay (ms)")
                    value: Config.options.background.effects.audio.beatDecay
                    from: 20
                    to: 1000
                    stepSize: 10
                    onValueChanged: Config.options.background.effects.audio.beatDecay = value
                }
                ConfigSpinBox {
                    icon: "hourglass_bottom"
                    text: Translation.tr("Minimum beat gap (ms)")
                    value: Config.options.background.effects.audio.beatMinInterval
                    from: 20
                    to: 1000
                    stepSize: 10
                    onValueChanged: Config.options.background.effects.audio.beatMinInterval = value
                }
            }
            GroupedList {
                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Update rate (Hz)")
                    value: Config.options.background.effects.audio.updateRate
                    from: 15
                    to: 240
                    stepSize: 5
                    onValueChanged: Config.options.background.effects.audio.updateRate = value
                }
                ConfigSpinBox {
                    icon: "equalizer"
                    text: Translation.tr("Spectrum bars")
                    value: Config.options.background.effects.audio.bars
                    from: 8
                    to: 256
                    stepSize: 2
                    onValueChanged: Config.options.background.effects.audio.bars = value
                }
                ConfigSpinBox {
                    icon: "graphic_eq"
                    text: Translation.tr("Lowest frequency (Hz)")
                    value: Config.options.background.effects.audio.rangeLow
                    from: 20
                    to: 500
                    stepSize: 10
                    onValueChanged: Config.options.background.effects.audio.rangeLow = value
                }
                ConfigSpinBox {
                    icon: "graphic_eq"
                    text: Translation.tr("Highest frequency (Hz)")
                    value: Config.options.background.effects.audio.rangeHigh
                    from: 1000
                    to: 22000
                    stepSize: 500
                    onValueChanged: Config.options.background.effects.audio.rangeHigh = value
                }
                ConfigSlider {
                    text: Translation.tr("Spectrum fall speed")
                    buttonIcon: "trending_down"
                    value: Config.options.background.effects.audio.barDecay
                    from: 0.002
                    to: 0.2
                    onValueChanged: Config.options.background.effects.audio.barDecay = value
                }
                ConfigSlider {
                    text: Translation.tr("Auto gain release")
                    buttonIcon: "tune"
                    usePercentTooltip: false
                    value: Config.options.background.effects.audio.gainRelease
                    from: 0.99
                    to: 0.99999
                    onValueChanged: Config.options.background.effects.audio.gainRelease = value
                }
            }
        }

        ContentSection {
            icon: "music_cast"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Music Recognition")

            GroupedList {
                ConfigSpinBox {
                    icon: "timer_off"
                    text: Translation.tr("Total duration timeout (s)")
                    value: Config.options.musicRecognition.timeout
                    from: 10
                    to: 100
                    stepSize: 2
                    onValueChanged: {
                        Config.options.musicRecognition.timeout = value;
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (s)")
                    value: Config.options.musicRecognition.interval
                    from: 2
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.musicRecognition.interval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "screen_record"
            shape: MaterialShape.Shape.Arch
            title: Translation.tr("Screen Recording")

            GroupedList {
                ConfigSlider {
                    id: recordingFrameRateSlider
                    Layout.fillWidth: true
                    buttonIcon: "videocam"
                    text: Translation.tr("Recording frame rate")
                    textWidth: 180
                    usePercentTooltip: false
                    value: Config.options.screenRecord.frameRate
                    from: 10
                    to: 144
                    stepSize: 1
                    stopIndicatorValues: [30, 60, 90, 120]
                    onValueChanged: {
                        if (recordingFrameRateSlider.completed)
                            Config.options.screenRecord.frameRate = value;
                    }

                    property bool completed: false
                    Component.onCompleted: Qt.callLater(() => completed = true)
                }
            }

            ContentSubsection {
                title: Translation.tr("Input overlay")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "keyboard"
                        text: Translation.tr("Show input overlay while recording")
                        checked: Config.options.screenRecord.showInputOverlay
                        onCheckedChanged: Config.options.screenRecord.showInputOverlay = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "mouse"
                        text: Translation.tr("Show mouse button input")
                        enabled: Config.options.screenRecord.showInputOverlay
                            && !Config.options.screenRecord.onlyShowInputChords
                        checked: Config.options.screenRecord.showMouseInput
                        onCheckedChanged: Config.options.screenRecord.showMouseInput = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "keyboard_command_key"
                        text: Translation.tr("Only show key combinations")
                        enabled: Config.options.screenRecord.showInputOverlay
                        checked: Config.options.screenRecord.onlyShowInputChords
                        onCheckedChanged: Config.options.screenRecord.onlyShowInputChords = checked
                    }

                    ConfigSlider {
                        id: inputOverlayOffsetSlider
                        Layout.fillWidth: true
                        enabled: Config.options.screenRecord.showInputOverlay
                        buttonIcon: "vertical_align_center"
                        text: Translation.tr("Vertical offset")
                        textWidth: 180
                        usePercentTooltip: false
                        value: Config.options.screenRecord.inputOverlayVerticalOffset
                        from: 0
                        to: 200
                        stepSize: 1
                        onValueChanged: {
                            if (inputOverlayOffsetSlider.completed) {
                                Config.options.screenRecord.inputOverlayVerticalOffset = value
                                GlobalStates.recordingInputOverlayPreview = true
                                inputOverlayPreviewTimer.restart()
                            }
                        }

                        property bool completed: false
                        Component.onCompleted: Qt.callLater(() => completed = true)
                        Component.onDestruction: GlobalStates.recordingInputOverlayPreview = false

                        Timer {
                            id: inputOverlayPreviewTimer
                            interval: 450
                            repeat: false
                            onTriggered: GlobalStates.recordingInputOverlayPreview = false
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "file_open"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Save paths")

            GroupedList {
                ConfigTextArea {
                    id: videoRecordPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "video_file"
                    text: Translation.tr("Video Recording Path")
                    value: Config.options.screenRecord.savePath
                    onValueChanged: {
                        videoRecordPathDebounceTimer.restart();
                    }

                    Timer {
                        id: videoRecordPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenRecord.savePath = videoRecordPathField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: screenshotPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "screenshot_monitor"
                    text: Translation.tr("Screenshot Path (leave empty to just copy)")
                    value: Config.options.screenSnip.savePath
                    onValueChanged: {
                        screenshotPathDebounceTimer.restart();
                    }

                    Timer {
                        id: screenshotPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenSnip.savePath = screenshotPathField.value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "search"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Search")

            GroupedList {
                ConfigSwitch {
                    text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
                    checked: Config.options.search.sloppy
                    onCheckedChanged: {
                        Config.options.search.sloppy = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Clipboard history")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "movie"
                        text: Translation.tr("Process video entries (thumbnail + metadata)")
                        checked: Config.options.search.clipboardVideoProcessing
                        onCheckedChanged: {
                            Config.options.search.clipboardVideoProcessing = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "auto_fix_high"
                        text: Translation.tr("Enable Smart Paste transforms")
                        checked: Config.options.search.clipboardSmartPaste.enable
                        onCheckedChanged: {
                            Config.options.search.clipboardSmartPaste.enable = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "content_paste_go"
                        text: Translation.tr("Auto rewrite clipboard when copying links")
                        checked: Config.options.search.clipboardSmartPaste.autoRewriteClipboardOnCopy
                        enabled: Config.options.search.clipboardSmartPaste.enable
                        onCheckedChanged: {
                            Config.options.search.clipboardSmartPaste.autoRewriteClipboardOnCopy = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "link_off"
                        text: Translation.tr("Strip tracking parameters from URLs")
                        checked: Config.options.search.clipboardSmartPaste.stripTrackingParams
                        enabled: Config.options.search.clipboardSmartPaste.enable
                        onCheckedChanged: {
                            Config.options.search.clipboardSmartPaste.stripTrackingParams = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "dynamic_feed"
                        text: Translation.tr("Rewrite social links for better embeds")
                        checked: Config.options.search.clipboardSmartPaste.rewriteSocialEmbeds
                        enabled: Config.options.search.clipboardSmartPaste.enable
                        onCheckedChanged: {
                            Config.options.search.clipboardSmartPaste.rewriteSocialEmbeds = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "alternate_email"
                        text: Translation.tr("Copy X/Twitter links to a custom domain")
                        checked: Config.options.search.clipboardSmartPaste.rewriteXTwitter
                        enabled: Config.options.search.clipboardSmartPaste.enable
                            && Config.options.search.clipboardSmartPaste.rewriteSocialEmbeds
                        onCheckedChanged: {
                            Config.options.search.clipboardSmartPaste.rewriteXTwitter = checked;
                        }
                    }

                    ConfigTextArea {
                        Layout.fillWidth: true
                        fieldWidth: 230
                        buttonIcon: "link"
                        text: Translation.tr("X/Twitter replacement domain")
                        value: Config.options.search.clipboardSmartPaste.xTwitterReplacementDomain
                        enabled: Config.options.search.clipboardSmartPaste.enable
                            && Config.options.search.clipboardSmartPaste.rewriteSocialEmbeds
                            && Config.options.search.clipboardSmartPaste.rewriteXTwitter
                        onValueChanged: {
                            Config.options.search.clipboardSmartPaste.xTwitterReplacementDomain = value;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "photo_camera"
                        text: Translation.tr("Copy Instagram links to a custom domain")
                        checked: Config.options.search.clipboardSmartPaste.rewriteInstagram
                        enabled: Config.options.search.clipboardSmartPaste.enable
                            && Config.options.search.clipboardSmartPaste.rewriteSocialEmbeds
                        onCheckedChanged: {
                            Config.options.search.clipboardSmartPaste.rewriteInstagram = checked;
                        }
                    }

                    ConfigTextArea {
                        Layout.fillWidth: true
                        fieldWidth: 230
                        buttonIcon: "link"
                        text: Translation.tr("Instagram replacement domain")
                        value: Config.options.search.clipboardSmartPaste.instagramReplacementDomain
                        enabled: Config.options.search.clipboardSmartPaste.enable
                            && Config.options.search.clipboardSmartPaste.rewriteSocialEmbeds
                            && Config.options.search.clipboardSmartPaste.rewriteInstagram
                        onValueChanged: {
                            Config.options.search.clipboardSmartPaste.instagramReplacementDomain = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Bitwarden")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "visibility_lock"
                        text: Translation.tr("Dismiss Win+B menu after interacting with an item")
                        checked: Config.options.search.bitwardenDismissOnInteract
                        onCheckedChanged: {
                            Config.options.search.bitwardenDismissOnInteract = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "timer"
                        text: Translation.tr("Show TOTP seconds remaining in actions")
                        checked: Config.options.search.bitwardenTotp.showCountdown
                        onCheckedChanged: {
                            Config.options.search.bitwardenTotp.showCountdown = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "content_paste_off"
                        text: Translation.tr("Auto-clear copied TOTP from clipboard")
                        checked: Config.options.search.bitwardenTotp.autoClearClipboard
                        onCheckedChanged: {
                            Config.options.search.bitwardenTotp.autoClearClipboard = checked;
                        }
                    }

                    ConfigSpinBox {
                        icon: "timer_off"
                        text: Translation.tr("Auto-clear delay (s)")
                        enabled: Config.options.search.bitwardenTotp.autoClearClipboard
                        value: Config.options.search.bitwardenTotp.autoClearSeconds
                        from: 1
                        to: 120
                        stepSize: 1
                        onValueChanged: {
                            Config.options.search.bitwardenTotp.autoClearSeconds = value;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "shield_lock"
                        text: Translation.tr("Do not overwrite clipboard if recently copied")
                        checked: Config.options.search.bitwardenTotp.protectRecentClipboard
                        onCheckedChanged: {
                            Config.options.search.bitwardenTotp.protectRecentClipboard = checked;
                        }
                    }

                    ConfigSpinBox {
                        icon: "av_timer"
                        text: Translation.tr("Recent-copy protection window (s)")
                        enabled: Config.options.search.bitwardenTotp.protectRecentClipboard
                        value: Config.options.search.bitwardenTotp.protectRecentClipboardSeconds
                        from: 1
                        to: 60
                        stepSize: 1
                        onValueChanged: {
                            Config.options.search.bitwardenTotp.protectRecentClipboardSeconds = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Prefixes")

                GroupedList {
                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "bolt"
                            fieldWidth: 100
                            text: Translation.tr("Action")
                            value: Config.options.search.prefix.action
                            onValueChanged: {
                                Config.options.search.prefix.action = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "content_paste"
                            fieldWidth: 100
                            text: Translation.tr("Clipboard")
                            value: Config.options.search.prefix.clipboard
                            onValueChanged: {
                                Config.options.search.prefix.clipboard = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "mood"
                            fieldWidth: 100
                            text: Translation.tr("Emojis")
                            value: Config.options.search.prefix.emojis
                            onValueChanged: {
                                Config.options.search.prefix.emojis = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "emoji_symbols"
                            fieldWidth: 100
                            text: Translation.tr("Icons")
                            value: Config.options.search.prefix.symbols
                            onValueChanged: {
                                Config.options.search.prefix.symbols = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "terminal"
                            fieldWidth: 100
                            text: Translation.tr("Shell command")
                            value: Config.options.search.prefix.shellCommand
                            onValueChanged: {
                                Config.options.search.prefix.shellCommand = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            fieldWidth: 100
                            buttonIcon: "travel_explore"
                            text: Translation.tr("Web search")
                            value: Config.options.search.prefix.webSearch
                            onValueChanged: {
                                Config.options.search.prefix.webSearch = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "apps"
                            fieldWidth: 100
                            text: Translation.tr("Apps")
                            value: Config.options.search.prefix.app
                            onValueChanged: {
                                Config.options.search.prefix.app = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "password"
                            fieldWidth: 100
                            text: Translation.tr("Bitwarden")
                            value: Config.options.search.prefix.bitwarden
                            onValueChanged: {
                                Config.options.search.prefix.bitwarden = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "keyboard_command_key"
                            fieldWidth: 100
                            text: Translation.tr("Keybinds")
                            value: Config.options.search.prefix.keybinds
                            onValueChanged: {
                                Config.options.search.prefix.keybinds = value;
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Web search")

                GroupedList {
                    ConfigTextArea {
                        id: baseUrlField
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "travel_explore"
                        text: Translation.tr("Base URL")
                        value: Config.options.search.engineBaseUrl
                        onValueChanged: {
                            baseUrlDebounceTimer.restart();
                        }

                        Timer {
                            id: baseUrlDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.search.engineBaseUrl = baseUrlField.value;
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "deployed_code_update"
            title: Translation.tr("System updates (Arch only)")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "update"
                    text: Translation.tr("Enable update checks")
                    checked: Config.options.updates.enableCheck
                    onCheckedChanged: {
                        Config.options.updates.enableCheck = checked;
                    }
                }

                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Check interval (mins)")
                    value: Config.options.updates.checkInterval
                    from: 60
                    to: 1440
                    stepSize: 60
                    onValueChanged: {
                        Config.options.updates.checkInterval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "weather_mix"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Weather")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "assistant_navigation"
                    text: Translation.tr("Enable GPS based location")
                    checked: Config.options.bar.weather.enableGPS
                    onCheckedChanged: {
                        Config.options.bar.weather.enableGPS = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "thermometer"
                    text: Translation.tr("Fahrenheit unit")
                    checked: Config.options.bar.weather.useUSCS
                    onCheckedChanged: {
                        Config.options.bar.weather.useUSCS = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (m)")
                    value: Config.options.bar.weather.fetchInterval
                    from: 5
                    to: 50
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.weather.fetchInterval = value;
                    }
                }
                ConfigTextArea {
                    id: cityField
                    Layout.fillWidth: true
                    buttonIcon: "location_city"
                    text: Translation.tr("City name")
                    value: Config.options.bar.weather.city
                    onValueChanged: cityDebounceTimer.restart()

                    Timer {
                        id: cityDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: Config.options.bar.weather.city = cityField.value
                    }
                }
            }
        }
        WorldMap {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
        }
    }
}
