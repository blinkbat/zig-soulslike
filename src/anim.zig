// KEYED POSE TRACKS — the general form of `hero.sampleCurve`, and the thing every ATTACK in this
// game was missing.

const std = @import("std");
const mathx = @import("mathx.zig");

/// How a segment approaches ITS OWN key — the ease belongs to the key it arrives at, which is the way
/// an animator reads a track ("slow into the top, snap out of it").
pub const Ease = enum {
    /// Constant rate. Correct for something genuinely mechanical, wrong for a body.
    linear,
    /// Ease in and out. The default, and what a limb changing direction actually does.
    smooth,
    /// Slow to leave, fast to arrive — a gather loading.
    accel,
    /// Fast to leave, slow to arrive — a mass running out of momentum.
    decel,
    /// Almost all of the travel in the first fifth. The STRIKE: a FromSoft attack's active window is
    /// two to four frames, and a strike that eases into its target is a strike with no snap.
    snap,
    /// Hold the previous value outright until this key's time, then jump. For a HANG — the delayed
    /// downswing that baits a roll — where the pose must not creep while it waits.
    hold,
};

/// ONE KEY on one channel: `t` is the fraction of the MOVE (0..1, ascending), `v` the channel's own
/// unit (degrees, or a 0..1 fraction), `ease` how the track gets here from the key before it.
pub const Key = struct { t: f32, v: f32, ease: Ease = .smooth };

pub fn easeAt(e: Ease, f: f32) f32 {
    return switch (e) {
        .linear => f,
        .smooth => f * f * (3.0 - 2.0 * f),
        .accel => f * f,
        .decel => 1.0 - (1.0 - f) * (1.0 - f),
        .snap => 1.0 - std.math.pow(f32, 1.0 - f, 5.0),
        .hold => if (f >= 1.0) 1.0 else 0.0,
    };
}

/// SAMPLE A KEYED CHANNEL at `u` (0..1 through the move). Outside the key range it CLAMPS, so a track
/// that stops early simply holds its last pose — which is the held End Pose the whole punish-window
/// contract is built on, gained by writing no key rather than by remembering to.
pub fn keyAt(keys: []const Key, u: f32) f32 {
    if (keys.len == 0) return 0;
    if (u <= keys[0].t) return keys[0].v;
    const last = keys[keys.len - 1];
    if (u >= last.t) return last.v;
    var i: usize = 1;
    while (i < keys.len) : (i += 1) {
        if (u > keys[i].t) continue;
        const a = keys[i - 1];
        const b = keys[i];
        const span = b.t - a.t;
        const f = if (span > 1e-6) (u - a.t) / span else 1.0;
        return a.v + (b.v - a.v) * easeAt(b.ease, mathx.clampF(f, 0, 1));
    }
    return last.v;
}

/// A CREATURE'S MOVES AS WHOLE-POSE TRACKS. `P` is the creature's own pose struct: every field
/// defaulted to its carry, and a `chan()` that flattens it ROOT-most to TIP-most (the order is the
/// spring bank's lag, so it is load-bearing). A key says only what MOVES off the carry — which is how
/// a pose reads as a pose rather than as a dozen numbers. Sampling clamps at both ends like `keyAt`,
/// so a track that stops early holds its last pose: the held End Pose, gained by writing no key.
pub fn Pose(comptime P: type) type {
    return struct {
        pub const Chan = @TypeOf((P{}).chan());
        pub const PoseKey = struct { t: f32, p: P, ease: Ease = .smooth };

        pub fn sample(keys: []const PoseKey, u: f32) Chan {
            if (keys.len == 0) return (P{}).chan();
            if (u <= keys[0].t) return keys[0].p.chan();
            const last = keys[keys.len - 1];
            if (u >= last.t) return last.p.chan();
            var i: usize = 1;
            while (i < keys.len) : (i += 1) {
                if (u > keys[i].t) continue;
                const a = keys[i - 1];
                const b = keys[i];
                const span = b.t - a.t;
                const f = if (span > 1e-6) mathx.clampF((u - a.t) / span, 0, 1) else 1.0;
                const ca = a.p.chan();
                const cb = b.p.chan();
                var out: Chan = undefined;
                for (&out, ca, cb) |*o, va, vb| o.* = va + (vb - va) * easeAt(b.ease, f);
                return out;
            }
            return last.p.chan();
        }
    };
}

/// **THE POSE IS A TARGET, NOT THE OUTPUT** — the one idea that separates a body from a puppet, and
/// the reason a two-pose lerp can never be fixed by tuning it. A spring chases the keyed value with
/// its own velocity, so it arrives LATE, carries PAST, and settles back: the overshoot law this
/// codebase already states for props, applied to the thing that needed it most.
pub const Spring = struct {
    v: f32 = 0,
    vel: f32 = 0,

    /// `stiff` is how hard it is pulled (1/s^2-ish); `zeta` is the DAMPING RATIO — 1.0 is critical
    /// (arrives fast, never overshoots), below 1 overshoots and rings, above 1 is sluggish. Weight
    /// lives just under 1.
    pub fn step(self: *Spring, target: f32, stiff: f32, zeta: f32, dt: f32) f32 {
        const damp = 2.0 * zeta * @sqrt(mathx.maxF(stiff, 0));
        // **SUBSTEPPED, because these are stiff enough to need it.** A spring fast enough to track a
        // two-hundred-millisecond strike has a natural period near a tenth of a second, and integrating
        // that in one frame-sized step is how a spring layer either lags visibly or detonates. The total
        // `dt` is still clamped — a hitch must not be simulated in full — and then walked in pieces small
        // enough that the result is the same at 30 fps as at 144.
        const total = mathx.minF(dt, 1.0 / 30.0);
        const steps: u32 = @intFromFloat(@max(1.0, @ceil(total * 240.0)));
        const h = total / @as(f32, @floatFromInt(steps));
        var i: u32 = 0;
        while (i < steps) : (i += 1) {
            self.vel += (stiff * (target - self.v) - damp * self.vel) * h;
            self.v += self.vel * h;
        }
        return self.v;
    }
    /// Put it AT a value with no motion — a spawn, a teleport, a body that has just been re-seated.
    pub fn set(self: *Spring, value: f32) void {
        self.v = value;
        self.vel = 0;
    }
};

/// A BANK OF SPRINGS over a creature's posture channels, with the CHAIN LAG built in.
pub fn SpringBank(comptime CH: usize) type {
    return struct {
        const Self = @This();
        s: [CH]Spring = [_]Spring{.{}} ** CH,

        /// Chase `target`, writing the settled values back over it. The channel array is ordered
        /// ROOT-most to TIP-most; a channel's INDEX in it is what decides its lag.
        pub fn chase(self: *Self, target: *[CH]f32, stiff: f32, zeta: f32, falloff: f32, dt: f32) void {
            for (&self.s, 0..) |*sp, i| {
                const k = stiff * std.math.pow(f32, falloff, @floatFromInt(i));
                target[i] = sp.step(target[i], k, zeta, dt);
            }
        }
        pub fn seat(self: *Self, at: [CH]f32) void {
            for (&self.s, at) |*sp, v| sp.set(v);
        }
    };
}

test "A KEYED TRACK HOLDS AT BOTH ENDS, and a track that stops early holds its last pose" {
    const k = [_]Key{
        .{ .t = 0.0, .v = 10 },
        .{ .t = 0.4, .v = 90, .ease = .accel },
        .{ .t = 0.6, .v = 90, .ease = .hold },
        .{ .t = 0.7, .v = -40, .ease = .snap },
    };
    try std.testing.expectApproxEqAbs(@as(f32, 10), keyAt(&k, -1.0), 1e-5); // clamped before the first
    try std.testing.expectApproxEqAbs(@as(f32, 10), keyAt(&k, 0.0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 90), keyAt(&k, 0.4), 1e-5);
    // THE HANG DOES NOT CREEP. `.hold` is what a delayed downswing needs: the pose must sit dead still
    // while it waits, or the bait is a slow drift and the player reads it as the swing already coming.
    try std.testing.expectApproxEqAbs(@as(f32, 90), keyAt(&k, 0.55), 1e-5);
    // …and past the last key it HOLDS — the End Pose, gained by writing no key rather than remembering.
    try std.testing.expectApproxEqAbs(@as(f32, -40), keyAt(&k, 0.7), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -40), keyAt(&k, 1.0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -40), keyAt(&k, 9.0), 1e-5);
    // THE SNAP IS FRONT-LOADED: a strike's travel is nearly over by the fifth of the way in, which is
    // what makes it an attack rather than a reach.
    const quarter = keyAt(&k, 0.6 + (0.7 - 0.6) * 0.25);
    try std.testing.expect(quarter < 90 - (90 - -40) * 0.6);
    // Monotone in u across a rising segment — no key ordering bug can put a limb somewhere it never was.
    var prev = keyAt(&k, 0.0);
    var u: f32 = 0;
    while (u <= 0.4) : (u += 0.01) {
        const now = keyAt(&k, u);
        try std.testing.expect(now >= prev - 1e-4);
        prev = now;
    }
}

test "A SPRING ARRIVES, OVERSHOOTS AND SETTLES — the weight law, as a type rather than a reminder" {
    // Underdamped: it must go PAST the target and come back. A mass in motion overshoots its rest.
    var s = Spring{};
    s.set(0);
    var peak: f32 = 0;
    var t: f32 = 0;
    const dt = 1.0 / 60.0;
    while (t < 2.0) : (t += dt) peak = @max(peak, s.step(100, 220, 0.55, dt));
    try std.testing.expect(peak > 104); // it carried past
    try std.testing.expect(peak < 160); // …but it is a body, not a trampoline
    try std.testing.expectApproxEqAbs(@as(f32, 100), s.v, 2.0); // and it settled onto its rest

    // Critically damped: arrives fast and NEVER overshoots — for anything that must not wobble.
    var c = Spring{};
    c.set(0);
    var cpeak: f32 = 0;
    t = 0;
    while (t < 2.0) : (t += dt) cpeak = @max(cpeak, c.step(100, 220, 1.0, dt));
    try std.testing.expect(cpeak <= 100.5);

    // A HITCH MUST NOT DETONATE IT. `dt` is clamped inside `step`, so a half-second frame is survivable.
    var h = Spring{};
    h.set(0);
    _ = h.step(100, 900, 0.5, 0.5);
    try std.testing.expect(std.math.isFinite(h.v) and @abs(h.v) < 1000);
}

test "THE CHAIN LAGS OUTWARD — the tip arrives after the root, without anyone authoring the stagger" {
    // This is what `knight.setStrike` and `ogre.setSwipe` hand-approximate with sqrt/linear/squared
    // curves off one clock, re-derived per creature. As a property of the bank it is free and uniform.
    var bank = SpringBank(3){};
    bank.seat(.{ 0, 0, 0 });
    const dt = 1.0 / 240.0; // a stiff spring needs a step short enough to integrate it honestly
    var reached = [_]f32{ -1, -1, -1 };
    var t: f32 = 0;
    while (t < 1.5) : (t += dt) {
        var target = [_]f32{ 100, 100, 100 };
        bank.chase(&target, 260, 0.62, 0.55, dt);
        for (target, 0..) |v, i| {
            if (reached[i] < 0 and v >= 60) reached[i] = t;
        }
    }
    for (reached) |r| try std.testing.expect(r > 0); // they all get there…
    try std.testing.expect(reached[0] < reached[1]); // …root first
    try std.testing.expect(reached[1] < reached[2]); // …tip last
}
