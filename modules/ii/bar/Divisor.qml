import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    readonly property string monitorName: parent?.monitorName ?? root.QsWindow.window?.screen?.name ?? ""
    property bool vertical: Config.getBarSetting(root.monitorName, ["vertical"], Config.options.bar.vertical)
    property real btnSize: 40
    property real btnSpacing: 2
    property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    property string style: Config.getBarSetting(root.monitorName, ["divider", "style"], Config.options.bar.divider.style) // "rect" - "dot" - "space"
    property int dividerSpacing: Config.getBarSetting(root.monitorName, ["divider", "spacing"], Config.options.bar.divider.spacing)

    width:  vertical ? btnSize : (root.style === "space" ? root.dividerSpacing : (1 + btnSpacing * 3))
    height: vertical ? (root.style === "space" ? root.dividerSpacing : (1 + btnSpacing * 3)) : btnSize

    Rectangle {
        visible: root.style === "rect"
        anchors.centerIn: parent
        width:  vertical ? Math.round(btnSize * 0.6) : 1
        height: vertical ? 1 : Math.round(btnSize * 0.6)
        color:  isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutlineVariant)
    }

    StyledText {
        visible: root.style === "dot"
        anchors.centerIn: parent
        text: "•"
        color: isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
        font.pixelSize: Appearance.font.pixelSize.normal
    }
}