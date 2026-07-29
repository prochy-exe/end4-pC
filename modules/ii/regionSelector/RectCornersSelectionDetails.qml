import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property real regionX
    required property real regionY
    required property real regionWidth
    required property real regionHeight
    required property real mouseX
    required property real mouseY
    required property color color
    required property color overlayColor
    property bool showAimLines: Config.options.regionSelector.rect.showAimLines

    property bool breathingBorderOnly: false
    readonly property bool hasSelection: root.regionWidth > 0 && root.regionHeight > 0

    // Darken the whole monitor only before a selection exists.
    Rectangle {
        z: 1
        visible: !root.breathingBorderOnly && !root.hasSelection
        anchors.fill: parent
        color: root.overlayColor
    }

    // Carve out the active selection from the overlay using four rectangles.
    Rectangle {
        z: 2
        visible: !root.breathingBorderOnly && root.hasSelection
        x: 0
        y: 0
        width: parent.width
        height: Math.max(0, Math.round(root.regionY))
        color: root.overlayColor
    }
    Rectangle {
        z: 2
        visible: !root.breathingBorderOnly && root.hasSelection
        x: 0
        y: Math.round(root.regionY)
        width: Math.max(0, Math.round(root.regionX))
        height: Math.max(0, Math.round(root.regionHeight))
        color: root.overlayColor
    }
    Rectangle {
        z: 2
        visible: !root.breathingBorderOnly && root.hasSelection
        x: Math.round(root.regionX + root.regionWidth)
        y: Math.round(root.regionY)
        width: Math.max(0, parent.width - x)
        height: Math.max(0, Math.round(root.regionHeight))
        color: root.overlayColor
    }
    Rectangle {
        z: 2
        visible: !root.breathingBorderOnly && root.hasSelection
        x: 0
        y: Math.round(root.regionY + root.regionHeight)
        width: parent.width
        height: Math.max(0, parent.height - y)
        color: root.overlayColor
    }

    DashedBorder {
        id: selectionBorder
        z: 9
        visible: root.hasSelection
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: Math.round(root.regionX) - borderWidth
            topMargin: Math.round(root.regionY) - borderWidth
        }
        width: Math.round(root.regionWidth) + borderWidth * 2
        height: Math.round(root.regionHeight) + borderWidth * 2

        color: root.color
        dashLength: 8
        gapLength: 4
        borderWidth: 1

        // Breathing
        opacity: 0.9
        SequentialAnimation on opacity {
            running: root.breathingBorderOnly
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 0.3; duration: 1200; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.3; to: 0.9; duration: 1200; easing.type: Easing.InOutQuad }
        }
    }

    StyledText {
        z: 2
        visible: !root.breathingBorderOnly && root.hasSelection
        anchors {
            top: selectionBorder.bottom
            right: selectionBorder.right
            margins: 8
        }
        color: root.color
        text: `${Math.round(root.regionWidth)} x ${Math.round(root.regionHeight)}`
    }

    // Coord lines
    Rectangle { // Vertical
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        x: root.mouseX
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: root.color
    }
    Rectangle { // Horizontal
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        y: root.mouseY
        anchors {
            left: parent.left
            right: parent.right
        }
        height: 1
        color: root.color
    }
}
