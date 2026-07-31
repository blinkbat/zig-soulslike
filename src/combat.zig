const std = @import("std");
const mathx = @import("mathx.zig");

// ── COMBAT VITALS: HP + the two-tier ELDEN RING stagger model ───────────────────────────
// Every character embeds one. Both meters RESET on the break they cause (docs/ELDEN_RING.md):
//   POISE  — flinch resistance → LIGHT STUN. Regens, so lights only interrupt if landed fast
//            enough. Frogs get LOW poise.
//   STANCE — chipped by each light break and directly by heavies → HEAVY STUN. Regens SLOWER, so
//            the heavy demands sustained PRESSURE. (ER's stance break, minus the riposte.)
// Pure logic. Stun ANIMATIONS live in each character; this only decides WHAT a hit triggers.

pub const StunKind = enum { none, light, heavy };

// What the victim reacts to THIS frame.
pub const HitResult = enum { none, light, heavy, death };

// One landed blow, as plain data (attacker/victim stay decoupled). `stance` is DIRECT stance damage:
// heavies set it to break stance faster, lights leave it 0 and lean on the light-break chip.
pub const Hit = struct {
    dmg: f32 = 0,
    poise: f32 = 0,
    stance: f32 = 0,
};

// ── tuning ──────────────────────────────────────────────────────────────────────────────
// THE TWO SIDES ARE TUNED SEPARATELY (owner's call): a stagger you INFLICT is a punish window you
// must be able to walk into, one you SUFFER is time taken off the player. Foe numbers sit beside the
// hero's so the gap is visible.
const REGEN_DELAY = 0.8; // seconds after the last hit before the HERO's meters refill
const POISE_REFILL = 1.3; // seconds to refill poise from empty
const STANCE_REFILL = 4.6; // …stance slower — the "keep pressure on" meter
const LIGHT_BREAK_STANCE = 0.40; // fraction of max stance one LIGHT break chips off
// Chip damage must PERSIST, or a foe recovered before your next swing can only be staggered by a
// burst and every fight collapses into "land two fast or don't bother".
const FOE_REGEN_DELAY = 2.2;
const FOE_REGEN_RATE = 0.45;
// Stun durations. The foe's are what a stance break is FOR — long enough to close and take a free
// swing, or breaking it bought nothing but a noise.
pub const LIGHT_STUN_DUR = 0.46;
pub const HEAVY_STUN_DUR = 1.15;
pub const FOE_LIGHT_STUN_DUR = 0.78;
pub const FOE_HEAVY_STUN_DUR = 2.40;
// Since-last-event clocks start SATURATED, so an untouched meter is already past its gate. The value
// is `mathx`'s now: the hero rig and the archer's arrows keep the same kind of clock and were writing
// the bare literal, and one sentinel with one meaning belongs in one place.
const LONG_AGO = mathx.LONG_AGO;

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

    /// A FOE's regen schedule — slow to start, slow to fill. Every enemy builds through here; only
    /// the hero uses plain `init`.
    pub fn initFoe(hpMax: f32, poiseMax: f32, stanceMax: f32) Vitals {
        var v = init(hpMax, poiseMax, stanceMax);
        v.regenDelay = FOE_REGEN_DELAY;
        v.regenRate = FOE_REGEN_RATE;
        return v;
    }

    pub fn hpFrac(self: *const Vitals) f32 {
        return if (self.hpMax > 0) mathx.clampF(self.hp / self.hpMax, 0, 1) else 0;
    }

    /// PUT HP BACK. The kobold priest's whole reason to exist, and the first thing in the game that
    /// moves this meter UPWARD on a foe — `tick` deliberately regenerates poise and stance and never
    /// HP ("flasks only"), so a healer needs its own door.
    ///
    /// IT CANNOT RAISE THE DEAD, and that is the load-bearing line rather than a nicety: `dead` is a
    /// LATCH the whole foe standard reads (`alive`, the dissipation, `justDied`), so healing a corpse
    /// past 0 would hand back a foe with hp on the clock and `dead` still true — a thing with a health
    /// bar that cannot be hit and never finishes dying. A priest watching a friend fall has missed its
    /// window; that IS the counterplay.
    ///
    /// Returns how much it actually restored, so a caster can tell a real save from a wasted cast and
    /// only pay for the one that landed.
    pub fn heal(self: *Vitals, amt: f32) f32 {
        if (self.dead or amt <= 0) return 0;
        const before = self.hp;
        self.hp = mathx.minF(self.hpMax, self.hp + amt);
        return self.hp - before;
    }

    /// Is this one worth healing — alive, and actually missing something? What a priest picks its
    /// target by, and the same test `heal` makes, so the choice and the pour cannot disagree.
    pub fn needsHeal(self: *const Vitals, slack: f32) bool {
        return !self.dead and self.hp < self.hpMax - slack;
    }

    // Per frame. Nothing regens until `regenDelay` after the last hit; HP never does (flasks only).
    pub fn tick(self: *Vitals, dt: f32) void {
        self.sinceHit += dt;
        if (self.dead or self.sinceHit < self.regenDelay) return;
        self.poise = mathx.minF(self.poiseMax, self.poise + self.poiseMax / POISE_REFILL * self.regenRate * dt);
        self.stance = mathx.minF(self.stanceMax, self.stance + self.stanceMax / STANCE_REFILL * self.regenRate * dt);
    }

    // A killing blow latches `dead`; otherwise the tiers cascade (poise empties → light; that break
    // or direct stance damage empties stance → heavy), heavy outranking light on the same hit.
    pub fn hit(self: *Vitals, h: Hit) HitResult {
        if (self.dead) return .none;
        self.hp = mathx.maxF(0, self.hp - h.dmg);
        if (self.hp <= 0) {
            self.dead = true;
            return .death;
        }
        self.sinceHit = 0;
        self.stance -= h.stance; // direct stance damage lands regardless
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
// ER's shallow, fast-refilling pool (docs/ELDEN_RING.md §3 — these ARE its Endurance-15 numbers): a
// flat bite per action, pouring back ~4x as fast as a roll spends it, so it paces a FLURRY without
// becoming a resource you manage between fights. Deliberately NOT on `Vitals`, which every foe
// shares — a foe meter nothing reads would rot. Enemies pay for commitment in recovery frames.
pub const STAM_MAX = 105.0; // ER's Endurance-15 pool — about eight rolls from full
pub const STAM_ROLL = 12.0; // ER's flat, load-independent roll cost: the anchor for the rest
pub const STAM_LIGHT = 10.0; // R1, ER's straight-sword band
pub const STAM_HEAVY = 16.0; // R2 — ER heavies run ~1.3-1.8x their own light
pub const STAM_SPRINT = 9.0; // …per second held
const STAM_REGEN = 45.0; // …per second, once the delay is out
const STAM_DELAY = 0.55; // seconds after the last spend before it refills
/// How long the bar flags a refused action — long enough to read as deliberate, short enough that it
/// never lingers past the pool coming back.
pub const STAM_REFUSE_FLASH: f32 = 0.35;

// An empty bar locks out roll / attack / sprint (owner's call) — the genre's primary death window.
// NOT a no-time-theft violation: that law forbids taking control away DURING the player's own action,
// where this is the consequence of a choice made a second earlier, readable off a bar, and WALKING is
// never gated. It was deliberately OFF once (pure time taken off the player); switching it on was a
// combat-feel call and the owner's. Kept as a CONSTANT because it is the one switch that turns the
// whole economy off, and every gate asks `canAct`/`canSprint` rather than the pool.
pub const STAM_LOCKOUT = true;

/// WINDED: run the pool ALL THE WAY OUT and the sprint stays denied until the bar is back to this
/// fraction of full (owner's call). Without it, sprint on an empty bar is a stutter — the first
/// milligram of regen buys a frame of running that empties it again, so a spent player mashing Shift
/// travels at a walk anyway while the bar strobes at zero. A latch that has to be paid back to half
/// makes running dry a decision with a cost you can see, and the cost is the thing that makes the
/// sprint worth spending in the first place.
///
/// SPRINT ONLY. Roll and attack keep the PANIC rule (`canAct` — any stamina above zero), because
/// deleting the panic roll is exactly what that rule exists to prevent.
pub const STAM_WIND_CLEAR: f32 = 0.5;

pub const Stamina = struct {
    cur: f32 = STAM_MAX,
    max: f32 = STAM_MAX,
    sinceSpend: f32 = LONG_AGO, // gates the refill delay
    /// Latched the moment the pool hits 0, held until it has refilled to `STAM_WIND_CLEAR`. A LATCH
    /// and not a `cur == 0` test, which is the whole point: the denial has to outlive the emptiness.
    winded: bool = false,

    pub fn frac(self: *const Stamina) f32 {
        return if (self.max > 0) mathx.clampF(self.cur / self.max, 0, 1) else 0;
    }

    /// Can a committed action START? Not "can you pay for it" but "have you got ANY left": a roll costs
    /// 12 and you may take it on 1, emptying the bar and locking yourself out after. That asymmetry is
    /// the PANIC ROLL, the genre's most important move — gating on `cur >= cost` turns the bottom tenth
    /// of the bar into something that looks like stamina and behaves like nothing.
    pub fn canAct(self: *const Stamina) bool {
        return !STAM_LOCKOUT or self.cur > 0;
    }

    /// Charge a one-off action. Floors at 0 — a committed action is never refunded or cut short.
    pub fn spend(self: *Stamina, cost: f32) void {
        self.cur = mathx.maxF(0, self.cur - cost);
        self.sinceSpend = 0;
        self.settleWind();
    }

    /// A sprint is asked separately from `canAct` for two reasons: it is CONTINUOUS, so it must stop
    /// the instant the bar empties (the caller drops the hero to a WALK, never freezes him), and it is
    /// the one action the WINDED latch gates.
    pub fn canSprint(self: *const Stamina) bool {
        return self.canAct() and (!STAM_LOCKOUT or !self.winded);
    }

    /// Per frame. `sprinting` bleeds continuously; `committed` (mid-swing / mid-roll) only PAUSES the
    /// refill, ER-style. Neither ever touches the player's input.
    pub fn tick(self: *Stamina, dt: f32, sprinting: bool, committed: bool) void {
        if (sprinting) {
            self.cur = mathx.maxF(0, self.cur - STAM_SPRINT * dt);
            self.sinceSpend = 0;
        } else {
            self.sinceSpend += dt;
            if (!committed and self.sinceSpend >= STAM_DELAY) {
                self.cur = mathx.minF(self.max, self.cur + STAM_REGEN * dt);
            }
        }
        self.settleWind();
    }

    /// The fill the bar owes before the sprint comes back, as a fraction, or 0 when it owes nothing.
    /// The HUD's only question — it draws the mark, it does not know the rule.
    pub fn windedTo(self: *const Stamina) f32 {
        return if (self.canSprint()) 0 else STAM_WIND_CLEAR;
    }

    /// The winded latch, set and cleared in ONE place and called from every path that moves `cur`. Two
    /// copies of "did that empty me?" is how the drain from a sprint and the drain from a roll end up
    /// disagreeing about whether the player is spent.
    fn settleWind(self: *Stamina) void {
        if (self.cur <= 0) {
            self.winded = true;
        } else if (self.winded and self.cur >= STAM_WIND_CLEAR * self.max) {
            self.winded = false;
        }
    }

    pub fn reset(self: *Stamina) void {
        self.cur = self.max;
        self.sinceSpend = LONG_AGO;
        self.winded = false;
    }
};

// ── FOCUS (FP): the hero's alone, like Stamina ──────────────────────────────────────────
// ER's blue bar. NOTHING SPENDS IT YET — there are no spells or skills — so it sits full, exactly
// as it does in a build with no catalyst equipped. It is a real meter rather than the HUD's old
// hardcoded 1.0 for one reason: the Cerulean flask has to pour into SOMETHING, and a flask whose
// target is a literal cannot be tested, tuned, or seen to work.
pub const FP_MAX = 60.0;

pub const Focus = struct {
    cur: f32 = FP_MAX,
    max: f32 = FP_MAX,

    pub fn frac(self: *const Focus) f32 {
        return if (self.max > 0) mathx.clampF(self.cur / self.max, 0, 1) else 0;
    }
    /// Is there room for a pour? Asked BEFORE the charge is spent — a flask whose restore would be
    /// a no-op must be refused at the press, not discovered a second later when the liquid lands
    /// and the charge is already gone (see `hero.startDrink`).
    pub fn canTake(self: *const Focus) bool {
        return self.cur < self.max - 1e-3;
    }
    /// Returns whether it actually took any. The same test `canTake` makes, kept here so the pour
    /// can never disagree with the gate that let it through.
    pub fn restore(self: *Focus, amt: f32) bool {
        if (!self.canTake()) return false;
        self.cur = minF(self.max, self.cur + amt);
        return true;
    }
    pub fn reset(self: *Focus) void {
        self.cur = self.max;
    }
};

// ── FLASKS (Elden Ring's, both of them) ─────────────────────────────────────────────────
// The Flask of CRIMSON Tears restores HP, the Flask of CERULEAN Tears restores FP, they share the
// quick-item slot, and D-pad down cycles which one is up. Charges refill at the grace — here, on
// the respawn, which is the same event.
//
// THE DRINK IS COMMITTED, and that is the whole design. A heal you can take for free mid-combo is
// not a resource, it is a button; ER makes you find a gap, and the gap is what turns "I am hurt"
// into a decision. So it takes FLASK_DRINK_DUR of standing still, the restore lands PART WAY IN
// (raise the flask, then drink — a heal that fires on frame one lets you cancel out of your own
// commitment), and a blow that staggers you interrupts it AND spends the charge, ER-style.
//
// (ER lets you walk while drinking. This one plants you, because walking-and-drinking needs the
// flask arm blended onto the live walk and the hero has no upper-body layer yet — see poseDrink.)
pub const FlaskKind = enum { crimson, cerulean };

pub const FLASK_CRIMSON: u8 = 4; // charges of each at a fresh grace…
pub const FLASK_CERULEAN: u8 = 2; // …fewer blue, since there is far less to spend it on
pub const FLASK_HP_FRAC: f32 = 0.45; // fraction of the MAX restored — ER's low-upgrade Crimson
pub const FLASK_FP_FRAC: f32 = 0.50;
pub const FLASK_DRINK_DUR: f32 = 1.05; // the committed window
pub const FLASK_POUR_AT: f32 = 0.42; // …and where inside it the restore actually lands

pub const Flasks = struct {
    crimson: u8 = FLASK_CRIMSON,
    cerulean: u8 = FLASK_CERULEAN,
    sel: FlaskKind = .crimson,

    pub fn charges(self: *const Flasks, k: FlaskKind) u8 {
        return switch (k) {
            .crimson => self.crimson,
            .cerulean => self.cerulean,
        };
    }
    /// Charges of the one currently in the slot.
    pub fn ready(self: *const Flasks) u8 {
        return self.charges(self.sel);
    }
    /// D-pad down. Cycles regardless of whether the other one has anything left — an empty flask
    /// you can still SEE in the slot is how you know to go and rest, and skipping it would make
    /// the cycle silently do nothing when you are dry.
    pub fn cycle(self: *Flasks) void {
        self.sel = switch (self.sel) {
            .crimson => .cerulean,
            .cerulean => .crimson,
        };
    }
    /// Spend one charge of the selected flask. Callers gate on this: false = nothing was drunk.
    pub fn take(self: *Flasks) bool {
        switch (self.sel) {
            .crimson => {
                if (self.crimson == 0) return false;
                self.crimson -= 1;
            },
            .cerulean => {
                if (self.cerulean == 0) return false;
                self.cerulean -= 1;
            },
        }
        return true;
    }
    /// Back to full — resting at the grace, which for this build is the respawn.
    pub fn refill(self: *Flasks) void {
        self.crimson = FLASK_CRIMSON;
        self.cerulean = FLASK_CERULEAN;
    }
};

// ── RUNES: the run's currency — the HERO'S ALONE, like Stamina ───────────────────────────
// Souls / blood echoes / runes: same mechanic, ER's name (ER is the north star). A kill pays out the
// instant it lands but the COUNTER never jumps — it ROLLS up over a beat, which is the difference
// between a readout and a reward. Pure logic, so the roll is testable without a HUD to look at.
pub const RUNE_ROLL_RATE = 7.0; // …of the remaining gap, per second — a big haul counts up fast
pub const RUNE_ROLL_FLOOR = 26.0; // …but never slower, or the last few runes crawl for a second and a
//   half after the number has visually stopped moving.

pub const Runes = struct {
    total: u32 = 0,
    shown: f32 = 0, // what the HUD prints — chases `total`

    pub fn gain(self: *Runes, n: u32) void {
        self.total += n;
    }

    /// Per frame. EXPONENTIAL with a floor: proportional so a 900-rune giant counts up fast, floored
    /// so a 60-rune toad doesn't take longer to tally than the fight did.
    pub fn tick(self: *Runes, dt: f32) void {
        const goal: f32 = @floatFromInt(self.total);
        if (self.shown >= goal) {
            self.shown = goal; // never DRIFT above it, or the display shows a rune you don't have
            return;
        }
        self.shown = minF(goal, self.shown + maxF((goal - self.shown) * RUNE_ROLL_RATE, RUNE_ROLL_FLOOR) * dt);
    }

    /// What to print. FLOORED, not rounded: a counter mid-roll must never show more than is banked.
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
    // Each pair breaks poise once; no tick() between them, so stance never regens — sustained
    // pressure reaches the heavy.
    while (i < 12) : (i += 1) {
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

test "a healer puts HP back, tops out, and CANNOT raise the dead" {
    // The kobold priest's mechanic. The dead check is the one that matters: `dead` is a latch every
    // part of the foe standard reads, so healing a corpse would produce a thing with health and no
    // way to die.
    var v = Vitals.initFoe(100, 20, 40);
    _ = v.hit(.{ .dmg = 60 });
    try std.testing.expectApproxEqAbs(@as(f32, 40), v.hp, 1e-4);
    try std.testing.expect(v.needsHeal(1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 25), v.heal(25), 1e-4); // …reports what it restored
    try std.testing.expectApproxEqAbs(@as(f32, 65), v.hp, 1e-4);
    // Tops out rather than overflowing, and reports only the part that landed — so a caster can tell
    // a real save from a wasted cast.
    try std.testing.expectApproxEqAbs(@as(f32, 35), v.heal(999), 1e-4);
    try std.testing.expectApproxEqAbs(v.hpMax, v.hp, 1e-4);
    try std.testing.expect(!v.needsHeal(1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.heal(50), 1e-4); // nothing missing → nothing poured
    // …and a corpse stays a corpse.
    var d = Vitals.initFoe(100, 20, 40);
    try std.testing.expectEqual(HitResult.death, d.hit(.{ .dmg = 200 }));
    try std.testing.expectApproxEqAbs(@as(f32, 0), d.heal(80), 1e-4);
    try std.testing.expect(d.dead and d.hp <= 0);
    try std.testing.expect(!d.needsHeal(1.0)); // never a target, either
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
    // The point of the split: two seconds on, the hero is fully recovered and the foe has not started
    // refilling at all, so pressure actually accrues.
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
    // A break must be worth causing — long enough to walk in on. The hero's stays short: the FEEL
    // RULES spend as little of the player's time as they can.
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

test "running the bar dry costs the sprint until it is back to half" {
    var s = Stamina{};
    // SPRINT it all the way out, through the continuous drain rather than by spending a lump.
    var t: f32 = 0;
    while (s.cur > 0) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, true, false);
    try std.testing.expect(s.winded);
    try std.testing.expect(!s.canSprint());
    // A sliver back is enough to ROLL again — the panic roll is untouched by this — and not nearly
    // enough to run on, which is the whole difference the latch makes.
    var u: f32 = 0;
    while (u < STAM_DELAY + 0.10) : (u += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(s.cur > 0 and s.cur < STAM_WIND_CLEAR * s.max);
    try std.testing.expect(s.canAct());
    try std.testing.expect(!s.canSprint());
    try std.testing.expectApproxEqAbs(STAM_WIND_CLEAR, s.windedTo(), 1e-6);
    // …and it clears at the threshold, not one frame before it.
    while (s.cur < STAM_WIND_CLEAR * s.max) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(!s.winded);
    try std.testing.expect(s.canSprint());
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.windedTo(), 1e-6);
    // A RESPAWN is not winded, whatever the last life ended on.
    s.cur = 0;
    s.settleWind();
    try std.testing.expect(s.winded);
    s.reset();
    try std.testing.expect(!s.winded and s.canSprint());
}

test "THE PANIC ROLL: a sliver of stamina still buys a full-cost action" {
    // The genre's defining asymmetry: act on ANY stamina above zero, pay what you have, be locked out
    // after. Gating on `cur >= cost` would turn the bottom tenth of the bar into decoration.
    var s = Stamina{};
    s.cur = 1.0;
    try std.testing.expect(s.canAct());
    s.spend(STAM_ROLL); // costs 12, he has 1 — the roll happens anyway
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    try std.testing.expect(!s.canAct()); // and now he pays for it
}

test "a roll chain costs the sum of its rolls — the refill cannot pay for it" {
    // Committed actions pause the refill, so three rolls back to back cost 3x — not 3x minus whatever
    // leaked back in between them.
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
    // Why stamina paces a flurry instead of gating a fight: the heaviest single spend is back inside
    // half a second of standing still, once the delay is out.
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
    // Never more than is banked, at ANY point in the roll: a counter that overshoots and settles back
    // is worse than one that snaps.
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
    // A second kill mid-tally adds to the GOAL rather than resetting the roll — otherwise a flurry
    // leaves the counter permanently behind.
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

test "flasks: a drink spends exactly one charge, and an empty flask refuses" {
    var f = Flasks{};
    try std.testing.expectEqual(FLASK_CRIMSON, f.ready());
    var i: u8 = 0;
    while (i < FLASK_CRIMSON) : (i += 1) try std.testing.expect(f.take());
    try std.testing.expectEqual(@as(u8, 0), f.ready());
    try std.testing.expect(!f.take()); // dry — and it must SAY so rather than heal for free
    // …and draining one leaves the other untouched: they are separate flasks, not one pool.
    f.cycle();
    try std.testing.expectEqual(FlaskKind.cerulean, f.sel);
    try std.testing.expectEqual(FLASK_CERULEAN, f.ready());
    try std.testing.expect(f.take());
    f.refill();
    try std.testing.expectEqual(FLASK_CERULEAN, f.ready());
    f.cycle();
    try std.testing.expectEqual(FLASK_CRIMSON, f.ready());
}

test "flasks: the cycle still moves when the other one is empty" {
    // Otherwise being dry on blue would silently make D-pad down do nothing, and an input that
    // does nothing with no feedback is the exact thing the stamina refusal flash exists to stop.
    var f = Flasks{};
    f.cerulean = 0;
    f.cycle();
    try std.testing.expectEqual(FlaskKind.cerulean, f.sel);
    try std.testing.expectEqual(@as(u8, 0), f.ready());
}

test "focus refuses a pour it cannot take, so a full bar never eats a charge" {
    // The one deliberate step away from ER: nothing spends FP in this build, so a Cerulean flask
    // that consumed a charge into a permanently-full bar would be a button that can only ever be
    // wasted. Restoring nothing reports false and the caller keeps the charge.
    var fp = Focus{};
    try std.testing.expect(!fp.restore(10));
    fp.cur = 10;
    try std.testing.expect(fp.restore(FP_MAX * FLASK_FP_FRAC));
    try std.testing.expectApproxEqAbs(@as(f32, 40), fp.cur, 1e-4);
    try std.testing.expect(fp.restore(FP_MAX)); // tops out rather than overflowing
    try std.testing.expectApproxEqAbs(FP_MAX, fp.cur, 1e-4);
}

test "the flask heals a real bite of the bar, and the pour lands inside the commitment" {
    try std.testing.expect(FLASK_HP_FRAC > 0.25 and FLASK_HP_FRAC < 0.75); // meaningful, not a full heal
    try std.testing.expect(FLASK_POUR_AT > 0.2 and FLASK_POUR_AT < 1.0); // …and you pay before you drink
}

test "the lockout switch is what decides whether an empty pool bites" {
    var s = Stamina{};
    s.spend(STAM_MAX); // bone dry
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    // Against the CONSTANT, not `false`, so flipping STAM_LOCKOUT off stays a one-line change instead
    // of a one-line change plus a failing test.
    try std.testing.expectEqual(!STAM_LOCKOUT, s.canAct());
}
