const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const elemfx = @import("../gfx/elemfx.zig");
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
const setLocal = heromod.setHumanoid;

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
const ORB = heromod.HELD;

const H: f32 = heromod.H;

pub const SCALE = (H + 0.65) / H;
const HIP_HALF = heromod.HIP_HALF * 0.82;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.86;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
const solePatches = archermod.solePatches;

const ROBE = rgba(31, 36, 24, 255);
const ROBE_LT = rgba(43, 50, 31, 255);
const ROBE_DK = rgba(19, 23, 15, 255);
const HEM = rgba(15, 18, 12, 255);
const ROT = rgba(56, 44, 22, 255);
const CORD = rgba(64, 52, 34, 255);
const SKIN = rgba(70, 58, 44, 255);
const SKIN_DK = rgba(48, 40, 30, 255);
const HAIR = rgba(30, 26, 20, 255);
const ORB_SHELL = rgba(20, 10, 24, 255);
const ORB_VEIN = rgba(58, 22, 64, 255);
const CHAOS_CORE = elemfx.sig(.chaos).core;
const CHAOS_EDGE = elemfx.sig(.chaos).edge;
const EYE = mathx.withAlpha(CHAOS_CORE, 120);
// Drawn with primitives, so these are SCREEN values and not albedos.
const VINE = rgba(62, 74, 40, 255);
const VINE_DK = rgba(38, 46, 26, 255);
const VINE_TIP = mathx.withAlpha(CHAOS_EDGE, 255);
const LAND_DUST = foe.Spray{
    .fanLo = 0.6,  .fanHi = 2.4,
    .upLo = 0.2,   .upHi = 0.9,
    .lifeLo = 0.40, .lifeHi = 0.80,
    .rLo = 0.06,   .rHi = 0.14,
    .r1 = 0.22,    .col = foe.DUST, .grav = 0.6,
    .col1 = foe.DUST_THIN, .drag = 2.2,
};
const LEAF_SPRAY = foe.Spray{
    .fanLo = 0.4,  .fanHi = 1.8,
    .upLo = 0.6,   .upHi = 2.6,
    .lifeLo = 0.35, .lifeHi = 0.70,
    .rLo = 0.018,  .rHi = 0.040,
    .r1 = 0.008,   .col = rgba(66, 78, 40, 235), .grav = 5.0,
    .col1 = rgba(40, 32, 18, 200), .stretch = 0.02, .drag = 1.4,
};

pub const AGGRO_R_BANK: f32 = 24.0;
pub var AGGRO_R: f32 = AGGRO_R_BANK;
const TURN_RATE = 3.6;
const WALK_SPEED = heromod.WALK_SPEED_BANK * 0.95;
const BODY_R = 0.42;
const HURT_R = 0.56;
pub var SOULS: u32 = 2400;

const HP_MAX: f32 = 1050.0;
const POISE_MAX: f32 = 46.0;
const STANCE_MAX: f32 = 120.0;
/// Owner: weak to FIRE, somewhat to ICE (not as much), strong against CHAOS.
const RESISTS = combat.resists(.{ .fire = -50, .cold = -25, .chaos = 75 });

/// OWNER: ALL OF HER DAMAGE IS PHYSICAL, but the whips, which cut — physical AND chaos, and the chaos is corruption, not venom (`Hit.venom` off). The whips and the spear open him: both BUILD BLEED.
const WHIP_BLEED: f32 = 22.0;
const SPEAR_BLEED: f32 = 36.0;
pub var WHIP_HIT = combat.Hit{ .dmg = 15, .poise = 20, .stance = 6, .elem = combat.elems(.{ .chaos = 8 }), .dose = combat.Doses.one(.bleed, WHIP_BLEED) };
pub var SNARE_HIT = combat.Hit{ .dmg = 6, .poise = 26, .stance = 8 };
/// How long the vines hold his feet — under two of the whip's periods, so a snare is one lash taken and one dodged.
pub const SNARE_HOLD: f32 = 1.6;
/// …AND THEY BITE WHILE THEY HOLD: a physical pulse every `SNARE_PULSE_EVERY` through the hold, no poise (the knight's gas pattern, `Coven.holdDose`).
pub const SNARE_PULSE_EVERY: f32 = 0.4;
pub var SNARE_PULSE_HIT = combat.Hit{ .dmg = 3 };

const DEATH_DUR = 1.4;
const DISS_DUR = 1.0;
const DISSOLVE = foe.Dissolve{ .rate = 60.0, .spread = 0.95, .rise = 0.8, .flake = rgba(58, 66, 36, 255) };
const SHOVE_DECAY = 6.0;
const A_PROT = 3.0;

/// Water deeper than this is not ground she will land on or walk into — ankle deep and no more.
pub const DRY_MAX: f32 = 0.3;

/// THE RING SHE WANTS YOU IN. Inside `LEAP_R` she leaps clear; between the two she casts and drifts sideways.
const KEEP_MIN: f32 = 7.0;
const KEEP_MAX: f32 = 13.0;
const DRIFT_DUR: f32 = 0.8;
const LEAP_R: f32 = 4.6;
/// Seconds from TAKE-OFF to the next leap she may throw — armed the frame she leaves the ground, so a leap cut short by a stagger is still a leap spent.
pub const LEAP_CD: f32 = 14.0;
/// A rush inside this ring is answered with a sidestep — RUSH being closing speed off his position over the last frame, never his press.
const STEP_R: f32 = 3.4;
const STEP_CLOSE: f32 = 1.2;
const STEP_DIST: f32 = 2.4;
const STEP_DUR: f32 = 0.30;
const STEP_CD: f32 = 4.5;

const VINE_WIND: f32 = 0.90;
const VINE_CAST: f32 = 0.26;
const VINE_CD: f32 = 5.5;
pub const SNARE_R: f32 = 1.55;
/// It is shown before it bites: the ring of buds stands this long, then withers.
pub const SNARE_SHOW: f32 = 2.2;
const CAST_MIN: f32 = 3.0;
const CAST_MAX: f32 = 16.0;

const WHIP_WIND: f32 = 0.72;
const WHIP_CAST: f32 = 0.22;
const WHIP_CD: f32 = 4.2;
pub const WHIP_N: usize = 3;
const WHIP_SOW_MIN: f32 = 1.3;
const WHIP_SOW_MAX: f32 = 2.4;
pub const WHIP_GROW: f32 = 0.45;
pub const WHIP_LIFE: f32 = 5.5;
pub const WHIP_PERIOD: f32 = 1.15;
/// The rear-back before each lash. Over `foe.TELL_MIN`, and under the roll's i-frames so the lash is a thing you roll.
pub const WHIP_TELL: f32 = 0.36;
pub const WHIP_REACH: f32 = 2.3;
/// HALF-angle either side of where the stalk points (`foe.inArc` takes a half-width): a 110-degree cone.
const WHIP_ARC: f32 = 55.0;
const WHIP_TURN: f32 = 2.4;
pub const WITHER: f32 = 0.6;
const WHIP_H: f32 = 2.6;

/// THE SPEAR IS THE ANSWER TO CLOSING: a rush inside `SPEAR_R` (his position over the last frame, never his press). The wind is the TELL and it is long for a punish, and SHE is the tell — the coil, the arm hauled back, the hand pointing down the line — then the tip runs `SPEAR_LEN` in `SPEAR_STRIKE`.
const SPEAR_R: f32 = 6.5;
const SPEAR_MIN: f32 = 1.6;
const SPEAR_CLOSE: f32 = 1.0;
pub const SPEAR_WIND: f32 = 0.62;
pub const SPEAR_STRIKE: f32 = 0.20;
const SPEAR_RECOVER: f32 = 0.45;
const SPEAR_CD: f32 = 3.5;
pub const SPEAR_LEN: f32 = 6.5;
pub const SPEAR_HALF_W: f32 = 0.42;
pub const SPEAR_HOLD: f32 = 0.35;
const SPEAR_RISE: f32 = 0.9;
pub var SPEAR_HIT = combat.Hit{ .dmg = 20, .poise = 28, .stance = 12, .dose = combat.Doses.one(.bleed, SPEAR_BLEED) };

/// SEED PODS, SCATTERED AS SHE LEAVES: thrown from the orb as she takes off, they fly a short arc, land between her and the man, SWELL for the fuse and POP into splinters.
pub const POD_N: usize = 4;
const POD_SCATTER_MIN: f32 = 1.6;
const POD_SCATTER_MAX: f32 = 3.6;
const POD_SPREAD: f32 = 100.0;
pub const POD_FLIGHT: f32 = 0.55;
const POD_FLIGHT_UP: f32 = 1.6;
pub const POD_FUSE: f32 = 1.3;
pub const POD_R: f32 = 1.7;
const POD_R0: f32 = 0.16;
const POD_R1: f32 = 0.44;
pub var POD_HIT = combat.Hit{ .dmg = 12, .poise = 18, .stance = 6 };
const POD_SPLINTERS = 12;
const POD_BURST: usize = 8;
const SPLINTER_SPRAY = foe.Spray{
    .fanLo = 1.6,  .fanHi = 4.8,
    .upLo = 0.6,   .upHi = 3.2,
    .lifeLo = 0.25, .lifeHi = 0.55,
    .rLo = 0.012,  .rHi = 0.030,
    .r1 = 0.006,   .col = rgba(150, 138, 96, 240), .grav = 9.0,
    .col1 = rgba(96, 86, 56, 200), .stretch = 0.05, .drag = 1.0, .bounce = 0.3,
};

const RECOVER: f32 = 0.55;
const SUMMON_WIND: f32 = 1.30;
const SUMMON_CAST: f32 = 0.40;
pub const SUMMON_R: f32 = 3.2;
/// Share of max HP a second while she channels. From half, untouched, she is whole again in 15 s.
pub const HEAL_RATE: f32 = 0.035;
/// The hum take is 1.25 s; retriggered a beat inside that so it never gaps and never chatters.
const HUM_EVERY: f32 = 1.05;
pub const PHASE_HP: f32 = 0.5;

const Arc = struct { dist: f32, rise: f32, hang: f32, fall: f32, up: f32 };
/// Up fast, HANG, then down on a curve with no slope at the ground — that is landing gently.
pub const LEAP_ARC = Arc{ .dist = 9.0, .rise = 0.34, .hang = 0.62, .fall = 1.00, .up = 2.1 };
pub const RETREAT_ARC = Arc{ .dist = 15.0, .rise = 0.40, .hang = 0.75, .fall = 1.10, .up = 3.0 };

fn arcTotal(a: Arc) f32 {
    return a.rise + a.hang + a.fall;
}
fn arcHop(a: Arc, t: f32) f32 {
    if (t < a.rise) return a.up * mathx.sinf(0.5 * std.math.pi * t / a.rise);
    if (t < a.rise + a.hang) return a.up;
    const u = mathx.clampF((t - a.rise - a.hang) / a.fall, 0, 1);
    return a.up * (1.0 - mathx.smoothstep(0, 1, u));
}
/// Ground covered so far: the speed peaks mid-flight and is nothing at touchdown.
fn arcAlong(a: Arc, t: f32) f32 {
    const u = mathx.clampF(t / arcTotal(a), 0, 1);
    return a.dist * 0.5 * (1.0 - mathx.cosf(std.math.pi * u));
}

comptime {
    std.debug.assert(VINE_WIND >= foe.TELL_MIN and WHIP_WIND >= foe.TELL_MIN and SUMMON_WIND >= foe.TELL_MIN);
    std.debug.assert(WHIP_TELL >= foe.TELL_MIN and WHIP_TELL < heromod.ROLL_IFRAME_END_BANK);
    std.debug.assert(WHIP_PERIOD > WHIP_TELL);
    std.debug.assert(LEAP_R < KEEP_MIN and KEEP_MIN < KEEP_MAX and KEEP_MAX < AGGRO_R_BANK);
    std.debug.assert(STEP_R < LEAP_R);
    std.debug.assert(LEAP_CD > arcTotal(LEAP_ARC) and STEP_CD > STEP_DUR);
    std.debug.assert(SPEAR_WIND >= 2.0 * foe.TELL_MIN and SPEAR_CD > SPEAR_WIND + SPEAR_STRIKE + SPEAR_RECOVER); // a punish gets twice the floor of a tell
    std.debug.assert(SPEAR_MIN < SPEAR_R and SPEAR_R <= KEEP_MIN);
    std.debug.assert(SPEAR_LEN + SPEAR_HALF_W + foe.HERO_R > SPEAR_R); // …or the ring hands out a thrust that stops short of the man it was thrown at
    std.debug.assert(CAST_MIN < KEEP_MIN and CAST_MAX > KEEP_MAX);
    std.debug.assert(SNARE_HOLD < 2.0 * WHIP_PERIOD);
    std.debug.assert(HEAL_RATE * 15.0 >= PHASE_HP);
    std.debug.assert(LEAP_ARC.dist > LEAP_R + KEEP_MIN * 0.5);
}

const NPART = 120;
const CHIP_LIGHT = 8;
const CHIP_HEAVY = 14;
const CHIP_DEATH = 18;
const CAST_BURST: usize = 14;
const SUMMON_BURST: usize = 22;
comptime {
    std.debug.assert(NPART >= @as(usize, @intCast(foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH) + foe.WOUND_PARTS)) + elemfx.burstCount(.chaos, SUMMON_BURST));
}

pub const Wave = enum { deer, sporelings, wights, frogs };
const WAVE_N: i32 = @typeInfo(Wave).@"enum".fields.len;
pub const WAVE_MAX: u8 = 4;
pub fn waveKind(w: Wave) wf.FoeKind {
    return switch (w) {
        .deer => .fungal_deer,
        .sporelings => .shroom,
        .wights => .birchwight,
        .frogs => .toad,
    };
}
pub fn waveCount(w: Wave) u8 {
    return switch (w) {
        .deer => 2,
        .sporelings => 4,
        .wights => 3,
        .frogs => 4,
    };
}
comptime {
    for (@typeInfo(Wave).@"enum".fields) |f| std.debug.assert(waveCount(@enumFromInt(f.value)) <= WAVE_MAX);
}

const State = enum { idle, drift, vine_wind, vine_cast, whip_wind, whip_cast, spear_wind, spear_cast, leap, step, summon_wind, summon_cast, retreat, passive, recover, stunlight, stunheavy, dead };

const Choice = enum { vine, whip, keep, hold };
fn classify(dist: f32, vineReady: bool, whipReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist >= CAST_MIN and dist <= CAST_MAX) {
        if (vineReady) return .vine;
        if (whipReady) return .whip;
    }
    return .keep;
}

const TRAIL_N = 3;
const TRAIL_OFF = [TRAIL_N]f32{ -28.0, 4.0, 26.0 };
const TRAIL_LEN = [TRAIL_N]f32{ 0.82, 1.05, 0.72 };
const TRAIL_STIFF = [TRAIL_N]f32{ 32.0, 38.0, 46.0 };
const TRAIL_ZETA: f32 = 0.42;
const TRAIL_DRAG: f32 = 14.0;
const TRAIL_FLARE: f32 = 26.0;
const HEM_DRAG = 13.0;
const HEM_EASE = 6.0;
const HEM_SETTLE = 3.2;
const HEM_SWAY = 2.0;

const ORB_AT = v3(0, -0.062 * H, 0.052 * H);
const ORB_R = 0.052 * H;

// Arm channels, the necromancer's conventions: `rx(-sh)` raises an arm forward, `el` is flexion, `abd` is out from the side.
const CARRY_ORB_SH = -20.0;
const CARRY_ORB_EL = 74.0;
const CARRY_ORB_ABD = 10.0;
const CARRY_FREE_SH = -6.0;
const CARRY_FREE_EL = 22.0;
const CARRY_FREE_ABD = 8.0;
const CARRY_LEAN = 4.0;
const CARRY_HEAD = 3.0;

const WIND_ORB_SH = -86.0;
const WIND_ORB_EL = 12.0;
const WIND_ORB_ABD = 4.0;
const WIND_FREE_SH = -42.0;
const WIND_FREE_EL = 44.0;
const WIND_FREE_ABD = 46.0;
const WIND_LEAN = -7.0;
const WIND_TWIST = -18.0;
const WIND_HEAD = -6.0;

const CAST_ORB_SH = -72.0;
const CAST_ORB_EL = 34.0;
const CAST_LEAN = 12.0;
const CAST_TWIST = 10.0;
const CAST_HEAD = 10.0;

const SUMMON_ORB_SH = -156.0;
const SUMMON_ORB_EL = 12.0;
const SUMMON_ORB_ABD = 20.0;
const SUMMON_FREE_SH = -150.0;
const SUMMON_FREE_EL = 10.0;
const SUMMON_FREE_ABD = 24.0;
const SUMMON_LEAN = -16.0;
const SUMMON_HEAD = -22.0;
const THROW_ORB_SH = -62.0;
const THROW_ORB_ABD = 58.0;
const THROW_FREE_SH = -62.0;
const THROW_FREE_ABD = 58.0;
const THROW_LEAN = 12.0;

// THE COIL IS THE TELL: the orb hand hauled right back past the shoulder and high, the trunk reared and wound away from him, the head down — and the free arm POINTING STRAIGHT DOWN THE LINE the whole wind. Then the whole body unwinds into the thrust.
const SPEAR_WIND_ORB_SH = 48.0;
const SPEAR_WIND_ORB_EL = 96.0;
const SPEAR_WIND_ORB_ABD = 34.0;
const SPEAR_WIND_FREE_SH = -90.0;
const SPEAR_WIND_FREE_EL = 4.0;
const SPEAR_WIND_FREE_ABD = 2.0;
const SPEAR_WIND_LEAN = -20.0;
const SPEAR_WIND_TWIST = -44.0;
const SPEAR_WIND_HEAD = 14.0;
const SPEAR_THRUST_ORB_SH = -74.0;
const SPEAR_THRUST_ORB_EL = 0.0;
const SPEAR_THRUST_ORB_ABD = 6.0;
const SPEAR_THRUST_FREE_SH = 30.0;
const SPEAR_THRUST_FREE_ABD = 40.0;
const SPEAR_THRUST_LEAN = 30.0;
const SPEAR_THRUST_TWIST = 22.0;
const SPEAR_THRUST_HEAD = -6.0;

const PASSIVE_ORB_SH = -168.0;
const PASSIVE_ORB_EL = 4.0;
const PASSIVE_ORB_ABD = 6.0;
const PASSIVE_FREE_SH = -30.0;
const PASSIVE_FREE_EL = 40.0;
const PASSIVE_FREE_ABD = 34.0;
const PASSIVE_LEAN = -10.0;
const PASSIVE_HEAD = -18.0;

const LEAP_SH = -56.0;
const LEAP_EL = 20.0;
const LEAP_ABD = 56.0;
const LEAP_LEAN = -10.0;
const LEAP_HEAD = 4.0;

const STEP_LEAN_SIDE = 12.0;

fn easeTo(cur: f32, target: f32, e: f32) f32 {
    return lerpF(cur, target, mathx.clampF(e, 0, 1));
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    hem: rl.Mesh,
    trail: [TRAIL_N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "druidess");
        var bone: [N]rl.Mesh = undefined;
        bone[ROOT] = pelvisMesh();
        bone[SPINE] = abdomenMesh();
        bone[CHEST] = chestMesh();
        bone[NECK] = neckMesh();
        bone[SKULL] = hoodMesh();
        bone[HIPL] = thighMesh();
        bone[KNEEL] = shankMesh();
        bone[ANKL] = archermod.footMesh(1.0, 611);
        bone[HIPR] = thighMesh();
        bone[KNEER] = shankMesh();
        bone[ANKR] = archermod.footMesh(-1.0, 614);
        bone[SHL] = sleeveMesh(1.0);
        bone[ELL] = forearmMesh(1.0);
        bone[WRL] = handMesh(1.0);
        bone[SHR] = sleeveMesh(-1.0);
        bone[ELR] = forearmMesh(-1.0);
        bone[WRR] = handMesh(-1.0);
        bone[ORB] = orbMesh();
        var trail: [TRAIL_N]rl.Mesh = undefined;
        inline for (0..TRAIL_N) |i| trail[i] = trailMesh(i);
        return .{ .bone = bone, .hem = hemMesh(), .trail = trail, .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, d: *const Druidess) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, d.xf[i]);
        rl.drawMesh(self.hem, self.mat, d.hemMat);
        for (0..TRAIL_N) |i| rl.drawMesh(self.trail[i], self.mat, d.trailMat[i]);
    }
};

pub const Druidess = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    vineCd: f32 = 0,
    whipCd: f32 = 0,
    leapCd: f32 = 0,
    stepCd: f32 = 0,
    spearCd: f32 = 0,
    /// The line the spear runs down, committed at the strike: her facing then.
    spearYaw: f32 = 0,
    speared: bool = false,
    /// She left the ground this frame — the coven throws the pods.
    scattered: bool = false,
    /// The one phase change: latched the frame she commits to the call, so a stagger through the gather cannot hand her a second wave.
    phase2: bool = false,
    /// The channel is spent — stopped or finished — and she does not go back to it.
    healed: bool = false,
    wave: Wave = .frogs,
    /// ONE-FRAME REPORTS. The creature says what and where; the game and the coven do it.
    summoned: ?Wave = null,
    sowed: bool = false,
    snared: ?rl.Vector3 = null,
    /// The mark a cast is committed to, taken at the START of the gather so a walking man leaves it behind.
    castAt: rl.Vector3 = mathx.zero3,
    whipSpots: [WHIP_N]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** WHIP_N,
    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,
    arc: Arc = LEAP_ARC,
    flown: f32 = 0,
    /// THE ROOM SHE FIGHTS IN, stamped by the game off the arena she stands in (`game.stampRooms`): no leap, retreat, drift or step lands outside it. Null is open ground.
    room: ?wf.Arena = null,
    /// THE WATER, asked through the game (`foe.Ground`): nothing of hers lands or walks into more than `DRY_MAX` of it.
    ground: foe.Ground = .{},
    /// This leap goes OVER HIS HEAD — her first answer, and the only one when the water is behind her.
    overHead: bool = false,
    hop: f32 = 0,
    stepSide: f32 = 1,
    heroWas: rl.Vector3 = mathx.zero3,
    closing: f32 = 0,
    humT: f32 = 0,

    orbSh: f32 = CARRY_ORB_SH,
    orbEl: f32 = CARRY_ORB_EL,
    orbAbd: f32 = CARRY_ORB_ABD,
    freeSh: f32 = CARRY_FREE_SH,
    freeEl: f32 = CARRY_FREE_EL,
    freeAbd: f32 = CARRY_FREE_ABD,
    bodyLean: f32 = CARRY_LEAN,
    sideLean: f32 = 0,
    twist: f32 = 0,
    headPitch: f32 = CARRY_HEAD,
    headYaw: f32 = 0,
    /// 0..1, how lit the orb is: the gather of a cast and the whole of the channel.
    glow: f32 = 0,
    hemLean: f32 = 0,
    hemVel: f32 = 0,
    trailDrag: f32 = 0,
    trailYaw: [TRAIL_N]f32 = [_]f32{0} ** TRAIL_N,
    trailVel: [TRAIL_N]f32 = [_]f32{0} ** TRAIL_N,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    hemMat: rl.Matrix = undefined,
    trailMat: [TRAIL_N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Druidess {
        var d = Druidess{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .heroWas = home,
        };
        d.rest = REST;
        d.fxRng = foe.fxStream(seed, 74011.0, 0xD8);
        d.aiRng = foe.fxStream(seed, 30931.0, 0xD9);
        d.vineCd = 0.6 + seed * 0.8;
        d.whipCd = 1.8 + seed * 0.6;
        for (&d.trailYaw) |*y| y.* = faceYaw;
        d.pose();
        return d;
    }

    pub fn centerWorld(self: *const Druidess) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], mathx.zero3);
    }
    pub fn topWorld(self: *const Druidess) rl.Vector3 {
        return foe.bodyPoint(self.pos, 1.0 * H, self.scale, self.hop);
    }
    pub fn lockPoint(self: *const Druidess) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], archermod.LOCK_AT);
    }
    pub fn orbWorld(self: *const Druidess) rl.Vector3 {
        return foe.markOn(self.xf[ORB], ORB_AT);
    }
    pub fn hurtRadius(self: *const Druidess) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Druidess) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Druidess) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Druidess) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Druidess) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(self: *const Druidess) bool {
        return self.hop > 0.02;
    }
    pub fn flashFrac(self: *const Druidess) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn channeling(self: *const Druidess) bool {
        return self.state == .passive;
    }
    pub fn casting(self: *const Druidess) bool {
        return self.state == .vine_wind or self.state == .vine_cast or self.state == .whip_wind or self.state == .whip_cast or self.state == .spear_wind;
    }

    /// Where the `i`th of `n` called bodies stands: a fan of `SUMMON_R` in front of her, between her and the man.
    pub fn summonSpot(self: *const Druidess, i: u8, n: u8) rl.Vector3 {
        const share = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(@max(n, 1))) - 0.5;
        const yaw = self.facing + mathx.radians(140.0) * share;
        const dir = mathx.headingDir(yaw);
        return v3(self.pos.x + dir.x * SUMMON_R, self.pos.y, self.pos.z + dir.z * SUMMON_R);
    }

    pub fn navWant(self: *const Druidess, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        return mathx.addV(self.pos, mathx.scaleV(self.moveDir, 3.0));
    }

    fn fdir(self: *const Druidess) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Druidess, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    pub fn update(self: *Druidess, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.summoned = null;
        self.sowed = false;
        self.snared = null;
        self.speared = false;
        self.scattered = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.vineCd = mathx.maxF(0, self.vineCd - dt);
        self.whipCd = mathx.maxF(0, self.whipCd - dt);
        self.leapCd = mathx.maxF(0, self.leapCd - dt);
        self.stepCd = mathx.maxF(0, self.stepCd - dt);
        self.spearCd = mathx.maxF(0, self.spearCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        // CLOSING is his position over the last frame — what any body standing here could see — and never his press.
        const now = mathx.distXZ(self.pos, hero);
        const was = mathx.distXZ(self.pos, self.heroWas);
        self.closing = if (dt > 1e-4) (was - now) / dt else 0;
        self.heroWas = hero;

        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                _ = foe.postDrive(self, dt, bounds, WALK_SPEED, d, AGGRO_R, TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (!self.dodgeNow(d, hero) and self.t >= 0.20) self.decide(d, hero);
            },
            .drift => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = WALK_SPEED;
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.setCarry(dt);
                if (self.homing and mathx.distXZ(self.pos, foe.tetherFor(self)) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (!self.dodgeNow(d, hero) and self.t >= DRIFT_DUR) self.decide(d, hero);
            },
            .vine_wind, .whip_wind => {
                self.faceToward(hero, dt);
                const wind: f32 = if (self.state == .vine_wind) VINE_WIND else WHIP_WIND;
                self.setWind(dt, mathx.clampF(self.t / wind, 0, 1));
                self.gatherAtOrb(dt);
                if (self.t >= wind) self.enter(if (self.state == .vine_wind) .vine_cast else .whip_cast);
            },
            .vine_cast => {
                self.setCast(mathx.clampF(self.t / VINE_CAST, 0, 1));
                if (self.t >= VINE_CAST) {
                    self.snared = self.castAt;
                    self.vineCd = VINE_CD;
                    self.release();
                }
            },
            .whip_cast => {
                self.setCast(mathx.clampF(self.t / WHIP_CAST, 0, 1));
                if (self.t >= WHIP_CAST) {
                    self.sowed = true;
                    self.whipCd = WHIP_CD;
                    self.release();
                }
            },
            .spear_wind => {
                self.faceToward(hero, dt);
                self.setSpearWind(dt);
                self.gatherAtOrb(dt);
                if (self.t >= SPEAR_WIND) {
                    self.spearYaw = self.facing;
                    self.speared = true;
                    self.spearCd = SPEAR_CD;
                    self.bloom(self.orbWorld(), CAST_BURST);
                    sfx.world(.druid_spear, self.pos);
                    self.enter(.spear_cast);
                }
            },
            .spear_cast => {
                self.setSpearCast(mathx.clampF(self.t / SPEAR_STRIKE, 0, 1));
                if (self.t >= SPEAR_STRIKE + SPEAR_RECOVER) self.decide(d, hero);
            },
            .leap, .retreat => {
                self.faceToward(hero, dt);
                self.fly(dt, bounds, &movedDist, &moveSpeed, &moveYaw);
                self.setLeap(dt);
                if (self.t >= arcTotal(self.arc)) {
                    self.hop = 0;
                    self.land();
                    if (self.state == .leap) {
                        self.decide(d, hero);
                    } else {
                        sfx.world(.druid_hum, self.pos);
                        self.enter(.passive);
                    }
                }
            },
            .step => {
                const u = mathx.clampF(self.t / STEP_DUR, 0, 1);
                moveSpeed = (STEP_DIST / STEP_DUR) * 0.5 * std.math.pi * mathx.sinf(std.math.pi * u);
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, self.moveDir, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(self.moveDir);
                self.faceToward(hero, dt * 2.0);
                self.setStep(dt);
                if (self.t >= STEP_DUR) {
                    self.stepCd = STEP_CD;
                    self.enter(.idle);
                }
            },
            .summon_wind => {
                self.faceToward(hero, dt);
                self.setSummonWind(dt);
                self.gatherAtOrb(dt);
                if (self.t >= SUMMON_WIND) self.enter(.summon_cast);
            },
            .summon_cast => {
                self.setSummonCast(mathx.clampF(self.t / SUMMON_CAST, 0, 1));
                if (self.t >= SUMMON_CAST) {
                    self.summoned = self.wave;
                    self.bloom(self.orbWorld(), SUMMON_BURST);
                    sfx.world(.druid_summon, self.pos);
                    self.startArc(RETREAT_ARC, hero, .retreat);
                }
            },
            .passive => {
                self.faceToward(hero, dt * 0.6);
                self.setPassive(dt);
                _ = self.vit.heal(HEAL_RATE * self.vit.hpMax * dt);
                self.gatherAtOrb(dt);
                // The hum is a take shorter than the channel, retriggered on its own beat (the souls hum's rule).
                self.humT += dt;
                if (self.humT >= HUM_EVERY) {
                    self.humT -= HUM_EVERY;
                    sfx.world(.druid_hum, self.pos);
                }
                if (self.vit.hp >= self.vit.hpMax - 0.5) {
                    self.healed = true;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.setRecover(dt);
                if (self.t >= RECOVER) self.decide(d, hero);
            },
            .stunlight, .stunheavy => {
                self.easeNeutral(dt);
                self.hop = mathx.approach(self.hop, 0, dt * 6.0);
                const dur = combat.foeStunDur(self.state == .stunheavy);
                if (self.t >= dur) self.enter(.idle);
            },
            .dead => {
                self.easeNeutral(dt);
                self.hop = mathx.approach(self.hop, 0, dt * 6.0);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.tickHem(dt, moveSpeed);
        self.tickTrails(dt, moveSpeed);
        self.pose();
        self.tryHit(blade);
        return null;
    }

    /// Inside her reach rings she leaves before she casts. The leap is a jump and the roots refuse it (`foe.canLeap`); the sidestep is a step and needs no leave.
    fn dodgeNow(self: *Druidess, d: f32, hero: rl.Vector3) bool {
        if (d <= LEAP_R and self.leapCd <= 0 and foe.canLeap(&self.root)) {
            self.leapCd = LEAP_CD;
            self.startArc(LEAP_ARC, hero, .leap);
            sfx.world(.druid_leap, self.pos);
            return true;
        }
        if (d <= STEP_R and self.closing >= STEP_CLOSE and self.stepCd <= 0) {
            self.stepSide = if (self.aiRng.float() < 0.5) 1.0 else -1.0;
            const to = mathx.dirXZ(self.pos, hero);
            const lat = mathx.perpXZ(if (mathx.lenXZ(to) > 1e-4) to else self.fdir());
            // A step into the wall is the other side's step; no side at all is no step, and the spear answers instead.
            if (!self.inRoom(self.landing(mathx.scaleV(lat, self.stepSide), STEP_DIST))) self.stepSide = -self.stepSide;
            if (self.inRoom(self.landing(mathx.scaleV(lat, self.stepSide), STEP_DIST))) {
                self.moveDir = mathx.scaleV(lat, self.stepSide);
                self.enter(.step);
                sfx.world(.druid_step, self.pos);
                return true;
            }
        }
        if (d <= SPEAR_R and d >= SPEAR_MIN and self.closing >= SPEAR_CLOSE and self.spearCd <= 0) {
            self.enter(.spear_wind);
            return true;
        }
        return false;
    }

    /// Ground she may stand on: dry, and inside the room with her own footprint to spare. Open ground is all room; an unstamped bench is all dry.
    fn inRoom(self: *const Druidess, at: rl.Vector3) bool {
        if (self.ground.depth(at.x, at.z) > DRY_MAX) return false;
        const r = self.room orelse return true;
        if (!r.contains(at.x, at.z)) return false;
        return r.nearestWall(at).d >= self.bodyR();
    }
    fn landing(self: *const Druidess, dir: rl.Vector3, dist: f32) rl.Vector3 {
        return v3(self.pos.x + dir.x * dist, self.pos.y, self.pos.z + dir.z * dist);
    }
    /// The furthest she can go along `dir` and still land in the room, up to `max`, a metre at a time.
    fn roomReach(self: *const Druidess, dir: rl.Vector3, max: f32) f32 {
        var best: f32 = 0;
        var d: f32 = 1.0;
        while (d <= max) : (d += 1.0) {
            if (self.inRoom(self.landing(dir, d))) best = d;
        }
        return best;
    }
    /// A walk that would leave the room is turned along the wall, and failing that towards the middle.
    fn steerInRoom(self: *const Druidess, want: rl.Vector3) rl.Vector3 {
        const probe = WALK_SPEED * DRIFT_DUR + self.bodyR();
        if (self.inRoom(self.landing(want, probe))) return want;
        const lat = mathx.perpXZ(want);
        if (self.inRoom(self.landing(lat, probe))) return lat;
        const back = mathx.scaleV(lat, -1.0);
        if (self.inRoom(self.landing(back, probe))) return back;
        const r = self.room orelse return want;
        return mathx.dirXZ(self.pos, r.middle());
    }

    fn startArc(self: *Druidess, arc: Arc, hero: rl.Vector3, s: State) void {
        var away = mathx.scaleV(mathx.dirXZ(self.pos, hero), -1.0);
        if (mathx.lenXZ(away) < 1e-4) away = mathx.scaleV(self.fdir(), -1.0);
        const side: f32 = if (self.aiRng.float() < 0.5) 1.0 else -1.0;
        const clear = mathx.normV(mathx.addV(away, mathx.scaleV(mathx.perpXZ(away), 0.25 * side)));
        const over = mathx.scaleV(away, -1.0);
        self.arc = arc;
        // OVER HIS HEAD FIRST (owner): the leap that gets away from him AND from whatever is behind her. Back is for when the ground past him is not there.
        if (self.inRoom(self.landing(over, arc.dist))) {
            self.moveDir = over;
            self.overHead = true;
        } else {
            self.moveDir = clear;
            self.overHead = false;
            if (!self.inRoom(self.landing(clear, arc.dist))) {
                // Neither way is open at the full length: the bearing with the most room, leaning away from him, and no further than that room allows.
                var bestDir = clear;
                var bestScore: f32 = -1;
                var k: u32 = 0;
                while (k < 12) : (k += 1) {
                    const a = @as(f32, @floatFromInt(k)) / 12.0 * std.math.tau;
                    const dir = v3(mathx.cosf(a), 0, mathx.sinf(a));
                    const reach = self.roomReach(dir, arc.dist);
                    const score = reach * (1.0 + 0.5 * (dir.x * away.x + dir.z * away.z));
                    if (score > bestScore) {
                        bestScore = score;
                        bestDir = dir;
                    }
                }
                self.moveDir = bestDir;
                self.arc.dist = mathx.clampF(self.roomReach(bestDir, arc.dist), 2.0, arc.dist);
            }
        }
        self.flown = 0;
        self.scattered = true;
        self.enter(s);
    }

    fn fly(self: *Druidess, dt: f32, bounds: f32, movedDist: *f32, moveSpeed: *f32, moveYaw: *?f32) void {
        const along = arcAlong(self.arc, self.t);
        const step = mathx.maxF(0, along - self.flown);
        self.flown = along;
        mathx.stepXZ(&self.pos, self.moveDir, step, bounds);
        movedDist.* = step;
        moveSpeed.* = if (dt > 1e-4) step / dt else 0;
        moveYaw.* = mathx.headingXZ(self.moveDir);
        self.hop = arcHop(self.arc, self.t);
    }

    fn land(self: *Druidess) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, self.pos, v3(0, 0, 1), 6, 1.2, self.scale, LAND_DUST);
        sfx.world(.druid_land, self.pos);
    }

    fn release(self: *Druidess) void {
        self.bloom(self.orbWorld(), CAST_BURST);
        sfx.world(.druid_release, self.pos);
        self.enter(.recover);
    }

    fn decide(self: *Druidess, d: f32, hero: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, foe.tetherFor(self));
            return self.enter(.drift);
        }
        self.homing = false;
        if (!self.phase2 and d <= AGGRO_R and self.vit.hpFrac() <= PHASE_HP) {
            self.phase2 = true;
            self.wave = @enumFromInt(self.aiRng.intn(WAVE_N));
            return self.enter(.summon_wind);
        }
        switch (classify(d, self.vineCd <= 0, self.whipCd <= 0)) {
            .vine => {
                self.castAt = hero;
                self.enter(.vine_wind);
            },
            .whip => {
                self.castAt = hero;
                self.rollWhipSpots();
                self.enter(.whip_wind);
            },
            .keep => {
                const f = self.fdir();
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                const out = mathx.scaleV(f, -1.0);
                const lat = mathx.scaleV(mathx.perpXZ(f), side);
                const want = if (d < KEEP_MIN)
                    mathx.normV(mathx.addV(out, mathx.scaleV(lat, 0.5)))
                else if (d > KEEP_MAX)
                    mathx.normV(mathx.addV(f, mathx.scaleV(lat, 0.4)))
                else
                    lat;
                self.moveDir = self.steerInRoom(want);
                self.enter(.drift);
            },
            .hold => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, foe.tetherFor(self));
                    self.enter(.drift);
                } else self.enter(.idle);
            },
        }
    }

    /// Where the whips will stand is rolled at the gather, so the buds shown through the wind are the vines that come.
    fn rollWhipSpots(self: *Druidess) void {
        for (&self.whipSpots, 0..) |*s, i| {
            const a = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(WHIP_N))) * std.math.tau + self.aiRng.range(-0.5, 0.5);
            const r = self.aiRng.range(WHIP_SOW_MIN, WHIP_SOW_MAX);
            s.* = v3(self.castAt.x + mathx.cosf(a) * r, self.castAt.y, self.castAt.z + mathx.sinf(a) * r);
        }
    }

    fn enter(self: *Druidess, s: State) void {
        self.state = s;
        self.t = 0;
        switch (s) {
            .vine_wind, .whip_wind, .summon_wind, .spear_wind => sfx.world(.druid_cast, self.pos),
            else => {},
        }
    }
    fn enterStun(self: *Druidess, s: State) void {
        self.state = s;
        self.t = 0;
        self.homing = false;
    }
    fn enterDeath(self: *Druidess) void {
        if (self.state == .dead) return;
        self.enterStun(.dead);
        self.justDied = true;
    }

    pub fn tryHit(self: *Druidess, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 1.1, .heavy = 2.0 });
        self.chips(s.contact, s.dir, if (heavyBlow) CHIP_HEAVY else CHIP_LIGHT, if (heavyBlow) 3.0 else 2.2);
        sfx.world(.druid_hurt, self.pos);
        // ONE BLOW STOPS THE CHANNEL, and she does not go back to it: the stopping is the whole of "you must go and stop her".
        const wasChannel = self.state == .passive;
        if (wasChannel) self.healed = true;
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 2.8);
                sfx.world(.druid_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => if (wasChannel) self.enter(.recover),
        }
    }

    pub fn stagger(self: *Druidess, heavy: bool) void {
        if (self.state == .dead) return;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    /// The save's rail says she is down: put her past her own dissolve, so a loaded run never meets a boss it killed.
    pub fn markSlain(self: *Druidess) void {
        self.vit.hp = 0;
        self.vit.dead = true;
        self.state = .dead;
        self.t = DEATH_DUR + DISS_DUR;
        self.fade = 1;
        self.hop = 0;
        self.gone = true;
    }
    pub fn debugKill(self: *Druidess) void {
        self.enterDeath();
    }
    pub fn debugVine(self: *Druidess, hero: rl.Vector3) void {
        self.vineCd = 0;
        self.castAt = hero;
        self.enter(.vine_wind);
    }
    pub fn debugWhip(self: *Druidess, hero: rl.Vector3) void {
        self.whipCd = 0;
        self.castAt = hero;
        self.rollWhipSpots();
        self.enter(.whip_wind);
    }
    pub fn debugSpear(self: *Druidess) void {
        self.spearCd = 0;
        self.enter(.spear_wind);
    }
    pub fn stageGather(self: *Druidess, u: f32) void {
        self.state = .vine_wind;
        self.t = mathx.clampF(u, 0, 1) * VINE_WIND;
        self.setWind(1.0, self.t / VINE_WIND);
        self.pose();
    }

    fn chips(self: *Druidess, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, LEAF_SPRAY);
    }
    fn bloom(self: *Druidess, at: rl.Vector3, n: usize) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .chaos, n, self.scale);
    }
    fn gatherAtOrb(self: *Druidess, dt: f32) void {
        const n = foe.emitDue(&self.fxAccum, dt, 16.0);
        if (n > 0) elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, self.orbWorld(), .chaos, n, 0.55 * self.scale, self.scale);
    }

    fn setCarry(self: *Druidess, dt: f32) void {
        const e = dt * 6.0;
        self.orbSh = easeTo(self.orbSh, CARRY_ORB_SH, e);
        self.orbEl = easeTo(self.orbEl, CARRY_ORB_EL, e);
        self.orbAbd = easeTo(self.orbAbd, CARRY_ORB_ABD, e);
        self.freeSh = easeTo(self.freeSh, CARRY_FREE_SH, e);
        self.freeEl = easeTo(self.freeEl, CARRY_FREE_EL, e);
        self.freeAbd = easeTo(self.freeAbd, CARRY_FREE_ABD, e);
        self.bodyLean = easeTo(self.bodyLean, CARRY_LEAN, e);
        self.sideLean = easeTo(self.sideLean, 0, e);
        self.twist = easeTo(self.twist, 0, e);
        self.headPitch = easeTo(self.headPitch, CARRY_HEAD, e);
        self.headYaw = easeTo(self.headYaw, 0, e);
        self.glow = easeTo(self.glow, 0.15, e);
    }

    fn setWind(self: *Druidess, dt: f32, u: f32) void {
        const e = dt * 9.0;
        self.orbSh = easeTo(self.orbSh, WIND_ORB_SH, e);
        self.orbEl = easeTo(self.orbEl, WIND_ORB_EL, e);
        self.orbAbd = easeTo(self.orbAbd, WIND_ORB_ABD, e);
        self.freeSh = easeTo(self.freeSh, WIND_FREE_SH, e);
        self.freeEl = easeTo(self.freeEl, WIND_FREE_EL, e);
        self.freeAbd = easeTo(self.freeAbd, WIND_FREE_ABD, e);
        self.bodyLean = easeTo(self.bodyLean, WIND_LEAN, e);
        self.sideLean = easeTo(self.sideLean, 0, e);
        self.twist = easeTo(self.twist, WIND_TWIST, e);
        self.headPitch = easeTo(self.headPitch, WIND_HEAD, e);
        self.glow = mathx.maxF(self.glow, 0.15 + 0.85 * mathx.smoothstep(0, 1, u));
    }

    fn setCast(self: *Druidess, u: f32) void {
        const e = foe.swingCurve(u);
        self.orbSh = lerpF(WIND_ORB_SH, CAST_ORB_SH, e);
        self.orbEl = lerpF(WIND_ORB_EL, CAST_ORB_EL, e);
        self.bodyLean = lerpF(WIND_LEAN, CAST_LEAN, e);
        self.twist = lerpF(WIND_TWIST, CAST_TWIST, e);
        self.headPitch = lerpF(WIND_HEAD, CAST_HEAD, e);
        self.glow = 1.0 - 0.6 * e;
    }

    /// The coil: fast into the pose so the whole wind is HELD there, and the orb lit the while.
    fn setSpearWind(self: *Druidess, dt: f32) void {
        const e = dt * 16.0;
        self.orbSh = easeTo(self.orbSh, SPEAR_WIND_ORB_SH, e);
        self.orbEl = easeTo(self.orbEl, SPEAR_WIND_ORB_EL, e);
        self.orbAbd = easeTo(self.orbAbd, SPEAR_WIND_ORB_ABD, e);
        self.freeSh = easeTo(self.freeSh, SPEAR_WIND_FREE_SH, e);
        self.freeEl = easeTo(self.freeEl, SPEAR_WIND_FREE_EL, e);
        self.freeAbd = easeTo(self.freeAbd, SPEAR_WIND_FREE_ABD, e);
        self.bodyLean = easeTo(self.bodyLean, SPEAR_WIND_LEAN, e);
        self.sideLean = easeTo(self.sideLean, 0, e);
        self.twist = easeTo(self.twist, SPEAR_WIND_TWIST, e);
        self.headPitch = easeTo(self.headPitch, SPEAR_WIND_HEAD, e);
        self.glow = easeTo(self.glow, 1.0, e);
    }

    /// The unwind: everything the coil wound goes the other way at once, and the orb hand drives straight out.
    fn setSpearCast(self: *Druidess, u: f32) void {
        const e = foe.swingCurve(u);
        self.orbSh = lerpF(SPEAR_WIND_ORB_SH, SPEAR_THRUST_ORB_SH, e);
        self.orbEl = lerpF(SPEAR_WIND_ORB_EL, SPEAR_THRUST_ORB_EL, e);
        self.orbAbd = lerpF(SPEAR_WIND_ORB_ABD, SPEAR_THRUST_ORB_ABD, e);
        self.freeSh = lerpF(SPEAR_WIND_FREE_SH, SPEAR_THRUST_FREE_SH, e);
        self.freeAbd = lerpF(SPEAR_WIND_FREE_ABD, SPEAR_THRUST_FREE_ABD, e);
        self.bodyLean = lerpF(SPEAR_WIND_LEAN, SPEAR_THRUST_LEAN, e);
        self.twist = lerpF(SPEAR_WIND_TWIST, SPEAR_THRUST_TWIST, e);
        self.headPitch = lerpF(SPEAR_WIND_HEAD, SPEAR_THRUST_HEAD, e);
        self.glow = 1.0 - 0.5 * e;
    }

    fn setSummonWind(self: *Druidess, dt: f32) void {
        const e = dt * 5.0;
        self.orbSh = easeTo(self.orbSh, SUMMON_ORB_SH, e);
        self.orbEl = easeTo(self.orbEl, SUMMON_ORB_EL, e);
        self.orbAbd = easeTo(self.orbAbd, SUMMON_ORB_ABD, e);
        self.freeSh = easeTo(self.freeSh, SUMMON_FREE_SH, e);
        self.freeEl = easeTo(self.freeEl, SUMMON_FREE_EL, e);
        self.freeAbd = easeTo(self.freeAbd, SUMMON_FREE_ABD, e);
        self.bodyLean = easeTo(self.bodyLean, SUMMON_LEAN, e);
        self.twist = easeTo(self.twist, 0, e);
        self.headPitch = easeTo(self.headPitch, SUMMON_HEAD, e);
        self.glow = easeTo(self.glow, 1.0, e);
    }

    fn setSummonCast(self: *Druidess, u: f32) void {
        const e = foe.swingCurve(u);
        self.orbSh = lerpF(SUMMON_ORB_SH, THROW_ORB_SH, e);
        self.orbAbd = lerpF(SUMMON_ORB_ABD, THROW_ORB_ABD, e);
        self.freeSh = lerpF(SUMMON_FREE_SH, THROW_FREE_SH, e);
        self.freeAbd = lerpF(SUMMON_FREE_ABD, THROW_FREE_ABD, e);
        self.bodyLean = lerpF(SUMMON_LEAN, THROW_LEAN, e);
        self.headPitch = lerpF(SUMMON_HEAD, 8.0, e);
    }

    fn setPassive(self: *Druidess, dt: f32) void {
        const e = dt * 4.0;
        self.orbSh = easeTo(self.orbSh, PASSIVE_ORB_SH, e);
        self.orbEl = easeTo(self.orbEl, PASSIVE_ORB_EL, e);
        self.orbAbd = easeTo(self.orbAbd, PASSIVE_ORB_ABD, e);
        self.freeSh = easeTo(self.freeSh, PASSIVE_FREE_SH, e);
        self.freeEl = easeTo(self.freeEl, PASSIVE_FREE_EL, e);
        self.freeAbd = easeTo(self.freeAbd, PASSIVE_FREE_ABD, e);
        self.bodyLean = easeTo(self.bodyLean, PASSIVE_LEAN, e);
        self.sideLean = easeTo(self.sideLean, 0, e);
        self.twist = easeTo(self.twist, 0, e);
        self.headPitch = easeTo(self.headPitch, PASSIVE_HEAD, e);
        self.glow = easeTo(self.glow, 1.0, e);
    }

    fn setLeap(self: *Druidess, dt: f32) void {
        const e = dt * 7.0;
        self.orbSh = easeTo(self.orbSh, LEAP_SH, e);
        self.orbEl = easeTo(self.orbEl, LEAP_EL, e);
        self.orbAbd = easeTo(self.orbAbd, LEAP_ABD, e);
        self.freeSh = easeTo(self.freeSh, LEAP_SH, e);
        self.freeEl = easeTo(self.freeEl, LEAP_EL, e);
        self.freeAbd = easeTo(self.freeAbd, LEAP_ABD, e);
        self.bodyLean = easeTo(self.bodyLean, LEAP_LEAN, e);
        self.twist = easeTo(self.twist, 0, e);
        self.headPitch = easeTo(self.headPitch, LEAP_HEAD, e);
        self.glow = easeTo(self.glow, 0.4, e);
    }

    fn setStep(self: *Druidess, dt: f32) void {
        const e = dt * 12.0;
        self.sideLean = easeTo(self.sideLean, -STEP_LEAN_SIDE * self.stepSide, e);
        self.bodyLean = easeTo(self.bodyLean, CARRY_LEAN + 6.0, e);
    }

    fn setRecover(self: *Druidess, dt: f32) void {
        self.setCarry(dt * 0.7);
    }

    fn easeNeutral(self: *Druidess, dt: f32) void {
        self.setCarry(dt * 1.4);
    }

    fn tickHem(self: *Druidess, dt: f32, speed: f32) void {
        const want = HEM_DRAG * mathx.clampF(speed / WALK_SPEED, 0, 1);
        const accel = (want - self.hemLean) * HEM_EASE * HEM_SETTLE;
        self.hemVel += accel * dt;
        self.hemVel *= mathx.maxF(0, 1.0 - HEM_EASE * dt);
        self.hemLean += self.hemVel * dt;
    }

    /// THE TANGLE IS THREE SPRINGS ON HER HEADING. Each tail chases her facing through its own stiffness and rings past it, so a turn swings the robes round after her and they settle in three different beats.
    fn tickTrails(self: *Druidess, dt: f32, speed: f32) void {
        const drag = TRAIL_DRAG * mathx.clampF(speed / WALK_SPEED, 0, 1) - TRAIL_FLARE * mathx.clampF(self.hop / LEAP_ARC.up, 0, 1);
        self.trailDrag = easeTo(self.trailDrag, drag, dt * 5.0);
        for (0..TRAIL_N) |i| {
            const err = mathx.wrapPi(self.facing - self.trailYaw[i]);
            const damp = 2.0 * TRAIL_ZETA * @sqrt(TRAIL_STIFF[i]);
            self.trailVel[i] += (TRAIL_STIFF[i] * err - damp * self.trailVel[i]) * dt;
            self.trailYaw[i] += self.trailVel[i] * dt;
        }
    }

    fn stunAmount(self: *const Druidess) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn pose(self: *Druidess) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();

        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.22 * H, dk);
        const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip + self.hop / mathx.maxF(self.scale, 1e-3);
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(self.sideLean + 9.0 * dk), rx(16.0 * dk), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legPair(&wx, &self.rest, self.pos.y + self.hop, self.phase, m, 0, self.fwdB, self.latB, HIPL, KNEEL, HIPR, KNEER, solePatches);
        }
        self.poseUpper(&wx, dk, stun, dead, pel.prot);
        self.xf = wx;
        self.chainHem();
        self.chainTrails(fs);
    }

    fn chainHem(self: *Druidess) void {
        const swayLag = HEM_SWAY * mathx.sinf(std.math.tau * self.phase - 0.9) * self.moving;
        self.hemMat = mul(mul(rx(self.hemLean), rz(swayLag)), self.xf[ROOT]);
    }

    fn chainTrails(self: *Druidess, fs: f32) void {
        const at = foe.markOn(self.xf[ROOT], mathx.zero3);
        for (0..TRAIL_N) |i| {
            const yaw = mathx.degrees(self.trailYaw[i]) + TRAIL_OFF[i];
            self.trailMat[i] = mul(mul(scaleM(fs, fs, fs), mul(rx(self.trailDrag + self.hemLean * 0.5), ry(yaw))), heromod.rootAt(at));
        }
    }

    fn poseUpper(self: *Druidess, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 4.0;
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const swayArg = self.elapsed * (0.38 + 0.18 * (0.5 + 0.5 * mathx.sinf(self.seed * 27.3))) + self.seed * 6.28;
        const swy = mathx.sinf(swayArg) * idleAmt;
        const swyLag = mathx.sinf(swayArg - 0.9) * idleAmt;

        const nod = 1.4 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const lean = self.bodyLean - 22.0 * stun + 26.0 * dk;
        setLocal(wx, SPINE, rest, mul3(
            rx(lean * 0.45 + nod + 0.7 * swy),
            ry(-0.35 * prot + self.twist * 0.4),
            rz(wonk * 0.5 + 1.0 * swy),
        ));
        setLocal(wx, CHEST, rest, mul3(
            rx(lean * 0.55 + nod * 0.6 + 0.5 * swyLag),
            ry(-0.5 * prot + self.twist * 0.6),
            rz(-wonk * 0.3 - 0.7 * swyLag),
        ));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.35 + 10.0 * dk - 8.0 * stun));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.65 + 18.0 * dk - 24.0 * stun),
            ry(self.headYaw - 0.5 * prot),
            rz(wonk - 1.2 * swyLag - 0.8 * nod),
        ));

        if (dead) heromod.deadLegs(wx, rest, dk);

        const armStun = -60.0 * stun;
        const swing = -9.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const fwdHalf = mathx.maxF(0, mathx.sinf(twoPi * self.phase));
        const freeSh = self.freeSh + swing + armStun - 30.0 * dk + 2.0 * swyLag;
        setLocal(wx, SHL, rest, mul3(rx(-freeSh), ry(0), rz(self.freeAbd + wonk * 0.4)));
        setLocal(wx, ELL, rest, rx(-self.freeEl - 12.0 * fwdHalf * m));
        setLocal(wx, WRL, rest, rz(-5.0));

        const orbSh = self.orbSh - swing * 0.4 + armStun - 26.0 * dk + 1.6 * swy;
        setLocal(wx, SHR, rest, mul3(rx(-orbSh), ry(0), rz(-self.orbAbd - wonk * 0.4)));
        setLocal(wx, ELR, rest, rx(-self.orbEl));
        setLocal(wx, WRR, rest, rx(-18.0));
        setLocal(wx, ORB, rest, rl.math.matrixIdentity());
    }

    pub fn draw(self: *const Druidess, model: *const Model) void {
        model.draw(self);
    }

    pub fn drawFx(self: *const Druidess) void {
        if (!self.gone and self.glow > 0.05) {
            const at = self.orbWorld();
            const r = ORB_R * self.scale;
            const pulse = 1.0 + 0.12 * mathx.sinf(self.elapsed * 9.0);
            rl.drawSphereEx(at, r * (1.6 + 1.4 * self.glow) * pulse, 8, 6, mathx.withAlpha(CHAOS_CORE, mathx.u8f(28.0 + 70.0 * self.glow)));
            if (self.channeling()) {
                // THE CHANNEL IS A COLUMN YOU CAN SEE FROM THE OTHER SIDE OF THE FIELD: orb to ground, brighter as she mends.
                const foot = v3(self.pos.x, self.pos.y + 0.05, self.pos.z);
                const k = 0.5 + 0.5 * mathx.sinf(self.elapsed * 5.0);
                rl.drawCylinderEx(foot, at, 0.30 * self.scale, 0.10 * self.scale, 8, mathx.withAlpha(CHAOS_EDGE, mathx.u8f(40.0 + 30.0 * k)));
                rl.drawCylinderEx(foot, v3(foot.x, foot.y + 0.02, foot.z), 1.2 * self.scale, 1.2 * self.scale, 12, mathx.withAlpha(CHAOS_EDGE, 70));
            }
        }
        foe.drawParticles(&self.parts);
    }
};

pub const VINE_N: usize = 14;

pub const VineKind = enum { whip, snare, spear };

pub const Vine = struct {
    live: bool = false,
    kind: VineKind = .whip,
    at: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    yaw: f32 = 0,
    seed: f32 = 0,
    lashes: u32 = 0,
    lashed: bool = false,

    pub fn grown(self: *const Vine) f32 {
        return sproutCurve(mathx.clampF(self.t / WHIP_GROW, 0, 1));
    }
    fn lifeEnd(self: *const Vine) f32 {
        return switch (self.kind) {
            .whip => WHIP_GROW + WHIP_LIFE,
            .snare => SNARE_SHOW,
            .spear => SPEAR_STRIKE + SPEAR_HOLD,
        };
    }
    /// How far the spear has run from her feet: the whole length inside `SPEAR_STRIKE`, drawn back into the ground as it withers.
    pub fn extent(self: *const Vine) f32 {
        return SPEAR_LEN * foe.swingCurve(mathx.clampF(self.t / SPEAR_STRIKE, 0, 1)) * self.stand();
    }
    /// 1 standing, falling to 0 across the wither.
    pub fn stand(self: *const Vine) f32 {
        return 1.0 - mathx.clampF((self.t - self.lifeEnd()) / WITHER, 0, 1);
    }
    pub fn spent(self: *const Vine) bool {
        return self.t >= self.lifeEnd() + WITHER;
    }
    /// -1 reared right back, 0 upright, +1 whipped through: the lash's one clock.
    pub fn lash(self: *const Vine) f32 {
        const life = self.t - WHIP_GROW;
        if (self.kind != .whip or life < 0 or life >= WHIP_LIFE) return 0;
        const into = life - @floor(life / WHIP_PERIOD) * WHIP_PERIOD;
        if (into < WHIP_TELL) return -mathx.smoothstep(0, WHIP_TELL * 0.85, into);
        const after = into - WHIP_TELL;
        if (after < 0.12) return lerpF(-1.0, 1.0, foe.swingCurve(after / 0.12));
        // THE CRACK: past the mark and ringing back onto it, then the slow droop back upright.
        const ring = after - 0.12;
        const settle = 1.0 - mathx.smoothstep(0.12, WHIP_PERIOD - WHIP_TELL, after);
        return settle * (1.0 + 0.28 * mathx.sinf(ring * 26.0) * @exp(-ring * 6.0));
    }
};

/// A SPROUT OVERSHOOTS: up to 1.14 of its height and back down onto it — a mass in motion, not a slider.
fn sproutCurve(u: f32) f32 {
    if (u < 0.72) return 1.14 * mathx.smoothstep(0, 0.72, u);
    return 1.14 - 0.14 * mathx.smoothstep(0.72, 1.0, u);
}

pub const POD_CAP: usize = 12;

pub const Pod = struct {
    live: bool = false,
    from: rl.Vector3 = mathx.zero3,
    to: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    seed: f32 = 0,

    pub fn landed(self: *const Pod) bool {
        return self.t >= POD_FLIGHT;
    }
    /// Where it is: a lob from the orb to its spot, then the spot.
    pub fn at(self: *const Pod) rl.Vector3 {
        const u = mathx.clampF(self.t / POD_FLIGHT, 0, 1);
        var p = mathx.lerpV(self.from, self.to, u);
        p.y += POD_FLIGHT_UP * 4.0 * u * (1.0 - u);
        return p;
    }
    /// 0 as it lands, 1 as it goes off.
    pub fn swell(self: *const Pod) f32 {
        return mathx.clampF((self.t - POD_FLIGHT) / POD_FUSE, 0, 1);
    }
    /// The shell, with a heartbeat that quickens as the fuse runs.
    pub fn radius(self: *const Pod) f32 {
        const s = self.swell();
        const beat = mathx.sinf(self.t * (7.0 + 16.0 * s) + self.seed * 6.28);
        return lerpF(POD_R0, POD_R1, mathx.smoothstep(0, 1, s)) * (1.0 + 0.07 * beat * s);
    }
    pub fn due(self: *const Pod) bool {
        return self.t >= POD_FLIGHT + POD_FUSE;
    }
};

const GROUND_THREAT = foe.Threat{};
const CAP_N = wf.MAX_PER_KIND;
/// Sized over the worst frame: four pods off one leap share a fuse and go off together — each a chaos burst and its splinters.
const COVEN_PARTS: usize = 160;
comptime {
    std.debug.assert(COVEN_PARTS >= POD_N * (elemfx.burstCount(.chaos, POD_BURST) + @as(usize, @intCast(foe.hitParts(POD_SPLINTERS)))) + 24);
}

pub const Coven = struct {
    model: Model,
    band: [CAP_N]Druidess = undefined,
    n: usize = 0,
    vines: [VINE_N]Vine = [_]Vine{.{}} ** VINE_N,
    pods: [POD_CAP]Pod = [_]Pod{.{}} ** POD_CAP,
    pendingSnare: f32 = 0,
    holdLeft: f32 = 0,
    holdT: f32 = 0,
    holdAt: rl.Vector3 = mathx.zero3,
    parts: [COVEN_PARTS]foe.Particle = [_]foe.Particle{.{}} ** COVEN_PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0xD00D),

    pub fn init(shader: rl.Shader) Coven {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Coven) []Druidess {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Coven) []const Druidess {
        return self.band[0..self.n];
    }
    pub fn reset(self: *Coven, m: *const wf.Map) void {
        self.clearGround();
        foe.resetGroup(Druidess, &self.band, &self.n, m, .druidess);
    }
    pub fn clear(self: *Coven) void {
        self.n = 0;
        self.clearGround();
    }
    fn clearGround(self: *Coven) void {
        self.vines = [_]Vine{.{}} ** VINE_N;
        self.pods = [_]Pod{.{}} ** POD_CAP;
        self.pendingSnare = 0;
        self.holdLeft = 0;
        self.holdT = 0;
    }

    /// The bite of the vines that have him: a physical pulse on its own clock for as long as the hold runs. Read once a frame by the game, after the snare itself.
    pub fn holdDose(self: *Coven, dt: f32) ?foe.Blow {
        if (self.holdLeft <= 0) return null;
        self.holdLeft -= dt;
        self.holdT += dt;
        if (self.holdT < SNARE_PULSE_EVERY) return null;
        self.holdT -= SNARE_PULSE_EVERY;
        return .{ .hit = SNARE_PULSE_HIT, .from = self.holdAt, .on = .hero };
    }
    pub fn setShader(self: *Coven, sh: rl.Shader) void {
        self.model.setShader(sh);
    }

    pub fn update(self: *Coven, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var worst: ?foe.Blow = null;
        for (self.live()) |*d| {
            if (d.update(dt, d.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&worst, h, d.pos, &d.threat);
            if (d.sowed) self.sowWhips(d);
            if (d.snared) |at| self.erupt(at, hero, &worst);
            if (d.speared) self.thrust(d.pos, d.spearYaw);
            if (d.scattered) self.scatter(d);
        }
        self.tickVines(dt, hero, &worst);
        self.tickPods(dt, hero, &worst);
        foe.tickParticles(&self.parts, dt, hero.y);
        return worst;
    }

    /// A fan of pods thrown off the orb as she leaves, landing on the side she is leaving — where the man comes through after her.
    pub fn scatter(self: *Coven, d: *const Druidess) void {
        const from = d.orbWorld();
        var i: usize = 0;
        while (i < POD_N) : (i += 1) {
            const share = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(POD_N)) - 0.5;
            const yaw = d.facing + mathx.radians(POD_SPREAD) * share + self.fxRng.range(-0.15, 0.15);
            const dist = self.fxRng.range(POD_SCATTER_MIN, POD_SCATTER_MAX);
            const dir = mathx.headingDir(yaw);
            const to = v3(d.pos.x + dir.x * dist, d.pos.y, d.pos.z + dir.z * dist);
            for (&self.pods) |*p| {
                if (p.live) continue;
                p.* = .{ .live = true, .from = from, .to = to, .seed = self.fxRng.float() };
                break;
            }
        }
    }

    pub fn tickPods(self: *Coven, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        for (&self.pods) |*p| {
            if (!p.live) continue;
            p.t += dt;
            if (!p.due()) continue;
            p.live = false;
            const at = p.to;
            sfx.world(.druid_pod, at);
            elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .chaos, POD_BURST, 1.0);
            foe.spray(&self.parts, &self.fxHead, &self.fxRng, v3(at.x, at.y + POD_R1 * 0.6, at.z), v3(0, 1, 0), POD_SPLINTERS, 3.6, 1.0, SPLINTER_SPRAY);
            if (mathx.distXZ(at, hero) <= POD_R + foe.HERO_R) foe.worseBlow(worst, POD_HIT, at, &GROUND_THREAT);
        }
    }

    pub fn livePods(self: *const Coven) usize {
        var n: usize = 0;
        for (&self.pods) |*p| {
            if (p.live) n += 1;
        }
        return n;
    }

    /// The seconds of snare the frame owes him; read once by the game, like the shoal's net.
    pub fn takeSnare(self: *Coven) f32 {
        const s = self.pendingSnare;
        self.pendingSnare = 0;
        return s;
    }

    fn sowWhips(self: *Coven, d: *const Druidess) void {
        for (d.whipSpots) |spot| {
            const yaw = mathx.headingXZ(mathx.dirXZ(spot, d.castAt));
            self.plant(.{ .live = true, .kind = .whip, .at = spot, .yaw = yaw, .seed = self.fxRng.float() });
            sfx.world(.druid_sprout, spot);
        }
    }

    pub fn erupt(self: *Coven, at: rl.Vector3, hero: rl.Vector3, worst: *?foe.Blow) void {
        const caught = mathx.distXZ(at, hero) <= SNARE_R + foe.HERO_R;
        // `lashed` on a snare is "it has hold of someone": the stalks clutch harder for it.
        self.plant(.{ .live = true, .kind = .snare, .at = at, .seed = self.fxRng.float(), .lashed = caught });
        sfx.world(.druid_snare, at);
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .chaos, 10, 1.0);
        if (caught) {
            self.pendingSnare = mathx.maxF(self.pendingSnare, SNARE_HOLD);
            self.holdLeft = SNARE_HOLD;
            self.holdT = 0;
            self.holdAt = at;
            foe.worseBlow(worst, SNARE_HIT, at, &GROUND_THREAT);
        }
    }

    pub fn thrust(self: *Coven, from: rl.Vector3, yaw: f32) void {
        self.plant(.{ .live = true, .kind = .spear, .at = from, .yaw = yaw, .seed = self.fxRng.float() });
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, from, mathx.headingDir(yaw), .chaos, 8, 1.0);
    }

    fn plant(self: *Coven, v: Vine) void {
        var oldest: usize = 0;
        for (&self.vines, 0..) |*slot, i| {
            if (!slot.live) {
                slot.* = v;
                return;
            }
            if (slot.t > self.vines[oldest].t) oldest = i;
        }
        self.vines[oldest] = v;
    }

    pub fn tickVines(self: *Coven, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        for (&self.vines) |*v| {
            if (!v.live) continue;
            v.t += dt;
            if (v.spent()) {
                v.live = false;
                continue;
            }
            if (v.kind == .spear) {
                // Billed as the TIP PASSES HIM, once: the strip from her feet to wherever the point has got to this frame.
                if (!v.lashed and v.t <= SPEAR_STRIKE + dt) {
                    const tip = mathx.addV(v.at, mathx.scaleV(mathx.headingDir(v.yaw), v.extent()));
                    const q = mathx.closestOnSegV(v3(hero.x, v.at.y, hero.z), v.at, tip);
                    if (mathx.distXZ(q, hero) <= SPEAR_HALF_W + foe.HERO_R) {
                        v.lashed = true;
                        foe.worseBlow(worst, SPEAR_HIT, v.at, &GROUND_THREAT);
                    }
                }
                continue;
            }
            if (v.kind != .whip) continue;
            const life = v.t - WHIP_GROW;
            if (life < 0 or life >= WHIP_LIFE) continue;
            const n: u32 = @intFromFloat(@floor(life / WHIP_PERIOD));
            const into = life - @as(f32, @floatFromInt(n)) * WHIP_PERIOD;
            if (n != v.lashes) {
                v.lashes = n;
                v.lashed = false;
            }
            // It turns onto the man while it rears and holds its line through the strike: the tell is where it points.
            if (into < WHIP_TELL) {
                const to = mathx.dirXZ(v.at, hero);
                if (mathx.lenXZ(to) > 1e-4) v.yaw = mathx.approachAngle(v.yaw, mathx.headingXZ(to), WHIP_TURN * dt);
            } else if (!v.lashed) {
                v.lashed = true;
                sfx.world(.druid_whip, v.at);
                if (foe.inArc(v.at, v.yaw, hero, WHIP_REACH, WHIP_ARC)) foe.worseBlow(worst, WHIP_HIT, v.at, &GROUND_THREAT);
            }
        }
    }

    pub fn liveVines(self: *const Coven) usize {
        var n: usize = 0;
        for (&self.vines) |*v| {
            if (v.live) n += 1;
        }
        return n;
    }

    pub fn draw(self: *const Coven, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }

    pub fn drawFx(self: *const Coven) void {
        for (self.liveConst()) |*d| {
            d.drawFx();
            if (d.casting()) drawMark(d);
        }
        for (&self.vines) |*v| {
            if (!v.live) continue;
            switch (v.kind) {
                .whip => drawWhip(v),
                .snare => drawSnare(v),
                .spear => drawSpear(v),
            }
        }
        for (&self.pods) |*p| {
            if (p.live) drawPod(p);
        }
        foe.drawParticles(&self.parts);
    }

    pub fn pierce(self: *Coven, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Coven) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Coven) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Coven) u32 {
        return foe.aliveCount(self.liveConst());
    }
    pub fn soulsDropped(self: *const Coven) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
};

/// The buds through her wind, where the vines will stand: the ring for a snare, the three spots for the whips.
fn drawMark(d: *const Druidess) void {
    // THE SPEAR'S TELL IS HER BODY (owner), nothing on the ground: the coil, the arm drawn back, the hand pointing down the line. Only the orb marks the wind, and `drawFx` has it.
    if (d.state == .spear_wind) return;
    const wind: f32 = if (d.state == .vine_wind or d.state == .vine_cast) VINE_WIND else WHIP_WIND;
    const u = if (d.state == .vine_wind or d.state == .whip_wind) mathx.clampF(d.t / wind, 0, 1) else 1.0;
    const h = 0.08 + 0.30 * u;
    const col = mathx.withAlpha(CHAOS_EDGE, mathx.u8f(90.0 + 120.0 * u));
    if (d.state == .vine_wind or d.state == .vine_cast) {
        var i: u32 = 0;
        while (i < 8) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) / 8.0 * std.math.tau;
            const at = v3(d.castAt.x + mathx.cosf(a) * SNARE_R, d.castAt.y, d.castAt.z + mathx.sinf(a) * SNARE_R);
            rl.drawCylinderEx(at, v3(at.x, at.y + h, at.z), 0.05, 0.02, 5, VINE_DK);
            rl.drawSphereEx(v3(at.x, at.y + h, at.z), 0.05 + 0.03 * u, 5, 4, col);
        }
    } else {
        for (d.whipSpots) |s| {
            rl.drawCylinderEx(s, v3(s.x, s.y + h * 1.4, s.z), 0.07, 0.03, 5, VINE_DK);
            rl.drawSphereEx(v3(s.x, s.y + h * 1.4, s.z), 0.07 + 0.04 * u, 5, 4, col);
        }
    }
}

/// A pod on the ground: a dark shell over a glow that comes up through it as the fuse runs, on a stalk nub, beating.
fn drawPod(p: *const Pod) void {
    const at = p.at();
    const r = p.radius();
    const s = p.swell();
    rl.drawSphereEx(v3(at.x, at.y + r * 0.9, at.z), r, 7, 7, VINE_DK);
    rl.drawSphereEx(v3(at.x, at.y + r * 0.9, at.z), r * (0.55 + 0.42 * s), 6, 6, mathx.withAlpha(CHAOS_CORE, mathx.u8f(40.0 + 170.0 * s)));
    rl.drawCylinderEx(v3(at.x, at.y + r * 1.7, at.z), v3(at.x + 0.04, at.y + r * 1.7 + 0.12 + 0.08 * s, at.z), 0.025, 0.012, 5, VINE);
    if (s > 0.6) rl.drawSphereEx(v3(at.x, at.y + r * 0.9, at.z), r * (1.15 + 0.35 * (s - 0.6) / 0.4), 6, 6, mathx.withAlpha(CHAOS_EDGE, mathx.u8f(30.0 + 60.0 * (s - 0.6) / 0.4)));
}

fn drawWhip(v: *const Vine) void {
    const g = v.grown() * v.stand();
    if (g <= 0.01) return;
    const lash = v.lash();
    // Reared back the stalk pitches away from the man; whipped through it pitches at him, and the tip is what arrives. Between lashes it WRITHES — a slow bend and a sway, alive and not a post.
    const idle = 1.0 - mathx.minF(1.0, @abs(lash));
    const writhe = 8.0 * mathx.sinf(v.t * 2.3 + v.seed * 6.28) * idle;
    const sway = 7.0 * mathx.sinf(v.t * 1.7 + v.seed * 3.1) * idle;
    const bend: f32 = (if (lash < 0) 34.0 * lash else 74.0 * lash) + writhe;
    const fwd = mathx.headingDir(v.yaw + mathx.radians(sway));
    const segN: u32 = 5;
    const segLen = WHIP_H * g / @as(f32, @floatFromInt(segN));
    var p = v.at;
    var i: u32 = 0;
    while (i < segN) : (i += 1) {
        const share = (@as(f32, @floatFromInt(i)) + 1.0) / @as(f32, @floatFromInt(segN));
        // The bend lives in the upper stalk (share squared), so the root stands and the tip does the travelling.
        const pitch = mathx.radians(bend * share * share + 6.0 * mathx.sinf(v.seed * 20.0 + share * 7.0 + v.t * 0.9));
        const dir = v3(fwd.x * mathx.sinf(pitch), mathx.cosf(pitch), fwd.z * mathx.sinf(pitch));
        const q = mathx.addV(p, mathx.scaleV(dir, segLen));
        const r0 = (0.11 - 0.016 * @as(f32, @floatFromInt(i))) * g;
        const r1 = (0.095 - 0.016 * @as(f32, @floatFromInt(i))) * g;
        rl.drawCylinderEx(p, q, r0, r1, 6, if (i % 2 == 0) VINE else VINE_DK);
        rl.drawSphereEx(q, r1 * 1.25, 5, 5, VINE_DK);
        p = q;
    }
    // The bud lights through the rear-back and is brightest as it arrives.
    const heat = mathx.maxF(0, lash);
    const arm = mathx.maxF(0, -lash);
    rl.drawSphereEx(p, 0.10 * g * (1.0 + 0.6 * heat), 6, 5, VINE_TIP);
    if (arm > 0.05 or heat > 0.05) rl.drawSphereEx(p, 0.16 * g * (1.0 + heat), 6, 5, mathx.withAlpha(CHAOS_CORE, mathx.u8f(50.0 * arm + 90.0 * heat)));
}

fn spearHeight(s: f32) f32 {
    return SPEAR_RISE * mathx.smoothstep(0, 1.6, s);
}

/// Out of the ground at her feet, up to chest height inside the first metre and a half, and level to the point: a shaft, thick at the root and thin at the bud.
fn drawSpear(v: *const Vine) void {
    const ext = v.extent();
    if (ext <= 0.05) return;
    const dir = mathx.headingDir(v.yaw);
    const segN: u32 = 6;
    const thick = 0.4 + 0.6 * v.stand();
    // A wave runs down the shaft as it goes out, and the point RINGS once it has arrived: driven, then quivering, then still.
    const going = 1.0 - mathx.clampF(v.t / SPEAR_STRIKE, 0, 1);
    const since = mathx.maxF(0, v.t - SPEAR_STRIKE);
    const ring = 0.11 * mathx.sinf(since * 38.0) * @exp(-since * 7.0);
    var i: u32 = 0;
    var tip = v.at;
    while (i < segN) : (i += 1) {
        const s0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segN));
        const s1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segN));
        const wob = (0.04 + 0.12 * going) * mathx.sinf(v.seed * 9.0 + s1 * 11.0 - v.t * 30.0);
        const a = v3(v.at.x + dir.x * s0 * ext, v.at.y + spearHeight(s0 * ext) + ring * s0 * s0, v.at.z + dir.z * s0 * ext);
        const b = v3(v.at.x + dir.x * s1 * ext - dir.z * wob, v.at.y + spearHeight(s1 * ext) + ring * s1 * s1, v.at.z + dir.z * s1 * ext + dir.x * wob);
        const r0 = (0.15 - 0.10 * s0) * thick;
        const r1 = (0.15 - 0.10 * s1) * thick;
        rl.drawCylinderEx(a, b, r0, r1, 6, if (i % 2 == 0) VINE else VINE_DK);
        rl.drawSphereEx(b, r1 * 1.25, 5, 5, VINE_DK);
        tip = b;
    }
    rl.drawSphereEx(tip, 0.10 * thick, 6, 5, VINE_TIP);
}

fn drawSnare(v: *const Vine) void {
    // Up with an overshoot, then every stalk WRITHES on its own beat; with hold of someone they clutch — harder, faster, further in.
    const up = sproutCurve(mathx.clampF(v.t / 0.22, 0, 1)) * v.stand();
    if (up <= 0.01) return;
    const grip: f32 = if (v.lashed) 1.0 else 0.0;
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const a = fi / 8.0 * std.math.tau + v.seed * 0.7;
        const beat = mathx.sinf(v.t * (3.1 + 3.0 * grip) + fi * 1.3 + v.seed * 6.0);
        const r = SNARE_R * 0.86;
        const base = v3(v.at.x + mathx.cosf(a) * r, v.at.y, v.at.z + mathx.sinf(a) * r);
        const inward = v3(-mathx.cosf(a), 0, -mathx.sinf(a));
        const reachIn = (0.20 + 0.10 * grip) * up + 0.05 * beat * up;
        const knee = mathx.addV(base, v3(inward.x * reachIn, (0.62 + 0.06 * beat) * up, inward.z * reachIn));
        const curl = (0.55 + 0.25 * grip) * up + 0.08 * beat * up;
        const tip = mathx.addV(knee, v3(inward.x * curl, (0.30 - 0.12 * grip) * up * v.stand(), inward.z * curl));
        rl.drawCylinderEx(base, knee, 0.075 * up, 0.055 * up, 6, VINE_DK);
        rl.drawCylinderEx(knee, tip, 0.055 * up, 0.025 * up, 6, VINE);
        rl.drawSphereEx(tip, 0.06 * up, 5, 4, VINE_TIP);
        if (grip > 0) rl.drawSphereEx(tip, 0.10 * up, 5, 4, mathx.withAlpha(CHAOS_CORE, mathx.u8f(50.0 + 40.0 * beat)));
    }
}

fn orbMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD001);
    b.setMat(.marble);
    b.addBlob(ORB_AT, v3(ORB_R, ORB_R * 0.96, ORB_R), 6, 12, ORB_SHELL);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const t = rng.range(-0.6, 0.6);
        const out = ORB_R * 0.94;
        const p = v3(ORB_AT.x + mathx.cosf(a) * out * @sqrt(1.0 - t * t), ORB_AT.y + t * out, ORB_AT.z + mathx.sinf(a) * out * @sqrt(1.0 - t * t));
        b.addBlob(p, v3(ORB_R * 0.22, ORB_R * 0.14, ORB_R * 0.22), 3, 6, ORB_VEIN);
    }
    b.setMat(.flame);
    b.addBlob(ORB_AT, v3(ORB_R * 0.46, ORB_R * 0.46, ORB_R * 0.46), 4, 8, mathx.withAlpha(CHAOS_CORE, 200));
    // The talons of the hand it sits in.
    b.setMat(.skin);
    i = 0;
    while (i < 4) : (i += 1) {
        const a = -0.9 + 0.6 * @as(f32, @floatFromInt(i));
        const from = v3(ORB_AT.x + mathx.cosf(a) * ORB_R * 0.5, ORB_AT.y + ORB_R * 0.7, ORB_AT.z - ORB_R * 0.3);
        const to = v3(ORB_AT.x + mathx.cosf(a) * ORB_R * 1.02, ORB_AT.y + ORB_R * 0.1, ORB_AT.z + mathx.sinf(a) * ORB_R * 0.6);
        b.addCapsule(from, to, 0.0062 * H, 0.0046 * H, 5, SKIN_DK);
    }
    return b.toMesh();
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.086 * H, 0.076 * H, 0.072 * H), 4, 10, ROBE);
    b.addBlob(v3(0, -0.020 * H, -0.030 * H), v3(0.078 * H, 0.050 * H, 0.060 * H), 4, 9, ROBE_DK);
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD002);
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.080 * H, 0.084 * H, 0.066 * H), 4, 10, ROBE);
    b.addBlob(v3(0, 0.046 * H, 0), v3(0.084 * H, 0.056 * H, 0.068 * H), 4, 9, ROBE_LT);
    b.setMat(.leather);
    b.addCapsule(v3(-0.090 * H, -0.018 * H, 0.010 * H), v3(0.090 * H, -0.024 * H, 0.010 * H), 0.012 * H, 0.012 * H, 7, CORD);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const x = rng.range(-0.06, 0.06) * H;
        b.addCapsule(v3(x, -0.026 * H, 0.060 * H), v3(x + rng.signed() * 0.02 * H, -0.026 * H - rng.range(0.06, 0.13) * H, 0.066 * H), 0.007 * H, 0.005 * H, 5, CORD);
    }
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD003);
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.010 * H, 0), v3(0.084 * H, 0.086 * H, 0.066 * H), 4, 10, ROBE);
    b.addBlob(v3(0, 0.050 * H, -0.004 * H), v3(0.094 * H, 0.052 * H, 0.070 * H), 4, 10, ROBE_LT);
    // THE YOKE, or the arms hang in mid-air (the necromancer's rule): the shoulder joints stand at `SHOULDER_HALF` and the barrel does not reach them.
    const shx = SHOULDER_HALF * H;
    const shy = (0.818 - 0.760) * H;
    b.addCapsule(v3(-shx, shy, 0), v3(shx, shy, 0), 0.036 * H, 0.036 * H, 8, ROBE);
    // The cowl over the shoulders, a skirt hung from the collar.
    b.addSkirt(v3(0, 0.074 * H, 0), 0.062 * H, 0.096 * H, 0.118 * H, 0.008 * H, 10, ROBE_DK, &rng);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        b.addBlob(v3(mathx.cosf(a) * 0.070 * H, rng.range(-0.05, 0.03) * H, mathx.sinf(a) * 0.060 * H), v3(0.022 * H, 0.016 * H, 0.020 * H), 3, 6, ROT);
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.010 * H, 0), v3(0, 0.040 * H, 0.004 * H), 0.024 * H, 0.022 * H, 8, SKIN_DK);
    return b.toMesh();
}

fn hoodMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD004);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.020 * H, 0.012 * H), v3(0.046 * H, 0.054 * H, 0.050 * H), 5, 11, SKIN);
    b.addBlob(v3(0, -0.002 * H, 0.046 * H), v3(0.030 * H, 0.026 * H, 0.020 * H), 4, 8, SKIN_DK);
    b.addBlob(v3(0, -0.028 * H, 0.032 * H), v3(0.026 * H, 0.014 * H, 0.020 * H), 4, 8, SKIN_DK);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addBlob(v3(side * 0.020 * H, 0.012 * H, 0.050 * H), v3(0.012 * H, 0.008 * H, 0.008 * H), 3, 7, rgba(12, 10, 12, 255));
    }
    b.setMat(.flame);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addBlob(v3(side * 0.020 * H, 0.012 * H, 0.056 * H), v3(0.007 * H, 0.005 * H, 0.004 * H), 3, 6, EYE);
    }
    b.setMat(.cloth);
    // THE HOOD: a shell over the crown that stands proud at the front and falls to a peak behind.
    b.addBlob(v3(0, 0.040 * H, -0.010 * H), v3(0.066 * H, 0.062 * H, 0.070 * H), 5, 12, ROBE);
    b.addBlob(v3(0, 0.020 * H, -0.040 * H), v3(0.058 * H, 0.066 * H, 0.050 * H), 4, 10, ROBE_DK);
    b.addCapsule(v3(0, 0.070 * H, -0.030 * H), v3(0.010 * H * rng.signed(), 0.096 * H, -0.096 * H), 0.030 * H, 0.012 * H, 7, ROBE_DK);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addCapsule(v3(side * 0.052 * H, 0.030 * H, 0.030 * H), v3(side * 0.050 * H, -0.060 * H, 0.020 * H), 0.018 * H, 0.014 * H, 7, ROBE);
    }
    b.setMat(.plain);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const side: f32 = if (i % 2 == 0) 1.0 else -1.0;
        const x = side * rng.range(0.024, 0.044) * H;
        b.addCapsule(v3(x, -0.010 * H, 0.010 * H), v3(x + rng.signed() * 0.010 * H, -0.010 * H - rng.range(0.06, 0.12) * H, -0.004 * H), 0.006 * H, 0.004 * H, 5, HAIR);
    }
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_THIGH * H, 0), 0.050 * H, 0.040 * H, 9, ROBE_DK);
    b.addDome(v3(0, 0, 0), v3(0, 1, 0), 0.050 * H, 9, ROBE_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.100 * H, 0), 0.038 * H, 0.032 * H, 9, ROBE_DK);
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.095 * H, 0), v3(0, -heromod.SEG_SHANK * H, 0), 0.020 * H, 0.017 * H, 8, SKIN_DK);
    return b.toMesh();
}

fn sleeveMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xD005 else 0xD006);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.004 * H, 0), v3(0.032 * H, 0.030 * H, 0.030 * H), 4, 9, ROBE);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_UPARM * H, 0), 0.028 * H, 0.040 * H, 8, ROBE);
    // The sleeve hangs open below the elbow, torn and heavy.
    b.addSkirt(v3(0, -heromod.SEG_UPARM * H, 0), 0.040 * H, 0.070 * H, 0.056 * H, 0.006 * H, 8, ROBE_DK, &rng);
    return b.toMesh();
}

fn forearmMesh(side: f32) rl.Mesh {
    _ = side;
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.010 * H, 0), v3(0, -heromod.SEG_FOREARM * H, 0), 0.020 * H, 0.016 * H, 8, SKIN);
    b.addBlob(v3(0, -0.060 * H, 0.004 * H), v3(0.018 * H, 0.030 * H, 0.016 * H), 3, 7, SKIN_DK);
    return b.toMesh();
}

fn handMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xD007 else 0xD008);
    b.setMat(.skin);
    b.addBlob(v3(0, -0.026 * H, 0.006 * H), v3(0.020 * H, 0.026 * H, 0.016 * H), 4, 8, SKIN);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const x = (-1.5 + @as(f32, @floatFromInt(i))) * 0.0095 * H;
        const len = rng.range(0.034, 0.050) * H;
        b.addCapsule(v3(x, -0.046 * H, 0.010 * H), v3(x + rng.signed() * 0.003 * H, -0.046 * H - len, 0.018 * H), 0.0052 * H, 0.0038 * H, 5, SKIN_DK);
    }
    return b.toMesh();
}

/// From the hip down past the feet and OUT: this is the mass the creature reads as. `-0.030·H` under the sole plane is the drag.
fn hemMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD009);
    b.setMat(.cloth);
    const top = 0.010 * H;
    const bot = -0.030 * H - REST[ROOT].y;
    const hip = -0.20 * REST[ROOT].y;
    const knee = -0.56 * REST[ROOT].y;
    b.addSkirt(v3(0, top, 0), 0.080 * H, top - hip, 0.092 * H, 0.010 * H, 11, HEM, &rng);
    b.addSkirt(v3(0, hip, 0), 0.092 * H, hip - knee, 0.134 * H, 0.010 * H, 12, HEM, &rng);
    b.addSkirt(v3(0, knee, 0), 0.134 * H, knee - bot, 0.215 * H, 0.010 * H, 14, HEM, &rng);
    // Draped cords and torn strips, hung at the rim so the tangle has edges.
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const r0 = 0.10 * H;
        const r1 = rng.range(0.19, 0.24) * H;
        const from = v3(mathx.cosf(a) * r0, knee + rng.range(0.0, 0.06) * H, mathx.sinf(a) * r0);
        const to = v3(mathx.cosf(a + rng.range(-0.3, 0.3)) * r1, bot + rng.range(-0.01, 0.03) * H, mathx.sinf(a + rng.range(-0.3, 0.3)) * r1);
        b.addCapsule(from, to, 0.012 * H, 0.008 * H, 5, if (rng.float() < 0.5) ROBE_DK else ROT);
    }
    i = 0;
    while (i < 6) : (i += 1) {
        const a = rng.angle();
        const rr = 0.205 * H;
        b.addBlob(v3(mathx.cosf(a) * rr, bot + rng.range(0.006, 0.05) * H, mathx.sinf(a) * rr), v3(rng.range(0.016, 0.030) * H, rng.range(0.010, 0.020) * H, rng.range(0.014, 0.026) * H), 3, 7, if (rng.float() < 0.5) ROT else ROBE_LT);
    }
    return b.toMesh();
}

/// One tail of the tangle, authored in a frame at the ROOT pointing straight back (-Z): it drops off the hip to the ground and runs on along it.
fn trailMesh(comptime i: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD010 + i);
    b.setMat(.cloth);
    const len = TRAIL_LEN[i] * H;
    const bot = -0.030 * H - REST[ROOT].y;
    const side = rng.signed() * 0.03 * H;
    const pts = [_]rl.Vector3{
        v3(0, -0.03 * H, -0.10 * H),
        v3(side, -0.22 * H, -0.26 * H),
        v3(-side * 0.5, bot * 0.72, -0.44 * H),
        v3(side * 1.4, bot, -0.62 * H),
        v3(-side, bot + 0.004 * H, -0.62 * H - len * 0.42),
        v3(side * 0.6, bot + 0.002 * H, -0.62 * H - len),
    };
    var k: usize = 0;
    while (k + 1 < pts.len) : (k += 1) {
        const u = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(pts.len - 1));
        const ra = (0.062 - 0.040 * u) * H * rng.range(0.9, 1.1);
        const rb = (0.056 - 0.040 * (u + 0.2)) * H;
        b.addCapsule(pts[k], pts[k + 1], ra, mathx.maxF(rb, 0.010 * H), 7, if (k % 2 == 0) HEM else ROBE_DK);
        if (k >= 2) b.addBlob(pts[k], v3(0.030 * H, 0.020 * H, 0.032 * H), 3, 7, if (rng.float() < 0.5) ROT else ROBE_LT);
    }
    // Side tendrils off the run along the ground.
    var t: u32 = 0;
    while (t < 3) : (t += 1) {
        const at = mathx.lerpV(pts[3], pts[5], rng.range(0.1, 0.9));
        const out = rng.signed() * rng.range(0.06, 0.14) * H;
        b.addCapsule(at, v3(at.x + out, at.y + 0.004 * H, at.z - rng.range(0.02, 0.10) * H), 0.014 * H, 0.008 * H, 5, ROBE_DK);
    }
    return b.toMesh();
}

// ---------------------------------------------------------------------------------------------------------------

test "IT IS A BOSS, ON THE FOREST'S CURVE, AND ITS MARK STANDS INSIDE ITS HURT SPHERE" {
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(foe.isBoss(.druidess));
    try std.testing.expectEqual(foe.Nature.humanoid, foe.traitsOf(.druidess).nature);
    try std.testing.expect(d.alive() and !d.dying() and !d.staggered() and !d.airborne());
    const markOut = mathx.lenV(mathx.subV(d.centerWorld(), d.lockPoint()));
    std.debug.print("\n  druidess {d:.2} m tall; mark {d:.2} m off the hurt centre (sphere r {d:.2}, body r {d:.2}); orb {d:.2} m up\n", .{ d.topWorld().y - d.pos.y, markOut, d.hurtRadius(), d.bodyR(), d.orbWorld().y });
    try std.testing.expect(markOut < d.hurtRadius());
    try std.testing.expect(d.orbWorld().y > 0.8 and d.orbWorld().y < d.topWorld().y);
    try std.testing.expect(d.topWorld().y > 2.2);
}

test "SHE LEAVES BEFORE SHE CASTS — inside LEAP_R she goes up, hangs, travels far, and comes down with no speed left" {
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.leash.noteSeen();
    const hero = mathx.ground(0, 3.0);
    const dt: f32 = 1.0 / 120.0;
    var t: f32 = 0;
    var peak: f32 = 0;
    var airT: f32 = 0;
    var lastHop: f32 = 0;
    var touchdownSpeed: f32 = 0;
    var flew = false;
    while (t < arcTotal(LEAP_ARC) + 1.0) : (t += dt) {
        _ = d.update(dt, hero, 200.0, .{});
        if (d.state == .leap) flew = true;
        if (d.airborne()) {
            airT += dt;
            peak = @max(peak, d.hop);
            if (d.hop < 0.15 and lastHop > d.hop) touchdownSpeed = @max(touchdownSpeed, (lastHop - d.hop) / dt);
        }
        lastHop = d.hop;
    }
    const out = mathx.distXZ(d.pos, hero);
    std.debug.print("\n  druidess leap: {d:.2} s in the air, {d:.2} m up, over his head and down {d:.2} m past him; the last 15 cm come down no faster than {d:.2} m/s\n", .{ airT, peak, out, touchdownSpeed });
    try std.testing.expect(flew and d.overHead);
    try std.testing.expect(airT > 1.5);
    try std.testing.expect(peak > 1.8);
    try std.testing.expect(out > LEAP_R);
    try std.testing.expect(touchdownSpeed < 2.0);
    try std.testing.expect(d.leapCd > 0);
}

test "ONE LEAP PER COOLDOWN, COUNTED FROM TAKE-OFF — a man who keeps closing does not get her airborne again, and a stagger mid-air spends the leap all the same" {
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.leash.noteSeen();
    d.vineCd = 99;
    d.whipCd = 99;
    d.stepCd = 99;
    const dt: f32 = 1.0 / 60.0;
    var takeoffs: u32 = 0;
    var was = d.state;
    var t: f32 = 0;
    var first: ?f32 = null;
    var second: ?f32 = null;
    while (t < LEAP_CD * 1.6) : (t += dt) {
        // Always inside her leap ring, wherever she has got to, and in sight the whole while as `game.markSight` would have it.
        const hero = v3(d.pos.x, 0, d.pos.z + 3.0);
        d.leash.noteSeen();
        _ = d.update(dt, hero, 400.0, .{});
        if (d.state == .leap and was != .leap) {
            takeoffs += 1;
            if (first == null) first = t else if (second == null) second = t;
        }
        was = d.state;
    }
    std.debug.print("\n  druidess leaps: take-offs at {d:.2} s and {d:.2} s with a man never further than 3 m (cooldown {d:.1} s)\n", .{ first orelse -1.0, second orelse -1.0, LEAP_CD });
    try std.testing.expectEqual(@as(u32, 2), takeoffs);
    try std.testing.expect(second.? - first.? >= LEAP_CD - dt);

    var cut = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    cut.leash.noteSeen();
    cut.vineCd = 99;
    cut.whipCd = 99;
    cut.stepCd = 99;
    _ = cut.update(dt, mathx.ground(0, 3.0), 400.0, .{});
    try std.testing.expectEqual(State.leap, cut.state);
    cut.stagger(true);
    var s: f32 = 0;
    while (s < combat.FOE_HEAVY_STUN_DUR + 2.0) : (s += dt) {
        cut.leash.noteSeen();
        _ = cut.update(dt, v3(cut.pos.x, 0, cut.pos.z + 3.0), 400.0, .{});
        try std.testing.expect(cut.state != .leap);
    }
    try std.testing.expect(cut.leapCd > 0);
}

test "THE SIDESTEP ANSWERS A RUSH AND NOTHING ELSE — closing speed, never a press — and it has a cooldown" {
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.leash.noteSeen();
    d.leapCd = 99;
    d.vineCd = 99;
    d.whipCd = 99;
    const dt: f32 = 1.0 / 60.0;
    // A man STANDING inside the ring is not a rush, however close: she backs off him and never steps.
    var hero = mathx.ground(0, 3.0);
    var t: f32 = 0;
    while (t < 1.0) : (t += dt) {
        _ = d.update(dt, hero, 200.0, .{});
        try std.testing.expect(d.state != .step);
    }
    var stepped = false;
    var steps: u32 = 0;
    var was = d.state;
    var gap: f32 = 3.3;
    t = 0;
    while (t < STEP_CD * 0.8) : (t += dt) {
        gap -= 3.0 * dt;
        if (gap < 1.0) gap = 3.3;
        hero = v3(d.pos.x, 0, d.pos.z + gap);
        _ = d.update(dt, hero, 200.0, .{});
        if (d.state == .step and was != .step) steps += 1;
        was = d.state;
        if (d.state == .step) stepped = true;
    }
    std.debug.print("\n  druidess: a man rushing in at 3 m/s drew {d} sidestep(s) inside {d:.1} s of a {d:.1} s cooldown\n", .{ steps, STEP_CD * 0.8, STEP_CD });
    try std.testing.expect(stepped);
    try std.testing.expectEqual(@as(u32, 1), steps);
}

test "THE WHIPS LASH THE MAN WHERE HE STANDS, ON THEIR OWN CLOCK, AND WITHER — and have no body to hit" {
    var c = Coven{ .model = undefined };
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = mathx.ground(0, 8.0);
    d.vineCd = 99;
    d.debugWhip(hero);
    c.n = 1;
    c.band[0] = d;
    const dt: f32 = 1.0 / 120.0;
    var t: f32 = 0;
    var hits: u32 = 0;
    var sownAt: ?f32 = null;
    var most: usize = 0;
    while (t < WHIP_WIND + WHIP_CAST + WHIP_GROW + WHIP_LIFE + WITHER + 0.5) : (t += dt) {
        if (c.update(dt, hero, 200.0, .{})) |b| {
            if (b.hit.dmg == WHIP_HIT.dmg) hits += 1;
        }
        if (c.liveVines() > 0) {
            if (sownAt == null) sownAt = t;
            c.band[0].whipCd = 99;
        }
        most = @max(most, c.liveVines());
    }
    std.debug.print("\n  druidess whips: {d} stalks sown at {d:.2} s, {d} lashes taken standing still, all withered by {d:.1} s\n", .{ most, sownAt orelse -1.0, hits, t });
    try std.testing.expectEqual(WHIP_N, most);
    try std.testing.expect(hits >= 3);
    try std.testing.expectEqual(@as(usize, 0), c.liveVines());
    const shaft = foe.shaftThrough(v3(0, 1, 8), .{ .dmg = 10 });
    try std.testing.expect(!c.pierce(shaft));

    var away = Coven{ .model = undefined };
    var e = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    e.vineCd = 99;
    e.debugWhip(hero);
    away.n = 1;
    away.band[0] = e;
    var miss: u32 = 0;
    t = 0;
    while (t < WHIP_WIND + WHIP_CAST + WHIP_GROW + WHIP_LIFE) : (t += dt) {
        if (away.update(dt, mathx.ground(0, 8.0 + WHIP_SOW_MAX + WHIP_REACH + 1.0), 200.0, .{})) |_| miss += 1;
        if (away.liveVines() > 0) away.band[0].whipCd = 99;
    }
    try std.testing.expectEqual(@as(u32, 0), miss);
}

test "THE SNARE TAKES THE FEET OF WHOEVER STANDS IN THE RING, AND NOBODY OUTSIDE IT" {
    var c = Coven{ .model = undefined };
    var worst: ?foe.Blow = null;
    c.erupt(mathx.ground(0, 6.0), mathx.ground(0.8, 6.4), &worst);
    try std.testing.expect(worst != null);
    try std.testing.expectApproxEqAbs(SNARE_HOLD, c.takeSnare(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), c.takeSnare(), 1e-6);
    // …and it BITES while it holds: physical pulses through the hold and none after.
    const dt: f32 = 1.0 / 60.0;
    var bitten: f32 = 0;
    var pulses: u32 = 0;
    var t: f32 = 0;
    while (t < SNARE_HOLD + 1.0) : (t += dt) {
        if (c.holdDose(dt)) |b| {
            bitten += b.hit.dmg;
            pulses += 1;
            try std.testing.expect(b.hit.elem.total() == 0 and b.hit.poise == 0);
            try std.testing.expect(t <= SNARE_HOLD + dt);
        }
    }
    std.debug.print("\n  druidess snare: {d} pulses of {d:.0} through a {d:.1} s hold, {d:.0} HP in all\n", .{ pulses, SNARE_PULSE_HIT.dmg, SNARE_HOLD, bitten });
    try std.testing.expect(pulses >= 3 and bitten >= 9.0);
    try std.testing.expect(c.holdDose(dt) == null);

    var none: ?foe.Blow = null;
    c.erupt(mathx.ground(0, 6.0), mathx.ground(0, 6.0 + SNARE_R + foe.HERO_R + 0.2), &none);
    try std.testing.expect(none == null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), c.takeSnare(), 1e-6);
    try std.testing.expect(c.holdDose(dt) == null);
    try std.testing.expect(SNARE_HOLD < 2.0 * WHIP_PERIOD);
}

test "HER DAMAGE IS PHYSICAL, BUT THE WHIPS CUT WITH CHAOS THAT IS NOT VENOM — and the whips and the spear open him" {
    try std.testing.expect(SNARE_HIT.elem.total() == 0 and SPEAR_HIT.elem.total() == 0 and POD_HIT.elem.total() == 0 and SNARE_PULSE_HIT.elem.total() == 0);
    try std.testing.expect(WHIP_HIT.dmg > 0 and WHIP_HIT.elem.at(.chaos) > 0 and !WHIP_HIT.venom);
    try std.testing.expect(WHIP_HIT.dose.at(.bleed) > 0 and SPEAR_HIT.dose.at(.bleed) > 0);
    try std.testing.expect(SNARE_HIT.dose.at(.bleed) == 0 and POD_HIT.dose.at(.bleed) == 0);
    var man = combat.Vitals.init(300, 60, 60);
    _ = man.hit(WHIP_HIT);
    try std.testing.expectApproxEqAbs(@as(f32, 0), man.ail(.poison).meter, 1e-6);
    try std.testing.expectApproxEqAbs(WHIP_BLEED, man.ail(.bleed).meter, 1e-4);
    // Bleed is a BURST that goes off on the TICK after the meter fills, pays out flat and resets: the proc is the flag, not the state.
    var lashes: u32 = 1;
    _ = man.tickAils(1.0 / 60.0);
    var bled = man.ailProcced(.bleed);
    while (!bled and lashes < 12) : (lashes += 1) {
        _ = man.hit(WHIP_HIT);
        _ = man.tickAils(1.0 / 60.0);
        bled = man.ailProcced(.bleed);
    }
    std.debug.print("\n  druidess: a whip lash builds {d:.0} bleed of {d:.0}, the spear {d:.0}; standing in the whips he is opened by the {d}th lash\n", .{ WHIP_BLEED, combat.ailBank(.bleed).max, SPEAR_BLEED, lashes });
    try std.testing.expect(bled);
    try std.testing.expect(man.hp < 300 - WHIP_HIT.dmg * @as(f32, @floatFromInt(lashes)));
}

test "THE SPEAR COMES OUT AS YOU CLOSE — thrown for real at every stand in its band, never at a man standing still, and once per cooldown" {
    const dt: f32 = 1.0 / 120.0;
    for ([_]f32{ 2.2, 3.6, 5.0, 6.3 }) |stand| {
        var c = Coven{ .model = undefined };
        var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
        d.leapCd = 99;
        d.stepCd = 99;
        d.vineCd = 99;
        d.whipCd = 99;
        c.n = 1;
        c.band[0] = d;
        var hero = mathx.ground(0, stand + 0.4);
        var hit = false;
        var wound: ?f32 = null;
        var t: f32 = 0;
        while (t < 1.5) : (t += dt) {
            hero.z = mathx.maxF(0.9, hero.z - 1.5 * dt);
            c.band[0].leash.noteSeen();
            if (c.update(dt, hero, 400.0, .{})) |b| {
                if (b.hit.dmg == SPEAR_HIT.dmg) hit = true;
            }
            if (c.band[0].state == .spear_wind and wound == null) wound = t;
        }
        std.debug.print("\n  druidess spear at a {d:.1} m stand: wound at {d:.2} s, landed={}", .{ stand, wound orelse -1.0, hit });
        // The far stand starts outside the ring and walks into it; the near ones are inside from the first frame.
        try std.testing.expect(wound != null and wound.? < 0.25);
        try std.testing.expect(hit);
    }
    std.debug.print("\n", .{});

    var still = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    still.leapCd = 99;
    still.stepCd = 99;
    still.vineCd = 99;
    still.whipCd = 99;
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) {
        still.leash.noteSeen();
        _ = still.update(dt, mathx.ground(0, 4.0), 400.0, .{});
        try std.testing.expect(still.state != .spear_wind and still.state != .spear_cast);
    }

    var c = Coven{ .model = undefined };
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.leapCd = 99;
    d.stepCd = 99;
    d.vineCd = 99;
    d.whipCd = 99;
    c.n = 1;
    c.band[0] = d;
    var winds: u32 = 0;
    var was = c.band[0].state;
    var gap: f32 = 6.0;
    t = 0;
    while (t < SPEAR_CD * 0.9) : (t += dt) {
        gap -= 1.5 * dt;
        if (gap < 2.0) gap = 6.0;
        const hero = v3(c.band[0].pos.x, 0, c.band[0].pos.z + gap);
        c.band[0].leash.noteSeen();
        _ = c.update(dt, hero, 400.0, .{});
        if (c.band[0].state == .spear_wind and was != .spear_wind) winds += 1;
        was = c.band[0].state;
    }
    try std.testing.expectEqual(@as(u32, 1), winds);
}

test "THE CAST IS COMMITTED TO WHERE HE STOOD WHEN THE GATHER BEGAN — walk, and the ring comes up behind you" {
    var c = Coven{ .model = undefined };
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    var hero = mathx.ground(0, 8.0);
    d.whipCd = 99;
    d.debugVine(hero);
    c.n = 1;
    c.band[0] = d;
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    var snared: f32 = 0;
    var billed = false;
    while (t < VINE_WIND + VINE_CAST + 0.2) : (t += dt) {
        hero.z += 2.0 * dt;
        if (c.update(dt, hero, 200.0, .{})) |_| billed = true;
        snared = @max(snared, c.takeSnare());
    }
    std.debug.print("\n  druidess snare: the ring stood at 8.0 m, the man walked to {d:.2} m through a {d:.2} s gather; snared {d:.2} s\n", .{ hero.z, VINE_WIND, snared });
    try std.testing.expect(!billed);
    try std.testing.expectApproxEqAbs(@as(f32, 0), snared, 1e-6);
    try std.testing.expect(c.liveVines() == 1);
}

test "PHASE TWO AT HALF HEALTH: she calls a wave, leaps clear, and mends — and ONE blow ends it for good" {
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.leash.noteSeen();
    d.leapCd = 99;
    d.vineCd = 99;
    d.whipCd = 99;
    const hero = mathx.ground(0, 9.0);
    const dt: f32 = 1.0 / 60.0;
    d.vit.hp = HP_MAX * 0.45;
    var t: f32 = 0;
    var wave: ?Wave = null;
    var calls: u32 = 0;
    var retreatAir: f32 = 0;
    var farthest: f32 = 0;
    while (t < 8.0) : (t += dt) {
        _ = d.update(dt, hero, 200.0, .{});
        if (d.summoned) |w| {
            wave = w;
            calls += 1;
        }
        if (d.state == .retreat and d.airborne()) retreatAir += dt;
        farthest = @max(farthest, mathx.distXZ(d.pos, hero));
        if (d.state == .passive) break;
    }
    try std.testing.expectEqual(@as(u32, 1), calls);
    try std.testing.expect(wave != null);
    try std.testing.expect(retreatAir > 1.0);
    try std.testing.expectEqual(State.passive, d.state);
    const n = waveCount(wave.?);
    try std.testing.expect(n >= 2 and n <= WAVE_MAX);
    var i: u8 = 0;
    while (i < n) : (i += 1) {
        const spot = d.summonSpot(i, n);
        try std.testing.expectApproxEqAbs(SUMMON_R, mathx.distXZ(spot, d.pos), 1e-3);
    }
    const hpAtRest = d.vit.hp;
    var s: f32 = 0;
    while (s < 2.0) : (s += dt) _ = d.update(dt, hero, 200.0, .{});
    const mended = d.vit.hp - hpAtRest;
    std.debug.print("\n  druidess phase two: called {d} {s}, flew {d:.1} m out, mended {d:.1} HP in 2 s of channel ({d:.1}/s of {d:.0})\n", .{ n, wf.foeName(waveKind(wave.?)), farthest, mended, mended / 2.0, HP_MAX });
    try std.testing.expect(mended > HEAL_RATE * HP_MAX * 1.8);
    try std.testing.expectEqual(State.passive, d.state);

    const at = d.centerWorld();
    const shaft = foe.shaftThrough(at, heromod.BOW_QUICK_HIT);
    _ = d.update(dt, hero, 200.0, shaft);
    try std.testing.expect(d.hits == 1);
    try std.testing.expect(d.state != .passive);
    try std.testing.expect(d.healed and d.phase2);
    const hpStopped = d.vit.hp;
    s = 0;
    while (s < 6.0) : (s += dt) {
        _ = d.update(dt, hero, 200.0, .{});
        try std.testing.expect(d.summoned == null);
        try std.testing.expect(d.state != .passive and d.state != .summon_wind);
    }
    try std.testing.expect(d.vit.hp <= hpStopped + 1e-3);
}

fn squareRoom(half: f32) wf.Arena {
    var a = wf.Arena{ .n = 4, .nboss = 1 };
    a.boss[0] = .druidess;
    a.vx = [_]f32{0} ** wf.MAX_ARENA_VERTS;
    a.vz = [_]f32{0} ** wf.MAX_ARENA_VERTS;
    a.vx[0] = -half;
    a.vz[0] = -half;
    a.vx[1] = half;
    a.vz[1] = -half;
    a.vx[2] = half;
    a.vz[2] = half;
    a.vx[3] = -half;
    a.vz[3] = half;
    return a;
}

test "SHE NEVER LEAVES THE ROOM — cornered against the wall she leaps OVER HIS HEAD, a retreat is cut to the room, and a drift turns along the wall" {
    const dt: f32 = 1.0 / 120.0;
    const room = squareRoom(10.0);

    // Open ground both ways: she goes OVER HIM, readily — that is her first answer.
    var free = Druidess.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    free.room = room;
    free.leash.noteSeen();
    _ = free.update(dt, mathx.ground(0, 3.0), 400.0, .{});
    try std.testing.expectEqual(State.leap, free.state);
    try std.testing.expect(free.overHead and free.moveDir.z > 0);

    // HE is against the wall: past him is out of the room, so she goes back.
    var backed = Druidess.spawn(mathx.ground(0, 4.0), 0, 1.0, 0.3);
    backed.room = room;
    backed.leash.noteSeen();
    _ = backed.update(dt, mathx.ground(0, 7.0), 400.0, .{});
    try std.testing.expectEqual(State.leap, backed.state);
    try std.testing.expect(!backed.overHead and backed.moveDir.z < 0);

    // WATER past him (the bench's probe: everything north of z = 5 is deep), so she goes back onto dry ground.
    const Bench = struct {
        fn depth(_: *const anyopaque, _: f32, z: f32) f32 {
            return if (z > 5.0) 2.0 else 0.0;
        }
    };
    var dry = Druidess.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    dry.ground = .{ .ctx = @ptrCast(&dry), .depthAt = Bench.depth };
    dry.leash.noteSeen();
    _ = dry.update(dt, mathx.ground(0, 3.0), 400.0, .{});
    try std.testing.expectEqual(State.leap, dry.state);
    try std.testing.expect(!dry.overHead and dry.moveDir.z < 0);
    try std.testing.expect(dry.ground.depth(dry.landing(dry.moveDir, dry.arc.dist).x, dry.landing(dry.moveDir, dry.arc.dist).z) <= DRY_MAX);
    // …and with the water behind HER instead, over him is the dry way.
    var shore = Druidess.spawn(mathx.ground(0, 3.0), 0, 1.0, 0.3);
    shore.ground = .{ .ctx = @ptrCast(&shore), .depthAt = Bench.depth };
    shore.leash.noteSeen();
    _ = shore.update(dt, mathx.ground(0, 0.0), 400.0, .{});
    try std.testing.expectEqual(State.leap, shore.state);
    try std.testing.expect(shore.overHead and shore.moveDir.z < 0);

    // The wall at her back: the only landing inside the room is past him.
    var pinned = Druidess.spawn(mathx.ground(0, -8.0), 0, 1.0, 0.3);
    pinned.room = room;
    pinned.leash.noteSeen();
    const hero = mathx.ground(0, -5.0);
    _ = pinned.update(dt, hero, 400.0, .{});
    try std.testing.expectEqual(State.leap, pinned.state);
    try std.testing.expect(pinned.overHead and pinned.moveDir.z > 0);
    var nearest: f32 = 1e9;
    var hopOver: f32 = 0;
    var t: f32 = 0;
    while (t < arcTotal(LEAP_ARC) + 0.5) : (t += dt) {
        pinned.leash.noteSeen();
        _ = pinned.update(dt, hero, 400.0, .{});
        const gap = mathx.distXZ(pinned.pos, hero);
        if (gap < nearest) {
            nearest = gap;
            hopOver = pinned.hop;
        }
        try std.testing.expect(room.contains(pinned.pos.x, pinned.pos.z));
    }
    std.debug.print("\n  druidess cornered: went over his head {d:.2} m up at {d:.2} m off him, landed at z {d:.2} inside a ±10 room\n", .{ hopOver, nearest, pinned.pos.z });
    try std.testing.expect(nearest < 1.0 and hopOver > 1.5);
    try std.testing.expect(pinned.pos.z > hero.z + 3.0);

    // A retreat that would clear the room is cut to what the room has.
    var small = Druidess.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    small.room = squareRoom(6.0);
    small.startArc(RETREAT_ARC, mathx.ground(0, 3.0), .retreat);
    std.debug.print("  druidess retreat in a ±6 room: {d:.1} m of the {d:.1} m arc\n", .{ small.arc.dist, RETREAT_ARC.dist });
    try std.testing.expect(small.arc.dist < RETREAT_ARC.dist);
    try std.testing.expect(small.room.?.contains(small.landing(small.moveDir, small.arc.dist).x, small.landing(small.moveDir, small.arc.dist).z));

    // Chased along the wall for ten seconds with every dodge on cooldown, she drifts and never crosses it.
    var walker = Druidess.spawn(mathx.ground(0, 8.0), 0, 1.0, 0.3);
    walker.room = room;
    walker.leapCd = 99;
    walker.stepCd = 99;
    walker.vineCd = 99;
    walker.whipCd = 99;
    walker.spearCd = 99;
    t = 0;
    while (t < 10.0) : (t += dt) {
        walker.leash.noteSeen();
        const chaser = v3(walker.pos.x, 0, walker.pos.z - 5.0);
        _ = walker.update(dt, chaser, 400.0, .{});
        try std.testing.expect(room.contains(walker.pos.x, walker.pos.z));
    }
}

test "THE PODS GO OUT AS SHE LEAVES, LAND BETWEEN HER AND THE MAN, SWELL, AND POP ON THE ONE STANDING THERE" {
    var c = Coven{ .model = undefined };
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.leash.noteSeen();
    c.n = 1;
    c.band[0] = d;
    const dt: f32 = 1.0 / 120.0;
    var hero = mathx.ground(0, 3.0);
    _ = c.update(dt, hero, 400.0, .{});
    try std.testing.expectEqual(State.leap, c.band[0].state);
    try std.testing.expectEqual(POD_N, c.livePods());
    var i: usize = 0;
    var toward: usize = 0;
    while (i < POD_N) : (i += 1) {
        const p = c.pods[i];
        const out = mathx.distXZ(p.to, mathx.zero3);
        try std.testing.expect(out >= POD_SCATTER_MIN - 1e-3 and out <= POD_SCATTER_MAX + 1e-3);
        if (p.to.z > 0) toward += 1;
    }
    try std.testing.expectEqual(POD_N, toward);
    // Stand on the first pod's spot and take the pop.
    hero = c.pods[0].to;
    var hit = false;
    var poppedAt: ?f32 = null;
    var swelled: f32 = 0;
    var t: f32 = dt;
    while (t < POD_FLIGHT + POD_FUSE + 0.5) : (t += dt) {
        c.band[0].leash.noteSeen();
        if (c.pods[0].live) swelled = @max(swelled, c.pods[0].radius());
        if (c.update(dt, hero, 400.0, .{})) |b| {
            if (b.hit.dmg == POD_HIT.dmg) {
                hit = true;
                if (poppedAt == null) poppedAt = t;
            }
        }
    }
    std.debug.print("\n  druidess pods: {d} thrown, swelled to r {d:.2} m, popped at {d:.2} s (flight {d:.2} + fuse {d:.2})\n", .{ POD_N, swelled, poppedAt orelse -1.0, POD_FLIGHT, POD_FUSE });
    try std.testing.expect(hit);
    try std.testing.expect(swelled > POD_R1 * 0.9);
    try std.testing.expect(poppedAt.? >= POD_FLIGHT + POD_FUSE - 2.0 * dt);
    try std.testing.expectEqual(@as(usize, 0), c.livePods());
}

test "THE ARC LANDS WHERE IT SAYS: the ground covered is the whole distance and the last of it is covered slowly" {
    for ([_]Arc{ LEAP_ARC, RETREAT_ARC }) |a| {
        const total = arcTotal(a);
        try std.testing.expectApproxEqAbs(a.dist, arcAlong(a, total), 1e-4);
        try std.testing.expectApproxEqAbs(@as(f32, 0), arcHop(a, total), 1e-4);
        try std.testing.expectApproxEqAbs(a.up, arcHop(a, a.rise + a.hang * 0.5), 1e-4);
        const tail = arcAlong(a, total) - arcAlong(a, total - 0.1);
        const mid = arcAlong(a, total * 0.5 + 0.05) - arcAlong(a, total * 0.5 - 0.05);
        try std.testing.expect(tail < mid * 0.25);
    }
}

test "THE TANGLE RINGS PAST HER TURN AND SETTLES ON IT — springs, not eases" {
    var d = Druidess.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.facing = mathx.radians(90.0);
    const dt: f32 = 1.0 / 120.0;
    var over: f32 = 0;
    var t: f32 = 0;
    while (t < 3.0) : (t += dt) {
        d.tickTrails(dt, 0);
        for (d.trailYaw) |y| over = @max(over, y - d.facing);
    }
    std.debug.print("\n  druidess tangle: overshot the turn by {d:.1} deg, settled within {d:.2} deg\n", .{ mathx.degrees(over), mathx.degrees(@abs(d.trailYaw[1] - d.facing)) });
    try std.testing.expect(over > mathx.radians(3.0));
    for (d.trailYaw) |y| try std.testing.expect(@abs(y - d.facing) < mathx.radians(1.5));
}
