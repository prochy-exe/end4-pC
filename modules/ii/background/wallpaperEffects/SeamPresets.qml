pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell

/**
 * Ready-made configurations for the cross-monitor seam. These affect only
 * seam controls; the primary wallpaper's regular shader preset stays intact.
 */
Singleton {
    id: root

    readonly property var presets: ({
        balanced: {
            label: "Balanced",
            icon: "tune",
            values: {
                neighborBleed: true,
                neighborBleedMusicReactive: true,
                neighborBleedWidth: 0.12,
                neighborBleedStrength: 0.6,
                neighborBleedFragmentThreshold: 0.18,
                neighborBleedFragmentSoftness: 0.22,
                neighborBleedColorTrails: true,
                neighborBleedColorThreshold: 0.18,
                neighborBleedColorSoftness: 0.18,
                neighborBleedColorStrength: 0.45,
                neighborBleedEdgeSoftness: 0.38,
                neighborBleedRaggedness: 0.50,
                neighborBleedGrain: 0.80,
                neighborBleedMotionSpeed: 0.60,
                neighborBleedFeedback: 0.35,
                neighborBleedBattle: false,
                neighborBleedBattleStrength: 0.0,
                neighborBleedPrimaryPush: 1.0,
                neighborBleedSecondaryResistance: 1.0
            }
        },
        colourTrails: {
            // A visible RGB-fragment setup that remains localized, letting
            // only coloured, distorted details travel across the seam.
            label: "Colour trails",
            icon: "gradient",
            values: {
                neighborBleed: true,
                neighborBleedMusicReactive: true,
                neighborBleedWidth: 0.38,
                neighborBleedStrength: 0.65,
                neighborBleedFragmentThreshold: 0.12,
                neighborBleedFragmentSoftness: 0.18,
                neighborBleedColorTrails: true,
                neighborBleedColorThreshold: 0.12,
                neighborBleedColorSoftness: 0.16,
                neighborBleedColorStrength: 0.60,
                neighborBleedEdgeSoftness: 0.32,
                neighborBleedRaggedness: 0.60,
                neighborBleedGrain: 0.70,
                neighborBleedMotionSpeed: 0.85,
                neighborBleedFeedback: 0.30,
                neighborBleedBattle: false,
                neighborBleedBattleStrength: 0.0,
                neighborBleedPrimaryPush: 1.0,
                neighborBleedSecondaryResistance: 1.0
            }
        },
        fragmentFight: {
            label: "Fragment fight",
            icon: "sports_martial_arts",
            values: {
                neighborBleed: true,
                neighborBleedMusicReactive: true,
                neighborBleedWidth: 0.20,
                neighborBleedStrength: 0.75,
                neighborBleedFragmentThreshold: 0.12,
                neighborBleedFragmentSoftness: 0.18,
                neighborBleedColorTrails: true,
                neighborBleedColorThreshold: 0.10,
                neighborBleedColorSoftness: 0.16,
                neighborBleedColorStrength: 0.55,
                neighborBleedEdgeSoftness: 0.30,
                neighborBleedRaggedness: 0.75,
                neighborBleedGrain: 0.90,
                neighborBleedMotionSpeed: 0.80,
                neighborBleedFeedback: 0.35,
                neighborBleedBattle: true,
                neighborBleedBattleStrength: 0.65,
                neighborBleedPrimaryPush: 0.90,
                neighborBleedSecondaryResistance: 0.85
            }
        },
        overdrive: {
            // The original full-screen colour-feedback recipe. It is kept as
            // a deliberate opt-in, not as the baseline for normal presets.
            label: "Overdrive trails",
            icon: "local_fire_department",
            values: {
                neighborBleed: true,
                neighborBleedMusicReactive: true,
                neighborBleedWidth: 1.0,
                neighborBleedStrength: 1.0,
                neighborBleedFragmentThreshold: 0.01,
                neighborBleedFragmentSoftness: 0.08,
                neighborBleedColorTrails: true,
                neighborBleedColorThreshold: 0.015,
                neighborBleedColorSoftness: 0.06,
                neighborBleedColorStrength: 1.0,
                neighborBleedEdgeSoftness: 0.18,
                neighborBleedRaggedness: 0.75,
                neighborBleedGrain: 0.50,
                neighborBleedMotionSpeed: 1.25,
                neighborBleedFeedback: 1.0,
                neighborBleedBattle: false,
                neighborBleedBattleStrength: 0.0,
                neighborBleedPrimaryPush: 1.0,
                neighborBleedSecondaryResistance: 1.0
            }
        }
    })

    readonly property var order: ["balanced", "colourTrails", "fragmentFight", "overdrive"]

    function apply(name) {
        const preset = root.presets[name];
        const target = Config.options?.background?.effects;
        if (!preset || !target)
            return;
        for (const key in preset.values)
            target[key] = preset.values[key];
    }

    // Wallpaper look presets should not inherit a previously extreme seam.
    // Preserve whether the user enabled the seam and its flow direction, but
    // return its modifiers to the restrained balanced profile.
    function calmCurrent() {
        const target = Config.options?.background?.effects;
        if (!target?.neighborBleed)
            return;
        const safeValues = root.presets.balanced.values;
        for (const key in safeValues) {
            if (key !== "neighborBleed" && key !== "neighborBleedMode")
                target[key] = safeValues[key];
        }
    }

    function _matches(values) {
        const target = Config.options?.background?.effects;
        if (!target)
            return false;
        for (const key in values) {
            const want = values[key];
            const have = target[key];
            if (typeof want === "number") {
                if (Math.abs((have ?? 0) - want) > 0.005)
                    return false;
            } else if (have !== want) {
                return false;
            }
        }
        return true;
    }

    function currentName() {
        for (const name of root.order) {
            if (root._matches(root.presets[name].values))
                return name;
        }
        return "custom";
    }

    function comboModel() {
        const out = [{ displayName: "Custom", icon: "tune", value: "custom" }];
        for (const name of root.order) {
            out.push({
                displayName: root.presets[name].label,
                icon: root.presets[name].icon,
                value: name
            });
        }
        return out;
    }
}
