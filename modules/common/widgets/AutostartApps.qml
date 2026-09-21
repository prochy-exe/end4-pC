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

ColumnLayout {
    id: root
    Layout.fillWidth: true
    width: parent.width
    spacing: 4

    // Item to reparent the app-picker dialog onto so it covers the whole
    // settings page's visible viewport instead of just this widget's own
    // (usually much smaller) bounds - pass the page's ContentPage id in.
    // Falls back to staying local if the caller doesn't provide one.
    property Item stickyParent: null
    property bool appPickerOpen: false
    property int appPickerTargetIndex: -1
    function openAppPicker(index) {
        root.appPickerTargetIndex = index
        root.appPickerOpen = true
    }

    function addEntry() {
        let list = []
        for (let i = 0; i < Config.options.hyprland.autostartApps.apps.length; i++) {
            let o = Config.options.hyprland.autostartApps.apps[i]
            list.push({ cmd: o.cmd, workspace: o.workspace, delay: o.delay })
        }
        list.push({ cmd: "", workspace: 1, delay: 0 })
        Config.options.hyprland.autostartApps.apps = list
    }

    function removeEntry(index) {
        let list = []
        for (let i = 0; i < Config.options.hyprland.autostartApps.apps.length; i++) {
            if (i === index) continue
            let o = Config.options.hyprland.autostartApps.apps[i]
            list.push({ cmd: o.cmd, workspace: o.workspace, delay: o.delay })
        }
        Config.options.hyprland.autostartApps.apps = list
    }

    function updateEntry(index, key, value) {
        let list = []
        for (let i = 0; i < Config.options.hyprland.autostartApps.apps.length; i++) {
            let o = Config.options.hyprland.autostartApps.apps[i]
            list.push({ cmd: o.cmd, workspace: o.workspace, delay: o.delay })
        }
        list[index][key] = value
        Config.options.hyprland.autostartApps.apps = list
    }

    RowLayout {
        Layout.fillWidth: true
        GroupedList {
            Layout.fillWidth: true
            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.hyprland.autostartApps.enable
                onCheckedChanged: {
                    Config.options.hyprland.autostartApps.enable = checked
                }
            }
        }

        RippleButton {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            visible: Config.options.hyprland.autostartApps.enable
            buttonRadius: implicitWidth / 2
            colBackground: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary), 0.85)
            colBackgroundHover: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary), 0.6)
            colRipple: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary), 0.5)
            onClicked: {
                Quickshell.execDetached(["python3", `${Directories.scriptPath}/hyprland/autostart.py`])
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "motion_play"
                iconSize: Appearance.font.pixelSize.normal
                color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.bottomMargin: -4
        height: 24
        visible: Config.options.hyprland.autostartApps.apps.length > 0 && Config.options.hyprland.autostartApps.enable

        Row {
            id: headerRightGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            StyledText {
                width: 118
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Workspace")
                color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }

            StyledText {
                width: 118
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Delay")
                color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }

            Item { width: 36; height: 1 }
        }

        StyledText {
            anchors.left: parent.left
            anchors.right: headerRightGroup.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("App or Command")
            color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
        }
    }

    Repeater {
        id: appsRepeater
        model: Config.options.hyprland.autostartApps.apps

        delegate: Item {
            id: entryRow
            required property var modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: cmdArea.implicitHeight
            visible: Config.options.hyprland.autostartApps.enable

            Row {
                id: rightGroup
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                RippleButton {
                    width: 36
                    height: 36
                    buttonRadius: width / 2
                    colBackground: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary), 0.85)
                    colBackgroundHover: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary), 0.6)
                    colRipple: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary), 0.5)
                    onClicked: root.openAppPicker(entryRow.index)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "search"
                        iconSize: Appearance.font.pixelSize.normal
                        color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                    }
                }

                ConfigSpinBox {
                    width: 118
                    value: entryRow.modelData.workspace ?? 1
                    from: 1
                    to: 20

                    property bool ready: false
                    Component.onCompleted: ready = true

                    onValueChanged: {
                        if (!ready) return
                        root.updateEntry(entryRow.index, "workspace", value)
                    }
                }

                ConfigSpinBox {
                    width: 118
                    value: entryRow.modelData.delay ?? 0
                    from: 0
                    to: 60
                    stepSize: 1

                    property bool ready: false
                    Component.onCompleted: ready = true

                    onValueChanged: {
                        if (!ready) return
                        root.updateEntry(entryRow.index, "delay", value)
                    }
                }

                RippleButton {
                    width: 36
                    height: 36
                    buttonRadius: width / 2
                    colBackground: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError), 0.85)
                    colBackgroundHover: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError), 0.6)
                    colRipple: ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError), 0.5)
                    onClicked: root.removeEntry(entryRow.index)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.normal
                        color: MonitorThemes.shellColorForItem(root, "colError", Appearance.colors.colError)
                    }
                }
            }

            MaterialTextArea {
                id: cmdArea
                anchors.left: parent.left
                anchors.right: rightGroup.left
                anchors.rightMargin: 6
                placeholderText: Translation.tr("App (e.g. firefox)")
                text: entryRow.modelData.cmd ?? ""
                wrapMode: TextEdit.Wrap
                font.pixelSize: Appearance.font.pixelSize.normal

                property bool ready: false
                Component.onCompleted: ready = true

                onTextChanged: {
                    if (!ready) return
                    debounceTimer.restart()
                }

                Timer {
                    id: debounceTimer
                    interval: 3000
                    repeat: false
                    onTriggered: {
                        root.updateEntry(entryRow.index, "cmd", cmdArea.text)
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4

        Item { Layout.fillWidth: true }

        ToolbarPairedFab {
            visible: Config.options.hyprland.autostartApps.enable
            iconText: "add"
            onClicked: root.addEntry()
        }
    }

    // App-picker dialog - reparented onto stickyParent (the settings page,
    // when provided) so it covers the whole visible page instead of just
    // this widget's own bounds. Mirrors the ToggleDialog pattern in
    // SidebarRightContent.qml: activate the Loader first, THEN flip show
    // true, so WindowDialog's open animation actually plays.
    Loader {
        id: appPickerLoader
        parent: root.stickyParent ?? root
        // anchors.fill: parent does NOT resolve here - anchoring right after
        // reassigning this item's own parent in the same declaration doesn't
        // take effect (ends up 0x0), so size/position explicitly instead.
        x: 0
        y: 0
        width: (root.stickyParent ?? root).width
        height: (root.stickyParent ?? root).height
        z: 2000
        active: root.appPickerOpen
        sourceComponent: AppPickerDialog {
            onPicked: entry => {
                if (root.appPickerTargetIndex >= 0)
                    root.updateEntry(root.appPickerTargetIndex, "cmd", (entry.command ?? []).join(" "))
            }
        }
        onActiveChanged: {
            if (active) {
                item.show = true
                item.forceActiveFocus()
            }
        }
        Connections {
            target: appPickerLoader.item
            function onDismiss() {
                appPickerLoader.item.show = false
                root.appPickerOpen = false
            }
            function onVisibleChanged() {
                if (appPickerLoader.item && !appPickerLoader.item.visible && !root.appPickerOpen)
                    appPickerLoader.active = false
            }
        }
    }
}
