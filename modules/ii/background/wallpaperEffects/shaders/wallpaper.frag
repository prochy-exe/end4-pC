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
    float musicIntensity;
    float beatIntensity;
    // 0 = current tuned mix, 1 = volume, 2 = kick/beat, 3 = bass,
    // 4 = mid, 5 = treble. Resolved from the settings dropdowns.
    float meltTrigger;
    float pointTrigger;
    float feedbackTrigger;
    float sortTrigger;
    float blockTrigger;
    float aberrationTrigger;
    float noiseTrigger;
    float lidarTrigger;
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
    float neighborBleed;
    float neighborBleedMusicReactive;
    float neighborBleedWidth;
    float neighborBleedStrength;
    float neighborBleedFragmentThreshold;
    float neighborBleedFragmentSoftness;
    float neighborBleedColorTrails;
    float neighborBleedColorThreshold;
    float neighborBleedColorSoftness;
    float neighborBleedColorStrength;
    float neighborBleedLidar;
    float neighborBleedLidarOutlines;
    float neighborBleedLidarStrength;
    float neighborBleedLidarDensity;
    float neighborBleedLidarSpeed;
    float lidarEnabled;
    float neighborBleedEdgeSoftness;
    float neighborBleedRaggedness;
    float neighborBleedGrain;
    float neighborBleedMotionSpeed;
    float neighborBleedFeedback;
    float neighborBleedBattle;
    float neighborBleedBattleStrength;
    float neighborBleedPrimaryPush;
    float neighborBleedSecondaryResistance;
    float neighborBleedEffectStrength;
    float neighborReady;
    vec2 neighborDirection;
    float neighborTransitionMix;
    float neighborTransitionPhase;
    float neighborTransition;
    vec2 neighborTransitionDirection;
    vec2 neighborCanvasOrigin;
    vec2 neighborCanvasScale;
    vec2 neighborCanvasResolution;
    float neighborEffectStrength;
    float neighborMusicIntensity;
    float neighborBeatIntensity;
    float neighborPointAmount;
    float neighborPointSpacing;
    float neighborMeltAmount;
    float neighborMeltReach;
    float neighborMeltWidth;
    float neighborSortAmount;
    float neighborSortThreshold;
    float neighborSortLength;
    float neighborBlockSize;
    float neighborBlockAmount;
    float neighborChromaticAberration;
    float neighborNoiseAmount;
    float neighborTrAxisMode;
    float neighborTrAxisSign;
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
layout(binding = 5) uniform sampler2D neighborWallpaperA;
layout(binding = 6) uniform sampler2D neighborWallpaperB;

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

// Shared by LiDAR and the melt field: a contour can be defined by either a
// luminance break or a coloured edge, which keeps pale line art and saturated
// artwork equally usable as a melt source.
float imageOutline(vec3 center, vec3 left, vec3 right, vec3 up, vec3 down) {
    float lumaEdge = abs(luma(right) - luma(left)) + abs(luma(down) - luma(up));
    float colourEdge = max(max(length(center - left), length(center - right)),
        max(length(center - up), length(center - down)));
    return smoothstep(0.08, 0.50, max(lumaEdge * 1.25, colourEdge * 0.55));
}

// Auto retains the original hand-tuned mix for each effect. An explicit route
// replaces that mix with exactly one audio event, using the matching global
// intensity control so "Kick" really means the beat envelope drives it.
float routedAudioDrive(float trigger, float autoDrive, float musicGain, float beatGain,
    float ambientScope) {
    if (trigger < 0.5)
        return autoDrive;
    // Explicit bands read the raw analyzer values, unlike Auto which already
    // carries effectStrength. Do not let that bypass the per-monitor "Apply
    // to" gate when a transition or seam happens to keep audio data alive.
    if (ambientScope <= 0.0005)
        return 0.0;
    if (trigger < 1.5)
        return volume * musicGain;
    if (trigger < 2.5)
        return beat * beatGain;
    if (trigger < 3.5)
        return bass * musicGain;
    if (trigger < 4.5)
        return mid * musicGain;
    return treble * musicGain;
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

// The two wallpaper windows cannot share textures directly, so each window
// holds a local decoded copy of its touching neighbour's wallpaper. The seam
// starts on that neighbour's *facing edge* and preserves the coordinate along
// the edge. That makes the source read as a continuation dragged across the
// physical monitor boundary, rather than as a second image pasted on top.
vec2 neighborUv(vec2 uv, vec2 dir, float displacement) {
    float towardNeighbor = clamp(dot(uv - vec2(0.5), dir) + 0.5, 0.0, 1.0);
    float inward = 1.0 - towardNeighbor;
    vec2 n = uv;
    // At the shared edge, sample the opposite edge of the primary image. As
    // the filaments travel into this monitor they only look a short distance
    // into that image, so its boundary is visibly stretched outwards.
    if (abs(dir.x) > 0.5)
        n.x = 0.5 - dir.x * 0.5 + dir.x * inward * 0.34;
    else
        n.y = 0.5 - dir.y * 0.5 + dir.y * inward * 0.34;
    n -= dir * displacement;
    return clamp(n, 0.0, 1.0);
}

// `transitionUv` is in virtual-primary canvas coordinates, keeping the switch
// block pattern continuous when it crosses a real monitor edge.
vec3 sampleNeighborAt(vec2 textureUv, vec2 transitionUv) {
    vec2 n = clamp(textureUv, 0.0, 1.0);
    vec3 b = texture(neighborWallpaperB, n).rgb;
    // The cross-monitor handover is an extension of the *incoming* wallpaper.
    // Sampling A while the source monitor is still breaking apart made the old
    // image leak into its neighbour before the new image arrived. B has already
    // completed the warm-up before the shared clock starts, so it is safe to use
    // from the first pixel of the directional sweep.
    if (neighborTransitionPhase < 0.9999 || neighborTransitionMix >= 0.999)
        return b;

    // Match the normal wallpaper handover: source B overwrites source A in
    // seeded blocks instead of fading in as a soft gradient. The borrowed
    // primary image therefore infects the existing seam progressively.
    vec3 a = texture(neighborWallpaperA, n).rgb;
    vec2 cell = vec2(trBlockPx() * 3.0) / max(neighborCanvasResolution, vec2(1.0));
    float r = hash12(floor(transitionUv / cell) + vec2(transitionSeed + 53.7));
    float m = clamp(neighborTransitionMix * 1.5 - r * 0.5, 0.0, 1.0);
    return mix(a, b, smoothstep(0.0, 1.0, m));
}

vec3 sampleNeighbor(vec2 uv, vec2 dir, float displacement) {
    vec2 n = neighborUv(uv, dir, displacement);
    return sampleNeighborAt(n, n);
}

// Primary texture coordinates for a virtual-primary canvas position. Outside
// the primary's real bounds, run back through the source canvas from its
// touching edge. This keeps the travelling strip recognisably sourced from the
// actual new wallpaper instead of stretching one static edge column.
vec2 neighborExtensionTextureUv(vec2 canvasUv) {
    vec2 outward = dot(neighborTransitionDirection, neighborTransitionDirection) > 0.5
        ? normalize(neighborTransitionDirection) : -neighborDirection;
    vec2 n = canvasUv;
    if (abs(outward.x) > 0.5) {
        float depth = outward.x > 0.0 ? max(canvasUv.x - 1.0, 0.0) : max(-canvasUv.x, 0.0);
        n.x = outward.x > 0.0 ? 1.0 - depth : depth;
    } else {
        float depth = outward.y > 0.0 ? max(canvasUv.y - 1.0, 0.0) : max(-canvasUv.y, 0.0);
        n.y = outward.y > 0.0 ? 1.0 - depth : depth;
    }
    return clamp(n, 0.0, 1.0);
}

vec3 sampleNeighborCanvas(vec2 canvasUv) {
    return sampleNeighborAt(neighborExtensionTextureUv(canvasUv), canvasUv);
}

// Replays the source wallpaper's deterministic effect pipeline on a canvas
// that extends beyond the source monitor. Feedback is applied by the bridge
// below because recursive frame textures cannot cross Quickshell windows;
// melt, blocks, pixel sort, RGB split, points, noise, seed and timeline stay
// line-for-line aligned with the local wallpaper pipeline.
vec4 sampleNeighborExtension(vec2 canvasUv, float neighborEffect, float seamTransition) {
    vec2 uv = canvasUv;
    vec2 primaryRes = max(neighborCanvasResolution, vec2(1.0));
    float e = clamp(neighborEffect, 0.0, 2.0);
    float tr = clamp(seamTransition, 0.0, 2.0);
    bool inTransition = tr > 0.001;
    if (max(e, tr) <= 0.0005)
        return vec4(sampleNeighborCanvas(uv), 0.0);

    float amb = 0.15 + volume * 0.35;
    float meltAmt = neighborMeltAmount * routedAudioDrive(meltTrigger,
        e * (amb + bass * 0.80 + beat * 1.30), neighborMusicIntensity, neighborBeatIntensity, e) + tr * trMelt;
    float pointAmt = neighborPointAmount * routedAudioDrive(pointTrigger,
        e * (amb * 0.15 + beat * 0.70), neighborMusicIntensity, neighborBeatIntensity, e) + tr * trPoint;
    float blockAmt = neighborBlockAmount * routedAudioDrive(blockTrigger,
        e * (amb * 0.30 + bass * 0.30 + beat * 0.45), neighborMusicIntensity, neighborBeatIntensity, e) + tr * trBlock;
    float sortAmt = neighborSortAmount * routedAudioDrive(sortTrigger,
        e * (amb + mid * 0.60 + beat * 0.35), neighborMusicIntensity, neighborBeatIntensity, e) + tr * trSort;
    float caAmt = neighborChromaticAberration * routedAudioDrive(aberrationTrigger,
        e * (amb + treble * 0.70 + beat * 0.45), neighborMusicIntensity, neighborBeatIntensity, e) + tr * trAberration;
    float noiseAmt = neighborNoiseAmount * routedAudioDrive(noiseTrigger,
        e * (amb + treble * 0.50 + beat * 0.25), neighborMusicIntensity, neighborBeatIntensity, e) + tr * trNoise;

    float rBlock = trBlockPx();
    float rTravel = mix(0.05, 0.30, trRand(41.9));
    float rStreak = mix(0.10, 0.45, trRand(55.3));
    float rShear = mix(0.00, 0.09, trRand(69.7));
    float rStagger = mix(0.15, 0.80, trRand(83.1));
    float rWave = trRand(97.5);
    float rWaveDir = step(0.5, trRand(111.9));
    float rMeltW = mix(2.0, 9.0, trRand(223.1));
    float seed = floor(time * 15.0);
    // This tracks geometry only. RGB/noise can make every source pixel differ
    // numerically, but they are not image fragments travelling across a seam.
    float spatialDistortion = 0.0;

    vec2 cfgDir = mix(vec2(1.0, 0.0), vec2(0.0, 1.0), step(0.5, sortDirection));
    vec2 transitionAxis = (neighborTrAxisMode > 1.5)
        ? mix(vec2(1.0, 0.0), vec2(0.0, 1.0), step(0.5, trRand(1.7)))
        : mix(vec2(1.0, 0.0), vec2(0.0, 1.0), step(0.5, neighborTrAxisMode));
    vec2 sortDir = inTransition ? transitionAxis : cfgDir;
    vec2 acrossDir = vec2(sortDir.y, sortDir.x);
    // Sampling opposite to the visual travel makes detached primary blocks
    // continue out through the primary edge and into this receiver.
    float rSign = neighborTrAxisMode > 1.5
        ? (trRand(13.3) < 0.5 ? -1.0 : 1.0) : -neighborTrAxisSign;
    vec2 cellUV = vec2(inTransition ? rBlock : max(neighborBlockSize, 1.0)) / primaryRes;

    if (meltAmt > 0.001) {
        // A seam knows which way the neighbour actually sits. Use that signed
        // vector for the contour flow so source outlines continue outward
        // through the physical edge instead of collecting at a screen corner.
        vec2 meltFlow = dot(neighborTransitionDirection, neighborTransitionDirection) > 0.5
            ? normalize(neighborTransitionDirection) : sortDir;
        float spectrumCoord = abs(meltFlow.x) > 0.5 ? uv.y : uv.x;
        float level = clamp(texture(spectrum, vec2(clamp(spectrumCoord, 0.0, 1.0), 0.5)).r, 0.0, 1.0);
        level = max(level, tr * (0.35 + 0.65 * hash11(floor(spectrumCoord * 220.0) + transitionSeed)));
        float drive = clamp(meltAmt, 0.0, 1.5) * level;
        if (drive > 0.002) {
            float detail = clamp(neighborMeltWidth * 0.30, 1.0, 18.0);
            vec2 texel = vec2(detail) / primaryRes;
            float lengthSeed = hash12(floor(uv * primaryRes / max(detail * 2.0, 1.0))
                + vec2(transitionSeed));
            float length = clamp(neighborMeltReach, 0.0, 1.0)
                * (0.08 + lengthSeed * 0.62) * clamp(drive, 0.0, 1.25);
            float bestOutline = 0.0;
            vec2 bestOrigin = uv;
            // Three taps turn a contour into a continuous-looking dragged
            // filament without the cost of a full blur along every pixel.
            for (int i = 1; i <= 3; ++i) {
                vec2 origin = uv - meltFlow * length * (float(i) / 3.0);
                vec3 center = sampleNeighborCanvas(origin);
                float outline = imageOutline(center,
                    sampleNeighborCanvas(origin - vec2(texel.x, 0.0)),
                    sampleNeighborCanvas(origin + vec2(texel.x, 0.0)),
                    sampleNeighborCanvas(origin - vec2(0.0, texel.y)),
                    sampleNeighborCanvas(origin + vec2(0.0, texel.y)));
                if (outline > bestOutline) {
                    bestOutline = outline;
                    bestOrigin = origin;
                }
            }
            float pull = bestOutline * (0.35 + 0.65 * clamp(drive, 0.0, 1.0));
            uv = mix(uv, bestOrigin, pull);
            spatialDistortion = max(spatialDistortion, pull);
        }
    }

    if (blockAmt > 0.0005) {
        float a = clamp(blockAmt, 0.0, 1.0);
        vec2 cell = floor(uv / cellUV);
        vec2 h = hash22(cell + vec2(seed * 1.7, seed * 3.1));
        float alive = step(1.0 - a * 0.5, hash12(cell + vec2(seed * 7.3)));
        uv += (h - 0.5) * cellUV * 5.0 * a * alive;
        spatialDistortion = max(spatialDistortion, a * alive
            * smoothstep(0.08, 0.35, length(h - 0.5)));
    }

    float loose = 0.0;
    if (inTransition) {
        vec2 cell = floor(uv / cellUV);
        float scatter = hash12(cell * 1.13 + vec2(transitionSeed));
        float along01 = clamp(dot(uv, sortDir), 0.0, 1.0);
        float detach = mix(scatter, mix(along01, 1.0 - along01, rWaveDir), rWave);
        loose = clamp((tr - detach * rStagger) / max(1.0 - rStagger, 0.15), 0.0, 1.0);
        uv += sortDir * rSign * loose * loose * rTravel * (0.4 + scatter);
        uv += acrossDir * (hash12(cell + vec2(transitionSeed + 9.1)) - 0.5) * loose * rShear;
        spatialDistortion = max(spatialDistortion, loose);
    }

    if (sortAmt > 0.0005) {
        float along = dot(uv, sortDir);
        float across = dot(uv, acrossDir);
        float segLen = max(neighborSortLength, 0.002) * (0.35 + mid * 1.30);
        segLen += tr * tr * rStreak;
        segLen *= 0.5 + hash11(floor(across * 220.0) + seed * 0.37);
        float head = floor(along / segLen) * segLen;
        vec2 headUv = uv + sortDir * (head - along);
        float threshold = mix(neighborSortThreshold, -0.15, clamp(tr, 0.0, 1.0));
        float pick = smoothstep(threshold - 0.12, threshold + 0.12,
            luma(sampleNeighborCanvas(headUv)));
        uv = mix(uv, headUv, pick * clamp(sortAmt, 0.0, 1.0));
        spatialDistortion = max(spatialDistortion, pick * clamp(sortAmt, 0.0, 1.0));
    }

    vec3 col;
    if (caAmt > 0.02) {
        float primaryAspect = primaryRes.x / primaryRes.y;
        vec2 off = vec2(caAmt * 0.012 / primaryAspect, 0.0);
        off += (hash22(vec2(seed)) - 0.5) * caAmt * 0.004;
        col = vec3(sampleNeighborCanvas(uv + off).r, sampleNeighborCanvas(uv).g,
            sampleNeighborCanvas(uv - off).b);
    } else {
        col = sampleNeighborCanvas(uv);
    }

    if (pointAmt > 0.002) {
        float a = clamp(pointAmt, 0.0, 1.0);
        vec2 cellSize = vec2(max(neighborPointSpacing, 2.0)) / primaryRes;
        vec2 baseCell = floor(uv / cellSize);
        float best = 1e9;
        vec2 bestOrigin = uv;
        float bestSize = 1.0;
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                vec2 c = baseCell + vec2(float(i), float(j));
                vec2 origin = (c + 0.5) * cellSize;
                float cloudSeed = inTransition ? transitionSeed : 0.0;
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
        float radius = mix(0.80, 0.20, a) * bestSize;
        float mask = 1.0 - smoothstep(radius * 0.55, radius, best);
        col = mix(col, sampleNeighborCanvas(bestOrigin) * mask, a);
        spatialDistortion = max(spatialDistortion, a * mask);
    }

    float corrupt = clamp(blockAmt, 0.0, 1.0) * 0.12
        + loose * tr * mix(0.03, 0.25, trRand(195.3)) * clamp(trBlock, 0.0, 1.0);
    if (corrupt > 0.001) {
        float r = hash12(floor(canvasUv / (cellUV * 2.0)) + vec2(seed * 11.0));
        float swapped = step(1.0 - corrupt, r);
        col = mix(col, col.gbr, swapped);
        spatialDistortion = max(spatialDistortion, swapped * corrupt * 0.45);
    }
    if (noiseAmt > 0.001) {
        float n = hash12(canvasUv * primaryRes + vec2(fract(time) * 719.0));
        col += (n - 0.5) * noiseAmt * 0.25;
    }
    return vec4(clamp(col, 0.0, 1.0), clamp(spatialDistortion, 0.0, 1.0));
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 res = max(resolution, vec2(1.0));
    float aspect = res.x / res.y;

    float destroy = max(clamp(effectStrength, 0.0, 2.0), clamp(transition, 0.0, 2.0));
    // A seam exists only while it is being driven by live audio or the
    // primary's wallpaper switch. Silence restores the receiver's untouched
    // wallpaper instead of leaving a permanent static overlay behind.
    bool neighborSwitching = neighborTransitionPhase < 0.9999;
    bool hasNeighbourBleed = neighborBleed > 0.001 && neighborReady > 0.5
        && dot(neighborDirection, neighborDirection) > 0.5
        && (neighborEffectStrength > 0.0005 || neighborTransition > 0.0005
            || neighborSwitching);
    bool hasLocalLidar = lidarEnabled > 0.5;
    if (destroy <= 0.0005 && !hasNeighbourBleed && !hasLocalLidar) {
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
    float meltAmt  = meltAmount * routedAudioDrive(meltTrigger,
        e * (amb + bass * 0.80 + beat * 1.30), musicIntensity, beatIntensity, e) + tr * trMelt;
    // Beat weight kept well below the transition term on purpose: a kick should
    // stipple the picture, not dissolve it outright. Full scatter is reserved
    // for a wallpaper switch.
    float pointAmt = pointAmount * routedAudioDrive(pointTrigger,
        e * (amb * 0.15 + beat * 0.70), musicIntensity, beatIntensity, e) + tr * trPoint;
    float blockAmt = blockAmount * routedAudioDrive(blockTrigger,
        e * (amb * 0.3 + bass * 0.30 + beat * 0.45), musicIntensity, beatIntensity, e) + tr * trBlock;
    float sortAmt = sortAmount * routedAudioDrive(sortTrigger,
        e * (amb + mid * 0.60 + beat * 0.35), musicIntensity, beatIntensity, e) + tr * trSort;
    float fbAmt = feedbackAmount * routedAudioDrive(feedbackTrigger,
        e * (amb + bass * 0.45 + beat * 0.25), musicIntensity, beatIntensity, e) + tr * trFeedback;
    float caAmt = chromaticAberration * routedAudioDrive(aberrationTrigger,
        e * (amb + treble * 0.70 + beat * 0.45), musicIntensity, beatIntensity, e) + tr * trAberration;
    float noiseAmt = noiseAmount * routedAudioDrive(noiseTrigger,
        e * (amb + treble * 0.50 + beat * 0.25), musicIntensity, beatIntensity, e) + tr * trNoise;

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

    // --- 0. outline melt ---------------------------------------------------
    // Contours become the melt source rather than a spectrum-aligned corner.
    // The music controls filament length and intensity; the actual image tells
    // the shader which pixels should stretch, the same way LiDAR finds edges.
    if (meltAmt > 0.001) {
        float spectrumCoord = abs(sortDir.x) > 0.5 ? uv.y : uv.x;
        float level = clamp(texture(spectrum, vec2(clamp(spectrumCoord, 0.0, 1.0), 0.5)).r, 0.0, 1.0);
        level = max(level, tr * (0.35 + 0.65 * hash11(floor(spectrumCoord * 220.0) + transitionSeed)));
        float drive = clamp(meltAmt, 0.0, 1.5) * level;
        if (drive > 0.002) {
            float flowSign = (!inTransition || trAxisMode > 1.5 || trAxisSign > 0.0) ? 1.0 : -1.0;
            vec2 meltFlow = sortDir * flowSign;
            float detail = clamp(meltWidth * (inTransition ? rMeltW : 1.0) * 0.30, 1.0, 18.0);
            vec2 texel = vec2(detail) / res;
            float lengthSeed = hash12(floor(uv * res / max(detail * 2.0, 1.0))
                + vec2(inTransition ? transitionSeed : 0.0));
            float length = clamp(meltReach, 0.0, 1.0)
                * (0.08 + lengthSeed * 0.62) * clamp(drive, 0.0, 1.25);
            float bestOutline = 0.0;
            vec2 bestOrigin = uv;
            for (int i = 1; i <= 3; ++i) {
                vec2 origin = clamp(uv - meltFlow * length * (float(i) / 3.0), 0.0, 1.0);
                vec3 center = sampleBase(origin);
                float outline = imageOutline(center,
                    sampleBase(clamp(origin - vec2(texel.x, 0.0), 0.0, 1.0)),
                    sampleBase(clamp(origin + vec2(texel.x, 0.0), 0.0, 1.0)),
                    sampleBase(clamp(origin - vec2(0.0, texel.y), 0.0, 1.0)),
                    sampleBase(clamp(origin + vec2(0.0, texel.y), 0.0, 1.0)));
                if (outline > bestOutline) {
                    bestOutline = outline;
                    bestOrigin = origin;
                }
            }
            float pull = bestOutline * (0.35 + 0.65 * clamp(drive, 0.0, 1.0));
            uv = mix(uv, bestOrigin, pull);
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

    // --- 3c. cross-monitor seam bleed -------------------------------------
    // Both screens locally sample the wallpaper on their facing neighbour.
    // This is intentionally a full-edge *virtual bridge*, rather than only
    // the literal overlapping run of pixels: vertically offset monitors would
    // otherwise still look stitched together for most of their apparent seam.
    // It exists only while live audio or the primary's wallpaper switch is
    // driving it. The bridge derives its geometry from the same effect values
    // as the primary wallpaper, so it reads as the primary effect continuing
    // across the physical monitor boundary rather than as an overlay.
    if (hasNeighbourBleed) {
        float towardNeighbor = clamp(dot(uv - vec2(0.5), neighborDirection) + 0.5, 0.0, 1.0);
        float edgeDistance = 1.0 - towardNeighbor;
        // The source's destruction envelope alone is zero at both ends, which
        // made the borrowed image materialize at the middle of a switch and
        // disappear at the end. The shared phase gives the *new* source a
        // physical journey: source edge -> far edge of this monitor -> source
        // edge. Its body is never allowed to use the outgoing wallpaper.
        float switchPhase = clamp(neighborTransitionPhase, 0.0, 1.0);
        float switchSweep = sin(3.14159265 * switchPhase);
        float seamSwitch = max(clamp(neighborTransition, 0.0, 1.0), switchSweep);
        float bleedWidth = clamp(neighborBleedWidth, 0.04, 1.0);
        float alongEdge = abs(neighborDirection.x) > 0.5 ? uv.y : uv.x;
        float spectrumLevel = clamp(texture(spectrum, vec2(clamp(alongEdge, 0.0, 1.0), 0.5)).r, 0.0, 1.0);
        float audioEnvelope = clamp(neighborEffectStrength, 0.0, 1.25);
        float defaultLidarPulse = clamp(bass * 0.40 + beat * 0.85 + volume * 0.20, 0.0, 1.25);
        float audioPulse = routedAudioDrive(lidarTrigger, defaultLidarPulse,
            musicIntensity, beatIntensity, audioEnvelope);
        float regularDrive = clamp(max(audioEnvelope, seamSwitch), 0.0, 1.0);
        float sourceAmb = 0.15 + volume * 0.35;
        float bridgeBlock = clamp(neighborBlockAmount * audioEnvelope
            * (sourceAmb * 0.30 + bass * 0.30 + beat * 0.45) + seamSwitch * trBlock, 0.0, 1.0);
        float bridgeSort = clamp(neighborSortAmount * audioEnvelope
            * (sourceAmb + mid * 0.60 + beat * 0.35) + seamSwitch * trSort, 0.0, 1.0);

        // This mask only locates the borrowed canvas on the physical edge. It
        // does not create an FFT picture of its own: every visible colour and
        // distortion inside it comes from sampleNeighborExtension(), which
        // replays the normal primary wallpaper pipeline above.
        float grainPixels = max(2.0, neighborBlockSize * (0.80 + bridgeBlock * 1.20)
            * clamp(neighborBleedGrain, 0.25, 4.0));
        vec2 bridgeCellSize = vec2(grainPixels) / res;
        vec2 bridgeCell = floor(uv / bridgeCellSize);
        float dynamicEdgeWidth = bleedWidth * clamp(0.22 + regularDrive * 0.78
            + seamSwitch * 0.20, 0.0, 1.0);
        // The maximum setting is an intentional full-canvas idle mode:
        // fragments can reach the far edge even between quieter beats.
        float fullCanvas = smoothstep(0.94, 1.0, bleedWidth);
        // A configured full-width idle seam must not bypass the travel mask
        // during a wallpaper change. That used to make the old frame appear
        // across the receiver at once. While switching, the mask is anchored
        // to the source-facing edge and expands/retracts continuously.
        float transitionEdgeWidth = switchSweep * 1.04;
        float idleEdgeWidth = mix(dynamicEdgeWidth, 1.15, fullCanvas);
        float edgeWidth = neighborSwitching ? transitionEdgeWidth : idleEdgeWidth;
        float cellRag = hash12(bridgeCell + vec2(transitionSeed * 0.041,
            floor(time * 15.0 * clamp(neighborBleedMotionSpeed, 0.0, 4.0))
            * (0.8 + bridgeBlock * 1.6))) - 0.5;
        float raggedEdge = cellRag * grainPixels / max(res.x, res.y)
            * (0.5 + bridgeBlock * 4.5) * clamp(neighborBleedRaggedness, 0.0, 2.0);
        float baseSeam = 1.0 - smoothstep(max(edgeWidth
            * clamp(neighborBleedEdgeSoftness, 0.01, 0.98), 0.001),
            max(edgeWidth, 0.002), edgeDistance + raggedEdge);

        // `bridgeUv` stays in the receiver's real coordinates. After mapping
        // into virtual-primary coordinates below, the primary effect pipeline
        // itself decides every melt, block and sort displacement. That is the
        // crucial difference from a bespoke FFT seam: this is an extension of
        // the primary canvas, not a second effect painted over this monitor.
        vec2 bridgeUv = uv;
        vec2 virtualBridgeUv = neighborCanvasOrigin + bridgeUv * neighborCanvasScale;
        // The extension exports only fragments that the primary pipeline moved
        // geometrically; plain source pixels and cosmetic RGB/noise remain on
        // the primary monitor.
        vec3 rawPrimary = sampleNeighborCanvas(virtualBridgeUv);
        vec4 primaryExtension = sampleNeighborExtension(virtualBridgeUv,
            audioEnvelope, neighborTransition);
        vec3 baseNeighbour = primaryExtension.rgb;
        float baseMask = baseSeam;
        float geometricMask = smoothstep(clamp(neighborBleedFragmentThreshold, 0.0, 1.0),
            clamp(neighborBleedFragmentThreshold + neighborBleedFragmentSoftness, 0.001, 1.0),
            primaryExtension.a);
        // Colour trails are intentionally saturation-aware. Bright but neutral
        // noise/white lines do not satisfy this gate, while the vivid channel
        // separation from a colourful primary preset can travel with the seam.
        vec3 colourDelta = abs(primaryExtension.rgb - rawPrimary);
        float deltaMagnitude = length(colourDelta);
        float colourSaturation = max(max(colourDelta.r, colourDelta.g), colourDelta.b)
            - min(min(colourDelta.r, colourDelta.g), colourDelta.b);
        float colourMask = smoothstep(clamp(neighborBleedColorThreshold, 0.0, 1.0),
            clamp(neighborBleedColorThreshold + neighborBleedColorSoftness, 0.001, 1.0),
            deltaMagnitude) * smoothstep(0.035, 0.20, colourSaturation);
        float fragmentsMask = max(geometricMask, neighborBleedColorTrails > 0.5
            ? colourMask * clamp(neighborBleedColorStrength, 0.0, 1.5) : 0.0);
        // A transition has to carry a continuous distorted ribbon as it crosses
        // the seam. Without this floor, only individually detached blocks pass
        // the geometric test, so the handover pops up in random islands and
        // vanishes before it can visibly return to the source edge.
        float transitionRibbon = smoothstep(0.015, 0.24, seamSwitch);
        fragmentsMask = max(fragmentsMask, transitionRibbon);
        // A seam never carries a clean copy of the source wallpaper. Lift the
        // weaker valid fragments so they stay legible, while zero remains zero
        // and the untouched receiver wallpaper is never overwritten.
        float distortionMask = sqrt(clamp(fragmentsMask, 0.0, 1.0));

        // A LiDAR pass scans imported fragments only, never the receiver
        // wallpaper. The outline mode derives its mask from the source
        // wallpaper's luminance and colour edges, then makes that outline
        // pulse with the same spectrum and beat that drive the seam.
        if (neighborBleedLidar > 0.5) {
            vec2 scanAxis = abs(neighborDirection.x) > 0.5
                ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
            float scanCoord = dot(virtualBridgeUv, scanAxis);
            float lidarDensity = clamp(neighborBleedLidarDensity, 4.0, 96.0);
            float lidarSpeed = clamp(neighborBleedLidarSpeed, 0.0, 4.0);
            float lidarPattern;
            if (neighborBleedLidarOutlines > 0.5) {
                // Density becomes edge-detail here: a high setting samples a
                // tighter source neighbourhood and preserves fine contours.
                float outlineDetail = mix(4.0, 0.75, (lidarDensity - 4.0) / 92.0);
                vec2 outlineTexel = vec2(outlineDetail) / max(neighborCanvasResolution, vec2(1.0));
                vec3 sourceLeft = sampleNeighborCanvas(clamp(virtualBridgeUv - vec2(outlineTexel.x, 0.0), 0.0, 1.0));
                vec3 sourceRight = sampleNeighborCanvas(clamp(virtualBridgeUv + vec2(outlineTexel.x, 0.0), 0.0, 1.0));
                vec3 sourceUp = sampleNeighborCanvas(clamp(virtualBridgeUv - vec2(0.0, outlineTexel.y), 0.0, 1.0));
                vec3 sourceDown = sampleNeighborCanvas(clamp(virtualBridgeUv + vec2(0.0, outlineTexel.y), 0.0, 1.0));
                vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
                float lumaEdge = abs(dot(sourceRight - sourceLeft, lumaWeights))
                    + abs(dot(sourceDown - sourceUp, lumaWeights));
                float colourEdge = max(max(length(rawPrimary - sourceLeft), length(rawPrimary - sourceRight)),
                    max(length(rawPrimary - sourceUp), length(rawPrimary - sourceDown)));
                float outlineMask = smoothstep(0.08, 0.50, max(lumaEdge * 1.25, colourEdge * 0.55));
                float pulsePhase = fract(scanCoord * lidarDensity * 0.35 - time * lidarSpeed * 0.35);
                float pulseBand = 0.35 + 0.65 * (1.0 - smoothstep(0.08, 0.42, abs(pulsePhase - 0.5)));
                float audioGlow = clamp(0.18 + audioPulse * 0.62 + spectrumLevel * 0.35, 0.0, 1.0);
                lidarPattern = outlineMask * pulseBand * audioGlow;
            } else {
                float scanPhase = fract(scanCoord * lidarDensity - time * lidarSpeed);
                float raster = 1.0 - smoothstep(0.012, 0.055, min(scanPhase, 1.0 - scanPhase));
                float sweepPhase = fract(scanCoord - time * lidarSpeed * 0.16);
                float sweep = 1.0 - smoothstep(0.025, 0.11, abs(sweepPhase - 0.5));
                lidarPattern = max(raster * 0.35, sweep);
            }
            float lidarMask = lidarPattern * baseMask * distortionMask
                * clamp(neighborBleedLidarStrength, 0.0, 1.0);
            vec3 lidarColour = mix(vec3(0.04, 0.95, 0.42), vec3(0.05, 0.72, 1.0), spectrumLevel);
            baseNeighbour = clamp(baseNeighbour + lidarColour * lidarMask, 0.0, 1.0);
        }

        // The borrowed primary is a translucent overlay. The receiver remains
        // underneath it, but it never fights back or contributes feedback, so
        // every visible fragment in this layer belongs to the source monitor.
        float overlay = baseMask * distortionMask * neighborBleed
            * (0.58 + bridgeSort * 0.16) * clamp(neighborBleedStrength, 0.0, 1.5);
        col = mix(col, baseNeighbour, clamp(overlay, 0.0, 0.78));
    }

    // --- 3d. local LiDAR ---------------------------------------------------
    // The same controls that accent a seam can also scan the wallpaper in its
    // own window. In outline mode the mask comes from the current source image
    // at the already-displaced UV, so its contours sit on the same melt/block/
    // sort result instead of being a separate overlay.
    if (hasLocalLidar) {
        float lidarDensity = clamp(neighborBleedLidarDensity, 4.0, 96.0);
        float lidarSpeed = clamp(neighborBleedLidarSpeed, 0.0, 4.0);
        float scanCoord = uv.y;
        float spectrumLevel = clamp(texture(spectrum, vec2(clamp(uv.x, 0.0, 1.0), 0.5)).r, 0.0, 1.0);
        float defaultLidarPulse = clamp(bass * 0.40 + beat * 0.85 + volume * 0.20, 0.0, 1.25);
        float audioPulse = routedAudioDrive(lidarTrigger, defaultLidarPulse,
            musicIntensity, beatIntensity, e);
        float lidarPattern;

        if (neighborBleedLidarOutlines > 0.5) {
            float outlineDetail = mix(4.0, 0.75, (lidarDensity - 4.0) / 92.0);
            vec2 outlineTexel = vec2(outlineDetail) / res;
            vec3 sourceCenter = sampleBase(uv);
            vec3 sourceLeft = sampleBase(clamp(uv - vec2(outlineTexel.x, 0.0), 0.0, 1.0));
            vec3 sourceRight = sampleBase(clamp(uv + vec2(outlineTexel.x, 0.0), 0.0, 1.0));
            vec3 sourceUp = sampleBase(clamp(uv - vec2(0.0, outlineTexel.y), 0.0, 1.0));
            vec3 sourceDown = sampleBase(clamp(uv + vec2(0.0, outlineTexel.y), 0.0, 1.0));
            vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
            float lumaEdge = abs(dot(sourceRight - sourceLeft, lumaWeights))
                + abs(dot(sourceDown - sourceUp, lumaWeights));
            float colourEdge = max(max(length(sourceCenter - sourceLeft), length(sourceCenter - sourceRight)),
                max(length(sourceCenter - sourceUp), length(sourceCenter - sourceDown)));
            float outlineMask = smoothstep(0.08, 0.50, max(lumaEdge * 1.25, colourEdge * 0.55));
            float pulsePhase = fract(scanCoord * lidarDensity * 0.35 - time * lidarSpeed * 0.35);
            float pulseBand = 0.35 + 0.65 * (1.0 - smoothstep(0.08, 0.42, abs(pulsePhase - 0.5)));
            float audioGlow = clamp(0.18 + audioPulse * 0.62 + spectrumLevel * 0.35, 0.0, 1.0);
            lidarPattern = outlineMask * pulseBand * audioGlow;
        } else {
            float scanPhase = fract(scanCoord * lidarDensity - time * lidarSpeed);
            float raster = 1.0 - smoothstep(0.012, 0.055, min(scanPhase, 1.0 - scanPhase));
            float sweepPhase = fract(scanCoord - time * lidarSpeed * 0.16);
            float sweep = 1.0 - smoothstep(0.025, 0.11, abs(sweepPhase - 0.5));
            lidarPattern = max(raster * 0.35, sweep);
        }

        float lidarMask = lidarPattern * clamp(neighborBleedLidarStrength, 0.0, 1.0);
        vec3 lidarColour = mix(vec3(0.04, 0.95, 0.42), vec3(0.05, 0.72, 1.0), spectrumLevel);
        col = clamp(col + lidarColour * lidarMask, 0.0, 1.0);
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
    // This is the colour half of Block corruption, not a general audio effect.
    // It used to be driven from `e` alone, so it could still swap RGB blocks
    // with the Block corruption slider at zero. Keep both the live and the
    // transition contribution explicitly tied to their respective block
    // amounts: zero now means no block displacement *and* no colour corruption.
    float corrupt = clamp(blockAmt, 0.0, 1.0) * 0.12
        + loose * tr * rCorrupt * clamp(trBlock, 0.0, 1.0);
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
