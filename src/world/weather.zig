const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;



/// How long the sky stays clear between storms. Long, and RANGED, because the thing that makes weather read
/// as weather is that you cannot tell when it is coming — at a fixed gap it is a metronome.
pub const DRY_LO: f32 = 150.0;
pub const DRY_HI: f32 = 420.0;
/// **THE FIRST GAP IS ITS OWN, AND IT IS SHORT** (owner: played for a while and saw no rain). The ordinary
/// dry spell is minutes long on purpose — but the stream is SEEDED once at startup (`game.init`), so a long
/// opening draw is not bad luck ONCE, it is the same long wait on every launch of the build, forever.
/// Measured at the game's own seed the opening drew **394 s**: six and a half minutes of uninterrupted play
/// before the sky did anything, and the clock only runs while no menu, fire or conversation is up. The first
/// storm has to land inside a session or nobody ever learns the sky does this.
pub const OPEN_LO: f32 = 45.0;
pub const OPEN_HI: f32 = 110.0;
pub const WET_LO: f32 = 55.0;
pub const WET_HI: f32 = 145.0;
/// **IT ARRIVES AND LEAVES OVER A REAL SPAN.** Weather that snaps on is a switch being thrown; the ramp is
/// what makes it something you notice happening. OUT is slower than IN — a shower stops raining in a hurry
/// and the last of it hangs about, which is also the order that never strands the audio bed mid-swell.
pub const RAMP_IN: f32 = 9.0;
pub const RAMP_OUT: f32 = 14.0;

/// **AND IT DOES NOT SIT AT ONE LEVEL WHILE IT IS THERE** (owner: vary the heaviness a bit as it storms). A
/// storm held at its top is a FILTER over the game — the sheet is the same sheet for two minutes and the ear
/// stops hearing the bed. So the level breathes under its own top: two slow swells beating against each other,
/// on periods that do not divide (17.5 s and 30), so a lull never lands twice in the same place in a storm.
///
/// **HOW FAR UNDER ITS TOP A LULL TAKES IT.** Deep enough to see — at a moderate storm the second sheet swings
/// from a fifth of itself to full over one swell (`copyFade`), which is the density visibly moving — and short
/// of the levels other things key off: the flash needs `FLASH_AT` and the lull bottoms out well over it, so
/// lightning cannot switch off inside its own storm.
pub const GUST_DEEP: f32 = 0.30;
const GUST_A: f32 = 17.5;
const GUST_B: f32 = 30.0;
/// The two together close on a full swell at 179 s, so the clock wraps on their common period rather than
/// counting seconds forever — `t`'s own reason one field along.
const GUST_WRAP: f32 = 210.0;

/// 0..1, 1 at the fullest — what the top is multiplied down FROM, never up.
pub fn gustAt(t: f32) f32 {
    const a = 0.5 + 0.5 * mathx.sinf(std.math.tau * t / GUST_A);
    const b = 0.5 + 0.5 * mathx.sinf(std.math.tau * t / GUST_B + 1.7);
    return 1.0 - GUST_DEEP * (1.0 - (a * 0.6 + b * 0.4));
}

pub const Kind = enum { gentle, moderate };
pub const GENTLE_TOP: f32 = 0.52;
pub const MODERATE_TOP: f32 = 1.0;
pub const MODERATE_ODDS: f32 = 0.38;

pub const FLASH_AT: f32 = 0.62;
pub const FLASH_GAP_LO: f32 = 7.0;
pub const FLASH_GAP_HI: f32 = 26.0;
pub const FLASH_DUR: f32 = 0.42;

pub const STRIKE_LO: f32 = 380.0;
pub const STRIKE_HI: f32 = 2600.0;
pub const SOUND_MPS: f32 = 343.0;
pub const BOOM_NEAR: f32 = 1.0;
pub const BOOM_FAR: f32 = 0.34;

pub const Peal = struct { in: f32 = 0, gain: f32 = 0 };
/// **HOW MANY CAN BE IN THE AIR AT ONCE, AND IT IS ARITHMETIC OVER WHAT FEEDS IT** (the ring law): the
/// longest travel is `STRIKE_HI / SOUND_MPS` = 7.58 s and the soonest a second strike can follow is
/// `FLASH_GAP_LO` = 7.0, so a SINGLE slot silently dropped the first roll every time the two overlapped —
/// a flash you saw and never heard. Plus one, because a peal due on a full frame lands the next one.
pub const PEALS: usize = @intFromFloat(@ceil(STRIKE_HI / SOUND_MPS / FLASH_GAP_LO) + 1);

comptime {
    std.debug.assert(@as(f32, @floatFromInt(PEALS)) * FLASH_GAP_LO > STRIKE_HI / SOUND_MPS);
}

pub const DIM_MAX: f32 = 0.17;

/// The overlay's darkening for a wet level — taken off the LEVEL and not off the storm, because a location
/// can now be the thing setting it (`worldfmt.Location.wet`) and the world clock is then only one voice.
pub fn dimOf(level: f32) f32 {
    return level * DIM_MAX;
}

pub const Weather = struct {
    rng: mathx.Rng,
    kind: Kind = .gentle,
    wet: bool = false,
    left: f32 = 0,
    level: f32 = 0,
    flashT: f32 = -1,
    nextFlash: f32 = 0,
    peals: [PEALS]Peal = [_]Peal{.{}} ** PEALS,
    npeals: usize = 0,
    boomGain: f32 = 0,
    boomNow: bool = false,
    t: f32 = 0,
    /// **THE SLOW CLOCK, AND IT IS `f64` FOR THE SAME REASON `t` IS WRAPPED.** `t` above wraps on the rain's
    /// own cell — 5 m at 13 m/s, so it resets 2.6 times a SECOND — because everything it drives is already
    /// modulo that cell and an f32 counting since boot loses the low bits the phase is made of.
    ///
    /// Sporefall needs the opposite: periods of 41 s to 82 s, and handed the rain's clock its motes crept
    /// three centimetres and snapped back forever while the shoal fade never advanced at all (owner: "like
    /// theyre resetting in place"). f64 keeps both ends — a session's worth of seconds and the low bits —
    /// so it never has to wrap and there is no jump to hide.
    slowT: f64 = 0,
    gustT: f32 = 0,

    pub fn init(seed: u64) Weather {
        var w = Weather{ .rng = mathx.Rng.init(seed) };
        w.left = w.rng.range(OPEN_LO, OPEN_HI);
        return w;
    }

    pub fn topFor(k: Kind) f32 {
        return switch (k) {
            .gentle => GENTLE_TOP,
            .moderate => MODERATE_TOP,
        };
    }

    pub fn tick(self: *Weather, dt: f32) void {
        // **THE FALL CLOCK WRAPS ON ITS OWN CELL** — `t` exists only to drive a phase that is already modulo
        // `CELL_H`, and an f32 that has been counting seconds since the game booted has lost the low bits that
        // phase is made of (`audio.mkCrickets`' note, one system along). Wrapped here, it never grows at all.
        self.t = @mod(self.t + dt, CELL_H / FALL_MPS);
        self.slowT += dt;
        self.gustT = @mod(self.gustT + dt, GUST_WRAP);
        self.boomNow = false;
        self.left -= dt;
        if (self.left <= 0) {
            self.wet = !self.wet;
            if (self.wet) {
                self.kind = if (self.rng.float() < MODERATE_ODDS) .moderate else .gentle;
                self.left = self.rng.range(WET_LO, WET_HI);
                self.nextFlash = self.rng.range(FLASH_GAP_LO, FLASH_GAP_HI);
            } else {
                self.left = self.rng.range(DRY_LO, DRY_HI);
            }
        }
        // THE LEVEL WALKS TO WHAT THE CLOCK ASKED FOR. `approach` is the shared ease, so weather arrives the
        // way every other continuous thing in this game does.
        // …AND THE SWELL RIDES ON THE TOP, not on the level: it is what the storm is ASKING for, so the ramp
        // still owns how fast the sheet may move and the gust cannot become a step (`gustAt`).
        const want: f32 = if (self.wet) topFor(self.kind) * gustAt(self.gustT) else 0;
        const secs = if (want > self.level) RAMP_IN else RAMP_OUT;
        self.level = mathx.approach(self.level, want, dt / secs);

        if (self.flashT >= 0) {
            self.flashT += dt;
            if (self.flashT > FLASH_DUR) self.flashT = -1;
        }
        if (self.kind == .moderate and self.wet and self.level >= FLASH_AT) {
            self.nextFlash -= dt;
            if (self.nextFlash <= 0) {
                self.nextFlash = self.rng.range(FLASH_GAP_LO, FLASH_GAP_HI);
                self.flashT = 0;
                const far = self.rng.range(STRIKE_LO, STRIKE_HI);
                const u = (far - STRIKE_LO) / (STRIKE_HI - STRIKE_LO);
                // REFUSED RATHER THAN OVERWRITING THE OLDEST — the ring is sized so it cannot come up
                // (`PEALS`), and a silent overwrite is exactly the bug this replaced.
                if (self.npeals < PEALS) {
                    self.peals[self.npeals] = .{ .in = far / SOUND_MPS, .gain = mathx.lerpF(BOOM_NEAR, BOOM_FAR, u) };
                    self.npeals += 1;
                }
            }
        }
        // THE SOUND IS STILL COMING even if the rain has stopped — a strike you saw is a strike you hear.
        // **ONE ROLL A FRAME**: `thunder` is a single edge, so two peals due together land on consecutive
        // frames rather than one of them being lost. A sixtieth of a second is nothing against a 7 s travel.
        var i: usize = 0;
        while (i < self.npeals) : (i += 1) self.peals[i].in -= dt;
        var due: ?usize = null;
        for (self.peals[0..self.npeals], 0..) |p, k| {
            if (p.in > 0) continue;
            if (due == null or p.in < self.peals[due.?].in) due = k;
        }
        if (due) |k| {
            self.boomGain = self.peals[k].gain;
            self.boomNow = true;
            self.npeals -= 1;
            self.peals[k] = self.peals[self.npeals];
        }
    }

    /// Seconds since boot, for anything whose period is longer than the rain's cell. Cast at the call so
    /// the accumulator keeps its precision and only the sine argument spends it.
    pub fn slowSecs(self: *const Weather) f32 {
        return @floatCast(self.slowT);
    }

    pub fn rain(self: *const Weather) f32 {
        return self.level;
    }

    pub fn flash(self: *const Weather) f32 {
        if (self.flashT < 0) return 0;
        const u = self.flashT / FLASH_DUR;
        if (u < 0.16) return 1.0 - u / 0.16 * 0.35;
        if (u < 0.34) return 0.10;
        if (u < 0.52) return 0.62 * (1.0 - (u - 0.34) / 0.18);
        return 0.10 * (1.0 - (u - 0.52) / 0.48);
    }

    /// The thunder that just arrived, as a gain — a ONE-FRAME edge, null on every other frame.
    pub fn thunder(self: *const Weather) ?f32 {
        return if (self.boomNow) self.boomGain else null;
    }

    pub fn dim(self: *const Weather) f32 {
        return dimOf(self.level);
    }

    /// **THE DEBUG ROW'S OWN CYCLE — dry, gentle, moderate, dry** (`menu.DBG_WEATHER`). It is the day clock's
    /// scrub row one system along, and for the same reason: weather arrives on a clock measured in MINUTES,
    /// so "does it work" is not a question anybody can sit and answer without a way to ask it directly.
    pub fn cycleForce(self: *Weather) void {
        if (!self.wet) return self.force(.gentle, FORCE_DUR);
        if (self.kind == .gentle) return self.force(.moderate, FORCE_DUR);
        self.clear();
    }

    pub const FORCE_DUR: f32 = 180.0;

    pub fn clear(self: *Weather) void {
        self.wet = false;
        self.left = self.rng.range(OPEN_LO, OPEN_HI);
        self.flashT = -1;
        self.nextFlash = 0;
    }

    pub fn says(self: *const Weather) [:0]const u8 {
        if (self.level <= 0.02) return "Weather: Dry";
        return switch (self.kind) {
            .gentle => if (self.wet) "Weather: Gentle" else "Weather: Gentle (clearing)",
            .moderate => if (self.wet) "Weather: Moderate" else "Weather: Moderate (clearing)",
        };
    }

    pub fn force(self: *Weather, k: Kind, secs: f32) void {
        self.kind = k;
        self.wet = true;
        self.left = secs;
        self.level = topFor(k);
        self.nextFlash = 0.01;
    }
};


pub const CELL_H: f32 = 5.0;
/// …and how far out it reaches (owner: spread rain out into the distance). **AND IT HAS TO REACH AS FAR AS
/// THE STORM'S OWN AIR HIDES, WHICH IS THE WHOLE OF THIS NUMBER.** At 24 m it still read as a puddle round the
/// hero, and the arithmetic says why rather than the eye: the haze is `1 - exp(-density * dist)`, so at the
/// old rim a full storm was only 53% thick — half the far field's detail still legible, with no rain anywhere
/// on it. Solved the other way round, against `gfx.HAZE_STORM`: the rim now stands where the air is 80% thick
/// and the taper starts where it is 70%, so the sheet dissolves into murk instead of ending at a wall.
/// **AND THE SPREAD IS ALSO THE THINNING**: streaks are distributed by area (`@sqrt`), so the near field
/// thins as the disc grows, and the far field costs almost no fill because a streak thirty metres out covers
/// a few pixels.
pub const CELL_R: f32 = 40.0;
const TAPER_FROM: f32 = 0.74;
/// How many cells are stacked up the camera's column. Four puts the top of the rain 15 m up, which is over
/// the tallest thing a player stands next to.
pub const STACKS: usize = 4;
pub const STACK_UNDER: f32 = 1.0;

/// Streaks in one cell. **THE ONE PERFORMANCE DIAL, AND THE ONE DENSITY DIAL** — it is what "how hard it is
/// raining" is actually made of, and it moves BOTH strengths together (owner: all forms of rain too heavy).
/// At 820 in an 11.5 m disc the gentle shower was a curtain and the storm was a wall; a test prints the
/// triangles it buys, and the DENSITY it works out to against `CELL_R` — which is the number that reads.
/// **RAISED WITH THE RADIUS, AND BY LESS THAN IT**: at 1000 in the 40 m disc the near field came out at
/// 0.20/m2, a third of what it was, which is drizzle. 2000 lands it at 0.40 — under the old 0.55, since the
/// near field is what "too heavy" was made of, and far enough over drizzle to still be a storm.
pub const STREAKS: usize = 2000;

const LEN_LO: f32 = 0.40;
const LEN_HI: f32 = 0.92;
const WIDE_LO: f32 = 0.008;
const WIDE_HI: f32 = 0.016;

/// **WHICH WAY THE WEATHER IS COMING FROM**, as metres of drift per metre of fall — the same slant for every
/// streak, in WORLD space, so turning the camera turns the rain rather than the rain following the lens.
/// **MEASURED OFF THE FIRST FRAME OF IT, NOT ARGUED.** At 0.17 a 0.9 m streak leans 15 cm over its whole
/// length, which at any framing a player actually uses reads as vertical — and vertical rain is a screen
/// effect. This is a real lean without becoming a gale (that would want the flora bending with it).
const SLANT_X: f32 = 0.30;
const SLANT_Z: f32 = -0.12;

/// Metres a second, at the top of the fall. Real rain runs 7-9; this sits over that, because a game's rain
/// has to read at a glance and in a still frame — but only just over (owner: all rain falls too quickly). At
/// 21 a 0.9 m streak crossed twenty-three times its own body every second, which is not fall, it is a
/// SMEAR: the sheet read as vertical scan lines with the individual drops gone.
pub const FALL_MPS: f32 = 13.0;

const DROP_HEAD = rgba(176, 190, 205, 96);
const DROP_TAIL = rgba(150, 166, 186, 150);

pub const OPACITY: f32 = 0.26;
pub const DOUBLE_AT: f32 = 0.60;
pub const COPY_TOP: f32 = 0.72;
/// The copy is a cell SHORTER than the column under it — it already starts half a cell up, so its top stack
/// sits 17 m over the eye, which is sky nobody is looking at.
pub const COPY_STACKS: usize = STACKS - 1;
/// **AND IT IS OFFSET IN Y, BARELY IN XZ** (owner: rain only on the front right). A 5 m sideways shift of a
/// disc this size put the heavy sheet's overlap — its whole doubled density — off to one quarter, with the
/// opposite side left at single strength and its taper 5 m nearer: the storm was visibly lopsided. Half a cell
/// of HEIGHT is what actually decorrelates the two, and it moves nothing sideways at all.
const COPY_OFF = v3(1.6, CELL_H * 0.5, -1.1);

pub fn copyFade(level: f32) f32 {
    if (level <= DOUBLE_AT) return 0;
    return mathx.clampF((level - DOUBLE_AT) / (MODERATE_TOP - DOUBLE_AT), 0, 1) * COPY_TOP;
}

/// **BUILT ONCE AND PERMANENT** — there is no `unload` and there may not be one: this model's material holds
/// the SCENE shader, and `rl.unloadModel` unloads the material's shader (AGENTS.md's own terrain-tile crash).
/// Everything else drawn through `gfx.Scene` is kept for the process's life on exactly that reasoning.
pub const Rain = struct {
    model: rl.Model,

    pub fn build(shader: rl.Shader) Rain {
        var b = gfx.Builder.init();
        b.setMat(.plain);
        b.setAnimY(0);
        var rng = mathx.Rng.init(0x2A11_D40D);
        for (0..STREAKS) |_| {
            const a = rng.angle();
            const rr = CELL_R * @sqrt(rng.float());
            const x = mathx.cosf(a) * rr;
            const z = mathx.sinf(a) * rr;
            const y = rng.float() * CELL_H;
            // THE OUTER BAND THINS TO NOTHING, so the sheet has no far wall (`TAPER_FROM`). Baked into the
            // GEOMETRY because it has to be: vertex alpha here is the EMISSIVE channel (`gfx` law) and the
            // `fade` uniform is per-DRAW, so a per-streak opacity is the one thing this renderer cannot do.
            const t = mathx.smoothstep(TAPER_FROM * CELL_R, CELL_R, rr);
            const taper = 1.0 - t;
            const len = rng.range(LEN_LO, LEN_HI) * mathx.lerpF(0.55, 1.0, taper);
            const wide = rng.range(WIDE_LO, WIDE_HI) * taper;
            streak(&b, v3(x, y, z), len, wide);
        }
        return .{ .model = b.toModel(shader) };
    }

    /// **THE WHOLE STORM, IN `STACKS` DRAW CALLS** (twice that at the heavier end). The cell is drawn up the
    /// camera's own column and slid down by a phase that WRAPS on `CELL_H`, so the seam between one cell and
    /// the next never arrives — there is no beginning or end to fall off.
    ///
    /// It is drawn LAST, after every opaque thing, with the depth mask off (`Scene.beginFade`) — a streak is a
    /// half-there surface and may not write depth over the world behind it. It is still depth TESTED, which is
    /// what puts the rain behind a wall you are standing under rather than over it.
    /// **CENTRED ON THE MAN, NOT ON THE LENS** (owner: rain must project on all sides of the hero). `at` is his
    /// ground point and `eye` is only where the column is stacked FROM. On the camera the disc reached 24 m
    /// behind the lens and only 19 ahead of the hero — the short side being the side the frame is looking at.
    /// And it has to be a point the CAMERA DOES NOT ROTATE: any lead taken off the camera's own forward slides
    /// the whole sheet sideways when you turn, which is 40 m/s of rain drifting for no physical reason.
    pub fn draw(self: *const Rain, scene: *gfx.Scene, eye: rl.Vector3, at: rl.Vector3, level: f32, t: f32) void {
        if (level <= 0.02) return;
        const lv = mathx.clampF(level, 0, 1);
        const phase = @mod(t * FALL_MPS, CELL_H);
        const baseY = @floor(eye.y) - STACK_UNDER * CELL_H - phase;
        scene.beginFade(OPACITY * lv);
        self.column(v3(at.x, baseY, at.z), STACKS);
        const cf = copyFade(lv);
        if (cf > 0.004) {
            scene.setFade(OPACITY * lv * cf);
            self.column(v3(at.x + COPY_OFF.x, baseY + COPY_OFF.y, at.z + COPY_OFF.z), COPY_STACKS);
        }
        scene.endFade();
    }

    fn column(self: *const Rain, at: rl.Vector3, stacks: usize) void {
        for (0..stacks) |s| {
            const y = at.y + @as(f32, @floatFromInt(s)) * CELL_H;
            rl.drawModelEx(self.model, v3(at.x, y, at.z), v3(0, 1, 0), 0, v3(1, 1, 1), rl.Color.white);
        }
    }
};

fn streak(b: *gfx.Builder, foot: rl.Vector3, len: f32, wide: f32) void {
    const half = len * 0.5;
    const mid = v3(foot.x + SLANT_X * half, foot.y + half, foot.z + SLANT_Z * half);
    const top = v3(foot.x + SLANT_X * len, foot.y + len, foot.z + SLANT_Z * len);
    const w = wide * 0.5;
    for ([_]rl.Vector3{ v3(w, 0, 0), v3(0, 0, w) }) |off| {
        card(b, foot, mid, off, DROP_HEAD, DROP_TAIL);
        card(b, mid, top, off, DROP_TAIL, fade(DROP_TAIL));
    }
}

fn fade(c: rl.Color) rl.Color {
    return rgba(c.r, c.g, c.b, 205);
}

fn card(b: *gfx.Builder, a: rl.Vector3, c: rl.Vector3, off: rl.Vector3, ca: rl.Color, cc: rl.Color) void {
    const n = v3(0, 1, 0);
    b.quadFade(
        v3(a.x - off.x, a.y, a.z - off.z),
        v3(a.x + off.x, a.y, a.z + off.z),
        v3(c.x + off.x, c.y, c.z + off.z),
        v3(c.x - off.x, c.y, c.z - off.z),
        n,
        ca,
        cc,
    );
}

pub fn drawOverlay(w: i32, h: i32, dimAmt: f32, flashAmt: f32) void {
    if (dimAmt > 0.004) {
        rl.drawRectangle(0, 0, w, h, rgba(26, 32, 44, mathx.u8f(255.0 * mathx.clampF(dimAmt, 0, 1))));
    }
    if (flashAmt > 0.004) {
        const a = mathx.clampF(flashAmt, 0, 1);
        // Two passes: a wide pale wash and a brighter core, so the strike has some shape to it rather than
        // being one flat white frame.
        // **MEASURED OFF THE SHOT.** At 120/70 the strike whited the frame out — every contour gone, which
        // reads as fog arriving rather than as light. A flash you can still see the world through is the one
        // that says something happened to the SKY.
        rl.drawRectangle(0, 0, w, h, rgba(198, 210, 236, mathx.u8f(74.0 * a)));
        rl.drawRectangle(0, 0, w, h, rgba(236, 242, 255, mathx.u8f(46.0 * a * a)));
    }
}

test "IT RAINS SOMETIMES, NOT OFTEN AND NOT NEVER — and never twice on the same clock" {
    var w = Weather.init(0xBEEF);
    const dt = 1.0 / 60.0;
    var wet: f32 = 0;
    var storms: usize = 0;
    var wasWet = false;
    var gapLo: f32 = 1e9;
    var gapHi: f32 = 0;
    var gap: f32 = 0;
    var t: f32 = 0;
    while (t < 3600.0) : (t += dt) {
        w.tick(dt);
        if (w.wet) {
            wet += dt;
            if (!wasWet) {
                storms += 1;
                if (storms > 1) {
                    gapLo = @min(gapLo, gap);
                    gapHi = @max(gapHi, gap);
                }
                gap = 0;
            }
        } else gap += dt;
        wasWet = w.wet;
    }
    const share = wet / 3600.0;
    std.debug.print("\n  weather: {d} storms an hour, raining {d:.0}% of the time, dry gaps {d:.0}..{d:.0} s\n", .{ storms, share * 100, gapLo, gapHi });
    try std.testing.expect(storms >= 4 and storms <= 20);
    try std.testing.expect(share > 0.10 and share < 0.45);
    try std.testing.expect(gapLo >= DRY_LO - 1.0);
    try std.testing.expect(gapHi <= DRY_HI + 1.0);
    try std.testing.expect(gapHi - gapLo > 30.0);
}

test "IT ARRIVES AND LEAVES OVER A SPAN — the level never steps, and it always comes back to nothing" {
    var w = Weather.init(7);
    const dt = 1.0 / 60.0;
    var prev = w.level;
    var peak: f32 = 0;
    var biggest: f32 = 0;
    var t: f32 = 0;
    while (t < 2400.0) : (t += dt) {
        w.tick(dt);
        biggest = @max(biggest, @abs(w.level - prev));
        peak = @max(peak, w.level);
        prev = w.level;
        try std.testing.expect(w.level >= 0 and w.level <= MODERATE_TOP + 1e-4);
    }
    // No step: the biggest one-frame move is under what the ramp allows, with a frame of slack.
    try std.testing.expect(biggest <= dt / RAMP_IN * 1.2);
    try std.testing.expect(peak >= GENTLE_TOP * (1.0 - GUST_DEEP) - 0.02);
}

test "A STORM BREATHES — the level moves under its own top, and never over it or under the flash" {
    var w = Weather.init(21);
    w.force(.moderate, 600.0);
    const dt = 1.0 / 60.0;
    var lo: f32 = 1e9;
    var hi: f32 = -1e9;
    var prev = w.level;
    var biggest: f32 = 0;
    var t: f32 = 0;
    while (t < GUST_WRAP) : (t += dt) {
        w.tick(dt);
        if (t > RAMP_OUT) {
            lo = @min(lo, w.level);
            hi = @max(hi, w.level);
        }
        biggest = @max(biggest, @abs(w.level - prev));
        prev = w.level;
        try std.testing.expect(w.level <= MODERATE_TOP + 1e-4);
    }
    std.debug.print("\n  weather: a moderate storm breathes {d:.2}..{d:.2} of full\n", .{ lo, hi });
    try std.testing.expect(hi - lo > 0.12);
    try std.testing.expect(biggest <= dt / RAMP_IN * 1.2);
    try std.testing.expect(MODERATE_TOP * (1.0 - GUST_DEEP) > FLASH_AT);
    // …and the gust is a multiplier DOWN from the top, never up: 1 is its ceiling.
    var u: f32 = 0;
    while (u < GUST_WRAP) : (u += 0.37) {
        const g = gustAt(u);
        try std.testing.expect(g > 1.0 - GUST_DEEP - 1e-5 and g <= 1.0 + 1e-5);
    }
}

test "THE FLASH IS THE MODERATE STORM'S ALONE, and the thunder is LATE by its own distance" {
    var g = Weather.init(11);
    g.force(.gentle, 600.0);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 300.0) : (t += dt) {
        g.tick(dt);
        try std.testing.expectEqual(@as(f32, 0), g.flash());
        try std.testing.expect(g.thunder() == null);
    }

    var m = Weather.init(12);
    m.force(.moderate, 600.0);
    var flashes: usize = 0;
    var booms: usize = 0;
    var sinceFlash: f32 = -1;
    var lagLo: f32 = 1e9;
    var lagHi: f32 = 0;
    t = 0;
    while (t < 300.0) : (t += dt) {
        const wasFlashing = m.flashT >= 0;
        m.tick(dt);
        if (!wasFlashing and m.flashT >= 0) {
            flashes += 1;
            sinceFlash = 0;
        } else if (sinceFlash >= 0) sinceFlash += dt;
        if (m.thunder()) |gain| {
            booms += 1;
            try std.testing.expect(gain > 0 and gain <= BOOM_NEAR);
            try std.testing.expect(sinceFlash > STRIKE_LO / SOUND_MPS - 0.05);
            lagLo = @min(lagLo, sinceFlash);
            lagHi = @max(lagHi, sinceFlash);
        }
    }
    t = 0;
    while (t < STRIKE_HI / SOUND_MPS + 1.0) : (t += dt) {
        m.nextFlash = 1e9;
        m.tick(dt);
        if (m.thunder()) |_| booms += 1;
    }
    std.debug.print("  lightning: {d} strikes in 5 min, thunder {d:.1}..{d:.1} s behind the light\n", .{ flashes, lagLo, lagHi });
    try std.testing.expect(flashes > 5);
    try std.testing.expectEqual(flashes, booms);
    try std.testing.expect(lagHi <= STRIKE_HI / SOUND_MPS + 0.1);
}

test "TWO STRIKES CAN BE IN THE AIR AT ONCE, and NEITHER roll is lost" {
    try std.testing.expect(STRIKE_HI / SOUND_MPS > FLASH_GAP_LO);
    const dt = 1.0 / 60.0;

    var w = Weather.init(1);
    w.force(.moderate, 600.0);
    w.nextFlash = 1e9;
    w.peals[0] = .{ .in = STRIKE_HI / SOUND_MPS, .gain = BOOM_FAR };
    w.peals[1] = .{ .in = 0.40, .gain = BOOM_NEAR };
    w.npeals = 2;
    var heard: [PEALS]f32 = undefined;
    var n: usize = 0;
    var t: f32 = 0;
    while (t < STRIKE_HI / SOUND_MPS + 1.0) : (t += dt) {
        w.tick(dt);
        if (w.thunder()) |gain| {
            try std.testing.expect(n < PEALS);
            heard[n] = gain;
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(BOOM_NEAR, heard[0]);
    try std.testing.expectEqual(BOOM_FAR, heard[1]);

    w.peals[0] = .{ .in = 0.001, .gain = BOOM_NEAR };
    w.peals[1] = .{ .in = 0.001, .gain = BOOM_FAR };
    w.npeals = 2;
    w.tick(dt);
    try std.testing.expect(w.thunder() != null);
    try std.testing.expectEqual(@as(usize, 1), w.npeals);
    w.tick(dt);
    try std.testing.expect(w.thunder() != null);
    try std.testing.expectEqual(@as(usize, 0), w.npeals);
}

test "THE STRIKE IS A DOUBLE, NOT A LAMP — and it is over inside half a second" {
    var w = Weather.init(3);
    w.force(.moderate, 60.0);
    w.flashT = 0;
    var peakEarly: f32 = 0;
    var dip: f32 = 1;
    var peakLate: f32 = 0;
    var u: f32 = 0;
    while (u <= 1.0) : (u += 0.01) {
        w.flashT = u * FLASH_DUR;
        const f = w.flash();
        if (u < 0.16) peakEarly = @max(peakEarly, f);
        if (u > 0.18 and u < 0.32) dip = @min(dip, f);
        if (u > 0.36 and u < 0.50) peakLate = @max(peakLate, f);
    }
    try std.testing.expect(peakEarly > 0.9);
    try std.testing.expect(dip < 0.2);
    try std.testing.expect(peakLate > 0.3 and peakLate < peakEarly);
    w.flashT = FLASH_DUR + 0.001;
    w.nextFlash = 1e9;
    w.tick(1.0 / 60.0);
    try std.testing.expectEqual(@as(f32, 0), w.flash());
}

test "THE SHEET IS A HANDFUL OF DRAW CALLS, and its cost is written down" {
    const tris = STREAKS * 2 * 2 * 2;
    const gentleDraws = STACKS;
    const heavyDraws = STACKS + COPY_STACKS;
    const heavyFill = @as(f32, @floatFromInt(STACKS)) + @as(f32, @floatFromInt(COPY_STACKS)) * COPY_TOP;
    const density = @as(f32, @floatFromInt(STREAKS)) / (std.math.pi * CELL_R * CELL_R);
    std.debug.print("  rain: {d} tris in the cell, {d} draws gentle / {d} moderate ({d} tris on screen, {d:.2} columns of fill), {d:.2} streaks/m2 out to {d:.0} m\n", .{ tris, gentleDraws, heavyDraws, tris * heavyDraws, heavyFill, density, CELL_R });
    // A SHEET YOU CAN SEE THROUGH. At 820 streaks in an 11.5 m disc this was 1.97/m2 — a curtain up against
    // the lens (owner: all forms of rain too heavy), and the near field is where every one of those pixels was.
    try std.testing.expect(density < 1.0);
    try std.testing.expect(heavyDraws <= 8);
    // …and in the triangle one. RAISED WITH THE DISC: reaching 40 m instead of 24 is what stops the sheet
    // reading as a puddle round the hero, and the streaks that buy it are far-field ones a few pixels wide.
    // The DRAW count did not move, which is the half of this that costs state changes.
    try std.testing.expect(tris * heavyDraws < 120_000);
    try std.testing.expect(heavyFill < @as(f32, @floatFromInt(STACKS)) * 1.6);
    try std.testing.expect(DOUBLE_AT > GENTLE_TOP);
}

test "THE HEAVY SHEET FADES, IT DOES NOT ARRIVE — no step anywhere on the ramp" {
    try std.testing.expectEqual(@as(f32, 0), copyFade(0));
    try std.testing.expectEqual(@as(f32, 0), copyFade(GENTLE_TOP));
    try std.testing.expectEqual(@as(f32, 0), copyFade(DOUBLE_AT));
    try std.testing.expectEqual(COPY_TOP, copyFade(MODERATE_TOP));

    var prev = copyFade(0);
    var biggest: f32 = 0;
    var lv: f32 = 0;
    while (lv <= MODERATE_TOP) : (lv += 1e-3) {
        const c = copyFade(lv);
        biggest = @max(biggest, @abs(c - prev));
        prev = c;
    }
    try std.testing.expect(biggest < COPY_TOP * 0.01);

    const secs = (MODERATE_TOP - DOUBLE_AT) * RAMP_IN;
    try std.testing.expect(secs > 3.0);
    std.debug.print("  rain: the heavy sheet fades up over {d:.1}s and out over {d:.1}s\n", .{ secs, (MODERATE_TOP - DOUBLE_AT) * RAMP_OUT });
}

test "THE FALL WRAPS ON THE CELL, so the sheet has no seam and no end" {
    // The phase is what the draw slides the column by, and it may never leave [0, CELL_H) — one metre past it
    // and a whole cell of rain pops a body length up the screen.
    var t: f32 = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) {
        const phase = @mod(t * FALL_MPS, CELL_H);
        try std.testing.expect(phase >= 0 and phase < CELL_H);
    }
    // …and the column reaches over the tallest thing a player stands beside (the knight's 5.2 m crown).
    const tall = @as(f32, @floatFromInt(STACKS)) * CELL_H - STACK_UNDER * CELL_H;
    try std.testing.expect(tall > 5.5);
    try std.testing.expect(FALL_MPS > LEN_HI * 10.0);
}

test "THE FIRST STORM LANDS INSIDE A SESSION, at the seed the game actually ships" {
    // **THE BUG: A SEEDED STREAM MAKES A LONG OPENING DRAW PERMANENT.** At `DRY_LO..DRY_HI` the game's own
    // seed drew 394 s, and because the seed is fixed that was 394 s on EVERY launch of the build — the
    // feature was invisible unless you played six and a half minutes without opening a menu. Pinned at the
    // REAL seed, not a test one, because the whole failure was that one particular draw is the only draw
    // that ever happens.
    const SEED: u64 = 0x5701_A17E;
    var w = Weather.init(SEED);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var seen: f32 = -1;
    while (t < 600.0 and seen < 0) : (t += dt) {
        w.tick(dt);
        if (w.level > 0.02) seen = t;
    }
    std.debug.print("\n  weather: first rain visible {d:.0}s into a session (opening gap {d:.0}..{d:.0}s)\n", .{ seen, OPEN_LO, OPEN_HI });
    try std.testing.expect(seen > 0);
    try std.testing.expect(seen < OPEN_HI + RAMP_IN);
    var fresh = Weather.init(SEED);
    fresh.tick(dt);
    try std.testing.expectEqual(@as(f32, 0), fresh.rain());

    for ([_]u64{ 1, 2, 7, 0xBEEF, 0xD0D0, 0x5701_A17E }) |sd| {
        var g = Weather.init(sd);
        var u: f32 = 0;
        var got: f32 = -1;
        while (u < OPEN_HI + RAMP_IN + 1.0 and got < 0) : (u += dt) {
            g.tick(dt);
            if (g.level > 0.02) got = u;
        }
        try std.testing.expect(got > 0);
    }
}

// ── THE STRAY BANKS ─────────────────────────────────────────────────────────────────────────────────────
//
// **MIST THAT DRIFTS THROUGH, AND ONLY WHEN THE AIR IS ALREADY THICK** (owner: stray volumetric clouds, very
// translucent, gradient-based, flit around softly and slowly during foggy times — VERY slow). The haze
// (`gfx.HAZE_STORM`) is the AIR: it closes the distance evenly and has no shape at all. These are the shape —
// a few banks of it standing in the field, so the fog is somewhere you walk through rather than a value.
//
// **THE GRADIENT IS IN THE GEOMETRY, NOT IN A TEXTURE AND NOT IN SHELLS.** One bank is a CLUSTER of overlapping
// lumps scattered through a flattened volume with the density falling off outward, so the alpha COMPOUNDS where
// they pile up in the middle and thins toward the rim where they run out. That is what makes a soft edge
// without a per-vertex opacity — vertex alpha here is the EMISSIVE channel (`gfx`'s law) — and without three
// concentric shells, each of which would read as a ring. ONE DRAW per bank.
//
// **AND IT IS SLOWER THAN ANYTHING ELSE IN THE GAME.** `DRIFT_HI` is 0.16 m/s: a bank takes a minute and a half
// to cross its own width. Anything you can watch moving reads as a prop being slid; the whole point of this is
// that you never catch it moving, you only notice it has moved.

pub const MIST_CAP: usize = 7;
pub const MIST_KINDS: usize = 3;
const LUMPS: usize = 22;
const LUMP_LO: f32 = 0.30;
const LUMP_HI: f32 = 0.52;
const MIST_FLAT: f32 = 0.34;
const LUMP_SEGS: i32 = 5;
const LUMP_SIDES: i32 = 7;

pub const MIST_R: f32 = 46.0;
const SIZE_LO: f32 = 7.0;
const SIZE_HI: f32 = 15.0;
const RISE_LO: f32 = 0.5;
const RISE_HI: f32 = 2.4;

/// **VERY SLOW** (the owner's own word, twice). Metres a second: the fast end takes 90 s to cross a 15 m bank.
const DRIFT_LO: f32 = 0.045;
const DRIFT_HI: f32 = 0.160;
/// …and it BREATHES rather than only travelling — a slow bob and a slower turn on its own axis, both on periods
/// measured in tens of seconds. This is the "flit", and it is nearly imperceptible per frame by design.
const BOB: f32 = 0.30;
const BOB_SECS_LO: f32 = 26.0;
const BOB_SECS_HI: f32 = 48.0;
const SPIN_LO: f32 = 0.6; // degrees a second
const SPIN_HI: f32 = 2.4;

const LIFE_LO: f32 = 110.0;
const LIFE_HI: f32 = 260.0;
const MIST_FADE: f32 = 26.0;

/// **THE CEILING ON ONE BANK'S OPACITY AT FULL FOG.** Very low — `OPACITY`'s own reasoning one system along: a
/// bank you cannot see the world through is a wall standing in the field (owner: should be less opaque).
pub const MIST_TOP: f32 = 0.10;

const NEAR_GONE: f32 = 0.80;
const NEAR_FULL: f32 = 2.30;
pub const MIST_MIN: f32 = 0.02;

const MIST_COL = rgba(196, 204, 214, 96);

const Bank = struct {
    pos: rl.Vector3 = mathx.zero3,
    r: f32 = 0,
    kind: usize = 0,
    vx: f32 = 0,
    vz: f32 = 0,
    yaw: f32 = 0,
    spin: f32 = 0,
    age: f32 = 0,
    life: f32 = 0,
    bobT: f32 = 0,
    bobSecs: f32 = 0,
};

fn nearFade(bk: Bank, eye: rl.Vector3) f32 {
    const d = mathx.lenV(mathx.subV(bk.pos, eye));
    return mathx.smoothstep(NEAR_GONE * bk.r, NEAR_FULL * bk.r, d);
}

pub const Mist = struct {
    models: [MIST_KINDS]rl.Model,
    banks: [MIST_CAP]Bank = [_]Bank{.{}} ** MIST_CAP,
    rng: mathx.Rng = mathx.Rng.init(0x511F_7A11),
    seeded: bool = false,

    pub fn build(shader: rl.Shader) Mist {
        var out: Mist = .{ .models = undefined };
        var rng = mathx.Rng.init(0x3A57_C10D);
        for (&out.models) |*m| m.* = clusterMesh(shader, &rng);
        return out;
    }

    fn clusterMesh(shader: rl.Shader, rng: *mathx.Rng) rl.Model {
        var b = gfx.Builder.init();
        b.setMat(.plain);
        b.setAnimY(0);
        for (0..LUMPS) |_| {
            const a = rng.angle();
            const u = rng.float();
            const rr = @sqrt(u) * u * 0.92;
            const lr = rng.range(LUMP_LO, LUMP_HI);
            b.addBlob(
                v3(mathx.cosf(a) * rr, rng.signed() * MIST_FLAT * 0.55, mathx.sinf(a) * rr),
                v3(lr, lr * MIST_FLAT, lr * rng.range(0.8, 1.25)),
                LUMP_SEGS,
                LUMP_SIDES,
                MIST_COL,
            );
        }
        return b.toModel(shader);
    }

    fn alphaOf(self: *const Mist, i: usize, fog: f32, eye: rl.Vector3) f32 {
        const bk = self.banks[i];
        if (bk.life <= 0) return 0;
        const inK = mathx.smoothstep(0, MIST_FADE, bk.age);
        const outK = 1.0 - mathx.smoothstep(bk.life - MIST_FADE, bk.life, bk.age);
        return MIST_TOP * mathx.clampF(fog, 0, 1) * inK * outK * nearFade(bk, eye);
    }

    fn seed(self: *Mist, i: usize, at: rl.Vector3, groundY: f32, first: bool) void {
        const a = self.rng.angle();
        const rr = if (first) MIST_R * @sqrt(self.rng.float()) else MIST_R * self.rng.range(0.72, 1.0);
        const spd = self.rng.range(DRIFT_LO, DRIFT_HI);
        const heading = self.rng.angle();
        self.banks[i] = .{
            .pos = v3(at.x + mathx.cosf(a) * rr, groundY + self.rng.range(RISE_LO, RISE_HI), at.z + mathx.sinf(a) * rr),
            .r = self.rng.range(SIZE_LO, SIZE_HI) * 0.5,
            .kind = @intFromFloat(self.rng.float() * @as(f32, @floatFromInt(MIST_KINDS)) * 0.999),
            .vx = mathx.cosf(heading) * spd,
            .vz = mathx.sinf(heading) * spd,
            .yaw = mathx.degrees(self.rng.angle()),
            .spin = self.rng.range(SPIN_LO, SPIN_HI) * (if (self.rng.float() < 0.5) @as(f32, -1) else 1),
            .age = if (first) self.rng.range(0, LIFE_LO * 0.5) else 0,
            .life = self.rng.range(LIFE_LO, LIFE_HI),
            .bobT = self.rng.range(0, 60),
            .bobSecs = self.rng.range(BOB_SECS_LO, BOB_SECS_HI),
        };
    }

    /// THE DRIFT. `at` is the man, `groundY` the height under him, `fog` 0..1 — and at nothing it does nothing,
    /// which is what every clear day in the game pays for this.
    ///
    /// It drifts LEVEL rather than following the terrain under it: at 0.16 m/s nobody can tell, and sampling the
    /// heightfield per bank per frame cannot be justified by a picture nobody can see.
    pub fn tick(self: *Mist, dt: f32, at: rl.Vector3, groundY: f32, fog: f32) void {
        if (fog <= MIST_MIN) {
            self.seeded = false;
            return;
        }
        if (!self.seeded) {
            self.seeded = true;
            for (0..MIST_CAP) |i| self.seed(i, at, groundY, true);
            return;
        }
        for (0..MIST_CAP) |i| {
            const bk = &self.banks[i];
            bk.age += dt;
            bk.bobT += dt;
            bk.pos.x += bk.vx * dt;
            bk.pos.z += bk.vz * dt;
            bk.yaw += bk.spin * dt;
            if (bk.age >= bk.life or mathx.distXZ(bk.pos, at) > MIST_R * 1.35) self.seed(i, at, groundY, false);
        }
    }

    /// **ONE BANK AT A KNOWN PLACE AND FULL STRENGTH** — the shot harness's own (`game.forceMistForShot`,
    /// `Weather.force`'s arrangement). The field seeds itself out at 33..46 m because that is where weather
    /// belongs; a PHOTOGRAPH of a bank has to have one in the frame, mid-life and past both ramps.
    pub fn stageOne(self: *Mist, at: rl.Vector3, ahead: f32, facing: f32) void {
        self.seeded = true;
        for (&self.banks) |*b| b.* = .{};
        const d = mathx.headingDir(facing);
        self.banks[0] = .{
            .pos = v3(at.x + d.x * ahead, at.y + RISE_HI, at.z + d.z * ahead),
            .r = SIZE_HI * 0.5,
            .life = LIFE_HI,
            .age = LIFE_HI * 0.5,
            .bobSecs = BOB_SECS_LO,
        };
    }

    pub fn draw(self: *const Mist, scene: *gfx.Scene, eye: rl.Vector3, fog: f32, tint: rl.Color) void {
        if (fog <= MIST_MIN) return;
        var any = false;
        for (0..MIST_CAP) |i| {
            const a = self.alphaOf(i, fog, eye);
            if (a <= 0.004) continue;
            if (!any) {
                scene.beginFade(a);
                any = true;
            } else scene.setFade(a);
            const bk = self.banks[i];
            const bob = mathx.sinf(std.math.tau * bk.bobT / bk.bobSecs) * BOB;
            const s = bk.r;
            rl.drawModelEx(
                self.models[@min(bk.kind, MIST_KINDS - 1)],
                v3(bk.pos.x, bk.pos.y + bob, bk.pos.z),
                v3(0, 1, 0),
                bk.yaw,
                v3(s, s, s),
                tint,
            );
        }
        if (any) scene.endFade();
    }
};

test "A BANK IS SLOWER THAN ANYTHING ELSE IN THE WORLD, and you never catch it arriving" {
    const crossing = SIZE_HI / DRIFT_HI;
    std.debug.print("\n  mist: a {d:.0} m bank crosses its own width in {d:.0} s ({d:.3}..{d:.3} m/s), {d} banks of {d} lumps\n", .{ SIZE_HI, crossing, DRIFT_LO, DRIFT_HI, MIST_CAP, LUMPS });
    try std.testing.expect(crossing > 60.0);
    try std.testing.expect(DRIFT_HI < FALL_MPS * 0.02);
    try std.testing.expect(MIST_FADE * 2.0 < LIFE_LO);
    try std.testing.expect(MIST_TOP < 0.25);
    const tris = MIST_CAP * LUMPS * @as(usize, @intCast(LUMP_SEGS * LUMP_SIDES * 2));
    std.debug.print("  ...and the whole field is {d} draws, {d} tris\n", .{ MIST_CAP, tris });
    try std.testing.expect(MIST_CAP <= STACKS + COPY_STACKS);
}

test "THE BANKS COST NOTHING ON A CLEAR DAY, and the first foggy frame places them around him" {
    var m = Mist{ .models = undefined };
    m.tick(1.0 / 60.0, mathx.zero3, 0, 0);
    try std.testing.expect(!m.seeded);
    try std.testing.expectEqual(@as(f32, 0), m.alphaOf(0, 0, mathx.zero3));

    // The first foggy frame places every one of them, inside the ring, none at more than its ceiling. Judged
    // from a lens well outside the field, or the near fade is what is being measured instead.
    const far = v3(0, 2, -400);
    m.tick(1.0 / 60.0, mathx.zero3, 0, 1.0);
    try std.testing.expect(m.seeded);
    for (0..MIST_CAP) |i| {
        const bk = m.banks[i];
        try std.testing.expect(bk.life >= LIFE_LO and bk.life <= LIFE_HI);
        try std.testing.expect(mathx.distXZ(bk.pos, mathx.zero3) <= MIST_R + 1e-3);
        try std.testing.expect(bk.kind < MIST_KINDS);
        try std.testing.expect(m.alphaOf(i, 1.0, far) <= MIST_TOP + 1e-5);
        try std.testing.expect(bk.r >= SIZE_LO * 0.5 and bk.r <= SIZE_HI * 0.5);
    }

    var t: f32 = 0;
    while (t < 3600.0) : (t += 1.0 / 30.0) {
        m.tick(1.0 / 30.0, mathx.zero3, 0, 1.0);
        for (0..MIST_CAP) |i| try std.testing.expect(mathx.distXZ(m.banks[i].pos, mathx.zero3) <= MIST_R * 1.36);
    }
    m.tick(1.0 / 60.0, mathx.zero3, 0, 0);
    try std.testing.expect(!m.seeded);
}

test "A BANK GIVES WAY AS YOU WALK INTO IT, AND COMES BACK AS YOU LEAVE" {
    const bk = Bank{ .pos = mathx.zero3, .r = 6.0, .life = LIFE_HI, .age = LIFE_HI * 0.5 };
    try std.testing.expectEqual(@as(f32, 0), nearFade(bk, mathx.zero3));
    try std.testing.expectEqual(@as(f32, 0), nearFade(bk, v3(NEAR_GONE * bk.r * 0.99, 0, 0)));
    try std.testing.expectEqual(@as(f32, 1), nearFade(bk, v3(NEAR_FULL * bk.r + 0.01, 0, 0)));
    var prev: f32 = 1.0;
    var d: f32 = NEAR_FULL * bk.r + 2.0;
    while (d >= 0) : (d -= 0.05) {
        const got = nearFade(bk, v3(d, 0, 0));
        try std.testing.expect(got <= prev + 1e-6);
        prev = got;
    }
    try std.testing.expect(nearFade(bk, v3(0, 12.0, 0)) > 0.5);

    var small = bk;
    small.r = 3.5;
    const at: f32 = 8.0;
    try std.testing.expect(nearFade(small, v3(at, 0, 0)) > nearFade(bk, v3(at, 0, 0)));

    try std.testing.expect(MIST_FADE * 3.0 < LIFE_LO);
    std.debug.print("  mist: {d:.0}s ramps inside a {d:.0}..{d:.0}s life, gone within {d:.1}x its radius, full past {d:.1}x\n", .{ MIST_FADE, LIFE_LO, LIFE_HI, NEAR_GONE, NEAR_FULL });
}

// ============================================================================================================
// SPOREFALL — THE THIRD WEATHER
// ============================================================================================================
//
// **IT IS NOT FOG WITH A FILTER ON IT.** Rain and fog are both the sky going grey; a spore bloom is the AIR
// ITSELF being alive, and it has to read on a bright noon as well as under cloud. So it is three things at
// once and all three are driven off the one 0..1 dial:
//
//   1. the distance haze turns peach (`sporeHaze`, pushed through `gfx.Scene.setHour`),
//   2. the drifting banks stop being grey and become lit cloud (`sporeTint` on the mist's own draw),
//   3. and there are SPORES IN IT — this system, a slow-falling mote cell round the camera.
//
// The motes are the part that says "alive" rather than "weather". They fall at `SPORE_MPS`, which is 3% of
// rain: near enough to hanging that the eye reads drift, far enough from still that the air is not frozen.

/// **HOW FAR THE MOTES REACH.** Smaller than `CELL_R` on purpose — rain is a sheet you stand under and see
/// across a field, spores are something in the air AROUND YOU. Past this the peach haze carries it instead,
/// and haze costs no fill at all.
pub const SPORE_R: f32 = 26.0;
pub const SPORE_CELL_H: f32 = 7.0;
pub const SPORE_STACKS: usize = 3;

/// Motes across the WHOLE field, split evenly between the shoals below. Raised with the fade: an average
/// shoal sits at half strength, so the cloud needs more of them to hold the density it had when all were on.
pub const MOTES: usize = 420;
const MOTE_LO: f32 = 0.016;
const MOTE_HI: f32 = 0.052;

/// **SPORES DO NOT TRAVEL, THEY HANG** (owner: "too fast ... sloooowww"). Metres a second. Rain is 13; this
/// is under a hundredth of it, and one mote takes over a minute to cross its own cell. At the first cut's
/// 0.40 the field read as fine snow, which is a thing that falls.
pub const SPORE_MPS: f32 = 0.085;
/// …and it does not settle STRAIGHT. Each shoal swims on two out-of-phase periods — slowed WITH the fall,
/// because a slow drift under a fast wobble reads as jitter rather than as air. Metres, and seconds.
///
/// **AND EVERY SHOAL SWIMS ITS OWN WAY** (owner: "they need to vary over time positionally"). Shared, these
/// terms move all 420 motes as one rigid block: the cloud translates and nothing inside it ever changes,
/// which is what made it read as a stuck object rather than as air. Detuned per shoal, five clouds drift
/// through each other and the field has internal motion without a per-mote vertex path.
const SWIM_X: f32 = 1.60;
const SWIM_Z: f32 = 1.15;
const SWIM_SECS_X: f32 = 54.0;
const SWIM_SECS_Z: f32 = 37.0;
/// How far apart the shoals are detuned, as a fraction either side of the base period. Wide enough that no
/// two come back into step inside a session.
const SWIM_SPREAD: f32 = 0.42;

fn swimOf(t: f32, i: usize) rl.Vector3 {
    const k = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(SPORE_SHOALS)) - 0.5;
    const px = SWIM_SECS_X * (1.0 + SWIM_SPREAD * k * 2.0);
    const pz = SWIM_SECS_Z * (1.0 - SWIM_SPREAD * k * 1.7);
    const off = @as(f32, @floatFromInt(i)) * 2.399;
    return v3(
        mathx.sinf(std.math.tau * t / px + off) * SWIM_X * (0.7 + 0.6 * @abs(k * 2.0)),
        // A little vertical wander on top of the settle, so a shoal is not a plane sliding sideways.
        mathx.sinf(std.math.tau * t / (px * 1.63) + off * 1.7) * 0.55,
        mathx.cosf(std.math.tau * t / pz + off * 0.7) * SWIM_Z * (0.7 + 0.6 * @abs(k * 2.0)),
    );
}

/// **PEACH, AND EMISSIVE.** Alpha is the emissive channel (`gfx` law), so 236 is a mote that keeps its colour
/// in shadow — which is the whole point of a glowing spore. The pair gives the cloud two tones at any depth.
const MOTE_WARM = rgba(255, 208, 178, 236);
const MOTE_PALE = rgba(255, 232, 214, 214);

// -- AND THEY FADE IN AND OUT --------------------------------------------------------------------------
//
// **A SPORE HAS TO ARRIVE AND LEAVE, NOT ENTER AND EXIT.** With one mote field the only way out of frame is
// to fall out of the bottom, and at `SPORE_MPS` that now takes a minute and a half — so the cloud would be
// the same cloud, motionless, forever.
//
// Vertex alpha is the EMISSIVE channel (`gfx` law) and the `fade` uniform is per-DRAW, so a per-mote opacity
// is the one thing this renderer cannot do — the same wall `Rain` hits with its taper, which it solves by
// baking the thinning into the GEOMETRY. That cannot work here, because this one has to move.
//
// So the field is cut into `SPORE_SHOALS` separate models, each drawn at its own `fade` on a long sine
// offset a fifth of a period from its neighbour's. Each shoal materialises, drifts and dissolves; because
// they are out of phase the field as a whole never blinks, which a test pins.
pub const SPORE_SHOALS: usize = 5;
/// Seconds for one shoal to come up and go back down. Long — the slowest cycle in the game after a mist
/// bank's life, and under half a minute the field pulses like a heartbeat.
pub const SHOAL_SECS: f32 = 41.0;

/// One shoal's share of the light, 0..1, on its own offset cycle. Held off zero rather than run to it: a
/// shoal that vanishes outright pops on the frame it comes back.
pub fn shoalFade(t: f32, i: usize) f32 {
    const off = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(SPORE_SHOALS));
    const u = @mod(t / SHOAL_SECS + off, 1.0);
    return 0.10 + 0.90 * (0.5 - 0.5 * mathx.cosf(std.math.tau * u));
}

pub const SPORE_OPACITY: f32 = 0.62;
const SPORE_TAPER: f32 = 0.70;

/// The tint the mist banks are drawn with, so one grey mesh serves both weathers. White is the bank's own
/// `MIST_COL`; at full spore it is peach lit from inside.
pub fn sporeTint(k: f32) rl.Color {
    const t = mathx.clampF(k, 0, 1);
    return rgba(
        255,
        @intFromFloat(mathx.lerpF(255, 196, t)),
        @intFromFloat(mathx.lerpF(255, 170, t)),
        255,
    );
}

/// **BUILT ONCE AND PERMANENT**, same reasoning as `Rain` — the material holds the scene shader.
pub const Spore = struct {
    shoals: [SPORE_SHOALS]rl.Model,

    pub fn build(shader: rl.Shader) Spore {
        var out: Spore = .{ .shoals = undefined };
        var rng = mathx.Rng.init(0x5F0AE_11FE);
        for (&out.shoals) |*into| {
            var b = gfx.Builder.init();
            b.setMat(.plain);
            b.setAnimY(0);
            for (0..MOTES / SPORE_SHOALS) |_| {
                const a = rng.angle();
                const rr = SPORE_R * @sqrt(rng.float());
                const t = mathx.smoothstep(SPORE_TAPER * SPORE_R, SPORE_R, rr);
                const r = rng.range(MOTE_LO, MOTE_HI) * (1.0 - t * 0.55);
                b.addBlob(
                    v3(mathx.cosf(a) * rr, rng.float() * SPORE_CELL_H, mathx.sinf(a) * rr),
                    v3(r, r * rng.range(0.7, 1.3), r),
                    2,
                    4,
                    if (rng.float() < 0.34) MOTE_PALE else MOTE_WARM,
                );
            }
            into.* = b.toModel(shader);
        }
        return out;
    }

    /// Stacked and wrapped like the rain, but the wrap is on `SPORE_MPS` — and the whole column swims
    /// sideways, which the rain must never do (a slanted sheet that slides is a camera bug; a cloud of seed
    /// that slides is wind). Each shoal carries its own `fade`, so they arrive and leave out of phase.
    pub fn draw(self: *const Spore, scene: *gfx.Scene, eye: rl.Vector3, at: rl.Vector3, level: f32, t: f32) void {
        if (level <= 0.02) return;
        const lv = mathx.clampF(level, 0, 1);
        // **NO `@floor` ON THE EYE.** `Rain` quantises its column to a whole metre so the sheet does not
        // slide as the camera bobs, and at 13 m/s that snap is a thirteenth of a second of travel — nobody
        // sees it. At 0.085 m/s the SAME snap is twelve seconds of drift arriving on one frame, and it read
        // exactly as the owner described: motes resetting in place. The column follows the eye continuously.
        var any = false;
        for (&self.shoals, 0..) |*m, si| {
            const amt = SPORE_OPACITY * lv * shoalFade(t, si);
            if (amt <= 0.004) continue;
            if (!any) {
                scene.beginFade(amt);
                any = true;
            } else scene.setFade(amt);
            const sw = swimOf(t, si);
            // Each shoal falls on its OWN phase too, so they do not all wrap on the same frame.
            const lead = @as(f32, @floatFromInt(si)) * SPORE_CELL_H / @as(f32, @floatFromInt(SPORE_SHOALS));
            const phase = @mod(t * SPORE_MPS + lead, SPORE_CELL_H);
            const baseY = eye.y - SPORE_CELL_H * 1.5 - phase + sw.y;
            for (0..SPORE_STACKS) |i| {
                const y = baseY + @as(f32, @floatFromInt(i)) * SPORE_CELL_H;
                rl.drawModelEx(m.*, v3(at.x + sw.x, y, at.z + sw.z), v3(0, 1, 0), 0, v3(1, 1, 1), rl.Color.white);
            }
        }
        if (any) scene.endFade();
    }
};

test "A SPORE SETTLES, IT DOES NOT FALL - and the shoals breathe out of phase so the field never blinks" {
    const cross = SPORE_CELL_H / SPORE_MPS;
    std.debug.print("\n  spore: {d:.3} m/s, one mote crosses its {d:.0} m cell in {d:.0} s ({d:.0}x slower than rain)\n", .{ SPORE_MPS, SPORE_CELL_H, cross, FALL_MPS / SPORE_MPS });
    try std.testing.expect(SPORE_MPS < FALL_MPS * 0.01);
    try std.testing.expect(cross > 60.0);
    // The wobble has to be SLOWER than the fall, or the drift reads as jitter rather than as air.
    try std.testing.expect(SWIM_SECS_X > cross * 0.5);
    // No two shoals peak together, and the field never goes dark or surges.
    var lo: f32 = 1e9;
    var hi: f32 = -1e9;
    var step: f32 = 0;
    while (step < SHOAL_SECS) : (step += 0.25) {
        var sum: f32 = 0;
        for (0..SPORE_SHOALS) |i| sum += shoalFade(step, i);
        lo = @min(lo, sum);
        hi = @max(hi, sum);
    }
    std.debug.print("  ...{d} shoals on a {d:.0} s cycle: the field holds between {d:.2} and {d:.2} shoals lit\n", .{ SPORE_SHOALS, SHOAL_SECS, lo, hi });
    try std.testing.expect(lo > @as(f32, @floatFromInt(SPORE_SHOALS)) * 0.35);
    try std.testing.expect((hi - lo) / hi < 0.08);
    const tris = MOTES * 2 * 4 * 2;
    std.debug.print("  ...{d} motes, {d} tris over the field, {d} draws at full - the rain is {d} tris in {d}\n", .{ MOTES, tris, SPORE_SHOALS * SPORE_STACKS, STREAKS * 2, STACKS });
}

test "THE SPORE FIELD IS NOT ON THE RAIN'S CLOCK - that one wraps 2.6 times a second" {
    const rainWrap = CELL_H / FALL_MPS;
    const fall = SPORE_CELL_H / SPORE_MPS;
    std.debug.print("\n  clocks: rain t wraps every {d:.3} s; sporefall needs {d:.0} s to fall a cell and {d:.0} s to breathe\n", .{ rainWrap, fall, SHOAL_SECS });
    // Handed `Weather.t`, every spore period below was a sawtooth a third of a second long.
    try std.testing.expect(rainWrap < 0.5);
    try std.testing.expect(fall > rainWrap * 100.0);
    try std.testing.expect(SHOAL_SECS > rainWrap * 100.0);
    // The slow clock climbs and never wraps.
    var w = Weather.init(1);
    var i: usize = 0;
    while (i < 60 * 200) : (i += 1) w.tick(1.0 / 60.0);
    std.debug.print("  ...after 200 s of ticks: rain t = {d:.3}, slow = {d:.1}\n", .{ w.t, w.slowSecs() });
    try std.testing.expect(w.slowSecs() > 199.0);
    try std.testing.expect(w.t < rainWrap);
    // …and the shoals actually move on it, which they did not on the old one.
    try std.testing.expect(@abs(shoalFade(0, 0) - shoalFade(SHOAL_SECS * 0.5, 0)) > 0.5);
    try std.testing.expect(@abs(shoalFade(0, 0) - shoalFade(rainWrap, 0)) < 0.01);
    // Every shoal swims its own way: none of them share a displacement at any instant.
    for (1..SPORE_SHOALS) |k| {
        const a = swimOf(17.0, 0);
        const b = swimOf(17.0, k);
        try std.testing.expect(mathx.lenV(mathx.subV(a, b)) > 0.15);
    }
}
