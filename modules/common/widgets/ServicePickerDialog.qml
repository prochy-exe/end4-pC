import qs.services
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

WindowDialog {
    id: root
    backgroundWidth: 460
    backgroundHeight: 520

    signal picked(var service)

    property var services: []

    function refresh() {
        root.services = []
        systemServices.running = true
        userServices.running = true
    }

    function parseServices(text, scope) {
        return text.split("\n").map(line => {
            const name = line.trim().split(/\s+/)[0]
            return name && name.endsWith(".service") ? { name, scope } : null
        }).filter(entry => entry !== null)
    }

    function addServices(entries) {
        const existing = new Set(root.services.map(service => service.name + service.scope))
        root.services = root.services.concat(entries.filter(service => {
            const key = service.name + service.scope
            if (existing.has(key)) return false
            existing.add(key)
            return true
        })).sort((a, b) => (a.scope + a.name).localeCompare(b.scope + b.name))
    }

    Process {
        id: systemServices
        command: ["systemctl", "list-unit-files", "--type=service", "--no-legend", "--no-pager"]
        stdout: StdioCollector { id: systemOutput }
        onExited: root.addServices(root.parseServices(systemOutput.text, "system"))
    }

    Process {
        id: userServices
        command: ["systemctl", "--user", "list-unit-files", "--type=service", "--no-legend", "--no-pager"]
        stdout: StdioCollector { id: userOutput }
        onExited: root.addServices(root.parseServices(userOutput.text, "user"))
    }

    onShowChanged: {
        if (show) {
            root.refresh()
            searchField.forceActiveFocus()
        }
    }

    WindowDialogTitle { text: Translation.tr("Select service") }
    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    MaterialTextArea {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search services...")
        wrapMode: TextEdit.NoWrap
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: root.services.filter(service => !searchField.text || service.name.toLowerCase().includes(searchField.text.toLowerCase()))

        delegate: RippleButton {
            required property var modelData
            width: ListView.view.width
            implicitHeight: 48
            buttonRadius: Appearance.rounding.normal
            onClicked: {
                root.picked(modelData)
                root.dismiss()
            }
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
                MaterialSymbol {
                    text: modelData.scope === "user" ? "person" : "dns"
                    iconSize: Appearance.font.pixelSize.large
                    color: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
                }
                StyledText {
                    Layout.fillWidth: true
                    text: modelData.name
                    elide: Text.ElideRight
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
                }
                StyledText {
                    text: modelData.scope === "user" ? Translation.tr("User") : Translation.tr("System")
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                }
            }
        }
    }

    WindowDialogButtonRow {
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }
    }
}
