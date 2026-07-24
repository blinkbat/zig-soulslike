const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");

// ── THE FOE STANDARD ────────────────────────────────────────────────────────────────────
// The shared contract + behaviours every enemy plugs into, so the game's cross-cutting foe
// systems — lock-on, floating HP bars, footprint collision, the hero's-blade hit test, and
// the combat beats (rumble/shake) — are written ONCE and work for ANY foe (the gaping toad,
// the skeletal archer, and whatever comes next). Adding an enemy should be: build its rig +
// AI, satisfy this contract, reuse the behaviours here, and it drops into every system with
// little or no game.zig change.
//
// THE CONTRACT — a Foe type exposes (duck-typed; the shared/generic call sites check it):
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
// landed, un-latched blow LATCH it (one hit per swing), apply HP/poise/stance via `vit`, and
// return the contact + sweep dir + reaction. Returns null when nothing lands (window closed —
// which also RE-ARMS the latch — already latched this swing, or out of reach). Every foe's
// tryHit is `if (foe.strike(...)) |s| { own FX; react on s.reaction; }`.
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
