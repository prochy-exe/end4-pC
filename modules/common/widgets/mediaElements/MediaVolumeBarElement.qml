import qs.services
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// Controls the player's own MPRIS volume directly (org.mpris.MediaPlayer2.Player's
// optional Volume property) - only affects this player, no system mixing involved.
// Hidden entirely for players that don't implement it (volumeSupported: false).
RowLayout {
    id: root
    property MprisPlayer player
    property QtObject blendedColors: null
    Layout.fillWidth: true
    spacing: 6

    readonly property color highlight: root.blendedColors?.colPrimary ?? MonitorThemes.shellColorForItem(root, "colPrimary", Appearance.colors.colPrimary)
    readonly property color track: root.blendedColors?.colSecondaryContainer ?? MonitorThemes.shellColorForItem(root, "colSecondaryContainer", Appearance.colors.colSecondaryContainer)
    readonly property color iconColor: root.blendedColors?.colOnLayer0 ?? MonitorThemes.shellColorForItem(root, "colOnLayer0", Appearance.colors.colOnLayer0)
    readonly property real volume: root.player?.volume ?? 1

    visible: root.player?.volumeSupported ?? false

    RippleButton {
        implicitWidth: 24
        implicitHeight: 24
        colBackground: "transparent"
        buttonRadius: Appearance.rounding.full
        downAction: () => {
            if (root.player) root.player.volume = (root.player.volume > 0) ? 0 : 1.0
        }
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            iconSize: Appearance.font.pixelSize.large
            color: root.iconColor
            text: root.volume <= 0 ? "volume_off" : root.volume < 0.5 ? "volume_down" : "volume_up"
        }
    }

    StyledSlider {
        Layout.fillWidth: true
        configuration: StyledSlider.Configuration.S
        highlightColor: root.highlight
        trackColor: root.track
        handleColor: root.highlight
        from: 0
        to: 1
        value: root.volume
        onMoved: {
            if (root.player) root.player.volume = value
        }
    }
}
