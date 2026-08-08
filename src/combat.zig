const std = @import("std");
const mathx = @import("mathx.zig");
const stats = @import("stats.zig");
const item = @import("item.zig");


pub const StunKind = enum { none, light, heavy };

pub const HitResult = enum { none, light, heavy, death };

pub const HitOutcome = enum { ignored, taken, blocked, guardBroken };


/// THE FOUR NON-PHYSICAL DAMAGE TYPES, PoE2's. Physical is deliberately NOT one of them: it is the damage everything in the game already deals, it is the one type nothing resists, and what mitigates it there is ARMOUR, which does not exist here yet.
pub const Elem = enum(u8) { fire, cold, lightning, chaos };

pub const NELEM = @typeInfo(Elem).@"enum".fields.len;

pub fn elemName(e: Elem) [:0]const u8 {
    return switch (e) {
        .fire => "Fire",
        .cold => "Cold",
        .lightning => "Lightning",
        .chaos => "Chaos",
    };
}

/// A number per element, WRITTEN BY NAME — damage on a `Hit`, percent on a `Resists`. Authoring through this rather than an array literal is what stops a four-wide row from silently shifting when the enum gains a fifth: the field names are matched against the enum at comptime, so a rename is a compile error and an omitted element is a 0.
pub const Spread = struct { fire: f32 = 0, cold: f32 = 0, lightning: f32 = 0, chaos: f32 = 0 };

fn pack(s: Spread) [NELEM]f32 {
    var out = [_]f32{0} ** NELEM;
    inline for (@typeInfo(Elem).@"enum".fields) |f| out[f.value] = @field(s, f.name);
    return out;
}

/// ELEMENTAL DAMAGE RIDING ON A BLOW, on top of its physical `dmg` — PoE2's "adds X fire damage".
pub const Elems = struct {
    v: [NELEM]f32 = [_]f32{0} ** NELEM,

    pub fn at(self: Elems, e: Elem) f32 {
        return self.v[@intFromEnum(e)];
    }
    pub fn total(self: Elems) f32 {
        var n: f32 = 0;
        for (self.v) |x| n += x;
        return n;
    }
    pub fn any(self: Elems) bool {
        return self.total() > 0;
    }
    pub fn scaled(self: Elems, k: f32) Elems {
        var out = self;
        for (&out.v) |*x| x.* *= k;
        return out;
    }
};

pub fn elems(s: Spread) Elems {
    return .{ .v = pack(s) };
}

/// PoE2's MAXIMUM RESISTANCE: 75%, however much is stacked on top.
pub const RES_CAP: f32 = 75.0;
/// …and a floor, because a NEGATIVE resistance amplifies the hit instead and there is no natural stop on that side. -100 is exactly double damage.
pub const RES_FLOOR: f32 = -100.0;

/// WHAT A BODY SHRUGS OFF, per element, as a percentage. Stored UNCAPPED and capped on the way out, so a creature authored at 90 still reads as 90 on a sheet while taking damage at 75 — the same split PoE2 shows.
pub const Resists = struct {
    v: [NELEM]f32 = [_]f32{0} ** NELEM,

    /// What is stacked (uncapped) — for display.
    pub fn raw(self: Resists, e: Elem) f32 {
        return self.v[@intFromEnum(e)];
    }
    /// What actually applies.
    pub fn at(self: Resists, e: Elem) f32 {
        return mathx.clampF(self.raw(e), RES_FLOOR, RES_CAP);
    }
    pub fn taken(self: Resists, e: Elem, amt: f32) f32 {
        return amt * (1.0 - self.at(e) / 100.0);
    }
    /// The whole elemental half of a blow, each part through its own resistance.
    pub fn takenAll(self: Resists, es: Elems) f32 {
        var n: f32 = 0;
        for (es.v, 0..) |amt, i| {
            if (amt != 0) n += self.taken(@enumFromInt(i), amt);
        }
        return n;
    }
};

pub fn resists(s: Spread) Resists {
    return .{ .v = pack(s) };
}

pub const Hit = struct {
    dmg: f32 = 0, // PHYSICAL — nothing resists it
    poise: f32 = 0,
    stance: f32 = 0,
    elem: Elems = .{},
    /// FOCUS TORN OUT OF HIM ON TOP OF THE DAMAGE — the shade's touch, and the only thing in the game that
    /// takes the blue bar off anybody. Deliberately NOT part of `raw()`: what a shield's stamina bill and
    /// "which of two blows was worse" measure is the WEIGHT of the thing that hit you, and a drain has none.
    /// Nothing but the hero carries a `Focus`, so a foe handed one of these simply never reads the field.
    fp: f32 = 0,

    /// THE WHOLE BLOW BEFORE ANYBODY'S RESISTANCES. What a shield's stamina bill and "which of two blows was worse" are measured on: those are about the weight of the thing that hit you, not about what you happen to resist.
    pub fn raw(self: Hit) f32 {
        return self.dmg + self.elem.total();
    }
};

const REGEN_DELAY = 0.8; // seconds after the last hit before the HERO's meters refill
const POISE_REFILL = 1.3; // seconds to refill poise from empty
const STANCE_REFILL = 4.6;
const LIGHT_BREAK_STANCE = 0.40; // fraction of max stance one LIGHT break chips off
const FOE_REGEN_DELAY = 2.2;
const FOE_REGEN_RATE = 0.45;
pub const LIGHT_STUN_DUR = 0.46;
pub const HEAVY_STUN_DUR = 1.15;
pub const FOE_LIGHT_STUN_DUR = 0.78;
pub const FOE_HEAVY_STUN_DUR = 2.40;
const LONG_AGO = mathx.LONG_AGO;


pub const Vitals = struct {
    hp: f32,
    hpMax: f32,
    poise: f32,
    poiseMax: f32,
    stance: f32,
    stanceMax: f32,
    sinceHit: f32 = LONG_AGO, // seconds since the last poise-damaging hit (gates regen)
    /// …and since anything last took HP off this body, A DRIP INCLUDED — what the floating HP bar is gated on
    /// (`game.drawFoeBars`). Its OWN clock, because a hold has to be as visible as a blow while denying none of
    /// the refill `sinceHit` gates: one field cannot answer "show the bar" and "hold the gate shut" separately,
    /// and the roots need opposite answers to the two.
    sinceHurt: f32 = LONG_AGO,
    dead: bool = false,
    regenDelay: f32 = REGEN_DELAY,
    regenRate: f32 = 1.0,
    stunLeft: f32 = 0,
    lightStun: f32 = LIGHT_STUN_DUR,
    heavyStun: f32 = HEAVY_STUN_DUR,
    res: Resists = .{},

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

    pub fn initFoe(hpMax: f32, poiseMax: f32, stanceMax: f32) Vitals {
        var v = init(hpMax, poiseMax, stanceMax);
        v.regenDelay = FOE_REGEN_DELAY;
        v.regenRate = FOE_REGEN_RATE;
        v.lightStun = FOE_LIGHT_STUN_DUR;
        v.heavyStun = FOE_HEAVY_STUN_DUR;
        return v;
    }

    /// The creature's own resistances, bolted on where it is declared (`initFoe(..).withRes(..)`) so a foe's nature sits in one expression beside its HP.
    pub fn withRes(self: Vitals, r: Resists) Vitals {
        var v = self;
        v.res = r;
        return v;
    }

    /// WHAT THIS BODY WOULD ACTUALLY LOSE to that blow: the physical straight through, each element through its own resistance.
    pub fn damageFrom(self: *const Vitals, h: Hit) f32 {
        return h.dmg + self.res.takenAll(h.elem);
    }

    pub fn stunned(self: *const Vitals) bool {
        return self.stunLeft > 0;
    }

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

    pub fn heal(self: *Vitals, amt: f32) f32 {
        if (self.dead or amt <= 0) return 0;
        const before = self.hp;
        self.hp = mathx.minF(self.hpMax, self.hp + amt);
        return self.hp - before;
    }

    pub fn needsHeal(self: *const Vitals, slack: f32) bool {
        return !self.dead and self.hp < self.hpMax - slack;
    }

    pub fn tick(self: *Vitals, dt: f32) void {
        self.sinceHit += dt;
        self.sinceHurt += dt;
        if (self.stunLeft > 0) {
            self.stunLeft -= dt;
            // THE REACTION IS OVER: poise back to full, whichever tier it was.
            if (self.stunLeft <= 0) {
                self.stunLeft = 0;
                self.poise = self.poiseMax;
            }
        }
        if (self.dead or self.sinceHit < self.regenDelay) return;
        self.poise = mathx.minF(self.poiseMax, self.poise + self.poiseMax / POISE_REFILL * self.regenRate * dt);
        self.stance = mathx.minF(self.stanceMax, self.stance + self.stanceMax / STANCE_REFILL * self.regenRate * dt);
    }

    /// A DRIP — damage billed EVERY FRAME by something that holds (`Root`), as opposed to a blow. `hit` in every
    /// respect but the REGEN CLOCK: `hit` stamps `sinceHit` at 0, which gates the poise/stance refill, and
    /// stamped afresh every frame for a whole `ROOT_HOLD` that gate never opens — so a grip documented to carry
    /// no poise and no stance would deny most of a poise bar anyway, which is the stagger tool it is documented
    /// not to be. `sinceHurt` IS stamped, so the bar shows the drip working. Poise-free drips only.
    pub fn drip(self: *Vitals, h: Hit) HitResult {
        const clock = self.sinceHit;
        const r = self.hit(h);
        self.sinceHit = clock;
        return r;
    }

    pub fn hit(self: *Vitals, h: Hit) HitResult {
        if (self.dead) return .none;
        self.sinceHurt = 0; // before the death exit: every path that takes HP is one the bar should have shown
        self.hp = mathx.maxF(0, self.hp - self.damageFrom(h));
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

// ER's shallow, fast-refilling pool (docs/ELDEN_RING.md §3 — these ARE its Endurance-15 numbers): a flat bite per action, pouring back ~4x as fast as a roll spends it, so it paces a FLURRY without becoming a resource you manage between fights.
pub const STAM_MAX = stats.staminaFor(stats.START); // 105 — ENDURANCE owns the pool size now (`stats.zig`); about eight rolls from full
pub const STAM_ROLL = 12.0; // ER's flat, load-independent roll cost: the anchor for the rest
pub const STAM_LIGHT = 10.0; // R1, ER's straight-sword band
pub const STAM_HEAVY = 16.0; // R2
pub const STAM_SHOT = 8.0;
pub const STAM_AIMED = 18.0;
pub const STAM_SPRINT = 9.0;
const STAM_REGEN = 45.0;
const STAM_DELAY = 0.55; // seconds after the last spend before it refills
pub const STAM_REFUSE_FLASH: f32 = 0.35;

pub const STAM_LOCKOUT = true;

pub const STAM_WIND_CLEAR: f32 = 0.5;

/// A FOE'S GUARD COMES BACK SLOWLY, the way its poise does (`FOE_REGEN_RATE`): at the hero's rate a
/// shieldman's boards are back up before the next swing lands and the bar can never be emptied.
pub const FOE_STAM_RATE: f32 = 0.26;

pub const Stamina = struct {
    cur: f32 = STAM_MAX,
    max: f32 = STAM_MAX,
    sinceSpend: f32 = LONG_AGO, // gates the refill delay
    winded: bool = false,
    regenRate: f32 = 1.0,

    /// A guard that is NOT the hero's — its own pool, on the slow foe schedule (mirrors `Vitals.initFoe`).
    pub fn initFoe(max: f32) Stamina {
        return .{ .cur = max, .max = max, .regenRate = FOE_STAM_RATE };
    }

    pub fn frac(self: *const Stamina) f32 {
        return if (self.max > 0) mathx.clampF(self.cur / self.max, 0, 1) else 0;
    }

    pub fn canAct(self: *const Stamina) bool {
        return !STAM_LOCKOUT or self.cur > 0;
    }

    pub fn spend(self: *Stamina, cost: f32) void {
        self.cur = mathx.maxF(0, self.cur - cost);
        self.sinceSpend = 0;
        self.settleWind();
    }

    pub fn canSprint(self: *const Stamina) bool {
        return self.canAct() and (!STAM_LOCKOUT or !self.winded);
    }

    pub fn tick(self: *Stamina, dt: f32, sprinting: bool, committed: bool) void {
        if (sprinting) {
            self.cur = mathx.maxF(0, self.cur - STAM_SPRINT * dt);
            self.sinceSpend = 0;
        } else {
            self.sinceSpend += dt;
            if (!committed and self.sinceSpend >= STAM_DELAY) {
                self.cur = mathx.minF(self.max, self.cur + STAM_REGEN * self.regenRate * dt);
            }
        }
        self.settleWind();
    }

    pub fn windedTo(self: *const Stamina) f32 {
        return if (self.canSprint()) 0 else STAM_WIND_CLEAR;
    }

    /// ONE SHARP BREATH (the Second Wind item): `frac` of the pool back at once, through `settleWind`
    /// like every other path that moves `cur` — which is what clears the winded latch, since half a pool
    /// is past `STAM_WIND_CLEAR`. `sinceSpend` restarts: it is a gasp, not a rest, so the trickle waits.
    pub fn secondWind(self: *Stamina, share: f32) void {
        self.cur = mathx.minF(self.max, self.cur + self.max * share);
        self.sinceSpend = 0;
        self.settleWind();
    }

    /// The winded latch, set and cleared in ONE place and called from every path that moves `cur`.
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

pub const GUARD_NEGATE: f32 = 0.85; // fraction of a blocked blow's HP damage the shield eats…
pub const GUARD_STAM_FLAT: f32 = 5.0;
pub const GUARD_STAM_PER_DMG: f32 = 1.10;
pub const GUARD_ARC: f32 = 65.0;

/// Billed on the RAW weight of the blow: the arm behind a burning arrow does not know what you resist.
pub fn guardStamina(h: Hit) f32 {
    return GUARD_STAM_FLAT + GUARD_STAM_PER_DMG * h.raw();
}
/// WHAT GETS THROUGH — still a `Hit`, so the chip's elemental share meets the blocker's resistances instead of arriving as raw HP. DAMAGE ONLY: poise and stance are what the shield is FOR, and a chip that carried the blow's stagger through would flinch him behind his own guard.
pub fn guardChip(h: Hit) Hit {
    const k = 1.0 - GUARD_NEGATE;
    // The DRAIN is chipped by the same fraction, for the reason the chip exists at all: nothing the boards
    // stop is stopped outright. A shade's touch caught square still costs a mouthful of the blue bar.
    return .{ .dmg = h.dmg * k, .elem = h.elem.scaled(k), .fp = h.fp * k };
}

// THE PARRY — L2, the shield's own skill, and the guard's opposite number in every respect. A held shield is a
// LEVEL that pays stamina to eat blows all day and chips you for the privilege; this is a COMMITTED WINDOW that
// pays once and refuses one blow outright. Whiff it and the shield is not up either, because the window is a
// committed action and `canGuard` excludes those — which is the whole risk of asking for it.

/// Under the heavy's 16 and over a quick shot's 8: the cost of a guess, not of a swing.
pub const STAM_PARRY: f32 = 9.0;
/// WHAT THE BOARDS DEAL WHEN THEY CATCH: nothing to the health, everything to the FOOTING. No `dmg`, because a
/// parry has never been damage — the punish after it is. And NO POISE either, so a catch can never resolve as a
/// mere flinch: it breaks the stance or it does not, which is exactly the owner's "may heavy stun them", read
/// off the same bar the sword has been chipping all fight rather than off a dice roll. Sized so the game's
/// high-poise heavy (the ogre's 90 stance) takes two clean catches and everything lighter takes one.
pub const PARRY_HIT = Hit{ .stance = 46 };

pub const FP_MAX = stats.fpFor(stats.START); // 60 — MIND owns it (`stats.zig`)

pub const Focus = struct {
    cur: f32 = FP_MAX,
    max: f32 = FP_MAX,

    pub fn frac(self: *const Focus) f32 {
        return if (self.max > 0) mathx.clampF(self.cur / self.max, 0, 1) else 0;
    }
    pub fn canTake(self: *const Focus) bool {
        return self.cur < self.max - 1e-3;
    }
    pub fn restore(self: *Focus, amt: f32) bool {
        if (!self.canTake()) return false;
        self.cur = minF(self.max, self.cur + amt);
        return true;
    }
    /// PAY THE WHOLE COST OR CAST NOTHING — the exact OPPOSITE of `Stamina.canAct`'s panic rule, and the
    /// difference is deliberate: the bottom of the stamina bar buys a roll you cannot afford because that
    /// is the genre's most important move, where a half-paid spell would be a spell that half exists. ER
    /// refuses the cast outright, so an FP bar reading 4 of a 12-cost sorcery is 4 you cannot use.
    pub fn spend(self: *Focus, amt: f32) bool {
        if (self.cur < amt) return false;
        self.cur -= amt;
        return true;
    }
    /// TAKEN FROM HIM RATHER THAN SPENT BY HIM (`Hit.fp`), so it FLOORS where `spend` refuses: a blow is not
    /// a purchase, and one landing on four points of focus takes the four.
    pub fn drain(self: *Focus, amt: f32) void {
        self.cur = mathx.maxF(0, self.cur - amt);
    }
    pub fn reset(self: *Focus) void {
        self.cur = self.max;
    }
};

// The wand's one spell, and the first thing in the game that spends FP.

/// WHAT THE BOLT COSTS, and the pool is the only thing rationing it — a cast bills NO stamina (owner's
/// call), so the wand competes with the flask for a grace's worth of resource rather than with the roll.
/// NAMED FOR ITS SPELL, like `ROOT_FP` beside it: as `BOLT_FP` it read as "what a cast costs", and the
/// character book duly priced the roots at the bolt's twelve.
pub const BOLT_FP: f32 = 12.0; // five casts of a 60-point pool
/// THE BOLT, and it is ALL CHAOS — no physical at all, the brood mother's rule for the same reason: one
/// substance, one element. Its damage sits between a light slash's 13 and a heavy's 27 before anything
/// resists it, which is the "decent" the owner asked for; the poise is above a light's and under a
/// heavy's, so it rocks a foe without being the stagger tool the greatsword is.
pub const BOLT_HIT = Hit{ .poise = 14, .stance = 6, .elem = elems(.{ .chaos = 24 }) };

/// THE ROOTS — the wand's second spell, and the first thing in the game that takes a foe's FEET rather than
/// its health. It costs MORE than the bolt and deals LESS: you cast it to buy the ground back, not to kill.
pub const ROOT_FP: f32 = 18.0; // dearer than the bolt's 12 — three casts to a grace, not five
pub const ROOT_HOLD: f32 = 3.5; // seconds the feet are held
pub const ROOT_DPS: f32 = 4.0; // chaos a second while they hold (~14 over a full grip)
/// How far from the mark the ground is SEARCHED for feet to take, which is the reach of a cast with nothing
/// locked. NOT A BLAST RADIUS: `game.rootVictim` takes ONE body out of it, since a sword's swing is the only
/// thing in the game that reaches more than one.
pub const ROOT_R: f32 = 2.6;
/// …and how wide the earth splits AROUND THE BODY IT TOOK. A body, not the reach: a ring thrown out to
/// `ROOT_R` reads as an area spell — there are none — and promises a hold on the neighbour it did not take.
pub const ROOT_GRIP_R: f32 = 1.0;

/// A FOE'S FEET, HELD. Shaped like `Regen` — a clock that bills a little every frame it runs — because that
/// is what it is, with the sign reversed and somebody else's meter on the other end.
pub const Root = struct {
    left: f32 = 0,

    pub fn held(self: *const Root) bool {
        return self.left > 0;
    }
    /// A SECOND CAST REFRESHES RATHER THAN STACKING (the drip's rule, `Regen.start`): two overlapping grips
    /// at different clocks is a hold no bar and no animation can show.
    pub fn grab(self: *Root) void {
        self.left = ROOT_HOLD;
    }
    pub fn release(self: *Root) void {
        self.left = 0;
    }
    /// The bite this frame, or null when nothing is holding. NO POISE AND NO STANCE: the roots are not a
    /// stagger tool, and a hold that also flinched would be the guard-break the owner did not ask for.
    pub fn tick(self: *Root, dt: f32) ?Hit {
        if (self.left <= 0) return null;
        const step = minF(dt, self.left);
        self.left -= step;
        return .{ .elem = elems(.{ .chaos = ROOT_DPS * step }) };
    }
};

/// WHICH SORCERY THE ROD IS SET TO. Exhaustive everywhere it is read, so a third spell is a compile error
/// until it has said what it costs and what it does.
pub const Spell = enum { bolt, roots };

pub fn spellName(s: Spell) [:0]const u8 {
    return switch (s) {
        .bolt => "Chaos Bolt",
        .roots => "Roots",
    };
}

/// WHAT EACH ONE BILLS. One place, so the HUD's "could he cast?" and the cast itself cannot disagree.
pub fn spellFp(s: Spell) f32 {
    return switch (s) {
        .bolt => BOLT_FP,
        .roots => ROOT_FP,
    };
}

/// …and WHAT EACH ONE IS WORTH, before anybody's resistances — the character sheet's own row. The grip bills
/// its chaos a frame at a time, so its whole span is what compares with a blow that lands at once.
pub fn spellDamage(s: Spell) f32 {
    return switch (s) {
        .bolt => BOLT_HIT.raw(),
        .roots => ROOT_HOLD * ROOT_DPS,
    };
}

pub const FlaskKind = enum { crimson, cerulean };

pub const FLASK_CRIMSON: u8 = 2; // …two red to one blue
pub const FLASK_CERULEAN: u8 = 1;
pub const FLASK_HP_FRAC: f32 = 0.45; // fraction of the MAX restored
pub const FLASK_FP_FRAC: f32 = 0.50;
pub const FLASK_DRINK_DUR: f32 = 1.05; // the committed window
pub const FLASK_POUR_AT: f32 = 0.42;

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
    pub fn ready(self: *const Flasks) u8 {
        return self.charges(self.sel);
    }
    pub fn cycle(self: *Flasks) void {
        self.sel = switch (self.sel) {
            .crimson => .cerulean,
            .cerulean => .crimson,
        };
    }
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
    pub fn refill(self: *Flasks) void {
        self.crimson = FLASK_CRIMSON;
        self.cerulean = FLASK_CERULEAN;
    }
};

/// The flask kind an item IS, or null. `item.isFlask` is the same question one layer down, where it is a fact
/// about the item and not about the pool its charges live in.
pub fn flaskOf(k: item.Kind) ?FlaskKind {
    return switch (k) {
        .crimson_flask => .crimson,
        .cerulean_flask => .cerulean,
        else => null,
    };
}

/// HOW MANY OF A QUICK-BAR THING HE HAS. A flask counts CHARGES, which come back at a grace; everything else
/// counts what is in the BAG, which does not. The HUD asks this off the live game and the character book off
/// its `View`, and both have the two pools in hand — as a copy on each side it was one rule in two files.
pub fn quickCount(k: item.Kind, flasks: *const Flasks, bag: *const item.Bag) u8 {
    if (flaskOf(k)) |f| return flasks.charges(f);
    return @intCast(@min(bag.count(k), 99));
}

/// THE QUICK BAR — ER's pouch, on the cross's DOWN slot, and **in combat the only way to spend a
/// consumable** (`game.inCombat` decides; the character book's own Use is refused while a fight is on).
/// What is on it is therefore a decision made BEFORE the fight, which is the whole point of it. Out of
/// combat you may use anything straight off the inventory page and never touch this.
///
/// THE FLASKS ARE JUST ITS FIRST TWO ENTRIES and are not special-cased anywhere but the spend: `Flasks` keeps
/// their charges because those come back at a grace, where everything else comes out of the bag.
pub const QUICK_SLOTS: usize = 10;

pub const Quick = struct {
    /// ORDERED, and a removal leaves its hole rather than compacting: the bar is cycled by muscle memory in
    /// the middle of a fight, and a list that shuffles under you every time you drop something is one you
    /// cannot learn. `add` takes the first free slot.
    slots: [QUICK_SLOTS]?item.Kind = blk: {
        var s = [_]?item.Kind{null} ** QUICK_SLOTS;
        s[0] = .crimson_flask;
        s[1] = .cerulean_flask;
        break :blk s;
    },
    sel: usize = 0,

    pub fn selected(self: *const Quick) ?item.Kind {
        return self.slots[self.sel];
    }
    pub fn holds(self: *const Quick, k: item.Kind) bool {
        for (self.slots) |s| {
            if (s == k) return true;
        }
        return false;
    }
    pub fn filled(self: *const Quick) usize {
        var n: usize = 0;
        for (self.slots) |s| {
            if (s != null) n += 1;
        }
        return n;
    }
    /// …into the first free slot. False = it is already on, or the bar is full.
    pub fn add(self: *Quick, k: item.Kind) bool {
        if (self.holds(k)) return false;
        for (&self.slots, 0..) |*s, i| {
            if (s.* != null) continue;
            s.* = k;
            if (self.slots[self.sel] == null) self.sel = i; // the bar was empty: land on what just arrived
            return true;
        }
        return false;
    }

    /// Set one socket; `null` empties it. A kind already elsewhere on the bar MOVES here — two sockets on
    /// one flask are two cycle steps to the same swallow.
    pub fn put(self: *Quick, i: usize, k: ?item.Kind) void {
        if (i >= QUICK_SLOTS) return;
        if (k) |want| {
            for (&self.slots, 0..) |*s, j| {
                if (j != i and s.* == want) s.* = null;
            }
        }
        self.slots[i] = k;
        if (self.slots[self.sel] == null) self.settle();
    }
    pub fn remove(self: *Quick, k: item.Kind) bool {
        for (&self.slots) |*s| {
            if (s.* != k) continue;
            s.* = null;
            if (self.slots[self.sel] == null) self.settle();
            return true;
        }
        return false;
    }
    /// The next occupied slot, wrapping. A bar with one thing on it stays on that thing.
    pub fn cycle(self: *Quick) void {
        for (1..QUICK_SLOTS + 1) |step| {
            const i = (self.sel + step) % QUICK_SLOTS;
            if (self.slots[i] == null) continue;
            self.sel = i;
            return;
        }
    }
    /// DROP WHAT HE HAS RUN OUT OF, called once a frame (`game.stepWorld`). A row pointing at nothing is a
    /// cycle step that does nothing and a HUD cell showing a thing he does not have.
    ///
    /// A FLASK AT ZERO STAYS ON. Its charges are not the bag's — they come back at a grace — so an empty one
    /// is still the thing he is carrying, and taking it off the bar the moment he drank the last swallow
    /// would mean re-loading the bar at every bonfire.
    pub fn dropEmpty(self: *Quick, bag: *const item.Bag) void {
        for (&self.slots) |*s| {
            const k = s.* orelse continue;
            if (flaskOf(k) != null) continue;
            if (bag.count(k) == 0) s.* = null;
        }
        if (self.slots[self.sel] == null) self.settle();
    }

    /// Point `sel` at something real, for when what it was on has just been taken off.
    fn settle(self: *Quick) void {
        for (self.slots, 0..) |s, i| {
            if (s == null) continue;
            self.sel = i;
            return;
        }
        self.sel = 0; // nothing left on it at all
    }
};

pub const ARROWS_MAX: u8 = 10;
/// FIRE ARROWS ARE THE SCARCE ONES — half a plain quiver, so the fire rider is a shot you pick a target for rather than the one you open with.
pub const FIRE_ARROWS_MAX: u8 = 5;

pub const ArrowKind = enum { plain, fire };

pub const Quiver = struct {
    arrows: u8 = ARROWS_MAX,
    fire: u8 = FIRE_ARROWS_MAX,
    sel: ArrowKind = .plain,

    pub fn cap(k: ArrowKind) u8 {
        return switch (k) {
            .plain => ARROWS_MAX,
            .fire => FIRE_ARROWS_MAX,
        };
    }
    pub fn count(self: *const Quiver, k: ArrowKind) u8 {
        return switch (k) {
            .plain => self.arrows,
            .fire => self.fire,
        };
    }
    pub fn ready(self: *const Quiver) u8 {
        return self.count(self.sel);
    }
    /// THE SELECTED KIND IS THE ONE THAT FLIES, empty or not: a dry fire quiver refuses the shot rather than quietly loosing a plain shaft you did not ask for.
    pub fn cycle(self: *Quiver) void {
        self.sel = switch (self.sel) {
            .plain => .fire,
            .fire => .plain,
        };
    }
    /// Spend one of the SELECTED kind, reporting whether there WAS one — the caller refuses the shot on false.
    pub fn take(self: *Quiver) bool {
        switch (self.sel) {
            .plain => {
                if (self.arrows == 0) return false;
                self.arrows -= 1;
            },
            .fire => {
                if (self.fire == 0) return false;
                self.fire -= 1;
            },
        }
        return true;
    }
    /// …and the CEILING comes off `cap`, never off the constants again: as three places naming
    /// `ARROWS_MAX`/`FIRE_ARROWS_MAX` a third kind of arrow was three edits, and the two here would have
    /// compiled fine against the old pair.
    pub fn add(self: *Quiver, k: ArrowKind, n: u8) void {
        switch (k) {
            .plain => self.arrows = @min(cap(.plain), self.arrows +| n),
            .fire => self.fire = @min(cap(.fire), self.fire +| n),
        }
    }
    pub fn refill(self: *Quiver) void {
        self.arrows = cap(.plain);
        self.fire = cap(.fire);
    }
};


pub const Regen = struct {
    left: f32 = 0, // seconds still to run
    rate: f32 = 0, // HP a second while it does

    pub fn active(self: *const Regen) bool {
        return self.left > 0;
    }
    pub fn start(self: *Regen, total: f32, dur: f32) void {
        if (dur <= 0) return;
        self.left = dur;
        self.rate = total / dur;
    }
    pub fn tick(self: *Regen, dt: f32, v: *Vitals) void {
        if (!self.active()) return;
        if (v.dead) return self.reset();
        const step = minF(dt, self.left);
        self.left -= step;
        _ = v.heal(self.rate * step);
    }
    pub fn reset(self: *Regen) void {
        self.left = 0;
        self.rate = 0;
    }
};

pub const RUNE_ROLL_RATE = 7.0;
pub const RUNE_ROLL_FLOOR = 26.0;

pub const Runes = struct {
    total: u32 = 0,
    shown: f32 = 0, // what the HUD prints — chases `total`

    pub fn gain(self: *Runes, n: u32) void {
        self.total += n;
    }

    pub fn tick(self: *Runes, dt: f32) void {
        const goal: f32 = @floatFromInt(self.total);
        if (self.shown >= goal) {
            self.shown = goal; // never DRIFT above it, or the display shows a rune you don't have
            return;
        }
        self.shown = minF(goal, self.shown + maxF((goal - self.shown) * RUNE_ROLL_RATE, RUNE_ROLL_FLOOR) * dt);
    }

    pub fn display(self: *const Runes) u32 {
        return @intFromFloat(@floor(maxF(self.shown, 0)));
    }
};

const minF = mathx.minF;
const maxF = mathx.maxF;

test "the roots hold for their span, bill chaos the whole way, and let go on their own" {
    var r = Root{};
    try std.testing.expect(!r.held());
    try std.testing.expect(r.tick(1.0 / 60.0) == null); // nothing holding → nothing billed
    r.grab();
    try std.testing.expect(r.held());
    var paid: f32 = 0;
    var t: f32 = 0;
    while (t < ROOT_HOLD * 2.0) : (t += 1.0 / 60.0) {
        if (r.tick(1.0 / 60.0)) |h| paid += h.raw();
    }
    try std.testing.expect(!r.held()); // it expires without anybody releasing it
    try std.testing.expectApproxEqAbs(ROOT_HOLD * ROOT_DPS, paid, 1e-3); // …and bills its span exactly ONCE
}

test "the grip is ALL CHAOS and carries no stagger — a hold is not a flinch" {
    var r = Root{};
    r.grab();
    const h = r.tick(0.5).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.dmg, 1e-6); // no physical…
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.poise, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.stance, 1e-6);
    try std.testing.expectApproxEqAbs(ROOT_DPS * 0.5, h.elem.at(.chaos), 1e-5);
    // …so a body that shrugs chaos off shrugs the roots off, which is the wand's own honest trade.
    var chitin = Vitals.initFoe(100, 20, 40).withRes(resists(.{ .chaos = RES_CAP }));
    var bare = Vitals.initFoe(100, 20, 40);
    try std.testing.expectEqual(HitResult.none, chitin.hit(h)); // and it never flinches either of them
    _ = bare.hit(h);
    try std.testing.expect(chitin.hp > bare.hp);
}

test "THE GRIP DOES NOT DENY THE REFILL — a drip bills HP and leaves the regen clock alone" {
    // Billed through `hit`, the bite re-stamps `sinceHit` every frame and the gate never opens, so a foe held
    // for its whole span comes out of the roots with the poise it went in with. That is a stagger tool.
    var held = Vitals.initFoe(100, 20, 40);
    var loose = Vitals.initFoe(100, 20, 40);
    for ([_]*Vitals{ &held, &loose }) |v| _ = v.hit(.{ .poise = 15 }); // chipped by a real blow first
    var r = Root{};
    r.grab();
    var t: f32 = 0;
    while (t < ROOT_HOLD) : (t += 1.0 / 60.0) {
        if (r.tick(1.0 / 60.0)) |bite| _ = held.drip(bite);
        held.tick(1.0 / 60.0);
        loose.tick(1.0 / 60.0);
    }
    try std.testing.expectApproxEqAbs(loose.poise, held.poise, 1e-3); // the grip cost it no poise recovery…
    try std.testing.expect(held.poise > 5.5);
    try std.testing.expect(held.hp < loose.hp); // …and took the HP it is entitled to
    // …AND IT IS VISIBLE WHILE IT DOES IT: the bar's own clock is stamped every frame the grip bills.
    try std.testing.expect(held.sinceHurt < 1.0 / 30.0);
    try std.testing.expect(loose.sinceHurt > ROOT_HOLD - 0.1);
    // A REAL BLOW'S OWN DENIAL SURVIVES the drip that lands on the same frame.
    var struck = Vitals.initFoe(100, 20, 40);
    _ = struck.hit(.{ .poise = 15 });
    _ = struck.drip(.{ .elem = elems(.{ .chaos = 1 }) });
    try std.testing.expectApproxEqAbs(@as(f32, 0), struck.sinceHit, 1e-6);
}

test "a re-cast REFRESHES the grip rather than stacking a second clock on it" {
    var r = Root{};
    r.grab();
    _ = r.tick(ROOT_HOLD * 0.8);
    try std.testing.expect(r.left < ROOT_HOLD * 0.3);
    r.grab();
    try std.testing.expectApproxEqAbs(ROOT_HOLD, r.left, 1e-6);
    r.release();
    try std.testing.expect(!r.held() and r.tick(1.0) == null);
}

test "THE ROOTS COST MORE THAN THE BOLT AND DEAL LESS — a control tool, not a second bolt" {
    try std.testing.expect(spellFp(.roots) > spellFp(.bolt));
    // …and what erupts stays inside the body it took, or a single-target spell is drawn as an area one.
    try std.testing.expect(ROOT_GRIP_R < ROOT_R);
    try std.testing.expect(ROOT_HOLD * ROOT_DPS < BOLT_HIT.raw());
    // …and both are affordable off a full pool, or the sheet's Mind curve is a lie on the character page.
    try std.testing.expect(spellFp(.roots) <= FP_MAX);
    for (0..@typeInfo(Spell).@"enum".fields.len) |i| {
        const s: Spell = @enumFromInt(i);
        try std.testing.expect(spellName(s).len > 0);
        try std.testing.expect(spellFp(s) > 0);
        try std.testing.expect(spellDamage(s) > 0);
    }
    try std.testing.expect(spellDamage(.roots) < spellDamage(.bolt));
}

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
        if (v.hit(.{ .poise = 6 }) == .heavy) heavies += 1;
        while (v.stunned()) v.tick(1.0 / 60.0);
    }
    try std.testing.expect(heavies >= 1);
}

test "NOBODY IS POISE-DAMAGED WHILE REELING, and poise is full again when the stun ends" {
    var v = Vitals.init(100, 20, 500); // huge stance, so nothing here cascades to a heavy
    _ = v.hit(.{ .poise = 12 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 12 }));
    try std.testing.expect(v.stunned());
    const poiseAt = v.poise;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 1, .poise = 99 }));
    }
    try std.testing.expectApproxEqAbs(poiseAt, v.poise, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 90), v.hp, 1e-4);
    v.poise = 1;
    while (v.stunned()) v.tick(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(v.poiseMax, v.poise, 1e-5);
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 99 })); // flinchable again
}

test "the immunity is POISE only: a heavy landed inside a light stun still breaks stance" {
    var v = Vitals.initFoe(100, 10, 30);
    _ = v.hit(.{ .poise = 6 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 6 }));
    try std.testing.expect(v.stunned());
    try std.testing.expectEqual(HitResult.heavy, v.hit(.{ .poise = 1, .stance = 20 }));
    try std.testing.expectApproxEqAbs(FOE_HEAVY_STUN_DUR, v.stunLeft, 1e-5);
}

test "the immunity window IS the reaction the rig poses, on both sides" {
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
    hero.beginStun(.none);
    try std.testing.expect(!hero.stunned());
}

test "a HEAVY break refills poise when it ends, which is the tier that needed it" {
    var v = Vitals.init(100, 40, 20);
    v.poise = 3; // most of the way to a flinch already
    try std.testing.expectEqual(HitResult.heavy, v.hit(.{ .poise = 1, .stance = 30 }));
    try std.testing.expect(v.poise < v.poiseMax); // the heavy break did NOT touch it…
    while (v.stunned()) v.tick(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(v.poiseMax, v.poise, 1e-5);
}

test "the stun clock is not held behind the regen gate" {
    try std.testing.expect(FOE_REGEN_DELAY > FOE_LIGHT_STUN_DUR);
    var v = Vitals.initFoe(100, 10, 999);
    _ = v.hit(.{ .poise = 6 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 6 }));
    var t: f32 = 0;
    while (t < FOE_LIGHT_STUN_DUR + 0.05) : (t += 1.0 / 60.0) v.tick(1.0 / 60.0);
    try std.testing.expect(!v.stunned());
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
    var v = Vitals.initFoe(100, 20, 40);
    _ = v.hit(.{ .dmg = 60 });
    try std.testing.expectApproxEqAbs(@as(f32, 40), v.hp, 1e-4);
    try std.testing.expect(v.needsHeal(1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 25), v.heal(25), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 65), v.hp, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 35), v.heal(999), 1e-4);
    try std.testing.expectApproxEqAbs(v.hpMax, v.hp, 1e-4);
    try std.testing.expect(!v.needsHeal(1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.heal(50), 1e-4); // nothing missing → nothing poured
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
    // The point of the split: two seconds on, the hero is fully recovered and the foe has not started refilling at all, so pressure actually accrues.
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
    try std.testing.expect(!s.canSprint());
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
    var u: f32 = 0;
    while (u < STAM_DELAY + 0.10) : (u += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(s.cur > 0 and s.cur < STAM_WIND_CLEAR * s.max);
    try std.testing.expect(s.canAct());
    try std.testing.expect(!s.canSprint());
    try std.testing.expectApproxEqAbs(STAM_WIND_CLEAR, s.windedTo(), 1e-6);
    while (s.cur < STAM_WIND_CLEAR * s.max) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(!s.winded);
    try std.testing.expect(s.canSprint());
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.windedTo(), 1e-6);
    s.cur = 0;
    s.settleWind();
    try std.testing.expect(s.winded);
    s.reset();
    try std.testing.expect(!s.winded and s.canSprint());
}

test "THE PANIC ROLL: a sliver of stamina still buys a full-cost action" {
    var s = Stamina{};
    s.cur = 1.0;
    try std.testing.expect(s.canAct());
    s.spend(STAM_ROLL); // costs 12, he has 1 — the roll happens anyway
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    try std.testing.expect(!s.canAct());
}

test "a roll chain costs the sum of its rolls — the refill cannot pay for it" {
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
    try std.testing.expect(STAM_REGEN > 2.0 * STAM_HEAVY);
    try std.testing.expect(STAM_HEAVY > STAM_LIGHT and STAM_LIGHT < STAM_ROLL);
    try std.testing.expect(STAM_MAX / STAM_ROLL > 6.0); // ER's "~8 rolls from full"
}

test "the small shield costs stamina by the WEIGHT of the blow, and lets a little through" {
    const teeth = Hit{ .dmg = 9, .poise = 7 }; // a kobold's bite
    const club = Hit{ .dmg = 36, .poise = 44, .stance = 20 }; // the ogre's slam
    try std.testing.expect(guardStamina(club) > 2.5 * guardStamina(teeth));
    try std.testing.expect(guardStamina(club) < 4.0 * guardStamina(teeth));
    // …and the chip is a bite, not a scratch and not the blow.
    try std.testing.expect(guardChip(club).dmg > 3.0 and guardChip(club).dmg < 0.25 * club.dmg);
}

test "THE PARRY REFUSES A BLOW, and whether it staggers is the STANCE BAR's answer" {
    // No health and no poise on it — a catch can never come out as a flinch, only as "held" or "broken".
    try std.testing.expectApproxEqAbs(@as(f32, 0), PARRY_HIT.raw(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), PARRY_HIT.poise, 1e-6);
    try std.testing.expect(PARRY_HIT.stance > 0);
    // The game's high-poise heavy: two catches, never one. Sized against the ogre's own bar on purpose.
    const ogreStance: f32 = 90.0;
    var giant = Vitals.initFoe(300, 30, ogreStance);
    try std.testing.expectEqual(HitResult.none, giant.hit(PARRY_HIT));
    try std.testing.expectEqual(HitResult.heavy, giant.hit(PARRY_HIT));
    // …and anything lighter goes over on the first one.
    var lesser = Vitals.initFoe(60, 12, 40);
    try std.testing.expectEqual(HitResult.heavy, lesser.hit(PARRY_HIT));
    // It is billed once, at the press, and for less than the swing it replaces.
    try std.testing.expect(STAM_PARRY < STAM_HEAVY and STAM_PARRY > 0);
}

test "a small shield holds off the small stuff and CANNOT hold a giant" {
    var s = Stamina{};
    var bites: u32 = 0;
    while (s.cur > 0) : (bites += 1) s.spend(guardStamina(.{ .dmg = 9 }));
    var t = Stamina{};
    var slams: u32 = 0;
    while (t.cur > 0) : (slams += 1) t.spend(guardStamina(.{ .dmg = 36 }));
    try std.testing.expect(bites >= 6);
    try std.testing.expect(slams >= 2 and slams <= 3);
}

test "A FOE'S GUARD IS A SLOW POOL — its own size, and the winded latch holds the shield down" {
    var s = Stamina.initFoe(62);
    try std.testing.expectApproxEqAbs(@as(f32, 62), s.max, 1e-5);
    try std.testing.expect(s.regenRate < 0.5); // a hero-rate foe guard can never be emptied
    // Emptied under a blow it is WINDED, and stays winded well past the frame that emptied it —
    // which is what makes a guard break a real opening instead of a flicker.
    while (s.cur > 0) s.spend(guardStamina(.{ .dmg = 13 }));
    try std.testing.expect(s.winded and !s.canSprint());
    var t: f32 = 0;
    while (t < 1.5) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(s.winded);
    while (t < 20.0) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(!s.winded); // …and it does come back, given the time
    var h = Stamina{};
    try std.testing.expectApproxEqAbs(@as(f32, 1), h.regenRate, 1e-6);
    h.spend(STAM_ROLL);
    h.tick(0.55 + 1.0 / 60.0, false, false);
    h.tick(1.0 / 60.0, false, false);
    try std.testing.expect(h.cur > STAM_MAX - STAM_ROLL);
}

test "the jerky's drip pours its whole meal, and no more" {
    var v = Vitals.init(100, 20, 40);
    _ = v.hit(.{ .dmg = 80 });
    var r = Regen{};
    r.start(60, 20.0);
    try std.testing.expect(r.active());
    var t: f32 = 0;
    while (t < 10.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0, &v);
    try std.testing.expectApproxEqAbs(@as(f32, 50), v.hp, 0.5);
    while (t < 25.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0, &v);
    try std.testing.expectApproxEqAbs(@as(f32, 80), v.hp, 0.5);
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
    try std.testing.expectEqual(@as(u32, 0), r.display());
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 900), r.display());
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
    var f = Flasks{};
    f.cerulean = 0;
    f.cycle();
    try std.testing.expectEqual(FlaskKind.cerulean, f.sel);
    try std.testing.expectEqual(@as(u8, 0), f.ready());
}

test "focus refuses a pour it cannot take, so a full bar never eats a charge" {
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
    try std.testing.expect(FLASK_POUR_AT > 0.2 and FLASK_POUR_AT < 1.0);
}

test "a spread is written by NAME, and lands on the element it names" {
    const e = elems(.{ .fire = 7, .chaos = 3 });
    try std.testing.expectApproxEqAbs(@as(f32, 7), e.at(.fire), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3), e.at(.chaos), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), e.at(.cold), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), e.at(.lightning), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 10), e.total(), 1e-5);
    try std.testing.expect(e.any() and !(Elems{}).any());
    for (0..NELEM) |i| try std.testing.expect(elemName(@enumFromInt(i)).len > 0);
}

test "PHYSICAL IS WHAT WE ALREADY DEAL, and no resistance touches it" {
    // Every blow authored before elements existed is one of these, and its arithmetic must not have moved.
    var v = Vitals.init(100, 20, 40);
    v.res = resists(.{ .fire = 75, .cold = 75, .lightning = 75, .chaos = 75 });
    _ = v.hit(.{ .dmg = 30 });
    try std.testing.expectApproxEqAbs(@as(f32, 70), v.hp, 1e-4);
}

test "a resistance takes its percentage off its OWN element and nothing else" {
    var v = Vitals.init(100, 20, 40);
    v.res = resists(.{ .fire = 50 });
    _ = v.hit(.{ .dmg = 20, .elem = elems(.{ .fire = 40 }) });
    try std.testing.expectApproxEqAbs(@as(f32, 60), v.hp, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 40), v.damageFrom(.{ .elem = elems(.{ .cold = 40 }) }), 1e-4);
}

test "75 IS THE CAP however much is stacked, and the raw number is still there to show" {
    const r = resists(.{ .fire = 140 });
    try std.testing.expectApproxEqAbs(@as(f32, 140), r.raw(.fire), 1e-4);
    try std.testing.expectApproxEqAbs(RES_CAP, r.at(.fire), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 25), r.taken(.fire, 100), 1e-4);
    // A body at the cap and one stacked past it take the same damage — that is what a cap means.
    try std.testing.expectApproxEqAbs(resists(.{ .fire = RES_CAP }).taken(.fire, 100), r.taken(.fire, 100), 1e-4);
}

test "NEGATIVE RESISTANCE AMPLIFIES — that is what makes a fire arrow worth aiming" {
    const dry = resists(.{ .fire = -50 });
    try std.testing.expectApproxEqAbs(@as(f32, 150), dry.taken(.fire, 100), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 200), resists(.{ .fire = -900 }).taken(.fire, 100), 1e-4);
    try std.testing.expectApproxEqAbs(RES_FLOOR, resists(.{ .fire = -900 }).at(.fire), 1e-4);
}

test "the SAME blow costs two creatures different HP, by their resistances alone" {
    const arrow = Hit{ .dmg = 20, .elem = elems(.{ .fire = 20 }) };
    var tinder = Vitals.initFoe(100, 20, 40).withRes(resists(.{ .fire = -50 }));
    var damp = Vitals.initFoe(100, 20, 40).withRes(resists(.{ .fire = 50 }));
    _ = tinder.hit(arrow);
    _ = damp.hit(arrow);
    try std.testing.expectApproxEqAbs(@as(f32, 50), tinder.hp, 1e-4); // 20 + 30
    try std.testing.expectApproxEqAbs(@as(f32, 70), damp.hp, 1e-4); // 20 + 10
    try std.testing.expect(tinder.hp < damp.hp);
    try std.testing.expectApproxEqAbs(@as(f32, 40), arrow.raw(), 1e-4);
}

test "poise and stance are the BLOW's, not the body's — an element cannot buy stagger immunity" {
    var soak = Vitals.init(100, 20, 40).withRes(resists(.{ .fire = RES_CAP }));
    try std.testing.expectEqual(HitResult.light, soak.hit(.{ .poise = 99, .elem = elems(.{ .fire = 50 }) }));
    try std.testing.expect(soak.hp > 80); // most of the fire was shrugged off…
    try std.testing.expect(soak.stunned()); // …and the flinch happened anyway
}

test "the shield eats the WHOLE blow, and the chip meets the resistances on its way through" {
    const burning = Hit{ .dmg = 20, .elem = elems(.{ .fire = 20 }) };
    // Billed on the raw weight: a burning arrow costs more stamina to hold off than a bare one.
    try std.testing.expect(guardStamina(burning) > guardStamina(.{ .dmg = 20 }));
    try std.testing.expectApproxEqAbs(GUARD_STAM_FLAT + GUARD_STAM_PER_DMG * 40.0, guardStamina(burning), 1e-4);
    const chip = guardChip(.{ .dmg = 20, .poise = 44, .stance = 20, .elem = elems(.{ .fire = 20 }) });
    try std.testing.expectApproxEqAbs(20.0 * (1.0 - GUARD_NEGATE), chip.dmg, 1e-4);
    try std.testing.expectApproxEqAbs(20.0 * (1.0 - GUARD_NEGATE), chip.elem.at(.fire), 1e-4);
    // …and NOTHING of the stagger: a caught blow is paid for in stamina, never in poise.
    try std.testing.expectApproxEqAbs(@as(f32, 0), chip.poise, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), chip.stance, 1e-6);
    var proof = Vitals.init(100, 20, 40).withRes(resists(.{ .fire = RES_CAP }));
    var bare = Vitals.init(100, 20, 40);
    _ = proof.hit(chip);
    _ = bare.hit(chip);
    try std.testing.expect(proof.hp > bare.hp);
}

test "a healer, a drip and a corpse are all indifferent to what type killed you" {
    var v = Vitals.initFoe(100, 20, 40).withRes(resists(.{ .cold = -100 }));
    try std.testing.expectEqual(HitResult.death, v.hit(.{ .elem = elems(.{ .cold = 51 }) })); // 102 taken
    try std.testing.expect(v.dead);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.heal(80), 1e-4);
}

test "the quiver holds two kinds, and the SELECTED one is the one that flies" {
    var q = Quiver{};
    try std.testing.expectEqual(ArrowKind.plain, q.sel);
    try std.testing.expectEqual(ARROWS_MAX, q.ready());
    q.cycle();
    try std.testing.expectEqual(ArrowKind.fire, q.sel);
    try std.testing.expectEqual(FIRE_ARROWS_MAX, q.ready());
    try std.testing.expect(q.take());
    try std.testing.expectEqual(FIRE_ARROWS_MAX - 1, q.count(.fire));
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain)); // spending one did NOT touch the other
    // A DRY FIRE QUIVER REFUSES rather than falling back on a plain shaft you did not ask for.
    var i: u8 = 0;
    while (i < FIRE_ARROWS_MAX) : (i += 1) _ = q.take();
    try std.testing.expectEqual(@as(u8, 0), q.ready());
    try std.testing.expect(!q.take());
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    q.cycle();
    try std.testing.expect(q.take()); // …and the plain ones were there all along
    q.add(.fire, 200);
    q.add(.plain, 200);
    try std.testing.expectEqual(FIRE_ARROWS_MAX, q.count(.fire));
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    q.fire = 0;
    q.arrows = 0;
    q.refill();
    try std.testing.expectEqual(FIRE_ARROWS_MAX, q.count(.fire));
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    for (0..2) |_| q.cycle();
    try std.testing.expectEqual(ArrowKind.plain, q.sel); // the cycle is a round trip
}

test "fire arrows are the SCARCE ones" {
    try std.testing.expect(FIRE_ARROWS_MAX < ARROWS_MAX and FIRE_ARROWS_MAX > 0);
    const full = Quiver{};
    for (0..2) |i| {
        const k: ArrowKind = @enumFromInt(i);
        try std.testing.expectEqual(Quiver.cap(k), full.count(k)); // a fresh quiver IS full of both
    }
}

test "the lockout switch is what decides whether an empty pool bites" {
    var s = Stamina{};
    s.spend(STAM_MAX); // bone dry
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    try std.testing.expectEqual(!STAM_LOCKOUT, s.canAct());
}

test "THE QUICK BAR STARTS AS THE TWO FLASKS, so a fresh game plays exactly as it did" {
    const q = Quick{};
    try std.testing.expectEqual(@as(usize, 2), q.filled());
    try std.testing.expectEqual(item.Kind.crimson_flask, q.selected().?);
    try std.testing.expect(q.holds(.cerulean_flask));
    // …and the two of them ARE flasks as far as anything downstream is concerned.
    try std.testing.expectEqual(FlaskKind.crimson, flaskOf(.crimson_flask).?);
    try std.testing.expectEqual(FlaskKind.cerulean, flaskOf(.cerulean_flask).?);
    try std.testing.expectEqual(@as(?FlaskKind, null), flaskOf(.mushroom_jerky));
}

test "the bar cycles what is ON it and skips the holes a removal leaves" {
    var q = Quick{};
    try std.testing.expect(q.add(.mushroom_jerky)); // lands in slot 2
    try std.testing.expect(!q.add(.mushroom_jerky)); // …and never twice: one thing is one row to cycle past
    q.cycle();
    try std.testing.expectEqual(item.Kind.cerulean_flask, q.selected().?);
    q.cycle();
    try std.testing.expectEqual(item.Kind.mushroom_jerky, q.selected().?);
    q.cycle();
    try std.testing.expectEqual(item.Kind.crimson_flask, q.selected().?); // wrapped, having skipped slots 3..9

    // A REMOVAL LEAVES ITS HOLE — the bar is cycled by muscle memory and may not shuffle under a thumb.
    try std.testing.expect(q.remove(.cerulean_flask));
    try std.testing.expectEqual(item.Kind.crimson_flask, q.slots[0].?);
    try std.testing.expectEqual(@as(?item.Kind, null), q.slots[1]);
    try std.testing.expectEqual(item.Kind.mushroom_jerky, q.slots[2].?);
    q.cycle();
    try std.testing.expectEqual(item.Kind.mushroom_jerky, q.selected().?);
}

test "taking off what the bar was TURNED TO lands the selection on something real" {
    var q = Quick{};
    try std.testing.expect(q.remove(.crimson_flask)); // the one it was on
    try std.testing.expectEqual(item.Kind.cerulean_flask, q.selected().?);
    try std.testing.expect(q.remove(.cerulean_flask));
    try std.testing.expectEqual(@as(?item.Kind, null), q.selected()); // an empty bar is empty, not stale
}

test "the bar is CAPPED, and a full one refuses rather than dropping what is on it" {
    var q = Quick{};
    var k: usize = 0;
    while (q.filled() < QUICK_SLOTS) : (k += 1) {
        q.slots[q.filled()] = .bloodgrass; // straight in: there are not ten quickable kinds to add
    }
    try std.testing.expectEqual(QUICK_SLOTS, q.filled());
    try std.testing.expect(!q.add(.mushroom_jerky));
    try std.testing.expectEqual(item.Kind.crimson_flask, q.selected().?); // and nothing was evicted for it
}

test "THE BAR SHEDS WHAT HE HAS RUN OUT OF, and never a flask" {
    var bag = item.Bag{};
    bag.add(.mushroom_jerky, 1);
    var q = Quick{};
    try std.testing.expect(q.add(.mushroom_jerky));
    q.dropEmpty(&bag);
    try std.testing.expect(q.holds(.mushroom_jerky)); // he still has one

    _ = bag.take(.mushroom_jerky, 1);
    q.dropEmpty(&bag);
    try std.testing.expect(!q.holds(.mushroom_jerky)); // …and now he does not
    // AN EMPTY FLASK STAYS ON. Its charges come back at a grace, so it is still what he is carrying —
    // dropped here, the bar would have to be re-loaded at every bonfire.
    try std.testing.expect(q.holds(.crimson_flask) and q.holds(.cerulean_flask));
    try std.testing.expectEqual(@as(u16, 0), bag.count(.crimson_flask)); // and the bag has never held one
}

test "…and shedding the row it was TURNED TO lands the selection on something real" {
    var bag = item.Bag{};
    bag.add(.mushroom_jerky, 1);
    var q = Quick{};
    q.slots[0] = null; // a bar carrying nothing but the edible
    q.slots[1] = null;
    q.slots[2] = .mushroom_jerky;
    q.sel = 2;
    _ = bag.take(.mushroom_jerky, 1);
    q.dropEmpty(&bag);
    try std.testing.expectEqual(@as(?item.Kind, null), q.selected());
    try std.testing.expectEqual(@as(usize, 0), q.filled());
}
