import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.wallpaperEffects

ContentPage {
    id: page
    forceWidth: true
    baseWidth: 680
    bottomContentPadding: 50

    property bool savePresetDialogOpen: false

    function goTo(term) {
        const needle = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                const child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(needle))
                    return child
            }
            for (let i = 0; i < rootItem.children.length; i++) {
                const child = findTarget(rootItem.children[i])
                if (child) return child
            }
            return null
        }

        const target = findTarget(mainLayout)
        if (target) {
            const pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y)
        }
    }

    component AudioTriggerSelector: ConfigComboBox {
        property string routingKey: ""
        Layout.fillWidth: true
        fieldWidth: 110
        model: [
            { displayName: Translation.tr("Auto"), icon: "auto_awesome", value: "auto" },
            { displayName: Translation.tr("Volume"), icon: "graphic_eq", value: "volume" },
            { displayName: Translation.tr("Kick / beat"), icon: "ads_click", value: "beat" },
            { displayName: Translation.tr("Bass"), icon: "low_priority", value: "bass" },
            { displayName: Translation.tr("Mid"), icon: "equalizer", value: "mid" },
            { displayName: Translation.tr("Treble"), icon: "high_quality", value: "treble" },
        ]
        currentValue: Config.options.background.effects.audioRouting?.[routingKey] ?? "auto"
        onSelected: newValue => {
            Config.options.background.effects.audioRouting[routingKey] = newValue
        }
    }

    Loader {
        id: savePresetDialogLoader
        parent: page
        x: 0
        y: 0
        width: page.width
        height: page.height
        z: 2000
        active: page.savePresetDialogOpen
        sourceComponent: SavePresetDialog {
            onSaved: name => EffectPresets.saveCurrentAs(name)
        }
        onActiveChanged: {
            if (active) {
                item.show = true
                item.forceActiveFocus()
            }
        }
        Connections {
            target: savePresetDialogLoader.item
            function onDismiss() {
                savePresetDialogLoader.item.show = false
                page.savePresetDialogOpen = false
            }
            function onVisibleChanged() {
                if (savePresetDialogLoader.item && !savePresetDialogLoader.item.visible
                        && !page.savePresetDialogOpen)
                    savePresetDialogLoader.active = false
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "swap_horiz"
            title: Translation.tr("Wallpaper transitions")
            shape: MaterialShape.Shape.Clover4Leaf

            ContentSubsection {
                title: Translation.tr("Change animation")

                GroupedList {
                    ConfigSpinBox {
                        icon: "timer"
                        text: Translation.tr("Wallpaper change interval (min)")
                        value: Config.options.wallpaperSelector.changeInterval / 60000
                        from: 0
                        to: 1440
                        stepSize: 5
                        onValueChanged: Config.options.wallpaperSelector.changeInterval = value * 60000
                    }
                    ConfigComboBox {
                        buttonIcon: "texture"
                        text: Translation.tr("Change effect")
                        fieldWidth: 100
                        model: [
                            { displayName: Translation.tr("None"), icon: "block", value: "" },
                            { displayName: Translation.tr("Circle"), icon: "circle", value: "circleSelect" },
                            { displayName: Translation.tr("Circle Pit"), icon: "blur_circular", value: "circlePit" },
                            { displayName: Translation.tr("Magic"), icon: "auto_awesome", value: "magic" },
                            { displayName: Translation.tr("Peel"), icon: "layers", value: "Peel" },
                            { displayName: Translation.tr("Fade"), icon: "gradient", value: "transition" },
                            { displayName: Translation.tr("Pixelate"), icon: "grain", value: "pixelate" },
                            { displayName: Translation.tr("Stripes"), icon: "texture_minus", value: "stripes" },
                            { displayName: Translation.tr("Datamosh"), icon: "blur_on", value: "datamosh" },
                            { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                        ]
                        currentValue: Config.options.background.wallpaperAnimation
                        onSelected: newValue => Config.options.background.wallpaperAnimation = newValue
                    }
                    ConfigSpinBox {
                        icon: "schedule"
                        text: Translation.tr("Transition duration (ms)")
                        enabled: Config.options.background.wallpaperAnimation !== ""
                        value: Config.options.background.transitionDuration
                        from: 100
                        to: 5000
                        stepSize: 50
                        onValueChanged: Config.options.background.transitionDuration = value
                    }
                    ConfigSwitch {
                        buttonIcon: "sync_alt"
                        text: Translation.tr("Synchronize Datamosh direction")
                        enabled: Config.options.background.wallpaperAnimation === "datamosh"
                        checked: Config.options.background.effects.transitionMode === "synchronized"
                        onClicked: Config.options.background.effects.transitionMode =
                            Config.options.background.effects.transitionMode === "synchronized"
                                ? "independent" : "synchronized"
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Datamosh change style")

                GroupedList {
                    enabled: Config.options.background.wallpaperAnimation === "datamosh"

                    ConfigSwitch {
                        buttonIcon: "casino"
                        text: Translation.tr("Randomize each switch")
                        checked: Config.options.background.effects.transition.randomize
                        onClicked: Config.options.background.effects.transition.randomize =
                            !Config.options.background.effects.transition.randomize
                    }
                    ConfigComboBox {
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Direction")
                        fieldWidth: 100
                        model: [
                            { displayName: Translation.tr("Vertical"), icon: "swap_vert", value: "vertical" },
                            { displayName: Translation.tr("Horizontal"), icon: "swap_horiz", value: "horizontal" },
                            { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                        ]
                        currentValue: Config.options.background.effects.transition.glitchDirection
                        onSelected: newValue => Config.options.background.effects.transition.glitchDirection = newValue
                    }
                    ConfigSlider {
                        text: Translation.tr("Melt")
                        buttonIcon: "water_drop"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.melt
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.transition.melt = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Point cloud")
                        buttonIcon: "scatter_plot"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.pointCloud
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.transition.pointCloud = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Pixel sort")
                        buttonIcon: "sort"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.pixelSort
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.transition.pixelSort = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Feedback")
                        buttonIcon: "motion_blur"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.feedback
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.transition.feedback = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Block corruption")
                        buttonIcon: "grid_view"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.blockCorruption
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.transition.blockCorruption = value
                    }
                    ConfigSlider {
                        text: Translation.tr("RGB separation")
                        buttonIcon: "gradient"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.chromaticAberration
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.transition.chromaticAberration = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Noise")
                        buttonIcon: "grain"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.noise
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.transition.noise = value
                    }
                }
            }
        }

        ContentSection {
            icon: "blur_on"
            title: Translation.tr("Live distortion")
            shape: MaterialShape.Shape.Puffy

            ContentSubsection {
                title: Translation.tr("Live wallpaper distortion")

                GroupedList {
                    ConfigComboBox {
                        buttonIcon: "palette"
                        text: Translation.tr("Preset")
                        fieldWidth: 110
                        enabled: !Config.options.background.effects.randomizePerMonitor
                        model: EffectPresets.comboModel()
                        currentValue: EffectPresets.currentName()
                        onSelected: newValue => {
                            if (newValue !== "custom") EffectPresets.apply(newValue)
                        }
                    }
                    ConfigRow {
                        uniform: false
                        Item { Layout.fillWidth: true }
                        RippleButtonWithIcon {
                            materialIcon: "bookmark_add"
                            mainText: Translation.tr("Save as preset...")
                            onClicked: page.savePresetDialogOpen = true
                        }
                        RippleButtonWithIcon {
                            materialIcon: "delete"
                            mainText: Translation.tr("Delete preset")
                            visible: EffectPresets.currentName().startsWith("custom:")
                            onClicked: EffectPresets.deleteCustom(EffectPresets.currentName().slice(7))
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "shuffle"
                        text: Translation.tr("Randomize per monitor")
                        checked: Config.options.background.effects.randomizePerMonitor
                        onClicked: Config.options.background.effects.randomizePerMonitor =
                            !Config.options.background.effects.randomizePerMonitor
                    }
                    ConfigRow {
                        uniform: false
                        visible: Config.options.background.effects.randomizePerMonitor
                        Item { Layout.fillWidth: true }
                        RippleButtonWithIcon {
                            materialIcon: "casino"
                            mainText: Translation.tr("Reroll")
                            onClicked: EffectPresets.rerollAll()
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "animation"
                        text: Translation.tr("Enable live distortion")
                        checked: Config.options.background.effects.enable
                        onClicked: Config.options.background.effects.enable =
                            !Config.options.background.effects.enable
                    }
                    ConfigComboBox {
                        buttonIcon: "monitor"
                        text: Translation.tr("Apply to")
                        fieldWidth: 125
                        model: [
                            { displayName: Translation.tr("All monitors"), icon: "select_all", value: "all" },
                            { displayName: Translation.tr("All but primary"), icon: "splitscreen", value: "allButPrimary" },
                        ].concat(Quickshell.screens.map(s => ({
                            displayName: Translation.tr("Only %1").arg(s.name),
                            icon: "monitor",
                            value: s.name
                        })))
                        currentValue: Config.options.background.effects.screenMode
                        onSelected: newValue => Config.options.background.effects.screenMode = newValue
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Live distortion mix")

                GroupedList {
                    enabled: Config.options.background.effects.enable
                        && !Config.options.background.effects.randomizePerMonitor

                    ConfigSlider {
                        text: Translation.tr("Point cloud")
                        buttonIcon: "scatter_plot"
                        value: Config.options.background.effects.pointCloud
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.pointCloud = value
                    }
                    ConfigSpinBox {
                        icon: "grain"
                        text: Translation.tr("Point spacing (px)")
                        value: Config.options.background.effects.pointSpacing
                        from: 2; to: 64; stepSize: 1
                        onValueChanged: Config.options.background.effects.pointSpacing = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Melt")
                        buttonIcon: "water_drop"
                        value: Config.options.background.effects.melt
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.melt = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Melt reach")
                        buttonIcon: "height"
                        value: Config.options.background.effects.meltReach
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.meltReach = value
                    }
                    ConfigSpinBox {
                        icon: "width"
                        text: Translation.tr("Melt column width (px)")
                        value: Config.options.background.effects.meltWidth
                        from: 1; to: 64; stepSize: 1
                        onValueChanged: Config.options.background.effects.meltWidth = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Feedback")
                        buttonIcon: "motion_blur"
                        value: Config.options.background.effects.feedback
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.feedback = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Pixel sort")
                        buttonIcon: "sort"
                        value: Config.options.background.effects.pixelSort
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.pixelSort = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Pixel sort threshold")
                        buttonIcon: "exposure"
                        value: Config.options.background.effects.sortThreshold
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.sortThreshold = value
                    }
                    ConfigComboBox {
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Glitch direction")
                        fieldWidth: 100
                        model: [
                            { displayName: Translation.tr("Vertical"), icon: "swap_vert", value: "vertical" },
                            { displayName: Translation.tr("Horizontal"), icon: "swap_horiz", value: "horizontal" },
                            { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                        ]
                        currentValue: Config.options.background.effects.glitchDirection
                        onSelected: newValue => Config.options.background.effects.glitchDirection = newValue
                    }
                    ConfigSlider {
                        text: Translation.tr("Block corruption")
                        buttonIcon: "grid_view"
                        value: Config.options.background.effects.blockCorruption
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.blockCorruption = value
                    }
                    ConfigSpinBox {
                        icon: "grid_4x4"
                        text: Translation.tr("Block size (px)")
                        value: Config.options.background.effects.blockSize
                        from: 1; to: 64; stepSize: 1
                        onValueChanged: Config.options.background.effects.blockSize = value
                    }
                    ConfigSlider {
                        text: Translation.tr("RGB separation")
                        buttonIcon: "gradient"
                        value: Config.options.background.effects.chromaticAberration
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.chromaticAberration = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Noise")
                        buttonIcon: "grain"
                        value: Config.options.background.effects.noise
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.noise = value
                    }
                }
            }
        }

        ContentSection {
            icon: "graphic_eq"
            title: Translation.tr("Audio response")
            shape: MaterialShape.Shape.Cookie7Sided

            ContentSubsection {
                title: Translation.tr("Music response")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "music_note"
                        text: Translation.tr("React live distortion to music")
                        checked: Config.options.background.effects.musicReactive
                        enabled: Config.options.background.effects.enable
                        onClicked: Config.options.background.effects.musicReactive =
                            !Config.options.background.effects.musicReactive
                    }
                    ConfigSlider {
                        text: Translation.tr("Music intensity")
                        buttonIcon: "graphic_eq"
                        enabled: Config.options.background.effects.enable
                            && Config.options.background.effects.musicReactive
                            && !Config.options.background.effects.randomizePerMonitor
                        value: Config.options.background.effects.musicIntensity
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.musicIntensity = value
                    }
                    ConfigComboBox {
                        buttonIcon: "playlist_play"
                        text: Translation.tr("Audio source")
                        fieldWidth: 125
                        enabled: Config.options.background.effects.enable
                            && Config.options.background.effects.musicReactive
                        model: {
                            const seen = []
                            const out = [{ displayName: Translation.tr("Any audio"), icon: "done_all", value: "" }]
                            const add = name => {
                                const value = (name ?? "").trim()
                                if (value.length === 0 || seen.includes(value.toLowerCase())) return
                                seen.push(value.toLowerCase())
                                out.push({ displayName: value, icon: "music_note", value })
                            }
                            ;(MprisController.players ?? []).forEach(player => add(player?.identity))
                            add(Config.options.background.effects.player)
                            return out
                        }
                        currentValue: Config.options.background.effects.player
                        onSelected: newValue => Config.options.background.effects.player = newValue
                    }
                    ConfigSlider {
                        text: Translation.tr("Beat intensity")
                        buttonIcon: "resize"
                        enabled: Config.options.background.effects.enable
                            && Config.options.background.effects.musicReactive
                            && !Config.options.background.effects.randomizePerMonitor
                        value: Config.options.background.effects.beatIntensity
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.beatIntensity = value
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Audio trigger routing")
                tooltip: Translation.tr("Choose the audio signal that drives each live effect. Auto keeps the preset's tuned mix.")

                ConfigRow {
                    Layout.fillWidth: true
                    uniform: true
                    enabled: Config.options.background.effects.enable
                        && Config.options.background.effects.musicReactive
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "melt"; text: Translation.tr("Melt"); buttonIcon: "water_drop" }
                    }
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "pointCloud"; text: Translation.tr("Point cloud"); buttonIcon: "scatter_plot" }
                    }
                }
                ConfigRow {
                    Layout.fillWidth: true
                    uniform: true
                    enabled: Config.options.background.effects.enable
                        && Config.options.background.effects.musicReactive
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "feedback"; text: Translation.tr("Feedback"); buttonIcon: "motion_blur" }
                    }
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "pixelSort"; text: Translation.tr("Pixel sort"); buttonIcon: "sort" }
                    }
                }
                ConfigRow {
                    Layout.fillWidth: true
                    uniform: true
                    enabled: Config.options.background.effects.enable
                        && Config.options.background.effects.musicReactive
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "blockCorruption"; text: Translation.tr("Block corruption"); buttonIcon: "grid_view" }
                    }
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "chromaticAberration"; text: Translation.tr("RGB separation"); buttonIcon: "gradient" }
                    }
                }
                ConfigRow {
                    Layout.fillWidth: true
                    uniform: true
                    enabled: Config.options.background.effects.enable
                        && Config.options.background.effects.musicReactive
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "noise"; text: Translation.tr("Noise"); buttonIcon: "grain" }
                    }
                    GroupedList {
                        itemVerticalPadding: 16
                        AudioTriggerSelector { routingKey: "lidar"; text: Translation.tr("LiDAR accents"); buttonIcon: "radar" }
                    }
                }
            }
        }

        ContentSection {
            icon: "splitscreen"
            title: Translation.tr("Cross-monitor effects")
            shape: MaterialShape.Shape.SoftBoom

            ContentSubsection {
                title: Translation.tr("Cross-monitor fragments")

                GroupedList {
                    ConfigSwitch {
                        id: neighborBleedSwitch
                        buttonIcon: "splitscreen"
                        text: Translation.tr("Blend neighboring wallpapers")
                        checked: Config.options.background.effects.neighborBleed
                        onClicked: Config.options.background.effects.neighborBleed =
                            !Config.options.background.effects.neighborBleed
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    opacity: enabled ? 1 : 0.4
                    enabled: neighborBleedSwitch.checked
                    GroupedList {
                        ConfigComboBox {
                            buttonIcon: "palette"
                            text: Translation.tr("Fragment preset")
                            fieldWidth: 110
                            model: SeamPresets.comboModel()
                            currentValue: SeamPresets.currentName()
                            onSelected: newValue => {
                                if (newValue !== "custom") SeamPresets.apply(newValue)
                            }
                        }
                        ConfigComboBox {
                            buttonIcon: "swap_horiz"
                            text: Translation.tr("Fragment direction")
                            fieldWidth: 135
                            model: [
                                { displayName: Translation.tr("Primary outward"), icon: "arrow_forward", value: "primary" },
                                { displayName: Translation.tr("Mutual neighbours"), icon: "sync_alt", value: "mutual" },
                            ]
                            currentValue: Config.options.background.effects.neighborBleedMode
                            onSelected: newValue => Config.options.background.effects.neighborBleedMode = newValue
                        }
                        ConfigSwitch {
                            buttonIcon: "music_note"
                            text: Translation.tr("React fragments to music")
                            checked: Config.options.background.effects.neighborBleedMusicReactive
                            onClicked: Config.options.background.effects.neighborBleedMusicReactive =
                                !Config.options.background.effects.neighborBleedMusicReactive
                        }
                    }
                    GroupedList {
                        ConfigSlider {
                            text: Translation.tr("Fragment reach")
                            buttonIcon: "width"
                            value: Config.options.background.effects.neighborBleedWidth
                            from: 0.04; to: 1
                            onValueChanged: Config.options.background.effects.neighborBleedWidth = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Source influence")
                            buttonIcon: "arrow_forward"
                            value: Config.options.background.effects.neighborBleedStrength
                            from: 0; to: 1
                            onValueChanged: Config.options.background.effects.neighborBleedStrength = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Edge softness")
                            buttonIcon: "gradient"
                            value: Config.options.background.effects.neighborBleedEdgeSoftness
                            from: 0.02; to: 0.98
                            onValueChanged: Config.options.background.effects.neighborBleedEdgeSoftness = value
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    opacity: enabled ? 1 : 0.4
                    enabled: neighborBleedSwitch.checked
                    GroupedList {
                        ConfigSlider {
                            text: Translation.tr("Fragment threshold")
                            buttonIcon: "filter_alt"
                            value: Config.options.background.effects.neighborBleedFragmentThreshold
                            from: 0; to: 0.8
                            onValueChanged: Config.options.background.effects.neighborBleedFragmentThreshold = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Fragment softness")
                            buttonIcon: "blur_linear"
                            value: Config.options.background.effects.neighborBleedFragmentSoftness
                            from: 0.01; to: 0.8
                            onValueChanged: Config.options.background.effects.neighborBleedFragmentSoftness = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Edge raggedness")
                            buttonIcon: "polyline"
                            usePercentTooltip: false
                            value: Config.options.background.effects.neighborBleedRaggedness
                            from: 0; to: 2
                            onValueChanged: Config.options.background.effects.neighborBleedRaggedness = value
                        }
                    }
                    GroupedList {
                        ConfigSlider {
                            text: Translation.tr("Fragment grain")
                            buttonIcon: "grain"
                            usePercentTooltip: false
                            value: Config.options.background.effects.neighborBleedGrain
                            from: 0.25; to: 4
                            onValueChanged: Config.options.background.effects.neighborBleedGrain = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Fragment motion speed")
                            buttonIcon: "speed"
                            usePercentTooltip: false
                            value: Config.options.background.effects.neighborBleedMotionSpeed
                            from: 0; to: 4
                            onValueChanged: Config.options.background.effects.neighborBleedMotionSpeed = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Fragment feedback")
                            buttonIcon: "motion_blur"
                            usePercentTooltip: false
                            value: Config.options.background.effects.neighborBleedFeedback
                            from: 0; to: 2
                            onValueChanged: Config.options.background.effects.neighborBleedFeedback = value
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    opacity: enabled ? 1 : 0.4
                    enabled: neighborBleedSwitch.checked
                    GroupedList {
                        ConfigSwitch {
                            id: colorTrailsSwitch
                            buttonIcon: "colorize"
                            text: Translation.tr("Carry colour trails")
                            checked: Config.options.background.effects.neighborBleedColorTrails
                            onClicked: Config.options.background.effects.neighborBleedColorTrails =
                                !Config.options.background.effects.neighborBleedColorTrails
                        }
                        ConfigSlider {
                            text: Translation.tr("Colour trail threshold")
                            buttonIcon: "filter_alt"
                            enabled: colorTrailsSwitch.checked
                            value: Config.options.background.effects.neighborBleedColorThreshold
                            from: 0; to: 0.8
                            onValueChanged: Config.options.background.effects.neighborBleedColorThreshold = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Colour trail softness")
                            buttonIcon: "blur_linear"
                            enabled: colorTrailsSwitch.checked
                            value: Config.options.background.effects.neighborBleedColorSoftness
                            from: 0.01; to: 0.8
                            onValueChanged: Config.options.background.effects.neighborBleedColorSoftness = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Colour trail strength")
                            buttonIcon: "gradient"
                            enabled: colorTrailsSwitch.checked
                            value: Config.options.background.effects.neighborBleedColorStrength
                            from: 0; to: 1
                            onValueChanged: Config.options.background.effects.neighborBleedColorStrength = value
                        }
                    }
                    GroupedList {
                        ConfigSwitch {
                            id: battleSwitch
                            buttonIcon: "sports_martial_arts"
                            text: Translation.tr("Let monitors contend")
                            checked: Config.options.background.effects.neighborBleedBattle
                            onClicked: Config.options.background.effects.neighborBleedBattle =
                                !Config.options.background.effects.neighborBleedBattle
                        }
                        ConfigSlider {
                            text: Translation.tr("Contention intensity")
                            buttonIcon: "bolt"
                            enabled: battleSwitch.checked
                            value: Config.options.background.effects.neighborBleedBattleStrength
                            from: 0; to: 1
                            onValueChanged: Config.options.background.effects.neighborBleedBattleStrength = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Outgoing force")
                            buttonIcon: "north_east"
                            enabled: battleSwitch.checked
                            usePercentTooltip: false
                            value: Config.options.background.effects.neighborBleedPrimaryPush
                            from: 0; to: 2
                            onValueChanged: Config.options.background.effects.neighborBleedPrimaryPush = value
                        }
                        ConfigSlider {
                            text: Translation.tr("Receiving resistance")
                            buttonIcon: "shield"
                            enabled: battleSwitch.checked
                            usePercentTooltip: false
                            value: Config.options.background.effects.neighborBleedSecondaryResistance
                            from: 0; to: 2
                            onValueChanged: Config.options.background.effects.neighborBleedSecondaryResistance = value
                        }
                    }
                }

                ConfigRow {
                    Layout.fillWidth: true
                    enabled: neighborBleedSwitch.checked
                    Item { Layout.fillWidth: true }
                    RippleButtonWithIcon {
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Reset cross-monitor controls")
                        onClicked: SeamPresets.apply("balanced")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("LiDAR image accents")

                GroupedList {
                    ConfigSwitch {
                        id: lidarSwitch
                        buttonIcon: "radar"
                        text: Translation.tr("Enable LiDAR image accents")
                        enabled: Config.options.background.effects.enable
                        checked: Config.options.background.effects.neighborBleedLidar
                        onClicked: Config.options.background.effects.neighborBleedLidar =
                            !Config.options.background.effects.neighborBleedLidar
                    }
                    ConfigComboBox {
                        buttonIcon: "detection_and_zone"
                        text: Translation.tr("LiDAR mask")
                        fieldWidth: 160
                        enabled: lidarSwitch.enabled && lidarSwitch.checked
                        model: [
                            { displayName: Translation.tr("Scanning raster"), icon: "scan", value: "scan" },
                            { displayName: Translation.tr("Current image outlines"), icon: "gesture", value: "outlines" },
                        ]
                        currentValue: Config.options.background.effects.neighborBleedLidarMode
                        onSelected: newValue => Config.options.background.effects.neighborBleedLidarMode = newValue
                    }
                    ConfigSlider {
                        text: Translation.tr("Accent intensity")
                        buttonIcon: "flare"
                        enabled: lidarSwitch.enabled && lidarSwitch.checked
                        value: Config.options.background.effects.neighborBleedLidarStrength
                        from: 0; to: 1
                        onValueChanged: Config.options.background.effects.neighborBleedLidarStrength = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Scan-line density")
                        buttonIcon: "format_line_spacing"
                        enabled: lidarSwitch.enabled && lidarSwitch.checked
                        usePercentTooltip: false
                        value: Config.options.background.effects.neighborBleedLidarDensity
                        from: 4; to: 96
                        onValueChanged: Config.options.background.effects.neighborBleedLidarDensity = value
                    }
                    ConfigSlider {
                        text: Translation.tr("Sweep speed")
                        buttonIcon: "speed"
                        enabled: lidarSwitch.enabled && lidarSwitch.checked
                        usePercentTooltip: false
                        value: Config.options.background.effects.neighborBleedLidarSpeed
                        from: 0; to: 4
                        onValueChanged: Config.options.background.effects.neighborBleedLidarSpeed = value
                    }
                }
            }
        }
    }
}
