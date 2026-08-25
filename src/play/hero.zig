const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const anim = @import("../core/anim.zig");
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

/// One stride's samples. A finer table is silently truncated to the first 8 and the seam test still passes.
pub const GAIT_N = 8;

/// Antiphase with the same side's hip flex; unit amplitude for the LEFT arm. NOT `sin` — a quarter-cycle off.
pub fn armSwing(phase: f32) f32 {
    return mathx.cosf(std.math.tau * phase);
}

test "THE ARM OPPOSES ITS OWN LEG — the swing and the hip flex are antiphase, measured off the curve" {
    for ([_]f32{ 0.0, 0.5, 1.0 }) |ph| {
        const hipRx = -sampleCurve(HIP_FLEX, ph);
        const armRx = armSwing(ph);
        std.debug.print("\n  phase {d:.2}: left hip rx {d: >6.1}, left arm rx {d: >5.2}", .{ ph, hipRx, armRx });
        try std.testing.expect(hipRx * armRx < 0);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), @abs(armSwing(0.0)), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), @abs(armSwing(0.5)), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), armSwing(0.25), 1e-5);
    std.debug.print("\n", .{});
}

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
/// …capped: he can stand on ground far steeper than he can walk up.
const SLOPE_LEAN_MAX: f32 = 16.0;
/// Degrees a second.
pub const SLOPE_LEAN_RATE: f32 = 120.0;

/// Degrees.
pub fn slopeLean(rise: f32) f32 {
    const deg = mathx.degrees(std.math.atan(rise)) * SLOPE_LEAN;
    return mathx.clampF(deg, -SLOPE_LEAN_MAX, SLOPE_LEAN_MAX);
}

pub const JUMP_APEX: f32 = 1.0;
pub const JUMP_AIR: f32 = 0.72;
const JUMP_G: f32 = 8.0 * JUMP_APEX / (JUMP_AIR * JUMP_AIR);
const JUMP_V0: f32 = JUMP_G * JUMP_AIR * 0.5;
const AIR_TURN_RATE: f32 = 2.6;
/// `v = sqrt(2 g h)` off `combat.Hit.launch`: at the slams' 0.85 m that is 5.12 m/s and 0.66 s of air, under his
/// own jump's 1.0 m / 0.72 s. The distance is authored, not derived — `LAUNCH_BACK` over that flight's airtime.
pub const LAUNCH_BACK: f32 = 1.6;
fn launchV0(apex: f32) f32 {
    return @sqrt(2.0 * JUMP_G * mathx.maxF(apex, 0.01));
}
fn launchSpeed(apex: f32) f32 {
    return LAUNCH_BACK * JUMP_G / (2.0 * launchV0(apex));
}
/// `2 v / g` — for a harness aiming at a fraction of the flight (`shots.zig`) rather than at a frame count.
pub fn launchAirFor(apex: f32) f32 {
    return 2.0 * launchV0(apex) / JUMP_G;
}
/// Degrees the trunk arches BACK at the apex; over the heavy stagger's own `STAG_LEAN`.
const LAUNCH_ARCH: f32 = 54.0;
const LAUNCH_HEAD: f32 = 40.0;
const LAUNCH_ARM: f32 = 62.0;
const LAUNCH_HIP: f32 = 34.0;
const LAUNCH_KNEE: f32 = 46.0;
/// The pose reads `vertVel` against THIS, not against its own throw's v0, so a bigger slam reads as a bigger throw.
pub const LAUNCH_MAX_APEX: f32 = 1.2;
comptime {
    // Pinned here so a foe file can author a launch (`combat.SLAM_LAUNCH`) without importing the hero.
    std.debug.assert(combat.SLAM_LAUNCH < JUMP_APEX);
    std.debug.assert(combat.SLAM_LAUNCH <= LAUNCH_MAX_APEX);
}
const LAND_DUR: f32 = 0.34;
const LAND_SINK = 0.052 * H;
const LAND_SINK_AT: f32 = 0.22;
const LAND_REBOUND: f32 = 0.62;
pub const LAND_SINK_DEEPEST: f32 = LAND_DUR * LAND_SINK_AT;
const LAND_STOOP: f32 = 7.0;
/// Degrees. Three terms off the vertical velocity alone.
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

pub const ROLL_DUR = 0.70;
pub const ROLL_IFRAME_END = 0.46;
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
/// `yaw` is horizontal abduction; 0 makes `ry` the identity, so the rod goes through the same expression.
const Carry = struct {
    flex: f32,
    abd: f32,
    elbow: f32,
    wrist: f32,
    swing: f32,
    elbowSwing: f32,
    yaw: f32 = 0,
};

const WAND_CARRY = Carry{ .flex = 14.0, .abd = 6.0, .elbow = 74.0, .wrist = -12.0, .swing = 0.55, .elbowSwing = 0.40 };
const TORCH_CARRY = Carry{ .flex = 10.0, .abd = 10.0, .elbow = 85.0, .wrist = -4.0, .swing = 0.34, .elbowSwing = 0.26, .yaw = 28.0 };
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
const BELL_MOUTH_R = 0.026 * H; // ~9.4 cm across the mouth
const BELL_WALL = 0.0035 * H;
const BELL_BRONZE = rgba(78, 58, 30, 255);
const BELL_BRONZE_LT = rgba(104, 80, 42, 255);
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

/// Square across the fist (the rod sits at 55 along it), so the brand stands plumb off a level forearm.
const TORCH_PITCH = 90.0;
const TORCH_ULNAR = 5.0;
const TORCH_PALM = 0.016 * H;
const TORCH_CA = @cos(radians(TORCH_PITCH));
const TORCH_SA = @sin(radians(TORCH_PITCH));
const TORCH_UC = @cos(radians(TORCH_ULNAR));
const TORCH_US = @sin(radians(TORCH_ULNAR));
const TORCH_AX = v3(TORCH_SA * TORCH_US, -TORCH_CA, TORCH_SA * TORCH_UC);
fn torchAt(t: f32) rl.Vector3 {
    return v3(
        TORCH_AX.x * t * H,
        FIST_Y + TORCH_AX.y * t * H,
        FIST_Z + TORCH_PALM + TORCH_AX.z * t * H,
    );
}
const TORCH_TIP_T = 0.26;
const TORCH_BUTT_T = 0.07;
const TORCH_R = 0.017 * H;
const TORCH_HEAD_R = 0.034 * H;
const TORCH_HAFT = rgba(46, 33, 24, 255);
const TORCH_HAFT_LT = rgba(66, 49, 36, 255);
const TORCH_PITCHWAD = rgba(20, 16, 14, 255);

const CHAOS_MOTE = elemfx.sig(.chaos).edge;
const CHAOS_HOT = elemfx.sig(.chaos).core;
const CHAOS_COOL = elemfx.sig(.chaos).cool;
const CHAOS_STRETCH = elemfx.sig(.chaos).stretch;
const CAST_MOTE_RATE = 52.0;
const CAST_MOTE_R = 0.17;
const CAST_MOTE_RATE_HI = 300.0;
const CAST_MOTE_R_HI = 0.055;
const CAST_MOTE_CAP = 8;
const CAST_MOTE_LIFE_LO = 0.030;
const CAST_MOTE_LIFE_HI = 0.055;
/// `drawParticles` fades radius WITH alpha: at 0.04 s a mote is legible on one frame of three, at 0.015 nine showed as three.
const CAST_MOTE_R0 = 0.023;
const CAST_MOTE_R1 = 0.011;
const CAST_SPARKS = 26;
const CAST_COLLAR = 12;
const CAST_COLLAR_SP = 4.4;
/// SMALL: it is a solid sphere, not additive, so at 0.30 it rendered as a translucent balloon hiding the stone.
const CAST_FLASH_R = 0.095;
const CAST_FLASH_LIFE = 0.085;
const BOLT_BURST = 22;


const LEVIN_STEPS = 9;
const LEVIN_SPARKS = 2;
const LEVIN_BURST = 26;
const LEVIN_JITTER = 0.11 * H;
/// MEASURED: a lightning mote is 2 cm and lives 0.04 s — the short life is bought back with radius, never more motes.
const LEVIN_SPARK_SCALE = 2.2;
/// 2.4 not 3.2 off the same render: at 7 cm a mote is a soft ball and the shower photographed as SMOKE.
const LEVIN_BURST_SCALE = 2.4;

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
/// Under the levin's 2.2 — fire lives longer in `elemfx`, and at the same throw the shaft photographed as a hedge.
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
/// ~1.05 m — HIP height on the 1.8 m rig, and bracketed from both sides.
const ROOT_LEN = 0.58 * H;
const ROOT_R0 = 0.052 * H;
const ROOT_R1 = 0.019 * H;
/// MEASURED, NOT GUESSED (AGENTS.md): at `34,25,18` on `.bark` these sampled 115,94,68 against grass at
/// 110,97,67. SOLVED from there: screen = (albedo/255 × 1.72)^(1/2.2) × 255, so half the ground's 110 is
/// screen 55, and 55 back through the chain is albedo 5. `.wood` is the material that does not lift it again.
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

// The mechanic's own numbers (reach, arc, span, what it bills) are `combat.RIME_*`; these are only the picture.

const BREATH_RATE = elemfx.POUR_RATE;
const BREATH_CAP = elemfx.POUR_CAP;
// A jet's grain is `elemfx.POUR_GRAIN`, not his: held here and passed through `scale` the bench drew it 60% coarser.

const BREATH_NOZZLE_FWD = 0.030 * H;
/// Through the WAIST, spine and chest, never the root. Degrees, total across the two.
const BREATH_LEAN = -13.0;
const BREATH_HEAD = 6.0;
const BREATH_REACH = 12.0;
/// `breathDir` is level and the bite is XZ, so a level shoulder is 40, not 90 (the throw's `CAST_SH_FWD` is 118).
const BREATH_SH_LEVEL = 40.0;
const BREATH_SHIVER = 1.5;
const BREATH_SHIVER_HZ = 12.0;

/// **SIZED FOR THE DISC, NOT THE POINT.** A burst affords two dozen because they leave one place; a 3.4 m ring
/// at that count is a scatter of specks.
const DUST_MOTES = 96;

const FX_N = 1536;

comptime {
    const gather = CAST_MOTE_RATE_HI * CAST_MOTE_LIFE_HI;
    const release = CAST_SPARKS + CAST_COLLAR + 1;
    const erupt = ROOT_DUST + ROOT_MOTES;
    const caught = PARRY_SPARKS + 1 + PARRY_GLINT + 1;
    const ticks = @ceil(combat.RIME_DUR * BREATH_RATE);
    const breath = @as(f32, @floatFromInt(elemfx.pourCount(1))) * ticks;
    const struck = LEVIN_STEPS * LEVIN_SPARKS + LEVIN_BURST + SIPHON_MOTES;
    // A fire burst emits its ASH beside every third mote (`elemfx.burstCount`), so 22 steps of 4 is 110, not 88.
    const lance = LANCE_STEPS * elemfx.burstCount(.fire, LANCE_SPARKS);
    const blocked = BLOCK_GRIT_MAX + BLOCK_SPARK_MAX + 1;
    const wake = FOG_WAKE_RATE * FOG_WAKE_LIFE_HI;
    const worst = gather + breath + wake +
        @as(f32, release + erupt + caught + struck + 2 * BOLT_BURST + lance + blocked + DUST_MOTES);
    if (@as(f32, FX_N) < worst) @compileError(std.fmt.comptimePrint(
        "hero: FX_N = {d} but a cast can have {d} particles in the air — raise it",
        .{ FX_N, worst },
    ));
}

const WAND_LIT = mathx.colVec(CHAOS_MOTE);
/// Radius matters more than brightness (the chapel's law): at a torch's 6 m it washed him violet head to foot.
const WAND_LIT_CARRY = 0.20;
const WAND_LIT_CARRY_R = 2.6;
const WAND_LIT_CHARGED = 1.00;
const WAND_LIT_CHARGED_R = 7.0;
const WAND_LIT_FLARE = 2.30;
const WAND_LIT_FLARE_R = 12.0;

/// The world torch's row (`props` `.torch`: 0.64/0.34/0.13 at 6 m) opened out — a fifth again the colour, a third more reach.
const TORCH_LIT = v3(0.78, 0.42, 0.16);
const TORCH_LIT_R = 8.0;
const TORCH_FLICKER = 0.16;
const TORCH_FLAME_T = TORCH_TIP_T + 0.030;
const TORCH_FLAME_S = 0.45;

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

/// **NOTHING MAY EVER SET `vit.armour`.** `takeHit`/`blockHit` pre-apply it off `armourA()`; both doors at once
/// is `combat.armourTaken` twice, silently.
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

/// Summed over every socket; `combat.armourTaken` is a diminishing curve, so a sum cannot reach immunity.
pub fn armourOf(worn: Worn) f32 {
    return plateOf(worn).a;
}

/// **TEN NUMBERS, NOT ONE `Plate` FIELD.** A piece names ONE meter (`item.AilRate`), and a single `Plate` has
/// nowhere to put a sporecrown and a waker's nail at once.
pub const Suit = struct { plate: item.Plate, charm: item.Charm, rates: [combat.NAIL]f32 = [_]f32{1} ** combat.NAIL };

/// **ONE WALK OF THE SOCKETS FOR BOTH TABLES.** `settleBody` asks every frame, and a walk apiece is two
/// `item.equip` lookups per socket for one answer.
/// **PHYSICAL AND THE FOUR COLUMNS ADD; THE RATES MULTIPLY** — halving twice leaves a quarter, where
/// subtracting 0.5 twice leaves nothing and makes the second piece free immunity.
pub fn suitOf(worn: Worn) Suit {
    var pl = item.Plate{ .slot = .chest };
    var ch = item.Charm{ .slot = .ring };
    var rates = [_]f32{1} ** combat.NAIL;
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        if (worn.at(@enumFromInt(f.value))) |k| {
            switch (item.equip(k)) {
                .plate => |p| {
                    pl.a += p.a;
                    pl.res = pl.res.plus(p.res);
                    if (p.rate) |r| rates[@intFromEnum(combat.ailOfName(r.ail))] *= r.k;
                    pl.move *= p.move;
                },
                .charm => |c| {
                    ch.leech += c.leech;
                    ch.hpFrac += c.hpFrac;
                    ch.fpFrac += c.fpFrac;
                    ch.spiritFp *= c.spiritFp;
                },
                else => {},
            }
        }
    }
    return .{ .plate = pl, .charm = ch, .rates = rates };
}

pub fn plateOf(worn: Worn) item.Plate {
    return suitOf(worn).plate;
}

/// **HOW FAST HE WALKS, ALL OF IT IN ONE PLACE** — the tree's node and what is on his feet. `game.moveHero` is
/// the only caller, so a shoe that hurries him cannot be applied on one movement path and not the others.
pub fn moveRateOf(worn: Worn, perk: ptree.Bonus) f32 {
    return perk.moveSpeed * plateOf(worn).move;
}

pub fn charmOf(worn: Worn) item.Charm {
    return suitOf(worn).charm;
}

/// **THE MOST A BARGAIN MAY EAT OF A POOL.** Both bars answer to it, so a charm stack can shorten a bar and
/// never delete it. Written out at each of the three sites, one of them retuned alone is a pool with no floor.
pub const POOL_EATEN_CAP: f32 = 0.9;

/// The focus pool off an ALREADY-WALKED suit, so `settleBody` can ask for the pool without walking again.
pub fn fpMaxFrom(sheet: statsmod.Sheet, charm: item.Charm, perk: ptree.Bonus) f32 {
    return sheet.fp() * (1.0 - mathx.clampF(charm.fpFrac, 0, POOL_EATEN_CAP)) * perk.fpMax;
}

pub fn hpMaxOf(sheet: statsmod.Sheet, worn: Worn, perk: ptree.Bonus) f32 {
    const eaten = charmOf(worn).hpFrac + perk.hpFrac;
    return sheet.hp() * (1.0 - mathx.clampF(eaten, 0, POOL_EATEN_CAP));
}

/// `fpMaxFrom` with the socket walk in front of it — the formula lives THERE and nowhere else.
pub fn fpMaxOf(sheet: statsmod.Sheet, worn: Worn, perk: ptree.Bonus) f32 {
    return fpMaxFrom(sheet, charmOf(worn), perk);
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

/// The ONE place `hero.Armament` and `item.Wear` are matched up. Null for the two with no variants.
pub fn wearFor(a: Armament) ?item.Wear {
    return switch (a) {
        .sword => .hand_sword,
        .dagger => .hand_dagger,
        .club => .hand_club,
        .bow => .hand_bow,
        .shield => .hand_shield,
        .bell, .wand, .torch => null,
    };
}

pub fn heldGear(a: Armament, worn: Worn) ?item.Kind {
    const w = wearFor(a) orelse return null;
    return worn.at(w);
}

/// **THE SKILL RIDES THE DAMAGE DIAL AND NOTHING ELSE**: strength makes a club hit HARDER, not heavier —
/// poise and stance belong to the WEAPON's mass. Elemental rides damage, stance rides poise.
pub fn weigh(h: combat.Hit, row: item.Arm, sheet: statsmod.Sheet) combat.Hit {
    const skill = scaleOf(sheet, row.scales);
    return .{
        .dmg = h.dmg * row.dmg * skill,
        .poise = h.poise * row.poise,
        .stance = h.stance * row.poise,
        .elem = h.elem.scaled(row.dmg * skill),
        .fp = h.fp,
        .dose = combat.Doses.one(.poison, row.venom),
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
/// PAID FOR AT BOTH JOINTS: `shieldFit` inverts `GUARD_ARM_FOLD` (shoulder flex + elbow), so opening at the elbow alone rotates the shield off its own arm (measured).
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
/// SEPARATED ON HUE, not value: the boards come back off this sun around 140, and a pale cream spark at 3 cm read as a soft bubble on them (measured, at 30).
const PARRY_SPARK = rgba(255, 206, 108, 240);
const PARRY_SPARK_HOT = rgba(255, 250, 232, 250);
const PARRY_SPARK_COOL = rgba(224, 118, 40, 210);
const SPARK_STRETCH = 0.055;
const SPARK_BOUNCE = 0.45;
const PARRY_SPARKS = 34;
/// Forward is DOWN THE LENS: at 0.42 of the forward speed most were still inside the disc's outline four frames later (measured).
const PARRY_SPARK_FAN = 9.0;
const PARRY_SPARK_OUT_LO = 1.0;
const PARRY_SPARK_OUT_HI = 3.2;
const PARRY_SPARK_R0_LO = 0.009;
const PARRY_SPARK_R0_HI = 0.019;
const PARRY_SPARK_GRAV = 9.0;
const SPARK_PROUD: f32 = 0.02;
/// A solid sphere, not additive: at 0.085 it read as a puff of smoke sat on the boards.
const PARRY_FLASH_R = 0.05;
const PARRY_FLASH_LIFE = 0.06;
const PARRY_GLINT = 18;
/// TIGHTER than the catch's fan: thrown as far and lived as long, a dozen motes read as litter a metre off the boards (measured).
const PARRY_GLINT_FAN = 4.5;
/// LAID ALONG THE ARC, not thrown from a point — every burst here is coincident on its emission frame.
const PARRY_GLINT_SPAN = 0.22;
const PARRY_GLINT_TRAIL = 0.55;
/// …and the bloom is UNDER the catch's 0.05, not over it: at 0.075 the first frame was a solid white ball.
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

/// Gravity is NEGATIVE — the one emitter in his kit that rises. Colours are the gate's own (`propfx.FOG_WAKE_*`).
const FOG_WAKE_OUT_LO = 0.35;
const FOG_WAKE_OUT_HI = 1.05;
const FOG_WAKE_RISE = 0.28;
const FOG_WAKE_GRAV = -0.55;
const FOG_WAKE_LIFE_LO = 0.55;
const FOG_WAKE_LIFE_HI = 1.25;
const FOG_WAKE_R0_LO = 0.055;
const FOG_WAKE_R0_HI = 0.115;
const FOG_WAKE_R1 = 0.20;
const FOG_WAKE_THIN = mathx.rgba(206, 214, 226, 0);
const FOG_WAKE_DRAG: f32 = 2.8;
/// `FX_N` is solved over this rate.
pub const FOG_WAKE_RATE: f32 = 26.0;
pub const FOG_WAKE_CAP: u32 = 8;
/// Under the parry's shower (`PARRY_SPARKS`, 34): the catch is the earned one.
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
/// In the WRIST's frame, since the hand grips BEHIND the boss.
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
/// `t` is the fraction of STATURE along the grip axis (`bladeAt`), so a reach is metres once `H` is fixed;
/// `r` is the capsule the fight is fought with, not anything you can see.
pub const Blade = enum { sword, dagger, club };

const BladeSpec = struct { base: f32, tip: f32, r: f32 };

const BLADES = [_]BladeSpec{
    .{ .base = -0.06, .tip = 0.64, .r = BLADE_R }, // sword: 1.15 m past the fist
    .{ .base = -0.05, .tip = 0.37, .r = 0.25 }, // dagger: 0.67 m
    .{ .base = -0.06, .tip = 0.80, .r = 0.42 }, // club: 1.44 m
};

comptime {
    if (BLADES.len != @typeInfo(Blade).@"enum".fields.len) @compileError("hero: a Blade has no capsule row");
}

fn bladeSpec(b: Blade) BladeSpec {
    return BLADES[@intFromEnum(b)];
}

pub fn bladeOf(a: Armament) ?Blade {
    return switch (a) {
        .sword => .sword,
        .dagger => .dagger,
        .club => .club,
        .bow, .bell, .shield, .wand, .torch => null,
    };
}

/// Six moves, two per class, no strings. `slash`/`chop` the straight sword's diagonal cut and overhead;
/// `flick`/`thrust` the dagger (DS1's rapid jabs, ER's Main-gauche / Miséricorde / Scorpion's Stinger thrust);
/// `sweep`/`smash` the club (DS1's Large Club dashing swing, and the great hammer's overhead smash).
pub const Stroke = enum { slash, chop, flick, thrust, sweep, smash };

/// Fractions of the stroke's own clock. `dur` is seconds at dial 1 and `item.Arm.dur` multiplies it (`atkDur`),
/// so every phase scales together. `hitA`..`hitB` is the capsule's live window, `travelA`..`travelB` when the
/// body covers `lunge` metres, `recovA` where the pose starts home (and re-tracking resumes), `chain` where a
/// queued press takes over.
pub const Timing = struct {
    dur: f32,
    hitA: f32,
    hitB: f32,
    travelA: f32,
    travelB: f32,
    recovA: f32,
    chain: f32,
    lunge: f32,
};

pub const Move = struct { stroke: Stroke, t: Timing };

/// THE SWORD'S TWO ROWS ARE THE SHIPPED NUMBERS TRANSCRIBED (`AL_*`/`AH_*`) and must stay that way.
const SWORD_LIGHT = Timing{ .dur = ATK_LIGHT_DUR, .hitA = AL_HIT_A, .hitB = AL_HIT_B, .travelA = AL_STRIKE_A, .travelB = AL_STRIKE_B, .recovA = AL_RECOV_A, .chain = AL_CHAIN, .lunge = AL_LUNGE };
const SWORD_HEAVY = Timing{ .dur = ATK_HEAVY_DUR, .hitA = AH_HIT_A, .hitB = AH_HIT_B, .travelA = AH_STRIKE_A, .travelB = AH_STRIKE_B, .recovA = AH_RECOV_A, .chain = AH_CHAIN, .lunge = AH_LUNGE };

/// Indexed `[Blade][heavy]`. **THE SECONDS IN THE COMMENTS BELOW ARE AFTER THE ROW'S DIAL** (dagger 0.78, club 1.34).
const MOVES = [3][2]Move{
    .{
        .{ .stroke = .slash, .t = SWORD_LIGHT },
        .{ .stroke = .chop, .t = SWORD_HEAVY },
    },
    .{
        // 0.413 s, live 0.083 — the fastest thing he owns, and it buys that with 0.67 m of reach.
        .{ .stroke = .flick, .t = .{ .dur = 0.53, .hitA = 0.30, .hitB = 0.50, .travelA = 0.26, .travelB = 0.46, .recovA = 0.60, .chain = 0.74, .lunge = 0.35 } },
        // 0.671 s. THE STEP IS THE MOVE: 1.35 m of it, which is how the shortest weapon reaches anything at all.
        .{ .stroke = .thrust, .t = .{ .dur = 0.86, .hitA = 0.40, .hitB = 0.60, .travelA = 0.34, .travelB = 0.58, .recovA = 0.66, .chain = 0.82, .lunge = 1.35 } },
    },
    .{
        // 0.884 s, live 0.283 — the longest active window in the kit by 2x.
        .{ .stroke = .sweep, .t = .{ .dur = 0.66, .hitA = 0.34, .hitB = 0.66, .travelA = 0.30, .travelB = 0.62, .recovA = 0.70, .chain = 0.86, .lunge = 0.60 } },
        // 1.447 s, and the blow does not arrive until 0.695 of it. The HANG is in the track (`.hold`).
        .{ .stroke = .smash, .t = .{ .dur = 1.08, .hitA = 0.48, .hitB = 0.66, .travelA = 0.44, .travelB = 0.64, .recovA = 0.72, .chain = 0.90, .lunge = 0.85 } },
    },
};

// Each mistake fails SILENTLY: `travelB == travelA` divides by zero in `updateAttack`, `hitA >= hitB` is a
// capsule that never goes live, and a fraction past 1 is a phase the clock never reaches.
comptime {
    if (MOVES.len != @typeInfo(Blade).@"enum".fields.len) @compileError("hero: a Blade has no moveset row");
    for (MOVES) |pair| {
        for (pair) |m| {
            const t = m.t;
            if (!(t.dur > 0)) @compileError("hero: a move with no duration divides by zero in `atkDur`");
            if (!(t.hitA < t.hitB)) @compileError("hero: a move whose hit window never opens");
            if (!(t.travelA < t.travelB)) @compileError("hero: a move whose travel span divides by zero");
            if (!(t.recovA > t.hitA and t.recovA < 1)) @compileError("hero: recovery must start after the blow and inside the move");
            if (!(t.chain > t.recovA and t.chain <= 1)) @compileError("hero: the chain must open after recovery starts and inside the move");
            if (!(t.hitB <= 1 and t.travelB <= 1)) @compileError("hero: a phase past the end of the move");
            if (!(t.lunge >= 0)) @compileError("hero: a stroke does not travel backwards");
        }
    }
}

pub fn moveOf(b: Blade, heavy: bool) Move {
    return MOVES[@intFromEnum(b)][@intFromBool(heavy)];
}

/// Degrees except `dip`, which is metres the pelvis drops. Signs are the AUTHORED (right-hand) side's;
/// `armSide`'s mirror times the alternation flip (`lat`) carries the LATERAL channels over, sagittal alone.
/// `sh` is how far the weapon shoulder is RAISED, `sweep` its yaw across the body (negative = cocked back),
/// `grip` the pitch taken out of the grip axis (`GRIP_PITCH` levels the blade, 0 leaves it along the forearm).
const MCH_N = 14;

const MK = struct {
    dip: f32 = 0,
    yaw: f32 = 0,
    chest: f32 = 0,
    pitch: f32 = 0,
    tilt: f32 = 0,
    sh: f32 = 0,
    sweep: f32 = 0,
    abd: f32 = 0,
    elbow: f32 = IDLE_ELBOW,
    wrist: f32 = 0,
    roll: f32 = 0,
    free: f32 = 0,
    brace: f32 = 0,
    grip: f32 = 0,

    /// Two literal orders, here and in `mkAt`: a field inserted in the middle silently renames every channel
    /// after it, which is a whole stroke posed through the wrong joints with nothing to see at the call site.
    pub fn chan(self: MK) [MCH_N]f32 {
        var c: [MCH_N]f32 = undefined;
        inline for (@typeInfo(MK).@"struct".fields, 0..) |f, i| c[i] = @field(self, f.name);
        return c;
    }
};

comptime {
    if (@typeInfo(MK).@"struct".fields.len != MCH_N) @compileError("hero: MCH_N disagrees with MK's field count");
}

const MKey = anim.Pose(MK).PoseKey;
const sampleMK = anim.Pose(MK).sample;

fn mkAt(keys: []const MKey, u: f32) MK {
    const c = sampleMK(keys, u);
    var out: MK = .{};
    inline for (@typeInfo(MK).@"struct".fields, 0..) |f, i| @field(out, f.name) = c[i];
    return out;
}

// **NO SPRING BANK HERE ON PURPOSE**: every hero pose is a pure function of its own clock (`pose` takes no
// `dt`, which keeps `--shot` reproducible), so the load, HANG, snap, carry-past and settle are authored as
// KEYS. Interrupt continuity is `applyXfade`'s job here, not a spring's.
//
// **AN ARRIVAL IS `.accel` INTO THE BLOW AND `.decel` OUT OF IT, NEVER `.snap`.** `snap` is front-loaded
// (1-(1-f)^5), so on a strike key it puts the stroke BEHIND the capsule: measured, the dagger's tip crossed
// 13 of its 84 degrees inside its own live window and the club was already on the ground when it opened.

const FLICK_REST = MK{ .sh = 22, .elbow = 44, .sweep = -10, .grip = GRIP_PITCH };
const FLICK_COCK = MK{ .sh = 52, .elbow = 92, .sweep = -36, .roll = 28, .wrist = 16, .yaw = -8, .chest = -13, .dip = 0.012 * H, .pitch = -4, .free = -14, .brace = 4, .abd = 6, .grip = GRIP_PITCH };

/// DS1's dagger "jabbed in rapid succession". Cocked IN to the far ribs rather than back — elbow and wrist
/// do the work. The whole gather is 0.075 s at the dial the fight runs it at.
const FLICK_KEYS = [_]MKey{
    .{ .t = 0.00, .p = FLICK_REST },
    .{ .t = 0.16, .p = FLICK_COCK, .ease = .decel },
    .{ .t = 0.48, .p = .{ .sh = 56, .elbow = 16, .sweep = 48, .roll = -34, .wrist = -22, .yaw = 12, .chest = 27, .dip = 0.012 * H, .pitch = 5, .free = 20, .brace = 8, .grip = GRIP_PITCH }, .ease = .accel },
    .{ .t = 0.58, .p = .{ .sh = 53, .elbow = 11, .sweep = 60, .roll = -38, .wrist = -27, .yaw = 15, .chest = 33, .dip = 0.010 * H, .pitch = 4, .free = 24, .brace = 6, .grip = GRIP_PITCH }, .ease = .decel },
    .{ .t = 0.72, .p = .{ .sh = 36, .elbow = 36, .sweep = 38, .roll = -14, .wrist = -8, .yaw = 6, .chest = 17, .dip = 0.006 * H, .pitch = 3, .free = 11, .brace = 3, .grip = GRIP_PITCH } },
    .{ .t = 1.00, .p = FLICK_REST },
};

const THRUST_REST = MK{ .sh = 12, .elbow = 42, .grip = GRIP_PITCH };
/// **`sh` IS MEASURED FROM ARM-HANGING-DOWN, SO 90 IS HORIZONTAL FORWARD.** Extended at 40 the point raked
/// 55 deg into the dirt (measured). The coil is BEHIND him, not across him: at a slash's rotation the point
/// swung 1.36 m sideways inside its live window against the flick's 1.43. The drive is `sh` + `elbow` + the step.
const THRUST_COIL = MK{ .sh = 26, .elbow = 104, .sweep = -4, .roll = 8, .wrist = 14, .yaw = -9, .chest = -11, .dip = 0.030 * H, .pitch = -7, .free = -20, .brace = 10, .abd = 4, .grip = GRIP_PITCH };

/// DS1's dagger R2, and ER's Main-gauche / Miséricorde / Scorpion's Stinger. The shoulder goes FORWARD
/// rather than up and the trunk SQUARES rather than turning; the 1.35 m step is the reach.
const THRUST_KEYS = [_]MKey{
    .{ .t = 0.00, .p = THRUST_REST },
    .{ .t = 0.22, .p = THRUST_COIL, .ease = .decel },
    // **THE COIL IS HELD, AND THAT IS THE BAIT** (`anim.Ease.hold`) — 0.07 s of a point standing still at the ribs.
    .{ .t = 0.32, .p = THRUST_COIL, .ease = .hold },
    .{ .t = 0.50, .p = .{ .sh = 78, .elbow = 3, .sweep = 0, .roll = 2, .wrist = -6, .yaw = 4, .chest = 6, .dip = 0.014 * H, .pitch = 15, .free = 26, .brace = 5, .grip = GRIP_PITCH }, .ease = .accel },
    .{ .t = 0.60, .p = .{ .sh = 84, .elbow = -3, .sweep = 1, .roll = 1, .wrist = -9, .yaw = 6, .chest = 8, .dip = 0.010 * H, .pitch = 18, .free = 29, .brace = 3, .grip = GRIP_PITCH }, .ease = .decel },
    .{ .t = 0.76, .p = .{ .sh = 44, .elbow = 44, .sweep = 0, .roll = 4, .yaw = 2, .chest = 3, .dip = 0.010 * H, .pitch = 6, .free = 12, .brace = 4, .grip = GRIP_PITCH } },
    .{ .t = 1.00, .p = THRUST_REST },
};

const SWEEP_REST = MK{ .sh = 24, .elbow = 32, .grip = GRIP_PITCH };
const SWEEP_WIND = MK{ .sh = 44, .elbow = 68, .sweep = -94, .roll = 18, .wrist = 22, .yaw = -30, .chest = -35, .dip = 0.030 * H, .pitch = -9, .free = -26, .brace = 13, .abd = 14, .tilt = -6, .grip = GRIP_PITCH };

/// DS1's Large Club dashing horizontal swing. Hips first, and 1.44 m of bog-oak does not stop where the swing did.
const SWEEP_KEYS = [_]MKey{
    .{ .t = 0.00, .p = SWEEP_REST },
    .{ .t = 0.24, .p = SWEEP_WIND, .ease = .decel },
    .{ .t = 0.31, .p = SWEEP_WIND, .ease = .hold },
    .{ .t = 0.58, .p = .{ .sh = 44, .elbow = 21, .sweep = 76, .roll = -22, .wrist = -18, .yaw = 27, .chest = 41, .dip = 0.040 * H, .pitch = 6, .free = 30, .brace = 9, .tilt = 5, .grip = GRIP_PITCH }, .ease = .accel },
    .{ .t = 0.71, .p = .{ .sh = 40, .elbow = 15, .sweep = 106, .roll = -30, .wrist = -24, .yaw = 35, .chest = 53, .dip = 0.036 * H, .pitch = 5, .free = 34, .brace = 7, .tilt = 8, .grip = GRIP_PITCH }, .ease = .decel },
    .{ .t = 0.87, .p = .{ .sh = 32, .elbow = 36, .sweep = 78, .roll = -12, .wrist = -8, .yaw = 20, .chest = 30, .dip = 0.018 * H, .pitch = 4, .free = 16, .brace = 4, .tilt = 3, .grip = GRIP_PITCH } },
    .{ .t = 1.00, .p = SWEEP_REST },
};

const SMASH_REST = MK{ .sh = 16, .elbow = 32, .grip = GRIP_PITCH };
/// **THE ELBOW IS NEARLY STRAIGHT AT THE TOP, AND THAT IS THE WHOLE TELL.** Folded to 86 the tip clears his
/// crown by 4 cm (measured) and nobody in front can read it; at 34 it stands 3.3 m up.
const SMASH_TOP = MK{ .sh = 170, .elbow = 34, .sweep = -6, .wrist = 22, .yaw = -8, .chest = -11, .dip = -0.008 * H, .pitch = -15, .free = -36, .brace = 5, .abd = 8 };

/// DS1's "slow, heavy overhead smash" for the Great Club and two-handed Large Club. He RISES onto it (the dip
/// goes negative), HANGS, then drops his whole weight behind it; the deepest dip in the kit.
const SMASH_KEYS = [_]MKey{
    .{ .t = 0.00, .p = SMASH_REST },
    .{ .t = 0.28, .p = SMASH_TOP, .ease = .decel },
    // **THE HANG IS THE TELL, AND IT IS 0.17 s** at the dial the fight runs it at — ten frames. It was 0.37 s
    // (owner: less hang time before coming down).
    .{ .t = 0.40, .p = SMASH_TOP, .ease = .hold },
    // `.smooth` not `.accel`: back-loaded, the club was still 3.35 m up when the capsule went live (measured).
    .{ .t = 0.56, .p = .{ .sh = 65, .elbow = 14, .sweep = 4, .wrist = 30, .yaw = 6, .chest = 15, .dip = 0.075 * H, .pitch = 27, .free = 22, .brace = 17 }, .ease = .smooth },
    .{ .t = 0.67, .p = .{ .sh = 58, .elbow = 26, .sweep = 3, .wrist = 16, .yaw = 5, .chest = 12, .dip = 0.066 * H, .pitch = 23, .free = 18, .brace = 14 }, .ease = .decel },
    .{ .t = 0.83, .p = .{ .sh = 40, .elbow = 30, .wrist = 6, .yaw = 3, .chest = 6, .dip = 0.032 * H, .pitch = 12, .free = 9, .brace = 7 } },
    .{ .t = 1.00, .p = SMASH_REST },
};

/// A slash and a sweep come off alternating shoulders; a thrust and a smash are on the centre line, and
/// mirroring one only makes it look like it missed on purpose.
fn strokeTrack(s: Stroke) ?struct { keys: []const MKey, mirrors: bool } {
    return switch (s) {
        .slash, .chop => null,
        .flick => .{ .keys = &FLICK_KEYS, .mirrors = true },
        .thrust => .{ .keys = &THRUST_KEYS, .mirrors = false },
        .sweep => .{ .keys = &SWEEP_KEYS, .mirrors = true },
        .smash => .{ .keys = &SMASH_KEYS, .mirrors = false },
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

/// The CHEST carries the larger share: split evenly the shoulders lead the hips, which reads as the arm dragging the body round.
const TRUNK_YAW_SPINE = 0.35;
const TRUNK_YAW_CHEST = 0.65;

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
        // `legChain`'s stance sweep is measured in UNITS off the leg, so scaling one without the other skates the planted foot.
        const sagLen = STRIDE * mathx.clampF(0.55 + 0.45 * speed / WALK_REF_SPEED, 0.8, 2.0) *
            mathx.lerpF(1.0, BACK_STRIDE, mathx.maxF(0, -fwdB.*));
        const strideLen = mathx.lerpF(sagLen, STRAFE_CYCLE, @abs(latB.*));
        phase.* += movedDist / strideLen;
    }
    phase.* -= @floor(phase.*);
}

/// The FLAT world's ground plane. The IK takes the actor's own `pos.y`; this is only what a rig posed at the
/// origin stands on, and what the sole tests measure against.
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

/// Appending is free: `save.zig` writes the rack by TAG NAME, and the book's hand menu is folded over these
/// fields IN THIS ORDER.
pub const Armament = enum { sword, dagger, club, bow, bell, shield, wand, torch };

pub const Arm = Armament;
pub const Off = Armament;

pub const RIGHT: usize = 0;
pub const LEFT: usize = 1;

/// The bow's R1/R2 are not swings; the loose is routed on `bowOut` at the input.
pub fn armSwings(a: Armament) bool {
    return switch (a) {
        .sword, .dagger, .club => true,
        .bow, .bell, .shield, .wand, .torch => false,
    };
}

pub fn armTwoHanded(a: Armament) bool {
    return a == .bow;
}

pub fn handsHold(arm: Armament, off: Armament, a: Armament) bool {
    if (armTwoHanded(arm)) return a == arm;
    if (armTwoHanded(off)) return a == off;
    // **THE WEAPON HAND IS ONE HAND.** The rig has ONE held bone (`SWORD`), so a second melee class would
    // silently not be drawn. The RIGHT cell wins, and `offInHand` reports it so the book can give a reason.
    if (armSwings(arm) and armSwings(off)) return a == arm;
    return arm == a or off == a;
}

/// Off the two cells alone, so the book can price a candidate loadout (`derive`) with the same answer
/// the hero gives about himself (`Hero.meleeArm`).
pub fn meleeArmOf(arm: Armament, off: Armament) ?Armament {
    if (armSwings(arm) and handsHold(arm, off, arm)) return arm;
    if (armSwings(off) and handsHold(arm, off, off)) return off;
    return null;
}

/// `hand_sword` when he holds nothing that swings: a bare row is the honest price of an empty hand, and
/// `armSwings` gates whether it is shown at all.
pub fn swingSocket(arm: Armament, off: Armament) item.Wear {
    const a = meleeArmOf(arm, off) orelse return .hand_sword;
    return wearFor(a) orelse .hand_sword;
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
    torch: rl.Mesh,
    torchFlame: rl.Mesh,
    dagger: rl.Mesh,
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
    /// A WORLD height, integrated under gravity; `lift` is DERIVED off it. A lift integrated over a moving
    /// datum sinks with the ground it was measured from when he runs off a ledge.
    airY: f32 = 0,
    vertVel: f32 = 0,
    jumping: bool = false,
    /// Differs from `jumping` in exactly two ways: he cannot steer it and cannot turn in it, and he lands in
    /// a heavy stun rather than on his feet.
    launched: bool = false,
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
    /// WHICH COLUMN THE WARD RUNNING IS IN. One ward at a time by construction: a second tonic replaces the
    /// first the way `Timed` refreshes rather than stacks.
    wardElem: combat.Elem = .chaos,
    grease: combat.Timed = .{},
    /// WHICH ELEMENT IS ON THE EDGE. Same rule — one coating, and the last one wiped on is the one that is there.
    greaseElem: combat.Elem = .fire,
    /// **A SECOND CLOCK, NOT THE GREASE'S** — a grease hangs an element on the blow, a coat leaves a DOSE in the
    /// wound, and both may be on the edge at once. One `Timed` for the two would have the nightcap wipe the
    /// tallow off.
    coat: combat.Timed = .{},
    coatAil: combat.Ail = .sleep,
    steady: combat.Timed = .{},
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
    mem: combat.Memory = .{},
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
    /// **SECONDS OF NET.** The foes' own law on the hero's side (`foe.grip`): it takes ONE thing, the FEET.
    /// The state machine still runs, the sword still swings, the shield still blocks — he simply cannot go
    /// anywhere, and a roll is travel so it is refused with the walk.
    snare: f32 = 0,
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
            .torch = torchMesh(),
            .torchFlame = torchFlameMesh(),
            .dagger = daggerMesh(),
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

    /// The three bars take their SIZE from the sheet here and nowhere else, so a raised attribute cannot leave one at its old length.
    fn makeWhole(self: *Hero) void {
        self.vit = freshVitals(self.sheet);
        // The bar's LENGTH, never its refill rate. `poise` is set alongside `poiseMax` because a lengthened bar left at its old fill comes up short.
        self.vit.poiseMax = POISE_MAX * self.perk.poiseMax;
        self.vit.poise = self.vit.poiseMax;
        self.refitHp();
        self.stam.max = self.sheet.stamina() * self.perk.stamMax;
        self.fp.max = fpMaxOf(self.sheet, self.worn, self.perk);
        self.stam.reset();
        self.fp.reset();
        self.regen.reset();
        self.ward.reset();
        self.grease.reset();
        self.coat.reset();
        self.steady.reset();
        self.vit.poiseRate = 1;
        self.settleBody();
        // **THE FLASKS COME BACK AND THE ARROWS DO NOT** (owner: arrows are found or bought, never granted). This
        // is the one line that made the bow free: `makeWhole` runs on a rest, on a death and on a load, so a
        // refill here meant a full quiver three ways and the arrow economy was decoration.
        self.flasks.refill();
    }

    fn tickClocks(self: *Hero, dt: f32) void {
        // Cleared HERE, not in each update: a frame long enough to cross both the release knot and the end of the shot sets `loosed` and drops `shooting` in one call.
        self.loosed = false;
        self.thrown = false;
        self.rang = false;
        self.landed = false;
        self.elapsed += dt;
        if (self.levinT > 0) self.levinT = mathx.maxF(0, self.levinT - dt);
        self.trail.age(dt);
        self.blendT = @min(self.blendT + dt, mathx.LONG_AGO);
        // Stamina must advance exactly ONCE per frame whichever path runs, or `--shot` drains every swing it
        // takes and never refills. The cast is in the PAUSE list but not the DRAIN argument: it bills FP.
        self.stam.regenRate = self.perk.stamRegen;
        if (!self.held) self.stam.tick(dt, self.sprinting, self.attacking or self.rolling or self.guarding or self.casting or self.parrying);
        // NOT gated on the poise clock — this is a trickle, not the stagger refill. Neither can exceed its pool.
        if (!self.held and !self.dead) {
            if (self.perk.hpRegen > 0) _ = self.vit.heal(self.perk.hpRegen * dt);
            if (self.perk.fpRegen > 0) _ = self.fp.restore(self.perk.fpRegen * dt);
        }
        self.snare = @max(0, self.snare - dt);
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
        return self.jumping or self.launched;
    }

    pub fn startJump(self: *Hero, dir: rl.Vector3, speed: f32) bool {
        if (!self.bodyFree()) return false;
        self.jumping = true;
        self.jumps +%= 1;
        self.airY = self.pos.y;
        self.vertVel = JUMP_V0;
        self.airSpeed = if (mathx.lenXZ(dir) > 0.01) speed else 0;
        self.airYaw = if (self.airSpeed > 0.01) mathx.headingXZ(dir) else self.facing;
        self.startXfade();
        return true;
    }

    /// Deliberately NOT gated on `committed()` the way `startJump` is — a swing or roll being taken off him
    /// mid-way is the whole of what the move says. The stun is CLEARED on the way up, because the loop asks
    /// `staggered()` before `airborne()` and a launch that also stunned him would never leave the ground; he is
    /// stunned on the way down instead (`tickAir`). `held` refuses outright: `tickAir` will not integrate while
    /// the world is stopped, so a launch granted on such a frame would strand him mid-flight.
    pub fn startLaunch(self: *Hero, away: rl.Vector3, apex: f32) bool {
        if (self.dead or self.held or apex <= 0) return false;
        self.dropActions();
        self.stun = .none;
        self.stunT = 0;
        self.jumping = false;
        self.launched = true;
        self.airY = self.pos.y;
        self.vertVel = launchV0(apex);
        self.airSpeed = launchSpeed(apex);
        self.airYaw = if (mathx.lenXZ(away) > 1e-3) mathx.headingXZ(away) else self.facing + std.math.pi;
        self.landT = mathx.LONG_AGO;
        self.startXfade();
        return true;
    }

    fn tickAir(self: *Hero, dt: f32) void {
        if (self.held) return;
        if (!self.airborne()) {
            self.lift = 0;
            return;
        }
        self.airY += self.vertVel * dt - 0.5 * JUMP_G * dt * dt;
        self.vertVel -= JUMP_G * dt;
        if (self.airY <= self.pos.y) {
            const thrown = self.launched;
            self.airY = self.pos.y;
            self.lift = 0;
            self.vertVel = 0;
            self.jumping = false;
            self.launched = false;
            self.landed = true;
            self.landT = 0;
            // **THE LIGHT STUN, NOT THE HEAVY ONE** (owner: "big slam knockback recovery takes too long"). The
            // FLIGHT is the reaction — 0.66 s of it, and a 1.15 s heavy stun on top made 1.8 s of no control off
            // one blow. At 0.46 it comes to 1.12 s, near enough the plain heavy stagger (1.15) this replaces.
            if (thrown) {
                self.enterStun(.light);
                return;
            }
            self.startXfade();
            self.fireQueued();
            return;
        }
        self.lift = self.airY - self.pos.y;
    }

    pub fn steerAir(self: *Hero, dt: f32, dir: rl.Vector3) void {
        if (self.launched) return;
        if (self.airSpeed <= 0.01 or mathx.lenXZ(dir) < 0.01) return;
        self.airYaw = mathx.approachAngle(self.airYaw, mathx.headingXZ(dir), AIR_TURN_RATE * dt);
    }

    pub fn updateAir(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = self.airSpeed;
        self.speedS = mathx.approach(self.speedS, self.airSpeed, dt * SPEED_SMOOTH);
        // THROWN, HE KEEPS THE BEARING HE WAS HIT ON: travelling backwards while still facing what hit him is what makes the arch read as being knocked over rather than as a leap.
        if (!self.launched) {
            const want = faceYaw orelse self.airYaw;
            self.facing = mathx.approachAngle(self.facing, want, ROLL_YAW_RATE * dt);
        }
        self.pose();
    }

    pub fn startRoll(self: *Hero, dir: rl.Vector3) void {
        if (!self.bodyFree()) return;
        // **A ROLL IS TRAVEL.** Refused here at the CHOOSE, the way a leap is refused of a rooted creature
        // (`foe.canLeap`) — gated later it would spend the stamina and roll on the spot.
        if (self.snared()) {
            self.refuse();
            return;
        }
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
        return self.jumping or self.launched or self.rolling or self.attacking or self.drinking or self.shooting or self.casting or self.parrying or self.ringing;
    }

    pub fn holds(self: *const Hero, a: Armament) bool {
        return handsHold(self.arm, self.off, a);
    }

    /// The RIGHT wins if somehow both, since that is the hand the rig's held bone is parented to. One of the
    /// TWO forms the four `*Left` predicates take; what separates them is only which hand they name for an
    /// armament that is not held at all.
    fn heldLeft(self: *const Hero, a: Armament) bool {
        return self.arm != a and self.off == a and self.offInHand();
    }

    fn heldRight(self: *const Hero, a: Armament) bool {
        return self.arm == a;
    }

    pub fn bellLeft(self: *const Hero) bool {
        return self.heldLeft(.bell);
    }

    /// **AN UNHELD ARMAMENT FALLS BACK TO ITS OWN HAND, WHICH IS WHY THESE TWO ARE REVERSED**: the rod and
    /// boards are LEFT-hand, so `!heldRight`; the sword and bell are RIGHT-hand, so `heldLeft`. It only shows
    /// while a swap's blend eases out, so unifying them is a LOOK, not a cleanup.
    pub fn wandLeft(self: *const Hero) bool {
        return !self.heldRight(.wand);
    }

    pub fn shieldLeft(self: *const Hero) bool {
        return !self.heldRight(.shield);
    }

    pub fn torchLeft(self: *const Hero) bool {
        return !self.heldRight(.torch);
    }

    pub fn bowOut(self: *const Hero) bool {
        return self.holds(.bow);
    }

    pub fn bellOut(self: *const Hero) bool {
        return self.holds(.bell);
    }

    /// False when the right cell has taken both hands (`armTwoHanded`) and when both cells hold a melee class
    /// (`handsHold`'s weapon-hand rule). The book reads this to give a REASON rather than draw a weapon that is not there.
    pub fn offInHand(self: *const Hero) bool {
        if (armTwoHanded(self.arm) or armTwoHanded(self.off)) return false;
        return !(armSwings(self.arm) and armSwings(self.off));
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

    pub fn torchOut(self: *const Hero) bool {
        return self.holds(.torch);
    }

    /// Asked by the light and by the bed that is its voice, so the two can never disagree about when it is burning.
    pub fn torchLit(self: *const Hero) bool {
        return self.torchOut() and !self.resting;
    }

    /// **THE BODY IS FREE TO START SOMETHING.** Committed to a move, reeling, dead or seated at a fire: four
    /// states and ONE answer, and every door into a new action opens on it — `startJump`, `startRoll`,
    /// `startAttack`, `startDrink`, `swapHand`/`equip`, and the book's two-part hand action (`game.takeHand`).
    /// Spelled out at each site, a door added later forgets one of the four, and a caller that gates only half
    /// of a change applies the other half anyway.
    pub fn bodyFree(self: *const Hero) bool {
        return !self.committed() and !self.staggered() and !self.dead and !self.resting;
    }

    /// …AND THE ARMS THAT ALSO REFUSE A SPRINT (`shieldArm`, `castReady`, `canRing`). One name for the pair,
    /// because a sprint is the only extra state a HELD arm answers to and three copies of the five is the same
    /// forgetting `bodyFree` exists to stop.
    fn armFree(self: *const Hero) bool {
        return self.bodyFree() and !self.sprinting;
    }

    fn swapHand(self: *Hero, live: *Armament, alt: *Armament) bool {
        if (!self.bodyFree()) return false;
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

    /// Taking a thing already in another cell SWAPS the two rather than refusing.
    pub fn equip(self: *Hero, hand: usize, slot: usize, a: Armament) bool {
        if (!self.bodyFree()) return false;
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

    /// The sword and the five tools always; a dagger or club only with its own weapon in its socket, because
    /// those two are things you FIND. `book.candidates` enforces the same rule at the offer.
    pub fn canRack(self: *const Hero, a: Armament) bool {
        if (!armSwings(a) or a == .sword) return true;
        return self.worn.at(wearFor(a) orelse return false) != null;
    }

    /// A save written before the rack was distinct can hold the same armament twice; the first cell keeps it.
    /// **THE FILLER MAY NOT BE A WEAPON HE DOES NOT OWN** — first-unused-in-declaration-order handed every such
    /// save a free `.dagger`. Six fillers always pass `canRack` against four cells, so a duplicate is resolvable.
    pub fn tidyHands(self: *Hero) void {
        var seen = std.EnumSet(Armament).initEmpty();
        for (self.rack()) |c| {
            if (!seen.contains(c.*)) {
                seen.insert(c.*);
                continue;
            }
            for (std.enums.values(Armament)) |a| {
                if (seen.contains(a) or !self.canRack(a)) continue;
                c.* = a;
                seen.insert(a);
                break;
            }
        }
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

    /// `armFree` with ONE exception, which is why it is still spelled out: a shot already in flight keeps the
    /// aim, and that is the only door in the game that holds through its own commitment.
    pub fn canAim(self: *const Hero) bool {
        return self.bowOut() and (!self.committed() or self.shooting) and
            !self.staggered() and !self.dead and !self.sprinting and !self.resting and self.stam.canAct();
    }

    pub fn requestShot(self: *Hero, aimed: bool) void {
        if (!self.bowOut() or !self.bodyFree()) return;
        if (aimed and !self.aiming) return;
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
        return self.shieldOut() and self.armFree();
    }

    pub fn canGuard(self: *const Hero) bool {
        return self.shieldArm() and self.stam.canAct();
    }

    /// It asks nothing about whether the boards are RAISED. Answered THROUGH `canGuard` so the two cannot drift.
    pub fn canParry(self: *const Hero) bool {
        return self.canGuard();
    }

    /// NEVER BUFFERED: a parry is a window the player picked a moment for. Reports whether one started.
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

    /// MEASURED off the fit matrix's own constants and MIRRORED WITH IT (`shieldFit`), since both the hub and
    /// the normal are lateral. Taken off a fixed `WRL`, boards equipped RIGHT threw every shower off the other hand.
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = at,
                .v = v,
                .life = rng.range(0.16, 0.72),
                .r0 = rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI),
                .r1 = 0.003,
                .col = if (rng.float() < 0.45) PARRY_SPARK_HOT else PARRY_SPARK,
                .col1 = PARRY_SPARK_COOL,
                .grav = PARRY_SPARK_GRAV,
                .stretch = SPARK_STRETCH,
                .bounce = SPARK_BOUNCE,
                .add = true,
            });
        }
        foemod.emitPart(&self.fx, &self.fxHead, .{ .p = at, .v = mathx.scaleV(f.n, 0.8), .life = PARRY_FLASH_LIFE, .r0 = PARRY_FLASH_R, .r1 = PARRY_FLASH_R * 0.25, .col = PARRY_SPARK_HOT, .add = true });
    }

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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = p,
                .v = v,
                .life = rng.range(FOG_WAKE_LIFE_LO, FOG_WAKE_LIFE_HI),
                .r0 = rng.range(FOG_WAKE_R0_LO, FOG_WAKE_R0_HI),
                .r1 = FOG_WAKE_R1,
                .col = if (rng.float() < 0.45) propfx.FOG_WAKE_PALE else propfx.FOG_WAKE_DEEP,
                .col1 = FOG_WAKE_THIN,
                .grav = FOG_WAKE_GRAV,
                .drag = FOG_WAKE_DRAG,
            });
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = at,
                .v = v,
                .life = rng.range(BLOCK_GRIT_LIFE_LO, BLOCK_GRIT_LIFE_HI),
                .r0 = rng.range(0.010, 0.022),
                .r1 = 0.004,
                .col = if (rng.float() < 0.5) BLOCK_GRIT else BLOCK_GRIT_DARK,
                .grav = BLOCK_GRIT_GRAV,
                .stretch = 0.030,
                .bounce = 0.35,
            });
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = at,
                .v = v,
                .life = rng.range(0.16, 0.38),
                .r0 = rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI),
                .r1 = 0.003,
                .col = if (rng.float() < 0.34) PARRY_SPARK_HOT else PARRY_SPARK,
                .col1 = PARRY_SPARK_COOL,
                .grav = PARRY_SPARK_GRAV,
                .stretch = SPARK_STRETCH,
                .bounce = SPARK_BOUNCE,
                .add = true,
            });
        }
        foemod.emitPart(&self.fx, &self.fxHead, .{
            .p = at,
            .v = mathx.scaleV(f.n, 0.25),
            .life = BLOCK_PUFF_LIFE,
            .r0 = BLOCK_PUFF_R * (0.6 + 0.4 * w),
            .r1 = BLOCK_PUFF_R * 1.6,
            .col = BLOCK_GRIT_DARK,
            .grav = 1.5,
            .drag = 3.0,
        });
    }

    /// What separates a glint from a catch is COUNT and fan, never colour, or a whiff reads as half a hit.
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = from,
                .v = v,
                .life = rng.range(0.05, 0.15),
                .r0 = rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI),
                .r1 = 0.003,
                .col = PARRY_SPARK_HOT,
                .col1 = PARRY_SPARK_COOL,
                .grav = PARRY_SPARK_GRAV,
                .stretch = SPARK_STRETCH,
                .add = true,
            });
        }
        foemod.emitPart(&self.fx, &self.fxHead, .{ .p = at, .v = mathx.scaleV(f.n, 0.9), .life = PARRY_FLASH_LIFE, .r0 = PARRY_GLINT_FLASH_R, .r1 = PARRY_GLINT_FLASH_R * 0.25, .col = PARRY_SPARK_HOT, .add = true });
    }

    pub fn armed(self: *const Hero) bool {
        return self.mem.holds(self.spell);
    }

    /// The BODY's half only; `canCast` is this AND the rack, so a refusal can say which of the two said no.
    pub fn castReady(self: *const Hero) bool {
        return self.wandOut() and self.armFree();
    }

    pub fn canCast(self: *const Hero) bool {
        return self.castReady() and self.armed();
    }

    pub fn requestCast(self: *Hero) bool {
        if (!self.canCast()) return false;
        return self.startCast();
    }

    pub fn castCost(self: *const Hero) f32 {
        return combat.spellFp(self.spell) * self.perk.spellCost;
    }

    /// **THE RING IS THE RACK, NOT THE TABLE** — what is memorized, in the order the fire put it in.
    pub fn cycleSpell(self: *Hero) bool {
        if (self.dead or self.casting) return false;
        const next = self.mem.next(self.spell) orelse return false;
        if (next == self.spell) return false;
        self.spell = next;
        return true;
    }

    /// Follows the rack (`tidyHands`' rule one socket along): a finger left on an un-memorized sorcery is a HUD cell naming a spell the wand refuses.
    pub fn tidySpells(self: *Hero) void {
        if (self.armed()) return;
        if (self.mem.first()) |s| self.spell = s;
    }

    /// The ONE door: nothing puts a sorcery in the rack without the selection being re-seated.
    pub fn memorize(self: *Hero, slot: usize, s: ?combat.Spell) void {
        self.mem.put(slot, s);
        self.tidySpells();
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
        self.castT += dt * self.castRate();
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
        return self.bellOut() and self.armFree();
    }

    pub fn ringCost(self: *const Hero) f32 {
        return combat.spiritFp(self.spirit) * self.perk.spellCost * charmOf(self.worn).spiritFp;
    }

    /// Reports whether one STARTED, since the caller's voice must not sound for a ring the pool refused.
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

    /// Off the cast clock, not a flag of its own: AN EFFECT'S CLOCK IS DERIVED FROM THE MECHANIC'S, NEVER PARALLEL TO IT.
    pub fn breathLive(self: *const Hero) bool {
        if (!self.casting or self.spell != .rime) return false;
        return self.castT >= breathAt() and self.castT < breathAt() + combat.RIME_DUR;
    }

    /// **THE POUR IS BILLED ON THE CAST CLOCK, NOT THE WALL CLOCK.** `breathLive` is a window in `castT`, which
    /// `perk.castSpeed` advances faster, so a real-time dose made every point of cast speed a cut to the spell:
    /// at the tree's 1.45x the cone billed 10.5 cold against the 15.3 `combat.SPELLS` prices it at, quietly
    /// under the ladder its own comptime assert exists to hold.
    pub fn breathDose(self: *const Hero, dt: f32) f32 {
        return dt * self.castRate();
    }

    pub fn breathU(self: *const Hero) f32 {
        if (!self.casting or self.spell != .rime) return 0;
        return mathx.clampF((self.castT - breathAt()) / combat.RIME_DUR, 0, 1);
    }

    /// Off the POSED ROD, so it rides the wrist and the kick. The last centimetres step out along his FACING,
    /// not the rod's own axis, because `facing` is what the cone is aimed down (`breathDir`).
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
            // RADIANS because a cone's geometry wants them; authored in degrees for `withinArc` and converted here.
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

    /// Off the posed wrist THE ROD IS ACTUALLY IN. Measured from the mesh's own constants (`wandMesh` takes no
    /// fit matrix), so one index and no mirror. Welded to `WRL`, a rod equipped RIGHT threw every bolt out of the empty hand.
    pub fn wandTipWorld(self: *const Hero) rl.Vector3 {
        return rl.math.vector3Transform(wandAt(WAND_TIP_T), self.xf[if (self.wandLeft()) WRL else WRR]);
    }

    pub fn torchFlameWorld(self: *const Hero) rl.Vector3 {
        return rl.math.vector3Transform(torchAt(TORCH_FLAME_T), self.xf[if (self.torchLeft()) WRL else WRR]);
    }

    /// SCALED WHOLE, not on the damage alone, or the poise it staggers with stays at its level-1 figure. Null
    /// for the two that bill over time (`combat.spellBlow`). Intelligence is the other half: the wand has no
    /// `item.Arm` row to hang a skill scale off (`wearFor` gives it no socket).
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
        if (!self.bodyFree()) return;
        // NOTHING SWINGS AN EMPTY HAND. `game.handActs` already routes R1/R2 per armament; this catches a caller
        // reaching past it, where a swing with no weapon poses the rig round an undrawn mesh and lands a bare-row blow.
        const held = self.meleeArm() orelse return;
        self.atkRow = self.armOf(wearFor(held) orelse .hand_sword);
        self.atkBlade = bladeOf(held) orelse .sword;
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
        const tm = self.swingMove().t;
        const dur: f32 = self.atkDur(self.atkHeavy);
        const u = mathx.clampF(self.atkT / dur, 0, 1);
        const speed: f32 = if (u >= tm.travelA and u < tm.travelB) tm.lunge / ((tm.travelB - tm.travelA) * dur) else 0;
        const moved = speed * dt;
        mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), moved, bounds);
        self.speed = speed;
        self.speedS = mathx.approach(self.speedS, speed, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| {
            if (u >= tm.recovA) self.facing = mathx.approachAngle(self.facing, ty, dt * ATK_RETRACK);
        }
        self.atkT += dt;
        const chain: f32 = tm.chain;
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
        if (!self.bodyFree()) return false;
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
                .crimson => _ = self.vit.heal(self.vit.hpMax * combat.FLASK_HP_FRAC * self.perk.flaskHeal),
                .cerulean => _ = self.fp.restore(self.fp.max * combat.FLASK_FP_FRAC),
            }
        }
        if (self.drinkT >= combat.FLASK_DRINK_DUR) {
            self.drinking = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    /// Through `Vitals.heal`, which refuses a corpse: a drain landing on the frame something else killed him may not undo it.
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
        const t = self.swingMove().t;
        const u = self.atkT / self.atkDur(self.atkHeavy);
        return u >= t.hitA and u < t.hitB;
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
        // Each mote is solved to ARRIVE at the stone and the stone crosses ~5 m/s through the lift, so without
        // the tip's velocity they converge on where it WAS. Skipped on frame one: `xf` is undefined until `pose` has run.
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
            foemod.emitPart(&self.fx, &self.fxHead, .{ .p = from, .v = v, .life = life, .r0 = CAST_MOTE_R0, .r1 = CAST_MOTE_R1, .col = CHAOS_MOTE, .stretch = CHAOS_STRETCH, .add = true });
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = at,
                .v = v,
                .life = life,
                .r0 = rng.range(0.030, 0.058),
                .r1 = 0.008,
                .col = if (rng.float() < 0.4) CHAOS_HOT else CHAOS_MOTE,
                .col1 = CHAOS_COOL,
                .grav = 2.0,
                .stretch = 0.040,
                .add = true,
            });
        }
        i = 0;
        while (i < CAST_COLLAR) : (i += 1) {
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, CAST_COLLAR) + rng.range(-0.26, 0.26);
            const sp = rng.range(CAST_COLLAR_SP * 0.7, CAST_COLLAR_SP);
            const v = mathx.addV(
                mathx.scaleV(side, mathx.cosf(a) * sp),
                mathx.addV(mathx.scaleV(up, mathx.sinf(a) * sp), mathx.scaleV(dir, rng.range(0.3, 1.4))),
            );
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = at,
                .v = v,
                .life = rng.range(0.13, 0.26),
                .r0 = rng.range(0.022, 0.040),
                .r1 = 0.006,
                .col = CHAOS_HOT,
                .col1 = CHAOS_COOL,
                .grav = 1.2,
                .stretch = 0.040,
                .add = true,
            });
        }
        foemod.emitPart(&self.fx, &self.fxHead, .{ .p = at, .v = mathx.scaleV(dir, 1.2), .life = CAST_FLASH_LIFE, .r0 = CAST_FLASH_R, .r1 = CAST_FLASH_R * 0.30, .col = CHAOS_HOT, .add = true });
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

    /// The other RESERVED slot (`game.reservedLights`): a room full of world fires may not evict the one light he brought.
    pub fn torchLight(self: *const Hero) ?gfx.Light {
        if (!self.torchLit()) return null;
        const k = mathx.maxF(1.0 + TORCH_FLICKER * mathx.gutter(@floatCast(rl.getTime()), 0.7), 0.05);
        return .{
            .pos = self.torchFlameWorld(),
            .col = mathx.scaleV(TORCH_LIT, k),
            .radius = TORCH_LIT_R,
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = from,
                .v = v,
                .life = rng.range(0.38, 0.78),
                .r0 = rng.range(0.045, 0.100),
                .r1 = 0.014,
                .col = ROOT_SOIL,
                .grav = 7.0,
                .stretch = 0.030,
                .bounce = 0.25,
            });
        }
        var j: u32 = 0;
        while (j < ROOT_MOTES) : (j += 1) {
            const a = rng.angle();
            const rr = rng.range(0.2, combat.ROOT_GRIP_R);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + rng.range(0.05, 0.6), at.z + mathx.sinf(a) * rr);
            const v = v3(rng.signed() * 0.9, rng.range(0.8, 2.4), rng.signed() * 0.9);
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = from,
                .v = v,
                .life = rng.range(0.45, 1.00),
                .r0 = rng.range(0.038, 0.072),
                .r1 = 0.010,
                .col = if (rng.float() < 0.4) CHAOS_HOT else CHAOS_MOTE,
                .col1 = CHAOS_COOL,
                .grav = -0.6,
                .add = true,
            });
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = at,
                .v = v,
                .life = life,
                .r0 = rng.range(0.040, 0.086),
                .r1 = 0.010,
                .col = if (rng.float() < 0.45) CHAOS_HOT else CHAOS_MOTE,
                .col1 = CHAOS_COOL,
                .grav = 3.4,
                .drag = 1.2,
                .stretch = 0.040,
                .add = true,
            });
        }
    }

    /// **A CLOUD IS NOT A BURST: IT HANGS.** Barely any gravity, heavy drag, a long life — so the ring the
    /// powder doses is something you can see the edge of. TINTED by the caller: it has to agree with the meter
    /// it fills (`hud.ailTint`).
    pub fn dustPuff(self: *Hero, at: rl.Vector3, r: f32, col: rl.Color, salt: u32) void {
        var rng = foemod.fxStream(@floatFromInt(salt), 619.0, 0x5D2A);
        var i: u32 = 0;
        while (i < DUST_MOTES) : (i += 1) {
            const a = rng.angle();
            // sqrt spreads the motes EVENLY over the disc; linear in radius piles them at the middle.
            const rad = r * @sqrt(rng.float());
            const p = v3(at.x + mathx.cosf(a) * rad, at.y + rng.range(0.05, 1.15), at.z + mathx.sinf(a) * rad);
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = p,
                .v = v3(mathx.cosf(a) * rng.range(0.25, 1.10), rng.range(0.15, 0.75), mathx.sinf(a) * rng.range(0.25, 1.10)),
                .life = rng.range(0.9, 1.9),
                .r0 = rng.range(0.075, 0.190),
                .r1 = rng.range(0.030, 0.090),
                .col = col,
                .col1 = mathx.withAlpha(col, 0),
                .grav = 0.28,
                .drag = 2.6,
            });
        }
    }

    /// `from`/`to` are the blow's OWN segment (`game.strikeSegment`), never a line derived a second time: the flash has to be where the blade was.
    pub fn levinStroke(self: *Hero, from: rl.Vector3, to: rl.Vector3, groundY: f32, salt: u32) void {
        // THE FLOOR IS THE EARTH UNDER THE STRIKE, not his feet and not the contact (`boltBurst`'s law) — the
        // contact is a body's CHEST, so floored there a falling spark would stop a metre up. Lightning's grav is 0 today.
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
            const chip = rng.float() < 0.5;
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = at,
                .v = v,
                .life = rng.range(0.22, 0.46),
                .r0 = rng.range(0.030, 0.062),
                .r1 = 0.008,
                .col = if (chip) SUNDER_CHIP else SUNDER_DUST,
                .grav = 6.0,
                .stretch = if (chip) 0.030 else 0,
                .bounce = if (chip) 0.35 else 0,
            });
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
            foemod.emitPart(&self.fx, &self.fxHead, .{
                .p = from,
                .v = v,
                .life = life,
                .r0 = rng.range(0.026, 0.048),
                .r1 = 0.008,
                .col = if (rng.float() < 0.45) CHAOS_HOT else CHAOS_MOTE,
                .col1 = CHAOS_COOL,
                .stretch = 0.030,
                .add = true,
            });
        }
    }

    pub fn attackHit(self: *const Hero) combat.Hit {
        const base = weigh(if (self.atkHeavy) ATK_HEAVY_HIT else ATK_LIGHT_HIT, self.swingRow(), self.sheet).scaled(self.perk.dmg * self.vit.dmgMult());
        if (!self.grease.on() and !self.coat.on()) return base;
        var out = base;
        if (self.grease.on()) out.elem.v[@intFromEnum(self.greaseElem)] += base.dmg * self.grease.value(0);
        // **ADDS TO THE EDGE'S OWN, NEVER REPLACES IT** (`weigh` writes the venom in): an envenomed dirk under
        // the nightcap carries both, in two meters.
        if (self.coat.on()) out.dose.v[@intFromEnum(self.coatAil)] += self.coat.value(0);
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

    /// The weapon hand is one hand (`handsHold`), so this is the single question `meleeLeft`, `startAttack`, the held mesh and the stow all open on.
    pub fn meleeArm(self: *const Hero) ?Armament {
        return meleeArmOf(self.arm, self.off);
    }

    /// False when he holds none: an unheld weapon falls back to its own hand and the melee classes are RIGHT-handed.
    pub fn meleeLeft(self: *const Hero) bool {
        const a = self.meleeArm() orelse return false;
        return self.arm != a;
    }

    fn swingRow(self: *const Hero) item.Arm {
        return if (self.attacking) self.atkRow else self.armOf(swingSocket(self.arm, self.off));
    }

    /// LATCHED for the stroke in flight: a club taken up mid-swing may not lend its reach to the sword that started it.
    pub fn heldBlade(self: *const Hero) Blade {
        if (self.attacking) return self.atkBlade;
        return bladeOf(self.meleeArm() orelse return .sword) orelse .sword;
    }

    pub fn bladeR(self: *const Hero) f32 {
        return bladeSpec(self.heldBlade()).r;
    }

    fn bladeMesh(self: *const Hero) rl.Mesh {
        return switch (self.heldBlade()) {
            .sword => self.mesh[SWORD],
            .dagger => self.dagger,
            .club => self.club,
        };
    }

    fn swingMove(self: *const Hero) Move {
        return moveOf(self.heldBlade(), self.atkHeavy);
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
        // The dials that live on the BODY are stamped here as well as per frame: a dose taken between putting a
        // cap on and the next `tickTimed` was billed at the old rate.
        self.settleBody();
        return true;
    }

    fn refitBars(self: *Hero) void {
        self.refitHp();
        refitPool(&self.stam.cur, &self.stam.max, self.sheet.stamina());
        refitPool(&self.fp.cur, &self.fp.max, fpMaxOf(self.sheet, self.worn, self.perk));
    }

    /// **THE FRACTION IS KEPT ACROSS THE RESIZE**: taking a ring off may not heal him and putting one on may not kill him.
    fn refitHp(self: *Hero) void {
        const frac = if (self.vit.hpMax > 1e-4) self.vit.hp / self.vit.hpMax else 1.0;
        self.vit.hpMax = hpMaxOf(self.sheet, self.worn, self.perk);
        self.vit.hp = mathx.minF(self.vit.hpMax, self.vit.hpMax * frac);
    }

    pub fn drinkLeech(self: *Hero) f32 {
        const back = self.charm().leech + self.perk.leech;
        return if (back > 0) self.vit.heal(back) else 0;
    }

    /// **HOW FAST A CAST RUNS, IN ONE PLACE** — the tree's node and whatever a meter is doing to him. The
    /// breath's dose rides the same number (`breathDose`), or every point of cast speed would be a cut to the
    /// spell it bought.
    pub fn castRate(self: *const Hero) f32 {
        return self.perk.castSpeed * self.vit.hasteMult();
    }

    /// **HOW FAST HE WALKS, ALL OF IT IN ONE PLACE** — the tree's node, what is on his feet, and what his
    /// meters are doing to him. `game.moveHero` is the only caller, so a slow cannot land on one movement path
    /// and not the others.
    pub fn moveRate(self: *const Hero) f32 {
        if (self.snared()) return 0;
        return moveRateOf(self.worn, self.perk) * self.vit.travelMult();
    }

    pub fn snared(self: *const Hero) bool {
        return self.snare > 0;
    }
    /// Longest wins — a second net over the first extends the hold, it never shortens it.
    pub fn snareFor(self: *Hero, secs: f32) void {
        if (self.dead) return;
        self.snare = @max(self.snare, secs);
    }

    pub fn atkDur(self: *const Hero, heavy: bool) f32 {
        return moveOf(self.heldBlade(), heavy).t.dur * self.swingRow().dur / self.vit.hasteMult();
    }

    /// ONE answer for the three places that each spelled out the same pair (`updateShot`, `bowLevels`, `shotU`) — the mechanic's knot and the pose's `u` cannot be a shaft apart.
    pub fn shotDur(self: *const Hero, aimed: bool) f32 {
        return @as(f32, if (aimed) BOW_SHOT_DUR else BOW_QUICK_DUR) * self.drawRow().dur;
    }

    fn shotAt(self: *const Hero) f32 {
        return if (self.shotAimed) BOW_SHOT_AT else BOW_QUICK_AT;
    }

    pub fn guardWalk(self: *const Hero) f32 {
        return self.armOf(.hand_shield).walk;
    }

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
        // **THE THROW IS LAST, BECAUSE IT BEATS THE STAGGER IT REPLACES.** `startLaunch` clears the stun it finds
        // and hands it back on the landing, so a slam reads as one reaction rather than a flinch then a flight.
        if (r != .death) _ = self.startLaunch(mathx.scaleV(fromDir, -1), h.launch);
        return .taken;
    }

    /// Takes a whole `Hit` because a floor has an ELEMENT. A DRIP, not a blow: its pulse lands inside the regen delay (0.42 against 0.8), so billed through `hit` the gate never opens.
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
        const negate = combat.guardNegation(board.negate, self.perk.guard);
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
        // A guard that BROKE did not stop the blow, so the throw is still owed. `blockHit` has no bearing of its own, so it is taken off his facing.
        if (h.launch > 0) _ = self.startLaunch(mathx.headingDir(self.facing + std.math.pi), h.launch);
        return .guardBroken;
    }
    pub fn tickFlash(self: *Hero, dt: f32) void {
        self.hurtFlash = mathx.maxF(0, self.hurtFlash - dt * 2.6);
    }

    pub fn startWard(self: *Hero, e: combat.Elem, amount: f32, secs: f32) void {
        self.wardElem = e;
        self.ward.start(amount, secs);
        self.settleBody();
    }

    pub fn startGrease(self: *Hero, e: combat.Elem, frac: f32, secs: f32) void {
        self.greaseElem = e;
        self.grease.start(frac, secs);
    }

    pub fn startCoat(self: *Hero, a: combat.Ail, amt: f32, secs: f32) void {
        self.coatAil = a;
        self.coat.start(amt, secs);
    }

    /// The side gate is what makes this safe (`Vitals.build` refuses a foe-only row), so a `dose` use may name
    /// any of the ten without a second list here.
    pub fn doseSelf(self: *Hero, a: combat.Ail, amt: f32) void {
        if (self.dead) return;
        self.vit.build(a, amt);
    }

    pub fn startSteady(self: *Hero, mult: f32, secs: f32) void {
        self.steady.start(mult, secs);
        self.vit.poiseRate = self.steady.value(1);
    }

    pub fn purgePoison(self: *Hero) void {
        self.vit.clearAils();
    }

    pub fn tickTimed(self: *Hero, dt: f32) void {
        self.ward.tick(dt);
        self.grease.tick(dt);
        self.coat.tick(dt);
        self.steady.tick(dt);
        self.vit.poiseRate = self.steady.value(1);
        self.settleBody();
    }

    /// **THE ONE PLACE THE DIALS ON HIS BODY ARE WRITTEN** — asked every frame (`tickTimed`), because `wear`
    /// changes what is on him without going anywhere near here. A coat taken off may not leave its column
    /// behind, and a cap taken off may not leave its poison rate behind either.
    fn settleBody(self: *Hero) void {
        // ONE WALK OF THE SOCKETS, not one per dial (`suitOf`) — the columns, the poison rate and the focus
        // pool all come off it, and this runs every frame.
        const suit = suitOf(self.worn);
        var r = self.baseRes;
        r.v[@intFromEnum(self.wardElem)] += self.ward.value(0);
        const worn = combat.resistsOf(suit.plate.res);
        for (&r.v, worn.v) |*x, w| x.* += w;
        self.vit.res = r;
        // **ALL TEN, EVERY FRAME.** The tree's one node is poison's alone (`ptree.Bonus.poison`). A walk rather
        // than a line per meter, so a helm for a new ailment needs no edit here.
        for (0..combat.NAIL) |i| {
            const perked: f32 = if (i == @intFromEnum(combat.Ail.poison)) self.perk.poison else 1.0;
            self.vit.ailRate[i] = perked * suit.rates[i];
        }
        // **THE STUPEFIED POOL IS SHORTER, NOT DRAINED.** Refit rather than spend, so letting it go hands the
        // focus back at the share he had — the same rule a lengthened HP bar comes up on (`refitHp`).
        refitPool(&self.fp.cur, &self.fp.max, fpMaxFrom(self.sheet, suit.charm, self.perk) * self.vit.focusMult());
    }

    pub fn poisonBy(self: *Hero, amt: f32) void {
        if (self.dead) return;
        self.vit.build(.poison, amt);
    }

    /// **THE METERS ARE TICKED EVEN WHILE HE IS DEAD**, and `tickAils` is what refuses the bite. Gated up here
    /// instead, `justProcced` never cleared and the proc's beat (`game`'s shake, voice and flash) re-fired on
    /// every frame of the death animation.
    ///
    /// **AND THE THREE THAT PUT HIM ON THE FLOOR ARE ANSWERED HERE**, because a meter's proc is the only blow in
    /// the game that arrives from inside the body: the lightning's stun, a sleep taking hold, and the berserk
    /// bargain coming due at the far end of its own clock.
    pub fn tickPoison(self: *Hero, dt: f32) bool {
        const was = self.vit.hp;
        if (self.vit.tickAils(dt)) self.enterDeath();
        if (!self.dead) {
            if (self.vit.ailProcced(.stun) or self.vit.ailProcced(.sleep)) self.enterStun(.heavy);
            // **THE PRICE OF THE BARGAIN IS PAID ON THE WAY OUT** — the one stagger nothing struck him for.
            if (self.vit.ailEnded(.berserk)) self.enterStun(.heavy);
        }
        return self.vit.hp < was;
    }

    /// The harness's own reset between two staged moves, so one cell cannot leak into the next.
    pub fn clearForShot(self: *Hero) void {
        self.dropActions();
        self.stun = .none;
        self.stunT = 0;
        self.clearAir();
        self.startXfade();
        self.pose();
    }

    fn clearAir(self: *Hero) void {
        self.jumping = false;
        self.launched = false;
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
        // **ASLEEP IS A STAGGER THAT WILL NOT TIME OUT** (owner: unable to act until hit). The wake is on the
        // blow path (`takeHit`), so a poison tick leaves him lying there and only a real blow gets him up.
        if (self.stunT >= dur and !self.vit.asleep()) {
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
        if (self.launched) return self.poseLaunch();
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

        legChain(&wx, &self.rest, self.footY(), ph, m, runB, fw, lat, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
        legChain(&wx, &self.rest, self.footY(), ph + 0.5, m, runB, fw, lat, -1.0, HIPR, KNEER, BOOT_SOLE[1]);

        const armAmp = mathx.lerpF(ARM_SWING, RUN_ARM_SWING, runB);
        const armL = -armAmp * armSwing(ph) * m * fw;
        const armR = armAmp * armSwing(ph) * m * fw;
        armChain(&wx, self.rest, armL, m, runB, sprintB, 1.0, 0.0, SHL, ELL, WRL);
        armChain(&wx, self.rest, armR, m, runB, sprintB, -1.0, 1.0, SHR, ELR, WRR);
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());

        if (gB > 0.001) self.poseGuard(&wx, gB, rec, lean, prot, bank);

        self.poseCarried(&wx);
        if (self.bowOut()) self.poseBowArms(&wx, lean, prot, bank);
        if (self.drinking) self.poseDrinkArm(&wx, dk.lift, dk.tip);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// Asked in ONE place: the jump used to ask for the rod alone, and the brand's flame — and its light — snapped down onto a hanging arm for the whole of a leap.
    fn poseCarried(self: *const Hero, wx: *[N]rl.Matrix) void {
        if (self.wandOut()) self.poseCarryArm(wx, self.wandLeft(), WAND_CARRY);
        if (self.torchOut()) self.poseCarryArm(wx, self.torchLeft(), TORCH_CARRY);
    }

    fn poseCarryArm(self: *const Hero, wx: *[N]rl.Matrix, left: bool, c: Carry) void {
        const a = armSide(left, true);
        const swing = ARM_SWING * mathx.cosf(std.math.tau * self.phase) * self.moving * self.fwdB;
        var p = wx.*;
        setLocal(&p, a.sh, self.rest, mul3(
            rx(-c.flex + c.swing * swing),
            ry(a.mirror * c.yaw),
            rz(a.mirror * (ARM_ABD + c.abd)),
        ));
        setLocal(&p, a.el, self.rest, rx(-(c.elbow + c.elbowSwing * swing)));
        setLocal(&p, a.wr, self.rest, rz(a.mirror * c.wrist));
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
        placeSword(&gp, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
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
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
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

    /// Off the vertical velocity, normalised on the launch's own v0 so a bigger throw is not a different
    /// animation. Where the jump TUCKS at the apex this ARCHES. **AND THE ARCH OVERSHOOTS ITS REST**
    /// (`AGENTS.md`): it peaks a little past the apex, so he is still laying back once he has started to fall.
    fn poseLaunch(self: *Hero) void {
        const k = mathx.clampF(self.vertVel / launchV0(LAUNCH_MAX_APEX), -1, 1);
        const rise = mathx.clampF(k, 0, 1);
        const fall = mathx.clampF(-k, 0, 1);
        const arch = mathx.maxF(1.0 - rise, 0) * (1.0 - 0.45 * fall);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rx(-LAUNCH_ARCH * 0.30 * arch),
            mul(tr(0, hipY - 0.05 * H * arch, 0), ry(facingDeg)),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, rx(-LAUNCH_ARCH * 0.38 * arch));
        setLocal(&wx, CHEST, self.rest, rx(-LAUNCH_ARCH * 0.32 * arch));
        setLocal(&wx, NECK, self.rest, rx(-LAUNCH_HEAD * 0.4 * arch));
        setLocal(&wx, HEAD, self.rest, rx(-LAUNCH_HEAD * 0.6 * arch + HEAD_WALK * fall));
        inline for (.{ SHL, SHR }, .{ ELL, ELR }, .{ WRL, WRR }, .{ 1.0, -1.0 }) |sh, el, wr, side| {
            setLocal(&wx, sh, self.rest, mul(
                rx(-LAUNCH_ARM * arch),
                rz(side * (ARM_ABD + 0.62 * LAUNCH_ARM * arch)),
            ));
            setLocal(&wx, el, self.rest, rx(-(IDLE_ELBOW + 24.0 * arch)));
            setLocal(&wx, wr, self.rest, rl.math.matrixIdentity());
        }
        inline for (.{ HIPL, HIPR }, .{ KNEEL, KNEER }, .{ ANKL, ANKR }, .{ 1.0, -1.0 }) |hip, knee, ank, side| {
            const skew = 1.0 + side * 0.14; // wabi-sabi: the two legs never come up together
            setLocal(&wx, hip, self.rest, mul(
                rx(LAUNCH_HIP * arch * skew),
                rz(side * HIP_ADDUCT),
            ));
            setLocal(&wx, knee, self.rest, rx(IDLE_KNEE + LAUNCH_KNEE * arch * skew));
            setLocal(&wx, ank, self.rest, ry(side * FOOT_TOEOUT));
        }
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
        self.poseCarried(&wx);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// Off the vertical velocity: DRIVE up, TUCK where it passes through zero — which IS the apex, so the pose cannot drift out of step with the arc — REACH down.
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
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
        if (self.guardB > 0.001) self.poseGuard(&wx, mathx.clampF(self.guardB, 0, 1), 0, fold * 0.5, 0, 0);
        self.poseCarried(&wx);
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
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseAttack(self: *Hero) void {
        const stroke = self.swingMove().stroke;
        if (strokeTrack(stroke)) |tr_| return self.poseStroke(tr_.keys, tr_.mirrors);
        if (stroke == .chop) return self.poseHeavy();
        self.poseLight();
    }

    /// Four moves, one function. `lat` is the lateral sign (which hand, times the chain's alternation) and it multiplies exactly the channels that mirror.
    fn poseStroke(self: *Hero, keys: []const MKey, mirrors: bool) void {
        const u = mathx.clampF(self.atkT / self.atkDur(self.atkHeavy), 0, 1);
        const k = mkAt(keys, u);
        const sA = armSide(self.meleeLeft(), false);
        const fA = armSide(!self.meleeLeft(), false);
        const sd = sA.mirror;
        const sw: f32 = if (mirrors and self.atkAlt) -1.0 else 1.0;
        const lat = sd * sw;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        // THE WAIST TAKES THE FOLD, THE PELVIS STAYS NEAR-UPRIGHT (the ogre's `PELVIS_SHARE` law): a quarter of the pitch at the root, the rest split across spine and chest.
        const trunk = 0.5 * (0.75 * k.pitch + self.aimLean);
        const lead: f32 = if (lat > 0) 1.0 else 0.6;
        const trail: f32 = if (lat > 0) 0.6 else 1.0;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(lat * k.yaw),
            mul(tr(0, hipY - k.dip, 0), mul(rx(0.25 * k.pitch), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, mul3(rx(trunk), ry(lat * TRUNK_YAW_SPINE * k.chest), rz(lat * 0.5 * k.tilt)));
        setLocal(&wx, CHEST, self.rest, mul3(rx(trunk), ry(lat * TRUNK_YAW_CHEST * k.chest), rz(lat * 0.5 * k.tilt)));
        setLocal(&wx, NECK, self.rest, ry(-lat * 0.35 * (k.yaw + k.chest)));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK - 0.25 * k.pitch), ry(-lat * 0.30 * (k.yaw + k.chest))));
        setLocal(&wx, HIPL, self.rest, mul(rx(-0.7 * lead * k.brace), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + lead * k.brace));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(0.35 * trail * k.brace), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 1.25 * trail * k.brace));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, fA.sh, self.rest, mul(rx(-k.free), rz(sd * ARM_ABD)));
        setLocal(&wx, fA.el, self.rest, rx(-(IDLE_ELBOW + 0.45 * @abs(k.free))));
        setLocal(&wx, fA.wr, self.rest, rl.math.matrixIdentity());
        setLocal(&wx, sA.sh, self.rest, mul3(rx(-k.sh), ry(lat * k.sweep), rz(sd * (-ARM_ABD - k.abd))));
        setLocal(&wx, sA.el, self.rest, rx(-k.elbow));
        setLocal(&wx, sA.wr, self.rest, mul(ry(lat * k.roll), rx(k.wrist)));
        placeSword(&wx, self.rest, rx(k.grip), sd < 0);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseLight(self: *Hero) void {
        // OFF `atkHeavy`, NOT A CONSTANT: `poseAttack` picks by STROKE, so a class mapping `.slash` to its R2 would divide the heavy clock by the light duration.
        const u = mathx.clampF(self.atkT / self.atkDur(self.atkHeavy), 0, 1);
        const rec = 1.0 - mathx.smoothstep(AL_RECOV_A, 1.0, u);
        const wind = mathx.smoothstep(0, AL_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AL_STRIKE_A, AL_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_STRIKE_B + AL_LAG, u) * rec;
        const sElb = mathx.smoothstep(AL_WIND_B, AL_HIT_A + 0.04, u) * rec;
        const sWr = mathx.smoothstep(AL_STRIKE_A + 2 * AL_LAG, AL_STRIKE_B + 2 * AL_LAG, u) * rec;
        const sw: f32 = if (self.atkAlt) -1.0 else 1.0;
        const amp: f32 = if (self.atkAlt) 0.8 else 1.0;
        const sA = armSide(self.meleeLeft(), false);
        const fA = armSide(!self.meleeLeft(), false);
        const sd = sA.mirror;

        const os = AL_OVER * bump(u, AL_STRIKE_B + 2 * AL_LAG, AL_RECOV_A + 0.15);
        const yawP = sd * sw * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sPelv);
        const yawC = sd * sw * (1.35 * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sChest) + os);
        const crunch = AL_SPINE_CRUNCH * sChest;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yawP),
            mul(tr(0, hipY - (AL_LOAD * wind + AL_DIP * sPelv), 0), mul(rx(1.5 * sChest), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(crunch + self.aimLean * 0.5), ry(TRUNK_YAW_SPINE * yawC)));
        setLocal(&wx, CHEST, self.rest, mul(rx(crunch + self.aimLean * 0.5), ry(TRUNK_YAW_CHEST * yawC)));
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
        setLocal(&wx, fA.sh, self.rest, mul(rx(-10.0 * wind + 24.0 * sChest), rz(sd * ARM_ABD)));
        setLocal(&wx, fA.el, self.rest, rx(-(IDLE_ELBOW + 12.0 * wind)));
        setLocal(&wx, fA.wr, self.rest, rl.math.matrixIdentity());
        const windAmp: f32 = if (self.atkAlt) AL_ALT_WIND else 1.0;
        const sRaise = mathx.smoothstep(AL_WIND_B - 0.06, AL_HIT_A - 0.02, u) * rec;
        const elev = AL_SH_ELEV_WIND * wind + (AL_SH_ELEV - AL_SH_ELEV_WIND) * sRaise;
        const sSweep = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_HIT_B - 0.01, u) * rec;
        const back = AL_SWEEP_WIND * windAmp;
        const sweep = sw * (-back * wind + (back + AL_SWEEP_END) * sSweep + 0.9 * os);
        setLocal(&wx, sA.sh, self.rest, mul3(rx(-elev), ry(sd * sweep), rz(sd * (-ARM_ABD - 10.0 * amp * wind))));
        const elb = IDLE_ELBOW + (AL_ELBOW_WIND - IDLE_ELBOW) * wind - (AL_ELBOW_WIND - AL_ELBOW_STRIKE) * sElb;
        setLocal(&wx, sA.el, self.rest, rx(-elb));
        const lvl = mathx.smoothstep(0.05, AL_STRIKE_A, u) * rec;
        const lay = sw * (AL_WRIST_LAY * wind - (AL_WRIST_LAY + AL_WRIST_WHIP) * sWr);
        setLocal(&wx, sA.wr, self.rest, mul3(ry(sd * sw * AL_EDGE_ROLL * lvl), rx(-AL_TIP_UP * lvl), rz(sd * lay)));
        placeSword(&wx, self.rest, rx(GRIP_PITCH * lvl), sd < 0);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseHeavy(self: *Hero) void {
        const u = mathx.clampF(self.atkT / self.atkDur(self.atkHeavy), 0, 1);
        const rec = 1.0 - mathx.smoothstep(AH_RECOV_A, 1.0, u);
        const wind = mathx.smoothstep(0, AH_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AH_STRIKE_A, AH_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AH_STRIKE_A + AH_LAG, AH_STRIKE_B + AH_LAG, u) * rec;
        const sSh = mathx.smoothstep(AH_STRIKE_A + 2 * AH_LAG, AH_STRIKE_B + 2 * AH_LAG, u) * rec;
        const sElb = mathx.smoothstep(AH_STRIKE_A + 3 * AH_LAG, AH_STRIKE_B + 3 * AH_LAG, u) * rec;
        const sWr = mathx.smoothstep(AH_STRIKE_A + 4 * AH_LAG, AH_STRIKE_B + 4 * AH_LAG, u) * rec;

        const gather = mathx.smoothstep(AH_WIND_B - 0.05, AH_STRIKE_A + 2 * AH_LAG, u) * (1.0 - sSh) * rec;
        const rcl = bump(u, AH_STRIKE_B + 2 * AH_LAG, AH_RECOV_A) * rec;
        const sA = armSide(self.meleeLeft(), false);
        const fA = armSide(!self.meleeLeft(), false);
        const sd = sA.mirror;

        const yaw = sd * (-AH_BODY_YAW * wind + 2.0 * AH_BODY_YAW * sPelv);
        const spineX = -AH_LEAN_BACK * wind + (AH_LEAN_BACK + AH_SPINE_CRUNCH) * sChest;
        const tilt = -AH_SPINE_TILT * wind + 1.5 * AH_SPINE_TILT * sChest;
        const dip = (AH_LOAD * wind + (AH_DIP - AH_LOAD) * sPelv) - 0.008 * H * rcl;
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
        setLocal(&wx, fA.sh, self.rest, mul(rx(-22.0 * wind + 30.0 * sChest), rz(sd * (ARM_ABD + 6.0 * wind))));
        setLocal(&wx, fA.el, self.rest, rx(-(IDLE_ELBOW + 16.0 * wind)));
        setLocal(&wx, fA.wr, self.rest, rl.math.matrixIdentity());
        const up = AH_SH_UP;
        const shX = -up * wind - AH_GATHER * gather + (up - AH_SH_DOWN) * sSh + AH_RECOIL * rcl;
        setLocal(&wx, sA.sh, self.rest, mul(rx(shX), rz(sd * (-ARM_ABD - 8.0 * wind))));
        const elb = IDLE_ELBOW + (AH_ELBOW_WIND - IDLE_ELBOW) * wind + 5.0 * gather - (AH_ELBOW_WIND - AH_ELBOW_STRIKE) * sElb;
        setLocal(&wx, sA.el, self.rest, rx(-elb));
        setLocal(&wx, sA.wr, self.rest, rx(AH_WRIST_COCK * wind - (AH_WRIST_COCK + AH_WRIST_SNAP) * sWr + 8.0 * rcl));
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

        const shRz = rod.mirror * mathx.lerpF(ARM_ABD + WAND_CARRY.abd, CAST_LIFT_ABD, wind);
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
        setLocal(&wx, SPINE, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), ry(TRUNK_YAW_SPINE * yaw)));
        setLocal(&wx, CHEST, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), ry(TRUNK_YAW_CHEST * yaw)));
        setLocal(&wx, NECK, self.rest, rx(-0.35 * spineX));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK + CAST_HEAD * sThrow + BREATH_HEAD * bOn), ry(-0.4 * yaw)));
        setLocal(&wx, HIPL, self.rest, mul(rx(-6.0 * wind - 4.0 * sThrow), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 12.0 * wind + 4.0 * sThrow));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(4.0 * wind + 3.0 * sThrow), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 9.0 * wind + 3.0 * sThrow));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        const elb = mathx.lerpF(WAND_CARRY.elbow, CAST_ELBOW, wind) - CAST_ELBOW_SNAP * sThrow + 6.0 * kick -
            BREATH_REACH * bOn + 0.5 * BREATH_REACH * bOut + shiver;
        setLocal(&wx, rod.sh, self.rest, mul3(rx(-(mathx.lerpF(WAND_CARRY.flex, CAST_SH_FWD, wind) - BREATH_SH_LEVEL * bOn)), ry(shRy), rz(shRz)));
        setLocal(&wx, rod.el, self.rest, rx(-elb));
        setLocal(&wx, rod.wr, self.rest, rz(rod.mirror * (mathx.lerpF(WAND_CARRY.wrist, CAST_WRIST, wind) - 1.5 * CAST_WRIST * sThrow - 8.0 * kick + 1.6 * shiver)));
        setLocal(&wx, free.sh, self.rest, mul(rx(GUARD_SWORD_BACK * wind), rz(free.mirror * -ARM_ABD)));
        setLocal(&wx, free.el, self.rest, rx(-(IDLE_ELBOW + (GUARD_SWORD_ELBOW - IDLE_ELBOW) * wind)));
        setLocal(&wx, free.wr, self.rest, rx(GUARD_SWORD_WRIST * wind));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
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
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
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
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
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
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
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
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.meleeLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// `lit` is FALSE in the depth pass (`game.drawCasters` runs this twice). **A FIRE MAY NOT CAST A SHADOW**:
    /// the flame is real geometry 0.45 m off his axis, and at the ortho box's 13 mm a texel it laid a 23-texel blob beside him.
    pub fn draw(self: *const Hero, lit: bool) void {
        const stowSword = self.resting or self.meleeArm() == null;
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
            _ = self.drawHand(self.off, false, lit);
            return;
        }
        if (self.drawHand(self.arm, false, lit)) return;
        if (self.offInHand()) _ = self.drawHand(self.off, true, lit);
    }

    fn drawHand(self: *const Hero, a: Armament, left: bool, lit: bool) bool {
        const wrist = self.xf[if (left) WRL else WRR];
        const grip = gripFrame(wrist, self.rest, left);
        switch (a) {
            // All three melee classes are drawn at `xf[SWORD]` off `bladeMesh`, so there is nothing for this hand to hang.
            .sword, .dagger, .club => {},
            .bow => {
                rl.drawMesh(self.bow, self.mat, grip);
                for (self.stringXf) |sm| rl.drawMesh(self.bowString, self.mat, sm);
                if (self.nockVis) rl.drawMesh(self.bowNock, self.mat, self.nockXf);
                return true;
            },
            .bell => rl.drawMesh(self.bell, self.mat, grip),
            .shield => rl.drawMesh(self.shield, self.mat, mul(shieldFit(left), wrist)),
            .wand => rl.drawMesh(self.wand, self.mat, wrist),
            .torch => {
                rl.drawMesh(self.torch, self.mat, wrist);
                if (lit) {
                    const at = self.torchFlameWorld();
                    rl.drawMesh(self.torchFlame, self.mat, tr(at.x, at.y, at.z));
                }
            },
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

/// **A POLE IS AUTHORED POINTING UP OFF THE GRIP** (the warriors' kit convention), so the fit FLIPS it. After
/// this a caster's `tilt` is degrees the head leads FORWARD of plumb in the WORLD, and the fit bills the ARM
/// and never the trunk, so a pose that arches the spine pays for it in its own tilt.
pub fn staffFit(tilt: f32) rl.Matrix {
    return mul(ry(180.0), rx(180.0 - tilt));
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

/// **`groundY` IS THE ACTOR'S OWN `pos.y`, NEVER A CONSTANT.** The plane the sole is driven to is the ground
/// UNDER THIS BODY; with a world-space zero the IK asks for the hip's height above sea level, so on sculpted
/// terrain every leg is solved for the wrong span — folded to nothing in a dug basin, locked straight on a rise.
pub fn legChain(wx: []rl.Matrix, rest: []const rl.Vector3, groundY: f32, ph: f32, m: f32, runB: f32, sag: f32, lat: f32, side: f32, hip: usize, knee: usize, sole: SolePatch) void {
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
    const vert = mathx.maxF(0.1 * legLen, (hipW.y - groundY) / rootS - rest[ank].y - clear);
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
        if (deepest >= groundY) break;
        // MEASURED horizontally, not off the foot's length: a steeply pitched foot has most of that length pointing DOWN.
        const ankW = rl.math.vector3Transform(v3(0, 0, 0), wx[ank]);
        const lever = mathx.maxF(0.02 * wscale, mathx.lenXZ(mathx.subV(worst, ankW)));
        const step = mathx.degrees(std.math.asin(mathx.clampF((groundY - deepest) / lever, -1, 1)));
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
/// A fillet costs a box 6 quads → segs×sides, so the tessellation is sized to the part's largest dimension in units of stature.
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

/// Ground out of a kobold's tooth (`item.describe`), so the blade is BONE. The visible point is at t 0.28 where the capsule reaches 0.37.
fn daggerMesh() rl.Mesh {
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
    b.setMat(.plain);
    b.addCylinder(bladeAt(0.040), bladeAt(0.170), 0.0185 * H, 0.0125 * H, 5, art.BONE);
    b.addCylinder(bladeAt(0.170), bladeAt(0.280), 0.0125 * H, 0.0008 * H, 5, art.BONE);
    return b.toMesh();
}

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

/// `u` is 0 at the shoulder, 1 at the mouth. The exponent IS the bell: under 1 it bulges like a pot, at 1 it is a cone, past ~1.5 it tucks in then throws out to the rim.
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
    // PER SEGMENT — the total arc is `curl` × the segment count. BRACKETED BOTH SIDES: at 0.03–0.065 they read
    // as grave markers, far past this as croquet hoops.
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
    // Barely proud of the rod it bands: at 1.15 of the shaft radius the pair read as a lampshade.
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

fn torchMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x70C48);
    const segs = 4;
    b.setMat(.wood);
    var prev = torchAt(-TORCH_BUTT_T);
    var i: i32 = 0;
    while (i < segs) : (i += 1) {
        const f0 = @as(f32, @floatFromInt(i)) / @as(f32, segs);
        const f1 = (@as(f32, @floatFromInt(i)) + 1.0) / @as(f32, segs);
        const to = torchAt(mathx.lerpF(-TORCH_BUTT_T, TORCH_TIP_T - 0.030, f1));
        const r0 = TORCH_R * mathx.lerpF(0.90, 1.14, f0) * rng.range(0.95, 1.05);
        const r1 = TORCH_R * mathx.lerpF(0.90, 1.14, f1) * rng.range(0.95, 1.05);
        b.addCapsule(prev, to, r0, r1, 7, if (@mod(i, 2) == 0) TORCH_HAFT else TORCH_HAFT_LT);
        prev = to;
    }
    b.setMat(.leather);
    const turns = 5;
    var t: i32 = 0;
    while (t < turns) : (t += 1) {
        const f0 = -0.038 + 0.086 * (@as(f32, @floatFromInt(t)) + 0.12) / @as(f32, turns);
        const f1 = -0.038 + 0.086 * (@as(f32, @floatFromInt(t)) + 0.88) / @as(f32, turns);
        const rr = TORCH_R * rng.range(1.16, 1.30);
        b.addCapsule(torchAt(f0), torchAt(f1), rr, rr, 8, WAND_BIND);
    }
    b.setMat(.steel);
    const collar = torchAt(TORCH_TIP_T - 0.055);
    b.addCapsule(torchAt(TORCH_TIP_T - 0.074), collar, TORCH_R * 1.20, TORCH_R * 1.10, 8, art.IRON);
    b.setMat(.cloth);
    const head = torchAt(TORCH_TIP_T);
    b.addBlob(head, v3(TORCH_HEAD_R, TORCH_HEAD_R * 1.24, TORCH_HEAD_R), 4, 9, TORCH_PITCHWAD);
    var c: i32 = 0;
    while (c < 3) : (c += 1) {
        const f = TORCH_TIP_T - 0.046 + 0.020 * @as(f32, @floatFromInt(c));
        const rr = TORCH_HEAD_R * mathx.lerpF(0.72, 0.98, @as(f32, @floatFromInt(c)) / 2.0);
        b.addCapsule(torchAt(f - 0.004), torchAt(f + 0.004), rr, rr, 8, WAND_BIND);
    }
    return b.toMesh();
}

/// **DRAWN IN WORLD SPACE, NOT ON THE WRIST.** The shader's flame billow (`shaders.sceneVS`, mat 11) throws
/// along the MODEL's +Y, so hung off the wrist it would lash sideways every time he turned his arm over.
fn torchFlameMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x70C49);
    art.flameInto(&b, &rng, 0, 0, 0, TORCH_FLAME_S);
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
        .torch = undefined,
        .torchFlame = undefined,
        .dagger = undefined,
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
    // **AND DYING DOES NOT GIVE THEM BACK** (owner: found or bought, never granted). This asserted a refill, so
    // the cheapest way to restock was to walk into something — the whole arrow economy for one death.
    h.respawnNow();
    try std.testing.expectEqual(@as(u8, 0), h.quiver.ready());
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
    // …and a death leaves the dry bank dry. The FLASKS come back; the arrows do not.
    h.respawnNow();
    try std.testing.expectEqual(@as(u8, 0), h.quiver.count(.fire));
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.count(.plain));
    try std.testing.expectEqual(combat.FLASK_CRIMSON, h.flasks.charges(.crimson));
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
    // The camera's boom rides `aimB` (AIM_DIST 0.7 against a 4.6 zoom), so zeroing it inside `dropAim` cut the eye four metres in ONE frame.
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

test "A LARGE SLAM TAKES HIM OFF HIS FEET — measured: the apex, the airtime, the throw, and the landing" {
    var h = testHero();
    h.vit.hpMax = 900;
    h.vit.hp = 900;
    const slam = combat.Hit{ .dmg = 20, .poise = 60, .launch = combat.SLAM_LAUNCH };
    h.startAttack(.light);
    try std.testing.expect(h.attacking);
    const from = mathx.ground(0, 2.0); // in front of him at yaw 0, so he is thrown toward -Z
    const was = h.pos;
    try std.testing.expectEqual(combat.HitOutcome.taken, h.takeHit(slam, mathx.dirXZ(h.pos, from)));
    try std.testing.expect(!h.attacking);
    try std.testing.expect(h.airborne());
    try std.testing.expect(!h.staggered()); // …and NOT stunned on the way up, or he would never leave the ground

    const dt: f32 = 1.0 / 120.0;
    var apex: f32 = 0;
    var air: f32 = 0;
    while (h.airborne()) : (air += dt) {
        const dir = mathx.headingDir(h.airYaw);
        mathx.stepXZ(&h.pos, dir, h.airSpeed * dt, 200.0);
        h.updateAir(dt, 0);
        apex = mathx.maxF(apex, h.lift);
        try std.testing.expect(air < 3.0);
    }
    const thrown = mathx.distXZ(was, h.pos);
    std.debug.print("\n  slam launch: apex {d:.2} m (authored {d:.2}), {d:.2} s of air, thrown {d:.2} m (authored {d:.2})\n", .{ apex, combat.SLAM_LAUNCH, air, thrown, LAUNCH_BACK });
    try std.testing.expectApproxEqAbs(combat.SLAM_LAUNCH, apex, 0.05);
    try std.testing.expectApproxEqAbs(LAUNCH_BACK, thrown, 0.12);
    try std.testing.expect(h.pos.z < was.z - 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.facing, 1e-4);
    try std.testing.expect(h.staggered());
    // The LIGHT stun: the flight already was the reaction, so the whole throw costs about what the heavy stagger it replaces did (0.66 + 0.46 against 1.15).
    try std.testing.expectEqual(combat.StunKind.light, h.stun);
    const whole = air + combat.heroStunDur(false);
    std.debug.print("  …the whole throw costs {d:.2} s, against a plain heavy stagger's {d:.2} s\n", .{ whole, combat.HEAVY_STUN_DUR });
    try std.testing.expect(whole < combat.HEAVY_STUN_DUR * 1.15);

    var g2 = testHero();
    _ = g2.startLaunch(mathx.headingDir(std.math.pi), combat.SLAM_LAUNCH);
    const yaw = g2.airYaw;
    g2.steerAir(0.5, mathx.headingDir(1.2));
    try std.testing.expectApproxEqAbs(yaw, g2.airYaw, 1e-6);

    var flat = testHero();
    _ = flat.takeHit(.{ .dmg = 20, .poise = 60 }, mathx.ground(0, 1));
    try std.testing.expect(!flat.airborne());
    try std.testing.expect(flat.staggered());
}

test "A STOPPED WORLD BEATS THE THROW — no launch on a held frame, or it hangs in the air until the world runs" {
    // `tickAir` refuses to integrate while `held`, so a launch granted here would never land.
    var h = testHero();
    h.held = true;
    try std.testing.expect(!h.startLaunch(mathx.headingDir(std.math.pi), combat.SLAM_LAUNCH));
    try std.testing.expect(!h.airborne());
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


/// `updateAir` minus the TRAVEL, which is `game.moveHeroAir`'s and needs an Env.
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
    // Semi-implicit Euler's error is O(g·dt²) — 9 mm at 30 fps and nothing above it. Measured in FRAMES it would be a hero who jumps higher on a better machine.
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

test "THE BRAND IS HELD CLEAR OF HIM — the flame's own height, reach and stand-off from the head" {
    var h = testHero();
    try std.testing.expect(h.equip(LEFT, 0, .torch));
    try std.testing.expect(h.torchOut() and h.torchLeft());
    // Past the swap's own cross-fade, or this measures the pose he is blending OUT of (the arm still hanging).
    h.blendT = mathx.LONG_AGO;
    h.pose();

    const wrist = h.xf[WRL];
    const at = h.torchFlameWorld();
    const foot = rl.math.vector3Transform(torchAt(0), wrist);
    const tip = rl.math.vector3Transform(torchAt(TORCH_TIP_T), wrist);
    const head = v3(h.xf[HEAD].m12, h.xf[HEAD].m13, h.xf[HEAD].m14);
    const side = @abs(at.x - h.pos.x);
    const fwd = at.z - h.pos.z;
    const off = mathx.lenV(mathx.subV(at, head));
    const rise = mathx.subV(tip, foot);
    const plumb = rise.y / mathx.lenV(rise);
    std.debug.print(
        "\n  torch flame: {d:.2} m up (crown {d:.2}), {d:.2} m to the side, {d:.2} m in front, {d:.2} m clear of the head; brand {d:.0} deg off plumb\n",
        .{ at.y, H, side, fwd, off, mathx.degrees(std.math.acos(mathx.clampF(plumb, -1, 1))) },
    );

    // THE BRAND STANDS UP: inside 25 degrees of plumb, or it reads as a club being carried, not a light.
    try std.testing.expect(plumb > 0.90);
    try std.testing.expect(at.y > H - 0.10 and at.y < H + 0.15);
    try std.testing.expect(side > 0.28 and side < 0.48);
    try std.testing.expect(fwd > 0.20 and fwd < 0.45);
    try std.testing.expect(off > 0.35);

    const lit = h.torchLight() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(at.x, lit.pos.x);
    try std.testing.expectEqual(TORCH_LIT_R, lit.radius);
    try std.testing.expect(lit.radius > WAND_LIT_CARRY_R * 3.0);
    try std.testing.expect(h.equip(LEFT, 0, .shield));
    try std.testing.expect(h.torchLight() == null);
}

test "A HAND IS A HAND, AND WHICH HAND IS THE WHOLE OF THE TRADE" {
    var h = testHero();
    h.setGuard(true);
    try std.testing.expect(h.guarding);

    try std.testing.expect(h.equip(LEFT, 0, .torch));
    h.setGuard(true);
    try std.testing.expect(!h.guarding and !h.canGuard());

    // Nothing refuses a guard for CARRYING a torch, and the docs may not say it does.
    try std.testing.expect(h.equip(LEFT, 0, .shield));
    try std.testing.expect(h.equip(RIGHT, 0, .torch));
    try std.testing.expect(h.torchOut() and !h.torchLeft());
    h.setGuard(true);
    try std.testing.expect(h.guarding and h.canGuard());
    try std.testing.expect(!armSwings(.torch));
    try std.testing.expect(wearFor(.torch) == null);
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

test "A NET TAKES THE FEET AND NOTHING ELSE — no walk, no roll, and the sword still swings" {
    var h = testHero();
    const rate = h.moveRate();
    try std.testing.expect(rate > 0);
    h.snareFor(1.35);
    try std.testing.expect(h.snared());
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.moveRate(), 1e-6);

    // A ROLL IS TRAVEL, so it is refused — and refused at the CHOOSE, without spending the stamina.
    const rolls = h.rolls;
    const stam = h.stam.cur;
    h.startRoll(v3(0, 0, 1));
    try std.testing.expectEqual(rolls, h.rolls);
    try std.testing.expect(!h.rolling);
    try std.testing.expectApproxEqAbs(stam, h.stam.cur, 1e-4);

    // …but the arms are his. Held feet is not a stun.
    try std.testing.expect(h.bodyFree());
    h.setGuard(true);
    try std.testing.expect(h.guarding);
    h.setGuard(false);

    // Longest wins: a second net over the first extends the hold, never shortens it.
    h.snareFor(0.4);
    try std.testing.expect(h.snare > 0.4);

    var t: f32 = 0;
    while (t < 1.5) : (t += 1.0 / 60.0) h.update(1.0 / 60.0, 0, 0, null);
    try std.testing.expect(!h.snared());
    try std.testing.expectApproxEqAbs(rate, h.moveRate(), 1e-4);
    std.debug.print("\n  net: {d:.2} s of held feet, then the walk comes back at {d:.2}\n", .{ @as(f32, 1.35), h.moveRate() });
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

test "CAST SPEED SHORTENS THE BREATH, IT DOES NOT SHORTEN THE POUR" {
    for ([_]f32{ 1.0, 1.18, 1.454 }) |rate| {
        var h = testHero();
        h.off = .wand;
        h.perk.castSpeed = rate;
        h.memorize(0, .rime);
        try std.testing.expect(h.requestCast());
        const dt: f32 = 1.0 / 240.0;
        var held: f32 = 0;
        var billed: f32 = 0;
        var guard: u32 = 0;
        while (h.casting and guard < 4000) : (guard += 1) {
            h.updateCast(dt, null);
            if (h.breathLive()) {
                held += dt;
                billed += h.breathDose(dt) * combat.RIME_DPS;
            }
        }
        std.debug.print("\n  cast speed {d:.3}x: breath open {d:.3} s, pours {d:.2} cold", .{ rate, held, billed });
        try std.testing.expectApproxEqAbs(combat.RIME_DUR / rate, held, 0.02);
        try std.testing.expectApproxEqAbs(combat.RIME_DUR * combat.RIME_DPS, billed, 0.4);
    }
    std.debug.print("\n", .{});
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

test "THE ROD'S RING VISITS EVERY MEMORIZED SPELL ONCE AND COMES BACK — the rack's order, not the table's" {
    var h = testHero();
    h.memorize(0, .sunder);
    h.memorize(1, .levin);
    h.memorize(2, .bolt);
    h.spell = .sunder;
    const want = [_]combat.Spell{ .levin, .bolt, .sunder };
    for (want) |w| {
        try std.testing.expect(h.cycleSpell());
        try std.testing.expectEqual(w, h.spell);
    }

    h.memorize(0, null);
    h.memorize(1, null);
    h.mem.put(2, .bolt);
    h.tidySpells();
    try std.testing.expectEqual(combat.Spell.bolt, h.spell);
    try std.testing.expect(!h.cycleSpell());
    try std.testing.expect(h.armed());
    h.memorize(2, null);
    try std.testing.expect(!h.armed());
    try std.testing.expect(!h.cycleSpell());
    h.off = .wand;
    try std.testing.expect(!h.canCast());
    try std.testing.expect(!h.requestCast());
}

test "A SORCERY IN THE RACK NEVER SITS IN TWO SLOTS, and the finger follows what it is put in" {
    var h = testHero();
    h.memorize(0, .bolt);
    h.memorize(1, .levin);
    h.spell = .levin;
    h.memorize(1, .bolt);
    try std.testing.expectEqual(combat.Spell.levin, h.mem.at(0).?);
    try std.testing.expectEqual(combat.Spell.bolt, h.mem.at(1).?);
    try std.testing.expectEqual(@as(usize, 2), h.mem.filled());
    try std.testing.expectEqual(combat.Spell.levin, h.spell);
    h.memorize(0, null);
    try std.testing.expectEqual(combat.Spell.bolt, h.spell);
    try std.testing.expect(h.armed());
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
    legChain(&wx, &rest, SOLE_Y, ph, 1.0, 0.0, 0.0, lat, side, hip, knee, sole);
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
    // 17 deg of knee lift over 13 deg of hip flex netted ~1 cm of clearance once the pelvis dip was subtracted, so the swing foot skimmed the grass.
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

/// The whole leg solve, measured at one ground height: how far the deepest sole sits under the plane the actor
/// is standing on, and how bent the knee is. Both must be the same at every elevation.
fn strafeAtGround(groundY: f32) struct { sole: f32, knee: f32 } {
    var h = testHero();
    h.pos = v3(0, groundY, 0);
    h.moving = 1;
    h.speedS = WALK_SPEED;
    h.fwdB = 0;
    h.latB = 1;
    var lowest: f32 = std.math.floatMax(f32);
    var knee: f32 = 0;
    var i: i32 = 0;
    while (i < 240) : (i += 1) {
        h.phase = @as(f32, @floatFromInt(i)) / 240.0;
        h.pose();
        lowest = mathx.minF(lowest, soleDepth(&h.xf, &BOOT_SOLE) - groundY);
        const hip = rl.math.vector3Transform(mathx.zero3, h.xf[HIPL]);
        const ank = rl.math.vector3Transform(mathx.zero3, h.xf[ANKL]);
        knee += mathx.lenV(mathx.subV(hip, ank));
    }
    return .{ .sole = lowest, .knee = knee / 240.0 };
}

test "THE LEG IK SOLVES AGAINST THE ACTOR'S OWN GROUND, not world zero — a dug basin is not mush" {
    const flat = strafeAtGround(0);
    inline for (.{ -6.0, -2.5, 1.75, 5.0 }) |y| {
        const at = strafeAtGround(y);
        try std.testing.expectApproxEqAbs(flat.sole, at.sole, 1e-3);
        try std.testing.expectApproxEqAbs(flat.knee, at.knee, 1e-3);
    }
    // …and the span the hip actually holds the ankle at is a LEG, not a folded stump.
    try std.testing.expect(flat.knee > 0.72 * LEG_LEN);
    std.debug.print("\n  strafe at any elevation: sole {d:.4} m under the plane, hip-ankle {d:.3} m of a {d:.3} m leg\n", .{ flat.sole, flat.knee, LEG_LEN });
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
    try std.testing.expect(!h.meleeLeft());
    try std.testing.expect(h.holds(.sword));
    h.pose();
    const right = h.xf[SWORD];

    h.arm = .shield;
    h.off = .sword;
    try std.testing.expect(h.meleeLeft());
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
    try std.testing.expect(!h.meleeLeft() and !h.holds(.sword));
}

fn meleeHero(a: Armament, k: ?item.Kind) Hero {
    var h = testHero();
    h.arm = a;
    h.off = .shield;
    if (k) |kind| std.debug.assert(h.wear(wearFor(a).?, kind));
    return h;
}

test "A DAGGER IS SHORTER THAN A SWORD AND A CLUB IS LONGER — the reach is the weapon's, not the rig's" {
    const fist = bladeAt(0);
    var reach: [3]f32 = undefined;
    for (BLADES, 0..) |spec, i| reach[i] = mathx.lenV(mathx.subV(bladeAt(spec.tip), fist));
    std.debug.print("\n  blade reach: sword {d:.2} m, dagger {d:.2} m, club {d:.2} m\n", .{ reach[0], reach[1], reach[2] });
    try std.testing.expect(reach[@intFromEnum(Blade.dagger)] < reach[@intFromEnum(Blade.sword)]);
    try std.testing.expect(reach[@intFromEnum(Blade.club)] > reach[@intFromEnum(Blade.sword)]);
    try std.testing.expect(bladeSpec(.dagger).r < BLADE_R and bladeSpec(.club).r > BLADE_R);

    var h = testHero();
    try std.testing.expectEqual(Blade.sword, h.heldBlade());
    h.arm = .dagger;
    try std.testing.expectEqual(Blade.dagger, h.heldBlade());
    h.arm = .club;
    try std.testing.expectEqual(Blade.club, h.heldBlade());
    h.arm = .bow;
    try std.testing.expectEqual(@as(?Armament, null), h.meleeArm());

    var club = meleeHero(.club, .greatclub);
    club.pose();
    club.updateBlade();
    var s = testHero();
    s.pose();
    s.updateBlade();
    try std.testing.expect(mathx.distXZ(club.pos, club.bladeB) > mathx.distXZ(s.pos, s.bladeB));
}

test "THE SWING IN FLIGHT KEEPS ITS OWN CAPSULE — a club taken up mid-stroke lends the sword nothing" {
    var h = testHero();
    h.startAttack(.light);
    const r = h.bladeR();
    try std.testing.expectApproxEqAbs(BLADE_R, r, 1e-6);
    h.arm = .club; // `equip` refuses mid-swing; the latch is what holds if anything reaches past it
    try std.testing.expectApproxEqAbs(r, h.bladeR(), 1e-6);
    try std.testing.expectEqual(Blade.sword, h.heldBlade());
    try std.testing.expectEqual(Stroke.slash, h.swingMove().stroke);
    h.attacking = false;
    try std.testing.expectEqual(Blade.club, h.heldBlade());
    h.startAttack(.light);
    try std.testing.expect(h.bladeR() > r);
    try std.testing.expectEqual(Stroke.sweep, h.swingMove().stroke);
}

test "ALL THREE CLASSES WORK IN EITHER HAND — the mesh, the pose and the capsule agree on which fist" {
    for ([_]Armament{ .sword, .dagger, .club }) |a| {
        var right = testHero();
        right.arm = a;
        right.off = .shield;
        var left = testHero();
        left.arm = .shield;
        left.off = a;
        try std.testing.expect(!right.meleeLeft() and left.meleeLeft());
        try std.testing.expectEqual(right.heldBlade(), left.heldBlade());

        for ([_]Attack{ .light, .heavy }) |kind| {
            for ([_]*Hero{ &right, &left }) |h| {
                h.startAttack(kind);
                h.blendT = POSE_XFADE;
                h.atkT = 0.5 * h.atkDur(kind == .heavy);
                h.pose();
                h.updateBlade();
            }
            // Asked of each hero about ITSELF — the exact form of the `wandTipWorld` failure, and the only
            // frame-independent one. Comparing the two heroes' tips is not: a thrust and a smash are on the
            // CENTRE LINE and do not mirror (`strokeTrack`).
            for ([_]*Hero{ &right, &left }) |h| {
                const own = rl.math.vector3Transform(mathx.zero3, h.xf[if (h.meleeLeft()) WRL else WRR]);
                const other = rl.math.vector3Transform(mathx.zero3, h.xf[if (h.meleeLeft()) WRR else WRL]);
                try std.testing.expect(mathx.distXZ(h.bladeA, own) < 0.5);
                try std.testing.expect(mathx.distXZ(h.bladeA, own) < mathx.distXZ(h.bladeA, other));
            }
            // The SAGITTAL half is never mirrored: both hands reach as far forward and as high. Getting `armSide`'s `mirror` wrong flips a stroke backwards.
            try std.testing.expectApproxEqAbs(right.bladeB.y, left.bladeB.y, 0.30);
            for ([_]*Hero{ &right, &left }) |h| h.attacking = false;
        }
    }
}

test "THE WEAPON HAND IS ONE HAND — a second melee class in the other cell is stowed, not dual-wielded" {
    var h = testHero();
    h.arm = .club;
    h.off = .dagger;
    try std.testing.expect(!h.offInHand());
    try std.testing.expect(h.holds(.club) and !h.holds(.dagger));
    try std.testing.expectEqual(Armament.club, h.meleeArm().?);
    try std.testing.expectEqual(Blade.club, h.heldBlade());
    try std.testing.expect(!h.meleeLeft());

    for ([_]Armament{ .sword, .dagger, .club }) |r| {
        for ([_]Armament{ .sword, .dagger, .club }) |o| {
            var t = testHero();
            t.arm = r;
            t.off = o;
            try std.testing.expectEqual(r, t.meleeArm().?);
            try std.testing.expectEqual(wearFor(r).?, swingSocket(r, o));
        }
    }

    var g = testHero();
    g.arm = .dagger;
    g.off = .shield;
    try std.testing.expect(g.offInHand() and g.holds(.shield) and g.shieldOut());
}

test "A CLASS'S ROW AND ITS WEAPON'S ROW ARE THE SAME NUMBERS — written once, in `item`" {
    try std.testing.expectEqual(item.DAGGER, item.equip(.fang_dirk).arm);
    try std.testing.expectEqual(item.CLUB, item.equip(.greatclub).arm);
    try std.testing.expectEqual(item.DAGGER, item.bareArm(.hand_dagger));
    try std.testing.expectEqual(item.CLUB, item.bareArm(.hand_club));
    const s = item.bareArm(.hand_sword);
    try std.testing.expectEqual(@as(f32, 1), s.dmg);
    try std.testing.expectEqual(@as(f32, 1), s.poise);
    try std.testing.expectEqual(@as(f32, 1), s.dur);
    try std.testing.expectEqual(@as(f32, 1), s.stam);
    try std.testing.expectEqual(item.Heft.heavy, item.CLUB.heft);
    try std.testing.expectEqual(Stroke.smash, moveOf(.club, true).stroke);
    try std.testing.expectEqual(item.Heft.light, item.DAGGER.heft);
    for ([_]Blade{ .sword, .dagger, .club }) |b| {
        const w = wearFor(switch (b) {
            .sword => Armament.sword,
            .dagger => Armament.dagger,
            .club => Armament.club,
        }).?;
        try std.testing.expectEqual(w, item.bareArm(w).slot);
        try std.testing.expectEqual(item.Reach.melee, item.bareArm(w).reach);
    }
}

test "NOTHING SWINGS AN EMPTY HAND — a press with no melee class in a fist starts no stroke" {
    var h = testHero();
    h.arm = .shield;
    h.off = .bell;
    h.startAttack(.light);
    try std.testing.expect(!h.attacking);
    h.off = .club;
    h.startAttack(.light);
    try std.testing.expect(h.attacking and h.meleeLeft());
}

test "SIX MOVES, SIX STROKES — every class's R1 and R2 is its own, and the sword's two are untouched" {
    try std.testing.expectEqual(Stroke.slash, moveOf(.sword, false).stroke);
    try std.testing.expectEqual(Stroke.chop, moveOf(.sword, true).stroke);
    try std.testing.expectEqual(@as(f32, ATK_LIGHT_DUR), moveOf(.sword, false).t.dur);
    try std.testing.expectEqual(@as(f32, AL_HIT_A), moveOf(.sword, false).t.hitA);
    try std.testing.expectEqual(@as(f32, AH_LUNGE), moveOf(.sword, true).t.lunge);
    try std.testing.expect(strokeTrack(.slash) == null and strokeTrack(.chop) == null);

    var seen = std.EnumSet(Stroke).initEmpty();
    for ([_]Blade{ .sword, .dagger, .club }) |b| {
        for ([_]bool{ false, true }) |heavy| {
            const s = moveOf(b, heavy).stroke;
            try std.testing.expect(!seen.contains(s));
            seen.insert(s);
        }
    }
    try std.testing.expectEqual(@as(usize, 6), seen.count());

    std.debug.print("\n  moveset (seconds at the row's own dial):\n", .{});
    const rows = [_]struct { a: Armament, k: ?item.Kind }{
        .{ .a = .sword, .k = null },
        .{ .a = .dagger, .k = .fang_dirk },
        .{ .a = .club, .k = .greatclub },
    };
    var lightDur: [3]f32 = undefined;
    var heavyDur: [3]f32 = undefined;
    var live: [3][2]f32 = undefined;
    for (rows, 0..) |r, i| {
        var h = meleeHero(r.a, r.k);
        inline for ([_]bool{ false, true }) |heavy| {
            const t = moveOf(bladeOf(r.a).?, heavy).t;
            const dur = h.atkDur(heavy);
            const active = (t.hitB - t.hitA) * dur;
            live[i][@intFromBool(heavy)] = active;
            if (heavy) heavyDur[i] = dur else lightDur[i] = dur;
            std.debug.print("    {s:<7} {s:<6} {s:<7} total {d:.3}  live {d:.3} at {d:.3}  step {d:.2} m\n", .{
                @tagName(r.a),
                if (heavy) "R2" else "R1",
                @tagName(moveOf(bladeOf(r.a).?, heavy).stroke),
                dur,
                active,
                t.hitA * dur,
                t.lunge,
            });
        }
    }
    try std.testing.expect(lightDur[1] < lightDur[0] and lightDur[0] < lightDur[2]);
    try std.testing.expect(heavyDur[1] < heavyDur[0] and heavyDur[0] < heavyDur[2]);
    try std.testing.expect(live[2][0] > 1.5 * live[0][0] and live[2][0] > 1.5 * live[1][1]);
    for ([_]f32{ live[0][0], live[0][1], live[1][1], live[2][0], live[2][1] }) |o| {
        try std.testing.expect(live[1][0] < o);
    }
    try std.testing.expect(moveOf(.dagger, true).t.lunge > moveOf(.sword, true).t.lunge);
    try std.testing.expect(moveOf(.dagger, true).t.lunge > 3.0 * moveOf(.dagger, false).t.lunge);
}

test "THE HANG IS REAL AND THE SMASH ARRIVES OVERHEAD — measured off the posed club, not argued" {
    var club = meleeHero(.club, .greatclub);
    club.startAttack(.heavy);
    club.blendT = POSE_XFADE; // past the cross-fade: the stroke's own pose, not a blend with an unset one
    const dur = club.atkDur(true);
    const t = moveOf(.club, true).t;

    const topA = mkAt(&SMASH_KEYS, 0.30);
    const topB = mkAt(&SMASH_KEYS, 0.38);
    try std.testing.expectApproxEqAbs(topA.sh, topB.sh, 1e-4);
    try std.testing.expectApproxEqAbs(topA.dip, topB.dip, 1e-4);
    const hang = (0.40 - 0.28) * dur;
    std.debug.print("\n  smash: hang {d:.3} s of {d:.3} s, blow at {d:.3} s\n", .{ hang, dur, t.hitA * dur });
    // A REAL HANG, BUT NOT A TELEGRAPH: ten frames of a motionless club, not twenty-two.
    try std.testing.expect(hang > 0.14 and hang < 0.24);

    club.atkT = 0.40 * dur;
    club.pose();
    club.updateBlade();
    const overhead = club.bladeB.y;
    const crown = club.pos.y + H;

    // **MEASURED ACROSS THE LIVE WINDOW, NOT AT ITS OPENING FRAME.** The capsule goes live half way down, so
    // at `hitA` the club is still well overhead; the claim is a span, not a point.
    const span = tipSpan(.club, .greatclub, true, .y);
    std.debug.print("  smash tip: {d:.2} m overhead (crown {d:.2}); live window sweeps {d:.2} m -> {d:.2} m\n", .{ overhead, crown, span.hi, span.lo });
    try std.testing.expect(overhead > crown);
    try std.testing.expect(span.hi > crown);
    try std.testing.expect(span.lo < 0.45 * H);
    try std.testing.expect(span.hi - span.lo > 1.6);
}

test "A CLUB IS SWUNG LIKE ONE — it sinks the hips, the dagger does not, and the thrust goes STRAIGHT" {
    var bare = testHero();
    var club = meleeHero(.club, .greatclub);
    var dagger = meleeHero(.dagger, .fang_dirk);

    // **COMPARED AT EACH STROKE'S OWN DEEPEST FRAME, NOT AT A SHARED `u`**: the smash's midpoint is the HANG,
    // where he is RISEN onto the club. Asked at 0.5 the club came out above the sword and the claim read backwards.
    for ([_]Attack{ .light, .heavy }) |kind| {
        const heavy = kind == .heavy;
        var deep: [3]f32 = undefined;
        for ([_]*Hero{ &bare, &club, &dagger }, 0..) |h, i| {
            h.startAttack(kind);
            h.blendT = POSE_XFADE;
            deep[i] = 1e9;
            var u: f32 = 0;
            while (u <= 1.0) : (u += 0.02) {
                h.atkT = u * h.atkDur(heavy);
                h.pose();
                deep[i] = mathx.minF(deep[i], h.xf[ROOT].m13);
            }
            h.attacking = false;
        }
        std.debug.print("  deepest hip ({s}): sword {d:.3}, club {d:.3}, dagger {d:.3}\n", .{ @tagName(kind), deep[0], deep[1], deep[2] });
        try std.testing.expect(deep[1] < deep[0]);
        try std.testing.expect(deep[2] > deep[0]);
    }

    // Measured as the LATERAL drift of the tip across the live window.
    const thrustLat = tipSpan(.dagger, .fang_dirk, true, .x);
    const flickLat = tipSpan(.dagger, .fang_dirk, false, .x);
    const thrust = thrustLat.hi - thrustLat.lo;
    const flick = flickLat.hi - flickLat.lo;
    std.debug.print("  dagger tip lateral travel: thrust {d:.3} m, flick {d:.3} m\n", .{ thrust, flick });
    try std.testing.expect(thrust < 0.5 * flick);
}

/// The blade's own pitch off horizontal at a fraction of its stroke, + = the point is BELOW the grip.
fn bladePitchAt(a: Armament, k: ?item.Kind, heavy: bool, u: f32) f32 {
    var h = meleeHero(a, k);
    h.startAttack(if (heavy) .heavy else .light);
    h.blendT = POSE_XFADE;
    h.atkT = u * h.atkDur(heavy);
    h.pose();
    h.updateBlade();
    const d = mathx.subV(h.bladeB, h.bladeA);
    return mathx.degrees(std.math.atan2(-d.y, @sqrt(d.x * d.x + d.z * d.z)));
}

test "A SWEEP RUNS LEVEL AND A SMASH COMES DOWN — the blade's own pitch, not the arm's" {
    const t = moveOf(.club, false).t;
    const mid = 0.5 * (t.hitA + t.hitB);
    const sweep = bladePitchAt(.club, .greatclub, false, mid);
    const thrust = bladePitchAt(.dagger, .fang_dirk, true, 0.52);
    const smash = bladePitchAt(.club, .greatclub, true, 0.56); // the impact key, not the window's tail
    std.debug.print("\n  blade pitch (+ = point below the grip): sweep {d:.1} deg, thrust {d:.1}, smash {d:.1}\n", .{ sweep, thrust, smash });
    // **A HORIZONTAL SWING MUST BE HORIZONTAL.** At 60 deg it rakes the dirt and reads as a failed overhead (measured, the first pass).
    try std.testing.expect(@abs(sweep) < 25);
    try std.testing.expect(@abs(thrust) < 25);
    // **A 1.44 m CLUB ON A 1.3 m SHOULDER CANNOT BE BOTH VERTICAL AND ON THE GROUND**: solved, the head reaches
    // the earth with the shaft near 40 deg, and forcing it past that drove the tip 0.81 m UNDER the floor
    // (measured). The steepness claim is therefore RELATIVE — against the club's own horizontal.
    try std.testing.expect(smash > 2.0 * @abs(sweep));
    try std.testing.expect(smash > 30);
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
    try std.testing.expectEqual(Armament.shield, h.arm);
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

    // **THE TIDY MAY NOT CONJURE A WEAPON HE HAS NOT FOUND.** `.dagger` is position 1, so the first-unused-value fill handed one out on every load of a save with a duplicated cell.
    for (stale.rack()) |c| try std.testing.expect(c.* != .dagger and c.* != .club);
    try std.testing.expect(!stale.canRack(.dagger) and !stale.canRack(.club));
    try std.testing.expect(stale.canRack(.sword) and stale.canRack(.bow));

    var owns = testHero();
    owns.arm = .sword;
    owns.armAlt = .sword;
    owns.off = .sword;
    owns.offAlt = .shield;
    try std.testing.expect(owns.wear(.hand_club, .greatclub));
    try std.testing.expect(owns.canRack(.club) and !owns.canRack(.dagger));
    owns.tidyHands();
    var sawClub = false;
    for (owns.rack()) |c| {
        try std.testing.expect(c.* != .dagger);
        if (c.* == .club) sawClub = true;
    }
    try std.testing.expect(sawClub);
}

test "A SKILL REACHES THE BLOW IT GOVERNS AND NOTHING ELSE" {
    var bare = testHero();
    bare.atkHeavy = true;
    try std.testing.expectApproxEqAbs(ATK_HEAVY_HIT.dmg, bare.attackHit().dmg, 1e-4);
    bare.atkHeavy = false;
    try std.testing.expectApproxEqAbs(ATK_LIGHT_HIT.dmg, bare.attackHit().dmg, 1e-4);
    try std.testing.expectApproxEqAbs(combat.BOLT_HIT.raw(), bare.castBlow().?.raw(), 1e-3);

    var club = meleeHero(.club, .greatclub);
    var dirk = meleeHero(.dagger, .fang_dirk);
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

    var strong = meleeHero(.club, .greatclub);
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
    var club = meleeHero(.club, .greatclub);
    var dirk = meleeHero(.dagger, .fang_dirk);

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
    try std.testing.expect(!bare.wear(.hand_sword, .greatclub));
    try std.testing.expect(!bare.wear(.hand_club, .fang_dirk));
    try std.testing.expect(bare.worn.at(.chest) == null);
}

test "WHAT STARTS IS WHAT LANDS — a variant taken up mid-stroke cannot reach into the one in flight" {
    var h = testHero();
    h.startAttack(.light);
    const dur = h.atkDur(false);
    const dmg = h.attackHit().dmg;
    h.atkT = dur * 0.70;
    try std.testing.expect(!h.hitActive());
    h.arm = .club; // `equip` refuses mid-swing; this is what holds if something reaches past it

    // Read live, `atkT / dur` fell back to 0.52 of a club's longer clock — inside `AL_HIT_A`..`AL_HIT_B`, which
    // re-opens a closed window and re-arms `foe.strike`'s one-hit latch.
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

const Span = struct { lo: f32, hi: f32, mean: f32 };

/// `.y` is height, `.x` is his own LATERAL (facing is pinned to +Z). As three separate loops the step size and the endpoints were three slightly different questions.
fn tipSpan(a: Armament, k: ?item.Kind, heavy: bool, axis: enum { x, y }) Span {
    var h = meleeHero(a, k);
    h.facing = 0;
    h.startAttack(if (heavy) .heavy else .light);
    h.blendT = POSE_XFADE; // past the cross-fade: the stroke's own pose, not a blend with an unset one
    const t = moveOf(bladeOf(a).?, heavy).t;
    const dur = h.atkDur(heavy);
    var out = Span{ .lo = 1e9, .hi = -1e9, .mean = 0 };
    var n: f32 = 0;
    var u = t.hitA;
    while (u <= t.hitB) : (u += 0.01) {
        h.atkT = u * dur;
        h.pose();
        h.updateBlade();
        const v = if (axis == .x) h.bladeB.x else h.bladeB.y;
        out.lo = mathx.minF(out.lo, v);
        out.hi = mathx.maxF(out.hi, v);
        out.mean += v;
        n += 1;
    }
    out.mean /= n;
    return out;
}

/// The MEAN height across the live window — not where the arm ends up and not the highest point the tip reaches.
fn aimHeightOf(a: Armament, k: ?item.Kind, heavy: bool) f32 {
    return tipSpan(a, k, heavy, .y).mean;
}

test "EVERY STROKE AIMS AT A BODY — except the one whose target is the ground" {
    const slash = aimHeightOf(.sword, null, false);
    const flick = aimHeightOf(.dagger, .fang_dirk, false);
    const sweep = aimHeightOf(.club, .greatclub, false);
    const smash = aimHeightOf(.club, .greatclub, true);
    const thrust = aimHeightOf(.dagger, .fang_dirk, true);
    std.debug.print("\n  aim (mean tip height over the live window, H={d:.2}): slash {d:.2}, flick {d:.2}, thrust {d:.2}, sweep {d:.2}, smash {d:.2}\n", .{ H, slash, flick, thrust, sweep, smash });

    // Authored off the arm rather than off the target, the flick sat at 0.80 m and the sweep at 0.66 — both
    // raking a standing man's SHINS (measured; owner: they should aim higher with weak).
    for ([_]f32{ flick, sweep }) |aim| {
        try std.testing.expect(aim > 0.55 * H); // a torso, not a knee
        try std.testing.expect(@abs(aim - slash) < 0.35);
    }
    try std.testing.expect(thrust > 0.45 * H);
    // The smash's MEAN sits well under the club's own horizontal because the window opens overhead and closes on the earth; where it FINISHES is measured next door, at -0.01 m.
    try std.testing.expect(smash < sweep);
    try std.testing.expect(smash < 0.7 * slash);
}

test "AN ENVENOMED EDGE FILLS A BODY IN FOUR STROKES, and what it becomes is CHAOS" {
    var h = testHero();
    try std.testing.expect(h.wear(.hand_dagger, .envenomed_dagger));
    h.arm = .dagger;
    const dose = h.attackHit().dose.at(.poison);
    std.debug.print("\n  envenomed dirk: {d:.0} venom a hit, {d:.0} to fill (`combat.POISON_MAX`)\n", .{ dose, combat.POISON_MAX });
    try std.testing.expect(dose > 0);
    // The clean dirk beside it leaves nothing behind, and hits harder for it.
    var clean = testHero();
    try std.testing.expect(clean.wear(.hand_dagger, .fang_dirk));
    clean.arm = .dagger;
    try std.testing.expectApproxEqAbs(@as(f32, 0), clean.attackHit().dose.at(.poison), 1e-6);
    try std.testing.expect(clean.attackHit().dmg > h.attackHit().dmg);

    // FOUR landed strokes and the fifth frame it is running, on a body that is not the hero's.
    var body = combat.Vitals.initFoe(400, 999, 999);
    var strokes: u32 = 0;
    while (strokes < 4) : (strokes += 1) {
        _ = body.hit(h.attackHit());
        try std.testing.expect(!body.ailOn(.poison));
    }
    _ = body.tickAils(1.0 / 60.0);
    try std.testing.expect(body.ailOn(.poison));

    // …and the bite it turns into is CHAOS, so a creature's own column answers it. The brood's +75 is the cap.
    const hpWas = body.hp;
    _ = body.tickAils(1.0);
    const bare = hpWas - body.hp;
    var warded = combat.Vitals.initFoe(400, 999, 999).withRes(combat.resists(.{ .chaos = 75 }));
    strokes = 0;
    while (strokes < 4) : (strokes += 1) _ = warded.hit(h.attackHit());
    _ = warded.tickAils(1.0 / 60.0);
    const wardedWas = warded.hp;
    _ = warded.tickAils(1.0);
    const through = wardedWas - warded.hp;
    std.debug.print("  one second of it: {d:.2} HP bare, {d:.2} at 75% chaos ({d:.0}%)\n", .{ bare, through, through / bare * 100 });
    try std.testing.expectApproxEqAbs(0.25, through / bare, 0.02);
}

test "A WARD AND A COATING NAME THEIR OWN ELEMENT — and the last one wiped on is the one that is there" {
    var h = testHero();
    h.startWard(.fire, 40, 60);
    h.tickTimed(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 40), h.vit.res.raw(.fire), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.vit.res.raw(.chaos), 1e-4);
    // REFRESHED, NEVER STACKED, and a second tonic moves the whole ward rather than opening a second column.
    h.startWard(.chaos, 40, 60);
    h.tickTimed(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.vit.res.raw(.fire), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 40), h.vit.res.raw(.chaos), 1e-4);

    const dry = h.attackHit();
    try std.testing.expectApproxEqAbs(@as(f32, 0), dry.elem.total(), 1e-6);
    h.startGrease(.cold, 0.5, 60);
    const iced = h.attackHit();
    try std.testing.expectApproxEqAbs(dry.dmg * 0.5, iced.elem.at(.cold), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), iced.elem.at(.fire), 1e-6);
    h.startGrease(.fire, 0.5, 60);
    const lit = h.attackHit();
    try std.testing.expectApproxEqAbs(dry.dmg * 0.5, lit.elem.at(.fire), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), lit.elem.at(.cold), 1e-6);
    // The physical half is untouched either way: a coating is hung ON TOP of the blow.
    try std.testing.expectApproxEqAbs(dry.dmg, lit.dmg, 1e-6);
}

test "WHAT IS ON HIS FEET REACHES HOW FAST HE WALKS, and a cap reaches how fast he fills" {
    var h = testHero();
    const bare = moveRateOf(h.worn, h.perk);
    try std.testing.expect(h.wear(.feet, .spidersilk_moccasins));
    const silk = moveRateOf(h.worn, h.perk);
    std.debug.print("\n  pace: bare {d:.3}, moccasins {d:.3} (+{d:.1}%)\n", .{ bare, silk, (silk / bare - 1) * 100 });
    try std.testing.expect(silk > bare);
    // The boots beside them are the plain shoe — armour only, and the pace is the bare one.
    try std.testing.expect(h.wear(.feet, .marchboots));
    try std.testing.expectApproxEqAbs(bare, moveRateOf(h.worn, h.perk), 1e-6);

    // …and the rate a status meter fills is settled on the BODY, off the same table (`settleBody`).
    var cap = testHero();
    cap.tickTimed(1.0 / 60.0);
    const openRate = cap.vit.ailRateOf(.poison);
    try std.testing.expect(cap.wear(.helm, .sporecrown));
    cap.tickTimed(1.0 / 60.0);
    try std.testing.expect(cap.vit.ailRateOf(.poison) < openRate);
    cap.poisonBy(50);
    const slowed = cap.vit.ail(.poison).meter;
    var open = testHero();
    open.tickTimed(1.0 / 60.0);
    open.poisonBy(50);
    std.debug.print("  a 50 dose: {d:.1} open-headed, {d:.1} under the sporecrown\n", .{ open.vit.ail(.poison).meter, slowed });
    try std.testing.expect(slowed < open.vit.ail(.poison).meter);
}

test "DEATH PUTS HIM BACK WHERE HE LAST SAT DOWN — the stamped spawn, not the spot the map was entered at" {
    var h = testHero();
    const entry = mathx.ground(0, 4);
    h.setSpawn(entry, std.math.pi);

    // The fire he sat at (`game.tickRest` stamps the seat), a long way from the entry.
    const fire = mathx.ground(-38.5, 61.25);
    h.setSpawn(fire, 1.25);
    h.pos = v3(12, 0, -3);
    h.vit.hp = 1;
    h.poisonBy(combat.POISON_MAX);
    try std.testing.expect(h.vit.ailFrac(.poison) > 0.9);
    _ = h.takeHit(.{ .dmg = 999 }, v3(1, 0, 0));
    try std.testing.expect(h.dead);
    var t: f32 = 0;
    while (t < DEATH_DUR + 0.1) : (t += 1.0 / 60.0) h.updateDeath(1.0 / 60.0);
    try std.testing.expect(!h.dead);
    try std.testing.expectApproxEqAbs(fire.x, h.pos.x, 1e-4);
    try std.testing.expectApproxEqAbs(fire.z, h.pos.z, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), h.facing, 1e-4);
    try std.testing.expect(mathx.distXZ(h.pos, entry) > 60);
    // He comes back WHOLE, and nothing he was carrying in his blood comes back with him.
    try std.testing.expectApproxEqAbs(h.vit.hpMax, h.vit.hp, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.vit.ailFrac(.poison), 1e-6);
}
