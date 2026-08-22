const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");

const v3 = mathx.v3;

// THE WORLD CLOCK — one number, `hour`, and everything the light does is a function of it.
//
// **ONE DIRECTION CASTS, AND IT IS THE SAME ONE THE SHADER KEYS OFF** (AGENTS.md: "Sun + shadows are ONE
// source"). `keyDir` is the whole of it: the SUN while it is up, the MOON once it is down.
//
// **THE SKY DRAWS THE TRUE PATH; THE SHADOWS DO NOT.** A sun at two degrees throws a 300 m shadow, which the
// 108 m ortho box cannot hold, so `keyDir` FLOORS the altitude (`KEY_ALT_MIN`) while `sunDir`/`moonDir` keep
// the honest angle for the disc.
//
// **THE ANCHOR IS NOT A KEYFRAME.** `SHOT_HOUR` reproduces the sun this game was authored under
// (`shots.LIT_YAW` = 53). Retuning the path without moving the anchor silently re-lights 362 photographs.

pub const HOURS: f32 = 24.0;
pub const SUNRISE: f32 = 6.0;
pub const SUNSET: f32 = 20.0;
pub const DAY_SPAN: f32 = SUNSET - SUNRISE;
pub const NIGHT_SPAN: f32 = HOURS - DAY_SPAN;

/// The bearings the sun rises and sets on, in degrees of `mathx.headingXZ` (0 = +Z).
const AZ_RISE: f32 = 100.0;
const AZ_SET: f32 = 262.0;

/// THE ANCHOR, and the two constants below are SOLVED from it. `gfx.SUN_DIR` = norm(-0.60, 0.50, -0.46) is
/// bearing 180 + atan(0.60/0.46) = 232.5256 deg at altitude atan(0.50 / hypot(0.60, 0.46)) = 33.4793 deg; that
/// bearing is 0.8180593 of the `AZ_RISE`..`AZ_SET` sweep, giving the hour, and the altitude is that fraction of
/// the arch's sine, giving the peak: 33.4793 / sin(pi * 0.8180593) = 61.8895. **MOVE `AZ_RISE`/`AZ_SET` AND BOTH MOVE WITH THEM** — solve them again, do not nudge them.
pub const SUN_ALT_MAX: f32 = 61.8895;
pub const SHOT_HOUR: f32 = 17.45283;

/// 9 pm, and **the sun is DOWN there** (owner's call) — deliberately NOT `SHOT_HOUR`, which is the golden hour with the sun well up. An hour past `SUNSET`, pinned past the horizon by a comptime assert.
pub const EVENING_HOUR: f32 = 21.0;
comptime {
    std.debug.assert(EVENING_HOUR > SUNSET);
}

const KEY_ALT_MIN: f32 = 15.0;

/// **NOT SUNRISE AND SUNSET.** The moon is the ANTI-sun, so the handover turns the key most of the way round the
/// compass: swapped on `isDay` it lands at 20:00 and measured 179.9 degrees in a hundredth of an hour with the
/// key still at half the anchor's brightness. The swap sits at the DIMMEST hours of each ramp instead. **`isDay` IS NOT TOUCHED** — this is the CASTER's question.
const KEY_SWAP_DAWN: f32 = 5.0;
const KEY_SWAP_DUSK: f32 = 20.8;

comptime {
    std.debug.assert(KEY_SWAP_DAWN < SUNRISE);
    std.debug.assert(KEY_SWAP_DUSK > SUNSET);
}

/// HOW LONG THE HANDOVER TAKES, in hours either side of the swap hour. **THE TWO CASTERS ARE FADED TOGETHER RATHER THAN SWITCHED** (owner's call), so the eye gets the light SWEEPING round. Kept inside the dim band, so the sweep never runs during sunset.
const KEY_SWAP_FADE: f32 = 0.45;

fn moonShare(hour: f32) f32 {
    const h = wrapHour(hour);
    // The dusk crossing, and the dawn one measured the same way on the other side of midnight. Both windows are well inside the night, which the comptime block above pins.
    if (h > SUNSET) return mathx.smoothstep(KEY_SWAP_DUSK - KEY_SWAP_FADE, KEY_SWAP_DUSK + KEY_SWAP_FADE, h);
    if (h < SUNRISE) return 1.0 - mathx.smoothstep(KEY_SWAP_DAWN - KEY_SWAP_FADE, KEY_SWAP_DAWN + KEY_SWAP_FADE, h);
    return 0;
}

const KEY_SWEEP: f32 = if (AZ_SET > AZ_RISE) 1.0 else -1.0;

pub const DAY_MINUTES: f32 = 20.0;
pub const RATE_DEFAULT: f32 = HOURS / (DAY_MINUTES * 60.0);

pub fn wrapHour(h: f32) f32 {
    if (!std.math.isFinite(h)) return SHOT_HOUR;
    const r = @rem(h, HOURS);
    return if (r < 0) r + HOURS else r;
}

pub const RATE_MULTS = [_]f32{ 1, 4, 20, 120 };

pub const Clock = struct {
    hour: f32 = SHOT_HOUR,
    rate: f32 = RATE_DEFAULT,
    /// THE RATE A HOLD COMES BACK TO, so the two debug rows cannot fight: pick a speed, hold the clock, let it go, and it runs at the speed you picked.
    resumeRate: f32 = RATE_DEFAULT,

    pub fn tick(self: *Clock, dt: f32) void {
        if (self.rate == 0) return;
        self.hour = wrapHour(self.hour + self.rate * dt);
    }
    pub fn set(self: *Clock, h: f32) void {
        self.hour = wrapHour(h);
    }
    pub fn nudge(self: *Clock, dh: f32) void {
        self.set(self.hour + dh);
    }
    pub fn frozen(self: *const Clock) bool {
        return self.rate == 0;
    }
    pub fn freeze(self: *Clock, on: bool) void {
        if (!on) {
            self.rate = self.resumeRate;
            return;
        }
        if (self.rate != 0) self.resumeRate = self.rate;
        self.rate = 0;
    }

    pub fn speed(self: *const Clock) f32 {
        return (if (self.rate == 0) self.resumeRate else self.rate) / RATE_DEFAULT;
    }

    /// …and how long a whole day takes at that speed, in REAL seconds — what the debug row says, since "120x" means nothing and "10 s/day" is the thing you are about to watch.
    pub fn dayLen(self: *const Clock) f32 {
        return HOURS / mathx.maxF(self.speed() * RATE_DEFAULT, 1e-6);
    }

    pub fn cycleSpeed(self: *Clock) void {
        const cur = self.speed();
        var at: usize = 0;
        var best: f32 = std.math.floatMax(f32);
        for (RATE_MULTS, 0..) |m, i| {
            const err = @abs(m - cur);
            if (err >= best) continue;
            best = err;
            at = i;
        }
        self.resumeRate = RATE_DEFAULT * RATE_MULTS[(at + 1) % RATE_MULTS.len];
        if (self.rate != 0) self.rate = self.resumeRate;
    }
};

pub fn dayLenText(c: *const Clock, buf: []u8) [:0]const u8 {
    const s = c.dayLen();
    if (s >= 90.0) return std.fmt.bufPrintZ(buf, "{d:.0} min", .{s / 60.0}) catch "?";
    return std.fmt.bufPrintZ(buf, "{d:.0} s", .{s}) catch "?";
}


fn dayU(hour: f32) f32 {
    const h = wrapHour(hour);
    if (h >= SUNRISE and h <= SUNSET) return (h - SUNRISE) / DAY_SPAN;
    // Night: measured FORWARD from sunset, wrapping through midnight, so 24:00 and 00:00 are the same point.
    const past = if (h > SUNSET) h - SUNSET else h + (HOURS - SUNSET);
    return 1.0 + past / NIGHT_SPAN;
}

pub fn isDay(hour: f32) bool {
    const h = wrapHour(hour);
    return h >= SUNRISE and h <= SUNSET;
}

/// HOW FAR THROUGH ITS OWN SPAN THE HOUR IS: 0 at the horizon it left and 1 at the one it is heading for, for whichever span `isDay` says it is in. Off `dayU`, the same progression the sun's azimuth is swept by, so a dial drawn from it cannot disagree with the light behind it.
pub fn spanU(hour: f32) f32 {
    const u = dayU(hour);
    return if (u <= 1.0) u else u - 1.0;
}

pub fn dayAmt(hour: f32) f32 {
    if (!isDay(hour)) return 0;
    return mathx.sinf(std.math.pi * dayU(hour));
}

fn dirFrom(azDeg: f32, altDeg: f32) rl.Vector3 {
    const az = mathx.radians(azDeg);
    const alt = mathx.radians(altDeg);
    const c = mathx.cosf(alt);
    return v3(mathx.sinf(az) * c, mathx.sinf(alt), mathx.cosf(az) * c);
}

pub fn sunDir(hour: f32) rl.Vector3 {
    const u = dayU(hour);
    const alt = SUN_ALT_MAX * mathx.sinf(std.math.pi * u);
    // **THE BEARING GOES ALL THE WAY ROUND ONCE A DAY, AND THE NIGHT CARRIES THE PART OF THE CIRCLE THE DAY DOES NOT.** Swept at the day's own rate through the night, `u = 2` lands 36 degrees short of a full turn on a 162 degree day, so at 06:00 every shadow steps 36 degrees sideways on one frame.
    const az = if (u <= 1.0)
        AZ_RISE + (AZ_SET - AZ_RISE) * u
    else
        AZ_SET + (360.0 - (AZ_SET - AZ_RISE)) * (u - 1.0);
    return dirFrom(az, alt);
}

pub fn moonDir(hour: f32) rl.Vector3 {
    const s = sunDir(hour);
    return v3(-s.x, -s.y, -s.z);
}

pub fn keyDir(hour: f32) rl.Vector3 {
    const s = sunDir(hour);
    const share = moonShare(hour);
    const az = std.math.atan2(s.x, s.z) + std.math.pi * share * KEY_SWEEP;
    const alt = std.math.asin(mathx.clampF(s.y, -1, 1)) * (1.0 - 2.0 * share);
    // …AND THE FLOOR, which is what makes a caster under the horizon usable at all: the altitude crosses zero inside every handover, and a key coming from the horizon casts a shadow the depth box cannot hold. Held ON the floor through the crossing, so what moves there is the BEARING alone.
    const minY = mathx.sinf(mathx.radians(KEY_ALT_MIN));
    const y = mathx.maxF(mathx.sinf(alt), minY);
    const c = @sqrt(mathx.maxF(0, 1.0 - y * y));
    return v3(mathx.sinf(az) * c, y, mathx.cosf(az) * c);
}

pub fn shadowReach(hour: f32) f32 {
    return reachOf(keyDir(hour));
}

pub fn reachOf(d: rl.Vector3) f32 {
    return mathx.lenXZ(d) / mathx.maxF(d.y, 1e-3);
}


pub const Palette = struct {
    /// The KEY, colour and strength in one: the shader multiplies it by the hot 1.72 and the wrap term, so dropping this toward black IS nightfall. The moon's is cold and about a tenth of noon's.
    key: rl.Vector3,
    ambGround: rl.Vector3,
    ambSky: rl.Vector3,
    haze: rl.Vector3,
    hazeBank: rl.Vector3,
    skyLow: rl.Vector3,
    skyMid: rl.Vector3,
    skyHigh: rl.Vector3,
    skyBank: rl.Vector3,
    skyGlow: rl.Vector3,
    skyDisc: rl.Vector3,
    cloudDark: rl.Vector3,
    cloudLit: rl.Vector3,
    stars: f32,

    fn lerp(a: Palette, b: Palette, t: f32) Palette {
        var out: Palette = a;
        inline for (@typeInfo(Palette).@"struct".fields) |f| {
            const av = @field(a, f.name);
            const bv = @field(b, f.name);
            if (f.type == rl.Vector3) {
                @field(out, f.name) = mathx.lerpV(av, bv, t);
            } else if (f.type == f32) {
                @field(out, f.name) = mathx.lerpF(av, bv, t);
            } else {
                @compileError("daynight: Palette." ++ f.name ++ " has no blend");
            }
        }
        return out;
    }
};

// **WEATHER CHANGES THE LIGHT, NOT JUST THE FRAME** (owner: affect lighting depending on weather). Cloud does
// four things a slate rectangle cannot: puts the KEY out so the shadows go with it, leaves the AMBIENT alone
// (an overcast sky is one enormous soft source), takes the WARMTH out, and closes the DISTANCE. Here and not in
// `weather.zig` because it is a PALETTE operation. **AND EVERY TERM IS A FACTOR ON THE HOUR'S OWN VALUE, NEVER A CONSTANT** — absolute storm colours would light the world at 3 a.m.

const STORM_KEY: f32 = 0.34;
const STORM_HAZE: f32 = 1.70;
const STORM_AMB: f32 = 1.06;

fn slate(c: rl.Vector3) rl.Vector3 {
    const l = 0.299 * c.x + 0.587 * c.y + 0.114 * c.z;
    return v3(l * 0.86, l * 0.96, l * 1.14);
}

fn toward(c: rl.Vector3, target: rl.Vector3, k: f32) rl.Vector3 {
    return mathx.lerpV(c, target, k);
}

pub fn overcast(p: Palette, wet: f32) Palette {
    const k = mathx.clampF(wet, 0, 1);
    if (k <= 0) return p;
    var o = p;
    o.key = toward(p.key, mathx.scaleV(slate(p.key), STORM_KEY), k);
    o.ambSky = toward(p.ambSky, mathx.scaleV(slate(p.ambSky), STORM_AMB), k);
    o.ambGround = toward(p.ambGround, mathx.scaleV(slate(p.ambGround), STORM_AMB), k);
    o.haze = toward(p.haze, mathx.scaleV(slate(p.haze), STORM_HAZE), k);
    o.hazeBank = toward(p.hazeBank, mathx.scaleV(slate(p.hazeBank), 0.15), k);
    const lid = mathx.scaleV(slate(p.skyMid), 0.82);
    o.skyLow = toward(p.skyLow, mathx.scaleV(lid, 1.10), k);
    o.skyMid = toward(p.skyMid, lid, k);
    o.skyHigh = toward(p.skyHigh, mathx.scaleV(lid, 0.86), k);
    // NO DISC AND NO AUREOLE: you cannot see the sun through this.
    o.skyBank = toward(p.skyBank, mathx.scaleV(slate(p.skyBank), 0.20), k);
    o.skyGlow = toward(p.skyGlow, mathx.scaleV(slate(p.skyGlow), 0.14), k);
    o.skyDisc = toward(p.skyDisc, mathx.scaleV(slate(p.skyDisc), 0.10), k);
    o.cloudDark = toward(p.cloudDark, mathx.scaleV(slate(p.cloudDark), 0.52), k);
    o.cloudLit = toward(p.cloudLit, mathx.scaleV(slate(p.cloudLit), 0.60), k);
    o.stars = mathx.lerpF(p.stars, 0, k);
    return o;
}

// **A SPORE BLOOM BRIGHTENS THE AIR. Every other weather in this game slates it.** It leaves the key alone,
// pushes PEACH into everything the distance is made of, and shortens it — standing inside a lamp, not under
// cloud, which is why it reads at noon as well as at dusk. **AND IT THINS WITH ALTITUDE**: `skyLow` takes the full tint, `skyMid` two thirds, `skyHigh` a fifth, or the whole dome reads as a sunset.

/// **A FACTOR ON THE HOUR'S OWN VALUE, NEVER A CONSTANT** (`overcast`'s law): lerping toward an absolute peach DARKENED noon's horizon by 0.140 while lifting its zenith. `peach` is `slate` written warm — take the luminance the hour actually has and re-split it toward the red end.
fn peach(c: rl.Vector3) rl.Vector3 {
    const l = 0.299 * c.x + 0.587 * c.y + 0.114 * c.z;
    return v3(l * 1.62, l * 0.90, l * 0.74);
}

/// How much brighter than the hour a full bloom is. Over 1 in every channel-weighted sense, which is the whole claim: a bloom is a source.
const BLOOM_LIFT: f32 = 1.08;
/// The haze is lifted harder than the sky — it is the part standing between him and everything.
const BLOOM_HAZE_LIFT: f32 = 2.10;
const BLOOM_BANK_LIFT: f32 = 1.35;
/// How much of the tint each band of the dome takes. Full at the horizon, a fifth at the zenith: spores hang at head height and settle.
const BLOOM_BANDS = [3]f32{ 1.0, 0.62, 0.20 };
/// Multiplier on `hazeDensity` at full bloom — the far field goes SHORT, the way pollen closes a valley.
pub const HAZE_SPORE_D: f32 = 2.30;
/// The ambient goes with it: a lit fog is a source, and the ground under one is not lit by the sun alone.
const BLOOM_AMB: f32 = 1.35;
/// …and the stars go out. You cannot see through it.
const BLOOM_STARS: f32 = 0.25;

/// **AND IT MAY NOT CLIP.** A channel over 1 is a white hole in the dome, and the bands that blow first are
/// noon's. Scaled as a WHOLE VECTOR rather than clamped per channel: clamping red at 1 while green climbs turns peach into yellow on exactly the hours it is loudest.
fn ceiling(c: rl.Vector3) rl.Vector3 {
    const hi = @max(c.x, @max(c.y, c.z));
    return if (hi <= 1.0) c else mathx.scaleV(c, 1.0 / hi);
}

fn blush(c: rl.Vector3, k: f32, lift: f32) rl.Vector3 {
    return ceiling(toward(c, mathx.scaleV(peach(c), lift), k));
}

pub fn bloom(p: Palette, spore: f32) Palette {
    const k = mathx.clampF(spore, 0, 1);
    if (k <= 0) return p;
    var o = p;
    o.haze = blush(p.haze, k, BLOOM_HAZE_LIFT);
    o.hazeBank = blush(p.hazeBank, k, BLOOM_BANK_LIFT);
    o.skyLow = blush(p.skyLow, k * BLOOM_BANDS[0], BLOOM_LIFT);
    o.skyMid = blush(p.skyMid, k * BLOOM_BANDS[1], BLOOM_LIFT);
    o.skyHigh = blush(p.skyHigh, k * BLOOM_BANDS[2], BLOOM_LIFT);
    o.skyBank = blush(p.skyBank, k, BLOOM_BANK_LIFT);
    o.cloudDark = blush(p.cloudDark, k, BLOOM_LIFT);
    o.cloudLit = blush(p.cloudLit, k, BLOOM_LIFT);
    o.ambSky = blush(p.ambSky, k, BLOOM_AMB);
    o.ambGround = blush(p.ambGround, k * 0.6, BLOOM_LIFT);
    o.stars = p.stars * (1.0 - k * (1.0 - BLOOM_STARS));
    return o;
}


pub fn keyAmt(p: Palette) f32 {
    const luma = 0.299 * p.key.x + 0.587 * p.key.y + 0.114 * p.key.z;
    return mathx.clampF(luma / ANCHOR_KEY_LUMA, 0, 4);
}
const ANCHOR_KEY_LUMA: f32 = 1.13158; // luma(1.32, 1.10, 0.80)

const Key = struct { at: f32, p: Palette };

const NIGHT_P = Palette{
    .key = v3(0.048, 0.064, 0.118),
    .ambGround = v3(0.010, 0.012, 0.020),
    .ambSky = v3(0.026, 0.034, 0.058),
    .haze = v3(0.005, 0.007, 0.014),
    .hazeBank = v3(0.018, 0.026, 0.048),
    .skyLow = v3(0.042, 0.052, 0.082),
    .skyMid = v3(0.026, 0.032, 0.058),
    .skyHigh = v3(0.012, 0.016, 0.036),
    .skyBank = v3(0.060, 0.074, 0.115),
    .skyGlow = v3(0.220, 0.240, 0.300),
    .skyDisc = v3(0.860, 0.885, 0.940),
    .cloudDark = v3(0.022, 0.026, 0.042),
    .cloudLit = v3(0.090, 0.100, 0.130),
    .stars = 1.0,
};

/// Ordered, first key at 0 and last at 24 with the SAME palette on both, so the wrap through midnight is a blend and not a seam. **THE `SHOT_HOUR` ROW IS THE ANCHOR AND MAY NOT BE RETUNED CASUALLY** — those numbers are baked into the two shaders and every reference frame in `shots/`.
const KEYS = [_]Key{
    .{ .at = 0.0, .p = NIGHT_P },
    .{ .at = 5.0, .p = .{
        .key = v3(0.088, 0.104, 0.168),
        .ambGround = v3(0.019, 0.021, 0.031),
        .ambSky = v3(0.046, 0.056, 0.088),
        .haze = v3(0.012, 0.015, 0.026),
        .hazeBank = v3(0.080, 0.062, 0.072),
        .skyLow = v3(0.175, 0.142, 0.180),
        .skyMid = v3(0.092, 0.098, 0.148),
        .skyHigh = v3(0.038, 0.048, 0.098),
        .skyBank = v3(0.300, 0.180, 0.180),
        .skyGlow = v3(0.420, 0.290, 0.290),
        .skyDisc = v3(0.780, 0.800, 0.870),
        .cloudDark = v3(0.070, 0.068, 0.092),
        .cloudLit = v3(0.260, 0.190, 0.200),
        .stars = 0.42,
    } },
    .{ .at = 6.0, .p = .{
        .key = v3(0.940, 0.395, 0.180),
        .ambGround = v3(0.046, 0.038, 0.038),
        .ambSky = v3(0.120, 0.124, 0.166),
        .haze = v3(0.056, 0.046, 0.048),
        // …AND THE BANK IS KEPT UNDER THE ANCHOR'S REACH. At 0.52 the cliffs forty metres out went to flat pink — the mid-ground stopped existing, which is a wash and not a sunrise.
        .hazeBank = v3(0.255, 0.122, 0.055),
        .skyLow = v3(0.640, 0.330, 0.205),
        .skyMid = v3(0.335, 0.250, 0.270),
        .skyHigh = v3(0.115, 0.140, 0.250),
        .skyBank = v3(0.880, 0.400, 0.150),
        .skyGlow = v3(1.150, 0.560, 0.230),
        .skyDisc = v3(1.150, 0.720, 0.420),
        .cloudDark = v3(0.155, 0.125, 0.155),
        .cloudLit = v3(0.800, 0.390, 0.210),
        .stars = 0.0,
    } },
    .{ .at = 8.5, .p = .{
        .key = v3(1.250, 1.070, 0.860),
        .ambGround = v3(0.076, 0.076, 0.070),
        .ambSky = v3(0.176, 0.208, 0.276),
        .haze = v3(0.070, 0.076, 0.084),
        .hazeBank = v3(0.190, 0.150, 0.090),
        .skyLow = v3(0.460, 0.480, 0.500),
        .skyMid = v3(0.320, 0.400, 0.520),
        .skyHigh = v3(0.150, 0.250, 0.480),
        .skyBank = v3(0.320, 0.270, 0.180),
        .skyGlow = v3(0.860, 0.760, 0.540),
        .skyDisc = v3(1.000, 0.950, 0.800),
        .cloudDark = v3(0.270, 0.300, 0.360),
        .cloudLit = v3(0.560, 0.560, 0.540),
        .stars = 0.0,
    } },
    .{ .at = 12.0, .p = .{
        // NOT HOTTER THAN THE ANCHOR, just WHITER. The anchor's key was measured against real renders to sit just under the clip, so a noon that pushed every channel past it blew the pale surfaces out. What makes midday read as midday is the warmth LEAVING.
        .key = v3(1.310, 1.280, 1.180),
        .ambGround = v3(0.090, 0.092, 0.092),
        .ambSky = v3(0.196, 0.232, 0.310),
        .haze = v3(0.080, 0.090, 0.108),
        .hazeBank = v3(0.130, 0.125, 0.110),
        .skyLow = v3(0.500, 0.540, 0.580),
        .skyMid = v3(0.340, 0.440, 0.590),
        .skyHigh = v3(0.150, 0.270, 0.560),
        .skyBank = v3(0.230, 0.230, 0.220),
        .skyGlow = v3(0.800, 0.780, 0.720),
        .skyDisc = v3(1.000, 0.990, 0.940),
        .cloudDark = v3(0.310, 0.350, 0.420),
        .cloudLit = v3(0.660, 0.680, 0.680),
        .stars = 0.0,
    } },
    .{ .at = SHOT_HOUR, .p = .{
        .key = v3(1.320, 1.100, 0.800),
        .ambGround = v3(0.090, 0.076, 0.054),
        .ambSky = v3(0.168, 0.188, 0.244),
        .haze = v3(0.078, 0.070, 0.056),
        .hazeBank = v3(0.340, 0.190, 0.050),
        .skyLow = v3(0.325, 0.310, 0.278),
        .skyMid = v3(0.235, 0.250, 0.300),
        .skyHigh = v3(0.150, 0.170, 0.230),
        .skyBank = v3(0.400, 0.260, 0.100),
        .skyGlow = v3(0.900, 0.620, 0.280),
        .skyDisc = v3(1.000, 0.850, 0.550),
        .cloudDark = v3(0.165, 0.172, 0.205),
        .cloudLit = v3(0.400, 0.310, 0.200),
        .stars = 0.0,
    } },
    .{ .at = 19.4, .p = .{
        .key = v3(1.020, 0.430, 0.185),
        .ambGround = v3(0.052, 0.042, 0.040),
        .ambSky = v3(0.132, 0.136, 0.186),
        .haze = v3(0.066, 0.050, 0.048),
        .hazeBank = v3(0.310, 0.135, 0.050),
        .skyLow = v3(0.740, 0.320, 0.150),
        .skyMid = v3(0.380, 0.250, 0.265),
        .skyHigh = v3(0.120, 0.145, 0.245),
        .skyBank = v3(1.000, 0.380, 0.110),
        .skyGlow = v3(1.300, 0.560, 0.180),
        .skyDisc = v3(1.200, 0.660, 0.300),
        .cloudDark = v3(0.170, 0.125, 0.145),
        .cloudLit = v3(0.940, 0.400, 0.170),
        .stars = 0.0,
    } },
    .{ .at = 20.8, .p = .{
        .key = v3(0.130, 0.150, 0.230),
        .ambGround = v3(0.020, 0.022, 0.032),
        .ambSky = v3(0.058, 0.068, 0.102),
        .haze = v3(0.013, 0.014, 0.024),
        .hazeBank = v3(0.140, 0.082, 0.072),
        .skyLow = v3(0.290, 0.170, 0.155),
        .skyMid = v3(0.120, 0.118, 0.160),
        .skyHigh = v3(0.040, 0.052, 0.100),
        .skyBank = v3(0.440, 0.200, 0.130),
        .skyGlow = v3(0.520, 0.340, 0.290),
        .skyDisc = v3(0.840, 0.860, 0.920),
        .cloudDark = v3(0.062, 0.060, 0.082),
        .cloudLit = v3(0.290, 0.180, 0.170),
        .stars = 0.55,
    } },
    .{ .at = 22.5, .p = NIGHT_P },
    .{ .at = HOURS, .p = NIGHT_P },
};

comptime {
    std.debug.assert(KEYS[0].at == 0);
    std.debug.assert(KEYS[KEYS.len - 1].at == HOURS);
    for (KEYS[1..], 0..) |k, i| std.debug.assert(k.at > KEYS[i].at);
}

pub fn paletteAt(hour: f32) Palette {
    const h = wrapHour(hour);
    var i: usize = 0;
    while (i + 1 < KEYS.len and KEYS[i + 1].at <= h) i += 1;
    if (i + 1 >= KEYS.len) return KEYS[KEYS.len - 1].p;
    const a = KEYS[i];
    const b = KEYS[i + 1];
    const span = b.at - a.at;
    const t = if (span <= 0) 0 else mathx.smoothstep(0, 1, (h - a.at) / span);
    return Palette.lerp(a.p, b.p, t);
}


pub const Until = enum {
    morning,
    evening,

    pub fn hour(u: Until) f32 {
        return switch (u) {
            .morning => 8.5,
            .evening => EVENING_HOUR,
        };
    }
    pub fn label(u: Until) [:0]const u8 {
        return switch (u) {
            .morning => "Rest until morning",
            .evening => "Rest until evening",
        };
    }
};

/// HOW LONG A REST HAS TO CARRY THE CLOCK to reach `to`, always FORWARD: a fire cannot take you backwards through a night you have already spent. Landing exactly on the hour asked for is a full day round.
pub fn hoursUntil(from: f32, to: f32) f32 {
    const d = wrapHour(to - from);
    return if (d <= 1e-4) HOURS else d;
}

pub fn clockText(hour: f32, buf: []u8) []const u8 {
    return clockTextZ(hour, buf);
}

pub fn clockTextZ(hour: f32, buf: []u8) [:0]const u8 {
    const h = wrapHour(hour);
    const hh: u32 = @intFromFloat(@floor(h));
    const mm: u32 = @intFromFloat(@floor((h - @floor(h)) * 60.0));
    return std.fmt.bufPrintZ(buf, "{d:0>2}:{d:0>2}", .{ hh % 24, mm % 60 }) catch "--:--";
}

pub fn phaseName(hour: f32) [:0]const u8 {
    const h = wrapHour(hour);
    if (h < 5.0) return "night";
    if (h < SUNRISE) return "first light";
    if (h < 7.5) return "sunrise";
    if (h < 11.0) return "morning";
    if (h < 14.0) return "midday";
    if (h < 16.5) return "afternoon";
    if (h < 18.8) return "golden hour";
    if (h < SUNSET) return "sunset";
    if (h < 21.5) return "dusk";
    return "night";
}


/// THE ANCHOR SUN — the light this whole game was authored, measured and photographed under. **AND IT IS THE ONE COPY**: `gfx.SUN_DIR` is this, not a second triple beside it. Written out in both files, the test below compared the clock against `daynight`'s own copy.
pub const ANCHOR_DIR = mathx.normV(v3(-0.60, 0.50, -0.46));

test "SHOT_HOUR REPRODUCES THE SUN THE GAME WAS PHOTOGRAPHED UNDER — 362 reference frames ride on it" {
    // A THOUSANDTH OF A UNIT VECTOR is under a twentieth of a degree of sun, where one shadow-map texel across the 108 m box is already a third of a degree at the distances that matter.
    const TOL: f32 = 1e-3;
    const d = keyDir(SHOT_HOUR);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.x, d.x, TOL);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.y, d.y, TOL);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.z, d.z, TOL);
    const s = sunDir(SHOT_HOUR);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.y, s.y, TOL);
}

test "keyAmt is exactly 1 at the anchor, and the specular dims with the light everywhere else" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), keyAmt(paletteAt(SHOT_HOUR)), 1e-4);
    try std.testing.expect(keyAmt(paletteAt(0)) < 0.15);
    try std.testing.expect(keyAmt(paletteAt(12)) > 1.0);
    var h: f32 = 0;
    while (h < HOURS) : (h += 0.05) try std.testing.expect(keyAmt(paletteAt(h)) >= 0);
}

test "the palette's anchor row IS the numbers the two shaders carried" {
    const p = paletteAt(SHOT_HOUR);
    try std.testing.expectApproxEqAbs(@as(f32, 1.32), p.key.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.10), p.key.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.80), p.key.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.078), p.haze.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.070), p.haze.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.056), p.haze.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.168), p.ambSky.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.325), p.skyLow.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p.stars, 1e-6);
}

test "the sun rises in the east, sets in the west, and is under the world at midnight" {
    try std.testing.expect(sunDir(SUNRISE).y < 1e-4 and sunDir(SUNRISE).y > -1e-4);
    try std.testing.expect(sunDir(SUNSET).y < 1e-4 and sunDir(SUNSET).y > -1e-4);
    try std.testing.expect(sunDir(12.0).y > 0.8);
    try std.testing.expect(sunDir(0.0).y < -0.5);
    var prev = mathx.headingXZ(sunDir(SUNRISE));
    var h: f32 = SUNRISE + 0.25;
    while (h <= SUNSET) : (h += 0.25) {
        const now = mathx.headingXZ(sunDir(h));
        try std.testing.expect(mathx.wrapPi(now - prev) > -1e-4);
        prev = now;
    }
}

test "ONE DIRECTION ALWAYS CASTS, AND ITS ALTITUDE IS FLOORED — the shadow box can hold every hour of it" {
    const floorY = mathx.sinf(mathx.radians(KEY_ALT_MIN));
    var h: f32 = 0;
    while (h < HOURS) : (h += 0.05) {
        const d = keyDir(h);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), mathx.lenV(d), 1e-4);
        try std.testing.expect(d.y >= floorY - 1e-4);
        try std.testing.expect(std.math.isFinite(shadowReach(h)));
        try std.testing.expect(shadowReach(h) <= 1.0 / floorY);
    }
    const night = keyDir(1.0);
    const sunAt1 = sunDir(1.0);
    try std.testing.expect(night.x * sunAt1.x + night.z * sunAt1.z < 0);
}

test "MIDNIGHT IS A BLEND AND NOT A SEAM — the palette is continuous across the wrap" {
    const before = paletteAt(23.999);
    const after = paletteAt(0.001);
    try std.testing.expectApproxEqAbs(before.key.x, after.key.x, 2e-3);
    try std.testing.expectApproxEqAbs(before.skyHigh.z, after.skyHigh.z, 2e-3);
    var h: f32 = 0;
    var prev = paletteAt(0);
    while (h < HOURS) : (h += 0.02) {
        const now = paletteAt(h);
        try std.testing.expect(@abs(now.key.x - prev.key.x) < 0.05);
        try std.testing.expect(@abs(now.stars - prev.stars) < 0.05);
        prev = now;
    }
}

test "NIGHT IS DARK AND DAY IS NOT — the key is what carries it, so the bars can be read either way" {
    try std.testing.expect(paletteAt(0).key.x < 0.2);
    try std.testing.expect(paletteAt(12).key.x > 1.2);
    try std.testing.expect(paletteAt(0).stars > 0.9 and paletteAt(12).stars == 0);
    try std.testing.expect(paletteAt(0).skyDisc.z > paletteAt(0).skyDisc.x);
    try std.testing.expect(paletteAt(SHOT_HOUR).skyDisc.x > paletteAt(SHOT_HOUR).skyDisc.z);
}

test "the clock wraps, holds when frozen, and scrubs both ways" {
    var c = Clock{};
    try std.testing.expectApproxEqAbs(SHOT_HOUR, c.hour, 1e-6);
    c.set(23.5);
    c.rate = 1.0;
    c.tick(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c.hour, 1e-5);
    c.freeze(true);
    try std.testing.expect(c.frozen());
    c.tick(100.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c.hour, 1e-5);
    c.nudge(-1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 23.5), c.hour, 1e-5);
    c.freeze(false);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), c.rate, 1e-9);
    c.set(std.math.nan(f32)); // a NaN cannot be allowed to poison the light for the rest of the session
    try std.testing.expectApproxEqAbs(SHOT_HOUR, c.hour, 1e-6);
}

test "THE DAY SPEED AND THE HOLD ARE TWO QUESTIONS — neither row reaches into the other's answer" {
    var c = Clock{};
    try std.testing.expectApproxEqAbs(@as(f32, 1), c.speed(), 1e-5);
    try std.testing.expectApproxEqAbs(DAY_MINUTES * 60.0, c.dayLen(), 1e-2);
    // It walks the published steps and WRAPS, so the row is one button and cannot dead-end at the top.
    for (RATE_MULTS[1..]) |m| {
        c.cycleSpeed();
        try std.testing.expectApproxEqAbs(m, c.speed(), 1e-4);
    }
    c.cycleSpeed();
    try std.testing.expectApproxEqAbs(RATE_MULTS[0], c.speed(), 1e-4);

    c.cycleSpeed();
    c.freeze(true);
    try std.testing.expect(c.frozen());
    c.cycleSpeed();
    try std.testing.expect(c.frozen());
    try std.testing.expectApproxEqAbs(@as(f32, 20), c.speed(), 1e-4);
    c.freeze(false);
    try std.testing.expect(!c.frozen());
    try std.testing.expectApproxEqAbs(@as(f32, 20), c.speed(), 1e-4);
    c.resumeRate = RATE_DEFAULT * RATE_MULTS[RATE_MULTS.len - 1];
    c.rate = c.resumeRate;
    try std.testing.expect(c.dayLen() < 15.0);
}

test "THE CASTER MAY ONLY CHANGE HANDS IN THE DARK — the moonrise light switch" {
    // Two opposite bearings cannot avoid the half turn; WHEN can be arranged. This weights the swing by how bright the key is while it swings: on `isDay` it measured 67.8 (179.9 deg at 19.99 h, key at 0.471). The STEP is part of the measurement.
    const STEP: f32 = 0.01;
    var h: f32 = 0;
    var worst: f32 = 0;
    var worstLit: f32 = 0;
    while (h < HOURS) : (h += STEP) {
        const swing = @abs(mathx.degrees(mathx.wrapPi(mathx.headingXZ(keyDir(h + STEP)) - mathx.headingXZ(keyDir(h)))));
        worst = mathx.maxF(worst, swing);
        worstLit = mathx.maxF(worstLit, swing * keyAmt(paletteAt(h)));
    }
    try std.testing.expect(worstLit < 2.0);
    // …and NOTHING anywhere on the clock jumps, lit or not. A hundredth of an hour is 30 real seconds of the standard day: the key may turn, and it may not teleport.
    try std.testing.expect(worst < 6.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(keyDir(12.0), mathx.normV(sunDir(12.0))), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(keyDir(0.0), mathx.normV(moonDir(0.0))), 1e-4);

    try std.testing.expect(keyAmt(paletteAt(KEY_SWAP_DAWN)) < 0.20);
    try std.testing.expect(keyAmt(paletteAt(KEY_SWAP_DUSK)) < 0.20);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), moonShare(KEY_SWAP_DAWN), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), moonShare(KEY_SWAP_DUSK), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 1), moonShare(KEY_SWAP_DAWN - KEY_SWAP_FADE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(KEY_SWAP_DAWN + KEY_SWAP_FADE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(KEY_SWAP_DUSK - KEY_SWAP_FADE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1), moonShare(KEY_SWAP_DUSK + KEY_SWAP_FADE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(SUNRISE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(SUNSET), 1e-4);
    try std.testing.expect(sunDir(SUNSET + 0.4).y < 0 and moonShare(SUNSET + 0.4) < 0.05);
    try std.testing.expect(sunDir(SUNRISE - 0.4).y < 0 and moonShare(SUNRISE - 0.4) < 0.05);
    try std.testing.expect(keyDir(SUNSET + 0.4).y > 0);
}

test "a rest always carries the clock FORWARD, and asking for the hour you are on is a full day" {
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), hoursUntil(6.0, 8.5), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), hoursUntil(17.5, 8.5), 1e-5);
    try std.testing.expectApproxEqAbs(HOURS, hoursUntil(8.5, 8.5), 1e-4);
    inline for (@typeInfo(Until).@"enum".fields) |f| {
        const u: Until = @enumFromInt(f.value);
        try std.testing.expect(u.label().len > 0);
        try std.testing.expect(u.hour() >= 0 and u.hour() < HOURS);
    }
    // MORNING IS A DAY HOUR AND EVENING IS NOT (owner's call): one row puts you out in the clean light and the other after the sun has gone.
    try std.testing.expect(isDay(Until.morning.hour()));
    try std.testing.expect(!isDay(Until.evening.hour()));
    try std.testing.expect(sunDir(Until.evening.hour()).y < 0);
    try std.testing.expect(keyAmt(paletteAt(Until.evening.hour())) < 0.25);
}

test "the readout says the hour and names the phase" {
    var buf: [8]u8 = undefined;
    try std.testing.expectEqualStrings("06:30", clockText(6.5, &buf));
    try std.testing.expectEqualStrings("00:00", clockText(24.0, &buf));
    try std.testing.expectEqualStrings("17:27", clockText(SHOT_HOUR, &buf));
    try std.testing.expectEqualStrings("golden hour", phaseName(SHOT_HOUR));
    try std.testing.expectEqualStrings("night", phaseName(2.0));
    var h: f32 = 0;
    while (h < HOURS) : (h += 0.1) try std.testing.expect(phaseName(h).len > 0);
}

test "A BLOOM BRIGHTENS THE DISTANCE, and it thins with altitude — every other weather here slates it" {
    const noon = paletteAt(12.0);
    const lit = bloom(noon, 1.0);
    std.debug.print("\n  bloom: haze {d:.3},{d:.3},{d:.3} -> {d:.3},{d:.3},{d:.3}, density x{d:.2}\n", .{ noon.haze.x, noon.haze.y, noon.haze.z, lit.haze.x, lit.haze.y, lit.haze.z, HAZE_SPORE_D });
    try std.testing.expect(lit.haze.x > lit.haze.y and lit.haze.y > lit.haze.z);
    try std.testing.expect(lit.haze.x > noon.haze.x);
    try std.testing.expect(HAZE_SPORE_D > 1.0);
    // The KEY is the one thing it does not touch — that is what makes it the opposite of `overcast`.
    try std.testing.expectEqual(noon.key.x, lit.key.x);
    try std.testing.expect(overcast(noon, 1.0).key.x < noon.key.x);
    // Horizon takes the full tint, zenith a fifth: without the ramp the dome reads as a sunset.
    const dLow = lit.skyLow.x - noon.skyLow.x;
    const dHigh = lit.skyHigh.x - noon.skyHigh.x;
    std.debug.print("  ...dome tint: low +{d:.3}, mid +{d:.3}, high +{d:.3}\n", .{ dLow, lit.skyMid.x - noon.skyMid.x, dHigh });
    try std.testing.expect(dLow > dHigh * 3.0);
    // …and it LIFTS every band at every hour. The first cut lerped to an absolute peach and darkened noon.
    var hi: f32 = 0;
    for ([_]f32{ 0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 17.5, 20.0, 21.0 }) |h| {
        const q = paletteAt(h);
        const w = bloom(q, 1.0);
        try std.testing.expect(w.skyLow.x >= q.skyLow.x);
        try std.testing.expect(w.haze.x > q.haze.x);
        try std.testing.expect(w.haze.x > w.haze.z);
        // …and NOTHING CLIPS. A band over 1.0 is a white hole in the dome, not a brighter sky.
        inline for (.{ w.skyLow, w.skyMid, w.skyHigh, w.hazeBank, w.cloudLit }) |c| {
            hi = @max(hi, @max(c.x, @max(c.y, c.z)));
        }
    }
    std.debug.print("  ...brightest channel at any hour under a full bloom: {d:.3}\n", .{hi});
    try std.testing.expect(hi <= 1.0);
    const half = bloom(noon, 0.5);
    try std.testing.expect(half.haze.x > noon.haze.x and half.haze.x < lit.haze.x);
    try std.testing.expect(bloom(noon, 0).stars == noon.stars);
    try std.testing.expect(paletteAt(0.0).stars > bloom(paletteAt(0.0), 1.0).stars);
}
