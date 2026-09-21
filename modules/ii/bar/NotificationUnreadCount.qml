import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MaterialSymbol {
    id: root
    property string monitorName: ""
    readonly property bool isMaterial: Config.getBarSetting(root.monitorName, ["cornerStyle"], Config.options.bar.cornerStyle) === 3
    readonly property bool showUnreadCount: Config.getBarSetting(root.monitorName, ["indicators", "notifications", "showUnreadCount"], Config.options.bar.indicators.notifications.showUnreadCount)
    property color iconColor: root.isMaterial ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.pixelSize.larger
    color: iconColor

    property real pulseScale: 1
    scale: pulseScale

    SequentialAnimation on pulseScale {
        running: !Notifications.silent && Notifications.unread > 0
        loops: Animation.Infinite
        NumberAnimation { to: 1.14; duration: 450; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 700 }
    }

    Rectangle {
        id: notifPing
        visible: !Notifications.silent && Notifications.unread > 0
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        radius: Appearance.rounding.full
        color: root.isMaterial ? MonitorThemes.shellColorForItem(root, "colOnPrimary", Appearance.colors.colOnPrimary) : MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
        z: 1

        implicitHeight: root.showUnreadCount ? Math.max(notificationCounterText.implicitWidth, notificationCounterText.implicitHeight) : 8
        implicitWidth: implicitHeight

        StyledText {
            id: notificationCounterText
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.isMaterial ? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary) : MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
            text: Notifications.unread
        }
    }
}