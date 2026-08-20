pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

/**
 * The random seed for a wallpaper switch, shared by every monitor.
 *
 * Each screen gets its own WallpaperEffect and its own EffectController, so
 * rolling the seed inside startTransition() gave every monitor a different
 * disintegration for the same wallpaper change. The first monitor to start
 * rolls the shared character and the rest join its generation, so the switch
 * looks identical everywhere even when each monitor has a different image.
 */
Singleton {
    id: root

    property real seed: Math.random() * 1000
    property real swapStart: 0.40
    property real swapEnd: 0.65

    /** Path the current seed was rolled for, so N monitors roll once. */
    property string rolledFor: ""
    /** Monotonic identity for the current multi-monitor wallpaper change. */
    property int generation: 0
    /** 0 = old frame, 1 = new frame, shared by primary and seam extensions. */
    property real transitionProgress: 1.0
    property int transitionDuration: 1200
    // Gives all local and borrowed textures time to upload before the common
    // clock advances. Otherwise a late receiver first becomes visible halfway
    // across its monitor, which reads as a pop instead of a travelling seam.
    property int textureReadyDelay: 180
    // One clock for all wallpaper shader instances. The renderer only reads it
    // while active, so this does not cause idle wallpaper repaints, but it
    // keeps primary and secondary procedural phases in lockstep.
    property real effectTime: Date.now() / 1000
    readonly property bool transitioning: transitionDelay.running || transitionAnimation.running
    readonly property real transitionMix: {
        const a = root.swapStart;
        const b = Math.max(a + 0.001, root.swapEnd);
        const t = Math.max(0, Math.min(1, (root.transitionProgress - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }
    readonly property real transitionEnvelope: Math.pow(Math.sin(Math.PI
        * Math.max(0, Math.min(1, root.transitionProgress))), 1.5)

    function rollFor(path, datamosh) {
        if (path === root.rolledFor)
            return;
        root.rolledFor = path;
        root.seed = Math.random() * 1000;
        if (datamosh) {
            root.swapStart = 0.34 + Math.random() * 0.16;
            root.swapEnd = root.swapStart + 0.16 + Math.random() * 0.18;
        } else {
            // A dissolve has no destruction peak to hide the swap behind, so it
            // hands over across the whole animation instead.
            root.swapStart = 0.0;
            root.swapEnd = 1.0;
        }
    }

    /**
     * Starts one clock for a wallpaper-change event. Screens may legitimately
     * have different incoming paths in per-monitor or mutual-fragment mode,
     * so path equality must never decide whether a receiver joins the clock.
     * Any caller arriving while it is staging or running joins this generation.
     */
    function startTransition(path, duration, datamosh) {
        const next = path ?? "";
        if (next === "")
            return root.generation;
        if (root.transitioning)
            return root.generation;
        root.rollFor(next, datamosh);
        root.transitionDuration = duration;
        root.transitionProgress = 0.0;
        root.generation += 1;
        transitionDelay.restart();
        return root.generation;
    }

    Timer {
        id: transitionDelay
        interval: root.textureReadyDelay
        onTriggered: transitionAnimation.restart()
    }

    NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: root.transitionDuration
        easing.type: Easing.Linear
    }

    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: root.effectTime = Date.now() / 1000
    }

    /**
     * Deterministic 0..1 draw from the shared seed. Used for the per-switch
     * effect strengths so those match across monitors too - Math.random() would
     * not, since each monitor evaluates them independently.
     */
    function draw(k) {
        const x = Math.sin(root.seed * 12.9898 + k * 78.233) * 43758.5453;
        return x - Math.floor(x);
    }
}
