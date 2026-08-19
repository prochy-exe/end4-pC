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

    property EffectController controller: EffectController {
        ambientAllowedHere: root.ambientAllowedHere
        monitorName: root.monitorName
        transitionDirection: root.transitionDirection
    }
    readonly property bool transitioning: root.controller.transitioning

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
    Component.onCompleted: root.applySource()

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
        // Progress before the flip, both in one go, so the renderer never gets
        // a frame with the new wallpaper already at full mix.
        root.controller.transitionProgress = instant ? 1.0 : 0.0;
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

    WallpaperRenderer {
        anchors.fill: parent
        active: root.active
        sourceA: root.backImage
        sourceB: root.frontImage
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
}
