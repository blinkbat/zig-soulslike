const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");

// ── THE FOE STANDARD ────────────────────────────────────────────────────────────────────
// The contract + behaviours every enemy plugs into, so the cross-cutting systems — lock-on, HP
// bars, collision, the blade hit test, the combat beats — are written ONCE for any foe. Adding
// an enemy is: build its rig + AI, satisfy this contract, reuse the behaviours here.
//
// THE CONTRACT — a Foe type exposes (duck-typed; the generic call sites check it):
//   FIELDS   pos: rl.Vector3          — ground position (XZ; Y≈0)
//            vit: combat.Vitals       — HP + the two-tier poise/stance stagger (embed one)
//            hits: u32                — total blows landed on it (drives the combat beats)
//            justDied: bool           — true only on the frame a blow kills it (kill beat)
//   METHODS  alive() bool             — a live combatant (a fully-dissipated corpse is false)
//            dying() bool             — collapsed/dissipating: no threat, no HP bar, no lock
//            staggered() bool         — reeling/dead: the wide-open window
//            airborne() bool          — off the ground (collision leaves it be); false if N/A
//            bodyR() f32              — ground-footprint radius (collision)
//            hurtRadius() f32         — hurt-sphere radius the hero's blade tests against
//            centerWorld() rl.Vector3 — body-mass centre (blade test + camera focus)
//            lockPoint() rl.Vector3   — where the lock-on reticle rides
//            topWorld() rl.Vector3    — where the floating HP bar rides (above the head)
//            flashFrac() f32          — 0..1 blood/hit-flash strength (gfx hitFlash uniform)
//            tryHit(Blade) void       — apply the hero's blade this frame (reuse `strike`)
//
// A `Group` (Knot of toads, Line of archers) is a fixed array of Foe + the shared roll-ups
// (anyDied / totalHits / aliveCount) the beats read; game.zig iterates the groups generically.

// ── shared foe tuning ── each of these was three identical copies (frog / archer / ogre). One
// place, so a retune can't reach two foes and miss the third.
pub const FLASH_DUR: f32 = 0.20; // seconds a struck foe pops on the shared gfx `hitFlash` uniform
pub const FLASH_GAIN: f32 = 0.85; // …and how hard it drives it, applied by every Group's draw()
// THE HERO'S FOOTPRINT, in the one place both sides can see it.
// `HERO_R` is the collision radius game.zig pushes him out of the world with; `HERO_REACH` is the
// forgiveness every foe adds to its own attack reach on top of it. They lived in different files
// (HERO_R in game.zig, HERO_REACH here) with each comment pointing at the other, so no foe could
// reason about how close the hero can actually GET — which is how the ogre's swipe ended up with an
// inner edge inside the distance collision physically permits (see ogre.SWIPE_INNER).
pub const HERO_R: f32 = 0.36;
pub const HERO_REACH: f32 = 0.55;
/// The nearest the hero can stand to a foe of footprint `bodyR` — collision never allows closer.
/// Attack shapes with an inner edge must clear this or the "get inside it" counter cannot exist.
pub fn closestApproach(bodyR: f32) f32 {
    return bodyR + HERO_R;
}

/// One instance's spawn record in a Group's `homes` table.
// (A `Home` struct used to live here, describing one hard-coded spawn. Spawns are map data now
// — `worldfmt.Foe`, placed with the editor's Units layer — and every group reads them from
// there, so nothing referenced it any more.)

// Carry a landed blow's KNOCKBACK for one frame and bleed it off. A jolt off the blade, not a
// slide — collision cleans up any overlap it causes.
pub fn applyShove(pos: *rl.Vector3, shove: *rl.Vector3, decay: f32, bounds: f32, dt: f32) void {
    if (mathx.lenXZ(shove.*) <= 0.01) return;
    pos.x = mathx.clampF(pos.x + shove.x * dt, -bounds, bounds);
    pos.z = mathx.clampF(pos.z + shove.z * dt, -bounds, bounds);
    shove.* = mathx.scaleV(shove.*, mathx.maxF(0, 1.0 - decay * dt));
}

// ── TELEGRAPH FX: the shared particle pool ──────────────────────────────────────────────
// The unlit specks that SELL a foe's tells — dust under a coil, an amber charge glow, a blood
// burst, the grace-gold motes a corpse dissipates into. The particle's SHAPE and how it
// integrates/draws is cross-cutting and lives here; the AUTHORING (which bursts fire, how fast,
// how big) stays per-foe — that is the creature's character.
//
// Each owner keeps its own ring + head + emit carry + seeded Rng, so pools stay independent and
// deterministic; these routines just operate on them.

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

/// Integrate every live particle a frame. Dust settles ON the ground rather than sinking through.
pub fn tickParticles(pool: []Particle, dt: f32) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        q.life -= dt;
        q.p.x += q.v.x * dt;
        q.p.y += q.v.y * dt;
        q.p.z += q.v.z * dt;
        q.v.y -= q.grav * dt;
        if (q.p.y < 0) q.p.y = 0;
    }
}

/// Draw the live particles as unlit spheres — call INSIDE the lit 3D pass, after the opaque
/// geometry (never the shadow depth pass), so the dust/glow reads OVER the foe.
/// Low-poly on purpose: these are sub-10 cm specks, so a coarse sphere reads the same as raylib's
/// default 16×16 one at ~1/5 the triangles — real savings when a whole knot bursts at once.
pub fn drawParticles(pool: []const Particle) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        const frac = mathx.clampF(q.life / q.max, 0, 1);
        const rad = mathx.lerpF(q.r1, q.r0, frac); // r0 at spawn (frac 1) → r1 at death (frac 0)
        const a = mathx.u8f(@as(f32, @floatFromInt(q.col.a)) * frac);
        rl.drawSphereEx(q.p, rad, 6, 8, mathx.withAlpha(q.col, a));
    }
}

// ── the Group roll-ups (generic over ANY foe array — the shared contract is all they touch) ──
// Every Group (Knot / Line / Grief) exposes these three; the bodies were identical in all three,
// so they live here once and each Group's method is a one-line delegate.

/// Did any foe die THIS frame? The kill beat keys off this, since aliveCount only drops later
/// (when the dissipation finishes).
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

/// RUNES the group paid out THIS FRAME: `per` for every instance whose one-frame `justDied` is set.
/// Keyed off the same flag the kill BEAT reads, so the payout, the rumble and the shake can never
/// disagree about whether something died — and because that flag is one-frame, a corpse cannot pay
/// twice however long its dissipation takes.
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

// What a landed blow yields: WHERE it connected + the sweep direction (for blood/knockback) +
// the reaction the vitals decided (none / light / heavy / death). The caller lays its own FX +
// state transition on top — the geometry, one-hit LATCH, and damage are handled here.
pub const Strike = struct {
    contact: rl.Vector3,
    dir: rl.Vector3,
    reaction: combat.HitResult,
};

// THE shared hit behaviour: test the hero's swept blade against a foe's hurt sphere; on a
// landed, un-latched blow LATCH it (one hit per swing), apply HP/poise/stance, and return
// contact + sweep dir + reaction. Returns null when nothing lands — window closed (which
// RE-ARMS the latch), already latched this swing, or out of reach.
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
