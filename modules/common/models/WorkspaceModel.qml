import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common as C

NestableObject {
    id: root

    required property HyprlandMonitor monitor
    readonly property string monitorName: monitor?.name ?? ""
    readonly property var liveMonitorData: HyprlandData.monitors.find(m => m.id === monitor?.id)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    // Hyprland can (rarely, e.g. a monitor reconnecting after DPMS wake with
    // no bound workspace) hand back a garbage id near INT32_MAX for a
    // monitor's active workspace. That id feeds group/getWorkspaceId's
    // arithmetic below, which would otherwise render as a wall of huge
    // overlapping numbers - clamp it back to a sane fallback instead.
    readonly property int rawActiveWorkspace: monitor?.activeWorkspace?.id ?? 1
    readonly property int activeWorkspace: (rawActiveWorkspace > 0 && rawActiveWorkspace < 100000) ? rawActiveWorkspace : 1
    readonly property bool currentWorkspaceNotFake: activeWindow?.activated ?? false // Active empty workspace = fake. At least, that's how I like to call it.
    readonly property int fakeWorkspace: currentWorkspaceNotFake ? -9999 : activeWorkspace
    readonly property int shownCount: C.Config.getBarSetting(root.monitorName, ["workspaces", "shown"], C.Config.options.bar.workspaces.shown)
    readonly property int group: Math.floor((activeWorkspace - 1) / shownCount)
    readonly property var specialWorkspace: liveMonitorData?.specialWorkspace
    readonly property string specialWorkspaceName: specialWorkspace?.name.replace("special:", "") ?? "special"
    readonly property bool specialWorkspaceActive: specialWorkspaceName !== ""

    property list<bool> occupied: []
    property list<var> biggestWindow: occupied.map((_, index) => {
        const wsId = getWorkspaceIdAt(index);
        var biggestWindow = HyprlandData.biggestWindowForWorkspace(wsId);
        return biggestWindow;
    })

    function getWorkspaceId(group, index) {
        return group * root.shownCount + index + 1;
    }
    function getWorkspaceIdAt(index) {
        return root.getWorkspaceId(root.group, index);
    }

    // Function to update workspaceOccupied
    function updateWorkspaceOccupied() {
        root.occupied = Array.from({
            length: root.shownCount
        }, (_, i) => {
            const thisWorkspaceId = getWorkspaceId(root.group, i);
            return Hyprland.workspaces.values.some(ws => ws.id === thisWorkspaceId);
        });
    }

    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    onGroupChanged: {
        updateWorkspaceOccupied();
    }
}