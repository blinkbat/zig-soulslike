const std = @import("std");
const mathx = @import("../core/mathx.zig");
const stats = @import("stats.zig");
const item = @import("item.zig");


pub const StunKind = enum { none, light, heavy };

pub const Side = enum { hero, foe };

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

/// A number per element, WRITTEN BY NAME. Field names are matched against the enum at comptime, so a rename is a compile error and an omitted element is a 0; an array literal would silently shift on a fifth.
pub const Spread = struct { fire: f32 = 0, cold: f32 = 0, lightning: f32 = 0, chaos: f32 = 0 };

comptime {
    const mine = @typeInfo(Elem).@"enum".fields;
    const theirs = @typeInfo(item.ElemName).@"enum".fields;
    if (mine.len != theirs.len) @compileError("combat: item.ElemName is not the four elements");
    for (mine, theirs) |a, b| {
        if (a.value != b.value or !std.mem.eql(u8, a.name, b.name))
            @compileError("combat: item.ElemName." ++ b.name ++ " does not line up with Elem." ++ a.name);
    }
}

pub fn elemOf(n: item.ElemName) Elem {
    return @enumFromInt(@intFromEnum(n));
}

pub fn resistsOf(r: item.Res) Resists {
    return resists(.{ .fire = r.fire, .cold = r.cold, .lightning = r.lightning, .chaos = r.chaos });
}

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
    launch: f32 = 0,
    dose: Doses = .{},
    gore: f32 = 0,

    /// THE WHOLE BLOW BEFORE ANYBODY'S RESISTANCES — what a shield's stamina bill and "which of two blows was worse" are measured on.
    pub fn raw(self: Hit) f32 {
        return self.dmg + self.elem.total() + self.gore;
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
            .launch = self.launch,
            .dose = self.dose,
            .gore = self.gore,
        };
    }
};

/// Named at the call site (`Doses.one(.poison, 26)`) rather than through a ten-field spread.
pub const Doses = struct {
    v: [NAIL]f32 = [_]f32{0} ** NAIL,

    pub fn one(a: Ail, amt: f32) Doses {
        var out = Doses{};
        out.v[@intFromEnum(a)] = amt;
        return out;
    }
    pub fn at(self: Doses, a: Ail) f32 {
        return self.v[@intFromEnum(a)];
    }
    pub fn any(self: Doses) bool {
        for (self.v) |x| {
            if (x > 0) return true;
        }
        return false;
    }
};

const REGEN_DELAY = 0.8;
const POISE_REFILL = 1.3;
const STANCE_REFILL = 4.6;
/// **THE ROAD FROM REPEATED LIGHT TO A HEAVY STAGGER** — the share of STANCE one flinch bills, so at 0.40 the
/// third flinch inside the stance window IS the break. Per body (`Vitals.breakShare`): a global share made
/// every creature in the game stagger on the same three, with no way to author one that flinches like paper
/// and still will not go down to flinches alone (0), or one the count comes for quickly.
pub const LIGHT_BREAK_STANCE: f32 = 0.40;
const FOE_REGEN_DELAY = 2.2;
const FOE_REGEN_RATE = 0.45;
pub const LIGHT_STUN_DUR = 0.46;
pub const HEAVY_STUN_DUR = 1.15;
pub const FOE_LIGHT_STUN_DUR: f32 = 0.78;
pub const FOE_HEAVY_STUN_DUR: f32 = 2.40;

pub fn foeStunDur(heavy: bool) f32 {
    return if (heavy) FOE_HEAVY_STUN_DUR else FOE_LIGHT_STUN_DUR;
}

/// `poiseMax` IS the damage it shrugs off inside the window — the knight's 78 against a 900 bar, a kobold's 12.
/// 0.82 puts his base blows on the old scale: 13 damage pours 10.7 where the light swing carried 10 poise, and
/// 27 pours 22.1 where the heavy carried 22.
pub var FOE_POISE_PER_DMG: f32 = 0.82;
/// **YOU CANNOT DO ONE THING OVER AND OVER** (owner). Each light stun, heavy stun and status proc on a creature
/// leaves WEAR on that channel: the next takes (1 + wear × this) as much. Wear halves every `WEAR_HALFLIFE`.
pub const LIGHT_WEAR: f32 = 0.60;
pub const HEAVY_WEAR: f32 = 0.60;
pub const AIL_WEAR: f32 = 0.70;
pub const WEAR_HALFLIFE: f32 = 14.0;

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
    breakShare: f32 = LIGHT_BREAK_STANCE,
    stunLeft: f32 = 0,
    stunAs: StunKind = .none,
    lightStun: f32 = LIGHT_STUN_DUR,
    heavyStun: f32 = HEAVY_STUN_DUR,
    res: Resists = .{},
    armour: f32 = 0,
    ails: [NAIL]Status = [_]Status{.{}} ** NAIL,
/// How fast each meter fills on this body: the hero's perks and what he is wearing, 1 for a creature.
    ailRate: [NAIL]f32 = [_]f32{1} ** NAIL,
    side: Side = .hero,
    lightWear: f32 = 0,
    heavyWear: f32 = 0,
    ailWear: [NAIL]f32 = [_]f32{0} ** NAIL,

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
        v.side = .foe;
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
        return armourTaken(self.armour, h.dmg) + self.res.takenAll(h.elem) + h.gore;
    }

    pub fn ail(self: *const Vitals, a: Ail) *const Status {
        return &self.ails[@intFromEnum(a)];
    }
    pub fn ailFrac(self: *const Vitals, a: Ail) f32 {
        return self.ails[@intFromEnum(a)].frac(ailRow(a));
    }
    pub fn ailOn(self: *const Vitals, a: Ail) bool {
        return self.ails[@intFromEnum(a)].on;
    }
    pub fn ailProcced(self: *const Vitals, a: Ail) bool {
        return self.ails[@intFromEnum(a)].justProcced;
    }
    pub fn ailEnded(self: *const Vitals, a: Ail) bool {
        return self.ails[@intFromEnum(a)].justEnded;
    }
    pub fn ailRateOf(self: *const Vitals, a: Ail) f32 {
        return self.ailRate[@intFromEnum(a)];
    }

    pub fn bears(self: *const Vitals, a: Ail) bool {
        return switch (ailRow(a).bearer) {
            .both => true,
            .hero => self.side == .hero,
            .foe => self.side == .foe,
        };
    }

    pub fn build(self: *Vitals, a: Ail, amt: f32) void {
        if (amt <= 0 or self.dead or !self.bears(a)) return;
        if (a == .stun and self.stunned()) return;
        const i = @intFromEnum(a);
        const wear = if (self.side == .foe) 1.0 + AIL_WEAR * self.ailWear[i] else 1.0;
        self.ails[i].add(ailRow(a), amt * self.ailRate[i] / wear);
    }

    pub fn clearAils(self: *Vitals) void {
        self.ails = [_]Status{.{}} ** NAIL;
    }

    pub fn travelMult(self: *const Vitals) f32 {
        var k: f32 = 1;
        if (self.ailOn(.chill)) k *= CHILL_TRAVEL;
        if (self.ailOn(.stupefy)) k *= STUPEFY_TRAVEL;
        if (self.ailOn(.berserk)) k *= BERSERK_TRAVEL;
        return k;
    }

    pub fn dmgMult(self: *const Vitals) f32 {
        return if (self.ailOn(.berserk)) BERSERK_DMG else 1.0;
    }

/// What its own attack and cast CLOCKS are divided by — its own clocks, never the world's.
    pub fn hasteMult(self: *const Vitals) f32 {
        return if (self.ailOn(.berserk)) BERSERK_HASTE else 1.0;
    }

    pub fn focusMult(self: *const Vitals) f32 {
        return if (self.ailOn(.stupefy)) STUPEFY_FOCUS else 1.0;
    }

    pub fn asleep(self: *const Vitals) bool {
        return self.ailOn(.sleep);
    }

    pub fn wake(self: *Vitals) void {
        self.ails[@intFromEnum(Ail.sleep)] = .{};
    }

    pub fn withArmour(self: Vitals, a: f32) Vitals {
        var out = self;
        out.armour = a;
        return out;
    }

    pub fn withBreak(self: Vitals, share: f32) Vitals {
        var out = self;
        out.breakShare = mathx.maxF(share, 0);
        return out;
    }

    /// Flinches from a full bar to the stagger, which is what the share MEANS. 0 is a body the count never comes for.
    /// Saturating: a hand-edited share of 1e-30 is 1e30 flinches, and that is an out-of-range `@intFromFloat`.
    pub fn flinchesToBreak(self: *const Vitals) u32 {
        if (self.breakShare <= 0) return 0;
        return @intFromFloat(mathx.minF(@ceil(1.0 / self.breakShare), 1e9));
    }

    pub fn stunned(self: *const Vitals) bool {
        return self.stunLeft > 0;
    }

    /// **WHICH STAGGER IS IN FLIGHT** — STORED, because it cannot be recovered from the bars: `hit` refills `stance` to full on the frame it breaks, so a `stance <= 0` test for "was that the heavy one" is never true.
    pub fn stunHeavy(self: *const Vitals) bool {
        return self.stunAs == .heavy;
    }

    pub fn revive(self: *Vitals, frac: f32) void {
        self.dead = false;
        self.hp = mathx.maxF(1.0, self.hpMax * mathx.clampF(frac, 0, 1));
        self.poise = self.poiseMax;
        self.stance = self.stanceMax;
        self.stunLeft = 0;
        self.stunAs = .none;
        self.sinceHit = LONG_AGO;
        self.sinceHurt = LONG_AGO;
        self.clearAils();
    }

    pub fn beginStun(self: *Vitals, kind: StunKind) void {
        self.stunAs = kind;
        self.stunLeft = switch (kind) {
            .none => 0,
            .light => self.lightStun,
            .heavy => self.heavyStun,
        };
    }

    pub fn refuseFlinch(self: *Vitals, poiseWas: f32) void {
        self.poise = poiseWas;
        self.stance = mathx.minF(self.stanceMax, self.stance + self.breakShare * self.stanceMax);
        self.beginStun(.none);
        if (self.lightWear >= 1) self.lightWear -= 1;
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
        if (!self.dead and self.asleep()) {
            self.stunAs = .heavy;
            self.stunLeft = self.heavyStun;
        }
        if (self.stunLeft > 0) {
            self.stunLeft -= dt;
            if (self.stunLeft <= 0) {
                self.stunLeft = 0;
                self.stunAs = .none;
                self.poise = self.poiseMax;
            }
        }
        const wearK = std.math.pow(f32, 0.5, dt / WEAR_HALFLIFE);
        self.lightWear *= wearK;
        self.heavyWear *= wearK;
        for (&self.ailWear) |*w| w.* *= wearK;
        if (self.dead or self.sinceHit < self.regenDelay) return;
        self.poise = mathx.minF(self.poiseMax, self.poise + self.poiseMax / POISE_REFILL * self.regenRate * self.poiseRate * dt);
        self.stance = mathx.minF(self.stanceMax, self.stance + self.stanceMax / STANCE_REFILL * self.regenRate * dt);
    }

    pub fn drip(self: *Vitals, h: Hit) HitResult {
        const clock = self.sinceHit;
        const r = self.strike(h, false);
        self.sinceHit = clock;
        return r;
    }

    pub fn tickAils(self: *Vitals, dt: f32) bool {
        var owed = Hit{};
        var any = false;
        for (&self.ails, 0..) |*s, i| {
            const row = AILS[i];
            const due = s.tick(row, dt, self.hpMax);
            if (s.justProcced) self.ailWear[i] += 1;
            if (due <= 0) continue;
            const pulse = ailPulse(row, due);
            owed.elem = owed.elem.plus(pulse.elem);
            owed.gore += pulse.gore;
            any = true;
        }
        if (!any or self.dead) return false;
        return self.drip(owed) == .death;
    }

    pub fn hit(self: *Vitals, h: Hit) HitResult {
        return self.strike(h, true);
    }

    fn strike(self: *Vitals, h: Hit, builds: bool) HitResult {
        if (self.dead) return .none;
        self.sinceHurt = 0;
        const taken = self.damageFrom(h);
        self.hp = mathx.maxF(0, self.hp - taken);
        if (self.hp <= 0) {
            self.dead = true;
            return .death;
        }
        self.sinceHit = 0;
        if (builds) {
            self.wake();
            for (h.dose.v, 0..) |amt, i| self.build(@enumFromInt(i), amt);
            for (h.elem.v, 0..) |amt, i| {
                if (amt == 0) continue;
                const e: Elem = @enumFromInt(i);
                self.build(ailOf(e), self.res.taken(e, amt) * BUILD_PER_DMG);
            }
        }
        if (self.stunned()) return .none;
        const foe = self.side == .foe;
        const stanceWear = if (foe) 1.0 + HEAVY_WEAR * self.heavyWear else 1.0;
        self.stance -= h.stance / stanceWear;
        var light = false;
        const poiseHit = if (foe) (if (builds) taken * FOE_POISE_PER_DMG else 0) else h.poise;
        const poiseWear = if (foe) 1.0 + LIGHT_WEAR * self.lightWear else 1.0;
        self.poise -= poiseHit / poiseWear;
        if (self.poise <= 0) {
            self.poise = self.poiseMax;
            self.stance -= self.breakShare * self.stanceMax;
            light = true;
        }
        if (self.stance <= 0) {
            self.stance = self.stanceMax;
            if (foe) self.heavyWear += 1;
            self.beginStun(.heavy);
            return .heavy;
        }
        if (light) {
            if (foe) self.lightWear += 1;
            self.beginStun(.light);
            return .light;
        }
        return .none;
    }
};

// ER's shallow, fast-refilling pool (docs/ELDEN_RING.md §3 — its Endurance-15 numbers): a flat bite per action, pouring back ~4x as fast as a roll spends it, so it paces a FLURRY and not a whole fight.
pub const STAM_MAX = stats.staminaFor(stats.START); // 105 — ENDURANCE owns the pool size now (`stats.zig`); about eight rolls from full
pub var STAM_ROLL: f32 = 12.0;
pub var STAM_LIGHT: f32 = 10.0;
pub var STAM_HEAVY: f32 = 16.0;
pub var STAM_SHOT: f32 = 8.0;
pub var STAM_AIMED: f32 = 18.0;
pub var STAM_SPRINT: f32 = 9.0;
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

pub var GUARD_NEGATE: f32 = 0.85;
pub var GUARD_STAM_FLAT: f32 = 5.0;
pub var GUARD_STAM_PER_DMG: f32 = 1.10;
pub const GUARD_ARC: f32 = 65.0;

pub fn withinGuardArc(bearing: f32, facing: f32) bool {
    return withinArc(bearing, facing, GUARD_ARC);
}

pub fn withinArc(bearing: f32, facing: f32, arc: f32) bool {
    return @abs(mathx.degrees(mathx.wrapPi(bearing - facing))) <= arc;
}

pub fn subtendedArc(half: f32, dist: f32) f32 {
    return mathx.degrees(std.math.atan2(half, mathx.maxF(dist, 1e-4)));
}

pub fn guardStamina(h: Hit) f32 {
    return GUARD_STAM_FLAT + GUARD_STAM_PER_DMG * h.raw();
}
/// PoE2's own: `A/(A + 5*dmg)` is turned aside, so the same coat is worth a fifth of a middling blow.
pub fn armourTaken(a: f32, dmg: f32) f32 {
    if (a <= 0 or dmg <= 0) return dmg;
    return dmg * (1.0 - a / (a + 5.0 * dmg));
}

/// **A BOARD MAY NEVER STOP A BLOW OUTRIGHT.** With a shield ROW (`item.Arm.negate`) multiplying the base and a tree node adding to it, the two could sum past 1 and make blocking free.
pub const GUARD_NEGATE_CAP: f32 = 0.95;

/// **WHAT A BOARD ACTUALLY TURNS ASIDE, NAMED ONCE.** `hero.blockHit` and the character book's `guard` row both spelled it out — two copies of the one figure the page exists to compare, and a page promising 97% behind a door the fight holds to 95 is a page lying.
pub fn guardNegation(boardNegate: f32, perkGuard: f32) f32 {
    return mathx.minF(GUARD_NEGATE_CAP, GUARD_NEGATE * boardNegate + perkGuard);
}

pub fn guardChip(h: Hit, negate: f32) Hit {
    return guardChipSplit(h, negate, negate);
}

pub fn guardChipSplit(h: Hit, negate: f32, negateElem: f32) Hit {
    const k = 1.0 - mathx.clampF(negate, 0, 1);
    const ke = 1.0 - mathx.clampF(negateElem, 0, 1);
    return .{ .dmg = h.dmg * k, .elem = h.elem.scaled(ke), .fp = h.fp * ke };
}


pub var STAM_PARRY: f32 = 9.0;
/// Sized so the ogre's 90 stance takes two catches and lighter takes one.
/// `SLAM_HIT` in `foes/` and by nothing else. Here rather than in `hero.zig` so a creature can say its blow throws him without importing the man it throws.
pub const SLAM_LAUNCH: f32 = 0.85;

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

/// **THE HOLD IS WHAT THE SPELL SELLS** (owner: make it last longer) — 3.5 s to 5.0. The DRIP came down to pay
/// for it: `SPELLS`' ladder is monotone, so 12 FP has a window of (18, 22) between the siphon under it and the
/// levin over it, and the same hold at the old 5.6/s would have billed 28 and broken the price list at comptime.
pub const ROOT_HOLD: f32 = 5.0;
pub const ROOT_DPS: f32 = 4.0;
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

pub const RIME_DUR: f32 = 0.85;
pub const RIME_REACH: f32 = 6.0;
pub const RIME_ARC: f32 = 30.0;
pub const RIME_DPS: f32 = 18.0;

pub const CHILL_HOLD: f32 = 4.0;
pub const CHILL_TRAVEL: f32 = 0.55;

comptime {
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

/// **THE TWO THAT DO NOT CROSS THE GROUND** — they arrive on ONE named body on the frame they are cast, so they need a REACH and an ARC rather than a speed. Narrower than the rime cone's 30 on purpose: that is a wash, these are aimed.
pub const STRIKE_ARC: f32 = 22.0;

/// POISE PAST EVERY CREATURE'S `POISE_MAX` BAR THE BONE KNIGHT'S 78 (the ogre's 30 is next), where his heavy
/// swing at 22 leaves the giants standing. STANCE deliberately UNDER that swing's 14: a spell thrown from across the room may not be the better guard-breaker.
pub const LEVIN_HIT = Hit{ .poise = 34, .stance = 10, .elem = elems(.{ .lightning = 22 }) };
/// Well past the roots' 7 m throw, since nothing has to cross the ground, and far short of the bolt's 55: an interrupt thrown from outside the fight is not an interrupt.
pub const LEVIN_REACH: f32 = 16.0;

pub const SIPHON_HIT = Hit{ .elem = elems(.{ .chaos = 18 }) };
pub const SIPHON_SHARE: f32 = 0.55;
pub const SIPHON_REACH: f32 = 12.0;

/// The only spell that does not stop at the first body: a LANCE
/// goes THROUGH. PER BODY and deliberately small, priced where the rime is — what it buys is the SECOND body and the third. Poise under the levin's 34 and over a hero light's.
pub const LANCE_HIT = Hit{ .poise = 18, .stance = 6, .elem = elems(.{ .fire = 16.5 }) };
pub const LANCE_REACH: f32 = 20.0;
pub const LANCE_R: f32 = 0.55;

pub const SUNDER_HIT = Hit{ .dmg = 14, .poise = 12, .stance = 40 };
pub const SUNDER_REACH: f32 = 4.0;

pub const BABBLE_HIT = Hit{ .dose = Doses.one(.confusion, ailBank(.confusion).max) };
/// PAST THE ROOTS' 7 m AND WELL SHORT OF THE BOLT'S 55 — cast INTO the room, not across the field.
pub const BABBLE_REACH: f32 = 13.0;

pub const BIDDING_HIT = Hit{ .dose = Doses.one(.charm, ailBank(.charm).max) };
pub const BIDDING_REACH: f32 = 9.0;

pub const Spell = enum { bolt, roots, rime, levin, siphon, lance, sunder, babble, bidding };

pub const SpellRow = struct {
    spell: Spell,
    name: [:0]const u8,
    fp: f32,
    scroll: item.Kind,
    says: [:0]const u8,
    blow: ?Hit = null,
    reach: ?f32 = null,
    drip: f32 = 0,
};

/// **ROW ORDER IS `Spell`'S OWN**, pinned at comptime: an eighth spell is a compile error until it has said what it costs and what it does. This is the price, not the physics.
pub const SPELLS_BANK = [_]SpellRow{
    .{ .spell = .bolt,   .name = "Chaos Bolt",   .fp = 8,  .scroll = .scroll_bolt,   .says = "A thrown stone of chaos. Crosses the ground, and cover stops it.",     .blow = BOLT_HIT },
    .{ .spell = .roots,  .name = "Roots",        .fp = 12, .scroll = .scroll_roots,  .says = "Holds a body where it stands and bleeds it while it is held.",        .drip = ROOT_HOLD * ROOT_DPS },
    .{ .spell = .rime,   .name = "Rime Breath",  .fp = 15, .scroll = .scroll_rime,   .says = "A cone of cold, held out for as long as the breath lasts. Slows what it touches.", .drip = RIME_DUR * RIME_DPS },
    .{ .spell = .levin,  .name = "Levin Strike", .fp = 11, .scroll = .scroll_levin,  .says = "Lands on one body the frame it is cast. Staggers anything that is not a boss.", .blow = LEVIN_HIT,  .reach = LEVIN_REACH },
    .{ .spell = .siphon, .name = "Siphon",       .fp = 13, .scroll = .scroll_siphon, .says = "Drinks a share of what the body actually loses. No stagger.",          .blow = SIPHON_HIT, .reach = SIPHON_REACH },
    .{ .spell = .lance,  .name = "Ember Lance",  .fp = 14, .scroll = .scroll_lance,  .says = "A held line of fire that spits every body standing in it.",           .blow = LANCE_HIT,  .reach = LANCE_REACH },
    .{ .spell = .sunder, .name = "Sunder",       .fp = 16, .scroll = .scroll_sunder, .says = "Breaks a guard inside sword reach. The one sorcery cast in the fight.", .blow = SUNDER_HIT, .reach = SUNDER_REACH },
    .{ .spell = .babble, .name = "Babble",       .fp = 19, .scroll = .scroll_babble, .says = "Takes a body's aim away. It swings at whatever is nearest, you included.", .blow = BABBLE_HIT,  .reach = BABBLE_REACH },
    .{ .spell = .bidding, .name = "Bidding",     .fp = 24, .scroll = .scroll_bidding, .says = "Turns a body on the ones it came with. The dearest thing the rod does.", .blow = BIDDING_HIT, .reach = BIDDING_REACH },
};

pub var SPELLS: [SPELLS_BANK.len]SpellRow = SPELLS_BANK;

comptime {
    if (SPELLS_BANK.len != @typeInfo(Spell).@"enum".fields.len) @compileError("combat: SPELLS_BANK is not one row per Spell");
    for (SPELLS_BANK, 0..) |row, i| {
        if (@intFromEnum(row.spell) != i) @compileError("combat: SPELLS_BANK row " ++ row.name ++ " is out of `Spell` order");
        if ((row.blow == null) != (row.drip > 0)) @compileError("combat: " ++ row.name ++ " has no worth, or two");
        if (!item.isSpellScroll(row.scroll)) @compileError("combat: " ++ row.name ++ " names a scroll that " ++
            "`item.isSpellScroll` does not know — the bag would hold an object nothing can memorize");
        if (row.says.len == 0) @compileError("combat: " ++ row.name ++ " says nothing about what it does");
        for (SPELLS_BANK[0..i]) |prev| {
            if (prev.scroll == row.scroll) @compileError("combat: " ++ row.name ++ " and " ++ prev.name ++
                " are written on the same scroll — one sheet cannot hand over two sorceries");
        }
    }
    for (0..item.NK) |i| {
        const k: item.Kind = @enumFromInt(i);
        if (!item.isSpellScroll(k)) continue;
        var named = false;
        for (SPELLS_BANK) |row| named = named or row.scroll == k;
        if (!named) @compileError("combat: nothing is written on " ++ @tagName(k));
    }
}

pub fn rowFor(s: Spell) SpellRow {
    return SPELLS[@intFromEnum(s)];
}

/// The authored row, for the ladder's own comptime asserts and the consts solved off it (`ailBank`'s reason).
pub fn bankRow(s: Spell) SpellRow {
    return SPELLS_BANK[@intFromEnum(s)];
}

fn bankFp(s: Spell) f32 {
    return bankRow(s).fp;
}

fn bankDoses(s: Spell) bool {
    const row = bankRow(s);
    return if (row.blow) |b| b.dose.any() else false;
}

fn bankDamage(s: Spell) f32 {
    const row = bankRow(s);
    return if (row.blow) |b| b.raw() else row.drip;
}

pub fn spellName(s: Spell) [:0]const u8 {
    return bankRow(s).name;
}

pub fn spellSays(s: Spell) [:0]const u8 {
    return bankRow(s).says;
}

pub fn spellScroll(s: Spell) item.Kind {
    return bankRow(s).scroll;
}

pub fn carriesSpell(bag: *const item.Bag, s: Spell) bool {
    return bag.count(spellScroll(s)) > 0;
}

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

pub fn spellDoses(s: Spell) bool {
    const row = rowFor(s);
    return if (row.blow) |b| b.dose.any() else false;
}

pub fn spellDose(s: Spell) ?Ail {
    const b = rowFor(s).blow orelse return null;
    for (b.dose.v, 0..) |amt, i| {
        if (amt > 0) return @enumFromInt(i);
    }
    return null;
}

pub const MEM_SLOTS: usize = 3;

comptime {
    if (MEM_SLOTS == 0 or MEM_SLOTS > 8) @compileError("combat: MEM_SLOTS is 1..8 — a rack of none casts " ++
        "nothing, and past eight the screens have no numeral to call a slot by");
}

pub const Memory = struct {
    slots: [MEM_SLOTS]?Spell = blk: {
        var s = [_]?Spell{null} ** MEM_SLOTS;
        s[0] = .bolt;
        break :blk s;
    },

    pub fn at(self: *const Memory, i: usize) ?Spell {
        return if (i < MEM_SLOTS) self.slots[i] else null;
    }

    pub fn holds(self: *const Memory, s: Spell) bool {
        return self.slotOf(s) != null;
    }

    pub fn slotOf(self: *const Memory, s: Spell) ?usize {
        for (self.slots, 0..) |c, i| {
            if (c == s) return i;
        }
        return null;
    }

    pub fn filled(self: *const Memory) usize {
        var n: usize = 0;
        for (self.slots) |c| {
            if (c != null) n += 1;
        }
        return n;
    }

    pub fn first(self: *const Memory) ?Spell {
        for (self.slots) |c| {
            if (c) |s| return s;
        }
        return null;
    }

    pub fn put(self: *Memory, i: usize, s: ?Spell) void {
        if (i >= MEM_SLOTS) return;
        if (s) |want| {
            if (self.slotOf(want)) |had| self.slots[had] = self.slots[i];
        }
        self.slots[i] = s;
    }

    pub fn next(self: *const Memory, from: Spell) ?Spell {
        const start = self.slotOf(from) orelse return self.first();
        for (1..MEM_SLOTS + 1) |step| {
            if (self.slots[(start + step) % MEM_SLOTS]) |s| return s;
        }
        return null;
    }
};

pub const BOLT_FP: f32 = bankFp(.bolt);

comptime {
// The ladder is MONOTONE and that is the whole price list: 8→25, 11→22, 12→19.6, 13→18, 14→16.5, 15→15.3,
// 16→14 — and every rung clears a free light swing (`hero.ATK_LIGHT_HIT`, 13).
    @setEvalBranchQuota(8000);
    for (std.enums.values(Spell)) |a| {
        for (std.enums.values(Spell)) |b| {
            if (bankDoses(a) or bankDoses(b)) continue;
            if (bankFp(a) < bankFp(b)) std.debug.assert(bankDamage(a) > bankDamage(b));
        }
    }
    for (std.enums.values(Spell)) |d| {
        if (!bankDoses(d)) continue;
        std.debug.assert(bankDamage(d) == 0);
        for (std.enums.values(Spell)) |s| {
            if (bankDoses(s)) continue;
            std.debug.assert(bankFp(d) > bankFp(s));
        }
    }
    for (std.enums.values(Spell)) |s| std.debug.assert(bankFp(s) > 0 and bankFp(s) <= FP_MAX);
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

/// **THE CHARGES ARE ONE POOL AND THE SPLIT IS HIS** (Elden Ring's allotment, at a bonfire): the total never
/// moves, only where it sits. `FLASK_CRIMSON` is where a fresh run starts it.
pub const FLASK_TOTAL: u8 = 3;
pub const FLASK_CRIMSON: u8 = 2;
pub const FLASK_CERULEAN: u8 = FLASK_TOTAL - FLASK_CRIMSON;
pub const FLASK_HP_FRAC: f32 = 0.45;
pub const FLASK_FP_FRAC: f32 = 0.50;
pub const FLASK_DRINK_DUR: f32 = 1.05;
pub const FLASK_POUR_AT: f32 = 0.42;

pub const Flasks = struct {
    /// The ALLOTMENT — how many of each the bonfire fills. `crimsonMax + ceruleanMax` is the pool and is
    /// invariant under `allot`; the two live counts below are what is left of it.
    crimsonMax: u8 = FLASK_CRIMSON,
    ceruleanMax: u8 = FLASK_CERULEAN,
    crimson: u8 = FLASK_CRIMSON,
    cerulean: u8 = FLASK_CERULEAN,
    sel: FlaskKind = .crimson,

    pub fn charges(self: *const Flasks, k: FlaskKind) u8 {
        return switch (k) {
            .crimson => self.crimson,
            .cerulean => self.cerulean,
        };
    }
    pub fn allotted(self: *const Flasks, k: FlaskKind) u8 {
        return switch (k) {
            .crimson => self.crimsonMax,
            .cerulean => self.ceruleanMax,
        };
    }
    pub fn total(self: *const Flasks) u8 {
        return self.crimsonMax + self.ceruleanMax;
    }
    /// Move the split. The pool is held, and re-allotting FILLS — the bonfire is where it is done.
    pub fn allot(self: *Flasks, crimsonMax: u8) void {
        const n = self.total();
        self.crimsonMax = @min(crimsonMax, n);
        self.ceruleanMax = n - self.crimsonMax;
        self.refill();
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
        self.crimson = self.crimsonMax;
        self.cerulean = self.ceruleanMax;
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
};



/// **TEN AILMENTS, ONE METER APIECE.** Order is the row order of `AILS` and pinned at comptime.
pub const Ail = enum { poison, burning, chill, stun, bleed, sleep, confusion, charm, berserk, stupefy };

pub const NAIL = @typeInfo(Ail).@"enum".fields.len;

pub const Bearer = enum { both, foe, hero };

pub const Payout = enum { over, burst };

pub const AilRow = struct {
    ail: Ail,
    name: [:0]const u8,
    says: [:0]const u8,
    bearer: Bearer = .both,
    payout: Payout = .over,
    elem: ?Elem = null,
    max: f32,
    decayDelay: f32 = POISON_DECAY_DELAY,
    decay: f32,
    dur: f32 = 0,
    hpFrac: f32 = 0,
    flat: f32 = 0,
    pulse: ?Elem = null,
};

pub const POISON_DECAY_DELAY: f32 = 1.1;

pub const BUILD_PER_DMG: f32 = 1.0;

pub const STUPEFY_TRAVEL: f32 = 0.78;
pub const STUPEFY_FOCUS: f32 = 0.55;

pub const BERSERK_DMG: f32 = 1.35;
pub const BERSERK_TRAVEL: f32 = 1.22;
pub const BERSERK_HASTE: f32 = 1.25;

comptime {
    std.debug.assert(STUPEFY_TRAVEL > CHILL_TRAVEL and STUPEFY_TRAVEL < 1.0);
    std.debug.assert(STUPEFY_FOCUS > 0 and STUPEFY_FOCUS < 1.0);
    std.debug.assert(BERSERK_DMG > 1.0 and BERSERK_TRAVEL > 1.0 and BERSERK_HASTE > 1.0);
}

pub const AILS_BANK = [_]AilRow{
    .{
        .ail = .poison, .name = "Poison", .elem = .chaos, .pulse = .chaos,
        .says = "Bleeds you for a share of your health over a long clock.",
        .max = 100.0, .decay = 24.0, .dur = 14.0, .hpFrac = 0.26,
    },
    .{
        .ail = .burning, .name = "Burning", .elem = .fire, .pulse = .fire,
        .says = "Burns hotter than poison and for a third as long.",
        .max = 100.0, .decay = 30.0, .dur = 4.6, .hpFrac = 0.22,
    },
    .{
        // **ITS METER IS SMALL ON PURPOSE**: the rime breath pours 15.3 cold, and a 100 meter would mean the
        // one spell built for this could not fill it. Pinned against the pour at comptime below.
        .ail = .chill, .name = "Chill", .elem = .cold,
        .says = "The feet only. A chilled body cannot close, it is not a slowed one.",
        .max = 14.0, .decay = 6.0, .dur = CHILL_HOLD,
    },
    .{
        .ail = .stun, .name = "Stun", .elem = .lightning,
        .says = "Fills fast and empties faster. Full, it staggers.",
        .max = 40.0, .decayDelay = 0.6, .decay = 60.0, .dur = HEAVY_STUN_DUR,
    },
    .{
        .ail = .bleed, .name = "Bleed", .payout = .burst,
        .says = "Full, it opens you at once. Armour barely answers it.",
        .max = 100.0, .decay = 14.0, .flat = 45.0,
    },
    .{
        .ail = .sleep, .name = "Sleep",
        .says = "Cannot act until struck. A tick will not wake it.",
        .max = 100.0, .decay = 18.0, .dur = 6.0,
    },
    .{
        .ail = .confusion, .name = "Confusion", .bearer = .foe,
        .says = "It swings at whatever is nearest, friend or not.",
        .max = 100.0, .decay = 20.0, .dur = 7.0,
    },
    .{
        .ail = .charm, .name = "Charm", .bearer = .foe,
        .says = "It turns on the ones it came with.",
        .max = 100.0, .decay = 20.0, .dur = 8.0,
    },
    .{
        .ail = .berserk, .name = "Berserk",
        .says = "Harder and faster, bleeding out, and it ends flat on your back.",
        .max = 100.0, .decay = 16.0, .dur = 9.0, .hpFrac = 0.18, .pulse = .chaos,
    },
    .{
        .ail = .stupefy, .name = "Stupefied", .bearer = .hero,
        .says = "Thins the focus and drags the feet.",
        .max = 100.0, .decay = 20.0, .dur = 8.0,
    },
};

pub var AILS: [AILS_BANK.len]AilRow = AILS_BANK;

comptime {
    if (AILS_BANK.len != NAIL) @compileError("combat: AILS_BANK is not one row per Ail");
    for (AILS_BANK, 0..) |row, i| {
        if (@intFromEnum(row.ail) != i) @compileError("combat: AILS_BANK row " ++ row.name ++ " is out of `Ail` order");
        if (row.says.len == 0) @compileError("combat: " ++ row.name ++ " says nothing about what it does");
        if (row.max <= 0 or row.decay <= 0) @compileError("combat: " ++ row.name ++ " has a meter nothing can fill or empty");
        if (row.payout == .over and row.dur <= 0) @compileError("combat: " ++ row.name ++ " runs on a clock of zero");
        if (row.hpFrac > 0 and row.pulse == null) @compileError("combat: " ++ row.name ++ " bills health as nothing at all");
        if (row.payout == .burst and row.hpFrac > 0) @compileError("combat: " ++ row.name ++ " bursts for a share of the bar — a burst bills `flat`");
        if (row.payout == .over and row.flat > 0) @compileError("combat: " ++ row.name ++ " runs on a clock and bills a flat sum — that is a burst");
    }
    for (AILS_BANK, 0..) |a, i| {
        for (AILS_BANK[0..i]) |b| {
            if (a.elem != null and std.meta.eql(a.elem, b.elem))
                @compileError("combat: " ++ a.name ++ " and " ++ b.name ++ " both build off one element");
        }
    }
    for (std.enums.values(Elem)) |e| {
        var named = false;
        for (AILS_BANK) |row| named = named or std.meta.eql(row.elem, @as(?Elem, e));
        if (!named) @compileError("combat: nothing is built by " ++ @tagName(e) ++ " damage");
    }
    // The one spell built to chill must fill the chill meter: the pour is 15.3 cold.
    if (RIME_DUR * RIME_DPS < ailBank(.chill).max) @compileError("combat: the rime breath no longer fills a chill meter");
}

comptime {
    @setEvalBranchQuota(4000);
    const N = @typeInfo(item.AilName).@"enum".fields.len;
    if (N != NAIL) @compileError("combat: `item.AilName` is not one tag per `Ail`");
    for (@typeInfo(item.AilName).@"enum".fields, 0..) |f, i| {
        if (!std.mem.eql(u8, f.name, @tagName(@as(Ail, @enumFromInt(i)))))
            @compileError("combat: `item.AilName." ++ f.name ++ "` is at index " ++
                std.fmt.comptimePrint("{d}", .{i}) ++ " where `Ail` has " ++ @tagName(@as(Ail, @enumFromInt(i))));
    }
}

pub fn ailOfName(a: item.AilName) Ail {
    return @enumFromInt(@intFromEnum(a));
}

pub fn ailRow(a: Ail) AilRow {
    return AILS[@intFromEnum(a)];
}

pub fn ailBank(a: Ail) AilRow {
    return AILS_BANK[@intFromEnum(a)];
}

pub fn ailName(a: Ail) [:0]const u8 {
    return ailBank(a).name;
}

pub fn ailSays(a: Ail) [:0]const u8 {
    return ailBank(a).says;
}

const AIL_OF_ELEM: [NELEM]Ail = blk: {
    var out: [NELEM]Ail = undefined;
    for (std.enums.values(Elem)) |e| {
        for (AILS_BANK) |row| {
            if (std.meta.eql(row.elem, @as(?Elem, e))) out[@intFromEnum(e)] = row.ail;
        }
    }
    break :blk out;
};

pub fn ailOf(e: Elem) Ail {
    return AIL_OF_ELEM[@intFromEnum(e)];
}

pub const POISON_MAX: f32 = ailBank(.poison).max;

comptime {
    const strokes = 4;
    if (item.ENVENOMED.venom * strokes < POISON_MAX) @compileError("combat: the envenomed edge no longer fills a meter in four strokes");
    if (item.ENVENOMED.venom * (strokes - 1) >= POISON_MAX) @compileError("combat: the envenomed edge fills a meter in three strokes or fewer");
}

pub const Status = struct {
    meter: f32 = 0,
    on: bool = false,
    sinceDose: f32 = LONG_AGO,
    justProcced: bool = false,
    justEnded: bool = false,

    pub fn frac(self: *const Status, row: AilRow) f32 {
        return mathx.clampF(self.meter / row.max, 0, 1);
    }
    pub fn active(self: *const Status) bool {
        return self.on;
    }
    pub fn add(self: *Status, row: AilRow, amt: f32) void {
        if (self.on or amt <= 0) return;
        self.meter = minF(row.max, self.meter + amt);
        self.sinceDose = 0;
    }
    pub fn tick(self: *Status, row: AilRow, dt: f32, hpMax: f32) f32 {
        self.justProcced = false;
        self.justEnded = false;
        if (self.meter <= 0 and !self.on) return 0;
        if (self.on) {
            self.meter = maxF(0, self.meter - row.max / row.dur * dt);
            if (self.meter <= 0) {
                self.* = .{};
                self.justEnded = true;
                return 0;
            }
            return hpMax * row.hpFrac / row.dur * dt;
        }
        self.sinceDose += dt;
        if (self.meter >= row.max) {
            self.justProcced = true;
            if (row.payout == .burst) {
                self.meter = 0;
                self.sinceDose = 0;
                return row.flat;
            }
            self.on = true;
            self.meter = row.max;
            return 0;
        }
        if (self.sinceDose >= row.decayDelay) self.meter = maxF(0, self.meter - row.decay * dt);
        return 0;
    }
    pub fn reset(self: *Status) void {
        self.* = .{};
    }
};

pub fn ailPulse(row: AilRow, amt: f32) Hit {
    var out = Hit{};
    if (row.pulse) |e| out.elem.v[@intFromEnum(e)] = amt else out.gore = amt;
    return out;
}

pub fn poisonPulse(amt: f32) Hit {
    return ailPulse(ailRow(.poison), amt);
}

test "ELEMENTAL DAMAGE BUILDS ITS OWN METER, AFTER RESISTANCES — and a DRIP builds nothing" {
    // Ten, because the chill meter is 14 and a bigger column would only prove the clamp.
    for (std.enums.values(Elem)) |e| {
        var body = Vitals.initFoe(400, 999, 999);
        var blow = Hit{};
        blow.elem.v[@intFromEnum(e)] = 10;
        _ = body.hit(blow);
        const built = body.ail(ailOf(e)).meter;
        try std.testing.expectApproxEqAbs(@as(f32, 10) * BUILD_PER_DMG, built, 1e-4);
        for (std.enums.values(Ail)) |a| {
            if (a == ailOf(e)) continue;
            try std.testing.expectApproxEqAbs(@as(f32, 0), body.ail(a).meter, 1e-6);
        }
    }

    // A column bigger than the meter fills it and stops — the chill's 14 against the rime's whole 15.3 pour.
    var frosted = Vitals.initFoe(400, 999, 999);
    _ = frosted.hit(.{ .elem = elems(.{ .cold = RIME_DUR * RIME_DPS }) });
    try std.testing.expectApproxEqAbs(ailRow(.chill).max, frosted.ail(.chill).meter, 1e-4);

    // **RESISTANCE CUTS THE METER AS WELL AS THE TICK** (owner: so resists can help). 75 chaos is a quarter dose.
    var warded = Vitals.initFoe(400, 999, 999).withRes(resists(.{ .chaos = 75 }));
    _ = warded.hit(.{ .elem = elems(.{ .chaos = 40 }) });
    try std.testing.expectApproxEqAbs(@as(f32, 10), warded.ail(.poison).meter, 1e-4);
    var bare = Vitals.initFoe(400, 999, 999).withRes(resists(.{ .chaos = -50 }));
    _ = bare.hit(.{ .elem = elems(.{ .chaos = 40 }) });
    try std.testing.expectApproxEqAbs(@as(f32, 60), bare.ail(.poison).meter, 1e-4);
    std.debug.print("\n  40 chaos builds {d:.0} poison bare, {d:.0} at +75, {d:.0} at -50\n", .{
        @as(f32, 40), warded.ail(.poison).meter, bare.ail(.poison).meter,
    });

    var dripped = Vitals.initFoe(400, 999, 999);
    _ = dripped.drip(.{ .elem = elems(.{ .chaos = 40 }) });
    try std.testing.expectApproxEqAbs(@as(f32, 0), dripped.ail(.poison).meter, 1e-6);
    try std.testing.expect(dripped.hp < 400);

    var rots = Vitals.initFoe(4000, 999, 999);
    rots.build(.poison, ailRow(.poison).max);
    var t: f32 = 0;
    while (t < ailRow(.poison).dur * 1.5) : (t += 1.0 / 60.0) _ = rots.tickAils(1.0 / 60.0);
    try std.testing.expect(!rots.ailOn(.poison));
}

test "THE SLOWS MULTIPLY, AND THE BARGAIN PULLS THE OTHER WAY" {
    var v = Vitals.init(400, 999, 999);
    try std.testing.expectApproxEqAbs(@as(f32, 1), v.travelMult(), 1e-6);

    v.build(.chill, ailRow(.chill).max);
    _ = v.tickAils(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(CHILL_TRAVEL, v.travelMult(), 1e-5);

    v.build(.stupefy, ailRow(.stupefy).max);
    _ = v.tickAils(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(CHILL_TRAVEL * STUPEFY_TRAVEL, v.travelMult(), 1e-5);
    try std.testing.expect(v.travelMult() < CHILL_TRAVEL);
    try std.testing.expect(STUPEFY_TRAVEL > CHILL_TRAVEL);
    try std.testing.expectApproxEqAbs(STUPEFY_FOCUS, v.focusMult(), 1e-6);

    var mad = Vitals.init(400, 999, 999);
    mad.build(.berserk, ailRow(.berserk).max);
    _ = mad.tickAils(1.0 / 60.0);
    try std.testing.expect(mad.travelMult() > 1.0);
    try std.testing.expect(mad.dmgMult() > 1.0 and mad.hasteMult() > 1.0);
    std.debug.print("\n  berserk: x{d:.2} damage, x{d:.2} feet, x{d:.2} clocks; stupefy x{d:.2} feet, x{d:.2} focus\n", .{
        mad.dmgMult(), mad.travelMult(), mad.hasteMult(), STUPEFY_TRAVEL, STUPEFY_FOCUS,
    });

    var paid: f32 = 0;
    var t: f32 = 0;
    var ended = false;
    while (t < ailRow(.berserk).dur * 1.3) : (t += 1.0 / 60.0) {
        const was = mad.hp;
        _ = mad.tickAils(1.0 / 60.0);
        paid += was - mad.hp;
        if (mad.ailEnded(.berserk)) ended = true;
    }
    try std.testing.expect(ended);
    try std.testing.expect(!mad.ailOn(.berserk));
    try std.testing.expectApproxEqAbs(400.0 * ailRow(.berserk).hpFrac, paid, 4.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), mad.dmgMult(), 1e-6);
}

test "A TICK DOES NOT WAKE A SLEEPER, AND A BLOW DOES" {
    var v = Vitals.initFoe(400, 999, 999);
    v.build(.sleep, ailRow(.sleep).max);
    _ = v.tickAils(1.0 / 60.0);
    try std.testing.expect(v.asleep() and v.ailProcced(.sleep));

    v.build(.poison, ailRow(.poison).max);
    var t: f32 = 0;
    while (t < ailRow(.sleep).dur * 0.5) : (t += 1.0 / 60.0) _ = v.tickAils(1.0 / 60.0);
    try std.testing.expect(v.ailOn(.poison));
    try std.testing.expect(v.asleep());
    try std.testing.expect(v.hp < 400);

    while (t < ailRow(.sleep).dur * 1.2) : (t += 1.0 / 60.0) _ = v.tickAils(1.0 / 60.0);
    try std.testing.expect(!v.asleep());

    var hit2 = Vitals.initFoe(400, 999, 999);
    hit2.build(.sleep, ailRow(.sleep).max);
    _ = hit2.tickAils(1.0 / 60.0);
    try std.testing.expect(hit2.asleep());
    hit2.wake();
    try std.testing.expect(!hit2.asleep());
}

test "A RAISED BODY COMES BACK CLEAN — it does not carry the meter that killed it" {
    var v = Vitals.initFoe(400, 999, 999);
    v.build(.poison, ailRow(.poison).max);
    v.build(.sleep, ailRow(.sleep).max);
    _ = v.tickAils(1.0 / 60.0);
    try std.testing.expect(v.ailOn(.poison) and v.asleep());
    v.hp = 0;
    v.dead = true;

    v.revive(0.55);
    for (std.enums.values(Ail)) |a| {
        try std.testing.expect(!v.ailOn(a));
        try std.testing.expectApproxEqAbs(@as(f32, 0), v.ail(a).meter, 1e-6);
    }
    try std.testing.expect(!v.asleep());
    const before = v.hp;
    _ = v.tickAils(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(before, v.hp, 1e-6);
    std.debug.print("\n  raised at 55%: {d:.0} hp, no meter carried over\n", .{v.hp});
}

test "A FOE-ONLY METER REFUSES HIM, AND A HERO-ONLY ONE REFUSES A CREATURE" {
    var him = Vitals.init(200, 99, 99);
    var it = Vitals.initFoe(200, 99, 99);
    for (std.enums.values(Ail)) |a| {
        him.build(a, ailRow(a).max);
        it.build(a, ailRow(a).max);
        const wantHim = ailRow(a).bearer != .foe;
        const wantIt = ailRow(a).bearer != .hero;
        try std.testing.expectEqual(wantHim, him.ail(a).meter > 0);
        try std.testing.expectEqual(wantIt, it.ail(a).meter > 0);
    }
    try std.testing.expectEqual(@as(f32, 0), him.ail(.charm).meter);
    try std.testing.expectEqual(@as(f32, 0), him.ail(.confusion).meter);
    try std.testing.expectEqual(@as(f32, 0), it.ail(.stupefy).meter);
}

test "BLEED BURSTS FLAT AND RE-ARMS, AND ARMOUR BARELY ANSWERS IT" {
    const B = ailRow(.bleed);
    var plated = Vitals.init(400, 999, 999).withArmour(60);
    plated.build(.bleed, B.max);
    _ = plated.tickAils(1.0 / 60.0);
    try std.testing.expect(plated.ailProcced(.bleed));
    // Flat and unarmoured: 60 armour turns some of a 45 physical blow aside and NONE of this.
    try std.testing.expectApproxEqAbs(400.0 - B.flat, plated.hp, 0.01);
    try std.testing.expect(armourTaken(60, B.flat) < B.flat);
    std.debug.print("\n  bleed: 60 armour keeps {d:.0} of a {d:.0} physical blow and {d:.0} of the burst\n", .{
        B.flat - armourTaken(60, B.flat), B.flat, @as(f32, 0),
    });
    try std.testing.expect(!plated.ailOn(.bleed));
    try std.testing.expectApproxEqAbs(@as(f32, 0), plated.ail(.bleed).meter, 1e-6);
    plated.build(.bleed, B.max);
    _ = plated.tickAils(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(400.0 - B.flat * 2.0, plated.hp, 0.01);

    var small = Vitals.init(100, 99, 99);
    var big = Vitals.init(400, 99, 99);
    small.build(.bleed, B.max);
    big.build(.bleed, B.max);
    _ = small.tickAils(1.0 / 60.0);
    _ = big.tickAils(1.0 / 60.0);
    const smallShare = (100.0 - small.hp) / 100.0;
    const bigShare = (400.0 - big.hp) / 400.0;
    std.debug.print("  bleed bursts {d:.0} flat: {d:.0}% of a 100 bar, {d:.0}% of a 400 one\n", .{ B.flat, smallShare * 100.0, bigShare * 100.0 });
    try std.testing.expect(smallShare > bigShare * 3.0);
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
    pub fn value(self: *const Timed, off: f32) f32 {
        return if (self.left > 0) self.amount else off;
    }
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

pub const Gold = Souls;

pub const Souls = struct {
    total: u32 = 0,
    shown: f32 = 0,

    pub fn gain(self: *Souls, n: u32) void {
        self.total +|= n;
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

    /// **THROUGH A `u64` AND CAPPED ON THE TOTAL.** `maxInt(u32)` has no f32 that represents it — the nearest is 2^32 — so a saturated total rolls `shown` to a float ONE PAST the type it was being cast into, and that cast is illegal rather than merely wrong. `maxF` is the NaN guard.
    pub fn display(self: *const Souls) u32 {
        const n: u64 = @intFromFloat(@floor(maxF(self.shown, 0)));
        return @intCast(@min(n, self.total));
    }
};

const minF = mathx.minF;
const maxF = mathx.maxF;

test "POISON: the meter fills, PROCS, and the same meter drains as the clock" {
    const P = ailRow(.poison);
    var s = Status{};
    try std.testing.expect(!s.active() and s.frac(P) == 0);
    s.add(P, P.max - 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.tick(P, 1.0 / 60.0, 70), 1e-6);
    try std.testing.expect(!s.active() and s.frac(P) > 0.9);
    s.add(P, 5.0);
    _ = s.tick(P, 1.0 / 60.0, 70);
    try std.testing.expect(s.active() and s.justProcced);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), s.frac(P), 1e-4);
    _ = s.tick(P, 1.0 / 60.0, 70);
    try std.testing.expect(!s.justProcced);

    var paid: f32 = 0;
    var t: f32 = 1.0 / 30.0;
    while (t < P.dur * 1.2) : (t += 1.0 / 60.0) paid += s.tick(P, 1.0 / 60.0, 70);
    try std.testing.expect(!s.active());
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.frac(P), 1e-6);
    try std.testing.expectApproxEqAbs(70.0 * P.hpFrac, paid, 0.5);
}

test "POISON CANNOT BE RE-APPLIED WHILE IT RUNS — a state you are already in, not a burst" {
    const P = ailRow(.poison);
    var s = Status{};
    s.add(P, P.max);
    _ = s.tick(P, 1.0 / 60.0, 70);
    try std.testing.expect(s.active());
    var t: f32 = 0;
    while (t < P.dur * 0.5) : (t += 1.0 / 60.0) _ = s.tick(P, 1.0 / 60.0, 70);
    const half = s.frac(P);
    for (0..40) |_| s.add(P, P.max);
    try std.testing.expectApproxEqAbs(half, s.frac(P), 1e-5);
    while (t < P.dur + 0.2) : (t += 1.0 / 60.0) _ = s.tick(P, 1.0 / 60.0, 70);
    try std.testing.expect(!s.active());
    s.add(P, 20.0);
    try std.testing.expect(s.frac(P) > 0.15);
}

test "LINGERING IS THE COST: the meter decays once the doses stop" {
    const P = ailRow(.poison);
    var s = Status{};
    s.add(P, P.max * 0.7);
    var t: f32 = 0;
    while (t < P.decayDelay * 0.5) : (t += 1.0 / 60.0) _ = s.tick(P, 1.0 / 60.0, 70);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), s.frac(P), 1e-3);
    while (t < P.decayDelay + P.max / P.decay + 0.2) : (t += 1.0 / 60.0) _ = s.tick(P, 1.0 / 60.0, 70);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.frac(P), 1e-6);
    try std.testing.expect(!s.active());
    var spaced = Status{};
    for (0..6) |_| {
        spaced.add(P, P.max * 0.45);
        var u: f32 = 0;
        while (u < P.decayDelay + P.max / P.decay) : (u += 1.0 / 60.0) _ = spaced.tick(P, 1.0 / 60.0, 70);
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
        if (spellDoses(s)) try std.testing.expect(spellBlow(s).?.dose.any()) else try std.testing.expect(spellDamage(s) > 0);
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

test "NOTHING BUILDS ON A BODY ALREADY STUNNED — a heavy landed inside a light stun takes no stance" {
    var v = Vitals.initFoe(100, 10, 30);
    _ = v.hit(.{ .dmg = 7 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .dmg = 7 }));
    try std.testing.expect(v.stunned());
    const stanceAt = v.stance;
    try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 1, .stance = 20 }));
    try std.testing.expectApproxEqAbs(stanceAt, v.stance, 1e-5);
    try std.testing.expectApproxEqAbs(FOE_LIGHT_STUN_DUR, v.stunLeft, 1e-5);
    v.build(.stun, 30);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.ailFrac(.stun), 1e-6);
}

test "A CREATURE'S FLINCH IS A SHARE OF ITS HEALTH IN BLOWS, NOT A COUNT OF THEM — and a drip pours nothing" {
    // Two blows worth the pool between them flinch it whatever their `poise` says; thirteen pokes of 1 do the same.
    var v = Vitals.initFoe(100, 10, 999);
    try std.testing.expectEqual(HitResult.none, v.hit(.{ .dmg = 7, .poise = 99 }));
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .dmg = 7 }));
    var pokes = Vitals.initFoe(100, 10, 999);
    var n: u32 = 0;
    var flinched = false;
    while (n < 13) : (n += 1) {
        if (pokes.hit(.{ .dmg = 1 }) == .light) flinched = true;
    }
    try std.testing.expect(flinched);
    var dripped = Vitals.initFoe(100, 10, 999);
    n = 0;
    while (n < 40) : (n += 1) try std.testing.expectEqual(HitResult.none, dripped.drip(.{ .dmg = 2 }));
    try std.testing.expectApproxEqAbs(dripped.poiseMax, dripped.poise, 1e-5);
    var hero = Vitals.init(100, 10, 999);
    try std.testing.expectEqual(HitResult.light, hero.hit(.{ .dmg = 1, .poise = 12 }));
}

test "YOU CANNOT DO ONE THING OVER AND OVER — each flinch, break and proc wears the next one harder, and the wear fades" {
    var v = Vitals.initFoe(100, 10, 999);
    var blows: u32 = 0;
    while (v.hit(.{ .dmg = 3 }) != .light) blows += 1;
    const first = blows;
    while (v.stunned()) v.tick(1.0 / 60.0);
    blows = 0;
    while (v.hit(.{ .dmg = 3 }) != .light) blows += 1;
    try std.testing.expect(blows > first);
    std.debug.print("\n  flinch wear: {d} blows the first time, {d} the second\n", .{ first + 1, blows + 1 });
    var t: f32 = 0;
    while (t < WEAR_HALFLIFE * 6) : (t += 1.0 / 30.0) v.tick(1.0 / 30.0);
    try std.testing.expect(v.lightWear < 0.05);

    var s = Vitals.initFoe(100, 999, 30);
    try std.testing.expectEqual(HitResult.heavy, s.hit(.{ .dmg = 1, .stance = 30 }));
    while (s.stunned()) s.tick(1.0 / 60.0);
    try std.testing.expectEqual(HitResult.none, s.hit(.{ .dmg = 1, .stance = 30 }));

    var p = Vitals.initFoe(100, 999, 999);
    p.build(.poison, POISON_MAX);
    _ = p.tickAils(1.0 / 60.0);
    try std.testing.expect(p.ailOn(.poison));
    try std.testing.expect(p.ailWear[@intFromEnum(Ail.poison)] > 0.9);
    p.clearAils();
    p.build(.poison, POISON_MAX);
    try std.testing.expect(p.ailFrac(.poison) < 0.7);
    var h = Vitals.init(100, 10, 999);
    _ = h.hit(.{ .poise = 12 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.lightWear, 1e-6);
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
    _ = v.hit(.{ .dmg = 7 });
    try std.testing.expectEqual(HitResult.light, v.hit(.{ .dmg = 7 }));
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
    // The damage that pours 15 into a 20 pool — the same chip, the creature's way.
    _ = foeV.hit(.{ .dmg = 15.0 / FOE_POISE_PER_DMG });
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

test "ALLOTTING MOVES THE SPLIT AND NEVER THE POOL — and it fills, the way a bonfire does" {
    var f = Flasks{};
    try std.testing.expectEqual(FLASK_TOTAL, f.total());
    try std.testing.expect(f.take());
    f.allot(FLASK_TOTAL);
    try std.testing.expectEqual(FLASK_TOTAL, f.total());
    try std.testing.expectEqual(FLASK_TOTAL, f.charges(.crimson));
    try std.testing.expectEqual(@as(u8, 0), f.charges(.cerulean));
    f.allot(0);
    try std.testing.expectEqual(FLASK_TOTAL, f.charges(.cerulean));
    try std.testing.expectEqual(@as(u8, 0), f.charges(.crimson));
    // Past the pool is clamped to it, never widened.
    f.allot(200);
    try std.testing.expectEqual(FLASK_TOTAL, f.total());
    try std.testing.expectEqual(FLASK_TOTAL, f.allotted(.crimson));
    std.debug.print("\n  flasks: a pool of {d}, split anywhere in 0..{d}\n", .{ FLASK_TOTAL, FLASK_TOTAL });
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
    q.add(.plain, ARROWS_MAX);
    q.add(.fire, FIRE_ARROWS_MAX);
    try std.testing.expectEqual(FIRE_ARROWS_MAX, q.count(.fire));
    try std.testing.expectEqual(ARROWS_MAX, q.count(.plain));
    for (0..NARROW) |_| q.cycle();
    try std.testing.expectEqual(ArrowKind.plain, q.sel);
}

/// How many kinds the quiver holds — off the enum, so a third arrow moves the round trip and the walk below with it rather than leaving two tests asserting a 2 that stopped being the count.
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

test "A SHEAF NEVER CARRIES MORE THAN THE QUIVER HOLDS" {
    // `item.zig` imports nothing but std, so the two halves of this contract are checked from THIS side — a sheaf worth more than the bank it fills silently bins the surplus the moment it is picked up.
    inline for (@typeInfo(item.Kind).@"enum".fields) |f| {
        const k: item.Kind = @enumFromInt(f.value);
        switch (item.use(k)) {
            .arrows => |a| {
                const c = Quiver.cap(if (a.fire) .fire else .plain);
                std.debug.print("\n  {s}: {d} arrows into a bank of {d}\n", .{ item.displayName(k), a.n, c });
                try std.testing.expect(a.n <= c);
            },
            else => {},
        }
    }
}

/// Flinches taken before the stagger, with `lightWear` held out — that channel is its own law, and this
/// measures the share and nothing else. 0 for a body the count never comes for.
fn flinchesUntilBreak(share: f32, cap: u32) u32 {
    var v = Vitals.initFoe(9999, 4, 40).withBreak(share);
    var n: u32 = 0;
    var swings: u32 = 0;
    while (swings < cap) : (swings += 1) {
        v.stunLeft = 0;
        v.lightWear = 0;
        switch (v.hit(.{ .dmg = 6 })) {
            .heavy => return n + 1,
            .light => n += 1,
            else => {},
        }
    }
    return 0;
}

test "THE FLINCH SHARE IS PER BODY — the count to a stagger is the share, and 0 is a body flinches never break" {
    const CAP: u32 = 64;
    const rows = [_]struct { share: f32, want: u32 }{
        .{ .share = LIGHT_BREAK_STANCE, .want = 3 },
        .{ .share = LIGHT_BREAK_STANCE / 2.0, .want = 5 },
        .{ .share = 1.0, .want = 1 },
        .{ .share = 0, .want = 0 },
    };
    std.debug.print("\n  flinch share:", .{});
    for (rows) |row| {
        const got = flinchesUntilBreak(row.share, CAP);
        std.debug.print(" {d:.2} -> {d} flinches;", .{ row.share, got });
        try std.testing.expectEqual(row.want, got);
        // The dial the bench prints and the fight it bills have to be the one number.
        const said = (Vitals.initFoe(9999, 4, 40).withBreak(row.share)).flinchesToBreak();
        try std.testing.expectEqual(row.want, said);
    }
    std.debug.print(" (0 is never)\n", .{});
}

test "A REFUSED FLINCH HANDS BACK WHATEVER THE SHARE WAS, not a global 0.40" {
    var v = Vitals.initFoe(400, 4, 40).withBreak(0.10);
    const was = v.poise;
    _ = v.hit(.{ .dmg = 6 });
    try std.testing.expectApproxEqAbs(v.stanceMax * (1.0 - 0.10), v.stance, 1e-4);
    v.refuseFlinch(was);
    try std.testing.expectApproxEqAbs(v.stanceMax, v.stance, 1e-4);
}
