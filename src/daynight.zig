const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;

// THE WORLD CLOCK — one number, `hour`, and everything the light does is a function of it.
//
// **ONE DIRECTION CASTS, AND IT IS THE SAME ONE THE SHADER KEYS OFF** (AGENTS.md: "Sun + shadows are ONE
// source"). That law does not change here; what changes is that the source is now solved from the hour
// instead of written down. `keyDir` is the whole of it: the SUN while the sun is up, the MOON once it is
// down, and nothing else in the game gets a say.
//
// **THE SKY DRAWS THE TRUE PATH; THE SHADOWS DO NOT.** A sun at two degrees of altitude throws a shadow
// three hundred metres long, which the 108 m ortho box cannot hold and the depth pass cannot cull for — the
// last minutes of the day would be a world of clipped, crawling shadows. So `keyDir` FLOORS the altitude
// (`KEY_ALT_MIN`) while `sunDir`/`moonDir` keep the honest angle for the disc in the sky. The eye reads the
// disc's height off the horizon and the shadow's DIRECTION off the ground; it does not solve one from the
// other, and this is the one place they are allowed to disagree.
//
// **THE ANCHOR IS NOT A KEYFRAME.** Every reference shot in `shots/` is framed off the bearing of the sun
// this game was authored under (`shots.LIT_YAW` = 53 puts it over the camera's shoulder), and the whole
// palette was measured against that one light. So the cycle is SOLVED THROUGH it: `SHOT_HOUR` is the hour
// that reproduces it, the palette's noon-to-dusk keys are the authored numbers sitting on that hour, and a
// test pins both. Retuning the path without moving the anchor is what silently re-lights 362 photographs.

pub const HOURS: f32 = 24.0;
/// When the sun clears the horizon and when it goes back under it. A LONG day (14 h) and a shorter night, so
/// "morning" and "evening" are places you can actually be sent to rest until.
pub const SUNRISE: f32 = 6.0;
pub const SUNSET: f32 = 20.0;
pub const DAY_SPAN: f32 = SUNSET - SUNRISE;
pub const NIGHT_SPAN: f32 = HOURS - DAY_SPAN;

/// The bearings the sun rises and sets on, in degrees of `mathx.headingXZ` (0 = +Z).
const AZ_RISE: f32 = 100.0;
const AZ_SET: f32 = 262.0;

/// THE ANCHOR, and the two constants below are SOLVED from it rather than chosen (see the note above).
/// `gfx.SUN_DIR` = norm(-0.60, 0.50, -0.46) is bearing 180 + atan(0.60/0.46) = 232.5256 deg, at an altitude of
/// atan(0.50 / hypot(0.60, 0.46)) = 33.4793 deg. That bearing is 0.8180593 of the sweep from `AZ_RISE` to
/// `AZ_SET`, which gives the hour; and the altitude is that fraction of the arch's own sine, which gives the
/// peak: 33.4793 / sin(pi * 0.8180593) = 61.8895.
/// **MOVE `AZ_RISE`/`AZ_SET` AND BOTH OF THESE MOVE WITH THEM** — solve them again, do not nudge them. The
/// first test below is what fails if you don't, and what it is protecting is 362 photographs.
pub const SUN_ALT_MAX: f32 = 61.8895;
/// The one hour `--shot` runs at, and the light every reference frame in `shots/` was judged under.
pub const SHOT_HOUR: f32 = 17.45283;

/// The lowest altitude the CASTING direction is allowed to reach — see the note above. About the sun at
/// half past six on a summer evening, which is as long as a shadow the box can hold.
const KEY_ALT_MIN: f32 = 15.0;

/// **WHEN THE CASTER CHANGES HANDS, AND IT IS NOT SUNRISE AND SUNSET.**
///
/// There is ONE shadow-casting light. The moon is the ANTI-sun, so the instant the key stops being one and starts
/// being the other its bearing turns most of the way round the compass, and every shadow in the world swings with
/// it on one frame. Swapped on `isDay` — at the horizon crossings themselves — that happened at 06:00 and 20:00,
/// and 20:00 is 0.6 h INTO the ramp down from the sunset row: measured, the bearing moved 179.9 degrees in a
/// hundredth of an hour while the key was still at half the anchor's brightness. That is the abrupt switch.
///
/// So the swap is moved to the DIMMEST hours of each ramp, which are the `KEYS` rows either side of the bright
/// terminator ones (first light, and dusk). Two things fall out of that and both are what you want:
///   - the flip happens while the key is at about a tenth of the anchor, where a bearing change reads as the
///     light going cold rather than as a switch being thrown;
///   - through the hour on each side, the caster is the sun with its altitude on the floor (`KEY_ALT_MIN`) and
///     its true bearing — so dusk throws long shadows away from where the sun actually went down, and the small
///     hours before dawn throw them from where it is about to come up. Both were being cast from the OPPOSITE
///     side of the sky before.
///
/// **`isDay` IS NOT TOUCHED** — it is the day's own definition and the palette, the dial and the bonfire's hours
/// all read it. This is the CASTER's question and it is asked here, once.
const KEY_SWAP_DAWN: f32 = 5.0;
const KEY_SWAP_DUSK: f32 = 20.8;

comptime {
    // Inside the night on both sides, or the swap is happening while the sun is genuinely up.
    std.debug.assert(KEY_SWAP_DAWN < SUNRISE);
    std.debug.assert(KEY_SWAP_DUSK > SUNSET);
}

/// HOW LONG THE HANDOVER TAKES, in hours either side of the swap hour. **THE TWO CASTERS ARE FADED TOGETHER
/// RATHER THAN SWITCHED** (owner's call): across this window the key's bearing turns the whole half circle and its
/// altitude crosses through the floor, so what the eye gets is the light SWEEPING round — the shadows visibly
/// travelling — instead of every one of them being somewhere else on the next frame. Kept inside the dim band the
/// swap hour sits in, so the sweep is happening while the key is at a tenth of the anchor and not during sunset.
const KEY_SWAP_FADE: f32 = 0.45;

/// HOW MUCH OF THE KEY IS THE MOON'S, 0..1 — the sun's alone by day, the moon's alone by night, and a smooth
/// crossing at each end. Its own function because both the direction and every question about which body is
/// casting are answers to this one number.
fn moonShare(hour: f32) f32 {
    const h = wrapHour(hour);
    // The dusk crossing, and the dawn one measured the same way on the other side of midnight. `hoursUntil`-style
    // wrapping is not needed: both windows are well inside the night, which the comptime block above pins.
    if (h > SUNSET) return mathx.smoothstep(KEY_SWAP_DUSK - KEY_SWAP_FADE, KEY_SWAP_DUSK + KEY_SWAP_FADE, h);
    if (h < SUNRISE) return 1.0 - mathx.smoothstep(KEY_SWAP_DAWN - KEY_SWAP_FADE, KEY_SWAP_DAWN + KEY_SWAP_FADE, h);
    return 0; // broad daylight
}

/// WHICH WAY ROUND THE HANDOVER TURNS. The sun's own azimuth sweeps from `AZ_RISE` toward `AZ_SET`, so the key
/// carries on the same way rather than doubling back — a light that reversed its travel to change hands would be
/// a second thing to notice at the one moment this whole window exists to make unremarkable.
const KEY_SWEEP: f32 = if (AZ_SET > AZ_RISE) 1.0 else -1.0;

/// A DAY IN REAL MINUTES at the default rate. Twenty is slow enough that an hour of light is a minute of
/// play — you notice the shadows have moved, you never watch them move.
pub const DAY_MINUTES: f32 = 20.0;
pub const RATE_DEFAULT: f32 = HOURS / (DAY_MINUTES * 60.0);

/// Wrap an hour into [0, 24).
pub fn wrapHour(h: f32) f32 {
    if (!std.math.isFinite(h)) return SHOT_HOUR;
    const r = @rem(h, HOURS);
    return if (r < 0) r + HOURS else r;
}

/// THE DEBUG SPEEDS, as multiples of the standard day — what the pause menu's Day Speed row walks. The top of
/// the range is a day in TEN SECONDS, which is the point of the row: at 1x the sky moving is something you
/// notice having happened, and to check the clock runs at all you need to be able to WATCH it.
pub const RATE_MULTS = [_]f32{ 1, 4, 20, 120 };

pub const Clock = struct {
    hour: f32 = SHOT_HOUR,
    /// Game hours a real second. Zero is a held clock, which is what the editor and `--shot` want.
    rate: f32 = RATE_DEFAULT,
    /// THE RATE A HOLD COMES BACK TO, so the two debug rows cannot fight: pick a speed, hold the clock to look
    /// at something, let it go, and it runs at the speed you picked rather than silently back at the default.
    resumeRate: f32 = RATE_DEFAULT,

    pub fn tick(self: *Clock, dt: f32) void {
        if (self.rate == 0) return;
        self.hour = wrapHour(self.hour + self.rate * dt);
    }
    pub fn set(self: *Clock, h: f32) void {
        self.hour = wrapHour(h);
    }
    /// SCRUBBED BY HAND — the debug menu's and the editor's one control. Hours, signed.
    pub fn nudge(self: *Clock, dh: f32) void {
        self.set(self.hour + dh);
    }
    pub fn frozen(self: *const Clock) bool {
        return self.rate == 0;
    }
    /// …and the toggle behind it. It REMEMBERS the speed (`resumeRate`) rather than snapping back to the
    /// standard one, or holding the clock for a moment would quietly undo the Day Speed row every time.
    pub fn freeze(self: *Clock, on: bool) void {
        if (!on) {
            self.rate = self.resumeRate;
            return;
        }
        if (self.rate != 0) self.resumeRate = self.rate;
        self.rate = 0;
    }

    /// HOW MANY TIMES THE STANDARD DAY it is set to run at — the SETTING, so a held clock still reports the speed
    /// it will start at rather than zero. Whether it is running at all is `frozen()`, which is a separate
    /// question and is asked separately.
    pub fn speed(self: *const Clock) f32 {
        return (if (self.rate == 0) self.resumeRate else self.rate) / RATE_DEFAULT;
    }

    /// …and how long a whole day takes at that speed, in REAL seconds — what the debug row actually says, since
    /// "120x" means nothing and "10 s/day" is the thing you are about to watch.
    pub fn dayLen(self: *const Clock) f32 {
        return HOURS / mathx.maxF(self.speed() * RATE_DEFAULT, 1e-6);
    }

    /// THE NEXT SPEED UP, wrapping. Setting the speed of a HELD clock sets the speed it will start at and leaves
    /// it held: one row says how fast and the other says whether, and neither reaches into the other's answer.
    ///
    /// **IT SNAPS TO THE NEAREST STEP AND THEN ADVANCES BY INDEX**, rather than looking for the first step ABOVE
    /// the current speed. `speed()` reconstructs the multiplier by dividing, so a rate set from a step can come
    /// back a hair under it (120 as 119.99999) — and a strict comparison then finds nothing above it, wraps to the
    /// bottom, and the row cannot be walked past the top at all. Nearest-then-next cannot stall, and it also does
    /// something sensible with a rate nobody picked off this list.
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

/// A DAY'S LENGTH IN WORDS, for the row that sets it — minutes while there are minutes in it, seconds once the
/// whole day is shorter than the pause it takes to read the label.
pub fn dayLenText(c: *const Clock, buf: []u8) [:0]const u8 {
    const s = c.dayLen();
    if (s >= 90.0) return std.fmt.bufPrintZ(buf, "{d:.0} min", .{s / 60.0}) catch "?";
    return std.fmt.bufPrintZ(buf, "{d:.0} s", .{s}) catch "?";
}

// ——— where the sun and the moon actually are ———

/// 0..1 through the DAY for an hour inside it; outside it, the value runs on past the ends, which is what
/// makes the azimuth sweep continuous across both knots.
fn dayU(hour: f32) f32 {
    const h = wrapHour(hour);
    if (h >= SUNRISE and h <= SUNSET) return (h - SUNRISE) / DAY_SPAN;
    // Night: measured FORWARD from sunset, wrapping through midnight, so 24:00 and 00:00 are the same point.
    const past = if (h > SUNSET) h - SUNSET else h + (HOURS - SUNSET);
    return 1.0 + past / NIGHT_SPAN; // 1 at sunset → 2 at sunrise
}

pub fn isDay(hour: f32) bool {
    const h = wrapHour(hour);
    return h >= SUNRISE and h <= SUNSET;
}

/// HOW FAR THROUGH ITS OWN SPAN THE HOUR IS: 0 at the horizon it left and 1 at the one it is heading for, for
/// whichever of the two spans `isDay` says it is in. That pair is the whole of what a readout needs — and it
/// comes off `dayU`, the same progression the sun's azimuth is swept by, so a dial drawn from it cannot disagree
/// with the light in the scene behind it.
pub fn spanU(hour: f32) f32 {
    const u = dayU(hour);
    return if (u <= 1.0) u else u - 1.0;
}

/// 0 at both horizons, 1 at noon — the daylight dial every palette key is really about.
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

/// The sun's TRUE direction (surface → sun). Below the horizon at night, which is the point of it.
pub fn sunDir(hour: f32) rl.Vector3 {
    const u = dayU(hour);
    // One sine over the whole run: positive through the day, negative through the night, and zero at both
    // knots — so nothing pops at sunrise or sunset and midnight is the deepest point under the world.
    const alt = SUN_ALT_MAX * mathx.sinf(std.math.pi * u);
    // **THE BEARING GOES ALL THE WAY ROUND, ONCE A DAY, AND THE NIGHT CARRIES THE PART OF THE CIRCLE THE DAY DOES
    // NOT.** Swept at the day's own rate through the night instead, `u = 2` landed at `2·(AZ_SET − AZ_RISE)` past
    // the rise bearing — with a 162 degree day that is 36 degrees SHORT of a full turn, so at 06:00, where `dayU`
    // wraps 2 back to 0, every shadow in the world stepped 36 degrees sideways on one frame. Measured at 36.16.
    // `dayU`'s own note claims the sweep is continuous across both knots; it was true at sunset only, because
    // there `u` is 1 from both sides and nothing wraps.
    const az = if (u <= 1.0)
        AZ_RISE + (AZ_SET - AZ_RISE) * u
    else
        AZ_SET + (360.0 - (AZ_SET - AZ_RISE)) * (u - 1.0);
    return dirFrom(az, alt);
}

/// …and the MOON, which is the anti-sun: one of the two is always up, so the world is never unlit.
pub fn moonDir(hour: f32) rl.Vector3 {
    const s = sunDir(hour);
    return v3(-s.x, -s.y, -s.z);
}

/// WHAT CASTS THIS HOUR — the sun while it is up, the moon once it is not, with the altitude floored so the
/// shadow map stays a shadow map (see the note at the top). The bearing is never floored: a low sun's
/// shadows must still point the right way, and that is the half the eye actually reads.
pub fn keyDir(hour: f32) rl.Vector3 {
    const s = sunDir(hour);
    const share = moonShare(hour);
    // **THE HANDOVER IS A SWEEP, NOT A PICK.** The moon is the anti-sun, so "which of the two is casting" is
    // exactly a HALF TURN of the bearing and a SIGN on the altitude — and both of those can be crossed gradually.
    // At `share` 0 and 1 this is `sunDir` and `moonDir` to the last bit; in between it is neither, which is the
    // point. Written as a choice between the two vectors there was nothing in between to write.
    const az = std.math.atan2(s.x, s.z) + std.math.pi * share * KEY_SWEEP;
    const alt = std.math.asin(mathx.clampF(s.y, -1, 1)) * (1.0 - 2.0 * share);
    // …AND THE FLOOR, which is what makes a caster under the horizon usable at all (see the note at the top): the
    // altitude crosses zero somewhere inside every handover, and a key coming from the horizon casts a shadow the
    // depth box cannot hold. Held ON the floor through the crossing, so what moves there is the BEARING alone.
    const minY = mathx.sinf(mathx.radians(KEY_ALT_MIN));
    const y = mathx.maxF(mathx.sinf(alt), minY);
    const c = @sqrt(mathx.maxF(0, 1.0 - y * y));
    return v3(mathx.sinf(az) * c, y, mathx.cosf(az) * c);
}

/// HOW FAR SIDEWAYS A CASTER THROWS ITS SHADOW, per metre of its own height (`env.SUN_REACH`'s job). It is
/// cot(altitude) of whatever is casting, so it grows as the light drops — read off `keyDir`, which is what
/// floors it, and therefore bounded by construction rather than by hope.
pub fn shadowReach(hour: f32) f32 {
    const d = keyDir(hour);
    return mathx.lenXZ(d) / mathx.maxF(d.y, 1e-3);
}

// ——— what colour the world is ———

/// EVERY COLOUR THE HOUR DECIDES, in one struct so the whole look of a time of day is ONE row of a table and
/// never a set of numbers scattered over two shaders.
///
/// **THE TWO HALVES OF THIS STRUCT ARE ON DIFFERENT SCALES, AND IT IS NOT A MISTAKE.** The scene shader gammas
/// its output (`pow 1/2.2`), so everything it reads — `key`, the two ambients, `haze`, `hazeBank` — is
/// PRE-GAMMA and authored near-black (AGENTS.md's dark-albedo rule). The SKY shader does not gamma anything:
/// it writes what it computes, so every `sky*`/`cloud*` value here is a LITERAL SCREEN VALUE. Authoring the
/// sky pre-gamma is the mistake that reads as a black hole over a blazing noon — the ground came out of one
/// pipeline and the zenith out of the other, and only one of them had been lifted.
pub const Palette = struct {
    /// The KEY, colour and strength in one: the shader multiplies it by the hot 1.72 and the wrap term, so
    /// dropping this toward black IS nightfall. The moon's is cold and about a tenth of noon's.
    key: rl.Vector3,
    /// The hemisphere ambient — what faces the ground, and what faces the sky.
    ambGround: rl.Vector3,
    ambSky: rl.Vector3,
    /// Distance haze, and the warm bank it takes on looking into the light's own quarter. **AT THE DARK HOURS
    /// IT MUST SIT UNDER WHAT THE GROUND IS LIT TO**, or the distance comes out brighter than the foreground and
    /// reads as FOG rather than as nightfall — the first pass carried the anchor's daylight haze into dusk and
    /// the cliffs forty metres out glowed pale lavender over a black field.
    haze: rl.Vector3,
    hazeBank: rl.Vector3,
    /// The sky's three stops, horizon → middle → zenith.
    skyLow: rl.Vector3,
    skyMid: rl.Vector3,
    skyHigh: rl.Vector3,
    /// The bank of colour laid along the horizon under the light, the aureole around it, and the disc itself.
    skyBank: rl.Vector3,
    skyGlow: rl.Vector3,
    skyDisc: rl.Vector3,
    /// The cloud deck, shadowed side and lit side.
    cloudDark: rl.Vector3,
    cloudLit: rl.Vector3,
    /// How much of the star field is out, 0..1 — and it is its OWN dial rather than `1 - dayAmt` because the
    /// stars have to be gone well before the sky finishes brightening or dawn reads as a switch being thrown.
    stars: f32,

    /// FIELD BY FIELD OFF THE STRUCT ITSELF, so a colour added to the palette is blended by existing;
    /// written out by hand it is one more place for a new key to be carried by the first row all day.
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

/// HOW BRIGHT THIS HOUR'S KEY IS AGAINST THE HOUR THE SPECULARS WERE AUTHORED AT — 1 at the anchor. Every
/// highlight in the scene shader (steel's glint, marble's sheen, the water's glitter path) is a mirror of the
/// key, and mirrors do not stay bright when the thing they reflect goes out: left at full, a drawn blade blazed
/// like noon under a half moon. Luma-weighted, because what a highlight borrows is the key's BRIGHTNESS.
pub fn keyAmt(p: Palette) f32 {
    const luma = 0.299 * p.key.x + 0.587 * p.key.y + 0.114 * p.key.z;
    return mathx.clampF(luma / ANCHOR_KEY_LUMA, 0, 4);
}
/// …the anchor's own, written out rather than computed off the table so this is a CONSTANT and not a lookup
/// (`paletteAt(SHOT_HOUR)` would be a walk of the keys on every frame). A test pins the two together.
const ANCHOR_KEY_LUMA: f32 = 1.13158; // luma(1.32, 1.10, 0.80)

const Key = struct { at: f32, p: Palette };

/// MIDNIGHT — moonlight, and it is nearly monochrome: a cold key, a cold ambient, and the only warmth in the
/// world coming off the fires themselves (the point lights are untouched by any of this). Hoisted out of the
/// table below because it is THREE of its rows — hour 0, the small hours, and hour 24 — which is what makes
/// the wrap through midnight a blend rather than a seam.
const NIGHT_P = Palette{
    // MOONLIGHT DESATURATES, it does not merely dim: a night whose key keeps the sun's warmth is an overcast
    // afternoon with the brightness turned down, which is exactly how the first pass read. So the red channel
    // goes furthest down and the blue leads — and the level is low enough that the FIRES are what you steer by.
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
    .skyDisc = v3(0.860, 0.885, 0.940), // the MOON: pale, and the brightest thing in the sky
    .cloudDark = v3(0.022, 0.026, 0.042),
    .cloudLit = v3(0.090, 0.100, 0.130),
    .stars = 1.0,
};

/// THE DAY, AS A HANDFUL OF HOURS. Ordered, first key at 0 and last at 24 with the SAME palette on both, so
/// the wrap through midnight is a blend like every other and not a seam.
///
/// **THE `SHOT_HOUR` ROW IS THE ANCHOR AND MAY NOT BE RETUNED CASUALLY** — those are the exact numbers that
/// were baked into the two shaders, measured against real renders (AGENTS.md's albedo rule), and every
/// reference frame in `shots/` is that row. Everything else in this table is free.
const KEYS = [_]Key{
    .{ .at = 0.0, .p = NIGHT_P },
    // THE LAST OF THE DARK, an hour before the sun. The east has begun to go grey-blue and the stars are
    // going out from the bottom up.
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
    // SUNRISE. The one moment the light comes in flat along the ground: a deep red key, the longest shadows
    // the box will hold, and a horizon bank that reaches most of the way up the sky.
    .{ .at = 6.0, .p = .{
        .key = v3(0.940, 0.395, 0.180),
        .ambGround = v3(0.046, 0.038, 0.038),
        .ambSky = v3(0.120, 0.124, 0.166),
        .haze = v3(0.056, 0.046, 0.048),
        // …AND THE BANK IS KEPT UNDER THE ANCHOR'S REACH. Looking down the sun's own bearing this is what the
        // whole distance is mixed toward, and at 0.52 the cliffs forty metres out went to flat pink — the
        // mid-ground stopped existing, which is a wash and not a sunrise.
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
    // MORNING — the warmth burning off, the sky opening up cool and clean. The hour "rest until morning"
    // puts you in, and it is deliberately the CLEAREST light in the day: the fight reads best here.
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
    // NOON. The flattest, least interesting light there is, and it is meant to be: a world with no golden
    // hour in it has nothing to lose when one arrives. Pale key, high cold sky, almost no bank.
    .{ .at = 12.0, .p = .{
        // NOT HOTTER THAN THE ANCHOR, just WHITER. The anchor's key was measured against real renders to sit
        // just under the clip (AGENTS.md's albedo rule), so a noon that pushed every channel past it blew the
        // pale surfaces out. What makes midday read as midday is the warmth LEAVING, not the level arriving.
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
    // THE ANCHOR — the golden hour the whole game was authored and photographed under. Every number in this
    // row came out of the two shaders; see the note above the table before touching one.
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
    // SUNSET, and it is the loudest the sky ever gets: the whole west banked over, the key gone to blood, and
    // the cloud deck lit from underneath.
    .{ .at = 19.4, .p = .{
        .key = v3(1.020, 0.430, 0.185),
        .ambGround = v3(0.052, 0.042, 0.040),
        .ambSky = v3(0.132, 0.136, 0.186),
        .haze = v3(0.066, 0.050, 0.048),
        .hazeBank = v3(0.310, 0.135, 0.050), // the sunrise's reason, one notch louder: this is the LAST of it
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
    // DUSK — the sun gone, the west still holding a band of it, and the first stars out overhead, and it is
    // already cool because there is no sun left in it. **THIS ROW IS ALSO WHERE THE CASTER CHANGES HANDS**
    // (`KEY_SWAP_DUSK`): its key is the dimmest of the ramp, which is the only place a 180-degree flip of the one
    // shadow-casting light can happen without reading as a switch being thrown. Lowering this key makes that
    // moment quieter still; raising it makes the swap visible again.
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
    // NIGHT PROPER, and the wrap.
    .{ .at = 22.5, .p = NIGHT_P },
    .{ .at = HOURS, .p = NIGHT_P },
};

comptime {
    // Ordered, and it spans the whole clock — `paletteAt` walks it forward and interpolates between
    // neighbours, so an out-of-order row is a look that jumps backwards at one hour of the day.
    std.debug.assert(KEYS[0].at == 0);
    std.debug.assert(KEYS[KEYS.len - 1].at == HOURS);
    for (KEYS[1..], 0..) |k, i| std.debug.assert(k.at > KEYS[i].at);
}

/// THE LOOK AT AN HOUR — the two keys either side of it, blended with the ease taken off both ends. A linear
/// walk between keys puts a CORNER in the light at every row (the eye reads a rate change in a sky's colour
/// far more readily than it reads the colour), and dawn arriving as a ramp that stops dead is the whole
/// difference between a cycle and a slideshow.
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

// ——— naming an hour ———

/// THE HOURS A BONFIRE WILL HOLD YOU UNTIL, and the only times in the day with names. Two, because two is
/// what the owner asked for and because they are the two that change how a fight goes: the clearest light in
/// the day, and the last of it.
pub const Until = enum {
    morning,
    evening,

    pub fn hour(u: Until) f32 {
        return switch (u) {
            .morning => 8.5, // the MORNING key — the clean, cold light
            .evening => SHOT_HOUR, // …and the anchor, which is the golden hour the game looks best in
        };
    }
    pub fn label(u: Until) [:0]const u8 {
        return switch (u) {
            .morning => "Rest until morning",
            .evening => "Rest until evening",
        };
    }
};

/// HOW LONG A REST HAS TO CARRY THE CLOCK to reach `to`, always FORWARD: a fire cannot take you backwards
/// through a night you have already spent. Landing exactly on the hour asked for is a full day round.
pub fn hoursUntil(from: f32, to: f32) f32 {
    const d = wrapHour(to - from);
    return if (d <= 1e-4) HOURS else d;
}

/// The clock as a 24-hour readout, for the debug corner and the editor's status line.
pub fn clockText(hour: f32, buf: []u8) []const u8 {
    return clockTextZ(hour, buf);
}

/// …and the same readout NUL-terminated, which is what every text path in this codebase takes (`hud.text`).
/// The FORMAT lives here and `clockText` delegates, so the two shapes cannot print two different clocks.
pub fn clockTextZ(hour: f32, buf: []u8) [:0]const u8 {
    const h = wrapHour(hour);
    const hh: u32 = @intFromFloat(@floor(h));
    const mm: u32 = @intFromFloat(@floor((h - @floor(h)) * 60.0));
    return std.fmt.bufPrintZ(buf, "{d:0>2}:{d:0>2}", .{ hh % 24, mm % 60 }) catch "--:--";
}

/// …and the PHASE it is in, which is what a one-line readout actually wants to say.
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

// ——— tests ———

/// The sun `gfx` used to carry as a constant, and the thing every frame in `shots/` was lit by.
const ANCHOR_DIR = mathx.normV(v3(-0.60, 0.50, -0.46));

test "SHOT_HOUR REPRODUCES THE SUN THE GAME WAS PHOTOGRAPHED UNDER — 362 reference frames ride on it" {
    // A THOUSANDTH OF A UNIT VECTOR is the bar, and it is the right one: that is under a twentieth of a
    // degree of sun, where one shadow-map texel across the 108 m box is already a third of a degree at the
    // distances that matter. Tighter than this is chasing the last bits of an `atan` nobody can photograph.
    const TOL: f32 = 1e-3;
    const d = keyDir(SHOT_HOUR);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.x, d.x, TOL);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.y, d.y, TOL);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.z, d.z, TOL);
    // …and the anchor is the SUN and not the floored key: the golden hour is well above the floor.
    const s = sunDir(SHOT_HOUR);
    try std.testing.expectApproxEqAbs(ANCHOR_DIR.y, s.y, TOL);
}

test "keyAmt is exactly 1 at the anchor, and the specular dims with the light everywhere else" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), keyAmt(paletteAt(SHOT_HOUR)), 1e-4);
    try std.testing.expect(keyAmt(paletteAt(0)) < 0.15); // a blade under a half moon is not a blade at noon
    try std.testing.expect(keyAmt(paletteAt(12)) > 1.0);
    var h: f32 = 0;
    while (h < HOURS) : (h += 0.05) try std.testing.expect(keyAmt(paletteAt(h)) >= 0);
}

test "the palette's anchor row IS the numbers the two shaders carried" {
    const p = paletteAt(SHOT_HOUR);
    try std.testing.expectApproxEqAbs(@as(f32, 1.32), p.key.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.10), p.key.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.80), p.key.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.078), p.haze.x, 1e-5); // gfx.HAZE
    try std.testing.expectApproxEqAbs(@as(f32, 0.070), p.haze.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.056), p.haze.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.168), p.ambSky.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.325), p.skyLow.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p.stars, 1e-6); // no stars in the golden hour
}

test "the sun rises in the east, sets in the west, and is under the world at midnight" {
    try std.testing.expect(sunDir(SUNRISE).y < 1e-4 and sunDir(SUNRISE).y > -1e-4);
    try std.testing.expect(sunDir(SUNSET).y < 1e-4 and sunDir(SUNSET).y > -1e-4);
    try std.testing.expect(sunDir(12.0).y > 0.8); // high at noon
    try std.testing.expect(sunDir(0.0).y < -0.5); // and well under it at midnight
    // The bearing sweeps ONE WAY through the day — never doubles back, which would swing the shadows.
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
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), mathx.lenV(d), 1e-4); // always a unit vector…
        try std.testing.expect(d.y >= floorY - 1e-4); // …and never grazing
        try std.testing.expect(std.math.isFinite(shadowReach(h)));
        try std.testing.expect(shadowReach(h) <= 1.0 / floorY); // bounded, which is what the cull needs
    }
    // …and at night it is the MOON that casts, from the opposite quarter of the sky.
    const night = keyDir(1.0);
    const sunAt1 = sunDir(1.0);
    try std.testing.expect(night.x * sunAt1.x + night.z * sunAt1.z < 0);
}

test "MIDNIGHT IS A BLEND AND NOT A SEAM — the palette is continuous across the wrap" {
    const before = paletteAt(23.999);
    const after = paletteAt(0.001);
    try std.testing.expectApproxEqAbs(before.key.x, after.key.x, 2e-3);
    try std.testing.expectApproxEqAbs(before.skyHigh.z, after.skyHigh.z, 2e-3);
    // …and so is every other hour: no step between neighbouring samples anywhere on the clock.
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
    try std.testing.expect(paletteAt(0).key.x < 0.2); // moonlight
    try std.testing.expect(paletteAt(12).key.x > 1.2); // noon
    try std.testing.expect(paletteAt(0).stars > 0.9 and paletteAt(12).stars == 0);
    // The MOON is the pale thing in the sky and the sun is the warm one, which is the whole read at a glance.
    try std.testing.expect(paletteAt(0).skyDisc.z > paletteAt(0).skyDisc.x);
    try std.testing.expect(paletteAt(SHOT_HOUR).skyDisc.x > paletteAt(SHOT_HOUR).skyDisc.z);
}

test "the clock wraps, holds when frozen, and scrubs both ways" {
    var c = Clock{};
    try std.testing.expectApproxEqAbs(SHOT_HOUR, c.hour, 1e-6);
    c.set(23.5);
    c.rate = 1.0; // an hour a second, for the test
    c.tick(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c.hour, 1e-5); // straight through midnight
    c.freeze(true);
    try std.testing.expect(c.frozen());
    c.tick(100.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c.hour, 1e-5); // a held clock holds
    c.nudge(-1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 23.5), c.hour, 1e-5); // …and scrubs backwards past 0
    // …AND LETTING IT GO GIVES BACK THE SPEED IT WAS ON, not the default. A hold is a look at one moment; it may
    // not quietly undo the Day Speed row, which is what a snap back to `RATE_DEFAULT` did.
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

    // A HELD CLOCK STAYS HELD while its speed is set — the row says how fast, never whether.
    c.cycleSpeed(); // 4x
    c.freeze(true);
    try std.testing.expect(c.frozen());
    c.cycleSpeed();
    try std.testing.expect(c.frozen());
    try std.testing.expectApproxEqAbs(@as(f32, 20), c.speed(), 1e-4); // …and it reports the speed it will START at
    c.freeze(false);
    try std.testing.expect(!c.frozen());
    try std.testing.expectApproxEqAbs(@as(f32, 20), c.speed(), 1e-4);
    // …and the fastest step really is a day you can sit and watch, which is the whole reason the row exists. Set
    // rather than cycled to: the cycle WRAPS, so "keep pressing until it is at the top" is a loop with no end.
    c.resumeRate = RATE_DEFAULT * RATE_MULTS[RATE_MULTS.len - 1];
    c.rate = c.resumeRate;
    try std.testing.expect(c.dayLen() < 15.0);
}

test "THE CASTER MAY ONLY CHANGE HANDS IN THE DARK — the moonrise light switch" {
    // ONE shadow-casting light and a moon that is the ANTI-sun: the swap turns the key most of the way round the
    // compass on one frame, and no arrangement of two opposite bearings avoids that. What CAN be arranged is WHEN
    // it happens, so this measures the swing WEIGHTED BY HOW BRIGHT THE KEY IS while it swings — a 180 degree
    // flip of a light that is nearly out is the light going cold, and the same flip at half the anchor's
    // brightness is every shadow in the world reversing while you watch.
    //
    // Swapped on `isDay` this measured 67.8 (179.9 degrees at 19.99 h, key at 0.471 of the anchor) — the abrupt
    // change the owner reported. Two things fixed it and the bound below is tight enough to hold both: the swap
    // moved to the dim ends of the ramps (`KEY_SWAP_DAWN`/`KEY_SWAP_DUSK`), and the handover became a SWEEP across
    // `KEY_SWAP_FADE` rather than a pick — so the half turn is spread over most of an hour instead of one frame.
    // The STEP is part of the measurement: a coarser walk would smear the flip across two samples and flatter it.
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
    // …and NOTHING anywhere on the clock jumps, lit or not. A hundredth of an hour is 30 real seconds of the
    // standard day: the key may turn, and it may not teleport.
    try std.testing.expect(worst < 6.0);

    // THE ENDS OF A HANDOVER ARE THE TRUE BODIES, to the last bit — the sweep is what happens BETWEEN them, and if
    // the ends drifted then noon would be lit by something that is not the sun.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(keyDir(12.0), mathx.normV(sunDir(12.0))), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(keyDir(0.0), mathx.normV(moonDir(0.0))), 1e-4);

    // …AND THE HANDOVERS HAPPEN IN THE DIM HOURS, which is the whole of why those numbers are what they are. A
    // tenth of the anchor: the fires are what you steer by there, and this is the light they are steering you by.
    try std.testing.expect(keyAmt(paletteAt(KEY_SWAP_DAWN)) < 0.20);
    try std.testing.expect(keyAmt(paletteAt(KEY_SWAP_DUSK)) < 0.20);
    // Each is HALF DONE at its own hour — which is what makes that hour the middle of it and not the start…
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), moonShare(KEY_SWAP_DAWN), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), moonShare(KEY_SWAP_DUSK), 1e-3);
    // …and FINISHED at the window's edges, so the day is lit by a whole sun and the small hours by a whole moon
    // rather than by a permanent blend of the two.
    try std.testing.expectApproxEqAbs(@as(f32, 1), moonShare(KEY_SWAP_DAWN - KEY_SWAP_FADE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(KEY_SWAP_DAWN + KEY_SWAP_FADE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(KEY_SWAP_DUSK - KEY_SWAP_FADE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1), moonShare(KEY_SWAP_DUSK + KEY_SWAP_FADE), 1e-4);
    // THE BRIGHT TERMINATOR HOURS CARRY NO HANDOVER AT ALL. The sunrise and sunset rows are the loudest
    // directional light in the day, and they are the two hours a turning key may never land on.
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(SUNRISE), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), moonShare(SUNSET), 1e-4);
    // …so through the hour on each side of one, the SUN is still what casts — from under the horizon, which is
    // what puts dusk's long shadows away from where it actually went down rather than from the opposite sky.
    try std.testing.expect(sunDir(SUNSET + 0.4).y < 0 and moonShare(SUNSET + 0.4) < 0.05);
    try std.testing.expect(sunDir(SUNRISE - 0.4).y < 0 and moonShare(SUNRISE - 0.4) < 0.05);
    // The floor is what makes that usable: a caster under the horizon still casts from ABOVE it.
    try std.testing.expect(keyDir(SUNSET + 0.4).y > 0);
}

test "a rest always carries the clock FORWARD, and asking for the hour you are on is a full day" {
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), hoursUntil(6.0, 8.5), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), hoursUntil(17.5, 8.5), 1e-5); // round through the night
    try std.testing.expectApproxEqAbs(HOURS, hoursUntil(8.5, 8.5), 1e-4);
    inline for (@typeInfo(Until).@"enum".fields) |f| {
        const u: Until = @enumFromInt(f.value);
        try std.testing.expect(u.label().len > 0);
        try std.testing.expect(u.hour() >= 0 and u.hour() < HOURS);
    }
    // Morning is a DAY hour and so is evening — a fire that put you out in the dark is not a rest.
    try std.testing.expect(isDay(Until.morning.hour()) and isDay(Until.evening.hour()));
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
