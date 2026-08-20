import QtQuick
import qs.services
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions

Item {
    id: root
    signal clicked(event: var)
    property alias iconText: symbol.text
    property bool isActive: false
    property int acceptedMouseButtons: Qt.LeftButton
    default property alias content: customContent.data

    implicitWidth: 26
    implicitHeight: 26

    property bool hovered: mouseArea.containsMouse
    readonly property bool highlighted: hovered || isActive

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: root.highlighted ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : ColorUtils.transparentize(MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0), 0.8)

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        MaterialSymbol {
            id: symbol
            anchors.centerIn: parent
            visible: text.length > 0
            iconSize: Appearance.font.pixelSize.large
            color: root.highlighted ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }
        }

        Item {
            id: customContent
            anchors.fill: parent
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: root.acceptedMouseButtons
        onClicked: (e) => root.clicked(e)
    }
}
