pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property bool inhibit: false
    property bool changedBeforePersistenceReady: false

    function restoreInhibit() {
        if (!Persistent.ready) return;
        if (!Persistent.isNewHyprlandInstance && !root.changedBeforePersistenceReady)
            root.inhibit = Persistent.states.idle.inhibit;
        else
            Persistent.states.idle.inhibit = root.inhibit;
    }

    Component.onCompleted: root.restoreInhibit()
    Connections {
        target: Persistent
        function onReadyChanged() { root.restoreInhibit(); }
    }

    function toggleInhibit(active = null) {
        if (!Persistent.ready)
            root.changedBeforePersistenceReady = true;
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    function resyncInhibitor() {
        if (root.inhibit && !inhibitorProcess.running)
            inhibitorProcess.running = true;
    }

    GlobalShortcut {
        name: "idleInhibitorResync"
        description: "Re-applies the idle inhibitor after waking from sleep"
        onPressed: root.resyncInhibitor()
    }

    Process {
        command: ["/usr/bin/python3", `${Directories.scriptPath}/hypridle/power_inhibit.py`]
        running: true
        stdinEnabled: true
    }

    Process {
        id: inhibitorProcess
        running: root.inhibit
        command: ["systemd-inhibit", "--what=idle", "--mode=block",
            "--who=Quickshell caffeine", "--why=Keep awake is enabled", "cat"]
        // Closing the pipe also releases the inhibitor when the shell exits.
        stdinEnabled: true
        onExited: (exitCode, exitStatus) => {
            if (root.inhibit) {
                console.warn("[Idle] Idle inhibitor exited:", exitCode);
                root.toggleInhibit(false);
            }
        }
    }
}
