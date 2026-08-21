import qs.services
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// A small read-only marker on MonitorPreviewCanvas showing where an item
// (ticker/notifications/OSD) currently sits - purely visual, no dragging.
// Actual repositioning happens in the live on-screen editor (popupEditor/)
// on the real screen; this canvas is just a preview of the result.
Item {
    id: root
    required property string label
    required property string iconName
    required property color accentColor
    // The point this marker centers itself on, in the parent's coordinate
    // space - a plain "x"/"y" property set at instantiation would silently
    // override this component's own internal positioning binding rather
    // than combine with it (whichever is set last at the call site wins,
    // per normal QML property semantics), so centering has to go through
    // dedicated properties instead of x/y directly.
    required property real centerX
    required property real centerY
    // Horizontal offset applied when 2+ items land at/near the same spot,
    // so they line up in a row instead of fully overlapping. 0 for a lone
    // item.
    property real rowOffsetX: 0

    implicitWidth: 20
    implicitHeight: 20
    x: root.centerX - width / 2 + root.rowOffsetX
    y: root.centerY - height / 2

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.accentColor
        border.width: 1.5
        border.color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.iconName
        iconSize: Appearance.font.pixelSize.small
        color: "white"
        fill: 1
    }

    StyledToolTip {
        extraVisibleCondition: false
        alternativeVisibleCondition: hoverArea.containsMouse
        text: root.label
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
    }
}
