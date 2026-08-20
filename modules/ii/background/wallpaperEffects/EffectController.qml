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
    // Set by WallpaperEffect when this screen has a physical neighbour whose
    // wallpaper texture can be sampled locally. Keeps the cross-monitor seam
    // from requesting frames on isolated monitors.
    property bool neighborAvailable: false

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
    // A datamosh transition is allowed to use live audio even when the
    // continuous ambient effect is disabled. Otherwise a transition's own
    // beat scalar changes slightly, but the seam and its spectrum/melt field
    // remain frozen at zero unless the user also enables ambient animation.
    readonly property bool transitionMusicReactive: root.opts?.musicReactive ?? true
    readonly property bool transitionAudioActive: root.datamoshSwitch
        && root.transitionMusicReactive && root.transitionProgress < 0.999
    readonly property bool neighborBleed: (root.opts?.neighborBleed ?? false) && root.neighborAvailable
    readonly property bool neighborBleedMusicReactive: root.opts?.neighborBleedMusicReactive ?? true
    // The receiving monitor can be excluded by "Show on" while the primary
    // still drives its seam. This is deliberately gated by the global ambient
    // toggle, not `musicReactive` (which also includes this monitor's local
    // screen filter), so only the bridge extends the primary effect outward.
    readonly property bool neighborBleedAudioActive: root.neighborBleed
        && root.neighborBleedMusicReactive && (root.opts?.enable ?? false)
        && (root.opts?.musicReactive ?? true)
    readonly property real neighborBleedWidth: root.opts?.neighborBleedWidth ?? 0.16
    readonly property real neighborBleedStrength: root.opts?.neighborBleedStrength ?? 0.9
    readonly property real neighborBleedFragmentThreshold: root.opts?.neighborBleedFragmentThreshold ?? 0.08
    readonly property real neighborBleedFragmentSoftness: root.opts?.neighborBleedFragmentSoftness ?? 0.24
    readonly property bool neighborBleedColorTrails: root.opts?.neighborBleedColorTrails ?? true
    readonly property real neighborBleedColorThreshold: root.opts?.neighborBleedColorThreshold ?? 0.12
    readonly property real neighborBleedColorSoftness: root.opts?.neighborBleedColorSoftness ?? 0.20
    readonly property real neighborBleedColorStrength: root.opts?.neighborBleedColorStrength ?? 0.7
    readonly property bool neighborBleedLidar: root.opts?.neighborBleedLidar ?? false
    readonly property bool neighborBleedLidarOutlines: (root.opts?.neighborBleedLidarMode ?? "scan") === "outlines"
    readonly property real neighborBleedLidarStrength: root.opts?.neighborBleedLidarStrength ?? 0.55
    readonly property real neighborBleedLidarDensity: root.opts?.neighborBleedLidarDensity ?? 24
    readonly property real neighborBleedLidarSpeed: root.opts?.neighborBleedLidarSpeed ?? 0.75
    // LiDAR is no longer a seam-only feature. It follows the same master
    // enable/show-on scope as the local wallpaper effects and keeps a render
    // tick alive for its scan and audio pulse even at a silent idle.
    readonly property bool lidarEnabled: root.ambientEnabled && root.neighborBleedLidar
    readonly property real neighborBleedEdgeSoftness: root.opts?.neighborBleedEdgeSoftness ?? 0.32
    readonly property real neighborBleedRaggedness: root.opts?.neighborBleedRaggedness ?? 1.0
    readonly property real neighborBleedGrain: root.opts?.neighborBleedGrain ?? 1.0
    readonly property real neighborBleedMotionSpeed: root.opts?.neighborBleedMotionSpeed ?? 1.0
    readonly property real neighborBleedFeedback: root.opts?.neighborBleedFeedback ?? 1.0
    readonly property bool neighborBleedBattle: root.opts?.neighborBleedBattle ?? true
    readonly property real neighborBleedBattleStrength: root.opts?.neighborBleedBattleStrength ?? 1.0
    readonly property real neighborBleedPrimaryPush: root.opts?.neighborBleedPrimaryPush ?? 1.0
    readonly property real neighborBleedSecondaryResistance: root.opts?.neighborBleedSecondaryResistance ?? 1.0
    readonly property real musicIntensity: root.ambientEnabled ? (root.effectiveValues?.musicIntensity ?? 0.35) : 0
    readonly property real beatIntensity: root.effectiveValues?.beatIntensity ?? 0.75
    // Audio routes deliberately stay global rather than joining the visual
    // presets: a monitor can use a different look without silently changing
    // which musical event drives it. Numeric values keep the shader compact.
    function triggerFor(key) {
        switch (root.opts?.audioRouting?.[key] ?? "auto") {
        case "volume": return 1.0;
        case "beat": return 2.0;
        case "bass": return 3.0;
        case "mid": return 4.0;
        case "treble": return 5.0;
        default: return 0.0; // Auto: preserve the tuned legacy mix.
        }
    }
    readonly property real meltTrigger: root.triggerFor("melt")
    readonly property real pointTrigger: root.triggerFor("pointCloud")
    readonly property real feedbackTrigger: root.triggerFor("feedback")
    readonly property real sortTrigger: root.triggerFor("pixelSort")
    readonly property real blockTrigger: root.triggerFor("blockCorruption")
    readonly property real aberrationTrigger: root.triggerFor("chromaticAberration")
    readonly property real noiseTrigger: root.triggerFor("noise")
    readonly property real lidarTrigger: root.triggerFor("lidar")

    readonly property real bass: root.musicReactive || root.transitionAudioActive || root.neighborBleedAudioActive ? AudioLevels.bass : 0
    readonly property real mid: root.musicReactive || root.transitionAudioActive || root.neighborBleedAudioActive ? AudioLevels.mid : 0
    readonly property real treble: root.musicReactive || root.transitionAudioActive || root.neighborBleedAudioActive ? AudioLevels.treble : 0
    readonly property real volume: root.musicReactive || root.transitionAudioActive || root.neighborBleedAudioActive ? AudioLevels.volume : 0
    readonly property real beat: root.musicReactive || root.transitionAudioActive || root.neighborBleedAudioActive ? AudioLevels.beat : 0
    // The spectrum the melt front traces. Empty when not reacting to music, in
    // which case a transition supplies its own curve.
    readonly property var spectrum: root.musicReactive || root.transitionAudioActive || root.neighborBleedAudioActive ? AudioLevels.points : []

    // The states take over from each other rather than stacking, so a kick
    // peaks at exactly beatIntensity and stays clearly below a transition at
    // transitionIntensity - summing them instead put every kick at ~1.0.
    // AudioLevels.beat is already a 1 -> 0 envelope, so no second decay here.
    //
    // There is no idle floor: with nothing playing this is 0, the wallpaper is
    // a still image and the renderer stops requesting frames entirely.
    function effectStrengthFor(values, allowed) {
        if (!(root.opts?.enable ?? false) || !allowed || !(root.opts?.musicReactive ?? true))
            return 0;
        return Math.max(AudioLevels.volume * (values?.musicIntensity ?? 0.35),
            AudioLevels.beat * (values?.beatIntensity ?? 0.75));
    }
    readonly property real effectStrength: root.effectStrengthFor(root.effectiveValues,
        root.ambientAllowedHere)
    // Kept separate from effectStrength: the latter must stay zero on a
    // secondary monitor excluded by "Show on", while this one wakes only its
    // cross-monitor seam with the same volume/beat envelope as the primary.
    readonly property real neighborBleedEffectStrength: root.neighborBleedAudioActive
        ? Math.max(root.volume * (root.effectiveValues?.musicIntensity ?? 0.35), root.beat * root.beatIntensity)
        : 0
    // Render the seam only while a live audio envelope exists. With no signal,
    // its frame clock stops and the receiver stays completely untouched.
    readonly property bool neighborBleedAnimating: root.neighborBleed
        && root.neighborBleedEffectStrength > 0.0005

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
    function transitionAxisModeFor(direction) {
        if (direction !== "")
            return (direction === "up" || direction === "down") ? 1.0 : 0.0;
        const d = root.trOpts?.glitchDirection ?? "random";
        if (d === "horizontal")
            return 0.0;
        if (d === "vertical")
            return 1.0;
        return 2.0; // rolled per switch, in the shader, from the shared seed
    }
    readonly property real trAxisMode: root.transitionAxisModeFor(root.transitionDirection)
    // +1 = right/down, -1 = left/up. Only meaningful to the shader when
    // hasDirection is true; otherwise it forwards 1.0 and is ignored (the
    // shader falls back to its own per-switch random sign in that case).
    function transitionAxisSignFor(direction) {
        return direction !== "" && direction !== "right" && direction !== "down" ? -1.0 : 1.0;
    }
    readonly property real trAxisSign: root.transitionAxisSignFor(root.transitionDirection)

    // 0 = showing sourceA untouched, 1 = showing sourceB untouched. Each
    // controller joins one shared generation instead of running its own timer;
    // otherwise differently cached monitor textures start at different times.
    property int transitionGeneration: 0
    readonly property bool sharesTransition: root.transitionGeneration !== 0
        && root.transitionGeneration === TransitionSeed.generation
        && TransitionSeed.transitioning
    readonly property real transitionProgress: root.sharesTransition
        ? TransitionSeed.transitionProgress : 1.0

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

    readonly property bool transitioning: root.sharesTransition

    function startTransition(forPath) {
        // The singleton stages every monitor's uploaded images, then advances
        // one common clock for both local wallpapers and seam extensions.
        root.transitionGeneration = TransitionSeed.startTransition(
            forPath ?? "", root.transitionDuration, root.datamoshSwitch);
    }

    /** Jump straight to "showing sourceB, no effect", e.g. on first load. */
    function settle() {
        root.transitionGeneration = 0;
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
        || root.neighborBleedAnimating || root.lidarEnabled
}
