pragma ComponentBehavior: Bound

import qs.modules.ii.background.wallpaperEffects
import QtQuick

/**
 * Drop-in shader wallpaper, covering both uses of the effect system:
 *
 *  - the ambient effect, which continuously melts/moshes whatever wallpaper is
 *    currently set and reacts to music (Config ...background.effects.enable);
 *  - the switch transition, where changing `source` disintegrates the old
 *    wallpaper into the new one, selected by setting the wallpaper animation
 *    to "datamosh" (...background.wallpaperAnimation).
 *
 * Neither depends on the other; either works without the other.
 */
Item {
    id: root

    /** Path (or url) of the wallpaper to show. */
    property string source: ""
    /** Set false to swap wallpapers instantly, without the transition. */
    property bool animateSwitch: root.controller.transitionEnabled
    /** False while the window is off screen - see WallpaperRenderer.active. */
    property bool active: true
    /** Whether the ambient effect (not the switch transition) is allowed to
     * show on this monitor - see Background.qml's effectAllowedHere. */
    property bool ambientAllowedHere: true
    /** This monitor's name, only used for per-monitor randomization - see
     * Config...background.effects.randomizePerMonitor. */
    property string monitorName: ""
    /** "", "up", "down", "left", "right" - see Background.qml's
     * transitionDirection. Only meaningful while a datamosh switch runs. */
    property string transitionDirection: ""
    /** Primary-monitor wallpaper path, borrowed by a secondary monitor. */
    property string neighborSource: ""
    /** Direction from this monitor toward that neighbour. */
    property string neighborDirection: ""
    /** Receiver bounds expressed in the primary monitor's virtual canvas. */
    property vector2d neighborCanvasOrigin: Qt.vector2d(0, 0)
    property vector2d neighborCanvasScale: Qt.vector2d(1, 1)
    property vector2d neighborCanvasResolution: Qt.vector2d(1, 1)
    /** Resolved effect values from the monitor that owns neighborSource. */
    property var neighborEffectValues: null
    /** Whether the source monitor itself is configured to show ambient effects. */
    property bool neighborAmbientAllowed: false
    /** The source monitor's synchronized transition direction. */
    property string neighborSourceTransitionDirection: ""
    readonly property vector2d neighborDirectionVector: {
        switch (root.neighborDirection) {
        case "right": return Qt.vector2d(1, 0);
        case "left": return Qt.vector2d(-1, 0);
        case "down": return Qt.vector2d(0, 1);
        case "up": return Qt.vector2d(0, -1);
        default: return Qt.vector2d(0, 0);
        }
    }
    // The borrowed primary image travels away from the primary and into this
    // monitor, the opposite of the vector used to find its facing source edge.
    readonly property vector2d neighborTransitionDirection: Qt.vector2d(
        -root.neighborDirectionVector.x, -root.neighborDirectionVector.y)

    property EffectController controller: EffectController {
        ambientAllowedHere: root.ambientAllowedHere
        monitorName: root.monitorName
        transitionDirection: root.transitionDirection
        neighborAvailable: root.neighborDirection !== ""
    }
    readonly property bool transitioning: root.controller.transitioning
    readonly property real neighborEffectStrength: root.controller.effectStrengthFor(
        root.neighborEffectValues, root.neighborAmbientAllowed)
    readonly property real neighborTransitionAxisMode: root.controller.transitionAxisModeFor(
        root.neighborSourceTransitionDirection)
    readonly property real neighborTransitionAxisSign: root.controller.transitionAxisSignFor(
        root.neighborSourceTransitionDirection)

    // Two textures, ping-ponged rather than reloaded. `secondIsFront` says which
    // one holds the wallpaper on screen; the incoming one is always loaded into
    // the other. Nothing is ever unloaded, so the *outgoing* wallpaper is still
    // resident when a transition starts - reloading it was what produced a black
    // frame at the start of every switch, since the transition begins at
    // transitionMix 0, i.e. showing sourceA.
    property bool secondIsFront: false
    readonly property Image frontImage: root.secondIsFront ? imageTwo : imageOne
    readonly property Image backImage: root.secondIsFront ? imageOne : imageTwo

    /** What the user is currently seeing. */
    property string shownSource: ""
    /** Loading into backImage, waiting on it to become ready. */
    property string loadingSource: ""
    /** Requested while a transition was already running. */
    property string queuedSource: ""

    onSourceChanged: root.applySource()
    Component.onCompleted: {
        root.applySource();
        root.applyNeighborSource();
    }

    function applySource() {
        if (!root.controller || root.source === root.shownSource || root.source === root.loadingSource)
            return;

        // backImage is the outgoing wallpaper while a transition runs, so it
        // cannot be reused until that finishes. Queue instead of corrupting it.
        if (root.controller.transitioning) {
            root.queuedSource = root.source;
            return;
        }

        root.loadingSource = root.source;
        root.backImage.source = root.source;
        // Cached images load synchronously and may never emit a status change,
        // so try immediately as well as from onStatusChanged.
        root.showWhenReady();
    }

    // Nothing is put on screen until the incoming wallpaper has actually
    // decoded - that is what keeps the first frame from being empty.
    function showWhenReady() {
        const loaded = root.loadingSource;
        if (loaded === "" || root.backImage.status === Image.Loading)
            return;
        root.loadingSource = "";
        if (root.backImage.status === Image.Error)
            return;
        root.pendingSource = loaded;

        // First wallpaper, or transitions turned off: nothing to stutter, show
        // it outright.
        if (!root.animateSwitch || root.shownSource === "") {
            root.reveal(true);
            return;
        }
        // Image.Ready only means *decoded*. The upload to the GPU happens on the
        // first frame that binds the texture, which would otherwise be the first
        // frame of the transition - that upload is the stutter. backImage is
        // already bound as sourceA, so letting a couple of frames render first
        // gets it uploaded before the animation starts.
        root.warmupFrames = 2;
        warmup.running = true;
    }

    function reveal(instant) {
        const loaded = root.pendingSource;
        root.pendingSource = "";
        // The shared controller enters its staging phase immediately after the
        // flip, at progress 0, so the renderer keeps sampling source A until
        // every monitor has had a chance to upload source B.
        root.secondIsFront = !root.secondIsFront;
        root.shownSource = loaded;

        if (instant) {
            root.controller.settle();
            // Give the other Image the same wallpaper on first load. Its texture
            // and layer FBO are then already built when the first switch binds
            // it, instead of costing a ~200ms hitch mid-transition.
            if (root.backImage.source === "")
                root.backImage.source = loaded;
        } else {
            root.controller.startTransition(loaded);
        }
    }

    // Counts down rendered frames between "decoded" and "start the transition".
    property int warmupFrames: 0
    property string pendingSource: ""

    FrameAnimation {
        id: warmup
        running: false
        onTriggered: {
            if (--root.warmupFrames > 0)
                return;
            warmup.running = false;
            root.reveal(false);
        }
    }

    Image {
        id: imageOne
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        asynchronous: true
        visible: false
        layer.enabled: true
        onStatusChanged: root.showWhenReady()
    }

    Image {
        id: imageTwo
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        asynchronous: true
        visible: false
        layer.enabled: true
        onStatusChanged: root.showWhenReady()
    }

    // Windows have independent scene graphs, so a ShaderEffect cannot sample a
    // neighbour window directly. These two local copies are ping-ponged just
    // like this monitor's own wallpapers. Keeping the outgoing primary image
    // resident gives the seam shader an A/B pair to break apart rather than
    // replacing the borrowed picture in one visible pop.
    property bool neighborSecondIsFront: false
    readonly property Image neighborFrontImage: root.neighborSecondIsFront ? neighborImageTwo : neighborImageOne
    readonly property Image neighborBackImage: root.neighborSecondIsFront ? neighborImageOne : neighborImageTwo
    property string shownNeighborSource: ""
    property string loadingNeighborSource: ""
    property string queuedNeighborSource: ""
    property string pendingNeighborSource: ""
    property bool neighborAwaitingSharedTransition: false
    /** Shared transition generation joined by the currently shown neighbour. */
    property int neighborTransitionGeneration: 0
    // This is the primary wallpaper's switch clock, not an animation local to
    // the secondary monitor. Once its borrowed texture is decoded, the seam
    // joins the switch at the same progress and with the same seed. Generation
    // rather than path is intentional: mutual mode has two different paths.
    readonly property bool neighborTransitioning: root.shownNeighborSource !== ""
        && root.neighborTransitionGeneration === TransitionSeed.generation
        && TransitionSeed.transitioning
    readonly property real neighborTransitionProgress: root.neighborTransitioning
        ? TransitionSeed.transitionMix : 1.0
    // Unlike the granular A -> B mix above, this is the uncompressed shared
    // clock. The seam uses it to travel all the way across the receiving
    // monitor and back instead of appearing only at the destruction peak.
    readonly property real neighborTransitionPhase: root.neighborTransitioning
        ? TransitionSeed.transitionProgress : 1.0
    readonly property real neighborTransition: root.neighborTransitioning
        ? TransitionSeed.transitionEnvelope * root.controller.transitionIntensity : 0.0
    property int neighborWarmupFrames: 0

    onNeighborSourceChanged: root.applyNeighborSource()

    function applyNeighborSource() {
        const requested = root.neighborSource;
        if (requested === "" || requested === root.shownNeighborSource || requested === root.loadingNeighborSource)
            return;

        // The outgoing texture is still sampled while its granular reveal is
        // in flight. Do not overwrite it with a third wallpaper mid-effect.
        if (root.neighborTransitioning) {
            root.queuedNeighborSource = requested;
            return;
        }

        root.loadingNeighborSource = requested;
        root.neighborBackImage.source = requested;
        root.showNeighborWhenReady();
    }

    function showNeighborWhenReady() {
        const loaded = root.loadingNeighborSource;
        if (loaded === "" || root.neighborBackImage.status === Image.Loading)
            return;
        root.loadingNeighborSource = "";
        if (root.neighborBackImage.status === Image.Error)
            return;
        root.pendingNeighborSource = loaded;

        if (!root.animateSwitch || root.shownNeighborSource === "") {
            root.revealNeighbor(true);
            return;
        }

        // Bind the incoming source for two frames before it becomes visible so
        // its first transition block does not pay the texture-upload cost.
        root.neighborWarmupFrames = 2;
        neighborWarmup.running = true;
    }

    function revealNeighbor(instant) {
        const loaded = root.pendingNeighborSource;
        // The source monitor has not started the shared generation yet. Keep
        // the old seam resident until it does; a local clock would make this
        // receiver pop in independently of the actual wallpaper handover.
        if (!instant && !TransitionSeed.transitioning) {
            root.neighborAwaitingSharedTransition = true;
            return;
        }

        root.pendingNeighborSource = "";
        root.neighborAwaitingSharedTransition = false;
        root.neighborSecondIsFront = !root.neighborSecondIsFront;
        root.shownNeighborSource = loaded;
        root.neighborTransitionGeneration = instant ? 0 : TransitionSeed.generation;

        if (instant) {
            if (root.neighborBackImage.source === "")
                root.neighborBackImage.source = loaded;
            return;
        }

    }

    FrameAnimation {
        id: neighborWarmup
        running: false
        onTriggered: {
            if (--root.neighborWarmupFrames > 0)
                return;
            neighborWarmup.running = false;
            root.revealNeighbor(false);
        }
    }

    Image {
        id: neighborImageOne
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        asynchronous: true
        visible: false
        layer.enabled: true
        onStatusChanged: root.showNeighborWhenReady()
    }

    Image {
        id: neighborImageTwo
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        asynchronous: true
        visible: false
        layer.enabled: true
        onStatusChanged: root.showNeighborWhenReady()
    }

    WallpaperRenderer {
        anchors.fill: parent
        active: root.active
        sourceA: root.backImage
        sourceB: root.frontImage
        neighborWallpaperA: root.neighborBackImage
        neighborWallpaperB: root.neighborFrontImage
        neighborTransitionMix: root.neighborTransitionProgress
        neighborTransitionPhase: root.neighborTransitionPhase
        neighborTransitioning: root.neighborTransitioning
        neighborTransition: root.neighborTransition
        neighborTransitionDirection: root.neighborTransitionDirection
        neighborDirection: root.neighborDirectionVector
        neighborCanvasOrigin: root.neighborCanvasOrigin
        neighborCanvasScale: root.neighborCanvasScale
        neighborCanvasResolution: root.neighborCanvasResolution
        neighborEffectValues: root.neighborEffectValues
        neighborEffectStrength: root.neighborEffectStrength
        neighborTransitionAxisMode: root.neighborTransitionAxisMode
        neighborTransitionAxisSign: root.neighborTransitionAxisSign
        neighborReady: root.neighborDirection !== "" && root.shownNeighborSource !== ""
            && root.neighborFrontImage.status === Image.Ready
        controller: root.controller
    }

    // A switch requested mid-transition was deferred; run it now.
    Connections {
        target: root.controller
        function onTransitioningChanged() {
            if (root.controller.transitioning || root.queuedSource === "")
                return;
            root.queuedSource = "";
            root.applySource();
        }
    }

    Connections {
        target: TransitionSeed
        function onTransitioningChanged() {
            if (TransitionSeed.transitioning) {
                if (root.neighborAwaitingSharedTransition && root.pendingNeighborSource !== "")
                    root.revealNeighbor(false);
                return;
            }
            if (root.queuedNeighborSource === "")
                return;
            root.queuedNeighborSource = "";
            root.applyNeighborSource();
        }
    }
}
