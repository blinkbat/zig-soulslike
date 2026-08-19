const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("combat.zig");
const item = @import("item.zig");
const statsmod = @import("stats.zig");
const art = @import("../props/propart.zig");
const propfx = @import("../props/propfx.zig");
const archer = @import("../foes/archer.zig");
const foemod = @import("../foes/foe.zig");
const elemfx = @import("../gfx/elemfx.zig");
const ptree = @import("passivetree.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const radians = mathx.radians;


pub const H: f32 = 1.8;

comptime {
    // `foe.zig` is below this file in the import graph and cannot read `H`, so it hardcodes 1.71.
    std.debug.assert(@abs(foemod.HERO_HIGH - 0.95 * H) < 0.005);
}

pub const WALK_SPEED: f32 = 1.7;
pub const RUN_SPEED: f32 = 3.4;
pub const SPRINT_SPEED: f32 = 5.1;
pub const STRAFE_SPEED: f32 = 0.85;
pub const GUARD_SPEED: f32 = 0.75;
pub const DRINK_SPEED: f32 = 0.35;
const DRINK_SINK: f32 = 0.012;

pub const SEG_THIGH = 0.245;
pub const SEG_SHANK = 0.246;
pub const SEG_UPARM = 0.188;
pub const SEG_FOREARM = 0.145;

pub const N = 18;
pub const ROOT = 0;
pub const SPINE = 1;
pub const CHEST = 2;
pub const NECK = 3;
pub const HEAD = 4;
pub const HIPL = 5;
pub const KNEEL = 6;
pub const ANKL = 7;
pub const HIPR = 8;
pub const KNEER = 9;
pub const ANKR = 10;
pub const SHL = 11;
pub const ELL = 12;
pub const WRL = 13;
pub const SHR = 14;
pub const ELR = 15;
pub const WRR = 16;
pub const HELD = 17;
const SWORD = HELD;

pub const PARENT = [N]i32{ -1, ROOT, SPINE, CHEST, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CHEST, SHL, ELL, CHEST, SHR, ELR, WRR };

pub fn restHumanoid(hx: f32, sx: f32, stature: f32) [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.640, 0);
    r[CHEST] = v3(0, 0.760, 0);
    r[NECK] = v3(0, 0.815, 0);
    r[HEAD] = v3(0, 0.885, 0);
    r[HIPL] = v3(hx, 0.530, 0);
    r[KNEEL] = v3(hx, 0.285, 0);
    r[ANKL] = v3(hx, 0.039, 0);
    r[HIPR] = v3(-hx, 0.530, 0);
    r[KNEER] = v3(-hx, 0.285, 0);
    r[ANKR] = v3(-hx, 0.039, 0);
    r[SHL] = v3(sx, 0.818, 0);
    r[ELL] = v3(sx, 0.630, 0);
    r[WRL] = v3(sx, 0.485, 0);
    r[SHR] = v3(-sx, 0.818, 0);
    r[ELR] = v3(-sx, 0.630, 0);
    r[WRR] = v3(-sx, 0.485, 0);
    r[HELD] = v3(-sx, 0.485, 0);
    for (&r) |*p| p.* = v3(p.x * stature, p.y * stature, p.z * stature);
    return r;
}

pub const HIP_HALF = 0.090;
pub const SHOULDER_HALF = 0.150;

fn restPositions() [N]rl.Vector3 {
    return restHumanoid(HIP_HALF, SHOULDER_HALF, H);
}

const SKIN = rgba(150, 112, 86, 255);
const SKIN_DK = rgba(120, 88, 66, 255);
const TUNIC = rgba(38, 40, 50, 255);
const TUNIC_DK = rgba(28, 30, 38, 255);
const LEATHER = rgba(58, 39, 26, 255);
const LEATHER_DK = rgba(38, 26, 18, 255);
const CLOTHDK = rgba(44, 39, 32, 255);
const BOOT = rgba(24, 22, 20, 255);
const BELT = rgba(34, 26, 18, 255);
const HAIR = rgba(40, 31, 24, 255);
const CAPE = rgba(82, 20, 12, 255);
const STEEL = rgba(98, 104, 114, 255);
const STEEL_DK = rgba(58, 62, 70, 255);
const BRASS = art.BRASS;

/// HOW MANY SAMPLES ONE STRIDE IS WRITTEN IN. Six tables and `sampleCurve`'s own wrap all counted it
/// separately; a table given a finer resolution than the sampler's modulus reads the first eight entries and
/// silently drops the rest, and the seam test still passes because both ends of the truncation match.
pub const GAIT_N = 8;

pub const HIP_FLEX = [GAIT_N]f32{ 25, 13, 3, -5, -10, -3, 12, 22 };
pub const KNEE_FLEX = [GAIT_N]f32{ 5, 18, 10, 4, 10, 38, 62, 30 };
pub const ANK_DORSI = [GAIT_N]f32{ -2, -6, 2, 9, 6, -14, -6, -1 };

pub const RUN_HIP = [GAIT_N]f32{ 42, 25, 8, -8, 5, 35, 60, 55 };
pub const RUN_KNEE = [GAIT_N]f32{ 26, 48, 40, 28, 62, 98, 80, 44 };
pub const RUN_ANK = [GAIT_N]f32{ -3, 10, 22, 2, -18, -6, 0, -2 };
const RUN_LEAN = 24.0;
const RUN_ARM_SWING = 30.0;
const RUN_ELBOW = 85.0;
const RUN_CROUCH = 0.06 * H;
const BODY_PITCH_RUN = 9.0;
const BODY_PITCH_SPRINT = 18.0;
const HEAD_WALK = 7.0;
const GAZE_AHEAD = 15.0;
const NECK_EXT_MAX = 34.0;
const A_RUN_BOUNCE = 0.05 * H;
const RUN_SPEED_LO = 2.1;
const RUN_SPEED_HI = RUN_SPEED;
const SPRINT_LEAN = 40.0;
const SPRINT_REF_SPEED = SPRINT_SPEED;

const SLOPE_LEAN: f32 = 0.55;
/// …capped: he can stand on ground far steeper than he can walk up, and a 40 deg fold reads as a stumble.
const SLOPE_LEAN_MAX: f32 = 16.0;
/// How fast the lean chases the ground, in degrees a second.
pub const SLOPE_LEAN_RATE: f32 = 120.0;

/// The body pitch a given uphill gradient asks for, in degrees.
pub fn slopeLean(rise: f32) f32 {
    const deg = mathx.degrees(std.math.atan(rise)) * SLOPE_LEAN;
    return mathx.clampF(deg, -SLOPE_LEAN_MAX, SLOPE_LEAN_MAX);
}

pub const JUMP_APEX: f32 = 1.0;
pub const JUMP_AIR: f32 = 0.72;
const JUMP_G: f32 = 8.0 * JUMP_APEX / (JUMP_AIR * JUMP_AIR);
const JUMP_V0: f32 = JUMP_G * JUMP_AIR * 0.5;
const AIR_TURN_RATE: f32 = 2.6;
const LAND_DUR: f32 = 0.34;
const LAND_SINK = 0.052 * H;
const LAND_SINK_AT: f32 = 0.22;
const LAND_REBOUND: f32 = 0.62;
pub const LAND_SINK_DEEPEST: f32 = LAND_DUR * LAND_SINK_AT;
const LAND_STOOP: f32 = 7.0;
/// THE FLIGHT POSE, all degrees. Three terms off ONE number (the vertical velocity): DRIVE on the way up,
/// TUCK at the apex where the velocity passes through zero, REACH on the way down.
const JUMP_TOEOFF: f32 = 26.0;
const JUMP_TOE_PLANTAR: f32 = 30.0;
const JUMP_TUCK_HIP: f32 = 62.0;
const JUMP_TUCK_KNEE: f32 = 88.0;
const JUMP_REACH_HIP: f32 = 14.0;
const JUMP_REACH_KNEE: f32 = 16.0;
const JUMP_REACH_DORSI: f32 = 12.0;
const JUMP_ARM_UP: f32 = 52.0;
const JUMP_ARM_HOLD: f32 = 0.55;
const JUMP_ARM_DROP: f32 = 0.55;
const JUMP_ARM_ELBOW: f32 = 34.0;
const JUMP_ARM_FOLD: f32 = 26.0;
const JUMP_ARM_OUT: f32 = 22.0;
const JUMP_ARCH: f32 = -8.0;
const JUMP_FOLD: f32 = 12.0;
const JUMP_HEAD_UP: f32 = -10.0;
const JUMP_LEG_SPLIT: f32 = 5.0;

const ROLL_DUR = 0.70;
const ROLL_IFRAME_END = 0.46;
pub const ROLL_DIST = 3.5;
const ROLL_BALL_Y = 0.50;
const ROLL_TUCK_IN = 0.16;
const ROLL_SPIN_A = 0.05;
const ROLL_SPIN_M0 = 0.40;
const ROLL_SPIN_M1 = 0.45;
const ROLL_SPIN_B = 0.80;
const ROLL_SPIN_OVER = 220.0; // degrees covered by the fast tumble segment
const ROLL_UNTUCK_A = 0.62;
const ROLL_UNTUCK_B = 0.97;
const ROLL_RISE_A = 0.70;
const ROLL_RISE_B = 1.00;
const ROLL_BRAKE_A = 0.50;
const ROLL_BRAKE_B = 0.92;
const ROLL_HIP = 95.0;
const ROLL_KNEE = 115.0;
const ROLL_SPINE = 30.0;
const ROLL_HEAD = 32.0;
const ROLL_SHOULDER = 45.0;
const ROLL_ELBOW = 100.0;
const ROLL_LEAN = 8.0;
const ROLL_SKEW = 7.0;
const ROLL_ARM_GUIDE = 1.25;
const ROLL_ARM_PUSH = 0.80;
const ROLL_LEG_LEAD = 1.08;
const ROLL_LEG_TRAIL = 0.92;
const ROLL_VAR_LO = 0.7;
const ROLL_VAR_HI = 1.3;
const ROLL_YAW_RATE = 22.0;

const ATK_LIGHT_DUR = 0.60;
const ATK_HEAVY_DUR = 1.00;
const AL_WIND_B = 0.28;
const AL_STRIKE_A = 0.28;
const AL_STRIKE_B = 0.48;
const AL_LAG = 0.03;
const AL_RECOV_A = 0.62;
const AL_HIT_A = 0.32;
const AL_HIT_B = 0.56;
const AL_LUNGE = 0.55;
const AL_CHAIN = 0.80;
const AH_WIND_B = 0.34;
const AH_STRIKE_A = 0.38;
const AH_STRIKE_B = 0.52;
const AH_LAG = 0.025;
const AH_RECOV_A = 0.72;
const AH_HIT_A = 0.40;
const AH_HIT_B = 0.58;
const AH_LUNGE = 1.05;
const AH_CHAIN = 0.86;
const ATK_RETRACK = 9.0;
const AL_BODY_YAW = 26.0;
const AL_BODY_YAW_THRU = 24.0;
const AL_SH_ELEV_WIND = 55.0;
const AL_SH_ELEV = 79.0;
const AL_SWEEP_WIND = 72.0;
const AL_SWEEP_END = 64.0;
const AL_ALT_WIND = 0.62;
const AL_ELBOW_WIND = 96.0;
const AL_ELBOW_STRIKE = 8.0;
const AL_WRIST_LAY = 18.0;
const AL_WRIST_WHIP = 12.0;
const AL_EDGE_ROLL = 90.0;
const AL_TIP_UP = 10.0;
const AL_SPINE_CRUNCH = 2.5;
const AL_OVER = 6.0;
const AL_LOAD = 0.016 * H;
const AL_DIP = 0.015 * H;
const AH_BODY_YAW = 11.0;
const AH_LEAN_BACK = 10.0;
const AH_SPINE_CRUNCH = 16.0;
const AH_SPINE_TILT = 5.0;
const AH_GATHER = 9.0;
const AH_SH_UP = 158.0;
const AH_SH_DOWN = 38.0;
const AH_ELBOW_WIND = 92.0;
const AH_ELBOW_STRIKE = 10.0;
const AH_WRIST_COCK = 22.0;
const AH_WRIST_SNAP = 28.0;
const AH_RECOIL = 7.0;
const AH_LOAD = 0.02 * H;
const AH_DIP = 0.05 * H;
const AH_PITCH = 9.0;
const BOW_QUICK_DUR: f32 = 0.62;
const BOW_QUICK_AT: f32 = 0.55;
const BOW_SHOT_DUR: f32 = 0.34;
const BOW_SHOT_AT: f32 = 0.22;
const BOW_SNAP: f32 = 0.06;
pub const BOW_QUICK_HIT = combat.Hit{ .dmg = 10, .poise = 5 };
pub const BOW_AIMED_HIT = combat.Hit{ .dmg = 23, .poise = 11, .stance = 8 };
pub const FIRE_ARROW_FRAC: f32 = 0.5;

pub fn fireTipped(h: combat.Hit) combat.Hit {
    var out = h;
    out.elem = combat.elems(.{ .fire = h.dmg * FIRE_ARROW_FRAC });
    return out;
}

pub fn arrowBlow(k: combat.ArrowKind, aimed: bool, perk: ptree.Bonus) combat.Hit {
    const base = (if (aimed) BOW_AIMED_HIT else BOW_QUICK_HIT).scaled(perk.bowDmg * perk.dmg);
    return switch (k) {
        .plain => base,
        .fire => fireTipped(base),
    };
}

pub fn arrowShot(k: combat.ArrowKind) archer.Shot {
    return switch (k) {
        .plain => .arrow,
        .fire => .firearrow,
    };
}

pub fn arrowBurns(k: combat.ArrowKind) bool {
    return switch (k) {
        .plain => false,
        .fire => true,
    };
}

pub const BOW_QUICK_SPEED: f32 = 26.0;
pub const BOW_AIMED_SPEED: f32 = 40.0;
pub const BOW_AIM_REACH: f32 = 60.0;
pub const BOW_AIM_SPEED: f32 = 0.45;
const BOW_SH_FLEX = 88.0;
const BOW_SH_ABD = 9.0;
const BOW_ELBOW = 13.0;
const BOW_WRIST = 6.0;
const BOW_DRAW_SH = 84.0;
const BOW_DRAW_ELBOW = 152.0;
const BOW_DRAW_ABD = 33.0;
const BOW_DRAW_YAW = 16.0;
const BOW_BLADE = 7.0;
const BOW_HEAD_NOD = 6.0;
const BOW_HEAD_YAW = 8.0;
const BOW_HEAD_CANT = 9.0;
const BOW_STOOP = 4.0;
const BOW_CARRY_SH = 26.0;
const BOW_CARRY_ELBOW = 8.0;
const BOW_DRAW_REST = 26.0;
const BOW_KICK = 7.0;
const BOW_BLEND_RATE = 11.0;
const TURN_TO_SHOT = 11.0;

const CAST_DUR: f32 = 0.66;
const CAST_AT: f32 = 0.46;

const RING_DUR: f32 = 1.05;
pub const RING_AT: f32 = 0.38;
const RING_SH_FWD = 74.0;
const RING_SH_ABD = 26.0;
const RING_ELBOW = 62.0;
const RING_FLICK = 46.0;
const RING_FLICK_RATE = 13.0;
const RING_FLICK_LEAD: f32 = 0.10;
const RING_DECAY: f32 = 4.2;
const RING_RECOV_A: f32 = 0.66;
const RING_LEAN = 7.0; // deg the trunk gives back against the raised arm — the waist, never the root
const RING_HEAD = -9.0;
pub const BOLT_SPEED: f32 = 30.0;
pub const BOLT_REACH: f32 = 55.0;

const CAST_SH_FWD = 118.0;
const CAST_LIFT_ABD = 24.0;
const CAST_ELBOW = 52.0;
const CAST_ELBOW_SNAP = 40.0;
const CAST_SWEEP = 46.0;
const CAST_WRIST = 38.0;
const WAND_CARRY_FLEX = 14.0;
const WAND_CARRY_ABD = 6.0;
const WAND_CARRY_ELBOW = 74.0;
const WAND_CARRY_WRIST = -12.0;
const WAND_CARRY_SWING = 0.55;
const WAND_CARRY_ELBOW_SWING = 0.40;
const CAST_TRUNK = 7.0;
const CAST_LEAN = 6.0;
const CAST_HEAD = 9.0;
const CAST_DIP = 0.020 * H;
const CAST_WIND_B = 0.32;
const CAST_RECOV_A = 0.70;

const BELL_PITCH = 12.0;
const BELL_CA = @cos(radians(BELL_PITCH));
const BELL_SA = @sin(radians(BELL_PITCH));
fn bellAt(t: f32) rl.Vector3 {
    return v3(-BELL_SA * t * H * 0.35, FIST_Y - BELL_CA * t * H, FIST_Z + BELL_SA * t * H);
}
const BELL_GRIP_T0 = -0.040;
const BELL_CROWN_T = 0.052;
const BELL_MOUTH_T = 0.107;
const BELL_MOUTH_R = 0.026 * H; // ~9.4 cm across the mouth: a hand bell, not a chapel one
const BELL_WALL = 0.0035 * H;
const BELL_BRONZE = rgba(78, 58, 30, 255);
const BELL_BRONZE_LT = rgba(104, 80, 42, 255);
/// The mouth is a HOLE, so near-black cannot blow out — and the contrast against the rim is the read.
const BELL_BORE = rgba(14, 11, 8, 255);
const BELL_HANDLE = rgba(46, 34, 26, 255);

const WAND_LEN = 0.30 * H;
const WAND_R = 0.0155 * H;
const WAND_STONE_R = 0.030 * H;
const WAND_WOOD = rgba(41, 30, 24, 255);
const WAND_WOOD_LT = rgba(62, 47, 36, 255);
const WAND_BIND = rgba(30, 25, 22, 255);
const WAND_FERRULE = rgba(9, 10, 12, 255);
const WAND_STONE = rgba(96, 40, 122, 120);
const WAND_STONE_HOT = rgba(150, 74, 176, 60);
const WAND_PITCH = 55.0;
const WAND_ULNAR = 8.0;
const WAND_PALM = 0.017 * H;
const WAND_CA = @cos(radians(WAND_PITCH));
const WAND_SA = @sin(radians(WAND_PITCH));
const WAND_UC = @cos(radians(WAND_ULNAR));
const WAND_US = @sin(radians(WAND_ULNAR));
const WAND_AX = v3(WAND_SA * WAND_US, -WAND_CA, WAND_SA * WAND_UC);
const WAND_U = mathx.normV(v3(-WAND_AX.z, 0, WAND_AX.x));
const WAND_V = mathx.normV(mathx.crossV(WAND_AX, WAND_U));
fn wandAt(t: f32) rl.Vector3 {
    return v3(
        WAND_AX.x * t * H,
        FIST_Y + WAND_AX.y * t * H,
        FIST_Z + WAND_PALM + WAND_AX.z * t * H,
    );
}
const WAND_TIP_T = 0.30;
const WAND_BUTT_T = 0.055;
fn offAxis(at: rl.Vector3, r: f32, a: f32) rl.Vector3 {
    const c = r * mathx.cosf(a);
    const s = r * mathx.sinf(a);
    return v3(at.x + c * WAND_U.x + s * WAND_V.x, at.y + c * WAND_U.y + s * WAND_V.y, at.z + c * WAND_U.z + s * WAND_V.z);
}

const CHAOS_MOTE = elemfx.sig(.chaos).edge;
const CHAOS_HOT = elemfx.sig(.chaos).core;
const CAST_MOTE_RATE = 52.0;
const CAST_MOTE_R = 0.17;
const CAST_MOTE_RATE_HI = 300.0;
const CAST_MOTE_R_HI = 0.055;
const CAST_MOTE_CAP = 8;
const CAST_MOTE_LIFE_LO = 0.030;
const CAST_MOTE_LIFE_HI = 0.055;
/// …and the radius is what buys that short life back, not the count: `drawParticles` fades radius WITH alpha,
/// so at 0.04 s a mote is legible on one frame of three and at 0.015 nine motes showed as three.
const CAST_MOTE_R0 = 0.023;
const CAST_MOTE_R1 = 0.011;
const CAST_SPARKS = 26;
const CAST_COLLAR = 12;
const CAST_COLLAR_SP = 4.4;
/// One bloom on the stone at the throw. SMALL: it is a solid sphere, not additive, so at 0.30 it rendered as a
/// translucent balloon hiding the stone, the claws, the cone and the collar all at once.
const CAST_FLASH_R = 0.095;
const CAST_FLASH_LIFE = 0.085;
const BOLT_BURST = 22;


const LEVIN_STEPS = 9;
const LEVIN_SPARKS = 2;
const LEVIN_BURST = 26;
const LEVIN_JITTER = 0.11 * H;
/// **THE SHORT LIFE IS BOUGHT BACK WITH RADIUS, NEVER WITH MORE MOTES** (the cast gather's own law, MEASURED off
/// a render here too): a lightning mote is authored at 2 cm and lives four hundredths of a second, so the first
/// pass photographed as eight white specks hanging over a skeleton's head — the strike had plainly happened and
/// nothing said where. `elemfx`'s `scale` takes the grain AND the throw, so the stroke stays a stroke.
const LEVIN_SPARK_SCALE = 2.2;
/// …and the landing is the loudest thing in it, since it is what says WHERE. Held to 2.4 rather than 3.2 off the
/// same render: at 7 cm a mote is a soft ball and the shower photographed as SMOKE over the body, which is the
/// one thing a spark may not read as.
const LEVIN_BURST_SCALE = 2.4;

/// **AND THE STROKE IS A SOLID BOLT, NOT A ROW OF SPARKS** (owner: it should look more like a solid bolt).
/// Nine spark sites over sixteen metres is one cluster every 1.8 m — beads on a string, and no amount of
/// motes fixes it, because what says LIGHTNING is an unbroken shaft with a kink in it. So the shaft is
/// GEOMETRY now (`drawLevinBolt`, the archer's own tapered-cylinder trail primitive) and the sparks are what
/// crackles off it.
const LEVIN_BOLT_PTS = 12;
const LEVIN_BOLT_LIFE: f32 = 0.16;
const LEVIN_BOLT_W: f32 = 0.055;
const LEVIN_BOLT_TIP: f32 = 0.45;
const LEVIN_BOLT_GLOW: f32 = 3.6;
const LEVIN_BOLT_JAG: f32 = 0.34;
const LEVIN_CORE = rgba(248, 250, 255, 255);
const LEVIN_GLOW = rgba(150, 190, 255, 120);

const SIPHON_MOTES = 34;
const SIPHON_LIFE_LO = 0.18;
const SIPHON_LIFE_HI = 0.30;
const SIPHON_SPREAD = 0.30 * H;

const LANCE_STEPS = 22;
const LANCE_SPARKS = 4;
const LANCE_JITTER = 0.06 * H;
/// **THE SHORT LIFE IS BOUGHT BACK WITH RADIUS** — the stroke's own law. Fire lives longer than lightning in
/// `elemfx`, so this sits under the levin's 2.2: at the same throw the shaft photographed as a hedge.
const LANCE_SPARK_SCALE = 1.7;
const LANCE_FLOOR_DROP = 1.05 * H;

const SUNDER_MOTES = 28;
const SUNDER_SPEED_LO = 2.2;
const SUNDER_SPEED_HI = 5.0;
const SUNDER_DUST = mathx.rgba(126, 116, 100, 190);
const SUNDER_CHIP = mathx.rgba(78, 68, 56, 215);

const ROOT_SITES = 3;
const ROOT_FANS = 9;
const ROOT_RISE: f32 = 0.20;
const ROOT_SINK: f32 = 0.55;
const ROOT_LAG: f32 = 0.55;
const ROOT_PUNCH: f32 = 0.20;
const ROOT_KINDS = 3;
const ROOT_SEGS = 10;
/// ~1.05 m — HIP height on the 1.8 m rig, and bracketed from both sides: lower and it is scenery round the
/// ankles, man-height and the tendrils hide the creature they are holding.
const ROOT_LEN = 0.58 * H;
const ROOT_R0 = 0.052 * H;
const ROOT_R1 = 0.019 * H;
/// MEASURED, NOT GUESSED (AGENTS.md): at `34,25,18` on `.bark` these sampled 115,94,68 against grass at
/// 110,97,67 — the same value, so they read as pale timber for want of any separation at all. SOLVED from
/// there: screen = (albedo/255 × 1.72)^(1/2.2) × 255, so half the ground's 110 is screen 55, and 55 back
/// through the chain is albedo 5. `.wood` is the material that does not lift it again (it is the rod's own).
/// The two bark tones are kept CLOSE: pushed apart they band the shaft like a barber's pole.
const ROOT_BARK = rgba(5, 4, 3, 255);
const ROOT_BARK_LT = rgba(9, 7, 5, 255);
const ROOT_HEART = rgba(24, 21, 15, 255);
const ROOT_SOIL = mathx.rgba(96, 78, 58, 190);
const ROOT_DUST = 34;
const ROOT_MOTES = 26;
const ROOT_LIFE: f32 = ROOT_RISE + combat.ROOT_HOLD + ROOT_SINK;
const ROOT_SITE_LIFE: f32 = ROOT_LIFE + ROOT_RISE * ROOT_LAG;

const RootSite = struct {
    at: rl.Vector3 = mathx.zero3,
    t: f32 = mathx.LONG_AGO,
    seed: f32 = 0,
};

// THE RIME BREATH — the rod's third sorcery, and the only one that is a DIRECTION rather than a mark. What
// the numbers here own is the PICTURE; the mechanic's own (reach, arc, span, what it bills) are
// `combat.RIME_*`, so the cone that is drawn cannot say something different from the cone that hits.

const BREATH_RATE = elemfx.POUR_RATE;
const BREATH_CAP = elemfx.POUR_CAP;
// HOW BIG A FROST MOTE IS is NOT here: a jet's grain is finer than the signature table's, and that is a fact
// about POURING rather than about him (`elemfx.POUR_GRAIN`). Held here as his own it was passed in through
// `scale`, so the editor's bench — which is where this is tuned — drew the same stream 60% coarser.

const BREATH_NOZZLE_FWD = 0.030 * H;
/// The trunk braces BACK against what the rod is pushing out and OVERSHOOTS its rest coming off it (the
/// reactions law) — through the WAIST, spine and chest, never the root. Degrees, total across the two.
const BREATH_LEAN = -13.0;
const BREATH_HEAD = 6.0;
const BREATH_REACH = 12.0;
/// **AND THE ROD COMES DOWN TO LEVEL FOR IT, which is a mechanic and not a flourish.** The throw beat leaves
/// the shoulder at `CAST_SH_FWD` (118 deg — well past straight out), because a BOLT is thrown at a mark that
/// may be above him. The cone is not: `breathDir` is level by construction and the bite is tested in XZ, so a
/// rod still pointed at the sky is a picture promising a reach the mechanic does not have. Subtracted off the
/// flexion to land near 78 deg — a shade UNDER straight out, which is where the arm has to sit for the STONE
/// to end up level: the wand is held at an angle in the fist, so a shoulder at a true 90 still points it up.
const BREATH_SH_LEVEL = 40.0;
const BREATH_SHIVER = 1.5;
const BREATH_SHIVER_HZ = 12.0;

const FX_N = 1280;

comptime {
    const gather = CAST_MOTE_RATE_HI * CAST_MOTE_LIFE_HI;
    const release = CAST_SPARKS + CAST_COLLAR + 1;
    const erupt = ROOT_DUST + ROOT_MOTES;
// …and the shield's sparks: a parry cannot run WITH a cast, but its sparks outlive the swap.
    const caught = PARRY_SPARKS + 1 + PARRY_GLINT + 1;
    const ticks = @ceil(combat.RIME_DUR * BREATH_RATE);
    const breath = @as(f32, @floatFromInt(elemfx.pourCount(1))) * ticks;
    // …and the two STRIKES, which land on the frame they are cast rather than after a flight, so their whole
    // claim is in the air at once. They cannot run WITH a pour — but the pour's motes outlive their cast, and
    // the rod may be turned to another spell the moment it ends, so the pool has to hold both.
    const struck = LEVIN_STEPS * LEVIN_SPARKS + LEVIN_BURST + SIPHON_MOTES;
    const worst = gather + breath + @as(f32, release + erupt + caught + struck + 2 * BOLT_BURST);
    if (@as(f32, FX_N) < worst) @compileError(std.fmt.comptimePrint(
        "hero: FX_N = {d} but a cast can have {d} particles in the air — raise it",
        .{ FX_N, worst },
    ));
}

const WAND_LIT = mathx.colVec(CHAOS_MOTE);
/// Radius matters more than brightness (the chapel's law), so the carry's ember is SHORT as well as dim: at a
/// torch's 6 m it washed him violet head to foot standing still.
const WAND_LIT_CARRY = 0.20;
const WAND_LIT_CARRY_R = 2.6;
const WAND_LIT_CHARGED = 1.00;
const WAND_LIT_CHARGED_R = 7.0;
const WAND_LIT_FLARE = 2.30;
const WAND_LIT_FLARE_R = 12.0;

pub const AIM_LEAN_DOWN = 34.0;
pub const AIM_LEAN_UP = 12.0;
const AIM_LEAN_RATE = 190.0;
const AIM_LEAN_BIAS = 7.0;

pub const BLADE_R = 0.34;

const TRAIL_N = 20; // ring capacity (~0.3 s of samples at 60 fps)
const TRAIL_LIFE = 0.20;
const TRAIL_ROOT = 0.35;
const TRAIL_PEAK = 84.0;

pub const HP_MAX = statsmod.hpFor(statsmod.START);
pub const POISE_MAX = 55.0;
pub const STANCE_MAX = 90.0;
pub const ATK_LIGHT_HIT = combat.Hit{ .dmg = 13, .poise = 10 };
pub const ATK_HEAVY_HIT = combat.Hit{ .dmg = 27, .poise = 22, .stance = 14 };

pub fn freshVitals(sheet: statsmod.Sheet) combat.Vitals {
    return combat.Vitals.init(sheet.hp(), POISE_MAX, STANCE_MAX);
}


pub const Worn = struct {
    in: std.EnumArray(item.Wear, ?item.Kind) = std.EnumArray(item.Wear, ?item.Kind).initFill(null),

    pub fn at(self: Worn, w: item.Wear) ?item.Kind {
        return self.in.get(w);
    }

    pub fn put(self: *Worn, w: item.Wear, k: ?item.Kind) void {
        self.in.set(w, k);
    }
};

/// **WHAT THE WHOLE SUIT IS WORTH AGAINST PHYSICAL** — summed over every socket with a plate in it, because a
/// helm and a coat and a pair of boots are three pieces of one answer. `combat.armourTaken` is a diminishing
/// curve, so summing them cannot become immunity however many sockets gain a plate. A FREE function for
/// `armourA`'s own reason: the character page prices a suit he is only considering (`book.armourOf`).
pub fn armourOf(worn: Worn) f32 {
    return plateOf(worn).a;
}

/// **THE WHOLE DEFENSIVE ROW OF THE SUIT, IN ONE WALK** — `charmOf`'s shape: one fold over the sockets
/// returning one aggregate. As three separate folds (physical, the elements, the status rate) it was the same
/// loop over the same `.plate` arm written out three times, and three places to forget a socket from.
/// **PHYSICAL AND THE FOUR COLUMNS ADD; THE STATUS RATE MULTIPLIES** — two pieces that each halve it leave a
/// quarter, where two that each took 0.5 off would leave nothing and make a second one free immunity.
pub fn plateOf(worn: Worn) item.Plate {
    var out = item.Plate{ .slot = .chest };
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        if (worn.at(@enumFromInt(f.value))) |k| {
            switch (item.equip(k)) {
                .plate => |p| {
                    out.a += p.a;
                    out.res.fire += p.res.fire;
                    out.res.cold += p.res.cold;
                    out.res.lightning += p.res.lightning;
                    out.res.chaos += p.res.chaos;
                    out.poison *= p.poison;
                },
                else => {},
            }
        }
    }
    return out;
}

pub fn resistOf(worn: Worn) item.Res {
    return plateOf(worn).res;
}

pub fn poisonRateOf(worn: Worn) f32 {
    return plateOf(worn).poison;
}

pub fn charmOf(worn: Worn) item.Charm {
    var out = item.Charm{ .slot = .ring };
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        if (worn.at(@enumFromInt(f.value))) |k| {
            switch (item.equip(k)) {
                .charm => |c| {
                    out.leech += c.leech;
                    out.hpFrac += c.hpFrac;
                    out.fpFrac += c.fpFrac;
                    out.spiritFp *= c.spiritFp;
                },
                else => {},
            }
        }
    }
    return out;
}

pub fn hpMaxOf(sheet: statsmod.Sheet, worn: Worn, perk: ptree.Bonus) f32 {
    // **AND THE BERSERKER'S BARGAIN EATS THE SAME BAR A CHARM DOES** (`passivetree.Grant.sacrifice`) — the two
    // costs ADD before the clamp, so a leech signet worn under Berserk cannot take more than the floor allows
    // and a build that stacked both can still be alive.
    const eaten = charmOf(worn).hpFrac + perk.hpFrac;
    return sheet.hp() * (1.0 - mathx.clampF(eaten, 0, 0.9));
}

pub fn fpMaxOf(sheet: statsmod.Sheet, worn: Worn, perk: ptree.Bonus) f32 {
    return sheet.fp() * (1.0 - mathx.clampF(charmOf(worn).fpFrac, 0, 0.9)) * perk.fpMax;
}

pub fn boonsOnto(worn: Worn, sheet: *statsmod.Sheet) void {
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        if (worn.at(@enumFromInt(f.value))) |k| {
            switch (item.equip(k)) {
                .boon => |b| sheet.add(b.attr, b.n),
                else => {},
            }
        }
    }
}

fn refitPool(cur: *f32, max: *f32, to: f32) void {
    const frac = if (max.* > 1e-4) cur.* / max.* else 1.0;
    max.* = to;
    cur.* = mathx.minF(to, to * frac);
}

pub fn scaleOf(sheet: statsmod.Sheet, s: item.Scaling) f32 {
    return switch (s) {
        .strength => sheet.scale(.strength),
        .dexterity => sheet.scale(.dexterity),
        .quality => 0.5 * (sheet.scale(.strength) + sheet.scale(.dexterity)),
    };
}

pub fn armRow(worn: Worn, w: item.Wear) item.Arm {
    if (worn.at(w)) |k| {
        switch (item.equip(k)) {
            .arm => |a| return a,
            else => {},
        }
    }
    return item.bareArm(w);
}

/// …and WHICH SOCKET AN ARMAMENT DRAWS ITS ROW FROM — the ONE place `hero.Armament` and `item.Wear` are matched
/// up (`item.Wear`'s own note: the item file cannot name an armament). Null for the two that have no variants:
/// there is one bell and one rod in this world.
pub fn wearFor(a: Armament) ?item.Wear {
    return switch (a) {
        .sword => .hand_sword,
        .bow => .hand_bow,
        .shield => .hand_shield,
        .bell, .wand => null,
    };
}

/// **WHICH PIECE OF GEAR IS IN THAT HAND, IF ANY** — the one answer the HUD's cell, the book's socket and the
/// held mesh all ask, so a dirk cannot be drawn in one picture and a sword in the other.
pub fn heldGear(a: Armament, worn: Worn) ?item.Kind {
    const w = wearFor(a) orelse return null;
    return worn.at(w);
}

/// **WHAT A WEAPON'S ROW DOES TO A BLOW, AND THE ONE PLACE IT IS DONE** — the sword's swing and the bow's shaft
/// both come through here, so "heavier" cannot come to mean two different things one hand apart. The ELEMENTAL
/// half rides the DAMAGE dial (a fire arrow's fire is a share of the shaft's own physical, `arrowBlow`) and the
/// STANCE rides the POISE dial: both of those are the blow's WEIGHT, and a row that moved one without the other
/// would be a weapon hitting harder without hitting heavier — `combat.Hit.scaled`'s own reason, per weapon.
///
/// **AND THE SKILL RIDES THE DAMAGE DIAL AND NOTHING ELSE** (`sheet`, through the row's own `scales`). Strength
/// makes a club hit HARDER, not heavier: poise and stance belong to the WEAPON's mass, so a scrawny man swinging
/// a greatclub still flinches what the sword bounces off, and a strong one does not gain a stagger he did not buy.
pub fn weigh(h: combat.Hit, row: item.Arm, sheet: statsmod.Sheet) combat.Hit {
    const skill = scaleOf(sheet, row.scales);
    return .{
        .dmg = h.dmg * row.dmg * skill,
        .poise = h.poise * row.poise,
        .stance = h.stance * row.poise,
        .elem = h.elem.scaled(row.dmg * skill),
        .fp = h.fp,
    };
}

const HURT_LEAN = 40.0;
const HURT_HEAD = 52.0;
const HURT_STEP = 0.18 * H;
const STAG_LEAN = 42.0;
const DEATH_SINK = 0.30;
pub const DEATH_DUR = 3.6;

const GUARD_SH_FLEX = 24.0;
const GUARD_SH_CROSS = 40.0;
const GUARD_SH_ABD = 2.0;
const GUARD_ELBOW = 96.0;
const GUARD_BLADE = 9.0;
const GUARD_CROUCH = 0.022 * H;
const GUARD_SWORD_BACK = 40.0;
const GUARD_SWORD_ELBOW = 46.0;
const GUARD_SWORD_WRIST = 30.0;
const GUARD_HEAD = 6.0;
const GUARD_BLEND_RATE = 11.0;
const BLOCK_RECOIL_DUR = 0.24;
const BLOCK_SHIELD_BACK = 15.0;
const BLOCK_SHIELD_FOLD = 10.0;
const BLOCK_TRUNK = 9.0;
const BLOCK_STEP = 0.14 * H;
const BLOCK_SINK = 0.048 * H;
const BLOCK_FLASH = 0.22; // a LICK of red, well under `takeHit`'s 0.35 for a blow that got through

pub const PARRY_DUR = 0.52;
const PARRY_OPEN = 0.10;
const PARRY_SHUT = 0.26;
pub const PARRY_PUNCH_AT = 0.33;
const PARRY_REBOUND = 0.75;
/// THE THRUST, AND IT IS PAID FOR AT BOTH JOINTS. `shieldFit` is the INVERSE of the guard's arm fold
/// (`GUARD_ARM_FOLD` = shoulder flex + elbow), so the boards keep their facing only while that SUM does:
/// opened at the elbow alone, a shove this size rotates the shield clean off its own arm (measured).
const PARRY_PUNCH = 60.0;
const PARRY_SWEEP = 26.0;
const PARRY_WRIST = 20.0;
const PARRY_TRUNK = 52.0;
const PARRY_ARM_LEAD = 16.0;
pub const PARRY_COIL_AT = 0.17;
pub const PARRY_SWEEP_END = 2.0 * PARRY_PUNCH_AT - PARRY_COIL_AT;
const PARRY_PELVIS = 0.30;
const PARRY_PITCH = 8.0;
const PARRY_HAND_LEAD = 0.075 * H;
const PARRY_SINK = 0.024 * H;
const PARRY_SWORD_COCK = 18.0;
const PARRY_HEAD = 12.0;
/// STRUCK IRON — thrown along the boards' own normal, so a catch reads off the SHIELD and not off the hero.
/// SEPARATED ON HUE, not on value: the boards come back off this sun around 140, and a pale cream spark at 3 cm
/// read as a soft bubble sitting on them (measured, at 30 of them). Hot amber on pale tan reads at a tenth that.
const PARRY_SPARK = rgba(255, 206, 108, 240);
const PARRY_SPARK_HOT = rgba(255, 250, 232, 250);
const PARRY_SPARKS = 34;
/// AND THE FAN IS THE DOMINANT HALF OF THE THROW: forward is DOWN THE LENS here, so at 0.42 of the forward
/// speed most were still inside the disc's own outline four frames later (measured). What says "shower" is the
/// ones crossing the RIM — hence a fan bigger than the shield's radius, and only enough forward to clear.
const PARRY_SPARK_FAN = 9.0;
const PARRY_SPARK_OUT_LO = 1.0;
const PARRY_SPARK_OUT_HI = 3.2;
const PARRY_SPARK_R0_LO = 0.009;
const PARRY_SPARK_R0_HI = 0.019;
const PARRY_SPARK_GRAV = 9.0;
const SPARK_PROUD: f32 = 0.02;
/// One bloom on the boss, SMALL for the cast flash's reason: a solid sphere, not additive, so at 0.085 it read
/// as a puff of smoke sat on the boards — on the FIRST frame it and every spark are still at the same point.
const PARRY_FLASH_R = 0.05;
const PARRY_FLASH_LIFE = 0.06;
const PARRY_GLINT = 18;
/// TIGHTER THAN THE CATCH'S FAN, NOT WIDER. Thrown as far and lived as long as struck iron, a dozen motes
/// were strewn across the grass a metre off the boards five frames later and read as litter (measured) —
/// a glint has to HUG the shield and be gone. Count buys the brightness, the fan and the life buy the read.
const PARRY_GLINT_FAN = 4.5;
/// LAID ALONG THE ARC, not thrown from a point. Every burst here is coincident on its emission frame, and a
/// whiffed swipe has no impact to justify a flash — a white ball beside the boards read as an artifact
/// (measured). Spread over the sweep's own axis it is a STREAK from the first frame.
const PARRY_GLINT_SPAN = 0.22;
const PARRY_GLINT_TRAIL = 0.55;
/// …and the bloom is UNDER the catch's 0.05, not over it: at 0.075 the first frame was a solid white ball
/// sitting beside the boards (measured), which is the balloon the cast flash's own note warns about.
const PARRY_GLINT_FLASH_R = 0.03;

const BLOCK_GRIT = rgba(196, 190, 178, 225);
const BLOCK_GRIT_DARK = rgba(120, 112, 100, 210);
const BLOCK_GRIT_MIN = 10;
const BLOCK_GRIT_MAX = 26;
const BLOCK_GRIT_OUT_LO = 0.5;
const BLOCK_GRIT_OUT_HI = 1.7;
const BLOCK_GRIT_FAN = 3.4;
const BLOCK_GRIT_GRAV = 13.0;
const BLOCK_GRIT_LIFE_LO = 0.10;
const BLOCK_GRIT_LIFE_HI = 0.30;
const BLOCK_PUFF_R = 0.11;
const BLOCK_PUFF_LIFE = 0.16;

/// **THE FOG GATE'S WAKE** (`fogWake`). The exact opposite dial-for-dial of the block's grit, which is what
/// makes it read as vapour rather than as debris: it goes SIDEWAYS and UP instead of out and down, it lives
/// four times as long, it is a hand wide instead of a fingernail, and its gravity is NEGATIVE — the one
/// emitter in the hero's kit that rises. The COLOURS are the gate's own and are taken from it
/// (`propfx.FOG_WAKE_*`), so retuning the wall retunes what it sheds.
const FOG_WAKE_OUT_LO = 0.35;
const FOG_WAKE_OUT_HI = 1.05;
const FOG_WAKE_RISE = 0.28;
const FOG_WAKE_GRAV = -0.55;
const FOG_WAKE_LIFE_LO = 0.55;
const FOG_WAKE_LIFE_HI = 1.25;
const FOG_WAKE_R0_LO = 0.055;
const FOG_WAKE_R0_HI = 0.115;
const FOG_WAKE_R1 = 0.20;
/// **AND IRON STRUCK IRON THROWS LIGHT** (owner: sparks fly). The block was grit alone — pale, heavy, and
/// dropping — which is the dust off the facing and nothing else, so a blow caught on a bound rim looked like
/// one caught on a plank. Deliberately UNDER the parry's shower (`PARRY_SPARKS`, 34): the catch is the
/// earned one and may not be out-sparked by holding the boards up.
const BLOCK_SPARK_MIN = 4;
const BLOCK_SPARK_MAX = 15;
const BLOCK_SPARK_FAN_K: f32 = 0.62;

const SHIELD_R = 0.115 * H;
const SHIELD_THICK = 0.020 * H;
const SHIELD_WOOD = rgba(56, 41, 29, 255);
const SHIELD_WOOD_LT = rgba(82, 62, 44, 255);
const SHIELD_IRON = rgba(26, 28, 34, 255);
const SHIELD_BOSS = rgba(46, 49, 58, 255);
const SHIELD_STANDOFF = 0.045 * H;
const GUARD_ARM_FOLD = GUARD_SH_FLEX + GUARD_ELBOW;
const SH_FOLD_S = @sin(radians(GUARD_ARM_FOLD));
const SH_FOLD_C = @cos(radians(GUARD_ARM_FOLD));
const SH_CROSS_S = @sin(radians(GUARD_SH_CROSS));
const SH_CROSS_C = @cos(radians(GUARD_SH_CROSS));
/// The face's own normal in the WRIST's frame — where the standoff has to be measured, since the hand grips
/// BEHIND the boss.
const SHIELD_N = v3(SH_CROSS_S, -SH_CROSS_C * SH_FOLD_S, SH_CROSS_C * SH_FOLD_C);
const SHIELD_HUB = v3(
    SHIELD_STANDOFF * SHIELD_N.x,
    FIST_Y + SHIELD_STANDOFF * SHIELD_N.y,
    FIST_Z + SHIELD_STANDOFF * SHIELD_N.z,
);
fn shieldFit(left: bool) rl.Matrix {
    const sd: f32 = if (left) 1.0 else -1.0;
    return mul3(ry(sd * GUARD_SH_CROSS), rx(GUARD_ARM_FOLD), tr(sd * SHIELD_HUB.x, SHIELD_HUB.y, SHIELD_HUB.z));
}

const GRIP_PITCH = 34.0;
const GRIP_OUT = 8.0;
const GRIP_CA = @cos(radians(GRIP_PITCH));
const GRIP_SA = @sin(radians(GRIP_PITCH));
const OUT_CA = @cos(radians(GRIP_OUT));
const OUT_SA = @sin(radians(GRIP_OUT));
const FIST_Y = -0.05 * H;
const FIST_Z = 0.005 * H;
fn bladeAt(t: f32) rl.Vector3 {
    return v3(-GRIP_SA * OUT_SA * t * H, FIST_Y - GRIP_CA * t * H, FIST_Z + GRIP_SA * OUT_CA * t * H);
}
/// **WHAT IS ACTUALLY IN HIS FIST — THREE SHAPES ON ONE GRIP.** Same bone (`SWORD`), same grip frame, same
/// stroke: the pose, the trail, the sparks and every window are written once and only the STEEL changes. `t`
/// is the fraction of stature out along the grip axis (`bladeAt`), so a reach here is metres the moment `H` is
/// fixed, and `r` is the capsule the fight is fought with rather than anything you can see.
pub const Blade = enum { sword, dirk, club };

const BladeSpec = struct { base: f32, tip: f32, r: f32 };

const BLADES = [_]BladeSpec{
    .{ .base = -0.06, .tip = 0.64, .r = BLADE_R }, // sword: 1.15 m past the fist
    .{ .base = -0.05, .tip = 0.37, .r = 0.25 }, // dirk: 0.67 m, and a hand's width of it is edge
    .{ .base = -0.06, .tip = 0.80, .r = 0.42 }, // club: 1.44 m of bog-oak, swung with the whole body
};

fn bladeSpec(b: Blade) BladeSpec {
    return BLADES[@intFromEnum(b)];
}

/// WHICH SHAPE A PIECE OF GEAR IS. The socket is `hand_sword` for all three — this is the one place a kind
/// becomes a shape, exactly as `hero.wearFor` is the one place an armament becomes a socket.
pub fn bladeFor(k: ?item.Kind) Blade {
    return switch (k orelse return .sword) {
        .fang_dirk => .dirk,
        .greatclub => .club,
        else => .sword,
    };
}

/// …AND HOW THE BODY GOES INTO IT. A club is not a sword with bigger numbers: it is gathered further back,
/// dropped from lower in the hips and carried further through, and a dirk is the same stroke shut down to the
/// elbow. Multipliers on the ONE set of pose constants (`AL_*`, `AH_*`), so a retune of the swing still moves
/// all three together and there is no second stroke to keep in step.
/// **THE PLAIN SWORD IS 1 ON EVERY DIAL** — the starting kit is the game exactly as it was, which is the law
/// `item.bareArm` keeps on the other side of the same weapon. A test pins the table against `item.Heft`: what
/// the page calls Heavy is what the body swings heavy, and the two cannot drift.
pub const SwingShape = struct { arc: f32 = 1, wind: f32 = 1, dip: f32 = 1 };

pub fn swingOf(b: Blade) SwingShape {
    return switch (b) {
        .sword => .{},
        .dirk => .{ .arc = 0.82, .wind = 0.84, .dip = 0.86 },
        .club => .{ .arc = 1.22, .wind = 1.30, .dip = 1.40 },
    };
}

const CARRY_DAMP = 0.45;
const CARRY_ELBOW = 14.0;
const CARRY_ELBOW_RUN = 30.0;
const CARRY_WRIST_LIFT = -54.0;
const CARRY_LIFT_WALK = 0.4;
const CARRY_ABD_RUN = 12.0;
const CARRY_WRIST_YAW = -48.0;
const CARRY_SWING_STILL = 0.6;

const POSE_XFADE = 0.09;
const SPEED_SMOOTH = 80.0;

const GAIT_DIR_EASE = 22.0;
const STRAFE_ABD = 22.0;
const STRAFE_STANCE = 0.52; // fraction of the cycle each foot is planted (~4% double support)
const STRAFE_CROSS = 38.0;
const STRAFE_BEHIND = 10.0;
const STRAFE_LAND = 7.0;
const STRAFE_CLEAR = 0.035 * H;
const STRAFE_SINK = 0.0055 * H;
const STRAFE_PROT = 7.0;
const STRAFE_SWAY = 0.012 * H;
const STRAFE_LEAN = 2.5;
const BACK_STRIDE = 0.85;

pub const LEG_LEN = (0.530 - 0.039) * H;
const STRAFE_REACH = LEG_LEN * @sin(mathx.radians(STRAFE_ABD));
const STRAFE_CYCLE = 2.0 * STRAFE_REACH / STRAFE_STANCE;
pub const STRAFE_DIP = LEG_LEN - @sqrt((LEG_LEN - STRAFE_SINK) * (LEG_LEN - STRAFE_SINK) - STRAFE_REACH * STRAFE_REACH);

const STRIDE = 0.85 * H;
const WALK_REF_SPEED = WALK_SPEED;
const ARM_SWING = 9.0;
pub const A_BOB = 0.024 * H;
const A_SWAY = 0.009 * H;
const A_PROT = 3.5;
const A_LIST = 2.0;
const TORSO_LEAN = 3.0;
pub const HIP_ADDUCT = 2.0;
pub const FOOT_TOEOUT = 6.0;
const ARM_ABD = 9.0;
pub const IDLE_KNEE = 4.0;
const SIT_Y = 0.115;
const SIT_PITCH = 3.0;
const SIT_SPINE = 8.0;
const SIT_CHEST = 4.0;
const SIT_HIP_FLEX = 52.0;
const SIT_HIP_ABD = 62.0;
const SIT_KNEE = 118.0;
const SIT_ANKLE = 6.0;
const IDLE_ELBOW = 6.0;
const MOVING_EASE = 10.0;

pub fn sampleCurve(tbl: [GAIT_N]f32, phase: f32) f32 {
    const ph = phase - @floor(phase);
    const t = ph * @as(f32, GAIT_N);
    const base: usize = @intFromFloat(@floor(t));
    const a = base % GAIT_N;
    const b = (base + 1) % GAIT_N;
    const f = t - @floor(t);
    return tbl[a] + (tbl[b] - tbl[a]) * f;
}

pub fn advanceGait(phase: *f32, moving: *f32, fwdB: *f32, latB: *f32, speedS: *f32, dt: f32, movedDist: f32, speed: f32, moveYaw: ?f32, facing: f32) void {
    speedS.* = mathx.approach(speedS.*, speed, dt * SPEED_SMOOTH);
    const target: f32 = if (speed > 0.05) 1.0 else 0.0;
    moving.* = mathx.approach(moving.*, target, dt * MOVING_EASE);
    if (moveYaw) |my| {
        const rel = mathx.wrapPi(my - facing);
        fwdB.* = mathx.approach(fwdB.*, mathx.cosf(rel), dt * GAIT_DIR_EASE);
        latB.* = mathx.approach(latB.*, -mathx.sinf(rel), dt * GAIT_DIR_EASE);
    } else {
        fwdB.* = mathx.approach(fwdB.*, 1.0, dt * GAIT_DIR_EASE);
        latB.* = mathx.approach(latB.*, 0.0, dt * GAIT_DIR_EASE);
    }
    if (movedDist > 0) {
        // The SIDESTEP's cycle is FIXED at `STRAFE_CYCLE`: `legChain`'s stance sweep is measured in UNITS off
        // the leg, so scaling one without the other skates the planted foot.
        const sagLen = STRIDE * mathx.clampF(0.55 + 0.45 * speed / WALK_REF_SPEED, 0.8, 2.0) *
            mathx.lerpF(1.0, BACK_STRIDE, mathx.maxF(0, -fwdB.*));
        const strideLen = mathx.lerpF(sagLen, STRAFE_CYCLE, @abs(latB.*));
        phase.* += movedDist / strideLen;
    }
    phase.* -= @floor(phase.*);
}

pub const SOLE_Y: f32 = 0.0;

pub const SolePatch = struct {
    bone: usize,
    heel: f32,
    toe: f32,
    halfW: f32,
    drop: f32,
};

pub fn soleDepth(wx: []const rl.Matrix, patches: []const SolePatch) f32 {
    var lowest: f32 = std.math.floatMax(f32);
    for (patches) |p| {
        for ([_]f32{ -p.halfW, p.halfW }) |x| {
            for ([_]f32{ -p.heel, p.toe }) |z| {
                lowest = mathx.minF(lowest, rl.math.vector3Transform(v3(x, -p.drop, z), wx[p.bone]).y);
            }
        }
    }
    return lowest;
}

// Measured off `footMesh`: the sole cube spans z −0.05·H…+0.14·H, x ±0.0425·H, underside on the ankle plane.
pub const BOOT_SOLE = [_]SolePatch{
    .{ .bone = ANKL, .heel = 0.05 * H, .toe = 0.14 * H, .halfW = 0.0425 * H, .drop = 0.039 * H },
    .{ .bone = ANKR, .heel = 0.05 * H, .toe = 0.14 * H, .halfW = 0.0425 * H, .drop = 0.039 * H },
};

pub fn strafeProt(ph: f32, lat: f32, m: f32) f32 {
    return -STRAFE_PROT * mathx.cosf(std.math.tau * ph) * @abs(lat) * m;
}

pub fn strafeSway(latW: f32, runB: f32) f32 {
    return mathx.lerpF(A_SWAY * (1.0 - 0.6 * runB), STRAFE_SWAY, latW);
}

pub const Pelvis = struct { bob: f32, sway: f32, prot: f32, dip: f32 };

pub fn pelvisChannels(phase: f32, m: f32, fwdB: f32, latB: f32, aprot: f32) Pelvis {
    const twoPi = std.math.tau;
    const latW = @abs(latB) * m;
    return .{
        .bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * phase) * m,
        .sway = strafeSway(latW, 0) * mathx.sinf(twoPi * phase) * m,
        .prot = aprot * mathx.sinf(twoPi * phase) * m * @abs(fwdB) + strafeProt(phase, latB, m),
        .dip = STRAFE_DIP * latW,
    };
}

pub fn deadLegs(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, dk: f32) void {
    setHumanoid(wx, HIPL, rest, mul(rx(-58.0 * dk), rz(-3.0)));
    setHumanoid(wx, KNEEL, rest, rx(8.0 + 98.0 * dk));
    setHumanoid(wx, ANKL, rest, ry(7.0));
    setHumanoid(wx, HIPR, rest, mul(rx(-50.0 * dk), rz(3.0)));
    setHumanoid(wx, KNEER, rest, rx(8.0 + 90.0 * dk));
    setHumanoid(wx, ANKR, rest, ry(-7.0));
}

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const scaleM = mathx.scaleM;
const mul = mathx.mul;
const mul3 = mathx.mul3;
fn lerpM(a: rl.Matrix, b: rl.Matrix, t: f32) rl.Matrix {
    var out: rl.Matrix = undefined;
    inline for (@typeInfo(rl.Matrix).@"struct".fields) |f| {
        @field(out, f.name) = mathx.lerpF(@field(a, f.name), @field(b, f.name), t);
    }
    return out;
}

pub fn rootAt(pos: rl.Vector3) rl.Matrix {
    return tr(pos.x, pos.y, pos.z);
}

fn bump(u: f32, a: f32, b: f32) f32 {
    const mid = 0.5 * (a + b);
    return mathx.pulse(u, a, mid, mid, b);
}

fn burstFrame(axis: rl.Vector3) struct { side: rl.Vector3, up: rl.Vector3 } {
    var side = mathx.perpXZ(axis);
    if (mathx.lenV(side) < 1e-3) side = v3(1, 0, 0);
    side = mathx.normV(side);
    return .{ .side = side, .up = mathx.normV(mathx.crossV(axis, side)) };
}

pub const Attack = enum { light, heavy };

pub const Armament = enum { sword, bow, bell, shield, wand };

pub const Arm = Armament;
pub const Off = Armament;

pub const HAND_SLOTS: usize = 2;

pub const RIGHT: usize = 0;
pub const LEFT: usize = 1;

pub fn armSwings(a: Armament) bool {
    return switch (a) {
        .sword => true,
        // The bow's R1/R2 are the quick and the aimed shot — they are not SWINGS, and the loose is routed on
        // `bowOut` at the input. What this answers is whether the blade capsule can ever go live.
        .bow => false,
        .bell => false,
        .shield => false,
        .wand => false,
    };
}

pub fn armTwoHanded(a: Armament) bool {
    return a == .bow;
}

pub fn handsHold(arm: Armament, off: Armament, a: Armament) bool {
    if (armTwoHanded(arm)) return a == arm;
    if (armTwoHanded(off)) return a == off;
    return arm == a or off == a;
}

pub const Queued = union(enum) { attack: Attack, roll: rl.Vector3 };

pub const Hero = struct {
    mesh: [N]rl.Mesh,
    bow: rl.Mesh,
    bowString: rl.Mesh,
    bowNock: rl.Mesh,
    shield: rl.Mesh,
    wand: rl.Mesh,
    bell: rl.Mesh,
    dirk: rl.Mesh,
    club: rl.Mesh,
    roots: [ROOT_KINDS]rl.Mesh,
    guitar: rl.Mesh,
    mat: rl.Material,
    rest: [N]rl.Vector3,
    xf: [N]rl.Matrix = undefined,

    pos: rl.Vector3 = mathx.zero3,
    /// Whole-body pitch from the SLOPE he is standing on, in degrees, + = uphill ahead (lean into the climb).
    slopePitch: f32 = 0,
    facing: f32 = 0, // yaw radians, 0 = +Z
    phase: f32 = 0,
    moving: f32 = 0,
    speed: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    elapsed: f32 = 0,
    rolling: bool = false,
    rolls: u32 = 0,
    rollT: f32 = 0,
    rollDir: rl.Vector3 = mathx.zero3,
    rollYaw: f32 = 0,
    rollSide: f32 = -1,
    rollVar: f32 = 1,
    lift: f32 = 0,
    /// The WORLD height of his feet while airborne, integrated under gravity; `lift` is DERIVED off it every
    /// frame. Run off a ledge and the datum falls away underneath, so the gap opens on its own — where a lift
    /// integrated over a moving datum sinks with the ground it was measured from.
    airY: f32 = 0,
    vertVel: f32 = 0,
    jumping: bool = false,
    jumps: u32 = 0,
    airYaw: f32 = 0,
    airSpeed: f32 = 0,
    landed: bool = false,
    landT: f32 = mathx.LONG_AGO,
    attacking: bool = false,
    atkT: f32 = 0,
    queued: ?Queued = null,
    atkHeavy: bool = false,
    atkAlt: bool = false,
    swings: u32 = 0,
    bladeA: rl.Vector3 = mathx.zero3,
    bladeB: rl.Vector3 = mathx.zero3,
    bladeA0: rl.Vector3 = mathx.zero3,
    bladeB0: rl.Vector3 = mathx.zero3,
    hitWasActive: bool = false,
    trail: foemod.Trail(TRAIL_N) = .{},
    fx: [FX_N]foemod.Particle = [_]foemod.Particle{.{}} ** FX_N,
    fxHead: usize = 0,
    levinPath: [LEVIN_BOLT_PTS]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** LEVIN_BOLT_PTS,
    levinT: f32 = 0,
    sheet: statsmod.Sheet = .{},
    perk: ptree.Bonus = .{},
    worn: Worn = .{},
    vit: combat.Vitals = freshVitals(.{}),
    stam: combat.Stamina = .{},
    fp: combat.Focus = .{},
    souls: combat.Souls = .{},
    flasks: combat.Flasks = .{},
    quick: combat.Quick = .{},
    quiver: combat.Quiver = .{},
    regen: combat.Regen = .{},
    baseRes: combat.Resists = .{},
    ward: combat.Timed = .{},
    grease: combat.Timed = .{},
    steady: combat.Timed = .{},
    poison: combat.Status = .{},
    drinking: bool = false,
    drinkT: f32 = 0,
    poured: bool = false,
    stamRefused: f32 = 0,
    sprinting: bool = false,
    aimLean: f32 = 0,
    aimLeanWant: f32 = 0,
    arm: Armament = .sword,
    armAlt: Armament = .bow,
    aiming: bool = false,
    aimB: f32 = 0,
    shooting: bool = false,
    shotT: f32 = 0,
    shotAimed: bool = false,
    shotArrow: combat.ArrowKind = .plain,
    atkRow: item.Arm = item.bareArm(.hand_sword),
    atkBlade: Blade = .sword,
    shotRow: item.Arm = item.bareArm(.hand_bow),
    loosed: bool = false,
    shots: u32 = 0,
    drawAmt: f32 = 0,
    stringXf: [2]rl.Matrix = undefined,
    nockXf: rl.Matrix = undefined,
    nockVis: bool = false,
    lastNock: rl.Vector3 = mathx.zero3,
    off: Armament = .shield,
    offAlt: Armament = .wand,
    spell: combat.Spell = .bolt,
    casting: bool = false,
    castT: f32 = 0,
    castAlt: bool = false,
    casts: u32 = 0,
    thrown: bool = false,
    breathAcc: f32 = 0,
    spirit: combat.SpiritKind = .wolf,
    ringing: bool = false,
    ringT: f32 = 0,
    rang: bool = false,
    rootSites: [ROOT_SITES]RootSite = [_]RootSite{.{}} ** ROOT_SITES,
    rootHead: usize = 0,
    moteAcc: f32 = 0,
    tipPrev: rl.Vector3 = mathx.zero3,
    fpRefused: f32 = 0,
    guarding: bool = false,
    guardB: f32 = 0,
    blockT: f32 = mathx.LONG_AGO,
    parrying: bool = false,
    parryT: f32 = 0,
    parries: u32 = 0,
    held: bool = false,
    stun: combat.StunKind = .none,
    stunT: f32 = 0,
    hurtFlash: f32 = 0,
    dead: bool = false,
    deathT: f32 = 0,
    spawnPos: rl.Vector3 = mathx.zero3,
    spawnFacing: f32 = 0,

    speedS: f32 = 0,
    blendT: f32 = mathx.LONG_AGO,
    blendXf: [N]rl.Matrix = undefined,
    resting: bool = false,
    restT: f32 = 0,

    pub fn init(shader: rl.Shader) Hero {
        const mat = gfx.material(shader, "hero");
        return .{
            .mesh = buildMeshes(),
            .bow = archer.bowMesh(),
            .bowString = archer.stringMesh(),
            .bowNock = archer.nockArrowMesh(),
            .shield = shieldMesh(),
            .wand = wandMesh(),
            .bell = bellMesh(),
            .dirk = dirkMesh(),
            .club = clubMesh(),
            .roots = blk: {
                var out: [ROOT_KINDS]rl.Mesh = undefined;
                for (&out, 0..) |*m, i| m.* = rootTendrilMesh(@intCast(i));
                break :blk out;
            },
            .guitar = guitarMesh(),
            .mat = mat,
            .rest = restPositions(),
        };
    }

    pub fn setShader(self: *Hero, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    pub fn sit(self: *Hero, on: bool, pos: rl.Vector3, yaw: f32) void {
        self.resting = on;
        self.restT = 0;
        if (!on) self.startXfade();
        if (!on) return;
        self.pos = pos;
        self.facing = yaw;
        self.speed = 0;
        self.speedS = 0;
        self.moving = 0;
        self.clearAir();
        self.dropActions();
        self.sprinting = false;
        self.guardB = 0;
        self.aimB = 0;
        self.stun = .none;
        self.hurtFlash = 0;
        self.makeWhole();
    }

    pub fn applyPerks(self: *Hero, b: ptree.Bonus) void {
        self.perk = b;
        self.baseRes = b.res;
        self.resheet();
        self.makeWhole();
    }

    /// A bonfire, and a death is a return to one. The three bars take their SIZE from the sheet here and
    /// nowhere else, so a raised attribute cannot leave one at its old length.
    fn makeWhole(self: *Hero) void {
        self.vit = freshVitals(self.sheet);
        self.refitHp();
        self.stam.max = self.sheet.stamina();
        self.fp.max = fpMaxOf(self.sheet, self.worn, self.perk);
        self.stam.reset();
        self.fp.reset();
        self.regen.reset();
        self.poison.reset();
        self.ward.reset();
        self.grease.reset();
        self.steady.reset();
        self.vit.poiseRate = 1;
        self.settleResists();
        self.flasks.refill();
        self.quiver.refill();
    }

    fn tickClocks(self: *Hero, dt: f32) void {
        // Every one-frame edge is cleared HERE, not in its own update: a frame long enough to cross both the
        // release knot and the end of the shot sets `loosed` and drops `shooting` in the same call, so nothing
        // would run `updateShot` again to clear it and game.zig loosed a fresh shaft every frame after.
        self.loosed = false;
        self.thrown = false; // the cast's own one-frame edge, cleared here for the reason `loosed` is
        self.rang = false;
        self.landed = false;
        self.elapsed += dt;
        if (self.levinT > 0) self.levinT = mathx.maxF(0, self.levinT - dt);
        self.trail.age(dt);
        self.blendT = @min(self.blendT + dt, mathx.LONG_AGO);
        // Stamina must advance exactly ONCE per frame whichever path runs, or `--shot` drains every swing it
        // takes and never refills. The cast is in the PAUSE list but not the DRAIN argument: it bills FP.
        // **THE ROGUE'S BAR REFILLS FASTER** (`passivetree.Grant.stamRegen`) — stamped on the pool rather
        // than multiplied into the tick, because `Stamina.regenRate` is the dial that already exists and the
        // brew rides beside it.
        self.stam.regenRate = self.perk.stamRegen;
        if (!self.held) self.stam.tick(dt, self.sprinting, self.attacking or self.rolling or self.guarding or self.casting or self.parrying);
        // **THE TWO SLOW REFILLS THE TREE BUYS**, and they run on the same one-a-frame rule the stamina does.
        // HP is the first thing in the game that comes back without an item; FP the blue bar's own answer.
        // NOT gated on the poise clock — this is a trickle, not the stagger refill, and a warrior who cannot
        // heal while being hit has bought nothing at all. Neither can exceed its pool: `heal`/`restore` clamp.
        if (!self.held and !self.dead) {
            if (self.perk.hpRegen > 0) _ = self.vit.heal(self.perk.hpRegen * dt);
            if (self.perk.fpRegen > 0) _ = self.fp.restore(self.perk.fpRegen * dt);
        }
        self.stamRefused = @max(0, self.stamRefused - dt);
        self.fpRefused = @max(0, self.fpRefused - dt);
        self.guardB = mathx.approach(self.guardB, if (self.guarding or self.parrying) 1.0 else 0.0, dt * GUARD_BLEND_RATE);
        self.aimB = mathx.approach(self.aimB, if (self.aiming) 1.0 else 0.0, dt * BOW_BLEND_RATE);
        self.aimLean = mathx.approach(self.aimLean, self.aimLeanWant, dt * AIM_LEAN_RATE);
        self.blockT = @min(self.blockT + dt, mathx.LONG_AGO);
        self.landT = @min(self.landT + dt, mathx.LONG_AGO);
        self.tickAir(dt);
        self.souls.tick(dt);
        foemod.tickParticles(&self.fx, dt, self.pos.y);
        for (&self.rootSites) |*s| s.t = @min(s.t + dt, mathx.LONG_AGO);
    }

    pub fn update(self: *Hero, dt: f32, movedDist: f32, speed: f32, moveYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = speed;
        advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist, speed, moveYaw, self.facing);
    }

    pub fn footPos(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + self.lift, self.pos.z);
    }
    pub fn footY(self: *const Hero) f32 {
        return self.pos.y + self.lift;
    }
    pub fn airborne(self: *const Hero) bool {
        return self.jumping;
    }

    pub fn startJump(self: *Hero, dir: rl.Vector3, speed: f32) bool {
        if (self.committed() or self.dead or self.staggered() or self.resting) return false;
        self.jumping = true;
        self.jumps +%= 1;
        self.airY = self.pos.y;
        self.vertVel = JUMP_V0;
        self.airSpeed = if (mathx.lenXZ(dir) > 0.01) speed else 0;
        self.airYaw = if (self.airSpeed > 0.01) mathx.headingXZ(dir) else self.facing;
        self.startXfade();
        return true;
    }

    fn tickAir(self: *Hero, dt: f32) void {
        if (self.held) return;
        if (!self.jumping) {
            self.lift = 0;
            return;
        }
        self.airY += self.vertVel * dt - 0.5 * JUMP_G * dt * dt;
        self.vertVel -= JUMP_G * dt;
        if (self.airY <= self.pos.y) {
            self.airY = self.pos.y;
            self.lift = 0;
            self.vertVel = 0;
            self.jumping = false;
            self.landed = true;
            self.landT = 0;
            self.startXfade();
            self.fireQueued();
            return;
        }
        self.lift = self.airY - self.pos.y;
    }

    pub fn steerAir(self: *Hero, dt: f32, dir: rl.Vector3) void {
        if (self.airSpeed <= 0.01 or mathx.lenXZ(dir) < 0.01) return;
        self.airYaw = mathx.approachAngle(self.airYaw, mathx.headingXZ(dir), AIR_TURN_RATE * dt);
    }

    pub fn updateAir(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = self.airSpeed;
        self.speedS = mathx.approach(self.speedS, self.airSpeed, dt * SPEED_SMOOTH);
        const want = faceYaw orelse self.airYaw;
        self.facing = mathx.approachAngle(self.facing, want, ROLL_YAW_RATE * dt);
        self.pose();
    }

    pub fn startRoll(self: *Hero, dir: rl.Vector3) void {
        if (self.committed() or self.dead or self.staggered() or self.resting) return;
        if (!self.stam.canAct()) {
            self.refuse();
            return;
        }
        self.stam.spend(combat.STAM_ROLL * self.perk.rollStam);
        var d = v3(dir.x, 0, dir.z);
        if (mathx.lenXZ(d) < 0.1) d = mathx.headingDir(self.facing);
        d = mathx.normV(d);
        self.rolling = true;
        self.rolls +%= 1;
        self.rollT = 0;
        self.rollDir = d;
        self.rollYaw = mathx.headingXZ(d);
        const leadL = sampleCurve(HIP_FLEX, self.phase) > sampleCurve(HIP_FLEX, self.phase + 0.5);
        self.rollSide = if (self.moving > 0.5 and leadL) 1.0 else -1.0;
        const h = (self.phase + self.elapsed * 0.61) * 7.31;
        self.rollVar = mathx.lerpF(ROLL_VAR_LO, ROLL_VAR_HI, h - @floor(h));
        self.startXfade();
    }

    pub fn updateRoll(self: *Hero, dt: f32, bounds: f32) void {
        self.tickClocks(dt);
        self.facing = mathx.approachAngle(self.facing, self.rollYaw, dt * ROLL_YAW_RATE);
        const u = mathx.clampF(self.rollT / ROLL_DUR, 0, 1);
        const peak = ROLL_DIST / (ROLL_DUR * 0.5 * (ROLL_BRAKE_A + ROLL_BRAKE_B));
        const speed = peak * (1.0 - mathx.smoothstep(ROLL_BRAKE_A, ROLL_BRAKE_B, u));
        const moved = speed * dt;
        mathx.stepXZ(&self.pos, self.rollDir, moved, bounds);
        self.speed = speed;
        self.speedS = mathx.approach(self.speedS, speed, dt * SPEED_SMOOTH);
        self.rollT += dt;
        self.pose();
        if (self.rollT >= ROLL_DUR) {
            self.rolling = false;
            self.startXfade();
            self.fireQueued();
        }
    }


    pub fn committed(self: *const Hero) bool {
        return self.jumping or self.rolling or self.attacking or self.drinking or self.shooting or self.casting or self.parrying or self.ringing;
    }

    pub fn holds(self: *const Hero, a: Armament) bool {
        return handsHold(self.arm, self.off, a);
    }

    /// **WHICH HAND SOMETHING IS IN.** The RIGHT wins if somehow both, since that is the hand the rig's own
    /// held bone is parented to and the mirror is the exception rather than the rule. ONE COPY: every
    /// armament that is POSED, MEASURED or EMITTED FROM asks this, and transcribed per weapon it was already
    /// three different tests — which is how the rod's own tip kept answering for a hand that was not holding it.
    fn heldLeft(self: *const Hero, a: Armament) bool {
        return self.arm != a and self.off == a and self.offInHand();
    }

    fn heldRight(self: *const Hero, a: Armament) bool {
        return self.arm == a;
    }

    pub fn swordLeft(self: *const Hero) bool {
        return self.heldLeft(.sword);
    }

    pub fn bellLeft(self: *const Hero) bool {
        return self.heldLeft(.bell);
    }

    pub fn wandLeft(self: *const Hero) bool {
        return !self.heldRight(.wand);
    }

    /// …and THE BOARDS, which the guard, the parry and the sparks off their face are all measured from.
    pub fn shieldLeft(self: *const Hero) bool {
        return !self.heldRight(.shield);
    }

    pub fn bowOut(self: *const Hero) bool {
        return self.holds(.bow);
    }

    pub fn bellOut(self: *const Hero) bool {
        return self.holds(.bell);
    }

    /// Not the same question as which one is EQUIPPED: a raised bow takes the OTHER hand to the string too, so
    /// whatever is in it is not in it while the bow is up. Everything else leaves it free — the bell included,
    /// which is rung one-handed. Asked here rather than cleared on the swap, so it cannot stale.
    pub fn offInHand(self: *const Hero) bool {
        return !armTwoHanded(self.arm) and !armTwoHanded(self.off);
    }

    pub fn armInHand(self: *const Hero) Armament {
        return if (armTwoHanded(self.off)) self.off else self.arm;
    }

    pub fn wandOut(self: *const Hero) bool {
        return self.holds(.wand);
    }

    pub fn shieldOut(self: *const Hero) bool {
        return self.holds(.shield);
    }

    fn swapHand(self: *Hero, live: *Armament, alt: *Armament) bool {
        if (self.committed() or self.staggered() or self.dead or self.resting) return false;
        if (live.* == alt.*) return false;
        std.mem.swap(Armament, live, alt);
        self.drawAmt = 0;
        self.startXfade();
        return true;
    }

    pub fn swapOff(self: *Hero) bool {
        return self.swapHand(&self.off, &self.offAlt);
    }

    pub fn swapArm(self: *Hero) bool {
        return self.swapHand(&self.arm, &self.armAlt);
    }

    fn cell(self: *Hero, hand: usize, slot: usize) *Armament {
        if (hand == RIGHT) return if (slot == 0) &self.arm else &self.armAlt;
        return if (slot == 0) &self.off else &self.offAlt;
    }

    fn rack(self: *Hero) [4]*Armament {
        return .{ &self.arm, &self.armAlt, &self.off, &self.offAlt };
    }

    /// **THERE IS ONE OF EACH, AND THE RACK IS FOUR CELLS.** He carried one sword, and both hands could hold
    /// it: the same blade drawn twice, blocked with, swung with, and swapped between. Taking a thing that is
    /// already in another cell SWAPS the two rather than refusing — what stood here goes where it came from —
    /// so the four stay distinct without a press ever being eaten.
    pub fn equip(self: *Hero, hand: usize, slot: usize, a: Armament) bool {
        if (self.committed() or self.staggered() or self.dead or self.resting) return false;
        const into = self.cell(hand, slot);
        if (into.* == a) return false;
        const wasArm = self.arm;
        const wasOff = self.off;
        const displaced = into.*;
        into.* = a;
        for (self.rack()) |c| {
            if (c != into and c.* == a) c.* = displaced;
        }
        if (self.arm != wasArm or self.off != wasOff) {
            self.drawAmt = 0;
            self.startXfade();
        }
        return true;
    }

    /// A save written before the rack was distinct can hold the same armament twice; the first cell keeps it
    /// and the later one takes whatever nothing else is holding.
    pub fn tidyHands(self: *Hero) void {
        var seen = std.EnumSet(Armament).initEmpty();
        for (self.rack()) |c| {
            if (!seen.contains(c.*)) {
                seen.insert(c.*);
                continue;
            }
            for (std.enums.values(Armament)) |a| {
                if (seen.contains(a)) continue;
                c.* = a;
                seen.insert(a);
                break;
            }
        }
    }

    pub fn slotAt(self: *const Hero, hand: usize, slot: usize) Armament {
        const live = if (hand == RIGHT) self.arm else self.off;
        const alt = if (hand == RIGHT) self.armAlt else self.offAlt;
        return if (slot == 0) live else alt;
    }

    pub fn setAim(self: *Hero, want: bool) void {
        self.aiming = want and self.canAim();
    }

    /// WHAT HE IS SWINGING AT, in degrees off his own eye line (+ = below him).
    pub fn aimAtPitch(self: *Hero, deg: ?f32) void {
        self.aimLeanWant = mathx.clampF(AIM_LEAN_BIAS + (deg orelse 0), -AIM_LEAN_UP, AIM_LEAN_DOWN);
    }

    fn dropAim(self: *Hero) void {
        self.aiming = false;
        self.shooting = false;
        self.loosed = false;
        self.drawAmt = 0;
        self.nockVis = false;
    }

    pub fn canAim(self: *const Hero) bool {
        return self.bowOut() and (!self.committed() or self.shooting) and
            !self.staggered() and !self.dead and !self.sprinting and !self.resting and self.stam.canAct();
    }

    pub fn requestShot(self: *Hero, aimed: bool) void {
        if (!self.bowOut() or self.dead or self.staggered()) return;
        if (aimed and !self.aiming) return;
        if (self.committed()) return;
        self.startShot(aimed);
    }

    fn startShot(self: *Hero, aimed: bool) void {
        if (!self.stam.canAct()) {
            self.refuse();
            return;
        }
        if (!self.quiver.take()) {
            self.refuse();
            return;
        }
        self.shotArrow = self.quiver.sel;
        self.shotRow = self.armOf(.hand_bow);
        self.stam.spend(@as(f32, if (aimed) combat.STAM_AIMED else combat.STAM_SHOT) * self.shotRow.stam);
        self.shooting = true;
        self.shotAimed = aimed;
        self.shotT = 0;
        self.loosed = false;
        self.shots +%= 1;
        self.startXfade();
    }

    pub fn updateShot(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        const dur: f32 = self.shotDur(self.shotAimed);
        const at: f32 = self.shotAt();
        const was = self.shotT / dur;
        self.shotT += dt;
        // A one-frame EDGE: a long frame cannot fire twice, a short one cannot miss the knot.
        if (was < at and self.shotT / dur >= at) self.loosed = true;
        self.pose();
        if (self.shotT >= dur) {
            self.shooting = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    pub fn nockWorld(self: *const Hero) rl.Vector3 {
        return self.lastNock;
    }

    fn bowLevels(self: *const Hero) struct { up: f32, pull: f32 } {
        if (!self.bowOut()) return .{ .up = 0, .pull = 0 };
        if (self.shooting) {
            const at: f32 = self.shotAt();
            const u = self.shotU();
            const up = if (self.shotAimed)
                mathx.maxF(self.aimB, mathx.smoothstep(0, at, u))
            else
                mathx.smoothstep(0, at * 0.7, u);
            return .{ .up = up, .pull = up * (1.0 - mathx.smoothstep(at, at + BOW_SNAP, u)) };
        }
        return .{ .up = self.aimB, .pull = self.aimB };
    }

    fn refuse(self: *Hero) void {
        self.stamRefused = combat.STAM_REFUSE_FLASH;
    }

    fn refuseFp(self: *Hero) void {
        self.fpRefused = combat.STAM_REFUSE_FLASH;
    }


    pub fn setGuard(self: *Hero, want: bool) void {
        self.guarding = want and self.canGuard();
    }

    fn shieldArm(self: *const Hero) bool {
        return self.shieldOut() and !self.committed() and !self.staggered() and !self.dead and !self.sprinting and !self.resting;
    }

    pub fn canGuard(self: *const Hero) bool {
        return self.shieldArm() and self.stam.canAct();
    }

    /// It asks nothing about whether the boards are RAISED. Answered THROUGH `canGuard` so the two cannot drift.
    pub fn canParry(self: *const Hero) bool {
        return self.canGuard();
    }

    /// NEVER BUFFERED: a parry is a window the player picked a moment for. Reports whether one started, so
    /// the caller's tell cannot sound for a shove the bar refused.
    pub fn requestParry(self: *Hero) bool {
        if (!self.shieldArm()) return false;
        if (!self.stam.canAct()) {
            self.refuse();
            return false;
        }
        self.stam.spend(combat.STAM_PARRY);
        self.parrying = true;
        self.parryT = 0;
        self.parries +%= 1;
        self.guarding = false;
        self.startXfade();
        return true;
    }

    pub fn updateParry(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        self.parryT += dt;
        const punchT = PARRY_PUNCH_AT * PARRY_DUR;
        if (self.parryT >= punchT and self.parryT - dt < punchT) self.parryGlint();
        // Pose BEFORE clearing `parrying` — the roll's one-frame contract.
        self.pose();
        if (self.parryT >= PARRY_DUR) {
            self.parrying = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    pub fn parryLive(self: *const Hero) bool {
        return self.parrying and self.parryT >= PARRY_OPEN and self.parryT < PARRY_SHUT;
    }

    pub fn noteParry(self: *Hero) void {
        self.blockT = 0;
        self.parrySparks();
    }

    /// MEASURED off the fit matrix's own constants, so re-hanging the shield keeps the sparks on its face —
    /// AND MIRRORED WITH IT (`shieldFit`), since both the hub and the normal are lateral. Taken off a fixed
    /// `WRL`, boards equipped RIGHT threw every parry shower and every block gout off the other hand.
    pub fn shieldFaceWorld(self: *const Hero) struct { at: rl.Vector3, n: rl.Vector3 } {
        const left = self.shieldLeft();
        const sd: f32 = if (left) 1.0 else -1.0;
        const wrist = self.xf[if (left) WRL else WRR];
        const hub = v3(sd * SHIELD_HUB.x, SHIELD_HUB.y, SHIELD_HUB.z);
        const at = rl.math.vector3Transform(hub, wrist);
        const out = rl.math.vector3Transform(mathx.addV(hub, v3(sd * SHIELD_N.x, SHIELD_N.y, SHIELD_N.z)), wrist);
        return .{ .at = at, .n = mathx.normV(mathx.subV(out, at)) };
    }

    fn parrySparks(self: *Hero) void {
        const f = self.shieldFaceWorld();
        const fr = burstFrame(f.n);
        const side = fr.side;
        const up = fr.up;
        const at = mathx.addV(f.at, mathx.scaleV(f.n, SPARK_PROUD));
        var rng = foemod.fxStream(@floatFromInt(self.parries), 733.0, 0x8B06);
        var i: u32 = 0;
        while (i < PARRY_SPARKS) : (i += 1) {
            const a = rng.angle();
            const fan = rng.range(0.35, 1.0) * PARRY_SPARK_FAN;
            const v = mathx.addV(
                mathx.scaleV(f.n, rng.range(PARRY_SPARK_OUT_LO, PARRY_SPARK_OUT_HI)),
                mathx.addV(mathx.scaleV(side, mathx.cosf(a) * fan), mathx.scaleV(up, mathx.sinf(a) * fan)),
            );
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.16, 0.72), rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI), 0.003, if (rng.float() < 0.45) PARRY_SPARK_HOT else PARRY_SPARK, PARRY_SPARK_GRAV);
        }
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(f.n, 0.8), PARRY_FLASH_LIFE, PARRY_FLASH_R, PARRY_FLASH_R * 0.25, PARRY_SPARK_HOT, 0);
    }

    /// **THE FOG PARTING ROUND HIM AS HE CROSSES A GATE.** Off the hero's OWN pool, so it ticks, fades and
    /// draws with everything else he sheds and needs no second pool anywhere. The motes are the sheet's own
    /// colour, they drift OUTWARD and UPWARD off his chest rather than falling, and they are long-lived and
    /// wide — vapour torn open, not grit.
    pub fn fogWake(self: *Hero, at: rl.Vector3, along: rl.Vector3, n: u32) void {
        const side = mathx.perpXZ(along);
        var rng = foemod.fxStream(self.elapsed, 733.0, 0xF06);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = rng.angle();
            const out = rng.range(FOG_WAKE_OUT_LO, FOG_WAKE_OUT_HI);
            const v = mathx.addV(
                mathx.scaleV(side, mathx.cosf(a) * out),
                v3(0, @abs(mathx.sinf(a)) * out * 0.8 + FOG_WAKE_RISE, 0),
            );
            const p = mathx.addV(at, v3(rng.signed() * 0.34, rng.signed() * 0.42, rng.signed() * 0.18));
            foemod.emitParticle(&self.fx, &self.fxHead, p, v, rng.range(FOG_WAKE_LIFE_LO, FOG_WAKE_LIFE_HI), rng.range(FOG_WAKE_R0_LO, FOG_WAKE_R0_HI), FOG_WAKE_R1, if (rng.float() < 0.45) propfx.FOG_WAKE_PALE else propfx.FOG_WAKE_DEEP, FOG_WAKE_GRAV);
        }
    }

    pub fn blockSparks(self: *Hero, weight: f32) void {
        const f = self.shieldFaceWorld();
        const fr = burstFrame(f.n);
        const at = mathx.addV(f.at, mathx.scaleV(f.n, SPARK_PROUD));
        const w = mathx.clampF(weight, 0, 1);
        const n: u32 = @intFromFloat(mathx.lerpF(BLOCK_GRIT_MIN, BLOCK_GRIT_MAX, w));
        var rng = foemod.fxStream(self.elapsed, 911.0, 0x8B08);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = rng.angle();
            const fan = rng.range(0.30, 1.0) * BLOCK_GRIT_FAN;
            const v = mathx.addV(
                mathx.scaleV(f.n, rng.range(BLOCK_GRIT_OUT_LO, BLOCK_GRIT_OUT_HI)),
                mathx.addV(mathx.scaleV(fr.side, mathx.cosf(a) * fan), mathx.scaleV(fr.up, mathx.sinf(a) * fan)),
            );
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(BLOCK_GRIT_LIFE_LO, BLOCK_GRIT_LIFE_HI), rng.range(0.010, 0.022), 0.004, if (rng.float() < 0.5) BLOCK_GRIT else BLOCK_GRIT_DARK, BLOCK_GRIT_GRAV);
        }
        const ns: u32 = @intFromFloat(mathx.lerpF(BLOCK_SPARK_MIN, BLOCK_SPARK_MAX, w));
        var j: u32 = 0;
        while (j < ns) : (j += 1) {
            const a = rng.angle();
            const fan = rng.range(0.35, 1.0) * PARRY_SPARK_FAN * BLOCK_SPARK_FAN_K;
            const v = mathx.addV(
                mathx.scaleV(f.n, rng.range(PARRY_SPARK_OUT_LO, PARRY_SPARK_OUT_HI)),
                mathx.addV(mathx.scaleV(fr.side, mathx.cosf(a) * fan), mathx.scaleV(fr.up, mathx.sinf(a) * fan)),
            );
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.16, 0.38), rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI), 0.003, if (rng.float() < 0.34) PARRY_SPARK_HOT else PARRY_SPARK, PARRY_SPARK_GRAV);
        }
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(f.n, 0.25), BLOCK_PUFF_LIFE, BLOCK_PUFF_R * (0.6 + 0.4 * w), BLOCK_PUFF_R * 1.6, BLOCK_GRIT_DARK, 1.5);
    }

    /// The swipe's own light — `parrySparks`' construction at a fraction of its size, all of it HOT: what
    /// separates a glint from a catch is COUNT and fan, never colour, or a whiff reads as half a hit.
    fn parryGlint(self: *Hero) void {
        const f = self.shieldFaceWorld();
        const fr = burstFrame(f.n);
        const side = fr.side;
        const up = fr.up;
        const at = mathx.addV(f.at, mathx.scaleV(f.n, SPARK_PROUD));
        var rng = foemod.fxStream(@floatFromInt(self.parries), 419.0, 0x8B07);
        var i: u32 = 0;
        while (i < PARRY_GLINT) : (i += 1) {
            const along = rng.range(-1.0, 1.0);
            const from = mathx.addV(at, mathx.scaleV(side, along * PARRY_GLINT_SPAN));
            const a = rng.angle();
            const fan = rng.range(0.35, 1.0) * PARRY_GLINT_FAN;
            const v = mathx.addV(
                mathx.addV(
                    mathx.scaleV(f.n, rng.range(PARRY_SPARK_OUT_LO * 0.5, PARRY_SPARK_OUT_HI * 0.4)),
                    mathx.scaleV(side, along * PARRY_GLINT_FAN * PARRY_GLINT_TRAIL),
                ),
                mathx.addV(mathx.scaleV(side, mathx.cosf(a) * fan * 0.4), mathx.scaleV(up, mathx.sinf(a) * fan)),
            );
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, rng.range(0.05, 0.15), rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI), 0.003, PARRY_SPARK_HOT, PARRY_SPARK_GRAV);
        }
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(f.n, 0.9), PARRY_FLASH_LIFE, PARRY_GLINT_FLASH_R, PARRY_GLINT_FLASH_R * 0.25, PARRY_SPARK_HOT, 0);
    }

    pub fn canCast(self: *const Hero) bool {
        return self.wandOut() and !self.committed() and !self.staggered() and !self.dead and
            !self.resting and !self.sprinting;
    }

    pub fn requestCast(self: *Hero) bool {
        if (!self.canCast()) return false;
        return self.startCast();
    }

    pub fn castCost(self: *const Hero) f32 {
        return combat.spellFp(self.spell) * self.perk.spellCost;
    }

    pub fn cycleSpell(self: *Hero) bool {
        if (self.dead or self.casting) return false;
        self.spell = switch (self.spell) {
            .bolt => .roots,
            .roots => .rime,
            .rime => .levin,
            .levin => .siphon,
            .siphon => .lance,
            .lance => .sunder,
            .sunder => .bolt,
        };
        return true;
    }

    fn startCast(self: *Hero) bool {
        if (!self.fp.spend(self.castCost())) {
            self.refuseFp();
            return false;
        }
        self.casting = true;
        self.castT = 0;
        self.thrown = false;
        self.moteAcc = 0;
        self.breathAcc = 0;
        self.castAlt = !self.castAlt;
        self.casts +%= 1;
        self.startXfade();
        return true;
    }

    pub fn updateCast(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        const was = self.castT / CAST_DUR;
        self.castT += dt * self.perk.castSpeed;
        // A one-frame EDGE, `updateShot`'s: a long frame cannot throw twice, a short one cannot miss it.
        if (was < CAST_AT and self.castT / CAST_DUR >= CAST_AT) self.thrown = true;
        self.pose();
        if (self.castT / CAST_DUR < CAST_AT) self.gatherMotes(dt);
        if (self.breathLive()) self.pourBreath(dt);
        if (self.castT >= self.castSpan()) {
            self.casting = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    pub fn canRing(self: *const Hero) bool {
        return self.bellOut() and !self.committed() and !self.staggered() and !self.dead and
            !self.resting and !self.sprinting;
    }

    pub fn ringCost(self: *const Hero) f32 {
        return combat.spiritFp(self.spirit) * self.perk.spellCost * charmOf(self.worn).spiritFp;
    }

    /// R1 with the bell out, PRESSED — committed, so an edge. Reports whether one STARTED, since the caller's
    /// voice must not sound for a ring the pool refused.
    pub fn requestRing(self: *Hero) bool {
        if (!self.canRing()) return false;
        if (!self.fp.spend(self.ringCost())) {
            self.refuseFp();
            return false;
        }
        self.ringing = true;
        self.ringT = 0;
        self.rang = false;
        self.startXfade();
        return true;
    }

    pub fn updateRing(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        const was = self.ringT / RING_DUR;
        self.ringT += dt;
        // The one-frame edge, `updateCast`'s: a long frame cannot ring twice and a short one cannot miss it.
        if (was < RING_AT and self.ringT / RING_DUR >= RING_AT) self.rang = true;
        self.pose();
        if (self.ringT >= RING_DUR) {
            self.ringing = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    pub fn stageRing(self: *Hero, u: f32) void {
        self.arm = .bell;
        self.ringing = true;
        self.ringT = mathx.clampF(u, 0, 1) * RING_DUR;
        self.pose();
    }

    fn ringU(self: *const Hero) f32 {
        if (!self.ringing) return 0;
        return mathx.clampF(self.ringT / RING_DUR, 0, 1);
    }

    pub fn castSpan(self: *const Hero) f32 {
        return CAST_DUR + if (self.spell == .rime) combat.RIME_DUR else 0;
    }

    fn breathAt() f32 {
        return CAST_DUR * CAST_AT;
    }

    /// IS THE CONE OPEN THIS FRAME — the one question game.zig asks to know whether anything is being breathed
    /// on. Off the cast clock rather than a flag of its own: `AN EFFECT'S CLOCK IS DERIVED FROM THE
    /// MECHANIC'S, NEVER PARALLEL TO IT`, and a second bool here could disagree with the pose.
    pub fn breathLive(self: *const Hero) bool {
        if (!self.casting or self.spell != .rime) return false;
        return self.castT >= breathAt() and self.castT < breathAt() + combat.RIME_DUR;
    }

    pub fn breathU(self: *const Hero) f32 {
        if (!self.casting or self.spell != .rime) return 0;
        return mathx.clampF((self.castT - breathAt()) / combat.RIME_DUR, 0, 1);
    }

    /// WHERE THE BREATH LEAVES HIM — **off the POSED ROD**, so it rides the wrist and the kick rather than
    /// hanging in front of a hand that has moved. `wandTipWorld` is the stone itself and the last centimetres
    /// are stepped out along his FACING rather than along the rod's own axis: what the cone is aimed down is
    /// `facing` (`breathDir`), and a nozzle taken off the wand's local forward would sit off the line the
    /// mechanic actually tests. The ONE point both the picture and the cone are measured from.
    pub fn breathMouth(self: *const Hero) rl.Vector3 {
        const tip = self.wandTipWorld();
        const d = mathx.headingDir(self.facing);
        return v3(tip.x + d.x * BREATH_NOZZLE_FWD, tip.y, tip.z + d.z * BREATH_NOZZLE_FWD);
    }

    pub fn breathDir(self: *const Hero) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }

    fn pourBreath(self: *Hero, dt: f32) void {
        var rng = foemod.fxStream(self.castT + @as(f32, @floatFromInt(self.casts)), 691.0, 0x51CE);
        const at = self.breathMouth();
        const dir = self.breathDir();
        var n = foemod.emitTicks(&self.breathAcc, dt, BREATH_RATE, BREATH_CAP);
        while (n > 0) : (n -= 1) {
            // The mechanic's own arc, in RADIANS because that is what a cone's geometry wants — the constant
            // is authored in degrees for `withinArc`'s sake and converted at the ONE place that needs the
            // other unit, rather than kept as two constants that can part company.
            elemfx.pour(&self.fx, &self.fxHead, &rng, at, dir, .cold, 1, mathx.radians(combat.RIME_ARC), combat.RIME_REACH, 1.0);
        }
    }

    fn castU(self: *const Hero) f32 {
        if (!self.casting) return 0;
        if (self.spell == .rime and self.castT > breathAt()) {
            const held = mathx.minF(self.castT - breathAt(), combat.RIME_DUR);
            return mathx.clampF((self.castT - held) / CAST_DUR, 0, 1);
        }
        return mathx.clampF(self.castT / CAST_DUR, 0, 1);
    }

    pub fn chargeFill(self: *const Hero) f32 {
        if (!self.casting or self.castT / CAST_DUR >= CAST_AT) return 0;
        return mathx.clampF(self.castT / (CAST_DUR * CAST_AT), 0, 1);
    }

    /// Where the bolt leaves, off the posed wrist THE ROD IS ACTUALLY IN. MEASURED from the mesh's own
    /// constants, which are that wrist's frame either side (`wandMesh` takes no fit matrix), so this is one
    /// index and no mirror. Welded to `WRL`, a rod equipped RIGHT drew and posed correctly and then threw
    /// every bolt, laid every rune ring and breathed the whole rime cone out of his empty left hand.
    pub fn wandTipWorld(self: *const Hero) rl.Vector3 {
        return rl.math.vector3Transform(wandAt(WAND_TIP_T), self.xf[if (self.wandLeft()) WRL else WRR]);
    }

    /// SCALED WHOLE, not on the damage alone: what the tree bought is a stronger spell, and a bolt that hit
    /// harder without hitting heavier would leave the poise it staggers with pinned at its level-1 figure.
    /// Null for the two that bill over time (`combat.spellBlow`), so a caller cannot spend a blow they have not
    /// got — the STRIKES read it too, and the levin's whole point is the poise this scales.
    ///
    /// **AND INTELLIGENCE IS THE OTHER HALF OF THE SAME MULTIPLE** — the tree's node and the sheet's skill are
    /// one product, because they are the same claim about the same cast. A rod is the only thing that reads
    /// this attribute, which is why the scaling is here and not on an `item.Arm` row: `hero.wearFor` gives the
    /// wand no socket, so there is no row to hang it off (`Armament`'s "one bell and one rod in this world").
    pub fn castBlow(self: *const Hero) ?combat.Hit {
        const base = combat.spellBlow(self.spell) orelse return null;
        return base.scaled(self.perk.spellDmg * self.sheet.scale(.intelligence));
    }

    pub fn requestAttack(self: *Hero, kind: Attack) void {
        if (self.committed()) {
            self.queued = .{ .attack = kind };
        } else self.startAttack(kind);
    }
    pub fn requestRoll(self: *Hero, dir: rl.Vector3) void {
        if (self.committed()) {
            self.queued = .{ .roll = dir };
        } else self.startRoll(dir);
    }
    pub fn steerQueuedRoll(self: *Hero, dir: rl.Vector3) void {
        if (self.queued) |*q| switch (q.*) {
            .roll => |*d| d.* = dir,
            .attack => {},
        };
    }
    fn fireQueued(self: *Hero) void {
        const q = self.queued orelse return;
        self.queued = null;
        switch (q) {
            .attack => |k| self.startAttack(k),
            .roll => |d| self.startRoll(d),
        }
    }

    pub fn startAttack(self: *Hero, kind: Attack) void {
        if (self.committed() or self.dead or self.staggered() or self.resting) return;
        self.atkRow = self.armOf(.hand_sword);
        self.atkBlade = bladeFor(self.worn.at(.hand_sword));
        const cost: f32 = @as(f32, if (kind == .heavy) combat.STAM_HEAVY else combat.STAM_LIGHT) * self.atkRow.stam;
        if (!self.stam.canAct()) {
            self.refuse();
            return;
        }
        self.stam.spend(cost);
        self.attacking = true;
        self.swings +%= 1;
        self.atkHeavy = kind == .heavy;
        self.atkAlt = false;
        self.atkT = 0;
        self.startXfade();
    }

    pub fn updateAttack(self: *Hero, dt: f32, bounds: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        const dur: f32 = self.atkDur(self.atkHeavy);
        const sa: f32 = if (self.atkHeavy) AH_STRIKE_A else AL_STRIKE_A;
        const sb: f32 = if (self.atkHeavy) AH_STRIKE_B else AL_STRIKE_B;
        const lunge: f32 = if (self.atkHeavy) AH_LUNGE else AL_LUNGE;
        const u = mathx.clampF(self.atkT / dur, 0, 1);
        const speed: f32 = if (u >= sa and u < sb) lunge / ((sb - sa) * dur) else 0;
        const moved = speed * dt;
        mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), moved, bounds);
        self.speed = speed;
        self.speedS = mathx.approach(self.speedS, speed, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| {
            const recovA: f32 = if (self.atkHeavy) AH_RECOV_A else AL_RECOV_A;
            if (u >= recovA) self.facing = mathx.approachAngle(self.facing, ty, dt * ATK_RETRACK);
        }
        self.atkT += dt;
        const chain: f32 = if (self.atkHeavy) AH_CHAIN else AL_CHAIN;
        const wasLight = !self.atkHeavy;
        const wasAlt = self.atkAlt;
        if (self.atkT / dur >= chain and self.queued != null) {
            self.attacking = false;
            self.startXfade();
            self.fireQueued();
            self.alternateChain(wasLight, wasAlt);
            self.pose();
            self.updateBlade();
            return;
        }
        // Pose BEFORE clearing `attacking` (the same one-frame contract as the roll).
        self.pose();
        self.updateBlade();
        if (self.atkT >= dur) {
            self.attacking = false;
            self.startXfade();
            self.fireQueued();
            self.alternateChain(wasLight, wasAlt);
        }
    }

    fn alternateChain(self: *Hero, wasLight: bool, wasAlt: bool) void {
        if (self.attacking and !self.atkHeavy and wasLight) self.atkAlt = !wasAlt;
    }


    pub fn cycleQuick(self: *Hero) void {
        if (self.dead or self.drinking) return;
        self.quick.cycle();
        self.syncFlask();
    }

    pub fn syncFlask(self: *Hero) void {
        if (self.quick.selected()) |k| {
            if (combat.flaskOf(k)) |f| self.flasks.sel = f;
        }
    }

    pub fn cycleArrow(self: *Hero) bool {
        if (self.dead or self.shooting) return false;
        self.quiver.cycle();
        return true;
    }

    pub fn shotBlow(self: *const Hero) combat.Hit {
        return weigh(arrowBlow(self.shotArrow, self.shotAimed, self.perk), self.drawRow(), self.sheet);
    }
    pub fn shotShaft(self: *const Hero) archer.Shot {
        return arrowShot(self.shotArrow);
    }

    pub fn startDrink(self: *Hero) bool {
        if (self.committed() or self.dead or self.staggered()) return false;
        if (self.flasks.sel == .cerulean and !self.fp.canTake()) {
            self.refuse();
            return false;
        }
        if (!self.flasks.take()) {
            self.refuse();
            return false;
        }
        self.drinking = true;
        self.drinkT = 0;
        self.poured = false;
        self.startXfade();
        return true;
    }

    pub fn tickDrink(self: *Hero, dt: f32) void {
        self.drinkT += dt;
        const u = self.drinkT / combat.FLASK_DRINK_DUR;
        if (!self.poured and u >= combat.FLASK_POUR_AT) {
            self.poured = true;
            switch (self.flasks.sel) {
                .crimson => _ = self.vit.heal(self.vit.hpMax * combat.FLASK_HP_FRAC),
                .cerulean => _ = self.fp.restore(self.fp.max * combat.FLASK_FP_FRAC),
            }
        }
        if (self.drinkT >= combat.FLASK_DRINK_DUR) {
            self.drinking = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    /// **WHAT THE SIPHON HANDS BACK** — through `Vitals.heal`, the crimson flask's own door, which refuses a
    /// corpse: a drain that lands on the frame something else killed him may not undo it. Reported so the caller
    /// knows whether anything actually went in; a full bar is a cast that bought nothing but the damage.
    pub fn drinkSiphon(self: *Hero, hp: f32) f32 {
        return self.vit.heal(hp);
    }

    fn drinkLevels(self: *const Hero) struct { lift: f32, tip: f32 } {
        if (!self.drinking) return .{ .lift = 0, .tip = 0 };
        const u = mathx.clampF(self.drinkT / combat.FLASK_DRINK_DUR, 0, 1);
        return .{ .lift = mathx.pulse(u, 0, 0.26, 0.72, 1.0), .tip = mathx.pulse(u, 0.22, 0.46, 0.66, 0.92) };
    }

    pub fn hitActive(self: *const Hero) bool {
        if (!self.attacking) return false;
        const u = self.atkT / self.atkDur(self.atkHeavy);
        return if (self.atkHeavy) (u >= AH_HIT_A and u < AH_HIT_B) else (u >= AL_HIT_A and u < AL_HIT_B);
    }

    fn updateBlade(self: *Hero) void {
        self.bladeA0 = self.bladeA;
        self.bladeB0 = self.bladeB;
        const spec = bladeSpec(self.heldBlade());
        self.bladeA = rl.math.vector3Transform(bladeAt(spec.base), self.xf[SWORD]);
        self.bladeB = rl.math.vector3Transform(bladeAt(spec.tip), self.xf[SWORD]);
        const act = self.hitActive();
        if (act) self.trail.push(self.bladeA, self.bladeB, self.bladeB0, TRAIL_ROOT);
        if (act and !self.hitWasActive) {
            self.bladeA0 = self.bladeA;
            self.bladeB0 = self.bladeB;
        }
        self.hitWasActive = act;
    }

    pub fn drawTrail(self: *const Hero) void {
        self.trail.draw(TRAIL_LIFE, foemod.WAKE, TRAIL_PEAK);
        self.drawLevinBolt();
        foemod.drawParticles(&self.fx);
    }

    fn gatherMotes(self: *Hero, dt: f32) void {
        const at = self.wandTipWorld();
        // Each mote is solved to ARRIVE at the stone, and the stone crosses ~5 m/s through the lift — so without
        // the tip's own velocity they converge on where it WAS. Skipped on the first gather frame: `startCast`
        // cannot prime `tipPrev` (it runs off an input edge, and `xf` is `undefined` until `pose` has run once).
        const tipV = if (self.castT > dt and dt > 0)
            mathx.scaleV(mathx.subV(at, self.tipPrev), 1.0 / dt)
        else
            mathx.zero3;
        self.tipPrev = at;
        const fill = self.chargeFill();
        const shell = mathx.lerpF(CAST_MOTE_R, CAST_MOTE_R_HI, fill);
        var rng = foemod.fxStream(self.castT + @as(f32, @floatFromInt(self.casts)), 977.0, 0x8B01);
        var n = foemod.emitTicks(&self.moteAcc, dt, mathx.lerpF(CAST_MOTE_RATE, CAST_MOTE_RATE_HI, fill * fill), CAST_MOTE_CAP);
        while (n > 0) : (n -= 1) {
            const a = rng.angle();
            const el = rng.range(-0.5, 1.0);
            const rr = rng.range(shell * 0.5, shell);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + el * rr, at.z + mathx.sinf(a) * rr);
            const life = rng.range(CAST_MOTE_LIFE_LO, CAST_MOTE_LIFE_HI);
            const v = mathx.addV(mathx.scaleV(mathx.subV(at, from), 1.0 / life), tipV);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, life, CAST_MOTE_R0, CAST_MOTE_R1, CHAOS_MOTE, 0);
        }
    }

    pub fn castSparks(self: *Hero, dir: rl.Vector3) void {
        const at = self.wandTipWorld();
        const fr = burstFrame(dir);
        const side = fr.side;
        const up = fr.up;
        var rng = foemod.fxStream(@floatFromInt(self.casts), 613.0, 0x8B02);
        var i: u32 = 0;
        while (i < CAST_SPARKS) : (i += 1) {
            const spread = v3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1));
            const v = mathx.addV(mathx.scaleV(dir, rng.range(2.6, 7.0)), mathx.scaleV(spread, rng.range(1.0, 3.2)));
            const life = rng.range(0.20, 0.44);
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, life, rng.range(0.030, 0.058), 0.008, if (rng.float() < 0.4) CHAOS_HOT else CHAOS_MOTE, 2.0);
        }
        i = 0;
        while (i < CAST_COLLAR) : (i += 1) {
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, CAST_COLLAR) + rng.range(-0.26, 0.26);
            const sp = rng.range(CAST_COLLAR_SP * 0.7, CAST_COLLAR_SP);
            const v = mathx.addV(
                mathx.scaleV(side, mathx.cosf(a) * sp),
                mathx.addV(mathx.scaleV(up, mathx.sinf(a) * sp), mathx.scaleV(dir, rng.range(0.3, 1.4))),
            );
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.13, 0.26), rng.range(0.022, 0.040), 0.006, CHAOS_HOT, 1.2);
        }
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(dir, 1.2), CAST_FLASH_LIFE, CAST_FLASH_R, CAST_FLASH_R * 0.30, CHAOS_HOT, 0);
    }

    /// A RESERVED light slot, so a torch he stands beside cannot evict it.
    pub fn wandLight(self: *const Hero) ?gfx.Light {
        if (!self.wandOut() or self.resting) return null;
        const u = self.castU();
        const held = mathx.smoothstep(0, CAST_AT, u) * (1.0 - mathx.smoothstep(CAST_AT, CAST_RECOV_A, u));
        const spike = bump(u, CAST_AT - 0.04, CAST_AT + 0.26);
        return .{
            .pos = self.wandTipWorld(),
            .col = mathx.scaleV(WAND_LIT, WAND_LIT_CARRY +
                (WAND_LIT_CHARGED - WAND_LIT_CARRY) * held + (WAND_LIT_FLARE - WAND_LIT_CHARGED) * spike),
            .radius = WAND_LIT_CARRY_R +
                (WAND_LIT_CHARGED_R - WAND_LIT_CARRY_R) * held + (WAND_LIT_FLARE_R - WAND_LIT_CHARGED_R) * spike,
        };
    }

    pub fn rootsBurst(self: *Hero, at: rl.Vector3, bit: bool) void {
        self.rootHead = (self.rootHead + 1) % ROOT_SITES;
        self.rootSites[self.rootHead] = .{ .at = at, .t = 0, .seed = @floatFromInt(self.casts) };
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, at.y);
        var rng = foemod.fxStream(@floatFromInt(self.casts), 331.0, 0x8B04);
        const dust: u32 = if (bit) ROOT_DUST else ROOT_DUST / 2;
        var i: u32 = 0;
        while (i < dust) : (i += 1) {
            const a = rng.angle();
            const rr = rng.range(0.1, combat.ROOT_GRIP_R * 0.8);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + 0.03, at.z + mathx.sinf(a) * rr);
            const sp = rng.range(1.1, 3.0);
            const v = v3(mathx.cosf(a) * sp, rng.range(2.4, 5.4), mathx.sinf(a) * sp);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, rng.range(0.38, 0.78), rng.range(0.045, 0.100), 0.014, ROOT_SOIL, 7.0);
        }
        var j: u32 = 0;
        while (j < ROOT_MOTES) : (j += 1) {
            const a = rng.angle();
            const rr = rng.range(0.2, combat.ROOT_GRIP_R);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + rng.range(0.05, 0.6), at.z + mathx.sinf(a) * rr);
            const v = v3(rng.signed() * 0.9, rng.range(0.8, 2.4), rng.signed() * 0.9);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, rng.range(0.45, 1.00), rng.range(0.038, 0.072), 0.010, if (rng.float() < 0.4) CHAOS_HOT else CHAOS_MOTE, -0.6);
        }
    }

    pub fn drawRoots(self: *const Hero) void {
        for (self.rootSites) |s| {
            if (s.t >= ROOT_SITE_LIFE) continue;
            var rng = foemod.fxStream(s.seed + 1.0, 613.0, 0x8B05);
            for (0..ROOT_FANS) |k| {
                const jitter = rng.range(-0.34, 0.34);
                const out = rng.range(0.22, combat.ROOT_GRIP_R * 0.66);
                const sc = rng.range(0.62, 1.46);
                const lean = rng.range(4.0, 24.0);
                const kind = @as(usize, @intFromFloat(rng.range(0, ROOT_KINDS)));
                const u = s.t - ROOT_RISE * ROOT_LAG * (@as(f32, @floatFromInt(k)) / ROOT_FANS);
                if (u <= 0) continue;
                const tear = mathx.smoothstep(0, ROOT_RISE, u) + ROOT_PUNCH * bump(u, ROOT_RISE * 0.5, ROOT_RISE * 2.2);
                const up = tear * (1.0 - mathx.smoothstep(ROOT_RISE + combat.ROOT_HOLD, ROOT_LIFE, u));
                if (up <= 0.001) continue;
                const yaw = std.math.tau * (@as(f32, @floatFromInt(k)) / ROOT_FANS) + jitter;
                rl.drawMesh(self.roots[@min(kind, ROOT_KINDS - 1)], self.mat, mul3(
                    mul(scaleM(sc, sc * up, sc), rz(lean)),
                    ry(mathx.degrees(yaw)),
                    tr(s.at.x + mathx.cosf(yaw) * out, s.at.y, s.at.z + mathx.sinf(yaw) * out),
                ));
            }
        }
    }

    pub fn boltBurst(self: *Hero, at: rl.Vector3, groundY: f32, salt: u32) void {
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, groundY);
        var rng = foemod.fxStream(@floatFromInt(salt), 419.0, 0x8B03);
        var i: u32 = 0;
        while (i < BOLT_BURST) : (i += 1) {
            const a = rng.angle();
            const el = rng.range(-0.3, 1.0);
            const sp = rng.range(1.8, 6.4);
            const v = v3(mathx.cosf(a) * sp, el * sp, mathx.sinf(a) * sp);
            const life = rng.range(0.24, 0.56);
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, life, rng.range(0.040, 0.086), 0.010, if (rng.float() < 0.45) CHAOS_HOT else CHAOS_MOTE, 3.4);
        }
    }

    /// **THE LEVIN'S STROKE — the whole spell, on one frame.** `from`/`to` are the blow's OWN segment
    /// (`game.strikeSegment`), never a line derived a second time here: the flash has to be where the blade was.
    /// The sparks are laid ALONG it because the element has none of its own travel (`elemfx`'s lightning), and
    /// the burst at the far end is what says it arrived on a BODY rather than passing through the air.
    pub fn levinStroke(self: *Hero, from: rl.Vector3, to: rl.Vector3, groundY: f32, salt: u32) void {
        // THE FLOOR IS THE EARTH UNDER THE STRIKE, NOT HIS OWN FEET AND NOT THE CONTACT — `boltBurst`'s law, and
        // the contact is a body's CHEST here, so floored there a spark that ever fell would stop in mid-air a
        // metre up. Lightning's grav is 0 today (`elemfx`), which is exactly what makes this the kind of wrong
        // that leaves no trace until somebody retunes the element.
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, groundY);
        var rng = foemod.fxStream(@floatFromInt(salt), 733.0, 0x8B06);
        self.levinT = LEVIN_BOLT_LIFE;
        self.layLevinPath(from, to, &rng);
        var i: u32 = 0;
        while (i < LEVIN_STEPS) : (i += 1) {
            const u = (@as(f32, @floatFromInt(i)) + rng.range(-0.35, 0.35)) / LEVIN_STEPS;
            const p = mathx.lerpV(from, to, mathx.clampF(u, 0, 1));
            const off = v3(rng.signed() * LEVIN_JITTER, rng.signed() * LEVIN_JITTER * 0.35, rng.signed() * LEVIN_JITTER);
            elemfx.burst(&self.fx, &self.fxHead, &rng, mathx.addV(p, off), mathx.zero3, .lightning, LEVIN_SPARKS, LEVIN_SPARK_SCALE);
        }
        elemfx.burst(&self.fx, &self.fxHead, &rng, to, mathx.zero3, .lightning, LEVIN_BURST, LEVIN_BURST_SCALE);
    }

    fn layLevinPath(self: *Hero, from: rl.Vector3, to: rl.Vector3, rng: *mathx.Rng) void {
        const dir = mathx.normV(mathx.subV(to, from));
        const side = mathx.normV(mathx.crossV(dir, v3(0, 1, 0)));
        const up = mathx.crossV(side, dir);
        for (&self.levinPath, 0..) |*p, i| {
            const u = @as(f32, @floatFromInt(i)) / @as(f32, LEVIN_BOLT_PTS - 1);
            const base = mathx.lerpV(from, to, u);
            const swing = LEVIN_BOLT_JAG * mathx.sinf(u * std.math.pi);
            p.* = mathx.addV(base, mathx.addV(
                mathx.scaleV(side, rng.signed() * swing),
                mathx.scaleV(up, rng.signed() * swing * 0.6),
            ));
        }
    }

    fn drawLevinBolt(self: *const Hero) void {
        if (self.levinT <= 0) return;
        const k = mathx.clampF(self.levinT / LEVIN_BOLT_LIFE, 0, 1);
        const coreA = mathx.u8f(255.0 * k);
        const glowA = mathx.u8f(@as(f32, @floatFromInt(LEVIN_GLOW.a)) * k);
        var i: usize = 0;
        while (i + 1 < LEVIN_BOLT_PTS) : (i += 1) {
            const p0 = self.levinPath[i];
            const p1 = self.levinPath[i + 1];
            if (mathx.lenV(mathx.subV(p1, p0)) < 1e-4) continue;
            const ua = @as(f32, @floatFromInt(i)) / @as(f32, LEVIN_BOLT_PTS - 1);
            const ub = @as(f32, @floatFromInt(i + 1)) / @as(f32, LEVIN_BOLT_PTS - 1);
            const w0 = LEVIN_BOLT_W * mathx.lerpF(1.0, LEVIN_BOLT_TIP, ua);
            const w1 = LEVIN_BOLT_W * mathx.lerpF(1.0, LEVIN_BOLT_TIP, ub);
            rl.drawCylinderEx(p0, p1, w0 * LEVIN_BOLT_GLOW, w1 * LEVIN_BOLT_GLOW, 4, mathx.withAlpha(LEVIN_GLOW, glowA));
            rl.drawCylinderEx(p0, p1, w0, w1, 4, mathx.withAlpha(LEVIN_CORE, coreA));
        }
    }

    pub fn lanceBeam(self: *Hero, from: rl.Vector3, to: rl.Vector3, salt: u32) void {
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, mathx.minF(from.y, to.y) - LANCE_FLOOR_DROP);
        var rng = foemod.fxStream(@floatFromInt(salt), 811.0, 0x8B08);
        var i: u32 = 0;
        while (i < LANCE_STEPS) : (i += 1) {
            const u = (@as(f32, @floatFromInt(i)) + rng.range(-0.30, 0.30)) / LANCE_STEPS;
            const p = mathx.lerpV(from, to, mathx.clampF(u, 0, 1));
            const off = v3(rng.signed() * LANCE_JITTER, rng.signed() * LANCE_JITTER * 0.5, rng.signed() * LANCE_JITTER);
            const n = @max(1, @as(usize, @intFromFloat(@round(mathx.lerpF(@as(f32, LANCE_SPARKS), 1.0, u)))));
            elemfx.burst(&self.fx, &self.fxHead, &rng, mathx.addV(p, off), mathx.zero3, .fire, n, LANCE_SPARK_SCALE);
        }
    }

    pub fn sunderBurst(self: *Hero, at: rl.Vector3, bit: bool, salt: u32) void {
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, at.y);
        var rng = foemod.fxStream(@floatFromInt(salt), 877.0, 0x8B09);
        const n: u32 = if (bit) SUNDER_MOTES else SUNDER_MOTES / 2;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n))) * std.math.tau + rng.range(-0.25, 0.25);
            const sp = rng.range(SUNDER_SPEED_LO, SUNDER_SPEED_HI);
            const v = v3(mathx.cosf(a) * sp, rng.range(0.3, 1.4), mathx.sinf(a) * sp);
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.22, 0.46), rng.range(0.030, 0.062), 0.008, if (rng.float() < 0.5) SUNDER_DUST else SUNDER_CHIP, 6.0);
        }
    }

    pub fn siphonDrain(self: *Hero, at: rl.Vector3, salt: u32) void {
        const tip = self.wandTipWorld();
        var rng = foemod.fxStream(@floatFromInt(salt), 787.0, 0x8B07);
        var i: u32 = 0;
        while (i < SIPHON_MOTES) : (i += 1) {
            const a = rng.angle();
            const rr = rng.range(0.0, SIPHON_SPREAD);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + rng.range(-SIPHON_SPREAD, SIPHON_SPREAD), at.z + mathx.sinf(a) * rr);
            const life = rng.range(SIPHON_LIFE_LO, SIPHON_LIFE_HI);
            const v = mathx.scaleV(mathx.subV(tip, from), 1.0 / life);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, life, rng.range(0.026, 0.048), 0.008, if (rng.float() < 0.45) CHAOS_HOT else CHAOS_MOTE, 0);
        }
    }

    pub fn attackHit(self: *const Hero) combat.Hit {
        const base = weigh(if (self.atkHeavy) ATK_HEAVY_HIT else ATK_LIGHT_HIT, self.swingRow(), self.sheet).scaled(self.perk.dmg);
        if (!self.grease.on()) return base;
        var out = base;
        out.elem = combat.elems(.{ .fire = base.dmg * self.grease.value(0) });
        return out;
    }
    pub fn setSpawn(self: *Hero, pos: rl.Vector3, facing: f32) void {
        self.spawnPos = pos;
        self.spawnFacing = facing;
    }
    pub fn staggered(self: *const Hero) bool {
        return self.stun != .none;
    }
    pub fn respawnNow(self: *Hero) void {
        self.respawn();
    }

    pub fn iFramed(self: *const Hero) bool {
        return self.rolling and self.rollT < ROLL_IFRAME_END + self.perk.iframe;
    }

    fn armOf(self: *const Hero, w: item.Wear) item.Arm {
        return armRow(self.worn, w);
    }

    fn swingRow(self: *const Hero) item.Arm {
        return if (self.attacking) self.atkRow else self.armOf(.hand_sword);
    }

    /// WHICH SHAPE IS IN THE FIST — latched for the stroke in flight, `swingRow`'s own law: a club taken up
    /// mid-swing may not lend its reach to the sword that started it.
    pub fn heldBlade(self: *const Hero) Blade {
        return if (self.attacking) self.atkBlade else bladeFor(self.worn.at(.hand_sword));
    }

    pub fn bladeR(self: *const Hero) f32 {
        return bladeSpec(self.heldBlade()).r;
    }

    fn bladeMesh(self: *const Hero) rl.Mesh {
        return switch (self.heldBlade()) {
            .sword => self.mesh[SWORD],
            .dirk => self.dirk,
            .club => self.club,
        };
    }

    fn swingShape(self: *const Hero) SwingShape {
        return swingOf(self.heldBlade());
    }
    fn drawRow(self: *const Hero) item.Arm {
        return if (self.shooting) self.shotRow else self.armOf(.hand_bow);
    }

    pub fn armourA(self: *const Hero) f32 {
        return armourOf(self.worn) + self.perk.armour;
    }
    pub fn charm(self: *const Hero) item.Charm {
        return charmOf(self.worn);
    }

    fn resheet(self: *Hero) void {
        self.sheet = self.perk.sheet();
        boonsOnto(self.worn, &self.sheet);
    }

    pub fn wear(self: *Hero, w: item.Wear, k: ?item.Kind) bool {
        if (k) |kind| {
            if (item.wearSlot(kind) != w) return false;
        }
        self.worn.put(w, k);
        self.resheet();
        self.refitBars();
        return true;
    }

    fn refitBars(self: *Hero) void {
        self.refitHp();
        refitPool(&self.stam.cur, &self.stam.max, self.sheet.stamina());
        refitPool(&self.fp.cur, &self.fp.max, fpMaxOf(self.sheet, self.worn, self.perk));
    }

    /// THE RED BAR'S LENGTH — the sheet's own figure less whatever a charm is eating. **THE FRACTION IS KEPT
    /// ACROSS THE RESIZE**: taking a ring off may not heal him and putting one on may not kill him, and a bar
    /// that jumped either way would be the one number on screen the player cannot trust.
    fn refitHp(self: *Hero) void {
        const frac = if (self.vit.hpMax > 1e-4) self.vit.hp / self.vit.hpMax else 1.0;
        self.vit.hpMax = hpMaxOf(self.sheet, self.worn, self.perk);
        self.vit.hp = mathx.minF(self.vit.hpMax, self.vit.hpMax * frac);
    }

    pub fn drinkLeech(self: *Hero) f32 {
        const back = self.charm().leech + self.perk.leech;
        return if (back > 0) self.vit.heal(back) else 0;
    }

    pub fn atkDur(self: *const Hero, heavy: bool) f32 {
        return @as(f32, if (heavy) ATK_HEAVY_DUR else ATK_LIGHT_DUR) * self.swingRow().dur;
    }

    /// …AND THE SAME CLOCK FOR THE BOW, which is the one armament whose `dur` reached nothing: the warbow's row
    /// says 128% and the shot ran on the bare constant, so the page printed a number the draw did not honour.
    /// ONE answer for the three places that were each spelling out the same pair (`updateShot`, `bowLevels`,
    /// `shotU`) — the mechanic's knot and the pose's own `u` cannot be a shaft apart.
    pub fn shotDur(self: *const Hero, aimed: bool) f32 {
        return @as(f32, if (aimed) BOW_SHOT_DUR else BOW_QUICK_DUR) * self.drawRow().dur;
    }

    fn shotAt(self: *const Hero) f32 {
        return if (self.shotAimed) BOW_SHOT_AT else BOW_QUICK_AT;
    }

    pub fn guardWalk(self: *const Hero) f32 {
        return self.armOf(.hand_shield).walk;
    }

    /// HOW MUCH OF THE COMPASS THE BOARDS ACTUALLY COVER — the base arc through the row in that hand. A tower
    /// shield covers half again what the small one does, and it is the same one comparison either way
    /// (`combat.withinArc`), so a bearing cannot be wrapped two different ways a shield apart.
    pub fn guardArc(self: *const Hero) f32 {
        return combat.GUARD_ARC * self.armOf(.hand_shield).arc;
    }

    pub fn guardCovers(self: *const Hero, fromDir: rl.Vector3) bool {
        // A ZERO DIRECTION IS NEVER BLOCKED, which is what lets `--shot` force reactions with synthetic hits.
        if (!self.guarding or mathx.lenXZ(fromDir) < 1e-4) return false;
        return combat.withinArc(mathx.headingXZ(fromDir), self.facing, self.guardArc());
    }

    pub fn takeHit(self: *Hero, h: combat.Hit, fromDir: rl.Vector3) combat.HitOutcome {
        if (self.dead) return .ignored;
        if (self.iFramed()) return .ignored;
        if (self.guardCovers(fromDir)) return self.blockHit(h);
        self.fp.drain(h.fp);
        const r = self.vit.hit(h.throughArmour(self.armourA()));
        const flash: f32 = switch (r) {
            .death => 1.0,
            .heavy => 0.9,
            .light => 0.6,
            .none => 0.35,
        };
        self.hurtFlash = mathx.maxF(self.hurtFlash, flash);
        switch (r) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.heavy),
            .light => {
                if (self.stun != .heavy) self.enterStun(.light);
            },
            .none => {},
        }
        return .taken;
    }

    /// Takes a whole `Hit` because a floor has an ELEMENT. A DRIP, not a blow: its pulse lands inside the
    /// regen delay (0.42 against 0.8), so billed through `hit` the gate never opens and a pool denies him a
    /// whole poise bar it carries none to take.
    pub fn burn(self: *Hero, h: combat.Hit) combat.HitOutcome {
        if (self.dead or h.raw() <= 0) return .ignored;
        const r = self.vit.drip(h);
        self.hurtFlash = mathx.maxF(self.hurtFlash, 0.45);
        if (r == .death) self.enterDeath();
        return .taken;
    }

    fn blockHit(self: *Hero, h: combat.Hit) combat.HitOutcome {
        self.blockT = 0;
        const board = self.armOf(.hand_shield);
        self.stam.spend(combat.guardStamina(h) * board.stam);
        const negate = mathx.minF(combat.GUARD_NEGATE_CAP, combat.GUARD_NEGATE * board.negate + self.perk.guard);
        const chip = combat.guardChip(h, negate);
        self.fp.drain(chip.fp);
        const r = self.vit.hit(chip.throughArmour(self.armourA()));
        self.hurtFlash = mathx.maxF(self.hurtFlash, BLOCK_FLASH);
        if (r == .death) {
            self.enterDeath();
            return .taken;
        }
        if (self.stam.cur > 0) return .blocked;
        self.guarding = false;
        self.enterStun(.heavy);
        return .guardBroken;
    }
    pub fn tickFlash(self: *Hero, dt: f32) void {
        self.hurtFlash = mathx.maxF(0, self.hurtFlash - dt * 2.6);
    }

    pub fn startWard(self: *Hero, chaos: f32, secs: f32) void {
        self.ward.start(chaos, secs);
        self.settleResists();
    }

    pub fn startGrease(self: *Hero, frac: f32, secs: f32) void {
        self.grease.start(frac, secs);
    }

    pub fn startSteady(self: *Hero, mult: f32, secs: f32) void {
        self.steady.start(mult, secs);
        self.vit.poiseRate = self.steady.value(1);
    }

    pub fn purgePoison(self: *Hero) void {
        self.poison.reset();
    }

    pub fn tickTimed(self: *Hero, dt: f32) void {
        self.ward.tick(dt);
        self.grease.tick(dt);
        self.steady.tick(dt);
        self.vit.poiseRate = self.steady.value(1);
        self.settleResists();
    }

    fn settleResists(self: *Hero) void {
        var r = self.baseRes;
        r.v[@intFromEnum(combat.Elem.chaos)] += self.ward.value(0);
        // …AND WHATEVER HE HAS ON. The mantle is the first thing in the world that answers an element, and it
        // composes here rather than at `wear` for the tree's own reason: this is the ONE place `vit.res` is
        // written, so a coat taken off cannot leave its column behind.
        const worn = resistOf(self.worn);
        r.v[@intFromEnum(combat.Elem.fire)] += worn.fire;
        r.v[@intFromEnum(combat.Elem.cold)] += worn.cold;
        r.v[@intFromEnum(combat.Elem.lightning)] += worn.lightning;
        r.v[@intFromEnum(combat.Elem.chaos)] += worn.chaos;
        self.vit.res = r;
    }

    pub fn poisonBy(self: *Hero, amt: f32) void {
        if (self.dead) return;
        self.poison.add(amt * self.perk.poison * poisonRateOf(self.worn));
    }

    pub fn tickPoison(self: *Hero, dt: f32) bool {
        const due = self.poison.tick(dt, self.vit.hpMax);
        if (due <= 0 or self.dead) return false;
        if (self.vit.drip(combat.poisonPulse(due)) == .death) self.enterDeath();
        return true;
    }

    fn clearAir(self: *Hero) void {
        self.jumping = false;
        self.lift = 0;
        self.airY = self.pos.y;
        self.vertVel = 0;
        self.airSpeed = 0;
        self.landT = mathx.LONG_AGO;
    }

    fn dropActions(self: *Hero) void {
        self.attacking = false;
        self.rolling = false;
        self.drinking = false;
        self.casting = false;
        self.ringing = false;
        self.guarding = false;
        self.parrying = false;
        self.dropAim();
        self.queued = null;
    }

    fn enterStun(self: *Hero, kind: combat.StunKind) void {
        self.dropActions();
        self.stun = kind;
        self.stunT = 0;
        self.speed = 0;
        self.vit.beginStun(kind);
        self.startXfade();
    }
    fn enterDeath(self: *Hero) void {
        self.dropActions();
        self.stun = .none;
        self.dead = true;
        self.deathT = 0;
        self.speed = 0;
        self.startXfade();
    }

    pub fn updateStun(self: *Hero, dt: f32) void {
        self.tickClocks(dt);
        self.stunT += dt;
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        const dur = combat.heroStunDur(self.stun == .heavy);
        self.pose();
        if (self.stunT >= dur) {
            self.stun = .none;
            self.startXfade();
        }
    }

    pub fn updateDeath(self: *Hero, dt: f32) void {
        self.tickClocks(dt);
        self.deathT += dt;
        self.speed = 0;
        self.speedS = 0;
        self.pose();
        if (self.deathT >= DEATH_DUR) self.respawn();
    }
    fn respawn(self: *Hero) void {
        self.dead = false;
        self.deathT = 0;
        self.stun = .none;
        self.hurtFlash = 0;
        self.makeWhole();
        self.dropActions();
        self.stamRefused = 0;
        self.fpRefused = 0;
        self.sprinting = false;
        self.guardB = 0;
        self.aimB = 0;
        self.blockT = mathx.LONG_AGO;
        self.pos = self.spawnPos;
        self.facing = self.spawnFacing;
        self.clearAir();
        self.moving = 0;
        self.speed = 0;
        self.speedS = 0;
        self.trail = .{};
        self.fx = [_]foemod.Particle{.{}} ** FX_N;
        self.fxHead = 0;
        self.startXfade();
    }

    pub fn pose(self: *Hero) void {
        self.poseBody();
        self.poseBowString();
    }

    fn poseBody(self: *Hero) void {
        if (self.dead) return self.poseDeath();
        if (self.stun != .none) return self.poseStun();
        if (self.jumping) return self.poseJump();
        if (self.rolling) return self.poseRoll();
        if (self.attacking) return self.poseAttack();
        if (self.casting) return self.poseCast();
        if (self.ringing) return self.poseRing();
        if (self.parrying) return self.poseParry();
        const m = self.moving;
        const ph = self.phase;
        const twoPi = std.math.tau;
        const fw = self.fwdB;
        const lat = self.latB;
        const fwPos = mathx.clampF(fw, 0, 1);
        const runB = mathx.clampF((self.speedS - RUN_SPEED_LO) / (RUN_SPEED_HI - RUN_SPEED_LO), 0, 1) * fwPos;
        const sprintB = mathx.clampF((self.speedS - RUN_SPEED_HI) / (SPRINT_REF_SPEED - RUN_SPEED_HI), 0, 1) * fwPos;
        const gB = mathx.clampF(self.guardB, 0, 1);
        const rec = self.blockRecoil();
        const guardBack = BLOCK_STEP * rec;
        const dk = self.drinkLevels();
        const land = self.landDip();
        const crouch = (RUN_CROUCH * runB + 0.5 * RUN_CROUCH * sprintB) * m +
            STRAFE_DIP * @abs(lat) * m +
            GUARD_CROUCH * gB + BLOCK_SINK * rec + DRINK_SINK * H * dk.lift + LAND_SINK * land;

        const walkBob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * ph);
        const runBounce = A_RUN_BOUNCE * (0.5 - 0.5 * mathx.cosf(2.0 * twoPi * (ph - 0.2)));
        const fwAbs = @abs(fw);
        const bob = mathx.lerpF(walkBob, runBounce, runB) * m * fwAbs + 0.006 * H * mathx.sinf(self.elapsed * 2.2) * (1.0 - m);
        const latW = @abs(lat) * m;
        const sway = strafeSway(latW, runB) * mathx.sinf(twoPi * ph) * m;
        const prot = A_PROT * mathx.sinf(twoPi * ph) * m * @abs(fw) + strafeProt(ph, lat, m);
        const list = A_LIST * mathx.sinf(twoPi * ph) * m * fwAbs;

        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const bodyPitch = (BODY_PITCH_RUN * runB + (BODY_PITCH_SPRINT - BODY_PITCH_RUN) * sprintB) * m + self.slopePitch;
        var wx: [N]rl.Matrix = undefined;
        const pelvY = hipY - crouch + bob;
        wx[ROOT] = mul3(
            mul(rz(list), ry(prot)),
            mul(tr(sway, pelvY, -guardBack), mul(rx(bodyPitch), ry(facingDeg))),
            rootAt(self.footPos()),
        );

        const lean = (mathx.lerpF(TORSO_LEAN * fw, RUN_LEAN, runB) + sprintB * (SPRINT_LEAN - RUN_LEAN)) * m +
            LAND_STOOP * land;
        const bank = STRAFE_LEAN * lat * m;
        const aim = self.aimLean;
        setLocal(&wx, SPINE, self.rest, mul3(rx(lean * 0.5 + aim * 0.5), ry(-0.3 * prot), rz(0.5 * bank)));
        setLocal(&wx, CHEST, self.rest, mul3(rx(lean * 0.5 + aim * 0.5), ry(-0.5 * prot), rz(0.5 * bank)));
        const fwdTilt = bodyPitch + lean;
        const gazeCounter = mathx.clampF(fwdTilt - GAZE_AHEAD, 0, NECK_EXT_MAX);
        setLocal(&wx, NECK, self.rest, mul(rx(-0.45 * gazeCounter), ry(-0.2 * prot)));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK - 0.55 * gazeCounter));

        legChain(&wx, &self.rest, ph, m, runB, fw, lat, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
        legChain(&wx, &self.rest, ph + 0.5, m, runB, fw, lat, -1.0, HIPR, KNEER, BOOT_SOLE[1]);

        const armAmp = mathx.lerpF(ARM_SWING, RUN_ARM_SWING, runB);
        const armL = -armAmp * mathx.cosf(twoPi * ph) * m * fw;
        const armR = armAmp * mathx.cosf(twoPi * ph) * m * fw;
        armChain(&wx, self.rest, armL, m, runB, sprintB, 1.0, 0.0, SHL, ELL, WRL);
        armChain(&wx, self.rest, armR, m, runB, sprintB, -1.0, 1.0, SHR, ELR, WRR);
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());

        if (gB > 0.001) self.poseGuard(&wx, gB, rec, lean, prot, bank);

        if (self.wandOut()) self.poseWandArm(&wx);
        if (self.bowOut()) self.poseBowArms(&wx, lean, prot, bank);
        if (self.drinking) self.poseDrinkArm(&wx, dk.lift, dk.tip);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseWandArm(self: *const Hero, wx: *[N]rl.Matrix) void {
        const a = armSide(self.wandLeft(), true);
        const swing = ARM_SWING * mathx.cosf(std.math.tau * self.phase) * self.moving * self.fwdB;
        var p = wx.*;
        setLocal(&p, a.sh, self.rest, mul(rx(-WAND_CARRY_FLEX + WAND_CARRY_SWING * swing), rz(a.mirror * (ARM_ABD + WAND_CARRY_ABD))));
        setLocal(&p, a.el, self.rest, rx(-(WAND_CARRY_ELBOW + WAND_CARRY_ELBOW_SWING * swing)));
        setLocal(&p, a.wr, self.rest, rz(a.mirror * WAND_CARRY_WRIST));
        for ([_]usize{ a.sh, a.el, a.wr }) |i| wx[i] = p[i];
    }

    fn poseBowArms(self: *const Hero, wx: *[N]rl.Matrix, lean: f32, prot: f32, bank: f32) void {
        const lvl = self.bowLevels();
        const kick: f32 = if (self.loosedAlready()) BOW_KICK * (1.0 - self.shotU()) else 0;
        const swing = ARM_SWING * mathx.cosf(std.math.tau * self.phase) * self.moving * self.fwdB * (1.0 - lvl.up);
        var bp = wx.*;
        const blade = BOW_BLADE * lvl.up;
        const stoop = BOW_STOOP * (1.0 - 0.75 * lvl.pull);
        setLocal(&bp, SPINE, self.rest, mul3(rx(lean * 0.5 + stoop * 0.5), ry(-0.3 * prot + blade), rz(0.5 * bank)));
        setLocal(&bp, CHEST, self.rest, mul3(rx(lean * 0.5 + stoop * 0.5), ry(-0.5 * prot + blade), rz(0.5 * bank)));
        setLocal(&bp, NECK, self.rest, ry(-blade * 0.6));
        setLocal(&bp, HEAD, self.rest, mul3(rx(BOW_HEAD_NOD * lvl.up), ry(-blade * 0.5 + BOW_HEAD_YAW * lvl.pull), rz(BOW_HEAD_CANT * lvl.pull)));
        const shFlex = mathx.lerpF(BOW_CARRY_SH, BOW_SH_FLEX, lvl.up) - kick - swing;
        const shElbow = mathx.lerpF(BOW_CARRY_ELBOW, BOW_ELBOW, lvl.up);
        setLocal(&bp, SHR, self.rest, mul(rx(-shFlex), rz(-BOW_SH_ABD)));
        setLocal(&bp, ELR, self.rest, rx(-shElbow));
        setLocal(&bp, WRR, self.rest, rz(-BOW_WRIST - 4.0 * kick));
        setLocal(&bp, HELD, self.rest, mul(ry(180.0), rx(100.0 - 3.0 * kick)));
        setLocal(&bp, SHL, self.rest, mul3(
            rx(-mathx.lerpF(BOW_DRAW_REST, BOW_DRAW_SH, lvl.pull) + swing),
            ry(-BOW_DRAW_YAW * lvl.pull),
            rz(mathx.lerpF(ARM_ABD, BOW_DRAW_ABD, lvl.pull)),
        ));
        setLocal(&bp, ELL, self.rest, rx(-mathx.lerpF(IDLE_ELBOW, BOW_DRAW_ELBOW, lvl.pull)));
        setLocal(&bp, WRL, self.rest, rl.math.matrixIdentity());
        for ([_]usize{ SPINE, CHEST, NECK, HEAD, SHL, ELL, WRL, SHR, ELR, WRR, HELD }) |i| wx[i] = bp[i];
    }

    fn poseBowString(self: *Hero) void {
        self.drawAmt = self.bowLevels().pull;
        self.nockVis = false;
        if (!self.bowOut() or self.resting) return;
        const p = archer.poseBow(self.xf[HELD], self.xf[WRL], self.drawAmt);
        self.stringXf = p.string;
        self.nockXf = p.nock;
        self.lastNock = p.at;
        self.nockVis = self.drawAmt > 0.03 and !self.loosedAlready();
    }

    fn shotU(self: *const Hero) f32 {
        if (!self.shooting) return 0;
        return mathx.clampF(self.shotT / self.shotDur(self.shotAimed), 0, 1);
    }
    fn loosedAlready(self: *const Hero) bool {
        if (!self.shooting) return false;
        return self.shotU() >= self.shotAt();
    }

    fn blockRecoil(self: *const Hero) f32 {
        if (self.blockT >= BLOCK_RECOIL_DUR) return 0;
        const u = mathx.clampF(self.blockT / BLOCK_RECOIL_DUR, 0, 1);
        return (1.0 - u) * (1.0 - u);
    }

    fn poseGuard(self: *const Hero, wx: *[N]rl.Matrix, k: f32, rec: f32, lean: f32, prot: f32, bank: f32) void {
        var gp = wx.*;
        const brd = armSide(self.shieldLeft(), true);
        const free = armSide(!self.shieldLeft(), false);
        const blade = brd.mirror * -(GUARD_BLADE + BLOCK_TRUNK * rec);
        setLocal(&gp, SPINE, self.rest, mul3(rx(lean * 0.5), ry(-0.3 * prot + blade), rz(0.5 * bank)));
        setLocal(&gp, CHEST, self.rest, mul3(rx(lean * 0.5 + 5.0 * rec), ry(-0.5 * prot + blade), rz(0.5 * bank)));
        setLocal(&gp, NECK, self.rest, ry(-blade));
        setLocal(&gp, HEAD, self.rest, mul(rx(GUARD_HEAD), ry(-blade)));
        setLocal(&gp, brd.sh, self.rest, mul3(rx(-(GUARD_SH_FLEX - BLOCK_SHIELD_BACK * rec)), rz(brd.mirror * GUARD_SH_ABD), ry(brd.mirror * -GUARD_SH_CROSS)));
        setLocal(&gp, brd.el, self.rest, rx(-(GUARD_ELBOW + BLOCK_SHIELD_FOLD * rec)));
        setLocal(&gp, brd.wr, self.rest, rl.math.matrixIdentity());
        setLocal(&gp, free.sh, self.rest, mul(rx(GUARD_SWORD_BACK), rz(free.mirror * -ARM_ABD)));
        setLocal(&gp, free.el, self.rest, rx(-GUARD_SWORD_ELBOW));
        setLocal(&gp, free.wr, self.rest, rx(GUARD_SWORD_WRIST));
        placeSword(&gp, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        for ([_]usize{ SPINE, CHEST, NECK, HEAD, SHL, ELL, WRL, SHR, ELR, WRR, SWORD }) |i| {
            wx[i] = lerpM(wx[i], gp[i], k);
        }
    }

    fn absorb(u: f32, at: f32, rebound: f32) f32 {
        if (u <= at) return mathx.smoothstep(0, at, u);
        const w = mathx.clampF((u - at) / (1.0 - at), 0, 1);
        const fall = (1.0 - w) * (1.0 - w);
        return fall * mathx.cosf(std.math.tau * rebound * w);
    }

    fn parryDrive(u: f32) f32 {
        return absorb(u, PARRY_PUNCH_AT, PARRY_REBOUND);
    }

    fn landDip(self: *const Hero) f32 {
        if (self.landT >= LAND_DUR) return 0;
        return absorb(self.landT / LAND_DUR, LAND_SINK_AT, LAND_REBOUND);
    }

    fn parrySweep(u: f32) f32 {
        const coil = mathx.smoothstep(0, PARRY_COIL_AT, u);
        const whip = mathx.smoothstep(PARRY_COIL_AT, PARRY_SWEEP_END, u);
        const settle = 1.0 - mathx.smoothstep(PARRY_SWEEP_END, 1.0, u);
        return (2.0 * whip - coil) * settle;
    }

    fn poseParry(self: *Hero) void {
        const u = mathx.clampF(self.parryT / PARRY_DUR, 0, 1);
        const k = parryDrive(u);
        const s = parrySweep(u);
        const rec = self.blockRecoil();
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const brd = armSide(self.shieldLeft(), true);
        const free = armSide(!self.shieldLeft(), false);
        const blade = brd.mirror * (-(GUARD_BLADE + BLOCK_TRUNK * rec) + PARRY_TRUNK * s);
        const sink = GUARD_CROUCH + PARRY_SINK * k + BLOCK_SINK * rec;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(PARRY_PELVIS * blade),
            mul(tr(0, hipY - sink, PARRY_HAND_LEAD * k - BLOCK_STEP * rec), mul(rx(PARRY_PITCH * k), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, ry(0.5 * blade));
        setLocal(&wx, CHEST, self.rest, mul(rx(5.0 * rec), ry(0.5 * blade)));
        setLocal(&wx, NECK, self.rest, ry(-0.45 * blade));
        setLocal(&wx, HEAD, self.rest, mul(rx(PARRY_HEAD), ry(-0.55 * blade)));
        setLocal(&wx, HIPL, self.rest, mul(rx(-5.0 * k), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 12.0 * k + 8.0 * rec));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(4.0 * k), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 8.0 * k + 8.0 * rec));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, brd.sh, self.rest, mul3(
            rx(-(GUARD_SH_FLEX + PARRY_PUNCH * k - BLOCK_SHIELD_BACK * rec)),
            rz(brd.mirror * GUARD_SH_ABD),
            ry(brd.mirror * (-(GUARD_SH_CROSS - PARRY_SWEEP * k) + PARRY_ARM_LEAD * s)),
        ));
        setLocal(&wx, brd.el, self.rest, rx(-(GUARD_ELBOW - PARRY_PUNCH * k + BLOCK_SHIELD_FOLD * rec)));
        setLocal(&wx, brd.wr, self.rest, rz(brd.mirror * PARRY_WRIST * k));
        setLocal(&wx, free.sh, self.rest, mul(rx(GUARD_SWORD_BACK + PARRY_SWORD_COCK * k), rz(free.mirror * -ARM_ABD)));
        setLocal(&wx, free.el, self.rest, rx(-(GUARD_SWORD_ELBOW + 14.0 * k)));
        setLocal(&wx, free.wr, self.rest, rx(GUARD_SWORD_WRIST));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }


    fn startXfade(self: *Hero) void {
        self.blendXf = self.xf;
        self.blendT = 0;
    }

    fn applyXfade(self: *const Hero, wx: *[N]rl.Matrix) void {
        if (self.blendT >= POSE_XFADE) return;
        const k = mathx.smoothstep(0, POSE_XFADE, self.blendT);
        for (0..N) |i| wx[i] = lerpM(self.blendXf[i], wx[i], k);
    }

    /// Off ONE number, the vertical velocity: DRIVE up, TUCK where it passes through zero — which IS the
    /// apex, so the pose cannot drift out of step with the arc the way a second clock would — REACH down.
    fn poseJump(self: *Hero) void {
        const k = mathx.clampF(self.vertVel / JUMP_V0, -1, 1);
        const drive = mathx.clampF(k, 0, 1);
        const reach = mathx.clampF(-k, 0, 1);
        const tuck = 1.0 - @abs(k);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul(mul(tr(0, hipY, 0), ry(facingDeg)), rootAt(self.footPos()));
        const fold = JUMP_FOLD * tuck + JUMP_ARCH * drive;
        setLocal(&wx, SPINE, self.rest, rx(fold * 0.5));
        setLocal(&wx, CHEST, self.rest, rx(fold * 0.5));
        setLocal(&wx, NECK, self.rest, rx(JUMP_HEAD_UP * 0.4 * drive));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK * reach + JUMP_HEAD_UP * 0.6 * drive));
        jumpLeg(&wx, self.rest, drive, reach, tuck, 1.0 + JUMP_LEG_SPLIT / JUMP_TUCK_HIP, 1.0, HIPL, KNEEL, ANKL);
        jumpLeg(&wx, self.rest, drive, reach, tuck, 1.0 - JUMP_LEG_SPLIT / JUMP_TUCK_HIP, -1.0, HIPR, KNEER, ANKR);
        jumpArm(&wx, self.rest, drive, reach, tuck, 1.0, SHL, ELL, WRL);
        jumpArm(&wx, self.rest, drive, reach, tuck, -1.0, SHR, ELR, WRR);
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        if (self.guardB > 0.001) self.poseGuard(&wx, mathx.clampF(self.guardB, 0, 1), 0, fold * 0.5, 0, 0);
        if (self.wandOut()) self.poseWandArm(&wx);
        if (self.bowOut()) self.poseBowArms(&wx, fold * 0.5, 0, 0);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseRoll(self: *Hero) void {
        const u = mathx.clampF(self.rollT / ROLL_DUR, 0, 1);
        const tuckIn = mathx.smoothstep(0, ROLL_TUCK_IN, u);
        const tuck = tuckIn * (1.0 - mathx.smoothstep(ROLL_UNTUCK_A, ROLL_UNTUCK_B, u));
        const spin = ROLL_SPIN_OVER * mathx.smoothstep(ROLL_SPIN_A, ROLL_SPIN_M1, u) +
            (360.0 - ROLL_SPIN_OVER) * mathx.smoothstep(ROLL_SPIN_M0, ROLL_SPIN_B, u);
        const crouch = tuckIn * (1.0 - mathx.smoothstep(ROLL_RISE_A, ROLL_RISE_B, u));
        const ballY = mathx.lerpF(self.rest[ROOT].y, ROLL_BALL_Y, crouch);
        const v = self.rollVar;
        const lean = ROLL_LEAN * self.rollSide * v * tuck;
        const skew = ROLL_SKEW * self.rollSide * v *
            mathx.pulse(u, 0.30, 0.75, 0.85, 1.0);
        const facingDeg = mathx.degrees(self.facing);

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(rz(lean), rx(spin)),
            mul(ry(facingDeg + skew), tr(0, ballY, 0)),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, rx(ROLL_SPINE * tuck));
        setLocal(&wx, CHEST, self.rest, rx(ROLL_SPINE * tuck));
        setLocal(&wx, NECK, self.rest, rx(ROLL_HEAD * 0.4 * tuck));
        setLocal(&wx, HEAD, self.rest, mul(rx(mathx.lerpF(HEAD_WALK, ROLL_HEAD, tuck)), ry(-0.5 * skew)));
        const leadF = 1.0 + (ROLL_LEG_LEAD - 1.0) * v;
        const trailF = 1.0 + (ROLL_LEG_TRAIL - 1.0) * v;
        const guideF = 1.0 + (ROLL_ARM_GUIDE - 1.0) * v;
        const pushF = 1.0 + (ROLL_ARM_PUSH - 1.0) * v;
        const overL = self.rollSide > 0;
        rollLeg(&wx, self.rest, tuck, if (overL) leadF else trailF, 1.0, HIPL, KNEEL, ANKL);
        rollLeg(&wx, self.rest, tuck, if (overL) trailF else leadF, -1.0, HIPR, KNEER, ANKR);
        rollArm(&wx, self.rest, tuck, if (overL) guideF else pushF, 1.0, SHL, ELL, WRL);
        rollArm(&wx, self.rest, tuck, if (overL) pushF else guideF, -1.0, SHR, ELR, WRR);
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseAttack(self: *Hero) void {
        if (self.atkHeavy) return self.poseHeavy();
        self.poseLight();
    }

    fn poseLight(self: *Hero) void {
        const u = mathx.clampF(self.atkT / self.atkDur(false), 0, 1);
        const rec = 1.0 - mathx.smoothstep(AL_RECOV_A, 1.0, u);
        const wind = mathx.smoothstep(0, AL_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AL_STRIKE_A, AL_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_STRIKE_B + AL_LAG, u) * rec;
        const sElb = mathx.smoothstep(AL_WIND_B, AL_HIT_A + 0.04, u) * rec;
        const sWr = mathx.smoothstep(AL_STRIKE_A + 2 * AL_LAG, AL_STRIKE_B + 2 * AL_LAG, u) * rec;
        const sw: f32 = if (self.atkAlt) -1.0 else 1.0;
        const amp: f32 = if (self.atkAlt) 0.8 else 1.0;
        const sd: f32 = if (self.swordLeft()) -1.0 else 1.0;
        const shS: usize = if (sd < 0) SHL else SHR;
        const elS: usize = if (sd < 0) ELL else ELR;
        const wrS: usize = if (sd < 0) WRL else WRR;
        const shF: usize = if (sd < 0) SHR else SHL;
        const elF: usize = if (sd < 0) ELR else ELL;
        const wrF: usize = if (sd < 0) WRR else WRL;

        const shape = self.swingShape();
        const os = AL_OVER * bump(u, AL_STRIKE_B + 2 * AL_LAG, AL_RECOV_A + 0.15);
        const yawP = sd * sw * shape.arc * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sPelv);
        const yawC = sd * sw * (1.35 * shape.arc * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sChest) + os);
        const crunch = AL_SPINE_CRUNCH * sChest;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yawP),
            mul(tr(0, hipY - shape.dip * (AL_LOAD * wind + AL_DIP * sPelv), 0), mul(rx(1.5 * sChest), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(crunch + self.aimLean * 0.5), ry(0.35 * yawC)));
        setLocal(&wx, CHEST, self.rest, mul(rx(crunch + self.aimLean * 0.5), ry(0.65 * yawC)));
        setLocal(&wx, NECK, self.rest, ry(-0.4 * (yawP + yawC)));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK), ry(-0.35 * (yawP + yawC))));
        const braceL: f32 = if (self.atkAlt) 6.0 else -10.0;
        const braceR: f32 = if (self.atkAlt) -10.0 else 6.0;
        const kneeL: f32 = if (self.atkAlt) 5.0 else 8.0;
        const kneeR: f32 = if (self.atkAlt) 8.0 else 5.0;
        setLocal(&wx, HIPL, self.rest, mul(rx(braceL * sPelv), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + kneeL * sPelv + 6.0 * wind));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(braceR * sPelv), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + kneeR * sPelv + 6.0 * wind));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, shF, self.rest, mul(rx(-10.0 * wind + 24.0 * sChest), rz(sd * ARM_ABD)));
        setLocal(&wx, elF, self.rest, rx(-(IDLE_ELBOW + 12.0 * wind)));
        setLocal(&wx, wrF, self.rest, rl.math.matrixIdentity());
        const windAmp: f32 = if (self.atkAlt) AL_ALT_WIND else 1.0;
        const sRaise = mathx.smoothstep(AL_WIND_B - 0.06, AL_HIT_A - 0.02, u) * rec;
        const elev = AL_SH_ELEV_WIND * wind + (AL_SH_ELEV - AL_SH_ELEV_WIND) * sRaise;
        const sSweep = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_HIT_B - 0.01, u) * rec;
        const back = AL_SWEEP_WIND * windAmp * shape.wind;
        const sweep = sw * (-back * wind + (back + AL_SWEEP_END * shape.arc) * sSweep + 0.9 * os);
        setLocal(&wx, shS, self.rest, mul3(rx(-elev), ry(sd * sweep), rz(sd * (-ARM_ABD - 10.0 * amp * wind))));
        const elb = IDLE_ELBOW + (AL_ELBOW_WIND - IDLE_ELBOW) * wind - (AL_ELBOW_WIND - AL_ELBOW_STRIKE) * sElb;
        setLocal(&wx, elS, self.rest, rx(-elb));
        const lvl = mathx.smoothstep(0.05, AL_STRIKE_A, u) * rec;
        const lay = sw * (AL_WRIST_LAY * wind - (AL_WRIST_LAY + AL_WRIST_WHIP) * sWr);
        setLocal(&wx, wrS, self.rest, mul3(ry(sd * sw * AL_EDGE_ROLL * lvl), rx(-AL_TIP_UP * lvl), rz(sd * lay)));
        placeSword(&wx, self.rest, rx(GRIP_PITCH * lvl), sd < 0);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseHeavy(self: *Hero) void {
        const u = mathx.clampF(self.atkT / self.atkDur(true), 0, 1);
        const rec = 1.0 - mathx.smoothstep(AH_RECOV_A, 1.0, u);
        const wind = mathx.smoothstep(0, AH_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AH_STRIKE_A, AH_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AH_STRIKE_A + AH_LAG, AH_STRIKE_B + AH_LAG, u) * rec;
        const sSh = mathx.smoothstep(AH_STRIKE_A + 2 * AH_LAG, AH_STRIKE_B + 2 * AH_LAG, u) * rec;
        const sElb = mathx.smoothstep(AH_STRIKE_A + 3 * AH_LAG, AH_STRIKE_B + 3 * AH_LAG, u) * rec;
        const sWr = mathx.smoothstep(AH_STRIKE_A + 4 * AH_LAG, AH_STRIKE_B + 4 * AH_LAG, u) * rec;

        const gather = mathx.smoothstep(AH_WIND_B - 0.05, AH_STRIKE_A + 2 * AH_LAG, u) * (1.0 - sSh) * rec;
        const rcl = bump(u, AH_STRIKE_B + 2 * AH_LAG, AH_RECOV_A) * rec;
        const sd: f32 = if (self.swordLeft()) -1.0 else 1.0;
        const shS: usize = if (sd < 0) SHL else SHR;
        const elS: usize = if (sd < 0) ELL else ELR;
        const wrS: usize = if (sd < 0) WRL else WRR;
        const shF: usize = if (sd < 0) SHR else SHL;
        const elF: usize = if (sd < 0) ELR else ELL;
        const wrF: usize = if (sd < 0) WRR else WRL;

        const shape = self.swingShape();
        const yaw = sd * shape.arc * (-AH_BODY_YAW * wind + 2.0 * AH_BODY_YAW * sPelv);
        const spineX = -AH_LEAN_BACK * shape.wind * wind + (AH_LEAN_BACK + AH_SPINE_CRUNCH) * sChest;
        const tilt = -AH_SPINE_TILT * wind + 1.5 * AH_SPINE_TILT * sChest;
        const dip = shape.dip * (AH_LOAD * wind + (AH_DIP - AH_LOAD) * sPelv) - 0.008 * H * rcl;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yaw),
            mul(tr(0, hipY - dip, 0), mul(rx(AH_PITCH * sPelv), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), rz(sd * 0.5 * tilt)));
        setLocal(&wx, CHEST, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), rz(sd * 0.5 * tilt)));
        setLocal(&wx, NECK, self.rest, rx(-0.3 * spineX));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK + 4.0 * sChest), ry(-0.4 * yaw)));
        setLocal(&wx, HIPL, self.rest, mul(rx(-14.0 * wind - 8.0 * sPelv), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 8.0 * wind + 6.0 * sPelv));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(2.0 * wind + 5.0 * sPelv), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 17.0 * wind + 4.0 * sPelv));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, shF, self.rest, mul(rx(-22.0 * wind + 30.0 * sChest), rz(sd * (ARM_ABD + 6.0 * wind))));
        setLocal(&wx, elF, self.rest, rx(-(IDLE_ELBOW + 16.0 * wind)));
        setLocal(&wx, wrF, self.rest, rl.math.matrixIdentity());
        const up = AH_SH_UP * shape.wind;
        const shX = -up * wind - AH_GATHER * shape.wind * gather + (up - AH_SH_DOWN * shape.arc) * sSh + AH_RECOIL * rcl;
        setLocal(&wx, shS, self.rest, mul(rx(shX), rz(sd * (-ARM_ABD - 8.0 * wind))));
        const elb = IDLE_ELBOW + (AH_ELBOW_WIND - IDLE_ELBOW) * wind + 5.0 * gather - (AH_ELBOW_WIND - AH_ELBOW_STRIKE) * sElb;
        setLocal(&wx, elS, self.rest, rx(-elb));
        setLocal(&wx, wrS, self.rest, rx(AH_WRIST_COCK * wind - (AH_WRIST_COCK + AH_WRIST_SNAP) * sWr + 8.0 * rcl));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), sd < 0);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseCast(self: *Hero) void {
        const u = self.castU();
        const rec = 1.0 - mathx.smoothstep(CAST_RECOV_A, 1.0, u);
        const wind = mathx.smoothstep(0, CAST_WIND_B, u) * rec;
        const sSweep = mathx.smoothstep(CAST_WIND_B, CAST_RECOV_A, u) * rec;
        const sThrow = mathx.smoothstep(CAST_AT - 0.08, CAST_AT + 0.06, u) * rec;
        const kick = bump(u, CAST_AT + 0.06, CAST_RECOV_A) * rec;
        const sw: f32 = if (self.castAlt) -1.0 else 1.0;

        const bU = self.breathU();
        const bOn = mathx.smoothstep(0, 0.14, bU) * (1.0 - mathx.smoothstep(0.82, 1.0, bU));
        const bOut = bump(bU, 0.80, 1.0);
        const shiver = bOn * BREATH_SHIVER * mathx.sinf(bU * combat.RIME_DUR * BREATH_SHIVER_HZ * std.math.tau);

        const rod = armSide(self.wandLeft(), true);
        const free = armSide(!self.wandLeft(), false);

        const shRz = rod.mirror * mathx.lerpF(ARM_ABD + WAND_CARRY_ABD, CAST_LIFT_ABD, wind);
        const shRy = rod.mirror * sw * CAST_SWEEP * (1.0 - 2.0 * sSweep) * wind;
        const yaw = rod.mirror * sw * (-CAST_TRUNK * wind + 1.6 * CAST_TRUNK * sSweep);
        const dip = CAST_DIP * wind - 0.4 * CAST_DIP * sThrow;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yaw),
            mul(tr(0, hipY - dip, 0), mul(rx(2.0 * sThrow), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        const spineX = -CAST_LEAN * wind + 2.0 * CAST_LEAN * sThrow + BREATH_LEAN * bOn - 0.45 * BREATH_LEAN * bOut;
        setLocal(&wx, SPINE, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), ry(0.35 * yaw)));
        setLocal(&wx, CHEST, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), ry(0.65 * yaw)));
        setLocal(&wx, NECK, self.rest, rx(-0.35 * spineX));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK + CAST_HEAD * sThrow + BREATH_HEAD * bOn), ry(-0.4 * yaw)));
        setLocal(&wx, HIPL, self.rest, mul(rx(-6.0 * wind - 4.0 * sThrow), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 12.0 * wind + 4.0 * sThrow));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(4.0 * wind + 3.0 * sThrow), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 9.0 * wind + 3.0 * sThrow));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        const elb = mathx.lerpF(WAND_CARRY_ELBOW, CAST_ELBOW, wind) - CAST_ELBOW_SNAP * sThrow + 6.0 * kick -
            BREATH_REACH * bOn + 0.5 * BREATH_REACH * bOut + shiver;
        setLocal(&wx, rod.sh, self.rest, mul3(rx(-(mathx.lerpF(WAND_CARRY_FLEX, CAST_SH_FWD, wind) - BREATH_SH_LEVEL * bOn)), ry(shRy), rz(shRz)));
        setLocal(&wx, rod.el, self.rest, rx(-elb));
        setLocal(&wx, rod.wr, self.rest, rz(rod.mirror * (mathx.lerpF(WAND_CARRY_WRIST, CAST_WRIST, wind) - 1.5 * CAST_WRIST * sThrow - 8.0 * kick + 1.6 * shiver)));
        setLocal(&wx, free.sh, self.rest, mul(rx(GUARD_SWORD_BACK * wind), rz(free.mirror * -ARM_ABD)));
        setLocal(&wx, free.el, self.rest, rx(-(IDLE_ELBOW + (GUARD_SWORD_ELBOW - IDLE_ELBOW) * wind)));
        setLocal(&wx, free.wr, self.rest, rx(GUARD_SWORD_WRIST * wind));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseRing(self: *Hero) void {
        const u = self.ringU();
        const rec = 1.0 - mathx.smoothstep(RING_RECOV_A, 1.0, u);
        const lift = mathx.smoothstep(0, RING_AT - 0.06, u) * rec;
        const flickT = (u - (RING_AT - RING_FLICK_LEAD)) * RING_DUR;
        const shake: f32 = if (flickT <= 0) 0 else @exp(-flickT * RING_DECAY) * mathx.sinf(flickT * RING_FLICK_RATE);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const bel = armSide(self.bellLeft(), false);
        const free = armSide(!self.bellLeft(), true);

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul(mul(tr(0, hipY - 0.012 * lift, 0), ry(facingDeg)), rootAt(self.footPos()));
        const spineX = -RING_LEAN * lift;
        setLocal(&wx, SPINE, self.rest, rx(0.5 * (spineX + self.aimLean)));
        setLocal(&wx, CHEST, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), ry(bel.mirror * -5.0 * lift)));
        setLocal(&wx, NECK, self.rest, rx(-0.35 * spineX));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK + RING_HEAD * lift));
        setLocal(&wx, HIPL, self.rest, mul(rx(-3.0 * lift), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 9.0 * lift));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(-2.0 * lift), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 7.0 * lift));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, bel.sh, self.rest, mul3(rx(-RING_SH_FWD * lift), ry(0), rz(bel.mirror * (-ARM_ABD - RING_SH_ABD * lift))));
        setLocal(&wx, bel.el, self.rest, rx(-(IDLE_ELBOW + (RING_ELBOW - IDLE_ELBOW) * lift) + 5.0 * shake));
        setLocal(&wx, bel.wr, self.rest, mul(rz(bel.mirror * RING_FLICK * shake), rx(-14.0 * lift)));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        setLocal(&wx, free.sh, self.rest, mul(rx(-6.0 * lift), rz(free.mirror * ARM_ABD)));
        setLocal(&wx, free.el, self.rest, rx(-(IDLE_ELBOW + 10.0 * lift)));
        setLocal(&wx, free.wr, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseDrinkArm(self: *const Hero, wx: *[N]rl.Matrix, lift: f32, tip: f32) void {
        var dp = wx.*;
        setLocal(&dp, NECK, self.rest, rx(-14.0 * tip));
        setLocal(&dp, HEAD, self.rest, rx(HEAD_WALK - 30.0 * tip));
        setLocal(&dp, SHL, self.rest, mul(rx(-58.0 * lift - 14.0 * tip), rz(ARM_ABD + 16.0 * lift)));
        setLocal(&dp, ELL, self.rest, rx(-(IDLE_ELBOW + 96.0 * lift + 22.0 * tip)));
        setLocal(&dp, WRL, self.rest, rx(-28.0 * tip));
        for ([_]usize{ NECK, HEAD, SHL, ELL, WRL }) |i| wx[i] = dp[i];
    }

    pub fn poseRest(self: *Hero, dt: f32) void {
        self.restT += dt;
        const t = self.restT;
        const phrase = 0.5 - 0.5 * mathx.cosf(t * 0.55);
        const strum = mathx.sinf((t * 1.15 - @floor(t * 1.15)) * std.math.tau) * (0.55 + 0.45 * phrase);
        const breathe = 0.010 * H * mathx.sinf(t * 1.05);
        const lilt = 5.2 * mathx.sinf(t * 0.62) + 1.8 * mathx.sinf(t * 0.29 + 1.1);
        const facingDeg = mathx.degrees(self.facing);

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rz(lilt * 0.18),
            mul(tr(0, SIT_Y * H + breathe, 0), mul(rx(SIT_PITCH), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(SIT_SPINE + 0.6 * strum), rz(lilt * 0.45)));
        setLocal(&wx, CHEST, self.rest, mul(rx(SIT_CHEST), rz(lilt * 0.37)));
        setLocal(&wx, NECK, self.rest, mul(rx(5.0), rz(-lilt * 0.30)));
        setLocal(&wx, HEAD, self.rest, mul3(rx(HEAD_WALK + 13.0 - 4.0 * phrase), ry(11.0), rz(-lilt * 0.40)));
        sitLeg(&wx, self.rest, 1.0, HIPL, KNEEL, ANKL);
        sitLeg(&wx, self.rest, -1.0, HIPR, KNEER, ANKR);
        const fret = 6.0 * phrase;
        setLocal(&wx, SHL, self.rest, mul(rx(-14.0 - fret), rz(ARM_ABD + 46.0)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 52.0 + fret)));
        setLocal(&wx, WRL, self.rest, rz(-26.0));
        setLocal(&wx, SHR, self.rest, mul(rx(-48.0 + 1.2 * strum), rz(-ARM_ABD - 34.0)));
        setLocal(&wx, ELR, self.rest, rx(-(IDLE_ELBOW + 88.0 + 3.5 * strum)));
        setLocal(&wx, WRR, self.rest, rz(9.0 * strum));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        self.xf = wx;
    }

    fn poseStun(self: *Hero) void {
        const heavy = self.stun == .heavy;
        const u = mathx.clampF(self.stunT / combat.heroStunDur(heavy), 0, 1);
        const amt = if (heavy)
            mathx.pulse(u, 0, 0.12, 0.68, 1.0)
        else
            mathx.sinf(u * std.math.pi);
        const leanMag: f32 = if (heavy) STAG_LEAN else HURT_LEAN;
        const lean = leanMag * amt;
        const wob: f32 = if (heavy) 3.0 * mathx.sinf(self.elapsed * 13.0) * amt else 0;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const sinkMag: f32 = if (heavy) 0.06 else 0.05;
        const sink = sinkMag * H * amt;
        const backMag: f32 = if (heavy) 0.10 * H else HURT_STEP;
        const back = backMag * amt;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rz(wob),
            mul(tr(0, hipY - sink, -back), mul(rx(-0.55 * lean), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(-0.55 * lean), rz(0.3 * wob)));
        setLocal(&wx, CHEST, self.rest, mul(rx(-0.55 * lean), rz(0.3 * wob)));
        const headBackMag: f32 = if (heavy) HURT_HEAD * 1.3 else HURT_HEAD;
        const headBack = headBackMag * amt;
        setLocal(&wx, NECK, self.rest, rx(-0.4 * headBack));
        setLocal(&wx, HEAD, self.rest, rx(-headBack));
        const braceR: f32 = if (heavy) 26.0 * amt else 6.0 * amt;
        const kneeRMag: f32 = if (heavy) 30.0 else 12.0;
        setLocal(&wx, HIPL, self.rest, mul(rx(8.0 * amt), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 16.0 * amt));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(-braceR), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + kneeRMag * amt));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        const armUpMag: f32 = if (heavy) 42.0 else 48.0;
        const armUp = armUpMag * amt;
        setLocal(&wx, SHL, self.rest, mul(rx(-armUp), rz(ARM_ABD + 0.5 * armUp)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 20.0 * amt)));
        setLocal(&wx, WRL, self.rest, rl.math.matrixIdentity());
        setLocal(&wx, SHR, self.rest, mul(rx(-0.8 * armUp), rz(-ARM_ABD - 0.4 * armUp)));
        setLocal(&wx, ELR, self.rest, rx(-(IDLE_ELBOW + 16.0 * amt)));
        setLocal(&wx, WRR, self.rest, rl.math.matrixIdentity());
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseDeath(self: *Hero) void {
        const u = mathx.clampF(self.deathT / DEATH_DUR, 0, 1);
        const k = mathx.smoothstep(0, 0.5, u);
        const settle = mathx.smoothstep(0.5, 0.85, u);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const y = mathx.lerpF(hipY, DEATH_SINK * hipY, k);
        const pitch = 22.0 * k + 20.0 * settle;
        const twist = 12.0 * k;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rz(twist),
            mul(tr(0, y, 0), mul(rx(pitch), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, rx(28.0 * k));
        setLocal(&wx, CHEST, self.rest, rx(28.0 * k));
        setLocal(&wx, NECK, self.rest, rx(20.0 * k));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK + 26.0 * k));
        setLocal(&wx, HIPL, self.rest, mul(rx(-70.0 * k), rz(-HIP_ADDUCT - 10.0 * k)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 110.0 * k));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(-60.0 * k), rz(HIP_ADDUCT + 8.0 * k)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 100.0 * k));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, SHL, self.rest, mul(rx(-14.0 * k), rz(ARM_ABD + 14.0 * k)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 30.0 * k)));
        setLocal(&wx, WRL, self.rest, rl.math.matrixIdentity());
        setLocal(&wx, SHR, self.rest, mul(rx(-10.0 * k), rz(-ARM_ABD - 10.0 * k)));
        setLocal(&wx, ELR, self.rest, rx(-(IDLE_ELBOW + 24.0 * k)));
        setLocal(&wx, WRR, self.rest, rl.math.matrixIdentity());
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    pub fn draw(self: *const Hero) void {
        const stowSword = self.resting or !self.holds(.sword);
        for (0..N) |i| {
            if (i == SWORD) continue;
            rl.drawMesh(self.mesh[i], self.mat, self.xf[i]);
        }
        if (!stowSword) rl.drawMesh(self.bladeMesh(), self.mat, self.xf[SWORD]);
        if (self.resting) {
            rl.drawMesh(self.guitar, self.mat, self.xf[ROOT]);
            return;
        }
        if (armTwoHanded(self.off)) {
            _ = self.drawHand(self.off, false);
            return;
        }
        if (self.drawHand(self.arm, false)) return;
        if (self.offInHand()) _ = self.drawHand(self.off, true);
    }

    fn drawHand(self: *const Hero, a: Armament, left: bool) bool {
        const wrist = self.xf[if (left) WRL else WRR];
        const grip = gripFrame(wrist, self.rest, left);
        switch (a) {
            .sword => {},
            .bow => {
                rl.drawMesh(self.bow, self.mat, grip);
                for (self.stringXf) |sm| rl.drawMesh(self.bowString, self.mat, sm);
                if (self.nockVis) rl.drawMesh(self.bowNock, self.mat, self.nockXf);
                return true;
            },
            .bell => rl.drawMesh(self.bell, self.mat, grip),
            .shield => rl.drawMesh(self.shield, self.mat, mul(shieldFit(left), wrist)),
            .wand => rl.drawMesh(self.wand, self.mat, wrist),
        }
        return false;
    }

    pub fn shoulderPoint(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + self.rest[CHEST].y, self.pos.z);
    }
};

pub fn setHumanoid(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    setJoint(wx, &rest, i, @intCast(PARENT[i]), animRot);
}
const setLocal = setHumanoid;

pub fn placeSword(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, animRot: rl.Matrix, left: bool) void {
    wx[SWORD] = mul(animRot, gripFrame(wx[if (left) WRL else WRR], rest, left));
}

pub fn gripFrame(wrist: rl.Matrix, rest: [N]rl.Vector3, left: bool) rl.Matrix {
    const d = mathx.subV(rest[SWORD], rest[WRR]);
    const off = if (left) v3(-d.x, d.y, d.z) else d;
    return mul(tr(off.x, off.y, off.z), wrist);
}

pub const ArmSide = struct {
    sh: usize,
    el: usize,
    wr: usize,
    mirror: f32,
};

pub fn armSide(left: bool, authoredLeft: bool) ArmSide {
    return .{
        .sh = if (left) SHL else SHR,
        .el = if (left) ELL else ELR,
        .wr = if (left) WRL else WRR,
        .mirror = if (left == authoredLeft) 1.0 else -1.0,
    };
}

pub fn setJoint(wx: []rl.Matrix, rest: []const rl.Vector3, i: usize, p: usize, animRot: rl.Matrix) void {
    const off = mathx.subV(rest[i], rest[p]);
    wx[i] = mul(mul(animRot, tr(off.x, off.y, off.z)), wx[p]);
}

pub fn legChain(wx: []rl.Matrix, rest: []const rl.Vector3, ph: f32, m: f32, runB: f32, sag: f32, lat: f32, side: f32, hip: usize, knee: usize, sole: SolePatch) void {
    const ank = sole.bone;
    const phS = if (sag >= 0) ph else -ph;
    const sagW = @abs(sag) * m;
    const hipFlex = mathx.lerpF(sampleCurve(HIP_FLEX, phS), sampleCurve(RUN_HIP, phS), runB) * sagW;
    const kneeWR = mathx.lerpF(sampleCurve(KNEE_FLEX, phS), sampleCurve(RUN_KNEE, phS), runB);
    const ankDorsi = mathx.lerpF(sampleCurve(ANK_DORSI, phS), sampleCurve(RUN_ANK, phS), runB) * sagW;
    const latW = @abs(lat) * m;
    const thigh = rest[hip].y - rest[knee].y;
    const shank = rest[knee].y - rest[ank].y;
    const legLen = thigh + shank;
    const rigS = legLen / LEG_LEN;
    const reach = STRAFE_REACH * rigS; // the measured sweep, scaled onto THIS rig
    const q = ph - @floor(ph);
    const swingLen = 1.0 - STRAFE_STANCE;
    var s: f32 = undefined;
    var w: f32 = -1.0;
    if (q < STRAFE_STANCE) {
        s = reach * (1.0 - 2.0 * q / STRAFE_STANCE);
    } else {
        w = (q - STRAFE_STANCE) / swingLen;
        const v0 = -2.0 * reach * swingLen / STRAFE_STANCE;
        const w2 = w * w;
        const w3 = w2 * w;
        s = -reach * (2.0 * w3 - 3.0 * w2 + 1.0) + v0 * (w3 - 2.0 * w2 + w) + reach * (3.0 * w2 - 2.0 * w3);
    }
    const dx = -lat * s * m;
    const crossing = side * lat > 0;
    const inSwing = w >= 0;
    const arc = if (inSwing) mathx.sinf(std.math.pi * w) else 0.0;
    const passF = (if (crossing) @as(f32, STRAFE_CROSS) else -STRAFE_BEHIND) * arc * latW;
    const landF = if (inSwing or !crossing) 0.0 else STRAFE_LAND * (1.0 - 2.0 * q / STRAFE_STANCE) * latW;
    const latHip = passF + landF;
    const clear = STRAFE_CLEAR * rigS * arc * latW;
    const rootS = mathx.maxF(1e-4, @sqrt(wx[ROOT].m0 * wx[ROOT].m0 + wx[ROOT].m1 * wx[ROOT].m1 + wx[ROOT].m2 * wx[ROOT].m2));
    const hipW = rl.math.vector3Transform(mathx.subV(rest[hip], rest[ROOT]), wx[ROOT]);
    const vert = mathx.maxF(0.1 * legLen, (hipW.y - SOLE_Y) / rootS - rest[ank].y - clear);
    const span = @sqrt(vert * vert + dx * dx);
    const abd = mathx.degrees(std.math.atan2(dx, vert));
    const totalHip = hipFlex + latHip;
    const cosK = mathx.clampF((span - thigh * mathx.cosf(mathx.radians(totalHip))) / shank, -1.0, 1.0);
    const latKnee = totalHip + mathx.degrees(std.math.acos(cosK));
    const kneeW = mathx.smoothstep(0.10, 0.55, latW);
    const kneeFlex = mathx.lerpF(mathx.lerpF(IDLE_KNEE, kneeWR, sagW), mathx.maxF(0, latKnee), kneeW);
    const held = if (inSwing) 1.0 - arc else 1.0;
    const flat = (latHip - kneeFlex) * held * latW;
    const frontal = mathx.lerpF(-side * HIP_ADDUCT, abd, latW);
    const roll = -frontal * held;
    setJoint(wx, rest, hip, ROOT, mul(rx(-hipFlex - latHip), rz(frontal)));
    setJoint(wx, rest, knee, hip, rx(kneeFlex));
    const wscale = mathx.maxF(1e-4, @sqrt(wx[knee].m0 * wx[knee].m0 + wx[knee].m1 * wx[knee].m1 + wx[knee].m2 * wx[knee].m2));
    var pitch = -ankDorsi + flat;
    var pass: u8 = 0;
    while (pass < 5) : (pass += 1) {
        setJoint(wx, rest, ank, knee, mul3(rx(pitch), ry(side * FOOT_TOEOUT), rz(roll)));
        var deepest: f32 = std.math.floatMax(f32);
        var worst = v3(0, 0, 0);
        var worstZ: f32 = 0;
        for ([_]f32{ -sole.halfW, sole.halfW }) |cx| {
            for ([_]f32{ -sole.heel, sole.toe }) |cz| {
                const c = rl.math.vector3Transform(v3(cx, -sole.drop, cz), wx[ank]);
                if (c.y < deepest) {
                    deepest = c.y;
                    worst = c;
                    worstZ = cz;
                }
            }
        }
        if (deepest >= SOLE_Y) break;
        // The lever is MEASURED horizontally, not taken from the foot's length: an already steeply pitched
        // foot has most of that length pointing DOWN, and a length-based step badly undershoots.
        const ankW = rl.math.vector3Transform(v3(0, 0, 0), wx[ank]);
        const lever = mathx.maxF(0.02 * wscale, mathx.lenXZ(mathx.subV(worst, ankW)));
        const step = mathx.degrees(std.math.asin(mathx.clampF((SOLE_Y - deepest) / lever, -1, 1)));
        pitch += if (worstZ > 0) -step else step;
    }
}

fn armChain(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, swing: f32, m: f32, runB: f32, sprintB: f32, side: f32, carry: f32, sh: usize, el: usize, wr: usize) void {
    const carryMove = carry * m;
    const sprint = carry * mathx.clampF(sprintB, 0, 1) * m;
    const sw = swing * (1.0 - CARRY_DAMP * carry) * (1.0 - CARRY_SWING_STILL * sprint);
    const walkElbow = mathx.maxF(6.0, 4.0 + 0.8 * sw);
    const runElbow = mathx.lerpF(RUN_ELBOW, CARRY_ELBOW_RUN, carry);
    const elbow = mathx.maxF(mathx.lerpF(IDLE_ELBOW, mathx.lerpF(walkElbow, runElbow, runB), m), CARRY_ELBOW * carry);
    const abd = ARM_ABD + CARRY_ABD_RUN * sprint;
    setLocal(wx, sh, rest, mul(rx(-sw), rz(side * abd)));
    setLocal(wx, el, rest, rx(-elbow));
    const lift = CARRY_WRIST_LIFT * mathx.lerpF(CARRY_LIFT_WALK, 1.0, mathx.clampF(sprintB, 0, 1)) * carryMove;
    setLocal(wx, wr, rest, mul(rx(lift), ry(CARRY_WRIST_YAW * sprint)));
}

fn rollLeg(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, tuck: f32, f: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    setLocal(wx, hip, rest, mul(rx(-ROLL_HIP * f * tuck), rz(-side * HIP_ADDUCT)));
    setLocal(wx, knee, rest, rx(mathx.lerpF(IDLE_KNEE, ROLL_KNEE * f, tuck)));
    setLocal(wx, ank, rest, ry(side * FOOT_TOEOUT));
}
fn jumpLeg(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, drive: f32, reach: f32, tuck: f32, f: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    const hipA = JUMP_TOEOFF * drive - JUMP_TUCK_HIP * f * tuck - JUMP_REACH_HIP * reach;
    setLocal(wx, hip, rest, mul(rx(hipA), rz(-side * HIP_ADDUCT)));
    setLocal(wx, knee, rest, rx(IDLE_KNEE + JUMP_TUCK_KNEE * f * tuck + JUMP_REACH_KNEE * reach));
    setLocal(wx, ank, rest, mul(rx(-JUMP_TOE_PLANTAR * drive + JUMP_REACH_DORSI * reach), ry(side * FOOT_TOEOUT)));
}
fn jumpArm(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, drive: f32, reach: f32, tuck: f32, side: f32, sh: usize, el: usize, wr: usize) void {
    const up = JUMP_ARM_UP * (JUMP_ARM_HOLD + (1.0 - JUMP_ARM_HOLD) * drive) * (1.0 - JUMP_ARM_DROP * reach);
    setLocal(wx, sh, rest, mul(rx(-up), rz(side * (ARM_ABD + JUMP_ARM_OUT * reach))));
    setLocal(wx, el, rest, rx(-(IDLE_ELBOW + JUMP_ARM_ELBOW * drive + JUMP_ARM_FOLD * tuck)));
    setLocal(wx, wr, rest, rl.math.matrixIdentity());
}
fn sitLeg(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, side: f32, hip: usize, knee: usize, ank: usize) void {
    setLocal(wx, hip, rest, mul(rx(-SIT_HIP_FLEX), rz(side * SIT_HIP_ABD)));
    setLocal(wx, knee, rest, rx(SIT_KNEE));
    setLocal(wx, ank, rest, mul(rx(SIT_ANKLE), ry(side * FOOT_TOEOUT * 2.0)));
}
fn rollArm(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, tuck: f32, f: f32, side: f32, sh: usize, el: usize, wr: usize) void {
    setLocal(wx, sh, rest, mul(rx(-ROLL_SHOULDER * f * tuck), rz(side * ARM_ABD)));
    setLocal(wx, el, rest, rx(-mathx.lerpF(IDLE_ELBOW, ROLL_ELBOW * f, tuck)));
    setLocal(wx, wr, rest, rl.math.matrixIdentity());
}

const ROUND_EDGES = true;
pub const ROUND_E: f32 = 0.34;
/// A fillet costs a box 6 quads → segs×sides, so the TESSELLATION IS SIZED TO THE PART. Measured off the part's
/// largest dimension in units of stature, so it holds if the rig is ever rescaled.
pub fn roundGrid(size: rl.Vector3) struct { segs: i32, sides: i32 } {
    const big = @max(@max(@abs(size.x), @abs(size.y)), @abs(size.z)) / H;
    if (big >= 0.12) return .{ .segs = 6, .sides = 12 };
    if (big >= 0.05) return .{ .segs = 5, .sides = 10 };
    return .{ .segs = 3, .sides = 6 };
}

pub fn slab(b: *Builder, c: rl.Vector3, size: rl.Vector3, col: rl.Color) void {
    if (!ROUND_EDGES) return b.addCube(c, size, col);
    const g = roundGrid(size);
    b.addRoundBox(c, size, ROUND_E, g.segs, g.sides, col);
}

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = abdomenMesh();
    mesh[CHEST] = chestMesh();
    mesh[NECK] = neckMesh();
    mesh[HEAD] = headMesh();
    mesh[HIPL] = thighMesh();
    mesh[KNEEL] = shankMesh();
    mesh[ANKL] = footMesh();
    mesh[HIPR] = thighMesh();
    mesh[KNEER] = shankMesh();
    mesh[ANKR] = footMesh();
    mesh[SHL] = upperArmMesh(true);
    mesh[ELL] = forearmMesh();
    mesh[WRL] = handMesh();
    mesh[SHR] = upperArmMesh(false);
    mesh[ELR] = forearmMesh();
    mesh[WRR] = handMesh();
    mesh[SWORD] = swordMesh();
    return mesh;
}

fn swordMesh() rl.Mesh {
    var b = Builder.init();
    const s = v3(0.5 * OUT_CA, 0, 0.5 * OUT_SA);
    const n = v3(-0.5 * GRIP_CA * OUT_SA, 0.5 * GRIP_SA, 0.5 * GRIP_CA * OUT_CA);
    const a = v3(-0.5 * GRIP_SA * OUT_SA, -0.5 * GRIP_CA, 0.5 * GRIP_SA * OUT_CA);
    b.setMat(.leather);
    b.addCylinder(bladeAt(0.026), bladeAt(-0.05), 0.014 * H, 0.012 * H, 6, BELT);
    b.setMat(.steel);
    b.addBox(bladeAt(-0.058), scaleV(s, 0.028 * H), scaleV(a, 0.028 * H), scaleV(n, 0.028 * H), BRASS);
    b.addBox(bladeAt(0.036), scaleV(n, 0.115 * H), scaleV(a, 0.02 * H), scaleV(s, 0.03 * H), STEEL);
    b.addBox(bladeAt(0.231), scaleV(n, 0.048 * H), scaleV(a, 0.37 * H), scaleV(s, 0.012 * H), STEEL);
    b.addCylinder(bladeAt(0.416), bladeAt(0.481), 0.020 * H, 0.001, 4, STEEL_DK);
    return b.toMesh();
}

/// A FANG, HAFTED. Ground out of a kobold's tooth (`item.describe`), so the blade is BONE and tapers the whole
/// way instead of running parallel and stopping: no fuller, no crossguard worth the name, and the cord wrap
/// stands in for a grip. The visible point is at t 0.28 where the capsule reaches 0.37 — the sword's own
/// proportion, which is the room a stroke needs over what it looks like.
fn dirkMesh() rl.Mesh {
    var b = Builder.init();
    const s = v3(0.5 * OUT_CA, 0, 0.5 * OUT_SA);
    const n = v3(-0.5 * GRIP_CA * OUT_SA, 0.5 * GRIP_SA, 0.5 * GRIP_CA * OUT_CA);
    const a = v3(-0.5 * GRIP_SA * OUT_SA, -0.5 * GRIP_CA, 0.5 * GRIP_SA * OUT_CA);
    b.setMat(.leather);
    b.addCylinder(bladeAt(0.020), bladeAt(-0.042), 0.0135 * H, 0.0115 * H, 6, BELT);
    b.addCylinder(bladeAt(0.006), bladeAt(0.018), 0.0150 * H, 0.0150 * H, 6, LEATHER);
    b.setMat(.steel);
    b.addBox(bladeAt(-0.048), scaleV(s, 0.020 * H), scaleV(a, 0.018 * H), scaleV(n, 0.020 * H), BRASS);
    b.addBox(bladeAt(0.030), scaleV(n, 0.052 * H), scaleV(a, 0.013 * H), scaleV(s, 0.022 * H), STEEL_DK);
    b.setMat(.plain); // bone, which is what the skeletons are cut from too
    b.addCylinder(bladeAt(0.040), bladeAt(0.170), 0.0185 * H, 0.0125 * H, 5, art.BONE);
    b.addCylinder(bladeAt(0.170), bladeAt(0.280), 0.0125 * H, 0.0008 * H, 5, art.BONE);
    return b.toMesh();
}

/// BOG-OAK SHOD WITH IRON, and the mass is at the END of it — a haft that swells into a head, three bands
/// round the swell and an iron cap over the top. It reaches half again what the dirk does and the head is
/// three times the wrist, which is the whole of why it costs what it costs to swing.
fn clubMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.wood);
    b.addCylinder(bladeAt(-0.055), bladeAt(0.360), 0.0175 * H, 0.0245 * H, 7, art.BARK);
    b.addCapsule(bladeAt(0.360), bladeAt(0.610), 0.0470 * H, 0.0520 * H, 8, art.BARK_LIVE);
    b.setMat(.steel);
    b.addCylinder(bladeAt(-0.062), bladeAt(-0.048), 0.0205 * H, 0.0205 * H, 7, art.IRON);
    b.addCylinder(bladeAt(0.395), bladeAt(0.415), 0.0500 * H, 0.0505 * H, 8, art.IRON);
    b.addCylinder(bladeAt(0.480), bladeAt(0.500), 0.0530 * H, 0.0535 * H, 8, art.IRON);
    b.addCylinder(bladeAt(0.565), bladeAt(0.585), 0.0545 * H, 0.0550 * H, 8, art.IRON);
    b.addCapsule(bladeAt(0.610), bladeAt(0.640), 0.0520 * H, 0.0300 * H, 8, art.IRON);
    return b.toMesh();
}

fn bellMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xBE11);

    b.setMat(.wood);
    b.addCapsule(bellAt(BELL_GRIP_T0), bellAt(BELL_GRIP_T0 + 0.018), 0.0105 * H, 0.0088 * H, 7, BELL_HANDLE);
    b.addCapsule(bellAt(BELL_GRIP_T0 + 0.014), bellAt(0.030), 0.0092 * H, 0.0115 * H, 7, BELL_HANDLE);
    b.addCapsule(bellAt(0.030), bellAt(BELL_CROWN_T), 0.0115 * H, 0.0080 * H, 7, BELL_HANDLE);

    b.setMat(.steel);
    b.addCapsule(bellAt(BELL_CROWN_T), bellAt(BELL_CROWN_T + 0.008), BELL_MOUTH_R * 0.30, BELL_MOUTH_R * 0.36, 12, BELL_BRONZE_LT);

    const BANDS = 6;
    const span = BELL_MOUTH_T - BELL_CROWN_T - 0.008;
    var i: i32 = 0;
    while (i < BANDS) : (i += 1) {
        const f0 = @as(f32, @floatFromInt(i)) / @as(f32, BANDS);
        const f1 = (@as(f32, @floatFromInt(i)) + 1.0) / @as(f32, BANDS);
        const t0 = BELL_CROWN_T + 0.008 + span * f0;
        const t1 = BELL_CROWN_T + 0.008 + span * f1;
        const r0 = bellR(f0) * rng.range(0.985, 1.015);
        const r1 = bellR(f1) * rng.range(0.985, 1.015);
        const tone = if (@mod(i, 2) == 0) BELL_BRONZE else BELL_BRONZE_LT;
        b.addCylinder(bellAt(t0), bellAt(t1), r0, r1, 14, tone);
        b.addCylinder(bellAt(t0), bellAt(t1), r0 - BELL_WALL, r1 - BELL_WALL, 14, BELL_BORE);
    }
    b.addCylinder(bellAt(BELL_MOUTH_T), bellAt(BELL_MOUTH_T - 0.004), BELL_MOUTH_R, BELL_MOUTH_R - BELL_WALL, 14, BELL_BRONZE_LT);
    const waistT = BELL_CROWN_T + 0.008 + span * 0.62;
    b.addCylinder(bellAt(waistT - 0.004), bellAt(waistT + 0.004), bellR(0.62) * 1.035, bellR(0.62) * 1.035, 14, BELL_BRONZE_LT);

    const hang = bellAt(BELL_MOUTH_T - 0.020);
    const off = BELL_MOUTH_R * 0.30;
    b.addCylinder(bellAt(BELL_CROWN_T + 0.012), v3(hang.x + off, hang.y, hang.z + off * 0.4), 0.0022 * H, 0.0026 * H, 5, BELL_BRONZE);
    b.addBlob(v3(hang.x + off, hang.y, hang.z + off * 0.4), v3(0.0072 * H, 0.0080 * H, 0.0072 * H), 4, 8, BELL_BRONZE_LT);
    return b.toMesh();
}

/// The skirt's radius at `u` (0 at the shoulder, 1 at the mouth). The exponent IS the bell: under 1 it bulges
/// like a pot, at 1 it is a cone, and past ~1.5 the wall stays tucked in and then throws out to the rim.
fn bellR(u: f32) f32 {
    return BELL_MOUTH_R * (0.34 + 0.66 * std.math.pow(f32, mathx.clampF(u, 0, 1), 1.7));
}

fn guitarMesh() rl.Mesh {
    var b = Builder.init();
    const a = mathx.normV(v3(0.74, 0.62, 0.26));
    const d = v3(0, 0.40, 0.92);
    const n = mathx.normV(mathx.subV(d, mathx.scaleV(a, d.x * a.x + d.y * a.y + d.z * a.z)));
    art.guitarInto(&b, .{
        .o = v3(-0.30, -0.09, 0.14),
        .w = mathx.crossV(a, n),
        .a = a,
        .n = n,
        .s = 1.35,
    });
    return b.toMesh();
}

pub fn boltMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(0.070, 0.070, 0.155), 7, 11, CHAOS_MOTE);
    b.addBlob(v3(0, 0, 0.020), v3(0.040, 0.040, 0.095), 6, 9, CHAOS_HOT);
    return b.toModel(shader);
}

fn rootTendrilMesh(variant: u32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x600751 +% variant *% 7919);
    b.setMat(.wood);
    const bark = mathx.lerpColor(ROOT_BARK, ROOT_BARK_LT, @as(f32, @floatFromInt(variant)) / @as(f32, ROOT_KINDS - 1));
    // The CURL is drawn ONCE and applied every segment, so the thing arcs; re-rolled per segment it wanders, and
    // a wander of straight capsules is a chain of elbows. BRACKETED BOTH SIDES: at 0.03–0.065 they read as grave
    // markers, far past this as croquet hoops. PER SEGMENT — the total arc is `curl` × the segment count.
    const curl = rng.range(0.069, 0.109);
    const sway = rng.range(-0.07, 0.07);
    var p = v3(0, -0.10 * H, 0);
    var dir = mathx.normV(v3(0, 1.0, rng.range(0.03, 0.11)));
    var r = ROOT_R0;
    var i: u32 = 0;
    while (i < ROOT_SEGS) : (i += 1) {
        const k = (@as(f32, @floatFromInt(i)) + 1.0) / @as(f32, ROOT_SEGS);
        const step = ROOT_LEN / @as(f32, ROOT_SEGS) * rng.range(0.84, 1.16);
        const nr = mathx.lerpF(ROOT_R0, ROOT_R1, k) * rng.range(0.90, 1.10);
        const to = mathx.addV(p, mathx.scaleV(dir, step));
        b.addCapsule(p, to, r, nr, 9, bark);
        p = to;
        r = nr;
        dir = mathx.normV(v3(
            dir.x + (sway + rng.range(-0.05, 0.05)) * (0.4 + k),
            dir.y - curl * (0.4 + k),
            dir.z + (curl * 0.45 + rng.range(-0.05, 0.05)) * (0.4 + k),
        ));
    }
    b.addBlob(p, v3(r * 1.30, r * 0.95, r * 1.30), 4, 9, ROOT_HEART);
    var s: u32 = 0;
    while (s < 3) : (s += 1) {
        const base = mathx.lerpV(v3(0, 0, 0), p, rng.range(0.40, 0.78));
        const a = rng.angle();
        const len = ROOT_LEN * rng.range(0.11, 0.19);
        const out = v3(base.x + mathx.cosf(a) * len * 0.55, base.y + rng.range(0.75, 1.15) * len, base.z + mathx.sinf(a) * len * 0.55);
        const sr = ROOT_R1 * rng.range(1.0, 1.5);
        b.addCapsule(base, out, sr * 1.5, sr, 7, bark);
    }
    return b.toMesh();
}

fn wandMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x7A4D91);
    const segs = 5;
    b.setMat(.wood);
    var prev = wandAt(-WAND_BUTT_T);
    var i: i32 = 0;
    while (i < segs) : (i += 1) {
        const f0 = @as(f32, @floatFromInt(i)) / @as(f32, segs);
        const f1 = (@as(f32, @floatFromInt(i)) + 1.0) / @as(f32, segs);
        var to = wandAt(WAND_TIP_T * f1);
        to.x += WAND_LEN * 0.035 * rng.range(-1.0, 1.0) * f1;
        to.z += WAND_LEN * 0.030 * rng.range(-1.0, 1.0) * f1;
        const r0 = WAND_R * mathx.lerpF(1.20, 0.80, f0) * rng.range(0.94, 1.06);
        const r1 = WAND_R * mathx.lerpF(1.20, 0.80, f1) * rng.range(0.94, 1.06);
        b.addCapsule(prev, to, r0, r1, 7, if (@mod(i, 2) == 0) WAND_WOOD else WAND_WOOD_LT);
        if (i > 0 and i < segs - 1) {
            const kn = offAxis(mathx.lerpV(prev, to, rng.range(0.30, 0.70)), r1 * 0.55, rng.range(0, std.math.tau));
            b.addBlob(kn, v3(r1 * 0.85, r1 * 0.85, r1 * 0.85), 4, 7, WAND_WOOD_LT);
        }
        prev = to;
    }

    const turns = 6;
    var t: i32 = 0;
    while (t < turns) : (t += 1) {
        const f0 = -0.042 + 0.092 * (@as(f32, @floatFromInt(t)) + 0.15) / @as(f32, turns);
        const f1 = -0.042 + 0.092 * (@as(f32, @floatFromInt(t)) + 0.85) / @as(f32, turns);
        const rr = WAND_R * rng.range(1.20, 1.34);
        b.addCapsule(wandAt(f0), wandAt(f1), rr, rr, 8, WAND_BIND);
    }

    b.setMat(.steel);
    const neck = wandAt(WAND_TIP_T - 0.052);
    // Barely proud of the rod it bands: at 1.15 of the shaft radius the pair of them read as a lampshade.
    b.addCapsule(wandAt(WAND_TIP_T - 0.078), neck, WAND_R * 1.02, WAND_R * 0.94, 8, WAND_FERRULE);
    const stone = wandAt(WAND_TIP_T);
    const behind = wandAt(WAND_TIP_T - 0.020);
    var c: i32 = 0;
    while (c < 3) : (c += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(c)) / 3.0 + rng.range(-0.22, 0.22);
        const tipCl = offAxis(behind, WAND_STONE_R * 0.66 * rng.range(0.86, 1.06), a);
        b.addCapsule(neck, tipCl, WAND_R * 0.40, WAND_R * 0.24, 5, WAND_FERRULE);
    }

    b.setMat(.marble);
    b.addBlob(stone, v3(WAND_STONE_R * 1.06, WAND_STONE_R * 0.94, WAND_STONE_R), 6, 11, WAND_STONE);
    b.addBlob(stone, v3(WAND_STONE_R * 0.66, WAND_STONE_R * 0.60, WAND_STONE_R * 0.70), 5, 9, WAND_STONE_HOT);
    return b.toMesh();
}

fn shieldMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5C1E1D);
    b.setMat(.wood);
    b.addBlob(v3(0, 0, 0), v3(SHIELD_R, SHIELD_R, SHIELD_THICK), 5, 16, SHIELD_WOOD);
    const dome = struct {
        fn at(rho: f32) f32 {
            const t = mathx.clampF(rho / SHIELD_R, 0, 1);
            return SHIELD_THICK * @sqrt(mathx.maxF(1.0 - t * t, 0));
        }
    }.at;
    const seams = 3;
    var i: i32 = 0;
    while (i < seams) : (i += 1) {
        const f = (@as(f32, @floatFromInt(i)) + 1.0) / (@as(f32, seams) + 1.0);
        const y = mathx.lerpF(-SHIELD_R, SHIELD_R, f) * rng.range(0.90, 1.10);
        const half = @sqrt(mathx.maxF(SHIELD_R * SHIELD_R - y * y, 1e-4)) * 0.84;
        const rEnd = @sqrt(half * half + y * y);
        for ([_]f32{ -1, 1 }) |side| {
            b.addCapsule(
                v3(0, y, dome(@abs(y))),
                v3(side * half, y, dome(rEnd)),
                0.0050 * H,
                0.0038 * H,
                5,
                SHIELD_WOOD_LT,
            );
        }
    }
    b.setMat(.steel);
    const straps = 13;
    var k: i32 = 0;
    while (k < straps) : (k += 1) {
        const a0 = std.math.tau * @as(f32, @floatFromInt(k)) / @as(f32, straps);
        const a1 = a0 + std.math.tau / @as(f32, straps) * rng.range(0.90, 1.06);
        const r0 = SHIELD_R * rng.range(0.985, 1.005);
        b.addCapsule(
            v3(r0 * mathx.cosf(a0), r0 * mathx.sinf(a0), 0),
            v3(r0 * mathx.cosf(a1), r0 * mathx.sinf(a1), 0),
            0.0090 * H,
            0.0082 * H,
            6,
            SHIELD_IRON,
        );
    }
    b.addBlob(
        v3(0.004 * H, -0.002 * H, SHIELD_THICK * 0.55),
        v3(0.034 * H, 0.033 * H, 0.030 * H),
        4,
        11,
        SHIELD_BOSS,
    );
    b.setMat(.leather);
    slab(&b, v3(0, 0, -SHIELD_THICK * 1.15), v3(0.090 * H, 0.026 * H, 0.014 * H), LEATHER);
    slab(&b, v3(0, 0, -SHIELD_THICK * 0.9), v3(0.034 * H, 0.052 * H, 0.010 * H), LEATHER_DK);
    return b.toMesh();
}

const scaleV = mathx.scaleV;

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    slab(&b, v3(0, -0.01 * H, 0), v3(0.235 * H, 0.16 * H, 0.175 * H), BELT);
    b.setMat(.cloth);
    slab(&b, v3(0, 0.055 * H, 0), v3(0.215 * H, 0.07 * H, 0.16 * H), TUNIC_DK);
    b.setMat(.steel);
    slab(&b, v3(0, -0.005 * H, 0.0925 * H), v3(0.035 * H, 0.035 * H, 0.012 * H), BRASS);
    b.setMat(.leather);
    slab(&b, v3(0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    slab(&b, v3(-0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    slab(&b, v3(-0.115 * H, -0.045 * H, -0.03 * H), v3(0.05 * H, 0.06 * H, 0.045 * H), LEATHER_DK);
    slab(&b, v3(-0.115 * H, -0.028 * H, -0.03 * H), v3(0.054 * H, 0.02 * H, 0.05 * H), LEATHER);
    const d = v3(0.10, -0.90, -0.42);
    const p1 = v3(0.995, 0.090, 0.042);
    const p2 = v3(0, -0.422, 0.9045);
    const s0 = v3(0.115 * H, -0.045 * H, -0.015 * H);
    const hl = 0.185 * H;
    b.addBox(v3(s0.x + d.x * hl, s0.y + d.y * hl, s0.z + d.z * hl), v3(p1.x * 0.020 * H, p1.y * 0.020 * H, p1.z * 0.020 * H), v3(d.x * hl, d.y * hl, d.z * hl), v3(p2.x * 0.010 * H, p2.y * 0.010 * H, p2.z * 0.010 * H), LEATHER_DK);
    b.setMat(.steel);
    b.addBox(v3(s0.x + d.x * 2 * hl, s0.y + d.y * 2 * hl, s0.z + d.z * 2 * hl), v3(p1.x * 0.023 * H, p1.y * 0.023 * H, p1.z * 0.023 * H), v3(d.x * 0.014 * H, d.y * 0.014 * H, d.z * 0.014 * H), v3(p2.x * 0.012 * H, p2.y * 0.012 * H, p2.z * 0.012 * H), STEEL_DK);
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    slab(&b, v3(0, -0.01 * H, 0), v3(0.205 * H, 0.13 * H, 0.145 * H), TUNIC);
    slab(&b, v3(0, 0.075 * H, 0), v3(0.235 * H, 0.09 * H, 0.16 * H), TUNIC);
    slab(&b, v3(0, -0.012 * H, 0.079 * H), v3(0.135 * H, 0.155 * H, 0.014 * H), CAPE);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    slab(&b, v3(0, -0.005 * H, 0), v3(0.285 * H, 0.12 * H, 0.165 * H), TUNIC); // 0.695—0.815 H
    b.setMat(.leather);
    slab(&b, v3(0, 0.035 * H, -0.005 * H), v3(0.305 * H, 0.06 * H, 0.18 * H), LEATHER_DK);
    b.setMat(.cloth);
    slab(&b, v3(0, -0.01 * H, 0.086 * H), v3(0.135 * H, 0.11 * H, 0.012 * H), CAPE);
    slab(&b, v3(0, -0.035 * H, -0.098 * H), v3(0.24 * H, 0.115 * H, 0.016 * H), CAPE);
    b.setMat(.leather);
    slab(&b, v3(0, 0.042 * H, -0.10 * H), v3(0.25 * H, 0.035 * H, 0.02 * H), LEATHER);
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCylinder(v3(0, 0, 0), v3(0, 0.070 * H, 0), 0.040 * H, 0.036 * H, 8, SKIN_DK);
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    slab(&b, v3(0, 0.075 * H, -0.005 * H), v3(0.135 * H, 0.115 * H, 0.15 * H), SKIN);
    slab(&b, v3(0, 0.018 * H, 0.012 * H), v3(0.10 * H, 0.055 * H, 0.125 * H), SKIN);
    slab(&b, v3(0, 0.05 * H, 0.082 * H), v3(0.028 * H, 0.03 * H, 0.03 * H), SKIN_DK);
    b.setMat(.leather);
    slab(&b, v3(0, 0.118 * H, -0.025 * H), v3(0.145 * H, 0.05 * H, 0.15 * H), HAIR);
    slab(&b, v3(0, 0.055 * H, -0.078 * H), v3(0.135 * H, 0.125 * H, 0.035 * H), HAIR);
    slab(&b, v3(0, 0.012 * H, -0.092 * H), v3(0.05 * H, 0.05 * H, 0.035 * H), HAIR);
    slab(&b, v3(0, 0.092 * H, 0.0 * H), v3(0.142 * H, 0.018 * H, 0.152 * H), LEATHER_DK);
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.078 * H, 0.058 * H, 10, CLOTHDK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -0.002 * H, 0), v3(0, -0.075 * H, 0), 0.088 * H, 0.072 * H, 10, LEATHER_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.09 * H, 0), 0.058 * H, 0.062 * H, 10, CLOTHDK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -0.09 * H, 0), v3(0, -SEG_SHANK * H, 0), 0.064 * H, 0.036 * H, 10, BOOT);
    slab(&b, v3(0, -0.02 * H, 0.052 * H), v3(0.062 * H, 0.06 * H, 0.026 * H), LEATHER);
    return b.toMesh();
}

fn footMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    // Boot: sole rests on the ground (ankle joint is ANKLE_Y=0.039 H up), toes forward +Z.
    const ay = 0.039 * H;
    slab(&b, v3(0, -ay + 0.028 * H, 0.045 * H), v3(0.085 * H, 0.056 * H, 0.19 * H), BOOT);
    slab(&b, v3(0, -ay + 0.075 * H, -0.02 * H), v3(0.075 * H, 0.05 * H, 0.09 * H), BOOT);
    return b.toMesh();
}

fn upperArmMesh(big: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    if (big) {
        slab(&b, v3(0, -0.005 * H, 0), v3(0.125 * H, 0.10 * H, 0.13 * H), LEATHER);
        b.setMat(.steel);
        slab(&b, v3(0, 0.048 * H, 0), v3(0.105 * H, 0.045 * H, 0.115 * H), STEEL_DK);
    } else {
        slab(&b, v3(0, 0.005 * H, 0), v3(0.105 * H, 0.085 * H, 0.115 * H), LEATHER);
    }
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.052 * H, 0.044 * H, 9, TUNIC);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.065 * H, 0), 0.044 * H, 0.040 * H, 9, TUNIC);
    b.setMat(.leather);
    b.addCylinder(v3(0, -0.065 * H, 0), v3(0, -SEG_FOREARM * H, 0), 0.047 * H, 0.034 * H, 9, LEATHER);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    slab(&b, v3(0, -0.05 * H, 0.005 * H), v3(0.05 * H, 0.10 * H, 0.045 * H), BOOT);
    return b.toMesh();
}


fn testHero() Hero {
    var h = Hero{
        .mesh = undefined,
        .bow = undefined,
        .bowString = undefined,
        .bowNock = undefined,
        .shield = undefined,
        .wand = undefined,
        .bell = undefined,
        .dirk = undefined,
        .club = undefined,
        .roots = undefined,
        .guitar = undefined,
        .mat = undefined,
        .rest = restPositions(),
    };
    h.pose();
    return h;
}

test "the DRAUGHT is committed like the other two: inputs buffer, they do not fire through it" {
    var h = testHero();
    try std.testing.expect(h.startDrink());
    const stamAtDrink = h.stam.cur;

    h.requestAttack(.light);
    try std.testing.expect(h.drinking);
    try std.testing.expect(!h.attacking);
    try std.testing.expectEqual(stamAtDrink, h.stam.cur);
    try std.testing.expect(h.queued != null);

    h.requestRoll(v3(0, 0, 1));
    try std.testing.expect(!h.rolling and h.drinking);

    var guard: u32 = 0;
    while (h.drinking and guard < 500) : (guard += 1) h.tickDrink(0.016);
    try std.testing.expect(!h.drinking);
    try std.testing.expect(h.rolling);
    try std.testing.expect(h.queued == null);
}

test "A DRAUGHT IS A SHUFFLE, and the legs stay the gait's" {
    try std.testing.expect(DRINK_SPEED > 0.0 and DRINK_SPEED < GUARD_SPEED);
    var h = testHero();
    try std.testing.expect(h.startDrink());
    h.tickDrink(combat.FLASK_DRINK_DUR * 0.4);
    const dk = h.drinkLevels();
    try std.testing.expect(dk.lift > 0.5 and dk.tip > 0.0);
    h.drinking = false;
    const dry = h.drinkLevels();
    try std.testing.expectEqual(@as(f32, 0), dry.lift);
    try std.testing.expectEqual(@as(f32, 0), dry.tip);
}

test "THE BOW TAKES THE SHIELD, and it takes it by being asked rather than by clearing a flag" {
    var h = testHero();
    h.setGuard(true);
    try std.testing.expect(h.guarding);

    try std.testing.expect(h.swapArm());
    try std.testing.expect(h.bowOut());
    h.setGuard(true);
    try std.testing.expect(!h.guarding);
    try std.testing.expect(!h.canGuard());

    try std.testing.expect(h.swapArm());
    h.setGuard(true);
    try std.testing.expect(h.guarding);
}

test "the swap is refused mid-action, so a weapon cannot change hands inside a swing" {
    var h = testHero();
    h.startAttack(.light);
    try std.testing.expect(!h.swapArm());
    try std.testing.expect(!h.bowOut());
    var g = testHero();
    g.startRoll(v3(0, 0, 1));
    try std.testing.expect(!g.swapArm());
    var d = testHero();
    d.enterStun(.heavy);
    try std.testing.expect(!d.swapArm());
    var k = testHero();
    k.enterDeath();
    try std.testing.expect(!k.swapArm());
}

test "AIMING NEEDS THE BOW, and a LOOSE does not cost him the aim" {
    var h = testHero();
    h.setAim(true);
    try std.testing.expect(!h.aiming);

    _ = h.swapArm();
    h.setAim(true);
    try std.testing.expect(h.aiming);
    h.requestShot(true);
    try std.testing.expect(h.shooting and h.shotAimed);
    h.setAim(true);
    try std.testing.expect(h.aiming);
    try std.testing.expect(h.canAim());

    var r = testHero();
    _ = r.swapArm();
    r.startRoll(v3(0, 0, 1));
    r.setAim(true);
    try std.testing.expect(!r.aiming);
    var s = testHero();
    _ = s.swapArm();
    s.sprinting = true;
    s.setAim(true);
    try std.testing.expect(!s.aiming);
    var e = testHero();
    _ = e.swapArm();
    e.stam.cur = 0;
    e.setAim(true);
    try std.testing.expect(!e.aiming);
}

test "an AIMED shot is refused without an aim, which is what makes L2 a stance and not a modifier" {
    var h = testHero();
    _ = h.swapArm();
    h.requestShot(true);
    try std.testing.expect(!h.shooting);
    h.setAim(true);
    h.requestShot(true);
    try std.testing.expect(h.shooting and h.shotAimed);

    var q = testHero();
    _ = q.swapArm();
    q.requestShot(false);
    try std.testing.expect(q.shooting and !q.shotAimed);

    var w = testHero();
    w.requestShot(false);
    w.requestShot(true);
    try std.testing.expect(!w.shooting);
}

test "THE SHAFT LEAVES EXACTLY ONCE, on the frame the loose crosses its own knot" {
    for ([_]bool{ false, true }) |aimed| {
        var h = testHero();
        _ = h.swapArm();
        if (aimed) h.setAim(true);
        h.requestShot(aimed);
        try std.testing.expect(h.shooting);
        var fired: u32 = 0;
        var guard: u32 = 0;
        while (h.shooting and guard < 2000) : (guard += 1) {
            h.updateShot(1.0 / 240.0, null);
            if (h.loosed) fired += 1;
        }
        try std.testing.expectEqual(@as(u32, 1), fired);
        try std.testing.expect(!h.shooting);
    }
    var c = testHero();
    _ = c.swapArm();
    c.requestShot(false);
    var fired: u32 = 0;
    var guard: u32 = 0;
    while (c.shooting and guard < 100) : (guard += 1) {
        c.updateShot(0.25, null);
        if (c.loosed) fired += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), fired);
}

test "AN EMPTY QUIVER REFUSES THE SHOT, and it does not bill him for the one that never left" {
    var h = testHero();
    _ = h.swapArm();
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.ready());
    var fired: u32 = 0;
    while (fired < combat.ARROWS_MAX) : (fired += 1) {
        h.stam.reset();
        h.requestShot(false);
        try std.testing.expect(h.shooting);
        while (h.shooting) h.updateShot(1.0 / 60.0, null);
    }
    try std.testing.expectEqual(@as(u8, 0), h.quiver.ready());
    h.stam.reset();
    const stamBefore = h.stam.cur;
    h.requestShot(false);
    try std.testing.expect(!h.shooting);
    try std.testing.expect(h.stamRefused > 0);
    try std.testing.expectApproxEqAbs(stamBefore, h.stam.cur, 1e-5);
    h.respawnNow();
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.ready());
}

test "THE FIRE ARROW ADDS FIRE and takes nothing off the shaft's own physical" {
    for ([_]combat.Hit{ BOW_QUICK_HIT, BOW_AIMED_HIT }) |base| {
        const tipped = fireTipped(base);
        try std.testing.expectApproxEqAbs(base.dmg, tipped.dmg, 1e-5);
        try std.testing.expectApproxEqAbs(base.poise, tipped.poise, 1e-5);
        try std.testing.expectApproxEqAbs(base.stance, tipped.stance, 1e-5);
        try std.testing.expectApproxEqAbs(base.dmg * FIRE_ARROW_FRAC, tipped.elem.at(.fire), 1e-4);
        try std.testing.expectApproxEqAbs(@as(f32, 0), tipped.elem.at(.cold), 1e-6);
        try std.testing.expect(tipped.raw() > base.raw());
    }
    try std.testing.expect(fireTipped(BOW_QUICK_HIT).raw() < BOW_AIMED_HIT.raw());
    const tipped = fireTipped(BOW_AIMED_HIT);
    var dry = combat.Vitals.initFoe(200, 99, 999).withRes(combat.resists(.{ .fire = -50 }));
    var wet = combat.Vitals.initFoe(200, 99, 999).withRes(combat.resists(.{ .fire = 50 }));
    try std.testing.expect(dry.damageFrom(tipped) > wet.damageFrom(tipped));
    try std.testing.expect(wet.damageFrom(tipped) > BOW_AIMED_HIT.dmg);
}

test "the arrow he DREW is the arrow that flies, whatever he cycles to mid-shot" {
    var h = testHero();
    _ = h.swapArm();
    try std.testing.expect(h.cycleArrow());
    try std.testing.expectEqual(combat.ArrowKind.fire, h.quiver.sel);
    h.stam.reset();
    h.requestShot(false);
    try std.testing.expect(h.shooting);
    try std.testing.expectEqual(combat.ArrowKind.fire, h.shotArrow);
    try std.testing.expectEqual(combat.FIRE_ARROWS_MAX - 1, h.quiver.count(.fire));
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.count(.plain));
    try std.testing.expect(!h.cycleArrow());
    try std.testing.expectEqual(combat.ArrowKind.fire, h.shotArrow);
    try std.testing.expect(h.shotBlow().elem.any());
    while (h.shooting) h.updateShot(1.0 / 60.0, null);
    try std.testing.expect(h.cycleArrow());
    h.stam.reset();
    h.requestShot(false);
    try std.testing.expectEqual(combat.ArrowKind.plain, h.shotArrow);
    try std.testing.expect(!h.shotBlow().elem.any());
}

test "A DRY FIRE QUIVER REFUSES, with plain shafts still on his back" {
    var h = testHero();
    _ = h.swapArm();
    h.quiver.fire = 0;
    try std.testing.expect(h.cycleArrow());
    h.stam.reset();
    const stamBefore = h.stam.cur;
    h.requestShot(false);
    try std.testing.expect(!h.shooting and h.stamRefused > 0);
    try std.testing.expectApproxEqAbs(stamBefore, h.stam.cur, 1e-5);
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.count(.plain));
    h.respawnNow();
    try std.testing.expectEqual(combat.FIRE_ARROWS_MAX, h.quiver.count(.fire));
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.count(.plain));
}

test "the two shots are a jab and a payoff, and every number says which is which" {
    try std.testing.expect(combat.STAM_SHOT < combat.STAM_LIGHT);
    try std.testing.expect(combat.STAM_AIMED > combat.STAM_HEAVY);
    try std.testing.expect(BOW_QUICK_HIT.dmg < ATK_LIGHT_HIT.dmg);
    try std.testing.expect(BOW_AIMED_HIT.dmg < ATK_HEAVY_HIT.dmg);
    try std.testing.expect(BOW_QUICK_HIT.poise < ATK_LIGHT_HIT.poise);
    try std.testing.expect(BOW_AIMED_HIT.poise < ATK_HEAVY_HIT.poise);
    try std.testing.expect(BOW_AIMED_HIT.poise * 2 <= ATK_HEAVY_HIT.poise);
    try std.testing.expect(BOW_AIMED_HIT.stance > 0 and BOW_QUICK_HIT.stance == 0);
    try std.testing.expect(BOW_AIMED_SPEED > BOW_QUICK_SPEED and BOW_QUICK_SPEED > 15.0);
    try std.testing.expect(BOW_AIM_SPEED < GUARD_SPEED and BOW_AIM_SPEED > 0.2);
    try std.testing.expect(BOW_QUICK_DUR > BOW_SHOT_DUR);
}

test "a stagger drops the bow but never the CHOICE of weapon" {
    var h = testHero();
    _ = h.swapArm();
    h.setAim(true);
    h.requestShot(true);
    h.enterStun(.heavy);
    try std.testing.expect(!h.aiming and !h.shooting);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.drawAmt, 1e-6);
    try std.testing.expect(h.bowOut());
    h.enterDeath();
    var guard: u32 = 0;
    while (h.dead and guard < 2000) : (guard += 1) h.updateDeath(1.0 / 60.0);
    try std.testing.expect(h.bowOut());
    try std.testing.expect(!h.aiming and h.drawAmt == 0);
}

test "THE AIM BLEND EASES DOWN THROUGH A STAGGER, exactly as the guard's does" {
    // The camera's boom rides `aimB` (`game.rig.aimB` → `camera.boom`, AIM_DIST 0.7 against a 4.6 zoom), so
    // zeroing it inside `dropAim` cut the eye four metres in ONE frame every time a blow flinched him mid-aim.
    var h = testHero();
    _ = h.swapArm();
    h.setAim(true);
    var t: f32 = 0;
    while (t < 0.5) : (t += 1.0 / 60.0) h.update(1.0 / 60.0, 0, 0, null);
    try std.testing.expectApproxEqAbs(@as(f32, 1), h.aimB, 1e-4);
    h.enterStun(.heavy);
    try std.testing.expect(!h.aiming);
    try std.testing.expect(h.aimB > 0.9);
    h.updateStun(1.0 / 60.0);
    try std.testing.expect(h.aimB < 1.0 and h.aimB > 0);
    t = 0;
    while (t < 0.4) : (t += 1.0 / 60.0) h.updateStun(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.aimB, 1e-4);

    var s = testHero();
    _ = s.swapArm();
    s.setAim(true);
    s.aimB = 1;
    s.sit(true, mathx.zero3, 0);
    try std.testing.expectEqual(@as(f32, 0), s.aimB);
    var r = testHero();
    r.aimB = 1;
    r.respawnNow();
    try std.testing.expectEqual(@as(f32, 0), r.aimB);
}

test "a Cerulean is refused into a full bar rather than pouring a charge away" {
    var h = testHero();
    h.flasks.sel = .cerulean;
    const before = h.flasks.ready();
    try std.testing.expect(!h.startDrink());
    try std.testing.expectEqual(before, h.flasks.ready());
    try std.testing.expect(h.stamRefused > 0);

    h.fp.cur = 10;
    try std.testing.expect(h.startDrink());
    try std.testing.expectEqual(before - 1, h.flasks.ready());

    var g = testHero();
    try std.testing.expect(g.startDrink());
    try std.testing.expectEqual(combat.FLASK_CRIMSON - 1, g.flasks.ready());
}

test "roll knots are ordered and the somersault lands exactly 360 before the rise" {
    comptime {
        std.debug.assert(0 < ROLL_TUCK_IN and ROLL_TUCK_IN < ROLL_UNTUCK_A);
        std.debug.assert(ROLL_SPIN_A < ROLL_SPIN_M0 and ROLL_SPIN_M0 < ROLL_SPIN_M1 and ROLL_SPIN_M1 < ROLL_SPIN_B);
        std.debug.assert(ROLL_SPIN_B < ROLL_UNTUCK_B and ROLL_UNTUCK_A < ROLL_UNTUCK_B);
        std.debug.assert(ROLL_RISE_A < ROLL_RISE_B and ROLL_RISE_B <= 1.0);
        std.debug.assert(ROLL_BRAKE_A < ROLL_BRAKE_B and ROLL_BRAKE_B <= 1.0);
        std.debug.assert(AL_WIND_B <= AL_STRIKE_A and AL_STRIKE_B + 4 * AL_LAG <= AL_RECOV_A);
        std.debug.assert(AH_WIND_B <= AH_STRIKE_A and AH_STRIKE_B + 4 * AH_LAG <= AH_RECOV_A);
        std.debug.assert(AL_HIT_A >= AL_STRIKE_A and AL_HIT_B <= AL_RECOV_A);
        std.debug.assert(AH_HIT_A >= AH_STRIKE_A and AH_HIT_B <= AH_RECOV_A);
        std.debug.assert(AL_CHAIN >= AL_RECOV_A + 0.15 and AL_CHAIN < 1.0);
        std.debug.assert(AH_CHAIN >= AH_RECOV_A and AH_CHAIN < 1.0);
    }
    inline for (.{ ROLL_SPIN_B, 0.9, 1.0 }) |u| {
        const spin = ROLL_SPIN_OVER * mathx.smoothstep(ROLL_SPIN_A, ROLL_SPIN_M1, u) +
            (360.0 - ROLL_SPIN_OVER) * mathx.smoothstep(ROLL_SPIN_M0, ROLL_SPIN_B, u);
        try std.testing.expectApproxEqAbs(@as(f32, 360), spin, 1e-4);
    }
}

test "roll travel: the brake profile integrates to ROLL_DIST" {
    const peak = ROLL_DIST / (ROLL_DUR * 0.5 * (ROLL_BRAKE_A + ROLL_BRAKE_B));
    const steps: f32 = 20000;
    var dist: f64 = 0;
    var i: f32 = 0.5;
    while (i < steps) : (i += 1) {
        const u = i / steps;
        dist += peak * (1.0 - mathx.smoothstep(ROLL_BRAKE_A, ROLL_BRAKE_B, u)) * (ROLL_DUR / steps);
    }
    try std.testing.expectApproxEqAbs(@as(f64, ROLL_DIST), dist, 1e-3);
}


/// Fly one whole jump at `dt` and report what it did. The hero's own advance path, so what is measured is what
/// the game runs — `updateAir` minus the TRAVEL, which is `game.moveHeroAir`'s and needs an Env.
fn flyJump(dt: f32) struct { apex: f32, air: f32, frames: usize } {
    var h = testHero();
    _ = h.startJump(mathx.zero3, 0);
    var apex: f32 = 0;
    var t: f32 = 0;
    var n: usize = 0;
    while (h.airborne()) : (n += 1) {
        h.updateAir(dt, null);
        apex = @max(apex, h.lift);
        t += dt;
        if (n > 100_000) break;
    }
    return .{ .apex = apex, .air = t, .frames = n };
}

test "THE JUMP IS THE SAME JUMP AT EVERY FRAME RATE — and it always comes down" {
    // `env.walkStep`'s lesson, one layer over: a vertical integration measured in FRAMES rather than seconds is
    // a hero who jumps higher on a better machine. Semi-implicit Euler's error is O(g·dt²), which is 9 mm at
    // 30 fps and nothing above it — so the tolerance is a real bound and not a shrug.
    for ([_]f32{ 1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0, 1.0 / 240.0 }) |dt| {
        const j = flyJump(dt);
        try std.testing.expect(j.frames < 100_000);
        try std.testing.expectApproxEqAbs(JUMP_APEX, j.apex, 0.02);
        try std.testing.expectApproxEqAbs(JUMP_AIR, j.air, 0.05);
    }
}

test "A JUMP NEVER WRITES pos.y — the ground under him is `groundActor`'s and stays that" {
    var h = testHero();
    h.pos = v3(3, 1.25, -2);
    _ = h.startJump(mathx.zero3, 0);
    var high: f32 = 0;
    while (h.airborne()) {
        h.updateAir(1.0 / 60.0, null);
        try std.testing.expectEqual(@as(f32, 1.25), h.pos.y);
        try std.testing.expectApproxEqAbs(h.footY(), h.pos.y + h.lift, 1e-5);
        high = @max(high, h.lift);
    }
    try std.testing.expect(high > 0.9);
    try std.testing.expectEqual(@as(f32, 0), h.lift);
}

test "THE GROUND CATCHES HIS FEET WHEREVER IT IS — a jump onto a ledge lands early, off one lands late" {
    const flat = flyJump(1.0 / 60.0).air;
    var up = testHero();
    _ = up.startJump(mathx.zero3, 0);
    var t: f32 = 0;
    while (up.airborne()) : (t += 1.0 / 60.0) {
        if (t > 0.30) up.pos.y = 0.6;
        up.updateAir(1.0 / 60.0, null);
    }
    try std.testing.expect(t < flat);
    try std.testing.expectEqual(@as(f32, 0.6), up.pos.y);
    var down = testHero();
    down.pos = v3(0, 2.0, 0);
    _ = down.startJump(mathx.zero3, 0);
    t = 0;
    while (down.airborne()) : (t += 1.0 / 60.0) {
        if (t > 0.20) down.pos.y = 0;
        down.updateAir(1.0 / 60.0, null);
    }
    try std.testing.expect(t > flat);
}

test "A JUMP IS COMMITTED: no second one out of the air, and nothing else starts out of it either" {
    var h = testHero();
    try std.testing.expect(h.startJump(mathx.zero3, 0));
    try std.testing.expect(h.committed());
    try std.testing.expect(!h.startJump(mathx.zero3, 0));
    h.startRoll(v3(0, 0, 1));
    try std.testing.expect(!h.rolling);
    h.requestAttack(.light);
    try std.testing.expect(!h.attacking and h.queued != null);
    var n: usize = 0;
    while (h.airborne() and n < 1000) : (n += 1) h.updateAir(1.0 / 60.0, null);
    try std.testing.expect(h.attacking);
}

test "A JUMP IS FREE, and the two states that refuse it outright" {
    var h = testHero();
    h.stam.spend(combat.STAM_MAX);
    try std.testing.expect(!h.stam.canAct());
    try std.testing.expect(h.startJump(mathx.zero3, 0));
    try std.testing.expectEqual(@as(f32, 0), h.stam.cur);

    var stunned = testHero();
    stunned.enterStun(.light);
    try std.testing.expect(!stunned.startJump(mathx.zero3, 0));
    var sitting = testHero();
    sitting.resting = true;
    try std.testing.expect(!sitting.startJump(mathx.zero3, 0));
}

test "A BLOW IN THE AIR STILL BRINGS HIM DOWN — the arc runs under every branch, not just its own" {
    var h = testHero();
    _ = h.startJump(mathx.zero3, 0);
    h.updateAir(0.1, null);
    try std.testing.expect(h.lift > 0.2);
    h.enterStun(.heavy);
    try std.testing.expect(h.jumping);
    var n: usize = 0;
    while (h.airborne() and n < 1000) : (n += 1) h.updateStun(1.0 / 60.0);
    try std.testing.expect(n < 1000);
    try std.testing.expectEqual(@as(f32, 0), h.lift);
}

test "HE JUMPS, HE DOES NOT DIVE — the trunk stays near upright the whole way through" {
    var h = testHero();
    _ = h.startJump(v3(0, 0, -1), RUN_SPEED);
    var worst: f32 = 0;
    while (h.airborne()) {
        h.updateAir(1.0 / 60.0, null);
        const tilt = mathx.tiltDeg(foemod.markOn(h.xf[ROOT], mathx.zero3), foemod.markOn(h.xf[HEAD], mathx.zero3));
        worst = @max(worst, tilt);
    }
    try std.testing.expect(worst < 20.0);
}

test "THE LANDING ABSORB OVERSHOOTS ITS REST AND IS SPENT, so the gait gets it back whole" {
    var h = testHero();
    h.landT = 0;
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.landDip(), 1e-4);
    var peak: f32 = 0;
    var over: f32 = 0;
    var t: f32 = 0;
    while (t <= LAND_DUR) : (t += 1.0 / 240.0) {
        h.landT = t;
        peak = @max(peak, h.landDip());
        over = @min(over, h.landDip());
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1), peak, 0.02);
    try std.testing.expect(over < -0.05);
    h.landT = LAND_DUR;
    try std.testing.expectEqual(@as(f32, 0), h.landDip());
    h.landT = mathx.LONG_AGO;
    try std.testing.expectEqual(@as(f32, 0), h.landDip());
}

fn testGuarded() Hero {
    var h = testHero();
    h.facing = 0;
    h.guarding = true;
    return h;
}

fn fromAngle(deg: f32) rl.Vector3 {
    return v3(mathx.sinf(radians(deg)), 0, mathx.cosf(radians(deg)));
}

test "the shield is a DIRECTION: it catches the front and not the flank" {
    var h = testGuarded();
    try std.testing.expect(h.guardCovers(fromAngle(0)));
    try std.testing.expect(h.guardCovers(fromAngle(combat.GUARD_ARC - 1)));
    try std.testing.expect(h.guardCovers(fromAngle(-(combat.GUARD_ARC - 1))));
    try std.testing.expect(!h.guardCovers(fromAngle(combat.GUARD_ARC + 1)));
    try std.testing.expect(!h.guardCovers(fromAngle(180)));
    // A blow with NO direction cannot be guarded — the harness's synthetic reaction hits rely on it.
    try std.testing.expect(!h.guardCovers(mathx.zero3));
    h.guarding = false;
    try std.testing.expect(!h.guardCovers(fromAngle(0)));
}

test "a blocked blow costs STAMINA and chip, and never poise" {
    var h = testGuarded();
    const club = combat.Hit{ .dmg = 36, .poise = 44, .stance = 20 };
    const stam0 = h.stam.cur;
    try std.testing.expectEqual(combat.HitOutcome.blocked, h.takeHit(club, fromAngle(10)));
    try std.testing.expectApproxEqAbs(HP_MAX - combat.guardChip(club, combat.GUARD_NEGATE).dmg, h.vit.hp, 1e-3);
    try std.testing.expectApproxEqAbs(stam0 - combat.guardStamina(club), h.stam.cur, 1e-3);
    try std.testing.expect(!h.staggered() and h.guarding);
    try std.testing.expectApproxEqAbs(POISE_MAX, h.vit.poise, 1e-4);
    try std.testing.expectApproxEqAbs(STANCE_MAX, h.vit.stance, 1e-4);
    const hp0 = h.vit.hp;
    try std.testing.expectEqual(combat.HitOutcome.taken, h.takeHit(club, fromAngle(140)));
    try std.testing.expectApproxEqAbs(hp0 - club.dmg, h.vit.hp, 1e-3);
    try std.testing.expectApproxEqAbs(POISE_MAX - club.poise, h.vit.poise, 1e-3);
    try std.testing.expect(h.vit.stance < STANCE_MAX);
}

test "running the bar out under a blow BREAKS the guard, and it stays down" {
    var h = testGuarded();
    const club = combat.Hit{ .dmg = 36, .poise = 44, .stance = 20 };
    var out = combat.HitOutcome.blocked;
    var n: u32 = 0;
    while (out == .blocked and n < 10) : (n += 1) out = h.takeHit(club, fromAngle(0));
    try std.testing.expectEqual(combat.HitOutcome.guardBroken, out);
    try std.testing.expect(h.stun == .heavy and !h.guarding);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.stam.cur, 1e-4);
    // THE PUNISHMENT IS WHAT COMES NEXT: the pool is empty, so the shield cannot come back up…
    try std.testing.expect(!h.canGuard());
    h.setGuard(true);
    try std.testing.expect(!h.guarding);
    try std.testing.expectEqual(combat.HitOutcome.taken, h.takeHit(club, fromAngle(0)));
}

test "chip CAN kill through a raised shield" {
    var h = testGuarded();
    h.vit.hp = 1.0;
    try std.testing.expectEqual(combat.HitOutcome.taken, h.takeHit(.{ .dmg = 36 }, fromAngle(0)));
    try std.testing.expect(h.dead and !h.guarding);
}

test "A SPELL'S BURST SETTLES ON THE GROUND IT WENT OFF ON, not on the one under his boots" {
    var h = testHero();
    h.pos = v3(0, 0, 0);
    const dug: f32 = -3.0;
    h.rootsBurst(v3(6, dug, 0), true);
    var soil: usize = 0;
    for (h.fx) |q| {
        if (q.life <= 0) continue;
        soil += 1;
        try std.testing.expectEqual(@as(?f32, dug), q.floor);
    }
    try std.testing.expect(soil > 0);
    var t: f32 = 0;
    while (t < 1.2) : (t += 1.0 / 60.0) foemod.tickParticles(&h.fx, 1.0 / 60.0, h.pos.y);
    for (h.fx) |q| {
        if (q.life > 0) try std.testing.expect(q.p.y < 0);
    }
    var w = testHero();
    w.boltBurst(v3(0, 4.0, 0), 0.0, 1);
    for (w.fx) |q| {
        if (q.life > 0) try std.testing.expectEqual(@as(?f32, 0.0), q.floor);
    }
    var own = testHero();
    own.pose();
    own.parrySparks();
    for (own.fx) |q| {
        if (q.life > 0) try std.testing.expect(q.floor == null);
    }
}

test "i-frames beat the shield, and a committed action drops it" {
    var h = testGuarded();
    h.rolling = true;
    h.rollT = 0.1;
    const stam0 = h.stam.cur;
    try std.testing.expectEqual(combat.HitOutcome.ignored, h.takeHit(.{ .dmg = 36 }, fromAngle(0)));
    try std.testing.expectApproxEqAbs(HP_MAX, h.vit.hp, 1e-4);
    try std.testing.expectApproxEqAbs(stam0, h.stam.cur, 1e-4);
    var free = testHero();
    free.setGuard(true);
    try std.testing.expect(free.guarding);
    inline for (.{ "rolling", "attacking", "drinking", "sprinting", "dead" }) |field| {
        var busy = testHero();
        @field(busy, field) = true;
        busy.setGuard(true);
        try std.testing.expect(!busy.guarding);
    }
    var reeling = testHero();
    reeling.stun = .light;
    reeling.setGuard(true);
    try std.testing.expect(!reeling.guarding);
    var spent = testHero();
    spent.stam.spend(combat.STAM_MAX);
    spent.setGuard(true);
    try std.testing.expect(!spent.guarding);
}

test "the guard PAUSES the refill — a held shield is not free" {
    var h = testHero();
    h.stam.cur = 40;
    h.guarding = true;
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) h.tickClocks(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 40), h.stam.cur, 1e-3);
    h.guarding = false;
    t = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) h.tickClocks(1.0 / 60.0);
    try std.testing.expect(h.stam.cur > 60);
}

test "the STANCE lags the block, and the block never lags the stance" {
    var h = testHero();
    h.setGuard(true);
    try std.testing.expect(h.guarding);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.guardB, 1e-6);
    try std.testing.expect(h.guardCovers(fromAngle(0)));
    var t: f32 = 0;
    while (t < 0.10) : (t += 1.0 / 60.0) h.tickClocks(1.0 / 60.0);
    try std.testing.expect(h.guardB > 0.6);
}


test "THE PARRY IS A WINDOW INSIDE A COMMITTED ACTION, and the tail of it is open" {
    var h = testHero();
    const stam0 = h.stam.cur;
    try std.testing.expect(h.canParry());
    try std.testing.expect(h.requestParry());
    try std.testing.expectApproxEqAbs(stam0 - combat.STAM_PARRY, h.stam.cur, 1e-4);
    try std.testing.expect(h.committed() and !h.canGuard());
    try std.testing.expect(!h.parryLive());
    var t: f32 = 0;
    var liveFor: f32 = 0;
    while (h.parrying and t < PARRY_DUR * 3.0) : (t += 1.0 / 60.0) {
        if (h.parryLive()) liveFor += 1.0 / 60.0;
        h.updateParry(1.0 / 60.0, null);
    }
    try std.testing.expect(!h.parrying);
    try std.testing.expect(liveFor > 0.08 and liveFor < PARRY_DUR * 0.5);
    try std.testing.expect(!h.parryLive());
    var late = testHero();
    try std.testing.expect(late.requestParry());
    late.parryT = PARRY_SHUT + 0.01;
    try std.testing.expect(!late.parryLive());
    try std.testing.expectEqual(combat.HitOutcome.taken, late.takeHit(.{ .dmg = 20, .poise = 99 }, fromAngle(0)));
    try std.testing.expect(PARRY_DUR * PARRY_PUNCH_AT > PARRY_OPEN and PARRY_DUR * PARRY_PUNCH_AT < PARRY_SHUT);
}

test "the parry is refused by everything the guard is, and an empty bar SAYS SO" {
    inline for (.{ "rolling", "attacking", "drinking", "sprinting", "dead" }) |field| {
        var busy = testHero();
        @field(busy, field) = true;
        try std.testing.expect(!busy.requestParry());
    }
    var reeling = testHero();
    reeling.stun = .heavy;
    try std.testing.expect(!reeling.requestParry());
    var armed = testHero();
    armed.off = .wand;
    try std.testing.expect(!armed.requestParry());
    var spent = testHero();
    spent.stam.spend(combat.STAM_MAX);
    try std.testing.expect(!spent.requestParry());
    try std.testing.expect(spent.stamRefused > 0);
    var thin = testHero();
    thin.stam.cur = 1.0;
    try std.testing.expect(thin.requestParry());
    try std.testing.expectApproxEqAbs(@as(f32, 0), thin.stam.cur, 1e-4);
}

test "the shove OVERSHOOTS its rest and settles back on it, and the boards never sink through the window" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parryDrive(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), Hero.parryDrive(PARRY_PUNCH_AT), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parryDrive(1.0), 1e-5);
    var crossed = false;
    var u: f32 = PARRY_PUNCH_AT;
    while (u <= 1.0) : (u += 0.005) {
        if (Hero.parryDrive(u) < -0.02) crossed = true;
    }
    try std.testing.expect(crossed);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1), Hero.parrySweep(PARRY_COIL_AT), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), Hero.parrySweep(PARRY_SWEEP_END), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(1.0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(PARRY_PUNCH_AT), 1e-5);
    try std.testing.expect(PARRY_SWEEP_END > PARRY_PUNCH_AT and PARRY_SWEEP_END < 1.0);
    var h = testHero();
    h.setGuard(true);
    var t: f32 = 0;
    while (t < 0.4) : (t += 1.0 / 60.0) h.tickClocks(1.0 / 60.0);
    try std.testing.expect(h.guardB > 0.95);
    try std.testing.expect(h.requestParry());
    while (h.parrying) h.updateParry(1.0 / 60.0, null);
    try std.testing.expect(h.guardB > 0.95);
}

test "A PARRY STARTS COLD — no guard needed, and the boards SETTLE afterwards rather than staying up" {
    var h = testHero();
    try std.testing.expect(!h.guarding);
    try std.testing.expect(h.canParry());
    try std.testing.expect(h.requestParry());
    while (h.parrying) h.updateParry(1.0 / 60.0, null);
    try std.testing.expect(h.guardB > 0.95);
    var t: f32 = 0;
    while (t < 0.4) : (t += 1.0 / 60.0) {
        h.setGuard(false);
        h.tickClocks(1.0 / 60.0);
    }
    try std.testing.expect(h.guardB < 0.05);
}

test "THERE IS ONE LEFT HAND: the wand and the boards can never both be in it, and a bow takes it outright" {
    var h = testHero();
    try std.testing.expect(h.canGuard());
    try std.testing.expect(!h.canCast());
    try std.testing.expect(h.swapOff());
    try std.testing.expectEqual(Off.wand, h.off);
    // The wand is in the hand, so the boards cannot be — `canGuard` ASKING, not a flag a swap remembered to clear.
    try std.testing.expect(!h.canGuard());
    h.setGuard(true);
    try std.testing.expect(!h.guarding);
    try std.testing.expect(h.canCast());
    try std.testing.expect(h.swapArm());
    try std.testing.expect(h.bowOut());
    try std.testing.expectEqual(Off.wand, h.off);
    try std.testing.expect(!h.offInHand() and !h.wandOut());
    try std.testing.expect(!h.canCast() and !h.canGuard());
    try std.testing.expect(h.swapArm());
    try std.testing.expect(h.wandOut() and h.canCast());
}

test "A CAST IS BILLED IN FP AND NOTHING ELSE — and pay-or-nothing, unlike the panic roll" {
    var h = testHero();
    h.off = .wand;
    const stamBefore = h.stam.cur;
    try std.testing.expect(h.requestCast());
    try std.testing.expectApproxEqAbs(combat.FP_MAX - combat.BOLT_FP, h.fp.cur, 1e-4);
    try std.testing.expectApproxEqAbs(stamBefore, h.stam.cur, 1e-4);
    try std.testing.expect(h.casting and h.committed());
    var spent = testHero();
    spent.off = .wand;
    spent.fp.cur = combat.BOLT_FP - 0.01;
    try std.testing.expect(!spent.requestCast());
    try std.testing.expect(!spent.casting);
    try std.testing.expect(spent.fpRefused > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), spent.stamRefused, 1e-6);
    var dry = testHero();
    dry.off = .wand;
    dry.stam.cur = 0;
    try std.testing.expect(!dry.stam.canAct());
    try std.testing.expect(dry.requestCast());
}

test "A CAST IS COMMITTED: nothing fires through one, and a stagger takes the spell you already paid for" {
    var h = testHero();
    h.off = .wand;
    try std.testing.expect(h.requestCast());
    try std.testing.expect(!h.requestCast());
    h.requestAttack(.light);
    try std.testing.expect(h.casting and !h.attacking);
    var guard: u32 = 0;
    while (h.casting and guard < 500) : (guard += 1) h.updateCast(1.0 / 60.0, null);
    try std.testing.expect(!h.casting);
    try std.testing.expect(h.attacking);
    var hit = testHero();
    hit.off = .wand;
    try std.testing.expect(hit.requestCast());
    const paid = hit.fp.cur;
    hit.enterStun(.light);
    try std.testing.expect(!hit.casting and hit.staggered());
    try std.testing.expectApproxEqAbs(paid, hit.fp.cur, 1e-4);
}

test "REPEATED CASTS SWEEP OPPOSITE WAYS, and the bolt leaves ONCE, from over his head" {
    var h = testHero();
    h.off = .wand;
    h.pose();
    var sides: [2]bool = undefined;
    var peak: f32 = -1e9;
    for (&sides, 0..) |*side, n| {
        h.fp.cur = combat.FP_MAX;
        try std.testing.expect(h.requestCast());
        side.* = h.castAlt;
        var throws: u32 = 0;
        var guard: u32 = 0;
        while (h.casting and guard < 500) : (guard += 1) {
            h.updateCast(1.0 / 60.0, null);
            if (h.thrown) {
                throws += 1;
                // THE ARM IS UP: measured off the posed wrist rather than asserted about an angle, so a retune
                // of the sweep is still held to "above his head".
                const tip = h.wandTipWorld();
                try std.testing.expect(tip.y > h.pos.y + h.rest[HEAD].y);
                peak = mathx.maxF(peak, tip.y);
            }
        }
        try std.testing.expectEqual(@as(u32, 1), throws);
        try std.testing.expectEqual(@as(u32, @intCast(n + 1)), h.casts);
    }
    try std.testing.expect(sides[0] != sides[1]);
    try std.testing.expect(peak > 0);
}

test "THE BOLT IS ALL CHAOS, and it is worth more than a light slash before anything resists it" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), combat.BOLT_HIT.dmg, 1e-6);
    try std.testing.expectApproxEqAbs(combat.BOLT_HIT.raw(), combat.BOLT_HIT.elem.at(.chaos), 1e-6);
    try std.testing.expect(combat.BOLT_HIT.raw() > ATK_LIGHT_HIT.dmg);
    try std.testing.expect(combat.BOLT_HIT.raw() < ATK_HEAVY_HIT.dmg);
    try std.testing.expect(combat.BOLT_HIT.poise > ATK_LIGHT_HIT.poise);
    try std.testing.expect(combat.BOLT_HIT.poise < ATK_HEAVY_HIT.poise);
    const casts = combat.FP_MAX / combat.BOLT_FP;
    try std.testing.expect(casts >= 4 and casts <= 8);
}

test "a bonfire gives the FP back, and a respawn does not inherit the refusal flash" {
    var h = testHero();
    h.off = .wand;
    _ = h.requestCast();
    h.fp.cur = 0;
    h.fpRefused = combat.STAM_REFUSE_FLASH;
    h.makeWhole();
    try std.testing.expectApproxEqAbs(combat.FP_MAX, h.fp.cur, 1e-4);
    h.respawn();
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.fpRefused, 1e-6);
    try std.testing.expectEqual(Off.wand, h.off);
}

test "THE FLOOR IS A DRIP: standing in acid takes HP and never the poise refill" {
    var burnt = testHero();
    var clean = testHero();
    for ([_]*Hero{ &burnt, &clean }) |h| _ = h.takeHit(.{ .poise = 20 }, mathx.zero3);
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        _ = burnt.burn(.{ .elem = combat.elems(.{ .chaos = 0.1 }) });
        burnt.vit.tick(1.0 / 60.0);
        clean.vit.tick(1.0 / 60.0);
    }
    try std.testing.expectApproxEqAbs(clean.vit.poise, burnt.vit.poise, 1e-3);
    try std.testing.expectApproxEqAbs(burnt.vit.poiseMax, burnt.vit.poise, 1e-3);
    try std.testing.expect(burnt.vit.hp < clean.vit.hp);
    try std.testing.expect(burnt.vit.sinceHurt < 1.0 / 30.0);
    try std.testing.expect(clean.vit.sinceHurt > 2.0);
}

fn testStrafeAnkle(ph: f32, lat: f32, side: f32, hip: usize, knee: usize, sole: SolePatch) rl.Vector3 {
    const rest = restPositions();
    var wx: [N]rl.Matrix = undefined;
    wx[ROOT] = tr(0, rest[ROOT].y - STRAFE_DIP * @abs(lat), 0);
    legChain(&wx, &rest, ph, 1.0, 0.0, 0.0, lat, side, hip, knee, sole);
    return rl.math.vector3Transform(v3(0, 0, 0), wx[sole.bone]);
}

test "strafe: the legs really CROSS, then UNCROSS (the whole point of the grapevine)" {
    const rest = restPositions();
    const hx = rest[HIPL].x;
    const crossedL = testStrafeAnkle(0.0, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const crossedR = testStrafeAnkle(0.0 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(crossedL.x < crossedR.x - 0.05);
    const openL = testStrafeAnkle(0.5, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const openR = testStrafeAnkle(0.5 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(openL.x > openR.x + 2.0 * hx);
    const mCrossR = testStrafeAnkle(0.5 + 0.5, -1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    const mCrossL = testStrafeAnkle(0.5, -1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    try std.testing.expect(mCrossR.x > mCrossL.x + 0.05);
}

test "strafe: the crossing leg passes IN FRONT and its partner passes BEHIND" {
    const crossMid = testStrafeAnkle(0.52 + 0.48 * 0.5, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const behindMid = testStrafeAnkle(0.52 + 0.48 * 0.5 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(crossMid.z > 0.05);
    try std.testing.expect(behindMid.z < -0.05);
    try std.testing.expect(crossMid.z > behindMid.z + 0.25);
}

test "strafe: planted feet stay ON the ground and the swing foot actually leaves it" {
    // The failure this catches is the one that shipped: 17 deg of "knee lift" over 13 deg of hip flex netted ~1 cm of clearance once the pelvis dip was subtracted, so the swing foot skimmed the grass and the sidestep read as a slide.
    const restFootY = restPositions()[ANKL].y;
    var worstPlanted: f32 = 0;
    var bestSwing: f32 = 0;
    var i: i32 = 0;
    while (i < 200) : (i += 1) {
        const ph = @as(f32, @floatFromInt(i)) / 200.0;
        for ([_]f32{ 1.0, -1.0 }) |lat| {
            const q = ph - @floor(ph);
            const a = testStrafeAnkle(ph, lat, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
            const err = @abs(a.y - restFootY);
            if (q < STRAFE_STANCE) {
                worstPlanted = mathx.maxF(worstPlanted, err);
            } else {
                bestSwing = mathx.maxF(bestSwing, a.y - restFootY);
            }
        }
    }
    try std.testing.expect(worstPlanted < 0.006); // sub-centimetre at H = 1.8 — no float, no clip
    try std.testing.expect(bestSwing > 0.8 * STRAFE_CLEAR);
}

test "strafe: the planted foot does NOT skate — it holds still while the body passes it" {
    const step = 0.01;
    var q: f32 = 0.06;
    while (q < STRAFE_STANCE - 0.06) : (q += step) {
        const a = testStrafeAnkle(q, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
        const b = testStrafeAnkle(q + step, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
        const bodyTravel = step * STRAFE_CYCLE;
        try std.testing.expect(@abs((b.x - a.x) - bodyTravel) < 0.1 * bodyTravel);
    }
}

test "strafe: cadence lands near the forward walk's — no coffeed-up patter" {
    const walkCycle = STRIDE;
    const walkCadence = 1.0 / walkCycle;
    const strafeCadence = STRAFE_SPEED / STRAFE_CYCLE;
    try std.testing.expect(strafeCadence < 1.15 * walkCadence);
    try std.testing.expect(strafeCadence > 0.75 * walkCadence);
}

test "the rig's rest leg length matches the LEG_LEN the strafe geometry is measured off" {
    const rest = restPositions();
    try std.testing.expect(@abs((rest[HIPL].y - rest[ANKL].y) - LEG_LEN) < 1e-4);
    try std.testing.expect(@abs((rest[HIPR].y - rest[ANKR].y) - LEG_LEN) < 1e-4);
}

fn deepestSole(speed: f32, lat: f32) f32 {
    var h = testHero();
    h.moving = 1;
    h.speedS = speed;
    h.fwdB = @sqrt(mathx.maxF(0, 1.0 - lat * lat));
    h.latB = lat;
    var lowest: f32 = std.math.floatMax(f32);
    var i: i32 = 0;
    while (i < 240) : (i += 1) {
        h.phase = @as(f32, @floatFromInt(i)) / 240.0;
        h.pose();
        lowest = mathx.minF(lowest, soleDepth(&h.xf, &BOOT_SOLE));
    }
    return lowest;
}

test "feet do not RAKE through the floor — walking, running, sprinting or sidestepping" {
    try std.testing.expect(deepestSole(WALK_SPEED, 0.0) > SOLE_Y - 0.015);
    try std.testing.expect(deepestSole(WALK_SPEED, 1.0) > SOLE_Y - 0.015);
    try std.testing.expect(deepestSole(WALK_SPEED, -1.0) > SOLE_Y - 0.015);
    try std.testing.expect(deepestSole(WALK_SPEED, 0.7) > SOLE_Y - 0.08);
    try std.testing.expect(deepestSole(WALK_SPEED, -0.7) > SOLE_Y - 0.08);
    try std.testing.expect(deepestSole(RUN_SPEED, 0.0) > SOLE_Y - 0.10);
    try std.testing.expect(deepestSole(SPRINT_SPEED, 0.0) > SOLE_Y - 0.30);
}

test "gait curves wrap continuously across the stride seam" {
    inline for (.{ HIP_FLEX, KNEE_FLEX, ANK_DORSI, RUN_HIP, RUN_KNEE, RUN_ANK }) |tbl| {
        const nearEnd = sampleCurve(tbl, 0.9999);
        const start = sampleCurve(tbl, 0.0);
        try std.testing.expect(@abs(nearEnd - start) < 1.0);
    }
}

test "THE BLADE IS IN WHICHEVER HAND HOLDS IT — bone, capsule and swing, all mirrored off one sign" {
    var h = testHero();
    h.arm = .sword;
    h.off = .shield;
    try std.testing.expect(!h.swordLeft());
    try std.testing.expect(h.holds(.sword));
    h.pose();
    const right = h.xf[SWORD];

    h.arm = .shield;
    h.off = .sword;
    try std.testing.expect(h.swordLeft());
    try std.testing.expect(h.holds(.sword));
    h.pose();
    const left = h.xf[SWORD];

    try std.testing.expect(right.m12 * left.m12 < 0 or @abs(right.m12 - left.m12) > 0.05);
    try std.testing.expectApproxEqAbs(right.m13, left.m13, 0.35);

    h.arm = .sword;
    h.off = .shield;
    h.pose();
    h.updateBlade();
    const rTip = h.bladeB;
    h.arm = .shield;
    h.off = .sword;
    h.pose();
    h.updateBlade();
    try std.testing.expect(mathx.distXZ(rTip, h.bladeB) > 0.1);

    h.arm = .bow;
    h.off = .sword;
    try std.testing.expect(!h.swordLeft() and !h.holds(.sword));
}

test "A DIRK IS SHORTER THAN A SWORD AND A CLUB IS LONGER — the reach is the weapon's, not the rig's" {
    const fist = bladeAt(0);
    var reach: [3]f32 = undefined;
    for (BLADES, 0..) |spec, i| reach[i] = mathx.lenV(mathx.subV(bladeAt(spec.tip), fist));
    // Printed so a retune is a number to read rather than a picture to squint at.
    std.debug.print("\n  blade reach: sword {d:.2} m, dirk {d:.2} m, club {d:.2} m\n", .{ reach[0], reach[1], reach[2] });
    try std.testing.expect(reach[@intFromEnum(Blade.dirk)] < reach[@intFromEnum(Blade.sword)]);
    try std.testing.expect(reach[@intFromEnum(Blade.club)] > reach[@intFromEnum(Blade.sword)]);
    try std.testing.expect(bladeSpec(.dirk).r < BLADE_R and bladeSpec(.club).r > BLADE_R);

    var h = testHero();
    try std.testing.expectEqual(Blade.sword, h.heldBlade());
    try std.testing.expect(h.wear(.hand_sword, .fang_dirk));
    try std.testing.expectEqual(Blade.dirk, h.heldBlade());
    try std.testing.expect(h.wear(.hand_sword, .greatclub));
    try std.testing.expectEqual(Blade.club, h.heldBlade());

    h.pose();
    h.updateBlade();
    const clubTip = mathx.distXZ(h.pos, h.bladeB);
    var s = testHero();
    s.pose();
    s.updateBlade();
    try std.testing.expect(clubTip > mathx.distXZ(s.pos, s.bladeB));
}

test "THE SWING IN FLIGHT KEEPS ITS OWN CAPSULE — a club taken up mid-stroke lends the sword nothing" {
    var h = testHero();
    h.startAttack(.light);
    const r = h.bladeR();
    try std.testing.expectApproxEqAbs(BLADE_R, r, 1e-6);
    try std.testing.expect(h.wear(.hand_sword, .greatclub));
    try std.testing.expectApproxEqAbs(r, h.bladeR(), 1e-6);
    try std.testing.expectEqual(Blade.sword, h.heldBlade());
    h.attacking = false;
    try std.testing.expectEqual(Blade.club, h.heldBlade());
    h.startAttack(.light);
    try std.testing.expect(h.bladeR() > r);
}

test "A HEAVY WEAPON IS SWUNG LIKE ONE — the same stroke, wider and lower on the hips" {
    // THE STARTING KIT IS UNMOVED, and what the page calls Heavy is what the body swings heavy.
    try std.testing.expectEqual(SwingShape{}, swingOf(.sword));
    for ([_]item.Kind{ .fang_dirk, .greatclub }) |k| {
        const shape = swingOf(bladeFor(k));
        const heavy = item.equip(k).arm.heft == .heavy;
        try std.testing.expect((shape.arc > 1) == heavy);
        try std.testing.expect((shape.wind > 1) == heavy);
        try std.testing.expect((shape.dip > 1) == heavy);
    }

    var bare = testHero();
    var club = testHero();
    try std.testing.expect(club.wear(.hand_sword, .greatclub));
    var dirk = testHero();
    try std.testing.expect(dirk.wear(.hand_sword, .fang_dirk));

    for ([_]Attack{ .light, .heavy }) |kind| {
        const heavy = kind == .heavy;
        for ([_]*Hero{ &bare, &club, &dirk }) |h| {
            h.startAttack(kind);
            h.blendT = POSE_XFADE; // past the cross-fade: the stroke's own pose, not a blend with an unset one
            h.atkT = 0.5 * h.atkDur(heavy); // the same POINT in each stroke, which is not the same second
            h.pose();
        }
        // The pelvis is the one bone both strokes drop, and `dip` is the whole of what the weapon moves there.
        try std.testing.expect(club.xf[ROOT].m13 < bare.xf[ROOT].m13);
        try std.testing.expect(dirk.xf[ROOT].m13 > bare.xf[ROOT].m13);
        for ([_]*Hero{ &bare, &club, &dirk }) |h| h.attacking = false;
    }
}

test "THE ROD LEAVES THE HAND IT IS IN — the tip is where every spell comes out of" {
    var h = testHero();
    h.arm = .sword;
    h.off = .wand;
    try std.testing.expect(h.wandLeft() and h.wandOut() and h.canCast());
    h.pose();
    const leftTip = h.wandTipWorld();
    const leftWrist = h.xf[WRL];

    h.arm = .wand;
    h.off = .shield;
    try std.testing.expect(!h.wandLeft() and h.wandOut() and h.canCast());
    h.pose();
    const rightTip = h.wandTipWorld();

    try std.testing.expect(mathx.distXZ(leftTip, rightTip) > 0.15);
    try std.testing.expect(mathx.distXZ(leftTip, rl.math.vector3Transform(mathx.zero3, leftWrist)) < 0.5);
    try std.testing.expect(mathx.distXZ(rightTip, rl.math.vector3Transform(mathx.zero3, h.xf[WRR])) < 0.5);

    h.casting = true;
    h.castT = CAST_DUR * CAST_AT;
    h.pose();
    const castTip = h.wandTipWorld();
    try std.testing.expect(mathx.distXZ(castTip, rl.math.vector3Transform(mathx.zero3, h.xf[WRR])) < 0.6);
    var carry = testHero();
    carry.arm = .wand;
    carry.off = .shield;
    carry.pose();
    try std.testing.expect(mathx.distXZ(wristAt(h.xf[WRR]), wristAt(carry.xf[WRR])) > 0.08);
}

test "THE BOARDS AND THE BELL GO WITH THEIR HAND TOO" {
    var h = testHero();
    h.arm = .sword;
    h.off = .shield;
    try std.testing.expect(h.shieldLeft() and h.canGuard());
    h.guardB = 1.0;
    h.guarding = true;
    h.pose();
    const leftFace = h.shieldFaceWorld();

    h.arm = .shield;
    h.off = .sword;
    try std.testing.expect(!h.shieldLeft() and h.canGuard());
    h.pose();
    const rightFace = h.shieldFaceWorld();
    try std.testing.expect(mathx.distXZ(leftFace.at, rightFace.at) > 0.15);
    for ([_]rl.Vector3{ leftFace.n, rightFace.n }) |n| try std.testing.expect(n.z > 0.2);

    var b = testHero();
    b.arm = .bell;
    b.off = .shield;
    b.ringing = true;
    b.ringT = RING_DUR * RING_AT;
    b.pose();
    const rungRight = b.xf[WRR];
    b.arm = .shield;
    b.off = .bell;
    try std.testing.expect(b.bellLeft() and b.bellOut());
    b.pose();
    var idle = testHero();
    idle.arm = .shield;
    idle.off = .bell;
    idle.pose();
    try std.testing.expect(mathx.distXZ(wristAt(b.xf[WRL]), wristAt(idle.xf[WRL])) > 0.08);
    try std.testing.expect(mathx.distXZ(wristAt(b.xf[WRR]), wristAt(rungRight)) > 0.08);
}

fn wristAt(m: rl.Matrix) rl.Vector3 {
    return rl.math.vector3Transform(mathx.zero3, m);
}

test "A TWO-HANDER CLAIMS BOTH HANDS FROM EITHER SLOT" {
    var h = testHero();
    h.arm = .shield;
    h.off = .bow;
    try std.testing.expect(h.bowOut());
    try std.testing.expect(!h.holds(.shield));
    try std.testing.expect(!h.canGuard() and !h.canParry());
    try std.testing.expect(!h.offInHand());
    try std.testing.expectEqual(Armament.bow, h.armInHand());
    h.arm = .bow;
    h.off = .shield;
    try std.testing.expect(!h.holds(.shield) and !h.canGuard());
    try std.testing.expectEqual(Armament.bow, h.armInHand());
    h.arm = .sword;
    h.off = .shield;
    try std.testing.expect(h.offInHand() and h.holds(.sword) and h.holds(.shield));
    try std.testing.expectEqual(Armament.sword, h.armInHand());
}

test "ONE OF EACH ACROSS THE FOUR CELLS — taking a thing that is already racked swaps the two" {
    var h = testHero();
    try std.testing.expect(h.equip(LEFT, 0, .sword));
    try std.testing.expectEqual(Armament.sword, h.off);
    try std.testing.expectEqual(Armament.shield, h.arm); // what the left hand held went where the sword was
    try std.testing.expect(h.equip(RIGHT, 1, .wand));
    try std.testing.expectEqual(Armament.wand, h.armAlt);
    try std.testing.expectEqual(Armament.bow, h.offAlt);

    var seen = std.EnumSet(Armament).initEmpty();
    for (h.rack()) |c| {
        try std.testing.expect(!seen.contains(c.*));
        seen.insert(c.*);
    }

    var stale = testHero();
    stale.arm = .sword;
    stale.armAlt = .sword;
    stale.off = .sword;
    stale.offAlt = .shield;
    stale.tidyHands();
    try std.testing.expectEqual(Armament.sword, stale.arm);
    try std.testing.expect(stale.armAlt != .sword and stale.off != .sword);
    try std.testing.expect(stale.armAlt != stale.off);
    try std.testing.expectEqual(Armament.shield, stale.offAlt);
}

test "A SKILL REACHES THE BLOW IT GOVERNS AND NOTHING ELSE" {
    var bare = testHero();
    bare.atkHeavy = true;
    try std.testing.expectApproxEqAbs(ATK_HEAVY_HIT.dmg, bare.attackHit().dmg, 1e-4);
    bare.atkHeavy = false;
    try std.testing.expectApproxEqAbs(ATK_LIGHT_HIT.dmg, bare.attackHit().dmg, 1e-4);
    try std.testing.expectApproxEqAbs(combat.BOLT_HIT.raw(), bare.castBlow().?.raw(), 1e-3);

    var club = testHero();
    _ = club.wear(.hand_sword, .greatclub);
    var dirk = testHero();
    _ = dirk.wear(.hand_sword, .fang_dirk);
    club.atkHeavy = true;
    dirk.atkHeavy = true;
    const clubBase = club.attackHit().dmg;
    const dirkBase = dirk.attackHit().dmg;
    club.sheet.set(.strength, 60);
    dirk.sheet.set(.strength, 60);
    try std.testing.expect(club.attackHit().dmg > clubBase);
    try std.testing.expectApproxEqAbs(dirkBase, dirk.attackHit().dmg, 1e-4);
    dirk.sheet.set(.dexterity, 60);
    try std.testing.expect(dirk.attackHit().dmg > dirkBase);

    var strong = testHero();
    _ = strong.wear(.hand_sword, .greatclub);
    strong.atkHeavy = true;
    const weakPoise = strong.attackHit().poise;
    const weakStance = strong.attackHit().stance;
    strong.sheet.set(.strength, 99);
    try std.testing.expect(strong.attackHit().dmg > clubBase);
    try std.testing.expectApproxEqAbs(weakPoise, strong.attackHit().poise, 1e-4);
    try std.testing.expectApproxEqAbs(weakStance, strong.attackHit().stance, 1e-4);

    var bow = testHero();
    bow.arm = .bow;
    const shotBase = bow.shotBlow().dmg;
    bow.sheet.set(.strength, 99);
    try std.testing.expectApproxEqAbs(shotBase, bow.shotBlow().dmg, 1e-4);
    bow.sheet.set(.dexterity, 60);
    try std.testing.expect(bow.shotBlow().dmg > shotBase);

    var rod = testHero();
    const boltBase = rod.castBlow().?;
    rod.sheet.set(.intelligence, 60);
    const boltUp = rod.castBlow().?;
    try std.testing.expect(boltUp.raw() > boltBase.raw());
    try std.testing.expect(boltUp.poise > boltBase.poise);
}

test "WHAT HE PUTS ON CARRIES POINTS OF SKILL, and the sheet is the tree PLUS the gear" {
    var h = testHero();
    const base = h.sheet.at(.strength);
    try std.testing.expect(h.wear(.belt, .banded_warbelt));
    try std.testing.expectEqual(base + 3, h.sheet.at(.strength));
    var plain = testHero();
    plain.atkHeavy = true;
    h.atkHeavy = true;
    try std.testing.expect(h.attackHit().dmg > plain.attackHit().dmg);
    try std.testing.expect(h.wear(.belt, null));
    try std.testing.expectEqual(base, h.sheet.at(.strength));
    try std.testing.expectEqual(base, h.sheet.at(.dexterity));

    try std.testing.expect(h.wear(.belt, .banded_warbelt));
    var b = ptree.Bonus{};
    b.attrs[@intFromEnum(statsmod.Attr.strength)] = 2;
    h.applyPerks(b);
    try std.testing.expectEqual(base + 5, h.sheet.at(.strength));

    var v = testHero();
    v.vit.hp = v.vit.hpMax * 0.5;
    v.fp.cur = v.fp.max * 0.5;
    v.stam.cur = v.stam.max * 0.5;
    try std.testing.expect(v.wear(.neck, .ashen_amulet));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), v.vit.hp / v.vit.hpMax, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), v.fp.cur / v.fp.max, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), v.stam.cur / v.stam.max, 1e-4);
    var swordOnly = testHero();
    try std.testing.expect(v.castBlow().?.raw() > swordOnly.castBlow().?.raw());
    swordOnly.atkHeavy = true;
    v.atkHeavy = true;
    try std.testing.expectApproxEqAbs(swordOnly.attackHit().dmg, v.attackHit().dmg, 1e-4);
}

test "THE WHOLE SUIT ANSWERS PHYSICAL, and stacking it cannot become immunity" {
    var one = testHero();
    _ = one.wear(.chest, .quilted_gambeson);
    var all = testHero();
    _ = all.wear(.chest, .quilted_gambeson);
    _ = all.wear(.helm, .pitted_helm);
    _ = all.wear(.feet, .marchboots);
    try std.testing.expect(all.armourA() > one.armourA());
    const a = all.armourA();
    const smallOff = 1.0 - combat.armourTaken(a, 10) / 10.0;
    const bigOff = 1.0 - combat.armourTaken(a, 60) / 60.0;
    try std.testing.expect(smallOff > bigOff);
    try std.testing.expect(smallOff < 1.0);
    try std.testing.expect(!all.wear(.helm, .marchboots));
    try std.testing.expect(!all.wear(.ring2, .leech_signet));
    try std.testing.expect(all.wear(.ring2, .deft_signet));
}

test "WHAT HE IS WEARING REACHES THE FIGHT — the swing, the clock, the bill, the boards and the bar" {
    var bare = testHero();
    var club = testHero();
    _ = club.wear(.hand_sword, .greatclub);
    var dirk = testHero();
    _ = dirk.wear(.hand_sword, .fang_dirk);

    bare.atkHeavy = true;
    club.atkHeavy = true;
    dirk.atkHeavy = true;
    try std.testing.expect(club.attackHit().dmg > bare.attackHit().dmg);
    try std.testing.expect(club.attackHit().poise > bare.attackHit().poise);
    try std.testing.expect(club.attackHit().stance > bare.attackHit().stance);
    try std.testing.expect(dirk.attackHit().dmg < bare.attackHit().dmg);

    try std.testing.expect(club.atkDur(true) > bare.atkDur(true));
    try std.testing.expect(club.atkDur(false) > bare.atkDur(false));
    try std.testing.expect(dirk.atkDur(false) < bare.atkDur(false));

    club.startAttack(.heavy);
    bare.startAttack(.heavy);
    try std.testing.expect(club.stam.cur < bare.stam.cur);

    var door = testHero();
    _ = door.wear(.hand_shield, .tower_shield);
    try std.testing.expect(door.guardArc() > bare.guardArc());
    door.guarding = true;
    bare.guarding = true;
    door.perk.guard = 0.5;
    const blow = combat.Hit{ .dmg = 40, .poise = 30, .stance = 10 };
    const hpBefore = door.vit.hp;
    _ = door.takeHit(blow, mathx.headingDir(door.facing + std.math.pi));
    try std.testing.expect(door.vit.hp < hpBefore);

    var coat = testHero();
    _ = coat.wear(.chest, .quilted_gambeson);
    const a = coat.armourA();
    try std.testing.expect(a > 0);
    const smallOff = 1.0 - combat.armourTaken(a, 10) / 10.0;
    const bigOff = 1.0 - combat.armourTaken(a, 60) / 60.0;
    try std.testing.expect(smallOff > bigOff);
    const through = blow.throughArmour(a);
    try std.testing.expectApproxEqAbs(blow.poise, through.poise, 1e-6);
    try std.testing.expectApproxEqAbs(blow.stance, through.stance, 1e-6);

    // THE CHARM: a shorter bar, and it gives back on a landed blow. The FRACTION is kept across the resize, so
    // putting it on cannot kill him and taking it off cannot heal him.
    var ring = testHero();
    const fullBar = ring.vit.hpMax;
    ring.vit.hp = ring.vit.hpMax * 0.5;
    _ = ring.wear(.ring, .leech_signet);
    try std.testing.expect(ring.vit.hpMax < fullBar);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ring.vit.hp / ring.vit.hpMax, 1e-4);
    const before = ring.vit.hp;
    try std.testing.expect(ring.drinkLeech() > 0);
    try std.testing.expect(ring.vit.hp > before);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bare.drinkLeech(), 1e-6);

    try std.testing.expect(!bare.wear(.chest, .greatclub));
    try std.testing.expect(!bare.wear(.hand_sword, .quilted_gambeson));
    try std.testing.expect(bare.worn.at(.chest) == null);
}

test "WHAT STARTS IS WHAT LANDS — a variant taken up mid-stroke cannot reach into the one in flight" {
    var h = testHero();
    h.startAttack(.light);
    const dur = h.atkDur(false);
    const dmg = h.attackHit().dmg;
    h.atkT = dur * 0.70;
    try std.testing.expect(!h.hitActive());
    try std.testing.expect(h.wear(.hand_sword, .greatclub));

    // THE SWING IN FLIGHT IS UNMOVED. Read live, `atkT / dur` fell back to 0.52 of a club's longer clock —
    // inside `AL_HIT_A`..`AL_HIT_B`, which re-opens a window that had already closed and re-arms
    // `foe.strike`'s one-hit latch, so one press landed on one body twice for the club's own damage.
    try std.testing.expectApproxEqAbs(dur, h.atkDur(false), 1e-6);
    try std.testing.expectApproxEqAbs(dmg, h.attackHit().dmg, 1e-4);
    try std.testing.expect(!h.hitActive());

    h.attacking = false;
    h.startAttack(.light);
    try std.testing.expect(h.atkDur(false) > dur);
    try std.testing.expect(h.attackHit().dmg > dmg);

    var b = testHero();
    b.arm = .bow;
    b.quiver = .{};
    b.startShot(false);
    const shot = b.shotDur(false);
    const shaft = b.shotBlow().dmg;
    try std.testing.expect(b.wear(.hand_bow, .grave_warbow));
    try std.testing.expectApproxEqAbs(shot, b.shotDur(false), 1e-6);
    try std.testing.expectApproxEqAbs(shaft, b.shotBlow().dmg, 1e-4);
    b.shooting = false;
    try std.testing.expect(b.shotDur(false) > shot);
    try std.testing.expectApproxEqAbs(BOW_SHOT_DUR * item.equip(.grave_warbow).arm.dur, b.shotDur(true), 1e-6);
}
