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
            Quickshell.execDetached(["systemctl", "--user", turnOn ? "start" : "stop", def.serviceName])
            root._setRunning(id, turnOn) // optimistic; corrected by the next poll
            servicePollDelay.restart()
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

    // systemctl can report multiple unit states in one call - poll all
    // "service" mode definitions together rather than one process each.
    function pollServices() {
        if (root.serviceDefinitions.length === 0) return
        if (serviceStatusProc.running) return
        serviceStatusProc.pendingIds = root.serviceDefinitions.map(d => d.id)
        serviceStatusProc.command = ["systemctl", "--user", "is-active", ...root.serviceDefinitions.map(d => d.serviceName)]
        serviceStatusProc.running = true
    }

    Process {
        id: serviceStatusProc
        property list<string> pendingIds: []
        stdout: StdioCollector {
            id: serviceStatusCollector
        }
        onExited: {
            const lines = serviceStatusCollector.text.split("\n")
            for (let i = 0; i < serviceStatusProc.pendingIds.length; i++) {
                root._setRunning(serviceStatusProc.pendingIds[i], (lines[i] ?? "").trim() === "active")
            }
        }
    }

    // Re-poll shortly after a manual toggle so the UI reflects the real
    // outcome (e.g. a service that failed to start) rather than staying on
    // the optimistic guess until the next periodic poll.
    Timer {
        id: servicePollDelay
        interval: 700
        onTriggered: root.pollServices()
    }

    Timer {
        interval: 5000
        running: root.serviceDefinitions.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollServices()
    }
}
