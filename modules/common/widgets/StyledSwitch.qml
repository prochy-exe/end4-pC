import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Switch {
    id: root
    property real scale: 0.75
    implicitHeight: 30 * root.scale
    implicitWidth: 52 * root.scale

    property color activeColor: MonitorThemes.colorForItem(root, "primary_container", Appearance?.colors.colPrimaryContainer ?? "#cbc4cb")
    property color inactiveColor: MonitorThemes.colorForItem(root, "surface_bright", Appearance?.m3colors.m3surfaceBright ?? "#3a3939")
    property string monitorName: ""
    readonly property string resolvedMonitorName: {
        if (root.monitorName) return root.monitorName
        let item = root.parent
        while (item) {
            if (item.monitorName) return item.monitorName
            if (item.screen?.name) return item.screen.name
            item = item.parent
        }
        return root.QsWindow?.window?.screen?.name ?? ""
    }

    PointingHandInteraction {}

    background: Rectangle {
        width: parent.width
        height: parent.height
        radius: Appearance?.rounding.full ?? 9999
        color: root.checked ? root.activeColor : root.inactiveColor

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    indicator: Rectangle {
        readonly property real thumbSize: 26 * root.scale
        readonly property real pad: 2 * root.scale
        readonly property real stretchExtra: 4 * root.scale

        width: (root.pressed || root.down)
            ? thumbSize + stretchExtra
            : thumbSize
        height: thumbSize
        radius: Appearance.rounding.full

        color: MonitorThemes.colorForItem(root, "primary", Appearance.colors.colPrimary)

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.55)
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
            shadowBlur: 0.4
        }

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.checked
            ? ((root.pressed || root.down)
                ? parent.width - width - pad - stretchExtra
                : parent.width - width - pad)
            : pad

        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: 320
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.42, 1.5, 0.28, 0.95, 1, 1]
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: 160
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.42, 1.5, 0.28, 0.95, 1, 1]
            }
        }
    }
}
