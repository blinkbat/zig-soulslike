const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const gfx = @import("../gfx/gfx.zig");
const wf = @import("../world/worldfmt.zig");

const v3 = mathx.v3;


pub const FLASH_DUR: f32 = 0.20;
pub const FLASH_GAIN: f32 = 0.85;
pub const FROST_GAIN: f32 = 0.55;
pub const HERO_R: f32 = 0.36;
pub const HERO_REACH: f32 = 0.55;
pub const HERO_LOW: f32 = -0.10;
pub const HERO_HIGH: f32 = 1.71; // 0.95 of his 1.8 m stature
pub const HERO_EYE: f32 = 1.25;
pub fn closestApproach(bodyR: f32) f32 {
    return bodyR + HERO_R;
}

pub const AIRBORNE_LIFT: f32 = 0.04;

/// **WHAT A CREATURE IS, AND HOW IT GETS ABOUT — ONE ROW PER KIND, HERE.** Twenty-one creatures had no
/// vocabulary between them: every question about a whole family (does this thing swim, does it move at all,
/// is it a body a necromancer could raise) was answered per creature, in that creature's file, by name.
///
/// `Nature` is WHAT IT IS and `Gait` is HOW IT TRAVELS, and they are two axes on purpose — a shade and a
/// leechfly both leave the ground and are nothing else alike.
pub const Nature = enum {
    beast,
    demon,
    undead,
    humanoid,
    plant,
    /// Nothing in this world is one yet. It is named because the row it would fill is a row somebody would
    /// otherwise call `construct` in a comment and file under `beast`.
    construct,

    pub fn label(n: Nature) [:0]const u8 {
        return switch (n) {
            .beast => "Beast",
            .demon => "Demon",
            .undead => "Undead",
            .humanoid => "Humanoid",
            .plant => "Plant",
            .construct => "Construct",
        };
    }
};

/// **NOT `airborne()`, WHICH IS A DIFFERENT QUESTION.** That one is whether a body is off the ground THIS
/// FRAME (a toad mid-hop, a shade mid-blink) and it is what collision asks. This is what the creature IS:
/// a leechfly is `.flying` on every frame of its life, and a hopping toad is not.
pub const Gait = enum {
    /// On foot, and the water gate holds it (`game.gateTerrain`).
    walking,
    /// At home in it — the water gate does not apply at any depth.
    waterfaring,
    /// Over it.
    flying,
    /// Does not travel at all, so no gate has anything to say to it.
    rooted,

    pub fn label(g: Gait) [:0]const u8 {
        return switch (g) {
            .walking => "Walking",
            .waterfaring => "Waterfaring",
            .flying => "Flying",
            .rooted => "Rooted",
        };
    }
};

pub const Traits = struct { nature: Nature, gait: Gait = .walking };

pub fn traitsOf(k: wf.FoeKind) Traits {
    return switch (k) {
        .toad => .{ .nature = .beast, .gait = .waterfaring },
        .fen_lurker => .{ .nature = .demon, .gait = .waterfaring },
        .leechfly => .{ .nature = .beast, .gait = .flying },
        .shade => .{ .nature = .undead, .gait = .flying },
        .rooted => .{ .nature = .plant, .gait = .rooted },
        .brood_sac => .{ .nature = .beast, .gait = .rooted },
        .archer, .shieldman, .greatsword, .bone_knight, .necromancer => .{ .nature = .undead },
        .berserker, .priest, .slinger, .ogre => .{ .nature = .humanoid },
        .brood_mother, .broodling, .delver, .florid_ravager => .{ .nature = .beast },
        .shroom, .mushroom_mage => .{ .nature = .plant },
    };
}

/// **HOW DEEP A THING WILL GO IN, AS A SHARE OF ITS OWN STATURE.** The hero's own limit is 0.76 of his
/// (`env.WADE_MAX`) and he is the one who chose to be in there; a creature turns back at the hips. Read of
/// the body rather than a flat metre so a kobold and a cyclops are refused at their own waterlines.
pub const WADE_FRAC: f32 = 0.45;

/// The depth past which a creature will not follow. Infinite for anything the water is not an obstacle to,
/// which is what `Gait` is for — a fen demon lives down there and a leechfly is over it.
pub fn wadeLimit(k: wf.FoeKind, stature: f32) f32 {
    return switch (traitsOf(k).gait) {
        .walking => WADE_FRAC * mathx.maxF(stature, 0.2),
        .waterfaring, .flying, .rooted => std.math.floatMax(f32),
    };
}

/// **NO ATTACK COMES OUT OF NOWHERE** (owner's law): seconds a creature's kit must be VISIBLY MOVING before
/// it can deal damage. Derived from what already reads — the ogre's swipe, the brood's bite, the toad's gape,
/// all half a second and up — against the berserker's chop at 0.14 and the broodling's at 0.20, which read as
/// INSTANT. It is a FLOOR under the winds, never the length of one: `PARRY_LEAD` brackets those from above.
pub const TELL_MIN: f32 = 0.30;

/// HOW LONG BEFORE A BLOW LANDS IT CAN STILL BE CAUGHT ON THE BOARDS — one number, IN SECONDS, measured back
/// from the move's own impact frame, and it IS the parry's difficulty. **Every creature with windows reads
/// THIS one.** You parry an instant before THE HIT, whatever is swinging (owner's call), so a club, a mace,
/// a greatsword and a mother's fangs teach one rule. See `ogre.parryable` for the example.
pub const PARRY_LEAD: f32 = 0.18;

pub fn inParryWindow(left: f32) bool {
    return left >= 0 and left <= PARRY_LEAD;
}

/// THE HERO'S SHIELD, STAMPED ON EVERY MEMBER (`game.markParry`), and whether any of them was caught on it
/// this frame — a ONE-FRAME edge, `anyDied`'s, read after `update`.
pub fn setParry(foes: anytype, p: Parry) void {
    for (foes) |*f| f.parry = p;
}
pub fn anyParried(foes: anytype) bool {
    for (foes) |*f| {
        if (f.parried) return true;
    }
    return false;
}

pub fn corporeal(f: anytype) bool {
    return f.alive() and !f.dying();
}


/// HOW FAR PAST ITS OWN NOTICE RING a creature follows before turning for home. Per-creature: one flat 30 m
/// was both 2.7x the toad's aggro and the spacing between camps in `worlds/`.
pub const LEASH_SLACK: f32 = 6.0;
/// …and it is home again only this close — the hysteresis, so a foe at the boundary cannot flap.
pub const LEASH_HOME_R: f32 = 3.0;
pub const LEASH_CALM: f32 = 4.5;
/// Walking back into a homing foe turns it round, and for this long it cannot try to leave again. MUST stay
/// above `LEASH_CALM` (else standing still sheds it) and below `PROVOKE_HOLD` (what three blows buy); it is
/// also the debounce that stops a hero at the ring's edge flipping a foe between chase and return.
pub const REENGAGE_HOLD: f32 = 8.0;

pub const SIGHT_MEMORY: f32 = 6.0;

pub const PROVOKE_PER_HIT: f32 = 1.0;
pub const PROVOKE_ROUSE: f32 = 14.0;
pub const PROVOKE_BREAK: f32 = 2.5;
pub const PROVOKE_HOLD: f32 = 14.0;
pub const PROVOKE_DECAY: f32 = 0.35;

pub fn leashR(aggroR: f32) f32 {
    return aggroR + LEASH_SLACK;
}

pub const Leash = struct {
    sinceCombat: f32 = mathx.LONG_AGO,
    sinceSeen: f32 = 0,
    provoked: f32 = 0,
    rouseLeft: f32 = 0,
    breakLeft: f32 = 0,
    engagedLeft: f32 = 0,
    returning: bool = false,

    /// Per frame, BEFORE the state machine decides anything. `out` is how far the CREATURE is from its post
    /// and `heroOut` how far the HERO is from that same post — a walk home is never blind to him.
    ///
    /// **BOTH RANGES ARE MEASURED FROM THE POST, and that is the whole of the tether.** As the gap between
    /// the two BODIES, tethers nominally 17–30 m long released at 34 m (ogre) to 176 m (leechfly). The
    /// question a tether asks is "has he left my patch", and a patch is a place, not a separation.
    pub fn tick(self: *Leash, dt: f32, out: f32, heroOut: f32, aggroR: f32) void {
        self.sinceCombat += dt;
        self.sinceSeen += dt;
        self.provoked = mathx.maxF(0, self.provoked - PROVOKE_DECAY * dt);
        self.rouseLeft = mathx.maxF(0, self.rouseLeft - dt);
        self.breakLeft = mathx.maxF(0, self.breakLeft - dt);
        self.engagedLeft = mathx.maxF(0, self.engagedLeft - dt);
        if (self.breakLeft > 0) {
            self.returning = false;
            return;
        }
        if (self.returning) {
            if (out <= LEASH_HOME_R) {
                self.returning = false;
            } else if (heroOut <= aggroR) {
                self.reengage();
            }
            return;
        }
        if (self.engagedLeft > 0) return;
        if (out > leashR(aggroR) and heroOut > aggroR and self.sinceCombat >= LEASH_CALM) self.returning = true;
    }

    pub fn noteCombat(self: *Leash) void {
        self.sinceCombat = 0;
    }

    pub fn noteSeen(self: *Leash) void {
        self.sinceSeen = 0;
    }

    pub fn blindNow(self: *Leash) void {
        self.sinceSeen = mathx.LONG_AGO;
    }

    pub fn blind(self: *const Leash) bool {
        return self.sinceSeen > SIGHT_MEMORY and !self.roused();
    }

    pub fn provoke(self: *Leash) void {
        self.noteCombat();
        self.rouseLeft = PROVOKE_ROUSE;
        self.provoked += PROVOKE_PER_HIT;
        self.reengage();
        if (self.provoked >= PROVOKE_BREAK) self.breakLeft = PROVOKE_HOLD;
    }

    fn reengage(self: *Leash) void {
        self.returning = false;
        self.engagedLeft = REENGAGE_HOLD;
    }

    pub fn goingHome(self: *const Leash) bool {
        return self.returning;
    }

    pub fn roused(self: *const Leash) bool {
        return self.breakLeft > 0 or self.rouseLeft > 0;
    }
};

pub fn sensedDist(l: *const Leash, real: f32, aggroR: f32) f32 {
    if (l.blind()) return mathx.LONG_AGO; // it cannot see him, and it is past remembering where he was
    if (l.goingHome()) return mathx.LONG_AGO;
    if (l.roused()) return mathx.minF(real, aggroR);
    return real;
}

/// ONE FRAME OF A CREATURE'S TETHER, off the three points it is actually about — so `out` and `heroOut`
/// cannot be transposed into a tether that releases at the wrong range.
pub fn tickLeash(l: *Leash, dt: f32, at: rl.Vector3, home: rl.Vector3, hero: rl.Vector3, aggroR: f32) void {
    l.tick(dt, mathx.distXZ(at, home), mathx.distXZ(home, hero), aggroR);
}

/// …AND A FIXTURE'S, which is the same tether with the first distance known: a creature that never travels
/// is always at its post, so `out` is 0 by construction and the only thing the tether can still answer is
/// whether HE has left its patch. The rooted and the fen lurker each wrote this line out with the literal 0
/// in it, which is a hand-derived argument sitting where `tickLeash` exists to stop one.
pub fn tickFixedLeash(l: *Leash, dt: f32, home: rl.Vector3, hero: rl.Vector3, aggroR: f32) void {
    l.tick(dt, 0, mathx.distXZ(home, hero), aggroR);
}

pub fn senseHero(l: *const Leash, at: rl.Vector3, hero: rl.Vector3, aggroR: f32) f32 {
    return sensedDist(l, mathx.distXZ(at, hero), aggroR);
}

pub fn faceToward(pos: rl.Vector3, facing: *f32, target: rl.Vector3, rate: f32, dt: f32) void {
    const d = mathx.dirXZ(pos, target);
    if (mathx.lenXZ(d) < 1e-3) return;
    facing.* = mathx.approachAngle(facing.*, mathx.headingXZ(d), rate * dt);
}

pub const Nav = struct {
    dir: ?rl.Vector3 = null,
    /// WHICH WAY ROUND IT WENT LAST TIME, and this is the whole of why it does not dither: with both sides of
    /// an obstacle equally open, the side it already committed to wins, so a creature at a corner keeps going
    /// round the way it started instead of shivering in front of it. Re-set to whichever side actually worked
    /// every time a detour is taken, so it cannot commit to a wrong one for good.
    side: f32 = 1,

    pub fn aim(self: *const Nav, from: rl.Vector3, want: rl.Vector3) rl.Vector3 {
        const d = self.dir orelse return want;
        return mathx.addV(from, d);
    }

    pub fn along(self: *const Nav, want: rl.Vector3) rl.Vector3 {
        return self.dir orelse want;
    }
};

test "AN UNSTAMPED WAY CHANGES NOTHING — steering is a bend on a refused heading, never a layer on top of one" {
    const at = mathx.ground(0, 0);
    const want = mathx.ground(0, 10);
    var n = Nav{};
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(want, n.aim(at, want)), 1e-6);
    const straight = mathx.dirXZ(at, want);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(straight, n.along(straight)), 1e-6);
    n.dir = v3(1, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(mathx.ground(1, 0), n.aim(at, want)), 1e-6);
    try std.testing.expectApproxEqAbs(mathx.headingXZ(n.dir.?), mathx.headingXZ(mathx.dirXZ(at, n.aim(at, want))), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), n.along(straight).x, 1e-6);
}

/// How hard the bearing rate is smoothed — a creature answers a real orbit, never one frame of jitter.
pub const SENSE_SMOOTH: f32 = 6.0;
pub const PRESSURE_HALFLIFE: f32 = 3.2;

/// **WHAT A CREATURE KNOWS ABOUT HOW THE FIGHT IS GOING, and it is all WORLD STATE** — the bearing's own
/// measured rate and the damage its own body has taken since it last stood somewhere else. Neither reads the
/// hero's state machine, so the NO INPUT READING law is kept by construction: this is what any body standing
/// there could feel.
///
/// It exists because the two questions it answers were being re-derived per creature. `circleRate` was the
/// knight's alone, hand-rolled beside its state machine; `pressed` did not exist anywhere, which is why the
/// only reason he ever left a spot was that you walked round him — never that standing there was costing him.
///
/// **PRESSURE IS PER SPOT, NOT PER FIGHT** (`stood`). Damage banked against a place it has since left is not
/// a reason to leave again, so travelling further than `spanR` wipes the meter — otherwise a creature that
/// repositions once arrives already convinced it should reposition again, and that reads as panic.
pub const Sense = struct {
    bearingWas: f32 = 0,
    circleRate: f32 = 0,
    hurtHere: f32 = 0,
    stood: rl.Vector3 = mathx.zero3,

    /// ONE FRAME, before the state machine decides anything (`Leash.tick`'s slot). `bearing` is the quarry's
    /// bearing off the creature's own facing, in radians.
    ///
    /// `settled` is false while the creature's OWN movement is what is sweeping the bearing — a hop, a leap,
    /// a charge. Measured through one of those it reads its own travel as the hero circling it and answers a
    /// thing nobody did.
    pub fn tick(self: *Sense, dt: f32, at: rl.Vector3, bearing: f32, spanR: f32, settled: bool) void {
        const rate = @abs(mathx.wrapPi(bearing - self.bearingWas)) / mathx.maxF(dt, 1e-4);
        self.bearingWas = bearing;
        if (settled) self.circleRate = mathx.approach(self.circleRate, rate, dt * SENSE_SMOOTH);
        if (mathx.distXZ(at, self.stood) > spanR) {
            self.stood = at;
            self.hurtHere = 0;
            return;
        }
        self.hurtHere *= std.math.pow(f32, 0.5, dt / PRESSURE_HALFLIFE);
    }

    pub fn hurt(self: *Sense, dmg: f32) void {
        self.hurtHere += mathx.maxF(dmg, 0);
    }

    pub fn circling(self: *const Sense, rate: f32) bool {
        return self.circleRate > rate;
    }

    pub fn pressed(self: *const Sense, maxHp: f32, share: f32) bool {
        return self.hurtHere >= mathx.maxF(maxHp, 1) * share;
    }
};

test "PRESSURE IS PER SPOT: damage banked where it USED to stand is not a reason to leave where it is now" {
    var s = Sense{};
    const dt = 1.0 / 60.0;
    const here = mathx.ground(0, 0);
    s.tick(dt, here, 0, 0.5, true);
    s.hurt(40);
    try std.testing.expect(s.pressed(100, 0.3));
    var k: i32 = 0;
    while (k < 30) : (k += 1) s.tick(dt, here, 0, 0.5, true);
    try std.testing.expect(s.hurtHere > 0);
    s.tick(dt, mathx.ground(0, 3.0), 0, 0.5, true);
    try std.testing.expect(!s.pressed(100, 0.3));
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.hurtHere, 1e-6);
}

test "IT DOES NOT READ ITS OWN TRAVEL AS AN ORBIT" {
    var s = Sense{};
    const dt = 1.0 / 60.0;
    const at = mathx.ground(0, 0);
    var k: i32 = 0;
    var b: f32 = 0;
    while (k < 40) : (k += 1) {
        b += 0.05;
        s.tick(dt, at, b, 0.5, false);
    }
    try std.testing.expect(!s.circling(0.45));
    k = 0;
    while (k < 60) : (k += 1) {
        b += 0.05;
        s.tick(dt, at, b, 0.5, true);
    }
    try std.testing.expect(s.circling(0.45));
}

/// **HOW MANY MOTES A WOUND ACTUALLY THROWS** (owner: hits should have more particles, ~1.5x). ONE DIAL FOR
/// THE WHOLE FIELD. Every creature sheds something different when it is cut — blood, bone chips, splinters,
/// spores, ichor, dirt — and what each one sheds and how much of it relative to the others is that creature's
/// own business and stays in its own file. What is NOT per-creature is how heavy a landed blow reads overall,
/// and as twenty literals scattered over twelve files that was a number nobody could turn.
pub const HIT_PARTS: f32 = 1.5;

pub fn hitParts(n: i32) i32 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(n)) * HIT_PARTS));
}

pub fn flashFrac(flash: f32) f32 {
    return mathx.clampF(flash / FLASH_DUR, 0, 1);
}

/// …AND THE DRAIN THAT GOES WITH IT, because `FLASH_DUR` is a DURATION and only a decay of 1.0/s makes it
/// one. `wounded` stamps the meter at `FLASH_DUR` and `flashFrac` divides by it, so the pop is that long iff
/// the body counts down in real seconds. Written out per creature, fourteen did and THREE — the wolf and the
/// two hounds that copied it — subtracted `dt * 4.0` and popped for 0.05 s: hitting those three read as a
/// quarter of a flash against everything else on the same field, off a bare literal named nowhere.
pub fn fadeFlash(flash: *f32, dt: f32) void {
    flash.* = mathx.maxF(0, flash.* - dt);
}

/// A POINT ON A CREATURE'S OWN AXIS: `h` metres of ITS OWN SCALE above the ground under it, plus whatever it
/// is holding off that ground this frame (`lift` — a hop, a leap, a hover). EVERY WORLD POINT ON AN ACTOR IS
/// MEASURED FROM `pos.y` is the law it keeps: off the datum, a foe on a bank keeps its bar down in the field.
pub fn bodyPoint(pos: rl.Vector3, h: f32, scale: f32, lift: f32) rl.Vector3 {
    return v3(pos.x, pos.y + h * scale + lift, pos.z);
}

/// …AND A POINT ON THE POSED BODY ITSELF, which is a different thing entirely: `at` is in the BONE's own
/// frame, so the answer follows whatever that bone is doing this frame. THE RETICLE RIDES THIS — locked onto
/// a head, the mark dips when the head dips. Every bone matrix already carries the rig's scale, the facing
/// and `pos`, and every `spawn` poses before it returns, so the matrix is never undefined.
pub fn markOn(bone: rl.Matrix, at: rl.Vector3) rl.Vector3 {
    return rl.math.vector3Transform(at, bone);
}

pub fn swingCurve(u: f32) f32 {
    return std.math.pow(f32, mathx.smoothstep(0, 1, u), 1.35);
}

pub fn stunCurve(t: f32, heavy: bool) f32 {
    const u = mathx.clampF(t / combat.foeStunDur(heavy), 0, 1);
    if (!heavy) return mathx.sinf(u * std.math.pi);
    return mathx.pulse(u, 0, 0.14, 0.74, 1.0);
}

pub const Push = struct { light: f32, heavy: f32 };

pub const Clock = struct { wind: f32, strike: f32, recover: f32 };

pub fn moveClock(row: anytype) Clock {
    return .{ .wind = row.windDur, .strike = row.strikeDur, .recover = row.recoverDur };
}

pub fn reached(self: anytype, blade: Blade) ?Strike {
    const s = strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return null;
    self.leash.provoke();
    // **AND WHOEVER SWUNG IT JUST BOUGHT ITS ATTENTION.** The ONE place damage-threat is written, for the
    // reason `stunCurve` and `PARRY_LEAD` live here: the hero's blade and a spirit's jaws come through this
    // same door, so "who has been hurting me" cannot end up as two rules that disagree. The blade says who it
    // belongs to (`Blade.by`) — nothing here has to know what a wolf is.
    self.threat.hurtBy(blade.by, blade.hit.raw());
    if (blade.pierce) self.facing = mathx.headingXZ(mathx.scaleV(s.dir, -1));
    return s;
}

pub fn wounded(self: anytype, s: Strike, blade: Blade, push: Push) bool {
    self.hits += 1;
    self.flash = FLASH_DUR;
    const heavy = blade.hit.heavy();
    self.shove = mathx.scaleV(s.dir, if (heavy) push.heavy else push.light);
    return heavy;
}

/// ROOTED: THE FEET ARE HELD, AND NOTHING ELSE IS (owner's law) — the state machine runs, the kit swings, the
/// blow lands, and the body simply does not travel. Taken as a GATE at the end of a creature's own `update`
/// rather than a guard at each `stepXZ`, because a creature grows movements and a per-site list forgets one.
pub const Grip = struct {
    was: rl.Vector3,
    on: bool,
    killed: bool,

    pub fn hold(self: Grip, pos: *rl.Vector3) void {
        if (!self.on) return;
        pos.x = self.was.x;
        pos.z = self.was.z;
    }
};

/// ONE FRAME OF THE WAND'S GRIP, for every creature that can be caught in it. Taken at the TOP of `update`
/// and held through a `defer` there, so the pin covers whatever the state machine goes on to do:
///
///     const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
///     defer if (!self.airborne()) grip.hold(&self.pos);
///     if (grip.killed) self.enterDeath();
///
/// The airborne guard IS the finishes-its-arc half of the law below. Three creatures hold unconditionally:
/// the LEECHFLY because it is ALWAYS airborne and being rootable is its designed weakness, the OGRE and the
/// ROOTED because neither can leave the ground at all. The bite is billed as a DRIP, never as a blow.
pub fn canLeap(root: *const combat.Root) bool {
    return !root.held();
}

pub fn grip(root: *combat.Root, chill: *combat.Chill, vit: *combat.Vitals, dt: f32, at: rl.Vector3) Grip {
    const on = root.held();
    const bitten = if (root.tick(dt)) |bite| vit.drip(bite) == .death else false;
    const frozen = if (chill.tick(dt)) |bite| vit.drip(bite) == .death else false;
    return .{ .was = at, .on = on, .killed = bitten or frozen };
}

/// THE HERO'S SHIELD AS THE THING SWINGING AT HIM SEES IT — `Leash`'s pattern exactly, stamped every frame
/// from outside (`game.markParry`) rather than fetched, because the creature must never reach out for the
/// hero and because the ARC belongs to the shield, not to whatever is being caught on it.
pub const Parry = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    arc: f32 = combat.GUARD_ARC,

    pub fn catches(self: *const Parry, at: rl.Vector3, reach: f32) bool {
        if (!self.live) return false;
        if (mathx.distXZ(self.at, at) > reach) return false;
        const to = mathx.dirXZ(self.at, at);
        if (mathx.lenXZ(to) < 1e-4) return true;
        return combat.withinArc(mathx.headingXZ(to), self.facing, self.arc);
    }
};

/// **HOW DEEP THE WATER IS, AS A CREATURE STANDING IN IT SEES IT** — `Leash`'s and `Parry`'s arrangement
/// exactly, and for their reason: only `game.zig` can see the creature and `env`'s water field at once, and a
/// creature that reached out for the world would be a creature that knows about `Env`. Stamped every frame
/// (`game.markWade`) onto any body carrying the field, and read by the one creature that lives in it.
///
/// **AND IT IS A PLACE, NOT A STATE OF HIS.** `quarry` is how deep the water is where the HERO IS STANDING,
/// which is a fact about the ground — never about what he pressed. The NO INPUT READING law is kept by
/// construction: a thing under the surface can feel someone wading and could feel a wolf wading just as well.
pub const Wade = struct {
    here: f32 = 0,
    quarry: f32 = 0,
};

pub fn setWade(foes: anytype, at: anytype, quarry: f32, comptime depthAt: anytype) void {
    for (foes) |*f| f.wade = .{ .here = depthAt(at, f.pos), .quarry = quarry };
}

pub fn applyShove(pos: *rl.Vector3, shove: *rl.Vector3, decay: f32, bounds: f32, dt: f32) void {
    if (mathx.lenXZ(shove.*) <= 0.01) return;
    mathx.stepXZ(pos, shove.*, dt, bounds);
    shove.* = mathx.scaleV(shove.*, mathx.maxF(0, 1.0 - decay * dt));
}


pub const DUST = mathx.rgba(150, 132, 96, 175);
pub const MOTE = mathx.rgba(252, 198, 92, 170);
pub const WAKE = mathx.rgba(224, 230, 244, 255);

pub fn fxStream(seed: f32, mul: f32, salt: u64) mathx.Rng {
    return mathx.Rng.init(@as(u64, @intFromFloat(@abs(seed) * mul)) +% salt);
}

pub const Particle = struct {
    p: rl.Vector3 = mathx.zero3,
    v: rl.Vector3 = mathx.zero3,
    life: f32 = 0,
    max: f32 = 1,
    r0: f32 = 0.05,
    r1: f32 = 0.05,
    col: rl.Color = mathx.rgba(255, 255, 255, 255),
    grav: f32 = 0,
    floor: ?f32 = null,
};

pub fn emitTicks(acc: *f32, dt: f32, rate: f32, cap: usize) usize {
    acc.* += dt * rate;
    var n: usize = 0;
    while (acc.* >= 1.0 and n < cap) : (n += 1) acc.* -= 1.0;
    // **A HITCH IS A WHOLE MOTE STILL OWED AFTER THE CAP — NOT MERELY REACHING IT.** `n == cap` read a full
    // frame as a hitch, and `emitCap` FLOORS AT ONE, so at any rate under ~24/s the cap *is* one and every
    // ordinary mote tripped it: the leftover fraction was thrown away each time and the fenlurker's 16/s
    // wake ran at 15. What is dropped now is only what could not be paid, never the fraction that has simply
    // not become a mote yet — which is the one thing an accumulator exists to carry.
    if (acc.* >= 1.0) acc.* = 0;
    return n;
}

/// …AND THE CEILING ITSELF, off the rate — the ONE place "a couple of frames' arrears at 60 fps" is written
/// down. Below that a frame is a frame; above it, it is a hitch and the arrears are dropped. Every live
/// emitter owes far less than this per real frame, so it only ever bites on the stall it exists for.
/// Floored at ONE, or an emitter could never pay a single mote. **AND A CAP OF ONE IS THE NORMAL CASE, NOT
/// AN EDGE ONE** — every rate under ~24/s lands there, which is why `emitTicks` may not read reaching the cap
/// as a hitch (see the note at its own drop).
const EMIT_CAP_FRAMES: f32 = 2.5;
pub fn emitCap(rate: f32) usize {
    return @max(1, @as(usize, @intFromFloat(@ceil(mathx.maxF(rate, 0) / 60.0 * EMIT_CAP_FRAMES))));
}

test "THE CAP CLEARS A REAL FRAME AND NEVER LANDS ON ZERO" {
    for ([_]f32{ 5, 26, 54, 82, 240, 560 }) |rate| {
        try std.testing.expect(@as(f32, @floatFromInt(emitCap(rate))) > rate / 60.0);
    }
    try std.testing.expectEqual(@as(usize, 1), emitCap(0));
    var acc: f32 = 0;
    try std.testing.expectEqual(@as(usize, 1), emitTicks(&acc, 1.0, 1.0, emitCap(1.0)));
}

test "the accumulator carries a fraction across frames and DROPS a hitch's arrears" {
    var acc: f32 = 0;
    try std.testing.expectEqual(@as(usize, 10), emitTicks(&acc, 0.1, 100.0, 64));
    try std.testing.expectEqual(@as(usize, 0), emitTicks(&acc, 0.005, 100.0, 64));
    try std.testing.expectEqual(@as(usize, 1), emitTicks(&acc, 0.005, 100.0, 64));
    acc = 0;
    try std.testing.expectEqual(@as(usize, 24), emitTicks(&acc, 2.0, 560.0, 24));
    try std.testing.expectEqual(@as(f32, 0), acc);
    try std.testing.expectEqual(@as(usize, 0), emitTicks(&acc, 0, 560.0, 24));
}

test "A SLOW EMITTER RUNS AT ITS OWN RATE — a cap of one is not a hitch every time" {
    for ([_]f32{ 5.0, 9.0, 16.0, 22.0 }) |rate| {
        try std.testing.expectEqual(@as(usize, 1), emitCap(rate));
        var acc: f32 = 0;
        var n: usize = 0;
        var t: f32 = 0;
        const dt = 1.0 / 60.0;
        while (t < 10.0) : (t += dt) n += emitTicks(&acc, dt, rate, emitCap(rate));
        const got = @as(f32, @floatFromInt(n)) / 10.0;
        std.debug.print("  emitter at {d:.0}/s actually emits {d:.1}/s\n", .{ rate, got });
        try std.testing.expectApproxEqAbs(rate, got, 0.2);
    }
    var slow: f32 = 0;
    try std.testing.expectEqual(@as(usize, 1), emitTicks(&slow, 3.0, 16.0, emitCap(16.0)));
    try std.testing.expectEqual(@as(f32, 0), slow);
}

pub fn emitParticle(pool: []Particle, head: *usize, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
    pool[head.*] = .{ .p = p, .v = vel, .life = life, .max = life, .r0 = r0, .r1 = r1, .col = col, .grav = grav };
    head.* = (head.* + 1) % pool.len;
}

pub const Spray = struct {
    fanLo: f32,
    fanHi: f32,
    upLo: f32,
    upHi: f32,
    lifeLo: f32,
    lifeHi: f32,
    rLo: f32,
    rHi: f32,
    r1: f32,
    col: rl.Color,
    grav: f32,
};

/// **THE DRAW ORDER IS LOAD-BEARING** — angle, speed, the fan on X, the lift, the fan on Z, the life, the
/// radius. It is the order all five wrote by hand, and a helper that pulled the same numbers in another
/// order would give every one of them a different-looking wound off the very same seed.
pub fn spray(pool: []Particle, head: *usize, rng: *mathx.Rng, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32, scale: f32, s: Spray) void {
    const parts = hitParts(n);
    var i: i32 = 0;
    while (i < parts) : (i += 1) {
        const a = rng.angle();
        const sp = rng.range(0.4, 1.0) * spd;
        const vel = v3(
            dir.x * sp + mathx.cosf(a) * rng.range(s.fanLo, s.fanHi),
            rng.range(s.upLo, s.upHi),
            dir.z * sp + mathx.sinf(a) * rng.range(s.fanLo, s.fanHi),
        );
        emitParticle(pool, head, at, vel, rng.range(s.lifeLo, s.lifeHi), rng.range(s.rLo, s.rHi) * scale, s.r1, s.col, s.grav);
    }
}

test "THE SPRAY IS THE FIVE HAND-WRITTEN LOOPS, MOTE FOR MOTE — the draw order is the thing being pinned" {
    const S = Spray{
        .fanLo = 0.15, .fanHi = 0.8,
        .upLo = 0.7,   .upHi = 2.4,
        .lifeLo = 0.28, .lifeHi = 0.5,
        .rLo = 0.028,  .rHi = 0.055,
        .r1 = 0.008,   .col = DUST, .grav = 7.5,
    };
    const at = v3(1, 2, 3);
    const dir = v3(0.6, 0, -0.8);
    const scale: f32 = 1.3;

    var wantPool = [_]Particle{.{}} ** 64;
    var wantHead: usize = 0;
    var r = mathx.Rng.init(0xB10D);
    var i: i32 = 0;
    while (i < hitParts(9)) : (i += 1) {
        const a = r.angle();
        const sp = r.range(0.4, 1.0) * 2.5;
        const vel = v3(
            dir.x * sp + mathx.cosf(a) * r.range(S.fanLo, S.fanHi),
            r.range(S.upLo, S.upHi),
            dir.z * sp + mathx.sinf(a) * r.range(S.fanLo, S.fanHi),
        );
        emitParticle(&wantPool, &wantHead, at, vel, r.range(S.lifeLo, S.lifeHi), r.range(S.rLo, S.rHi) * scale, S.r1, S.col, S.grav);
    }

    var gotPool = [_]Particle{.{}} ** 64;
    var gotHead: usize = 0;
    var r2 = mathx.Rng.init(0xB10D);
    spray(&gotPool, &gotHead, &r2, at, dir, 9, 2.5, scale, S);

    try std.testing.expectEqual(wantHead, gotHead);
    try std.testing.expect(gotHead > 0);
    for (wantPool, gotPool) |w, g| {
        try std.testing.expectEqual(w.v.x, g.v.x);
        try std.testing.expectEqual(w.v.y, g.v.y);
        try std.testing.expectEqual(w.v.z, g.v.z);
        try std.testing.expectEqual(w.life, g.life);
        try std.testing.expectEqual(w.r0, g.r0);
    }
    std.debug.print("\n  spray: {d} motes, identical to the hand-written loop mote for mote\n", .{gotHead});
}

pub fn floorBurst(pool: []Particle, from: usize, to: usize, floor: f32) void {
    var i = from;
    while (i != to) : (i = (i + 1) % pool.len) pool[i].floor = floor;
}

pub const Dissolve = struct {
    rate: f32 = 54.0,
    spread: f32 = 0.85,
    rise: f32 = 0.70,
    flake: rl.Color = DUST,
};
const DISS_MOTE_SHARE: f32 = 0.76;
const DISS_MOTE_R: f32 = 0.094;
const DISS_FLAKE_R: f32 = 0.129;

pub fn dissolveMotes(self: anytype, dt: f32, d: Dissolve) void {
    const thinning = 1.0 - 0.6 * self.fade;
    var n = emitTicks(&self.fxAccum, dt, d.rate * thinning, emitCap(d.rate));
    while (n > 0) : (n -= 1) {
        const a = self.fxRng.angle();
        const rr = self.fxRng.range(0.1, 1.0) * d.spread * self.scale * thinning;
        const p = mathx.v3(
            self.pos.x + mathx.cosf(a) * rr,
            self.pos.y + self.fxRng.range(0.08, 1.0) * d.rise * self.scale,
            self.pos.z + mathx.sinf(a) * rr,
        );
        if (self.fxRng.float() < DISS_MOTE_SHARE) {
            emitParticle(&self.parts, &self.fxHead, p, mathx.v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.5, 1.4), self.fxRng.signed() * 0.3), self.fxRng.range(0.55, 1.05), self.fxRng.range(0.42, 1.0) * DISS_MOTE_R * d.spread * self.scale, 0.004, MOTE, -0.7);
        } else {
            emitParticle(&self.parts, &self.fxHead, p, mathx.v3(self.fxRng.signed() * 0.35, self.fxRng.range(0.1, 0.45), self.fxRng.signed() * 0.35), self.fxRng.range(0.32, 0.65), self.fxRng.range(0.55, 1.0) * DISS_FLAKE_R * d.spread * self.scale, 0.011, d.flake, 2.0);
        }
    }
}

/// **A CORPSE SOMETHING IS STANDING OVER DOES NOT GO** — the BODY's own `heldOpen` flag, stamped by
/// `game.markVigil` and read here as an OPT-IN, so the eleven creatures nothing raises are untouched and pay a
/// comptime-false branch. `markWays`' arrangement (`@hasField`) and `blocksOf`'s, for their reason: gaining a
/// behaviour is a FIELD on the creature and never an edit to the shared pass.
fn stayed(self: anytype) bool {
    if (comptime @hasField(std.meta.Child(@TypeOf(self)), "heldOpen")) return self.heldOpen;
    return false;
}

pub fn dissipate(self: anytype, dt: f32, still: f32, diss: f32, d: Dissolve) void {
    if (self.t < still) return;
    if (stayed(self)) return;
    self.fade = mathx.smoothstep(still, still + diss, self.t);
    dissolveMotes(self, dt, d);
    if (self.t >= still + diss) self.gone = true;
}

/// **THE BODY COMING BACK UP** — `dissipate` run backwards, and the one copy of it. It reads FIELDS ONLY for
/// `dissolveMotes`' reason, which is what lets it live here at all: `vit`, `fade`, `gone`, `hitLatch`,
/// `flash`, `shove`, `justDied`, `heldOpen`, `t`. `hits` is deliberately NOT among them — it is the running
/// tally `game.allHits` diffs across a frame to hear the blade land, and a body that reset it mid-frame would
/// take the total DOWN. The STATE it comes up in is not here and cannot be — a state machine's
/// enum is private to its own file — so a creature's own `reraise` calls this and then says what it is doing
/// next, which is the whole of what each one has to write.
pub fn rekindle(self: anytype, frac: f32) void {
    self.vit.revive(frac);
    self.fade = 0;
    self.gone = false;
    self.hitLatch = false;
    self.flash = FLASH_DUR;
    self.shove = mathx.zero3;
    self.justDied = false;
    self.heldOpen = false;
    self.t = 0;
}

pub fn tickParticles(pool: []Particle, dt: f32, floor: f32) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        q.life -= dt;
        q.p.x += q.v.x * dt;
        q.p.y += q.v.y * dt;
        q.p.z += q.v.z * dt;
        q.v.y -= q.grav * dt;
        const at = q.floor orelse floor;
        if (q.p.y < at) q.p.y = at;
    }
}

const TrailSample = struct { a: rl.Vector3 = mathx.zero3, b: rl.Vector3 = mathx.zero3, age: f32 = mathx.LONG_AGO };

/// Metres the point must travel in a frame to be worth a sample. A DEGENERACY GUARD, not a per-weapon dial:
/// 0.05 m at 60 fps is 3 m/s of tip, and nothing slower is a swing — so callers do not get to pass their own.
pub const TRAIL_SWEEP_MIN: f32 = 0.05;

pub fn Trail(comptime N: usize) type {
    return struct {
        const Self = @This();
        s: [N]TrailSample = [_]TrailSample{.{}} ** N,
        head: usize = 0,

        /// The segment `root`..1 of `base`→`tip`, kept only if the tip actually MOVED — a stationary blade
        /// laying down samples fills the ring with a stack of identical quads and the ribbon never fades.
        pub fn push(self: *Self, base: rl.Vector3, tip: rl.Vector3, prevTip: rl.Vector3, root: f32) void {
            if (mathx.lenV(mathx.subV(tip, prevTip)) <= TRAIL_SWEEP_MIN) return;
            self.head = (self.head + 1) % N;
            self.s[self.head] = .{ .a = mathx.lerpV(base, tip, root), .b = tip, .age = 0 };
        }
        pub fn age(self: *Self, dt: f32) void {
            for (&self.s) |*q| q.age = mathx.minF(q.age + dt, mathx.LONG_AGO);
        }
        pub fn reset(self: *Self) void {
            for (&self.s) |*q| q.age = mathx.LONG_AGO;
        }
        pub fn draw(self: *const Self, life: f32, col: rl.Color, peak: f32) void {
            if (self.s[self.head].age >= life) return;
            rl.gl.rlDisableBackfaceCulling();
            defer rl.gl.rlEnableBackfaceCulling();
            var i: usize = 0;
            while (i + 1 < N) : (i += 1) {
                const s0 = &self.s[(self.head + N - i) % N];
                const s1 = &self.s[(self.head + N - i - 1) % N];
                if (s0.age >= life or s1.age >= life) break;
                const f = 1.0 - 0.5 * (s0.age + s1.age) / life;
                const strip = [4]rl.Vector3{ s0.a, s0.b, s1.a, s1.b };
                rl.drawTriangleStrip3D(&strip, mathx.withAlpha(col, mathx.u8f(peak * f * f)));
            }
        }
    };
}

const PART_FINE_R: f32 = 0.10;
const PART_MID_R: f32 = 0.04;
pub fn drawParticles(pool: []const Particle) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        const frac = mathx.clampF(q.life / q.max, 0, 1);
        const rad = mathx.lerpF(q.r1, q.r0, frac);
        const a = mathx.u8f(@as(f32, @floatFromInt(q.col.a)) * frac);
        const rings: i32 = if (rad >= PART_FINE_R) 6 else if (rad >= PART_MID_R) 4 else 3;
        const slices: i32 = if (rad >= PART_FINE_R) 8 else if (rad >= PART_MID_R) 6 else 4;
        rl.drawSphereEx(q.p, rad, rings, slices, mathx.withAlpha(q.col, a));
    }
}


pub fn resetGroup(comptime T: type, out: []T, n: *usize, m: *const wf.Map, want: wf.FoeKind) void {
    n.* = 0;
    for (m.foes[0..m.nfoes]) |h| {
        if (h.kind != want or n.* >= out.len) continue;
        // ON THE GROUND: a spawn table stores x/z only, so a foe on a sculpted rise dropped at y = 0 is
        // buried to the waist.
        out[n.*] = T.spawn(v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
        n.* += 1;
    }
}

pub fn resetRoles(
    comptime T: type,
    comptime R: type,
    out: []T,
    n: *usize,
    m: *const wf.Map,
    comptime roleOf: fn (wf.FoeKind) ?R,
) void {
    n.* = 0;
    for (m.foes[0..m.nfoes]) |h| {
        const role = roleOf(h.kind) orelse continue;
        if (n.* >= out.len) continue;
        out[n.*] = T.spawnAs(role, v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
        n.* += 1;
    }
}

pub fn drawGroup(foes: anytype, model: anytype, scene: ?*gfx.Scene) void {
    var lit: f32 = -1;
    var iced: f32 = -1;
    for (foes) |*f| {
        if (!f.alive()) continue;
        if (scene) |sc| {
            const want = FLASH_GAIN * f.flashFrac();
            if (want != lit) {
                sc.setFlash(want);
                lit = want;
            }
            if (comptime @hasField(@TypeOf(f.*), "chill")) {
                const cold = FROST_GAIN * f.chill.frac();
                if (cold != iced) {
                    sc.setFrost(cold);
                    iced = cold;
                }
            }
        }
        f.draw(model);
    }
    if (scene) |sc| {
        if (lit > 0) sc.setFlash(0);
        if (iced > 0) sc.setFrost(0);
    }
}

pub fn anyDied(foes: anytype) bool {
    for (foes) |*f| {
        if (f.justDied) return true;
    }
    return false;
}

pub fn totalHits(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| n += f.hits;
    return n;
}

pub fn soulsDropped(foes: anytype, per: u32) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += per;
    }
    return n;
}

pub fn soulsEach(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += f.soulValue();
    }
    return n;
}

pub fn aliveCount(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.alive()) n += 1;
    }
    return n;
}

pub fn weaponReaches(was: [2]rl.Vector3, now: [2]rl.Vector3, hero: rl.Vector3, r: f32) bool {
    const lo = v3(hero.x, hero.y + HERO_LOW, hero.z);
    const hi = v3(hero.x, hero.y + HERO_HIGH, hero.z);
    const SWEEP = 3;
    const ALONG = 4;
    for (0..SWEEP + 1) |si| {
        const sk = @as(f32, @floatFromInt(si)) / SWEEP;
        const a0 = mathx.lerpV(was[0], now[0], sk);
        const a1 = mathx.lerpV(was[1], now[1], sk);
        for (0..ALONG + 1) |pi| {
            const p = mathx.lerpV(a0, a1, @as(f32, @floatFromInt(pi)) / ALONG);
            if (mathx.lenV(mathx.subV(p, mathx.closestOnSegV(p, lo, hi))) <= r) return true;
        }
    }
    return false;
}

pub const Blade = struct {
    active: bool = false,
    r: f32 = 0,
    a: rl.Vector3 = mathx.zero3,
    b: rl.Vector3 = mathx.zero3,
    a0: rl.Vector3 = mathx.zero3,
    b0: rl.Vector3 = mathx.zero3,
    hit: combat.Hit = .{},
    pierce: bool = false,
    cullAt: f32 = 0,
    through: bool = false,
    by: Victim = .hero,
};


pub const Victim = enum { hero, spirit };

pub const THREAT_HALFLIFE: f32 = 5.0;
/// How much threat a point of damage is worth. Only the RATIO between this and `THREAT_PROX` matters — this
/// one is 1.0 so that damage numbers read directly as threat and the other dial is the one to turn.
pub const THREAT_PER_DMG: f32 = 1.0;
pub const THREAT_PROX: f32 = 26.0;
pub const THREAT_PROX_R: f32 = 9.0;
pub const SPIRIT_TAUNT: f32 = 1.55;
pub const THREAT_SWITCH: f32 = 1.30;
pub const THREAT_DWELL: f32 = 0.65;

pub const Threat = struct {
    dmgHero: f32 = 0,
    dmgSpirit: f32 = 0,
    on: Victim = .hero,
    since: f32 = mathx.LONG_AGO,
    /// Where that victim is standing, stamped each frame by the game (`game.markThreat`). The creature reads
    /// this and never asks what a spirit is.
    at: rl.Vector3 = mathx.zero3,
    hasSpirit: bool = false,

    pub fn aim(self: *const Threat, heroPos: rl.Vector3) rl.Vector3 {
        if (!self.hasSpirit or self.on == .hero) return heroPos;
        return self.at;
    }

    pub fn hurtBy(self: *Threat, who: Victim, dmg: f32) void {
        const t = mathx.maxF(dmg, 0) * THREAT_PER_DMG;
        switch (who) {
            .hero => self.dmgHero += t,
            .spirit => self.dmgSpirit += t,
        }
    }

    pub fn score(dmg: f32, dist: f32, taunt: f32) f32 {
        const prox = mathx.clampF((THREAT_PROX_R - dist) / THREAT_PROX_R, 0, 1);
        return (dmg + THREAT_PROX * prox * prox) * taunt;
    }

    pub fn tick(self: *Threat, dt: f32, distHero: f32, distSpirit: f32, spirit: bool) void {
        self.hasSpirit = spirit;
        self.since += dt;
        const k = std.math.pow(f32, 0.5, dt / THREAT_HALFLIFE);
        self.dmgHero *= k;
        self.dmgSpirit *= k;
        if (!spirit) {
            self.on = .hero;
            self.dmgSpirit = 0;
            return;
        }
        if (self.since < THREAT_DWELL) return;
        // …and the scores are solved BELOW the dwell, not above it: they are pure, so every creature on the
        // field was computing a pair it then threw away for the whole 0.65 s after any change of mind.
        const h = score(self.dmgHero, distHero, 1.0);
        const s = score(self.dmgSpirit, distSpirit, SPIRIT_TAUNT);
        const want: Victim = switch (self.on) {
            .hero => if (s > h * THREAT_SWITCH) .spirit else .hero,
            .spirit => if (h > s * THREAT_SWITCH) .hero else .spirit,
        };
        if (want != self.on) {
            self.on = want;
            self.since = 0;
        }
    }
};

pub const Blow = struct {
    hit: combat.Hit,
    from: rl.Vector3,
    on: Victim = .hero,
};

pub fn worseBlow(worst: *?Blow, h: combat.Hit, from: rl.Vector3, on: Victim) void {
    if (worst.* == null or h.raw() > worst.*.?.hit.raw()) worst.* = .{ .hit = h, .from = from, .on = on };
}

pub fn groupBlow(foes: anytype, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?Blow {
    var worst: ?Blow = null;
    for (foes) |*f| {
        if (f.update(dt, f.threat.aim(hero), bounds, blade)) |h| worseBlow(&worst, h, f.pos, f.threat.on);
    }
    return worst;
}

test "THREAT: hitting something takes its attention, and letting up hands it back" {
    var t = Threat{ .hasSpirit = true, .on = .spirit };
    t.since = 100;
    t.tick(1.0 / 60.0, 3.0, 3.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    t.hurtBy(.hero, 60);
    t.tick(1.0 / 60.0, 3.0, 3.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
    var s: f32 = 0;
    while (s < 14.0) : (s += 1.0 / 60.0) t.tick(1.0 / 60.0, 14.0, 2.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
}

test "THREAT: standing close is its own claim, with nobody hitting anything" {
    var t = Threat{ .hasSpirit = true, .on = .spirit };
    t.since = 100;
    t.tick(1.0 / 60.0, 0.6, 12.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
}

test "THREAT DOES NOT DITHER — a near-tie holds whoever has it, whichever way round" {
    const D: f32 = 5.0;
    const inside = THREAT_SWITCH - 0.05;
    const h = Threat.score(100, D, 1.0);
    const prox = Threat.score(0, D, 1.0);
    const dS = h * inside / SPIRIT_TAUNT - prox;

    var t = Threat{ .hasSpirit = true, .on = .spirit, .dmgHero = 100, .dmgSpirit = dS };
    t.since = 100;
    t.tick(1.0 / 60.0, D, D, true);
    try std.testing.expectEqual(Victim.spirit, t.on);

    var u = Threat{ .hasSpirit = true, .on = .hero, .dmgHero = 100, .dmgSpirit = dS };
    u.since = 100;
    u.tick(1.0 / 60.0, D, D, true);
    try std.testing.expectEqual(Victim.hero, u.on);
}

test "THREAT: it will not change its mind twice in a heartbeat" {
    var t = Threat{ .hasSpirit = true, .on = .hero };
    t.since = 100;
    t.hurtBy(.spirit, 400);
    t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    t.hurtBy(.hero, 4000);
    t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    var s: f32 = 0;
    while (s < THREAT_DWELL + 0.1) : (s += 1.0 / 60.0) t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
}

test "WITH NO SPIRIT ON THE FIELD it is the hero, exactly as it always was" {
    var t = Threat{};
    t.hurtBy(.spirit, 500);
    t.tick(1.0 / 60.0, 30.0, 0.0, false);
    try std.testing.expectEqual(Victim.hero, t.on);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.dmgSpirit, 1e-6);
    const hero = v3(1, 0, 2);
    try std.testing.expectEqual(hero.x, t.aim(hero).x);
}

fn blocksOf(f: anytype) u32 {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "blocksTaken")) return f.blocksTaken();
    return 0;
}

pub fn pierceGroup(foes: anytype, blade: Blade) bool {
    var hit = false;
    for (foes) |*f| {
        if (!corporeal(f)) continue;
        const before = f.hits;
        const caught = blocksOf(f);
        f.tryHit(blade);
        if (f.hits == before and blocksOf(f) == caught) continue;
        hit = true;
        if (!blade.through) return true;
    }
    return hit;
}

pub const Strike = struct {
    contact: rl.Vector3,
    dir: rl.Vector3,
    reaction: combat.HitResult,
};

pub fn strike(vit: *combat.Vitals, hitLatch: *bool, center: rl.Vector3, hurtR: f32, blade: Blade) ?Strike {
    if (blade.pierce) {
        if (!blade.active) return null;
    } else {
        if (!blade.active) {
            hitLatch.* = false;
            return null;
        }
        if (hitLatch.*) return null;
    }
    const reach = hurtR + blade.r;
    const q1 = mathx.closestOnSegV(center, blade.a, blade.b);
    const hit1 = mathx.lenV(mathx.subV(center, q1)) <= reach;
    const q0 = mathx.closestOnSegV(center, blade.a0, blade.b0);
    if (!(hit1 or mathx.lenV(mathx.subV(center, q0)) <= reach)) return null;
    if (!blade.pierce) hitLatch.* = true;
    const contact = if (hit1) q1 else q0;
    var sweep = if (blade.pierce)
        mathx.subV(blade.b, blade.a)
    else
        mathx.subV(mathx.lerpV(blade.a, blade.b, 0.7), mathx.lerpV(blade.a0, blade.b0, 0.7));
    sweep.y = 0;
    const dir = if (mathx.lenXZ(sweep) > 0.03) mathx.normV(sweep) else mathx.dirXZ(contact, center);
    // **THE CULL IS READ BEFORE THE BLOW, NEVER AFTER IT.** Asked of the HP the body walked into the swing
    // with, so it is a threshold a player can see on the bar and aim for; asked afterwards it would just be
    // "anything the blow nearly killed", which is a different mechanic wearing the same name. It kills
    // through the ordinary path (`Vitals.hit` with the rest of its health) so the death, the reaction, the
    // souls and the drop are the blow's own — nothing here reaches past `vit`.
    if (blade.cullAt > 0 and !vit.dead and vit.hpFrac() <= blade.cullAt) {
        var out = blade.hit;
        out.dmg += vit.hp;
        return .{ .contact = contact, .dir = dir, .reaction = vit.hit(out) };
    }
    return .{ .contact = contact, .dir = dir, .reaction = vit.hit(blade.hit) };
}

test "A SHAFT IS SPENT ON THE FIRST BODY AND A LANCE GOES THROUGH THE LINE" {
    const Dummy = struct {
        pos: rl.Vector3,
        hits: u32 = 0,
        vit: combat.Vitals = combat.Vitals.initFoe(100, 999, 999),
        fn alive(_: *const @This()) bool {
            return true;
        }
        fn dying(_: *const @This()) bool {
            return false;
        }
        fn tryHit(self: *@This(), b: Blade) void {
            if (!b.active or mathx.lenV(mathx.subV(self.pos, mathx.closestOnSegV(self.pos, b.a, b.b))) > b.r) return;
            self.hits += 1;
            _ = self.vit.hit(b.hit);
        }
    };
    const line = [3]rl.Vector3{ v3(1, 1, 0), v3(2, 1, 0), v3(3, 1, 0) };
    const shaft = Blade{ .active = true, .pierce = true, .r = 0.5, .a = v3(0, 1, 0), .b = v3(9, 1, 0), .a0 = v3(0, 1, 0), .b0 = v3(9, 1, 0), .hit = .{ .dmg = 5 } };

    var spent = [3]Dummy{ .{ .pos = line[0] }, .{ .pos = line[1] }, .{ .pos = line[2] } };
    try std.testing.expect(pierceGroup(&spent, shaft));
    try std.testing.expectEqual(@as(u32, 1), spent[0].hits);
    try std.testing.expectEqual(@as(u32, 0), spent[1].hits);
    try std.testing.expectEqual(@as(u32, 0), spent[2].hits);

    var run = [3]Dummy{ .{ .pos = line[0] }, .{ .pos = line[1] }, .{ .pos = line[2] } };
    var lance = shaft;
    lance.through = true;
    try std.testing.expect(pierceGroup(&run, lance));
    for (&run) |*d| {
        try std.testing.expectEqual(@as(u32, 1), d.hits);
        try std.testing.expect(d.vit.hp < d.vit.hpMax);
    }
    // …and it still reports a MISS when the line is empty, or `throwLance` cannot tell one from a hit.
    var wide = [1]Dummy{.{ .pos = v3(0, 1, 40) }};
    try std.testing.expect(!pierceGroup(&wide, lance));
}

test "a CORPSE is not a body in the way, from the frame it starts to fall" {
    const Dummy = struct {
        gone: bool = false,
        down: bool = false,
        fn alive(self: *const @This()) bool {
            return !self.gone;
        }
        fn dying(self: *const @This()) bool {
            return self.down;
        }
    };
    var d = Dummy{};
    try std.testing.expect(corporeal(&d));
    d.down = true;
    try std.testing.expect(!corporeal(&d));
    d.gone = true;
    try std.testing.expect(!corporeal(&d));
}

test "THE SHIELD IS A DIRECTION AND EACH MOVE ITS OWN REACH" {
    const hero = v3(0, 0, 0);
    var p = Parry{ .live = false, .at = hero, .facing = 0 };
    const ahead = v3(0, 0, 3);
    try std.testing.expect(!p.catches(ahead, 4.0));
    p.live = true;
    try std.testing.expect(p.catches(ahead, 4.0));
    try std.testing.expect(!p.catches(ahead, 2.0));
    // Behind the arc. GUARD_ARC either side of facing, so a foe at 90 deg is out and one just inside is in.
    const flank = v3(3, 0, 0);
    try std.testing.expect(!p.catches(flank, 4.0));
    const edge = mathx.radians(combat.GUARD_ARC - 2.0);
    try std.testing.expect(p.catches(v3(3.0 * mathx.sinf(edge), 0, 3.0 * mathx.cosf(edge)), 4.0));
    const past = mathx.radians(combat.GUARD_ARC + 2.0);
    try std.testing.expect(!p.catches(v3(3.0 * mathx.sinf(past), 0, 3.0 * mathx.cosf(past)), 4.0));
    p.facing = std.math.pi;
    try std.testing.expect(!p.catches(ahead, 4.0));
    try std.testing.expect(p.catches(v3(0, 0, -3), 4.0));
}

test "THE LEASH: a foe drawn far from home walks back once the fight has gone quiet" {
    var l = Leash{};
    const aggro: f32 = 20.0;
    const far = leashR(aggro) + 8.0;
    const gone = aggro + 1.0; // the hero, OUT OF ITS PATCH — every range here is measured from the POST
    l.noteCombat();
    l.tick(1.0 / 60.0, far, gone, aggro);
    try std.testing.expect(!l.goingHome());
    var t: f32 = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, gone, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, leashR(aggro) - 1.0, gone, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, LEASH_HOME_R - 0.5, gone, aggro);
    try std.testing.expect(!l.goingHome());
    var near = Leash{};
    t = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) near.tick(1.0 / 60.0, 2.0, gone, aggro);
    try std.testing.expect(!near.goingHome());
}

test "IT NEVER TURNS ROUND WHILE HE IS STILL IN ITS PATCH, and walking back in ends the walk home" {
    const aggro: f32 = 20.0;
    const far = leashR(aggro) + 8.0;
    var toe = Leash{};
    var t: f32 = 0;
    while (t < LEASH_CALM * 3.0) : (t += 1.0 / 60.0) toe.tick(1.0 / 60.0, far, 1.2, aggro);
    try std.testing.expect(!toe.goingHome());

    var l = Leash{};
    t = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, aggro + 1.0, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, far, aggro - 0.5, aggro);
    try std.testing.expect(!l.goingHome());
    // …and RE-ENGAGING COSTS HIM: it cannot try to leave again on the next quiet moment, only after the hold.
    t = 0;
    while (t < REENGAGE_HOLD - 1.0) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, aggro + 1.0, aggro);
    try std.testing.expect(!l.goingHome());
    while (t < REENGAGE_HOLD + 0.2) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, aggro + 1.0, aggro);
    try std.testing.expect(l.goingHome());
}

test "ONE PLAYER HIT ROUSES IT FROM ANY RANGE, and KEEPING AT IT breaks the leash" {
    var l = Leash{};
    try std.testing.expect(!l.roused());
    l.provoke();
    try std.testing.expect(l.roused());
    const aggro: f32 = 20.0;
    var t: f32 = 0;
    while (t < PROVOKE_ROUSE - 0.5) : (t += 1.0 / 60.0) {
        l.tick(1.0 / 60.0, 0, aggro + 1.0, aggro);
        try std.testing.expect(l.roused());
    }
    while (t < PROVOKE_ROUSE + 0.5) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, 0, aggro + 1.0, aggro);
    try std.testing.expect(!l.roused());

    var c = Leash{};
    const far = leashR(aggro) + 8.0;
    const sniped = aggro * 2.0;
    t = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    c.provoke();
    c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(!c.goingHome());
    try std.testing.expect(c.roused());
    t = 0;
    while (t < REENGAGE_HOLD + LEASH_CALM + 0.2) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    c.provoke();
    c.provoke();
    c.provoke();
    c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(!c.goingHome());
    t = 0;
    while (t < REENGAGE_HOLD + LEASH_CALM + 1.0) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(!c.goingHome());
    t = 0;
    while (t < PROVOKE_HOLD + LEASH_CALM + 1.0) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    try std.testing.expect(!c.roused());
}

test "NOTHING NOTICES WHAT IT CANNOT SEE, and it keeps at him a while after it loses him" {
    const aggro: f32 = 20.0;
    var l = Leash{};
    l.blindNow();
    try std.testing.expect(l.blind());
    try std.testing.expect(sensedDist(&l, 1.0, aggro) > aggro);
    l.noteSeen();
    try std.testing.expect(!l.blind());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sensedDist(&l, 1.0, aggro), 1e-4);
    var t: f32 = 0;
    while (t < SIGHT_MEMORY - 0.5) : (t += 1.0 / 60.0) {
        l.tick(1.0 / 60.0, 0, 1.0, aggro);
        try std.testing.expect(!l.blind());
    }
    while (t < SIGHT_MEMORY + 0.5) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, 0, 1.0, aggro);
    try std.testing.expect(l.blind());

    // A BLOW STILL FINDS IT THROUGH COVER: being shot from somewhere it cannot see is exactly when a foe
    // must come looking, so the rouse outranks blindness.
    var shot = Leash{};
    shot.blindNow();
    shot.provoke();
    try std.testing.expect(!shot.blind());
    try std.testing.expect(sensedDist(&shot, 40.0, aggro) <= aggro);
}

test "the leash constants say what the rule is" {
    try std.testing.expect(LEASH_HOME_R < LEASH_SLACK);
    try std.testing.expect(LEASH_SLACK > 0 and leashR(11.0) > 11.0);
    try std.testing.expect(PROVOKE_BREAK > PROVOKE_PER_HIT);
    try std.testing.expect(PROVOKE_ROUSE > LEASH_CALM * 2.0);
    try std.testing.expect(PROVOKE_HOLD > LEASH_CALM * 2.0);
    try std.testing.expect(REENGAGE_HOLD > LEASH_CALM and REENGAGE_HOLD < PROVOKE_HOLD);
    try std.testing.expect(SIGHT_MEMORY > LEASH_CALM);
}

test "A SHAFT'S blood and shove run ALONG its flight, and it never touches the swing latch" {
    var vit = combat.Vitals.init(100, 999, 999);
    var latch = false;
    const shaft = mathx.v3(-1, 1, 0.3);
    const tip = mathx.v3(1, 1, 0.3);
    const s = strike(&vit, &latch, mathx.v3(0, 1, 0), 0.5, .{
        .active = true,
        .pierce = true,
        .r = 0.16,
        .a = shaft,
        .b = tip,
        .a0 = shaft,
        .b0 = tip,
        .hit = .{ .dmg = 5 },
    }).?;
    try std.testing.expect(s.dir.x > 0.95);
    try std.testing.expect(@abs(s.dir.z) < 0.2);
    try std.testing.expect(!latch);
    const again = strike(&vit, &latch, mathx.v3(0, 1, 0), 0.5, .{
        .active = true,
        .pierce = true,
        .r = 0.16,
        .a = shaft,
        .b = tip,
        .a0 = shaft,
        .b0 = tip,
        .hit = .{ .dmg = 5 },
    });
    try std.testing.expect(again != null);
}

test "strike: latches one hit per swing, re-arms when the window closes, applies the reaction" {
    var vit = combat.Vitals.init(100, 8, 100);
    var latch = false;
    const c = mathx.v3(0, 1, 0);
    const active = Blade{ .active = true, .r = 0.4, .a = mathx.v3(0, 1, -1), .b = mathx.v3(0, 1, 1), .a0 = mathx.v3(0, 1, -1), .b0 = mathx.v3(0, 1, 1), .hit = .{ .dmg = 10, .poise = 20 } };
    const s = strike(&vit, &latch, c, 0.5, active);
    try std.testing.expect(s != null);
    try std.testing.expectEqual(combat.HitResult.light, s.?.reaction);
    try std.testing.expect(latch);
    try std.testing.expect(strike(&vit, &latch, c, 0.5, active) == null);
    _ = strike(&vit, &latch, c, 0.5, .{ .active = false });
    try std.testing.expect(!latch);
    try std.testing.expect(strike(&vit, &latch, mathx.v3(9, 1, 0), 0.5, active) == null);
}

test "A SWUNG WEAPON REACHES WHAT IT CROSSED, and nothing it went over" {
    const hero = v3(0, 0, 2.0);
    const level = [2]rl.Vector3{ v3(0, 1.1, 0.4), v3(0, 1.1, 2.1) };
    try std.testing.expect(weaponReaches(level, level, hero, 0.6));
    const over = [2]rl.Vector3{ v3(0, 2.9, 0.4), v3(0, 2.9, 2.1) };
    try std.testing.expect(!weaponReaches(over, over, hero, 0.6));
    const short = [2]rl.Vector3{ v3(0, 1.1, -0.6), v3(0, 1.1, 0.8) };
    try std.testing.expect(!weaponReaches(short, short, hero, 0.6));
    const a = [2]rl.Vector3{ v3(-1.4, 1.1, 2.0), v3(-0.2, 1.1, 2.0) };
    const b = [2]rl.Vector3{ v3(0.2, 1.1, 2.0), v3(1.4, 1.1, 2.0) };
    try std.testing.expect(!weaponReaches(a, a, hero, 0.15));
    try std.testing.expect(!weaponReaches(b, b, hero, 0.15));
    try std.testing.expect(weaponReaches(a, b, hero, 0.15));
}

test "THE SWING RIBBON ONLY RECORDS A BLADE THAT MOVED, and it expires" {
    var t = Trail(4){};
    const base = v3(0, 1.1, 0.2);
    t.push(base, v3(0, 1.1, 1.4), v3(0, 1.1, 1.4 + TRAIL_SWEEP_MIN * 0.5), 0.3);
    try std.testing.expect(t.s[t.head].age >= mathx.LONG_AGO);
    t.push(base, v3(0, 1.1, 1.4), v3(0.9, 1.1, 1.4), 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.s[t.head].age, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2 + 0.3 * 1.2), t.s[t.head].a.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.4), t.s[t.head].b.z, 1e-6);
    t.age(0.4);
    try std.testing.expect(t.s[t.head].age > 0.39);
    t.reset();
    for (t.s) |s| try std.testing.expect(s.age >= mathx.LONG_AGO);
}

test "A SWING STARTS SLOW ENOUGH TO BE SEEN, then whips" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), swingCurve(0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), swingCurve(1), 1e-5);
    // The first quarter of the window moves the limb a TWELFTH of its arc. Front-loaded it moved 58% of it,
    // which is why a parry could only ever be timed off the sound and the clock.
    try std.testing.expect(swingCurve(0.25) < 0.10);
    try std.testing.expect(1.0 - swingCurve(0.75) > 2.0 * swingCurve(0.25));
    var prev: f32 = -1;
    var u: f32 = 0;
    while (u <= 1.0001) : (u += 1.0 / 64.0) {
        const now = swingCurve(u);
        try std.testing.expect(now >= prev);
        prev = now;
    }
    try std.testing.expect(swingCurve(0.5) < 0.5);
}

// ── WHERE THE LENS IS, FOR THE POOLS THAT CAN ASK ───────────────────────────────────────────────────────
//
// **A MOTE IS A CPU-TRANSFORMED SPHERE, AND THAT IS THE WHOLE REASON THIS EXISTS.** `drawParticles` puts every
// live mote through `rl.drawSphereEx`, which generates its vertices on the CPU with trig per vertex — the
// necromancer's sigil writes the measurement down beside itself: 157 of them at 4x6 is ~7.5k transformed
// triangles a frame. A boss in phase two now stands in a LANE of chaos (`knight.GAS_CAP` went from three
// clouds to twelve for the charge trail), and twelve pools of `GAS_PARTS` is an order of magnitude past that.
// Most of that lane is behind you or across the arena while you fight the thing that laid it.
//
// **IT IS NOT THE FRUSTUM AND MUST NEVER BECOME ONE.** `env.View` is the frustum, there is exactly one of them,
// and a second culler is the bug AGENTS.md names outright (a culler bug looks like an empty world). This is the
// coarse question a pool can answer about ITSELF: a reach, and a HEMISPHERE behind the lens. Nothing inside any
// field of view this game uses can fail either test, which is what makes it safe to be approximate.

var lensAt: rl.Vector3 = mathx.zero3;
var lensFwd: rl.Vector3 = v3(0, 0, 1);

/// Set ONCE a frame, before anything draws its motes (`game.drawScene`).
pub fn setLens(at: rl.Vector3, fwd: rl.Vector3) void {
    lensAt = at;
    lensFwd = fwd;
}

/// How far out a pool of motes is still worth the vertices. Past this a mote of any size in the game is under a
/// pixel and the haze has most of it (`gfx.HAZE_DENSITY` at 60 m is over half, and more in a storm).
pub const MOTE_REACH: f32 = 60.0;
/// …and how far off the view axis a pool has to be before it is dropped, as a cosine. -0.45 is 117 degrees off
/// the lens: past the corner of any frustum this game can produce, with room to spare.
const MOTE_BEHIND: f32 = -0.45;

/// **IS THIS WHOLE CLOUD OF MOTES WORTH DRAWING** — `at` its centre, `r` how far its motes reach from it.
pub fn motesVisible(at: rl.Vector3, r: f32) bool {
    const d = mathx.subV(at, lensAt);
    const dist2 = d.x * d.x + d.y * d.y + d.z * d.z;
    const reach = MOTE_REACH + r;
    if (dist2 > reach * reach) return false;
    // THE LENS IS IN IT, or close enough that its near edge is behind the camera and its far edge is not: the
    // angle test is meaningless there, so it draws. This is the branch that keeps the gate honest.
    if (dist2 <= r * r * 2.25) return true;
    const dist = @sqrt(@max(dist2, 1e-6));
    return (d.x * lensFwd.x + d.y * lensFwd.y + d.z * lensFwd.z) / dist > MOTE_BEHIND;
}

test "THE MOTE GATE NEVER DROPS SOMETHING YOU COULD SEE" {
    setLens(mathx.zero3, v3(0, 0, 1));
    // Dead ahead, at every range inside the reach.
    var d: f32 = 1.0;
    while (d < MOTE_REACH) : (d += 1.0) try std.testing.expect(motesVisible(v3(0, 0, d), 1.5));
    // …and off to the side as far as any frustum corner reaches — 60 degrees off axis is well past the widest
    // half-angle this game renders at, and it still draws.
    var deg: f32 = 0;
    while (deg <= 90.0) : (deg += 5.0) {
        const a = mathx.radians(deg);
        try std.testing.expect(motesVisible(v3(mathx.sinf(a) * 20.0, 0, mathx.cosf(a) * 20.0), 1.5));
    }
    // DIRECTLY BEHIND is the case it exists for…
    try std.testing.expect(!motesVisible(v3(0, 0, -20.0), 1.5));
    // …and so is the far side of the world.
    try std.testing.expect(!motesVisible(v3(0, 0, MOTE_REACH + 10.0), 1.5));
    // **AND A POOL THE LENS IS STANDING INSIDE ALWAYS DRAWS**, whichever way it happens to be pointed: a cloud
    // you are in fills the frame, and dropping that one is the one failure nobody could miss.
    try std.testing.expect(motesVisible(v3(0, 0, -1.0), 6.0));
    try std.testing.expect(motesVisible(mathx.zero3, 6.0));
}

test "EVERY CREATURE IS CLASSIFIED, and the water is only home to the two it belongs to" {
    // The hero's own waterline, read where it is written rather than copied: this file sits below `env` in
    // the import graph, so it borrows it the way `env`'s own tests borrow a creature.
    const envWadePin = @import("../world/env.zig").WADE_MAX;
    var waterfaring: usize = 0;
    var still: usize = 0;
    for (std.enums.values(wf.FoeKind)) |k| {
        const t = traitsOf(k);
        // A stature of 1.8 m: the limit is a share of the body, so it can never be zero or the whole depth.
        const lim = wadeLimit(k, 1.8);
        switch (t.gait) {
            .walking => {
                try std.testing.expect(lim > 0.2 and lim < 1.8);
                try std.testing.expect(lim < envWadePin);
            },
            .waterfaring => {
                waterfaring += 1;
                try std.testing.expect(lim > 100.0);
            },
            .flying, .rooted => {
                still += 1;
                try std.testing.expect(lim > 100.0);
            },
        }
    }
    try std.testing.expectEqual(@as(usize, 2), waterfaring);
    try std.testing.expectEqual(Gait.waterfaring, traitsOf(.toad).gait);
    try std.testing.expectEqual(Gait.waterfaring, traitsOf(.fen_lurker).gait);
    try std.testing.expectEqual(Nature.demon, traitsOf(.fen_lurker).nature);
    try std.testing.expect(still >= 4);
    std.debug.print("\n  wade: a 1.8 m walker turns back at {d:.2} m, where the hero goes to {d:.2} m\n", .{ wadeLimit(.archer, 1.8), envWadePin });
}
