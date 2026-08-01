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

/// WHAT BECAME OF A BLOW aimed at the hero, which is not the same question as what his vitals did
/// with it — a hit can be rolled through, or caught on the shield, and neither reaches `Vitals.hit`.
/// Returned by `hero.takeHit` because the CALLER has to know: the felt beat for a blocked blow is a
/// different rumble, a different shake and a different voice from one that landed, and before this
/// existed game.zig played the hurt grunt for every blow a foe reported — i-framed ones included.
pub const HitOutcome = enum { ignored, taken, blocked, guardBroken };

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

// ── NOBODY IS POISE-DAMAGED WHILE ALREADY REELING (owner's call) ─────────────────────────
// A reaction is a beat you are already paying for; chipping poise through it means the blow that
// staggered you also sets up the next stagger, and a warband or a chained R1 can hold either side in
// one unbroken flinch. So for as long as a stun runs, incoming poise is DROPPED — and when it ends,
// poise goes back to FULL, both tiers. Two consequences worth stating because they are the mechanic:
//
//   - HP AND DIRECT STANCE DAMAGE STILL LAND. The window you opened is still a punish window: land a
//     heavy inside a light stun and its stance damage counts, exactly as before. What you cannot do
//     is re-flinch something that is already flinching.
//   - THE REFILL AT THE END IS WHAT MAKES IT SYMMETRIC. A light break already reset poise, but a
//     HEAVY break resets STANCE and leaves poise wherever the blow left it — so without this, coming
//     out of the bigger reaction left you more fragile than coming out of the small one.
//
// `Vitals` owns the clock rather than reading each rig's, because `foe.strike` applies a blow through
// `hit()` knowing nothing about the creature it belongs to. The DURATIONS are the same two constants
// the rigs pose against, carried per-side by init/initFoe and pinned by a test below — one clock, two
// readers, no third number to drift.

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
    /// Seconds of stun still to run. Above zero = poise-immune (see the block above). Seeded by `hit`
    /// from the two durations below and counted down by `tick`.
    stunLeft: f32 = 0,
    lightStun: f32 = LIGHT_STUN_DUR, // …how long each tier's reaction lasts for THIS character
    heavyStun: f32 = HEAVY_STUN_DUR,

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

    /// A FOE's regen schedule — slow to start, slow to fill — and its LONGER stun windows, which are
    /// also how long its poise immunity lasts. Every enemy builds through here; only the hero uses
    /// plain `init`.
    pub fn initFoe(hpMax: f32, poiseMax: f32, stanceMax: f32) Vitals {
        var v = init(hpMax, poiseMax, stanceMax);
        v.regenDelay = FOE_REGEN_DELAY;
        v.regenRate = FOE_REGEN_RATE;
        v.lightStun = FOE_LIGHT_STUN_DUR;
        v.heavyStun = FOE_HEAVY_STUN_DUR;
        return v;
    }

    /// Is a reaction still running — and therefore poise still immune? The rigs keep their own clocks
    /// for the ANIMATION; this is the mechanical one.
    pub fn stunned(self: *const Vitals) bool {
        return self.stunLeft > 0;
    }

    /// ARM A REACTION'S IMMUNITY WINDOW. `hit` calls this for every stun IT decides, which covers every
    /// foe — they can only be staggered through a blow. The hero has one other door: a GUARD BREAK is a
    /// heavy stagger that `hit` never returned (the chip that emptied the bar was a plain damage hit),
    /// so `hero.enterStun` calls this as well. Idempotent on purpose, so pairing it with a stun the hit
    /// already armed is harmless rather than something the caller has to reason about.
    pub fn beginStun(self: *Vitals, kind: StunKind) void {
        self.stunLeft = switch (kind) {
            .none => 0,
            .light => self.lightStun,
            .heavy => self.heavyStun,
        };
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
        // THE STUN CLOCK RUNS BEFORE THE REGEN GATE, and that ordering is load-bearing: the hit that
        // started the stun also zeroed `sinceHit`, and a foe's `regenDelay` (2.2 s) is longer than
        // either of its stun windows — so behind the gate the clock would never reach zero and the
        // poise immunity would never lift.
        if (self.stunLeft > 0) {
            self.stunLeft -= dt;
            // THE REACTION IS OVER: poise back to full, whichever tier it was. This is the "recharges
            // when the stun ends" half — see the block above for why the heavy tier needs it.
            if (self.stunLeft <= 0) {
                self.stunLeft = 0;
                self.poise = self.poiseMax;
            }
        }
        if (self.dead or self.sinceHit < self.regenDelay) return;
        self.poise = mathx.minF(self.poiseMax, self.poise + self.poiseMax / POISE_REFILL * self.regenRate * dt);
        self.stance = mathx.minF(self.stanceMax, self.stance + self.stanceMax / STANCE_REFILL * self.regenRate * dt);
    }

    // A killing blow latches `dead`; otherwise the tiers cascade (poise empties → light; that break
    // or direct stance damage empties stance → heavy), heavy outranking light on the same hit.
    //
    // POISE IS IMMUNE WHILE A STUN RUNS (see the block above the struct). HP and direct STANCE damage
    // are not: a heavy landed inside a light stun still breaks stance, which is the punish window
    // doing its job.
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
        if (!self.stunned()) {
            self.poise -= h.poise;
            if (self.poise <= 0) {
                self.poise = self.poiseMax;
                self.stance -= LIGHT_BREAK_STANCE * self.stanceMax;
                light = true;
            }
        }
        if (self.stance <= 0) {
            self.stance = self.stanceMax;
            self.beginStun(.heavy); // a fresh reaction, and its immunity, from this frame
            return .heavy;
        }
        if (light) {
            self.beginStun(.light);
            return .light;
        }
        return .none;
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

// ── GUARDING: the plain Dark Souls block, and a SMALL SHIELD to do it with ───────────────
// Hold the shield up and a blow from the front is caught on it instead of on you: almost no HP,
// but it is paid for out of STAMINA, and running the bar out under a blow is a GUARD BREAK — a
// heavy stagger, wide open. No parry, no guard counter (docs/ELDEN_RING.md §3 has both; neither is
// built). That is the whole system, and it is deliberately the DS1 shape rather than ER's: block,
// pay, and either punish the gap or lose your footing.
//
// THE SHIELD IS SMALL, and every number here says so. A greatshield trades mobility for a wall you
// can stand behind; a small one buys you a beat, and what it cannot do is soak a giant. So:
//   - it does NOT reach 100% physical negation (ER's medium/greatshield rule), and the chip that
//     gets through CAN kill you, exactly as it can in DS,
//   - its STABILITY is poor, which in this model is the stamina it costs per blow, and it costs by
//     the WEIGHT OF THE BLOW: a kobold's teeth are nothing and the ogre's club breaks you in three.
// Both are one-line dials, and they are the two that decide whether guarding is a crutch.
pub const GUARD_NEGATE: f32 = 0.85; // fraction of a blocked blow's HP damage the shield eats…
pub const GUARD_STAM_FLAT: f32 = 5.0; // …stamina every blocked blow costs…
pub const GUARD_STAM_PER_DMG: f32 = 1.10; // …plus this per point of the blow's RAW damage (stability)
/// How far off his facing the shield covers, in degrees EITHER SIDE. A shield is a direction, not a
/// bubble: getting round it is the counterplay a warband already knows how to do, and it is why
/// guarding cannot answer a group the way rolling can. Wide enough not to punish a fight where the
/// camera and the foe disagree by a few degrees, nowhere near a hemisphere.
pub const GUARD_ARC: f32 = 65.0;

/// A BLOCKED BLOW STILL COSTS POISE — none of it. It costs STAMINA, and this is the whole stability
/// model: flat bite plus the weight of what hit you.
pub fn guardStamina(h: Hit) f32 {
    return GUARD_STAM_FLAT + GUARD_STAM_PER_DMG * h.dmg;
}
/// …and the CHIP: what gets past a shield that is not a wall. Kept as real damage on purpose — chip
/// you cannot die to is a number, and DS lets it kill you.
pub fn guardChip(h: Hit) f32 {
    return h.dmg * (1.0 - GUARD_NEGATE);
}

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

// ── REGEN: HP back over TIME, and the first thing in the game that is not a flask ────────
// `Vitals.tick` refills poise and stance and deliberately never HP ("flasks only"), and `heal` is an
// instant pour. This is the third shape: a slow drip you set going and then have to SURVIVE, which
// is a different decision from a flask. A flask is an answer to being hurt NOW; a drip is a bet that
// the next twenty seconds go well.
//
// MUSHROOM JERKY is the first item to use it. THE POTENCY IS NOT HERE — it rides `item.Use.regen`
// with the item it belongs to, because "how much, over how long" is what tells one edible from the
// next, and a second one reading its numbers off a constant named after the first is a bug waiting
// to be written. This file owns the MECHANISM; the item owns the dose.

pub const Regen = struct {
    left: f32 = 0, // seconds still to run
    rate: f32 = 0, // HP a second while it does

    pub fn active(self: *const Regen) bool {
        return self.left > 0;
    }
    /// Start (or RESTART) a drip of `total` HP spread over `dur`. Eating a second one refreshes
    /// rather than stacking: two overlapping drips at different rates is a thing no player can read
    /// off a bar, and the bar is the only place this is visible.
    pub fn start(self: *Regen, total: f32, dur: f32) void {
        if (dur <= 0) return;
        self.left = dur;
        self.rate = total / dur;
    }
    /// Per frame. Pours through `Vitals.heal`, so it tops out at max and CANNOT raise the dead —
    /// the same door the kobold priest uses, for the same reason.
    pub fn tick(self: *Regen, dt: f32, v: *Vitals) void {
        if (!self.active()) return;
        if (v.dead) return self.reset(); // …and dying ends it: a corpse is not still digesting
        const step = minF(dt, self.left);
        self.left -= step;
        _ = v.heal(self.rate * step);
    }
    // (A `fracLeft` for a HUD bar was written here and DELETED: nothing drew it, and its own
    // doc-comment said "what a bar would draw" about a bar that does not exist. Second time in two
    // passes — the shield's `blocks` counter was the first. Write the reader, then the accessor.)
    pub fn reset(self: *Regen) void {
        self.left = 0;
        self.rate = 0;
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
    // Each pair breaks poise once, and each break's own stun is RUN OUT before the next pair — poise
    // is immune while a reaction plays, so pressure now means landing between the flinches rather
    // than through them. Stance never regens across it (its delay is far longer than the stun), which
    // is what still lets the chip accumulate into the heavy.
    while (i < 12) : (i += 1) {
        if (v.hit(.{ .poise = 6 }) == .heavy) heavies += 1;
        while (v.stunned()) v.tick(1.0 / 60.0);
    }
    try std.testing.expect(heavies >= 1);
}

test "NOBODY IS POISE-DAMAGED WHILE REELING, and poise is full again when the stun ends" {
    // The owner's rule, and the chain-flinch it exists to kill: before this, the blow that staggered
    // you also set up the next stagger, so a warband or a mashed R1 could hold either side in one
    // unbroken reaction.
    var v = Vitals.init(100, 20, 500); // huge stance, so nothing here cascades to a heavy
    _ = v.hit(.{ .poise = 12 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 12 }));
    try std.testing.expect(v.stunned());
    const poiseAt = v.poise;
    // Ten more blows through the reel: HP lands every time, poise does not move at all, and not one
    // of them re-flinches him.
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 1, .poise = 99 }));
    }
    try std.testing.expectApproxEqAbs(poiseAt, v.poise, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 90), v.hp, 1e-4); // …the damage was never in question
    // …and it lifts on its own, with poise full.
    v.poise = 1;
    while (v.stunned()) v.tick(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(v.poiseMax, v.poise, 1e-5);
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 99 })); // flinchable again
}

test "the immunity is POISE only: a heavy landed inside a light stun still breaks stance" {
    // The punish window has to survive the fix. You opened it; landing the big one in it must still
    // count, or "stagger it, then hit it" stops paying.
    var v = Vitals.initFoe(100, 10, 30);
    _ = v.hit(.{ .poise = 6 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 6 }));
    try std.testing.expect(v.stunned());
    // Stance is already chipped by the light break (LIGHT_BREAK_STANCE); one heavy's direct stance
    // damage finishes it, mid-flinch.
    try std.testing.expectEqual(HitResult.heavy, v.hit(.{ .poise = 1, .stance = 20 }));
    // …and the bigger reaction re-armed the window at the HEAVY length, not the light one.
    try std.testing.expectApproxEqAbs(FOE_HEAVY_STUN_DUR, v.stunLeft, 1e-5);
}

test "the immunity window IS the reaction the rig poses, on both sides" {
    // Two clocks for one thing is a drift waiting to happen: the rigs run their own `t` against these
    // constants for the ANIMATION and Vitals runs `stunLeft` for the MECHANIC, so they have to be
    // seeded from the same pair — and the hero's pair is not the foes'.
    var hero = Vitals.init(100, 10, 999);
    var foeV = Vitals.initFoe(100, 10, 999);
    hero.beginStun(.light);
    foeV.beginStun(.light);
    try std.testing.expectApproxEqAbs(LIGHT_STUN_DUR, hero.stunLeft, 1e-6);
    try std.testing.expectApproxEqAbs(FOE_LIGHT_STUN_DUR, foeV.stunLeft, 1e-6);
    hero.beginStun(.heavy);
    foeV.beginStun(.heavy);
    try std.testing.expectApproxEqAbs(HEAVY_STUN_DUR, hero.stunLeft, 1e-6);
    try std.testing.expectApproxEqAbs(FOE_HEAVY_STUN_DUR, foeV.stunLeft, 1e-6);
    // …and `.none` disarms rather than leaving a window open behind a cleared reaction.
    hero.beginStun(.none);
    try std.testing.expect(!hero.stunned());
}

test "a HEAVY break refills poise when it ends, which is the tier that needed it" {
    // A light break resets poise on the spot; a heavy one resets STANCE and leaves poise wherever the
    // blow left it. Without the refill at the end, coming out of the bigger reaction left you more
    // fragile than coming out of the small one — the wrong way round.
    var v = Vitals.init(100, 40, 20);
    v.poise = 3; // most of the way to a flinch already
    try std.testing.expectEqual(HitResult.heavy, v.hit(.{ .poise = 1, .stance = 30 }));
    try std.testing.expect(v.poise < v.poiseMax); // the heavy break did NOT touch it…
    while (v.stunned()) v.tick(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(v.poiseMax, v.poise, 1e-5); // …the end of the reaction does
}

test "the stun clock is not held behind the regen gate" {
    // THE ordering bug this guards: the hit that starts a stun also zeroes `sinceHit`, and a foe's
    // regen delay (2.2 s) is longer than either of its stun windows. Counted down after that gate,
    // `stunLeft` would never reach zero and a stunned foe would be poise-immune for ever.
    try std.testing.expect(FOE_REGEN_DELAY > FOE_LIGHT_STUN_DUR);
    var v = Vitals.initFoe(100, 10, 999);
    _ = v.hit(.{ .poise = 6 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 6 }));
    var t: f32 = 0;
    while (t < FOE_LIGHT_STUN_DUR + 0.05) : (t += 1.0 / 60.0) v.tick(1.0 / 60.0);
    try std.testing.expect(!v.stunned()); // …still well inside the regen delay
    try std.testing.expect(v.sinceHit < v.regenDelay);
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

test "the small shield costs stamina by the WEIGHT of the blow, and lets a little through" {
    // The two dials that decide whether guarding is a crutch, asserted against the two ends of the
    // game's damage range rather than against themselves.
    const teeth = Hit{ .dmg = 9, .poise = 7 }; // a kobold's bite
    const club = Hit{ .dmg = 36, .poise = 44, .stance = 20 }; // the ogre's slam
    // …but not PROPORTIONALLY: the flat bite means every block costs something, so a blow four
    // times the damage is under three times the stamina, and that is deliberate.
    try std.testing.expect(guardStamina(club) > 2.5 * guardStamina(teeth));
    try std.testing.expect(guardStamina(club) < 4.0 * guardStamina(teeth));
    // …and the chip is a bite, not a scratch and not the blow.
    try std.testing.expect(guardChip(club) > 3.0 and guardChip(club) < 0.25 * club.dmg);
}

test "a small shield holds off the small stuff and CANNOT hold a giant" {
    // The design in one test: the same full bar buys a long exchange with the little ones and three
    // swings of the club. Blocking is a beat you buy, never a wall you stand behind.
    var s = Stamina{};
    var bites: u32 = 0;
    while (s.cur > 0) : (bites += 1) s.spend(guardStamina(.{ .dmg = 9 }));
    var t = Stamina{};
    var slams: u32 = 0;
    while (t.cur > 0) : (slams += 1) t.spend(guardStamina(.{ .dmg = 36 }));
    try std.testing.expect(bites >= 6);
    try std.testing.expect(slams >= 2 and slams <= 3);
}

test "the jerky's drip pours its whole meal, and no more" {
    var v = Vitals.init(100, 20, 40);
    _ = v.hit(.{ .dmg = 80 });
    var r = Regen{};
    r.start(60, 20.0);
    try std.testing.expect(r.active());
    var t: f32 = 0;
    while (t < 10.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0, &v);
    try std.testing.expectApproxEqAbs(@as(f32, 50), v.hp, 0.5); // …half the meal at half time
    while (t < 25.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0, &v);
    try std.testing.expectApproxEqAbs(@as(f32, 80), v.hp, 0.5); // …all of it, and it STOPS
    try std.testing.expect(!r.active());
}

test "a drip tops out at max, cannot raise the dead, and REFRESHES rather than stacking" {
    var v = Vitals.init(100, 20, 40);
    _ = v.hit(.{ .dmg = 10 });
    var r = Regen{};
    r.start(60, 20.0);
    var t: f32 = 0;
    while (t < 25.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0, &v);
    try std.testing.expectApproxEqAbs(@as(f32, 100), v.hp, 1e-3); // capped, not overflowed
    // A second one RESTARTS: two overlapping drips at different rates is a thing no bar can show.
    r.start(60, 20.0);
    r.tick(1.0, &v);
    r.start(30, 10.0);
    try std.testing.expectApproxEqAbs(@as(f32, 10), r.left, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 3), r.rate, 1e-4);
    // …and dying ends it on the spot rather than digesting through the death anim.
    var d = Vitals.init(100, 20, 40);
    var dr = Regen{};
    dr.start(60, 20.0);
    _ = d.hit(.{ .dmg = 500 });
    dr.tick(1.0 / 60.0, &d);
    try std.testing.expect(!dr.active() and d.hp <= 0);
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
