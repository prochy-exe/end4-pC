import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.wallpaperEffects
import Quickshell
import Quickshell.Io

ContentPage {
    id: page
    forceWidth: true

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

    function displayPathFor(path) {
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    property bool savePresetDialogOpen: false

    // Sticky like InterfaceConfig's iconPickerLoader, for the same reason -
    // it needs to cover the page's visible viewport regardless of scroll.
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
                if (savePresetDialogLoader.item && !savePresetDialogLoader.item.visible && !page.savePresetDialogOpen)
                    savePresetDialogLoader.active = false
            }
        }
    }

    // Resyncs live hyprland.conf values into the compositor whenever
    // Settings is opened - this used to live on the standalone "Hyprland"
    // settings page, which got dissolved; its controls now live across this
    // page (decoration/animations), General (input), and Windows (layout),
    // but Settings eagerly loads every page's Loader on open regardless of
    // which one the user clicks first, so keeping this as one intact block
    // here works exactly the same as when it was on its own page.
    Component.onCompleted: {
        const h = Config.options.hyprland
        HyprlandConfig.setMany({
            "decoration:rounding":                  h.decoration.rounding,
            "decoration:blur:enabled":              h.decoration.blur.enabled ? 1 : 0,
            "decoration:blur:size":                 h.decoration.blur.size,
            "decoration:blur:passes":               h.decoration.blur.passes,
            "decoration:active_opacity":            h.decoration.activeOpacity,
            "decoration:inactive_opacity":          h.decoration.inactiveOpacity,
            "general:border_size":                  h.general.borderSize,
            "general:gaps_in":                      h.general.gapsIn,
            "general:gaps_out":                     h.general.gapsOut,
            "general:layout":                       h.general.layout,
            "animations:enabled":                   h.animations.enable ? 1 : 0,
            "input:kb_layout":                      h.input.kbLayout,
            "input:numlock_by_default":             h.input.numlock ? 1 : 0,
            "input:repeat_delay":                   h.input.repeatDelay,
            "input:repeat_rate":                    h.input.repeatRate,
            "input:follow_mouse":                   h.input.followMouse,
            "input:touchpad:natural_scroll":        h.input.touchpad.naturalScroll ? 1 : 0,
            "input:touchpad:disable_while_typing":  h.input.touchpad.disableWhileTyping ? 1 : 0,
            "input:touchpad:clickfinger_behavior":  h.input.touchpad.clickfingerBehavior ? 1 : 0,
            "input:touchpad:scroll_factor":         h.input.touchpad.scrollFactor
        })
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20
        ContentSection {
            icon: "panorama"
            title: Translation.tr("Wallpaper")
            shape: MaterialShape.Shape.Clover4Leaf

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: wrapperCol.implicitHeight + 16
                topLeftRadius: Appearance.rounding.verylarge
                topRightRadius: Appearance.rounding.verylarge
                bottomLeftRadius: Appearance.rounding.normal
                bottomRightRadius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: wrapperCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "monitor"
                        text: Translation.tr("Use same wallpaper for all monitors")
                        checked: Config.options.background.wallpaperMode === "shared"
                        onClicked: {
                            Config.options.background.wallpaperMode =
                                Config.options.background.wallpaperMode === "shared" ? "perMonitor" : "shared";
                        }
                    }

                    Carousel {
                        Layout.fillWidth: true
                        implicitHeight: 280
                        largeItemWidthRatio: 0.5
                        mediumItemWidthRatio: 0.485
                        itemSpacing: 8
                        // "Same for all": one Desktop slot + Lock screen, as before.
                        // Per-monitor: one slot per real output + Lock screen.
                        model: (Config.options.background.wallpaperMode === "shared"
                            ? [page.displayPathFor(Config.options.background.wallpaperPath)]
                            : Quickshell.screens.map(s => page.displayPathFor(
                                (Config.options.background.monitorWallpapers ?? []).find(m => m.name === s.name)?.path
                                    ?? Config.options.background.wallpaperPath
                            ))
                        ).concat([
                            page.displayPathFor(
                                Config.options.background.lockWall !== ""
                                    ? Config.options.background.lockWall
                                    : Config.options.background.wallpaperPath
                            )
                        ])
                        wheelEnabled: false
                        dragEnabled: false
                        clickAction: (index, modelData) => {
                            const lockIndex = Config.options.background.wallpaperMode === "shared"
                                ? 1 : Quickshell.screens.length;
                            if (index === lockIndex) {
                                GlobalStates.wallpaperSelectorTarget = "lockWall";
                            } else if (Config.options.background.wallpaperMode === "shared") {
                                GlobalStates.wallpaperSelectorTarget = "wallpaper";
                            } else {
                                GlobalStates.wallpaperSelectorTarget = "monitor:" + Quickshell.screens[index].name;
                            }
                            GlobalStates.wallpaperSelectorOpen = true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Appearance.rounding.normal
                            color: "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    text: "desktop_windows"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Desktop")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Appearance.rounding.normal
                            color: "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    text: "lock"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Lockscreen")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }

            GroupedList {
                Layout.topMargin: -2

                ConfigSwitch {
                    id: syncWallpaperSwitch
                    buttonIcon: "sync"
                    text: Translation.tr("Use same wallpaper for both")
                    checked: Config.options.background.lockWall === ""
                    onCheckedChanged: {
                        if (checked) {
                            Config.options.background.lockWall = "";
                        }
                    }
                }

                ConfigSwitch {
                    buttonIcon: "preview"
                    text: Translation.tr("Preview wallpaper")
                    checked: Config.options.background.enableWallpaperPreview
                    onCheckedChanged: {
                        Config.options.background.enableWallpaperPreview = checked;
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Wallpaper change interval (min)")
                    value: Config.options.wallpaperSelector.changeInterval / 60000
                    from: 0
                    to: 1440
                    stepSize: 5
                    onValueChanged: {
                        Config.options.wallpaperSelector.changeInterval = value * 60000;
                    }
                }

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "texture"
                    text: Translation.tr("Transitions")
                    fieldWidth: 50
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
                    onSelected: newValue => {
                        Config.options.background.wallpaperAnimation = newValue;
                    }
                }

                ConfigSpinBox {
                    icon: "schedule"
                    text: Translation.tr("Transition duration (ms)")
                    enabled: Config.options.background.wallpaperAnimation !== ""
                    value: Config.options.background.transitionDuration
                    from: 100
                    to: 5000
                    stepSize: 50
                    onValueChanged: {
                        Config.options.background.transitionDuration = value;
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "sync_alt"
                    text: Translation.tr("Synchronize direction across monitors")
                    // Only meaningful for the datamosh switch transition - the
                    // classic shuffle transitions have no per-monitor character.
                    enabled: Config.options.background.wallpaperAnimation === "datamosh"
                    checked: Config.options.background.effects.transitionMode === "synchronized"
                    onClicked: {
                        Config.options.background.effects.transitionMode =
                            Config.options.background.effects.transitionMode === "synchronized" ? "independent" : "synchronized";
                    }
                }
            }

            Connections {
                target: Config.options.background
                function onLockWallChanged() {
                    syncWallpaperSwitch.checked = Qt.binding(() => Config.options.background.lockWall === "")
                }
            }

            ContentSubsection {
                title: Translation.tr("Datamosh transition")
                Layout.fillWidth: true

                // The switch's own look, separate from the ambient effect below.
                // Deliberately has no monitor option: a wallpaper switch runs on
                // every screen, with the same seed, so it looks identical on all
                // of them. Duration lives with the Transitions dropdown above,
                // since it applies to every wallpaper animation.
                GroupedList {
                    enabled: Config.options.background.wallpaperAnimation === "datamosh"

                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "casino"
                        text: Translation.tr("Randomize each switch")
                        checked: Config.options.background.effects.transition.randomize
                        onClicked: {
                            Config.options.background.effects.transition.randomize = !Config.options.background.effects.transition.randomize;
                        }
                    }
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Direction")
                        fieldWidth: 80
                        model: [
                            { displayName: Translation.tr("Vertical"), icon: "swap_vert", value: "vertical" },
                            { displayName: Translation.tr("Horizontal"), icon: "swap_horiz", value: "horizontal" },
                            { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                        ]
                        currentValue: Config.options.background.effects.transition.glitchDirection
                        onSelected: newValue => {
                            Config.options.background.effects.transition.glitchDirection = newValue;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Melt")
                        buttonIcon: "water_drop"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.melt
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.transition.melt = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Point cloud")
                        buttonIcon: "scatter_plot"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.pointCloud
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.transition.pointCloud = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Pixel sort")
                        buttonIcon: "sort"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.pixelSort
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.transition.pixelSort = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Feedback")
                        buttonIcon: "motion_blur"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.feedback
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.transition.feedback = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Block corruption")
                        buttonIcon: "grid_view"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.blockCorruption
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.transition.blockCorruption = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("RGB separation")
                        buttonIcon: "gradient"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.chromaticAberration
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.transition.chromaticAberration = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Noise")
                        buttonIcon: "grain"
                        enabled: !Config.options.background.effects.transition.randomize
                        value: Config.options.background.effects.transition.noise
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.transition.noise = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Shader effects")
                Layout.fillWidth: true

                // Continuous effect on the wallpaper that is already set. The
                // datamosh switch transition is not here - it is the "Datamosh"
                // entry in the Transitions dropdown above.
                GroupedList {
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "palette"
                        text: Translation.tr("Preset")
                        fieldWidth: 90
                        // Moot once every monitor is picking its own preset.
                        enabled: !Config.options.background.effects.randomizePerMonitor
                        model: EffectPresets.comboModel()
                        // Derived, not stored: move any slider below and this
                        // goes back to Custom on its own rather than keeping a
                        // label that no longer describes the values.
                        currentValue: EffectPresets.currentName()
                        onSelected: newValue => {
                            if (newValue !== "custom")
                                EffectPresets.apply(newValue);
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
                        Layout.fillWidth: true
                        buttonIcon: "shuffle"
                        text: Translation.tr("Randomize per monitor")
                        checked: Config.options.background.effects.randomizePerMonitor
                        onClicked: {
                            Config.options.background.effects.randomizePerMonitor = !Config.options.background.effects.randomizePerMonitor;
                        }
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
                        Layout.fillWidth: true
                        buttonIcon: "animation"
                        text: Translation.tr("Animate current wallpaper")
                        checked: Config.options.background.effects.enable
                        onClicked: {
                            Config.options.background.effects.enable = !Config.options.background.effects.enable;
                        }
                    }
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "monitor"
                        text: Translation.tr("Show on")
                        fieldWidth: 90
                        // Live monitor list, so this is always the real outputs
                        // rather than names typed from memory.
                        model: [
                            { displayName: Translation.tr("All monitors"), icon: "select_all", value: "all" },
                            { displayName: Translation.tr("All but primary"), icon: "splitscreen", value: "allButPrimary" },
                        ].concat(Quickshell.screens.map(s => ({
                            displayName: Translation.tr("Only %1").arg(s.name),
                            icon: "monitor",
                            value: s.name
                        })))
                        currentValue: Config.options.background.effects.screenMode
                        onSelected: newValue => {
                            Config.options.background.effects.screenMode = newValue;
                        }
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "music_note"
                        text: Translation.tr("React to music")
                        checked: Config.options.background.effects.musicReactive
                        enabled: Config.options.background.effects.enable
                        onClicked: {
                            Config.options.background.effects.musicReactive = !Config.options.background.effects.musicReactive;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Music intensity")
                        buttonIcon: "graphic_eq"
                        enabled: Config.options.background.effects.enable && Config.options.background.effects.musicReactive
                            && !Config.options.background.effects.randomizePerMonitor
                        value: Config.options.background.effects.musicIntensity
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.musicIntensity = value;
                        }
                    }
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "playlist_play"
                        text: Translation.tr("React only to")
                        fieldWidth: 90
                        enabled: Config.options.background.effects.enable && Config.options.background.effects.musicReactive
                        // Whatever MPRIS currently knows about, plus whatever is
                        // already configured in case that player is closed.
                        model: {
                            const seen = [];
                            const out = [{ displayName: Translation.tr("Any audio"), icon: "done_all", value: "" }];
                            const add = name => {
                                const v = (name ?? "").trim();
                                if (v.length === 0 || seen.includes(v.toLowerCase()))
                                    return;
                                seen.push(v.toLowerCase());
                                out.push({ displayName: v, icon: "music_note", value: v });
                            };
                            (MprisController.players ?? []).forEach(p => add(p?.identity));
                            add(Config.options.background.effects.player);
                            return out;
                        }
                        currentValue: Config.options.background.effects.player
                        onSelected: newValue => {
                            Config.options.background.effects.player = newValue;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Beat intensity")
                        buttonIcon: "resize"
                        enabled: Config.options.background.effects.enable && Config.options.background.effects.musicReactive
                            && !Config.options.background.effects.randomizePerMonitor
                        value: Config.options.background.effects.beatIntensity
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.beatIntensity = value;
                        }
                    }
                }

                // Look of the ambient effect only - the Datamosh transition
                // rerolls its own character on every switch and ignores these.
                // Moot once every monitor is picking its own preset.
                GroupedList {
                    Layout.topMargin: 0
                    enabled: Config.options.background.effects.enable
                        && !Config.options.background.effects.randomizePerMonitor

                    ConfigSlider {
                        text: Translation.tr("Point cloud")
                        buttonIcon: "scatter_plot"
                        value: Config.options.background.effects.pointCloud
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.pointCloud = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "grain"
                        text: Translation.tr("Point spacing (px)")
                        value: Config.options.background.effects.pointSpacing
                        from: 2
                        to: 64
                        stepSize: 1
                        onValueChanged: {
                            Config.options.background.effects.pointSpacing = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Melt")
                        buttonIcon: "water_drop"
                        value: Config.options.background.effects.melt
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.melt = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Melt reach")
                        buttonIcon: "height"
                        value: Config.options.background.effects.meltReach
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.meltReach = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "width"
                        text: Translation.tr("Melt column width (px)")
                        value: Config.options.background.effects.meltWidth
                        from: 1
                        to: 64
                        stepSize: 1
                        onValueChanged: {
                            Config.options.background.effects.meltWidth = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Feedback")
                        buttonIcon: "motion_blur"
                        value: Config.options.background.effects.feedback
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.feedback = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Pixel sort")
                        buttonIcon: "sort"
                        value: Config.options.background.effects.pixelSort
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.pixelSort = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Pixel sort threshold")
                        buttonIcon: "exposure"
                        value: Config.options.background.effects.sortThreshold
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.sortThreshold = value;
                        }
                    }
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "swap_vert"
                        text: Translation.tr("Glitch direction")
                        fieldWidth: 80
                        model: [
                            { displayName: Translation.tr("Vertical"), icon: "swap_vert", value: "vertical" },
                            { displayName: Translation.tr("Horizontal"), icon: "swap_horiz", value: "horizontal" },
                            { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                        ]
                        currentValue: Config.options.background.effects.glitchDirection
                        onSelected: newValue => {
                            Config.options.background.effects.glitchDirection = newValue;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Block corruption")
                        buttonIcon: "grid_view"
                        value: Config.options.background.effects.blockCorruption
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.blockCorruption = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "grid_4x4"
                        text: Translation.tr("Block size (px)")
                        value: Config.options.background.effects.blockSize
                        from: 1
                        to: 64
                        stepSize: 1
                        onValueChanged: {
                            Config.options.background.effects.blockSize = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("RGB separation")
                        buttonIcon: "gradient"
                        value: Config.options.background.effects.chromaticAberration
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.chromaticAberration = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Noise")
                        buttonIcon: "grain"
                        value: Config.options.background.effects.noise
                        from: 0
                        to: 1
                        onValueChanged: {
                            Config.options.background.effects.noise = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Audio analysis")
                Layout.fillWidth: true

                // These feed qs-audiotap, which drives every visualiser in the
                // shell (bar, background widget, ticker, player cards) as well
                // as the wallpaper effect - not just this page.
                GroupedList {
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "bolt"
                        text: Translation.tr("Keep audio analysis running")
                        checked: Config.options.background.effects.audio.autoStart
                        onClicked: {
                            Config.options.background.effects.audio.autoStart = !Config.options.background.effects.audio.autoStart;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Beat sensitivity")
                        buttonIcon: "sensors"
                        usePercentTooltip: false
                        value: Config.options.background.effects.audio.beatSensitivity
                        from: 1.05
                        to: 3.0
                        onValueChanged: {
                            Config.options.background.effects.audio.beatSensitivity = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Beat floor")
                        buttonIcon: "vertical_align_bottom"
                        value: Config.options.background.effects.audio.beatFloor
                        from: 0
                        to: 0.6
                        onValueChanged: {
                            Config.options.background.effects.audio.beatFloor = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "timer"
                        text: Translation.tr("Beat decay (ms)")
                        value: Config.options.background.effects.audio.beatDecay
                        from: 20
                        to: 1000
                        stepSize: 10
                        onValueChanged: {
                            Config.options.background.effects.audio.beatDecay = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "hourglass_bottom"
                        text: Translation.tr("Minimum beat gap (ms)")
                        value: Config.options.background.effects.audio.beatMinInterval
                        from: 20
                        to: 1000
                        stepSize: 10
                        onValueChanged: {
                            Config.options.background.effects.audio.beatMinInterval = value;
                        }
                    }
                }

                GroupedList {
                    Layout.topMargin: 0
                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Update rate (Hz)")
                        value: Config.options.background.effects.audio.updateRate
                        from: 15
                        to: 240
                        stepSize: 5
                        onValueChanged: {
                            Config.options.background.effects.audio.updateRate = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "equalizer"
                        text: Translation.tr("Spectrum bars")
                        value: Config.options.background.effects.audio.bars
                        from: 8
                        to: 256
                        stepSize: 2
                        onValueChanged: {
                            Config.options.background.effects.audio.bars = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "graphic_eq"
                        text: Translation.tr("Lowest frequency (Hz)")
                        value: Config.options.background.effects.audio.rangeLow
                        from: 20
                        to: 500
                        stepSize: 10
                        onValueChanged: {
                            Config.options.background.effects.audio.rangeLow = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "graphic_eq"
                        text: Translation.tr("Highest frequency (Hz)")
                        value: Config.options.background.effects.audio.rangeHigh
                        from: 1000
                        to: 22000
                        stepSize: 500
                        onValueChanged: {
                            Config.options.background.effects.audio.rangeHigh = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Spectrum fall speed")
                        buttonIcon: "trending_down"
                        value: Config.options.background.effects.audio.barDecay
                        from: 0.002
                        to: 0.2
                        onValueChanged: {
                            Config.options.background.effects.audio.barDecay = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Auto gain release")
                        buttonIcon: "tune"
                        usePercentTooltip: false
                        value: Config.options.background.effects.audio.gainRelease
                        from: 0.99
                        to: 0.99999
                        onValueChanged: {
                            Config.options.background.effects.audio.gainRelease = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Centered wallpaper")
                Layout.fillWidth: true

                GroupedList {
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.centeredWallpaper
                        onClicked: {
                            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper;
                        }
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "lock"
                        text: Translation.tr("Show only when locked")
                        checked: Config.options.background.centeredWallpaperOnlyWhenLocked
                        onCheckedChanged: {
                            Config.options.background.centeredWallpaperOnlyWhenLocked = checked;
                        }
                        enabled: Config.options.background.centeredWallpaper
                    }
                }

                GroupedList {
                    Layout.topMargin: 0
                    visible: Config.options.background.centeredWallpaper
                    ConfigSelectionShapeArray {
                        currentValue: Config.options.background.centeredWallpaperShape
                        shapeColor: Appearance.colors.colPrimary
                        backgroundColor: Appearance.colors.colPrimaryContainer
                        options: [
                            "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                            "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                            "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                            "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                            "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                        ]
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperShape = newValue
                        }
                    }
                    ColorSelectionArray {
                        visible: Config.options.background.centeredWallpaper
                        icon: "palette"
                        text: Translation.tr("Background Color")
                        currentValue: Config.options.background.centeredWallpaperColor
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperColor = newValue
                        }
                    }
                    ConfigSlider {
                        visible: Config.options.background.centeredWallpaper
                        text: Translation.tr("Size")
                        value: Config.options.background.centeredWallpaperSize
                        usePercentTooltip: false
                        buttonIcon: "aspect_ratio"
                        from: 400
                        to: 800
                        stopIndicatorValues: [400]
                        onValueChanged: {
                            Config.options.background.centeredWallpaperSize = value;
                        }
                    }
                }
            }
        }
        ContentSection {
            id: settingsClock
            icon: "clock_loader_40"
            shape: MaterialShape.Shape.Bun
            title: Translation.tr("Clock")

            function stylePresent(styleName) {
                if (!Config.options.background.widgets.clock.showOnlyWhenLocked && Config.options.background.widgets.clock.style === styleName) {
                    return true;
                }
                if (Config.options.background.widgets.clock.styleLocked === styleName) {
                    return true;
                }
                return false;
            }

            readonly property bool digitalPresent: stylePresent("digital")
            readonly property bool cookiePresent: stylePresent("cookie")

            GroupedList {
                ConfigSwitch {
                    Layout.fillWidth: false
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.clock.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.enable = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "lock_clock"
                    text: Translation.tr("Show only when locked")
                    checked: Config.options.background.widgets.clock.showOnlyWhenLocked
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.showOnlyWhenLocked = checked;
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Placement strategy")
                    icon: "move"
                    Layout.fillWidth: false
                    currentValue: Config.options.background.widgets.clock.placementStrategy
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.placementStrategy = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Draggable"),
                            icon: "drag_pan",
                            value: "free"
                        },
                        {
                            displayName: Translation.tr("Least busy"),
                            icon: "category",
                            value: "leastBusy"
                        },
                        {
                            displayName: Translation.tr("Most busy"),
                            icon: "shapes",
                            value: "mostBusy"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Clock style")
                    icon: "nest_clock_farsight_analog"
                    currentValue: Config.options.background.widgets.clock.style
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_view",
                            value: "pixel"
                        }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Clock style (locked)")
                    icon: "shield_watch"
                    currentValue: Config.options.background.widgets.clock.styleLocked
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.styleLocked = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_view",
                            value: "pixel"
                        }
                    ]
                }
            }

            ContentSubsection {
                visible: settingsClock.digitalPresent
                title: Translation.tr("Digital clock settings")

                ConfigRow {
                    uniform: true

                    GroupedList {
                        ConfigSwitch {
                            buttonIcon: "vertical_distribute"
                            text: Translation.tr("Vertical")
                            checked: Config.options.background.widgets.clock.digital.vertical
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.vertical = checked }
                        }
                        ConfigSwitch {
                            buttonIcon: "date_range"
                            text: Translation.tr("Show date")
                            checked: Config.options.background.widgets.clock.digital.showDate
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.showDate = checked }
                        }
                    }

                    GroupedList {
                        ConfigSwitch {
                            buttonIcon: "animation"
                            text: Translation.tr("Animate time change")
                            checked: Config.options.background.widgets.clock.digital.animateChange
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.animateChange = checked }
                        }
                        ConfigSwitch {
                            buttonIcon: "activity_zone"
                            text: Translation.tr("Use adaptive alignment")
                            checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.adaptiveAlignment = checked }
                        }
                    }
                }

                GroupedList {
                    ConfigSwitch {
                        id: autoColorSwitch
                        buttonIcon: "auto_awesome"
                        text: Translation.tr("Automatic colors")
                        checked: Config.options.background.widgets.clock.color === ""
                        onCheckedChanged: {
                            if (checked) {
                                Config.options.background.widgets.clock.color = ""
                            }
                        }
                    }

                    ColorSelectionArray {
                        icon: "palette"
                        text: Translation.tr("Color")
                        currentValue: Config.options.background.widgets.clock.color
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.color = newValue
                            autoColorSwitch.checked = false
                        }
                    }
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Font family")
                    text: Config.options.background.widgets.clock.digital.font.family
                    wrapMode: TextEdit.Wrap

                    Timer {
                        id: debounceTimer
                        interval: 500
                        repeat: false
                        onTriggered: {
                            Config.options.background.widgets.clock.digital.font.family = parent.text
                        }
                    }

                    onTextChanged: {
                        debounceTimer.restart()
                    }
                }
                GroupedList {
                    Layout.topMargin: 10
                    ConfigSlider {
                        text: Translation.tr("Font weight")
                        value: Config.options.background.widgets.clock.digital.font.weight
                        usePercentTooltip: false
                        buttonIcon: "format_bold"
                        from: 1
                        to: 1000
                        stopIndicatorValues: [350]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.weight = value;
                        }
                    }

                    ConfigSlider {
                        text: Translation.tr("Font size")
                        value: Config.options.background.widgets.clock.digital.font.size
                        usePercentTooltip: false
                        buttonIcon: "format_size"
                        from: 50
                        to: 700
                        stopIndicatorValues: [90]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.size = value;
                        }
                    }

                    ConfigSlider {
                        text: Translation.tr("Font width")
                        value: Config.options.background.widgets.clock.digital.font.width
                        usePercentTooltip: false
                        buttonIcon: "fit_width"
                        from: 25
                        to: 125
                        stopIndicatorValues: [100]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.width = value;
                        }
                    }
                    ConfigSlider {
                        text: Translation.tr("Font roundness")
                        value: Config.options.background.widgets.clock.digital.font.roundness
                        usePercentTooltip: false
                        buttonIcon: "line_curve"
                        from: 0
                        to: 100
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.roundness = value;
                        }
                    }
                }
            }

            ContentSubsection {
                visible: settingsClock.cookiePresent
                title: Translation.tr("Cookie clock settings")
                GroupedList {   
                    ConfigSwitch {  
                        buttonIcon: "wand_stars"
                        text: Translation.tr("Auto styling with Gemini")
                        checked: Config.options.background.widgets.clock.cookie.aiStyling
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.aiStyling = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "airwave"
                        text: Translation.tr("Use old sine wave cookie implementation")
                        checked: Config.options.background.widgets.clock.cookie.useSineCookie
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.useSineCookie = checked;
                        }
                    }

                    ConfigSpinBox {
                        icon: "add_triangle"
                        text: Translation.tr("Sides")
                        value: Config.options.background.widgets.clock.cookie.sides
                        from: 0
                        to: 40
                        stepSize: 1
                        onValueChanged: {
                            Config.options.background.widgets.clock.cookie.sides = value;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "autoplay"
                        text: Translation.tr("Constantly rotate")
                        checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.constantlyRotate = checked;
                        }
                    }

                    ConfigRow {

                        ConfigSwitch {
                            enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"
                            buttonIcon: "brightness_7"
                            text: Translation.tr("Hour marks")
                            checked: Config.options.background.widgets.clock.cookie.hourMarks
                            onEnabledChanged: {
                                checked = Config.options.background.widgets.clock.cookie.hourMarks;
                            }
                            onCheckedChanged: {
                                Config.options.background.widgets.clock.cookie.hourMarks = checked;
                            }
                        }

                        ConfigSwitch {
                            enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers"
                            buttonIcon: "timer_10"
                            text: Translation.tr("Digits in the middle")
                            checked: Config.options.background.widgets.clock.cookie.timeIndicators
                            onEnabledChanged: {
                                checked = Config.options.background.widgets.clock.cookie.timeIndicators;
                            }
                            onCheckedChanged: {
                                Config.options.background.widgets.clock.cookie.timeIndicators = checked;
                            }
                        }
                    }
                }
            }

            GroupedList {
                Layout.topMargin: 10
                visible: settingsClock.cookiePresent
                ConfigSelectionArray {
                    text: "Dial Style"
                    icon: "graph_6"
                    currentValue: Config.options.background.widgets.clock.cookie.dialNumberStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.dialNumberStyle = newValue;
                        if (newValue !== "dots" && newValue !== "full") {
                            Config.options.background.widgets.clock.cookie.hourMarks = false;
                        }
                        if (newValue === "numbers") {
                            Config.options.background.widgets.clock.cookie.timeIndicators = false;
                        }
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "none"
                        },
                        {
                            displayName: Translation.tr("Dots"),
                            icon: "graph_6",
                            value: "dots"
                        },
                        {
                            displayName: Translation.tr("Full"),
                            icon: "history_toggle_off",
                            value: "full"
                        },
                        {
                            displayName: Translation.tr("Numbers"),
                            icon: "counter_1",
                            value: "numbers"
                        }
                    ]
                }
                ConfigSelectionArray {
                    icon: "highlighter_size_2"
                    text: Translation.tr("Hour hand")
                    currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.hourHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hollow"),
                            icon: "circle",
                            value: "hollow"
                        },
                        {
                            displayName: Translation.tr("Fill"),
                            icon: "eraser_size_5",
                            value: "fill"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Minute hand")
                    icon: "eraser_size_1" 
                    currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Thin"),
                            icon: "line_end",
                            value: "thin"
                        },
                        {
                            displayName: Translation.tr("Medium"),
                            icon: "eraser_size_2",
                            value: "medium"
                        },
                        {
                            displayName: Translation.tr("Bold"),
                            icon: "eraser_size_4",
                            value: "bold"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Second hand")
                    icon: "pen_size_1"
                    currentValue: Config.options.background.widgets.clock.cookie.secondHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.secondHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Line"),
                            icon: "line_end",
                            value: "line"
                        },
                        {
                            displayName: Translation.tr("Dot"),
                            icon: "adjust",
                            value: "dot"
                        },
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Date style")
                    icon: "date_range"
                    currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.dateStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Bubble"),
                            icon: "bubble_chart",
                            value: "bubble"
                        },
                        {
                            displayName: Translation.tr("Border"),
                            icon: "rotate_right",
                            value: "border"
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "rectangle",
                            value: "rect"
                        }
                    ]
                }
            }
            
            ContentSubsection {
                visible: Config.options.background.widgets.clock.style === "pixel"
                title: Translation.tr("Pixel Clock Settings")
                GroupedList {
                    visible: Config.options.background.widgets.clock.style === "pixel"
                    ConfigSelectionArray {
                        text: Translation.tr("Pixel clock orientation")
                        visible: Config.options.background.widgets.clock.style === "pixel"
                        icon: "screen_rotation"
                        currentValue: Config.options.background.widgets.clock.pixel.orientation
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.pixel.orientation = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Horizontal"),
                                icon: "swap_horiz",
                                value: "horizontal"
                            },
                            {
                                displayName: Translation.tr("Vertical"),
                                icon: "swap_vert",
                                value: "vertical"
                            }
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Quote")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.widgets.clock.quote.enable
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.quote.enable = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "font_download"
                        text: Translation.tr("Follow Clock Font")
                        enabled: Config.options.background.widgets.clock.style !== "pixel"
                        checked: Config.options.background.widgets.clock.quote.followClock
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.quote.followClock = checked;
                        }
                    }
                    ConfigTextArea {
                        id: quoteField
                        Layout.fillWidth: true
                        fieldWidth: 300
                        buttonIcon: "format_quote"
                        text: Translation.tr("Quote")
                        placeholderText: Translation.tr("Quote")
                        value: Config.options.background.widgets.clock.quote.text
                        onValueChanged: {
                            quoteDebounceTimer.restart();
                        }

                        Timer {
                            id: quoteDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.background.widgets.clock.quote.text = quoteField.value;
                            }
                        }
                    }
                }
            }
        }
        ContentSection {
            icon: "panorama"
            shape: MaterialShape.Shape.SoftBoom 
            title: Translation.tr("Custom Image")
            GroupedList {
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.customImage.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.customImage.enable = checked;
                    }
                }
                ConfigSelectionShapeArray {
                    currentValue: Config.options.background.widgets.customImage.shape
                    shapeColor: Appearance.colors.colPrimary
                    backgroundColor: Appearance.colors.colPrimaryContainer
                    options: [
                        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                        "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                        "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                        "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                    ]
                    onSelected: newValue => {
                        Config.options.background.widgets.customImage.shape = newValue
                    }
                }
            }
        }
        ContentSection {
            shape: MaterialShape.Shape.Puffy
            icon: "panorama"
            title: Translation.tr("Wallpaper selector")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "ad"
                    text: Translation.tr('Use system file picker')
                    checked: Config.options.wallpaperSelector.useSystemFileDialog
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.useSystemFileDialog = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "home"
                    text: Translation.tr('Show home directory in quick access')
                    checked: Config.options.wallpaperSelector.showHomePath
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.showHomePath = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "done"
                    text: Translation.tr('Close after selection')
                    checked: Config.options.wallpaperSelector.closeAfterSelection
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.closeAfterSelection = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr('Show blur background')
                    checked: Config.options.wallpaperSelector.showBlurBackground
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.showBlurBackground = checked;
                    }
                }

                ConfigSpinBox {
                    icon: "grid_on"
                    text: Translation.tr("Columns in grid view")
                    value: Config.options.wallpaperSelector.columns
                    from: 3
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.wallpaperSelector.columns = value;
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Wallpaper change interval (min)")
                    value: Config.options.wallpaperSelector.changeInterval / 60000
                    from: 0
                    to: 1440
                    stepSize: 5
                    onValueChanged: {
                        Config.options.wallpaperSelector.changeInterval = value * 60000;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "search"
                    text: Translation.tr('Always show search bar')
                    checked: Config.options.wallpaperSelector.showSearchbar
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.showSearchbar = checked;
                    }
                }
                ConfigTextArea {
                    id: userPathField
                    Layout.fillWidth: true
                    buttonIcon: "folder"
                    text: Translation.tr("Custom Wallpaper Folder")
                    placeholderText: Translation.tr("e.g., /home/user/Pictures")
                    fieldWidth: 300
                    value: Config.options.wallpaperSelector.userPath ?? ""

                    onValueChanged: {
                        userPathDebounceTimer.restart()
                    }

                    Timer {
                        id: userPathDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.wallpaperSelector.userPath = userPathField.value
                        }
                    }
                }
                ConfigTextArea {
                    id: liveWallpapersPathField
                    Layout.fillWidth: true
                    buttonIcon: "video_template"
                    text: Translation.tr("Live Wallpaper Folder")
                    placeholderText: Translation.tr("e.g., /home/user/Videos/Wallpapers")
                    fieldWidth: 300
                    value: Config.options.wallpaperSelector.liveWallpapersPath ?? ""

                    onValueChanged: {
                        liveWallpapersPathDebounceTimer.restart()
                    }

                    Timer {
                        id: liveWallpapersPathDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.wallpaperSelector.liveWallpapersPath = liveWallpapersPathField.value
                        }
                    }
                } 
            }
        }
        ContentSection {
            icon: "text_format"
            shape: MaterialShape.Shape.Arrow
            title: Translation.tr("Fonts")

            GroupedList {
                ConfigTextArea {
                    id: mainFontField
                    Layout.fillWidth: true
                    buttonIcon: "font_download"
                    text: Translation.tr("Font family name (e.g., Google Sans Flex)")
                    value: Config.options.appearance.fonts.main
                    onValueChanged: {
                        mainFontDebounceTimer.restart();
                    }

                    Timer {
                        id: mainFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.main = mainFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: numbersFontField
                    Layout.fillWidth: true
                    buttonIcon: "123"
                    text: Translation.tr("Numbers family name")
                    value: Config.options.appearance.fonts.numbers
                    onValueChanged: {
                        numbersFontDebounceTimer.restart();
                    }

                    Timer {
                        id: numbersFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.numbers = numbersFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: titleFontField
                    Layout.fillWidth: true
                    buttonIcon: "title"
                    text: Translation.tr("Title family name")
                    value: Config.options.appearance.fonts.title
                    onValueChanged: {
                        titleFontDebounceTimer.restart();
                    }

                    Timer {
                        id: titleFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.title = titleFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: monospaceFontField
                    Layout.fillWidth: true
                    buttonIcon: "space_bar"
                    text: Translation.tr("Monospace font name (e.g., JetBrains Mono NF)")
                    value: Config.options.appearance.fonts.monospace
                    onValueChanged: {
                        monospaceFontDebounceTimer.restart();
                    }

                    Timer {
                        id: monospaceFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.monospace = monospaceFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: iconNerdFontField
                    Layout.fillWidth: true
                    buttonIcon: "emoticon"
                    text: Translation.tr("Nerd Fonts Icons (e.g., JetBrains Mono NF)")
                    value: Config.options.appearance.fonts.iconNerd
                    onValueChanged: {
                        iconNerdFontDebounceTimer.restart();
                    }

                    Timer {
                        id: iconNerdFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.iconNerd = iconNerdFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: readingFontField
                    Layout.fillWidth: true
                    buttonIcon: "book_ribbon"
                    text: Translation.tr("Reading font name (e.g., Readex Pro)")
                    value: Config.options.appearance.fonts.reading
                    onValueChanged: {
                        readingFontDebounceTimer.restart();
                    }

                    Timer {
                        id: readingFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.reading = readingFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: expressiveFontField
                    Layout.fillWidth: true
                    buttonIcon: "mood_heart"
                    text: Translation.tr("Expressive font name (e.g., Space Grotesk)")
                    value: Config.options.appearance.fonts.expressive
                    onValueChanged: {
                        expressiveFontDebounceTimer.restart();
                    }

                    Timer {
                        id: expressiveFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.expressive = expressiveFontField.value;
                        }
                    }
                }
            }
        }
        ContentSection {
            icon: "colors"
            title: Translation.tr("Color generation")
            shape: MaterialShape.Shape.VerySunny

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "hardware"
                    text: Translation.tr("Shell & utilities")
                    checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked }
                }
                ConfigSwitch {
                    buttonIcon: "tv_options_input_settings"
                    text: Translation.tr("Qt apps")
                    checked: Config.options.appearance.wallpaperTheming.enableQtApps
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableQtApps = checked }
                }
                ConfigSwitch {
                    buttonIcon: "terminal"
                    text: Translation.tr("Terminal")
                    checked: Config.options.appearance.wallpaperTheming.enableTerminal
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableTerminal = checked }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        buttonIcon: "dark_mode"
                        text: Translation.tr("Force dark mode in terminal")
                        checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                        onCheckedChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked }
                    }
                }
                ConfigSpinBox {
                    icon: "invert_colors"
                    text: Translation.tr("Terminal: Harmony (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100 }
                }
                ConfigSpinBox {
                    icon: "gradient"
                    text: Translation.tr("Terminal: Harmonize threshold")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value }
                }
                ConfigSpinBox {
                    icon: "format_color_text"
                    text: Translation.tr("Terminal: Foreground boost (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100 }
                }
            }
        }
        ContentSection {
            icon: "deblur"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Visual & Aesthetics")

            GroupedList {
                ConfigSpinBox {
                    icon: "rounded_corner"
                    text: Translation.tr("Window Rounding")
                    value: Config.options.hyprland.decoration.rounding
                    from: 0; to: 30; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.decoration.rounding) return
                        Config.options.hyprland.decoration.rounding = value
                        HyprlandConfig.set("decoration:rounding", value)
                    }
                }

                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur")
                    checked: Config.options.hyprland.decoration.blur.enabled
                    onCheckedChanged: {
                        if (checked === Config.options.hyprland.decoration.blur.enabled) return
                        Config.options.hyprland.decoration.blur.enabled = checked
                        HyprlandConfig.set("decoration:blur:enabled", checked ? 1 : 0)
                    }
                }

                ConfigSpinBox {
                    icon: "blur_circular"
                    text: Translation.tr("Blur Size")
                    value: Config.options.hyprland.decoration.blur.size
                    from: 1; to: 20; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.decoration.blur.size) return
                        Config.options.hyprland.decoration.blur.size = value
                        HyprlandConfig.set("decoration:blur:size", value)
                    }
                }

                ConfigSpinBox {
                    icon: "layers"
                    text: Translation.tr("Blur Passes")
                    value: Config.options.hyprland.decoration.blur.passes
                    from: 1; to: 6; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.decoration.blur.passes) return
                        Config.options.hyprland.decoration.blur.passes = value
                        HyprlandConfig.set("decoration:blur:passes", value)
                    }
                }

                ConfigSpinBox {
                    icon: "border_outer"
                    text: Translation.tr("Border Size")
                    value: Config.options.hyprland.general.borderSize
                    from: 0; to: 10; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.general.borderSize) return
                        Config.options.hyprland.general.borderSize = value
                        HyprlandConfig.set("general:border_size", value)
                    }
                }

                ConfigSpinBox {
                    icon: "margin"
                    text: Translation.tr("Gaps In")
                    value: Config.options.hyprland.general.gapsIn
                    from: 0; to: 40; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.general.gapsIn) return
                        Config.options.hyprland.general.gapsIn = value
                        HyprlandConfig.set("general:gaps_in", value)
                    }
                }

                ConfigSpinBox {
                    icon: "open_in_full"
                    text: Translation.tr("Gaps Out")
                    value: Config.options.hyprland.general.gapsOut
                    from: 0; to: 60; stepSize: 1
                    onValueChanged: {
                        if (value === Config.options.hyprland.general.gapsOut) return
                        Config.options.hyprland.general.gapsOut = value
                        HyprlandConfig.set("general:gaps_out", value)
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Active Opacity")
                    value: Math.round(Config.options.hyprland.decoration.activeOpacity * 100)
                    from: 10; to: 100; stepSize: 5
                    onValueChanged: {
                        const newVal = value / 100.0
                        if (newVal === Config.options.hyprland.decoration.activeOpacity) return
                        Config.options.hyprland.decoration.activeOpacity = newVal
                        HyprlandConfig.set("decoration:active_opacity", newVal)
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Inactive Opacity")
                    value: Math.round(Config.options.hyprland.decoration.inactiveOpacity * 100)
                    from: 10; to: 100; stepSize: 5
                    onValueChanged: {
                        const newVal = value / 100.0
                        if (newVal === Config.options.hyprland.decoration.inactiveOpacity) return
                        Config.options.hyprland.decoration.inactiveOpacity = newVal
                        HyprlandConfig.set("decoration:inactive_opacity", newVal)
                    }
                }
            }
        }
        ContentSection {
            icon: "animation"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Animations")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.hyprland.animations.enable
                    onCheckedChanged: {
                        if (checked === Config.options.hyprland.animations.enable) return
                        Config.options.hyprland.animations.enable = checked
                        HyprlandConfig.set("animations:enabled", checked ? 1 : 0)
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Presets")
                    icon: "present_to_all"
                    currentValue: Config.options.hyprland.animations.animation
                    onSelected: newValue => {
                        Config.options.hyprland.animations.animation = newValue
                        saveAnimProc.command = [
                            "python3",
                            HyprlandConfig.configuratorScriptPath,
                            "--anim-preset", newValue
                        ]
                        saveAnimProc.running = true
                    }
                    options: [
                        { displayName: Translation.tr("Elastic"),   icon: "move_selection_right", value: "fast"   },
                        { displayName: Translation.tr("Normal"),    icon: "animation",            value: "normal" },
                        { displayName: Translation.tr("Niri Like"), icon: "mobiledata_arrows",    value: "niri"   },
                    ]
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                Layout.topMargin: 15
                text: Translation.tr("Animation presets require a require line in your hyprland.lua. Add the following line to enable presets:") + '\n\nrequire("hyprland/shellOverrides/animations")'

                Item { Layout.fillWidth: true }

                RippleButtonWithIcon {
                    id: copySourceButton
                    property bool justCopied: false
                    Layout.fillWidth: false
                    buttonRadius: Appearance.rounding.small
                    materialIcon: justCopied ? "check" : "content_copy"
                    mainText: justCopied ? Translation.tr("Copied!") : Translation.tr("Copy line")
                    onClicked: {
                        copySourceButton.justCopied = true
                        Quickshell.clipboardText = 'require("hyprland/shellOverrides/animations")'
                        revertSourceTimer.restart()
                    }
                    colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    Timer {
                        id: revertSourceTimer
                        interval: 1500
                        onTriggered: copySourceButton.justCopied = false
                    }
                }
            }

            Process {
                id: saveAnimProc
                onRunningChanged: if (!running) reloadAnimProc.running = true
            }
            Process {
                id: reloadAnimProc
                command: ["hyprctl", "reload"]
            }
        }
    }
}
