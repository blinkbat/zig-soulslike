const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const anim = @import("../core/anim.zig");
const wf = @import("../world/worldfmt.zig");
const elemfx = @import("../gfx/elemfx.zig");
const sfx = @import("../core/audio.zig");
const shroommod = @import("shroom.zig");
const knightmod = @import("knight.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;


const H: f32 = heromod.H;

/// 0.86 puts a 2.66 m crown on the swordsman, over the mushroom mage's 2.04 and under the bone knight.
pub const SCALE = (heromod.H + 0.86) / heromod.H;
/// The widths ride the height at 0.97 of the hip's share — a stalk, not a barrel.
const HIP_HALF = heromod.HIP_HALF * SCALE;
const SHOULDER_HALF = heromod.SHOULDER_HALF * SCALE * 0.97;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const HEAD = heromod.HEAD;
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
const HELD = heromod.HELD;

const SOLES = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.048 * H, .toe = 0.192 * H, .halfW = 0.064 * H, .drop = 0.038 * H },
    .{ .bone = ANKR, .heel = 0.048 * H, .toe = 0.192 * H, .halfW = 0.064 * H, .drop = 0.038 * H },
};

// AUTHOR DARK AND SOLVE IT: screen goes as albedo^(1/2.2) and `.skin` only mottles (x0.94..1.05), so the albedo
// IS the read. `RIND` at (112,96,74) came back at 187 luma against the mushroom mage's cloak at (10,13,9), which
// lands at 58; 26 puts the rind at 90 on screen and the magus's body at 63.
const RIND = rgba(26, 22, 17, 255);
const RIND_DK = rgba(16, 14, 11, 255);
const RIND_LT = rgba(42, 36, 28, 255);
const GILL = rgba(12, 8, 8, 255);
const MYC = rgba(15, 18, 13, 255);
const MYC_DK = rgba(9, 11, 8, 255);
const CAP_COL = shroommod.CAP_COL;
const CAP_DK = shroommod.CAP_DK;
const WART = shroommod.WART;
const FLESH = rgba(30, 26, 20, 255);
// A blade may not be the brightest thing in the frame: at 104 it came off the chain at 170 luma against a body
// at 90, and `.steel`'s specular is catastrophic on a flat face. 58 lands it at 128.
const STEEL = rgba(58, 61, 66, 255);
const STEEL_DK = rgba(30, 32, 36, 255);
const VENOM = rgba(150, 206, 120, 210);
const EYE = rgba(214, 232, 150, 44);

const CHAOS_CORE = elemfx.sig(.chaos).core;
const CHAOS_EDGE = elemfx.sig(.chaos).edge;

/// It must reach past where the pair themselves stand: at 26 the magus could blink outside the ring its own boss bar wakes on.
/// The ring as authored — what the comptime pin below is asked of, since the ring itself is live now.
pub const AGGRO_R_BANK: f32 = 30.0;
pub var AGGRO_R: f32 = AGGRO_R_BANK;

const MARK_AT = v3(0, 0.03 * H, 0);

const SHOVE_DECAY: f32 = 6.5;
const A_PROT: f32 = 3.2;

const SPRING_STIFF: f32 = 1500.0;
const SPRING_ZETA: f32 = 0.72;
const SPRING_FALLOFF: f32 = 0.93;

const CHAN_N = 10;
const Chan = [CHAN_N]f32;
const CH_LEAN = 0;
const CH_TWIST = 1;
const CH_HEAD = 2;
const CH_RSH = 3;
const CH_RABD = 4;
const CH_REL = 5;
const CH_LSH = 6;
const CH_LEL = 7;
/// **WHERE THE KIT POINTS, AS A POSE CHANNEL** — degrees the weapon leads FORWARD of the forearm line (0 down,
/// 90 level, 180 on end), the warriors' own convention (`hero.staffFit`).
const CH_TILT = 8;
/// Prepended in the BONE's frame so the lateral offset survives the swing — once an arm has swung forward,
/// abduction is a near no-op (34 deg of it moved the off fist 0.13 m). The hand sits `armLen · sin(clasp)` off
/// its shoulder, so on 0.57 m shoulders and a 0.88 m arm the midline is `asin(0.57/0.88)` = 40 deg.
const CH_CLASP = 9;

const P = struct {
    lean: f32 = 0,
    twist: f32 = 0,
    head: f32 = 0,
    rsh: f32 = 0,
    rabd: f32 = 0,
    rel: f32 = 0,
    lsh: f32 = 0,
    lel: f32 = 0,
    tilt: f32 = 0,
    clasp: f32 = 0,

    pub fn chan(self: P) Chan {
        return .{ self.lean, self.twist, self.head, self.rsh, self.rabd, self.rel, self.lsh, self.lel, self.tilt, self.clasp };
    }
};

const PoseKey = anim.Pose(P).PoseKey;

fn chanOf(self: anytype) Chan {
    return .{ self.bodyLean, self.twist, self.headPitch, self.rsh, self.rabd, self.rel, self.lsh, self.lel, self.tilt, self.clasp };
}

fn setChan(self: anytype, c: Chan) void {
    self.bodyLean = c[CH_LEAN];
    self.twist = c[CH_TWIST];
    self.headPitch = c[CH_HEAD];
    self.rsh = c[CH_RSH];
    self.rabd = c[CH_RABD];
    self.rel = c[CH_REL];
    self.lsh = c[CH_LSH];
    self.lel = c[CH_LEL];
    self.tilt = c[CH_TILT];
    self.clasp = c[CH_CLASP];
}

fn settle(self: anytype, dt: f32) void {
    var want = chanOf(self);
    self.springs.chase(&want, SPRING_STIFF, SPRING_ZETA, SPRING_FALLOFF, dt);
    setChan(self, want);
}
const samplePose = anim.Pose(P).sample;


const SW_HP: f32 = 620.0;
const SW_POISE: f32 = 62.0;
const SW_STANCE: f32 = 96.0;
const SW_RESISTS = combat.resists(.{ .chaos = 75, .fire = -45, .cold = -25, .lightning = 10 });
pub var SW_SOULS: u32 = 1500;

const SW_TURN_RATE: f32 = 3.05;
const SW_SPEED: f32 = heromod.RUN_SPEED_BANK * 0.92;
const SW_BODY_R: f32 = 0.56;
/// 1.05 m about a centre 1.45 m up on a 2.42 m body — the crown at `SW_TOP_F` without dropping below the knee.
const SW_HURT_R: f32 = 0.78;
const SW_CENTER_F: f32 = 0.60;
const SW_TOP_F: f32 = 1.06;

const SW_DEATH_DUR: f32 = 2.05;
const SW_DISS_DUR: f32 = 1.15;
const SW_DISSOLVE = foe.Dissolve{ .rate = 62.0, .spread = 0.95, .rise = 1.05, .flake = WART };
const SW_SHOVE = foe.Push{ .light = 1.05, .heavy = 2.35 };

/// The blade, from the fist. A longsword on a 2.41 m body: 1.62 m of it past the hand.
const SW_BLADE_LEN: f32 = 0.90 * H;
const SW_KIT_R: f32 = 0.30;

/// The MEASURED reach of the stroke, not a number beside one: thrown at a man dead ahead the slash lands out to 2.35 m.
const SW_SLASH_R: f32 = 2.2;

/// Half the arc the stroke sweeps on its own, in degrees — measured off the blade's own path, and what the
const SW_SWEEP_HALF: f32 = 46.0;

/// Thrown at a man 165 deg off he came round to 72 and billed nothing; given the slash's allowance he was handed
/// out at 100 deg and drove past the man at every stand in its band.
fn swSlashArc() f32 {
    return SW_TURN_RATE * SW_SLASH_WIND + mathx.radians(SW_SWEEP_HALF);
}
fn swLungeArc() f32 {
    return SW_TURN_RATE * SW_LUNGE_WIND;
}
fn swHeavyArc() f32 {
    return SW_TURN_RATE * SW_HEAVY_WIND;
}

/// Priced by its CLOCK, not by its row: measured through his own update at his slash band he billed 22.7 a second
/// against the first boss's 22.0, and he is one of TWO bodies. Cooldowns up about 40% carry the chain to ~13 a second.
const SW_SLASH_WIND: f32 = 0.62;
const SW_SLASH_DUR: f32 = 0.26;
const SW_SLASH_REC: f32 = 0.62;
const SW_SLASH2_CHANCE: f32 = 0.55;
const SW_SLASH_CD: f32 = 1.35;

const SW_LUNGE_MIN: f32 = 3.4;
const SW_LUNGE_MAX: f32 = 7.3;
const SW_LUNGE_WIND: f32 = 0.70;
const SW_LUNGE_DUR: f32 = 0.34;
const SW_LUNGE_REC: f32 = 0.72;
/// At 3.6 it came round every 4.6 s measured, close enough to the slash's own cadence to read as one move on repeat; at 6.4 it is one throw in ~7.7 s.
const SW_LUNGE_CD: f32 = 6.4;
/// Metres pre-scale, so the travel is `× SCALE`: 7.68 m on the ground, down from the 10.94 m that 7.4 bought.
const SW_LUNGE_DIST: f32 = 5.2;
const SW_LUNGE_UP: f32 = 0.30;

const SW_BACK_DIST: f32 = 4.8;
const SW_BACK_DUR: f32 = 0.38;
const SW_BACK_UP: f32 = 0.52;
const SW_BACK_LAND: f32 = 0.20;
const SW_BACK_CD: f32 = 6.5;

/// The knight's overhead is 46 and his bread-and-butter sweep 33; the slash was landing 56 raw and the lunge 72,
/// out of a stroke that CHAINS. Now 18 on the slash and 25 on the lunge, all of it off `dmg`, so the venom clock
/// the fight is built on is untouched.
const SW_SLASH_HIT = combat.Hit{ .dmg = 7, .poise = 30, .stance = 26, .elem = combat.elems(.{ .chaos = 11 }) };
/// A thrust does not throw a man off his feet: `launch = 3.4` is 1.33 s off the ground per hit from a move that
/// closes 7.7 m. The throw moved to the OVERHEAD.
const SW_LUNGE_HIT = combat.Hit{ .dmg = 13, .poise = 44, .stance = 34, .elem = combat.elems(.{ .chaos = 12 }) };

const SW_HEAVY_R: f32 = 2.1;
const SW_HEAVY_WIND: f32 = 1.15;
const SW_HEAVY_DUR: f32 = 0.30;
const SW_HEAVY_REC: f32 = 0.98;
const SW_HEAVY_CD: f32 = 8.5;
const SW_HEAVY_LAUNCH: f32 = 1.2;
const SW_HEAVY_HIT = combat.Hit{ .dmg = 24, .poise = 58, .stance = 42, .launch = SW_HEAVY_LAUNCH, .elem = combat.elems(.{ .chaos = 14 }) };

const SW_NPART = 40;

comptime {
    std.debug.assert(SW_SLASH_WIND >= foe.TELL_MIN);
    std.debug.assert(SW_LUNGE_WIND >= foe.TELL_MIN);
    std.debug.assert(SW_LUNGE_MIN > SW_SLASH_R);
    std.debug.assert(SW_SWEEP_HALF > 20.0 and SW_SWEEP_HALF < 90.0);
    std.debug.assert(SW_LUNGE_DIST + SW_SLASH_R >= SW_LUNGE_MAX);
    std.debug.assert(SW_BACK_DIST + SW_SLASH_R > SW_LUNGE_MIN);
    std.debug.assert(SW_BACK_DIST + SW_SLASH_R < SW_LUNGE_MAX);
    std.debug.assert(SW_SLASH_HIT.elem.at(.chaos) > 0 and SW_LUNGE_HIT.elem.at(.chaos) > 0);
    std.debug.assert(SW_HEAVY_WIND > SW_SLASH_WIND and SW_HEAVY_WIND > SW_LUNGE_WIND);
    std.debug.assert(SW_HEAVY_R <= SW_SLASH_R);
    std.debug.assert(SW_HEAVY_CD > SW_LUNGE_CD);
    std.debug.assert(SW_HEAVY_REC > SW_SLASH_REC and SW_HEAVY_REC > SW_LUNGE_REC);
    std.debug.assert(SW_HEAVY_HIT.launch > 0 and SW_SLASH_HIT.launch == 0 and SW_LUNGE_HIT.launch == 0);
    std.debug.assert(SW_HEAVY_LAUNCH > combat.SLAM_LAUNCH and SW_HEAVY_LAUNCH <= heromod.LAUNCH_MAX_APEX);
}

const SW_CARRY = P{ .lean = 17.0, .head = -9.0, .rsh = 14.0, .rabd = 16.0, .rel = 58.0, .lsh = 10.0, .lel = 34.0, .tilt = 34.0 };

const SW_SLASH_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = SW_CARRY },
    .{ .t = 0.60, .p = .{ .lean = -8.0, .twist = -38.0, .head = 6.0, .rsh = -34.0, .rabd = 54.0, .rel = 96.0, .lsh = 22.0, .lel = 48.0, .tilt = 128.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -12.0, .twist = -46.0, .head = 8.0, .rsh = -44.0, .rabd = 62.0, .rel = 104.0, .lsh = 26.0, .lel = 52.0, .tilt = 148.0 } },
};

const SW_SLASH_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -12.0, .twist = -46.0, .head = 8.0, .rsh = -44.0, .rabd = 62.0, .rel = 104.0, .lsh = 26.0, .lel = 52.0, .tilt = 148.0 } },
    .{ .t = 0.46, .p = .{ .lean = 14.0, .twist = 40.0, .head = -8.0, .rsh = 74.0, .rabd = 10.0, .rel = 16.0, .lsh = -14.0, .lel = 22.0, .tilt = 96.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 11.0, .twist = 48.0, .head = -6.0, .rsh = 82.0, .rabd = 6.0, .rel = 10.0, .lsh = -20.0, .lel = 18.0, .tilt = 74.0 } },
};

const SW_SLASH2_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = 11.0, .twist = 48.0, .head = -6.0, .rsh = 82.0, .rabd = 6.0, .rel = 10.0, .lsh = -20.0, .lel = 18.0, .tilt = 74.0 } },
    .{ .t = 0.44, .p = .{ .lean = 8.0, .twist = -34.0, .head = -4.0, .rsh = 30.0, .rabd = 58.0, .rel = 30.0, .lsh = 30.0, .lel = 26.0, .tilt = 100.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 4.0, .twist = -40.0, .head = -2.0, .rsh = 20.0, .rabd = 64.0, .rel = 38.0, .lsh = 34.0, .lel = 30.0, .tilt = 88.0 } },
};

const SW_LUNGE_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = SW_CARRY },
    .{ .t = 0.55, .p = .{ .lean = -18.0, .twist = -22.0, .head = 10.0, .rsh = -20.0, .rabd = 22.0, .rel = 118.0, .lsh = 16.0, .lel = 62.0, .tilt = 112.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -24.0, .twist = -28.0, .head = 13.0, .rsh = -26.0, .rabd = 26.0, .rel = 128.0, .lsh = 20.0, .lel = 68.0, .tilt = 120.0 } },
};

const SW_LUNGE_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -24.0, .twist = -28.0, .head = 13.0, .rsh = -26.0, .rabd = 26.0, .rel = 128.0, .lsh = 20.0, .lel = 68.0, .tilt = 120.0 } },
    .{ .t = 0.30, .p = .{ .lean = 26.0, .twist = 16.0, .head = -10.0, .rsh = 84.0, .rabd = 4.0, .rel = 6.0, .lsh = -26.0, .lel = 14.0, .tilt = 92.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 22.0, .twist = 12.0, .head = -8.0, .rsh = 78.0, .rabd = 6.0, .rel = 10.0, .lsh = -22.0, .lel = 18.0, .tilt = 88.0 } },
};

/// Solved, not picked: `asin(shoulderHalf / armLen)` on this body's own numbers (0.57 m and 0.88 m).
const SW_HEAVY_CLASP: f32 = 40.0;

const SW_HEAVY_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = SW_CARRY },
    .{ .t = 0.52, .p = .{ .lean = -13.0, .head = 13.0, .rsh = -48.0, .rabd = 12.0, .rel = 66.0, .lsh = -46.0, .lel = 64.0, .clasp = SW_HEAVY_CLASP * 0.85, .tilt = 168.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -21.0, .head = 18.0, .rsh = -72.0, .rabd = 5.0, .rel = 46.0, .lsh = -72.0, .lel = 46.0, .clasp = SW_HEAVY_CLASP, .tilt = 178.0 } },
};

const SW_HEAVY_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -21.0, .head = 18.0, .rsh = -72.0, .rabd = 5.0, .rel = 46.0, .lsh = -72.0, .lel = 46.0, .clasp = SW_HEAVY_CLASP, .tilt = 178.0 } },
    .{ .t = 0.42, .p = .{ .lean = 33.0, .head = -18.0, .rsh = 88.0, .rabd = 4.0, .rel = 8.0, .lsh = 88.0, .lel = 8.0, .clasp = SW_HEAVY_CLASP, .tilt = 66.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 27.0, .head = -14.0, .rsh = 80.0, .rabd = 6.0, .rel = 13.0, .lsh = 80.0, .lel = 13.0, .clasp = SW_HEAVY_CLASP, .tilt = 48.0 } },
};

/// `.slash2` opens 88 deg of twist off its own end pose and the magus's `.orb` 84 of `lsh`, which the spring bank whips through in a tenth of a second.
fn recTrack(comptime keys: []const PoseKey, comptime carry: P) [2]PoseKey {
    return .{
        .{ .t = 0.00, .p = keys[keys.len - 1].p },
        .{ .t = 1.00, .p = carry, .ease = .decel },
    };
}

const SW_HEAVY_REC_KEYS = recTrack(&SW_HEAVY_KEYS, SW_CARRY);

const SW_BACK_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = 22.0, .twist = 12.0, .head = -8.0, .rsh = 78.0, .rabd = 6.0, .rel = 10.0, .lsh = -22.0, .lel = 18.0, .tilt = 88.0 } },
    .{ .t = 0.40, .p = .{ .lean = -30.0, .head = 16.0, .rsh = 6.0, .rabd = 40.0, .rel = 84.0, .lsh = 34.0, .lel = 56.0, .tilt = 60.0 }, .ease = .decel },
    .{ .t = 1.00, .p = SW_CARRY, .ease = .decel },
};

const SW_REC_KEYS = recTrack(&SW_SLASH_KEYS, SW_CARRY);
const SW_SLASH2_REC_KEYS = recTrack(&SW_SLASH2_KEYS, SW_CARRY);
const SW_LUNGE_REC_KEYS = recTrack(&SW_LUNGE_KEYS, SW_CARRY);

const SwState = enum { idle, stride, slash_wind, slash, slash2, heavy_wind, heavy, lunge_wind, lunge, back, recover, stunlight, stunheavy, dead };

const SwChoice = enum { hold, close, slash, heavy, lunge, back };

const Recover = enum {
    slash,
    slash2,
    heavy,
    lunge,

    fn dur(self: Recover) f32 {
        return switch (self) {
            .slash, .slash2 => SW_SLASH_REC,
            .heavy => SW_HEAVY_REC,
            .lunge => SW_LUNGE_REC,
        };
    }
    fn keys(self: Recover) []const PoseKey {
        return switch (self) {
            .slash => &SW_REC_KEYS,
            .slash2 => &SW_SLASH2_REC_KEYS,
            .heavy => &SW_HEAVY_REC_KEYS,
            .lunge => &SW_LUNGE_REC_KEYS,
        };
    }
};

fn swClassify(dist: f32, off: f32, slashReady: bool, heavyReady: bool, lungeReady: bool, backReady: bool, crowded: bool) SwChoice {
    if (dist > AGGRO_R) return .hold;
    if (crowded and backReady) return .back;
    const a = @abs(off);
// An 8.5 s clock only asked when the 1.35 s one happens to be cold is a move you see once a fight.
    if (dist <= SW_HEAVY_R and heavyReady and a <= swHeavyArc()) return .heavy;
    if (dist <= SW_SLASH_R and slashReady and a <= swSlashArc()) return .slash;
    if (lungeReady and dist >= SW_LUNGE_MIN and dist <= SW_LUNGE_MAX and a <= swLungeArc()) return .lunge;
    return .close;
}


const MG_HP: f32 = 520.0;
const MG_POISE: f32 = 34.0;
const MG_STANCE: f32 = 62.0;
const MG_RESISTS = combat.resists(.{ .chaos = 75, .fire = -55, .cold = -15, .lightning = -20 });
pub var MG_SOULS: u32 = 1500;

const MG_TURN_RATE: f32 = 2.5;
const MG_SPEED: f32 = heromod.WALK_SPEED_BANK * 0.72;
const MG_BODY_R: f32 = 0.52;
const MG_HURT_R: f32 = 0.74;
const MG_CENTER_F: f32 = 0.62;
const MG_TOP_F: f32 = 1.08;

const MG_DEATH_DUR: f32 = 1.85;
const MG_DISS_DUR: f32 = 1.10;
const MG_DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 1.0, .flake = CAP_DK };
const MG_SHOVE = foe.Push{ .light = 1.20, .heavy = 2.70 };

const MG_FLEE_R: f32 = 7.0;
const MG_KEEP_R: f32 = 16.0;
const MG_DRIFT_DUR: f32 = 0.85;

/// At 15 m/s it crossed the caster's own keep-band in 1.07 s; at 9.5 that is 1.68 s, and 0.74 s out of `MG_ORB_MIN` — still nearly twice the hero's sprint.
pub const ORB_SPEED: f32 = 9.5;
pub const ORB_R: f32 = 0.32;
pub const ORB_LIFE: f32 = 3.6;
/// ATTRITION, and the knight's gas is the tier: 14 raw, thrown often, and never the thing that kills you.
pub const ORB_HIT = combat.Hit{ .poise = 14, .elem = combat.elems(.{ .chaos = 14 }) };
const MG_ORB_WIND: f32 = 0.36;
const MG_ORB_DUR: f32 = 0.16;
const MG_REC: f32 = 0.26;
const MG_ORB_CD: f32 = 2.3;
const MG_ORB_RELEASE_K: f32 = 0.34;
const MG_ORB_MIN: f32 = MG_FLEE_R;

/// At 1.9 s of growing, a bunch sown under you went off inside one of the swordsman's own chains; 3.2 s is two of his slashes plus the tail.
pub const CAP_GROW: f32 = 3.2;
pub const CAP_GLOW: f32 = 1.05;
pub const CAP_BURST_R: f32 = 3.1;
/// blow: at 40 apiece, standing in the middle of a bunch was 160 raw — more than three of the knight's overheads.
pub const CAP_HIT = combat.Hit{ .poise = 34, .stance = 22, .launch = 2.2, .elem = combat.elems(.{ .chaos = 20 }) };
const MG_SPROUT_WIND: f32 = 0.78;
const MG_SPROUT_DUR: f32 = 0.30;
const MG_SPROUT_CD: f32 = 6.2;
const MG_SPROUT_MIN: f32 = MG_FLEE_R;
const MG_SPROUT_MAX: f32 = 18.0;
const MG_BUNCH: usize = 4;
const MG_BUNCH_R: f32 = 1.8;
const CAP_STAGGER: f32 = 0.45;

const MG_FADE_OUT: f32 = 1.15;
const MG_GONE_DUR: f32 = 0.55;
const MG_FADE_IN: f32 = 0.60;
const MG_FADE_CD: f32 = 9.0;
const MG_REAPPEAR_R: f32 = 13.0;
pub const MIST_R: f32 = 3.4;
/// At 5.5 s the ground it denied was clear again before it had cast anything from the new spot; 9.5 s leaves it standing across a whole cast cycle.
pub const MIST_LIFE: f32 = 9.5;
pub const MIST_BUILD: f32 = 16.0;

const MG_NPART = 72;

comptime {
    std.debug.assert(MG_ORB_WIND >= foe.TELL_MIN);
    std.debug.assert(MG_SPROUT_WIND >= foe.TELL_MIN);
    std.debug.assert(MG_FLEE_R < MG_KEEP_R);
    std.debug.assert(MG_SPROUT_MIN < MG_KEEP_R and MG_SPROUT_MAX > MG_KEEP_R);
    std.debug.assert(MG_SPROUT_MIN >= MG_FLEE_R and MG_ORB_MIN >= MG_FLEE_R);
    std.debug.assert(MG_FADE_OUT > MG_ORB_WIND * 2.0);
    std.debug.assert(MG_REAPPEAR_R > MG_FLEE_R);
    std.debug.assert(CAP_GROW > CAP_GLOW * 2.0);
    std.debug.assert(ORB_SPEED * ORB_LIFE > AGGRO_R_BANK);
    std.debug.assert(MG_PRESS_RATE_HURT >= 1.0 and MG_FADE_CD_HURT <= MG_FADE_CD);
// A creature may not stand further off than the ring its own bar wakes on: keeping to 16 and blinking 13 put the magus 29 m out against an `AGGRO_R` of 26.
    std.debug.assert(MG_KEEP_R + MG_REAPPEAR_R <= AGGRO_R_BANK);
}

const MG_CARRY = P{ .lean = 4.0, .head = 3.0, .rsh = 16.0, .rabd = 7.0, .rel = 38.0, .lsh = 8.0, .lel = 20.0, .tilt = 172.0 };

const MG_ORB_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = MG_CARRY },
    .{ .t = 0.60, .p = .{ .lean = -6.0, .twist = -14.0, .head = 5.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 40.0, .lel = 92.0, .tilt = 150.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -9.0, .twist = -18.0, .head = 6.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 46.0, .lel = 100.0, .tilt = 142.0 } },
};

const MG_ORB_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -9.0, .twist = -18.0, .head = 6.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 46.0, .lel = 100.0, .tilt = 142.0 } },
    .{ .t = 0.34, .p = .{ .lean = 12.0, .twist = 12.0, .head = -6.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 116.0, .lel = 16.0, .tilt = 118.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 9.0, .twist = 8.0, .head = -4.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 124.0, .lel = 10.0, .tilt = 112.0 } },
};

const MG_SPROUT_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = MG_CARRY },
    .{ .t = 0.58, .p = .{ .lean = -14.0, .head = 14.0, .rsh = -52.0, .rabd = 28.0, .rel = 44.0, .lsh = -44.0, .lel = 50.0, .tilt = 176.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -19.0, .head = 18.0, .rsh = -66.0, .rabd = 32.0, .rel = 38.0, .lsh = -56.0, .lel = 44.0, .tilt = 180.0 } },
};

const MG_SPROUT_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -19.0, .head = 18.0, .rsh = -66.0, .rabd = 32.0, .rel = 38.0, .lsh = -56.0, .lel = 44.0, .tilt = 180.0 } },
    .{ .t = 0.38, .p = .{ .lean = 24.0, .head = -14.0, .rsh = 54.0, .rabd = 10.0, .rel = 14.0, .lsh = 44.0, .lel = 18.0, .tilt = 14.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 20.0, .head = -11.0, .rsh = 48.0, .rabd = 8.0, .rel = 16.0, .lsh = 40.0, .lel = 20.0, .tilt = 22.0 } },
};

const MG_SPROUT_REC_KEYS = recTrack(&MG_SPROUT_KEYS, MG_CARRY);
const MG_ORB_REC_KEYS = recTrack(&MG_ORB_KEYS, MG_CARRY);

const MgRecover = enum {
    orb,
    sprout,

    fn keys(self: MgRecover) []const PoseKey {
        return switch (self) {
            .orb => &MG_ORB_REC_KEYS,
            .sprout => &MG_SPROUT_REC_KEYS,
        };
    }
};

const MG_FADE_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = MG_CARRY },
    .{ .t = 1.00, .p = .{ .lean = 26.0, .head = -22.0, .rsh = 4.0, .rabd = 4.0, .rel = 118.0, .lsh = 4.0, .lel = 112.0, .tilt = 150.0 }, .ease = .accel },
};

const MgState = enum { idle, drift, orb_wind, orb_throw, sprout_wind, sprout, recover, fade_out, gone, fade_in, stunlight, stunheavy, dead };

const MgChoice = enum { hold, back, keep, orb, sprout, vanish };

fn mgClassify(dist: f32, orbReady: bool, sproutReady: bool, fadeReady: bool, pressed: bool) MgChoice {
    if (dist > AGGRO_R) return .hold;
    if (pressed and fadeReady) return .vanish;
    if (dist < MG_FLEE_R) return .back;
    if (sproutReady and dist >= MG_SPROUT_MIN and dist <= MG_SPROUT_MAX) return .sprout;
    if (orbReady and dist >= MG_ORB_MIN) return .orb;
    return .keep;
}

pub const CAP_N: usize = 24;

pub const Cap = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    r: f32 = 0.5,
    seed: f32 = 0,
    burst: bool = false,

    /// 0 while it grows, climbing to 1 over the glow — the picture and the clock are one number.
    pub fn heat(self: *const Cap) f32 {
        if (self.t <= CAP_GROW) return 0;
        return mathx.clampF((self.t - CAP_GROW) / CAP_GLOW, 0, 1);
    }
    pub fn grown(self: *const Cap) f32 {
        return mathx.clampF(self.t / CAP_GROW, 0, 1);
    }
    pub fn showing(self: *const Cap) bool {
        return self.live and self.t > 0;
    }
};

pub const MIST_N: usize = 8;

pub const Mist = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    t: f32 = 0,

    pub fn amt(self: *const Mist) f32 {
        if (!self.live) return 0;
        const u = mathx.clampF(self.t / MIST_LIFE, 0, 1);
        return mathx.smoothstep(0, 0.14, u) * (1.0 - mathx.smoothstep(0.55, 1.0, u));
    }
    pub fn covers(self: *const Mist, at: rl.Vector3) bool {
        return self.live and self.amt() > 0.10 and mathx.distXZ(self.at, at) <= MIST_R;
    }
};

pub const ORB_N: usize = 12;

pub const Orb = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    vel: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    spin: f32 = 0,
    floor: f32 = 0,
};

const SW_CROWD_HOLD: f32 = 3.2;

pub const SwModel = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) SwModel {
        return .{ .bone = swBones(), .mat = gfx.material(shader, "fungal swordsman") };
    }
    pub fn setShader(self: *SwModel, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const SwModel, k: *const Swordsman) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
    }
};

pub const Swordsman = struct {
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

    state: SwState = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    slashCd: f32 = 0,
    heavyCd: f32 = 0,
    lungeCd: f32 = 0,
    backCd: f32 = 0,
    crowd: f32 = 0,
    doubling: bool = false,

    hop: f32 = 0,
    hopDone: f32 = 0,
    hopDir: rl.Vector3 = mathx.zero3,

    heroHit: ?combat.Hit = null,
    dealt: bool = false,
    rec: Recover = .slash,

    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,

    bodyLean: f32 = 0,
    twist: f32 = 0,
    headPitch: f32 = 0,
    rsh: f32 = 0,
    rabd: f32 = 0,
    rel: f32 = 0,
    lsh: f32 = 0,
    lel: f32 = 0,
    tilt: f32 = 0,
    clasp: f32 = 0,
    springs: anim.SpringBank(CHAN_N) = .{},

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(SW_HP, SW_POISE, SW_STANCE).withRes(SW_RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [SW_NPART]foe.Particle = [_]foe.Particle{.{}} ** SW_NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(3),
    rng: mathx.Rng = mathx.Rng.init(5),

    wpnWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },

    parry: foe.Parry = .{},
    parried: bool = false,

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Swordsman {
        var k = Swordsman{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(SW_HP, SW_POISE, SW_STANCE).withRes(SW_RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 51103.0, 0x5A1);
        k.rng = foe.fxStream(seed, 22679.0, 0x5A2);
        k.springs.seat(SW_CARRY.chan());
        k.chanSet(SW_CARRY.chan());
        k.pose();
        k.wpnWas = k.bladeSeg();
        return k;
    }

    pub fn kind(_: *const Swordsman) wf.FoeKind {
        return .fungal_swordsman;
    }
    pub fn centerWorld(self: *const Swordsman) rl.Vector3 {
        return foe.bodyPoint(self.pos, SW_CENTER_F * H, self.scale, self.hop);
    }
    pub fn topWorld(self: *const Swordsman) rl.Vector3 {
        return foe.bodyPoint(self.pos, SW_TOP_F * H, self.scale, self.hop);
    }
    pub fn lockPoint(self: *const Swordsman) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], MARK_AT);
    }
    pub fn hurtRadius(self: *const Swordsman) f32 {
        return SW_HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Swordsman) f32 {
        return SW_BODY_R * self.scale;
    }
    pub fn alive(self: *const Swordsman) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Swordsman) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Swordsman) bool {
        return self.state == .stunlight or self.state == .stunheavy;
    }
    pub fn airborne(self: *const Swordsman) bool {
        return self.hop > foe.AIRBORNE_LIFT;
    }
    fn hopOf(self: *const Swordsman) f32 {
        return self.hop / self.scale;
    }
    pub fn flashFrac(self: *const Swordsman) f32 {
        return self.flash / foe.FLASH_DUR;
    }

    fn fdir(self: *const Swordsman) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Swordsman, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, SW_TURN_RATE, dt);
    }

    pub fn navWant(self: *const Swordsman, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .stride) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    pub fn bladeSeg(self: *const Swordsman) [2]rl.Vector3 {
        const grip = rl.math.vector3Transform(mathx.zero3, self.xf[HELD]);
        const tip = rl.math.vector3Transform(v3(0, SW_BLADE_LEN, 0), self.xf[HELD]);
        return .{ grip, tip };
    }

    fn chanGet(self: *const Swordsman) Chan {
        return chanOf(self);
    }
    fn chanSet(self: *Swordsman, c: Chan) void {
        setChan(self, c);
    }
    fn settlePose(self: *Swordsman, dt: f32) void {
        settle(self, dt);
    }

    fn enter(self: *Swordsman, s: SwState) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        if (s != .lunge and s != .back) {
            self.hop = 0;
            self.hopDone = 0;
        }
    }

    fn recoverAfter(self: *Swordsman, r: Recover) void {
        self.rec = r;
        self.enter(.recover);
    }

    pub fn update(self: *Swordsman, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.parried = false;
        self.heroHit = null;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Swordsman, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.slashCd = mathx.maxF(0, self.slashCd - dt);
        self.heavyCd = mathx.maxF(0, self.heavyCd - dt);
        self.lungeCd = mathx.maxF(0, self.lungeCd - dt);
        self.backCd = mathx.maxF(0, self.backCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= SW_SLASH_R) self.crowd += dt else self.crowd = mathx.maxF(0, self.crowd - dt * 1.6);

        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.chanSet(SW_CARRY.chan());
                _ = foe.postDrive(self, dt, bounds, SW_SPEED, d, AGGRO_R, SW_TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (self.t >= 0.12) self.decide(d, hero);
            },
            .stride => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = SW_SPEED;
                const moved = moveSpeed * dt * self.chill.travel();
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.chanSet(SW_CARRY.chan());
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= 0.22) self.decide(d, hero);
            },
            .slash_wind => {
                self.faceToward(hero, dt);
                self.chanSet(samplePose(&SW_SLASH_WIND_KEYS, mathx.clampF(self.t / SW_SLASH_WIND, 0, 1)));
                if (self.t >= SW_SLASH_WIND) {
                    sfx.world(.swing_heavy, self.pos);
                    self.enter(.slash);
                }
            },
            .slash => {
                self.faceToward(hero, dt * 0.33);
                self.chanSet(samplePose(&SW_SLASH_KEYS, mathx.clampF(self.t / SW_SLASH_DUR, 0, 1)));
                self.tryReach(hero);
                if (self.t >= SW_SLASH_DUR) {
                    if (self.doubling) {
                        sfx.world(.swing_light, self.pos);
                        self.enter(.slash2);
                    } else {
                        self.slashCd = SW_SLASH_CD;
                        self.recoverAfter(.slash);
                    }
                }
            },
            .slash2 => {
                self.chanSet(samplePose(&SW_SLASH2_KEYS, mathx.clampF(self.t / SW_SLASH_DUR, 0, 1)));
                self.tryReach(hero);
                if (self.t >= SW_SLASH_DUR) {
                    self.doubling = false;
                    self.slashCd = SW_SLASH_CD;
                    self.recoverAfter(.slash2);
                }
            },
            .heavy_wind => {
                self.faceToward(hero, dt);
                self.chanSet(samplePose(&SW_HEAVY_WIND_KEYS, mathx.clampF(self.t / SW_HEAVY_WIND, 0, 1)));
                if (self.t >= SW_HEAVY_WIND) {
                    sfx.world(.swing_heavy, self.pos);
                    self.enter(.heavy);
                }
            },
            .heavy => {
                self.chanSet(samplePose(&SW_HEAVY_KEYS, mathx.clampF(self.t / SW_HEAVY_DUR, 0, 1)));
                self.tryReach(hero);
                if (self.t >= SW_HEAVY_DUR) {
                    self.heavyCd = SW_HEAVY_CD;
                    self.recoverAfter(.heavy);
                }
            },
            .lunge_wind => {
                self.faceToward(hero, dt);
                self.chanSet(samplePose(&SW_LUNGE_WIND_KEYS, mathx.clampF(self.t / SW_LUNGE_WIND, 0, 1)));
                if (self.t >= SW_LUNGE_WIND) {
                    self.hopDir = self.fdir();
                    sfx.world(.swing_heavy, self.pos);
                    self.enter(.lunge);
                }
            },
            .lunge => {
                self.chanSet(samplePose(&SW_LUNGE_KEYS, mathx.clampF(self.t / SW_LUNGE_DUR, 0, 1)));
                const u = mathx.clampF(self.t / SW_LUNGE_DUR, 0, 1);
                const want = SW_LUNGE_DIST * (1.0 - (1.0 - u) * (1.0 - u)) * self.scale;
                mathx.stepXZ(&self.pos, self.hopDir, want - self.hopDone, bounds);
                self.hopDone = want;
                self.hop = SW_LUNGE_UP * mathx.sinf(u * std.math.pi) * self.scale;
                self.tryReach(hero);
                if (self.t >= SW_LUNGE_DUR) {
                    self.hop = 0;
                    self.lungeCd = SW_LUNGE_CD;
                    self.recoverAfter(.lunge);
                }
            },
            .back => {
                self.faceToward(hero, dt * 0.5);
                self.chanSet(samplePose(&SW_BACK_KEYS, mathx.clampF(self.t / (SW_BACK_DUR + SW_BACK_LAND), 0, 1)));
                const u = mathx.clampF(self.t / SW_BACK_DUR, 0, 1);
                const want = SW_BACK_DIST * (1.0 - (1.0 - u) * (1.0 - u)) * self.scale;
                mathx.stepXZ(&self.pos, self.hopDir, want - self.hopDone, bounds);
                self.hopDone = want;
                self.hop = SW_BACK_UP * mathx.sinf(u * std.math.pi) * self.scale;
                if (self.t >= SW_BACK_DUR + SW_BACK_LAND) {
                    self.hop = 0;
                    self.crowd = 0;
                    self.backCd = SW_BACK_CD;
                    self.decide(foe.senseHero(&self.leash, self.pos, hero, AGGRO_R), hero);
                }
            },
            .recover => {
                if (d <= AGGRO_R) self.faceToward(hero, dt * 0.55);
                const dur = self.rec.dur();
                self.chanSet(samplePose(self.rec.keys(), mathx.clampF(self.t / dur, 0, 1)));
                if (self.t >= dur) self.enter(.idle);
            },
            .stunlight, .stunheavy => {
                self.chanSet(SW_CARRY.chan());
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .dead => {
                foe.dissipate(self, dt, SW_DEATH_DUR, SW_DISS_DUR, SW_DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.settlePose(dt);
        self.wpnWas = self.bladeSeg();
        self.pose();
    }

    fn decide(self: *Swordsman, dist: f32, toward: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.stride);
        }
        self.homing = false;
        const f = mathx.dirXZ(self.pos, toward);
        const off = mathx.wrapPi(mathx.headingXZ(f) - self.facing);
        switch (swClassify(dist, off, self.slashCd <= 0, self.heavyCd <= 0, self.lungeCd <= 0, self.backCd <= 0, self.crowd >= SW_CROWD_HOLD)) {
            .slash => {
                self.doubling = self.rng.float() < SW_SLASH2_CHANCE;
                self.enter(.slash_wind);
            },
            .heavy => self.enter(.heavy_wind),
            .lunge => self.enter(.lunge_wind),
            .back => {
                if (foe.canLeap(&self.root)) {
                    self.hopDir = mathx.scaleV(f, -1.0);
                    self.enter(.back);
                } else {
                    self.crowd = 0;
                    self.enter(.idle);
                }
            },
            .close => {
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                const lat = mathx.scaleV(mathx.perpXZ(f), side * 0.22);
                self.moveDir = mathx.normV(mathx.addV(f, lat));
                self.enter(.stride);
            },
            .hold => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, self.home);
                    self.enter(.stride);
                } else self.enter(.idle);
            },
        }
    }

    fn toImpact(self: *const Swordsman) ?f32 {
        return switch (self.state) {
            .slash_wind => SW_SLASH_WIND - self.t + SW_SLASH_DUR * 0.46,
            .slash => SW_SLASH_DUR * 0.46 - self.t,
            .heavy_wind => SW_HEAVY_WIND - self.t + SW_HEAVY_DUR * 0.42,
            .heavy => SW_HEAVY_DUR * 0.42 - self.t,
            .lunge_wind => SW_LUNGE_WIND - self.t + SW_LUNGE_DUR * 0.30,
            .lunge => SW_LUNGE_DUR * 0.30 - self.t,
            else => null,
        };
    }

    /// **THE RETURN CUT IS NOT PARRYABLE AND THAT IS THE POINT OF IT** — `.slash2` is off the follow-through
    fn parryable(self: *const Swordsman) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(SW_KIT_R, self.scale) + SW_BLADE_LEN * self.scale * 0.5;
    }

    pub fn takeParry(self: *Swordsman) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.slashCd = SW_SLASH_CD;
        self.heavyCd = SW_HEAVY_CD;
        self.lungeCd = SW_LUNGE_CD;
        self.doubling = false;
        self.venom(self.bladeSeg()[1], 14);
        sfx.world(.duo_sword_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light, .none => self.enterStun(false),
        }
    }

    fn tryReach(self: *Swordsman, hero: rl.Vector3) void {
        if (self.dealt) return;
        const r = foe.hurtReach(SW_KIT_R, self.scale);
        if (!foe.weaponReaches(self.wpnWas, self.bladeSeg(), hero, r)) return;
        self.heroHit = switch (self.state) {
            .lunge => SW_LUNGE_HIT,
            .heavy => SW_HEAVY_HIT,
            else => SW_SLASH_HIT,
        };
        self.dealt = true;
        self.leash.noteCombat();
        self.venom(self.bladeSeg()[1], 7);
    }

    pub fn tryHit(self: *Swordsman, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SW_SHOVE);
        self.venom(s.contact, if (heavy) 10 else 5);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Swordsman, heavy: bool) void {
        if (self.state == .dead) return;
        sfx.world(.duo_sword_hurt, self.pos);
        self.enter(if (heavy) .stunheavy else .stunlight);
    }

    fn enterDeath(self: *Swordsman) void {
        if (self.state == .dead) return;
        sfx.world(.duo_sword_die, self.pos);
        self.justDied = true;
        self.enter(.dead);
    }

    pub fn stagger(self: *Swordsman, heavy: bool) void {
        if (self.state == .dead) return;
        self.enterStun(heavy);
    }

    pub fn markSlain(self: *Swordsman) void {
        self.vit.hp = 0;
        self.vit.dead = true;
        self.state = .dead;
        self.t = SW_DEATH_DUR + SW_DISS_DUR;
        self.fade = 1;
        self.gone = true;
    }

    fn venom(self: *Swordsman, at: rl.Vector3, n: usize) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .chaos, n, self.scale);
    }

    fn stunAmount(self: *const Swordsman) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t / combat.foeStunDur(false), false),
            .stunheavy => foe.stunCurve(self.t / combat.foeStunDur(true), true),
            else => 0,
        };
    }

    pub fn pose(self: *Swordsman) void {
        poseBody(self, SW_DEATH_DUR);
    }

    pub fn draw(self: *const Swordsman, model: *const SwModel) void {
        if (self.gone) return;
        model.draw(self);
    }
    pub fn drawFx(self: *const Swordsman) void {
        foe.drawParticles(&self.parts);
    }
};

const MG_PRESS_HOLD: f32 = 2.4;
const MG_PRESS_HP: f32 = 0.86;
/// `mgHarm` is 0 at the threshold the press clock starts at and 1 at nothing left: at full HP the caster owes
/// 2.4 s of being stood on and 9 s between blinks; at death's door 1.0 s and 4.0 s.
const MG_PRESS_RATE_HURT: f32 = 2.4;
const MG_FADE_CD_HURT: f32 = 4.0;

fn mgHarm(hpFrac: f32) f32 {
    return mathx.clampF((MG_PRESS_HP - hpFrac) / MG_PRESS_HP, 0, 1);
}

pub const MgModel = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) MgModel {
        return .{ .bone = mgBones(), .mat = gfx.material(shader, "fungal magus") };
    }
    pub fn setShader(self: *MgModel, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const MgModel, k: *const Magus) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
    }
};

pub const Magus = struct {
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

    state: MgState = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    orbCd: f32 = 0,
    sproutCd: f32 = 0,
    fadeCd: f32 = 0,
    press: f32 = 0,
    rec: MgRecover = .sprout,

    returnTo: rl.Vector3 = mathx.zero3,

    heroHit: ?combat.Hit = null,
    threw: bool = false,
    threwFrom: rl.Vector3 = mathx.zero3,
    sowed: bool = false,
    sowAt: rl.Vector3 = mathx.zero3,
    misted: bool = false,
    mistAt: rl.Vector3 = mathx.zero3,

    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,

    bodyLean: f32 = 0,
    twist: f32 = 0,
    headPitch: f32 = 0,
    rsh: f32 = 0,
    rabd: f32 = 0,
    rel: f32 = 0,
    lsh: f32 = 0,
    lel: f32 = 0,
    tilt: f32 = 0,
    clasp: f32 = 0,
    springs: anim.SpringBank(CHAN_N) = .{},

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(MG_HP, MG_POISE, MG_STANCE).withRes(MG_RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [MG_NPART]foe.Particle = [_]foe.Particle{.{}} ** MG_NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(7),
    rng: mathx.Rng = mathx.Rng.init(11),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Magus {
        var k = Magus{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(MG_HP, MG_POISE, MG_STANCE).withRes(MG_RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 63127.0, 0x7B1);
        k.rng = foe.fxStream(seed, 30011.0, 0x7B2);
        k.orbCd = 0.6 + seed * 1.2;
        k.springs.seat(MG_CARRY.chan());
        k.chanSet(MG_CARRY.chan());
        k.pose();
        return k;
    }

    pub fn kind(_: *const Magus) wf.FoeKind {
        return .fungal_magus;
    }
    pub fn centerWorld(self: *const Magus) rl.Vector3 {
        return foe.bodyPoint(self.pos, MG_CENTER_F * H, self.scale, 0);
    }
    pub fn topWorld(self: *const Magus) rl.Vector3 {
        return foe.bodyPoint(self.pos, MG_TOP_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Magus) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], MARK_AT);
    }
    pub fn hurtRadius(self: *const Magus) f32 {
        return MG_HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Magus) f32 {
        return MG_BODY_R * self.scale;
    }
    pub fn alive(self: *const Magus) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Magus) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Magus) bool {
        return self.state == .stunlight or self.state == .stunheavy;
    }
    pub fn airborne(_: *const Magus) bool {
        return false;
    }
    fn hopOf(_: *const Magus) f32 {
        return 0;
    }
    pub fn flashFrac(self: *const Magus) f32 {
        return self.flash / foe.FLASH_DUR;
    }

    pub fn absent(self: *const Magus) bool {
        return self.state == .gone;
    }

    pub fn hidden(self: *const Magus) bool {
        return self.absent();
    }
    pub fn phased(self: *const Magus) bool {
        return self.absent();
    }

    fn fdir(self: *const Magus) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Magus, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, MG_TURN_RATE, dt);
    }

    pub fn navWant(self: *const Magus, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    pub fn staffHead(self: *const Magus) rl.Vector3 {
        // The head knob sits 0.58 of the shaft over the mid-shaft grip (`staffMesh`).
        return rl.math.vector3Transform(v3(0, STAFF_LEN * 0.58 + 0.028 * H, 0), self.xf[HELD]);
    }

    fn chanGet(self: *const Magus) Chan {
        return chanOf(self);
    }
    fn chanSet(self: *Magus, c: Chan) void {
        setChan(self, c);
    }
    fn settlePose(self: *Magus, dt: f32) void {
        settle(self, dt);
    }

    fn enter(self: *Magus, s: MgState) void {
        self.state = s;
        self.t = 0;
    }

    fn recoverAfter(self: *Magus, r: MgRecover) void {
        self.rec = r;
        self.enter(.recover);
    }

    pub fn update(self: *Magus, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.threw = false;
        self.sowed = false;
        self.misted = false;
        self.heroHit = null;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        if (!self.absent()) self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Magus, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.orbCd = mathx.maxF(0, self.orbCd - dt);
        self.sproutCd = mathx.maxF(0, self.sproutCd - dt);
        self.fadeCd = mathx.maxF(0, self.fadeCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= MG_FLEE_R and self.vit.hpFrac() < MG_PRESS_HP) {
            self.press += dt * lerpF(1.0, MG_PRESS_RATE_HURT, mgHarm(self.vit.hpFrac()));
        } else self.press = mathx.maxF(0, self.press - dt * 1.2);

        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.chanSet(MG_CARRY.chan());
                _ = foe.postDrive(self, dt, bounds, MG_SPEED, d, AGGRO_R, MG_TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (self.t >= 0.16) self.decide(d, hero);
            },
            .drift => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = MG_SPEED;
                const moved = moveSpeed * dt * self.chill.travel();
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.chanSet(MG_CARRY.chan());
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= MG_DRIFT_DUR) self.decide(d, hero);
            },
            .orb_wind => {
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / MG_ORB_WIND, 0, 1);
                self.chanSet(samplePose(&MG_ORB_WIND_KEYS, u));
                self.kindle(dt, u);
                if (self.t >= MG_ORB_WIND) self.enter(.orb_throw);
            },
            .orb_throw => {
                if (self.t < MG_ORB_DUR * MG_ORB_RELEASE_K) self.faceToward(hero, dt * 0.4);
                self.chanSet(samplePose(&MG_ORB_KEYS, mathx.clampF(self.t / MG_ORB_DUR, 0, 1)));
                const at = MG_ORB_DUR * MG_ORB_RELEASE_K;
                if (self.t - dt < at and self.t >= at) {
                    self.threw = true;
                    self.threwFrom = self.staffHead();
                    sfx.world(.duo_orb, self.pos);
                }
                if (self.t >= MG_ORB_DUR) {
                    self.orbCd = MG_ORB_CD;
                    self.recoverAfter(.orb);
                }
            },
            .sprout_wind => {
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / MG_SPROUT_WIND, 0, 1);
                self.chanSet(samplePose(&MG_SPROUT_WIND_KEYS, u));
                self.kindle(dt, u * 1.4);
                if (self.t >= MG_SPROUT_WIND) self.enter(.sprout);
            },
            .sprout => {
                self.chanSet(samplePose(&MG_SPROUT_KEYS, mathx.clampF(self.t / MG_SPROUT_DUR, 0, 1)));
                const at = MG_SPROUT_DUR * 0.42;
                if (self.t - dt < at and self.t >= at) {
                    self.sowed = true;
                    self.sowAt = mathx.ground(hero.x, hero.z);
                    self.sowAt.y = hero.y;
                    sfx.world(.duo_sprout, self.pos);
                }
                if (self.t >= MG_SPROUT_DUR) {
                    self.sproutCd = MG_SPROUT_CD;
                    self.recoverAfter(.sprout);
                }
            },
            .recover => {
                if (d <= AGGRO_R) self.faceToward(hero, dt * 0.6);
                self.chanSet(samplePose(self.rec.keys(), mathx.clampF(self.t / MG_REC, 0, 1)));
                if (self.t >= MG_REC) self.enter(.idle);
            },
            .fade_out => {
                const u = mathx.clampF(self.t / MG_FADE_OUT, 0, 1);
                self.chanSet(samplePose(&MG_FADE_KEYS, u));
                self.fade = u;
                self.shed(dt, u);
                if (self.t >= MG_FADE_OUT) {
                    self.misted = true;
                    self.mistAt = self.pos;
                    self.fade = 1;
                    self.enter(.gone);
                }
            },
            .gone => {
                self.fade = 1;
                if (self.t >= MG_GONE_DUR) {
                    self.pos = self.returnTo;
                    self.pos.x = mathx.clampF(self.pos.x, -bounds, bounds);
                    self.pos.z = mathx.clampF(self.pos.z, -bounds, bounds);
                    self.facing = mathx.headingXZ(mathx.dirXZ(self.pos, hero));
                    self.enter(.fade_in);
                    sfx.world(.duo_bloom, self.pos);
                }
            },
            .fade_in => {
                const u = mathx.clampF(self.t / MG_FADE_IN, 0, 1);
                self.chanSet(samplePose(&MG_FADE_KEYS, 1.0 - u));
                self.fade = 1.0 - u;
                self.shed(dt, 1.0 - u);
                if (self.t >= MG_FADE_IN) {
                    self.fade = 0;
                    self.press = 0;
                    self.fadeCd = lerpF(MG_FADE_CD, MG_FADE_CD_HURT, mgHarm(self.vit.hpFrac()));
                    self.enter(.idle);
                }
            },
            .stunlight, .stunheavy => {
                self.chanSet(MG_CARRY.chan());
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .dead => {
                foe.dissipate(self, dt, MG_DEATH_DUR, MG_DISS_DUR, MG_DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.settlePose(dt);
        self.pose();
    }

    fn decide(self: *Magus, dist: f32, toward: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.drift);
        }
        self.homing = false;
        const f = mathx.dirXZ(self.pos, toward);
        const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
        const lat = mathx.scaleV(mathx.perpXZ(f), side);
        switch (mgClassify(dist, self.orbCd <= 0, self.sproutCd <= 0, self.fadeCd <= 0, self.press >= MG_PRESS_HOLD)) {
            .orb => self.enter(.orb_wind),
            .sprout => self.enter(.sprout_wind),
            .vanish => {
                const a = self.rng.angle();
                const away = v3(mathx.cosf(a), 0, mathx.sinf(a));
                self.returnTo = mathx.addV(self.pos, mathx.scaleV(away, MG_REAPPEAR_R));
                self.returnTo.y = self.pos.y;
                self.enter(.fade_out);
                sfx.world(.duo_fade, self.pos);
            },
            .back => {
                self.moveDir = mathx.normV(mathx.addV(mathx.scaleV(f, -1.0), mathx.scaleV(lat, 0.5)));
                self.enter(.drift);
            },
            .keep => {
                self.moveDir = if (dist > MG_KEEP_R)
                    mathx.normV(mathx.addV(f, mathx.scaleV(lat, 0.35)))
                else
                    lat;
                self.enter(.drift);
            },
            .hold => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, self.home);
                    self.enter(.drift);
                } else self.enter(.idle);
            },
        }
    }

    fn kindle(self: *Magus, dt: f32, u: f32) void {
        const n = foe.emitTicks(&self.fxAccum, dt, lerpF(6.0, 34.0, u * u), 6);
        if (n == 0) return;
        elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, self.staffHead(), .chaos, n, 0.22 * (0.4 + 0.6 * u) * self.scale, self.scale);
    }

    fn shed(self: *Magus, dt: f32, u: f32) void {
        const n = foe.emitTicks(&self.fxAccum, dt, lerpF(4.0, 26.0, u), 6);
        if (n == 0) return;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, self.centerWorld(), v3(0, -1, 0), .chaos, n, self.scale);
    }

    pub fn tryHit(self: *Magus, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, MG_SHOVE);
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, s.contact, v3(0, 1, 0), .chaos, if (heavy) 10 else 5, self.scale);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Magus, heavy: bool) void {
        if (self.state == .dead) return;
        if (self.state == .fade_out or self.state == .fade_in) {
            self.fade = 0;
            self.press = 0;
            self.fadeCd = MG_FADE_CD;
        }
        sfx.world(.duo_magus_hurt, self.pos);
        self.enter(if (heavy) .stunheavy else .stunlight);
    }

    fn enterDeath(self: *Magus) void {
        if (self.state == .dead) return;
        self.fade = 0;
        sfx.world(.duo_magus_die, self.pos);
        self.justDied = true;
        self.enter(.dead);
    }

    pub fn markSlain(self: *Magus) void {
        self.vit.hp = 0;
        self.vit.dead = true;
        self.state = .dead;
        self.t = MG_DEATH_DUR + MG_DISS_DUR;
        self.fade = 1;
        self.gone = true;
    }

    pub fn stagger(self: *Magus, heavy: bool) void {
        if (self.state == .dead) return;
        self.enterStun(heavy);
    }

    fn stunAmount(self: *const Magus) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t / combat.foeStunDur(false), false),
            .stunheavy => foe.stunCurve(self.t / combat.foeStunDur(true), true),
            else => 0,
        };
    }

    pub fn pose(self: *Magus) void {
        poseBody(self, MG_DEATH_DUR);
    }

    pub fn draw(self: *const Magus, model: *const MgModel) void {
        if (self.gone or self.fade >= 0.98) return;
        model.draw(self);
    }
    pub fn drawFx(self: *const Magus) void {
        foe.drawParticles(&self.parts);
    }
};

fn poseBody(self: anytype, deathDur: f32) void {
    const fs = foe.rigScale(self.scale, self.fade);
    const sink = foe.rigSink(0.46, self.scale, self.fade);
    const facingDeg = mathx.degrees(self.facing);
    const hipY = self.rest[ROOT].y;

    const dead = self.state == .dead;
    const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / deathDur, 0, 1)) else 0;
    const stun = self.stunAmount();
    const m = self.moving * (1.0 - dk);
    const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);

    var wx: [N]rl.Matrix = undefined;
    const collapse = lerpF(hipY, 0.18 * H, dk);
    const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip + self.hopOf();
    wx[ROOT] = mathx.mul(mathx.scaleM(fs, fs, fs), mathx.mul3(
        mathx.mul3(mathx.rz(9.0 * dk), mathx.rx(22.0 * dk), mathx.ry(pel.prot)),
        mathx.mul(mathx.tr(pel.sway * fs, pelvY * fs + sink, 0), mathx.ry(facingDeg)),
        heromod.rootAt(self.pos),
    ));

    if (!dead) {
        heromod.legPair(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, HIPL, KNEEL, HIPR, KNEER, SOLES);
    }

    const rest = self.rest;
    const twoPi = std.math.tau;
    const wonk = (self.seed - 0.5) * 5.5;
    const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
    const swayArg = self.elapsed * (0.5 + 0.2 * (0.5 + 0.5 * mathx.sinf(self.seed * 29.3))) + self.seed * 6.28;
    const swy = mathx.sinf(swayArg) * idleAmt;
    const swyLag = mathx.sinf(swayArg - 0.9) * idleAmt;

    const nod = 1.7 * mathx.cosf(2.0 * twoPi * self.phase) * m;
    const lean = self.bodyLean - 24.0 * stun + 28.0 * dk;
    setLocal(&wx, SPINE, rest, mathx.mul3(
        mathx.rx(lean * 0.40 + nod + 0.7 * swy),
        mathx.ry(-0.35 * pel.prot + self.twist * 0.40),
        mathx.rz(wonk * 0.5 + 1.0 * swy),
    ));
    setLocal(&wx, CHEST, rest, mathx.mul3(
        mathx.rx(lean * 0.60 + nod * 0.6 + 0.6 * swyLag),
        mathx.ry(-0.5 * pel.prot + self.twist * 0.60),
        mathx.rz(-wonk * 0.3 - 0.7 * swyLag),
    ));
    setLocal(&wx, NECK, rest, mathx.rx(self.headPitch * 0.30 + 8.0 * dk - 6.0 * stun));
    setLocal(&wx, HEAD, rest, mathx.mul3(
        mathx.rx(self.headPitch * 0.70 + 16.0 * dk - 30.0 * stun),
        mathx.ry(-0.5 * pel.prot),
        mathx.rz(wonk * 1.2 - 1.1 * swyLag - 0.8 * nod),
    ));

    if (dead) heromod.deadLegs(&wx, rest, dk);

    const armStun = -56.0 * stun;
    const busy = mathx.clampF(mathx.smoothstep(10.0, 46.0, @abs(self.rsh)), 0, 1);
    const swing = 12.0 * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) * (1.0 - busy);
    setLocal(&wx, SHR, rest, mathx.mul3(mathx.rz(self.clasp), mathx.rx(-(self.rsh - swing + armStun - 24.0 * dk)), mathx.rz(-(self.rabd + wonk * 0.4))));
    setLocal(&wx, ELR, rest, mathx.rx(-(self.rel + wonk * 0.6)));
    setLocal(&wx, WRR, rest, mathx.rz(-8.0));
    setLocal(&wx, SHL, rest, mathx.mul3(mathx.rz(-self.clasp), mathx.rx(-(self.lsh + swing + armStun - 24.0 * dk)), mathx.rz(self.rabd * 0.35 + wonk * 0.4)));
    setLocal(&wx, ELL, rest, mathx.rx(-(self.lel - wonk * 0.6)));
    setLocal(&wx, WRL, rest, mathx.rz(8.0));

// After the fit, `tilt` is degrees the kit leads FORWARD of the forearm — 0 down, 90 level, 180 on end. Measured
// in the forearm's frame instead, a `tilt` of 94 put the point 3.73 m up and the whole stroke reached 1.85 m on a
// body carrying 2.17 m of sword.
    setLocal(&wx, HELD, rest, heromod.staffFit(self.tilt - (self.rsh - swing)));
    self.xf = wx;
}

/// A staff is shoulder-tall on the body carrying it: measured off the posed grip at 1.27 m, 1.05·H stood the head 3.67 m up over a 2.42 m creature.
pub const STAFF_LEN: f32 = 0.86 * H;

comptime {
    std.debug.assert(STAFF_LEN > 0.60 * H and STAFF_LEN < 1.0 * H);
}

fn swBones() [N]rl.Mesh {
    var b: [N]rl.Mesh = undefined;
    b[ROOT] = swPelvis();
    b[SPINE] = swLumbar();
    b[CHEST] = swChest();
    b[NECK] = neckMesh();
    b[HEAD] = swHead();
    b[HIPL] = thighMesh(0x11);
    b[KNEEL] = shinMesh(0x12);
    b[ANKL] = footMesh(1.0);
    b[HIPR] = thighMesh(0x13);
    b[KNEER] = shinMesh(0x14);
    b[ANKR] = footMesh(-1.0);
    b[SHL] = upperArmMesh(1.0);
    b[ELL] = forearmMesh(1.0);
    b[WRL] = handMesh(1.0);
    b[SHR] = upperArmMesh(-1.0);
    b[ELR] = forearmMesh(-1.0);
    b[WRR] = handMesh(-1.0);
    b[HELD] = swordMesh();
    return b;
}

fn mgBones() [N]rl.Mesh {
    var b: [N]rl.Mesh = undefined;
    b[ROOT] = mgPelvis();
    b[SPINE] = mgLumbar();
    b[CHEST] = mgChest();
    b[NECK] = neckMesh();
    b[HEAD] = mgHead();
    b[HIPL] = thighMesh(0x21);
    b[KNEEL] = shinMesh(0x22);
    b[ANKL] = footMesh(1.0);
    b[HIPR] = thighMesh(0x23);
    b[KNEER] = shinMesh(0x24);
    b[ANKR] = footMesh(-1.0);
    b[SHL] = upperArmMesh(1.0);
    b[ELL] = forearmMesh(1.0);
    b[WRL] = handMesh(1.0);
    b[SHR] = upperArmMesh(-1.0);
    b[ELR] = forearmMesh(-1.0);
    b[WRR] = handMesh(-1.0);
    b[HELD] = staffMesh();
    return b;
}

fn limb(b: *Builder, len: f32, r0: f32, r1: f32, belly: f32, col: rl.Color, dk: rl.Color) void {
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), r0, r1, 8, col);
    b.addBlob(v3(0, -len * 0.38, r0 * 0.18), v3(r0 * belly, len * 0.30, r0 * belly * 0.92), 7, 6, col);
    b.addBlob(v3(0, -r0 * 0.10, 0), v3(r0 * 1.02, r0 * 0.78, r0 * 1.02), 7, 6, dk);
}

fn shelf(b: *Builder, at: rl.Vector3, ang: f32, out: f32, thick: f32, col: rl.Color) void {
    const c = mathx.cosf(ang);
    const sn = mathx.sinf(ang);
    const mid = v3(at.x + c * out * 0.55, at.y, at.z + sn * out * 0.55);
    const wide = out * (0.58 + 0.42 * @abs(c));
    const deep = out * (0.58 + 0.42 * @abs(sn));
    b.addBlob(mid, v3(wide, thick, deep), 3, 9, col);
    b.addBlob(v3(mid.x, mid.y - thick * 0.85, mid.z), v3(wide * 0.86, thick * 0.42, deep * 0.86), 3, 8, GILL);
}

fn crust(b: *Builder, rng: *mathx.Rng, at: rl.Vector3, r: rl.Vector3, n: u32, col: rl.Color) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const t = rng.range(-0.8, 0.9);
        const sz = rng.range(0.13, 0.30);
        b.addBlob(
            v3(at.x + mathx.cosf(a) * r.x * 0.94, at.y + t * r.y * 0.72, at.z + mathx.sinf(a) * r.z * 0.94),
            v3(r.x * sz, r.y * sz * rng.range(0.35, 0.75), r.z * sz * 0.55),
            5,
            4,
            col,
        );
    }
}

fn swPelvis() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1188);
    b.setMat(.skin);
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.122 * H, 0.082 * H, 0.098 * H), 9, 7, RIND);
    b.addBlob(v3(0, 0.030 * H, 0.006 * H), v3(0.114 * H, 0.020 * H, 0.094 * H), 8, 6, RIND_DK);
    b.setMat(.cloth);
    b.addSkirt(v3(0, 0.010 * H, 0), 0.118 * H, 0.180 * H, 0.150 * H, 0.012 * H, 11, RIND_DK, &rng);
    b.setMat(.skin);
    crust(&b, &rng, v3(0, 0, 0), v3(0.122 * H, 0.082 * H, 0.098 * H), 5, WART);
    return b.toMesh();
}

fn swLumbar() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.092 * H, 0), 0.104 * H, 0.118 * H, 9, RIND);
    return b.toMesh();
}

fn swChest() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x51A7);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.050 * H, 0.004 * H), v3(0.156 * H, 0.112 * H, 0.120 * H), 10, 8, RIND);
    b.addBlob(v3(0, -0.008 * H, 0.014 * H), v3(0.134 * H, 0.070 * H, 0.108 * H), 9, 7, RIND_LT);
    var i: u32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        const back = 0.5 - 0.5 * mathx.sinf(a);
        const tier = rng.range(0.02, 0.13) * H;
        shelf(
            &b,
            v3(0, 0.030 * H + tier, 0),
            a,
            (0.10 + 0.13 * back) * H * rng.range(0.82, 1.15),
            rng.range(0.012, 0.026) * H,
            if (rng.float() < 0.35) RIND_DK else RIND,
        );
    }
    shelf(&b, v3(0, 0.006 * H, 0), mathx.radians(196.0), 0.20 * H, 0.030 * H, RIND_DK);
    crust(&b, &rng, v3(0, 0.040 * H, 0), v3(0.150 * H, 0.106 * H, 0.116 * H), 7, WART);
    return b.toMesh();
}

fn swHead() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x6C21);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.052 * H, 0.020 * H), v3(0.132 * H, 0.030 * H, 0.118 * H), 4, 10, RIND);
    b.addBlob(v3(0, 0.074 * H, -0.008 * H), v3(0.096 * H, 0.026 * H, 0.086 * H), 4, 9, RIND_DK);
    b.addBlob(v3(0, 0.026 * H, 0.026 * H), v3(0.086 * H, 0.030 * H, 0.078 * H), 6, 8, GILL);
    b.addBlob(v3(0, 0.010 * H, 0.006 * H), v3(0.062 * H, 0.028 * H, 0.058 * H), 6, 7, GILL);
    b.setMat(.plain);
    b.addBlob(v3(0.026 * H, 0.028 * H, 0.048 * H), v3(0.011 * H, 0.009 * H, 0.009 * H), 5, 5, EYE);
    b.addBlob(v3(-0.024 * H, 0.026 * H, 0.048 * H), v3(0.010 * H, 0.009 * H, 0.009 * H), 5, 5, EYE);
    b.setMat(.skin);
    var w: u32 = 0;
    while (w < 6) : (w += 1) {
        const a = rng.range(-2.2, 2.2);
        b.addBlob(
            v3(mathx.sinf(a) * 0.104 * H, 0.062 * H, -0.030 * H + mathx.cosf(a) * 0.030 * H),
            v3(0.020 * H, rng.range(0.010, 0.024) * H, 0.016 * H),
            5,
            4,
            CAP_DK,
        );
    }
    return b.toMesh();
}

fn mgPelvis() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4411);
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.116 * H, 0.080 * H, 0.096 * H), 9, 7, MYC);
    b.addBlob(v3(0, 0.028 * H, 0.004 * H), v3(0.110 * H, 0.018 * H, 0.092 * H), 8, 6, MYC_DK);
    b.addSkirt(v3(0, 0.014 * H, 0), 0.112 * H, 0.260 * H, 0.164 * H, 0.010 * H, 13, MYC_DK, &rng);
    b.addSkirt(v3(0, -0.030 * H, 0), 0.104 * H, 0.150 * H, 0.132 * H, 0.009 * H, 9, GILL, &rng);
    return b.toMesh();
}

fn mgLumbar() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.090 * H, 0), 0.100 * H, 0.112 * H, 9, MYC);
    return b.toMesh();
}

fn mgChest() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x77C3);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.048 * H, 0.004 * H), v3(0.144 * H, 0.106 * H, 0.116 * H), 10, 8, MYC);
    b.addBlob(v3(0, -0.006 * H, 0.012 * H), v3(0.126 * H, 0.066 * H, 0.104 * H), 9, 7, MYC_DK);
    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const rr = 0.118 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.092 * H + rng.range(-0.008, 0.020) * H, mathx.sinf(a) * rr * 0.9),
            v3(rng.range(0.020, 0.040) * H, rng.range(0.024, 0.048) * H, 0.014 * H),
            5,
            4,
            if (rng.float() < 0.4) GILL else MYC_DK,
        );
    }
    return b.toMesh();
}

/// At 0.132 of H the cap was a smooth ball sitting on the shoulders; the mushroom mage's own rim is 0.200 — the read is the OVERHANG and the dark ring under it.
const MG_RIM: f32 = 0.196 * H;

comptime {
    std.debug.assert(MG_RIM > SHOULDER_HALF * 1.35 and MG_RIM < SHOULDER_HALF * 2.4);
}

fn mgHead() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3B90);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.062 * H, 0), v3(MG_RIM, 0.070 * H, MG_RIM * 0.94), 12, 9, CAP_COL);
    b.addBlob(v3(0.012 * H, 0.098 * H, -0.010 * H), v3(MG_RIM * 0.58, 0.044 * H, MG_RIM * 0.55), 9, 7, CAP_COL);
    b.addBlob(v3(0, 0.030 * H, 0.002 * H), v3(MG_RIM * 0.92, 0.020 * H, MG_RIM * 0.87), 11, 7, GILL);
    b.addBlob(v3(0, 0.006 * H, 0.030 * H), v3(MG_RIM * 0.44, 0.030 * H, MG_RIM * 0.32), 7, 6, GILL);
    b.setMat(.plain);
    b.addBlob(v3(0.028 * H, 0.008 * H, MG_RIM * 0.52), v3(0.013 * H, 0.011 * H, 0.010 * H), 5, 5, EYE);
    b.addBlob(v3(-0.028 * H, 0.006 * H, MG_RIM * 0.52), v3(0.012 * H, 0.010 * H, 0.010 * H), 5, 5, EYE);
    b.setMat(.skin);
    var w: u32 = 0;
    while (w < 13) : (w += 1) {
        const a = rng.angle();
        const rr = rng.range(0.18, 0.86) * MG_RIM;
        const sz = rng.range(0.09, 0.19) * MG_RIM;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.078 * H + 0.034 * H * (1.0 - rr / MG_RIM), mathx.sinf(a) * rr * 0.94),
            v3(sz, sz * 0.44, sz),
            5,
            4,
            CAP_DK,
        );
    }
    b.addBlob(v3(-MG_RIM * 0.74, 0.046 * H, -MG_RIM * 0.52), v3(MG_RIM * 0.26, 0.020 * H, MG_RIM * 0.22), 5, 4, CAP_DK);
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.010 * H, 0), v3(0, 0.026 * H, 0), 0.062 * H, 0.070 * H, 8, GILL);
    return b.toMesh();
}

fn thighMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    limb(&b, 0.196 * H, 0.062 * H, 0.050 * H, 1.18, RIND_DK, RIND);
    crust(&b, &rng, v3(0, -0.098 * H, 0), v3(0.062 * H, 0.098 * H, 0.062 * H), 3, MYC_DK);
    return b.toMesh();
}

fn shinMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    limb(&b, 0.186 * H, 0.048 * H, 0.036 * H, 1.22, RIND_DK, RIND);
    crust(&b, &rng, v3(0, -0.080 * H, 0), v3(0.048 * H, 0.086 * H, 0.048 * H), 3, MYC_DK);
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(side * 0.004 * H, -0.014 * H, 0.036 * H), v3(0.050 * H, 0.026 * H, 0.088 * H), 7, 6, RIND_DK);
    return b.toMesh();
}

fn upperArmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x2A11 else 0x2A22);
    b.setMat(.skin);
    limb(&b, 0.152 * H, 0.048 * H, 0.040 * H, 1.20, RIND, RIND_DK);
    crust(&b, &rng, v3(0, -0.076 * H, 0), v3(0.048 * H, 0.076 * H, 0.048 * H), 2, WART);
    return b.toMesh();
}

fn forearmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x3B11 else 0x3B22);
    b.setMat(.skin);
    limb(&b, 0.140 * H, 0.040 * H, 0.032 * H, 1.16, RIND, RIND_DK);
    crust(&b, &rng, v3(0, -0.070 * H, 0), v3(0.040 * H, 0.070 * H, 0.040 * H), 2, WART);
    return b.toMesh();
}

fn handMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(side * 0.004 * H, -0.028 * H, 0), v3(0.032 * H, 0.040 * H, 0.026 * H), 6, 5, FLESH);
    return b.toMesh();
}

fn swordMesh() rl.Mesh {
    var b = Builder.init();
// `Mat.steel`'s specular is catastrophic on a FACE — a blinding `pow(nh,96)` however dark it was authored, so
// dropping the albedo from 104 to 58 changed nothing on screen.
    b.setMat(.plain);
    const half = 0.030 * H;
    inline for (.{ .{ 0.00, 0.42, 1.00 }, .{ 0.42, 0.78, 0.84 }, .{ 0.78, 1.00, 0.62 } }) |seg| {
        const y0 = SW_BLADE_LEN * seg[0];
        const y1 = SW_BLADE_LEN * seg[1];
        b.addCube(v3(0, (y0 + y1) * 0.5, 0), v3(half * 2.0 * seg[2], y1 - y0, half * 0.50), STEEL);
    }
    b.addCube(v3(0, SW_BLADE_LEN * 0.48, 0), v3(half * 0.78, SW_BLADE_LEN * 0.90, half * 0.62), STEEL_DK);
    b.addCube(v3(0, SW_BLADE_LEN + 0.026 * H, 0), v3(half * 0.62, 0.058 * H, half * 0.40), STEEL);
    b.setMat(.steel);
    b.addCube(v3(0, 0, 0), v3(0.150 * H, 0.022 * H, 0.030 * H), STEEL_DK);
    b.addBlob(v3(0, -0.116 * H, 0), v3(0.026 * H, 0.024 * H, 0.026 * H), 6, 5, STEEL_DK);
    b.setMat(.plain);
    b.setMat(.leather);
    b.addCapsule(v3(0, -0.014 * H, 0), v3(0, -0.104 * H, 0), 0.022 * H, 0.026 * H, 7, RIND_DK);
    b.setMat(.plain);
    var i: u32 = 0;
    while (i < 11) : (i += 1) {
        const t = 0.08 + 0.082 * @as(f32, @floatFromInt(i));
        b.addBlob(v3(0, SW_BLADE_LEN * t, half * 0.30), v3(half * 0.16, half * 0.50, half * 0.12), 4, 4, VENOM);
    }
    return b.toMesh();
}

/// The shaft spans −0.55..+0.45 of its length about the HELD origin, ferrule near the butt.
fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x2E6D);
    const top = STAFF_LEN * 0.58;
    const foot = -STAFF_LEN * 0.42;
    b.setMat(.bark);
    b.addCapsule(v3(0, foot, 0), v3(0, top * 0.72, 0.012 * H), 0.021 * H, 0.026 * H, 7, RIND_DK);
    b.addCapsule(v3(0, top * 0.72, 0.012 * H), v3(0, top, -0.006 * H), 0.026 * H, 0.020 * H, 7, RIND_DK);
    b.addBlob(v3(0, foot, 0), v3(0.026 * H, 0.020 * H, 0.026 * H), 4, 6, CAP_DK);
    b.addCapsule(v3(0, -0.050 * H, 0), v3(0, 0.062 * H, 0), 0.031 * H, 0.031 * H, 7, CAP_DK);
    b.setMat(.skin);
    b.addBlob(v3(0, top + 0.028 * H, -0.006 * H), v3(0.070 * H, 0.052 * H, 0.066 * H), 8, 7, CAP_COL);
    b.addBlob(v3(0, top + 0.004 * H, -0.006 * H), v3(0.058 * H, 0.016 * H, 0.054 * H), 7, 6, GILL);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const t = rng.range(-0.30, 0.42);
        const a = rng.angle();
        b.addBlob(
            v3(mathx.cosf(a) * 0.020 * H, STAFF_LEN * t, mathx.sinf(a) * 0.020 * H),
            v3(0.020 * H, 0.012 * H, 0.020 * H),
            5,
            4,
            CAP_DK,
        );
    }
    return b.toMesh();
}

pub fn orbMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.flame);
    // A CORE INSIDE A SKIN: at one blob on 90 alpha the whole thing was a smear the ground showed through.
    b.addBlob(mathx.zero3, v3(ORB_R, ORB_R, ORB_R), 8, 7, mathx.withAlpha(CHAOS_EDGE, 120));
    b.addBlob(mathx.zero3, v3(ORB_R * 0.62, ORB_R * 0.62, ORB_R * 0.62), 7, 6, mathx.withAlpha(CHAOS_CORE, 235));
    return b.toModel(shader);
}



const SW_CAP: usize = wf.MAX_PER_KIND;
const MG_CAP: usize = wf.MAX_PER_KIND;

pub const Vanguard = struct {
    model: SwModel,
    men: [SW_CAP]Swordsman = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Vanguard {
        return .{ .model = SwModel.init(shader) };
    }
    pub fn setShader(self: *Vanguard, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn live(self: *Vanguard) []Swordsman {
        return self.men[0..self.n];
    }
    pub fn liveConst(self: *const Vanguard) []const Swordsman {
        return self.men[0..self.n];
    }
    pub fn reset(self: *Vanguard, m: *const wf.Map) void {
        foe.resetGroup(Swordsman, &self.men, &self.n, m, .fungal_swordsman);
    }
    pub fn update(self: *Vanguard, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Vanguard, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Vanguard) void {
        for (self.liveConst()) |*k| k.drawFx();
    }
    pub fn pierce(self: *Vanguard, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn setParry(self: *Vanguard, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Vanguard) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn anyDied(self: *const Vanguard) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Vanguard) u32 {
        return foe.soulsDropped(self.liveConst(), SW_SOULS);
    }
    pub fn totalHits(self: *const Vanguard) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Vanguard) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

pub const Conclave = struct {
    model: MgModel,
    orbModel: rl.Model,
    magi: [MG_CAP]Magus = undefined,
    n: usize = 0,

    orbs: [ORB_N]Orb = [_]Orb{.{}} ** ORB_N,
    caps: [CAP_N]Cap = [_]Cap{.{}} ** CAP_N,
    mists: [MIST_N]Mist = [_]Mist{.{}} ** MIST_N,
    soak: foe.Soak = .{},

    parts: [DUO_PARTS]foe.Particle = [_]foe.Particle{.{}} ** DUO_PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0xD00),

    pub fn init(shader: rl.Shader) Conclave {
        return .{ .model = MgModel.init(shader), .orbModel = orbMesh(shader) };
    }
    pub fn setShader(self: *Conclave, sh: rl.Shader) void {
        self.model.setShader(sh);
        self.orbModel.materials[0].shader = sh;
    }
    pub fn live(self: *Conclave) []Magus {
        return self.magi[0..self.n];
    }
    pub fn liveConst(self: *const Conclave) []const Magus {
        return self.magi[0..self.n];
    }
    pub fn reset(self: *Conclave, m: *const wf.Map) void {
        self.clearGround();
        foe.resetGroup(Magus, &self.magi, &self.n, m, .fungal_magus);
    }

    pub fn clear(self: *Conclave) void {
        self.n = 0;
        self.clearGround();
    }

    fn clearGround(self: *Conclave) void {
        self.orbs = [_]Orb{.{}} ** ORB_N;
        self.caps = [_]Cap{.{}} ** CAP_N;
        self.mists = [_]Mist{.{}} ** MIST_N;
        self.soak = .{};
    }

    pub fn update(self: *Conclave, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var worst: ?foe.Blow = null;
        for (self.live()) |*k| {
            if (k.update(dt, k.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&worst, h, k.pos, &k.threat);
            if (k.threw) self.launchOrb(k.threwFrom, k.threat.aim(hero), k.pos.y);
            if (k.sowed) self.sow(k.sowAt);
            if (k.misted) self.mist(k.mistAt);
        }
        self.tickOrbs(dt, hero, &worst);
        self.tickCaps(dt, hero, &worst);
        for (&self.mists) |*g| {
            if (!g.live) continue;
            g.t += dt;
            if (g.t >= MIST_LIFE) g.live = false;
        }
        foe.tickParticles(&self.parts, dt, hero.y);
        return worst;
    }

    pub fn breath(self: *Conclave, at: rl.Vector3, dt: f32) f32 {
        var inside = false;
        for (&self.mists) |*g| {
            if (g.covers(at)) inside = true;
        }
        return self.soak.step(inside, dt, MIST_BUILD);
    }

    fn launchOrb(self: *Conclave, from: rl.Vector3, at: rl.Vector3, floor: f32) void {
        for (&self.orbs) |*o| {
            if (o.live) continue;
            const to = foe.heroChest(at);
            o.* = .{ .live = true, .at = from, .vel = mathx.scaleV(mathx.normV(mathx.subV(to, from)), ORB_SPEED), .spin = self.fxRng.angle(), .floor = floor };
            return;
        }
    }

    fn tickOrbs(self: *Conclave, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        for (&self.orbs) |*o| {
            if (!o.live) continue;
            o.t += dt;
            o.at = mathx.addV(o.at, mathx.scaleV(o.vel, dt));
            o.spin += dt * 9.0;
            const chest = foe.heroChest(hero);
            if (mathx.lenV(mathx.subV(o.at, chest)) <= ORB_R + foe.HERO_R) {
                o.live = false;
                self.splashAt(o.at, 9);
                foe.worseBlow(worst, ORB_HIT, o.at, &GROUND_THREAT);
                continue;
            }
            if (o.t >= ORB_LIFE or foe.landed(o.at.y, o.floor, hero.y)) {
                o.live = false;
                self.splashAt(o.at, 9);
            }
        }
    }

    fn sow(self: *Conclave, at: rl.Vector3) void {
        var placed: usize = 0;
        var tries: usize = 0;
        while (placed < MG_BUNCH and tries < MG_BUNCH * 4) : (tries += 1) {
            const a = self.fxRng.angle();
            const r = self.fxRng.range(MG_BUNCH_R * 0.25, MG_BUNCH_R);
            const spot = v3(at.x + mathx.cosf(a) * r, at.y, at.z + mathx.sinf(a) * r);
            for (&self.caps) |*c| {
                if (c.live) continue;
                c.* = .{ .live = true, .at = spot, .r = self.fxRng.range(0.64, 1.04), .t = -self.fxRng.range(0, CAP_STAGGER) };
                placed += 1;
                break;
            }
        }
    }

    fn tickCaps(self: *Conclave, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        for (&self.caps) |*c| {
            if (!c.live) continue;
            c.t += dt;
            if (c.t < CAP_GROW + CAP_GLOW) continue;
            if (!c.burst) {
                c.burst = true;
                self.splashAt(c.at, 18);
                sfx.world(.duo_burst, c.at);
                if (mathx.distXZ(c.at, hero) <= CAP_BURST_R) foe.worseBlow(worst, CAP_HIT, c.at, &GROUND_THREAT);
            }
            if (c.t >= CAP_GROW + CAP_GLOW + 0.10) c.live = false;
        }
    }

    fn mist(self: *Conclave, at: rl.Vector3) void {
        for (&self.mists) |*g| {
            if (g.live) continue;
            g.* = .{ .live = true, .at = at };
            return;
        }
    }

    fn splashAt(self: *Conclave, at: rl.Vector3, n: usize) void {
        const from = self.fxHead;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .chaos, n, 1.0);
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    pub fn draw(self: *const Conclave, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
        for (&self.caps) |*c| {
            if (!c.showing() or c.burst) continue;
            drawCap(c);
        }
    }

    pub fn drawFx(self: *const Conclave) void {
        for (self.liveConst()) |*k| k.drawFx();
        for (&self.orbs) |*o| {
            if (!o.live) continue;
            rl.drawModelEx(self.orbModel, o.at, v3(0, 1, 0), mathx.degrees(o.spin), v3(1, 1, 1), rl.Color.white);
            // The halo is what carries at range — the mesh alone is a 0.32 m ball 16 m away.
            rl.drawSphereEx(o.at, ORB_R * (2.1 + 0.16 * mathx.sinf(o.t * 16.0)), 8, 6, mathx.withAlpha(CHAOS_CORE, 64));
        }
        for (&self.mists) |*g| {
            const a = g.amt();
            if (a <= 0.02) continue;
            rl.drawSphereEx(v3(g.at.x, g.at.y + MIST_R * 0.16, g.at.z), MIST_R * (0.55 + 0.45 * a), 10, 6, mathx.withAlpha(MIST_COL, mathx.u8f(46.0 * a)));
        }
        foe.drawParticles(&self.parts);
    }

    pub fn pierce(self: *Conclave, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Conclave) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Conclave) u32 {
        return foe.soulsDropped(self.liveConst(), MG_SOULS);
    }
    pub fn totalHits(self: *const Conclave) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Conclave) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

const DUO_PARTS: usize = 96;

fn drawCap(c: *const Cap) void {
    const g = c.grown();
    const up = c.r * (0.34 + 0.66 * @sqrt(g));
    const stem = v3(c.at.x, c.at.y + up * 0.46, c.at.z);
    rl.drawCylinderEx(c.at, stem, c.r * 0.17, c.r * 0.24, 6, RIND_LT);
// The cap's colour IS its clock; against moss and rind a (52,18,14) cap was a dark lump on dark ground.
    const heat = c.heat();
    const head = v3(stem.x, stem.y + up * 0.24, stem.z);
    const col = mathx.lerpColor(mathx.withAlpha(CHAOS_EDGE, 255), mathx.withAlpha(CHAOS_CORE, 255), heat);
    rl.drawSphereEx(head, up * 0.54, 7, 6, col);
    const puff = up * (0.70 + 0.60 * heat) * (1.0 + 0.10 * mathx.sinf(c.t * 20.0));
    rl.drawSphereEx(head, puff, 7, 6, mathx.withAlpha(CHAOS_CORE, mathx.u8f(38.0 + 76.0 * heat)));
}

const GROUND_THREAT = foe.Threat{};

const MIST_COL = rgba(178, 196, 150, 255);

test "THE TWO BANDS ABUT, so there is no ring where neither of them is answering" {
    try std.testing.expect(MG_FLEE_R > SW_SLASH_R);
    try std.testing.expect(SW_LUNGE_MAX > MG_FLEE_R);
    std.debug.print("\n  duo: sword swings to {d:.1} m and lunges to {d:.1}; the magus flees inside {d:.1} and keeps to {d:.1}\n", .{ SW_SLASH_R, SW_LUNGE_MAX, MG_FLEE_R, MG_KEEP_R });
    try std.testing.expect(MG_KEEP_R < AGGRO_R);
}

test "EVERY BAND OF THE SWORDSMAN PICKS A MOVE, and a bearing he cannot reach is a hard gate" {
    var d: f32 = 0;
    while (d <= AGGRO_R) : (d += 0.25) {
        try std.testing.expect(swClassify(d, 0, true, true, true, true, false) != .hold);
    }
    try std.testing.expectEqual(SwChoice.hold, swClassify(AGGRO_R + 1.0, 0, true, true, true, true, false));
    try std.testing.expectEqual(SwChoice.back, swClassify(1.0, 0, true, true, true, true, true));
    try std.testing.expectEqual(SwChoice.heavy, swClassify(1.0, 0, true, true, true, false, true));
    try std.testing.expectEqual(SwChoice.heavy, swClassify(SW_HEAVY_R - 0.1, 0, true, true, true, false, false));
    try std.testing.expectEqual(SwChoice.slash, swClassify(SW_HEAVY_R - 0.1, 0, true, false, true, false, false));
    try std.testing.expectEqual(SwChoice.slash, swClassify(SW_SLASH_R - 0.1, 0, true, false, true, false, false));
    try std.testing.expectEqual(SwChoice.lunge, swClassify(SW_LUNGE_MIN + 0.1, 0, false, false, true, false, false));
    try std.testing.expectEqual(SwChoice.close, swClassify(SW_HEAVY_R + 0.3, 0, false, true, false, false, false));
    try std.testing.expectEqual(SwChoice.close, swClassify(6.0, 0, false, false, false, false, false));
    inline for (.{ @as(f32, 1.0), @as(f32, -1.0) }) |sgn| {
        const wide = sgn * (swSlashArc() + 0.05);
        try std.testing.expectEqual(SwChoice.close, swClassify(SW_SLASH_R - 0.1, wide, true, false, false, false, false));
        const wideL = sgn * (swLungeArc() + 0.05);
        try std.testing.expectEqual(SwChoice.close, swClassify(SW_LUNGE_MIN + 0.1, wideL, false, false, true, false, false));
    }
    std.debug.print("  sword: swings to {d:.1} m inside {d:.0} deg, lunges {d:.1}..{d:.1} inside {d:.0} deg, overhead to {d:.1} m on a {d:.2} s tell\n", .{
        SW_SLASH_R, mathx.degrees(swSlashArc()), SW_LUNGE_MIN, SW_LUNGE_MAX, mathx.degrees(swLungeArc()), SW_HEAVY_R, SW_HEAVY_WIND,
    });
}

test "ONE STROKE THROWS HIM AND IT IS THE SLOW ONE — the lunge stopped juggling and the overhead took it on" {
    try std.testing.expectEqual(@as(f32, 0), SW_LUNGE_HIT.launch);
    try std.testing.expectEqual(@as(f32, 0), SW_SLASH_HIT.launch);
    try std.testing.expect(SW_HEAVY_HIT.launch > 0);
    const air = heromod.launchAirFor(SW_HEAVY_HIT.launch);
    const wasAir = heromod.launchAirFor(3.4);
    std.debug.print("  throw: the overhead puts him {d:.2} m up for {d:.2} s; the lunge used to put him {d:.2} m up for {d:.2} s\n", .{ SW_HEAVY_HIT.launch, air, @as(f32, 3.4), wasAir });
    try std.testing.expect(air < wasAir);
    try std.testing.expect(SW_HEAVY_REC > air);
}

test "THE MAGUS NEVER CLOSES, and being pressed outranks casting" {
    try std.testing.expectEqual(MgChoice.back, mgClassify(MG_FLEE_R - 0.1, true, true, false, false));
    try std.testing.expectEqual(MgChoice.vanish, mgClassify(MG_FLEE_R - 0.1, true, true, true, true));
    try std.testing.expectEqual(MgChoice.back, mgClassify(MG_FLEE_R - 0.1, true, true, false, true));
    try std.testing.expectEqual(MgChoice.sprout, mgClassify(MG_SPROUT_MIN + 0.1, true, true, false, false));
    try std.testing.expectEqual(MgChoice.orb, mgClassify(MG_SPROUT_MIN + 0.1, true, false, false, false));
    try std.testing.expectEqual(MgChoice.hold, mgClassify(AGGRO_R + 1.0, true, true, true, true));
    var d: f32 = 0;
    while (d <= AGGRO_R) : (d += 0.25) {
        const c = mgClassify(d, false, false, false, false);
        try std.testing.expect(c == .back or c == .keep);
    }
}

test "A BUNCH GROWS LONGER THAN IT GLOWS, and the glow is the last warning" {
    var duo = Conclave{ .model = undefined, .orbModel = undefined };
    duo.sow(mathx.ground(0, 0));
    var n: usize = 0;
    for (&duo.caps) |*c| n += @intFromBool(c.live);
    try std.testing.expectEqual(MG_BUNCH, n);
    for (&duo.caps) |*c| {
        if (!c.live) continue;
        try std.testing.expect(mathx.distXZ(c.at, mathx.ground(0, 0)) >= MG_BUNCH_R * 0.2);
        try std.testing.expect(mathx.distXZ(c.at, mathx.ground(0, 0)) <= MG_BUNCH_R + 1e-3);
    }
    var c0 = Cap{ .live = true };
    c0.t = CAP_GROW * 0.5;
    try std.testing.expectApproxEqAbs(@as(f32, 0), c0.heat(), 1e-6);
    c0.t = CAP_GROW + CAP_GLOW;
    try std.testing.expectApproxEqAbs(@as(f32, 1), c0.heat(), 1e-6);
    std.debug.print("  a bunch of {d}: {d:.1} s of growing, {d:.2} s of glowing, then {d:.1} m of burst\n", .{ MG_BUNCH, CAP_GROW, CAP_GLOW, CAP_BURST_R });
}

test "CLEARING THE FIELD CLEARS THE BODIES TOO, not just what they left on it" {
    var duo = Conclave{ .model = undefined, .orbModel = undefined };
    duo.magi[0] = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    duo.n = 1;
    duo.caps[0] = .{ .live = true };
    duo.mists[0] = .{ .live = true };
    duo.clear();
    try std.testing.expectEqual(@as(usize, 0), duo.liveConst().len);
    try std.testing.expect(!duo.caps[0].live and !duo.mists[0].live);
}

test "THE MIST THICKENS BEFORE IT BILLS, then bills on entry and on the clock" {
    var duo = Conclave{ .model = undefined, .orbModel = undefined };
    duo.mist(mathx.ground(0, 0));
    const dt: f32 = 1.0 / 60.0;
    try std.testing.expectEqual(@as(f32, 0), duo.breath(mathx.ground(0.5, 0), dt));
    var t: f32 = 0;
    while (t < MIST_LIFE * 0.25) : (t += dt) {
        for (&duo.mists) |*g| {
            if (g.live) g.t += dt;
        }
    }
    const first = duo.breath(mathx.ground(0.5, 0), dt);
    const after = duo.breath(mathx.ground(0.5, 0), dt);
    try std.testing.expect(first > after * 10.0);
    try std.testing.expectApproxEqAbs(MIST_BUILD * foe.ENTRY_BOLUS, first, 1e-4);
    try std.testing.expectEqual(@as(f32, 0), duo.breath(mathx.ground(MIST_R + 2.0, 0), dt));
    while (t < MIST_LIFE) : (t += dt) {
        for (&duo.mists) |*g| {
            if (g.live) g.t += dt;
        }
    }
    try std.testing.expectEqual(@as(f32, 0), duo.breath(mathx.ground(0.5, 0), dt));
    std.debug.print("  mist: {d:.1} m across for {d:.1} s, {d:.0} sleep a second inside it" ++ "\n", .{ MIST_R, MIST_LIFE, MIST_BUILD });
}

test "BOTH ARE TALL AND STURDY, and the swordsman is the one that hits" {
    const crown = SCALE * H;
    std.debug.print("  duo: {d:.2} m to the crown; sword {d:.0} HP / {d:.0} poise, magus {d:.0} / {d:.0}\n", .{ crown, SW_HP, SW_POISE, MG_HP, MG_POISE });
    try std.testing.expect(crown > heromod.H * 1.25);
    try std.testing.expect(SW_POISE > MG_POISE);
    try std.testing.expect(SW_HP > MG_HP);
    try std.testing.expect(SW_SLASH_HIT.raw() > ORB_HIT.raw());
    try std.testing.expect(SW_LUNGE_HIT.raw() > ORB_HIT.raw() * 1.5);
}

test "EVERY CHANNEL LANDS IN ITS OWN FIELD — the CH_ indices and P.chan()'s order are one list kept by hand" {
    const p = P{ .lean = 1, .twist = 2, .head = 3, .rsh = 4, .rabd = 5, .rel = 6, .lsh = 7, .lel = 8, .tilt = 9, .clasp = 10 };
    var k = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
    k.chanSet(p.chan());
    try std.testing.expectEqual(p.lean, k.bodyLean);
    try std.testing.expectEqual(p.twist, k.twist);
    try std.testing.expectEqual(p.head, k.headPitch);
    try std.testing.expectEqual(p.rsh, k.rsh);
    try std.testing.expectEqual(p.rabd, k.rabd);
    try std.testing.expectEqual(p.rel, k.rel);
    try std.testing.expectEqual(p.lsh, k.lsh);
    try std.testing.expectEqual(p.lel, k.lel);
    try std.testing.expectEqual(p.tilt, k.tilt);
    try std.testing.expectEqual(p.clasp, k.clasp);
    var m = Magus.spawn(mathx.zero3, 0, 1.0, 0.0);
    m.chanSet(p.chan());
    try std.testing.expectEqual(p.tilt, m.tilt);
    try std.testing.expectEqual(p.clasp, m.clasp);
    try std.testing.expectEqual(@as(usize, CHAN_N), p.chan().len);
}

test "THE SEAMS HOLD — every pose track starts where the one before it ended" {
    const pairs = .{
        .{ &SW_SLASH_WIND_KEYS, &SW_SLASH_KEYS },
        .{ &SW_SLASH_KEYS, &SW_SLASH2_KEYS },
        .{ &SW_SLASH_KEYS, &SW_REC_KEYS },
        .{ &SW_SLASH2_KEYS, &SW_SLASH2_REC_KEYS },
        .{ &SW_HEAVY_WIND_KEYS, &SW_HEAVY_KEYS },
        .{ &SW_HEAVY_KEYS, &SW_HEAVY_REC_KEYS },
        .{ &SW_LUNGE_WIND_KEYS, &SW_LUNGE_KEYS },
        .{ &SW_LUNGE_KEYS, &SW_BACK_KEYS },
        .{ &SW_LUNGE_KEYS, &SW_LUNGE_REC_KEYS },
        .{ &MG_ORB_WIND_KEYS, &MG_ORB_KEYS },
        .{ &MG_ORB_KEYS, &MG_ORB_REC_KEYS },
        .{ &MG_SPROUT_WIND_KEYS, &MG_SPROUT_KEYS },
        .{ &MG_SPROUT_KEYS, &MG_SPROUT_REC_KEYS },
    };
    inline for (@typeInfo(Recover).@"enum".fields) |f| {
        const r: Recover = @enumFromInt(f.value);
        const stroke = switch (r) {
            .slash => &SW_SLASH_KEYS,
            .slash2 => &SW_SLASH2_KEYS,
            .heavy => &SW_HEAVY_KEYS,
            .lunge => &SW_LUNGE_KEYS,
        };
        for (samplePose(stroke, 1.0), samplePose(r.keys(), 0.0)) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
        try std.testing.expect(r.dur() > 0);
    }
    inline for (@typeInfo(MgRecover).@"enum".fields) |f| {
        const r: MgRecover = @enumFromInt(f.value);
        const cast = switch (r) {
            .orb => &MG_ORB_KEYS,
            .sprout => &MG_SPROUT_KEYS,
        };
        for (samplePose(cast, 1.0), samplePose(r.keys(), 0.0)) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    }
    inline for (pairs) |p| {
        const endA = samplePose(p[0], 1.0);
        const startB = samplePose(p[1], 0.0);
        for (endA, startB) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    }
    for (samplePose(&SW_SLASH_WIND_KEYS, 0.0), SW_CARRY.chan()) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    for (samplePose(&MG_ORB_WIND_KEYS, 0.0), MG_CARRY.chan()) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
}

test "THE BLADE LANDS ON THE MAN WHERE HE STANDS - every stroke thrown for real, anywhere its own band picks it" {
    const dt = 1.0 / 120.0;
    const probe = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
    const apart = foe.closestApproach(probe.bodyR());
    const rows = [_]struct { name: []const u8, wind: SwState, strike: SwState, pick: SwChoice, near: f32, far: f32 }{
        .{ .name = "slash", .wind = .slash_wind, .strike = .slash, .pick = .slash, .near = apart, .far = SW_SLASH_R },
        .{ .name = "heavy", .wind = .heavy_wind, .strike = .heavy, .pick = .heavy, .near = apart, .far = SW_HEAVY_R },
        .{ .name = "lunge", .wind = .lunge_wind, .strike = .lunge, .pick = .lunge, .near = SW_LUNGE_MIN, .far = SW_LUNGE_MAX },
    };
    var misses: usize = 0;
    var thrown: usize = 0;
    var refused: usize = 0;
    for (rows) |row| {
        for ([_]f32{ 0, 45, 100, 165 }) |deg| {
            for ([_]f32{ 0.0, 0.34, 0.67, 1.0 }) |u| {
                const stand = lerpF(mathx.maxF(row.near, apart) + 0.05, row.far * 0.97, u);
                const off = mathx.radians(deg);
                if (swClassify(stand, off, row.pick == .slash, row.pick == .heavy, row.pick == .lunge, false, false) != row.pick) {
                    refused += 1;
                    continue;
                }
                thrown += 1;
                var k = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
                var hero = v3(@sin(off) * stand, 0, @cos(off) * stand);
                k.enter(row.wind);
                var hit = false;
                var best: f32 = 1e9;
                var relAt: f32 = 0;
                var guard: usize = 0;
                while (guard < 2000) : (guard += 1) {
                    if (k.update(dt, hero, 400.0, .{}) != null) {
                        hit = true;
                        break;
                    }
                    if (mathx.distXZ(k.pos, hero) < apart) {
                        const out = mathx.dirXZ(k.pos, hero);
                        hero = v3(k.pos.x + out.x * apart, 0, k.pos.z + out.z * apart);
                    }
                    const a = @abs(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(k.pos, hero)) - k.facing));
                    if (a < best) {
                        best = a;
                        relAt = mathx.distXZ(k.pos, hero);
                    }
                    if (k.state != row.wind and k.state != row.strike and k.state != .slash2) break;
                }
                if (!hit) {
                    misses += 1;
                    std.debug.print("\n  {s} at {d:.2} m, {d:.0} deg off: MISSED - came round to {d:.0} deg at best, man {d:.2} m off him then\n", .{ row.name, stand, deg, mathx.degrees(best), relAt });
                }
            }
        }
    }
    std.debug.print("  blade: {d} stands thrown for real and landed, {d} refused by a gate\n", .{ thrown, refused });
    try std.testing.expectEqual(@as(usize, 0), misses);
    try std.testing.expect(thrown >= 16);
}

test "AND THE BAND IS INSIDE THE REACH - the pick never hands out a stroke that goes past him" {
// `SW_SLASH_R` is the measured reach and not a number beside one: measured dead ahead, through the real update.
    const dt = 1.0 / 120.0;
    const rows = [_]struct { name: []const u8, wind: SwState, band: f32 }{
        .{ .name = "slash", .wind = .slash_wind, .band = SW_SLASH_R },
        .{ .name = "heavy", .wind = .heavy_wind, .band = SW_HEAVY_R },
    };
    for (rows) |row| {
        var far: f32 = 0;
        var d: f32 = 0.6;
        while (d < 6.0) : (d += 0.05) {
            var k = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
            k.enter(row.wind);
            var guard: usize = 0;
            while (guard < 900) : (guard += 1) {
                if (k.update(dt, v3(0, 0, d), 900.0, .{}) != null) {
                    far = d;
                    break;
                }
                if (k.state == .recover or k.state == .idle) break;
            }
        }
        std.debug.print("  blade: the {s} lands out to {d:.2} m, and its band stops at {d:.2}\n", .{ row.name, far, row.band });
        try std.testing.expect(row.band <= far);
        try std.testing.expect(row.band - foe.closestApproach(SW_BODY_R * SCALE) > 0.8);
    }
}

test "THE MAGUS COMES BACK UP OUT OF REACH, and a stagger through the fade spends it" {
    const dt = 1.0 / 120.0;
    var k = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    const hero = mathx.ground(0, 2.0);
    k.enter(.fade_out);
    k.returnTo = mathx.addV(k.pos, v3(MG_REAPPEAR_R, 0, 0));
    var guard: usize = 0;
    while (guard < 4000 and k.state != .idle) : (guard += 1) _ = k.update(dt, hero, 400.0, .{});
    try std.testing.expect(mathx.distXZ(k.pos, hero) > MG_FLEE_R);
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.fade, 1e-4);
    try std.testing.expect(k.fadeCd > 0);

    var caught = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    caught.enter(.fade_out);
    var n: usize = 0;
    while (n < 30) : (n += 1) _ = caught.update(dt, hero, 400.0, .{});
    try std.testing.expect(caught.fade > 0);
    caught.stagger(true);
    try std.testing.expectApproxEqAbs(@as(f32, 0), caught.fade, 1e-6);
    try std.testing.expectApproxEqAbs(MG_FADE_CD, caught.fadeCd, 1e-4);
    try std.testing.expect(caught.state == .stunheavy);
}

test "THE OVERHEAD IS ACTUALLY TWO-HANDED — the off fist is ON the hilt, measured, not asserted by its name" {
    const dt = 1.0 / 120.0;
    var k = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
    const carry = mathx.lenV(mathx.subV(rl.math.vector3Transform(mathx.zero3, k.xf[WRL]), rl.math.vector3Transform(mathx.zero3, k.xf[HELD])));
    k.enter(.heavy_wind);
    var worst: f32 = 0;
    var t: f32 = 0;
    while (t < SW_HEAVY_WIND + SW_HEAVY_DUR) : (t += dt) {
        _ = k.update(dt, v3(0, 0, 1.6), 400.0, .{});
        if (t < SW_HEAVY_WIND) continue;
        worst = @max(worst, mathx.lenV(mathx.subV(rl.math.vector3Transform(mathx.zero3, k.xf[WRL]), rl.math.vector3Transform(mathx.zero3, k.xf[HELD]))));
    }
    std.debug.print("\n  overhead grip: the off fist stays within {d:.2} m of the hilt through the stroke (carried, it is {d:.2} m off)\n", .{ worst, carry });
    try std.testing.expect(worst < carry * 0.5);
    try std.testing.expect(worst < 0.45);
}

test "A BEATEN MAGUS LEAVES SOONER AND COMES BACK ROUND QUICKER" {
    const dt = 1.0 / 120.0;
    var secs: [2]f32 = undefined;
    for ([_]f32{ MG_PRESS_HP - 0.02, 0.06 }, 0..) |frac, i| {
        var k = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
        k.vit.hp = MG_HP * frac;
        var t: f32 = 0;
        while (t < 12.0 and k.state != .fade_out) : (t += dt) {
            k.leash.noteSeen();
            _ = k.update(dt, mathx.ground(0, MG_FLEE_R - 1.0), 400.0, .{});
            k.pos = mathx.ground(0, 0);
        }
        secs[i] = t;
    }
    std.debug.print("\n  press: at {d:.0}% HP it holds {d:.2} s before it dissolves, at 6% it holds {d:.2}\n", .{ MG_PRESS_HP * 100.0, secs[0], secs[1] });
    try std.testing.expect(secs[0] < 12.0 and secs[1] < secs[0]);
    try std.testing.expect(lerpF(MG_FADE_CD, MG_FADE_CD_HURT, mgHarm(0.06)) < MG_FADE_CD);
    try std.testing.expectApproxEqAbs(MG_FADE_CD, lerpF(MG_FADE_CD, MG_FADE_CD_HURT, mgHarm(1.0)), 1e-5);
}

test "THE VENOM IS ON EVERY STROKE, and it is the clock the fight runs on" {
    const row = combat.ailRow(.poison);
    var v = combat.Vitals.initFoe(99999, 99999, 99999);
    var strokes: usize = 0;
    while (!v.ailOn(.poison) and strokes < 60) : (strokes += 1) {
        _ = v.hit(SW_SLASH_HIT);
        _ = v.tickAils(1.0 / 60.0);
    }
    std.debug.print("  venom: {d} slashes break a bare {s} bar of {d:.0}, at {d:.0} chaos a stroke" ++ "\n", .{ strokes, row.name, row.max, SW_SLASH_HIT.elem.at(.chaos) });
    try std.testing.expect(strokes >= 3 and strokes <= 12);
    try std.testing.expect(SW_LUNGE_HIT.elem.at(.chaos) > 0);
}

test "AN ORB FLIES, LANDS ON HIM AND IS SPENT - and the pool never leaks" {
// Zig only analyses what is reached, and `run` never called the orb path.
    var c = Conclave{ .model = undefined, .orbModel = undefined };
    const hero = mathx.ground(0, 9);
    c.launchOrb(v3(0, 1.6, 0), hero, 0);
    var lit: usize = 0;
    for (&c.orbs) |*o| lit += @intFromBool(o.live);
    try std.testing.expectEqual(@as(usize, 1), lit);

    const dt = 1.0 / 120.0;
    var worst: ?foe.Blow = null;
    var t: f32 = 0;
    while (t < ORB_LIFE and worst == null) : (t += dt) c.tickOrbs(dt, hero, &worst);
    const b = worst orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(ORB_HIT.elem.at(.chaos), b.hit.elem.at(.chaos));
    for (&c.orbs) |*o| try std.testing.expect(!o.live);
    std.debug.print("  orb: {d:.0} m/s across {d:.1} m, landed in {d:.2} s\n", .{ ORB_SPEED, mathx.distXZ(mathx.zero3, hero), t });

    c.launchOrb(v3(0, 1.6, 0), mathx.ground(0, 200), 0);
    var u: f32 = 0;
    var junk: ?foe.Blow = null;
    while (u < ORB_LIFE + 0.5) : (u += dt) c.tickOrbs(dt, mathx.ground(300, 300), &junk);
    for (&c.orbs) |*o| try std.testing.expect(!o.live);
    try std.testing.expect(junk == null);
}

test "AN ORB THROWN FROM BELOW HIM SURVIVES THE STAFF — the earth is not wherever he is standing" {
    var c = Conclave{ .model = undefined, .orbModel = undefined };
    const dt = 1.0 / 120.0;
    const rise = 2.4;
    const staff = 1.6;
    const hero = v3(0, rise, 26);
    c.launchOrb(v3(0, staff, 0), hero, 0);
    var worst: ?foe.Blow = null;
    c.tickOrbs(dt, hero, &worst);
    var lit: usize = 0;
    for (&c.orbs) |*o| lit += @intFromBool(o.live);
    std.debug.print("\n  magus on ground {d:.2} m under him: staff at {d:.2} m, floor was {d:.2} m — {d} orb(s) still in flight\n", .{ rise, staff, rise + 0.05, lit });
    try std.testing.expect(staff < rise);
    try std.testing.expectEqual(@as(usize, 1), lit);
    var t: f32 = 0;
    while (t < ORB_LIFE and worst == null) : (t += dt) c.tickOrbs(dt, hero, &worst);
    try std.testing.expect(worst != null);
}

test "A BUNCH GOES OFF ONCE, on the frame it bursts, and only on what is standing in it" {
    var c = Conclave{ .model = undefined, .orbModel = undefined };
    c.sow(mathx.ground(0, 0));
    const dt = 1.0 / 120.0;
    var hits: usize = 0;
    var t: f32 = 0;
    while (t < CAP_GROW + CAP_GLOW + 1.0) : (t += dt) {
        var worst: ?foe.Blow = null;
        c.tickCaps(dt, mathx.ground(0, 0), &worst);
        if (worst != null) hits += 1;
    }
    try std.testing.expectEqual(MG_BUNCH, hits);
    for (&c.caps) |*cp| try std.testing.expect(!cp.live);

    var away = Conclave{ .model = undefined, .orbModel = undefined };
    away.sow(mathx.ground(0, 0));
    var miss: usize = 0;
    var u: f32 = 0;
    while (u < CAP_GROW + CAP_GLOW + 1.0) : (u += dt) {
        var worst: ?foe.Blow = null;
        away.tickCaps(dt, mathx.ground(0, CAP_BURST_R + MG_BUNCH_R + 2.0), &worst);
        if (worst != null) miss += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), miss);
}

test "THEY WAKE ON A DISTANCE AND NOTHING ELSE - no gate, no ward, no line of sight" {
    const dt = 1.0 / 60.0;
    var sw = Swordsman.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    var mg = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.70);
    const hero = mathx.ground(0, AGGRO_R * 0.4);
    const swHome = sw.pos;
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) {
        _ = sw.update(dt, hero, 400.0, .{});
        _ = mg.update(dt, hero, 400.0, .{});
    }
    std.debug.print("\n  woke: sword {d:.1} m from him (was {d:.1}), state {s}; magus {d:.1} m, state {s}\n", .{
        mathx.distXZ(sw.pos, hero), mathx.distXZ(swHome, hero), @tagName(sw.state),
        mathx.distXZ(mg.pos, hero),                             @tagName(mg.state),
    });
    try std.testing.expect(sw.state != .idle or mathx.distXZ(sw.pos, swHome) > 0.1);
    try std.testing.expect(mg.state != .idle or mathx.distXZ(mg.pos, mathx.ground(0, 0)) > 0.1);
    try std.testing.expect(mathx.distXZ(sw.pos, hero) < mathx.distXZ(swHome, hero));

    var far = Swordsman.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    const away = mathx.ground(0, AGGRO_R + 12.0);
    var u: f32 = 0;
    while (u < 2.0) : (u += dt) _ = far.update(dt, away, 400.0, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(far.pos, mathx.ground(0, 0)), 0.01);
}

const PAIR_OVER_KNIGHT: f32 = 1.60;

fn conclaveDps(stand: f32, secs: f32) f32 {
    const dt = 1.0 / 60.0;
    const hero = mathx.ground(0, stand);
    var c = Conclave{ .model = undefined, .orbModel = undefined };
    c.magi[0] = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.70);
    c.n = 1;
    var total: f32 = 0;
    var t: f32 = 0;
    while (t < secs) : (t += dt) {
        c.magi[0].leash.noteSeen();
        if (c.update(dt, hero, 400.0, .{})) |b| total += b.hit.raw();
        c.magi[0].pos = mathx.ground(0, 0);
    }
    return total / secs;
}

fn dpsAgainst(f: anytype, stand: f32, secs: f32) f32 {
    const dt = 1.0 / 60.0;
    const hero = mathx.ground(0, stand);
    var total: f32 = 0;
    var t: f32 = 0;
    while (t < secs) : (t += dt) {
        f.leash.noteSeen();
        if (f.update(dt, hero, 400.0, .{})) |h| total += h.raw();
        f.pos = mathx.ground(0, 0);
    }
    return total / secs;
}

test "AND NOTHING HERE OUT-EARNS THE FIRST BOSS PER SECOND EITHER" {
    var swWorst: f32 = 0;
    var knWorst: f32 = 0;
    var mgWorst: f32 = 0;
    for ([_]f32{ 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.5, 8.0, 10.0, 14.0 }) |stand| {
        var blade = Swordsman.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
        var plate = knightmod.Knight.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
        const sw = dpsAgainst(&blade, stand, 60.0);
        const kn = dpsAgainst(&plate, stand, 60.0);
        const mg = conclaveDps(stand, 60.0);
        swWorst = @max(swWorst, sw);
        knWorst = @max(knWorst, kn);
        mgWorst = @max(mgWorst, mg);
        std.debug.print("\n  at {d:>5.1} m: sword {d:>5.1}, magus {d:>5.1}, pair {d:>5.1} | knight {d:>5.1}", .{ stand, sw, mg, sw + mg, kn });
    }
    std.debug.print("\n  worst band: sword {d:.1}, magus {d:.1}, pair {d:.1} | knight {d:.1}\n", .{ swWorst, mgWorst, swWorst + mgWorst, knWorst });
    try std.testing.expect(swWorst > 4.0 and mgWorst > 2.0);
    try std.testing.expect(swWorst <= knWorst);
    try std.testing.expect(swWorst + mgWorst <= knWorst * PAIR_OVER_KNIGHT);
}

test "NOTHING HERE HITS HARDER THAN THE FIRST BOSS DOES" {
    const sweep = knightmod.SWEEP_HIT.raw();
    const overhead = knightmod.OVERHEAD_HIT.raw();
    const slash = SW_SLASH_HIT.raw();
    const lunge = SW_LUNGE_HIT.raw();
    const heavy = SW_HEAVY_HIT.raw();
    const bunch = CAP_HIT.raw() * @as(f32, @floatFromInt(MG_BUNCH));
    std.debug.print("\n  damage: slash {d:.0}, x2 chain {d:.0}, lunge {d:.0}, overhead {d:.0}, orb {d:.0}, a whole bunch {d:.0}" ++
        " | knight sweep {d:.0}, overhead {d:.0}\n", .{ slash, slash * 2, lunge, heavy, ORB_HIT.raw(), bunch, sweep, overhead });
    try std.testing.expect(slash < sweep);
    try std.testing.expect(lunge <= overhead);
    try std.testing.expect(heavy > lunge and heavy <= overhead);
    try std.testing.expect(slash * 2 > lunge);
    try std.testing.expect(ORB_HIT.raw() < knightmod.SWAT_HIT.raw());
    try std.testing.expect(bunch > overhead and bunch < overhead * 2.0);
}

test "A DISSOLVED MAGUS IS NOT THERE FOR ANY OF THE THREE QUESTIONS" {
    var k = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    try std.testing.expect(!k.hidden() and !k.phased() and !k.absent());
    k.enter(.gone);
    try std.testing.expect(k.absent() and k.hidden() and k.phased());
    const before = k.hits;
    _ = k.update(1.0 / 60.0, mathx.ground(0, 1), 400.0, .{
        .active = true,
        .r = 4.0,
        .a = mathx.ground(0, -1),
        .b = mathx.ground(0, 1),
        .hit = .{ .dmg = 50 },
    });
    try std.testing.expectEqual(before, k.hits);
    try std.testing.expect(k.alive());
}
