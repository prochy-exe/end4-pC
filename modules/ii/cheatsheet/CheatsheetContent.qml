import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property var sectionIcons: ({
        "Apps": "apps",
        "Media": "music_note",
        "Other": "tune",
        "Screen": "monitor",
        "Session": "power_settings_new",
        "Utilities": "build",
        "Window": "select_window_2",
        "Workspace": "grid_view",
        "Custom": "terminal",
    })

    // Merges default (rebindable) and user-created custom keybinds into one
    // flat, always-current list - reflects rebinds/disables/custom binds live,
    // since it reads straight from KeybindManager (same source the Keybinds
    // settings page uses). Disabled shortcuts (no key bound) are hidden.
    function allEntries() {
        const defaults = KeybindManager.keybinds
            .filter(kb => !kb.disabled)
            .map(kb => ({ description: kb.description, section: kb.section, key: kb.currentKey }))
        const custom = KeybindManager.customKeybinds
            .map(c => ({ description: c.description, section: c.section, key: c.key }))
        return [...defaults, ...custom]
    }

    function sectionNames() {
        const set = new Set(root.allEntries().map(e => e.section))
        return [...set].sort()
    }

    function entriesForSection(name) {
        return root.allEntries()
            .filter(e => e.section === name)
            .sort((a, b) => a.description.localeCompare(b.description))
    }

    // The section name is already shown as the card header, so strip the
    // "Category: " prefix from each row's own description.
    function displayName(description) {
        const idx = description.indexOf(":")
        return idx === -1 ? description : description.slice(idx + 1).trim()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: GlobalStates.cheatsheetOpen = false
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
    }

    StyledFlickable {
        id: flickable
        clip: true
        anchors.fill: parent
        anchors.margins: 40
        contentHeight: height
        contentWidth: flow.implicitWidth

        MouseArea {
            width: flow.implicitWidth
            height: flickable.height
            onClicked: {} // swallow clicks so they don't dismiss the sheet
        }

        Flow {
            id: flow
            height: flickable.height
            flow: Flow.TopToBottom
            spacing: 24

            Repeater {
                model: root.sectionNames()
                delegate: ColumnLayout {
                    id: card
                    required property string modelData
                    width: 300
                    spacing: 8

                    RowLayout {
                        spacing: 6
                        MaterialSymbol {
                            text: root.sectionIcons[card.modelData] ?? "keyboard"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: card.modelData
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        clip: true
                        implicitHeight: rowsCol.implicitHeight + 16

                        ColumnLayout {
                            id: rowsCol
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 8
                            }
                            spacing: 8

                            Repeater {
                                model: root.entriesForSection(card.modelData)
                                // A row per entry, description above key chips rather than
                                // side by side: RowLayout doesn't grow its height to fit
                                // wrapped text (it sizes the row before wrapping is
                                // resolved), which is what let long descriptions and long
                                // key combos bleed into the row below/next to them.
                                // Stacking vertically gives each its own full card width to
                                // wrap or flow within, so nothing has to fight the other for
                                // horizontal space.
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: root.displayName(modelData.description)
                                        color: Appearance.colors.colOnLayer1
                                        wrapMode: Text.WordWrap
                                    }
                                    KeyChips {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        keyString: modelData.key
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ScrollEdgeFade {
            target: flickable
            vertical: false
            color: Appearance.colors.colLayer0Base
        }
    }
}
