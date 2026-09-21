import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

ContentPage {
    id: page
    property bool isMinimal: Config.options.settings.style === "minimal"
    forceWidth: true
    baseWidth: !isMinimal ? 700 : 600
    bottomContentPadding: 35

    function goTo(term) {
        const t = term.toLowerCase().trim()
        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) return child
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

    function quickPreviewLayout() {
        const screens = Quickshell.screens.map((screen, index) => {
            const monitor = Hyprland.monitorFor(screen) ?? HyprlandData.monitors.find(m => m.name === screen.name) ?? screen;
            return {
                screen: screen,
                monitor: monitor,
                layoutX: Number.isFinite(Number(monitor.x)) ? Number(monitor.x) : index,
                layoutY: Number.isFinite(Number(monitor.y)) ? Number(monitor.y) : 0,
                layoutWidth: Number.isFinite(Number(monitor.width)) ? Number(monitor.width) : 1
            };
        }).sort((a, b) => a.layoutY - b.layoutY || a.layoutX - b.layoutX);
        const rows = [];
        for (const entry of screens) {
            let row = rows.find(r => {
                const verticallyAligned = Math.abs(r.y - entry.layoutY) < 100;
                const horizontallySeparate = r.entries.every(other =>
                    entry.layoutX >= other.layoutX + other.layoutWidth
                    || other.layoutX >= entry.layoutX + entry.layoutWidth
                );
                return verticallyAligned || horizontallySeparate;
            });
            if (!row) {
                row = { y: entry.layoutY, entries: [] };
                rows.push(row);
            }
            row.entries.push(entry);
        }
        rows.sort((a, b) => a.y - b.y);
        const layout = [];
        rows.forEach((row, rowIndex) => row.entries
            .sort((a, b) => a.layoutX - b.layoutX)
            .forEach((entry, columnIndex) => layout.push({
                screen: entry.screen,
                x: columnIndex / row.entries.length,
                y: rowIndex / rows.length,
                width: 1 / row.entries.length,
                height: 1 / rows.length
            })));
        return layout;
    }

    function quickPreviewWallpaperPath(screen) {
        if (Config.options.background.wallpaperMode === "perMonitor") {
            const monitorPath = (Config.options.background.monitorWallpapers ?? [])
                .find(m => m.name === screen.name)?.path;
            if (monitorPath) return monitorPath;
        }
        return Config.options.background.wallpaperPath;
    }

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: toggled ? MonitorThemes.shellColorForItem(page, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
        padding: 5
        Layout.fillWidth: true
        Layout.fillHeight: true
        toggled: Appearance.m3colors.darkmode === dark
        colBackground: MonitorThemes.shellColorForItem(page, "colLayer2", Appearance.colors.colLayer2)
        onClicked: {
            Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
        }
        contentItem: Item {
            anchors.centerIn: parent
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Wallpaper & Colors")
            shape: MaterialShape.Shape.Puffy
            Layout.fillWidth: true
            collapsible: false

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    id: quickPreview
                    Layout.preferredWidth: 420
                    Layout.preferredHeight: 280
                    radius: Appearance.rounding.large - 3
                    color: MonitorThemes.shellColorForItem(page, "colLayer2", Appearance.colors.colLayer2)
                    clip: true

                    Repeater {
                        model: page.quickPreviewLayout()
                        delegate: Item {
                            required property var modelData
                            x: modelData.x * quickPreview.width
                            y: modelData.y * quickPreview.height
                            width: modelData.width * quickPreview.width
                            height: modelData.height * quickPreview.height
                            clip: true

                            StyledImage {
                                anchors.fill: parent
                                sourceSize.width: parent.width
                                sourceSize.height: parent.height
                                fillMode: Image.PreserveAspectCrop
                                source: /\.(mp4|webm|mkv|avi|mov)$/i.test(page.quickPreviewWallpaperPath(modelData.screen))
                                    ? Config.options.background.thumbnailPath
                                    : page.quickPreviewWallpaperPath(modelData.screen)
                                cache: false
                            }
                        }
                    }

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: 420; height: 280
                            radius: Appearance.rounding.large - 3
                        }
                    }

                    ToolbarPairedFab {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 8
                        iconText: "colorize"
                        onClicked: {
                            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color"]);
                        }
                        StyledToolTip {
                            text: "Change accent color"
                        }
                    }
                }

                ColumnLayout {
                    visible: !isMinimal
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2
                        uniformCellSizes: true
                        SmallLightDarkPreferenceButton { dark: false }
                        SmallLightDarkPreferenceButton { dark: true }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 2
                        columnSpacing: 2

                        Repeater {
                            model: [
                                { value: "auto",               displayName: Translation.tr("Auto"),        icon: "auto_awesome" },
                                { value: "scheme-content",     displayName: Translation.tr("Content"),     icon: "image" },
                                { value: "scheme-expressive",  displayName: Translation.tr("Expressive"),  icon: "palette" },
                                { value: "scheme-fidelity",    displayName: Translation.tr("Fidelity"),    icon: "equal" },
                                { value: "scheme-fruit-salad", displayName: Translation.tr("Fruit Salad"), icon: "nutrition" },
                                { value: "scheme-monochrome",  displayName: Translation.tr("Mono"),  icon: "invert_colors" },
                                { value: "scheme-neutral",     displayName: Translation.tr("Neutral"),     icon: "tonality" },
                                { value: "scheme-rainbow",     displayName: Translation.tr("Rainbow"),     icon: "gradient" },
                                { value: "scheme-tonal-spot",  displayName: Translation.tr("Tonal Spot"),  icon: "lens" },
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: width * 0.6
                                radius: Appearance.rounding.normal

                                property bool isSelected: Config.options.appearance.palette.type === modelData.value
                                property bool hovered: hoverArea.containsMouse

                                color: isSelected ? MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary) 
                                    : hovered ? MonitorThemes.shellColorForItem(page, "colSecondaryContainerHover", Appearance.colors.colSecondaryContainerHover) 
                                    : MonitorThemes.shellColorForItem(page, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)

                                MaterialSymbol {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: 8
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: parent.isSelected ? MonitorThemes.shellColorForItem(page, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(page, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                                }

                                StyledText {
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.margins: 8
                                    text: modelData.displayName
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: parent.isSelected ? MonitorThemes.shellColorForItem(page, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(page, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
                                }

                                MouseArea {
                                    id: hoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Config.options.appearance.palette.type = modelData.value
                                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`])
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                visible: isMinimal
                Layout.topMargin: 20
                title: Translation.tr("Transparency")     
                GroupedList {
                    visible: isMinimal
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.appearance.transparency.enable
                        onCheckedChanged: { Config.options.appearance.transparency.enable = checked; }
                    }
                    ConfigSwitch {
                        buttonIcon: "autofps_select"
                        enabled: Config.options.appearance.transparency.enable
                        text: Translation.tr("Automatic")
                        checked: Config.options.appearance.transparency.automatic
                        onCheckedChanged: { Config.options.appearance.transparency.automatic = checked; }
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "devices"
                text: Translation.tr("Use monitor wallpaper colors")
                enabled: Config.hasDistinctMonitorWallpapers(false) || Config.hasDistinctMonitorWallpapers(true)
                checked: Config.options.background.useMonitorSpecificColors
                onCheckedChanged: Config.options.background.useMonitorSpecificColors = checked
            }
            ConfigSwitch {
                buttonIcon: "blender"
                text: Translation.tr("Blend monitor palettes")
                enabled: !Config.options.background.useMonitorSpecificColors
                    && (Config.hasDistinctMonitorWallpapers(false) || Config.hasDistinctMonitorWallpapers(true))
                checked: Config.options.background.blendMonitorColors
                onCheckedChanged: Config.options.background.blendMonitorColors = checked
            }
            ConfigComboBox {
                Layout.fillWidth: true
                enabled: !Config.options.background.useMonitorSpecificColors
                    && !Config.options.background.blendMonitorColors
                    && (Config.hasDistinctMonitorWallpapers(false) || Config.hasDistinctMonitorWallpapers(true))
                buttonIcon: "monitor"
                text: Translation.tr("Component color monitor")
                model: Quickshell.screens.map(screen => ({ displayName: screen.name, icon: "monitor", value: screen.name }))
                currentValue: Config.options.background.componentColorMonitor
                onSelected: newValue => Config.options.background.componentColorMonitor = newValue
            }
        }

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Bar & Screen")
            shape: MaterialShape.Shape.ClamShell
            Layout.fillWidth: true
            visible: isMinimal
            GroupedList {
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    Layout.preferredHeight: barPosCol.implicitHeight + 24

                    ColumnLayout {
                        id: barPosCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "swap_vert"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                            StyledText {
                                text: Translation.tr("Bar position")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: barPosArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                            onSelected: newValue => {
                                Config.options.bar.bottom = (newValue & 1) !== 0;
                                Config.options.bar.vertical = (newValue & 2) !== 0;
                            }
                            options: [
                                { displayName: Translation.tr("Top"), icon: "arrow_upward",   value: 0 },
                                { displayName: Translation.tr("Left"), icon: "arrow_back",     value: 2 },
                                { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                                { displayName: Translation.tr("Right"), icon: "arrow_forward",  value: 3 }
                            ]
                        }
                    }
                    options: [
                        { displayName: Translation.tr("Top"), icon: "arrow_upward",   value: 0 },
                        { displayName: Translation.tr("Left"), icon: "arrow_back",     value: 2 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Right"), icon: "arrow_forward",  value: 3 }
                    ]
                }
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    Layout.preferredHeight: barStyleCol.implicitHeight + 24

                    ColumnLayout {
                        id: barStyleCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "settop_component"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                            StyledText {
                                text: Translation.tr("Bar style")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: barStyleArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: Config.options.bar.cornerStyle
                            onSelected: newValue => { Config.options.bar.cornerStyle = newValue; }
                            options: [
                                { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                                { displayName: Translation.tr("Float"), icon: "view_day",   value: 1 },
                                { displayName: Translation.tr("Islands"), icon: "crop_3_2",   value: 2 },
                                { displayName: Translation.tr("M3"), icon: "interests",  value: 3 }
                            ]
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: screenRoundCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                    ColumnLayout {
                        id: groupStyleCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "tab_group"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                            StyledText {
                                text: Translation.tr("Group style")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: groupStyleArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: Config.options.bar.borderless
                            onSelected: newValue => { Config.options.bar.borderless = newValue; }
                            options: [
                                { displayName: Translation.tr("No"),          icon: "close",         value: "transparent" },
                                { displayName: Translation.tr("Pills"),     icon: "pill",          value: "pills" },
                                { displayName: Translation.tr("Separated"), icon: "view_column_2", value: "separated" }
                            ]
                        }
                    }
                    
                }
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    Layout.preferredHeight: groupStyleCol.implicitHeight + 24

                    ColumnLayout {
                        id: screenRoundCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "rounded_corner"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                            StyledText {
                                text: Translation.tr("Screen round corner")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: screenRoundArray
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight
                            currentValue: Config.options.appearance.fakeScreenRounding
                            onSelected: newValue => { Config.options.appearance.fakeScreenRounding = newValue; }
                            options: [
                                { displayName: Translation.tr("No"),                  icon: "close",           value: 0 },
                                { displayName: Translation.tr("Yes"),                 icon: "check",           value: 1 },
                                { displayName: Translation.tr("When not fullscreen"), icon: "fullscreen_exit", value: 2 }
                            ]
                        }
                    }
                    options: [
                        { displayName: Translation.tr("Top"), icon: "arrow_upward",   value: 0 },
                        { displayName: Translation.tr("Left"), icon: "arrow_back",     value: 2 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Right"), icon: "arrow_forward",  value: 3 }
                    ]
                }
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    icon: "settop_component"
                    text: Translation.tr("Bar style")
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => { Config.options.bar.cornerStyle = newValue; }
                    options: [
                        { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                        { displayName: Translation.tr("Float"), icon: "view_day",   value: 1 },
                        { displayName: Translation.tr("Islands"), icon: "crop_3_2",   value: 2 },
                        { displayName: Translation.tr("M3"), icon: "interests",  value: 3 },
                        { displayName: Translation.tr("Panel"), icon: "toolbar",  value: 4 }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Group style")
                    icon: "tab_group"
                    currentValue: Config.options.bar.borderless
                    onSelected: newValue => { Config.options.bar.borderless = newValue; }
                    options: [
                        { displayName: Translation.tr(""),          icon: "block",          value: "transparent" },
                        { displayName: Translation.tr("Pills"),     icon: "pill",           value: "pills" },
                        { displayName: Translation.tr("Separated"), icon: "view_column_2",  value: "separated" },
                        { displayName: Translation.tr("Segmented"), icon: "tablet",           value: "segmented" },
                    ]
                }
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    icon: "rounded_corner"
                    text: Translation.tr("Screen round corner")
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: newValue => { Config.options.appearance.fakeScreenRounding = newValue; }
                    options: [
                        { displayName: Translation.tr("No"),                  icon: "close",           value: 0 },
                        { displayName: Translation.tr("Yes"),                 icon: "check",           value: 1 },
                        { displayName: Translation.tr("When not fullscreen"), icon: "fullscreen_exit", value: 2 }
                    ]
                }
            }
        }
    }
}
