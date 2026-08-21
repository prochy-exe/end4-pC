import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.common

Rectangle {
    id: root

    default property alias content: container.data
    property int padding: 12
    property int spacing: 8

    implicitHeight: 34
    implicitWidth: container.implicitWidth + padding

    radius: Appearance.rounding.full
    color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
    border.width: 1
    border.color: MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border)

    RowLayout {
        id: container
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
