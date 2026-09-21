import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root
    property var liveBinds: []

    Process {
        id: liveBindsProc
        command: ["hyprctl", "binds", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.liveBinds = JSON.parse(text)
                } catch (error) {
                    console.warn("[Cheatsheet] Could not read active shortcuts:", error)
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") liveBindsProc.running = true
        }
    }

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

    // Include named active bindings that are not managed by Settings.
    function allEntries() {
        const defaults = KeybindManager.keybinds
            .filter(kb => !kb.disabled)
            .map(kb => ({ description: kb.description, section: kb.section, key: kb.currentKey }))
        const custom = KeybindManager.customKeybinds
            .map(c => ({ description: c.description, section: c.section, key: c.key }))
        const entries = [...defaults, ...custom]
        const descriptions = new Set(entries.map(entry => entry.description))
        const seen = new Set()
        for (const bind of root.liveBinds) {
            if (!bind.description || descriptions.has(bind.description)) continue
            const modifiers = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"],
                [2, "CAPS"], [16, "MOD2"], [32, "MOD3"], [128, "MOD5"]]
                .filter(([mask]) => bind.modmask & mask).map(([, name]) => name)
            const key = [...modifiers, bind.key || `code:${bind.keycode}`].join(" + ")
            const identity = JSON.stringify([bind.description, key, bind.submap])
            if (seen.has(identity)) continue
            seen.add(identity)
            const section = bind.description.includes(":") ? bind.description.split(":")[0] : "Custom"
            entries.push({ description: bind.description, section, key })
        }
        return entries
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
        color: MonitorThemes.shellColorForItem(root, "colScrim", Appearance.colors.colScrim)
    }

    StyledFlickable {
        id: flickable
        clip: true
        anchors.fill: parent
        anchors.margins: 40
        contentHeight: flow.implicitHeight
        contentWidth: width
        flickableDirection: Flickable.VerticalFlick

        MouseArea {
            width: flickable.width
            height: Math.max(flickable.height, flow.implicitHeight)
            onClicked: {} // swallow clicks so they don't dismiss the sheet
        }

        Flow {
            id: flow
            width: flickable.width
            flow: Flow.LeftToRight
            spacing: 24

            Repeater {
                model: root.sectionNames()
                delegate: ColumnLayout {
                    id: card
                    required property string modelData
                    width: Math.min(300, flickable.width)
                    spacing: 8

                    RowLayout {
                        spacing: 6
                        MaterialSymbol {
                            text: root.sectionIcons[card.modelData] ?? "keyboard"
                            iconSize: Appearance.font.pixelSize.larger
                            color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                        }
                        StyledText {
                            text: card.modelData
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Medium
                            color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Appearance.rounding.normal
                        color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)
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
                                        color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
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

    }

    ScrollEdgeFade {
        target: flickable
        vertical: true
        color: MonitorThemes.shellColorForItem(root, "colScrim", Appearance.colors.colScrim)
    }
}
