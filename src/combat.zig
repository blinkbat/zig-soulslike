const std = @import("std");
const mathx = @import("mathx.zig");
const stats = @import("stats.zig");
const item = @import("item.zig");


pub const StunKind = enum { none, light, heavy };

pub const HitResult = enum { none, light, heavy, death };

pub const HitOutcome = enum { ignored, taken, blocked, guardBroken };


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

/// A number per element, WRITTEN BY NAME — damage on a `Hit`, percent on a `Resists`. Field names are
/// matched against the enum at comptime, so a rename is a compile error and an omitted element is a 0;
/// an array literal would silently shift when the enum gains a fifth.
pub const Spread = struct { fire: f32 = 0, cold: f32 = 0, lightning: f32 = 0, chaos: f32 = 0 };

fn pack(s: Spread) [NELEM]f32 {
    var out = [_]f32{0} ** NELEM;
    inline for (@typeInfo(Elem).@"enum".fields) |f| out[f.value] = @field(s, f.name);
    return out;
}

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
    pub fn plus(self: Elems, other: Elems) Elems {
        var out = self;
        for (&out.v, other.v) |*x, y| x.* += y;
        return out;
    }
};

pub fn elems(s: Spread) Elems {
    return .{ .v = pack(s) };
}

/// PoE2's MAXIMUM RESISTANCE: 75%, however much is stacked on top.
pub const RES_CAP: f32 = 75.0;
pub const RES_FLOOR: f32 = -100.0;

pub const Resists = struct {
    v: [NELEM]f32 = [_]f32{0} ** NELEM,

    pub fn raw(self: Resists, e: Elem) f32 {
        return self.v[@intFromEnum(e)];
    }
    pub fn at(self: Resists, e: Elem) f32 {
        return mathx.clampF(self.raw(e), RES_FLOOR, RES_CAP);
    }
    pub fn taken(self: Resists, e: Elem, amt: f32) f32 {
        return amt * (1.0 - self.at(e) / 100.0);
    }
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
    dmg: f32 = 0,
    poise: f32 = 0,
    stance: f32 = 0,
    elem: Elems = .{},
    fp: f32 = 0,

    /// THE WHOLE BLOW BEFORE ANYBODY'S RESISTANCES — what a shield's stamina bill and "which of two blows
    /// was worse" are measured on, since those are about weight rather than about what you resist.
    pub fn raw(self: Hit) f32 {
        return self.dmg + self.elem.total();
    }

    pub fn heavy(self: Hit) bool {
        return self.stance > 0;
    }

    pub fn throughArmour(self: Hit, a: f32) Hit {
        var out = self;
        out.dmg = armourTaken(a, self.dmg);
        return out;
    }

    pub fn scaled(self: Hit, k: f32) Hit {
        return .{
            .dmg = self.dmg * k,
            .poise = self.poise * k,
            .stance = self.stance * k,
            .elem = self.elem.scaled(k),
            .fp = self.fp * k,
        };
    }
};

const REGEN_DELAY = 0.8;
const POISE_REFILL = 1.3;
const STANCE_REFILL = 4.6;
const LIGHT_BREAK_STANCE = 0.40;
const FOE_REGEN_DELAY = 2.2;
const FOE_REGEN_RATE = 0.45;
pub const LIGHT_STUN_DUR = 0.46;
pub const HEAVY_STUN_DUR = 1.15;
pub const FOE_LIGHT_STUN_DUR = 0.78;
pub const FOE_HEAVY_STUN_DUR = 2.40;

pub fn foeStunDur(heavy: bool) f32 {
    return if (heavy) FOE_HEAVY_STUN_DUR else FOE_LIGHT_STUN_DUR;
}

pub fn heroStunDur(heavy: bool) f32 {
    return if (heavy) HEAVY_STUN_DUR else LIGHT_STUN_DUR;
}

const LONG_AGO = mathx.LONG_AGO;


pub const Vitals = struct {
    hp: f32,
    hpMax: f32,
    poise: f32,
    poiseMax: f32,
    stance: f32,
    stanceMax: f32,
    sinceHit: f32 = LONG_AGO,
    sinceHurt: f32 = LONG_AGO,
    dead: bool = false,
    regenDelay: f32 = REGEN_DELAY,
    regenRate: f32 = 1.0,
    poiseRate: f32 = 1.0,
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

    pub fn withRes(self: Vitals, r: Resists) Vitals {
        var v = self;
        v.res = r;
        return v;
    }

    pub fn damageFrom(self: *const Vitals, h: Hit) f32 {
        return h.dmg + self.res.takenAll(h.elem);
    }

    pub fn stunned(self: *const Vitals) bool {
        return self.stunLeft > 0;
    }

    pub fn revive(self: *Vitals, frac: f32) void {
        self.dead = false;
        self.hp = mathx.maxF(1.0, self.hpMax * mathx.clampF(frac, 0, 1));
        self.poise = self.poiseMax;
        self.stance = self.stanceMax;
        self.stunLeft = 0;
        self.sinceHit = LONG_AGO;
        self.sinceHurt = LONG_AGO;
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
            if (self.stunLeft <= 0) {
                self.stunLeft = 0;
                self.poise = self.poiseMax;
            }
        }
        if (self.dead or self.sinceHit < self.regenDelay) return;
        self.poise = mathx.minF(self.poiseMax, self.poise + self.poiseMax / POISE_REFILL * self.regenRate * self.poiseRate * dt);
        self.stance = mathx.minF(self.stanceMax, self.stance + self.stanceMax / STANCE_REFILL * self.regenRate * dt);
    }

    /// A DRIP — damage billed EVERY FRAME by something that holds (`Root`), as opposed to a blow. `hit` in
    /// every respect but the REGEN CLOCK: stamped afresh every frame for a whole `ROOT_HOLD`, `sinceHit`
    /// never opens the poise/stance refill, so a grip carrying no poise would deny most of a poise bar
    /// anyway. `sinceHurt` IS stamped, so the bar shows it. Poise-free drips only.
    pub fn drip(self: *Vitals, h: Hit) HitResult {
        const clock = self.sinceHit;
        const r = self.hit(h);
        self.sinceHit = clock;
        return r;
    }

    pub fn hit(self: *Vitals, h: Hit) HitResult {
        if (self.dead) return .none;
        self.sinceHurt = 0;
        self.hp = mathx.maxF(0, self.hp - self.damageFrom(h));
        if (self.hp <= 0) {
            self.dead = true;
            return .death;
        }
        self.sinceHit = 0;
        self.stance -= h.stance;
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
            self.beginStun(.heavy);
            return .heavy;
        }
        if (light) {
            self.beginStun(.light);
            return .light;
        }
        return .none;
    }
};

// ER's shallow, fast-refilling pool (docs/ELDEN_RING.md §3 — its Endurance-15 numbers): a flat bite per
// action, pouring back ~4x as fast as a roll spends it, so it paces a FLURRY and not a whole fight.
pub const STAM_MAX = stats.staminaFor(stats.START); // 105 — ENDURANCE owns the pool size now (`stats.zig`); about eight rolls from full
pub const STAM_ROLL = 12.0;
pub const STAM_LIGHT = 10.0;
pub const STAM_HEAVY = 16.0;
pub const STAM_SHOT = 8.0;
pub const STAM_AIMED = 18.0;
pub const STAM_SPRINT = 9.0;
const STAM_REGEN = 45.0;
const STAM_DELAY = 0.55;
pub const STAM_REFUSE_FLASH: f32 = 0.35;

pub const STAM_LOCKOUT = true;

pub const STAM_WIND_CLEAR: f32 = 0.5;

pub const FOE_STAM_RATE: f32 = 0.26;

pub const Stamina = struct {
    cur: f32 = STAM_MAX,
    max: f32 = STAM_MAX,
    sinceSpend: f32 = LONG_AGO,
    winded: bool = false,
    regenRate: f32 = 1.0,
    /// THE TOADFLESH BROTH — the refill runs `brew.amount`× while its clock runs. One clock, refreshed
    /// never stacked (the status law); it speeds the trickle and touches nothing else, so the delay,
    /// the winded latch and the panic rule all mean what they always did.
    brew: Timed = .{},

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
        self.brew.tick(dt);
        if (sprinting) {
            self.cur = mathx.maxF(0, self.cur - STAM_SPRINT * dt);
            self.sinceSpend = 0;
        } else {
            self.sinceSpend += dt;
            if (!committed and self.sinceSpend >= STAM_DELAY) {
                self.cur = mathx.minF(self.max, self.cur + STAM_REGEN * self.regenRate * self.brew.value(1.0) * dt);
            }
        }
        self.settleWind();
    }

    pub fn startBrew(self: *Stamina, mult: f32, secs: f32) void {
        self.brew.start(mult, secs);
    }

    pub fn windedTo(self: *const Stamina) f32 {
        return if (self.canSprint()) 0 else STAM_WIND_CLEAR;
    }

    pub fn secondWind(self: *Stamina, share: f32) void {
        self.cur = mathx.minF(self.max, self.cur + self.max * share);
        self.sinceSpend = 0;
        self.settleWind();
    }

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
        self.brew.reset();
    }
};

pub const GUARD_NEGATE: f32 = 0.85;
pub const GUARD_STAM_FLAT: f32 = 5.0;
pub const GUARD_STAM_PER_DMG: f32 = 1.10;
pub const GUARD_ARC: f32 = 65.0;

pub fn withinGuardArc(bearing: f32, facing: f32) bool {
    return withinArc(bearing, facing, GUARD_ARC);
}

pub fn withinArc(bearing: f32, facing: f32, arc: f32) bool {
    return @abs(mathx.degrees(mathx.wrapPi(bearing - facing))) <= arc;
}

/// **HOW WIDE A THING OF HALF-WIDTH `half` IS FROM `dist` AWAY** — degrees, `withinArc`'s own unit, so an arc
/// test can be widened by the width of the body it is testing rather than by a fudge. The knight's door
/// against his own axis, the rime cone against a giant's flank and the ogre's sweep against the man's own
/// radius are one triangle written three ways; this is the one way.
pub fn subtendedArc(half: f32, dist: f32) f32 {
    return mathx.degrees(std.math.atan2(half, mathx.maxF(dist, 1e-4)));
}

pub fn guardStamina(h: Hit) f32 {
    return GUARD_STAM_FLAT + GUARD_STAM_PER_DMG * h.raw();
}
/// WHAT GETS THROUGH — still a `Hit`, so the chip's elemental share meets the blocker's resistances instead of arriving as raw HP. DAMAGE ONLY: poise and stance are what the shield is FOR, and a chip that carried the blow's stagger through would flinch him behind his own guard.
/// **ARMOUR — THE FIFTH COLUMN, AND IT IS A CURVE AND NOT A PERCENTAGE.** PoE2's own, and the shape AGENTS.md
/// reserved for the day armour landed: `A/(A + 5*dmg)` of a blow is turned aside, so the same coat is worth a
/// fifth of a middling blow and a tenth of the one that was going to kill you. That is why armour can never
/// become immunity however much of it is stacked, and why it needs no cap of its own the way a resistance does.
///
/// **PHYSICAL ONLY.** The four elements have `Resists`; this is the thing they were always the other half of.
/// **AND IT TOUCHES NEITHER POISE NOR STANCE** — those belong to the BLOW and not to the body it lands on, which
/// is `guardChip`'s law and the reason a coat cannot make him harder to stagger.
pub fn armourTaken(a: f32, dmg: f32) f32 {
    if (a <= 0 or dmg <= 0) return dmg;
    return dmg * (1.0 - a / (a + 5.0 * dmg));
}

/// **A BOARD MAY NEVER STOP A BLOW OUTRIGHT** — the chip is the entire reason a guard is not a wall, and with a
/// shield ROW (`item.Arm.negate`) multiplying the base and a tree node adding to it, the two could sum past 1
/// and make blocking free. `guardChip` clamps at 1; this stops it ever getting there.
pub const GUARD_NEGATE_CAP: f32 = 0.95;

pub fn guardChip(h: Hit, negate: f32) Hit {
    const k = 1.0 - mathx.clampF(negate, 0, 1);
    return .{ .dmg = h.dmg * k, .elem = h.elem.scaled(k), .fp = h.fp * k };
}


pub const STAM_PARRY: f32 = 9.0;
/// WHAT THE BOARDS DEAL WHEN THEY CATCH: nothing to the health, everything to the FOOTING. No `dmg`, because a
/// parry has never been damage — the punish after it is. And NO POISE either, so a catch can never resolve as
/// a mere flinch: it breaks the stance or it does not, which is the owner's "may heavy stun them" read off the
/// same bar the sword has been chipping. Sized so the ogre's 90 stance takes two catches and lighter takes one.
pub const PARRY_HIT = Hit{ .stance = 46 };

pub const FP_MAX = stats.fpFor(stats.START);

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
    /// difference is deliberate: the bottom of the stamina bar buys a roll you cannot afford because that is the
    /// genre's most important move, where a half-paid spell would be a spell that half exists (ER's rule too).
    pub fn spend(self: *Focus, amt: f32) bool {
        if (self.cur < amt) return false;
        self.cur -= amt;
        return true;
    }
    pub fn drain(self: *Focus, amt: f32) void {
        self.cur = mathx.maxF(0, self.cur - amt);
    }
    pub fn reset(self: *Focus) void {
        self.cur = self.max;
    }
};


pub const SpiritKind = enum { wolf };

/// The spirit a scroll IS, or null. `item.zig` cannot answer this — it imports nothing but std, and this is
/// the same split `flaskOf` keeps: the ITEM is a fact about the bag, the KIND is a fact about the mechanic.
pub fn spiritOf(k: item.Kind) ?SpiritKind {
    return switch (k) {
        .spirit_scroll_wolf => .wolf,
        else => null,
    };
}

pub fn scrollFor(s: SpiritKind) item.Kind {
    return switch (s) {
        .wolf => .spirit_scroll_wolf,
    };
}

pub fn spiritFp(s: SpiritKind) f32 {
    return switch (s) {
        .wolf => 30.0,
    };
}

pub fn spiritName(s: SpiritKind) [:0]const u8 {
    return switch (s) {
        .wolf => "Hildebrand",
    };
}

pub const SUMMON_MAX: usize = 1;


pub const BOLT_HIT = Hit{ .poise = 14, .stance = 6, .elem = elems(.{ .chaos = 25 }) };

pub const ROOT_HOLD: f32 = 3.5;
pub const ROOT_DPS: f32 = 5.6;
pub const ROOT_R: f32 = 2.6;
pub const ROOT_GRIP_R: f32 = 1.0;

pub const Root = struct {
    left: f32 = 0,

    pub fn held(self: *const Root) bool {
        return self.left > 0;
    }
    pub fn grab(self: *Root) void {
        self.left = ROOT_HOLD;
    }
    pub fn release(self: *Root) void {
        self.left = 0;
    }
    pub fn tick(self: *Root, dt: f32) ?Hit {
        if (self.left <= 0) return null;
        const step = minF(dt, self.left);
        self.left -= step;
        return .{ .elem = elems(.{ .chaos = ROOT_DPS * step }) };
    }
};

/// THE RIME BREATH — the rod's third sorcery, and **THE FIRST THING IN THE GAME THAT REACHES MORE THAN ONE
/// BODY WITHOUT BEING A SWING** (owner's call; it overturns the no-area-spells law — see AGENTS.md). A CONE
/// poured out of him for `RIME_DUR`, not a blast at a mark, so its area is a thing he aims and holds and a
/// body walks out of it the way a body walks out of a swing.
pub const RIME_DUR: f32 = 0.85;
pub const RIME_REACH: f32 = 6.0;
pub const RIME_ARC: f32 = 30.0;
pub const RIME_DPS: f32 = 18.0;

pub const CHILL_HOLD: f32 = 4.0;
/// WHAT A CHILLED BODY'S TRAVEL IS MULTIPLIED BY. **The feet, and nothing else** — `Root`'s own law, which
/// this is the partial case of: the state machine still runs, the kit still swings at its own speed and the
/// blows land as hard. A chilled thing is not a slowed thing, it is a thing that cannot close.
pub const CHILL_TRAVEL: f32 = 0.55;

comptime {
    // IT COSTS MORE THAN THE ROOTS AND DEALS LESS, which is the whole shape of it: reach across a field is
    // what it sells, and it may not also be the better single-target spell. The PRICE half of that pair now
    // lives in the `SPELLS` ladder's own monotonicity assert; this is the half about the two DRIPS, which is
    // the comparison that table cannot make for itself.
    std.debug.assert(RIME_DUR * RIME_DPS < ROOT_HOLD * ROOT_DPS);
    std.debug.assert(CHILL_HOLD > 3.0 * RIME_DUR);
    std.debug.assert(CHILL_TRAVEL > 0 and CHILL_TRAVEL < 1);
    std.debug.assert(RIME_ARC > GUARD_ARC * 0.4 and RIME_ARC < 45.0);
}

pub const Chill = struct {
    left: f32 = 0,
    owed: f32 = 0,

    pub fn held(self: *const Chill) bool {
        return self.left > 0;
    }
    pub fn breathe(self: *Chill, dt: f32) void {
        self.left = CHILL_HOLD;
        self.owed += RIME_DPS * dt;
    }
    pub fn touch(self: *Chill) void {
        self.left = CHILL_HOLD;
    }
    pub fn release(self: *Chill) void {
        self.left = 0;
        self.owed = 0;
    }
    /// The bite owed this frame, or null. A DRIP and never a blow — no poise and no stance, `Root.tick`'s
    /// reason: a cone that flinched would flinch everything in front of him at once.
    pub fn tick(self: *Chill, dt: f32) ?Hit {
        self.left = maxF(0, self.left - dt);
        if (self.owed <= 0) return null;
        const bite = elems(.{ .cold = self.owed });
        self.owed = 0;
        return .{ .elem = bite };
    }
    pub fn travel(self: *const Chill) f32 {
        return if (self.left > 0) CHILL_TRAVEL else 1.0;
    }
    pub fn frac(self: *const Chill) f32 {
        return mathx.clampF(self.left / CHILL_HOLD, 0, 1);
    }
};

/// **THE TWO THAT DO NOT CROSS THE GROUND.** The bolt is a stone thrown through the arrow pool and the rime is
/// a cone he holds; these two arrive on ONE named body on the frame they are cast, so what they need is not a
/// speed but a REACH and an ARC to find that body inside.
///
/// **HOW FAR OFF HIS FACING ONE WILL TAKE A BODY WITH NOTHING LOCKED.** Narrower than the rime cone's 30 on
/// purpose: that spell is a wash poured over whatever is in front of him, and these are aimed at somebody.
pub const STRIKE_ARC: f32 = 22.0;

/// **THE LEVIN STRIKE — the rod's fourth, and the one that does not travel.** Lightning's own signature in
/// `elemfx` is the fastest and shortest-lived in the table — a spark is dead before it arrives — so a bolt of
/// it sailing across six metres of field as a thrown stone would be the one spell whose picture argues with
/// its element. What it sells is the INTERRUPT: the heaviest poise anything the hero owns carries, bought with
/// damage that is deliberately middling.
/// POISE PAST EVERY CREATURE'S OWN `POISE_MAX` BAR THE BONE KNIGHT'S 78 (the ogre's 30 is the highest of the
/// rest), so one cast flinches anything that is not a boss — where his own heavy swing at 22 flinches the
/// toads and leaves the giants standing. The STANCE is deliberately UNDER that swing's 14: a spell thrown from
/// across the room may not be the better guard-breaker than a stroke committed inside reach.
pub const LEVIN_HIT = Hit{ .poise = 34, .stance = 10, .elem = elems(.{ .lightning = 22 }) };
/// Well past the roots' 7 m throw, since nothing has to cross the ground to get there, and far short of the
/// bolt's 55: an interrupt thrown from outside the fight is not an interrupt.
pub const LEVIN_REACH: f32 = 16.0;

pub const SIPHON_HIT = Hit{ .elem = elems(.{ .chaos = 18 }) };
pub const SIPHON_SHARE: f32 = 0.55;
pub const SIPHON_REACH: f32 = 12.0;

/// **THE EMBER LANCE — the rod's sixth, and the first FIRE anywhere on his side of the fight.** Every other
/// element he owns has a spell (chaos twice, cold, lightning) and fire had none: it arrived only as an arrow
/// he had to have fletched or a candle he had to have found, while the newest creature in the wood throws it
/// at him. And it is the only one that does not stop at the first body — a LANCE goes THROUGH, so what it is
/// for is a line of them: the muster shoulder to shoulder, a warband, a ring of mages.
/// PER BODY, and deliberately small — it is priced where the rime is, because it is the rime's kind of spell:
/// what the focus buys is the SECOND body and the third, never the number on the first. Poise under the
/// levin's 34 (that spell's whole sale is the interrupt) and over a hero light's, so a line of small things
/// is a line of small things that all flinch at once.
pub const LANCE_HIT = Hit{ .poise = 18, .stance = 6, .elem = elems(.{ .fire = 16.5 }) };
pub const LANCE_REACH: f32 = 20.0;
pub const LANCE_R: f32 = 0.55;

/// **SUNDER — the seventh, and the rod's answer to a SHIELD.** Stance is the bar that decides whether a guard
/// holds, and until now the only thing that moved it in any quantity was a committed stroke inside reach: the
/// shieldman, the greatsword and the knight are all fights a caster simply had no tool for.
///
/// **AND IT IS CAST IN MELEE RANGE ON PURPOSE** (`SUNDER_REACH`, inside a sword's own). `LEVIN_HIT`'s note is
/// the law it keeps: a spell thrown from across the room may not be the better guard-breaker than a stroke
/// committed inside reach. So it carries a parry's worth of stance and you have to be standing there to spend it.
/// PHYSICAL, and NO ELEMENT — a sundering blow is a mass arriving, and every element in the table already has
/// a spell. The damage is the lowest of the seven, which is the ladder's own rule paying for the stance.
pub const SUNDER_HIT = Hit{ .dmg = 14, .poise = 12, .stance = 40 };
/// INSIDE THE SWORD'S OWN REACH (`game.MELEE_AIM_R` is 3.6). This is the one sorcery that is not a way to
/// avoid being in the fight.
pub const SUNDER_REACH: f32 = 4.0;

pub const Spell = enum { bolt, roots, rime, levin, siphon, lance, sunder };

pub const SpellRow = struct {
    spell: Spell,
    name: [:0]const u8,
    fp: f32,
    blow: ?Hit = null,
    reach: ?f32 = null,
    drip: f32 = 0,
};

/// **THE ROD'S SEVEN, AS ONE TABLE YOU CAN READ DOWN.** It was five switches over `Spell` and seven loose
/// `*_FP` constants scattered through the file, so retuning one spell meant five edits in four places and a
/// missed one still compiled. The FP column is the LADDER — read it top to bottom and the price list is the
/// whole design, which is what the monotonicity assert below is checking.
///
/// **ROW ORDER IS `Spell`'S OWN**, pinned at comptime: an eighth spell is a compile error here until it has
/// said what it costs and what it does. The MECHANICS each one is made of (`ROOT_HOLD`, `RIME_ARC`, `LANCE_R`,
/// `SIPHON_SHARE`…) stay up beside their own spell — this is the price, not the physics.
pub const SPELLS = [_]SpellRow{
    .{ .spell = .bolt,   .name = "Chaos Bolt",   .fp = 8,  .blow = BOLT_HIT },
    .{ .spell = .roots,  .name = "Roots",        .fp = 12, .drip = ROOT_HOLD * ROOT_DPS },
    .{ .spell = .rime,   .name = "Rime Breath",  .fp = 15, .drip = RIME_DUR * RIME_DPS },
    .{ .spell = .levin,  .name = "Levin Strike", .fp = 11, .blow = LEVIN_HIT,  .reach = LEVIN_REACH },
    .{ .spell = .siphon, .name = "Siphon",       .fp = 13, .blow = SIPHON_HIT, .reach = SIPHON_REACH },
    .{ .spell = .lance,  .name = "Ember Lance",  .fp = 14, .blow = LANCE_HIT,  .reach = LANCE_REACH },
    .{ .spell = .sunder, .name = "Sunder",       .fp = 16, .blow = SUNDER_HIT, .reach = SUNDER_REACH },
};

comptime {
    if (SPELLS.len != @typeInfo(Spell).@"enum".fields.len) @compileError("combat: SPELLS is not one row per Spell");
    for (SPELLS, 0..) |row, i| {
        if (@intFromEnum(row.spell) != i) @compileError("combat: SPELLS row " ++ row.name ++ " is out of `Spell` order");
        if ((row.blow == null) != (row.drip > 0)) @compileError("combat: " ++ row.name ++ " has no worth, or two");
    }
}

pub fn rowFor(s: Spell) SpellRow {
    return SPELLS[@intFromEnum(s)];
}

pub fn spellName(s: Spell) [:0]const u8 {
    return rowFor(s).name;
}

/// WHAT EACH ONE BILLS. One place, so the HUD's "could he cast?" and the cast itself cannot disagree.
pub fn spellFp(s: Spell) f32 {
    return rowFor(s).fp;
}

pub fn spellBlow(s: Spell) ?Hit {
    return rowFor(s).blow;
}

pub fn spellReach(s: Spell) ?f32 {
    return rowFor(s).reach;
}

pub fn spellDamage(s: Spell) f32 {
    const row = rowFor(s);
    return if (row.blow) |b| b.raw() else row.drip;
}

pub const BOLT_FP: f32 = spellFp(.bolt);

comptime {
    // **THE LADDER IS MONOTONE, AND THAT IS THE WHOLE PRICE LIST**: 8→25, 11→22, 12→19.6, 13→18, 14→16.5,
    // 15→15.3, 16→14. **AND EVERY RUNG NOW CLEARS A FREE LIGHT SWING** (`hero.ATK_LIGHT_HIT`, 13) — five of
    // the seven used to sit under it while costing a third of the pool, which is a rod nobody would draw. Every
    // step up in FP is a step DOWN in raw damage, because what the difference buys is never damage — it is a
    // stagger, a hold, a mouthful of HP back, or a second body in the cone. Asserted over every PAIR rather
    // than against a written-out order, so a sixth spell is priced by this rule without editing it, and the
    // three hand-written comparisons this replaces (rime > roots > bolt, both ways round) cannot drift apart.
    for (std.enums.values(Spell)) |a| {
        for (std.enums.values(Spell)) |b| {
            if (spellFp(a) < spellFp(b)) std.debug.assert(spellDamage(a) > spellDamage(b));
        }
    }
    // …and every one of them is castable off a full pool, or the sheet's Mind curve promises what it cannot pay.
    for (std.enums.values(Spell)) |s| std.debug.assert(spellFp(s) > 0 and spellFp(s) <= FP_MAX);
}

test "the chill outlives the breath, refreshes rather than stacks, and lets go on its own" {
    var c = Chill{};
    try std.testing.expect(!c.held());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), c.travel(), 1e-4);

    c.breathe(1.0 / 60.0);
    try std.testing.expect(c.held());
    try std.testing.expectApproxEqAbs(CHILL_TRAVEL, c.travel(), 1e-4);

    const bite = c.tick(0).?;
    try std.testing.expect(bite.elem.at(.cold) > 0);
    try std.testing.expect(bite.dmg == 0 and bite.poise == 0 and bite.stance == 0);
    try std.testing.expect(c.tick(0) == null);

    var t: f32 = 0;
    while (t < CHILL_HOLD * 0.5) : (t += 0.05) _ = c.tick(0.05);
    c.breathe(0.05);
    _ = c.tick(0);
    try std.testing.expectApproxEqAbs(CHILL_HOLD, c.left, 1e-3);

    t = 0;
    while (t < CHILL_HOLD + 0.2) : (t += 0.05) _ = c.tick(0.05);
    try std.testing.expect(!c.held());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), c.travel(), 1e-4);
}

test "the whole pour bills less than the roots' grip, and a body resists it as COLD" {
    var billed: f32 = 0;
    var c = Chill{};
    var t: f32 = 0;
    while (t < RIME_DUR) : (t += 1.0 / 60.0) {
        c.breathe(1.0 / 60.0);
        if (c.tick(1.0 / 60.0)) |bite| billed += bite.elem.at(.cold);
    }
    try std.testing.expectApproxEqAbs(RIME_DUR * RIME_DPS, billed, RIME_DUR * RIME_DPS * 0.03);
    try std.testing.expect(billed < ROOT_HOLD * ROOT_DPS);

    var res = Resists{};
    res.v[@intFromEnum(Elem.cold)] = 75;
    var warm = Vitals.initFoe(100, 100, 100);
    var cold = Vitals.initFoe(100, 100, 100).withRes(res);
    _ = warm.drip(.{ .elem = elems(.{ .cold = 10 }) });
    _ = cold.drip(.{ .elem = elems(.{ .cold = 10 }) });
    try std.testing.expect(cold.hp > warm.hp);
}

pub const FlaskKind = enum { crimson, cerulean };

pub const FLASK_CRIMSON: u8 = 2;
pub const FLASK_CERULEAN: u8 = 1;
pub const FLASK_HP_FRAC: f32 = 0.45;
pub const FLASK_FP_FRAC: f32 = 0.50;
pub const FLASK_DRINK_DUR: f32 = 1.05;
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

pub fn flaskOf(k: item.Kind) ?FlaskKind {
    return switch (k) {
        .crimson_flask => .crimson,
        .cerulean_flask => .cerulean,
        else => null,
    };
}

pub fn quickCount(k: item.Kind, flasks: *const Flasks, bag: *const item.Bag) u8 {
    if (flaskOf(k)) |f| return flasks.charges(f);
    return @intCast(@min(bag.count(k), 99));
}

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
    pub fn add(self: *Quick, k: item.Kind) bool {
        if (self.holds(k)) return false;
        for (&self.slots, 0..) |*s, i| {
            if (s.* != null) continue;
            s.* = k;
            if (self.slots[self.sel] == null) self.sel = i;
            return true;
        }
        return false;
    }

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
    pub fn cycle(self: *Quick) void {
        for (1..QUICK_SLOTS + 1) |step| {
            const i = (self.sel + step) % QUICK_SLOTS;
            if (self.slots[i] == null) continue;
            self.sel = i;
            return;
        }
    }
    pub fn dropEmpty(self: *Quick, bag: *const item.Bag) void {
        for (&self.slots) |*s| {
            const k = s.* orelse continue;
            if (flaskOf(k) != null) continue;
            if (bag.count(k) == 0) s.* = null;
        }
        if (self.slots[self.sel] == null) self.settle();
    }

    fn settle(self: *Quick) void {
        for (self.slots, 0..) |s, i| {
            if (s == null) continue;
            self.sel = i;
            return;
        }
        self.sel = 0;
    }
};

pub const ARROWS_MAX: u8 = 10;
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
    pub fn cycle(self: *Quiver) void {
        self.sel = switch (self.sel) {
            .plain => .fire,
            .fire => .plain,
        };
    }
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



pub const POISON_MAX: f32 = 100.0;
pub const POISON_DECAY_DELAY: f32 = 1.1;
pub const POISON_DECAY: f32 = 24.0;
pub const POISON_DUR: f32 = 14.0;
pub const POISON_HP_FRAC: f32 = 0.26;

pub const Status = struct {
    meter: f32 = 0,
    on: bool = false,
    sinceDose: f32 = LONG_AGO,
    /// A ONE-FRAME EDGE (`justDied`'s idiom): the frame it went off, for the beat that says so.
    justProcced: bool = false,

    pub fn frac(self: *const Status) f32 {
        return mathx.clampF(self.meter / POISON_MAX, 0, 1);
    }
    pub fn active(self: *const Status) bool {
        return self.on;
    }
    pub fn add(self: *Status, amt: f32) void {
        if (self.on or amt <= 0) return;
        self.meter = minF(POISON_MAX, self.meter + amt);
        self.sinceDose = 0;
    }
    pub fn tick(self: *Status, dt: f32, hpMax: f32) f32 {
        self.justProcced = false;
        if (self.on) {
            self.meter = maxF(0, self.meter - POISON_MAX / POISON_DUR * dt);
            if (self.meter <= 0) {
                self.* = .{};
                return 0;
            }
            return hpMax * POISON_HP_FRAC / POISON_DUR * dt;
        }
        self.sinceDose += dt;
        if (self.meter >= POISON_MAX) {
            self.on = true;
            self.justProcced = true;
            self.meter = POISON_MAX;
            return 0;
        }
        if (self.sinceDose >= POISON_DECAY_DELAY) self.meter = maxF(0, self.meter - POISON_DECAY * dt);
        return 0;
    }
    pub fn reset(self: *Status) void {
        self.* = .{};
    }
};

pub fn poisonPulse(amt: f32) Hit {
    return .{ .elem = elems(.{ .chaos = amt }) };
}

test "POISON IS CHAOS — the ward and the node that name it actually answer it" {
    const pulse = poisonPulse(10);
    try std.testing.expectEqual(@as(f32, 0), pulse.dmg);
    try std.testing.expectApproxEqAbs(@as(f32, 10), pulse.elem.at(.chaos), 1e-5);
    try std.testing.expectEqual(@as(f32, 0), pulse.poise);
    try std.testing.expectEqual(@as(f32, 0), pulse.stance);

    var bare = Vitals.init(200, 99, 999);
    try std.testing.expectApproxEqAbs(@as(f32, 10), bare.damageFrom(pulse), 1e-4);
    var warded = Vitals.init(200, 99, 999).withRes(resists(.{ .chaos = 40 }));
    try std.testing.expectApproxEqAbs(@as(f32, 6), warded.damageFrom(pulse), 1e-4);
    var stacked = Vitals.init(200, 99, 999).withRes(resists(.{ .chaos = 400 }));
    try std.testing.expectApproxEqAbs(10.0 * (1.0 - RES_CAP / 100.0), stacked.damageFrom(pulse), 1e-4);
    try std.testing.expect(stacked.damageFrom(pulse) > 0);
}

pub const Timed = struct {
    amount: f32 = 0,
    left: f32 = 0,

    pub fn on(self: *const Timed) bool {
        return self.left > 0;
    }
    /// What it is worth this frame — `off` while nothing is running, so the caller never writes the gate.
    pub fn value(self: *const Timed, off: f32) f32 {
        return if (self.left > 0) self.amount else off;
    }
    /// REFRESHED, NEVER STACKED (the status law): a second dose sets the clock, it does not add to it.
    pub fn start(self: *Timed, amount: f32, secs: f32) void {
        self.amount = amount;
        self.left = secs;
    }
    pub fn tick(self: *Timed, dt: f32) void {
        self.left = maxF(0, self.left - dt);
    }
    pub fn reset(self: *Timed) void {
        self.* = .{};
    }
};

test "a timed effect REFRESHES rather than stacking, and reads as `off` once its clock is out" {
    var t = Timed{};
    try std.testing.expect(!t.on());
    try std.testing.expectEqual(@as(f32, 1.0), t.value(1.0));
    t.start(1.5, 2.0);
    t.tick(1.0);
    t.start(1.5, 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), t.left, 1e-6); // …set, never 3.0
    t.tick(2.5);
    try std.testing.expectEqual(@as(f32, 0), t.left);
    try std.testing.expect(!t.on());
    try std.testing.expectEqual(@as(f32, 1.0), t.value(1.0));
}

pub const Regen = struct {
    left: f32 = 0,
    rate: f32 = 0,

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

pub const SOUL_ROLL_RATE = 7.0;
pub const SOUL_ROLL_FLOOR = 26.0;

pub const Souls = struct {
    total: u32 = 0,
    shown: f32 = 0,

    pub fn gain(self: *Souls, n: u32) void {
        self.total += n;
    }

    pub fn dropAll(self: *Souls) u32 {
        const had = self.total;
        self.total = 0;
        self.shown = 0;
        return had;
    }

    pub fn tick(self: *Souls, dt: f32) void {
        const goal: f32 = @floatFromInt(self.total);
        if (self.shown >= goal) {
            self.shown = goal;
            return;
        }
        self.shown = minF(goal, self.shown + maxF((goal - self.shown) * SOUL_ROLL_RATE, SOUL_ROLL_FLOOR) * dt);
    }

    pub fn display(self: *const Souls) u32 {
        return @intFromFloat(@floor(maxF(self.shown, 0)));
    }
};

const minF = mathx.minF;
const maxF = mathx.maxF;

test "POISON: the meter fills, PROCS, and the same meter drains as the clock" {
    var s = Status{};
    try std.testing.expect(!s.active() and s.frac() == 0);
    s.add(POISON_MAX - 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.tick(1.0 / 60.0, 70), 1e-6);
    try std.testing.expect(!s.active() and s.frac() > 0.9);
    s.add(5.0);
    _ = s.tick(1.0 / 60.0, 70);
    try std.testing.expect(s.active() and s.justProcced);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), s.frac(), 1e-4);
    _ = s.tick(1.0 / 60.0, 70);
    try std.testing.expect(!s.justProcced);

    var paid: f32 = 0;
    var t: f32 = 1.0 / 30.0;
    while (t < POISON_DUR * 1.2) : (t += 1.0 / 60.0) paid += s.tick(1.0 / 60.0, 70);
    try std.testing.expect(!s.active());
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.frac(), 1e-6);
    try std.testing.expectApproxEqAbs(70.0 * POISON_HP_FRAC, paid, 0.5);
}

test "POISON CANNOT BE RE-APPLIED WHILE IT RUNS — a state you are already in, not a burst" {
    var s = Status{};
    s.add(POISON_MAX);
    _ = s.tick(1.0 / 60.0, 70);
    try std.testing.expect(s.active());
    var t: f32 = 0;
    while (t < POISON_DUR * 0.5) : (t += 1.0 / 60.0) _ = s.tick(1.0 / 60.0, 70);
    const half = s.frac();
    for (0..40) |_| s.add(POISON_MAX);
    try std.testing.expectApproxEqAbs(half, s.frac(), 1e-5);
    while (t < POISON_DUR + 0.2) : (t += 1.0 / 60.0) _ = s.tick(1.0 / 60.0, 70);
    try std.testing.expect(!s.active());
    s.add(20.0);
    try std.testing.expect(s.frac() > 0.15);
}

test "LINGERING IS THE COST: the meter decays once the doses stop" {
    var s = Status{};
    s.add(POISON_MAX * 0.7);
    var t: f32 = 0;
    while (t < POISON_DECAY_DELAY * 0.5) : (t += 1.0 / 60.0) _ = s.tick(1.0 / 60.0, 70);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), s.frac(), 1e-3);
    while (t < POISON_DECAY_DELAY + POISON_MAX / POISON_DECAY + 0.2) : (t += 1.0 / 60.0) _ = s.tick(1.0 / 60.0, 70);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.frac(), 1e-6);
    try std.testing.expect(!s.active());
    // SPACED DOSES NEVER PROC (ER's own point): half a bar, wait it off, half a bar again.
    var spaced = Status{};
    for (0..6) |_| {
        spaced.add(POISON_MAX * 0.45);
        var u: f32 = 0;
        while (u < POISON_DECAY_DELAY + POISON_MAX / POISON_DECAY) : (u += 1.0 / 60.0) _ = spaced.tick(1.0 / 60.0, 70);
        try std.testing.expect(!spaced.active());
    }
}

test "the roots hold for their span, bill chaos the whole way, and let go on their own" {
    var r = Root{};
    try std.testing.expect(!r.held());
    try std.testing.expect(r.tick(1.0 / 60.0) == null);
    r.grab();
    try std.testing.expect(r.held());
    var paid: f32 = 0;
    var t: f32 = 0;
    while (t < ROOT_HOLD * 2.0) : (t += 1.0 / 60.0) {
        if (r.tick(1.0 / 60.0)) |h| paid += h.raw();
    }
    try std.testing.expect(!r.held());
    try std.testing.expectApproxEqAbs(ROOT_HOLD * ROOT_DPS, paid, 1e-3);
}

test "the grip is ALL CHAOS and carries no stagger — a hold is not a flinch" {
    var r = Root{};
    r.grab();
    const h = r.tick(0.5).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.dmg, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.poise, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.stance, 1e-6);
    try std.testing.expectApproxEqAbs(ROOT_DPS * 0.5, h.elem.at(.chaos), 1e-5);
    var chitin = Vitals.initFoe(100, 20, 40).withRes(resists(.{ .chaos = RES_CAP }));
    var bare = Vitals.initFoe(100, 20, 40);
    try std.testing.expectEqual(HitResult.none, chitin.hit(h));
    _ = bare.hit(h);
    try std.testing.expect(chitin.hp > bare.hp);
}

test "THE GRIP DOES NOT DENY THE REFILL — a drip bills HP and leaves the regen clock alone" {
    // Billed through `hit`, the bite re-stamps `sinceHit` every frame and the gate never opens, so a foe held
    // for its whole span comes out of the roots with the poise it went in with. That is a stagger tool.
    var held = Vitals.initFoe(100, 20, 40);
    var loose = Vitals.initFoe(100, 20, 40);
    for ([_]*Vitals{ &held, &loose }) |v| _ = v.hit(.{ .poise = 15 });
    var r = Root{};
    r.grab();
    var t: f32 = 0;
    while (t < ROOT_HOLD) : (t += 1.0 / 60.0) {
        if (r.tick(1.0 / 60.0)) |bite| _ = held.drip(bite);
        held.tick(1.0 / 60.0);
        loose.tick(1.0 / 60.0);
    }
    try std.testing.expectApproxEqAbs(loose.poise, held.poise, 1e-3);
    try std.testing.expect(held.poise > 5.5);
    try std.testing.expect(held.hp < loose.hp);
    try std.testing.expect(held.sinceHurt < 1.0 / 30.0);
    try std.testing.expect(loose.sinceHurt > ROOT_HOLD - 0.1);
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
    try std.testing.expect(spellFp(.rime) > spellFp(.roots));
    try std.testing.expect(spellDamage(.rime) < spellDamage(.roots));
    try std.testing.expect(spellFp(.roots) > spellFp(.bolt));
    try std.testing.expect(ROOT_GRIP_R < ROOT_R);
    try std.testing.expect(ROOT_HOLD * ROOT_DPS < BOLT_HIT.raw());
    try std.testing.expect(spellFp(.roots) <= FP_MAX);
    for (0..@typeInfo(Spell).@"enum".fields.len) |i| {
        const s: Spell = @enumFromInt(i);
        try std.testing.expect(spellName(s).len > 0);
        try std.testing.expect(spellFp(s) > 0);
        try std.testing.expect(spellDamage(s) > 0);
    }
    try std.testing.expect(spellDamage(.roots) < spellDamage(.bolt));
}

test "THE LEVIN BUYS THE STAGGER AND NOTHING ELSE — the heaviest poise the hero owns, at middling damage" {
    try std.testing.expect(spellFp(.levin) > spellFp(.bolt) and spellFp(.levin) < spellFp(.roots));
    try std.testing.expect(spellDamage(.levin) < spellDamage(.bolt));
    try std.testing.expect(LEVIN_HIT.poise > 30.0);
    try std.testing.expect(LEVIN_HIT.poise < 78.0);
    try std.testing.expect(LEVIN_HIT.stance > 0 and LEVIN_HIT.stance < 14.0);
    try std.testing.expectApproxEqAbs(LEVIN_HIT.raw(), LEVIN_HIT.elem.at(.lightning), 1e-4);
    try std.testing.expect(LEVIN_HIT.dmg == 0);
    try std.testing.expect(LEVIN_REACH > ROOT_R and LEVIN_REACH < 55.0);
}

test "THE SIPHON FEEDS OFF WHAT IT ACTUALLY TOOK, so a body that resists chaos is a bad meal" {
    try std.testing.expect(SIPHON_HIT.poise == 0 and SIPHON_HIT.stance == 0);
    try std.testing.expect(SIPHON_HIT.dmg == 0);
    try std.testing.expect(spellFp(.siphon) > spellFp(.levin) and spellFp(.siphon) < spellFp(.rime));
    try std.testing.expect(SIPHON_REACH < LEVIN_REACH);

    var bare = Vitals.initFoe(100, 20, 40);
    var boned = Vitals.initFoe(100, 20, 40).withRes(resists(.{ .chaos = RES_CAP }));
    const off_bare = bare.damageFrom(SIPHON_HIT);
    const off_boned = boned.damageFrom(SIPHON_HIT);
    try std.testing.expect(off_bare > off_boned * 3.9); // 75% resisted is a quarter of the meal
    try std.testing.expect(off_bare * SIPHON_SHARE < off_bare);
    // The heal is what a body actually lost, so it cannot outrun the damage even at full share.
    try std.testing.expect(SIPHON_SHARE > 0 and SIPHON_SHARE < 1);
}

test "a small hit chips poise without a stun" {
    var v = Vitals.init(100, 20, 40);
    try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 5, .poise = 8 }));
    try std.testing.expectApproxEqAbs(@as(f32, 95), v.hp, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 12), v.poise, 1e-5);
}

test "emptying poise triggers a light stun and resets poise" {
    var v = Vitals.init(100, 20, 100);
    _ = v.hit(.{ .poise = 12 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 12 }));
    try std.testing.expectApproxEqAbs(@as(f32, 20), v.poise, 1e-5);
    try std.testing.expect(v.stance < v.stanceMax);
}

test "enough light breaks cascade into a heavy stun (keep pressure on)" {
    var v = Vitals.init(100, 10, 20);
    var heavies: u32 = 0;
    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        if (v.hit(.{ .poise = 6 }) == .heavy) heavies += 1;
        while (v.stunned()) v.tick(1.0 / 60.0);
    }
    try std.testing.expect(heavies >= 1);
}

test "NOBODY IS POISE-DAMAGED WHILE REELING, and poise is full again when the stun ends" {
    var v = Vitals.init(100, 20, 500);
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
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .poise = 99 }));
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
    v.poise = 3;
    try std.testing.expectEqual(HitResult.heavy, v.hit(.{ .poise = 1, .stance = 30 }));
    try std.testing.expect(v.poise < v.poiseMax);
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
    var v = Vitals.init(100, 50, 30);
    _ = v.hit(.{ .poise = 1, .stance = 20 });
    try std.testing.expectEqual(HitResult.heavy, v.hit(.{ .poise = 1, .stance = 20 }));
}

test "lethal damage returns death and latches dead" {
    var v = Vitals.init(30, 20, 40);
    try std.testing.expectEqual(HitResult.death, v.hit(.{ .dmg = 40, .poise = 99 }));
    try std.testing.expect(v.dead);
    try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 40 }));
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
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.heal(50), 1e-4);
    var d = Vitals.initFoe(100, 20, 40);
    try std.testing.expectEqual(HitResult.death, d.hit(.{ .dmg = 200 }));
    try std.testing.expectApproxEqAbs(@as(f32, 0), d.heal(80), 1e-4);
    try std.testing.expect(d.dead and d.hp <= 0);
    try std.testing.expect(!d.needsHeal(1.0));
}

test "regen waits out the delay, then refills; HP never regens" {
    var v = Vitals.init(100, 20, 40);
    _ = v.hit(.{ .dmg = 10, .poise = 15 });
    v.tick(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 5), v.poise, 1e-5);
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) v.tick(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(v.poiseMax, v.poise, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 90), v.hp, 1e-5);
}

test "a foe's chip damage PERSISTS far longer than the hero's" {
    var hero = Vitals.init(100, 20, 40);
    var foeV = Vitals.initFoe(100, 20, 40);
    _ = hero.hit(.{ .poise = 15 });
    _ = foeV.hit(.{ .poise = 15 });
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) {
        hero.tick(1.0 / 60.0);
        foeV.tick(1.0 / 60.0);
    }
    try std.testing.expectApproxEqAbs(hero.poiseMax, hero.poise, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 5), foeV.poise, 1e-3);
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
    s.tick(0.5, false, false);
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
    try std.testing.expect(!s.canAct());
    try std.testing.expect(!s.canSprint());
    var t: f32 = 0;
    while (t < STAM_DELAY + 0.05) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(s.canAct());
}

test "running the bar dry costs the sprint until it is back to half" {
    var s = Stamina{};
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
    s.spend(STAM_ROLL);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    try std.testing.expect(!s.canAct());
}

test "a roll chain costs the sum of its rolls — the refill cannot pay for it" {
    var s = Stamina{};
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        s.spend(STAM_ROLL);
        var t: f32 = 0;
        while (t < 0.70) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, true);
    }
    try std.testing.expectApproxEqAbs(STAM_MAX - 3 * STAM_ROLL, s.cur, 1e-3);
}

test "sprinting bleeds the pool and holds the refill off" {
    var s = Stamina{};
    var t: f32 = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, true, false);
    try std.testing.expectApproxEqAbs(STAM_MAX - STAM_SPRINT, s.cur, 0.2);
    s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(s.cur < STAM_MAX - STAM_SPRINT + 0.2);
}

test "a swing PAUSES the refill rather than draining it" {
    var s = Stamina{};
    s.spend(STAM_HEAVY);
    const after = s.cur;
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, true);
    try std.testing.expectApproxEqAbs(after, s.cur, 1e-4);
}

test "the pool refills far faster than any one action drains it" {
    try std.testing.expect(STAM_REGEN > 2.0 * STAM_HEAVY);
    try std.testing.expect(STAM_HEAVY > STAM_LIGHT and STAM_LIGHT < STAM_ROLL);
    try std.testing.expect(STAM_MAX / STAM_ROLL > 6.0);
}

test "the small shield costs stamina by the WEIGHT of the blow, and lets a little through" {
    const teeth = Hit{ .dmg = 9, .poise = 7 };
    const club = Hit{ .dmg = 36, .poise = 44, .stance = 20 };
    try std.testing.expect(guardStamina(club) > 2.5 * guardStamina(teeth));
    try std.testing.expect(guardStamina(club) < 4.0 * guardStamina(teeth));
    try std.testing.expect(guardChip(club, GUARD_NEGATE).dmg > 3.0 and guardChip(club, GUARD_NEGATE).dmg < 0.25 * club.dmg);
}

test "THE PARRY REFUSES A BLOW, and whether it staggers is the STANCE BAR's answer" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), PARRY_HIT.raw(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), PARRY_HIT.poise, 1e-6);
    try std.testing.expect(PARRY_HIT.stance > 0);
    const ogreStance: f32 = 90.0;
    var giant = Vitals.initFoe(300, 30, ogreStance);
    try std.testing.expectEqual(HitResult.none, giant.hit(PARRY_HIT));
    try std.testing.expectEqual(HitResult.heavy, giant.hit(PARRY_HIT));
    var lesser = Vitals.initFoe(60, 12, 40);
    try std.testing.expectEqual(HitResult.heavy, lesser.hit(PARRY_HIT));
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
    try std.testing.expect(s.regenRate < 0.5);
    while (s.cur > 0) s.spend(guardStamina(.{ .dmg = 13 }));
    try std.testing.expect(s.winded and !s.canSprint());
    var t: f32 = 0;
    while (t < 1.5) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(s.winded);
    while (t < 20.0) : (t += 1.0 / 60.0) s.tick(1.0 / 60.0, false, false);
    try std.testing.expect(!s.winded);
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
    try std.testing.expectApproxEqAbs(@as(f32, 100), v.hp, 1e-3);
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

test "souls roll UP to a kill's payout and never overshoot it" {
    var r = Souls{};
    r.gain(900);
    try std.testing.expectEqual(@as(u32, 900), r.total);
    try std.testing.expectEqual(@as(u32, 0), r.display());
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 900), r.display());
    var r2 = Souls{};
    r2.gain(60);
    t = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) {
        r2.tick(1.0 / 60.0);
        try std.testing.expect(r2.display() <= r2.total);
    }
    try std.testing.expectEqual(@as(u32, 60), r2.display());
}

test "a soul payout mid-roll retargets instead of restarting" {
    var r = Souls{};
    r.gain(120);
    var t: f32 = 0;
    while (t < 0.15) : (t += 1.0 / 60.0) r.tick(1.0 / 60.0);
    const mid = r.display();
    try std.testing.expect(mid > 0 and mid < 120);
    r.gain(120);
    try std.testing.expectEqual(@as(u32, 240), r.total);
    try std.testing.expect(r.display() >= mid);
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
    try std.testing.expect(!f.take());
    f.sel = .cerulean;
    try std.testing.expectEqual(FLASK_CERULEAN, f.ready());
    try std.testing.expect(f.take());
    f.refill();
    try std.testing.expectEqual(FLASK_CERULEAN, f.ready());
    f.sel = .crimson;
    try std.testing.expectEqual(FLASK_CRIMSON, f.ready());
}

test "focus refuses a pour it cannot take, so a full bar never eats a charge" {
    var fp = Focus{};
    try std.testing.expect(!fp.restore(10));
    fp.cur = 10;
    try std.testing.expect(fp.restore(FP_MAX * FLASK_FP_FRAC));
    try std.testing.expectApproxEqAbs(@as(f32, 40), fp.cur, 1e-4);
    try std.testing.expect(fp.restore(FP_MAX));
    try std.testing.expectApproxEqAbs(FP_MAX, fp.cur, 1e-4);
}

test "the flask heals a real bite of the bar, and the pour lands inside the commitment" {
    try std.testing.expect(FLASK_HP_FRAC > 0.25 and FLASK_HP_FRAC < 0.75);
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
    try std.testing.expectApproxEqAbs(@as(f32, 50), tinder.hp, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 70), damp.hp, 1e-4);
    try std.testing.expect(tinder.hp < damp.hp);
    try std.testing.expectApproxEqAbs(@as(f32, 40), arrow.raw(), 1e-4);
}

test "poise and stance are the BLOW's, not the body's — an element cannot buy stagger immunity" {
    var soak = Vitals.init(100, 20, 40).withRes(resists(.{ .fire = RES_CAP }));
    try std.testing.expectEqual(HitResult.light, soak.hit(.{ .poise = 99, .elem = elems(.{ .fire = 50 }) }));
    try std.testing.expect(soak.hp > 80);
    try std.testing.expect(soak.stunned());
}

test "the shield eats the WHOLE blow, and the chip meets the resistances on its way through" {
    const burning = Hit{ .dmg = 20, .elem = elems(.{ .fire = 20 }) };
    try std.testing.expect(guardStamina(burning) > guardStamina(.{ .dmg = 20 }));
    try std.testing.expectApproxEqAbs(GUARD_STAM_FLAT + GUARD_STAM_PER_DMG * 40.0, guardStamina(burning), 1e-4);
    const chip = guardChip(.{ .dmg = 20, .poise = 44, .stance = 20, .elem = elems(.{ .fire = 20 }) }, GUARD_NEGATE);
    try std.testing.expectApproxEqAbs(20.0 * (1.0 - GUARD_NEGATE), chip.dmg, 1e-4);
    try std.testing.expectApproxEqAbs(20.0 * (1.0 - GUARD_NEGATE), chip.elem.at(.fire), 1e-4);
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
    try std.testing.expectEqual(HitResult.death, v.hit(.{ .elem = elems(.{ .cold = 51 }) }));
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
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    var i: u8 = 0;
    while (i < FIRE_ARROWS_MAX) : (i += 1) _ = q.take();
    try std.testing.expectEqual(@as(u8, 0), q.ready());
    try std.testing.expect(!q.take());
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    q.cycle();
    try std.testing.expect(q.take());
    q.add(.fire, 200);
    q.add(.plain, 200);
    try std.testing.expectEqual(FIRE_ARROWS_MAX, q.count(.fire));
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    q.fire = 0;
    q.arrows = 0;
    q.refill();
    try std.testing.expectEqual(FIRE_ARROWS_MAX, q.count(.fire));
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    for (0..NARROW) |_| q.cycle();
    try std.testing.expectEqual(ArrowKind.plain, q.sel);
}

/// How many kinds the quiver holds — off the enum, so a third arrow moves the round trip and the walk below
/// with it rather than leaving two tests asserting a 2 that stopped being the count.
const NARROW = @typeInfo(ArrowKind).@"enum".fields.len;

test "fire arrows are the SCARCE ones" {
    try std.testing.expect(FIRE_ARROWS_MAX < ARROWS_MAX and FIRE_ARROWS_MAX > 0);
    const full = Quiver{};
    for (0..NARROW) |i| {
        const k: ArrowKind = @enumFromInt(i);
        try std.testing.expectEqual(Quiver.cap(k), full.count(k));
    }
}

test "the lockout switch is what decides whether an empty pool bites" {
    var s = Stamina{};
    s.spend(STAM_MAX);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.cur, 1e-4);
    try std.testing.expectEqual(!STAM_LOCKOUT, s.canAct());
}

test "THE QUICK BAR STARTS AS THE TWO FLASKS, so a fresh game plays exactly as it did" {
    const q = Quick{};
    try std.testing.expectEqual(@as(usize, 2), q.filled());
    try std.testing.expectEqual(item.Kind.crimson_flask, q.selected().?);
    try std.testing.expect(q.holds(.cerulean_flask));
    try std.testing.expectEqual(FlaskKind.crimson, flaskOf(.crimson_flask).?);
    try std.testing.expectEqual(FlaskKind.cerulean, flaskOf(.cerulean_flask).?);
    try std.testing.expectEqual(@as(?FlaskKind, null), flaskOf(.mushroom_jerky));
}

test "the bar cycles what is ON it and skips the holes a removal leaves" {
    var q = Quick{};
    try std.testing.expect(q.add(.mushroom_jerky));
    try std.testing.expect(!q.add(.mushroom_jerky));
    q.cycle();
    try std.testing.expectEqual(item.Kind.cerulean_flask, q.selected().?);
    q.cycle();
    try std.testing.expectEqual(item.Kind.mushroom_jerky, q.selected().?);
    q.cycle();
    try std.testing.expectEqual(item.Kind.crimson_flask, q.selected().?);

    try std.testing.expect(q.remove(.cerulean_flask));
    try std.testing.expectEqual(item.Kind.crimson_flask, q.slots[0].?);
    try std.testing.expectEqual(@as(?item.Kind, null), q.slots[1]);
    try std.testing.expectEqual(item.Kind.mushroom_jerky, q.slots[2].?);
    q.cycle();
    try std.testing.expectEqual(item.Kind.mushroom_jerky, q.selected().?);
}

test "taking off what the bar was TURNED TO lands the selection on something real" {
    var q = Quick{};
    try std.testing.expect(q.remove(.crimson_flask));
    try std.testing.expectEqual(item.Kind.cerulean_flask, q.selected().?);
    try std.testing.expect(q.remove(.cerulean_flask));
    try std.testing.expectEqual(@as(?item.Kind, null), q.selected());
}

test "the bar is CAPPED, and a full one refuses rather than dropping what is on it" {
    var q = Quick{};
    var k: usize = 0;
    while (q.filled() < QUICK_SLOTS) : (k += 1) {
        q.slots[q.filled()] = .bloodgrass;
    }
    try std.testing.expectEqual(QUICK_SLOTS, q.filled());
    try std.testing.expect(!q.add(.mushroom_jerky));
    try std.testing.expectEqual(item.Kind.crimson_flask, q.selected().?);
}

test "THE BAR SHEDS WHAT HE HAS RUN OUT OF, and never a flask" {
    var bag = item.Bag{};
    bag.add(.mushroom_jerky, 1);
    var q = Quick{};
    try std.testing.expect(q.add(.mushroom_jerky));
    q.dropEmpty(&bag);
    try std.testing.expect(q.holds(.mushroom_jerky));

    _ = bag.take(.mushroom_jerky, 1);
    q.dropEmpty(&bag);
    try std.testing.expect(!q.holds(.mushroom_jerky));
    try std.testing.expect(q.holds(.crimson_flask) and q.holds(.cerulean_flask));
    try std.testing.expectEqual(@as(u16, 0), bag.count(.crimson_flask));
}

test "…and shedding the row it was TURNED TO lands the selection on something real" {
    var bag = item.Bag{};
    bag.add(.mushroom_jerky, 1);
    var q = Quick{};
    q.slots[0] = null;
    q.slots[1] = null;
    q.slots[2] = .mushroom_jerky;
    q.sel = 2;
    _ = bag.take(.mushroom_jerky, 1);
    q.dropEmpty(&bag);
    try std.testing.expectEqual(@as(?item.Kind, null), q.selected());
    try std.testing.expectEqual(@as(usize, 0), q.filled());
}
