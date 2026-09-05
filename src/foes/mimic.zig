const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const village = @import("../props/propvillage.zig");
const chestmod = @import("../play/chest.zig");
const archermod = @import("archer.zig");

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
const approach = mathx.approach;

// THE RIG: a low bone body on four short legs, a neck of vertebrae, and the CHEST for a head with its lid for an upper jaw.
const ROOT = 0;
const HIP_FL = 1;
const KNEE_FL = 2;
const HIP_FR = 3;
const KNEE_FR = 4;
const HIP_BL = 5;
const KNEE_BL = 6;
const HIP_BR = 7;
const KNEE_BR = 8;
const NECK0 = 9;
const NECK1 = 10;
const NECK2 = 11;
const NECK3 = 12;
const HEAD = 13;
const LID = 14;
const FANGS = 15;
const LIDFANGS = 16;
const N = 17;

const PARENT = [N]i32{ -1, ROOT, HIP_FL, ROOT, HIP_FR, ROOT, HIP_BL, ROOT, HIP_BR, ROOT, NECK0, NECK1, NECK2, NECK3, HEAD, HEAD, LID };
const LEGS = [4]struct { hip: usize, knee: usize, side: f32, fore: f32 }{
    .{ .hip = HIP_FL, .knee = KNEE_FL, .side = 1.0, .fore = 1.0 },
    .{ .hip = HIP_FR, .knee = KNEE_FR, .side = -1.0, .fore = 1.0 },
    .{ .hip = HIP_BL, .knee = KNEE_BL, .side = 1.0, .fore = -1.0 },
    .{ .hip = HIP_BR, .knee = KNEE_BR, .side = -1.0, .fore = -1.0 },
};

const ROOT_Y: f32 = 0.56;
const LEG_X: f32 = 0.30;
const LEG_Z: f32 = 0.28;
const KNEE_Y: f32 = 0.25;
const SHIN: f32 = KNEE_Y;
const NECK_STEP: f32 = 0.32;
/// Where the chest's base sits off the last vertebra: the neck comes up UNDER it.
const HEAD_LIFT: f32 = 0.30;

const REST = blk: {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, ROOT_Y, 0);
    r[HIP_FL] = v3(LEG_X, ROOT_Y - 0.06, LEG_Z);
    r[KNEE_FL] = v3(LEG_X + 0.04, KNEE_Y, LEG_Z + 0.02);
    r[HIP_FR] = v3(-LEG_X, ROOT_Y - 0.06, LEG_Z);
    r[KNEE_FR] = v3(-LEG_X - 0.04, KNEE_Y, LEG_Z + 0.02);
    r[HIP_BL] = v3(LEG_X, ROOT_Y - 0.06, -LEG_Z);
    r[KNEE_BL] = v3(LEG_X + 0.04, KNEE_Y, -LEG_Z - 0.02);
    r[HIP_BR] = v3(-LEG_X, ROOT_Y - 0.06, -LEG_Z);
    r[KNEE_BR] = v3(-LEG_X - 0.04, KNEE_Y, -LEG_Z - 0.02);
    r[NECK0] = v3(0, ROOT_Y + 0.14, 0.10);
    r[NECK1] = v3(0, r[NECK0].y + NECK_STEP, 0.18);
    r[NECK2] = v3(0, r[NECK1].y + NECK_STEP, 0.24);
    r[NECK3] = v3(0, r[NECK2].y + NECK_STEP, 0.28);
    r[HEAD] = v3(0, r[NECK3].y + HEAD_LIFT, 0.30);
    r[LID] = v3(r[HEAD].x, r[HEAD].y + village.CHEST_HINGE_Y, r[HEAD].z + village.CHEST_HINGE_Z);
    r[FANGS] = v3(r[HEAD].x, r[HEAD].y + village.CHEST_HINGE_Y, r[HEAD].z);
    r[LIDFANGS] = r[LID];
    break :blk r;
};

const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
const BONE_LT = archermod.BONE_LT;
const TOOTH = rgba(178, 168, 140, 255);
const TOOTH_DK = rgba(128, 118, 92, 255);
const GUM = rgba(58, 22, 26, 255);
/// The blue in the seam, emissive like the real chest's gold (`propvillage.CHEST_GLOW_EMISSIVE`): alpha is inverse emissive in this shader.
const GLOW = rgba(92, 148, 255, 26);
const GLOW_HOT = rgba(168, 204, 255, 26);
const CHIP_SPRAY = archermod.boneChips(1.05);

pub var AGGRO_R: f32 = 14.0;
const HOME_R: f32 = 2.0;
const TURN_RATE: f32 = 3.0;
const WALK_SPEED: f32 = 1.5;
const CHASE_SPEED: f32 = 2.3;
const ACCEL: f32 = 5.0;
const BODY_R: f32 = 0.55;
const HEAD_R: f32 = 0.62;
const BODY_HURT_R: f32 = 0.55;
pub var SOULS: u32 = 480;

const HP_MAX: f32 = 210.0;
const POISE_MAX: f32 = 22.0;
const STANCE_MAX: f32 = 60.0;
const RESISTS = combat.resists(.{ .fire = -20, .cold = 30, .lightning = -30, .chaos = 40 });

/// DANGEROUS (owner): the bite is a knight's overhead worth of a blow, off a thing you walked up to and pressed Y on.
pub var BITE_HIT = combat.Hit{ .dmg = 30, .poise = 40, .stance = 16 };
pub var SWING_HIT = combat.Hit{ .dmg = 22, .poise = 34, .stance = 12 };

pub const RISE_DUR: f32 = 0.90;
const BITE_WIND: f32 = 0.50;
const BITE_STRIKE: f32 = 0.22;
const BITE_RECOVER: f32 = 0.70;
const BITE_CD: f32 = 2.2;
const BITE_LUNGE: f32 = 1.0;
/// Share of the wind gone before the body starts forward; the lunge is spread over the rest of it and the strike.
const BITE_LUNGE_FROM: f32 = 0.6;
const BITE_R: f32 = 2.3;
const BITE_FRONT_DOT: f32 = 0.50;
const BITE_IMPACT_K: f32 = 0.45;

const SWING_WIND: f32 = 0.55;
const SWING_DUR: f32 = 0.55;
const SWING_RECOVER: f32 = 0.60;
const SWING_CD: f32 = 3.2;
const SWING_R: f32 = 2.5;
/// Degrees off her facing past which the head goes ROUND rather than out — the bite cannot be brought to a man on the flank.
const SWING_BEARING: f32 = 55.0;
/// The head passes the man once; this is the half-width of the sweep's bill about its own bearing.
const SWING_SLOT: f32 = 32.0;

const DEATH_DUR: f32 = 1.35;
const DISS_DUR: f32 = 1.0;
const SHOVE_DECAY: f32 = 7.0;
const GAIT_RATE: f32 = 1.9;

comptime {
    std.debug.assert(BITE_WIND >= foe.TELL_MIN and SWING_WIND >= foe.TELL_MIN);
    std.debug.assert(BITE_CD > BITE_WIND + BITE_STRIKE + BITE_RECOVER);
    std.debug.assert(SWING_CD > SWING_WIND + SWING_DUR + SWING_RECOVER);
    std.debug.assert(SWING_R > BITE_R * 0.8);
    std.debug.assert(chestmod.REACH > BODY_R + foe.HERO_R); // …or the prompt never comes up against the box's own footprint
}

const NPART = 72;
const CHIP_LIGHT = 9;
const CHIP_HEAVY = 15;
const CHIP_DEATH = 20;
const CHIP_RISE = 14;
comptime {
    std.debug.assert(NPART >= foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH) + foe.WOUND_PARTS);
}

const State = enum { chest, rise, idle, walk, bite, swing, stunlight, stunheavy, dead };

const Choice = enum { bite, swing, close, hold };
fn classify(dist: f32, bearingDeg: f32, biteR: f32, swingR: f32, biteReady: bool, swingReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist <= swingR and swingReady and (@abs(bearingDeg) > SWING_BEARING or !biteReady)) return .swing;
    if (dist <= biteR and biteReady and @abs(bearingDeg) <= SWING_BEARING) return .bite;
    return .close;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    chest: rl.Model,
    lid: rl.Model,
    glow: rl.Model,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var bone: [N]rl.Mesh = undefined;
        bone[ROOT] = pelvisMesh();
        inline for (LEGS) |L| {
            bone[L.hip] = thighMesh(L.side);
            bone[L.knee] = shinMesh(L.side);
        }
        bone[NECK0] = vertebraMesh(0);
        bone[NECK1] = vertebraMesh(1);
        bone[NECK2] = vertebraMesh(2);
        bone[NECK3] = vertebraMesh(3);
        bone[HEAD] = throatMesh();
        bone[FANGS] = fangsMesh(1.0);
        bone[LIDFANGS] = fangsMesh(-1.0);
        return .{ .bone = bone, .chest = village.chestMesh(shader), .lid = village.chestLidMesh(shader), .glow = glowMesh(shader), .mat = gfx.material(shader, "bone mimic") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
        self.chest.materials[0].shader = sh;
        self.lid.materials[0].shader = sh;
        self.glow.materials[0].shader = sh;
    }
    pub fn draw(self: *const Model, m: *const Mimic) void {
        rl.drawMesh(self.chest.meshes[0], self.chest.materials[0], m.xf[HEAD]);
        rl.drawMesh(self.lid.meshes[0], self.lid.materials[0], m.xf[LID]);
        if (m.rise <= 0.001) return;
        for (0..N) |i| {
            if (i == HEAD or i == LID) continue;
            rl.drawMesh(self.bone[i], self.mat, m.xf[i]);
        }
    }
};

pub const Mimic = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    parry: foe.Parry = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .chest,
    t: f32 = 0,
    elapsed: f32 = 0,
    biteCd: f32 = 0,
    swingCd: f32 = 0,
    /// 0 IS THE CHEST AND 1 IS THE CREATURE, and every dial on the wake is a share of it.
    rise: f32 = 0,
    justWoke: bool = false,
    snapped: bool = false,
    swept: bool = false,
    speed: f32 = 0,
    speedS: f32 = 0,
    phase: f32 = 0,
    moving: f32 = 0,
    swingDir: f32 = 1,
    lid: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    parried: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = REST,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Mimic {
        var m = Mimic{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        m.fxRng = foe.fxStream(seed, 70123.0, 0x1C);
        m.aiRng = foe.fxStream(seed, 24601.0, 0x1D);
        m.pose();
        return m;
    }

    pub fn kind(_: *const Mimic) wf.FoeKind {
        return .bone_mimic;
    }
    /// The chest is the head, and the head is the mark: awake it is up on the stalk, asleep it is the box on the ground.
    pub fn lockPoint(self: *const Mimic) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, village.CHEST_HINGE_Y * 0.7, 0));
    }
    pub fn headWorld(self: *const Mimic) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, village.CHEST_HINGE_Y * 0.6, 0));
    }
    pub fn centerWorld(self: *const Mimic) rl.Vector3 {
        return foe.markOn(self.xf[ROOT], mathx.zero3);
    }
    pub fn topWorld(self: *const Mimic) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, village.CHEST_TOP, 0));
    }
    pub fn hurtRadius(self: *const Mimic) f32 {
        return BODY_HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Mimic) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Mimic) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Mimic) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Mimic) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(_: *const Mimic) bool {
        return false;
    }
    pub fn flashFrac(self: *const Mimic) f32 {
        return foe.flashFrac(self.flash);
    }
    /// ASLEEP IT IS A CHEST: no lock, no aim, nothing thrown converges on it. It still stands in your way like a box does.
    pub fn hidden(self: *const Mimic) bool {
        return self.state == .chest;
    }
    pub fn asleep(self: *const Mimic) bool {
        return self.state == .chest;
    }
    /// How lit the seam is: the box glows steady; woken, the throat blazes and beats.
    pub fn glowAmt(self: *const Mimic) f32 {
        if (self.state == .dead) return mathx.maxF(0, 1.0 - self.t / (DEATH_DUR * 0.5));
        if (self.state == .chest) return 0.75 + 0.10 * mathx.sinf(self.elapsed * 1.6 + self.seed * 6.28);
        return 0.85 + 0.15 * mathx.sinf(self.elapsed * 7.0) + 0.6 * self.lid;
    }

    pub fn navWant(self: *const Mimic, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        if (foe.postAim(self)) |go| return go;
        return if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Mimic, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }
    fn bearingTo(self: *const Mimic, hero: rl.Vector3) f32 {
        return foe.bearingDeg(self.pos, self.facing, hero);
    }

    /// The man tried to open it, or hit it: the box comes up on its stalk. Reported by `justWoke` for one frame.
    pub fn wake(self: *Mimic) void {
        if (self.state != .chest) return;
        self.justWoke = true;
        self.leash.provoke();
        self.chips(foe.markOn(self.xf[HEAD], v3(0, 0.1, 0)), v3(0, 1, 0), CHIP_RISE, 2.6);
        self.enter(.rise);
    }

    fn toImpact(self: *const Mimic) ?f32 {
        if (self.state != .bite) return null;
        return BITE_WIND + BITE_STRIKE * BITE_IMPACT_K - self.t;
    }
    fn parryable(self: *const Mimic) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(BITE_R, self.scale) + BITE_LUNGE * self.scale;
    }
    fn takeParry(self: *Mimic) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.biteCd = BITE_CD;
        self.chips(self.headWorld(), mathx.dirXZ(self.pos, self.parry.at), 10, 3.0);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    pub fn update(self: *Mimic, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.heroHit = null;
        self.justWoke = false;
        self.snapped = false;
        self.swept = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.justDied = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed and self.state != .chest) self.stagger(true);
        self.t += dt;
        self.elapsed += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.biteCd = mathx.maxF(0, self.biteCd - dt);
        self.swingCd = mathx.maxF(0, self.swingCd - dt);
        if (self.state != .chest) foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        var moved: f32 = 0;
        switch (self.state) {
            .chest => {
                self.speed = 0;
                self.rise = 0;
                self.lid = 0;
                // AN ORDERED ONE IS AWAKE FROM THE FIRST FRAME (the owlbear's rule): a box cannot walk a route, and `ai=` on it used to be swallowed by the sleep.
                if (self.post.idles()) {
                    self.rise = 1.0;
                    self.enter(.idle);
                }
            },
            .rise => {
                self.speed = 0;
                self.rise = mathx.smoothstep(0, 1, mathx.clampF(self.t / RISE_DUR, 0, 1));
                // The lid gapes as it comes up: the FIRST thing you see is the teeth.
                self.lid = mathx.smoothstep(0.2, 0.9, self.rise) * 0.8;
                if (self.rise > 0.5) self.faceToward(hero, dt);
                if (self.t >= RISE_DUR) {
                    self.rise = 1;
                    self.enter(.idle);
                }
            },
            .dead => {
                self.speed = 0;
                self.lid = approach(self.lid, 0.9, dt * 3.0);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, archermod.DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                self.lid = approach(self.lid, 0.25, dt * 4.0);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .bite => {
                if (self.t < BITE_WIND) self.faceToward(hero, dt);
                self.speed = 0;
                self.lid = self.gapeAmt();
                if (self.t >= BITE_WIND * BITE_LUNGE_FROM and self.t < BITE_WIND + BITE_STRIKE) {
                    const span = BITE_WIND * (1.0 - BITE_LUNGE_FROM) + BITE_STRIKE;
                    const step = BITE_LUNGE * self.scale * (dt / span);
                    mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
                    moved = step;
                }
                if (self.t >= BITE_WIND + BITE_STRIKE * BITE_IMPACT_K and self.t < BITE_WIND + BITE_STRIKE) self.tryBite(hero);
                if (self.t >= BITE_WIND + BITE_STRIKE + BITE_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .swing => {
                self.speed = 0;
                self.lid = 0.35 + 0.25 * mathx.maxF(0, self.swingAmt());
                if (self.t >= SWING_WIND and self.t < SWING_WIND + SWING_DUR) self.trySweep(hero);
                if (self.t >= SWING_WIND + SWING_DUR + SWING_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .idle, .walk => {
                self.lid = approach(self.lid, 0.12 + 0.06 * mathx.sinf(self.elapsed * 2.2), dt * 3.0);
                const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
                const bearing = self.bearingTo(hero);
                switch (classify(sensed, bearing, self.biteReach(), self.swingReach(), self.biteCd <= 0, self.swingCd <= 0)) {
                    .bite => {
                        self.speed = 0;
                        self.heroLatch = false;
                        self.biteCd = BITE_CD * self.aiRng.range(0.85, 1.25);
                        self.enter(.bite);
                    },
                    .swing => {
                        self.speed = 0;
                        self.heroLatch = false;
                        self.swingDir = if (bearing >= 0) 1.0 else -1.0;
                        self.swingCd = SWING_CD * self.aiRng.range(0.85, 1.2);
                        self.enter(.swing);
                    },
                    .close => {
                        self.faceToward(self.nav.aim(self.pos, hero), dt);
                        const stop = foe.hurtReach(BITE_R, self.scale) * 0.75 + foe.HERO_R;
                        if (mathx.distXZ(self.pos, hero) > stop) {
                            self.speed = approach(self.speed, CHASE_SPEED, ACCEL * dt);
                            moved = self.travel(dt, bounds);
                            self.state = .walk;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                    .hold => {
                        if (foe.postWant(self, dt, sensed, AGGRO_R)) |go| {
                            self.faceToward(self.nav.aim(self.pos, go), dt);
                            self.speed = approach(self.speed, WALK_SPEED, ACCEL * dt);
                            moved = self.travel(dt, bounds);
                            self.state = .walk;
                        } else if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) {
                            self.faceToward(self.nav.aim(self.pos, self.home), dt);
                            self.speed = approach(self.speed, WALK_SPEED, ACCEL * dt);
                            moved = self.travel(dt, bounds);
                            self.state = .walk;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                }
            },
        }

        self.speedS = approach(self.speedS, self.speed, 6.0 * dt);
        self.moving = approach(self.moving, if (moved > 0) 1.0 else 0.0, 5.0 * dt);
        if (moved > 0) self.phase = self.phase + moved * GAIT_RATE / self.scale;
        self.takeParry();
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn travel(self: *Mimic, dt: f32, bounds: f32) f32 {
        const step = self.speed * dt;
        mathx.stepXZ(&self.pos, self.nav.along(mathx.headingDir(self.facing)), step, bounds);
        return step;
    }

    fn biteReach(self: *const Mimic) f32 {
        return foe.hurtReach(BITE_R, self.scale) + BITE_LUNGE * self.scale * 0.6;
    }
    fn swingReach(self: *const Mimic) f32 {
        return foe.hurtReach(SWING_R, self.scale);
    }

    fn tryBite(self: *Mimic, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(BITE_R, self.scale), BITE_FRONT_DOT)) return;
        self.heroHit = BITE_HIT;
        self.heroLatch = true;
        self.snapped = true;
        self.leash.noteCombat();
    }

    /// The head goes ROUND: one full turn of the sweep over `SWING_DUR`, and it bills the man once as it passes his bearing.
    fn trySweep(self: *Mimic, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (mathx.distXZ(self.pos, hero) > foe.hurtReach(SWING_R, self.scale)) return;
        const sweep = self.sweepBearing();
        const bearing = self.bearingTo(hero);
        if (@abs(mathx.degrees(mathx.wrapPi(mathx.radians(sweep - bearing)))) > SWING_SLOT) return;
        self.heroHit = SWING_HIT;
        self.heroLatch = true;
        self.swept = true;
        self.leash.noteCombat();
    }

    /// Degrees off her facing the head is at through the swing: starts behind her on the side he is NOT on, comes round the front and on past.
    fn sweepBearing(self: *const Mimic) f32 {
        const u = mathx.clampF((self.t - SWING_WIND) / SWING_DUR, 0, 1);
        return self.swingDir * (-200.0 + 400.0 * foe.swingCurve(u));
    }

    pub fn tryHit(self: *Mimic, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reachedPart(self, &self.vit, blade, .{ .center = self.headWorld(), .r = HEAD_R * self.scale }) orelse
            foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.5, .heavy = 1.1 });
        self.chips(s.contact, s.dir, if (heavy) CHIP_HEAVY else CHIP_LIGHT, if (heavy) 3.0 else 2.0);
        // A BLOW WAKES IT AS SURELY AS A HAND ON THE LID: the box was a body all along.
        if (self.state == .chest) self.wake();
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 2.8);
                self.enterDeath();
            },
            .heavy => if (self.state != .rise) self.enterStun(.stunheavy),
            .light => if (self.state != .rise) self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn chips(self: *Mimic, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, CHIP_SPRAY);
    }

    fn enter(self: *Mimic, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Mimic, s: State) void {
        self.heroLatch = false;
        self.enter(s);
    }
    fn enterDeath(self: *Mimic) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.rise = mathx.maxF(self.rise, 0.001);
        self.enter(.dead);
        self.justDied = true;
    }
    pub fn stagger(self: *Mimic, heavy: bool) void {
        if (self.state == .dead or self.state == .chest or self.state == .rise) return;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Mimic) void {
        self.enterDeath();
    }
    pub fn debugWake(self: *Mimic) void {
        self.wake();
        self.rise = 1;
        self.enter(.idle);
        self.pose();
    }
    pub fn debugBite(self: *Mimic) void {
        self.heroLatch = false;
        self.biteCd = BITE_CD;
        self.enter(.bite);
    }
    pub fn debugSwing(self: *Mimic, dir: f32) void {
        self.heroLatch = false;
        self.swingDir = dir;
        self.swingCd = SWING_CD;
        self.enter(.swing);
    }
    pub fn stageGather(self: *Mimic, u: f32) void {
        self.rise = 1;
        self.state = .bite;
        self.t = mathx.clampF(u, 0, 1) * BITE_WIND;
        self.lid = self.gapeAmt();
        self.pose();
    }

    /// -1 reared back, 0 rest, +1 driven down and out: the bite's one clock, and the lid reads off it.
    fn biteAmt(self: *const Mimic) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return -mathx.smoothstep(0, BITE_WIND * 0.85, self.t);
        const s = self.t - BITE_WIND;
        if (s < BITE_STRIKE) return lerpF(-1.0, 1.0, foe.swingCurve(s / BITE_STRIKE));
        return 1.0 - mathx.smoothstep(BITE_STRIKE, BITE_STRIKE + BITE_RECOVER * 0.7, s);
    }
    /// The lid: wide through the rear-back, SHUT at the snap, ajar after.
    fn gapeAmt(self: *const Mimic) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return 0.15 + 0.85 * mathx.smoothstep(0, BITE_WIND * 0.8, self.t);
        const s = self.t - BITE_WIND;
        if (s < BITE_STRIKE) return 1.0 - foe.swingCurve(s / BITE_STRIKE);
        return 0.15 * mathx.smoothstep(BITE_STRIKE, BITE_STRIKE + 0.3, s);
    }
    /// -1 coiled back the other way, +1 swung through.
    fn swingAmt(self: *const Mimic) f32 {
        if (self.state != .swing) return 0;
        if (self.t < SWING_WIND) return -mathx.smoothstep(0, SWING_WIND * 0.85, self.t);
        const s = self.t - SWING_WIND;
        if (s < SWING_DUR) return lerpF(-1.0, 1.0, foe.swingCurve(s / SWING_DUR));
        return 1.0 - mathx.smoothstep(SWING_DUR, SWING_DUR + SWING_RECOVER * 0.8, s);
    }
    fn stunAmount(self: *const Mimic) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }

    pub fn drawFx(self: *const Mimic) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Mimic, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Mimic) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(0.3, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const up = self.rise;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const bite = self.biteAmt();
        const swing = self.swingAmt();
        const m = self.moving * (1.0 - dk);
        const bob = 0.02 * mathx.sinf(self.phase * 2.0 * std.math.tau) * m;
        const breathe = mathx.sinf(self.elapsed * 1.3 + self.seed * 6.28) * 0.008 * up;

        var wx: [N]rl.Matrix = undefined;
        // THE BODY COMES UP OUT OF THE BOX: root from the ground to its stance, and the whole stalk telescopes on `rise`. Dead, it sits back down.
        const rootY = lerpF(0.0, ROOT_Y, up) * (1.0 - 0.7 * dk) + bob + breathe;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul(rz(4.0 * mathx.sinf(self.phase * std.math.tau) * m + 26.0 * dk), rx(-6.0 * stun + 14.0 * dk)),
            mul(tr(0, rootY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        // FOUR SHORT LEGS, folded flat inside the box and unfolding as it stands; a scuttle in diagonal pairs when it walks.
        inline for (LEGS, 0..) |L, i| {
            const pairPhase = if (i == 0 or i == 3) self.phase else self.phase + 0.5;
            const swingL = mathx.sinf(pairPhase * std.math.tau) * 26.0 * m;
            const lift = mathx.maxF(0, mathx.cosf(pairPhase * std.math.tau)) * 30.0 * m;
            const tuck = (1.0 - up) * 88.0;
            heromod.setJoint(&wx, &self.rest, L.hip, ROOT, mul(rx(-L.fore * (14.0 - swingL) - tuck * L.fore), rz(L.side * 18.0)));
            heromod.setJoint(&wx, &self.rest, L.knee, L.hip, mul(rx(L.fore * (28.0 + lift) + tuck * L.fore * 0.6), rz(-L.side * 8.0)));
        }

        // THE NECK: rears up and back through the bite's wind, whips down and forward at the snap; coils sideways and sweeps for the swing.
        const rear = mathx.maxF(0, -bite);
        const drive = mathx.maxF(0, bite);
        const pitch = -26.0 * rear + 34.0 * drive - 18.0 * stun + 40.0 * dk;
        const yaw = self.swingDir * (-70.0 * mathx.maxF(0, -swing) + 0.0) + (if (self.state == .swing and self.t >= SWING_WIND) self.sweepBearing() * 0.55 else 0.0);
        const idleSway = mathx.sinf(self.elapsed * 0.9 + self.seed * 3.0) * 5.0 * up * (1.0 - dk);
        const grow = up;
        inline for (.{ NECK0, NECK1, NECK2, NECK3 }, 0..) |b, i| {
            const share: f32 = @floatFromInt(i + 1);
            const parent: usize = if (i == 0) ROOT else b - 1;
            const off = mathx.scaleV(mathx.subV(self.rest[b], self.rest[parent]), grow);
            const rot = mul3(rx(pitch * 0.28 + 10.0 * drive * share * 0.25 - 4.0 * rear), ry(yaw * 0.30 + idleSway * 0.3), rz(mathx.sinf(self.elapsed * 1.7 + share) * 1.5 * up));
            wx[b] = mul(mul(rot, tr(off.x, off.y, off.z)), wx[parent]);
        }
        {
            const off = mathx.scaleV(mathx.subV(self.rest[HEAD], self.rest[NECK3]), grow);
            // The chest sits level on the stalk; at the snap it pitches down onto him, and the swing carries it round.
            const headRot = mul3(rx(pitch * 0.4), ry(yaw * 0.25), rz(0));
            wx[HEAD] = mul(mul(headRot, tr(off.x, off.y, off.z)), wx[NECK3]);
        }
        // THE CHEST ON THE GROUND IS EXACTLY THE PROP: the box's own frame, on the ground, facing the way it was posted.
        if (up <= 0.001 and !dead) {
            wx[HEAD] = mul(scaleM(fs, fs, fs), mul(ry(facingDeg), heromod.rootAt(self.pos)));
        }
        const open = mathx.clampF(self.lid, 0, 1);
        heromod.setJoint(&wx, &self.rest, LID, HEAD, rx(-chestmod.OPEN_DEG * 0.75 * open));
        // The teeth GROW with the wake: nothing on the box until it stirs.
        const teeth = mathx.smoothstep(0.15, 0.85, up);
        wx[FANGS] = mul(mul(scaleM(1.0, teeth, 1.0), tr(0, village.CHEST_HINGE_Y, 0)), wx[HEAD]);
        wx[LIDFANGS] = mul(scaleM(1.0, teeth, 1.0), wx[LID]);
        self.xf = wx;
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Hoard = struct {
    model: Model,
    band: [CAP_N]Mimic = undefined,
    n: usize = 0,
    /// The SLEEPING one inside `chest.REACH` of the man, if any — what the prompt asks about and what Y wakes.
    near: ?usize = null,

    pub fn init(shader: rl.Shader) Hoard {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Hoard) []Mimic {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Hoard) []const Mimic {
        return self.band[0..self.n];
    }
    pub fn reset(self: *Hoard, m: *const wf.Map) void {
        self.near = null;
        foe.resetGroup(Mimic, &self.band, &self.n, m, .bone_mimic);
    }
    pub fn clear(self: *Hoard) void {
        self.n = 0;
        self.near = null;
    }
    pub fn setShader(self: *Hoard, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Hoard, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Hoard) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn update(self: *Hoard, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var nearest = mathx.Nearest.within(chestmod.REACH);
        for (self.live(), 0..) |*m, i| {
            if (m.asleep() and m.alive()) nearest.offer(i, m.pos, hero);
        }
        self.near = nearest.best;
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    /// Y on the box: it comes up. True if there was one to wake.
    pub fn wakeNear(self: *Hoard) bool {
        const i = self.near orelse return false;
        self.band[i].wake();
        self.near = null;
        return true;
    }
    pub fn draw(self: *const Hoard, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
        // The seam glows blue, box or beast: the one thing that tells it from the chest beside it, and the thing you are looking at when it opens.
        const sc = scene orelse return;
        rl.gl.rlDisableDepthMask();
        for (self.liveConst()) |*m| {
            if (!m.alive()) continue;
            const a = m.glowAmt();
            if (a <= 0.01) continue;
            sc.beginFade(mathx.clampF(a, 0, 1));
            rl.drawMesh(self.model.glow.meshes[0], self.model.glow.materials[0], m.xf[HEAD]);
            sc.endFade();
        }
        rl.gl.rlEnableDepthMask();
    }
    pub fn drawFx(self: *const Hoard) void {
        for (self.liveConst()) |*m| m.drawFx();
    }
    pub fn pierce(self: *Hoard, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Hoard) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyWoke(self: *const Hoard) bool {
        for (self.liveConst()) |*m| {
            if (m.justWoke) return true;
        }
        return false;
    }
    pub fn soulsDropped(self: *const Hoard) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Hoard) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Hoard) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn glowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    const hx = village.CHEST_HALF_X + 0.010;
    const hz = village.CHEST_HALF_Z + 0.010;
    b.setMat(.plain);
    b.addCube(v3(0, village.CHEST_HINGE_Y, 0), v3(hx * 2.0, 0.034, hz * 2.0), GLOW);
    const inX = village.CHEST_HALF_X - 0.09;
    const inZ = village.CHEST_HALF_Z - 0.09;
    b.addBlob(v3(0, village.CHEST_HINGE_Y - 0.13, 0), v3(inX, 0.10, inZ), 3, 8, GLOW_HOT);
    return b.toModel(shader);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1C01);
    b.setMat(.plain);
    b.addBlob(v3(0, 0, 0), v3(0.26, 0.16, 0.30), 5, 10, BONE);
    b.addBlob(v3(0, 0.08, -0.02), v3(0.14, 0.10, 0.22), 4, 8, BONE_DK);
    // The ribs, a cage that stands proud of the pelvis and open below.
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const z = -0.20 + 0.10 * @as(f32, @floatFromInt(i));
        inline for (.{ 1.0, -1.0 }) |side| {
            const r = 0.22 * rng.range(0.9, 1.1);
            b.addCapsule(v3(0, 0.10, z), v3(side * r, -0.04, z + 0.02), 0.022, 0.016, 5, if (i % 2 == 0) BONE else BONE_LT);
            b.addCapsule(v3(side * r, -0.04, z + 0.02), v3(side * r * 0.7, -0.15, z + 0.03), 0.016, 0.012, 5, BONE_DK);
        }
    }
    return b.toMesh();
}

fn thighMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    const len = ROOT_Y - 0.06 - KNEE_Y;
    b.addBlob(v3(0, 0.01, 0), v3(0.07, 0.06, 0.07), 4, 8, BONE);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.04, -len, 0.02), 0.036, 0.028, 7, BONE);
    return b.toMesh();
}

fn shinMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x1C05 else 0x1C06);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.01, 0), v3(0.05, 0.045, 0.05), 4, 7, BONE_DK);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.01, -SHIN + 0.03, 0.02), 0.028, 0.020, 6, BONE);
    // Three toes splayed on the ground.
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const a = -0.6 + 0.6 * @as(f32, @floatFromInt(i));
        const len = 0.10 * rng.range(0.85, 1.15);
        b.addCapsule(v3(side * 0.01, -SHIN + 0.03, 0.02), v3(side * 0.01 + mathx.sinf(a) * len, -SHIN + 0.01, 0.02 + mathx.cosf(a) * len), 0.016, 0.009, 5, BONE_DK);
    }
    return b.toMesh();
}

fn vertebraMesh(i: u32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1C10 + i);
    b.setMat(.plain);
    const r = 0.085 - 0.008 * @as(f32, @floatFromInt(i));
    b.addBlob(v3(0, 0, 0), v3(r, r * 0.8, r * 0.9), 5, 9, BONE);
    b.addCapsule(v3(0, 0, 0), v3(0, NECK_STEP * 0.6, 0.02), r * 0.55, r * 0.5, 7, BONE_DK);
    // Processes off each vertebra, uneven, the way a spine is.
    inline for (.{ 1.0, -1.0 }) |side| {
        const out = (0.10 + rng.range(-0.02, 0.03));
        b.addCapsule(v3(0, NECK_STEP * 0.3, 0), v3(side * out, NECK_STEP * 0.36, -0.03), 0.018, 0.010, 5, BONE_LT);
    }
    b.addCapsule(v3(0, NECK_STEP * 0.3, -0.02), v3(0, NECK_STEP * 0.42, -0.10 - rng.range(0, 0.03)), 0.016, 0.009, 5, BONE_LT);
    return b.toMesh();
}

/// Under the chest: the gullet the stalk runs into, and the sinew that holds the box to it.
fn throatMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(v3(0, -HEAD_LIFT * 0.5, 0.02), v3(0.16, HEAD_LIFT * 0.55, 0.16), 5, 9, BONE_DK);
    b.addCapsule(v3(0, -HEAD_LIFT, 0), v3(0, 0.04, 0), 0.09, 0.14, 8, BONE);
    b.setMat(.skin);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addCapsule(v3(side * 0.10, -HEAD_LIFT * 0.6, -0.06), v3(side * 0.30, 0.06, -0.10), 0.02, 0.014, 5, GUM);
        b.addCapsule(v3(side * 0.08, -HEAD_LIFT * 0.6, 0.06), v3(side * 0.28, 0.06, 0.14), 0.02, 0.014, 5, GUM);
    }
    return b.toMesh();
}

/// The teeth round the box's mouth — down off the lid's rim, up off the carcase's — with the gum they grow from. Authored at full height; the wake scales them up out of nothing.
fn fangsMesh(dir: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (dir > 0) 0x1C20 else 0x1C21);
    const hx = village.CHEST_HALF_X;
    const hz = village.CHEST_HALF_Z;
    // On the LID bone the fangs hang off the lid's front edge, which is at +2 hz along its own frame; on the carcase they stand on the front and side rims.
    const rimZ: f32 = if (dir > 0) hz else hz * 2.0;
    b.setMat(.skin);
    b.addCube(v3(0, dir * 0.02, rimZ - 0.04), v3(hx * 2.0 - 0.08, 0.05, 0.06), GUM);
    b.setMat(.plain);
    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        const x = -hx + 0.10 + (hx * 2.0 - 0.20) * @as(f32, @floatFromInt(i)) / 8.0 + rng.range(-0.02, 0.02);
        const len = rng.range(0.11, 0.20);
        const base = v3(x, dir * 0.03, rimZ - 0.05);
        const tip = v3(x + rng.range(-0.02, 0.02), dir * (0.03 + len), rimZ - 0.05 + rng.range(-0.02, 0.02));
        b.addCapsule(base, tip, 0.030 * rng.range(0.8, 1.2), 0.006, 5, if (i % 3 == 0) TOOTH_DK else TOOTH);
    }
    if (dir > 0) {
        inline for (.{ 1.0, -1.0 }) |side| {
            var k: u32 = 0;
            while (k < 3) : (k += 1) {
                const z = hz - 0.16 - 0.16 * @as(f32, @floatFromInt(k));
                const len = rng.range(0.08, 0.14);
                b.addCapsule(v3(side * (hx - 0.05), 0.03, z), v3(side * (hx - 0.05), 0.03 + len, z), 0.024, 0.005, 5, TOOTH);
            }
        }
    }
    return b.toMesh();
}

// ---------------------------------------------------------------------------------------------------------------

test "ASLEEP IT IS A CHEST: on the ground, hidden from the lock, glowing, and the prompt is a chest's" {
    var h = Hoard{ .model = undefined };
    h.band[0] = Mimic.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    h.n = 1;
    const m = &h.band[0];
    try std.testing.expect(m.asleep() and m.hidden() and m.alive() and !m.staggered());
    try std.testing.expect(m.glowAmt() > 0.5);
    // The box's frame IS the prop's: base on the ground, top at the prop's own top.
    try std.testing.expectApproxEqAbs(@as(f32, 0), foe.markOn(m.xf[HEAD], mathx.zero3).y, 1e-4);
    try std.testing.expectApproxEqAbs(village.CHEST_TOP, m.topWorld().y, 1e-4);
    _ = h.update(1.0 / 60.0, mathx.ground(0, chestmod.REACH - 0.2), 400.0, .{});
    try std.testing.expectEqual(@as(?usize, 0), h.near);
    _ = h.update(1.0 / 60.0, mathx.ground(0, chestmod.REACH + 0.5), 400.0, .{});
    try std.testing.expect(h.near == null);
    std.debug.print("\n  bone mimic: a {d:.2} m box, prompt inside {d:.1} m, glow {d:.2}\n", .{ village.CHEST_TOP, chestmod.REACH, m.glowAmt() });
}

test "Y ON THE BOX AND IT COMES UP ON ITS STALK — the head rises off the ground, the teeth grow in, and it is a body from then on" {
    var h = Hoard{ .model = undefined };
    h.band[0] = Mimic.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    h.n = 1;
    const hero = mathx.ground(0, 1.6);
    _ = h.update(1.0 / 60.0, hero, 400.0, .{});
    try std.testing.expect(h.wakeNear());
    try std.testing.expect(h.band[0].justWoke);
    try std.testing.expect(!h.band[0].hidden());
    var t: f32 = 0;
    var headY: f32 = 0;
    var teeth: f32 = 0;
    while (t < RISE_DUR + 0.1) : (t += 1.0 / 60.0) {
        _ = h.update(1.0 / 60.0, hero, 400.0, .{});
        headY = @max(headY, h.band[0].headWorld().y);
        const scaleY = h.band[0].xf[FANGS].m5;
        teeth = @max(teeth, scaleY);
    }
    std.debug.print("\n  bone mimic risen: head {d:.2} m up, crown {d:.2} m, teeth at {d:.2} of their height, {d:.2} s of wake\n", .{ headY, h.band[0].topWorld().y, teeth, RISE_DUR });
    try std.testing.expect(h.band[0].rise >= 1.0);
    try std.testing.expect(headY > 1.8);
    try std.testing.expect(teeth > 0.95);
    try std.testing.expect(h.near == null);
    try std.testing.expect(!h.wakeNear());
}

test "A BLOW ON THE BOX WAKES IT TOO, AND COUNTS" {
    var m = Mimic.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    const at = m.lockPoint();
    const shaft = foe.shaftThrough(at, heromod.BOW_AIMED_HIT);
    m.tryHit(shaft);
    try std.testing.expectEqual(@as(u32, 1), m.hits);
    try std.testing.expect(m.vit.hp < HP_MAX);
    try std.testing.expect(!m.asleep() and m.justWoke);
}

test "THE BITE LANDS ON THE MAN WHERE HE STANDS — thrown for real at every stand in its band, once per snap, after a tell" {
    const dt: f32 = 1.0 / 120.0;
    var thrown: usize = 0;
    var misses: usize = 0;
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        const probe = Mimic.spawn(mathx.ground(0, 0), 0, scale, 0.3);
        const near = foe.closestApproach(probe.bodyR()) + 0.05;
        const far = probe.biteReach() - 0.02;
        for ([_]f32{ 0, 25, 48 }) |deg| {
            for ([_]f32{ 0.0, 0.35, 0.7, 1.0 }) |u| {
                const stand = lerpF(near, far, u);
                var m = Mimic.spawn(mathx.ground(0, 0), 0, scale, 0.3);
                m.debugWake();
                const a = mathx.radians(deg);
                const hero = v3(@sin(a) * stand, 0, @cos(a) * stand);
                m.debugBite();
                thrown += 1;
                var hit = false;
                var firstAt: f32 = 0;
                var t: f32 = 0;
                while (t < BITE_WIND + BITE_STRIKE + BITE_RECOVER) : (t += dt) {
                    if (m.update(dt, hero, 400.0, .{})) |_| {
                        if (!hit) firstAt = t;
                        hit = true;
                    }
                }
                if (!hit) {
                    misses += 1;
                    std.debug.print("\n  mimic x{d:.2} at {d:.2} m, {d:.0} deg off: MISSED (band to {d:.2})\n", .{ scale, stand, deg, far });
                } else try std.testing.expect(firstAt >= foe.TELL_MIN);
            }
        }
    }
    std.debug.print("\n  bone mimic: {d} bites thrown across three scales, {d} billed nothing\n", .{ thrown, misses });
    try std.testing.expectEqual(@as(usize, 0), misses);
}

test "THE HEAD GOES ROUND: the swing bills a man on the flank and one behind, once, and a bite would not have reached them" {
    const dt: f32 = 1.0 / 120.0;
    for ([_]f32{ 90.0, 150.0, -120.0 }) |deg| {
        var m = Mimic.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
        m.debugWake();
        const a = mathx.radians(deg);
        const stand = m.swingReach() - 0.3;
        const hero = v3(@sin(a) * stand, 0, @cos(a) * stand);
        try std.testing.expectEqual(Choice.swing, classify(stand, deg, m.biteReach(), m.swingReach(), true, true));
        m.debugSwing(if (deg >= 0) 1.0 else -1.0);
        var hits: u32 = 0;
        var t: f32 = 0;
        while (t < SWING_WIND + SWING_DUR + SWING_RECOVER) : (t += dt) {
            if (m.update(dt, hero, 400.0, .{})) |b| {
                hits += 1;
                try std.testing.expectApproxEqAbs(SWING_HIT.dmg, b.dmg, 1e-4);
            }
        }
        std.debug.print("\n  mimic swing at {d:.0} deg, {d:.2} m: {d} hit(s)\n", .{ deg, stand, hits });
        try std.testing.expectEqual(@as(u32, 1), hits);
    }
    try std.testing.expectEqual(Choice.bite, classify(1.8, 10.0, 2.9, 3.05, true, true));
    try std.testing.expectEqual(Choice.close, classify(6.0, 10.0, 2.9, 3.05, true, true));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, 0.0, 2.9, 3.05, true, true));
}

test "IT IS DANGEROUS — the bite out-hits the ogre's swipe, and a parry drops it" {
    const ogremod = @import("ogre.zig");
    try std.testing.expect(BITE_HIT.dmg > ogremod.SWIPE_HIT.dmg);
    var m = Mimic.spawn(mathx.zero3, 0, 1.0, 0.3);
    m.debugWake();
    m.debugBite();
    m.t = BITE_WIND + BITE_STRIKE * BITE_IMPACT_K - foe.PARRY_LEAD * 0.5;
    try std.testing.expect(m.parryable() != null);
    m.parry = .{ .live = true, .at = mathx.ground(0, 1.6), .facing = std.math.pi, .arc = combat.GUARD_ARC };
    m.takeParry();
    try std.testing.expect(m.parried and m.staggered());
}
