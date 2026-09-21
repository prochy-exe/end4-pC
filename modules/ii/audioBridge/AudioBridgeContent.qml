pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A single global volume control that automatically targets whichever
// device is actually doing the amplifying, rather than a manual per-device
// picker: when the DX5 II is routed out via any Line Out output (LO ALL/
// LO SE/LO BAL - feeding an external amp, here the WiiM), the DX5 II's own
// volume control is the wrong target (and, if it's also in DAC mode, is
// additionally inert - see Dx5iiBridge.volumeInert), so the slider drives
// the WiiM instead. Otherwise (a headphone output, or "All") the DX5 II is
// itself the amp, so the slider drives it directly.
//
// DAC mode is deliberately NOT an independent trigger for this - it only
// actually does anything (fixes the line-out level, ignores volume
// commands) while output is routed via Line Out. On a headphone output,
// DAC mode has no bearing on volume at all, so it must never override the
// Line-Out-based routing decision by itself.
//
// The DX5 II's own output routing selector is separate from all of this -
// it always targets the DX5 II regardless of which device the volume
// slider is currently driving, since it's the one actually routing audio
// to the physical outputs.
//
// The actual routing decision lives in AudioBridgeRouter.qml, shared with
// the keyboard-shortcut IPC actions in AudioBridge.qml, so this popup and
// those shortcuts can't disagree about which device is "active".
Item {
    id: root
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    readonly property var activeBridge: AudioBridgeRouter.activeBridge
    readonly property string activeBridgeName: AudioBridgeRouter.activeBridgeName
    readonly property string routeReason: AudioBridgeRouter.routeReason

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        implicitWidth: 340
        implicitHeight: contentColumn.implicitHeight + 32
        radius: Appearance.rounding.large
        color: MonitorThemes.shellColorForItem(root, "colLayer0", Appearance.colors.colLayer0)
        border.width: 1
        border.color: MonitorThemes.shellColorForItem(root, "colLayer0Border", Appearance.colors.colLayer0Border)

        ColumnLayout {
            id: contentColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            spacing: 14

            StyledText {
                text: Translation.tr("Audio bridges")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
            }

            // --- Which device the slider below is currently driving, and why ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: root.activeBridge.deviceConnected ? "check_circle" : (root.activeBridge.relayConnected ? "sync_problem" : "cancel")
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.activeBridge.deviceConnected
                        ? MonitorThemes.colorForItem(root, "primary", Appearance.m3colors.m3primary)
                        : MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    text: {
                        const suffix = root.routeReason.length > 0 ? ` (${root.routeReason})` : ""
                        if (root.activeBridge.deviceConnected) return Translation.tr("Controlling %1 volume%2").arg(root.activeBridgeName).arg(suffix)
                        if (root.activeBridge.relayConnected) return Translation.tr("Bridge running, %1 not reachable%2").arg(root.activeBridgeName).arg(suffix)
                        return Translation.tr("Starting %1 bridge...%2").arg(root.activeBridgeName).arg(suffix)
                    }
                }
            }

            // --- Volume ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    enabled: root.activeBridge.relayConnected
                    onClicked: root.activeBridge.toggleMute()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.activeBridge.isMuted ? "volume_off" : "volume_up"
                        iconSize: Appearance.font.pixelSize.larger
                        color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
                    }
                }

                ThrottledVolumeSlider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    bridge: root.activeBridge
                }

                StyledText {
                    text: root.activeBridge.hasVolume ? `${root.activeBridge.volumePercent}%` : "--"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
                    Layout.preferredWidth: 34
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutline)
                opacity: 0.2
            }

            // --- DX5 II output routing - always the DX5 II, regardless of
            // which device's volume is currently selected above, since it's
            // the one actually routing audio to the physical outputs. ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("DX5 II output")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                }

                StyledComboBox {
                    id: outputCombo
                    Layout.fillWidth: true
                    enabled: Dx5iiBridge.relayConnected
                    model: Dx5iiBridge.outputTypeOptions.map(o => o.name)

                    // currentIndex is deliberately not a plain `:` binding:
                    // QtQuick's ComboBox assigns to it internally as part of
                    // populating from `model` (e.g. resetting to 0), which
                    // silently breaks a declarative binding the first time
                    // that happens. Re-asserting it imperatively whenever the
                    // underlying value or the (filtered) option list changes
                    // is what actually keeps it in sync.
                    function syncCurrentIndex() {
                        currentIndex = Dx5iiBridge.outputTypeOptions.findIndex(o => o.value === Dx5iiBridge.outputType)
                    }

                    Component.onCompleted: syncCurrentIndex()
                    onModelChanged: syncCurrentIndex()
                    Connections {
                        target: Dx5iiBridge
                        function onOutputTypeChanged() { outputCombo.syncCurrentIndex() }
                    }

                    onActivated: index => {
                        const opt = Dx5iiBridge.outputTypeOptions[index]
                        if (opt) Dx5iiBridge.setOutputType(opt.value)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: MonitorThemes.shellColorForItem(root, "colOutlineVariant", Appearance.colors.colOutline)
                opacity: 0.2
            }

            // --- Device identification footer. dx5ii-bridge is BLE, not
            // IP-based, so its BLE address is what's shown; wamp-bridge's
            // device_info was patched (player.c's fetch_device_info) to
            // additionally report its resolved connection host, since
            // nothing in either bridge's WS API exposed one before. ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    text: {
                        const name = Dx5iiBridge.deviceName.length > 0 ? Dx5iiBridge.deviceName : "DX5 II"
                        const addr = Dx5iiBridge.bleAddress.length > 0 ? Dx5iiBridge.bleAddress : Translation.tr("unknown address")
                        return `${name} • ${addr}`
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: MonitorThemes.shellColorForItem(root, "colSubtext", Appearance.colors.colSubtext)
                    text: {
                        const name = WampBridge.deviceName.length > 0 ? WampBridge.deviceName : "WiiM"
                        const addr = WampBridge.host.length > 0 ? WampBridge.host : (WampBridge.mac.length > 0 ? WampBridge.mac : Translation.tr("unknown address"))
                        const ssid = WampBridge.ssid.length > 0 ? ` • ${WampBridge.ssid}` : ""
                        return `${name} • ${addr}${ssid}`
                    }
                }
            }
        }
    }
}
