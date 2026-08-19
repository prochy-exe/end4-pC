pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Lets the shell manage custom Hyprland window rules.
 * Wraps scripts/hyprland/windowrule_manager.py, which (re)writes a clearly
 * marked, auto-generated hl.window_rule() block at the end of
 * custom/rules.lua - the user's own pre-existing content there, and
 * everything in hyprland/*.lua, is never touched.
 */
Singleton {
    id: root
    property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/windowrule_manager.py`)
    property var rules: []
    property var builtinRules: []
    property var matchSchema: []
    property var effectSchema: []
    property var groupOptions: []
    property var monitorNames: []
    readonly property bool loading: proc.running
    property string lastError: ""
    // True while the pick-window subprocess (slurp) is waiting for a click.
    // Settings.qml uses this to stop treating losing focus to slurp's own
    // input-grabbing overlay as "user dismissed the settings window".
    property bool pickingActive: false

    signal windowPicked(string cls, string title, string initialClass, string initialTitle)
    signal pickFailed(string error)

    property var _queue: []

    function refresh() {
        root._enqueue(["list"])
    }

    function refreshSchema() {
        root._enqueue(["schema"])
    }

    function refreshBuiltin() {
        root._enqueue(["list-builtin"])
    }

    function refreshMonitors() {
        root._enqueue(["list-monitors"])
    }

    function addRule(ruleObj) {
        root._enqueue(["add", JSON.stringify(ruleObj)])
    }

    function updateRule(id, ruleObj) {
        root._enqueue(["update", id, JSON.stringify(ruleObj)])
    }

    function setEnabled(id, enabled) {
        root._enqueue(["set-enabled", id, enabled ? "true" : "false"])
    }

    function removeRule(id) {
        root._enqueue(["remove", id])
    }

    function pickWindow() {
        root._enqueue(["pick-window"])
    }

    function _enqueue(cmdArgs) {
        root._queue.push(cmdArgs)
        root._pump()
    }

    function _pump() {
        if (proc.running || root._queue.length === 0) return
        const next = root._queue.shift()
        proc.kind = next[0]
        if (proc.kind === "pick-window") root.pickingActive = true
        proc.command = [root.scriptPath, ...next]
        proc.running = true
    }

    Process {
        id: proc
        property string kind: ""
        stdout: StdioCollector {
            id: collector
        }
        onExited: (exitCode, exitStatus) => {
            if (proc.kind === "pick-window") root.pickingActive = false
            let ok = false
            let result = null
            try {
                result = JSON.parse(collector.text)
                ok = !!result.ok
                if (!ok) {
                    if (proc.kind === "pick-window") root.pickFailed(result.error ?? "Unknown error")
                    else root.lastError = result.error ?? "Unknown error"
                } else {
                    root.lastError = ""
                    if (proc.kind === "list") {
                        root.rules = result.rules ?? []
                    } else if (proc.kind === "list-builtin") {
                        root.builtinRules = result.rules ?? []
                    } else if (proc.kind === "schema") {
                        root.matchSchema = result.match ?? []
                        root.effectSchema = result.effects ?? []
                        root.groupOptions = result.groupOptions ?? []
                    } else if (proc.kind === "list-monitors") {
                        root.monitorNames = result.monitors ?? []
                    } else if (proc.kind === "pick-window") {
                        root.windowPicked(result.class ?? "", result.title ?? "", result.initialClass ?? "", result.initialTitle ?? "")
                    }
                }
            } catch (e) {
                root.lastError = `Failed to parse response: ${e}`
            }
            const mutating = ok && proc.kind !== "list" && proc.kind !== "list-builtin" && proc.kind !== "schema" && proc.kind !== "pick-window" && proc.kind !== "list-monitors"
            if (mutating) {
                Quickshell.execDetached(["hyprctl", "reload"])
                root._enqueue(["list"])
            } else {
                root._pump()
            }
        }
    }

    Component.onCompleted: {
        root.refreshSchema()
        root.refresh()
        root.refreshBuiltin()
        root.refreshMonitors()
    }
}
