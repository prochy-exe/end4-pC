pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Shared routing/action logic for the dx5ii-bridge/wamp-bridge audio
 * control widget (modules/ii/audioBridge/), used by both the popup UI and
 * the keyboard-shortcut-facing IPC actions in AudioBridge.qml, so the two
 * can't drift into disagreeing about which device is "active".
 *
 * Routing: the DX5 II's own volume control is the wrong target (or fully
 * inert - see Dx5iiBridge.volumeInert) whenever it's routed out via Line
 * Out (feeding the WiiM as an external amp), so volume actions target the
 * WiiM in that case and the DX5 II otherwise. See AudioBridgeContent.qml's
 * header comment for the full reasoning - this mirrors it exactly.
 */
Singleton {
    id: root

    readonly property bool isLineOutOutput: [2, 5, 6].includes(Dx5iiBridge.outputType)
    readonly property bool routeToWamp: root.isLineOutOutput
    readonly property var activeBridge: root.routeToWamp ? WampBridge : Dx5iiBridge
    readonly property string activeBridgeName: root.routeToWamp ? "WiiM" : "DX5 II"
    readonly property string routeReason: {
        if (!root.routeToWamp) return ""
        if (Dx5iiBridge.volumeInert) return Translation.tr("DX5 II routed via Line Out, in DAC mode")
        return Translation.tr("DX5 II routed via Line Out")
    }

    // Nothing else keeps the bridges' relay connections alive except the
    // popup being open (see Dx5iiBridge/WampBridge.qml's ensureStarted) -
    // these actions are meant to work headlessly from a keyboard shortcut
    // without ever opening it, so they can't assume that already happened.
    // ensureStarted() is a no-op if already connected/connecting, so this
    // is cheap to call unconditionally every time.
    function ensureBridgesStarted() {
        Dx5iiBridge.ensureStarted()
        WampBridge.ensureStarted()
    }

    function volumeStep(deltaPercent) {
        root.ensureBridgesStarted()
        const bridge = root.activeBridge
        if (!bridge.relayConnected) return
        const current = bridge.hasVolume ? bridge.volumePercent : 50
        bridge.setVolumePercent(current + deltaPercent)
    }

    function volumeUp(step) {
        root.volumeStep(step > 0 ? step : 5)
    }

    function volumeDown(step) {
        root.volumeStep(-(step > 0 ? step : 5))
    }

    function toggleMute() {
        root.ensureBridgesStarted()
        root.activeBridge.toggleMute()
    }

    // Cycles the DX5 II's own output routing through whichever outputs are
    // actually enabled on the device (Dx5iiBridge.outputTypeOptions is
    // already filtered to that - see its own comment). Always targets the
    // DX5 II regardless of which device volume actions are currently
    // routed to, same as the popup's output picker.
    function cycleOutput(direction) {
        root.ensureBridgesStarted()
        const options = Dx5iiBridge.outputTypeOptions
        if (!Dx5iiBridge.relayConnected || options.length === 0) return
        const curIdx = options.findIndex(o => o.value === Dx5iiBridge.outputType)
        const nextIdx = ((curIdx < 0 ? 0 : curIdx) + direction + options.length) % options.length
        Dx5iiBridge.setOutputType(options[nextIdx].value)
    }
}
