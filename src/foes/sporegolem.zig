const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const art = @import("../props/propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const lerpF = mathx.lerpF;

// **THE SPORELING'S BRUTISH COUSIN, ANSWERED WITH FIRE AND NOT WITH A SWORD** (owner's brief). `ARMOUR` is the
// point of it: fire and lightning skip it entirely, cold and chaos do nothing.
//
// **BUT STEEL HAS TO REGISTER** (owner: seems impossible to hit with melee, should do a little dmg, just highly
// reduced). At 220 a light landed 3.0 of a 210 bar — 71 swings, and 21 heavies against the OGRE's 11. At 80 a light lands 5.8 and a heavy 17.0.

pub const H: f32 = 3.15;
pub const SCALE: f32 = 1.0;

pub const AGGRO_R: f32 = 15.0;
const TURN_RATE: f32 = 1.5;
/// **VERY SLOW** (owner). Two-fifths of a walk — everything else is priced against a player free to leave.
const WALK_SPEED: f32 = 1.05;

const BODY_R: f32 = 0.86;
const HURT_R: f32 = 1.30;
const CENTER_F: f32 = 0.52;
const TOP_F: f32 = 0.98;

/// `combat.armourTaken` turns aside `A/(A + 5*dmg)` — at 220 a 27-damage heavy lost 62% and a 13-damage light 77%. Armour is PHYSICAL ONLY.
const ARMOUR: f32 = 80.0;
const HP_MAX: f32 = 210.0;
const POISE_MAX: f32 = 46.0;
const STANCE_MAX: f32 = 70.0;
const RESISTS = combat.resists(.{ .fire = -85, .cold = 55, .lightning = -40, .chaos = 70 });
pub const SOULS: u32 = 900;

const DEATH_DUR: f32 = 1.7;
const DISS_DUR: f32 = 1.2;
const SHOVE_DECAY: f32 = 4.0;
pub const SHOVE = foe.Push{ .light = 0.55, .heavy = 1.35 };

const CAP_COL = rgba(58, 34, 42, 255);
const CAP_DK = rgba(34, 20, 26, 255);
const GILL = rgba(150, 132, 128, 255);
const FLESH = rgba(52, 42, 40, 255);
const FLESH_DK = rgba(31, 25, 25, 255);
const MOTE = rgba(206, 112, 158, 105);
const CORE = rgba(236, 172, 200, 70);
const DISSOLVE = foe.Dissolve{ .rate = 54.0, .spread = 1.25, .rise = 0.70, .flake = MOTE };


/// **A LONG TELL FOR AN ENORMOUS BLOW** — nearly a second of the cap going up. Hits harder than anything in the game that is not a boss.
pub const SMASH_WIND: f32 = 0.92;
const SMASH_FALL: f32 = 0.16;
const SMASH_RECOVER: f32 = 0.86;
const SMASH_CD: f32 = 2.6;
pub const SMASH_R: f32 = 2.35;
pub const SMASH_HIT = combat.Hit{ .dmg = 58, .poise = 40, .stance = 22 };

/// **TOLD IN HALF THE TIME** (owner: "quicker tell") — this answers backing off the smash, so at the smash's own wind-up it would be a second smash you could also walk out of.
pub const SLAM_WIND: f32 = 0.44;
const SLAM_AIR: f32 = 0.46;
const SLAM_RECOVER: f32 = 1.05;
const SLAM_CD: f32 = 4.4;
/// Metres it covers, and how high the body rides at the top of the arc.
pub const SLAM_REACH: f32 = 5.6;
const SLAM_UP: f32 = 1.30;
pub const SLAM_R: f32 = 2.05;
pub const SLAM_HIT = combat.Hit{ .dmg = 48, .poise = 44, .stance = 26, .launch = combat.SLAM_LAUNCH };

// **AND THE ANSWER TO WALKING AWAY.** Past the slam's 7.2 m this creature had nothing: at 1.05 m/s against a
// hero who runs at 3.4 the whole band out to its aggro ring was free. A SAC OF SPORES, LOBBED — it does not
// make the golem faster, it makes standing still cost something. What lands is the SPORELING'S OWN CLOUD
// (`shroom.Cloud`, one pool and one poison meter), so this is area denial and never a second way to be flattened.
/// **THE LONGEST TELL IN THE GAME** — a second and a half, because what it answers is a player with all the room in the world to read it.
pub const SAC_WIND: f32 = 1.55;
const SAC_THROW: f32 = 0.24;
const SAC_RECOVER: f32 = 1.30;
const SAC_CD: f32 = 8.0;
/// Off the far end of the slam's band, so the three moves still answer three distances and never one.
const SAC_MIN: f32 = 7.60;
const SAC_MAX: f32 = 13.0;
pub const SAC_SPEED: f32 = 12.0;
/// Small: the cloud is the weapon and a sac to the chest is the tax on standing where it aimed.
pub const SAC_HIT = combat.Hit{ .dmg = 15, .poise = 14 };
/// Share of stature — over the brim, so the arc starts above its own head.
const SAC_FROM_Y: f32 = 0.86;

/// **THREE BANDS, AND THEY DO NOT OVERLAP**: inside `SMASH_R` it smashes, the slam owns the band beyond, and the sac everything past the slam's reach. Two moves answering one distance is one move with a coin flip.
const SMASH_AT: f32 = 3.10;
const SLAM_MIN: f32 = 3.40;
const SLAM_MAX: f32 = 7.20;

comptime {
    std.debug.assert(SMASH_WIND >= foe.TELL_MIN);
    std.debug.assert(SLAM_WIND >= foe.TELL_MIN);
    std.debug.assert(SLAM_WIND < SMASH_WIND * 0.6);
    std.debug.assert(SMASH_AT < SLAM_MIN);
    std.debug.assert(SLAM_MIN < SLAM_MAX);
    std.debug.assert(SLAM_REACH + SLAM_R > SLAM_MIN);
    std.debug.assert(SLAM_REACH < SLAM_MAX);
    std.debug.assert(SMASH_HIT.dmg > SLAM_HIT.dmg);
    std.debug.assert(SLAM_HIT.poise > SMASH_HIT.poise);
    std.debug.assert(SLAM_MAX < SAC_MIN);
    std.debug.assert(SAC_MIN < SAC_MAX and SAC_MAX <= AGGRO_R);
    std.debug.assert(SAC_WIND > SMASH_WIND);
    std.debug.assert(SAC_HIT.dmg < SLAM_HIT.dmg and SAC_HIT.stance == 0);
}

// Six bones, the sporeling's layout with an arm each side. NO NECK — the cap sits ON the body, which is what makes the smash read as the whole creature falling forward.

/// Sized by the RING LAW: the disc tell's residency (`RING_RATE` at its longest life) can share a frame with the body dying into its own dissolve and the shared wound on top.
const PARTS = 60;
/// The disc tell's motes per second — spore-light walked round the blow's own rim.
const RING_RATE: f32 = 30.0;
comptime {
    std.debug.assert(@as(f32, PARTS) >= RING_RATE * 0.55 + DISSOLVE.rate * 0.7 + @as(f32, foe.WOUND_PARTS));
}

const N = 6;
const BODY = 0;
const CAP = 1;
const ARML = 2;
const ARMR = 3;
const LEGL = 4;
const LEGR = 5;

const CAP_Y: f32 = 0.70 * H;
/// **WIDER THAN THE BODY, NOT WIDER THAN THE CREATURE IS TALL** — 0.62 of H on a 3.15 m creature is a 3.9 m brim, which photographed as a pink pancake with legs under it (`shroommage.RIM`'s ceiling).
const CAP_R: f32 = 0.33 * H;
const ARM_Y: f32 = 0.52 * H;
/// Hugging the trunk, not hung off it — at 0.27 the two slabs read as separate blocks standing beside the body.
const ARM_X: f32 = 0.205 * H;
const LEG_X: f32 = 0.13 * H;

fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[BODY] = v3(0, 0.30 * H, 0);
    r[CAP] = v3(0, CAP_Y, 0);
    r[ARML] = v3(ARM_X, ARM_Y, 0.02 * H);
    r[ARMR] = v3(-ARM_X, ARM_Y, 0.02 * H);
    r[LEGL] = v3(LEG_X, 0.20 * H, 0);
    r[LEGR] = v3(-LEG_X, 0.20 * H, 0);
    return r;
}

const State = enum { idle, walk, smash_wind, smash_fall, smash_rec, slam_wind, slam_air, slam_rec, sac_wind, sac_throw, sac_rec, stunlight, stunheavy, dead };

pub const Golem = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    facing: f32 = 0,
    seed: f32 = 0,
    scale: f32 = SCALE,
    gone: bool = false,
    state: State = .idle,
    t: f32 = 0,
    phase: f32 = 0,
    moving: f32 = 0,
    speed: f32 = 0,
    fade: f32 = 0,
    flash: f32 = 0,
    hits: u32 = 0,
    hitLatch: bool = false,
    justDied: bool = false,
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    shove: rl.Vector3 = mathx.zero3,
    smashCd: f32 = 0,
    slamCd: f32 = 0,
    sacCd: f32 = 0,
    /// One-frame, like `burst`: where the sac left the cap, read by the loop the frame it appears.
    lobFrom: ?rl.Vector3 = null,
    lift: f32 = 0,
    launch: rl.Vector3 = mathx.zero3,
    /// Where the slam will land — committed with `launch`, and what the flight's disc tell is drawn at.
    landAt: rl.Vector3 = mathx.zero3,
    struck: bool = false,
    burst: ?rl.Vector3 = null,
    fxAccum: f32 = 0,
    fxHead: usize = 0,
    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = restPose(),
    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS).withArmour(ARMOUR),

    pub fn spawn(at: rl.Vector3, yaw: f32, scale: f32, seed: f32) Golem {
        var g = Golem{
            .pos = at,
            .home = at,
            .facing = mathx.radians(yaw),
            .seed = seed,
            .scale = scale * SCALE,
            .fxRng = foe.fxStream(seed, 51413.0, 0x60_1E),
            .vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS).withArmour(ARMOUR),
        };
        g.pose();
        return g;
    }

    pub fn kind(self: *const Golem) wf.FoeKind {
        _ = self;
        return .spore_golem;
    }
    pub fn hurtRadius(self: *const Golem) f32 {
        return HURT_R * self.scale;
    }
    pub fn alive(self: *const Golem) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Golem) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Golem) bool {
        return self.state == .stunlight or self.state == .stunheavy;
    }
    pub fn draw(self: *const Golem, model: *const Model) void {
        model.draw(self);
    }
    pub fn drawFx(self: *const Golem) void {
        foe.drawParticles(&self.parts);
    }

    /// The blow's own circle in spore-light — pink on grass, so it reads without the delver's tan-on-tan problem. Soft, additive, and rising a little: a warning, not debris.
    fn discTell(self: *Golem, dt: f32, at: rl.Vector3, r: f32) void {
        var owed = foe.emitDue(&self.fxAccum, dt, RING_RATE);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * r, self.pos.y + 0.04, at.z + mathx.sinf(a) * r),
                .v = v3(self.fxRng.signed() * 0.2, self.fxRng.range(0.3, 0.8), self.fxRng.signed() * 0.2),
                .life = self.fxRng.range(0.38, 0.55),
                .r0 = 0.055 * self.scale,
                .r1 = 0.13 * self.scale,
                .col = MOTE,
                .add = true,
            });
        }
    }
    pub fn flashFrac(self: *const Golem) f32 {
        return foe.flashFrac(self.flash);
    }
    /// **THE TRAVEL STATE IS `.walk`, WHICH IS THE ONE THE STAMP HAS TO BE FOR.** Asked while `.idle` the heading was solved for the frames it stands still and null on every frame it moves, so the stamp was never read.
    pub fn navWant(self: *const Golem, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .walk) return null;
        return if (self.leash.goingHome()) self.home else hero;
    }
    pub fn bodyR(self: *const Golem) f32 {
        return BODY_R * self.scale;
    }
    pub fn centerWorld(self: *const Golem) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.lift);
    }
    pub fn topWorld(self: *const Golem) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.lift);
    }
    pub fn lockPoint(self: *const Golem) rl.Vector3 {
        return foe.markOn(self.xf[CAP], v3(0, 0.04 * H, 0));
    }
    pub fn souls(self: *const Golem) u32 {
        _ = self;
        return SOULS;
    }
    /// **AIRBORNE ON THE SLAM, AND THAT MATTERS TO THE FLOOR** — a creature off the ground does not collide with terrain the way a walking one does, which is what lets the slam cross a lip it could not climb.
    pub fn airborne(self: *const Golem) bool {
        return self.state == .slam_air and self.lift > foe.AIRBORNE_LIFT;
    }

    /// **AND IT PUTS THE BODY BACK ON THE GROUND** (`frog.base`, `shroom.enterStun`): `.slam_air` is the only thing that writes `lift`, so a stagger or a death in mid-flight left the whole creature 1.3 m up for good.
    fn enter(self: *Golem, s: State) void {
        self.state = s;
        self.t = 0;
        self.struck = false;
        self.lift = 0;
    }

    /// **ONE DOOR OUT** (every other creature's `enterDeath`). The blade and a drip that kills reach `.dead`
    /// down different paths, and written out at both the drip's copy had no voice.
    fn enterDeath(self: *Golem) void {
        if (self.state == .dead) return;
        sfx.world(.shroom_die, self.pos);
        self.enter(.dead);
        self.justDied = true;
    }

    fn decide(self: *Golem, dist: f32) void {
        if (self.leash.goingHome()) return self.enter(.walk);
        if (dist <= SMASH_AT and self.smashCd <= 0) {
            self.smashCd = SMASH_CD;
            return self.enter(.smash_wind);
        }
        // **THE SLAM IS A LEAP, SO IT IS GATED WHERE THE MOVE IS CHOSEN** (`ravager`'s law, `foe.canLeap`) — the airborne half of `foe.grip` lets a body finish an arc it is already in, so a jump still ALLOWED to start is a jump straight out of the roots.
        if (dist >= SLAM_MIN and dist <= SLAM_MAX and self.slamCd <= 0 and foe.canLeap(&self.root)) {
            self.slamCd = SLAM_CD;
            return self.enter(.slam_wind);
        }
        // **AND PAST THE SLAM IT THROWS.** Its own band — a creature this slow needs a reason to be respected from across a field.
        if (dist >= SAC_MIN and dist <= SAC_MAX and self.sacCd <= 0) {
            self.sacCd = SAC_CD;
            return self.enter(.sac_wind);
        }
        if (dist <= AGGRO_R) return self.enter(.walk);
        self.enter(.idle);
    }

    /// Over the brim of its own cap, so the arc starts above its head.
    pub fn sacPoint(self: *const Golem) rl.Vector3 {
        return foe.bodyPoint(self.pos, SAC_FROM_Y * H, self.scale, self.lift);
    }

    pub fn update(self: *Golem, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        // A CLOUD TICKS ITS MOTES PAST THE BODY'S OWN END (the foe contract's rule): the flakes a dissolve throws are still in the air when the slab goes `gone`, and returning before this froze them there for the rest of the level.
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        // Taken before anything moves `pos`, held through a `defer`, and left to the `vit.dead` check below to resolve a drip that kills.
        const held = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) held.hold(&self.pos);
        self.vit.tick(dt);
        // **THE STUN METER GOES DOWN THIS BODY'S OWN DOOR.** Twenty creatures answer `grip.downed` with
        // `stagger(true)`; this one has no such method and syncs its state off `vit.stunned()` instead — which
        // only sleep ever set. A full lightning meter procced and did NOTHING, on the one creature lightning is
        // meant to answer (`RESISTS` carries -40 to it). The sync below enters `.stunheavy` off this.
        if (held.downed) self.vit.beginStun(.heavy);
        foe.fadeFlash(&self.flash, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        self.smashCd = mathx.maxF(0, self.smashCd - dt);
        self.slamCd = mathx.maxF(0, self.slamCd - dt);
        self.sacCd = mathx.maxF(0, self.sacCd - dt);
        self.t += dt;
        self.burst = null;
        self.lobFrom = null;
        // THE ONE-FRAME FLAG, CLEARED AT THE TOP. `Host.live` hands out the whole slab with no `gone` filter, so
        // left set this latched for the rest of the map — and `game.anyFoeDied` reads it, so the kill sound, shake and rumble fired EVERY FRAME after the first golem died.
        self.justDied = false;

        if (self.state == .dead) {
            foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            self.speed = 0;
            self.pose();
            return null;
        }
        if (self.vit.dead) {
            self.enterDeath();
            self.pose();
            return null;
        }

        // **THE DECISIONS READ THE SENSED DISTANCE, NEVER THE REAL ONE** (`foe.sensedDist`) — the raw gap ignored
        // the tether it is already ticking, so a golem that had lost sight of him kept walking and the anti-cheese
        // rouse `foe.reached` buys did nothing. The reach tests below stay on the REAL distance: a blow lands where the body is.
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        var blow: ?combat.Hit = null;
        var moved: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.face(hero, dt);
                // **ORDERS ARE WHAT IT DOES BEFORE IT HAS SEEN ANYBODY** (`foe.postStep`), refused inside the ring.
                const ps = foe.postStep(self, dt, bounds, WALK_SPEED, d, AGGRO_R);
                if (ps.yaw) |w| {
                    moved = ps.moved;
                    self.facing = mathx.approachAngle(self.facing, w, TURN_RATE * dt);
                }
                if (self.t >= 0.35) self.decide(d);
            },
            .walk => {
                // IT WALKS WHERE IT IS LOOKING and turns round what is in the way through the FACING — the ogre's
                // and the ravager's arrangement, because a mass this size does not strafe. Stepping at the target instead carried it sideways for the two seconds a 1.5 rad/s turn takes.
                const tgt = if (self.leash.goingHome()) self.home else hero;
                self.face(self.nav.aim(self.pos, tgt), dt);
                const step = WALK_SPEED * dt;
                mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
                moved = step;
                if (self.t >= 0.40) self.decide(d);
            },
            // **IT REARS AND HOLDS.** The cap goes all the way up over the first two thirds and the last third is dead still, which is the frame the player is actually reading.
            .smash_wind => {
                self.face(hero, dt);
                // **THE DISC IS DRAWN BEFORE IT IS BILLED** (the knight's slam law): the blow's own rim in spore-light for the whole wind, off the same centre and radius the blow uses.
                self.discTell(dt, self.reachPoint(SMASH_R * 0.62), SMASH_R * self.scale);
                if (self.t >= SMASH_WIND) self.enter(.smash_fall);
            },
            .smash_fall => {
                if (!self.struck and self.t >= SMASH_FALL * 0.5) {
                    self.struck = true;
                    const at = self.reachPoint(SMASH_R * 0.62);
                    self.burst = at;
                    // NOT PARRYABLE, AND THAT IS A DECISION (the delver-burst rule): the blow is a DISC of ground with no bearing to catch. The counter is your feet, both moves.
                    if (mathx.distXZ(at, hero) <= SMASH_R * self.scale + foe.HERO_R) {
                        blow = SMASH_HIT;
                    }
                }
                if (self.t >= SMASH_FALL) self.enter(.smash_rec);
            },
            .smash_rec => if (self.t >= SMASH_RECOVER) self.decide(d),
            // **IT GATHERS AND THROWS ITSELF.** The launch vector is fixed at the end of the wind-up, so the slam commits to a spot the way the bone knight's fall does — it cannot steer onto you in the air.
            .slam_wind => {
                self.face(hero, dt);
                if (self.t >= SLAM_WIND) {
                    const way = mathx.dirXZ(self.pos, hero);
                    const gap = mathx.minF(mathx.distXZ(self.pos, hero), SLAM_REACH);
                    self.launch = mathx.scaleV(way, gap);
                    self.landAt = mathx.addV(self.pos, self.launch);
                    self.enter(.slam_air);
                }
            },
            .slam_air => {
                const u = mathx.clampF(self.t / SLAM_AIR, 0, 1);
                const step = mathx.lenV(self.launch) / SLAM_AIR * dt;
                mathx.stepXZ(&self.pos, mathx.normV(self.launch), step, bounds);
                moved = step;
                // Drawn at the spot the launch COMMITTED to — the wind cannot show it (the aim is still tracking there), so the flight does, which is the half-second you dodge in.
                self.discTell(dt, self.landAt, SLAM_R * self.scale);
                self.lift = SLAM_UP * mathx.sinf(std.math.pi * u) * self.scale;
                if (u >= 1.0) {
                    self.lift = 0;
                    self.burst = self.pos;
                    if (mathx.distXZ(self.pos, hero) <= SLAM_R * self.scale + foe.HERO_R) {
                        blow = SLAM_HIT;
                    }
                    self.enter(.slam_rec);
                }
            },
            .slam_rec => if (self.t >= SLAM_RECOVER) self.decide(d),
            // **THE SAC SWELLS AND IT KEEPS FACING HIM.** The aim is taken at the THROW, so tracking through the wind is honest — what it cannot do is steer the sac once it is in the air.
            .sac_wind => {
                self.face(hero, dt);
                if (self.t >= SAC_WIND) self.enter(.sac_throw);
            },
            .sac_throw => {
                if (!self.struck) {
                    self.struck = true;
                    self.lobFrom = self.sacPoint();
                }
                if (self.t >= SAC_THROW) self.enter(.sac_rec);
            },
            .sac_rec => if (self.t >= SAC_RECOVER) self.decide(d),
            .stunlight, .stunheavy => if (!self.vit.stunned()) self.decide(d),
            .dead => {},
        }

        if (self.vit.stunned() and self.state != .stunlight and self.state != .stunheavy and self.state != .dead) {
            self.enter(if (self.vit.stunHeavy()) .stunheavy else .stunlight);
        }

        self.speed = if (dt > 0) moved / dt else 0;
        self.moving = mathx.approach(self.moving, if (moved > 0) 1 else 0, 4.0 * dt);
        self.phase += self.speed * 0.55 * dt + self.moving * 0.20 * dt;
        self.pose();
        self.tryHit(blade);
        return blow;
    }

    fn face(self: *Golem, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    fn reachPoint(self: *const Golem, out: f32) rl.Vector3 {
        const d = mathx.headingDir(self.facing);
        return v3(self.pos.x + d.x * out * self.scale, self.pos.y, self.pos.z + d.z * out * self.scale);
    }


    pub fn tryHit(self: *Golem, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, SHOVE);
        sfx.world(.shroom_hurt, self.pos);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enter(.stunheavy),
            .light => self.enter(.stunlight),
            .none => {},
        }
        _ = heavy;
    }

    pub fn pose(self: *Golem) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const dk = if (self.state == .dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;

        // **THE WHOLE CREATURE IS THE ANIMATION.** No neck and no wrists, so every read it has is the trunk: the rear is the body arching back, the smash is the body folding forward, and the slam is the same fold thrown off the ground.
        const rear = self.rearAmt();
        const fold = self.foldAmt();
        const lob = self.lobAmt();
        const bob = mathx.sinf(self.phase * std.math.tau) * 0.022 * H * self.moving;
        const trunk = -34.0 * rear + 66.0 * fold - 74.0 * dk + 30.0 * lob;

        var wx: [N]rl.Matrix = undefined;
        const rootY = self.rest[BODY].y + bob - 0.30 * H * dk;
        wx[BODY] = mul3(
            rx(trunk),
            tr(0, rootY, 0),
            mul(ry(facingDeg), tr(self.pos.x, self.pos.y + self.lift, self.pos.z)),
        );
        // The cap leads the fold and lags the rear, which is what stops the two reading as one rigid board.
        const swing = mathx.sinf(self.phase * std.math.tau) * 16.0 * self.moving;
        self.limb(&wx, CAP, rx(-12.0 * rear + 24.0 * fold + 16.0 * lob));
        // BOTH ARMS, TOGETHER: two arms doing the same thing is what separates the throw from the smash's asymmetric flail.
        self.limb(&wx, ARML, rx(swing - 28.0 * rear + 58.0 * fold + 74.0 * lob));
        self.limb(&wx, ARMR, rx(-swing - 28.0 * rear + 58.0 * fold + 74.0 * lob));
        self.limb(&wx, LEGL, rx(-swing * 0.7));
        self.limb(&wx, LEGR, rx(swing * 0.7));
        for (&wx) |*m| m.* = mul(mathx.scaleM(fs, fs, fs), m.*);
        self.xf = wx;
    }

    /// Hangs a bone off the trunk at its rest offset. Everything above the body follows the trunk.
    fn limb(self: *const Golem, wx: *[N]rl.Matrix, i: usize, local: rl.Matrix) void {
        const off = mathx.subV(self.rest[i], self.rest[BODY]);
        wx[i] = mul(mul(local, tr(off.x, off.y, off.z)), wx[BODY]);
    }

    /// 0..1 of the gather, on whichever move is gathering.
    fn rearAmt(self: *const Golem) f32 {
        return switch (self.state) {
            .smash_wind => mathx.smoothstep(0, SMASH_WIND * 0.66, self.t),
            .slam_wind => mathx.smoothstep(0, SLAM_WIND * 0.80, self.t),
            .smash_fall, .slam_air => 1.0 - mathx.clampF(self.t / 0.10, 0, 1),
            else => 0,
        };
    }
    /// -1 wound right back over itself, +1 thrown through — the LOB's one signed channel, on its own clock. Outside `rearAmt`/`foldAmt` on purpose: those are the vertical blows, and borrowing their curves would tell the player a smash was coming.
    fn lobAmt(self: *const Golem) f32 {
        return switch (self.state) {
            .sac_wind => -mathx.smoothstep(0, SAC_WIND * 0.72, self.t),
            .sac_throw => mathx.lerpF(-1.0, 1.0, mathx.clampF(self.t / SAC_THROW, 0, 1)),
            .sac_rec => 1.0 - mathx.smoothstep(0, SAC_RECOVER * 0.6, self.t),
            else => 0,
        };
    }
    /// 0..1 of the blow itself.
    fn foldAmt(self: *const Golem) f32 {
        return switch (self.state) {
            .smash_fall => mathx.smoothstep(0, SMASH_FALL, self.t),
            .smash_rec => 1.0 - mathx.smoothstep(0, SMASH_RECOVER * 0.55, self.t),
            .slam_air => mathx.smoothstep(SLAM_AIR * 0.45, SLAM_AIR, self.t),
            .slam_rec => 1.0 - mathx.smoothstep(0, SLAM_RECOVER * 0.5, self.t),
            else => 0,
        };
    }
};


fn buildBone(b: *Builder, i: usize) void {
    var rng = mathx.Rng.init(0x60_1E33 + @as(u64, @intCast(i)));
    switch (i) {
        BODY => {
            b.setMat(.skin);
            // The sporeling's own profile with the mass moved UP, which is what turns a mushroom into something that can throw itself.
            b.addBlob(v3(0, 0.12 * H, 0), v3(0.24 * H, 0.26 * H, 0.22 * H), 11, 9, FLESH);
            b.addBlob(v3(0, -0.08 * H, 0), v3(0.20 * H, 0.14 * H, 0.19 * H), 9, 8, FLESH_DK);
            var k: u32 = 0;
            while (k < 9) : (k += 1) {
                const a = rng.angle();
                const rr = 0.24 * H * rng.range(0.7, 1.05);
                const s = rng.range(0.030, 0.062) * H;
                b.addBlob(
                    v3(mathx.cosf(a) * rr, rng.range(-0.10, 0.20) * H, mathx.sinf(a) * rr),
                    v3(s, s * rng.range(0.7, 1.2), s),
                    5,
                    5,
                    if (rng.float() < 0.35) FLESH else FLESH_DK,
                );
            }
        },
        CAP => {
            b.setMat(.skin);
            // **THE CAP IS THE WEAPON AND IT IS SIZED LIKE ONE.** Wider than the body it sits on, so the silhouette says "this comes down on you" before the creature has done anything.
            b.addBlob(v3(0, 0.04 * H, 0), v3(CAP_R, 0.20 * H, CAP_R * 0.95), 13, 10, CAP_COL);
            b.addBlob(v3(0, 0.15 * H, 0), v3(CAP_R * 0.66, 0.12 * H, CAP_R * 0.64), 10, 8, CAP_DK);
            b.addBlob(v3(0, -0.04 * H, 0), v3(CAP_R * 0.88, 0.030 * H, CAP_R * 0.84), 10, 9, GILL);
            var k: u32 = 0;
            while (k < 14) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 14.0 * std.math.tau + rng.range(-0.12, 0.12);
                const rr = CAP_R * rng.range(0.55, 0.92);
                const s = rng.range(0.020, 0.048) * H;
                b.addBlob(v3(mathx.cosf(a) * rr, 0.09 * H, mathx.sinf(a) * rr), v3(s, s * 0.7, s), 5, 5, CAP_DK);
            }
            // The only bright thing on it, and the reason you can see the cap coming in a dark hollow.
            b.setMat(.plain);
            b.addBlob(v3(0, -0.06 * H, 0), v3(CAP_R * 0.46, 0.026 * H, CAP_R * 0.44), 9, 8, MOTE);
            b.addBlob(v3(0, -0.07 * H, 0), v3(CAP_R * 0.24, 0.020 * H, CAP_R * 0.22), 8, 7, CORE);
        },
        ARML, ARMR => {
            b.setMat(.skin);
            const side: f32 = if (i == ARML) 1.0 else -1.0;
            b.addCapsule(
                v3(0, 0, 0),
                v3(side * 0.075 * H, -0.34 * H, 0.02 * H),
                0.105 * H,
                0.125 * H,
                9,
                FLESH,
            );
            b.addBlob(v3(side * 0.075 * H, -0.37 * H, 0.02 * H), v3(0.13 * H, 0.10 * H, 0.14 * H), 8, 7, FLESH_DK);
        },
        LEGL, LEGR => {
            b.setMat(.skin);
            b.addCapsule(v3(0, 0, 0), v3(0, -0.19 * H, 0), 0.085 * H, 0.10 * H, 8, FLESH_DK);
            b.addBlob(v3(0, -0.20 * H, 0.02 * H), v3(0.11 * H, 0.05 * H, 0.14 * H), 7, 6, FLESH_DK);
        },
        else => {},
    }
}

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn draw(self: *const Model, t: *const Golem) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, t.xf[i]);
    }

    pub fn build(shader: rl.Shader) Model {
        var mesh: [N]rl.Mesh = undefined;
        for (0..N) |i| {
            var b = Builder.init();
            buildBone(&b, i);
            mesh[i] = b.toMesh();
        }
        return .{ .mesh = mesh, .mat = gfx.material(shader, "spore golem") };
    }
};

/// **THE MAP'S OWN PER-KIND CAP** — it was a bare 8, so a map placing a ninth golem got eight and `foe.resetGroup` dropped the rest in silence.
pub const CAP_N: usize = wf.MAX_PER_KIND;

/// THE SAC IN FLIGHT — it wears the cap's palette rather than a new one. Not the mage's ball: that thing is LIGHT, drawn additive; this is a lump with gills showing.
pub fn sacMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(mathx.zero3, v3(0.20, 0.17, 0.22), 8, 10, CAP_COL);
    b.addBlob(v3(0, -0.05, -0.03), v3(0.13, 0.10, 0.14), 7, 8, CAP_DK);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.06, 0.02), v3(0.11, 0.07, 0.11), 7, 8, MOTE);
    return b.toModel(shader);
}

pub const Host = struct {
    model: Model,
    ones: [CAP_N]Golem = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Host {
        return .{ .model = Model.build(shader) };
    }
    pub fn live(self: *Host) []Golem {
        return self.ones[0..self.n];
    }
    pub fn liveConst(self: *const Host) []const Golem {
        return self.ones[0..self.n];
    }
    pub fn reset(self: *Host, m: *const wf.Map) void {
        foe.resetGroup(Golem, &self.ones, &self.n, m, .spore_golem);
    }
    pub fn update(self: *Host, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn setShader(self: *Host, sh: rl.Shader) void {
        self.model.mat.shader = sh;
    }
    pub fn draw(self: *const Host, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn pierce(self: *Host, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Host) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Host) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Host) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn drawFx(self: *const Host) void {
        for (self.liveConst()) |*h| h.drawFx();
    }
    pub fn aliveCount(self: *const Host) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

test "THE HOMUNCULUS IS ANSWERED WITH FIRE, NOT WITH A SWORD" {
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    const light = combat.Hit{ .dmg = 13 };
    const heavy = combat.Hit{ .dmg = 27 };
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 27 }) };
    const took_l = g.vit.damageFrom(light);
    const took_h = g.vit.damageFrom(heavy);
    const took_f = g.vit.damageFrom(fire);
    std.debug.print("\n  spore golem: armour {d:.0} — a 13 light lands {d:.1} ({d:.0} swings), a 27 heavy lands {d:.1} ({d:.0}), 27 fire lands {d:.1} ({d:.0})\n", .{ ARMOUR, took_l, HP_MAX / took_l, took_h, HP_MAX / took_h, took_f, HP_MAX / took_f });
    try std.testing.expect(took_l < 13.0 * 0.55);
    try std.testing.expect(took_h < 27.0 * 0.70);
    try std.testing.expect(took_f > 27.0 * 1.5);
    // **A MARGIN, NOT A WALL** (owner: seems impossible to hit with melee). At 4x the fight was 21 heavy swings
    // against the ogre's 11. Bounded at BOTH ends: under 2 the armour says nothing, over 3.5 the sword stops being a choice a player can make badly.
    const margin = took_f / took_h;
    try std.testing.expect(margin > 2.0 and margin < 3.5);
    // …and it may never take longer with a sword than the OGRE does, which carries half again the health and no armour at all. That comparison is the one the number got away from.
    try std.testing.expect(HP_MAX / took_h < 300.0 / 27.0 * 1.25);
    // …and armour is never immunity, however much of it there is (`combat.armourTaken`).
    try std.testing.expect(took_l > 0 and took_h > 0);
}

test "HIS SWORD CAN ACTUALLY REACH IT — the blade is taken on every live state, not discarded" {
    const swing = foe.Blade{
        .active = true,
        .r = 0.35,
        .a = v3(0, 0.8, -1.2),
        .b = v3(0, 0.8, 1.2),
        .a0 = v3(0, 0.8, -1.2),
        .b0 = v3(0, 0.8, 1.2),
        .hit = .{ .dmg = 13, .poise = 6 },
    };
    for ([_]State{ .idle, .walk, .smash_wind, .smash_fall, .smash_rec, .slam_wind, .slam_air, .slam_rec, .stunlight, .stunheavy }) |st| {
        var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
        g.state = st;
        _ = g.update(1.0 / 60.0, v3(0, 0, 30), 200, swing);
        try std.testing.expectEqual(@as(u32, 1), g.hits);
        try std.testing.expect(g.vit.hp < HP_MAX);
    }
}

test "A DEATH IS ONE FRAME LONG, and the flakes outlive the body that threw them" {
    const dt: f32 = 1.0 / 60.0;
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 4.0);
    _ = g.update(dt, hero, 200, .{});
    try std.testing.expect(!g.justDied);

    g.vit.hp = 0;
    g.vit.dead = true;
    const Live = struct {
        fn count(ps: []const foe.Particle) usize {
            var n: usize = 0;
            for (ps) |q| {
                if (q.life > 0) n += 1;
            }
            return n;
        }
    };

    var claims: u32 = 0;
    var frames: u32 = 0;
    var atGone: usize = 0;
    var goneAt: ?u32 = null;
    while (frames < 900) : (frames += 1) {
        _ = g.update(dt, hero, 200, .{});
        if (g.justDied) claims += 1;
        if (g.gone and goneAt == null) {
            goneAt = frames;
            atGone = Live.count(&g.parts);
        }
    }
    std.debug.print("\n  spore golem: {d} frame(s) claimed a death over {d}; gone at frame {d} with {d} flakes still up, {d} left now\n", .{ claims, frames, goneAt orelse 0, atGone, Live.count(&g.parts) });
    // **ONE.** `Host.live` hands out the whole slab with no `gone` filter, so a flag left set here is one `game.anyFoeDied` reads every frame for the rest of the map.
    try std.testing.expectEqual(@as(u32, 1), claims);
    try std.testing.expect(goneAt != null);
    // …and the flakes still up when the slab went have aged out since, rather than frozen where they were.
    try std.testing.expect(atGone > 0);
    try std.testing.expectEqual(@as(usize, 0), Live.count(&g.parts));
}

test "THE FIRST TWO BANDS COVER EACH OTHER: the smash owns its feet, the slam owns where you back off to" {
    std.debug.print("  spore golem: smash {d:.2} m at a {d:.2} s tell | slam {d:.1} m from {d:.1}..{d:.1} at a {d:.2} s tell\n", .{ SMASH_R, SMASH_WIND, SLAM_REACH, SLAM_MIN, SLAM_MAX, SLAM_WIND });
    try std.testing.expect(SLAM_WIND * 2.0 < SMASH_WIND);
    // Backing out of the smash puts you INSIDE the slam's opening band, which is the whole trap.
    try std.testing.expect(SMASH_R < SLAM_MIN);
    try std.testing.expect(SLAM_MIN < SMASH_R + 2.0);
    try std.testing.expect(WALK_SPEED < 1.2);
}

test "AND A THIRD BAND PAST BOTH: WALKING AWAY IS NOT AN ANSWER ANY MORE" {
    std.debug.print("  spore golem: sac {d:.1}..{d:.1} m at a {d:.2} s tell, {d:.0} s apart | walks {d:.2} m/s against a hero's 3.40 run\n", .{ SAC_MIN, SAC_MAX, SAC_WIND, SAC_CD, WALK_SPEED });
    // THE HOLE IT FILLS: past the slam's far edge the creature had nothing, and it closes ground at less than a third of a run.
    try std.testing.expect(SLAM_MAX < SAC_MIN);
    try std.testing.expect(SAC_MAX > SLAM_MAX + 4.0);
    // …AND IT IS STILL THE SLOWEST TELL ON THE FIELD. It answers a player with room to read it, so it may not be the thing that punishes him for having room.
    try std.testing.expect(SAC_WIND > SMASH_WIND and SAC_WIND > SLAM_WIND * 3.0);
    // Area denial, not artillery: the sac itself does less than either fist.
    try std.testing.expect(SAC_HIT.dmg * 3.0 < SMASH_HIT.dmg);

    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.5);
    const hero = v3(0, 0, (SAC_MIN + SAC_MAX) * 0.5);
    var t: f32 = 0;
    var from: ?rl.Vector3 = null;
    while (t < 8.0 and from == null) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, hero, 400, .{});
        from = g.lobFrom;
    }
    const at = from orelse return error.TestUnexpectedResult;
    // IT LEAVES OVER ITS OWN BRIM, not out of its chest — the arc has to start above the cap it came from.
    try std.testing.expect(at.y > g.pos.y + CAP_Y * 0.9);
    // ONE SAC PER THROW: the flag is one frame, like every other creature's.
    var more: u32 = 0;
    var k: u32 = 0;
    while (k < 30) : (k += 1) {
        _ = g.update(1.0 / 60.0, hero, 400, .{});
        if (g.lobFrom != null) more += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), more);
    try std.testing.expect(!g.airborne());
}

test "A ROOTED GOLEM CAN STILL THROW — the roots take the leap, not the arm" {
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.5);
    g.root.grab();
    const hero = v3(0, 0, (SAC_MIN + SAC_MAX) * 0.5);
    var lobbed = false;
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD * 0.9) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, hero, 400, .{});
        if (g.lobFrom != null) lobbed = true;
        try std.testing.expect(g.state != .slam_air);
    }
    try std.testing.expect(lobbed);
}

test "IT COMMITS TO A SPOT AND CANNOT STEER ONTO HIM IN THE AIR" {
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.5);
    const hero = v3(0, 0, 5.0);
    var t: f32 = 0;
    while (t < 6.0 and g.state != .slam_air) : (t += 1.0 / 60.0) _ = g.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expect(g.state == .slam_air);
    const aimed = g.launch;
    const moved = v3(6.0, 0, 5.0);
    var k: u32 = 0;
    while (k < 4) : (k += 1) _ = g.update(1.0 / 60.0, moved, 400, .{});
    try std.testing.expectApproxEqAbs(aimed.x, g.launch.x, 1e-5);
    try std.testing.expectApproxEqAbs(aimed.z, g.launch.z, 1e-5);
    try std.testing.expect(g.airborne());
}

test "THE STAMPED WAY IS ACTUALLY READ, and a slam broken in the air comes down" {
    const dt: f32 = 1.0 / 60.0;
    // OUTSIDE THE LOB'S BAND: at 12 m it throws a sac instead of setting off, and a walk test that spends
    // three seconds in a throw first is measuring the wrong thing.
    const hero = v3(0, 0, SAC_MAX + 1.2);

    // **THE STAMP BENDS THE WALK.** `markWays` asks `navWant` while the body is in its TRAVEL state, so a
    // heading written onto `nav` has to move the creature — a field nothing reads is the silent half of
    // `game.markWays`' field-implies-method pin.
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.5);
    while (g.state != .walk) _ = g.update(dt, hero, 400, .{});
    try std.testing.expect(g.navWant(hero) != null);
    var bent = g;
    bent.nav.dir = v3(1, 0, 0);
    var k: u32 = 0;
    while (k < 30) : (k += 1) {
        _ = g.update(dt, hero, 400, .{});
        _ = bent.update(dt, hero, 400, .{});
        bent.nav.dir = v3(1, 0, 0);
    }
    try std.testing.expect(bent.pos.x > g.pos.x + 0.1);

    // …AND IT WALKS WHERE IT LOOKS: spawned facing away it sets off the way it is pointing and turns, rather
    // than sliding backwards at him for the two seconds a 1.5 rad/s about-face takes.
    var away = Golem.spawn(mathx.zero3, 180.0, 1.0, 0.5);
    while (away.state != .walk) _ = away.update(dt, hero, 400, .{});
    const from = away.pos;
    k = 0;
    while (k < 12) : (k += 1) _ = away.update(dt, hero, 400, .{});
    try std.testing.expect(away.pos.z < from.z);

    // **AND A BODY CAUGHT IN MID-FLIGHT IS ON THE GROUND ON THE FRAME IT IS CAUGHT** (`frog.base`'s rule).
    var air = Golem.spawn(mathx.zero3, 0, 1.0, 0.5);
    var t: f32 = 0;
    while (t < 6.0 and air.state != .slam_air) : (t += dt) _ = air.update(dt, v3(0, 0, 5.0), 400, .{});
    try std.testing.expect(air.state == .slam_air);
    while (air.lift <= foe.AIRBORNE_LIFT) _ = air.update(dt, v3(0, 0, 5.0), 400, .{});
    try std.testing.expect(air.airborne());
    air.enter(.stunheavy);
    try std.testing.expectApproxEqAbs(@as(f32, 0), air.lift, 1e-6);
    try std.testing.expect(!air.airborne());
    try std.testing.expectApproxEqAbs(air.pos.y, air.centerWorld().y - CENTER_F * H, 1e-5);

    // **AND A BLOW FROM OUTSIDE ITS AGGRO STILL WAKES IT** — `foe.reached` rouses the tether, and the
    // decisions have to be reading that tether or the rouse buys nothing and a bow beats the creature.
    var plinked = Golem.spawn(mathx.zero3, 0, 1.0, 0.5);
    const far = v3(0, 0, AGGRO_R + 1.5);
    k = 0;
    while (k < 60) : (k += 1) _ = plinked.update(dt, far, 400, .{});
    try std.testing.expect(plinked.state == .idle);
    plinked.leash.provoke();
    k = 0;
    while (k < 60) : (k += 1) _ = plinked.update(dt, far, 400, .{});
    try std.testing.expect(plinked.state != .idle);
}

test "THE WAND REACHES IT: the grip bills and lets go, and the rime's cone does too" {
    const dt: f32 = 1.0 / 60.0;
    const hero = v3(0, 0, 4.0);

    // **ROOTS BILL, AND THE GRIP EXPIRES.** `game.seedRoots` writes `root` on whatever it picks, and a
    // creature that never calls `foe.grip` bills none of it and holds the clock open for good — the spell
    // costs 12 FP and does literally nothing.
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    const before = g.vit.hp;
    g.root.grab();
    try std.testing.expect(g.root.held());
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD + 0.2) : (t += dt) _ = g.update(dt, hero, 400, .{});
    try std.testing.expect(!g.root.held());
    const paid = before - g.vit.hp;
    std.debug.print("\n  spore golem: the roots bill {d:.1} of a {d:.0} bar over {d:.1} s\n", .{ paid, HP_MAX, combat.ROOT_HOLD });
    try std.testing.expect(paid > 0);
    // CHAOS, and it resists chaos hard, so the bill is well under the raw drip rather than equal to it.
    try std.testing.expect(paid < combat.ROOT_HOLD * combat.ROOT_DPS);

    // **AND THE FEET ARE HELD WHILE IT RUNS** — the whole point of the spell on a thing that walks at you.
    var pinned = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    while (pinned.state != .walk) _ = pinned.update(dt, v3(0, 0, 9.0), 400, .{});
    pinned.root.grab();
    const stood = pinned.pos;
    var k: u32 = 0;
    while (k < 20) : (k += 1) _ = pinned.update(dt, v3(0, 0, 9.0), 400, .{});
    try std.testing.expectApproxEqAbs(stood.x, pinned.pos.x, 1e-5);
    try std.testing.expectApproxEqAbs(stood.z, pinned.pos.z, 1e-5);

    // **THE RIME BILLS AS COLD, WHICH IT RESISTS** — the cone is poured every frame it is held, so what has
    // to happen here is that the owed bite is collected at all.
    var cold = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hp0 = cold.vit.hp;
    t = 0;
    while (t < combat.RIME_DUR) : (t += dt) {
        cold.chill.breathe(dt);
        _ = cold.update(dt, hero, 400, .{});
    }
    try std.testing.expect(cold.vit.hp < hp0);
    try std.testing.expect(cold.chill.held());
    t = 0;
    while (t < combat.CHILL_HOLD + 0.2) : (t += dt) _ = cold.update(dt, hero, 400, .{});
    try std.testing.expect(!cold.chill.held());
}

test "A STAGGER FROM ANYWHERE PICKS THE RIGHT SEVERITY — `stance <= 0` never was true" {
    const dt: f32 = 1.0 / 60.0;
    const hero = v3(0, 0, 4.0);
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    _ = g.update(dt, hero, 400, .{});
    // A break straight through the bars, the way a blow that did not come down `tryHit` arrives. `Vitals.hit`
    // refills `stance` on the frame it breaks, so the severity has to be read off the stun and not off a bar.
    g.vit.stance = 1;
    try std.testing.expectEqual(combat.HitResult.heavy, g.vit.hit(.{ .stance = 40 }));
    try std.testing.expect(g.vit.stunHeavy());
    _ = g.update(dt, hero, 400, .{});
    try std.testing.expectEqual(State.stunheavy, g.state);

    var lit = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    _ = lit.update(dt, hero, 400, .{});
    // A creature's flinch is damage poured into the pool (`combat.FOE_POISE_PER_DMG`), so empty the pool and land one point.
    lit.vit.poise = 0.5;
    try std.testing.expectEqual(combat.HitResult.light, lit.vit.hit(.{ .dmg = 20 }));
    try std.testing.expect(!lit.vit.stunHeavy());
    _ = lit.update(dt, hero, 400, .{});
    try std.testing.expectEqual(State.stunlight, lit.state);
}

test "IT CANNOT SLAM ITS WAY OUT OF THE ROOTS — the leap is gated where the move is chosen" {
    const dt: f32 = 1.0 / 60.0;
    // Standing in the slam's own band, cooldown clear, and held by the ankles: it may pick anything but the
    // leap. `foe.grip`'s airborne guard lets a body finish an arc it is ALREADY in, so a jump still allowed to
    // start is a jump straight out of the fist of roots (`ravager`'s own note).
    const hero = v3(0, 0, (SLAM_MIN + SLAM_MAX) * 0.5);
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    g.root.grab();
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD * 0.8) : (t += dt) {
        _ = g.update(dt, hero, 400, .{});
        try std.testing.expect(g.state != .slam_wind and g.state != .slam_air);
    }
    // …and the same golem, unheld, takes it — or the gate above is passing for the wrong reason.
    var free = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    t = 0;
    var leapt = false;
    while (t < 6.0 and !leapt) : (t += dt) {
        _ = free.update(dt, hero, 400, .{});
        if (free.state == .slam_wind or free.state == .slam_air) leapt = true;
    }
    try std.testing.expect(leapt);
}

test "THE DISC IS DRAWN BEFORE IT IS BILLED — the smash walks its own rim through the whole wind" {
    var g = Golem.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    g.leash.noteSeen();
    const hero = mathx.ground(0, 2.0);
    const dt: f32 = 1.0 / 60.0;
    var emitted: usize = 0;
    var wound = false;
    var t: f32 = 0;
    while (t < 4.0) : (t += dt) {
        const before = g.fxHead;
        _ = g.update(dt, hero, 500.0, .{});
        if (g.state == .smash_wind) {
            wound = true;
            emitted += (g.fxHead + PARTS - before) % PARTS;
        }
        if (g.struck) break;
    }
    try std.testing.expect(wound);
    try std.testing.expect(g.struck);
    // ~30/s across a 0.92 s wind, and every mote sits ON the rim — the blow's own radius off its own centre.
    const centre = g.reachPoint(SMASH_R * 0.62);
    const rim = SMASH_R * g.scale;
    var on: usize = 0;
    var off: usize = 0;
    for (&g.parts) |*q| {
        if (q.life <= 0 or !q.add) continue;
        const d = mathx.distXZ(q.p, centre);
        if (@abs(d - rim) < 0.30) on += 1 else off += 1;
    }
    std.debug.print("\n  golem smash tell: {d} motes over the wind, {d} on the rim / {d} off it (rim {d:.2} m)\n", .{ emitted, on, off, rim });
    try std.testing.expect(emitted >= 20);
    try std.testing.expect(on >= 8);
    try std.testing.expect(off <= on / 2);
}

test "A FULL STUN METER PUTS IT DOWN — the one creature that reads `vit.stunned()` and not `grip.downed`" {
    // The bug this pins: twenty creatures answer `foe.grip`'s `downed` with `stagger(true)`; this one has no
    // such method and syncs its state off `vit.stunned()`, which ONLY sleep ever set. So a lightning stun
    // filled, procced, and the slab carried on swinging — on the creature `RESISTS` marks as lightning's own.
    var g = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    g.vit.build(.stun, combat.ailRow(.stun).max);
    _ = g.update(dt, v3(0, 0, 30), 200, .{});
    std.debug.print("\n  stun proc: state {s}, {d:.2} s of hold left\n", .{ @tagName(g.state), g.vit.stunLeft });
    try std.testing.expectEqual(State.stunheavy, g.state);
    try std.testing.expect(g.staggered());

    // …and lightning is what fills it, through the same door every other element builds its meter down.
    var lit = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    _ = lit.vit.hit(combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) });
    try std.testing.expect(lit.vit.ailFrac(.stun) > 0);

    // A DEAD SLAB IS NEVER PUT DOWN — `grip.downed` is already gated on it, and the dead check must still win.
    var corpse = Golem.spawn(mathx.zero3, 0, 1.0, 0.3);
    corpse.vit.dead = true;
    corpse.vit.build(.stun, combat.ailRow(.stun).max);
    _ = corpse.update(dt, v3(0, 0, 30), 200, .{});
    try std.testing.expectEqual(State.dead, corpse.state);
}
