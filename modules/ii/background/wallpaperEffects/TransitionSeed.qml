pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell

/**
 * The random seed for a wallpaper switch, shared by every monitor.
 *
 * Each screen gets its own WallpaperEffect and its own EffectController, so
 * rolling the seed inside startTransition() gave every monitor a different
 * disintegration for the same wallpaper change. Keying the roll on the incoming
 * wallpaper path instead means the first monitor to start rolls it and the rest
 * reuse it, so the switch looks identical everywhere.
 */
Singleton {
    id: root

    property real seed: Math.random() * 1000
    property real swapStart: 0.40
    property real swapEnd: 0.65

    /** Path the current seed was rolled for, so N monitors roll once. */
    property string rolledFor: ""

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
     * Deterministic 0..1 draw from the shared seed. Used for the per-switch
     * effect strengths so those match across monitors too - Math.random() would
     * not, since each monitor evaluates them independently.
     */
    function draw(k) {
        const x = Math.sin(root.seed * 12.9898 + k * 78.233) * 43758.5453;
        return x - Math.floor(x);
    }
}
