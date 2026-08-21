import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

RippleButton {
    id: root
    property string query

    implicitHeight: 30
    leftPadding: 6
    rightPadding: 10
    buttonRadius: Appearance.rounding.verysmall
    colBackground: MonitorThemes.shellColorForItem(root, "colSurfaceContainerHighest", Appearance.colors.colSurfaceContainerHighest)
    colBackgroundHover: MonitorThemes.shellColorForItem(root, "colSurfaceContainerHighestHover", Appearance.colors.colSurfaceContainerHighestHover)
    colRipple: MonitorThemes.shellColorForItem(root, "colSurfaceContainerHighestActive", Appearance.colors.colSurfaceContainerHighestActive)

    PointingHandInteraction {}
    onClicked: {
        let url = Config.options.search.engineBaseUrl + root.query;
        for (let site of (Config?.options?.search.excludedSites ?? [])) {
            url += ` -site:${site}`;
        }
        Qt.openUrlExternally(url);
        GlobalStates.sidebarLeftOpen = false;
    }

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: rowLayout.implicitWidth
        implicitHeight: rowLayout.implicitHeight
        RowLayout {
            id: rowLayout
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                text: "search"
                iconSize: 20
                color: MonitorThemes.colorForItem(root, "on_surface", Appearance.m3colors.m3onSurface)
            }
            StyledText {
                id: text
                horizontalAlignment: Text.AlignHCenter
                text: root.query
                color: MonitorThemes.colorForItem(root, "on_surface", Appearance.m3colors.m3onSurface)
            }
        }
    }
}
