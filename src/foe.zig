const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const gfx = @import("gfx.zig");
const wf = @import("worldfmt.zig");

const v3 = mathx.v3;

// ── THE FOE STANDARD ────────────────────────────────────────────────────────────────────
// The contract + behaviours every enemy plugs into, so lock-on, HP bars, collision, the blade hit
// test and the combat beats are written ONCE. Adding an enemy is: build its rig + AI, satisfy the
// contract, reuse what's here.
//
// THE CONTRACT — duck-typed; the generic call sites check it:
//   FIELDS   pos (where it stands: XZ, and Y = THE GROUND HEIGHT THERE — 0 on a flat map, whatever the
//            terrain was sculpted to otherwise; game.zig grounds it every frame), vit (embed a
//            combat.Vitals), hits (total blows landed),
//            justDied (true ONLY on the frame a blow kills it — drives the kill beat)
//   METHODS  alive (a fully-dissipated corpse is false) / dying (collapsing: no threat, no bar, no
//            lock) / staggered (the wide-open window) / airborne (collision leaves it be; false if
//            N/A) / bodyR (collision footprint) / hurtRadius (what the blade tests) / centerWorld
//            (mass centre) / lockPoint (reticle) / topWorld (floating HP bar) / flashFrac (0..1 for
//            gfx hitFlash) / tryHit(Blade) — reuse `strike`.
//
// A `Group` is a fixed array of Foe plus the shared plumbing below; game.zig iterates them generically.

// ── shared foe tuning ── each was three identical copies (frog / archer / ogre). One place, so a
// retune can't reach two foes and miss the third.
pub const FLASH_DUR: f32 = 0.20; // seconds a struck foe pops on the shared gfx `hitFlash` uniform
pub const FLASH_GAIN: f32 = 0.85; // …and how hard it drives it, applied by every Group's draw()
// THE HERO'S FOOTPRINT, where both sides can see it: `HERO_R` is what game.zig pushes him out of the
// world with, `HERO_REACH` the forgiveness every foe adds to its own attack reach. They lived in
// different files with each comment pointing at the other, so no foe could reason about how close the
// hero can GET — which is how the ogre's swipe got an inner edge inside the distance collision
// permits (see ogre.SWIPE_INNER).
pub const HERO_R: f32 = 0.36;
pub const HERO_REACH: f32 = 0.55;
/// The nearest the hero can stand to a foe of footprint `bodyR`. An attack shape with an inner edge
/// must clear this or the "get inside it" counter cannot exist.
pub fn closestApproach(bodyR: f32) f32 {
    return bodyR + HERO_R;
}

/// TURN TOWARD A POINT at `rate` rad/s, shortest arc, ignoring a target you are standing on. Each
/// foe carried a byte-identical copy of these three lines (frog / archer / ogre), differing only in
/// which of its own TURN_RATEs it reached for — the same WET failure `applyShove` and `strike` live
/// here to prevent. The zero-length guard is the load-bearing part: `headingXZ` of a zero vector is
/// atan2(0, 0) = 0, so a hero standing exactly on a foe would otherwise snap its facing to +Z.
pub fn faceToward(pos: rl.Vector3, facing: *f32, target: rl.Vector3, rate: f32, dt: f32) void {
    const d = mathx.dirXZ(pos, target);
    if (mathx.lenXZ(d) < 1e-3) return;
    facing.* = mathx.approachAngle(facing.*, mathx.headingXZ(d), rate * dt);
}

/// A struck foe's 0..1 flash strength for the shared `gfx` hitFlash uniform (see FLASH_DUR /
/// FLASH_GAIN). Likewise three byte-identical copies of one expression over a constant that was
/// ALREADY shared, which is one copy more than a thing this small has any business having.
pub fn flashFrac(flash: f32) f32 {
    return mathx.clampF(flash / FLASH_DUR, 0, 1);
}

// Carry a landed blow's KNOCKBACK for one frame and bleed it off — a jolt off the blade, not a slide.
// Collision cleans up any overlap it causes.
pub fn applyShove(pos: *rl.Vector3, shove: *rl.Vector3, decay: f32, bounds: f32, dt: f32) void {
    if (mathx.lenXZ(shove.*) <= 0.01) return;
    mathx.stepXZ(pos, shove.*, dt, bounds); // the shared bounded step — shove is a velocity, so dist = dt
    shove.* = mathx.scaleV(shove.*, mathx.maxF(0, 1.0 - decay * dt));
}

// ── TELEGRAPH FX: the shared particle pool ──────────────────────────────────────────────
// The unlit specks that SELL a foe's tells. The particle's SHAPE and how it integrates/draws is
// cross-cutting and lives here; the AUTHORING (which bursts fire, how fast, how big) stays per-foe —
// that is the creature's character. Each owner keeps its own ring + head + emit carry + seeded Rng,
// so pools stay independent and deterministic.

// Two burst COLOURS belong here for the same reason FLASH_* do (they were byte-identical copies in
// frog.zig and ogre.zig): they are the WORLD's, not one creature's. `DUST` is what any heavy body
// kicks off dry ground; `MOTE` is the grace-gold every corpse dissipates into, which has to be ONE
// colour or the dissipation stops reading as one phenomenon. BLOOD stays per-foe — the toad bleeds
// oxblood and the ogre dark ichor, on purpose.
pub const DUST = mathx.rgba(150, 132, 96, 175);
pub const MOTE = mathx.rgba(252, 198, 92, 170);

/// One telegraph particle: integrates ballistically, lerps r0→r1, fades out as its life runs down.
pub const Particle = struct {
    p: rl.Vector3 = mathx.zero3,
    v: rl.Vector3 = mathx.zero3,
    life: f32 = 0, // seconds remaining (0 = dead slot)
    max: f32 = 1, // life at spawn (for the fade fraction)
    r0: f32 = 0.05, // radius at spawn
    r1: f32 = 0.05, // radius at death (r1>r0 = an expanding puff; r1<r0 = a shrinking spark)
    col: rl.Color = mathx.rgba(255, 255, 255, 255),
    grav: f32 = 0, // downward accel (world/s²); negative floats up
};

/// Push one particle into the ring, overwriting the oldest slot and advancing `head`.
pub fn emitParticle(pool: []Particle, head: *usize, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
    pool[head.*] = .{ .p = p, .v = vel, .life = life, .max = life, .r0 = r0, .r1 = r1, .col = col, .grav = grav };
    head.* = (head.* + 1) % pool.len;
}

/// Integrate every live particle a frame. Dust settles ON the ground rather than sinking through, and
/// `floor` is where that ground IS — the emitting creature's own `pos.y`, since a burst belongs to its
/// feet. It used to be a hard 0, which on sculpted terrain drops a puff of dust and a corpse's motes
/// straight through the hill the creature is standing on.
pub fn tickParticles(pool: []Particle, dt: f32, floor: f32) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        q.life -= dt;
        q.p.x += q.v.x * dt;
        q.p.y += q.v.y * dt;
        q.p.z += q.v.z * dt;
        q.v.y -= q.grav * dt;
        if (q.p.y < floor) q.p.y = floor;
    }
}

/// Unlit spheres — call INSIDE the lit 3D pass, after the opaque geometry (never the depth pass), so
/// the dust/glow reads OVER the foe. Low-poly on purpose: at sub-10 cm a coarse sphere reads the same
/// as raylib's default 16×16 at ~1/5 the triangles, which is real when a whole knot bursts at once.
pub fn drawParticles(pool: []const Particle) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        const frac = mathx.clampF(q.life / q.max, 0, 1);
        const rad = mathx.lerpF(q.r1, q.r0, frac); // r0 at spawn (frac 1) → r1 at death (frac 0)
        const a = mathx.u8f(@as(f32, @floatFromInt(q.col.a)) * frac);
        rl.drawSphereEx(q.p, rad, 6, 8, mathx.withAlpha(q.col, a));
    }
}

// ── the Group plumbing (generic over ANY foe array — the shared contract is all it touches) ──
// Every Group's bodies for these were identical, so they live here once and each Group's method is a
// one-line delegate. A `reset` or `draw` that drifted on ONE foe shows up as that foe surviving a
// death, or as a hot hitFlash uniform reddening whatever draws next — and nothing would say so.

/// RE-HOME from the map: every spawn of `want`, built fresh (full HP, home position, slain restored)
/// — what a hero death does to the field, ER-style. Overflow past `out.len` is skipped.
pub fn resetGroup(comptime T: type, out: []T, n: *usize, m: *const wf.Map, want: wf.FoeKind) void {
    n.* = 0;
    for (m.foes[0..m.nfoes]) |h| {
        if (h.kind != want or n.* >= out.len) continue;
        // ON THE GROUND, which the map's own height field decides — a spawn table stores x/z only, so
        // posting a foe on a sculpted rise and dropping it at y = 0 would bury it to the waist.
        out[n.*] = T.spawn(v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
        n.* += 1;
    }
}

/// Draw the live instances, each flaring by its OWN hit flash on the shared `hitFlash` uniform, then
/// put the uniform back to 0. `scene` null = a path with no per-actor flash (the depth pass, where the
/// write is inert anyway).
pub fn drawGroup(foes: anytype, model: anytype, scene: ?*gfx.Scene) void {
    for (foes) |*f| {
        if (!f.alive()) continue;
        if (scene) |sc| sc.setFlash(FLASH_GAIN * f.flashFrac());
        f.draw(model);
    }
    if (scene) |sc| sc.setFlash(0);
}

/// Died THIS frame? The kill beat keys off this — aliveCount only drops once the dissipation finishes.
pub fn anyDied(foes: anytype) bool {
    for (foes) |*f| {
        if (f.justDied) return true;
    }
    return false;
}

/// Total blows landed across the group (drives the combat beats + the debug read-out).
pub fn totalHits(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| n += f.hits;
    return n;
}

/// RUNES paid out THIS FRAME: `per` per instance whose one-frame `justDied` is set. The same flag the
/// kill BEAT reads, so payout / rumble / shake can never disagree — and being one-frame, a corpse
/// cannot pay twice however long its dissipation takes.
pub fn runesDropped(foes: anytype, per: u32) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += per;
    }
    return n;
}

/// How many foes are still standing.
pub fn aliveCount(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.alive()) n += 1;
    }
    return n;
}

// The hero's blade this frame as plain data — keeps every foe decoupled from the hero rig.
// Endpoints are guard→tip; the *0 pair is LAST frame's, for a swept (tunnel-proof) test.
pub const Blade = struct {
    active: bool = false,
    r: f32 = 0,
    a: rl.Vector3 = mathx.zero3,
    b: rl.Vector3 = mathx.zero3,
    a0: rl.Vector3 = mathx.zero3,
    b0: rl.Vector3 = mathx.zero3,
    hit: combat.Hit = .{}, // HP/poise/stance the swing deals (light vs heavy, set by game.zig)
};

// ONE BLOW A GROUP LANDED ON THE HERO, and WHERE IT CAME FROM. The position is the load-bearing
// half: the hero's shield covers an ARC (combat.GUARD_ARC), so "was that blocked?" cannot be
// answered without knowing which side of him it arrived on. Every Group used to hand back a bare
// `?combat.Hit` — the strongest of its instances' — which threw the attacker away at the one place
// that still knew it, leaving the caller to guess (the nearest live foe is *usually* the one that
// hit you, and usually is not a mechanic).
pub const Blow = struct {
    hit: combat.Hit,
    from: rl.Vector3, // the attacker's own `pos`, in world space
};

/// Keep the STRONGEST blow of a frame. The comparison is on `.dmg` and a copy that drifted would
/// silently let a nibble outrank a slam, so it is written once. Called directly only by the WARBAND,
/// whose update walks its members for its own reasons; every other Group goes through `groupBlow`.
pub fn worseBlow(worst: *?Blow, h: combat.Hit, from: rl.Vector3) void {
    if (worst.* == null or h.dmg > worst.*.?.hit.dmg) worst.* = .{ .hit = h, .from = from };
}

/// ADVANCE A GROUP AND RETURN THE STRONGEST BLOW IT LANDED. The whole body of `Knot.update` and
/// `Grief.update`, which were byte-identical down to the loop variable — the same WET failure
/// `resetGroup`/`drawGroup` live here to prevent, and one a third foe would have copied again.
pub fn groupBlow(foes: anytype, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?Blow {
    var worst: ?Blow = null;
    for (foes) |*f| {
        if (f.update(dt, hero, bounds, blade)) |h| worseBlow(&worst, h, f.pos);
    }
    return worst;
}

// What a landed blow yields: WHERE it connected, the sweep direction (blood/knockback), and the
// reaction the vitals decided. The caller lays its own FX + state transition on top; the geometry,
// the one-hit LATCH and the damage are handled here.
pub const Strike = struct {
    contact: rl.Vector3,
    dir: rl.Vector3,
    reaction: combat.HitResult,
};

// THE shared hit behaviour: swept blade vs hurt sphere; on a landed un-latched blow, LATCH it (one hit
// per swing), apply HP/poise/stance and return the Strike. Null when nothing lands — window closed
// (which RE-ARMS the latch), already latched this swing, or out of reach.
pub fn strike(vit: *combat.Vitals, hitLatch: *bool, center: rl.Vector3, hurtR: f32, blade: Blade) ?Strike {
    if (!blade.active) {
        hitLatch.* = false; // window closed → the next swing may land again
        return null;
    }
    if (hitLatch.*) return null;
    const reach = hurtR + blade.r;
    // Swept: test THIS frame's blade segment AND last frame's, so a fast arc can't skip the foe.
    const q1 = mathx.closestOnSegV(center, blade.a, blade.b);
    const hit1 = mathx.lenV(mathx.subV(center, q1)) <= reach;
    const q0 = mathx.closestOnSegV(center, blade.a0, blade.b0);
    if (!(hit1 or mathx.lenV(mathx.subV(center, q0)) <= reach)) return null;
    hitLatch.* = true;
    // The blow reads at the wound: blood/knockback fly along the blade's sweep at the contact.
    const contact = if (hit1) q1 else q0;
    var sweep = mathx.subV(mathx.lerpV(blade.a, blade.b, 0.7), mathx.lerpV(blade.a0, blade.b0, 0.7));
    sweep.y = 0;
    const dir = if (mathx.lenXZ(sweep) > 0.03) mathx.normV(sweep) else mathx.dirXZ(contact, center);
    return .{ .contact = contact, .dir = dir, .reaction = vit.hit(blade.hit) };
}

test "strike: latches one hit per swing, re-arms when the window closes, applies the reaction" {
    var vit = combat.Vitals.init(100, 8, 100); // low poise → a hit flinches
    var latch = false;
    const c = mathx.v3(0, 1, 0);
    const active = Blade{ .active = true, .r = 0.4, .a = mathx.v3(0, 1, -1), .b = mathx.v3(0, 1, 1), .a0 = mathx.v3(0, 1, -1), .b0 = mathx.v3(0, 1, 1), .hit = .{ .dmg = 10, .poise = 20 } };
    // First contact lands + latches + flinches.
    const s = strike(&vit, &latch, c, 0.5, active);
    try std.testing.expect(s != null);
    try std.testing.expectEqual(combat.HitResult.light, s.?.reaction);
    try std.testing.expect(latch);
    // Same active swing again: latched → no second hit.
    try std.testing.expect(strike(&vit, &latch, c, 0.5, active) == null);
    // Window closes → latch re-arms for the next swing.
    _ = strike(&vit, &latch, c, 0.5, .{ .active = false });
    try std.testing.expect(!latch);
    // Out of reach → no hit.
    try std.testing.expect(strike(&vit, &latch, mathx.v3(9, 1, 0), 0.5, active) == null);
}
