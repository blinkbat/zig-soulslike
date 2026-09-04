const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const camera = @import("../core/camera.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;



pub const DRY_LO: f32 = 150.0;
pub const DRY_HI: f32 = 420.0;
/// THE FIRST GAP IS ITS OWN, AND IT IS SHORT. The stream is SEEDED once at startup (`game.init`), so a long opening draw is the same wait on every launch of the build: measured at the game's own seed, 394 s.
pub const OPEN_LO: f32 = 45.0;
pub const OPEN_HI: f32 = 110.0;
pub const WET_LO: f32 = 55.0;
pub const WET_HI: f32 = 145.0;
pub const RAMP_IN: f32 = 9.0;
pub const RAMP_OUT: f32 = 14.0;

/// The level breathes under its own top — two swells on periods that do not divide (17.5 s and 30). It bottoms out well over `FLASH_AT`, so lightning cannot switch off inside its own storm.
pub const GUST_DEEP: f32 = 0.30;
const GUST_A: f32 = 17.5;
const GUST_B: f32 = 30.0;
/// The two close on a full swell at 179 s, so the clock wraps on their common period (`t`'s own reason).
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
/// ARITHMETIC OVER WHAT FEEDS IT (the ring law): `STRIKE_HI / SOUND_MPS` = 7.58 s of travel against `FLASH_GAP_LO` = 7.0 between strikes, so a SINGLE slot dropped the first roll whenever the two overlapped. Plus one, because a peal due on a full frame lands next.
pub const PEALS: usize = @intFromFloat(@ceil(STRIKE_HI / SOUND_MPS / FLASH_GAP_LO) + 1);

comptime {
    std.debug.assert(@as(f32, @floatFromInt(PEALS)) * FLASH_GAP_LO > STRIKE_HI / SOUND_MPS);
}

pub const DIM_MAX: f32 = 0.17;

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
    /// THE SLOW CLOCK, and it is `f64` for the same reason `t` is wrapped: `t` wraps on the rain's own cell — 5 m at 13 m/s, so 2.6 times a SECOND — and sporefall needs periods of 41 s to 82 s.
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
        // THE FALL CLOCK WRAPS ON ITS OWN CELL: `t` exists only to drive a phase already modulo `CELL_H`, and an f32 counting seconds since boot has lost the low bits that phase is made of.
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
                if (self.npeals < PEALS) {
                    self.peals[self.npeals] = .{ .in = far / SOUND_MPS, .gain = mathx.lerpF(BOOM_NEAR, BOOM_FAR, u) };
                    self.npeals += 1;
                }
            }
        }
        // The sound is still coming even if the rain has stopped. ONE ROLL A FRAME: two peals due together land on consecutive frames rather than one being lost.
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

    pub fn thunder(self: *const Weather) ?f32 {
        return if (self.boomNow) self.boomGain else null;
    }

    pub fn dim(self: *const Weather) f32 {
        return dimOf(self.level);
    }

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
/// The haze is `1 - exp(-density * dist)`, so at a 24 m rim a full storm was only 53% thick. Solved against `gfx.HAZE_STORM`: the rim stands where the air is 80% thick and the taper starts at 70%.
/// AND THE SPREAD IS ALSO THE THINNING — streaks are distributed by area (`@sqrt`), so the near field thins as the disc grows.
pub const CELL_R: f32 = 40.0;
const TAPER_FROM: f32 = 0.74;
/// How many cells are stacked up the camera's column. Four puts the top of the rain 15 m up.
pub const STACKS: usize = 4;
pub const STACK_UNDER: f32 = 1.0;

/// Streaks in one cell. THE ONE PERFORMANCE DIAL, AND THE ONE DENSITY DIAL. Raised with the radius and by LESS than it: 2000 in the 40 m disc lands 0.40/m², under the old 0.55.
pub const STREAKS: usize = 2000;

const LEN_LO: f32 = 0.40;
const LEN_HI: f32 = 0.92;
const WIDE_LO: f32 = 0.008;
const WIDE_HI: f32 = 0.016;

/// WHICH WAY THE WEATHER IS COMING FROM, as metres of drift per metre of fall — the same slant for every streak, in WORLD space, so turning the camera turns the rain rather than the rain following the lens.
const SLANT_X: f32 = 0.30;
const SLANT_Z: f32 = -0.12;

/// Metres a second, at the top of the fall. Real rain runs 7-9 and this sits just over it.
pub const FALL_MPS: f32 = 13.0;

const DROP_HEAD = rgba(176, 190, 205, 96);
const DROP_TAIL = rgba(150, 166, 186, 150);

pub const OPACITY: f32 = 0.26;
pub const DOUBLE_AT: f32 = 0.60;
pub const COPY_TOP: f32 = 0.72;
/// The copy is a cell SHORTER than the column under it — it already starts half a cell up, so its top stack sits 17 m over the eye.
pub const COPY_STACKS: usize = STACKS - 1;
const COPY_OFF = v3(1.6, CELL_H * 0.5, -1.1);

pub fn copyFade(level: f32) f32 {
    if (level <= DOUBLE_AT) return 0;
    return mathx.clampF((level - DOUBLE_AT) / (MODERATE_TOP - DOUBLE_AT), 0, 1) * COPY_TOP;
}

/// **BUILT ONCE AND PERMANENT** — there is no `unload` and there may not be one: this model's material holds the SCENE shader, and `rl.unloadModel` unloads the material's shader (AGENTS.md's terrain-tile crash).
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
            const t = mathx.smoothstep(TAPER_FROM * CELL_R, CELL_R, rr);
            const taper = 1.0 - t;
            const len = rng.range(LEN_LO, LEN_HI) * mathx.lerpF(0.55, 1.0, taper);
            const wide = rng.range(WIDE_LO, WIDE_HI) * taper;
            streak(&b, v3(x, y, z), len, wide);
        }
        return .{ .model = b.toModel(shader) };
    }

    /// CENTRED ON THE MAN, NOT ON THE LENS, and it must be a point the CAMERA DOES NOT ROTATE or turning slides the rain.
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
    return mathx.withAlpha(c, 205);
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
    try std.testing.expect(density < 1.0);
    try std.testing.expect(heavyDraws <= 8);
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
    // The phase is what the draw slides the column by, and it may never leave [0, CELL_H) — one metre past it and a whole cell of rain pops a body length up the screen.
    var t: f32 = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) {
        const phase = @mod(t * FALL_MPS, CELL_H);
        try std.testing.expect(phase >= 0 and phase < CELL_H);
    }
    const tall = @as(f32, @floatFromInt(STACKS)) * CELL_H - STACK_UNDER * CELL_H;
    try std.testing.expect(tall > 5.5);
    try std.testing.expect(FALL_MPS > LEN_HI * 10.0);
}

test "THE FIRST STORM LANDS INSIDE A SESSION, at the seed the game actually ships" {
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

const DRIFT_LO: f32 = 0.045;
const DRIFT_HI: f32 = 0.160;
const BOB: f32 = 0.30;
const BOB_SECS_LO: f32 = 26.0;
const BOB_SECS_HI: f32 = 48.0;
const SPIN_LO: f32 = 0.6; // degrees a second
const SPIN_HI: f32 = 2.4;

const LIFE_LO: f32 = 110.0;
const LIFE_HI: f32 = 260.0;
const MIST_FADE: f32 = 26.0;

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

    /// THE DRIFT. `at` is the man, `groundY` the height under him, `fog` 0..1. It drifts LEVEL rather than following the terrain — at 0.16 m/s nobody can tell.
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


pub const SPORE_R: f32 = 26.0;
pub const SPORE_CELL_H: f32 = 7.0;
pub const SPORE_STACKS: usize = 3;

pub const MOTES: usize = 420;
const MOTE_LO: f32 = 0.016;
const MOTE_HI: f32 = 0.052;

/// SPORES DO NOT TRAVEL, THEY HANG. Metres a second — rain is 13, and one mote takes over a minute to cross its own cell.
pub const SPORE_MPS: f32 = 0.085;
/// Each shoal swims on two out-of-phase periods, slowed WITH the fall. Metres, and seconds. AND EVERY SHOAL SWIMS ITS OWN WAY — shared, these terms move all 420 motes as one rigid block.
const SWIM_X: f32 = 1.60;
const SWIM_Z: f32 = 1.15;
const SWIM_SECS_X: f32 = 54.0;
const SWIM_SECS_Z: f32 = 37.0;
const SWIM_SPREAD: f32 = 0.42;

fn swimOf(t: f32, i: usize) rl.Vector3 {
    const k = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(SPORE_SHOALS)) - 0.5;
    const px = SWIM_SECS_X * (1.0 + SWIM_SPREAD * k * 2.0);
    const pz = SWIM_SECS_Z * (1.0 - SWIM_SPREAD * k * 1.7);
    const off = @as(f32, @floatFromInt(i)) * 2.399;
    return v3(
        mathx.sinf(std.math.tau * t / px + off) * SWIM_X * (0.7 + 0.6 * @abs(k * 2.0)),
        mathx.sinf(std.math.tau * t / (px * 1.63) + off * 1.7) * 0.55,
        mathx.cosf(std.math.tau * t / pz + off * 0.7) * SWIM_Z * (0.7 + 0.6 * @abs(k * 2.0)),
    );
}

/// **PEACH, AND EMISSIVE.** Alpha is the emissive channel, so 236 is a mote that keeps its colour in shadow.
const MOTE_WARM = rgba(255, 208, 178, 236);
const MOTE_PALE = rgba(255, 232, 214, 214);

pub const SPORE_SHOALS: usize = 5;
pub const SHOAL_SECS: f32 = 41.0;

/// One shoal's share of the light, 0..1, on its own offset cycle. Held off zero rather than run to it: a shoal that vanishes outright pops on the frame it comes back.
pub fn shoalFade(t: f32, i: usize) f32 {
    const off = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(SPORE_SHOALS));
    const u = @mod(t / SHOAL_SECS + off, 1.0);
    return 0.10 + 0.90 * (0.5 - 0.5 * mathx.cosf(std.math.tau * u));
}

pub const SPORE_OPACITY: f32 = 0.62;
const SPORE_TAPER: f32 = 0.70;
const SPORE_BANK_PEACH = v3(1.0, 196.0 / 255.0, 170.0 / 255.0);

pub fn bankTint(hour: rl.Vector3, spore: f32) rl.Color {
    const t = mathx.clampF(spore, 0, 1);
    const peach = mathx.lerpV(v3(1, 1, 1), SPORE_BANK_PEACH, t);
    return rgba(
        mathx.u8f(hour.x * peach.x * 255.0),
        mathx.u8f(hour.y * peach.y * 255.0),
        mathx.u8f(hour.z * peach.z * 255.0),
        255,
    );
}

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

    pub fn draw(self: *const Spore, scene: *gfx.Scene, eye: rl.Vector3, at: rl.Vector3, level: f32, t: f32) void {
        if (level <= 0.02) return;
        const lv = mathx.clampF(level, 0, 1);
        var any = false;
        for (&self.shoals, 0..) |*m, si| {
            const amt = SPORE_OPACITY * lv * shoalFade(t, si);
            if (amt <= 0.004) continue;
            if (!any) {
                scene.beginFade(amt);
                any = true;
            } else scene.setFade(amt);
            const sw = swimOf(t, si);
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
    try std.testing.expect(SWIM_SECS_X > cross * 0.5);
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
    try std.testing.expect(rainWrap < 0.5);
    try std.testing.expect(fall > rainWrap * 100.0);
    try std.testing.expect(SHOAL_SECS > rainWrap * 100.0);
    var w = Weather.init(1);
    var i: usize = 0;
    while (i < 60 * 200) : (i += 1) w.tick(1.0 / 60.0);
    std.debug.print("  ...after 200 s of ticks: rain t = {d:.3}, slow = {d:.1}\n", .{ w.t, w.slowSecs() });
    try std.testing.expect(w.slowSecs() > 199.0);
    try std.testing.expect(w.t < rainWrap);
    try std.testing.expect(@abs(shoalFade(0, 0) - shoalFade(SHOAL_SECS * 0.5, 0)) > 0.5);
    try std.testing.expect(@abs(shoalFade(0, 0) - shoalFade(rainWrap, 0)) < 0.01);
    for (1..SPORE_SHOALS) |k| {
        const a = swimOf(17.0, 0);
        const b = swimOf(17.0, k);
        try std.testing.expect(mathx.lenV(mathx.subV(a, b)) > 0.15);
    }
}


pub const SKEIN_GAP_LO: f32 = 18.0;
pub const SKEIN_GAP_HI: f32 = 62.0;
pub const SKEIN_DRY: f32 = 0.02;
pub const SKEIN_AFTER_RAIN: f32 = 22.0;

pub const BIRDS_LO: usize = 3;
pub const BIRDS_HI: usize = 17;


/// THE CEILING IS A SHARE OF THE RESTING FRAME'S OWN TOP (`camera.skyTop`, 11.46 deg): at 0.70 that is 8.0 deg, which leaves the birds a clear third of sky above them.
const SKY_SHARE: f32 = 0.70;

pub const HIGH_LO: f32 = 17.0;
pub const HIGH_HI: f32 = 24.0;

fn skyCeiling() f32 {
    return camera.skyTop() * SKY_SHARE;
}

comptime {
    std.debug.assert(camera.skyTop() > 0.02);
    std.debug.assert(SKY_SHARE > 0 and SKY_SHARE < 1);
    std.debug.assert(HIGH_LO > 15.5 and HIGH_HI > HIGH_LO);
}

pub fn skeinNear() f32 {
    return HIGH_HI / @tan(skyCeiling());
}
pub fn skeinWide() f32 {
    return skeinNear() * 1.18;
}
pub fn skeinRim() f32 {
    return skeinWide() * 1.20;
}

/// exp(−0.013 d) leaves 15% of a thing at 130 m and 4% at 240 m, and the haze does not soften a bird — it pulls it to the sky's own colour. At 0.35 the same two ranges keep 55% and 33%.
pub const SKEIN_HAZE: f32 = 0.35;

const SKEIN_MPS_LO: f32 = 14.0;
const SKEIN_MPS_HI: f32 = 26.0;

const WING: f32 = 1.0;
const SPAN_LO: f32 = 2.6;
const SPAN_HI: f32 = 5.0;
const SPAN_JITTER: f32 = 0.22;
const FLAP_LO: f32 = 0.35;
const FLAP_HI: f32 = 1.35;
const FLAP_SECS_LO: f32 = 0.42;
const FLAP_SECS_HI: f32 = 0.72;
const TRAIL_LO: f32 = 3.0;
const TRAIL_HI: f32 = 7.0;
const SPREAD: f32 = 4.5;
/// At 70 m the worst per-frame step is `mps*dt*1.5/70` — under a hundredth of the alpha at the fastest a flock flies.
const SKEIN_FADE_M: f32 = 70.0;
pub const SKEIN_TOP: f32 = 1.0;

const BIRD_COL = rgba(16, 15, 18, 255);

const Bird = struct {
    back: f32 = 0,
    side: f32 = 0,
    lift: f32 = 0,
    span: f32 = 1,
    flapT: f32 = 0,
    flapSecs: f32 = 0.5,
};

pub const Skein = struct {
    model: rl.Model,
    birds: [BIRDS_HI]Bird = [_]Bird{.{}} ** BIRDS_HI,
    n: usize = 0,
    wait: f32 = 0,
    flown: f32 = 0,
    cross: f32 = 0,
    dryFor: f32 = 0,
    at: rl.Vector3 = mathx.zero3,
    dir: rl.Vector3 = mathx.zero3,
    high: f32 = 0,
    mps: f32 = 0,
    rng: mathx.Rng = mathx.Rng.init(0xB18D_5EED),
    armed: bool = false,

    pub fn build(shader: rl.Shader) Skein {
        return .{ .model = birdMesh(shader) };
    }

    fn birdMesh(shader: rl.Shader) rl.Model {
        var b = gfx.Builder.init();
        b.setMat(.plain);
        b.setAnimY(0);
        const half = WING * 0.5;
        const rise = WING * 0.26;
        const chord = WING * 0.16;
        for ([_]f32{ 1, -1 }) |side| {
            b.addBox(
                v3(side * half * 0.5, rise * 0.5, 0),
                v3(side * half * 0.5, rise * 0.5, 0),
                v3(0, chord * 0.10, 0),
                v3(0, 0, chord * 0.5),
                BIRD_COL,
            );
        }
        b.addBlob(mathx.zero3, v3(chord * 0.34, chord * 0.30, chord * 0.9), 4, 6, BIRD_COL);
        return b.toModel(shader);
    }

    pub fn tick(self: *Skein, dt: f32, at: rl.Vector3, groundY: f32, rainLevel: f32) void {
        if (!self.armed) {
            self.armed = true;
            self.wait = self.rng.range(SKEIN_GAP_LO, SKEIN_GAP_HI);
        }
        if (rainLevel > SKEIN_DRY) {
            self.dryFor = 0;
            if (self.n == 0) return;
        } else self.dryFor += dt;

        if (self.n > 0) {
            self.flown += self.mps * dt;
            for (self.birds[0..self.n]) |*bd| bd.flapT += dt;
            if (self.flown >= self.cross) {
                self.n = 0;
                self.wait = self.rng.range(SKEIN_GAP_LO, SKEIN_GAP_HI);
            }
            return;
        }
        if (self.dryFor < SKEIN_AFTER_RAIN) return;
        self.wait -= dt;
        if (self.wait > 0) return;
        self.launch(at, groundY, null, null);
    }

    fn launch(self: *Skein, at: rl.Vector3, groundY: f32, count: ?usize, bearing: ?f32) void {
        const heading = bearing orelse self.rng.angle();
        const d = v3(mathx.cosf(heading), 0, mathx.sinf(heading));
        const side: f32 = if (self.rng.float() < 0.5) -1.0 else 1.0;
        const off = side * self.rng.range(skeinNear(), skeinWide());
        const rim = skeinRim();
        self.dir = d;
        self.high = groundY + self.rng.range(HIGH_LO, HIGH_HI);
        self.mps = self.rng.range(SKEIN_MPS_LO, SKEIN_MPS_HI);
        self.cross = 2.0 * @sqrt(mathx.maxF(rim * rim - off * off, 1.0));
        self.flown = 0;
        self.at = v3(at.x - d.x * self.cross * 0.5 - d.z * off, self.high, at.z - d.z * self.cross * 0.5 + d.x * off);
        const lo: f32 = @floatFromInt(BIRDS_LO);
        const hi: f32 = @floatFromInt(BIRDS_HI);
        self.n = count orelse @intFromFloat(@round(self.rng.range(lo, hi)));
        const kind = self.rng.range(SPAN_LO, SPAN_HI);
        for (self.birds[0..self.n], 0..) |*bd, i| {
            const rank: f32 = @floatFromInt(i);
            bd.* = .{
                .back = rank * self.rng.range(TRAIL_LO, TRAIL_HI) * 0.5,
                .side = self.rng.range(-SPREAD, SPREAD) * (0.35 + rank * 0.18),
                .lift = self.rng.range(-SPREAD, SPREAD) * 0.4,
                .span = kind * self.rng.range(1.0 - SPAN_JITTER, 1.0 + SPAN_JITTER),
                .flapT = self.rng.range(0, 4),
                .flapSecs = self.rng.range(FLAP_SECS_LO, FLAP_SECS_HI),
            };
        }
    }

    pub fn flying(self: *const Skein) bool {
        return self.n > 0;
    }

    pub fn alpha(self: *const Skein) f32 {
        if (self.n == 0 or self.cross <= 0) return 0;
        const u = mathx.clampF(self.flown / self.cross, 0, 1);
        const f = mathx.clampF(SKEIN_FADE_M / mathx.maxF(self.cross, 1.0), 0.02, 0.45);
        return SKEIN_TOP * mathx.smoothstep(0, f, u) * (1.0 - mathx.smoothstep(1.0 - f, 1.0, u));
    }

    pub fn leadAt(self: *const Skein) rl.Vector3 {
        return v3(self.at.x + self.dir.x * self.flown, self.high, self.at.z + self.dir.z * self.flown);
    }

    pub fn draw(self: *const Skein, scene: *gfx.Scene) void {
        const a = self.alpha();
        if (a <= 0.004) return;
        const head = self.leadAt();
        const yaw = mathx.degrees(mathx.headingXZ(self.dir));
        scene.beginFade(a);
        scene.setHaze(SKEIN_HAZE);
        for (self.birds[0..self.n]) |bd| {
            const p = v3(
                head.x - self.dir.x * bd.back - self.dir.z * bd.side,
                head.y + bd.lift,
                head.z - self.dir.z * bd.back + self.dir.x * bd.side,
            );
            const flap = mathx.lerpF(FLAP_LO, FLAP_HI, 0.5 + 0.5 * mathx.sinf(std.math.tau * bd.flapT / bd.flapSecs));
            rl.drawModelEx(self.model, p, v3(0, 1, 0), yaw, v3(bd.span, bd.span * flap, bd.span), rl.Color.white);
        }
        scene.setHaze(1.0);
        scene.endFade();
    }

    pub fn stageOne(self: *Skein, at: rl.Vector3, groundY: f32, heading: f32) void {
        self.dryFor = SKEIN_AFTER_RAIN;
        self.armed = true;
        self.launch(at, groundY, BIRDS_HI, heading);
        self.flown = self.cross * 0.42;
    }
};

test "EVERY BIRD IS IN THE PICTURE WITH THE CAMERA WHERE IT RESTS — which is why none of them ever were" {
    const top = camera.skyTop();
    var sk = Skein{ .model = undefined };
    sk.dryFor = SKEIN_AFTER_RAIN;
    const dt = 1.0 / 60.0;
    var worst: f32 = 0;
    var lowest: f32 = 1e9;
    var nearest: f32 = 1e9;
    var farthest: f32 = 0;
    var flights: usize = 0;
    var was = false;
    var t: f32 = 0;
    while (t < 1800.0) : (t += dt) {
        sk.tick(dt, mathx.zero3, 0, 0);
        if (sk.flying() and !was) flights += 1;
        was = sk.flying();
        if (!sk.flying() or sk.alpha() <= 0.004) continue;
        const head = sk.leadAt();
        for (sk.birds[0..sk.n]) |bd| {
            const p = v3(
                head.x - sk.dir.x * bd.back - sk.dir.z * bd.side,
                head.y + bd.lift,
                head.z - sk.dir.z * bd.back + sk.dir.x * bd.side,
            );
            const d = mathx.lenXZ(p);
            const e = std.math.atan2(p.y, mathx.maxF(d, 0.001));
            worst = mathx.maxF(worst, e);
            lowest = mathx.minF(lowest, e);
            nearest = mathx.minF(nearest, d);
            farthest = mathx.maxF(farthest, d);
        }
    }
    std.debug.print("\n  birds: {d} flights, elevation {d:.1}..{d:.1} deg against a {d:.1} deg frame; range {d:.0}..{d:.0} m\n", .{
        flights, mathx.degrees(lowest), mathx.degrees(worst), mathx.degrees(top), nearest, farthest,
    });
    try std.testing.expect(flights > 20);
    try std.testing.expect(worst < top);
    try std.testing.expect(lowest > 0);
    // …AND CLEAR OF THE CLIFFS THEY USED TO FLY THROUGH (`props.cliffParts` stands 15.5 m).
    try std.testing.expect(HIGH_LO > 15.5);
    try std.testing.expect(nearest > skeinNear() * 0.9);
}

test "THE BIRDS ARE AN EVENT, NOT A FLOCK THAT LIVES THERE — infrequent, dry-only, and never twice the same" {
    const dt = 1.0 / 60.0;
    var sk = Skein{ .model = undefined };
    var t: f32 = 0;
    var flights: usize = 0;
    var wasFlying = false;
    var upFor: f32 = 0;
    var visible: f32 = 0;
    var smallest: usize = 999;
    var biggest: usize = 0;
    var bearX: f32 = 0;
    var bearZ: f32 = 0;
    var lowest: f32 = 1e9;
    while (t < 3600.0) : (t += dt) {
        sk.tick(dt, mathx.zero3, 0, 0);
        if (sk.flying()) {
            visible += dt;
            upFor += dt;
            lowest = mathx.minF(lowest, sk.high);
            if (!wasFlying) {
                flights += 1;
                smallest = @min(smallest, sk.n);
                biggest = @max(biggest, sk.n);
                bearX += sk.dir.x;
                bearZ += sk.dir.z;
            }
        } else if (wasFlying) upFor = 0;
        wasFlying = sk.flying();
    }
    const share = visible / 3600.0;
    std.debug.print("\n  skein: {d} flights in an hour, {d} to {d} birds, in the sky {d:.0}% of it, lowest {d:.0} m up\n", .{ flights, smallest, biggest, share * 100.0, lowest });
    const meanOff = (skeinNear() + skeinWide()) * 0.5;
    const meanChord = 2.0 * @sqrt(skeinRim() * skeinRim() - meanOff * meanOff);
    const meanCycle = (SKEIN_GAP_LO + SKEIN_GAP_HI) * 0.5 + meanChord / ((SKEIN_MPS_LO + SKEIN_MPS_HI) * 0.5);
    const want = 3600.0 / meanCycle;
    std.debug.print("  ...{d:.0} predicted from the gap and the crossing, {d} flown\n", .{ want, flights });
    try std.testing.expect(@as(f32, @floatFromInt(flights)) > want * 0.66 and @as(f32, @floatFromInt(flights)) < want * 1.34);
    try std.testing.expect(smallest <= BIRDS_LO + 3 and biggest >= BIRDS_HI - 3);
    try std.testing.expect(smallest >= BIRDS_LO and biggest <= BIRDS_HI);
    const lane = @sqrt(bearX * bearX + bearZ * bearZ) / @as(f32, @floatFromInt(flights));
    std.debug.print("  ...and their bearings pull {d:.2} one way (1.00 would be a flight path)\n", .{lane});
    try std.testing.expect(lane < 0.75);
    try std.testing.expect(lowest >= HIGH_LO);
    try std.testing.expect(share < 0.50);
}

test "NOTHING FLIES IN THE RAIN, AND NOTHING IS WAITING TO THE SECOND IT STOPS" {
    const dt = 1.0 / 60.0;
    var wet = Skein{ .model = undefined };
    var t: f32 = 0;
    while (t < 3600.0) : (t += dt) {
        wet.tick(dt, mathx.zero3, 0, 0.6);
        try std.testing.expect(!wet.flying());
    }
    var dry = Skein{ .model = undefined };
    var e: f32 = 0;
    var firstDry: f32 = -1;
    while (e < 1200.0) : (e += dt) {
        dry.tick(dt, mathx.zero3, 0, 0);
        if (dry.flying() and firstDry < 0) firstDry = e;
    }
    std.debug.print("  first flight on a clear sky at {d:.0} s (gap {d:.0}..{d:.0}, and {d:.0} s of settling after rain)\n", .{ firstDry, SKEIN_GAP_LO, SKEIN_GAP_HI, SKEIN_AFTER_RAIN });
    try std.testing.expect(firstDry >= SKEIN_GAP_LO);

    var caught = Skein{ .model = undefined };
    caught.stageOne(mathx.zero3, 0, 0.4);
    try std.testing.expect(caught.flying());
    var f: f32 = 0;
    var stillUp = false;
    while (f < 3.0) : (f += dt) {
        caught.tick(dt, mathx.zero3, 0, 0.9);
        if (caught.flying()) stillUp = true;
    }
    try std.testing.expect(stillUp);
}

test "A CROSSING IS A CROSSING — it enters far, leaves far, and fades at both rims" {
    const dt = 1.0 / 60.0;
    var sk = Skein{ .model = undefined };
    sk.stageOne(mathx.zero3, 0, 0);
    sk.flown = 0;
    const entered = sk.leadAt();
    var t: f32 = 0;
    var peak: f32 = 0;
    var nearest: f32 = 1e9;
    var wasA: f32 = sk.alpha();
    var worstStep: f32 = 0;
    while (t < 120.0 and sk.flying()) : (t += dt) {
        sk.tick(dt, mathx.zero3, 0, 0);
        if (!sk.flying()) break;
        const a = sk.alpha();
        peak = mathx.maxF(peak, a);
        worstStep = mathx.maxF(worstStep, @abs(a - wasA));
        wasA = a;
        nearest = mathx.minF(nearest, mathx.distXZ(sk.leadAt(), mathx.zero3));
    }
    std.debug.print("  a crossing: in at {d:.0} m, nearest {d:.0} m, took {d:.0} s; alpha peaks {d:.2}, worst step {d:.4}\n", .{ mathx.distXZ(entered, mathx.zero3), nearest, t, peak, worstStep });
    try std.testing.expect(mathx.distXZ(entered, mathx.zero3) > skeinRim() * 0.9);
    try std.testing.expect(peak > SKEIN_TOP * 0.9 and peak <= SKEIN_TOP + 1e-5);
    try std.testing.expect(worstStep < 0.01);
    const chord = 2.0 * @sqrt(skeinRim() * skeinRim() - skeinNear() * skeinNear());
    try std.testing.expect(t > chord / SKEIN_MPS_HI - 1.0);
    try std.testing.expect(t < 2.0 * skeinRim() / SKEIN_MPS_LO + 1.0);
}

test "THE FLOCK IS RAGGED AND EACH BIRD FLAPS ON ITS OWN — a pack, not one animal copied" {
    var sk = Skein{ .model = undefined };
    sk.stageOne(mathx.zero3, 0, 0);
    var backs: f32 = 0;
    var sides: f32 = 0;
    var beatLo: f32 = 1e9;
    var beatHi: f32 = 0;
    var spanLo: f32 = 1e9;
    var spanHi: f32 = 0;
    for (sk.birds[0..sk.n]) |bd| {
        backs = mathx.maxF(backs, bd.back);
        sides = mathx.maxF(sides, @abs(bd.side));
        beatLo = mathx.minF(beatLo, bd.flapSecs);
        beatHi = mathx.maxF(beatHi, bd.flapSecs);
        spanLo = mathx.minF(spanLo, bd.span);
        spanHi = mathx.maxF(spanHi, bd.span);
        try std.testing.expect(bd.flapSecs >= FLAP_SECS_LO and bd.flapSecs <= FLAP_SECS_HI);
    }
    std.debug.print("  a skein of {d}: trails {d:.1} m back, {d:.1} m wide; wingbeats {d:.2}..{d:.2} s, spans {d:.1}..{d:.1} m\n", .{ sk.n, backs, sides, beatLo, beatHi, spanLo, spanHi });
    try std.testing.expect(backs > TRAIL_LO);
    try std.testing.expect(sides > 1.0);
    try std.testing.expect(beatHi - beatLo > (FLAP_SECS_HI - FLAP_SECS_LO) * 0.5);
    try std.testing.expect(spanHi - spanLo > spanLo * SPAN_JITTER * 0.8);
    try std.testing.expect(spanLo >= SPAN_LO * (1.0 - SPAN_JITTER) - 1e-3);
    try std.testing.expect(spanHi <= SPAN_HI * (1.0 + SPAN_JITTER) + 1e-3);
    try std.testing.expect(BIRDS_HI <= 20);
}
