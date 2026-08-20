pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell

/**
 * Look presets for the wallpaper effect.
 *
 * Applying one writes its values straight into `background.effects`, so the
 * sliders always show what is actually running - there is no hidden override
 * layer. "Custom" is not stored anywhere either: `currentName()` compares the
 * live values against each preset, so nudging any slider makes the dropdown
 * read Custom on its own instead of keeping a stale label.
 *
 * Deliberately scoped to the look and the intensities. Two things are left out
 * on purpose:
 *
 *  - `effects.audio` is the analysis tuning for *every* visualiser in the shell,
 *    so a wallpaper preset has no business rewriting it.
 *  - `glitchDirection` is an orientation, not a look. Including it meant picking
 *    a direction knocked the dropdown to Custom, and applying a preset silently
 *    reoriented the whole effect. It is now independent of presets in both
 *    directions.
 */
Singleton {
    id: root

    readonly property var presets: ({
        dnb: {
            label: "DnB",
            icon: "bolt",
            values: {
                pointCloud: 0.45,
                pointSpacing: 12,
                musicIntensity: 0.22,
                beatIntensity: 0.65,
                melt: 0.55,
                meltReach: 0.55,
                meltWidth: 16,
                feedback: 0.30,
                pixelSort: 0.35,
                sortThreshold: 0.65,
                sortLength: 0.12,
                blockSize: 10,
                blockCorruption: 0.45,
                chromaticAberration: 0.30,
                noise: 0.15
            }
        },
        lofi: {
            // Tape rather than digital: heavy persistence for the smear, wide
            // soft runs, strong colour bleed, visible grain. Pair it with a
            // horizontal glitch direction for the full scanline look - that is
            // a separate setting, deliberately not part of the preset.
            label: "Lofi / VHS",
            icon: "videocam",
            values: {
                pointCloud: 0.12,
                pointSpacing: 20,
                musicIntensity: 0.25,
                beatIntensity: 0.25,
                melt: 0.32,
                meltReach: 0.32,
                meltWidth: 26,
                feedback: 0.55,
                pixelSort: 0.18,
                sortThreshold: 0.75,
                sortLength: 0.16,
                blockSize: 6,
                blockCorruption: 0.12,
                chromaticAberration: 0.42,
                noise: 0.32
            }
        },
        cyberpunk: {
            // Hard digital failure: coarse blocks, maximum corruption, sharp
            // RGB split, almost no melt.
            label: "Cyberpunk",
            icon: "electric_bolt",
            values: {
                pointCloud: 0.50,
                pointSpacing: 9,
                musicIntensity: 0.25,
                beatIntensity: 0.65,
                melt: 0.12,
                meltReach: 0.30,
                meltWidth: 12,
                feedback: 0.25,
                pixelSort: 0.45,
                sortThreshold: 0.60,
                sortLength: 0.08,
                blockSize: 18,
                blockCorruption: 0.55,
                chromaticAberration: 0.55,
                noise: 0.18
            }
        },
        paint: {
            // Shows off the melt on its own - everything that competes with the
            // paint runs is turned down or off.
            label: "Paint drip",
            icon: "water_drop",
            values: {
                pointCloud: 0.02,
                pointSpacing: 16,
                musicIntensity: 0.28,
                beatIntensity: 0.50,
                melt: 0.75,
                meltReach: 0.70,
                meltWidth: 22,
                feedback: 0.25,
                pixelSort: 0.05,
                sortThreshold: 0.82,
                sortLength: 0.12,
                blockSize: 10,
                blockCorruption: 0.03,
                chromaticAberration: 0.08,
                noise: 0.03
            }
        },
        ambient: {
            // Barely there. For when you want the wallpaper to breathe with the
            // music without ever being the thing you look at.
            label: "Ambient",
            icon: "spa",
            values: {
                pointCloud: 0.15,
                pointSpacing: 24,
                musicIntensity: 0.12,
                beatIntensity: 0.18,
                melt: 0.16,
                meltReach: 0.18,
                meltWidth: 30,
                feedback: 0.28,
                pixelSort: 0.06,
                sortThreshold: 0.80,
                sortLength: 0.15,
                blockSize: 8,
                blockCorruption: 0.04,
                chromaticAberration: 0.10,
                noise: 0.04
            }
        }
    })

    readonly property var order: ["dnb", "lofi", "cyberpunk", "paint", "ambient"]

    // The 14 ambient-effect keys every preset (built-in or custom) carries -
    // taken from an existing preset rather than duplicated, so adding a key
    // to one built-in automatically extends what saveCurrentAs() captures.
    readonly property var presetKeys: Object.keys(root.presets.dnb.values)

    // User-saved presets live in Config, not here, so they persist and sync
    // like everything else - this singleton only ever reads/writes them
    // through Config.options.
    readonly property var customPresets: Config.options?.background?.customEffectPresets ?? []

    function _customIndex(name) {
        return root.customPresets.findIndex(p => p.name === name);
    }

    // --- per-monitor randomization (Config.options.background.effects.randomizePerMonitor) ---

    readonly property var monitorAssignments: Config.options?.background?.effects?.monitorPresetAssignments ?? []

    function _allPresetKeys() {
        return root.order.concat(root.customPresets.map(p => "custom:" + p.name));
    }

    function _assignmentFor(monitorName) {
        return root.monitorAssignments.find(a => a.name === monitorName);
    }

    /** The look assigned to a monitor, or null if it has none yet - call
     * ensureAssigned() first to guarantee one. Pure lookup, no side effects. */
    function valuesForMonitor(monitorName) {
        const assignment = root._assignmentFor(monitorName);
        const preset = assignment ? root._resolve(assignment.preset) : null;
        return preset ? preset.values : null;
    }

    /** Rolls and persists a new random look for one monitor - both the
     * initial pick and what the Settings "Reroll" button calls. */
    function reroll(monitorName) {
        const keys = root._allPresetKeys();
        if (!monitorName || keys.length === 0)
            return;
        const pick = keys[Math.floor(Math.random() * keys.length)];
        const list = root.monitorAssignments.slice();
        const index = list.findIndex(a => a.name === monitorName);
        const entry = { name: monitorName, preset: pick };
        if (index >= 0)
            list[index] = entry;
        else
            list.push(entry);
        Config.options.background.effects.monitorPresetAssignments = list;
    }

    /** Picks a look for a monitor only if it doesn't already have a valid one
     * (none yet, or its preset was since deleted) - safe to call every time a
     * monitor's controller activates, it only ever writes once per monitor. */
    function ensureAssigned(monitorName) {
        if (!monitorName)
            return;
        const assignment = root._assignmentFor(monitorName);
        if (assignment && root._resolve(assignment.preset))
            return;
        root.reroll(monitorName);
    }

    function rerollAll() {
        for (const screen of Quickshell.screens)
            root.reroll(screen.name);
    }

    /** Snapshot the live slider values into a named, saved preset. Saving
     * again under a name that already exists overwrites it in place instead
     * of piling up duplicates. */
    function saveCurrentAs(name) {
        const trimmed = (name ?? "").trim();
        if (trimmed.length === 0)
            return;
        const target = Config.options?.background?.effects;
        if (!target)
            return;

        const values = {};
        for (const key of root.presetKeys)
            values[key] = target[key];

        const list = root.customPresets.slice();
        const index = root._customIndex(trimmed);
        const entry = { name: trimmed, values };
        if (index >= 0)
            list[index] = entry;
        else
            list.push(entry);
        Config.options.background.customEffectPresets = list;
    }

    function deleteCustom(name) {
        const index = root._customIndex(name);
        if (index < 0)
            return;
        const list = root.customPresets.slice();
        list.splice(index, 1);
        Config.options.background.customEffectPresets = list;
    }

    function apply(name) {
        const preset = root._resolve(name);
        if (!preset)
            return;
        const target = Config.options?.background?.effects;
        if (!target)
            return;
        const v = preset.values;
        for (const key in v)
            target[key] = v[key];
        // Built-ins are safe starting points. A custom preset is an explicit
        // user choice, so it keeps the current seam character intact.
        if (root.presets[name])
            SeamPresets.calmCurrent();
    }

    /** Looks up a preset (built-in or "custom:<name>") by its combo-box key. */
    function _resolve(key) {
        if (root.presets[key])
            return root.presets[key];
        if (key?.startsWith("custom:")) {
            const entry = root.customPresets[root._customIndex(key.slice(7))];
            if (entry)
                return { label: entry.name, icon: "bookmark", values: entry.values };
        }
        return null;
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

    /** Combo-box key whose values the config currently matches, or "custom". */
    function currentName() {
        if (!Config.options?.background?.effects)
            return "custom";
        for (const name of root.order) {
            if (root._matches(root.presets[name].values))
                return name;
        }
        for (const entry of root.customPresets) {
            if (root._matches(entry.values))
                return "custom:" + entry.name;
        }
        return "custom";
    }

    /** Model for a ConfigComboBox: Custom, then built-ins, then user presets. */
    function comboModel() {
        const out = [
            {
                displayName: "Custom",
                icon: "tune",
                value: "custom"
            }
        ];
        for (const name of root.order) {
            out.push({
                displayName: root.presets[name].label,
                icon: root.presets[name].icon,
                value: name
            });
        }
        for (const entry of root.customPresets) {
            out.push({
                displayName: entry.name,
                icon: "bookmark",
                value: "custom:" + entry.name
            });
        }
        return out;
    }
}
