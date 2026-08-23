import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledPopup {
    id: root
    keepOpenWhileHovered: true

    readonly property var mouse: KeychronDevices.mouse
    readonly property var keyboard: KeychronDevices.keyboard
    readonly property var kbProfile: keyboard.profile
    readonly property var mouseProfile: mouse.profile

    function optionsFor(profile) {
        const count = profile?.count ?? 0
        const opts = []
        for (let i = 0; i < count; i++) {
            opts.push({ displayName: `${i + 1}`, icon: "", value: i })
        }
        return opts
    }

    ColumnLayout {
        implicitWidth: 240
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 3
            text: KeychronDevices.lastError !== "" ? KeychronDevices.lastError : Translation.tr("Keychron devices")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
            opacity: KeychronDevices.lastError !== "" ? 1 : 0.7
            elide: Text.ElideRight
        }

        GroupedList {
            Layout.fillWidth: true
            bgcolor: MonitorThemes.shellColorForItem(root, "colSurfaceContainerLow", Appearance.colors.colSurfaceContainerLow)

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "mouse"
                label: Translation.tr("M6 8K")
                value: root.mouse.connected
                    ? `${root.mouse.connection}${root.mouse.battery !== null ? " · " + root.mouse.battery + "%" + (root.mouse.charging ? " ⚡" : "") : " · " + Translation.tr("asleep")}`
                    : Translation.tr("Disconnected")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "keyboard"
                label: Translation.tr("Q3 HE")
                value: root.keyboard.connected
                    ? `${root.keyboard.connection}${root.keyboard.battery !== null ? " · " + root.keyboard.battery + "%" : ""}`
                    : Translation.tr("Disconnected")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.mouseProfile !== null
            spacing: 6

            StyledText {
                text: Translation.tr("Mouse")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                opacity: 0.6
                Layout.leftMargin: 3
            }

            ConfigSelectionArray {
                Layout.alignment: Qt.AlignRight
                options: root.optionsFor(root.mouseProfile)
                currentValue: root.mouseProfile?.current ?? -1
                onSelected: newValue => KeychronDevices.selectMouseProfile(newValue)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.kbProfile !== null
            spacing: 6

            StyledText {
                text: Translation.tr("Keyboard")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
                opacity: 0.6
                Layout.leftMargin: 3
            }

            ConfigSelectionArray {
                Layout.alignment: Qt.AlignRight
                options: root.optionsFor(root.kbProfile)
                currentValue: root.kbProfile?.current ?? -1
                onSelected: newValue => KeychronDevices.selectKeyboardProfile(newValue)
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.keyboard.connected
            wrapMode: Text.WordWrap
            text: root.kbProfile === null
                ? (root.keyboard.connection === "Bluetooth"
                    ? Translation.tr("Profile switching needs a USB/2.4G connection")
                    : Translation.tr("Profile info unavailable"))
                : Translation.tr("Battery: Fn+B on the keyboard, or connect over Bluetooth")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: MonitorThemes.shellColorForItem(root, "colOnSurfaceVariant", Appearance.colors.colOnSurfaceVariant)
            opacity: 0.5
        }
    }
}
