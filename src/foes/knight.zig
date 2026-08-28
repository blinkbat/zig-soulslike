const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const anim = @import("../core/anim.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const archermod = @import("archer.zig");
const ogremod = @import("ogre.zig");
const propart = @import("../props/propart.zig");
const elemfx = @import("../gfx/elemfx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// Solved on the chain: screen ~22.7 x albedo^(1/2.2) on the chest, ~30.3 on the door; rims 43 -> 58 -> 80 -> 112.
const IRON = rgba(13, 15, 20, 255);
const IRON_LT = rgba(42, 46, 54, 255);
const IRON_MD = rgba(22, 25, 31, 255);
const IRON_DK = rgba(6, 7, 10, 255);
/// Not `propart.RUST`: at 2.5 m the door's rims land it at 178 on screen. Solved back down to near 120.
const RUST = rgba(24, 16, 10, 255);
const BRASS = rgba(66, 51, 22, 255);
const STRAP = rgba(34, 26, 19, 255);
const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
const BONE_LT = archermod.BONE_LT;
/// Solved to near 140: over the plate's brightest rim (112), under the ground (126) on hue.
const KBONE = rgba(57, 52, 44, 255);
const KBONE_LT = rgba(90, 83, 70, 255);
const KBONE_DK = rgba(30, 27, 23, 255);
const EMBER = rgba(228, 118, 52, 54);
const SOCKET = rgba(12, 10, 9, 255);
const EMBER_MARK = rgba(232, 122, 46, 235);
/// Its fire is LIGHT — drawn additive, and cooling through this as it climbs off the ring.
const EMBER_MARK_COOL = rgba(158, 40, 14, 120);

const DUST = foe.DUST;
const CHIP = archermod.BONE_CHIP;
const CHIP_SPRAY = archermod.boneChips(1.2);
const SPARK = rgba(255, 206, 126, 240);
const SPARK_COOL = rgba(226, 116, 38, 200);

const PLATE = gfx.Mat.plain;
const BRIGHT = gfx.Mat.steel;

const TRAIL_N = 24;
const TRAIL_LIFE = 0.13;
const TRAIL_ROOT = 0.46;
const TRAIL_PEAK = 88.0;

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
const WPN = heromod.HELD;

const H: f32 = heromod.H;
const HIP_HALF = 0.112;
const SHOULDER_HALF = 0.216;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;

pub const SCALE = ogremod.SCALE * 1.28;

/// MEASURED off `footMesh`; `hero.legChain` levels the ankle against it every frame.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.064 * H, .toe = 0.200 * H, .halfW = 0.063 * H, .drop = 0.041 * H },
    .{ .bone = ANKR, .heel = 0.064 * H, .toe = 0.200 * H, .halfW = 0.063 * H, .drop = 0.041 * H },
};

pub const AGGRO_R = 22.0;
/// **OVER A SPRINT'S OWN RATE ABOUT HIM, AND UNDER THE OGRE'S 3.4** — he cannot be out-circled either. What
/// leaves a window is the COMMIT (`Attack.track`), never the flank.
const TURN_RATE = 3.20;
/// Under `TURN_RATE`, or there is no window. The heavy rows' default: they let go across a commit, where the
/// quick rows hold you and the overhead lets go entirely.
const SWING_TURN = 2.20;
/// 51 deg of correction over the 1.45 s tell, into a 70-deg sector subtending ~25 either side.
const FALL_AIM = 0.62;
/// Strides are the shared gait at his scale: 4.4 m a cycle, a footfall every 1.5 s.
const WALK_SPEED = heromod.WALK_SPEED * 0.94;

const BODY_R = 0.60; // ground footprint, PRE-SCALE
const HURT_R = 0.78; // pre-scale
/// In the PELVIS BONE's own frame, not a height off his feet.
const CENTER_AT = v3(0, 0.02 * H, 0);
const LOCK_AT = v3(0, -0.03 * H, 0);
const TOP_AT = v3(0, 0.088 * H, 0);

const TOWER_ARC = towerArc();
fn towerArc() f32 {
    // Measured: 2.7 m of plank 0.8 m out occludes about 35 deg either side.
    const half = @max(SH_CHORD_L, SH_CHORD_R);
    const out = CHEST_FRONT_Z + SH_STANDOFF + SH_CURVE_R * @cos(SH_ARC_L);
    return combat.subtendedArc(half, out) + TOWER_SWEPT_ALLOW;
}
const TOWER_SWEPT_ALLOW = 17.0;
/// **OAK ANSWERS A BLADE BETTER THAN IT ANSWERS A SPELL** (owner) — over the hero's own `GUARD_NEGATE` (0.85)
/// against steel, well under it against anything thrown, so a rod is the way through his front.
const TOWER_NEGATE: f32 = 0.90;
const TOWER_NEGATE_ELEM: f32 = 0.60;
comptime {
    std.debug.assert(TOWER_NEGATE_ELEM < TOWER_NEGATE);
    std.debug.assert(TOWER_NEGATE < 1.0 and TOWER_NEGATE_ELEM > 0);
}
/// ELDEN_RING.md §7's stance loop: 80 stance, ~13/s regen, a ~6 s pressure window ending in a critical.
const TOWER_STANCE_PASS: f32 = 0.15;

/// Opens inside the first third — the blade lands at `impactK` 0.22-0.55 — and shuts in the LAST quarter of the
/// recover: the sword comes home first (`RECOVER_BACK_K`), then the door, or the two meet in front of him.
const SWIPE_OPEN_K: f32 = 0.30;
/// **THE DOOR IS HAULED ASIDE IN THE GATHER, NOT ON THE FRAME THE BLADE ARRIVES** (owner: it flies around off his
/// hand like a kite). Share of the WIND the haul is spread over, and how far it gets by the strike. Measured
/// before: the whole 96 deg of `SWIPE_ABD` plus 82 of yaw went in 0.126 s — 762 deg/s, which is a snap and not a
/// motion. `SWIPE_LEAD_TO` stays under `guardUp`'s 0.5 threshold, so the PICTURE leads and the MECHANIC does not
/// move: the flag can never claim the plank is aside before it is.
const SWIPE_LEAD_K: f32 = 0.55;
const SWIPE_LEAD_TO: f32 = 0.45;
/// Per second, so it is also the CEILING on how fast the plank may ever be hauled: 3.5 of the swipe's 96 deg of
/// abduction plus 82 of yaw is about 340 deg/s at the very worst, against the 762 the snap was doing.
const DOOR_EASE: f32 = 3.5;
/// Degrees a second the plank's FACE may turn on his arm — the last word over every pose, so no seam anywhere
/// can spin it. 300 is a shoulder throwing it hard; 113 deg in a single frame is 6780, which is what it was doing.
const DOOR_TURN_MAX: f32 = 300.0;
const SWIPE_SHUT_K0: f32 = 0.44;
const SWIPE_SHUT_K1: f32 = 0.88;
/// The recover's shape for every sword stroke: the End Pose HELD to here, then the sword PARKED out on his right
/// (`P_PARK`) from `RECOVER_BACK_K` to `RECOVER_PARK_TO` while the door swings home across the front, and only
/// then into the carry. The sword's road home is UP now (`CARRY_TILT` 150), which is what let `RECOVER_BACK_K`
/// come down and gave the shut its time; on the old Pflug carry the hilt sat at the door's right edge and a
/// sword coming home while the plank was still moving met it.
const RECOVER_HOLD_K: f32 = 0.22;
const RECOVER_BACK_K: f32 = 0.40;
const RECOVER_PARK_TO: f32 = 0.90;
const P_PARK = P{ .armSh = CARRY_SH - 10.0, .armAbd = CARRY_ABD + 18.0, .lean = GUARD_LEAN + 3.0, .brace = 0.34 };
comptime {
    std.debug.assert(RECOVER_BACK_K < SWIPE_SHUT_K0 and SWIPE_SHUT_K1 <= RECOVER_PARK_TO);
}
/// In the shoulder's own degrees. **OUT LEFT AND BACK, EDGE-ON** (owner: the sword was going through the shield):
/// pitched back 40 and out 52 the plank hung where every stroke now finishes (0.10 m off the blade); RAISED it
/// swung over his head onto his sword side, because the door hangs 3.7 m below the fist. Behind the left
/// shoulder plane nothing he throws forward can meet it. A test measures the gap through the whole stroke.
const SWIPE_SH: f32 = 70.0;
/// NEGATIVE: on the left arm a positive abduction channel folds it ACROSS the chest (the guard's pull), so out to
/// his left is the other sign. At +52 the "open" door was hauled onto his sword side.
const SWIPE_ABD: f32 = -96.0;
const SWIPE_YAW: f32 = 82.0;

const FALL_SECTOR = 70.0;

/// Gates nothing by itself — each move answers for its own front (`Attack.bearing`, `weigh`); the law at the foot of this file is pinned on it.
/// Under what the ram subtends at its 2.7 m arrival (~20 deg).
const SWING_BEARING = 19.0;


const Chan = [Knight.CHAN_N]f32;

const P = struct {
    brace: f32 = 0.16,
    lean: f32 = GUARD_LEAN,
    twist: f32 = GUARD_TWIST,
    head: f32 = 3.0,
    armSh: f32 = CARRY_SH,
    offSh: f32 = GUARD_SH,
    armAbd: f32 = CARRY_ABD,
    offAbd: f32 = GUARD_ABD,
    armSweep: f32 = CARRY_SWEEP,
    armEl: f32 = CARRY_EL,
    offEl: f32 = GUARD_EL,
    tilt: f32 = CARRY_TILT,

    pub fn chan(self: P) Chan {
        var c: Chan = undefined;
        c[Knight.CH_BRACE] = self.brace;
        c[Knight.CH_LEAN] = self.lean;
        c[Knight.CH_TWIST] = self.twist;
        c[Knight.CH_HEAD] = self.head;
        c[Knight.CH_ARM_SH] = self.armSh;
        c[Knight.CH_OFF_SH] = self.offSh;
        c[Knight.CH_ARM_ABD] = self.armAbd;
        c[Knight.CH_OFF_ABD] = self.offAbd;
        c[Knight.CH_ARM_SWEEP] = self.armSweep;
        c[Knight.CH_ARM_EL] = self.armEl;
        c[Knight.CH_OFF_EL] = self.offEl;
        c[Knight.CH_TILT] = self.tilt;
        return c;
    }
};

const PoseKey = anim.Pose(P).PoseKey;
const samplePose = anim.Pose(P).sample;

const SPRING_STIFF: f32 = 1900.0; // period ~0.14 s, inside the 0.22 s bash
const SPRING_ZETA: f32 = 0.72;
const SPRING_FALLOFF: f32 = 0.94;
const SPRING_STIFF_DOWN: f32 = 2800.0;

const MoveKeys = struct {
    wind: []const PoseKey,
    strike: []const PoseKey,
    recover: []const PoseKey,
};

const Weight = enum {
    light,
    heavy,
    crushing,

    fn ember(self: Weight) f32 {
        return switch (self) {
            .light => 0,
            .heavy => 0.55,
            .crushing => 1.0,
        };
    }
};

const Attack = struct {
    /// PRE-SCALE, MEASURED off the posed kit at the impact frame (a test re-measures it).
    reachOut: f32,
    windDur: f32,
    strikeDur: f32,
    impactK: f32,
    recoverDur: f32,
    cd: f32,
    hit: combat.Hit,
    weight: Weight,
    bearing: f32,
    /// rad/s once committed. A property of the MOVE: quick rows may exceed `TURN_RATE`, heavy rows may not.
    track: f32 = SWING_TURN,
    /// **METRES THE STROKE CARRIES HIM FORWARD, PRE-SCALE** — the LUNGE, on top of the kit's own reach (`bandR`).
    step: f32 = 0,
    /// **THE SHARE OF THE LUNGE LANDED WHEN THE KIT CROSSES HIS FRONT, MEASURED.** A held End Pose keeps the kit
    /// out to the end of the stroke (1.0); a sweep passes the front ONCE, part way through its step, and the
    /// rest of the lunge is reach the far stand never sees.
    stepLands: f32 = 1.0,
    /// **THE DEAD ZONE, PRE-SCALE, MEASURED** — the nearest stand the kit crosses with the lunge taken. A stroke
    /// whose point drops 5 m out is thrown OVER a man at his boots; inside this the AI does not pick it.
    reachIn: f32 = 0,
};

fn nearR(a: Attack, scale: f32) f32 {
    return a.reachIn * scale;
}

// The Anor Londo Sentinel's kit (docs/GIANT_KNIGHTS.md) on the ER knight brain (docs/ELDEN_RING.md §7).

const SWEEP = Attack{
    .reachOut = 1.27, // MEASURED down his facing while live: 3.72 m (5.8 m out on the flank, which is not where the aimed man stands)
    // Winds are up ~15% across the kit (owner: more windup now that they can hit — more predictable).
    .windDur = 1.15,
    .strikeDur = 0.42,
    .impactK = 0.22,
    .recoverDur = 1.35,
    .cd = 3.60,
    .hit = SWEEP_HIT,
    .weight = .heavy,
    .bearing = SWEEP_BEARING,
    .track = 2.00,
    .step = 0.40,
    // MEASURED: the blade crosses his front at k 0.64 of the strike, when the step's ease has landed 0.87 of it.
    .stepLands = 0.87,
};

const SWEEP2 = Attack{
    .reachOut = 1.28, // MEASURED down his facing while live: 3.75 m
    // FLOORED: `foe.PARRY_LEAD` (0.18 s) may never be more than about a fifth of a wind.
    .windDur = 0.58,
    .strikeDur = 0.34,
    .impactK = 0.25,
    .recoverDur = 1.40,
    .cd = 3.60,
    .hit = SWEEP2_HIT,
    .weight = .heavy,
    .bearing = SWEEP_BEARING,
    .track = 2.00,
    .step = 0.34,
    // MEASURED like the sweep's: a forehand off the same snap crosses his front with most of the step landed.
    .stepLands = 0.80,
};

const OVERHEAD = Attack{
    .reachOut = 0.96, // MEASURED down his facing: 2.83 m for the kit alone — the LUNGE (`step`) is what carries the drop out
    .windDur = 1.00,
    .strikeDur = 0.30,
    .impactK = 0.55,
    .recoverDur = 1.50,
    .cd = 4.50,
    .hit = OVERHEAD_HIT,
    .weight = .crushing,
    .bearing = 56.0,
    // "Very poor tracking" (docs/GIANT_KNIGHTS.md): the line is committed at the drop.
    .track = 0.0,
    // Tracking stays 0, so the BODY carries the drop to you instead.
    .step = 0.55,
    // MEASURED: the blade is in the earth by k 0.55; the last of the lunge does not move where it landed.
    .stepLands = 0.90,
};

const THRUST = Attack{
    .reachOut = 1.42, // MEASURED down his facing while live: 4.16 m — the step is on top (`thrustBandR`)
    .windDur = 0.62,
    .strikeDur = 0.26,
    .impactK = 0.55,
    .recoverDur = 0.95,
    .cd = 1.80,
    .hit = THRUST_HIT,
    .weight = .light,
    .bearing = 54.0,
    .track = 4.40,
    // A POKE, not a lunge (was 0.60): the long step carried his fist PAST a man inside 4 m, and the point is
    // only out at full stretch for an instant, so a promised lunge was reach the far stand never saw.
    .step = 0.16,
    .reachIn = 0.90,
};

/// **WHERE A MOVE REACHES FROM** — the kit plus its lunge. `triggerR` is the kit alone, which is what the parry
/// window and the hurt shape want; this is what the AI picks at, and they differ for every stroke that steps.
fn bandR(a: Attack, scale: f32) f32 {
    return triggerR(a, scale) + a.step * a.stepLands * scale;
}

fn thrustBandR(scale: f32) f32 {
    return bandR(THRUST, scale);
}

/// **THE SHIELD-SIDE SWAT IS THE DOOR'S REACH, NOT THE SWORD'S** — one row, two kits. The door flicks at the
/// bash's range; asked off the sword's 4.96 m a shield-side flanker at 4 m drew a flick that could not reach him.
/// PRE-SCALE, MEASURED down his facing while live: the door's flick arrives 2.10 m out.
const SWAT_SHIELD_REACH_OUT: f32 = 0.72;
fn swatTriggerR(shieldSide: bool, scale: f32) f32 {
    return if (shieldSide) foe.hurtReach(SWAT_SHIELD_REACH_OUT, scale) else triggerR(SWAT, scale);
}
fn strokeBandR(mv: usize, shieldSide: bool, scale: f32) f32 {
    if (mv == SWAT_I and shieldSide) return swatTriggerR(true, scale);
    return bandR(MOVES[mv], scale);
}

const BASH = Attack{
    .reachOut = 0.94, // MEASURED down his facing while live: the door's face arrives 2.78 m off his axis
    .windDur = 0.64,
    .strikeDur = 0.22,
    .impactK = 0.44,
    .recoverDur = 0.85,
    .cd = 2.60,
    .hit = BASH_HIT,
    .weight = .light,
    // `SH_RAM_HALF` subtends ~20 deg at the 2.7 m it arrives.
    .bearing = 20.0,
    // Its own test measures the lateral miss: it may not be out-turned inside its own 0.22 s.
    .track = 4.00,
    .step = 0.52,
};

const SWAT = Attack{
    // MEASURED down his facing: 3.23 m. A flick round the hip, not a reach — the flank punish and the boots-band quick blow.
    .reachOut = 1.10,
    .windDur = 0.60,
    .strikeDur = 0.16,
    .impactK = 0.40,
    .recoverDur = 0.42,
    .cd = 1.50,
    .hit = SWAT_HIT,
    .weight = .light,
    .bearing = FLANK_BEARING,
    .track = 4.80,
};
// Up ~12% (owner: a bit more damage, now that they land) — the `Weight` rule still caps a HEAVY under 34.
pub const SWAT_HIT = combat.Hit{ .dmg = 16, .poise = 22, .stance = 6 };

pub const SWEEP_HIT = combat.Hit{ .dmg = 33, .poise = 42, .stance = 14 };
pub const SWEEP2_HIT = combat.Hit{ .dmg = 29, .poise = 36, .stance = 12 };
pub const OVERHEAD_HIT = combat.Hit{ .dmg = 46, .poise = 50, .stance = 20 };
pub const THRUST_HIT = combat.Hit{ .dmg = 25, .poise = 26, .stance = 8 };
pub const BASH_HIT = combat.Hit{ .dmg = 30, .poise = 36, .stance = 12 };

const SLAM = struct {
    windDur: f32,
    strikeDur: f32,
    impactK: f32,
    recoverDur: f32,
    cd: f32,
    fwd: f32, // pre-scale
    r: f32, // pre-scale
    hit: combat.Hit,
}{
    // A run clears the crater's disc inside the tell and a walk deliberately must not (pinned by a test).
    .windDur = 1.22,
    .strikeDur = 0.42,
    .impactK = 0.50,
    .recoverDur = 1.70,
    .cd = 8.00,
    .fwd = 0.62,
    .r = 1.28,
    .hit = SLAM_HIT,
};
pub const SLAM_HIT = combat.Hit{ .dmg = 34, .poise = 52, .stance = 24, .launch = combat.SLAM_LAUNCH };

const AWAKEN = struct {
    at: f32,
    liftDur: f32,
    holdDur: f32,
    settleDur: f32,
}{
    .at = 0.5,
    .liftDur = 0.70,
    .holdDur = 1.45,
    .settleDur = 0.55,
};

const AWK_SH = -160.0;
const AWK_EL = -4.0;
const AWK_ABD = 3.0;
const AWK_TILT = 24.0;
const AWK_ARCH = 7.0;

const CHAOS_BLAST = struct {
    r: f32, // pre-scale
    hit: combat.Hit,
}{
    .r = 0.62,
    .hit = .{ .dmg = 9, .poise = 18, .stance = 5, .elem = combat.elems(.{ .chaos = 11 }) },
};

pub const GAS_LIFE: f32 = 4.2;
const GAS_HANG: f32 = 0.42;
pub const GAS_R: f32 = 1.00;
const GAS_GROW: f32 = 0.40;
const GAS_CAP: usize = 12;
/// PRE-SCALE — 4.4 m at his own size against a trail cloud's 3.4 m width, so the lane has crossings in it.
const CHAOS_TRAIL_EVERY: f32 = 1.50;
/// Behind his own axis, pre-scale — `heelPoint`, shared by the wake and the trail.
const HEEL_BACK: f32 = 0.50;
const CHAOS_TRAIL_SCALE: f32 = 0.58;
pub const GAS_DOSE_EVERY: f32 = 0.55;
const GAS_HIT = combat.Hit{ .dmg = 6, .poise = 0, .stance = 0, .elem = combat.elems(.{ .chaos = 8 }) };
const GAS_ALPHA: u8 = 104;
const GAS_RATE: f32 = 88.0;
fn gasRate(scale: f32) f32 {
    const k = scale / SCALE;
    return GAS_RATE * k * k;
}
const GAS_PUFF_LO: f32 = 0.90;
const GAS_PUFF_HI: f32 = 1.40;
/// METRES, never his scale — the hazard is waded by a 1.8 m body, and at 1.35 x scale it stood 4 m tall.
const GAS_H: f32 = 1.30;
const GAS_DRIFT: f32 = 0.12;
/// Over half the puffs are born ON the rim, in a band a tenth wide — the edge is the message.
const GAS_RIM_SHARE: f32 = 0.55;
const GAS_PARTS = 132;
comptime {
    std.debug.assert(@as(f32, @floatFromInt(GAS_PARTS)) >= GAS_RATE * GAS_PUFF_HI);
    std.debug.assert(GAS_HIT.poise == 0 and GAS_HIT.stance == 0);
}

fn gasTint(c: rl.Color, f: f32) rl.Color {
    const a: f32 = @as(f32, @floatFromInt(GAS_ALPHA)) * mathx.clampF(f, 0, 1);
    return rl.Color{ .r = c.r, .g = c.g, .b = c.b, .a = @intFromFloat(a) };
}

pub const Gas = struct {
    pos: rl.Vector3 = mathx.zero3,
    scale: f32 = 1.0,
    t: f32 = 0,
    live: bool = false,
    parts: [GAS_PARTS]foe.Particle = [_]foe.Particle{.{}} ** GAS_PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x6A50),

    /// 1 while it hangs, 0 where it ends — drives the RATE, the ALPHA and the RADIUS together.
    fn fade(self: *const Gas) f32 {
        return 1.0 - mathx.smoothstep(GAS_LIFE * GAS_HANG, GAS_LIFE, self.t);
    }
    pub fn radius(self: *const Gas) f32 {
        const grow = mathx.smoothstep(0, GAS_GROW, self.t);
        return GAS_R * self.scale * grow * (0.55 + 0.45 * self.fade());
    }
    pub fn covers(self: *const Gas, p: rl.Vector3) bool {
        return self.live and self.t < GAS_LIFE and mathx.distXZ(self.pos, p) <= self.radius();
    }
    pub fn update(self: *Gas, dt: f32) void {
        foe.tickParticles(&self.parts, dt, self.pos.y);
        if (!self.live) return;
        self.t += dt;
        if (self.t >= GAS_LIFE) {
            self.live = false;
            return;
        }
        // **HIS EMBER, NOT CHAOS'S VIOLET** (owner: orangish like his tells, so it is never read as poison). The one
        // call site that picks its own colour over `elemfx.sig`, because the cloud is a tell first and an element second.
        const s = struct { edge: rl.Color, core: rl.Color, cool: ?rl.Color }{ .edge = EMBER_MARK, .core = EMBER, .cool = EMBER_MARK_COOL };
        const f = self.fade();
        const emitRate = gasRate(self.scale) * f;
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rim = self.fxRng.float() < GAS_RIM_SHARE;
            const rr = self.radius() * (if (rim) self.fxRng.range(0.93, 1.0) else @sqrt(self.fxRng.float()) * 0.80);
            const dir = v3(mathx.cosf(a), 0, mathx.sinf(a));
            const from = v3(
                self.pos.x + dir.x * rr,
                self.pos.y + self.fxRng.range(0.05, GAS_H),
                self.pos.z + dir.z * rr,
            );
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = from,
                .v = v3(-dir.x * GAS_DRIFT, self.fxRng.range(-0.03, 0.09), -dir.z * GAS_DRIFT),
                .life = self.fxRng.range(GAS_PUFF_LO, GAS_PUFF_HI),
                .r0 = self.fxRng.range(0.10, 0.16),
                .r1 = self.fxRng.range(0.19, 0.27),
                .col = gasTint(if (self.fxRng.float() < 0.34) s.edge else s.core, f),
                .col1 = if (s.cool) |c1| gasTint(c1, f) else null,
            });
        }
    }
    pub fn drawFx(self: *const Gas) void {
        // NOT gated on `live`: `update` ticks motes past the cloud's own death.
        if (!foe.motesVisible(self.pos, self.radius() + GAS_PUFF_HI)) return;
        foe.drawParticles(&self.parts);
    }
};

const LEAP = struct {
    windDur: f32,
    flightDur: f32,
    landDur: f32,
    dist: f32, // pre-scale
    rise: f32,
    cd: f32,
    turnMul: f32,
}{
    .windDur = 0.30,
    .flightDur = 0.46,
    .landDur = 0.32,
    .dist = 1.45,
    .rise = 0.40,
    .cd = 6.5,
    .turnMul = 5.5,
};

const STEPTURN = struct {
    windDur: f32,
    turnDur: f32,
    settleDur: f32,
    sweep: f32,
    least: f32,
    cd: f32,
}{
    .windDur = 0.22,
    .turnDur = 0.30,
    .settleDur = 0.24,
    .sweep = 62.0,
    // Past the bash's 26-deg gate: inside it he throws from where he stands, and the gather does the aiming.
    .least = 30.0,
    .cd = 1.15,
};
const STEP_LEAD = 26.0;

const LEAP_CHAIN_WIND: f32 = 0.34;

const COUNTER_CD: f32 = 1.9;

const SWAT_ORBIT_BAND: f32 = 1.2;

/// Under the 0.80 rad/s a walking hero carries at his own closest approach, so honest circling trips it.
const CIRCLE_RATE: f32 = 0.45;

const REPOSITION_AT: f32 = 0.12;

/// **THE JUMPBACK IS A LAST RESORT** (owner) — every door to the leap asks this tier, well above what
/// `REPOSITION_AT` prices the shove and `W_PRESS` at. Ground is only given up under real hurt.
const RETREAT_AT: f32 = 0.20;
comptime {
    std.debug.assert(RETREAT_AT > REPOSITION_AT * 1.5);
}

const HOP = struct {
    windDur: f32,
    airDur: f32,
    settleDur: f32,
    dist: f32, // pre-scale
    cd: f32,
    turnMul: f32,
}{
    .windDur = 0.28,
    .airDur = 0.26,
    .settleDur = 0.22,
    .dist = 1.10,
    .cd = 2.6,
    .turnMul = 3.4,
};

const CHARGE = struct {
    windDur: f32,
    speed: f32,
    accel: f32,
    overrun: f32, // metres past the mark
    range: f32,
    brakeDur: f32,
    recoverDur: f32,
    cd: f32,
    far: f32,
    patience: f32,
    hit: combat.Hit,
}{
    // Bracketed by `foe.TELL_MIN` below and the fall's gather above, like every wind he has.
    .windDur = 0.42,
    // The hero sprints 5.10; at 7.6 he arrived at a jog.
    .speed = 15.4,
    .accel = 0.22,
    .overrun = 2.6,
    .range = 26.0,
    // `brakeDist` integrates to `speed * brakeDur / 2` — held at 3.8 m past the mark through the speed-up
    // (15.4 x 0.50 / 2), or a faster charge would simply skid further and be easier to stand still and watch.
    .brakeDur = 0.50,
    .recoverDur = 1.05,
    .cd = 9.0,
    // The thrust band's own floor (7.3 m).
    .far = 7.4,
    .patience = 2.4,
    .hit = CHARGE_HIT,
};
pub const CHARGE_HIT = combat.Hit{ .dmg = 42, .poise = 52, .stance = 22 };
const CHARGE_LIT_FUSE: f32 = 0.65;
pub const FALL_HIT = combat.Hit{ .dmg = 24, .poise = 64, .stance = 32 };

const FALL_WIND_DUR = 1.45;
const FALL_DUR = 0.44;
const FALL_IMPACT_K = 0.86; // fraction into the topple, MEASURED off the pose
const DOWN_DUR = 2.10;
const ROLL_DUR = 0.72;
const RISE_DUR = 1.15;
const FALL_CD = 8.00;
const FALL_LEN = 0.95 * H;
const FALL_HALF_W = SHOULDER_HALF * H * 1.05;
const FALL_BACK_SLACK = 0.30;

/// **THE BODY GOES BEFORE THE BODY GOES** (owner: tilt back slowly before he falls back). Share of the topple the
/// WIND has already taken, in `TOPPLE_DEG` units — 0.16 is ~15°. The spine's own `FALL_WIND_LEAN` read as a
/// gather like any other; a giant going over backwards rotates at his HEELS, and that is the tell.
const FALL_WIND_TOPPLE: f32 = 0.16;

/// **THE FALL ANSWERS DISTANCE, NOT A SECTOR** (owner: make his fall an AoE so you have to make some distance).
/// A ring off the same mark the body lands on, PRE-SCALE and SOLVED against the tell it is drawn through: a RUN
/// clears it and a WALK does not, the slam's own rule. The crush strip is still the body arriving; this is the
/// ground answering, and it is billed only where the strip missed.
const FALL_WAVE_R: f32 = 1.38;
/// Under the crush on every count — the strip is five metres of armour landing on you, this is the shock off it.
pub const FALL_WAVE_HIT = combat.Hit{ .dmg = 14, .poise = 34, .stance = 16 };
/// Where along the fallen body the ring is centred, as a share of `FALL_LEN` behind his boots — `slamGround`'s
/// own dust mark, so the picture and the blow cannot part company.
const FALL_MARK_K: f32 = 0.55;

/// **HE ROCKS ON HIS BACK UNTIL HE CAN GET UP** (owner). Degrees about his own head-to-toe axis, which flat on
/// his back is a roll side to side. Faded in and out so entering and leaving `.downed` cannot snap him.
const ROCK_DEG: f32 = 7.0;
const ROCK_RATE: f32 = 4.4; // rad/s — about a 1.4 s wallow, slower than anything he does upright
const ROCK_EDGE: f32 = 0.30; // seconds of fade at each end of the lie

const TOPPLE_DEG = 92.0;
const LIE_LIFT = 0.34; // pre-scale
const ROLL_SHIFT = 0.30; // pre-scale
const ROLL_HUMP = 0.26; // pre-scale
/// Past upright, in `TOPPLE_DEG` units (0.06 is ~5.5 deg).
const RISE_OVERSHOOT = 0.07;

const HP_MAX = 900.0;
const POISE_MAX = 78.0;
const STANCE_MAX = 138.0;
const RESISTS = combat.resists(.{ .fire = -35, .cold = 60, .chaos = 45 });
pub const SOULS: u32 = 2400;
const DEATH_DUR = 2.20;
/// WHEN THE BODY ARRIVES. `audio.mkKnightDie` writes its crash to this same number, and so does the dust.
const DEATH_LAND = DEATH_DUR * 0.62;
const DEATH_SETTLE = 0.46;
/// Past flat, in `TOPPLE_DEG` units (0.06 is ~5.5 deg).
const DEATH_BOUNCE = 0.06;
const DISS_DUR = 1.40;
const DISSOLVE = foe.Dissolve{ .rate = 82.0, .spread = 1.15, .rise = 0.72, .flake = CHIP };

const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 6.0;
const PARRY_LEAD = foe.PARRY_LEAD;
/// **TWO PARRIES OPEN HIM** (owner: good parry potential — the player should feel like a badass). His own bite,
/// over `combat.PARRY_HIT`'s 46: against 138 of stance that was three, and the third never came.
const PARRY_STANCE: f32 = 70.0;
comptime {
    std.debug.assert(PARRY_STANCE * 2 >= STANCE_MAX and PARRY_STANCE < STANCE_MAX);
}

const NPART = 208;

const PELVIS_SHARE = 0.14;
const STUN_EASE_DEG = 240.0;
const STUN_EASE_FRAC = 4.0;
const A_BOB = heromod.A_BOB;
const A_PROT = 5.0;

// **THE CARRY IS PFLUG** (Liechtenauer's plough — owner: better sword posture, look at actual swordsmen): hilt at
// the right hip, elbow bent, the point presented forward-down at the man's chest, beside the door's right edge.
// It rode point-down off his side before, a sword at rest; a presented point is a threat, and every gather now
// starts from it, so the draw-back IS the tell. A test pins where the point sits.
const CARRY_SH = 20.0;
const CARRY_EL = -10.0;
/// Abducted enough that the hilt — and every stroke's path out of and back into the carry — clears the door's
/// right edge (x −1.54 at the guard) by the blade's own margin: at 16 the raise into the overhead passed it by 0.12 m.
const CARRY_ABD = -2.0;
/// deg the blade leads FORWARD of the forearm line — `hero.GRIP_PITCH`'s convention. NEGATIVE here: with the
/// forearm already near level (34 + 48 from vertical), a positive lead pointed the blade at the sky (5.9 m up).
const CARRY_TILT = 150.0;
/// Yawed in so the point is presented AT the man and not 3.5 m to his right of him.
const CARRY_SWEEP = 30.0;
// MEASURED at sh52/el−92/abd44: the shield hand 1.82 m in front of his chest bone, the door's hub 2.15 m.
const GUARD_SH = 6.0;
const GUARD_EL = -126.0;
const GUARD_ABD = 12.0;
const GUARD_TWIST = -18.0;
const GUARD_LEAN = 7.0;

const BASH_WIND_SH = -38.0;
const BASH_WIND_EL = -150.0;
const BASH_WIND_ABD = 20.0;
// The door is on the forearm now, so the torso's twist turns the PLANK: wound to -58 it faced his own left.
const BASH_WIND_TWIST = -30.0;
const BASH_WIND_LEAN = -22.0;
// **THE FOREARM KEEPS ITS LINE AND THE BODY DRIVES.** Strapped to the forearm, a straight-arm punch (elbow -14)
// turned the plank 110 deg with the arm and rammed its edge. The upper arm swings forward 56 deg and the elbow
// OPENS by the same, so the forearm — and the face on it — stays across his front; the lean and the lunge carry it.
const BASH_HIT_SH = 62.0;
const BASH_HIT_EL = -70.0;
const BASH_HIT_ABD = 10.0;
/// Twist turns the plank with the torso now: +22 faced it 46 deg LEFT of the man, -16 squares it.
const BASH_HIT_TWIST = -16.0;
const BASH_HIT_LEAN = 22.0;

// **THE SWEEP IS A LOW FOREHAND, COCKED BEHIND HIS RIGHT HIP AND RIPPED ACROSS THE FRONT.** Wound high across
// the body it crossed his front 4.8 m up and only came down to a man's height out on his own sword flank.
const SWP_WIND_SH = 30.0;
const SWP_WIND_EL = -14.0;
const SWP_WIND_ABD = 48.0;
const SWP_WIND_SWEEP = 118.0;
const SWP_WIND_TWIST = 44.0;
const SWP_WIND_LEAN = 8.0;
const SWP_WIND_TILT = 30.0;
// The arm stays EXTENDED through the front (`SWP_HIT_SH` 52): folded to 22 on the follow-through the blade
// crossed his front at 3.4 m and the far half of the band was never touched.
const SWP_HIT_SWEEP = -60.0;
const SWP_HIT_TWIST = -30.0;
// Bent deep (`lean` 40) so the FIST comes down to ~2.3 m: at 2.7 the root of the blade cleared a man at his boots.
const SWP_HIT_LEAN = 40.0;
const SWP_HIT_TILT = 44.0;
const SWP_HIT_SH = 48.0;
const SWP_HIT_ABD = 8.0;

// The second sweep is a SECOND FOREHAND: the blade is drawn back low across his front to the right hip (un-live,
// the whole 0.58 s a tell) and ripped across again. A backhand from the left had nowhere to cock — the door now
// stands edge-on behind his left shoulder, and the sword hand went through it.
const SW2_WIND_SWEEP = 110.0;
const SW2_WIND_TILT = 20.0;
// Finishes no further left than the sweep does: at -96 the tip ended on the door's forward edge.
const SW2_HIT_SWEEP = -64.0;
const SW2_HIT_TWIST = -32.0;
const SW2_HIT_LEAN = 40.0;
const SW2_HIT_TILT = 44.0;

const OVR_WIND_SH = -148.0;
const OVR_WIND_EL = -24.0;
const OVR_WIND_ABD = 10.0;
const OVR_WIND_TILT = -30.0;
const OVR_WIND_LEAN = -14.0;
const OVR_WIND_TWIST = -18.0;
const OVR_HIT_SH = 64.0;
const OVR_HIT_TILT = -12.0;
const OVR_HIT_EL = -8.0;
const OVR_HIT_LEAN = 32.0;
/// Torso turned INTO the drop and the arm swept across it: off the shoulder alone the blade came down 1.2 m to
/// the right of the man he was squared on.
const OVR_HIT_TWIST = -16.0;
const OVR_HIT_SWEEP = -40.0;
/// ADDUCTED across the chest: a blade pointing straight down barely answers `armSweep` or `twist`.
const OVR_HIT_ABD = -10.0;


const SWEEP_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.22, .p = .{ .armSh = 26, .armAbd = 34, .armSweep = 40, .tilt = 24, .lean = 6, .twist = 18, .brace = 0.30 }, .ease = .decel },
        .{ .t = 0.70, .p = .{ .armSh = SWP_WIND_SH, .armEl = SWP_WIND_EL, .armAbd = SWP_WIND_ABD, .armSweep = SWP_WIND_SWEEP, .tilt = SWP_WIND_TILT, .lean = SWP_WIND_LEAN, .twist = SWP_WIND_TWIST, .head = -10, .brace = 0.60 }, .ease = .accel },
        .{ .t = 0.86, .p = .{ .armSh = SWP_WIND_SH - 6, .armEl = SWP_WIND_EL, .armAbd = SWP_WIND_ABD + 4, .armSweep = SWP_WIND_SWEEP + 8, .tilt = SWP_WIND_TILT + 6, .lean = SWP_WIND_LEAN - 3, .twist = SWP_WIND_TWIST + 5, .head = -10, .brace = 0.66 }, .ease = .decel },
        // THE HANG: cocked and still for the last seventh of the gather, so the man reads it before it comes.
        .{ .t = 1.00, .p = .{ .armSh = SWP_WIND_SH - 6, .armEl = SWP_WIND_EL, .armAbd = SWP_WIND_ABD + 4, .armSweep = SWP_WIND_SWEEP + 8, .tilt = SWP_WIND_TILT + 6, .lean = SWP_WIND_LEAN - 3, .twist = SWP_WIND_TWIST + 5, .head = -10, .brace = 0.66 }, .ease = .hold },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_WIND_SH - 6, .armEl = SWP_WIND_EL, .armAbd = SWP_WIND_ABD + 4, .armSweep = SWP_WIND_SWEEP + 8, .tilt = SWP_WIND_TILT + 6, .lean = SWP_WIND_LEAN - 3, .twist = SWP_WIND_TWIST + 5, .head = -10, .brace = 0.66 } },
        .{ .t = 0.34, .p = .{ .armSh = SWP_HIT_SH + 4, .armEl = -6, .armAbd = SWP_HIT_ABD + 6, .armSweep = -20, .tilt = SWP_HIT_TILT + 6, .lean = SWP_HIT_LEAN - 6, .twist = -20, .head = 10, .brace = 0.84 }, .ease = .snap },
        .{ .t = 0.74, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD - 4, .armSweep = SWP_HIT_SWEEP - 12, .tilt = SWP_HIT_TILT - 4, .lean = SWP_HIT_LEAN + 4, .twist = SWP_HIT_TWIST - 6, .head = 18, .brace = 0.90 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SWP_HIT_SWEEP, .tilt = SWP_HIT_TILT, .lean = SWP_HIT_LEAN, .twist = SWP_HIT_TWIST, .head = 16, .brace = 0.86 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SWP_HIT_SWEEP, .tilt = SWP_HIT_TILT, .lean = SWP_HIT_LEAN, .twist = SWP_HIT_TWIST, .head = 16, .brace = 0.86 } },
        .{ .t = 0.14, .p = .{ .armSh = SWP_HIT_SH - 4, .armEl = -8, .armAbd = SWP_HIT_ABD - 2, .armSweep = SWP_HIT_SWEEP - 4, .tilt = SWP_HIT_TILT - 4, .lean = SWP_HIT_LEAN + 2, .twist = SWP_HIT_TWIST - 3, .head = 14, .brace = 0.80 }, .ease = .decel },
        .{ .t = RECOVER_HOLD_K, .p = .{ .armSh = SWP_HIT_SH - 4, .armEl = -8, .armAbd = SWP_HIT_ABD - 2, .armSweep = SWP_HIT_SWEEP - 4, .tilt = SWP_HIT_TILT - 4, .lean = SWP_HIT_LEAN + 2, .twist = SWP_HIT_TWIST - 3, .head = 14, .brace = 0.80 }, .ease = .hold },
        .{ .t = RECOVER_BACK_K, .p = P_PARK, .ease = .decel },
        .{ .t = RECOVER_PARK_TO, .p = P_PARK, .ease = .hold },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const SWEEP2_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SWP_HIT_SWEEP, .tilt = SWP_HIT_TILT, .lean = SWP_HIT_LEAN, .twist = SWP_HIT_TWIST, .head = 16, .brace = 0.86 } },
        .{ .t = 1.00, .p = .{ .armSh = SWP_HIT_SH + 4, .armEl = -6, .armAbd = SWP_HIT_ABD + 12, .armSweep = SW2_WIND_SWEEP, .tilt = SW2_WIND_TILT, .lean = SWP_HIT_LEAN - 8, .twist = SW2_WIND_SWEEP * 0.4, .head = -4, .brace = 0.70 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH + 4, .armEl = -6, .armAbd = SWP_HIT_ABD + 12, .armSweep = SW2_WIND_SWEEP, .tilt = SW2_WIND_TILT, .lean = SWP_HIT_LEAN - 8, .twist = SW2_WIND_SWEEP * 0.4, .head = -4, .brace = 0.70 } },
        .{ .t = 0.30, .p = .{ .armSh = SWP_HIT_SH + 2, .armEl = -6, .armAbd = SWP_HIT_ABD + 4, .armSweep = -20, .tilt = SW2_HIT_TILT + 6, .lean = SW2_HIT_LEAN - 8, .twist = -18, .head = 12, .brace = 0.86 }, .ease = .snap },
        .{ .t = 0.72, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD - 4, .armSweep = SW2_HIT_SWEEP + 12, .tilt = SW2_HIT_TILT - 4, .lean = SW2_HIT_LEAN + 4, .twist = SW2_HIT_TWIST + 7, .head = 20, .brace = 0.92 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .armSh = SWP_HIT_SH - 4, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SW2_HIT_SWEEP, .tilt = SW2_HIT_TILT, .lean = SW2_HIT_LEAN, .twist = SW2_HIT_TWIST, .head = 18, .brace = 0.88 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH - 4, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SW2_HIT_SWEEP, .tilt = SW2_HIT_TILT, .lean = SW2_HIT_LEAN, .twist = SW2_HIT_TWIST, .head = 18, .brace = 0.88 } },
        .{ .t = 0.14, .p = .{ .armSh = SWP_HIT_SH - 8, .armEl = -8, .armAbd = SWP_HIT_ABD - 3, .armSweep = SW2_HIT_SWEEP + 5, .tilt = SW2_HIT_TILT - 5, .lean = SW2_HIT_LEAN + 3, .twist = SW2_HIT_TWIST + 4, .head = 16, .brace = 0.82 }, .ease = .decel },
        .{ .t = RECOVER_HOLD_K, .p = .{ .armSh = SWP_HIT_SH - 8, .armEl = -8, .armAbd = SWP_HIT_ABD - 3, .armSweep = SW2_HIT_SWEEP + 5, .tilt = SW2_HIT_TILT - 5, .lean = SW2_HIT_LEAN + 3, .twist = SW2_HIT_TWIST + 4, .head = 16, .brace = 0.82 }, .ease = .hold },
        .{ .t = RECOVER_BACK_K, .p = P_PARK, .ease = .decel },
        .{ .t = RECOVER_PARK_TO, .p = P_PARK, .ease = .hold },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const OVER_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // The raise goes OUT and round the door's right edge before it comes over the top: from the old low
        // carry, straight to the cock, the hilt swung down past the hip and 0.26 m off the plank's lower edge.
        .{ .t = 0.20, .p = .{ .armSh = 20, .armEl = -30, .armAbd = 44, .tilt = -10, .lean = 2, .twist = -6, .brace = 0.30 }, .ease = .decel },
        .{ .t = 0.58, .p = .{ .armSh = OVR_WIND_SH + 30, .armEl = OVR_WIND_EL - 10, .armAbd = OVR_WIND_ABD + 26, .tilt = OVR_WIND_TILT + 24, .lean = -6, .twist = -14, .head = -8, .brace = 0.38 }, .ease = .decel },
        .{ .t = 0.86, .p = .{ .armSh = OVR_WIND_SH, .armEl = OVR_WIND_EL, .armAbd = OVR_WIND_ABD + 12, .tilt = OVR_WIND_TILT, .lean = OVR_WIND_LEAN, .twist = OVR_WIND_TWIST, .head = -14, .brace = 0.55 }, .ease = .accel },
        .{ .t = 1.00, .p = .{ .armSh = OVR_WIND_SH, .armEl = OVR_WIND_EL, .armAbd = OVR_WIND_ABD + 12, .tilt = OVR_WIND_TILT, .lean = OVR_WIND_LEAN, .twist = OVR_WIND_TWIST, .head = -14, .brace = 0.55 }, .ease = .hold },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = OVR_WIND_SH, .armEl = OVR_WIND_EL, .armAbd = OVR_WIND_ABD + 12, .tilt = OVR_WIND_TILT, .lean = OVR_WIND_LEAN, .twist = OVR_WIND_TWIST, .head = -14, .brace = 0.55 } },
        .{ .t = 0.42, .p = .{ .armSh = 10, .armEl = OVR_WIND_EL - 34, .armAbd = 0, .armSweep = OVR_HIT_SWEEP * 0.6, .tilt = -22, .lean = 12, .twist = -4, .head = 6, .brace = 0.74 }, .ease = .snap },
        .{ .t = 0.80, .p = .{ .armSh = OVR_HIT_SH + 8, .armEl = OVR_HIT_EL, .armAbd = OVR_HIT_ABD, .armSweep = OVR_HIT_SWEEP, .tilt = OVR_HIT_TILT - 6, .lean = OVR_HIT_LEAN + 7, .twist = OVR_HIT_TWIST - 4, .head = 24, .brace = 0.94 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .armSh = OVR_HIT_SH, .armEl = OVR_HIT_EL, .armAbd = OVR_HIT_ABD, .armSweep = OVR_HIT_SWEEP, .tilt = OVR_HIT_TILT, .lean = OVR_HIT_LEAN, .twist = OVR_HIT_TWIST, .head = 22, .brace = 0.90 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = OVR_HIT_SH, .armEl = OVR_HIT_EL, .armAbd = OVR_HIT_ABD, .armSweep = OVR_HIT_SWEEP, .tilt = OVR_HIT_TILT, .lean = OVR_HIT_LEAN, .twist = OVR_HIT_TWIST, .head = 22, .brace = 0.90 } },
        .{ .t = 0.14, .p = .{ .armSh = OVR_HIT_SH - 3, .armEl = OVR_HIT_EL - 3, .armAbd = OVR_HIT_ABD, .armSweep = OVR_HIT_SWEEP, .tilt = OVR_HIT_TILT - 2, .lean = OVR_HIT_LEAN + 2, .twist = OVR_HIT_TWIST, .head = 20, .brace = 0.86 }, .ease = .decel },
        .{ .t = RECOVER_HOLD_K, .p = .{ .armSh = OVR_HIT_SH - 3, .armEl = OVR_HIT_EL - 3, .armAbd = OVR_HIT_ABD, .armSweep = OVR_HIT_SWEEP, .tilt = OVR_HIT_TILT - 2, .lean = OVR_HIT_LEAN + 2, .twist = OVR_HIT_TWIST, .head = 20, .brace = 0.86 }, .ease = .hold },
        .{ .t = RECOVER_BACK_K, .p = P_PARK, .ease = .decel },
        .{ .t = RECOVER_PARK_TO, .p = P_PARK, .ease = .hold },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const THRUST_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.46, .p = .{ .armSh = THR_WIND_SH + 14, .armEl = THR_WIND_EL + 10, .armAbd = THR_WIND_ABD - 6, .armSweep = THR_WIND_SWEEP * 0.6, .tilt = THR_WIND_TILT - 6, .offSh = GUARD_SH - THR_OFF_RISE * 0.5, .lean = 0, .twist = GUARD_TWIST - 4, .brace = 0.28 }, .ease = .decel },
        .{ .t = 0.86, .p = .{ .armSh = THR_WIND_SH, .armEl = THR_WIND_EL, .armAbd = THR_WIND_ABD, .armSweep = THR_WIND_SWEEP, .tilt = THR_WIND_TILT, .offSh = GUARD_SH - THR_OFF_RISE, .lean = THR_WIND_LEAN, .twist = GUARD_TWIST - 10, .brace = 0.44 }, .ease = .accel },
        .{ .t = 1.00, .p = .{ .armSh = THR_WIND_SH, .armEl = THR_WIND_EL, .armAbd = THR_WIND_ABD, .armSweep = THR_WIND_SWEEP, .tilt = THR_WIND_TILT, .offSh = GUARD_SH - THR_OFF_RISE, .lean = THR_WIND_LEAN, .twist = GUARD_TWIST - 10, .brace = 0.44 }, .ease = .hold },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = THR_WIND_SH, .armEl = THR_WIND_EL, .armAbd = THR_WIND_ABD, .armSweep = THR_WIND_SWEEP, .tilt = THR_WIND_TILT, .offSh = GUARD_SH - THR_OFF_RISE, .lean = THR_WIND_LEAN, .twist = GUARD_TWIST - 10, .brace = 0.44 } },
        .{ .t = 0.28, .p = .{ .armSh = THR_HIT_SH + 4, .armEl = THR_HIT_EL, .armAbd = CARRY_ABD, .armSweep = THR_HIT_SWEEP, .tilt = THR_HIT_TILT, .offSh = GUARD_SH - 4, .lean = THR_HIT_LEAN + 4, .twist = THR_HIT_TWIST - 2, .head = 8, .brace = 0.80 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .armSh = THR_HIT_SH, .armEl = THR_HIT_EL, .armAbd = CARRY_ABD, .armSweep = THR_HIT_SWEEP, .tilt = THR_HIT_TILT, .offSh = GUARD_SH, .lean = THR_HIT_LEAN, .twist = THR_HIT_TWIST, .head = 6, .brace = 0.72 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = THR_HIT_SH, .armEl = THR_HIT_EL, .armAbd = CARRY_ABD, .armSweep = THR_HIT_SWEEP, .tilt = THR_HIT_TILT, .lean = THR_HIT_LEAN, .twist = THR_HIT_TWIST, .head = 6, .brace = 0.72 } },
        .{ .t = 0.14, .p = .{ .armSh = THR_HIT_SH - 6, .armEl = THR_HIT_EL - 4, .armAbd = CARRY_ABD, .armSweep = THR_HIT_SWEEP * 0.6, .tilt = THR_HIT_TILT - 4, .lean = THR_HIT_LEAN + 3, .twist = THR_HIT_TWIST * 0.5, .head = 4, .brace = 0.64 }, .ease = .decel },
        .{ .t = RECOVER_HOLD_K, .p = .{ .armSh = THR_HIT_SH - 6, .armEl = THR_HIT_EL - 4, .armAbd = CARRY_ABD, .armSweep = THR_HIT_SWEEP * 0.6, .tilt = THR_HIT_TILT - 4, .lean = THR_HIT_LEAN + 3, .twist = THR_HIT_TWIST * 0.5, .head = 4, .brace = 0.64 }, .ease = .hold },
        .{ .t = RECOVER_BACK_K, .p = P_PARK, .ease = .decel },
        .{ .t = RECOVER_PARK_TO, .p = P_PARK, .ease = .hold },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const BASH_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.52, .p = .{ .offSh = BASH_WIND_SH + 10, .offEl = BASH_WIND_EL + 12, .offAbd = BASH_WIND_ABD - 4, .armSh = CARRY_SH - 8, .lean = BASH_WIND_LEAN + 8, .twist = BASH_WIND_TWIST + 16, .head = -4, .brace = 0.36 }, .ease = .decel },
        .{ .t = 0.86, .p = .{ .offSh = BASH_WIND_SH, .offEl = BASH_WIND_EL, .offAbd = BASH_WIND_ABD, .armSh = CARRY_SH - 12, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 8, .tilt = CARRY_TILT + 10, .lean = BASH_WIND_LEAN, .twist = BASH_WIND_TWIST, .head = -6, .brace = 0.50 }, .ease = .accel },
        .{ .t = 1.00, .p = .{ .offSh = BASH_WIND_SH, .offEl = BASH_WIND_EL, .offAbd = BASH_WIND_ABD, .armSh = CARRY_SH - 12, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 8, .tilt = CARRY_TILT + 10, .lean = BASH_WIND_LEAN, .twist = BASH_WIND_TWIST, .head = -6, .brace = 0.50 }, .ease = .hold },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = BASH_WIND_SH, .offEl = BASH_WIND_EL, .offAbd = BASH_WIND_ABD, .armSh = CARRY_SH - 12, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 8, .tilt = CARRY_TILT + 10, .lean = BASH_WIND_LEAN, .twist = BASH_WIND_TWIST, .head = -6, .brace = 0.50 } },
        .{ .t = 0.30, .p = .{ .offSh = BASH_HIT_SH + 6, .offEl = BASH_HIT_EL, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 18, .armEl = CARRY_EL, .armAbd = CARRY_ABD - 6, .lean = BASH_HIT_LEAN + 6, .twist = BASH_HIT_TWIST + 6, .head = 14, .brace = 0.76 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .offSh = BASH_HIT_SH, .offEl = BASH_HIT_EL, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 18, .armEl = CARRY_EL, .armAbd = CARRY_ABD - 6, .lean = BASH_HIT_LEAN, .twist = BASH_HIT_TWIST, .head = 14, .brace = 0.72 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = BASH_HIT_SH, .offEl = BASH_HIT_EL, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 18, .armEl = CARRY_EL, .armAbd = CARRY_ABD - 6, .lean = BASH_HIT_LEAN, .twist = BASH_HIT_TWIST, .head = 14, .brace = 0.72 } },
        .{ .t = 0.42, .p = .{ .offSh = BASH_HIT_SH - 8, .offEl = BASH_HIT_EL - 6, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 10, .lean = BASH_HIT_LEAN + 3, .twist = BASH_HIT_TWIST - 4, .head = 10, .brace = 0.62 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const SLAM_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.20, .p = .{ .offSh = GUARD_SH + 16, .offEl = GUARD_EL + 8, .lean = 16, .head = 8, .brace = 0.62 }, .ease = .decel },
        .{ .t = 0.74, .p = .{ .offSh = SLM_WIND_SH + 22, .offEl = SLM_WIND_EL - 8, .offAbd = SLM_WIND_ABD - 6, .armSh = CARRY_SH - 20, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 10, .armSweep = -14, .lean = SLM_WIND_LEAN + 6, .twist = SLM_WIND_TWIST - 4, .head = -8, .brace = 0.50 }, .ease = .accel },
        .{ .t = 0.92, .p = .{ .offSh = SLM_WIND_SH, .offEl = SLM_WIND_EL, .offAbd = SLM_WIND_ABD, .armSh = CARRY_SH - 26, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -18, .lean = SLM_WIND_LEAN, .twist = SLM_WIND_TWIST, .head = -12, .brace = 0.62 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = SLM_WIND_SH, .offEl = SLM_WIND_EL, .offAbd = SLM_WIND_ABD, .armSh = CARRY_SH - 26, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -18, .lean = SLM_WIND_LEAN, .twist = SLM_WIND_TWIST, .head = -12, .brace = 0.62 }, .ease = .hold },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = SLM_WIND_SH, .offEl = SLM_WIND_EL, .offAbd = SLM_WIND_ABD, .armSh = CARRY_SH - 26, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -18, .lean = SLM_WIND_LEAN, .twist = SLM_WIND_TWIST, .head = -12, .brace = 0.62 } },
        .{ .t = 0.36, .p = .{ .offSh = SLM_HIT_SH + 10, .offEl = SLM_HIT_EL, .offAbd = 12, .armSh = CARRY_SH + 6, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -10, .lean = SLM_HIT_LEAN + 8, .twist = SLM_HIT_TWIST - 4, .head = 22, .brace = 0.94 }, .ease = .snap },
        .{ .t = 0.62, .p = .{ .offSh = SLM_HIT_SH - 9, .offEl = SLM_HIT_EL - 5, .offAbd = 12, .armSh = CARRY_SH + 12, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -6, .lean = SLM_HIT_LEAN - 6, .twist = SLM_HIT_TWIST, .head = 14, .brace = 0.80 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = SLM_HIT_SH, .offEl = SLM_HIT_EL, .offAbd = 12, .armSh = CARRY_SH + 12, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -6, .lean = SLM_HIT_LEAN, .twist = SLM_HIT_TWIST, .head = 20, .brace = 0.92 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = SLM_HIT_SH, .offEl = SLM_HIT_EL, .offAbd = 12, .armSh = CARRY_SH + 12, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -6, .lean = SLM_HIT_LEAN, .twist = SLM_HIT_TWIST, .head = 20, .brace = 0.92 } },
        .{ .t = 0.46, .p = .{ .offSh = SLM_HIT_SH - 4, .offEl = SLM_HIT_EL - 4, .offAbd = 12, .armSh = CARRY_SH + 8, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 10, .lean = SLM_HIT_LEAN + 3, .twist = SLM_HIT_TWIST, .head = 18, .brace = 0.86 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.22 }, .ease = .decel },
    },
};

const FALL_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.34, .p = .{ .lean = FALL_WIND_GATHER, .offSh = GUARD_SH + 8, .armSh = CARRY_SH + 10, .head = 10, .brace = 0.44 }, .ease = .decel },
        .{ .t = 0.78, .p = .{ .lean = FALL_WIND_LEAN * 0.5, .offSh = FALL_SH + 14, .offEl = FALL_EL + 20, .offAbd = 14, .armSh = FALL_SH + 16, .armEl = FALL_EL + 24, .armAbd = 16, .tilt = 70, .twist = -6, .head = -18, .brace = 0.24 }, .ease = .accel },
        .{ .t = 1.00, .p = .{ .lean = FALL_WIND_LEAN, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 10, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = 110, .twist = 0, .head = -30, .brace = 0 }, .ease = .decel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .lean = FALL_WIND_LEAN, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 10, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = 110, .twist = 0, .head = -30, .brace = 0 } },
        .{ .t = 0.34, .p = .{ .lean = -14, .offSh = FALL_SH - 40, .offEl = FALL_EL + 46, .offAbd = 44, .armSh = FALL_SH - 52, .armEl = FALL_EL + 38, .armAbd = 52, .armSweep = -18, .tilt = 84, .head = -34, .brace = 0.30 }, .ease = .decel },
        .{ .t = 0.70, .p = .{ .lean = -2, .offSh = FALL_SH - 22, .offEl = FALL_EL + 28, .offAbd = 30, .armSh = FALL_SH - 30, .armEl = FALL_EL + 20, .armAbd = 36, .armSweep = -10, .tilt = 96, .head = -12, .brace = 0.55 }, .ease = .linear },
        .{ .t = 1.00, .p = .{ .lean = 4, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 6, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = FLOORED_TILT, .head = -4, .brace = 0 }, .ease = .snap },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .lean = 4, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 6, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = FLOORED_TILT, .head = -4, .brace = 0 } },
        .{ .t = 1.00, .p = .{ .lean = 4, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 6, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = FLOORED_TILT, .head = -4, .brace = 0 } },
    },
};

const SHOVE_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.56, .p = .{ .offSh = SHV_WIND_SH + 8, .offEl = SHV_WIND_EL, .offAbd = GUARD_ABD + 4, .armSh = CARRY_SH - 14, .lean = -16, .twist = BASH_WIND_TWIST - 14, .head = -8, .brace = 0.42 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = SHV_WIND_SH, .offEl = SHV_WIND_EL, .offAbd = GUARD_ABD + 8, .armSh = CARRY_SH - 18, .armAbd = CARRY_ABD + 12, .lean = -22, .twist = BASH_WIND_TWIST - 20, .head = -10, .brace = 0.56 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = SHV_WIND_SH, .offEl = SHV_WIND_EL, .offAbd = GUARD_ABD + 8, .armSh = CARRY_SH - 18, .armAbd = CARRY_ABD + 12, .lean = -22, .twist = BASH_WIND_TWIST - 20, .head = -10, .brace = 0.56 } },
        // THE ELBOW STAYS FOLDED — `SHOVE_CARRY_X` carries the door across, never the arm.
        .{ .t = 0.32, .p = .{ .offSh = SHV_HIT_SH + 6, .offEl = SHV_HIT_EL, .offAbd = GUARD_ABD + 12, .armSh = CARRY_SH + 14, .armAbd = CARRY_ABD - 8, .lean = 16, .twist = BASH_HIT_TWIST + 26, .head = 12, .brace = 0.82 }, .ease = .snap },
        .{ .t = 0.68, .p = .{ .offSh = SHV_HIT_SH - 5, .offEl = SHV_HIT_EL - 4, .offAbd = GUARD_ABD + 16, .armSh = CARRY_SH + 18, .armAbd = CARRY_ABD - 10, .lean = 10, .twist = BASH_HIT_TWIST + 34, .head = 8, .brace = 0.74 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = SHV_HIT_SH, .offEl = SHV_HIT_EL, .offAbd = GUARD_ABD + 14, .armSh = CARRY_SH + 16, .armAbd = CARRY_ABD - 10, .lean = 12, .twist = BASH_HIT_TWIST + 30, .head = 10, .brace = 0.78 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = SHV_HIT_SH, .offEl = SHV_HIT_EL, .offAbd = GUARD_ABD + 14, .armSh = CARRY_SH + 16, .armAbd = CARRY_ABD - 10, .lean = 12, .twist = BASH_HIT_TWIST + 30, .head = 10, .brace = 0.78 } },
        .{ .t = 0.48, .p = .{ .offSh = SHV_HIT_SH - 6, .offEl = SHV_HIT_EL - 6, .offAbd = GUARD_ABD + 8, .armSh = CARRY_SH + 10, .lean = 10, .twist = BASH_HIT_TWIST + 20, .head = 8, .brace = 0.66 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};
const SHV_WIND_SH = -14.0;
const SHV_WIND_EL = -138.0;
const SHV_HIT_SH = 34.0;
const SHV_HIT_EL = -104.0;
const SHOVE_YAW = 26.0;
const SHOVE_CARRY_X = 0.30 * H;
const SHOVE_CARRY_Z = 0.10 * H;
// BRACKETED FROM ABOVE by where the flank answer becomes the SWEEP: the shove may reach past the bash's own
// door, never past 0.95 of the sweep's trigger, or the two moves argue over the same stand. Re-measure it when
// `BASH.reachOut` moves — that number went 0.90 to 0.94 when the sword arm's sweep flipped sign under it.
const SHOVE_BAND = 1.18;
const SHOVE_SHIELD_WIND = 0.60;
/// **THE FASTEST TELL HE OWNS, AND THE ANSWER TO CAMPING ON THE DOOR** (owner). 0.52 x 0.58 lands on
/// `foe.TELL_MIN` exactly, and it takes NO `windHold` — the whole point is that it does not wait.
const SWAT_SHIELD_WIND = 0.58;
const SWAT_HANG: f32 = 0.26;

const SWAT_SWORD_KEYS = MoveKeys{
    // THE ELBOW STAYS SHUT AND LOW: straightening threw the tip 5.68 m off a move declared at 3.09.
    // Flicked from his right hip ACROSS the front, not out to the flank: the gather has already turned him onto the man.
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 1.00, .p = .{ .armSweep = SWT_WIND_SWEEP, .armSh = SWT_SH, .armEl = SWT_EL, .armAbd = SWT_ABD, .tilt = SWT_TILT, .twist = GUARD_TWIST + 14, .lean = SWT_LEAN, .brace = 0.32 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSweep = SWT_WIND_SWEEP, .armSh = SWT_SH, .armEl = SWT_EL, .armAbd = SWT_ABD, .tilt = SWT_TILT, .twist = GUARD_TWIST + 14, .lean = SWT_LEAN, .brace = 0.32 } },
        .{ .t = 0.38, .p = .{ .armSweep = SWT_HIT_SWEEP - 10, .armSh = SWT_SH + 4, .armEl = SWT_EL, .armAbd = SWT_ABD + 6, .tilt = SWT_TILT, .twist = GUARD_TWIST - 22, .lean = SWT_LEAN + 8, .head = 8, .brace = 0.58 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .armSweep = SWT_HIT_SWEEP, .armSh = SWT_SH + 2, .armEl = SWT_EL, .armAbd = SWT_ABD + 4, .tilt = SWT_TILT, .twist = GUARD_TWIST - 15, .lean = SWT_LEAN + 5, .head = 6, .brace = 0.52 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSweep = SWT_HIT_SWEEP, .armSh = SWT_SH + 2, .armEl = SWT_EL, .armAbd = SWT_ABD + 4, .tilt = SWT_TILT, .twist = GUARD_TWIST - 15, .lean = SWT_LEAN + 5, .head = 6, .brace = 0.52 } },
        .{ .t = RECOVER_HOLD_K, .p = .{ .armSweep = SWT_HIT_SWEEP, .armSh = SWT_SH + 2, .armEl = SWT_EL, .armAbd = SWT_ABD + 4, .tilt = SWT_TILT, .twist = GUARD_TWIST - 15, .lean = SWT_LEAN + 5, .head = 6, .brace = 0.52 }, .ease = .hold },
        .{ .t = RECOVER_BACK_K, .p = P_PARK, .ease = .decel },
        .{ .t = RECOVER_PARK_TO, .p = P_PARK, .ease = .hold },
        .{ .t = 1.00, .p = .{ .brace = 0.18 }, .ease = .decel },
    },
};
// The blade points OUT for the flick to travel: hung near-vertical, 82 deg of shoulder sweep moved the tip 30.
const SWT_SH = 30.0;
/// Its own elbow, not the carry's: riding the carry's it followed `CARRY_EL` about, which lifted the flick a metre.
const SWT_EL = -18.0;
/// Out past the door's right edge on the cock: at 12 the blade root swung down 0.36 m off the plank.
const SWT_ABD = 20.0;
const SWT_TILT = 46.0;
const SWT_LEAN = 32.0;
const SWT_WIND_SWEEP = 30.0;
const SWT_HIT_SWEEP = -70.0;

const SWAT_SHIELD_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 1.00, .p = .{ .offSh = GUARD_SH - 26, .offEl = GUARD_EL - 14, .offAbd = GUARD_ABD + 22, .twist = GUARD_TWIST - 20, .lean = 2, .brace = 0.34 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = GUARD_SH - 26, .offEl = GUARD_EL - 14, .offAbd = GUARD_ABD + 22, .twist = GUARD_TWIST - 20, .lean = 2, .brace = 0.34 } },
        .{ .t = 0.38, .p = .{ .offSh = GUARD_SH + 30, .offEl = GUARD_EL + 26, .offAbd = GUARD_ABD + 46, .twist = GUARD_TWIST + 24, .lean = 12, .head = 8, .brace = 0.62 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .offSh = GUARD_SH + 22, .offEl = GUARD_EL + 18, .offAbd = GUARD_ABD + 36, .twist = GUARD_TWIST + 17, .lean = 9, .head = 6, .brace = 0.56 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = GUARD_SH + 22, .offEl = GUARD_EL + 18, .offAbd = GUARD_ABD + 36, .twist = GUARD_TWIST + 17, .lean = 9, .head = 6, .brace = 0.56 } },
        .{ .t = 1.00, .p = .{ .brace = 0.18 }, .ease = .decel },
    },
};

/// **A ROW PER `MOVES` ROW, IN ITS ORDER**, so a stroke added to that table is a compile error here until it
/// names its key tables. As a `switch (mv)` ending in `else => BASH_KEYS` a new index silently wore the bash's
/// arms — the same shape that cost the SWAT its own beat through `windFor`, and one a length pin cannot see.
const MOVE_KEYS = [MOVES.len]MoveKeys{ SWEEP_KEYS, OVER_KEYS, THRUST_KEYS, BASH_KEYS, SWEEP2_KEYS, BASH_KEYS };

/// `mv` is an index and not an enum. The two rows that answer to a SIDE come through `trackFor` instead
/// (`bashKeys`, `swatKeys`) and the BASH's tables are their base, which is why they sit twice in `MOVE_KEYS`.
fn keysFor(mv: usize) MoveKeys {
    return MOVE_KEYS[@min(mv, MOVE_KEYS.len - 1)];
}
fn bashKeys(shoving: bool) MoveKeys {
    return if (shoving) SHOVE_KEYS else BASH_KEYS;
}
fn swatKeys(shieldSide: bool) MoveKeys {
    return if (shieldSide) SWAT_SHIELD_KEYS else SWAT_SWORD_KEYS;
}

const THR_WIND_SH = 26.0;
const THR_WIND_EL = -52.0;
const THR_WIND_ABD = 14.0;
const THR_WIND_TILT = 60.0;
const THR_WIND_LEAN = -8.0;
/// Chambered to the RIGHT of the door, held there (the wind's last key is a `.hold`) and driven across —
/// cocked on the centre line the point ran through the door's top edge.
const THR_WIND_SWEEP = 30.0;
const THR_OFF_RISE = 9.0;
// The arm is nearly LEVEL and the blade angles DOWN off it (negative tilt), so the point rides forward at a man's
// chest and is still out there at full stretch; pitched down 58 with the blade leading it, the point plunged in
// place 3.6 m out and the far half of the band was a promise.
const THR_HIT_SH = 80.0;
const THR_HIT_EL = -4.0;
const THR_HIT_TILT = -10.0;
const THR_HIT_LEAN = 30.0;
/// The point is carried onto his CENTRE LINE — off the shoulder alone it ran a metre right of a squared man.
const THR_HIT_SWEEP = -40.0;
const THR_HIT_TWIST = -18.0;

const SLM_WIND_SH = -132.0;
const SLM_WIND_EL = -30.0;
const SLM_WIND_ABD = 26.0;
const SLM_WIND_LEAN = -18.0;
const SLM_WIND_TWIST = 14.0;
const SLM_HIT_SH = 64.0;
const SLM_HIT_EL = -10.0;
const SLM_HIT_LEAN = 36.0;
const SLM_HIT_TWIST = -8.0;
const SLM_PITCH_UP = -56.0;
/// Face DOWN when it lands (a test reads the plank's normal). On the forearm the arm's own drop supplies most of
/// the pitch: at 66 the face came down pointing back at him, at 88 further still.
const SLM_PITCH_DOWN = 30.0;
const SLM_CARRY_UP = 0.60 * H;
const SLM_CARRY_END_Y = -0.10 * H;
const SLM_CARRY_FWD = 0.20 * H;

const CHG_LEAN = 22.0;
const CHG_OFF_SH = 34.0;
const CHG_OFF_EL = -96.0;
const CHG_ARM_SH = -38.0;
const CHG_ARM_ABD = 30.0;
const CHG_ARM_SWEEP = -30.0;
const CHG_TILT = 12.0;
const BRAKE_LEAN = -26.0;
const BRAKE_OFF_SH = -20.0;
const BRAKE_OFF_ABD = 44.0;

const P_CHG = P{ .armSh = CHG_ARM_SH, .armEl = -16.0, .armAbd = CHG_ARM_ABD, .armSweep = CHG_ARM_SWEEP, .tilt = CHG_TILT, .offSh = CHG_OFF_SH, .offEl = CHG_OFF_EL, .offAbd = GUARD_ABD + 6.0, .lean = CHG_LEAN, .twist = -10.0, .head = 10.0, .brace = 0.72 };
const P_CHG_RUN = P{ .armSh = CHG_ARM_SH, .armEl = -16.0, .armAbd = CHG_ARM_ABD, .armSweep = CHG_ARM_SWEEP, .tilt = CHG_TILT, .offSh = CHG_OFF_SH, .offEl = CHG_OFF_EL, .offAbd = GUARD_ABD + 6.0, .lean = CHG_LEAN, .twist = -10.0, .head = 10.0, .brace = 0.30 };
const CHG_DRIVE_LEAN = CHG_LEAN + 9.0;
const P_CHG_DRIVE = P{ .armSh = CHG_ARM_SH - 8.0, .armEl = -12.0, .armAbd = CHG_ARM_ABD + 4.0, .armSweep = CHG_ARM_SWEEP - 12.0, .tilt = CHG_TILT + 6.0, .offSh = CHG_OFF_SH + 6.0, .offEl = CHG_OFF_EL - 8.0, .offAbd = GUARD_ABD + 2.0, .lean = CHG_DRIVE_LEAN, .twist = -14.0, .head = 15.0, .brace = 0.44 };
const P_SKID = P{ .armSh = CHG_ARM_SH, .armEl = -16.0, .armAbd = CHG_ARM_ABD, .armSweep = CHG_ARM_SWEEP, .tilt = CHG_TILT, .offSh = BRAKE_OFF_SH, .offEl = GUARD_EL + 30.0, .offAbd = BRAKE_OFF_ABD, .lean = BRAKE_LEAN, .twist = 14.0, .head = -12.0, .brace = 0.85 };
const P_SKID_END = P{ .armSh = CARRY_SH + 4.0, .armEl = CARRY_EL, .armAbd = CARRY_ABD + 10.0, .offSh = BRAKE_OFF_SH, .offEl = GUARD_EL + 30.0, .offAbd = BRAKE_OFF_ABD, .lean = BRAKE_LEAN + 8.0, .twist = 14.0, .head = -12.0, .brace = 0.45 };

const CHARGE_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.30, .p = .{ .lean = GUARD_LEAN + 8, .head = 8, .brace = 0.52, .offSh = GUARD_SH + 6, .offEl = GUARD_EL + 4, .armSh = CARRY_SH - 12, .armSweep = -10 }, .ease = .decel },
        .{ .t = 1.00, .p = P_CHG, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = P_CHG },
        .{ .t = 0.30, .p = P_CHG_RUN, .ease = .decel },
        .{ .t = 1.00, .p = P_CHG_DRIVE, .ease = .accel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = P_CHG_DRIVE },
        .{ .t = 0.38, .p = P_SKID, .ease = .decel },
        .{ .t = 1.00, .p = P_SKID_END },
    },
};
const CHG_LOOSE = 0.62;
const CHG_REC = [_]PoseKey{
    .{ .t = 0.00, .p = P_SKID_END },
    .{ .t = END_HOLD, .p = P_SKID_END },
    .{ .t = 1.00, .p = .{}, .ease = .decel },
};

const HOP_BANK = 8.0;

/// Fraction of the recover — the five-phase contract's held End Pose (docs/ELDEN_RING.md §7).
const END_HOLD = 0.32;

const FALL_WIND_LEAN = -30.0;
const FALL_WIND_GATHER = 24.0;
const FALL_SH = 4.0;
const FALL_EL = -100.0;
const FLOORED_TILT = 4.0;
const RISE_KNEE = 92.0;
const RISE_HIP = 72.0;

/// **HOW FAR A WIND-UP MAY BRING HIM ROUND** (owner: he tracks a bit too much between attacks, needs more room
/// to get behind). Degrees off the facing the gather started from. The RATE is still his full `TURN_RATE` — a man
/// strafing across his front is still followed hard — but a gather may no longer pivot him onto somebody who has
/// walked behind him. Measured before it: a walker was off his front 21% of a 45 s ring and behind him 17%.
const GATHER_SWEEP_MAX: f32 = 60.0;

const GATHER_HEAVY = 1.5;
const GATHER_FALL = 1.9;
const GATHER_PLAIN = 0.95;

const State = enum {
    idle,
    approach,
    hop,
    stepturn,
    leapwind,
    leap,
    awaken,
    sweepwind,
    sweep,
    chainwind,
    sweep2,
    overwind,
    over,
    thrustwind,
    thrust,
    bashwind,
    bash,
    swatwind,
    swat,
    slamwind,
    slam,
    chargewind,
    charge,
    brake,
    recover,
    fallwind,
    fall,
    downed,
    rollover,
    rise,
    stunlight,
    stunheavy,
    dead,
};

const Blow = enum { sweep, sweep2, over, thrust, bash, swat, slam, charge, fall };

const MOVES = [_]Attack{ SWEEP, OVERHEAD, THRUST, BASH, SWEEP2, SWAT };
pub const SWEEP_I = 0;
pub const OVER_I = 1;
pub const THRUST_I = 2;
pub const BASH_I = 3;
pub const SWEEP2_I = 4;
pub const SWAT_I = 5;

comptime {
    // **THE INDICES ARE PINNED TO THE ROWS THEY NAME** — `keysFor`, `routeFor`, `trackFor`, `cdSlot`, `cds`
    // and `takeParry` all resolve through them, so reordering the table silently re-points the whole kit.
    const named = .{ .{ SWEEP_I, SWEEP }, .{ OVER_I, OVERHEAD }, .{ THRUST_I, THRUST }, .{ BASH_I, BASH }, .{ SWEEP2_I, SWEEP2 }, .{ SWAT_I, SWAT } };
    if (named.len != MOVES.len) @compileError("knight: MOVES and the *_I indices disagree on how many strokes there are");
    for (named) |row| {
        if (!std.meta.eql(MOVES[row[0]], row[1])) @compileError("knight: a *_I index no longer names its own row of MOVES");
    }
    std.debug.assert(CHOOSE_N <= MOVES.len and SWEEP2_I >= CHOOSE_N and SWAT_I >= CHOOSE_N);
    // …AND EVERY INDEX HAS ITS OWN GATHER. `windFor` switches on a `usize` and ends in an `else` handing back
    // the BASH's — that is how the SWAT lost its beat: `windFor(SWAT_I)` returned `.bashwind`, so the stroke
    // came out as `.bash`, its `windHold` and `SWAT_SHIELD_WIND` never applied, its impact came off the SHIELD,
    // and `setRecover` played the bash's arms. UNIQUENESS IS THE COVERAGE TEST FOR THAT SWITCH: an index nobody
    // named falls to `.bashwind`, collides with `BASH_I`, and fails the build. A length pin only ever said the
    // two lists were the same SIZE. **THE KEY TABLES ARE COVERED SEPARATELY** — `MOVE_KEYS` is an array as long
    // as `MOVES`, so it cannot silently borrow a row; uniqueness would be wrong there, since the two side-aware
    // rows share the BASH's on purpose.
    for (0..MOVES.len) |i| {
        for (i + 1..MOVES.len) |j| {
            if (windFor(i) == windFor(j))
                @compileError("knight: two MOVES rows share a gather state — a stroke is wearing another's animation");
        }
    }
}
const CHOOSE_N = 4;

const SWEEP_BEARING = 72.0;
/// EVERY gather aims at full `TURN_RATE` now, and the sweep's runs 1.00 s — 183 deg — so a sweep begun out here arrives well inside `SWEEP_BEARING` under its own steam.
const FLANK_BEARING = SWEEP_BEARING + 28.0;

/// docs/ELDEN_RING.md §7: strings run "1-4 hits, variable", recovery "3-4 frames mid-combo, 23-24 at combo end".
fn stringNext(cur: usize) ?usize {
    return switch (cur) {
        SWEEP_I => SWEEP2_I,
        SWEEP2_I => THRUST_I,
        THRUST_I => SWEEP2_I,
        BASH_I => THRUST_I,
        else => null,
    };
}
fn routeFor(mv: usize) []const usize {
    return switch (mv) {
        SWEEP_I => &[_]usize{ SWEEP2_I, THRUST_I, SWAT_I },
        BASH_I => &[_]usize{ THRUST_I, SWEEP_I, SWEEP2_I },
        THRUST_I => &[_]usize{ SWEEP2_I, THRUST_I },
        SWEEP2_I => &[_]usize{ THRUST_I, SWAT_I },
        SWAT_I => &[_]usize{ THRUST_I, SWEEP_I, OVER_I },
        else => &[_]usize{},
    };
}
const STRING_WIND_MUL: f32 = 0.55;
const STRING_CD_PER_LINK: f32 = 0.22;

const PLANT_IN: f32 = 0.30;

const QUAKE_FALL: f32 = 0.46;
const QUAKE_CRATER: f32 = 0.40;
const QUAKE_BRAKE: f32 = 0.24;
const QUAKE_SWEEP: f32 = 0.20;
const QUAKE_OVER: f32 = 0.30;
const QUAKE_BASH: f32 = 0.22;
const QUAKE_REPEL: f32 = 0.14;
const QUAKE_STEP: f32 = 0.07;

/// HALF THE DISTANCE BETWEEN HIS BOOTS, pre-scale.
const TURN_STANCE_HALF: f32 = 0.105;

/// **EVERY STROKE NAMES ITS OWN GATHER.** The `else` is dead air the comptime pin beside `MOVES` polices: it
/// hands back the BASH's, so an unnamed index collides with `BASH_I` and fails the build rather than borrowing
/// a gather.
fn windFor(mv: usize) State {
    return switch (mv) {
        SWEEP_I => .sweepwind,
        OVER_I => .overwind,
        THRUST_I => .thrustwind,
        SWEEP2_I => .chainwind,
        SWAT_I => .swatwind,
        BASH_I => .bashwind,
        else => .bashwind,
    };
}

const Choice = enum { fall, slam, hop, charge, strike, approach, wait, hold, stepturn, leap };

/// docs/ELDEN_RING.md §7's brain: DISTANCE BANDS with DICE ODDS inside each. `roll` is the frame's die.
const Decision = struct { what: Choice, mv: usize = SWEEP_I, shove: bool = false, shoveShield: bool = false };

const BOOTS_SWORD = [_]usize{ BASH_I, SWAT_I, SWEEP_I, BASH_I, THRUST_I };
const BOOTS_SHIELD = [_]usize{ SWEEP_I, BASH_I, SWAT_I, SWEEP_I, OVER_I };
const RANGE_SWORD = [_]usize{ SWEEP_I, THRUST_I, SWAT_I, SWEEP_I, OVER_I };
const RANGE_SHIELD = [_]usize{ OVER_I, SWEEP_I, THRUST_I, SWAT_I, OVER_I };

const Sit = struct {
    dist: f32,
    bearing: f32,
    scale: f32,
    fallReady: bool = false,
    slamReady: bool = false,
    chargeReady: bool = false,
    hopReady: bool = false,
    stepReady: bool = false,
    leapReady: bool = false,
    circling: bool = false,
    pressed: bool = false,
    harried: bool = false,
    lit: bool = false,
    cursor: usize = 0,
    ready: []const bool,

    fn off(self: Sit) f32 {
        return @abs(self.bearing);
    }
    fn shieldSide(self: Sit) bool {
        return self.bearing > 0;
    }
};

// A SCORE AND NEVER A DIE: the same moment always scores the same way.
const W_ROTATION: f32 = 1.00;
const W_FIT: f32 = 0.55;
const W_SQUARE: f32 = 0.40;
/// docs/ELDEN_RING.md §7 — "stand on the shield side" only teaches anything if the sides genuinely differ.
const W_SIDE: f32 = 0.45;
const W_PRESS: f32 = 0.35;
const W_CIRCLE: f32 = 0.45;
const W_LIT: f32 = 0.30;

/// Peaks at 0.72 of the reach. **OFF `bandR`, NOT THE KIT**: a stroke that carries him in fits from further out.
fn fitTerm(mv: usize, dist: f32, scale: f32) f32 {
    const r = bandR(MOVES[mv], scale);
    if (r <= 0) return 0;
    const u = mathx.clampF(dist / r, 0, 1);
    const d = (u - 0.72) / 0.72;
    return mathx.clampF(1.0 - d * d, 0, 1);
}

fn squareTerm(mv: usize, off: f32) f32 {
    const lim = MOVES[mv].bearing;
    if (lim <= 0) return 0;
    return mathx.clampF(1.0 - off / lim, 0, 1);
}

fn sideTerm(mv: usize, shieldSide: bool) f32 {
    return if ((MOVES[mv].weight != .light) == shieldSide) 1.0 else 0.0;
}

fn pressTerm(mv: usize) f32 {
    return if (mv == THRUST_I or mv == BASH_I) 1.0 else 0.0;
}

/// Normalised on the hardest-following row he owns, so this cannot drift when a `track` is retuned.
fn trackTerm(mv: usize) f32 {
    return MOVES[mv].track / TRACK_MOST;
}
/// Solved ONCE at comptime — `trackTerm` was walking the whole table on every candidate of every decision.
const TRACK_MOST: f32 = blk: {
    var most: f32 = 0;
    for (MOVES) |a| {
        if (a.track > most) most = a.track;
    }
    if (most <= 0) @compileError("knight: nothing in the kit tracks at all — `trackTerm` would divide by zero");
    break :blk most;
};

fn litTerm(mv: usize) f32 {
    return if (MOVES[mv].weight != .light) 1.0 else 0.0;
}

/// A move on cooldown is SKIPPED, never waited for. A bearing the arc cannot reach is a HARD gate, not a weight.
fn weigh(pattern: []const usize, sit: Sit) Decision {
    var best: ?usize = null;
    var bestScore: f32 = 0;
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const mv = pattern[(sit.cursor + i) % pattern.len];
        if (!sit.ready[mv]) continue;
        if (sit.off() > MOVES[mv].bearing) continue;
        // A stand the kit cannot reach — too far, or inside its dead zone — is a guaranteed whiff, not a worse choice.
        if (sit.dist > strokeBandR(mv, sit.shieldSide(), sit.scale)) continue;
        if (sit.dist < nearR(MOVES[mv], sit.scale)) continue;
        const place = 1.0 - @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(pattern.len));
        var score = W_ROTATION * place +
            W_FIT * fitTerm(mv, sit.dist, sit.scale) +
            W_SQUARE * squareTerm(mv, sit.off()) +
            W_SIDE * sideTerm(mv, sit.shieldSide());
        if (sit.pressed) score += W_PRESS * pressTerm(mv);
        if (sit.circling) score += W_CIRCLE * trackTerm(mv);
        if (sit.lit) score += W_LIT * litTerm(mv);
        if (best == null or score > bestScore) {
            best = mv;
            bestScore = score;
        }
    }
    if (best) |mv| return .{ .what = .strike, .mv = mv };
    if (sit.stepReady and sit.off() >= STEPTURN.least) return .{ .what = .stepturn };
    return .{ .what = .wait };
}

fn classify(sit: Sit) Decision {
    const dist = sit.dist;
    const scale = sit.scale;
    const fallReady = sit.fallReady;
    const slamReady = sit.slamReady;
    const chargeReady = sit.chargeReady;
    const hopReady = sit.hopReady;
    const stepReady = sit.stepReady;
    const leapReady = sit.leapReady;
    const circling = sit.circling;
    const pressed = sit.pressed;
    const harried = sit.harried;
    const cursor = sit.cursor;
    const ready = sit.ready;
    if (dist > AGGRO_R) return .{ .what = .hold };
    const b = sit.off();
    // His shield is his LEFT arm, which is a POSITIVE bearing here (docs/ELDEN_RING.md §7).
    const shieldSide = sit.shieldSide();
    if (b >= 180.0 - FALL_SECTOR) {
        if (fallReady and dist <= crushLen(scale)) return .{ .what = .fall };
        if (leapReady and harried and dist <= crushLen(scale) * 0.9) return .{ .what = .leap };
        if (hopReady and circling and pressed) return .{ .what = .hop };
        if (stepReady) return .{ .what = .stepturn };
        return .{ .what = .wait };
    }
    if (b > SWEEP_BEARING) {
        if (b <= FLANK_BEARING and ready[SWAT_I] and dist <= swatTriggerR(shieldSide, scale)) {
            return .{ .what = .strike, .mv = SWAT_I };
        }
        if (circling and ready[SWAT_I] and dist <= swatTriggerR(shieldSide, scale) * SWAT_ORBIT_BAND) {
            return .{ .what = .strike, .mv = SWAT_I };
        }
        if (b <= FLANK_BEARING and ready[BASH_I] and dist <= triggerR(MOVES[BASH_I], scale) * SHOVE_BAND) {
            return .{ .what = .strike, .mv = BASH_I, .shove = true, .shoveShield = shieldSide };
        }
        // **BOUGHT WITH PRESENCE, NOT WITH DAMAGE** (owner) — gated on `pressed` too it wanted a fight already
        // in progress, so the one move answering a man circling him only fired at one who was also trading.
        if (hopReady and circling) return .{ .what = .hop };
        if (b <= FLANK_BEARING and ready[SWEEP_I] and dist <= triggerR(MOVES[SWEEP_I], scale)) {
            return .{ .what = .strike, .mv = SWEEP_I };
        }
        if (leapReady and harried and b > FLANK_BEARING) return .{ .what = .leap };
        if (stepReady and b >= STEPTURN.least) return .{ .what = .stepturn };
        return .{ .what = .wait };
    }
    if (dist <= triggerR(MOVES[BASH_I], scale)) {
        if (slamReady and cursor % 3 == 2) return .{ .what = .slam };
        return weigh(if (shieldSide) &BOOTS_SHIELD else &BOOTS_SWORD, sit);
    }
    if (dist <= triggerR(MOVES[SWEEP_I], scale)) {
        return weigh(if (shieldSide) &RANGE_SHIELD else &RANGE_SWORD, sit);
    }
    if (dist <= thrustBandR(scale)) {
        if (b <= THRUST.bearing and ready[THRUST_I]) return .{ .what = .strike, .mv = THRUST_I };
        // **HE SHUTS THE GAP RATHER THAN STANDING IN IT** (owner). Out here with the thrust spent he WAITED —
        // the one band where the player could heal and pick a spell. The hop is 3.2 m in 0.54 s.
        if (hopReady) return .{ .what = .hop };
        if (stepReady and b >= STEPTURN.least) return .{ .what = .stepturn };
        return .{ .what = .wait };
    }
    if (chargeReady and dist >= CHARGE.far * 0.75) return .{ .what = .charge };
    return .{ .what = .approach };
}

fn triggerR(a: Attack, scale: f32) f32 {
    return foe.hurtReach(a.reachOut, scale);
}

fn fallWaveR(scale: f32) f32 {
    return foe.hurtReach(FALL_WAVE_R, scale);
}

/// **THE ONE RADIUS THE SLAM IS DRAWN AND BILLED AT.** `trySlam` has always asked `foe.hurtReach`, so the two FX
/// walking a bare `SLAM.r * scale` drew a disc `foe.HERO_REACH` short of the one that lands.
fn slamRingR(scale: f32) f32 {
    return foe.hurtReach(SLAM.r, scale);
}

fn crushLen(scale: f32) f32 {
    return foe.hurtReach(FALL_LEN, scale);
}

const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;
const SW_GUARD = 0.130 * H;
/// Bracketed from ABOVE by what the sweep may reach: at 0.84·H the blade measured 4.45 m and arrived 6.9 m out.
const SW_BLADE = 0.57 * H;
/// Also the swipes' hurt radius. At 0.032·H it was 8:1 across a near-3 m edge, where a greatsword is nearer 20:1.
const SW_HALF_W = 0.019 * H;
const SW_SEG = [2]rl.Vector3{
    v3(0, FIST_Y + SW_GUARD, FIST_Z),
    v3(0, FIST_Y + SW_GUARD + SW_BLADE, FIST_Z),
};

/// Authored pointing UP off the grip, so the fit flips it; `wpnTilt` then follows `hero.GRIP_PITCH`.
const wpnFit = heromod.staffFit;

pub fn moveClock(mv: usize) foe.Clock {
    return foe.moveClock(MOVES[@min(mv, MOVES.len - 1)]);
}
pub const FallClock = struct { wind: f32, drop: f32, down: f32, roll: f32, rise: f32 };
pub fn fallClock() FallClock {
    return .{ .wind = FALL_WIND_DUR, .drop = FALL_DUR, .down = DOWN_DUR, .roll = ROLL_DUR, .rise = RISE_DUR };
}
pub fn slamClock() foe.Clock {
    return .{ .wind = SLAM.windDur, .strike = SLAM.strikeDur, .recover = SLAM.recoverDur };
}
pub fn chargeClock() foe.Clock {
    return .{ .wind = CHARGE.windDur, .strike = CHARGE.range / CHARGE.speed, .recover = CHARGE.brakeDur + CHARGE.recoverDur };
}
pub fn awakenPeak() f32 {
    return AWAKEN.liftDur + AWAKEN.holdDur * 0.85;
}
pub fn leapPeak() f32 {
    return LEAP.windDur + LEAP.flightDur * 0.5;
}
pub fn stepTurnMid() f32 {
    return STEPTURN.windDur + STEPTURN.turnDur * 0.6;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    shield: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "knight");
        return .{ .bone = buildMeshes(), .shield = shieldMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Knight) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        rl.drawMesh(self.shield, self.mat, k.shXf);
    }
};

pub const Knight = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    parry: foe.Parry = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    atk: usize = SWEEP_I,
    blow: Blow = .sweep,
    cds: [MOVES.len]f32 = [_]f32{0} ** MOVES.len,
    fallCd: f32 = 0,
    slamCd: f32 = 0,
    chargeCd: f32 = 0,
    hopCd: f32 = 0,
    stepCd: f32 = 0,
    leapCd: f32 = 0,
    counterCd: f32 = 0,
    lit: bool = false,
    awoken: bool = false,
    stepThen: ?usize = null,
    air: f32 = 0,
    leapDir: rl.Vector3 = mathx.zero3,
    leapChained: bool = false,
    farT: f32 = 0,
    windHold: f32 = 0,
    riposteCd: f32 = 0,
    strung: u8 = 0,
    strungUsed: [MOVES.len]bool = [_]bool{false} ** MOVES.len,
    opener: usize = SWEEP_I,
    cursor: usize = 0,
    springs: anim.SpringBank(CHAN_N) = .{},
    ringAccum: f32 = 0,
    emberAccum: f32 = 0,
    hopSide: f32 = 1,
    sense: foe.Sense = .{},
    dealt: bool = false,
    strikeFelt: bool = false,
    /// A one-frame flag; the GROUP owns the cloud, which outlives the body that laid it.
    gasAt: ?rl.Vector3 = null,
    gasScale: f32 = 1.0,
    /// Spaced by GROUND COVERED, never by a clock: at the charge's 15.4 m/s and `CHAOS_TRAIL_EVERY`'s 1.50 m
    /// that is ten clouds a second, and the lane keeps its spacing whatever the speed is retuned to.
    trailAt: f32 = 0,
    shoving: bool = false,
    shoveShield: bool = false,
    swatShield: bool = false,
    deathFrom: f32 = 0,
    rollFrom: f32 = 0,
    thud: f32 = 0,
    /// A one-frame magnitude (`justDied`'s rule), read by the group.
    quake: f32 = 0,
    chargeLen: f32 = 0,
    heroHit: ?combat.Hit = null,
    homing: bool = false,
    strokeDone: f32 = 0,
    /// The facing a gather STARTED from, so the aim it is allowed can be measured against it (`GATHER_SWEEP_MAX`).
    windFrom: f32 = 0,
    /// The CHASED door channels — what the arm and `guardUp` both read (`tickDoor`).
    openAmt: f32 = 0,
    acrossAmt: f32 = 0,
    liftAmt: f32 = 0,
    driveAmt: f32 = 0,
    /// The plank's chased FACE, in the world. Zero until the first pose seats it.
    doorFace: rl.Vector3 = mathx.zero3,
    /// The dt the last `pose` is entitled to chase over. `update` stamps it; a bare `pose()` gets a frame.
    poseDt: f32 = 1.0 / 60.0,

    parried: bool = false,
    covered: bool = false,
    blocks: u32 = 0,
    blockT: f32 = mathx.LONG_AGO,

    armSh: f32 = CARRY_SH,
    armEl: f32 = CARRY_EL,
    armAbd: f32 = CARRY_ABD,
    armSweep: f32 = 0,
    wpnTilt: f32 = CARRY_TILT,
    offSh: f32 = GUARD_SH,
    offEl: f32 = GUARD_EL,
    offAbd: f32 = GUARD_ABD,
    bodyLean: f32 = GUARD_LEAN,
    twist: f32 = GUARD_TWIST,
    headPitch: f32 = 3.0,
    headYaw: f32 = 0,
    legBrace: f32 = 0,

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
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,
    bodyXf: rl.Matrix = undefined,
    shXf: rl.Matrix = undefined,
    shieldFix: rl.Matrix = undefined,
    shieldGrip: rl.Vector3 = mathx.zero3,
    wpnWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    wpnIs: ?[2]rl.Vector3 = null,
    shWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    shIs: ?[2]rl.Vector3 = null,
    live: bool = false,
    trail: foe.Trail(TRAIL_N) = .{},

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Knight {
        var k = Knight{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 64871.0, 23);
        k.aiRng = foe.fxStream(seed, 39079.0, 29);
        for (&k.cds) |*c| c.* = 0.3 + seed * 0.8;
        k.springs.seat(k.chanGet());
        k.shieldFix = rl.math.matrixIdentity();
        k.pose();
        calibrateShield(&k);
        k.pose();
        return k;
    }

    fn move(self: *const Knight) Attack {
        return MOVES[@min(self.atk, MOVES.len - 1)];
    }

    pub fn centerWorld(self: *const Knight) rl.Vector3 {
        return foe.markOn(self.xf[ROOT], CENTER_AT);
    }
    pub fn hurtRadius(self: *const Knight) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Knight) f32 {
        return BODY_R * self.scale;
    }
    /// **ON THE GROUND HE IS A CAPSULE, NOT THE RING UNDER HIS BOOTS** (`game.bodyOf`). Taken off the SKULL's own mark, not a length constant; the topple pivots on the ground point at `pos`, so the near cap is exactly the standing ring.
    pub fn bodySeg(self: *const Knight) ?[2]rl.Vector3 {
        if (!self.floored()) return null;
        const head = self.topWorld();
        return .{ self.pos, v3(head.x, self.pos.y, head.z) };
    }
    pub fn lockPoint(self: *const Knight) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], LOCK_AT);
    }
    pub fn topWorld(self: *const Knight) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], TOP_AT);
    }
    pub fn alive(self: *const Knight) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Knight) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Knight) bool {
        return switch (self.state) {
            .stunlight, .stunheavy, .downed, .rollover, .rise, .dead => true,
            else => false,
        };
    }
    pub fn flashFrac(self: *const Knight) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn airborne(self: *const Knight) bool {
        return self.air > foe.AIRBORNE_LIFT;
    }
    pub fn kind(self: *const Knight) wf.FoeKind {
        _ = self;
        return .bone_knight;
    }
    pub fn blocksTaken(self: *const Knight) u32 {
        return self.blocks;
    }
    /// GIANT_KNIGHTS.md: "basically impossible to kill when attacking from the front IF THEY'RE NOT IN AN ATTACK ANIMATION". The SLAM is the other way in (`swipeOpen`, `slamLift`).
    pub fn guardUp(self: *const Knight) bool {
        if (self.gone) return false;
        return switch (self.state) {
            .idle, .approach, .hop, .stepturn, .leapwind, .leap, .awaken, .chargewind, .charge, .brake, .fallwind => true,
            // The sword strokes and their gathers answer the ONE channel; three arms spelled the same test out.
            .sweepwind, .chainwind, .overwind, .swatwind, .thrustwind, .sweep, .sweep2, .over, .swat, .thrust => self.swipeOpen() < 0.5,
            .bashwind, .bash => self.shoveAcross() < 0.5,
            .slamwind => self.t < SLAM.windDur * 0.30,
            .recover => switch (self.blow) {
                .slam => false,
                .sweep, .sweep2, .over, .swat, .thrust => self.swipeOpen() < 0.5,
                .bash => self.shoveAcross() < 0.5,
                else => true,
            },
            .slam, .fall, .downed, .rollover, .rise, .stunlight, .stunheavy, .dead => false,
        };
    }

    /// 0 square across his chest, 1 hauled fully out and edge-on. `guardUp`'s other picture; a test pins the pair.
    fn shoveDir(self: *const Knight) f32 {
        return if (self.shoveShield) 1.0 else -1.0;
    }
    fn shoveAcrossWant(self: *const Knight) f32 {
        if (!self.shoving) return 0;
        return switch (self.state) {
            .bashwind => mathx.smoothstep(0.55, 1.0, self.t / self.windDur()) * 0.25,
            .bash => 0.25 + 0.75 * mathx.smoothstep(0, BASH.strikeDur * 0.40, self.t),
            .recover => if (self.blow == .bash)
                1.0 - mathx.smoothstep(self.recoverDur() * 0.35, self.recoverDur() * 0.92, self.t)
            else
                0,
            else => 0,
        };
    }

    /// Every SWORD stroke takes the door off his front — the thrust too, since its point runs down the centre
    /// line the door hangs on. The bash keeps it because the door IS the bash, and so does the shield-side swat.
    fn swipesNow(self: *const Knight, blow: Blow) bool {
        return switch (blow) {
            .sweep, .sweep2, .over, .thrust => true,
            .swat => !self.swatShield,
            else => false,
        };
    }

    /// **THE DOOR IS A MASS, SO ITS CHANNEL IS CHASED AND NEVER ASSIGNED** (owner: it flies around off his hand
    /// like a kite). `swipeOpenWant`/`shoveAcrossWant` are schedules with seams in them — a flag flipping, a state
    /// changing, `shoving` clearing — and they were read STRAIGHT into the arm, outside the spring bank that
    /// smooths every other channel. Measured: the hub crossed 4.3 m in one frame. Both are chased now at
    /// `DOOR_EASE`, and **`guardUp` reads the CHASED value**, so the mechanic and the picture are still the one
    /// channel and neither can step.
    fn swipeOpen(self: *const Knight) f32 {
        return self.openAmt;
    }
    fn shoveAcross(self: *const Knight) f32 {
        return self.acrossAmt;
    }
    /// **A CHASED CHANNEL HAS TO BE SEATED** (`SpringBank.seat`'s rule). A move dropped into from nothing — a
    /// debug entry, a shot, a test — has no previous frame to inherit the door from, and starting it at 0 made a
    /// combo link look like the plank was still coming across when in a real fight it never left.
    pub fn seatDoor(self: *Knight) void {
        self.openAmt = self.swipeOpenWant();
        self.acrossAmt = self.shoveAcrossWant();
        self.liftAmt = self.slamLiftWant();
        self.driveAmt = self.slamDriveWant();
        // …and the FACE with them: zeroed, the next pose takes its target whole instead of chasing it.
        self.doorFace = mathx.zero3;
    }
    fn slamLift(self: *const Knight) f32 {
        return self.liftAmt;
    }
    fn slamDrive(self: *const Knight) f32 {
        return self.driveAmt;
    }
    fn tickDoor(self: *Knight, dt: f32) void {
        const step = dt * DOOR_EASE;
        self.openAmt = mathx.approach(self.openAmt, self.swipeOpenWant(), step);
        self.acrossAmt = mathx.approach(self.acrossAmt, self.shoveAcrossWant(), step);
        self.liftAmt = mathx.approach(self.liftAmt, self.slamLiftWant(), step);
        self.driveAmt = mathx.approach(self.driveAmt, self.slamDriveWant(), step);
    }

    fn swipeOpenWant(self: *const Knight) f32 {
        const swipe = switch (self.state) {
            // **IT STAYS OUT ACROSS THE COMBO** (owner) — each link's gather used to bring it square again. The
            // OPENER's gather is still guarded; a link that keeps the guard by design puts it back (`swipesNow`).
            .sweepwind, .chainwind, .overwind, .swatwind, .thrustwind => {
                if (!self.swipesNow(self.blow)) return 0;
                if (self.strung > 0) return 1.0;
                // **AND THE PLANK IS ALREADY GOING BY THEN.** It leads to `SWIPE_LEAD_TO`, which is under
                // `guardUp`'s own 0.5, so the flag still flips on the strike and the picture is never behind it.
                const wind = self.windDur();
                return SWIPE_LEAD_TO * mathx.smoothstep(wind * (1.0 - SWIPE_LEAD_K), wind, self.t);
            },
            .sweep, .sweep2, .over, .thrust => true,
            // **RETURNS, DOES NOT FALL THROUGH.** A bare `false` drops into the RECOVER ramp below on `.swat`'s
            // own clock, which reads 1.0 early — the one swat thrown WITH the door then took the door away.
            .swat => if (self.swipesNow(.swat)) true else return 0,
            .recover => if (self.swipesNow(self.blow)) false else return 0,
            else => return 0,
        };
        if (swipe) {
            const dur = self.move().strikeDur;
            return lerpF(SWIPE_LEAD_TO, 1.0, mathx.smoothstep(0, dur * SWIPE_OPEN_K, self.t));
        }
        const dur = self.recoverDur();
        return 1.0 - mathx.smoothstep(dur * SWIPE_SHUT_K0, dur * SWIPE_SHUT_K1, self.t);
    }
    /// 0 standing, 1 flat on his back, NEGATIVE forward. ONE channel, so the picture, the mark, the bar and the crush strip cannot tell four different stories.
    fn toppleAmt(self: *const Knight) f32 {
        return switch (self.state) {
            .fallwind => FALL_WIND_TOPPLE * mathx.smoothstep(FALL_WIND_DUR * 0.20, FALL_WIND_DUR, self.t),
            // Picked up from where the wind left him, so the tell and the drop are ONE motion.
            .fall => blk: {
                const u = mathx.clampF(self.t / FALL_DUR, 0, 1);
                break :blk mathx.minF(1.0, FALL_WIND_TOPPLE + (1.0 - FALL_WIND_TOPPLE) * u * u * 1.08);
            },
            .downed, .rollover => 1.0,
            .rise => -(1.0 - mathx.smoothstep(RISE_DUR * 0.30, RISE_DUR * 0.84, self.t)) +
                RISE_OVERSHOOT * mathx.pulse(self.t / RISE_DUR, 0.74, 0.86, 0.90, 1.0),
            .dead => if (@abs(self.deathFrom) > 0.5) self.deathFrom else deathTopple(self.deathFrom, self.t),
            else => 0,
        };
    }
    /// **HE FALLS, HE IS NOT LOWERED** — quadratic to `DEATH_LAND`, never a smoothstep, then `DEATH_BOUNCE` of overshoot settling back onto its rest.
    fn deathTopple(from: f32, t: f32) f32 {
        if (t < DEATH_LAND) {
            const u = t / DEATH_LAND;
            return lerpF(from, -1.0, u * u);
        }
        const s = (t - DEATH_LAND) / DEATH_SETTLE;
        if (s >= 1.0) return -1.0;
        return -1.0 + DEATH_BOUNCE * mathx.sinf(std.math.pi * s) * (1.0 - s);
    }

    fn rollAmt(self: *const Knight) f32 {
        return switch (self.state) {
            .rollover => mathx.smoothstep(ROLL_DUR * 0.12, ROLL_DUR * 0.92, self.t),
            .dead => self.rollFrom,
            else => 0,
        };
    }

    /// Degrees of wallow while he lies there. Rides his own axis, so it is the SAME channel the rollover turns —
    /// a body cannot be rocking about one axis and turning about another and still read as one mass.
    fn rockAmt(self: *const Knight) f32 {
        if (self.state != .downed) return 0;
        const edge = mathx.minF(
            mathx.smoothstep(0, ROCK_EDGE, self.t),
            mathx.smoothstep(0, ROCK_EDGE, DOWN_DUR - self.t),
        );
        return ROCK_DEG * edge * mathx.sinf(self.t * ROCK_RATE + self.seed * 6.0);
    }
    /// 0 on guard, 1 hauled fully up. THE PICTURE OF `guardUp` and may never disagree with it; this channel drives the door's own PITCH.
    fn slamLiftWant(self: *const Knight) f32 {
        return switch (self.state) {
            .slamwind => mathx.smoothstep(SLAM.windDur * 0.10, SLAM.windDur * 0.70, self.t),
            .slam => 1.0,
            .recover => if (self.blow == .slam)
                1.0 - mathx.smoothstep(self.recoverDur() * 0.30, self.recoverDur() * 0.85, self.t)
            else
                0,
            else => 0,
        };
    }
    fn slamDriveWant(self: *const Knight) f32 {
        return switch (self.state) {
            .slam => mathx.clampF(self.t / (SLAM.strikeDur * SLAM.impactK), 0, 1),
            .recover => if (self.blow == .slam) 1.0 - mathx.smoothstep(0, self.recoverDur() * 0.5, self.t) else 0,
            else => 0,
        };
    }
    fn slamPitch(self: *const Knight) f32 {
        const up = SLM_PITCH_UP * self.slamLift();
        return up + (SLM_PITCH_DOWN - SLM_PITCH_UP) * self.slamDrive() * self.slamLift();
    }
    fn slamCarry(self: *const Knight) rl.Vector3 {
        const lift = self.slamLift();
        if (lift <= 0) return mathx.zero3;
        const drive = self.slamDrive();
        const up = SLM_CARRY_UP * (1.0 - drive) + SLM_CARRY_END_Y * drive;
        const fwd = SLM_CARRY_FWD * drive;
        return v3(0, up * lift, fwd * lift);
    }

    fn recoverDur(self: *const Knight) f32 {
        return switch (self.blow) {
            .sweep, .sweep2, .over, .thrust, .bash, .swat => MOVES[@min(self.atk, MOVES.len - 1)].recoverDur,
            .slam => SLAM.recoverDur,
            .charge => CHARGE.recoverDur,
            .fall => RISE_DUR,
        };
    }

    fn planted(self: *const Knight) f32 {
        return switch (self.state) {
            .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind, .slamwind, .fallwind => mathx.smoothstep(0, PLANT_IN, self.t),
            .sweep, .sweep2, .over, .thrust, .bash, .slam => 1.0,
            .recover => 1.0 - mathx.smoothstep(self.recoverDur() * 0.55, self.recoverDur(), self.t),
            else => 0,
        };
    }
    fn inString(self: *const Knight) bool {
        return self.strung > 0;
    }
    fn floored(self: *const Knight) bool {
        return switch (self.state) {
            .fall, .downed, .rollover, .rise => true,
            else => false,
        };
    }

    fn fdir(self: *const Knight) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Knight, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    /// **A GATHER TURNS HIS SHOULDERS, NOT HIS FEET.** The aim is his full rate and stays that way — what is
    /// capped is the TOTAL it may bring round off the facing the wind started from, so a wind cannot erase
    /// ground you spent the whole recovery buying. Past the cap the answer is the STEP-TURN, which is a move you
    /// can see coming.
    fn holdWindSweep(self: *Knight) void {
        const spun = mathx.wrapPi(self.facing - self.windFrom);
        const cap = mathx.radians(GATHER_SWEEP_MAX);
        if (spun > cap) self.facing = mathx.wrapPi(self.windFrom + cap);
        if (spun < -cap) self.facing = mathx.wrapPi(self.windFrom - cap);
    }
    /// The hero's bearing off his facing, in degrees (0 dead ahead, +-180 behind).
    fn bearingTo(self: *const Knight, hero: rl.Vector3) f32 {
        const d = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(d) < 1e-3) return 0;
        return mathx.degrees(mathx.wrapPi(mathx.headingXZ(d) - self.facing));
    }

    pub fn navWant(self: *const Knight, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .approach) return null;
        return if (self.homing) self.home else hero;
    }

    pub fn update(self: *Knight, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        // The door's own chase is per-SECOND, and `pose` has no dt of its own — unset, `DOOR_TURN_MAX` was
        // silently a per-60-Hz-frame cap, so on a 144 Hz panel the plank turned 2.4x what the constant says.
        self.poseDt = dt;
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        self.live = false;
        self.quake = 0;
        self.gasAt = null;
        // THE ROOTS HAVE THE FEET AND NOTHING ELSE, held unconditionally: he cannot leave the ground.
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.blockT += dt;
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        self.fallCd = mathx.maxF(0, self.fallCd - dt);
        self.slamCd = mathx.maxF(0, self.slamCd - dt);
        self.chargeCd = mathx.maxF(0, self.chargeCd - dt);
        self.hopCd = mathx.maxF(0, self.hopCd - dt);
        self.stepCd = mathx.maxF(0, self.stepCd - dt);
        self.leapCd = mathx.maxF(0, self.leapCd - dt);
        self.counterCd = mathx.maxF(0, self.counterCd - dt);
        self.riposteCd = mathx.maxF(0, self.riposteCd - dt);
        foe.fadeFlash(&self.flash, dt);
        self.thud = mathx.maxF(0, self.thud - dt * 2.8);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        self.trail.age(dt);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const a = self.move();
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const bearing = self.bearingTo(hero);
        const faceWas = self.facing;
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        const fighting = self.leash.roused() or d <= AGGRO_R;
        if (fighting and d > CHARGE.far and !self.leash.goingHome()) {
            self.farT += dt;
        } else {
            self.farT = mathx.maxF(0, self.farT - dt * 2.0);
        }

        // Measured off the world, never the stick. `settled` is false through the moves that carry HIM, or his own travel reads as an orbit.
        self.sense.tick(dt, self.pos, mathx.radians(bearing), self.bodyR(), switch (self.state) {
            .hop, .leapwind, .leap, .chargewind, .charge, .brake => false,
            else => true,
        });

        self.takeParry();
        switch (self.state) {
            .idle => {
                // **HE DOES NOT TURN ON THE SPOT** (owner) — a standing man holds his facing and STEP-TURNS when
                // the bearing warrants it, so where he is looking is a fact you can read and be wrong about.
                self.setCarry(dt);
                // **ORDERS ARE WHAT IT DOES BEFORE IT HAS SEEN ANYBODY** (`foe.postDrive`), refused inside the ring.
                _ = foe.postDrive(self, dt, bounds, WALK_SPEED, d, AGGRO_R, TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (self.t >= 0.18) self.decide(d, bearing);
            },
            .approach => {
                const tgt = if (self.homing) self.home else hero;
                self.faceToward(self.nav.aim(self.pos, tgt), dt);
                const f = self.fdir();
                moveSpeed = WALK_SPEED;
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, f, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(f);
                self.setCarry(dt);
                if (self.homing) {
                    if (d <= AGGRO_R) {
                        self.homing = false;
                        self.decide(d, bearing);
                    } else if (mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) self.enterIdle();
                } else if (d <= self.longestTrigger() or d > AGGRO_R or self.wantsFall(d, bearing) or self.chargeReady()) {
                    self.decide(d, bearing);
                }
            },
            .hop => {
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE * HOP.turnMul, dt);
                self.setHop(self.t);
                const t0 = HOP.windDur;
                const t1 = HOP.windDur + HOP.airDur;
                if (self.t >= t0 and self.t <= t1) {
                    const u = mathx.clampF((self.t - t0) / HOP.airDur, 0, 1);
                    const want = HOP.dist * self.scale * mathx.smoothstep(0, 1, u);
                    const f = self.fdir();
                    mathx.stepXZ(&self.pos, v3(f.z * self.hopSide, 0, -f.x * self.hopSide), want - self.strokeDone, bounds);
                    self.strokeDone = want;
                }
                if (!self.dealt and self.t >= t1) {
                    self.dealt = true;
                    self.plantBurst();
                    sfx.world(.knight_plant, self.pos);
                }
                if (self.t >= t1 + HOP.settleDur) self.enterIdle();
            },
            .awaken => {
                self.setAwaken(self.t);
                self.emitAwaken(dt);
                if (self.t >= AWAKEN.liftDur + AWAKEN.holdDur + AWAKEN.settleDur) {
                    self.lit = true;
                    self.quake = mathx.maxF(self.quake, QUAKE_CRATER);
                    sfx.world(.knight_roar, self.pos);
                    self.chaosBurst(self.centerWorld(), 30);
                    self.decide(d, bearing);
                }
            },
            .leapwind => {
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE, dt);
                self.setLeap(self.t);
                if (self.t >= self.leapWind()) {
                    self.leapDir = mathx.dirXZ(hero, self.pos);
                    if (mathx.lenXZ(self.leapDir) < 1e-4) self.leapDir = mathx.scaleV(self.fdir(), -1);
                    self.enter(.leap);
                }
            },
            .leap => {
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE * LEAP.turnMul, dt);
                self.setLeap(self.leapWind() + self.t);
                const u = mathx.clampF(self.t / LEAP.flightDur, 0, 1);
                const want = LEAP.dist * self.scale * mathx.smoothstep(0, 1, u);
                mathx.stepXZ(&self.pos, self.leapDir, want - self.strokeDone, bounds);
                self.strokeDone = want;
                self.air = LEAP.rise * self.scale * mathx.sinf(u * std.math.pi);
                if (!self.dealt and self.t >= LEAP.flightDur) {
                    self.dealt = true;
                    self.air = 0;
                    self.plantBurst();
                    self.dustBurst(self.pos, 14, 2.6, 0.26);
                    self.quake = mathx.maxF(self.quake, QUAKE_BRAKE);
                    sfx.world(.knight_plant, self.pos);
                }
                if (self.t >= LEAP.flightDur) self.air = 0;
                if (self.t >= LEAP.flightDur + LEAP.landDur) self.decide(d, bearing);
            },
            .stepturn => {
                const t0 = STEPTURN.windDur;
                const t1 = t0 + STEPTURN.turnDur;
                if (self.t >= t0 and self.t <= t1) {
                    const rate = mathx.radians(STEPTURN.sweep) / STEPTURN.turnDur;
                    foe.faceToward(self.pos, &self.facing, hero, rate, dt);
                }
                self.setStepTurn(self.t);
                if (!self.dealt and self.t >= t1) {
                    self.dealt = true;
                    self.plantBurst();
                    self.quake = mathx.maxF(self.quake, QUAKE_STEP * 2.2);
                    sfx.world(.knight_plant, self.pos);
                }
                if (self.t >= t1 + STEPTURN.settleDur) {
                    if (self.stepThen) |mv| {
                        self.stepThen = null;
                        self.atk = mv;
                        self.opener = mv;
                        self.strung = 0;
                        self.enter(windFor(mv));
                    } else self.decide(d, bearing);
                }
            },
            .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind, .swatwind => {
                // **THE GATHER AIMS, THE COMMIT DOES NOT** (owner). At 0.45 of his own turn the overhead brought
                // 16 deg round across a 0.88 s gather against a walk's 0.80 rad/s. `Attack.track` still costs him
                // tracking once committed, which is what leaves the window.
                self.faceToward(hero, dt);
                self.holdWindSweep();
                const dur = self.windDur();
                // ACROSS THE WHOLE GATHER: the track owns its own shape, and an outer easing curve laid over a keyed one is two animators fighting.
                self.setWindKeys(self.t / dur);
                const w = a.weight;
                const load: f32 = if (w == .light) GATHER_PLAIN else GATHER_HEAVY;
                self.emitGather(dt, mathx.clampF(self.t / dur, 0, 1) * load, w);
                // EVERY GATHER NAMES ITS OWN COMMIT. As `else => .bash` a seventh wind added to the prong list
                // above came out as the BASH — the same shape that cost the SWAT its beat through `windFor`.
                if (self.t >= dur) self.enter(switch (self.state) {
                    .sweepwind => .sweep,
                    .chainwind => .sweep2,
                    .overwind => .over,
                    .thrustwind => .thrust,
                    .swatwind => .swat,
                    .bashwind => .bash,
                    else => unreachable,
                });
            },
            .sweep, .sweep2, .over, .thrust, .bash, .swat => {
                const turn: f32 = a.track;
                foe.faceToward(self.pos, &self.facing, hero, turn, dt);
                const k = mathx.clampF(self.t / a.strikeDur, 0, 1);
                self.setStrike(foe.swingCurve(k));
                self.driveStep(k, bounds);
                // Fired ONCE at the impact frame off `dealt`'s own latch, and sized by what lands.
                if (!self.strikeFelt and self.t >= a.strikeDur * a.impactK) {
                    self.strikeFelt = true;
                    self.quake = @max(self.quake, switch (self.state) {
                        .over => QUAKE_OVER,
                        .bash => QUAKE_BASH,
                        else => QUAKE_SWEEP,
                    });
                    const seg = if (self.state == .bash) self.shieldHere() else self.wpnHere();
                    if (self.state == .over) {
                        self.dustBurst(seg[1], 20, 3.4, 0.34);
                        self.grit(seg[1], 12);
                        sfx.world(.knight_slam, seg[1]);
                    } else {
                        self.dustBurst(v3(seg[1].x, self.pos.y, seg[1].z), 9, 2.2, 0.20);
                    }
                    if (self.lit and a.weight != .light) {
                        self.gasAt = v3(seg[1].x, self.pos.y, seg[1].z);
                        self.gasScale = 1.0;
                    }
                }
                if (self.t >= a.strikeDur * a.impactK) self.live = true;
                if (self.t >= a.strikeDur) {
                    self.strungUsed[self.cdSlot()] = true;
                    const chase = @abs(self.bearingTo(hero));
                    if (self.atk == SWAT_I and chase > SWEEP_BEARING and self.harried() and self.leapCd <= 0 and foe.canLeap(&self.root)) {
                        self.billString();
                        self.leapCd = LEAP.cd * self.aiRng.range(0.85, 1.25);
                        self.leapChained = true;
                        self.enter(.leapwind);
                    } else {
                        const nxt: ?usize = blk: {
                            const route = routeFor(self.opener);
                            if (self.strung >= route.len) break :blk null;
                            const n = route[self.strung];
                            if (chase >= SWEEP_BEARING + 15.0) break :blk null;
                            if (d > triggerR(MOVES[n], self.scale) * 1.25) break :blk null;
                            if (d < nearR(MOVES[n], self.scale)) break :blk null;
                            break :blk n;
                        };
                        if (nxt) |n| {
                            self.strung += 1;
                            self.atk = n;
                            self.enter(windFor(n));
                        } else {
                            self.billString();
                            self.enter(.recover);
                        }
                    }
                }
            },
            .slamwind => {
                self.faceToward(hero, dt * 0.40);
                self.setSlamWind(mathx.smoothstep(0, SLAM.windDur * 0.9, self.t));
                self.emitGather(dt, mathx.clampF(self.t / SLAM.windDur, 0, 1) * GATHER_HEAVY, .crushing);
                self.slamRingTell(dt);
                if (self.t >= SLAM.windDur) self.enter(.slam);
            },
            .slam => {
                const k = mathx.clampF(self.t / SLAM.strikeDur, 0, 1);
                self.setSlam(foe.swingCurve(k));
                if (!self.dealt and self.t >= SLAM.strikeDur * SLAM.impactK) {
                    self.dealt = true;
                    self.trySlam(hero);
                    self.slamCrater();
                    self.thud = 0.70;
                    self.quake = QUAKE_CRATER;
                    if (self.lit) {
                        self.gasAt = self.slamMark();
                        self.gasScale = 1.0;
                    }
                }
                if (self.t >= SLAM.strikeDur) {
                    self.slamCd = SLAM.cd * self.aiRng.range(0.85, 1.4);
                    self.enter(.recover);
                }
            },
            .chargewind => {
                    // The one wind allowed to really AIM (1.4x his own turn): what you dodge is the TRAVEL.
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE * 1.4, dt);
                self.setChargeWind(mathx.clampF(self.t / CHARGE.windDur, 0, 1));
                self.emitGather(dt, mathx.clampF(self.t / CHARGE.windDur, 0, 1) * GATHER_HEAVY, .crushing);
                if (self.t >= CHARGE.windDur) {
                    // THE LINE IS COMMITTED HERE and never updates after.
                    self.chargeLen = mathx.minF(mathx.distXZ(self.pos, hero) + CHARGE.overrun, CHARGE.range);
                    self.enter(.charge);
                }
            },
            .charge => {
                self.setCharge(self.t);
                const f = self.fdir();
                const want = mathx.minF(chargeDist(self.t), self.chargeLen);
                const step = want - self.strokeDone;
                mathx.stepXZ(&self.pos, f, step, bounds);
                self.strokeDone = want;
                movedDist = step;
                moveYaw = mathx.headingXZ(f);
                moveSpeed = CHARGE.speed;
                self.chargeWake(dt);
                self.chaosTrail();
                if (self.t >= 0.08) self.live = true;
                if (want >= self.chargeLen) self.enter(.brake);
            },
            .brake => {
                self.setBrake(mathx.clampF(self.t / CHARGE.brakeDur, 0, 1));
                const f = self.fdir();
                const want = brakeDist(self.t);
                const step = want - self.strokeDone;
                mathx.stepXZ(&self.pos, f, step, bounds);
                self.strokeDone = want;
                movedDist = step;
                moveYaw = mathx.headingXZ(f);
                moveSpeed = CHARGE.speed * (1.0 - mathx.clampF(self.t / CHARGE.brakeDur, 0, 1));
                if (self.t >= CHARGE.brakeDur) {
                    self.chargeCd = CHARGE.cd * self.aiRng.range(0.85, 1.35);
                    self.enter(.recover);
                }
            },
            .recover => {
                const dur = self.recoverDur();
                self.setRecover(mathx.clampF(self.t / dur, 0, 1));
                if (self.t >= dur) self.decide(d, bearing);
            },
            .fallwind => {
                foe.faceToward(self.pos, &self.facing, self.awayFrom(hero), FALL_AIM, dt);
                self.setFallWind(mathx.clampF(self.t / FALL_WIND_DUR, 0, 1));
                self.ringTell(dt, self.fallMarkOf(), fallWaveR(self.scale), mathx.clampF(self.t / FALL_WIND_DUR, 0, 1));
                self.emitGather(dt, mathx.clampF(self.t / FALL_WIND_DUR, 0, 1) * GATHER_FALL, .crushing);
                if (self.t >= FALL_WIND_DUR) self.enter(.fall);
            },
            .fall => {
                self.setFalling(mathx.clampF(self.t / FALL_DUR, 0, 1));
                if (!self.dealt and self.t >= FALL_DUR * FALL_IMPACT_K) {
                    self.dealt = true;
                    self.tryCrush(hero, FALL_HIT);
                    // The strip is the body landing ON him; the ring is what the ground does, and only where the body missed.
                    if (self.heroHit == null) self.tryWave(hero, FALL_WAVE_HIT);
                    self.thud = 1.0;
                    self.quake = QUAKE_FALL;
                    self.slamGround();
                }
                if (self.t >= FALL_DUR) self.enter(.downed);
            },
            .downed => {
                self.easeFloored(dt);
                if (self.t >= DOWN_DUR) self.enter(.rollover);
            },
            .rollover => {
                self.setRollover(mathx.clampF(self.t / ROLL_DUR, 0, 1));
                self.driveRoll(bounds);
                if (self.t >= ROLL_DUR) self.enter(.rise);
            },
            .rise => {
                self.setRise(mathx.clampF(self.t / RISE_DUR, 0, 1));
                if (self.t >= RISE_DUR) {
                    self.fallCd = FALL_CD * self.aiRng.range(0.8, 1.4);
                    self.enterIdle();
                }
            },
            .stunlight => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle();
            },
            .stunheavy => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle();
            },
            .dead => {
                self.easeNeutral(dt);
                // `audio.mkKnightDie`'s crash is written to this same instant.
                if (!self.dealt and self.t >= DEATH_LAND) {
                    self.dealt = true;
                    self.quake = mathx.maxF(self.quake, QUAKE_BRAKE);
                    self.dustBurst(mathx.lerpV(self.pos, self.centerWorld(), 0.6), 22, 3.0, 0.34);
                }
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        self.settlePose(dt);

        self.covered = self.guardUp();

        if (moveYaw == null) {
            const dyaw = mathx.wrapPi(self.facing - faceWas);
            const arc = @abs(dyaw) * TURN_STANCE_HALF * H * self.scale;
            if (arc > 1e-5) {
                movedDist += arc;
                moveSpeed = mathx.maxF(moveSpeed, arc / mathx.maxF(dt, 1e-4));
                const f = self.fdir();
                const sign: f32 = if (dyaw > 0) 1.0 else -1.0;
                moveYaw = mathx.headingXZ(v3(f.z * sign, 0, -f.x * sign));
            }
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.footfalls();
        self.tickDoor(dt);
        self.pose();
        if (self.live) self.tryReach(hero);
        switch (self.state) {
            .sweep, .sweep2, .over, .thrust => {
                const seg = self.wpnHere();
                self.trail.push(seg[0], seg[1], self.wpnWas[1], TRAIL_ROOT);
            },
            else => {},
        }
        self.tryHit(blade);
        return self.heroHit;
    }

    fn chargeDist(t: f32) f32 {
        const ta = mathx.minF(t, CHARGE.accel);
        const ramp = CHARGE.speed * ta * ta / (2.0 * CHARGE.accel);
        return ramp + CHARGE.speed * mathx.maxF(0, t - CHARGE.accel);
    }
    fn brakeDist(t: f32) f32 {
        const tb = mathx.minF(t, CHARGE.brakeDur);
        return CHARGE.speed * (tb - tb * tb / (2.0 * CHARGE.brakeDur));
    }

    fn awayFrom(self: *const Knight, hero: rl.Vector3) rl.Vector3 {
        const back = mathx.dirXZ(hero, self.pos);
        return v3(self.pos.x + back.x, self.pos.y, self.pos.z + back.z);
    }

    fn windDur(self: *const Knight) f32 {
        const held = switch (self.state) {
            .overwind, .swatwind => self.windHold,
            else => 0,
        };
        const base = if (self.shoving and self.shoveShield and (self.state == .bashwind))
            self.move().windDur * SHOVE_SHIELD_WIND + held
        else if (self.swatShield and self.state == .swatwind)
            self.move().windDur * SWAT_SHIELD_WIND
        else
            self.move().windDur + held;
        if (self.strung == 0) return base;
        return mathx.maxF(base * STRING_WIND_MUL, foe.TELL_MIN);
    }
    fn cdSlot(self: *const Knight) usize {
        return if (self.atk == SWEEP2_I) SWEEP_I else self.atk;
    }
    /// THE DEBT, PAID ONCE, AT THE END OF THE STRING — dearer the longer it ran (`STRING_CD_PER_LINK`), with the jitter every cooldown in this file carries.
    fn billString(self: *Knight) void {
        const dearer = 1.0 + STRING_CD_PER_LINK * @as(f32, @floatFromInt(self.strung));
        for (&self.strungUsed, 0..) |*u, i| {
            if (!u.*) continue;
            u.* = false;
            self.cds[i] = MOVES[i].cd * dearer * self.aiRng.range(0.82, 1.45);
        }
        self.strung = 0;
    }
    fn longestTrigger(self: *const Knight) f32 {
        var r: f32 = thrustBandR(self.scale);
        for (MOVES[0..CHOOSE_N]) |a| r = mathx.maxF(r, triggerR(a, self.scale));
        return r;
    }
    fn wantsFall(self: *const Knight, dist: f32, bearingDeg: f32) bool {
        return self.fallCd <= 0 and @abs(bearingDeg) >= 180.0 - FALL_SECTOR and dist <= crushLen(self.scale);
    }
    fn chargeReady(self: *const Knight) bool {
        const need = CHARGE.patience * (if (self.lit) CHARGE_LIT_FUSE else 1.0);
        return self.farT >= need and self.chargeCd <= 0 and foe.canLeap(&self.root);
    }

    fn driveStep(self: *Knight, k: f32, bounds: f32) void {
        const reach = self.move().step;
        if (reach <= 0) return;
        switch (self.state) {
            .sweep, .sweep2, .over, .thrust, .bash, .swat => {},
            else => return,
        }
        const e = 1.0 - (1.0 - k) * (1.0 - k);
        const want = reach * self.scale * e;
        mathx.stepXZ(&self.pos, self.fdir(), want - self.strokeDone, bounds);
        self.strokeDone = want;
    }

    fn driveRoll(self: *Knight, bounds: f32) void {
        if (self.state != .rollover) return;
        const f = self.fdir();
        const want = ROLL_SHIFT * self.scale * self.rollAmt();
        mathx.stepXZ(&self.pos, v3(f.z, 0, -f.x), want - self.strokeDone, bounds);
        self.strokeDone = want;
    }

    const CHAN_N = 12;

    const CH_BRACE = 0;
    const CH_LEAN = 1;
    const CH_TWIST = 2;
    const CH_HEAD = 3;
    const CH_ARM_SH = 4;
    const CH_OFF_SH = 5;
    const CH_ARM_ABD = 6;
    const CH_OFF_ABD = 7;
    const CH_ARM_SWEEP = 8;
    const CH_ARM_EL = 9;
    const CH_OFF_EL = 10;
    const CH_TILT = 11;

    fn chanGet(self: *const Knight) Chan {
        var c: Chan = undefined;
        c[CH_BRACE] = self.legBrace;
        c[CH_LEAN] = self.bodyLean;
        c[CH_TWIST] = self.twist;
        c[CH_HEAD] = self.headPitch;
        c[CH_ARM_SH] = self.armSh;
        c[CH_OFF_SH] = self.offSh;
        c[CH_ARM_ABD] = self.armAbd;
        c[CH_OFF_ABD] = self.offAbd;
        c[CH_ARM_SWEEP] = self.armSweep;
        c[CH_ARM_EL] = self.armEl;
        c[CH_OFF_EL] = self.offEl;
        c[CH_TILT] = self.wpnTilt;
        return c;
    }
    fn chanSet(self: *Knight, c: Chan) void {
        self.legBrace = c[CH_BRACE];
        self.bodyLean = c[CH_LEAN];
        self.twist = c[CH_TWIST];
        self.headPitch = c[CH_HEAD];
        self.armSh = c[CH_ARM_SH];
        self.offSh = c[CH_OFF_SH];
        self.armAbd = c[CH_ARM_ABD];
        self.offAbd = c[CH_OFF_ABD];
        self.armSweep = c[CH_ARM_SWEEP];
        self.armEl = c[CH_ARM_EL];
        self.offEl = c[CH_OFF_EL];
        self.wpnTilt = c[CH_TILT];
    }

    fn settlePose(self: *Knight, dt: f32) void {
        var want = self.chanGet();
        const down = switch (self.state) {
            .downed, .rollover, .rise, .dead => true,
            else => false,
        };
        const stiff: f32 = if (down) SPRING_STIFF_DOWN else SPRING_STIFF;
        const zeta: f32 = if (down) 1.0 else SPRING_ZETA;
        self.springs.chase(&want, stiff, zeta, SPRING_FALLOFF, dt);
        self.chanSet(want);
    }

    fn enter(self: *Knight, s: State) void {
        self.leaveAwaken();
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.strikeFelt = false;
        self.live = false;
        self.strokeDone = 0;
        self.trailAt = 0;
        self.windFrom = self.facing;
        switch (s) {
            .bashwind, .thrustwind => {
                self.blow = if (s == .bashwind) .bash else .thrust;
                sfx.world(.swing_light, self.pos);
            },
            .sweepwind => {
                self.blow = .sweep;
                sfx.world(.swing_heavy, self.pos);
            },
            .chainwind => {
                self.blow = .sweep2;
                sfx.world(.swing_light, self.pos);
            },
            .overwind => {
                self.blow = .over;
                self.windHold = if (self.aiRng.float() < 0.45) 0 else self.aiRng.range(0.25, 0.80);
                sfx.world(.swing_heavy, self.pos);
            },
            .slamwind => {
                self.blow = .slam;
                sfx.world(.knight_heave, self.pos);
            },
            .hop => {
                self.dealt = false;
                sfx.world(.knight_step, self.pos);
            },
            .stepturn => {
                self.leapChained = false;
                sfx.world(.knight_step, self.pos);
            },
            .leapwind => {
                sfx.world(.knight_heave, self.pos);
            },
            .leap => sfx.world(.knight_lunge, self.pos),
            .swatwind => {
                // **EVERY WIND STAMPS ITS OWN BLOW.** The swat's did not, so through its strike and recovery
                // `self.blow` named the PREVIOUS move — which `swipeOpen` and `guardUp`'s recover arm both read.
                self.blow = .swat;
                self.windHold = if (self.aiRng.float() < 0.5) 0 else self.aiRng.range(0.10, SWAT_HANG);
                sfx.world(.swing_light, self.pos);
            },
            .awaken => {
                self.leapChained = false;
                sfx.world(.knight_roar, self.pos);
            },
            .chargewind => {
                self.blow = .charge;
                sfx.world(.knight_roar, self.pos);
                self.plantBurst();
            },
            .charge => {
                sfx.world(.knight_heave, self.pos);
                self.plantBurst();
            },
            .brake => {
                self.quake = QUAKE_BRAKE;
                sfx.world(.knight_plant, self.pos);
            },
            .fallwind => {
                self.blow = .fall;
                sfx.world(.knight_roar, self.pos);
                self.plantBurst();
            },
            .sweep, .sweep2, .over, .thrust, .bash => {
                sfx.world(.knight_heave, self.pos);
                self.plantBurst();
            },
            .swat => sfx.world(.knight_swipe, self.pos),
            .slam => sfx.world(.knight_heave, self.pos),
            .rollover => sfx.world(.knight_plant, self.pos),
            .rise => {
                self.turnAbout();
                sfx.world(.knight_step, self.pos);
            },
            else => {},
        }
    }

    fn turnAbout(self: *Knight) void {
        self.facing = mathx.wrapPi(self.facing + std.math.pi);
    }
    fn enterIdle(self: *Knight) void {
        self.state = .idle;
        self.t = 0;
        self.homing = false;
    }
    /// **THE ONE MOVE THAT IS NOT A MOVE.** The roar is a phase CHANGE, and a phase change that can be stagger-cancelled is one the player never sees land.
    pub fn transforming(self: *const Knight) bool {
        return self.state == .awaken;
    }

    /// **A SPENT TRANSFORMATION IS ALWAYS A LIT ONE.** `awoken` latches when he COMMITS; `lit` lands 2.7 s later, so anything taking him out of `.awaken` between the two spent his one phase change. EVERY path out goes through here.
    fn leaveAwaken(self: *Knight) void {
        if (self.transforming() and self.awoken) self.lit = true;
    }

    fn enterStun(self: *Knight, s: State) void {
        self.leaveAwaken();
        self.billString();
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.live = false;
        self.strokeDone = 0;
        self.homing = false;
    }
    fn enterDeath(self: *Knight) void {
        self.deathFrom = self.toppleAmt();
        self.rollFrom = self.rollAmt();
        self.enterStun(.dead);
        self.justDied = true;
    }

    fn circled(self: *const Knight) bool {
        return self.sense.circling(CIRCLE_RATE);
    }

    fn pressed(self: *const Knight) bool {
        return self.sense.pressed(HP_MAX, REPOSITION_AT);
    }

    fn harried(self: *const Knight) bool {
        return self.sense.pressed(HP_MAX, RETREAT_AT);
    }

    fn decide(self: *Knight, dist: f32, bearingDeg: f32) void {
        if (!self.awoken and self.vit.hpFrac() <= AWAKEN.at and self.leash.roused()) {
            self.awoken = true;
            self.billString();
            return self.enter(.awaken);
        }
        if (self.leash.goingHome()) {
            self.homing = true;
            return self.enter(.approach);
        }
        var ready: [MOVES.len]bool = undefined;
        for (&ready, 0..) |*r, i| r.* = self.cds[i] <= 0;
        const dec = classify(.{ .dist = dist, .bearing = bearingDeg, .scale = self.scale, .fallReady = self.fallCd <= 0, .slamReady = self.slamCd <= 0, .chargeReady = self.chargeReady(), .hopReady = self.hopCd <= 0 and foe.canLeap(&self.root), .stepReady = self.stepCd <= 0, .leapReady = self.leapCd <= 0 and foe.canLeap(&self.root), .circling = self.circled(), .pressed = self.pressed(), .harried = self.harried(), .lit = self.lit, .cursor = self.cursor, .ready = &ready });
        switch (dec.what) {
            .fall => self.enter(.fallwind),
            .slam => self.enter(.slamwind),
            .hop => {
                self.hopSide = if (bearingDeg >= 0) 1.0 else -1.0;
                self.hopCd = HOP.cd * self.aiRng.range(0.8, 1.3);
                self.enter(.hop);
            },
            .stepturn => {
                self.stepCd = STEPTURN.cd * self.aiRng.range(0.85, 1.25);
                self.enter(.stepturn);
            },
            .leap => {
                self.leapCd = LEAP.cd * self.aiRng.range(0.85, 1.25);
                self.enter(.leapwind);
            },
            .charge => {
                self.farT = 0;
                self.enter(.chargewind);
            },
            .strike => {
                self.atk = dec.mv;
                self.opener = dec.mv;
                self.shoving = dec.shove;
                self.shoveShield = dec.shoveShield;
                self.swatShield = bearingDeg > 0;
                self.cursor +%= 1;
                self.enter(windFor(dec.mv));
            },
            .approach => {
                self.homing = false;
                self.enter(.approach);
            },
            .wait => {
                self.homing = false;
                self.enterIdle();
            },
            .hold => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.enter(.approach);
                } else self.enterIdle();
            },
        }
    }

    fn wpnHere(self: *const Knight) [2]rl.Vector3 {
        return self.wpnIs orelse self.weaponSeg();
    }
    fn shieldHere(self: *const Knight) [2]rl.Vector3 {
        return self.shIs orelse self.shieldSeg();
    }
    pub fn weaponSeg(self: *const Knight) [2]rl.Vector3 {
        return .{
            rl.math.vector3Transform(SW_SEG[0], self.xf[WPN]),
            rl.math.vector3Transform(SW_SEG[1], self.xf[WPN]),
        };
    }
    pub fn shieldSeg(self: *const Knight) [2]rl.Vector3 {
        return .{
            rl.math.vector3Transform(SH_LOW, self.shXf),
            rl.math.vector3Transform(SH_HIGH, self.shXf),
        };
    }

    /// The hurt shape IS the kit: what it swept this frame against the column the hero stands in, latched to one blow per stroke. **THE DOOR'S HURT WIDTH IS THE RAM, NOT THE WRAP** (`SH_RAM_HALF`).
    fn tryReach(self: *Knight, hero: rl.Vector3) void {
        if (self.dealt) return;
        const door = self.doorSwings();
        const r = foe.hurtReach(if (door) SH_RAM_HALF else SW_HALF_W, self.scale);
        const was = if (door) self.shWas else self.wpnWas;
        const now = if (door) self.shieldHere() else self.wpnHere();
        if (!foe.weaponReaches(was, now, hero, r)) return;
        self.heroHit = if (self.state == .charge) CHARGE.hit else self.move().hit;
        if (self.lit) {
            var h = self.heroHit.?;
            h.dmg += CHAOS_BLAST.hit.dmg;
            h.poise += CHAOS_BLAST.hit.poise;
            h.stance += CHAOS_BLAST.hit.stance;
            h.elem = h.elem.plus(CHAOS_BLAST.hit.elem);
            self.heroHit = h;
            self.chaosBurst(now[1], 18);
            self.quake = mathx.maxF(self.quake, QUAKE_BASH);
        }
        self.dealt = true;
        self.leash.noteCombat();
    }

    /// Which kit the blow is ON. The shield-side swat is the DOOR's flick, and tested on the sword it billed nothing: the sword was at his hip.
    fn doorSwings(self: *const Knight) bool {
        return switch (self.state) {
            .bash, .charge => true,
            .swat => self.swatShield,
            else => false,
        };
    }

    fn trySlam(self: *Knight, hero: rl.Vector3) void {
        const at = self.slamMark();
        if (mathx.distXZ(at, hero) > slamRingR(self.scale)) return;
        self.heroHit = SLAM.hit;
        self.leash.noteCombat();
    }
    pub fn slamMarkOf(self: *const Knight) rl.Vector3 {
        return self.slamMark();
    }
    fn slamMark(self: *const Knight) rl.Vector3 {
        const f = self.fdir();
        return v3(self.pos.x + f.x * SLAM.fwd * self.scale, self.pos.y, self.pos.z + f.z * SLAM.fwd * self.scale);
    }

    /// Where five metres of him ends up, and what the ring is drawn and billed off.
    pub fn fallMarkOf(self: *const Knight) rl.Vector3 {
        const back = mathx.scaleV(self.fdir(), -1);
        const d = FALL_MARK_K * FALL_LEN * self.scale;
        return v3(self.pos.x + back.x * d, self.pos.y, self.pos.z + back.z * d);
    }

    fn tryWave(self: *Knight, hero: rl.Vector3, h: combat.Hit) void {
        const at = self.fallMarkOf();
        if (mathx.distXZ(at, hero) > fallWaveR(self.scale)) return;
        self.heroHit = h;
        self.leash.noteCombat();
    }

    fn tryCrush(self: *Knight, hero: rl.Vector3, h: combat.Hit) void {
        const to = v3(hero.x - self.pos.x, 0, hero.z - self.pos.z);
        const back = mathx.scaleV(self.fdir(), -1);
        const axial = to.x * back.x + to.z * back.z;
        const lateral = @abs(to.x * back.z - to.z * back.x);
        if (axial < -FALL_BACK_SLACK * self.scale or axial > crushLen(self.scale)) return;
        if (lateral > foe.hurtReach(FALL_HALF_W, self.scale)) return;
        self.heroHit = h;
        self.leash.noteCombat();
    }

    fn toImpact(self: *const Knight) ?f32 {
        const a = self.move();
        const live = a.strikeDur * a.impactK;
        return switch (self.state) {
            .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind => (self.windDur() - self.t) + live,
            .sweep, .sweep2, .over, .thrust, .bash => live - self.t,
            .swatwind, .swat => null,
            .idle, .approach, .hop, .stepturn, .leapwind, .leap, .awaken, .slamwind, .slam, .chargewind, .charge, .brake, .recover, .fallwind, .fall, .downed, .rollover, .rise, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Knight) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return self.parryReach(self.move());
    }
    /// Where the kit ARRIVES at the impact frame, hero footprint included — the MOVE's own, never the creature's.
    fn parryReach(self: *const Knight, a: Attack) f32 {
        return foe.hurtReach(a.reachOut, self.scale);
    }

    fn takeParry(self: *Knight) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.cds[self.cdSlot()] = self.move().cd;
        switch (self.state) {
            .bashwind, .thrustwind => self.setStrike(0.32),
            .sweepwind, .chainwind, .overwind => self.setStrike(0.28),
            else => {},
        }
        const far = if (self.state == .bash or self.state == .bashwind) self.shieldHere()[1] else self.wpnHere()[1];
        self.sparks(far, mathx.dirXZ(self.parry.at, self.pos), 18);
        sfx.world(.knight_hurt, self.pos);
        switch (self.vit.hit(.{ .stance = PARRY_STANCE })) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    fn shielded(self: *const Knight, blade: foe.Blade) bool {
        if (!self.covered) return false;
        const at = mathx.lerpV(blade.a, blade.b, 0.5);
        const d = mathx.dirXZ(self.pos, at);
        if (mathx.lenXZ(d) < 1e-4) return true;
        return combat.withinArc(mathx.headingXZ(d), self.facing, TOWER_ARC);
    }

    pub fn tryHit(self: *Knight, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const blocked = self.shielded(blade);
        var b = blade;
        if (blocked) {
            b.hit = combat.guardChipSplit(blade.hit, TOWER_NEGATE, TOWER_NEGATE_ELEM);
            b.hit.stance = blade.hit.stance * TOWER_STANCE_PASS;
        }
        const poiseWas = self.vit.poise;
        var s = foe.reached(self, b) orelse return;
        if (blocked) {
            // The door takes the flinch: what chips through it is damage and the guard-break's own stance, never
            // poise. Restoring the POOL is not enough — the break had already begun a stagger nothing here reads,
            // and a stunned body refuses every pool (`combat.refuseFlinch`).
            if (s.reaction == .light) {
                self.vit.refuseFlinch(poiseWas);
                s.reaction = .none;
            } else self.vit.poise = poiseWas;
            return self.caught(s);
        }
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 0.30, .heavy = 0.55 });
        self.sense.hurt(b.hit.dmg);
        self.chips(s.contact, s.dir, if (heavyBlow) 22 else 13, if (heavyBlow) 3.6 else 2.5);
        sfx.world(.knight_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, 26, 3.2);
                sfx.world(.knight_die, self.pos);
                self.enterDeath();
            },
            .heavy => if (!self.floored() and !self.transforming()) self.enterStun(.stunheavy),
            .light => if (!self.floored() and !self.inString() and !self.transforming()) self.enterStun(.stunlight),
            .none => self.counterFlank(s),
        }
    }

    fn counterFlank(self: *Knight, s: foe.Strike) void {
        if (self.counterCd > 0 or self.floored()) return;
        switch (self.state) {
            .idle, .approach, .recover, .stepturn => {},
            else => return,
        }
        const from = mathx.headingXZ(mathx.scaleV(s.dir, -1));
        const off = mathx.degrees(mathx.wrapPi(from - self.facing));
        const b = @abs(off);
        if (b <= TOWER_ARC) return;
        self.counterCd = COUNTER_CD * self.aiRng.range(0.85, 1.2);
        if (b >= 180.0 - FALL_SECTOR) {
            // His spine's answer is the FALL; the leap only buys ground once he is being shredded there.
            if (self.fallCd <= 0) return self.enter(.fallwind);
            if (self.harried() and self.leapCd <= 0 and foe.canLeap(&self.root)) {
                self.leapCd = LEAP.cd * self.aiRng.range(0.85, 1.25);
                return self.enter(.leapwind);
            }
        }
        self.swatShield = off > 0;
        self.stepThen = SWAT_I;
        self.stepCd = STEPTURN.cd * self.aiRng.range(0.85, 1.25);
        self.enter(.stepturn);
    }

    fn caught(self: *Knight, s: foe.Strike) void {
        self.blockT = 0;
        self.blocks += 1;
        self.shove = mathx.scaleV(self.fdir(), -0.35);
        self.sparks(s.contact, s.dir, 16);
        if (s.reaction == .death) {
            self.hits += 1;
            self.flash = FLASH_DUR;
            sfx.world(.knight_die, self.pos);
            return self.enterDeath();
        }
        sfx.world(.knight_repel, self.pos);
        self.quake = mathx.maxF(self.quake, QUAKE_REPEL);
        self.dustBurst(s.contact, 6, 1.2, 0.14);
        // The SHIELD is untouched — it never breaks. The stance bar behind it does, and a break outranks the riposte, since he cannot throw it.
        if (s.reaction == .heavy) {
            self.hits += 1;
            self.flash = FLASH_DUR;
            self.grit(s.contact, 14);
            sfx.world(.knight_hurt, self.pos);
            if (!self.floored()) self.enterStun(.stunheavy);
            return;
        }
        if ((self.state == .idle or self.state == .approach) and self.riposteCd <= 0 and self.aiRng.float() < 0.60) {
            self.riposteCd = 3.5;
            self.atk = THRUST_I;
            self.enter(.thrustwind);
        }
    }

    pub fn debugBash(self: *Knight) void {
        self.atk = BASH_I;
        self.shoving = false;
        self.shoveShield = false;
        self.enter(.bashwind);
        self.seatDoor();
    }
    pub fn debugShove(self: *Knight, shield: bool) void {
        self.atk = BASH_I;
        self.shoving = true;
        self.shoveShield = shield;
        self.enter(.bashwind);
        self.seatDoor();
    }
    pub fn debugSweep(self: *Knight) void {
        self.atk = SWEEP_I;
        self.enter(.sweepwind);
        self.seatDoor();
    }
    pub fn debugSweep2(self: *Knight) void {
        self.atk = SWEEP2_I;
        // `.chainwind` IS a link — it is never reached any other way — so the door it inherits is the one the
        // stroke before it hauled out, not a guard. Dropped in with `strung` 0 the plank was still across his
        // front while the re-cock swept low through it.
        self.strung = 1;
        self.opener = SWEEP_I;
        self.enter(.chainwind);
        self.seatDoor();
    }
    pub fn debugOverhead(self: *Knight) void {
        self.atk = OVER_I;
        self.enter(.overwind);
        self.windHold = 0;
        self.seatDoor();
    }
    pub fn debugThrust(self: *Knight) void {
        self.atk = THRUST_I;
        self.enter(.thrustwind);
        self.seatDoor();
    }
    pub fn debugSlam(self: *Knight) void {
        self.enter(.slamwind);
        self.seatDoor();
    }
    pub fn debugAwaken(self: *Knight) void {
        self.awoken = true;
        self.enter(.awaken);
        self.seatDoor();
    }
    pub fn debugLeap(self: *Knight) void {
        self.enter(.leapwind);
        self.seatDoor();
    }
    pub fn debugStepTurn(self: *Knight) void {
        self.enter(.stepturn);
        self.seatDoor();
    }
    pub fn debugSwat(self: *Knight, shieldSide: bool) void {
        self.atk = SWAT_I;
        self.swatShield = shieldSide;
        self.enter(.swatwind);
        self.seatDoor();
    }
    pub fn debugHop(self: *Knight, side: f32) void {
        self.hopSide = side;
        self.enter(.hop);
        self.seatDoor();
    }
    pub fn debugCharge(self: *Knight) void {
        self.enter(.chargewind);
        self.seatDoor();
    }
    pub fn debugFall(self: *Knight) void {
        self.enter(.fallwind);
        self.seatDoor();
    }
    pub fn stagger(self: *Knight, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Knight) void {
        self.enterDeath();
    }

    fn setCarry(self: *Knight, dt: f32) void {
        const e = dt * 6.0;
        const breathe = mathx.sinf(self.elapsed * 0.95 + self.seed * 6.28);
        const stalk = self.moving;
        const rec = mathx.maxF(0, 1.0 - self.blockT / 0.26);
        self.armSh = mathx.approach(self.armSh, CARRY_SH + 2.5 * breathe - 4.0 * stalk, e);
        self.armEl = mathx.approach(self.armEl, CARRY_EL, e);
        self.armAbd = mathx.approach(self.armAbd, CARRY_ABD + 2.0 * breathe, e);
        self.armSweep = mathx.approach(self.armSweep, CARRY_SWEEP - 5.0 * stalk, e);
        self.wpnTilt = mathx.approach(self.wpnTilt, CARRY_TILT, e);
        self.offSh = mathx.approach(self.offSh, GUARD_SH + 14.0 * rec, e);
        self.offEl = mathx.approach(self.offEl, GUARD_EL - 8.0 * rec, e);
        self.offAbd = mathx.approach(self.offAbd, GUARD_ABD + 1.5 * breathe, e);
        self.bodyLean = mathx.approach(self.bodyLean, GUARD_LEAN + 1.0 * breathe + 5.0 * stalk + 10.0 * rec, e);
        self.twist = mathx.approach(self.twist, GUARD_TWIST, e);
        self.headPitch = mathx.approach(self.headPitch, 3.0 + 1.4 * breathe - 5.0 * stalk + 8.0 * rec, e);
        self.legBrace = mathx.approach(self.legBrace, 0.16 + 0.5 * rec, e);
    }

    /// `approach` steps in the units of what it is moving, so ONE rate cannot serve an angle and a fraction.
    fn easeNeutral(self: *Knight, dt: f32) void {
        const d = dt * STUN_EASE_DEG;
        self.armSh = mathx.approach(self.armSh, CARRY_SH, d);
        self.armEl = mathx.approach(self.armEl, CARRY_EL, d);
        self.armAbd = mathx.approach(self.armAbd, CARRY_ABD, d);
        self.armSweep = mathx.approach(self.armSweep, CARRY_SWEEP, d);
        self.wpnTilt = mathx.approach(self.wpnTilt, CARRY_TILT, d * 2.0);
        self.offSh = mathx.approach(self.offSh, GUARD_SH, d);
        self.offEl = mathx.approach(self.offEl, GUARD_EL, d);
        self.offAbd = mathx.approach(self.offAbd, GUARD_ABD, d);
        self.bodyLean = mathx.approach(self.bodyLean, GUARD_LEAN, d);
        self.twist = mathx.approach(self.twist, GUARD_TWIST, d * 2.0);
        self.headPitch = mathx.approach(self.headPitch, 3.0, d);
        self.legBrace = mathx.approach(self.legBrace, 0, dt * STUN_EASE_FRAC);
    }

    fn easeFloored(self: *Knight, dt: f32) void {
        const d = dt * 120.0;
        self.armSh = mathx.approach(self.armSh, FALL_SH, d);
        self.armEl = mathx.approach(self.armEl, FALL_EL, d);
        self.armAbd = mathx.approach(self.armAbd, 8.0, d);
        self.armSweep = mathx.approach(self.armSweep, 0, d);
        self.wpnTilt = mathx.approach(self.wpnTilt, FLOORED_TILT, d);
        self.offSh = mathx.approach(self.offSh, FALL_SH, d);
        self.offEl = mathx.approach(self.offEl, FALL_EL, d);
        self.offAbd = mathx.approach(self.offAbd, 6.0, d);
        self.bodyLean = mathx.approach(self.bodyLean, 2.0, d);
        self.twist = mathx.approach(self.twist, 0, d);
        self.headPitch = mathx.approach(self.headPitch, -6.0, d);
        self.legBrace = mathx.approach(self.legBrace, 0, dt * STUN_EASE_FRAC);
    }

    fn setStrike(self: *Knight, k: f32) void {
        self.chanSet(samplePose(self.trackFor().strike, k));
    }
    fn trackFor(self: *const Knight) MoveKeys {
        return switch (self.atk) {
            BASH_I => bashKeys(self.shoving),
            SWAT_I => swatKeys(self.swatShield),
            else => keysFor(self.atk),
        };
    }
    fn setWindKeys(self: *Knight, k: f32) void {
        self.chanSet(samplePose(self.trackFor().wind, k));
    }

    fn setSlamWind(self: *Knight, k: f32) void {
        self.chanSet(samplePose(SLAM_KEYS.wind, k));
        const shiver = mathx.sinf(self.t * 24.0) * 1.5 * mathx.smoothstep(0.72, 1.0, mathx.minF(k, 1.0));
        self.offSh += shiver;
        self.bodyLean += shiver * 0.4;
    }

    fn setSlam(self: *Knight, kW: f32) void {
        self.chanSet(samplePose(SLAM_KEYS.strike, kW));
    }

    fn setHop(self: *Knight, t: f32) void {
        const t0 = HOP.windDur;
        const t1 = HOP.windDur + HOP.airDur;
        const dip = mathx.smoothstep(0, t0, mathx.minF(t, t0)) * (1.0 - mathx.smoothstep(t0, t0 + 0.10, t));
        const air = mathx.clampF((t - t0) / HOP.airDur, 0, 1) * (1.0 - mathx.smoothstep(t1, t1 + 0.06, t));
        const settle = mathx.smoothstep(t1, t1 + HOP.settleDur * 0.8, t);
        const bank = HOP_BANK * self.hopSide * air * (1.0 - settle);
        self.armSh = CARRY_SH;
        self.armEl = CARRY_EL;
        self.armAbd = CARRY_ABD + 6.0 * air;
        self.armSweep = CARRY_SWEEP - 4.0 * air * self.hopSide;
        self.wpnTilt = CARRY_TILT;
        self.offSh = GUARD_SH;
        self.offEl = GUARD_EL;
        self.offAbd = GUARD_ABD;
        self.bodyLean = GUARD_LEAN + 3.0 * air;
        self.twist = GUARD_TWIST + bank;
        self.headPitch = 3.0;
        self.legBrace = 0.16 + 0.55 * dip + 0.30 * mathx.pulse(mathx.clampF((t - t1) / HOP.settleDur, 0, 1), 0, 0.25, 0.45, 0.95);
    }

    fn setAwaken(self: *Knight, t: f32) void {
        const lift = mathx.smoothstep(0, AWAKEN.liftDur, t);
        const hold = mathx.smoothstep(AWAKEN.liftDur, AWAKEN.liftDur + 0.25, t);
        const done = mathx.smoothstep(AWAKEN.liftDur + AWAKEN.holdDur, AWAKEN.liftDur + AWAKEN.holdDur + AWAKEN.settleDur, t);
        const shiver = mathx.sinf(self.elapsed * 30.0) * 2.2 * hold * (1.0 - done);
        self.armSh = lerpF(CARRY_SH, AWK_SH, lift) + shiver;
        self.armEl = lerpF(CARRY_EL, AWK_EL, lift);
        self.armAbd = lerpF(CARRY_ABD, AWK_ABD, lift);
        self.armSweep = lerpF(CARRY_SWEEP, 0, lift);
        self.wpnTilt = lerpF(CARRY_TILT, AWK_TILT, lift) + shiver * 0.5;
        self.offSh = GUARD_SH + 10.0 * lift;
        self.offEl = GUARD_EL;
        self.offAbd = GUARD_ABD + 4.0 * lift;
        self.bodyLean = GUARD_LEAN - AWK_ARCH * lift + 26.0 * done;
        self.twist = GUARD_TWIST;
        self.headPitch = 3.0 - 22.0 * lift + 30.0 * done;
        self.legBrace = 0.16 + 0.44 * lift + 0.30 * done * (1.0 - done);
    }

    fn emitAwaken(self: *Knight, dt: f32) void {
        const seg = self.wpnHere();
        const k = mathx.clampF(self.t / (AWAKEN.liftDur + AWAKEN.holdDur), 0, 1);
        const emitRate = 30.0 + 210.0 * k;
        var owed = foe.emitDue(&self.emberAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const at = mathx.lerpV(seg[0], seg[1], self.fxRng.float());
            elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, at, .chaos, 1, 0.22 + 0.26 * k, self.scale * 0.5);
        }
    }

    fn chaosBurst(self: *Knight, at: rl.Vector3, n: usize) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, mathx.zero3, .chaos, n, self.scale * 0.7);
    }

    fn leapWind(self: *const Knight) f32 {
        return if (self.leapChained) LEAP.windDur * LEAP_CHAIN_WIND else LEAP.windDur;
    }

    fn setLeap(self: *Knight, t: f32) void {
        const t0 = LEAP.windDur;
        const t1 = t0 + LEAP.flightDur;
        const load = mathx.smoothstep(0, t0, mathx.minF(t, t0)) * (1.0 - mathx.smoothstep(t0, t0 + 0.08, t));
        const air = mathx.clampF((t - t0) / LEAP.flightDur, 0, 1) * (1.0 - mathx.smoothstep(t1, t1 + 0.07, t));
        const land = mathx.smoothstep(t1, t1 + LEAP.landDur * 0.7, t);
        self.armSh = CARRY_SH - 26.0 * load + 16.0 * air;
        self.armEl = CARRY_EL - 30.0 * load - 10.0 * air;
        self.armAbd = CARRY_ABD + 6.0 * load + 20.0 * air;
        self.armSweep = CARRY_SWEEP - 8.0 * air;
        self.wpnTilt = CARRY_TILT + 22.0 * air;
        self.offSh = GUARD_SH + 12.0 * load + 6.0 * air;
        self.offEl = GUARD_EL - 8.0 * load;
        self.offAbd = GUARD_ABD + 4.0 * load;
        self.bodyLean = GUARD_LEAN + 16.0 * load - 12.0 * air + 8.0 * land * (1.0 - land);
        self.twist = GUARD_TWIST;
        self.headPitch = 3.0 + 8.0 * load - 6.0 * air;
        self.legBrace = 0.16 + 0.72 * load - 0.14 * air +
            0.40 * mathx.pulse(mathx.clampF((t - t1) / LEAP.landDur, 0, 1), 0, 0.20, 0.42, 0.95);
    }

    fn setStepTurn(self: *Knight, t: f32) void {
        const t0 = STEPTURN.windDur;
        const t1 = t0 + STEPTURN.turnDur;
        const dip = mathx.smoothstep(0, t0, mathx.minF(t, t0)) * (1.0 - mathx.smoothstep(t1, t1 + 0.10, t));
        const drive = mathx.clampF((t - t0) / STEPTURN.turnDur, 0, 1);
        const settle = mathx.smoothstep(t1, t1 + STEPTURN.settleDur * 0.7, t);
        const lead = mathx.pulse(t / (t1 + STEPTURN.settleDur), 0.10, 0.42, 0.58, 1.0);
        self.armSh = CARRY_SH - 8.0 * dip;
        self.armEl = CARRY_EL;
        self.armAbd = CARRY_ABD + 10.0 * drive * (1.0 - settle);
        self.armSweep = CARRY_SWEEP - 12.0 * lead;
        self.wpnTilt = CARRY_TILT + 6.0 * drive;
        self.offSh = GUARD_SH + 6.0 * dip;
        self.offEl = GUARD_EL;
        self.offAbd = GUARD_ABD + 4.0 * dip;
        self.bodyLean = GUARD_LEAN + 9.0 * dip - 4.0 * settle;
        self.twist = GUARD_TWIST + STEP_LEAD * lead;
        self.headPitch = 3.0 - 6.0 * dip;
        self.legBrace = 0.16 + 0.52 * dip + 0.26 * mathx.pulse(mathx.clampF((t - t1) / STEPTURN.settleDur, 0, 1), 0, 0.22, 0.44, 0.95);
    }

    fn setChargeWind(self: *Knight, k: f32) void {
        self.chanSet(samplePose(CHARGE_KEYS.wind, k));
        const shiver = mathx.sinf(self.t * 24.0) * 1.4 * mathx.smoothstep(0.60, 1.0, mathx.minF(k, 1.0));
        self.bodyLean += shiver;
    }

    fn setCharge(self: *Knight, t: f32) void {
        self.chanSet(samplePose(CHARGE_KEYS.strike, mathx.clampF(t / CHG_LOOSE, 0, 1)));
    }

    fn setBrake(self: *Knight, u: f32) void {
        self.chanSet(samplePose(CHARGE_KEYS.recover, u));
    }

    fn setRecover(self: *Knight, u: f32) void {
        const track = switch (self.blow) {
            .sweep => SWEEP_KEYS,
            .sweep2 => SWEEP2_KEYS,
            .over => OVER_KEYS,
            .thrust => THRUST_KEYS,
            .bash => bashKeys(self.shoving),
            .swat => swatKeys(self.swatShield),
            .slam => SLAM_KEYS,
            .charge => return self.chanSet(samplePose(&CHG_REC, u)),
            .fall => FALL_KEYS,
        };
        self.chanSet(samplePose(track.recover, u));
    }

    fn setFallWind(self: *Knight, k: f32) void {
        self.chanSet(samplePose(FALL_KEYS.wind, k));
        const shiver = mathx.sinf(self.t * 24.0) * 1.6 * mathx.smoothstep(0.66, 1.0, mathx.minF(k, 1.0));
        self.bodyLean += shiver;
    }

    fn setFalling(self: *Knight, k: f32) void {
        self.chanSet(samplePose(FALL_KEYS.strike, k));
    }

    fn setRollover(self: *Knight, u: f32) void {
        const throwArm = mathx.pulse(u, 0, 0.30, 0.50, 0.92);
        const drive = mathx.pulse(u, 0.06, 0.34, 0.62, 1.0);
        self.armSh = FALL_SH - 54.0 * throwArm;
        self.armEl = FALL_EL - 32.0 * throwArm;
        self.armAbd = 8.0 + 36.0 * throwArm;
        self.armSweep = -28.0 * throwArm;
        self.wpnTilt = FLOORED_TILT;
        self.offSh = FALL_SH + 32.0 * drive;
        self.offEl = FALL_EL - 46.0 * drive;
        self.offAbd = 6.0 + 28.0 * drive;
        self.bodyLean = 2.0 + 16.0 * throwArm;
        self.twist = -24.0 * throwArm;
        self.headPitch = -6.0 + 18.0 * throwArm;
        self.legBrace = 0;
    }

    fn setRise(self: *Knight, u: f32) void {
        const push = mathx.pulse(u, 0.10, 0.40, 0.58, 0.92);
        const up = mathx.smoothstep(0.34, 1.0, u);
        self.offSh = lerpF(FALL_SH, GUARD_SH, up) - 34.0 * push;
        self.offEl = lerpF(FALL_EL, GUARD_EL, up) - 26.0 * push;
        self.offAbd = lerpF(6.0, GUARD_ABD, up) + 20.0 * push;
        self.armSh = lerpF(FALL_SH, CARRY_SH, up);
        self.armEl = lerpF(FALL_EL, CARRY_EL, up);
        self.armAbd = lerpF(8.0, CARRY_ABD, up);
        self.wpnTilt = lerpF(FLOORED_TILT, CARRY_TILT, up);
        self.bodyLean = lerpF(2.0, GUARD_LEAN, up) + 22.0 * push;
        self.twist = lerpF(0, GUARD_TWIST, up);
        self.headPitch = lerpF(-6.0, 3.0, up) + 14.0 * push;
        self.legBrace = mathx.pulse(u, 0.18, 0.52, 0.70, 1.0);
    }

    fn stunAmount(self: *const Knight) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn rigScale(self: *const Knight) f32 {
        return foe.rigScale(self.scale, self.fade);
    }

    pub fn pose(self: *Knight) void {
        const fs = self.rigScale();
        const sink = foe.rigSink(0.9, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const stun = self.stunAmount();
        const topple = self.toppleAmt();
        const roll = self.rollAmt();
        const rock = self.rockAmt();
        const down = @abs(topple);

        const m = self.moving * (1.0 - down) * (1.0 - self.planted());
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const sway = heromod.strafeSway(0, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB);
        const braceSink = 0.034 * H * self.legBrace;

        var wx: [N]rl.Matrix = undefined;
        const bodyPitch = self.bodyLean * (1.0 - down) - 26.0 * stun;
        const pitchRoot = bodyPitch * PELVIS_SHARE;
        const ring = self.thud * mathx.sinf((1.0 - self.thud) * 3.0 * std.math.pi);
        const hump = ROLL_HUMP * mathx.sinf(std.math.pi * roll);
        const lieLift = (LIE_LIFT * down + 0.10 * ring + hump) * self.scale + self.air;
        const pelvY = hipY + bob - braceSink;

        self.bodyXf = mul3(ry(180.0 * roll + rock), rx(-TOPPLE_DEG * topple), ry(facingDeg));
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(0), rx(pitchRoot), ry(prot + self.twist * 0.20 + 180.0 * roll + rock)),
            mul3(tr(sway * fs, pelvY * fs + sink, 0), rx(-TOPPLE_DEG * topple), tr(0, lieLift, 0)),
            mul(ry(facingDeg), heromod.rootAt(self.pos)),
        ));

        if (!dead and !self.floored()) {
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, 0, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, 0, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, stun, dead, prot, bodyPitch);
        self.xf = wx;
        self.shXf = shieldXf(self, self.poseDt);
        const seg = self.weaponSeg();
        self.wpnWas = self.wpnIs orelse seg;
        self.wpnIs = seg;
        const sh = self.shieldSeg();
        self.shWas = self.shIs orelse sh;
        self.shIs = sh;
    }

    fn poseUpper(self: *Knight, wx: *[N]rl.Matrix, stun: f32, dead: bool, prot: f32, bodyPitch: f32) void {
        const rest = self.rest;
        const wonk = (self.seed - 0.5) * 5.0;
        const waist = bodyPitch * (1.0 - PELVIS_SHARE);
        const dk = if (dead) mathx.smoothstep(0, DEATH_DUR * 0.5, self.t) else 0;
        const rise = if (self.state == .rise) mathx.pulse(self.t / RISE_DUR, 0.18, 0.52, 0.70, 1.0) else 0;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.44), ry(-0.35 * prot + self.twist * 0.40), rz(wonk * 0.5)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.56), ry(-0.5 * prot + self.twist * 0.60), rz(-wonk * 0.3)));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.4 - 8.0 * stun + 10.0 * dk));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.6 - 28.0 * stun + 18.0 * dk),
            ry(self.headYaw - self.twist * 0.3),
            rz(wonk + 10.0 * dk),
        ));

        if (dead) {
            // **A FELLED STATUE DOES NOT CURL** — flat, both legs are STRAIGHT. Hip/knee bend threw both boots 3.30 m in the air behind him, twice his own knee.
            setLocal(wx, HIPL, rest, mul(rx(-5.0 * dk), rz(-6.0)));
            setLocal(wx, KNEEL, rest, rx(6.0 + 5.0 * dk));
            setLocal(wx, ANKL, rest, rx(-9.0 * dk));
            setLocal(wx, HIPR, rest, mul(rx(-2.0 * dk), rz(5.0)));
            setLocal(wx, KNEER, rest, rx(6.0 + 3.0 * dk));
            setLocal(wx, ANKR, rest, rx(-5.0 * dk));
        } else if (self.floored()) {
            const cross = if (self.state == .rollover) mathx.pulse(self.t / ROLL_DUR, 0, 0.26, 0.54, 0.96) else 0;
            setLocal(wx, HIPL, rest, mul(rx(-RISE_HIP * rise - 30.0 * cross), rz(-4.0 - 20.0 * cross)));
            setLocal(wx, KNEEL, rest, rx(4.0 + RISE_KNEE * rise + 46.0 * cross));
            setLocal(wx, ANKL, rest, rx(-14.0 * rise));
            setLocal(wx, HIPR, rest, mul(rx(-8.0 * rise - 6.0 * cross), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(4.0 + 20.0 * rise + 12.0 * cross));
            setLocal(wx, ANKR, rest, rx(8.0 * rise));
        }

        const armStun = -58.0 * stun;
        setLocal(wx, SHR, rest, mul3(
            rx(-self.armSh + armStun - 20.0 * dk),
            rz(-self.armAbd + wonk * 0.4),
            ry(-self.armSweep),
        ));
        setLocal(wx, ELR, rest, rx(self.armEl));
        setLocal(wx, WRR, rest, rz(-4.0));
        setLocal(wx, WPN, rest, wpnFit(self.wpnTilt));

        // Applied here rather than in each `set*` so the picture cannot drift from `guardUp` — a test pins them.
        const open = self.swipeOpen();
        const across = self.shoveAcross();
        setLocal(wx, SHL, rest, mul3(
            rx(-(self.offSh - SWIPE_SH * open) + armStun - 16.0 * dk),
            rz(-(self.offAbd + SWIPE_ABD * open) - wonk * 0.4),
            ry(self.armSweep * 0.30 + SWIPE_YAW * open + SHOVE_YAW * across * self.shoveDir()),
        ));
        setLocal(wx, ELL, rest, rx(self.offEl));
        setLocal(wx, WRL, rest, rz(5.0));
    }



    const PUFF = foe.Puff{
        .blast = foe.Blast.of(foe.DUST_DRAG, 0.42, 0.76),
        .spdLo = 0.45,
        .upLo = 0.8,
        .upHi = 3.0,
        .rLo = 0.08,
        .rHi = 0.17,
        .bigJit = .{ 0.8, 1.35 },
    };
    fn dustBurst(self: *Knight, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        foe.puff(&self.parts, &self.fxHead, &self.fxRng, v3(c.x, self.pos.y + 0.06, c.z), n, spd, big, self.scale, PUFF);
    }
    fn grit(self: *Knight, c: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(1.3, 3.6) * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(c.x, self.pos.y + 0.09, c.z),
                .v = v3(mathx.cosf(a) * s, self.fxRng.range(2.6, 5.6), mathx.sinf(a) * s),
                .life = self.fxRng.range(0.48, 0.9),
                .r0 = self.fxRng.range(0.026, 0.058) * self.scale,
                .r1 = 0.012,
                .col = CHIP,
                .grav = 9.0,
                .stretch = 0.030,
                .bounce = 0.42,
            });
        }
    }
    fn chips(self: *Knight, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, CHIP_SPRAY);
    }
    fn sparks(self: *Knight, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.5, 4.4);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(-dir.x * sp * 0.5 + mathx.cosf(a) * sp * 0.6, self.fxRng.range(1.2, 3.8), -dir.z * sp * 0.5 + mathx.sinf(a) * sp * 0.6),
                .life = self.fxRng.range(0.16, 0.34),
                .r0 = self.fxRng.range(0.015, 0.032),
                .r1 = 0.002,
                .col = SPARK,
                .col1 = SPARK_COOL,
                .grav = 6.0,
                .stretch = 0.055,
                .bounce = 0.45,
                .add = true,
            });
        }
    }
    fn plantBurst(self: *Knight) void {
        const f = self.fdir();
        for ([_]f32{ -1, 1 }) |side| {
            const rr = 0.40 * self.scale;
            const at = v3(self.pos.x - f.z * side * rr, self.pos.y + 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(at, 10, 2.1, 0.22);
        }
    }
    fn slamGround(self: *Knight) void {
        const mid = self.fallMarkOf();
        const from = self.fxHead;
        self.dustBurst(mid, 48, 5.8, 0.52);
        self.grit(mid, 20);
        // AND THE WAVE IS SEEN TO ARRIVE, at the radius it bills: dust thrown OUTWARD off the rim, not a puff at the middle.
        const reach = fallWaveR(self.scale);
        var i: i32 = 0;
        while (i < 30) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = reach * self.fxRng.range(0.80, 1.0);
            const p = v3(mid.x + mathx.cosf(a) * rr, self.pos.y + 0.05, mid.z + mathx.sinf(a) * rr);
            const spd = self.fxRng.range(2.4, 4.6);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = p,
                .v = v3(mathx.cosf(a) * spd, self.fxRng.range(1.0, 2.6), mathx.sinf(a) * spd),
                .life = self.fxRng.range(0.45, 0.80),
                .r0 = self.fxRng.range(0.10, 0.20) * self.scale,
                .r1 = 0.02 * self.scale,
                .col = DUST,
                .grav = 2.2,
            });
        }
        foe.floorBurst(&self.parts, from, self.fxHead, self.pos.y);
        sfx.world(.knight_slam, mid);
    }
    fn slamRingTell(self: *Knight, dt: f32) void {
        self.ringTell(dt, self.slamMark(), slamRingR(self.scale), mathx.clampF(self.t / SLAM.windDur, 0, 1));
    }
    /// **THE DISC IS DRAWN BEFORE IT IS BILLED** — the blow own circle walked during the WIND, off the same mark
    /// and radius the mechanic uses. Two moves take a disc now, so the walk is one function and the caller owns
    /// where and how big.
    fn ringTell(self: *Knight, dt: f32, at: rl.Vector3, reach: f32, k: f32) void {
        const emitRate = 10.0 + 52.0 * k;
        var owed = foe.emitDue(&self.ringAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = reach * self.fxRng.range(0.94, 1.04);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, self.pos.y + 0.04, at.z + mathx.sinf(a) * rr),
                .v = v3(0, self.fxRng.range(0.5, 1.6) * (0.4 + k), 0),
                .life = self.fxRng.range(0.30, 0.55),
                .r0 = self.fxRng.range(0.030, 0.062) * self.scale,
                .r1 = 0.010,
                .col = EMBER_MARK,
                .col1 = EMBER_MARK_COOL,
                .grav = 0.9,
                .add = true,
            });
        }
    }

    /// The picture and the blow share `SLAM.r` and `slamMark`, so the FX cannot promise a smaller ring than the mechanic bills.
    fn slamCrater(self: *Knight) void {
        const at = self.slamMark();
        const reach = slamRingR(self.scale);
        var i: i32 = 0;
        while (i < 44) : (i += 1) {
            const a = self.fxRng.angle();
            const life = self.fxRng.range(0.40, 0.62);
            const sp = reach / life * self.fxRng.range(0.75, 1.0);
            // NO DRAG and NOT `foe.DUST_GRAV`. Its speed is solved as reach/life to land exactly on `SLAM.r`, so
            // drag would take back the reach the ring already promised, and a hanging gravity would leave it there after the blow is over.
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * 0.4 * self.scale, self.pos.y + 0.10, at.z + mathx.sinf(a) * 0.4 * self.scale),
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.5, 1.7), mathx.sinf(a) * sp),
                .life = life,
                .r0 = self.fxRng.range(0.11, 0.19) * self.scale,
                .r1 = 0.42 * self.fxRng.range(0.8, 1.3) * self.scale,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = 4.2,
            });
        }
        self.grit(at, 18);
        sfx.world(.knight_slam, at);
    }
    fn chaosTrail(self: *Knight) void {
        if (!self.lit) return;
        if (self.strokeDone - self.trailAt < CHAOS_TRAIL_EVERY * self.scale) return;
        self.trailAt = self.strokeDone;
        const at = self.heelPoint();
        self.gasAt = v3(at.x, self.pos.y, at.z);
        self.gasScale = CHAOS_TRAIL_SCALE;
    }

    fn heelPoint(self: *const Knight) rl.Vector3 {
        const back = mathx.scaleV(self.fdir(), -1);
        return v3(self.pos.x + back.x * HEEL_BACK * self.scale, self.pos.y, self.pos.z + back.z * HEEL_BACK * self.scale);
    }

    fn chargeWake(self: *Knight, dt: f32) void {
        const emitRate = 46.0;
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const back = mathx.scaleV(self.fdir(), -1);
            const heel = self.heelPoint();
            const side = self.fxRng.signed() * 0.45 * self.scale;
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.34, 0.60);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(heel.x - back.z * side, self.pos.y + 0.18, heel.z + back.x * side),
                .v = v3(back.x * self.fxRng.range(1.2, 2.8) * self.scale * B.boost, self.fxRng.range(1.6, 3.4) * B.boost, back.z * self.fxRng.range(1.2, 2.8) * self.scale * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.08, 0.15) * self.scale,
                .r1 = 0.34 * self.fxRng.range(0.8, 1.2) * self.scale,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }
    fn emitGather(self: *Knight, dt: f32, k: f32, w: Weight) void {
        const emitRate = (6.0 + 28.0 * k);
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 0.8) * self.scale;
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.28, 0.52);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.05, self.pos.z + mathx.sinf(a) * rr),
                .v = v3(self.fxRng.signed() * 0.5 * B.boost, self.fxRng.range(0.3, 1.4) * B.boost, self.fxRng.signed() * 0.5 * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.035, 0.08) * self.scale,
                .r1 = 0.014,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
        const fire = w.ember();
        if (fire <= 0) return;
        const emberRate = (14.0 + 78.0 * k) * fire;
        var emberOwed = foe.emitDue(&self.emberAccum, dt, emberRate);
        while (emberOwed > 0) : (emberOwed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.52, 1.18) * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.04, self.pos.z + mathx.sinf(a) * rr),
                .v = v3(self.fxRng.signed() * 0.2, self.fxRng.range(2.2, 5.4) * (0.6 + 0.6 * fire), self.fxRng.signed() * 0.2),
                .life = self.fxRng.range(0.46, 0.86),
                .r0 = self.fxRng.range(0.038, 0.082) * self.scale * (0.7 + 0.5 * fire),
                .r1 = 0.010,
                .col = EMBER_MARK,
                .col1 = EMBER_MARK_COOL,
                .grav = -0.7,
                .stretch = 0.028,
                .add = true,
            });
        }
    }
    fn footfalls(self: *Knight) void {
        if (self.moving < 0.4 or self.staggered()) {
            self.prevPhase = self.phase;
            return;
        }
        const crossed = (self.prevPhase < 0.5 and self.phase >= 0.5) or (self.phase < self.prevPhase);
        self.prevPhase = self.phase;
        if (!crossed) return;
        const side: f32 = if (self.phase < 0.5) 1.0 else -1.0;
        const f = self.fdir();
        const rr = 0.13 * H * self.scale;
        const at = v3(self.pos.x - f.z * side * rr, self.pos.y + 0.05, self.pos.z + f.x * side * rr);
        self.dustBurst(at, 9, 1.7, 0.19);
        self.quake = mathx.maxF(self.quake, QUAKE_STEP);
        sfx.world(.knight_step, at);
    }
    pub fn drawFx(self: *const Knight) void {
        foe.drawParticles(&self.parts);
        self.trail.draw(TRAIL_LIFE, foe.WAKE, TRAIL_PEAK);
    }

    pub fn draw(self: *const Knight, model: *const Model) void {
        model.draw(self);
    }

    /// A boss slain in an earlier session comes back already gone (`save.scatter`) — straight to the terminal state `foe.dissipate` leaves. `gone` is what `update`, `alive` and `foe.drawGroup` each early-out on.
    pub fn markSlain(self: *Knight) void {
        self.vit.hp = 0;
        self.vit.dead = true;
        self.state = .dead;
        self.t = DEATH_DUR + DISS_DUR;
        self.fade = 1;
        self.gone = true;
    }
};

const CAP = wf.MAX_PER_KIND;

pub const Vigil = struct {
    model: Model,
    knights: [CAP]Knight = undefined,
    n: usize = 0,
    gas: [GAS_CAP]Gas = [_]Gas{.{}} ** GAS_CAP,
    gasHead: usize = 0,
    gasT: f32 = 0,

    pub fn init(shader: rl.Shader) Vigil {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Vigil) []Knight {
        return self.knights[0..self.n];
    }
    pub fn liveConst(self: *const Vigil) []const Knight {
        return self.knights[0..self.n];
    }
    pub fn reset(self: *Vigil, m: *const wf.Map) void {
        self.clearGas();
        foe.resetGroup(Knight, &self.knights, &self.n, m, .bone_knight);
    }
    pub fn clear(self: *Vigil) void {
        self.n = 0;
        self.clearGas();
    }
    fn clearGas(self: *Vigil) void {
        for (&self.gas) |*g| g.* = .{};
        self.gasHead = 0;
        self.gasT = 0;
    }
    fn spawnGas(self: *Vigil, at: rl.Vector3, scale: f32) void {
        self.gas[self.gasHead] = .{
            .pos = at,
            .scale = scale,
            .live = true,
            .fxRng = foe.fxStream(at.x + at.z, 641.0, 0x6A50),
        };
        self.gasHead = (self.gasHead + 1) % GAS_CAP;
    }
    pub fn gasDose(self: *Vigil, dt: f32, hero: rl.Vector3) ?foe.Blow {
        var inIt: ?rl.Vector3 = null;
        for (&self.gas) |*g| {
            if (g.covers(hero)) inIt = g.pos;
        }
        const at = inIt orelse {
            // **SEEDED AT THE INTERVAL, NOT AT ZERO** (`foe.Soak`'s note): the frame you cross is the frame it bills.
            self.gasT = GAS_DOSE_EVERY;
            return null;
        };
        self.gasT += dt;
        if (self.gasT < GAS_DOSE_EVERY) return null;
        self.gasT -= GAS_DOSE_EVERY;
        return .{ .hit = GAS_HIT, .from = at, .on = .hero };
    }
    pub fn fuming(self: *const Vigil, hero: rl.Vector3) bool {
        for (&self.gas) |*g| {
            if (g.covers(hero)) return true;
        }
        return false;
    }
    pub fn setShader(self: *Vigil, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Vigil, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Vigil) bool {
        return foe.anyParried(self.liveConst());
    }
    /// The worst of this frame's quakes — a one-frame magnitude, like `justDied`.
    pub fn quakeAmt(self: *const Vigil) f32 {
        var q: f32 = 0;
        for (self.liveConst()) |*k| q = mathx.maxF(q, k.quake);
        return q;
    }
    pub fn boss(self: *const Vigil, hero: rl.Vector3) ?usize {
        for (self.liveConst(), 0..) |*k, i| {
            if (!k.alive()) continue;
            if (k.leash.roused() or mathx.distXZ(k.pos, hero) <= AGGRO_R) return i;
        }
        return null;
    }
    pub fn update(self: *Vigil, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        const blow = foe.groupBlow(self.live(), dt, hero, bounds, blade);
        for (self.live()) |*k| {
            if (k.gasAt) |at| self.spawnGas(at, k.scale * k.gasScale);
        }
        for (&self.gas) |*g| g.update(dt);
        return blow;
    }
    pub fn draw(self: *const Vigil, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Vigil) void {
        for (self.liveConst()) |*k| k.drawFx();
        for (&self.gas) |*g| g.drawFx();
    }
    pub fn pierce(self: *Vigil, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Vigil) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Vigil) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Vigil) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Vigil) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = cuirassMesh();
    mesh[NECK] = gorgetMesh();
    mesh[SKULL] = helmMesh();
    mesh[HIPL] = thighMesh(1.0, 311);
    mesh[KNEEL] = shinMesh(312);
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh(-1.0, 314);
    mesh[KNEER] = shinMesh(315);
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh(1.0, 0.98);
    mesh[ELL] = forearmMesh(1.0, 0.98);
    mesh[WRL] = gauntletMesh(true);
    mesh[SHR] = upperArmMesh(-1.0, 1.06);
    mesh[ELR] = forearmMesh(-1.0, 1.06);
    mesh[WRR] = gauntletMesh(false);
    mesh[WPN] = swordMesh();
    return mesh;
}

fn shade(c: rl.Color, d: f32) rl.Color {
    return rgba(
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.r)) + d, 0, 255)),
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.g)) + d, 0, 255)),
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.b)) + d, 0, 255)),
        c.a,
    );
}



fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4201);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, 0.036 * H, 0), v3(0.216 * H, 0.150 * H, 0.180 * H), 0.048 * H, 3, 11, IRON_DK);
    b.addCylinder(v3(0, -0.006 * H, 0), v3(0, -0.075 * H, 0), 0.128 * H, 0.140 * H, 12, IRON_DK);
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        const a = (@as(f32, @floatFromInt(i)) + 0.5) / 7.0 * std.math.tau;
        const rr = 0.136 * H;
        const torn = i == 4;
        const len = if (torn) 0.038 * H else rng.range(0.062, 0.148) * H;
        const outw = v3(mathx.cosf(a), 0, mathx.sinf(a));
        const tang = v3(-mathx.sinf(a), 0, mathx.cosf(a));
        const cant = rng.range(-0.020, 0.026) * H;
        b.addBox(
            v3(outw.x * rr, -0.078 * H - len * 0.5, outw.z * rr),
            mathx.scaleV(tang, rng.range(0.046, 0.064) * H),
            v3(outw.x * (0.014 * H + cant), len * 0.5, outw.z * (0.014 * H + cant)),
            mathx.scaleV(outw, 0.009 * H),
            switch (i % 3) {
                0 => IRON,
                1 => IRON_MD,
                else => IRON_DK,
            },
        );
    }
    b.addBlob(v3(mathx.cosf(4.5 / 7.0 * std.math.tau) * 0.118 * H, -0.128 * H, mathx.sinf(4.5 / 7.0 * std.math.tau) * 0.118 * H), v3(0.030 * H, 0.052 * H, 0.028 * H), 6, 10, KBONE);
    b.setMat(.leather);
    // A BELT GOES ROUND HIM, SO ITS AXIS IS VERTICAL — across his hips it was a 1.5 m drum whose two flat sunlit caps filled his whole back.
    b.addCylinder(v3(0, 0.034 * H, 0), v3(0, 0.078 * H, 0), 0.140 * H, 0.140 * H, 11, STRAP);
    b.setMat(BRIGHT);
    b.addBox(v3(0, 0.056 * H, 0.138 * H), v3(0.036 * H, 0, 0), v3(0, 0.030 * H, 0), v3(0, 0, 0.010 * H), BRASS);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4229);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, 0.056 * H, -0.008 * H), v3(0.190 * H, 0.150 * H, 0.164 * H), 0.055 * H, 3, 11, IRON_DK);
    for ([_]f32{ -0.070, -0.024, 0.024, 0.070 }) |sx| {
        b.addBox(
            v3(sx * H, 0.048 * H, 0.062 * H * rng.range(0.9, 1.05)),
            v3(0.024 * H, 0, 0),
            v3(rng.range(-0.006, 0.006) * H, 0.058 * H, 0),
            v3(0, 0, 0.007 * H),
            if (rng.float() < 0.3) RUST else IRON_DK,
        );
    }
    return b.toMesh();
}

/// NAMED because the DOOR is measured against its front face; a hand-derived `0.208/2 − 0.006` at the test site stops describing his chest the first time the breastplate is re-authored. `addRoundBox` takes a FULL size, hence the halving.
const CUIRASS_C = v3(0, 0.016 * H, -0.006 * H);
const CUIRASS_SIZE = v3(0.318 * H, 0.176 * H, 0.208 * H);
pub const CHEST_FRONT_Z = CUIRASS_C.z + CUIRASS_SIZE.z * 0.5;

fn cuirassMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4243);
    b.setMat(PLATE);
    b.addRoundBox(CUIRASS_C, CUIRASS_SIZE, 0.072 * H, 4, 12, IRON);
    b.addRoundBox(v3(0, -0.050 * H, 0.004 * H), v3(0.258 * H, 0.084 * H, 0.184 * H), 0.056 * H, 3, 11, IRON_MD);
    b.addRoundBox(v3(0, -0.092 * H, 0.006 * H), v3(0.206 * H, 0.060 * H, 0.158 * H), 0.048 * H, 3, 11, IRON_DK);
    for ([_]usize{ 0, 1, 2, 3 }) |ri| {
        const fy = 0.086 * H - @as(f32, @floatFromInt(ri)) * 0.036 * H;
        const spanX = (0.104 + 0.016 * @as(f32, @floatFromInt(ri))) * H;
        for ([_]f32{ -1, 1 }) |sx| {
            const drop = rng.range(0.010, 0.026) * H;
            b.addCapsule(
                v3(sx * 0.014 * H, fy + rng.range(-0.004, 0.004) * H, 0.100 * H),
                v3(sx * spanX, fy - drop, 0.074 * H),
                rng.range(0.013, 0.018) * H,
                rng.range(0.009, 0.013) * H,
                8,
                IRON_MD,
            );
            b.addCapsule(
                v3(sx * 0.014 * H, fy - drop * 0.9, 0.096 * H),
                v3(sx * spanX * 0.96, fy - drop * 1.8, 0.070 * H),
                0.010 * H,
                0.007 * H,
                7,
                IRON_DK,
            );
        }
    }
    b.addBox(v3(0, 0.020 * H, 0.106 * H), v3(0.020 * H, 0, 0), v3(0, 0.150 * H, 0), v3(0, 0, 0.016 * H), IRON_LT);
    for ([_]f32{ 1, -1 }) |side| {
        const sword = side < 0;
        const big: f32 = if (sword) 1.26 else 0.92;
        const reach: f32 = if (sword) 1.02 else 0.94;
        const tilt: f32 = if (sword) 0.38 else 0.16;
        const sx = side * SHOULDER_HALF * H * reach;
        const sy: f32 = if (sword) 0.034 * H else 0.062 * H;
        b.addBlob(v3(sx, sy, -0.006 * H), v3(0.116 * H * big, 0.086 * H * big, 0.148 * H * big), 7, 12, IRON);
        b.addDome(v3(sx, sy + 0.044 * H, -0.006 * H), v3(side * tilt, 1.0, 0), 0.092 * H * big, 12, IRON_MD);
        b.addBlob(v3(sx, sy - 0.052 * H, -0.006 * H), v3(0.104 * H * big, 0.040 * H * big, 0.132 * H * big), 6, 11, IRON_DK);
        if (sword) {
            b.addBox(
                v3(sx * 1.06, sy - 0.072 * H, -0.004 * H),
                v3(0.062 * H, 0, 0),
                v3(0.010 * H, 0.046 * H, 0),
                v3(0, 0, 0.078 * H),
                IRON_MD,
            );
        }
    }
    b.setMat(BRIGHT);
    b.addCylinder(v3(0, 0.176 * H, -0.006 * H), v3(0, 0.190 * H, -0.006 * H), 0.106 * H, 0.094 * H, 11, IRON_LT);
    for ([_]f32{ 1, -1 }) |side| {
        const big: f32 = if (side < 0) 1.10 else 1.0;
        const sx = side * SHOULDER_HALF * H;
        b.addCapsule(
            v3(sx * 0.60, 0.108 * H, 0.030 * H),
            v3(sx * 1.30, 0.078 * H, 0.010 * H),
            0.020 * H * big,
            0.016 * H * big,
            8,
            IRON_LT,
        );
    }
    b.setMat(PLATE);
    for ([_]f32{ 1, -1 }) |side| {
        const sx = side * SHOULDER_HALF * H;
        b.addBlob(v3(sx * 1.02, -0.010 * H, 0.048 * H), v3(0.022 * H, 0.022 * H, 0.018 * H), 5, 9, if (side < 0) RUST else BRASS);
    }
    b.setMat(BRIGHT);
    var r: i32 = 0;
    while (r < 10) : (r += 1) {
        const a = rng.angle();
        const yy = rng.range(-0.10, 0.14) * H;
        const rr = 0.300 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, yy, mathx.sinf(a) * rr * 0.68 - 0.006 * H),
            v3(0.011 * H, 0.011 * H, 0.011 * H),
            4,
            8,
            if (rng.float() < 0.35) RUST else IRON_LT,
        );
    }
    b.setMat(PLATE);
    for ([_]struct { x: f32, y: f32, s: f32 }{
        .{ .x = -0.086, .y = 0.062, .s = 1.20 },
        .{ .x = 0.104, .y = -0.014, .s = 0.85 },
        .{ .x = -0.032, .y = -0.070, .s = 1.05 },
        .{ .x = 0.062, .y = 0.096, .s = 0.70 },
    }) |d| {
        const w = 0.030 * H * d.s;
        b.addBlob(v3(d.x * H, d.y * H, 0.098 * H), v3(w, w * rng.range(0.6, 1.1), 0.012 * H), 6, 10, IRON_DK);
        b.setMat(BRIGHT);
        b.addCapsule(
            v3(d.x * H - w, d.y * H + w * 0.5, 0.104 * H),
            v3(d.x * H + w * rng.range(0.7, 1.2), d.y * H + w * rng.range(-0.4, 0.8), 0.104 * H),
            0.005 * H,
            0.004 * H,
            6,
            IRON_LT,
        );
        b.setMat(PLATE);
    }
    b.addBlob(v3(-0.118 * H, 0.028 * H, 0.088 * H), v3(0.026 * H, 0.044 * H, 0.026 * H), 6, 10, SOCKET);
    b.addBlob(v3(-0.118 * H, 0.030 * H, 0.082 * H), v3(0.015 * H, 0.030 * H, 0.014 * H), 5, 9, KBONE);
    return b.toMesh();
}

fn gorgetMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCylinder(v3(0, -0.006 * H, 0), v3(0, 0.052 * H, 0), 0.040 * H, 0.036 * H, 8, BONE_DK);
    b.addCylinder(v3(0, 0.002 * H, -0.002 * H), v3(0, 0.048 * H, -0.002 * H), 0.070 * H, 0.062 * H, 11, IRON);
    b.setMat(BRIGHT);
    b.addCylinder(v3(0, 0.048 * H, -0.002 * H), v3(0, 0.058 * H, -0.002 * H), 0.066 * H, 0.058 * H, 11, IRON_LT);
    return b.toMesh();
}

fn helmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4271);
    b.setMat(PLATE);
    b.addBlob(v3(0, 0.018 * H, 0.002 * H), v3(0.048 * H, 0.066 * H, 0.053 * H), 8, 14, IRON);
    b.addDome(v3(0, 0.058 * H, 0.000 * H), v3(0, 1, 0), 0.047 * H, 12, IRON_DK);
    for ([_]f32{ -1, 1 }) |sx| {
        const ox = sx * 0.021 * H;
        const oy = 0.026 * H + sx * 0.002 * H;
        b.addBlob(v3(ox, oy, 0.041 * H), v3(0.016 * H, 0.015 * H, 0.014 * H), 6, 10, SOCKET);
        b.addBlob(v3(ox, oy, 0.045 * H), v3(0.010 * H, 0.009 * H, 0.006 * H), 5, 9, EMBER);
    }
    b.addCapsule(v3(0, 0.046 * H, 0.045 * H), v3(0, 0.008 * H, 0.048 * H), 0.008 * H, 0.006 * H, 7, IRON_MD);
    b.addBlob(v3(0, 0.004 * H, 0.043 * H), v3(0.009 * H, 0.011 * H, 0.008 * H), 5, 9, SOCKET);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCapsule(
            v3(sx * 0.012 * H, 0.012 * H, 0.046 * H),
            v3(sx * 0.044 * H, 0.022 * H, 0.026 * H),
            0.010 * H,
            0.007 * H,
            7,
            IRON_MD,
        );
    }
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const y = -0.016 * H - @as(f32, @floatFromInt(i)) * 0.011 * H;
        const w = rng.range(0.014, 0.026) * H;
        b.addBox(v3(rng.range(-0.008, 0.008) * H, y, 0.044 * H), v3(w, 0, 0), v3(0, 0.003 * H, 0), v3(0, 0, 0.006 * H), SOCKET);
    }
    b.addCapsule(v3(0, 0.074 * H, 0.028 * H), v3(0, 0.086 * H, -0.036 * H), 0.014 * H, 0.019 * H, 9, IRON_DK);
    b.setMat(BRIGHT);
    b.addCapsule(v3(-0.046 * H, 0.040 * H, 0.036 * H), v3(0.046 * H, 0.040 * H, 0.036 * H), 0.011 * H, 0.009 * H, 8, IRON_LT);
    b.setMat(PLATE);
    b.addBox(v3(0, -0.046 * H, 0.036 * H), v3(0.036 * H, 0, 0), v3(0, 0.014 * H, 0), v3(0, 0, 0.030 * H), KBONE);
    b.addBlob(v3(-0.032 * H, -0.044 * H, 0.020 * H), v3(0.011 * H, 0.014 * H, 0.012 * H), 5, 9, KBONE_LT);
    b.addBlob(v3(0.031 * H, -0.047 * H, 0.018 * H), v3(0.010 * H, 0.013 * H, 0.011 * H), 5, 9, KBONE_DK);
    for ([_]i32{ 0, 1, 2, 3, 4 }) |ti| {
        const tx = (-0.026 + 0.013 * @as(f32, @floatFromInt(ti))) * H;
        b.addBox(
            v3(tx + rng.range(-0.002, 0.002) * H, -0.038 * H, 0.049 * H),
            v3(0.0045 * H, 0, 0),
            v3(0, rng.range(0.006, 0.011) * H, 0),
            v3(0, 0, 0.004 * H),
            if (rng.float() < 0.25) SOCKET else KBONE_LT,
        );
    }
    return b.toMesh();
}

fn thighMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const len = REST[HIPL].y - REST[KNEEL].y;
    b.setMat(PLATE);
    b.addRoundBox(v3(side * 0.004 * H, -len * 0.24, 0.006 * H), v3(0.148 * H, len * 0.66, 0.136 * H), 0.050 * H, 3, 11, IRON);
    b.addRoundBox(v3(0, -len * 0.66, 0.008 * H), v3(0.128 * H, len * 0.54, 0.118 * H), 0.044 * H, 3, 11, shade(IRON, rng.range(-4.0, 4.0)));
    b.addBlob(v3(side * 0.006 * H, -len * 0.98, 0.020 * H), v3(0.064 * H, 0.060 * H, 0.062 * H), 6, 11, IRON_DK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -len * 0.44, 0), v3(0, -len * 0.44 - 0.012 * H, 0), 0.078 * H, 0.078 * H, 9, STRAP);
    return b.toMesh();
}

fn shinMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const len = REST[KNEEL].y - REST[ANKL].y;
    b.setMat(PLATE);
    b.addRoundBox(v3(0, -len * 0.42, 0.006 * H), v3(0.122 * H, len * 0.74, 0.112 * H), 0.044 * H, 3, 11, shade(IRON, rng.range(-3.0, 3.0)));
    b.addCylinder(v3(0, -len * 0.82, 0.004 * H), v3(0, -len * 1.02, 0.004 * H), 0.056 * H, 0.066 * H, 11, IRON_DK);
    b.setMat(BRIGHT);
    b.addCapsule(v3(0, -len * 0.14, 0.058 * H), v3(0, -len * 0.72, 0.052 * H), 0.011 * H, 0.009 * H, 8, IRON_LT);
    return b.toMesh();
}

/// The footprint `solePatches` is measured off; its underside sits on the ankle plane.
fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4283);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, -0.016 * H, 0.052 * H), v3(0.126 * H, 0.050 * H, 0.238 * H), 0.024 * H, 3, 10, IRON);
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const z = 0.088 * H + @as(f32, @floatFromInt(i)) * 0.034 * H * rng.range(0.9, 1.12);
        b.addBox(v3(0, -0.002 * H, z), v3(0.058 * H - @as(f32, @floatFromInt(i)) * 0.005 * H, 0, 0), v3(0, 0.016 * H, 0), v3(0, 0, 0.010 * H), if (i % 2 == 0) IRON_LT else IRON_DK);
    }
    b.addBlob(v3(side * 0.044 * H, -0.002 * H, -0.034 * H), v3(0.040 * H, 0.038 * H, 0.038 * H), 5, 10, IRON_DK);
    b.setMat(BRIGHT);
    b.addCapsule(v3(0, -0.012 * H, 0.176 * H), v3(0, -0.002 * H, 0.208 * H), 0.030 * H, 0.023 * H, 8, RUST);
    return b.toMesh();
}

fn upperArmMesh(side: f32, big: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 4297 else 4327);
    const len = REST[SHL].y - REST[ELL].y;
    b.setMat(PLATE);
    b.addRoundBox(v3(0, -len * 0.44, 0.004 * H), v3(0.098 * H * big, len * 0.92, 0.090 * H * big), 0.036 * H, 3, 11, shade(IRON, rng.range(-3.0, 3.0)));
    b.addBlob(v3(0, -len * 0.98, 0.008 * H), v3(0.052 * H * big, 0.048 * H, 0.050 * H * big), 6, 11, IRON_DK);
    return b.toMesh();
}

fn forearmMesh(side: f32, big: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 4337 else 4349);
    const len = REST[ELL].y - REST[WRL].y;
    b.setMat(PLATE);
    b.addRoundBox(v3(0, -len * 0.46, 0.004 * H), v3(0.086 * H * big, len * 0.94, 0.078 * H * big), 0.032 * H, 3, 11, shade(IRON, rng.range(-3.0, 3.0)));
    b.setMat(.leather);
    b.addCylinder(v3(0, -len * 0.26, 0), v3(0, -len * 0.26 - 0.009 * H, 0), 0.052 * H * big, 0.052 * H * big, 9, STRAP);
    return b.toMesh();
}

fn gauntletMesh(off: bool) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (off) 4357 else 4363);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, FIST_Y * 0.5, FIST_Z), v3(0.062 * H, 0.070 * H, 0.058 * H), 0.020 * H, 3, 10, IRON);
    b.setMat(BRIGHT);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const x = (-0.030 + @as(f32, @floatFromInt(i)) * 0.020) * H;
        const r = rng.range(0.011, 0.016) * H;
        b.addBlob(v3(x, FIST_Y - 0.010 * H, FIST_Z + 0.036 * H), v3(r, r, r * 1.2), 5, 9, if (i % 2 == 0) IRON_LT else IRON_DK);
    }
    b.addCylinder(v3(0, FIST_Y * 0.5 + 0.070 * H, FIST_Z), v3(0, FIST_Y * 0.5 + 0.082 * H, FIST_Z), 0.058 * H, 0.050 * H, 10, IRON_LT);
    if (off) {
        b.setMat(.leather);
        b.addCylinder(v3(-0.056 * H, FIST_Y * 0.5, FIST_Z), v3(0.056 * H, FIST_Y * 0.5, FIST_Z), 0.020 * H, 0.020 * H, 7, STRAP);
    }
    return b.toMesh();
}

fn swordMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4373);
    const fy = FIST_Y;
    const fz = FIST_Z;
    const guardY = fy + SW_GUARD;
    const tipY = guardY + SW_BLADE;

    b.setMat(.leather);
    b.addCylinder(v3(0, fy + 0.090 * H, fz), v3(0, fy - 0.086 * H, fz), 0.019 * H, 0.019 * H, 8, STRAP);
    b.setMat(PLATE);
    b.addBlob(v3(0, fy - 0.100 * H, fz), v3(0.030 * H, 0.024 * H, 0.030 * H), 6, 10, IRON_LT);
    for ([_]f32{ 1, -1 }) |side| {
        const armLen = 0.104 * H * (if (side > 0) @as(f32, 1.0) else 0.88);
        b.addBox(
            v3(side * armLen * 0.5, guardY, fz),
            v3(side * armLen, 0, 0),
            v3(0, 0.014 * H, 0),
            v3(0, 0, 0.016 * H),
            IRON,
        );
        b.addCapsule(
            v3(side * armLen, guardY, fz),
            v3(side * (armLen + 0.014 * H), guardY - 0.006 * H, fz),
            0.013 * H,
            0.009 * H,
            7,
            IRON_LT,
        );
    }
    b.addCylinder(v3(0, guardY, fz), v3(0, guardY + 0.034 * H, fz), 0.020 * H, 0.016 * H, 8, IRON_DK);
    const seg = [_]f32{ 0.04, 0.40, 0.76, 0.96 };
    const halfW = [_]f32{ SW_HALF_W / H, SW_HALF_W / H * 0.90, SW_HALF_W / H * 0.72, SW_HALF_W / H * 0.42 };
    const halfT = [_]f32{ 0.0080, 0.0070, 0.0056, 0.0038 };
    for (0..3) |s| {
        const y0 = guardY + seg[s] * SW_BLADE;
        const y1 = guardY + seg[s + 1] * SW_BLADE;
        b.addBox(
            v3(0, (y0 + y1) * 0.5, fz),
            v3((halfW[s] + halfW[s + 1]) * 0.5 * H, 0, 0),
            v3(0, (y1 - y0) * 0.5, 0),
            v3(0, 0, halfT[s] * H),
            if (s == 1) IRON_DK else IRON,
        );
    }
    b.addBox(v3(0, guardY + 0.42 * SW_BLADE, fz), v3(0.015 * H, 0, 0), v3(0, 0.32 * SW_BLADE, 0), v3(0, 0, 0.009 * H), IRON_DK);
    b.setMat(BRIGHT);
    b.addCapsule(v3(0, guardY + seg[3] * SW_BLADE, fz), v3(0, tipY, fz), 0.017 * H, 0.005 * H, 7, IRON_LT);
    for ([_]f32{ 1, -1 }) |side| {
        b.addCapsule(
            v3(side * SW_HALF_W * 0.96, guardY + 0.06 * SW_BLADE, fz),
            v3(side * SW_HALF_W * 0.42, guardY + 0.92 * SW_BLADE, fz),
            0.005 * H,
            0.004 * H,
            5,
            IRON_LT,
        );
    }
    b.setMat(PLATE);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const y = guardY + rng.range(0.12, 0.86) * SW_BLADE;
        const side: f32 = if (rng.float() < 0.5) 1 else -1;
        b.addBox(
            v3(side * 0.044 * H, y, fz),
            v3(side * rng.range(0.010, 0.020) * H, 0, 0),
            v3(0, rng.range(0.006, 0.014) * H, 0),
            v3(0, 0, 0.010 * H),
            RUST,
        );
    }
    return b.toMesh();
}


const SH_TOP = 0.150 * H; // → the top edge at ~4.7 m: his chin
const SH_BOT = 0.700 * H; // → the foot at ~0.2 m: his ankles
const SH_CURVE_R = 0.46 * H;
/// `TOWER_ARC` is derived off these, so the only way to buy coverage is to build door. At 34/30 the honest
/// occlusion was ~35 deg either side against a mechanic claiming 105.
const SH_ARC_L = mathx.radians(38.0);
const SH_ARC_R = mathx.radians(34.0);
pub const SH_CHORD_L = SH_CURVE_R * @sin(mathx.radians(38.0));
pub const SH_CHORD_R = SH_CURVE_R * @sin(mathx.radians(34.0));
pub const SH_SAG_L = SH_CURVE_R * (1.0 - @cos(mathx.radians(34.0)));
comptime {
    std.debug.assert(SH_CHORD_R > SHOULDER_HALF * H * 1.02);
    std.debug.assert(SH_CHORD_L > SHOULDER_HALF * H * 1.08);
    std.debug.assert(SH_SAG_L > 0.05 * H);
    std.debug.assert((SH_TOP + SH_BOT) > (SH_CHORD_L + SH_CHORD_R) * 1.55);
}
/// THE RAM: the near-flat middle of the arc — the bash's and the charge's hurt half-width, because iron a
/// metre back round the curve cannot be what hit you. `asin(SH_RAM_HALF / BASH.reachOut)` is what the
/// accuracy test measures the swing against.
pub const SH_RAM_HALF = SH_CURVE_R * @sin(mathx.radians(24.0));
const SH_THICK = 0.030 * H;
const SH_STAVES = 9;
const SH_CENTRE_Y = (SH_TOP - SH_BOT) * 0.5;
/// **UNDER 1, ON PURPOSE**: at 1.06 the staves overlapped into one sheet and the door sampled as a flat tone.
const SH_STAVE_FILL = 0.90;
const SH_STAVE_PROUD = 0.012 * H;
/// It faces the sun square where his chest is angled away, so the same albedo comes off it half again as
/// bright (measured: 112 against the cuirass's 84). Solved to land near 62 on screen: below the ground, cold.
const SH_FIELD = rgba(8, 9, 13, 255);
const SH_BAND = rgba(23, 26, 32, 255);
/// How far off his FIST the door rides, along his own front. CENTRE-GRIPPED behind a boss, not strapped to
/// the forearm, so it needs a hand's depth and no more: 0.108·H stood 0.57 m off the hand, 0.062·H 0.33 m.
const SH_STANDOFF = 0.028 * H;

/// The two points on its leading FACE that the ram's swept hurt test runs between (`shieldSeg`). **THEY SPAN
/// THE WHOLE DOOR, because the whole door is what arrives.** A test pins the height as well as the reach.
const SH_LOW = v3(0, -SH_BOT, SH_THICK);
const SH_HIGH = v3(0, SH_TOP, SH_THICK);

/// A point on the arc's midline: `a` radians round the curve (+ = the wrap side), `y` up the stave, `out`
/// metres proud of the face along that stave's own normal. The ONE piece of arc arithmetic.
fn arcAt(a: f32, y: f32, out: f32) rl.Vector3 {
    return v3(
        @sin(a) * (SH_CURVE_R + out),
        y,
        @cos(a) * (SH_CURVE_R + out) - SH_CURVE_R,
    );
}

fn shieldMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4391);
    b.setMat(PLATE);
    {
        const am = (SH_ARC_L - SH_ARC_R) * 0.5;
        const halfW = SH_CURVE_R * (SH_ARC_L + SH_ARC_R) * 0.5 * 1.02;
        const n = v3(@sin(am), 0, @cos(am));
        const mid = (SH_TOP - SH_BOT) * 0.5;
        b.addBox(
            arcAt(am, mid, -SH_THICK * 0.55),
            v3(n.z * halfW, 0, -n.x * halfW),
            v3(0, (SH_TOP + SH_BOT) * 0.5 * 0.97, 0),
            v3(n.x * SH_THICK * 0.30, 0, n.z * SH_THICK * 0.30),
            IRON_DK,
        );
    }
    var i: usize = 0;
    while (i < SH_STAVES) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SH_STAVES;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SH_STAVES;
        const a0 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, t0);
        const a1 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, t1);
        const am = (a0 + a1) * 0.5;
        const halfW = SH_CURVE_R * (a1 - a0) * 0.5 * SH_STAVE_FILL * rng.range(0.80, 1.16);
        const foot = -SH_BOT + rng.range(0.0, 0.075) * H;
        const crownDrop = @abs(am) / SH_ARC_L;
        const top = SH_TOP - 0.050 * H * crownDrop * crownDrop;
        const mid = (top + foot) * 0.5;
        const halfH = (top - foot) * 0.5;
        const n = v3(@sin(am), 0, @cos(am));
        const proud = (if (i % 2 == 0) SH_STAVE_PROUD else 0.0) + rng.range(-0.003, 0.004) * H;
        b.addBox(
            arcAt(am, mid, proud),
            v3(n.z * halfW, 0, -n.x * halfW),
            v3(0, halfH, 0),
            v3(n.x * SH_THICK * 0.5, 0, n.z * SH_THICK * 0.5),
            shade(SH_FIELD, rng.range(-6.0, 6.0)),
        );
        if (i == 6) {
            b.addBox(
                arcAt(am + (a1 - a0) * 0.34, foot + (top - foot) * 0.30, proud + 0.006 * H),
                v3(n.z * halfW * 0.42, 0, -n.x * halfW * 0.42),
                v3(0, (top - foot) * 0.11, 0),
                v3(n.x * SH_THICK * 0.34, 0, n.z * SH_THICK * 0.34),
                SOCKET,
            );
        }
    }
    for ([_]f32{ 0.02, -0.34, -0.62 }) |ty| {
        var s: usize = 0;
        while (s < SH_STAVES) : (s += 1) {
            const am = mathx.lerpF(-SH_ARC_R, SH_ARC_L, (@as(f32, @floatFromInt(s)) + 0.5) / SH_STAVES);
            const halfW = SH_CURVE_R * (SH_ARC_L + SH_ARC_R) / SH_STAVES * 0.5 * 1.14;
            const n = v3(@sin(am), 0, @cos(am));
            b.addBox(
                arcAt(am, ty * H + rng.range(-0.004, 0.004) * H, SH_STAVE_PROUD + 0.014 * H),
                v3(n.z * halfW, 0, -n.x * halfW),
                v3(0, rng.range(0.026, 0.034) * H, 0),
                v3(n.x * 0.014 * H, 0, n.z * 0.014 * H),
                SH_BAND,
            );
        }
    }
    const topAt = struct {
        fn of(a: f32) f32 {
            const drop = @abs(a) / SH_ARC_L;
            return SH_TOP - 0.050 * H * drop * drop;
        }
    }.of;
    var s: usize = 0;
    while (s < SH_STAVES) : (s += 1) {
        const a0 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(s)) / SH_STAVES);
        const a1 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(s + 1)) / SH_STAVES);
        b.addCapsule(arcAt(a0, topAt(a0) - 0.006 * H, 0.004 * H), arcAt(a1, topAt(a1) - 0.006 * H, 0.004 * H), 0.016 * H, 0.014 * H, 7, IRON_LT);
        if (s < SH_STAVES - 2) {
            b.addCapsule(arcAt(a0, -SH_BOT + 0.008 * H, 0.004 * H), arcAt(a1, -SH_BOT + 0.008 * H, 0.004 * H), 0.013 * H, 0.011 * H, 7, RUST);
        }
    }
    b.addCapsule(arcAt(-SH_ARC_R, topAt(-SH_ARC_R) - 0.010 * H, 0.004 * H), arcAt(-SH_ARC_R, -SH_BOT + 0.050 * H, 0.004 * H), 0.015 * H, 0.012 * H, 8, IRON_LT);
    b.addCapsule(arcAt(SH_ARC_L, topAt(SH_ARC_L) - 0.010 * H, 0.004 * H), arcAt(SH_ARC_L, -SH_BOT + 0.024 * H, 0.004 * H), 0.015 * H, 0.012 * H, 8, if (rng.float() < 0.5) RUST else IRON_LT);
    const cross = arcAt(0.02, -0.075 * H, SH_STAVE_PROUD + 0.016 * H);
    {
        var cs: usize = 0;
        while (cs < SH_STAVES) : (cs += 1) {
            const a0 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(cs)) / SH_STAVES);
            const a1 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(cs + 1)) / SH_STAVES);
            b.addCapsule(
                arcAt(a0, cross.y, SH_STAVE_PROUD + 0.016 * H),
                arcAt(a1, cross.y, SH_STAVE_PROUD + 0.016 * H),
                0.024 * H,
                0.021 * H,
                8,
                IRON_LT,
            );
        }
    }
    b.addCapsule(
        arcAt(0.02, SH_TOP - 0.090 * H, SH_STAVE_PROUD + 0.016 * H),
        arcAt(0.02, -SH_BOT + 0.120 * H, SH_STAVE_PROUD + 0.016 * H),
        0.026 * H,
        0.022 * H,
        8,
        IRON_LT,
    );
    b.setMat(BRIGHT);
    b.addBlob(cross, v3(0.046 * H, 0.046 * H, 0.026 * H), 6, 11, IRON_MD);
    var r: i32 = 0;
    while (r < 12) : (r += 1) {
        const a = rng.range(-0.9, 0.9);
        b.addBlob(
            arcAt(mathx.lerpF(-SH_ARC_R, SH_ARC_L, a * 0.5 + 0.5), rng.range(-SH_BOT * 0.85, SH_TOP * 0.9), SH_STAVE_PROUD + 0.014 * H),
            v3(0.012 * H, 0.012 * H, 0.009 * H),
            4,
            8,
            if (rng.float() < 0.4) RUST else IRON_LT,
        );
    }
    b.setMat(.leather);
    b.addCylinder(v3(-0.060 * H, 0.020 * H, -0.014 * H), v3(0.060 * H, 0.020 * H, -0.014 * H), 0.014 * H, 0.014 * H, 7, STRAP);
    return b.toMesh();
}

/// How far the FACE may tip off his own horizontal — the SINE of the tip, so 0.50 is 30°. The one move allowed
/// past it is the SLAM, which lays the plank face-DOWN on purpose (`doorNormal` y −0.95).
const HANG_TIP: f32 = 0.50;

/// **A SHIELD IS CARRIED, NOT WELDED TO THE FOREARM** (owner: it goes up in the air like a retard, or the sword
/// goes through it). Strapped rigidly, every roll of the forearm rolled four and a half metres of oak: measured
/// across his whole kit the plank INVERTED — its own up axis at −0.82 — and its foot climbed to 6.87 m over a
/// 5.11 m crown; a stagger flung it horizontal at 5.49 m and the rollover stood it on end. So the arm AIMS it in
/// YAW and nothing else: the face may tip `HANG_TIP` off his horizontal and no further, and the plank's length is
/// then whatever is left of his up. Standing that is world up; toppled it is his, so the door goes down with him.
/// **The SLAM is the one exemption and it is a FRACTION, not a flag** (`slamDrive`): laid flat, the plank has no
/// upright left to solve for, so its length is taken off his FORWARD instead and the far end lies out in front
/// of him. Exempting the whole move instead let the HAUL through, and the haul is where a −56° pitch put the
/// plank's foot 7.41 m up.
fn hangUpright(k: *Knight, dt: f32, m: rl.Matrix, bodyUp: rl.Vector3, bodyFwd: rl.Vector3, laid: f32) rl.Matrix {
    const s = mathx.lenV(v3(m.m4, m.m5, m.m6));
    if (s < 1e-5) return m;
    var n = mathx.normV(v3(m.m8, m.m9, m.m10));
    const allow = lerpF(HANG_TIP, 1.0, laid);
    // **THE FACE IS CHASED, NOT ASSIGNED.** Easing the channels under it was not enough — the arm's own roll has
    // singularities, and a counter yanking him out of a slam re-aims the whole basis in a frame: 113 deg of face
    // turn in ONE FRAME, standing in idle.
    // **AND THE TIP IS CLAMPED AFTER THE CHASE, NOT BEFORE.** A slerp runs the great circle between its ends, and
    // between two legal near-horizontal faces on opposite bearings that circle goes over the POLE: clamped only
    // on the way in, the chase itself tipped the plank to 0.62 of upright.
    n = clampTip(turnToward(&k.doorFace, clampTip(n, bodyUp, bodyFwd, allow), dt), bodyUp, bodyFwd, allow);
    // Its foot is the far end (`SH_LOW` at −`SH_BOT`), so laying it out in FRONT is his forward NEGATED.
    const ref = mathx.normV(mathx.lerpV(bodyUp, mathx.scaleV(bodyFwd, -1), laid));
    const y = mathx.normV(mathx.subV(ref, mathx.scaleV(n, n.x * ref.x + n.y * ref.y + n.z * ref.z)));
    const x = mathx.crossV(y, n);
    var out = m;
    out.m0 = x.x * s;
    out.m1 = x.y * s;
    out.m2 = x.z * s;
    out.m4 = y.x * s;
    out.m5 = y.y * s;
    out.m6 = y.z * s;
    out.m8 = n.x * s;
    out.m9 = n.y * s;
    out.m10 = n.z * s;
    return out;
}

/// **THE DOOR IS STRAPPED TO THE FOREARM** (owner: it floated off his arm and hung at bizarre angles). Position AND
/// orientation come off the wrist bone through one fix solved at spawn (`calibrateShield`) so the GUARD looks
/// exactly as it was authored — square across his front, pulled onto his centre line — and from then on the arm
/// carries the plank rigidly wherever it goes. Oriented off the BODY instead, the fist only supplied a position:
/// the plank stayed square to his front while the arm swung out, and left the arm behind.
fn shieldXf(k: *Knight, dt: f32) rl.Matrix {
    const fs = k.rigScale();
    const carry = k.slamCarry();
    const push = k.shoveAcross();
    const g = k.shieldGrip;
    var m = hangUpright(
        k,
        dt,
        mul3(
            mul3(tr(0, -SH_CENTRE_Y, 0), rx(k.slamPitch()), tr(0, SH_CENTRE_Y, 0)),
            mul(k.shieldFix, tr(g.x, g.y, g.z)),
            k.xf[WRL],
        ),
        mathx.normV(v3(k.bodyXf.m4, k.bodyXf.m5, k.bodyXf.m6)),
        mathx.normV(v3(k.bodyXf.m8, k.bodyXf.m9, k.bodyXf.m10)),
        k.slamDrive() * k.slamLift(),
    );
    // What the arm cannot carry the MOVE does (`slamCarry`, `SHOVE_CARRY_*`): a lift in HIS frame on top of the grip.
    const extra = rl.math.vector3Transform(
        mathx.scaleV(v3(SHOVE_CARRY_X * push * k.shoveDir(), carry.y, carry.z + SHOVE_CARRY_Z * push), fs),
        k.bodyXf,
    );
    m.m12 += extra.x;
    m.m13 += extra.y;
    m.m14 += extra.z;
    // **AND THE STRAP IS A LENGTH, NOT A SUGGESTION.** A move's own carry may swing the hub round the fist; it
    // may not take it further off than the grip. The slam's had it 4.15 m out against a 0.98 m grip — the door
    // left his hand, flew to 10.14 m and came back down, which is the same failure the strap was built to end.
    const fist = rl.math.vector3Transform(mathx.zero3, k.xf[WRL]);
    const arm = v3(m.m12 - fist.x, m.m13 - fist.y, m.m14 - fist.z);
    const reach = mathx.lenV(arm);
    const strap = mathx.lenV(mathx.scaleV(k.shieldGrip, fs));
    if (reach > strap and reach > 1e-5) {
        const pull = strap / reach;
        m.m12 = fist.x + arm.x * pull;
        m.m13 = fist.y + arm.y * pull;
        m.m14 = fist.z + arm.z * pull;
    }
    return m;
}

/// Solved ONCE, at spawn, in the guard pose: the rotation that turns the wrist frame into the door's authored
/// orientation (`rx(-6)·rz(3)` in his frame), and the grip — fist plus the centre-line pull and standoff — in
/// the wrist's own units.
fn calibrateShield(k: *Knight) void {
    const fs = k.rigScale();
    var rw = k.xf[WRL];
    rw.m12 = 0;
    rw.m13 = 0;
    rw.m14 = 0;
    const inv = 1.0 / fs;
    rw.m0 *= inv;
    rw.m1 *= inv;
    rw.m2 *= inv;
    rw.m4 *= inv;
    rw.m5 *= inv;
    rw.m6 *= inv;
    rw.m8 *= inv;
    rw.m9 *= inv;
    rw.m10 *= inv;
    const rwInv = rl.math.matrixInvert(rw);
    k.shieldFix = mul(mul3(rx(-6.0), rz(3.0), k.bodyXf), rwInv);
    const offWorld = rl.math.vector3Transform(mathx.scaleV(v3(-SHOULDER_HALF * H * 0.80, 0, SH_STANDOFF), fs), k.bodyXf);
    const offLocal = rl.math.vector3Transform(mathx.scaleV(offWorld, inv), rwInv);
    k.shieldGrip = mathx.addV(v3(0, FIST_Y, FIST_Z), offLocal);
}

test "HE ROLLS ONTO HIS FRONT AND STAYS THERE — the rise does not roll him back onto his back first" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.debugFall();
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    var rollPeak: f32 = 0;
    var seam: f32 = 0; // biggest one-frame helm jump in the move
    var humpTop: f32 = 0;
    var overshot = false;
    var prev = k.topWorld();
    var flat: f32 = 1e9;
    while (t < FALL_WIND_DUR + FALL_DUR + DOWN_DUR + ROLL_DUR + RISE_DUR + 0.25) : (t += dt) {
        _ = k.update(dt, v3(0, 0, -4), 200.0, .{});
        const helm = k.topWorld();
        if (k.state == .downed) flat = mathx.minF(flat, helm.y);
        if (k.state == .rollover) {
            rollPeak = mathx.maxF(rollPeak, k.rollAmt());
            humpTop = mathx.maxF(humpTop, helm.y);
        }
        if (k.state == .rise) try std.testing.expectApproxEqAbs(@as(f32, 0), k.rollAmt(), 1e-6);
        if (k.state == .rise and k.toppleAmt() > 0.01) overshot = true;
        if (t > FALL_WIND_DUR) seam = mathx.maxF(seam, @sqrt((helm.x - prev.x) * (helm.x - prev.x) +
            (helm.y - prev.y) * (helm.y - prev.y) + (helm.z - prev.z) * (helm.z - prev.z)));
        prev = helm;
    }
    try std.testing.expect(rollPeak > 0.99);
    try std.testing.expect(humpTop > flat + 0.4);
    try std.testing.expect(overshot);
    std.debug.print("\n  roll/rise: flat helm {d:.2}, hump to {d:.2}, worst one-frame move {d:.3} m\n", .{ flat, humpTop, seam });
    try std.testing.expect(seam < 0.35);
    try std.testing.expectEqual(State.idle, k.state);
    try std.testing.expect(@abs(mathx.wrapPi(k.facing - std.math.pi)) < 0.5);
}

test "A BODY ALREADY ON THE GROUND CANNOT BE FLINCHED UPRIGHT — the punish window survives being used" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .downed;
    k.t = DOWN_DUR * 0.4;
    k.easeFloored(1.0);
    k.pose();
    const before = k.vit.hp;
    const p = k.centerWorld();
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 30, .poise = 99, .stance = 60 } });
    try std.testing.expectEqual(State.downed, k.state);
    try std.testing.expect(k.vit.hp < before);
    try std.testing.expectEqual(@as(u32, 1), k.hits);
    k.hitLatch = false;
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = HP_MAX, .poise = 1, .stance = 1 } });
    try std.testing.expectEqual(State.dead, k.state);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), k.deathFrom, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), k.toppleAmt(), 1e-6);
    var t: f32 = 0;
    var nearest: f32 = 1e9;
    while (t < DEATH_DUR) : (t += 1.0 / 60.0) {
        k.t = t;
        nearest = mathx.minF(nearest, @abs(k.toppleAmt()));
    }
    std.debug.print("\n  killed flat: the body never comes back closer than {d:.2} of upright\n", .{nearest});
    try std.testing.expect(nearest > 0.8);
    var up = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    up.debugKill();
    up.t = DEATH_DUR;
    try std.testing.expect(up.toppleAmt() < -0.8);
}

test "THE SWORD IS CARRIED HIGH — blade up past his sword shoulder, where it cannot reach the door at all" {
    // **WHAT THIS REPLACES, AND WHY** (owner: the sword goes through it; use your judgment of how bodies work).
    // The carry was authored as Pflug — hilt at the hip, point presented forward-down. On a body whose door
    // covers his whole right side out to 1.54 m, the rig cannot put a point out past that edge without throwing
    // the arm after it: measured, the point sat 3.66 m off his centre line and 1.37 m BELOW the hilt, which is
    // Alber and not Pflug, and photographed it read as a pike carried out sideways. So the blade goes UP.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.setCarry(1.0);
    k.seatDoor();
    k.pose();
    const seg = k.weaponSeg();
    const tip = seg[1];
    const root = seg[0];
    const crown = k.topWorld().y;
    std.debug.print("\n  carry: point at x {d:.2} y {d:.2} z {d:.2}; hilt at x {d:.2} y {d:.2} z {d:.2}; door gap {d:.2} m (crown {d:.2})\n", .{
        tip.x, tip.y, tip.z, root.x, root.y, root.z, bladeDoorGap(&k).gap, crown,
    });
    try std.testing.expect(tip.y > root.y + 2.0);
    try std.testing.expect(tip.y > crown);
    // Near-plumb, so it reads as a line beside him rather than a spar held out.
    try std.testing.expect(@abs(tip.x - root.x) < 0.9 and @abs(tip.z - root.z) < 0.9);
    try std.testing.expect(root.x < -0.9 and root.x > -2.2);
    try std.testing.expect(root.y > 2.4 and root.y < 3.6);
    // AND THE CLEARANCE IS STRUCTURAL NOW, not tuned: a blade overhead cannot be swung into a plank at his side.
    try std.testing.expect(bladeDoorGap(&k).gap > 0.60);
    // …nor into HIM. Up beside the shoulder is only right while it clears the pauldron and the helm.
    const clear = struct {
        fn to(kk: *const Knight, i: usize, a: rl.Vector3, b: rl.Vector3) f32 {
            const at = rl.math.vector3Transform(mathx.zero3, kk.xf[i]);
            return mathx.lenV(mathx.subV(at, mathx.closestOnSegV(at, a, b)));
        }
    };
    std.debug.print("  blade clears: shoulder {d:.2} m, skull {d:.2} m; stands {d:.2} m over his crown\n", .{ clear.to(&k, SHR, root, tip), clear.to(&k, SKULL, root, tip), tip.y - crown });
    try std.testing.expect(clear.to(&k, SHR, root, tip) > 0.55);
    try std.testing.expect(clear.to(&k, SKULL, root, tip) > 1.0);
}

test "THE DOOR IS A FULL-HEIGHT WALL — ankle to chin, bowed, and the creature still visible over it" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.setCarry(1.0);
    k.seatDoor();
    k.pose();
    const hub = rl.math.vector3Transform(mathx.zero3, k.shXf);
    const low = hub.y - SH_BOT * k.scale;
    const high = hub.y + SH_TOP * k.scale;
    const crown = k.topWorld().y;
    const knee = k.xf[KNEEL].m13;
    std.debug.print("\n  door: foot {d:.2} m, top {d:.2} m (knee {d:.2}, crown {d:.2})\n", .{ low, high, knee, crown });
    try std.testing.expect(low < knee * 0.35);
    try std.testing.expect(low > 0.05);
    try std.testing.expect(high > crown * 0.82);
    try std.testing.expect(high < crown - 0.25);

    const mid = rl.math.vector3Transform(arcAt(0, 0, 0), k.shXf);
    const edgeL = rl.math.vector3Transform(arcAt(SH_ARC_L, 0, 0), k.shXf);
    const edgeR = rl.math.vector3Transform(arcAt(-SH_ARC_R, 0, 0), k.shXf);
    std.debug.print("  bow: mid z {d:.2}, left edge z {d:.2} (x {d:.2}), right edge z {d:.2} (x {d:.2})\n", .{
        mid.z, edgeL.z, edgeL.x, edgeR.z, edgeR.x,
    });
    try std.testing.expect(edgeL.z < mid.z - SH_SAG_L * k.scale * 0.7);
    try std.testing.expect(edgeR.z < mid.z - 0.02 * H * k.scale);
    try std.testing.expect(edgeL.x > SHOULDER_HALF * H * k.scale);
    try std.testing.expect(@abs(edgeR.x) > SHOULDER_HALF * H * k.scale);

    const chestZ = k.xf[CHEST].m14;
    const front = chestZ + CHEST_FRONT_Z * k.scale;
    const back = hub.z - SH_THICK * k.scale;
    std.debug.print("\n  door: cuirass face {d:.2}, door back face {d:.2} → {d:.2} m of daylight\n", .{ front, back, back - front });
    try std.testing.expect(back > front);
    try std.testing.expect(back < front + 0.25 * k.scale);
    try std.testing.expect(@abs(hub.x) < SH_CHORD_R * k.scale * 0.45);
}

test "HE IS BIGGER THAN THE OGRE, and that is the one fact the creature is built on" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(k.topWorld().y > giant.topWorld().y);
    try std.testing.expect(k.topWorld().y > giant.topWorld().y * 1.15);
    try std.testing.expect(crushLen(k.scale) >= k.topWorld().y * 0.85);
    try std.testing.expect(crushLen(k.scale) <= k.topWorld().y * 1.15);
}

test "THE DOOR COVERS HIS FRONT AND NOTHING ELSE — and the fall answers exactly the sector it cannot" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.covered = true;
    const at = struct {
        fn it(deg: f32, r: f32) foe.Blade {
            const a = mathx.radians(deg);
            const p = v3(mathx.sinf(a) * r, 1.0, mathx.cosf(a) * r);
            return .{ .active = true, .a = p, .b = p };
        }
    }.it;
    try std.testing.expect(k.shielded(at(0, 4.0)));
    try std.testing.expect(k.shielded(at(TOWER_ARC - 3.0, 4.0)));
    try std.testing.expect(!k.shielded(at(TOWER_ARC + 3.0, 4.0)));
    try std.testing.expect(!k.shielded(at(180.0, 4.0)));
    try std.testing.expect(SH_CHORD_L + SH_CHORD_R > 0.45 * H);
    try std.testing.expect(TOWER_ARC > 40.0 and TOWER_ARC < 60.0);
    try std.testing.expect(180.0 - FALL_SECTOR > TOWER_ARC);
    try std.testing.expect(180.0 - FALL_SECTOR > TOWER_ARC);
    try std.testing.expect(180.0 - FALL_SECTOR - TOWER_ARC > 20.0);
    k.covered = false;
    try std.testing.expect(!k.shielded(at(0, 4.0)));
}

test "A BLOW ON THE DOOR TAKES NO POISE, BUT THE FOOTING BEHIND IT CAN BE WORN THROUGH" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .idle;
    k.covered = true;
    const before = k.vit.hp;
    const stanceBefore = k.vit.stance;
    const p = v3(0, 2.6, k.hurtRadius() * 0.5);
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 40, .poise = 90, .stance = 60 } });
    try std.testing.expectEqual(@as(u32, 1), k.blocks);
    try std.testing.expectEqual(State.idle, k.state);
    try std.testing.expect(k.vit.poise == k.vit.poiseMax);
    try std.testing.expect(k.vit.stance < stanceBefore);
    try std.testing.expect(k.vit.hp < before);
    try std.testing.expect(k.vit.hp > before - 40.0 * 0.5);
    var pressed = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    pressed.state = .idle;
    var swings: u32 = 0;
    while (swings < 40 and !pressed.staggered()) : (swings += 1) {
        pressed.covered = true;
        pressed.hitLatch = false;
        pressed.vit.hp = HP_MAX;
        pressed.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 1, .poise = 90, .stance = 60 } });
    }
    try std.testing.expect(pressed.staggered());
    try std.testing.expect(swings > 2);
    try std.testing.expect(pressed.blocks == swings);
    var back = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    back.state = .idle;
    back.covered = true;
    const q = v3(0, 2.6, -k.hurtRadius() * 0.5);
    // A creature's flinch is health taken (`combat.FOE_POISE_PER_DMG`): 100 off his 900 pours 82 into a 78 pool.
    back.tryHit(.{ .active = true, .r = 0.2, .a = q, .b = q, .a0 = q, .b0 = q, .hit = .{ .dmg = 100, .poise = 90, .stance = 60 } });
    try std.testing.expectEqual(@as(u32, 0), back.blocks);
    try std.testing.expectEqual(@as(u32, 1), back.hits);
    try std.testing.expect(back.staggered());
}

test "A BLOW THE DOOR STOPPED CANNOT FLINCH HIM — the pool, the footing, the stagger and the wear all refused" {
    // `Vitals.strike` empties the pool and begins the stagger before `tryHit` can answer for the block, and
    // restoring only `poise` left him `stunned()` — which refuses every pool for a whole stun while he goes on
    // attacking. The chip is 10% of `dmg` (`TOWER_NEGATE`), so 10 pours 0.82 into a pool left with 0.5 in it.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .idle;
    k.covered = true;
    k.vit.poise = 0.5;
    const stanceBefore = k.vit.stance;
    const p = v3(0, 2.6, k.hurtRadius() * 0.5);
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 10, .poise = 0, .stance = 60 } });
    try std.testing.expectEqual(@as(u32, 1), k.blocks);
    try std.testing.expect(!k.vit.stunned());
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), k.vit.poise, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.vit.lightWear, 1e-6);
    // The guard-break's own share still passes (`TOWER_STANCE_PASS`) and nothing beyond it.
    try std.testing.expectApproxEqAbs(stanceBefore - 60.0 * TOWER_STANCE_PASS, k.vit.stance, 1e-3);

    // …and the same blow with the door turned away DOES flinch him, so the refusal is the door and not the sum.
    var open = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    open.state = .idle;
    open.vit.poise = 0.5;
    const q = v3(0, 2.6, -open.hurtRadius() * 0.5);
    open.tryHit(.{ .active = true, .r = 0.2, .a = q, .b = q, .a0 = q, .b0 = q, .hit = .{ .dmg = 10, .poise = 0, .stance = 0 } });
    try std.testing.expectEqual(@as(u32, 0), open.blocks);
    try std.testing.expect(open.vit.stunned());
}

test "THE STRING IS ONE COMMITMENT — variable length, capped, and the debt paid at the finisher" {
    try std.testing.expect(stringNext(OVER_I) == null);
    for ([_]usize{ SWEEP_I, SWEEP2_I, THRUST_I, BASH_I }) |mv| try std.testing.expect(stringNext(mv) != null);
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    for ([_]usize{ SWEEP_I, SWEEP2_I, THRUST_I, BASH_I }) |mv| {
        k.atk = mv;
        k.state = windFor(mv);
        k.windHold = 0;
        k.strung = 1;
        const strungWind = k.windDur();
        k.strung = 0;
        try std.testing.expect(strungWind >= foe.TELL_MIN);
        try std.testing.expect(strungWind < k.windDur());
    }
    k.strung = 2;
    k.cds = [_]f32{0} ** MOVES.len;
    k.strungUsed = [_]bool{false} ** MOVES.len;
    k.strungUsed[SWEEP_I] = true;
    k.strungUsed[THRUST_I] = true;
    k.billString();
    try std.testing.expect(k.cds[SWEEP_I] > 0 and k.cds[THRUST_I] > 0);
    try std.testing.expect(k.cds[BASH_I] == 0);
    try std.testing.expectEqual(@as(u8, 0), k.strung);
    try std.testing.expect(k.cds[SWEEP_I] > SWEEP.cd * 0.82);
    var cut = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    cut.strung = 1;
    cut.strungUsed[SWEEP_I] = true;
    cut.enterStun(.stunheavy);
    try std.testing.expect(cut.cds[SWEEP_I] > 0);
    try std.testing.expectEqual(@as(u8, 0), cut.strung);
}

test "THE FLANK IS NOT A PLACE TO STAND — the sweep reaches it, and its own gather is the aim" {
    const scale = SCALE;
    // Past the shove's band (`SHOVE_BAND` x the bash's trigger), where the flank answer is the SWEEP.
    const r = triggerR(SWEEP, scale) * 0.95;
    try std.testing.expect(r > triggerR(BASH, scale) * SHOVE_BAND);
    var noSwat = [_]bool{ true, true, true, true, true, true };
    noSwat[SWAT_I] = false;
    var found = false;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const dec = classify(.{ .dist = r, .bearing = SWEEP_BEARING + 20.0, .scale = scale, .cursor = i, .ready = &noSwat });
        if (dec.what == .strike and dec.mv == SWEEP_I) found = true;
    }
    try std.testing.expect(found);
    // Inside the flick's own reach a flanker draws the swat — the SWORD side off the sword's, the SHIELD side off the door's; beyond it the sweep.
    try std.testing.expectEqual(@as(usize, SWAT_I), classify(.{ .dist = swatTriggerR(false, scale) * 0.9, .bearing = -(SWEEP_BEARING + 20.0), .scale = scale, .cursor = 0, .ready = &[_]bool{ true, true, true, true, true, true } }).mv);
    try std.testing.expectEqual(@as(usize, SWAT_I), classify(.{ .dist = swatTriggerR(true, scale) * 0.9, .bearing = SWEEP_BEARING + 20.0, .scale = scale, .cursor = 0, .ready = &[_]bool{ true, true, true, true, true, true } }).mv);
    try std.testing.expect(swatTriggerR(true, scale) < swatTriggerR(false, scale));
    const shieldFar = classify(.{ .dist = r, .bearing = SWEEP_BEARING + 20.0, .scale = scale, .cursor = 0, .ready = &[_]bool{ true, true, true, true, true, true } });
    try std.testing.expectEqual(@as(usize, SWEEP_I), shieldFar.mv);
    const far = classify(.{ .dist = r, .bearing = FLANK_BEARING + 10.0, .scale = scale, .cursor = 0, .ready = &[_]bool{ true, true, true, true, true, true } });
    try std.testing.expect(far.what != .strike);

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const rad = mathx.radians(FLANK_BEARING);
    const hero = v3(mathx.sinf(rad) * r, 0, mathx.cosf(rad) * r);
    k.atk = SWEEP_I;
    k.enter(.sweepwind);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < SWEEP.windDur) : (t += dt) {
        foe.faceToward(k.pos, &k.facing, hero, TURN_RATE, dt);
    }
    try std.testing.expect(@abs(k.bearingTo(hero)) < SWEEP_BEARING);
}

test "THE POSE DOES NOT TELEPORT — the body CHASES its target, so no interrupt can snap it" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt = 1.0 / 60.0;
    k.atk = SWEEP_I;
    k.enter(.sweep);
    k.t = SWEEP.strikeDur;
    var n: u32 = 0;
    while (n < 40) : (n += 1) {
        k.setStrike(1.0);
        k.settlePose(dt);
    }
    const mid = k.chanGet();
    k.enterStun(.stunheavy);
    k.easeNeutral(dt);
    k.settlePose(dt);
    const after = k.chanGet();
    for (mid, after) |was, now| try std.testing.expect(@abs(now - was) < 12.0);
    n = 0;
    while (n < 240) : (n += 1) {
        k.easeNeutral(dt);
        k.settlePose(dt);
    }
    try std.testing.expectApproxEqAbs(CARRY_SH, k.armSh, 3.0);
    try std.testing.expect(SPRING_ZETA < 1.0);
    try std.testing.expect(SPRING_STIFF_DOWN > SPRING_STIFF);
    try std.testing.expect(SPRING_FALLOFF < 1.0 and SPRING_FALLOFF > 0.8);
}

test "LIGHT AND HEAVY ARE TELLABLE APART BEFORE THEY LAND, and a move cannot lie about its weight" {
    var lightest: f32 = 1e9;
    var heaviest: f32 = 0;
    for (MOVES) |a| {
        switch (a.weight) {
            .light => lightest = @min(lightest, a.hit.dmg),
            .heavy, .crushing => heaviest = @max(heaviest, a.hit.dmg),
        }
        if (a.hit.dmg >= 34) try std.testing.expect(a.weight == .crushing);
        if (a.hit.dmg <= 27) try std.testing.expect(a.weight != .crushing);
    }
    try std.testing.expect(lightest < heaviest);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Weight.light.ember(), 1e-6);
    try std.testing.expect(Weight.heavy.ember() > 0 and Weight.heavy.ember() < Weight.crushing.ember());
}

test "A COMBO IS A ROUTE HE WALKS, and its END is a window you can plan for" {
    for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWEEP2_I, SWAT_I }) |mv| {
        const route = routeFor(mv);
        try std.testing.expect(route.len >= 1);
        try std.testing.expect(route[0] != mv);
        for (route, 0..) |link, i| {
            if (link == OVER_I) try std.testing.expectEqual(route.len - 1, i);
        }
    }
    try std.testing.expectEqual(@as(usize, 0), routeFor(OVER_I).len);
    var longest: usize = 0;
    for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWEEP2_I, SWAT_I }) |mv| longest = @max(longest, routeFor(mv).len);
    try std.testing.expect(longest >= 3);
    {
        var distinct: u32 = 0;
        for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWAT_I }) |a| {
            for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWAT_I }) |b2| {
                if (a >= b2) continue;
                const ra = routeFor(a);
                const rb = routeFor(b2);
                if (ra.len != rb.len or !std.mem.eql(usize, ra, rb)) distinct += 1;
            }
        }
        try std.testing.expectEqual(@as(u32, 6), distinct);
    }
    for (MOVES) |a| try std.testing.expect(a.windDur >= foe.TELL_MIN);

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.strung = 0;
    try std.testing.expect(!k.inString());
    k.strung = 1;
    try std.testing.expect(k.inString());
    const p = v3(0, 2.6, -k.hurtRadius() * 0.5);
    k.atk = SWEEP2_I;
    k.enter(.sweep2);
    k.strung = 1;
    k.vit.poise = 1;
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 4, .poise = 40, .stance = 1 } });
    try std.testing.expect(!k.staggered());
    try std.testing.expectEqual(State.sweep2, k.state);
    var b2 = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    b2.atk = SWEEP2_I;
    b2.enter(.sweep2);
    b2.strung = 1;
    b2.vit.stance = 1;
    b2.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 4, .poise = 10, .stance = 40 } });
    try std.testing.expect(b2.staggered());
}

test "HE DOES NOT FLINCH AT A POKE — a boss's poise is past what light spam can reach" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const p = v3(0, 2.6, -k.hurtRadius() * 0.5);
    var pokes: u32 = 0;
    while (pokes < 4) : (pokes += 1) {
        k.hitLatch = false;
        k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 6, .poise = 14, .stance = 3 } });
    }
    try std.testing.expect(!k.staggered());
    // TWO parries open him (owner: parry potential), and one does not — his own bite, over the shared 46.
    try std.testing.expect(PARRY_STANCE * 2 >= STANCE_MAX);
    try std.testing.expect(PARRY_STANCE < STANCE_MAX);
    try std.testing.expect(PARRY_STANCE > combat.PARRY_HIT.stance);
    try std.testing.expect(TOWER_STANCE_PASS < 0.25);
}

test "A FLANK BLOW HE SHRUGS OFF IS ANSWERED — he counters, he does not stand there turning" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const side = v3(k.hurtRadius() * 0.6, 2.6, 0);
    k.state = .idle;
    k.tryHit(.{ .active = true, .r = 0.2, .a = side, .b = side, .a0 = side, .b0 = side, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.stepturn, k.state);
    try std.testing.expectEqual(@as(?usize, SWAT_I), k.stepThen);
    try std.testing.expect(k.counterCd > 0);
    try std.testing.expect(@abs(k.bearingTo(side)) > 40.0);

    var front = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    front.state = .idle;
    const ahead = v3(0, 2.6, front.hurtRadius() * 0.6);
    front.tryHit(.{ .active = true, .r = 0.2, .a = ahead, .b = ahead, .a0 = ahead, .b0 = ahead, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.idle, front.state);

    var broke = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    broke.state = .idle;
    broke.vit.stance = 1;
    broke.tryHit(.{ .active = true, .r = 0.2, .a = side, .b = side, .a0 = side, .b0 = side, .hit = .{ .dmg = 6, .poise = 2, .stance = 60 } });
    try std.testing.expect(broke.staggered());

    var mid = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    mid.atk = SWEEP_I;
    mid.enter(.sweep);
    mid.tryHit(.{ .active = true, .r = 0.2, .a = side, .b = side, .a0 = side, .b0 = side, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.sweep, mid.state);

    var back = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    back.state = .idle;
    const behind = v3(0, 2.6, -back.hurtRadius() * 0.6);
    back.tryHit(.{ .active = true, .r = 0.2, .a = behind, .b = behind, .a0 = behind, .b0 = behind, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.fallwind, back.state);

    var spent = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    spent.state = .idle;
    spent.fallCd = 5.0;
    spent.tryHit(.{ .active = true, .r = 0.2, .a = behind, .b = behind, .a0 = behind, .b0 = behind, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.stepturn, spent.state);
    try std.testing.expectEqual(@as(?usize, SWAT_I), spent.stepThen);

    var flee = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    flee.state = .idle;
    flee.fallCd = 5.0;
    flee.sense.hurt(HP_MAX * RETREAT_AT + 1.0);
    flee.tryHit(.{ .active = true, .r = 0.2, .a = behind, .b = behind, .a0 = behind, .b0 = behind, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.leapwind, flee.state);
}

test "PHASE TWO AT HALF HEALTH — he lights the sword, and from then on every blow opens a disc" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), AWAKEN.at, 1e-6);

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.leash.provoke();
    try std.testing.expect(!k.lit);
    k.vit.hp = k.vit.hpMax * 0.6;
    k.decide(6.0, 0);
    try std.testing.expect(k.state != .awaken);
    k.vit.hp = k.vit.hpMax * 0.5;
    k.decide(6.0, 0);
    try std.testing.expectEqual(State.awaken, k.state);
    try std.testing.expect(!k.lit);

    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    const far = v3(0, 0, 40.0);
    while (t < AWAKEN.liftDur + AWAKEN.holdDur + AWAKEN.settleDur + 0.05) : (t += dt) {
        try std.testing.expect(k.update(dt, far, 400.0, .{}) == null);
    }
    try std.testing.expect(k.lit);

    k.vit.hp = k.vit.hpMax;
    k.vit.hp = k.vit.hpMax * 0.2;
    k.decide(6.0, 0);
    try std.testing.expect(k.state != .awaken);
    try std.testing.expect(k.lit);

    try std.testing.expect(CHAOS_BLAST.hit.elem.at(.chaos) > 0);
    try std.testing.expect(GAS_HIT.dmg < CHAOS_BLAST.hit.dmg);
    try std.testing.expect(GAS_HIT.poise == 0 and GAS_HIT.stance == 0);
    try std.testing.expect(GAS_HIT.elem.at(.chaos) > 0);
    try std.testing.expect(CHAOS_BLAST.hit.dmg < SWEEP_HIT.dmg);
    try std.testing.expect(CHAOS_BLAST.r > 0.5);
}

test "PHASE TWO'S GAS: the heavy strokes foul the ground, the flick does not, and only once he is lit" {
    var anyHeavy = false;
    var anyLight = false;
    for (MOVES) |a| {
        if (a.weight == .light) anyLight = true else anyHeavy = true;
    }
    try std.testing.expect(anyHeavy and anyLight);
    try std.testing.expect(MOVES[SWAT_I].weight == .light);

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.lit = false;
    k.atk = SWEEP_I;
    k.enter(.sweep);
    var f: usize = 0;
    while (f < 60) : (f += 1) {
        _ = k.update(1.0 / 60.0, v3(0, 0, 3.0), 60, .{});
        try std.testing.expect(k.gasAt == null);
    }

    var g = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    g.lit = true;
    g.atk = SWEEP_I;
    g.enter(.sweep);
    var laid = false;
    f = 0;
    while (f < 120 and !laid) : (f += 1) {
        _ = g.update(1.0 / 60.0, v3(0, 0, 40.0), 60, .{});
        if (g.gasAt != null) laid = true;
    }
    try std.testing.expect(laid);
}

test "the gas DOSES on its own clock, re-arms when he steps out, and thins to nothing" {
    var v = Vigil{ .model = undefined };
    const at = mathx.zero3;
    v.spawnGas(at, 1.0);
    try std.testing.expect(v.gas[0].radius() < GAS_R);
    var t: f32 = 0;
    while (t < GAS_GROW * 2) : (t += 1.0 / 60.0) v.gas[0].update(1.0 / 60.0);
    try std.testing.expect(v.gas[0].covers(at));

    var bites: usize = 0;
    t = 0;
    while (t < GAS_DOSE_EVERY * 3.0) : (t += 1.0 / 60.0) {
        if (v.gasDose(1.0 / 60.0, at) != null) bites += 1;
    }
    // The FIRST frame inside bills, so three intervals of standing there is four doses.
    try std.testing.expect(bites >= 3 and bites <= 5);

    const outside = v3(GAS_R * 4.0, 0, 0);
    try std.testing.expect(v.gasDose(1.0 / 60.0, outside) == null);
    // **RE-ARMED, NOT ZEROED**: stepping out leaves it DUE, so stepping back in bills on the entry frame.
    try std.testing.expectApproxEqAbs(GAS_DOSE_EVERY, v.gasT, 1e-6);
    try std.testing.expect(v.gasDose(1.0 / 60.0, at) != null);

    t = 0;
    while (t < GAS_LIFE + 0.5) : (t += 1.0 / 60.0) v.gas[0].update(1.0 / 60.0);
    try std.testing.expect(!v.gas[0].covers(at));
    try std.testing.expect(v.gasDose(1.0 / 60.0, at) == null);

    t = 0;
    while (t < GAS_PUFF_HI + 0.05) : (t += 1.0 / 60.0) v.gas[0].update(1.0 / 60.0);
    for (v.gas[0].parts) |p| try std.testing.expect(p.life <= 0);
}

/// A point held at `deg` off whatever he is facing RIGHT NOW, `out` metres away — what a bearing rule has to be
/// tested against once the creature turns faster than the tester can drop a fixed point.
fn flankOf(k: *const Knight, deg: f32, out: f32) rl.Vector3 {
    const a = k.facing + mathx.radians(deg);
    return v3(k.pos.x + mathx.sinf(a) * out, 0, k.pos.z + mathx.cosf(a) * out);
}

test "THE SWIPE-AND-LEAP — one beat, not two, only ever off a flank, and only once he is being shredded" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.atk = SWAT_I;
    k.opener = SWAT_I;
    k.enter(.swat);
    k.leapCd = 0;
    k.sense.hurt(HP_MAX * RETREAT_AT * 1.2);
    // **HELD ON THE FLANK WHILE HE TURNS ONTO IT.** A fixed point is not a flank any more: he tracks at
    // 4.8 rad/s through the swat's own 0.16 s, so a body dropped at 95 deg finishes the stroke squared up.
    // What the chain reads is the BEARING at the end, so the test has to keep one.
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    while (t < SWAT.strikeDur + 0.05 and k.state == .swat) : (t += dt) {
        _ = k.update(dt, flankOf(&k, 95.0, 4.1), 400.0, .{});
    }
    try std.testing.expectEqual(State.leapwind, k.state);
    try std.testing.expect(k.leapChained);
    try std.testing.expect(k.leapWind() < LEAP.windDur);
    try std.testing.expect(LEAP_CHAIN_WIND < 1.0);

    var sq = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    sq.atk = SWAT_I;
    sq.opener = SWAT_I;
    sq.enter(.swat);
    sq.leapCd = 0;
    sq.sense.hurt(HP_MAX * RETREAT_AT * 1.2);
    t = 0;
    while (t < SWAT.strikeDur + 0.05 and sq.state == .swat) : (t += dt) {
        _ = sq.update(dt, flankOf(&sq, 0.0, 4.0), 400.0, .{});
    }
    try std.testing.expect(sq.state != .leapwind);

    // The same flank, unharried: he does NOT give the ground — the string ends and he stands his recovery.
    var calm = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    calm.atk = SWAT_I;
    calm.opener = SWAT_I;
    calm.enter(.swat);
    calm.leapCd = 0;
    t = 0;
    while (t < SWAT.strikeDur + 0.05 and calm.state == .swat) : (t += dt) {
        _ = calm.update(dt, flankOf(&calm, 95.0, 4.1), 400.0, .{});
    }
    try std.testing.expect(calm.state != .leapwind);

    var cold = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    cold.enter(.leapwind);
    try std.testing.expect(!cold.leapChained);
    try std.testing.expectApproxEqAbs(LEAP.windDur, cold.leapWind(), 1e-6);
    try std.testing.expect(cold.leapWind() >= foe.TELL_MIN);
}

test "THE LEAP — he buys ground and lands facing you, and the roots refuse it" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const ready = [_]bool{ true, true, true, true, true, true };
    const dec = classify(.{ .dist = crushLen(k.scale) * 0.6, .bearing = 180.0, .scale = k.scale, .leapReady = true, .pressed = true, .harried = true, .cursor = 0, .ready = &ready });
    try std.testing.expectEqual(Choice.leap, dec.what);
    // Pressure that only warrants a REPOSITION never buys the jumpback — the leap asks the retreat tier.
    const merelyPressed = classify(.{ .dist = crushLen(k.scale) * 0.6, .bearing = 180.0, .scale = k.scale, .stepReady = true, .leapReady = true, .pressed = true, .cursor = 0, .ready = &ready });
    try std.testing.expectEqual(Choice.stepturn, merelyPressed.what);
    comptime std.debug.assert(FLANK_BEARING + 5.0 < 180.0 - FALL_SECTOR);
    const flankPressed = classify(.{ .dist = triggerR(SWEEP, k.scale) * 0.8, .bearing = FLANK_BEARING + 5.0, .scale = k.scale, .stepReady = true, .leapReady = true, .pressed = true, .cursor = 0, .ready = &ready });
    try std.testing.expect(flankPressed.what != Choice.leap);
    const flankHarried = classify(.{ .dist = triggerR(SWEEP, k.scale) * 0.8, .bearing = FLANK_BEARING + 5.0, .scale = k.scale, .leapReady = true, .pressed = true, .harried = true, .cursor = 0, .ready = &ready });
    try std.testing.expectEqual(Choice.leap, flankHarried.what);
    const unpressed = classify(.{ .dist = crushLen(k.scale) * 0.6, .bearing = 180.0, .scale = k.scale, .stepReady = true, .leapReady = true, .cursor = 0, .ready = &ready });
    try std.testing.expectEqual(Choice.stepturn, unpressed.what);
    const withFall = classify(.{ .dist = crushLen(k.scale) * 0.6, .bearing = 180.0, .scale = k.scale, .fallReady = true, .leapReady = true, .pressed = true, .harried = true, .cursor = 0, .ready = &ready });
    try std.testing.expectEqual(Choice.fall, withFall.what);
    // The tiers are one meter read twice: banked hurt past REPOSITION_AT moves him about, past RETREAT_AT breaks him.
    var meter = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    meter.sense.hurt(HP_MAX * REPOSITION_AT + 1.0);
    try std.testing.expect(meter.pressed() and !meter.harried());
    meter.sense.hurt(HP_MAX * (RETREAT_AT - REPOSITION_AT));
    try std.testing.expect(meter.harried());

    const hero = v3(0, 0, -3.0);
    k.facing = 0;
    k.enter(.leapwind);
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    var peak: f32 = 0;
    var flew = false;
    const startZ = k.pos.z;
    while (t < LEAP.windDur + LEAP.flightDur + LEAP.landDur + 0.1) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        peak = @max(peak, k.air);
        if (k.airborne()) flew = true;
    }
    try std.testing.expect(flew and peak > foe.AIRBORNE_LIFT * 4.0);
    try std.testing.expect(k.pos.z > startZ + 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.air, 1e-4);
    try std.testing.expect(@abs(k.bearingTo(hero)) < 40.0);
    var held = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    held.root.grab();
    try std.testing.expect(!foe.canLeap(&held.root));
}

test "THE SWORD SIDE HAS AN ANSWER — the shove, and it pays for that flank with his front" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const ready = [_]bool{ true, true, true, true, true, true };
    const near = triggerR(BASH, k.scale) * 0.9;
    var noSwat = ready;
    noSwat[SWAT_I] = false;
    const sword = classify(.{ .dist = near, .bearing = -(SWEEP_BEARING + 12.0), .scale = k.scale, .hopReady = true, .cursor = 0, .ready = &noSwat });
    try std.testing.expectEqual(Choice.strike, sword.what);
    try std.testing.expectEqual(@as(usize, BASH_I), sword.mv);
    try std.testing.expect(sword.shove);
    try std.testing.expect(!sword.shoveShield);
    const shield = classify(.{ .dist = near, .bearing = SWEEP_BEARING + 12.0, .scale = k.scale, .pressed = true, .cursor = 0, .ready = &noSwat });
    try std.testing.expect(shield.shove);
    try std.testing.expect(shield.shoveShield);
    var sw = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    sw.shoveShield = false;
    var sh2 = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    sh2.shoveShield = true;
    try std.testing.expect(sw.shoveDir() * sh2.shoveDir() < 0);
    var s = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.atk = BASH_I;
    s.shoving = true;
    s.enter(.bash);
    s.t = BASH.strikeDur * 0.6;
    // The channel is CHASED now, so a poked clock has to be seated — in play it is inherited frame to frame.
    s.seatDoor();
    try std.testing.expect(s.shoveAcross() > 0.5);
    try std.testing.expect(!s.guardUp());
    s.shoving = false;
    s.seatDoor();
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.shoveAcross(), 1e-6);
    try std.testing.expect(s.guardUp());
    try std.testing.expect(BASH.windDur >= foe.TELL_MIN);
    for ([_][]const PoseKey{ SHOVE_KEYS.wind, SHOVE_KEYS.strike, SHOVE_KEYS.recover }) |list| {
        try std.testing.expectApproxEqAbs(@as(f32, 0), list[0].t, 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 1), list[list.len - 1].t, 1e-6);
    }
    const wEnd = samplePose(SHOVE_KEYS.wind, 1.0);
    const sStart = samplePose(SHOVE_KEYS.strike, 0.0);
    for (wEnd, sStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
}

test "THE PHASES MEET — a stroke's wind, strike and recover are one continuous track" {
    for ([_]usize{ SWEEP_I, SWEEP2_I, OVER_I, THRUST_I, BASH_I }) |mv| {
        const m = keysFor(mv);
        const windEnd = samplePose(m.wind, 1.0);
        const strikeStart = samplePose(m.strike, 0.0);
        const strikeEnd = samplePose(m.strike, 1.0);
        const recStart = samplePose(m.recover, 0.0);
        for (windEnd, strikeStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        for (strikeEnd, recStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        for ([_][]const PoseKey{ m.wind, m.strike, m.recover }) |list| {
            try std.testing.expect(list.len >= 2);
            try std.testing.expectApproxEqAbs(@as(f32, 0), list[0].t, 1e-6);
            try std.testing.expectApproxEqAbs(@as(f32, 1), list[list.len - 1].t, 1e-6);
            var i: usize = 1;
            while (i < list.len) : (i += 1) try std.testing.expect(list[i].t > list[i - 1].t);
        }
    }
    {
        const windEnd = samplePose(CHARGE_KEYS.wind, 1.0);
        const runStart = samplePose(CHARGE_KEYS.strike, 0.0);
        const runEnd = samplePose(CHARGE_KEYS.strike, 1.0);
        const brakeStart = samplePose(CHARGE_KEYS.recover, 0.0);
        const brakeEnd = samplePose(CHARGE_KEYS.recover, 1.0);
        const recStart = samplePose(&CHG_REC, 0.0);
        for (windEnd, runStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        for (runEnd, brakeStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        for (brakeEnd, recStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
    }
}

test "EVERY STROKE HAS A SHAPE, NOT TWO POSES — a gather that loads, a snap, and a follow-through" {
    for ([_]usize{ SWEEP_I, SWEEP2_I, OVER_I, THRUST_I, BASH_I }) |mv| {
        const m = keysFor(mv);
        const s0 = samplePose(m.strike, 0.0);
        const s1 = samplePose(m.strike, 1.0);
        var far: usize = 0;
        var span: f32 = 0;
        for (s0, s1, 0..) |a, b, i| {
            if (@abs(b - a) > span) {
                span = @abs(b - a);
                far = i;
            }
        }
        try std.testing.expect(span > 20.0);
        const third = samplePose(m.strike, 0.34)[far];
        const done = @abs(third - s0[far]) / span;
        try std.testing.expect(done > 0.55);
        var overshot = false;
        var u: f32 = 0;
        while (u <= 1.0) : (u += 0.02) {
            const v = samplePose(m.strike, u);
            for (v, s0, s1) |now, a, b| {
                const hi = @max(a, b);
                const lo = @min(a, b);
                if (now > hi + 2.0 or now < lo - 2.0) overshot = true;
            }
        }
        try std.testing.expect(overshot);
    }
    const w = OVER_KEYS.wind;
    try std.testing.expectEqual(anim.Ease.hold, w[w.len - 1].ease);
}

test "A MOVE IS A SEQUENCE OF POSES, and the last one HOLDS — the End Pose is the punish window" {
    const keys = [_]PoseKey{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.45, .p = .{ .armSh = -120, .lean = -22 }, .ease = .accel },
        .{ .t = 0.55, .p = .{ .armSh = -120, .lean = -22 }, .ease = .hold },
        .{ .t = 0.70, .p = .{ .armSh = 70, .lean = 34 }, .ease = .snap },
    };
    const gather = samplePose(&keys, 0.25);
    try std.testing.expect(gather[Knight.CH_ARM_SH] < CARRY_SH and gather[Knight.CH_ARM_SH] > -120);
    const hangA = samplePose(&keys, 0.47);
    const hangB = samplePose(&keys, 0.54);
    try std.testing.expectApproxEqAbs(hangA[Knight.CH_ARM_SH], hangB[Knight.CH_ARM_SH], 1e-4);
    const quarter = samplePose(&keys, 0.55 + 0.15 * 0.25);
    try std.testing.expect(quarter[Knight.CH_ARM_SH] > -120 + (70 - -120) * 0.6);
    const end = samplePose(&keys, 1.0);
    const wayPast = samplePose(&keys, 4.0);
    try std.testing.expectApproxEqAbs(@as(f32, 70), end[Knight.CH_ARM_SH], 1e-4);
    try std.testing.expectApproxEqAbs(end[Knight.CH_ARM_SH], wayPast[Knight.CH_ARM_SH], 1e-6);
}

test "THE BODY LANDS ON YOU ONCE — every blow he owns is latched, and the fall's was not" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.debugFall();
    const behind = v3(0, 0, -crushLen(k.scale) * 0.5);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var landed: u32 = 0;
    while (t < FALL_WIND_DUR + FALL_DUR + 0.2) : (t += dt) {
        if (k.update(dt, behind, 400.0, .{}) != null) landed += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), landed);
    var heavier: u32 = 0;
    for (MOVES) |a| {
        if (a.hit.dmg > FALL_HIT.dmg) heavier += 1;
    }
    try std.testing.expect(heavier >= MOVES.len - 2);
    try std.testing.expect(SLAM_HIT.dmg > FALL_HIT.dmg and CHARGE_HIT.dmg > FALL_HIT.dmg);
}

test "THE FALL LANDS BEHIND HIM AND NOWHERE ELSE" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const reach = crushLen(k.scale);
    k.heroHit = null;
    k.tryCrush(v3(0, 0, -reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit != null);
    k.heroHit = null;
    k.tryCrush(v3(0, 0, reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
    k.heroHit = null;
    k.tryCrush(v3(0, 0, -reach - 1.5), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
    k.heroHit = null;
    k.tryCrush(v3(foe.hurtReach(FALL_HALF_W, k.scale) + 1.2, 0, -reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
}

test "THE BANDS AND THE PATTERNS: falls behind, hops when circled, and repeats so he can be learned" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const ready = [_]bool{ true, true, true, true, true, true };
    const cold = [_]bool{ false, false, false, false, false, false };
    const boots = triggerR(BASH, k.scale) * 0.8;
    const mid0 = (triggerR(BASH, k.scale) + triggerR(SWEEP, k.scale)) * 0.5;

    for ([_]usize{ 0, 1, 2, 3, 4, 5 }) |c| {
        const a = classify(.{ .dist = mid0, .bearing = 0, .scale = k.scale, .cursor = c, .ready = &ready });
        const b2 = classify(.{ .dist = mid0, .bearing = 0, .scale = k.scale, .cursor = c, .ready = &ready });
        try std.testing.expectEqual(a.what, b2.what);
        try std.testing.expectEqual(a.mv, b2.mv);
    }
    {
        var seen = [_]bool{false} ** MOVES.len;
        for ([_]usize{ 0, 1, 2, 3 }) |c| {
            const dec = classify(.{ .dist = mid0, .bearing = 0, .scale = k.scale, .cursor = c, .ready = &ready });
            if (dec.what == .strike) seen[dec.mv] = true;
        }
        var kinds: u32 = 0;
        for (seen) |s| {
            if (s) kinds += 1;
        }
        try std.testing.expect(kinds >= 2);
    }
    {
        var differs = false;
        for ([_]usize{ 0, 1, 2, 3 }) |c| {
            const l = classify(.{ .dist = mid0, .bearing = SWING_BEARING - 6.0, .scale = k.scale, .cursor = c, .ready = &ready });
            const r = classify(.{ .dist = mid0, .bearing = -(SWING_BEARING - 6.0), .scale = k.scale, .cursor = c, .ready = &ready });
            if (l.mv != r.mv) differs = true;
        }
        try std.testing.expect(differs);
    }

    try std.testing.expectEqual(Choice.fall, classify(.{ .dist = crushLen(k.scale) * 0.7, .bearing = 180.0, .scale = k.scale, .fallReady = true, .slamReady = true, .hopReady = true, .circling = true, .pressed = true, .cursor = 0, .ready = &ready }).what);
    try std.testing.expectEqual(Choice.hop, classify(.{ .dist = crushLen(k.scale) * 0.7, .bearing = 180.0, .scale = k.scale, .slamReady = true, .hopReady = true, .circling = true, .pressed = true, .cursor = 0, .ready = &ready }).what);
    try std.testing.expectEqual(Choice.wait, classify(.{ .dist = crushLen(k.scale) * 0.7, .bearing = 180.0, .scale = k.scale, .slamReady = true, .hopReady = true, .circling = true, .cursor = 0, .ready = &ready }).what);
    try std.testing.expectEqual(Choice.wait, classify(.{ .dist = crushLen(k.scale) * 0.7, .bearing = 180.0, .scale = k.scale, .slamReady = true, .hopReady = true, .cursor = 0, .ready = &ready }).what);
    const flank = SWEEP_BEARING + 15.0;
    try std.testing.expectEqual(@as(usize, SWAT_I), classify(.{ .dist = boots, .bearing = flank, .scale = k.scale, .fallReady = true, .slamReady = true, .hopReady = true, .circling = true, .pressed = true, .cursor = 0, .ready = &ready }).mv);
    var noSwat = ready;
    noSwat[SWAT_I] = false;
    var coldBash = noSwat;
    coldBash[BASH_I] = false;
    for ([_]f32{ flank, -flank }) |b| {
        const d = classify(.{ .dist = boots, .bearing = b, .scale = k.scale, .fallReady = true, .slamReady = true, .hopReady = true, .circling = true, .cursor = 0, .ready = &noSwat });
        try std.testing.expectEqual(Choice.strike, d.what);
        try std.testing.expectEqual(@as(usize, BASH_I), d.mv);
        try std.testing.expect(d.shove);
        try std.testing.expect(d.shoveShield == (b > 0));
    }
    try std.testing.expectEqual(@as(usize, SWEEP_I), classify(.{ .dist = boots, .bearing = flank, .scale = k.scale, .fallReady = true, .slamReady = true, .hopReady = true, .cursor = 0, .ready = &coldBash }).mv);
    try std.testing.expectEqual(Choice.hop, classify(.{ .dist = boots, .bearing = -flank, .scale = k.scale, .fallReady = true, .slamReady = true, .hopReady = true, .circling = true, .pressed = true, .cursor = 0, .ready = &coldBash }).what);
    try std.testing.expectEqual(Choice.wait, classify(.{ .dist = boots, .bearing = flank, .scale = k.scale, .fallReady = true, .slamReady = true, .hopReady = true, .cursor = 0, .ready = &cold }).what);
    var noFall = ready;
    noFall[SWAT_I] = false;
    try std.testing.expectEqual(Choice.wait, classify(.{ .dist = boots, .bearing = FLANK_BEARING + 5.0, .scale = k.scale, .slamReady = true, .hopReady = true, .cursor = 0, .ready = &noFall }).what);
    try std.testing.expectEqual(Choice.fall, classify(.{ .dist = boots, .bearing = FLANK_BEARING + 10.0, .scale = k.scale, .fallReady = true, .slamReady = true, .hopReady = true, .cursor = 0, .ready = &ready }).what);
    try std.testing.expect(FLANK_BEARING + 10.0 >= 180.0 - FALL_SECTOR);
    try std.testing.expectEqual(Choice.slam, classify(.{ .dist = boots, .bearing = 0, .scale = k.scale, .slamReady = true, .cursor = 2, .ready = &ready }).what);
    const mid = mid0;
    try std.testing.expect(classify(.{ .dist = mid, .bearing = 34.0, .scale = k.scale, .fallReady = true, .cursor = 0, .ready = &ready }).what == .strike);
    try std.testing.expect(OVERHEAD.bearing > 34.0 and THRUST.bearing > 34.0);
    try std.testing.expect(BASH.bearing < 34.0);
    for (MOVES) |a| try std.testing.expect(a.bearing <= FLANK_BEARING);
    {
        var one = [_]bool{ false, false, false, false, false, false };
        one[SWEEP_I] = true;
        try std.testing.expectEqual(@as(usize, SWEEP_I), classify(.{ .dist = mid, .bearing = 0, .scale = k.scale, .cursor = 1, .ready = &one }).mv);
    }
    const long = (triggerR(SWEEP, k.scale) + thrustBandR(k.scale)) * 0.5;
    try std.testing.expectEqual(@as(usize, THRUST_I), classify(.{ .dist = long, .bearing = 0, .scale = k.scale, .fallReady = true, .slamReady = true, .chargeReady = true, .hopReady = true, .cursor = 0, .ready = &ready }).mv);
    try std.testing.expect(thrustBandR(k.scale) > triggerR(SWEEP, k.scale));
    try std.testing.expectEqual(Choice.wait, classify(.{ .dist = boots, .bearing = 0, .scale = k.scale, .cursor = 0, .ready = &cold }).what);
    try std.testing.expectEqual(Choice.approach, classify(.{ .dist = thrustBandR(k.scale) + 4.0, .bearing = 0, .scale = k.scale, .fallReady = true, .cursor = 0, .ready = &ready }).what);
    try std.testing.expectEqual(Choice.hold, classify(.{ .dist = AGGRO_R + 1.0, .bearing = 0, .scale = k.scale, .fallReady = true, .slamReady = true, .chargeReady = true, .hopReady = true, .circling = true, .pressed = true, .cursor = 0, .ready = &ready }).what);
    try std.testing.expectEqual(Choice.charge, classify(.{ .dist = CHARGE.far + 3.0, .bearing = 0, .scale = k.scale, .fallReady = true, .chargeReady = true, .cursor = 0, .ready = &ready }).what);
    try std.testing.expectEqual(Choice.strike, classify(.{ .dist = boots, .bearing = 0, .scale = k.scale, .fallReady = true, .chargeReady = true, .cursor = 0, .ready = &ready }).what);
}

test "THE WINDOW IS AN INSTANT BEFORE THE HIT, on all five strokes — and the FALL, SLAM, CHARGE and HOP have none" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const windOf = [_]State{ .sweepwind, .overwind, .thrustwind, .bashwind, .chainwind, .swatwind };
    const strikeOf = [_]State{ .sweep, .over, .thrust, .bash, .sweep2, .swat };
    for (MOVES, 0..) |a, mv| {
        if (mv == SWAT_I) continue;
        const impact = a.strikeDur * a.impactK;
        try std.testing.expect(PARRY_LEAD < a.windDur * 0.4);
        const step = 1.0 / 600.0;
        var open: f32 = -1;
        var shut: f32 = -1;
        var elapsed: f32 = 0;
        k.atk = mv;
        k.windHold = 0;
        while (elapsed <= a.windDur + impact) : (elapsed += step) {
            if (elapsed > a.windDur) {
                k.state = strikeOf[mv];
                k.t = elapsed - a.windDur;
            } else {
                k.state = windOf[mv];
                k.t = elapsed;
            }
            if (k.parryable() != null) {
                if (open < 0) open = elapsed;
                shut = elapsed;
            }
        }
        try std.testing.expect(open > 0);
        try std.testing.expectApproxEqAbs(a.windDur + impact, shut, 2.0 * step);
        try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);
    }
    for ([_]State{ .fallwind, .fall, .downed, .rollover, .rise, .slamwind, .slam, .chargewind, .charge, .brake, .hop, .stepturn, .swatwind, .swat, .idle, .approach, .recover, .stunlight, .stunheavy, .dead }) |s| {
        k.state = s;
        k.t = 0;
        try std.testing.expect(k.parryable() == null);
        k.t = 0.2;
        try std.testing.expect(k.parryable() == null);
    }
}

test "EACH STROKE'S DECLARED REACH IS WHAT THE KIT ACTUALLY ARRIVES AT — ON THE LINE HE IS FACING, WHILE LIVE" {
    // `reachOut` is the AI's trigger radius AND the parry window's reach, so it may never promise less than
    // the blow delivers, nor much more. **MEASURED DOWN HIS FACING**, not at any bearing: the gather aims him
    // square onto the man, so how far the kit flies out on a flank is not a distance anyone stands at. **AND
    // THROUGH THE REAL UPDATE**: the springs lag the keyed pose by a few frames, so a keyed replay puts the
    // swat's crossing before its own impact frame and reads a third of its reach.
    const dt = 1.0 / 240.0;
    const rows = [_]struct { mv: usize, shield: bool }{
        .{ .mv = SWEEP_I, .shield = false },
        .{ .mv = OVER_I, .shield = false },
        .{ .mv = THRUST_I, .shield = false },
        .{ .mv = BASH_I, .shield = false },
        .{ .mv = SWEEP2_I, .shield = false },
        .{ .mv = SWAT_I, .shield = false },
        .{ .mv = SWAT_I, .shield = true },
    };
    var wrong: usize = 0;
    for (rows) |row| {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
        k.atk = row.mv;
        k.opener = row.mv;
        k.swatShield = row.shield;
        k.enter(windFor(row.mv));
        k.windHold = 0;
        var anywhere: f32 = 0;
        var front: f32 = 0;
        var guard: usize = 0;
        while (guard < 4000) : (guard += 1) {
            _ = k.update(dt, v3(0, 0, 40.0), 400.0, .{});
            if (k.strung != 0) break;
            switch (k.state) {
                .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind, .swatwind, .sweep, .sweep2, .over, .thrust, .bash, .swat => {},
                else => break,
            }
            if (!k.live) continue;
            const door = k.doorSwings();
            const lane = foe.hurtReach(if (door) SH_RAM_HALF else SW_HALF_W, k.scale);
            const seg = if (door) k.shieldHere() else k.wpnHere();
            const f = k.fdir();
            var i: usize = 0;
            while (i <= 8) : (i += 1) {
                const p = mathx.lerpV(seg[0], seg[1], @as(f32, @floatFromInt(i)) / 8.0);
                anywhere = mathx.maxF(anywhere, mathx.distXZ(k.pos, p));
                const fw = (p.x - k.pos.x) * f.x + (p.z - k.pos.z) * f.z;
                const lt = @abs((p.x - k.pos.x) * f.z - (p.z - k.pos.z) * f.x);
                if (lt <= lane) front = mathx.maxF(front, fw);
            }
        }
        const declared = (if (row.shield) SWAT_SHIELD_REACH_OUT else MOVES[row.mv].reachOut) * k.scale;
        std.debug.print("\n  {s}{s}: declared {d:.2} m, kit arrives {d:.2} m down his facing ({d:.2} m at its widest)\n", .{ moveName(row.mv), if (row.shield) "(door)" else "", declared, front, anywhere });
        if (declared < front - 0.05 or declared > front + 0.65) wrong += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), wrong);
}

fn moveName(mv: usize) []const u8 {
    return switch (mv) {
        SWEEP_I => "sweep ",
        OVER_I => "over  ",
        THRUST_I => "thrust",
        BASH_I => "bash  ",
        SWAT_I => "swat  ",
        else => "sweep2",
    };
}

fn kitGap(was: [2]rl.Vector3, now: [2]rl.Vector3, hero: rl.Vector3) struct { gap: f32, xz: f32, overY: f32 } {
    const lo = v3(hero.x, hero.y + foe.HERO_LOW, hero.z);
    const hi = v3(hero.x, hero.y + foe.HERO_HIGH, hero.z);
    var best: f32 = 1e9;
    var bestXZ: f32 = 1e9;
    var overY: f32 = 1e9;
    var si: usize = 0;
    while (si <= 3) : (si += 1) {
        const sk = @as(f32, @floatFromInt(si)) / 3.0;
        const a0 = mathx.lerpV(was[0], now[0], sk);
        const a1 = mathx.lerpV(was[1], now[1], sk);
        var pi: usize = 0;
        while (pi <= 8) : (pi += 1) {
            const p = mathx.lerpV(a0, a1, @as(f32, @floatFromInt(pi)) / 8.0);
            const d = mathx.lenV(mathx.subV(p, mathx.closestOnSegV(p, lo, hi)));
            const dxz = mathx.distXZ(p, hero);
            if (d < best) best = d;
            if (dxz < bestXZ) bestXZ = dxz;
            // The lowest the kit came while OVER the man — the height of the whiff.
            if (dxz < 1.0 and p.y < overY) overY = p.y;
        }
    }
    return .{ .gap = best, .xz = bestXZ, .overY = overY };
}

/// Nearest approach of the blade to the door's face this frame — the door sampled across its arc and height, the blade along its length.
const DoorGap = struct { gap: f32, door: rl.Vector3, blade: rl.Vector3, along: f32 };
fn bladeDoorGap(k: *const Knight) DoorGap {
    const seg = k.wpnHere();
    var best = DoorGap{ .gap = 1e9, .door = mathx.zero3, .blade = mathx.zero3, .along = 0 };
    const arcs = [_]f32{ -SH_ARC_R, -SH_ARC_R * 0.5, 0, SH_ARC_L * 0.5, SH_ARC_L };
    for (arcs) |a| {
        var yi: usize = 0;
        while (yi <= 6) : (yi += 1) {
            const y = lerpF(-SH_BOT, SH_TOP, @as(f32, @floatFromInt(yi)) / 6.0);
            const d = rl.math.vector3Transform(arcAt(a, y, 0), k.shXf);
            var bi: usize = 0;
            while (bi <= 8) : (bi += 1) {
                const u = @as(f32, @floatFromInt(bi)) / 8.0;
                const p = mathx.lerpV(seg[0], seg[1], u);
                const g = mathx.lenV(mathx.subV(p, d));
                if (g < best.gap) best = .{ .gap = g, .door = d, .blade = p, .along = u };
            }
        }
    }
    return best;
}

/// The door's leading-face normal in the world — what the plank is pointed at.
fn doorNormal(k: *const Knight) rl.Vector3 {
    const o = rl.math.vector3Transform(mathx.zero3, k.shXf);
    const n = rl.math.vector3Transform(v3(0, 0, 1), k.shXf);
    const d = mathx.subV(n, o);
    return mathx.scaleV(d, 1.0 / mathx.lenV(d));
}

test "THE DOOR FACES WHAT IT MEETS — forward on guard and at the ram, down when it slams, and it never leaves the arm" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.setCarry(1.0);
    k.seatDoor();
    k.pose();
    const guard = doorNormal(&k);
    std.debug.print("\n  door normal on guard: ({d:.2}, {d:.2}, {d:.2})\n", .{ guard.x, guard.y, guard.z });
    try std.testing.expect(guard.z > 0.9);

    const dt = 1.0 / 120.0;
    var b = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    b.debugBash();
    var atRam = mathx.zero3;
    var worstGap: f32 = 0;
    while (b.state == .bashwind or b.state == .bash) {
        _ = b.update(dt, v3(0, 0, 40), 400, .{});
        if (b.state == .bash and b.t >= BASH.strikeDur * BASH.impactK and atRam.z == 0) atRam = doorNormal(&b);
        const fist = rl.math.vector3Transform(v3(0, FIST_Y, FIST_Z), b.xf[WRL]);
        const hub = rl.math.vector3Transform(mathx.zero3, b.shXf);
        worstGap = mathx.maxF(worstGap, mathx.lenV(mathx.subV(hub, fist)));
    }
    std.debug.print("  door normal at the ram: ({d:.2}, {d:.2}, {d:.2}); hub never further than {d:.2} m from the fist\n", .{ atRam.x, atRam.y, atRam.z, worstGap });

    var s = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.debugSlam();
    var atSlam = mathx.zero3;
    while (s.state == .slamwind or s.state == .slam) {
        _ = s.update(dt, v3(0, 0, 40), 400, .{});
        if (s.state == .slam and s.t >= SLAM.strikeDur * SLAM.impactK and atSlam.y == 0) atSlam = doorNormal(&s);
    }
    std.debug.print("  door normal at the slam: ({d:.2}, {d:.2}, {d:.2})\n", .{ atSlam.x, atSlam.y, atSlam.z });

    try std.testing.expect(atRam.z > 0.8);
    try std.testing.expect(worstGap < 1.1);
    try std.testing.expect(atSlam.y < -0.8);
}

test "THE SWORD DOES NOT PASS THROUGH THE DOOR — a forward stroke carries the shield aside" {
    // Owner: "the sword is going thru the shield... weird". Measured through the real update, wind to recover.
    const dt = 1.0 / 120.0;
    const clear = SH_THICK * SCALE + foe.hurtReach(SW_HALF_W, SCALE) - foe.HERO_REACH + 0.10;
    var fouls: usize = 0;
    for ([_]usize{ SWEEP_I, SWEEP2_I, OVER_I, THRUST_I, SWAT_I }) |mv| {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.31);
        k.atk = mv;
        k.opener = mv;
        k.swatShield = false;
        if (mv == SWEEP2_I) {
            // The backhand only ever follows the forehand: start it from the sweep's End Pose with the door already out.
            k.atk = SWEEP_I;
            k.state = .sweep;
            k.setStrike(1.0);
            k.springs.seat(k.chanGet());
            k.atk = SWEEP2_I;
            k.strung = 1;
        }
        k.enter(windFor(mv));
        // …and the DOOR is inherited too, not started from a guard he was never in.
        k.seatDoor();
        k.windHold = 0;
        var worst = DoorGap{ .gap = 1e9, .door = mathx.zero3, .blade = mathx.zero3, .along = 0 };
        var worstAt: State = .idle;
        var worstT: f32 = 0;
        var hub = mathx.zero3;
        var guard: usize = 0;
        while (guard < 4000) : (guard += 1) {
            _ = k.update(dt, v3(0, 0, 40.0), 400.0, .{});
            if (k.state == .idle) break;
            const g = bladeDoorGap(&k);
            if (g.gap < worst.gap) {
                worst = g;
                worstAt = k.state;
                worstT = k.t;
                hub = rl.math.vector3Transform(mathx.zero3, k.shXf);
            }
        }
        std.debug.print("\n  {s}: blade comes within {d:.2} m of the door (in {s} at {d:.2} s; clearance {d:.2}) — door point x{d:.2} y{d:.2} z{d:.2}, blade {d:.0}% along at x{d:.2} y{d:.2} z{d:.2}; hub now x{d:.2} y{d:.2} z{d:.2}\n", .{ moveName(mv), worst.gap, @tagName(worstAt), worstT, clear, worst.door.x, worst.door.y, worst.door.z, worst.along * 100, worst.blade.x, worst.blade.y, worst.blade.z, hub.x, hub.y, hub.z });
        if (worst.gap < clear) fouls += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), fouls);
}

test "THE SWORD IS SWUNG AT THE MAN WHERE HE STANDS — thrown for real, every stroke lands anywhere in its band" {
    // The dip test above only says the kit reaches the height band SOMEWHERE in the stroke. This one says it
    // does so AT THE STAND: thrown through the real update — the gather aims, the strike tracks and steps — a
    // stroke that clears a 1.8 m man's crown at his own distance is a whiff over his head, however wide it swung.
    const dt = 1.0 / 120.0;
    var misses: usize = 0;
    const rows = [_]struct { mv: usize, shield: bool }{
        .{ .mv = SWEEP_I, .shield = false },
        .{ .mv = OVER_I, .shield = false },
        .{ .mv = THRUST_I, .shield = false },
        .{ .mv = BASH_I, .shield = false },
        .{ .mv = SWEEP2_I, .shield = false },
        .{ .mv = SWAT_I, .shield = false },
        .{ .mv = SWAT_I, .shield = true },
    };
    // THE BREAD-AND-BUTTER HAS NO DEAD ZONE: a man at his boots is hit by a sweep, a flick and the door.
    for ([_]usize{ SWEEP_I, SWEEP2_I, SWAT_I, BASH_I }) |mv| try std.testing.expectEqual(@as(f32, 0), MOVES[mv].reachIn);
    for (rows) |row| {
        const mv = row.mv;
        // Out to `bandR`, where the AI actually picks it — the lunge's extra reach is only real if the kit is still out there at the end of the stroke.
        const near = mathx.maxF(foe.closestApproach(BODY_R * SCALE) + 0.2, nearR(MOVES[mv], SCALE) + 0.1);
        const far = strokeBandR(mv, row.shield, SCALE) * 0.97;
        for ([_]f32{ 0.0, 0.34, 0.67, 1.0 }) |u| {
            const stand = lerpF(near, far, u);
            var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.31);
            var hero = v3(0, 0, stand);
            k.atk = mv;
            k.opener = mv;
            k.swatShield = row.shield;
            k.shoving = false;
            k.enter(windFor(mv));
            k.windHold = 0;
            var lowGap: f32 = 1e9;
            var lowXZ: f32 = 1e9;
            var overY: f32 = 1e9;
            var relAt: f32 = 0;
            var hit = false;
            var guard: usize = 0;
            const apart = foe.closestApproach(k.bodyR());
            while (guard < 4000) : (guard += 1) {
                _ = k.update(dt, hero, 400.0, .{});
                // The lunge SHOVES a man it runs into, as `env.resolveActor` does in the game — bodies do not overlap.
                if (mathx.distXZ(k.pos, hero) < apart) {
                    const out = mathx.dirXZ(k.pos, hero);
                    hero = v3(k.pos.x + out.x * apart, 0, k.pos.z + out.z * apart);
                }
                if (k.strung != 0) break;
                if (k.heroHit != null) {
                    hit = true;
                    break;
                }
                if (k.live) {
                    const door = k.doorSwings();
                    const g = kitGap(if (door) k.shWas else k.wpnWas, if (door) k.shieldHere() else k.wpnHere(), hero);
                    if (g.gap < lowGap) {
                        lowGap = g.gap;
                        relAt = mathx.distXZ(k.pos, hero);
                    }
                    lowXZ = mathx.minF(lowXZ, g.xz);
                    overY = mathx.minF(overY, g.overY);
                }
                switch (k.state) {
                    .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind, .swatwind, .sweep, .sweep2, .over, .thrust, .bash, .swat => {},
                    else => break,
                }
            }
            if (!hit) {
                misses += 1;
                std.debug.print("\n  {s}{s} at {d:.2} m: MISSED — gap {d:.2} m (man {d:.2} m off him then), nearest XZ pass {d:.2} m, lowest over him {d:.2} m up\n", .{ moveName(mv), if (row.shield) "(door)" else "", stand, lowGap, relAt, lowXZ, overY });
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), misses);
}

test "EVERY STROKE COMES DOWN INTO THE HERO'S OWN HEIGHT BAND — a giant's kit swung at a giant's height MISSES" {
    // Every live stroke must dip to somewhere a 1.8 m body actually occupies: authored in its own units a
    // five-metre creature sweeps its kit through ITS chest, 2.5 m over the head of the man it swings at.
    const dt = 1.0 / 120.0;
    const strikeOf = [_]State{ .sweep, .over, .thrust, .bash, .sweep2, .swat };
    for (MOVES, 0..) |a, mv| {
        var k = Knight.spawn(mathx.ground(0, 0), 0, 1.0, 0.33);
        k.windHold = 0;
        k.atk = mv;
        k.swatShield = false;
        k.state = strikeOf[mv];
        k.t = 0;
        var lowest: f32 = 1e9;
        while (k.t <= a.strikeDur) : (k.t += dt) {
            k.setStrike(foe.swingCurve(mathx.clampF(k.t / a.strikeDur, 0, 1)));
            k.pose();
            const seg = if (mv == BASH_I) k.shieldSeg() else k.weaponSeg();
            for (seg) |p| lowest = mathx.minF(lowest, p.y - k.pos.y);
        }
        std.debug.print("\n  {s}: kit dips to {d:.2} m (hero crown {d:.2}, band top {d:.2})\n", .{ moveName(mv), lowest, heromod.H, foe.HERO_HIGH });
        try std.testing.expect(lowest < foe.HERO_HIGH);
    }
}

test "EVERY BONE GETS A MATRIX IN EVERY STATE, and the body really does go over and come back up" {
    var k = Knight.spawn(mathx.ground(3, -2), mathx.radians(40), 1.0, 0.41);
    const crown = k.topWorld().y - k.pos.y;
    const hero = v3(3.0 - mathx.sinf(mathx.radians(40)) * 3.0, 0, -2.0 - mathx.cosf(mathx.radians(40)) * 3.0);
    k.debugFall();
    var t: f32 = 0;
    var lowest = crown;
    var wasDown = false;
    while (t < FALL_WIND_DUR + FALL_DUR + DOWN_DUR + ROLL_DUR + RISE_DUR + 0.3) : (t += 1.0 / 60.0) {
        _ = k.update(1.0 / 60.0, hero, 200.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
        const h = k.topWorld().y - k.pos.y;
        lowest = mathx.minF(lowest, h);
        if (k.state == .downed) wasDown = true;
    }
    try std.testing.expect(wasDown);
    try std.testing.expect(lowest < crown * 0.35);
    try std.testing.expect(lowest > -0.6);
    try std.testing.expectApproxEqAbs(crown, k.topWorld().y - k.pos.y, crown * 0.12);
    try std.testing.expect(k.fallCd > 0);
}

test "THE PUNISH WINDOW IS REAL — flat on his back, the mark and the hurt sphere come down with him" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const standMark = k.lockPoint().y;
    const standHurt = k.centerWorld().y;
    k.state = .downed;
    k.t = DOWN_DUR * 0.5;
    k.easeFloored(1.0);
    k.pose();
    try std.testing.expect(k.lockPoint().y < standMark * 0.4);
    try std.testing.expect(k.centerWorld().y < standHurt * 0.4);
    try std.testing.expect(k.centerWorld().z < -k.bodyR() * 0.5);
    for ([_]State{ .fall, .downed, .rollover, .rise }) |s| {
        k.state = s;
        try std.testing.expect(!k.guardUp());
    }
    k.state = .slam;
    try std.testing.expect(!k.guardUp());
    for ([_]struct { s: State, mv: usize }{
        .{ .s = .sweep, .mv = SWEEP_I },
        .{ .s = .sweep2, .mv = SWEEP2_I },
        .{ .s = .over, .mv = OVER_I },
    }) |c| {
        k.state = c.s;
        k.atk = c.mv;
        k.t = 0;
        k.seatDoor();
        try std.testing.expect(k.guardUp());
        k.t = k.move().strikeDur;
        k.seatDoor();
        try std.testing.expect(!k.guardUp());
    }
    for ([_]State{ .bash, .charge, .hop }) |s| {
        k.state = s;
        for ([_]f32{ 0, 0.12, 0.24 }) |t| {
            k.t = t;
            k.seatDoor();
            try std.testing.expect(k.guardUp());
        }
    }
    k.state = .thrust;
    k.atk = THRUST_I;
    k.t = THRUST.strikeDur;
    k.seatDoor();
    try std.testing.expect(!k.guardUp());
}

test "THE DOOR IS SEEN TO LEAVE — the picture of the guard cannot disagree with the guard" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    for ([_]State{ .idle, .approach, .hop, .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind, .bash, .chargewind, .charge, .brake, .fallwind }) |s| {
        k.state = s;
        for ([_]f32{ 0, 0.2 }) |t| {
            k.t = t;
            // The door channels are CHASED now (`tickDoor`), so a poked clock is seated — in play each frame
            // inherits the last. What is pinned is still the SCHEDULE and the flag agreeing.
            k.seatDoor();
            try std.testing.expect(k.guardUp());
            try std.testing.expectApproxEqAbs(@as(f32, 0), k.slamLift(), 1e-6);
            try std.testing.expectApproxEqAbs(@as(f32, 0), k.swipeOpen(), 1e-6);
        }
    }
    for ([_]struct { s: State, mv: usize }{
        .{ .s = .sweep, .mv = SWEEP_I },
        .{ .s = .sweep2, .mv = SWEEP2_I },
        .{ .s = .over, .mv = OVER_I },
    }) |c| {
        k.state = c.s;
        k.atk = c.mv;
        const a = k.move();
        k.t = 0;
        k.seatDoor();
        // **THE PICTURE LEADS THE FLAG AND MAY NEVER TRAIL IT.** The plank is already `SWIPE_LEAD_TO` of the way
        // aside when the blade starts — hauled through the GATHER, not snapped on the impact frame — and the
        // guard is still UP, because the lead sits under `guardUp`'s own 0.5.
        try std.testing.expect(k.swipeOpen() > 0.3 and k.guardUp());
        k.t = a.strikeDur * a.impactK;
        k.seatDoor();
        try std.testing.expect(k.swipeOpen() > 0.5);
        k.t = a.strikeDur;
        k.seatDoor();
        try std.testing.expect(k.swipeOpen() > 0.99 and !k.guardUp());
        k.state = .recover;
        k.blow = switch (c.mv) {
            SWEEP_I => .sweep,
            SWEEP2_I => .sweep2,
            else => .over,
        };
        k.t = 0;
        k.seatDoor();
        try std.testing.expect(k.swipeOpen() > 0.99 and !k.guardUp());
        k.t = k.recoverDur();
        k.seatDoor();
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.swipeOpen(), 1e-6);
        try std.testing.expect(k.guardUp());
    }
    k.state = .slamwind;
    k.t = SLAM.windDur * 0.6;
    k.seatDoor();
    try std.testing.expect(!k.guardUp());
    try std.testing.expect(k.slamLift() > 0.5);
    k.state = .slam;
    k.t = 0;
    k.seatDoor();
    try std.testing.expect(!k.guardUp());
    try std.testing.expectApproxEqAbs(@as(f32, 1), k.slamLift(), 1e-6);
    k.state = .recover;
    k.t = 0;
    k.blow = .bash;
    k.seatDoor();
    try std.testing.expect(k.guardUp() and k.slamLift() == 0);
    k.blow = .slam;
    k.seatDoor();
    try std.testing.expect(!k.guardUp());
    try std.testing.expect(k.slamLift() > 0.9);
    k.t = SLAM.recoverDur;
    k.seatDoor();
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.slamLift(), 1e-6);
    for ([_]State{ .fall, .downed, .rollover, .rise }) |s| {
        k.state = s;
        k.t = 0.3;
        k.seatDoor();
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.slamLift(), 1e-6);
    }
}

test "NO ATTACK COMES OUT OF NOWHERE, and the fall's tell is the longest thing he does" {
    for (MOVES) |a| try std.testing.expect(a.windDur >= foe.TELL_MIN);
    try std.testing.expect(SLAM.windDur >= foe.TELL_MIN);
    try std.testing.expect(CHARGE.windDur >= foe.TELL_MIN);
    try std.testing.expect(FALL_WIND_DUR >= foe.TELL_MIN);
    for (MOVES) |a| try std.testing.expect(FALL_WIND_DUR > a.windDur);
    try std.testing.expect(FALL_WIND_DUR > SLAM.windDur);
    try std.testing.expect(FALL_WIND_DUR > CHARGE.windDur);
    const opening = DOWN_DUR + ROLL_DUR + RISE_DUR;
    for (MOVES) |a| try std.testing.expect(opening > a.recoverDur * 2.0);
    try std.testing.expect(opening > SLAM.recoverDur * 1.8);
    try std.testing.expect(opening > CHARGE.brakeDur + CHARGE.recoverDur);
    try std.testing.expect(opening > combat.FOE_HEAVY_STUN_DUR);
    try std.testing.expect(FALL_CD > opening);
    for (MOVES) |a| try std.testing.expect(FALL_HIT.poise > a.hit.poise and FALL_HIT.stance > a.hit.stance);
    try std.testing.expect(FALL_HIT.poise > SLAM_HIT.poise and FALL_HIT.stance > SLAM_HIT.stance);
    try std.testing.expect(FALL_HIT.poise > CHARGE_HIT.poise and FALL_HIT.stance > CHARGE_HIT.stance);
    for ([_]usize{ SWEEP_I, OVER_I, BASH_I }) |i| try std.testing.expect(THRUST.cd < MOVES[i].cd);
    try std.testing.expect(THRUST.cd < SLAM.cd and THRUST.cd < CHARGE.cd and THRUST.cd < FALL_CD);
}

test "HE IS NOT DULL — a man walking circles round him is under attack, not watching one" {
    // The complaint this pins (owner: the ogre is harder, the knight is dull). A hero strolling a ring round
    // him used to be safe: he could not turn fast enough to face a walk, so most of the fight was him WAITING.
    // Measured as the share of the fight he spends committed to something, and the longest quiet gap in it.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.leash.provoke();
    const dt = 1.0 / 60.0;
    const ring = triggerR(SWEEP, k.scale) * 0.72;
    var ang: f32 = 0;
    var t: f32 = 0;
    var busy: usize = 0;
    var frames: usize = 0;
    var quiet: f32 = 0;
    var worstQuiet: f32 = 0;
    var strokes: usize = 0;
    var was = k.state;
    while (t < 45.0) : (t += dt) {
        ang += (heromod.WALK_SPEED / ring) * dt;
        const hero = v3(mathx.sinf(ang) * ring, 0, mathx.cosf(ang) * ring);
        // `game.markSight` stamps this every frame in the live loop; without it he goes blind at
        // `foe.SIGHT_MEMORY` and the measurement is of a creature that has lost you, not a dull one.
        k.leash.noteSeen();
        _ = k.update(dt, hero, 400.0, .{});
        frames += 1;
        // A step-turn is a MOVE — a planted pivot he chose — not waiting; idle turning is gone and this is what replaced it.
        const idle = switch (k.state) {
            .idle, .approach => true,
            else => false,
        };
        if (idle) {
            quiet += dt;
            worstQuiet = mathx.maxF(worstQuiet, quiet);
        } else {
            quiet = 0;
            busy += 1;
        }
        if (k.state != was) {
            switch (k.state) {
                .sweep, .sweep2, .over, .thrust, .bash, .swat, .slam, .charge, .fall => strokes += 1,
                else => {},
            }
            was = k.state;
        }
    }
    const share = @as(f32, @floatFromInt(busy)) / @as(f32, @floatFromInt(frames));
    std.debug.print("\n  45 s of a walked circle: {d} blows thrown, {d:.0}% of it committed, longest lull {d:.2} s\n", .{ strokes, share * 100.0, worstQuiet });
    // MEASURED: 21 blows, 93% committed, worst lull 0.73 s. It was 30 blows at 91% with a 2.23 s lull when he
    // turned on the spot and threw strokes that could not reach; now the time between blows is hops, step-turns
    // and the fall's aftermath — MOVES, not waiting — and the count is lower because every blow is thrown from a
    // stand it can land on. The lull is held to about one reposition: a big recovery plus a step-turn is 2.5 s.
    try std.testing.expect(strokes >= 18);
    try std.testing.expect(share > 0.85);
    try std.testing.expect(worstQuiet < SLAM.recoverDur + STEPTURN.windDur + STEPTURN.turnDur + STEPTURN.settleDur);
}

test "HE TRACKS LIKE THE OGRE — the window is the COMMIT, not the flank" {
    // **THE LAW THIS REPLACES**: he was slower than a WALKING man (0.68 against 0.80), so the flank was free to
    // anybody holding a direction and the fight was a stroll in circles (owner: the ogre is harder, and the knight is dull).
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const r = k.bodyR() + foe.HERO_R;
    const sprintRate = heromod.SPRINT_SPEED / r;
    std.debug.print("\n  knight turns {d:.2} rad/s, ogre {d:.2}; a sprint round the knight carries {d:.2}\n", .{ TURN_RATE, ogremod.TURN_RATE, sprintRate });
    // IN THE OGRE'S CLASS, and under it: he is armour, not a beast.
    try std.testing.expect(TURN_RATE > sprintRate);
    try std.testing.expect(TURN_RATE < ogremod.TURN_RATE);
    for (MOVES) |a| {
        if (a.weight != .light) try std.testing.expect(a.track < TURN_RATE);
    }
    // The QUICK strokes hold you the way the ogre's swipe does, and the heavies plainly do not.
    for (MOVES) |a| {
        if (a.weight == .light) try std.testing.expect(a.track > sprintRate);
    }
    try std.testing.expect(MOVES[SWAT_I].track <= ogremod.SWIPE_TURN);
    for (MOVES) |a| {
        if (a.weight == .heavy) try std.testing.expect(a.track * 2.0 < MOVES[SWAT_I].track);
    }
    try std.testing.expect(SWING_TURN < TURN_RATE);
    try std.testing.expect(MOVES[SWAT_I].track > TURN_RATE and MOVES[THRUST_I].track > TURN_RATE);
    try std.testing.expectEqual(@as(f32, 0), MOVES[OVER_I].track);
    try std.testing.expect(FALL_AIM < TURN_RATE);

    // The LATERAL miss at the impact frame against the kit's own half-width. `kitHalf` is the angle the RAM
    // itself subtends at the range it arrives, never the wrap's whole chord.
    const kitHalf = std.math.asin(SH_RAM_HALF / BASH.reachOut);
    const commit = BASH.windDur + BASH.strikeDur * BASH.impactK;
    const walkRate = heromod.WALK_SPEED / r;
    const drift = (walkRate - BASH.track) * commit;
    std.debug.print("  bash commit {d:.2} s: he GAINS {d:.0} deg on a walking man across it; ram subtends {d:.0}\n", .{
        commit, -mathx.degrees(drift), mathx.degrees(kitHalf),
    });
    // The drift a commit sheds may not by itself carry the door off a squared-up man. It is NEGATIVE now:
    // the bash GAINS bearing across its own commit rather than shedding it.
    try std.testing.expect(drift < kitHalf);
    try std.testing.expect(BASH.track > sprintRate);
    try std.testing.expect(mathx.radians(SWING_BEARING) <= kitHalf);

    // THE SWEEP IS NOT HELD TO THAT, AND THAT IS THE DESIGN — pinned so the pair cannot become one move.
    try std.testing.expect(SWEEP.windDur > BASH.windDur * 1.4);
}

test "THE SLAM IS OUTRUN, NOT OUT-TRADED — a run clears the crater's disc and a walk does not" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const tell = SLAM.windDur + SLAM.strikeDur * SLAM.impactK;
    const ring = foe.hurtReach(SLAM.r, k.scale);
    std.debug.print("\n  slam: disc {d:.2} m, tell {d:.2} s -> run reaches {d:.2}, walk {d:.2}\n", .{
        ring, tell, heromod.RUN_SPEED * tell, heromod.WALK_SPEED * tell,
    });
    try std.testing.expect(heromod.RUN_SPEED * tell > ring + 0.4);
    try std.testing.expect(heromod.WALK_SPEED * tell < ring - 0.1);
    var s = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const mark = s.slamMark();
    s.heroHit = null;
    s.trySlam(v3(mark.x, 0, mark.z + ring - 0.2));
    try std.testing.expect(s.heroHit != null);
    s.heroHit = null;
    s.trySlam(v3(0, 0, -1.0));
    try std.testing.expect(s.heroHit != null);
    s.heroHit = null;
    s.trySlam(v3(mark.x, 0, mark.z + ring + 0.3));
    try std.testing.expect(s.heroHit == null);
}

test "THE CHARGE ANSWERS STAYING AWAY, AND THE LINE IS COMMITTED AT THE LAUNCH" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.31);
    k.leash.provoke();
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var launched = false;
    var hero = v3(0, 0, 13.0);
    while (t < 14.0 and !launched) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        const away = mathx.dirXZ(k.pos, hero);
        const norm = if (mathx.lenXZ(away) > 1e-3) away else v3(0, 0, 1);
        hero = v3(k.pos.x + norm.x * 13.0, 0, k.pos.z + norm.z * 13.0);
        if (k.state == .chargewind) launched = true;
    }
    try std.testing.expect(launched);
    while (k.state == .chargewind) : (t += dt) _ = k.update(dt, hero, 400.0, .{});
    try std.testing.expectEqual(State.charge, k.state);
    const line = k.facing;
    const lenAtLaunch = k.chargeLen;
    var ran: f32 = 0;
    while (k.state == .charge) : (t += dt) {
        const side = v3(k.pos.x - mathx.headingDir(line).z * 8.0, 0, k.pos.z + mathx.headingDir(line).x * 8.0);
        _ = k.update(dt, side, 400.0, .{});
        try std.testing.expectApproxEqAbs(line, k.facing, 1e-4);
        ran = mathx.maxF(ran, k.strokeDone);
    }
    std.debug.print("\n  charge: committed {d:.1} m, ran {d:.1} m, then the skid\n", .{ lenAtLaunch, ran });
    try std.testing.expectApproxEqAbs(lenAtLaunch, ran, 0.30);
    try std.testing.expectEqual(State.brake, k.state);
    while (k.state == .brake or k.state == .recover) : (t += dt) _ = k.update(dt, hero, 400.0, .{});
    try std.testing.expect(k.chargeCd > 0);
    try std.testing.expect(k.farT < CHARGE.patience);
}

test "NO FOLLOW-UP CHAINS AT A MAN WHO IS ALREADY BEHIND HIM" {
    var seed: f32 = 0.05;
    while (seed < 1.0) : (seed += 0.17) {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, seed);
        k.debugSweep();
        const dt = 1.0 / 60.0;
        var t: f32 = 0;
        // **HELD BEHIND HIM, NOT DROPPED BEHIND HIM.** At ogre-class tracking a 1 s gather turns him the whole
        // way round, so a fixed point behind his START is squarely in front by the time the stroke lands —
        // which is the design. The rule being pinned is about the BEARING at the end of the stroke.
        while (t < SWEEP.windDur + SWEEP.strikeDur + 0.1) : (t += dt) {
            _ = k.update(dt, flankOf(&k, 180.0, 6.0), 400.0, .{});
            try std.testing.expect(k.state != .chainwind and k.state != .sweep2);
        }
    }
}

test "THE GUARD COUNTER ANSWERS THE DOOR AND ONLY THE DOOR — and never off a body already committed" {
    var found = false;
    var seed: f32 = 0.03;
    while (seed < 1.0) : (seed += 0.11) {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, seed);
        k.state = .idle;
        k.covered = true;
        const p = v3(0, 2.6, k.hurtRadius() * 0.5);
        k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 10, .poise = 5, .stance = 4 } });
        try std.testing.expectEqual(@as(u32, 1), k.blocks);
        if (k.state == .thrustwind) {
            found = true;
            try std.testing.expect(k.riposteCd > 0);
        } else {
            try std.testing.expectEqual(State.idle, k.state);
        }
    }
    try std.testing.expect(found); // across nine seeds the 60% roll must fire at least once
    var mid = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    mid.debugSweep();
    mid.covered = true;
    const q = v3(0, 2.6, mid.hurtRadius() * 0.5);
    mid.tryHit(.{ .active = true, .r = 0.2, .a = q, .b = q, .a0 = q, .b0 = q, .hit = .{ .dmg = 10, .poise = 5, .stance = 4 } });
    try std.testing.expectEqual(State.sweepwind, mid.state);
}

test "EVERY NEW STATE POSES EVERY BONE — the slam, the hop and the charge drive clean through" {
    var k = Knight.spawn(mathx.ground(2, 1), mathx.radians(30), 1.0, 0.4);
    const hero = mathx.ground(2, 9);
    const dt = 1.0 / 60.0;
    k.debugSlam();
    var t: f32 = 0;
    var ringPeak: usize = 0;
    while (t < SLAM.windDur + SLAM.strikeDur + SLAM.recoverDur + 0.2) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
        var live: usize = 0;
        for (k.parts) |p| {
            if (p.life > 0) live += 1;
        }
        ringPeak = @max(ringPeak, live);
    }
    std.debug.print("\n  slam fx: {d} particles live at the peak\n", .{ringPeak});
    try std.testing.expect(ringPeak >= 30);
    k.debugHop(1.0);
    t = 0;
    const before = k.pos;
    while (t < HOP.windDur + HOP.airDur + HOP.settleDur + 0.1) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
    }
    std.debug.print("  hop: covered {d:.2} m of {d:.2} promised\n", .{ mathx.distXZ(before, k.pos), HOP.dist * k.scale });
    try std.testing.expect(mathx.distXZ(before, k.pos) > HOP.dist * k.scale * 0.7);
    k.debugCharge();
    t = 0;
    var wakePeak: usize = 0;
    while (t < CHARGE.windDur + CHARGE.range / CHARGE.speed + CHARGE.brakeDur + CHARGE.recoverDur + 0.2) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
        if (k.state == .charge) {
            var live: usize = 0;
            for (k.parts) |p| {
                if (p.life > 0) live += 1;
            }
            wakePeak = @max(wakePeak, live);
        }
    }
    std.debug.print("  charge fx: {d} wake particles live at the peak\n", .{wakePeak});
    try std.testing.expect(wakePeak >= 16);
}

test "THE LIT CHARGE LAYS A LANE — spaced by ground covered, behind him, and never in phase one" {
    var cold = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    cold.lit = false;
    cold.debugCharge();
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        _ = cold.update(1.0 / 60.0, v3(0, 0, 18.0), 400.0, .{});
        try std.testing.expect(cold.gasAt == null);
    }

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.lit = true;
    k.debugCharge();
    var at: [16]rl.Vector3 = undefined;
    var n: usize = 0;
    var smallest: f32 = 9;
    t = 0;
    while (t < 4.0) : (t += 1.0 / 60.0) {
        _ = k.update(1.0 / 60.0, v3(0, 0, 18.0), 400.0, .{});
        if (k.state == .brake or k.state == .recover) break;
        if (k.gasAt) |p| {
            if (n < at.len) at[n] = p;
            smallest = mathx.minF(smallest, k.gasScale);
            n += 1;
        }
    }
    std.debug.print("\n  chaos trail: {d} clouds over the charge\n", .{n});
    try std.testing.expect(n >= 3);
    try std.testing.expect(n <= GAS_CAP);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const gap = mathx.distXZ(at[i - 1], at[i]);
        try std.testing.expectApproxEqAbs(CHAOS_TRAIL_EVERY * k.scale, gap, 0.35);
    }
    try std.testing.expect(smallest < 1.0);
    try std.testing.expectApproxEqAbs(CHAOS_TRAIL_SCALE, smallest, 1e-6);
    try std.testing.expect(CHAOS_TRAIL_EVERY > 2.0 * GAS_R * CHAOS_TRAIL_SCALE);
}

test "THE SITUATION ARGUES WITH THE ROTATION — and the same situation always loses the same argument" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const ready = [_]bool{ true, true, true, true, true, true };
    const mid = (triggerR(BASH, k.scale) + triggerR(SWEEP, k.scale)) * 0.5;
    for ([_]usize{ 0, 1, 2, 3, 4 }) |c| {
        const a = classify(.{ .dist = mid, .bearing = 12.0, .scale = k.scale, .pressed = true, .cursor = c, .ready = &ready });
        const b = classify(.{ .dist = mid, .bearing = 12.0, .scale = k.scale, .pressed = true, .cursor = c, .ready = &ready });
        try std.testing.expectEqual(a.mv, b.mv);
    }
    var movedByPress = false;
    var movedByOrbit = false;
    var movedByPhase = false;
    for ([_]f32{ 12.0, -12.0 }) |bear| {
        for ([_]usize{ 0, 1, 2, 3, 4 }) |c| {
            const base = classify(.{ .dist = mid, .bearing = bear, .scale = k.scale, .cursor = c, .ready = &ready });
            const push = classify(.{ .dist = mid, .bearing = bear, .scale = k.scale, .pressed = true, .cursor = c, .ready = &ready });
            const spin = classify(.{ .dist = mid, .bearing = bear, .scale = k.scale, .circling = true, .cursor = c, .ready = &ready });
            const lit = classify(.{ .dist = mid, .bearing = bear, .scale = k.scale, .lit = true, .cursor = c, .ready = &ready });
            if (push.mv != base.mv) movedByPress = true;
            if (spin.mv != base.mv) movedByOrbit = true;
            if (lit.mv != base.mv) movedByPhase = true;
        }
    }
    try std.testing.expect(movedByPress);
    try std.testing.expect(movedByOrbit);
    try std.testing.expect(movedByPhase);
    try std.testing.expect(pressTerm(THRUST_I) > pressTerm(SWEEP_I));
    try std.testing.expect(trackTerm(SWAT_I) > trackTerm(OVER_I));
    try std.testing.expect(litTerm(SWEEP_I) > litTerm(SWAT_I));
    var seen = [_]bool{false} ** MOVES.len;
    for ([_]usize{ 0, 1, 2, 3, 4 }) |c| {
        const dec = weigh(&RANGE_SWORD, .{ .dist = mid, .bearing = 12.0, .scale = k.scale, .cursor = c, .ready = &ready });
        try std.testing.expectEqual(Choice.strike, dec.what);
        seen[dec.mv] = true;
    }
    var kinds: usize = 0;
    for (seen) |x| {
        if (x) kinds += 1;
    }
    try std.testing.expect(kinds >= 2);
}

test "THE CHARGE COMES FROM A STEP OUTSIDE HIS SWORD — not only from across the arena" {
    // 8.5 m is the spacing a fight is actually held at, past the thrust's own band.
    const k0 = Knight.spawn(mathx.zero3, 0, 1.0, 0.31);
    const kite = 8.5;
    try std.testing.expect(kite > thrustBandR(k0.scale));
    try std.testing.expect(kite < 10.5);
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.31);
    k.leash.provoke();
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var hero = v3(0, 0, kite);
    var launched = false;
    while (t < 12.0 and !launched) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        const away = mathx.dirXZ(k.pos, hero);
        const norm = if (mathx.lenXZ(away) > 1e-3) away else v3(0, 0, 1);
        hero = v3(k.pos.x + norm.x * kite, 0, k.pos.z + norm.z * kite);
        if (k.state == .chargewind) launched = true;
    }
    std.debug.print("\n  charge fuse: lit at {d:.1} m after {d:.1} s\n", .{ kite, t });
    try std.testing.expect(launched);
    const half = Knight.chargeDist(0.5);
    std.debug.print("  charge: {d:.1} m in the first half second, hero sprints {d:.1} m\n", .{ half, heromod.SPRINT_SPEED * 0.5 });
    try std.testing.expect(half > heromod.SPRINT_SPEED * 0.5 * 1.6);
    try std.testing.expect(Knight.brakeDist(CHARGE.brakeDur) < 4.2);
}

test "A FELLED STATUE DOES NOT CURL — the death keeps his legs on the ground and puts his head there" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const kneeY = k.rest[KNEEL].y * k.scale;
    k.debugKill();
    var t: f32 = 0;
    var foot: f32 = 0;
    var head: f32 = 1e9;
    var far: f32 = 0;
    while (t <= DEATH_DUR) : (t += 1.0 / 120.0) {
        k.t = t;
        k.easeFloored(1.0);
        k.pose();
        foot = mathx.maxF(foot, mathx.maxF(k.xf[ANKL].m13, k.xf[ANKR].m13));
        if (t > DEATH_DUR * 0.75) {
            head = mathx.minF(head, k.topWorld().y);
            far = mathx.maxF(far, mathx.distXZ(k.pos, k.topWorld()));
        }
    }
    std.debug.print("\n  death: highest boot {d:.2} m (knee sits at {d:.2}), helm settles {d:.2} m up and {d:.2} m out\n", .{ foot, kneeY, head, far });
    try std.testing.expect(foot < kneeY);
    try std.testing.expect(head < kneeY);
    try std.testing.expect(far > 2.5);
}

test "A FLOORED BODY HOLDS THE GROUND IT IS LYING ON — the capsule, not the ring at his boots" {
    const collision = @import("../core/collision.zig");
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.pose();
    try std.testing.expect(k.bodySeg() == null);
    k.state = .downed;
    k.t = DOWN_DUR * 0.5;
    k.easeFloored(1.0);
    k.pose();
    const seg = k.bodySeg().?;
    const len = mathx.distXZ(seg[0], seg[1]);
    const cap = collision.capsule(seg[0].x, seg[0].z, seg[1].x, seg[1].z, k.bodyR());
    const ring = collision.circle(k.pos.x, k.pos.z, k.bodyR());
    var u: f32 = 0.25;
    var walked: f32 = 0;
    while (u <= 1.0) : (u += 0.05) {
        const p = mathx.lerpV(seg[0], seg[1], u);
        try std.testing.expect(collision.blocksPoint(p, foe.HERO_R * 0.5, cap));
        if (!collision.blocksPoint(p, foe.HERO_R * 0.5, ring)) walked = mathx.maxF(walked, mathx.distXZ(k.pos, p));
    }
    std.debug.print("\n  floored: {d:.2} m of body behind a {d:.2} m ring — {d:.2} m of it was walk-through\n", .{ len, k.bodyR(), walked });
    try std.testing.expect(len > 2.5);
    try std.testing.expect(walked > len * 0.5);
    k.state = .idle;
    k.t = 0;
    try std.testing.expect(k.bodySeg() == null);
}

test "A SPENT TRANSFORMATION IS ALWAYS A LIT ONE — staggering him mid-roar may not cost phase two" {
    // `awoken` latches the instant he COMMITS to the awaken; `lit` only lands when the roar finishes 2.7 s
    // later. Anything that took him out of `.awaken` in between left him having spent his one phase change
    // without ever entering phase two — no lit sword, no discs, no chaos clouds, for the rest of the fight.
    std.debug.print("\n  the awaken window is {d:.2} s of state he can be knocked out of\n", .{ AWAKEN.liftDur + AWAKEN.holdDur + AWAKEN.settleDur });

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.leash.provoke();
    k.vit.hp = k.vit.hpMax * AWAKEN.at;
    k.decide(6.0, 0);
    try std.testing.expectEqual(State.awaken, k.state);
    try std.testing.expect(k.awoken and !k.lit);

    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    const far = v3(0, 0, 40.0);
    while (t < AWAKEN.liftDur) : (t += dt) _ = k.update(dt, far, 400.0, .{});
    k.enterStun(.stunheavy);

    try std.testing.expect(k.awoken);
    try std.testing.expect(k.lit);

    // …and he never gets a second one, so a lost one is lost for the whole fight.
    k.vit.hp = k.vit.hpMax * 0.2;
    k.decide(6.0, 0);
    try std.testing.expect(k.state != .awaken);
    try std.testing.expect(k.lit);
}

test "THE ROAR IS NOT INTERRUPTIBLE — a phase change plays in full or it is not a phase change" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.leash.provoke();
    k.vit.hp = k.vit.hpMax * AWAKEN.at;
    k.decide(6.0, 0);
    try std.testing.expectEqual(State.awaken, k.state);
    try std.testing.expect(k.transforming());

    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    const far = v3(0, 0, 40.0);
    while (t < AWAKEN.liftDur + AWAKEN.holdDur) : (t += dt) {
        _ = k.update(dt, far, 400.0, .{});
        try std.testing.expectEqual(State.awaken, k.state);
    }
}

test "HE TRIES TO HIT YOU — the GATHER aims at his full turn, and the COMMIT still does not" {
    // The bug this pins: every wind but the sweep's aimed at 0.45 of his rate, so standing in front was free.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.leash.provoke();
    const dt = 1.0 / 240.0;
    const r = k.bodyR() + foe.HERO_R;
    inline for (.{ .{ State.overwind, OVER_I }, .{ State.thrustwind, THRUST_I }, .{ State.bashwind, BASH_I }, .{ State.swatwind, SWAT_I } }) |row| {
        k.state = row[0];
        k.atk = row[1];
        k.swatShield = false;
        k.windHold = 0;
        k.t = 0;
        k.facing = 0;
        const dur = k.windDur();
        var t: f32 = 0;
        while (t < dur) : (t += dt) {
            _ = k.update(dt, v3(0, 0, r), 400.0, .{});
        }
        // The body is dead ahead, so what is pinned is the rate he is ALLOWED, not the angle he covers — the
        // TOTAL is capped separately (`GATHER_SWEEP_MAX`) and a man out in front never reaches it.
        try std.testing.expect(k.state != row[0] or k.t >= dur - 2.0 * dt);
    }
    for (MOVES) |a| {
        if (a.weight != .light) try std.testing.expect(a.track < TURN_RATE);
    }
    const heroRate = heromod.WALK_SPEED / r;
    std.debug.print("\n  wind aims at {d:.2} rad/s (it was 0.45 of that); a walking man carries {d:.2}\n", .{ TURN_RATE, heroRate });
    try std.testing.expect(TURN_RATE > heroRate);
}

test "THE DOOR STAYS OUT ACROSS A FRONT COMBO, and comes back for the strokes that keep it" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    // THE OPENER'S GATHER IS STILL GUARDED: nothing has been committed yet.
    for ([_]struct { s: State, b: Blow }{
        .{ .s = .sweepwind, .b = .sweep },
        .{ .s = .overwind, .b = .over },
    }) |c| {
        k.state = c.s;
        k.blow = c.b;
        k.strung = 0;
        k.t = 0.1;
        k.seatDoor();
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.swipeOpen(), 1e-6);
        try std.testing.expect(k.guardUp());
        // …and a LINK's gather keeps it hauled out rather than waving it back across.
        k.strung = 1;
        k.seatDoor();
        try std.testing.expectApproxEqAbs(@as(f32, 1), k.swipeOpen(), 1e-6);
        try std.testing.expect(!k.guardUp());
    }
    // A link that keeps the guard by design puts it straight back — the bash and a SHIELD swat. The thrust
    // does NOT: its point runs down the line the door hangs on, so it is a sword stroke like the swipes.
    k.state = .thrustwind;
    k.blow = .thrust;
    k.strung = 1;
    k.seatDoor();
    try std.testing.expect(!k.guardUp());
    k.state = .bashwind;
    k.blow = .bash;
    k.seatDoor();
    try std.testing.expect(k.guardUp());
    k.state = .swatwind;
    k.blow = .swat;
    k.swatShield = true;
    k.seatDoor();
    try std.testing.expect(k.guardUp());
    k.swatShield = false;
    k.seatDoor();
    try std.testing.expect(!k.guardUp());

    // The bug this pins: the swat's wind never stamped `blow`, so the door's own swat read the previous move.
    var named = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    for ([_]struct { s: State, b: Blow }{
        .{ .s = .sweepwind, .b = .sweep },
        .{ .s = .chainwind, .b = .sweep2 },
        .{ .s = .overwind, .b = .over },
        .{ .s = .thrustwind, .b = .thrust },
        .{ .s = .bashwind, .b = .bash },
        .{ .s = .swatwind, .b = .swat },
        .{ .s = .slamwind, .b = .slam },
        .{ .s = .chargewind, .b = .charge },
        .{ .s = .fallwind, .b = .fall },
    }) |c| {
        named.blow = .over;
        named.enter(c.s);
        try std.testing.expectEqual(c.b, named.blow);
    }

    // **OFF THE POSED DOOR, NOT ONLY OFF THE FLAG** — if the flag says open and the plank has not moved, the
    // mechanic and the picture have parted company (`guardUp`'s law).
    var m = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    m.facing = 0;
    m.state = .sweepwind;
    m.blow = .sweep;
    m.atk = SWEEP_I;
    // GUARDED is the gather's START — the plank leads from there (`SWIPE_LEAD_TO`), so measuring from 0.9 of the
    // wind would price only the part of the haul the lead has not already done.
    m.strung = 0;
    m.t = 0;
    m.seatDoor();
    m.setWindKeys(0.0);
    m.pose();
    const guarded = doorMid(&m);
    m.strung = 1;
    m.t = m.windDur() * 0.9;
    m.seatDoor();
    m.setWindKeys(0.9);
    m.pose();
    const hauled = doorMid(&m);
    const moved = mathx.lenV(mathx.subV(hauled, guarded));
    std.debug.print("\n  door's middle moves {d:.2} m between the opener's gather and a link's\n", .{moved});
    try std.testing.expect(moved > 1.0);
}

/// Hold a face within `allow` of his own horizontal, in the SINE of the tip. The bearing it is pushed back onto
/// is its own where it has one; with the face pointing straight up or down there is none, and his FORWARD is the
/// one direction always available. **This may not bail out** — the degenerate case is where the plank is worst.
fn clampTip(n: rl.Vector3, bodyUp: rl.Vector3, bodyFwd: rl.Vector3, allow: f32) rl.Vector3 {
    const tip = n.x * bodyUp.x + n.y * bodyUp.y + n.z * bodyUp.z;
    if (@abs(tip) <= allow) return n;
    var flat = mathx.subV(n, mathx.scaleV(bodyUp, tip));
    if (mathx.lenV(flat) < 0.02) {
        flat = mathx.subV(bodyFwd, mathx.scaleV(bodyUp, bodyFwd.x * bodyUp.x + bodyFwd.y * bodyUp.y + bodyFwd.z * bodyUp.z));
        if (mathx.lenV(flat) < 1e-4) return n;
    }
    const keep = @sqrt(mathx.maxF(1.0 - allow * allow, 0));
    const lean = if (tip > 0) allow else -allow;
    return mathx.normV(mathx.addV(mathx.scaleV(mathx.normV(flat), keep), mathx.scaleV(bodyUp, lean)));
}

/// Rotate `cur` toward `want` by at most `DOOR_TURN_MAX` for this frame, about the axis between them, and store
/// it back. A zero or unseated `cur` takes `want` whole — a first frame has nothing to chase from.
fn turnToward(cur: *rl.Vector3, want: rl.Vector3, dt: f32) rl.Vector3 {
    if (mathx.lenV(cur.*) < 0.5) {
        cur.* = want;
        return want;
    }
    const from = mathx.normV(cur.*);
    const dot = mathx.clampF(from.x * want.x + from.y * want.y + from.z * want.z, -1, 1);
    const ang = std.math.acos(dot);
    const cap = mathx.radians(DOOR_TURN_MAX) * dt;
    if (ang <= cap or ang < 1e-5) {
        cur.* = want;
        return want;
    }
    const k = cap / ang;
    const sn = @sin(ang);
    // **DEAD OPPOSITE IS REACHABLE AND IT DIVIDES BY ZERO.** A slam interrupted mid-flight hands this a target
    // 180° from the face it is holding, and a slerp has no axis there: `sin(ang)` goes to nothing and the plank
    // comes out NaN. Any perpendicular will do for one step, and the next frame is an ordinary slerp again.
    if (sn < 1e-3) {
        var axis = mathx.crossV(from, v3(0, 1, 0));
        if (mathx.lenV(axis) < 1e-4) axis = mathx.crossV(from, v3(0, 0, 1));
        const side = mathx.normV(mathx.crossV(axis, from));
        const out = mathx.normV(mathx.addV(mathx.scaleV(from, @cos(cap)), mathx.scaleV(side, @sin(cap))));
        cur.* = out;
        return out;
    }
    const a = @sin((1.0 - k) * ang) / sn;
    const b = @sin(k * ang) / sn;
    const out = mathx.normV(mathx.addV(mathx.scaleV(from, a), mathx.scaleV(want, b)));
    cur.* = out;
    return out;
}

/// A world direction in his BODY's own frame (`bodyXf`, a pure rotation, so its transpose is its inverse). The
/// yaw-only version leaves his TOPPLE in, and a body rotating 92 deg through a rise then reads as the door
/// spinning on his arm.
fn bodyDir(k: *const Knight, d: rl.Vector3) rl.Vector3 {
    const b = k.bodyXf;
    return v3(
        d.x * b.m0 + d.y * b.m1 + d.z * b.m2,
        d.x * b.m4 + d.y * b.m5 + d.z * b.m6,
        d.x * b.m8 + d.y * b.m9 + d.z * b.m10,
    );
}

/// The door's own middle — the picture `swipeOpen` claims to be drawing is this point LEAVING his front.
fn doorMid(k: *const Knight) rl.Vector3 {
    const seg = k.shieldSeg();
    return mathx.lerpV(seg[0], seg[1], 0.5);
}

test "THE SHIELD SWIPE IS THE FASTEST THING HE OWNS — camping on the door is answered" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.atk = SWAT_I;
    k.state = .swatwind;
    k.strung = 0;
    k.windHold = SWAT_HANG;
    k.swatShield = false;
    const sword = k.windDur();
    k.swatShield = true;
    const shield = k.windDur();
    std.debug.print("\n  swat gather: sword side {d:.2} s, shield side {d:.2} s (floor {d:.2})\n", .{ sword, shield, foe.TELL_MIN });
    try std.testing.expect(shield < sword * 0.75);
    // NEVER UNDER THE FLOOR: no move in this game may arrive before it has been seen.
    try std.testing.expect(shield >= foe.TELL_MIN);
    // …and it does not take the bait hold, which is the whole of "fast".
    try std.testing.expect(shield <= MOVES[SWAT_I].windDur);
    // The door is the weapon, so it does NOT leave his front to throw it.
    k.state = .swat;
    k.t = MOVES[SWAT_I].strikeDur;
    k.swatShield = true;
    try std.testing.expect(k.guardUp());
}

test "THE DOOR IS OAK — it answers steel almost wholly and sorcery only partly" {
    const steel = combat.Hit{ .dmg = 40 };
    const spell = combat.Hit{ .elem = combat.elems(.{ .chaos = 40 }) };
    const throughSteel = combat.guardChipSplit(steel, TOWER_NEGATE, TOWER_NEGATE_ELEM).raw();
    const throughSpell = combat.guardChipSplit(spell, TOWER_NEGATE, TOWER_NEGATE_ELEM).raw();
    std.debug.print("\n  door: a 40 blade leaves {d:.1} through, a 40 spell leaves {d:.1}\n", .{ throughSteel, throughSpell });
    try std.testing.expect(throughSpell > throughSteel * 3.0);
    // AND IT IS STILL A DOOR: a rod is the way through the front, never a free one.
    try std.testing.expect(throughSpell < 40.0 * 0.5);
    // The hero's own board is unchanged — one figure for both columns.
    const board = combat.guardChip(spell, combat.GUARD_NEGATE);
    try std.testing.expectApproxEqAbs(combat.guardChip(steel, combat.GUARD_NEGATE).raw(), board.raw(), 1e-4);
}

test "EVERY FRONT STROKE CARRIES HIM IN — the lunge is a column, not two hand-written drives" {
    // The bug this pins: `step` was the thrust's and the bash's alone, so a sweep was thrown from where he stood.
    for ([_]usize{ SWEEP_I, SWEEP2_I, OVER_I, THRUST_I, BASH_I }) |mv| {
        try std.testing.expect(MOVES[mv].step > 0);
    }
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    for (MOVES, 0..) |a, mv| {
        const kit = triggerR(a, k.scale);
        const band = bandR(a, k.scale);
        try std.testing.expect(band >= kit);
        if (a.step > 0) {
            std.debug.print("  {s}: kit {d:.2} m, carries {d:.2} m, reaches {d:.2} m\n", .{ moveName(mv), kit, a.step * k.scale, band });
            try std.testing.expect(band > kit);
        }
    }
    // A stroke may not carry him further than it reaches, or the blow lands behind him.
    for (MOVES) |a| try std.testing.expect(a.step < a.reachOut);
}


test "THE SWAT HAS ITS OWN GATHER — every stroke's index names a state nothing else answers to" {
    // The bug this pins: `windFor` ended in `else => .bashwind`, and `SWAT_I` fell into it. The AI picks the
    // swat (`classify`), `enter(windFor(SWAT_I))` put him in the BASH's gather, and at the end of it he came out
    // in `.bash` — so `windHold`/`SWAT_SHIELD_WIND` never applied, the impact came off `shieldHere()` instead of
    // the weapon, `blow` read `.bash` for `guardUp`/`swipeOpen`, and `setRecover` played the bash's arms.
    try std.testing.expectEqual(State.swatwind, windFor(SWAT_I));
    for (0..MOVES.len) |i| {
        for (i + 1..MOVES.len) |j| try std.testing.expect(windFor(i) != windFor(j));
    }

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.atk = SWAT_I;
    k.opener = SWAT_I;
    k.swatShield = false;
    k.enter(windFor(SWAT_I));
    try std.testing.expectEqual(Blow.swat, k.blow);
    const dt = 1.0 / 240.0;
    var t: f32 = 0;
    while (t < k.windDur() + 0.05 and (k.state == .swatwind or k.state == .bashwind)) : (t += dt) {
        _ = k.update(dt, v3(0, 0, 4.0), 400.0, .{});
    }
    std.debug.print("\n  the swat's gather lands in {s} carrying blow {s}\n", .{ @tagName(k.state), @tagName(k.blow) });
    try std.testing.expectEqual(State.swat, k.state);
    try std.testing.expectEqual(Blow.swat, k.blow);

    // …and the shield swat's own wind is the fastest tell he owns, which only `.swatwind` can read.
    var d = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.atk = SWAT_I;
    d.swatShield = true;
    d.enter(windFor(SWAT_I));
    d.windHold = 0;
    const shielded = d.windDur();
    d.swatShield = false;
    try std.testing.expect(shielded < d.windDur());
    try std.testing.expect(shielded >= foe.TELL_MIN);
}

test "THE FALL IS ANSWERED WITH DISTANCE — a run clears the ring from the mark and a walk does not" {
    // Owner: make his fall an AoE so you have to make some distance. The counter used to be his QUARTER; it is
    // his RADIUS now, and the radius is solved against the tell it is drawn through, never picked.
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const reach = fallWaveR(k.scale);
    const tell = FALL_WIND_DUR + FALL_DUR * FALL_IMPACT_K;
    const walked = heromod.WALK_SPEED * tell;
    const ran = heromod.RUN_SPEED * tell;
    std.debug.print("\n  fall ring {d:.2} m over a {d:.2} s tell: a walk covers {d:.2} m, a run {d:.2} m (crush strip {d:.2} m)\n", .{ reach, tell, walked, ran, crushLen(k.scale) });
    try std.testing.expect(walked < reach);
    try std.testing.expect(ran > reach);
    // …and it may not simply repeat the crush: the ring must reach ground the strip never covered.
    try std.testing.expect(reach > foe.hurtReach(FALL_HALF_W, k.scale));
}

test "HE GOES OVER BEFORE HE GOES OVER — the wind tilts him back, and the drop carries on from there" {
    // Owner: tilt back slowly before he falls back. The spine's own lean is a gather like every other gather;
    // what says FALL is the body leaving plumb, and it has to be CONTINUOUS into the drop or it snaps.
    const dt = 1.0 / 240.0;
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.debugFall();
    var t: f32 = 0;
    var last: f32 = 0;
    var jump: f32 = 0;
    var atWindEnd: f32 = 0;
    var quarter: f32 = 0;
    while (t < FALL_WIND_DUR + FALL_DUR) : (t += dt) {
        _ = k.update(dt, v3(0, 0, 3), 400.0, .{});
        const now = k.toppleAmt();
        jump = mathx.maxF(jump, @abs(now - last));
        last = now;
        if (k.state == .fallwind) {
            atWindEnd = now;
            if (t <= FALL_WIND_DUR * 0.25) quarter = now;
        }
    }
    std.debug.print("\n  fall tell: {d:.0} deg back by the end of the wind ({d:.0} deg at a quarter through); worst one-frame step {d:.3} of the topple\n", .{ atWindEnd * TOPPLE_DEG, quarter * TOPPLE_DEG, jump });
    // He is VISIBLY going, and going SLOWLY — most of it is in the back half of the wind, not a flick at the end.
    try std.testing.expect(atWindEnd * TOPPLE_DEG > 8.0);
    try std.testing.expect(quarter < atWindEnd * 0.35);
    // ONE MOTION: the drop picks up where the wind left him, so no frame jumps.
    try std.testing.expect(jump < 0.03);
}

test "HE ROCKS ON HIS BACK UNTIL HE CAN GET UP — and nothing else he does rocks" {
    const dt = 1.0 / 120.0;
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.debugFall();
    var t: f32 = 0;
    var lo: f32 = 1e9;
    var hi: f32 = -1e9;
    var crossings: usize = 0;
    var was: f32 = 0;
    var offDown: f32 = 0;
    while (t < FALL_WIND_DUR + FALL_DUR + DOWN_DUR + ROLL_DUR + RISE_DUR) : (t += dt) {
        _ = k.update(dt, v3(0, 0, 3), 400.0, .{});
        const r = k.rockAmt();
        if (k.state == .downed) {
            lo = mathx.minF(lo, r);
            hi = mathx.maxF(hi, r);
            if ((r > 0) != (was > 0)) crossings += 1;
            was = r;
        } else offDown = mathx.maxF(offDown, @abs(r));
    }
    std.debug.print("  wallow: {d:.1} to {d:.1} deg, {d} times through plumb over {d:.2} s on the ground\n", .{ lo, hi, crossings, DOWN_DUR });
    try std.testing.expect(hi > 2.0 and hi <= ROCK_DEG);
    try std.testing.expect(lo < -2.0 and lo >= -ROCK_DEG);
    try std.testing.expect(crossings >= 2);
    // GENTLE: nothing near the topple it is riding on, and it is over before he rolls.
    try std.testing.expect(ROCK_DEG < TOPPLE_DEG * 0.10);
    try std.testing.expectApproxEqAbs(@as(f32, 0), offDown, 1e-6);
}

test "THE RING BILLS WHERE THE BODY MISSED — and standing still in it is what you are punished for" {
    const probe = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const reach = fallWaveR(probe.scale);
    const mark = probe.fallMarkOf();
    // The two shapes, asked directly: the strip is the body, the ring is the ground.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.heroHit = null;
    k.tryWave(v3(mark.x + reach * 0.75, 0, mark.z), FALL_WAVE_HIT);
    try std.testing.expect(k.heroHit != null);
    k.heroHit = null;
    k.tryCrush(v3(mark.x + reach * 0.75, 0, mark.z), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
    k.heroHit = null;
    k.tryWave(v3(mark.x + reach + 1.0, 0, mark.z), FALL_WAVE_HIT);
    try std.testing.expect(k.heroHit == null);
    // THE BODY STILL WINS where the body lands.
    try std.testing.expect(FALL_WAVE_HIT.dmg < FALL_HIT.dmg);
    try std.testing.expect(FALL_WAVE_HIT.poise < FALL_HIT.poise);
    try std.testing.expect(FALL_WAVE_HIT.stance < FALL_HIT.stance);

    // …AND THROWN FOR REAL: a man who stands there is hit, and the same man RUNNING is not. That is the move.
    const dt = 1.0 / 120.0;
    const run = struct {
        fn it(flee: f32) bool {
            var kk = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
            var hero = v3(0, 0, -2.0);
            kk.debugFall();
            var t: f32 = 0;
            while (t < FALL_WIND_DUR + FALL_DUR + 0.1) : (t += dt) {
                if (kk.update(dt, hero, 400.0, .{}) != null) return true;
                const away = mathx.dirXZ(kk.fallMarkOf(), hero);
                hero = v3(hero.x + away.x * flee * dt, 0, hero.z + away.z * flee * dt);
            }
            return false;
        }
    }.it;
    const stood = run(0);
    const ran = run(heromod.RUN_SPEED);
    std.debug.print("  stood still: {}; ran for it: {}\n", .{ stood, ran });
    try std.testing.expect(stood);
    try std.testing.expect(!ran);
}

test "THE DOOR IS CARRIED IN EVERY STATE HE HAS — never inverted, never over his head, never off his arm" {
    // The pin that was missing. `THE DOOR FACES WHAT IT MEETS` asks three instants and the clearance test asks
    // five strokes; this one walks EVERY move and asks the two things the owner actually saw go wrong. Measured
    // before the carry rule: the plank inverted to -0.82 and its foot climbed to 6.87 m over a 5.11 m crown, and
    // the slam had the hub 4.15 m off a 0.98 m strap.
    const dt = 1.0 / 60.0;
    const G = struct {
        fn sweep(k: *Knight) void {
            k.debugSweep();
        }
        fn sweep2(k: *Knight) void {
            k.debugSweep2();
        }
        fn over(k: *Knight) void {
            k.debugOverhead();
        }
        fn thrust(k: *Knight) void {
            k.debugThrust();
        }
        fn bash(k: *Knight) void {
            k.debugBash();
        }
        fn swatS(k: *Knight) void {
            k.debugSwat(false);
        }
        fn swatD(k: *Knight) void {
            k.debugSwat(true);
        }
        fn shoveS(k: *Knight) void {
            k.debugShove(false);
        }
        fn shoveD(k: *Knight) void {
            k.debugShove(true);
        }
        fn slam(k: *Knight) void {
            k.debugSlam();
        }
        fn charge(k: *Knight) void {
            k.debugCharge();
        }
        fn fall(k: *Knight) void {
            k.debugFall();
        }
        fn leap(k: *Knight) void {
            k.debugLeap();
        }
        fn hop(k: *Knight) void {
            k.debugHop(1.0);
        }
        fn step(k: *Knight) void {
            k.debugStepTurn();
        }
        fn awaken(k: *Knight) void {
            k.debugAwaken();
        }
        fn kill(k: *Knight) void {
            k.debugKill();
        }
        fn stunL(k: *Knight) void {
            k.stagger(false);
        }
        fn stunH(k: *Knight) void {
            k.stagger(true);
        }
        fn idle(_: *Knight) void {}
    };
    const rows = [_]struct { name: []const u8, secs: f32, go: *const fn (*Knight) void }{
        .{ .name = "idle", .secs = 2.0, .go = G.idle },
        .{ .name = "sweep", .secs = 3.2, .go = G.sweep },
        .{ .name = "sweep2", .secs = 2.6, .go = G.sweep2 },
        .{ .name = "overhead", .secs = 3.2, .go = G.over },
        .{ .name = "thrust", .secs = 2.2, .go = G.thrust },
        .{ .name = "bash", .secs = 2.0, .go = G.bash },
        .{ .name = "swat", .secs = 1.6, .go = G.swatS },
        .{ .name = "swat(door)", .secs = 1.8, .go = G.swatD },
        .{ .name = "shove", .secs = 2.2, .go = G.shoveS },
        .{ .name = "shove(door)", .secs = 2.2, .go = G.shoveD },
        .{ .name = "slam", .secs = 3.4, .go = G.slam },
        .{ .name = "charge", .secs = 4.5, .go = G.charge },
        .{ .name = "fall", .secs = 7.0, .go = G.fall },
        .{ .name = "leap", .secs = 2.4, .go = G.leap },
        .{ .name = "hop", .secs = 1.6, .go = G.hop },
        .{ .name = "stepturn", .secs = 1.4, .go = G.step },
        .{ .name = "awaken", .secs = 3.0, .go = G.awaken },
        .{ .name = "stun light", .secs = 1.6, .go = G.stunL },
        .{ .name = "stun heavy", .secs = 2.4, .go = G.stunH },
        .{ .name = "death", .secs = 3.0, .go = G.kill },
    };
    var worstPlumb: f32 = 2;
    var worstFoot: f32 = -1e9;
    var worstHub: f32 = 0;
    for (rows) |row| {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.37);
        const strap = mathx.lenV(mathx.scaleV(k.shieldGrip, k.rigScale()));
        var plumb: f32 = 2;
        var foot: f32 = -1e9;
        var hub: f32 = 0;
        var t: f32 = 0;
        row.go(&k);
        while (t < row.secs) : (t += dt) {
            _ = k.update(dt, v3(0, 0, 3.6), 400.0, .{});
            const at = rl.math.vector3Transform(mathx.zero3, k.shXf);
            const fist = rl.math.vector3Transform(mathx.zero3, k.xf[WRL]);
            // **THE STRAP IS A LENGTH IN EVERY STATE**, the slam and the shove included — that one has no exemption.
            hub = mathx.maxF(hub, mathx.lenV(mathx.subV(at, fist)));
            // A plank laid flat has no upright to measure, and a body going to the ground takes its door down with it.
            if (k.slamDrive() * k.slamLift() > 0.01 or k.floored() or k.dying()) continue;
            const seg = k.shieldSeg();
            plumb = mathx.minF(plumb, mathx.normV(mathx.subV(seg[1], seg[0])).y);
            foot = mathx.maxF(foot, seg[0].y - k.pos.y);
        }
        std.debug.print("\n  {s}: plumb {d:.2}, foot up to {d:.2} m, hub {d:.2} m off a {d:.2} m strap\n", .{ row.name, plumb, foot, hub, strap });
        try std.testing.expect(hub <= strap + 1e-3);
        try std.testing.expect(plumb >= 0.80);

        // Its foot may swing, but it stays under his own waist — it may never get up near his chest, let alone his crown.
        try std.testing.expect(foot < (k.topWorld().y - k.pos.y) * 0.55);
        worstPlumb = mathx.minF(worstPlumb, plumb);
        worstFoot = mathx.maxF(worstFoot, foot);
        worstHub = mathx.maxF(worstHub, hub);
    }
    std.debug.print("\n  worst anywhere: plumb {d:.2}, foot {d:.2} m, hub {d:.2} m\n", .{ worstPlumb, worstFoot, worstHub });
}

test "A WIND CANNOT FOLLOW YOU ROUND ONTO HIS BACK — the gather turns his shoulders, the STEP-TURN moves his feet" {
    // Owner: he tracks a bit too much between attacks, needs a bit more room to get behind. The step-turn was
    // not the culprit — measured, a walked ring drew only 6 of them in 45 s. Every GATHER was: each aimed at his
    // full rate for up to 1.15 s, which is 211 deg, so any wind-up erased whatever ground the recovery bought.
    const dt = 1.0 / 240.0;
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.leash.provoke();
    // Stood dead behind him, at a stand the sweep is picked from.
    const r = triggerR(SWEEP, k.scale) * 0.72;
    const hero = v3(0, 0, -r);
    k.atk = SWEEP_I;
    k.opener = SWEEP_I;
    k.enter(.sweepwind);
    k.windHold = 0;
    var t: f32 = 0;
    while (t < k.windDur()) : (t += dt) _ = k.update(dt, hero, 400.0, .{});
    const left = @abs(k.bearingTo(hero));
    std.debug.print("\n  a full gather from dead behind brings him to {d:.0} deg off (cap {d:.0}); the rear sector starts at {d:.0}\n", .{ left, GATHER_SWEEP_MAX, 180.0 - FALL_SECTOR });
    try std.testing.expect(left > 180.0 - GATHER_SWEEP_MAX - 6.0);
    // AND YOUR BACK POCKET SURVIVES IT: a wind may not carry him out of the sector the FALL is the answer to.
    try std.testing.expect(left > 180.0 - FALL_SECTOR);
    try std.testing.expect(GATHER_SWEEP_MAX < 180.0 - FALL_SECTOR);

    // …AND HE IS STILL NOT DULL. The same walked ring the dullness law is measured on, with the room measured too.
    var g = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    g.leash.provoke();
    const step = 1.0 / 60.0;
    const ring = triggerR(SWEEP, g.scale) * 0.72;
    var ang: f32 = 0;
    var e: f32 = 0;
    var behind: usize = 0;
    var frames: usize = 0;
    var strokes: usize = 0;
    var was = g.state;
    while (e < 45.0) : (e += step) {
        ang += (heromod.WALK_SPEED / ring) * step;
        g.leash.noteSeen();
        _ = g.update(step, v3(mathx.sinf(ang) * ring, 0, mathx.cosf(ang) * ring), 400.0, .{});
        frames += 1;
        if (@abs(g.bearingTo(v3(mathx.sinf(ang) * ring, 0, mathx.cosf(ang) * ring))) > 180.0 - FALL_SECTOR) behind += 1;
        if (g.state != was) {
            switch (g.state) {
                .sweep, .sweep2, .over, .thrust, .bash, .swat, .slam, .charge, .fall => strokes += 1,
                else => {},
            }
            was = g.state;
        }
    }
    const share = @as(f32, @floatFromInt(behind)) / @as(f32, @floatFromInt(frames));
    std.debug.print("  45 s of a walked ring: behind him {d:.0}% of it (was 17), {d} blows thrown\n", .{ share * 100.0, strokes });
    try std.testing.expect(share > 0.20);
    try std.testing.expect(strokes >= 18);
}


test "THE DOOR IS HELD, NOT FLOWN — no move may whip the plank across the ground in a frame" {
    // Owner: it flies around off his hand like a kite. The strap already held the hub at the fist and the plank
    // already could not invert — what was left was SPEED. `swipeOpen` and `shoveAcross` were schedules with
    // seams in them (a state change, a flag clearing) read STRAIGHT into the arm, outside the spring bank that
    // smooths every other channel: measured, the hub crossed 4.3 m in ONE FRAME. Chased at `DOOR_EASE` and led
    // through the gather, the worst any move now does is the SLAM's own haul at 1.08 m.
    const dt = 1.0 / 60.0;
    const G = struct {
        fn sweep(k: *Knight) void {
            k.debugSweep();
        }
        fn over(k: *Knight) void {
            k.debugOverhead();
        }
        fn thrust(k: *Knight) void {
            k.debugThrust();
        }
        fn bash(k: *Knight) void {
            k.debugBash();
        }
        fn swatS(k: *Knight) void {
            k.debugSwat(false);
        }
        fn swatD(k: *Knight) void {
            k.debugSwat(true);
        }
        fn shoveS(k: *Knight) void {
            k.debugShove(false);
        }
        fn shoveD(k: *Knight) void {
            k.debugShove(true);
        }
        fn slam(k: *Knight) void {
            k.debugSlam();
        }
        fn charge(k: *Knight) void {
            k.debugCharge();
        }
        fn leap(k: *Knight) void {
            k.debugLeap();
        }
        fn hop(k: *Knight) void {
            k.debugHop(1.0);
        }
        fn step(k: *Knight) void {
            k.debugStepTurn();
        }
        fn stun(k: *Knight) void {
            k.stagger(true);
        }
        fn fall(k: *Knight) void {
            k.debugFall();
        }
    };
    const rows = [_]struct { n: []const u8, secs: f32, go: *const fn (*Knight) void }{
        .{ .n = "sweep (and what it chains into)", .secs = 4.0, .go = G.sweep },
        .{ .n = "overhead", .secs = 3.0, .go = G.over },
        .{ .n = "thrust", .secs = 2.0, .go = G.thrust },
        .{ .n = "bash", .secs = 1.8, .go = G.bash },
        .{ .n = "swat", .secs = 1.3, .go = G.swatS },
        .{ .n = "swat(door)", .secs = 1.5, .go = G.swatD },
        .{ .n = "shove", .secs = 2.0, .go = G.shoveS },
        .{ .n = "shove(door)", .secs = 2.0, .go = G.shoveD },
        .{ .n = "slam", .secs = 3.2, .go = G.slam },
        .{ .n = "charge", .secs = 2.0, .go = G.charge },
        .{ .n = "leap", .secs = 2.0, .go = G.leap },
        .{ .n = "hop", .secs = 1.4, .go = G.hop },
        .{ .n = "stepturn", .secs = 1.2, .go = G.step },
        .{ .n = "stagger", .secs = 2.0, .go = G.stun },
        .{ .n = "fall", .secs = 6.0, .go = G.fall },
    };
    var worst: f32 = 0;
    var worstRow: []const u8 = "";
    for (rows) |row| {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.37);
        row.go(&k);
        // A frame of settle first: a debug entry SEATS the door (`seatDoor`) where a real fight hands it over,
        // and the seat itself is the one step nothing in play ever takes.
        _ = k.update(dt, v3(0, 0, 3.6), 400.0, .{});
        var prev = rl.math.vector3Transform(mathx.zero3, k.shXf);
        var t: f32 = 0;
        var peak: f32 = 0;
        while (t < row.secs) : (t += dt) {
            _ = k.update(dt, v3(0, 0, 3.6), 400.0, .{});
            const now = rl.math.vector3Transform(mathx.zero3, k.shXf);
            // Off his own POSITION, so a lunge or a charge is his feet travelling and not the door flying.
            peak = mathx.maxF(peak, mathx.lenV(mathx.subV(mathx.subV(now, k.pos), mathx.subV(prev, k.pos))));
            prev = now;
        }
        if (peak > worst) {
            worst = peak;
            worstRow = row.n;
        }
        try std.testing.expect(peak < 1.30);
    }
    std.debug.print("\n  worst door hub step in any move: {d:.2} m a frame, in the {s} (it was 4.3)\n", .{ worst, worstRow });
}

test "MAKE DAMN SURE: through a whole chaotic fight, the door is HELD on every single frame" {
    // The per-move probes drop him into one state from nothing. This drives a REAL fight for 120 s — the AI
    // choosing, chaining, countering, staggering, falling, lighting, dying and coming back — and asks the four
    // things the owner actually complained about on EVERY frame, not at sampled instants. A seam that only shows
    // up when a stagger lands mid-swipe, or a string is billed under a wind, lives here and nowhere else.
    const dt = 1.0 / 60.0;
    var rng = mathx.Rng.init(0x5EED_1234);
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.37);
    k.leash.provoke();
    const strap = mathx.lenV(mathx.scaleV(k.shieldGrip, k.rigScale()));
    const waist = (k.topWorld().y - k.pos.y) * 0.55;

    var seen = [_]bool{false} ** @typeInfo(State).@"enum".fields.len;
    var worstStep: f32 = 0;
    var worstStepIn: []const u8 = "";
    var worstHub: f32 = 0;
    var worstPlumb: f32 = 2;
    var worstPlumbIn: []const u8 = "";
    var worstFoot: f32 = 0;
    var worstFootIn: []const u8 = "";
    var hits: usize = 0;

    var ang: f32 = 0;
    var ring: f32 = 4.0;
    var ringTo: f32 = 4.0;
    var spin: f32 = 1.0;
    var prev = mathx.subV(rl.math.vector3Transform(mathx.zero3, k.shXf), k.pos);
    var prevN = bodyDir(&k, doorNormal(&k));
    var worstTurn: f32 = 0;
    var worstTurnIn: []const u8 = "";
    var t: f32 = 0;
    while (t < 120.0) : (t += dt) {
        if (rng.float() < 0.010) ringTo = rng.range(1.7, 11.0);
        if (rng.float() < 0.008) spin = if (rng.float() < 0.5) -1.0 else 1.0;
        ring = mathx.approach(ring, ringTo, dt * 3.0);
        ang += spin * (rng.range(0, heromod.RUN_SPEED) / ring) * dt;
        const hero = v3(mathx.sinf(ang) * ring, 0, mathx.cosf(ang) * ring);
        k.leash.noteSeen();
        _ = k.update(dt, hero, 400.0, .{});

        if (rng.float() < 0.030) {
            const a = rng.angle();
            const at = mathx.addV(k.centerWorld(), mathx.scaleV(v3(mathx.cosf(a), 0, mathx.sinf(a)), k.hurtRadius() * 0.8));
            k.tryHit(.{ .active = true, .r = 0.3, .a = at, .b = at, .a0 = at, .b0 = at, .hit = .{
                .dmg = rng.range(4, 46),
                .poise = rng.range(0, 90),
                .stance = rng.range(0, 60),
            } });
            hits += 1;
        }
        if (k.gone or !k.alive()) {
            k = Knight.spawn(mathx.zero3, 0, 1.0, rng.float());
            k.leash.provoke();
            prev = mathx.subV(rl.math.vector3Transform(mathx.zero3, k.shXf), k.pos);
            // …and the FACE reference with it, or the first frame of the new body is measured against the old one's.
            prevN = bodyDir(&k, doorNormal(&k));
            continue;
        }
        seen[@intFromEnum(k.state)] = true;

        const tag = @tagName(k.state);
        const hub = rl.math.vector3Transform(mathx.zero3, k.shXf);
        const fist = rl.math.vector3Transform(mathx.zero3, k.xf[WRL]);
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13) and !std.math.isNan(m.m14));
        try std.testing.expect(!std.math.isNan(hub.x) and !std.math.isNan(hub.y));

        const off = mathx.lenV(mathx.subV(hub, fist));
        worstHub = mathx.maxF(worstHub, off);
        try std.testing.expect(off <= strap + 1e-3);

        const here = mathx.subV(hub, k.pos);
        const step = mathx.lenV(mathx.subV(here, prev));
        if (step > worstStep) {
            worstStep = step;
            worstStepIn = tag;
        }
        prev = here;
        try std.testing.expect(step < 1.30);

        // A hub that barely moves can still whip four and a half metres of plank if the FACE turns, which a step
        // test cannot see. Taken in HIS frame, so his own turn is his feet and not the door spinning on his arm.
        const nrm = bodyDir(&k, doorNormal(&k));
        const dot = mathx.clampF(nrm.x * prevN.x + nrm.y * prevN.y + nrm.z * prevN.z, -1, 1);
        const turn = mathx.degrees(std.math.acos(dot));
        if (turn > worstTurn) {
            worstTurn = turn;
            worstTurnIn = tag;
        }
        prevN = nrm;
        if (turn > 20.0) {
            std.debug.print("\n  SPUN at t={d:.2} in .{s}: the face turned {d:.0} deg in one frame\n", .{ t, tag, turn });
            return error.TestUnexpectedResult;
        }

        // The slam lays it flat on purpose, and a body on the ground takes its door down with it.
        if (k.slamDrive() * k.slamLift() > 0.01 or k.floored() or k.dying()) continue;
        const seg = k.shieldSeg();
        const plumb = mathx.normV(mathx.subV(seg[1], seg[0])).y;
        if (plumb < worstPlumb) {
            worstPlumb = plumb;
            worstPlumbIn = tag;
        }
        const foot = seg[0].y - k.pos.y;
        if (foot > worstFoot) {
            worstFoot = foot;
            worstFootIn = tag;
        }
        if (plumb < 0.80 or foot >= waist) {
            const bu = mathx.normV(v3(k.bodyXf.m4, k.bodyXf.m5, k.bodyXf.m6));
            std.debug.print("\n  BROKE at t={d:.2} in .{s}: plumb {d:.2}, foot {d:.2} m (waist {d:.2})\n", .{ t, tag, plumb, foot, waist });
            std.debug.print("    face ({d:.2},{d:.2},{d:.2}) bodyUp ({d:.2},{d:.2},{d:.2}) laid {d:.4} topple {d:.2}\n", .{ nrm.x, nrm.y, nrm.z, bu.x, bu.y, bu.z, k.slamDrive() * k.slamLift(), k.toppleAmt() });
            return error.TestUnexpectedResult;
        }
    }

    var visited: usize = 0;
    for (seen) |b| {
        if (b) visited += 1;
    }
    std.debug.print("\n  120 s of a real fight, {d} blows landed on him, {d} of his {d} states visited\n", .{ hits, visited, seen.len });
    std.debug.print("  worst frame step {d:.2} m (in .{s}); hub never further than {d:.2} m off a {d:.2} m strap\n", .{ worstStep, worstStepIn, worstHub, strap });
    std.debug.print("  worst face turn {d:.1} deg a frame (in .{s})\n", .{ worstTurn, worstTurnIn });
    std.debug.print("  worst plumb {d:.2} (in .{s}); highest foot {d:.2} m (in .{s}), waist is {d:.2}\n", .{ worstPlumb, worstPlumbIn, worstFoot, worstFootIn, waist });
    // NO SILENT COVERAGE: a soak that never reached the fall or the stuns would pass having proved nothing.
    for ([_]State{ .idle, .sweepwind, .sweep, .chainwind, .sweep2, .recover, .stunlight, .stunheavy, .fall, .downed, .rise, .dead }) |s| {
        if (!seen[@intFromEnum(s)]) std.debug.print("  NEVER VISITED: .{s}\n", .{@tagName(s)});
        try std.testing.expect(seen[@intFromEnum(s)]);
    }
    try std.testing.expect(visited >= 24);
}

test "A FACE HANDED ITS OWN OPPOSITE STILL TURNS — the slerp has no axis at 180 deg and used to come out NaN" {
    // A slam cut short mid-flight hands the chase a target dead opposite the face it is holding. `sin(ang)` is
    // zero there and the divide took the whole plank with it.
    const dt = 1.0 / 60.0;
    var face = v3(0, 0, 1);
    var turned: f32 = 0;
    var steps: usize = 0;
    while (steps < 40) : (steps += 1) {
        const out = turnToward(&face, v3(0, 0, -1), dt);
        try std.testing.expect(!std.math.isNan(out.x) and !std.math.isNan(out.y) and !std.math.isNan(out.z));
        try std.testing.expectApproxEqAbs(@as(f32, 1), mathx.lenV(out), 1e-4);
        turned = mathx.degrees(std.math.acos(mathx.clampF(out.z, -1, 1)));
    }
    std.debug.print("\n  a face handed its own opposite turns {d:.0} deg over 40 frames, and stays a unit vector\n", .{turned});
    // It has to actually GO somewhere — a fallback that returns the input is a plank frozen facing backwards.
    try std.testing.expect(turned > 20.0);
    // …and never faster than the cap, whatever it was handed.
    var one = v3(0, 0, 1);
    const step = turnToward(&one, v3(0, 0, -1), dt);
    const moved = mathx.degrees(std.math.acos(mathx.clampF(step.z, -1, 1)));
    try std.testing.expect(moved <= DOOR_TURN_MAX * dt + 0.01);
}
