const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const propart = @import("../props/propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;


const FUR = rgba(29, 24, 17, 255);
const FUR_DK = rgba(14, 11, 8, 255);
const FUR_LT = rgba(46, 38, 26, 255);
const MUZZLE = rgba(18, 15, 12, 255);
const NOSE = rgba(10, 9, 8, 255);
const EAR_IN = rgba(74, 44, 37, 255);
const EYE = rgba(250, 196, 74, 105);
const TOOTH = rgba(150, 143, 126, 255);
const HIDE = rgba(24, 18, 14, 255);
const HIDE_LT = rgba(36, 28, 20, 255);
const CLOTH = rgba(52, 45, 33, 255);
const CLOTH_DK = rgba(33, 28, 21, 255);

const ZERK_CLOTH = rgba(101, 57, 51, 255);
const ZERK_CLOTH_DK = rgba(63, 35, 32, 255);
const SLING_CLOTH = rgba(62, 88, 46, 255);
const SLING_CLOTH_DK = rgba(38, 55, 29, 255);
const PRIEST_CLOTH = rgba(123, 121, 117, 255);
const PRIEST_CLOTH_DK = rgba(76, 75, 72, 255);

fn fabric(r: Role) [2]rl.Color {
    return switch (r) {
        .berserker => .{ ZERK_CLOTH, ZERK_CLOTH_DK },
        .priest => .{ PRIEST_CLOTH, PRIEST_CLOTH_DK },
        .slinger => .{ SLING_CLOTH, SLING_CLOTH_DK },
    };
}
const IRON = propart.IRON;
const IRON_LT = rgba(46, 44, 41, 255);
const HAFT = rgba(46, 33, 21, 255);
const CLAW = rgba(150, 142, 122, 255);
const BONE_CHARM = rgba(140, 130, 106, 255);
const HEAL_GLOW = rgba(196, 156, 60, 150);
const SLING_CORD = rgba(92, 78, 58, 255);
const CLUMP_CHAR = rgba(38, 32, 28, 255);
const EMBER = rgba(238, 122, 30, 205);
const EMBER_HOT = rgba(255, 214, 132, 225);
const EMBER_CORE = rgba(255, 168, 52, 255);
const EMBER_COOL = rgba(150, 46, 14, 170);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const SKULL = heromod.HEAD;
const HIPL = heromod.HIPL;
const KNEEL = heromod.KNEEL;
const ANKL = heromod.ANKL;
const HIPR = heromod.HIPR;
const KNEER = heromod.KNEER;
const ANKR = heromod.ANKR;
const SHL = heromod.SHL;
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR;
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const KIT = heromod.HELD;


const H: f32 = heromod.H;
// The LEGS and ARMS take the hero's fractions from the shared source: `legChain`'s strafe geometry is measured off the leg pair, so a local copy that drifted would make a kobold's planted feet skate.
const SEG_THIGH = heromod.SEG_THIGH;
const SEG_SHANK = heromod.SEG_SHANK;
const SEG_UPARM = heromod.SEG_UPARM;
const SEG_FOREARM = heromod.SEG_FOREARM;

pub const SCALE: f32 = 1.12;
const HIP_HALF = 0.096;
const SHOULDER_HALF = 0.168;
const RIB_HALF = SHOULDER_HALF - 0.018;

const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;

const setLocal = heromod.setHumanoid;

const LOCK_AT = v3(0, 0.02 * H, 0.05 * H);

/// The kobold's PAW footprint, measured off `footMesh` below: the pad spans z −0.041·H…+0.206·H and x ±0.052·H, its underside on the ankle plane.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.041 * H, .toe = 0.206 * H, .halfW = 0.052 * H, .drop = 0.042 * H },
    .{ .bone = ANKR, .heel = 0.041 * H, .toe = 0.206 * H, .halfW = 0.052 * H, .drop = 0.042 * H },
};

const A_PROT = 4.6;

pub const Role = enum { berserker, priest, slinger };

const Spec = struct {
    hp: f32,
    poise: f32,
    stance: f32,
    speed: f32,
    bodyR: f32,
    hurtR: f32,
    souls: u32,
    wantMin: f32,
    wantMax: f32,
};

const SPEC = [_]Spec{
    .{ .hp = 76, .poise = 11, .stance = 34, .speed = 1.22, .bodyR = 0.40, .hurtR = 0.60, .souls = 120, .wantMin = 0.0, .wantMax = 1.5 },
    .{ .hp = 54, .poise = 10, .stance = 24, .speed = 0.86, .bodyR = 0.38, .hurtR = 0.58, .souls = 210, .wantMin = 7.5, .wantMax = 12.0 },
    .{ .hp = 62, .poise = 12, .stance = 28, .speed = 1.0, .bodyR = 0.38, .hurtR = 0.58, .souls = 140, .wantMin = 5.0, .wantMax = 10.5 },
};

fn spec(r: Role) *const Spec {
    return &SPEC[@intFromEnum(r)];
}

comptime {
    if (SPEC.len != @typeInfo(Role).@"enum".fields.len) @compileError("kobold: a Role with no spec row");
    // …and the kinds are a CONTIGUOUS RUN off `berserker` in role order, since `roleOf`/`kindOf` are an ordinal shift. Unpinned, a kind inserted mid-run silently posts the wrong role — the priest spawns as a berserker and nothing fails to compile.
    for (@typeInfo(Role).@"enum".fields, 0..) |f, i| {
        const fk: wf.FoeKind = @enumFromInt(@intFromEnum(wf.FoeKind.berserker) + i);
        if (!std.mem.eql(u8, f.name, @tagName(fk))) {
            @compileError("kobold: wf.FoeKind." ++ @tagName(fk) ++ " is not in the warband's contiguous run");
        }
    }
}

pub fn roleOf(k: wf.FoeKind) ?Role {
    const lo = @intFromEnum(wf.FoeKind.berserker);
    const i = @intFromEnum(k);
    if (i < lo or i >= lo + SPEC.len) return null;
    return @enumFromInt(i - lo);
}

pub fn kindOf(r: Role) wf.FoeKind {
    return @enumFromInt(@intFromEnum(wf.FoeKind.berserker) + @intFromEnum(r));
}

pub const AGGRO_R = 16.0;
const HOME_R = 1.5;
const TURN_RATE = 5.2;
const WALK_SPEED = heromod.WALK_SPEED;
/// …and what the BERSERKER closes at, which is the hero's own run scaled by his spec (`approachSpeed`). At 1.22 of it that is 4.15 m/s: past the hero's run (3.4) so backing off on foot does not shake him, and well under the sprint (5.1) so the sprint still does.
const RUN_SPEED = heromod.RUN_SPEED;
const ZERK_WALK_IN = 0.9;
const DEATH_DUR = 1.0;
const DISS_DUR = 0.85;
const DISSOLVE = foe.Dissolve{ .rate = 26.0, .spread = 0.42, .rise = 0.55 };
const SHOVE_DECAY = 8.0;

const ZERK_SWINGS_LO: u32 = 3;
const ZERK_SWINGS_HI: u32 = 5;
pub const CHOP_DUR = 0.58;
pub const CHOP_HIT_A = 0.53;
const ZERK_CHOP = CHOP_DUR;
const ZERK_HIT_A = CHOP_HIT_A;
const ZERK_HIT_B = 0.78;
const ZERK_STEP = 0.42;

const DASH_CD = 6.5;
const DASH_R_MIN = 2.3;
const DASH_R_MAX = 7.5;
const DASH_GATHER = 0.14;
const DASH_FLIGHT = 0.30;
const DASH_LAND = 0.22;
const DASH_DIST = 3.9;
const DASH_RISE = 0.28;

fn dashU(t: f32) f32 {
    return mathx.clampF((t - DASH_GATHER) / DASH_FLIGHT, 0, 1);
}
fn dashTravel(t: f32) f32 {
    const u = dashU(t);
    return DASH_DIST * (1.0 - (1.0 - u) * (1.0 - u));
}
const ZERK_RECOVER = 1.75;
const ZERK_REACH = 1.9;
pub const ZERK_HIT = combat.Hit{ .dmg = 11, .poise = 9 };

const CAST_DUR = 1.25;
const CAST_CD = 9.0;
const HEAL_AMT = 30.0;
/// **A FULL METER IN ONE RITE.** Half of one would decay away before a second cast could land on it
/// (`combat.AILS`' berserk row decays at 16/s), so the rite would visibly do nothing.
const RITE_ZERK = combat.ailRow(.berserk).max;
const HEAL_SLACK = 4.0;
const HEAL_RANGE = 14.0;
const HEAL_BLOOM: u32 = 34;

const WHIRL_DUR = 0.70;
const SLING_CD = 1.9;
const BITE_R = 1.45;
const BITE_PREFER_R = 5.0;
/// The jaws arrive at `BITE_DUR * BITE_HIT_A` = 0.34 s — over `foe.TELL_MIN`, and with real margin over the parry window. At the old 0.52 x 0.30 the snap landed at 0.156 s: HALF the tell floor, and the fairness test never caught it because it compared the FRACTION against the SECONDS.
const BITE_DUR = 0.62;
const BITE_HIT_A = 0.55;
const BITE_HIT_B = 0.76;
const BITE_CD = 1.15;
const BITE_COIL_AT = 0.42;
const BITE_ARCH = 14.0;
// The snap: the waist throwing the whole head at you (degrees through the lumbar; the chest adds 0.65 of it again and the pelvis its small share).
const BITE_FOLD = 18.0;
const BITE_GAZE = 26.0;
const BITE_ARM_BACK = 30.0;
const BITE_ARM_TUCK = 14.0;
pub const BITE_HIT = combat.Hit{ .dmg = 9, .poise = 7 };
const RESISTS = combat.resists(.{ .fire = -45, .cold = 20 });
pub const CLUMP_SPEED = 11.0;
const SLING_SPARKS: u32 = 12;
const CLUMP_SPARKS: u32 = 18;
pub const CLUMP_HIT = combat.Hit{ .poise = 8, .elem = combat.elems(.{ .fire = 10 }) };

const REPOSITION_DUR = 1.3;

const PELVIS_SHARE: f32 = 0.12;

const CROUCH_HEAVE: f32 = 32.0;
const CROUCH_STUN: f32 = 20.0;

const DASH_COIL: f32 = 30.0;
const DASH_ABSORB: f32 = 24.0;
const DASH_LEAD_HIP: f32 = 76.0;
const DASH_LEAD_KNEE: f32 = 88.0;
const DASH_TRAIL_HIP: f32 = 32.0;
const DASH_TRAIL_KNEE: f32 = 26.0;
const DASH_TOE: f32 = 24.0;
const DASH_LEAN: f32 = 20.0;
const DASH_ARM_BACK: f32 = 44.0;

fn legSink(crouch: f32) f32 {
    return (SEG_THIGH + SEG_SHANK) * H * (1.0 - mathx.cosf(mathx.radians(crouch)));
}

/// ARITHMETIC over the worst frame (the ring law): at 22 the HEAL BLOOM ALONE OVERFLOWED IT, 34 motes on one frame into 22 slots. Worst frame is the bloom's 34 on the ~14 `emitCastMotes` leaves resident (34/s at a 0.42 s life), with a blow landing the same frame for `emitBlood`'s 14 and the wound — 65.
const NPART = 68;
comptime {
    // THE RING LAW, EXECUTABLE — the assert that was missing when 22 could not hold HEAL_BLOOM's 34.
    std.debug.assert(NPART >= HEAL_BLOOM + 14 + foe.hitParts(9) + foe.WOUND_PARTS);
}
const BLOOD = rgba(104, 26, 22, 200);
const BLOOD_DRY = rgba(48, 11, 9, 190);

const State = enum {
    idle,
    approach,
    reposition,
    chop,
    dash,
    heave,
    cast,
    whirl,
    bite,
    stunlight,
    stunheavy,
    dead,
};

pub const Act = union(enum) {
    none: void,
    sling: rl.Vector3,
    healed: void,
};

pub const Kobold = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    role: Role = .berserker,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    chopsLeft: u32 = 0,
    chopLeftHand: bool = false,
    castCd: f32 = 0,
    slingCd: f32 = 0,
    biteCd: f32 = 0,
    dashCd: f32 = 0,
    dashDone: f32 = 0,
    dashPhase: f32 = 0,
    hop: f32 = 0,
    healWanted: bool = false,
    castGlow: f32 = 0,
    whirlPh: f32 = 0,
    moveDir: rl.Vector3 = mathx.zero3,

    vit: combat.Vitals = combat.Vitals.initFoe(76, 13, 34).withRes(RESISTS),
    hits: u32 = 0,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    fade: f32 = 0,
    gone: bool = false,
    dealt: bool = false,
    parry: foe.Parry = .{},
    parried: bool = false,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    wade: foe.Wade = .{},

    xf: [N]rl.Matrix = undefined,
    jawXf: rl.Matrix = undefined,
    tailXf: [TAIL_N]rl.Matrix = undefined,
    /// The tail's lash, in degrees, eased so a hit or a swing whips it rather than teleporting it.
    tailWhip: f32 = 0,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Kobold {
        return spawnAs(.berserker, home, faceYaw, scale, seed);
    }

    pub fn spawnAs(role: Role, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Kobold {
        const s = spec(role);
        var k = Kobold{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .role = role,
            .vit = combat.Vitals.initFoe(s.hp, s.poise, s.stance).withRes(RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 96337.0, 11);
        k.slingCd = 0.3 + seed;
        k.castCd = seed * 2.0;
        k.whirlPh = seed;
        k.pose();
        return k;
    }

    pub fn alive(self: *const Kobold) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Kobold) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Kobold) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// OFF THE GROUND only during the berserker's dash, and only for the FLIGHT of it — measured off the same `hop` the pelvis rides, against the threshold the toad and the archer share.
    pub fn airborne(self: *const Kobold) bool {
        return self.state == .dash and self.hop > foe.AIRBORNE_LIFT;
    }
    pub fn bodyR(self: *const Kobold) f32 {
        return spec(self.role).bodyR * self.scale;
    }
    pub fn hurtRadius(self: *const Kobold) f32 {
        return spec(self.role).hurtR * self.scale;
    }
    pub fn centerWorld(self: *const Kobold) rl.Vector3 {
        return foe.bodyPoint(self.pos, 0.80 * H, self.scale, 0);
    }
    /// THE MARK RIDES THE SKULL, and this is the creature it matters most on: a kobold is HUNCHED, so its head sits well below the 0.885·H the shared rest puts the joint at, and the flat 0.78·H this used to be was a guess. It also ducks, lunges and whips its head through a flurry.
    pub fn lockPoint(self: *const Kobold) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], LOCK_AT);
    }
    pub fn topWorld(self: *const Kobold) rl.Vector3 {
        return foe.bodyPoint(self.pos, 1.06 * H, self.scale, 0);
    }
    pub fn flashFrac(self: *const Kobold) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn soulValue(self: *const Kobold) u32 {
        return spec(self.role).souls;
    }
    pub fn kind(self: *const Kobold) wf.FoeKind {
        return kindOf(self.role);
    }

    fn faceToward(self: *Kobold, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    pub fn navWant(self: *const Kobold, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        return switch (self.state) {
            .approach, .reposition => mathx.addV(self.pos, self.moveDir),
            else => null,
        };
    }

    pub fn slingPoint(self: *const Kobold) rl.Vector3 {
        return rl.math.vector3Transform(v3(0, 0, SLING_LEN * H), self.xf[KIT]);
    }

    pub fn hurtOpen(self: *const Kobold) bool {
        if (self.dealt) return false;
        const u = switch (self.state) {
            .chop => self.t / ZERK_CHOP,
            .bite => self.t / BITE_DUR,
            else => return false,
        };
        return switch (self.state) {
            .chop => u >= ZERK_HIT_A and u < ZERK_HIT_B,
            .bite => u >= BITE_HIT_A and u < BITE_HIT_B,
            else => false,
        };
    }

    pub fn hurtReach(self: *const Kobold) f32 {
        return switch (self.state) {
            .chop => foe.hurtReach(ZERK_REACH, self.scale),
            .bite => foe.hurtReach(BITE_R, self.scale),
            else => 0,
        };
    }
    /// **THE FIRST CREATURE TO TAKE THE BARGAIN, AND IT READS THE HERO'S OWN THREE DIALS**
    /// (`combat.Vitals.dmgMult`/`hasteMult`/`travelMult`). The price too: `AILS`' `hpFrac`, then `justEnded`.
    pub fn hurtBlow(self: *const Kobold) combat.Hit {
        const base: combat.Hit = switch (self.state) {
            .chop => ZERK_HIT,
            else => BITE_HIT,
        };
        return base.scaled(self.vit.dmgMult());
    }
    pub fn markDealt(self: *Kobold) void {
        self.dealt = true;
        self.leash.noteCombat();
    }

    pub fn update(self: *Kobold, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.justDied = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        // **ITS OWN CLOCK, NEVER THE WORLD'S** (the chill's law) — nothing else in the frame changes rate.
        self.t += dt * self.vit.hasteMult();
        self.vit.tick(dt);
        // THE BILL COMES DUE ON THE WAY OUT: the one stagger nothing hit it for (`hero.tickPoison`'s beat).
        if (self.vit.ailEnded(.berserk) and !self.gone) self.stagger(true);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        self.castCd = mathx.maxF(0, self.castCd - dt);
        self.slingCd = mathx.maxF(0, self.slingCd - dt);
        self.biteCd = mathx.maxF(0, self.biteCd - dt);
        self.dashCd = mathx.maxF(0, self.dashCd - dt);
        self.tailWhip = mathx.approach(self.tailWhip, 0, dt * TAIL_WHIP_DECAY);
        var act: Act = .none;
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                if (self.t >= 0.25) self.decide(d);
            },
            .approach, .reposition => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                moveSpeed = self.approachSpeed(d);
                const moved = moveSpeed * dt;
                const go = self.nav.along(self.moveDir);
                mathx.stepXZ(&self.pos, go, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(go);
                if (self.t >= REPOSITION_DUR) self.decide(d);
            },
            .chop => {
                self.faceToward(hero, dt * 0.35);
                const u = self.t / ZERK_CHOP;
                if (u >= ZERK_HIT_A and u < ZERK_HIT_B) {
                    mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), ZERK_STEP / ((ZERK_HIT_B - ZERK_HIT_A) * ZERK_CHOP) * dt, bounds);
                }
                if (self.t >= ZERK_CHOP) {
                    if (self.chopsLeft > 0) {
                        self.chopsLeft -= 1;
                        self.chopLeftHand = !self.chopLeftHand;
                        self.enter(.chop);
                    } else self.enter(.heave);
                }
            },
            .heave => {
                if (self.t >= ZERK_RECOVER) self.decide(d);
            },
            .dash => {
                self.faceToward(hero, dt * 0.5);
                const want = dashTravel(self.t);
                mathx.stepXZ(&self.pos, self.moveDir, want - self.dashDone, bounds);
                self.dashDone = want;
                self.hop = DASH_RISE * mathx.sinf(dashU(self.t) * std.math.pi);
                if (self.t >= DASH_GATHER + DASH_FLIGHT + DASH_LAND) {
                    self.hop = 0;
                    // RE-MEASURED (it moved), BUT STILL THROUGH THE LEASH: on the raw distance a dash was the one exit that re-engaged a foe walking home, or one that cannot see him.
                    self.decide(foe.senseHero(&self.leash, self.pos, hero, AGGRO_R));
                }
            },
            .cast => {
                self.faceToward(hero, dt * 0.2);
                self.castGlow = mathx.smoothstep(0, 0.85, self.t / CAST_DUR);
                self.emitCastMotes(dt);
                if (self.t >= CAST_DUR) {
                    act = .healed;
                    self.castCd = CAST_CD;
                    self.castGlow = 0;
                    self.decide(d);
                }
            },
            .whirl => {
                self.faceToward(hero, dt);
                self.whirlPh += dt * 3.4;
                self.emitWhirlEmbers(dt);
                if (self.t >= WHIRL_DUR) {
                    act = .{ .sling = self.slingPoint() };
                    self.slingCd = SLING_CD;
                    sfx.world(.kobold_sling, self.pos);
                    self.releaseSparks();
                    self.decide(d);
                }
            },
            .bite => {
                self.faceToward(hero, dt * 0.8);
                if (self.t >= BITE_DUR) {
                    self.biteCd = BITE_CD;
                    self.decide(d);
                }
            },
            .stunlight => if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle),
            .stunheavy => if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle),
            .dead => foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE),
        }

        const gaitSpeed: f32 = if (movedDist > 0) moveSpeed else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.pose();
        self.takeParry();
        self.tryHit(blade);
        return act;
    }

    /// SECONDS BACK FROM THE AXE OR THE JAWS ARRIVING, or null. **THE TWO STROKES THAT HURT, AND NOT THE DASH** — the leap is answered by not being where it lands (the bone knight's HOP rule), and the whirl and the chant are not blows at all. The impact frame is the OPENING of `hurtOpen`'s own window.
    fn toImpact(self: *const Kobold) ?f32 {
        return switch (self.state) {
            .chop => ZERK_CHOP * ZERK_HIT_A - self.t,
            .bite => BITE_DUR * BITE_HIT_A - self.t,
            .idle, .approach, .reposition, .dash, .heave, .cast, .whirl, .stunlight, .stunheavy, .dead => null,
        };
    }

    /// THE INSTANT IT CAN BE CAUGHT IN, and how far out it reaches then — `hurtReach`'s OWN answer, which is already the per-state one, so a stroke the boards could not have met is never offered as one.
    fn parryable(self: *const Kobold) ?f32 {
        if (self.dealt) return null;
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return self.hurtReach();
    }

    /// **THE BOARDS TAKE IT.** `enterStun` already spends `dealt`, which is what stops the rest of the swing still billing through `Warband.update`'s own reach test.
    fn takeParry(self: *Kobold) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        if (self.state == .bite) self.biteCd = BITE_CD;
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    /// **THE BERSERKER RUNS** (owner: always run unless very close, and faster than the other skels). At `WALK_SPEED * 1.22` he closed at 2.07 m/s against a shieldman charging at 2.92 and a greatsword at 2.52. `warrior.approachSpeed`'s shape: run at distance, walk the last stride in.
    pub fn approachSpeed(self: *const Kobold, dist: f32) f32 {
        const base = spec(self.role).speed * self.vit.travelMult();
        if (self.role != .berserker or dist > AGGRO_R or dist <= self.walkInR()) return WALK_SPEED * base;
        return RUN_SPEED * base;
    }
    fn walkInR(self: *const Kobold) f32 {
        return foe.hurtReach(ZERK_REACH, self.scale) + ZERK_WALK_IN * self.scale;
    }

    fn enter(self: *Kobold, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        if (s != .cast) self.castGlow = 0;
        switch (s) {
            .cast => sfx.world(.kobold_cast, self.pos),
            .whirl => sfx.world(.kobold_whirl, self.pos),
            .bite => sfx.world(.kobold_bite, self.pos),
            .heave => sfx.world(.kobold_heave, self.pos),
            .chop => {
                sfx.world(.kobold_chop, self.pos);
                self.tailWhip = TAIL_WHIP_CHOP * (if (self.chopLeftHand) @as(f32, -1.0) else 1.0);
            },
            .dash => {
                self.dashDone = 0;
                self.dashCd = DASH_CD;
                self.dashPhase = self.phase;
                sfx.world(.kobold_snarl, self.pos);
                self.tailWhip = TAIL_WHIP_CHOP;
            },
            else => {},
        }
    }

    fn decide(self: *Kobold, d: f32) void {
        if (d > AGGRO_R) {
            const back = mathx.distXZ(self.pos, self.home);
            if (back > HOME_R) {
                self.moveDir = mathx.dirXZ(self.pos, self.home);
                return self.enter(.reposition);
            }
            return self.enter(.idle);
        }
        const s = spec(self.role);
        switch (self.role) {
            .berserker => {
                if (d <= foe.hurtReach(ZERK_REACH, self.scale)) {
                    self.chopsLeft = ZERK_SWINGS_LO + @as(u32, @intCast(self.fxRng.intn(@intCast(ZERK_SWINGS_HI - ZERK_SWINGS_LO + 1))));
                    self.chopLeftHand = false;
                    sfx.world(.kobold_snarl, self.pos);
                    self.enter(.chop);
                    return;
                }
                self.moveDir = mathx.dirXZ(self.pos, heroAt(self));
                if (self.dashCd <= 0 and foe.canLeap(&self.root) and d > DASH_R_MIN * self.scale and d <= DASH_R_MAX) return self.enter(.dash);
                return self.enter(.approach);
            },
            .priest => {
                if (self.healWanted and self.castCd <= 0) return self.enter(.cast);
                if (d < s.wantMin) {
                    self.moveDir = self.awayDir();
                    return self.enter(.reposition);
                }
                if (d > s.wantMax) {
                    self.moveDir = mathx.scaleV(self.awayDir(), -1);
                    return self.enter(.approach);
                }
                return self.enter(.idle);
            },
            .slinger => {
                if (d <= foe.hurtReach(BITE_PREFER_R, self.scale) and self.biteCd <= 0) return self.enter(.bite);
                if (d < s.wantMin) {
                    self.moveDir = self.awayDir();
                    return self.enter(.reposition);
                }
                if (d > s.wantMax) {
                    self.moveDir = mathx.scaleV(self.awayDir(), -1);
                    return self.enter(.approach);
                }
                if (self.slingCd <= 0) return self.enter(.whirl);
                // The sling is cooling: DRIFT (the archer's reload lesson) — a skirmisher between shots circles his own way, he does not stand on the mark the last clump was thrown from.
                self.moveDir = mathx.headingDir(self.facing + (if (self.seed < 0.5) @as(f32, 1) else -1) * std.math.pi * 0.5);
                return self.enter(.reposition);
            },
        }
    }

    fn heroAt(self: *const Kobold) rl.Vector3 {
        const f = mathx.headingDir(self.facing);
        return v3(self.pos.x + f.x * 4.0, self.pos.y, self.pos.z + f.z * 4.0);
    }

    fn awayDir(self: *const Kobold) rl.Vector3 {
        return mathx.headingDir(self.facing + std.math.pi + (self.seed - 0.5) * 0.8);
    }

    fn emitCastMotes(self: *Kobold, dt: f32) void {
        if (self.fxRng.float() > dt * 34.0) return;
        const head = self.staffTop();
        const a = self.fxRng.angle();
        const r = self.fxRng.range(0.16, 0.42);
        foe.emitPart(&self.parts, &self.fxHead, .{
            .p = v3(head.x + mathx.cosf(a) * r, head.y + self.fxRng.range(-0.2, 0.2), head.z + mathx.sinf(a) * r),
            .v = mathx.scaleV(mathx.dirXZ(v3(head.x + mathx.cosf(a) * r, 0, head.z + mathx.sinf(a) * r), head), 0.9),
            .life = 0.42,
            .r0 = 0.028,
            .r1 = 0.006,
            .col = HEAL_GLOW,
            .grav = -0.4,
            .add = true,
        });
    }

    fn emitWhirlEmbers(self: *Kobold, dt: f32) void {
        const at = self.slingPoint();
        const tangent = mathx.headingDir(self.facing + std.math.pi * 0.5 + self.whirlPh);
        var n: u32 = 0;
        while (n < 2) : (n += 1) {
            if (self.fxRng.float() > dt * 26.0) continue;
            const sp = self.fxRng.range(1.4, 3.2);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + self.fxRng.signed() * 0.05, at.y + self.fxRng.signed() * 0.05, at.z + self.fxRng.signed() * 0.05),
                .v = v3(tangent.x * sp, self.fxRng.range(0.2, 1.1), tangent.z * sp),
                .life = self.fxRng.range(0.30, 0.62),
                .r0 = self.fxRng.range(0.020, 0.036),
                .r1 = 0.004,
                .col = if (self.fxRng.float() < 0.4) EMBER_HOT else EMBER,
                .col1 = EMBER_COOL,
                .grav = 5.5,
                .stretch = 0.040,
                .add = true,
            });
        }
    }

    fn releaseSparks(self: *Kobold) void {
        const at = self.slingPoint();
        const away = mathx.headingDir(self.facing);
        var i: u32 = 0;
        while (i < SLING_SPARKS) : (i += 1) {
            const a = self.fxRng.angle();
            const spread = self.fxRng.range(0.6, 2.4);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * 0.06, at.y + self.fxRng.signed() * 0.06, at.z + mathx.sinf(a) * 0.06),
                .v = v3(
                    away.x * self.fxRng.range(0.8, 3.4) + mathx.cosf(a) * spread,
                    self.fxRng.range(0.4, 2.2),
                    away.z * self.fxRng.range(0.8, 3.4) + mathx.sinf(a) * spread,
                ),
                .life = self.fxRng.range(0.26, 0.60),
                .r0 = self.fxRng.range(0.024, 0.044),
                .r1 = 0.004,
                .col = if (self.fxRng.float() < 0.5) EMBER_HOT else EMBER,
                .col1 = EMBER_COOL,
                .grav = 6.5,
                .stretch = 0.045,
                .add = true,
            });
        }
    }

    pub fn impactSparks(self: *Kobold, at: rl.Vector3) void {
        var i: u32 = 0;
        while (i < CLUMP_SPARKS) : (i += 1) {
            const a = self.fxRng.angle();
            const out = self.fxRng.range(1.2, 4.6);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * 0.08, at.y + self.fxRng.range(0, 0.12), at.z + mathx.sinf(a) * 0.08),
                .v = v3(mathx.cosf(a) * out, self.fxRng.range(1.2, 4.0), mathx.sinf(a) * out),
                .life = self.fxRng.range(0.34, 0.78),
                .r0 = self.fxRng.range(0.026, 0.050),
                .r1 = 0.004,
                .col = if (self.fxRng.float() < 0.55) EMBER_HOT else EMBER,
                .col1 = EMBER_COOL,
                .grav = 7.5,
                .stretch = 0.045,
                .bounce = 0.40,
                .add = true,
            });
        }
    }

    pub fn staffTop(self: *const Kobold) rl.Vector3 {
        return rl.math.vector3Transform(v3(0, STAFF_TOP * H, 0), self.xf[KIT]);
    }

    pub fn healBloom(self: *Kobold, at: rl.Vector3, spread: f32) void {
        var i: u32 = 0;
        while (i < HEAL_BLOOM) : (i += 1) {
            const a = self.fxRng.angle();
            const r = self.fxRng.range(0.05, spread);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * r, at.y + self.fxRng.signed() * spread * 0.7, at.z + mathx.sinf(a) * r),
                .v = v3(mathx.cosf(a) * self.fxRng.range(0.3, 1.1), self.fxRng.range(0.7, 2.0), mathx.sinf(a) * self.fxRng.range(0.3, 1.1)),
                .life = self.fxRng.range(0.55, 1.05),
                .r0 = 0.052,
                .r1 = 0.006,
                .col = HEAL_GLOW,
                .grav = -0.9,
                .add = true,
            });
        }
    }


    fn emitBlood(self: *Kobold, at: rl.Vector3, dir: rl.Vector3) void {
        const parts: u32 = @intCast(@max(0, foe.hitParts(9)));
        var i: u32 = 0;
        while (i < parts) : (i += 1) {
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(dir.x * self.fxRng.range(2.2, 5.4) + self.fxRng.signed() * 2.8, self.fxRng.range(0.8, 3.2), dir.z * self.fxRng.range(2.2, 5.4) + self.fxRng.signed() * 2.8),
                .life = self.fxRng.range(0.45, 0.80),
                .r0 = 0.036,
                .r1 = 0.012,
                .col = BLOOD,
                .col1 = BLOOD_DRY,
                .grav = foe.BLOOD_GRAV,
                .stretch = foe.BLOOD_STRETCH,
                .splat = if (foe.onDryGround(self)) 3.0 else 0,
                .drag = foe.BLOOD_DRAG,
            });
        }
    }

    pub fn drawFx(self: *const Kobold) void {
        foe.drawParticles(&self.parts);
    }

    pub fn tryHit(self: *Kobold, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        _ = foe.wounded(self, s, blade, .{ .light = 1.35, .heavy = 2.1 });
        self.tailWhip = TAIL_WHIP_HURT * (if (self.fxRng.float() < 0.5) @as(f32, -1.0) else 1.0);
        self.emitBlood(s.contact, s.dir);
        sfx.world(.kobold_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.kobold_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enterStun(self: *Kobold, s: State) void {
        if (self.state == .cast) self.castCd = CAST_CD;
        self.state = s;
        self.t = 0;
        self.dealt = true;
        self.chopsLeft = 0;
        self.castGlow = 0;
        self.hop = 0;
    }

    pub fn stagger(self: *Kobold, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Kobold) void {
        self.enterDeath();
    }

    fn enterDeath(self: *Kobold) void {
        self.state = .dead;
        self.t = 0;
        self.dealt = true;
        self.chopsLeft = 0;
        self.castGlow = 0;
        self.hop = 0;
        self.justDied = true;
    }

    /// THE IDLE'S CLOCKS (the wanderer's law): breath, its lagged echo one joint down, and a slow weight rock — every RATE and PHASE dealt off the seed, at rates that never line up. Three identical mannequins PHASE-LOCKED is what a warband at its post read as.
    fn idleSway(self: *const Kobold, m: f32, dk: f32) struct { br: f32, brLag: f32, rock: f32, deal: f32 } {
        const s1 = 0.5 + 0.5 * mathx.sinf(self.seed * 12.98);
        const s2 = 0.5 + 0.5 * mathx.sinf(self.seed * 78.23);
        const amt = (1.0 - mathx.clampF(m * 2.0, 0, 1)) * (1.0 - dk);
        const arg = self.elapsed * (1.05 + 0.4 * s1) + self.seed * 6.28;
        return .{
            .br = mathx.sinf(arg) * amt,
            .brLag = mathx.sinf(arg - 0.7) * amt,
            .rock = mathx.sinf(self.elapsed * (0.42 + 0.2 * s2) + self.seed * 9.4) * amt,
            .deal = s1,
        };
    }

    pub fn pose(self: *Kobold) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = -0.4 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stunAmt = self.stunAmount();

        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const bob = pel.bob;
        const sway = pel.sway;
        const prot = pel.prot;
        const dip = pel.dip;

        var wx: [N]rl.Matrix = undefined;
        const collapse = mathx.lerpF(hipY, 0.16 * H, dk);
        const heave = self.heaveAmt();
        const gather = self.dashGather();
        const fly = self.dashFly();
        const landAbs = self.dashLand();
        const dashLoad = DASH_COIL * gather + DASH_ABSORB * landAbs;
        const crouch = CROUCH_HEAVE * heave + CROUCH_STUN * stunAmt + dashLoad;
        const o = self.idleSway(m, dk);
        // The base skulk is DEALT, not authored (5..9.5 deg): three of one warband stand three ways.
        const slouch = (5.0 + 4.5 * o.deal) + 1.8 * o.br + 4.0 * m + PELVIS_SHARE * (46.0 * heave + BITE_FOLD * self.biteLunge()) +
            16.0 * dk - 14.0 * stunAmt;
        const sag = legSink(crouch);
        const pelvY = if (dead) collapse else hipY + bob + 0.006 * H * o.br - dip - sag;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(8.0 * dk + 1.6 * o.rock), rx(slouch), ry(prot)),
            mul(tr(sway * fs, pelvY * fs + sink + self.hop, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        if (dead) {
            self.legCrumple(&wx, dk);
        } else if (self.state == .dash) {
            const leadL = self.dashLeadIsLeft();
            self.legDash(&wx, dashLoad, fly, leadL, 1.0, HIPL, KNEEL, ANKL);
            self.legDash(&wx, dashLoad, fly, !leadL, -1.0, HIPR, KNEER, ANKR);
        } else if (crouch > 0.5) {
            self.legCrouch(&wx, crouch, 1.0, HIPL, KNEEL, ANKL);
            self.legCrouch(&wx, crouch, -1.0, HIPR, KNEER, ANKR);
        } else {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stunAmt, prot, o);
        self.xf = wx;
        self.poseJaw();
        self.poseTail(dk, stunAmt);
    }

    fn legCrouch(self: *Kobold, wx: *[N]rl.Matrix, crouch: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
        self.legDash(wx, crouch, 0, false, side, hip, knee, ank);
    }

    fn legDash(self: *Kobold, wx: *[N]rl.Matrix, load: f32, fly: f32, lead: bool, side: f32, hip: usize, knee: usize, ank: usize) void {
        const hipA = if (lead) DASH_LEAD_HIP * fly else -DASH_TRAIL_HIP * fly;
        const kneeA = if (lead) DASH_LEAD_KNEE * fly else DASH_TRAIL_KNEE * fly;
        setLocal(wx, hip, self.rest, mul(rx(-(load + hipA)), rz(-side * heromod.HIP_ADDUCT)));
        setLocal(wx, knee, self.rest, rx(heromod.IDLE_KNEE + 2.0 * load + kneeA));
        setLocal(wx, ank, self.rest, mul(rx(-load + DASH_TOE * fly), ry(side * heromod.FOOT_TOEOUT)));
    }

    fn legCrumple(self: *Kobold, wx: *[N]rl.Matrix, dk: f32) void {
        setLocal(wx, HIPL, self.rest, mul(rx(-64.0 * dk), rz(-heromod.HIP_ADDUCT - 16.0 * dk)));
        setLocal(wx, KNEEL, self.rest, rx(heromod.IDLE_KNEE + 96.0 * dk));
        setLocal(wx, ANKL, self.rest, mul(rx(24.0 * dk), ry(heromod.FOOT_TOEOUT)));
        setLocal(wx, HIPR, self.rest, mul(rx(-22.0 * dk), rz(heromod.HIP_ADDUCT + 30.0 * dk)));
        setLocal(wx, KNEER, self.rest, rx(heromod.IDLE_KNEE + 52.0 * dk));
        setLocal(wx, ANKR, self.rest, mul(rx(10.0 * dk), ry(-heromod.FOOT_TOEOUT)));
    }

    fn poseJaw(self: *Kobold) void {
        const a = GAPE_DEG * self.gape();
        self.jawXf = mul(mul3(
            tr(-JAW_PIVOT.x, -JAW_PIVOT.y, -JAW_PIVOT.z),
            rx(a),
            tr(JAW_PIVOT.x, JAW_PIVOT.y, JAW_PIVOT.z),
        ), self.xf[SKULL]);
    }

    fn poseTail(self: *Kobold, dk: f32, stunAmt: f32) void {
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const clamp = (34.0 * stunAmt + 26.0 * dk + 22.0 * self.heaveAmt()) / TAIL_N;
        const swayAmp = (6.0 + 12.0 * m) + self.tailWhip;
        var acc = mul(tr(TAIL_ROOT.x, TAIL_ROOT.y, TAIL_ROOT.z), self.xf[ROOT]);
        for (0..TAIL_N) |i| {
            const fi = @as(f32, @floatFromInt(i));
            const lagPh = self.phase - fi * 0.085;
            const yaw = swayAmp * mathx.sinf(twoPi * lagPh) * (0.45 + 0.16 * fi);
            const pitch = (if (i == 0) TAIL_SET else TAIL_CURL) + clamp + 3.0 * mathx.sinf(twoPi * 2.0 * lagPh) * m;
            acc = mul(mul(rx(-pitch), ry(yaw)), acc);
            self.tailXf[i] = acc;
            acc = mul(tr(0, 0, -TAIL_SEG * H), acc);
        }
    }

    fn stunAmount(self: *const Kobold) f32 {
        return switch (self.state) {
            .stunlight => 1.0 - mathx.smoothstep(0, combat.FOE_LIGHT_STUN_DUR, self.t),
            .stunheavy => 1.0 - 0.45 * mathx.smoothstep(0, combat.FOE_HEAVY_STUN_DUR, self.t),
            else => 0,
        };
    }

    fn heaveAmt(self: *const Kobold) f32 {
        if (self.state != .heave) return 0;
        const u = mathx.clampF(self.t / ZERK_RECOVER, 0, 1);
        return mathx.pulse(u, 0, 0.16, 0.78, 1.0);
    }

    /// THE CHOP'S TRUNK COIL, in degrees of yaw: −1 wound AWAY from the live hand, +1 whipped through past it.
    fn chopTwist(self: *const Kobold) f32 {
        if (self.state != .chop) return 0;
        const u = mathx.clampF(self.t / ZERK_CHOP, 0, 1);
        const coil = 1.0 - mathx.smoothstep(0, ZERK_HIT_A, u);
        const thru = mathx.smoothstep(ZERK_HIT_A, ZERK_HIT_B, u);
        const sgn: f32 = if (self.chopLeftHand) -1.0 else 1.0;
        return sgn * (28.0 * coil - 22.0 * thru);
    }

    fn chopThrow(self: *const Kobold) f32 {
        if (self.state != .chop) return 0;
        const u = mathx.clampF(self.t / ZERK_CHOP, 0, 1);
        return 22.0 * mathx.pulse(u, ZERK_HIT_A * 0.6, ZERK_HIT_B, ZERK_HIT_B, 1.0) -
            9.0 * (1.0 - mathx.smoothstep(0, ZERK_HIT_A, u));
    }

    fn biteLunge(self: *const Kobold) f32 {
        if (self.state != .bite) return 0;
        const u = mathx.clampF(self.t / BITE_DUR, 0, 1);
        return mathx.pulse(u, 0, BITE_HIT_A, BITE_HIT_B, 1.0);
    }

    fn dashGather(self: *const Kobold) f32 {
        if (self.state != .dash) return 0;
        return mathx.pulse(self.t, 0, DASH_GATHER * 0.8, DASH_GATHER, DASH_GATHER + DASH_FLIGHT * 0.22);
    }
    fn dashFly(self: *const Kobold) f32 {
        if (self.state != .dash) return 0;
        return mathx.pulse(dashU(self.t), 0, 0.22, 0.74, 1.0);
    }
    fn dashLand(self: *const Kobold) f32 {
        if (self.state != .dash) return 0;
        const a = DASH_GATHER + DASH_FLIGHT;
        return mathx.pulse(self.t, a - DASH_FLIGHT * 0.18, a + DASH_LAND * 0.25, a + DASH_LAND * 0.45, a + DASH_LAND);
    }
    fn dashLeadIsLeft(self: *const Kobold) bool {
        return heromod.sampleCurve(heromod.HIP_FLEX, self.dashPhase) >
            heromod.sampleCurve(heromod.HIP_FLEX, self.dashPhase + 0.5);
    }

    fn biteCoil(self: *const Kobold) f32 {
        if (self.state != .bite) return 0;
        const u = mathx.clampF(self.t / BITE_DUR, 0, 1);
        const knee = BITE_HIT_A * BITE_COIL_AT;
        return mathx.pulse(u, 0, knee, knee, BITE_HIT_A);
    }

    // AGENTS.md: legs alone are NOT a gait. `o` is pose()'s own idleSway, handed down rather than recomputed.
    fn poseUpper(self: *Kobold, wx: *[N]rl.Matrix, dk: f32, stunAmt: f32, prot: f32, o: anytype) void {
        const twoPi = std.math.tau;
        const ph = self.phase;
        const m = self.moving * (1.0 - dk);
        const heave = self.heaveAmt();

        const nod = 3.6 * mathx.sinf(2.0 * twoPi * ph) * m;
        const counter = -0.62 * prot;
        // THE WAIST TAKES THE FOLD, over knees that pay for it (`legCrouch`). 46 deg through the lumbar and 30
        // more through the chest: the spine leads and the chest follows, which makes it a fold rather than a hinge.
        const lunge = self.biteLunge();
        const coil = self.biteCoil();
        const fold = 46.0 * heave + BITE_FOLD * lunge - BITE_ARCH * coil + DASH_LEAN * self.dashFly();
        const gasp = 9.0 * heave * mathx.sinf(twoPi * 2.4 * self.t);
        const spineExtra = 14.0 * dk - 16.0 * stunAmt;
        const twist = self.chopTwist();
        const throwF = self.chopThrow();
        setLocal(wx, SPINE, self.rest, mul3(
            rx(nod + fold + gasp + 1.7 * o.br + spineExtra * 0.5 + throwF * 0.45),
            ry(counter * 0.45 + twist * 0.40),
            rz(1.4 * mathx.sinf(twoPi * ph) * m + 0.9 * o.rock),
        ));
        setLocal(wx, CHEST, self.rest, mul3(
            rx(nod * 0.6 + 0.65 * fold + gasp * 0.7 + 1.2 * o.brLag + spineExtra * 0.5 + throwF * 0.55),
            ry(counter * 0.55 + twist * 0.60),
            rz(-1.0 * mathx.sinf(twoPi * ph) * m - 0.7 * o.rock),
        ));

        const headYaw = -counter * 0.5 + 6.0 * mathx.sinf(self.elapsed * 0.7 + self.seed * 6.0) * (1.0 - m);
        const headPitch = -3.0 - nod * 0.8 + 34.0 * heave - 52.0 * stunAmt + 26.0 * dk - BITE_GAZE * lunge + 10.0 * coil - throwF * 0.3;
        setLocal(wx, NECK, self.rest, mul(rx(headPitch * 0.45), ry(headYaw * 0.4)));
        setLocal(wx, SKULL, self.rest, mul3(rx(headPitch * 0.55), ry(headYaw * 0.6), rz(-1.8 * mathx.sinf(twoPi * ph) * m)));

        const swing = 22.0 * m;
        const lag = 0.125;
        const shL = -swing * mathx.cosf(twoPi * ph) + 3.0 * o.brLag + 1.2 * o.rock;
        const shR = -swing * mathx.cosf(twoPi * (ph + 0.5)) - 2.4 * o.brLag + 1.5 * o.rock;
        const elL = 24.0 + 24.0 * mathx.maxF(0, -mathx.cosf(twoPi * (ph - lag))) * m + 4.5 * mathx.maxF(0, o.br);
        const elR = 24.0 + 24.0 * mathx.maxF(0, -mathx.cosf(twoPi * (ph + 0.5 - lag))) * m + 3.2 * mathx.maxF(0, -o.br);
        const abd = 13.0;

        switch (self.role) {
            .berserker => self.poseZerk(wx, shL, shR, elL, elR, abd, heave, dk, stunAmt),
            .priest => self.posePriest(wx, shL, shR, elL, elR, abd, dk, stunAmt),
            .slinger => self.poseSlinger(wx, shL, shR, elL, elR, abd, dk, stunAmt),
        }
    }

    fn poseZerk(self: *Kobold, wx: *[N]rl.Matrix, shL: f32, shR: f32, elL: f32, elR: f32, abd: f32, heave: f32, dk: f32, stunAmt: f32) void {
        var aL = shL;
        var aR = shR;
        var eL = elL;
        var eR = elR;
        if (self.state == .chop) {
            const u = mathx.clampF(self.t / ZERK_CHOP, 0, 1);
            const raise = 1.0 - mathx.smoothstep(0, ZERK_HIT_A, u);
            const fall = mathx.smoothstep(ZERK_HIT_A, ZERK_HIT_B, u);
            const live = -150.0 * raise + 55.0 * fall;
            const idleArm = 34.0 * mathx.smoothstep(ZERK_HIT_B, 1.0, u);
            if (self.chopLeftHand) {
                aL = live;
                eL = 96.0 * raise + 12.0 * fall;
                aR = -70.0 - idleArm;
                eR = 74.0;
            } else {
                aR = live;
                eR = 96.0 * raise + 12.0 * fall;
                aL = -70.0 - idleArm;
                eL = 74.0;
            }
        } else if (heave > 0.01) {
            const swingLoose = 9.0 * heave * mathx.sinf(std.math.tau * 1.2 * self.t);
            aL = 30.0 * heave + swingLoose;
            aR = 30.0 * heave - swingLoose;
            eL = 18.0 + 14.0 * heave;
            eR = 18.0 + 14.0 * heave;
        } else if (self.state == .dash) {
            const f = self.dashFly();
            aL = 26.0 + DASH_ARM_BACK * f;
            aR = 26.0 + DASH_ARM_BACK * f * 0.82;
            eL = 30.0 + 46.0 * f;
            eR = 30.0 + 38.0 * f;
        }
        // ARMS FLY UP ON A HIT, and REACTIONS ARE HUGE (owner's law) — 30 deg was a shrug.
        const flail = 52.0 * stunAmt + 40.0 * dk;
        setLocal(wx, SHL, self.rest, mul3(rx(aL - flail * 0.78), ry(-8.0 - 14.0 * stunAmt), rz(abd + 20.0 * stunAmt)));
        setLocal(wx, ELL, self.rest, rx(-eL - 18.0 * stunAmt));
        setLocal(wx, WRL, self.rest, rx(-8.0));
        setLocal(wx, SHR, self.rest, mul3(rx(aR - flail), ry(8.0 + 18.0 * stunAmt), rz(-abd - 26.0 * stunAmt)));
        setLocal(wx, ELR, self.rest, rx(-eR - 26.0 * stunAmt));
        setLocal(wx, WRR, self.rest, rx(-8.0));
        setLocal(wx, KIT, self.rest, rl.math.matrixIdentity());
    }

    fn posePriest(self: *Kobold, wx: *[N]rl.Matrix, shL: f32, shR: f32, elL: f32, elR: f32, abd: f32, dk: f32, stunAmt: f32) void {
        const c = if (self.state == .cast) mathx.smoothstep(0, 0.55, self.t / CAST_DUR) else 0;
        const flail = 28.0 * stunAmt + 20.0 * dk;
        const aR = mathx.lerpF(shR - 14.0, -112.0, c);
        const eR = mathx.lerpF(elR, 34.0, c);
        const aL = mathx.lerpF(shL, -74.0, c);
        const eL = mathx.lerpF(elL, 82.0, c);
        setLocal(wx, SHL, self.rest, mul3(rx(aL - flail * 0.78), ry(mathx.lerpF(-6.0, -34.0, c)), rz(abd * (1.0 - 0.5 * c) + 18.0 * stunAmt)));
        setLocal(wx, ELL, self.rest, rx(-eL - 16.0 * stunAmt));
        setLocal(wx, WRL, self.rest, rx(-6.0));
        setLocal(wx, SHR, self.rest, mul3(rx(aR - flail), ry(mathx.lerpF(6.0, 16.0, c)), rz(-abd * (1.0 - 0.4 * c) - 24.0 * stunAmt)));
        setLocal(wx, ELR, self.rest, rx(-eR - 22.0 * stunAmt));
        setLocal(wx, WRR, self.rest, rx(-10.0 - 16.0 * c));
        setLocal(wx, KIT, self.rest, rx(mathx.lerpF(24.0, -18.0, c)));
    }

    fn poseSlinger(self: *Kobold, wx: *[N]rl.Matrix, shL: f32, shR: f32, elL: f32, elR: f32, abd: f32, dk: f32, stunAmt: f32) void {
        var aR = shR;
        var eR = elR;
        var yR: f32 = 8.0;
        if (self.state == .whirl) {
            const w = self.whirlPh * std.math.tau;
            aR = -118.0 + 22.0 * mathx.sinf(w);
            yR = 34.0 * mathx.cosf(w);
            eR = 26.0;
        }
        var aL = shL;
        var eL = elL;
        const snap = self.biteLunge();
        if (self.state == .bite) {
            aR = shR + BITE_ARM_BACK * snap;
            eR = elR + 34.0 * snap;
            aL = shL + BITE_ARM_BACK * snap;
            eL = elL + 34.0 * snap;
        }
        const flail = 46.0 * stunAmt + 36.0 * dk;
        setLocal(wx, SHL, self.rest, mul3(rx(aL - flail * 0.78), ry(-6.0 - 12.0 * stunAmt), rz(abd + 18.0 * stunAmt - BITE_ARM_TUCK * snap)));
        setLocal(wx, ELL, self.rest, rx(-eL - 16.0 * stunAmt));
        setLocal(wx, WRL, self.rest, rx(-6.0));
        setLocal(wx, SHR, self.rest, mul3(rx(aR - flail), ry(yR + 16.0 * stunAmt), rz(-abd - 24.0 * stunAmt + BITE_ARM_TUCK * snap)));
        setLocal(wx, ELR, self.rest, rx(-eR - 22.0 * stunAmt));
        setLocal(wx, WRR, self.rest, rx(-8.0));
        setLocal(wx, KIT, self.rest, rx(if (self.state == .whirl) -40.0 else 10.0));
    }

    pub fn gape(self: *const Kobold) f32 {
        if (self.state == .bite) return self.biteLunge();
        if (self.state == .chop) {
            const u = mathx.clampF(self.t / ZERK_CHOP, 0, 1);
            return 0.62 * mathx.pulse(u, 0, ZERK_HIT_A, ZERK_HIT_B, 1.0);
        }
        if (self.state == .dash) return 0.75 * mathx.sinf(dashU(self.t) * std.math.pi);
        if (self.state == .heave) return 0.85 * self.heaveAmt();
        if (self.state == .stunlight or self.state == .stunheavy) return 0.7 * self.stunAmount();
        if (self.state == .dead) return 0.55 * mathx.smoothstep(0, 0.3, self.t / DEATH_DUR);
        return 0;
    }

    pub fn draw(self: *const Kobold, model: *const Model) void {
        model.draw(self);
    }
};


const STAND_PELT: f32 = 0.20;
const STAND_MANE: f32 = 0.34;

fn furInto(b: *Builder, a: rl.Vector3, bb: rl.Vector3, r: f32, n: i32, rng: *mathx.Rng, col: rl.Color, stand: f32) void {
    const axis = mathx.normV(mathx.subV(bb, a));
    const seed = if (@abs(axis.y) < 0.99) v3(0, 1, 0) else v3(1, 0, 0);
    const u = mathx.normV(mathx.crossV(axis, seed));
    const w = mathx.normV(mathx.crossV(axis, u));
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = rng.range(0.10, 0.94);
        const p = mathx.lerpV(a, bb, t);
        const ang = rng.angle();
        const dir = mathx.addV(mathx.scaleV(u, mathx.cosf(ang)), mathx.scaleV(w, mathx.sinf(ang)));
        const thick = r * rng.range(0.20, 0.32);
        const c = mathx.addV(p, mathx.scaleV(dir, r * (1.0 + stand) - thick));
        const half = r * rng.range(0.30, 0.62) * (1.0 + stand);
        const lie = mathx.normV(mathx.addV(mathx.scaleV(axis, rng.range(0.6, 1.0)), mathx.scaleV(dir, rng.signed() * 0.45)));
        b.addCapsule(
            mathx.addV(c, mathx.scaleV(lie, -half)),
            mathx.addV(c, mathx.scaleV(lie, half)),
            thick,
            thick * rng.range(0.45, 0.75),
            6,
            col,
        );
    }
}

const SNOUT_LEN = 0.070;
const SNOUT_DROP = 0.014;
const JAW_PIVOT = v3(0, 0.020 * H, -0.006 * H);
const GAPE_DEG: f32 = 34.0;

fn skullMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4B0B01D);
    const s = H;
    b.addBlob(v3(0, 0.032 * s, 0.004 * s), v3(0.066 * s, 0.058 * s, 0.070 * s), 5, 9, FUR);
    b.addBlob(v3(0, 0.020 * s, -0.040 * s), v3(0.054 * s, 0.048 * s, 0.040 * s), 4, 8, FUR_DK);
    b.addCapsule(v3(-0.050 * s, 0.044 * s, 0.044 * s), v3(0.050 * s, 0.044 * s, 0.044 * s), 0.017 * s, 0.017 * s, 7, FUR_LT);
    for ([_]f32{ -1, 1 }) |side| {
        b.addBlob(v3(side * 0.044 * s, 0.016 * s, 0.022 * s), v3(0.024 * s, 0.026 * s, 0.030 * s), 4, 7, FUR);
    }
    const noseZ = (0.040 + SNOUT_LEN) * s;
    b.addCapsule(v3(0, 0.024 * s, 0.040 * s), v3(0, 0.024 * s - SNOUT_DROP * s, noseZ), 0.040 * s, 0.030 * s, 9, MUZZLE);
    b.addCapsule(v3(0, 0.042 * s, 0.046 * s), v3(0, 0.036 * s - SNOUT_DROP * s, noseZ - 0.004 * s), 0.024 * s, 0.017 * s, 7, FUR_DK);
    b.addBlob(v3(0, 0.028 * s - SNOUT_DROP * s, noseZ + 0.006 * s), v3(0.022 * s, 0.018 * s, 0.014 * s), 3, 7, NOSE);
    for ([_]f32{ -1, 1 }) |side| {
        b.addBlob(v3(side * 0.020 * s, 0.008 * s - SNOUT_DROP * s * 0.5, noseZ - 0.030 * s), v3(0.0062 * s, 0.015 * s, 0.0062 * s), 2, 5, TOOTH);
        b.addBlob(v3(side * 0.015 * s, 0.012 * s - SNOUT_DROP * s * 0.5, noseZ - 0.014 * s), v3(0.0042 * s, 0.009 * s, 0.0042 * s), 2, 4, TOOTH);
    }
    for ([_]f32{ -1, 1 }) |side| {
        b.addBlob(v3(side * 0.034 * s, 0.038 * s, 0.050 * s), v3(0.0210 * s, 0.0200 * s, 0.0140 * s), 3, 7, EYE);
    }
    for ([_]f32{ -1, 1 }) |side| {
        const lean: f32 = if (side < 0) 14.0 else -22.0;
        const hgt: f32 = if (side < 0) 0.092 else 0.080;
        const baseX = side * 0.036 * s;
        const tipX = baseX + side * 0.024 * s + mathx.sinf(mathx.radians(lean)) * 0.016 * s;
        const baseY = 0.036;
        b.addBlob(v3((baseX + tipX) * 0.5, (baseY + hgt * 0.5) * s, -0.018 * s), v3(0.026 * s, hgt * 0.5 * s, 0.013 * s), 4, 7, FUR);
        b.addBlob(v3((baseX + tipX) * 0.5, (baseY + hgt * 0.48) * s, -0.012 * s), v3(0.015 * s, hgt * 0.38 * s, 0.006 * s), 3, 6, EAR_IN);
    }
    furInto(&b, v3(-0.036 * s, 0.004 * s, -0.026 * s), v3(0.036 * s, 0.004 * s, -0.026 * s), 0.040 * s, 16, &rng, FUR, STAND_MANE);
    for ([_]f32{ -1, 1 }) |side| {
        furInto(&b, v3(side * 0.040 * s, 0.030 * s, 0.010 * s), v3(side * 0.050 * s, 0.000 * s, -0.030 * s), 0.026 * s, 9, &rng, FUR_DK, STAND_MANE);
    }
    return b.toMesh();
}

fn jawMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x9A4);
    const s = H;
    const noseZ = (0.040 + SNOUT_LEN) * s;
    b.addCapsule(v3(0, 0.004 * s, 0.036 * s), v3(0, 0.002 * s - SNOUT_DROP * s * 0.7, noseZ - 0.018 * s), 0.028 * s, 0.019 * s, 8, MUZZLE);
    b.addBlob(v3(0, 0.010 * s, 0.006 * s), v3(0.030 * s, 0.020 * s, 0.026 * s), 4, 7, FUR_DK);
    for ([_]f32{ -1, 1 }) |side| {
        b.addBlob(v3(side * 0.018 * s, 0.016 * s, noseZ - 0.034 * s), v3(0.0058 * s, 0.014 * s, 0.0058 * s), 2, 5, TOOTH);
        b.addBlob(v3(side * 0.013 * s, 0.014 * s, noseZ - 0.020 * s), v3(0.0040 * s, 0.008 * s, 0.0040 * s), 2, 4, TOOTH);
    }
    furInto(&b, v3(-0.020 * s, 0.000 * s, 0.010 * s), v3(0.020 * s, 0.000 * s, 0.010 * s), 0.022 * s, 6, &rng, FUR_DK, STAND_PELT);
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4EC0);
    const s = H;
    b.addCapsule(v3(0, 0, 0), v3(0, 0.048 * s, 0.010 * s), 0.050 * s, 0.044 * s, 8, FUR);
    furInto(&b, v3(0, 0.004 * s, -0.006 * s), v3(0, 0.046 * s, -0.006 * s), 0.058 * s, 34, &rng, FUR, STAND_MANE);
    furInto(&b, v3(0, 0.010 * s, -0.016 * s), v3(0, 0.040 * s, -0.016 * s), 0.062 * s, 26, &rng, FUR_DK, STAND_MANE);
    furInto(&b, v3(-0.062 * s, 0.006 * s, -0.010 * s), v3(0.062 * s, 0.006 * s, -0.010 * s), 0.034 * s, 22, &rng, FUR_LT, STAND_MANE);
    return b.toMesh();
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xBE17);
    const s = H;
    b.addBlob(v3(0, 0.014 * s, 0), v3(0.092 * s, 0.066 * s, 0.076 * s), 5, 9, FUR);
    b.addCube(v3(0, 0.030 * s, 0), v3(0.170 * s, 0.026 * s, 0.132 * s), HIDE);
    b.addCube(v3(0, 0.030 * s, 0.070 * s), v3(0.044 * s, 0.034 * s, 0.014 * s), HIDE_LT);
    furInto(&b, v3(-0.062 * s, 0.006 * s, -0.028 * s), v3(0.062 * s, 0.006 * s, -0.028 * s), 0.050 * s, 14, &rng, FUR_DK, STAND_PELT);
    return b.toMesh();
}

fn loinMesh(r: Role) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xBE17);
    const s = H;
    const col = fabric(r);
    b.setMat(.cloth);
    for ([_]f32{ 1, -1 }) |sz| {
        const zf = sz * 0.062 * s;
        b.addCube(v3(0, -0.006 * s, zf), v3(0.150 * s, 0.086 * s, 0.026 * s), col[0]);
        var i: i32 = 0;
        while (i < 8) : (i += 1) {
            if (rng.float() < 0.14) continue;
            const rx0 = (@as(f32, @floatFromInt(i)) - 3.5) * 0.036 * s;
            const drop = rng.range(0.030, 0.086) * s;
            b.addCube(
                v3(rx0 + rng.signed() * 0.006 * s, -0.048 * s - drop * 0.5, zf + rng.signed() * 0.004 * s),
                v3(0.030 * s, drop, 0.020 * s),
                if (rng.float() < 0.4) col[1] else col[0],
            );
        }
    }
    return b.toMesh();
}

fn hatMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A7);
    const s = H;
    const col = fabric(.priest);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.052 * s, 0.006 * s), v3(0.062 * s, 0.012 * s, 0.062 * s), 4, 9, col[1]);
    const TIERS = 7;
    var i: i32 = 0;
    while (i < TIERS) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, TIERS - 1);
        const leanX = 0.084 * t * t * s;
        const leanZ = 0.030 * t * t * s;
        const y = (0.058 + 0.106 * t) * s;
        const r = (0.050 * (1.0 - t) + 0.006) * s;
        b.addBlob(
            v3(leanX + rng.signed() * 0.004 * s, y, leanZ + rng.signed() * 0.004 * s),
            v3(r, 0.020 * s, r),
            4,
            8,
            if (@rem(i, 2) == 0) col[0] else col[1],
        );
    }
    b.addBlob(v3(-0.058 * s, 0.030 * s, 0.020 * s), v3(0.008 * s, 0.016 * s, 0.008 * s), 3, 5, TOOTH);
    return b.toMesh();
}

fn robeMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x0BE);
    const s = H;
    const col = fabric(.priest);
    b.setMat(.cloth);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const k = @as(f32, @floatFromInt(i)) / 6.0;
        const y = (0.10 - 0.34 * k) * s;
        const wide = (0.098 + 0.052 * k) * s;
        b.addCube(
            v3(rng.signed() * 0.006 * s, y, rng.signed() * 0.005 * s),
            v3(wide * 2.0, 0.062 * s, (0.086 + 0.030 * k) * s),
            if (@rem(i, 2) == 0) col[0] else col[1],
        );
    }
    b.addBlob(v3(0, 0.108 * s, -0.062 * s), v3(0.082 * s, 0.062 * s, 0.070 * s), 4, 8, col[1]);
    b.addBlob(v3(0, 0.126 * s, -0.020 * s), v3(0.094 * s, 0.034 * s, 0.078 * s), 4, 8, col[0]);
    var k2: i32 = 0;
    while (k2 < 11) : (k2 += 1) {
        if (rng.float() < 0.18) continue;
        const a = std.math.tau * (@as(f32, @floatFromInt(k2)) + rng.signed() * 0.3) / 11.0;
        const r = 0.140 * s;
        const drop = rng.range(0.034, 0.108) * s;
        b.addCube(
            v3(mathx.cosf(a) * r, -0.252 * s - drop * 0.5, mathx.sinf(a) * r * 0.72),
            v3(0.042 * s, drop, 0.030 * s),
            if (rng.float() < 0.45) CLOTH_DK else CLOTH,
        );
    }
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x10BA);
    const s = H;
    b.addBlob(v3(0, 0.058 * s, -0.004 * s), v3(0.116 * s, 0.070 * s, 0.116 * s), 5, 9, FUR);
    furInto(&b, v3(0, 0.014 * s, -0.062 * s), v3(0, 0.100 * s, -0.062 * s), 0.064 * s, 22, &rng, FUR_DK, STAND_PELT);
    return b.toMesh();
}

fn ribcageMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x21BC);
    const s = H;
    const rib = RIB_HALF;
    b.addBlob(v3(0, 0.020 * s, 0.002 * s), v3(rib * s, 0.100 * s, 0.158 * s), 5, 9, FUR);
    b.addBlob(v3(0, -0.030 * s, 0.004 * s), v3((rib - 0.014) * s, 0.058 * s, 0.140 * s), 4, 8, FUR_DK);
    b.addBox(v3(0.042 * s, 0.020 * s, 0.074 * s), v3(0.034 * s, 0.104 * s, 0.007 * s), v3(-0.038 * s, 0.012 * s, 0), v3(0, 0, 0.012 * s), HIDE);
    furInto(&b, v3(-0.150 * s, 0.086 * s, -0.040 * s), v3(0.150 * s, 0.086 * s, -0.040 * s), 0.064 * s, 26, &rng, FUR_LT, STAND_MANE);
    furInto(&b, v3(0, -0.020 * s, -0.078 * s), v3(0, 0.076 * s, -0.078 * s), 0.058 * s, 16, &rng, FUR_DK, STAND_PELT);
    return b.toMesh();
}

const TAIL_N = 5;
const TAIL_SEG = 0.062;
const TAIL_ROOT = v3(0, 0.026 * H, -0.062 * H);
const TAIL_SET: f32 = 20.0;
const TAIL_CURL: f32 = 15.0;
const TAIL_R0 = 0.034;
const TAIL_R1 = 0.011;
const TAIL_WHIP_DECAY = 90.0;
const TAIL_WHIP_CHOP = 34.0;
const TAIL_WHIP_HURT = 52.0;

fn tailMesh(i: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x7A11 + i * 977);
    const s = H;
    const k0 = @as(f32, @floatFromInt(i)) / TAIL_N;
    const k1 = @as(f32, @floatFromInt(i + 1)) / TAIL_N;
    const r0 = mathx.lerpF(TAIL_R0, TAIL_R1, k0) * s;
    const r1 = mathx.lerpF(TAIL_R0, TAIL_R1, k1) * s;
    const a = mathx.zero3;
    const bb = v3(rng.signed() * 0.004 * s, rng.signed() * 0.003 * s, -TAIL_SEG * s);
    b.addCapsule(a, bb, r0, r1, 8, if (i % 2 == 0) FUR else FUR_DK);
    furInto(&b, a, bb, r0, 7 + @as(i32, @intCast(i)), &rng, if (i >= TAIL_N - 2) FUR else FUR_DK, STAND_MANE);
    return b.toMesh();
}

fn limbMesh(seed: u64, len: f32, r0: f32, r1: f32, col: rl.Color, tufts: i32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    const kink = rng.signed() * 0.006 * s;
    const a = v3(0, 0, 0);
    const bb = v3(kink, -len * s, rng.signed() * 0.005 * s);
    b.addCapsule(a, bb, r0 * s, r1 * s, 8, col);
    furInto(&b, a, bb, r0 * s, tufts, &rng, if (rng.float() < 0.4) col else FUR_DK, STAND_PELT);
    return b.toMesh();
}

fn handMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    b.addBlob(v3(0, -0.020 * s, 0.004 * s), v3(0.025 * s, 0.028 * s, 0.019 * s), 3, 7, FUR);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const fx = (@as(f32, @floatFromInt(i)) - 1.5) * 0.0125 * s;
        const fl = 0.024 * s * rng.range(0.85, 1.15);
        const tip = v3(fx, -0.044 * s - fl, 0.012 * s);
        b.addCapsule(v3(fx, -0.038 * s, 0.008 * s), tip, 0.0060 * s, 0.0046 * s, 5, MUZZLE);
        b.addBlob(v3(tip.x, tip.y - 0.004 * s, tip.z + 0.004 * s), v3(0.0038 * s, 0.007 * s, 0.0038 * s), 2, 4, CLAW);
    }
    return b.toMesh();
}

fn footMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    b.addBlob(v3(0, -0.031 * s, 0.073 * s), v3(0.047 * s, 0.017 * s, 0.116 * s), 4, 8, FUR_DK);
    b.addCapsule(v3(0, -0.017 * s, -0.033 * s), v3(0, -0.017 * s, 0.035 * s), 0.031 * s, 0.035 * s, 7, FUR);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const fx = (@as(f32, @floatFromInt(i)) - 1.0) * 0.028 * s;
        const tipZ = (0.177 + rng.range(0.0, 0.026)) * s;
        b.addCapsule(v3(fx, -0.035 * s, 0.118 * s), v3(fx, -0.038 * s, tipZ), 0.014 * s, 0.011 * s, 6, FUR_DK);
        b.addBlob(v3(fx, -0.038 * s, tipZ + 0.009 * s), v3(0.006 * s, 0.006 * s, 0.012 * s), 2, 5, CLAW);
    }
    b.addBlob(v3(0, -0.033 * s, -0.031 * s), v3(0.035 * s, 0.014 * s, 0.024 * s), 3, 6, MUZZLE);
    b.addCube(v3(0, 0.007 * s, 0.007 * s), v3(0.066 * s, 0.019 * s, 0.059 * s), HIDE);
    return b.toMesh();
}


const AXE_HAFT = 0.250;
const STAFF_TOP = 0.340;
const SLING_LEN = 0.190;

fn axeMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    const grip = v3(0, -0.05 * s, 0.006 * s);
    const headY = grip.y + AXE_HAFT * s;
    b.addCylinder(v3(grip.x, grip.y - 0.048 * s, grip.z), v3(grip.x, headY, grip.z + 0.020 * s), 0.0145 * s, 0.0120 * s, 8, HAFT);
    b.addDome(v3(grip.x, grip.y - 0.048 * s, grip.z), v3(0, -1, 0), 0.0145 * s, 8, HAFT);
    b.addCube(v3(grip.x, grip.y - 0.006 * s, grip.z), v3(0.032 * s, 0.042 * s, 0.032 * s), HIDE);
    const bx = 0.056 * s * rng.range(0.9, 1.1);
    b.addBox(v3(grip.x + bx * 0.5, headY - 0.006 * s, grip.z + 0.022 * s), v3(bx, 0.010 * s, 0), v3(0, 0.082 * s, 0.006 * s), v3(0, 0, 0.020 * s), IRON);
    b.addBox(v3(grip.x + bx * 1.0, headY - 0.006 * s, grip.z + 0.022 * s), v3(0.018 * s, 0.005 * s, 0), v3(0, 0.068 * s, 0), v3(0, 0, 0.014 * s), IRON_LT);
    b.addCapsule(v3(grip.x - 0.006 * s, headY - 0.024 * s, grip.z + 0.014 * s), v3(grip.x + 0.010 * s, headY + 0.034 * s, grip.z + 0.026 * s), 0.0115 * s, 0.0115 * s, 7, HIDE_LT);
    return b.toMesh();
}

fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x57AFF);
    const s = H;
    const grip = v3(0, -0.05 * s, 0.006 * s);
    var prev = v3(grip.x, grip.y - 0.115 * s, grip.z);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const k = (@as(f32, @floatFromInt(i)) + 1.0) / 6.0;
        const nxt = v3(
            grip.x + mathx.sinf(k * 2.6) * 0.012 * s,
            grip.y - 0.115 * s + (STAFF_TOP + 0.115) * s * k,
            grip.z + mathx.sinf(k * 1.7 + 1.0) * 0.008 * s,
        );
        b.addCapsule(prev, nxt, (0.0140 - 0.0026 * k) * s, (0.0137 - 0.0026 * k) * s, 8, HAFT);
        prev = nxt;
    }
    b.addDome(v3(grip.x, grip.y - 0.115 * s, grip.z), v3(0, -1, 0), 0.0140 * s, 8, HAFT);
    for ([_]f32{ -1, 1 }) |side| {
        b.addCapsule(prev, v3(prev.x + side * 0.032 * s, prev.y + 0.042 * s, prev.z + 0.010 * s), 0.0095 * s, 0.0062 * s, 6, HAFT);
    }
    b.addBlob(v3(prev.x, prev.y + 0.030 * s, prev.z + 0.006 * s), v3(0.021 * s, 0.025 * s, 0.021 * s), 4, 8, HEAL_GLOW);
    var k: i32 = 0;
    while (k < 4) : (k += 1) {
        const hy = prev.y - rng.range(0.03, 0.10) * s;
        const hx = prev.x + rng.signed() * 0.016 * s;
        b.addCapsule(v3(hx, hy, prev.z), v3(hx + rng.signed() * 0.008 * s, hy - 0.030 * s, prev.z + rng.signed() * 0.006 * s), 0.0026 * s, 0.0022 * s, 4, HIDE_LT);
        b.addBlob(v3(hx, hy - 0.036 * s, prev.z), v3(0.0078 * s, 0.0135 * s, 0.0058 * s), 2, 5, BONE_CHARM);
    }
    b.addCube(v3(grip.x, grip.y, grip.z), v3(0.030 * s, 0.044 * s, 0.030 * s), HIDE);
    return b.toMesh();
}

fn slingMesh() rl.Mesh {
    var b = Builder.init();
    const s = H;
    const grip = v3(0, -0.05 * s, 0.006 * s);
    const pouch = v3(grip.x, grip.y, grip.z + SLING_LEN * s);
    for ([_]f32{ -1, 1 }) |side| {
        b.addCapsule(
            v3(grip.x + side * 0.009 * s, grip.y, grip.z),
            v3(pouch.x + side * 0.015 * s, pouch.y, pouch.z - 0.022 * s),
            0.0032 * s,
            0.0028 * s,
            5,
            SLING_CORD,
        );
    }
    b.addBlob(pouch, v3(0.024 * s, 0.015 * s, 0.021 * s), 4, 7, HIDE);
    const lump = v3(pouch.x, pouch.y + 0.008 * s, pouch.z);
    b.addBlob(lump, v3(0.014 * s, 0.013 * s, 0.014 * s), 3, 6, CLUMP_CHAR);
    b.addBlob(lump, v3(0.017 * s, 0.017 * s, 0.017 * s), 3, 8, EMBER_CORE);
    b.setMat(.flame);
    b.setAnimY(lump.y);
    b.addBlob(v3(lump.x, lump.y + 0.016 * s, lump.z), v3(0.014 * s, 0.026 * s, 0.014 * s), 3, 7, propart.FLAME_MID);
    b.setMat(.plain);
    b.addCube(grip, v3(0.030 * s, 0.038 * s, 0.030 * s), HIDE_LT);
    return b.toMesh();
}

const CLUMP_TONGUES = 8;
pub fn clumpMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x570E);
    b.addBlob(mathx.zero3, v3(0.055 * rng.range(0.9, 1.2), 0.050 * rng.range(0.9, 1.2), 0.058), 4, 7, CLUMP_CHAR);
    b.addBlob(mathx.zero3, v3(0.062, 0.058, 0.065), 3, 8, EMBER_CORE);
    b.setMat(.flame);
    b.setAnimY(0);
    b.addBlob(mathx.zero3, v3(0.082, 0.078, 0.086), 3, 9, propart.COAL);
    var t: i32 = 0;
    while (t < CLUMP_TONGUES) : (t += 1) {
        const a = rng.angle();
        const p = rng.range(-0.9, 0.9);
        const len = rng.range(0.055, 0.135);
        const w = rng.range(0.016, 0.028);
        const dir = v3(mathx.cosf(a) * (1.0 - @abs(p)), p, mathx.sinf(a) * (1.0 - @abs(p)));
        const root = mathx.scaleV(dir, 0.045);
        b.addCapsule(root, mathx.scaleV(dir, 0.045 + len * 0.55), w, w * 0.80, 7, if (rng.float() < 0.5) propart.FLAME_MID else propart.FLAME_TIP);
        b.addCapsule(mathx.scaleV(dir, 0.045 + len * 0.52), mathx.scaleV(dir, 0.045 + len), w * 0.78, w * 0.22, 6, propart.FLAME_TIP);
    }
    return b.toModel(shader);
}

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = ribcageMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = skullMesh();
    mesh[HIPL] = limbMesh(0x7401, SEG_THIGH, 0.076, 0.058, FUR, 22);
    mesh[KNEEL] = limbMesh(0x7402, SEG_SHANK, 0.056, 0.039, FUR, 19);
    mesh[ANKL] = footMesh(0x7403);
    mesh[HIPR] = limbMesh(0x7404, SEG_THIGH, 0.076, 0.058, FUR, 22);
    mesh[KNEER] = limbMesh(0x7405, SEG_SHANK, 0.056, 0.039, FUR, 19);
    mesh[ANKR] = footMesh(0x7406);
    mesh[SHL] = limbMesh(0x7407, SEG_UPARM, 0.055, 0.044, FUR, 19);
    mesh[ELL] = limbMesh(0x7408, SEG_FOREARM, 0.044, 0.033, FUR, 20);
    mesh[WRL] = handMesh(0x7409);
    mesh[SHR] = limbMesh(0x740A, SEG_UPARM, 0.055, 0.044, FUR, 19);
    mesh[ELR] = limbMesh(0x740B, SEG_FOREARM, 0.044, 0.033, FUR, 20);
    mesh[WRR] = handMesh(0x740C);
    var empty = Builder.init();
    empty.addBlob(mathx.zero3, v3(0.0001, 0.0001, 0.0001), 2, 3, FUR);
    mesh[KIT] = empty.toMesh();
    return mesh;
}

pub const Model = struct {
    mesh: [N]rl.Mesh,
    kit: [SPEC.len]rl.Mesh,
    offAxe: rl.Mesh,
    jaw: rl.Mesh,
    robe: rl.Mesh,
    hat: rl.Mesh,
    loin: [SPEC.len]rl.Mesh,
    tail: [TAIL_N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "kobold");
        var tail: [TAIL_N]rl.Mesh = undefined;
        for (0..TAIL_N) |i| tail[i] = tailMesh(i);
        return .{
            .mesh = buildMeshes(),
            .kit = [SPEC.len]rl.Mesh{ axeMesh(0xA7E1), staffMesh(), slingMesh() },
            .offAxe = axeMesh(0xA7E2),
            .jaw = jawMesh(),
            .robe = robeMesh(),
            .hat = hatMesh(),
            .loin = [SPEC.len]rl.Mesh{ loinMesh(.berserker), loinMesh(.priest), loinMesh(.slinger) },
            .tail = tail,
            .mat = mat,
        };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Kobold) void {
        for (0..N) |i| {
            if (i == KIT) continue;
            rl.drawMesh(self.mesh[i], self.mat, k.xf[i]);
        }
        rl.drawMesh(self.jaw, self.mat, k.jawXf);
        for (0..TAIL_N) |i| rl.drawMesh(self.tail[i], self.mat, k.tailXf[i]);
        rl.drawMesh(self.loin[@intFromEnum(k.role)], self.mat, k.xf[ROOT]);
        if (k.role == .priest) {
            rl.drawMesh(self.robe, self.mat, k.xf[SPINE]);
            rl.drawMesh(self.hat, self.mat, k.xf[SKULL]);
        }
        rl.drawMesh(self.kit[@intFromEnum(k.role)], self.mat, k.xf[KIT]);
        if (k.role == .berserker) {
            rl.drawMesh(self.offAxe, self.mat, mul(mathx.scaleM(-1, 1, 1), k.xf[WRL]));
        }
    }
};


pub const CAP = SPEC.len * wf.MAX_PER_KIND;

pub const Warband = struct {
    model: Model,
    band: [CAP]Kobold = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Warband {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Warband) []Kobold {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Warband) []const Kobold {
        return self.band[0..self.n];
    }

    pub fn reset(self: *Warband, m: *const wf.Map) void {
        foe.resetRoles(Kobold, Role, &self.band, &self.n, m, roleOf);
    }

    pub fn setShader(self: *Warband, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Warband, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Warband) void {
        for (self.liveConst()) |*k| k.drawFx();
    }

    pub fn setParry(self: *Warband, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Warband) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn pierce(self: *Warband, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Warband) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Warband) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Warband) u32 {
        return foe.aliveCount(self.liveConst());
    }
    pub fn splash(self: *Warband, at: rl.Vector3) void {
        var best: ?*Kobold = null;
        var bestD: f32 = 1e9;
        for (self.live()) |*k| {
            if (k.gone) continue;
            const d = mathx.distXZ(k.pos, at);
            if (d < bestD) {
                bestD = d;
                best = k;
            }
        }
        if (best) |k| k.impactSparks(at);
    }

    pub fn soulsDropped(self: *const Warband) u32 {
        return foe.soulsEach(self.liveConst());
    }

    pub fn update(
        self: *Warband,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime loose: fn (@TypeOf(ctx), rl.Vector3) void,
    ) ?foe.Blow {
        for (self.live()) |*k| {
            if (k.role != .priest) continue;
            // **ONE RITE, ONE COOLDOWN, TWO THINGS IT CAN BE** — a full-health band is what it spends the cast
            // on, which is what makes killing it FIRST the read.
            k.healWanted = self.neediest(k.pos) != null or self.unrousedIdx(k.pos) != null;
        }
        var blow: ?foe.Blow = null;
        for (self.live()) |*k| {
            switch (k.update(dt, k.threat.aim(hero), bounds, blade)) {
                .none => {},
                .sling => |from| loose(ctx, from),
                // **THE WOUND COMES FIRST** — the bargain bills a share of the bar on top of whatever opened it.
                .healed => {
                    if (self.neediestIdx(k.pos)) |ti| {
                        if (self.band[ti].vit.heal(HEAL_AMT) > 0) {
                            sfx.world(.kobold_heal, self.band[ti].pos);
                            k.healBloom(k.staffTop(), 0.26);
                            self.band[ti].healBloom(self.band[ti].centerWorld(), 0.46);
                        }
                    } else if (self.unrousedIdx(k.pos)) |ti| {
                        self.band[ti].vit.build(.berserk, RITE_ZERK);
                        sfx.world(.kobold_snarl, self.band[ti].pos);
                        k.healBloom(k.staffTop(), 0.26);
                        self.band[ti].healBloom(self.band[ti].centerWorld(), 0.52);
                    }
                },
            }
            if (k.hurtOpen() and mathx.distXZ(k.pos, hero) <= k.hurtReach()) {
                k.markDealt();
                foe.worseBlow(&blow, k.hurtBlow(), k.pos, &k.threat);
            }
        }
        return blow;
    }

    fn neediestIdx(self: *const Warband, from: rl.Vector3) ?usize {
        var best: ?usize = null;
        var worst: f32 = 1.0;
        for (self.liveConst(), 0..) |*k, i| {
            if (!foe.corporeal(k)) continue;
            if (!k.vit.needsHeal(HEAL_SLACK)) continue;
            if (mathx.distXZ(from, k.pos) > HEAL_RANGE) continue;
            const f = k.vit.hpFrac();
            if (f < worst) {
                worst = f;
                best = i;
            }
        }
        return best;
    }
    /// Nearest rather than healthiest: the one standing next to it is the one the player is fighting. Anything
    /// at all in the meter is skipped — refresh-not-stack, so a second rite would spend the cast for nothing.
    fn unrousedIdx(self: *const Warband, from: rl.Vector3) ?usize {
        var best: ?usize = null;
        var near: f32 = HEAL_RANGE;
        for (self.liveConst(), 0..) |*k, i| {
            if (!foe.corporeal(k)) continue;
            if (k.role == .priest) continue;
            if (k.vit.ail(.berserk).meter > 0 or k.vit.ailOn(.berserk)) continue;
            const d = mathx.distXZ(from, k.pos);
            if (d > near) continue;
            near = d;
            best = i;
        }
        return best;
    }

    fn neediest(self: *const Warband, from: rl.Vector3) ?*const Kobold {
        const i = self.neediestIdx(from) orelse return null;
        return &self.band[i];
    }
};


test "the role table, the enum and the map's foe kinds agree" {
    // The comptime block above pins the ordinal shift; this pins the accessor built on it, and that non-kobold
    // kinds are rejected rather than folded into a role.
    try std.testing.expectEqual(Role.berserker, roleOf(.berserker).?);
    try std.testing.expectEqual(Role.priest, roleOf(.priest).?);
    try std.testing.expectEqual(Role.slinger, roleOf(.slinger).?);
    try std.testing.expect(roleOf(.toad) == null);
    try std.testing.expect(roleOf(.archer) == null);
    try std.testing.expect(roleOf(.ogre) == null);
    // …and `kindOf` is its INVERSE, the direction the lock-on takes: game.zig used to spell this arithmetic
    // out a second time, where the comptime block above could not reach it.
    for (0..SPEC.len) |i| {
        const r: Role = @enumFromInt(i);
        try std.testing.expectEqual(r, roleOf(kindOf(r)).?);
    }
}

test "a kobold is a man's height and BROADER than he is" {
    try std.testing.expect(SCALE > 0.95 and SCALE < 1.15);
    try std.testing.expect(SHOULDER_HALF > heromod.SHOULDER_HALF);
    try std.testing.expect(HIP_HALF > heromod.HIP_HALF);
}

test "the berserker's recovery is a REAL opening, and his poise is glass" {
    const flurry = @as(f32, @floatFromInt(ZERK_SWINGS_LO)) * ZERK_CHOP;
    try std.testing.expect(ZERK_RECOVER > flurry * 0.8);
    try std.testing.expect(ZERK_RECOVER > combat.FOE_HEAVY_STUN_DUR * 0.5);
    try std.testing.expect(spec(.berserker).poise < spec(.slinger).poise);
}

test "the priest is the priority target, and the numbers say so" {
    try std.testing.expect(spec(.priest).hp < spec(.berserker).hp);
    try std.testing.expect(spec(.priest).souls > spec(.berserker).souls);
    try std.testing.expect(spec(.priest).souls > spec(.slinger).souls);
    try std.testing.expect(spec(.priest).wantMin > spec(.slinger).wantMin);
    try std.testing.expect(CAST_DUR > 1.0 and CAST_CD > 6.0);
    try std.testing.expect(HEAL_AMT > spec(.priest).hp * 0.4);
}

test "the slinger has exactly two answers, and they do not overlap" {
    try std.testing.expect(BITE_R < spec(.slinger).wantMin);
    try std.testing.expect(CLUMP_SPEED < 15.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), CLUMP_HIT.dmg, 1e-6);
    try std.testing.expectApproxEqAbs(CLUMP_HIT.raw(), CLUMP_HIT.elem.at(.fire), 1e-6);
    try std.testing.expect(CLUMP_HIT.raw() < ZERK_HIT.raw() + BITE_HIT.raw());
}

test "a hurt window latches, so one swing lands once" {
    var k = Kobold.spawnAs(.berserker, mathx.zero3, 0, 1.0, 0.5);
    k.state = .chop;
    k.t = ZERK_CHOP * (ZERK_HIT_A + ZERK_HIT_B) * 0.5;
    k.dealt = false;
    try std.testing.expect(k.hurtOpen());
    k.markDealt();
    try std.testing.expect(!k.hurtOpen());
    k.dealt = false;
    k.enterStun(.stunlight);
    try std.testing.expect(!k.hurtOpen());
    try std.testing.expectEqual(@as(u32, 0), k.chopsLeft);
}

test "the priest never reaches for an attack window" {
    var p = Kobold.spawnAs(.priest, mathx.zero3, 0, 1.0, 0.2);
    for ([_]State{ .idle, .approach, .cast, .heave, .whirl, .bite }) |s| {
        p.state = s;
        p.dealt = false;
        p.t = 0.4;
        if (s == .bite or s == .heave or s == .whirl) continue; // states it cannot enter
        try std.testing.expect(!p.hurtOpen());
    }
}

test "BOTH KOBOLD STROKES CAN BE CAUGHT, and the DASH cannot — a leap is not a stroke" {
    const cases = [_]struct { st: State, at: f32, reach: f32 }{
        .{ .st = .chop, .at = ZERK_CHOP * ZERK_HIT_A, .reach = ZERK_REACH },
        .{ .st = .bite, .at = BITE_DUR * BITE_HIT_A, .reach = BITE_R },
    };
    for (cases) |c| {
        var k = Kobold.spawnAs(if (c.st == .chop) .berserker else .slinger, mathx.zero3, 0, 1.0, 0.3);
        k.state = c.st;
        k.dealt = false;
        k.t = c.at - foe.PARRY_LEAD * 0.5;
        const reach = k.parryable() orelse return error.TestUnexpectedResult;
        try std.testing.expectApproxEqAbs(foe.hurtReach(c.reach, k.scale), reach, 1e-5);
        k.parry = .{ .live = true, .at = mathx.ground(0, c.reach * 0.5), .facing = std.math.pi, .arc = combat.GUARD_ARC };
        k.takeParry();
        try std.testing.expect(k.parried);
        try std.testing.expect(k.state == .stunlight or k.state == .stunheavy);
        // `enterStun` spends `dealt`, which is what stops the rest of the stroke billing through the group.
        try std.testing.expect(!k.hurtOpen());
    }
    var d = Kobold.spawnAs(.berserker, mathx.zero3, 0, 1.0, 0.3);
    d.state = .dash;
    d.dealt = false;
    var t: f32 = 0;
    while (t < DASH_GATHER + DASH_FLIGHT + DASH_LAND) : (t += 1.0 / 240.0) {
        d.t = t;
        try std.testing.expect(d.parryable() == null);
    }
}

test "NO ATTACK COMES OUT OF NOWHERE: every kobold move is visible before it can hurt" {
    try std.testing.expect(ZERK_CHOP * ZERK_HIT_A >= foe.TELL_MIN);
    try std.testing.expect(ZERK_CHOP * (ZERK_HIT_B - ZERK_HIT_A) > 0.10);
    // IN SECONDS, NOT AS A FRACTION — the old `BITE_HIT_A >= TELL_MIN` compared 0.30 of a clock against
    // 0.30 of a second and passed while the snap landed at 0.156 s.
    try std.testing.expect(BITE_DUR * BITE_HIT_A >= foe.TELL_MIN);
    try std.testing.expect(BITE_DUR * BITE_HIT_A > foe.PARRY_LEAD * 1.5);
    try std.testing.expect(WHIRL_DUR >= foe.TELL_MIN);
    try std.testing.expect(CAST_DUR >= foe.TELL_MIN);
    try std.testing.expect(DASH_GATHER + DASH_FLIGHT >= foe.TELL_MIN);
}

test "THE SLINGER DRIFTS WHILE THE SLING COOLS — the bearing sweeps and the band holds" {
    var k = Kobold.spawnAs(.slinger, mathx.ground(0, 0), 0, 1.0, 0.3);
    k.leash.noteSeen();
    k.slingCd = 99.0;
    k.biteCd = 99.0;
    const hero = mathx.ground(0, 7.5);
    var swept: f32 = 0;
    var was = mathx.headingXZ(mathx.dirXZ(hero, k.pos));
    var t: f32 = 0;
    while (t < 1.2) : (t += 1.0 / 60.0) {
        _ = k.update(1.0 / 60.0, hero, 500.0, .{});
        const now = mathx.headingXZ(mathx.dirXZ(hero, k.pos));
        swept += @abs(mathx.wrapPi(now - was));
        was = now;
    }
    const d = mathx.distXZ(k.pos, hero);
    std.debug.print("\n  slinger drift: bearing swept {d:.0} deg, range {d:.1} m (band {d:.1}..{d:.1})\n", .{ mathx.degrees(swept), d, SPEC[2].wantMin, SPEC[2].wantMax });
    try std.testing.expect(swept > mathx.radians(12.0));
    try std.testing.expect(d > SPEC[2].wantMin and d < SPEC[2].wantMax + 1.0);
}
