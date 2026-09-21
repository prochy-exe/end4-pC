pragma ComponentBehavior: Bound
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Shared by AudioBridgeContent.qml's popup and AudioBridgeOsd.qml's OSD -
// a volume slider bound to one of the audio bridges (dx5ii/wamp), with two
// behaviors neither plain ConfigSlider usage nor a naive bridge.setVolumePercent()
// call gets right on its own:
//
// - Dragging fires onValueChanged on every pixel of mouse movement - sent
//   unthrottled, that's tens of overlapping volume_step requests per
//   second. dx5ii-bridge computes each one as a delta from its OWN cached
//   last-known volume (see Dx5iiBridge.qml's rawToPercent comment); over a
//   slow BLE link, that cache falls behind the flood of in-flight
//   requests, so a fast drag visibly jumps backward as stale-baseline
//   deltas land out of order. Sending at a capped rate instead keeps the
//   slider itself perfectly smooth - it's driven by the widget's own
//   value, not a round trip - while keeping the actual command rate
//   something a BLE-connected device can keep up with.
// - A device confirmation landing mid-drag would otherwise snap the
//   slider to whatever it reports - which, on the DX5 II, can legitimately
//   differ by a step from what's being dragged to (its raw volume is
//   quantized to 99/198 discrete steps, so a requested percent doesn't
//   always round-trip back to the exact same percent). Pushes are ignored
//   while actively dragging; the slider catches up once released.
ConfigSlider {
    id: root
    required property var bridge

    showLabel: false
    from: 0
    to: 100
    enabled: bridge.relayConnected
    usePercentTooltip: true

    // Emitted on any real user-driven change (not a programmatic resync) -
    // callers that auto-hide on a timeout should reset it from this.
    signal userInteracted()

    property bool suppressCommand: false
    property int pendingPercent: -1
    property bool throttleActive: false

    onValueChanged: {
        if (suppressCommand) return
        root.userInteracted()
        pendingPercent = Math.round(value)
        if (!throttleActive) {
            throttleActive = true
            sendThrottle.lastSentPercent = pendingPercent
            bridge.setVolumePercent(pendingPercent)
            sendThrottle.restart()
        }
    }

    Timer {
        id: sendThrottle
        interval: 80
        repeat: false
        property int lastSentPercent: -1
        onTriggered: {
            if (root.pendingPercent !== lastSentPercent) {
                lastSentPercent = root.pendingPercent
                root.bridge.setVolumePercent(root.pendingPercent)
                restart()
            } else {
                root.throttleActive = false
            }
        }
    }

    function syncFromBridge() {
        suppressCommand = true
        value = bridge.volumePercent
        suppressCommand = false
    }

    Component.onCompleted: syncFromBridge()
    onBridgeChanged: syncFromBridge()
    onPressedChanged: {
        if (!pressed) syncFromBridge()
    }
    Connections {
        target: root.bridge
        function onVolumePercentChanged() {
            if (!root.pressed) root.syncFromBridge()
        }
    }
}
