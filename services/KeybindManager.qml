pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Lets the shell rebind any named top-level Hyprland keybind.
 * Wraps scripts/hyprland/keybind_manager.py, which parses the pristine
 * hyprland/keybinds.lua and (re)writes a clearly-marked, auto-generated
 * hl.unbind()/hl.bind() block at the end of custom/keybinds.lua - nothing
 * else in either file is ever touched.
 */
Singleton {
    id: root
    property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/keybind_manager.py`)
    property var keybinds: []
    property var customKeybinds: []
    readonly property bool loading: proc.running
    property string lastError: ""

    property var _queue: []

    function refresh() {
        root._enqueue(["list"])
    }

    function setBind(description: string, newKey: string) {
        root._enqueue(["set", description, newKey])
    }

    function disableBind(description: string) {
        root._enqueue(["disable", description])
    }

    function resetBind(description: string) {
        root._enqueue(["reset", description])
    }

    function resetAll() {
        root._enqueue(["reset-all"])
    }

    function addCustomBind(description: string, key: string, command: string, kind = "shell") {
        root._enqueue(["add-custom", description, key, command, "--kind", kind])
    }

    function updateCustomBind(id: string, description: string, key: string, command: string, kind = "") {
        const args = ["update-custom", id, description, key, command]
        if (kind) args.push("--kind", kind)
        root._enqueue(args)
    }

    function removeCustomBind(id: string) {
        root._enqueue(["remove-custom", id])
    }

    function _enqueue(cmdArgs) {
        root._queue.push(cmdArgs)
        root._pump()
    }

    function _pump() {
        if (proc.running || root._queue.length === 0) return
        const next = root._queue.shift()
        proc.isList = next[0] === "list"
        proc.command = [root.scriptPath, ...next]
        proc.running = true
    }

    Process {
        id: proc
        property bool isList: false
        stdout: StdioCollector {
            id: collector
        }
        onExited: (exitCode, exitStatus) => {
            let ok = false
            try {
                const result = JSON.parse(collector.text)
                ok = !!result.ok
                if (!ok) {
                    root.lastError = result.error ?? "Unknown error"
                } else {
                    root.lastError = ""
                    if (proc.isList) {
                        root.keybinds = result.keybinds ?? []
                        root.customKeybinds = result.custom ?? []
                    }
                }
            } catch (e) {
                root.lastError = `Failed to parse response: ${e}`
            }
            if (!proc.isList && ok) {
                Quickshell.execDetached(["hyprctl", "reload"])
                root._enqueue(["list"])
            } else {
                root._pump()
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name == "configreloaded") root.refresh()
        }
    }

    Component.onCompleted: root.refresh()
}
