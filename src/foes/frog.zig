const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;


const rx = mathx.rx;
const ry = mathx.ry;
const tr = mathx.tr;
const scaleM = mathx.scaleM;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const place = mathx.placeAt;

const HIDE = rgba(34, 38, 23, 255);
const HIDE_DK = rgba(20, 23, 14, 255);
const HIDE_LT = rgba(52, 55, 34, 255);
const BELLY = rgba(64, 62, 42, 255);
const SAC = rgba(80, 74, 48, 255);
const MAW = rgba(104, 34, 28, 255);
const TONGUE = rgba(126, 56, 48, 255);
const TOOTH = rgba(166, 156, 126, 255);
const TOOTH_DK = rgba(126, 116, 90, 255);
const EYE = rgba(252, 196, 84, 96);
const EYE_HOT = rgba(255, 62, 34, 62);
const PUPIL = rgba(10, 8, 6, 255);
const CLAW = rgba(28, 26, 20, 255);

const NP = 9;
const BODY = 0;
const LJAW = 1;
const THROAT = 2;
const HAUNCH_L = 3;
const SHANK_L = 4;
const HAUNCH_R = 5;
const SHANK_R = 6;
const ARM_L = 7;
const ARM_R = 8;

const P_JAW = v3(0, 0.24, 0.02);
const P_SAC = v3(0, 0.12, 0.24);
const P_HIP = v3(0.40, 0.24, -0.06);
const P_KNEE = v3(0.47, 0.46, 0.00);
const P_SHOULDER = v3(0.22, 0.26, 0.22);

const LOCK_AT = v3(0, 0.30, 0.06);
const BODY_CY = 0.34;
const HURT_R = 0.46;
const BODY_R = 0.55;

pub const SCALE = 1.4;

pub var AGGRO_R: f32 = 11.0;
const HOME_R = 2.2;
const LUNGE_R = 5.6;
const BITE_R = 1.45;
const HOP_REACH = 1.95;
const HOP_APEX = 0.62;
const LUNGE_APEX = 1.28;
const KEEP_OFF = BITE_R - 0.25;

const HOP_COIL = 0.16;
const HOP_FLIGHT = 0.40;
const HOP_LAND = 0.16;
const HOP_SETTLE_AGGRO = 0.07;
const LUNGE_COIL = 0.82;
const LUNGE_FLIGHT = 0.34;
const LUNGE_LAND = 0.12;
const RECOVER_DUR = 0.78;
const CHOMP_GAPE = 0.42;
const CHOMP_SNAP = 0.11;
const CHOMP_RECOVER = 0.42;
const CHOMP_JAW = 64.0;
const CHOMP_SAC = 1.95;
const LUNGE_CD = 2.1;
const CHOMP_CD = 0.7;
const TURN_RATE = 5.0;

const REST_EXT = 0.34;
const HIP_SWING = 66.0;
const KNEE_STRAIGHTEN = 104.0;
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 7.0;
const DISS_DUR = 0.95;
const DISSOLVE = foe.Dissolve{ .rate = 44.0, .spread = 0.55, .rise = 0.35 };

/// Sized by ARITHMETIC over the worst frame (the ring law): a KILLING HEAVY BLOW landing on the frame a lunge impacts. The lunge lays 32 dust; `tryHit` then fires the heavy spray (27), the death spray (21) and `foe.wounded`'s 3. That is 83, and a ring that overwrites its oldest does it SILENTLY.
const FX_MAX = 84;
const DUST = foe.DUST;
const EMBER = rgba(252, 196, 84, 150);
/// An ember is LIGHT, so it is drawn additive and it COOLS — amber down through this as it rises and dies.
const EMBER_COOL = rgba(214, 92, 26, 90);
const SPIT = rgba(176, 190, 150, 140);
const SPIT_DRY = rgba(120, 138, 104, 110);
const BLOOD = rgba(112, 22, 16, 235);
/// **THE FAN IS WHAT OPENS A WOUND, NOT THE THROW.** At 0.8 m/s of fan against 2.6 of throw every drop went the same way and five frames on it was still one blob (`shots/29b`); the parry's shower reads because its tangential spread is the BIGGER number. Drag pays for the speed — 3.6/s, so it dies down inside a body-length.
const BLOOD_SPRAY = foe.Spray{
    .fanLo = 0.6,  .fanHi = 3.8,
    .upLo = 0.8,   .upHi = 3.6,
    .lifeLo = 0.45, .lifeHi = 0.85,
    .rLo = 0.028,  .rHi = 0.055,
    .r1 = 0.008,   .col = BLOOD, .grav = foe.BLOOD_GRAV,
    .col1 = rgba(52, 9, 7, 225), .stretch = foe.BLOOD_STRETCH, .splat = 3.0, .drag = foe.BLOOD_DRAG,
};
const BLOOD_LIGHT = 9;
const BLOOD_HEAVY = 18;
const BLOOD_DEATH = 14;
const BLOOD_SPD_LIGHT = 4.6;
const BLOOD_SPD_HEAVY = 6.4;
const BLOOD_SPD_DEATH = 5.4;
comptime {
    // THE RING LAW, EXECUTABLE: the lunge's 32 dust with a killing heavy blow's two sprays and the shared wound on top. A count raised without the pool is a burst that silently eats its own oldest.
    std.debug.assert(FX_MAX >= 32 + foe.hitParts(BLOOD_HEAVY) + foe.hitParts(BLOOD_DEATH) + foe.WOUND_PARTS);
}

const HP_MAX = 46.0;
const POISE_MAX = 8.0;
const STANCE_MAX = 26.0;
const RESISTS = combat.resists(.{ .fire = 40, .cold = -30, .lightning = -25 });
const CHOMP_HIT = combat.Hit{ .dmg = 13, .poise = 15 };
pub var LUNGE_HIT = combat.Hit{ .dmg = 19, .poise = 26, .stance = 8 };
const PARRY_LEAD = foe.PARRY_LEAD;

const LUNGE_IMPACT_R = 1.9;
const LUNGE_FRONT_DOT = 0.25;
const LUNGE_IMPACT_FWD = 0.6; // dust-burst / impact-zone centre, this far ahead of the seat (pre-scale)
/// `BITE_R`/`LUNGE_IMPACT_R` are WORLD metres at the shipped `SCALE` — what `classify` measures a raw `distXZ` against. A HURT BOX is the creature's OWN metres (`foe.hurtReach`), so it is those divided back out, and that is what makes a re-scaled placement's reach track its body.
const BITE_OWN = BITE_R / SCALE;
const LUNGE_IMPACT_OWN = LUNGE_IMPACT_R / SCALE;
const TRAIL_RATE: f32 = 150.0;
const DEATH_DUR = 1.25;
pub var SOULS: u32 = 60;

const State = enum { idle, hop, lunge, recover, chomp, stunlight, stunheavy, dead };

/// Damage banked at one spot (`foe.Sense`) before it startles sideways — under a third of the bar, so one heavy chop or two pokes scatter it. The LUNGE still outranks it: a toad that can answer, answers.
const PANIC_AT = 0.28;

const Choice = enum { rest, hop, lunge, chomp, scatter, wait };
fn classify(dist: f32, lungeReady: bool, chompReady: bool, rooted: bool, pressed: bool) Choice {
    if (dist <= BITE_R) return if (chompReady) .chomp else .wait;
    if (rooted) return .wait;
    if (dist > AGGRO_R) return .rest;
    if (dist <= LUNGE_R and lungeReady) return .lunge;
    if (pressed) return .scatter;
    return .hop;
}

const Particle = foe.Particle;

pub const Model = struct {
    mesh: [NP]rl.Mesh,
    eyes: [2]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "frog");
        return .{ .mesh = buildMeshes(), .eyes = [2]rl.Mesh{ eyeMesh(EYE), eyeMesh(EYE_HOT) }, .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, xf: *const [NP]rl.Matrix, hot: bool) void {
        for (0..NP) |i| rl.drawMesh(self.mesh[i], self.mat, xf[i]);
        rl.drawMesh(self.eyes[@intFromBool(hot)], self.mat, xf[BODY]);
    }
};

pub const Frog = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    parry: foe.Parry = .{},
    parried: bool = false,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    idleWait: f32 = 0,
    lungeCd: f32 = 0,
    chompCd: f32 = 0,
    elapsed: f32 = 0,
    hopFrom: rl.Vector3 = mathx.zero3,
    hopTo: rl.Vector3 = mathx.zero3,
    hopAim: rl.Vector3 = mathx.zero3,
    hopReach: f32 = 0,
    launched: bool = false,
    hopApex: f32 = 0,
    hopDur: f32 = 0,
    isLunge: bool = false,

    sy: f32 = 1,
    sxz: f32 = 1,
    lift: f32 = 0,
    pitch: f32 = 0,
    legExt: f32 = REST_EXT,
    arm: f32 = 0,
    jaw: f32 = 0,
    sac: f32 = 1,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    heroLatch: bool = false,
    justDied: bool = false,
    /// WHO IT IS FIGHTING (`foe.Threat`) — embedded here and stamped by the game, `Leash`'s own law. The creature never asks what a spirit is; it is handed a target in the argument it calls `hero`.
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    sense: foe.Sense = .{},
    panicSide: f32 = 1,
    fade: f32 = 0,
    gone: bool = false,

    parts: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    /// Carried ONLY so its blood knows whether the ground under it is dry — a toad in the shallows moves and fights exactly as one on the bank.
    wade: foe.Wade = .{},

    xf: [NP]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Frog {
        var f = Frog{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        f.fxRng = foe.fxStream(seed, 104729.0, 1);
        f.panicSide = if (f.fxRng.float() < 0.5) 1 else -1;
        f.idleWait = 1.0 + seed * 2.0;
        f.resolveIdle();
        f.pose();
        return f;
    }

    pub fn centerWorld(self: *const Frog) rl.Vector3 {
        return foe.bodyPoint(self.pos, BODY_CY, self.scale, self.lift);
    }
    pub fn hurtRadius(self: *const Frog) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Frog) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Frog) rl.Vector3 {
        return foe.markOn(self.xf[BODY], LOCK_AT);
    }
    pub fn airborne(self: *const Frog) bool {
        return self.lift > foe.AIRBORNE_LIFT;
    }
    pub fn topWorld(self: *const Frog) rl.Vector3 {
        return foe.bodyPoint(self.pos, 0.80, self.scale, self.lift);
    }
    pub fn alive(self: *const Frog) bool {
        return !self.gone;
    }
    pub fn staggered(self: *const Frog) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn dying(self: *const Frog) bool {
        return self.state == .dead;
    }
    pub fn flashFrac(self: *const Frog) f32 {
        return foe.flashFrac(self.flash);
    }

    fn faceToward(self: *Frog, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    pub fn navWant(self: *const Frog, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        if (foe.postAim(self)) |go| return go;
        return if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
    }

    pub fn startHop(self: *Frog, to: rl.Vector3, bounds: f32, lunge: bool) void {
        self.hopAim = mathx.clampXZ(v3(to.x, 0, to.z), bounds);
        self.hopReach = mathx.distXZ(self.pos, self.hopAim);
        self.hopFrom = self.pos;
        self.hopTo = self.hopAim;
        self.launched = false;
        self.isLunge = lunge;
        self.hopApex = if (lunge) LUNGE_APEX else HOP_APEX;
        self.hopDur = if (lunge) LUNGE_FLIGHT else HOP_FLIGHT * mathx.clampF(0.5 + self.hopReach / HOP_REACH, 0.6, 1.5);
        self.state = if (lunge) .lunge else .hop;
        self.t = 0;
        self.heroLatch = false;
        sfx.world(if (lunge) .toad_lunge else .toad_hop, self.pos);
    }
    pub fn startChomp(self: *Frog) void {
        self.state = .chomp;
        self.t = 0;
        self.heroLatch = false;
        sfx.world(.toad_gape, self.pos);
    }
    fn enterStun(self: *Frog, s: State) void {
        self.state = s;
        self.t = 0;
        self.heroLatch = false;
    }

    /// SECONDS UNTIL THE SLAM LANDS, counted from the start of the leap so the coil and the arc are ONE continuous countdown. `tryImpact` fires the frame the toad touches down, so the window shuts there by construction: a caught leap is one that never arrived.
    fn toImpact(self: *const Frog) ?f32 {
        return switch (self.state) {
            .lunge => (LUNGE_COIL + self.hopDur) - self.t,
            .idle, .hop, .recover, .chomp, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Frog) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(LUNGE_IMPACT_OWN, self.scale);
    }

    /// THE BOARDS TAKE THE LEAP. `enterStun` is what kills it: the `.lunge` state is gone, so `updateHop` never reaches its landing and `tryImpact` never fires. The toad COMES STRAIGHT DOWN — both stun resolvers write `lift` from scratch.
    fn takeParry(self: *Frog) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.lungeCd = LUNGE_CD;
        self.dustBurst(self.pos, 14, 2.2, 0.20);
        sfx.world(.toad_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }
    fn enterDeath(self: *Frog) void {
        self.state = .dead;
        self.t = 0;
        self.heroLatch = false;
        self.justDied = true;
    }
    pub fn stagger(self: *Frog, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Frog) void {
        self.enterDeath();
    }
    fn tryBite(self: *Frog, hero: rl.Vector3, range: f32, h: combat.Hit) void {
        if (self.heroLatch) return;
        if (mathx.distXZ(self.pos, hero) <= foe.hurtReach(range, self.scale)) {
            self.heroHit = h;
            self.heroLatch = true;
            self.leash.noteCombat();
        }
    }
    fn tryImpact(self: *Frog, hero: rl.Vector3, h: combat.Hit) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(LUNGE_IMPACT_OWN, self.scale), LUNGE_FRONT_DOT)) return;
        self.heroHit = h;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    pub fn update(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            self.updateFx(dt);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.lungeCd = mathx.maxF(0, self.lungeCd - dt);
        self.chompCd = mathx.maxF(0, self.chompCd - dt);
        foe.fadeFlash(&self.flash, dt);
        self.t += dt;
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        const bearing = mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(self.pos, hero)) - self.facing);
        self.sense.tick(dt, self.pos, bearing, self.bodyR(), switch (self.state) {
            .hop, .lunge => false,
            else => true,
        });
        self.updateFx(dt);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        self.takeParry();

        switch (self.state) {
            .idle => self.updateIdle(dt, hero, bounds),
            .hop => self.updateHop(dt, hero, bounds, HOP_COIL, self.hopDur, HOP_LAND),
            .lunge => self.updateHop(dt, hero, bounds, LUNGE_COIL, self.hopDur, LUNGE_LAND),
            .recover => {
                self.resolveRecover();
                if (self.t >= RECOVER_DUR) self.enterIdle(0.02);
            },
            .chomp => self.updateChomp(dt, hero),
            .stunlight => {
                self.resolveStunLight();
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle(0.02);
            },
            .stunheavy => {
                self.resolveStunHeavy();
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle(0.06);
            },
            .dead => {
                self.resolveDeath();
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn enterIdle(self: *Frog, wait: f32) void {
        self.state = .idle;
        self.t = 0;
        self.idleWait = wait;
    }

    fn decide(self: *Frog, hero: rl.Vector3, bounds: f32) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        switch (classify(d, self.lungeCd <= 0, self.chompCd <= 0, !foe.canLeap(&self.root), self.sense.pressed(HP_MAX, PANIC_AT))) {
            .chomp => {
                self.chompCd = CHOMP_CD;
                self.startChomp();
            },
            .lunge => {
                self.lungeCd = LUNGE_CD;
                const dir = mathx.dirXZ(self.pos, hero);
                const reach = mathx.minF(mathx.maxF(0, d - KEEP_OFF), LUNGE_R);
                self.startHop(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds, true);
            },
            .hop => {
                const dir = self.nav.along(mathx.dirXZ(self.pos, hero));
                const reach = mathx.minF(HOP_REACH, mathx.maxF(0, d - KEEP_OFF));
                self.startHop(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds, false);
            },
            // THE STARTLE: punished where it sits, it scatters a full hop SIDEWAYS off the line — one panic hop clears `Sense`'s own span, so it startles once and then answers. The side alternates.
            .scatter => {
                const to = mathx.dirXZ(self.pos, hero);
                const dir = self.nav.along(v3(to.z * self.panicSide, 0, -to.x * self.panicSide));
                self.panicSide = -self.panicSide;
                self.startHop(v3(self.pos.x + dir.x * HOP_REACH, 0, self.pos.z + dir.z * HOP_REACH), bounds, false);
            },
            .wait => self.enterIdle(0.12),
            .rest => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) {
                    const dir = self.nav.along(mathx.dirXZ(self.pos, self.home));
                    self.startHop(v3(self.pos.x + dir.x * HOP_REACH, 0, self.pos.z + dir.z * HOP_REACH), bounds, false);
                } else self.enterIdle(1.4 + self.seed * 2.2);
            },
        }
    }

    fn updateIdle(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= AGGRO_R) self.faceToward(hero, dt);
        self.resolveIdle();
        const wait = if (d <= AGGRO_R) mathx.minF(self.idleWait, 0.16) else self.idleWait;
        if (self.t < wait) return;
        // **IT WALKS ITS ORDERS THE ONLY WAY IT MOVES — IN HOPS** (`foe.postWant`). One leap toward the place
        // its round is pointing at, capped at its own reach, so a round reads as a frog and not as a glide.
        if (foe.postWant(self, dt, d, AGGRO_R)) |go| {
            const dir = self.nav.along(mathx.dirXZ(self.pos, go));
            const reach = mathx.minF(HOP_REACH, mathx.distXZ(self.pos, go));
            if (reach > 0.2) {
                self.startHop(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds, false);
                return;
            }
        }
        self.decide(hero, bounds);
    }

    fn updateHop(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32, coil: f32, flight: f32, land: f32) void {
        const total = coil + flight + land;
        if (self.t < coil) {
            // EVERY hop faces its own AIM: `hopStep` launches along the FACING, so a coil that eyed the hero instead re-bent the hop at the launch — undoing the nav bend and curving a homeward hop back toward him.
            self.faceToward(self.hopAim, dt);
            const k = mathx.smoothstep(0, coil, self.t);
            self.resolveCoil(k, self.isLunge);
            if (self.isLunge) self.emitCoil(dt, k);
        } else if (self.t < coil + flight) {
            const s = foe.hopStep(self, dt, bounds, self.fdir(), coil, flight);
            self.resolveFlight(s);
            if (self.isLunge) self.emitLungeTrail(dt, s);
        } else {
            const k = mathx.smoothstep(0, land, self.t - coil - flight);
            self.resolveLand(k);
            if ((self.t - dt) < coil + flight) {
                if (self.isLunge) self.dustBurst(self.impactWorld(), 32, 4.4, 0.30) else self.dustBurst(self.pos, 8, 1.8, 0.16);
                if (self.isLunge) self.tryImpact(hero, LUNGE_HIT);
            }
        }
        mathx.holdXZ(&self.pos, bounds);
        if (self.t >= total) {
            if (self.isLunge) {
                self.state = .recover;
                self.t = 0;
            } else {
                self.enterIdle(HOP_SETTLE_AGGRO);
            }
        }
    }

    fn updateChomp(self: *Frog, dt: f32, hero: rl.Vector3) void {
        if (self.t < CHOMP_GAPE) {
            self.faceToward(hero, dt);
            const k = foe.swingCurve(self.t / CHOMP_GAPE);
            self.resolveGape(k);
            self.emitGape(dt, k);
        } else if (self.t < CHOMP_GAPE + CHOMP_SNAP) {
            if ((self.t - dt) < CHOMP_GAPE) {
                self.spitSpray();
                sfx.world(.toad_chomp, self.pos);
            }
            self.resolveSnap((self.t - CHOMP_GAPE) / CHOMP_SNAP);
            self.tryBite(hero, BITE_OWN, CHOMP_HIT);
        } else {
            self.resolveChompRecover(mathx.smoothstep(0, CHOMP_RECOVER, self.t - CHOMP_GAPE - CHOMP_SNAP));
            if (self.t >= CHOMP_GAPE + CHOMP_SNAP + CHOMP_RECOVER) self.enterIdle(0.1);
        }
    }

    fn base(self: *Frog) void {
        self.sy = 1;
        self.sxz = 1;
        self.lift = 0;
        self.pitch = 0;
        self.legExt = REST_EXT;
        self.arm = 0;
        self.jaw = 0;
        self.sac = 1;
    }
    fn resolveIdle(self: *Frog) void {
        self.base();
        const br = mathx.sinf(self.elapsed * 1.8 + self.seed * 6.28);
        self.sy = 1.0 + 0.03 * br;
        self.sxz = 1.0 - 0.02 * br;
        self.sac = 1.0 + 0.06 * mathx.sinf(self.elapsed * 2.3 + self.seed * 3.0);
        self.jaw = 1.5 + 1.5 * mathx.maxF(0, br);
        // …and every ~17 s a GULP — the throat balloons and the jaw works once. A discrete event on a slow clock incommensurate with the breath, which is what stops the idle reading as a loop.
        const gulp = mathx.smoothstep(0.90, 0.995, mathx.sinf(self.elapsed * 0.37 + self.seed * 9.1));
        self.sac += 0.55 * gulp;
        self.jaw += 7.0 * gulp;
        self.sy -= 0.03 * gulp;
    }
    fn resolveCoil(self: *Frog, k: f32, lunge: bool) void {
        self.base();
        const deep: f32 = if (lunge) 1.75 else 1.0;
        self.sy = 1.0 - 0.30 * k * deep;
        self.sxz = 1.0 + 0.18 * k * deep;
        self.legExt = mathx.lerpF(REST_EXT, 0.05, k);
        self.pitch = -6.0 * k * deep;
        self.arm = 0.15 * k;
        const sacGain: f32 = if (lunge) 0.28 else 0.10;
        self.sac = 1.0 + sacGain * k;
        self.jaw = if (lunge) 12.0 * k else 0.0;
    }
    fn resolveFlight(self: *Frog, s: f32) void {
        self.lift = self.hopApex * 4.0 * s * (1.0 - s); // parabola, peak at s=0.5
        const launch = 1.0 - mathx.smoothstep(0.0, 0.32, s);
        const preland = mathx.smoothstep(0.72, 1.0, s);
        self.legExt = mathx.clampF(1.0 - 0.35 * preland, 0.0, 1.0);
        self.sy = 1.0 + 0.20 * launch - 0.10 * preland;
        self.sxz = 1.0 - 0.12 * launch + 0.06 * preland;
        self.pitch = mathx.lerpF(-14.0, 16.0, s);
        self.arm = mathx.smoothstep(0.55, 1.0, s);
        self.jaw = 2.0;
        self.sac = 1.0;
    }
    fn resolveLand(self: *Frog, k: f32) void {
        const splat = mathx.pulse(k, 0, 0.45, 0.45, 1.0);
        // A mass in motion OVERSHOOTS its rest: the squash rebounds PAST 1 and settles back onto it. The rebound peaks at 0.92, where the splat has decayed to nothing — earlier and the two cancel out.
        const reb = mathx.pulse(k, 0.72, 0.92, 0.92, 1.0);
        self.lift = 0;
        self.sy = 1.0 - 0.26 * splat + 0.08 * reb;
        self.sxz = 1.0 + 0.16 * splat - 0.055 * reb;
        self.legExt = mathx.lerpF(0.2, REST_EXT, k);
        self.arm = 1.0 - k;
        self.pitch = 8.0 * (1.0 - k);
        self.jaw = 2.0;
        self.sac = 1.0;
    }
    fn resolveRecover(self: *Frog) void {
        const u = mathx.clampF(self.t / RECOVER_DUR, 0, 1);
        const out = 1.0 - mathx.smoothstep(0.7, 1.0, u);
        const pant = mathx.sinf(self.elapsed * 9.0);
        self.lift = 0;
        self.sy = mathx.lerpF(1.0, 0.80, out);
        self.sxz = mathx.lerpF(1.0, 1.14, out);
        self.legExt = mathx.lerpF(REST_EXT, 0.12, out);
        self.pitch = 7.0 * out;
        self.arm = 0.5 * out;
        self.jaw = 8.0 * out + 3.0 * pant * out;
        self.sac = 1.0 + (0.18 + 0.10 * pant) * out;
    }
    fn resolveGape(self: *Frog, k: f32) void {
        self.base();
        self.sy = 1.0 - 0.06 * k;
        self.sxz = 1.0 + 0.05 * k;
        self.pitch = -13.0 * k;
        self.jaw = CHOMP_JAW * k;
        self.sac = 1.0 + (CHOMP_SAC - 1.0) * k;
        self.legExt = mathx.lerpF(REST_EXT, 0.22, k);
        self.arm = 0.2 * k;
    }
    fn resolveSnap(self: *Frog, s: f32) void {
        self.jaw = mathx.lerpF(CHOMP_JAW, 0.0, mathx.smoothstep(0, 0.55, s));
        self.pitch = mathx.lerpF(-13.0, 14.0, s);
        self.sac = mathx.lerpF(CHOMP_SAC, 0.9, s);
        self.sy = 1.0 + 0.05 * s;
        self.sxz = 1.0 - 0.03 * s;
        self.lift = 0;
        self.legExt = 0.30;
        self.arm = 0.2;
    }
    fn resolveChompRecover(self: *Frog, k: f32) void {
        const rc = mathx.sinf(k * std.math.pi) * (1.0 - k);
        self.sy = 1.0 - 0.03 * rc;
        self.sxz = 1.0 + 0.02 * rc;
        self.lift = 0;
        self.pitch = mathx.lerpF(12.0, 0.0, k);
        self.jaw = 3.0 * (1.0 - k);
        self.sac = mathx.lerpF(0.9, 1.0, k);
        self.legExt = mathx.lerpF(0.30, REST_EXT, k);
        self.arm = 0.2 * (1.0 - k);
    }

    fn resolveStunLight(self: *Frog) void {
        self.base();
        const u = mathx.clampF(self.t / combat.FOE_LIGHT_STUN_DUR, 0, 1);
        const j = mathx.sinf(u * std.math.pi);
        self.pitch = -30.0 * j;
        self.sy = 1.0 - 0.22 * j;
        self.sxz = 1.0 + 0.15 * j;
        self.jaw = 30.0 * j;
        self.legExt = mathx.lerpF(REST_EXT, 0.66, j);
        self.lift = 0.16 * j;
        self.sac = 1.0 + 0.14 * j;
    }
    fn resolveStunHeavy(self: *Frog) void {
        self.base();
        const u = mathx.clampF(self.t / combat.FOE_HEAVY_STUN_DUR, 0, 1);
        const down = mathx.pulse(u, 0, 0.16, 0.74, 1.0);
        const reel = mathx.sinf(self.elapsed * 8.0);
        self.lift = 0;
        self.sy = mathx.lerpF(1.0, 0.56, down);
        self.sxz = mathx.lerpF(1.0, 1.32, down);
        self.legExt = mathx.lerpF(REST_EXT, 0.05, down);
        self.pitch = 13.0 * down;
        self.jaw = 20.0 * down + 4.0 * reel * down;
        self.sac = 1.0 + 0.22 * down;
        self.arm = 0.7 * down;
    }
    fn resolveDeath(self: *Frog) void {
        self.base();
        const k = mathx.smoothstep(0, 0.4, mathx.clampF(self.t / DEATH_DUR, 0, 1));
        self.lift = 0;
        self.sy = mathx.lerpF(1.0, 0.30, k);
        self.sxz = mathx.lerpF(1.0, 1.40, k);
        self.legExt = mathx.lerpF(REST_EXT, 0.02, k);
        self.pitch = 15.0 * k;
        self.jaw = 15.0 * k;
        self.sac = mathx.lerpF(1.0, 0.85, k);
    }

    pub fn tryHit(self: *Frog, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        self.sense.hurt(blade.hit.dmg);
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 1.25, .heavy = 1.9 });
        self.bloodBurst(s.contact, s.dir, if (heavyBlow) BLOOD_HEAVY else BLOOD_LIGHT, if (heavyBlow) BLOOD_SPD_HEAVY else BLOOD_SPD_LIGHT);
        sfx.world(.toad_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.bloodBurst(s.contact, s.dir, BLOOD_DEATH, BLOOD_SPD_DEATH);
                sfx.world(.toad_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn emitLungeTrail(self: *Frog, dt: f32, s: f32) void {
        const c = self.centerWorld();
        const back = mathx.scaleV(self.fdir(), -1);
        const heavy = 1.0 - 0.55 * s;
        var owed = foe.emitDue(&self.fxAccum, dt, TRAIL_RATE * heavy);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const r = self.fxRng.range(0.05, 0.42) * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(c.x + mathx.cosf(a) * r, c.y + self.fxRng.signed() * 0.30 * self.scale, c.z + mathx.sinf(a) * r),
                .v = v3(back.x * self.fxRng.range(0.5, 2.2), self.fxRng.range(-0.1, 0.7), back.z * self.fxRng.range(0.5, 2.2)),
                .life = self.fxRng.range(0.26, 0.58),
                .r0 = self.fxRng.range(0.030, 0.075) * self.scale,
                .r1 = 0.004,
                .col = EMBER,
                .col1 = EMBER_COOL,
                .grav = -0.55,
                .stretch = 0.030,
                .add = true,
            });
        }
        if (self.fxRng.float() < dt * 44.0 * heavy) {
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.3, 0.62);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + self.fxRng.signed() * 0.3 * self.scale, self.pos.y + 0.05, self.pos.z + self.fxRng.signed() * 0.3 * self.scale),
                .v = v3(back.x * self.fxRng.range(1.0, 2.6) * B.boost, self.fxRng.range(0.5, 1.6) * B.boost, back.z * self.fxRng.range(1.0, 2.6) * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.05, 0.12) * self.scale,
                .r1 = 0.01,
                .col = foe.DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }

    fn bloodBurst(self: *Frog, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var s = BLOOD_SPRAY;
        if (!foe.onDryGround(self)) s.splat = 0;
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, s);
    }

    fn fdir(self: *const Frog) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn impactWorld(self: *const Frog) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x + d.x * LUNGE_IMPACT_FWD * self.scale, self.pos.y + 0.04, self.pos.z + d.z * LUNGE_IMPACT_FWD * self.scale);
    }
    fn mouthWorld(self: *const Frog) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x + d.x * 0.52 * self.scale, self.pos.y + 0.32 * self.scale + self.lift, self.pos.z + d.z * 0.52 * self.scale);
    }
    fn updateFx(self: *Frog, dt: f32) void {
        foe.tickParticles(&self.parts, dt, self.pos.y);
    }
    const PUFF = foe.Puff{
        .blast = foe.Blast.of(foe.DUST_DRAG, 0.35, 0.62),
        .spdLo = 0.5,
        .upLo = 0.6,
        .upHi = 2.2,
        .rLo = 0.06,
        .rHi = 0.12,
    };
    fn dustBurst(self: *Frog, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        foe.puff(&self.parts, &self.fxHead, &self.fxRng, v3(c.x, self.pos.y + 0.05, c.z), n, spd, big, self.scale, PUFF);
    }
    fn emitCoil(self: *Frog, dt: f32, k: f32) void {
        const emitRate = (12.0 + 40.0 * k);
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.18, 0.5) * self.scale;
            const bp = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.04, self.pos.z + mathx.sinf(a) * rr);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = bp,
                .v = v3(self.fxRng.signed() * 0.4, self.fxRng.range(0.5, 1.5), self.fxRng.signed() * 0.4),
                .life = self.fxRng.range(0.3, 0.5),
                .r0 = self.fxRng.range(0.05, 0.10) * self.scale,
                .r1 = self.fxRng.range(0.14, 0.24) * self.scale,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
            if (self.fxRng.float() < 0.6) {
                const m = self.mouthWorld();
                foe.emitPart(&self.parts, &self.fxHead, .{
                    .p = v3(m.x + self.fxRng.signed() * 0.22, m.y + self.fxRng.range(-0.08, 0.24), m.z + self.fxRng.signed() * 0.22),
                    .v = v3(self.fxRng.signed() * 0.22, self.fxRng.range(0.35, 0.95), self.fxRng.signed() * 0.22),
                    .life = self.fxRng.range(0.3, 0.55) + 0.4 * k,
                    .r0 = self.fxRng.range(0.03, 0.06) * self.scale,
                    .r1 = 0.004,
                    .col = EMBER,
                    .col1 = EMBER_COOL,
                    .grav = -0.6,
                    .add = true,
                });
            }
        }
    }
    fn emitGape(self: *Frog, dt: f32, k: f32) void {
        const emitRate = (10.0 + 30.0 * k);
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const m = self.mouthWorld();
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(m.x + self.fxRng.signed() * 0.22, m.y + self.fxRng.range(-0.05, 0.22), m.z + self.fxRng.signed() * 0.22),
                .v = v3(self.fxRng.signed() * 0.2, self.fxRng.range(0.3, 0.8), self.fxRng.signed() * 0.2),
                .life = self.fxRng.range(0.3, 0.55),
                .r0 = self.fxRng.range(0.03, 0.06) * self.scale,
                .r1 = 0.004,
                .col = EMBER,
                .col1 = EMBER_COOL,
                .grav = -0.5,
                .add = true,
            });
            if (self.fxRng.float() < 0.5) {
                const d = self.fdir();
                foe.emitPart(&self.parts, &self.fxHead, .{
                    .p = v3(m.x, m.y - 0.06, m.z),
                    .v = v3(d.x * 0.5 + self.fxRng.signed() * 0.2, -0.2, d.z * 0.5 + self.fxRng.signed() * 0.2),
                    .life = self.fxRng.range(0.35, 0.6),
                    .r0 = self.fxRng.range(0.03, 0.05) * self.scale,
                    .r1 = 0.015 * self.scale,
                    .col = SPIT,
                    .col1 = SPIT_DRY,
                    .grav = 5.0,
                });
            }
        }
    }
    fn spitSpray(self: *Frog) void {
        const m = self.mouthWorld();
        const d = self.fdir();
        var i: i32 = 0;
        while (i < 12) : (i += 1) {
            const spd = self.fxRng.range(1.6, 3.4);
            const vel = v3(d.x * spd + self.fxRng.signed() * 0.7, self.fxRng.range(0.2, 1.1), d.z * spd + self.fxRng.signed() * 0.7);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = m,
                .v = vel,
                .life = self.fxRng.range(0.32, 0.58),
                .r0 = self.fxRng.range(0.03, 0.05) * self.scale,
                .r1 = 0.012 * self.scale,
                .col = SPIT,
                .grav = 6.0,
                .stretch = 0.040,
                .splat = 2.6,
            });
        }
    }
    pub fn drawFx(self: *const Frog) void {
        foe.drawParticles(&self.parts);
    }

    pub fn pose(self: *Frog) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(0.30, self.scale, self.fade);
        const bframe = mul(
            scaleM(fs, fs, fs),
            mul3(rx(self.pitch), ry(mathx.degrees(self.facing)), tr(self.pos.x, self.pos.y + self.lift + sink, self.pos.z)),
        );
        const squash = scaleM(self.sxz, self.sy, self.sxz);

        var wx: [NP]rl.Matrix = undefined;
        wx[BODY] = mul(squash, bframe);
        wx[LJAW] = place(P_JAW, rx(self.jaw), wx[BODY]);
        wx[THROAT] = place(P_SAC, scaleM(self.sac, self.sac, self.sac), wx[BODY]);

        const hipDeg = (self.legExt - REST_EXT) * HIP_SWING;
        const kneeDeg = (self.legExt - REST_EXT) * KNEE_STRAIGHTEN;
        const kneeOff = v3(P_KNEE.x - P_HIP.x, P_KNEE.y - P_HIP.y, P_KNEE.z - P_HIP.z);
        wx[HAUNCH_L] = place(P_HIP, rx(-hipDeg), bframe);
        wx[SHANK_L] = place(kneeOff, rx(kneeDeg), wx[HAUNCH_L]);
        const hipR = v3(-P_HIP.x, P_HIP.y, P_HIP.z);
        const kneeOffR = v3(-kneeOff.x, kneeOff.y, kneeOff.z);
        wx[HAUNCH_R] = place(hipR, rx(-hipDeg), bframe);
        wx[SHANK_R] = place(kneeOffR, rx(kneeDeg), wx[HAUNCH_R]);

        const armDeg = -28.0 * self.arm;
        wx[ARM_L] = place(P_SHOULDER, rx(armDeg), bframe);
        wx[ARM_R] = place(v3(-P_SHOULDER.x, P_SHOULDER.y, P_SHOULDER.z), rx(armDeg), bframe);
        self.xf = wx;
    }

    pub fn eyesHot(self: *const Frog) bool {
        return self.state == .lunge;
    }

    pub fn draw(self: *const Frog, model: *const Model) void {
        model.draw(&self.xf, self.eyesHot());
    }
};

const CAP: usize = wf.MAX_PER_KIND;

pub const Knot = struct {
    model: Model,
    frogs: [CAP]Frog = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Knot {
        return .{ .model = Model.init(shader) };
    }
    pub fn reset(self: *Knot, m: *const wf.Map) void {
        foe.resetGroup(Frog, &self.frogs, &self.n, m, .toad);
    }
    pub fn live(self: *Knot) []Frog {
        return self.frogs[0..self.n];
    }
    pub fn liveConst(self: *const Knot) []const Frog {
        return self.frogs[0..self.n];
    }
    pub fn setShader(self: *Knot, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Knot, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    /// …and whether any of them was caught on it this frame. A ONE-FRAME edge, `anyDied`'s, read after `update`.
    pub fn anyParried(self: *const Knot) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn update(self: *Knot, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Knot, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Knot) void {
        for (self.liveConst()) |*f| f.drawFx();
    }
    pub fn pierce(self: *Knot, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Knot) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Knot) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Knot) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Knot) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildMeshes() [NP]rl.Mesh {
    var mesh: [NP]rl.Mesh = undefined;
    mesh[BODY] = bodyMesh();
    mesh[LJAW] = lowerJawMesh();
    mesh[THROAT] = throatMesh();
    mesh[HAUNCH_L] = thighMesh(1.0);
    mesh[SHANK_L] = shankMesh(1.0);
    mesh[HAUNCH_R] = thighMesh(-1.0);
    mesh[SHANK_R] = shankMesh(-1.0);
    mesh[ARM_L] = armMesh(1.0);
    mesh[ARM_R] = armMesh(-1.0);
    return mesh;
}

fn tooth(b: *Builder, bpos: rl.Vector3, dir: rl.Vector3, len: f32, r: f32, col: rl.Color) void {
    b.addCylinder(bpos, v3(bpos.x + dir.x * len, bpos.y + dir.y * len, bpos.z + dir.z * len), r, 0.004, 5, col);
}

const ToothRow = struct {
    seed: u64,
    tuskLen: f32,
    toothLen: f32,
    tuskRad: f32,
    toothRad: f32,
    dirY: f32,
    zlean: f32,
    z0: f32,
    zCurve: f32 = 0,
    shift: rl.Vector3 = mathx.zero3,
};
fn toothRow(b: *Builder, cfg: ToothRow) void {
    var trng = mathx.Rng.init(cfg.seed);
    var i: i32 = -4;
    while (i <= 4) : (i += 1) {
        if (trng.float() < 0.14) continue;
        const fx = @as(f32, @floatFromInt(i)) * 0.064 + trng.range(-0.016, 0.016);
        const tusk = @abs(i) >= 3 and trng.float() < 0.8;
        const broken = trng.float() < 0.15;
        const len = (if (tusk) cfg.tuskLen else cfg.toothLen) * (if (broken) trng.range(0.3, 0.5) else trng.range(0.72, 1.25));
        const rad = (if (tusk) cfg.tuskRad else cfg.toothRad) * trng.range(0.8, 1.2);
        const dir = v3(trng.range(-0.13, 0.13), cfg.dirY, cfg.zlean + trng.range(-0.05, 0.10));
        const y = 0.235 + trng.range(-0.008, 0.012);
        const z = cfg.z0 - cfg.zCurve * fx * fx;
        tooth(b, v3(fx - cfg.shift.x, y - cfg.shift.y, z - cfg.shift.z), dir, len, rad, if (trng.float() < 0.5) TOOTH else TOOTH_DK);
    }
}

fn eyeMesh(col: rl.Color) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.0 else 0.92;
        const ex = 0.19 * sgn;
        const cy = mathx.lerpF(0.525, 0.585, k);
        b.addBlob(v3(ex, cy, 0.34), v3(0.10 * k, 0.055 * k, 0.095 * k), 7, 12, col);
        b.addBlob(v3(ex, cy + 0.002, 0.34 + 0.095 * k - 0.008), v3(0.018, 0.038, 0.017), 5, 8, PUPIL);
    }
    return b.toMesh();
}

fn bodyMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4207);
    b.setMat(.hide);
    b.addBlob(v3(0, 0.26, -0.02), v3(0.42, 0.27, 0.45), 9, 15, HIDE);
    b.addBlob(v3(0.02, 0.43, -0.13), v3(0.29, 0.20, 0.29), 8, 13, HIDE);
    b.addBlob(v3(-0.03, 0.28, -0.36), v3(0.19, 0.15, 0.15), 7, 12, HIDE_DK);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.13, 0.10), v3(0.27, 0.13, 0.27), 8, 13, BELLY);
    b.setMat(.hide);

    // The head: one broad jowled mass jutting at the mouth line (~y0.24), never a slab.
    b.addBlob(v3(0, 0.345, 0.30), v3(0.33, 0.13, 0.22), 9, 15, HIDE);
    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.06 else 0.96;
        b.addBlob(v3(sgn * 0.215, 0.315, 0.34), v3(0.145 * k, 0.10 * k, 0.15 * k), 7, 12, HIDE);
    }
    b.addBlob(v3(0, 0.26, 0.44), v3(0.32, 0.05, 0.10), 8, 14, HIDE_DK);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.30, 0.30), v3(0.24, 0.035, 0.17), 6, 12, MAW);
    b.addBlob(v3(0, 0.25, 0.16), v3(0.21, 0.085, 0.10), 6, 11, MAW);
    b.setMat(.hide);

    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.0 else 0.92;
        const ex = 0.19 * sgn;
        b.addBlob(v3(ex, 0.45, 0.30), v3(0.135 * k, 0.075, 0.125), 7, 12, HIDE_DK);
        b.addBlob(v3(ex, mathx.lerpF(0.44, 0.50, k), 0.31), v3(0.125 * k, 0.115 * k, 0.115 * k), 8, 13, HIDE_LT);
        b.addBlob(v3(ex, mathx.lerpF(0.515, 0.575, k), 0.285), v3(0.115 * k, 0.055, 0.095 * k), 7, 12, HIDE_LT);
    }
    b.addBlob(v3(0.085, 0.395, 0.495), v3(0.023, 0.018, 0.023), 5, 8, HIDE_DK);
    b.addBlob(v3(-0.072, 0.402, 0.50), v3(0.019, 0.016, 0.020), 5, 8, HIDE_DK);

    toothRow(&b, .{ .seed = 9173, .tuskLen = 0.21, .toothLen = 0.13, .tuskRad = 0.046, .toothRad = 0.030, .dirY = -1, .zlean = 0.10, .z0 = 0.50, .zCurve = 0.55 });

    var w: i32 = 0;
    while (w < 17) : (w += 1) {
        const a = rng.angle();
        const h = rng.range(0.30, 0.50);
        const rr = mathx.lerpF(0.40, 0.16, (h - 0.28) / 0.32) - 0.02;
        const wx = mathx.cosf(a) * rr;
        const wz = -0.05 + mathx.sinf(a) * rr;
        const ws = rng.range(0.026, 0.050);
        b.addBlob(v3(wx, h, wz), v3(ws, ws * rng.range(0.45, 0.7), ws * rng.range(0.8, 1.25)), 5, 9, if (rng.float() < 0.5) HIDE_DK else HIDE_LT);
    }
    return b.toMesh();
}

fn lowerJawMesh() rl.Mesh {
    var b = Builder.init();
    const j = struct {
        fn at(bx: f32, by: f32, bz: f32) rl.Vector3 {
            return v3(bx - P_JAW.x, by - P_JAW.y, bz - P_JAW.z);
        }
    }.at;
    b.setMat(.hide);
    b.addBlob(j(0, 0.18, 0.26), v3(0.31, 0.055, 0.25), 8, 14, HIDE);
    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.05 else 0.95;
        b.addBlob(j(sgn * 0.20, 0.19, 0.18), v3(0.12 * k, 0.05, 0.16 * k), 6, 11, HIDE);
    }
    b.setMat(.skin);
    b.addBlob(j(0, 0.145, 0.26), v3(0.28, 0.05, 0.22), 7, 12, BELLY);
    b.addBlob(j(0, 0.225, 0.30), v3(0.24, 0.025, 0.16), 6, 12, TONGUE);
    b.addBlob(j(0, 0.235, 0.36), v3(0.10, 0.022, 0.09), 5, 9, TONGUE);
    b.setMat(.hide);
    b.addBlob(j(0, 0.235, 0.47), v3(0.30, 0.032, 0.062), 8, 14, HIDE_DK);
    toothRow(&b, .{ .seed = 6421, .tuskLen = 0.19, .toothLen = 0.115, .tuskRad = 0.042, .toothRad = 0.028, .dirY = 1, .zlean = 0.08, .z0 = 0.49, .zCurve = 0.55, .shift = P_JAW });
    return b.toMesh();
}

fn throatMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.025, 0.01), v3(0.24, 0.11, 0.20), 8, 13, SAC);
    b.addBlob(v3(0.015, -0.075, 0.07), v3(0.165, 0.065, 0.14), 7, 11, SAC);
    return b.toMesh();
}

fn thighMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xF60601 else 0xF60602);
    b.setMat(.hide);
    const knee = v3((P_KNEE.x - P_HIP.x) * side, P_KNEE.y - P_HIP.y, P_KNEE.z - P_HIP.z);
    b.addCapsule(v3(0, 0, 0), knee, 0.19, 0.125, 12, HIDE);
    const bulge = v3(knee.x * 0.42, knee.y * 0.42 + 0.02, knee.z * 0.42 - 0.03);
    b.addBlob(bulge, v3(0.215 * rng.range(0.95, 1.05), 0.185, 0.20 * rng.range(0.95, 1.06)), 8, 13, HIDE_LT);
    b.addBlob(knee, v3(0.135, 0.125, 0.13), 7, 12, HIDE);
    return b.toMesh();
}

fn shankMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x5A4E01 else 0x5A4E02);
    b.setMat(.hide);
    const foot = v3(-0.10 * side, 0.0 - P_KNEE.y, 0.16 - P_KNEE.z);
    b.addCapsule(v3(0, 0, 0), foot, 0.11, 0.05, 10, HIDE);
    const heel = foot;
    b.addBlob(v3(heel.x, heel.y + 0.015, heel.z + 0.05), v3(0.16, 0.028, 0.15), 6, 11, HIDE_DK);
    for ([_]f32{ -1, 0, 1 }) |t| {
        const tl = rng.range(0.17, 0.215);
        const toe = v3(heel.x + t * (0.115 + rng.range(-0.01, 0.015)), heel.y + 0.005, heel.z + tl);
        b.addCapsule(v3(heel.x + t * 0.05, heel.y + 0.02, heel.z + 0.05), toe, 0.030, 0.014, 6, HIDE_DK);
        b.addBlob(v3(toe.x, toe.y, toe.z + 0.015), v3(0.014, 0.011, 0.026), 4, 7, CLAW);
    }
    return b.toMesh();
}

fn armMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xA2601 else 0xA2602);
    b.setMat(.hide);
    const hand = v3(0.02 * side, -0.26, 0.16);
    b.addCapsule(v3(0, 0, 0), hand, 0.072, 0.043, 9, HIDE);
    b.addBlob(v3(hand.x, hand.y - 0.006, hand.z + 0.03), v3(0.105, 0.026, 0.10), 5, 9, HIDE_DK);
    for ([_]f32{ -1, 0, 1 }) |t| {
        const fl = rng.range(0.05, 0.075);
        b.addCapsule(v3(hand.x + t * 0.045, hand.y - 0.004, hand.z + 0.06), v3(hand.x + t * 0.055, hand.y - 0.008, hand.z + 0.06 + fl), 0.014, 0.008, 5, HIDE_DK);
        b.addBlob(v3(hand.x + t * 0.056, hand.y - 0.008, hand.z + 0.065 + fl), v3(0.010, 0.009, 0.016), 4, 7, CLAW);
    }
    return b.toMesh();
}


test "THE LEAP IS AN INSTANT FROM BEING SWATTED, and nothing else the toad does is catchable" {
    try std.testing.expect(PARRY_LEAD > 0);
    // An INSTANT, not a slice of the tell: its 0.70 s coil must not be catchable for a fifth of itself.
    try std.testing.expect(PARRY_LEAD < LUNGE_COIL * 0.25);
    try std.testing.expect(PARRY_LEAD < LUNGE_FLIGHT);

    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    f.startHop(mathx.ground(0, 4), 60.0, true);
    const impact = LUNGE_COIL + f.hopDur;
    // MEASURED off the state machine: walk the leap from the first frame of its coil and collect the span that is actually parryable. ONE clock here — coil, arc and landing are all `.lunge`.
    const step = 1.0 / 600.0;
    var open: f32 = -1;
    var shut: f32 = -1;
    var elapsed: f32 = 0;
    while (elapsed <= impact) : (elapsed += step) {
        f.t = elapsed;
        if (f.parryable() != null) {
            if (open < 0) open = elapsed;
            shut = elapsed;
        }
    }
    try std.testing.expect(open > 0);
    try std.testing.expectApproxEqAbs(impact, shut, 2.0 * step);
    try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);
    // …AT THE BODY'S OWN SCALE, not at 1.0: `foe.hurtReach`'s whole point is that a re-scaled placement's reach tracks its body, and pinned against the world-metre constant this passed only while SCALE was 1.
    try std.testing.expectApproxEqAbs(LUNGE_IMPACT_OWN * f.scale + foe.HERO_REACH, f.parryable().?, 1e-5);

    for ([_]State{ .idle, .hop, .recover, .chomp, .stunlight, .stunheavy, .dead }) |s| {
        f.state = s;
        f.t = 0;
        try std.testing.expect(f.parryable() == null);
        f.t = CHOMP_GAPE - PARRY_LEAD * 0.5;
        try std.testing.expect(f.parryable() == null);
    }
}

test "A CAUGHT LEAP NEVER ARRIVES, and the toad comes straight down out of the air" {
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const hero = v3(0, 0, 1.5);
    f.startHop(hero, 60.0, true);
    f.facing = 0;
    f.t = LUNGE_COIL + f.hopDur - PARRY_LEAD * 0.5;
    f.lift = 0.9;
    f.parry = .{ .live = true, .at = hero, .facing = 0 };
    f.takeParry();
    try std.testing.expect(!f.parried and f.state == .lunge);
    f.parry = .{ .live = true, .at = hero, .facing = std.math.pi };
    f.takeParry();
    try std.testing.expect(f.parried);
    try std.testing.expect(f.state == .stunlight or f.state == .stunheavy);
    try std.testing.expect(!f.heroLatch);
    try std.testing.expect(f.lungeCd > 0); // …and it cannot pounce straight back out of the sprawl
    _ = f.update(1.0 / 60.0, hero, 60.0, .{});
    try std.testing.expect(!f.airborne());
}

test "classify: ranges pick chomp < lunge < hop < rest, and cooldowns gate" {
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1, true, true, false, false));
    try std.testing.expectEqual(Choice.hop, classify((LUNGE_R + AGGRO_R) * 0.5, true, true, false, false));
    try std.testing.expectEqual(Choice.lunge, classify(LUNGE_R - 0.5, true, true, false, false));
    try std.testing.expectEqual(Choice.hop, classify(LUNGE_R - 0.5, false, true, false, false));
    try std.testing.expectEqual(Choice.chomp, classify(BITE_R - 0.2, true, true, false, false));
    try std.testing.expectEqual(Choice.wait, classify(BITE_R - 0.2, true, false, false, false));
}

test "ROOTED, A TOAD HAS ONLY ITS JAWS — every other move it owns leaves the ground" {
    try std.testing.expectEqual(Choice.wait, classify(LUNGE_R - 0.5, true, true, true, false));
    try std.testing.expectEqual(Choice.wait, classify((LUNGE_R + AGGRO_R) * 0.5, true, true, true, false));
    try std.testing.expectEqual(Choice.wait, classify(AGGRO_R + 1, true, true, true, false));
    try std.testing.expectEqual(Choice.chomp, classify(BITE_R - 0.2, true, true, true, false));
    try std.testing.expectEqual(Choice.wait, classify(LUNGE_R - 0.5, false, true, true, true));
}

test "THE STARTLE SCATTERS IT SIDEWAYS, AND ONLY WHEN IT CANNOT ANSWER — the lunge still outranks panic" {
    // Punished with the lunge ready, it lunges; punished with it cooling, it scatters instead of walking in.
    try std.testing.expectEqual(Choice.lunge, classify(LUNGE_R - 0.5, true, true, false, true));
    try std.testing.expectEqual(Choice.scatter, classify(LUNGE_R - 0.5, false, true, false, true));
    try std.testing.expectEqual(Choice.scatter, classify(AGGRO_R - 1.0, true, true, false, true));
    try std.testing.expectEqual(Choice.chomp, classify(BITE_R - 0.2, true, true, false, true));

    // …and the hop it takes is OFF THE LINE: bank a heavy blow's damage where it sits, let it decide, and measure the aim against the bearing to the hero.
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    f.leash.provoke();
    f.lungeCd = LUNGE_CD;
    f.sense.hurt(HP_MAX * PANIC_AT + 1.0);
    const hero = mathx.ground(0, 4.0);
    f.decide(hero, 200.0);
    try std.testing.expectEqual(State.hop, f.state);
    const aim = mathx.dirXZ(f.pos, f.hopAim);
    const to = mathx.dirXZ(f.pos, hero);
    try std.testing.expect(@abs(aim.x * to.x + aim.z * to.z) < 0.15);
    std.debug.print("\n  toad startle: banked {d:.0} dmg at the spot, hop aimed {d:.0} deg off the hero line\n", .{ HP_MAX * PANIC_AT + 1.0, mathx.degrees(std.math.acos(mathx.clampF(aim.x * to.x + aim.z * to.z, -1, 1))) });

    // One scatter clears the meter — the hop crosses its own pressure span, so it startles ONCE.
    try std.testing.expect(f.hopReach > f.bodyR());
}

test "THE LANDING REBOUNDS PAST REST AND SETTLES — the overshoot law on the squash" {
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    var lo: f32 = 99;
    var hi: f32 = 0;
    var k: f32 = 0;
    while (k <= 1.0) : (k += 0.02) {
        f.resolveLand(k);
        lo = mathx.minF(lo, f.sy);
        hi = mathx.maxF(hi, f.sy);
    }
    f.resolveLand(1.0);
    std.debug.print("\n  toad landing: squash bottoms at {d:.2}, rebounds to {d:.2}, ends at {d:.2}\n", .{ lo, hi, f.sy });
    try std.testing.expect(lo < 0.80);
    try std.testing.expect(hi > 1.02);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), f.sy, 0.01);
}

test "a held toad never leaves the earth, and pounces again the moment it is let go" {
    var f = Frog.spawn(mathx.zero3, 0, 1, 0.4);
    f.root.grab();
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD * 0.9) : (t += 1.0 / 60.0) {
        _ = f.update(1.0 / 60.0, v3(0, 0, LUNGE_R - 0.5), 500.0, .{});
        try std.testing.expect(!f.airborne());
        try std.testing.expect(f.lift <= 0.0001);
    }
    f.root.release();
    var left = false;
    t = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        _ = f.update(1.0 / 60.0, v3(0, 0, LUNGE_R - 0.5), 500.0, .{});
        if (f.airborne()) left = true;
    }
    try std.testing.expect(left);
}

test "range thresholds are ordered and inside senses" {
    try std.testing.expect(BITE_R < LUNGE_R and LUNGE_R < AGGRO_R);
    try std.testing.expect(KEEP_OFF < BITE_R);
}

test "lunge impact catches the front zone, not the sides or behind" {
    var front = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    front.tryImpact(v3(0, 0, 1.0), LUNGE_HIT);
    try std.testing.expect(front.heroHit != null);

    var behind = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.tryImpact(v3(0, 0, -1.0), LUNGE_HIT);
    try std.testing.expect(behind.heroHit == null);

    var beside = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    beside.tryImpact(v3(1.0, 0, 0), LUNGE_HIT);
    try std.testing.expect(beside.heroHit == null);

    var onTop = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    onTop.tryImpact(v3(0.1, 0, 0), LUNGE_HIT);
    try std.testing.expect(onTop.heroHit != null);

    var far = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.tryImpact(v3(0, 0, 99), LUNGE_HIT);
    try std.testing.expect(far.heroHit == null);
}

test "AN ARROW AGGROS IT FROM OUTSIDE ITS OWN SENSES, and it comes for him" {
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const hero = mathx.ground(0, AGGRO_R + 30);
    var k: u32 = 0;
    while (k < 120) : (k += 1) _ = f.update(1.0 / 60.0, hero, 200, .{});
    try std.testing.expect(!f.leash.roused());
    try std.testing.expect(mathx.distXZ(f.pos, hero) > AGGRO_R);
    try std.testing.expect(foe.sensedDist(&f.leash, mathx.distXZ(f.pos, hero), AGGRO_R) > AGGRO_R);

    const shaftAt = f.centerWorld();
    const blade = foe.Blade{
        .active = true,
        .pierce = true,
        .r = 0.4,
        .a = mathx.addV(shaftAt, mathx.v3(0, 0, 2)),
        .b = mathx.addV(shaftAt, mathx.v3(0, 0, -0.2)),
        .a0 = mathx.addV(shaftAt, mathx.v3(0, 0, 2)),
        .b0 = mathx.addV(shaftAt, mathx.v3(0, 0, -0.2)),
        .hit = .{ .dmg = 5, .poise = 1 },
    };
    const before = f.hits;
    f.tryHit(blade);
    try std.testing.expect(f.hits > before);
    try std.testing.expect(f.leash.roused());
    try std.testing.expect(foe.sensedDist(&f.leash, mathx.distXZ(f.pos, hero), AGGRO_R) <= AGGRO_R);
    try std.testing.expect(@abs(mathx.wrapPi(f.facing - mathx.headingXZ(mathx.v3(0, 0, 1)))) < 0.2);
    const startD = mathx.distXZ(f.pos, hero);
    k = 0;
    while (k < 240) : (k += 1) _ = f.update(1.0 / 60.0, hero, 200, .{});
    try std.testing.expect(f.leash.roused());
    try std.testing.expect(mathx.distXZ(f.pos, hero) < startD - 5.0);
}

test "a hop's flight parabola starts and ends on the ground and peaks at the apex" {
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    f.hopApex = HOP_APEX;
    f.resolveFlight(0.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.lift, 1e-5);
    f.resolveFlight(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.lift, 1e-5);
    f.resolveFlight(0.5);
    try std.testing.expectApproxEqAbs(HOP_APEX, f.lift, 1e-5);
}

test "NO ATTACK COMES OUT OF NOWHERE: the gape and the coil are both real tells" {
    try std.testing.expect(CHOMP_GAPE >= foe.TELL_MIN);
    try std.testing.expect(LUNGE_COIL >= foe.TELL_MIN);
    try std.testing.expect(LUNGE_COIL > CHOMP_GAPE);
}

test "THE WOUND OPENS: five frames on, the blood is a spray across the throw and not one blob" {
    var pool = [_]Particle{.{}} ** FX_MAX;
    const at = v3(0, 0.55, 0);
    const dir = v3(1, 0, 0);
    for ([_]struct { name: []const u8, n: i32, spd: f32 }{
        .{ .name = "light", .n = BLOOD_LIGHT, .spd = BLOOD_SPD_LIGHT },
        .{ .name = "heavy", .n = BLOOD_HEAVY, .spd = BLOOD_SPD_HEAVY },
    }) |b| {
        const m = foe.measureSpray(&pool, BLOOD_SPRAY, at, dir, b.n, b.spd, 1.0, 0xB10D, 5.0 / 60.0, 0);
        std.debug.print("\n  toad {s}: {d} motes, opens {d:.2} m across the throw, reaches {d:.2} m, {d} stains, all down by {d:.2} s\n", .{ b.name, m.motes, m.open, m.reach, m.splats, m.sink });
        try std.testing.expect(m.open > 0.38);
        try std.testing.expect(m.splats * 2 >= m.motes);
    }
}
