pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    implicitHeight: col.implicitHeight + 16
    property string monitorName: ""

    readonly property bool widgetsShownOnMonitor: Quickshell.screens.length <= 1
        || Config.backgroundWidgetsShown(root.monitorName)

    function setWidgetsShownOnMonitor(shown) {
        if (Quickshell.screens.length <= 1 || root.monitorName === "") return
        const activeNames = Quickshell.screens.map(screen => screen.name).filter(name => name !== "")
        let screens = (Config.options.background.screenList ?? []).slice()

        // An empty screen list means every monitor. Expand it before removing
        // one monitor, otherwise turning this off would silently remain "all".
        if (screens.length === 0)
            screens = activeNames.slice()
        else
            screens = screens.filter(name => activeNames.includes(name))

        if (shown) {
            if (!screens.includes(root.monitorName)) screens.push(root.monitorName)
        } else {
            screens = screens.filter(name => name !== root.monitorName)
        }

        Config.options.background.screenList = screens.length === activeNames.length ? [] : screens
    }

    readonly property bool lockWidgetsShownOnMonitor: Quickshell.screens.length <= 1
        || Config.lockWidgetsShown(root.monitorName)

    function setLockWidgetsShownOnMonitor(shown) {
        if (Quickshell.screens.length <= 1 || root.monitorName === "") return
        const activeNames = Quickshell.screens.map(screen => screen.name).filter(name => name !== "")
        let screens = (Config.options.lock.screenList ?? []).slice()

        if (screens.length === 0)
            screens = activeNames.slice()
        else
            screens = screens.filter(name => activeNames.includes(name))

        if (shown) {
            if (!screens.includes(root.monitorName)) screens.push(root.monitorName)
        } else {
            screens = screens.filter(name => name !== root.monitorName)
        }

        Config.options.lock.screenList = screens.length === activeNames.length ? [] : screens
    }

    readonly property var widgetList: [
        { key: "visualizer",  icon: "graphic_eq",         name: Translation.tr("Visualizer") },
        { key: "customImage", icon: "image",              name: Translation.tr("Custom Image") },
        { key: "weather",     icon: "partly_cloudy_day",  name: Translation.tr("Weather") },
        { key: "clock",       icon: "schedule",           name: Translation.tr("Clock") },
        { key: "media",       icon: "music_note",         name: Translation.tr("Media") },
        { key: "images",      icon: "photo_library",      name: Translation.tr("Image Converter") },
        { key: "reverseSearch", icon: "image_search",     name: Translation.tr("Reverse Image Search") },
        { key: "resources",   icon: "monitor_heart",      name: Translation.tr("Resources") },
        { key: "calendar",    icon: "calendar_month",     name: Translation.tr("Calendar") },
        { key: "worldClock",  icon: "public",             name: Translation.tr("World Clock") },
        { key: "userCard",    icon: "person",             name: Translation.tr("User Card") },
        { key: "notes",       icon: "note_stack_add",     name: Translation.tr("Notes") },
        { key: "timers",      icon: "timer",              name: Translation.tr("Timers") },
        { key: "todo",        icon: "add_task",           name: Translation.tr("To-Do") },
        { key: "sticker",     icon: "sticker",            name: Translation.tr("Sticker") },
    ]

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        ConfigSwitch {
            id: showWidgetsSwitch
            Layout.fillWidth: true
            buttonIcon: "widgets"
            monitorName: root.monitorName
            text: Translation.tr("Show widgets on this monitor")
            onClicked: root.setWidgetsShownOnMonitor(!root.widgetsShownOnMonitor)

            Binding {
                target: showWidgetsSwitch
                property: "checked"
                value: root.widgetsShownOnMonitor
                restoreMode: Binding.RestoreBinding
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "lock"
            monitorName: root.monitorName
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: Config.options.background.widgetsLocked = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "shadow"
            text: Translation.tr("Shadow")
            checked: Config.options.background.widgets.shadow 
            onCheckedChanged: Config.options.background.widgets.shadow = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "blur_on"
            text: Translation.tr("Blur widgets")
            checked: Config.options.background.widgets.blurWidgets 
            onCheckedChanged: Config.options.background.widgets.blurWidgets = checked
        }

        ConfigSlider {
            Layout.fillWidth: true
            showLabel: false
            visible: Config.options.background.widgets.blurWidgets
            value: Config.options.background.widgets.blurRadius ?? 32
            usePercentTooltip: false
            buttonIcon: "aspect_ratio"
            from: 1
            to: 64
            stopIndicatorValues: [32]
            onValueChanged: Config.options.background.widgets.blurRadius = value
        }

        ConfigSwitch {
            id: showLockWidgetsSwitch
            Layout.fillWidth: true
            buttonIcon: "lock_person"
            monitorName: root.monitorName
            text: Translation.tr("Show widgets on lockscreen (this monitor)")
            infoText: Translation.tr("Requires the master \"Show Widgets\" switch in Settings → Interface → Lock screen.")
            enabled: Config.options.lock.showWidgets
            onClicked: root.setLockWidgetsShownOnMonitor(!root.lockWidgetsShownOnMonitor)

            Binding {
                target: showLockWidgetsSwitch
                property: "checked"
                value: Config.options.lock.showWidgets && root.lockWidgetsShownOnMonitor
                restoreMode: Binding.RestoreBinding
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutlineVariant)
            opacity: 0.4
        }

        Repeater {
            model: root.widgetList
            delegate: RowLayout {
                id: widgetRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                ConfigSwitch {
                    id: widgetSwitch
                    Layout.fillWidth: true
                    buttonIcon: widgetRow.modelData.icon
                    monitorName: root.monitorName
                    text: widgetRow.modelData.name
                    enabled: root.widgetsShownOnMonitor
                    onClicked: {
                        if (!root.widgetsShownOnMonitor) return
                        const enabled = Config.getBackgroundWidgetSetting(
                            root.monitorName, widgetRow.modelData.key, Config.options.background.widgets[widgetRow.modelData.key].enable)
                        Config.setBackgroundWidgetSetting(root.monitorName, widgetRow.modelData.key, !enabled)
                    }

                    Binding {
                        target: widgetSwitch
                        property: "checked"
                        value: root.widgetsShownOnMonitor && Config.getBackgroundWidgetSetting(
                            root.monitorName, widgetRow.modelData.key, Config.options.background.widgets[widgetRow.modelData.key].enable)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                // Clock manages its own lockscreen visibility (see "Only show when locked"
                // in Appearance settings), so it has no generic showOnLock toggle here.
                CircleUtilButton {
                    id: lockToggle
                    visible: widgetRow.modelData.key !== "clock"
                    readonly property bool showOnLock: Config.options.background.widgets[widgetRow.modelData.key]?.showOnLock ?? true
                    onClicked: Config.options.background.widgets[widgetRow.modelData.key].showOnLock = !lockToggle.showOnLock

                    MaterialSymbol {
                        horizontalAlignment: Qt.AlignHCenter
                        text: lockToggle.showOnLock ? "lock_open" : "lock"
                        iconSize: Appearance.font.pixelSize.large
                        color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)

                        StyledToolTip {
                            extraVisibleCondition: lockToggle.hovered
                            text: lockToggle.showOnLock
                                ? Translation.tr("Shown on lockscreen — click to hide")
                                : Translation.tr("Hidden on lockscreen — click to show")
                        }
                    }
                }
            }
        }
    }
}
