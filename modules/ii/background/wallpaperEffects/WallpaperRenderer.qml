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

        property real bass: root.controller?.bass ?? 0
        property real mid: root.controller?.mid ?? 0
        property real treble: root.controller?.treble ?? 0
        property real volume: root.controller?.volume ?? 0
        property real beat: root.controller?.beat ?? 0

        property real effectStrength: root.controller?.effectStrength ?? 0
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
        live: root.active && (root.controller?.animating ?? false)
        wrapMode: ShaderEffectSource.ClampToEdge
        // Allocate the (double-buffered, screen-sized) FBOs up front. Left to
        // `live` flipping true at the start of a transition, that allocation
        // lands mid-animation and shows up as a dropped frame.
        Component.onCompleted: feedbackBuffer.scheduleUpdate()
    }

    // Drives `time`. Stopping this when nothing is animating is what makes the
    // idle case free: no repaint is requested, so the wallpaper is a still image.
    FrameAnimation {
        running: root.active && (root.controller?.animating ?? false)
        onTriggered: {
            shader.time += frameTime;
            // Republish the spectrum from inside the render tick - see
            // liveSpectrum. Stops dead with this animation, so nothing keeps
            // dirtying scene-graph items once the window is gone.
            root.liveSpectrum = root.controller?.spectrum ?? [];
        }
    }
}
