pragma ComponentBehavior: Bound
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
    readonly property bool shouldShowAppIcons: Boolean(C.Config.options.bar?.workspaces?.showAppIcons || C.Config.options.bar?.workspaces?.indicatorStyle === "icon")
    property list<var> biggestWindow: shouldShowAppIcons ? occupied.map((_, index) => {
        const number = getWorkspaceIdAt(index)
        return root.biggestWindowForNumber(number)
    }) : []

    function getWorkspaceId(group, index) {
        return group * root.shownCount + index + 1
    }
    function getWorkspaceIdAt(index) {
        return root.getWorkspaceId(root.group, index)
    }

    function _niriRealId(number) {
        const ws = WM.workspaces.find(w => w.output === root.monitorName && w.idx === number)
        return ws?.id ?? null
    }

    function biggestWindowForNumber(number) {
        if (WM.compositor === "hyprland")
            return HyprlandData.biggestWindowForWorkspace(number)

        const realId = root._niriRealId(number)
        if (realId === null) return null
        const winsInWs = WM.windowList.filter(w => w.workspaceId === realId)
        if (winsInWs.length === 0) return null
        const win = winsInWs.find(w => w.focused) ?? winsInWs[0]
        return { class: win.appId, title: win.title, id: win.id }
    }

    function updateWorkspaceOccupied() {
        const count = root.shownCount;
        let newOccupied = new Array(count);

        if (WM.compositor === "hyprland") {
            const occupiedWsIds = new Set();
            const wsVals = Hyprland.workspaces?.values || [];
            for (let i = 0; i < wsVals.length; i++) {
                const ws = wsVals[i];
                if (ws && (ws.windows > 0 || ws.id !== root.activeNumber)) {
                    occupiedWsIds.add(ws.id);
                }
            }
            const winList = HyprlandData.windowList || [];
            for (let i = 0; i < winList.length; i++) {
                const w = winList[i];
                if (w?.workspace?.id !== undefined) {
                    occupiedWsIds.add(w.workspace.id);
                }
            }

            for (let i = 0; i < count; i++) {
                const thisWorkspaceId = getWorkspaceId(root.group, i);
                newOccupied[i] = occupiedWsIds.has(thisWorkspaceId);
            }
        } else {
            const winList = WM.windowList || [];
            for (let i = 0; i < count; i++) {
                const number = getWorkspaceId(root.group, i);
                const realId = root._niriRealId(number);
                newOccupied[i] = (realId !== null) && winList.some(w => w.workspaceId === realId);
            }
        }
        root.occupied = newOccupied;
    }

    Component.onCompleted: updateWorkspaceOccupied()

    // Hyprland
    Connections {
        target: Hyprland.workspaces
        enabled: WM.compositor === "hyprland"
        function onValuesChanged() {
            root.updateWorkspaceOccupied()
        }
    }
    Connections {
        target: Hyprland
        enabled: WM.compositor === "hyprland"
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied()
        }
    }
    Connections {
        target: HyprlandData
        enabled: WM.compositor === "hyprland"
        function onWindowListChanged() {
            root.updateWorkspaceOccupied()
        }
    }

    // Niri
    Connections {
        target: WM
        enabled: WM.compositor !== "hyprland"
        function onWorkspacesChanged() {
            root.updateWorkspaceOccupied()
        }
        function onWindowListChanged() {
            root.updateWorkspaceOccupied()
        }
    }

    onGroupChanged: {
        updateWorkspaceOccupied()
    }
}