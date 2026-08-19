# Per-monitor wallpapers with synchronized directional transitions

Status: approved design, not yet planned/implemented.

## Goal

Let each monitor show its own wallpaper (or share one, toggle-able), and make
the datamosh switch transition feel coordinated across monitors: either
independent (today's behavior) or "synchronized directional," where each
monitor's disintegration visually sweeps toward wherever its neighbors sit,
and pulses with the beat.

## Explicit non-goals (this spec)

- **Per-monitor or mixed color theming.** `switchwall.sh` drives one global
  Material You theme (bar, sidebar, GTK/Qt, terminal). Which wallpaper feeds
  that theme, and whether two wallpapers' palettes can be blended, is a
  separate fast-follow spec once this one ships. Until then, theming keeps
  following whatever `Config.options.background.wallpaperPath` (the "shared"
  path/global picker) currently holds, unchanged from today.
- **True cross-monitor pixel bleed.** Not possible under Wayland - each
  monitor's background is a separate `wlr-layer-shell` surface bound to one
  output; no client can paint pixels onto a different output's surface.
  "Synchronized directional" is the closest achievable approximation:
  coordinated timing/seed + a shared sense of motion, not shared pixels.
- **Per-monitor auto-rotation.** The existing wallpaper-change-interval timer
  keeps working exactly as today, against the shared wallpaper only. Per-monitor
  wallpapers are set manually via the picker for now.

## 1. Data model (`modules/common/Config.qml`)

Under `background` (siblings of the existing `wallpaperPath`):

```
property string wallpaperMode: "shared"       // "shared" | "perMonitor"
property list<var> monitorWallpapers: []       // [{ name: <monitor name>, path: <string> }]
```

Under `background.effects` (sibling of the existing `randomizePerMonitor`):

```
property string transitionMode: "independent"  // "independent" | "synchronized"
```

Both new top-level fields default to today's behavior (`"shared"` /
`"independent"`), so nothing changes for anyone who doesn't touch the new UI.

## 2. Wallpaper selection UI

**`AppearanceConfig.qml`** - the existing wallpaper `Carousel` (currently two
items: Desktop, Lock screen) gains a `ConfigSwitch` right above it, "Use same
wallpaper for all monitors" (`Config.options.background.wallpaperMode ===
"shared"`, mirroring the exact pattern the existing `syncWallpaperSwitch` for
`lockWall` already uses just above it).

- **On** (`wallpaperMode = "shared"`): carousel unchanged from today - one
  "Desktop" thumbnail (from `wallpaperPath`) + "Lock screen".
- **Off** (`wallpaperMode = "perMonitor"`): the "Desktop" slot is replaced by
  one thumbnail per `Quickshell.screens` entry (from
  `monitorWallpapers.find(m => m.name === screen.name)?.path`, falling back to
  `wallpaperPath` if that monitor has no override yet so it's never blank).
  "Lock screen" stays a single shared slot - locking isn't a per-monitor
  concept here.

**`WallpaperSelectorContent.qml`** - `selectWallpaperPath()` already branches
on `GlobalStates.wallpaperSelectorTarget` (`"wallpaper"` today applies through
the full theming pipeline; `"lockWall"` writes `Config.options.background.lockWall`
directly, bypassing it). Add a third branch:

```js
} else if (GlobalStates.wallpaperSelectorTarget.startsWith("monitor:")) {
    const name = GlobalStates.wallpaperSelectorTarget.slice(7);
    Wallpapers.select(filePath, root.useDarkMode, finalPath => {
        const list = (Config.options.background.monitorWallpapers ?? []).slice();
        const index = list.findIndex(m => m.name === name);
        const entry = { name, path: finalPath };
        if (index >= 0) list[index] = entry; else list.push(entry);
        Config.options.background.monitorWallpapers = list;
        GlobalStates.wallpaperSelectorTarget = "wallpaper";
        GlobalStates.wallpaperSelectorOpen = false;
    });
}
```

Same shape as the existing `lockWall` branch - direct Config write via
`Wallpapers.select`'s `onFileSelected` callback, no theming script invoked.
Clicking a per-monitor carousel thumbnail sets
`GlobalStates.wallpaperSelectorTarget = "monitor:" + screenName` before
opening the selector, same as the existing Desktop/Lock click handler does.

## 3. Wallpaper resolution (`modules/ii/background/Background.qml`)

`bgRoot.effectiveWallpaperPath` gains one branch, checked after the existing
`lockWall` (lock screen still wins) and before the shared-path fallback:

```js
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

Everything downstream (the transition machinery, `onWallpaperPathChanged`,
etc.) already keys off `wallpaperPath`/`effectiveWallpaperPath` per monitor
window, so per-monitor images fall out of this one change with no further
plumbing - each `bgRoot` instance already runs its own independent
transition today (that's how the existing classic-shader transitions already
work, each window rolling its own pick from `shaderList`).

## 4. Synchronized directional transition

Scoped to `wallpaperAnimation === "datamosh"` only - the classic shader
transitions have no per-monitor "character" (melt/block/point params) to
synchronize in the first place.

### 4a. Direction (`Background.qml`)

New property on `bgRoot`, computed from live Hyprland monitor geometry (not
`MonitorConfigOption`'s one-shot fetch, so it tracks reconnects/rearranges):

```js
property string transitionDirection: {
    if (Config.options.background.effects.transitionMode !== "synchronized")
        return "";
    const mine = Hyprland.monitors.values.find(m => m.name === bgRoot.screen.name);
    const others = Hyprland.monitors.values.filter(m => m.name !== bgRoot.screen.name);
    if (!mine || others.length === 0)
        return "";
    const centerOf = m => ({ x: m.x + m.width / 2, y: m.y + m.height / 2 });
    const c = centerOf(mine);
    const centroid = others.reduce((acc, m) => {
        const oc = centerOf(m);
        return { x: acc.x + oc.x / others.length, y: acc.y + oc.y / others.length };
    }, { x: 0, y: 0 });
    const dx = centroid.x - c.x, dy = centroid.y - c.y;
    return Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up");
}
```

Works for any monitor count/arrangement: it always reduces to "which compass
direction is most toward the rest of the group," recomputed live if monitors
change. Passed down `Background.qml` -> `WallpaperEffect.transitionDirection`
-> `EffectController.transitionDirection`, same plumbing already used for
`ambientAllowedHere`/`monitorName`.

### 4b. Shader (`wallpaperEffects/shaders/wallpaper.frag`)

Today `trAxisMode` (0=X axis, 1=Y axis, 2=roll from the per-switch seed)
picks an *axis* but every direction-dependent term (melt head origin, block
slide vector, point drift vector) currently assumes a fixed, unsigned sense
along that axis. This is the one part of the feature with real risk: giving
the disintegration an actual up-vs-down / left-vs-right *polarity* means
tracing `sortDir`/`trDir`/`acrossDir` through every place they're used and
threading a sign through consistently, then recompiling via
`shaders/build.sh`.

Plan: add a `trAxisSign: float` uniform (default `1.0`). `EffectController`
sets it from `transitionDirection` (`"down"`/`"right"` -> `1.0`,
`"up"`/`"left"` -> `-1.0`, empty -> `1.0`, no behavior change when not
synchronized) and forces `trAxisMode` to `0` or `1` (never the random roll)
whenever a direction is set. The exact sign-to-visual-direction mapping
("does +1 on the Y axis read as *down* in this shader's UV space") gets
confirmed empirically: implement, then verify with
`scripts/images/screenshot_all_monitors.sh` against a real multi-monitor
arrangement, flip the sign if the sweep reads backwards. This is a tuning
step, not an open design question - the requirement (sweep visually goes
toward the neighbor) is unambiguous either way.

### 4c. Multi-monitor timing

When several monitors change wallpaper at the same moment (e.g. picking
"same for all" while in synchronized mode), `TransitionSeed.rollFor` already
keys its shared roll by the incoming path, so simultaneous switches to the
same image already share one seed/timing today - no change needed there,
only the axis/sign override above is new. When monitors change at different
times (the normal per-monitor manual-pick case), each just uses its own
computed direction independently; there's nothing to time-synchronize against
since nothing else is transitioning at that moment.

## 5. Beat-reactive transition (`EffectController.qml`)

No new toggle - reuses `effects.musicReactive` (already gates the ambient
effect's audio reactivity). Today `transitionIntensity` is a flat `1.0`
whenever `datamoshSwitch` is true. Add an audio-driven pulse on top, gated the
same way `musicReactive` already gates `bass`/`mid`/`treble`/`volume`/`beat`:

```js
readonly property real transitionIntensity: root.datamoshSwitch
    ? (root.musicReactive ? 0.85 + 0.15 * root.beat : 1.0)
    : 0
```

Exact weighting (`0.85 base + 0.15 * beat` above) is a starting point to tune
by feel during implementation, same as every other intensity curve in this
shader already is (see the existing beat-weighting comments throughout
`wallpaper.frag`) - not a separate design decision, just a number to dial in
while testing against real audio.

## 6. Testing / verification plan

- Config schema + property-path correctness: same audit method already used
  earlier in this session (extract every `Config.options.*` reference from
  touched QML, diff against `Config.qml`'s actual property tree).
  Static/mechanical, catches typos with zero manual testing.
- `qs log -c end4-pC -f` tail after every file save, watching for QML parse
  errors and runtime warnings on the touched files specifically (established
  pattern from this session - `qmllint` is not usable in this environment,
  confirmed exit-255 on pristine files).
- Config round-trip: after exercising the new UI, read
  `~/.config/illogical-impulse/config.json` back and confirm
  `monitorWallpapers`/`wallpaperMode`/`transitionMode` hold what was set.
- Shader direction correctness (the one part static checks can't cover):
  `scripts/images/screenshot_all_monitors.sh` before/after triggering a
  synchronized-mode wallpaper change, visually confirm the sweep direction
  matches the monitor's actual physical position relative to its neighbor(s).
- Regression check: with `wallpaperMode: "shared"` and
  `transitionMode: "independent"` (the defaults), behavior must be pixel-for-
  pixel unchanged from before this feature - both new fields are additive
  branches with an explicit "old behavior" fallback path.

## Open items carried into the fast-follow theming spec

- Which monitor's wallpaper drives the global Material You theme when
  `wallpaperMode === "perMonitor"`, or how two palettes get blended when
  "mixed" is selected (per-role color blend after independent matugen runs on
  each contributing image, most likely - not decided here).
