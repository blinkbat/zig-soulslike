const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;

// CUTE IS A SHAPE LANGUAGE: one big dome, one squat pale body, one gaping mouth, and everything blunt.
/// **THE KINGDOM'S OWN RUST, AND IT IS PUBLIC BECAUSE IT IS NOT THIS CREATURE'S.** The mushroom mage
/// wears the same cap (`shroommage.zig`), and a second copy of these three drifted the day either was
/// retuned — two fungal things in one wood that no longer look like the same substance.
pub const CAP_COL = rgba(52, 18, 14, 255);
pub const CAP_DK = rgba(34, 12, 10, 255); // the chipped bite out of the rim, and the gills' shadow
/// **THE FLECKS FAINTLY GLOW** (owner). Vertex alpha is the emissive channel and lower is more self-lit, so
/// this is only a little under full: FAINT is the whole brief — a sporeling that lit up like the ravager's
/// gullet would out-read the creature the glow belongs to, and these are meant to be a hint in the dark that
/// something small is standing in the bracken. Small areas, so they may run pale without washing the cap out.
pub const WART = rgba(122, 112, 84, 186);
const STALK = rgba(72, 62, 45, 255);
const STALK_DK = rgba(52, 44, 32, 255); // the skirt fold under the cap
const MOUTH = rgba(10, 8, 7, 255);
/// The spores: dry ochre dust with a violet cast — chaos, the brood's own element, in one hue family with
/// the wand and the pools so a third purple in the world does not become a third substance.
const SPORE = rgba(192, 172, 136, 215);
const SPORE_VIO = rgba(134, 92, 172, 210);
/// How much of the cloud is the violet. Past a third, which is what makes it the colour you notice rather
/// than a fleck through the ochre.
const SPORE_VIO_SHARE: f32 = 0.48;

/// Its own stature, cap-top off the ground. SQUAT (owner's word) — knee height on the hero.
pub const H: f32 = 0.92;

pub const AGGRO_R: f32 = 9.0;
const KEEP_R: f32 = 1.25; // close enough; it waits here for the fling to come back
const HOME_R: f32 = 2.0;

const BODY_R: f32 = 0.40;
const HURT_R: f32 = 0.55;
const CENTER_F: f32 = 0.42; // of H — the middle of the little body
const TOP_F: f32 = 1.05;

const HP_MAX: f32 = 34.0; // fragile on purpose: the threat is the cloud, not the body
const POISE_MAX: f32 = 12.0; // one clean light flinches it
const STANCE_MAX: f32 = 26.0;
/// A DAMP LITTLE FUNGUS STUFFED WITH ITS OWN ELEMENT: chaos barely touches it, fire eats it, and a cold
/// snap is just weather in the wood.
const RESISTS = combat.resists(.{ .fire = -50, .cold = 15, .chaos = 75 });
pub const SOULS: u32 = 70;

/// The BONK — its whole body arriving. Light: the cloud it leaves behind is the actual bill.
pub const FLING_HIT = combat.Hit{ .dmg = 12, .poise = 20, .stance = 8 };
/// WHAT STANDING IN THE CLOUD COSTS, AND IT IS NO LONGER DAMAGE: the spores POISON him (`combat.Status`).
pub const SPORE_BUILD: f32 = 24.0;

// The approach is HOPPING — a mushroom has no legs worth walking on, and the bounce is the character.
const HOP_REACH: f32 = 1.05;
const HOP_APEX: f32 = 0.42;
const HOP_COIL: f32 = 0.16;
const HOP_FLIGHT: f32 = 0.34;
const HOP_LAND: f32 = 0.14;
const HOP_SETTLE: f32 = 0.10;

/// THE FLING. It gathers (deep squat, cap tipped back, trembling), then throws its whole body in a high
/// arc and pops its cloud where it lands. Chosen ONLY inside its own reach (the cannot-land law): from
/// farther out it hops in first.
const FLING_MAX: f32 = 5.4;
const GATHER_DUR: f32 = 0.62; // >= foe.TELL_MIN, and the deep squat is readable across the band
const FLING_FLIGHT: f32 = 0.55;
const FLING_APEX: f32 = 1.7;
const FLING_LAND: f32 = 0.16; // the splat itself; the flop-recover follows as its own state
const FLING_CD: f32 = 4.6;
const RECOVER_DUR: f32 = 0.95; // belly-down wobble back onto its feet — the ordinary opening
const SPLAT_R: f32 = 0.85; // the bonk bills this far around the landing point (plus the hero's footprint)

/// …AND SOMETIMES IT TRIPS (owner's call). Same gather, same tremble — then it catches a root and eats
/// dirt where it stands. No blow, no cloud, and a sprawl half again the fling's own recovery: the roll is
/// the unpredictability and the pratfall is the punish window.
const TRIP_CHANCE: f32 = 0.28;
const TRIP_FALL: f32 = 0.24;
const TRIP_SPRAWL: f32 = 1.15;
const TRIP_RISE: f32 = 0.50;

/// The cloud: where a fling lands, a slow ochre bloom that stays after the creature has bounced off.
pub const CLOUD_LIFE: f32 = 3.4;
pub const CLOUD_R: f32 = 1.9;
const CLOUD_GROW: f32 = 0.5; // seconds to full radius
const CLOUD_CAP: usize = 8;

const DEATH_DUR: f32 = 0.9; // small body, quick topple
const DISS_DUR: f32 = 0.9;
const SHOVE_DECAY: f32 = 8.0; // named like every sibling's, rather than a literal at the one call site
const DISSOLVE = foe.Dissolve{ .rate = 46.0, .spread = 0.6, .rise = 0.8, .flake = SPORE };

/// Sized by ARITHMETIC over the emitters' worst frame (the ring-buffer law): the landing stacks the
/// 16-spore burst (life ≤ 0.7) on 14 dust (≤ 0.5) on the flight trail's last 0.55 s at 26/s (≈ 14).
const PARTS = 48;

// The rig: six bones of toy.
const N = 6;
const BODY = 0;
const CAP = 1;
const FOOTL = 2;
const FOOTR = 3;
const ARML = 4;
const ARMR = 5;

const REST = [N]rl.Vector3{
    v3(0, 0, 0),
    v3(0, 0.56 * H, 0.02),
    v3(0.13, 0.05, 0.04),
    v3(-0.13, 0.05, 0.04),
    v3(0.24, 0.36 * H, 0.03),
    v3(-0.24, 0.36 * H, 0.03),
};

const State = enum { idle, hop, gather, fling, trip, recover, stunlight, stunheavy, dead };

/// PURE DECISION — rooted, it can only wait (both the hop and the fling LEAVE THE EARTH, `foe.canLeap`).
const Choice = enum { rest, wait, hop, fling };
fn classify(dist: f32, flingReady: bool, rooted: bool) Choice {
    if (rooted) return .wait;
    if (dist > AGGRO_R) return .rest;
    if (dist <= FLING_MAX and flingReady) return .fling;
    if (dist > KEEP_R) return .hop;
    return .wait;
}

/// What one frame of this creature did that the CLUSTER has to answer for — the cloud outlives the flight
/// that threw it, so it belongs to the group, not the body.
pub const Act = union(enum) {
    none,
    /// It landed a fling here: pop the cloud, and `hit` if the body arrived on the hero.
    burst: struct { at: rl.Vector3, hit: ?combat.Hit },
};

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "shroom");
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, t: *const Shroom) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, t.xf[i]);
    }
};

pub const Shroom = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS, stamped from outside like every creature's — and everything this creature does is
    /// a leap, so held by the ankles it can only stand there and tremble.
    root: combat.Root = .{},
    /// THE RIME BREATH'S COLD (`combat.Chill`) — stamped from outside like the roots, and billed through the
    /// same `foe.grip`. The field is what opts a creature into the cone at all (`game.rimeBreathe`).
    chill: combat.Chill = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    idleWait: f32 = 0.4,
    flingCd: f32 = 0,
    /// The trip's die, CAST AT THE DECISION and spent at the launch instant — the gather must be one
    /// animation whichever way it ends, or the roll would be readable and the joke dead.
    tripping: bool = false,
    homing: bool = false,

    hopFrom: rl.Vector3 = mathx.zero3,
    hopTo: rl.Vector3 = mathx.zero3,
    hopAim: rl.Vector3 = mathx.zero3,
    hopReach: f32 = 0,
    hopDur: f32 = 0,
    hopApex: f32 = 0,
    launched: bool = false,
    lift: f32 = 0, // world-Y height of the body over `pos.y` mid-arc

    // pose channels
    squash: f32 = 1, // <1 loaded/splatted, >1 stretched in flight — the whole-toy squash
    pitch: f32 = 0, // body rx: forward over its face on the trip, back on the gather
    armUp: f32 = 0, // 0 hanging … 1 flung out wide (flight, and the sprawl)
    kick: f32 = 0, // the feet paddling — flight, and the upended sprawl
    capLagX: f32 = 0, // the cap arrives late (follower on pitch) — the wobble that makes it a toy
    capLagY: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    burstAt: ?rl.Vector3 = null, // one-frame, like `justDied`: the cluster reads it after update
    justDied: bool = false,
    /// WHO IT IS FIGHTING (`foe.Threat`) — embedded here and stamped by the game, `Leash`'s own law.
    threat: foe.Threat = .{},
    /// …AND THE WAY ROUND WHAT IS IN THE WAY (`foe.Nav`), stamped the same way and for the same reason.
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Shroom {
        var s = Shroom{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        s.fxRng = foe.fxStream(seed, 60013.0, 0x5B00);
        s.aiRng = foe.fxStream(seed, 35317.0, 3);
        s.idleWait = 0.2 + seed * 0.5;
        s.pose();
        return s;
    }

    pub fn centerWorld(self: *const Shroom) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.lift);
    }
    /// THE MARK RIDES THE CAP — the one part of it that is always doing something.
    pub fn lockPoint(self: *const Shroom) rl.Vector3 {
        return foe.markOn(self.xf[CAP], v3(0, 0.04, 0));
    }
    pub fn topWorld(self: *const Shroom) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.lift);
    }
    pub fn hurtRadius(self: *const Shroom) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Shroom) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Shroom) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Shroom) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Shroom) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(self: *const Shroom) bool {
        return self.lift > foe.AIRBORNE_LIFT;
    }
    pub fn flashFrac(self: *const Shroom) f32 {
        return foe.flashFrac(self.flash);
    }

    fn fdir(self: *const Shroom) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    /// WHERE IT IS TRYING TO GO (`game.markWay`), asked while it is SITTING — the toad's rule, and for its
    /// reason: this one travels in committed hops too, so the stamp has to be ready on the frame the next one is
    /// chosen.
    pub fn navWant(self: *const Shroom, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Shroom, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, 5.2, dt); // small and eager — it turns fast
    }

    pub fn update(self: *Shroom, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.heroHit = null;
        self.burstAt = null;
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.flingCd = mathx.maxF(0, self.flingCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        switch (self.state) {
            .idle => self.updateIdle(dt, hero, bounds),
            .hop => self.updateArc(dt, hero, bounds, HOP_COIL, self.hopDur, HOP_LAND, false),
            .gather => {
                self.faceToward(self.hopAim, dt);
                const k = mathx.smoothstep(0, GATHER_DUR, self.t);
                self.squash = lerpF(1.0, 0.62, k); // loads DEEP — the tell is the whole body
                self.pitch = lerpF(0, -14.0, k); // tipped back on its heels, cap up, eyes on you
                self.armUp = lerpF(self.armUp, 0.25, k);
                self.kick = 0;
                if (self.t >= GATHER_DUR * 0.7) self.emitTremble(dt); // spore-dust shakes off the cap
                if (self.t >= GATHER_DUR) {
                    // Re-asked at the LAUNCH: a wand root closing during the gather arrives after the
                    // choose site, and a leap is the one thing the grip refuses (`foe.canLeap`).
                    if (self.tripping or !foe.canLeap(&self.root)) {
                        // THE ROOT IT CAUGHT. Same gather to the last frame — the difference is only
                        // ever visible one frame too late, which is the whole joke and the whole tax.
                        sfx.world(.shroom_hurt, self.pos); // the chirp cracks — it knows
                        self.enter(.trip);
                    } else {
                        sfx.world(.shroom_fling, self.pos);
                        self.launched = false;
                        self.enter(.fling);
                    }
                }
            },
            .fling => self.updateArc(dt, hero, bounds, 0, FLING_FLIGHT, FLING_LAND, true),
            .trip => {
                const fall = mathx.smoothstep(0, TRIP_FALL, self.t);
                const rise = mathx.smoothstep(TRIP_FALL + TRIP_SPRAWL, TRIP_FALL + TRIP_SPRAWL + TRIP_RISE, self.t);
                self.pitch = lerpF(-14.0, 78.0, fall) - 78.0 * rise; // over its own face, flat on the cap
                self.squash = lerpF(0.62, 0.86, fall) + 0.14 * rise;
                self.armUp = fall * (1.0 - rise); // arms out where it lies
                // …and the little feet KICK while it is down: helpless, upended, alive.
                self.kick = mathx.sinf(self.elapsed * 16.0) * fall * (1.0 - rise);
                if ((self.t - dt) < TRIP_FALL and self.t >= TRIP_FALL) {
                    self.dustBurst(self.pos, 7, 1.3, 0.12);
                    self.emitPuff(self.pos, 4); // a feeble little cough of spores, cosmetic only
                }
                if (self.t >= TRIP_FALL + TRIP_SPRAWL + TRIP_RISE) {
                    self.flingCd = FLING_CD * 0.55 * self.aiRng.range(0.9, 1.2); // embarrassed; tries again sooner
                    self.enterIdle(0.1);
                }
            },
            .recover => {
                // Belly-down off the landing, wobbling back up onto its feet.
                const k = mathx.smoothstep(0, RECOVER_DUR, self.t);
                self.pitch = lerpF(34.0, 0, k) + 6.0 * mathx.sinf(self.t * 18.0) * (1.0 - k);
                self.squash = lerpF(0.74, 1.0, k);
                self.armUp = mathx.approach(self.armUp, 0, dt * 3.0);
                self.kick = mathx.approach(self.kick, 0, dt * 6.0);
                if (self.t >= RECOVER_DUR) self.enterIdle(0.15);
            },
            .stunlight, .stunheavy => {
                self.squash = mathx.approach(self.squash, 1.0, dt * 4.0);
                self.pitch = mathx.approach(self.pitch, -22.0, dt * 160.0); // knocked back on its heels
                self.armUp = mathx.approach(self.armUp, 0.8, dt * 6.0);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enterIdle(0.1);
            },
            .dead => {
                self.pitch = mathx.approach(self.pitch, 84.0, dt * 140.0); // face-down one last time
                self.squash = mathx.approach(self.squash, 0.7, dt * 2.0);
                self.lift = mathx.approach(self.lift, 0, dt * 4.0);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        // The cap chases the body a beat late — the toy wobble, through every state at once.
        self.capLagX = mathx.approach(self.capLagX, self.pitch * 0.5, dt * 260.0);
        self.capLagY = mathx.approach(self.capLagY, mathx.degrees(self.facing), dt * 400.0);
        self.pose();
        self.tryHit(blade);
        if (self.burstAt) |at| return .{ .burst = .{ .at = at, .hit = self.heroHit } };
        return .none;
    }

    fn updateIdle(self: *Shroom, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= AGGRO_R) self.faceToward(hero, dt);
        // Three little clocks (the wanderer's law, toy-sized): a breath, a cap sway, a weight rock.
        const br = mathx.sinf(self.elapsed * (1.7 + 0.4 * self.seed) + self.seed * 6.28);
        self.squash = mathx.approach(self.squash, 1.0 + 0.03 * br, dt * 3.0);
        self.pitch = mathx.approach(self.pitch, 2.0 * mathx.sinf(self.elapsed * 0.7 + self.seed * 9.0), dt * 30.0);
        self.armUp = mathx.approach(self.armUp, 0.06 + 0.05 * br, dt * 2.0);
        self.kick = mathx.approach(self.kick, 0, dt * 4.0);
        const wait = if (d <= AGGRO_R) mathx.minF(self.idleWait, 0.14) else self.idleWait;
        if (self.t >= wait) self.decide(hero, bounds);
    }

    fn decide(self: *Shroom, hero: rl.Vector3, bounds: f32) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        switch (classify(d, self.flingCd <= 0, !foe.canLeap(&self.root))) {
            .rest => {
                if (mathx.distXZ(self.pos, self.home) > HOME_R) {
                    self.homing = true;
                    self.beginHop(self.home, bounds);
                } else self.enterIdle(0.5 + self.seed * 0.4);
            },
            .wait => self.enterIdle(0.25),
            .hop => {
                self.homing = false;
                self.beginHop(hero, bounds);
            },
            .fling => self.beginFling(hero),
        }
    }

    fn beginHop(self: *Shroom, to: rl.Vector3, bounds: f32) void {
        const d = mathx.distXZ(self.pos, to);
        const reach = mathx.minF(HOP_REACH, mathx.maxF(0.3, d - KEEP_R * 0.8));
        // …ROUND WHAT IS IN THE WAY (`foe.Nav`), and HERE at the choose because a hop is committed the moment it
        // leaves the ground. The FLING is left straight: that one is the attack.
        const dir = self.nav.along(mathx.dirXZ(self.pos, to));
        self.hopAim = mathx.clampXZ(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds);
        self.hopReach = mathx.distXZ(self.pos, self.hopAim);
        self.hopDur = HOP_FLIGHT;
        self.hopApex = HOP_APEX;
        self.launched = false;
        self.enter(.hop);
        sfx.world(.shroom_hop, self.pos);
    }

    fn beginFling(self: *Shroom, hero: rl.Vector3) void {
        // Committed AT THE DECISION: where it goes, and whether it goes at all (`tripping`) — rolled here
        // so the gather cannot leak the outcome.
        self.hopAim = hero;
        self.hopReach = mathx.clampF(mathx.distXZ(self.pos, hero), 0.8, FLING_MAX);
        self.hopDur = FLING_FLIGHT;
        self.hopApex = FLING_APEX;
        self.tripping = self.aiRng.float() < TRIP_CHANCE;
        self.flingCd = FLING_CD * self.aiRng.range(0.85, 1.4);
        sfx.world(.shroom_coo, self.pos); // the tell's own voice — sweet, then the second note bends flat
        self.enter(.gather);
    }

    /// The frog's own arc (coil / flight / land), minus the coil for the fling — the GATHER state is its
    /// coil, so the fling enters here already loaded and leaves the ground on its first frame.
    fn updateArc(self: *Shroom, dt: f32, hero: rl.Vector3, bounds: f32, coil: f32, flight: f32, land: f32, fling: bool) void {
        const total = coil + flight + land;
        if (self.t < coil) {
            // At the AIM it committed to, never the hero: the launch re-aims along facing, so a homing
            // hop steered at the hero here flew AT him from any range and the little thing never got home.
            self.faceToward(self.hopAim, dt);
            const k = mathx.smoothstep(0, coil, self.t);
            self.squash = lerpF(1.0, 0.78, k);
        } else if (self.t < coil + flight) {
            if (!self.launched) {
                self.launched = true;
                self.hopFrom = self.pos;
                const f = self.fdir();
                self.hopTo = mathx.clampXZ(v3(self.pos.x + f.x * self.hopReach, 0, self.pos.z + f.z * self.hopReach), bounds);
            }
            const s = (self.t - coil) / flight;
            const inv = 1.0 / flight;
            // Velocity-increment, never an absolute lerp — the frog's warp-bug lesson.
            self.pos.x += (self.hopTo.x - self.hopFrom.x) * inv * dt;
            self.pos.z += (self.hopTo.z - self.hopFrom.z) * inv * dt;
            self.lift = self.hopApex * mathx.sinf(std.math.pi * mathx.clampF(s, 0, 1)) * self.scale;
            // Superman: arms out, feet paddling, cap pressed back by the wind of its own going.
            self.squash = 1.0 + @as(f32, if (fling) 0.18 else 0.10) * mathx.sinf(std.math.pi * s);
            self.pitch = if (fling) lerpF(-14.0, 42.0, s) else lerpF(-6.0, 18.0, s);
            self.armUp = if (fling) 1.0 else 0.4;
            self.kick = mathx.sinf(self.elapsed * 22.0) * 0.7;
            if (fling) self.emitTrail(dt);
        } else {
            self.lift = 0;
            const k = mathx.smoothstep(0, land, self.t - coil - flight);
            self.squash = lerpF(0.55, 0.74, k); // the SPLAT — flat as a dropped bun, then it comes back
            self.pitch = if (fling) 34.0 else lerpF(18.0, 0, k);
            self.kick = 0;
            if ((self.t - dt) < coil + flight) { // touchdown frame, once
                if (fling) {
                    self.dustBurst(self.pos, 14, 2.6, 0.20);
                    self.emitPuff(self.pos, 16);
                    sfx.world(.shroom_puff, self.pos);
                    self.burstAt = self.pos; // THE CLOUD — the cluster owns it from here
                    if (mathx.distXZ(self.pos, hero) <= (SPLAT_R + foe.HERO_REACH) * self.scale) {
                        self.heroHit = FLING_HIT; // the bonk itself
                        self.leash.noteCombat();
                    }
                } else {
                    self.dustBurst(self.pos, 4, 1.2, 0.10);
                }
            }
        }
        mathx.holdXZ(&self.pos, bounds);
        if (self.t >= total) {
            if (fling) {
                self.enter(.recover);
            } else if (self.homing and mathx.distXZ(self.pos, self.home) <= HOME_R) {
                self.homing = false;
                self.enterIdle(0.4);
            } else {
                self.enterIdle(HOP_SETTLE);
            }
        }
    }

    fn enter(self: *Shroom, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterIdle(self: *Shroom, wait: f32) void {
        self.state = .idle;
        self.t = 0;
        self.idleWait = wait;
        self.lift = 0;
    }
    fn enterStun(self: *Shroom, s: State) void {
        self.enter(s);
        self.lift = 0;
        self.tripping = false;
    }
    fn enterDeath(self: *Shroom) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugFling(self: *Shroom, hero: rl.Vector3) void {
        self.beginFling(hero);
        self.tripping = false;
    }
    pub fn debugTrip(self: *Shroom, hero: rl.Vector3) void {
        self.beginFling(hero);
        self.tripping = true;
    }
    pub fn debugKill(self: *Shroom) void {
        self.enterDeath();
    }
    pub fn debugStagger(self: *Shroom, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }

    pub fn tryHit(self: *Shroom, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.9, .heavy = 1.4 }); // light — it goes flying
        self.emitPuff(s.contact, if (heavy) 6 else 3); // it bleeds spores
        sfx.world(.shroom_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.shroom_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn emit(self: *Shroom, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }
    fn dustBurst(self: *Shroom, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.0) * spd;
            self.emit(v3(c.x, self.pos.y + 0.04, c.z), v3(mathx.cosf(a) * sp, self.fxRng.range(0.5, 1.6), mathx.sinf(a) * sp), self.fxRng.range(0.3, 0.5), self.fxRng.range(0.04, 0.08), big, foe.DUST, 4.5);
        }
    }
    /// Spore dust — the puffs are ITS blood and its exhaust both, in the cloud's own two tones.
    fn emitPuff(self: *Shroom, at: rl.Vector3, n: i32) void {
        const parts = foe.hitParts(n); // the field's one dial (`foe.HIT_PARTS`)
        var i: i32 = 0;
        while (i < parts) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.3, 1.1);
            self.emit(
                v3(at.x, at.y + 0.2, at.z),
                v3(mathx.cosf(a) * sp, self.fxRng.range(0.4, 1.3), mathx.sinf(a) * sp),
                self.fxRng.range(0.45, 0.7),
                self.fxRng.range(0.05, 0.09),
                self.fxRng.range(0.11, 0.17),
                if (self.fxRng.float() < SPORE_VIO_SHARE) SPORE_VIO else SPORE,
                0.6,
            );
        }
    }
    fn emitTremble(self: *Shroom, dt: f32) void {
        const emitRate = 9.0;
        var owed = foe.emitTicks(&self.fxAccum, dt, emitRate, foe.emitCap(emitRate));
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = 0.4 * self.scale;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + (0.5 + self.lift) * self.scale, self.pos.z + mathx.sinf(a) * rr),
                v3(0, self.fxRng.range(0.1, 0.4), 0),
                self.fxRng.range(0.3, 0.6),
                self.fxRng.range(0.03, 0.06),
                0.10,
                SPORE,
                1.2,
            );
        }
    }
    fn emitTrail(self: *Shroom, dt: f32) void {
        const emitRate = 26.0;
        var owed = foe.emitTicks(&self.fxAccum, dt, emitRate, foe.emitCap(emitRate));
        while (owed > 0) : (owed -= 1) {
            const c = self.centerWorld();
            self.emit(c, v3(self.fxRng.signed() * 0.4, self.fxRng.range(-0.2, 0.4), self.fxRng.signed() * 0.4), self.fxRng.range(0.3, 0.55), 0.06, 0.14, SPORE, 0.8);
        }
    }
    pub fn drawFx(self: *const Shroom) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Shroom, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Shroom) void {
        const fs = self.scale * (1.0 - 0.55 * self.fade);
        // SQUASH AND STRETCH, conserving the toy's volume: sy down, sx out.
        const sy = self.squash;
        const sxz = 1.0 / @sqrt(mathx.maxF(0.5, sy));
        const root = mul3(
            mul(scaleM(sxz * fs, sy * fs, sxz * fs), rx(self.pitch)),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y + self.lift, self.pos.z),
        );
        self.xf[BODY] = root;
        // The cap arrives LATE (capLag) and counter-tips: the wobble is the whole toy read. The lag is
        // against the body's own pitch, so a faceplant sends the cap nodding past it and back.
        const capTip = self.capLagX - self.pitch * 0.5;
        const wob = 2.4 * mathx.sinf(self.elapsed * (2.1 + 0.5 * self.seed) + self.seed * 12.0);
        self.xf[CAP] = mul(mul3(rz(wob), rx(capTip), tr(REST[CAP].x, REST[CAP].y, REST[CAP].z)), root);
        // Feet: tiny, paddling when airborne or upended.
        const kickA = 34.0 * self.kick;
        self.xf[FOOTL] = mul(mul(rx(kickA), tr(REST[FOOTL].x, REST[FOOTL].y, REST[FOOTL].z)), root);
        self.xf[FOOTR] = mul(mul(rx(-kickA), tr(REST[FOOTR].x, REST[FOOTR].y, REST[FOOTR].z)), root);
        // Arms: hanging nubs at rest, flung WIDE in flight and in the sprawl.
        const spread = lerpF(12.0, 84.0, mathx.clampF(self.armUp, 0, 1));
        self.xf[ARML] = mul(mul(rz(-spread), tr(REST[ARML].x, REST[ARML].y, REST[ARML].z)), root);
        self.xf[ARMR] = mul(mul(rz(spread), tr(REST[ARMR].x, REST[ARMR].y, REST[ARMR].z)), root);
    }
};


/// The cloud's own ring: peak emission `CLOUD_RATE + CLOUD_RATE_FRESH` against lives up to `CLOUD_PUFF_MAX`,
/// rounded up — at anything under that the ring quietly eats its own spores mid-hang and the cloud thins in
/// the middle of its life instead of at the end of it. Arithmetic, and asserted, never a round number.
const CLOUD_RATE: f32 = 38.0;
const CLOUD_RATE_FRESH: f32 = 26.0;
const CLOUD_PUFF_MIN: f32 = 1.1;
const CLOUD_PUFF_MAX: f32 = 1.7;
const CLOUD_PARTS = 112;
// **WHAT THE CLOUDS COST, MEASURED** (`necro.drawSigil`'s note, one creature along). A live cloud is up to
// `CLOUD_PARTS` spheres at 6x8 through `foe.drawParticles`, so the field's worst case is `CLOUD_CAP` of them
// at once — about 900 spheres, ~86k CPU-transformed triangles. Tripled from the old 36 to buy a hazard you
// can actually see, and bounded by two things: a slot draws nothing unless something emitted into it, and
// eight concurrent clouds needs eight flings inside one `CLOUD_LIFE` against a `FLING_CD` of 4.6 s — which
// is more sporelings than a cluster fields. Two or three clouds is the real number, and that is where it
// was before. Left alone deliberately: the resolution is `drawParticles`' and shared with every effect in
// the game, so trimming it here would be trimming it everywhere.
comptime {
    std.debug.assert(@as(f32, @floatFromInt(CLOUD_PARTS)) >= (CLOUD_RATE + CLOUD_RATE_FRESH) * CLOUD_PUFF_MAX);
}

pub const Cloud = struct {
    pos: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    live: bool = false,
    parts: [CLOUD_PARTS]foe.Particle = [_]foe.Particle{.{}} ** CLOUD_PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    /// Which puff this is over the cloud's WHOLE LIFE, and it has to be that rather than an index within the
    /// frame: the emitter lays about one puff a frame at 60, so a per-frame counter never reached the third
    /// and the boundary was drawn only on a frame long enough to emit three at once — which is to say never,
    /// and worse, never in a way that looked like a tuning problem.
    rimTick: u32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x0C10),

    pub fn radius(self: *const Cloud) f32 {
        const grow = mathx.smoothstep(0, CLOUD_GROW, self.t);
        const fade = 1.0 - mathx.smoothstep(CLOUD_LIFE - 0.6, CLOUD_LIFE, self.t);
        return CLOUD_R * grow * (0.55 + 0.45 * fade);
    }
    pub fn covers(self: *const Cloud, p: rl.Vector3) bool {
        return self.live and self.t < CLOUD_LIFE and mathx.distXZ(self.pos, p) <= self.radius();
    }
    pub fn update(self: *Cloud, dt: f32) void {
        // BEFORE the live gate (`brood.Pool.update`'s rule): a puff laid on the cloud's last frame still has
        // up to `CLOUD_PUFF_MAX` to run, and a pool nobody ticks again is one frozen in the air until the
        // slot is reused.
        foe.tickParticles(&self.parts, dt, self.pos.y);
        if (!self.live) return;
        self.t += dt;
        if (self.t >= CLOUD_LIFE) {
            self.live = false;
            return;
        }
        // A slow ochre bloom — dense at the middle, violet flecks through it, barely any lift: spores
        // HANG, and the hang is what says "do not stand in this".
        //
        // **IT HAS TO BE A VOLUME, AND IT HAS TO HAVE AN EDGE** (owner's call). Thirty-odd puffs over a 1.9 m
        // disc was a handful of translucent blobs beside a mushroom — a hazard you walk into because there is
        // nothing there to not walk into. Two things fix it and neither is "more of the same":
        //   1. **HEIGHT.** Spores to a metre and a half, which is his own chest: a knee-high haze is something
        //      you step over, and this is something you are IN.
        //   2. **A RIM.** One puff in three is laid on the boundary rather than spread through the disc, so
        //      the cloud says where it STOPS. A gradient has no line to be on the safe side of.
        const emitRate = (CLOUD_RATE + CLOUD_RATE_FRESH * (1.0 - self.t / CLOUD_LIFE));
        var owed = foe.emitTicks(&self.fxAccum, dt, emitRate, foe.emitCap(emitRate));
        while (owed > 0) : (owed -= 1) {
            self.rimTick +%= 1;
            const a = self.fxRng.angle();
            const rim = self.rimTick % 3 == 0;
            // The rim rides the LIVE radius, so a cloud still growing has its edge in the right place every
            // frame rather than laying a boundary where it is going to be.
            const rr = if (rim) self.radius() * self.fxRng.range(0.88, 1.0) else self.fxRng.float() * self.radius() * 0.86;
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + self.fxRng.range(0.08, 1.45), self.pos.z + mathx.sinf(a) * rr),
                v3(self.fxRng.signed() * 0.15, self.fxRng.range(0.05, 0.3), self.fxRng.signed() * 0.15),
                self.fxRng.range(CLOUD_PUFF_MIN, CLOUD_PUFF_MAX),
                self.fxRng.range(0.13, 0.22),
                self.fxRng.range(0.26, 0.40),
                if (self.fxRng.float() < SPORE_VIO_SHARE) SPORE_VIO else SPORE,
                0.25,
            );
        }
    }
    pub fn drawFx(self: *const Cloud) void {
        // The gas cloud's own gate one creature along (`foe.motesVisible`): a spore cloud is the other big pool
        // of CPU-transformed spheres in the game, and a cluster of sporelings lays several of them.
        if (!foe.motesVisible(self.pos, self.radius() + CLOUD_PUFF_MAX)) return;
        foe.drawParticles(&self.parts);
    }
};


const CAP_N = wf.MAX_PER_KIND;

pub const Cluster = struct {
    model: Model,
    shrooms: [CAP_N]Shroom = undefined,
    n: usize = 0,
    clouds: [CLOUD_CAP]Cloud = [_]Cloud{.{}} ** CLOUD_CAP,
    cloudHead: usize = 0,

    pub fn init(shader: rl.Shader) Cluster {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Cluster) []Shroom {
        return self.shrooms[0..self.n];
    }
    pub fn liveConst(self: *const Cluster) []const Shroom {
        return self.shrooms[0..self.n];
    }
    pub fn reset(self: *Cluster, m: *const wf.Map) void {
        self.clearClouds();
        foe.resetGroup(Shroom, &self.shrooms, &self.n, m, .shroom);
    }
    /// EMPTY THE FIELD — the MEMBERS as well as the clouds. `game.clearFoes` calls this INSTEAD of zeroing
    /// `n`, so a `clear` that only swept the extras left every sporeling standing at a bonfire and in `--shot`.
    pub fn clear(self: *Cluster) void {
        self.n = 0;
        self.clearClouds();
    }
    /// …and the clouds alone, which is what a re-home wants (the brood's `clearSacs`).
    fn clearClouds(self: *Cluster) void {
        for (&self.clouds) |*c| c.* = .{};
        self.cloudHead = 0;
    }
    pub fn setShader(self: *Cluster, sh: rl.Shader) void {
        self.model.setShader(sh);
    }

    fn spawnCloud(self: *Cluster, at: rl.Vector3) void {
        self.clouds[self.cloudHead] = .{ .pos = at, .live = true, .fxRng = foe.fxStream(at.x + at.z, 977.0, 0xC10D) };
        self.cloudHead = (self.cloudHead + 1) % CLOUD_CAP;
    }

    pub fn update(self: *Cluster, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*s| {
            switch (s.update(dt, s.threat.aim(hero), bounds, blade)) {
                .none => {},
                .burst => |b| {
                    self.spawnCloud(b.at);
                    if (b.hit) |h| foe.worseBlow(&blow, h, s.pos, s.threat.on);
                },
            }
        }
        for (&self.clouds) |*c| c.update(dt);
        return blow;
    }

    /// THE SPORE DOSE: how much POISON BUILDUP standing in the cloud is worth this frame, 0 outside it.
    pub fn spores(self: *const Cluster, dt: f32, hero: rl.Vector3) f32 {
        return if (self.fuming(hero)) SPORE_BUILD * dt else 0;
    }
    /// Is he in a cloud at all — the LEVEL beside `spores`' pulse. Nothing reads it yet: it is what a tint or
    /// a hiss would ride, and neither exists, so do not take it for a wired-up cue.
    pub fn fuming(self: *const Cluster, hero: rl.Vector3) bool {
        for (&self.clouds) |*c| {
            if (c.covers(hero)) return true;
        }
        return false;
    }

    pub fn draw(self: *const Cluster, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Cluster) void {
        for (self.liveConst()) |*s| s.drawFx();
        for (&self.clouds) |*c| c.drawFx();
    }
    pub fn pierce(self: *Cluster, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Cluster) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Cluster) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Cluster) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Cluster) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[BODY] = bodyMesh();
    mesh[CAP] = capMesh();
    mesh[FOOTL] = footMesh(1);
    mesh[FOOTR] = footMesh(-1);
    mesh[ARML] = armMesh(1);
    mesh[ARMR] = armMesh(-1);
    return mesh;
}

fn bodyMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.26 * H, 0), v3(0.27, 0.24 * H, 0.25), 8, 13, STALK); // the squat pear of a body
    b.addBlob(v3(0, 0.12 * H, 0.04), v3(0.24, 0.13 * H, 0.22), 7, 12, STALK); // its little belly
    b.addBlob(v3(0, 0.50 * H, 0), v3(0.22, 0.05 * H, 0.20), 5, 10, STALK_DK); // the skirt under the cap
    b.setMat(.plain);
    // NO EYES, NO BLUSHES (owner's call) — the whole face is one gaping mouth under the cap's shadow.
    b.addBlob(v3(0.01, 0.25 * H, 0.222), v3(0.105, 0.062, 0.032), 6, 11, MOUTH);
    return b.toMesh();
}

fn capMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B0C);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.05, 0.01), v3(0.46, 0.20, 0.44), 8, 14, CAP_COL); // the dome, a hair oblong
    b.addBlob(v3(0.03, 0.16, -0.02), v3(0.26, 0.12, 0.25), 6, 12, CAP_COL); // its crown lump, off-centre
    b.addBlob(v3(0, 0.0, 0.01), v3(0.42, 0.045, 0.40), 5, 12, CAP_DK); // the gills' shadow under the rim
    // The cream flecks, dealt — sunk most of the way in (relief is subtle), no two alike.
    var w: i32 = 0;
    while (w < 9) : (w += 1) {
        const a = rng.angle();
        const rr = rng.range(0.14, 0.40);
        const sz = rng.range(0.035, 0.075);
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.065 + 0.14 * (1.0 - rr / 0.46), mathx.sinf(a) * rr * 0.92),
            v3(sz, sz * 0.45, sz),
            4,
            8,
            WART,
        );
    }
    // …and one old BITE out of the rim: something tried this mushroom once and thought better of it.
    b.addBlob(v3(0.33, 0.045, -0.24), v3(0.09, 0.05, 0.08), 4, 8, CAP_DK);
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, -0.02), v3(side * 0.02, -0.01, 0.10), 0.05, 0.045, 7, STALK_DK); // a stub of a foot
    return b.toMesh();
}

fn armMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.11, -0.05, 0.02), 0.045, 0.038, 7, STALK); // a nub of an arm
    b.addBlob(v3(side * 0.12, -0.055, 0.02), v3(0.045, 0.04, 0.04), 4, 8, STALK_DK); // its mitten hand
    return b.toMesh();
}


test "the fling is only chosen where it can land, and rooted it can only tremble" {
    // The cannot-land law: a fling at nine metres travels five and pops its cloud on empty grass.
    try std.testing.expectEqual(Choice.fling, classify(FLING_MAX - 0.5, true, false));
    try std.testing.expectEqual(Choice.hop, classify(FLING_MAX + 0.5, true, false));
    try std.testing.expectEqual(Choice.hop, classify(4.0, false, false));
    try std.testing.expectEqual(Choice.wait, classify(1.0, false, false));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1.0, true, false));
    // Both its moves LEAVE THE EARTH, so the roots refuse the lot at the choose site (foe.canLeap).
    try std.testing.expectEqual(Choice.wait, classify(4.0, true, true));
    try std.testing.expect(GATHER_DUR >= foe.TELL_MIN);
}

test "SOMETIMES IT TRIPS: same gather, two endings — and a trip throws no cloud and no blow" {
    var flung: u32 = 0;
    var tripped: u32 = 0;
    var s: u32 = 0;
    while (s < 16) : (s += 1) {
        var m = Shroom.spawn(mathx.zero3, 0, 1.0, @as(f32, @floatFromInt(s)) * 0.41 + 0.05);
        const hero = v3(0, 0, 3.5);
        var sawCloud = false;
        var sawTrip = false;
        var fr: u32 = 0;
        while (fr < 60 * 5) : (fr += 1) {
            switch (m.update(1.0 / 60.0, hero, 400, .{})) {
                .burst => sawCloud = true,
                .none => {},
            }
            if (m.state == .trip) sawTrip = true;
            if (sawCloud or (sawTrip and m.state == .idle)) break;
        }
        if (sawTrip) {
            tripped += 1;
            try std.testing.expect(!sawCloud); // dirt, not spores
        } else if (sawCloud) flung += 1;
    }
    try std.testing.expect(flung > 0);
    try std.testing.expect(tripped > 0); // the roll is real on both sides
    // …and the pratfall is the LONGER opening — that is what it pays for the joke.
    try std.testing.expect(TRIP_FALL + TRIP_SPRAWL + TRIP_RISE > RECOVER_DUR);
}

test "the fling actually arrives: it closes on a hero in band and pops the cloud at its own feet" {
    var m = Shroom.spawn(mathx.zero3, 0, 1.0, 0.13); // seed 0.13: first roll is a fling (pinned by the expects below)
    m.debugFling(v3(0, 0, 4.0));
    var burst: ?rl.Vector3 = null;
    var fr: u32 = 0;
    while (fr < 60 * 3) : (fr += 1) {
        switch (m.update(1.0 / 60.0, v3(0, 0, 4.0), 400, .{})) {
            .burst => |b| {
                burst = b.at;
                break;
            },
            .none => {},
        }
    }
    try std.testing.expect(burst != null);
    // It lands where it aimed — on the hero, give or take the splat.
    try std.testing.expect(mathx.distXZ(burst.?, v3(0, 0, 4.0)) < 1.2);
    try std.testing.expect(mathx.distXZ(m.pos, mathx.zero3) > 2.5); // it really did throw itself
}

test "THE CLOUD POISONS, IT DOES NOT BURN: linger and the meter fills, step out and it decays" {
    var c = Cluster{ .model = undefined };
    c.spawnCloud(mathx.zero3);
    const inside = v3(0.4, 0, 0.2);
    const outside = v3(9, 0, 9);
    var psn = combat.Status{};
    var t: f32 = 0;
    // ONE cloud, stood in for its whole life, is most of a bar and NOT a proc: it is the warning.
    while (t < CLOUD_LIFE) : (t += 1.0 / 60.0) {
        for (&c.clouds) |*cl| cl.update(1.0 / 60.0);
        psn.add(c.spores(1.0 / 60.0, inside));
        _ = psn.tick(1.0 / 60.0, 70);
    }
    try std.testing.expect(psn.frac() > 0.5 and !psn.active());
    // Outside it, nothing is dosed at all…
    try std.testing.expectApproxEqAbs(@as(f32, 0), c.spores(1.0 / 60.0, outside), 1e-6);
    // …and a dead cloud doses nothing however long he stands in the spot it held.
    var k: u32 = 0;
    while (k < 60 * 5) : (k += 1) {
        for (&c.clouds) |*cl| cl.update(1.0 / 60.0);
    }
    try std.testing.expect(!c.fuming(inside));
    try std.testing.expectApproxEqAbs(@as(f32, 0), c.spores(1.0 / 60.0, inside), 1e-6);

    // …and TWO clouds back to back DO go off, which is what makes a pair of sporelings a real problem.
    var pair = Cluster{ .model = undefined };
    var p2 = combat.Status{};
    pair.spawnCloud(mathx.zero3);
    t = 0;
    while (t < CLOUD_LIFE * 2.0) : (t += 1.0 / 60.0) {
        if (t > CLOUD_LIFE - 0.5 and !pair.clouds[1].live) pair.spawnCloud(mathx.zero3);
        for (&pair.clouds) |*cl| cl.update(1.0 / 60.0);
        p2.add(pair.spores(1.0 / 60.0, inside));
        _ = p2.tick(1.0 / 60.0, 70);
    }
    try std.testing.expect(p2.active());
}

test "CLEAR EMPTIES THE FIELD — the members as well as the clouds" {
    // `game.clearFoes` calls a group's own `clear()` INSTEAD of zeroing `n`, so a `clear` that only swept
    // the extras left every sporeling standing at a bonfire and in every `--shot` that asked for a bare field.
    var c = Cluster{ .model = undefined };
    c.shrooms[0] = Shroom.spawn(mathx.zero3, 0, 1.0, 0.3);
    c.n = 1;
    c.spawnCloud(mathx.zero3);
    try std.testing.expect(c.fuming(mathx.zero3));
    c.clear();
    try std.testing.expectEqual(@as(usize, 0), c.n);
    try std.testing.expect(!c.fuming(mathx.zero3));
}

test "A DEAD CLOUD'S LAST PUFFS STILL GO OUT — `drawFx` does not ask whether the cloud is live" {
    var c = Cluster{ .model = undefined };
    c.spawnCloud(mathx.zero3);
    var t: f32 = 0;
    while (t < CLOUD_LIFE + 0.05) : (t += 1.0 / 60.0) {
        for (&c.clouds) |*cl| cl.update(1.0 / 60.0);
    }
    try std.testing.expect(!c.fuming(mathx.zero3)); // the hazard is over…
    // …and the motes laid on its last frame carry up to `CLOUD_PUFF_MAX` more. Gated behind `live` the pool
    // stopped being ticked here and hung in the air until something flung a cloud into the same slot.
    t = 0;
    while (t < CLOUD_PUFF_MAX + 0.05) : (t += 1.0 / 60.0) {
        for (&c.clouds) |*cl| cl.update(1.0 / 60.0);
    }
    for (&c.clouds) |*cl| {
        for (cl.parts) |p| try std.testing.expect(p.life <= 0);
    }
}

test "a wandered sporeling hops HOME, not at a hero forty metres off" {
    // The coil used to steer at the HERO while the launch re-aimed along facing — so a homing hop from
    // any range flew at him instead, and the little thing never got back to its patch.
    var m = Shroom.spawn(mathx.zero3, 0, 1.0, 0.3);
    m.pos = v3(6, 0, 0);
    var fr: u32 = 0;
    while (fr < 60 * 10) : (fr += 1) _ = m.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    try std.testing.expect(mathx.distXZ(m.pos, m.home) < HOME_R + 0.5);
}

test "hurt in the CLOUD's own coin: chaos barely touches it, fire is the answer" {
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    const chaosBolt = combat.Hit{ .elem = combat.elems(.{ .chaos = 24 }) };
    _ = v.hit(chaosBolt);
    try std.testing.expect(v.hp > HP_MAX - 8.0); // 75 resist: six chaos of twenty-four
    const fire = combat.Hit{ .dmg = 16, .elem = combat.elems(.{ .fire = 8 }) };
    var v2 = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var shots: u32 = 0;
    while (!v2.dead and shots < 9) : (shots += 1) _ = v2.hit(fire);
    try std.testing.expect(v2.dead); // two fire arrows short of a toad's bill
}
