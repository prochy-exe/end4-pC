pragma ComponentBehavior: Bound

import qs.modules.ii.background.wallpaperEffects
import QtQuick

/**
 * The GPU half: one fragment pass plus a recursive ShaderEffectSource that
 * feeds the previous frame back in. Owns no policy - every number it hands to
 * the shader comes from `controller`.
 */
Item {
    id: root

    /** Items used as textures. Both need layer.enabled or an Image layer. */
    property Item sourceA
    property Item sourceB
    /** Old and new local copies of the primary wallpaper borrowed by this monitor. */
    property Item neighborWallpaperA
    property Item neighborWallpaperB
    /** Granular source A -> B handover for the permanent cross-monitor seam. */
    property real neighborTransitionMix: 1.0
    /** Shared 0 -> 1 wallpaper-change clock for the cross-monitor sweep. */
    property real neighborTransitionPhase: 1.0
    property bool neighborTransitioning: false
    /** The primary's destructive switch envelope, shared with its seam. */
    property real neighborTransition: 0.0
    property vector2d neighborTransitionDirection: Qt.vector2d(0, 0)
    /** Unit vector from this monitor toward that neighbour. */
    property vector2d neighborDirection: Qt.vector2d(0, 0)
    /** This receiver's bounds in the primary monitor's virtual canvas. */
    property vector2d neighborCanvasOrigin: Qt.vector2d(0, 0)
    property vector2d neighborCanvasScale: Qt.vector2d(1, 1)
    property vector2d neighborCanvasResolution: Qt.vector2d(1, 1)
    /** Resolved look of the monitor that owns the borrowed wallpaper. */
    property var neighborEffectValues: null
    property real neighborEffectStrength: 0
    property real neighborTransitionAxisMode: 2
    property real neighborTransitionAxisSign: 1
    property bool neighborReady: false
    property EffectController controller
    /**
     * False while the window this lives in is not on screen. Everything that
     * touches the scene graph has to stop then: Quickshell tears the window
     * down when the wallpaper is hidden (fullscreen video, lock/wake), and any
     * item still being marked dirty afterwards crashes in addToDirtyList().
     */
    property bool active: true

    ShaderEffect {
        id: shader
        anchors.fill: parent

        property vector2d resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
        property real time: 0

        property variant sourceA: root.sourceA
        property variant sourceB: root.sourceB
        property variant previousFrame: feedbackBuffer
        property variant spectrum: spectrumStrip
        property variant neighborWallpaperA: root.neighborWallpaperA
        property variant neighborWallpaperB: root.neighborWallpaperB
        property real neighborTransitionMix: root.neighborTransitionMix
        property real neighborTransitionPhase: root.neighborTransitionPhase
        property real neighborTransition: root.neighborTransition
        property vector2d neighborTransitionDirection: root.neighborTransitionDirection
        property vector2d neighborDirection: root.neighborDirection
        property vector2d neighborCanvasOrigin: root.neighborCanvasOrigin
        property vector2d neighborCanvasScale: root.neighborCanvasScale
        property vector2d neighborCanvasResolution: root.neighborCanvasResolution
        property real neighborEffectStrength: root.neighborEffectStrength
        property real neighborPointAmount: root.neighborEffectValues?.pointCloud ?? root.controller?.pointAmount ?? 0
        property real neighborMusicIntensity: root.neighborEffectValues?.musicIntensity ?? root.controller?.musicIntensity ?? 0
        property real neighborBeatIntensity: root.neighborEffectValues?.beatIntensity ?? root.controller?.beatIntensity ?? 0
        property real neighborPointSpacing: root.neighborEffectValues?.pointSpacing ?? root.controller?.pointSpacing ?? 10
        property real neighborMeltAmount: root.neighborEffectValues?.melt ?? root.controller?.meltAmount ?? 0
        property real neighborMeltReach: root.neighborEffectValues?.meltReach ?? root.controller?.meltReach ?? 0.55
        property real neighborMeltWidth: root.neighborEffectValues?.meltWidth ?? root.controller?.meltWidth ?? 14
        property real neighborSortAmount: root.neighborEffectValues?.pixelSort ?? root.controller?.sortAmount ?? 0
        property real neighborSortThreshold: root.neighborEffectValues?.sortThreshold ?? root.controller?.sortThreshold ?? 0.65
        property real neighborSortLength: root.neighborEffectValues?.sortLength ?? root.controller?.sortLength ?? 0.1
        property real neighborBlockSize: root.neighborEffectValues?.blockSize ?? root.controller?.blockSize ?? 8
        property real neighborBlockAmount: root.neighborEffectValues?.blockCorruption ?? root.controller?.blockAmount ?? 0
        property real neighborChromaticAberration: root.neighborEffectValues?.chromaticAberration ?? root.controller?.chromaticAberration ?? 0
        property real neighborNoiseAmount: root.neighborEffectValues?.noise ?? root.controller?.noiseAmount ?? 0
        property real neighborTrAxisMode: root.neighborTransitionAxisMode
        property real neighborTrAxisSign: root.neighborTransitionAxisSign
        property real neighborReady: root.neighborReady ? 1.0 : 0.0

        property real bass: root.controller?.bass ?? 0
        property real mid: root.controller?.mid ?? 0
        property real treble: root.controller?.treble ?? 0
        property real volume: root.controller?.volume ?? 0
        property real beat: root.controller?.beat ?? 0

        property real effectStrength: root.controller?.effectStrength ?? 0
        property real musicIntensity: root.controller?.musicIntensity ?? 0
        property real beatIntensity: root.controller?.beatIntensity ?? 0
        property real meltTrigger: root.controller?.meltTrigger ?? 0
        property real pointTrigger: root.controller?.pointTrigger ?? 0
        property real feedbackTrigger: root.controller?.feedbackTrigger ?? 0
        property real sortTrigger: root.controller?.sortTrigger ?? 0
        property real blockTrigger: root.controller?.blockTrigger ?? 0
        property real aberrationTrigger: root.controller?.aberrationTrigger ?? 0
        property real noiseTrigger: root.controller?.noiseTrigger ?? 0
        property real lidarTrigger: root.controller?.lidarTrigger ?? 0
        property real transition: root.controller?.transition ?? 0
        property real transitionMix: root.controller?.transitionMix ?? 1
        property real transitionSeed: root.controller?.transitionSeed ?? 0

        property real pointAmount: root.controller?.pointAmount ?? 0
        property real pointSpacing: root.controller?.pointSpacing ?? 10
        property real meltAmount: root.controller?.meltAmount ?? 0
        property real meltReach: root.controller?.meltReach ?? 0.55
        property real meltWidth: root.controller?.meltWidth ?? 14
        property real feedbackAmount: root.controller?.feedbackAmount ?? 0
        property real sortAmount: root.controller?.sortAmount ?? 0
        property real sortThreshold: root.controller?.sortThreshold ?? 0.65
        property real sortLength: root.controller?.sortLength ?? 0.1
        property real sortDirection: root.controller?.sortDirection ?? 1
        property real trMelt: root.controller?.trMelt ?? 0
        property real trPoint: root.controller?.trPoint ?? 0
        property real trSort: root.controller?.trSort ?? 0
        property real trBlock: root.controller?.trBlock ?? 0
        property real trFeedback: root.controller?.trFeedback ?? 0
        property real trAberration: root.controller?.trAberration ?? 0
        property real trNoise: root.controller?.trNoise ?? 0
        property real neighborBleed: root.controller?.neighborBleed ?? 0
        property real neighborBleedMusicReactive: root.controller?.neighborBleedMusicReactive ?? 0
        property real neighborBleedWidth: root.controller?.neighborBleedWidth ?? 0.16
        property real neighborBleedStrength: root.controller?.neighborBleedStrength ?? 0.9
        property real neighborBleedFragmentThreshold: root.controller?.neighborBleedFragmentThreshold ?? 0.08
        property real neighborBleedFragmentSoftness: root.controller?.neighborBleedFragmentSoftness ?? 0.24
        property real neighborBleedColorTrails: root.controller?.neighborBleedColorTrails ?? 1
        property real neighborBleedColorThreshold: root.controller?.neighborBleedColorThreshold ?? 0.12
        property real neighborBleedColorSoftness: root.controller?.neighborBleedColorSoftness ?? 0.20
        property real neighborBleedColorStrength: root.controller?.neighborBleedColorStrength ?? 0.7
        property real neighborBleedLidar: root.controller?.neighborBleedLidar ?? 0
        property real neighborBleedLidarOutlines: root.controller?.neighborBleedLidarOutlines ?? 0
        property real neighborBleedLidarStrength: root.controller?.neighborBleedLidarStrength ?? 0.55
        property real neighborBleedLidarDensity: root.controller?.neighborBleedLidarDensity ?? 24
        property real neighborBleedLidarSpeed: root.controller?.neighborBleedLidarSpeed ?? 0.75
        property real lidarEnabled: root.controller?.lidarEnabled ?? 0
        property real neighborBleedEdgeSoftness: root.controller?.neighborBleedEdgeSoftness ?? 0.32
        property real neighborBleedRaggedness: root.controller?.neighborBleedRaggedness ?? 1
        property real neighborBleedGrain: root.controller?.neighborBleedGrain ?? 1
        property real neighborBleedMotionSpeed: root.controller?.neighborBleedMotionSpeed ?? 1
        property real neighborBleedFeedback: root.controller?.neighborBleedFeedback ?? 1
        property real neighborBleedBattle: root.controller?.neighborBleedBattle ?? 1
        property real neighborBleedBattleStrength: root.controller?.neighborBleedBattleStrength ?? 1
        property real neighborBleedPrimaryPush: root.controller?.neighborBleedPrimaryPush ?? 1
        property real neighborBleedSecondaryResistance: root.controller?.neighborBleedSecondaryResistance ?? 1
        property real neighborBleedEffectStrength: root.controller?.neighborBleedEffectStrength ?? 0
        property real trAxisMode: root.controller?.trAxisMode ?? 2
        property real trAxisSign: root.controller?.trAxisSign ?? 1
        property real blockSize: root.controller?.blockSize ?? 8
        property real blockAmount: root.controller?.blockAmount ?? 0
        property real chromaticAberration: root.controller?.chromaticAberration ?? 0
        property real noiseAmount: root.controller?.noiseAmount ?? 0

        fragmentShader: Qt.resolvedUrl("shaders/wallpaper.frag.qsb")
    }

    /**
     * Snapshot of the spectrum, republished only from the render tick below.
     *
     * The strip's colours bind to *this*, never to AudioLevels directly. That
     * matters: bound straight to the audio signal, ~50 Rectangle colour writes
     * fire ~90 times a second from whenever the tap happens to emit, including
     * while Quickshell is tearing this window down for a fullscreen video or a
     * lock/wake - and an item marked dirty against a destroyed window segfaults
     * in QQuickItemPrivate::addToDirtyList().
     *
     * Going through here means the scene graph is only ever touched from our own
     * FrameAnimation, which stops whenever `active` or `animating` is false. The
     * audio signal cannot reach an item on its own schedule any more.
     */
    property var liveSpectrum: []

    // The spectrum as a one-pixel-tall strip, one pixel per FFT bar, handed to
    // the shader as a texture. Rectangles rather than a Canvas: this is pure
    // scene graph with no per-frame JS painting, and layer.smooth gives the
    // linear filtering that turns 50 bars into a continuous curve.
    Item {
        id: spectrumStrip
        width: Math.max(1, root.liveSpectrum.length)
        height: 1
        visible: false
        layer.enabled: true
        layer.smooth: true

        Repeater {
            model: spectrumStrip.width
            Rectangle {
                required property int index
                x: index
                y: 0
                width: 1
                height: 1
                color: {
                    const raw = root.liveSpectrum[index] ?? 0;
                    const v = Math.max(0, Math.min(1, raw / 1000));
                    return Qt.rgba(v, v, v, 1);
                }
            }
        }
    }

    // Previous-frame buffer. `recursive` is what makes sampling our own output
    // legal - Qt double-buffers it so this frame reads what the last one wrote.
    ShaderEffectSource {
        id: feedbackBuffer
        // Deliberately not anchored. A ShaderEffectSource's own geometry is
        // meaningless - its texture size follows `sourceItem` - and anchoring it
        // put a *recursive* (double-buffered) FBO into the geometry cascade that
        // runs when Quickshell re-creates this window, which is where it crashed.
        visible: false
        sourceItem: shader
        hideSource: false
        recursive: true
        live: root.active && ((root.controller?.animating ?? false) || root.neighborTransitioning)
        wrapMode: ShaderEffectSource.ClampToEdge
        // Allocate the (double-buffered, screen-sized) FBOs up front. Left to
        // `live` flipping true at the start of a transition, that allocation
        // lands mid-animation and shows up as a dropped frame.
        Component.onCompleted: feedbackBuffer.scheduleUpdate()
    }

    // Drives `time`. Stopping this when nothing is animating is what makes the
    // idle case free: no repaint is requested, so the wallpaper is a still image.
    FrameAnimation {
        running: root.active && ((root.controller?.animating ?? false) || root.neighborTransitioning
            || root.neighborEffectStrength > 0.0005)
        onTriggered: {
            // Every monitor evaluates its procedural effects against this
            // singleton timeline, so a primary effect and its extension agree
            // on the same block/noise phase at the shared physical edge.
            shader.time = TransitionSeed.effectTime;
            // Republish the spectrum from inside the render tick - see
            // liveSpectrum. Stops dead with this animation, so nothing keeps
            // dirtying scene-graph items once the window is gone.
            root.liveSpectrum = root.controller?.spectrum ?? [];
        }
    }

}
