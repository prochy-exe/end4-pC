pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

/**
 * Audio analysis for every visualiser in the shell.
 *
 * Runs scripts/audio/qs-audiotap, which talks to PipeWire directly and does its
 * own FFT, band split, auto gain and beat detection. That replaces cava: one
 * process, no ascii-bar reparsing, and no smoothing stage between the sound and
 * the screen. Each line is
 *
 *     bass mid treble volume beat bar0 .. barN-1     (all 0..1)
 *
 * `points` keeps the old 0..1000 scale so the existing bar widgets and
 * GlobalStates.visualizerPoints consumers did not have to change.
 */
Singleton {
    id: root

    readonly property string binary: `${Directories.scriptPath}/audio/qs-audiotap`
    readonly property var opts: Config.options?.background?.effects ?? null
    readonly property var audioOpts: root.opts?.audio ?? null

    // --- scalars for the wallpaper shader, 0..1 -----------------------------
    property real bass: 0
    property real mid: 0
    property real treble: 0
    property real volume: 0
    property real beat: 0

    // --- spectrum, 0..1000 to match what the bar widgets already expect -----
    property list<real> points: []
    property list<real> inputPoints: []

    // --- capture target ------------------------------------------------------
    // Always follows whichever player is actually playing, and is deliberately
    // NOT user-configurable: the player cards and the ticker draw a visualiser
    // for the app they are showing, so the capture has to be that app's stream.
    // If its PipeWire node cannot be resolved, qs-audiotap falls back to the
    // sink monitor on its own.
    readonly property var activePlayer: (MprisController.players ?? []).find(p => p?.isPlaying) ?? null
    readonly property string captureApp: root.activePlayer
        ? (root.activePlayer.desktopEntry || root.activePlayer.identity || "")
        : ""

    // --- what the *wallpaper effect* is allowed to react to ------------------
    // Separate from the capture above: the bars stay live for whatever is
    // playing, but the wallpaper stays still unless the chosen player is the
    // one making noise. Empty means anything.
    readonly property string allowedPlayer: (root.opts?.player ?? "").toLowerCase().trim()
    readonly property bool gated: {
        if (root.allowedPlayer.length === 0)
            return false;
        const p = root.activePlayer;
        if (!p)
            return true;
        return !((p.identity ?? "").toLowerCase().includes(root.allowedPlayer)
            || (p.desktopEntry ?? "").toLowerCase().includes(root.allowedPlayer));
    }

    // --- who needs analysis running -----------------------------------------
    function layoutUsesWidget(layoutEntry, widgetId) {
        if (!layoutEntry)
            return false;
        return (layoutEntry.leftLayout ?? []).includes(widgetId)
            || (layoutEntry.middleLayout ?? []).includes(widgetId)
            || (layoutEntry.rightLayout ?? []).includes(widgetId);
    }
    function anyLayoutUsesWidget(widgetId) {
        if (root.layoutUsesWidget(Config.options?.bar?.layouts, widgetId))
            return true;
        return (Config.options?.bar?.monitorLayouts ?? []).some(l => root.layoutUsesWidget(l, widgetId));
    }

    readonly property bool outputNeeded:
        (GlobalStates.mediaControlsOpen && (Config.options?.media?.menuElements ?? []).includes("visualizer"))
        || GlobalStates.mediaTickerOpen
        || GlobalStates.sidebarRightOpen
        || root.anyLayoutUsesWidget("visualizer")
        || (Config.options?.background?.widgets?.visualizer?.enable ?? false)
        || (root.opts?.enable ?? false)
    readonly property bool inputNeeded: root.anyLayoutUsesWidget("visualizerInput")

    // Kept warm so a visualiser appearing does not have to wait for a process
    // start and a PipeWire connect. Deliberately output only: auto-starting a
    // microphone capture is not something to do behind someone's back.
    readonly property bool autoStart: root.audioOpts?.autoStart ?? true

    function parse(line, target) {
        // Running warm with nothing on screen: skip publishing rather than
        // firing bindings across the shell ~90 times a second for no viewer.
        // The next line lands within ~11ms of a consumer appearing.
        if (target === "output" && !root.outputNeeded)
            return null;
        const v = line.split(" ");
        if (v.length < 6)
            return null;
        const bars = new Array(v.length - 5);
        for (let i = 5; i < v.length; i++)
            bars[i - 5] = parseFloat(v[i]) * 1000;
        if (target === "output") {
            root.points = bars;
            GlobalStates.visualizerPoints = bars;
            GlobalStates.visualizerOutputPoints = bars;
            // The wallpaper effect must not react to a video that the player
            // filter excludes, but the bars above stay live either way.
            const g = root.gated ? 0 : 1;
            root.bass = parseFloat(v[0]) * g;
            root.mid = parseFloat(v[1]) * g;
            root.treble = parseFloat(v[2]) * g;
            root.volume = parseFloat(v[3]) * g;
            root.beat = parseFloat(v[4]) * g;
        } else {
            root.inputPoints = bars;
            GlobalStates.visualizerInputPoints = bars;
        }
        return bars;
    }

    function clearOutput() {
        root.points = [];
        GlobalStates.visualizerPoints = [];
        GlobalStates.visualizerOutputPoints = [];
        root.bass = 0;
        root.mid = 0;
        root.treble = 0;
        root.volume = 0;
        root.beat = 0;
    }

    // Builds the helper if it is missing, then execs it. Done inside the
    // command rather than as a separate build Process because Quickshell's
    // Process emits no `exited` for a binary that does not exist, so there is
    // nothing to react to - a fresh clone would just sit there with no bars.
    // Settings -> Bar -> Visualizer Audio. "auto" follows whatever is playing,
    // "app:<name>" pins one application, anything else is a PipeWire node name.
    readonly property string outputSource: Config.options?.bar?.visualizer?.outputSource || "auto"
    readonly property string inputSource: Config.options?.bar?.visualizer?.inputSource || "auto"

    // An explicit choice wins over the automatic follow; "auto" falls back to
    // whichever app is playing, and qs-audiotap falls back to the sink monitor
    // if that app's node cannot be resolved.
    readonly property var outputTargetArgs: {
        const src = root.outputSource.trim();
        if (src.startsWith("app:")) {
            const name = src.slice(4).trim();
            if (name.length > 0)
                return ["--app", name];
        } else if (src.length > 0 && src !== "auto") {
            return ["--source", src];
        }
        if (root.captureApp.length > 0)
            return ["--app", root.captureApp];
        return [];
    }

    function tapCommand(extraArgs) {
        const a = root.audioOpts;
        const args = [
            "--bars", String(a?.bars ?? 50),
            "--range", String(a?.rangeLow ?? 50), String(a?.rangeHigh ?? 16000),
            "--rate", String(a?.updateRate ?? 90),
            "--bar-decay", String(a?.barDecay ?? 0.035),
            "--beat-decay", String((a?.beatDecay ?? 100) / 1000),
            "--beat-gap", String((a?.beatMinInterval ?? 110) / 1000),
            "--beat-sensitivity", String(a?.beatSensitivity ?? 1.35),
            "--beat-floor", String(a?.beatFloor ?? 0.15),
            "--gain-release", String(a?.gainRelease ?? 0.9995)
        ].concat(extraArgs);
        return ["bash", "-c",
            'bin="$1"; shift; [ -x "$bin" ] || "$(dirname "$bin")/build.sh" >&2 || exit 1; exec "$bin" "$@"',
            "qs-audiotap", root.binary].concat(args);
    }

    property Process outputProc: Process {
        running: root.outputNeeded || root.autoStart
        command: root.tapCommand(root.outputTargetArgs)
        onRunningChanged: {
            if (!outputProc.running)
                root.clearOutput();
        }
        stderr: SplitParser {
            onRead: data => console.log("[AudioLevels]", data)
        }
        stdout: SplitParser {
            onRead: data => root.parse(data, "output")
        }
    }

    property Process inputProc: Process {
        running: root.inputNeeded
        command: root.inputSource !== "auto"
            ? root.tapCommand(["--source", root.inputSource])
            : root.tapCommand(["--mic"])
        onRunningChanged: {
            if (!inputProc.running) {
                root.inputPoints = [];
                GlobalStates.visualizerInputPoints = [];
            }
        }
        stdout: SplitParser {
            onRead: data => root.parse(data, "input")
        }
    }

    // Retarget when the allowed player changes - qs-audiotap follows one node,
    // so switching apps means restarting it with a new --app.
    onOutputTargetArgsChanged: root.restartOutput()
    onAudioOptsChanged: root.restartOutput()
    function restartOutput() {
        if (outputProc.running) {
            outputProc.running = false;
            restartTimer.restart();
        }
    }
    property Timer restartTimer: Timer {
        interval: 60
        onTriggered: outputProc.running = Qt.binding(() => root.outputNeeded)
    }
}
