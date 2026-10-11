// World-space mist shared by the air march and its numerical checks.
static float air_range(constant FrameData &frame) {
    return min(max(frame.airParams.x, 32.0), max(frame.fogParams.y, 32.0) * 0.98);
}

// Smooth, bounded value noise: world coordinates anchor the banks; slow wind is their only motion.
static float air_hash(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

static float air_noise(float2 p) {
    float2 cell = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(air_hash(cell), air_hash(cell + float2(1,0)), f.x),
               mix(air_hash(cell + float2(0,1)), air_hash(cell + float2(1,1)), f.x), f.y);
}

// The fog's noise straight from the hash: the reference, and what the numerical checks use.
struct AirHashNoise {
    float sample(float2 p) const { return air_noise(p); }
};

// The same noise from a table of air_hash over AIR_NOISE_TABLE cells (air_noise_table_fragment), repeating every
// AIR_NOISE_TABLE cells (over 9000 blocks for the finest octave). One filtered texture read replaces four hashes: the
// smoothstep is applied to the coordinate, so the hardware's bilinear filter interpolates exactly as air_noise does.
constant float AIR_NOISE_TABLE = 256.0;

struct AirTableNoise {
    texture2d<float> table;
    float sample(float2 p) const {
        constexpr sampler repeat(filter::linear, address::repeat);
        float2 cell = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return table.sample(repeat, (cell + 0.5 + f) / AIR_NOISE_TABLE, level(0)).r;
    }
};

// What the density needs from the frame alone, worked out once per ray rather than at every step.
struct AirMedium {
    float3 scale;  // ground mist, veil and haze densities at the base height
    float2 drift;  // wind offset of the banks
    float base;    // mist base height
};

static AirMedium air_medium(constant FrameData &frame) {
    float sunHeight = frame.solarDir.w > 0.5 ? frame.solarDir.y : frame.sunDir.y;
    float dawn = exp(-pow((sunHeight - 0.08) / 0.28, 2.0));
    AirMedium medium;
    medium.scale = float3(0.0026 * (0.55 + 0.75 * dawn), 0.0022, 0.00070) * frame.fogParams.z
                 * smoothstep(0.1, 0.6, frame.fogParams.x) * frame.airParams.z;
    medium.drift = float2(frame.params.x * 0.07, frame.params.x * 0.035);
    medium.base = frame.airParams.y;
    return medium;
}

template <typename Noise>
static float3 air_density_layers(AirMedium medium, Noise noise, float3 world) {
    float height = max(world.y - medium.base, 0.0);
    float2 p = world.xz + medium.drift;
    float broad = noise.sample(p / 110.0), detail = noise.sample(p / 37.0 + float2(19.7, -6.3));
    float banks = smoothstep(0.20, 0.78, broad * 0.72 + detail * 0.28);
    // Keep a continuous scattering medium through treetops and hills, not only at sea level.
    // Banks shape the low mist; the broader veil keeps shafts visible between those banks.
    float ground = exp(-height / 22.0) * (0.22 + 0.78 * banks);
    float veil = exp(-height / 72.0) * (0.65 + 0.35 * broad);
    float haze = exp(-height / 210.0);
    return float3(ground, veil, haze) * medium.scale;
}

// An inexpensive directional atmosphere palette, inspired by scattering rather than an HDR atmosphere solver.
// Uses the actual solar elevation, so twilight stays continuous when the shadow light switches to the moon.
static float3 atmosphere_sky(constant FrameData &frame, float3 direction) {
    if (frame.solarDir.w < 0.5) return frame.skyColor.rgb;
    float3 V = normalize(direction), sun = frame.solarDir.xyz;
    float day = smoothstep(-0.16, 0.16, sun.y);
    float twilight = exp(-pow((sun.y + 0.015) / 0.18, 2.0));
    float horizon = exp(-max(V.y, 0.0) * 4.8);
    // A soft daytime sky: a clean mid blue overhead, paling to a light, slightly hazy blue towards the horizon.
    float haze = pow(1.0 - saturate(V.y), 2.6);
    // A low sun (morning, evening) washes the whole sky towards lavender and pink, not only the horizon.
    float low = 1.0 - smoothstep(0.02, 0.9, sun.y);
    float towardSun = saturate(dot(normalize(float3(V.x, 0.03, V.z)), normalize(float3(sun.x, 0.03, sun.z))));
    float3 dayZenith = mix(float3(0.25, 0.44, 0.70), float3(0.52, 0.47, 0.76), low);
    float3 dayHorizon = mix(float3(0.68, 0.82, 0.94), float3(0.92, 0.70, 0.66), low);
    float3 night = mix(float3(0.006, 0.012, 0.034), float3(0.030, 0.048, 0.090), horizon);
    float3 daylight = mix(dayZenith, dayHorizon, haze);
    // Towards the sun the haze glows bright and warm.
    daylight += mix(float3(0.12, 0.085, 0.05), float3(0.30, 0.22, 0.0), low) * pow(towardSun, 2.0) * haze * (0.35 + 0.35 * low);
    float3 colour = mix(night, daylight, day);
    float sunset = twilight * horizon * (0.12 + 0.88 * pow(towardSun, 3.0));
    colour = mix(colour, float3(0.80, 0.61, 0.35), sunset * 0.92);
    // A softer violet band opposite the sun instead of a uniformly orange sky.
    colour += float3(0.075, 0.017, 0.065) * twilight * horizon * pow(1.0 - towardSun, 2.0);
    float forward = pow(saturate(dot(V, sun)), 18.0);
    colour += float3(0.13, 0.09, 0.045) * forward * day * (1.0 - frame.params.y);
    float rain = saturate(frame.params.y);
    float3 overcast = mix(float3(0.014, 0.018, 0.026), float3(0.46, 0.45, 0.44), day);
    overcast *= mix(0.82, 1.15, horizon);
    return max(mix(colour, overcast, rain * 0.88), 0.0);
}

// --- soft clouds ---
// One layer of soft-edged clouds at the game's cloud height, in place of its blocky ones: where they are is a
// function of the world position alone (cloud_cover), so the sky draws them (cloud_layer) and the light's cloud map
// shades the ground under the same shapes (soft_cloud_map_fragment).
constant float CLOUD_SCALE = 640.0;     // blocks across the broadest shapes
constant float CLOUD_DRIFT = 1.4;       // blocks per second, towards +x
constant float CLOUD_TRANSMISSION_SOFT = 0.58; // of the sunlight, through the thickest part

constant float CLOUD_THICKNESS = 230.0; // blocks, base to top
constant int CLOUD_STEPS = 5;

// Broad shapes decide where the clouds are, finer ones only ruffle their edges. About 0 to 1, mostly near 0.5.
static float cloud_field(float2 p, float time) {
    float2 q = (p + float2(time * CLOUD_DRIFT, 0.0)) / CLOUD_SCALE;
    float broad = air_noise(q) * 0.62 + air_noise(q * 2.13 + float2(7.3, 1.9)) * 0.38;
    float fine = air_noise(q * 5.1 + float2(-3.1, 5.7)) * 0.62 + air_noise(q * 11.3 + float2(2.2, -8.4)) * 0.38;
    return broad + (fine - 0.5) * 0.22;
}

static float cloud_threshold(float rain) {
    return mix(0.58, 0.05, saturate(rain)); // rain: one unbroken grey deck
}

// How much cloud is over the world position `p` (xz), seen from above or below: x where there is cloud at all (a
// soft edge), y how thick it is there, both 0 to 1.
static float2 cloud_cover(float2 p, float time, float rain) {
    float n = cloud_field(p, time);
    float threshold = cloud_threshold(rain);
    return float2(smoothstep(threshold, threshold + 0.06, n), smoothstep(threshold, threshold + 0.26, n));
}

// The clouds over `sky` looking along `direction` from the camera. The layer has some height: a few samples up
// through it, each a slice of the same shapes, widest a quarter of the way up and narrowing to a rounded top, so a
// cloud seen from the side is a heap with a flat base and not a flat patch stretched towards the horizon.
// `covered` gets how much of the sky they hide there, 0 to 1. `dither` (0 to 1) shifts the slices up or down by up to
// one slice: different for every pixel and frame, it turns the steps between slices, plain to see where the layer is
// looked at from the side, into grain that the temporal anti-aliasing smooths away.
static float3 cloud_layer(constant FrameData &frame, float3 direction, float3 sky, thread float &covered, float dither = 0.5) {
    covered = 0.0;
    // (No clouds in the frame: a huge negative number. MetalShaders.SOFT_CLOUD_LIFT puts the layer above the build height.)
    float base = frame.cameraPos.w;
    if (frame.solarDir.w < 0.5 || base <= 0.0 || direction.y <= 0.012) return sky;
    float rain = frame.params.y;
    float threshold = cloud_threshold(rain);
    float day = mix(0.07, 1.0, frame.lightParams.x);
    // In the shade the sky's colour with a little rose; bright where the light reaches: the tops, and the side
    // turned to the light (one more look-up a little way towards it tells how much cloud it crossed to get here).
    float3 shade = frame.surfaceAmbient.rgb * float3(1.40, 1.22, 1.34);
    float3 sun = frame.surfaceSun.rgb * (0.78 * frame.sunDir.w);
    float2 toLight = normalize(frame.sunDir.xz + float2(1e-4, 0.0)) * (1.0 - 0.6 * abs(frame.sunDir.y));
    float2 middle = frame.cameraPos.xz + direction.xz * ((base + 0.3 * CLOUD_THICKNESS) / direction.y);
    float crossed = cloud_cover(middle + toLight * 170.0, frame.params.x, rain).y;
    float3 colour = float3(0.0);
    float through = 1.0;
    for (int i = 0; i < CLOUD_STEPS && through > 0.03; i++) {
        float h = (float(i) + dither) / float(CLOUD_STEPS);
        float2 p = frame.cameraPos.xz + direction.xz * ((base + h * CLOUD_THICKNESS) / direction.y);
        float narrowing = h < 0.25 ? (0.25 - h) * 0.25 : pow((h - 0.25) / 0.75, 1.6) * 0.24;
        float edge = threshold + narrowing;
        float density = smoothstep(edge, edge + 0.05, cloud_field(p, frame.params.x));
        if (density <= 0.0) continue;
        float lit = saturate(0.42 + 0.75 * h) * (1.0 - 0.5 * crossed);
        float opacity = density * 0.62;
        colour += (shade + sun * lit) * (through * opacity);
        through *= 1.0 - opacity;
    }
    float cover = 1.0 - through;
    if (cover <= 0.0) return sky;
    colour = colour / cover * day;
    colour = mix(colour, float3(0.47, 0.47, 0.48) * day, saturate(rain)); // rain: a flat, pale grey deck
    // Towards the horizon the layer thins into the haze.
    float fade = exp(-base / direction.y / 6000.0) * smoothstep(0.012, 0.09, direction.y);
    covered = cover * fade;
    return mix(sky, colour, covered);
}

static float3 cloud_layer(constant FrameData &frame, float3 direction, float3 sky) {
    float covered;
    return cloud_layer(frame, direction, sky, covered);
}

static float3 atmosphere_ambient(constant FrameData &frame) {
    if (frame.solarDir.w < 0.5) return frame.skyColor.rgb * mix(0.18, 0.65, frame.lightParams.x);
    // A hemisphere approximation: blue overhead fill mixed with light from the warm/cool horizon.
    return (atmosphere_sky(frame, float3(0,1,0)) * 0.60
          + atmosphere_sky(frame, float3(1,0.12,0)) * 0.20
          + atmosphere_sky(frame, float3(-1,0.12,0)) * 0.20) * 0.70;
}

static float3 atmosphere_shadow_tint(constant FrameData &frame) {
    if (frame.solarDir.w < 0.5) return float3(0.80, 0.88, 1.08);
    float3 ambient = atmosphere_ambient(frame);
    float luminance = max(dot(ambient, float3(0.2126,0.7152,0.0722)), 0.02);
    return mix(float3(1.0), clamp(ambient / luminance, 0.55, 1.35), 0.55);
}

static float air_phase(float cosine) {
    // A forward lobe for sun-facing shafts plus a broad lobe for oblique views through mist.
    // The mixture widens the visible beam without an excessive spike looking straight at the sun.
    float2 g = float2(0.5, 0.25);
    float2 hg = (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * clamp(cosine, -1.0, 1.0), 0.01), 1.5);
    return 0.10 + 0.16 * dot(hg, float2(0.55, 0.45));
}

struct AirVolume {
    float3 scattering;
    float transmittance;
    float moment; // opacity-weighted distance for volume history reprojection
};

static void air_integrate(thread AirVolume &volume, float density, float width, float distance, float3 incident) {
    float segment = exp(-max(density * width, 0.0));
    float weight = volume.transmittance * (1.0 - segment);
    volume.scattering += incident * weight;
    volume.moment += distance * weight;
    volume.transmittance *= segment;
}
