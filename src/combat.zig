const std = @import("std");
const mathx = @import("mathx.zig");

// ── COMBAT VITALS: HP + the two-tier ELDEN RING stagger model ───────────────────────────
// Every character (hero + foe) embeds one `Vitals`. It holds HP and the two hidden meters
// that drive staggering, modelled straight off Elden Ring (see docs/ELDEN_RING.md):
//
//   POISE  — flinch resistance ("poise HP"). Each hit chips it by the attack's poise damage.
//            When it empties the character takes a LIGHT STUN (a flinch/interrupt) and the
//            poise meter RESETS to full (ER resets player poise on stagger). It also
//            REGENERATES over time once you stop being hit — so light hits only interrupt
//            if you land them fast enough. Frogs get LOW poise (they flinch easily).
//   STANCE — the "poise break" that opens a heavy stagger. Each LIGHT break chips it (and
//            heavy attacks chip it directly via Hit.stance). When it empties the character
//            takes a HEAVY STUN (a long, wide-open stagger — ER's stance break, minus the
//            critical/riposte, which we don't have yet) and stance RESETS. Stance regens
//            SLOWER than poise, so reaching the heavy demands sustained PRESSURE.
//
// Pure logic, no GPU/world state — unit-tested below. The stun ANIMATIONS + timers live in
// each character (hero.zig / frog.zig); this module only decides WHAT event a hit triggers.

pub const StunKind = enum { none, light, heavy };

// The outcome of a single hit — what the victim should react to THIS frame.
pub const HitResult = enum { none, light, heavy, death };

// One landed blow, as plain data (keeps attacker/victim decoupled). `dmg` = HP damage;
// `poise` = poise-meter damage; `stance` = DIRECT stance damage (heavy attacks set this so
// they break stance faster — light attacks leave it 0 and lean on the light-break chip).
pub const Hit = struct {
    dmg: f32 = 0,
    poise: f32 = 0,
    stance: f32 = 0,
};

// ── tuning (shared feel constants) ──────────────────────────────────────────────────────
const REGEN_DELAY = 0.8; // seconds after the last hit before poise/stance start refilling
const POISE_REFILL = 1.3; // seconds to refill poise from empty (once regen kicks in)
const STANCE_REFILL = 4.6; // …stance refills slower — the "keep pressure on" meter
const LIGHT_BREAK_STANCE = 0.40; // fraction of max stance a single LIGHT break chips off
// Stun durations (seconds). Light is a sharp flinch (big + readable — a flinch is a BIG deal
// in a soulslike); heavy is the long wide-open stagger.
pub const LIGHT_STUN_DUR = 0.46;
pub const HEAVY_STUN_DUR = 1.15;

pub const Vitals = struct {
    hp: f32,
    hpMax: f32,
    poise: f32,
    poiseMax: f32,
    stance: f32,
    stanceMax: f32,
    sinceHit: f32 = 1e9, // seconds since the last poise-damaging hit (gates regen)
    dead: bool = false,

    pub fn init(hpMax: f32, poiseMax: f32, stanceMax: f32) Vitals {
        return .{
            .hp = hpMax,
            .hpMax = hpMax,
            .poise = poiseMax,
            .poiseMax = poiseMax,
            .stance = stanceMax,
            .stanceMax = stanceMax,
        };
    }

    pub fn hpFrac(self: *const Vitals) f32 {
        return if (self.hpMax > 0) mathx.clampF(self.hp / self.hpMax, 0, 1) else 0;
    }
    pub fn stanceFrac(self: *const Vitals) f32 {
        return if (self.stanceMax > 0) mathx.clampF(self.stance / self.stanceMax, 0, 1) else 0;
    }

    // Regenerate the meters. Call every frame. Nothing regens until REGEN_DELAY has elapsed
    // since the last hit; HP never auto-regens (souls: HP only comes back from flasks).
    pub fn tick(self: *Vitals, dt: f32) void {
        self.sinceHit += dt;
        if (self.dead or self.sinceHit < REGEN_DELAY) return;
        self.poise = mathx.minF(self.poiseMax, self.poise + self.poiseMax / POISE_REFILL * dt);
        self.stance = mathx.minF(self.stanceMax, self.stance + self.stanceMax / STANCE_REFILL * dt);
    }

    // Apply a hit. Returns the reaction it triggers: none / light stun / heavy stun / death.
    // A killing blow returns .death (and sets `dead`); the stun tiers otherwise cascade
    // (poise empties → light; that light break — or direct stance damage — empties stance →
    // heavy). Heavy outranks light on the same hit.
    pub fn hit(self: *Vitals, h: Hit) HitResult {
        if (self.dead) return .none;
        self.hp = mathx.maxF(0, self.hp - h.dmg);
        if (self.hp <= 0) {
            self.dead = true;
            return .death;
        }
        self.sinceHit = 0;
        // Direct stance damage lands regardless (heavy attacks chip it every hit).
        self.stance -= h.stance;
        // Poise chip → light break on empty (poise resets, and the break chips stance).
        var light = false;
        self.poise -= h.poise;
        if (self.poise <= 0) {
            self.poise = self.poiseMax;
            self.stance -= LIGHT_BREAK_STANCE * self.stanceMax;
            light = true;
        }
        if (self.stance <= 0) {
            self.stance = self.stanceMax;
            return .heavy;
        }
        return if (light) .light else .none;
    }
};

// ── invariants under test (pure logic) ──────────────────────────────────────────────────
test "a small hit chips poise without a stun" {
    var v = Vitals.init(100, 20, 40);
    try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 5, .poise = 8 }));
    try std.testing.expectApproxEqAbs(@as(f32, 95), v.hp, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 12), v.poise, 1e-5);
}

test "emptying poise triggers a light stun and resets poise" {
    var v = Vitals.init(100, 20, 100); // big stance so it won't cascade to heavy
    _ = v.hit(.{ .poise = 12 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 12 })); // 8 left, -12 → break
    try std.testing.expectApproxEqAbs(@as(f32, 20), v.poise, 1e-5); // poise reset to full
    try std.testing.expect(v.stance < v.stanceMax); // the light break chipped stance
}

test "enough light breaks cascade into a heavy stun (keep pressure on)" {
    var v = Vitals.init(100, 10, 20); // low poise + low stance = a frog; breaks fast
    var heavies: u32 = 0;
    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        // Each pair of hits breaks poise once (10 poise, -6 each). No tick() between hits,
        // so stance never regens — sustained pressure reaches the heavy.
        if (v.hit(.{ .poise = 6 }) == .heavy) heavies += 1;
    }
    try std.testing.expect(heavies >= 1);
}

test "a heavy attack's direct stance damage reaches the heavy faster" {
    var v = Vitals.init(100, 50, 30); // high poise (no light breaks), low stance
    _ = v.hit(.{ .poise = 1, .stance = 20 });
    try std.testing.expectEqual(HitResult.heavy, v.hit(.{ .poise = 1, .stance = 20 })); // 10 left, -20
}

test "lethal damage returns death and latches dead" {
    var v = Vitals.init(30, 20, 40);
    try std.testing.expectEqual(HitResult.death, v.hit(.{ .dmg = 40, .poise = 99 }));
    try std.testing.expect(v.dead);
    try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 40 })); // no reaction once dead
}

test "regen waits out the delay, then refills; HP never regens" {
    var v = Vitals.init(100, 20, 40);
    _ = v.hit(.{ .dmg = 10, .poise = 15 });
    v.tick(0.5); // inside REGEN_DELAY — no refill yet
    try std.testing.expectApproxEqAbs(@as(f32, 5), v.poise, 1e-5);
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) v.tick(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(v.poiseMax, v.poise, 1e-3); // poise back to full
    try std.testing.expectApproxEqAbs(@as(f32, 90), v.hp, 1e-5); // HP stays where it was
}
