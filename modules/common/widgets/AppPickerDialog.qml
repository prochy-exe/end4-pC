pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// Searchable list of installed applications, backed by AppSearch (the same
// fuzzy app search the dock/launcher use). Emits picked(entry) with the
// DesktopEntry and closes itself - callers pull whatever field they need
// (entry.command.join(' ') for a launchable command line, entry.name, ...).
WindowDialog {
    id: root
    backgroundWidth: 420
    backgroundHeight: 480

    signal picked(var entry)

    onShowChanged: if (show) searchField.forceActiveFocus()

    WindowDialogTitle {
        text: Translation.tr("Select app")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    MaterialTextArea {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search apps...")
        wrapMode: TextEdit.NoWrap
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: searchField.text.length > 0 ? AppSearch.fuzzyQuery(searchField.text) : AppSearch.list

        delegate: RippleButton {
            id: appButton
            required property var modelData
            width: list.width
            implicitHeight: 48
            buttonRadius: Appearance.rounding.normal
            onClicked: {
                root.picked(appButton.modelData)
                root.dismiss()
            }
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10
                IconImage {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    source: Quickshell.iconPath(appButton.modelData.icon, "image-missing")
                }
                StyledText {
                    Layout.fillWidth: true
                    text: appButton.modelData.name
                    elide: Text.ElideRight
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
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
