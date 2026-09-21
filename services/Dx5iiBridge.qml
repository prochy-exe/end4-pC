pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Control-plane client for dx5ii-bridge (/mnt/github/dx5ii-bridge), the
 * external C daemon that talks to a Topping DX5 II DAC/amp over BLE and
 * exposes it over a local WebSocket JSON API. This is purely a thin wrapper
 * around that already-existing API (see the project's docs/superpowers
 * specs for the wire protocol) - it doesn't reimplement any device logic.
 *
 * Quickshell's Process type can't speak WebSocket directly, so a small
 * stdlib-only Python relay (scripts/audio/ws_bridge_client.py) sits in
 * between: one JSON line in on its stdin becomes one WS text frame out,
 * and each WS text frame it receives becomes one JSON line on its stdout.
 */
Singleton {
    id: root

    readonly property string binaryPath: Config.options.audioBridges.dx5ii.binaryPath
    readonly property string wsBind: Config.options.audioBridges.dx5ii.wsBind
    readonly property int wsPort: Config.options.audioBridges.dx5ii.wsPort

    // Relay process reached the daemon's WebSocket port at all.
    property bool relayConnected: false
    // The daemon itself reports its BLE link to the DX5 II as connected
    // (relayConnected can be true - talking to the daemon - while this is
    // false, e.g. daemon up but device out of range/off).
    property bool deviceConnected: false
    property bool launchAttempted: false

    // From the daemon's "connection" event - the BLE address of the DX5 II
    // it's actually talking to.
    property string bleAddress: ""
    // From the "device_name" setting (part of the regular settings snapshot).
    property string deviceName: ""

    property int volumePercent: 0
    property bool hasVolume: false
    property bool isMuted: false
    // dx5ii-bridge push events can be partial (only the fields that actually
    // changed), so "step" won't be present in most volume-only pushes. This
    // remembers the last-known value across updates rather than re-guessing
    // a default every time a "step"-less push arrives - guessing wrong here
    // (e.g. assuming 1.0dB/unit while the device is actually in 0.5dB/unit)
    // silently doubles the effective max_raw mismatch and produces garbage
    // percentages, including negative ones.
    property int stepMode: 1
    // 0: Preamp (volume works normally), 1: DAC (device forces volume to 0
    // and ignores volume-set commands entirely - see dx5ii-bridge's own
    // device/commands.c k_setting_warnings "mode" entry). -1: not yet known.
    property int mode: -1
    readonly property bool volumeInert: root.mode === 1
    // Tracks the previous mode value so onModeChanged (which only sees the
    // new value) can tell "just left DAC mode" apart from any other
    // transition. -1 (never set) deliberately never counts as "was DAC", so
    // this doesn't fire spuriously off the very first status snapshot.
    property int previousMode: -1
    onModeChanged: {
        if (root.previousMode === 1 && root.mode !== 1 && root.hasVolume) {
            // The device appears to reset its own volume register to
            // maximum on leaving DAC mode (not just a stale reading -
            // skipping untrustworthy readings while inert, further down,
            // wasn't enough on its own to stop the 100% flash). Re-command
            // whatever was last known as the real level shortly after,
            // rather than trusting whatever the device settles on by
            // itself. Delayed slightly so this lands after that reset
            // rather than racing it.
            restoreVolumeTimer.targetPercent = root.volumePercent
            restoreVolumeTimer.restart()
        }
        root.previousMode = root.mode
    }
    // 0: All, 1: HPA ALL, 2: LO ALL, 3: HPA SE, 4: HPA BAL, 5: LO SE, 6: LO BAL
    property int outputType: -1
    // Bitmask of which outputs are actually enabled on the device (bit =
    // 1 << value, e.g. HPA SE = 1<<3 = 8) - dx5ii-bridge's own
    // device/commands.c k_bitmask_labels_output_options table. Not every
    // device has every output enabled, so the picker must be filtered to
    // this rather than always listing all 7.
    property int outputOptionsMask: -1 // -1: not yet known (nothing loaded)

    readonly property var allOutputTypes: [
        { value: 0, name: "All" },
        { value: 1, name: "HPA ALL" },
        { value: 2, name: "LO ALL" },
        { value: 3, name: "HPA SE" },
        { value: 4, name: "HPA BAL" },
        { value: 5, name: "LO SE" },
        { value: 6, name: "LO BAL" },
    ]
    // Only the outputs actually enabled on this device. Falls back to the
    // full list before the first status snapshot arrives (mask still -1)
    // rather than showing an empty picker, and always keeps the currently
    // active output listed even if the mask were ever inconsistent with it
    // (e.g. mid-change), so the picker never ends up unable to show what's
    // actually selected.
    readonly property var outputTypeOptions: root.allOutputTypes.filter(o =>
        root.outputOptionsMask === -1
        || (root.outputOptionsMask & (1 << o.value)) !== 0
        || o.value === root.outputType
    )
    readonly property string outputTypeName: {
        const opt = root.allOutputTypes.find(o => o.value === root.outputType)
        return opt ? opt.name : ""
    }

    // Raw volume is inverted (0 = loudest) and its range depends on step
    // mode: 1.0dB/unit (max 99) or 0.5dB/unit (max 198) - matches
    // dx5ii-bridge's own actions.c compute_new_volume/target_percent math
    // exactly, so the slider lines up with what a volume_step target_percent
    // request will actually produce.
    function rawToPercent(raw, step) {
        const maxRaw = step === 1 ? 99 : 198
        return Math.round(100 - (raw * 100 / maxRaw))
    }

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

    function setVolumePercent(percent) {
        const clamped = Math.max(0, Math.min(100, Math.round(percent)))
        root.sendAction({ action: "volume_step", target_percent: clamped })
        // Optimistic local update so the slider doesn't visually snap back
        // while waiting for the device's own confirmation to arrive.
        root.volumePercent = clamped
        root.hasVolume = true
    }

    function setMute(state) {
        root.sendAction({ action: "mute", state: state })
    }

    function toggleMute() {
        root.setMute("toggle")
    }

    function setOutputType(value) {
        root.sendAction({ action: "set", setting: "output_type", value: value })
        // Optimistic local update, same reasoning as setVolumePercent: don't
        // wait on the round trip to reflect the change the user just made.
        root.outputType = value
    }

    function sendAction(obj) {
        if (!root.relayConnected) {
            console.warn("[Dx5iiBridge] Dropping action, relay not connected:", JSON.stringify(obj))
            return
        }
        wsClientProc.write(JSON.stringify(obj) + "\n")
    }

    function applySettingsData(data) {
        if (!data) return
        // Both must happen before the volume check below, in case this same
        // update carries all three (a full status snapshot does).
        if (typeof data.step === "number") root.stepMode = data.step
        if (typeof data.mode === "number") root.mode = data.mode

        if (typeof data.volume === "number") {
            // DAC mode (mode === 1) forces the device's raw volume register
            // to 0 (loudest on the inverted scale = 100%) and keeps
            // reporting that forced value the whole time it's inert - not a
            // real level, so applying it would show a meaningless 100%
            // right as output routing switches back to the DX5 II (which
            // happens as soon as outputType leaves Line Out, possibly
            // before the device has reported mode returning to Preamp).
            //
            // Only skip it once there's already a real reading to protect,
            // though - if this is the very first reading we've ever seen
            // (e.g. connecting fresh while already in DAC mode), there's no
            // "last known good" to fall back on, and skipping unconditionally
            // left hasVolume stuck false forever, showing "--" instead of a
            // wrong-but-present value.
            if (root.mode !== 1 || !root.hasVolume) {
                const percent = root.rawToPercent(data.volume, root.stepMode)
                root.volumePercent = Math.max(0, Math.min(100, percent))
                root.hasVolume = true
            }
        }
        if (typeof data.is_mute === "boolean") root.isMuted = data.is_mute
        if (typeof data.output_type === "number") {
            const outputChanged = root.outputType !== data.output_type
            root.outputType = data.output_type
            // Ask for a fresh reading right away instead of waiting for the
            // next passive push, so the corrected volume (if this output
            // change also means DAC mode is no longer inert) arrives as
            // fast as this link allows rather than however long until the
            // device's own next unsolicited update.
            if (outputChanged) root.requestStatus()
        }
        if (typeof data.output_options === "number") root.outputOptionsMask = data.output_options
        if (typeof data.device_name === "string" && data.device_name.length > 0) root.deviceName = data.device_name
    }

    function handleLine(line) {
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            console.warn("[Dx5iiBridge] Malformed line from relay:", line)
            return
        }

        if (msg.type === "bridge_connected") {
            root.relayConnected = true
            root.launchAttempted = false
            reconnectTimer.stop()
            reconnectTimer.backoffMs = 1000
            root.requestStatus()
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
            if (typeof msg.address === "string" && msg.address.length > 0) root.bleAddress = msg.address
            // The daemon's own WebSocket (bridge_connected, above) often
            // comes up before its BLE link to the DX5 II does - the status
            // request that fires immediately on bridge_connected can race
            // ahead of that and come back as a device_error ("command timed
            // out or the device is not connected"), and nothing was ever
            // asking again afterward. That left every field (mode,
            // outputType, volumePercent, ...) stuck at its unset default
            // until the device happened to push an update on its own (e.g.
            // its own physical remote/knob). Re-requesting on the transition
            // into "connected" catches the device actually becoming
            // reachable, however late that happens relative to the relay.
            if (root.deviceConnected && !wasConnected) root.requestStatus()
            return
        }
        if (msg.event === "push") {
            root.applySettingsData(msg.message?.data)
            return
        }
        if (msg.ok === true && msg.response?.data) {
            // "status"/"get" replies wrap the device envelope wholesale.
            root.applySettingsData(msg.response.data)
            return
        }
        if (msg.ok === true && typeof msg.response?.setting === "string") {
            // "set" replies are shaped differently ({setting, value}, not
            // {data: {...}}) - this is the device's own confirmation of
            // what was actually applied, so it can correct the optimistic
            // update above if the device did something else (e.g. rejected
            // the value).
            const partial = {}
            partial[msg.response.setting] = msg.response.value
            root.applySettingsData(partial)
            return
        }
        if (msg.ok === false) {
            console.warn("[Dx5iiBridge] Action failed:", JSON.stringify(msg.error))
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

    // See onModeChanged above - re-asserts the last known real volume a
    // moment after leaving DAC mode, rather than trusting whatever the
    // device reports right at the transition.
    Timer {
        id: restoreVolumeTimer
        interval: 400
        repeat: false
        property int targetPercent: -1
        onTriggered: {
            if (targetPercent >= 0) root.setVolumePercent(targetPercent)
        }
    }

    // Backs off up to 10s between reconnect attempts; the first attempt
    // after a fresh failure fires quickly since the daemon is often just
    // mid-restart. Also responsible for launching the daemon itself the
    // first time nothing answers on its port at all - and every few
    // attempts thereafter (see attemptsSinceLaunch below), since the daemon
    // can die outright (e.g. killed by system suspend) without this ever
    // finding out otherwise: launchAttempted only clears on a real
    // bridge_connected, so without a retry-count fallback here, one launch
    // that dies leaves this polling a dead port forever.
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
                Quickshell.execDetached([root.binaryPath, "-ws-bind", root.wsBind, "-ws-port", String(root.wsPort), "-no-tray"])
                backoffMs = 1500
            } else {
                attemptsSinceLaunch += 1
                backoffMs = Math.min(backoffMs * 2, 10000)
            }
            wsClientProc.running = true
        }
    }
}
