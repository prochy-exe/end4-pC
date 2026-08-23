import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.monitorPreview
import qs.modules.common.models.hyprland
import Quickshell.Hyprland

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
    property string selectedMonitorTab: ""
    // Whether the user has ever manually picked a monitor (clicked a tab or
    // the canvas). Until then, ensureSelectedMonitorTab() keeps preferring
    // the primary monitor as monitors trickle in from Hyprland's IPC list -
    // without this, the first monitor to appear (not necessarily the
    // primary) would get locked in as soon as it made the list "valid".
    property bool monitorTabUserPicked: false
    // Single shared "which monitor is selected" index, derived from
    // selectedMonitorTab so Displays, Monitor-specific layout, Positioning &
    // Styles and the merged MonitorSetupCanvas below all agree on one
    // selection - clicking a monitor in the canvas or a tab in the sticky
    // strip both just write selectedMonitorTab, and everything else follows.
    readonly property int selectedMonitorIndex: monitorConfig.monitors.findIndex(m => m.name === page.selectedMonitorTab)
    readonly property var layoutKeys: ["leftLayout", "middleLayout", "rightLayout"]

    component MonitorConfigSwitch: ConfigSwitch {
        id: monitorSwitch
        required property var settingPath
        required property var fallbackValue

        Binding on checked {
            value: page.currentMonitorBarSetting(monitorSwitch.settingPath, monitorSwitch.fallbackValue)
        }

        onClicked: {
            page.setCurrentMonitorBarSetting(settingPath, checked)
        }
    }

    component CustomResourceRow: ColumnLayout {
        id: row
        required property var entry
        spacing: 6

        function commitPatch(patch) {
            page.updateCustomResource(row.entry.id, patch)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                text: (CustomBarResources.isRunning(row.entry.id) ? row.entry.iconOn : row.entry.iconOff) || "help"
                iconSize: Appearance.font.pixelSize.large
                color: MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary)
            }
            StyledText {
                Layout.fillWidth: true
                text: (row.entry.name ?? "").length > 0 ? row.entry.name : Translation.tr("(unnamed)")
                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
            }
            RippleButton {
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                implicitWidth: 28
                implicitHeight: 28
                onClicked: page.removeCustomResource(row.entry.id)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                }
            }
        }

        ConfigTextArea {
            Layout.fillWidth: true
            buttonIcon: "label"
            text: Translation.tr("Name")
            fieldWidth: 220
            Component.onCompleted: value = row.entry.name ?? ""
            onFocusLost: row.commitPatch({ name: value })
        }

        ConfigSelectionArray {
            text: Translation.tr("Mode")
            icon: "tune"
            currentValue: row.entry.mode
            onSelected: newValue => page.updateCustomResource(row.entry.id, { mode: newValue })
            options: [
                { displayName: Translation.tr("Command"), icon: "terminal", value: "command" },
                { displayName: Translation.tr("Systemd service"), icon: "settings_applications", value: "service" }
            ]
        }

        ConfigTextArea {
            Layout.fillWidth: true
            visible: row.entry.mode === "command"
            buttonIcon: "terminal"
            text: Translation.tr("Command")
            placeholderText: Translation.tr("Shell command to keep running while on")
            fieldWidth: 220
            Component.onCompleted: value = row.entry.command ?? ""
            onFocusLost: row.commitPatch({ command: value })
        }

        ConfigTextArea {
            Layout.fillWidth: true
            visible: row.entry.mode === "service"
            buttonIcon: "settings_applications"
            text: Translation.tr("Service name")
            placeholderText: Translation.tr("e.g. syncthing (systemctl --user)")
            fieldWidth: 220
            confirmButtonVisible: true
            confirmButtonIcon: "search"
            Component.onCompleted: value = row.entry.serviceName ?? ""
            onFocusLost: row.commitPatch({ serviceName: value })
            onConfirmClicked: page.openServicePicker(row.entry.id)
        }

        ConfigTextArea {
            Layout.fillWidth: true
            buttonIcon: (row.entry.iconOn ?? "").length > 0 ? row.entry.iconOn : "check_circle"
            text: Translation.tr("Icon (on)")
            placeholderText: Translation.tr("Material Symbol name, e.g. wifi")
            fieldWidth: 180
            confirmButtonVisible: true
            confirmButtonIcon: "search"
            Component.onCompleted: value = row.entry.iconOn ?? ""
            onFocusLost: row.commitPatch({ iconOn: value })
            onConfirmClicked: page.openIconPicker(row.entry.id, "iconOn")
        }

        ConfigTextArea {
            Layout.fillWidth: true
            buttonIcon: (row.entry.iconOff ?? "").length > 0 ? row.entry.iconOff : "circle"
            text: Translation.tr("Icon (off)")
            placeholderText: Translation.tr("Material Symbol name, e.g. wifi_off")
            fieldWidth: 180
            confirmButtonVisible: true
            confirmButtonIcon: "search"
            Component.onCompleted: value = row.entry.iconOff ?? ""
            onFocusLost: row.commitPatch({ iconOff: value })
            onConfirmClicked: page.openIconPicker(row.entry.id, "iconOff")
        }
    }
    component MediaElementSwitch: ConfigSwitch {
        id: elementSwitch
        required property string configKey
        required property string elementId
        checked: (Config.options.media[configKey] ?? []).includes(elementId)
        onCheckedChanged: {
            let list = (Config.options.media[configKey] ?? []).slice()
            if (checked) {
                if (!list.includes(elementId)) list.push(elementId)
            } else {
                list = list.filter(id => id !== elementId)
            }
            Config.options.media[configKey] = list
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
        { id: "keychronIndicator", name: Translation.tr("Keychron Devices"),    icon: "devices" },
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
        { id: "caffeineToggle",          name: Translation.tr("Caffeine / Idle inhibitor"), icon: "coffee" },
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

    function audioNodeName(node) {
        return (node?.name ?? "").trim()
    }

    // qs-audiotap can attach to one application's PipeWire stream, so the output
    // picker is no longer just a device list. Values are "auto" (follow whatever
    // is playing), "app:<name>" (pin to an application) or a device node name.
    function outputVisualizerSourceOptions(devices, currentValue, autoLabel) {
        const options = [{ displayName: autoLabel, icon: "auto_mode", value: "auto" }]
        const seen = new Set(["auto"])

        for (let i = 0; i < (MprisController.players ?? []).length; i++) {
            const name = (MprisController.players[i]?.identity ?? "").trim()
            if (name.length === 0)
                continue
            const value = `app:${name}`
            if (seen.has(value))
                continue
            seen.add(value)
            options.push({
                displayName: Translation.tr("App: %1").arg(name),
                icon: "music_note",
                value: value
            })
        }

        for (let i = 0; i < devices.length; i++) {
            const node = devices[i]
            const sourceName = page.audioNodeName(node)
            if (!sourceName || seen.has(sourceName))
                continue
            const monitorSource = sourceName.endsWith(".monitor") ? sourceName : `${sourceName}.monitor`
            if (seen.has(monitorSource))
                continue
            seen.add(monitorSource)
            options.push({
                displayName: Translation.tr("Device: %1").arg(Audio.friendlyDeviceName(node)),
                icon: "speaker",
                value: monitorSource
            })
        }

        const normalizedCurrent = (currentValue ?? "auto").toString().trim()
        if (normalizedCurrent.length > 0 && !seen.has(normalizedCurrent)) {
            options.push({
                displayName: Translation.tr("Custom (%1)").arg(normalizedCurrent),
                value: normalizedCurrent
            })
        }

        return options
    }

    function inputVisualizerSourceOptions(devices, currentValue, autoLabel) {
        const options = [{ displayName: autoLabel, value: "auto" }]
        const seen = new Set(["auto"])

        for (let i = 0; i < devices.length; i++) {
            const node = devices[i]
            const sourceName = page.audioNodeName(node)
            if (!sourceName || sourceName.endsWith(".monitor") || seen.has(sourceName))
                continue
            seen.add(sourceName)
            options.push({
                displayName: Audio.friendlyDeviceName(node),
                value: sourceName
            })
        }

        const normalizedCurrent = (currentValue ?? "auto").toString().trim()
        if (normalizedCurrent.length > 0 && !seen.has(normalizedCurrent)) {
            options.push({
                displayName: Translation.tr("Custom (%1)").arg(normalizedCurrent),
                value: normalizedCurrent
            })
        }

        return options
    }

    readonly property var visualizerOutputSourceOptions: page.outputVisualizerSourceOptions(
        Audio.outputDevices,
        Config.options.bar.visualizer.outputSource,
        Translation.tr("Auto (follow the playing app)")
    )

    readonly property var visualizerInputSourceOptions: page.inputVisualizerSourceOptions(
        Audio.inputDevices,
        Config.options.bar.visualizer.inputSource,
        Translation.tr("Auto (default input)")
    )

    readonly property real visualizerComboWidth: Math.max(220, Math.min(520, page.baseWidth * 0.55))

    function resolvedOutputVisualizerSource() {
        const source = (Config.options.bar.visualizer.outputSource ?? "auto").toString().trim()
        if (source.startsWith("app:"))
            return Translation.tr("application \"%1\"").arg(source.slice(4))
        if (source.length > 0 && source !== "auto")
            return source
        const playing = (MprisController.players ?? []).find(p => p?.isPlaying)
        if (playing)
            return Translation.tr("application \"%1\" (playing)").arg(playing.identity ?? "")
        const sinkName = (Audio.sink?.name ?? "").trim()
        return sinkName.length > 0 ? sinkName : Translation.tr("default output")
    }

    function fallbackInputCaptureSource() {
        const defaultName = (Audio.source?.name ?? "").trim()
        if (defaultName.length > 0 && !defaultName.endsWith(".monitor"))
            return defaultName
        const fallback = Audio.inputDevices.find(node => {
            const name = (node?.name ?? "").trim()
            return name.length > 0 && !name.endsWith(".monitor")
        })
        const fallbackName = (fallback?.name ?? "").trim()
        return fallbackName.length > 0 ? fallbackName : "auto"
    }

    function resolvedInputVisualizerSource() {
        let source = (Config.options.bar.visualizer.inputSource ?? "auto").toString().trim()
        if (source.length === 0 || source === "auto")
            source = page.fallbackInputCaptureSource()
        if (source.endsWith(".monitor"))
            source = page.fallbackInputCaptureSource()
        return source
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
        if (page.getMonitorBarSetting(monitorName, ["utilButtons", "showCaffeineToggle"], Config.options.bar.utilButtons.showCaffeineToggle)) legacy.push("caffeineToggle")
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

        const alreadyValid = names.includes(page.selectedMonitorTab)
        // Before any manual pick, keep re-preferring the primary monitor
        // even if the current auto-selection is still technically valid -
        // Hyprland's monitor list can populate one monitor at a time, and
        // the primary one isn't guaranteed to be first. Once the user has
        // clicked a monitor themselves, only step in if their pick actually
        // disappeared (e.g. that monitor got disconnected).
        if (page.monitorTabUserPicked && alreadyValid) return

        const primary = Config.options.hyprland.primaryMonitor ?? ""
        page.selectedMonitorTab = names.includes(primary) ? primary : names[0]
    }

    function monitorSettingsEntry(monitorName) {
        return (Config.options.bar.monitorSettings ?? []).find(item => item.name === monitorName) ?? null
    }

    function generateCustomResourceId() {
        return "cr_" + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36)
    }

    function addCustomResource() {
        const list = (Config.options.bar.customResources ?? []).slice()
        list.push({
            id: page.generateCustomResourceId(),
            name: Translation.tr("New resource"),
            mode: "command",
            command: "",
            serviceName: "",
            serviceScope: "user",
            iconOn: "check_circle",
            iconOff: "circle"
        })
        Config.options.bar.customResources = list
    }

    function updateCustomResource(id, patch) {
        Config.options.bar.customResources = (Config.options.bar.customResources ?? [])
            .map(entry => entry.id === id ? Object.assign({}, entry, patch) : entry)
    }

    function removeCustomResource(id) {
        Config.options.bar.customResources = (Config.options.bar.customResources ?? []).filter(entry => entry.id !== id)
    }

    // Shared icon-picker dialog state for Custom Utility Buttons' Icon
    // (on)/(off) fields - one dialog instance for every row rather than one
    // per field, tracking which entry/field it's currently picking for.
    property bool iconPickerOpen: false
    property var iconPickerTarget: null
    function openIconPicker(entryId, field) {
        page.iconPickerTarget = { entryId, field }
        page.iconPickerOpen = true
    }

    property bool servicePickerOpen: false
    property string servicePickerTarget: ""
    function openServicePicker(entryId) {
        page.servicePickerTarget = entryId
        page.servicePickerOpen = true
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
        if (page.selectedMonitorTab) {
            page.setMonitorBarSetting(page.selectedMonitorTab, path, value)
            return
        }

        // Fallback: if monitor selection is unavailable, apply globally instead of no-op.
        page.setPathValue(Config.options.bar, path, value)
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

    function copySelectedMonitorLayoutToAll() {
        if (!page.selectedMonitorTab) return
        const source = page.monitorLayoutEntry(page.selectedMonitorTab)
        const sourceLeft = source?.leftLayout ?? Config.options.bar.layouts.leftLayout
        const sourceMiddle = source?.middleLayout ?? Config.options.bar.layouts.middleLayout
        const sourceRight = source?.rightLayout ?? Config.options.bar.layouts.rightLayout
        const monitors = page.enabledBarMonitorNames()

        let layouts = (Config.options.bar.monitorLayouts ?? []).filter(item => monitors.includes(item.name))

        monitors.forEach(name => {
            if (name === page.selectedMonitorTab) return
            const index = layouts.findIndex(item => item.name === name)
            const entry = {
                name,
                leftLayout: sourceLeft.slice(),
                middleLayout: sourceMiddle.slice(),
                rightLayout: sourceRight.slice(),
            }
            page.normalizeMonitorLayoutEntry(entry)
            if (index >= 0) layouts[index] = entry
            else layouts.push(entry)
        })

        Config.options.bar.monitorLayouts = layouts
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

    Connections {
        target: Hyprland.monitors
        function onValuesChanged() {
            page.ensureSelectedMonitorTab()
        }
    }
    function setPrimaryWorkspaceStart(value) {
        const start = Math.max(1, Math.min(value, Config.options.hyprland.primaryWorkspaceEnd))
        if (start === Config.options.hyprland.primaryWorkspaceStart) return
        Config.options.hyprland.primaryWorkspaceStart = start
        monitorConfig.save()
    }

    function setPrimaryWorkspaceEnd(value) {
        const end = Math.min(100, Math.max(value, Config.options.hyprland.primaryWorkspaceStart))
        if (end === Config.options.hyprland.primaryWorkspaceEnd) return
        Config.options.hyprland.primaryWorkspaceEnd = end
        monitorConfig.save()
    }
    function ensureSpecificMonitor(getCurrent, setCurrent) {
        const names = PopupPlacement.availableMonitorNames()
        if (names.length === 0) return
        if (!names.includes(getCurrent())) setCurrent(names[0])
    }

    // Triggers the ticker, OSD and a real notification through the exact
    // same IPC/D-Bus paths the actual hotkeys and events use - not an
    // approximation, so what appears here is guaranteed identical to real
    // usage.
    function previewAll() {
        Quickshell.execDetached(["bash", "-c", "pid=$(pgrep -x qs | head -n1) && qs ipc --pid \"$pid\" call mediaTicker trigger"])
        Quickshell.execDetached(["bash", "-c", "pid=$(pgrep -x qs | head -n1) && qs ipc --pid \"$pid\" call osdVolume trigger"])
        Quickshell.execDetached(["notify-send", Translation.tr("Preview"), Translation.tr("This is what a real notification looks like."), "-a", "Shell"])
    }

    function resetToDefaults() {
        Config.options.media.tickerPosition = "bar"
        Config.options.media.tickerMonitorMode = "focused"
        Config.options.media.tickerMonitorName = ""
        Config.options.media.tickerCustomX = 0.5
        Config.options.media.tickerCustomY = 0.5
        Config.options.media.tickerCustomAnchor = "top"

        Config.options.notifications.position = "top_right"
        Config.options.notifications.monitorMode = "focused"
        Config.options.notifications.monitorName = ""
        Config.options.notifications.customX = 0.7
        Config.options.notifications.customY = 0.7
        Config.options.notifications.customAnchor = "top"

        Config.options.osd.position = "bar"
        Config.options.osd.monitorMode = "focused"
        Config.options.osd.monitorName = ""
        Config.options.osd.customX = 0.5
        Config.options.osd.customY = 0.5
        Config.options.osd.customAnchor = "top"
    }

    readonly property var positionModel: [
        { displayName: Translation.tr("Top left"), value: "top_left" },
        { displayName: Translation.tr("Top center"), value: "top_center" },
        { displayName: Translation.tr("Top right"), value: "top_right" },
        { displayName: Translation.tr("Center left"), value: "center_left" },
        { displayName: Translation.tr("Center"), value: "center" },
        { displayName: Translation.tr("Center right"), value: "center_right" },
        { displayName: Translation.tr("Bottom left"), value: "bottom_left" },
        { displayName: Translation.tr("Bottom center"), value: "bottom_center" },
        { displayName: Translation.tr("Bottom right"), value: "bottom_right" },
        { displayName: Translation.tr("Custom (set via live editor)"), value: "custom" },
    ]
    readonly property var positionModelWithBar: [{ displayName: Translation.tr("Follow bar"), value: "bar" }].concat(page.positionModel)
    // Fed to the shared MonitorSetupCanvas below (used to be Popup
    // positions' own inline items: [...] on a now-removed MonitorPreviewCanvas
    // - lifted to the page root since the one merged canvas lives up in
    // Displays now, not down next to these sections anymore).
    readonly property var popupPreviewItems: [
        {
            id: "ticker", label: Translation.tr("Media ticker"), iconName: "music_note",
            accentColor: MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary),
            monitorMode: Config.options.media.tickerMonitorMode, monitorName: Config.options.media.tickerMonitorName,
            position: Config.options.media.tickerPosition,
            customX: Config.options.media.tickerCustomX, customY: Config.options.media.tickerCustomY,
            customAnchor: Config.options.media.tickerCustomAnchor,
        },
        {
            id: "notifications", label: Translation.tr("Notifications"), iconName: "notifications",
            accentColor: MonitorThemes.shellColorForItem(page, "colTertiary", Appearance.colors.colTertiary),
            monitorMode: Config.options.notifications.monitorMode, monitorName: Config.options.notifications.monitorName,
            position: Config.options.notifications.position,
            customX: Config.options.notifications.customX, customY: Config.options.notifications.customY,
            customAnchor: Config.options.notifications.customAnchor,
        },
        {
            id: "osd", label: Translation.tr("On-screen display"), iconName: "tune",
            accentColor: MonitorThemes.shellColorForItem(page, "colSecondary", Appearance.colors.colSecondary),
            monitorMode: Config.options.osd.monitorMode, monitorName: Config.options.osd.monitorName,
            position: Config.options.osd.position,
            customX: Config.options.osd.customX, customY: Config.options.osd.customY,
            customAnchor: Config.options.osd.customAnchor,
        },
    ]
    MonitorConfigOption { id: monitorConfig }
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
            color: MonitorThemes.shellColorForItem(page, "colLayer0", Appearance.colors.colLayer0)
            border.width: 1
            border.color: MonitorThemes.shellColorForItem(page, "colLayer0Border", Appearance.colors.colLayer0Border)
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

    // Shared icon-picker dialog, sticky like stickyMonitorTabs above so it
    // covers the page's visible viewport regardless of scroll position -
    // opened via page.openIconPicker(entryId, field) from any
    // CustomResourceRow's Icon (on)/(off) field. Mirrors the ToggleDialog
    // pattern in SidebarRightContent.qml: activate the Loader first, THEN
    // flip show true, so WindowDialog's open animation actually plays
    // instead of snapping straight to shown.
    Loader {
        id: iconPickerLoader
        parent: page
        // anchors.fill: page does NOT resolve here - anchoring to a target
        // reassigned as this item's own parent in the same declaration
        // doesn't take effect (ends up 0x0), same reason stickyMonitorTabs
        // above uses explicit x/y/width instead of anchors too.
        x: 0
        y: 0
        width: page.width
        height: page.height
        z: 2000
        active: page.iconPickerOpen
        sourceComponent: MaterialSymbolPickerDialog {
            onPicked: name => {
                if (page.iconPickerTarget)
                    page.updateCustomResource(page.iconPickerTarget.entryId, { [page.iconPickerTarget.field]: name })
            }
        }
        onActiveChanged: {
            if (active) {
                item.show = true
                item.forceActiveFocus()
            }
        }
        Connections {
            target: iconPickerLoader.item
            function onDismiss() {
                iconPickerLoader.item.show = false
                page.iconPickerOpen = false
            }
            function onVisibleChanged() {
                if (iconPickerLoader.item && !iconPickerLoader.item.visible && !page.iconPickerOpen)
                    iconPickerLoader.active = false
            }
        }
    }

    Loader {
        id: servicePickerLoader
        parent: page
        x: 0
        y: 0
        width: page.width
        height: page.height
        z: 2000
        active: page.servicePickerOpen
        sourceComponent: ServicePickerDialog {
            onPicked: service => page.updateCustomResource(page.servicePickerTarget, {
                serviceName: service.name,
                serviceScope: service.scope
            })
        }
        onActiveChanged: {
            if (active) {
                item.show = true
                item.forceActiveFocus()
            }
        }
        Connections {
            target: servicePickerLoader.item
            function onDismiss() {
                servicePickerLoader.item.show = false
                page.servicePickerOpen = false
            }
            function onVisibleChanged() {
                if (servicePickerLoader.item && !servicePickerLoader.item.visible && !page.servicePickerOpen)
                    servicePickerLoader.active = false
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
            icon: "monitor"
            shape: MaterialShape.Shape.ClamShell
            title: Translation.tr("Displays")
            visible: monitorConfig.monitors.length > 0

            MonitorSetupCanvas {
                id: monitorCanvas
                Layout.fillWidth: true
                monitorConfig: monitorConfig
                popupItems: page.popupPreviewItems
                selectedMonitorName: page.selectedMonitorTab
                onMonitorSelected: name => page.selectedMonitorTab = name
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: (monitorConfig.monitors[page.selectedMonitorIndex]?.name ?? "")
                    + " · "
                    + (monitorConfig.monitors[page.selectedMonitorIndex]?.description ?? "")

                GroupedList {
                    ConfigSwitch {
                        id: enabledSwitch
                        buttonIcon: "tv_off"
                        text: Translation.tr("Enabled")
                        checked: false
                        onClicked: {
                            const nextChecked = !(monitorConfig.monitors[page.selectedMonitorIndex]?.disabled ?? false)
                            monitorConfig.updateMonitor(page.selectedMonitorIndex, { disabled: nextChecked })
                            monitorConfig.applyAndSave(page.selectedMonitorIndex)
                        }

                        Binding {
                            target: enabledSwitch
                            property: "checked"
                            value: !(monitorConfig.monitors[page.selectedMonitorIndex]?.disabled ?? false)
                            restoreMode: Binding.RestoreBinding
                        }
                    }

                    ConfigSwitch {
                        id: primaryMonitorSwitch
                        buttonIcon: "home_pin"
                        text: Translation.tr("Primary monitor")
                        enabled: !(monitorConfig.monitors[page.selectedMonitorIndex]?.disabled ?? false)
                        checked: false
                        onClicked: {
                            const monitorName = monitorConfig.monitors[page.selectedMonitorIndex]?.name ?? ""
                            if (!monitorName) return
                            const isCurrentPrimary = (Config.options.hyprland.primaryMonitor ?? "") === monitorName
                            const nextValue = isCurrentPrimary ? "" : monitorName
                            Config.options.hyprland.primaryMonitor = nextValue
                            monitorConfig.save()
                        }

                        Binding {
                            target: primaryMonitorSwitch
                            property: "checked"
                            value: (Config.options.hyprland.primaryMonitor ?? "") === (monitorConfig.monitors[page.selectedMonitorIndex]?.name ?? "")
                            restoreMode: Binding.RestoreBinding
                        }
                    }

                    ConfigSpinBox {
                        icon: "counter_1"
                        text: Translation.tr("Primary workspace start")
                        enabled: (Config.options.hyprland.primaryMonitor ?? "") !== ""
                        value: Config.options.hyprland.primaryWorkspaceStart
                        from: 1; to: 100; stepSize: 1
                        onValueChanged: page.setPrimaryWorkspaceStart(value)
                    }

                    ConfigSpinBox {
                        icon: "format_list_numbered"
                        text: Translation.tr("Primary workspace end")
                        enabled: (Config.options.hyprland.primaryMonitor ?? "") !== ""
                        value: Config.options.hyprland.primaryWorkspaceEnd
                        from: 1; to: 100; stepSize: 1
                        onValueChanged: page.setPrimaryWorkspaceEnd(value)
                    }

                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "aspect_ratio"
                        text: Translation.tr("Resolution & Refresh Rate")
                        textRole: "display"
                        model: (monitorConfig.monitors[page.selectedMonitorIndex]?.availableModes ?? [])
                            .map(mode => ({ display: mode, value: mode }))
                        currentValue: monitorConfig.monitors[page.selectedMonitorIndex]?.currentMode ?? ""
                        onSelected: newValue => {
                            const mode = newValue
                            const parts = mode.match(/(\d+)x(\d+)@([\d.]+)Hz/)
                            monitorConfig.updateMonitor(page.selectedMonitorIndex, {
                                currentMode: mode,
                                width: parseInt(parts[1]),
                                height: parseInt(parts[2]),
                                refreshRate: parseFloat(parts[3])
                            })
                            monitorConfig.applyAndSave(page.selectedMonitorIndex)
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Orientation")
                        icon: "mobile_rotate"
                        currentValue: monitorConfig.monitors[page.selectedMonitorIndex]?.transform ?? 0
                        onSelected: newValue => {
                            monitorConfig.updateMonitor(page.selectedMonitorIndex, { transform: newValue })
                            monitorConfig.applyAndSave(page.selectedMonitorIndex)
                        }
                        options: [
                            { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: 0 },
                            { displayName: "90°",                    icon: "rotate_90_degrees_cw",  value: 1 },
                            { displayName: "180°",                   icon: "screen_rotation",       value: 2 },
                            { displayName: "270°",                   icon: "rotate_90_degrees_ccw", value: 3 },
                        ]
                    }

                    ConfigSpinBox {
                        icon: "zoom_in"
                        text: Translation.tr("Scale")
                        value: Math.round((monitorConfig.monitors[page.selectedMonitorIndex]?.scale ?? 1.0) * 100)
                        from: 50; to: 300; stepSize: 25
                        onValueChanged: {
                            const newVal = value / 100.0
                            if (newVal === (monitorConfig.monitors[page.selectedMonitorIndex]?.scale ?? 1.0)) return
                            monitorConfig.updateMonitor(page.selectedMonitorIndex, { scale: newVal })
                            monitorConfig.applyAndSave(page.selectedMonitorIndex)
                        }
                    }

                    ConfigSpinBox {
                        icon: "swap_horiz"
                        text: Translation.tr("Position X")
                        value: monitorConfig.monitors[page.selectedMonitorIndex]?.x ?? 0
                        from: 0; to: 7680; stepSize: 1
                        onValueChanged: {
                            if (value === (monitorConfig.monitors[page.selectedMonitorIndex]?.x ?? 0)) return
                            monitorConfig.updateMonitor(page.selectedMonitorIndex, { x: value })
                            monitorConfig.applyAndSave(page.selectedMonitorIndex)
                        }
                    }

                    ConfigSpinBox {
                        icon: "swap_vert"
                        text: Translation.tr("Position Y")
                        value: monitorConfig.monitors[page.selectedMonitorIndex]?.y ?? 0
                        from: 0; to: 4320; stepSize: 1
                        onValueChanged: {
                            if (value === (monitorConfig.monitors[page.selectedMonitorIndex]?.y ?? 0)) return
                            monitorConfig.updateMonitor(page.selectedMonitorIndex, { y: value })
                            monitorConfig.applyAndSave(page.selectedMonitorIndex)
                        }
                    }
                }
            }
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
                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
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
                        onClicked: page.copySelectedMonitorLayoutToAll()
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
                ConfigSwitch {
                    id: showBarSwitch
                    buttonIcon: "dock_to_right"
                    text: Translation.tr("Show bar on this monitor")
                    checked: false
                    onClicked: {
                        if (!page.selectedMonitorTab) return
                        monitorConfig.setBarEnabled(page.selectedMonitorTab, !monitorConfig.isBarEnabled(page.selectedMonitorTab))
                    }

                    Binding {
                        target: showBarSwitch
                        property: "checked"
                        value: page.selectedMonitorTab ? monitorConfig.isBarEnabled(page.selectedMonitorTab) : false
                        restoreMode: Binding.RestoreBinding
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Bar position")
                    icon: "swap_vert"
                    enabled: monitorConfig.isBarEnabled(page.selectedMonitorTab)
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
                    enabled: monitorConfig.isBarEnabled(page.selectedMonitorTab)
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
                    enabled: monitorConfig.isBarEnabled(page.selectedMonitorTab)
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
                    enabled: monitorConfig.isBarEnabled(page.selectedMonitorTab)
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
            icon: "widgets"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Widgets")

            GroupedList {
                visible: Hyprland.monitors.values.length > 1
                Layout.bottomMargin: 10

                ConfigSwitch {
                    id: showWidgetsSwitch
                    buttonIcon: "widgets"
                    text: Translation.tr("Show widgets on this monitor")
                    checked: false
                    onClicked: {
                        if (!page.selectedMonitorTab) return
                        monitorConfig.setNameInScreenList(Config.options.background, page.selectedMonitorTab,
                            !monitorConfig.isNameInScreenList(Config.options.background.screenList, page.selectedMonitorTab))
                    }

                    Binding {
                        target: showWidgetsSwitch
                        property: "checked"
                        value: page.selectedMonitorTab ? monitorConfig.isNameInScreenList(Config.options.background.screenList, page.selectedMonitorTab) : false
                        restoreMode: Binding.RestoreBinding
                    }
                }
            }

            GridLayout {
                id: widgetsGrid
                Layout.fillWidth: true
                // Editing individual widgets is moot on a monitor that isn't
                // showing any of them at all - mirrors Positioning & Styles
                // disabling itself when the bar is off for the selected
                // monitor. With only one monitor there's no screenList
                // concept to speak of, so it's never disabled in that case.
                readonly property bool widgetsShownOnSelectedMonitor: Hyprland.monitors.values.length <= 1
                    || monitorConfig.isNameInScreenList(Config.options.background.screenList, page.selectedMonitorTab)
                enabled: widgetsShownOnSelectedMonitor
                columns: 3
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: [
                        {
                            icon: "weather_mix",
                            name: Translation.tr("Weather"),
                            enabled: Config.options.background.widgets.weather.enable
                        },
                        {
                            icon: "image",
                            name: Translation.tr("Image converter"),
                            enabled: Config.options.background.widgets.images.enable
                        },
                        {
                            icon: "music_note",
                            name: Translation.tr("Media Player"),
                            enabled: Config.options.background.widgets.media.enable
                        },
                        {
                            icon: "memory",
                            name: Translation.tr("Resources"),
                            enabled: Config.options.background.widgets.resources.enable
                        },
                        {
                            icon: "graphic_eq",
                            name: Translation.tr("Visualizer"),
                            enabled: Config.options.background.widgets.visualizer.enable
                        },
                        {
                            icon: "calendar_month",
                            name: Translation.tr("Calendar"),
                            enabled: Config.options.background.widgets.calendar.enable
                        },
                        {
                            icon: "public",
                            name: Translation.tr("World Clock"),
                            enabled: Config.options.background.widgets.worldClock.enable
                        },
                        {
                            icon: "person",
                            name: Translation.tr("User Card"),
                            enabled: Config.options.background.widgets.userCard.enable
                        },
                        {
                            icon: "note_stack_add",
                            name: Translation.tr("Notes"),
                            enabled: Config.options.background.widgets.notes.enable
                        }
                    ]
                    delegate: Rectangle {
                        id: widgetCard
                        required property var modelData
                        // What the card should actually communicate: not just
                        // the widget's own global flag, but whether it's
                        // really going to show up on the monitor currently
                        // selected above - a widget can be globally on and
                        // still not appear here if this monitor is excluded
                        // via screenList, and showing it as "Enabled" then is
                        // exactly the mixup that got reported.
                        readonly property bool effectivelyEnabled: modelData.enabled && widgetsGrid.widgetsShownOnSelectedMonitor
                        Layout.fillWidth: true
                        Layout.preferredHeight: 105
                        radius: Appearance.rounding.normal
                        color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                        border.width: 1
                        border.color: MonitorThemes.shellColorForItem(page, "colLayer0Border", Appearance.colors.colLayer0Border)
                        ColumnLayout {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 12
                            }
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                MaterialSymbol {
                                    text: widgetCard.modelData.icon
                                    iconSize: Appearance.font.pixelSize.normal + 5
                                    color: MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary)
                                }
                                Item { Layout.fillWidth: true }
                                ConfigSwitch {
                                    Layout.fillWidth: false
                                    checked: widgetCard.effectivelyEnabled
                                    onCheckedChanged: {
                                        // Only the grid being interactive
                                        // (this monitor actually shows
                                        // widgets) means a click drove this -
                                        // otherwise it's just the display
                                        // above reacting to a monitor switch,
                                        // and must not touch the real flag.
                                        if (!widgetsGrid.widgetsShownOnSelectedMonitor) return
                                        const modelData = widgetCard.modelData
                                        if (modelData.icon === "weather_mix")
                                            Config.options.background.widgets.weather.enable = checked
                                        else if (modelData.icon === "image")
                                            Config.options.background.widgets.images.enable = checked
                                        else if (modelData.icon === "music_note")
                                            Config.options.background.widgets.media.enable = checked
                                        else if (modelData.icon === "memory")
                                            Config.options.background.widgets.resources.enable = checked
                                        else if (modelData.icon === "graphic_eq")
                                            Config.options.background.widgets.visualizer.enable = checked
                                        else if (modelData.icon === "calendar_month")
                                            Config.options.background.widgets.calendar.enable = checked
                                        else if (modelData.icon === "public")
                                            Config.options.background.widgets.worldClock.enable = checked
                                        else if (modelData.icon === "person")
                                            Config.options.background.widgets.userCard.enable = checked
                                        else if (modelData.icon === "note_stack_add")
                                            Config.options.background.widgets.notes.enable = checked
                                    }
                                }
                            }
                            StyledText {
                                text: widgetCard.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                            StyledText {
                                text: widgetCard.effectivelyEnabled ? Translation.tr("Enabled") : Translation.tr("Disabled")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                            }
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Canvas")
                Layout.bottomMargin: 10

                GroupedList {
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "grid_4x4"
                        text: Translation.tr("Show alignment grid while dragging")
                        checked: Config.options.background.showGrid
                        onCheckedChanged: {
                            Config.options.background.showGrid = checked;
                        }
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "align_horizontal_center"
                        text: Translation.tr("Show snap lines when dropping")
                        checked: Config.options.background.showSnapLines
                        onCheckedChanged: {
                            Config.options.background.showSnapLines = checked;
                        }
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
                // Moved from Desktop's leftover "Notification popups" stub
                // section, which only had this plus a duplicate of the
                // timeout control that already lives in the Popups section
                // on this same page now.
                ConfigSwitch {
                    buttonIcon: "counter_2"
                    text: Translation.tr("Notification unread indicator: show count")
                    checked: Config.options.bar.indicators.notifications.showUnreadCount
                    onCheckedChanged: {
                        Config.options.bar.indicators.notifications.showUnreadCount = checked;
                    }
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
            icon: "widgets"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Custom Utility Buttons")

            ConfigRow {
                uniform: false
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Your own toggle buttons, shown alongside the utility buttons above (not part of the reorderable list yet). \"Command\" keeps a shell command running while on and stops it when toggled off; \"Systemd service\" starts/stops a systemctl --user unit. Icon fields take a Material Symbol name (the same icon font used throughout the shell) - shown live as you type. Same on every monitor.")
                    wrapMode: Text.Wrap
                    color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: (Config.options.bar.customResources ?? []).length > 0
                radius: Appearance.rounding.normal
                color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                implicitHeight: customResourceRows.implicitHeight + 16

                ColumnLayout {
                    id: customResourceRows
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 8
                    }
                    spacing: 16

                    Repeater {
                        model: Config.options.bar.customResources ?? []
                        delegate: CustomResourceRow {
                            required property var modelData
                            Layout.fillWidth: true
                            entry: modelData
                        }
                    }
                }
            }

            RippleButtonWithIcon {
                materialIcon: "add"
                mainText: Translation.tr("Add custom utility button")
                onClicked: page.addCustomResource()
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
            visible: page.enabledBarMonitorNames().length > 0

            onVisibleChanged: if (visible) page.ensureSelectedMonitorTab()

            ConfigRow {
                uniform: false
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Which resources show on the selected monitor's bar. Not set here = same as the default.")
                    wrapMode: Text.Wrap
                    color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                }

                RippleButtonWithIcon {
                    materialIcon: "sync"
                    mainText: Translation.tr("Copy to all")
                    visible: page.enabledBarMonitorNames().length > 1
                    onClicked: page.copyCurrentMonitorSettingsToAll()
                }
            }

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
                    MonitorConfigSwitch {
                        buttonIcon: "developer_board"
                        text: Translation.tr("GPU")
                        settingPath: ["resources", "alwaysShowGpu"]
                        fallbackValue: Config.options.bar.resources.alwaysShowGpu
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
                    text: Translation.tr("Polling interval (ms) - global")
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
            icon: "graphic_eq"
            shape: MaterialShape.Shape.Cookie7Sided
            title: Translation.tr("Visualizer Audio (Global)")

            GroupedList {
                ConfigRow {
                    uniform: false
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Shared by every visualizer in the shell. Output can follow whichever app is playing, or be pinned to one app or device.")
                        wrapMode: Text.WordWrap
                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                    }
                }

                ConfigComboBox {
                    text: Translation.tr("Output")
                    buttonIcon: "speaker"
                    fieldWidth: page.visualizerComboWidth
                    model: page.visualizerOutputSourceOptions
                    currentValue: Config.options.bar.visualizer.outputSource
                    onSelected: newValue => {
                        Config.options.bar.visualizer.outputSource = newValue
                    }
                }

                ConfigRow {
                    uniform: false
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Capturing: %1").arg(page.resolvedOutputVisualizerSource())
                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                        elide: Text.ElideRight
                    }
                }

                ConfigComboBox {
                    text: Translation.tr("Microphone")
                    buttonIcon: "mic"
                    fieldWidth: page.visualizerComboWidth
                    model: page.visualizerInputSourceOptions
                    currentValue: Config.options.bar.visualizer.inputSource
                    onSelected: newValue => {
                        Config.options.bar.visualizer.inputSource = newValue
                    }
                }

                ConfigRow {
                    uniform: false
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Capturing: %1").arg(page.resolvedInputVisualizerSource())
                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ContentSection {
            icon: "music_note"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Media")

            GroupedList {
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
        ContentSection {
            icon: "control_camera"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("Popup positions")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                text: Translation.tr("The monitor setup preview above shows where the ticker, notifications and on-screen display currently sit. Items following the active monitor show mirrored on every monitor there, since the real one is decided live. Click \"Edit positions\" to drag them for real, on your actual screen(s) - dragging one onto a different monitor moves it there too if \"Follow active monitor\" is off.")
            }

            RowLayout {
                Layout.topMargin: 4
                spacing: 8
                RippleButtonWithIcon {
                    materialIcon: "edit"
                    mainText: Translation.tr("Edit positions")
                    downAction: () => GlobalStates.popupEditorOpen = true
                }
                RippleButtonWithIcon {
                    materialIcon: "visibility"
                    mainText: Translation.tr("Preview")
                    downAction: () => page.previewAll()
                }
                RippleButtonWithIcon {
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Reset to defaults")
                    downAction: () => page.resetToDefaults()
                }
            }

            ContentSubsection {
                title: Translation.tr("Media ticker")
                tooltip: Translation.tr("A small popup that flashes briefly whenever a media key/bind changes playback - album art, title/artist and the visualizer background, nothing clickable.")

                GroupedList {
                    // Moved here from ServicesConfig.qml's Media > Ticker
                    // subsection, which is now gone: everything about this
                    // popup lives on this page, alongside the other two.
                    ConfigSwitch {
                        text: Translation.tr("Enable ticker")
                        checked: Config.options.media.tickerEnabled
                        onCheckedChanged: Config.options.media.tickerEnabled = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("Also flash on auto track change")
                        checked: Config.options.media.tickerOnTrackChange
                        onCheckedChanged: Config.options.media.tickerOnTrackChange = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("Hide if the player's window is visible")
                        checked: Config.options.media.tickerHideIfPlayerVisible
                        onCheckedChanged: Config.options.media.tickerHideIfPlayerVisible = checked
                    }
                    ConfigComboBox {
                        text: Translation.tr("Position")
                        buttonIcon: "picture_in_picture"
                        currentValue: Config.options.media.tickerPosition
                        onSelected: newValue => Config.options.media.tickerPosition = newValue
                        model: page.positionModelWithBar
                    }
                    ConfigSwitch {
                        buttonIcon: "my_location"
                        text: Translation.tr("Follow active monitor")
                        checked: Config.options.media.tickerMonitorMode === "focused"
                        onCheckedChanged: {
                            if (checked) {
                                Config.options.media.tickerMonitorMode = "focused"
                            } else {
                                Config.options.media.tickerMonitorMode = "specific"
                                page.ensureSpecificMonitor(
                                    () => Config.options.media.tickerMonitorName,
                                    v => Config.options.media.tickerMonitorName = v)
                            }
                        }
                    }
                    ConfigSpinBox {
                        icon: "timer"
                        text: Translation.tr("Duration (ms)")
                        value: Config.options.media.tickerTimeout
                        from: 500; to: 8000; stepSize: 250
                        onValueChanged: Config.options.media.tickerTimeout = value
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Notifications")
                tooltip: Translation.tr("The timeout here is a fallback: it only applies to notifications that don't ask for a duration of their own. An app that requests one is respected, and one that asks to stay until dismissed still does.")

                GroupedList {
                    ConfigComboBox {
                        text: Translation.tr("Position")
                        buttonIcon: "my_location"
                        currentValue: Config.options.notifications.position
                        onSelected: newValue => Config.options.notifications.position = newValue
                        model: page.positionModel
                    }
                    ConfigSwitch {
                        buttonIcon: "my_location"
                        text: Translation.tr("Follow active monitor")
                        checked: Config.options.notifications.monitorMode === "focused"
                        onCheckedChanged: {
                            if (checked) {
                                Config.options.notifications.monitorMode = "focused"
                            } else {
                                Config.options.notifications.monitorMode = "specific"
                                page.ensureSpecificMonitor(
                                    () => Config.options.notifications.monitorName,
                                    v => Config.options.notifications.monitorName = v)
                            }
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "open_in_full"
                        text: Translation.tr("Expand notification popups")
                        checked: Config.options.notifications.expandPopups
                        onCheckedChanged: Config.options.notifications.expandPopups = checked
                    }
                    // "Default", not "Duration": Notifications.qml only falls
                    // back to this when the sender passes expireTimeout < 0,
                    // i.e. asked for no particular duration. A sender's own
                    // value wins, and expireTimeout == 0 means "until
                    // dismissed" and gets no timer at all - so this number
                    // genuinely does not apply to every notification.
                    ConfigSpinBox {
                        icon: "timer"
                        text: Translation.tr("Default timeout (ms)")
                        value: Config.options.notifications.timeout
                        from: 1000; to: 30000; stepSize: 500
                        onValueChanged: Config.options.notifications.timeout = value
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("On-screen display")
                tooltip: Translation.tr("Volume, brightness and gamma indicators.")

                GroupedList {
                    ConfigComboBox {
                        text: Translation.tr("Position")
                        buttonIcon: "tune"
                        currentValue: Config.options.osd.position
                        onSelected: newValue => Config.options.osd.position = newValue
                        model: page.positionModelWithBar
                    }
                    ConfigSwitch {
                        buttonIcon: "my_location"
                        text: Translation.tr("Follow active monitor")
                        checked: Config.options.osd.monitorMode === "focused"
                        onCheckedChanged: {
                            if (checked) {
                                Config.options.osd.monitorMode = "focused"
                            } else {
                                Config.options.osd.monitorMode = "specific"
                                page.ensureSpecificMonitor(
                                    () => Config.options.osd.monitorName,
                                    v => Config.options.osd.monitorName = v)
                            }
                        }
                    }
                    // Same range/step as the copy that remains in
                    // InterfaceConfig.qml's On-screen display section - both
                    // write the one config value, so they stay in sync either
                    // way, but mismatched bounds would let one page offer a
                    // number the other refuses (and, because a ConfigSpinBox
                    // writes its clamped value back, silently rewrite it).
                    ConfigSpinBox {
                        icon: "av_timer"
                        text: Translation.tr("Timeout (ms)")
                        value: Config.options.osd.timeout
                        from: 100; to: 8000; stepSize: 100
                        onValueChanged: Config.options.osd.timeout = value
                    }
                }
            }
        }
        ContentSection {
            icon: "splitscreen_left"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Left Sidebar")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: mediaCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                    border.width: 1
                    border.color: "transparent"

                    ColumnLayout {
                        id: mediaCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        MaterialSymbol {
                            text: "music_note_2"
                            iconSize: Appearance.font.pixelSize.huge
                            color: MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary)
                        }
                        StyledText {
                            text: Translation.tr("Media Player")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                        }
                        Item { Layout.fillHeight: true }
                        GroupedList {
                            Layout.fillWidth: true
                            bgcolor: MonitorThemes.shellColorForItem(page, "colLayer2", Appearance.colors.colLayer2)
                            ConfigSwitch {
                                buttonIcon: "check"
                                text: Translation.tr("Enable")
                                checked: Config.options.sidebar.media.enable
                                onCheckedChanged: { Config.options.sidebar.media.enable = checked }
                            }
                            ConfigSwitch {
                                buttonIcon: "radio_button_partial"
                                text: Translation.tr("Follow Album Colors")
                                checked: Config.options.sidebar.media.artColors
                                onCheckedChanged: { Config.options.sidebar.media.artColors = checked }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: aiCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                        border.width: 1
                        border.color: "transparent"

                        ColumnLayout {
                            id: aiCol
                            anchors { fill: parent; margins: 12 }
                            spacing: 8

                            MaterialSymbol {
                                text: "smart_toy"
                                iconSize: Appearance.font.pixelSize.huge
                                color: MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary)
                            }
                            StyledText {
                                text: Translation.tr("AI")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                currentValue: Config.options.policies.ai
                                onSelected: newValue => { Config.options.policies.ai = newValue }
                                options: [
                                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                                    { displayName: Translation.tr("Local"), icon: "sync_saved_locally", value: 2 }
                                ]
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: weebCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                        border.width: 1
                        border.color: "transparent"

                        ColumnLayout {
                            id: weebCol
                            anchors { fill: parent; margins: 12 }
                            spacing: 8

                            MaterialSymbol {
                                text: "playing_cards"
                                iconSize: Appearance.font.pixelSize.huge
                                color: MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary)
                            }
                            StyledText {
                                text: Translation.tr("Weeb")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                currentValue: Config.options.policies.weeb
                                onSelected: newValue => { Config.options.policies.weeb = newValue }
                                options: [
                                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                                    { displayName: Translation.tr("Closet"), icon: "ev_shadow", value: 2 }
                                ]
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: translatorCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                border.width: 1
                border.color: "transparent"

                ColumnLayout {
                    id: translatorCol
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        ConfigSwitch {
                            buttonIcon: "translate"
                            text: Translation.tr("Enable Translator")
                            checked: Config.options.sidebar.translator.enable
                            onCheckedChanged: { Config.options.sidebar.translator.enable = checked }
                        }
                    }
                }
            }
        }
        ContentSection {
            icon: "splitscreen_right"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Right Sidebar")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "planner_banner_ad_pt"
                    text: Translation.tr('Banner')
                    checked: Config.options.sidebar.banner
                    onCheckedChanged: {
                        Config.options.sidebar.banner = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr('Media Player')
                    checked: Config.options.sidebar.mediaPlayer
                    onCheckedChanged: {
                        Config.options.sidebar.mediaPlayer = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr('Keep right sidebar loaded')
                    checked: Config.options.sidebar.keepRightSidebarLoaded
                    onCheckedChanged: {
                        Config.options.sidebar.keepRightSidebarLoaded = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Quick toggles")
                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Style")
                        icon: "toggle_on"
                        Layout.fillWidth: false
                        currentValue: Config.options.sidebar.quickToggles.style
                        onSelected: newValue => {
                            Config.options.sidebar.quickToggles.style = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Classic"),
                                icon: "password_2",
                                value: "classic"
                            },
                            {
                                displayName: Translation.tr("Android"),
                                icon: "action_key",
                                value: "android"
                            }
                        ]
                    }
                    ConfigSpinBox {
                        enabled: Config.options.sidebar.quickToggles.style === "android"
                        icon: "add_column_left"
                        text: Translation.tr("Columns")
                        value: Config.options.sidebar.quickToggles.android.columns
                        from: 1
                        to: 8
                        stepSize: 1
                        onValueChanged: {
                            Config.options.sidebar.quickToggles.android.columns = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Sliders")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.quickSliders.enable
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.enable = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "brightness_6"
                        text: Translation.tr("Brightness")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showBrightness
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showBrightness = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "volume_up"
                        text: Translation.tr("Volume")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showVolume
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showVolume = checked;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "mic"
                        text: Translation.tr("Microphone")
                        enabled: Config.options.sidebar.quickSliders.enable
                        checked: Config.options.sidebar.quickSliders.showMic
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showMic = checked;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Corner open")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.cornerOpen.enable
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.enable = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "highlight_mouse_cursor"
                        text: Translation.tr("Hover to trigger")
                        checked: Config.options.sidebar.cornerOpen.clickless
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.clickless = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "vertical_align_bottom"
                        text: Translation.tr("Place at bottom")
                        checked: Config.options.sidebar.cornerOpen.bottom
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.bottom = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "unfold_more_double"
                        text: Translation.tr("Value scroll")
                        checked: Config.options.sidebar.cornerOpen.valueScroll
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.valueScroll = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "visibility"
                        text: Translation.tr("Visualize region")
                        checked: Config.options.sidebar.cornerOpen.visualize
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.visualize = checked }
                    }
                    ConfigSwitch {
                        enabled: Config.options.sidebar.cornerOpen.clickless
                        buttonIcon: "ads_click"
                        text: Translation.tr("Force hover at absolute corner")
                        checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked }
                    }
                    ConfigSpinBox {
                        enabled: Config.options.sidebar.cornerOpen.clickless
                        icon: "arrow_cool_down"
                        text: Translation.tr("Vertical offset")
                        value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                        from: 0; to: 20; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value }
                    }
                    ConfigSpinBox {
                        icon: "arrow_range"
                        text: Translation.tr("Region width")
                        value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                        from: 1; to: 300; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionWidth = value }
                    }
                    ConfigSpinBox {
                        icon: "height"
                        text: Translation.tr("Region height")
                        value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                        from: 1; to: 300; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionHeight = value }
                    }
                }
            }
        }
        ContentSection { // I see that for many the overview is important, I put it first why not
            icon: "overview_key"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Overview")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.overview.enable
                    onCheckedChanged: {
                        Config.options.overview.enable = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Center icons")
                    checked: Config.options.overview.centerIcons
                    onCheckedChanged: {
                        Config.options.overview.centerIcons = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "loupe"
                    text: Translation.tr("Scale (%)")
                    value: Config.options.overview.scale * 100
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overview.scale = value / 100;
                    }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.overview.style
                    onSelected: newValue => {
                        Config.options.overview.style = newValue
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "grid_on",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Niri Like"),
                            icon: "mobiledata_arrows",
                            value: "niri"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Default Settings")
                visible: Config.options.overview.style !== "niri"

                GroupedList {
                    visible: Config.options.overview.style !== "niri"
                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        ConfigSpinBox {
                            icon: "splitscreen_bottom"
                            text: Translation.tr("Rows")
                            value: Config.options.overview.rows
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueChanged: {
                                Config.options.overview.rows = value;
                            }
                        }
                        ConfigSpinBox {
                            icon: "splitscreen_right"
                            text: Translation.tr("Columns")
                            value: Config.options.overview.columns
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueChanged: {
                                Config.options.overview.columns = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.leftMargin: 24
                        ConfigSelectionArray {
                            Layout.alignment: Qt.AlignHCenter
                            currentValue: Config.options.overview.orderRightLeft
                            onSelected: newValue => {
                                Config.options.overview.orderRightLeft = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Left to right"),
                                    icon: "arrow_forward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Right to left"),
                                    icon: "arrow_back",
                                    value: 1
                                }
                            ]
                        }
                        ConfigSelectionArray {
                            Layout.alignment: Qt.AlignHCenter
                            currentValue: Config.options.overview.orderBottomUp
                            onSelected: newValue => {
                                Config.options.overview.orderBottomUp = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Top-down"),
                                    icon: "arrow_downward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Bottom-up"),
                                    icon: "arrow_upward",
                                    value: 1
                                }
                            ]
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "call_to_action"
            title: Translation.tr("Dock")
            shape: MaterialShape.Shape.Cookie6Sided

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.dock.enable
                    onCheckedChanged: { Config.options.dock.enable = checked }
                }
                ConfigSwitch {
                    buttonIcon: "background_dot_small"
                    text: Translation.tr("Background")
                    checked: Config.options.dock.showBackground
                    onCheckedChanged: { Config.options.dock.showBackground = checked }
                }
                ConfigSwitch {
                    buttonIcon: "highlight_mouse_cursor"
                    text: Translation.tr("Hover to reveal")
                    checked: Config.options.dock.hoverToReveal
                    onCheckedChanged: { Config.options.dock.hoverToReveal = checked }
                }
                ConfigSwitch {
                    buttonIcon: "push_pin"
                    text: Translation.tr("Pinned on startup")
                    checked: Config.options.dock.pinnedOnStartup
                    onCheckedChanged: { Config.options.dock.pinnedOnStartup = checked }
                }
            }


            ContentSubsection {
                title: Translation.tr("Buttons & Media")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "music_note"
                        text: Translation.tr("Media Player")
                        checked: Config.options.dock.showMedia
                        onCheckedChanged: { Config.options.dock.showMedia = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "keep"
                        text: Translation.tr("Show Pin Button")
                        checked: Config.options.dock.showPinButton
                        onCheckedChanged: { Config.options.dock.showPinButton = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "apps"
                        text: Translation.tr("Show Apps Button")
                        checked: Config.options.dock.showAppsButton
                        onCheckedChanged: { Config.options.dock.showAppsButton = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "colors"
                        text: Translation.tr("Tint app icons")
                        checked: Config.options.dock.monochromeIcons
                        onCheckedChanged: { Config.options.dock.monochromeIcons = checked }
                    }
                }
            }
        }

        ContentSection {
            icon: "lock"
            title: Translation.tr("Lock screen")
            shape: MaterialShape.Shape.Pentagon

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "water_drop"
                    text: Translation.tr("Use Hyprlock (instead of Quickshell)")
                    checked: Config.options.lock.useHyprlock
                    onCheckedChanged: { Config.options.lock.useHyprlock = checked }
                }
                ConfigSwitch {
                    buttonIcon: "account_circle"
                    text: Translation.tr("Launch on startup")
                    checked: Config.options.lock.launchOnStartup
                    onCheckedChanged: { Config.options.lock.launchOnStartup = checked }
                }
                ConfigSwitch {
                    buttonIcon: "widgets"
                    text: Translation.tr("Show Widgets")
                    checked: Config.options.lock.showWidgets
                    onCheckedChanged: { Config.options.lock.showWidgets = checked }
                }
                ConfigSwitch {
                    buttonIcon: "tools_installation_kit"
                    text: Translation.tr("Show Toolbars")
                    checked: Config.options.lock.showToolbars
                    onCheckedChanged: { Config.options.lock.showToolbars = checked }
                }
                ConfigSwitch {
                    buttonIcon: "music_note"
                    enabled: Config.options.lock.showToolbars
                    text: Translation.tr("Show media player info")
                    checked: Config.options.lock.showMedia
                    onCheckedChanged: { Config.options.lock.showMedia = checked }
                }
            }

            ContentSubsection {
                title: Translation.tr("Idle & Sleep")
                GroupedList {
                    ConfigSpinBox {
                        icon: "timer"
                        text: Translation.tr("Lock after idle (min)")
                        value: Config.options.lock.idleTimeoutSec / 60
                        from: 1; to: 60; stepSize: 1
                        onValueChanged: {
                            Config.options.lock.idleTimeoutSec = value * 60;
                            idleTimeoutsDebounce.restart();
                        }
                    }
                    ConfigSpinBox {
                        icon: "bedtime"
                        text: Translation.tr("Sleep after lock (min)")
                        value: Config.options.lock.sleepAfterLockTimeoutSec / 60
                        from: 0; to: 120; stepSize: 1
                        onValueChanged: {
                            Config.options.lock.sleepAfterLockTimeoutSec = value * 60;
                            idleTimeoutsDebounce.restart();
                        }
                    }
                }
                // hypridle.conf has no live-reload, so this is debounced and
                // restarts the daemon after the user settles on a value
                // instead of on every single spin-button click.
                Timer {
                    id: idleTimeoutsDebounce
                    interval: 800
                    repeat: false
                    onTriggered: {
                        Quickshell.execDetached([
                            Directories.hypridleSetTimeoutsScriptPath,
                            `${Config.options.lock.idleTimeoutSec}`,
                            `${Config.options.lock.sleepAfterLockTimeoutSec}`
                        ]);
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Security")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "settings_power"
                        text: Translation.tr("Require password to power off/restart")
                        checked: Config.options.lock.security.requirePasswordToPower
                        onCheckedChanged: { Config.options.lock.security.requirePasswordToPower = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "key_vertical"
                        text: Translation.tr("Also unlock keyring")
                        checked: Config.options.lock.security.unlockKeyring
                        onCheckedChanged: { Config.options.lock.security.unlockKeyring = checked }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: General")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "center_focus_weak"
                        text: Translation.tr("Center clock")
                        checked: Config.options.lock.centerClock
                        onCheckedChanged: { Config.options.lock.centerClock = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "info"
                        text: Translation.tr('Show "Locked" text')
                        checked: Config.options.lock.showLockedText
                        onCheckedChanged: { Config.options.lock.showLockedText = checked }
                    }
                    ConfigSwitch {
                        buttonIcon: "shapes"
                        text: Translation.tr("Use varying shapes for password characters")
                        checked: Config.options.lock.materialShapeChars
                        onCheckedChanged: { Config.options.lock.materialShapeChars = checked }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: Blurred")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "blur_on"
                        text: Translation.tr("Enable blur")
                        checked: Config.options.lock.blur.enable
                        onCheckedChanged: { Config.options.lock.blur.enable = checked }
                    }
                    ConfigSpinBox {
                        icon: "deblur"
                        text: Translation.tr("Samples")
                        value: Config.options.lock.blur.size
                        from: 20; to: 200; stepSize: 10
                        onValueChanged: { Config.options.lock.blur.size = value }
                    }
                    ConfigSpinBox {
                        icon: "loupe"
                        text: Translation.tr("Extra wallpaper zoom (%)")
                        value: Config.options.lock.blur.extraZoom * 100
                        from: 1; to: 150; stepSize: 2
                        onValueChanged: { Config.options.lock.blur.extraZoom = value / 100 }
                    }
                }
            }
        }

        ContentSection {
            icon: "select_window"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Overlay")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "high_density"
                    text: Translation.tr("Enable opening zoom animation")
                    checked: Config.options.overlay.openingZoomAnimation
                    onCheckedChanged: {
                        Config.options.overlay.openingZoomAnimation = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "texture"
                    text: Translation.tr("Darken screen")
                    checked: Config.options.overlay.darkenScreen
                    onCheckedChanged: {
                        Config.options.overlay.darkenScreen = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Floating Image")
                GroupedList {
                    ConfigTextArea {
                        id: floatingImageSourceField
                        Layout.fillWidth: true
                        fieldWidth: 430
                        buttonIcon: "imagesmode"
                        text: Translation.tr("Image source")
                        value: Config.options.overlay.floatingImage.imageSource
                        onValueChanged: {
                            floatingImageSourceDebounceTimer.restart();
                        }

                        Timer {
                            id: floatingImageSourceDebounceTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                Config.options.overlay.floatingImage.imageSource = floatingImageSourceField.value;
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Crosshair")

                Rectangle {
                    id: crosshairCard
                    Layout.fillWidth: true
                    implicitHeight: crosshairCol.implicitHeight + 28
                    radius: Appearance.rounding.normal
                    color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)

                    ColumnLayout {
                        id: crosshairCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 8

                        ConfigTextArea {
                            id: crosshairCodeField
                            Layout.fillWidth: true
                            buttonIcon: "point_scan"
                            text: Translation.tr("Crosshair code")
                            placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                            value: Config.options.crosshair.code
                            onValueChanged: {
                                crosshairCodeDebounceTimer.restart();
                            }

                            Timer {
                                id: crosshairCodeDebounceTimer
                                interval: 1000
                                repeat: false
                                onTriggered: {
                                    Config.options.crosshair.code = crosshairCodeField.value;
                                }
                            }
                        }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.leftMargin: 8
                                Layout.fillWidth: true
                                text: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                                wrapMode: Text.Wrap
                            }
                            RippleButtonWithIcon {
                                id: editorButton
                                Layout.fillWidth: true
                                Layout.rightMargin: 6
                                Layout.preferredHeight: 40
                                buttonRadius: Appearance.rounding.normal
                                materialIcon: "open_in_new"
                                mainText: Translation.tr("Open editor")
                                onClicked: {
                                    Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "screenshot_frame_2"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Region selector (screen snipping/Google Lens)")

            ContentSubsection {
                title: Translation.tr("Hint target regions")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "select_window"
                        text: Translation.tr('Windows')
                        checked: Config.options.regionSelector.targetRegions.windows
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.windows = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "right_panel_open"
                        text: Translation.tr('Layers')
                        checked: Config.options.regionSelector.targetRegions.layers
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.layers = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "nearby"
                        text: Translation.tr('Content')
                        checked: Config.options.regionSelector.targetRegions.content
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.content = checked;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Google Lens")

                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Selection Type")
                        icon: "ink_selection"
                        currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                        onSelected: newValue => {
                            Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                        }
                        options: [
                            { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                            { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Rectangular selection")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "point_scan"
                        text: Translation.tr("Show aim lines")
                        checked: Config.options.regionSelector.rect.showAimLines
                        onCheckedChanged: {
                            Config.options.regionSelector.rect.showAimLines = checked;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Circle selection")

                GroupedList {
                    ConfigSpinBox {
                        icon: "eraser_size_3"
                        text: Translation.tr("Stroke width")
                        value: Config.options.regionSelector.circle.strokeWidth
                        from: 1
                        to: 20
                        stepSize: 1
                        onValueChanged: {
                            Config.options.regionSelector.circle.strokeWidth = value;
                        }
                    }

                    ConfigSpinBox {
                        icon: "screenshot_frame_2"
                        text: Translation.tr("Padding")
                        value: Config.options.regionSelector.circle.padding
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            Config.options.regionSelector.circle.padding = value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "voting_chip"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("On-screen display")
            GroupedList {
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Timeout (ms)")
                    value: Config.options.osd.timeout
                    from: 100
                    to: 8000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.osd.timeout = value;
                    }
                }
            }
        }
        ContentSection {
            icon: "music_note"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Super+M Menu")

            GroupedList {
                MediaElementSwitch { buttonIcon: "graphic_eq"; text: Translation.tr("Visualizer"); configKey: "menuElements"; elementId: "visualizer" }
                MediaElementSwitch { buttonIcon: "linear_scale"; text: Translation.tr("Progress bar"); configKey: "menuElements"; elementId: "progressBar" }
                MediaElementSwitch { buttonIcon: "skip_next"; text: Translation.tr("Skip buttons"); configKey: "menuElements"; elementId: "skipButtons" }
                MediaElementSwitch { buttonIcon: "play_circle"; text: Translation.tr("Play/Pause"); configKey: "menuElements"; elementId: "playPauseButton" }
                MediaElementSwitch { buttonIcon: "lyrics"; text: Translation.tr("Lyrics toggle"); configKey: "menuElements"; elementId: "lyricsToggle" }
                MediaElementSwitch { buttonIcon: "volume_up"; text: Translation.tr("Volume bar (this player only)"); configKey: "menuElements"; elementId: "volumeBar" }
            }
        }
    }
}
