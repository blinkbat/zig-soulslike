const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const gfx = @import("gfx.zig");
const wf = @import("worldfmt.zig");

const v3 = mathx.v3;


pub const FLASH_DUR: f32 = 0.20; // seconds a struck foe pops on the shared gfx `hitFlash` uniform
pub const FLASH_GAIN: f32 = 0.85;
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

/// **NO ATTACK COMES OUT OF NOWHERE** (owner's law): seconds a creature's kit must be VISIBLY MOVING before it
/// can deal damage. Derived from what already reads — the ogre's swipe 0.46, the brood bite 0.40, the toad's
/// gape 0.42 — against the two that read as INSTANT, the berserker's chop at 0.14 and the broodling's at 0.20.
/// Each creature's file tests its own moves against this; the shapes differ too much for one place to check.
pub const TELL_MIN: f32 = 0.30;

/// A CORPSE IS NOT A COLLIDER (owner's call): `alive()` stays true through the whole death collapse and its
/// dissipation, so every collision site has to ask this instead.
pub fn corporeal(f: anytype) bool {
    return f.alive() and !f.dying();
}


/// HOW FAR PAST ITS OWN NOTICE RING a creature follows before turning for home — per-creature, because one flat 30 m was both 2.7x the toad's aggro and the spacing between camps in `worlds/`.
pub const LEASH_SLACK: f32 = 6.0;
/// …and it is home again only this close, which is the hysteresis: start far, stop near, so a foe hovering at the boundary cannot flap between chasing and returning every other frame.
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

    /// Per frame, BEFORE the state machine decides anything. `out` is how far it is from its post, `toHero`
    /// the REAL distance to the hero — a walk home is never blind to him.
    pub fn tick(self: *Leash, dt: f32, out: f32, toHero: f32, aggroR: f32) void {
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
            } else if (toHero <= aggroR) {
                self.reengage();
            }
            return;
        }
        if (self.engagedLeft > 0) return;
        // It gives up only when he is BOTH far from its post AND out of its ring: a foe with the hero in its
        // face has no business turning round, whoever happens not to have landed a blow this half-second.
        if (out > leashR(aggroR) and toHero > aggroR and self.sinceCombat >= LEASH_CALM) self.returning = true;
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

pub fn faceToward(pos: rl.Vector3, facing: *f32, target: rl.Vector3, rate: f32, dt: f32) void {
    const d = mathx.dirXZ(pos, target);
    if (mathx.lenXZ(d) < 1e-3) return;
    facing.* = mathx.approachAngle(facing.*, mathx.headingXZ(d), rate * dt);
}

pub fn flashFrac(flash: f32) f32 {
    return mathx.clampF(flash / FLASH_DUR, 0, 1);
}

/// A POINT ON A CREATURE'S OWN AXIS: `h` metres of ITS OWN SCALE above the ground under it, plus whatever
/// it is holding off that ground this frame (`lift` — a hop, a leap, a hover). Seven creatures wrote this
/// same expression out three times each, and EVERY WORLD POINT ON AN ACTOR IS MEASURED FROM `pos.y` is the
/// law it exists to keep: off the datum instead, a foe on a bank keeps its bar down in the field.
pub fn bodyPoint(pos: rl.Vector3, h: f32, scale: f32, lift: f32) rl.Vector3 {
    return v3(pos.x, pos.y + h * scale + lift, pos.z);
}

/// …AND A POINT ON THE POSED BODY ITSELF, which is a different thing entirely: `at` is in the BONE's own
/// frame, so the answer follows whatever that bone is doing this frame rather than sitting at a fixed
/// height off the feet. THE RETICLE RIDES THIS. Locked onto a head, the mark goes where the head goes — it
/// dips when the head dips, and it does not hang in the air a foot above a creature that has ducked.
///
/// Every bone matrix already carries the rig's scale, the facing and the creature's `pos`, so this needs
/// nothing else; and every creature's `spawn` poses before it returns, so there is no frame on which the
/// matrix it reads is undefined.
pub fn markOn(bone: rl.Matrix, at: rl.Vector3) rl.Vector3 {
    return rl.math.vector3Transform(at, bone);
}

/// HOW HARD A REACTION IS PLAYING, 0..1, and it is ONE CURVE for every creature in the game. As five
/// private copies the constants had already drifted four ways — 0.12/0.78, 0.13/0.72, 0.14/0.70,
/// 0.16/0.78 — which is four different creatures disagreeing about the shape of the same event for no
/// reason anybody wrote down. A light flinch is a single symmetric swell; a heavy one snaps to its peak,
/// HOLDS there (that hold is the punish window, and it has to be legible), and lets go slowly.
pub fn stunCurve(t: f32, heavy: bool) f32 {
    if (!heavy) return mathx.sinf(mathx.clampF(t / combat.FOE_LIGHT_STUN_DUR, 0, 1) * std.math.pi);
    return mathx.pulse(mathx.clampF(t / combat.FOE_HEAVY_STUN_DUR, 0, 1), 0, 0.14, 0.74, 1.0);
}

/// How far a blow knocks a creature off its feet, by whether the blow was a heavy. A PAIR and not two
/// loose numbers: the two are only ever chosen against each other.
pub const Push = struct { light: f32, heavy: f32 };

/// THE BLADE REACHED IT — the swept test, the anti-cheese rouse, and the one thing a shaft does that a
/// swing does not. Seven creatures opened `tryHit` with these same four lines; the differences between
/// them were all in what came AFTER, which is why the split is here and not further down.
///
/// Duck-typed on the conventional field names (`drawGroup` and `anyDied` above already are): a creature
/// satisfying the foe contract has every one of them by definition.
pub fn reached(self: anytype, blade: Blade) ?Strike {
    const s = strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return null;
    self.leash.provoke();
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
    const heavy = blade.hit.stance > 0;
    self.shove = mathx.scaleV(s.dir, if (heavy) push.heavy else push.light);
    return heavy;
}

/// ROOTED: THE FEET ARE HELD, AND NOTHING ELSE IS (owner's law) — the state machine runs, the kit swings, the
/// blow lands, and the body simply does not travel. Taken as a GATE at the end of a creature's own `update`
/// rather than a guard at each `stepXZ`: a creature grows movements — a dash, a leap, the shove off a blade,
/// the next one nobody has written — and a per-site list is a list to forget something from. Y is left alone,
/// since `game.groundActor` owns it and a held foe still stands on its own ground.
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
///     const grip = foe.grip(&self.root, &self.vit, dt, self.pos);
///     defer grip.hold(&self.pos);
///     if (grip.killed) self.enterDeath();
///
/// Six byte-identical copies of that body sat in the creature files, which is six places to forget that the
/// bite is billed as a DRIP (`combat.Vitals.drip`) and never as a blow.
/// A JUMP IS THE ONE THING THE GRIP REFUSES OUTRIGHT (owner's law). Everywhere else the roots take the FEET as
/// a post-step gate and the move plays out on the spot — the club still comes down, the flurry still swings,
/// the travel is simply given back. A jump skill is not that: it does not travel, it LEAVES THE EARTH, and a
/// creature held by the ankles cannot. So it is gated where the move is CHOSEN, which is the one place a
/// post-step gate cannot reach: by the time `Grip.hold` runs, the leap is already committed and the only thing
/// left to deny is its distance, which lands you a creature hopping on the spot inside a fist of roots.
///
/// Asked at a choose site, so the creature is on the ground by construction. One already IN THE AIR when the
/// grip closes keeps its arc and lands: you cannot root what is not standing on anything.
pub fn canLeap(root: *const combat.Root) bool {
    return !root.held();
}

pub fn grip(root: *combat.Root, vit: *combat.Vitals, dt: f32, at: rl.Vector3) Grip {
    const on = root.held();
    const killed = if (root.tick(dt)) |bite| vit.drip(bite) == .death else false;
    return .{ .was = at, .on = on, .killed = killed };
}

/// THE HERO'S SHIELD AS THE THING SWINGING AT HIM SEES IT — `Leash`'s pattern exactly, stamped every frame from
/// outside (`game.markParry`) rather than fetched, because the creature must never reach out for the hero and
/// because the ARC belongs to the shield, not to whatever is being caught on it. A creature reads this during
/// its OWN parry window and nowhere else.
pub const Parry = struct {
    /// The catch window is open THIS frame. Every other field is meaningless while it is false.
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,

    /// Would this move be batted aside? `reach` is the MOVE's own and not one number per creature: only the
    /// move knows where its head is, and a slam you rolled clear of during its second of windup is not
    /// something a shield six metres away can touch. THE BLOCK'S OWN ARC (`combat.GUARD_ARC`) — a shield is a
    /// DIRECTION, and a parry that covered the back would be a better block than the block.
    pub fn catches(self: *const Parry, at: rl.Vector3, reach: f32) bool {
        if (!self.live) return false;
        if (mathx.distXZ(self.at, at) > reach) return false;
        const to = mathx.dirXZ(self.at, at);
        if (mathx.lenXZ(to) < 1e-4) return true; // standing inside him: there is no bearing to be wrong about
        return @abs(mathx.degrees(mathx.wrapPi(mathx.headingXZ(to) - self.facing))) <= combat.GUARD_ARC;
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
};

pub fn emitParticle(pool: []Particle, head: *usize, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
    pool[head.*] = .{ .p = p, .v = vel, .life = life, .max = life, .r0 = r0, .r1 = r1, .col = col, .grav = grav };
    head.* = (head.* + 1) % pool.len;
}

pub fn tickParticles(pool: []Particle, dt: f32, floor: f32) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        q.life -= dt;
        q.p.x += q.v.x * dt;
        q.p.y += q.v.y * dt;
        q.p.z += q.v.z * dt;
        q.v.y -= q.grav * dt;
        if (q.p.y < floor) q.p.y = floor;
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
        // ON THE GROUND, which the map's own height field decides — a spawn table stores x/z only, so posting a foe on a sculpted rise and dropping it at y = 0 would bury it to the waist.
        out[n.*] = T.spawn(v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
        n.* += 1;
    }
}

/// …AND THE SAME RESET FOR A GROUP WHOSE MEMBERS ARE ROLES OF ONE CREATURE (the warband, the muster, the
/// brood): its own `roleOf` says which role a map kind is, and `T.spawnAs` takes it. Three byte-identical
/// copies of this body sat in kobold/warrior/brood — the same one-line-delegate rule `resetGroup` above
/// already gives the single-kind groups.
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
    for (foes) |*f| {
        if (!f.alive()) continue;
        if (scene) |sc| {
            const want = FLASH_GAIN * f.flashFrac();
            if (want != lit) {
                sc.setFlash(want);
                lit = want;
            }
        }
        f.draw(model);
    }
    // …and a group never leaves its flash on for whatever draws next.
    if (scene) |sc| {
        if (lit > 0) sc.setFlash(0);
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

pub fn runesDropped(foes: anytype, per: u32) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += per;
    }
    return n;
}

/// …and the same for a group whose members are ROLES OF ONE CREATURE, where the payout is the MEMBER'S
/// (`runeValue`) rather than one number for the kind. Three byte-identical copies of this body sat in
/// kobold/brood/warrior — the one-line-delegate rule `resetGroup`/`drawGroup` already give the rest.
pub fn runesEach(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += f.runeValue();
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
    /// A PROJECTILE, NOT A SWING: one of the player's own, presented as the segment it crossed this frame so it goes through the same `strike` and gets each creature's own reactions.
    pierce: bool = false,
};

pub const Blow = struct {
    hit: combat.Hit,
    from: rl.Vector3, // the attacker's own `pos`, in world space
};

pub fn worseBlow(worst: *?Blow, h: combat.Hit, from: rl.Vector3) void {
    if (worst.* == null or h.raw() > worst.*.?.hit.raw()) worst.* = .{ .hit = h, .from = from };
}

pub fn groupBlow(foes: anytype, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?Blow {
    var worst: ?Blow = null;
    for (foes) |*f| {
        if (f.update(dt, hero, bounds, blade)) |h| worseBlow(&worst, h, f.pos);
    }
    return worst;
}

pub fn pierceGroup(foes: anytype, blade: Blade) bool {
    for (foes) |*f| {
        if (!f.alive() or f.dying()) continue;
        const before = f.hits;
        f.tryHit(blade);
        if (f.hits != before) return true;
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
    // A SHAFT'S OWN LENGTH *IS* ITS TRAVEL (`a`→`b` is this frame's segment), where a swing's sweep is the difference between two FRAMES of blade — which for a shaft subtracts to zero and used to fall through to "contact toward centre", i.e. square across the shaft.
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
    const gone = aggro + 1.0; // the hero, out of its ring
    l.noteCombat();
    l.tick(1.0 / 60.0, far, gone, aggro);
    try std.testing.expect(!l.goingHome());
    var t: f32 = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, gone, aggro);
    try std.testing.expect(l.goingHome());
    // THE HYSTERESIS: back inside the tether is NOT "home" — it keeps walking until it is actually there, so a foe hovering at the boundary cannot flap between chasing and returning every other frame.
    l.tick(1.0 / 60.0, leashR(aggro) - 1.0, gone, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, LEASH_HOME_R - 0.5, gone, aggro);
    try std.testing.expect(!l.goingHome());
    var near = Leash{};
    t = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) near.tick(1.0 / 60.0, 2.0, gone, aggro);
    try std.testing.expect(!near.goingHome());
}

test "IT NEVER TURNS ROUND WITH THE HERO IN ITS FACE, and walking back into its ring ends the walk home" {
    const aggro: f32 = 20.0;
    const far = leashR(aggro) + 8.0;
    // Toe to toe a long way from its post, and neither side has landed a blow in a while: it fights on.
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
    // …and the slack is POSITIVE whatever the creature, or a tether comes out shorter than the ring it was derived from and turns its owner for home mid-stare.
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
