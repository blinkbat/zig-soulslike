const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;


const HIDE = rgba(44, 27, 21, 255);
const HIDE_DK = rgba(25, 15, 12, 255);
const HIDE_LT = rgba(63, 38, 29, 255);
const BELLY = rgba(58, 44, 31, 255);
const SCAR = rgba(82, 62, 46, 255);
const EYE = rgba(242, 192, 96, 58);
const EYE_RIM = rgba(20, 16, 13, 255);
const PUPIL = rgba(8, 6, 5, 255);
const TUSK = rgba(140, 130, 106, 255);
const TUSK_DK = rgba(104, 96, 78, 255);
const RAG = rgba(38, 32, 26, 255);
const ROPE = rgba(52, 42, 29, 255);
const CLUB_WOOD = rgba(30, 21, 13, 255);
const CLUB_WOOD_LT = rgba(44, 32, 20, 255);
const CLUB_STONE = rgba(45, 43, 40, 255);
const CLUB_IRON = rgba(50, 46, 42, 255);
const IRON_RUST = rgba(72, 46, 26, 255);
const MAW = rgba(14, 8, 7, 255);
const TONGUE = rgba(58, 25, 23, 255);
const PARRY_SPARK = rgba(236, 170, 84, 230);
/// A struck spark is LIGHT and it COOLS — the hero's own catch cools the same way (`hero.PARRY_SPARK_COOL`).
const PARRY_SPARK_COOL = rgba(206, 96, 30, 190);

const N = 24;
const ROOT = 0;
const SPINE = 1;
const CHEST = 2;
const NECK = 3;
const SKULL = 4;
const HIPL = 5;
const KNEEL = 6;
const ANKL = 7;
const HIPR = 8;
const KNEER = 9;
const ANKR = 10;
const SHL = 11;
const ELL = 12;
const WRL = 13;
const SHR = 14;
const ELR = 15;
const WRR = 16;
const CLUB = 17;
const JAW = 18;
const TOEL = 19;
const TOER = 20;
const HUMP = 21;
const CLAVL = 22;
const CLAVR = 23;

const parent = [N]i32{ -1, ROOT, SPINE, HUMP, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CLAVL, SHL, ELL, CLAVR, SHR, ELR, WRR, SKULL, ANKL, ANKR, CHEST, CHEST, CHEST };

// Where this giant carries his weight, MEASURED off `footMesh`: the fat pad under each ankle, which `hero.legChain` levels every frame so the sole cannot rake through the ground.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.094 * H, .toe = 0.144 * H, .halfW = 0.082 * H, .drop = 0.039 * H },
    .{ .bone = ANKR, .heel = 0.094 * H, .toe = 0.144 * H, .halfW = 0.082 * H, .drop = 0.039 * H },
};

const H: f32 = heromod.H;
const SEG_THIGH = heromod.SEG_THIGH; // shared with the hero — legChain's geometry is measured off
const SEG_SHANK = heromod.SEG_SHANK;
const SEG_UPARM = 0.194;
const SEG_FOREARM = 0.153;

const REST = restPositions();

fn restPositions() [N]rl.Vector3 {
    const hx = 0.135;
    const sx = 0.235;
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.645, 0);
    r[CHEST] = v3(0, 0.775, 0);
    r[NECK] = v3(0, 0.842, 0.048);
    r[SKULL] = v3(0, 0.925, 0.104); // MEASURED against the chest barrel's top: at 0.070 the whole head sat
    // between the shoulder blobs and vanished from every rear quarter
    r[HIPL] = v3(hx, 0.530, 0);
    r[KNEEL] = v3(hx, 0.285, 0);
    r[ANKL] = v3(hx, 0.039, 0);
    r[HIPR] = v3(-hx, 0.530, 0);
    r[KNEER] = v3(-hx, 0.285, 0);
    r[ANKR] = v3(-hx, 0.039, 0);
    r[SHL] = v3(sx, 0.791, 0);
    r[ELL] = v3(sx, 0.556, 0);
    r[WRL] = v3(sx, 0.361, 0);
    r[SHR] = v3(-sx, 0.809, 0);
    r[ELR] = v3(-sx, 0.574, 0);
    r[WRR] = v3(-sx, 0.379, 0);
    r[CLUB] = v3(-sx, 0.379, 0);
    r[JAW] = v3(0, 0.905, 0.124); // = SKULL + (0, −0.020, +0.020); jawMesh is authored to that offset
    r[TOEL] = v3(hx, 0.026, 0.095);
    r[TOER] = v3(-hx, 0.026, 0.095);
    r[HUMP] = v3(0, 0.792, -0.020);
    r[CLAVL] = v3(0.075, 0.803, 0);
    r[CLAVR] = v3(-0.075, 0.812, 0);
    for (&r) |*p| p.* = v3(p.x * H, p.y * H, p.z * H);
    return r;
}

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;

fn stridePulse(x: f32, a: f32, b: f32) f32 {
    if (x <= a or x >= b) return 0;
    return mathx.sinf(std.math.pi * (x - a) / (b - a));
}

fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    heromod.setJoint(wx, &rest, i, @intCast(parent[i]), animRot);
}

// A hulking giant — ~4.1 m to the crown, a shade over twice the hero. The dial has been walked: 2.5 rejected as too big, 2.1 as too small, 2.4 read big again, and the owner has now asked for a bit off it.
pub const SCALE = 2.3;
const WALK_SPEED = heromod.WALK_SPEED * 0.72;
pub const AGGRO_R = 18.0;
const SLAM_R = 2.3;
const SWIPE_R = 4.4;
/// **THE REFERENCE FOR HOW HARD A BIG BODY FOLLOWS YOU** — PUBLIC because the bone knight is pinned into this
/// class rather than tuned against nothing (owner: track like the ogre). rad/s; ~195 deg/s.
pub const TURN_RATE = 3.4;
pub const SWIPE_TURN = 5.4;
/// DOWN off the CHEST joint (which sits at the top of the barrel, 0.775·H) — owner's call, the mark rode too high. Now ~0.715·H, 2.9 m of a 4.1 m creature, inside the hurt sphere (0.8..4.1 m) and clear of the skull at 0.925·H. It still HINGES with the chest through the slam.
const LOCK_AT = v3(0, -0.06 * H, 0);
const BODY_R = 0.55; // ground footprint (pre-scale) — broad
const HURT_R = 0.72; // hurt-sphere radius the hero's blade tests against (pre-scale) — a big target
const A_BOB = 0.030 * H;
const A_SWAY = 0.014 * H;
const A_LUMBER = 6.5;
const A_PROT = 6.0; // deg of pelvic TRANSVERSE rotation — the swagger (the hero walks on 3.5)
const TRUNK_NOD = 5.5;

const WINDUP_DUR = 1.35;
const SLAM_DUR = 0.22;
const SLAM_IMPACT_K = 0.85;
// MEASURED off the posed club's arc, which first touches the earth at ~0.19 s of the 0.22 s crash
const RECOVER_DUR = 1.20;
const SLAM_CD = 1.3;

const SWIPE_WIND_DUR = 0.52;
const SWIPE_DUR = 0.20;
const SWIPE_IMPACT_K = 0.42;
const SWIPE_REC_DUR = 0.52;
const SWIPE_CD = 1.05;

const BACK_WIND_DUR = 0.44;
const BACK_DUR = 0.24;
const BACK_IMPACT_K = 0.45;
const BACK_CHANCE = 0.55;
const BACK_ARC_MID = -65.0; // deg — the return's own swept sector (MEASURED off the posed bone, like the
const BACK_ARC = 175.0;

const DRIVE_WIND_DUR = 0.72;
const DRIVE_DUR = 0.62;
const DRIVE_IMPACT_K = 0.78;
const DRIVE_SPEED = 9.0; // m/s through the surge (~4.3 m covered)
const DRIVE_REC_DUR = 0.95;
const DRIVE_CD = 5.0;
const DRIVE_MIN = 4.5;
const DRIVE_MAX = 7.0;
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 6.0;
const STUN_EASE_DEG = 260.0;
const STUN_EASE_FRAC = 4.0;

const HP_MAX = 300.0;
const POISE_MAX = 30.0;
const STANCE_MAX = 90.0;
const RESISTS = combat.resists(.{ .fire = 30, .cold = 30, .lightning = -15, .chaos = 20 });
pub const SLAM_HIT = combat.Hit{ .dmg = 36, .poise = 44, .stance = 20, .launch = combat.SLAM_LAUNCH };
pub const SWIPE_HIT = combat.Hit{ .dmg = 23, .poise = 30, .stance = 11 };
pub const DRIVE_HIT = combat.Hit{ .dmg = 31, .poise = 40, .stance = 20 };
const DEATH_DUR = 1.7;
/// Fraction of `DEATH_DUR` at which the trunk ARRIVES on the earth — the fall accelerates to here
/// (a mass on a hinge, the knight's law), the settle overshoots past it, and the landing is an EVENT.
const DEATH_LAND = 0.62;
pub const SOULS: u32 = 900;
const DISS_DUR = 1.1;
const DISSOLVE = foe.Dissolve{ .rate = 70.0, .spread = 1.0, .rise = 0.70 };

const HERO_REACH = foe.HERO_REACH;
const SLAM_LEN = 1.05; // crush strip length ahead of the seat (pre-scale).
const SLAM_HALF_W = 0.45; // crush strip HALF-width (pre-scale) — about the club head + shock
const SWIPE_INNER = 1.18; // pre-scale: nearer than this and the club passes over you.
const SWIPE_SLACK_MIN_D = 0.5;
const SWIPE_OUTER = 1.95;
// The sector is NOT centred on his facing: the club starts cocked behind his right shoulder and finishes
// past his left, so the swept bearings run ~−119..+22 (MEASURED off the posed bone, height 2.37 → 1.07).
const SWIPE_ARC_MID = -48.0;
const SWIPE_ARC = 144.0;

// ONE NUMBER FOR BOTH MOVES (owner's call), IN SECONDS back from that move's own impact frame: a parry reads
// the blow ARRIVING, never the tell starting, so the window ends where the club does. As two fractions of two
// state clocks the slam's came out at 0.29 s, most of it with the club overhead and motionless. Now the whole
// game's (`foe.PARRY_LEAD`).
const PARRY_LEAD = foe.PARRY_LEAD;

const HUNCH = 9.0;
// HE HINGES AT THE WAIST (owner's law): the fraction of any body pitch the PELVIS may take. **PUBLIC because it is the LAW and not his own number** (`AGENTS.md` names it `ogre.PELVIS_SHARE`) — a second copy of 0.16 is a second thing to forget when the law is retuned.
pub const PELVIS_SHARE = 0.16;
// THE CARRY (owner's law): the club is HEFTED AT HIS SIDE, never dragged.
const CARRY_SH = 5.0;
const CARRY_EL = -13.0;
const CARRY_TILT = 44.0;
const WIND_TILT = 30.0;
const SLAM_TILT = -14.0;
// REACH against DEPTH along one arc: raked further ahead the head lands further out but higher — measured, −30 put the crater 2.1 out and 0.66 in the air, a slam that missed the earth.
const OVER_SH = -158.0;
const WIND_EL = -78.0;
const SLAM_SH = -56.0;
const SLAM_EL = -6.0;
const OFF_SH = -14.0;
const OFF_EL = -18.0;
const HEAD_DROOP = 8.0;
const HEAD_YAW_MAX = 55.0;
const HEAD_TRACK_RATE = 220.0;
const HEAD_SCAN = 26.0;
const HEAD_LOOK_DOWN = 16.0;

const OFF_ARM_SWING = 26.0;
const OFF_ELBOW_SWING = 22.0;
const CLUB_ARM_SWING = 9.0;
const CLUB_ELBOW_SWING = 6.0;
const CLUB_LAG = 0.6;
const CLUB_PEND = 7.0;
const PEND_LAG = 1.0;
const CLUB_ABD = 22.0;
const WIND_ABD = 16.0;
const SLAM_ABD = -14.0; // NEGATIVE = adducted ACROSS the body: the shoulder sits ~0.9 out to his
const OFF_ABD = 14.0;
const ARM_ABD_SWING = 0.35;
const WRIST_FLOP = 0.30;
const CLUB_HOLD = 0.6;

const JAW_REST = 5.0; // deg ajar at rest — a heavy underbite never quite closes
const JAW_BREATHE = 4.5;
const JAW_STALK = 7.0;
const JAW_ROAR = 36.0;
const JAW_GRIT = 6.0;
const JAW_PANT = 24.0;
const JAW_FLINCH = 26.0;
const JAW_DEATH = 32.0;
const JAW_JOSTLE = 5.0;

const GIRDLE_HEAVE = 3.6;
const GIRDLE_SWING = 0.30;
const GIRDLE_LAG = 0.85;
const GIRDLE_PROT = 0.40;
const GIRDLE_WIND = 15.0;
const GIRDLE_SPENT = -10.0;
const CLAV_DROOP = 6.0;
const CLAV_LOAD = 0.30;

const TOE_PUSH = 26.0;
const TOE_LIFT = 15.0;
const TOE_GRIP = 22.0;
const TOE_CURL = 24.0;

const HIP_ADDUCT = heromod.HIP_ADDUCT;
const FOOT_TOEOUT = heromod.FOOT_TOEOUT;
const IDLE_KNEE = heromod.IDLE_KNEE;
const IDLE_RATE = 1.5; // rad/s of the slow weight-shift cycle (~4.2 s period — heavy, unhurried)
const BREATHE_RATE = 1.05;
const A_BREATHE = 0.012 * H;
const A_IDLE_SWAY = 0.020 * H;
const IDLE_ROLL = 3.2;
const STANCE_WIDEN = 3.5;
// THE LEGS STAND PLANTED (owner's law).
const BRACE_HIP = 12.0;
const BRACE_KNEE = 24.0;
const BRACE_SINK = 0.011 * H;

/// Sized by ARITHMETIC over the worst frame (the ring law): a KILLING HEAVY BLOW landing on the frame the DRIVE hits. The drive lays 42 dust; `tryHit` then fires the heavy spray (30), the death spray (24) and `foe.wounded`'s 3. That is 99.
const FX_MAX = 100;
const DUST = foe.DUST;
/// A BIGGER BODY THROWS FURTHER — the toad's dials over a giant's wound read as a nick. Same shape as `frog.BLOOD_SPRAY`: the fan is the number that opens it, and drag turns the throw into a burst.
const BLOOD_SPRAY = foe.Spray{
    .fanLo = 0.8,  .fanHi = 4.6,
    .upLo = 1.0,   .upHi = 4.2,
    .lifeLo = 0.70, .lifeHi = 1.15,
    .rLo = 0.04,   .rHi = 0.08,
    .r1 = 0.01,    .col = BLOOD, .grav = foe.BLOOD_GRAV,
    .col1 = rgba(40, 9, 7, 225), .stretch = foe.BLOOD_STRETCH, .splat = 3.0, .drag = foe.BLOOD_DRAG,
};
const BLOOD_LIGHT = 10;
const BLOOD_HEAVY = 20;
const BLOOD_DEATH = 16;
const BLOOD_SPD_LIGHT = 5.4;
const BLOOD_SPD_HEAVY = 7.6;
const BLOOD_SPD_DEATH = 6.4;
comptime {
    // THE RING LAW, EXECUTABLE: the drive's 42 dust with a killing heavy blow's two sprays and the shared wound.
    std.debug.assert(FX_MAX >= 42 + foe.hitParts(BLOOD_HEAVY) + foe.hitParts(BLOOD_DEATH) + foe.WOUND_PARTS);
}
const BLOOD = rgba(84, 20, 16, 235);

const Particle = foe.Particle;

const State = enum { idle, approach, windup, slam, swipewind, swipe, backwind, backswipe, drivewind, drive, recover, stunlight, stunheavy, dead };

const Choice = enum { slam, swipe, drive, approach, wait, idle };
const SWIPE_BEARING = 32.0;
/// UP IN HIS FACE THE QUICK ONE WINS (owner's call). Fraction of the sweep band, out from its inner edge, inside which the swipe beats the slam even squared up with the slam ready — the 0.52 s cock-back rather than the 1.35 s rear.
const SWIPE_NEAR_K = 0.5;
fn classify(dist: f32, bearingDeg: f32, slamReady: bool, swipeReady: bool, driveReady: bool, swipeInner: f32) Choice {
    if (dist > AGGRO_R) return .idle;
    const offFront = @abs(bearingDeg) > SWIPE_BEARING;
    // AND THE SWIPE HAS TO BE ABLE TO LAND. Its arc passes clean OUTSIDE anything hugging his legs, and collision
    // holds the hero at 1.68 m where the sweep only starts biting at 2.28 — so toe to toe, choosing it spent two thirds of a second on a guaranteed miss. The pocket at his feet is EARNED; he looms instead (`.wait`).
    const inSweep = dist >= swipeInner and dist <= SWIPE_R;
    const near = swipeInner + (SWIPE_R - swipeInner) * SWIPE_NEAR_K;
    if (inSweep and swipeReady and (offFront or !slamReady or dist <= near)) return .swipe;
    if (dist <= SLAM_R) return if (slamReady) .slam else .wait;
    if (dist >= DRIVE_MIN and dist <= DRIVE_MAX and driveReady) return .drive;
    return .approach;
}

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "ogre");
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, xf: *const [N]rl.Matrix) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, xf[i]);
    }
};

pub const Ogre = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    parry: foe.Parry = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    slamCd: f32 = 0,
    swipeCd: f32 = 0,
    driveCd: f32 = 0,
    windHold: f32 = 0,
    elapsed: f32 = 0,
    slammed: bool = false,
    blowKind: enum { slam, swipe, backswipe, drive } = .slam,
    homing: bool = false,

    // posture channels (degrees) resolved each frame by the state, read by pose().
    clubShoulder: f32 = CARRY_SH,
    clubElbow: f32 = CARRY_EL,
    offShoulder: f32 = OFF_SH,
    offElbow: f32 = OFF_EL,
    bodyLean: f32 = HUNCH,
    headPitch: f32 = HEAD_DROOP,
    twist: f32 = 0,
    clubTilt: f32 = CARRY_TILT,
    clubAbd: f32 = CLUB_ABD,
    clubSweep: f32 = 0,
    // The waist twist alone rotates the arc but cannot carry an arm held out right across his centre line. Without the shoulder swing the "side swipe" only scythes his right flank (measured: −104..−23).
    jawOpen: f32 = JAW_REST,
    girdle: f32 = 0,
    legBrace: f32 = 0,
    jolt: f32 = 0,
    judder: f32 = 0,
    headYaw: f32 = 0,
    headLook: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    heroLatch: bool = false,
    parried: bool = false,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    wade: foe.Wade = .{},
    /// The DECISION stream — every hold, chain roll and cooldown jitter comes off this, its own stream so a dust budget change cannot re-deal the fight (fxRng's law). Seeded, so --shot stays deterministic.
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Ogre {
        var o = Ogre{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        o.rest = REST;
        o.fxRng = foe.fxStream(seed, 88883.0, 7);
        o.aiRng = foe.fxStream(seed, 51707.0, 5);
        o.pose();
        return o;
    }

    // …and all measured from `pos.y`, THE GROUND UNDER HIM.
    pub fn centerWorld(self: *const Ogre) rl.Vector3 {
        return foe.bodyPoint(self.pos, 0.60 * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Ogre) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ogre) f32 {
        return BODY_R * self.scale;
    }
    /// HIS MARK RIDES THE CHEST, NOT THE SKULL — the one creature where that is the right part. His crown is 4.4 m up, and a reticle bolted to it would sit at the top of the frame through every exchange. It still HINGES: he folds at the waist through the slam.
    pub fn lockPoint(self: *const Ogre) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], LOCK_AT);
    }
    pub fn topWorld(self: *const Ogre) rl.Vector3 {
        return foe.bodyPoint(self.pos, 1.02 * H, self.scale, 0);
    }
    pub fn headWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.86 * H * self.scale, self.pos.z);
    }
    pub fn clubLowWorld(self: *const Ogre) rl.Vector3 {
        return rl.math.vector3Transform(CLUB_LOW, self.xf[CLUB]);
    }
    pub fn alive(self: *const Ogre) bool {
        return !self.gone;
    }
    pub fn staggered(self: *const Ogre) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn dying(self: *const Ogre) bool {
        return self.state == .dead;
    }
    pub fn flashFrac(self: *const Ogre) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn airborne(self: *const Ogre) bool {
        _ = self;
        return false;
    }

    fn fdir(self: *const Ogre) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Ogre, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    pub fn navWant(self: *const Ogre, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .approach) return null;
        return if (self.homing) self.home else hero;
    }

    pub fn update(self: *Ogre, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            self.updateFx(dt);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.slamCd = mathx.maxF(0, self.slamCd - dt);
        self.swipeCd = mathx.maxF(0, self.swipeCd - dt);
        self.driveCd = mathx.maxF(0, self.driveCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        self.t += dt;
        self.updateFx(dt);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;

        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const bearing = self.bearingTo(hero);
        self.trackHead(hero, d, dt);
        self.takeParry();
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                if (self.t >= 0.2) self.decide(d, bearing);
            },
            .approach => {
                const tgt = if (self.homing) self.home else hero;
                // …AND HE TURNS ROUND WHAT IS IN THE WAY (`foe.Nav`). It goes through the FACING and not the step, because he walks where he is looking and HE NEVER STRAFES: bent at the step he would sidle round a wall still square to the hero.
                self.faceToward(self.nav.aim(self.pos, tgt), dt);
                const f = self.fdir();
                const moved = WALK_SPEED * dt;
                mathx.stepXZ(&self.pos, f, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(f);
                self.setCarry(dt);
                if (self.homing) {
                    if (d <= AGGRO_R) {
                        self.homing = false;
                        self.decide(d, bearing);
                    } else if (mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) self.enterIdle();
                } else if (d <= SWIPE_R or d > AGGRO_R or
                    (d >= DRIVE_MIN and d <= DRIVE_MAX and self.driveCd <= 0 and foe.canLeap(&self.root)))
                    self.decide(d, bearing);
            },
            .windup => {
                self.faceToward(hero, dt * 0.4);
                const k = mathx.smoothstep(0, WINDUP_DUR * 0.82, self.t);
                self.setWindup(k);
                self.emitStrain(dt, k);
                if (self.t >= WINDUP_DUR + self.windHold) self.enter(.slam);
            },
            .slam => {
                const k = foe.swingCurve(self.t / SLAM_DUR);
                self.setSlam(k);
                if (self.t >= SLAM_DUR * SLAM_IMPACT_K) {
                    self.tryImpact(hero, SLAM_HIT);
                    if (!self.slammed) {
                        self.slammed = true;
                        self.judder = 1.0;
                        self.dustBurst(self.impactWorld(), 36, 3.8, 0.38);
                        sfx.world(.ogre_slam, self.impactWorld());
                    }
                }
                if (self.t >= SLAM_DUR) {
                    self.slamCd = SLAM_CD * self.aiRng.range(0.85, 1.45);
                    self.enter(.recover);
                }
            },
            .swipewind => {
                self.faceToward(hero, dt * 1.4);
                self.setSwipeWind(mathx.smoothstep(0, SWIPE_WIND_DUR * 0.9, self.t));
                if (self.t >= SWIPE_WIND_DUR) self.enter(.swipe);
            },
            .swipe => {
                foe.faceToward(self.pos, &self.facing, hero, SWIPE_TURN, dt);
                const k = foe.swingCurve(self.t / SWIPE_DUR);
                self.setSwipe(k);
                if (self.t >= SWIPE_DUR * SWIPE_IMPACT_K) {
                    self.trySwipe(hero, SWIPE_HIT);
                    if (!self.slammed) {
                        self.slammed = true;
                        const low = self.clubLowWorld();
                        self.dustBurst(v3(low.x, self.pos.y + 0.05, low.z), 12, 2.2, 0.20);
                    }
                }
                if (self.t >= SWIPE_DUR) {
                    // THE TAIL IS NEVER SAFE, ONLY USUALLY SAFE: still in the band, the club sometimes comes straight back (`.backwind`). Rolled HERE, at the overswing, so the choice is made where the club is — and only where the return could actually land.
                    if (d >= self.swipeInner() and d <= self.swipeReach() and self.aiRng.float() < BACK_CHANCE) {
                        self.enter(.backwind);
                    } else {
                        self.swipeCd = SWIPE_CD * self.aiRng.range(0.8, 1.5);
                        self.enter(.recover);
                    }
                }
            },
            .backwind => {
                foe.faceToward(self.pos, &self.facing, hero, SWIPE_TURN * 0.6, dt);
                self.setBackwind(mathx.smoothstep(0, 1, self.t / BACK_WIND_DUR));
                if (self.t >= BACK_WIND_DUR) self.enter(.backswipe);
            },
            .backswipe => {
                foe.faceToward(self.pos, &self.facing, hero, SWIPE_TURN, dt);
                const k = foe.swingCurve(self.t / BACK_DUR);
                self.setBackswipe(k);
                if (self.t >= BACK_DUR * BACK_IMPACT_K) {
                    self.trySweep(hero, SWIPE_HIT, BACK_ARC_MID, BACK_ARC);
                    if (!self.slammed) {
                        self.slammed = true;
                        const low = self.clubLowWorld();
                        self.dustBurst(v3(low.x, self.pos.y + 0.05, low.z), 12, 2.2, 0.20);
                    }
                }
                if (self.t >= BACK_DUR) {
                    self.swipeCd = SWIPE_CD * self.aiRng.range(1.0, 1.7);
                    self.enter(.recover);
                }
            },
            .drivewind => {
                self.faceToward(hero, dt * 1.6);
                self.setDrivewind(mathx.smoothstep(0, DRIVE_WIND_DUR * 0.9, self.t));
                self.emitStrain(dt, mathx.clampF(self.t / DRIVE_WIND_DUR, 0, 1));
                if (self.t >= DRIVE_WIND_DUR) self.enter(.drive);
            },
            .drive => {
                self.faceToward(hero, dt * 0.5);
                const surge = DRIVE_DUR * DRIVE_IMPACT_K;
                self.setDrive(foe.swingCurve(self.t / DRIVE_DUR));
                if (self.t < surge) {
                    const f = self.fdir();
                    const moved = DRIVE_SPEED * dt;
                    mathx.stepXZ(&self.pos, f, moved, bounds);
                    movedDist = moved;
                    moveYaw = mathx.headingXZ(f);
                }
                if (self.t >= surge) {
                    self.tryImpact(hero, DRIVE_HIT);
                    if (!self.slammed) {
                        self.slammed = true;
                        self.judder = 1.0;
                        self.dustBurst(self.impactWorld(), 42, 4.2, 0.42);
                        sfx.world(.ogre_slam, self.impactWorld());
                    }
                }
                if (self.t >= DRIVE_DUR) {
                    self.driveCd = DRIVE_CD * self.aiRng.range(0.75, 1.6);
                    self.enter(.recover);
                }
            },
            .recover => {
                const dur: f32 = switch (self.blowKind) {
                    .slam => RECOVER_DUR,
                    .drive => DRIVE_REC_DUR,
                    .swipe, .backswipe => SWIPE_REC_DUR,
                };
                self.setRecover(mathx.clampF(self.t / dur, 0, 1));
                if (self.t >= dur) self.enterIdle();
            },
            .stunlight => {
                self.easeChannelsNeutral(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle();
            },
            .stunheavy => {
                self.easeChannelsNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle();
            },
            .dead => {
                self.easeChannelsNeutral(dt);
                // THE BODY ARRIVING IS AN EVENT (the knight's law) — four metres of flesh used to reach the ground in silence with nothing moving. Dust the length of the fallen trunk, once.
                const land = DEATH_DUR * DEATH_LAND;
                if (self.t >= land and self.t - dt < land) {
                    const f = self.fdir();
                    self.dustBurst(v3(self.pos.x + f.x * 0.5 * self.scale, self.pos.y, self.pos.z + f.z * 0.5 * self.scale), 10, 2.6, 0.30);
                    self.dustBurst(v3(self.pos.x + f.x * 1.1 * self.scale, self.pos.y, self.pos.z + f.z * 1.1 * self.scale), 8, 2.2, 0.26);
                    self.judder = 1.0;
                    sfx.world(.ogre_slam, self.pos);
                }
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }
        self.jolt = mathx.maxF(0, self.jolt - dt * 7.0);
        self.judder = mathx.maxF(0, self.judder - dt * 3.2); // the club-bounce rings ~0.3 s

        const gaitSpeed: f32 = if (movedDist <= 0) 0 else if (self.state == .drive) DRIVE_SPEED else WALK_SPEED;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.footfalls();
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn enter(self: *Ogre, s: State) void {
        self.state = s;
        self.t = 0;
        switch (s) {
            .slam, .swipe, .backswipe, .drive => {
                self.slammed = false;
                self.heroLatch = false;
                // Named through, not `else => .drive`: a fifth strike added to the prong list above wore the
                // DRIVE's blow silently, and a wrong-blow bug does not fail a test.
                self.blowKind = switch (s) {
                    .slam => .slam,
                    .swipe => .swipe,
                    .backswipe => .backswipe,
                    .drive => .drive,
                    else => unreachable,
                };
            },
            else => {},
        }
        if (s == .windup) {
            self.windHold = if (self.aiRng.float() < 0.4) 0 else self.aiRng.range(0.12, 0.55);
            sfx.world(.ogre_roar, self.pos);
        }
        if (s == .drivewind) sfx.world(.ogre_roar, self.pos);
        if (s == .swipewind or s == .backwind) sfx.world(.ogre_swipe, self.pos);
        switch (s) {
            .slam, .swipe, .backswipe, .drive => {
                sfx.world(.ogre_heave, self.pos);
                self.plantBurst();
            },
            else => {},
        }
    }
    fn enterIdle(self: *Ogre) void {
        self.state = .idle;
        self.t = 0;
        self.homing = false;
    }
    fn enterStun(self: *Ogre, s: State) void {
        self.state = s;
        self.t = 0;
        self.slammed = false;
        self.homing = false;
    }
    fn enterDeath(self: *Ogre) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
        self.homing = false;
    }

    // The hero's bearing off his facing, in degrees (0 = dead ahead, ±180 = behind) — what decides whether he can drop the club on you or has to SWEEP round to reach you.
    fn bearingTo(self: *const Ogre, hero: rl.Vector3) f32 {
        const d = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(d) < 1e-3) return 0;
        return mathx.degrees(mathx.wrapPi(mathx.headingXZ(d) - self.facing));
    }

    fn decide(self: *Ogre, dist: f32, bearingDeg: f32) void {
        const driveReady = self.driveCd <= 0 and foe.canLeap(&self.root);
        switch (classify(dist, bearingDeg, self.slamCd <= 0, self.swipeCd <= 0, driveReady, self.swipeInner())) {
            .slam => self.enter(.windup),
            .swipe => self.enter(.swipewind),
            .drive => self.enter(.drivewind),
            .approach => {
                self.homing = false;
                self.enter(.approach);
            },
            .wait => self.enterIdle(),
            .idle => {
                // ONE RADIUS DECIDES "AM I AT MY POST", and it is the LEASH's own (`foe.LEASH_HOME_R`), because that is where the tether stops caring. Setting off at 3 m and arriving at 2 m leaves him trudging a metre past the boundary that sent him.
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.enter(.approach);
                } else self.enterIdle();
            },
        }
    }

    pub fn tryHit(self: *Ogre, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 0.4, .heavy = 0.7 });
        self.bloodBurst(s.contact, s.dir, if (heavyBlow) BLOOD_HEAVY else BLOOD_LIGHT, if (heavyBlow) BLOOD_SPD_HEAVY else BLOOD_SPD_LIGHT);
        sfx.world(.ogre_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.bloodBurst(s.contact, s.dir, BLOOD_DEATH, BLOOD_SPD_DEATH);
                sfx.world(.ogre_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn slamReach(self: *const Ogre) f32 {
        return foe.hurtReach(SLAM_LEN, self.scale);
    }
    fn swipeReach(self: *const Ogre) f32 {
        return foe.hurtReach(SWIPE_OUTER, self.scale);
    }
    fn swipeInner(self: *const Ogre) f32 {
        return SWIPE_INNER * self.scale - HERO_REACH;
    }

    fn tryImpact(self: *Ogre, hero: rl.Vector3, h: combat.Hit) void {
        if (self.heroLatch) return;
        const to = v3(hero.x - self.pos.x, 0, hero.z - self.pos.z);
        const fwd = self.fdir();
        const axial = to.x * fwd.x + to.z * fwd.z;
        const lateral = @abs(to.x * fwd.z - to.z * fwd.x);
        if (axial < -0.2 or axial > self.slamReach()) return;
        if (lateral > foe.hurtReach(SLAM_HALF_W, self.scale)) return;
        self.heroHit = h;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    /// The swipe's hurt test, shared with the RETURN — each passes its own measured sector.
    fn trySweep(self: *Ogre, hero: rl.Vector3, h: combat.Hit, mid: f32, arc: f32) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d < self.swipeInner() or d > self.swipeReach()) return;
        const slack = combat.subtendedArc(HERO_REACH, mathx.maxF(SWIPE_SLACK_MIN_D, d));
        if (@abs(mathx.wrapDeg(self.bearingTo(hero) - mid)) > arc * 0.5 + slack) return;
        self.heroHit = h;
        self.heroLatch = true;
        self.leash.noteCombat();
    }
    fn trySwipe(self: *Ogre, hero: rl.Vector3, h: combat.Hit) void {
        self.trySweep(hero, h, SWIPE_ARC_MID, SWIPE_ARC);
    }

    fn slamMove(self: *const Ogre) bool {
        return self.state == .windup or self.state == .slam;
    }
    fn driveMove(self: *const Ogre) bool {
        return self.state == .drivewind or self.state == .drive;
    }

    fn toImpact(self: *const Ogre) ?f32 {
        return switch (self.state) {
            .windup => (WINDUP_DUR + self.windHold - self.t) + SLAM_DUR * SLAM_IMPACT_K,
            .slam => SLAM_DUR * SLAM_IMPACT_K - self.t,
            .swipewind => (SWIPE_WIND_DUR - self.t) + SWIPE_DUR * SWIPE_IMPACT_K,
            .swipe => SWIPE_DUR * SWIPE_IMPACT_K - self.t,
            .backwind => (BACK_WIND_DUR - self.t) + BACK_DUR * BACK_IMPACT_K,
            .backswipe => BACK_DUR * BACK_IMPACT_K - self.t,
            .drivewind => (DRIVE_WIND_DUR - self.t) + DRIVE_DUR * DRIVE_IMPACT_K,
            .drive => DRIVE_DUR * DRIVE_IMPACT_K - self.t,
            .idle, .approach, .recover, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Ogre) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        if (self.driveMove()) return self.slamReach() + DRIVE_SPEED * left;
        return if (self.slamMove()) self.slamReach() else self.swipeReach();
    }

    fn takeParry(self: *Ogre) void {
        const reach = self.parryable() orelse return;
        if (!self.parry.catches(self.pos, reach)) return;
        self.parried = true;
        self.flash = FLASH_DUR;
        self.judder = 1.0;
        self.leash.noteCombat();
        if (self.slamMove()) {
            self.slamCd = SLAM_CD;
        } else if (self.driveMove()) {
            self.driveCd = DRIVE_CD;
        } else {
            self.swipeCd = SWIPE_CD;
        }
        switch (self.state) {
            .windup => self.setSlam(0.30),
            .swipewind => self.setSwipe(0.35),
            .backwind => self.setBackswipe(0.35),
            .drivewind => self.setDrive(0.25),
            else => {},
        }
        const low = self.clubLowWorld();
        self.dustBurst(v3(low.x, self.pos.y + 0.05, low.z), 10, 1.8, 0.18);
        const back = mathx.dirXZ(self.parry.at, self.pos);
        var sp: i32 = 0;
        while (sp < 12) : (sp += 1) {
            const a = self.fxRng.angle();
            const fan = self.fxRng.range(0.5, 1.0);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = low,
                .v = v3(back.x * 3.4 * fan + mathx.cosf(a) * 1.5, self.fxRng.range(1.2, 3.2), back.z * 3.4 * fan + mathx.sinf(a) * 1.5),
                .life = self.fxRng.range(0.16, 0.30),
                .r0 = 0.05,
                .r1 = 0.01,
                .col = PARRY_SPARK,
                .col1 = PARRY_SPARK_COOL,
                .grav = 2.4,
                .stretch = 0.055,
                .bounce = 0.45,
                .add = true,
            });
        }
        sfx.world(.ogre_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    pub fn debugSlam(self: *Ogre) void {
        self.enter(.windup);
        self.windHold = 0;
    }
    pub fn debugSwipe(self: *Ogre) void {
        self.enter(.swipewind);
    }
    pub fn debugBackswipe(self: *Ogre) void {
        self.enter(.backwind);
    }
    pub fn debugDrive(self: *Ogre) void {
        self.enter(.drivewind);
    }
    pub fn stagger(self: *Ogre, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Ogre) void {
        self.enterDeath();
    }

    fn trackHead(self: *Ogre, hero: rl.Vector3, d: f32, dt: f32) void {
        if (self.staggered()) {
            self.headYaw = mathx.approach(self.headYaw, 0, dt * 120.0);
            self.headLook = mathx.approach(self.headLook, 0, dt * 60.0);
            return;
        }
        if (d > AGGRO_R) {
            self.headYaw = mathx.approach(self.headYaw, HEAD_SCAN * mathx.sinf(self.elapsed * 0.33 + self.seed * 7.0), dt * 30.0);
            self.headLook = mathx.approach(self.headLook, 0, dt * 30.0);
            return;
        }
        const bearing = mathx.degrees(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(self.pos, hero)) - self.facing));
        self.headYaw = mathx.approach(self.headYaw, mathx.clampF(bearing, -HEAD_YAW_MAX, HEAD_YAW_MAX), dt * HEAD_TRACK_RATE);
        const near = 1.0 - mathx.smoothstep(SLAM_R, AGGRO_R * 0.6, d);
        self.headLook = mathx.approach(self.headLook, HEAD_LOOK_DOWN * near, dt * 40.0);
    }

    fn setCarry(self: *Ogre, dt: f32) void {
        const e = dt * 6.0;
        const breathe = mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28);
        const rock = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28);
        const sigh = mathx.smoothstep(0.80, 1.0, mathx.sinf(self.elapsed * 0.42 + self.seed * 11.0)); // a slow swell every ~15 s
        const stalk = self.moving;
        self.clubShoulder = mathx.approach(self.clubShoulder, CARRY_SH + 3.0 * rock + 2.0 * sigh, e);
        self.clubElbow = mathx.approach(self.clubElbow, CARRY_EL + 2.5 * breathe, e);
        self.offShoulder = mathx.approach(self.offShoulder, OFF_SH - 2.5 * rock, e);
        self.offElbow = mathx.approach(self.offElbow, OFF_EL, e);
        self.bodyLean = mathx.approach(self.bodyLean, HUNCH + 1.5 * breathe + 4.0 * sigh + 4.0 * stalk, e);
        self.headPitch = mathx.approach(self.headPitch, HEAD_DROOP + 2.0 * breathe + 2.5 * rock + 5.0 * sigh - 12.0 * stalk, e);
        self.twist = mathx.approach(self.twist, 0, e * 8.0);
        self.clubTilt = mathx.approach(self.clubTilt, CARRY_TILT - (self.bodyLean - HUNCH) + 3.0 * rock, e * 8.0);
        self.clubAbd = mathx.approach(self.clubAbd, CLUB_ABD + 2.0 * breathe, e);
        self.clubSweep = mathx.approach(self.clubSweep, 0, e);
        self.legBrace = mathx.approach(self.legBrace, 0, e);
        self.jawOpen = mathx.approach(self.jawOpen, JAW_REST + JAW_BREATHE * breathe + 6.0 * sigh + JAW_STALK * stalk, e * 0.8);
        self.girdle = mathx.approach(self.girdle, GIRDLE_HEAVE * mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28 - 0.7) - 2.0 * sigh, e);
    }
    /// `mathx.approach` steps in the units of what it moves, so ONE rate cannot serve both an angle and a fraction: at the 4 the leg brace wants, the club arm crawled home from OVER_SH at four degrees a second — forty seconds for 163. At `STUN_EASE_DEG` it is home in ~0.6 s.
    fn easeChannelsNeutral(self: *Ogre, dt: f32) void {
        const d = dt * STUN_EASE_DEG;
        self.clubShoulder = mathx.approach(self.clubShoulder, CARRY_SH, d);
        self.clubElbow = mathx.approach(self.clubElbow, CARRY_EL, d);
        self.offShoulder = mathx.approach(self.offShoulder, OFF_SH, d);
        self.offElbow = mathx.approach(self.offElbow, OFF_EL, d);
        self.bodyLean = mathx.approach(self.bodyLean, HUNCH, d);
        self.headPitch = mathx.approach(self.headPitch, HEAD_DROOP, d);
        self.twist = mathx.approach(self.twist, 0, d * 2.0);
        self.clubTilt = mathx.approach(self.clubTilt, CARRY_TILT, d * 2.0);
        self.clubAbd = mathx.approach(self.clubAbd, CLUB_ABD, d);
        self.clubSweep = mathx.approach(self.clubSweep, 0, d);
        self.legBrace = mathx.approach(self.legBrace, 0, dt * STUN_EASE_FRAC); // 0..1, not degrees
        self.jawOpen = mathx.approach(self.jawOpen, JAW_REST, d * 0.25);
        self.girdle = mathx.approach(self.girdle, 0, d);
    }
    fn setWindup(self: *Ogre, k: f32) void {
        const kBody = mathx.smoothstep(0, 0.7, k);
        const kArm = k * @sqrt(k);
        const shiver = mathx.sinf(self.t * 36.0) * 1.8 * mathx.smoothstep(0.75, 1.0, k);
        self.clubShoulder = lerpF(CARRY_SH, OVER_SH, kArm) + shiver;
        self.clubElbow = lerpF(CARRY_EL, WIND_EL, kArm);
        self.offShoulder = lerpF(OFF_SH, -74.0, kBody);
        self.offElbow = lerpF(OFF_EL, -44.0, kBody);
        self.bodyLean = lerpF(HUNCH, -24.0, kBody);
        self.headPitch = lerpF(HEAD_DROOP, -20.0, kBody);
        self.twist = lerpF(0, -26.0, k);
        self.clubTilt = lerpF(CARRY_TILT, WIND_TILT, kArm) + shiver * 0.6;
        self.clubAbd = lerpF(CLUB_ABD, WIND_ABD, kArm);
        self.clubSweep = lerpF(self.clubSweep, 0, kArm);
        self.legBrace = lerpF(0, 0.55, kBody);
        self.jawOpen = lerpF(JAW_REST, JAW_ROAR, mathx.smoothstep(0, 0.45, k)) + shiver * 0.8;
        self.girdle = lerpF(0, GIRDLE_WIND, kArm) + shiver * 0.5;
    }
    fn setSlam(self: *Ogre, k: f32) void {
        const kArm = 1.0 - (1.0 - k) * (1.0 - k);
        self.clubShoulder = lerpF(OVER_SH, SLAM_SH + 6.0, kArm);
        self.clubElbow = lerpF(WIND_EL, SLAM_EL, kArm);
        self.offShoulder = lerpF(-74.0, 8.0, kArm);
        self.offElbow = lerpF(-44.0, -22.0, kArm);
        // …and the trunk drives DEEP: with the legs planted and the club shortened, the waist fold is the only thing that can carry the head to the earth (a straight arm leaves it 0.46 short, measured).
        self.bodyLean = lerpF(-24.0, 62.0, k);
        self.headPitch = lerpF(-20.0, 24.0, kArm);
        self.twist = lerpF(-26.0, 12.0, kArm);
        self.clubTilt = lerpF(WIND_TILT, SLAM_TILT, kArm);
        self.clubAbd = lerpF(WIND_ABD, SLAM_ABD, kArm);
        self.clubSweep = lerpF(self.clubSweep, 0, kArm);
        self.legBrace = lerpF(0.55, 0.95, k);
        self.jawOpen = lerpF(JAW_ROAR, JAW_GRIT, mathx.smoothstep(0.15, 0.8, k));
        self.girdle = lerpF(GIRDLE_WIND, -6.0, kArm);
    }
    fn setSwipeWind(self: *Ogre, k: f32) void {
        const kArm = mathx.smoothstep(0, 1, k);
        self.twist = lerpF(0, -46.0, k);
        self.clubShoulder = lerpF(CARRY_SH, -26.0, kArm);
        self.clubElbow = lerpF(CARRY_EL, -38.0, kArm);
        self.clubAbd = lerpF(CLUB_ABD, 58.0, kArm);
        self.clubSweep = lerpF(0, -20.0, kArm);
        self.clubTilt = lerpF(CARRY_TILT, 34.0, kArm);
        self.offShoulder = lerpF(OFF_SH, -28.0, kArm);
        self.offElbow = lerpF(OFF_EL, -52.0, kArm);
        self.bodyLean = lerpF(HUNCH, HUNCH - 5.0, k);
        self.headPitch = lerpF(HEAD_DROOP, -6.0, k);
        self.legBrace = lerpF(0, 0.30, k);
        self.jawOpen = lerpF(JAW_REST, JAW_ROAR * 0.55, k);
        self.girdle = lerpF(0, 9.0, kArm);
    }
    fn setSwipe(self: *Ogre, k: f32) void {
        const kW = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k);
        self.twist = lerpF(-46.0, 52.0, kW);
        self.clubShoulder = lerpF(-26.0, -6.0, kW);
        self.clubElbow = lerpF(-38.0, -8.0, kW);
        self.clubAbd = lerpF(58.0, 66.0, kW);
        self.clubSweep = lerpF(-20.0, 52.0, kW);
        self.clubTilt = lerpF(34.0, -18.0, kW);
        self.offShoulder = lerpF(-28.0, 22.0, kW);
        self.offElbow = lerpF(-52.0, -20.0, kW);
        self.bodyLean = lerpF(HUNCH - 5.0, HUNCH + 8.0, k);
        self.headPitch = lerpF(-6.0, 12.0, kW);
        self.legBrace = lerpF(0.30, 0.42, k);
        self.jawOpen = lerpF(JAW_ROAR * 0.55, JAW_GRIT, mathx.smoothstep(0.1, 0.7, k));
        self.girdle = lerpF(9.0, -2.0, kW);
    }
    // FROM THE OVERSWING, NOT THE CARRY: the swipe ends slung across him (twist 52, sweep 52, kW = 1), so these lerps start there and the chain is continuous. The re-cock is a DRAG, not a lift — re-shouldered, the whole return passed over the hero's head and the sector could not bill it.
    fn setBackwind(self: *Ogre, k: f32) void {
        self.twist = lerpF(52.0, 52.0, k);
        self.clubShoulder = lerpF(-6.0, -6.0, k);
        self.clubElbow = lerpF(-8.0, -8.0, k);
        self.clubAbd = lerpF(66.0, 66.0, k);
        self.clubSweep = lerpF(52.0, 56.0, k);
        self.clubTilt = lerpF(-18.0, -18.0, k);
        self.offShoulder = lerpF(22.0, -18.0, k);
        self.offElbow = lerpF(-20.0, -44.0, k);
        self.bodyLean = lerpF(HUNCH + 8.0, HUNCH + 10.0, k);
        self.headPitch = lerpF(12.0, -2.0, k);
        self.legBrace = lerpF(0.42, 0.38, k);
        self.jawOpen = lerpF(JAW_GRIT, JAW_ROAR * 0.5, k);
        self.girdle = lerpF(-2.0, 7.0, k);
    }
    fn setBackswipe(self: *Ogre, k: f32) void {
        const kW = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k);
        self.twist = lerpF(52.0, -48.0, kW);
        self.clubShoulder = lerpF(-6.0, -8.0, kW);
        self.clubElbow = lerpF(-8.0, -12.0, kW);
        self.clubAbd = lerpF(66.0, 60.0, kW);
        self.clubSweep = lerpF(56.0, -24.0, kW);
        self.clubTilt = lerpF(-18.0, 26.0, kW * kW);
        self.offShoulder = lerpF(-18.0, 14.0, kW);
        self.offElbow = lerpF(-44.0, -24.0, kW);
        self.bodyLean = lerpF(HUNCH + 10.0, HUNCH + 2.0, k);
        self.headPitch = lerpF(-2.0, 8.0, kW);
        self.legBrace = lerpF(0.38, 0.44, k);
        self.jawOpen = lerpF(JAW_ROAR * 0.5, JAW_GRIT, mathx.smoothstep(0.1, 0.7, k));
        self.girdle = lerpF(7.0, -3.0, kW);
    }
    fn setDrivewind(self: *Ogre, k: f32) void {
        const kArm = k * @sqrt(k);
        const shiver = mathx.sinf(self.t * 34.0) * 1.6 * mathx.smoothstep(0.7, 1.0, k);
        self.clubShoulder = lerpF(CARRY_SH, -118.0, kArm) + shiver;
        self.clubElbow = lerpF(CARRY_EL, -66.0, kArm);
        self.offShoulder = lerpF(OFF_SH, -52.0, k);
        self.offElbow = lerpF(OFF_EL, -48.0, k);
        self.bodyLean = lerpF(HUNCH, 30.0, k);
        self.headPitch = lerpF(HEAD_DROOP, -26.0, k);
        self.twist = lerpF(0, -18.0, k);
        self.clubTilt = lerpF(CARRY_TILT, WIND_TILT, kArm) + shiver * 0.5;
        self.clubAbd = lerpF(CLUB_ABD, WIND_ABD, kArm);
        self.clubSweep = lerpF(self.clubSweep, 0, kArm);
        self.legBrace = lerpF(0, 0.8, k);
        self.jawOpen = lerpF(JAW_REST, JAW_ROAR, mathx.smoothstep(0, 0.5, k)) + shiver * 0.7;
        self.girdle = lerpF(0, GIRDLE_WIND * 0.7, kArm);
    }
    fn setDrive(self: *Ogre, k: f32) void {
        const kArm = 1.0 - (1.0 - k) * (1.0 - k);
        self.clubShoulder = lerpF(-118.0, SLAM_SH + 4.0, kArm);
        self.clubElbow = lerpF(-66.0, SLAM_EL, kArm);
        self.offShoulder = lerpF(-52.0, 12.0, kArm);
        self.offElbow = lerpF(-48.0, -20.0, kArm);
        self.bodyLean = lerpF(30.0, 60.0, k);
        self.headPitch = lerpF(-26.0, 20.0, kArm);
        self.twist = lerpF(-18.0, 10.0, kArm);
        self.clubTilt = lerpF(WIND_TILT, SLAM_TILT, kArm);
        self.clubAbd = lerpF(WIND_ABD, SLAM_ABD, kArm);
        self.clubSweep = 0;
        self.legBrace = 0;
        self.jawOpen = lerpF(JAW_ROAR, JAW_GRIT, mathx.smoothstep(0.3, 0.9, k));
        self.girdle = lerpF(GIRDLE_WIND * 0.7, -6.0, kArm);
    }
    fn setRecover(self: *Ogre, u: f32) void {
        switch (self.blowKind) {
            .swipe => return self.setSwipeRecover(u),
            .backswipe => return self.setBackswipeRecover(u),
            .slam, .drive => {},
        }
        const spent = 1.0 - mathx.smoothstep(0.7, 1.0, u);
        const heave = 3.0 * mathx.sinf(self.elapsed * 7.0) * spent;
        const ring = self.judder * mathx.sinf(self.t * 44.0);
        self.clubShoulder = lerpF(CARRY_SH, SLAM_SH, spent) + heave * 0.4 + 6.5 * ring;
        self.clubElbow = lerpF(CARRY_EL, SLAM_EL, spent) + 3.0 * ring;
        self.offShoulder = lerpF(OFF_SH, -8.0, spent);
        self.offElbow = lerpF(OFF_EL, -34.0, spent);
        self.bodyLean = lerpF(HUNCH, 58.0, spent) + 2.2 * ring;
        self.headPitch = lerpF(HEAD_DROOP, 34.0 + heave, spent);
        self.twist = lerpF(0, 6.0, spent);
        self.clubTilt = lerpF(CARRY_TILT, SLAM_TILT, spent) + 4.0 * ring;
        self.clubAbd = lerpF(CLUB_ABD, SLAM_ABD, spent);
        self.clubSweep = 0;
        self.legBrace = lerpF(0, 1.0, spent);
        self.jawOpen = lerpF(JAW_REST, JAW_PANT + 3.0 * heave, spent) + 2.0 * ring;
        self.girdle = lerpF(0, GIRDLE_SPENT, spent) + heave * 0.5;
    }

    fn setSwipeRecover(self: *Ogre, u: f32) void {
        const over = 1.0 - mathx.smoothstep(0.35, 1.0, u);
        const settle = mathx.sinf(u * std.math.pi * 2.0) * (1.0 - u) * 2.5;
        self.twist = lerpF(0, 52.0, over) + settle;
        self.clubShoulder = lerpF(CARRY_SH, -4.0, over);
        self.clubElbow = lerpF(CARRY_EL, -30.0, over);
        self.clubAbd = lerpF(CLUB_ABD, 40.0, over);
        self.clubSweep = lerpF(0, 52.0, over);
        self.clubTilt = lerpF(CARRY_TILT, -14.0, over);
        self.offShoulder = lerpF(OFF_SH, 20.0, over);
        self.offElbow = lerpF(OFF_EL, -22.0, over);
        self.bodyLean = lerpF(HUNCH, HUNCH + 8.0, over) + settle * 0.4;
        self.headPitch = lerpF(HEAD_DROOP, 10.0, over);
        self.legBrace = lerpF(0, 0.42, over);
        self.jawOpen = lerpF(JAW_REST, JAW_PANT * 0.6, over);
        self.girdle = lerpF(0, -4.0, over);
    }

    fn setBackswipeRecover(self: *Ogre, u: f32) void {
        const over = 1.0 - mathx.smoothstep(0.35, 1.0, u);
        const settle = mathx.sinf(u * std.math.pi * 2.0) * (1.0 - u) * 2.5;
        self.twist = lerpF(0, -44.0, over) - settle;
        self.clubShoulder = lerpF(CARRY_SH, -8.0, over);
        self.clubElbow = lerpF(CARRY_EL, -26.0, over);
        self.clubAbd = lerpF(CLUB_ABD, 46.0, over);
        self.clubSweep = lerpF(0, -14.0, over);
        self.clubTilt = lerpF(CARRY_TILT, -12.0, over);
        self.offShoulder = lerpF(OFF_SH, 16.0, over);
        self.offElbow = lerpF(OFF_EL, -24.0, over);
        self.bodyLean = lerpF(HUNCH, HUNCH + 7.0, over) + settle * 0.4;
        self.headPitch = lerpF(HEAD_DROOP, 9.0, over);
        self.legBrace = lerpF(0, 0.40, over);
        self.jawOpen = lerpF(JAW_REST, JAW_PANT * 0.55, over);
        self.girdle = lerpF(0, -4.0, over);
    }

    fn stunAmount(self: *const Ogre) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn pose(self: *Ogre) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(0.95, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const du = if (dead) mathx.clampF(self.t / DEATH_DUR, 0, 1) else 0;
        const dk1 = mathx.smoothstep(0, 0.32, du);
        // HE FALLS, HE IS NOT LOWERED: a mass on a hinge ACCELERATES the whole way down, so the topple is quadratic to `DEATH_LAND` — a smoothstep is slowest at both ends, which is a body on a wire.
        const fall = mathx.clampF((du - 0.22) / (DEATH_LAND - 0.22), 0, 1);
        const dk2 = fall * fall;
        const settle = mathx.pulse(du, DEATH_LAND, 0.72, 0.72, 0.88);
        const stun = self.stunAmount();
        const light = self.state == .stunlight;
        const heavy = self.state == .stunheavy;
        const lstun: f32 = if (light) stun else 0;
        const hstun: f32 = if (heavy) stun else 0;

        const m = self.moving * (1.0 - dk1);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const catchDip = -0.020 * H * self.jolt * m;
        const braceSink = -BRACE_SINK * self.legBrace;
        const sway = A_SWAY * mathx.sinf(twoPi * self.phase) * m +
            A_SWAY * self.latB * mathx.cosf(twoPi * self.phase) * m;

        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk1);
        const wshift = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28);
        const idleBob = A_BREATHE * mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 3.0) * idleAmt;
        const idleSway = A_IDLE_SWAY * wshift * idleAmt;

        var wx: [N]rl.Matrix = undefined;
        const bodyPitch = self.bodyLean * (1.0 - dk2) - 40.0 * lstun + 34.0 * hstun;
        const leanX = PELVIS_SHARE * bodyPitch + 2.2 * self.jolt * m + 84.0 * dk2 + 5.0 * settle;
        const waist = (1.0 - PELVIS_SHARE) * bodyPitch;
        const lumber = A_LUMBER * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase + 0.5) * m;
        const rollZ = 16.0 * dk2 + 9.0 * hstun + IDLE_ROLL * wshift * idleAmt + lumber + 1.5 * self.judder * mathx.sinf(self.t * 44.0);
        const drop = -0.24 * H * hstun;
        const collapse = lerpF(hipY, 0.32 * H, dk1);
        const pelvY = if (dead) collapse else hipY + bob + catchDip + idleBob + braceSink + drop;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(rollZ), rx(leanX), ry(prot)),
            mul(tr((sway + idleSway) * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        if (!dead) {
            if (self.moving > 0.25) {
                heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, 0, 1.0, HIPL, KNEEL, solePatches[0]);
                heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, 0, -1.0, HIPR, KNEER, solePatches[1]);
            } else {
                const leftFree = mathx.clampF(-wshift, 0, 1) * idleAmt;
                const rightFree = mathx.clampF(wshift, 0, 1) * idleAmt;
                self.legPose(&wx, 1.0, leftFree, self.legBrace, HIPL, KNEEL, ANKL);
                self.legPose(&wx, -1.0, rightFree, self.legBrace, HIPR, KNEER, ANKR);
            }
        }
        self.poseUpper(&wx, dk1, dk2, lstun, hstun, dead, lumber, prot, waist);
        const curl = mathx.maxF(dk1, 0.6 * hstun);
        self.toePose(&wx, self.phase, m, curl, TOEL);
        self.toePose(&wx, self.phase + 0.5, m, curl, TOER);
        self.xf = wx;
    }

    fn toePose(self: *const Ogre, wx: *[N]rl.Matrix, ph: f32, m: f32, curl: f32, toe: usize) void {
        const p = ph - @floor(ph);
        const roll = (TOE_PUSH * stridePulse(p, 0.28, 0.62) - TOE_LIFT * stridePulse(p, 0.62, 1.0)) * m;
        setLocal(wx, toe, self.rest, rx(roll + TOE_GRIP * self.legBrace + TOE_CURL * curl + 2.0 * self.jolt * m));
    }

    fn legPose(self: *const Ogre, wx: *[N]rl.Matrix, side: f32, free: f32, brace: f32, hip: usize, knee: usize, ank: usize) void {
        const hipFlex = BRACE_HIP * brace + 5.0 * free;
        const kneeFlex = IDLE_KNEE + BRACE_KNEE * brace + 18.0 * free;
        const splay = STANCE_WIDEN * brace;
        setLocal(wx, hip, self.rest, mul(rx(-hipFlex), rz(-side * HIP_ADDUCT + side * splay)));
        setLocal(wx, knee, self.rest, rx(kneeFlex));
        const ankFlex = lerpF(hipFlex * 0.5, kneeFlex - hipFlex, brace) - 8.0 * free;
        setLocal(wx, ank, self.rest, mul(rx(ankFlex), ry(side * FOOT_TOEOUT)));
    }

    fn poseUpper(self: *Ogre, wx: *[N]rl.Matrix, dk1: f32, dk2: f32, lstun: f32, hstun: f32, dead: bool, lumber: f32, prot: f32, waist: f32) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk1);
        const armPh = std.math.tau * self.phase;
        const hung: f32 = switch (self.state) {
            .windup, .slam, .swipewind, .swipe, .backwind, .backswipe, .drivewind, .drive, .recover => 0,
            else => 1,
        };
        const nod = TRUNK_NOD * (0.5 - 0.5 * mathx.cosf(2.0 * armPh)) * m + 1.6 * self.jolt * m;
        const spineFlex = 6.0 + 26.0 * dk1 + 12.0 * hstun - 14.0 * lstun;
        setLocal(wx, SPINE, rest, mul3(rx(spineFlex * 0.40 + waist * 0.46 + nod * 0.45), ry(self.twist * 0.4 - 0.45 * prot), rz(-0.30 * lumber)));
        setLocal(wx, CHEST, rest, mul3(rx(spineFlex * 0.32 + waist * 0.34 + nod * 0.55), ry(self.twist * 0.6 - 0.75 * prot), rz(-0.45 * lumber)));
        const humpBreathe = mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28) * (1.0 - m);
        setLocal(wx, HUMP, rest, mul3(
            rx(spineFlex * 0.26 + waist * 0.20 + nod * 0.30 + 7.0 * hstun - 9.0 * lstun + 5.0 * dk2 + 1.3 * humpBreathe),
            ry(self.twist * 0.2 - 0.25 * prot),
            rz(-0.22 * lumber),
        ));
        const level = 0.6 * hung * mathx.maxF(0, waist - (1.0 - PELVIS_SHARE) * HUNCH);
        setLocal(wx, NECK, rest, mul3(rx(self.headPitch * 0.35 + self.headLook * 0.3 + 8.0 * dk1 - 0.55 * nod - level * 0.45), ry(0.55 * prot + 0.30 * self.headYaw), rz(-lumber * 0.5)));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.6 + self.headLook * 0.7 + 14.0 * dk2 + 16.0 * hstun - 26.0 * lstun - 0.45 * nod - level * 0.55),
            ry(0.70 * self.headYaw + 0.65 * prot), // the crane is SHARED with the neck above (0.30 there)
            rz(-lumber * 0.35 + 18.0 * dk2),
        ));
        const jaw = self.jawOpen + JAW_FLINCH * lstun + 16.0 * hstun + JAW_DEATH * mathx.maxF(dk1, dk2) +
            JAW_JOSTLE * (0.8 * self.jolt * m + 0.6 * self.judder * mathx.sinf(self.t * 31.0));
        setLocal(wx, JAW, rest, rx(mathx.maxF(0, jaw)));

        const buckle = mathx.maxF(dk1, 0.7 * hstun);
        if (dead or hstun > 0.05) {
            setLocal(wx, HIPL, rest, mul(rx(-58.0 * buckle), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(6.0 + 104.0 * buckle));
            setLocal(wx, ANKL, rest, ry(6.0));
            setLocal(wx, HIPR, rest, mul(rx(-44.0 * buckle), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(6.0 + 88.0 * buckle));
            setLocal(wx, ANKR, rest, ry(-6.0));
        }

        const freeSwing = OFF_ARM_SWING * mathx.cosf(armPh) * m;
        const clubSwing = CLUB_ARM_SWING * mathx.cosf(armPh - CLUB_LAG) * m;
        const clubPend = CLUB_PEND * (0.5 - 0.5 * mathx.cosf(armPh - CLUB_LAG - PEND_LAG)) * m;
        const freeFlex = OFF_ELBOW_SWING * (0.5 - 0.5 * mathx.cosf(armPh - 0.5)) * m;
        const clubFlex = CLUB_ELBOW_SWING * (0.5 - 0.5 * mathx.cosf(armPh - CLUB_LAG - 0.5)) * m;
        const hitchL = GIRDLE_SWING * OFF_ARM_SWING * mathx.cosf(armPh - GIRDLE_LAG) * m;
        const hitchR = GIRDLE_SWING * CLUB_ARM_SWING * mathx.cosf(armPh - CLUB_LAG - GIRDLE_LAG) * m;
        const shrugL = self.girdle + hitchL + 5.0 * lstun - 8.0 * dk2;
        const shrugR = (self.girdle + hitchR) * lerpF(1.0, CLAV_LOAD, hung) - CLAV_DROOP * hung + 4.0 * lstun - 10.0 * dk2;
        setLocal(wx, CLAVL, rest, mul(rz(shrugL), ry(-GIRDLE_PROT * prot)));
        setLocal(wx, CLAVR, rest, mul(rz(-shrugR), ry(GIRDLE_PROT * prot)));
        const armFly = -66.0 * lstun;
        setLocal(wx, SHL, rest, mul(rx(self.offShoulder + armFly * 0.6 - 18.0 * dk2 + freeSwing), rz(OFF_ABD + ARM_ABD_SWING * freeSwing)));
        setLocal(wx, ELL, rest, rx(self.offElbow - freeFlex));
        setLocal(wx, WRL, rest, rx(-WRIST_FLOP * freeSwing));
        setLocal(wx, SHR, rest, mul3(rx(self.clubShoulder + armFly - 22.0 * dk2 - clubSwing), rz(-self.clubAbd - ARM_ABD_SWING * clubSwing), ry(self.clubSweep)));
        setLocal(wx, ELR, rest, rx(self.clubElbow - clubFlex));
        setLocal(wx, WRR, rest, rl.math.matrixIdentity());
        const clubHold = CLUB_HOLD * mathx.maxF(0, clubSwing + clubFlex);
        setLocal(wx, CLUB, rest, rx(self.clubTilt + clubPend + clubHold - nod));
    }

    fn impactWorld(self: *const Ogre) rl.Vector3 {
        const low = self.clubLowWorld();
        return v3(low.x, self.pos.y + 0.05, low.z);
    }
    fn updateFx(self: *Ogre, dt: f32) void {
        foe.tickParticles(&self.parts, dt, self.pos.y);
    }
    const PUFF = foe.Puff{
        .blast = foe.Blast.of(foe.DUST_DRAG, 0.4, 0.7),
        .spdLo = 0.5,
        .upLo = 0.8,
        .upHi = 3.0,
        .rLo = 0.08,
        .rHi = 0.16,
    };
    fn dustBurst(self: *Ogre, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        foe.puff(&self.parts, &self.fxHead, &self.fxRng, v3(c.x, self.pos.y + 0.06, c.z), n, spd, big, self.scale, PUFF);
    }
    fn plantBurst(self: *Ogre) void {
        const f = mathx.headingDir(self.facing);
        for ([_]f32{ -1, 1 }) |side| {
            const rr = 0.42 * self.scale;
            const at = v3(self.pos.x - f.z * side * rr, self.pos.y + 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(at, 9, 2.0, 0.20);
        }
    }

    fn emitStrain(self: *Ogre, dt: f32, k: f32) void {
        const emitRate = (6.0 + 22.0 * k);
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.3, 0.9) * self.scale;
            const bp = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.05, self.pos.z + mathx.sinf(a) * rr);
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.3, 0.5);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = bp,
                .v = v3(self.fxRng.signed() * 0.3 * B.boost, self.fxRng.range(0.3, 1.0) * B.boost, self.fxRng.signed() * 0.3 * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.05, 0.11) * self.scale,
                .r1 = self.fxRng.range(0.1, 0.18) * self.scale,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }
    fn footfalls(self: *Ogre) void {
        if (self.moving < 0.4) {
            self.prevPhase = self.phase;
            return;
        }
        const crossed = (self.prevPhase < 0.5 and self.phase >= 0.5) or (self.phase < self.prevPhase); // 0.5 or the wrap past 0.0
        if (crossed) {
            self.jolt = 1.0;
            const side: f32 = if (self.phase < 0.5) 1.0 else -1.0;
            const f = self.fdir();
            const rr = 0.13 * H * self.scale;
            const foot = v3(self.pos.x - f.z * side * rr, self.pos.y + 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(foot, 6, 1.4, 0.14);
            sfx.world(.ogre_step, foot);
        }
        self.prevPhase = self.phase;
    }
    fn bloodBurst(self: *Ogre, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var s = BLOOD_SPRAY;
        if (!foe.onDryGround(self)) s.splat = 0;
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, s);
    }
    pub fn drawFx(self: *const Ogre) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Ogre, model: *const Model) void {
        model.draw(&self.xf);
    }
};

const CAP = wf.MAX_PER_KIND;

pub const Grief = struct {
    model: Model,
    ogres: [CAP]Ogre = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Grief {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Grief) []Ogre {
        return self.ogres[0..self.n];
    }
    pub fn liveConst(self: *const Grief) []const Ogre {
        return self.ogres[0..self.n];
    }
    pub fn reset(self: *Grief, m: *const wf.Map) void {
        foe.resetGroup(Ogre, &self.ogres, &self.n, m, .ogre);
    }
    pub fn setShader(self: *Grief, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Grief, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    /// …and whether any of them was caught on it this frame. A ONE-FRAME edge, `anyDied`'s, read after `update`.
    pub fn anyParried(self: *const Grief) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn update(self: *Grief, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Grief, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Grief) void {
        for (self.liveConst()) |*o| o.drawFx();
    }
    pub fn pierce(self: *Grief, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Grief) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Grief) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Grief) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Grief) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = torsoMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = headMesh();
    mesh[HIPL] = thighMesh();
    mesh[KNEEL] = shinMesh();
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh();
    mesh[KNEER] = shinMesh();
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh(0.94);
    mesh[ELL] = forearmMesh(31, false, 0.94);
    mesh[WRL] = fistMesh(true);
    mesh[SHR] = upperArmMesh(1.12);
    mesh[ELR] = forearmMesh(77, true, 1.10);
    mesh[WRR] = fistMesh(false);
    mesh[CLUB] = clubMesh();
    mesh[JAW] = jawMesh();
    mesh[TOEL] = toeMesh(1.0);
    mesh[TOER] = toeMesh(-1.0);
    mesh[HUMP] = humpMesh();
    mesh[CLAVL] = clavicleMesh(1.0, false);
    mesh[CLAVR] = clavicleMesh(-1.0, true);
    return mesh;
}

fn limb(b: *Builder, a: rl.Vector3, e: rl.Vector3, r0: f32, r1: f32, col: rl.Color) void {
    const mid = mathx.lerpV(a, e, 0.42);
    b.addCapsule(a, mid, r0, r0 * 1.09, 12, col);
    b.addCapsule(mid, e, r0 * 1.09, r1, 12, col);
    b.addBlob(e, v3(r1 * 1.16, r1 * 1.02, r1 * 1.16), 6, 12, col);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.002 * H, 0.005 * H), v3(0.152 * H, 0.086 * H, 0.132 * H), 8, 14, HIDE);
    b.addBlob(v3(0.070 * H, -0.010 * H, -0.080 * H), v3(0.082 * H, 0.070 * H, 0.072 * H), 7, 12, HIDE);
    b.addBlob(v3(-0.067 * H, -0.002 * H, -0.074 * H), v3(0.077 * H, 0.066 * H, 0.068 * H), 7, 12, HIDE);
    b.addBlob(v3(0, -0.072 * H, 0.042 * H), v3(0.084 * H, 0.050 * H, 0.070 * H), 7, 12, BELLY);
    b.addBlob(v3(0.095 * H, 0.048 * H, 0.020 * H), v3(0.050 * H, 0.032 * H, 0.048 * H), 5, 10, HIDE_LT);
    b.addBlob(v3(-0.092 * H, 0.052 * H, 0.016 * H), v3(0.046 * H, 0.030 * H, 0.046 * H), 5, 10, HIDE_LT);
    b.setMat(.leather);
    b.addCylinder(v3(0.10 * H, 0.048 * H, 0), v3(-0.10 * H, 0.058 * H, 0), 0.145 * H, 0.145 * H, 9, ROPE);
    b.setMat(.cloth);
    const strips = [_][3]f32{ .{ 0.088, 0.150, 0.128 }, .{ 0.030, 0.155, 0.176 }, .{ -0.036, 0.152, 0.104 }, .{ -0.092, 0.146, 0.150 }, .{ -0.006, -0.148, 0.132 } };
    for (strips) |s| {
        const w = 0.030 + 0.010 * @abs(s[0]);
        b.addBox(
            v3(s[0] * H, (-0.030 - s[2] * 0.5) * H, s[1] * H),
            v3(w * H, 0, 0.004 * H),
            v3(s[0] * 0.06 * H, -s[2] * 0.5 * H, if (s[1] > 0) 0.014 * H else -0.014 * H),
            v3(0, 0, 0.009 * H),
            RAG,
        );
    }
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0.008 * H, 0), v3(0, 0.120 * H, -0.004 * H), 0.150 * H, 0.186 * H, 16, HIDE);
    b.addBlob(v3(0, 0.040 * H, 0.072 * H), v3(0.158 * H, 0.088 * H, 0.112 * H), 9, 15, BELLY);
    b.addBlob(v3(0, -0.008 * H, 0.058 * H), v3(0.144 * H, 0.036 * H, 0.094 * H), 6, 13, HIDE_DK);
    b.addBlob(v3(0, 0.046 * H, 0.152 * H), v3(0.032 * H, 0.020 * H, 0.018 * H), 5, 9, HIDE_DK);
    b.addBlob(v3(0.088 * H, 0.020 * H, -0.062 * H), v3(0.062 * H, 0.058 * H, 0.056 * H), 6, 11, HIDE);
    b.addBlob(v3(-0.084 * H, 0.028 * H, -0.058 * H), v3(0.058 * H, 0.062 * H, 0.052 * H), 6, 11, HIDE);
    return b.toMesh();
}

const BARREL_Y = 0.022 * H;
const BARREL_HALF_H = 0.080 * H;
const BARREL_TOP = BARREL_Y + BARREL_HALF_H;

fn torsoMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, BARREL_Y, -0.012 * H), v3(0.232 * H, BARREL_HALF_H, 0.166 * H), 10, 17, HIDE);
    b.addBlob(v3(0, -0.036 * H, -0.005 * H), v3(0.206 * H, 0.062 * H, 0.150 * H), 8, 15, HIDE);
    b.addBlob(v3(0.070 * H, 0.012 * H, 0.108 * H), v3(0.090 * H, 0.070 * H, 0.078 * H), 8, 13, HIDE);
    b.addBlob(v3(-0.072 * H, 0.016 * H, 0.112 * H), v3(0.098 * H, 0.076 * H, 0.082 * H), 8, 13, HIDE);
    b.addBlob(v3(0, 0.000 * H, 0.140 * H), v3(0.030 * H, 0.088 * H, 0.030 * H), 6, 10, BELLY);
    b.addBlob(v3(0.010 * H, -0.060 * H, 0.126 * H), v3(0.098 * H, 0.026 * H, 0.040 * H), 6, 11, SCAR);
    var rng = mathx.Rng.init(7321);
    var w: i32 = 0;
    while (w < 16) : (w += 1) {
        const a = rng.angle();
        const yy = rng.range(-0.05, 0.10) * H;
        const rr = (0.226 - (yy / H + 0.02) * 0.34) * H;
        const sz = rng.range(0.016, 0.036) * H;
        b.addBlob(v3(mathx.cosf(a) * rr, yy, mathx.sinf(a) * rr * 0.72 - 0.012 * H), v3(sz, sz * rng.range(0.6, 1.1), sz * rng.range(0.7, 1.2)), 5, 9, if (rng.float() < 0.5) HIDE_DK else HIDE_LT);
    }
    return b.toMesh();
}

fn humpMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.008 * H, -0.090 * H), v3(0.146 * H, 0.088 * H, 0.092 * H), 10, 15, HIDE_DK);
    b.addBlob(v3(0.004 * H, 0.040 * H, -0.064 * H), v3(0.116 * H, 0.056 * H, 0.074 * H), 8, 14, HIDE);
    b.addBlob(v3(-0.058 * H, -0.048 * H, -0.104 * H), v3(0.058 * H, 0.044 * H, 0.044 * H), 6, 10, HIDE_DK);
    b.setMat(.steel);
    b.addBox(v3(0.055 * H, 0.050 * H, -0.118 * H), v3(0.028 * H, 0.007 * H, 0.0), v3(-0.006 * H, 0.052 * H, -0.024 * H), v3(0, 0, 0.006 * H), CLUB_IRON);
    b.setMat(.skin);
    b.addBlob(v3(0.055 * H, -0.020 * H, -0.138 * H), v3(0.020 * H, 0.052 * H, 0.014 * H), 6, 9, IRON_RUST);
    return b.toMesh();
}

fn clavicleMesh(side: f32, load: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const r0: f32 = if (load) 0.118 else 0.100;
    const r1: f32 = if (load) 0.088 else 0.076;
    const outer: f32 = if (load) 0.198 else 0.188;
    b.addCapsule(v3(side * 0.070 * H, 0.020 * H, -0.004 * H), v3(side * outer * H, -0.046 * H, 0), r0 * H, r1 * H, 13, HIDE);
    b.addBlob(v3(side * 0.162 * H, -0.026 * H, 0.006 * H), v3(r1 * 1.22 * H, r1 * 1.28 * H, r1 * 1.18 * H), 8, 13, HIDE);
    b.addBlob(v3(side * 0.112 * H, 0.030 * H, -0.030 * H), v3(0.060 * H, 0.030 * H, 0.050 * H), 6, 10, if (load) HIDE_LT else HIDE_DK);
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.016 * H, -0.020 * H), v3(0, 0.050 * H, 0.058 * H), 0.102 * H, 0.086 * H, 13, HIDE);
    b.addBlob(v3(0, 0.008 * H, -0.052 * H), v3(0.104 * H, 0.038 * H, 0.042 * H), 7, 12, HIDE_DK);
    b.addBlob(v3(0.062 * H, 0.014 * H, 0.026 * H), v3(0.034 * H, 0.044 * H, 0.030 * H), 6, 10, HIDE);
    b.addBlob(v3(-0.058 * H, 0.020 * H, 0.030 * H), v3(0.030 * H, 0.048 * H, 0.028 * H), 6, 10, HIDE);
    return b.toMesh();
}

const CRANIUM_Y = 0.058 * H;
const CRANIUM_HALF_H = 0.092 * H;
const CRANIUM_TOP = CRANIUM_Y + CRANIUM_HALF_H;

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, CRANIUM_Y, -0.002 * H), v3(0.130 * H, CRANIUM_HALF_H, 0.116 * H), 10, 16, HIDE);
    b.addBlob(v3(0, 0.006 * H, 0.050 * H), v3(0.118 * H, 0.074 * H, 0.100 * H), 9, 15, HIDE);
    b.addBlob(v3(0.014 * H, 0.104 * H, 0.014 * H), v3(0.052 * H, 0.018 * H, 0.064 * H), 6, 11, SCAR);
    b.addBlob(v3(0.004 * H, 0.070 * H, 0.088 * H), v3(0.098 * H, 0.028 * H, 0.044 * H), 8, 14, HIDE);
    b.addBlob(v3(-0.062 * H, 0.060 * H, 0.090 * H), v3(0.046 * H, 0.022 * H, 0.032 * H), 6, 11, HIDE_DK);
    b.addBlob(v3(0, 0.030 * H, 0.086 * H), v3(0.084 * H, 0.058 * H, 0.030 * H), 7, 13, EYE_RIM);
    b.setMat(.plain);
    // The orb between its two failures: at 0.046 it filled the face and read as a blank cream mask, and at
    // 0.036 the brow hid it from the game's own high camera on a drooped head — a cyclops with no visible
    // eye. 0.042, proud of the socket, under a THINNER brow: hooded, but it burns out from under it.
    b.addBlob(v3(0, 0.030 * H, 0.106 * H), v3(0.042 * H, 0.040 * H, 0.036 * H), 9, 14, EYE);
    b.addBlob(v3(0, 0.028 * H, 0.134 * H), v3(0.021 * H, 0.023 * H, 0.011 * H), 6, 11, PUPIL);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.058 * H, 0.108 * H), v3(0.050 * H, 0.015 * H, 0.028 * H), 7, 12, HIDE);
    b.addBlob(v3(0.032 * H, 0.044 * H, 0.116 * H), v3(0.028 * H, 0.013 * H, 0.020 * H), 6, 10, HIDE_DK);
    b.addBlob(v3(0, -0.012 * H, 0.106 * H), v3(0.090 * H, 0.020 * H, 0.026 * H), 6, 12, HIDE_DK);
    b.addBlob(v3(0.005 * H, -0.028 * H, 0.120 * H), v3(0.050 * H, 0.030 * H, 0.036 * H), 7, 12, HIDE_DK);
    b.addBlob(v3(0.014 * H, -0.012 * H, 0.124 * H), v3(0.024 * H, 0.020 * H, 0.020 * H), 6, 10, HIDE_LT);
    b.addBlob(v3(0.074 * H, -0.012 * H, 0.072 * H), v3(0.032 * H, 0.038 * H, 0.040 * H), 6, 11, HIDE_DK);
    b.addBlob(v3(-0.074 * H, -0.018 * H, 0.070 * H), v3(0.032 * H, 0.042 * H, 0.040 * H), 6, 11, HIDE_DK);
    b.addBlob(v3(0, -0.050 * H, 0.070 * H), v3(0.088 * H, 0.030 * H, 0.064 * H), 7, 12, MAW);
    b.addBlob(v3(0, -0.036 * H, 0.106 * H), v3(0.086 * H, 0.016 * H, 0.026 * H), 6, 12, HIDE);
    b.setMat(.stone);
    for ([_]f32{ -1.2, -0.45, 0.45, 1.2 }) |t| {
        const tl: f32 = if (t < 0) 0.028 else 0.021;
        b.addCapsule(v3(t * 0.030 * H, -0.046 * H, 0.098 * H), v3(t * 0.032 * H, (-0.046 - tl) * H, 0.100 * H), 0.013 * H, 0.006 * H, 8, if (t < 0) TUSK else TUSK_DK);
    }
    b.setMat(.skin);
    b.addBlob(v3(0.134 * H, 0.014 * H, -0.012 * H), v3(0.020 * H, 0.058 * H, 0.042 * H), 7, 11, HIDE);
    b.addBlob(v3(0.142 * H, 0.052 * H, -0.024 * H), v3(0.012 * H, 0.030 * H, 0.024 * H), 6, 9, HIDE_DK);
    b.addBlob(v3(-0.132 * H, 0.002 * H, -0.010 * H), v3(0.018 * H, 0.038 * H, 0.032 * H), 7, 10, HIDE);
    b.addBlob(v3(-0.136 * H, 0.028 * H, -0.014 * H), v3(0.012 * H, 0.012 * H, 0.018 * H), 5, 9, SCAR);
    return b.toMesh();
}

fn jawMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.040 * H, 0.060 * H), v3(0.100 * H, 0.038 * H, 0.076 * H), 9, 14, HIDE);
    b.addBlob(v3(0, -0.056 * H, 0.020 * H), v3(0.086 * H, 0.030 * H, 0.056 * H), 7, 12, HIDE);
    b.addBlob(v3(0, -0.019 * H, 0.100 * H), v3(0.066 * H, 0.014 * H, 0.020 * H), 6, 12, HIDE_DK);
    b.addBlob(v3(0.052 * H, -0.028 * H, 0.096 * H), v3(0.024 * H, 0.012 * H, 0.015 * H), 5, 10, HIDE_DK);
    b.addBlob(v3(-0.050 * H, -0.031 * H, 0.094 * H), v3(0.026 * H, 0.012 * H, 0.015 * H), 5, 10, HIDE_DK);
    b.setMat(.plain);
    b.addBlob(v3(0, -0.026 * H, 0.050 * H), v3(0.052 * H, 0.013 * H, 0.050 * H), 7, 12, TONGUE);
    b.setMat(.stone);
    b.addCapsule(v3(0.050 * H, -0.030 * H, 0.106 * H), v3(0.078 * H, 0.036 * H, 0.126 * H), 0.024 * H, 0.015 * H, 9, TUSK);
    b.addCapsule(v3(0.078 * H, 0.036 * H, 0.126 * H), v3(0.074 * H, 0.096 * H, 0.116 * H), 0.015 * H, 0.008 * H, 8, TUSK);
    b.addCapsule(v3(-0.054 * H, -0.034 * H, 0.104 * H), v3(-0.082 * H, 0.028 * H, 0.122 * H), 0.026 * H, 0.014 * H, 9, TUSK_DK);
    b.addBlob(v3(-0.082 * H, 0.032 * H, 0.122 * H), v3(0.015 * H, 0.010 * H, 0.014 * H), 6, 9, PUPIL);
    for ([_]f32{ -0.6, 0.6 }) |t| {
        b.addCapsule(v3(t * 0.032 * H, -0.022 * H, 0.098 * H), v3(t * 0.034 * H, 0.006 * H, 0.100 * H), 0.012 * H, 0.006 * H, 7, TUSK_DK);
    }
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.10 * H, 0.075 * H, HIDE);
    b.addBlob(v3(0.058 * H, -0.100 * H, 0.048 * H), v3(0.044 * H, 0.042 * H, 0.030 * H), 6, 11, SCAR);
    b.addBlob(v3(-0.010 * H, -0.062 * H, -0.062 * H), v3(0.060 * H, 0.070 * H, 0.040 * H), 7, 12, HIDE);
    return b.toMesh();
}

fn shinMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_SHANK * H, 0), 0.072 * H, 0.055 * H, HIDE);
    b.addBlob(v3(0, -0.070 * H, -0.048 * H), v3(0.062 * H, 0.070 * H, 0.038 * H), 7, 12, HIDE);
    b.addBlob(v3(0, -0.190 * H, -0.030 * H), v3(0.036 * H, 0.052 * H, 0.024 * H), 6, 11, HIDE_DK);
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const ay = 0.039 * H;
    const PAD_UP = 0.036 * H;
    b.addCapsule(v3(0, -ay + 0.032 * H + PAD_UP, -0.026 * H), v3(0, -ay + 0.026 * H + PAD_UP, 0.086 * H), 0.068 * H, 0.058 * H, 13, HIDE);
    b.addBlob(v3(0, -ay + 0.044 * H + PAD_UP, -0.030 * H), v3(0.062 * H, 0.052 * H, 0.058 * H), 8, 13, HIDE_DK);
    b.addBlob(v3(side * 0.020 * H, -ay + 0.020 * H + PAD_UP, 0.030 * H), v3(0.062 * H, 0.034 * H, 0.062 * H), 7, 12, HIDE);
    return b.toMesh();
}

fn toeMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    for ([_]f32{ -1, 0, 1 }) |t| {
        const tl: f32 = if (t == 0) 0.082 else 0.066;
        b.addCapsule(v3(t * 0.040 * H * side, 0.002 * H, 0.002 * H), v3(t * 0.048 * H * side, -0.005 * H, tl * H), 0.031 * H, 0.024 * H, 11, HIDE);
    }
    b.setMat(.stone);
    for ([_]f32{ -1, 0, 1 }) |t| {
        const nl: f32 = if (t * side > 0.5) 0.010 else 0.016;
        const tz: f32 = if (t == 0) 0.084 else 0.069;
        b.addBlob(v3(t * 0.048 * H * side, -0.004 * H, tz * H), v3(0.021 * H, 0.015 * H, nl * H), 6, 10, TUSK_DK);
    }
    return b.toMesh();
}

fn upperArmMesh(girth: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // Leaner than it was (0.088/0.072): the mass moved to the fists.
    limb(&b, v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.077 * H * girth, 0.063 * H * girth, HIDE);
    b.addBlob(v3(0, -0.064 * H, 0.046 * H), v3(0.055 * H * girth, 0.064 * H, 0.036 * H * girth), 7, 12, HIDE);
    b.addBlob(v3(0, -0.078 * H, -0.043 * H), v3(0.050 * H * girth, 0.070 * H, 0.032 * H * girth), 7, 12, HIDE);
    b.addBlob(v3(-0.018 * H, -0.082 * H, 0.062 * H), v3(0.030 * H, 0.047 * H, 0.018 * H), 6, 11, SCAR);
    return b.toMesh();
}

fn forearmMesh(seed: u64, corded: bool, girth: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_FOREARM * H, 0), 0.066 * H * girth, 0.053 * H * girth, HIDE);
    b.addBlob(v3(0, -0.043 * H, 0.018 * H), v3(0.062 * H * girth, 0.050 * H, 0.051 * H * girth), 7, 12, HIDE);
    var rng = mathx.Rng.init(seed);
    b.addBlob(v3(rng.range(-0.027, 0.027) * H, -rng.range(0.055, 0.11) * H, 0.046 * H), v3(0.027 * H, 0.023 * H, 0.018 * H), 6, 10, if (rng.float() < 0.5) SCAR else HIDE_DK);
    if (corded) {
        b.setMat(.leather);
        b.addCylinder(v3(0, -0.066 * H, 0), v3(0, -0.093 * H, 0), 0.066 * H * girth, 0.064 * H * girth, 8, ROPE);
        b.addCylinder(v3(0, -0.111 * H, 0), v3(0, -0.129 * H, 0), 0.061 * H * girth, 0.059 * H * girth, 8, ROPE);
    }
    return b.toMesh();
}

fn fistMesh(shackled: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.032 * H, 0.009 * H), v3(0.078 * H, 0.073 * H, 0.070 * H), 9, 13, HIDE);
    b.addBlob(v3(0, -0.054 * H, 0.023 * H), v3(0.066 * H, 0.038 * H, 0.060 * H), 7, 12, HIDE);
    b.setMat(.skin);
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |k| {
        b.addBlob(v3(k * 0.034 * H, -0.010 * H, 0.050 * H), v3(0.022 * H, 0.020 * H, 0.020 * H), 6, 10, HIDE_LT);
    }
    b.setMat(.stone);
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |k| {
        const nl: f32 = if (k > 1.0) 0.013 else 0.019;
        b.addBlob(v3(k * 0.034 * H, -0.015 * H, 0.070 * H), v3(0.016 * H, 0.020 * H, nl * H), 6, 10, TUSK_DK);
    }
    if (shackled) {
        b.setMat(.steel);
        b.addCylinder(v3(0, 0.040 * H, 0.005 * H), v3(0, 0.012 * H, 0.005 * H), 0.057 * H, 0.055 * H, 8, CLUB_IRON);
        b.addCube(v3(0, 0.026 * H, 0.064 * H), v3(0.020 * H, 0.024 * H, 0.014 * H), IRON_RUST);
        var li: i32 = 0;
        while (li < 3) : (li += 1) {
            const fi = @as(f32, @floatFromInt(li));
            b.addCube(
                v3(0.005 * H * fi, (-0.005 - 0.036 * fi) * H, (0.066 + 0.007 * fi) * H),
                v3(0.013 * H, 0.026 * H, 0.009 * H),
                if (li == 1) IRON_RUST else CLUB_IRON,
            );
        }
    }
    return b.toMesh();
}

const CLUB_DROP = 0.30 * H;
const CLUB_HEAD_R = 0.118 * H;
const CLUB_HEAD_HH = 0.082 * H;
const gy = -0.03 * H;
const gz = 0.02 * H;
const CLUB_LOW = v3(0, gy - CLUB_DROP - 0.014 * H, gz + 0.022 * H);
fn clubMesh() rl.Mesh {
    var b = Builder.init();
    const headY = gy - CLUB_DROP + CLUB_HEAD_HH;
    const drumTop = headY + CLUB_HEAD_HH;
    b.setMat(.leather);
    b.addCapsule(v3(0, gy + 0.19 * H, gz), v3(0, gy + 0.11 * H, gz), 0.038 * H, 0.042 * H, 10, ROPE);
    b.setMat(.wood);
    b.addCylinder(v3(0, gy + 0.11 * H, gz), v3(0, gy, gz), 0.042 * H, 0.048 * H, 10, CLUB_WOOD_LT);
    b.addCylinder(v3(0, gy, gz), v3(0, drumTop + 0.055 * H, gz + 0.010 * H), 0.052 * H, 0.070 * H, 10, CLUB_WOOD);
    b.addCylinder(v3(0, drumTop + 0.055 * H, gz + 0.010 * H), v3(0, drumTop - 0.012 * H, gz + 0.022 * H), 0.070 * H, 0.104 * H, 10, CLUB_WOOD);
    b.setMat(.steel);
    b.addCylinder(v3(0, gy - 0.062 * H, gz + 0.005 * H), v3(0, gy - 0.086 * H, gz + 0.006 * H), 0.072 * H, 0.072 * H, 8, CLUB_IRON);
    b.addCylinder(v3(0, drumTop + 0.022 * H, gz + 0.013 * H), v3(0, drumTop - 0.004 * H, gz + 0.015 * H), 0.092 * H, 0.094 * H, 8, IRON_RUST);
    b.setMat(.stone);
    b.addBlob(v3(0, headY, gz + 0.022 * H), v3(CLUB_HEAD_R * 1.06, CLUB_HEAD_HH, CLUB_HEAD_R * 1.06), 10, 14, CLUB_STONE);
    b.addBlob(v3(0.034 * H, headY + 0.022 * H, gz + 0.004 * H), v3(CLUB_HEAD_R * 0.80, CLUB_HEAD_HH * 0.92, CLUB_HEAD_R * 0.86), 8, 12, CLUB_STONE);
    b.setMat(.steel);
    var rng = mathx.Rng.init(5119);
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const yy = headY + rng.range(-0.03, 0.085) * H;
        const rr = CLUB_HEAD_R;
        const cx = mathx.cosf(a) * rr;
        const cz = gz + 0.022 * H + mathx.sinf(a) * rr;
        const sz = rng.range(0.020, 0.036) * H;
        const roll = rng.float();
        b.addBlob(v3(cx, yy, cz), v3(sz, sz * rng.range(0.7, 1.25), sz), 6, 10, if (roll < 0.35) CLUB_IRON else if (roll < 0.5) IRON_RUST else CLUB_STONE);
        if (rng.float() < 0.5) {
            const sl = rng.range(1.7, 2.25);
            b.addCylinder(v3(cx, yy, cz), v3(cx * sl, yy + rng.range(-0.02, 0.03) * H, gz + 0.022 * H + (cz - (gz + 0.022 * H)) * sl), 0.027 * H, 0.002 * H, 5, CLUB_IRON);
        }
    }
    b.addBox(v3(0.12 * H, headY + 0.055 * H, gz + 0.10 * H), v3(0.05 * H, 0.014 * H, 0.03 * H), v3(-0.004 * H, 0.05 * H, -0.01 * H), v3(0, 0, 0.006 * H), CLUB_IRON);
    b.addBox(v3(-0.11 * H, headY - 0.04 * H, gz - 0.055 * H), v3(0.055 * H, 0.010 * H, -0.035 * H), v3(0.004 * H, 0.012 * H, 0.0), v3(0, 0, 0.005 * H), IRON_RUST);
    return b.toMesh();
}

test "the swipe leaves a REACHABLE pocket at his feet — the counter has to exist" {
    const o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    const closest = foe.closestApproach(o.bodyR());
    const sectorInner = SWIPE_INNER * o.scale - HERO_REACH;
    try std.testing.expect(sectorInner > closest + 0.2);
    try std.testing.expect(sectorInner < SWIPE_OUTER * o.scale);
}

test "the carried club NEVER touches the ground — standing or lumbering (owner's law)" {
    var idle = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    var k: i32 = 0;
    while (k < 90) : (k += 1) {
        _ = idle.update(1.0 / 60.0, v3(0, 0, 80), 60, .{});
        try std.testing.expect(idle.clubLowWorld().y > 0.15);
    }
    var walk = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    var j: i32 = 0;
    var minY: f32 = 99;
    while (j < 160) : (j += 1) {
        _ = walk.update(1.0 / 60.0, v3(0, 0, 15), 60, .{});
        if (walk.state == .approach) minY = mathx.minF(minY, walk.clubLowWorld().y);
    }
    try std.testing.expect(minY > 0.15);
}

test "the SLAM reaches the earth, and the crush strip ends where the club does" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    o.debugSlam();
    var deepest: f32 = 99;
    var axialAtEarth: f32 = 0;
    var k: i32 = 0;
    while (k < 600 and (o.state == .windup or o.state == .slam)) : (k += 1) {
        _ = o.update(1.0 / 60.0, v3(0, 0, 2), 60, .{});
        if (o.state != .slam) continue;
        const c = o.clubLowWorld();
        if (c.y < 0.25 and axialAtEarth == 0) axialAtEarth = mathx.distXZ(o.pos, c);
        deepest = mathx.minF(deepest, c.y);
    }
    try std.testing.expect(deepest < 0.12);
    const stripEnd = SLAM_LEN * o.scale;
    try std.testing.expect(stripEnd > axialAtEarth and stripEnd < axialAtEarth + 1.2);
    try std.testing.expect(SLAM_R < stripEnd + HERO_REACH);
}

test "the head clears the chest barrel — a giant with no visible head is the fail this guards" {
    // THE MASSES, NOT THE JOINTS, and the WHOLE STRIDE: the skull joint sits 0.150·H under the cranium it
    // carries, so a joint comparison is that much stricter than the test's name — and sampled at one frame it
    // flipped on a nudge to `SCALE` with the rig unmoved.
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    var worst: f32 = 99;
    var k: i32 = 0;
    while (k < 400) : (k += 1) {
        _ = o.update(1.0 / 60.0, v3(0, 0, 15), 60, .{});
        if (k < 60) continue;
        const chest = rl.math.vector3Transform(mathx.zero3, o.xf[CHEST]);
        const skull = rl.math.vector3Transform(mathx.zero3, o.xf[SKULL]);
        worst = @min(worst, (skull.y - chest.y) / (H * o.scale));
    }
    const shows = worst + CRANIUM_TOP / H - BARREL_TOP / H;
    try std.testing.expect(shows > 0.10);
    try std.testing.expect(worst > 0.06);
}

test "the swipe's hurt SECTOR matches where the club actually goes (band + arc, measured)" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    o.debugSwipe();
    var lowest: f32 = 99;
    var highest: f32 = -99;
    var frames: u32 = 0;
    var fr: i32 = 0;
    while (fr < 600 and (o.state == .swipewind or o.state == .swipe)) : (fr += 1) {
        _ = o.update(1.0 / 60.0, v3(3.6, 0, -1.2), 60, .{});
        if (o.state != .swipe) continue;
        frames += 1;
        const club = o.clubLowWorld();
        const rad = mathx.distXZ(o.pos, club);
        try std.testing.expect(rad >= SWIPE_INNER * o.scale and rad <= SWIPE_OUTER * o.scale);
        const bearing = mathx.degrees(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(o.pos, club)) - o.facing));
        try std.testing.expect(@abs(mathx.wrapDeg(bearing - SWIPE_ARC_MID)) <= SWIPE_ARC * 0.5);
        lowest = mathx.minF(lowest, club.y);
        highest = mathx.maxF(highest, club.y);
    }
    try std.testing.expect(frames > 6);
    // …and it scythes THROUGH a hero-sized body (head 1.7 down to hip ~1.0), not over his hat.
    try std.testing.expect(highest > 1.6 and lowest < 1.3);
}

test "attack choice: squared up crushes, flanked SWIPES, cooling looms, far closes, out of aggro idles" {
    const o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const inner = o.swipeInner(); // where the sweep starts biting — 2.28 on a full-size one
    const mid = (inner + SWIPE_R) * 0.5;
    try std.testing.expectEqual(Choice.idle, classify(AGGRO_R + 1, 0, true, true, true, inner));
    try std.testing.expectEqual(Choice.slam, classify(SLAM_R - 0.5, 0, true, true, true, inner));
    try std.testing.expectEqual(Choice.swipe, classify(mid, 80, true, true, false, inner));
    try std.testing.expectEqual(Choice.swipe, classify(SWIPE_R - 0.2, -120, true, true, false, inner));
    try std.testing.expectEqual(Choice.swipe, classify(mid, 0, false, true, false, inner));
    try std.testing.expectEqual(Choice.wait, classify(SLAM_R - 0.5, 0, false, false, false, inner));

    const near = inner + (SWIPE_R - inner) * SWIPE_NEAR_K;
    try std.testing.expectEqual(Choice.swipe, classify(inner + 0.05, 0, true, true, true, inner));
    try std.testing.expectEqual(Choice.swipe, classify(near - 0.05, 0, true, true, true, inner));
    try std.testing.expectEqual(Choice.approach, classify(near + 0.05, 0, true, true, true, inner));
    try std.testing.expect(near < SWIPE_R);
    try std.testing.expectEqual(Choice.approach, classify(SWIPE_R + 1.0, 90, true, true, false, inner));
    try std.testing.expectEqual(Choice.approach, classify((SWIPE_R + AGGRO_R) * 0.5, 0, true, true, true, inner));

    try std.testing.expectEqual(Choice.drive, classify((DRIVE_MIN + DRIVE_MAX) * 0.5, 0, true, true, true, inner));
    try std.testing.expectEqual(Choice.drive, classify(DRIVE_MAX - 0.1, 140, true, true, true, inner));
    try std.testing.expectEqual(Choice.approach, classify((DRIVE_MIN + DRIVE_MAX) * 0.5, 0, true, true, false, inner));
    try std.testing.expectEqual(Choice.approach, classify(DRIVE_MAX + 0.5, 0, true, true, true, inner));
    try std.testing.expect(DRIVE_MIN > SWIPE_R);

    // HE NEVER SWIPES AT SOMETHING HUGGING HIS LEGS. Inside the band the arc passes clean outside the hero, so
    // the move is a guaranteed miss however flanked he is — he looms or crushes instead.
    const hugging = inner - 0.3;
    try std.testing.expectEqual(Choice.slam, classify(hugging, 80, true, true, false, inner));
    try std.testing.expectEqual(Choice.wait, classify(hugging, 80, false, true, false, inner));
    const toeToToe = o.bodyR() + foe.HERO_R;
    try std.testing.expect(toeToToe < inner);
    try std.testing.expectEqual(Choice.wait, classify(toeToToe, 0, false, true, false, inner));
}

test "range bands are ordered and sit inside aggro" {
    try std.testing.expect(SLAM_R < SWIPE_R);
    try std.testing.expect(SWIPE_R < DRIVE_MIN);
    try std.testing.expect(DRIVE_MAX < AGGRO_R);
}

test "THE DRIVE ALWAYS REACHES: surge travel + the crush strip covers its own band's far edge" {
    // The swipe's lesson (the cannot-land law): a move chosen at a range it cannot cover is a promised miss.
    const travel = DRIVE_SPEED * DRIVE_DUR * DRIVE_IMPACT_K;
    const o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    try std.testing.expect(travel + o.slamReach() >= DRIVE_MAX);
    try std.testing.expect(DRIVE_MIN > SLAM_R);

    // …and MEASURED, not asserted: spawn one at mid-band, let it run, and the blow must arrive.
    var g = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const hero = v3(0, 0, (DRIVE_MIN + DRIVE_MAX) * 0.5 + 1.0);
    var landed = false;
    var drove = false;
    var frames: i32 = 0;
    while (frames < 60 * 4) : (frames += 1) {
        if (g.update(1.0 / 60.0, hero, 60, .{}) != null) landed = true;
        if (g.state == .drive) drove = true;
        if (landed) break;
    }
    try std.testing.expect(drove);
    try std.testing.expect(landed);
    try std.testing.expect(mathx.distXZ(g.pos, mathx.zero3) > 2.0);
}

test "THE DRIVE IS A LEAP as far as the roots go: held feet choose the trudge instead" {
    var g = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    g.root.grab();
    var frames: i32 = 0;
    while (frames < 30) : (frames += 1) _ = g.update(1.0 / 60.0, v3(0, 0, (DRIVE_MIN + DRIVE_MAX) * 0.5), 60, .{});
    try std.testing.expect(g.state != .drivewind and g.state != .drive);
}

test "swipe hurt SECTOR: sweeps the whole front arc, misses the flanks behind it and the legs" {
    var side = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    side.trySwipe(v3(-2.4, 0, 2.4), SWIPE_HIT); // 45 deg off his front on the CLUB side — the arc's path
    try std.testing.expect(side.heroHit != null);

    var front = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    front.trySwipe(v3(0, 0, 3.0), SWIPE_HIT);
    try std.testing.expect(front.heroHit != null);

    var offside = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    offside.trySwipe(v3(2.6, 0, 1.6), SWIPE_HIT);
    try std.testing.expect(offside.heroHit == null); // (measured: the sweep dies at about +22 deg)

    var behind = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.trySwipe(v3(0, 0, -3.0), SWIPE_HIT);
    try std.testing.expect(behind.heroHit == null);

    var under = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    under.trySwipe(v3(0, 0, 0.35), SWIPE_HIT);
    try std.testing.expect(under.heroHit == null);

    var far = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.trySwipe(v3(0, 0, SWIPE_OUTER * SCALE + 2.0), SWIPE_HIT);
    try std.testing.expect(far.heroHit == null);
}

test "the RETURN's hurt sector matches where the club actually goes (band + arc, measured)" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    o.debugBackswipe();
    var lowest: f32 = 99;
    var highest: f32 = -99;
    var minB: f32 = 999;
    var maxB: f32 = -999;
    var frames: u32 = 0;
    var fr: i32 = 0;
    while (fr < 60) : (fr += 1) {
        _ = o.update(1.0 / 60.0, v3(0, 0, 3.4), 60, .{});
        if (o.state != .backswipe) continue;
        frames += 1;
        const club = o.clubLowWorld();
        const rad = mathx.distXZ(o.pos, club);
        try std.testing.expect(rad >= SWIPE_INNER * o.scale and rad <= SWIPE_OUTER * o.scale);
        const bearing = mathx.degrees(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(o.pos, club)) - o.facing));
        minB = mathx.minF(minB, bearing);
        maxB = mathx.maxF(maxB, bearing);
        try std.testing.expect(@abs(mathx.wrapDeg(bearing - BACK_ARC_MID)) <= BACK_ARC * 0.5);
        lowest = mathx.minF(lowest, club.y);
        highest = mathx.maxF(highest, club.y);
    }
    try std.testing.expect(frames > 6);
    try std.testing.expect(maxB - minB > 100.0);
    // …and it stays INSIDE the hero column through the front (a RISING cut, chest-high where it re-crosses
    // — the deep scythe was the outbound's job; a return over his head would be a hit the sector cannot bill).
    try std.testing.expect(lowest < 1.5 and highest > 1.6);
}

test "THE TAIL IS NEVER SAFE, ONLY USUALLY SAFE: the swipe sometimes returns, and only in the band" {
    var chains: u32 = 0;
    var recovers: u32 = 0;
    var s: u32 = 0;
    while (s < 14) : (s += 1) {
        var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, @as(f32, @floatFromInt(s)) * 0.37 + 0.1);
        o.debugSwipe();
        var fr: i32 = 0;
        while (fr < 90) : (fr += 1) {
            _ = o.update(1.0 / 60.0, v3(0, 0, 3.2), 60, .{});
            if (o.state == .backwind or o.state == .backswipe) {
                chains += 1;
                break;
            }
            if (o.state == .recover) {
                recovers += 1;
                break;
            }
        }
    }
    try std.testing.expect(chains > 0);
    try std.testing.expect(recovers > 0);

    // Out of the band there is no roll at all — a return that cannot land is not a decision.
    var s2: u32 = 0;
    while (s2 < 14) : (s2 += 1) {
        var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, @as(f32, @floatFromInt(s2)) * 0.37 + 0.1);
        o.debugSwipe();
        var fr: i32 = 0;
        while (fr < 90) : (fr += 1) {
            _ = o.update(1.0 / 60.0, v3(0, 0, 12.0), 60, .{});
            try std.testing.expect(o.state != .backwind and o.state != .backswipe);
            if (o.state == .recover) break;
        }
    }
}

test "higher poise: a single hero light does NOT flinch the ogre (only sustained pressure does)" {
    var vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX);
    try std.testing.expectEqual(combat.HitResult.none, vit.hit(heromod.ATK_LIGHT_HIT));
    _ = vit.hit(heromod.ATK_LIGHT_HIT);
    try std.testing.expectEqual(combat.HitResult.light, vit.hit(heromod.ATK_LIGHT_HIT));
}

test "slam crush is the club's LINE: hits ahead on the axis, clears the flanks + behind" {
    var front = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    front.tryImpact(v3(0, 0, 2.0), SLAM_HIT);
    try std.testing.expect(front.heroHit != null);

    var beside = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    beside.tryImpact(v3(2.4, 0, 0.6), SLAM_HIT);
    try std.testing.expect(beside.heroHit == null);

    var grazing = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    grazing.tryImpact(v3(0.9, 0, 1.8), SLAM_HIT);
    try std.testing.expect(grazing.heroHit != null);

    var behind = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.tryImpact(v3(0, 0, -2.0), SLAM_HIT);
    try std.testing.expect(behind.heroHit == null);

    var far = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.tryImpact(v3(0, 0, 99), SLAM_HIT);
    try std.testing.expect(far.heroHit == null);
}

test "NO ATTACK COMES OUT OF NOWHERE: every one of the giant's moves rears first" {
    try std.testing.expect(WINDUP_DUR >= foe.TELL_MIN);
    try std.testing.expect(SWIPE_WIND_DUR >= foe.TELL_MIN);
    try std.testing.expect(BACK_WIND_DUR >= foe.TELL_MIN);
    try std.testing.expect(DRIVE_WIND_DUR >= foe.TELL_MIN);
    try std.testing.expect(WINDUP_DUR > SWIPE_WIND_DUR * 2.0);
}

test "THE WINDOW IS AN INSTANT BEFORE THE HIT — the same instant for both moves" {
    try std.testing.expect(PARRY_LEAD > 0);
    // …and it is an INSTANT, not a slice of the tell. A 1.2 s rear must not be catchable for a fifth of itself.
    try std.testing.expect(PARRY_LEAD < WINDUP_DUR * 0.15);
    try std.testing.expect(PARRY_LEAD < SWIPE_WIND_DUR * 0.4);

    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    // MEASURED off the state machine rather than asserted about the constants: walk each move frame by frame
    // from its first and collect the span that is actually parryable. The slam runs with a HELD tell on
    // purpose — the hold stretches the rear, and the window must not move with it: what is parried is the drop.
    const HOLD = 0.4;
    for ([_]struct { wind: State, swing: State, windDur: f32, impact: f32 }{
        .{ .wind = .windup, .swing = .slam, .windDur = WINDUP_DUR + HOLD, .impact = SLAM_DUR * SLAM_IMPACT_K },
        .{ .wind = .swipewind, .swing = .swipe, .windDur = SWIPE_WIND_DUR, .impact = SWIPE_DUR * SWIPE_IMPACT_K },
        .{ .wind = .backwind, .swing = .backswipe, .windDur = BACK_WIND_DUR, .impact = BACK_DUR * BACK_IMPACT_K },
        .{ .wind = .drivewind, .swing = .drive, .windDur = DRIVE_WIND_DUR, .impact = DRIVE_DUR * DRIVE_IMPACT_K },
    }) |m| {
        const step = 1.0 / 600.0;
        var open: f32 = -1;
        var shut: f32 = -1;
        var elapsed: f32 = 0;
        o.enter(m.wind);
        o.t = 0;
        o.windHold = if (m.wind == .windup) HOLD else 0;
        while (elapsed <= m.windDur + m.impact) : (elapsed += step) {
            if (elapsed > m.windDur and o.state == m.wind) {
                o.enter(m.swing);
                o.t = elapsed - m.windDur;
            } else {
                o.t = if (o.state == m.wind) elapsed else elapsed - m.windDur;
            }
            if (o.parryable() != null) {
                if (open < 0) open = elapsed;
                shut = elapsed;
            }
        }
        try std.testing.expect(open > 0);
        try std.testing.expectApproxEqAbs(m.windDur + m.impact, shut, 2.0 * step);
        try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);
    }
    o.enter(.recover);
    o.t = 0;
    try std.testing.expect(o.parryable() == null);
}

test "A STAGGER GIVES THE POSTURE BACK BEFORE IT ENDS, so the next move starts from the carry" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    o.enter(.windup);
    var t: f32 = 0;
    while (t < WINDUP_DUR) : (t += 1.0 / 60.0) o.setWindup(mathx.smoothstep(0, WINDUP_DUR * 0.82, t));
    try std.testing.expect(@abs(o.clubShoulder - CARRY_SH) > 100.0);
    o.enterStun(.stunlight);
    t = 0;
    while (t < combat.FOE_LIGHT_STUN_DUR) : (t += 1.0 / 60.0) o.easeChannelsNeutral(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(CARRY_SH, o.clubShoulder, 0.01);
    try std.testing.expectApproxEqAbs(CARRY_EL, o.clubElbow, 0.01);
    try std.testing.expectApproxEqAbs(HUNCH, o.bodyLean, 0.01);
    try std.testing.expectApproxEqAbs(CARRY_TILT, o.clubTilt, 0.01);
    try std.testing.expectApproxEqAbs(CLUB_ABD, o.clubAbd, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), o.twist, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), o.legBrace, 0.01);
    try std.testing.expectApproxEqAbs(JAW_REST, o.jawOpen, 0.01);
    try std.testing.expect(@abs(OVER_SH - CARRY_SH) / STUN_EASE_DEG > 0.3);
}

test "A CAUGHT SLAM NEVER LANDS, and the second catch is the punish window" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const hero = v3(0, 0, 2.0);
    o.enter(.slam);
    o.t = SLAM_DUR * SLAM_IMPACT_K - PARRY_LEAD * 0.5;
    o.parry = .{ .live = true, .at = hero, .facing = 0 };
    o.takeParry();
    try std.testing.expect(!o.parried and o.state == .slam);
    o.parry = .{ .live = true, .at = hero, .facing = std.math.pi };
    o.takeParry();
    try std.testing.expect(o.parried);
    try std.testing.expectEqual(State.stunlight, o.state);
    try std.testing.expect(o.slamCd > 0);
    o.parry = .{};
    var t: f32 = 0;
    while (t < combat.FOE_LIGHT_STUN_DUR - 1.0 / 60.0) : (t += 1.0 / 60.0) {
        try std.testing.expect(o.update(1.0 / 60.0, hero, 60.0, .{}) == null);
    }
    o.enter(.swipe);
    o.t = SWIPE_DUR * SWIPE_IMPACT_K - PARRY_LEAD * 0.5;
    o.parried = false;
    o.parry = .{ .live = true, .at = hero, .facing = std.math.pi };
    o.takeParry();
    try std.testing.expect(o.parried);
    try std.testing.expectEqual(State.stunheavy, o.state);
    try std.testing.expect(combat.FOE_HEAVY_STUN_DUR > combat.FOE_LIGHT_STUN_DUR);
}

test "HE FALLS, HE IS NOT LOWERED — the topple accelerates, overshoots flat, and the ground answers" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.2);
    o.debugKill();
    const skullAt = struct {
        fn y(og: *Ogre, du: f32) f32 {
            og.t = du * DEATH_DUR;
            og.pose();
            return foe.markOn(og.xf[SKULL], mathx.zero3).y;
        }
    }.y;
    // The second half of the fall covers far more height than the first — quadratic, not eased.
    const drop1 = skullAt(&o, 0.22) - skullAt(&o, 0.42);
    const drop2 = skullAt(&o, 0.42) - skullAt(&o, DEATH_LAND);
    std.debug.print("\n  ogre death: skull drops {d:.2} m then {d:.2} m — the fall accelerates\n", .{ drop1, drop2 });
    try std.testing.expect(drop2 > drop1 * 2.0);
    // …and it OVERSHOOTS its rest and settles back onto it: past the landing the skull dips lower still.
    try std.testing.expect(skullAt(&o, 0.72) < skullAt(&o, 0.88));

    // THE BODY ARRIVING IS AN EVENT — the landing frame throws dust, once.
    var g = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.2);
    g.debugKill();
    const dt: f32 = 1.0 / 60.0;
    var burst: usize = 0;
    var t: f32 = 0;
    while (t < DEATH_DUR) : (t += dt) {
        const before = g.fxHead;
        _ = g.update(dt, mathx.ground(0, 9), 500.0, .{});
        const emitted = (g.fxHead + FX_MAX - before) % FX_MAX;
        if (t < DEATH_DUR * DEATH_LAND and t + dt >= DEATH_DUR * DEATH_LAND) burst = emitted;
    }
    std.debug.print("  ogre death: the landing frame threw {d} dust\n", .{burst});
    try std.testing.expect(burst >= 15);
}

test "THE WOUND OPENS: five frames on, a giant's blood is a spray across the throw and not one blob" {
    var pool = [_]Particle{.{}} ** FX_MAX;
    const at = v3(0, 1.6, 0);
    const dir = v3(1, 0, 0);
    for ([_]struct { name: []const u8, n: i32, spd: f32 }{
        .{ .name = "light", .n = BLOOD_LIGHT, .spd = BLOOD_SPD_LIGHT },
        .{ .name = "heavy", .n = BLOOD_HEAVY, .spd = BLOOD_SPD_HEAVY },
    }) |b| {
        const m = foe.measureSpray(&pool, BLOOD_SPRAY, at, dir, b.n, b.spd, 1.0, 0xB10D, 5.0 / 60.0, 0);
        std.debug.print("\n  ogre {s}: {d} motes, opens {d:.2} m across the throw, reaches {d:.2} m, {d} stains, all down by {d:.2} s\n", .{ b.name, m.motes, m.open, m.reach, m.splats, m.sink });
        try std.testing.expect(m.open > 0.50);
        try std.testing.expect(m.splats * 2 >= m.motes);
    }
}
