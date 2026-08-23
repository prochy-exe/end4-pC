pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/tailscale/tailscale_ctl.py")
    readonly property int pollInterval: 10000

    property var status: ({
        installed: true,
        connected: false,
        backend_state: "Unknown",
        needs_login: false,
        auth_url: null,
        self: ({ hostname: "", dns_name: "", ips: [] }),
        tailnet: "",
        exit_node: null,
        peers: ({ online: 0, total: 0 }),
        prefs: ({
            accept_routes: false, accept_dns: true, shields_up: false,
            ssh: false, exit_node_allow_lan_access: false, advertise_exit_node: false
        }),
        error: null
    })

    property var exitNodes: []
    property var recommendedNodes: []
    property bool exitNodesLoading: false
    property bool busy: false
    property string lastError: ""

    // The full exit-node scan (status --json over 550+ peers, plus a
    // netcheck and an exit-node suggest) is the slow call here - caching it
    // means opening the picker repeatedly (e.g. re-hovering the bar icon)
    // doesn't re-run all of that every time, only after it's gone stale or
    // you've actually changed the exit node.
    readonly property int exitNodesCacheMs: 60000
    property double exitNodesFetchedAt: 0

    function refresh() {
        if (statusProc.running)
            return
        statusProc.running = true
    }

    function refreshExitNodes(force) {
        if (exitNodesProc.running)
            return
        if (!force && root.exitNodes.length > 0
                && (Date.now() - root.exitNodesFetchedAt) < root.exitNodesCacheMs)
            return
        root.exitNodesLoading = true
        exitNodesProc.running = true
    }

    function setEnabled(enabled) {
        if (root.busy)
            return
        root.busy = true
        actionProc.command = ["python3", root.scriptPath, enabled ? "up" : "down"]
        actionProc.running = true
    }

    function setPref(flag, value) {
        if (root.busy)
            return
        root.busy = true
        actionProc.command = ["python3", root.scriptPath, "set-pref", flag, value ? "true" : "false"]
        actionProc.running = true
    }

    function setExitNode(value) {
        if (root.busy)
            return
        root.busy = true
        actionProc.command = ["python3", root.scriptPath, "set-exit-node", value]
        actionProc.running = true
    }

    Process {
        id: statusProc
        command: ["python3", root.scriptPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0)
                    return
                try {
                    root.status = JSON.parse(text)
                } catch (e) {
                    root.lastError = "parse error: " + e.message
                }
            }
        }
    }

    Process {
        id: exitNodesProc
        command: ["python3", root.scriptPath, "exit-nodes"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.exitNodesLoading = false
                if (text.length === 0)
                    return
                try {
                    const parsed = JSON.parse(text)
                    root.exitNodes = parsed.nodes ?? []
                    root.recommendedNodes = parsed.recommended ?? []
                    root.exitNodesFetchedAt = Date.now()
                } catch (e) {
                    root.lastError = "parse error: " + e.message
                }
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                try {
                    const parsed = JSON.parse(text)
                    root.lastError = parsed.ok === false ? (parsed.error || "action failed") : ""
                } catch (e) {
                    root.lastError = "parse error: " + e.message
                }
                root.refresh()
            }
        }
    }

    Timer {
        running: true
        repeat: true
        interval: root.pollInterval
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
