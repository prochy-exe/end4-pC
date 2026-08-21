pragma ComponentBehavior: Bound
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
    property string editingId: ""
    property bool formVisible: false

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

    function schemaField(list, key) {
        return list.find(f => f.key === key) ?? {type: "string"}
    }

    function defaultValueFor(field) {
        switch (field.type) {
            case "bool": return true
            case "vec2": return ["", ""]
            case "enum": return field.options?.[0] ?? ""
            case "enum_multi": return []
            case "opacity": return ["1.0", "", ""]
            case "intpair": return [field.options?.[0] ?? "", field.options?.[0] ?? ""]
            case "monitor": return [WindowRuleManager.monitorNames?.[0] ?? "", false]
            case "int": case "float": return field.min ?? 0
            default: return ""
        }
    }

    function allowedValuesFor(field) {
        switch (field.type) {
            case "bool": return Translation.tr("On / off")
            case "string": return Translation.tr("Free text")
            case "int": case "float":
                return (field.min !== undefined && field.max !== undefined) ? `${field.min} - ${field.max}` : Translation.tr("A number")
            case "vec2": return Translation.tr("Two numbers or expressions (e.g. monitor_w*0.5), X and Y")
            case "enum": return (field.options ?? []).join(" / ")
            case "enum_multi": return Translation.tr("Any combination of: ") + (field.options ?? []).join(", ")
            case "opacity": return Translation.tr("0-1 per slot (active / inactive / fullscreen), each optionally set to \"Absolute\"")
            case "intpair": return (field.options ?? []).join(" / ") + " " + Translation.tr("(internal / client)")
            case "monitor": return Translation.tr("A connected monitor, optionally \"Silent\"")
            default: return ""
        }
    }

    function summarizeMatch(match) {
        return (match ?? []).map(m => `${m.key} ~ ${m.value}`).join(", ")
    }

    function summarizeEffects(effects) {
        return (effects ?? []).map(e => e.key).join(", ")
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        // Layout
        ContentSection {
            icon: "auto_awesome_mosaic"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Layout")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Tiling Layout")
                    icon: "responsive_layout"
                    currentValue: Config.options.hyprland.general.layout
                    onSelected: newValue => {
                        Config.options.hyprland.general.layout = newValue
                        HyprlandConfig.set("general:layout", newValue)
                    }
                    options: [
                        { displayName: Translation.tr("Dwindle"),   icon: "browse",             value: "dwindle"   },
                        { displayName: Translation.tr("Master"),    icon: "auto_awesome_mosaic", value: "master"    },
                        { displayName: Translation.tr("Scrolling"), icon: "view_carousel",       value: "scrolling" },
                    ]
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: WindowRuleManager.lastError.length > 0
            materialIcon: "error"
            text: WindowRuleManager.lastError
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("Rules apply on top of your existing hyprland config - they don't replace anything already there. Match criteria for class/title/etc. are regexes.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            RippleButtonWithIcon {
                materialIcon: page.formVisible && page.editingId === "" ? "close" : "add"
                mainText: page.formVisible && page.editingId === "" ? Translation.tr("Cancel") : Translation.tr("Add window rule")
                onClicked: {
                    if (page.formVisible && page.editingId === "") {
                        page.formVisible = false
                    } else {
                        page.editingId = ""
                        page.formVisible = true
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: page.formVisible && page.editingId === ""
            visible: active
            sourceComponent: RuleForm {
                ruleId: ""
                onDone: page.formVisible = false
            }
        }

        ContentSection {
            Layout.fillWidth: true
            visible: WindowRuleManager.rules.length > 0
            icon: "select_window_2"
            title: Translation.tr("Rules")

            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                implicitHeight: rulesColumn.implicitHeight + 16

                ColumnLayout {
                    id: rulesColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 8
                    }
                    spacing: 2

                    Repeater {
                        model: WindowRuleManager.rules
                        delegate: ColumnLayout {
                            id: ruleDelegate
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10
                            spacing: 4

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                Layout.bottomMargin: 6
                                color: MonitorThemes.shellColorForItem(page, "colOutlineVariant", Appearance.colors.colOutlineVariant)
                                opacity: 0.4
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: page.summarizeMatch(ruleDelegate.modelData.match)
                                        color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                        wrapMode: Text.Wrap
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: page.summarizeEffects(ruleDelegate.modelData.effects)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                                        wrapMode: Text.Wrap
                                    }
                                }

                                StyledSwitch {
                                    Layout.alignment: Qt.AlignTop
                                    checked: ruleDelegate.modelData.enabled
                                    onToggled: WindowRuleManager.setEnabled(ruleDelegate.modelData.id, checked)
                                }

                                RippleButton {
                                    Layout.alignment: Qt.AlignTop
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    onClicked: {
                                        page.editingId = ruleDelegate.modelData.id
                                        page.formVisible = true
                                    }
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "edit"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                    }
                                }

                                RippleButton {
                                    Layout.alignment: Qt.AlignTop
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    onClicked: WindowRuleManager.removeRule(ruleDelegate.modelData.id)
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "delete"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                    }
                                }
                            }

                            Loader {
                                Layout.fillWidth: true
                                active: page.formVisible && page.editingId === ruleDelegate.modelData.id
                                visible: active
                                sourceComponent: RuleForm {
                                    ruleId: ruleDelegate.modelData.id
                                    initialMatch: ruleDelegate.modelData.match ?? []
                                    initialEffects: ruleDelegate.modelData.effects ?? []
                                    onDone: page.formVisible = false
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            Layout.fillWidth: true
            visible: WindowRuleManager.builtinRules.length > 0
            icon: "lock"
            title: Translation.tr("Built-in rules")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Already defined in hyprland/rules.lua - shown for reference, read-only since that file gets overwritten on updates. Add your own above to customize on top of these.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: MonitorThemes.shellColorForItem(page, "colLayer1", Appearance.colors.colLayer1)
                implicitHeight: builtinColumn.implicitHeight + 16

                ColumnLayout {
                    id: builtinColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 8
                    }
                    spacing: 2

                    Repeater {
                        model: WindowRuleManager.builtinRules
                        delegate: ColumnLayout {
                            id: builtinDelegate
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10
                            spacing: 4

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                Layout.bottomMargin: 6
                                color: MonitorThemes.shellColorForItem(page, "colOutlineVariant", Appearance.colors.colOutlineVariant)
                                opacity: 0.4
                                visible: builtinDelegate.index > 0
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: page.summarizeMatch(builtinDelegate.modelData.match)
                                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                                wrapMode: Text.Wrap
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: page.summarizeEffects(builtinDelegate.modelData.effects)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }

    component CompactField: Rectangle {
        id: fieldRoot
        property alias value: input.text
        property string placeholderText: ""
        // Only fires on Enter/blur, not per-keystroke - see FieldRow's
        // callers for why (committing on every change reassigns the owning
        // Repeater's model array, which tears down and rebuilds every
        // delegate, dropping focus/drag state mid-edit).
        signal committed(string text)
        implicitWidth: 160
        implicitHeight: 34
        radius: Appearance.rounding.small
        color: MonitorThemes.shellColorForItem(page, "colLayer2", Appearance.colors.colLayer2)
        border.width: input.activeFocus ? 2 : 0
        border.color: MonitorThemes.shellColorForItem(page, "colPrimary", Appearance.colors.colPrimary)
        clip: true

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter
            color: MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
            font.pixelSize: Appearance.font.pixelSize.normal
            selectByMouse: true
            clip: true
            onEditingFinished: fieldRoot.committed(text)

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0 && !input.activeFocus
                text: fieldRoot.placeholderText
                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
            }
        }
    }

    component HelpIconButton: RippleButton {
        id: helpButton
        property bool active: false
        signal toggled()
        Layout.alignment: Qt.AlignVCenter
        buttonRadius: Appearance.rounding.full
        colBackground: active ? MonitorThemes.shellColorForItem(page, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : "transparent"
        implicitWidth: 26
        implicitHeight: 26
        onClicked: helpButton.toggled()
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: "help"
            iconSize: Appearance.font.pixelSize.large
            color: helpButton.active ? MonitorThemes.shellColorForItem(page, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) : MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
        }
        StyledToolTip {
            text: Translation.tr("What do these options mean?")
        }
    }

    component FieldRow: RowLayout {
        id: fieldRow
        required property var schema
        required property var entry
        signal changed(var newEntry)
        signal removed()

        spacing: 8
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop

        StyledComboBox {
            Layout.preferredWidth: 220
            Layout.alignment: Qt.AlignTop
            model: fieldRow.schema.map(f => f.key)
            currentIndex: fieldRow.schema.findIndex(f => f.key === fieldRow.entry.key)
            onActivated: {
                const field = fieldRow.schema[currentIndex]
                fieldRow.changed({key: field.key, value: page.defaultValueFor(field)})
            }
        }

        Loader {
            Layout.fillWidth: true
            readonly property var field: page.schemaField(fieldRow.schema, fieldRow.entry.key)
            sourceComponent: {
                switch (field.type) {
                    case "bool": return boolValueComp
                    case "vec2": return vec2ValueComp
                    case "int": case "float": return numberValueComp
                    case "enum": return enumValueComp
                    case "enum_multi": return enumMultiValueComp
                    case "opacity": return opacityValueComp
                    case "intpair": return intpairValueComp
                    case "monitor": return monitorValueComp
                    default: return stringValueComp
                }
            }

            Component {
                id: boolValueComp
                RowLayout {
                    spacing: 8
                    StyledSwitch {
                        checked: !!fieldRow.entry.value
                        onToggled: fieldRow.changed({key: fieldRow.entry.key, value: checked})
                    }
                    StyledText {
                        text: !!fieldRow.entry.value ? Translation.tr("On") : Translation.tr("Off")
                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                    }
                }
            }
            Component {
                id: stringValueComp
                CompactField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Value")
                    value: fieldRow.entry.value ?? ""
                    onCommitted: newText => fieldRow.changed({key: fieldRow.entry.key, value: newText})
                }
            }
            Component {
                id: vec2ValueComp
                RowLayout {
                    spacing: 6
                    CompactField {
                        implicitWidth: 90
                        placeholderText: "X"
                        value: (fieldRow.entry.value ?? ["", ""])[0] ?? ""
                        onCommitted: newText => fieldRow.changed({key: fieldRow.entry.key, value: [newText, (fieldRow.entry.value ?? ["", ""])[1] ?? ""]})
                    }
                    CompactField {
                        implicitWidth: 90
                        placeholderText: "Y"
                        value: (fieldRow.entry.value ?? ["", ""])[1] ?? ""
                        onCommitted: newText => fieldRow.changed({key: fieldRow.entry.key, value: [(fieldRow.entry.value ?? ["", ""])[0] ?? "", newText]})
                    }
                }
            }
            Component {
                id: numberValueComp
                RowLayout {
                    id: numRow
                    readonly property var f: page.schemaField(fieldRow.schema, fieldRow.entry.key)
                    readonly property real numValue: Number(fieldRow.entry.value ?? f.min ?? 0)
                    spacing: 8
                    StyledSlider {
                        id: numSlider
                        Layout.fillWidth: true
                        from: numRow.f.min ?? 0
                        to: numRow.f.max ?? 1
                        stepSize: numRow.f.type === "int" ? 1 : 0
                        usePercentTooltip: false
                        value: numRow.numValue
                        // Commit once on release, not on every step of the
                        // drag (onMoved) - each commit reassigns the owning
                        // Repeater's model array, tearing down and rebuilding
                        // every delegate including this slider, which cuts
                        // the drag gesture short after the first step.
                        onPressedChanged: {
                            if (!pressed)
                                fieldRow.changed({key: fieldRow.entry.key, value: numRow.f.type === "int" ? Math.round(value) : Math.round(value * 100) / 100})
                        }
                    }
                    StyledText {
                        Layout.preferredWidth: 48
                        horizontalAlignment: Text.AlignRight
                        text: numRow.f.type === "int" ? String(Math.round(numSlider.value)) : numSlider.value.toFixed(2)
                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                    }
                }
            }
            Component {
                id: enumValueComp
                StyledComboBox {
                    readonly property var f: page.schemaField(fieldRow.schema, fieldRow.entry.key)
                    Layout.fillWidth: true
                    model: f.options ?? []
                    currentIndex: Math.max(0, (f.options ?? []).indexOf(fieldRow.entry.value))
                    onActivated: fieldRow.changed({key: fieldRow.entry.key, value: f.options[currentIndex]})
                }
            }
            Component {
                id: enumMultiValueComp
                Flow {
                    readonly property var f: page.schemaField(fieldRow.schema, fieldRow.entry.key)
                    width: parent ? parent.width : implicitWidth
                    spacing: 6
                    Repeater {
                        model: parent.f.options ?? []
                        delegate: RippleButton {
                            id: chip
                            required property string modelData
                            readonly property bool active: (fieldRow.entry.value ?? []).includes(modelData)
                            buttonRadius: Appearance.rounding.small
                            implicitHeight: 28
                            colBackground: active ? MonitorThemes.shellColorForItem(page, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : MonitorThemes.shellColorForItem(page, "colLayer2", Appearance.colors.colLayer2)
                            onClicked: {
                                const current = fieldRow.entry.value ?? []
                                const next = active ? current.filter(v => v !== modelData) : [...current, modelData]
                                fieldRow.changed({key: fieldRow.entry.key, value: next})
                            }
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                leftPadding: 6
                                rightPadding: 6
                                text: chip.modelData
                                color: chip.active ? MonitorThemes.shellColorForItem(page, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) : MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
                            }
                        }
                    }
                }
            }
            Component {
                id: opacityValueComp
                ColumnLayout {
                    id: opacityRoot
                    spacing: 4

                    // Opacity is a PRODUCT of all opacities by default (this
                    // rule's value times decoration:active_opacity/
                    // inactive_opacity) - "override" makes a slot absolute
                    // instead. Without it, 1.0 doesn't necessarily mean
                    // "fully opaque" if the global opacity isn't 1.0 too.
                    function slotNumber(index) {
                        const v = (fieldRow.entry.value ?? [])[index]
                        if (v === undefined || v === "") return index === 0 ? 1 : 0
                        return Number(String(v).replace("override", "").trim())
                    }
                    function slotOverridden(index) {
                        const v = (fieldRow.entry.value ?? [])[index]
                        return typeof v === "string" && v.includes("override")
                    }
                    function setSlot(index, num, overridden) {
                        let next = (fieldRow.entry.value ?? ["", "", ""]).slice()
                        while (next.length < 3) next.push("")
                        next[index] = overridden ? `${num} override` : String(num)
                        fieldRow.changed({key: fieldRow.entry.key, value: next})
                    }

                    Repeater {
                        model: [Translation.tr("Active"), Translation.tr("Inactive"), Translation.tr("Fullscreen")]
                        delegate: RowLayout {
                            id: opacityRow
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                Layout.preferredWidth: 80
                                text: opacityRow.modelData
                                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                            }
                            StyledSlider {
                                Layout.fillWidth: true
                                from: 0
                                to: 1
                                usePercentTooltip: true
                                value: opacityRoot.slotNumber(opacityRow.index)
                                // Commit on release only - see numberValueComp's
                                // slider for why (onMoved commits per-step,
                                // which tears down the delegate mid-drag).
                                onPressedChanged: {
                                    if (!pressed)
                                        opacityRoot.setSlot(opacityRow.index, Math.round(value * 100) / 100, opacityRoot.slotOverridden(opacityRow.index))
                                }
                            }
                            Item {
                                id: absoluteHoverArea
                                // StyledToolTip shows based on parent.hovered
                                // - a bare RowLayout has no such property, so
                                // it fell back to "always visible" for all
                                // three rows at once. This Item supplies one.
                                readonly property bool hovered: absoluteMouseArea.containsMouse
                                implicitWidth: absoluteRow.implicitWidth
                                implicitHeight: absoluteRow.implicitHeight

                                RowLayout {
                                    id: absoluteRow
                                    anchors.fill: parent
                                    spacing: 4
                                    StyledSwitch {
                                        scale: 0.7
                                        checked: opacityRoot.slotOverridden(opacityRow.index)
                                        onToggled: opacityRoot.setSlot(opacityRow.index, opacityRoot.slotNumber(opacityRow.index), checked)
                                    }
                                    StyledText {
                                        text: Translation.tr("Absolute")
                                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                                MouseArea {
                                    id: absoluteMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }
                                StyledToolTip {
                                    text: Translation.tr("Off: multiplied with the global active/inactive opacity.\nOn: this exact value, ignoring the global setting.")
                                }
                            }
                        }
                    }
                }
            }
            Component {
                id: monitorValueComp
                RowLayout {
                    id: monitorRow
                    // The currently stored monitor might belong to a display
                    // that's since been unplugged - keep it selectable/visible
                    // instead of silently swapping it out for whatever's first.
                    readonly property string currentName: (fieldRow.entry.value ?? ["", false])[0] ?? ""
                    readonly property bool currentSilent: !!(fieldRow.entry.value ?? ["", false])[1]
                    readonly property var options: {
                        const live = WindowRuleManager.monitorNames ?? []
                        return (monitorRow.currentName && !live.includes(monitorRow.currentName)) ? [monitorRow.currentName, ...live] : live
                    }
                    spacing: 8
                    StyledComboBox {
                        Layout.fillWidth: true
                        model: monitorRow.options
                        currentIndex: Math.max(0, monitorRow.options.indexOf(monitorRow.currentName))
                        onActivated: fieldRow.changed({key: fieldRow.entry.key, value: [monitorRow.options[currentIndex], monitorRow.currentSilent]})
                    }
                    Item {
                        id: silentHoverArea
                        readonly property bool hovered: silentMouseArea.containsMouse
                        implicitWidth: silentRow.implicitWidth
                        implicitHeight: silentRow.implicitHeight
                        RowLayout {
                            id: silentRow
                            anchors.fill: parent
                            spacing: 4
                            StyledSwitch {
                                scale: 0.7
                                checked: monitorRow.currentSilent
                                onToggled: fieldRow.changed({key: fieldRow.entry.key, value: [monitorRow.currentName, checked]})
                            }
                            StyledText {
                                text: Translation.tr("Silent")
                                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        MouseArea {
                            id: silentMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                        StyledToolTip {
                            text: Translation.tr("Move the window without also switching your active monitor/workspace to it.")
                        }
                    }
                }
            }
            Component {
                id: intpairValueComp
                RowLayout {
                    readonly property var f: page.schemaField(fieldRow.schema, fieldRow.entry.key)
                    spacing: 8
                    StyledComboBox {
                        Layout.fillWidth: true
                        model: parent.f.options ?? []
                        currentIndex: Math.max(0, (parent.f.options ?? []).indexOf((fieldRow.entry.value ?? [])[0]))
                        onActivated: {
                            let next = (fieldRow.entry.value ?? ["", ""]).slice()
                            next[0] = parent.f.options[currentIndex]
                            fieldRow.changed({key: fieldRow.entry.key, value: next})
                        }
                        StyledToolTip { text: Translation.tr("Internal (e.g. tiling layout) state") }
                    }
                    StyledText { text: "/"; color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext) }
                    StyledComboBox {
                        Layout.fillWidth: true
                        model: parent.f.options ?? []
                        currentIndex: Math.max(0, (parent.f.options ?? []).indexOf((fieldRow.entry.value ?? [])[1]))
                        onActivated: {
                            let next = (fieldRow.entry.value ?? ["", ""]).slice()
                            next[1] = parent.f.options[currentIndex]
                            fieldRow.changed({key: fieldRow.entry.key, value: next})
                        }
                        StyledToolTip { text: Translation.tr("Client-requested state") }
                    }
                }
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignTop
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            implicitWidth: 28
            implicitHeight: 28
            onClicked: fieldRow.removed()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: Appearance.font.pixelSize.large
                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
            }
        }
    }

    component FieldHelpPanel: Rectangle {
        id: helpPanel
        required property var schema
        property string note: ""
        property var extraOptions: []
        property string extraOptionsTitle: ""

        Layout.fillWidth: true
        radius: Appearance.rounding.normal
        color: MonitorThemes.shellColorForItem(page, "colLayer2", Appearance.colors.colLayer2)
        implicitHeight: helpColumn.implicitHeight + 20

        ColumnLayout {
            id: helpColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 10

            StyledText {
                Layout.fillWidth: true
                visible: helpPanel.note.length > 0
                text: helpPanel.note
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                wrapMode: Text.Wrap
            }

            Repeater {
                model: helpPanel.schema
                delegate: ColumnLayout {
                    id: helpRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 1

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.bottomMargin: 5
                        color: MonitorThemes.shellColorForItem(page, "colOutlineVariant", Appearance.colors.colOutlineVariant)
                        opacity: 0.4
                        visible: helpRow.index > 0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: helpRow.modelData.key
                        color: MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
                        font.weight: Font.Medium
                        font.family: Appearance.font.family.monospace ?? font.family
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: helpRow.modelData.description ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Allowed: ") + page.allowedValuesFor(helpRow.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                        wrapMode: Text.Wrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: helpPanel.extraOptions.length > 0
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.bottomMargin: 5
                    color: MonitorThemes.shellColorForItem(page, "colOutlineVariant", Appearance.colors.colOutlineVariant)
                    opacity: 0.4
                }
                StyledText {
                    Layout.fillWidth: true
                    text: helpPanel.extraOptionsTitle
                    color: MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: helpPanel.extraOptions
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            Layout.preferredWidth: 140
                            text: modelData.option
                            font.family: Appearance.font.family.monospace ?? font.family
                            color: MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
                            wrapMode: Text.Wrap
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.description
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: MonitorThemes.shellColorForItem(page, "colSubtext", Appearance.colors.colSubtext)
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }

    component RuleForm: ColumnLayout {
        id: form
        required property string ruleId
        property var initialMatch: []
        property var initialEffects: []
        signal done()

        property var matchList: JSON.parse(JSON.stringify(initialMatch))
        property var effectList: JSON.parse(JSON.stringify(initialEffects))
        property string formError: ""
        // Candidate selectors from the last "Pick window" click - shown as
        // toggleable chips so picking a window offers a choice (class,
        // title, initial_class, initial_title) instead of only ever adding
        // class, which alone can be too broad (e.g. a PiP popup shares its
        // class with the browser's main window).
        property var pickedCandidates: []
        property bool showMatchHelp: false
        property bool showEffectHelp: false

        Layout.fillWidth: true
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StyledText {
                text: Translation.tr("Match criteria")
                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                font.weight: Font.Medium
            }
            HelpIconButton {
                active: form.showMatchHelp
                onToggled: form.showMatchHelp = !form.showMatchHelp
            }
            Item { Layout.fillWidth: true }
            RippleButtonWithIcon {
                materialIcon: "my_location"
                mainText: Translation.tr("Pick window")
                onClicked: {
                    form.formError = ""
                    WindowRuleManager.pickWindow()
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: form.showMatchHelp
            visible: active
            sourceComponent: FieldHelpPanel {
                schema: WindowRuleManager.matchSchema
                note: Translation.tr("Text fields are regular expressions (RE2 syntax). Prefix with \"negative:\" to match when it does NOT match, e.g. \"negative:kitty\".")
            }
        }

        Connections {
            target: WindowRuleManager
            function onWindowPicked(cls, title, initialClass, initialTitle) {
                form.formError = ""
                const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
                let candidates = []
                if (cls) candidates.push({key: "class", value: `^${escape(cls)}$`})
                if (title) candidates.push({key: "title", value: `^${escape(title)}$`})
                if (initialClass && initialClass !== cls) candidates.push({key: "initial_class", value: `^${escape(initialClass)}$`})
                if (initialTitle && initialTitle !== title) candidates.push({key: "initial_title", value: `^${escape(initialTitle)}$`})
                form.pickedCandidates = candidates
            }
            function onPickFailed(error) {
                form.formError = error
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: form.pickedCandidates.length > 0
            spacing: 6

            Repeater {
                model: form.pickedCandidates
                delegate: RippleButton {
                    id: candidateChip
                    required property var modelData
                    readonly property bool active: form.matchList.some(m => m.key === modelData.key && m.value === modelData.value)
                    buttonRadius: Appearance.rounding.small
                    implicitHeight: 28
                    colBackground: active ? MonitorThemes.shellColorForItem(page, "colPrimaryContainer", Appearance.colors.colPrimaryContainer) : MonitorThemes.shellColorForItem(page, "colLayer2", Appearance.colors.colLayer2)
                    onClicked: {
                        if (candidateChip.active) {
                            form.matchList = form.matchList.filter(m => !(m.key === candidateChip.modelData.key && m.value === candidateChip.modelData.value))
                        } else {
                            let next = form.matchList.filter(m => m.key !== candidateChip.modelData.key)
                            next.push(candidateChip.modelData)
                            form.matchList = next
                        }
                    }
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        leftPadding: 8
                        rightPadding: 8
                        text: `${candidateChip.modelData.key}: ${candidateChip.modelData.value}`
                        color: candidateChip.active ? MonitorThemes.shellColorForItem(page, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer) : MonitorThemes.shellColorForItem(page, "colOnLayer2", Appearance.colors.colOnLayer2)
                    }
                    StyledToolTip {
                        text: candidateChip.active ? Translation.tr("Click to remove from match criteria") : Translation.tr("Click to add to match criteria")
                    }
                }
            }
        }

        Repeater {
            model: form.matchList
            delegate: FieldRow {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                schema: WindowRuleManager.matchSchema
                entry: modelData
                onChanged: newEntry => {
                    let next = form.matchList.slice()
                    next[index] = newEntry
                    form.matchList = next
                }
                onRemoved: {
                    let next = form.matchList.slice()
                    next.splice(index, 1)
                    form.matchList = next
                }
            }
        }

        RippleButtonWithIcon {
            materialIcon: "add"
            mainText: Translation.tr("Add match criterion")
            enabled: WindowRuleManager.matchSchema.length > 0
            onClicked: {
                const first = WindowRuleManager.matchSchema[0]
                form.matchList = [...form.matchList, {key: first.key, value: page.defaultValueFor(first)}]
            }
        }

        RowLayout {
            Layout.topMargin: 8
            Layout.fillWidth: true
            spacing: 10
            StyledText {
                text: Translation.tr("Effects")
                color: MonitorThemes.shellColorForItem(page, "colOnLayer1", Appearance.colors.colOnLayer1)
                font.weight: Font.Medium
            }
            HelpIconButton {
                active: form.showEffectHelp
                onToggled: form.showEffectHelp = !form.showEffectHelp
            }
            Item { Layout.fillWidth: true }
        }

        Loader {
            Layout.fillWidth: true
            active: form.showEffectHelp
            visible: active
            sourceComponent: FieldHelpPanel {
                schema: WindowRuleManager.effectSchema
                note: Translation.tr("Effects marked \"Dynamic\" in the wiki are re-evaluated whenever the matching property changes; the rest apply once, at open.")
                extraOptions: WindowRuleManager.groupOptions
                extraOptionsTitle: Translation.tr("\"group\" options (space-separated, can combine several)")
            }
        }

        Repeater {
            model: form.effectList
            delegate: FieldRow {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                schema: WindowRuleManager.effectSchema
                entry: modelData
                onChanged: newEntry => {
                    let next = form.effectList.slice()
                    next[index] = newEntry
                    form.effectList = next
                }
                onRemoved: {
                    let next = form.effectList.slice()
                    next.splice(index, 1)
                    form.effectList = next
                }
            }
        }

        RippleButtonWithIcon {
            materialIcon: "add"
            mainText: Translation.tr("Add effect")
            enabled: WindowRuleManager.effectSchema.length > 0
            onClicked: {
                const first = WindowRuleManager.effectSchema[0]
                form.effectList = [...form.effectList, {key: first.key, value: page.defaultValueFor(first)}]
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: form.formError.length > 0
            text: form.formError
            color: MonitorThemes.shellColorForItem(page, "colError", Appearance.colors.colError)
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.topMargin: 8
            spacing: 8
            RippleButtonWithIcon {
                materialIcon: "check"
                mainText: form.ruleId === "" ? Translation.tr("Add") : Translation.tr("Save")
                enabled: form.matchList.length > 0 && form.effectList.length > 0
                onClicked: {
                    const payload = {match: form.matchList, effects: form.effectList}
                    if (form.ruleId === "") WindowRuleManager.addRule(payload)
                    else WindowRuleManager.updateRule(form.ruleId, payload)
                    form.done()
                }
            }
            RippleButtonWithIcon {
                materialIcon: "close"
                mainText: Translation.tr("Cancel")
                onClicked: form.done()
            }
        }
    }
}
