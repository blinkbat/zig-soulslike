const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const gfx = @import("gfx.zig");
const wf = @import("worldfmt.zig");

const v3 = mathx.v3;


pub const FLASH_DUR: f32 = 0.20; // seconds a struck foe pops on the shared gfx `hitFlash` uniform
pub const FLASH_GAIN: f32 = 0.85;
/// How deep the rime coat goes at a full chill — under 1 so the body under it stays readable.
pub const FROST_GAIN: f32 = 0.55;
pub const HERO_R: f32 = 0.36;
pub const HERO_REACH: f32 = 0.55;
/// THE COLUMN A HERO STANDS IN, off his own feet. A swung weapon has to CROSS it, so a blow that went
/// over his skull or into the dirt at his boots is a miss. Written out rather than derived off `hero.H`
/// because foe.zig sits BELOW hero.zig in the import graph (hero → archer → foe) and it stays there.
pub const HERO_LOW: f32 = -0.10;
pub const HERO_HIGH: f32 = 1.71; // 0.95 of his 1.8 m stature
/// …and where a LOOK at him lands: the middle of the chest. Taken at his boots instead, every kerb he
/// happens to be standing behind hides him (see SIGHT).
pub const HERO_EYE: f32 = 1.25;
pub fn closestApproach(bodyR: f32) f32 {
    return bodyR + HERO_R;
}

pub const AIRBORNE_LIFT: f32 = 0.04;

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

/// …AND THE TEST ITSELF, off one clock: `left` is seconds until the blow lands. The `left < 0` half IS the
/// "shuts at the impact frame by construction" law.
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

/// A CORPSE IS NOT A COLLIDER (owner's call): `alive()` stays true through the whole death collapse and its
/// dissipation, so every collision site has to ask this instead.
pub fn corporeal(f: anytype) bool {
    return f.alive() and !f.dying();
}


/// HOW FAR PAST ITS OWN NOTICE RING a creature follows before turning for home. Per-creature: one flat 30 m
/// was both 2.7x the toad's aggro and the spacing between camps in `worlds/`.
pub const LEASH_SLACK: f32 = 6.0;
/// …and it is home again only this close — the hysteresis, so a foe at the boundary cannot flap.
pub const LEASH_HOME_R: f32 = 3.0;
/// …and only after this long with no blow given OR taken.
pub const LEASH_CALM: f32 = 4.5;
/// Walking back into a homing foe turns it round, and for this long it cannot try to leave again. MUST stay
/// above `LEASH_CALM` (else standing still sheds it) and below `PROVOKE_HOLD` (what three blows buy); it is
/// also the debounce that stops a hero at the ring's edge flipping a foe between chase and return.
pub const REENGAGE_HOLD: f32 = 8.0;

/// It loses its EYES, not its memory: it keeps on at the last known place this long. Above `LEASH_CALM`, or
/// breaking sight sheds a foe faster than walking away does and every fight becomes peekaboo.
pub const SIGHT_MEMORY: f32 = 6.0;

/// WHAT ONE BLOW IS WORTH as provocation…
pub const PROVOKE_PER_HIT: f32 = 1.0;
/// …how long one makes a foe ignore its own aggro range and come for you wherever you are.
pub const PROVOKE_ROUSE: f32 = 14.0;
/// …and how much BREAKS it outright.
pub const PROVOKE_BREAK: f32 = 2.5;
pub const PROVOKE_HOLD: f32 = 14.0;
pub const PROVOKE_DECAY: f32 = 0.35;

/// Derived off the creature's own aggro so a tether can never come out SHORTER than the range the same
/// creature notices you at — which would turn it for home mid-stare and yo-yo it in and out forever.
pub fn leashR(aggroR: f32) f32 {
    return aggroR + LEASH_SLACK;
}

pub const Leash = struct {
    sinceCombat: f32 = mathx.LONG_AGO,
    /// …and since it last had EYES on him. Stamped from outside (`game.markSight`): the prop grid a look is
    /// tested against belongs to `env`. STARTS SEEN, so a hand-built creature (a test, a shot portrait) with
    /// nothing but air in the way is not staring past him; `game.rehomeFoes` blinds the field on a fresh world.
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
            self.returning = false; // committed to the fight; the tether does not exist for now
            return;
        }
        if (self.returning) {
            // …and it only stops when it is actually HOME, not the moment it is back inside its tether —
            // unless the hero puts himself back inside its notice ring, which ends the walk there and then.
            if (out <= LEASH_HOME_R) {
                self.returning = false;
            } else if (heroOut <= aggroR) {
                self.reengage();
            }
            return;
        }
        if (self.engagedLeft > 0) return;
        // It gives up only when it is past its tether AND he has left its patch: a foe with the hero still
        // standing in the ground it guards has no business turning round, whoever happens not to have landed
        // a blow this half-second. The two tests SHARE the ring, so what it gives up on is what it re-takes.
        if (out > leashR(aggroR) and heroOut > aggroR and self.sinceCombat >= LEASH_CALM) self.returning = true;
    }

    pub fn noteCombat(self: *Leash) void {
        self.sinceCombat = 0;
    }

    /// It has eyes on him THIS FRAME.
    pub fn noteSeen(self: *Leash) void {
        self.sinceSeen = 0;
    }

    /// …and it has never had them — a foe posted by a world that has only just loaded.
    pub fn blindNow(self: *Leash) void {
        self.sinceSeen = mathx.LONG_AGO;
    }

    /// It has lost him: no sight for longer than its memory, and nothing has hit it lately. A blind foe
    /// reads the hero as infinitely far (`sensedDist`), which every creature already knows what to do
    /// about — it goes back to its post.
    pub fn blind(self: *const Leash) bool {
        return self.sinceSeen > SIGHT_MEMORY and !self.roused();
    }

    pub fn provoke(self: *Leash) void {
        self.noteCombat();
        self.rouseLeft = PROVOKE_ROUSE;
        self.provoked += PROVOKE_PER_HIT;
        self.reengage(); // ONE BLOW TURNS A HOMING FOE ROUND…
        if (self.provoked >= PROVOKE_BREAK) self.breakLeft = PROVOKE_HOLD; // …and keeping at it stops it leaving at all
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

/// …and HOW FAR IT READS THE HERO AS BEING, from where it is standing.
pub fn senseHero(l: *const Leash, at: rl.Vector3, hero: rl.Vector3, aggroR: f32) f32 {
    return sensedDist(l, mathx.distXZ(at, hero), aggroR);
}

pub fn faceToward(pos: rl.Vector3, facing: *f32, target: rl.Vector3, rate: f32, dt: f32) void {
    const d = mathx.dirXZ(pos, target);
    if (mathx.lenXZ(d) < 1e-3) return;
    facing.* = mathx.approachAngle(facing.*, mathx.headingXZ(d), rate * dt);
}

/// THE WAY ROUND WHAT IS IN THE WAY, and the whole of what a creature here knows about pathfinding.
///
/// **IT IS STAMPED FROM OUTSIDE** (`game.markWay`), the `Leash` arrangement and for its reason: a riser, a wall
/// and deep water are all questions about `env`, and a creature that reached for the world would be an eleventh
/// definition of what walkable means. What the creature owes in return is ONE method — `navWant`, the point it
/// is trying to walk at this frame, or null when it is not walking anywhere.
///
/// **IT IS STEERING AND NOT A ROUTE.** No graph, no path, nothing remembered: the stamp is a heading TESTED
/// for the next couple of metres. It answers one failure — a body pressed against a wall for the rest of the
/// fight because the only direction it considered was the hero's — and nothing more.
///
/// A creature reads it in exactly one place, whichever of the two its own movement is:
///   `aim`   — for one that walks where it is LOOKING (the ogre turns his whole body; he never strafes)
///   `along` — for one that steps on a committed vector and faces the hero anyway (the kobold, the shade)
pub const Nav = struct {
    /// The tested heading, unit XZ. NULL is the ordinary case and it means "the straight line is fine".
    dir: ?rl.Vector3 = null,
    /// WHICH WAY ROUND IT WENT LAST TIME, and this is the whole of why it does not dither: with both sides of
    /// an obstacle equally open, the side it already committed to wins, so a creature at a corner keeps going
    /// round the way it started instead of shivering in front of it. Re-set to whichever side actually worked
    /// every time a detour is taken, so it cannot commit to a wrong one for good.
    side: f32 = 1,

    /// THE POINT TO TURN TOWARD, given the one the creature actually wants.
    pub fn aim(self: *const Nav, from: rl.Vector3, want: rl.Vector3) rl.Vector3 {
        const d = self.dir orelse return want;
        return mathx.addV(from, d);
    }

    /// …and the same answer as a HEADING, for a creature that steps along a vector of its own rather than
    /// along its facing. `want` is already a unit direction.
    pub fn along(self: *const Nav, want: rl.Vector3) rl.Vector3 {
        return self.dir orelse want;
    }
};

test "AN UNSTAMPED WAY CHANGES NOTHING — steering is a bend on a refused heading, never a layer on top of one" {
    const at = mathx.ground(0, 0);
    const want = mathx.ground(0, 10);
    var n = Nav{};
    // Nothing stamped: both readings hand back exactly what the creature asked for, so a creature reading these
    // in its walk walks the same line it walked before any of this existed.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(want, n.aim(at, want)), 1e-6);
    const straight = mathx.dirXZ(at, want);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(straight, n.along(straight)), 1e-6);
    // …and stamped, BOTH readings turn — `aim` as a point one metre along the way and `along` as the way itself,
    // which is the one thing the two shapes have to agree on.
    n.dir = v3(1, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(mathx.ground(1, 0), n.aim(at, want)), 1e-6);
    try std.testing.expectApproxEqAbs(mathx.headingXZ(n.dir.?), mathx.headingXZ(mathx.dirXZ(at, n.aim(at, want))), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), n.along(straight).x, 1e-6);
}

/// How hard the bearing rate is smoothed — a creature answers a real orbit, never one frame of jitter.
pub const SENSE_SMOOTH: f32 = 6.0;
/// Seconds for "this spot is costing me" to fall by half. `Threat`'s own decay one purpose along, and much
/// shorter: threat is who to fight, this is whether to stay, and the second question goes stale faster.
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
    /// Radians a second the quarry's bearing is sweeping, smoothed. "It is walking round me."
    circleRate: f32 = 0,
    /// Damage taken since it last moved somewhere else, decaying.
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

    /// A BLOW LANDED ON IT — the raw damage, whoever threw it. `Threat.hurtBy`'s twin, and they are separate
    /// because they answer different questions off the same event: that one is WHO, this one is WHERE.
    pub fn hurt(self: *Sense, dmg: f32) void {
        self.hurtHere += mathx.maxF(dmg, 0);
    }

    /// Is somebody walking round it fast enough that turning is a losing game.
    pub fn circling(self: *const Sense, rate: f32) bool {
        return self.circleRate > rate;
    }

    /// **IS THIS SPOT COSTING IT** — the one question that earns a reposition. `share` is of its own MAX HP,
    /// so the same rule sizes itself on a toad and on a boss.
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
    // Still standing in it: the meter decays but it does not wipe.
    var k: i32 = 0;
    while (k < 30) : (k += 1) s.tick(dt, here, 0, 0.5, true);
    try std.testing.expect(s.hurtHere > 0);
    // …and one step out of it is a different spot, so the ledger closes with it.
    s.tick(dt, mathx.ground(0, 3.0), 0, 0.5, true);
    try std.testing.expect(!s.pressed(100, 0.3));
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.hurtHere, 1e-6);
}

test "IT DOES NOT READ ITS OWN TRAVEL AS AN ORBIT" {
    var s = Sense{};
    const dt = 1.0 / 60.0;
    const at = mathx.ground(0, 0);
    // A bearing swinging hard while the creature is the thing moving: `settled` false, so nothing accrues.
    var k: i32 = 0;
    var b: f32 = 0;
    while (k < 40) : (k += 1) {
        b += 0.05;
        s.tick(dt, at, b, 0.5, false);
    }
    try std.testing.expect(!s.circling(0.45));
    // …and the same sweep with its feet on the ground is read for what it is.
    k = 0;
    while (k < 60) : (k += 1) {
        b += 0.05;
        s.tick(dt, at, b, 0.5, true);
    }
    try std.testing.expect(s.circling(0.45));
}

pub fn flashFrac(flash: f32) f32 {
    return mathx.clampF(flash / FLASH_DUR, 0, 1);
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

/// HOW FAR THROUGH ITS ARC A SWING IS, 0..1 of the strike window — ONE CURVE for every creature, and it
/// exists because you must be able to parry off what you SEE (owner: "should be all 3" — visuals, sound and
/// timing, not the last two alone).
///
/// A FRONT-LOADED ARC (`1 - (1-u)³`) put 58% of the travel in the first quarter, so the limb was there
/// before the eye registered it; a SYMMETRIC one glides. This holds near the cock, then whips — 8% of the
/// arc in the first quarter, and the last quarter carries two and a half times the first.
pub fn swingCurve(u: f32) f32 {
    return std.math.pow(f32, mathx.smoothstep(0, 1, u), 1.35);
}

/// HOW HARD A REACTION IS PLAYING, 0..1, and it is ONE CURVE for every creature in the game. A light flinch
/// is a single symmetric swell; a heavy one snaps to its peak, HOLDS there — that hold is the punish window
/// and it has to be legible — and lets go slowly.
pub fn stunCurve(t: f32, heavy: bool) f32 {
    const u = mathx.clampF(t / combat.foeStunDur(heavy), 0, 1);
    if (!heavy) return mathx.sinf(u * std.math.pi);
    return mathx.pulse(u, 0, 0.14, 0.74, 1.0);
}

/// How far a blow knocks a creature off its feet, by whether the blow was a heavy. A PAIR and not two
/// loose numbers: the two are only ever chosen against each other.
pub const Push = struct { light: f32, heavy: f32 };

/// A MOVE'S CLOCK, for anything aiming at a beat inside it (`shots.zig` alone). NAMED rather than an
/// anonymous struct per creature, whose return types could not be held in one variable.
pub const Clock = struct { wind: f32, strike: f32, recover: f32 };

/// …off the creature's OWN attack row, so a retuned window still photographs the beat it is named after.
/// The WARRIOR keeps its own `Clock`: its rows carry a fourth knot (`chainWind`), a different shape.
pub fn moveClock(row: anytype) Clock {
    return .{ .wind = row.windDur, .strike = row.strikeDur, .recover = row.recoverDur };
}

/// THE BLADE REACHED IT — the swept test, the anti-cheese rouse, and the one thing a shaft does that a
/// swing does not. Duck-typed on the conventional field names.
pub fn reached(self: anytype, blade: Blade) ?Strike {
    const s = strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return null;
    self.leash.provoke();
    // **AND WHOEVER SWUNG IT JUST BOUGHT ITS ATTENTION.** The ONE place damage-threat is written, for the
    // reason `stunCurve` and `PARRY_LEAD` live here: the hero's blade and a spirit's jaws come through this
    // same door, so "who has been hurting me" cannot end up as two rules that disagree. The blade says who it
    // belongs to (`Blade.by`) — nothing here has to know what a wolf is.
    self.threat.hurtBy(blade.by, blade.hit.raw());
    // ONLY A `pierce` SNAPS THE FACING BACK DOWN ITS OWN LINE — being shot from somewhere it was not
    // looking is exactly when a creature must turn round, and a swing already came from in front of it.
    if (blade.pierce) self.facing = mathx.headingXZ(mathx.scaleV(s.dir, -1));
    return s;
}

/// …AND WHAT IT COSTS a creature that did not catch the blow on anything. Returns whether the BLOW was a
/// heavy (it carried stance), which is what every creature sizes its own blood, chips and dust off — never
/// the REACTION, since a heavy blow a high-poise creature shrugs off still hit it that hard.
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
/// Y is left alone: `game.groundActor` owns it, and a held foe still stands on its own ground.
pub const Grip = struct {
    was: rl.Vector3,
    on: bool,
    /// Whether THIS frame's bite finished it. Reported rather than acted on, because only the creature knows
    /// how to die.
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
///
/// A JUMP IS THE ONE THING THE GRIP REFUSES OUTRIGHT (owner's law): a jump does not travel, it LEAVES THE
/// EARTH, so it is gated where the move is CHOSEN — by `Grip.hold` the leap is committed, and denying its
/// distance leaves a creature hopping inside a fist of roots. One already IN THE AIR keeps its arc.
pub fn canLeap(root: *const combat.Root) bool {
    return !root.held();
}

/// **AND THE COLD IS BILLED THROUGH THE SAME DOOR** (`combat.Chill`). The rime breath is tested from OUTSIDE
/// the creature — only `game.zig` can see the cone and the field at once — but a bite that KILLS has to
/// arrive here, because entering a death is the one thing nothing outside a creature knows how to do. So the
/// breath stamps what it owes on the body and the body collects it on its own next frame, which is `Leash`'s
/// arrangement and `justDied`'s in the other direction.
///
/// The two bites are ORed into ONE `killed`: whichever of them finished it, the creature dies once.
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
    /// The catch window is open THIS frame. Every other field is meaningless while it is false.
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,

    /// Would this move be batted aside? `reach` is the MOVE's own and not one number per creature: only the
    /// move knows where its head is. THE BLOCK'S OWN ARC (`combat.GUARD_ARC`) — a shield is a DIRECTION, and a
    /// parry that covered the back would be a better block than the block.
    pub fn catches(self: *const Parry, at: rl.Vector3, reach: f32) bool {
        if (!self.live) return false;
        if (mathx.distXZ(self.at, at) > reach) return false;
        const to = mathx.dirXZ(self.at, at);
        if (mathx.lenXZ(to) < 1e-4) return true; // standing inside him: there is no bearing to be wrong about
        return combat.withinGuardArc(mathx.headingXZ(to), self.facing);
    }
};

// Carry a landed blow's KNOCKBACK for one frame and bleed it off — a jolt off the blade, not a slide.
pub fn applyShove(pos: *rl.Vector3, shove: *rl.Vector3, decay: f32, bounds: f32, dt: f32) void {
    if (mathx.lenXZ(shove.*) <= 0.01) return;
    mathx.stepXZ(pos, shove.*, dt, bounds); // the shared bounded step — shove is a velocity, so dist = dt
    shove.* = mathx.scaleV(shove.*, mathx.maxF(0, 1.0 - decay * dt));
}


pub const DUST = mathx.rgba(150, 132, 96, 175);
pub const MOTE = mathx.rgba(252, 198, 92, 170);
/// …and the pale flash a moving EDGE leaves (`Trail`). The world's, like the two above: steel is steel
/// whoever is swinging it, and authored per creature it had already drifted into two near-identical greys.
pub const WAKE = mathx.rgba(224, 230, 244, 255);

pub fn fxStream(seed: f32, mul: f32, salt: u64) mathx.Rng {
    return mathx.Rng.init(@as(u64, @intFromFloat(@abs(seed) * mul)) +% salt);
}

pub const Particle = struct {
    p: rl.Vector3 = mathx.zero3,
    v: rl.Vector3 = mathx.zero3,
    life: f32 = 0, // seconds remaining (0 = dead slot)
    max: f32 = 1, // life at spawn (for the fade fraction)
    r0: f32 = 0.05, // radius at spawn
    r1: f32 = 0.05, // radius at death (r1>r0 = an expanding puff; r1<r0 = a shrinking spark)
    col: rl.Color = mathx.rgba(255, 255, 255, 255),
    grav: f32 = 0, // downward accel (world/s²); negative floats up
    /// THE GROUND THIS ONE CAME OFF, when it is not the pool owner's own — `souls.fxFloor`'s rule, one layer
    /// down and per particle, because one pool can hold two bursts off two different grounds. Null means the
    /// owner's floor, which is every creature's whole pool: a creature's FX all come off its own feet.
    floor: ?f32 = null,
};

pub fn emitParticle(pool: []Particle, head: *usize, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
    pool[head.*] = .{ .p = p, .v = vel, .life = life, .max = life, .r0 = r0, .r1 = r1, .col = col, .grav = grav };
    head.* = (head.* + 1) % pool.len;
}

/// EVERY SLOT A BURST JUST WROTE, floored on the ground THAT burst came off rather than the pool owner's.
/// For an emitter that fires clear of its owner: the hero's roots erupt under the FOE and his bolt bursts
/// wherever it landed, and on sculpted ground neither settles on the earth under his boots. Take `head`
/// before the emit loop and hand both ends over after it — the ring wraps, so the walk does too.
/// ONE BURST MUST BE SMALLER THAN THE POOL: at exactly `pool.len` the head lands back where it started
/// and the walk reads as empty. The hero's and the drop's pools assert their worst frame at comptime
/// (`hero.FX_N`, `souls.PARTS`); a creature's is argued for in prose at its own declaration.
pub fn floorBurst(pool: []Particle, from: usize, to: usize, floor: f32) void {
    var i = from;
    while (i != to) : (i = (i + 1) % pool.len) pool[i].floor = floor;
}

/// WHAT ONE BODY BRINGS TO ITS OWN DISSOLVE, and all it brings: how thick the cloud is, how far out and how
/// far up the body it comes off — both in the creature's own scale — and the colour of the flakes it SHEDS.
/// The gold motes are not here: gold is the world's, the same off everything that dies.
pub const Dissolve = struct {
    rate: f32 = 54.0,
    spread: f32 = 0.85,
    rise: f32 = 0.70,
    flake: rl.Color = DUST,
};
/// The mix and the grain, which are the effect and not the creature: `spread` already carries the size.
const DISS_MOTE_SHARE: f32 = 0.76;
const DISS_MOTE_R: f32 = 0.094;
const DISS_FLAKE_R: f32 = 0.129;

/// THE BODY COMING APART — the one copy, for every creature on the field. Gold motes rising out of it and
/// flakes of the body falling back, both thinning as the fade closes.
///
/// It reads FIELDS only (`fade`, `scale`, `pos`, `fxAccum`, `fxRng`, `parts`, `fxHead`), which is what lets it
/// live here: a creature's own `emitDissolve` is private, and as five copies the ARCHER's had gone missing.
pub fn dissolveMotes(self: anytype, dt: f32, d: Dissolve) void {
    const thinning = 1.0 - 0.6 * self.fade;
    self.fxAccum += d.rate * thinning * dt;
    while (self.fxAccum >= 1.0) {
        self.fxAccum -= 1.0;
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
///
/// Named for what it does to the BODY and not for the creature doing it: the necromancer keeps its own `vigil`
/// (`necro.Vigil`, what it is standing over), and one name for both had this probe matching the CASTER too —
/// which is a type error here and would have been a silent behaviour change if the field types had agreed.
///
/// **AND IT IS THE MECHANIC, NOT A COURTESY.** A skeleton is 2.05 s from the killing blow to its last mote,
/// which is not long enough to hold a raise with a readable tell inside — so the hold is what MAKES the
/// window the raise happens in, and a body lying there NOT going to gold is the first thing the player is
/// shown about this creature.
fn stayed(self: anytype) bool {
    if (comptime @hasField(std.meta.Child(@TypeOf(self)), "heldOpen")) return self.heldOpen;
    return false;
}

/// THE CORPSE GOING. Past `still` the fall is over and the body dissipates over `diss`: `fade` is that ramp,
/// the dissolve comes off it the whole way, and the creature leaves the field at the end of it. The two
/// DURATIONS stay per-creature — a giant topples slower than a toad — but the shape does not.
pub fn dissipate(self: anytype, dt: f32, still: f32, diss: f32, d: Dissolve) void {
    if (self.t < still) return;
    // The fall is OVER either way — what is held is the going, so the body has already come to rest and lies
    // there. Held from part-way through, `fade` simply stops where it is rather than snapping back.
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
///
/// **THE `justDied` EDGE IS CLEARED** (its own law: a ONE-FRAME flag). A corpse raised on the same frame it
/// died would otherwise still be carrying the flag, and `trigger.Runtime`'s `deaths` counter — billed off that
/// edge — would count a death for a body standing up.
///
/// **AND THE VIGIL IS RELEASED HERE.** The hold exists to keep the body available; the frame it is used, it is
/// not a corpse any more, and a body left flagged would be a live creature nothing could ever dissolve.
pub fn rekindle(self: anytype, frac: f32) void {
    self.vit.revive(frac);
    self.fade = 0;
    self.gone = false;
    self.hitLatch = false;
    self.flash = FLASH_DUR; // it POPS on the shared flash: something just happened to this body
    self.shove = mathx.zero3;
    self.justDied = false;
    self.heldOpen = false;
    self.t = 0;
}

/// `floor` is the pool owner's own ground; a particle that named its own (`floorBurst`) keeps that instead.
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

/// A ring of the last N segments the edge occupied, drawn as a triangle strip between consecutive samples.
/// The only thing that makes a stroke aimed down the camera read at all: a level thrust foreshortens to a dot.
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
            // The early-out is BEFORE the GL state: two cull toggles around a draw that emits no triangles is
            // the whole cost of an idle skeleton's trail, asked of every muster member every frame.
            if (self.s[self.head].age >= life) return; // newest is stale → all of them are
            rl.gl.rlDisableBackfaceCulling(); // the ribbon must read from both sides of the arc
            defer rl.gl.rlEnableBackfaceCulling();
            var i: usize = 0;
            while (i + 1 < N) : (i += 1) {
                const s0 = &self.s[(self.head + N - i) % N];
                const s1 = &self.s[(self.head + N - i - 1) % N];
                if (s0.age >= life or s1.age >= life) break; // the rest is older still
                const f = 1.0 - 0.5 * (s0.age + s1.age) / life;
                const strip = [4]rl.Vector3{ s0.a, s0.b, s1.a, s1.b };
                rl.drawTriangleStrip3D(&strip, mathx.withAlpha(col, mathx.u8f(peak * f * f)));
            }
        }
    };
}

/// LEFT ALONE ON PURPOSE: `drawSphereEx` at 6x8 is 112 triangles — 336 immediate-mode vertex pushes,
/// CPU-transformed — so a full muster would be a quarter-million unlit triangles. It never is: a slot is
/// dead unless something emitted into it. The one cheaper shape (a cached unit sphere) would come out LIT.
pub fn drawParticles(pool: []const Particle) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        const frac = mathx.clampF(q.life / q.max, 0, 1);
        const rad = mathx.lerpF(q.r1, q.r0, frac); // r0 at spawn (frac 1) → r1 at death (frac 0)
        const a = mathx.u8f(@as(f32, @floatFromInt(q.col.a)) * frac);
        rl.drawSphereEx(q.p, rad, 6, 8, mathx.withAlpha(q.col, a));
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

/// …AND THE SAME RESET FOR A GROUP WHOSE MEMBERS ARE ROLES OF ONE CREATURE (the warband, the muster, the
/// brood): its own `roleOf` says which role a map kind is, and `T.spawnAs` takes it.
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
        // ON THE GROUND, which the map's own height field decides — see `resetGroup`.
        out[n.*] = T.spawnAs(role, v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
        n.* += 1;
    }
}

pub fn drawGroup(foes: anytype, model: anytype, scene: ?*gfx.Scene) void {
    // `setFlash` is a driver upload every time it is asked, and a group of 24 paid 24 per pass, twice a frame,
    // for the same 0. Uploaded only on CHANGE; `lit` starts outside 0..1 so nothing is assumed about the
    // uniform's state before this group.
    var lit: f32 = -1;
    // …and the rime coat rides the same fold (`combat.Chill.frac`: "how heavily the body is drawn frosted").
    // `@hasField` because a chillable body opted in by carrying the field — `markWays`' rule.
    var iced: f32 = -1;
    for (foes) |*f| {
        if (!f.alive()) continue;
        if (scene) |sc| {
            const want = FLASH_GAIN * f.flashFrac();
            if (want != lit) {
                sc.setFlash(want);
                lit = want;
            }
            if (@hasField(@TypeOf(f.*), "chill")) {
                const cold = FROST_GAIN * f.chill.frac();
                if (cold != iced) {
                    sc.setFrost(cold);
                    iced = cold;
                }
            }
        }
        f.draw(model);
    }
    // …and a group never leaves its flash on for whatever draws next.
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

/// …and the same for a group whose members are ROLES OF ONE CREATURE, where the payout is the MEMBER'S
/// (`soulValue`) rather than one number for the kind.
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

/// The segment a kit swept between frames (`was` → `now`, grip-end → far-end) against the hero's column, `r`
/// being the weapon's fatness plus the creature's slack. SAMPLED along the weapon AND across the sweep, not
/// solved: a whipped head covers half a metre in a frame and a two-endpoint test passes clean through a body.
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
    hit: combat.Hit = .{}, // HP/poise/stance the swing deals (light vs heavy, set by game.zig)
    /// A PROJECTILE, NOT A SWING: presented as the segment it crossed this frame so it goes through the
    /// same `strike` and gets each creature's own reactions.
    pierce: bool = false,
    /// WHOSE BLADE THIS IS. Defaults to the hero, so every existing site — his sword, his shafts, his bolts —
    /// says what it always said by saying nothing. A spirit's jaws set it (`wolf.blade`), and that is the
    /// whole of how a summon earns aggro.
    by: Victim = .hero,
};

// THREAT — WHO A CREATURE IS ACTUALLY FIGHTING
//
// **ONE TABLE PER CREATURE, and it is the creature's own field** (`Leash`'s law, and `Root`'s: cross-cutting
// state is EMBEDDED by the creature and STAMPED by the game).
//
// The model is Elden Ring's, which is a threat table with a decay on it:
//
//  - **HITTING SOMETHING TAKES ITS ATTENTION.** Damage is the loudest term by a distance, so a creature
//    chewing on the spirit turns on you the moment you commit to it. This is the rule ER players describe as
//    "bosses aggro whoever attacks them".
//  - **…BUT ONLY FOR A WHILE.** Threat from damage DECAYS (`THREAT_HALFLIFE`), which is the mechanic that
//    makes a summon work at all: stop hitting and your claim fades, and the creature drifts back to whatever
//    is still in its face. ER's own note is that a spirit which stops generating aggro loses it.
//  - **STANDING CLOSE IS ITSELF A CLAIM.** A live proximity term, so walking into something's reach takes its
//    eye whether or not you have touched it — and backing off hands it away again. This is the half that
//    makes the spirit useful when the player is trying to drink.
//  - **A SUMMON PULLS HARDER THAN ITS NUMBERS** (`SPIRIT_TAUNT`) — ER gives spirits a target-priority boost,
//    and the fragile ones get less of it. Ours is a wolf that is meant to be bitten, so it gets a real one.
//  - **AND IT DOES NOT DITHER.** The switch needs the challenger to beat the incumbent by a MARGIN, not to
//    tie with it. Without that a creature between two roughly equal claims re-picks every frame and spins on
//    the spot, which is the single thing that makes an aggro system read as broken rather than as alive.
//
// The whole of it is two floats and a latch, per creature, ticked once a frame.

/// WHO a creature has its eye on. Two today; a second spirit does not add a case, it adds a body behind
/// `spirit` — the pack is capped at one (`combat.SUMMON_MAX`) and this is the same decision one layer up.
pub const Victim = enum { hero, spirit };

/// Seconds for damage-threat to fall by half once you stop landing blows. Short enough that a player who
/// disengages hands the fight back to the wolf inside a couple of exchanges, long enough that one missed
/// swing does not.
pub const THREAT_HALFLIFE: f32 = 5.0;
/// How much threat a point of damage is worth. Only the RATIO between this and `THREAT_PROX` matters — this
/// one is 1.0 so that damage numbers read directly as threat and the other dial is the one to turn.
pub const THREAT_PER_DMG: f32 = 1.0;
/// …and what standing in its face is worth, at nose-to-nose. Sized against a couple of light hits: presence
/// alone should be able to hold a creature that nobody is hurting, and should lose to anybody who commits.
pub const THREAT_PROX: f32 = 26.0;
/// Past this the proximity term is nothing — beyond it you are not in the fight and only damage speaks.
pub const THREAT_PROX_R: f32 = 9.0;
/// The spirit's own pull. A wolf exists to be bitten instead of him, so it claims harder than its damage and
/// its position earn — ER's target-priority boost, and the reason a summon tanks at all.
pub const SPIRIT_TAUNT: f32 = 1.55;
/// **THE ANTI-DITHER.** A challenger must beat the incumbent by this much to take it. One flat multiplier, so
/// it behaves the same at every scale of threat.
pub const THREAT_SWITCH: f32 = 1.30;
/// …and it may not switch more often than this however the numbers move. Two creatures trading a target back
/// and forth twice a second is legible as a bug; a beat between changes of mind is legible as one.
pub const THREAT_DWELL: f32 = 0.65;

pub const Threat = struct {
    /// Damage-threat, per side, decaying. The proximity term is NOT stored — it is live, so a body that walks
    /// away stops claiming on the frame it does rather than draining for five seconds first.
    dmgHero: f32 = 0,
    dmgSpirit: f32 = 0,
    /// Who it is actually fighting. A LATCH: the scores propose and this disposes, which is the hysteresis.
    on: Victim = .hero,
    since: f32 = mathx.LONG_AGO,
    /// Where that victim is standing, stamped each frame by the game (`game.markThreat`). The creature reads
    /// this and never asks what a spirit is.
    at: rl.Vector3 = mathx.zero3,
    /// …and whether there is a spirit at all. With none, every rule below collapses to "the hero", which is
    /// exactly what the game was before any of this existed.
    hasSpirit: bool = false,

    /// WHAT IT SHOULD BE GOING FOR. Falls back to the hero whenever there is no spirit standing, so a
    /// creature whose `at` was never stamped behaves the way it always did.
    pub fn aim(self: *const Threat, heroPos: rl.Vector3) rl.Vector3 {
        if (!self.hasSpirit or self.on == .hero) return heroPos;
        return self.at;
    }

    /// A BLOW LANDED ON THIS CREATURE, and by whom. The one thing that writes damage-threat.
    pub fn hurtBy(self: *Threat, who: Victim, dmg: f32) void {
        const t = mathx.maxF(dmg, 0) * THREAT_PER_DMG;
        switch (who) {
            .hero => self.dmgHero += t,
            .spirit => self.dmgSpirit += t,
        }
    }

    /// The whole claim one side has right now: what it has done, plus where it is standing.
    pub fn score(dmg: f32, dist: f32, taunt: f32) f32 {
        const prox = mathx.clampF((THREAT_PROX_R - dist) / THREAT_PROX_R, 0, 1);
        return (dmg + THREAT_PROX * prox * prox) * taunt;
    }

    /// ONE FRAME. `distSpirit` is meaningless when `hasSpirit` is false and is not read.
    pub fn tick(self: *Threat, dt: f32, distHero: f32, distSpirit: f32, spirit: bool) void {
        self.hasSpirit = spirit;
        self.since += dt;
        // Exponential decay on both, so neither claim is permanent and neither snaps to nothing.
        const k = std.math.pow(f32, 0.5, dt / THREAT_HALFLIFE);
        self.dmgHero *= k;
        self.dmgSpirit *= k;
        if (!spirit) {
            self.on = .hero;
            self.dmgSpirit = 0;
            return;
        }
        const h = score(self.dmgHero, distHero, 1.0);
        const s = score(self.dmgSpirit, distSpirit, SPIRIT_TAUNT);
        if (self.since < THREAT_DWELL) return; // it has only just changed its mind — let it commit
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
    from: rl.Vector3, // the attacker's own `pos`, in world space
    /// WHO IT WAS SWUNG AT — a creature aiming at the spirit must not have its blow land on the hero
    /// standing somewhere else.
    on: Victim = .hero,
};

pub fn worseBlow(worst: *?Blow, h: combat.Hit, from: rl.Vector3, on: Victim) void {
    if (worst.* == null or h.raw() > worst.*.?.hit.raw()) worst.* = .{ .hit = h, .from = from, .on = on };
}

pub fn groupBlow(foes: anytype, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?Blow {
    var worst: ?Blow = null;
    for (foes) |*f| {
        // `aim` is the whole of the substitution: the creature is handed ITS OWN target in the argument it
        // has always called `hero`, so nothing inside it changes and nothing inside it knows.
        if (f.update(dt, f.threat.aim(hero), bounds, blade)) |h| worseBlow(&worst, h, f.pos, f.threat.on);
    }
    return worst;
}

test "THREAT: hitting something takes its attention, and letting up hands it back" {
    var t = Threat{ .hasSpirit = true, .on = .spirit };
    t.since = 100; // past the dwell, so it is free to change its mind
    // Both standing at the same range, nobody has hit it: the SPIRIT holds it, because that is what a taunt is.
    t.tick(1.0 / 60.0, 3.0, 3.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    // The hero commits. Damage is the loudest term, so it turns on him.
    t.hurtBy(.hero, 60);
    t.tick(1.0 / 60.0, 3.0, 3.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
    // …and then he backs off and stops swinging. His claim decays and the wolf in its face takes it back.
    var s: f32 = 0;
    while (s < 14.0) : (s += 1.0 / 60.0) t.tick(1.0 / 60.0, 14.0, 2.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
}

test "THREAT: standing close is its own claim, with nobody hitting anything" {
    var t = Threat{ .hasSpirit = true, .on = .spirit };
    t.since = 100;
    // The wolf is across the field and the hero is at its nose. Presence alone is enough to turn it.
    t.tick(1.0 / 60.0, 0.6, 12.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
}

test "THREAT DOES NOT DITHER — a near-tie holds whoever has it, whichever way round" {
    // A tie has to be built out of the SCORES, not out of the raw damage: the spirit's taunt multiplies its
    // whole claim, so equal damage is not a tie and testing it as one tests nothing. Solve for the spirit
    // damage that puts its score just INSIDE the switch margin, and the incumbent must keep it both ways.
    const D: f32 = 5.0;
    const inside = THREAT_SWITCH - 0.05;
    const h = Threat.score(100, D, 1.0);
    // (dS + prox) * TAUNT = h * inside  →  dS = h*inside/TAUNT - prox
    const prox = Threat.score(0, D, 1.0);
    const dS = h * inside / SPIRIT_TAUNT - prox;

    var t = Threat{ .hasSpirit = true, .on = .spirit, .dmgHero = 100, .dmgSpirit = dS };
    t.since = 100;
    t.tick(1.0 / 60.0, D, D, true);
    try std.testing.expectEqual(Victim.spirit, t.on); // the spirit is ahead but not by enough to be taken off

    var u = Threat{ .hasSpirit = true, .on = .hero, .dmgHero = 100, .dmgSpirit = dS };
    u.since = 100;
    u.tick(1.0 / 60.0, D, D, true);
    try std.testing.expectEqual(Victim.hero, u.on); // …and the same numbers leave the hero holding it too
}

test "THREAT: it will not change its mind twice in a heartbeat" {
    var t = Threat{ .hasSpirit = true, .on = .hero };
    t.since = 100;
    t.hurtBy(.spirit, 400); // an overwhelming claim…
    t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    // …and now an equally overwhelming one the other way, on the very next frame. The DWELL refuses it: a
    // creature spinning between two targets twice a second reads as a bug, not as indecision.
    t.hurtBy(.hero, 4000);
    t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    // Past the dwell it commits properly.
    var s: f32 = 0;
    while (s < THREAT_DWELL + 0.1) : (s += 1.0 / 60.0) t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
}

test "WITH NO SPIRIT ON THE FIELD it is the hero, exactly as it always was" {
    var t = Threat{};
    t.hurtBy(.spirit, 500); // …even with a claim from something that is no longer standing
    t.tick(1.0 / 60.0, 30.0, 0.0, false);
    try std.testing.expectEqual(Victim.hero, t.on);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.dmgSpirit, 1e-6);
    const hero = v3(1, 0, 2);
    try std.testing.expectEqual(hero.x, t.aim(hero).x); // and `aim` is a pass-through
}

/// HOW MANY BLOWS A CREATURE'S OWN BOARDS HAVE EATEN — zero for everything that carries none. `hits` counts
/// a body that TOOK a blow and a block deliberately is not one, so without this a shaft stopped on a shield
/// came back from `pierceGroup` as a MISS and flew on through the man who caught it.
fn blocksOf(f: anytype) u32 {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "blocksTaken")) return f.blocksTaken();
    return 0;
}

pub fn pierceGroup(foes: anytype, blade: Blade) bool {
    for (foes) |*f| {
        if (!f.alive() or f.dying()) continue;
        const before = f.hits;
        const caught = blocksOf(f);
        f.tryHit(blade);
        if (f.hits != before or blocksOf(f) != caught) return true;
    }
    return false;
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
            hitLatch.* = false; // window closed → the next swing may land again
            return null;
        }
        if (hitLatch.*) return null;
    }
    const reach = hurtR + blade.r;
    // Swept: test THIS frame's blade segment AND last frame's, so a fast arc can't skip the foe.
    const q1 = mathx.closestOnSegV(center, blade.a, blade.b);
    const hit1 = mathx.lenV(mathx.subV(center, q1)) <= reach;
    const q0 = mathx.closestOnSegV(center, blade.a0, blade.b0);
    if (!(hit1 or mathx.lenV(mathx.subV(center, q0)) <= reach)) return null;
    if (!blade.pierce) hitLatch.* = true;
    // The blow reads at the wound: blood/knockback fly along the blade's sweep at the contact.
    const contact = if (hit1) q1 else q0;
    // A SHAFT'S OWN LENGTH *IS* ITS TRAVEL, where a swing's sweep is the difference between two FRAMES of
    // blade — which for a shaft subtracts to zero and falls through to "contact toward centre".
    var sweep = if (blade.pierce)
        mathx.subV(blade.b, blade.a)
    else
        mathx.subV(mathx.lerpV(blade.a, blade.b, 0.7), mathx.lerpV(blade.a0, blade.b0, 0.7));
    sweep.y = 0;
    const dir = if (mathx.lenXZ(sweep) > 0.03) mathx.normV(sweep) else mathx.dirXZ(contact, center);
    return .{ .contact = contact, .dir = dir, .reaction = vit.hit(blade.hit) };
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
    d.down = true; // the collapse has begun, and `alive()` stays true for seconds yet
    try std.testing.expect(!corporeal(&d));
    d.gone = true;
    try std.testing.expect(!corporeal(&d));
}

test "THE SHIELD IS A DIRECTION AND EACH MOVE ITS OWN REACH" {
    const hero = v3(0, 0, 0);
    var p = Parry{ .live = false, .at = hero, .facing = 0 }; // facing +Z
    const ahead = v3(0, 0, 3);
    try std.testing.expect(!p.catches(ahead, 4.0)); // window shut: nothing is caught, however square it is
    p.live = true;
    try std.testing.expect(p.catches(ahead, 4.0));
    // Out past the MOVE's own reach — a windup you rolled away from is not a thing you can bat aside.
    try std.testing.expect(!p.catches(ahead, 2.0));
    // Behind the arc. GUARD_ARC either side of facing, so a foe at 90 deg is out and one just inside is in.
    const flank = v3(3, 0, 0);
    try std.testing.expect(!p.catches(flank, 4.0));
    const edge = mathx.radians(combat.GUARD_ARC - 2.0);
    try std.testing.expect(p.catches(v3(3.0 * mathx.sinf(edge), 0, 3.0 * mathx.cosf(edge)), 4.0));
    const past = mathx.radians(combat.GUARD_ARC + 2.0);
    try std.testing.expect(!p.catches(v3(3.0 * mathx.sinf(past), 0, 3.0 * mathx.cosf(past)), 4.0));
    // …and the arc turns with him rather than with the world.
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
    // THE HYSTERESIS: back inside the tether is NOT "home" — it walks until it is actually there.
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
    // The hero standing deep in the ground it guards, neither side having landed a blow: it fights on.
    // THE PATCH IS A PLACE, not a separation.
    var toe = Leash{};
    var t: f32 = 0;
    while (t < LEASH_CALM * 3.0) : (t += 1.0 / 60.0) toe.tick(1.0 / 60.0, far, 1.2, aggro);
    try std.testing.expect(!toe.goingHome());

    // THE BUG: it was blind for the whole walk back — the hero could stand in front of it and be ignored.
    var l = Leash{};
    t = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, aggro + 1.0, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, far, aggro - 0.5, aggro); // he steps back inside the ring, still nowhere near home
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
    const sniped = aggro * 2.0; // hit from well outside its own ring — the walk home is all it can see
    t = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    // ONE BLOW TURNS IT ROUND, and the hold is what stops one arrow a second flipping its mind every frame.
    c.provoke();
    c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(!c.goingHome());
    try std.testing.expect(c.roused());
    // A single hit's hold LAPSES and the tether takes over again…
    t = 0;
    while (t < REENGAGE_HOLD + LEASH_CALM + 0.2) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    // …but KEEPING AT IT (PROVOKE_BREAK worth of blows) makes it stop trying to leave for far longer.
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
    // Never seen — a foe posted by a world that has just loaded: he might as well not be there, however
    // close he is standing.
    l.blindNow();
    try std.testing.expect(l.blind());
    try std.testing.expect(sensedDist(&l, 1.0, aggro) > aggro);
    // Seen: it reads his REAL distance again.
    l.noteSeen();
    try std.testing.expect(!l.blind());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sensedDist(&l, 1.0, aggro), 1e-4);
    // …and it keeps coming for `SIGHT_MEMORY` after he breaks the line, which is what stops a pillar
    // ending a fight.
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
    // Start FAR, stop NEAR — the gap between them IS the debounce, and a zero gap is the flapping.
    try std.testing.expect(LEASH_HOME_R < LEASH_SLACK);
    // …and the slack is POSITIVE whatever the creature, or a tether comes out shorter than its own ring.
    try std.testing.expect(LEASH_SLACK > 0 and leashR(11.0) > 11.0);
    try std.testing.expect(PROVOKE_BREAK > PROVOKE_PER_HIT);
    try std.testing.expect(PROVOKE_ROUSE > LEASH_CALM * 2.0);
    try std.testing.expect(PROVOKE_HOLD > LEASH_CALM * 2.0);
    // Re-engaging has to cost MORE than simply waiting out the quiet window, and LESS than three blows buy.
    try std.testing.expect(REENGAGE_HOLD > LEASH_CALM and REENGAGE_HOLD < PROVOKE_HOLD);
    // …and BREAKING SIGHT must not shed a foe faster than walking away from one does.
    try std.testing.expect(SIGHT_MEMORY > LEASH_CALM);
}

test "A SHAFT'S blood and shove run ALONG its flight, and it never touches the swing latch" {
    // THE bug: a pierce passes one segment as BOTH `a`/`b` and `a0`/`b0`, so the swing's two-frame sweep subtracted to zero and `dir` came out square across the shaft — which is where blood and shove go.
    var vit = combat.Vitals.init(100, 999, 999); // huge poise/stance: no reaction to muddy this
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
    try std.testing.expect(s.dir.x > 0.95); // down the TRAVEL (+X)…
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
    var vit = combat.Vitals.init(100, 8, 100); // low poise → a hit flinches
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
    const level = [2]rl.Vector3{ v3(0, 1.1, 0.4), v3(0, 1.1, 2.1) }; // a blade laid through his chest
    try std.testing.expect(weaponReaches(level, level, hero, 0.6));
    const over = [2]rl.Vector3{ v3(0, 2.9, 0.4), v3(0, 2.9, 2.1) };
    try std.testing.expect(!weaponReaches(over, over, hero, 0.6));
    const short = [2]rl.Vector3{ v3(0, 1.1, -0.6), v3(0, 1.1, 0.8) };
    try std.testing.expect(!weaponReaches(short, short, hero, 0.6));
    // THE SWEEP IS THE POINT: a head that was one side of him last frame and the other side this frame
    // still hits, where a pair of endpoint tests would have it pass straight through.
    const a = [2]rl.Vector3{ v3(-1.4, 1.1, 2.0), v3(-0.2, 1.1, 2.0) };
    const b = [2]rl.Vector3{ v3(0.2, 1.1, 2.0), v3(1.4, 1.1, 2.0) };
    try std.testing.expect(!weaponReaches(a, a, hero, 0.15));
    try std.testing.expect(!weaponReaches(b, b, hero, 0.15));
    try std.testing.expect(weaponReaches(a, b, hero, 0.15));
}

test "THE SWING RIBBON ONLY RECORDS A BLADE THAT MOVED, and it expires" {
    var t = Trail(4){};
    const base = v3(0, 1.1, 0.2);
    // A blade sitting still lays nothing — samples of an unmoving edge stack into a quad that never fades.
    t.push(base, v3(0, 1.1, 1.4), v3(0, 1.1, 1.4 + TRAIL_SWEEP_MIN * 0.5), 0.3);
    try std.testing.expect(t.s[t.head].age >= mathx.LONG_AGO);
    t.push(base, v3(0, 1.1, 1.4), v3(0.9, 1.1, 1.4), 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.s[t.head].age, 1e-6);
    // The ribbon's inner edge sits `root` of the way down the blade, and its outer edge IS the point.
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
    // …and the LAST quarter carries more than twice what the first did: that asymmetry is the whip.
    try std.testing.expect(1.0 - swingCurve(0.75) > 2.0 * swingCurve(0.25));
    // …and it is monotone, so the arc never goes backwards mid-strike.
    var prev: f32 = -1;
    var u: f32 = 0;
    while (u <= 1.0001) : (u += 1.0 / 64.0) {
        const now = swingCurve(u);
        try std.testing.expect(now >= prev);
        prev = now;
    }
    // …and it is BEHIND a symmetric smoothstep the whole way, which is what makes the start the slow part.
    try std.testing.expect(swingCurve(0.5) < 0.5);
}
