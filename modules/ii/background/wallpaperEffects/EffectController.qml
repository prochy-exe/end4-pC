pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick

/**
 * Owns the IDLE / BEAT / TRANSITION state machine and resolves every shader
 * parameter from config + audio. WallpaperRenderer reads these and does
 * nothing else with them, so all the tuning lives in one place.
 *
 * The ambient effect (idle + music on the current wallpaper) and the switch
 * transition are fully independent: the ambient effect is its own toggle, and
 * the transition is selected by picking "datamosh" as the wallpaper animation.
 */
QtObject {
    id: root

    readonly property var opts: Config.options?.background?.effects ?? null
    readonly property string wallpaperAnimation: Config.options?.background?.wallpaperAnimation ?? ""

    // Set from Background.qml's effectAllowedHere (the "Show on" monitor
    // picker). Only gates the ambient effect below - the datamosh switch
    // transition runs on every monitor regardless, see datamoshSwitch, so a
    // controller can be active (for the transition) on a monitor where the
    // ambient effect itself is excluded.
    property bool ambientAllowedHere: true

    // Set from Background.qml - this controller's own monitor name, needed
    // only for per-monitor randomization below.
    property string monitorName: ""

    // Set from Background.qml's transitionDirection. "" means no override -
    // the transition keeps its existing per-switch random axis.
    property string transitionDirection: ""

    // Settings -> Appearance -> Shader effects -> "Randomize per monitor".
    // When on, every "look" value below (everything a preset covers) comes
    // from this monitor's own assigned preset instead of the shared sliders
    // - see EffectPresets.ensureAssigned/valuesForMonitor. musicReactive,
    // player and glitchDirection stay global either way: those are toggles,
    // not part of the look.
    readonly property bool randomizePerMonitor: root.opts?.randomizePerMonitor ?? false
    readonly property var effectiveValues: (root.randomizePerMonitor && root.monitorName)
        ? (EffectPresets.valuesForMonitor(root.monitorName) ?? root.opts)
        : root.opts

    function _ensureAssigned() {
        if (root.randomizePerMonitor && root.monitorName)
            EffectPresets.ensureAssigned(root.monitorName);
    }
    Component.onCompleted: root._ensureAssigned()
    onRandomizePerMonitorChanged: root._ensureAssigned()

    // --- ambient: IDLE / MUSIC / BEAT ---------------------------------------
    readonly property bool ambientEnabled: (root.opts?.enable ?? false) && root.ambientAllowedHere
    readonly property bool musicReactive: root.ambientEnabled && (root.opts?.musicReactive ?? true)
    readonly property real musicIntensity: root.ambientEnabled ? (root.effectiveValues?.musicIntensity ?? 0.35) : 0
    readonly property real beatIntensity: root.effectiveValues?.beatIntensity ?? 0.75

    readonly property real bass: root.musicReactive ? AudioLevels.bass : 0
    readonly property real mid: root.musicReactive ? AudioLevels.mid : 0
    readonly property real treble: root.musicReactive ? AudioLevels.treble : 0
    readonly property real volume: root.musicReactive ? AudioLevels.volume : 0
    readonly property real beat: root.musicReactive ? AudioLevels.beat : 0
    // The spectrum the melt front traces. Empty when not reacting to music, in
    // which case a transition supplies its own curve.
    readonly property var spectrum: root.musicReactive ? AudioLevels.points : []

    // The states take over from each other rather than stacking, so a kick
    // peaks at exactly beatIntensity and stays clearly below a transition at
    // transitionIntensity - summing them instead put every kick at ~1.0.
    // AudioLevels.beat is already a 1 -> 0 envelope, so no second decay here.
    //
    // There is no idle floor: with nothing playing this is 0, the wallpaper is
    // a still image and the renderer stops requesting frames entirely.
    readonly property real effectStrength: Math.max(root.volume * root.musicIntensity, root.beat * root.beatIntensity)

    // --- TRANSITION ---------------------------------------------------------
    // Which switch animation the user picked. "datamosh" is the destructive
    // one; the classic shader transitions cannot run underneath the ambient
    // effect (it owns the wallpaper surface), so they degrade to a plain
    // block dissolve rather than silently doing nothing.
    readonly property bool datamoshSwitch: root.wallpaperAnimation === "datamosh"
    // Synchronized mode with a computed direction overrides the transition's
    // own axis/sign entirely - see Background.qml's transitionDirection. Empty
    // string (not synchronized, or nothing to synchronize against) falls
    // straight through to today's per-switch random roll below.
    readonly property bool hasDirection: root.transitionDirection !== ""
    readonly property bool transitionEnabled: root.wallpaperAnimation !== ""
    // Reuses the ambient effect's own musicReactive *toggle* - no separate
    // switch for "should the transition react to music too" - but reads it
    // directly (root.opts, not root.musicReactive/root.beat), since those are
    // additionally gated on ambientEnabled (effects.enable + this monitor's
    // ambientAllowedHere). Gating the switch transition through them would
    // make a wallpaper switch pulse differently per monitor depending on the
    // ambient "Show on" picker, and not react at all for anyone with the
    // ambient effect off entirely - both wrong, since every monitor is meant
    // to see the identical switch regardless of ambient settings (same seed,
    // see startTransition above). Base 0.85 rather than 0.0 so a transition
    // during silence still plays at nearly full strength instead of visibly
    // dimming.
    readonly property bool transitionMusicReactive: root.opts?.musicReactive ?? true
    readonly property real transitionIntensity: root.datamoshSwitch
        ? (root.transitionMusicReactive ? 0.85 + 0.15 * AudioLevels.beat : 1.0)
        : 0
    // Shared with the classic wallpaper transitions in Background.qml - one
    // duration governs every wallpaper animation.
    readonly property int transitionDuration: Config.options?.background?.transitionDuration ?? 1200

    // Shared across monitors, so the same switch looks the same on every screen.
    readonly property real transitionSeed: TransitionSeed.seed
    readonly property real swapStart: TransitionSeed.swapStart
    readonly property real swapEnd: TransitionSeed.swapEnd

    // --- the transition's own look, separate from the ambient settings -------
    readonly property var trOpts: root.opts?.transition ?? null
    readonly property bool trRandomize: root.trOpts?.randomize ?? true
    // Drawn from the shared seed rather than Math.random(), so every monitor
    // resolves the same strengths for the same switch.
    function trValue(key, k, lo, hi) {
        if (!root.trRandomize)
            return root.trOpts?.[key] ?? hi;
        return lo + (hi - lo) * TransitionSeed.draw(k);
    }
    readonly property real trMelt: root.trValue("melt", 3, 0.55, 1.00)
    readonly property real trPoint: root.trValue("pointCloud", 11, 0.00, 0.95)
    readonly property real trSort: root.trValue("pixelSort", 17, 0.35, 1.00)
    readonly property real trBlock: root.trValue("blockCorruption", 23, 0.25, 0.90)
    readonly property real trFeedback: root.trValue("feedback", 31, 0.35, 0.95)
    readonly property real trAberration: root.trValue("chromaticAberration", 41, 0.05, 0.60)
    readonly property real trNoise: root.trValue("noise", 47, 0.10, 0.60)
    readonly property real trAxisMode: {
        if (root.hasDirection)
            return (root.transitionDirection === "up" || root.transitionDirection === "down") ? 1.0 : 0.0;
        const d = root.trOpts?.glitchDirection ?? "random";
        if (d === "horizontal")
            return 0.0;
        if (d === "vertical")
            return 1.0;
        return 2.0; // rolled per switch, in the shader, from the shared seed
    }
    // +1 = right/down, -1 = left/up. Only meaningful to the shader when
    // hasDirection is true; otherwise it forwards 1.0 and is ignored (the
    // shader falls back to its own per-switch random sign in that case).
    readonly property real trAxisSign: root.hasDirection
        ? ((root.transitionDirection === "right" || root.transitionDirection === "down") ? 1.0 : -1.0)
        : 1.0

    // 0 = showing sourceA untouched, 1 = showing sourceB untouched.
    // Starts settled so the very first wallpaper appears without a transition.
    property real transitionProgress: 1.0

    // Destruction envelope: zero at both ends, peak at the halfway point.
    // The exponent above 1 keeps the wallpaper recognisable at the start and
    // lets it come apart over the first half, instead of a plain sine's near
    // instant jump to heavy destruction - you want to watch it fall apart.
    readonly property real transition: {
        const p = Math.max(0, Math.min(1, root.transitionProgress));
        return Math.pow(Math.sin(Math.PI * p), 1.5) * root.transitionIntensity;
    }

    // The actual A -> B handover, deliberately later than the destruction peak
    // so the swap happens while the image is at its most unreadable.
    readonly property real transitionMix: {
        const p = root.transitionProgress;
        const a = root.swapStart;
        const b = Math.max(a + 0.001, root.swapEnd);
        const t = Math.max(0, Math.min(1, (p - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }

    readonly property bool transitioning: transitionAnim.running

    property NumberAnimation transitionAnim: NumberAnimation {
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: root.transitionDuration
        easing.type: Easing.Linear
    }

    function startTransition(forPath) {
        // Keyed on the incoming wallpaper so the first monitor to get here rolls
        // and the others reuse it, instead of each rolling its own.
        TransitionSeed.rollFor(forPath ?? "", root.datamoshSwitch);
        transitionAnim.restart();
    }

    /** Jump straight to "showing sourceB, no effect", e.g. on first load. */
    function settle() {
        transitionAnim.stop();
        root.transitionProgress = 1.0;
    }

    // --- resolved shader parameters -----------------------------------------
    // All from effectiveValues (this monitor's assigned preset when
    // randomizePerMonitor is on, otherwise the shared sliders) - except
    // glitchDirection just below, which stays a global toggle.
    readonly property real pointAmount: root.effectiveValues?.pointCloud ?? 0.6
    readonly property real pointSpacing: root.effectiveValues?.pointSpacing ?? 10
    readonly property real meltAmount: root.effectiveValues?.melt ?? 0.7
    readonly property real meltReach: root.effectiveValues?.meltReach ?? 0.55
    readonly property real meltWidth: root.effectiveValues?.meltWidth ?? 14
    readonly property real feedbackAmount: root.effectiveValues?.feedback ?? 0.6
    readonly property real sortAmount: root.effectiveValues?.pixelSort ?? 0.5
    readonly property real sortThreshold: root.effectiveValues?.sortThreshold ?? 0.65
    readonly property real sortLength: root.effectiveValues?.sortLength ?? 0.1
    // One axis for the whole look. "random" keeps the per-switch roll that the
    // transition already does and leaves the ambient effect vertical, since
    // paint running sideways is a choice rather than a default.
    readonly property string glitchDirection: root.opts?.glitchDirection ?? "random"
    readonly property real sortDirection: root.glitchDirection === "horizontal" ? 0.0 : 1.0
    readonly property real blockSize: root.effectiveValues?.blockSize ?? 8
    readonly property real blockAmount: root.effectiveValues?.blockCorruption ?? 0.7
    readonly property real chromaticAberration: root.effectiveValues?.chromaticAberration ?? 0.35
    readonly property real noiseAmount: root.effectiveValues?.noise ?? 0.25

    // Nothing is moving and nothing is being destroyed: the renderer can stop
    // driving frames entirely and just leave the wallpaper on screen.
    readonly property bool animating: root.transitioning || root.effectStrength > 0.0005 || root.transition > 0.0005
}
