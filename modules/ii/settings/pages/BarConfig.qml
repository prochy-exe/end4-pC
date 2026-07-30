import QtQuick
import QtQuick.Layouts
import QtQml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Hyprland

ContentPage {
    id: page
    forceWidth: true
    property string selectedMonitorTab: ""
    readonly property var layoutKeys: ["leftLayout", "middleLayout", "rightLayout"]

    component MonitorConfigSwitch: ConfigSwitch {
        id: monitorSwitch
        required property var settingPath
        required property var fallbackValue

        Binding on checked {
            value: page.currentMonitorBarSetting(monitorSwitch.settingPath, monitorSwitch.fallbackValue)
        }

        onCheckedChanged: page.setCurrentMonitorBarSetting(settingPath, checked)
    }

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

    property var allWidgets: [
        { id: "leftSidebarButton", name: Translation.tr("Left Sidebar Button"),  icon: "left_panel_open" },
        { id: "workspaces",        name: Translation.tr("Workspaces"),           icon: "steppers" },
        { id: "weatherBar",        name: Translation.tr("Weather"),              icon: "flare" },
        { id: "media",             name: Translation.tr("Media"),                icon: "music_note" },
        { id: "resources",         name: Translation.tr("Resources"),            icon: "empty_dashboard" },
        { id: "systemIcons",       name: Translation.tr("System Icons"),         icon: "info" },
        { id: "networkSpeed",      name: Translation.tr("Network Speed"),        icon: "network_check" },
        { id: "clockWidget",       name: Translation.tr("Clock"),                icon: "schedule" },
        { id: "utilButtons",       name: Translation.tr("Util Buttons"),         icon: "toggle_on" },
        { id: "sysTray",           name: Translation.tr("Tray"),                 icon: "inbox" },
        { id: "batteryIndicator",  name: Translation.tr("Battery"),              icon: "battery_android_frame_full" },
        { id: "activeWindow",      name: Translation.tr("Active Window"),        icon: "subtitles" },
        { id: "powerButton",       name: Translation.tr("Power Button"),         icon: "power_settings_new" },
        { id: "updatesCount",      name: Translation.tr("Updates"),              icon: "deployed_code_update" },
        { id: "docktoPanel",       name: Translation.tr("Dock to Panel"),        icon: "apps" },
        { id: "visualizer",        name: Translation.tr("Visualizer (Output)"),  icon: "graphic_eq" },
        { id: "visualizerInput",   name: Translation.tr("Visualizer (Input)"),   icon: "mic" },
        { id: "hyprlandXkbIndicator",   name: Translation.tr("Keyboard Layout"), icon: "keyboard" },
        { id: "divisor",            name: Translation.tr("Divider"),             icon: "horizontal_distribute" },
    ]

    property var utilButtonActions: [
        { id: "screenSnip",              name: Translation.tr("Screen snip"),         icon: "screenshot_region" },
        { id: "colorPicker",             name: Translation.tr("Color picker"),        icon: "colorize" },
        { id: "screenRecord",            name: Translation.tr("Record Screen"),       icon: "screen_record" },
        { id: "recordingIndicator",      name: Translation.tr("Recording indicator"), icon: "radio_button_checked" },
        { id: "keyboardToggle",          name: Translation.tr("Keyboard toggle"),     icon: "keyboard" },
        { id: "wallpaperToggle",         name: Translation.tr("Wallpapers Toggle"),   icon: "imagesmode" },
        { id: "micToggle",               name: Translation.tr("Mic toggle"),          icon: "mic" },
        { id: "darkModeToggle",          name: Translation.tr("Dark/Light toggle"),   icon: "dark_mode" },
        { id: "performanceProfileToggle",name: Translation.tr("Performance Profile"), icon: "speed" },
    ]

    readonly property var knownUtilButtonActionOrder: utilButtonActions.map(action => action.id)

    function availableForLayouts(layouts) {
        let used = [
            ...layouts.leftLayout,
            ...layouts.middleLayout,
            ...layouts.rightLayout
        ]
        const multipleAllowed = ["divisor"]
        return allWidgets.filter(w => {
            if (w.id === "divisor" && page.currentMonitorBarSetting(["borderless"], Config.options.bar.borderless) !== "transparent") return false
            return !used.includes(w.id) || multipleAllowed.includes(w.id)
        })
    }

    function getWidgetName(id) {
        const w = allWidgets.find(w => w.id === id)
        return w ? w.name : id
    }

    function getUtilButtonActionName(id) {
        const action = utilButtonActions.find(a => a.id === id)
        return action ? action.name : id
    }

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

    function normalizedUtilButtonActionOrder(value) {
        const actions = page.toArray(value)
        return actions.filter(actionId => page.knownUtilButtonActionOrder.includes(actionId))
    }

    function legacyUtilButtonActions(monitorName) {
        let legacy = []
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showScreenSnip"], Config.options.bar.utilButtons.showScreenSnip)) legacy.push("screenSnip")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showColorPicker"], Config.options.bar.utilButtons.showColorPicker)) legacy.push("colorPicker")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showScreenRecord"], Config.options.bar.utilButtons.showScreenRecord)) legacy.push("screenRecord")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showScreenRecordingIndicator"], Config.options.bar.utilButtons.showScreenRecordingIndicator)) legacy.push("recordingIndicator")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showKeyboardToggle"], Config.options.bar.utilButtons.showKeyboardToggle)) legacy.push("keyboardToggle")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showWallpaperToggle"], Config.options.bar.utilButtons.showWallpaperToggle)) legacy.push("wallpaperToggle")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showMicToggle"], Config.options.bar.utilButtons.showMicToggle)) legacy.push("micToggle")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showDarkModeToggle"], Config.options.bar.utilButtons.showDarkModeToggle)) legacy.push("darkModeToggle")
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showPerformanceProfileToggle"], Config.options.bar.utilButtons.showPerformanceProfileToggle)) legacy.push("performanceProfileToggle")
        return legacy
    }

    function selectedUtilButtonActions() {
        const monitorName = page.selectedMonitorTab
        const monitorEntry = page.monitorSettingsEntry(monitorName)
        const monitorOrder = page.resolvePathValue(monitorEntry?.values ?? {}, ["utilButtons", "order"], undefined)
        if (monitorOrder !== undefined)
            return page.normalizedUtilButtonActionOrder(monitorOrder)

        const globalOrder = page.resolvePathValue(Config.options.bar, ["utilButtons", "order"], undefined)
        if (globalOrder !== undefined)
            return page.normalizedUtilButtonActionOrder(globalOrder)

        return page.legacyUtilButtonActions(monitorName)
    }

    function availableUtilButtonActions(layout) {
        const used = page.normalizedUtilButtonActionOrder(layout)
        return utilButtonActions.filter(action => !used.includes(action.id))
    }

    function enabledBarMonitorNames() {
        const allNames = Hyprland.monitors.values.map(m => m.name)
        const selected = Config.options.bar.screenList ?? []
        if (selected.length === 0) return allNames
        return allNames.filter(name => selected.includes(name))
    }

    function ensureSelectedMonitorTab() {
        const names = enabledBarMonitorNames()
        if (names.length === 0) {
            page.selectedMonitorTab = ""
            return
        }

        if (!names.includes(page.selectedMonitorTab))
            page.selectedMonitorTab = names[0]
    }

    function monitorSettingsEntry(monitorName) {
        return (Config.options.bar.monitorSettings ?? []).find(item => item.name === monitorName) ?? null
    }

    function resolvePathValue(target, path, fallbackValue) {
        let current = target
        for (let i = 0; i < path.length; i++) {
            if (current === undefined || current === null || !(path[i] in current))
                return fallbackValue
            current = current[path[i]]
        }
        return current
    }

    function setPathValue(target, path, value) {
        let current = target
        for (let i = 0; i < path.length - 1; i++) {
            const key = path[i]
            if (current[key] === undefined || current[key] === null || typeof current[key] !== "object") {
                current[key] = {}
            }
            current = current[key]
        }
        current[path[path.length - 1]] = value
        return target
    }

    function deletePathValue(target, path) {
        let current = target
        for (let i = 0; i < path.length - 1; i++) {
            if (current === undefined || current === null || !(path[i] in current))
                return false
            current = current[path[i]]
        }
        if (current === undefined || current === null || !(path[path.length - 1] in current))
            return false
        delete current[path[path.length - 1]]
        return true
    }

    function getMonitorBarSetting(monitorName, path, fallbackValue) {
        if (!monitorName) return fallbackValue
        const entry = page.monitorSettingsEntry(monitorName)
        const values = entry?.values ?? {}
        return page.resolvePathValue(values, path, fallbackValue)
    }

    function setMonitorBarSetting(monitorName, path, value) {
        if (!monitorName) return
        const fallbackValue = page.resolvePathValue(Config.options.bar, path, undefined)
        let settings = (Config.options.bar.monitorSettings ?? []).slice()
        const index = settings.findIndex(item => item.name === monitorName)
        let entry = index >= 0 ? Object.assign({}, settings[index]) : { name: monitorName, values: {} }
        let values = entry.values ? JSON.parse(JSON.stringify(entry.values)) : {}

        if (value === fallbackValue) {
            page.deletePathValue(values, path)
            if (Object.keys(values).length === 0) {
                if (index >= 0) settings.splice(index, 1)
                Config.options.bar.monitorSettings = settings
                return
            }
        } else {
            page.setPathValue(values, path, value)
        }

        entry.values = values
        if (index >= 0) settings[index] = entry
        else settings.push(entry)

        Config.options.bar.monitorSettings = settings
    }

    function currentMonitorBarSetting(path, fallbackValue) {
        return page.getMonitorBarSetting(page.selectedMonitorTab, path, fallbackValue)
    }

    function setCurrentMonitorBarSetting(path, value) {
        page.setMonitorBarSetting(page.selectedMonitorTab, path, value)
    }

    function copyCurrentMonitorSettingsToAll() {
        if (!page.selectedMonitorTab) return
        const entry = page.monitorSettingsEntry(page.selectedMonitorTab)
        const values = entry?.values ? JSON.parse(JSON.stringify(entry.values)) : {}
        const monitors = page.enabledBarMonitorNames()
        let settings = (Config.options.bar.monitorSettings ?? []).slice()

        monitors.forEach(name => {
            if (name === page.selectedMonitorTab) return
            const index = settings.findIndex(item => item.name === name)
            const newEntry = { name, values: JSON.parse(JSON.stringify(values)) }
            if (index >= 0) settings[index] = newEntry
            else settings.push(newEntry)
        })

        Config.options.bar.monitorSettings = settings
    }

    function monitorLayoutEntry(monitorName) {
        return (Config.options.bar.monitorLayouts ?? []).find(item => item.name === monitorName) ?? null
    }

    function layoutForMonitor(monitorName, layoutKey) {
        const entry = monitorLayoutEntry(monitorName)
        const override = entry?.[layoutKey]
        return override !== undefined ? override : Config.options.bar.layouts[layoutKey]
    }

    function selectedMonitorLayouts() {
        return {
            leftLayout: layoutForMonitor(page.selectedMonitorTab, "leftLayout"),
            middleLayout: layoutForMonitor(page.selectedMonitorTab, "middleLayout"),
            rightLayout: layoutForMonitor(page.selectedMonitorTab, "rightLayout"),
        }
    }

    function arraysEqual(a, b) {
        if (a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false
        }
        return true
    }

    function normalizeMonitorLayoutEntry(entry) {
        for (let i = 0; i < page.layoutKeys.length; i++) {
            const key = page.layoutKeys[i]
            if (entry[key] !== undefined && arraysEqual(entry[key], Config.options.bar.layouts[key]))
                delete entry[key]
        }

        return page.layoutKeys.some(key => entry[key] !== undefined)
    }

    function setSelectedMonitorLayout(layoutKey, list) {
        if (page.selectedMonitorTab.length === 0) return

        let layouts = (Config.options.bar.monitorLayouts ?? []).slice()
        const index = layouts.findIndex(item => item.name === page.selectedMonitorTab)
        let entry = index >= 0 ? Object.assign({}, layouts[index]) : { name: page.selectedMonitorTab }

        entry[layoutKey] = list.slice()

        if (normalizeMonitorLayoutEntry(entry)) {
            if (index >= 0) layouts[index] = entry
            else layouts.push(entry)
        } else if (index >= 0) {
            layouts.splice(index, 1)
        }

        Config.options.bar.monitorLayouts = layouts
    }

    function clearSelectedMonitorLayoutOverride() {
        if (page.selectedMonitorTab.length === 0) return
        Config.options.bar.monitorLayouts = (Config.options.bar.monitorLayouts ?? []).filter(item => item.name !== page.selectedMonitorTab)
    }

    Component.onCompleted: ensureSelectedMonitorTab()

    Item {
        id: stickyMonitorTabs
        parent: page
        z: 1000
        visible: page.enabledBarMonitorNames().length > 0
        width: Math.min(page.baseWidth, page.width - 24)
        height: 48
        x: (page.width - width) / 2
        y: 8

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        SecondaryTabBar {
            id: stickyTabBar
            anchors.fill: parent
            anchors.margins: 2
            allowWheelSwitch: false
            currentIndex: Math.max(0, page.enabledBarMonitorNames().indexOf(page.selectedMonitorTab))

            Repeater {
                model: page.enabledBarMonitorNames()
                delegate: SecondaryTabButton {
                    required property string modelData
                    buttonText: modelData
                    checked: page.selectedMonitorTab === modelData
                    onClicked: page.selectedMonitorTab = modelData
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        Item {
            Layout.fillWidth: true
            implicitHeight: stickyMonitorTabs.visible ? stickyMonitorTabs.height + 8 : 0
        }

        ContentSection {
            icon: "tv_options_edit_channels"
            shape: MaterialShape.Shape.ClamShell
            title: Translation.tr("Monitor-specific layout")
            visible: page.enabledBarMonitorNames().length > 0

            onVisibleChanged: if (visible) page.ensureSelectedMonitorTab()

            ContentSubsection {
                title: Translation.tr("Override layout per monitor")

                ConfigRow {
                    uniform: false
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Configure bar layout for the selected monitor.")
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                    }

                    RippleButtonWithIcon {
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Reset")
                        onClicked: page.clearSelectedMonitorLayoutOverride()
                    }

                    RippleButtonWithIcon {
                        materialIcon: "sync"
                        mainText: Translation.tr("Copy to all")
                        visible: page.enabledBarMonitorNames().length > 1
                        onClicked: page.copyCurrentMonitorSettingsToAll()
                    }
                }

                GroupedList {
                    LayoutSection {
                        sectionTitle: page.currentMonitorBarSetting(["vertical"], Config.options.bar.vertical) ? Translation.tr("Top") : Translation.tr("Left")
                        layout: page.selectedMonitorLayouts().leftLayout
                        availableWidgets: page.availableForLayouts(page.selectedMonitorLayouts())
                        getWidgetName: page.getWidgetName
                        onUpdate: list => page.setSelectedMonitorLayout("leftLayout", list)
                    }

                    LayoutSection {
                        sectionTitle: Translation.tr("Center")
                        layout: page.selectedMonitorLayouts().middleLayout
                        availableWidgets: page.availableForLayouts(page.selectedMonitorLayouts())
                        getWidgetName: page.getWidgetName
                        onUpdate: list => page.setSelectedMonitorLayout("middleLayout", list)
                    }

                    LayoutSection {
                        sectionTitle: page.currentMonitorBarSetting(["vertical"], Config.options.bar.vertical) ? Translation.tr("Bottom") : Translation.tr("Right")
                        layout: page.selectedMonitorLayouts().rightLayout
                        availableWidgets: page.availableForLayouts(page.selectedMonitorLayouts())
                        getWidgetName: page.getWidgetName
                        onUpdate: list => page.setSelectedMonitorLayout("rightLayout", list)
                    }
                }
            }
        }

        ContentSection {
            icon: "pivot_table_chart"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Positioning & Styles")
            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Bar position")
                    icon: "swap_vert"
                    currentValue: (page.currentMonitorBarSetting(["bottom"], Config.options.bar.bottom) ? 1 : 0) | (page.currentMonitorBarSetting(["vertical"], Config.options.bar.vertical) ? 2 : 0)
                    onSelected: newValue => {
                        page.setCurrentMonitorBarSetting(["bottom"], (newValue & 1) !== 0);
                        page.setCurrentMonitorBarSetting(["vertical"], (newValue & 2) !== 0);
                    }
                    options: [
                        { displayName: Translation.tr("Top"),    icon: "arrow_upward",   value: 0 },
                        { displayName: Translation.tr("Left"),   icon: "arrow_back",     value: 2 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Right"),  icon: "arrow_forward",  value: 3 }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Bar style")
                    icon: "style"
                    currentValue: page.currentMonitorBarSetting(["cornerStyle"], Config.options.bar.cornerStyle)
                    onSelected: newValue => { page.setCurrentMonitorBarSetting(["cornerStyle"], newValue); }
                    options: [
                        { displayName: Translation.tr("Hug"),     icon: "line_curve", value: 0 },
                        { displayName: Translation.tr("Float"),   icon: "view_day",   value: 1 },
                        { displayName: Translation.tr("Islands"), icon: "crop_3_2",   value: 2 },
                        { displayName: Translation.tr("M3"), icon: "interests",   value: 3 }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Group style")
                    icon: "tab_group"
                    currentValue: page.currentMonitorBarSetting(["borderless"], Config.options.bar.borderless)
                    onSelected: newValue => { page.setCurrentMonitorBarSetting(["borderless"], newValue); }
                    options: [
                        { displayName: Translation.tr(""),          icon: "block",          value: "transparent" },
                        { displayName: Translation.tr("Pills"),     icon: "pill",           value: "pills" },
                        { displayName: Translation.tr("Separated"), icon: "view_column_2",  value: "separated" }
                    ]
                }
                ConfigRow{
                    uniform: true
                    MonitorConfigSwitch {
                        buttonIcon: "variable_insert"
                        text: Translation.tr("Show Background")
                        settingPath: ["showBackground"]
                        fallbackValue: Config.options.bar.showBackground
                        enabled: page.currentMonitorBarSetting(["cornerStyle"], Config.options.bar.cornerStyle) === 0 || page.currentMonitorBarSetting(["cornerStyle"], Config.options.bar.cornerStyle) === 1
                    }
                    ConfigSelectionArray {
                        text: Translation.tr("Autohide")
                        icon: "preview_off"
                        currentValue: page.currentMonitorBarSetting(["autoHide", "enable"], Config.options.bar.autoHide.enable)
                        onSelected: newValue => { page.setCurrentMonitorBarSetting(["autoHide", "enable"], newValue); }
                        options: [
                            { displayName: Translation.tr("No"),  icon: "close", value: false },
                            { displayName: Translation.tr("Yes"), icon: "check", value: true }
                        ]
                    }
                }
            }
        }

        ContentSection {
            shape: MaterialShape.Shape.Square
            icon: "inbox_customize"
            title: Translation.tr("Tray")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "keep"; text: Translation.tr("Make icons pinned by default")
                    checked: Config.options.tray.invertPinnedItems
                    onCheckedChanged: { Config.options.tray.invertPinnedItems = checked; }
                }
                ConfigSwitch {
                    buttonIcon: "colors"; text: Translation.tr("Tint icons")
                    checked: Config.options.tray.monochromeIcons
                    onCheckedChanged: { Config.options.tray.monochromeIcons = checked; }
                }
            }
        }

        ContentSection {
            icon: "vertical_align_center"
            shape: MaterialShape.Shape.Diamond
            title: Translation.tr("Divider")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: page.currentMonitorBarSetting(["divider", "style"], Config.options.bar.divider.style)
                    onSelected: newValue => { page.setCurrentMonitorBarSetting(["divider", "style"], newValue); }
                    options: [
                        { displayName: Translation.tr("Line"),  icon: "more_vert",       value: "rect" },
                        { displayName: Translation.tr("Dot"),   icon: "fiber_manual_record", value: "dot" },
                        { displayName: Translation.tr("Space"), icon: "space_bar",       value: "space" }
                    ]
                }
                ConfigSpinBox {
                    icon: "width"
                    enabled: page.currentMonitorBarSetting(["divider", "style"], Config.options.bar.divider.style) === "space"
                    text: Translation.tr("Space width (px)")
                    value: page.currentMonitorBarSetting(["divider", "spacing"], Config.options.bar.divider.spacing)
                    from: 4
                    to: 100
                    stepSize: 2
                    onValueChanged: {
                        page.setCurrentMonitorBarSetting(["divider", "spacing"], value);
                    }
                }
            }
        }

        ContentSection {
            icon: "buttons_alt"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Utility buttons")

            GroupedList {
                LayoutSection {
                    sectionTitle: Translation.tr("Actions")
                    layout: page.selectedUtilButtonActions()
                    availableWidgets: page.availableUtilButtonActions(layout)
                    getWidgetName: page.getUtilButtonActionName
                    onUpdate: list => {
                        if (page.selectedMonitorTab)
                            page.setCurrentMonitorBarSetting(["utilButtons", "order"], list)
                        else
                            Config.options.bar.utilButtons.order = list
                    }
                }
            }
        }

        ContentSection {
            shape: MaterialShape.Shape.Cookie12Sided
            icon: "steppers"; title: Translation.tr("Workspaces")
            GroupedList {
                MonitorConfigSwitch {
                    buttonIcon: "counter_1"; text: Translation.tr("Always show numbers")
                    settingPath: ["workspaces", "alwaysShowNumbers"]
                    fallbackValue: Config.options.bar.workspaces.alwaysShowNumbers
                }
                ConfigSelectionArray {
                    text: Translation.tr("Numbers style")
                    icon: "looks_3"
                    currentValue: JSON.stringify(page.currentMonitorBarSetting(["workspaces", "numberMap"], Config.options.bar.workspaces.numberMap))
                    onSelected: newValue => {
                        page.setCurrentMonitorBarSetting(["workspaces", "numberMap"], JSON.parse(newValue))
                    }
                    options: [
                        { displayName: Translation.tr("Normal"),    icon: "timer_10",        value: '[]' },
                        { displayName: Translation.tr("Han chars"), icon: "glyphs",          value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]' },
                        { displayName: Translation.tr("Roman"),     icon: "account_balance", value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]' }
                    ]
                }
                MonitorConfigSwitch {
                    buttonIcon: "award_star"; text: Translation.tr("Show app icons")
                    settingPath: ["workspaces", "showAppIcons"]
                    fallbackValue: Config.options.bar.workspaces.showAppIcons
                }
                ConfigSpinBox {
                    icon: "view_column"; text: Translation.tr("Workspaces shown")
                    value: page.currentMonitorBarSetting(["workspaces", "shown"], Config.options.bar.workspaces.shown)
                    from: 1; to: 30
                    onValueChanged: { page.setCurrentMonitorBarSetting(["workspaces", "shown"], value); }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Indicator style")
                    icon: "page_control"
                    currentValue: page.currentMonitorBarSetting(["workspaces", "indicatorStyle"], Config.options.bar.workspaces.indicatorStyle ?? "icon")
                    onSelected: newValue => {
                        page.setCurrentMonitorBarSetting(["workspaces", "indicatorStyle"], newValue)
                    }
                    options: [
                        { displayName: Translation.tr("Dots"),  icon: "radio_button_checked",   value: "dot" },
                        { displayName: Translation.tr("Icons"), icon: "interests",              value: "icon" },
                    ]
                }
            }
        }

        ContentSection {
            icon: "empty_dashboard"
            shape: MaterialShape.Shape.Burst
            title: Translation.tr("Resources")

            GroupedList {
                ConfigRow {
                    uniform: true
                    MonitorConfigSwitch {
                        buttonIcon: "planner_review"
                        text: Translation.tr("CPU")
                        settingPath: ["resources", "alwaysShowCpu"]
                        fallbackValue: Config.options.bar.resources.alwaysShowCpu
                    }
                    MonitorConfigSwitch {
                        buttonIcon: "thermostat"
                        text: Translation.tr("CPU Temperature")
                        settingPath: ["resources", "alwaysShowCpuTemp"]
                        fallbackValue: Config.options.bar.resources.alwaysShowCpuTemp
                    }
                }
                ConfigRow {
                    uniform: true
                    MonitorConfigSwitch {
                        buttonIcon: "memory"
                        text: Translation.tr("RAM")
                        settingPath: ["resources", "alwaysShowRam"]
                        fallbackValue: Config.options.bar.resources.alwaysShowRam
                    }
                    MonitorConfigSwitch {
                        buttonIcon: "storage"
                        text: Translation.tr("Disk")
                        settingPath: ["resources", "alwaysShowDisk"]
                        fallbackValue: Config.options.bar.resources.alwaysShowDisk
                    }
                }
                ConfigRow {
                    uniform: true
                    MonitorConfigSwitch {
                        buttonIcon: "swap_horiz"
                        text: Translation.tr("Swap")
                        settingPath: ["resources", "alwaysShowSwap"]
                        fallbackValue: Config.options.bar.resources.alwaysShowSwap
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: page.currentMonitorBarSetting(["resources", "style"], Config.options.bar.resources.style)
                    onSelected: newValue => { page.setCurrentMonitorBarSetting(["resources", "style"], newValue); }
                    options: [
                        { displayName: Translation.tr("Filled"),    icon: "incomplete_circle",  value: "filled" },
                        { displayName: Translation.tr("Outline"),   icon: "circles",            value: "outline" }
                    ]
                }
                MonitorConfigSwitch {
                    buttonIcon: "decimal_increase"; text: Translation.tr("Show Percentage")
                    settingPath: ["resources", "showValue"]
                    fallbackValue: Config.options.bar.resources.showValue
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (ms)")
                    value: Config.options.resources.updateInterval
                    from: 100
                    to: 10000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.resources.updateInterval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "music_note"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Media")

            GroupedList {
                ConfigTextArea {
                    id: preferredPlayerField
                    Layout.fillWidth: true
                    buttonIcon: "play_circle"
                    text: Translation.tr("Preferred Player")
                    placeholderText: Translation.tr("e.g. spotify, firefox")
                    value: page.currentMonitorBarSetting(["media", "preferredPlayer"], Config.options.bar.media.preferredPlayer)
                    onValueChanged: {
                        mediaDebounceTimer.restart();
                    }

                    Timer {
                        id: mediaDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            page.setCurrentMonitorBarSetting(["media", "preferredPlayer"], preferredPlayerField.value);
                        }
                    }
                }
                MonitorConfigSwitch {
                    buttonIcon: "keep"; text: Translation.tr("Pin media controls")
                    settingPath: ["media", "alwaysVisible"]
                    fallbackValue: Config.options.bar.media.alwaysVisible
                }
                MonitorConfigSwitch {
                    buttonIcon: "titlecase"; text: Translation.tr("Show only title")
                    settingPath: ["media", "onlyTitle"]
                    fallbackValue: Config.options.bar.media.onlyTitle
                }
                ConfigSpinBox {
                    icon: "width"
                    text: Translation.tr("Max media width")
                    value: page.currentMonitorBarSetting(["media", "maxWidth"], Config.options.bar.media.maxWidth)
                    from: 100
                    to: 500
                    stepSize: 10
                    onValueChanged: {
                        page.setCurrentMonitorBarSetting(["media", "maxWidth"], value);
                    }
                }
            }
        }

        ContentSection {
            shape: MaterialShape.Shape.Puffy
            icon: "tooltip"; title: Translation.tr("Tooltips")
            GroupedList {
                MonitorConfigSwitch {
                    buttonIcon: "ads_click"; text: Translation.tr("Click to show")
                    settingPath: ["tooltips", "clickToShow"]
                    fallbackValue: Config.options.bar.tooltips.clickToShow
                }
            }
        }
    }
}