pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

import qs.modules.common

Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/keychron/keychron_ctl.py")
    readonly property int pollInterval: 20000

    property var mouse: ({
        connected: false,
        connection: "",
        battery: null,
        charging: false,
        profile: null
    })
    property var keyboard: ({
        connected: false,
        connection: "",
        battery: null,
        battery_source: null,
        profile: null
    })

    property bool switching: false
    property string lastError: ""

    function refresh() {
        if (statusProc.running)
            return
        statusProc.running = true
    }

    function selectKeyboardProfile(index) {
        if (root.switching)
            return
        root.switching = true
        selectProc.command = ["python3", root.scriptPath, "select-kb-profile", String(index)]
        selectProc.running = true
    }

    function selectMouseProfile(index) {
        if (root.switching)
            return
        root.switching = true
        selectProc.command = ["python3", root.scriptPath, "select-mouse-profile", String(index)]
        selectProc.running = true
    }

    Process {
        id: statusProc
        command: ["python3", root.scriptPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0)
                    return
                try {
                    const parsed = JSON.parse(text)
                    if (parsed.mouse) root.mouse = parsed.mouse
                    if (parsed.keyboard) root.keyboard = parsed.keyboard
                    root.lastError = ""
                } catch (e) {
                    root.lastError = "parse error: " + e.message
                }
            }
        }
    }

    Process {
        id: selectProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.switching = false
                try {
                    const parsed = JSON.parse(text)
                    if (!parsed.ok)
                        root.lastError = parsed.error || "profile switch failed"
                    else
                        root.lastError = ""
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
