# Wallpaper effects

A shader wallpaper: datamosh / pixel-sort style glitching that reacts to music,
and wallpaper switches that disintegrate the old image into the new one.

All the visual work happens in one fragment shader. QML only supplies textures,
timing, audio scalars and transition parameters — the shader knows nothing about
Quickshell or PipeWire.

## Two independent uses

| | What it does | Turned on by |
|---|---|---|
| **Ambient** | Continuously melts/moshes whichever wallpaper is currently set, reacting to music | `background.effects.enable` (Settings → Background → Shader effects → *Animate current wallpaper*) |
| **Transition** | Turns a wallpaper change into a datamosh transition | `background.wallpaperAnimation = "datamosh"` (Settings → Background → *Transitions* dropdown) |

The transition is **not** its own toggle: it is one of the wallpaper animations,
picked from the same dropdown as Magic, Stripes, Pixelate and so on. It has no
look settings at all — every characteristic is rerolled from a random seed on
each switch (see *Randomness* below). The one control it honours is
`background.transitionDuration`, which is shared by **every** wallpaper
animation, classic ones included.

Neither use depends on the other. Pick *Datamosh* with the ambient effect off to
get a perfectly still wallpaper that only glitches when it changes; enable the
ambient effect with any other transition to get a melting wallpaper that swaps
images with a plain dissolve.

Because the shader wallpaper owns the wallpaper surface whenever it is active,
the classic transition shaders cannot run underneath it. With the ambient effect
on and a classic transition selected, switches degrade to a block dissolve
(`transitionIntensity` 0) rather than silently doing nothing. Selecting *None*
still swaps instantly. `"datamosh"` is deliberately excluded from the *Random*
pool, since which renderer draws the wallpaper cannot be decided per-switch.

With the ambient effect off (or all three of its intensities at 0) and no
transition running, the renderer stops requesting frames entirely: the wallpaper
becomes a plain still image with no per-frame GPU cost.

## Files

```
WallpaperEffect.qml     public component - set `source`, it does the rest
WallpaperRenderer.qml   ShaderEffect + recursive previous-frame buffer
EffectController.qml    MUSIC/BEAT/TRANSITION state machine, resolves all params
shaders/wallpaper.frag  the pipeline
shaders/build.sh        recompiles .frag -> .frag.qsb (needs qt6-shadertools)
```

Used from `modules/ii/background/Background.qml`, which swaps it in for the
plain wallpaper image and the older `wallpaperAnimation` shader transitions.

## Pipeline

```
sourceA/sourceB -> melt / drip -> block displacement -> pixel-sort approximation
                -> RGB separation -> previous-frame feedback
                -> colour corruption -> noise -> screen
```

**Melt** is the signature stage. The melt front *is* the spectrum: each column's
start row comes from the FFT bar at that x (handed to the shader as a
one-pixel-tall texture, one pixel per bar, linearly filtered into a curve), so
the wallpaper melts along the music's own outline. Starting every column at a
random height - what this did first - just reads as a scatter of unrelated
vertical lines.

Below that front the start pixel is dragged down as a paint run: full column
width at the top, narrowing as it falls, with a rounded bead near the tip where
paint gathers, and a per-column random stopping point so the drips do not all
end level. Dark pixels run further, on the grounds that heavy paint does, which
keeps the runs tied to the picture rather than to the grid.

Melt carries the strongest beat weighting and everything that competes with it
visually - block scatter, aberration, noise - is held well back. Balanced the
other way the runs vanish under speckle at beat peaks.

A transition has no spectrum to follow when nothing is playing, so it supplies
its own per-column level and the front becomes a rolling edge instead.

There is deliberately **no noise/UV warp stage**. A wobbling wallpaper reads as
a cheap "wavy" filter rather than as anything coming apart, so both the beat
response and the transition are built out of displacement, streaking and
smearing instead.

**Point cloud** breaks the picture into a grid of points that drift apart,
leaving the gaps between them empty. Each pixel finds the nearest drifted point
in its 3x3 neighbourhood — nine hashes, but only one texture read, for the winner
— and takes the colour that point carries from its own origin, so the image
survives as a scatter of samples rather than dissolving into noise, and
reassembles cleanly when the amount falls again. Points shrink as they scatter,
which is what makes it read as sparse rather than as a smeared mosaic.

Drift direction is fixed per point, so a rising amount pushes the cloud steadily
apart instead of reshuffling it every frame. Its beat weight is kept well below
its transition weight on purpose: a kick should stipple the picture, not dissolve
it. Only some switches dissolve into points (`rCloud` is rolled per transition) —
having every one do it would make the transition feel canned again.

The pixel sort is an approximation, not a real sort: each pixel snaps back to the
head of its segment along the sort axis when that head is bright enough, which
smears runs of pixels the way a sort does, at two texture reads instead of N.

Feedback is a `ShaderEffectSource` with `recursive: true`, sampled at a
block-derived motion vector — applying this frame's motion to the *previous*
frame's content is what makes it read as datamoshing rather than motion blur.

## Audio

`services/AudioLevels.qml` runs `scripts/audio/qs-audiotap`, which talks to
PipeWire directly and does its own FFT, band split, auto gain and beat detection.
It replaced cava outright — see `scripts/audio/` for the details. The QML side
does no DSP and adds no smoothing, so nothing sits between the sound and the
shader.

The capture target is **not** user-configurable: it always follows whichever
MPRIS player is actually playing, because the player cards and the ticker draw a
visualiser for the app they are showing. If that app's PipeWire node cannot be
resolved, qs-audiotap falls back to the sink monitor on its own.

`background.effects.player` is separate — it only gates the *wallpaper*. The bars
stay live for whatever is playing, but the wallpaper stays still unless the
chosen player is the one making noise. Empty means anything. The datamosh
transition needs no audio at all; it looks the same in silence.

Reactivity tuning (beat sensitivity/floor/decay/gap, update rate, spectrum bars
and range, auto gain release) lives under `background.effects.audio` and is
passed straight through to qs-audiotap as flags. Those apply to every visualiser
in the shell, not just the wallpaper.

Each band drives a different part of the look:

| Band | Drives |
|---|---|
| bass | melt depth, block displacement, feedback |
| mid | pixel sort |
| treble | RGB separation, noise |
| beat | a short burst across all of them, weighted towards tearing over smearing |

## Glitch direction

`background.effects.glitchDirection` is one axis for the whole look — melt runs,
block slide and pixel sort all use it:

| value | behaviour |
|---|---|
| `vertical` | paint runs downward, sort along Y |
| `horizontal` | everything rotates 90°, runs travel sideways |
| `random` | each wallpaper switch rolls its own axis; the ambient effect stays vertical |

`random` is the default: it keeps the per-switch roll the transition already did,
and leaves the ambient effect vertical, since paint running sideways is a choice
rather than a default. The melt works in run/lane space rather than x/y precisely
so this rotation is one uniform rather than a second code path.

## Presets

`EffectPresets.qml` holds the look presets, shown as a dropdown at the top of
Settings → Background → Shader effects.

| Preset | Character |
|---|---|
| **DnB** | Punchy and sharp — strong beat weighting, coarse block scatter, hard edges |
| **Lofi / VHS** | Tape rather than digital — heavy persistence for the smear, wide soft runs, strong colour bleed, visible grain. Pair with a horizontal glitch direction for the full scanline look |
| **Cyberpunk** | Hard digital failure — coarse blocks, near-maximum corruption, sharp RGB split, almost no melt |
| **Paint drip** | The melt on its own; everything that competes with the runs is turned down |
| **Ambient** | Barely there — breathes with the music without being what you look at |

Applying one writes its values straight into `background.effects`, so the sliders
always show what is actually running — there is no hidden override layer.
"Custom" is not stored: `currentName()` compares the live values against each
preset, so nudging any slider makes the dropdown read Custom on its own rather
than keeping a label that no longer describes the values.

Presets are deliberately scoped to the look and the intensities. Two things are
left out on purpose:

- `effects.audio` is the analysis tuning for *every* visualiser in the shell, so
  a wallpaper preset has no business rewriting it.
- `glitchDirection` is an orientation, not a look. While it was a preset value,
  picking a direction knocked the dropdown to Custom and applying a preset
  silently reoriented the whole effect. It is now independent in both directions:
  changing it keeps your preset, and applying a preset keeps your direction.

Both glitch directions — ambient and transition — can be changed freely while
`transition.randomize` is on. Randomize governs the effect *strengths*, not the
orientation.

## The transition's own settings

`background.effects.transition` is a separate block from the ambient settings:
its own melt / point cloud / pixel sort / feedback / block corruption / RGB
separation / noise, plus its own `glitchDirection`. `randomize` (on by default)
rolls those strengths per switch instead of using the configured values.

It deliberately has **no monitor option**. A wallpaper switch happens on every
screen — `Background.qml` scopes `effects.screenMode` to the ambient effect only,
so a monitor excluded from that still plays the transition.

## Shared seed across monitors

`TransitionSeed.qml` is a singleton holding the seed and the A→B handover window.
Each screen gets its own `WallpaperEffect` and its own `EffectController`, so
rolling inside `startTransition()` gave every monitor a *different*
disintegration for the same wallpaper change. The roll is now keyed on the
incoming wallpaper path: the first monitor to start rolls it, the rest reuse it.

The per-switch strengths are drawn from that seed too (`TransitionSeed.draw()`),
not from `Math.random()` — each monitor evaluates its own bindings, so anything
random resolved per-controller would diverge.

What still varies per pixel comes from the seed inside the shader: which blocks
detach when, how far they slide, debris size, whether it shatters at once or
peels from one edge. Before any of this, the hashes were keyed to pixel position
alone, so every switch rendered the *identical* pattern and read as canned.

## State intensities

The states **saturate** rather than stack, so each config value is the level that
state actually reaches:

```
effectStrength = max(volume * musicIntensity, beat * beatIntensity)
destruction    = max(effectStrength, transitionEnvelope)
```

Summing them instead put every kick at ~1.0, i.e. at full transition strength,
which obliterated the wallpaper on every bass note.

There is no idle floor. With nothing playing `effectStrength` is 0, the wallpaper
is a still image and the renderer stops requesting frames - an "idle intensity"
knob only ever meant "how much does a silent desktop cost you".

## Monitors

`background.effects.screenMode` is `all`, `allButPrimary`, or a monitor name.
Primary comes from `Config.options.hyprland.primaryMonitor` — the value Settings
→ Hyprland actually sets. Hyprland's own monitor id 0 is just whichever output
came up first and does **not** track that choice, which is why it picked the
wrong screen before. A monitor the effect is excluded
from falls back to the plain wallpaper image; note that "datamosh" has no classic
`.frag.qsb`, so on an excluded monitor it swaps instantly rather than animating.

## Editing the shader

Edit `shaders/wallpaper.frag`, then run `shaders/build.sh` and restart the shell.
The `.frag.qsb` is committed because Quickshell loads that, not the source.

Avoid constant arrays and non-constant loop bounds: the compiled `.qsb` includes
a GLSL 100 es / 120 target, and at least one driver in use here rejects
`const int[]` (see the `Doom` shader comment in `Background.qml`).

## Tuning notes

- The transition is a *directional disintegration*, not a filter sweep: blocks
  detach on a staggered per-block schedule and slide along the sort axis while
  the sort segments grow towards a third of the screen and the brightness gate
  opens, so the picture collapses into streaks. The same code run in reverse as
  the envelope falls is what reassembles the new wallpaper out of the debris.
- The destruction envelope is `sin(pi * p) ^ 1.5`. The exponent above 1 matters:
  a plain sine is already past half destruction at 10% progress, which robs you
  of watching the wallpaper come apart.
- `feedback` is the parameter that decides how much this looks like datamoshing.
  At 0 it is a clean wallpaper, at high values old pixels keep propagating.
- The feedback path multiplies the previous frame by 0.97. Without that decay the
  loop ratchets towards white, because noise is added after the mix and the final
  clamp rectifies it.
- `blockSize` is in pixels and is shared by displacement, feedback motion vectors
  and corruption, so they line up on the same grid.
- Three things were costing dropped frames on a switch, all fixed and worth not
  reintroducing: the recursive `ShaderEffectSource` allocating its screen-sized
  double buffers when `live` first went true (now pre-allocated with
  `scheduleUpdate()` at startup, ~200ms), the second `Image`'s texture and layer
  FBO being built on the first switch (now warmed by giving it the same wallpaper
  on first load), and the GPU *upload* of a newly decoded image landing on the
  first transition frame. `Image.Ready` means decoded, not uploaded, so
  `WallpaperEffect` lets two frames render with the image bound before starting
  the animation.
- `WallpaperEffect` ping-pongs two `Image`s and never unloads either, and it does
  not put anything on screen until the incoming one has decoded. A transition
  starts at `transitionMix` 0 — i.e. showing `sourceA`, the *outgoing* wallpaper
  — so if that one is still loading the switch opens on a black frame.
- Transition timing is `background.transitionDuration` with the A→B handover
  placed in a randomly rolled window, always inside the destruction peak so the
  swap happens while the image is unreadable.
