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

// ── tuning ──────────────────────────────────────────────────────────────────────────────
// THE TWO SIDES ARE TUNED SEPARATELY (owner's call). A stagger you INFLICT is a punish window
// you must be able to walk into and use; a stagger you SUFFER is time taken off the player,
// which this game spends as little of as it can (FEEL RULES). So the foe numbers are the
// generous ones, side by side with the hero's where you can see the gap.
const REGEN_DELAY = 0.8; // seconds after the last hit before the HERO's meters start refilling
const POISE_REFILL = 1.3; // seconds to refill poise from empty (once regen kicks in)
const STANCE_REFILL = 4.6; // …stance refills slower — the "keep pressure on" meter
const LIGHT_BREAK_STANCE = 0.40; // fraction of max stance a single LIGHT break chips off
// A foe whose poise is back before your next swing can only be staggered by a burst, and every
// fight collapses into "land two fast or don't bother". Chip damage has to PERSIST.
const FOE_REGEN_DELAY = 2.2;
const FOE_REGEN_RATE = 0.45;
// Stun durations (seconds). Light is a sharp flinch (BIG and readable); heavy is the long
// wide-open stagger. The foe durations are what a stance break is FOR — long enough to close
// and take a free swing, or breaking it bought nothing but a noise.
pub const LIGHT_STUN_DUR = 0.46;
pub const HEAVY_STUN_DUR = 1.15;
pub const FOE_LIGHT_STUN_DUR = 0.78;
pub const FOE_HEAVY_STUN_DUR = 2.40;
// "Longer ago than any delay here" — the since-last-event clocks start saturated so a meter
// that has never been touched is already past its gate. Big enough that adding a frame's dt
// leaves it unchanged in f32, so it never creeps or overflows.
const LONG_AGO = 1e9;

pub const Vitals = struct {
    hp: f32,
    hpMax: f32,
    poise: f32,
    poiseMax: f32,
    stance: f32,
    stanceMax: f32,
    sinceHit: f32 = LONG_AGO, // seconds since the last poise-damaging hit (gates regen)
    dead: bool = false,
    regenDelay: f32 = REGEN_DELAY, // …how long that gate holds
    regenRate: f32 = 1.0, // …and the multiplier on the refill speed once it opens

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

    /// The same vitals on a FOE's regen schedule — slow to start, slow to fill. Every enemy
    /// builds through here; only the hero uses the plain `init`.
    pub fn initFoe(hpMax: f32, poiseMax: f32, stanceMax: f32) Vitals {
        var v = init(hpMax, poiseMax, stanceMax);
        v.regenDelay = FOE_REGEN_DELAY;
        v.regenRate = FOE_REGEN_RATE;
        return v;
    }

    pub fn hpFrac(self: *const Vitals) f32 {
        return if (self.hpMax > 0) mathx.clampF(self.hp / self.hpMax, 0, 1) else 0;
    }

    // Regenerate the meters; call every frame. Nothing regens until `regenDelay` after the
    // last hit; HP never auto-regens (flasks only).
    pub fn tick(self: *Vitals, dt: f32) void {
        self.sinceHit += dt;
        if (self.dead or self.sinceHit < self.regenDelay) return;
        self.poise = mathx.minF(self.poiseMax, self.poise + self.poiseMax / POISE_REFILL * self.regenRate * dt);
        self.stance = mathx.minF(self.stanceMax, self.stance + self.stanceMax / STANCE_REFILL * self.regenRate * dt);
    }

    // Apply a hit; returns the reaction: none / light / heavy / death. Killing blow latches
    // `dead`; otherwise the tiers cascade (poise empties → light; that break or direct stance
    // damage empties stance → heavy), heavy outranking light on the same hit.
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

// ── STAMINA: the hero's alone ───────────────────────────────────────────────────────────
// Elden Ring's shallow, fast-refilling pool (docs/ELDEN_RING.md §3 — these ARE its numbers,
// at Endurance 15). Every committed action takes a flat bite and it pours back roughly four
// times as fast as a roll spends it, so it paces a FLURRY without ever becoming a resource
// you manage between fights.
//
// Deliberately NOT on `Vitals`: that struct is shared with every foe, and an enemy stamina
// meter nothing reads and nothing draws is a field that rots. Enemies pay for commitment in
// recovery frames instead.
pub const STAM_MAX = 105.0; // ER's Endurance-15 pool — about eight rolls from full
pub const STAM_ROLL = 12.0; // ER's flat, load-independent roll cost: the anchor for the rest
pub const STAM_LIGHT = 10.0; // R1, ER's straight-sword band
pub const STAM_HEAVY = 16.0; // R2 — ER heavies run ~1.3-1.8x their own light
pub const STAM_SPRINT = 9.0; // …per second held
const STAM_REGEN = 45.0; // …per second, once the delay is out
const STAM_DELAY = 0.55; // seconds after the last spend before it refills
/// How long the stamina bar flags a refused action. Long enough to read as deliberate, short
/// enough that it never lingers past the moment the pool comes back.
pub const STAM_REFUSE_FLASH: f32 = 0.35;

// LOCKOUT IS ON (owner's call): an empty bar means you cannot roll, attack or sprint. This is
// the genre's primary death window and the only thing that makes the meter a real decision —
// without it the bar is a readout of nothing.
//
// It does NOT violate the no-time-theft law. What that law forbids is taking control away from
// the player during THEIR action (hitstop, dilation, input lag); a stamina lockout is the
// consequence of a choice they made a second ago, it is signalled by a bar they can read, and
// WALKING is never gated — you can always move, turn and back off on an empty meter. The old
// note below is kept because the reasoning still matters:
//
// (Previously OFF, on the grounds that it is pure time taken off the player, which the
// FEEL RULES spend as little of as they can. Switching it on was a combat-feel decision and
// the owner's to make, not a side effect of drawing the bar.)
//
// Left as a constant rather than deleted: it is the one switch that turns the whole economy
// off again, and every gate asks `canAct`/`canSprint` rather than testing the pool directly.
pub const STAM_LOCKOUT = true;

pub const Stamina = struct {
    cur: f32 = STAM_MAX,
    max: f32 = STAM_MAX,
    sinceSpend: f32 = LONG_AGO, // gates the refill delay

    pub fn frac(self: *const Stamina) f32 {
        return if (self.max > 0) mathx.clampF(self.cur / self.max, 0, 1) else 0;
    }

    /// Can a committed action START? The soulslike rule is NOT "can you pay for it" — it is
    /// "have you got ANY stamina left". A roll costs 12 and you are allowed to take it on 1,
    /// which empties the bar and locks you out afterwards.
    ///
    /// That asymmetry is load-bearing, not a rounding error: the PANIC ROLL on the last sliver
    /// of the meter is the most important move in the genre. Gating on `cur >= cost` instead
    /// silently deletes it and makes the bottom tenth of the bar dead weight — it would look
    /// like stamina and behave like nothing. Every FromSoft game since Demon's works this way.
    pub fn canAct(self: *const Stamina) bool {
        return !STAM_LOCKOUT or self.cur > 0;
    }

    /// Charge a one-off action (a roll, a swing). Floors at 0 — an action already committed
    /// is never refunded or cut short partway by running the pool dry.
    pub fn spend(self: *Stamina, cost: f32) void {
        self.cur = mathx.maxF(0, self.cur - cost);
        self.sinceSpend = 0;
    }

    /// Per frame. `sprinting` bleeds continuously; `committed` (mid-swing) only PAUSES the
    /// refill, ER-style. Neither the delay nor the pause ever touches the player's input.
    /// Can a sprint be STARTED or SUSTAINED? Same rule as `canAct`, checked separately because
    /// a sprint is continuous: it has to stop the instant the bar empties, and the caller has to
    /// drop the hero to a walk rather than freeze him.
    pub fn canSprint(self: *const Stamina) bool {
        return self.canAct();
    }

    pub fn tick(self: *Stamina, dt: f32, sprinting: bool, committed: bool) void {
        if (sprinting) {
            self.cur = mathx.maxF(0, self.cur - STAM_SPRINT * dt);
            self.sinceSpend = 0;
            return;
        }
        self.sinceSpend += dt;
        if (committed or self.sinceSpend < STAM_DELAY) return;
        self.cur = mathx.minF(self.max, self.cur + STAM_REGEN * dt);
    }

    pub fn reset(self: *Stamina) void {
        self.cur = self.max;
        self.sinceSpend = LONG_AGO;
    }
};

// ── RUNES: the run's currency — the HERO'S ALONE, like Stamina ───────────────────────────
// The souls counter, and it is called RUNES because this game's north star is Elden Ring (see
// AGENTS.md) — the HUD, the pad layout and the stagger model all follow ER, so the currency does
// too. Souls / blood echoes / runes: same mechanic, ER's name.
//
// A kill pays out the instant it lands, but the COUNTER never jumps: it ROLLS up to the new total
// over a beat. That is the whole difference between a readout and a reward, and it is why every
// game in the genre does it. Pure logic, here with the rest of it, so the roll is unit-testable
// without a HUD to look at.
pub const RUNE_ROLL_RATE = 7.0; // …of the remaining gap, per second — a big haul counts up fast
pub const RUNE_ROLL_FLOOR = 26.0; // …but never slower than this per second, or the last few runes
//   crawl for a second and a half after the number has visually stopped moving.

pub const Runes = struct {
    total: u32 = 0,
    shown: f32 = 0, // what the HUD prints — chases `total`

    pub fn gain(self: *Runes, n: u32) void {
        self.total += n;
    }

    /// Per frame. EXPONENTIAL with a floor: proportional so a nine-hundred-rune giant counts up
    /// fast, floored so a sixty-rune toad doesn't take longer to tally than the fight did.
    pub fn tick(self: *Runes, dt: f32) void {
        const goal: f32 = @floatFromInt(self.total);
        if (self.shown >= goal) {
            self.shown = goal; // …and never DRIFT above it, or the display shows a rune you don't have
            return;
        }
        self.shown = minF(goal, self.shown + maxF((goal - self.shown) * RUNE_ROLL_RATE, RUNE_ROLL_FLOOR) * dt);
    }

    /// What to print. FLOORED, not rounded: a counter mid-roll must never show a number above the
    /// runes actually banked.
    pub fn display(self: *const Runes) u32 {
        return @intFromFloat(@floor(maxF(self.shown, 0)));
    }
};

const minF = mathx.minF;
const maxF = mathx.maxF;

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

test "a foe's chip damage PERSISTS far longer than the hero's" {
    // The whole point of the split: two seconds after a hit the hero is fully recovered and the
    // foe has not started refilling at all, so pressure on a foe actually accrues.
    var hero = Vitals.init(100, 20, 40);
    var foeV = Vitals.initFoe(100, 20, 40);
    _ = hero.hit(.{ .poise = 15 });
    _ = foeV.hit(.{ .poise = 15 });
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) {
        hero.tick(1.0 / 60.0);
        foeV.tick(1.0 / 60.0);
    }
    try std.testing.expectApproxEqAbs(hero.poiseMax, hero.poise, 1e-3); // hero is back
    try std.testing.expectApproxEqAbs(@as(f32, 5), foeV.poise, 1e-3); // the foe is still chipped
}

test "the punish window a foe gives you outlasts the one you give it" {
    // A stance break must be worth causing: long enough to walk in on. The hero's own stays
    // short on purpose — the FEEL RULES spend as little of the player's time as they can.
    try std.testing.expect(FOE_HEAVY_STUN_DUR > 2.0 * HEAVY_STUN_DUR);
    try std.testing.expect(FOE_LIGHT_STUN_DUR > LIGHT_STUN_DUR);
    try std.testing.expect(FOE_REGEN_DELAY > REGEN_DELAY and FOE_REGEN_RATE < 1.0);
}

test "a roll costs its flat bite and the refill waits out the delay" {
    var s = Stamina{};
    s.spend(STAM_ROLL);
    try std.testing.expectApproxEqAbs(STAM_MAX - STAM_ROLL, s.cur, 1e-4);
    s.tick(0.5, false, false); // still inside STAM_DELAY — nothing back yet
    try std.testing.expectApproxEqAbs(STAM_MAX - STAM_ROLL, s.cur, 1e-4);
    var t: f32 = 0;
    while (t < 1.2) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expectApproxEqAbs(STAM_MAX, s.cur, 1e-3);
}

test "an empty pool locks out rolling, attacking and sprinting" {
    var s = Stamina{};
    try std.testing.expect(s.canAct());
    try std.testing.expect(s.canSprint());
    s.spend(STAM_MAX);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    try std.testing.expect(!s.canAct()); // no roll, no swing…
    try std.testing.expect(!s.canSprint()); // …and no sprint
    // …until the delay is out and something has come back.
    var t: f32 = 0;
    while (t < STAM_DELAY + 0.05) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(s.canAct());
}

test "THE PANIC ROLL: a sliver of stamina still buys a full-cost action" {
    // The genre's defining asymmetry. You may act on ANY stamina above zero, pay what you have,
    // and be locked out afterwards. Gating on `cur >= cost` would delete this and quietly turn
    // the bottom tenth of the bar into decoration.
    var s = Stamina{};
    s.cur = 1.0;
    try std.testing.expect(s.canAct());
    s.spend(STAM_ROLL); // costs 12, he has 1 — the roll happens anyway
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    try std.testing.expect(!s.canAct()); // and now he pays for it
}

test "a roll chain costs the sum of its rolls — the refill cannot pay for it" {
    // Committed actions pause the refill (ER pauses while attacking/rolling/sprinting), so
    // chaining three rolls back to back must cost 3x, not 3x minus whatever leaked back in.
    var s = Stamina{};
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        s.spend(STAM_ROLL);
        var t: f32 = 0;
        while (t < 0.70) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, true); // committed: mid-roll
    }
    try std.testing.expectApproxEqAbs(STAM_MAX - 3 * STAM_ROLL, s.cur, 1e-3);
}

test "sprinting bleeds the pool and holds the refill off" {
    var s = Stamina{};
    var t: f32 = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, true, false);
    try std.testing.expectApproxEqAbs(STAM_MAX - STAM_SPRINT, s.cur, 0.2); // ~a second's bleed
    s.tick(1.0 / 60.0, false, false); // the very next frame is still inside the delay
    try std.testing.expect(s.cur < STAM_MAX - STAM_SPRINT + 0.2);
}

test "a swing PAUSES the refill rather than draining it" {
    var s = Stamina{};
    s.spend(STAM_HEAVY);
    const after = s.cur;
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, true); // committed the whole time
    try std.testing.expectApproxEqAbs(after, s.cur, 1e-4); // paused, not bled
}

test "the pool refills far faster than any one action drains it" {
    // The whole reason stamina paces a flurry instead of gating a fight: the heaviest single
    // spend is back inside half a second of standing still, once the delay is out.
    try std.testing.expect(STAM_REGEN > 2.0 * STAM_HEAVY);
    try std.testing.expect(STAM_HEAVY > STAM_LIGHT and STAM_LIGHT < STAM_ROLL);
    try std.testing.expect(STAM_MAX / STAM_ROLL > 6.0); // ER's "~8 rolls from full"
}

test "runes roll UP to a kill's payout and never overshoot it" {
    var r = Runes{};
    r.gain(900); // an ogre
    try std.testing.expectEqual(@as(u32, 900), r.total);
    try std.testing.expectEqual(@as(u32, 0), r.display()); // …but the counter has not moved yet
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 900), r.display()); // …and it lands EXACTLY on the total
    // It must never print more than is banked, at any point in the roll — a counter that overshoots
    // and settles back is worse than one that snaps.
    var r2 = Runes{};
    r2.gain(60);
    t = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) {
        r2.tick(1.0 / 60.0);
        try std.testing.expect(r2.display() <= r2.total);
    }
    try std.testing.expectEqual(@as(u32, 60), r2.display());
}

test "a rune payout mid-roll retargets instead of restarting" {
    // Killing a second foe while the first one's runes are still counting up must add to the goal,
    // not reset the roll — otherwise a flurry of kills leaves the counter permanently behind.
    var r = Runes{};
    r.gain(120);
    var t: f32 = 0;
    while (t < 0.15) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0);
    const mid = r.display();
    try std.testing.expect(mid > 0 and mid < 120);
    r.gain(120);
    try std.testing.expectEqual(@as(u32, 240), r.total);
    try std.testing.expect(r.display() >= mid); // never goes BACKWARDS on a fresh kill
    t = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 240), r.display());
}

test "the lockout switch is what decides whether an empty pool bites" {
    var s = Stamina{};
    s.spend(STAM_MAX); // bone dry
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    // Written against the constant rather than against `false`, so flipping STAM_LOCKOUT back
    // off stays a one-line change instead of a one-line change plus a failing test.
    try std.testing.expectEqual(!STAM_LOCKOUT, s.canAct());
}
