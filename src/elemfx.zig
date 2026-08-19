const std = @import("std");
const rl = @import("raylib");

const combat = @import("combat.zig");
const foe = @import("foe.zig");
const mathx = @import("mathx.zig");

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
};

const FIRE = Sig{
    .core = rgba(255, 198, 104, 228),
    .edge = rgba(228, 116, 28, 200),
    .grav = -2.1,
    .speedLo = 1.1,
    .speedHi = 3.0,
    .lifeLo = 0.26,
    .lifeHi = 0.52,
    .r0 = 0.030,
    .r1 = 0.058,
    .ash = rgba(74, 68, 62, 120),
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
};

/// LIGHTNING — **THE ONLY COLOURLESS ONE IN THE TABLE**, and that is the decision. It went in first as the
/// thundercrock's pale blue (`archer.TRAIL_CROCK`) and the hue test below refused it: against COLD, which
/// owns the blues, the two were one substance at two brightnesses — a frost mote and a spark you could not
/// tell apart on a still frame. A spark is white-hot and has no colour of its own, so it is authored as the
/// achromatic one and separates from all three of the others by having no hue to compare. (The crock's
/// STREAK is left as it is: that is a thing in the SKY at range, and it has no cold to be confused with up
/// there.)
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
};

pub fn sig(e: combat.Elem) Sig {
    return switch (e) {
        .fire => FIRE,
        .cold => COLD,
        .lightning => LIGHTNING,
        .chaos => CHAOS,
    };
}


pub fn gather(pool: []foe.Particle, head: *usize, rng: *mathx.Rng, at: rl.Vector3, e: combat.Elem, n: usize, r: f32, scale: f32) void {
    const s = sig(e);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const dir = randomUnit(rng);
        const from = mathx.addV(at, mathx.scaleV(dir, r * scale));
        const sp = rng.range(s.speedLo, s.speedHi) * scale;
        const v = mathx.scaleV(dir, -sp);
        foe.emitParticle(pool, head, from, v, rng.range(s.lifeLo, s.lifeHi) * 0.7, s.r0 * scale, s.r1 * scale, s.core, s.grav * 0.4);
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
        foe.emitParticle(pool, head, from, v, life, s.r0 * scale, s.r1 * scale, if (i % 3 == 0) s.core else s.edge, s.grav);
        if (s.ash) |ash| {
            if (i % 3 == 1) {
                foe.emitParticle(pool, head, from, mathx.scaleV(v, 0.35), life * 2.4, s.r1 * scale, s.r1 * scale * 2.6, ash, s.grav * 0.30);
            }
        }
    }
}

/// MOTES A SECOND A `pour` LAYS DOWN. Part of the LANGUAGE and not of whoever is pouring: solved against
/// the table's own lifetimes so the stream reads as continuous from the nozzle to the far end, and under
/// about fifty it comes out as a dotted line. The hero's breath and the editor's bench both run at it, so
/// what is tuned on the bench is what arrives in the fight.
/// MEASURED OFF A RENDER, not chosen: at 70 the breath came back as eight dots strung across six metres of
/// ground — a rate that is fine for a jet a metre long is nothing at all spread over a cone. What has to be
/// continuous is the FAR end, where the same motes are spread over the widest part of the cone, so the rate
/// is solved there and the near end simply looks dense.
pub const POUR_RATE: f32 = 560.0;

pub const POUR_CAP: usize = foe.emitCap(POUR_RATE);

const POUR_GRAIN: f32 = 0.62;

const POUR_SIZE_LO: f32 = 0.45;
const POUR_SIZE_HI: f32 = 1.55;

/// **AND EVERY POUR HAS A KNOT AT ITS NOZZLE** — one root mote per this many stream motes, inside this much
/// of `r0` of the source, barely moving and dead almost at once. A cone with nothing bright at its apex is a
/// drift of dots that happens to start near the emitter; what says a jet is LEAVING something is the dense
/// near-still knot it leaves FROM. It is here and not at the call site for the file's own reason: a caller
/// picks the VERB and the ELEMENT, never a colour, a lifetime or a gravity.
const POUR_ROOT_EVERY: usize = 4;
const POUR_ROOT_R: f32 = 1.6;
const POUR_ROOT_LIFE_LO: f32 = 0.05;
const POUR_ROOT_LIFE_HI: f32 = 0.13;

/// How many motes ONE `pour` of `n` actually emits, root included — the pool arithmetic every caller sizes
/// its ring off (`hero.FX_N`). Written here so a change to the root's cadence cannot leave a caller's
/// comptime assert quietly stale. **It is the count for ONE CALL**: a caller making `k` calls owes
/// `k * pourCount(n)`, and `pourCount(k * n)` is not the same number — the knot restarts every call.
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
        foe.emitParticle(pool, head, from, mathx.scaleV(out, sp), life, s.r0 * scale * grain, s.r1 * scale * 1.5 * grain, if (i % 2 == 0) s.core else s.edge, s.grav * 0.5);
        if (i % POUR_ROOT_EVERY == 0) {
            const rr = s.r0 * scale * POUR_ROOT_R;
            const a = rng.angle();
            const wide = rng.range(0, rr);
            foe.emitParticle(
                pool,
                head,
                v3(from.x + mathx.cosf(a) * wide, from.y + rng.signed() * rr, from.z + mathx.sinf(a) * wide),
                mathx.scaleV(axis, rng.range(0.2, 0.9)),
                rng.range(POUR_ROOT_LIFE_LO, POUR_ROOT_LIFE_HI),
                rr * rng.range(0.5, 1.25),
                rr * 0.25,
                s.core,
                0,
            );
        }
    }
}

fn randomUnit(rng: *mathx.Rng) rl.Vector3 {
    const z = rng.signed();
    const a = rng.range(0, std.math.tau);
    const r = @sqrt(mathx.maxF(0, 1.0 - z * z));
    return v3(r * mathx.cosf(a), z, r * mathx.sinf(a));
}


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
