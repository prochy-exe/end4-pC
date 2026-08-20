pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQml.Models
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * User-defined toggle buttons shown in the bar's resources area, alongside
 * CPU/RAM/etc. Each definition (Config.options.bar.customResources) is
 * either:
 *   - "command": a shell command kept running as a child process while "on".
 *     Toggling off terminates it. State doesn't survive a shell restart.
 *   - "service": a systemd --user unit, started/stopped via systemctl.
 *     State is polled from systemd itself, so it's correct regardless of
 *     what started/stopped it and survives shell restarts.
 */
Singleton {
    id: root

    readonly property list<var> definitions: Config.options.bar.customResources ?? []
    readonly property list<var> commandDefinitions: root.definitions.filter(d => d.mode === "command")
    readonly property list<var> serviceDefinitions: root.definitions.filter(d => d.mode === "service" && (d.serviceName ?? "").length > 0)

    // id -> bool. Source of truth the bar UI reads from for both modes.
    property var runningStates: ({})

    function isRunning(id) {
        return root.runningStates[id] ?? false
    }

    function _setRunning(id, value) {
        if (root.runningStates[id] === value) return
        const next = Object.assign({}, root.runningStates)
        next[id] = value
        root.runningStates = next
    }

    function findDefinition(id) {
        return root.definitions.find(d => d.id === id) ?? null
    }

    function toggle(id) {
        const def = root.findDefinition(id)
        if (!def) return
        if (def.mode === "service") {
            if (!def.serviceName) return
            const turnOn = !root.isRunning(id)
            const scopeArgs = (def.serviceScope ?? "user") === "user" ? ["--user"] : []
            Quickshell.execDetached(["systemctl", ...scopeArgs, turnOn ? "start" : "stop", def.serviceName])
            root._setRunning(id, turnOn) // optimistic; corrected by the next poll
        } else {
            root._setRunning(id, !root.isRunning(id))
        }
    }

    // One live process per "command" mode definition; its own `running`
    // property both drives and reflects that process's lifecycle.
    Instantiator {
        model: root.commandDefinitions
        delegate: Process {
            id: commandProc
            required property var modelData
            command: ["bash", "-c", modelData.command ?? ""]
            running: root.isRunning(modelData.id)
            onRunningChanged: root._setRunning(modelData.id, running)
            onExited: {
                // The command may have exited on its own (crashed, or was a
                // one-shot); reflect that back as "off" instead of leaving the
                // toggle stuck showing "on".
                if (root.isRunning(modelData.id)) root._setRunning(modelData.id, false)
            }
        }
    }

    Instantiator {
        model: root.serviceDefinitions
        delegate: QtObject {
            id: servicePoller
            required property var modelData

            // Process is not a visual Item and has no default child property,
            // so keep its polling timer as a sibling QObject instead of nesting
            // it inside the process declaration.
            property Process serviceProc: Process {
                command: ["systemctl", ...((servicePoller.modelData.serviceScope ?? "user") === "user" ? ["--user"] : []), "is-active", servicePoller.modelData.serviceName]
                stdout: StdioCollector { id: serviceOutput }
                Component.onCompleted: running = true
                onExited: root._setRunning(servicePoller.modelData.id, serviceOutput.text.trim() === "active")
            }
            property Timer servicePollTimer: Timer {
                interval: 5000
                repeat: true
                running: true
                triggeredOnStart: true
                onTriggered: if (!servicePoller.serviceProc.running) servicePoller.serviceProc.running = true
            }
        }
    }

}
