const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const anim = @import("../core/anim.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const elemfx = @import("../gfx/elemfx.zig");
const archermod = @import("archer.zig");
const propart = @import("../props/propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
const BONE_LT = archermod.BONE_LT;

const ROBE = rgba(14, 19, 36, 255);
const ROBE_LT = rgba(22, 28, 48, 255);
const ROBE_DK = rgba(9, 12, 22, 255);
const HEM = rgba(8, 12, 26, 255);
const CORD = rgba(74, 62, 44, 255);

const RIME_ALB = rgba(44, 58, 72, 255);
const RIME_ALB_LT = rgba(62, 80, 96, 255);
const RIME_ALB_HI = rgba(96, 124, 142, 255);
const RIME = mathx.withAlpha(elemfx.sig(.cold).edge, 255);
const RIME_LT = rgba(206, 234, 246, 255);
const FROST_MOTE = elemfx.sig(.cold).core;
const FROST_SHARD = rgba(168, 208, 228, 240);
const FROST_COOL = elemfx.sig(.cold).cool;
const RAISE_GLOW = rgba(236, 198, 104, 200);

const DUST = foe.DUST;
const CHIP_SPRAY = archermod.boneChips(1.0);

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
const STAFF = heromod.HELD;

const H: f32 = heromod.H;

pub const SCALE = (H + 1.05) / H;
const HIP_HALF = heromod.HIP_HALF * 0.60;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.64;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
/// His feet are the archer's feet, and `footMesh` is what a sole patch is measured off.
const solePatches = archermod.solePatches;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;

const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;
const GRIP = v3(0, FIST_Y, FIST_Z);

pub var AGGRO_R: f32 = 26.0;
const TURN_RATE = 4.6;
const WALK_SPEED = heromod.WALK_SPEED_BANK * 1.18;
const SPEED = 1.0;
const BODY_R = 0.34;
pub var SOULS: u32 = 520;

const HP_MAX: f32 = 84.0;
/// **ALMOST NONE.** Under the hero's light poke (10 poise), so ANYTHING that lands staggers it.
const POISE_MAX: f32 = 5.0;
const STANCE_MAX: f32 = 34.0;

const RESISTS = combat.resists(.{ .fire = -35, .cold = 75, .chaos = 45 });

const DEATH_DUR = archermod.DEATH_DUR;
const DISS_DUR = archermod.DISS_DUR;
const SHOVE_DECAY = 7.0;
const A_PROT = 2.6;

pub const RAISE_R: f32 = 11.0;
pub const RAISE_WIND: f32 = 1.90;
const RAISE_DUR: f32 = 0.42;
const RAISE_RECOVER: f32 = 1.15;
const RAISE_CD: f32 = 7.5;
pub const RAISE_HP_FRAC: f32 = 0.55;
pub const RAISE_MATCH_R: f32 = 1.2;

const FROST_HIT_BANK = combat.Hit{ .poise = 18, .stance = 8, .elem = combat.elems(.{ .cold = 38 }) };
pub var FROST_HIT = FROST_HIT_BANK;
pub const FROST_R: f32 = 2.4;
/// The cast — the staff comes up and the hand goes out over the mark. PUBLIC because the harness aims a beat with it (`shots.FROST_TELL_AT`).
pub const FROST_WIND: f32 = 0.72;
const FROST_CAST_DUR: f32 = 0.30;
const FROST_RECOVER: f32 = 0.70;
/// AND IT GREW WITH THE CASTER: the ring lands at `FROST_R * SCALE`, so a taller necromancer widened it from 3.80 m to 4.16 m of ground to clear. 2.4 m/s of walking over 2.7 s clears 4.59 m.
pub const FROST_FUSE: f32 = 2.70;
const FROST_CD: f32 = 4.2;
/// How far up off the mark the burst can reach, in ABSOLUTE metres — the ring's radius grows with the caster, its height does not, because what it has to reach is the hero.
const FROST_WALL_H: f32 = 2.10;
const FROST_R_MIN: f32 = 3.0;
const FROST_R_MAX: f32 = 18.0;

comptime {
    // The ring lands centred on him, so he must clear its radius plus his own footprint. MEASURED AT THE SCALE IT IS DRAWN AT — asserting the bare `FROST_R` would pass on a ring a third wider.
    std.debug.assert(FROST_FUSE * 1.7 > FROST_R * SCALE + foe.HERO_R);
    std.debug.assert(FROST_WIND >= foe.TELL_MIN);
    std.debug.assert(RAISE_WIND > FROST_WIND + FROST_CAST_DUR);
    std.debug.assert(RAISE_CD > RAISE_WIND + RAISE_DUR + RAISE_RECOVER);
    std.debug.assert(FROST_HIT_BANK.dmg == 0 and FROST_HIT_BANK.elem.at(.cold) > 0);
    std.debug.assert(RAISE_R > FROST_R_MIN);
    std.debug.assert(WANT_MIN >= FROST_R_MIN and WANT_MAX <= FROST_R_MAX);
    std.debug.assert(WANT_MIN < WANT_MAX);
    std.debug.assert(WANT_MIN > FROST_R * SCALE);
}

/// Sized by ARITHMETIC over the worst FRAME, not over the biggest burst: the fuse runs on its own clock, so the ring going off (60) lands on the creep it has been laying the whole 2.70 s (22/s at a 1.0 s life).
const NPART = 144;
const RAISE_BLOOM: u32 = 40;
const FROST_BLOOM: u32 = 30;
const FROST_SHARDS: u32 = 60;
const CREEP_RATE: f32 = 22.0;
const CREEP_LIFE_HI: f32 = 1.00;
const CHIP_LIGHT: u32 = 11;
const CHIP_HEAVY: u32 = 18;
const CHIP_DEATH: u32 = 20;
comptime {
    std.debug.assert(@as(f32, NPART) >= CREEP_RATE * CREEP_LIFE_HI + @as(f32, @floatFromInt(FROST_SHARDS +
        @as(u32, @intCast(foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH))) + foe.WOUND_PARTS)));
    std.debug.assert(RAISE_BLOOM <= foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH) and FROST_BLOOM < NPART);
}

const HEM_DRAG = 15.0;
const HEM_EASE = 6.5;
const HEM_SETTLE = 3.4;
const HEM_SWAY = 2.2;


/// THE POSE IS A TARGET, NOT THE OUTPUT — eleven channels chased by one bank, ordered ROOT FIRST so the mass flows trunk -> shoulder -> head -> elbow -> hand and the pole arrives last.
const CH = 11;
const C_LEAN = 0;
const C_TWIST = 1;
const C_SSH = 2;
const C_CSH = 3;
const C_HEAD = 4;
const C_HYAW = 5;
const C_SEL = 6;
const C_CEL = 7;
const C_SABD = 8;
const C_CABD = 9;
const C_TILT = 10;

const P = struct {
    lean: f32 = 6.0,
    twist: f32 = 0,
    staffSh: f32 = STAFF_CARRY_SH,
    castSh: f32 = FREE_CARRY_SH,
    headPitch: f32 = 4.0,
    headYaw: f32 = 0,
    staffEl: f32 = STAFF_CARRY_EL,
    castEl: f32 = FREE_CARRY_EL,
    staffAbd: f32 = STAFF_CARRY_ABD,
    castAbd: f32 = FREE_CARRY_ABD,
    staffTilt: f32 = STAFF_CARRY_TILT,

    pub fn chan(self: P) [CH]f32 {
        return .{ self.lean, self.twist, self.staffSh, self.castSh, self.headPitch, self.headYaw, self.staffEl, self.castEl, self.staffAbd, self.castAbd, self.staffTilt };
    }
};
const Poser = anim.Pose(P);
const PK = Poser.PoseKey;
const CARRY = P{};
const CARRY_CH = CARRY.chan();

const POSE_STIFF: f32 = 560.0;
const POSE_ZETA: f32 = 0.60;
const POSE_FALL: f32 = 0.945;

/// A counter-move before the gather: the trunk goes the OTHER way first, or the gather starts from nothing.
const RAISE_ANTIC = P{ .lean = 12, .twist = 6, .staffSh = -22, .castSh = 4, .headPitch = 12, .headYaw = 4, .staffEl = 32, .castEl = 16, .staffAbd = 12, .castAbd = 4, .staffTilt = 171.5 };
const RAISE_DEEP = P{ .lean = -27, .twist = -31, .staffSh = 7, .castSh = -154, .headPitch = 30, .headYaw = -17, .staffEl = 10, .castEl = 28, .staffAbd = 8, .castAbd = 38, .staffTilt = 140 };
const RAISE_HELD = P{ .lean = RAISE_LEAN, .twist = RAISE_TWIST, .staffSh = RAISE_STAFF_SH, .castSh = RAISE_FREE_SH, .headPitch = RAISE_HEAD, .headYaw = RAISE_HEAD_YAW, .staffEl = RAISE_STAFF_EL, .castEl = RAISE_FREE_EL, .staffAbd = RAISE_STAFF_ABD, .castAbd = RAISE_FREE_ABD, .staffTilt = RAISE_STAFF_TILT };
const RAISE_LOAD = P{ .lean = -26, .twist = -29, .staffSh = 4, .castSh = -150, .headPitch = 29, .headYaw = -16, .staffEl = 11, .castEl = 27, .staffAbd = 8, .castAbd = 36, .staffTilt = 142 };
const RAISE_THROW = P{ .lean = RAISE_THROW_LEAN, .twist = -RAISE_TWIST * 0.4, .staffSh = RAISE_STAFF_SH, .castSh = RAISE_THROW_SH, .headPitch = RAISE_HEAD + 12.0, .headYaw = -6, .staffEl = RAISE_STAFF_EL, .castEl = RAISE_THROW_EL, .staffAbd = RAISE_STAFF_ABD, .castAbd = RAISE_THROW_ABD, .staffTilt = RAISE_THROW_TILT };

const FROST_ANTIC = P{ .lean = 10, .twist = 5, .staffSh = -8, .castSh = 2, .headPitch = 8, .headYaw = 3, .staffEl = 30, .castEl = 16, .staffAbd = 8, .castAbd = 4, .staffTilt = 169.5 };
const FROST_DEEP = P{ .lean = -17, .twist = -22, .staffSh = -80, .castSh = -94, .headPitch = -11, .headYaw = -2, .staffEl = 37, .castEl = 71, .staffAbd = 18, .castAbd = 29, .staffTilt = 128 };
const FROST_HELD = P{ .lean = FROST_LEAN, .twist = FROST_TWIST, .staffSh = FROST_STAFF_SH, .castSh = FROST_FREE_SH, .headPitch = -8, .headYaw = 0, .staffEl = FROST_STAFF_EL, .castEl = FROST_FREE_EL, .staffAbd = FROST_STAFF_ABD, .castAbd = FROST_FREE_ABD, .staffTilt = FROST_STAFF_TILT };
const FROST_LOAD = P{ .lean = -16, .twist = -20, .staffSh = -78, .castSh = -92, .headPitch = -10, .headYaw = -1, .staffEl = 36, .castEl = 69, .staffAbd = 17, .castAbd = 28, .staffTilt = 129 };
const FROST_THROW = P{ .lean = FROST_THROW_LEAN, .twist = -FROST_TWIST * 0.5, .staffSh = FROST_STAFF_SH, .castSh = FROST_THROW_SH, .headPitch = 16, .headYaw = 0, .staffEl = FROST_STAFF_EL, .castEl = FROST_THROW_EL, .staffAbd = FROST_STAFF_ABD, .castAbd = FROST_THROW_ABD, .staffTilt = FROST_THROW_TILT };

/// PAST the rest and back through it: a recovery that glides onto carry reads weightless.
const PAST = P{ .lean = -4, .twist = 5, .staffSh = -22, .castSh = -18, .headPitch = -6, .headYaw = 3, .staffEl = 34, .castEl = 30, .staffAbd = 13, .castAbd = 11, .staffTilt = 171.5 };
const REBOUND = P{ .lean = 11, .twist = -2, .staffSh = -9, .castSh = 0, .headPitch = 9, .headYaw = -1, .staffEl = 22, .castEl = 18, .staffAbd = 7, .castAbd = 5, .staffTilt = 161.5 };

const RECOIL = P{ .lean = -30, .twist = 16, .staffSh = -78, .castSh = -70, .headPitch = -42, .headYaw = 14, .staffEl = 40, .castEl = 44, .staffAbd = 20, .castAbd = 24, .staffTilt = 179 };
const RECOIL_PAST = P{ .lean = 16, .twist = -6, .staffSh = 4, .castSh = 10, .headPitch = 18, .headYaw = -5, .staffEl = 18, .castEl = 16, .staffAbd = 5, .castAbd = 3, .staffTilt = 157.5 };
const LIMP = P{ .lean = 20, .twist = 6, .staffSh = 20, .castSh = 24, .headPitch = 24, .headYaw = 8, .staffEl = 9, .castEl = 8, .staffAbd = 4, .castAbd = 3, .staffTilt = 161.5 };

const RAISE_WIND_KEYS = [_]PK{
    .{ .t = 0.00, .p = CARRY },
    .{ .t = 0.14, .p = RAISE_ANTIC, .ease = .decel },
    .{ .t = 0.50, .p = RAISE_DEEP, .ease = .accel },
    .{ .t = 0.66, .p = RAISE_HELD, .ease = .decel },
    // THE BAIT IS THE FLAT PART. A held pose that creeps while it waits reads as the cast already starting.
    .{ .t = 1.00, .p = RAISE_HELD, .ease = .linear },
};
const RAISE_UP_KEYS = [_]PK{
    .{ .t = 0.00, .p = RAISE_HELD },
    .{ .t = 0.22, .p = RAISE_LOAD, .ease = .decel },
    .{ .t = 0.78, .p = RAISE_THROW, .ease = .accel },
    .{ .t = 1.00, .p = RAISE_THROW, .ease = .linear },
};
const RAISE_RECOVER_KEYS = [_]PK{
    .{ .t = 0.00, .p = RAISE_THROW },
    .{ .t = 0.34, .p = PAST, .ease = .decel },
    .{ .t = 0.66, .p = REBOUND, .ease = .smooth },
    .{ .t = 1.00, .p = CARRY, .ease = .smooth },
};
const FROST_WIND_KEYS = [_]PK{
    .{ .t = 0.00, .p = CARRY },
    .{ .t = 0.12, .p = FROST_ANTIC, .ease = .decel },
    .{ .t = 0.54, .p = FROST_DEEP, .ease = .accel },
    .{ .t = 0.72, .p = FROST_HELD, .ease = .decel },
    .{ .t = 1.00, .p = FROST_HELD, .ease = .linear },
};
const FROST_CAST_KEYS = [_]PK{
    .{ .t = 0.00, .p = FROST_HELD },
    .{ .t = 0.20, .p = FROST_LOAD, .ease = .decel },
    .{ .t = 0.74, .p = FROST_THROW, .ease = .accel },
    .{ .t = 1.00, .p = FROST_THROW, .ease = .linear },
};
const FROST_RECOVER_KEYS = [_]PK{
    .{ .t = 0.00, .p = FROST_THROW },
    .{ .t = 0.36, .p = PAST, .ease = .decel },
    .{ .t = 0.68, .p = REBOUND, .ease = .smooth },
    .{ .t = 1.00, .p = CARRY, .ease = .smooth },
};
const STUN_KEYS = [_]PK{
    .{ .t = 0.00, .p = CARRY },
    .{ .t = 0.11, .p = RECOIL, .ease = .accel },
    .{ .t = 0.48, .p = RECOIL_PAST, .ease = .decel },
    .{ .t = 0.76, .p = REBOUND, .ease = .smooth },
    .{ .t = 1.00, .p = CARRY, .ease = .smooth },
};
const DEAD_KEYS = [_]PK{
    .{ .t = 0.00, .p = RECOIL },
    .{ .t = 0.30, .p = LIMP, .ease = .decel },
    .{ .t = 1.00, .p = LIMP, .ease = .linear },
};

/// The knees take up the landing and the blow; the pelvis drops and `legChain` solves the bend under it.
const CROUCH_DROP = 0.085 * H;
/// A COMPRESSION DROPS THE GRIP 0.24 m AND THE FERRULE WITH IT, straight through the turf. The trunk's lean is billed to the tilt for the same reason; so is this.
const CROUCH_TILT: f32 = 48.0;
const LAND_DUR: f32 = 0.32;
const LAND_KEYS = [_]anim.Key{
    .{ .t = 0.00, .v = 0 },
    .{ .t = 0.26, .v = 1.0, .ease = .accel },
    .{ .t = 0.60, .v = -0.30, .ease = .decel },
    .{ .t = 1.00, .v = 0 },
};
const CROUCH_STIFF: f32 = 900.0;
const CROUCH_ZETA: f32 = 0.56;
const STUN_BRACE_HEAVY: f32 = 0.52;
const STUN_BRACE_LIGHT: f32 = 0.26;

const TUCK_STIFF: f32 = 420.0;
const TUCK_ZETA: f32 = 0.85;
/// The last quarter of the arc is where the tuck has to be gone: below it the fold would drive a sole under the floor.
const TUCK_LAND_BAND: f32 = LEAP_UP * 0.25;
const TUCK_HIP: f32 = 54.0;
const TUCK_KNEE: f32 = 92.0;
/// Neither leg tucks the same amount — a matched pair reads as one welded block.
const TUCK_SIDE = [2]f32{ 1.0, 0.82 };

/// The arc's own gravity, so a hop cut short in mid-air falls at the rate the authored hop was already falling at.
const LEAP_GRAV: f32 = 8.0 * LEAP_UP / (LEAP_DUR * LEAP_DUR);

const HEM_STIFF: f32 = HEM_EASE * HEM_SETTLE;
const HEM_ZETA: f32 = HEM_EASE / (2.0 * @sqrt(HEM_EASE * HEM_SETTLE));


const HOP = P{ .lean = -4, .twist = 4, .staffSh = -30, .castSh = -20, .headPitch = -6, .headYaw = 2, .staffEl = 40, .castEl = 34, .staffAbd = 15, .castAbd = 13, .staffTilt = 161.5 };

const BRACE_KEYS = [_]anim.Key{
    .{ .t = 0.00, .v = 0 },
    .{ .t = 0.13, .v = 1.0, .ease = .accel },
    .{ .t = 0.55, .v = 0.35, .ease = .decel },
    .{ .t = 1.00, .v = 0 },
};

/// A light reaction is the heavy one at a fraction of its throw, measured from carry — two hand-tuned tables drift apart.
fn blend(base: [CH]f32, to: [CH]f32, amt: f32) [CH]f32 {
    var c: [CH]f32 = undefined;
    for (&c, base, to) |*o, a, b| o.* = a + (b - a) * amt;
    return c;
}

/// THE BODY AS THE BLADE FINDS IT — ten posed volumes down the whole 2.85 m, because a chest-centred sphere on a body this thin misses the skull and the shins and lands in the air beside the robe.
const Hull = foe.Hull;
const HULL_MID = v3(0, 0.020 * H, 0);
const HULLS = [_]Hull{
    .{ .bone = SKULL, .center = v3(0, 0.014 * H, 0.006 * H), .radii = v3(0.052 * H, 0.080 * H, 0.058 * H) },
    .{ .bone = CHEST, .center = v3(0, 0.018 * H, 0), .radii = v3(0.085 * H, 0.076 * H, 0.062 * H) },
    .{ .bone = SPINE, .center = HULL_MID, .radii = v3(0.080 * H, 0.080 * H, 0.064 * H) },
    .{ .bone = ROOT, .center = v3(0, 0.006 * H, 0), .radii = v3(0.074 * H, 0.076 * H, 0.062 * H) },
    .{ .bone = HIPL, .center = v3(0, -heromod.SEG_THIGH * H * 0.5, 0), .radii = v3(0.047 * H, heromod.SEG_THIGH * H * 0.60, 0.047 * H) },
    .{ .bone = HIPR, .center = v3(0, -heromod.SEG_THIGH * H * 0.5, 0), .radii = v3(0.047 * H, heromod.SEG_THIGH * H * 0.60, 0.047 * H) },
    .{ .bone = KNEEL, .center = v3(0, -heromod.SEG_SHANK * H * 0.5, 0), .radii = v3(0.037 * H, heromod.SEG_SHANK * H * 0.60, 0.037 * H) },
    .{ .bone = KNEER, .center = v3(0, -heromod.SEG_SHANK * H * 0.5, 0), .radii = v3(0.037 * H, heromod.SEG_SHANK * H * 0.60, 0.037 * H) },
    .{ .bone = SHL, .center = v3(0, -heromod.SEG_UPARM * H * 0.5, 0), .radii = v3(0.031 * H, heromod.SEG_UPARM * H * 0.58, 0.031 * H) },
    .{ .bone = SHR, .center = v3(0, -heromod.SEG_UPARM * H * 0.5, 0), .radii = v3(0.031 * H, heromod.SEG_UPARM * H * 0.58, 0.031 * H) },
};

const State = enum { idle, drift, leap, raise_wind, raise_up, frost_wind, frost_cast, recover, stunlight, stunheavy, dead };

const Spent = enum { raise, frost };

/// The recovery's LENGTH and its KEYS are one fact. Split across two switches they drift, and a table sampled
/// against the wrong clock reads as a move that stops halfway.
const Recover = struct { dur: f32, keys: []const PK };
fn recoverOf(spent: Spent) Recover {
    return switch (spent) {
        .raise => .{ .dur = RAISE_RECOVER, .keys = &RAISE_RECOVER_KEYS },
        .frost => .{ .dur = FROST_RECOVER, .keys = &FROST_RECOVER_KEYS },
    };
}

const Choice = enum { raise, frost, keep, hold };
fn classify(dist: f32, hasBody: bool, raiseReady: bool, frostReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (hasBody and raiseReady) return .raise;
    if (frostReady and dist >= FROST_R_MIN and dist <= FROST_R_MAX) return .frost;
    return .keep;
}

const LEAP_R: f32 = 4.2;
const LEAP_DUR: f32 = 0.34;
const LEAP_SPEED: f32 = 4.6;
const LEAP_CD: f32 = 2.2;
const LEAP_UP: f32 = 0.55;

const WANT_MIN: f32 = 8.0;
const WANT_MAX: f32 = 15.0;
const DRIFT_DUR: f32 = 0.9;

pub const Vigil = struct {
    at: ?rl.Vector3 = null,

    pub fn any(self: *const Vigil) bool {
        return self.at != null;
    }
};

const Sigil = struct {
    at: rl.Vector3 = mathx.zero3,
    left: f32 = 0,
    blew: f32 = mathx.LONG_AGO,

    fn live(self: *const Sigil) bool {
        return self.left > 0;
    }
    /// **0 AT THE CAST, 1 AT THE BURST** — what the ring on the ground is drawn off, so the picture and the fuse are one number.
    fn fill(self: *const Sigil) f32 {
        return mathx.clampF(1.0 - self.left / FROST_FUSE, 0, 1);
    }
};

pub const Model = struct {
    bone: [N]rl.Mesh,
    hem: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "necro");
        var bone: [N]rl.Mesh = undefined;
        bone[ROOT] = pelvisMesh();
        bone[SPINE] = abdomenMesh();
        bone[CHEST] = chestMesh();
        bone[NECK] = neckMesh();
        bone[SKULL] = helmMesh();
        bone[HIPL] = thighMesh();
        bone[KNEEL] = shankMesh();
        bone[ANKL] = archermod.footMesh(1.0, 211);
        bone[HIPR] = thighMesh();
        bone[KNEER] = shankMesh();
        bone[ANKR] = archermod.footMesh(-1.0, 214);
        bone[SHL] = sleeveMesh();
        bone[ELL] = forearmMesh();
        bone[WRL] = handMesh();
        bone[SHR] = sleeveMesh();
        bone[ELR] = forearmMesh();
        bone[WRR] = handMesh();
        bone[STAFF] = staffMesh();
        return .{ .bone = bone, .hem = hemMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Necro) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        rl.drawMesh(self.hem, self.mat, k.hemXf());
    }
};

pub const Necro = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    vigil: Vigil = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    raiseCd: f32 = 0,
    frostCd: f32 = 0,
    raised: bool = false,
    raiseAt: rl.Vector3 = mathx.zero3,
    spent: Spent = .frost,
    sigil: Sigil = .{},
    /// A RING WENT INTO THE GROUND THIS FRAME — a one-frame edge, reset at the TOP of `update`. As a window on the fuse's own clock it read true for three frames at 60 fps.
    laid: bool = false,
    heroHit: ?combat.Hit = null,
    hitFrom: rl.Vector3 = mathx.zero3,
    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,
    parried: bool = false,

    posed: [CH]f32 = CARRY_CH,
    bank: anim.SpringBank(CH) = .{},
    crouch: f32 = 0,
    crouchSpring: anim.Spring = .{},
    tuck: f32 = 0,
    tuckSpring: anim.Spring = .{},
    landT: f32 = LAND_DUR,
    hemLean: f32 = 0,
    hemSpring: anim.Spring = .{},

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    leapCd: f32 = 0,
    hop: f32 = 0,
    hopVel: f32 = 0,
    falling: bool = false,
    /// The spell is DUE, not done — held until the incoming blade for this frame has been resolved.
    pendRaise: bool = false,
    pendLay: ?rl.Vector3 = null,
    gatherU: ?f32 = null,
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    sigAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    hemMat: rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Necro {
        var k = Necro{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
        };
        k.rest = REST;
        k.bank.seat(CARRY_CH);
        k.hemSpring.set(0);
        k.fxRng = foe.fxStream(seed, 68041.0, 23);
        k.raiseCd = 0.4 + seed * 1.1;
        k.frostCd = 0.9 + seed * 1.3;
        k.pose();
        return k;
    }

    pub fn centerWorld(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[SPINE], HULL_MID);
    }
    /// THE BROAD PHASE ONLY. It encloses every posed hull; `hullTouches` then decides, so a thin articulated body is neither missed at the skull nor struck in the empty air beside the robe.
    pub fn hurtRadius(self: *const Necro) f32 {
        const center = self.centerWorld();
        var radius: f32 = 0;
        for (HULLS) |hull| {
            const far = mathx.lenV(mathx.subV(foe.markOn(self.xf[hull.bone], hull.center), center)) + @max(hull.radii.x, @max(hull.radii.y, hull.radii.z)) * self.scale;
            radius = @max(radius, far);
        }
        return radius;
    }
    fn hullTouches(self: *const Necro, a: rl.Vector3, b: rl.Vector3, radius: f32) bool {
        for (HULLS) |hull| {
            if (foe.hullTouches(self.xf[hull.bone], hull.center, hull.radii, a, b, radius)) return true;
        }
        return false;
    }
    pub fn bodyR(self: *const Necro) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], archermod.LOCK_AT);
    }
    /// MEASURED OFF THE POSE, not off a stature fraction: a hop, a bow over a corpse and a collapse all move the crown, and a fixed height puts the lock and the camera solve where the body is not.
    pub fn topWorld(self: *const Necro) rl.Vector3 {
        var top = self.centerWorld();
        for (HULLS) |hull| {
            const xf = self.xf[hull.bone];
            const c = foe.markOn(xf, hull.center);
            const r = hull.radii;
            top.y = @max(top.y, c.y + foe.hullHalfY(xf, r));
        }
        return top;
    }
    pub fn alive(self: *const Necro) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Necro) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Necro) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn flashFrac(self: *const Necro) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn airborne(self: *const Necro) bool {
        return self.hop > foe.AIRBORNE_LIFT;
    }
    pub fn soulValue(self: *const Necro) u32 {
        _ = self;
        return SOULS;
    }

    pub fn casting(self: *const Necro) bool {
        return self.state == .raise_wind or self.state == .raise_up;
    }

    fn fdir(self: *const Necro) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Necro, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    pub fn navWant(self: *const Necro, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        if (self.homing) return foe.tetherFor(self);
        return mathx.addV(self.pos, self.moveDir);
    }

    pub fn update(self: *Necro, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.heroHit = null;
        self.laid = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            self.tickSigil(dt, hero);
            return self.heroHit;
        }
        self.justDied = false;
        self.raised = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        // A rooted body still finishes the arc it is already in — held mid-air it would hang there.
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.raiseCd = mathx.maxF(0, self.raiseCd - dt);
        self.frostCd = mathx.maxF(0, self.frostCd - dt);
        self.leapCd = mathx.maxF(0, self.leapCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;
        self.gatherU = null;
        var want = CARRY_CH;
        var wantCrouch: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                _ = foe.postDrive(self, dt, bounds, WALK_SPEED, d, AGGRO_R, TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (self.t >= 0.20) self.decide(d);
            },
            .leap => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                // THE AUTHORED SPEED CURVE, INTEGRATED over the slice of this frame that falls inside the window — sampled instead, a 30 Hz hop travelled a different distance from a 144 Hz one.
                const uWas = mathx.clampF((self.t - dt) / LEAP_DUR, 0, 1);
                const uNow = mathx.clampF(self.t / LEAP_DUR, 0, 1);
                const moved = LEAP_SPEED * LEAP_DUR / std.math.pi * (mathx.cosf(std.math.pi * uWas) - mathx.cosf(std.math.pi * uNow));
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveSpeed = if (dt > 1e-6) moved / dt else 0;
                moveYaw = mathx.headingXZ(way);
                self.hop = LEAP_UP * mathx.sinf(std.math.pi * uNow);
                self.hopVel = LEAP_UP * std.math.pi / LEAP_DUR * mathx.cosf(std.math.pi * uNow);
                want = HOP.chan();
                if (self.t >= LEAP_DUR) {
                    self.hop = 0;
                    self.hopVel = 0;
                    self.falling = false;
                    self.landT = 0;
                    self.decide(d);
                }
            },
            .drift => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = WALK_SPEED * SPEED;
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                if (self.homing and mathx.distXZ(self.pos, foe.tetherFor(self)) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= DRIFT_DUR) self.decide(d);
            },
            .raise_wind => {
                // IT TURNS TO THE BODY IT COMMITTED TO, NOT TO HIM — and that IS the tell. `raiseAt` and never `vigil.at`: the spot is committed at the START of the gather.
                self.faceToward(self.raiseAt, dt);
                const u = mathx.clampF(self.t / RAISE_WIND, 0, 1);
                want = Poser.sample(&RAISE_WIND_KEYS, u);
                self.gatherU = u;
                if (self.t >= RAISE_WIND) self.enter(.raise_up);
            },
            .raise_up => {
                want = Poser.sample(&RAISE_UP_KEYS, mathx.clampF(self.t / RAISE_DUR, 0, 1));
                self.gatherU = 1.0;
                if (self.t >= RAISE_DUR) {
                    self.spent = .raise;
                    self.raiseCd = RAISE_CD;
                    self.pendRaise = true;
                    self.enter(.recover);
                }
            },
            .frost_wind => {
                self.faceToward(hero, dt);
                want = Poser.sample(&FROST_WIND_KEYS, mathx.clampF(self.t / FROST_WIND, 0, 1));
                if (self.t >= FROST_WIND) self.enter(.frost_cast);
            },
            .frost_cast => {
                self.faceToward(hero, dt * 0.4);
                want = Poser.sample(&FROST_CAST_KEYS, mathx.clampF(self.t / FROST_CAST_DUR, 0, 1));
                if (self.t >= FROST_CAST_DUR) {
                    self.spent = .frost;
                    self.frostCd = FROST_CD;
                    self.pendLay = hero;
                    self.enter(.recover);
                }
            },
            .recover => {
                const rec = recoverOf(self.spent);
                want = Poser.sample(rec.keys, mathx.clampF(self.t / rec.dur, 0, 1));
                if (self.t >= rec.dur) self.decide(d);
            },
            .stunlight, .stunheavy => {
                const heavy = self.state == .stunheavy;
                const dur = combat.foeStunDur(heavy);
                const u = mathx.clampF(self.t / dur, 0, 1);
                const amp: f32 = if (heavy) 1.0 else 0.62;
                want = blend(CARRY_CH, Poser.sample(&STUN_KEYS, u), amp);
                wantCrouch = (if (heavy) STUN_BRACE_HEAVY else STUN_BRACE_LIGHT) * anim.keyAt(&BRACE_KEYS, u);
                if (self.t >= dur) self.enter(.idle);
            },
            .dead => {
                want = Poser.sample(&DEAD_KEYS, mathx.clampF(self.t / DEATH_DUR, 0, 1));
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, archermod.DISSOLVE);
            },
        }

        // A HOP CUT SHORT KEEPS ITS HEIGHT AND ITS RISE, then falls under the arc's own gravity — a stagger in flight must not freeze aloft or teleport down.
        if (self.falling) {
            self.hop = mathx.maxF(0, self.hop + self.hopVel * dt - 0.5 * LEAP_GRAV * dt * dt);
            self.hopVel -= LEAP_GRAV * dt;
            if (self.hop <= 0) {
                self.hop = 0;
                self.hopVel = 0;
                self.falling = false;
                self.landT = 0;
            }
        }
        if (self.landT < LAND_DUR) {
            self.landT += dt;
            // WHICHEVER DEMAND IS LARGER, SIGN AND ALL. `maxF` against a floor of 0 clipped the rebound half of the
            // landing curve, so the knees took the drop and then never gave it back.
            const land = anim.keyAt(&LAND_KEYS, mathx.clampF(self.landT / LAND_DUR, 0, 1));
            if (@abs(land) > @abs(wantCrouch)) wantCrouch = land;
        }

        // ONE ADVANCE PER UPDATE. `pose` and `draw` only replay it, so a shot frame cannot walk the simulation on.
        self.posed = want;
        self.bank.chase(&self.posed, POSE_STIFF, POSE_ZETA, POSE_FALL, dt);
        self.crouch = self.crouchSpring.step(wantCrouch, CROUCH_STIFF, CROUCH_ZETA, dt);
        self.tuck = self.tuckSpring.step(if (self.airborne()) 1 else 0, TUCK_STIFF, TUCK_ZETA, dt);

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        if (!self.airborne()) self.footfalls();
        self.tickHem(dt, moveSpeed);
        self.pose();
        self.tickSigil(dt, hero);
        self.tryHit(blade);
        // THE SPELL IS BILLED AFTER THE BLADE IS. A stroke landing on the release frame cancels the raise or the ring it was about to make; it does NOT cancel a ring already in the ground, nor damage due this frame.
        if (self.state != .dead and !self.staggered()) {
            if (self.pendRaise) {
                self.raised = true;
                self.bloom(self.raiseAt, RAISE_BLOOM);
                sfx.world(.shade_gather, self.raiseAt);
            }
            if (self.pendLay) |at| self.lay(at);
        }
        self.pendRaise = false;
        self.pendLay = null;
        // Hand-attached FX are sampled off the pose that was actually drawn this frame — and a cut cast stops
        // gathering on the frame it is cut, not the frame after.
        if (!self.staggered()) {
            if (self.gatherU) |u| self.gather(dt, u);
        }
        return self.heroHit;
    }


    fn tickSigil(self: *Necro, dt: f32, hero: rl.Vector3) void {
        self.sigil.blew = mathx.minF(self.sigil.blew + dt, mathx.LONG_AGO);
        if (!self.sigil.live()) return;
        self.sigil.left -= dt;
        self.creep(dt);
        if (self.sigil.left > 0) return;
        self.sigil.left = 0;
        self.sigil.blew = 0;
        self.burst();
        // XZ ALONE GAVE THE RING UNLIMITED VERTICAL REACH — it billed a hero standing on the deck above it. The blow is the visible ground burst, so the hero's own capsule must overlap that band. `FROST_WALL_H` clears his 1.4 m jump apex on purpose: this is not a move you hop over.
        const at = self.sigil.at;
        const overlaps = hero.y + foe.HERO_LOW <= at.y + FROST_WALL_H and hero.y + foe.HERO_HIGH >= at.y;
        if (overlaps and mathx.distXZ(at, hero) <= FROST_R * self.scale + foe.HERO_R) {
            self.bill(FROST_HIT, at);
        }
    }

    fn bill(self: *Necro, hit: combat.Hit, from: rl.Vector3) void {
        self.heroHit = hit;
        self.hitFrom = from;
        self.leash.noteCombat();
    }

    fn lay(self: *Necro, hero: rl.Vector3) void {
        self.sigil = .{ .at = v3(hero.x, hero.y, hero.z), .left = FROST_FUSE, .blew = mathx.LONG_AGO };
        self.laid = true;
        sfx.world(.wand_cast, self.sigil.at);
        self.mark(FROST_BLOOM);
    }

    fn enter(self: *Necro, s: State) void {
        self.state = s;
        self.t = 0;
        switch (s) {
            .raise_wind => {
                self.raiseAt = self.vigil.at orelse self.pos;
                sfx.world(.shade_reach, self.pos);
            },
            .frost_wind => sfx.world(.wand_charge, self.pos),
            else => {},
        }
    }
    fn enterStun(self: *Necro, s: State) void {
        self.state = s;
        self.t = 0;
        self.homing = false;
        self.falling = self.hop > 0;
    }
    fn enterDeath(self: *Necro) void {
        self.enterStun(.dead);
        self.justDied = true;
    }

    fn decide(self: *Necro, dist: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, foe.tetherFor(self));
            return self.enter(.drift);
        }
        self.homing = false;
        switch (classify(dist, self.vigil.any(), self.raiseCd <= 0, self.frostCd <= 0)) {
            .raise => self.enter(.raise_wind),
            .frost => self.enter(.frost_wind),
            .keep => {
                const f = self.fdir();
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                const out = mathx.scaleV(f, -1.0);
                const lat = mathx.scaleV(mathx.perpXZ(f), side);
                if (dist < LEAP_R and self.leapCd <= 0) {
                    self.leapCd = LEAP_CD;
                    self.moveDir = mathx.normV(mathx.addV(out, mathx.scaleV(lat, 0.35)));
                    return self.enter(.leap);
                }
                self.moveDir = if (dist < WANT_MIN)
                    mathx.normV(mathx.addV(out, mathx.scaleV(lat, 0.5)))
                else if (dist > WANT_MAX)
                    mathx.normV(mathx.addV(f, mathx.scaleV(lat, 0.4)))
                else
                    lat;
                self.enter(.drift);
            },
            .hold => {
                if (foe.headHome(self)) self.enter(.drift) else self.enter(.idle);
            },
        }
    }

    pub fn tryHit(self: *Necro, blade: foe.Blade) void {
        if (self.state == .dead) return;
        if (blade.active and !self.hullTouches(blade.a, blade.b, blade.r) and !self.hullTouches(blade.a0, blade.b0, blade.r)) return;
        const s = foe.reached(self, blade) orelse return;
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 1.5, .heavy = 2.3 });
        self.chips(s.contact, s.dir, if (heavyBlow) CHIP_HEAVY else CHIP_LIGHT, if (heavyBlow) 3.2 else 2.2);
        sfx.world(.bone_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 2.8);
                sfx.world(.bone_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    pub fn debugRaise(self: *Necro, at: rl.Vector3) void {
        self.vigil.at = at;
        self.raiseCd = 0;
        self.enter(.raise_wind);
    }
    pub fn debugFrost(self: *Necro) void {
        self.frostCd = 0;
        self.enter(.frost_wind);
    }
    pub fn debugLay(self: *Necro, hero: rl.Vector3) void {
        self.lay(hero);
    }
    pub fn stagger(self: *Necro, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Necro) void {
        self.enterDeath();
    }


    fn tickHem(self: *Necro, dt: f32, speed: f32) void {
        // THE SAME SPRING, not a hand-rolled Euler step: `1 - HEM_EASE * dt` went negative past 154 ms a frame and the cloth flipped. Cloth is the LAST thing to move, so its stiffness sits far under the body's.
        const want = HEM_DRAG * mathx.clampF(speed / (heromod.WALK_SPEED_BANK * SPEED), 0, 1);
        self.hemLean = self.hemSpring.step(want, HEM_STIFF, HEM_ZETA, dt);
    }

    pub fn hemXf(self: *const Necro) rl.Matrix {
        return self.hemMat;
    }

    fn chainHem(self: *Necro) void {
        const swayLag = HEM_SWAY * mathx.sinf(std.math.tau * self.phase - 0.9) * self.moving;
        self.hemMat = mul(mul(rx(self.hemLean), rz(swayLag)), self.xf[ROOT]);
    }

    pub fn pose(self: *Necro) void {
        if (!foe.posed(self)) return;
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;

        // A braced body walks less: `legChain` only solves the knee under a pelvis it believes is STANDING, and it
        // applies that solve by `1 - m`. Left at a walking `m` the half-applied solve put the soles 2.4 cm under.
        const m = self.moving * (1.0 - dk) * (1.0 - mathx.clampF(self.crouch * 1.7, 0, 1));
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const bob = pel.bob;
        const sway = pel.sway;
        const prot = pel.prot;
        const dip = pel.dip;

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.20 * H, dk);
        const pitchBody = 18.0 * dk;
        const ground = if (dead) collapse else hipY + bob - dip - CROUCH_DROP * self.crouch;
        // The HOP rides on every state's pelvis, death included, or a body killed in flight snaps to the floor.
        const pelvY = ground + self.hop / mathx.maxF(self.scale, 1e-3);
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(9.0 * dk), rx(pitchBody), ry(prot)),
            mul(tr(sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        if (!dead) {
            heromod.legPair(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, HIPL, KNEEL, HIPR, KNEER, solePatches);
        }
        self.poseUpper(&wx, dk, prot);
        if (dead) heromod.deadLegs(&wx, self.rest, dk);
        // The spring gives the tuck its LAG; the hop gives it the ground truth. Spring alone, the knees were still folded a frame after touchdown and drove the soles 4 cm under.
        const fly = self.tuck * mathx.clampF(self.hop / TUCK_LAND_BAND, 0, 1);
        if (fly > 0.001) tuckLegs(&wx, fly, self.pos.y);
        self.xf = wx;
        self.chainHem();
    }

    fn poseUpper(self: *Necro, wx: *[N]rl.Matrix, dk: f32, prot: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 5.0;
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const swayArg = self.elapsed * (0.42 + 0.20 * (0.5 + 0.5 * mathx.sinf(self.seed * 27.3))) + self.seed * 6.28;
        const swy = mathx.sinf(swayArg) * idleAmt;
        const swyLag = mathx.sinf(swayArg - 0.9) * idleAmt;

        const nod = 1.6 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const lean = self.posed[C_LEAN] + 24.0 * dk;
        const twist = self.posed[C_TWIST];
        const headPitch = self.posed[C_HEAD];
        setLocal(wx, SPINE, rest, mul3(
            rx(lean * 0.45 + nod + 0.7 * swy),
            ry(-0.35 * prot + twist * 0.4),
            rz(wonk * 0.5 + 1.0 * swy),
        ));
        setLocal(wx, CHEST, rest, mul3(
            rx(lean * 0.55 + nod * 0.6 + 0.5 * swyLag),
            ry(-0.5 * prot + twist * 0.6),
            rz(-wonk * 0.3 - 0.7 * swyLag),
        ));
        setLocal(wx, NECK, rest, rx(headPitch * 0.35 + 10.0 * dk));
        setLocal(wx, SKULL, rest, mul3(
            rx(headPitch * 0.65 + 18.0 * dk),
            ry(self.posed[C_HYAW] - 0.5 * prot),
            rz(wonk - 1.2 * swyLag - 0.8 * nod),
        ));

        const swing = -11.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const fwdHalf = mathx.maxF(0, mathx.sinf(twoPi * self.phase));
        const castSh = self.posed[C_CSH] + swing - 30.0 * dk + 2.0 * swyLag;
        setLocal(wx, SHL, rest, mul3(rx(-castSh), ry(0), rz(self.posed[C_CABD] + wonk * 0.4)));
        setLocal(wx, ELL, rest, rx(-self.posed[C_CEL] - 14.0 * fwdHalf * m));
        setLocal(wx, WRL, rest, rz(-5.0));

        const plant = mathx.maxF(0, mathx.sinf(twoPi * self.phase + std.math.pi)) * m;
        const staffSh = self.posed[C_SSH] - 7.0 * plant - 26.0 * dk + 1.6 * swy;
        const staffEl = self.posed[C_SEL] - 5.0 * plant;
        setLocal(wx, SHR, rest, mul3(rx(-staffSh), ry(0), rz(-self.posed[C_SABD] - wonk * 0.4)));
        setLocal(wx, ELR, rest, rx(-staffEl));
        setLocal(wx, WRR, rest, rz(4.0));
        // The arm's own rx down this chain is `-(staffSh + staffEl)`; added instead, the pole read out at 93 degrees, flat like a lance.
        // AND IT TURNS ABOUT THE GRIP. `staffFit` pivots on the bone origin, which is the WRIST — 0.09 H above the palm — so every degree of tilt swung the pole out of the hand that was supposed to be holding it.
        const tilt = self.posed[C_TILT] - CROUCH_TILT * self.crouch;
        setLocal(wx, STAFF, rest, mul3(tr(-GRIP.x, -GRIP.y, -GRIP.z), staffFit(tilt - staffSh - staffEl), tr(GRIP.x, GRIP.y, GRIP.z)));
    }

    pub fn draw(self: *const Necro, model: *const Model) void {
        model.draw(self);
    }

    pub fn drawFx(self: *const Necro) void {
        self.drawSigil();
        self.drawGather();
        foe.drawParticles(&self.parts);
    }

    fn drawSigil(self: *const Necro) void {
        const r = FROST_R * self.scale;
        const at = self.sigil.at;
        const y = at.y + MARK_LIFT;
        const grain = RUNE_GRAIN * self.scale;
        if (self.sigil.live()) {
            const f = self.sigil.fill();
            ringOfGrains(v3(at.x, y, at.z), r, grain * GRAIN_RIM, mathx.withAlpha(RIME, 215), RING_DOTS);
            ringOfGrains(v3(at.x, y, at.z), r * RING_INNER, grain * GRAIN_IN, mathx.withAlpha(RIME, mathx.u8f(150.0 + 85.0 * f)), RING_DOTS_IN);
            ringOfGrains(v3(at.x, y, at.z), r * RING_EYE, grain * GRAIN_EYE, mathx.withAlpha(RIME_LT, mathx.u8f(140.0 + 100.0 * f)), RING_DOTS_EYE);
            const march = f * @as(f32, @floatFromInt(RUNE_N));
            const lit = @floor(march);
            var i: i32 = 0;
            while (i < RUNE_N) : (i += 1) {
                const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RUNE_N)) * std.math.tau;
                const fi = @as(f32, @floatFromInt(i));
                const heat: f32 = if (fi < lit) 1.0 else if (fi < lit + 1.0) march - lit else 0.0;
                const col = if (heat > 0.02) RIME_LT else RIME;
                const alpha: f32 = if (heat > 0.02) 170.0 + 85.0 * heat else 150.0;
                runeAt(v3(at.x, y + RUNE_LIFT, at.z), a, r * RUNE_R, grain * (1.0 + 0.5 * heat), mathx.withAlpha(col, mathx.u8f(alpha)));
            }
            return;
        }
        const age = self.sigil.blew;
        if (age >= FROST_BURST_RING) return;
        const u = age / FROST_BURST_RING;
        const fade = (1.0 - u) * (1.0 - u);
        ringOfGrains(v3(at.x, y, at.z), r * (1.0 + 0.52 * u), grain * (GRAIN_RIM + 0.6 * u), mathx.withAlpha(RIME_LT, mathx.u8f(255.0 * fade)), RING_DOTS);
        ringOfGrains(v3(at.x, y, at.z), r * (RING_INNER + 0.78 * u), grain * (GRAIN_IN + 0.5 * u), mathx.withAlpha(RIME_LT, mathx.u8f(235.0 * fade)), RING_DOTS_IN);
        var i: i32 = 0;
        while (i < RUNE_N) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RUNE_N)) * std.math.tau;
            runeAt(v3(at.x, y + RUNE_LIFT, at.z), a, r * RUNE_R * (1.0 + 0.44 * u), grain * (1.5 - 0.6 * u), mathx.withAlpha(RIME_LT, mathx.u8f(255.0 * fade)));
        }
    }

    pub fn sigilLight(self: *const Necro) ?gfx.Light {
        const r = FROST_R * self.scale;
        const at = v3(self.sigil.at.x, self.sigil.at.y + SIGIL_LIT_Y, self.sigil.at.z);
        if (self.sigil.live()) {
            const f = self.sigil.fill();
            return .{
                .pos = at,
                .col = mathx.scaleV(SIGIL_LIT, SIGIL_LIT_LOW + (SIGIL_LIT_HIGH - SIGIL_LIT_LOW) * f),
                .radius = r * SIGIL_LIT_R,
            };
        }
        const age = self.sigil.blew;
        if (age >= SIGIL_LIT_BURST) return null;
        const u = 1.0 - age / SIGIL_LIT_BURST;
        return .{
            .pos = at,
            .col = mathx.scaleV(SIGIL_LIT, SIGIL_LIT_FLASH * u * u),
            .radius = r * SIGIL_LIT_R * (1.0 + 0.45 * (1.0 - u)),
        };
    }

    fn drawGather(self: *const Necro) void {
        const at = self.castPoint();
        switch (self.state) {
            .raise_wind, .raise_up => {
                const f = if (self.state == .raise_up) 1.0 else mathx.smoothstep(0.15, 1.0, self.t / RAISE_WIND);
                rl.drawSphereEx(at, 0.085 * self.scale * (0.4 + 0.6 * f), 7, 9, mathx.withAlpha(RAISE_GLOW, mathx.u8f(210.0 * f)));
            },
            .frost_wind, .frost_cast => {
                const f = if (self.state == .frost_cast) 1.0 else mathx.smoothstep(0.1, 1.0, self.t / FROST_WIND);
                rl.drawSphereEx(at, 0.075 * self.scale * (0.4 + 0.6 * f), 7, 9, mathx.withAlpha(RIME_LT, mathx.u8f(220.0 * f)));
            },
            else => {},
        }
    }

    pub fn castPoint(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[WRL], v3(0, FIST_Y, FIST_Z));
    }
    /// The STAFF hand's fist, which is where the pole is gripped.
    pub fn castPointRight(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[WRR], v3(0, FIST_Y, FIST_Z));
    }
    /// …and THE STAFF, as the segment it occupies — ferrule to head, taken off the SAME path the mesh is built from (the ogre's `clubLowWorld` law). Nothing about where the pole is may be guessed from a yaw.
    pub fn staffSeg(self: *const Necro) [2]rl.Vector3 {
        return .{
            foe.markOn(self.xf[STAFF], STAFF_FOOT),
            foe.markOn(self.xf[STAFF], STAFF_HEAD),
        };
    }


    fn gather(self: *Necro, dt: f32, u: f32) void {
        const emitRate = (10.0 + 26.0 * u);
        const at = self.castPoint();
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.35, 1.0) * 0.55 * self.scale;
            const p = v3(at.x + mathx.cosf(a) * rr, at.y + self.fxRng.range(-0.2, 0.5) * self.scale, at.z + mathx.sinf(a) * rr);
            const life = self.fxRng.range(0.20, 0.34);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = p,
                .v = mathx.scaleV(mathx.subV(at, p), 1.0 / life),
                .life = life,
                .r0 = self.fxRng.range(0.020, 0.042) * self.scale,
                .r1 = 0.004,
                .col = RAISE_GLOW,
                .stretch = 0.030,
                .add = true,
            });
        }
    }

    fn bloom(self: *Necro, at: rl.Vector3, n: u32) void {
        const from = self.fxHead;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 1.0) * 1.15;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, at.y + self.fxRng.range(1.0, 2.2), at.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * -0.5, -self.fxRng.range(1.6, 3.2), mathx.sinf(a) * -0.5),
                .life = self.fxRng.range(0.42, 0.78),
                .r0 = self.fxRng.range(0.05, 0.10),
                .r1 = 0.006,
                .col = RAISE_GLOW,
                .grav = -1.4,
                .stretch = 0.030,
                .add = true,
            });
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    fn mark(self: *Necro, n: u32) void {
        const from = self.fxHead;
        const at = self.sigil.at;
        const r = FROST_R * self.scale;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.1, 1.0) * r;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, at.y + 0.05, at.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * 0.7, self.fxRng.range(0.3, 0.9), mathx.sinf(a) * 0.7),
                .life = self.fxRng.range(0.30, 0.60),
                .r0 = self.fxRng.range(0.03, 0.06) * self.scale,
                .r1 = 0.008,
                .col = FROST_MOTE,
                .col1 = FROST_COOL,
                .grav = 1.4,
                .stretch = 0.020,
                .add = true,
            });
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    fn creep(self: *Necro, dt: f32) void {
        const emitRate = CREEP_RATE;
        var owed = foe.emitDue(&self.sigAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.80, 1.04) * FROST_R * self.scale;
            const from = self.fxHead;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.sigil.at.x + mathx.cosf(a) * rr, self.sigil.at.y + 0.04, self.sigil.at.z + mathx.sinf(a) * rr),
                .v = v3(0, self.fxRng.range(0.55, 1.30), 0),
                .life = self.fxRng.range(0.55, CREEP_LIFE_HI),
                .r0 = self.fxRng.range(0.028, 0.055) * self.scale,
                .r1 = 0.010,
                .col = FROST_MOTE,
                .col1 = FROST_COOL,
                .grav = 0.5,
                .add = true,
            });
            foe.floorBurst(&self.parts, from, self.fxHead, self.sigil.at.y);
        }
    }

    fn burst(self: *Necro) void {
        const from = self.fxHead;
        const at = self.sigil.at;
        const r = FROST_R * self.scale;
        sfx.world(.shade_touch, at);
        var i: u32 = 0;
        while (i < FROST_SHARDS) : (i += 1) {
            const a = self.fxRng.angle();
            const wall = i % 3 != 0;
            const rr = if (wall) self.fxRng.range(0.86, 1.06) * r else self.fxRng.range(0.0, 0.85) * r;
            const s = self.fxRng.range(0.7, 1.0) * 6.2;
            const out: f32 = if (wall) 0.30 else 0.62;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, at.y + MARK_LIFT, at.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * s * out, self.fxRng.range(4.2, 8.4), mathx.sinf(a) * s * out),
                .life = self.fxRng.range(0.46, 0.82),
                .r0 = self.fxRng.range(0.07, 0.15) * self.scale,
                .r1 = 0.016,
                .col = FROST_SHARD,
                .col1 = FROST_COOL,
                .grav = 5.4,
                .stretch = 0.040,
                .bounce = 0.30,
                .add = true,
            });
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    fn chips(self: *Necro, at: rl.Vector3, dir: rl.Vector3, n: u32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, @intCast(n), spd, self.scale, CHIP_SPRAY);
    }

    fn footfalls(self: *Necro) void {
        const ph = self.phase;
        const crossed = @floor(ph * 2.0) != @floor(self.prevPhase * 2.0);
        self.prevPhase = ph;
        if (!crossed or self.moving < 0.25) return;
        sfx.world(.step_soft, self.pos);
        const f = self.fdir();
        var i: u32 = 0;
        while (i < 4) : (i += 1) {
            const a = self.fxRng.angle();
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.30, 0.55);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + self.fxRng.signed() * 0.26 * self.scale, self.pos.y + 0.03, self.pos.z + self.fxRng.signed() * 0.26 * self.scale),
                .v = v3((-f.x * 0.5 + mathx.cosf(a) * 0.35) * B.boost, self.fxRng.range(0.15, 0.5) * B.boost, (-f.z * 0.5 + mathx.sinf(a) * 0.35) * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.05, 0.10) * self.scale,
                .r1 = 0.22 * self.scale,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }
};


/// AN EXTRA ROTATION FOLDED INTO A JOINT, carrying its children with it. The tuck rides ON TOP of `legChain`'s solve rather than replacing it, so the legs do not pop the frame the soles leave the floor — and a rotation cannot change a bone's length.
fn foldInto(wx: *[N]rl.Matrix, joint: usize, kids: []const usize, extra: rl.Matrix) void {
    const was = wx[joint];
    const inv = rl.math.matrixInvert(was);
    wx[joint] = mul(extra, was);
    for (kids) |c| wx[c] = mul(mul(wx[c], inv), wx[joint]);
}

fn tuckLegs(wx: *[N]rl.Matrix, tuck: f32, groundY: f32) void {
    const legs = [_][3]usize{ .{ HIPL, KNEEL, ANKL }, .{ HIPR, KNEER, ANKR } };
    for (legs, TUCK_SIDE, solePatches) |leg, amt, sole| {
        foldInto(wx, leg[0], &.{ leg[1], leg[2] }, rx(-TUCK_HIP * tuck * amt));
        foldInto(wx, leg[1], &.{leg[2]}, rx(TUCK_KNEE * tuck * amt));
        levelSole(wx, sole, groundY);
    }
}

/// FEET DO NOT SINK: level the ANKLE, never lift the BODY. In flight the sole is nowhere near the turf and this is a no-op; on the way down it takes the tuck out of the foot exactly as fast as the floor arrives.
fn levelSole(wx: *[N]rl.Matrix, sole: heromod.SolePatch, groundY: f32) void {
    var pass: u8 = 0;
    while (pass < 4) : (pass += 1) {
        var deepest: f32 = std.math.floatMax(f32);
        var worst = mathx.zero3;
        var worstZ: f32 = 0;
        for ([_]f32{ -sole.halfW, sole.halfW }) |cx| {
            for ([_]f32{ -sole.heel, sole.toe }) |cz| {
                const c = foe.markOn(wx[sole.bone], v3(cx, -sole.drop, cz));
                if (c.y < deepest) {
                    deepest = c.y;
                    worst = c;
                    worstZ = cz;
                }
            }
        }
        if (deepest >= groundY) return;
        const ank = foe.markOn(wx[sole.bone], mathx.zero3);
        const lever = mathx.maxF(0.02, mathx.lenXZ(mathx.subV(worst, ank)));
        const step = mathx.degrees(std.math.asin(mathx.clampF((groundY - deepest) / lever, -1, 1)));
        foldInto(wx, sole.bone, &.{}, rx(if (worstZ > 0) -step else step));
    }
}


// BUILT OUT OF `drawSphereEx` AND NOTHING ELSE. MEASURED: 157 calls at 4x6, ~7.5k CPU-transformed triangles a frame per live sigil, ~23k for three casters.
const RUNE_N: i32 = 14;
const RUNE_R: f32 = 0.89;
const RING_INNER: f32 = 0.78;
const RING_EYE: f32 = 0.18;
const RING_DOTS: i32 = 46;
const RING_DOTS_IN: i32 = @intFromFloat(@as(f32, @floatFromInt(RING_DOTS)) * RING_INNER);
const RING_DOTS_EYE: i32 = 6;
const GRAIN_RIM: f32 = 0.72;
const GRAIN_IN: f32 = 0.58;
const GRAIN_EYE: f32 = 0.55;
const MARK_LIFT: f32 = 0.06;
const RUNE_LIFT: f32 = 0.008;
const RUNE_GRAIN: f32 = 0.078;
const FROST_BURST_RING: f32 = 0.46;

const SIGIL_LIT = mathx.colVec(rgba(48, 138, 242, 255));
const SIGIL_LIT_LOW: f32 = 0.45;
const SIGIL_LIT_HIGH: f32 = 1.55;
const SIGIL_LIT_FLASH: f32 = 4.60;
const SIGIL_LIT_BURST: f32 = 0.40;
const SIGIL_LIT_R: f32 = 1.60;
const SIGIL_LIT_Y: f32 = 0.55;

fn runeAt(at: rl.Vector3, ang: f32, r: f32, size: f32, col: rl.Color) void {
    const ca = mathx.cosf(ang);
    const sa = mathx.sinf(ang);
    var i: i32 = -1;
    while (i <= 1) : (i += 1) {
        const rr = r + @as(f32, @floatFromInt(i)) * size * 0.9;
        rl.drawSphereEx(v3(at.x + ca * rr, at.y, at.z + sa * rr), size * 0.5, 4, 6, col);
    }
    for ([_]f32{ -1.0, 1.0 }) |s| {
        rl.drawSphereEx(
            v3(at.x + ca * r - sa * s * size * 0.95, at.y, at.z + sa * r + ca * s * size * 0.95),
            size * 0.42,
            4,
            6,
            col,
        );
    }
}

fn ringOfGrains(at: rl.Vector3, r: f32, size: f32, col: rl.Color, n: i32) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * std.math.tau;
        rl.drawSphereEx(v3(at.x + mathx.cosf(a) * r, at.y, at.z + mathx.sinf(a) * r), size, 4, 6, col);
    }
}


const STAFF_CARRY_SH = -14.0;
/// POSITIVE flex — negated at the joint (`rx(-staffEl)`), unlike the knight's and the ogre's, which are raw.
const STAFF_CARRY_EL = 26.0;
const STAFF_CARRY_ABD = 9.0;
const STAFF_CARRY_TILT = 165.5;

const FREE_CARRY_SH = -6.0;
const FREE_CARRY_EL = 22.0;
const FREE_CARRY_ABD = 7.0;

const RAISE_STAFF_SH = 2.0;
const RAISE_STAFF_EL = 12.0;
const RAISE_STAFF_ABD = 8.0;
/// THE TRUNK IS NOT BILLED BY THE FIT, ONLY THE ARM IS — so a pose that arches the spine pays for it here. `RAISE_LEAN` takes the chest back 22 degrees and the staff inherits every one of them.
const RAISE_STAFF_TILT = 144.0;
const RAISE_FREE_SH = -142.0;
const RAISE_FREE_EL = 26.0;
const RAISE_FREE_ABD = 34.0;
const RAISE_LEAN = -22.0;
const RAISE_TWIST = -26.0;
const RAISE_HEAD = 26.0;
const RAISE_HEAD_YAW = -14.0;
const RAISE_THROW_SH = 74.0;
const RAISE_THROW_EL = 10.0;
const RAISE_THROW_ABD = -8.0;
const RAISE_THROW_LEAN = 30.0;
/// `staffTilt` IS 180-IS-PLUMB and the fit bills the ARM, never the TRUNK — so a throw that pitches the trunk 52 degrees must pay for those degrees HERE or the planted pole swings out flat. Measured world lean lands at ~14 degrees, between carry's 16 and the gather's 9.
const RAISE_THROW_TILT = 189.5;

const FROST_STAFF_SH = -74.0;
const FROST_STAFF_EL = 34.0;
const FROST_STAFF_ABD = 16.0;
const FROST_STAFF_TILT = 131.0;
const FROST_FREE_SH = -86.0;
const FROST_FREE_EL = 66.0;
const FROST_FREE_ABD = 26.0;
const FROST_LEAN = -14.0;
const FROST_TWIST = -18.0;
const FROST_THROW_SH = 58.0;
const FROST_THROW_EL = 8.0;
const FROST_THROW_ABD = -6.0;
const FROST_THROW_LEAN = 24.0;
const FROST_THROW_TILT = 159.5;


const staffFit = heromod.staffFit;

// BOTH ENDS ARE SOLVED AGAINST THE BODY, not chosen: the fist rides at `rest[WRR].y` = 0.485-H, which on this rig is 1.17 m off the ground.
const STAFF_UP = 0.59 * H; // grip -> the head, landing ~2.97 m: a hand over the 2.82 m crown
const STAFF_DOWN = 0.46 * H; // ...and down past the grip to the ferrule, landing ~0.02 m: on the ground
const STAFF_SEGS = 9;
const STAFF_CURL = 0.042;

/// ONE PATH, and everything about the pole is measured off it — the mesh, the grip anchor and `staffSeg`. Generated then TRANSLATED so its arc-length grip sits exactly on `(0, FIST_Y, FIST_Z)`; a curve authored straight off nominal endpoints drifts away from the fist.
fn staffPath() [STAFF_SEGS + 1]rl.Vector3 {
    var rng = mathx.Rng.init(4409);
    var p: [STAFF_SEGS + 1]rl.Vector3 = undefined;
    const segs: f32 = @floatFromInt(STAFF_SEGS);
    const seg = (STAFF_UP + STAFF_DOWN) / segs;
    p[0] = v3(0, -STAFF_DOWN, 0);
    var lean: f32 = -STAFF_CURL * segs * 0.5;
    var i: usize = 1;
    while (i <= STAFF_SEGS) : (i += 1) {
        lean += STAFF_CURL;
        const wob = rng.range(-0.008, 0.008) * H;
        // The step is `seg` of ARC, not `seg` of HEIGHT: stepping in y made a curved pole LONGER than the 2.00 m of wood it is supposed to be, and pushed its head 0.41 m over the crown.
        const dir = mathx.normV(v3(mathx.sinf(lean) * 0.42, 1, mathx.cosf(lean * 0.7) * 0.10));
        p[i] = mathx.addV(p[i - 1], mathx.addV(mathx.scaleV(dir, seg), v3(wob, 0, wob * 0.5)));
    }
    const grip = alongPath(&p, STAFF_DOWN);
    const off = mathx.subV(GRIP, grip);
    for (&p) |*q| q.* = mathx.addV(q.*, off);
    return p;
}

/// The point `want` metres of ARC along the path from its foot.
fn alongPath(p: []const rl.Vector3, want: f32) rl.Vector3 {
    var run: f32 = 0;
    for (p[0 .. p.len - 1], p[1..]) |a, b| {
        const len = mathx.lenV(mathx.subV(b, a));
        if (run + len >= want) return mathx.lerpV(a, b, if (len > 1e-6) (want - run) / len else 0);
        run += len;
    }
    return p[p.len - 1];
}

const STAFF_PATH = staffPath();
const STAFF_FOOT = STAFF_PATH[0];
const STAFF_HEAD = STAFF_PATH[STAFF_SEGS];

fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(6607);
    const p = STAFF_PATH;

    b.setMat(.bark);
    // ONE WOOD, WEATHERED ALONG ITS LENGTH. Two tones alternated segment by segment banded the shaft like a barber's pole.
    var i: usize = 0;
    while (i < STAFF_SEGS) : (i += 1) {
        const fi: f32 = @floatFromInt(i);
        const k = fi / @as(f32, STAFF_SEGS - 1);
        const ra = (0.0150 - 0.0007 * fi) * H * rng.range(0.95, 1.06);
        const rb = (0.0143 - 0.0007 * fi) * H * rng.range(0.95, 1.06);
        const col = mathx.lerpColor(propart.BARK_OLD, propart.BARK, k * 0.75 + rng.range(-0.05, 0.05));
        b.addCapsule(p[i], p[i + 1], ra, rb, 9, col);
        // A bare joint between two tapers reads as cut pipe.
        if (i > 0) b.addBlob(p[i], v3(ra * 1.14, ra * 1.10, ra * 1.14), 3, 8, mathx.lerpColor(col, propart.BARK_DK, 0.35));
        if (rng.float() < 0.38) {
            const a = rng.angle();
            const out = rng.range(0.030, 0.062) * H;
            const elb = v3(p[i + 1].x + mathx.cosf(a) * out * 0.6, p[i + 1].y + rng.range(0.004, 0.020) * H, p[i + 1].z + mathx.sinf(a) * out * 0.6);
            b.addCapsule(p[i + 1], elb, 0.0075 * H, 0.0062 * H, 7, propart.BARK_DK);
            b.addCapsule(elb, v3(elb.x + mathx.cosf(a) * out * 0.5, elb.y - rng.range(0.014, 0.034) * H, elb.z + mathx.sinf(a) * out * 0.5), 0.0062 * H, 0.0058 * H, 6, propart.TIMBER);
        }
    }
    const head = STAFF_HEAD;
    b.addBlob(v3(head.x, head.y + 0.005 * H, head.z), v3(0.021 * H, 0.019 * H, 0.020 * H), 5, 12, propart.TIMBER);
    b.setMat(.marble);
    b.addBlob(v3(head.x, head.y + 0.033 * H, head.z), v3(0.024 * H, 0.036 * H, 0.022 * H), 4, 11, RIME_ALB_LT);
    b.addBlob(v3(head.x + 0.007 * H, head.y + 0.054 * H, head.z - 0.004 * H), v3(0.011 * H, 0.019 * H, 0.010 * H), 3, 9, RIME_ALB_HI);
    b.addBlob(v3(head.x - 0.010 * H, head.y + 0.040 * H, head.z + 0.006 * H), v3(0.008 * H, 0.012 * H, 0.008 * H), 3, 8, RIME_ALB);
    b.setMat(.steel);
    const foot = STAFF_FOOT;
    const up = mathx.normV(mathx.subV(p[1], foot));
    b.addCapsule(foot, mathx.addV(foot, mathx.scaleV(up, 0.030 * H)), 0.0150 * H, 0.0165 * H, 9, rgba(44, 42, 40, 255));
    b.addDome(foot, mathx.scaleV(up, -1), 0.0150 * H, 9, rgba(44, 42, 40, 255));
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.012 * H, 0), v3(0.072 * H, 0.082 * H, 0.056 * H), 5, 13, ROBE);
    b.addBlob(v3(0, 0.048 * H, 0), v3(0.082 * H, 0.052 * H, 0.060 * H), 5, 13, ROBE_LT);
    // THE YOKE, and without it the arms hang in mid-air: `restHumanoid` puts the shoulder joints at +/-0.117-H while this chest is 0.072-H across. The ONE place this creature may carry width.
    const shx = SHOULDER_HALF * H;
    const shy = (0.818 - 0.760) * H;
    b.addCapsule(v3(-shx, shy, 0), v3(shx, shy, 0), 0.030 * H, 0.030 * H, 10, ROBE);
    b.addBlob(v3(-shx, shy, 0), v3(0.031 * H, 0.031 * H, 0.031 * H), 3, 9, ROBE);
    b.addBlob(v3(shx, shy, 0), v3(0.031 * H, 0.031 * H, 0.031 * H), 3, 9, ROBE);
    // The mantle drapes PAST the waist joint so a bend at the spine cannot open a seam.
    propart.clothInto(&b, &MANTLE_RINGS, 0x9111, ROBE_DK, ROBE, .{ .sides = 22, .fold = 0.030, .ragged = true, .hemLo = -0.016, .hemHi = 0.008, .scale = H, .mix = 0.55 });
    b.addCapsule(v3(-0.088 * H, 0.052 * H, -0.014 * H), v3(-0.070 * H, -0.088 * H, -0.040 * H), 0.030 * H, 0.038 * H, 9, ROBE_DK);
    return b.toMesh();
}

const MANTLE_RINGS = [_][5]f32{
    .{ 0, -0.034, -0.002, 0.090, 0.073 },
    .{ 0, 0.006, -0.001, 0.086, 0.070 },
    .{ 0, 0.038, 0, 0.101, 0.076 },
    // Wide enough to carry the yoke: `restHumanoid` hangs the shoulders at 0.096 H and the capsule adds 0.030 on top of that.
    .{ 0, 0.058, 0.001, 0.132, 0.082 },
    .{ 0, 0.078, 0.002, 0.108, 0.068 },
};

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.066 * H, 0.086 * H, 0.055 * H), 5, 12, ROBE);
    b.addBlob(v3(0, 0.048 * H, 0), v3(0.070 * H, 0.056 * H, 0.057 * H), 5, 11, ROBE);
    propart.clothInto(&b, &WAIST_RINGS, 0x9222, ROBE_DK, ROBE, .{ .sides = 24, .fold = 0.030, .scale = H, .mix = 0.5 });
    b.setMat(.leather);
    b.addCapsule(v3(-0.080 * H, -0.020 * H, 0), v3(0.080 * H, -0.024 * H, 0), 0.011 * H, 0.011 * H, 8, CORD);
    b.addCapsule(v3(0.048 * H, -0.026 * H, 0.068 * H), v3(0.058 * H, -0.120 * H, 0.074 * H), 0.008 * H, 0.006 * H, 7, CORD);
    b.addCapsule(v3(0.034 * H, -0.026 * H, 0.070 * H), v3(0.026 * H, -0.078 * H, 0.076 * H), 0.007 * H, 0.005 * H, 7, CORD);
    return b.toMesh();
}

const WAIST_RINGS = [_][5]f32{
    .{ 0, -0.098, 0, 0.078, 0.064 },
    .{ 0, -0.050, 0, 0.076, 0.063 },
    .{ 0, 0.010, 0, 0.073, 0.061 },
    .{ 0, 0.060, 0, 0.070, 0.058 },
};

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.060 * H, 0.070 * H, 0.052 * H), 5, 12, ROBE);
    return b.toMesh();
}

/// ONE SURFACE from the waist to the drag, bottom row first. `-0.560` is BELOW the sole plane on purpose: that is the drag, and a hem stopping at the ankle is a dress. The lower rows also trail BACK, which is what the dragging is.
const HEM_RINGS = [_][5]f32{
    .{ 0.006, -0.560, -0.028, 0.126, 0.120 },
    .{ 0.005, -0.470, -0.022, 0.118, 0.112 },
    .{ 0.004, -0.360, -0.016, 0.105, 0.099 },
    .{ 0.003, -0.250, -0.011, 0.091, 0.086 },
    .{ 0.002, -0.150, -0.006, 0.079, 0.075 },
    .{ 0.001, -0.060, -0.002, 0.068, 0.065 },
    .{ 0, 0.006, 0, 0.058, 0.055 },
    .{ 0, 0.048, 0, 0.050, 0.048 },
};

fn hemMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(7717);
    b.setMat(.cloth);
    propart.clothInto(&b, &HEM_RINGS, 0x7717, HEM, ROBE, .{ .sides = 26, .fold = 0.032, .ragged = true, .hemLo = -0.026, .hemHi = 0.014, .scale = H, .mix = 0.35 });
    b.setMat(.marble);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const lift = rng.range(0.006, 0.052);
        const ring = hemRingAt(HEM_BOTTOM + lift);
        b.addBlob(
            v3((ring[0] + mathx.cosf(a) * ring[3] * 0.90) * H, (HEM_BOTTOM + lift) * H, (ring[2] + mathx.sinf(a) * ring[4] * 0.90) * H),
            v3(rng.range(0.010, 0.022) * H, rng.range(0.006, 0.016) * H, rng.range(0.008, 0.018) * H),
            3,
            8,
            if (rng.float() < 0.4) RIME_ALB_LT else RIME_ALB,
        );
    }
    return b.toMesh();
}

const HEM_BOTTOM = HEM_RINGS[0][1];

/// The hem's own profile at a height, so relief sits ON the surface instead of beside it.
fn hemRingAt(y: f32) [5]f32 {
    for (HEM_RINGS[0 .. HEM_RINGS.len - 1], HEM_RINGS[1..]) |lo, hi| {
        if (y > hi[1]) continue;
        const span = hi[1] - lo[1];
        const f = if (span > 1e-6) mathx.clampF((y - lo[1]) / span, 0, 1) else 0;
        var out: [5]f32 = undefined;
        for (&out, lo, hi) |*o, a, c| o.* = a + (c - a) * f;
        return out;
    }
    return HEM_RINGS[HEM_RINGS.len - 1];
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const fi: f32 = @floatFromInt(i);
        const y = fi * 0.011 * H;
        b.addBlob(v3(0, y, -0.002 * H), v3(0.014 * H, 0.008 * H, 0.014 * H), 4, 10, mathx.lerpColor(BONE_DK, BONE, fi / 4.0));
    }
    return b.toMesh();
}

fn helmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(5153);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.014 * H, 0.002 * H), v3(0.046 * H, 0.052 * H, 0.052 * H), 7, 16, BONE_DK);
    b.addBlob(v3(0.002 * H, 0.026 * H, 0), v3(0.050 * H, 0.046 * H, 0.054 * H), 7, 16, BONE);
    b.addCapsule(
        v3(-0.042 * H, 0.014 * H, 0.036 * H),
        v3(0.042 * H, 0.016 * H, 0.036 * H),
        0.013 * H,
        0.012 * H,
        10,
        BONE_LT,
    );
    b.addCapsule(v3(0.001 * H, 0.012 * H, 0.044 * H), v3(-0.001 * H, -0.026 * H, 0.040 * H), 0.008 * H, 0.010 * H, 9, BONE_LT);
    for ([_]f32{ -1.0, 1.0 }) |s| {
        const drop = rng.range(0.052, 0.070) * H;
        const jaw = v3(s * 0.036 * H, -drop, 0.024 * H);
        b.addCapsule(v3(s * 0.040 * H, 0.006 * H, 0.020 * H), jaw, 0.014 * H, 0.011 * H, 9, if (s > 0) BONE else BONE_DK);
        b.addBlob(jaw, v3(0.012 * H, 0.011 * H, 0.012 * H), 3, 9, BONE_DK);
    }
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const z = 0.030 * H - @as(f32, @floatFromInt(i)) * 0.016 * H;
        const up = rng.range(0.014, 0.030) * H;
        const root = v3(rng.signed() * 0.003 * H, 0.062 * H, z);
        b.addCapsule(root, v3(rng.signed() * 0.006 * H, 0.062 * H + up, z - 0.006 * H), 0.009 * H, 0.0075 * H, 7, if (rng.float() < 0.5) BONE_LT else BONE);
        b.addBlob(root, v3(0.010 * H, 0.007 * H, 0.010 * H), 3, 7, BONE_DK);
    }
    for ([_]f32{ -1.0, 1.0 }) |s| {
        b.addBlob(
            v3(s * 0.020 * H, -0.002 * H, 0.038 * H),
            v3(0.012 * H, 0.010 * H, 0.008 * H),
            4,
            10,
            rgba(7, 8, 10, 255),
        );
    }
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCapsule(v3(0, 0, 0), v3(0, -heromod.SEG_THIGH * H, 0), 0.044 * H, 0.036 * H, 10, ROBE_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCapsule(v3(0, 0, 0), v3(0, -0.090 * H, 0), 0.034 * H, 0.028 * H, 10, ROBE_DK);
    b.setMat(.plain);
    b.addCapsule(v3(0, -0.085 * H, 0), v3(0, -heromod.SEG_SHANK * H, 0), 0.017 * H, 0.014 * H, 9, BONE_DK);
    return b.toMesh();
}

/// The sleeve is CLOTH, so it is the same folded surface as the robe, bottom row first — its bottom drapes past the elbow joint.
const SLEEVE_RINGS = [_][5]f32{
    .{ 0, -0.204, 0, 0.032, 0.030 },
    .{ 0, -0.150, 0, 0.030, 0.028 },
    .{ 0, -0.090, 0, 0.027, 0.026 },
    .{ 0, -0.030, 0, 0.025, 0.024 },
    .{ 0, 0.006, 0, 0.026, 0.025 },
};

fn sleeveMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.024 * H, 0.026 * H, 0.024 * H), 5, 11, ROBE);
    b.addCapsule(v3(0, 0, 0), v3(0, -heromod.SEG_UPARM * H, 0), 0.021 * H, 0.024 * H, 9, ROBE);
    propart.clothInto(&b, &SLEEVE_RINGS, 0x51EE, ROBE_DK, ROBE_LT, .{ .sides = 18, .fold = 0.045, .ragged = true, .hemLo = -0.014, .hemHi = 0.006, .scale = H, .mix = 0.6 });
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    // The elbow's own mass: two tapers meeting at a bare joint show both their mouths the moment the arm flexes.
    b.addBlob(v3(0, 0, 0), v3(0.028 * H, 0.026 * H, 0.028 * H), 4, 10, ROBE);
    b.addCapsule(v3(0, 0, 0), v3(0, -0.070 * H, 0), 0.025 * H, 0.030 * H, 9, ROBE);
    b.setMat(.plain);
    b.addCapsule(v3(0, -0.062 * H, 0), v3(0, -heromod.SEG_FOREARM * H, 0), 0.012 * H, 0.010 * H, 9, BONE_DK);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(2801);
    b.setMat(.plain);
    // THE CARPUS. The forearm's bones stop AT the wrist joint (y = 0) and the palm rides 0.05-H below and 0.02-H forward of it; without this the hand hung in the gap.
    b.addCapsule(v3(0, 0.006 * H, -0.001 * H), v3(0, FIST_Y + 0.010 * H, FIST_Z * 0.5), 0.0115 * H, 0.0165 * H, 9, BONE_DK);
    b.addBlob(v3(0, FIST_Y + 0.008 * H, FIST_Z * 0.5), v3(0.017 * H, 0.014 * H, 0.015 * H), 4, 10, BONE_DK);
    b.addBlob(v3(0, FIST_Y, FIST_Z), v3(0.019 * H, 0.023 * H, 0.017 * H), 5, 11, BONE);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const x = (-1.5 + @as(f32, @floatFromInt(i))) * 0.009 * H;
        const len = rng.range(0.030, 0.044) * H;
        const knuckle = v3(x, FIST_Y - 0.016 * H, FIST_Z + 0.012 * H);
        const mid = v3(x + rng.signed() * 0.002 * H, knuckle.y - len * 0.6, knuckle.z + 0.008 * H);
        const tip = v3(mid.x, mid.y - len * 0.4, mid.z - 0.004 * H);
        b.addBlob(knuckle, v3(0.0062 * H, 0.0058 * H, 0.0062 * H), 3, 8, BONE_LT);
        b.addCapsule(knuckle, mid, 0.0050 * H, 0.0044 * H, 7, BONE);
        b.addBlob(mid, v3(0.0050 * H, 0.0048 * H, 0.0050 * H), 3, 7, BONE_DK);
        b.addCapsule(mid, tip, 0.0044 * H, 0.0040 * H, 7, BONE_LT);
        b.addBlob(tip, v3(0.0042 * H, 0.0042 * H, 0.0042 * H), 3, 6, BONE_DK);
    }
    const thumbRoot = v3(0.016 * H, FIST_Y - 0.006 * H, FIST_Z + 0.004 * H);
    const thumbTip = v3(0.026 * H, FIST_Y - 0.026 * H, FIST_Z + 0.014 * H);
    b.addBlob(thumbRoot, v3(0.0062 * H, 0.0060 * H, 0.0062 * H), 3, 8, BONE_LT);
    b.addCapsule(thumbRoot, thumbTip, 0.0052 * H, 0.0046 * H, 7, BONE);
    b.addBlob(thumbTip, v3(0.0046 * H, 0.0046 * H, 0.0046 * H), 3, 6, BONE_DK);
    return b.toMesh();
}


const CAP = wf.MAX_PER_KIND;

pub const Rite = struct {
    model: Model,
    band: [CAP]Necro = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Rite {
        return .{ .model = Model.init(shader) };
    }
    pub fn markLights(self: *const Rite, out: []gfx.Light) usize {
        var n: usize = 0;
        for (self.liveConst()) |*x| {
            if (n >= out.len) break;
            if (x.sigilLight()) |l| {
                out[n] = l;
                n += 1;
            }
        }
        return n;
    }

    pub fn live(self: *Rite) []Necro {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Rite) []const Necro {
        return self.band[0..self.n];
    }

    pub fn reset(self: *Rite, m: *const wf.Map) void {
        foe.resetGroup(Necro, &self.band, &self.n, m, .necromancer);
    }
    pub fn setShader(self: *Rite, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Rite, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Rite) void {
        for (self.liveConst()) |*k| k.drawFx();
    }
    pub fn pierce(self: *Rite, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Rite) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Rite) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Rite) u32 {
        return foe.aliveCount(self.liveConst());
    }
    pub fn soulsDropped(self: *const Rite) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn anyLaid(self: *const Rite) bool {
        for (self.liveConst()) |*k| {
            if (k.laid) return true;
        }
        return false;
    }

    pub fn update(self: *Rite, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*k| {
            if (k.update(dt, k.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&blow, h, k.hitFrom, &k.threat);
        }
        return blow;
    }
};


test "TALL AND SKINNY is two dials, and the RATIO is what either of them alone cannot say" {
    const scaffold = heromod.restHumanoid(heromod.HIP_HALF, heromod.SHOULDER_HALF, H);
    try std.testing.expect(SCALE > archermod.SCALE);
    try std.testing.expect(SCALE * H > 2.3);
    try std.testing.expect(REST[SHL].x < scaffold[SHL].x);
    try std.testing.expect(@abs(REST[HIPL].x) < @abs(scaffold[HIPL].x));
    const mySpan = 2.0 * REST[SHL].x * SCALE;
    const archerSpan = 2.0 * scaffold[SHL].x * archermod.SCALE;
    try std.testing.expect(mySpan < archerSpan);
    try std.testing.expect((SCALE * H) / mySpan > (archermod.SCALE * H) / archerSpan);
    try std.testing.expectApproxEqAbs(scaffold[ROOT].y, REST[ROOT].y, 1e-5);
}

test "THE STAFF STANDS UP, ON ITS OWN SIDE, AND ITS FOOT IS ON THE GROUND — measured, not argued" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    var j: u32 = 0;
    while (j < 30) : (j += 1) _ = k.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    const seg = k.staffSeg();
    const foot = seg[0];
    const head = seg[1];
    const crown = k.topWorld().y;
    std.debug.print(
        "\n  necro: crown {d:.2} | staff foot y {d:.2} head y {d:.2} | foot out {d:.2} head out {d:.2} | lean {d:.1} deg\n",
        .{
            crown,
            foot.y,
            head.y,
            mathx.lenXZ(mathx.subV(foot, k.pos)),
            mathx.lenXZ(mathx.subV(head, k.pos)),
            mathx.tiltDeg(foot, head),
        },
    );
    try std.testing.expect(head.y > foot.y);
    try std.testing.expect(foot.y < crown * 0.13);
    try std.testing.expect(mathx.lenXZ(mathx.subV(foot, k.pos)) < crown * 0.36);
    try std.testing.expect(head.y > k.centerWorld().y);
    try std.testing.expect(head.y < crown + 0.20);
    const lean = mathx.tiltDeg(foot, head);
    try std.testing.expect(lean < 35.0);
    const side = mathx.headingDir(k.facing);
    const right = mathx.perpXZ(side);
    const footSide = foot.x * right.x + foot.z * right.z;
    const headSide = head.x * right.x + head.z * right.z;
    try std.testing.expect(footSide * headSide > 0);
}

test "…AND IT STAYS A STAFF THROUGH BOTH CASTS — the trunk's own lean is billed, or it becomes a lance" {
    const at = struct {
        fn lean(k: *Necro) f32 {
            const s = k.staffSeg();
            return mathx.tiltDeg(s[0], s[1]);
        }
    }.lean;
    const dt = 1.0 / 60.0;

    var r = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    r.debugRaise(v3(2, 0, 2));
    var t: f32 = 0;
    while (t < RAISE_WIND * 0.95) : (t += dt) {
        r.vigil.at = v3(2, 0, 2);
        _ = r.update(dt, v3(0, 0, 9), 400, .{});
    }
    const rSeg = r.staffSeg();
    std.debug.print("  necro raise: staff lean {d:.1} deg, ferrule y {d:.2}\n", .{ at(&r), rSeg[0].y });
    try std.testing.expect(rSeg[1].y > rSeg[0].y);
    try std.testing.expect(at(&r) < 34.0);
    try std.testing.expect(rSeg[0].y < 0.45);

    var f = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    f.debugFrost();
    t = 0;
    while (t < FROST_WIND * 0.95) : (t += dt) _ = f.update(dt, v3(0, 0, 9), 400, .{});
    const fSeg = f.staffSeg();
    std.debug.print("  necro frost: staff lean {d:.1} deg, ferrule y {d:.2}\n", .{ at(&f), fSeg[0].y });
    try std.testing.expect(fSeg[1].y > fSeg[0].y);
    // The ORDER is what this pins: bent the right way the arm is pitch 40 and the ferrule 0.47, still clear of the planted raise's 0.31.
    try std.testing.expect(fSeg[0].y > rSeg[0].y + 0.12);
}

test "THE HEM REACHES THE GROUND AND PAST IT — that is what dragging means" {
    const bot = -0.030 * H - REST[ROOT].y;
    try std.testing.expect(bot + REST[ROOT].y < heromod.SOLE_Y);
    try std.testing.expect(bot + REST[ROOT].y < REST[ANKL].y);
}

test "THE HEM IS A SPRING: it lags going out, and it OVERSHOOTS its rest coming back" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt = 1.0 / 60.0;
    k.tickHem(dt, heromod.WALK_SPEED_BANK * SPEED);
    try std.testing.expect(k.hemLean > 0 and k.hemLean < HEM_DRAG * 0.5);
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) k.tickHem(dt, heromod.WALK_SPEED_BANK * SPEED);
    try std.testing.expect(@abs(k.hemLean - HEM_DRAG) < 1.5);
    var least: f32 = 999;
    t = 0;
    while (t < 2.5) : (t += dt) {
        k.tickHem(dt, 0);
        least = mathx.minF(least, k.hemLean);
    }
    try std.testing.expect(least < -0.05);
    try std.testing.expect(@abs(k.hemLean) < 1.0);
}

test "THE RAISE OUTRANKS THE FROST whenever a body is offered, and distance decides the rest" {
    try std.testing.expectEqual(Choice.raise, classify(6.0, true, true, true));
    try std.testing.expectEqual(Choice.raise, classify(16.0, true, true, false));
    try std.testing.expectEqual(Choice.frost, classify(6.0, false, true, true));
    try std.testing.expectEqual(Choice.frost, classify(6.0, true, false, true));
    try std.testing.expectEqual(Choice.keep, classify(FROST_R_MIN - 0.5, false, true, true));
    try std.testing.expectEqual(Choice.keep, classify(FROST_R_MAX + 1.0, false, true, true));
    try std.testing.expectEqual(Choice.keep, classify(9.0, false, false, false));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, true, true, true));
}

test "THE SPOT IS COMMITTED: the sigil does not follow him, and it goes off where it was laid" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const stood = v3(4, 0, 5);
    k.debugLay(stood);
    try std.testing.expect(k.sigil.live());
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(stood, k.sigil.at), 1e-5);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var fired = false;
    var ranAt = mathx.zero3;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        ranAt = v3(stood.x + 40.0 * t, 0, stood.z);
        _ = k.update(dt, ranAt, 400, .{});
        if (k.heroHit != null) fired = true;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(stood, k.sigil.at), 1e-5);
    try std.testing.expect(!fired);
}

test "A WALK CLEARS THE RING and standing still does not — the counter is his feet" {
    const dt = 1.0 / 60.0;
    var stay = Necro.spawn(v3(0, 0, 20), 0, 1.0, 0.2);
    const at = v3(0, 0, 0);
    stay.debugLay(at);
    var hit = false;
    var t: f32 = 0;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        _ = stay.update(dt, at, 400, .{});
        if (stay.heroHit != null) hit = true;
    }
    try std.testing.expect(hit);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(at, stay.hitFrom), 1e-5);

    var walk = Necro.spawn(v3(0, 0, 20), 0, 1.0, 0.2);
    walk.debugLay(at);
    var caught = false;
    t = 0;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        const he = v3(heromod.WALK_SPEED_BANK * t, 0, 0);
        _ = walk.update(dt, he, 400, .{});
        if (walk.heroHit != null) caught = true;
    }
    try std.testing.expect(!caught);
}

test "THE RING BILLS ITS BLOW ONCE, even from a caster that has left the field" {
    var k = Necro.spawn(v3(0, 0, 12), 0, 1.0, 0.2);
    const at = mathx.zero3;
    k.debugLay(at);
    k.debugKill();
    const dt = 1.0 / 60.0;
    var bills: u32 = 0;
    var t: f32 = 0;
    while (t < DEATH_DUR + DISS_DUR + FROST_FUSE + 1.5) : (t += dt) {
        if (k.update(dt, at, 400, .{}) != null) bills += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), bills);
}

test "THE RAISE'S OPENING IS THE LONG ONE, and it stays long past the frame it landed on" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    const hero = v3(0, 0, 9);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < RAISE_WIND + RAISE_DUR + 0.05) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expectEqual(State.recover, k.state);
    var n: u32 = 0;
    while (n < 20) : (n += 1) {
        k.vigil.at = null;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expectEqual(State.recover, k.state);
    try std.testing.expect(RAISE_RECOVER > FROST_RECOVER * 1.5);
    t = 0;
    while (t < RAISE_RECOVER) : (t += dt) {
        k.vigil.at = null;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expect(k.state != State.recover);
}

test "A FUSE LIT IS A ONE-FRAME EDGE — the pad is not struck three times for one cast" {
    var k = Necro.spawn(v3(0, 0, 9), 0, 1.0, 0.2);
    const dt = 1.0 / 60.0;
    k.debugFrost();
    var edges: u32 = 0;
    var t: f32 = 0;
    while (t < FROST_WIND + FROST_CAST_DUR + 0.5) : (t += dt) {
        _ = k.update(dt, mathx.zero3, 400, .{});
        if (k.laid) edges += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), edges);
}

test "THE RING OUTLIVES THE CASTER — killing it after the cast does not un-cast it" {
    var k = Necro.spawn(v3(0, 0, 12), 0, 1.0, 0.2);
    const at = mathx.zero3;
    k.debugLay(at);
    k.debugKill();
    const dt = 1.0 / 60.0;
    var hit = false;
    var t: f32 = 0;
    while (t < DEATH_DUR + DISS_DUR + FROST_FUSE + 0.4) : (t += dt) {
        _ = k.update(dt, at, 400, .{});
        if (k.heroHit != null) hit = true;
    }
    try std.testing.expect(!k.alive());
    try std.testing.expect(hit);
}

test "THE FROST IS THE FIRST COLD IN THE GAME, and it arrives as cold and nothing else" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), FROST_HIT.dmg, 1e-6);
    try std.testing.expect(FROST_HIT.elem.at(.cold) > 0);
    try std.testing.expectApproxEqAbs(FROST_HIT.elem.at(.cold), FROST_HIT.elem.total(), 1e-6);
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(FROST_HIT);
    const quarter = FROST_HIT.elem.at(.cold) * (1.0 - combat.RES_CAP / 100.0);
    try std.testing.expectApproxEqAbs(HP_MAX - quarter, v.hp, 0.01);
    var f = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = f.hit(combat.Hit{ .dmg = 10, .elem = combat.elems(.{ .fire = 5 }) });
    try std.testing.expect(f.hp < HP_MAX - 16.0);
}

test "THE RAISE IS THE LONGEST TELL IT HAS, it is PLANTED for all of it, and it reports rather than acts" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    const hero = v3(0, 0, 9);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    const startedAt = k.pos;
    var t: f32 = 0;
    var raisedOn: f32 = -1;
    while (t < RAISE_WIND + RAISE_DUR + 0.2) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, hero, 400, .{});
        if (k.raised) raisedOn = t;
    }
    try std.testing.expect(raisedOn > RAISE_WIND);
    try std.testing.expect(raisedOn < RAISE_WIND + RAISE_DUR + 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(startedAt, k.pos), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(body, k.raiseAt), 1e-5);
    _ = k.update(dt, hero, 400, .{});
    try std.testing.expect(!k.raised);
}

test "INTERRUPTING THE GATHER SPENDS IT — a staggered necromancer raises nothing" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < RAISE_WIND * 0.8) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
    }
    try std.testing.expect(k.casting());
    k.stagger(true);
    try std.testing.expect(!k.casting());
    var raisedEver = false;
    t = 0;
    while (t < combat.FOE_HEAVY_STUN_DUR + 0.5) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
        if (k.raised) raisedEver = true;
    }
    try std.testing.expect(!raisedEver);
}

test "IT NEVER MELEES, AND IT NEVER CLOSES — it holds the range its ice works at" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const dt = 1.0 / 60.0;
    const near = v3(0, 0, 1.2);
    var t: f32 = 0;
    var closest: f32 = 999;
    while (t < 6.0) : (t += dt) {
        _ = k.update(dt, near, 400, .{});
        closest = mathx.minF(closest, mathx.distXZ(k.pos, near));
    }
    try std.testing.expect(mathx.distXZ(k.pos, near) > 1.2);
    try std.testing.expect(k.heroHit == null or k.sigil.blew < 1.0);
}

test "IT IS FRAIL, AND THE PRICE SAYS IT IS THE PRIORITY TARGET" {
    try std.testing.expect(HP_MAX < 92.0);
    try std.testing.expect(POISE_MAX < 15.0);
    try std.testing.expect(SOULS > 280);
    try std.testing.expect(AGGRO_R > archermod.AGGRO_R);
}

test "A CORPSE IS HELD OPEN WITHIN REACH AND NOWHERE ELSE, so walking the fight away is an answer" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    try std.testing.expect(!k.vigil.any());
    k.vigil.at = v3(3, 0, 3);
    try std.testing.expect(k.vigil.any());
    k.vigil.at = null;
    try std.testing.expect(!k.vigil.any());
    try std.testing.expect(RAISE_R > FROST_R_MIN);
}

test "AN ELBOW BENDS ONE WAY — every cast's flex is FORWARD, and a throw ENDS straighter than it started" {
    inline for (.{ STAFF_CARRY_EL, FREE_CARRY_EL, RAISE_STAFF_EL, RAISE_FREE_EL, RAISE_THROW_EL, FROST_STAFF_EL, FROST_FREE_EL, FROST_THROW_EL }) |v| {
        try std.testing.expect(v >= 0);
    }
    try std.testing.expect(RAISE_THROW_EL < RAISE_FREE_EL);
    try std.testing.expect(FROST_THROW_EL < FROST_FREE_EL);
    std.debug.print("\n  necro free arm: carry {d:.0} -> gather {d:.0} -> throw {d:.0} degrees of flex\n", .{ FREE_CARRY_EL, FROST_FREE_EL, FROST_THROW_EL });
}


const TEST_DTS = [_]f32{ 1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0 };
const TEST_SCALES = [_]f32{ 0.5, 1.0, 1.8 };

fn runFor(k: *Necro, secs: f32, dt: f32, hero: rl.Vector3) void {
    var t: f32 = 0;
    while (t < secs) : (t += dt) _ = k.update(dt, hero, 400, .{});
}

fn boneLen(k: *const Necro, a: usize, b: usize) f32 {
    return mathx.lenV(mathx.subV(foe.markOn(k.xf[a], mathx.zero3), foe.markOn(k.xf[b], mathx.zero3)));
}

fn lowestSole(k: *const Necro) f32 {
    var low: f32 = 1e9;
    for ([_]usize{ ANKL, ANKR }, solePatches) |ank, sole| {
        for ([_]f32{ -sole.halfW, sole.halfW }) |cx| {
            for ([_]f32{ -sole.heel, sole.toe }) |cz| {
                low = mathx.minF(low, foe.markOn(k.xf[ank], v3(cx, -sole.drop, cz)).y);
            }
        }
    }
    return low;
}

test "THE POLE IS ONE PATH: the grip is ON the fist, the reported segment IS the mesh's own ends, and 2.00 m of wood stays 2.00 m of wood" {
    const grip = alongPath(&STAFF_PATH, STAFF_DOWN);
    try std.testing.expectApproxEqAbs(GRIP.x, grip.x, 1e-4);
    try std.testing.expectApproxEqAbs(GRIP.y, grip.y, 1e-4);
    try std.testing.expectApproxEqAbs(GRIP.z, grip.z, 1e-4);

    var arc: f32 = 0;
    for (STAFF_PATH[0 .. STAFF_PATH.len - 1], STAFF_PATH[1..]) |a, b| arc += mathx.lenV(mathx.subV(b, a));
    try std.testing.expectApproxEqAbs(STAFF_UP + STAFF_DOWN, arc, 0.03);
    // The head is a hand over the crown, not half a metre of pole above it.
    try std.testing.expect(mathx.lenV(mathx.subV(STAFF_HEAD, grip)) < mathx.lenV(mathx.subV(grip, STAFF_FOOT)) * 1.6);

    for (TEST_SCALES) |size| {
        var k = Necro.spawn(mathx.zero3, 0, size, 0.4);
        var span: f32 = -1;
        var upper: f32 = -1;
        var fore: f32 = -1;
        for ([_]?rl.Vector3{ null, v3(2, 0, 2) }, 0..) |body, pass| {
            k = Necro.spawn(mathx.zero3, 0, size, 0.4);
            if (pass == 1) k.debugRaise(body.?) else k.debugFrost();
            var t: f32 = 0;
            while (t < 1.2) : (t += 1.0 / 120.0) {
                k.vigil.at = body;
                _ = k.update(1.0 / 120.0, v3(0, 0, 9), 400, .{});
                const seg = k.staffSeg();
                const now = mathx.lenV(mathx.subV(seg[1], seg[0]));
                const up = boneLen(&k, SHR, ELR);
                const fw = boneLen(&k, ELR, WRR);
                if (span < 0) {
                    span = now;
                    upper = up;
                    fore = fw;
                }
                try std.testing.expectApproxEqAbs(span, now, 1e-3);
                try std.testing.expectApproxEqAbs(upper, up, 1e-3);
                try std.testing.expectApproxEqAbs(fore, fw, 1e-3);
                // The grip stays IN the fist: the pole turns about the real grip, never about the wrist origin.
                const held = foe.markOn(k.xf[STAFF], GRIP);
                try std.testing.expect(mathx.lenV(mathx.subV(held, k.castPointRight())) < 0.001 * size);
            }
        }
        std.debug.print("\n  necro x{d:.1}: staff span {d:.3} m, upper arm {d:.3}, forearm {d:.3}\n", .{ size, span, upper, fore });
    }
}

test "THE HOP TRAVELS THE SAME GROUND AT 30, 60 AND 144 Hz, and it is AIRBORNE while it does" {
    var far: f32 = -1;
    for (TEST_DTS) |dt| {
        var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
        k.state = .leap;
        k.t = 0;
        k.moveDir = v3(0, 0, -1);
        var flew = false;
        var peak: f32 = 0;
        var t: f32 = 0;
        while (t < LEAP_DUR + 0.5) : (t += dt) {
            _ = k.update(dt, v3(0, 0, 30), 400, .{});
            if (k.airborne()) flew = true;
            peak = mathx.maxF(peak, k.hop);
        }
        const went = mathx.distXZ(k.pos, mathx.zero3);
        std.debug.print("  necro hop at {d: >5.1} Hz: travelled {d:.4} m, apex {d:.3} m\n", .{ 1.0 / dt, went, peak });
        try std.testing.expect(flew);
        try std.testing.expect(peak > LEAP_UP * 0.9);
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.hop, 1e-5);
        if (far < 0) far = went;
        try std.testing.expectApproxEqAbs(far, went, 0.002);
    }
    // The authored curve's own integral: 2 * speed * duration / pi.
    try std.testing.expectApproxEqAbs(2.0 * LEAP_SPEED * LEAP_DUR / std.math.pi, far, 0.01);
}

test "A LANDING COMPRESSES AND GIVES IT BACK — the knees take the drop, then rise PAST rest" {
    for (TEST_DTS) |dt| {
        var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
        k.state = .leap;
        k.t = 0;
        k.moveDir = v3(0, 0, -1);
        var deepest: f32 = 0;
        var highest: f32 = 0;
        var t: f32 = 0;
        while (t < LEAP_DUR + LAND_DUR + 0.4) : (t += dt) {
            _ = k.update(dt, v3(0, 0, 30), 400, .{});
            if (k.hop > 0) continue;
            deepest = mathx.maxF(deepest, k.crouch);
            highest = mathx.minF(highest, k.crouch);
        }
        std.debug.print("  necro landing at {d: >5.1} Hz: compressed {d:.2}, rebounded to {d:.2}\n", .{ 1.0 / dt, deepest, highest });
        try std.testing.expect(deepest > 0.50);
        // A glide back onto rest reads as weightless: the pelvis must cross it.
        try std.testing.expect(highest < -0.10);
        try std.testing.expect(@abs(k.crouch) < 0.05);
    }
}

test "A HOP CUT SHORT KEEPS ITS HEIGHT AND ITS RISE, then lands — no freeze aloft, no teleport down" {
    for ([_]bool{ false, true }) |kill| {
        for (TEST_DTS) |dt| {
            var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
            k.state = .leap;
            k.t = 0;
            k.moveDir = v3(0, 0, -1);
            runFor(&k, LEAP_DUR * 0.35, dt, v3(0, 0, 30));
            const wasUp = k.hop;
            const wasVel = k.hopVel;
            try std.testing.expect(wasUp > 0.1 and wasVel > 0);
            if (kill) k.debugKill() else k.stagger(true);
            _ = k.update(dt, v3(0, 0, 30), 400, .{});
            try std.testing.expect(k.hop > wasUp - 0.02);
            try std.testing.expect(k.hopVel < wasVel + 1e-3);
            var rose = k.hop;
            var landed = false;
            var t: f32 = 0;
            while (t < 2.0) : (t += dt) {
                _ = k.update(dt, v3(0, 0, 30), 400, .{});
                rose = mathx.maxF(rose, k.hop);
                if (k.hop <= 0) landed = true;
            }
            try std.testing.expect(rose > wasUp);
            try std.testing.expect(landed);
            try std.testing.expectApproxEqAbs(@as(f32, 0), k.hop, 1e-5);
        }
    }
}

test "NOTHING PIERCES THE FLOOR through takeoff, apex, landing, recoil and death — soles, ferrule, hands and skull" {
    for (TEST_SCALES) |size| {
        var k = Necro.spawn(mathx.zero3, 0, size, 0.35);
        k.state = .leap;
        k.t = 0;
        k.moveDir = v3(0, 0, -1);
        var worstSole: f32 = 1e9;
        var deadSole: f32 = 1e9;
        var worstFerrule: f32 = 1e9;
        var worstHand: f32 = 1e9;
        var stage: u32 = 0;
        var t: f32 = 0;
        while (t < 5.5) : (t += 1.0 / 120.0) {
            _ = k.update(1.0 / 120.0, v3(0, 0, 30), 400, .{});
            if (stage == 0 and t > 0.9) {
                k.stagger(true);
                stage = 1;
            } else if (stage == 1 and t > 2.4) {
                k.debugKill();
                stage = 2;
            }
            if (k.fade > 0.85) break;
            if (k.fade > 0.001) continue; // the dissolve sinks the body into the turf on purpose
            if (k.dying()) {
                deadSole = mathx.minF(deadSole, lowestSole(&k));
                continue;
            }
            worstSole = mathx.minF(worstSole, lowestSole(&k));
            worstFerrule = mathx.minF(worstFerrule, k.staffSeg()[0].y);
            worstHand = mathx.minF(worstHand, mathx.minF(k.castPoint().y, k.castPointRight().y));
            try std.testing.expect(k.lockPoint().y > -0.05 * size);
        }
        std.debug.print("  necro x{d:.1}: worst sole {d: >6.3}, ferrule {d: >6.3}, hand {d: >6.3} | collapsing corpse sole {d: >6.3}\n", .{ size, worstSole, worstFerrule, worstHand, deadSole });
        try std.testing.expect(worstSole > -0.02 * size);
        try std.testing.expect(worstFerrule > -0.02 * size);
        try std.testing.expect(worstHand > 0.05 * size);
    }
}

test "A BLADE ON THE RELEASE FRAME CANCELS THE SPELL, and spends the cooldown all the same" {
    const cases = [_]bool{ true, false };
    for (cases) |isRaise| {
        var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
        const body = v3(2, 0, 2);
        const hero = v3(0, 0, 9);
        if (isRaise) k.debugRaise(body) else k.debugFrost();
        const endState: State = if (isRaise) .raise_up else .frost_cast;
        const endDur: f32 = if (isRaise) RAISE_DUR else FROST_CAST_DUR;
        const dt = 1.0 / 60.0;
        var guard: u32 = 0;
        while (guard < 1000) : (guard += 1) {
            if (k.state == endState and k.t + dt >= endDur) break;
            k.vigil.at = body;
            _ = k.update(dt, hero, 400, .{});
        }
        try std.testing.expect(guard < 1000);
        // ONE more frame — the one the event is due on — with a stroke landing in it.
        const at = k.centerWorld();
        const blade = foe.Blade{ .active = true, .a = at, .b = at, .a0 = at, .b0 = at, .r = 0.2, .hit = .{ .dmg = 6, .stance = 100 } };
        k.vigil.at = body;
        _ = k.update(dt, hero, 400, blade);
        try std.testing.expect(k.staggered());
        try std.testing.expect(!k.raised);
        try std.testing.expect(!k.laid);
        try std.testing.expect(!k.sigil.live());
        if (isRaise) try std.testing.expect(k.raiseCd > RAISE_CD * 0.9) else try std.testing.expect(k.frostCd > FROST_CD * 0.9);
        var after: u32 = 0;
        while (after < 200) : (after += 1) {
            k.vigil.at = null;
            _ = k.update(dt, hero, 400, .{});
            try std.testing.expect(!k.raised);
        }
    }
}

test "A RING ALREADY IN THE GROUND IS NOT THE CASTER'S TO CANCEL — a stroke that lands does not lift it" {
    var k = Necro.spawn(v3(0, 0, 14), 0, 1.0, 0.2);
    const at = mathx.zero3;
    k.debugLay(at);
    const dt = 1.0 / 60.0;
    runFor(&k, FROST_FUSE * 0.4, dt, at);
    const left = k.sigil.left;
    const hit = k.centerWorld();
    const blade = foe.Blade{ .active = true, .a = hit, .b = hit, .a0 = hit, .b0 = hit, .r = 0.3, .hit = .{ .dmg = 4, .stance = 100 } };
    _ = k.update(dt, at, 400, blade);
    try std.testing.expect(k.staggered());
    try std.testing.expect(k.sigil.live());
    try std.testing.expectApproxEqAbs(left - dt, k.sigil.left, 1e-4);
    var bills: u32 = 0;
    var t: f32 = 0;
    while (t < FROST_FUSE) : (t += dt) {
        if (k.update(dt, at, 400, .{}) != null) bills += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), bills);
}

test "THE RING IS A BURST, NOT A COLUMN — it takes the floor it was laid on and not the one above it" {
    const dt = 1.0 / 60.0;
    const bill = struct {
        fn at(heroY: f32) bool {
            var k = Necro.spawn(v3(0, 0, 20), 0, 1.0, 0.2);
            k.debugLay(mathx.zero3);
            var hit = false;
            var t: f32 = 0;
            while (t < FROST_FUSE + 0.2) : (t += dt) {
                _ = k.update(dt, v3(0, heroY, 0), 400, .{});
                if (k.heroHit != null) hit = true;
            }
            return hit;
        }
    }.at;
    try std.testing.expect(bill(0));
    // His own jump apex is 1.4 m and this is not a move he hops over.
    try std.testing.expect(bill(heromod.JUMP_APEX));
    try std.testing.expect(!bill(FROST_WALL_H + 1.0));
    try std.testing.expect(!bill(-(foe.HERO_HIGH + 0.5)));
    std.debug.print("  necro ring: reaches {d:.2} m over the mark; jump apex {d:.2} m still pays\n", .{ FROST_WALL_H, heromod.JUMP_APEX });
}

test "THE BLADE FINDS THE WHOLE BODY — skull, shins and all — and finds nothing in the air beside the robe" {
    for (TEST_SCALES) |size| {
        var k = Necro.spawn(mathx.zero3, 0, size, 0.3);
        runFor(&k, 0.5, 1.0 / 120.0, v3(0, 0, 40));
        for (HULLS) |hull| {
            const at = foe.markOn(k.xf[hull.bone], hull.center);
            try std.testing.expect(k.hullTouches(at, at, 0.01));
            // The broad phase must enclose every hull, or `foe.reached` throws the stroke away before the narrow test runs.
            try std.testing.expect(mathx.lenV(mathx.subV(at, k.centerWorld())) <= k.hurtRadius());
        }
        const skull = k.lockPoint();
        try std.testing.expect(k.hullTouches(skull, skull, 0.02));
        const shin = foe.markOn(k.xf[KNEEL], v3(0, -heromod.SEG_SHANK * H * 0.5, 0));
        try std.testing.expect(k.hullTouches(shin, shin, 0.02));
        const beside = v3(k.pos.x + 1.10 * size, k.pos.y + 1.30 * size, k.pos.z);
        try std.testing.expect(!k.hullTouches(beside, beside, 0.05));
        const overhead = v3(k.pos.x, k.pos.y + 3.6 * size, k.pos.z);
        try std.testing.expect(!k.hullTouches(overhead, overhead, 0.05));

        // A swept stroke through the skull lands; the same sweep a metre to the side does not.
        var live = Necro.spawn(mathx.zero3, 0, size, 0.3);
        runFor(&live, 0.5, 1.0 / 120.0, v3(0, 0, 40));
        const through = foe.shaftThrough(live.lockPoint(), .{ .dmg = 3 });
        _ = live.update(1.0 / 120.0, v3(0, 0, 40), 400, through);
        try std.testing.expect(live.hits == 1);

        var miss = Necro.spawn(mathx.zero3, 0, size, 0.3);
        runFor(&miss, 0.5, 1.0 / 120.0, v3(0, 0, 40));
        const wide = foe.shaftThrough(v3(0, miss.lockPoint().y, miss.pos.z + 1.6 * size), .{ .dmg = 3 });
        _ = miss.update(1.0 / 120.0, v3(0, 0, 40), 400, wide);
        try std.testing.expectEqual(@as(u32, 0), miss.hits);
        std.debug.print("  necro x{d:.1}: hurt sphere {d:.2} m over {d} posed hulls\n", .{ size, k.hurtRadius(), HULLS.len });
    }
}

test "AN INTERRUPT KEEPS THE POSE AND ITS VELOCITY — the springs carry every phase into the next" {
    const phases = [_]f32{ RAISE_WIND * 0.5, RAISE_WIND * 0.98, RAISE_WIND + RAISE_DUR * 0.5, RAISE_WIND + RAISE_DUR + 0.3 };
    var wide: u32 = 0;
    for (phases) |cut| {
        var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
        k.debugRaise(v3(2, 0, 2));
        const dt = 1.0 / 120.0;
        var t: f32 = 0;
        while (t < cut) : (t += dt) {
            k.vigil.at = v3(2, 0, 2);
            _ = k.update(dt, v3(0, 0, 9), 400, .{});
        }
        // A stagger throws the TARGET back to carry from wherever the cast had it. The output may only crawl toward it: crossing a fifth of that gap in two 8.3 ms frames is a spring, crossing all of it is a cut.
        const at = k.posed;
        k.stagger(true);
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
        var widest: f32 = 0;
        var crossed: f32 = 0;
        for (k.posed, at, CARRY_CH) |now, was, rest| {
            const gap = @abs(rest - was);
            widest = mathx.maxF(widest, gap);
            if (gap > 20.0) crossed = mathx.maxF(crossed, @abs(now - was) / gap);
        }
        // A phase whose pose already sits on carry has nothing to be continuous ABOUT; three of the four do.
        if (widest > 60.0) {
            wide += 1;
            try std.testing.expect(crossed < 0.30);
        }
        std.debug.print("  necro interrupt at {d:.2}s: widest channel gap {d:.0} deg, crossed {d:.1}% of it in two 8.3 ms frames\n", .{ cut, widest, crossed * 100.0 });
    }
    try std.testing.expect(wide >= 3);
}

test "RECOVERY CROSSES REST BEFORE IT SETTLES, and it does so at every frame rate" {
    for (TEST_DTS) |dt| {
        var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
        k.debugFrost();
        runFor(&k, FROST_WIND + FROST_CAST_DUR + 0.02, dt, v3(0, 0, 9));
        try std.testing.expectEqual(State.recover, k.state);
        var past = false;
        var t: f32 = 0;
        while (t < FROST_RECOVER + 1.4) : (t += dt) {
            _ = k.update(dt, v3(0, 0, 9), 400, .{});
            // Carry lean is +6; a recovery that glides onto it never goes under it.
            if (k.posed[C_LEAN] < CARRY.lean - 1.5) past = true;
        }
        try std.testing.expect(past);
        for (k.posed, CARRY_CH) |now, rest| try std.testing.expect(@abs(now - rest) < 3.0);
    }
}

test "THE HEM IS THE LAST THING TO MOVE, and it moves the same at 30, 60 and 144 Hz" {
    var settled: f32 = -1;
    var deepest: f32 = 1;
    for (TEST_DTS) |dt| {
        var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.3);
        var t: f32 = 0;
        while (t < 2.5) : (t += dt) k.tickHem(dt, heromod.WALK_SPEED_BANK * SPEED);
        if (settled < 0) settled = k.hemLean;
        try std.testing.expectApproxEqAbs(settled, k.hemLean, 0.05);
        var least: f32 = 999;
        t = 0;
        while (t < 2.5) : (t += dt) {
            k.tickHem(dt, 0);
            least = mathx.minF(least, k.hemLean);
        }
        try std.testing.expect(least < -0.05);
        deepest = mathx.minF(deepest, least);
        try std.testing.expect(@abs(k.hemLean) < 1.0);
    }
    // Cloth is slower than the body, or it reads welded to it.
    try std.testing.expect(HEM_STIFF < POSE_STIFF * std.math.pow(f32, POSE_FALL, CH - 1) * 0.2);
    std.debug.print("  necro hem: settles at {d:.2} deg, overshoots to {d:.2} on the stop\n", .{ settled, deepest });
}

test "A GATHER STILL COSTS THE COOLDOWN when it is cut, and the ring's own clock is untouched by it" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    k.debugFrost();
    const dt = 1.0 / 60.0;
    runFor(&k, FROST_WIND * 0.6, dt, v3(0, 0, 9));
    const cd = k.frostCd;
    k.stagger(true);
    runFor(&k, combat.FOE_HEAVY_STUN_DUR + 0.1, dt, v3(0, 0, 9));
    // An interrupted GATHER never spent it — only a completed cast does, and that is the existing rule.
    try std.testing.expect(k.frostCd <= cd + 1e-4);
    try std.testing.expect(!k.sigil.live());
}
