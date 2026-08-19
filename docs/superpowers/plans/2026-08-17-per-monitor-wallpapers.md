# Per-Monitor Wallpapers + Synchronized Directional Transitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each monitor show its own wallpaper (or share one, toggle-able), with a "synchronized directional" datamosh-transition mode where each monitor's disintegration sweeps toward its neighbors and pulses with the beat.

**Architecture:** Additive Config fields with "old behavior" defaults, a new branch in `Background.qml`'s wallpaper-path resolution, geometry-driven direction computed from live Hyprland monitor state and threaded through `WallpaperEffect` -> `EffectController` -> the shader (new `trAxisSign` uniform), reusing the existing `lockWall`-style direct-Config-write pattern for per-monitor selection so no theming script is invoked.

**Tech Stack:** QML (Quickshell), GLSL (`#version 440`, compiled via `qsb`), bash (verification only, no shader-side scripting).

**Spec:** `docs/superpowers/specs/2026-08-17-per-monitor-wallpapers-design.md`

## Global Constraints

- Both new top-level Config fields (`background.wallpaperMode`, `background.effects.transitionMode`) MUST default to today's values (`"shared"`, `"independent"`) — existing users see zero behavior change until they touch the new UI.
- Per-monitor wallpaper selection MUST NOT invoke `switchwall.sh` or any theming/matugen pipeline — direct `Config.options.background.monitorWallpapers` write only, same as the existing `lockWall` pattern.
- Synchronized-directional transition logic is scoped to `wallpaperAnimation === "datamosh"` only.
- `qmllint` is confirmed non-functional in this environment (exit 255 on pristine files) — do not rely on it. Verify QML changes via `qs log -c end4-pC -t <N>` after each save, grepping for the touched file names plus `error`/`SyntaxError`/`is not defined`.
- No automated test framework exists in this codebase. "Tests" below mean: config round-trips through `~/.config/illogical-impulse/config.json`, live log inspection, and (for the shader task only) screenshots via `scripts/images/screenshot_all_monitors.sh`.

---

### Task 1: Config schema

**Files:**
- Modify: `modules/common/Config.qml` (inside the existing `background: JsonObject { ... }` block, and inside `background.effects: JsonObject { ... }`)

**Interfaces:**
- Produces: `Config.options.background.wallpaperMode` (string, `"shared"` | `"perMonitor"`, default `"shared"`), `Config.options.background.monitorWallpapers` (list of `{name: string, path: string}`, default `[]`), `Config.options.background.effects.transitionMode` (string, `"independent"` | `"synchronized"`, default `"independent"`).

- [ ] **Step 1: Add the two `background`-level fields**

In `modules/common/Config.qml`, find the existing line (already present from an earlier session):

```qml
                property string screenMode: "all"
```

That one lives inside `background.effects`. For this step, instead find `property string wallpaperPath: ""` inside the top-level `background: JsonObject { ... }` block and add directly below it:

```qml
                property string wallpaperPath: ""
                // "perMonitor" consults monitorWallpapers below; a monitor with
                // no entry there falls back to wallpaperPath so it's never blank.
                property string wallpaperMode: "shared" // "shared" | "perMonitor"
                property list<var> monitorWallpapers: [] // [{ name, path }]
```

- [ ] **Step 2: Add the `transitionMode` field under `background.effects`**

Find the existing (already-present) line inside `background.effects`:

```qml
                    property bool randomizePerMonitor: false
                    property list<var> monitorPresetAssignments: []
```

Add directly below it:

```qml
                    // "synchronized" only takes effect when wallpaperAnimation
                    // is "datamosh" - see Background.qml's transitionDirection.
                    property string transitionMode: "independent" // "independent" | "synchronized"
```

- [ ] **Step 3: Verify no reload errors**

Run: `qs log -c end4-pC -t 100 2>&1 | grep -iE "Config\.qml|error|SyntaxError"`
Expected: no output referencing `Config.qml`.

- [ ] **Step 4: Verify the new fields round-trip**

Run: `python3 -c "import json; d=json.load(open('/home/dominik/.config/illogical-impulse/config.json')); print(d['background']['wallpaperMode'], d['background']['monitorWallpapers'], d['background']['effects']['transitionMode'])"`
Expected: `shared [] independent`

- [ ] **Step 5: Commit**

```bash
git add modules/common/Config.qml
git commit -m "feat(config): add per-monitor wallpaper and synchronized-transition schema"
```

---

### Task 2: Per-monitor wallpaper resolution

**Files:**
- Modify: `modules/ii/background/Background.qml` (the `effectiveWallpaperPath` property)

**Interfaces:**
- Consumes: `Config.options.background.wallpaperMode`, `Config.options.background.monitorWallpapers` (from Task 1).
- Produces: no new public interface — `bgRoot.effectiveWallpaperPath` behavior extended in place; everything downstream (transition machinery, `onWallpaperPathChanged`) already keys off it per monitor window.

- [ ] **Step 1: Extend `effectiveWallpaperPath`**

In `modules/ii/background/Background.qml`, find:

```qml
        property string effectiveWallpaperPath: {
            if (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                return Config.options.background.lockWall;
            return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath;
        }
```

Replace with:

```qml
        property string effectiveWallpaperPath: {
            if (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                return Config.options.background.lockWall;
            if (Config.options.background.wallpaperMode === "perMonitor") {
                const override = (Config.options.background.monitorWallpapers ?? [])
                    .find(m => m.name === bgRoot.screen.name);
                if (override?.path)
                    return override.path;
            }
            return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath;
        }
```

- [ ] **Step 2: Manually seed a per-monitor override to test with**

Find your monitor names: `hyprctl monitors -j | jq -r '.[].name'`
Then (with quickshell running so the FileView picks up the external edit):

```bash
python3 - <<'EOF'
import json
p = "/home/dominik/.config/illogical-impulse/config.json"
d = json.load(open(p))
d["background"]["wallpaperMode"] = "perMonitor"
# Replace "DP-1" with one of the names from `hyprctl monitors -j`
d["background"]["monitorWallpapers"] = [{"name": "DP-1", "path": d["background"]["wallpaperPath"]}]
json.dump(d, open(p, "w"), indent=2)
EOF
```

Use a *different* image path than the current global `wallpaperPath` for the override so the difference is visually obvious.

- [ ] **Step 3: Verify in the log and visually**

Run: `qs log -c end4-pC -t 100 2>&1 | grep -iE "Background\.qml|error"`
Expected: no errors.
Then check the monitor named in Step 2 is showing the overridden image while others still show the global `wallpaperPath`.

- [ ] **Step 4: Revert the manual test edit**

```bash
python3 - <<'EOF'
import json
p = "/home/dominik/.config/illogical-impulse/config.json"
d = json.load(open(p))
d["background"]["wallpaperMode"] = "shared"
d["background"]["monitorWallpapers"] = []
json.dump(d, open(p, "w"), indent=2)
EOF
```

- [ ] **Step 5: Commit**

```bash
git add modules/ii/background/Background.qml
git commit -m "feat(background): resolve per-monitor wallpaper overrides"
```

---

### Task 3: Wallpaper selector UI (per-monitor picker)

**Files:**
- Modify: `modules/ii/wallpaperSelector/WallpaperSelectorContent.qml` (`selectWallpaperPath`)
- Modify: `modules/ii/settings/pages/AppearanceConfig.qml` (wallpaper `Carousel` section, roughly lines 115-160 as of this session)

**Interfaces:**
- Consumes: `GlobalStates.wallpaperSelectorTarget` (existing, `"wallpaper"` | `"lockWall"` today), `Wallpapers.select(filePath, darkMode, onFileSelected)` (existing, unchanged), `Config.options.background.wallpaperMode` / `monitorWallpapers` (Task 1).
- Produces: `GlobalStates.wallpaperSelectorTarget` gains a third shape, `"monitor:" + monitorName`.

- [ ] **Step 1: Add the per-monitor branch to `selectWallpaperPath`**

In `modules/ii/wallpaperSelector/WallpaperSelectorContent.qml`, find:

```qml
    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            if (GlobalStates.wallpaperSelectorTarget === "lockWall") {
                Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                    Config.options.background.lockWall = finalPath;
                    GlobalStates.wallpaperSelectorTarget = "wallpaper";
                    GlobalStates.wallpaperSelectorOpen = false;
                });
            } else {
```

Replace with:

```qml
    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            if (GlobalStates.wallpaperSelectorTarget === "lockWall") {
                Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                    Config.options.background.lockWall = finalPath;
                    GlobalStates.wallpaperSelectorTarget = "wallpaper";
                    GlobalStates.wallpaperSelectorOpen = false;
                });
            } else if (GlobalStates.wallpaperSelectorTarget.startsWith("monitor:")) {
                const monitorName = GlobalStates.wallpaperSelectorTarget.slice(8);
                Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                    const list = (Config.options.background.monitorWallpapers ?? []).slice();
                    const index = list.findIndex(m => m.name === monitorName);
                    const entry = { name: monitorName, path: finalPath };
                    if (index >= 0) list[index] = entry; else list.push(entry);
                    Config.options.background.monitorWallpapers = list;
                    GlobalStates.wallpaperSelectorTarget = "wallpaper";
                    GlobalStates.wallpaperSelectorOpen = false;
                });
            } else {
```

(The trailing `} else {` here is the pre-existing shared-wallpaper branch — leave it and everything after it untouched.)

- [ ] **Step 2: Add the "same for all monitors" switch and per-monitor carousel to `AppearanceConfig.qml`**

Find the existing `Carousel` block:

```qml
                    Carousel {
                        Layout.fillWidth: true
                        implicitHeight: 280
                        largeItemWidthRatio: 0.5
                        mediumItemWidthRatio: 0.485
                        itemSpacing: 8
                        model: [
                            page.displayPathFor(Config.options.background.wallpaperPath),
                            page.displayPathFor(
                                Config.options.background.lockWall !== ""
                                    ? Config.options.background.lockWall
                                    : Config.options.background.wallpaperPath
                            )
                        ]
                        wheelEnabled: false
                        dragEnabled: false
                        clickAction: (index, modelData) => {
                            GlobalStates.wallpaperSelectorTarget = index === 1 ? "lockWall" : "wallpaper"
                            GlobalStates.wallpaperSelectorOpen = true
                        }
                    }
```

Replace with:

```qml
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "monitor"
                        text: Translation.tr("Use same wallpaper for all monitors")
                        checked: Config.options.background.wallpaperMode === "shared"
                        onClicked: {
                            Config.options.background.wallpaperMode =
                                Config.options.background.wallpaperMode === "shared" ? "perMonitor" : "shared";
                        }
                    }

                    Carousel {
                        Layout.fillWidth: true
                        implicitHeight: 280
                        largeItemWidthRatio: 0.5
                        mediumItemWidthRatio: 0.485
                        itemSpacing: 8
                        // "Same for all": one Desktop slot + Lock screen, as before.
                        // Per-monitor: one slot per real output + Lock screen.
                        model: (Config.options.background.wallpaperMode === "shared"
                            ? [page.displayPathFor(Config.options.background.wallpaperPath)]
                            : Quickshell.screens.map(s => page.displayPathFor(
                                (Config.options.background.monitorWallpapers ?? []).find(m => m.name === s.name)?.path
                                    ?? Config.options.background.wallpaperPath
                            ))
                        ).concat([
                            page.displayPathFor(
                                Config.options.background.lockWall !== ""
                                    ? Config.options.background.lockWall
                                    : Config.options.background.wallpaperPath
                            )
                        ])
                        wheelEnabled: false
                        dragEnabled: false
                        clickAction: (index, modelData) => {
                            const lockIndex = Config.options.background.wallpaperMode === "shared"
                                ? 1 : Quickshell.screens.length;
                            if (index === lockIndex) {
                                GlobalStates.wallpaperSelectorTarget = "lockWall";
                            } else if (Config.options.background.wallpaperMode === "shared") {
                                GlobalStates.wallpaperSelectorTarget = "wallpaper";
                            } else {
                                GlobalStates.wallpaperSelectorTarget = "monitor:" + Quickshell.screens[index].name;
                            }
                            GlobalStates.wallpaperSelectorOpen = true
                        }
                    }
```

- [ ] **Step 3: Verify no reload errors**

Run: `qs log -c end4-pC -t 150 2>&1 | grep -iE "AppearanceConfig\.qml|WallpaperSelectorContent\.qml|error|is not defined"`
Expected: no output referencing either file.

- [ ] **Step 4: Manual functional check**

Open Settings > Appearance, flip "Use same wallpaper for all monitors" off — carousel should now show one thumbnail per real monitor plus Lock screen. Click one, pick an image, confirm:
- The picked monitor's thumbnail updates.
- `~/.config/illogical-impulse/config.json`'s `background.monitorWallpapers` gained/updated an entry for that monitor name (`python3 -c "import json; print(json.load(open('/home/dominik/.config/illogical-impulse/config.json'))['background']['monitorWallpapers'])"`).
- That monitor's actual desktop background changed; others didn't.

- [ ] **Step 5: Commit**

```bash
git add modules/ii/wallpaperSelector/WallpaperSelectorContent.qml modules/ii/settings/pages/AppearanceConfig.qml
git commit -m "feat(wallpaper-selector): add per-monitor wallpaper picking"
```

---

### Task 4: Direction computation + plumbing

**Files:**
- Modify: `modules/ii/background/Background.qml`
- Modify: `modules/ii/background/wallpaperEffects/WallpaperEffect.qml`
- Modify: `modules/ii/background/wallpaperEffects/EffectController.qml`

**Interfaces:**
- Consumes: `Hyprland.monitors.values` (existing, already imported in `Background.qml` via `Quickshell.Hyprland`), `Config.options.background.effects.transitionMode` (Task 1).
- Produces: `bgRoot.transitionDirection: string` (`""` | `"up"` | `"down"` | `"left"` | `"right"`), threaded as `WallpaperEffect.transitionDirection` -> `EffectController.transitionDirection` (both `property string`, default `""`).

- [ ] **Step 1: Add `transitionDirection` to `Background.qml`**

Find the existing `datamoshTransition` property:

```qml
        property bool datamoshTransition: bgRoot.wallpaperAnimation === "datamosh"
```

Add directly below it:

```qml
        // Compass direction from this monitor toward the centroid of every
        // other connected monitor, live off Hyprland's own geometry (not the
        // Settings-page snapshot) so it tracks reconnects/rearranges. Only
        // computed when synchronized mode + datamosh are both active - "" means
        // "no override, use today's per-switch random axis".
        property string transitionDirection: {
            if (Config.options.background.effects.transitionMode !== "synchronized" || !bgRoot.datamoshTransition)
                return "";
            const mine = Hyprland.monitors.values.find(m => m.name === bgRoot.screen.name);
            const others = Hyprland.monitors.values.filter(m => m.name !== bgRoot.screen.name);
            if (!mine || others.length === 0)
                return "";
            const centerOf = m => ({ x: m.x + m.width / 2, y: m.y + m.height / 2 });
            const c = centerOf(mine);
            let cx = 0, cy = 0;
            for (const m of others) {
                const oc = centerOf(m);
                cx += oc.x / others.length;
                cy += oc.y / others.length;
            }
            const dx = cx - c.x, dy = cy - c.y;
            if (Math.abs(dx) > Math.abs(dy))
                return dx > 0 ? "right" : "left";
            return dy > 0 ? "down" : "up";
        }
```

- [ ] **Step 2: Pass it to `WallpaperEffect`**

Find (added in an earlier session):

```qml
                    ambientAllowedHere: bgRoot.effectAllowedHere
                    monitorName: bgRoot.screen.name
                }
```

Replace with:

```qml
                    ambientAllowedHere: bgRoot.effectAllowedHere
                    monitorName: bgRoot.screen.name
                    transitionDirection: bgRoot.transitionDirection
                }
```

- [ ] **Step 3: Add the passthrough property to `WallpaperEffect.qml`**

Find:

```qml
    /** This monitor's name, only used for per-monitor randomization - see
     * Config...background.effects.randomizePerMonitor. */
    property string monitorName: ""

    property EffectController controller: EffectController {
        ambientAllowedHere: root.ambientAllowedHere
        monitorName: root.monitorName
    }
```

Replace with:

```qml
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
```

- [ ] **Step 4: Add the property to `EffectController.qml`**

Find:

```qml
    // Set from Background.qml - this controller's own monitor name, needed
    // only for per-monitor randomization below.
    property string monitorName: ""
```

Add directly below it:

```qml
    // Set from Background.qml's transitionDirection. "" means no override -
    // the transition keeps its existing per-switch random axis.
    property string transitionDirection: ""
```

- [ ] **Step 5: Verify no reload errors**

Run: `qs log -c end4-pC -t 100 2>&1 | grep -iE "Background\.qml|WallpaperEffect\.qml|EffectController\.qml|error"`
Expected: no output referencing any of the three files.

- [ ] **Step 6: Commit**

```bash
git add modules/ii/background/Background.qml modules/ii/background/wallpaperEffects/WallpaperEffect.qml modules/ii/background/wallpaperEffects/EffectController.qml
git commit -m "feat(effects): compute and thread per-monitor transition direction"
```

---

### Task 5: EffectController - direction override + beat-reactive transition

**Files:**
- Modify: `modules/ii/background/wallpaperEffects/EffectController.qml`

**Interfaces:**
- Consumes: `root.transitionDirection` (Task 4).
- Produces: `trAxisMode` (existing property, behavior extended), new `trAxisSign: real` property, `transitionIntensity` (existing property, behavior extended).

- [ ] **Step 1: Override `trAxisMode` when a direction is set, and add `trAxisSign`**

Find:

```qml
    // One axis for the whole look. "random" keeps the per-switch roll that the
    // transition already does and leaves the ambient effect vertical, since
    // paint running sideways is a choice rather than a default.
    readonly property string glitchDirection: root.opts?.glitchDirection ?? "random"
```

This is the *ambient* glitch direction, unrelated to the transition axis - leave it untouched. Instead find the transition's own axis resolution, near the top of the file:

```qml
    readonly property bool datamoshSwitch: root.wallpaperAnimation === "datamosh"
```

Add directly below it:

```qml
    // Synchronized mode with a computed direction overrides the transition's
    // own axis/sign entirely - see Background.qml's transitionDirection. Empty
    // string (not synchronized, or nothing to synchronize against) falls
    // straight through to today's per-switch random roll below.
    readonly property bool hasDirection: root.transitionDirection !== ""
```

Then find the existing `trAxisMode` in the "TRANSITION" section (search for `readonly property var trOpts`, it's a few lines below):

```qml
    readonly property real trAxisMode: {
        const d = root.trOpts?.glitchDirection ?? "random";
        if (d === "horizontal")
            return 0.0;
        if (d === "vertical")
            return 1.0;
        return 2.0; // rolled per switch, in the shader, from the shared seed
    }
```

Replace with:

```qml
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
```

- [ ] **Step 2: Add beat-reactivity to `transitionIntensity`**

Find:

```qml
    readonly property real transitionIntensity: root.datamoshSwitch ? 1.0 : 0
```

Replace with:

```qml
    // Reuses the ambient effect's own musicReactive toggle - no separate
    // switch for "should the transition react to music too". Base 0.85 rather
    // than 0.0 so a transition during silence still plays at nearly full
    // strength instead of visibly dimming.
    readonly property real transitionIntensity: root.datamoshSwitch
        ? (root.musicReactive ? 0.85 + 0.15 * root.beat : 1.0)
        : 0
```

- [ ] **Step 3: Verify no reload errors**

Run: `qs log -c end4-pC -t 100 2>&1 | grep -iE "EffectController\.qml|error"`
Expected: no output referencing the file.

- [ ] **Step 4: Commit**

```bash
git add modules/ii/background/wallpaperEffects/EffectController.qml
git commit -m "feat(effects): direction-driven transition axis + beat-reactive transition intensity"
```

---

### Task 6: Shader - signed transition direction

**Files:**
- Modify: `modules/ii/background/wallpaperEffects/shaders/wallpaper.frag`
- Modify: `modules/ii/background/wallpaperEffects/WallpaperRenderer.qml` (new uniform wiring)
- Run: `modules/ii/background/wallpaperEffects/shaders/build.sh` (recompiles `.frag` -> `.frag.qsb`)

**Interfaces:**
- Consumes: `root.controller.trAxisSign` (Task 5).
- Produces: shader visually flips which edge a datamosh transition originates from, without changing today's default (`trAxisSign = 1.0`, random-axis) look at all.

This is the highest-risk task in the plan - GLSL, no automated test, verified only by screenshots. Take the two sub-tasks (block/feedback sign, melt sign) one at a time and screenshot after each.

- [ ] **Step 1: Add the `trAxisSign` uniform**

In `modules/ii/background/wallpaperEffects/shaders/wallpaper.frag`, find:

```glsl
    float trAxisMode;    // 0 = X, 1 = Y, 2 = roll from the seed
```

Add directly below it:

```glsl
    float trAxisSign;    // +1 or -1, only meaningful when trAxisMode != 2
```

- [ ] **Step 2: Wire the uniform through `WallpaperRenderer.qml`**

Find:

```qml
        property real trAxisMode: root.controller?.trAxisMode ?? 2
```

Add directly below it:

```qml
        property real trAxisSign: root.controller?.trAxisSign ?? 1
```

- [ ] **Step 3: Use the sign for the block-slide / feedback-trail direction**

In `wallpaper.frag`, find:

```glsl
    float rSign    = trRand(13.3) < 0.5 ? -1.0 : 1.0;
```

Replace with:

```glsl
    // A synchronized transition (trAxisMode != 2) uses the geometry-driven
    // sign instead of a per-switch coin flip, so block/feedback motion agrees
    // with which way the melt front (below) is running.
    float rSign    = (trAxisMode > 1.5) ? (trRand(13.3) < 0.5 ? -1.0 : 1.0) : trAxisSign;
```

- [ ] **Step 4: Recompile and verify block/feedback direction only**

Run: `bash modules/ii/background/wallpaperEffects/shaders/build.sh`
Expected: `==> wallpaper.frag` with no errors.

Set synchronized mode + trigger a wallpaper switch on a two-monitor setup (side by side), screenshot with `scripts/images/screenshot_all_monitors.sh`. Block debris should visibly slide toward the shared edge between the two monitors on both screens.

- [ ] **Step 5: Mirror the melt front's origin**

In `wallpaper.frag`, find:

```glsl
            // Loud bands start higher up the screen, so the melt front traces
            // the spectrum outline across the wallpaper.
            float head = 1.0 - level * clamp(meltReach, 0.0, 1.0);
```

Replace with:

```glsl
            // Loud bands start higher up the screen, so the melt front traces
            // the spectrum outline across the wallpaper. A synchronized
            // transition with a negative sign mirrors which edge the front
            // starts from, so "up" and "left" runs the drip the other way.
            float head = (trAxisMode > 1.5 || trAxisSign > 0.0)
                ? 1.0 - level * clamp(meltReach, 0.0, 1.0)
                : level * clamp(meltReach, 0.0, 1.0);
```

Then find, a few lines below:

```glsl
            float t = (along - head) / max(len, 1e-4);
```

Replace with:

```glsl
            float t = (trAxisMode > 1.5 || trAxisSign > 0.0)
                ? (along - head) / max(len, 1e-4)
                : (head - along) / max(len, 1e-4);
```

- [ ] **Step 6: Recompile and verify melt direction**

Run: `bash modules/ii/background/wallpaperEffects/shaders/build.sh`
Expected: `==> wallpaper.frag` with no errors.

Same two-monitor screenshot check as Step 4. If the melt front runs toward the *wrong* edge (away from the neighbor instead of toward it), the sign convention is inverted - flip `EffectController.trAxisSign`'s `1.0`/`-1.0` in Task 5 Step 1 (do not change the shader again, the mapping lives in one place).

- [ ] **Step 7: Regression check against non-synchronized playback**

With `transitionMode` back to `"independent"` (the default), trigger several ordinary wallpaper switches and confirm they look exactly as before this task - random axis, random sign, no visible change. This confirms `trAxisMode > 1.5` (today's random path) still short-circuits both changed sites correctly.

- [ ] **Step 8: Commit**

```bash
git add modules/ii/background/wallpaperEffects/shaders/wallpaper.frag modules/ii/background/wallpaperEffects/shaders/wallpaper.frag.qsb modules/ii/background/wallpaperEffects/WallpaperRenderer.qml
git commit -m "feat(shader): signed transition direction for synchronized multi-monitor mode"
```

---

### Task 7: Settings toggle for transition mode

**Files:**
- Modify: `modules/ii/settings/pages/AppearanceConfig.qml`

**Interfaces:**
- Consumes: `Config.options.background.effects.transitionMode` (Task 1).

- [ ] **Step 1: Add the switch next to the existing Transitions dropdown**

Find (in the "Shader effects"-adjacent wallpaper-transition controls, near the existing `wallpaperAnimation` `ConfigComboBox` labeled "Transitions"):

```qml
                ConfigSpinBox {
                    icon: "schedule"
                    text: Translation.tr("Transition duration (ms)")
                    enabled: Config.options.background.wallpaperAnimation !== ""
                    value: Config.options.background.transitionDuration
                    from: 100
                    to: 5000
                    stepSize: 50
                    onValueChanged: {
                        Config.options.background.transitionDuration = value;
                    }
                }
            }
```

Replace the closing `}` of that `GroupedList` with one more control added before it:

```qml
                ConfigSpinBox {
                    icon: "schedule"
                    text: Translation.tr("Transition duration (ms)")
                    enabled: Config.options.background.wallpaperAnimation !== ""
                    value: Config.options.background.transitionDuration
                    from: 100
                    to: 5000
                    stepSize: 50
                    onValueChanged: {
                        Config.options.background.transitionDuration = value;
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "sync_alt"
                    text: Translation.tr("Synchronize direction across monitors")
                    // Only meaningful for the datamosh switch transition - the
                    // classic shuffle transitions have no per-monitor character.
                    enabled: Config.options.background.wallpaperAnimation === "datamosh"
                    checked: Config.options.background.effects.transitionMode === "synchronized"
                    onClicked: {
                        Config.options.background.effects.transitionMode =
                            Config.options.background.effects.transitionMode === "synchronized" ? "independent" : "synchronized";
                    }
                }
            }
```

- [ ] **Step 2: Verify no reload errors**

Run: `qs log -c end4-pC -t 100 2>&1 | grep -iE "AppearanceConfig\.qml|error"`
Expected: no output referencing the file.

- [ ] **Step 3: End-to-end manual check**

With two or more monitors: set both to per-monitor wallpapers (different images), set Transitions to "Datamosh", flip "Synchronize direction across monitors" on, then change one monitor's wallpaper. Confirm the transition sweeps toward the other monitor's physical position, and that switching a third time with music playing shows a visibly beat-pulsing intensity.

- [ ] **Step 4: Commit**

```bash
git add modules/ii/settings/pages/AppearanceConfig.qml
git commit -m "feat(settings): add synchronized-direction transition toggle"
```
