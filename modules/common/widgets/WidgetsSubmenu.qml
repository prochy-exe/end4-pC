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
        || (Config.options.background.screenList ?? []).includes(root.monitorName)

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

    readonly property var widgetList: [
        { key: "visualizer",  icon: "graphic_eq",         name: Translation.tr("Visualizer") },
        { key: "customImage", icon: "image",              name: Translation.tr("Custom Image") },
        { key: "weather",     icon: "partly_cloudy_day",  name: Translation.tr("Weather") },
        { key: "clock",       icon: "schedule",           name: Translation.tr("Clock") },
        { key: "media",       icon: "music_note",         name: Translation.tr("Media") },
        { key: "images",      icon: "photo_library",      name: Translation.tr("Image Converter") },
        { key: "resources",   icon: "monitor_heart",      name: Translation.tr("Resources") },
        { key: "calendar",    icon: "calendar_month",     name: Translation.tr("Calendar") },
        { key: "worldClock",  icon: "public",             name: Translation.tr("World Clock") },
        { key: "userCard",    icon: "person",             name: Translation.tr("User Card") },
        { key: "notes",       icon: "note_stack_add",     name: Translation.tr("Notes") },
    ]

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        ConfigSwitch {
            id: showWidgetsSwitch
            Layout.fillWidth: true
            buttonIcon: "widgets"
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
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: Config.options.background.widgetsLocked = checked
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        Repeater {
            model: root.widgetList
            delegate: ConfigSwitch {
                id: widgetSwitch
                required property var modelData
                Layout.fillWidth: true
                buttonIcon: modelData.icon
                text: modelData.name
                enabled: root.widgetsShownOnMonitor
                onClicked: {
                    if (!root.widgetsShownOnMonitor) return
                    const enabled = Config.getBackgroundWidgetSetting(
                        root.monitorName, modelData.key, Config.options.background.widgets[modelData.key].enable)
                    Config.setBackgroundWidgetSetting(root.monitorName, modelData.key, !enabled)
                }

                Binding {
                    target: widgetSwitch
                    property: "checked"
                    value: root.widgetsShownOnMonitor && Config.getBackgroundWidgetSetting(
                        root.monitorName, modelData.key, Config.options.background.widgets[modelData.key].enable)
                    restoreMode: Binding.RestoreBinding
                }
            }
        }
    }
}
