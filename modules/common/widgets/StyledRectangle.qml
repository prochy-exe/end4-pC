import QtQuick
import qs.modules.common as C
import qs.services

// This is to enable future fancy styles for rectangles. Some ideas:
// - normal rounded rect
// - osk.sh
// - 3d
// i hope i actually get to this and not shrimply forget
// aaaaa i realized for this to work i would have to make this for shapes in general not just rects
Rectangle {
    enum ContentLayer { Background, Pane, Group, Subgroup, Control }
    property var contentLayer: StyledRectangle.ContentLayer.Pane // To appropriately add effects like shadows/3d-ization
    property string monitorName: ""

    color: {
        let role = "surface_container_low"
        if (contentLayer === StyledRectangle.ContentLayer.Background) role = "background"
        else if (contentLayer === StyledRectangle.ContentLayer.Group) role = "surface_container"
        else if (contentLayer === StyledRectangle.ContentLayer.Subgroup) role = "surface_container_high"
        else if (contentLayer === StyledRectangle.ContentLayer.Control) role = "surface_container_highest"
        return MonitorThemes.colorForItem(root, role, C.Appearance.colors.colLayer1)
    }
    Behavior on color { ColorAnimation { duration: C.Appearance.animation.elementMoveFast.duration } }
}
