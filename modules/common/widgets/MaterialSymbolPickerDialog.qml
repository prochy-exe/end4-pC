pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Searchable grid of Material Symbol names, backed by MaterialSymbolsSearch
// (services/MaterialSymbolsSearch.qml - the same fuzzy icon search the
// launcher's ":symbol" prefix already uses). Emits picked(name) and closes
// itself - callers just wire onPicked to write wherever the icon name goes.
WindowDialog {
    id: root
    backgroundWidth: 420
    backgroundHeight: 480

    signal picked(string iconName)

    onShowChanged: if (show) searchField.forceActiveFocus()

    WindowDialogTitle {
        text: Translation.tr("Select icon")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    MaterialTextArea {
        id: searchField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search icons (e.g. wifi)")
        wrapMode: TextEdit.NoWrap
    }

    GridView {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        cellWidth: 84
        cellHeight: 84
        model: MaterialSymbolsSearch.fuzzyQuery(searchField.text)

        delegate: Item {
            id: delegateItem
            required property string modelData
            readonly property int tabIdx: modelData.indexOf("\t")
            readonly property string iconName: tabIdx >= 0 ? modelData.slice(0, tabIdx) : modelData
            width: 84
            height: 84

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: delegateItem.iconName
                    iconSize: 28
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 78
                    text: delegateItem.iconName
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.picked(delegateItem.iconName)
                    root.dismiss()
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1)
                    opacity: mouseArea.containsMouse ? 0.3 : 0
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
