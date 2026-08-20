pragma ComponentBehavior: Bound

import qs.services
import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris

/**
 * One qs-audiotap bound to a single application, for UI that shows one specific
 * player - a player card, the ticker.
 *
 * AudioLevels' global tap follows whichever app is playing and publishes a
 * single shared spectrum, which is right for the bar visualiser but wrong here:
 * with two apps playing, every card drawing that shared array shows identical
 * bars regardless of which player it represents.
 *
 * Costs about 0.6% of one core and ~7MB while running, so it only runs while
 * `active` is true - normally "this card is on screen and its player is
 * playing". Falls back to nothing (empty points) rather than to the sink
 * monitor, since showing another app's audio under this card is the exact
 * confusion this exists to avoid.
 */
QtObject {
    id: root

    /** The player this tap represents. */
    property MprisPlayer player: null
    /** Set false to stop the process, e.g. while the card is off screen. */
    property bool active: true

    /** Spectrum for this app, 0..1000, matching AudioLevels.points. */
    property list<real> points: []

    readonly property string app: root.player
        ? (root.player.desktopEntry || root.player.identity || "")
        : ""
    readonly property bool shouldRun: root.active && root.app.length > 0 && (root.player?.isPlaying ?? false)

    property Process proc: Process {
        running: root.shouldRun
        command: AudioLevels.tapCommand(["--app", root.app])
        onRunningChanged: {
            if (!running)
                root.points = [];
        }
        stdout: SplitParser {
            onRead: data => {
                const v = data.split(" ");
                if (v.length < 6)
                    return;
                const bars = new Array(v.length - 5);
                for (let i = 5; i < v.length; i++)
                    bars[i - 5] = parseFloat(v[i]) * 1000;
                root.points = bars;
            }
        }
    }

    property Connections audioSettingsConnection: Connections {
        target: AudioLevels
        function onAudioSettingsChanged() {
            root.proc.running = false;
            Qt.callLater(() => root.proc.running = root.shouldRun);
        }
    }
}
