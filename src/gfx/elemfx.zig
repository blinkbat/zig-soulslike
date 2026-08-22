const std = @import("std");
const rl = @import("raylib");

const combat = @import("../play/combat.zig");
const foe = @import("../foes/foe.zig");
const mathx = @import("../core/mathx.zig");

const rgba = mathx.rgba;
const v3 = mathx.v3;

pub const Sig = struct {
    core: rl.Color,
    edge: rl.Color,
    grav: f32,
    speedLo: f32,
    speedHi: f32,
    lifeLo: f32,
    lifeHi: f32,
    r0: f32,
    r1: f32,
    inward: bool = false,
    ash: ?rl.Color = null,
    /// What the mote COOLS TO across its life — fire dies to ember red, cold whitens to frost, chaos sinks to a deeper violet. Null (lightning) is a spark that vanishes at full heat: white has nothing to cool to.
    cool: ?rl.Color = null,
    /// Air resistance — only fire has any: a flame leaps and then HANGS, which is most of what says "flame".
    drag: f32 = 0,
    /// Velocity trail (seconds) — lightning owns this: at its speeds the motes draw as jagged white streaks.
    stretch: f32 = 0,
};

// Fire's speeds are SOLVED WITH ITS DRAG, not raised: v0/k·(1−e^(−k·life)) at 5.5 and 2.6 is 1.57 m, the 1.56 m the old 3.0 covered in a straight line — the blast front-loads and then hangs, same reach.
const FIRE = Sig{
    .core = rgba(255, 198, 104, 228),
    .edge = rgba(228, 116, 28, 200),
    .grav = -2.1,
    .speedLo = 2.2,
    .speedHi = 5.5,
    .lifeLo = 0.26,
    .lifeHi = 0.52,
    .r0 = 0.030,
    .r1 = 0.058,
    .ash = rgba(74, 68, 62, 120),
    .cool = rgba(198, 58, 20, 180),
    .drag = 2.6,
};

const COLD = Sig{
    .core = rgba(212, 238, 250, 225),
    .edge = rgba(150, 200, 226, 235),
    .grav = 1.5,
    .speedLo = 0.5,
    .speedHi = 1.7,
    .lifeLo = 0.60,
    .lifeHi = 1.15,
    .r0 = 0.028,
    .r1 = 0.010,
    .cool = rgba(234, 246, 252, 150),
    .stretch = 0.020,
};

/// LIGHTNING — **THE ONLY COLOURLESS ONE IN THE TABLE.** As the thundercrock's pale blue the hue test refused it: against COLD, which owns the blues, the two were one substance at two brightnesses. A spark is white-hot, so it is the achromatic one. (The crock's STREAK stays as it is — a thing in the SKY at range.)
const LIGHTNING = Sig{
    .core = rgba(255, 255, 224, 255),
    .edge = rgba(226, 230, 232, 245),
    .grav = 0,
    .speedLo = 7.0,
    .speedHi = 14.0,
    .lifeLo = 0.040,
    .lifeHi = 0.085,
    .r0 = 0.021,
    .r1 = 0.003,
    .stretch = 0.030,
};

const CHAOS = Sig{
    .core = rgba(224, 176, 250, 210),
    .edge = rgba(168, 84, 216, 190),
    .grav = 0,
    .speedLo = 0.8,
    .speedHi = 2.3,
    .lifeLo = 0.20,
    .lifeHi = 0.44,
    .r0 = 0.023,
    .r1 = 0.011,
    .inward = true,
    .cool = rgba(104, 36, 152, 170),
    .stretch = 0.022,
};

pub fn sig(e: combat.Elem) Sig {
    return switch (e) {
        .fire => FIRE,
        .cold => COLD,
        .lightning => LIGHTNING,
        .chaos => CHAOS,
    };
}


/// A gather is an INHALE, not a blast — it converges at the old pace (this factor un-does fire's drag-solved speed raise) and carries no drag, which would stall the convergence it exists to show.
const GATHER_PACE: f32 = 0.55;

pub fn gather(pool: []foe.Particle, head: *usize, rng: *mathx.Rng, at: rl.Vector3, e: combat.Elem, n: usize, r: f32, scale: f32) void {
    const s = sig(e);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const dir = randomUnit(rng);
        const from = mathx.addV(at, mathx.scaleV(dir, r * scale));
        const sp = rng.range(s.speedLo, s.speedHi) * scale * GATHER_PACE;
        const v = mathx.scaleV(dir, -sp);
        foe.emitPart(pool, head, .{
            .p = from,
            .v = v,
            .life = rng.range(s.lifeLo, s.lifeHi) * 0.7,
            .r0 = s.r0 * scale,
            .r1 = s.r1 * scale,
            .col = s.core,
            .col1 = s.cool,
            .grav = s.grav * 0.4,
            .stretch = s.stretch,
            .add = true,
        });
    }
}

/// One in this many of a burst's motes is a CORE rather than an edge, and — for the one element that leaves a residue — the mote at this offset in that cadence is followed by an ash mote.
const BURST_EVERY: usize = 3;
const BURST_ASH_AT: usize = 1;

/// How many motes ONE `burst` of `n` actually emits — `pourCount`'s counterpart, and it is not `n`: fire lays an ASH mote beside every third, so a caller sizing its ring off `n` alone is a third short of the frame.
pub fn burstCount(e: combat.Elem, n: usize) usize {
    if (sig(e).ash == null) return n;
    return n + (n + BURST_EVERY - 1 - BURST_ASH_AT) / BURST_EVERY;
}

test "A BURST OF n IS NOT n MOTES — fire's ash rides along, and the count says so" {
    var pool = [_]foe.Particle{.{}} ** 256;
    var rng = mathx.Rng.init(0xA5F1);
    for ([_]combat.Elem{ .fire, .cold, .lightning, .chaos }) |e| {
        for ([_]usize{ 0, 1, 2, 3, 4, 5, 14, 22 }) |n| {
            for (&pool) |*q| q.life = 0;
            var head: usize = 0;
            burst(&pool, &head, &rng, mathx.zero3, v3(0, 0, 1), e, n, 1.0);
            var live: usize = 0;
            for (&pool) |*q| {
                if (q.life > 0) live += 1;
            }
            try std.testing.expectEqual(burstCount(e, n), live);
        }
    }
}

pub fn burst(pool: []foe.Particle, head: *usize, rng: *mathx.Rng, at: rl.Vector3, dir: rl.Vector3, e: combat.Elem, n: usize, scale: f32) void {
    const s = sig(e);
    const aimed = mathx.lenV(dir) > 1e-3;
    const axis = if (aimed) mathx.normV(dir) else mathx.zero3;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var out = randomUnit(rng);
        // A cone about the axis, biased outward — never a hemisphere, which reads as a puff rather than a blow.
        if (aimed) out = mathx.normV(mathx.addV(axis, mathx.scaleV(out, 0.62)));
        const sp = rng.range(s.speedLo, s.speedHi) * scale;
        const v = mathx.scaleV(out, if (s.inward) -sp * 0.55 else sp);
        const life = rng.range(s.lifeLo, s.lifeHi);
        const from = mathx.addV(at, mathx.scaleV(out, s.r0 * scale * 2.0));
        foe.emitPart(pool, head, .{
            .p = from,
            .v = v,
            .life = life,
            .r0 = s.r0 * scale,
            .r1 = s.r1 * scale,
            .col = if (i % BURST_EVERY == 0) s.core else s.edge,
            .col1 = s.cool,
            .grav = s.grav,
            .drag = s.drag,
            .stretch = s.stretch,
            .add = true,
        });
        if (s.ash) |ash| {
            if (i % BURST_EVERY == 1) {
                foe.emitPart(pool, head, .{
                    .p = from,
                    .v = mathx.scaleV(v, 0.35),
                    .life = life * 2.4,
                    .r0 = s.r1 * scale,
                    .r1 = s.r1 * scale * 2.6,
                    .col = ash,
                    .grav = s.grav * 0.30,
                    .drag = 2.0,
                });
            }
        }
    }
}

/// MOTES A SECOND. Part of the LANGUAGE, not of whoever is pouring, so the bench and the fight run the same rate. MEASURED OFF A RENDER: at 70 the breath came back as eight dots over six metres. What has to be continuous is the FAR end, where the motes are spread over the widest part of the cone.
pub const POUR_RATE: f32 = 560.0;

pub const POUR_CAP: usize = foe.emitCap(POUR_RATE);

const POUR_GRAIN: f32 = 0.62;

const POUR_SIZE_LO: f32 = 0.45;
const POUR_SIZE_HI: f32 = 1.55;

/// **EVERY POUR HAS A KNOT AT ITS NOZZLE** — one root mote per this many stream motes, inside this much of `r0` of the source. Without it a cone is a drift of dots that happens to start near the emitter. Here and not at the call site because a caller picks the VERB and the ELEMENT, never a colour, life or gravity.
const POUR_ROOT_EVERY: usize = 4;
const POUR_ROOT_R: f32 = 1.6;
const POUR_ROOT_LIFE_LO: f32 = 0.05;
const POUR_ROOT_LIFE_HI: f32 = 0.13;

/// How many motes ONE `pour` of `n` actually emits, root included — the pool arithmetic every caller sizes its
/// ring off (`hero.FX_N`). **It is the count for ONE CALL**: a caller making `k` calls owes `k * pourCount(n)`, and `pourCount(k * n)` is not the same number — the knot restarts every call.
pub fn pourCount(n: usize) usize {
    return n + (n + POUR_ROOT_EVERY - 1) / POUR_ROOT_EVERY;
}

pub fn pour(pool: []foe.Particle, head: *usize, rng: *mathx.Rng, from: rl.Vector3, dir: rl.Vector3, e: combat.Elem, n: usize, spread: f32, reach: f32, callerScale: f32) void {
    const s = sig(e);
    if (mathx.lenV(dir) < 1e-3) return;
    const scale = callerScale * POUR_GRAIN;
    const axis = mathx.normV(dir);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const off = mathx.scaleV(randomUnit(rng), @tan(spread) * @sqrt(rng.float()));
        const out = mathx.normV(mathx.addV(axis, off));
        const life = rng.range(s.lifeLo, s.lifeHi);
        const sp = (reach / mathx.maxF(life, 0.05)) * rng.range(0.55, 1.0);
        const grain = rng.range(POUR_SIZE_LO, POUR_SIZE_HI);
        // NO DRAG on a pour — its speed is solved as reach/life, and drag would take back the reach it claims.
        foe.emitPart(pool, head, .{
            .p = from,
            .v = mathx.scaleV(out, sp),
            .life = life,
            .r0 = s.r0 * scale * grain,
            .r1 = s.r1 * scale * 1.5 * grain,
            .col = if (i % 2 == 0) s.core else s.edge,
            .col1 = s.cool,
            .grav = s.grav * 0.5,
            .stretch = s.stretch,
            .add = true,
        });
        if (i % POUR_ROOT_EVERY == 0) {
            const rr = s.r0 * scale * POUR_ROOT_R;
            const a = rng.angle();
            const wide = rng.range(0, rr);
            foe.emitPart(pool, head, .{
                .p = v3(from.x + mathx.cosf(a) * wide, from.y + rng.signed() * rr, from.z + mathx.sinf(a) * wide),
                .v = mathx.scaleV(axis, rng.range(0.2, 0.9)),
                .life = rng.range(POUR_ROOT_LIFE_LO, POUR_ROOT_LIFE_HI),
                .r0 = rr * rng.range(0.5, 1.25),
                .r1 = rr * 0.25,
                .col = s.core,
                .add = true,
            });
        }
    }
}

const randomUnit = foe.randomUnit;


test "the four are told apart with the COLOUR TAKEN AWAY" {
    const f = sig(.fire);
    const c = sig(.cold);
    const l = sig(.lightning);
    const x = sig(.chaos);

    try std.testing.expect(f.grav < 0);
    try std.testing.expect(c.grav > 0 and l.grav >= 0 and x.grav >= 0);
    try std.testing.expect(f.ash != null);
    for ([_]Sig{ c, l, x }) |s| try std.testing.expect(s.ash == null);
    try std.testing.expect(f.r1 > f.r0);
    for ([_]Sig{ c, l, x }) |s| try std.testing.expect(s.r1 < s.r0);

    try std.testing.expect(c.lifeHi > 2.0 * f.lifeHi);
    try std.testing.expect(c.lifeHi > 2.0 * x.lifeHi);
    try std.testing.expect(l.lifeHi * 3.0 < f.lifeHi);
    try std.testing.expect(l.lifeHi * 3.0 < c.lifeHi);
    try std.testing.expect(l.speedHi > 2.0 * f.speedHi);
    try std.testing.expect(x.inward);
    for ([_]Sig{ f, c, l }) |s| try std.testing.expect(!s.inward);

    // Fire is the only one the air holds back — and the drag is SOLVED with the speeds (see FIRE), not on top.
    try std.testing.expect(f.drag > 0);
    for ([_]Sig{ c, l, x }) |s| try std.testing.expect(s.drag == 0);
    // Lightning streaks hardest; a flame never streaks — a smeared flame is a comet, not a fire.
    try std.testing.expect(f.stretch == 0);
    for ([_]Sig{ c, x }) |s| try std.testing.expect(l.stretch > 1.3 * s.stretch);
}

test "every element COOLS to its own colour, and lightning to none" {
    const f = sig(.fire);
    const c = sig(.cold);
    const l = sig(.lightning);
    const x = sig(.chaos);
    try std.testing.expect(l.cool == null);
    // Fire dies DOWN (to ember red, darker than its core); cold dies WHITER (frost settling).
    const fcool = f.cool.?;
    try std.testing.expect(@as(u16, fcool.r) + fcool.g + fcool.b < @as(u16, f.core.r) + f.core.g + f.core.b);
    const ccool = c.cool.?;
    try std.testing.expect(@as(u16, ccool.r) + ccool.g + ccool.b > @as(u16, c.edge.r) + c.edge.g + c.edge.b);
    try std.testing.expect(hueApart(fcool, ccool) > 45);
    try std.testing.expect(hueApart(fcool, x.cool.?) > 45);
    try std.testing.expect(hueApart(ccool, x.cool.?) > 45);
}

/// HOW FAR APART TWO PARTICLE COLOURS ACTUALLY LOOK — the distance on the two OPPONENT axes (red-green and
/// green-blue), which is a hue comparison that brightness cannot fake. A single axis cannot do this job: the
/// first pass compared red-against-blue alone and passed a cyan frost mote and a violet chaos mote as
/// separate while calling the frost and the lightning spark identical, which is both answers wrong.
fn hueApart(a: rl.Color, b: rl.Color) f32 {
    const arg = @as(f32, @floatFromInt(@as(i32, a.r) - @as(i32, a.g)));
    const agb = @as(f32, @floatFromInt(@as(i32, a.g) - @as(i32, a.b)));
    const brg = @as(f32, @floatFromInt(@as(i32, b.r) - @as(i32, b.g)));
    const bgb = @as(f32, @floatFromInt(@as(i32, b.g) - @as(i32, b.b)));
    return @sqrt((arg - brg) * (arg - brg) + (agb - bgb) * (agb - bgb));
}

test "every element separates on HUE as well, and none of them is grey" {
    var i: usize = 0;
    while (i < combat.NELEM) : (i += 1) {
        const a = sig(@enumFromInt(i));
        const core = @as(u16, a.core.r) + a.core.g + a.core.b;
        const edge = @as(u16, a.edge.r) + a.edge.g + a.edge.b;
        try std.testing.expect(core > 380);
        try std.testing.expect(a.core.a > 180);
        try std.testing.expect(core > edge);
        var j: usize = i + 1;
        while (j < combat.NELEM) : (j += 1) {
            const b = sig(@enumFromInt(j));
            try std.testing.expect(hueApart(a.core, b.core) > 45);
            try std.testing.expect(hueApart(a.edge, b.edge) > 45);
        }
    }
}

test "a pour covers the reach it claims" {
    var pool = [_]foe.Particle{.{}} ** 64;
    var head: usize = 0;
    var rng = mathx.Rng.init(0x51E);
    const REACH: f32 = 6.0;
    pour(&pool, &head, &rng, mathx.zero3, v3(0, 0, -1), .cold, 48, 0.42, REACH, 1.0);
    var covered: f32 = 0;
    for (pool) |p| {
        if (p.life <= 0) continue;
        covered = mathx.maxF(covered, mathx.lenV(p.v) * p.life);
    }
    try std.testing.expect(covered >= REACH * 0.9);
}

test "a gather actually converges" {
    var pool = [_]foe.Particle{.{}} ** 32;
    var head: usize = 0;
    var rng = mathx.Rng.init(0x6A7);
    const at = v3(1, 2, 3);
    gather(&pool, &head, &rng, at, .chaos, 24, 0.4, 1.0);
    for (pool) |p| {
        if (p.life <= 0) continue;
        const toward = mathx.normV(mathx.subV(at, p.p));
        const v = mathx.normV(p.v);
        try std.testing.expect(toward.x * v.x + toward.y * v.y + toward.z * v.z > 0.5);
    }
}
