pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Names the current slider values as a new (or overwritten) saved preset.
// Mirrors MaterialSymbolPickerDialog.qml's shape - a WindowDialog opened
// through a page-level Loader - so it looks and behaves like every other
// dialog in Settings.
WindowDialog {
    id: root
    backgroundWidth: 320

    signal saved(string name)

    onShowChanged: if (show) {
        nameField.text = ""
        nameField.forceActiveFocus()
    }

    WindowDialogTitle {
        text: Translation.tr("Save preset")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    MaterialTextField {
        id: nameField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Preset name")
        onAccepted: root._submit()
    }

    WindowDialogButtonRow {
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }
        DialogButton {
            buttonText: Translation.tr("Save")
            enabled: nameField.text.trim().length > 0
            onClicked: root._submit()
        }
    }

    function _submit() {
        const trimmed = nameField.text.trim()
        if (trimmed.length === 0)
            return
        root.saved(trimmed)
        root.dismiss()
    }
}
