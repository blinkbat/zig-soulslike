const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const item = @import("item.zig"); // the GEAR table — what a thing does when he puts it on (`item.Equip`)
const statsmod = @import("stats.zig");
const art = @import("propart.zig");
const archer = @import("archer.zig");
const foemod = @import("foe.zig");
const elemfx = @import("elemfx.zig"); // the elements' particle LANGUAGE — the breath pours COLD out of it
const ptree = @import("passivetree.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const radians = mathx.radians;


pub const H: f32 = 1.8; // stature (world units ≈ metres)

comptime {
    // `foe.zig` is below this file in the import graph and cannot read `H`, so it hardcodes 1.71.
    std.debug.assert(@abs(foemod.HERO_HIGH - 0.95 * H) < 0.005);
}

pub const WALK_SPEED: f32 = 1.7;
pub const RUN_SPEED: f32 = 3.4;
pub const SPRINT_SPEED: f32 = 5.1;
/// LOCKED-ON sideways travel, as a fraction of forward.
pub const STRAFE_SPEED: f32 = 0.85;
/// …and behind the shield, as a fraction of the WALK.
pub const GUARD_SPEED: f32 = 0.75;
/// A DRAUGHT IS COMMITTED, NOT PLANTED (owner's call) — this fraction of the WALK, and never zero.
pub const DRINK_SPEED: f32 = 0.35;
/// Extra crouch (units of H) as the flask goes up, folded into the gait's own `crouch`.
const DRINK_SINK: f32 = 0.012;

// Body-segment lengths as a fraction of stature H (Drillis & Contini 1966; Winter).
pub const SEG_THIGH = 0.245;
pub const SEG_SHANK = 0.246;
pub const SEG_UPARM = 0.188;
pub const SEG_FOREARM = 0.145;

pub const N = 18;
pub const ROOT = 0; // pelvis
pub const SPINE = 1; // lumbar / mid-torso pivot
pub const CHEST = 2; // thorax / shoulder girdle
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

/// The rest pose for any humanoid on this scaffold — the creature's own standing frame (X = its left, Y up,
/// Z forward), as fractions of stature scaled by `stature`.
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
    r[HELD] = v3(-sx, 0.485, 0); // zero offset from the wrist; the mesh is authored in the wrist frame
    for (&r) |*p| p.* = v3(p.x * stature, p.y * stature, p.z * stature);
    return r;
}

pub const HIP_HALF = 0.090; // a touch under half the bi-iliac breadth, so the stance is not splayed
pub const SHOULDER_HALF = 0.150; // ~half the biacromial breadth, plus pauldron room

fn restPositions() [N]rl.Vector3 {
    return restHumanoid(HIP_HALF, SHOULDER_HALF, H);
}

const SKIN = rgba(150, 112, 86, 255);
const SKIN_DK = rgba(120, 88, 66, 255);
const TUNIC = rgba(38, 40, 50, 255);
const TUNIC_DK = rgba(28, 30, 38, 255);
const LEATHER = rgba(58, 39, 26, 255);
const LEATHER_DK = rgba(38, 26, 18, 255);
const CLOTHDK = rgba(44, 39, 32, 255); // umber trousers
const BOOT = rgba(24, 22, 20, 255);
const BELT = rgba(34, 26, 18, 255);
const HAIR = rgba(40, 31, 24, 255);
const CAPE = rgba(82, 20, 12, 255);
const STEEL = rgba(98, 104, 114, 255);
const STEEL_DK = rgba(58, 62, 70, 255);
const BRASS = art.BRASS; // the WORLD's brass, not a second literal of it (`propruins.zig`'s line)

pub const HIP_FLEX = [8]f32{ 25, 13, 3, -5, -10, -3, 12, 22 };
pub const KNEE_FLEX = [8]f32{ 5, 18, 10, 4, 10, 38, 62, 30 };
pub const ANK_DORSI = [8]f32{ -2, -6, 2, 9, 6, -14, -6, -1 };

pub const RUN_HIP = [8]f32{ 42, 25, 8, -8, 5, 35, 60, 55 };
pub const RUN_KNEE = [8]f32{ 26, 48, 40, 28, 62, 98, 80, 44 };
pub const RUN_ANK = [8]f32{ -3, 10, 22, 2, -18, -6, 0, -2 };
const RUN_LEAN = 24.0;
const RUN_ARM_SWING = 30.0;
const RUN_ELBOW = 85.0;
const RUN_CROUCH = 0.06 * H;
const BODY_PITCH_RUN = 9.0; // whole-body pitch about the FEET
const BODY_PITCH_SPRINT = 18.0;
const HEAD_WALK = 7.0; // + = gaze down
const GAZE_AHEAD = 15.0; // running: counter the lean down to ~this chain angle
const NECK_EXT_MAX = 34.0; // cap total head+neck extension so lifting the gaze can't hyperextend the neck
const A_RUN_BOUNCE = 0.05 * H; // vertical airtime lift during flight (up-only, so planted feet don't sink)
const RUN_SPEED_LO = 2.1; // blend walk→run across this ground-speed band
const RUN_SPEED_HI = RUN_SPEED;
const SPRINT_LEAN = 40.0;
const SPRINT_REF_SPEED = SPRINT_SPEED; // speed the extra sprint lean/crouch saturate at

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

/// A REAL INTEGRATION under gravity, not a scripted arc like a toad's hop: he lands on whatever ground turns
/// out to be under him. These TWO are the decision and the other two are SOLVED off them.
pub const JUMP_APEX: f32 = 1.0; // metres his feet clear at the top: THREE terrain risers, where a walk gets two
pub const JUMP_AIR: f32 = 0.72; // seconds off the ground on the flat
/// apex = g·t²/8 and v0 = g·t/2, both inverted.
const JUMP_G: f32 = 8.0 * JUMP_APEX / (JUMP_AIR * JUMP_AIR);
const JUMP_V0: f32 = JUMP_G * JUMP_AIR * 0.5;
/// rad/s, well under `game.TURN_RATE`: the stick steers the HEADING and may never re-price the speed, or a
/// standing hop becomes a free sprint with no stamina bill.
const AIR_TURN_RATE: f32 = 2.6;
/// The landing absorb is VISUAL ONLY, and that is a law: a recovery that took the stick off him is the
/// hitstop the house rules refuse. Nothing mechanical reads `landT`.
const LAND_DUR: f32 = 0.34;
const LAND_SINK = 0.052 * H; // just over a caught blow's `BLOCK_SINK`: this is his own mass arriving
const LAND_SINK_AT: f32 = 0.22; // …and it ARRIVES rather than starting there — the touchdown frame is the impact
const LAND_REBOUND: f32 = 0.62; // …then rises PAST its own stance and settles onto it (the reactions law)
/// Seconds past touchdown at which the sink is DEEPEST — derived, so a retune of either dial re-aims the
/// harness's shot rather than leaving it a frame count nobody re-checked.
pub const LAND_SINK_DEEPEST: f32 = LAND_DUR * LAND_SINK_AT;
const LAND_STOOP: f32 = 7.0; // deg of thoracic fold over the sink; the pelvis dips, the trunk closes over it
/// THE FLIGHT POSE, all degrees. Three terms off ONE number (the vertical velocity): DRIVE on the way up,
/// TUCK at the apex where the velocity passes through zero, REACH on the way down.
const JUMP_TOEOFF: f32 = 26.0; // hip extension behind him at the push — the leg he just left the ground with
const JUMP_TOE_PLANTAR: f32 = 30.0; // …and the ankle that did it, still pointed
const JUMP_TUCK_HIP: f32 = 62.0;
const JUMP_TUCK_KNEE: f32 = 88.0;
const JUMP_REACH_HIP: f32 = 14.0; // descending: the legs come down UNDER him, knees nearly straight
const JUMP_REACH_KNEE: f32 = 16.0;
const JUMP_REACH_DORSI: f32 = 12.0; // …toes up, receiving the ground
const JUMP_ARM_UP: f32 = 52.0; // the drive throws the arms up and open…
const JUMP_ARM_HOLD: f32 = 0.55; // …and this much of the raise is KEPT for the whole flight (see `jumpArm`)
const JUMP_ARM_DROP: f32 = 0.55; // …traded away again over the descent
const JUMP_ARM_ELBOW: f32 = 34.0;
const JUMP_ARM_FOLD: f32 = 26.0; // the elbows close over the tuck, so the apex is a BALL and not a starfish
const JUMP_ARM_OUT: f32 = 22.0; // …and the descent spreads them for balance
const JUMP_ARCH: f32 = -8.0; // trunk EXTENDS at the push (negative = back arch), per segment
const JUMP_FOLD: f32 = 12.0; // …and closes over the tuck
const JUMP_HEAD_UP: f32 = -10.0; // the eyes go up with the drive and back to level on the way down
const JUMP_LEG_SPLIT: f32 = 5.0; // the two legs never do the same thing at once (wabi-sabi, cosmetic)

const ROLL_DUR = 0.70; // seconds, start to finish
const ROLL_IFRAME_END = 0.46; // invulnerable from the FIRST frame to here
pub const ROLL_DIST = 3.5; // ground units travelled
const ROLL_BALL_Y = 0.50; // pelvis pivot height at mid-roll
const ROLL_TUCK_IN = 0.16;
const ROLL_SPIN_A = 0.05; // somersault sweep: two OVERLAPPED eases, front-loaded.
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
const ROLL_SPINE = 30.0; // deg, PER SEGMENT
const ROLL_HEAD = 32.0;
const ROLL_SHOULDER = 45.0;
const ROLL_ELBOW = 100.0;
const ROLL_LEAN = 8.0;
const ROLL_SKEW = 7.0;
const ROLL_ARM_GUIDE = 1.25;
const ROLL_ARM_PUSH = 0.80;
const ROLL_LEG_LEAD = 1.08;
const ROLL_LEG_TRAIL = 0.92;
const ROLL_VAR_LO = 0.7; // per-roll drift of the imperfection magnitudes — cosmetic only, never
const ROLL_VAR_HI = 1.3; // duration, distance or heading
const ROLL_YAW_RATE = 22.0; // rad/s

const ATK_LIGHT_DUR = 0.60; // R1, seconds
const ATK_HEAVY_DUR = 1.00; // R2, seconds
const AL_WIND_B = 0.28;
const AL_STRIKE_A = 0.28; // pelvis fires; chest/shoulder/elbow/wrist each lag AL_LAG more
const AL_STRIKE_B = 0.48;
const AL_LAG = 0.03;
const AL_RECOV_A = 0.62;
const AL_HIT_A = 0.32; // TAE-style ACTIVE window — the blade only hits inside it
const AL_HIT_B = 0.56;
const AL_LUNGE = 0.55; // ground units stepped into the cut
const AL_CHAIN = 0.80; // u where a BUFFERED action may take over
const AH_WIND_B = 0.34;
const AH_STRIKE_A = 0.38;
const AH_STRIKE_B = 0.52;
const AH_LAG = 0.025;
const AH_RECOV_A = 0.72;
const AH_HIT_A = 0.40;
const AH_HIT_B = 0.58;
const AH_LUNGE = 1.05; // ground units
const AH_CHAIN = 0.86;
const ATK_RETRACK = 9.0; // rad/s
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
const AL_OVER = 6.0; // deg of follow-through overshoot past the end pose
const AL_LOAD = 0.016 * H;
const AL_DIP = 0.015 * H;
const AH_BODY_YAW = 11.0;
const AH_LEAN_BACK = 10.0; // deg, PER SEGMENT
const AH_SPINE_CRUNCH = 16.0; // deg, PER SEGMENT
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
const AH_PITCH = 9.0; // whole-body pitch about the FEET
const BOW_QUICK_DUR: f32 = 0.62; // R1, seconds
const BOW_QUICK_AT: f32 = 0.55;
const BOW_SHOT_DUR: f32 = 0.34; // R2 out of a HELD aim, seconds
const BOW_SHOT_AT: f32 = 0.22;
const BOW_SNAP: f32 = 0.06; // as a fraction of the shot's own duration
pub const BOW_QUICK_HIT = combat.Hit{ .dmg = 10, .poise = 5 };
pub const BOW_AIMED_HIT = combat.Hit{ .dmg = 23, .poise = 11, .stance = 8 };
/// Fire damage added on top of the shaft's physical, as a FRACTION of it, so it rides both shots in proportion.
pub const FIRE_ARROW_FRAC: f32 = 0.5;

pub fn fireTipped(h: combat.Hit) combat.Hit {
    var out = h;
    out.elem = combat.elems(.{ .fire = h.dmg * FIRE_ARROW_FRAC });
    return out;
}

/// EXHAUSTIVE here rather than `== .fire` tests in the loose, the shot harness and the HUD.
/// **AND THE ROGUE'S RANGED BRANCH IS A DIAL ON THE SHAFT ITSELF** (`passivetree.Grant.bowDmg`), with the
/// berserker's bargain over the top of it — a blow is a blow whichever hand threw it. Taken BEFORE the fire
/// tip, so a burning arrow's fire is a share of the shaft as it actually leaves the string (`fireTipped`'s
/// own rule) rather than of the bare constant.
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

/// Resolved here, since `hud.zig` knows nothing about the hero.
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
// Angles lifted from `archer.poseUpper`, a working full draw on this same rig.
const BOW_SH_FLEX = 88.0;
const BOW_SH_ABD = 9.0;
const BOW_ELBOW = 13.0; // the bow arm stays LONG — a folded bow arm is a bow held at your own face
const BOW_WRIST = 6.0;
const BOW_DRAW_SH = 84.0;
const BOW_DRAW_ELBOW = 152.0;
const BOW_DRAW_ABD = 33.0;
const BOW_DRAW_YAW = 16.0;
const BOW_BLADE = 7.0; // the trunk turns side-on to the target (deg, PER SEGMENT over spine + chest)
const BOW_HEAD_NOD = 6.0;
const BOW_HEAD_YAW = 8.0;
const BOW_HEAD_CANT = 9.0;
const BOW_STOOP = 4.0;
const BOW_CARRY_SH = 26.0; // the LOW CARRY, bow not presented
const BOW_CARRY_ELBOW = 8.0;
const BOW_DRAW_REST = 26.0;
const BOW_KICK = 7.0;
const BOW_BLEND_RATE = 11.0;
/// rad/s onto the aim line through a loose — faster than `ATK_RETRACK`: a shaft off the line just misses.
const TURN_TO_SHOT = 11.0;

const CAST_DUR: f32 = 0.66; // s
const CAST_AT: f32 = 0.46;

// Longer than a cast and the most committed thing he can do standing up: calling a second body onto the
// field is not a move you slip between two of a creature's swings.
const RING_DUR: f32 = 1.05;
/// The note is EARLY — the spirit is owed at the strike and the rest is the arm settling, so a player who
/// read the opening gets his wolf before the thing reaches him. The tail is still committed.
pub const RING_AT: f32 = 0.38;
/// deg the shoulder lifts the bell to shoulder height, and the elbow's fold under it.
const RING_SH_FWD = 74.0;
const RING_SH_ABD = 26.0;
const RING_ELBOW = 62.0;
/// A bell is not swung, it is SHAKEN: the wrist snaps through a small arc twice, the second throw smaller.
const RING_FLICK = 46.0; // deg of wrist roll at the peak of the first throw
const RING_FLICK_RATE = 13.0; // rad/s through the shake — fast, because the note is an IMPACT
/// Sized so the flick's first peak sits on `RING_AT`: the arm has to be moving before the clapper arrives.
const RING_FLICK_LEAD: f32 = 0.10; // in u
const RING_DECAY: f32 = 4.2; // how fast the shake dies — two throws' worth and then still
const RING_RECOV_A: f32 = 0.66; // where the arm starts coming back down
const RING_LEAN = 7.0; // deg the trunk gives back against the raised arm — the waist, never the root
const RING_HEAD = -9.0; // …and the head coming UP to watch for what he called
pub const BOLT_SPEED: f32 = 30.0;
pub const BOLT_REACH: f32 = 55.0;

/// deg. FLEXION, NOT ABDUCTION: the elbow's hinge axis rides the shoulder, so abducting stands it vertical and
/// the fold then sweeps the forearm across the chest instead of up past the temple. The rig has no humeral
/// rotation channel to correct it with.
const CAST_SH_FWD = 118.0;
const CAST_LIFT_ABD = 24.0; // deg, keeps the raise off the mid-line
const CAST_ELBOW = 52.0;
const CAST_ELBOW_SNAP = 40.0;
/// deg either side of centre, in the TRANSVERSE plane — which is why it can exceed the 34 the frontal plane
/// capped it at without laying the forearm over his own face.
const CAST_SWEEP = 46.0;
const CAST_WRIST = 38.0;
// The CARRY (`poseWandArm`): a folded elbow is what gets the lit head up off the ground.
const WAND_CARRY_FLEX = 14.0;
const WAND_CARRY_ABD = 6.0;
const WAND_CARRY_ELBOW = 74.0;
const WAND_CARRY_WRIST = -12.0;
const WAND_CARRY_SWING = 0.55; // fraction of the gait's shoulder swing
const WAND_CARRY_ELBOW_SWING = 0.40;
const CAST_TRUNK = 7.0; // trunk yaw toward the casting side (deg, PER SEGMENT over spine + chest)
const CAST_LEAN = 6.0;
const CAST_HEAD = 9.0;
const CAST_DIP = 0.020 * H;
const CAST_WIND_B = 0.32;
const CAST_RECOV_A = 0.70;

// THE SUMMONING BELL. It HANGS, so it is nearly plumb: the sword leads 34° forward of the forearm
// (`GRIP_PITCH`) because a blade is AIMED, where 12° is the fist's own cant after the wrist gives to weight.
const BELL_PITCH = 12.0;
const BELL_CA = @cos(radians(BELL_PITCH));
const BELL_SA = @sin(radians(BELL_PITCH));
/// A point `t` (units of H) down the bell's axis from the fist centre — `bladeAt`'s shape on its own cant.
fn bellAt(t: f32) rl.Vector3 {
    return v3(-BELL_SA * t * H * 0.35, FIST_Y - BELL_CA * t * H, FIST_Z + BELL_SA * t * H);
}
const BELL_GRIP_T0 = -0.040; // the butt of the handle, standing proud above the fist
const BELL_CROWN_T = 0.052; // where the handle meets the metal
const BELL_MOUTH_T = 0.107; // …and the rim, 10 cm of bronze below it
const BELL_MOUTH_R = 0.026 * H; // ~9.4 cm across the mouth: a hand bell, not a chapel one
const BELL_WALL = 0.0035 * H;
/// Deliberately off `BRASS` and off `STEEL` — a different alloy from his own guard. Dark for `WAND_FERRULE`'s
/// reason: a small strongly-curved revolved surface takes the sun over its whole visible face.
const BELL_BRONZE = rgba(78, 58, 30, 255);
const BELL_BRONZE_LT = rgba(104, 80, 42, 255);
/// The mouth is a HOLE, so near-black cannot blow out — and the contrast against the rim is the read.
const BELL_BORE = rgba(14, 11, 8, 255);
const BELL_HANDLE = rgba(46, 34, 26, 255);

/// Authored in the LEFT WRIST's frame, extending out of the fist along −Y exactly as the sword is off the
/// right, so the raised arm carries it up and away from the skull instead of across it.
const WAND_LEN = 0.30 * H;
const WAND_R = 0.0155 * H;
const WAND_STONE_R = 0.030 * H;
const WAND_WOOD = rgba(41, 30, 24, 255);
const WAND_WOOD_LT = rgba(62, 47, 36, 255);
const WAND_BIND = rgba(30, 25, 22, 255);
/// Near-black or it CLIPS: small strongly-curved capsules take the sun over their whole visible face, and both
/// 58/62/70 and `SHIELD_IRON` sampled at 255,255,255 here — a white cage round the stone, not a setting for it.
const WAND_FERRULE = rgba(9, 10, 12, 255);
/// The stone is EMISSIVE (vertex alpha is the emissive channel) so it reads as lit rather than painted.
const WAND_STONE = rgba(96, 40, 122, 120);
const WAND_STONE_HOT = rgba(150, 74, 176, 60);
/// deg. A rod in a closed fist lies on the OBLIQUE PALMAR AXIS (second metacarpal head → pisiform), not on the
/// hand's long axis the way a sabre grip pulls a blade (`GRIP_PITCH`'s 34). Do not flatten it back to −Y: that
/// is collinear with the forearm, same tan and thickness, so shoulder → arm → rod reads as one unbroken taper.
const WAND_PITCH = 55.0;
const WAND_ULNAR = 8.0; // deg outboard, little-finger side, clear of his own face
/// The shaft lies IN the palm, not on the wrist's bone line — half a closed fist's depth off it.
const WAND_PALM = 0.017 * H;
const WAND_CA = @cos(radians(WAND_PITCH));
const WAND_SA = @sin(radians(WAND_PITCH));
const WAND_UC = @cos(radians(WAND_ULNAR));
const WAND_US = @sin(radians(WAND_ULNAR));
/// The head leads DISTALLY (the sword's convention). Do NOT flip it proximal to improve the carry: the lit
/// end then points at the floor the instant the hand goes above the shoulder, and the rod has one authored
/// axis for both poses. The shaft is NOT a world axis, so every ring on it (cord turns, setting claws) must
/// be swept perpendicular to `WAND_U`/`WAND_V`, never a Y-flattened `addBlob`.
const WAND_AX = v3(WAND_SA * WAND_US, -WAND_CA, WAND_SA * WAND_UC);
const WAND_U = mathx.normV(v3(-WAND_AX.z, 0, WAND_AX.x));
const WAND_V = mathx.normV(mathx.crossV(WAND_AX, WAND_U));
/// A point t (units of H) along the wand's axis from the fist centre, wrist frame — `bladeAt`'s twin.
fn wandAt(t: f32) rl.Vector3 {
    return v3(
        WAND_AX.x * t * H,
        FIST_Y + WAND_AX.y * t * H,
        FIST_Z + WAND_PALM + WAND_AX.z * t * H,
    );
}
const WAND_TIP_T = 0.30; // where the stone sits, in the same units — the point a bolt leaves from
const WAND_BUTT_T = 0.055; // …and how far the butt stands back out of the fist, same units
/// `at`, stepped `r` off the shaft at angle `a` round it.
fn offAxis(at: rl.Vector3, r: f32, a: f32) rl.Vector3 {
    const c = r * mathx.cosf(a);
    const s = r * mathx.sinf(a);
    return v3(at.x + c * WAND_U.x + s * WAND_V.x, at.y + c * WAND_U.y + s * WAND_V.y, at.z + c * WAND_U.z + s * WAND_V.z);
}

/// ONE pair of colours for the whole spell — the stone, the gather, both bursts and the flight streak. Two
/// substances of one element is what the brood mother's spit-and-pool rule forbids. **AND THE PAIR IS THE
/// ELEMENT'S, NOT HIS** (`elemfx`'s own claim, which as two literals here was only ever a coincidence).
const CHAOS_MOTE = elemfx.sig(.chaos).edge;
const CHAOS_HOT = elemfx.sig(.chaos).core;
const CAST_MOTE_RATE = 52.0; // motes a second drawn onto the stone as the raise STARTS…
const CAST_MOTE_R = 0.17; // …from this far out
/// Both dials ride the charge, so the tell tightens visibly as the throw comes on.
const CAST_MOTE_RATE_HI = 300.0;
const CAST_MOTE_R_HI = 0.055;
/// Motes one frame may emit. The ramp needs an accumulator (a per-frame probability test tops out at ~60/s and
/// the ramp then does nothing), and the accumulator needs a ceiling or one hitch dumps the whole ring.
const CAST_MOTE_CAP = 8;
/// s. SHORT, because riding the tip's velocity (`gatherMotes`) cancels the tip's constant motion but not its
/// ACCELERATION, and the leftover smear is ½·a·life² — so the life is what pays, and it pays quadratically.
const CAST_MOTE_LIFE_LO = 0.030;
const CAST_MOTE_LIFE_HI = 0.055;
/// …and the radius is what buys that short life back, not the count: `drawParticles` fades radius WITH alpha,
/// so at 0.04 s a mote is legible on one frame of three and at 0.015 nine motes showed as three.
const CAST_MOTE_R0 = 0.023;
const CAST_MOTE_R1 = 0.011;
const CAST_SPARKS = 26; // the cone off the stone as it goes…
/// …and the COLLAR sideways out of it, which is what says the stone LET GO.
const CAST_COLLAR = 12;
const CAST_COLLAR_SP = 4.4;
/// One bloom on the stone at the throw. SMALL: it is a solid sphere, not additive, so at 0.30 it rendered as a
/// translucent balloon hiding the stone, the claws, the cone and the collar all at once.
const CAST_FLASH_R = 0.095;
const CAST_FLASH_LIFE = 0.085;
const BOLT_BURST = 22; // …and the bigger one where it lands

// THE TWO STRIKES' PICTURES — the mechanics' own numbers are `combat.LEVIN_*` / `combat.SIPHON_*`, and the
// GEOMETRY of the stroke is the blow's (`game.strikeSegment`), handed in: a flash somewhere the blade was not
// is a spell whose picture and mechanic disagree.

/// **THE ELEMENT HAS NO TRAVEL IN ITS OWN MOTES** — `elemfx`'s lightning is the shortest life in the table by a
/// factor of three and the only one with no gravity, which is the whole read: a spark is dead before it
/// arrives. So the travel has to come from WHERE THE SPARKS ARE PUT, all on the one frame the blow lands.
const LEVIN_STEPS = 9; // sites down the stroke…
const LEVIN_SPARKS = 3; // …and the handful thrown off each
const LEVIN_BURST = 26; // the shower where it lands — the bolt's own count, one size up
/// How far off the line a site may sit. A straight run of equal dots is a laser, and NOTHING DEAD IS STRAIGHT.
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

/// THE SIPHON is the SOULS' DROP one system along (`souls.zig`): motes solved to ARRIVE at the stone inside
/// their own life, off the body they are being taken out of. Chaos's own grav is 0 (`elemfx`), so there is no
/// ballistic term to solve against — only the tip's own motion, which is what makes the life SHORT (the
/// gather's law: what is left over after riding the tip is ½·a·life², and it pays quadratically).
const SIPHON_MOTES = 34;
const SIPHON_LIFE_LO = 0.18;
const SIPHON_LIFE_HI = 0.30;
/// How wide off the body's own axis they are drawn out of it.
const SIPHON_SPREAD = 0.30 * H;

/// **THE LANCE IS THE LEVIN'S CONSTRUCTION WITH ONE THING CHANGED: IT DOES NOT END.** Sites walked down a
/// line, sparks thrown off each — but the count THINS toward the far end rather than finishing in a shower,
/// because a terminal burst is what says "it arrived", and the whole read on this spell is that it did not
/// stop. More sites than the stroke's nine: the line is twenty metres where that one is a body's height.
const LANCE_STEPS = 22;
/// The near end's throw. Thinned to one by the tip (`lanceBeam`), so this is the THICK end of a taper.
const LANCE_SPARKS = 4;
/// How far off the line a site may sit — under the levin's, because a lance is a straighter thing than a
/// lightning stroke and this one may not read as torn.
const LANCE_JITTER = 0.06 * H;
/// **THE SHORT LIFE IS BOUGHT BACK WITH RADIUS** — the stroke's own law. Fire lives longer than lightning in
/// `elemfx`, so this sits under the levin's 2.2: at the same throw the shaft photographed as a hedge.
const LANCE_SPARK_SCALE = 1.7;
/// The shaft is cast level out of the rod, so its own y is a metre up — floored THERE a mote that fell would
/// stop in mid-air, which is `levinStroke`'s own trap. Dropped to about the ground under him.
const LANCE_FLOOR_DROP = 1.05 * H;

/// **SUNDER THROWS A RING, NOT A PUFF** — every other burst here is a scatter, and a scatter is what "an
/// impact" already looks like. What this spell is about is something LETTING GO, so the motes leave low and
/// outward on a walked angle, and they are dust and chips rather than any element's mote.
const SUNDER_MOTES = 28;
const SUNDER_SPEED_LO = 2.2;
const SUNDER_SPEED_HI = 5.0;
const SUNDER_DUST = mathx.rgba(126, 116, 100, 190);
const SUNDER_CHIP = mathx.rgba(78, 68, 56, 215);

// ONE substance: the chaos violet stays the light ON the wood, never a second violet thing.
const ROOT_SITES = 3;
/// Tendrils one site throws — each differently sized, leaned and DELAYED, or it is a rosette of equal spikes.
const ROOT_FANS = 9;
const ROOT_RISE: f32 = 0.20; // s
const ROOT_SINK: f32 = 0.55; // s
/// The stagger between the first tendril and the last, as a fraction of the rise.
const ROOT_LAG: f32 = 0.55;
/// …and how far the tear OVERSHOOTS its own height before settling onto it (the reactions law, on a prop).
const ROOT_PUNCH: f32 = 0.20;
/// Variants of the tendril mesh — one shape yaw-rotated nine times reads as a periodic pattern.
const ROOT_KINDS = 3;
/// Enough that the curl reads as a CURVE and not a chain of straight sticks. The mesh is built ONCE per
/// variant, so the count is free at run time — but the total arc is `curl` × the count (see `rootTendrilMesh`).
const ROOT_SEGS = 10;
/// ~1.05 m — HIP height on the 1.8 m rig, and bracketed from both sides: lower and it is scenery round the
/// ankles, man-height and the tendrils hide the creature they are holding.
const ROOT_LEN = 0.58 * H;
const ROOT_R0 = 0.052 * H; // ~9 cm through at the earth, tapering to ~3 at the snap
const ROOT_R1 = 0.019 * H;
/// MEASURED, NOT GUESSED (AGENTS.md): at `34,25,18` on `.bark` these sampled 115,94,68 against grass at
/// 110,97,67 — the same value, so they read as pale timber for want of any separation at all. SOLVED from
/// there: screen = (albedo/255 × 1.72)^(1/2.2) × 255, so half the ground's 110 is screen 55, and 55 back
/// through the chain is albedo 5. `.wood` is the material that does not lift it again (it is the rod's own).
/// The two bark tones are kept CLOSE: pushed apart they band the shaft like a barber's pole.
const ROOT_BARK = rgba(5, 4, 3, 255);
const ROOT_BARK_LT = rgba(9, 7, 5, 255);
/// …and the blunt snap of pale heartwood every one of them ends in (the dead-limb law). Solved to land at the
/// ground's own value, so it POPS off a near-black shaft — but it is a snap, not a sawn plank end, so it is small.
const ROOT_HEART = rgba(24, 21, 15, 255);
const ROOT_SOIL = mathx.rgba(96, 78, 58, 190);
const ROOT_DUST = 34;
const ROOT_MOTES = 26;
/// Rise, then the GRIP'S OWN span, then the sink — so what is standing in the ground IS how long the foe in it
/// has left, rather than a second clock that can disagree with `combat.Root`.
const ROOT_LIFE: f32 = ROOT_RISE + combat.ROOT_HOLD + ROOT_SINK;
/// …and the SITE outlives that by the fan's own stagger: cut at `ROOT_LIFE` the last tendril is still an
/// eighth of its height when the site stops drawing, and a root sinks — it is never popped away.
const ROOT_SITE_LIFE: f32 = ROOT_LIFE + ROOT_RISE * ROOT_LAG;

const RootSite = struct {
    at: rl.Vector3 = mathx.zero3,
    t: f32 = mathx.LONG_AGO, // …so an untouched slot is already spent
    seed: f32 = 0,
};

// THE RIME BREATH — the rod's third sorcery, and the only one that is a DIRECTION rather than a mark. What
// the numbers here own is the PICTURE; the mechanic's own (reach, arc, span, what it bills) are
// `combat.RIME_*`, so the cone that is drawn cannot say something different from the cone that hits.

/// Motes a second poured out of him — THE LANGUAGE'S OWN RATE (`elemfx.POUR_RATE`), not a second number
/// here: what the editor's bench is tuned at has to be what arrives in the fight.
const BREATH_RATE = elemfx.POUR_RATE;
/// …and the ceiling on ONE frame of it, `CAST_MOTE_CAP`'s reason exactly: the accumulator is what makes the
/// rate independent of the frame rate, and without a cap a single hitch empties the whole ring in one go.
const BREATH_CAP = elemfx.POUR_CAP;
// HOW BIG A FROST MOTE IS is NOT here: a jet's grain is finer than the signature table's, and that is a fact
// about POURING rather than about him (`elemfx.POUR_GRAIN`). Held here as his own it was passed in through
// `scale`, so the editor's bench — which is where this is tuned — drew the same stream 60% coarser.

/// WHERE IT LEAVES HIM — **THE ROD'S TIP** (owner's call). The rod is what pays for every other sorcery and
/// throws two of them; a third that came out of his face made the wand a prop for one spell in three. A hair
/// further out than `wandTipWorld` so the first motes clear the stone instead of starting inside it.
const BREATH_NOZZLE_FWD = 0.030 * H;
/// The trunk braces BACK against what the rod is pushing out and OVERSHOOTS its rest coming off it (the
/// reactions law) — through the WAIST, spine and chest, never the root. Degrees, total across the two.
const BREATH_LEAN = -13.0;
/// …and the head TRACKS the stream rather than pouring it: he is aiming the rod, so he looks down its line.
const BREATH_HEAD = 6.0;
/// How much FURTHER the rod arm straightens through the pour, past where the throw already snapped it.
const BREATH_REACH = 12.0;
/// **AND THE ROD COMES DOWN TO LEVEL FOR IT, which is a mechanic and not a flourish.** The throw beat leaves
/// the shoulder at `CAST_SH_FWD` (118 deg — well past straight out), because a BOLT is thrown at a mark that
/// may be above him. The cone is not: `breathDir` is level by construction and the bite is tested in XZ, so a
/// rod still pointed at the sky is a picture promising a reach the mechanic does not have. Subtracted off the
/// flexion to land near 78 deg — a shade UNDER straight out, which is where the arm has to sit for the STONE
/// to end up level: the wand is held at an angle in the fist, so a shoulder at a true 90 still points it up.
const BREATH_SH_LEVEL = 40.0;
/// …and it SHIVERS while it pours, because a held pose for the better part of a second is a freeze frame.
const BREATH_SHIVER = 1.5;
const BREATH_SHIVER_HZ = 12.0;

const FX_N = 1280;

comptime {
// The ring overwrites its oldest silently, so FX_N is arithmetic over the constants above, not a taste.
    const gather = CAST_MOTE_RATE_HI * CAST_MOTE_LIFE_HI;
    const release = CAST_SPARKS + CAST_COLLAR + 1;
    // …and the ROOTS' own burst, which shares this one pool and is thrown on the same frame a gather ends.
    const erupt = ROOT_DUST + ROOT_MOTES;
// …and the shield's sparks: a parry cannot run WITH a cast, but its sparks outlive the swap.
    const caught = PARRY_SPARKS + 1 + PARRY_GLINT + 1; // a caught parry also glinted on its own whip frame
    // …AND THE BREATH, which is the biggest single claim on the pool: a POUR is resident for its whole span
    // where every other effect here is a burst that is already dying. The whole pour, because `elemfx`'s cold
    // outlives `RIME_DUR` — a mote emitted on the last frame is still in the air.
    const ticks = @ceil(combat.RIME_DUR * BREATH_RATE);
    const breath = @as(f32, @floatFromInt(elemfx.pourCount(1))) * ticks;
    // …and the two STRIKES, which land on the frame they are cast rather than after a flight, so their whole
    // claim is in the air at once. They cannot run WITH a pour — but the pour's motes outlive their cast, and
    // the rod may be turned to another spell the moment it ends, so the pool has to hold both.
    const struck = LEVIN_STEPS * LEVIN_SPARKS + LEVIN_BURST + SIPHON_MOTES;
    const worst = gather + breath + @as(f32, release + erupt + caught + struck + 2 * BOLT_BURST); // two bolts can land across chained casts
    if (@as(f32, FX_N) < worst) @compileError(std.fmt.comptimePrint(
        "hero: FX_N = {d} but a cast can have {d} particles in the air — raise it",
        .{ FX_N, worst },
    ));
}

/// `CHAOS_MOTE` itself, not a second literal that looks like it.
const WAND_LIT = mathx.colVec(CHAOS_MOTE);
/// Radius matters more than brightness (the chapel's law), so the carry's ember is SHORT as well as dim: at a
/// torch's 6 m it washed him violet head to foot standing still.
const WAND_LIT_CARRY = 0.20;
const WAND_LIT_CARRY_R = 2.6;
const WAND_LIT_CHARGED = 1.00;
const WAND_LIT_CHARGED_R = 7.0;
const WAND_LIT_FLARE = 2.30;
const WAND_LIT_FLARE_R = 12.0;

/// HOW FAR THE WAIST WILL FOLD ONTO A MARK (deg, total across SPINE + CHEST).
pub const AIM_LEAN_DOWN = 34.0;
pub const AIM_LEAN_UP = 12.0;
/// …and how fast he gets there (deg/s).
const AIM_LEAN_RATE = 190.0;
const AIM_LEAN_BIAS = 7.0;

pub const BLADE_R = 0.34; // capsule radius (world units)

const TRAIL_N = 20; // ring capacity (~0.3 s of samples at 60 fps)
const TRAIL_LIFE = 0.20; // seconds a sample persists
const TRAIL_ROOT = 0.35; // ribbon spans this fraction down the blade → the tip
const TRAIL_PEAK = 84.0;

pub const HP_MAX = statsmod.hpFor(statsmod.START); // 70 — VITALITY owns it (`stats.zig`)
pub const POISE_MAX = 55.0;
pub const STANCE_MAX = 90.0;
pub const ATK_LIGHT_HIT = combat.Hit{ .dmg = 13, .poise = 10 };
pub const ATK_HEAVY_HIT = combat.Hit{ .dmg = 27, .poise = 22, .stance = 14 };

pub fn freshVitals(sheet: statsmod.Sheet) combat.Vitals {
    return combat.Vitals.init(sheet.hp(), POISE_MAX, STANCE_MAX);
}

// WHAT HE IS WEARING AND HOLDING (`item.Equip`)
//
// **BARE IS THE GAME EXACTLY AS IT WAS**, and that is the whole reason this could be added without retuning one
// existing number: every dial on an `item.Arm` defaults to 1, and the armour curve of 0 armour is the blow
// itself. A `null` socket therefore costs nothing and means nothing, which is what an empty socket should do.

/// WHAT IS IN EACH SOCKET, or null for bare. The BAG still owns the item — this only says which of them is in
/// use, so taking a thing off never loses it (`item.wearSlot` is the match between a kind and its socket).
/// **ONE CELL PER SOCKET, INDEXED BY THE SOCKET ITSELF.** Written out as ten named fields it was three parallel
/// lists — the `item.Wear` tags, the fields, and the two switches translating between them — whose names did not
/// even agree (`hand_sword` against `sword`), so a new socket was four edits to say one thing. Off the enum there
/// is nothing to keep in step: a tag gains its cell by existing, which is the same rule `save.render` and
/// `hero.armourOf` already walk this by.
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
    var out = item.Plate{ .slot = .chest }; // an aggregate wears no socket; `charmOf`'s own dummy
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

/// **…AND THE SAME SUM DOWN THE FOUR ELEMENTAL COLUMNS** (`item.Res`). **THIS IS THE ONE PLACE `item.Res`'s
/// four floats BECOME `combat.Elem`** (`settleResists`), which is why item.zig may name neither: `wearFor`
/// matches a `Wear` to an `Armament` here for exactly the same reason, and a second site that did this
/// mapping could put the cold column on fire and compile.
pub fn resistOf(worn: Worn) item.Res {
    return plateOf(worn).res;
}

/// …AND HOW FAST A STATUS FILLS THROUGH THE SUIT.
pub fn poisonRateOf(worn: Worn) f32 {
    return plateOf(worn).poison;
}

/// …AND EVERY CHARM ON IT, ADDED UP. A FREE function for `armourOf`'s own reason: the character page prices a
/// set he is only considering (`book.derive`), and the red bar's length is one of the numbers that moves.
pub fn charmOf(worn: Worn) item.Charm {
    var out = item.Charm{ .slot = .ring };
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        if (worn.at(@enumFromInt(f.value))) |k| {
            switch (item.equip(k)) {
                .charm => |c| {
                    out.leech += c.leech;
                    out.hpFrac += c.hpFrac;
                    out.fpFrac += c.fpFrac;
                    // **MULTIPLIED, like `poisonRateOf`** — the two are the same kind of dial, and summed a
                    // second discount would be a free call rather than a better one.
                    out.spiritFp *= c.spiritFp;
                },
                else => {},
            }
        }
    }
    return out;
}

/// THE RED BAR'S LENGTH FOR A SHEET AND A SUIT — the sheet's own figure less whatever a charm is eating.
/// `Hero.refitHp` is this same expression on the live man; the page needs it off a loadout.
pub fn hpMaxOf(sheet: statsmod.Sheet, worn: Worn, perk: ptree.Bonus) f32 {
    // **AND THE BERSERKER'S BARGAIN EATS THE SAME BAR A CHARM DOES** (`passivetree.Grant.sacrifice`) — the two
    // costs ADD before the clamp, so a leech signet worn under Berserk cannot take more than the floor allows
    // and a build that stacked both can still be alive.
    const eaten = charmOf(worn).hpFrac + perk.hpFrac;
    return sheet.hp() * (1.0 - mathx.clampF(eaten, 0, 0.9));
}

/// …AND THE BLUE BAR'S, on exactly the same terms. Its own function rather than a flag on the red one's:
/// `refitBars` writes three pools and the page prices all three, so the two bars a charm can eat into have to
/// answer the same shape of question.
pub fn fpMaxOf(sheet: statsmod.Sheet, worn: Worn, perk: ptree.Bonus) f32 {
    // …and the WELL branch lengthens it (`passivetree.Grant.fpMax`), which is the one thing on either bar
    // that pushes the other way — applied after the charm's bite, so a deeper pool is deeper for real.
    return sheet.fp() * (1.0 - mathx.clampF(charmOf(worn).fpFrac, 0, 0.9)) * perk.fpMax;
}

/// …AND WHAT IT IS WORTH IN POINTS OF SKILL, folded onto a sheet that already carries the tree's (`item.Boon`).
/// Walked over the SOCKETS rather than named per piece, so a boon in a socket nobody thought about still counts.
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

/// A POOL RESIZED WITH ITS FRACTION KEPT — `Hero.refitHp`'s rule, for the two bars that have no charm eating them.
fn refitPool(cur: *f32, max: *f32, to: f32) void {
    const frac = if (max.* > 1e-4) cur.* / max.* else 1.0;
    max.* = to;
    cur.* = mathx.minF(to, to * frac);
}

/// WHAT A ROW'S SCALING IS WORTH ON THIS SHEET — the ONE place `item.Scaling` and `stats.Attr` are matched up
/// (`wearFor`'s own rule, one shelf along). A quality weapon takes the MEAN of the two curves, which is what
/// makes the straight sword worth investing in either way and best under neither build.
pub fn scaleOf(sheet: statsmod.Sheet, s: item.Scaling) f32 {
    return switch (s) {
        .strength => sheet.scale(.strength),
        .dexterity => sheet.scale(.dexterity),
        .quality => 0.5 * (sheet.scale(.strength) + sheet.scale(.dexterity)),
    };
}

/// THE ROW FOR WHAT IS IN A SOCKET, off a `Worn` — a FREE function so the character book can price a loadout it
/// is only considering (`book.derive`) through the same table the fight reads. All ones for an empty socket.
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
const DEATH_SINK = 0.30; // death: pelvis sinks to this fraction of stance height
pub const DEATH_DUR = 3.6; // collapse + lie still before the hero respawns

const GUARD_SH_FLEX = 24.0;
const GUARD_SH_CROSS = 40.0;
const GUARD_SH_ABD = 2.0; // elbow tucked IN, near the ribs — a shield held out on a straight arm is a target
const GUARD_ELBOW = 96.0;
const GUARD_BLADE = 9.0; // trunk yaw toward the shield side (deg, PER SEGMENT over spine + chest)
const GUARD_CROUCH = 0.022 * H;
const GUARD_SWORD_BACK = 40.0;
const GUARD_SWORD_ELBOW = 46.0;
const GUARD_SWORD_WRIST = 30.0;
const GUARD_HEAD = 6.0;
const GUARD_BLEND_RATE = 11.0;
const BLOCK_RECOIL_DUR = 0.24; // seconds — over before the next swing, so blocking never costs tempo
const BLOCK_SHIELD_BACK = 15.0; // deg off the flex
const BLOCK_SHIELD_FOLD = 10.0;
const BLOCK_TRUNK = 9.0;
const BLOCK_STEP = 0.14 * H;
const BLOCK_SINK = 0.048 * H;
const BLOCK_FLASH = 0.22; // a LICK of red, well under `takeHit`'s 0.35 for a blow that got through

// One short committed shove with a catch window at the front. It does NOT ask whether the guard is up, and
// `canGuard` refuses while it runs — that tail is the risk it is priced on.
pub const PARRY_DUR = 0.52;
/// It opens off a REAL wind-up (owner: boards should be slower off the mark) — a tenth of a second in which
/// the coil is already readable — and shuts by half way, so the recovery is honestly open.
const PARRY_OPEN = 0.10;
const PARRY_SHUT = 0.26;
/// Where the shove PEAKS as a fraction of the duration, kept INSIDE the window: the frame that catches has to
/// be the frame the boards are furthest out, or the pose and the mechanic are telling different stories.
pub const PARRY_PUNCH_AT = 0.33;
/// A MASS IN MOTION OVERSHOOTS ITS REST — three quarters of a turn, so the arm crosses its rest once first.
const PARRY_REBOUND = 0.75;
/// THE THRUST, AND IT IS PAID FOR AT BOTH JOINTS. `shieldFit` is the INVERSE of the guard's arm fold
/// (`GUARD_ARM_FOLD` = shoulder flex + elbow), so the boards keep their facing only while that SUM does:
/// opened at the elbow alone, a shove this size rotates the shield clean off its own arm (measured).
const PARRY_PUNCH = 60.0;
/// …and the boards SQUARE UP onto the threat, unwinding the guard's own cross rather than carrying on past it.
const PARRY_SWEEP = 26.0;
const PARRY_WRIST = 20.0; // deg of cant in the fist, kept small: the fold does the work
/// THE SWIPE, AND IT IS DRIVEN FROM THE WAIST — which is why the sweep is not at the shoulder: a shoulder yaw
/// big enough to carry the boards across turns their FACE with it (`shieldFit` inverts that yaw). Deg PER SEGMENT.
const PARRY_TRUNK = 52.0; // (owner: the swipe was not reading — the waist is the face-safe channel to spend on)
/// …and the SHOULDER adds a little on top, so the boards outrun the chest carrying them. Small, because every
/// degree of it turns the shield's face as well as moving it: this is the axis `shieldFit` inverts.
const PARRY_ARM_LEAD = 16.0;
/// He COILS the other way first, then whips across, then settles back onto centre — three phases, own clock.
pub const PARRY_COIL_AT = 0.17; // fraction of the action spent winding up…
/// …and where the arc has been fully crossed. SOLVED, not chosen: `smoothstep` is half way through at half its
/// span, so the boards cross CENTRE at `COIL_AT + (END - COIL_AT)/2`, and this value puts that crossing exactly
/// on `PARRY_PUNCH_AT` — the frame the thrust peaks, which is the frame that catches.
pub const PARRY_SWEEP_END = 2.0 * PARRY_PUNCH_AT - PARRY_COIL_AT;
/// The share of the turn the PELVIS takes; the rest is waist. All of it at the root reads as a spin.
const PARRY_PELVIS = 0.30;
const PARRY_PITCH = 8.0; // he leans INTO it, about the feet
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
const PARRY_SPARK_FAN = 9.0; // m/s, peak sideways off the boss…
const PARRY_SPARK_OUT_LO = 1.0; // …and off the face itself
const PARRY_SPARK_OUT_HI = 3.2;
const PARRY_SPARK_R0_LO = 0.009;
const PARRY_SPARK_R0_HI = 0.019;
const PARRY_SPARK_GRAV = 9.0;
/// A hair PROUD of the surface a burst comes off, or the first frame's motes are half-buried in the boards
/// they were struck from. Named because BOTH shield emitters need exactly the same clearance.
const SPARK_PROUD: f32 = 0.02;
/// One bloom on the boss, SMALL for the cast flash's reason: a solid sphere, not additive, so at 0.085 it read
/// as a puff of smoke sat on the boards — on the FIRST frame it and every spark are still at the same point.
const PARRY_FLASH_R = 0.05;
const PARRY_FLASH_LIFE = 0.06;
/// One glint off the boards at the whip's peak, catch or no catch: under the zero-input-lag law a committed
/// action that shows nothing is a dropped input. Deliberately less than the catch's shower.
const PARRY_GLINT = 18;
/// TIGHTER THAN THE CATCH'S FAN, NOT WIDER. Thrown as far and lived as long as struck iron, a dozen motes
/// were strewn across the grass a metre off the boards five frames later and read as litter (measured) —
/// a glint has to HUG the shield and be gone. Count buys the brightness, the fan and the life buy the read.
const PARRY_GLINT_FAN = 4.5;
/// LAID ALONG THE ARC, not thrown from a point. Every burst here is coincident on its emission frame, and a
/// whiffed swipe has no impact to justify a flash — a white ball beside the boards read as an artifact
/// (measured). Spread over the sweep's own axis it is a STREAK from the first frame.
const PARRY_GLINT_SPAN = 0.22; // metres either side of the boss, along the direction of travel
const PARRY_GLINT_TRAIL = 0.55; // …and they carry that much of the fan along it, so the streak drifts on
/// …and the bloom is UNDER the catch's 0.05, not over it: at 0.075 the first frame was a solid white ball
/// sitting beside the boards (measured), which is the balloon the cast flash's own note warns about.
const PARRY_GLINT_FLASH_R = 0.03;

/// **A BLOCK IS NOT A SMALL PARRY** (owner). A catch REFUSES a blow — struck iron, hot, thrown wide, gone in
/// a flash. A block ABSORBS one, so what comes off the boards is DULL and SHORT and hugs the shield.
const BLOCK_GRIT = rgba(196, 190, 178, 225); // pale stone-grey, nowhere near the spark's amber
const BLOCK_GRIT_DARK = rgba(120, 112, 100, 210);
/// COUNT IS THE BLOW'S, not the shield's: a kobold's bite and an ogre's slam may not scatter the same boards
/// the same way. Scaled between these off the same `weight` the shake and the pad are (`game.heroBlockBeat`).
const BLOCK_GRIT_MIN = 10;
const BLOCK_GRIT_MAX = 26;
/// SHORT and CLOSE — the opposite of the spark's wide fan and long tail.
const BLOCK_GRIT_OUT_LO = 0.5;
const BLOCK_GRIT_OUT_HI = 1.7;
const BLOCK_GRIT_FAN = 3.4;
const BLOCK_GRIT_GRAV = 13.0; // heavier than a spark: it is grit, and it drops
const BLOCK_GRIT_LIFE_LO = 0.10;
const BLOCK_GRIT_LIFE_HI = 0.30;
const BLOCK_PUFF_R = 0.11; // …and the bloom is WIDE and DIM where the catch's is small and white-hot
const BLOCK_PUFF_LIFE = 0.16;

const SHIELD_R = 0.115 * H;
const SHIELD_THICK = 0.020 * H;
const SHIELD_WOOD = rgba(56, 41, 29, 255);
const SHIELD_WOOD_LT = rgba(82, 62, 44, 255);
const SHIELD_IRON = rgba(26, 28, 34, 255);
const SHIELD_BOSS = rgba(46, 49, 58, 255);
const SHIELD_STANDOFF = 0.045 * H; // the boards ride this far off the fist — a CENTRE GRIP, hand behind the boss
// The mesh is authored FACE-ON (a disc in XY, face along +Z) and this turns it into the left WRIST's frame.
const GUARD_ARM_FOLD = GUARD_SH_FLEX + GUARD_ELBOW;
const SH_FOLD_S = @sin(radians(GUARD_ARM_FOLD));
const SH_FOLD_C = @cos(radians(GUARD_ARM_FOLD));
const SH_CROSS_S = @sin(radians(GUARD_SH_CROSS));
const SH_CROSS_C = @cos(radians(GUARD_SH_CROSS));
/// The face's own normal in the WRIST's frame — where the standoff has to be measured, since the hand grips
/// BEHIND the boss.
const SHIELD_N = v3(SH_CROSS_S, -SH_CROSS_C * SH_FOLD_S, SH_CROSS_C * SH_FOLD_C);
/// …and where the middle of the boards SITS in that frame, the hand gripping behind the boss.
const SHIELD_HUB = v3(
    SHIELD_STANDOFF * SHIELD_N.x,
    FIST_Y + SHIELD_STANDOFF * SHIELD_N.y,
    FIST_Z + SHIELD_STANDOFF * SHIELD_N.z,
);
/// Measured and left: every input is a compile-time constant, so this rebuilds the same matrix twice a frame.
/// The boards' turn onto the forearm. MIRRORED for the right hand: the cross and the hub are both lateral,
/// and unmirrored a shield equipped right folded the wrong way and hung off the outside of the arm.
fn shieldFit(left: bool) rl.Matrix {
    const sd: f32 = if (left) 1.0 else -1.0;
    return mul3(ry(sd * GUARD_SH_CROSS), rx(GUARD_ARM_FOLD), tr(sd * SHIELD_HUB.x, SHIELD_HUB.y, SHIELD_HUB.z));
}

const GRIP_PITCH = 34.0; // deg the blade leads forward of the forearm line
const GRIP_OUT = 8.0; // deg the tip eases outward, so the low-ready hangs beside the leg, not across the shin
const GRIP_CA = @cos(radians(GRIP_PITCH));
const GRIP_SA = @sin(radians(GRIP_PITCH));
const OUT_CA = @cos(radians(GRIP_OUT));
const OUT_SA = @sin(radians(GRIP_OUT));
const FIST_Y = -0.05 * H; // fist centre in the wrist frame
const FIST_Z = 0.005 * H;
// A point t (units of H) down the canted blade axis from the fist centre, wrist frame.
fn bladeAt(t: f32) rl.Vector3 {
    return v3(-GRIP_SA * OUT_SA * t * H, FIST_Y - GRIP_CA * t * H, FIST_Z + GRIP_SA * OUT_CA * t * H);
}
const BLADE_BASE = bladeAt(-0.06); // guard end, pulled back toward/through the fist
const BLADE_TIP = bladeAt(0.64); // point, extended past the visible tip for reach (the far end of the arc lands)

const CARRY_DAMP = 0.45; // fraction of the gait swing the sword arm gives up
const CARRY_ELBOW = 14.0;
const CARRY_ELBOW_RUN = 30.0;
const CARRY_WRIST_LIFT = -54.0;
const CARRY_LIFT_WALK = 0.4;
const CARRY_ABD_RUN = 12.0;
const CARRY_WRIST_YAW = -48.0;
const CARRY_SWING_STILL = 0.6;

const POSE_XFADE = 0.09; // seconds — cross-fade over any pose discontinuity (roll start/end)
const SPEED_SMOOTH = 80.0; // units/s²

const GAIT_DIR_EASE = 22.0; // 1/s — fwdB/latB chase the body-frame travel direction
const STRAFE_ABD = 22.0; // peak frontal hip swing either side of the hip (deg)
const STRAFE_STANCE = 0.52; // fraction of the cycle each foot is planted (~4% double support)
// CADENCE HAS EXACTLY ONE DIAL: phase is driven by DISTANCE, so cadence = speed / STRAFE_CYCLE.
const STRAFE_CROSS = 38.0; // the crossing leg's hip FLEXION peak — it must pass IN FRONT of the stance
const STRAFE_BEHIND = 10.0;
const STRAFE_LAND = 7.0; // fore/aft hip offset at plant (deg), swept out linearly through stance
const STRAFE_CLEAR = 0.035 * H; // DAYLIGHT under the swing foot at mid-swing.
const STRAFE_SINK = 0.0055 * H; // how much SHORTER than dead-straight the leg is left
const STRAFE_PROT = 7.0; // pelvic TRANSVERSE rotation (deg)
const STRAFE_SWAY = 0.012 * H; // pelvis rides ONTO each planting foot
const STRAFE_LEAN = 2.5; // torso banks gently INTO the travel side (deg, cosmetic)
const BACK_STRIDE = 0.85; // backpedal steps shorten a touch too

pub const LEG_LEN = (0.530 - 0.039) * H;
const STRAFE_REACH = LEG_LEN * @sin(mathx.radians(STRAFE_ABD)); // half the stance sweep, in units
const STRAFE_CYCLE = 2.0 * STRAFE_REACH / STRAFE_STANCE; // body travel per FULL cycle
pub const STRAFE_DIP = LEG_LEN - @sqrt((LEG_LEN - STRAFE_SINK) * (LEG_LEN - STRAFE_SINK) - STRAFE_REACH * STRAFE_REACH);

const STRIDE = 0.85 * H; // ground distance per full (two-step) cycle at walk pace — ties phase to travel, no foot-skate
const WALK_REF_SPEED = WALK_SPEED; // reference walk speed the stride is tuned for
const ARM_SWING = 9.0; // shoulder flex amplitude (deg) at walk — restrained, contralateral to the legs
pub const A_BOB = 0.024 * H;
const A_SWAY = 0.009 * H; // lateral pelvis sway toward the stance foot
const A_PROT = 3.5; // pelvic transverse rotation (deg)
const A_LIST = 2.0; // pelvic frontal drop toward the swing leg (deg)
const TORSO_LEAN = 3.0; // deg, forward torso lean while walking
pub const HIP_ADDUCT = 2.0; // constant leg-toward-midline angle so the stance narrows (deg)
pub const FOOT_TOEOUT = 6.0; // feet splay outward (Fick angle)
const ARM_ABD = 9.0; // constant arm abduction so arms clear the torso (deg)
pub const IDLE_KNEE = 4.0;
const SIT_Y = 0.115; // pelvis height in units of H — on the ground, not perched
const SIT_PITCH = 3.0;
const SIT_SPINE = 8.0;
const SIT_CHEST = 4.0;
const SIT_HIP_FLEX = 52.0; // a THIGH ON THE FLOOR, not a knee at the chest
const SIT_HIP_ABD = 62.0;
const SIT_KNEE = 118.0;
const SIT_ANKLE = 6.0;
const IDLE_ELBOW = 6.0;
const MOVING_EASE = 10.0; // idle↔walk blend rate (1/s)

pub fn sampleCurve(tbl: [8]f32, phase: f32) f32 {
    const ph = phase - @floor(phase); // 0..1
    const t = ph * 8.0;
    const base: usize = @intFromFloat(@floor(t));
    const a = base % 8;
    const b = (base + 1) % 8;
    const f = t - @floor(t);
    return tbl[a] + (tbl[b] - tbl[a]) * f;
}

// The single source of walk/strafe for the hero AND every humanoid enemy. Stride `phase` accumulates by
// DISTANCE, never time, so feet never skate.
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
    heel: f32, // how far the sole reaches BEHIND the bone origin (-^'z)
    toe: f32,
    halfW: f32,
    drop: f32, // how far BELOW the bone origin the sole plane sits (the ankle joint height)
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

/// **THE PELVIS'S FOUR CHANNELS ON THE SHARED SCAFFOLD** — the breathing bob, the lateral sway, the
/// transverse rotation and the crossing-step dip. Every humanoid riding `legChain` needs all four and the
/// three that did were each assembling the same five lines out of `A_BOB`/`strafeSway`/`strafeProt`/
/// `STRAFE_DIP`; only `aprot` was ever honestly per-creature, so that is the only thing passed in.
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

/// **A COLLAPSED SKELETON'S LEGS**, `dk` being how far through the fall it is. The two bone creatures go
/// over the same way; as a copy each, the six angles were six literals in two files with nothing holding
/// them level.
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

/// The two axes a burst is fanned about, perpendicular to `axis` and to each other — a spray built on WORLD
/// axes reads as a puddle round his hand the moment the shield or the cast turns.
fn burstFrame(axis: rl.Vector3) struct { side: rl.Vector3, up: rl.Vector3 } {
    var side = mathx.perpXZ(axis);
    // An axis straight up or down has no horizontal perpendicular; any one will do, so long as it is stable.
    if (mathx.lenV(side) < 1e-3) side = v3(1, 0, 0);
    side = mathx.normV(side);
    return .{ .side = side, .up = mathx.normV(mathx.crossV(axis, side)) };
}

pub const Attack = enum { light, heavy };

/// **EVERYTHING HE CAN HOLD, AND EITHER HAND MAY HOLD ANY OF IT** (owner's call). It was two enums — a right
/// hand that could only ever be sword/bow/bell and a left that could only be shield/wand — so which hand a
/// thing lived in was a fact about its TYPE rather than a choice the player made. One set, two hands.
pub const Armament = enum { sword, bow, bell, shield, wand };

/// The two hands' old type names, now the same set. Kept so every `heromod.Arm` at a call site still reads as
/// "what is in that hand" rather than becoming a rename sweep across six files.
pub const Arm = Armament;
pub const Off = Armament;

/// HOW MANY THINGS ONE HAND CARRIES (owner: two options per hand). The swap button walks between them and no
/// further — a hand is a pair, which is what makes the choice one you make at the fire rather than in a menu
/// mid-fight.
pub const HAND_SLOTS: usize = 2;

/// WHICH HAND — the `hand` argument of `Hero.equip`/`slotAt`, named because `0`/`1` at thirty call sites is a
/// coin flip. There is no array behind them: the four slots are `arm`/`armAlt` and `off`/`offAlt`, and those
/// two functions are the only place the pair is resolved.
pub const RIGHT: usize = 0;
pub const LEFT: usize = 1;

/// EXHAUSTIVE, so a sixth armament that also does not swing is a row here and no edit elsewhere. A FREE
/// function rather than a `Hero` method, because the character book prices a CANDIDATE armament.
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

/// **A RAISED BOW TAKES BOTH HANDS.** The one armament that denies the other hand its own, which is why it is
/// asked about by name rather than by a flag on the row.
pub fn armTwoHanded(a: Armament) bool {
    return a == .bow;
}

/// **WHAT A PAIR OF HANDS IS ACTUALLY HOLDING** — `Hero.holds` off the two slots alone, so the character
/// book can price a CANDIDATE loadout that is in nobody's hands yet and get the same answer the fight will.
pub fn handsHold(arm: Armament, off: Armament, a: Armament) bool {
    if (armTwoHanded(arm)) return a == arm;
    if (armTwoHanded(off)) return a == off;
    return arm == a or off == a;
}

// One buffered action, ER-style: an attack/roll pressed while mid-action QUEUES here
pub const Queued = union(enum) { attack: Attack, roll: rl.Vector3 };

pub const Hero = struct {
    mesh: [N]rl.Mesh,
    bow: rl.Mesh,
    bowString: rl.Mesh,
    bowNock: rl.Mesh,
    /// Not a bone; it rides the left wrist through `shieldFit`.
    shield: rl.Mesh,
    /// …nor is the wand. Same route, but no fit matrix: it is authored IN that wrist's frame.
    wand: rl.Mesh,
    /// …and the bell rides the HELD slot, where the bow and the sword go.
    bell: rl.Mesh,
    /// Authored rising out of the earth at the origin. THREE meshes, because one shape yaw-rotated nine times
    /// is a periodic pattern.
    roots: [ROOT_KINDS]rl.Mesh,
    guitar: rl.Mesh,
    mat: rl.Material,
    rest: [N]rl.Vector3,
    xf: [N]rl.Matrix = undefined, // per-bone world matrix, recomputed each frame by pose()

    pos: rl.Vector3 = mathx.zero3,
    /// Whole-body pitch from the SLOPE he is standing on, in degrees, + = uphill ahead (lean into the climb).
    slopePitch: f32 = 0,
    facing: f32 = 0, // yaw radians, 0 = +Z
    phase: f32 = 0, // stride phase [0,1) (left-leg reference)
    moving: f32 = 0, // eased 0..1 walk blend
    speed: f32 = 0, // this frame's ground speed (world units/sec) — for HUD + stride scaling
    fwdB: f32 = 1, // eased travel-vs-facing FORWARD component (+1 ahead … -^'1 backpedal)
    latB: f32 = 0, // eased travel-vs-facing LATERAL component (+1 = stepping to his RIGHT)
    elapsed: f32 = 0,
    rolling: bool = false,
    /// A COUNTER, not a flag: a chained roll clears `rolling` and sets it again inside ONE frame, so a rising
    /// edge on the flag misses every roll after the first.
    rolls: u32 = 0,
    rollT: f32 = 0, // seconds into the current roll
    rollDir: rl.Vector3 = mathx.zero3, // world XZ unit direction of the roll
    rollYaw: f32 = 0, // committed heading of the roll; the visible yaw eases onto it fast
    rollSide: f32 = -1, // +1 = over the LEFT shoulder, -1 = the RIGHT (picked from the leading leg)
    rollVar: f32 = 1, // this roll's imperfection magnitude (ROLL_VAR_LO..HI, cosmetic only)
    /// His feet ABOVE the ground under him: `pos.y` stays the ground and `game.groundActor` stays its one
    /// writer. ZERO unless he is airborne, so a teleport can never strand him standing on nothing.
    lift: f32 = 0,
    /// The WORLD height of his feet while airborne, integrated under gravity; `lift` is DERIVED off it every
    /// frame. Run off a ledge and the datum falls away underneath, so the gap opens on its own — where a lift
    /// integrated over a moving datum sinks with the ground it was measured from.
    airY: f32 = 0,
    vertVel: f32 = 0,
    /// A jump is a COMMITTED action (`committed()`) and it runs to touchdown. `dropActions` deliberately does
    /// NOT clear it: flinched mid-air, he still has to come down.
    jumping: bool = false,
    /// Counted like `swings`/`rolls`, for the same reason.
    jumps: u32 = 0,
    airYaw: f32 = 0, // heading committed at takeoff; the stick bends it at `AIR_TURN_RATE`
    airSpeed: f32 = 0, // …and the ground speed it left with, which the stick may never touch
    /// ONE FRAME, the frame his feet touch down — game.zig thumps off it. Cleared in the prologue like `loosed`.
    landed: bool = false,
    landT: f32 = mathx.LONG_AGO, // seconds since touchdown: the absorb, and nothing mechanical reads it
    attacking: bool = false,
    atkT: f32 = 0, // seconds into the current swing
    queued: ?Queued = null,
    atkHeavy: bool = false,
    atkAlt: bool = false, // light-combo alternator: false = forehand slash, true = the RETURN backhand
    swings: u32 = 0,
    bladeA: rl.Vector3 = mathx.zero3, // blade capsule endpoints in WORLD space (guard → tip)
    bladeB: rl.Vector3 = mathx.zero3,
    bladeA0: rl.Vector3 = mathx.zero3,
    bladeB0: rl.Vector3 = mathx.zero3,
    hitWasActive: bool = false, // edge detector: sweep history (+ future hit list) resets on activation
    trail: foemod.Trail(TRAIL_N) = .{}, // the shared swing ribbon (`foe.zig`)
    fx: [FX_N]foemod.Particle = [_]foemod.Particle{.{}} ** FX_N,
    fxHead: usize = 0,
    /// Re-read wherever he is made whole (`makeWhole`) — the only moment a sheet can have changed and the
    /// only moment a bar may resize. DERIVED off the tree, and `game.applyTree` is the one writer.
    sheet: statsmod.Sheet = .{},
    /// Folded once and STAMPED on him: he reads fields off it and never walks the node list.
    perk: ptree.Bonus = .{},
    /// …and WHAT HE HAS PUT ON, which is the same arrangement one system along: read as fields, never searched
    /// for. Every socket empty is the game as it shipped (`Worn`).
    worn: Worn = .{},
    vit: combat.Vitals = freshVitals(.{}),
    stam: combat.Stamina = .{}, // ER's third bar — the hero's alone; foes don't carry one
    fp: combat.Focus = .{},
    souls: combat.Souls = .{},
    flasks: combat.Flasks = .{}, // Crimson + Cerulean — their charges; WHICH is up is the bar's business
    /// THE QUICK BAR the cross's DOWN slot is turned to, and in combat the only reach he has (`game.inCombat`).
    quick: combat.Quick = .{},
    /// …and the ARROWS, which are finite: an empty quiver refuses the shot (see `startShot`).
    quiver: combat.Quiver = .{},
    regen: combat.Regen = .{},
    /// The resistances a bonfire does NOT refill (`makeWhole` carries them across). Nothing grants him any
    /// yet; this is the field the day something does.
    baseRes: combat.Resists = .{},
    /// Timed chaos resistance (`combat.Timed`, which is where "refreshes, never stacks" lives now). It sits
    /// on top of `baseRes`, and `settleResists` is the one place the two are composed into `vit.res`.
    ward: combat.Timed = .{},
    /// The swing hangs `grease.amount` of its own physical as fire while its clock runs, read where the blow
    /// is BUILT (`attackHit`) so there is no second copy of the Hit.
    grease: combat.Timed = .{},
    /// …and the POISE bar refills at `steady.amount` times its rate while this one does — the broth's shape
    /// (`stam.startBrew`) on the bar that decides whether the next blow flinches him. Composed onto `vit` by
    /// `tickTimed` and nowhere else.
    steady: combat.Timed = .{},
    /// ONE meter that fills, procs, then drains. His alone for now: nothing applies one to a foe.
    poison: combat.Status = .{},
    drinking: bool = false,
    drinkT: f32 = 0,
    poured: bool = false,
    /// Seconds left on the "that was refused" flash.
    stamRefused: f32 = 0,
    sprinting: bool = false, // hold-B RUN, resolved by the caller — the only CONTINUOUS drain
    // Shaped like the GUARD, not like an attack: `aiming` is re-derived from the button every frame, and only
    // the LOOSE is committed.
    aimLean: f32 = 0,
    aimLeanWant: f32 = 0,
    /// **WHAT THE RIGHT HAND IS HOLDING RIGHT NOW**, and `armAlt` is the other of its two (`HAND_SLOTS`).
    arm: Armament = .sword,
    /// …and what the swap turns to. A hand is a PAIR and the button exchanges them, so the loadout is a
    /// decision made in the book and the swap is muscle memory — never a walk through five armaments.
    armAlt: Armament = .bow,
    aiming: bool = false,
    aimB: f32 = 0,
    shooting: bool = false,
    shotT: f32 = 0,
    shotAimed: bool = false,
    /// LATCHED when it was drawn, not read at the loose: the shaft leaves a few frames later, and cycling the
    /// quiver in between must not change what is already on the string.
    shotArrow: combat.ArrowKind = .plain,
    /// …AND THE ARMAMENT'S OWN ROW ON THE SAME RULE (`shotArrow`'s note, one axis along). What starts is what
    /// lands: the character book takes a variant while a swing or a draw is already in flight (`game.takeHand`
    /// deliberately lets the socket through where `equip` refuses), and read LIVE that swap re-priced and
    /// re-CLOCKED an action already running — a longer `dur` pulls `atkT / dur` back inside the strike window
    /// after it had closed, which re-arms `foe.strike`'s one-hit latch and lands one press on one body twice.
    atkRow: item.Arm = item.bareArm(.hand_sword),
    shotRow: item.Arm = item.bareArm(.hand_bow),
    /// ONE FRAME, the frame the shaft leaves — game.zig looses it from `nockWorld()`.
    loosed: bool = false,
    /// Counted like `swings`/`rolls`: a chained shot clears `shooting` and sets it again inside one frame.
    shots: u32 = 0,
    /// 0 = string home, 1 = full draw.
    drawAmt: f32 = 0,
    stringXf: [2]rl.Matrix = undefined,
    nockXf: rl.Matrix = undefined,
    nockVis: bool = false,
    lastNock: rl.Vector3 = mathx.zero3,
    off: Armament = .shield,
    offAlt: Armament = .wand,
    /// WHICH SORCERY THE ROD IS SET TO. NOT latched at `startCast` the way `shotArrow` is, and it does not
    /// need to be: `cycleSpell` refuses while a cast is running, so what starts is what throws.
    spell: combat.Spell = .bolt,
    /// A cast is running — COMMITTED, so it lives in `committed()` beside the swing and the loose.
    casting: bool = false,
    castT: f32 = 0,
    /// THE SWEEP ALTERNATOR, the light combo's `atkAlt`: repeated casts must be a PAIR of strokes sweeping
    /// opposite ways, not one animation replayed. Flipped at the START of each cast.
    castAlt: bool = false,
    /// Counted like `swings`/`shots`: a chained cast clears `casting` and sets it again inside one frame.
    casts: u32 = 0,
    /// ONE FRAME, the frame the bolt leaves — game.zig throws it from `wandTipWorld()`. For the RIME it is the
    /// frame the cone OPENS: a breath has no projectile, so what the edge hands over is the start of a window.
    thrown: bool = false,
    /// The breath's own emitter arrears, `moteAcc`'s twin and kept apart from it on purpose: the gather and
    /// the pour are two rates, and one accumulator carrying both would pour the raise's leftovers.
    breathAcc: f32 = 0,
    /// `spell`'s twin on the other hand. Whether he HOLDS its scroll is a question about the BAG, asked in
    /// game.zig; the hero only ever knows which one is chosen.
    spirit: combat.SpiritKind = .wolf,
    /// A ringing is running — COMMITTED, and it lives in `committed()` beside the cast for the same reason.
    ringing: bool = false,
    ringT: f32 = 0,
    /// ONE FRAME, the frame the bell SOUNDS and the spirit is owed. game.zig spawns off this rather than off
    /// `ringing` going false, so the beat lands on the note and not on the arm coming down after it.
    rang: bool = false,
    /// A RING, so a second cast leaves two holes rather than teleporting the first.
    rootSites: [ROOT_SITES]RootSite = [_]RootSite{.{}} ** ROOT_SITES,
    rootHead: usize = 0,
    /// Fractional motes the gather owes, carried between frames so a ramped rate is honest at any frame time.
    moteAcc: f32 = 0,
    /// Last frame's stone, differenced in `gatherMotes` for the tip's velocity. Written and read only there.
    tipPrev: rl.Vector3 = mathx.zero3,
    /// Its own field: flashing the stamina frame for a dry FP pool points the player at the wrong meter.
    fpRefused: f32 = 0,
    guarding: bool = false,
    guardB: f32 = 0,
    /// Seconds since the last blow caught on the shield. A PARRY stamps it too (`noteParry`): a caught blow is
    /// driven into the body exactly as a blocked one is, and a second clock could only disagree with this.
    blockT: f32 = mathx.LONG_AGO,
    /// A COMMITTED window, unlike the held guard it shares an arm with: it sits in `committed()`, is never
    /// buffered, and takes any block off him while it runs.
    parrying: bool = false,
    parryT: f32 = 0,
    /// Counted like `swings`/`casts`: a chained parry clears `parrying` and sets it again inside one frame.
    parries: u32 = 0,
    held: bool = false,
    stun: combat.StunKind = .none, // .light flinch / .heavy stagger (a committed reaction)
    stunT: f32 = 0, // seconds into the current stagger
    hurtFlash: f32 = 0, // 0..1 red damage-flash intensity (set on any hit, decays)
    dead: bool = false,
    deathT: f32 = 0, // seconds into the death collapse (respawns at DEATH_DUR)
    spawnPos: rl.Vector3 = mathx.zero3, // where a death respawns the hero
    spawnFacing: f32 = 0,

    speedS: f32 = 0, // short-eased ground speed driving POSTURE blends only
    blendT: f32 = mathx.LONG_AGO, // seconds since the last pose discontinuity (… POSE_XFADE = no blend)
    blendXf: [N]rl.Matrix = undefined, // frozen source pose for the cross-fade
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
        self.guardB = 0; // a SNAP, not the stagger's ease: he is somewhere else now
        self.aimB = 0; // …and the same for the aim, or the rest opens with the eye still up past his head
        self.stun = .none;
        self.hurtFlash = 0;
        self.makeWhole();
    }

    /// All three in ONE call: a caller that set two of them would leave a bar sized off the sheet he had a
    /// node ago. He is made WHOLE on the way out — nothing may spend a point away from a bonfire, so the one
    /// moment this runs is the one moment a refill is already owed.
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
        self.refitHp(); // …and what a charm is eating out of the red bar (`refitHp` keeps the fraction: it is full here)
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
        // `freshVitals` cleared `vit.res` above, so the base has to be laid back down here.
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
        self.rang = false; // …and the bell's note
        self.landed = false; // …and the touchdown's, for that same reason
        self.elapsed += dt;
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
        // Both have to move under every advance path, or the shield hangs mid-raise through a stagger and the
        // recoil freezes on whatever frame the block landed. The PARRY holds the stance blend up as the guard
        // does, or the shield sinks through its own window.
        self.guardB = mathx.approach(self.guardB, if (self.guarding or self.parrying) 1.0 else 0.0, dt * GUARD_BLEND_RATE);
        self.aimB = mathx.approach(self.aimB, if (self.aiming) 1.0 else 0.0, dt * BOW_BLEND_RATE);
        self.aimLean = mathx.approach(self.aimLean, self.aimLeanWant, dt * AIM_LEAN_RATE);
        self.blockT = @min(self.blockT + dt, mathx.LONG_AGO);
        self.landT = @min(self.landT + dt, mathx.LONG_AGO);
        // Gravity has a reason of its own to be here: a blow mid-air routes him to `updateStun` and a death to
        // `updateDeath`, and a man who stopped falling because he got hit would hang in the sky.
        self.tickAir(dt);
        self.souls.tick(dt);
        // Aged only inside `updateCast`, sparks would hang in the air and the ground splits would stand for good.
        foemod.tickParticles(&self.fx, dt, self.pos.y);
        for (&self.rootSites) |*s| s.t = @min(s.t + dt, mathx.LONG_AGO);
    }

    pub fn update(self: *Hero, dt: f32, movedDist: f32, speed: f32, moveYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = speed;
        advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist, speed, moveYaw, self.facing);
    }

    /// `pos` with the jump's height on it. Every `rootAt` site and the camera's shoulder read THIS; `pos`
    /// stays the ground under him, which is what the rest of the game measures from.
    pub fn footPos(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + self.lift, self.pos.z);
    }
    pub fn footY(self: *const Hero) f32 {
        return self.pos.y + self.lift;
    }
    /// Asked of the FLAG rather than the height, so the takeoff frame — lift still zero, feet already
    /// leaving — is airborne.
    pub fn airborne(self: *const Hero) bool {
        return self.jumping;
    }

    /// FREE: it is traversal, and `STAM_LOCKOUT` exists to punish greed in a fight, not to fence off the map.
    pub fn startJump(self: *Hero, dir: rl.Vector3, speed: f32) bool {
        if (self.committed() or self.dead or self.staggered() or self.resting) return false;
        self.jumping = true;
        self.jumps +%= 1;
        self.airY = self.pos.y;
        self.vertVel = JUMP_V0;
        // A standing jump goes STRAIGHT UP: no travel to carry, so it keeps the facing it had.
        self.airSpeed = if (mathx.lenXZ(dir) > 0.01) speed else 0;
        self.airYaw = if (self.airSpeed > 0.01) mathx.headingXZ(dir) else self.facing;
        self.startXfade();
        return true;
    }

    fn tickAir(self: *Hero, dt: f32) void {
        // NOT under the pause card: the menu branch still calls `update` for the breathing bob, and a man who
        // kept falling through it would be somewhere else when it closed.
        if (self.held) return;
        if (!self.jumping) {
            self.lift = 0;
            return;
        }
        // The CLOSED FORM, not `v -= g·dt; y += v·dt`: that plain pair loses g·t·dt/2 of height — NINE
        // CENTIMETRES of apex at 30 fps and none at 240. The half-a-dt² term is exact at every frame rate.
        self.airY += self.vertVel * dt - 0.5 * JUMP_G * dt * dt;
        self.vertVel -= JUMP_G * dt;
        // The ground that catches his feet may be higher or lower than the one he left, which is the whole
        // reason this is a velocity and not a scripted arc.
        if (self.airY <= self.pos.y) {
            self.airY = self.pos.y;
            self.lift = 0;
            self.vertVel = 0;
            self.jumping = false;
            self.landed = true;
            self.landT = 0;
            self.startXfade();
            self.fireQueued(); // …and whatever he pressed on the way down goes off now (the ER queue)
            return;
        }
        self.lift = self.airY - self.pos.y;
    }

    /// The stick bends the HEADING and nothing else. The step belongs to the mover: what a jump may fly OVER
    /// is a question about the ground, and the ground belongs to `env`.
    pub fn steerAir(self: *Hero, dt: f32, dir: rl.Vector3) void {
        if (self.airSpeed <= 0.01 or mathx.lenXZ(dir) < 0.01) return;
        self.airYaw = mathx.approachAngle(self.airYaw, mathx.headingXZ(dir), AIR_TURN_RATE * dt);
    }

    /// The clocks, the facing and the pose. The TRAVEL is `game.moveHeroAir`'s, for `steerAir`'s reason.
    pub fn updateAir(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = self.airSpeed;
        self.speedS = mathx.approach(self.speedS, self.airSpeed, dt * SPEED_SMOOTH);
        // At the ROLL's rate, which is the same relationship: the heading is committed and the visible yaw
        // whips onto it. `AIR_TURN_RATE` answers a different question — how fast the ARC may bend.
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
        self.rollYaw = mathx.headingXZ(d); // heading committed NOW; the visible yaw whips onto it
        const leadL = sampleCurve(HIP_FLEX, self.phase) > sampleCurve(HIP_FLEX, self.phase + 0.5);
        self.rollSide = if (self.moving > 0.5 and leadL) 1.0 else -1.0;
        // elapsed in the mix so standstill rolls (frozen phase) still vary roll to roll.
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
        // Pose BEFORE clearing `rolling`, or on the completing frame `pose()` falls to the walk branch and
        // pops a stale-phase stance for one frame.
        self.pose();
        if (self.rollT >= ROLL_DUR) {
            self.rolling = false;
            self.startXfade();
            self.fireQueued();
        }
    }


    /// A JUMP is in here beside the roll, so every rule hanging off this predicate lands without a second
    /// list: no double jump, no roll or cast out of the air, and an attack pressed mid-flight buffered.
    pub fn committed(self: *const Hero) bool {
        return self.jumping or self.rolling or self.attacking or self.drinking or self.shooting or self.casting or self.parrying or self.ringing;
    }

    /// **IS HE HOLDING ONE, IN EITHER HAND.** The whole of what "any armament in either hand" costs: every
    /// question the game used to ask of a SIDE — is the bow up, is the wand out, can he block — is really a
    /// question about what he is carrying, and asking it of one named hand is what pinned each thing to a side.
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

    /// …AND THE SAME QUESTION WITH THE OTHER FALLBACK, for anything whose animation was authored on the LEFT.
    fn heldRight(self: *const Hero, a: Armament) bool {
        return self.arm == a;
    }

    /// WHICH HAND THE BLADE IS IN — right-authored: `PARENT[SWORD]` is `WRR`.
    pub fn swordLeft(self: *const Hero) bool {
        return self.heldLeft(.sword);
    }

    /// …THE BELL, rung one-handed off the same wrist the blade hangs from.
    pub fn bellLeft(self: *const Hero) bool {
        return self.heldLeft(.bell);
    }

    /// …THE ROD. Left-authored (`wandMesh` is in that wrist's frame), and it is what `wandTipWorld` is taken
    /// off: a bolt, a rune ring and the rime's mouth all leave the STONE.
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

    /// …AND WHAT THE RIGHT HAND IS ACTUALLY WORKING — normally the arm slot, but a two-hander is worked from
    /// this hand out of EITHER slot (`draw`, and the rig nocks the bow at that wrist), so a bow set in the
    /// left slot is what this hand has. The input layer and the HUD's right cell both ask it.
    pub fn armInHand(self: *const Hero) Armament {
        return if (armTwoHanded(self.off)) self.off else self.arm;
    }

    pub fn wandOut(self: *const Hero) bool {
        return self.holds(.wand);
    }

    /// …and the BOARDS, which used to be the left hand's alone by construction.
    pub fn shieldOut(self: *const Hero) bool {
        return self.holds(.shield);
    }

    /// D-pad LEFT / RIGHT — **A HAND IS A PAIR AND THE BUTTON EXCHANGES IT.** It was a walk through a whole
    /// enum, which is a list that grows every time an armament is added and a thumb that has to count. Nothing
    /// is cleared: `canGuard` and `canCast` both ASK what is in the hand every frame.
    fn swapHand(self: *Hero, live: *Armament, alt: *Armament) bool {
        if (self.committed() or self.staggered() or self.dead or self.resting) return false;
        if (live.* == alt.*) return false; // both slots the same thing: the press achieves nothing, and says so
        std.mem.swap(Armament, live, alt);
        self.drawAmt = 0; // a bow put away mid-draw does not keep its draw
        self.startXfade();
        return true;
    }

    pub fn swapOff(self: *Hero) bool {
        return self.swapHand(&self.off, &self.offAlt);
    }

    pub fn swapArm(self: *Hero) bool {
        return self.swapHand(&self.arm, &self.armAlt);
    }

    /// **PUT SOMETHING IN A SLOT** — the character book's equip, and the only way anything reaches a hand that
    /// is not already in it. `hand` is `RIGHT`/`LEFT` and `slot` is 0 for the live one, 1 for its alternate.
    pub fn equip(self: *Hero, hand: usize, slot: usize, a: Armament) bool {
        if (self.committed() or self.staggered() or self.dead or self.resting) return false;
        const live = if (hand == RIGHT) &self.arm else &self.off;
        const alt = if (hand == RIGHT) &self.armAlt else &self.offAlt;
        const into = if (slot == 0) live else alt;
        if (into.* == a) return false;
        into.* = a;
        if (into == live) {
            self.drawAmt = 0;
            self.startXfade();
        }
        return true;
    }

    /// What is in one slot, for the screen that draws them.
    pub fn slotAt(self: *const Hero, hand: usize, slot: usize) Armament {
        const live = if (hand == RIGHT) self.arm else self.off;
        const alt = if (hand == RIGHT) self.armAlt else self.offAlt;
        return if (slot == 0) live else alt;
    }

    /// L2, HELD — called EVERY frame with the button's level, re-deriving the stance from scratch.
    pub fn setAim(self: *Hero, want: bool) void {
        self.aiming = want and self.canAim();
    }

    /// WHAT HE IS SWINGING AT, in degrees off his own eye line (+ = below him).
    pub fn aimAtPitch(self: *Hero, deg: ?f32) void {
        self.aimLeanWant = mathx.clampF(AIM_LEAN_BIAS + (deg orelse 0), -AIM_LEAN_UP, AIM_LEAN_DOWN);
    }

    /// NOT `aimB`: that is a stance blend and must EASE down through a stagger, as `guardB` does. The camera's
    /// boom rides it, so snapping it here cut the eye from `AIM_DIST` to the player's own zoom in ONE frame
    /// every time a blow flinched him mid-aim. Paths that want a snap say so beside their `guardB = 0`.
    fn dropAim(self: *Hero) void {
        self.aiming = false;
        self.shooting = false;
        self.loosed = false;
        self.drawAmt = 0;
        self.nockVis = false;
    }

    /// `shooting` is the ONE committed action this allows: a loose out of a held aim must not cost the aim.
    pub fn canAim(self: *const Hero) bool {
        // Through `committed()` and not a hand-rolled copy of its list: as a copy minus `shooting` it also
        // silently dropped `casting` and `parrying`.
        return self.bowOut() and (!self.committed() or self.shooting) and
            !self.staggered() and !self.dead and !self.sprinting and !self.resting and self.stam.canAct();
    }

    pub fn requestShot(self: *Hero, aimed: bool) void {
        if (!self.bowOut() or self.dead or self.staggered()) return;
        if (aimed and !self.aiming) return;
        if (self.committed()) return; // a loose is not buffered: see the note on the draught
        self.startShot(aimed);
    }

    fn startShot(self: *Hero, aimed: bool) void {
        if (!self.stam.canAct()) {
            self.refuse();
            return;
        }
        // Checked BEFORE the stamina is charged: a loose that never happened must not bill him for it.
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

    /// Call in place of move/attack while `shooting`.
    pub fn updateShot(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt); // clears `loosed`
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

    /// WHERE THE SHAFT LEAVES — the live string's own nock, not the fist (see `archer.poseBow`).
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

    /// Everything the guard asks BAR the stamina — the one clause the parry answers differently, since a
    /// press has to say NO out loud where the guard just stays down. It asks `shieldOut`, which is EITHER
    /// hand: what takes the boards off his arm is a hand going to a STRING, not a hand being busy.
    fn shieldArm(self: *const Hero) bool {
        return self.shieldOut() and !self.committed() and !self.staggered() and !self.dead and !self.sprinting and !self.resting;
    }

    /// AN EMPTY BAR CANNOT HOLD A SHIELD UP, and neither can a hand already holding something else.
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
        // The panic rule, stamina's: any bar above zero buys the window, and the whole cost comes off it.
        if (!self.stam.canAct()) {
            self.refuse();
            return false;
        }
        self.stam.spend(combat.STAM_PARRY);
        self.parrying = true;
        self.parryT = 0;
        self.parries +%= 1;
        // …and if he WAS blocking, that block is off: written here too, since a parry can start without `setGuard`.
        self.guarding = false;
        self.startXfade();
        return true;
    }

    /// Call in place of move/attack while `parrying`. PLANTED, like the cast and the quick shot.
    pub fn updateParry(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        self.parryT += dt;
        // The glint fires ON the whip's own peak frame, once — the pose's loudest instant, made louder.
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

    /// Its own predicate rather than a span read off the pose: the shove keeps playing for a third of a
    /// second after the window shuts, and that tail is the risk the parry is priced on.
    pub fn parryLive(self: *const Hero) bool {
        return self.parrying and self.parryT >= PARRY_OPEN and self.parryT < PARRY_SHUT;
    }

    /// NO stamina, no chip, no flinch — that was paid for at the press. What it leaves is the shield's own
    /// recoil clock and the sparks that say iron, not wood on flesh.
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

    /// Thrown about the boards' OWN normal: a spray built on world axes reads as a puddle round his hand the
    /// moment the shield turns.
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
            // A WIDE SPREAD OF LIVES, not one: struck iron throws a few that die instantly and a few that arc
            // right down to the grass, and the long ones are what make the shower read as a shower.
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.16, 0.72), rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI), 0.003, if (rng.float() < 0.45) PARRY_SPARK_HOT else PARRY_SPARK, PARRY_SPARK_GRAV);
        }
        // The bloom DRIFTS off the boards rather than sitting on them, or it reads as a sphere switched on.
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(f.n, 0.8), PARRY_FLASH_LIFE, PARRY_FLASH_R, PARRY_FLASH_R * 0.25, PARRY_SPARK_HOT, 0);
    }

    /// **THE BOARDS EATING A BLOW.** `parrySparks`' frame, deliberately none of its signature: grit rather
    /// than iron, a short close scatter rather than a shower, and a wide dim puff rather than a white bloom.
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
        // The dust the impact drove out of the facing — it SITS on the boards and thins, where the catch's
        // bloom leaves them.
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
            // WHERE ON THE ARC this mote sits — the streak, laid down before anything has moved.
            const along = rng.range(-1.0, 1.0);
            const from = mathx.addV(at, mathx.scaleV(side, along * PARRY_GLINT_SPAN));
            const a = rng.angle();
            const fan = rng.range(0.35, 1.0) * PARRY_GLINT_FAN;
            const v = mathx.addV(
                mathx.addV(
                    mathx.scaleV(f.n, rng.range(PARRY_SPARK_OUT_LO * 0.5, PARRY_SPARK_OUT_HI * 0.4)),
                    mathx.scaleV(side, along * PARRY_GLINT_FAN * PARRY_GLINT_TRAIL), // …carrying on the way it was going
                ),
                mathx.addV(mathx.scaleV(side, mathx.cosf(a) * fan * 0.4), mathx.scaleV(up, mathx.sinf(a) * fan)),
            );
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, rng.range(0.05, 0.15), rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI), 0.003, PARRY_SPARK_HOT, PARRY_SPARK_GRAV);
        }
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(f.n, 0.9), PARRY_FLASH_LIFE, PARRY_GLINT_FLASH_R, PARRY_GLINT_FLASH_R * 0.25, PARRY_SPARK_HOT, 0);
    }

    /// L1 with a wand in the left hand — the guard's own button, routed by what that hand is holding. STAMINA IS
    /// NOT ASKED: a cast is billed in FP alone, so an empty stamina bar still leaves him a spell.
    pub fn canCast(self: *const Hero) bool {
        return self.wandOut() and !self.committed() and !self.staggered() and !self.dead and
            !self.resting and !self.sprinting;
    }

    /// L1, PRESSED — a cast is committed, so this is an edge and not a level. Reports whether one STARTED.
    pub fn requestCast(self: *Hero) bool {
        if (!self.canCast()) return false;
        return self.startCast();
    }

    /// WHAT THE ROD WOULD BILL FOR THE SPELL IT IS SET TO — the HUD's "could he?" and the cast both ask this.
    pub fn castCost(self: *const Hero) f32 {
        return combat.spellFp(self.spell) * self.perk.spellCost;
    }

    /// Refused mid-cast: the FP for the one already running is spent, and swapping under it would throw a
    /// spell he did not pay for.
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
        // PAY OR CAST NOTHING (`combat.Focus.spend`) — and the refusal lights the FP bar, not the stamina one.
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

    /// Call in place of move/attack while `casting`.
    pub fn updateCast(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt); // clears `thrown`
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        const was = self.castT / CAST_DUR;
        // **THE WHOLE CAST IS ONE CLOCK, so speeding it up is speeding THAT** (`passivetree.Grant.castSpeed`).
        // Every window on the cast — the throw, the gather, the rime's own pour — is a fraction of `castT`,
        // so the tell shortens with the recovery and nothing can come out before its own picture does.
        self.castT += dt * self.perk.castSpeed;
        // A one-frame EDGE, `updateShot`'s: a long frame cannot throw twice, a short one cannot miss it.
        if (was < CAST_AT and self.castT / CAST_DUR >= CAST_AT) self.thrown = true;
        self.pose();
        // AFTER the pose: the gather emits at the posed stone, so earlier draws this frame's motes onto last frame's wand.
        if (self.castT / CAST_DUR < CAST_AT) self.gatherMotes(dt);
        // …and the same rule for the POUR, which comes off the posed HEAD: it has to be this frame's head or
        // the stream hangs a frame behind the face it is leaving.
        if (self.breathLive()) self.pourBreath(dt);
        if (self.castT >= self.castSpan()) {
            self.casting = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    /// It asks nothing about the bag or about what is already standing: those are game.zig's business.
    pub fn canRing(self: *const Hero) bool {
        return self.bellOut() and !self.committed() and !self.staggered() and !self.dead and
            !self.resting and !self.sprinting;
    }

    /// Through the same perk as `castCost`, so a Focus build pays less for both — **and through the AMULET on
    /// top of it**, which is the one dial in the game that is the bell's alone. Two independent discounts, so
    /// they multiply: the tree makes every spell cheaper and the gravebell makes only this one cheaper.
    pub fn ringCost(self: *const Hero) f32 {
        return combat.spiritFp(self.spirit) * self.perk.spellCost * charmOf(self.worn).spiritFp;
    }

    /// R1 with the bell out, PRESSED — committed, so an edge. Reports whether one STARTED, since the caller's
    /// voice must not sound for a ring the pool refused.
    pub fn requestRing(self: *Hero) bool {
        if (!self.canRing()) return false;
        // Pay or ring NOTHING, and the refusal lights the FP bar: under the zero-input-lag law a press that
        // shows nothing is a press that was dropped.
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

    /// Call in place of move/attack while `ringing`. PLANTED, like the cast: calling something is a standing job.
    pub fn updateRing(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt); // clears `rang`
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

    /// For the shot harness: no FP is spent and nothing is called — a POSE, with the mechanic left on the
    /// live path.
    pub fn stageRing(self: *Hero, u: f32) void {
        self.arm = .bell;
        self.ringing = true;
        self.ringT = mathx.clampF(u, 0, 1) * RING_DUR;
        self.pose();
    }

    /// How far through the current ringing, 0..1 (0 when there is none).
    fn ringU(self: *const Hero) f32 {
        if (!self.ringing) return 0;
        return mathx.clampF(self.ringT / RING_DUR, 0, 1);
    }

    /// HOW LONG THIS CAST ACTUALLY RUNS. Two spells throw something at a moment and are over; the RIME pours
    /// for `RIME_DUR` after that moment, and the animation may not end while the cone is still open — a spell
    /// whose picture finishes before its mechanic does is a man standing in idle breathing frost.
    pub fn castSpan(self: *const Hero) f32 {
        return CAST_DUR + if (self.spell == .rime) combat.RIME_DUR else 0;
    }

    /// The instant the cone opens, in seconds into the cast: the THROW's own beat, so the two spells that
    /// throw and the one that pours all commit at the same point of the same animation.
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

    /// 0..1 across the pour, and 0 either side of it.
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

    /// …and where it goes. LEVEL, and that is a decision: the cone is tested in XZ (`game.rimeBreathe`), so a
    /// pitched picture would promise a reach up or down that the mechanic does not have. `BREATH_SH_LEVEL` is
    /// the other half of keeping that promise — it is what brings the ROD down onto this line.
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

    /// How far through the current cast, 0..1 (0 when there is none) — POSE TIME, which is not clock time.
    fn castU(self: *const Hero) f32 {
        if (!self.casting) return 0;
        if (self.spell == .rime and self.castT > breathAt()) {
            const held = mathx.minF(self.castT - breathAt(), combat.RIME_DUR);
            return mathx.clampF((self.castT - held) / CAST_DUR, 0, 1);
        }
        return mathx.clampF(self.castT / CAST_DUR, 0, 1);
    }

    /// 0..1 across the raise, and 0 EITHER SIDE of it, so a caller pulsing on it stops when the stone lets go.
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
        // EXHAUSTIVE, not `else`: a third buffered action has to be asked whether it steers.
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
        // LATCHED HERE, and the bill is the first thing it prices: a club costs half again what the sword does
        // per stroke, a dirk three quarters, and whatever is picked up mid-stroke prices the NEXT one.
        self.atkRow = self.armOf(.hand_sword);
        const cost: f32 = @as(f32, if (kind == .heavy) combat.STAM_HEAVY else combat.STAM_LIGHT) * self.atkRow.stam;
        if (!self.stam.canAct()) {
            self.refuse();
            return;
        }
        self.stam.spend(cost);
        self.attacking = true;
        self.swings +%= 1;
        self.atkHeavy = kind == .heavy;
        self.atkAlt = false; // a fresh light is always the forehand; chaining flips it (see updateAttack)
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
        // Step into the cut: the lunge is spread evenly across the strike span.
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
            // `moving` is NOT reset — held input walks straight out of the recovery.
            self.startXfade();
            self.fireQueued();
            self.alternateChain(wasLight, wasAlt); // late-buffered lights still alternate
        }
    }

    fn alternateChain(self: *Hero, wasLight: bool, wasAlt: bool) void {
        if (self.attacking and !self.atkHeavy and wasLight) self.atkAlt = !wasAlt;
    }


    /// `flasks.sel` is STAMPED from the new entry rather than cycled on its own, so the draught, the HUD tint
    /// and the charge count all keep reading one field.
    pub fn cycleQuick(self: *Hero) void {
        if (self.dead or self.drinking) return;
        self.quick.cycle();
        self.syncFlask();
    }

    /// …and the same stamp wherever the bar is changed from outside (the character book's own slot).
    pub fn syncFlask(self: *Hero) void {
        if (self.quick.selected()) |k| {
            if (combat.flaskOf(k)) |f| self.flasks.sel = f;
        }
    }

    /// Refused mid-loose for the reason `shotArrow` exists. It does not need the bow to be out: choosing your
    /// ammunition is not an action.
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
        // THE CHARGE MUST NOT GO INTO A BAR THAT CANNOT TAKE IT — and only the CERULEAN is gated.
        if (self.flasks.sel == .cerulean and !self.fp.canTake()) {
            self.refuse();
            return false;
        }
        if (!self.flasks.take()) {
            self.refuse(); // dry — the HUD's "that did nothing" flash
            return false;
        }
        self.drinking = true;
        self.drinkT = 0;
        self.poured = false;
        self.startXfade();
        return true;
    }

    /// The draught's clock and nothing else — the caller still MOVES and poses him. Do NOT tick the shared
    /// clocks here: `update` does that on the way through the move, and both would double-advance them.
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

    /// HOW FAR THE FLASK IS UP AND HOW FAR IT IS TIPPED, 0 unless he is drinking — `bowLevels`' twin.
    fn drinkLevels(self: *const Hero) struct { lift: f32, tip: f32 } {
        if (!self.drinking) return .{ .lift = 0, .tip = 0 };
        const u = mathx.clampF(self.drinkT / combat.FLASK_DRINK_DUR, 0, 1);
        // Up fast, HOLD at the mouth through the pour, down slower — a flask is emptied, not waved.
        return .{ .lift = mathx.pulse(u, 0, 0.26, 0.72, 1.0), .tip = mathx.pulse(u, 0.22, 0.46, 0.66, 0.92) };
    }

    // TAE-events equivalent: the blade only HITS inside the strike's active window.
    pub fn hitActive(self: *const Hero) bool {
        if (!self.attacking) return false;
        const u = self.atkT / self.atkDur(self.atkHeavy);
        return if (self.atkHeavy) (u >= AH_HIT_A and u < AH_HIT_B) else (u >= AL_HIT_A and u < AL_HIT_B);
    }

    fn updateBlade(self: *Hero) void {
        self.bladeA0 = self.bladeA;
        self.bladeB0 = self.bladeB;
        self.bladeA = rl.math.vector3Transform(BLADE_BASE, self.xf[SWORD]);
        self.bladeB = rl.math.vector3Transform(BLADE_TIP, self.xf[SWORD]);
        const act = self.hitActive(); // sampled ONCE — both the trail and the edge test read it
        if (act) self.trail.push(self.bladeA, self.bladeB, self.bladeB0, TRAIL_ROOT);
        if (act and !self.hitWasActive) {
            self.bladeA0 = self.bladeA;
            self.bladeB0 = self.bladeB;
        }
        self.hitWasActive = act;
    }

    pub fn drawTrail(self: *const Hero) void {
        self.trail.draw(TRAIL_LIFE, foemod.WAKE, TRAIL_PEAK);
        foemod.drawParticles(&self.fx);
    }

    /// The gather is the TELL. Emitted from `updateCast` rather than the pose, which also runs headless.
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
        // Squared on the rate: the ramp belongs at the END of the raise, or it reads as one steady stream.
        const fill = self.chargeFill();
        const shell = mathx.lerpF(CAST_MOTE_R, CAST_MOTE_R_HI, fill);
        var rng = foemod.fxStream(self.castT + @as(f32, @floatFromInt(self.casts)), 977.0, 0x8B01);
        var n = foemod.emitTicks(&self.moteAcc, dt, mathx.lerpF(CAST_MOTE_RATE, CAST_MOTE_RATE_HI, fill * fill), CAST_MOTE_CAP);
        while (n > 0) : (n -= 1) {
            const a = rng.angle();
            const el = rng.range(-0.5, 1.0);
            const rr = rng.range(shell * 0.5, shell);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + el * rr, at.z + mathx.sinf(a) * rr);
            // …and its velocity points BACK at the stone, which makes it a gather. NO gravity: it is pulled in.
            const life = rng.range(CAST_MOTE_LIFE_LO, CAST_MOTE_LIFE_HI);
            const v = mathx.addV(mathx.scaleV(mathx.subV(at, from), 1.0 / life), tipV);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, life, CAST_MOTE_R0, CAST_MOTE_R1, CHAOS_MOTE, 0);
        }
    }

    /// The release: a cone down the bolt line, a collar sideways out of it, one flash on the stone.
    pub fn castSparks(self: *Hero, dir: rl.Vector3) void {
        const at = self.wandTipWorld();
        // The collar's plane is the BOLT LINE's perpendicular pair, not world axes, or a cast uphill is a puddle.
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
            // Evenly round THEN jittered: random angles clump and gap at this count.
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, CAST_COLLAR) + rng.range(-0.26, 0.26);
            const sp = rng.range(CAST_COLLAR_SP * 0.7, CAST_COLLAR_SP);
            const v = mathx.addV(
                mathx.scaleV(side, mathx.cosf(a) * sp),
                mathx.addV(mathx.scaleV(up, mathx.sinf(a) * sp), mathx.scaleV(dir, rng.range(0.3, 1.4))),
            );
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.13, 0.26), rng.range(0.022, 0.040), 0.006, CHAOS_HOT, 1.2);
        }
        // The flash DRIFTS down the bolt line rather than sitting still, or it reads as a sphere switched on.
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(dir, 1.2), CAST_FLASH_LIFE, CAST_FLASH_R, CAST_FLASH_R * 0.30, CHAOS_HOT, 0);
    }

    /// A RESERVED light slot, so a torch he stands beside cannot evict it.
    pub fn wandLight(self: *const Hero) ?gfx.Light {
        if (!self.wandOut() or self.resting) return null; // at a bonfire the rod is stowed for the guitar
        const u = self.castU();
        // The charge fills to the throw and is SPENT by it; the flare is a spike straddling that instant.
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

    /// THE GROUND SPLITTING. `bit` is whether the grip closed on anything: it only sizes the earth thrown up.
    pub fn rootsBurst(self: *Hero, at: rl.Vector3, bit: bool) void {
        self.rootHead = (self.rootHead + 1) % ROOT_SITES;
        self.rootSites[self.rootHead] = .{ .at = at, .t = 0, .seed = @floatFromInt(self.casts) };
        // THE EARTH IT ERUPTS THROUGH IS THE VICTIM'S, NOT HIS. `tickClocks` floors the pool at his own feet,
        // which on sculpted ground stops this shower in mid-air over a hollow or drops it through a rise.
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, at.y);
        var rng = foemod.fxStream(@floatFromInt(self.casts), 331.0, 0x8B04);
        // The EARTH first — thrown out and up, and it falls back, which is what says something came THROUGH it.
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
        // …then the element. They FLOAT off the wood (a negative grav) rather than arcing like the dirt does.
        var j: u32 = 0;
        while (j < ROOT_MOTES) : (j += 1) {
            const a = rng.angle();
            const rr = rng.range(0.2, combat.ROOT_GRIP_R);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + rng.range(0.05, 0.6), at.z + mathx.sinf(a) * rr);
            const v = v3(rng.signed() * 0.9, rng.range(0.8, 2.4), rng.signed() * 0.9);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, rng.range(0.45, 1.00), rng.range(0.038, 0.072), 0.010, if (rng.float() < 0.4) CHAOS_HOT else CHAOS_MOTE, -0.6);
        }
    }

    /// One mesh thrown `ROOT_FANS` times per site through a seeded yaw / offset / scale / lean, each on its
    /// OWN delay — the stagger is what stops them welding.
    pub fn drawRoots(self: *const Hero) void {
        for (self.rootSites) |s| {
            if (s.t >= ROOT_SITE_LIFE) continue;
            var rng = foemod.fxStream(s.seed + 1.0, 613.0, 0x8B05);
            for (0..ROOT_FANS) |k| {
                // Drawn from the stream FIRST and unconditionally, so the fan does not reshuffle as the site rises.
                const jitter = rng.range(-0.34, 0.34);
                // Out to two thirds of the GRIP, so the fan closes on ankles rather than ground it never took.
                const out = rng.range(0.22, combat.ROOT_GRIP_R * 0.66);
                const sc = rng.range(0.62, 1.46); // WIDE: nine of one height is a garden rake
                const lean = rng.range(4.0, 24.0); // the mesh already curls; the transform only tips it OFF plumb
                const kind = @as(usize, @intFromFloat(rng.range(0, ROOT_KINDS)));
                const u = s.t - ROOT_RISE * ROOT_LAG * (@as(f32, @floatFromInt(k)) / ROOT_FANS);
                if (u <= 0) continue;
                // TORN up, overshooting its own height and settling onto it, held, then drawn back slower.
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

    /// It lands nowhere near his feet, so the burst carries its OWN floor rather than the one `tickClocks`
    /// gives his pool. `groundY` is the earth under the contact and NOT `at.y`: the bolt bursts against a
    /// wall at the height it struck one, and its sparks fall from there.
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
        var i: u32 = 0;
        while (i < LEVIN_STEPS) : (i += 1) {
            const u = (@as(f32, @floatFromInt(i)) + rng.range(-0.35, 0.35)) / LEVIN_STEPS;
            const p = mathx.lerpV(from, to, mathx.clampF(u, 0, 1));
            const off = v3(rng.signed() * LEVIN_JITTER, rng.signed() * LEVIN_JITTER * 0.35, rng.signed() * LEVIN_JITTER);
            elemfx.burst(&self.fx, &self.fxHead, &rng, mathx.addV(p, off), mathx.zero3, .lightning, LEVIN_SPARKS, LEVIN_SPARK_SCALE);
        }
        elemfx.burst(&self.fx, &self.fxHead, &rng, to, mathx.zero3, .lightning, LEVIN_BURST, LEVIN_BURST_SCALE);
    }

    /// **THE LANCE'S SHAFT — the levin's construction, but the motes are laid ALONG A LINE THAT CARRIES ON.**
    /// The stroke stops at the body it struck; this one does not, and the whole thing the player has to learn
    /// about the spell is that the fire kept going. So there is no terminal burst: what marks the far end is
    /// the shaft simply thinning out, which is what a thing running out of reach looks like.
    ///
    /// FIRE RISES AND LEAVES A RESIDUE (`elemfx`'s own signature), so the floor is the earth under the SHAFT
    /// rather than under the caster — `boltBurst`'s law, and here it is a line rather than a point, so the
    /// floor is taken at the tip where the last of them fall.
    pub fn lanceBeam(self: *Hero, from: rl.Vector3, to: rl.Vector3, salt: u32) void {
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, mathx.minF(from.y, to.y) - LANCE_FLOOR_DROP);
        var rng = foemod.fxStream(@floatFromInt(salt), 811.0, 0x8B08);
        var i: u32 = 0;
        while (i < LANCE_STEPS) : (i += 1) {
            const u = (@as(f32, @floatFromInt(i)) + rng.range(-0.30, 0.30)) / LANCE_STEPS;
            const p = mathx.lerpV(from, to, mathx.clampF(u, 0, 1));
            const off = v3(rng.signed() * LANCE_JITTER, rng.signed() * LANCE_JITTER * 0.5, rng.signed() * LANCE_JITTER);
            // THINNING WITH DISTANCE — the near end is the thick end, so the shaft reads as thrown FROM him.
            const n = @max(1, @as(usize, @intFromFloat(@round(mathx.lerpF(@as(f32, LANCE_SPARKS), 1.0, u)))));
            elemfx.burst(&self.fx, &self.fxHead, &rng, mathx.addV(p, off), mathx.zero3, .fire, n, LANCE_SPARK_SCALE);
        }
    }

    /// **SUNDER'S BEAT — a RING on the ground and nothing in the air.** Every other sorcery is a thing that
    /// arrived; this one is a thing that came apart, so what it throws is low, outward and short-lived. `bit`
    /// is whether it found a body: a cast that hit nothing still shows, at half the count, because a spell
    /// that draws nothing on a miss reads as the button not having worked (`strikeMissAt`'s own reason).
    pub fn sunderBurst(self: *Hero, at: rl.Vector3, bit: bool, salt: u32) void {
        const was = self.fxHead;
        defer foemod.floorBurst(&self.fx, was, self.fxHead, at.y);
        var rng = foemod.fxStream(@floatFromInt(salt), 877.0, 0x8B09);
        const n: u32 = if (bit) SUNDER_MOTES else SUNDER_MOTES / 2;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            // A RING, so the angle is walked rather than drawn — a random scatter is a puff, and a puff is
            // what every other burst in this file already is.
            const a = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n))) * std.math.tau + rng.range(-0.25, 0.25);
            const sp = rng.range(SUNDER_SPEED_LO, SUNDER_SPEED_HI);
            const v = v3(mathx.cosf(a) * sp, rng.range(0.3, 1.4), mathx.sinf(a) * sp);
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.22, 0.46), rng.range(0.030, 0.062), 0.008, if (rng.float() < 0.5) SUNDER_DUST else SUNDER_CHIP, 6.0);
        }
    }

    /// **THE SIPHON'S DRAIN — the one effect in the game that runs the wrong way up the line.** Motes come off
    /// the BODY and are solved to arrive at the stone, which is `souls.zig`'s own construction: what it has to
    /// read as is a thing being taken, and a burst at the victim reads as a thing being given.
    pub fn siphonDrain(self: *Hero, at: rl.Vector3, salt: u32) void {
        const tip = self.wandTipWorld();
        var rng = foemod.fxStream(@floatFromInt(salt), 787.0, 0x8B07);
        var i: u32 = 0;
        while (i < SIPHON_MOTES) : (i += 1) {
            const a = rng.angle();
            const rr = rng.range(0.0, SIPHON_SPREAD);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + rng.range(-SIPHON_SPREAD, SIPHON_SPREAD), at.z + mathx.sinf(a) * rr);
            const life = rng.range(SIPHON_LIFE_LO, SIPHON_LIFE_HI);
            // Solved to ARRIVE: chaos's gravity is 0, so the whole velocity is the gap over the life and there
            // is no ½·g·t² to subtract back out.
            const v = mathx.scaleV(mathx.subV(tip, from), 1.0 / life);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, life, rng.range(0.026, 0.048), 0.008, if (rng.float() < 0.45) CHAOS_HOT else CHAOS_MOTE, 0);
        }
    }

    pub fn attackHit(self: *const Hero) combat.Hit {
        // THE WEAPON FIRST, THE TALLOW SECOND. The grease is a share of the blade's OWN physical, so a greased
        // club burns hotter than a greased dirk — read off the bare constant it would be one flat number for
        // every weapon in the game, which is the same bug as a fire arrow that ignores the bow.
        // …AND THE BARGAIN RIDES THE WHOLE BLOW (`passivetree.Grant.sacrifice`): what he gave health for is
        // WEIGHT, not just damage, so poise and stance come with it — `combat.Hit.scaled`'s own law, and the
        // reason Berserk staggers things a bare swing bounces off.
        const base = weigh(if (self.atkHeavy) ATK_HEAVY_HIT else ATK_LIGHT_HIT, self.swingRow(), self.sheet).scaled(self.perk.dmg);
        if (!self.grease.on()) return base;
        // Fire ON TOP, the physical untouched — the fire arrow's own construction (`fireTipped`).
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
    /// The death's own path, exposed because a NEW GAME needs exactly it and so does the harness. Set
    /// `setSpawn` first: this reads it.
    pub fn respawnNow(self: *Hero) void {
        self.respawn();
    }

    pub fn iFramed(self: *const Hero) bool {
        return self.rolling and self.rollT < ROLL_IFRAME_END + self.perk.iframe;
    }

    /// THE ROW FOR WHAT IS IN THAT SOCKET — all ones when it is empty, so every call site is the same arithmetic
    /// geared or bare and none of them has to ask whether he is wearing anything.
    fn armOf(self: *const Hero, w: item.Wear) item.Arm {
        return armRow(self.worn, w);
    }

    /// **THE ROW A COMMITTED ACTION IS RUNNING ON**, which is the one it STARTED on (`atkRow`) — the live socket
    /// only once nothing is in flight, so a variant taken up mid-stroke prices the next stroke and not this one.
    fn swingRow(self: *const Hero) item.Arm {
        return if (self.attacking) self.atkRow else self.armOf(.hand_sword);
    }
    fn drawRow(self: *const Hero) item.Arm {
        return if (self.shooting) self.shotRow else self.armOf(.hand_bow);
    }

    /// …and the two WORN rows, on the same rule: nothing on is a zero that changes nothing.
    pub fn armourA(self: *const Hero) f32 {
        // **THE TREE'S PLATE IS THE SUIT'S** (`passivetree.Grant.armour`) — added to `A` rather than given a
        // curve of its own, so a node and a coat are one number through `combat.armourTaken` and stacking
        // them can never become immunity.
        return armourOf(self.worn) + self.perk.armour;
    }
    /// EVERY CHARM HE HAS ON, ADDED UP — walked over the sockets because there are two fingers now, and a second
    /// band read off the first socket's name would have been a piece of gear silently doing nothing.
    pub fn charm(self: *const Hero) item.Charm {
        return charmOf(self.worn);
    }

    /// **THE LIVE SHEET IS THE TREE PLUS WHAT HE HAS ON**, and it is rebuilt here rather than at either of the two
    /// places that can move it: a node bought at a fire and a belt cinched in the book are the same edit to the
    /// same number, and two call sites each doing half of it is how one of them ends up doing none.
    fn resheet(self: *Hero) void {
        self.sheet = self.perk.sheet();
        boonsOnto(self.worn, &self.sheet);
    }

    /// **PUTTING SOMETHING ON, AND THE ONE DOOR IT GOES THROUGH.** A charm resizes the red bar, so the bar is
    /// refitted here rather than at the next bonfire: a ring you put on that does nothing until you rest is a
    /// ring the player decides is broken. Refuses a kind that does not belong in that socket, since the one
    /// thing worse than a socket that will not take a thing is one that takes it and does nothing.
    pub fn wear(self: *Hero, w: item.Wear, k: ?item.Kind) bool {
        if (k) |kind| {
            if (item.wearSlot(kind) != w) return false;
        }
        self.worn.put(w, k);
        self.resheet();
        self.refitBars();
        return true;
    }

    /// **EVERY BAR BACK ONTO THE SHEET WITHOUT MOVING WHAT IS IN IT.** A boon may name vitality, mind or endurance
    /// (`item.Boon` names an attribute and not a bar), so all three LENGTHS are a socket's business now — not only
    /// the red one a charm eats. Fractions are kept for `refitHp`'s reason and in both directions: cinching a belt
    /// may not heal him and loosening one may not kill him.
    fn refitBars(self: *Hero) void {
        self.refitHp();
        refitPool(&self.stam.cur, &self.stam.max, self.sheet.stamina());
        // …AND THE BLUE ONE THROUGH `fpMaxOf`, not off the bare sheet: the gravebell eats into it exactly the
        // way the leech signet eats into the red one, and read straight off `sheet.fp()` the charm would be a
        // discount that cost nothing.
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

    /// **WHAT THE SIGNET GIVES BACK, ON EVERY SWING OF HIS THAT LANDS** — `game.zig` calls it off the same edge
    /// the hit's own beat comes off (a foe's hit count climbing) and gates it on his own swing, since that edge is
    /// a SUM and a spirit's jaws move it too. A swing that achieved nothing feeds nothing.
    pub fn drinkLeech(self: *Hero) f32 {
        // THE SIGNET AND THE TREE ARE ONE DIAL (`passivetree.Grant.leech`): the warrior's life branch is the
        // same bargain the ring is, at the same site, so a build wearing both drinks once for the sum.
        const back = self.charm().leech + self.perk.leech;
        return if (back > 0) self.vit.heal(back) else 0;
    }

    /// HOW LONG THIS SWING TAKES — the armament's own duration through the row in that hand. The MECHANIC and
    /// the POSE both read it: a club posed at the sword's rate would land its blow a third of a second after the
    /// picture had finished swinging it.
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

    /// …AND WHERE IN IT THE SHAFT LEAVES, as a fraction. A pure constant, but it sat spelled out beside all
    /// three copies of the clock above (`updateShot`, `bowLevels`, `loosedAlready`) — the mechanic's own knot and
    /// the pose's release are the same instant, and two of them written by hand is two that can part company.
    fn shotAt(self: *const Hero) f32 {
        return if (self.shotAimed) BOW_SHOT_AT else BOW_QUICK_AT;
    }

    /// …and what he walks at behind the boards he actually has (`game.zig` applies `GUARD_SPEED`).
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
        self.fp.drain(h.fp); // …and the ONE thing that reaches the blue bar (`combat.Hit.fp`)
        // **ARMOUR IS THE LAST THING BETWEEN THE BLOW AND THE BAR** (`combat.armourTaken`) — physical only, and
        // the poise and stance go through untouched: those belong to the blow, not to what he is wearing.
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
                // A light flinch can't override an in-progress HEAVY stagger (don't shorten it).
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
        // A DOOR IS DEARER TO HOLD UP. The bill is the blow's (`guardStamina`) through the board's own dial: what
        // a bigger shield buys is what gets through, and what it costs is the arm holding it there.
        self.stam.spend(combat.guardStamina(h) * board.stam);
        // CAPPED, because nothing the boards stop is stopped outright (`combat.GUARD_NEGATE_CAP`): the row
        // multiplies and a tree node adds, and the two together could otherwise make blocking free.
        const negate = mathx.minF(combat.GUARD_NEGATE_CAP, combat.GUARD_NEGATE * board.negate + self.perk.guard);
        const chip = combat.guardChip(h, negate);
        self.fp.drain(chip.fp);
        // …and the coat still gets its say on what the boards let through.
        const r = self.vit.hit(chip.throughArmour(self.armourA()));
        self.hurtFlash = mathx.maxF(self.hurtFlash, BLOCK_FLASH);
        if (r == .death) {
            self.enterDeath();
            return .taken; // chipped to death behind the shield — that is a death, not a block
        }
        // THE BREAK TESTS THE POOL, NOT `canAct()`.
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
        // On the SWALLOW, not the next frame's tick: the blow already in the air is the one he drank it for.
        self.settleResists();
    }

    pub fn startGrease(self: *Hero, frac: f32, secs: f32) void {
        self.grease.start(frac, secs);
    }

    /// **THE POISE BAR REFILLS FASTER WHILE THIS RUNS.** Stamped onto `vit` on the SWALLOW rather than left to
    /// the next tick, `startWard`'s reason exactly: the blow already in the air is the one he drank it for.
    pub fn startSteady(self: *Hero, mult: f32, secs: f32) void {
        self.steady.start(mult, secs);
        self.vit.poiseRate = self.steady.value(1);
    }

    /// **THE FIRST CURE IN THE WORLD.** Wiped whether it is filling or already running — `Status.reset` is one
    /// door for both, which is the whole reason that type keeps the meter and the clock in one number.
    pub fn purgePoison(self: *Hero) void {
        self.poison.reset();
    }

    /// **EVERY TIMED THING HE IS CARRYING, ADVANCED IN ONE PLACE.** It was `tickWard`, which also ticked the
    /// tallow — a name that described one of the two things it did, and the obvious place for the third to be
    /// forgotten. The resistances are settled after, because the ward is one of the inputs to them.
    pub fn tickTimed(self: *Hero, dt: f32) void {
        self.ward.tick(dt);
        self.grease.tick(dt);
        self.steady.tick(dt);
        // The poise multiple lives on `vit` because that is where the refill is done; this is the one place it
        // is written, so a clock running out puts the bar back to its own rate without anybody asking.
        self.vit.poiseRate = self.steady.value(1);
        self.settleResists();
    }

    /// The ONE place `vit.res` is written. As a bare `vit.res = ward or nothing` it was sole writer AND
    /// clobberer, so `makeWhole` carrying the resistances across a bonfire was undone by the next tick.
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

    /// Sources hand it BUILDUP and never HP: what the poison takes is the proc's business, not the cloud's.
    /// **THE TREE'S DIAL AND THE HELM'S, MULTIPLIED** — two independent things that each slow the meter, so
    /// they compose the way two multipliers do rather than one of them winning.
    pub fn poisonBy(self: *Hero, amt: f32) void {
        if (self.dead) return;
        self.poison.add(amt * self.perk.poison * poisonRateOf(self.worn));
    }

    /// Billed as a DRIP: it carries no poise, and stamped through `hit` it would deny him a whole poise bar.
    pub fn tickPoison(self: *Hero, dt: f32) bool {
        const due = self.poison.tick(dt, self.vit.hpMax);
        if (due <= 0 or self.dead) return false;
        if (self.vit.drip(combat.poisonPulse(due)) == .death) self.enterDeath();
        return true;
    }

    /// For the two places that MOVE him rather than let him travel: a respawn and sitting down at a fire.
    fn clearAir(self: *Hero) void {
        self.jumping = false;
        self.lift = 0;
        self.airY = self.pos.y;
        self.vertVel = 0;
        self.airSpeed = 0;
        self.landT = mathx.LONG_AGO; // …and no absorb on arrival: he did not land there, he appeared there
    }

    /// Nothing is refunded: the draught's charge, the cast's FP and the parry's stamina were paid at the
    /// press. ONE list, because four copies is four places to forget one from. NOT `guardB` and NOT
    /// `sprinting`: the stance blend must EASE down through a stagger, and the sprint is game.zig's level.
    fn dropActions(self: *Hero) void {
        self.attacking = false;
        self.rolling = false;
        self.drinking = false;
        self.casting = false;
        self.ringing = false; // …and the FP it cost is NOT refunded, with the cast's and the parry's
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
        self.stamRefused = 0; // a respawn must not inherit the last life's refusal flash
        self.fpRefused = 0;
        self.sprinting = false;
        self.guardB = 0; // …and the boards go down at once, as they do at a bonfire
        self.aimB = 0; // …and so does the bow: a respawn is a cut, not a blend
        self.blockT = mathx.LONG_AGO;
        self.pos = self.spawnPos;
        self.facing = self.spawnFacing;
        self.clearAir();
        self.moving = 0;
        self.speed = 0;
        self.speedS = 0;
        // Both are in WORLD space, so left to age out on their own they hang where he WAS — a ribbon
        // stretched across the map. Invisible after a death, but it is the whole of what a NEW GAME sees.
        self.trail = .{};
        self.fx = [_]foemod.Particle{.{}} ** FX_N;
        self.fxHead = 0;
        self.startXfade();
    }

    pub fn pose(self: *Hero) void {
        self.poseBody();
        // …then the bow's live string, which rides WHICHEVER body pose just ran (see poseBowString).
        self.poseBowString();
    }

    fn poseBody(self: *Hero) void {
        if (self.dead) return self.poseDeath();
        if (self.stun != .none) return self.poseStun();
        // Above the roll: a man in the air is in the air whatever he pressed, and nothing below can be
        // running with him (they are all `committed()` together).
        if (self.jumping) return self.poseJump();
        if (self.rolling) return self.poseRoll();
        if (self.attacking) return self.poseAttack();
        if (self.casting) return self.poseCast();
        if (self.ringing) return self.poseRing();
        if (self.parrying) return self.poseParry();
        const m = self.moving;
        const ph = self.phase;
        const twoPi = std.math.tau;
        // Travel direction in the BODY frame: `fw` signs the sagittal gait (negative = the time-reversed
        // backpedal), `lat` drives the sidestep.
        const fw = self.fwdB;
        const lat = self.latB;
        const fwPos = mathx.clampF(fw, 0, 1);
        const runB = mathx.clampF((self.speedS - RUN_SPEED_LO) / (RUN_SPEED_HI - RUN_SPEED_LO), 0, 1) * fwPos;
        const sprintB = mathx.clampF((self.speedS - RUN_SPEED_HI) / (SPRINT_REF_SPEED - RUN_SPEED_HI), 0, 1) * fwPos;
        const gB = mathx.clampF(self.guardB, 0, 1);
        const rec = self.blockRecoil();
        const guardBack = BLOCK_STEP * rec;
        const dk = self.drinkLevels(); // zero unless he has a flask up — see poseDrinkArm
        // A term in the CROUCH rather than a pose of its own — he lands into a walk, a sprint or a
        // standstill, and three copies of a stance would be three animations of one event.
        const land = self.landDip();
        const crouch = (RUN_CROUCH * runB + 0.5 * RUN_CROUCH * sprintB) * m +
            STRAFE_DIP * @abs(lat) * m +
            GUARD_CROUCH * gB + BLOCK_SINK * rec + DRINK_SINK * H * dk.lift + LAND_SINK * land;

        const walkBob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * ph); // twice/stride, symmetric
        const runBounce = A_RUN_BOUNCE * (0.5 - 0.5 * mathx.cosf(2.0 * twoPi * (ph - 0.2))); // up-only, peaks at flight
        const fwAbs = @abs(fw);
        const bob = mathx.lerpF(walkBob, runBounce, runB) * m * fwAbs + 0.006 * H * mathx.sinf(self.elapsed * 2.2) * (1.0 - m);
        const latW = @abs(lat) * m;
        const sway = strafeSway(latW, runB) * mathx.sinf(twoPi * ph) * m; // weight sits over the single-support foot; a strafe just opens the amplitude
        const prot = A_PROT * mathx.sinf(twoPi * ph) * m * @abs(fw) + strafeProt(ph, lat, m);
        const list = A_LIST * mathx.sinf(twoPi * ph) * m * fwAbs;

        // PITCHED FORWARD ABOUT THE FEET, so the centre of gravity leads the base — the falling-forward run.
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
            LAND_STOOP * land; // …and the trunk closes over the sink, which is where most of a landing reads
        const bank = STRAFE_LEAN * lat * m;
        const aim = self.aimLean;
        setLocal(&wx, SPINE, self.rest, mul3(rx(lean * 0.5 + aim * 0.5), ry(-0.3 * prot), rz(0.5 * bank)));
        setLocal(&wx, CHEST, self.rest, mul3(rx(lean * 0.5 + aim * 0.5), ry(-0.5 * prot), rz(0.5 * bank)));
        const fwdTilt = bodyPitch + lean;
        const gazeCounter = mathx.clampF(fwdTilt - GAZE_AHEAD, 0, NECK_EXT_MAX);
        setLocal(&wx, NECK, self.rest, mul(rx(-0.45 * gazeCounter), ry(-0.2 * prot)));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK - 0.55 * gazeCounter)); // +rx = gaze down (walk); the counter lifts it toward ahead when running

        legChain(&wx, &self.rest, ph, m, runB, fw, lat, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
        legChain(&wx, &self.rest, ph + 0.5, m, runB, fw, lat, -1.0, HIPR, KNEER, BOOT_SOLE[1]);

        const armAmp = mathx.lerpF(ARM_SWING, RUN_ARM_SWING, runB);
        const armL = -armAmp * mathx.cosf(twoPi * ph) * m * fw;
        const armR = armAmp * mathx.cosf(twoPi * ph) * m * fw;
        armChain(&wx, self.rest, armL, m, runB, sprintB, 1.0, 0.0, SHL, ELL, WRL);
        armChain(&wx, self.rest, armR, m, runB, sprintB, -1.0, 1.0, SHR, ELR, WRR); // right hand carries the sword
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());

        // …and the shield goes up OVER all of it (see poseGuard) — the gait keeps running underneath.
        if (gB > 0.001) self.poseGuard(&wx, gB, rec, lean, prot, bank);

        if (self.wandOut()) self.poseWandArm(&wx);
        if (self.bowOut()) self.poseBowArms(&wx, lean, prot, bank);
        // LAST, so the flask wins the off hand off a raised bow — that hand was on the string.
        if (self.drinking) self.poseDrinkArm(&wx, dk.lift, dk.tip);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// The off arm only, laid over whatever gait just ran. The head leads AWAY from the fist (`WAND_AX`), so an
    /// arm hanging at the side aims the lit end at the dirt — the elbow lifts it. KEEPS the gait swing, damped.
    /// THE ARM THAT CARRIES THE ROD, and it is whichever one is holding it. Welded to the LEFT, a wand
    /// equipped RIGHT posed an empty hand into the carry while the rod itself hung off the other arm.
    /// `poseAttack`'s mirror on the same one sign: the lateral channels flip, the sagittal ones do not.
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
        // The nocked shaft shows while there is a real draw on it, and the release takes it away.
        self.nockVis = self.drawAmt > 0.03 and !self.loosedAlready();
    }

    /// How far through the current loose, 0..1 (0 when there is none).
    fn shotU(self: *const Hero) f32 {
        if (!self.shooting) return 0;
        return mathx.clampF(self.shotT / self.shotDur(self.shotAimed), 0, 1);
    }
    /// Has THIS shot already let the shaft go? (`loosed` is the one FRAME it happened on.)
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
        // THE BOARDS ARM IS WHICHEVER ONE HOLDS THEM. The whole stance is lateral about it — the trunk turns
        // the shield onto the blow — so the mirror carries the body too, not just the two arms.
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

    /// A mass ARRIVING and settling back onto its rest, over one normalized clock: it arrives over `at` (a
    /// shove that starts at full is a snap), then rings down through its own rest and back. `rebound` is how
    /// much of one cycle the ring gets; it dies AT u = 1, so there is nothing left to snap out of.
    fn absorb(u: f32, at: f32, rebound: f32) f32 {
        if (u <= at) return mathx.smoothstep(0, at, u);
        const w = mathx.clampF((u - at) / (1.0 - at), 0, 1);
        const fall = (1.0 - w) * (1.0 - w);
        return fall * mathx.cosf(std.math.tau * rebound * w);
    }

    fn parryDrive(u: f32) f32 {
        return absorb(u, PARRY_PUNCH_AT, PARRY_REBOUND);
    }

    /// …and the landing's own, off the touchdown clock. 0 once it is spent, so it costs the gait nothing.
    fn landDip(self: *const Hero) f32 {
        if (self.landT >= LAND_DUR) return 0;
        return absorb(self.landT / LAND_DUR, LAND_SINK_AT, LAND_REBOUND);
    }

    /// THE SWIPE ITSELF: −1 fully coiled the other way, +1 followed all the way through, crossing CENTRE about
    /// where the thrust peaks — which is the frame that catches. Home to 0, so the exit has nothing to unwind.
    fn parrySweep(u: f32) f32 {
        const coil = mathx.smoothstep(0, PARRY_COIL_AT, u); // wind up, fast
        const whip = mathx.smoothstep(PARRY_COIL_AT, PARRY_SWEEP_END, u); // …then the arc, crossing at half
        const settle = 1.0 - mathx.smoothstep(PARRY_SWEEP_END, 1.0, u); // …and the follow-through unwinds
        return (2.0 * whip - coil) * settle;
    }

    /// THE BAT-AWAY — the guard's own stance with the boards shoved out of it, driven by the trunk and rocked
    /// back onto rest. A CAUGHT blow lands on top through `blockRecoil`: the man moves and the shield holds.
    fn poseParry(self: *Hero) void {
        const u = mathx.clampF(self.parryT / PARRY_DUR, 0, 1);
        const k = parryDrive(u);
        const s = parrySweep(u);
        const rec = self.blockRecoil();
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        // `poseGuard`'s pair: the bat-away is thrown by whichever arm the boards are actually on.
        const brd = armSide(self.shieldLeft(), true);
        const free = armSide(!self.shieldLeft(), false);
        // Negative winds him onto that side, positive carries the arm across.
        const blade = brd.mirror * (-(GUARD_BLADE + BLOCK_TRUNK * rec) + PARRY_TRUNK * s);
        const sink = GUARD_CROUCH + PARRY_SINK * k + BLOCK_SINK * rec;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(PARRY_PELVIS * blade), // the pelvis takes a share of the turn; the rest is waist
            mul(tr(0, hipY - sink, PARRY_HAND_LEAD * k - BLOCK_STEP * rec), mul(rx(PARRY_PITCH * k), ry(facingDeg))),
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, ry(0.5 * blade));
        setLocal(&wx, CHEST, self.rest, mul(rx(5.0 * rec), ry(0.5 * blade)));
        setLocal(&wx, NECK, self.rest, ry(-0.45 * blade));
        setLocal(&wx, HEAD, self.rest, mul(rx(PARRY_HEAD), ry(-0.55 * blade)));
        // BRACED, NOT SQUATTING: the feet are set and the shove takes up in soft knees.
        setLocal(&wx, HIPL, self.rest, mul(rx(-5.0 * k), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 12.0 * k + 8.0 * rec));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(4.0 * k), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 8.0 * k + 8.0 * rec));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        // THE BOARDS, driven at the blow and squaring onto it. The shoulder gains what the elbow gives back, so
        // the FOLD `shieldFit` inverts is untouched — see PARRY_PUNCH. Only the yaw and the fist roll turn them.
        setLocal(&wx, brd.sh, self.rest, mul3(
            rx(-(GUARD_SH_FLEX + PARRY_PUNCH * k - BLOCK_SHIELD_BACK * rec)),
            rz(brd.mirror * GUARD_SH_ABD),
            ry(brd.mirror * (-(GUARD_SH_CROSS - PARRY_SWEEP * k) + PARRY_ARM_LEAD * s)),
        ));
        setLocal(&wx, brd.el, self.rest, rx(-(GUARD_ELBOW - PARRY_PUNCH * k + BLOCK_SHIELD_FOLD * rec)));
        setLocal(&wx, brd.wr, self.rest, rz(brd.mirror * PARRY_WRIST * k));
        // …and the sword hand DRAWS BACK: the riposte, loading.
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
        const tuck = 1.0 - @abs(k); // peaks at the apex, gone at both ends
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul(mul(tr(0, hipY, 0), ry(facingDeg)), rootAt(self.footPos()));
        const fold = JUMP_FOLD * tuck + JUMP_ARCH * drive;
        setLocal(&wx, SPINE, self.rest, rx(fold * 0.5));
        setLocal(&wx, CHEST, self.rest, rx(fold * 0.5));
        setLocal(&wx, NECK, self.rest, rx(JUMP_HEAD_UP * 0.4 * drive));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK * reach + JUMP_HEAD_UP * 0.6 * drive));
        // The two legs never do the same thing at once — a symmetric pair reads as a doll off a table.
        jumpLeg(&wx, self.rest, drive, reach, tuck, 1.0 + JUMP_LEG_SPLIT / JUMP_TUCK_HIP, 1.0, HIPL, KNEEL, ANKL);
        jumpLeg(&wx, self.rest, drive, reach, tuck, 1.0 - JUMP_LEG_SPLIT / JUMP_TUCK_HIP, -1.0, HIPR, KNEER, ANKR);
        jumpArm(&wx, self.rest, drive, reach, tuck, 1.0, SHL, ELL, WRL);
        jumpArm(&wx, self.rest, drive, reach, tuck, -1.0, SHR, ELR, WRR);
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        // The boards stay up if they were up: one hand is holding a shield, not helping him fly.
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
            mul(rz(lean), rx(spin)), // dip the roll-side shoulder, then somersault forward over it
            mul(ry(facingDeg + skew), tr(0, ballY, 0)), // face roll dir (off-square fading out), lift to the ball centre
            rootAt(self.footPos()),
        );
        setLocal(&wx, SPINE, self.rest, rx(ROLL_SPINE * tuck));
        setLocal(&wx, CHEST, self.rest, rx(ROLL_SPINE * tuck));
        setLocal(&wx, NECK, self.rest, rx(ROLL_HEAD * 0.4 * tuck));
        setLocal(&wx, HEAD, self.rest, mul(rx(mathx.lerpF(HEAD_WALK, ROLL_HEAD, tuck)), ry(-0.5 * skew))); // chin to chest; the eyes lead the body back to square
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
        // THE POSE RUNS ON THE SWING'S OWN CLOCK (`atkDur`), never the bare sword's: a club posed at the sword's
        // rate lands its blow a third of a second after the picture has finished swinging it.
        const u = mathx.clampF(self.atkT / self.atkDur(false), 0, 1);
        const rec = 1.0 - mathx.smoothstep(AL_RECOV_A, 1.0, u); // 1 until recovery, draining to 0
        const wind = mathx.smoothstep(0, AL_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AL_STRIKE_A, AL_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_STRIKE_B + AL_LAG, u) * rec;
        const sElb = mathx.smoothstep(AL_WIND_B, AL_HIT_A + 0.04, u) * rec;
        const sWr = mathx.smoothstep(AL_STRIKE_A + 2 * AL_LAG, AL_STRIKE_B + 2 * AL_LAG, u) * rec;
        const sw: f32 = if (self.atkAlt) -1.0 else 1.0; // swing side: +1 forehand, -1 backhand return
        const amp: f32 = if (self.atkAlt) 0.8 else 1.0; // the cross-body windup can't coil as deep
        // **THE MIRROR IS ONE SIGN.** Same keys, same clocks, same curves — thrown from the other shoulder.
        const sd: f32 = if (self.swordLeft()) -1.0 else 1.0;
        const shS: usize = if (sd < 0) SHL else SHR; // the arm that swings…
        const elS: usize = if (sd < 0) ELL else ELR;
        const wrS: usize = if (sd < 0) WRL else WRR;
        const shF: usize = if (sd < 0) SHR else SHL; // …and the one that counterbalances
        const elF: usize = if (sd < 0) ELR else ELL;
        const wrF: usize = if (sd < 0) WRR else WRL;

        const os = AL_OVER * bump(u, AL_STRIKE_B + 2 * AL_LAG, AL_RECOV_A + 0.15);
        const yawP = sd * sw * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sPelv);
        const yawC = sd * sw * (1.35 * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sChest) + os);
        const crunch = AL_SPINE_CRUNCH * sChest;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yawP),
            mul(tr(0, hipY - AL_LOAD * wind - AL_DIP * sPelv, 0), mul(rx(1.5 * sChest), ry(facingDeg))), // only a WHISKER of pitch: the swipe plane stays flat
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
        // One lag after the pelvis and running to the END of the hit window, so the blade is flying for
        // every active frame: no pre-window hang, no dead beat at the tail.
        const sSweep = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_HIT_B - 0.01, u) * rec;
        const sweep = sw * (-AL_SWEEP_WIND * windAmp * wind + (AL_SWEEP_WIND * windAmp + AL_SWEEP_END) * sSweep + 0.9 * os);
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
        // `poseLight`'s mirror, on the same one sign and for its reason.
        const sd: f32 = if (self.swordLeft()) -1.0 else 1.0;
        const shS: usize = if (sd < 0) SHL else SHR;
        const elS: usize = if (sd < 0) ELL else ELR;
        const wrS: usize = if (sd < 0) WRL else WRR;
        const shF: usize = if (sd < 0) SHR else SHL;
        const elF: usize = if (sd < 0) ELR else ELL;
        const wrF: usize = if (sd < 0) WRR else WRL;

        const yaw = sd * (-AH_BODY_YAW * wind + 2.0 * AH_BODY_YAW * sPelv);
        const spineX = -AH_LEAN_BACK * wind + (AH_LEAN_BACK + AH_SPINE_CRUNCH) * sChest;
        const tilt = -AH_SPINE_TILT * wind + 1.5 * AH_SPINE_TILT * sChest;
        const dip = AH_LOAD * wind + (AH_DIP - AH_LOAD) * sPelv - 0.008 * H * rcl;
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
        const shX = -AH_SH_UP * wind - AH_GATHER * gather + (AH_SH_UP - AH_SH_DOWN) * sSh + AH_RECOIL * rcl;
        setLocal(&wx, shS, self.rest, mul(rx(shX), rz(sd * (-ARM_ABD - 8.0 * wind))));
        const elb = IDLE_ELBOW + (AH_ELBOW_WIND - IDLE_ELBOW) * wind + 5.0 * gather - (AH_ELBOW_WIND - AH_ELBOW_STRIKE) * sElb;
        setLocal(&wx, elS, self.rest, rx(-elb));
        setLocal(&wx, wrS, self.rest, rx(AH_WRIST_COCK * wind - (AH_WRIST_COCK + AH_WRIST_SNAP) * sWr + 8.0 * rcl));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), sd < 0);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// A full pose, not an overlay: he is PLANTED for it.
    fn poseCast(self: *Hero) void {
        const u = self.castU();
        const rec = 1.0 - mathx.smoothstep(CAST_RECOV_A, 1.0, u); // 1 until recovery, draining to 0
        const wind = mathx.smoothstep(0, CAST_WIND_B, u) * rec;
        const sSweep = mathx.smoothstep(CAST_WIND_B, CAST_RECOV_A, u) * rec;
        const sThrow = mathx.smoothstep(CAST_AT - 0.08, CAST_AT + 0.06, u) * rec;
        const kick = bump(u, CAST_AT + 0.06, CAST_RECOV_A) * rec; // the rod bounces off the throw
        const sw: f32 = if (self.castAlt) -1.0 else 1.0;

        // THE BREATH RIDES ON TOP OF THE HELD THROW. Pose time stands still for the whole pour (`castU`), so
        // without these channels the rime is a freeze frame with particles coming out of it. `bOn` braces him
        // BACK against what the rod is putting out, `bOut` is the OVERSHOOT past his rest as it stops — a mass
        // in motion settles onto its rest, it does not glide onto it — and the shiver is what says it is still
        // pouring. **THE SHIVER IS ON THE ARM HOLDING IT**, not on the skull: the tremor belongs to whatever
        // the stream is coming out of, and on the head it was a man shaking his face at a rod.
        const bU = self.breathU();
        const bOn = mathx.smoothstep(0, 0.14, bU) * (1.0 - mathx.smoothstep(0.82, 1.0, bU));
        const bOut = bump(bU, 0.80, 1.0);
        const shiver = bOn * BREATH_SHIVER * mathx.sinf(bU * combat.RIME_DUR * BREATH_SHIVER_HZ * std.math.tau);

        // THE ROD ARM IS WHICHEVER ONE IS HOLDING IT, and the free arm is the other. Written out as SHL/ELL/WRL
        // it mimed the whole throw on the left while the rod itself hung off the right — `poseWandArm` picked
        // its side and this, the move the spell actually is, did not.
        const rod = armSide(self.wandLeft(), true);
        const free = armSide(!self.wandLeft(), false);

        // `wind` lifts, `sSweep` twirls — separate channels, so the alternator only picks the twirl's side.
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
        // He ARCHES under the raised arm and folds back over the throw — the waist hinge, not a root lean. The
        // breath's own fold is the same hinge and goes in here for that reason, never at the ROOT: a lean
        // routed through the root rotates his legs and reads as a lurch.
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
        // The arm goes LONG as the bolt leaves: an elbow still folded keeps the stone inside his own silhouette.
        const elb = mathx.lerpF(WAND_CARRY_ELBOW, CAST_ELBOW, wind) - CAST_ELBOW_SNAP * sThrow + 6.0 * kick -
            BREATH_REACH * bOn + 0.5 * BREATH_REACH * bOut + shiver;
        setLocal(&wx, rod.sh, self.rest, mul3(rx(-(mathx.lerpF(WAND_CARRY_FLEX, CAST_SH_FWD, wind) - BREATH_SH_LEVEL * bOn)), ry(shRy), rz(shRz)));
        setLocal(&wx, rod.el, self.rest, rx(-elb));
        setLocal(&wx, rod.wr, self.rest, rz(rod.mirror * (mathx.lerpF(WAND_CARRY_WRIST, CAST_WRIST, wind) - 1.5 * CAST_WRIST * sThrow - 8.0 * kick + 1.6 * shiver)));
        // …and the sword arm keeps out of its way.
        setLocal(&wx, free.sh, self.rest, mul(rx(GUARD_SWORD_BACK * wind), rz(free.mirror * -ARM_ABD)));
        setLocal(&wx, free.el, self.rest, rx(-(IDLE_ELBOW + (GUARD_SWORD_ELBOW - IDLE_ELBOW) * wind)));
        setLocal(&wx, free.wr, self.rest, rx(GUARD_SWORD_WRIST * wind));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// `poseCast` on the other arm; its one novelty is the SHAKE. Two throws come out of one `exp × sin` for
    /// free, the second smaller than the first, which is the house law about a mass overshooting its rest.
    fn poseRing(self: *Hero) void {
        const u = self.ringU();
        const rec = 1.0 - mathx.smoothstep(RING_RECOV_A, 1.0, u); // 1 until recovery, draining to 0
        const lift = mathx.smoothstep(0, RING_AT - 0.06, u) * rec; // the bell up to shoulder height…
        // …and the shake, live from just before the note. `flickT` is REAL seconds so the rate is a rate.
        const flickT = (u - (RING_AT - RING_FLICK_LEAD)) * RING_DUR;
        const shake: f32 = if (flickT <= 0) 0 else @exp(-flickT * RING_DECAY) * mathx.sinf(flickT * RING_FLICK_RATE);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        // THE ARM THAT RINGS IS THE ONE HOLDING THE BELL. Written out as SHR/ELR/WRR, a bell equipped LEFT was
        // drawn in that hand and sounded by the empty one — `poseCast`'s bug on the other side of the body.
        const bel = armSide(self.bellLeft(), false);
        const free = armSide(!self.bellLeft(), true);

        var wx: [N]rl.Matrix = undefined;
        // The trunk gives back at the WAIST: a lean at the root rotates the legs and reads as a lurch.
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
        // Everything that shakes is the WRIST: a whole arm swinging reads as throwing rather than sounding.
        setLocal(&wx, bel.sh, self.rest, mul3(rx(-RING_SH_FWD * lift), ry(0), rz(bel.mirror * (-ARM_ABD - RING_SH_ABD * lift))));
        setLocal(&wx, bel.el, self.rest, rx(-(IDLE_ELBOW + (RING_ELBOW - IDLE_ELBOW) * lift) + 5.0 * shake));
        setLocal(&wx, bel.wr, self.rest, mul(rz(bel.mirror * RING_FLICK * shake), rx(-14.0 * lift)));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        // …and the off arm stays where the carry left it, so the boards do not go anywhere while he rings.
        setLocal(&wx, free.sh, self.rest, mul(rx(-6.0 * lift), rz(free.mirror * ARM_ABD)));
        setLocal(&wx, free.el, self.rest, rx(-(IDLE_ELBOW + 10.0 * lift)));
        setLocal(&wx, free.wr, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// Only the off arm and the head are the flask's; the legs stay the walk's, or travel would SKATE.
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
        // SLOW AND SOFT (owner, twice: too violent).
        const strum = mathx.sinf((t * 1.15 - @floor(t * 1.15)) * std.math.tau) * (0.55 + 0.45 * phrase);
        const breathe = 0.010 * H * mathx.sinf(t * 1.05);
        // THE LILT — he rocks with the phrase, not the strum.
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
        // FRETTING HAND (left): reaching out along the neck, which runs up and across to his left.
        const fret = 6.0 * phrase;
        setLocal(&wx, SHL, self.rest, mul(rx(-14.0 - fret), rz(ARM_ABD + 46.0)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 52.0 + fret)));
        setLocal(&wx, WRL, self.rest, rz(-26.0));
        // STRUMMING HAND (right): forearm draped over the lower bout, hand at the sound hole.
        setLocal(&wx, SHR, self.rest, mul(rx(-48.0 + 1.2 * strum), rz(-ARM_ABD - 34.0)));
        setLocal(&wx, ELR, self.rest, rx(-(IDLE_ELBOW + 88.0 + 3.5 * strum)));
        setLocal(&wx, WRR, self.rest, rz(9.0 * strum));
        placeSword(&wx, self.rest, rl.math.matrixIdentity(), self.swordLeft());
        // NO cross-fade: no rest path ticks `blendT`, so `applyXfade` would lerp at k = 0 and draw the stale
        // standing pose.
        self.xf = wx;
    }

    fn poseStun(self: *Hero) void {
        const heavy = self.stun == .heavy;
        // Through `heroStunDur`, not the pair by hand: a pose normalised on a duration the state machine does
        // not exit on either freezes at its peak or is cut off mid-release.
        const u = mathx.clampF(self.stunT / combat.heroStunDur(heavy), 0, 1);
        const amt = if (heavy)
            mathx.pulse(u, 0, 0.12, 0.68, 1.0) // ramp, hold, release
        else
            mathx.sinf(u * std.math.pi); // a single flinch pulse
        const leanMag: f32 = if (heavy) STAG_LEAN else HURT_LEAN;
        const lean = leanMag * amt;
        const wob: f32 = if (heavy) 3.0 * mathx.sinf(self.elapsed * 13.0) * amt else 0;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const sinkMag: f32 = if (heavy) 0.06 else 0.05;
        const sink = sinkMag * H * amt;
        // +Z in the pre-facing frame is the facing dir, so a −Z offset is backward.
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
        // Legs: the off leg softens, the sword-side leg shoots back to catch balance (heavy).
        const braceR: f32 = if (heavy) 26.0 * amt else 6.0 * amt;
        const kneeRMag: f32 = if (heavy) 30.0 else 12.0;
        setLocal(&wx, HIPL, self.rest, mul(rx(8.0 * amt), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 16.0 * amt));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(-braceR), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + kneeRMag * amt));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        // Arms fly out/up as balance goes; the sword hand keeps its grip (flails, doesn't drop).
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
        // The SWORD is bone `SWORD` itself, so it is stowed by not drawing that bone — and it is stowed
        // whenever the RIGHT hand is not the one holding it, since that bone hangs off the right wrist.
        const stowSword = self.resting or !self.holds(.sword);
        for (0..N) |i| {
            if (stowSword and i == SWORD) continue;
            rl.drawMesh(self.mesh[i], self.mat, self.xf[i]);
        }
        if (self.resting) {
            rl.drawMesh(self.guitar, self.mat, self.xf[ROOT]);
            return;
        }
        // ONE CALL PER HAND, and the hand is an ARGUMENT. As two switches keyed to two enums, which hand a
        // thing was drawn in was decided by its TYPE — so a sword equipped left drew on the right.
        if (armTwoHanded(self.off)) {
            _ = self.drawHand(self.off, false);
            return;
        }
        if (self.drawHand(self.arm, false)) return;
        if (self.offInHand()) _ = self.drawHand(self.off, true);
    }

    /// One hand's armament, at that hand's wrist. Returns whether it claimed BOTH hands, which is the bow's
    /// alone (`armTwoHanded`) — a raised bow puts the other hand on the string, so there is nothing to draw
    /// in it whatever is equipped there.
    fn drawHand(self: *const Hero, a: Armament, left: bool) bool {
        const wrist = self.xf[if (left) WRL else WRR];
        const grip = gripFrame(wrist, self.rest, left);
        switch (a) {
            // The sword is a rig BONE and `placeSword` has already hung it off whichever wrist holds it,
            // so the loop above drew it wherever it actually is. Nothing to do here in either hand.
            .sword => {},
            .bow => {
                rl.drawMesh(self.bow, self.mat, grip);
                for (self.stringXf) |sm| rl.drawMesh(self.bowString, self.mat, sm);
                if (self.nockVis) rl.drawMesh(self.bowNock, self.mat, self.nockXf);
                return true;
            },
            .bell => rl.drawMesh(self.bell, self.mat, grip),
            // The boards turn onto the ARM rather than sitting in the fist, so they take the wrist and their
            // own fit; the wand rides the wrist as it is. Both mirror with the hand.
            .shield => rl.drawMesh(self.shield, self.mat, mul(shieldFit(left), wrist)),
            .wand => rl.drawMesh(self.wand, self.mat, wrist),
        }
        return false;
    }

    /// The base of the neck, deliberately over the GROUND under him rather than over his feet: the rig is
    /// bolted to this, so a jump taken 1:1 reads as the WORLD dropping a metre rather than as him rising.
    pub fn shoulderPoint(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + self.rest[CHEST].y, self.pos.z);
    }
};

pub fn setHumanoid(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    setJoint(wx, &rest, i, @intCast(PARENT[i]), animRot);
}
const setLocal = setHumanoid;

/// **THE SWORD HANGS OFF WHICHEVER WRIST HOLDS IT.** `PARENT[SWORD]` is `WRR`, so placing it through here
/// rather than through the rig's own parent is what makes the hand a choice — and `xf[SWORD]` being right in
/// both hands is what makes the draw, `updateBlade`'s capsule and the trail right for free.
pub fn placeSword(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, animRot: rl.Matrix, left: bool) void {
    wx[SWORD] = mul(animRot, gripFrame(wx[if (left) WRL else WRR], rest, left));
}

/// **ONE HAND'S GRIP SLOT** — the sword bone's rest offset off that wrist, mirrored for the left, and it
/// exists whether or not a sword is in the hand. Every held thing rides it, so no caller passes a bare wrist
/// where a grip is meant: `HELD` IS the sword bone, and that bone moves with the blade.
pub fn gripFrame(wrist: rl.Matrix, rest: [N]rl.Vector3, left: bool) rl.Matrix {
    const d = mathx.subV(rest[SWORD], rest[WRR]);
    const off = if (left) v3(-d.x, d.y, d.z) else d;
    return mul(tr(off.x, off.y, off.z), wrist);
}

/// **ONE ARM'S THREE JOINTS, PICKED BY SIDE.** A handed pose asks for a side instead of transcribing six
/// indices, which is what let `poseCast`, `poseGuard` and `poseRing` each mime one named arm while the thing
/// they were posing hung off the other one. `mirror` is the sign every LATERAL channel is multiplied by —
/// `ry` and `rz` flip, `rx` is sagittal and reads the same on either side (`poseLight`'s rule).
pub const ArmSide = struct {
    sh: usize,
    el: usize,
    wr: usize,
    mirror: f32,
};

/// `left` is which hand this arm IS; `authoredLeft` which hand its pose was written for.
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
    const rigS = legLen / LEG_LEN; // rig-relative, so the 2x ogre would get a 2x sidestep
    const reach = STRAFE_REACH * rigS; // the measured sweep, scaled onto THIS rig
    const q = ph - @floor(ph); // leg-local phase; q = 0 is the instant this foot PLANTS
    // Foot travel along the travel direction, -^'reach..+reach.
    const swingLen = 1.0 - STRAFE_STANCE;
    var s: f32 = undefined;
    var w: f32 = -1.0; // swing progress 0..1; negative while planted
    if (q < STRAFE_STANCE) {
        s = reach * (1.0 - 2.0 * q / STRAFE_STANCE);
    } else {
        w = (q - STRAFE_STANCE) / swingLen;
        const v0 = -2.0 * reach * swingLen / STRAFE_STANCE; // ds/dw at lift-off, matched to stance
        const w2 = w * w;
        const w3 = w2 * w;
        s = -reach * (2.0 * w3 - 3.0 * w2 + 1.0) + v0 * (w3 - 2.0 * w2 + w) + reach * (3.0 * w2 - 2.0 * w3);
    }
    // rz(+) swings a leg toward +X, and lat > 0 is travel to his RIGHT, which is world −X.
    const dx = -lat * s * m;
    const crossing = side * lat > 0;
    const inSwing = w >= 0;
    const arc = if (inSwing) mathx.sinf(std.math.pi * w) else 0.0; // 0→1→0, swing only
    const passF = (if (crossing) @as(f32, STRAFE_CROSS) else -STRAFE_BEHIND) * arc * latW;
    const landF = if (inSwing or !crossing) 0.0 else STRAFE_LAND * (1.0 - 2.0 * q / STRAFE_STANCE) * latW;
    const latHip = passF + landF; // this leg's sagittal angle, LATERAL contribution only
    const clear = STRAFE_CLEAR * rigS * arc * latW;
    const rootS = mathx.maxF(1e-4, @sqrt(wx[ROOT].m0 * wx[ROOT].m0 + wx[ROOT].m1 * wx[ROOT].m1 + wx[ROOT].m2 * wx[ROOT].m2));
    const hipW = rl.math.vector3Transform(mathx.subV(rest[hip], rest[ROOT]), wx[ROOT]);
    // …down to the ANKLE JOINT, which rides rest[ank].y above the sole plane — not down to the floor.
    const vert = mathx.maxF(0.1 * legLen, (hipW.y - SOLE_Y) / rootS - rest[ank].y - clear);
    const span = @sqrt(vert * vert + dx * dx); // hip→ankle length the two links must make up
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
    setJoint(wx, rest, knee, hip, rx(kneeFlex)); // +rx = knee bends (shank swings back/up)
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
    const carryMove = carry * m; // any stick movement (WALK)
    const sprint = carry * mathx.clampF(sprintB, 0, 1) * m; // hold-B RUN only
    const sw = swing * (1.0 - CARRY_DAMP * carry) * (1.0 - CARRY_SWING_STILL * sprint);
    const walkElbow = mathx.maxF(6.0, 4.0 + 0.8 * sw);
    const runElbow = mathx.lerpF(RUN_ELBOW, CARRY_ELBOW_RUN, carry);
    const elbow = mathx.maxF(mathx.lerpF(IDLE_ELBOW, mathx.lerpF(walkElbow, runElbow, runB), m), CARRY_ELBOW * carry);
    const abd = ARM_ABD + CARRY_ABD_RUN * sprint; // arm eases out to the side only on a hold-B RUN
    setLocal(wx, sh, rest, mul(rx(-sw), rz(side * abd))); // -^'rx forward, ±side rz outward
    setLocal(wx, el, rest, rx(-elbow)); // -^'rx = forearm forward (elbow flexes)
    const lift = CARRY_WRIST_LIFT * mathx.lerpF(CARRY_LIFT_WALK, 1.0, mathx.clampF(sprintB, 0, 1)) * carryMove;
    setLocal(wx, wr, rest, mul(rx(lift), ry(CARRY_WRIST_YAW * sprint)));
}

fn rollLeg(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, tuck: f32, f: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    setLocal(wx, hip, rest, mul(rx(-ROLL_HIP * f * tuck), rz(-side * HIP_ADDUCT)));
    setLocal(wx, knee, rest, rx(mathx.lerpF(IDLE_KNEE, ROLL_KNEE * f, tuck)));
    setLocal(wx, ank, rest, ry(side * FOOT_TOEOUT));
}
/// ONE LEG THROUGH THE ARC. `f` is this leg's share of the tuck — the two are deliberately unequal.
fn jumpLeg(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, drive: f32, reach: f32, tuck: f32, f: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    // NEGATIVE rx IS FLEXION at the hip (`rollLeg`'s convention, and the gait curves' behind it), so the
    // toe-off — the leg still EXTENDED behind him — is the one term here with a positive sign.
    const hipA = JUMP_TOEOFF * drive - JUMP_TUCK_HIP * f * tuck - JUMP_REACH_HIP * reach;
    setLocal(wx, hip, rest, mul(rx(hipA), rz(-side * HIP_ADDUCT)));
    setLocal(wx, knee, rest, rx(IDLE_KNEE + JUMP_TUCK_KNEE * f * tuck + JUMP_REACH_KNEE * reach));
    // The ankle stays POINTED through the push and comes up to receive the ground on the way down.
    setLocal(wx, ank, rest, mul(rx(-JUMP_TOE_PLANTAR * drive + JUMP_REACH_DORSI * reach), ry(side * FOOT_TOEOUT)));
}
/// THE ARMS MUST SURVIVE THE APEX: `drive` and `reach` both pass through zero at the top of the arc, so an
/// arm hung off either alone goes limp on the one frame the whole jump is read from. The raise KEEPS a share
/// of itself the whole flight (`JUMP_ARM_HOLD`) and only trades it for the spread on the way down.
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

// Every body part's box goes through `slab`, so `false` restores the hard-edged mesh EXACTLY — `addRoundBox`
// takes the same FULL size. THE BLADES STAY SHARP: `swordMesh` is not routed through it.
const ROUND_EDGES = true;
/// 1 is a plain ellipsoid, 0 the hard cube. Low enough that the flats survive the fillet.
pub const ROUND_E: f32 = 0.34;
/// A fillet costs a box 6 quads → segs×sides, so the TESSELLATION IS SIZED TO THE PART. Measured off the part's
/// largest dimension in units of stature, so it holds if the rig is ever rescaled.
pub fn roundGrid(size: rl.Vector3) struct { segs: i32, sides: i32 } {
    const big = @max(@max(@abs(size.x), @abs(size.y)), @abs(size.z)) / H;
    if (big >= 0.12) return .{ .segs = 6, .sides = 12 };
    if (big >= 0.05) return .{ .segs = 5, .sides = 10 };
    return .{ .segs = 3, .sides = 6 };
}

/// The ONE place any body on this rig chooses between a filleted and a hard edge — the folk build through it
/// too, or `ROUND_EDGES` would leave every other human in the world filleted.
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

// Authored in the RIGHT-WRIST frame about the fist centre (0, FIST_Y, FIST_Z), blade canted `GRIP_PITCH`
// forward of the forearm line. Attacks whip the wrist and arm; the blade just rides.
fn swordMesh() rl.Mesh {
    var b = Builder.init();
    const s = v3(0.5 * OUT_CA, 0, 0.5 * OUT_SA); // half-unit flat-side axis of the canted frame
    const n = v3(-0.5 * GRIP_CA * OUT_SA, 0.5 * GRIP_SA, 0.5 * GRIP_CA * OUT_CA); // half-unit edge-side axis
    const a = v3(-0.5 * GRIP_SA * OUT_SA, -0.5 * GRIP_CA, 0.5 * GRIP_SA * OUT_CA); // half-unit blade axis
    b.setMat(.leather);
    b.addCylinder(bladeAt(0.026), bladeAt(-0.05), 0.014 * H, 0.012 * H, 6, BELT); // grip through the fist
    b.setMat(.steel);
    b.addBox(bladeAt(-0.058), scaleV(s, 0.028 * H), scaleV(a, 0.028 * H), scaleV(n, 0.028 * H), BRASS); // pommel
    b.addBox(bladeAt(0.036), scaleV(n, 0.115 * H), scaleV(a, 0.02 * H), scaleV(s, 0.03 * H), STEEL); // crossguard, quillons on the edge line
    b.addBox(bladeAt(0.231), scaleV(n, 0.048 * H), scaleV(a, 0.37 * H), scaleV(s, 0.012 * H), STEEL); // blade, edges fore/aft
    b.addCylinder(bladeAt(0.416), bladeAt(0.481), 0.020 * H, 0.001, 4, STEEL_DK); // tapering point
    return b.toMesh();
}

/// The skirt FLARES on a curve — a straight cone reads as a funnel. Authored in the HELD bone's frame like
/// the bow. The mouth is a real hole: outer skin, inner bore a wall's thickness in, rim band joining the two;
/// left as a bare `addCylinder` it is an open cut-pipe end and the skirt reads as tin foil.
fn bellMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xBE11);

    b.setMat(.wood);
    // The handle, turned: a swell in the middle so the fist has something to close on.
    b.addCapsule(bellAt(BELL_GRIP_T0), bellAt(BELL_GRIP_T0 + 0.018), 0.0105 * H, 0.0088 * H, 7, BELL_HANDLE);
    b.addCapsule(bellAt(BELL_GRIP_T0 + 0.014), bellAt(0.030), 0.0092 * H, 0.0115 * H, 7, BELL_HANDLE);
    b.addCapsule(bellAt(0.030), bellAt(BELL_CROWN_T), 0.0115 * H, 0.0080 * H, 7, BELL_HANDLE);

    b.setMat(.steel);
    // THE CROWN — a dome, not a lid. It is the shoulder the skirt hangs off and it carries the sun.
    b.addCapsule(bellAt(BELL_CROWN_T), bellAt(BELL_CROWN_T + 0.008), BELL_MOUTH_R * 0.30, BELL_MOUTH_R * 0.36, 12, BELL_BRONZE_LT);

    // Banded so the profile can bend at all, each band's radius jittered — a cast bell is never lathe-true,
    // and the variation goes BETWEEN the bands, never along one.
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
        // …and the BORE behind it, a wall in. Dark, and it is what you see through the mouth.
        b.addCylinder(bellAt(t0), bellAt(t1), r0 - BELL_WALL, r1 - BELL_WALL, 14, BELL_BORE);
    }
    // The rim closes the wall off; without it the skirt has no thickness and the bronze ends in a sheet edge.
    b.addCylinder(bellAt(BELL_MOUTH_T), bellAt(BELL_MOUTH_T - 0.004), BELL_MOUTH_R, BELL_MOUTH_R - BELL_WALL, 14, BELL_BRONZE_LT);
    // A raised moulding round the waist, sunk most of the way in: RELIEF IS SUBTLE, so it stands a few percent
    // of the radius proud and no more.
    const waistT = BELL_CROWN_T + 0.008 + span * 0.62;
    b.addCylinder(bellAt(waistT - 0.004), bellAt(waistT + 0.004), bellR(0.62) * 1.035, bellR(0.62) * 1.035, 14, BELL_BRONZE_LT);

    // THE CLAPPER, hung short so it sits up inside the mouth rather than dangling out of it. Off the axis on
    // purpose — a clapper at rest has swung to one side and stayed there.
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
    const a = mathx.normV(v3(0.74, 0.62, 0.26)); // up the neck: out to his left and well UP
    const d = v3(0, 0.40, 0.92);
    const n = mathx.normV(mathx.subV(d, mathx.scaleV(a, d.x * a.x + d.y * a.y + d.z * a.z)));
    art.guitarInto(&b, .{
        .o = v3(-0.30, -0.09, 0.14), // the body's tail, out past his right hip
        .w = mathx.crossV(a, n),
        .a = a,
        .n = n,
        .s = 1.35,
    });
    return b.toMesh();
}

/// THE BOLT IN FLIGHT — drawn along +Z, because `archer.arrowXform` orients that axis down the flight, and
/// STRETCHED along it so a side-on shot reads as a streak. Vertex alpha is the emissive channel.
pub fn boltMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(0.070, 0.070, 0.155), 7, 11, CHAOS_MOTE);
    b.addBlob(v3(0, 0, 0.020), v3(0.040, 0.040, 0.095), 6, 9, CHAOS_HOT);
    return b.toModel(shader);
}

/// ONE ROOT TENDRIL, authored at the origin coming UP out of the earth along +Y with a lean into +Z, so a yaw
/// about the site fans a ring of them outward. It starts BELOW zero, or a tendril on sloping ground shows the
/// flat disc of its own bottom cap. NOTHING DEAD IS STRAIGHT: it breaks at a knee and snaps off blunt.
fn rootTendrilMesh(variant: u32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x600751 +% variant *% 7919);
    b.setMat(.wood);
    // ONE TONE PER SHAFT: alternated per segment the two bark values striped every tendril like a barber's
    // pole. They separate the three VARIANTS instead.
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
        // It falls away from plumb a little MORE each segment. The jitter roughens the arc, it does not make it.
        dir = mathx.normV(v3(
            dir.x + (sway + rng.range(-0.05, 0.05)) * (0.4 + k),
            dir.y - curl * (0.4 + k),
            dir.z + (curl * 0.45 + rng.range(-0.05, 0.05)) * (0.4 + k),
        ));
    }
    // …and the BLUNT SNAP it ends in, a touch fatter than the shaft so it reads as a break and not a taper.
    b.addBlob(p, v3(r * 1.30, r * 0.95, r * 1.30), 4, 9, ROOT_HEART);
    // THREE STUBS off the outer half — a bare shaft is a cane. Blunt too: `addCapsule` domes both ends.
    var s: u32 = 0;
    while (s < 3) : (s += 1) {
        const base = mathx.lerpV(v3(0, 0, 0), p, rng.range(0.40, 0.78));
        const a = rng.angle();
        const len = ROOT_LEN * rng.range(0.11, 0.19);
        // They RUN WITH the shaft, not across it: thrown out level they read as the crossbar of a grave marker.
        const out = v3(base.x + mathx.cosf(a) * len * 0.55, base.y + rng.range(0.75, 1.15) * len, base.z + mathx.sinf(a) * len * 0.55);
        const sr = ROOT_R1 * rng.range(1.0, 1.5);
        b.addCapsule(base, out, sr * 1.5, sr, 7, bark);
    }
    return b.toMesh();
}

/// Authored in the LEFT WRIST's frame on `WAND_AX`, so it needs no fit matrix. Wabi-sabi off a FIXED seed.
fn wandMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x7A4D91);
    const segs = 5;
    // Nothing dead is straight, and nothing ends in a point. The drift stays SMALL: "cut from a hedge".
    b.setMat(.wood);
    var prev = wandAt(-WAND_BUTT_T); // the butt below the fist — what says he grips it near the END
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
        // Knots, sunk most of the way in. OFF the axis rather than a collar round it: a knot grew on one side.
        if (i > 0 and i < segs - 1) {
            const kn = offAxis(mathx.lerpV(prev, to, rng.range(0.30, 0.70)), r1 * 0.55, rng.range(0, std.math.tau));
            b.addBlob(kn, v3(r1 * 0.85, r1 * 0.85, r1 * 0.85), 4, 7, WAND_WOOD_LT);
        }
        prev = to;
    }

    // Short fat capsules ALONG the shaft: a turn must be perpendicular to the rod, and the rod is not a
    // world axis.
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
    // The claws ring the SHAFT, in `WAND_U`/`WAND_V` — a ring in world XZ hangs askew on a rod off plumb.
    const behind = wandAt(WAND_TIP_T - 0.020);
    var c: i32 = 0;
    while (c < 3) : (c += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(c)) / 3.0 + rng.range(-0.22, 0.22);
        // They CRADLE it: tips stop short of the stone's equator, else it reads as three white teeth.
        const tipCl = offAxis(behind, WAND_STONE_R * 0.66 * rng.range(0.86, 1.06), a);
        b.addCapsule(neck, tipCl, WAND_R * 0.40, WAND_R * 0.24, 5, WAND_FERRULE);
    }

    // Vertex alpha is the EMISSIVE channel, so a LOW one is what reads as lit from inside rather than painted.
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
        fn at(rho: f32) f32 { // the dish's height above the equator plane at radius `rho`
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
    // The BOSS, sunk most of the way in so only its cap breaks the face, and a shade off centre.
    b.addBlob(
        v3(0.004 * H, -0.002 * H, SHIELD_THICK * 0.55),
        v3(0.034 * H, 0.033 * H, 0.030 * H),
        4,
        11,
        SHIELD_BOSS,
    );
    b.setMat(.leather);
    slab(&b, v3(0, 0, -SHIELD_THICK * 1.15), v3(0.090 * H, 0.026 * H, 0.014 * H), LEATHER);
    slab(&b, v3(0, 0, -SHIELD_THICK * 0.9), v3(0.034 * H, 0.052 * H, 0.010 * H), LEATHER_DK); // the arm pad
    return b.toMesh();
}

const scaleV = mathx.scaleV;

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    slab(&b, v3(0, -0.01 * H, 0), v3(0.235 * H, 0.16 * H, 0.175 * H), BELT);
    b.setMat(.cloth);
    slab(&b, v3(0, 0.055 * H, 0), v3(0.215 * H, 0.07 * H, 0.16 * H), TUNIC_DK); // hip skirt of the tunic
    b.setMat(.steel);
    slab(&b, v3(0, -0.005 * H, 0.0925 * H), v3(0.035 * H, 0.035 * H, 0.012 * H), BRASS); // buckle
    b.setMat(.leather);
    slab(&b, v3(0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    slab(&b, v3(-0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    slab(&b, v3(-0.115 * H, -0.045 * H, -0.03 * H), v3(0.05 * H, 0.06 * H, 0.045 * H), LEATHER_DK); // pouch
    slab(&b, v3(-0.115 * H, -0.028 * H, -0.03 * H), v3(0.054 * H, 0.02 * H, 0.05 * H), LEATHER); // pouch flap
    const d = v3(0.10, -0.90, -0.42);
    const p1 = v3(0.995, 0.090, 0.042);
    const p2 = v3(0, -0.422, 0.9045);
    const s0 = v3(0.115 * H, -0.045 * H, -0.015 * H); // scabbard throat (at the belt line)
    const hl = 0.185 * H; // scabbard half-length
    b.addBox(v3(s0.x + d.x * hl, s0.y + d.y * hl, s0.z + d.z * hl), v3(p1.x * 0.020 * H, p1.y * 0.020 * H, p1.z * 0.020 * H), v3(d.x * hl, d.y * hl, d.z * hl), v3(p2.x * 0.010 * H, p2.y * 0.010 * H, p2.z * 0.010 * H), LEATHER_DK);
    b.setMat(.steel);
    b.addBox(v3(s0.x + d.x * 2 * hl, s0.y + d.y * 2 * hl, s0.z + d.z * 2 * hl), v3(p1.x * 0.023 * H, p1.y * 0.023 * H, p1.z * 0.023 * H), v3(d.x * 0.014 * H, d.y * 0.014 * H, d.z * 0.014 * H), v3(p2.x * 0.012 * H, p2.y * 0.012 * H, p2.z * 0.012 * H), STEEL_DK); // chape
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
    slab(&b, v3(0, 0.035 * H, -0.005 * H), v3(0.305 * H, 0.06 * H, 0.18 * H), LEATHER_DK); // collar/mantle at the shoulders
    b.setMat(.cloth);
    slab(&b, v3(0, -0.01 * H, 0.086 * H), v3(0.135 * H, 0.11 * H, 0.012 * H), CAPE); // tabard chest panel
    slab(&b, v3(0, -0.035 * H, -0.098 * H), v3(0.24 * H, 0.115 * H, 0.016 * H), CAPE); // short cape at the back
    b.setMat(.leather);
    slab(&b, v3(0, 0.042 * H, -0.10 * H), v3(0.25 * H, 0.035 * H, 0.02 * H), LEATHER); // cape yoke
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
    slab(&b, v3(0, 0.075 * H, -0.005 * H), v3(0.135 * H, 0.115 * H, 0.15 * H), SKIN); // cranium
    slab(&b, v3(0, 0.018 * H, 0.012 * H), v3(0.10 * H, 0.055 * H, 0.125 * H), SKIN); // jaw
    slab(&b, v3(0, 0.05 * H, 0.082 * H), v3(0.028 * H, 0.03 * H, 0.03 * H), SKIN_DK); // nose
    b.setMat(.leather); // hair reads through the leather pore stipple (strand-ish, not plastic)
    slab(&b, v3(0, 0.118 * H, -0.025 * H), v3(0.145 * H, 0.05 * H, 0.15 * H), HAIR); // hair cap
    slab(&b, v3(0, 0.055 * H, -0.078 * H), v3(0.135 * H, 0.125 * H, 0.035 * H), HAIR); // back of hair
    slab(&b, v3(0, 0.012 * H, -0.092 * H), v3(0.05 * H, 0.05 * H, 0.035 * H), HAIR); // nape knot
    slab(&b, v3(0, 0.092 * H, 0.0 * H), v3(0.142 * H, 0.018 * H, 0.152 * H), LEATHER_DK); // headband
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.078 * H, 0.058 * H, 10, CLOTHDK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -0.002 * H, 0), v3(0, -0.075 * H, 0), 0.088 * H, 0.072 * H, 10, LEATHER_DK); // skirt ring
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.09 * H, 0), 0.058 * H, 0.062 * H, 10, CLOTHDK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -0.09 * H, 0), v3(0, -SEG_SHANK * H, 0), 0.064 * H, 0.036 * H, 10, BOOT);
    slab(&b, v3(0, -0.02 * H, 0.052 * H), v3(0.062 * H, 0.06 * H, 0.026 * H), LEATHER); // kneecap
    return b.toMesh();
}

fn footMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    // Boot: sole rests on the ground (ankle joint is ANKLE_Y=0.039 H up), toes forward +Z.
    const ay = 0.039 * H;
    slab(&b, v3(0, -ay + 0.028 * H, 0.045 * H), v3(0.085 * H, 0.056 * H, 0.19 * H), BOOT);
    slab(&b, v3(0, -ay + 0.075 * H, -0.02 * H), v3(0.075 * H, 0.05 * H, 0.09 * H), BOOT); // ankle cuff
    return b.toMesh();
}

fn upperArmMesh(big: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    if (big) {
        slab(&b, v3(0, -0.005 * H, 0), v3(0.125 * H, 0.10 * H, 0.13 * H), LEATHER);
        b.setMat(.steel);
        slab(&b, v3(0, 0.048 * H, 0), v3(0.105 * H, 0.045 * H, 0.115 * H), STEEL_DK); // steel rim cap
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
    b.addCylinder(v3(0, -0.065 * H, 0), v3(0, -SEG_FOREARM * H, 0), 0.047 * H, 0.034 * H, 9, LEATHER); // bracer
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    slab(&b, v3(0, -0.05 * H, 0.005 * H), v3(0.05 * H, 0.10 * H, 0.045 * H), BOOT); // glove
    return b.toMesh();
}


/// A Hero for the STATE tests.
fn testHero() Hero {
    var h = Hero{
        .mesh = undefined,
        .bow = undefined,
        .bowString = undefined,
        .bowNock = undefined,
        .shield = undefined,
        .wand = undefined,
        .bell = undefined,
        .roots = undefined,
        .guitar = undefined,
        .mat = undefined,
        .rest = restPositions(),
    };
    // `xf` and `blendXf` are `undefined` defaults, so without this the first `startXfade` freezes
    // uninitialised memory as the source pose and a test passes or fails on the struct's byte layout.
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
            h.updateShot(1.0 / 240.0, null); // a fast machine, where an edge is easiest to miss
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
    // IT RIDES BOTH SHOTS IN PROPORTION, so the snapshot never becomes the better of the two.
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
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.count(.plain)); // it spent the RIGHT quiver
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
    // A BOW CHIPS; IT DOES NOT WIN (owner's call).
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

    // A BONFIRE AND A RESPAWN ARE CUTS, not blends, and they say so themselves.
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
    // Numeric check of updateRoll's normalization claim (profile integral over u is (BRAKE_A+BRAKE_B)/2, so peak * integral * DUR == DIST).
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
        if (n > 100_000) break; // the "stuck in the air" failure, caught rather than hung on
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
    h.pos = v3(3, 1.25, -2); // standing on a bank, not on the datum
    _ = h.startJump(mathx.zero3, 0);
    var high: f32 = 0;
    while (h.airborne()) {
        h.updateAir(1.0 / 60.0, null);
        try std.testing.expectEqual(@as(f32, 1.25), h.pos.y);
        try std.testing.expectApproxEqAbs(h.footY(), h.pos.y + h.lift, 1e-5);
        high = @max(high, h.lift);
    }
    try std.testing.expect(high > 0.9);
    try std.testing.expectEqual(@as(f32, 0), h.lift); // …and ZERO the moment he is down, always
}

test "THE GROUND CATCHES HIS FEET WHEREVER IT IS — a jump onto a ledge lands early, off one lands late" {
    const flat = flyJump(1.0 / 60.0).air;
    // Onto a LEDGE: the datum rises under him mid-flight, and he lands on it.
    var up = testHero();
    _ = up.startJump(mathx.zero3, 0);
    var t: f32 = 0;
    while (up.airborne()) : (t += 1.0 / 60.0) {
        if (t > 0.30) up.pos.y = 0.6;
        up.updateAir(1.0 / 60.0, null);
    }
    try std.testing.expect(t < flat);
    try std.testing.expectEqual(@as(f32, 0.6), up.pos.y);
    // …and off a DROP, the far side of the same rule: the ground falls away and he is in the air longer.
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
    try std.testing.expect(!h.startJump(mathx.zero3, 0)); // no double jump, and it falls out of `committed()`
    h.startRoll(v3(0, 0, 1));
    try std.testing.expect(!h.rolling);
    // …and the swing pressed on the way down is BUFFERED, not eaten: it goes off the frame he lands.
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
    h.enterStun(.heavy); // dropActions leaves the jump alone on purpose: he is still up there
    try std.testing.expect(h.jumping);
    var n: usize = 0;
    while (h.airborne() and n < 1000) : (n += 1) h.updateStun(1.0 / 60.0);
    try std.testing.expect(n < 1000);
    try std.testing.expectEqual(@as(f32, 0), h.lift);
}

test "HE JUMPS, HE DOES NOT DIVE — the trunk stays near upright the whole way through" {
    // Measured as the angle of the PELVIS→HEAD line off world up, which is what the eye actually reads.
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
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.landDip(), 1e-4); // it ARRIVES; it does not start sunk
    var peak: f32 = 0;
    var over: f32 = 0;
    var t: f32 = 0;
    while (t <= LAND_DUR) : (t += 1.0 / 240.0) {
        h.landT = t;
        peak = @max(peak, h.landDip());
        over = @min(over, h.landDip());
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1), peak, 0.02);
    try std.testing.expect(over < -0.05); // …and it rises PAST its stance on the way back
    h.landT = LAND_DUR;
    try std.testing.expectEqual(@as(f32, 0), h.landDip());
    h.landT = mathx.LONG_AGO;
    try std.testing.expectEqual(@as(f32, 0), h.landDip());
}

/// A hero facing +Z with the shield already up.
fn testGuarded() Hero {
    var h = testHero();
    h.facing = 0;
    h.guarding = true;
    return h;
}

/// The world direction a blow `deg` off his facing comes FROM (facing 0 = +Z).
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
    // `tickClocks` floors the whole pool at `self.pos.y`, which is wrong for the two things thrown clear of
    // him: floored at his feet, thrown soil stops in mid-air over a hollow.
    var h = testHero();
    h.pos = v3(0, 0, 0); // he is standing on the datum…
    const dug: f32 = -3.0; // …and the victim is in a pit
    h.rootsBurst(v3(6, dug, 0), true);
    var soil: usize = 0;
    for (h.fx) |q| {
        if (q.life <= 0) continue;
        soil += 1;
        try std.testing.expectEqual(@as(?f32, dug), q.floor);
    }
    try std.testing.expect(soil > 0);
    // …and it is that floor the tick honours, so the dirt falls back into the hollow it came out of.
    var t: f32 = 0;
    while (t < 1.2) : (t += 1.0 / 60.0) foemod.tickParticles(&h.fx, 1.0 / 60.0, h.pos.y);
    for (h.fx) |q| {
        if (q.life > 0) try std.testing.expect(q.p.y < 0);
    }
    // A BOLT BURSTING UP A WALL still falls to the EARTH, which is why the floor is not the contact point.
    var w = testHero();
    w.boltBurst(v3(0, 4.0, 0), 0.0, 1);
    for (w.fx) |q| {
        if (q.life > 0) try std.testing.expectEqual(@as(?f32, 0.0), q.floor);
    }
    // …and what comes off HIM never names one, so it keeps taking the floor its owner hands it.
    var own = testHero();
    own.pose(); // `parrySparks` rides the posed wrist
    own.parrySparks();
    for (own.fx) |q| {
        if (q.life > 0) try std.testing.expect(q.floor == null);
    }
}

test "i-frames beat the shield, and a committed action drops it" {
    var h = testGuarded();
    h.rolling = true;
    h.rollT = 0.1; // inside ROLL_IFRAME_END
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
    // Frame one is before the window opens: the arm has to be moving first.
    try std.testing.expect(!h.parryLive());
    // …then it opens, and it SHUTS well before the animation does — that gap is the risk.
    var t: f32 = 0;
    var liveFor: f32 = 0;
    while (h.parrying and t < PARRY_DUR * 3.0) : (t += 1.0 / 60.0) {
        if (h.parryLive()) liveFor += 1.0 / 60.0;
        h.updateParry(1.0 / 60.0, null);
    }
    try std.testing.expect(!h.parrying);
    try std.testing.expect(liveFor > 0.08 and liveFor < PARRY_DUR * 0.5);
    // And nothing is caught outside it: a mistimed parry eats the hit at full weight, with no shield up either.
    try std.testing.expect(!h.parryLive());
    var late = testHero();
    try std.testing.expect(late.requestParry());
    late.parryT = PARRY_SHUT + 0.01;
    try std.testing.expect(!late.parryLive());
    try std.testing.expectEqual(combat.HitOutcome.taken, late.takeHit(.{ .dmg = 20, .poise = 99 }, fromAngle(0)));
    // …and the SHOVE PEAKS INSIDE the window, or the pose and the mechanic tell different stories.
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
    armed.off = .wand; // one left hand — the boards are not in it
    try std.testing.expect(!armed.requestParry());
    // AN EMPTY BAR IS THE ONE REFUSAL THAT FLASHES: the guard just stays down, but a press has to answer.
    var spent = testHero();
    spent.stam.spend(combat.STAM_MAX);
    try std.testing.expect(!spent.requestParry());
    try std.testing.expect(spent.stamRefused > 0);
    // …and the panic rule holds on the way in: any bar above zero buys the window.
    var thin = testHero();
    thin.stam.cur = 1.0;
    try std.testing.expect(thin.requestParry());
    try std.testing.expectApproxEqAbs(@as(f32, 0), thin.stam.cur, 1e-4);
}

test "the shove OVERSHOOTS its rest and settles back on it, and the boards never sink through the window" {
    // The drive channel: 0 at the start, 1 at the peak, back THROUGH rest and dead on it at the end.
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parryDrive(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), Hero.parryDrive(PARRY_PUNCH_AT), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parryDrive(1.0), 1e-5);
    var crossed = false;
    var u: f32 = PARRY_PUNCH_AT;
    while (u <= 1.0) : (u += 0.005) {
        if (Hero.parryDrive(u) < -0.02) crossed = true;
    }
    try std.testing.expect(crossed); // a mass in motion overshoots — a glide to a stop reads as weightless
    // …and THE SWIPE it travels on: coiled the OTHER way, all the way across, and home on centre at the end.
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1), Hero.parrySweep(PARRY_COIL_AT), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), Hero.parrySweep(PARRY_SWEEP_END), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(1.0), 1e-5);
    // …and it crosses CENTRE exactly where the thrust peaks: the boards travel fastest THROUGH the blow.
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(PARRY_PUNCH_AT), 1e-5);
    try std.testing.expect(PARRY_SWEEP_END > PARRY_PUNCH_AT and PARRY_SWEEP_END < 1.0);
    // …and the STANCE BLEND is held up for the whole window: a shield that sinks through a parry contradicts it.
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
    // …and with nothing on the button they EASE back down, which is a settle and not a latched guard.
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
    // …AND A RAISED BOW TAKES THAT HAND TO THE STRING. The wand stays EQUIPPED; it is simply not in his hand.
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
    // A HALF-FULL COST BUYS NOTHING — deliberately the opposite of the panic roll's asymmetry.
    var spent = testHero();
    spent.off = .wand;
    spent.fp.cur = combat.BOLT_FP - 0.01;
    try std.testing.expect(!spent.requestCast());
    try std.testing.expect(!spent.casting);
    try std.testing.expect(spent.fpRefused > 0); // …on the FP frame, not the stamina one
    try std.testing.expectApproxEqAbs(@as(f32, 0), spent.stamRefused, 1e-6);
    // AND AN EMPTY STAMINA BAR STILL LEAVES HIM A SPELL, which is the whole point of a second resource.
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
    // Committed like a swing — a second press is dropped rather than queued (the loose's rule).
    try std.testing.expect(!h.requestCast());
    h.requestAttack(.light);
    try std.testing.expect(h.casting and !h.attacking);
    var guard: u32 = 0;
    while (h.casting and guard < 500) : (guard += 1) h.updateCast(1.0 / 60.0, null);
    try std.testing.expect(!h.casting);
    try std.testing.expect(h.attacking);
    // …and a reaction DROPS one mid-sweep. The FP is already gone, exactly as a staggered draught's charge is.
    var hit = testHero();
    hit.off = .wand;
    try std.testing.expect(hit.requestCast());
    const paid = hit.fp.cur;
    hit.enterStun(.light);
    try std.testing.expect(!hit.casting and hit.staggered());
    try std.testing.expectApproxEqAbs(paid, hit.fp.cur, 1e-4); // no refund
}

test "REPEATED CASTS SWEEP OPPOSITE WAYS, and the bolt leaves ONCE, from over his head" {
    var h = testHero();
    h.off = .wand;
    h.pose(); // a clean source pose, so the cast's own cross-fade has something real to come out of
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
    try std.testing.expect(peak > 0); // …and the tip was sampled at all
}

test "THE BOLT IS ALL CHAOS, and it is worth more than a light slash before anything resists it" {
    // Pure chaos: no physical at all, the brood mother's one-substance-one-element rule.
    try std.testing.expectApproxEqAbs(@as(f32, 0), combat.BOLT_HIT.dmg, 1e-6);
    try std.testing.expectApproxEqAbs(combat.BOLT_HIT.raw(), combat.BOLT_HIT.elem.at(.chaos), 1e-6);
    // "DECENT DAMAGE" (owner's call), sat between the two swings it is spent instead of.
    try std.testing.expect(combat.BOLT_HIT.raw() > ATK_LIGHT_HIT.dmg);
    try std.testing.expect(combat.BOLT_HIT.raw() < ATK_HEAVY_HIT.dmg);
    // …and its poise sits between them too: it rocks a foe, it is not the stagger tool.
    try std.testing.expect(combat.BOLT_HIT.poise > ATK_LIGHT_HIT.poise);
    try std.testing.expect(combat.BOLT_HIT.poise < ATK_HEAVY_HIT.poise);
    // A FULL POOL IS A COUNTABLE NUMBER OF CASTS — if this stops dividing sensibly the wand has silently become a spammable or a one-shot.
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
    // The LOADOUT survives a death: what is in his hands is not a meter to refill.
    try std.testing.expectEqual(Off.wand, h.off);
}

test "THE FLOOR IS A DRIP: standing in acid takes HP and never the poise refill" {
    // A floor HOLDS, so it bills through `Vitals.drip` for the wand grip's reason: through `hit` it re-stamps the refill gate faster than it opens.
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
    // …and it is still VISIBLE while it does it — the floating bar's own clock is stamped by every pulse.
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
    const hx = rest[HIPL].x; // his LEFT hip sits at +x
    const crossedL = testStrafeAnkle(0.0, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const crossedR = testStrafeAnkle(0.0 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(crossedL.x < crossedR.x - 0.05);
    const openL = testStrafeAnkle(0.5, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const openR = testStrafeAnkle(0.5 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(openL.x > openR.x + 2.0 * hx); // uncrossed AND wider than the hips
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
        const bodyTravel = step * STRAFE_CYCLE; // world -^'x, so the foot must gain +x by this much
        try std.testing.expect(@abs((b.x - a.x) - bodyTravel) < 0.1 * bodyTravel);
    }
}

test "strafe: cadence lands near the forward walk's — no coffeed-up patter" {
    const walkCycle = STRIDE; // at the reference walk speed the stride scale is exactly 1
    const walkCadence = 1.0 / walkCycle; // cycles per unit time at unit speed
    const strafeCadence = STRAFE_SPEED / STRAFE_CYCLE;
    try std.testing.expect(strafeCadence < 1.15 * walkCadence);
    try std.testing.expect(strafeCadence > 0.75 * walkCadence);
}

test "the rig's rest leg length matches the LEG_LEN the strafe geometry is measured off" {
    const rest = restPositions();
    try std.testing.expect(@abs((rest[HIPL].y - rest[ANKL].y) - LEG_LEN) < 1e-4);
    try std.testing.expect(@abs((rest[HIPR].y - rest[ANKR].y) - LEG_LEN) < 1e-4);
}

// The deepest any sole corner reaches, over a full stride at `speed` travelling `lat`-ward.
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
    // Both halves fail SILENTLY: a sword equipped left used to draw and swing on the right, and the hitbox
    // stayed welded to the right wrist whatever the equipment page said.
    var h = testHero();
    h.arm = .sword;
    h.off = .shield;
    try std.testing.expect(!h.swordLeft());
    try std.testing.expect(h.holds(.sword));
    h.pose();
    const right = h.xf[SWORD];

    // The SAME loadout with the hands exchanged: the equip screen's whole promise.
    h.arm = .shield;
    h.off = .sword;
    try std.testing.expect(h.swordLeft());
    try std.testing.expect(h.holds(.sword)); // …so the swing is still allowed
    h.pose();
    const left = h.xf[SWORD];

    // The bone actually MOVED, and it moved ACROSS him rather than drifting: the lateral component flips
    // sign and the height does not.
    try std.testing.expect(right.m12 * left.m12 < 0 or @abs(right.m12 - left.m12) > 0.05);
    try std.testing.expectApproxEqAbs(right.m13, left.m13, 0.35);

    // …and the hitbox rides it, which is the half nothing on screen would have shown.
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

    // A BOW IN THE OTHER HAND TAKES BOTH, so a sword behind one is not held at all.
    h.arm = .bow;
    h.off = .sword;
    try std.testing.expect(!h.swordLeft() and !h.holds(.sword));
}

test "THE ROD LEAVES THE HAND IT IS IN — the tip is where every spell comes out of" {
    // The blade's test, one armament along, and this half is the one nothing on screen showed: the mesh and
    // the carry arm were both already handed, so a rod equipped RIGHT looked completely correct and then
    // threw its bolt, laid its rune ring and breathed its whole cone out of the empty left fist.
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

    // It crossed him rather than staying put, and it is on the wrist it is drawn at either way.
    try std.testing.expect(mathx.distXZ(leftTip, rightTip) > 0.15);
    try std.testing.expect(mathx.distXZ(leftTip, rl.math.vector3Transform(mathx.zero3, leftWrist)) < 0.5);
    try std.testing.expect(mathx.distXZ(rightTip, rl.math.vector3Transform(mathx.zero3, h.xf[WRR])) < 0.5);

    // …AND THROUGH THE CAST ITSELF, which is the move that was miming the left arm regardless.
    h.casting = true;
    h.castT = CAST_DUR * CAST_AT;
    h.pose();
    const castTip = h.wandTipWorld();
    try std.testing.expect(mathx.distXZ(castTip, rl.math.vector3Transform(mathx.zero3, h.xf[WRR])) < 0.6);
    // The throwing arm is the one that MOVED off its carry; the free arm stayed near where it was.
    var carry = testHero();
    carry.arm = .wand;
    carry.off = .shield;
    carry.pose();
    try std.testing.expect(mathx.distXZ(wristAt(h.xf[WRR]), wristAt(carry.xf[WRR])) > 0.08);
}

test "THE BOARDS AND THE BELL GO WITH THEIR HAND TOO" {
    // The shield: the sparks and the block's grit are thrown off the FACE, so a hub read off a fixed wrist
    // puts every one of them beside the other arm.
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
    // The face still points AWAY from him on both sides — a mirror that missed the normal turns it inward.
    for ([_]rl.Vector3{ leftFace.n, rightFace.n }) |n| try std.testing.expect(n.z > 0.2);

    // The bell is the right-authored one, so its failure is the mirror image: rung left, drawn left.
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
    // The LEFT wrist is now the one doing the ringing, and it has left its idle carry to do it.
    var idle = testHero();
    idle.arm = .shield;
    idle.off = .bell;
    idle.pose();
    try std.testing.expect(mathx.distXZ(wristAt(b.xf[WRL]), wristAt(idle.xf[WRL])) > 0.08);
    try std.testing.expect(mathx.distXZ(wristAt(b.xf[WRR]), wristAt(rungRight)) > 0.08); // …and the right one is not
}

/// A bone matrix's own origin in world space — where that joint IS. Tests compare poses by it.
fn wristAt(m: rl.Matrix) rl.Vector3 {
    return rl.math.vector3Transform(mathx.zero3, m);
}

test "A TWO-HANDER CLAIMS BOTH HANDS FROM EITHER SLOT" {
    // THE BUG: `offInHand` asked only whether the RIGHT slot was two-handed, so a bow set in the LEFT slot
    // left a shield in the right reading as held — blocked with, parried with, and drawn nowhere.
    var h = testHero();
    h.arm = .shield;
    h.off = .bow;
    try std.testing.expect(h.bowOut());
    try std.testing.expect(!h.holds(.shield));
    try std.testing.expect(!h.canGuard() and !h.canParry());
    try std.testing.expect(!h.offInHand());
    // …and that hand is what the bow is worked from, whichever slot it sits in.
    try std.testing.expectEqual(Armament.bow, h.armInHand());
    h.arm = .bow;
    h.off = .shield;
    try std.testing.expect(!h.holds(.shield) and !h.canGuard());
    try std.testing.expectEqual(Armament.bow, h.armInHand());
    // With no two-hander anywhere, both hands carry their own.
    h.arm = .sword;
    h.off = .shield;
    try std.testing.expect(h.offInHand() and h.holds(.sword) and h.holds(.shield));
    try std.testing.expectEqual(Armament.sword, h.armInHand());
}

test "A SKILL REACHES THE BLOW IT GOVERNS AND NOTHING ELSE" {
    // AT THE STARTING SHEET NOTHING MOVED. This is the whole licence for putting damage behind an attribute:
    // `stats.scaleFor(START)` is exactly 1, so every tuned constant in the game means what it always meant.
    var bare = testHero();
    bare.atkHeavy = true;
    try std.testing.expectApproxEqAbs(ATK_HEAVY_HIT.dmg, bare.attackHit().dmg, 1e-4);
    bare.atkHeavy = false;
    try std.testing.expectApproxEqAbs(ATK_LIGHT_HIT.dmg, bare.attackHit().dmg, 1e-4);
    try std.testing.expectApproxEqAbs(combat.BOLT_HIT.raw(), bare.castBlow().?.raw(), 1e-3);

    // STRENGTH DRIVES THE CLUB, DEXTERITY THE DIRK, and neither drives the other — a shared curve applied to
    // whatever weapon happened to be in his hand would make the two rows on the page decoration.
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
    try std.testing.expectApproxEqAbs(dirkBase, dirk.attackHit().dmg, 1e-4); // the dirk cares nothing for it
    dirk.sheet.set(.dexterity, 60);
    try std.testing.expect(dirk.attackHit().dmg > dirkBase);

    // …AND IT IS THE DAMAGE DIAL ONLY. A strong man swinging a club does not gain a stagger he never bought:
    // poise and stance belong to the WEAPON's mass, which is `weigh`'s own split.
    var strong = testHero();
    _ = strong.wear(.hand_sword, .greatclub);
    strong.atkHeavy = true;
    const weakPoise = strong.attackHit().poise;
    const weakStance = strong.attackHit().stance;
    strong.sheet.set(.strength, 99);
    try std.testing.expect(strong.attackHit().dmg > clubBase);
    try std.testing.expectApproxEqAbs(weakPoise, strong.attackHit().poise, 1e-4);
    try std.testing.expectApproxEqAbs(weakStance, strong.attackHit().stance, 1e-4);

    // THE BOW IS DEXTERITY'S EVEN WITH AN EMPTY SOCKET (`item.bareArm`) — inheriting the sword's `quality`
    // default, a bowman would have been paid for strength he never spent a point on.
    var bow = testHero();
    bow.arm = .bow;
    const shotBase = bow.shotBlow().dmg;
    bow.sheet.set(.strength, 99);
    try std.testing.expectApproxEqAbs(shotBase, bow.shotBlow().dmg, 1e-4);
    bow.sheet.set(.dexterity, 60);
    try std.testing.expect(bow.shotBlow().dmg > shotBase);

    // …AND INTELLIGENCE IS THE ROD'S, multiplying WHOLE so the levin keeps the poise it is bought for.
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
    // The belt lands on the sheet the moment it is cinched — not at the next bonfire, `Hero.wear`'s own rule.
    try std.testing.expect(h.wear(.belt, .banded_warbelt));
    try std.testing.expectEqual(base + 3, h.sheet.at(.strength));
    // …and it reaches the swing it is for.
    var plain = testHero();
    plain.atkHeavy = true;
    h.atkHeavy = true;
    try std.testing.expect(h.attackHit().dmg > plain.attackHit().dmg);
    // Taking it off gives the points back, and nothing else moved with them.
    try std.testing.expect(h.wear(.belt, null));
    try std.testing.expectEqual(base, h.sheet.at(.strength));
    try std.testing.expectEqual(base, h.sheet.at(.dexterity));

    // **THE TREE AND THE GEAR ADD**, and a node applied afterwards may not wipe the belt off the sheet — which is
    // exactly what `applyPerks` did while it assigned the sheet straight from the bonus.
    try std.testing.expect(h.wear(.belt, .banded_warbelt));
    var b = ptree.Bonus{};
    b.attrs[@intFromEnum(statsmod.Attr.strength)] = 2;
    h.applyPerks(b);
    try std.testing.expectEqual(base + 5, h.sheet.at(.strength));

    // A BOON MAY NOT MOVE A BAR WITHOUT KEEPING WHAT IS IN IT (`refitBars`). Vitality is the one that would show,
    // so it is checked through a charm's resize on a half-full bar plus a re-seat of the sheet.
    var v = testHero();
    v.vit.hp = v.vit.hpMax * 0.5;
    v.fp.cur = v.fp.max * 0.5;
    v.stam.cur = v.stam.max * 0.5;
    try std.testing.expect(v.wear(.neck, .ashen_amulet));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), v.vit.hp / v.vit.hpMax, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), v.fp.cur / v.fp.max, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), v.stam.cur / v.stam.max, 1e-4);
    // …and the amulet is the ROD's, so the cast moved and the sword did not.
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
    // THREE PIECES ARE ONE ANSWER: summed over the sockets (`armourOf`), not read off the coat alone — as one
    // socket's lookup a helm and a pair of boots were worn, drawn, described and worth nothing.
    try std.testing.expect(all.armourA() > one.armourA());
    // …and it is still a CURVE: the full suit turns aside less of a killing blow than of a poke, and never all.
    const a = all.armourA();
    const smallOff = 1.0 - combat.armourTaken(a, 10) / 10.0;
    const bigOff = 1.0 - combat.armourTaken(a, 60) / 60.0;
    try std.testing.expect(smallOff > bigOff);
    try std.testing.expect(smallOff < 1.0);
    // A socket still refuses what does not belong in it, on the new sockets as much as the old.
    try std.testing.expect(!all.wear(.helm, .marchboots));
    try std.testing.expect(!all.wear(.ring2, .leech_signet)); // the first ring's band, in the second finger
    try std.testing.expect(all.wear(.ring2, .deft_signet));
}

test "WHAT HE IS WEARING REACHES THE FIGHT — the swing, the clock, the bill, the boards and the bar" {
    var bare = testHero();
    var club = testHero();
    _ = club.wear(.hand_sword, .greatclub);
    var dirk = testHero();
    _ = dirk.wear(.hand_sword, .fang_dirk);

    // THE SWING: the club hits harder and heavier, the dirk lighter — and the STANCE follows the poise, or a
    // weapon would hit harder without hitting heavier (`weigh`).
    bare.atkHeavy = true;
    club.atkHeavy = true;
    dirk.atkHeavy = true;
    try std.testing.expect(club.attackHit().dmg > bare.attackHit().dmg);
    try std.testing.expect(club.attackHit().poise > bare.attackHit().poise);
    try std.testing.expect(club.attackHit().stance > bare.attackHit().stance);
    try std.testing.expect(dirk.attackHit().dmg < bare.attackHit().dmg);

    // …AND THE CLOCK MOVES WITH IT, both tiers. A weapon that hit half again as hard in the same time would be
    // a strictly better sword and there would be no decision on the page.
    try std.testing.expect(club.atkDur(true) > bare.atkDur(true));
    try std.testing.expect(club.atkDur(false) > bare.atkDur(false));
    try std.testing.expect(dirk.atkDur(false) < bare.atkDur(false));

    // …and the BILL. Measured on the pool, since that is where a swing is actually paid for.
    club.startAttack(.heavy);
    bare.startAttack(.heavy);
    try std.testing.expect(club.stam.cur < bare.stam.cur);

    // THE BOARDS: a door covers more of the compass and lets less through, and the negation is CAPPED so a row
    // and a tree node together can never make a block free (`combat.GUARD_NEGATE_CAP`).
    var door = testHero();
    _ = door.wear(.hand_shield, .tower_shield);
    try std.testing.expect(door.guardArc() > bare.guardArc());
    door.guarding = true;
    bare.guarding = true;
    door.perk.guard = 0.5; // a node stacked on top of the biggest shield in the game
    const blow = combat.Hit{ .dmg = 40, .poise = 30, .stance = 10 };
    const hpBefore = door.vit.hp;
    _ = door.takeHit(blow, mathx.headingDir(door.facing + std.math.pi));
    try std.testing.expect(door.vit.hp < hpBefore); // it chipped him: nothing the boards stop is stopped outright

    // THE COAT: physical only, and worth MORE against a small blow than a big one — the curve, not a percentage.
    var coat = testHero();
    _ = coat.wear(.chest, .quilted_gambeson);
    const a = coat.armourA();
    try std.testing.expect(a > 0);
    const smallOff = 1.0 - combat.armourTaken(a, 10) / 10.0;
    const bigOff = 1.0 - combat.armourTaken(a, 60) / 60.0;
    try std.testing.expect(smallOff > bigOff);
    // …and it never touches the poise or the stance: those belong to the blow.
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
    try std.testing.expectApproxEqAbs(@as(f32, 0), bare.drinkLeech(), 1e-6); // nothing on the finger gives nothing

    // A SOCKET REFUSES WHAT DOES NOT BELONG IN IT — the one failure that would otherwise be silent: the piece
    // sits there, every dial reads as 1, and it does nothing at all.
    try std.testing.expect(!bare.wear(.chest, .greatclub));
    try std.testing.expect(!bare.wear(.hand_sword, .quilted_gambeson));
    try std.testing.expect(bare.worn.at(.chest) == null);
}

test "WHAT STARTS IS WHAT LANDS — a variant taken up mid-stroke cannot reach into the one in flight" {
    var h = testHero();
    h.startAttack(.light);
    const dur = h.atkDur(false);
    const dmg = h.attackHit().dmg;
    // Mid-recovery, past the strike window: the book is open, the world is held, and he picks up the club.
    h.atkT = dur * 0.70;
    try std.testing.expect(!h.hitActive());
    try std.testing.expect(h.wear(.hand_sword, .greatclub));

    // THE SWING IN FLIGHT IS UNMOVED. Read live, `atkT / dur` fell back to 0.52 of a club's longer clock —
    // inside `AL_HIT_A`..`AL_HIT_B`, which re-opens a window that had already closed and re-arms
    // `foe.strike`'s one-hit latch, so one press landed on one body twice for the club's own damage.
    try std.testing.expectApproxEqAbs(dur, h.atkDur(false), 1e-6);
    try std.testing.expectApproxEqAbs(dmg, h.attackHit().dmg, 1e-4);
    try std.testing.expect(!h.hitActive());

    // …and the NEXT stroke is the club's, which is what makes it a latch and not a refusal.
    h.attacking = false;
    h.startAttack(.light);
    try std.testing.expect(h.atkDur(false) > dur);
    try std.testing.expect(h.attackHit().dmg > dmg);

    // THE SAME RULE ON THE STRING (`shotArrow`'s own): the warbow's `dur` is a real clock now, so a swap
    // between the draw and the loose may not re-time the shaft already on it.
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
    // …and the warbow IS slower to get away, as its row says and as `item.effect` has been printing all along.
    try std.testing.expect(b.shotDur(false) > shot);
    try std.testing.expectApproxEqAbs(BOW_SHOT_DUR * item.equip(.grave_warbow).arm.dur, b.shotDur(true), 1e-6);
}
