const std = @import("std");
const rl = @import("raylib");

const combat = @import("combat.zig");
const foe = @import("foe.zig");
const mathx = @import("mathx.zig");

const rgba = mathx.rgba;
const v3 = mathx.v3;

/// THE ELEMENTS' PARTICLE LANGUAGE — one signature per `combat.Elem`, and THE SIGNATURE IS THE MOTION.
pub const Sig = struct {
    /// The hot centre, and what a `gather` is made of.
    core: rl.Color,
    /// …and the cooler half a `burst` is mostly made of. Never a second hue: one substance, two temperatures.
    edge: rl.Color,
    /// Downward accel. NEGATIVE FLOATS, which is fire's whole read.
    grav: f32,
    speedLo: f32,
    speedHi: f32,
    lifeLo: f32,
    lifeHi: f32,
    r0: f32,
    r1: f32,
    /// CHAOS ALONE. A `pour`/`burst` whose motes converge on the source instead of leaving it.
    inward: bool = false,
    /// FIRE ALONE — what a mote cools INTO, once its own life is out. Null is every other element: nothing
    /// else in the set leaves a residue, and that absence is half of why the fire reads as fire.
    ash: ?rl.Color = null,
};

/// FIRE. The mesh flames (`propart.FLAME_*`) are albedos and are deliberately NOT reused here.
const FIRE = Sig{
    .core = rgba(255, 198, 104, 228),
    .edge = rgba(228, 116, 28, 200),
    .grav = -2.1, // …and it is the only negative one in the table
    .speedLo = 1.1,
    .speedHi = 3.0,
    .lifeLo = 0.26,
    .lifeHi = 0.52,
    .r0 = 0.030,
    .r1 = 0.058, // GROWS as it cools, which nothing else here does
    .ash = rgba(74, 68, 62, 120),
};

/// COLD — the necromancer's rune ring is the only other cold in the world, and it reads its two off THESE
/// (`necro.FROST_MOTE`, `necro.RIME`) rather than the other way round: this file sits below every creature
/// in the import graph, so the language is the only place the palette CAN be owned from.
const COLD = Sig{
    .core = rgba(212, 238, 250, 225),
    .edge = rgba(150, 200, 226, 235),
    .grav = 1.5, // it falls, and slowly
    .speedLo = 0.5,
    .speedHi = 1.7,
    .lifeLo = 0.60,
    .lifeHi = 1.15, // THE LONGEST IN THE TABLE, and that is the read
    .r0 = 0.028,
    .r1 = 0.010, // sublimates to nothing
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
    .speedHi = 14.0, // thrown hard…
    .lifeLo = 0.040,
    .lifeHi = 0.085, // …and dead before it arrives: THE SHORTEST IN THE TABLE by a factor of three
    .r0 = 0.021,
    .r1 = 0.003,
};

/// CHAOS — the wand's, and `hero.CHAOS_HOT`/`CHAOS_MOTE` are these two rather than a second pair that looks
/// like them (COLD's line: the language owns the palette, the creatures read it).
const CHAOS = Sig{
    .core = rgba(224, 176, 250, 210),
    .edge = rgba(168, 84, 216, 190),
    .grav = 0, // it obeys nothing, the ground included
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

// ── THE THREE VERBS ────────────────────────────────────────────────────────────────────────────────────
//
// Every elemental effect in the game is one of these three things happening in one of four ways, and the
// grid is the point: a caller picks the VERB its mechanic is doing and the ELEMENT it is doing it in, and
// never picks a colour, a lifetime or a gravity at a call site. Twelve cells, one table.

/// A CHARGE DRAWING IN — motes appearing on a shell of radius `r` and falling toward the point. What a
/// gathering cast is made of, and it is the same shape for all four: what differs is how fast they die on
/// the way in and what colour they are while they do it.
pub fn gather(pool: []foe.Particle, head: *usize, rng: *mathx.Rng, at: rl.Vector3, e: combat.Elem, n: usize, r: f32, scale: f32) void {
    const s = sig(e);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const dir = randomUnit(rng);
        const from = mathx.addV(at, mathx.scaleV(dir, r * scale));
        // INWARD for everything, because that is what a gather IS — chaos's own `inward` is about the other
        // two verbs, where it is the odd one out.
        const sp = rng.range(s.speedLo, s.speedHi) * scale;
        const v = mathx.scaleV(dir, -sp);
        foe.emitParticle(pool, head, from, v, rng.range(s.lifeLo, s.lifeHi) * 0.7, s.r0 * scale, s.r1 * scale, s.core, s.grav * 0.4);
    }
}

/// A BLOW LANDING — a cone thrown down `dir`, or a full sphere when `dir` is zero (the delver's rule: stood
/// dead on it there is no bearing). This is the verb a hit uses, and the one the four elements differ most
/// visibly in, because it is the one with the most travel in it.
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
        // CHAOS GOES THE WRONG WAY: it collapses back onto what it just left.
        const v = mathx.scaleV(out, if (s.inward) -sp * 0.55 else sp);
        const life = rng.range(s.lifeLo, s.lifeHi);
        const from = mathx.addV(at, mathx.scaleV(out, s.r0 * scale * 2.0));
        foe.emitParticle(pool, head, from, v, life, s.r0 * scale, s.r1 * scale, if (i % 3 == 0) s.core else s.edge, s.grav);
        // …AND THE FIRE'S RESIDUE, on a third of them: the only element here that leaves anything behind.
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

/// …AND THE CEILING ON ONE FRAME OF IT (`foe.emitCap`, off this rate). Both pourers want the same number for
/// the same reason, and as a hand-written literal on one side and the arithmetic on the other, moving
/// `POUR_RATE` silently turned that one into a throttle. It already had: at 240 the hero's cap was 18, and
/// the bench's own bare `8` was under what a single 60 fps frame owed.
pub const POUR_CAP: usize = foe.emitCap(POUR_RATE);

/// **A JET'S GRAIN IS FINER THAN THE TABLE'S, and that is the VERB's business rather than the caster's.** The
/// signatures' `r0` is sized for a couple of dozen motes lying about where each one has to read on its own
/// (the necromancer's rune ring); a pour is the opposite case — hundreds at once — and at the table's size it
/// comes out as a column of soap bubbles. Fine grains, and the DENSITY is what reads.
const POUR_GRAIN: f32 = 0.62;

/// **AND EVERY MOTE IN ONE IS A DIFFERENT SIZE.** A pour whose motes are all `r0` is the house style's own
/// named failure — too REGULAR — and at a jet's density it is the one place it shows worst: identical rounds
/// evenly spaced read as SOAP, not as frost. The spread is wide because the thing being drawn is a spray,
/// where a burst's motes genuinely are one substance breaking up.
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

/// A SUSTAINED STREAM — the breath, and whatever else pours later. `spread` is the cone's half-angle in
/// RADIANS and `reach` how far it is meant to arrive, which is what sizes the speed: a pour whose motes die
/// short of the mechanic's own reach is a spell that lies about where it hits.
pub fn pour(pool: []foe.Particle, head: *usize, rng: *mathx.Rng, from: rl.Vector3, dir: rl.Vector3, e: combat.Elem, n: usize, spread: f32, reach: f32, callerScale: f32) void {
    const s = sig(e);
    if (mathx.lenV(dir) < 1e-3) return;
    // The caller's own scale times the VERB's grain — so every pour in the game, the bench included, draws
    // the same size of mote for the same caller scale.
    const scale = callerScale * POUR_GRAIN;
    const axis = mathx.normV(dir);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        // THE CONE IS FULL, NOT A SHELL: `sqrt` of the roll, or the motes pile up on the outer surface and
        // the stream draws as a hollow tube with a hole down the middle of it.
        const off = mathx.scaleV(randomUnit(rng), @tan(spread) * @sqrt(rng.float()));
        const out = mathx.normV(mathx.addV(axis, off));
        // SPEED IS SOLVED OFF THE REACH, never chosen: the mote has to cover the cone in its own lifetime.
        const life = rng.range(s.lifeLo, s.lifeHi);
        const sp = (reach / mathx.maxF(life, 0.05)) * rng.range(0.55, 1.0);
        // …AND EACH ONE IS ITS OWN SIZE (`POUR_SIZE_*`), authored off the seeded stream so builds stay
        // deterministic. Applied to BOTH ends, so a big mote stays the big one for its whole life rather
        // than every mote converging on one death radius.
        const grain = rng.range(POUR_SIZE_LO, POUR_SIZE_HI);
        // The ELEMENT'S own taper: a stream widens because its motes DIVERGE, not because each one swells.
        foe.emitParticle(pool, head, from, mathx.scaleV(out, sp), life, s.r0 * scale * grain, s.r1 * scale * 1.5 * grain, if (i % 2 == 0) s.core else s.edge, s.grav * 0.5);
        // …AND THE KNOT AT THE NOZZLE. Always the CORE — this is the hot end of the stream, and an `edge`
        // here would say the substance is coolest where it leaves.
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

/// A UNIT VECTOR OFF THE STREAM, uniform on the sphere. REJECTION-FREE — Archimedes' hat-box, which draws a
/// height and a bearing and is done, because a `while` that resamples is a loop with no bound in a frame that
/// has one. (It said "Marsaglia", which is the polar method and is exactly the rejection sampler this avoids.)
fn randomUnit(rng: *mathx.Rng) rl.Vector3 {
    const z = rng.signed();
    const a = rng.range(0, std.math.tau);
    const r = @sqrt(mathx.maxF(0, 1.0 - z * z));
    return v3(r * mathx.cosf(a), z, r * mathx.sinf(a));
}

// ── TESTS ─────────────────────────────────────────────────────────────────────────────────────────────

test "the four are told apart with the COLOUR TAKEN AWAY" {
    // Which is the state the player meets them in: three at once over a bonfire, at a distance where the
    // hue is a couple of pixels and the MOTION is the whole read.
    const f = sig(.fire);
    const c = sig(.cold);
    const l = sig(.lightning);
    const x = sig(.chaos);

    // FIRE IS THE ONLY THING THAT GOES UP…
    try std.testing.expect(f.grav < 0);
    try std.testing.expect(c.grav > 0 and l.grav >= 0 and x.grav >= 0);
    // …and the only one that leaves a residue.
    try std.testing.expect(f.ash != null);
    for ([_]Sig{ c, l, x }) |s| try std.testing.expect(s.ash == null);
    // …and the only one that grows as it dies.
    try std.testing.expect(f.r1 > f.r0);
    for ([_]Sig{ c, l, x }) |s| try std.testing.expect(s.r1 < s.r0);

    // COLD LIES ABOUT: the longest life in the table, and by a clear factor over the next longest.
    try std.testing.expect(c.lifeHi > 2.0 * f.lifeHi);
    try std.testing.expect(c.lifeHi > 2.0 * x.lifeHi);
    // LIGHTNING IS GONE: the shortest, by a factor of three over anything else.
    try std.testing.expect(l.lifeHi * 3.0 < f.lifeHi);
    try std.testing.expect(l.lifeHi * 3.0 < c.lifeHi);
    // …and it is the only one thrown hard enough to be spent inside that life.
    try std.testing.expect(l.speedHi > 2.0 * f.speedHi);
    // CHAOS GOES THE WRONG WAY, and is the only one that does.
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
    // The hue check is the second half, not the first: two elements that move differently may still be
    // mistaken for one another on a still frame, which is what a screenshot of a fight is. BOTH halves are
    // checked — the core is what a gather is made of and the edge is most of what a burst is, so two
    // elements sharing either one share the picture on half the verbs.
    var i: usize = 0;
    while (i < combat.NELEM) : (i += 1) {
        const a = sig(@enumFromInt(i));
        // A LITERAL SCREEN VALUE, and a bright one: these are drawn unlit over a warm world.
        const core = @as(u16, a.core.r) + a.core.g + a.core.b;
        const edge = @as(u16, a.edge.r) + a.edge.g + a.edge.b;
        try std.testing.expect(core > 380);
        try std.testing.expect(a.core.a > 180);
        // …and the core is the HOTTER half of its own pair, or the two temperatures are the wrong way round.
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
    // A stream whose motes die short of the mechanic's own reach is a spell that lies about where it hits.
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
        // Every mote is moving toward the point it is gathering on, not away from it.
        const toward = mathx.normV(mathx.subV(at, p.p));
        const v = mathx.normV(p.v);
        try std.testing.expect(toward.x * v.x + toward.y * v.y + toward.z * v.z > 0.5);
    }
}
