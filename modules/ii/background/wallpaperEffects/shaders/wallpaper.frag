#version 440

// Wallpaper effect pipeline: block displacement -> pixel-sort approximation
// -> RGB separation -> previous-frame feedback -> colour corruption -> noise.
//
// There is deliberately no noise/UV warp stage: a wobbling wallpaper reads as
// a cheap "wavy" filter rather than as anything coming apart.
//
// The shader knows nothing about Quickshell or the audio source. It gets
// two wallpaper textures, its own previous output, and a handful of scalars.
//
// Everything is scaled by `effectStrength` (idle floor + beat envelope) or
// `transition` (wallpaper switch envelope), whichever is larger, so a value
// of 0 in both means "render the wallpaper untouched".

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;

    // --- frame ---
    vec2 resolution;
    float time;

    // --- audio, 0..1, already smoothed on the QML side ---
    float bass;
    float mid;
    float treble;
    float volume;
    float beat;

    // --- master ---
    float effectStrength; // idle floor + beat envelope
    float transition;     // destruction envelope of a wallpaper switch
    float transitionMix;  // sourceA -> sourceB blend
    float transitionSeed; // rerolled per switch; drives every random below

    // --- per-effect base weights, modulated by audio below ---
    float pointAmount;   // sparse point-cloud dissolve
    float pointSpacing;  // point grid spacing, px
    float meltAmount;
    float meltReach;     // how far up the screen the spectrum curve climbs
    float meltWidth;     // drip column width, px
    float feedbackAmount;
    float sortAmount;
    float sortThreshold;
    float sortLength;
    float sortDirection; // <0.5 = along X, >=0.5 = along Y - the global glitch axis

    // --- transition strengths, resolved on the QML side ---
    // Either rolled from the shared seed or taken from config, but always the
    // same on every monitor. The *spatial* character below still comes from
    // transitionSeed directly, since that has to vary per pixel.
    float trMelt;
    float trPoint;
    float trSort;
    float trBlock;
    float trFeedback;
    float trAberration;
    float trNoise;
    float trAxisMode;    // 0 = X, 1 = Y, 2 = roll from the seed
    float trAxisSign;    // +1 or -1, only meaningful when trAxisMode != 2
    float blockSize;     // px
    float blockAmount;
    float chromaticAberration;
    float noiseAmount;
};

layout(binding = 1) uniform sampler2D sourceA;      // outgoing wallpaper
layout(binding = 2) uniform sampler2D sourceB;      // incoming / current wallpaper
layout(binding = 3) uniform sampler2D previousFrame;
// One row of pixels, one per FFT bar, low frequency at x=0. Linear filtering
// turns it into a smooth curve between bars.
layout(binding = 4) uniform sampler2D spectrum;

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Every characteristic of a disintegration is derived from transitionSeed, so
// no two wallpaper switches look alike and none of them follow the look
// settings (those tune the ambient effect only).
float trRand(float k) {
    return hash11(transitionSeed + k);
}

float trBlockPx() {
    return mix(4.0, 44.0, trRand(27.1));
}

// Wallpaper colour at `uv`, accounting for an in-flight wallpaper switch.
// Costs one texture read at rest and two mid-transition.
vec3 sampleBase(vec2 uv) {
    vec2 c = clamp(uv, 0.0, 1.0);
    vec3 b = texture(sourceB, c).rgb;
    if (transitionMix >= 0.999)
        return b;
    vec3 a = texture(sourceA, c).rgb;
    // Blocks flip over one at a time rather than cross-fading, so the switch
    // reads as the old frame being overwritten instead of dissolved.
    vec2 cell = vec2(trBlockPx() * 3.0) / max(resolution, vec2(1.0));
    float r = hash12(floor(c / cell) + vec2(transitionSeed));
    float m = clamp(transitionMix * 1.5 - r * 0.5, 0.0, 1.0);
    return mix(a, b, smoothstep(0.0, 1.0, m));
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 res = max(resolution, vec2(1.0));
    float aspect = res.x / res.y;

    float destroy = max(clamp(effectStrength, 0.0, 2.0), clamp(transition, 0.0, 2.0));
    if (destroy <= 0.0005) {
        fragColor = vec4(sampleBase(uv), 1.0) * qt_Opacity;
        return;
    }

    // How "alive" the track is - keeps everything calm during silence even
    // when the idle floor is non-zero.
    float amb = 0.15 + volume * 0.35;

    // Each effect is driven by the idle/beat state scaled by audio, *plus* an
    // independent transition term. Folding the transition into the audio-scaled
    // part instead would make a wallpaper switch nearly invisible in silence.
    //
    // A kick should tear and shift the image rather than dissolve it, so the
    // transient is weighted towards the geometric effects (blocks / aberration)
    // and away from feedback, which is what actually eats detail.
    //
    // The transition drives a *directional* disintegration instead - the image
    // shears apart along the sort axis and stretches into streaks. See the `tr`
    // terms below.
    float e = clamp(effectStrength, 0.0, 2.0);
    float tr = clamp(transition, 0.0, 2.0);
    bool inTransition = tr > 0.001;

    // The roll for this switch: which way it comes apart, how coarse the debris
    // is, how far it travels, whether it shatters at once or peels off one side.
    float rBlockPx = trBlockPx();
    float rTravel  = mix(0.05, 0.30, trRand(41.9));
    float rStreak  = mix(0.10, 0.45, trRand(55.3));
    float rShear   = mix(0.00, 0.09, trRand(69.7));
    float rStagger = mix(0.15, 0.80, trRand(83.1));
    float rWave    = trRand(97.5);                      // scatter <-> directional sweep
    float rWaveDir = step(0.5, trRand(111.9));
    // A synchronized transition (trAxisMode != 2) uses the geometry-driven
    // sign instead of a per-switch coin flip, so block/feedback motion agrees
    // with which way the melt front (below) is running. Negated relative to
    // trAxisSign - and relative to the melt block below, which uses the sign
    // unnegated - because this feeds a `uv +=` sample-space displacement
    // (line 281/367), whose apparent motion runs opposite to its delta, while
    // melt instead constructs an explicit headUV to move toward. Do NOT drop
    // this minus sign to "match" melt; that reintroduces the bug it fixes.
    float rSign    = (trAxisMode > 1.5) ? (trRand(13.3) < 0.5 ? -1.0 : 1.0) : -trAxisSign;
    float rCorrupt = mix(0.03, 0.25, trRand(195.3));
    float rMeltW   = mix(2.0, 9.0, trRand(223.1));

    // Melt is the signature look, so it gets the strongest beat weighting and
    // everything that competes with it visually - block scatter, aberration,
    // noise - is held well back. Balanced the other way the paint runs vanish
    // under speckle at beat peaks.
    float meltAmt  = meltAmount          * e * (amb + bass * 0.80 + beat * 1.30)        + tr * trMelt;
    // Beat weight kept well below the transition term on purpose: a kick should
    // stipple the picture, not dissolve it outright. Full scatter is reserved
    // for a wallpaper switch.
    float pointAmt = pointAmount         * e * (amb * 0.15 + beat * 0.70)               + tr * trPoint;
    float blockAmt = blockAmount         * e * (amb * 0.3 + bass * 0.30 + beat * 0.45) + tr * trBlock;
    float sortAmt  = sortAmount          * e * (amb + mid * 0.60 + beat * 0.35)        + tr * trSort;
    float fbAmt    = feedbackAmount      * e * (amb + bass * 0.45 + beat * 0.25)       + tr * trFeedback;
    float caAmt    = chromaticAberration * e * (amb + treble * 0.70 + beat * 0.45)     + tr * trAberration;
    float noiseAmt = noiseAmount         * e * (amb + treble * 0.50 + beat * 0.25)     + tr * trNoise;

    // Block grid, shared by displacement / feedback / corruption so they line up.
    // A transition brings its own grid rather than the configured one.
    vec2 cellUV = vec2(inTransition ? rBlockPx : max(blockSize, 1.0)) / res;
    // Blocks hold for a few frames, otherwise they read as noise, not corruption.
    float seed = floor(time * 15.0);
    // One axis for the whole look - melt, block slide and pixel sort all use it.
    // A transition only rolls its own when the axis is set to random.
    vec2 cfgDir = mix(vec2(1.0, 0.0), vec2(0.0, 1.0), step(0.5, sortDirection));
    // A transition uses its own axis setting, not the ambient one.
    vec2 trDir = (trAxisMode > 1.5)
        ? mix(vec2(1.0, 0.0), vec2(0.0, 1.0), step(0.5, trRand(1.7)))
        : mix(vec2(1.0, 0.0), vec2(0.0, 1.0), step(0.5, trAxisMode));
    vec2 sortDir = inTransition ? trDir : cfgDir;
    vec2 acrossDir = vec2(sortDir.y, sortDir.x);

    // --- 0. melt / drip ----------------------------------------------------
    // The melt line *is* the spectrum: each column's start row comes from the
    // FFT bar at that x, so the wallpaper melts along the music's own curve.
    // Starting every column at a random height (what this used to do) just
    // reads as a scatter of unrelated vertical lines.
    //
    // Below that line the start pixel is dragged down as a paint run: full
    // column width at the top, narrowing as it falls, with a rounded bead near
    // the tip where paint gathers, and a per-column random stopping point so
    // the drips do not all end level with each other.
    if (meltAmt > 0.001) {
        // Worked in run/lane space rather than x/y so the runs follow the same
        // axis as everything else: `sortDir` is the direction paint travels,
        // `acrossDir` indexes the lanes it travels in.
        float laneRes = max(dot(res, acrossDir), 1.0);
        float colw = max(meltWidth * (inTransition ? rMeltW : 1.0), 1.0) / laneRes;
        float lane = dot(uv, acrossDir);
        float along = dot(uv, sortDir);
        float ci = floor(lane / colw);
        float cx = (ci + 0.5) * colw;
        float sd = inTransition ? transitionSeed : 0.0;

        float level = clamp(texture(spectrum, vec2(clamp(cx, 0.0, 1.0), 0.5)).r, 0.0, 1.0);
        // A transition has no spectrum to follow when nothing is playing, so it
        // supplies its own level and the curve becomes a rolling edge instead.
        level = max(level, tr * (0.35 + 0.65 * hash11(ci * 0.7 + sd)));
        float drive = clamp(meltAmt, 0.0, 1.5) * level;

        if (drive > 0.002) {
            // Loud bands start higher up the screen, so the melt front traces
            // the spectrum outline across the wallpaper. A synchronized
            // transition with a negative sign mirrors which edge the front
            // starts from, so "up" and "left" runs the drip the other way.
            // trAxisSign is used unnegated here, unlike rSign above - see the
            // comment there for why the two sites disagree on sign.
            float head = (trAxisMode > 1.5 || trAxisSign > 0.0)
                ? 1.0 - level * clamp(meltReach, 0.0, 1.0)
                : level * clamp(meltReach, 0.0, 1.0);
            vec2 headUV = uv + sortDir * (head - along);
            vec3 headCol = sampleBase(headUV);
            // Dark paint is heavy and runs further - keeps the drips tied to
            // what is actually in the picture rather than to the grid.
            float heavy = 1.0 - luma(headCol);
            float len = drive * (0.10 + hash11(ci * 3.9 + sd + 5.0) * 0.90) * (0.55 + heavy * 0.9);

            float t = (trAxisMode > 1.5 || trAxisSign > 0.0)
                ? (along - head) / max(len, 1e-4)
                : (head - along) / max(len, 1e-4);
            if (t >= 0.0 && t <= 1.0) {
                float bead = exp(-pow((t - 0.90) / 0.07, 2.0)) * 0.30;
                float halfW = colw * 0.5 * ((1.0 - t * 0.72) + bead);
                float edge = 1.0 - smoothstep(halfW * 0.65, halfW, abs(lane - cx));
                uv = mix(uv, headUV, edge);
            }
        }
    }

    // --- 1. block displacement ---------------------------------------------
    if (blockAmt > 0.0005) {
        float a = clamp(blockAmt, 0.0, 1.0);
        vec2 cell = floor(uv / cellUV);
        vec2 h = hash22(cell + vec2(seed * 1.7, seed * 3.1));
        float alive = step(1.0 - a * 0.5, hash12(cell + vec2(seed * 7.3)));
        uv += (h - 0.5) * cellUV * 5.0 * a * alive;
    }

    // --- 1b. transition: blocks come loose and slide -----------------------
    // Each block detaches at its own moment (from a hash that is stable for the
    // whole switch, so a block keeps travelling instead of flickering) and then
    // accelerates along the axis. `rWave` blends that per-block scatter towards
    // a positional sweep, so a switch may shatter everywhere at once or peel
    // away from one edge.
    float loose = 0.0;
    if (inTransition) {
        vec2 cell = floor(uv / cellUV);
        float scatter = hash12(cell * 1.13 + vec2(transitionSeed));
        float along01 = clamp(dot(uv, sortDir), 0.0, 1.0);
        float detach = mix(scatter, mix(along01, 1.0 - along01, rWaveDir), rWave);
        loose = clamp((tr - detach * rStagger) / max(1.0 - rStagger, 0.15), 0.0, 1.0);
        uv += sortDir * rSign * loose * loose * rTravel * (0.4 + scatter);
        uv += acrossDir * (hash12(cell + vec2(transitionSeed + 9.1)) - 0.5) * loose * rShear;
    }

    // --- 2. pixel-sort approximation ---------------------------------------
    // Snap every pixel back to the head of its segment when the head is bright
    // enough, which smears runs of pixels the way a real sort does.
    //
    // During a transition the segments grow towards a third of the screen and
    // the brightness gate opens up, so every column stretches into a streak and
    // the picture collapses into bands. Running in reverse as `tr` falls is what
    // reassembles the new wallpaper out of the debris.
    if (sortAmt > 0.0005) {
        float along = dot(uv, sortDir);
        float across = dot(uv, acrossDir);
        float segLen = max(sortLength, 0.002) * (0.35 + mid * 1.30);
        segLen += tr * tr * rStreak;
        segLen *= 0.5 + hash11(floor(across * 220.0) + seed * 0.37);
        float head = floor(along / segLen) * segLen;
        vec2 headUV = uv + sortDir * (head - along);
        float l = luma(sampleBase(headUV));
        float thr = mix(sortThreshold, -0.15, clamp(tr, 0.0, 1.0));
        float pick = smoothstep(thr - 0.12, thr + 0.12, l);
        uv = mix(uv, headUV, pick * clamp(sortAmt, 0.0, 1.0));
    }

    // --- 3. base colour + RGB separation -----------------------------------
    vec3 col;
    // Threshold high enough that a barely-visible fringe does not cost three
    // sampleBase() calls (six texture reads mid-transition) instead of one.
    if (caAmt > 0.02) {
        vec2 off = vec2(caAmt * 0.012 / aspect, 0.0);
        off += (hash22(vec2(seed)) - 0.5) * caAmt * 0.004;
        col = vec3(sampleBase(uv + off).r, sampleBase(uv).g, sampleBase(uv - off).b);
    } else {
        col = sampleBase(uv);
    }

    // --- 3b. sparse point cloud --------------------------------------------
    // The picture breaks into a grid of points that drift apart, leaving the
    // gaps between them empty. Each pixel finds the nearest drifted point in
    // its 3x3 neighbourhood - nine hashes, but only one texture read, for the
    // winner - and takes the colour that point carries from its own origin. So
    // the image survives as a scatter of samples rather than dissolving into
    // noise, and reassembles cleanly when the amount falls again.
    if (pointAmt > 0.002) {
        float a = clamp(pointAmt, 0.0, 1.0);
        vec2 cellSize = vec2(max(pointSpacing, 2.0)) / res;
        vec2 baseCell = floor(uv / cellSize);
        // Drift direction is fixed per point, so rising amount pushes the cloud
        // steadily apart instead of reshuffling it every frame.
        float cloudSeed = inTransition ? transitionSeed : 0.0;
        float best = 1e9;
        vec2 bestOrigin = uv;
        float bestSize = 1.0;
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                vec2 c = baseCell + vec2(float(i), float(j));
                vec2 origin = (c + 0.5) * cellSize;
                vec2 h = hash22(c + vec2(cloudSeed)) - 0.5;
                vec2 pos = origin + h * cellSize * a * 3.2;
                float d = length((uv - pos) / cellSize);
                if (d < best) {
                    best = d;
                    bestOrigin = origin;
                    bestSize = 0.6 + hash12(c + vec2(cloudSeed + 3.1)) * 0.8;
                }
            }
        }
        // Points shrink as they scatter - that is what makes it read as sparse
        // rather than as a smeared mosaic.
        float radius = mix(0.80, 0.20, a) * bestSize;
        float mask = 1.0 - smoothstep(radius * 0.55, radius, best);
        col = mix(col, sampleBase(bestOrigin) * mask, a);
    }

    // --- 4. previous-frame feedback ----------------------------------------
    // The block motion vector is applied to the *old* frame; that mismatch
    // between motion and content is what datamoshing actually looks like.
    if (fbAmt > 0.001) {
        float a = clamp(fbAmt, 0.0, 1.0);
        vec2 cell = floor(qt_TexCoord0 / cellUV);
        vec2 mv = (hash22(cell + vec2(seed * 2.3, seed * 5.9)) - 0.5) * cellUV * 6.0 * a;
        // During a transition the drag is aligned with the slide instead of
        // random, so loose blocks leave trails behind them rather than blurring
        // in place.
        mv -= sortDir * rSign * loose * tr * 0.012;
        // The 0.97 bleed keeps the loop from ratcheting towards white: noise is
        // added after this and the final clamp rectifies it, so without a decay
        // term a sustained high feedback would wash the wallpaper out.
        vec3 prev = texture(previousFrame, clamp(qt_TexCoord0 + mv, 0.0, 1.0)).rgb * 0.97;
        col = mix(col, prev, min(a, 0.80));
    }

    // --- 5. colour corruption ----------------------------------------------
    // Kept sparse. Scattered channel-swapped blocks over an otherwise intact
    // image read as a novelty glitch filter; during a transition they only look
    // right on debris that has already come loose, so they are gated on `loose`.
    float corrupt = smoothstep(0.60, 1.20, e) * 0.12 + loose * tr * rCorrupt;
    if (corrupt > 0.001) {
        float r = hash12(floor(qt_TexCoord0 / (cellUV * 2.0)) + vec2(seed * 11.0));
        col = mix(col, col.gbr, step(1.0 - corrupt, r));
    }

    // --- 6. noise ------------------------------------------------------------
    if (noiseAmt > 0.001) {
        float n = hash12(qt_TexCoord0 * res + vec2(fract(time) * 719.0));
        col += (n - 0.5) * noiseAmt * 0.25;
    }

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
