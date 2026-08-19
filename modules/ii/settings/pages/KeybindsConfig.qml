import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    forceWidth: true
    property string filterText: ""
    property bool addCustomFormVisible: false

    readonly property var sectionIcons: ({
        "Apps": "apps",
        "Media": "music_note",
        "Other": "tune",
        "Screen": "monitor",
        "Session": "power_settings_new",
        "Utilities": "build",
        "Window": "select_window_2",
        "Workspace": "grid_view",
    })

    readonly property string customSectionName: "Custom"

    function sectionNames() {
        const set = new Set(KeybindManager.keybinds.map(kb => kb.section))
        KeybindManager.customKeybinds.forEach(c => set.add(c.section))
        set.add(page.customSectionName)
        return [...set].sort()
    }

    function keybindsForSection(name) {
        const q = page.filterText.trim().toLowerCase()
        return KeybindManager.keybinds.filter(kb => kb.section === name
            && (!q || kb.description.toLowerCase().includes(q) || (kb.currentKey ?? "").toLowerCase().includes(q)))
    }

    function customBindsForSection(name) {
        const q = page.filterText.trim().toLowerCase()
        return KeybindManager.customKeybinds.filter(c => c.section === name
            && (!q || c.description.toLowerCase().includes(q) || c.key.toLowerCase().includes(q)))
    }

    function conflictFor(description, keyString) {
        const defaultConflict = KeybindManager.keybinds.find(kb => kb.description !== description && kb.currentKey === keyString)
        if (defaultConflict) return defaultConflict
        return KeybindManager.customKeybinds.find(c => c.description !== description && c.key === keyString) ?? null
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ConfigTextArea {
                Layout.fillWidth: true
                buttonIcon: "search"
                text: Translation.tr("Search")
                placeholderText: Translation.tr("Filter by name or key...")
                fieldWidth: 260
                fieldHeight: 36
                onValueChanged: page.filterText = value
            }

            RippleButtonWithIcon {
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset all")
                visible: KeybindManager.keybinds.some(kb => kb.overridden)
                onClicked: KeybindManager.resetAll()
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: KeybindManager.lastError.length > 0
            materialIcon: "error"
            text: KeybindManager.lastError
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("Click a key combo to record a new one; Esc while recording disables that shortcut entirely, clicking away cancels. Mouse-button shortcuts aren't listed here - edit ~/.config/hypr/custom/keybinds.lua directly for those.")
        }

        Repeater {
            model: page.sectionNames()
            delegate: ContentSection {
                required property string modelData
                readonly property bool isCustomSection: modelData === page.customSectionName
                Layout.fillWidth: true
                visible: isCustomSection || page.keybindsForSection(modelData).length > 0 || page.customBindsForSection(modelData).length > 0
                icon: page.sectionIcons[modelData] ?? "keyboard"
                title: modelData

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: modelData === page.customSectionName
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RippleButtonWithIcon {
                            materialIcon: page.addCustomFormVisible ? "close" : "add"
                            mainText: page.addCustomFormVisible ? Translation.tr("Cancel") : Translation.tr("Add custom keybind")
                            onClicked: page.addCustomFormVisible = !page.addCustomFormVisible
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: page.addCustomFormVisible
                        sourceComponent: AddCustomKeybindForm {
                            onAdded: page.addCustomFormVisible = false
                            onCancelled: page.addCustomFormVisible = false
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    visible: page.keybindsForSection(modelData).length > 0 || page.customBindsForSection(modelData).length > 0
                    implicitHeight: rowsColumn.implicitHeight + 16

                    ColumnLayout {
                        id: rowsColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 8
                        }
                        spacing: 2

                        Repeater {
                            model: page.keybindsForSection(modelData)
                            delegate: KeybindRow {
                                required property var modelData
                                keybind: modelData
                            }
                        }

                        Repeater {
                            model: page.customBindsForSection(modelData)
                            delegate: CustomKeybindRow {
                                required property var modelData
                                entry: modelData
                            }
                        }
                    }
                }
            }
        }
    }

    component KeybindRow: ColumnLayout {
        id: row
        required property var keybind
        readonly property bool isMouseBind: row.keybind.defaultKey.includes("mouse:")
        property bool recording: false
        property string conflictWarning: ""

        Layout.fillWidth: true
        Layout.bottomMargin: 10
        spacing: 4

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.bottomMargin: 6
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: row.keybind.description
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: row.keybind.overridden
                    text: Translation.tr("Default: ") + row.keybind.defaultKey
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Loader {
                Layout.alignment: Qt.AlignTop
                active: row.recording
                sourceComponent: KeyRecorder {
                    onAccepted: newKey => {
                        row.recording = false
                        const conflict = page.conflictFor(row.keybind.description, newKey)
                        row.conflictWarning = conflict
                            ? Translation.tr("Also bound to: ") + conflict.description
                            : ""
                        KeybindManager.setBind(row.keybind.description, newKey)
                    }
                    onDisabled: {
                        row.recording = false
                        row.conflictWarning = ""
                        KeybindManager.disableBind(row.keybind.description)
                    }
                    onCancelled: row.recording = false
                }
            }

            RippleButton {
                visible: !row.recording
                Layout.alignment: Qt.AlignTop
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                implicitHeight: Math.max(32, chipsLoader.implicitHeight)
                enabled: !row.isMouseBind
                onClicked: row.recording = true
                contentItem: Loader {
                    id: chipsLoader
                    sourceComponent: row.keybind.disabled ? disabledPillComponent : keyChipsComponent
                    Component {
                        id: disabledPillComponent
                        StyledText {
                            text: Translation.tr("Disabled")
                            color: Appearance.colors.colSubtext
                            font.italic: true
                        }
                    }
                    Component {
                        id: keyChipsComponent
                        KeyChips { keyString: row.keybind.currentKey ?? "" }
                    }
                }
            }

            RippleButton {
                visible: row.keybind.overridden
                Layout.alignment: Qt.AlignTop
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                implicitWidth: 28
                implicitHeight: 28
                onClicked: {
                    row.conflictWarning = ""
                    KeybindManager.resetBind(row.keybind.description)
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: row.isMouseBind
            text: Translation.tr("Bound to a mouse button - not rebindable here")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            visible: row.conflictWarning.length > 0
            text: row.conflictWarning
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }
    }

    component KeyRecorder: RippleButton {
        id: recorder
        signal accepted(string keyString)
        signal disabled()
        signal cancelled()
        property string liveText: ""
        property bool settled: false

        focus: true
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colPrimaryContainer
        implicitHeight: 32
        horizontalPadding: 10

        Component.onCompleted: recorder.forceActiveFocus()
        onActiveFocusChanged: {
            if (!activeFocus && !recorder.settled) {
                recorder.settled = true
                recorder.cancelled()
            }
        }

        contentItem: StyledText {
            text: recorder.liveText || Translation.tr("Press keys… (Esc clears, click away cancels)")
            color: Appearance.colors.colOnPrimaryContainer
        }

        Keys.onPressed: event => {
            event.accepted = true
            if (event.key === Qt.Key_Escape) {
                recorder.settled = true
                recorder.disabled()
                return
            }
            if (HyprKeyNames.isModifierKey(event.key)) {
                recorder.liveText = HyprKeyNames.modifierList(event.modifiers).join(" + ")
                return
            }
            const keyName = HyprKeyNames.resolveKey(event.key, event.nativeScanCode)
            if (!keyName) {
                recorder.liveText = Translation.tr("Unsupported key")
                return
            }
            const mods = HyprKeyNames.modifierList(event.modifiers)
            if (mods.length === 0 && !HyprKeyNames.allowsNoModifier(keyName)) {
                recorder.liveText = Translation.tr("Needs a modifier key")
                return
            }
            recorder.settled = true
            recorder.accepted([...mods, keyName].join(" + "))
        }
    }

    component CommandField: Rectangle {
        id: fieldRoot
        property alias value: textArea.text
        property string placeholderText: ""
        signal committed(string text)

        implicitHeight: Math.max(36, textArea.implicitHeight + 16)
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        border.width: textArea.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
        clip: true

        TextArea {
            id: textArea
            anchors.fill: parent
            anchors.margins: 8
            wrapMode: TextArea.Wrap
            selectByMouse: true
            color: Appearance.colors.colOnLayer2
            placeholderTextColor: Appearance.colors.colSubtext
            placeholderText: fieldRoot.placeholderText
            background: null
            renderType: Text.NativeRendering
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            onEditingFinished: fieldRoot.committed(text)
        }
    }

    component CustomKeybindRow: ColumnLayout {
        id: customRow
        required property var entry
        property bool recording: false
        property string conflictWarning: ""

        Layout.fillWidth: true
        Layout.bottomMargin: 10
        spacing: 4

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.bottomMargin: 6
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: customRow.entry.description
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Custom")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Loader {
                Layout.alignment: Qt.AlignTop
                active: customRow.recording
                sourceComponent: KeyRecorder {
                    onAccepted: newKey => {
                        customRow.recording = false
                        const conflict = page.conflictFor(customRow.entry.description, newKey)
                        customRow.conflictWarning = conflict
                            ? Translation.tr("Also bound to: ") + conflict.description
                            : ""
                        KeybindManager.updateCustomBind(customRow.entry.id, customRow.entry.description, newKey, customRow.entry.command)
                    }
                    onDisabled: customRow.recording = false
                    onCancelled: customRow.recording = false
                }
            }

            RippleButton {
                visible: !customRow.recording
                Layout.alignment: Qt.AlignTop
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                implicitHeight: Math.max(32, customChips.implicitHeight)
                onClicked: customRow.recording = true
                contentItem: KeyChips { id: customChips; keyString: customRow.entry.key }
            }

            RippleButton {
                Layout.alignment: Qt.AlignTop
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                implicitWidth: 28
                implicitHeight: 28
                onClicked: KeybindManager.removeCustomBind(customRow.entry.id)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        CommandField {
            Layout.fillWidth: true
            visible: customRow.entry.kind !== "lua"
            Component.onCompleted: value = customRow.entry.command
            onCommitted: newText => {
                if (newText.trim().length === 0 || newText === customRow.entry.command) return
                KeybindManager.updateCustomBind(customRow.entry.id, customRow.entry.description, customRow.entry.key, newText)
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: customRow.entry.kind === "lua"
            text: Translation.tr("Native Hyprland action")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            font.italic: true
        }

        StyledText {
            Layout.fillWidth: true
            visible: customRow.conflictWarning.length > 0
            text: customRow.conflictWarning
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }
    }

    component AddCustomKeybindForm: ColumnLayout {
        id: form
        signal added()
        signal cancelled()
        property string keyValue: ""
        property bool recording: false

        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 8

        ConfigTextArea {
            id: descField
            Layout.fillWidth: true
            buttonIcon: "label"
            text: Translation.tr("Name")
            placeholderText: Translation.tr("e.g. Launch htop")
            fieldWidth: 260
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            spacing: 10

            StyledText {
                text: Translation.tr("Key")
                color: Appearance.colors.colOnLayer1
            }

            Loader {
                active: form.recording
                sourceComponent: KeyRecorder {
                    onAccepted: newKey => {
                        form.keyValue = newKey
                        form.recording = false
                    }
                    onDisabled: form.recording = false
                    onCancelled: form.recording = false
                }
            }

            RippleButton {
                visible: !form.recording
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                implicitHeight: Math.max(32, formChipsLoader.implicitHeight)
                onClicked: form.recording = true
                contentItem: Loader {
                    id: formChipsLoader
                    sourceComponent: form.keyValue ? keyChipsComp : placeholderComp
                    Component {
                        id: keyChipsComp
                        KeyChips { keyString: form.keyValue }
                    }
                    Component {
                        id: placeholderComp
                        StyledText {
                            text: Translation.tr("Click to set")
                            color: Appearance.colors.colSubtext
                            font.italic: true
                        }
                    }
                }
            }
        }

        CommandField {
            id: commandField
            Layout.fillWidth: true
            Layout.leftMargin: 8
            placeholderText: Translation.tr("Shell command to run")
        }

        RowLayout {
            Layout.leftMargin: 8
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "add"
                mainText: Translation.tr("Add")
                enabled: descField.value.trim().length > 0 && form.keyValue.length > 0 && commandField.value.trim().length > 0
                onClicked: {
                    KeybindManager.addCustomBind(descField.value.trim(), form.keyValue, commandField.value)
                    form.added()
                }
            }
            RippleButtonWithIcon {
                materialIcon: "close"
                mainText: Translation.tr("Cancel")
                onClicked: form.cancelled()
            }
        }
    }
}
