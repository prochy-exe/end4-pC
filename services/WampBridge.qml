pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Control-plane client for wamp-bridge (/mnt/github/wamp-bridge), the
 * external C daemon that talks to a WiiM/LinkPlay amp over its local HTTP
 * API and exposes it over a local WebSocket JSON API. Purely a thin wrapper
 * around that already-existing API (see the project's own README for the
 * wire protocol) - no device logic is reimplemented here.
 *
 * Same relay approach as Dx5iiBridge.qml: Quickshell's Process can't speak
 * WebSocket, so scripts/audio/ws_bridge_client.py turns "one JSON line on
 * stdin" into a real WS text frame, and each received WS text frame into
 * one JSON line on stdout.
 */
Singleton {
    id: root

    readonly property string binaryPath: Config.options.audioBridges.wamp.binaryPath
    readonly property string wsBind: Config.options.audioBridges.wamp.wsBind
    readonly property int wsPort: Config.options.audioBridges.wamp.wsPort

    property bool relayConnected: false
    // wamp-bridge's own connection to the WiiM device (relayConnected can be
    // true - talking to the daemon - while this is false, e.g. daemon up
    // but the amp is powered off/unreachable on the LAN).
    property bool deviceConnected: false
    property bool launchAttempted: false

    property int volumePercent: 0
    property bool hasVolume: false
    property bool isMuted: false

    // From the "device_info" action (device/player.c's fetch_device_info).
    property string deviceName: ""
    property string mac: ""
    property string ssid: ""
    property string firmware: ""
    // The actual resolved connection target (e.g. "https://192.168.1.50"),
    // whether that came from -host, wamp-bridge's own on-disk cache, or
    // SSDP discovery - added to fetch_device_info specifically so this
    // widget has something to show, since nothing else in the WS API
    // exposes it.
    property string host: ""

    function ensureStarted() {
        if (root.relayConnected) return
        if (!wsClientProc.running) {
            reconnectTimer.stop()
            wsClientProc.running = true
        }
    }

    function requestStatus() {
        root.sendAction({ action: "status" })
    }

    function requestDeviceInfo() {
        root.sendAction({ action: "device_info" })
    }

    function setVolumePercent(percent) {
        const clamped = Math.max(0, Math.min(100, Math.round(percent)))
        root.sendAction({ action: "set_volume", value: clamped })
        root.volumePercent = clamped
        root.hasVolume = true
    }

    function setMute(state) {
        root.sendAction({ action: "mute", state: state })
    }

    function toggleMute() {
        root.setMute("toggle")
    }

    function sendAction(obj) {
        if (!root.relayConnected) {
            console.warn("[WampBridge] Dropping action, relay not connected:", JSON.stringify(obj))
            return
        }
        wsClientProc.write(JSON.stringify(obj) + "\n")
    }

    function applyStatusData(data) {
        if (!data) return
        if (typeof data.volume === "number") {
            root.volumePercent = Math.max(0, Math.min(100, Math.round(data.volume)))
            root.hasVolume = true
        }
        if (typeof data.muted === "boolean") root.isMuted = data.muted
        // These only ever arrive via a "device_info" reply, but applying
        // them here (rather than a separate function) means it doesn't
        // matter that "status" and "device_info" share the same generic
        // {ok, response} reply shape with nothing tagging which action
        // produced it - whichever fields are actually present get applied.
        if (typeof data.device_name === "string" && data.device_name.length > 0) root.deviceName = data.device_name
        if (typeof data.mac === "string" && data.mac.length > 0) root.mac = data.mac
        if (typeof data.ssid === "string" && data.ssid.length > 0) root.ssid = data.ssid
        if (typeof data.firmware === "string" && data.firmware.length > 0) root.firmware = data.firmware
        if (typeof data.host === "string" && data.host.length > 0) root.host = data.host
    }

    function handleLine(line) {
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            console.warn("[WampBridge] Malformed line from relay:", line)
            return
        }

        if (msg.type === "bridge_connected") {
            root.relayConnected = true
            root.launchAttempted = false
            reconnectTimer.stop()
            reconnectTimer.backoffMs = 1000
            root.requestStatus()
            root.requestDeviceInfo()
            deviceInfoRetryTimer.restart()
            return
        }
        if (msg.type === "bridge_disconnected") {
            root.relayConnected = false
            root.deviceConnected = false
            reconnectTimer.restart()
            return
        }

        if (msg.event === "connection") {
            const wasConnected = root.deviceConnected
            root.deviceConnected = msg.state === "connected"
            // "device_info" is request/response only - wamp-bridge never
            // pushes it unsolicited the way it does "status", so the one
            // request fired on relay-connect can easily race the device
            // actually becoming reachable (still off/waking up/DHCP not
            // settled yet) and get a device_error with no automatic retry.
            // Re-ask every time the device (re)connects instead.
            if (root.deviceConnected && !wasConnected) root.requestDeviceInfo()
            return
        }
        if (msg.event === "status") {
            root.applyStatusData(msg.data)
            return
        }
        if (msg.ok === true && msg.response) {
            root.applyStatusData(msg.response)
            return
        }
        if (msg.ok === false) {
            console.warn("[WampBridge] Action failed:", JSON.stringify(msg.error))
        }
    }

    // Covers the case where the device was already connected at the moment
    // the relay connected - the "connection: connected" retry above only
    // fires on a fresh transition, which never happens if it was connected
    // the whole time. One retry a few seconds later is enough: if it still
    // fails, the device genuinely isn't reachable yet.
    Timer {
        id: deviceInfoRetryTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.host === "" && root.relayConnected) root.requestDeviceInfo()
        }
    }

    Process {
        id: wsClientProc
        command: [
            "python3",
            Quickshell.shellPath("scripts/audio/ws_bridge_client.py"),
            root.wsBind,
            String(root.wsPort),
            "/ws",
        ]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        onExited: {
            root.relayConnected = false
            root.deviceConnected = false
            reconnectTimer.restart()
        }
    }

    // See Dx5iiBridge.qml's reconnectTimer comment: attemptsSinceLaunch
    // caps how long this polls a dead port before trying to launch the
    // daemon again, since launchAttempted only clears on a real
    // bridge_connected and the daemon can die outright (e.g. system
    // suspend) without that ever happening.
    Timer {
        id: reconnectTimer
        property int backoffMs: 1000
        property int attemptsSinceLaunch: 0
        interval: backoffMs
        repeat: false
        onTriggered: {
            if (!root.launchAttempted || attemptsSinceLaunch >= 5) {
                root.launchAttempted = true
                attemptsSinceLaunch = 0
                Quickshell.execDetached([root.binaryPath, "-ws-addr", root.wsBind, "-ws-port", String(root.wsPort), "-no-tray"])
                backoffMs = 1500
            } else {
                attemptsSinceLaunch += 1
                backoffMs = Math.min(backoffMs * 2, 10000)
            }
            wsClientProc.running = true
        }
    }
}
