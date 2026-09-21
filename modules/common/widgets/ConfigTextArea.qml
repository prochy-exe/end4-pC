import qs.services
import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RowLayout {
    id: root

    property string text: ""
    property string description: ""
    property string buttonIcon: ""
    property alias placeholderText: textArea.placeholderText
    property alias value: textArea.text
    property alias textArea: textArea
    property bool filled: true
    property bool showBorder: !filled
    property bool rounded: false
    property real fieldWidth: 220
    property real fieldHeight: 40
    property color colBackground: filled ? MonitorThemes.shellColorForItem(root, "colLayer1", Appearance.colors.colLayer1) : "transparent"
    property color colBackgroundFocused: filled ? MonitorThemes.shellColorForItem(root, "colLayer2", Appearance.colors.colLayer2) : "transparent"
    property color colBorder: MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutlineVariant)
    property color colBorderFocused: MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
    property color colOnBackground: MonitorThemes.shellColorForItem(root, "colOnLayer1", Appearance.colors.colOnLayer1)
    property color colLabel: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
    property real cornerRadius: rounded ? Appearance.rounding.large : Appearance.rounding.small

    property bool confirmButtonVisible: false
    property string confirmButtonIcon: "check"
    property color colConfirmBackground: MonitorThemes.shellColorForItem(root, "colPrimaryContainer", Appearance.colors.colPrimaryContainer)
    property color colConfirmBackgroundHover: MonitorThemes.shellColorForItem(root, "colPrimaryContainerHover", Appearance.colors.colPrimaryContainerHover)
    property color colConfirmBackgroundActive: MonitorThemes.shellColorForItem(root, "colPrimaryContainerActive", Appearance.colors.colPrimaryContainerActive)
    property color colOnConfirmBackground: MonitorThemes.shellColorForItem(root, "colOnPrimaryContainer", Appearance.colors.colOnPrimaryContainer)
    signal confirmClicked()
    signal focusLost()

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
        opacity: root.enabled ? 1 : 0.4
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.text
            color: root.colLabel
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
            wrapMode: Text.Wrap
            opacity: root.enabled ? 1 : 0.4
        }
    }

    Rectangle {
        id: fieldBg
        Layout.preferredWidth: root.fieldWidth
        Layout.preferredHeight: root.fieldHeight
        Layout.alignment: Qt.AlignVCenter
        radius: root.cornerRadius
        clip: true
        opacity: root.enabled ? 1 : 0.4
        color: textArea.activeFocus ? root.colBackgroundFocused : root.colBackground
        border.width: (hoverHandler.hovered || textArea.activeFocus) ? (textArea.activeFocus ? 2 : 1) : 0
        border.color: textArea.activeFocus ? root.colBorderFocused : root.colBorder

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
        Behavior on border.color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
        Behavior on border.width {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        HoverHandler {
            id: hoverHandler
        }

        TextArea {
            id: textArea
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            enabled: root.enabled
            wrapMode: TextArea.Wrap
            verticalAlignment: TextEdit.AlignVCenter
            selectByMouse: true
            placeholderTextColor: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
            color: root.colOnBackground
            selectedTextColor: MonitorThemes.shellColorForItem(root, "colOnSecondaryContainer", Appearance.colors.colOnSecondaryContainer)
            selectionColor: MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
            renderType: Text.NativeRendering
            background: null
            padding: 0
            font {
                family: Appearance.font.family.main
                pixelSize: Appearance.font.pixelSize.small
                hintingPreference: Font.PreferFullHinting
                variableAxes: Appearance.font.variableAxes.main
            }
            property bool hadFocus: false
            onActiveFocusChanged: {
                if (activeFocus) hadFocus = true
                else if (hadFocus) root.focusLost()
            }
        }
    }

    Rectangle {
        id: confirmBtn
        visible: root.confirmButtonVisible
        opacity: root.enabled ? 1 : 0.4
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        Layout.alignment: Qt.AlignVCenter
        radius: Appearance.rounding.small
        color: confirmMouseArea.pressed
            ? root.colConfirmBackgroundActive
            : (confirmMouseArea.containsMouse ? root.colConfirmBackgroundHover : root.colConfirmBackground)

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.confirmButtonIcon
            iconSize: Appearance.font.pixelSize.large
            color: root.colOnConfirmBackground
        }

        MouseArea {
            id: confirmMouseArea
            anchors.fill: parent
            enabled: root.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.confirmClicked()
        }
    }
}
