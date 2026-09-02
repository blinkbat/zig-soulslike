const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const anim = @import("../core/anim.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const archermod = @import("archer.zig");
const ogremod = @import("ogre.zig");

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
const setLocal = heromod.setHumanoid;

// THE TOLLING HOLLOW (owner's creature, owner's name). One blow, a bite, and a BRONZE BELL on its back: left
// alone past bite reach it rings and every body inside 34 m turns and comes (`foe.rouseWithin`). 340 HP, no
// armour. **THE TOLL IS REFUSED WHILE HE IS INSIDE BITE REACH** — a range, not a cooldown, and it reads no inputs.

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
/// The rig's spare bone; on this body it is the CLAPPER.
const CLAPPER = heromod.HELD;

const H: f32 = heromod.H;

/// 3.25 m of stature bent through `HUNCH`'s 52 degrees at the waist: crown at ~2.4 m, shoulders at 2.2 —
/// the head at the hero's own reach on a frame half again his height. The hunch is what makes the bell a PLATFORM.
pub const SCALE = (H + 1.45) / H;
const HIP_HALF = heromod.HIP_HALF * 1.55;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 1.62;
/// `restHumanoid` gives a man a 0.07 H neck, and on a chest this heavy the skull sat INSIDE the ribcage mass.
/// A bull's neck: the joint comes up a little and the skull goes out in FRONT of the chest, where the bite says the jaws are.
const REST = blk: {
    var r = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
    r[heromod.NECK] = v3(0, 0.828 * H, 0.022 * H);
    r[heromod.HEAD] = v3(0, 0.862 * H, 0.098 * H);
    break :blk r;
};
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.05 * H, .toe = 0.255 * H, .halfW = 0.075 * H, .drop = 0.036 * H },
    .{ .bone = ANKR, .heel = 0.05 * H, .toe = 0.255 * H, .halfW = 0.075 * H, .drop = 0.036 * H },
};

/// The ring as authored — what the comptime pin below is asked of, since the ring itself is live now.
pub const AGGRO_R_BANK: f32 = 20.0;
pub var AGGRO_R: f32 = AGGRO_R_BANK;
const HOME_R: f32 = 1.4;
const TURN_RATE: f32 = 2.6;
const WALK_SPEED: f32 = heromod.WALK_SPEED_BANK * 0.72;
const CHASE_SPEED: f32 = heromod.WALK_SPEED_BANK * 1.05;
const ACCEL: f32 = 3.2;
const BODY_R: f32 = 0.62;
const HURT_R: f32 = 0.78;
pub var SOULS: u32 = 420;

/// Over the cyclops's 300, and it is the whole creature: there is no armour under it.
const HP_MAX: f32 = 340.0;
/// Over the cyclops's 30 and well under the bone knight's 78: the hero's heavy swing at 22 does not flinch it.
const POISE_MAX: f32 = 34.0;
const STANCE_MAX: f32 = 62.0;
/// A hundredweight of bronze with no earth under it — the worst lightning weakness in the field. Cold and chaos are the skeleton family's own answer.
const RESISTS = combat.resists(.{ .fire = -30, .cold = 55, .lightning = -70, .chaos = 40 });

const DEATH_DUR: f32 = 1.55;
const DISS_DUR: f32 = 1.10;
const SHOVE_DECAY: f32 = 6.0;
const A_PROT: f32 = 3.0;
/// A BIG BODY HINGES AT THE WAIST AND ITS LEGS STAY PLANTED — the law's one number (`ogre.PELVIS_SHARE`).
const PELVIS_SHARE = ogremod.PELVIS_SHARE;
/// Degrees of permanent stoop, carried at the WAIST — leaned at the root the legs rotate with it and the whole
/// thing lurches. At 52 the spine is nearer horizontal than vertical, which lays the bell flat enough to ride.
const HUNCH: f32 = 52.0;

const CHIP_SPRAY = archermod.boneChips(1.25);
const CHIP_LIGHT = 12;
const CHIP_HEAVY = 18;
const CHIP_DEATH = 22;
const NPART = 84;

const BITE_WIND: f32 = 0.46;
const BITE_STRIKE: f32 = 0.20;
const BITE_RECOVER: f32 = 0.62;
const BITE_COOL: f32 = 1.55;
const BITE_LUNGE: f32 = 0.62;
/// **MEASURED AGAINST THE FIELD, NOT CHOSEN.** At 1.85 the whole reach came to 3.17 m at this scale — further
/// than the cyclops's slam, on the weakest blow in the game. Then measured off the posed jaws: they arrive
/// 1.55 m out, so 1.25 still answered for 0.77 m of clear air past them. 1.10 promises 2.11 m against a
/// 1.55 m arrival plus the hero's own 0.55 m footprint. The test prints both.
const BITE_R: f32 = 1.10;
const BITE_TRIGGER_R: f32 = BITE_R + BITE_LUNGE * 0.7;
/// Share of `BITE_R`, not of the trigger ring. The skitterer's same-named dial is a share of ITS trigger ring.
const STOP_FRAC: f32 = 0.8;
/// cos 66 degrees. A head on a neck this short cannot reach its own flank, which is what makes its hip safe ground.
const BITE_FRONT_DOT: f32 = 0.40;
/// Under the kobold berserker's chop and half the cyclops's swipe. The POISE is a big body's, which is what stops "low damage" reading as "harmless".
const BITE_HIT = combat.Hit{ .dmg = 13, .poise = 26, .stance = 9 };

const TOLL_WIND: f32 = 1.10;
const TOLL_SWING: f32 = 0.42;
const TOLL_RECOVER: f32 = 1.25;
const TOLL_COOL: f32 = 12.0;
/// Two and a half times its own notice ring, and wider than the spacing between camps in `worlds/`.
pub const TOLL_R: f32 = 34.0;
/// The frame the clapper strikes, as a share of the swing.
const TOLL_HIT_AT: f32 = 0.38;

// **THE GREMLIN'S VOLLEY** (owner: "a staggered 3-spark volley"). The host has nothing past its own jaws. The
// STAGGER is what makes it fair: three things to dodge separately, not one wall of light.
const SPARK_WIND: f32 = 0.72;
pub const SPARK_N: u8 = 3;
/// Seconds between one spark leaving and the next. **OVER THE ROLL'S INVULNERABLE WINDOW** (`hero.ROLL_IFRAME_END`,
/// 0.46 s) and not merely over its animation: two sparks inside one set of i-frames are one blow with a fatter shape.
const SPARK_GAP: f32 = 0.58;
const SPARK_RECOVER: f32 = 0.70;
const SPARK_CD: f32 = 5.5;
/// Inside `AGGRO_R` with room and past the bite ring by a wide margin — two moves answering one distance is one move with a coin flip.
pub const SPARK_MAX: f32 = 16.0;
pub const SPARK_SPEED: f32 = 17.0;
/// **THE VOLLEY CARRIES ITS DAMAGE, BECAUSE THE BITE MAY NOT** — that one is pinned under 16 and under half the
/// ogre's slam. Three of these is 45 through no armour against the bite's 13. Pure lightning: resists answer.
pub var SPARK_HIT = combat.Hit{ .poise = 8, .elem = combat.elems(.{ .lightning = 15 }) };

fn volleySpan() f32 {
    return @as(f32, @floatFromInt(SPARK_N - 1)) * SPARK_GAP;
}

comptime {
    std.debug.assert(BITE_WIND >= foe.TELL_MIN and TOLL_WIND >= foe.TELL_MIN);
    std.debug.assert(BITE_COOL > BITE_STRIKE + BITE_RECOVER);
    std.debug.assert(TOLL_R > AGGRO_R_BANK * 1.5);
    std.debug.assert(TOLL_WIND + TOLL_SWING + TOLL_RECOVER > BITE_WIND + BITE_STRIKE + BITE_RECOVER);
    std.debug.assert(TOLL_HIT_AT > 0 and TOLL_HIT_AT < 1);
    std.debug.assert(SPARK_WIND >= foe.TELL_MIN);
    std.debug.assert(SPARK_GAP > heromod.ROLL_IFRAME_END_BANK); // …or two arrive inside one set of i-frames
    std.debug.assert(SPARK_CD > SPARK_WIND + volleySpan() + SPARK_RECOVER);
    std.debug.assert(BITE_TRIGGER_R + foe.HERO_R < SPARK_MAX);
    std.debug.assert(SPARK_MAX < AGGRO_R_BANK);
    std.debug.assert(SPARK_N >= 2);
    std.debug.assert(NPART >= foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH) + foe.WOUND_PARTS);
    std.debug.assert(HP_MAX > 300.0); // over the cyclops: the sponge IS the creature
}

const HIDE = rgba(52, 46, 42, 255);
const HIDE_LT = rgba(70, 62, 56, 255);
const HIDE_DK = rgba(30, 27, 25, 255);
const GUT = rgba(22, 18, 17, 255);
const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
/// BRONZE, not steel and not gold (`gfx.Mat.gilt`'s row). **SOLVED OFF THE RENDER** (`AGENTS.md`): at
/// (104, 88, 46) the lit skirt came back at 182 luma against the hide's 128 and the ground's 106. Wanted ~140,
/// i.e. 0.77 on screen, and screen goes as albedo^(1/2.2), so 0.77^2.2 = 0.56 on the albedo.
const BRONZE = rgba(58, 49, 26, 255);
const BRONZE_DK = rgba(35, 30, 17, 255);
const BRONZE_LIP = rgba(74, 65, 37, 255);
const STRAP = rgba(46, 34, 24, 255);
const EYE = rgba(196, 168, 96, 90);

const State = enum { idle, walk, bite, toll, spark, stunlight, stunheavy, dead };

const Choice = enum { bite, toll, spark, walk, hold };
/// `biteR` is `triggerR`'s own answer, not a second spelling of it: written out as `BITE_TRIGGER_R + foe.HERO_R`
/// the ring the state machine gates on and the ring this decides on were two copies of one number.
/// **THE BELL FIRST, THEN THE SPARKS.** Both live past the jaws, so the order between them is the decision and
/// not a roll; the toll comes off a 12 s clock, and the volley owns the between-times.
fn classify(dist: f32, biteR: f32, biteReady: bool, tollReady: bool, sparkReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist <= biteR) return if (biteReady) .bite else .walk;
    if (tollReady) return .toll;
    if (sparkReady and dist <= SPARK_MAX) return .spark;
    return .walk;
}

/// `zeta` under 1 so it RINGS on rather than arriving (`AGENTS.md`). **SOLVED**: the haul is driven over
/// `TOLL_SWING` and natural frequency is sqrt(stiff) rad/s — at 46 the period was 0.93 s and the bell
/// reached 37 of the 52 degrees it was pulled through. 165 gives 12.8 rad/s and a 0.49 s period, so the mass
/// arrives inside the drive and carries PAST it.
const BELL_STIFF: f32 = 165.0;
const BELL_ZETA: f32 = 0.30;
/// Degrees the bell lags a walking body, per metre-per-second of travel.
const BELL_DRAG: f32 = 5.2;
/// Degrees the toll drives it through — 5x anything walking can produce. THE TOLL IS THE ONLY TIME THE BELL IS A WEAPON.
const BELL_HAUL: f32 = 52.0;
/// **CLEAR OF THE BACK, OR IT IS A LUMP.** Measured: at -0.088 H it sat inside the chest mass and nothing showed. -0.215 H hangs the crown a hand's breadth off the spine.
const BELL_AT = v3(0, 0.052 * H, -0.215 * H);
/// The clapper swings further than the skirt it hangs in, which is what makes it strike the wall.
const CLAPPER_LAG: f32 = 1.35;
const BELL_R: f32 = 0.150 * H;
const BELL_DROP: f32 = 0.235 * H;

// **THE GREMLIN IS NOT A SECOND BODY.** No HP of its own, no leash, no place in `FOE_GROUPS`: seven bones and
// six meshes riding the host's own transform, so killing the hollow takes the gremlin with it. It is the only
// thing here with a ranged answer; the hollow is the legs and the bar.

/// Stature in shares of the hero's. MEASURED AGAINST THE BELL, not the hero: at 0.34 H it came out 1.10 m —
/// as tall as the bronze is wide, a second creature rather than a passenger. 0.20 H is 0.65 m.
const G_H: f32 = 0.20 * H;
const G_RUMP = 0;
const G_TORSO = 1;
const G_HEAD = 2;
const G_ARML = 3;
const G_ARMR = 4;
const G_LEGL = 5;
const G_LEGR = 6;
const G_N = 7;

/// In the BELL's own frame: the crown blob rises `BELL_R * 0.30` off the bell's origin, and `G_REST[G_RUMP]`
/// is the ZERO of the rider's rig, so this point IS the seat. Posed off the FEET instead, the splayed legs
/// lifted the whole thing 0.3 m clear of the bronze.
const G_SEAT: f32 = BELL_R * 0.30 + 0.008 * H;
/// Degrees per degree the bell moves. Well under 1: mounted rigidly in the bell's frame it lay on its side the moment `HUNCH` went past forty.
const G_BRACE: f32 = 0.34;
/// Degrees it leans forward at rest.
const G_STOOP: f32 = 22.0;

/// **THE RUMP IS THE ORIGIN, BECAUSE THE RUMP IS WHAT TOUCHES THE BELL.** A seated creature's feet are wherever
/// its knees put them, so a rig measured off the feet drifted the seat with every change to the leg pose.
/// **And the joints OVERLAP their masses**: the torso's capsule reaches back down through the rump.
const G_REST = [G_N]rl.Vector3{
    v3(0, 0, 0), // rump — the seat
    v3(0, 0.22 * G_H, -0.01 * G_H), // torso, close over it
    v3(0, 0.50 * G_H, 0.05 * G_H), // head, thrust forward off a neckless shoulder line
    v3(0.15 * G_H, 0.34 * G_H, 0.03 * G_H),
    v3(-0.15 * G_H, 0.34 * G_H, 0.03 * G_H),
    v3(0.11 * G_H, -0.04 * G_H, 0.05 * G_H),
    v3(-0.11 * G_H, -0.04 * G_H, 0.05 * G_H),
};

/// In the arm bone's own frame. THREE things read it — the fist mesh, the glow sunk into it, and `sparkWorld`; a muzzle that disagrees with the picture is a bolt out of clear air.
const G_FIST = v3(0.05 * G_H, -0.30 * G_H, 0.06 * G_H);

// **IT HAS TO SILHOUETTE AGAINST THE BELL IT SITS ON.** SAMPLED (`AGENTS.md`): at (64,52,40) the rider came
// back at 142 luma against bronze reading 139-153 and hide at 112-128 — the same value as its own perch.
// Wanted ~100, i.e. 0.70 on screen, and 0.70^2.2 = 0.45 on the albedo. Separated on HUE too: the one COOL grey.
const G_HIDE = rgba(28, 26, 27, 255);
const G_HIDE_LT = rgba(41, 38, 39, 255);
const G_HIDE_DK = rgba(17, 15, 16, 255);
/// The same lightning the sparks are, so what you read before the volley is the volley's own colour.
const G_SPARK = rgba(196, 214, 255, 255);
const G_EYE = rgba(226, 236, 255, 110);

pub const Model = struct {
    bone: [N]rl.Mesh,
    bell: rl.Mesh,
    gremlin: [G_N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "tolling hollow");
        var bone: [N]rl.Mesh = undefined;
        bone[ROOT] = pelvisMesh();
        bone[SPINE] = abdomenMesh();
        bone[CHEST] = chestMesh();
        bone[NECK] = neckMesh();
        bone[SKULL] = skullMesh();
        bone[HIPL] = thighMesh();
        bone[KNEEL] = shankMesh();
        bone[ANKL] = footMesh(1.0);
        bone[HIPR] = thighMesh();
        bone[KNEER] = shankMesh();
        bone[ANKR] = footMesh(-1.0);
        bone[SHL] = upperArmMesh();
        bone[ELL] = forearmMesh();
        bone[WRL] = handMesh();
        bone[SHR] = upperArmMesh();
        bone[ELR] = forearmMesh();
        bone[WRR] = handMesh();
        bone[CLAPPER] = clapperMesh();
        var gremlin: [G_N]rl.Mesh = undefined;
        gremlin[G_RUMP] = gRumpMesh();
        gremlin[G_TORSO] = gTorsoMesh();
        gremlin[G_HEAD] = gHeadMesh();
        gremlin[G_ARML] = gArmMesh(1.0);
        gremlin[G_ARMR] = gArmMesh(-1.0);
        gremlin[G_LEGL] = gLegMesh(1.0);
        gremlin[G_LEGR] = gLegMesh(-1.0);
        return .{ .bone = bone, .bell = bellMesh(), .gremlin = gremlin, .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, h: *const Hollow) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, h.xf[i]);
        rl.drawMesh(self.bell, self.mat, h.bellXf());
        for (0..G_N) |i| rl.drawMesh(self.gremlin[i], self.mat, h.gxf[i]);
    }
};

pub const Hollow = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    parry: foe.Parry = .{},

    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,
    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    biteCool: f32 = 0,
    tollCool: f32 = 0,
    sparkCool: f32 = 0,
    /// How many of the volley's `SPARK_N` have left, so a long frame can never drop one and never fire two.
    sparksOut: u8 = 0,

    bell: anim.Spring = .{},
    bellAng: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    heroHit: ?combat.Hit = null,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    parried: bool = false,
    /// A one-frame edge (`justDied`'s idiom) cleared at the TOP of `update`: the creature cannot rouse anything
    /// itself, because every other body is in another group, another array, another type.
    tolled: bool = false,
    gaped: bool = false,
    snapped: bool = false,
    /// The creature says WHEN and `game.zig` puts the shot in the pool — the projectile is another array of another type.
    sparked: bool = false,
    heaved: bool = false,
    clanked: bool = false,
    yelped: bool = false,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    /// Which way its shoulders were passing last knock, so a walking clank fires on the FOOTFALL rather than on a clock beside it.
    knockWas: f32 = 0,

    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    bellMat: rl.Matrix = undefined,
    /// Its own array because it is not on the humanoid rig: bolting a second creature's joints into `N` would be a different layout, not a wider one.
    gxf: [G_N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Hollow {
        var h = Hollow{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
        };
        h.rest = REST;
        h.fxRng = foe.fxStream(seed, 63311.0, 0xB311);
        h.tollCool = 1.2 + seed * 2.4;
        h.pose();
        return h;
    }

    pub fn kind(_: *const Hollow) wf.FoeKind {
        return .tolling_hollow;
    }

    pub fn centerWorld(self: *const Hollow) rl.Vector3 {
        return foe.bodyPoint(self.pos, 0.62 * H, self.scale, 0);
    }
    pub fn topWorld(self: *const Hollow) rl.Vector3 {
        return foe.bodyPoint(self.pos, 1.05 * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Hollow) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], archermod.LOCK_AT);
    }
    pub fn hurtRadius(self: *const Hollow) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Hollow) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Hollow) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Hollow) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Hollow) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(_: *const Hollow) bool {
        return false;
    }
    pub fn flashFrac(self: *const Hollow) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn soulValue(_: *const Hollow) u32 {
        return SOULS;
    }
    pub fn stature(self: *const Hollow) f32 {
        return H * self.scale;
    }
    pub fn jawWorld(self: *const Hollow) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], v3(0, -0.020 * H, 0.075 * H));
    }
    pub fn bellXf(self: *const Hollow) rl.Matrix {
        return self.bellMat;
    }
    /// The bell, not the body — that is what the radius is measured from (`foe.rouseWithin`).
    pub fn bellWorld(self: *const Hollow) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], BELL_AT);
    }

    pub fn navWant(self: *const Hollow, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        if (foe.postAim(self)) |go| return go;
        return if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Hollow, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    /// SECONDS BACK FROM THE JAWS CLOSING, or null. One rule for every weapon in the field (`foe.PARRY_LEAD`).
    fn toImpact(self: *const Hollow) ?f32 {
        if (self.state != .bite) return null;
        return BITE_WIND + BITE_STRIKE * 0.45 - self.t;
    }

    fn parryable(self: *const Hollow) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(BITE_R, self.scale);
    }

    fn takeParry(self: *Hollow) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.biteCool = BITE_COOL;
        self.chips(self.jawWorld(), mathx.dirXZ(self.pos, self.parry.at), 10, 3.0);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    pub fn update(self: *Hollow, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.heroHit = null;
        self.tolled = false;
        self.gaped = false;
        self.snapped = false;
        self.sparked = false;
        self.heaved = false;
        self.clanked = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.justDied = false;
        self.parried = false;
        self.stateStep(dt, hero, bounds);
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Hollow, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.t += dt;
        self.elapsed += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.biteCool = mathx.maxF(0, self.biteCool - dt);
        self.tollCool = mathx.maxF(0, self.tollCool - dt);
        self.sparkCool = mathx.maxF(0, self.sparkCool - dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        var moveSpeed: f32 = 0;
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, archermod.DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = 0;
                const dur = combat.foeStunDur(self.state == .stunheavy);
                if (self.t >= dur) self.enter(.idle);
            },
            .bite => {
                if (self.t < BITE_WIND) self.faceToward(hero, dt);
                self.speed = 0;
                // Through `stepXZ` like any other committed travel, so the terrain gate still gets the last word.
                if (self.t >= BITE_WIND * 0.55 and self.t < BITE_WIND + BITE_STRIKE) {
                    const span = BITE_WIND * 0.45 + BITE_STRIKE;
                    // NOT handed to `advanceGait`: billed as travel it advanced the legs' stride phase with the walk speed sitting at zero.
                    mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), BITE_LUNGE * self.scale * (dt / span), bounds);
                }
                if (self.t >= BITE_WIND and self.t < BITE_WIND + BITE_STRIKE) self.tryBite(hero);
                if (self.t >= BITE_WIND + BITE_STRIKE + BITE_RECOVER) {
                    self.biteCool = BITE_COOL;
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .toll => {
                // No travel at all through the whole 2.77 s, which is what makes ringing the bell a thing it PAYS for.
                self.faceToward(hero, dt * 0.3);
                self.speed = 0;
                const swingT = self.t - TOLL_WIND;
                if (swingT >= 0) {
                    const at = TOLL_SWING * TOLL_HIT_AT;
                    if (swingT - dt < at and swingT >= at) {
                        self.tolled = true;
                        self.tollCool = TOLL_COOL;
                    }
                }
                if (self.t >= TOLL_WIND + TOLL_SWING + TOLL_RECOVER) self.enter(.idle);
            },
            // The host holds still for the whole volley and tracks slowly, so walking round it works and standing in it does not.
            .spark => {
                self.faceToward(hero, dt * 0.5);
                self.speed = 0;
                const since = self.t - SPARK_WIND;
                if (since >= 0 and self.sparksOut < SPARK_N and
                    since >= @as(f32, @floatFromInt(self.sparksOut)) * SPARK_GAP)
                {
                    self.sparksOut += 1;
                    self.sparked = true;
                }
                if (self.t >= SPARK_WIND + volleySpan() + SPARK_RECOVER) {
                    self.sparkCool = SPARK_CD;
                    self.enter(.idle);
                }
            },
            .idle, .walk => {
                const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
                switch (classify(sensed, triggerR(foe.HERO_R), self.biteCool <= 0, self.tollCool <= 0, self.sparkCool <= 0)) {
                    .bite => {
                        self.speed = 0;
                        self.heroLatch = false;
                        self.enter(.bite);
                    },
                    .toll => {
                        self.speed = 0;
                        self.enter(.toll);
                    },
                    .spark => {
                        self.speed = 0;
                        self.enter(.spark);
                    },
                    .walk => {
                        const want = hero;
                        const gap = mathx.distXZ(self.pos, want);
                        const stop = stopR(foe.HERO_R);
                        self.faceToward(self.nav.aim(self.pos, want), dt);
                        if (gap > stop) {
                            self.speed = approach(self.speed, CHASE_SPEED, ACCEL * dt);
                            foe.stride(self, dt, bounds, &movedDist, &moveSpeed, &moveYaw);
                            self.state = .walk;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                    .hold => {
                        // **ORDERS COME BEFORE GOING HOME**, because for a unit that has them the round IS
                        // where it belongs (`foe.homeFor`); the walk-home below is what a HELD body does.
                        const ps = foe.postStep(self, dt, bounds, WALK_SPEED, sensed, AGGRO_R);
                        if (ps.yaw) |w| {
                            self.speed = approach(self.speed, ps.speed, ACCEL * dt);
                            moveSpeed = self.speed;
                            movedDist = ps.moved;
                            moveYaw = w;
                            self.facing = mathx.approachAngle(self.facing, w, TURN_RATE * dt);
                            self.state = .walk;
                        } else if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) {
                            self.faceToward(self.nav.aim(self.pos, self.home), dt);
                            self.speed = approach(self.speed, WALK_SPEED, ACCEL * dt);
                            foe.stride(self, dt, bounds, &movedDist, &moveSpeed, &moveYaw);
                            self.state = .walk;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                }
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.tickBell(dt);
        self.pose();
    }

    /// **THE BELL IS DRIVEN, NEVER ASSIGNED.** One spring, one target; below critical damping it rings on after both the walk's lag and the haul.
    fn tickBell(self: *Hollow, dt: f32) void {
        var want = -BELL_DRAG * self.speedS;
        if (self.state == .toll) {
            const swingT = self.t - TOLL_WIND;
            want = if (swingT < 0)
                // The gather is the bell going the WRONG way — the haul has to come from somewhere.
                BELL_HAUL * 0.42 * mathx.smoothstep(0, TOLL_WIND * 0.9, self.t)
            else
                -BELL_HAUL * foe.swingCurve(mathx.clampF(swingT / TOLL_SWING, 0, 1));
        }
        self.bellAng = self.bell.step(want, BELL_STIFF, BELL_ZETA, dt);
        // The clapper touches the wall when the swing changes SIGN, so the clank lands with the footfall that caused it.
        const crossed = (self.knockWas < 0) != (self.bellAng < 0);
        if (crossed and self.state != .toll and @abs(self.bell.vel) > 6.0) self.clanked = true;
        self.knockWas = self.bellAng;
    }

    fn tryBite(self: *Hollow, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(BITE_R, self.scale), BITE_FRONT_DOT)) return;
        self.heroHit = BITE_HIT;
        self.heroLatch = true;
        self.snapped = true;
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Hollow, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.55, .heavy = 1.30 });
        self.chips(s.contact, s.dir, if (heavy) CHIP_HEAVY else CHIP_LIGHT, if (heavy) 3.0 else 2.0);
        self.yelped = true;
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 2.8);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn chips(self: *Hollow, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, CHIP_SPRAY);
    }

    fn enter(self: *Hollow, s: State) void {
        self.state = s;
        self.t = 0;
        switch (s) {
            .bite => self.gaped = true,
            .toll => self.heaved = true,
            .spark => {
                self.sparksOut = 0;
                self.heaved = true;
            },
            else => {},
        }
    }
    fn enterStun(self: *Hollow, s: State) void {
        self.state = s;
        self.t = 0;
        self.heroLatch = false;
    }
    fn enterDeath(self: *Hollow) void {
        if (self.state == .dead) return;
        self.enterStun(.dead);
        self.justDied = true;
    }

    pub fn stagger(self: *Hollow, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Hollow) void {
        self.enterDeath();
    }
    pub fn debugToll(self: *Hollow) void {
        self.tollCool = 0;
        self.enter(.toll);
    }
    pub fn debugBite(self: *Hollow) void {
        self.biteCool = 0;
        self.heroLatch = false;
        self.enter(.bite);
    }
    /// `stageGather` and not `stageToll`: the shot harness stages every creature's signature move through this one name (`shots.runMapShots`).
    pub fn stageGather(self: *Hollow, u: f32) void {
        self.state = .toll;
        self.t = mathx.clampF(u, 0, 1) * (TOLL_WIND + TOLL_SWING);
        self.pose();
    }

    pub fn drawFx(self: *const Hollow) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Hollow, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    fn stunAmount(self: *const Hollow) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    /// -1 fully cocked back, +1 fully through: the bite's ONE clock, so the gape and the snap cannot tell different stories. Zero outside the move.
    fn biteAmt(self: *const Hollow) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return -mathx.smoothstep(0, BITE_WIND * 0.85, self.t);
        if (self.t < BITE_WIND + BITE_STRIKE) {
            return lerpF(-1.0, 1.0, foe.swingCurve((self.t - BITE_WIND) / BITE_STRIKE));
        }
        return 1.0 - mathx.smoothstep(BITE_WIND + BITE_STRIKE, BITE_WIND + BITE_STRIKE + BITE_RECOVER * 0.7, self.t);
    }

    /// How far round its shoulders are hauled for the toll, -1 gathered to +1 driven through.
    fn tollAmt(self: *const Hollow) f32 {
        if (self.state != .toll) return 0;
        if (self.t < TOLL_WIND) return -mathx.smoothstep(0, TOLL_WIND * 0.92, self.t);
        const swingT = self.t - TOLL_WIND;
        if (swingT < TOLL_SWING) return lerpF(-1.0, 1.0, foe.swingCurve(swingT / TOLL_SWING));
        return 1.0 - mathx.smoothstep(TOLL_SWING, TOLL_SWING + TOLL_RECOVER * 0.75, swingT);
    }

    pub fn pose(self: *Hollow) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const bite = self.biteAmt();
        const toll = self.tollAmt();

        // Routed through the WAIST with a sixth at the pelvis — leaned at the root the legs rotate with it (`ogre.PELVIS_SHARE`).
        const bodyPitch = HUNCH + 9.0 * bite + 6.0 * toll - 26.0 * stun + 40.0 * dk;
        const leanX = PELVIS_SHARE * bodyPitch;
        const waist = (1.0 - PELVIS_SHARE) * bodyPitch;
        const lumber = 4.2 * mathx.sinf(std.math.tau * self.phase) * m;
        const breathe = mathx.sinf(self.elapsed * 1.15 + self.seed * 6.28) * (1.0 - m);

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.26 * H, dk);
        const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip + 0.004 * H * breathe;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(11.0 * dk + lumber * 0.5), rx(leanX), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legPair(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, HIPL, KNEEL, HIPR, KNEER, solePatches);
        } else {
            heromod.deadLegs(&wx, self.rest, dk);
        }
        self.poseUpper(&wx, waist, bite, toll, stun, dk, pel.prot, lumber, breathe);
        self.xf = wx;
        self.bellMat = hungOnChest(self.xf[CHEST], self.bellAng);
        self.poseGremlin(fs, dead, dk);
    }

    /// Its POSITION is the bell's crown, so it goes where the bell goes; its ORIENTATION is the host's yaw plus
    /// a `G_BRACE` fraction of the swing. Posed in the bell's own frame it lay on its side once `HUNCH` passed forty.
    fn poseGremlin(self: *Hollow, fs: f32, dead: bool, dk: f32) void {
        const seat = foe.markOn(self.bellMat, v3(0, G_SEAT, 0));
        const gs = fs;
        // -1..+1 of the bell's own haul, so the lean is the SWING and never a second clock.
        const swing = mathx.clampF(self.bellAng / BELL_HAUL, -1, 1);
        const haul = self.haulAmt();
        const aim = self.aimAmt();
        const stoop = G_STOOP + 34.0 * haul - 16.0 * aim + 40.0 * dk;
        const fidget = if (dead) 0 else mathx.sinf(self.elapsed * 5.4 + self.seed * 6.28) * 3.4;

        var g: [G_N]rl.Matrix = undefined;
        // NO LIFT OFF THE SEAT: `G_REST[G_RUMP]` is zero, so the seat point IS the rump and the two cannot part.
        g[G_RUMP] = mul(
            mul(scaleM(gs, gs, gs), mul3(
                rz(-18.0 * swing + fidget * 0.4 + 26.0 * dk),
                rx(-G_BRACE * swing * BELL_HAUL * 0.5),
                ry(mathx.degrees(self.facing)),
            )),
            heromod.rootAt(seat),
        );
        heromod.setJoint(&g, &G_REST, G_TORSO, G_RUMP, mul(rx(stoop * 0.55), rz(fidget * 0.5)));
        heromod.setJoint(&g, &G_REST, G_HEAD, G_TORSO, mul3(
            rx(stoop * 0.45 - 30.0 * aim + 24.0 * dk),
            ry(fidget * 1.6),
            rz(fidget),
        ));
        inline for (.{ G_ARML, G_ARMR }, .{ 1.0, -1.0 }) |arm, side| {
            const lift = -86.0 * haul - 62.0 * aim + 14.0 * side * fidget;
            heromod.setJoint(&g, &G_REST, arm, G_TORSO, mul(
                rx(lift + 40.0 * dk),
                rz(side * (26.0 - 14.0 * aim - 10.0 * haul)),
            ));
        }
        // **IT IS SEATED, NOT STANDING.** Posed as a standing creature the legs kicked backwards and lifted the whole rider clear of the bronze.
        inline for (.{ G_LEGL, G_LEGR }, .{ 1.0, -1.0 }) |leg, side| {
            heromod.setJoint(&g, &G_REST, leg, G_RUMP, mul(
                rx(38.0 + 12.0 * haul - 24.0 * dk),
                rz(side * (30.0 + 6.0 * @abs(swing))),
            ));
        }
        self.gxf = g;
    }

    /// 0..1, HELD flat across all three sparks — the arms do not re-cock between them, which is what "staggered volley" means.
    fn aimAmt(self: *const Hollow) f32 {
        if (self.state != .spark) return 0;
        if (self.t < SPARK_WIND) return mathx.smoothstep(0, SPARK_WIND * 0.9, self.t);
        const after = self.t - SPARK_WIND - volleySpan();
        if (after <= 0) return 1.0;
        return 1.0 - mathx.smoothstep(0, SPARK_RECOVER * 0.6, after);
    }

    /// Between the rider's two fists, off the POSED arms. `G_FIST` is the mesh's own hand position, so the glow you can see and the point the shot leaves cannot part company.
    pub fn sparkWorld(self: *const Hollow) rl.Vector3 {
        const l = foe.markOn(self.gxf[G_ARML], G_FIST);
        const r = foe.markOn(self.gxf[G_ARMR], v3(-G_FIST.x, G_FIST.y, G_FIST.z));
        return mathx.scaleV(mathx.addV(l, r), 0.5);
    }

    /// 0..1 off the toll's own clock and nothing else, so the arms and the bronze cannot tell different stories about when it was rung.
    fn haulAmt(self: *const Hollow) f32 {
        if (self.state != .toll) return 0;
        if (self.t < TOLL_WIND) return mathx.smoothstep(0, TOLL_WIND * 0.92, self.t);
        const swingT = self.t - TOLL_WIND;
        if (swingT < TOLL_SWING) return 1.0 - mathx.smoothstep(0, TOLL_SWING * 0.7, swingT);
        return 0;
    }

    /// **ONE MOUNT FOR BOTH HALVES OF THE BELL** — written out twice, a move of `BELL_AT` took the bell off the back and left the clapper where it was.
    fn hungOnChest(chest: rl.Matrix, ang: f32) rl.Matrix {
        return mul(mul(tr(BELL_AT.x, BELL_AT.y, BELL_AT.z), rx(ang)), chest);
    }

    fn poseUpper(
        self: *Hollow,
        wx: *[N]rl.Matrix,
        waist: f32,
        bite: f32,
        toll: f32,
        stun: f32,
        dk: f32,
        prot: f32,
        lumber: f32,
        breathe: f32,
    ) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 7.0;
        const nod = 1.8 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const twist = 26.0 * toll;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.44 + nod), ry(-0.35 * prot + twist * 0.45), rz(wonk * 0.5 - 0.3 * lumber)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.56 + nod * 0.6 + 1.2 * breathe), ry(-0.5 * prot + twist * 0.55), rz(-wonk * 0.3 - 0.2 * lumber)));
        setLocal(wx, NECK, rest, rx(-14.0 * bite + 8.0 * dk - 6.0 * stun));
        setLocal(wx, SKULL, rest, mul3(
            rx(-22.0 * bite + 16.0 * dk - 24.0 * stun + 3.0 * breathe),
            ry(-0.5 * prot - twist * 0.25),
            rz(wonk),
        ));

        // THE ARMS HANG AND NEVER COME UP: they are not weapons, and a brute reading as a boxer is the lie the swing would tell.
        const armStun = -48.0 * stun;
        const swing = -14.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const reach = 34.0 * mathx.maxF(bite, 0);
        inline for (.{ SHL, SHR }, .{ ELL, ELR }, .{ WRL, WRR }, .{ 1.0, -1.0 }) |sh, el, wr, side| {
            const s = if (side > 0) swing else -swing;
            setLocal(wx, sh, rest, mul3(rx(-(4.0 + s - reach) + armStun - 22.0 * dk), ry(0), rz(side * (14.0 + 4.0 * @abs(wonk)))));
            setLocal(wx, el, rest, rx(-(26.0 + 10.0 * @abs(s) * 0.1)));
            setLocal(wx, wr, rest, rz(side * 6.0));
        }
        // The clapper hangs inside the bell and lags it — which is why the two are separate bones at all.
        wx[CLAPPER] = hungOnChest(wx[CHEST], self.bellAng * CLAPPER_LAG);
    }
};

pub fn triggerR(quarryR: f32) f32 {
    return BITE_TRIGGER_R + quarryR;
}
/// Off the BITE's own reach, not off the trigger ring the way `skitterer.stopR` is — and NEITHER ring is scaled by the body,
/// or the two invert: at `BITE_R * scale * STOP_FRAC` a placement at 1.25 halted 3.0 m out with a trigger ring at 2.08.
fn stopR(quarryR: f32) f32 {
    return BITE_R * STOP_FRAC + quarryR;
}
comptime {
    std.debug.assert(stopR(foe.HERO_R) < triggerR(foe.HERO_R));
}

const CAP_N = wf.MAX_PER_KIND;

pub const Belfry = struct {
    model: Model,
    band: [CAP_N]Hollow = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Belfry {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Belfry) []Hollow {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Belfry) []const Hollow {
        return self.band[0..self.n];
    }
    pub fn reset(self: *Belfry, m: *const wf.Map) void {
        foe.resetGroup(Hollow, &self.band, &self.n, m, .tolling_hollow);
    }
    pub fn clear(self: *Belfry) void {
        self.n = 0;
    }
    pub fn setShader(self: *Belfry, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(self: *Belfry, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Belfry, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Belfry) void {
        for (self.liveConst()) |*h| h.drawFx();
    }
    pub fn pierce(self: *Belfry, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn setParry(self: *Belfry, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Belfry) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn anyDied(self: *const Belfry) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Belfry) u32 {
        return foe.soulsEach(self.liveConst());
    }
    pub fn totalHits(self: *const Belfry) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Belfry) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


/// **A SPARK CRACKLES — IT IS NOT A GLOWING PILL** (owner: they don't look like sparks). Lightning's signature
/// (`elemfx`): a near-COLOURLESS core, blue only in the fringe, jagged blunt-ended arms off the flight axis.
/// **Vertex alpha is the emissive channel**, so the core is authored near-transparent to make it burn.
pub fn sparkMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5AA7);
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(0.062, 0.058, 0.088), 6, 9, rgba(140, 164, 230, 96));
    b.addBlob(v3(0, 0, 0.012), v3(0.034, 0.032, 0.052), 5, 8, rgba(250, 252, 255, 18));
    var arm: u32 = 0;
    while (arm < 4) : (arm += 1) {
        const a = rng.range(0, std.math.tau);
        const out = rng.range(0.055, 0.085);
        const along = rng.range(-0.06, 0.05);
        const elbow = v3(mathx.cosf(a) * out, mathx.sinf(a) * out, along);
        const kinkA = a + rng.range(0.5, 1.4) * (if (rng.float() < 0.5) @as(f32, 1) else -1);
        const tip = v3(
            elbow.x + mathx.cosf(kinkA) * rng.range(0.04, 0.07),
            elbow.y + mathx.sinf(kinkA) * rng.range(0.04, 0.07),
            elbow.z + rng.range(-0.05, 0.03),
        );
        b.addCapsule(v3(0, 0, 0.01), elbow, 0.011, 0.008, 4, rgba(236, 242, 255, 30));
        b.addCapsule(elbow, tip, 0.008, 0.005, 4, rgba(170, 192, 240, 70));
    }
    return b.toModel(shader);
}


fn gRumpMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB401);
    b.setMat(.hide);
    b.addBlob(v3(0, 0.02 * G_H, 0), v3(0.22 * G_H, 0.18 * G_H, 0.21 * G_H), 5, 8, G_HIDE);
    b.addBlob(v3(0, -0.06 * G_H, -0.03 * G_H), v3(0.17 * G_H, 0.10 * G_H, 0.15 * G_H), 4, 7, G_HIDE_DK);
    b.addCapsule(
        v3(0, -0.02 * G_H, -0.14 * G_H),
        v3(0.03 * G_H * rng.signed(), -0.16 * G_H, -0.30 * G_H),
        0.045 * G_H,
        0.028 * G_H,
        6,
        G_HIDE_DK,
    );
    b.addBlob(v3(0.02 * G_H * rng.signed(), -0.17 * G_H, -0.31 * G_H), v3(0.035 * G_H, 0.030 * G_H, 0.035 * G_H), 4, 6, G_HIDE_LT);
    return b.toMesh();
}

fn gTorsoMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB402);
    b.setMat(.hide);
    // Overlap the joint well past it or the two masses show daylight and read as two creatures (`propart.courseInto`'s rule, on a body).
    b.addCapsule(v3(0, -0.10 * G_H, 0), v3(0, 0.16 * G_H, 0.02 * G_H), 0.17 * G_H, 0.18 * G_H, 9, G_HIDE);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const y = -0.02 * G_H + 0.06 * G_H * @as(f32, @floatFromInt(i));
        b.addCapsule(
            v3(-0.12 * G_H, y, 0.07 * G_H),
            v3(0.12 * G_H, y + 0.012 * G_H * rng.signed(), 0.07 * G_H),
            0.016 * G_H,
            0.016 * G_H,
            5,
            G_HIDE_DK,
        );
    }
    b.setMat(.leather);
    b.addBox(v3(0.04 * G_H, 0.10 * G_H, 0.09 * G_H), v3(0.15 * G_H, 0.13 * G_H, 0), v3(-0.05 * G_H, 0.06 * G_H, 0), v3(0, 0, 0.03 * G_H), STRAP);
    return b.toMesh();
}

fn gHeadMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB403);
    b.setMat(.hide);
    b.addBlob(v3(0, 0.04 * G_H, 0), v3(0.17 * G_H, 0.15 * G_H, 0.18 * G_H), 6, 9, G_HIDE);
    b.addBlob(v3(0, -0.02 * G_H, 0.12 * G_H), v3(0.10 * G_H, 0.075 * G_H, 0.08 * G_H), 5, 8, G_HIDE_LT);
    inline for (.{ 1.0, -1.0 }, .{ 1.0, 0.82 }) |side, grade| {
        const tip = v3(side * 0.20 * G_H * grade, (0.24 + 0.06 * grade) * G_H, -0.05 * G_H + 0.02 * G_H * rng.signed());
        b.addCapsule(v3(side * 0.11 * G_H, 0.11 * G_H, -0.01 * G_H), tip, 0.055 * G_H * grade, 0.022 * G_H, 6, G_HIDE);
        b.addBlob(tip, v3(0.030 * G_H, 0.026 * G_H, 0.030 * G_H), 4, 6, G_HIDE_LT);
    }
    b.setMat(.flame);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addBlob(v3(side * 0.075 * G_H, 0.055 * G_H, 0.145 * G_H), v3(0.033 * G_H, 0.030 * G_H, 0.020 * G_H), 4, 6, G_EYE);
    }
    return b.toMesh();
}

fn gArmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xB404 else 0xB405);
    b.setMat(.hide);
    const drop = v3(side * G_FIST.x, G_FIST.y, G_FIST.z);
    const elbow = v3(side * 0.04 * G_H, -0.15 * G_H, 0.01 * G_H);
    b.addCapsule(mathx.zero3, elbow, 0.058 * G_H, 0.046 * G_H, 7, G_HIDE);
    b.addCapsule(elbow, drop, 0.046 * G_H, 0.036 * G_H, 7, G_HIDE);
    b.addBlob(elbow, v3(0.055 * G_H, 0.050 * G_H, 0.055 * G_H), 4, 7, G_HIDE_LT);
    b.addBlob(drop, v3(0.070 * G_H * rng.range(0.94, 1.08), 0.062 * G_H, 0.066 * G_H), 5, 8, G_HIDE);
    b.setMat(.flame);
    b.addBlob(v3(drop.x, drop.y + 0.02 * G_H, drop.z + 0.045 * G_H), v3(0.036 * G_H, 0.036 * G_H, 0.030 * G_H), 4, 7, G_SPARK);
    return b.toMesh();
}

fn gLegMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const knee = v3(side * 0.10 * G_H, 0.04 * G_H, 0.20 * G_H);
    const foot = v3(side * 0.12 * G_H, -0.24 * G_H, 0.14 * G_H);
    b.addCapsule(mathx.zero3, knee, 0.062 * G_H, 0.050 * G_H, 7, G_HIDE);
    b.addCapsule(knee, foot, 0.048 * G_H, 0.038 * G_H, 6, G_HIDE);
    b.addBlob(foot, v3(0.070 * G_H, 0.040 * G_H, 0.085 * G_H), 5, 8, G_HIDE_LT);
    return b.toMesh();
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB301);
    b.setMat(.hide);
    // CHUBSY (owner: it looked anemic, no mass) — the glutes overlap the thighs' own sockets.
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.142 * H, 0.094 * H, 0.114 * H), 6, 10, HIDE);
    b.addBlob(v3(0, -0.030 * H, 0.008 * H), v3(0.122 * H, 0.064 * H, 0.094 * H), 5, 9, HIDE_DK);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addBlob(v3(side * 0.070 * H, -0.030 * H, -0.062 * H), v3(0.062 * H, 0.056 * H * rng.range(0.92, 1.08), 0.058 * H), 5, 8, HIDE);
        b.addBlob(v3(side * 0.108 * H, 0.030 * H, 0), v3(0.036 * H, 0.030 * H * rng.range(0.9, 1.1), 0.042 * H), 4, 7, HIDE_LT);
    }
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB302);
    b.setMat(.hide);
    // THE BELLY IS THE MASS (owner: chubsy).
    b.addCapsule(v3(0, -0.012 * H, 0), v3(0, 0.070 * H, -0.004 * H), 0.124 * H, 0.132 * H, 11, HIDE);
    b.addBlob(v3(0, 0.008 * H, 0.062 * H), v3(0.108 * H, 0.088 * H, 0.070 * H), 6, 10, HIDE);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addBlob(v3(side * 0.105 * H, -0.020 * H, 0.010 * H), v3(0.050 * H, 0.056 * H * rng.range(0.9, 1.1), 0.062 * H), 5, 8, HIDE_DK);
    }
    b.addBlob(v3(0, 0.026 * H, 0.128 * H), v3(0.046 * H, 0.038 * H, 0.020 * H), 5, 8, GUT);
    b.addBlob(v3(0, 0.020 * H, 0.136 * H), v3(0.030 * H, 0.026 * H, 0.013 * H), 4, 7, rgba(12, 10, 10, 255));
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB303);
    b.setMat(.hide);
    // A BARREL WITH THE SHOULDERS ON IT (owner: chubsy — the old narrow trunk read anemic). The shoulder masses OVERLAP the arm sockets.
    b.addCapsule(v3(0, -0.006 * H, -0.004 * H), v3(0, 0.058 * H, -0.008 * H), 0.112 * H, 0.120 * H, 12, HIDE);
    b.addBlob(v3(0.128 * H, 0.052 * H, -0.006 * H), v3(0.068 * H, 0.056 * H, 0.060 * H), 5, 9, HIDE_LT);
    b.addBlob(v3(-0.128 * H, 0.038 * H, -0.002 * H), v3(0.062 * H, 0.050 * H, 0.056 * H), 5, 9, HIDE_LT);
    inline for (.{ 1.0, -1.0 }, .{ 0.0, -0.008 }) |side, sag| {
        b.addBlob(v3(side * 0.058 * H, (0.012 + sag) * H, 0.084 * H), v3(0.058 * H, 0.048 * H * rng.range(0.92, 1.1), 0.040 * H), 5, 8, HIDE);
    }
    b.setMat(.leather);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addBox(
            v3(side * 0.060 * H, 0.040 * H, 0.010 * H),
            v3(0.020 * H, 0, 0),
            v3(0, 0.006 * H, 0),
            v3(0, 0, 0.100 * H),
            STRAP,
        );
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addCapsule(v3(0, -0.012 * H, -0.004 * H), v3(0, 0.030 * H, 0.070 * H), 0.062 * H, 0.050 * H, 10, HIDE);
    b.addBlob(v3(0, -0.008 * H, -0.024 * H), v3(0.066 * H, 0.042 * H, 0.040 * H), 5, 8, HIDE_DK);
    return b.toMesh();
}

fn skullMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB305);
    b.setMat(.hide);
    b.addBlob(v3(0, 0.006 * H, 0), v3(0.052 * H, 0.050 * H, 0.056 * H), 6, 10, HIDE);
    b.addBlob(v3(0, 0.030 * H, 0.026 * H), v3(0.048 * H, 0.014 * H, 0.026 * H), 4, 8, HIDE_LT);
    b.addBlob(v3(0.040 * H, -0.010 * H, 0.030 * H), v3(0.026 * H, 0.024 * H, 0.024 * H), 4, 7, HIDE);
    b.addBlob(v3(-0.038 * H, -0.012 * H, 0.032 * H), v3(0.023 * H, 0.021 * H, 0.022 * H), 4, 7, HIDE);
    b.addBlob(v3(0, -0.044 * H, 0.028 * H), v3(0.036 * H, 0.020 * H, 0.028 * H), 4, 7, HIDE_DK);
    b.addCapsule(v3(-0.034 * H, -0.026 * H, 0.030 * H), v3(0.034 * H, -0.028 * H, 0.030 * H), 0.022 * H, 0.022 * H, 7, HIDE_DK);
    b.addBlob(v3(0, -0.024 * H, 0.062 * H), v3(0.032 * H, 0.020 * H, 0.020 * H), 4, 7, HIDE_DK);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const x = -0.026 * H + 0.0104 * H * @as(f32, @floatFromInt(i));
        const len = 0.014 * H * rng.range(0.6, 1.25);
        b.addCapsule(v3(x, -0.012 * H, 0.058 * H), v3(x, -0.012 * H - len, 0.060 * H), 0.0042 * H, 0.0022 * H, 4, BONE);
        b.addCapsule(v3(x, -0.032 * H, 0.056 * H), v3(x, -0.032 * H + len * 0.8, 0.058 * H), 0.0040 * H, 0.0020 * H, 4, BONE_DK);
    }
    b.addBlob(v3(0.026 * H, 0.014 * H, 0.038 * H), v3(0.012 * H, 0.010 * H, 0.008 * H), 3, 6, EYE);
    b.addBlob(v3(-0.026 * H, 0.014 * H, 0.038 * H), v3(0.012 * H, 0.010 * H, 0.008 * H), 3, 6, EYE);
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const len = heromod.SEG_THIGH * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.076 * H, 0.056 * H, 10, HIDE);
    b.addBlob(v3(0, 0.014 * H, -0.006 * H), v3(0.082 * H, 0.068 * H, 0.078 * H), 5, 8, HIDE);
    b.addBlob(v3(0, -len * 0.35, -0.010 * H), v3(0.056 * H, 0.062 * H, 0.052 * H), 4, 8, HIDE_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const len = heromod.SEG_SHANK * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.058 * H, 0.038 * H, 9, HIDE);
    b.addBlob(v3(0, 0.008 * H, -0.004 * H), v3(0.062 * H, 0.056 * H, 0.058 * H), 5, 8, HIDE);
    b.addBlob(v3(0, -len * 0.25, -0.016 * H), v3(0.048 * H, 0.056 * H, 0.044 * H), 4, 7, HIDE_LT);
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const ay = 0.039 * H;
    b.addBlob(v3(0, -ay + 0.028 * H, 0.028 * H), v3(0.066 * H, 0.035 * H, 0.096 * H), 5, 9, HIDE);
    b.addBlob(v3(side * 0.010 * H, -ay + 0.017 * H, 0.100 * H), v3(0.050 * H, 0.020 * H, 0.040 * H), 4, 7, HIDE_DK);
    return b.toMesh();
}

fn upperArmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const len = heromod.SEG_UPARM * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.048 * H, 0.038 * H, 9, HIDE);
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.056 * H, 0.052 * H, 0.054 * H), 5, 8, HIDE);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const len = heromod.SEG_FOREARM * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len * 1.34, 0), 0.040 * H, 0.030 * H, 9, HIDE);
    b.addBlob(v3(0, 0.006 * H, 0), v3(0.046 * H, 0.044 * H, 0.045 * H), 4, 7, HIDE);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB30A);
    b.setMat(.hide);
    b.addBlob(v3(0, -0.024 * H, 0.004 * H), v3(0.028 * H, 0.034 * H, 0.024 * H), 4, 8, HIDE);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const x = -0.016 * H + 0.0107 * H * @as(f32, @floatFromInt(i));
        const drop = 0.040 * H * rng.range(0.74, 1.12);
        b.addCapsule(v3(x, -0.048 * H, 0.006 * H), v3(x, -0.048 * H - drop, 0.014 * H), 0.0075 * H, 0.0045 * H, 5, HIDE_DK);
    }
    return b.toMesh();
}

/// Sides over relief (`AGENTS.md`): the bands are a couple of percent proud and the side count is what makes it round.
fn bellMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB30B);
    b.setMat(.gilt);
    const drop = BELL_DROP;
    const r = BELL_R;
    b.addBlob(v3(0, 0, 0), v3(r * 0.44, r * 0.30, r * 0.44), 5, 12, BRONZE_DK);
    b.addCapsule(v3(0, -r * 0.12, 0), v3(0, -drop * 0.46, 0), r * 0.52, r * 0.82, 14, BRONZE);
    b.addCapsule(v3(0, -drop * 0.44, 0), v3(0, -drop * 0.88, 0), r * 0.84, r * 1.0, 14, BRONZE);
    b.addCapsule(v3(0, -drop * 0.86, 0), v3(0, -drop, 0), r * 1.02, r * 0.98, 14, BRONZE_LIP);
    inline for (.{ 0.34, 0.66 }) |u| {
        const y = -drop * u;
        b.addCapsule(
            v3(0, y, 0),
            v3(0.004 * H * rng.signed(), y - drop * 0.045, 0),
            r * (0.62 + 0.28 * u) * 1.035,
            r * (0.62 + 0.28 * u) * 1.03,
            14,
            BRONZE_DK,
        );
    }
    b.setMat(.leather);
    b.addBox(v3(0, r * 0.20, 0), v3(r * 0.34, 0, 0), v3(0, r * 0.16, 0), v3(0, 0, r * 0.10), STRAP);
    return b.toMesh();
}

fn clapperMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.gilt);
    b.addCapsule(v3(0, -BELL_DROP * 0.20, 0), v3(0, -BELL_DROP * 0.74, 0), 0.010 * H, 0.014 * H, 6, BRONZE_DK);
    b.addBlob(v3(0, -BELL_DROP * 0.78, 0), v3(BELL_R * 0.30, BELL_R * 0.30, BELL_R * 0.30), 4, 8, BRONZE_LIP);
    return b.toMesh();
}

test "IT IS A FOE — its own tether, its own souls, and it answers for its own kind" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.tolling_hollow, h.kind());
    try std.testing.expectEqual(foe.Nature.undead, foe.traitsOf(h.kind()).nature);
    try std.testing.expect(h.alive() and !h.dying() and !h.staggered());
    try std.testing.expect(h.hurtRadius() > h.bodyR());
    try std.testing.expect(h.topWorld().y > h.centerWorld().y);
    const markOut = mathx.lenV(mathx.subV(h.centerWorld(), h.lockPoint()));
    std.debug.print("\n  hollow mark stands {d:.2} m off the hurt centre (sphere r {d:.2}, body r {d:.2})\n", .{ markOut, h.hurtRadius(), h.bodyR() });
    try std.testing.expect(markOut < h.hurtRadius());
}

test "HIGH HP, LOW DEF, LOW DAMAGE — the three numbers the creature IS" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(HP_MAX > 300.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.vit.armour, 1e-6);
    const raw = combat.Hit{ .dmg = 40 };
    try std.testing.expectApproxEqAbs(@as(f32, 40), h.vit.damageFrom(raw), 1e-4);
    std.debug.print("\n  hollow: {d:.0} HP, {d:.0} armour, bite {d:.0} dmg / {d:.0} poise\n", .{ HP_MAX, h.vit.armour, BITE_HIT.dmg, BITE_HIT.poise });
    try std.testing.expect(BITE_HIT.dmg < 16.0);
    try std.testing.expect(BITE_HIT.poise > 20.0);
}

test "THE BELL IS THE HOLE — lightning is the worst weakness in the field" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    const levin = combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) };
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) };
    const cold = combat.Hit{ .elem = combat.elems(.{ .cold = 20 }) };
    try std.testing.expectApproxEqAbs(@as(f32, 34.0), h.vit.damageFrom(levin), 1e-3);
    try std.testing.expect(h.vit.damageFrom(fire) > 20.0);
    try std.testing.expect(h.vit.damageFrom(cold) < 20.0);
    try std.testing.expect(h.vit.res.at(.lightning) < -60.0);
}

test "YOU CANNOT STUNLOCK IT — the hero's heavy swing does not flinch it" {
    var light = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.none, light.vit.hit(heromod.ATK_LIGHT_HIT));
    var heavy = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.none, heavy.vit.hit(heromod.ATK_HEAVY_HIT));
    try std.testing.expect(POISE_MAX > heromod.ATK_HEAVY_HIT.poise);
}

test "STANDING IN ITS FACE SILENCES THE BELL AND THE SPARKS BOTH" {
    const ring = triggerR(foe.HERO_R);
    try std.testing.expectEqual(Choice.bite, classify(1.0, ring, true, true, true));
    try std.testing.expectEqual(Choice.walk, classify(1.0, ring, false, true, true));
    try std.testing.expectEqual(Choice.toll, classify(9.0, ring, true, true, true));
    try std.testing.expectEqual(Choice.spark, classify(9.0, ring, true, false, true));
    try std.testing.expectEqual(Choice.walk, classify(9.0, ring, true, false, false));
    try std.testing.expectEqual(Choice.walk, classify(SPARK_MAX + 1.0, ring, true, false, true));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, ring, true, true, true));
    try std.testing.expectApproxEqAbs(BITE_TRIGGER_R + foe.HERO_R, ring, 1e-6);
}

test "A STAGGERED THREE — the volley fires exactly `SPARK_N`, one at a time, at any frame length" {
    for ([_]f32{ 1.0 / 144.0, 1.0 / 60.0, 1.0 / 24.0 }) |dt| {
        var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
        h.leash.noteSeen();
        h.state = .spark;
        h.t = 0;
        h.sparksOut = 0;
        var fired: u32 = 0;
        var gaps: [SPARK_N]f32 = undefined;
        var lastAt: f32 = -1;
        var t: f32 = 0;
        while (t < SPARK_WIND + volleySpan() + SPARK_RECOVER + 0.5) : (t += dt) {
            const wasState = h.state;
            _ = h.update(dt, mathx.ground(0, 9.0), 200.0, .{});
            if (h.sparked) {
                // `sparksOut` is a COUNT, not an edge, so a long frame catches up rather than firing the rest of the volley at once.
                if (lastAt >= 0) gaps[fired - 1] = t - lastAt;
                lastAt = t;
                fired += 1;
                try std.testing.expect(fired <= SPARK_N);
            }
            if (wasState == .spark and h.state != .spark) break;
        }
        try std.testing.expectEqual(@as(u32, SPARK_N), fired);
        for (gaps[0 .. SPARK_N - 1]) |gp| {
            try std.testing.expect(gp >= SPARK_GAP - dt * 1.5 and gp <= SPARK_GAP + dt * 1.5);
        }
        std.debug.print("  spark volley at dt {d:.4}: {d} shots, gaps {d:.2} s (authored {d:.2}, roll i-frames {d:.2})\n", .{ dt, fired, gaps[0], SPARK_GAP, heromod.ROLL_IFRAME_END_BANK });
        try std.testing.expect(h.sparkCool > 0);
    }
}

test "THE RIDER SITS ON THE BELL AND THE SPARK LEAVES ITS FISTS — both measured off the pose" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.pose();
    const bell = h.bellWorld();
    const seat = foe.markOn(h.bellMat, v3(0, G_SEAT, 0));
    const rump = foe.markOn(h.gxf[G_RUMP], mathx.zero3);
    const head = foe.markOn(h.gxf[G_HEAD], mathx.zero3);
    const fists = h.sparkWorld();
    std.debug.print("\n  hollow {d:.2} m tall, hunched {d:.0} deg; bell at {d:.2} m, rider's rump {d:.2} m, its head {d:.2} m\n", .{ h.topWorld().y - h.pos.y, HUNCH, bell.y, rump.y, head.y });
    // **ITS RUMP IS THE SEAT**, to the millimetre: `G_REST[G_RUMP]` is the rig's zero, so no leg pose can lift the rider off the bronze (a feet-rooted rig left 0.3 m of daylight).
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.lenV(mathx.subV(rump, seat)), 1e-4);
    const crownTop = foe.markOn(h.bellMat, v3(0, BELL_R * 0.30, 0));
    try std.testing.expect(seat.y >= crownTop.y - 1e-4);
    const torso = foe.markOn(h.gxf[G_TORSO], mathx.zero3);
    try std.testing.expect(mathx.lenV(mathx.subV(torso, rump)) < G_H * h.scale * 0.35);
    try std.testing.expect(head.y > rump.y);
    try std.testing.expect(G_H * 3.0 < H * SCALE);
    std.debug.print("  …spark leaves the fists {d:.2} m up, {d:.2} m off the rider's own rump\n", .{ fists.y, mathx.lenV(mathx.subV(fists, rump)) });
    try std.testing.expect(mathx.lenV(mathx.subV(fists, rump)) > G_H * 0.15);
    try std.testing.expect(fists.y > h.pos.y + 1.0);
}

test "THE BELL STRIKES ONCE PER TOLL, whatever the frame length" {
    for ([_]f32{ 1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0 }) |dt| {
        var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
        h.leash.noteSeen();
        h.debugToll();
        var strikes: usize = 0;
        var t: f32 = 0;
        while (t < TOLL_WIND + TOLL_SWING + TOLL_RECOVER + 0.1) : (t += dt) {
            _ = h.update(dt, mathx.ground(0, 9.0), 200.0, .{});
            if (h.tolled) strikes += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), strikes);
    }
}

test "A TOLL IS A SUMMONS, NOT A WOUND — it rouses a camp without breaking its leashes" {
    const Body = struct {
        pos: rl.Vector3,
        leash: foe.Leash = .{},
        gone: bool = false,
        down: bool = false,
        pub fn alive(self: *const @This()) bool {
            return !self.gone;
        }
        pub fn dying(self: *const @This()) bool {
            return self.down;
        }
    };
    var camp = [_]Body{
        .{ .pos = mathx.ground(0, 4) },
        .{ .pos = mathx.ground(0, TOLL_R - 1.0) },
        .{ .pos = mathx.ground(0, TOLL_R + 2.0) },
        .{ .pos = mathx.ground(0, 6), .down = true },
    };
    const heard = foe.rouseWithin(&camp, mathx.zero3, TOLL_R);
    try std.testing.expectEqual(@as(u32, 2), heard);
    try std.testing.expect(camp[0].leash.roused() and camp[1].leash.roused());
    try std.testing.expect(!camp[2].leash.roused());
    try std.testing.expect(!camp[3].leash.roused()); // a body already falling does not answer a bell
    // FOUR TOLLS MAY NOT BUY WHAT THREE BLOWS DO: the break belongs to being hit.
    var k: usize = 0;
    while (k < 4) : (k += 1) _ = foe.rouseWithin(&camp, mathx.zero3, TOLL_R);
    try std.testing.expectApproxEqAbs(@as(f32, 0), camp[0].leash.provoked, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), camp[0].leash.breakLeft, 1e-6);
    try std.testing.expect(!camp[0].leash.goingHome());
}

test "THE BELL CARRIES FURTHER THAN THE CREATURE SEES — that IS the mechanic" {
    try std.testing.expect(TOLL_R > AGGRO_R);
    std.debug.print("\n  hollow: notices at {d:.0} m, its bell carries {d:.0} m\n", .{ AGGRO_R, TOLL_R });
}

test "THE BELL IS SPRUNG, NOT ASSIGNED — it overshoots the haul and settles back onto rest" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.debugToll();
    const dt: f32 = 1.0 / 120.0;
    // …with nobody in its patch, so what the bell settles ONTO is rest and not the walk's own lag.
    const away = mathx.ground(0, AGGRO_R * 4.0);
    var t: f32 = 0;
    var lo: f32 = 0;
    while (t < TOLL_WIND + TOLL_SWING) : (t += dt) {
        _ = h.update(dt, away, 200.0, .{});
        lo = mathx.minF(lo, h.bellAng);
    }
    std.debug.print("\n  bell hauled to {d:.1} deg against a {d:.1} deg drive\n", .{ lo, -BELL_HAUL });
    try std.testing.expect(lo < -BELL_HAUL);
    var crossings: usize = 0;
    var was = h.bellAng;
    t = 0;
    while (t < 2.0) : (t += dt) {
        _ = h.update(dt, away, 200.0, .{});
        if ((was < 0) != (h.bellAng < 0)) crossings += 1;
        was = h.bellAng;
    }
    std.debug.print("  …and rang through rest {d} times before settling to {d:.2} deg\n", .{ crossings, h.bellAng });
    try std.testing.expect(crossings >= 2);
    try std.testing.expect(@abs(h.bellAng) < 3.0);
}

test "IT BITES ONCE PER GAPE, and only what is in front of it" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.leash.noteSeen();
    const hero = mathx.ground(0, 1.4);
    var landed: usize = 0;
    var gaped = false;
    var t: f32 = 0;
    while (t < 4.0) : (t += 1.0 / 60.0) {
        if (h.update(1.0 / 60.0, hero, 200.0, .{})) |blow| {
            landed += 1;
            try std.testing.expectApproxEqAbs(BITE_HIT.dmg, blow.dmg, 1e-4);
        }
        if (h.gaped) gaped = true;
        if (landed > 0 and h.state != .bite) break;
    }
    try std.testing.expect(gaped);
    try std.testing.expectEqual(@as(usize, 1), landed);

    var back = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    back.state = .bite;
    back.t = BITE_WIND;
    back.tryBite(mathx.ground(0, -1.4));
    try std.testing.expect(back.heroHit == null);
}

test "A BIG PLACEMENT STILL BITES — the stop ring may never grow past the trigger ring" {
    // The bug this pins: a `stop` scaled by the body against a `triggerR` that is not. It halted outside its own bite ring at every map scale over ~1.23.
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, 1.3, wf.FOE_SCALE_HI }) |sc| {
        var h = Hollow.spawn(mathx.zero3, 0, sc, 0.3);
        h.leash.noteSeen();
        h.tollCool = 99.0; // …so walking up and biting is the only answer it has left
        h.sparkCool = 99.0; // (the rider's volley is the other one, and it would hold the host at range)
        const hero = mathx.ground(0, 11.0);
        var gaped = false;
        var t: f32 = 0;
        while (t < 9.0) : (t += 1.0 / 60.0) {
            _ = h.update(1.0 / 60.0, hero, 200.0, .{});
            if (h.gaped) gaped = true;
        }
        std.debug.print("  scale {d:.2}: halted {d:.2} m off, trigger ring {d:.2} m, gaped={}\n", .{ sc, mathx.distXZ(h.pos, hero), triggerR(foe.HERO_R), gaped });
        try std.testing.expect(gaped);
    }
}

test "A PARRIED BITE IS DROPPED AND PAID FOR" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.debugBite();
    h.t = BITE_WIND + BITE_STRIKE * 0.45 - foe.PARRY_LEAD * 0.5;
    try std.testing.expect(h.parryable() != null);
    h.parry = .{ .live = true, .at = mathx.ground(0, 1.2), .facing = std.math.pi, .arc = combat.GUARD_ARC };
    h.takeParry();
    try std.testing.expect(h.parried);
    try std.testing.expect(h.staggered());
    try std.testing.expect(h.biteCool > 0);
}

test "IT PAYS FOR THE BELL — the toll costs it longer than the bite does, and it travels not at all" {
    try std.testing.expect(TOLL_WIND + TOLL_SWING + TOLL_RECOVER > BITE_WIND + BITE_STRIKE + BITE_RECOVER);
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.leash.noteSeen();
    h.debugToll();
    const was = h.pos;
    var t: f32 = 0;
    while (t < TOLL_WIND + TOLL_SWING) : (t += 1.0 / 60.0) _ = h.update(1.0 / 60.0, mathx.ground(0, 9.0), 200.0, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(was, h.pos), 1e-4);
}

test "IT HAS A HEAD AND A BELL YOU CAN SEE — both stand clear of the chest's own mass" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.pose();
    // The barrel `chestMesh` actually builds: a capsule of 0.092 H about a centre 0.058 H over the joint.
    const CHEST_R: f32 = 0.092 * H;
    const centre = v3(0, REST[CHEST].y + 0.058 * H, REST[CHEST].z - 0.010 * H);
    const headOut = mathx.lenV(mathx.subV(REST[SKULL], centre));
    const bellOut = mathx.lenV(mathx.subV(mathx.addV(BELL_AT, v3(0, REST[CHEST].y, REST[CHEST].z)), centre));
    std.debug.print("\n  hollow: head {d:.2} m and bell {d:.2} m off the chest centre, against a {d:.2} m barrel\n", .{ headOut, bellOut, CHEST_R });
    try std.testing.expect(headOut > CHEST_R);
    try std.testing.expect(bellOut > CHEST_R);
    const jaw = h.jawWorld();
    std.debug.print("  …jaws {d:.2} m up and {d:.2} m forward of its own feet (bite reach {d:.2} m)\n", .{ jaw.y, mathx.distXZ(h.pos, jaw), foe.hurtReach(BITE_R, h.scale) });
    try std.testing.expect(mathx.distXZ(h.pos, jaw) > 0.2);
    try std.testing.expect(jaw.y > 1.2 and jaw.y < h.topWorld().y);
}

test "THE JAWS ARRIVE INSIDE WHAT THE PARRY WINDOW PROMISES — measured off the pose, never argued" {
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.leash.noteSeen();
    h.debugBite();
    const from = h.pos;
    var worst: f32 = 0;
    var t: f32 = 0;
    while (t < BITE_WIND + BITE_STRIKE) : (t += 1.0 / 120.0) {
        _ = h.update(1.0 / 120.0, mathx.ground(0, 2.0), 200.0, .{});
        worst = mathx.maxF(worst, mathx.distXZ(from, h.jawWorld()));
    }
    const promised = foe.hurtReach(BITE_R, h.scale);
    std.debug.print("\n  hollow jaws arrive {d:.2} m out (lunge included); the parry promises {d:.2} m\n", .{ worst, promised });
    try std.testing.expect(worst <= promised);
    try std.testing.expect(worst > promised * 0.7);
    try std.testing.expect(BITE_HIT.dmg < ogremod.SLAM_HIT.dmg * 0.5);
}

test "IT HINGES AT THE WAIST AND ITS LEGS STAY PLANTED" {
    try std.testing.expectApproxEqAbs(@as(f32, ogremod.PELVIS_SHARE), @as(f32, PELVIS_SHARE), 1e-6);
    try std.testing.expect(PELVIS_SHARE < 0.25);
    var h = Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.pose();
    const heelL = foe.markOn(h.xf[ANKL], mathx.zero3);
    const heelR = foe.markOn(h.xf[ANKR], mathx.zero3);
    std.debug.print("\n  hollow hunch {d:.0} deg: pelvis takes {d:.0} deg, the waist {d:.0}; heels at {d:.2} m / {d:.2} m\n", .{ HUNCH, PELVIS_SHARE * HUNCH, (1.0 - PELVIS_SHARE) * HUNCH, heelL.y, heelR.y });
    try std.testing.expect(heelL.y < 0.35 and heelR.y < 0.35);
}
