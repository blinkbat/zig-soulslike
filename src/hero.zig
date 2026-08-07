const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const statsmod = @import("stats.zig");
const art = @import("propart.zig");
const archer = @import("archer.zig");
const foemod = @import("foe.zig"); // the shared swing ribbon lives here, with the other FX every actor shares

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const radians = mathx.radians;


pub const H: f32 = 1.8; // stature (world units ≈ metres)

pub const WALK_SPEED: f32 = 1.7;
pub const RUN_SPEED: f32 = 3.4;
pub const SPRINT_SPEED: f32 = 5.1; // hold-B RUN — a touch faster than a full-stick walk-sprint
/// LOCKED-ON sideways travel, as a fraction of forward (ER is anisotropic too).
pub const STRAFE_SPEED: f32 = 0.85;
/// …and behind the shield, as a fraction of the WALK.
pub const GUARD_SPEED: f32 = 0.75;
/// A DRAUGHT IS COMMITTED, NOT PLANTED (owner's call) — he shuffles it down at this fraction of the
/// WALK. Clearly under the shield's 0.75, because tipping a flask back is the more awkward of the two,
/// and never zero: rooting him was the old behaviour and it read as a dropped input.
pub const DRINK_SPEED: f32 = 0.35;
/// How far he settles onto his heels as the flask goes up — folded into the gait's own `crouch` now that
/// the draught rides OVER the walk rather than replacing it.
const DRINK_SINK: f32 = 0.012;

// Body-segment lengths as a fraction of stature H (Drillis & Contini 1966; Winter).
pub const SEG_THIGH = 0.245; // hip → knee   (femur)
pub const SEG_SHANK = 0.246; // knee → ankle (tibia)
pub const SEG_UPARM = 0.188; // shoulder → elbow
pub const SEG_FOREARM = 0.145; // elbow → wrist

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

/// THE REST POSE for any humanoid on this scaffold: joint positions in the creature's own standing frame (X = its left, Y up, Z forward), as fractions of stature scaled by `stature`.
pub fn restHumanoid(hx: f32, sx: f32, stature: f32) [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.640, 0);
    r[CHEST] = v3(0, 0.760, 0);
    r[NECK] = v3(0, 0.815, 0); // neck base sits just at the shoulder line…
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

pub const HIP_HALF = 0.090; // hip half-separation (a touch under half the bi-iliac breadth so the stance isn't splayed)
pub const SHOULDER_HALF = 0.150; // shoulder half-separation (~half the biacromial breadth, plus pauldron room)

fn restPositions() [N]rl.Vector3 {
    return restHumanoid(HIP_HALF, SHOULDER_HALF, H);
}

const SKIN = rgba(150, 112, 86, 255);
const SKIN_DK = rgba(120, 88, 66, 255);
const TUNIC = rgba(38, 40, 50, 255); // dark iron-blue wool
const TUNIC_DK = rgba(28, 30, 38, 255);
const LEATHER = rgba(58, 39, 26, 255); // oxblood-brown pauldron/bracer leather
const LEATHER_DK = rgba(38, 26, 18, 255);
const CLOTHDK = rgba(44, 39, 32, 255); // umber trousers
const BOOT = rgba(24, 22, 20, 255); // near-black boots/gloves
const BELT = rgba(34, 26, 18, 255);
const HAIR = rgba(40, 31, 24, 255); // warm dark brown
const CAPE = rgba(82, 20, 12, 255); // faded oxblood-crimson cloth
const STEEL = rgba(98, 104, 114, 255);
const STEEL_DK = rgba(58, 62, 70, 255);
const BRASS = rgba(122, 92, 40, 255);

pub const HIP_FLEX = [8]f32{ 25, 13, 3, -5, -10, -3, 12, 22 };
pub const KNEE_FLEX = [8]f32{ 5, 18, 10, 4, 10, 38, 62, 30 };
pub const ANK_DORSI = [8]f32{ -2, -6, 2, 9, 6, -14, -6, -1 };

pub const RUN_HIP = [8]f32{ 42, 25, 8, -8, 5, 35, 60, 55 };
pub const RUN_KNEE = [8]f32{ 26, 48, 40, 28, 62, 98, 80, 44 }; // deeper bend throughout — coiled + low
pub const RUN_ANK = [8]f32{ -3, 10, 22, 2, -18, -6, 0, -2 };
const RUN_LEAN = 24.0; // deep forward trunk lean when running (deg)
const RUN_ARM_SWING = 30.0; // shoulder swing amplitude when running (deg)
const RUN_ELBOW = 85.0; // elbows bent ~90° and pumping
const RUN_CROUCH = 0.06 * H; // pelvis drops — a low centre of gravity
const BODY_PITCH_RUN = 9.0; // whole-body forward pitch about the FEET at run — moves the centre of gravity ahead of the base
const BODY_PITCH_SPRINT = 18.0;
const HEAD_WALK = 7.0; // gentle downward head tilt at idle/walk — a natural "looking a few steps ahead" gaze
const GAZE_AHEAD = 15.0; // running: counter the lean down to ~this chain angle; final gaze ≈ GAZE_AHEAD+HEAD_WALK below horizontal (a few metres ahead), never craned up
const NECK_EXT_MAX = 34.0; // cap total head+neck extension so lifting the gaze can't hyperextend the neck
const A_RUN_BOUNCE = 0.05 * H; // vertical airtime lift during flight (up-only, so planted feet don't sink)
const RUN_SPEED_LO = 2.1; // blend walk→run across this ground-speed band
const RUN_SPEED_HI = RUN_SPEED;
const SPRINT_LEAN = 40.0; // near-horizontal forward tilt at full sprint (deg)
const SPRINT_REF_SPEED = SPRINT_SPEED; // speed the extra sprint lean/crouch saturate at

const SLOPE_LEAN: f32 = 0.55;
/// …capped, because the hero can stand on ground far steeper than he can walk up (`env.MAX_SLOPE` governs travel, not standing), and a 40 deg fold at the waist reads as a stumble.
const SLOPE_LEAN_MAX: f32 = 16.0;
/// How fast the lean chases the ground, in degrees a second.
pub const SLOPE_LEAN_RATE: f32 = 120.0;

/// The body pitch a given uphill gradient asks for, in degrees.
pub fn slopeLean(rise: f32) f32 {
    const deg = mathx.degrees(std.math.atan(rise)) * SLOPE_LEAN;
    return mathx.clampF(deg, -SLOPE_LEAN_MAX, SLOPE_LEAN_MAX);
}

const ROLL_DUR = 0.70; // seconds, start to finish (souls medium-roll pacing, recovery included)
const ROLL_IFRAME_END = 0.46; // invulnerable from the FIRST frame to here (~ER medium, a shade
const ROLL_DIST = 3.5; // ground units travelled
const ROLL_BALL_Y = 0.50; // pelvis/pivot height at mid-roll (the tucked "ball" centre)
const ROLL_TUCK_IN = 0.16; // dive: crouched + balled by here, spin barely begun
const ROLL_SPIN_A = 0.05; // somersault sweep: two OVERLAPPED eases, front-loaded.
const ROLL_SPIN_M0 = 0.40; // over-the-shoulder tumble (A..M1, ROLL_SPIN_OVER deg) hands
const ROLL_SPIN_M1 = 0.45; // off to the slower unroll (M0..B); the full 360° lands here
const ROLL_SPIN_B = 0.80; // BEFORE the stand-up.
const ROLL_SPIN_OVER = 220.0; // degrees covered by the fast tumble segment
const ROLL_UNTUCK_A = 0.62; // legs extend to plant as the last of the spin lands…
const ROLL_UNTUCK_B = 0.97;
const ROLL_RISE_A = 0.70; // recovery: pelvis rises from ball height…
const ROLL_RISE_B = 1.00;
const ROLL_BRAKE_A = 0.50; // travel: full lunge speed until here…
const ROLL_BRAKE_B = 0.92;
const ROLL_HIP = 95.0; // tuck: thighs to chest (deg)
const ROLL_KNEE = 115.0; // tuck: heels toward glutes (deg)
const ROLL_SPINE = 30.0; // forward spine curl per segment (deg)
const ROLL_HEAD = 32.0; // chin to chest (deg)
const ROLL_SHOULDER = 45.0; // arms tuck forward (deg)
const ROLL_ELBOW = 100.0; // elbows tucked (deg)
const ROLL_LEAN = 8.0; // bank toward the roll-side shoulder while balled (deg)
const ROLL_SKEW = 7.0; // peak off-square yaw through the recovery, squared up by the end (deg)
const ROLL_ARM_GUIDE = 1.25; // roll-side arm tucks harder across the body…
const ROLL_ARM_PUSH = 0.80;
const ROLL_LEG_LEAD = 1.08; // lead leg balls tighter…
const ROLL_LEG_TRAIL = 0.92;
const ROLL_VAR_LO = 0.7; // per-roll drift of the imperfection magnitudes (never of
const ROLL_VAR_HI = 1.3; // duration/distance/heading — mechanics stay exact)
const ROLL_YAW_RATE = 22.0; // rad/s — the body whips onto the roll heading instead of teleport-snapping

const ATK_LIGHT_DUR = 0.60; // R1: diagonal high-right → low-left slash (seconds)
const ATK_HEAVY_DUR = 1.00; // R2: overhead chop (seconds)
const AL_WIND_B = 0.28; // a READABLE windup — long enough to register as anticipation
const AL_STRIKE_A = 0.28; // pelvis fires; chest/shoulder/elbow/wrist each lag AL_LAG more
const AL_STRIKE_B = 0.48;
const AL_LAG = 0.03;
const AL_RECOV_A = 0.62; // unwind to a stand across the tail
const AL_HIT_A = 0.32; // TAE-style ACTIVE window — the blade only hits inside it
const AL_HIT_B = 0.56;
const AL_LUNGE = 0.55; // ground units stepped into the cut — a real committed step-in (ER R1 pressure)
const AL_CHAIN = 0.80; // u where a BUFFERED action may take over: the swing has visually
const AH_WIND_B = 0.34; // slow raise to overhead — the R2 anticipation "tell"
const AH_STRIKE_A = 0.38;
const AH_STRIKE_B = 0.52;
const AH_LAG = 0.025;
const AH_RECOV_A = 0.72; // impact holds buried 0.52..0.72, then the slow rise
const AH_HIT_A = 0.40;
const AH_HIT_B = 0.58;
const AH_LUNGE = 1.05; // the chop LEAPS forward through the drop — committed reach, ER-style
const AH_CHAIN = 0.86; // the heavy earns a longer commitment before a buffered exit
const ATK_RETRACK = 9.0; // rad/s
const AL_BODY_YAW = 26.0; // trunk winds HARD toward the sword side (the exaggerated tell)…
const AL_BODY_YAW_THRU = 24.0;
const AL_SH_ELEV_WIND = 55.0; // forward-raise at the chamber: fist at shoulder height…
const AL_SH_ELEV = 79.0;
const AL_SWEEP_WIND = 72.0; // shoulder yaw wound around BEHIND the sword shoulder at the chamber…
const AL_SWEEP_END = 64.0;
const AL_ALT_WIND = 0.62;
const AL_ELBOW_WIND = 96.0; // deep fold — the blade lies back over the shoulder at the chamber
const AL_ELBOW_STRIKE = 8.0; // arm out LONG for the whole pass (fires with the raise): the blade
const AL_WRIST_LAY = 18.0; // wrist deviation: the blade trails back at the CHAMBER only, released
const AL_WRIST_WHIP = 12.0;
const AL_EDGE_ROLL = 90.0; // the swipe RE-GRIPS: roll the blade a quarter-turn about its OWN
const AL_TIP_UP = 10.0;
const AL_SPINE_CRUNCH = 2.5; // a horizontal cut ROTATES — barely any forward commit (keeps the
const AL_OVER = 6.0; // follow-through overshoot past the end pose, settling through recovery (the arrest, not a park)
const AL_LOAD = 0.016 * H; // the knees coil DOWN under the windup (anticipation you can feel)…
const AL_DIP = 0.015 * H;
const AH_BODY_YAW = 11.0; // an overhead is mostly sagittal — modest wind/release
const AH_LEAN_BACK = 10.0; // spine extension under the raised blade (per segment)
const AH_SPINE_CRUNCH = 16.0; // violent trunk flexion driving the chop (per segment)
const AH_SPINE_TILT = 5.0; // frontal coil toward the sword side under the raise, whipping past on the drop
const AH_GATHER = 9.0; // the blade settles a touch FURTHER back through the top-of-raise hang (a breath, not a freeze)
const AH_SH_UP = 158.0; // arm swung up past vertical, blade hanging back over the shoulder
const AH_SH_DOWN = 38.0; // chop lands with the arm forward-low
const AH_ELBOW_WIND = 92.0;
const AH_ELBOW_STRIKE = 10.0;
const AH_WRIST_COCK = 22.0;
const AH_WRIST_SNAP = 28.0;
const AH_RECOIL = 7.0; // impact judder: the buried blade bites, bounces a hair, re-settles
const AH_LOAD = 0.02 * H; // the staggered stance loads under the windup…
const AH_DIP = 0.05 * H;
const AH_PITCH = 9.0; // whole-body forward pitch about the feet through the strike
const BOW_QUICK_DUR: f32 = 0.62; // R1: snap it up, loose, drop it — the shot you take mid-fight
const BOW_QUICK_AT: f32 = 0.55;
const BOW_SHOT_DUR: f32 = 0.34; // R2 out of a HELD aim: the string is already back…
const BOW_SHOT_AT: f32 = 0.22;
const BOW_SNAP: f32 = 0.06; // as a fraction of the shot's own duration
pub const BOW_QUICK_HIT = combat.Hit{ .dmg = 10, .poise = 5 };
pub const BOW_AIMED_HIT = combat.Hit{ .dmg = 23, .poise = 11, .stance = 8 };
/// THE FIRE ARROW: a pitched head that adds FIRE damage on top of the shaft's own physical, PoE2's "adds X fire damage" on an armament. Carried as a FRACTION of that shaft's physical so it rides the quick shot and the aimed one in proportion instead of making the snapshot the better of the two — and it is the one dial for how much the scarce ammunition is worth (`combat.FIRE_ARROWS_MAX` is the other).
pub const FIRE_ARROW_FRAC: f32 = 0.5;

pub fn fireTipped(h: combat.Hit) combat.Hit {
    var out = h;
    out.elem = combat.elems(.{ .fire = h.dmg * FIRE_ARROW_FRAC });
    return out;
}

/// WHAT AN ARROW KIND IS, in the two terms the rest of the game needs: the BLOW it lands and the PROJECTILE
/// that carries it. Both live here, both EXHAUSTIVE, because the alternative was three `== .fire` tests in
/// three files — the loose, the shot harness and the HUD — and a third kind of arrow would have compiled
/// against every one of them and quietly flown as a plain shaft.
pub fn arrowBlow(k: combat.ArrowKind, aimed: bool) combat.Hit {
    const base = if (aimed) BOW_AIMED_HIT else BOW_QUICK_HIT;
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

/// …and whether the HUD should draw its ammo box alight. The cross takes a plain bool on purpose — `hud.zig` knows nothing about the hero — so the enum is resolved HERE rather than there.
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
const BOW_SH_FLEX = 88.0; // the bow punched out toward the target, arm near-straight…
const BOW_SH_ABD = 9.0;
const BOW_ELBOW = 13.0; // the bow arm stays LONG — a folded bow arm is a bow held at your own face
const BOW_WRIST = 6.0;
const BOW_DRAW_SH = 84.0; // the draw arm hauls right back to the anchor…
const BOW_DRAW_ELBOW = 152.0;
const BOW_DRAW_ABD = 33.0;
const BOW_DRAW_YAW = 16.0;
const BOW_BLADE = 7.0; // the trunk turns side-on to the target (deg, PER SEGMENT over spine + chest)
const BOW_HEAD_NOD = 6.0;
const BOW_HEAD_YAW = 8.0;
const BOW_HEAD_CANT = 9.0;
const BOW_STOOP = 4.0; // a ready stoop that straightens as the draw comes back (the counterweight)
const BOW_CARRY_SH = 26.0; // the LOW CARRY, bow not presented: down at his side
const BOW_CARRY_ELBOW = 8.0;
const BOW_DRAW_REST = 26.0;
const BOW_KICK = 7.0; // the bow arm bounces forward off the release (the follow-through)
const BOW_BLEND_RATE = 11.0;
/// rad/s onto the aim line through a loose — faster than `ATK_RETRACK`: a shaft off the line just misses.
const TURN_TO_SHOT = 11.0;

const CAST_DUR: f32 = 0.66; // s, between a light slash's 0.60 and a heavy's 1.00
const CAST_AT: f32 = 0.46; // …and the bolt leaves at the middle of the twirl, not the end of it
pub const BOLT_SPEED: f32 = 30.0; // under the aimed shaft's 40, over the quick one's 26
pub const BOLT_REACH: f32 = 55.0;

// Two beats on SEPARATE channels: the lift is `rx`+`rz`, the twirl a transverse `ry`. Welded onto one `rz`
// the raise WAS the sweep, and `rz` past 90 walks the arm through vertical where the sweep has no two sides.
/// deg. FLEXION, NOT ABDUCTION: the elbow's hinge axis rides the shoulder, so abducting stands it vertical and
/// the fold then sweeps the forearm across the chest instead of up past the temple. The rig has no humeral
/// rotation channel to correct it with.
const CAST_SH_FWD = 118.0;
const CAST_LIFT_ABD = 24.0; // just enough to keep the raise off the mid-line and out of his face
const CAST_ELBOW = 52.0; // opens OUT of the carry's fold as the arm comes up
const CAST_ELBOW_SNAP = 40.0; // …and goes LONG as the bolt leaves (the warriors' law)
/// deg either side of centre, in the TRANSVERSE plane — which is why it can exceed the 34 the frontal plane
/// capped it at without laying the forearm over his own face.
const CAST_SWEEP = 46.0;
const CAST_WRIST = 38.0; // the flick that throws it
// The CARRY (`poseWandArm`), and where the lift starts from: a folded elbow, since the elbow is what gets the
// lit head up off the ground.
const WAND_CARRY_FLEX = 14.0;
const WAND_CARRY_ABD = 6.0;
const WAND_CARRY_ELBOW = 74.0;
const WAND_CARRY_WRIST = -12.0;
const WAND_CARRY_SWING = 0.55; // fraction of the gait's shoulder swing a carried rod leaves the arm…
const WAND_CARRY_ELBOW_SWING = 0.40; // …and the elbow breathes with it rather than staying welded
const CAST_TRUNK = 7.0; // trunk yaw toward the casting side (deg, PER SEGMENT over spine + chest)
const CAST_LEAN = 6.0;
const CAST_HEAD = 9.0;
const CAST_DIP = 0.020 * H; // the knees load under the raise and give it back on the throw
const CAST_WIND_B = 0.32; // the raise, read as anticipation
const CAST_RECOV_A = 0.70; // …and the unwind back to a stand

/// THE WAND ITSELF — a knotted rod with a bound grip and a chaos-lit stone in its head. Authored in the
/// LEFT WRIST's frame extending out of the fist along −Y, exactly as the sword is off the right, so the
/// raised arm carries it up and away from the skull instead of across it.
const WAND_LEN = 0.30 * H;
const WAND_R = 0.0155 * H;
const WAND_STONE_R = 0.030 * H;
const WAND_WOOD = rgba(41, 30, 24, 255); // dark stained rod — a big smooth mass authored near-black
const WAND_WOOD_LT = rgba(62, 47, 36, 255);
const WAND_BIND = rgba(30, 25, 22, 255); // the grip's wrapped cord
/// Near-black or it CLIPS: small strongly-curved capsules take the sun over their whole visible face, and both
/// 58/62/70 and `SHIELD_IRON` sampled at 255,255,255 here — a white cage round the stone, not a setting for it.
/// Screen ∝ albedo^(1/2.2), so a 0.6× screen value is albedo × 0.6^2.2.
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
/// The head leads DISTALLY, the sword's convention (`bladeAt`). Do not flip it proximal to improve the carry:
/// the lit end then points at the floor the instant the hand goes above the shoulder, and the rod has one
/// authored axis for both poses. The carry earns the head's height at the ELBOW instead (`poseWandArm`).
///
/// The whole rod is built in this frame, and the shaft is NOT a world axis — so every ring on it (cord turns,
/// setting claws) has to be swept perpendicular to `WAND_U`/`WAND_V`, never a Y-flattened `addBlob`.
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

/// THE CHAOS VIOLET, and it is ONE pair of colours for the whole spell — the stone, the gather, both
/// bursts and the flight streak. Two substances of one element is what the brood mother's spit-and-pool
/// rule exists to forbid, and a bolt whose sparks were a different violet from its own trail is that.
const CHAOS_MOTE = rgba(168, 84, 216, 190);
const CHAOS_HOT = rgba(224, 176, 250, 210);
const CAST_MOTE_RATE = 52.0; // motes a second drawn onto the stone as the raise STARTS…
const CAST_MOTE_R = 0.17; // …from this far out
/// Both dials ride the charge so the tell tightens visibly as the throw comes on: a flat rate over a flat
/// radius gives no way to see from the FX how close the throw is.
const CAST_MOTE_RATE_HI = 300.0;
const CAST_MOTE_R_HI = 0.055;
/// Motes one frame may emit. The ramp needs an accumulator (a per-frame probability test tops out at ~60/s and
/// the ramp then does nothing), and the accumulator needs a ceiling or one hitch dumps the whole ring.
const CAST_MOTE_CAP = 8;
/// s. SHORT, because riding the tip's velocity (`gatherMotes`) cancels the tip's constant motion but not its
/// ACCELERATION, and the leftover smear is ½·a·life² — so the life is what pays, and it pays quadratically.
/// At 0.17 the gather was a violet contrail off the rod.
const CAST_MOTE_LIFE_LO = 0.030;
const CAST_MOTE_LIFE_HI = 0.055;
/// …and the radius is what buys that short life back, not the count: `drawParticles` fades radius WITH alpha,
/// so at 0.04 s a mote is legible on one frame of three and at 0.015 nine motes showed as three.
const CAST_MOTE_R0 = 0.023;
const CAST_MOTE_R1 = 0.011;
const CAST_SPARKS = 26; // the cone off the stone as it goes…
/// …and the COLLAR sideways out of it, which is what says the stone LET GO — the cone alone is
/// indistinguishable from the bolt's own first metre of flight.
const CAST_COLLAR = 12;
const CAST_COLLAR_SP = 4.4;
/// One bloom on the stone at the throw. SMALL: it is a solid sphere, not additive, so at 0.30 it rendered as a
/// translucent balloon hiding the stone, the claws, the cone and the collar all at once.
const CAST_FLASH_R = 0.095;
const CAST_FLASH_LIFE = 0.085;
const BOLT_BURST = 22; // …and the bigger one where it lands

// THE ROOTS — the rod's other sorcery. Dead wood out of the earth, and the ONE substance the spell adds: the
// chaos violet stays the light ON it and the motes around it, never a second violet thing (the brood's rule).
/// Sites the ground can be split at AT ONCE. A second cast before the first has sunk is a thing the player can
/// do, and two holes in the ground is what it should look like when he does.
const ROOT_SITES = 3;
/// Tendrils one site throws. Nine, and every one of them differently sized, leaned and DELAYED — a ring of
/// equal spikes going up on the same frame is the rosette-of-spokes failure, however good the mesh is.
const ROOT_FANS = 9;
const ROOT_RISE: f32 = 0.20; // s, TORN up out of the earth (fast: this is the violent half)…
const ROOT_SINK: f32 = 0.55; // …and drawn back down once the grip lets go
/// The stagger between the first tendril and the last, as a fraction of the rise.
const ROOT_LAG: f32 = 0.55;
/// …and how far the tear OVERSHOOTS its own height before settling back onto it. A mass thrown out of the
/// ground does not glide to a stop, and the settle is what reads as weight (the reactions law, on a prop).
const ROOT_PUNCH: f32 = 0.20;
/// Variants of the tendril mesh. One shape yaw-rotated nine times reads as a periodic pattern the moment you
/// stand still and look at it (the world's `bigtree` rule, at a tenth the scale).
const ROOT_KINDS = 3;
/// Enough that the curl reads as a CURVE and not a chain of straight sticks, over a shaft this long. The mesh is
/// built ONCE per variant, so the segment count costs nothing at run time — only the total arc has to come
/// down with it, since that is `curl` times the count (see `rootTendrilMesh`).
const ROOT_SEGS = 10;
/// ~1.05 m — HIP height on the 1.8 m rig, so the thing that has a foe by the feet is a mass you have to look
/// at rather than scenery round its ankles. Man-height (1.8) is the other failure: the tendrils then hide the
/// creature they are holding, which is the one thing this spell exists to show you.
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
const ROOT_SOIL = mathx.rgba(96, 78, 58, 190); // the earth it throws up
const ROOT_DUST = 34;
const ROOT_MOTES = 26;
/// Rise, then the GRIP'S OWN span, then the sink — so what is standing in the ground IS how long the foe in it
/// has left, rather than a second clock that can disagree with `combat.Root`.
const ROOT_LIFE: f32 = ROOT_RISE + combat.ROOT_HOLD + ROOT_SINK;
/// …and the SITE outlives that by the fan's own stagger, because every tendril's clock is set back by up to
/// `ROOT_RISE * ROOT_LAG` (see `drawRoots`). Cut at `ROOT_LIFE` the last of them is still an eighth of its
/// height when the site stops drawing, and a root sinks — it is never popped away.
const ROOT_SITE_LIFE: f32 = ROOT_LIFE + ROOT_RISE * ROOT_LAG;

/// One split in the ground: where, and how long ago. Whether the grip closed on anything is spent at the
/// eruption (it sizes the earth thrown up) and is not a property of what stands there afterwards.
const RootSite = struct {
    at: rl.Vector3 = mathx.zero3,
    t: f32 = mathx.LONG_AGO, // …so an untouched slot is already spent
    seed: f32 = 0,
};

const FX_N = 256;

comptime {
    // The ring overwrites its oldest silently, so the size is arithmetic over the constants above rather than
    // a taste — the failure it guards is a release burst eating the gather that is still on screen.
    const gather = CAST_MOTE_RATE_HI * CAST_MOTE_LIFE_HI;
    const release = CAST_SPARKS + CAST_COLLAR + 1;
    // …and the ROOTS' own burst, which shares this one pool and is thrown on the same frame a gather ends.
    const erupt = ROOT_DUST + ROOT_MOTES;
    // …and the shield's sparks, which the same pool carries: a parry cannot run WITH a cast, but its sparks
    // outlive the swap, so the two overlap in the ring however exclusive the actions are.
    const caught = PARRY_SPARKS + 1;
    const worst = gather + @as(f32, release + erupt + caught + 2 * BOLT_BURST); // two bolts can land across chained casts
    if (@as(f32, FX_N) < worst) @compileError(std.fmt.comptimePrint(
        "hero: FX_N = {d} but a cast can have {d} particles in the air — raise it",
        .{ FX_N, worst },
    ));
}

/// `CHAOS_MOTE` ITSELF, not a second literal that looks like it — one violet for the whole spell, and a
/// hand-transcribed shader vec3 holds that only as long as someone remembers to retune both.
const WAND_LIT = mathx.colVec(CHAOS_MOTE);
/// Radius matters more than brightness (the chapel's law), so the carry's ember is SHORT as well as dim: at a
/// torch's 6 m it washed him violet head to foot standing still.
const WAND_LIT_CARRY = 0.20;
const WAND_LIT_CARRY_R = 2.6;
const WAND_LIT_CHARGED = 1.00;
const WAND_LIT_CHARGED_R = 7.0;
const WAND_LIT_FLARE = 2.30;
const WAND_LIT_FLARE_R = 12.0;

// Blade hitbox, souls-style: a capsule on the SWORD bone's dummy points (guard → tip), ACTIVE only inside the HIT window, with last-frame endpoints kept for swept tests so a fast arc can't tunnel between frames.
/// HOW FAR THE WAIST WILL FOLD ONTO A MARK (deg, total across SPINE + CHEST).
pub const AIM_LEAN_DOWN = 34.0;
pub const AIM_LEAN_UP = 12.0;
/// …and how fast he gets there (deg/s).
const AIM_LEAN_RATE = 190.0;
const AIM_LEAN_BIAS = 7.0;

pub const BLADE_R = 0.34; // capsule radius (world units) — a FAT hit volume, far past the

const TRAIL_N = 20; // ring capacity (~0.3 s of samples at 60 fps)
const TRAIL_LIFE = 0.20; // seconds a sample persists (long enough that the full level arc
const TRAIL_ROOT = 0.35; // ribbon spans this fraction down the blade → the tip
const TRAIL_PEAK = 84.0;

pub const HP_MAX = statsmod.hpFor(statsmod.START); // 70 — VITALITY owns it (`stats.zig`); the balance anchor every foe's damage is measured against
pub const POISE_MAX = 55.0;
pub const STANCE_MAX = 90.0;
pub const ATK_LIGHT_HIT = combat.Hit{ .dmg = 13, .poise = 10 };
pub const ATK_HEAVY_HIT = combat.Hit{ .dmg = 27, .poise = 22, .stance = 14 };

pub fn freshVitals(sheet: statsmod.Sheet) combat.Vitals {
    return combat.Vitals.init(sheet.hp(), POISE_MAX, STANCE_MAX);
}

const HURT_LEAN = 40.0; // light flinch: torso snaps back this far (deg)
const HURT_HEAD = 52.0;
const HURT_STEP = 0.18 * H;
const STAG_LEAN = 42.0; // heavy stagger: a deep reeling arch back (deg)
const DEATH_SINK = 0.30; // death: pelvis sinks to this fraction of stance height
pub const DEATH_DUR = 3.6; // collapse + lie still before the hero respawns — long enough for

const GUARD_SH_FLEX = 24.0; // left shoulder forward of the body line (deg)…
const GUARD_SH_CROSS = 40.0;
const GUARD_SH_ABD = 2.0; // elbow tucked IN, near the ribs — a shield held out on a straight arm is a target
const GUARD_ELBOW = 96.0;
const GUARD_BLADE = 9.0; // trunk yaw toward the shield side (deg, PER SEGMENT over spine + chest)
const GUARD_CROUCH = 0.022 * H;
const GUARD_SWORD_BACK = 40.0; // the sword arm draws back and low, blade out of the shield's way…
const GUARD_SWORD_ELBOW = 46.0;
const GUARD_SWORD_WRIST = 30.0;
const GUARD_HEAD = 6.0; // chin tucked down behind the rim
const GUARD_BLEND_RATE = 11.0;
const BLOCK_RECOIL_DUR = 0.24; // seconds — over before the next swing, so blocking never costs tempo
const BLOCK_SHIELD_BACK = 15.0; // the arm retracts, taking the boards toward the chest (deg off the flex)
const BLOCK_SHIELD_FOLD = 10.0;
const BLOCK_TRUNK = 9.0;
const BLOCK_STEP = 0.14 * H;
const BLOCK_SINK = 0.048 * H;
const BLOCK_FLASH = 0.22; // a LICK of red, well under `takeHit`'s 0.35 for a blow that got through

// THE PARRY — L2, the shield's own skill, and one short committed shove of the boards with a catch window at
// the front of it. It does NOT ask whether the guard is up: blocking and parrying are the two things that one
// arm can do, not a move and its follow-up. At ER's own numbers a parry is a gamble made INSIDE an attack's
// tell, so the whole action has to be over before the blow you mistimed it on arrives; and because it is
// committed, `canGuard` refuses while it runs, so the block is off for its duration whether he was holding one
// or not. That tail is the risk, and it is why the window and the animation are two clocks.
pub const PARRY_DUR = 0.44;
/// It opens a HAIR late — the arm has to be visibly moving, which is `foe.TELL_MIN`'s rule turned on the
/// player — and shuts less than halfway through, so the recovery is honestly open.
const PARRY_OPEN = 0.04;
const PARRY_SHUT = 0.19;
/// Where the shove PEAKS as a fraction of the duration, kept INSIDE the window: the frame that catches has to
/// be the frame the boards are furthest out, or the pose and the mechanic are telling different stories.
pub const PARRY_PUNCH_AT = 0.30;
/// A MASS IN MOTION OVERSHOOTS ITS REST AND SETTLES BACK ONTO IT (owner's law) — three quarters of a turn, so
/// the arm comes back through its own rest and past it once before it settles.
const PARRY_REBOUND = 0.75;
/// THE THRUST, AND IT IS PAID FOR AT BOTH JOINTS. `shieldFit` is the INVERSE of the guard's arm fold
/// (`GUARD_ARM_FOLD` = shoulder flex + elbow), so the boards keep their facing only while that SUM does: opened
/// at the elbow alone, a shove of this size rotates the shield clean off its own arm and presents the player
/// with the end of his own forearm (measured, and it is the retune AGENTS.md's shieldFit law warns about). So
/// the shoulder takes +`PARRY_PUNCH` and the elbow gives back exactly as much — the fold is untouched, the
/// forearm keeps its direction, and what travels is the HAND: the upper arm's own length through twice this
/// angle, about 30 cm of boards driven at the blow.
const PARRY_PUNCH = 52.0;
/// …and the boards SQUARE UP onto the threat as they go, unwinding the guard's own cross rather than carrying
/// on past it. Swung FURTHER across at the SHOULDER (the first shape tried) they leave his chest bare and
/// arrive edge-on, which is a shield doing the one thing a shield must never do.
const PARRY_SWEEP = 26.0;
const PARRY_WRIST = 16.0; // deg of cant in the fist — a roll of the rim, kept small: the fold does the work
/// THE SWIPE, AND IT IS DRIVEN FROM THE WAIST. This is the whole reason the sweep is not at the shoulder: a
/// shoulder yaw big enough to carry the boards across his front turns their FACE with it, because `shieldFit`
/// is the inverse of exactly that yaw. The TRUNK turns the arm and the boards TOGETHER, so the shield stays
/// square to the direction it is travelling — which is what a bat-away is, and what a rim arriving edge-on is
/// not. Degrees PER SEGMENT over spine + chest at full follow-through.
const PARRY_TRUNK = 38.0;
/// …and the SHOULDER adds a little on top, so the boards outrun the chest carrying them (stagger the lags —
/// joints peaking on one frame read as a welded block). Small, because every degree of it turns the shield's
/// face as well as moving it: this is the axis `shieldFit` inverts, and 12 is about what the wrist cant beside
/// it is already worth.
const PARRY_ARM_LEAD = 12.0;
/// He COILS the other way first, then whips across, then settles back onto centre — three phases on their own
/// clock, staggered against the thrust's, because joints peaking on one frame read as a welded block.
pub const PARRY_COIL_AT = 0.13; // fraction of the action spent winding up…
/// …and where the arc has been fully crossed. SOLVED, not chosen: `smoothstep` is half way through at half its
/// span, so the boards cross CENTRE at `COIL_AT + (END - COIL_AT)/2` and this is the value that puts that
/// crossing exactly on `PARRY_PUNCH_AT` — the frame the thrust peaks, which is the frame that catches. At 0.58
/// the sweep was still a third of the way back on the coil when the blow arrived (measured, and the test that
/// pins the crossing is what found it).
pub const PARRY_SWEEP_END = 2.0 * PARRY_PUNCH_AT - PARRY_COIL_AT;
/// The share of the turn the PELVIS takes; the rest is waist. All of it at the root would rotate the legs and
/// read as a spin rather than a swipe.
const PARRY_PELVIS = 0.30;
const PARRY_PITCH = 6.0; // he leans INTO it, about the feet
const PARRY_LEAD = 0.055 * H; // …and steps into it
const PARRY_SINK = 0.020 * H;
const PARRY_SWORD_COCK = 14.0; // the sword hand draws a little further back: the riposte, loading
const PARRY_HEAD = 10.0;
/// STRUCK IRON — the one FX here lit like a spark, thrown along the boards' own normal so a catch reads off the
/// SHIELD and not off the hero holding it. They fall hard: hot metal has real weight in it.
///
/// SEPARATED ON HUE, not on value. The boards come back off this sun around 140 and a pale cream spark at 3 cm
/// read as a soft bubble sitting on them (measured, at 30 of them). HOT AMBER against pale tan reads at a
/// tenth the size, so the radius is what came down and the count with it.
const PARRY_SPARK = rgba(255, 206, 108, 240);
const PARRY_SPARK_HOT = rgba(255, 250, 232, 250);
const PARRY_SPARKS = 34;
/// AND THE FAN IS THE DOMINANT HALF OF THE THROW. Struck sparks do fly forward, but forward is DOWN THE LENS
/// here: at 0.42 of the forward speed most of them were still inside the disc's own outline four frames later
/// and read as dots painted on the boards (measured). What says "shower" is the ones crossing the RIM, so the
/// sideways throw has to outrun the one off the face — hence a fan bigger than the shield's radius in the first
/// three frames, and only enough forward to clear the boards.
const PARRY_SPARK_FAN = 9.0; // m/s, peak sideways off the boss…
const PARRY_SPARK_OUT_LO = 1.0; // …and off the face itself
const PARRY_SPARK_OUT_HI = 3.2;
const PARRY_SPARK_R0_LO = 0.009;
const PARRY_SPARK_R0_HI = 0.019;
const PARRY_SPARK_GRAV = 9.0;
/// One bloom on the boss, and SMALL for the cast flash's reason: it is a solid sphere, not additive, so a big
/// one is a balloon over the shield it exists to point at — measured at 0.085 it read as a puff of smoke sat on
/// the boards, because on the FIRST frame it and every spark are still at the same point.
const PARRY_FLASH_R = 0.05;
const PARRY_FLASH_LIFE = 0.06;

const SHIELD_R = 0.115 * H;
const SHIELD_THICK = 0.020 * H;
const SHIELD_WOOD = rgba(56, 41, 29, 255); // dark limewood boards…
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
/// The face's own normal, expressed in the WRIST's frame — which is where the standoff has to be measured, since the hand grips BEHIND the boss.
const SHIELD_N = v3(SH_CROSS_S, -SH_CROSS_C * SH_FOLD_S, SH_CROSS_C * SH_FOLD_C);
/// …and where the middle of the boards SITS in that frame, the hand gripping behind the boss.
const SHIELD_HUB = v3(
    SHIELD_STANDOFF * SHIELD_N.x,
    FIST_Y + SHIELD_STANDOFF * SHIELD_N.y,
    FIST_Z + SHIELD_STANDOFF * SHIELD_N.z,
);
/// MEASURED AND LEFT: every input here is a compile-time constant, so this rebuilds the same matrix twice a frame (the depth pass and the lit pass both go through `draw`).
fn shieldFit() rl.Matrix {
    return mul3(ry(GUARD_SH_CROSS), rx(GUARD_ARM_FOLD), tr(SHIELD_HUB.x, SHIELD_HUB.y, SHIELD_HUB.z));
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
const CARRY_ELBOW = 14.0; // readier standing/walking elbow on the sword side
const CARRY_ELBOW_RUN = 30.0; // at a run the carry arm keeps a readier bend (kept close to the body, not folded to the chest)
const CARRY_WRIST_LIFT = -54.0;
const CARRY_LIFT_WALK = 0.4;
const CARRY_ABD_RUN = 12.0;
const CARRY_WRIST_YAW = -48.0;
const CARRY_SWING_STILL = 0.6;

const POSE_XFADE = 0.09; // seconds — cross-fade over any pose discontinuity (roll start/end)
const SPEED_SMOOTH = 80.0; // units/s² — posture-blend speed chases ground speed, so

const GAIT_DIR_EASE = 22.0; // 1/s — fwdB/latB chase the body-frame travel direction
const STRAFE_ABD = 22.0; // peak frontal hip swing either side of the hip (deg) — the sweep is
const STRAFE_STANCE = 0.52; // fraction of the cycle each foot is planted (~4% double support)
// CADENCE HAS EXACTLY ONE DIAL: phase is driven by DISTANCE, so cadence = speed / STRAFE_CYCLE.
const STRAFE_CROSS = 38.0; // the crossing leg's hip FLEXION peak — it must pass IN FRONT of the stance
const STRAFE_BEHIND = 10.0;
const STRAFE_LAND = 7.0; // fore/aft hip offset at plant (deg), swept out linearly through stance
const STRAFE_CLEAR = 0.035 * H; // DAYLIGHT under the swing foot at mid-swing.
const STRAFE_SINK = 0.0055 * H; // how much SHORTER than dead-straight the leg is left at full
const STRAFE_PROT = 7.0; // pelvic TRANSVERSE rotation (deg): the crossing hip swings FORWARD to
const STRAFE_SWAY = 0.012 * H; // pelvis rides ONTO each planting foot (the weight transfer
const STRAFE_LEAN = 2.5; // torso banks gently INTO the travel side (deg, cosmetic)
const BACK_STRIDE = 0.85; // backpedal steps shorten a touch too (cautious, toe-reaching)

pub const LEG_LEN = (0.530 - 0.039) * H;
const STRAFE_REACH = LEG_LEN * @sin(mathx.radians(STRAFE_ABD)); // half the stance sweep, in units
const STRAFE_CYCLE = 2.0 * STRAFE_REACH / STRAFE_STANCE; // body travel per FULL cycle. advanceGait
pub const STRAFE_DIP = LEG_LEN - @sqrt((LEG_LEN - STRAFE_SINK) * (LEG_LEN - STRAFE_SINK) - STRAFE_REACH * STRAFE_REACH);

const STRIDE = 0.85 * H; // ground distance per full (two-step) cycle at walk pace — ties phase to travel, no foot-skate
const WALK_REF_SPEED = WALK_SPEED; // reference walk speed the stride is tuned for
const ARM_SWING = 9.0; // shoulder flex amplitude (deg) at walk — restrained, contralateral to the legs
pub const A_BOB = 0.024 * H;
const A_SWAY = 0.009 * H; // lateral pelvis sway toward the stance foot (subtle — no waddle)
const A_PROT = 3.5; // pelvic transverse rotation (deg)
const A_LIST = 2.0; // pelvic frontal drop toward the swing leg (deg)
const TORSO_LEAN = 3.0; // forward torso lean while walking (deg) — walking is near-upright
pub const HIP_ADDUCT = 2.0; // constant leg-toward-midline angle so the stance narrows (deg)
pub const FOOT_TOEOUT = 6.0; // feet splay slightly outward (Fick angle) — a real standing/gait detail
const ARM_ABD = 9.0; // constant arm abduction so arms clear the torso (deg)
pub const IDLE_KNEE = 4.0;
const SIT_Y = 0.115; // pelvis height in units of H — on the ground, not perched
const SIT_PITCH = 3.0;
const SIT_SPINE = 8.0; // he curls over the instrument from the waist up
const SIT_CHEST = 4.0;
const SIT_HIP_FLEX = 52.0; // a THIGH ON THE FLOOR, not a knee at the chest
const SIT_HIP_ABD = 62.0;
const SIT_KNEE = 118.0;
const SIT_ANKLE = 6.0;
const IDLE_ELBOW = 6.0;
const MOVING_EASE = 10.0; // idle—walk blend rate (1/s) — the `moving` fade in update(); fast, so gait answers the stick NOW

pub fn sampleCurve(tbl: [8]f32, phase: f32) f32 {
    const ph = phase - @floor(phase); // 0..1
    const t = ph * 8.0;
    const base: usize = @intFromFloat(@floor(t));
    const a = base % 8;
    const b = (base + 1) % 8;
    const f = t - @floor(t);
    return tbl[a] + (tbl[b] - tbl[a]) * f;
}

// Advance the shared humanoid GAIT STATE one frame — the single source of walk/strafe for the hero AND every humanoid enemy (AGENTS.md humanoid rule); eases the posture blends (`moving`, `speedS`) and body-frame travel direction (`fwdB`/`latB`, splitting sagittal walk from the strafe in legChain), and accumulates stride `phase` by DISTANCE (never time) so feet never skate.
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
        // Sagittal strides lengthen with speed; the SIDESTEP's cycle is FIXED at STRAFE_CYCLE, because legChain's stance sweep is measured in UNITS off the leg — scale one without the other and the planted foot skates again.
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

// The hero's own boot footprint, measured off `footMesh`: the sole cube spans z −0.05·H…+0.14·H and x ±0.0425·H, and its underside lands exactly on the ankle-height plane.
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

pub const Attack = enum { light, heavy };

pub const Arm = enum { sword, bow };

/// THE LEFT HAND'S ARMAMENT. The wand is the shield's ALTERNATIVE and not a third thing he carries: one
/// hand does one job, which is the same anatomy that takes the shield away behind a raised bow.
pub const Off = enum { shield, wand };

// One buffered action, ER-style: an attack/roll pressed while mid-action QUEUES here
pub const Queued = union(enum) { attack: Attack, roll: rl.Vector3 };

pub const Hero = struct {
    mesh: [N]rl.Mesh,
    bow: rl.Mesh,
    bowString: rl.Mesh,
    bowNock: rl.Mesh,
    /// THE SHIELD, which is not a bone.
    shield: rl.Mesh,
    /// …nor is THE WAND. Same route (the left wrist) but no fit matrix: it is authored IN that wrist's
    /// frame, so a retune of the cast angles cannot swing the rod off its own hand.
    wand: rl.Mesh,
    /// THE TENDRILS, authored rising out of the earth at the origin — the roots spell throws `ROOT_FANS` of
    /// them per site through a seeded transform, the way the world gets sixty trees out of three meshes. THREE
    /// of them for that same reason: one shape yaw-rotated seven times is a periodic pattern.
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
    /// HOW MANY ROLLS HE HAS TAKEN, ever — the same counter `swings` is, for the same reason: a chained roll clears `rolling` and sets it again inside ONE frame, so a rising edge on the flag misses every roll after the first.
    rolls: u32 = 0,
    rollT: f32 = 0, // seconds into the current roll
    rollDir: rl.Vector3 = mathx.zero3, // world XZ unit direction of the roll
    rollYaw: f32 = 0, // committed heading of the roll; the visible yaw eases onto it fast
    rollSide: f32 = -1, // +1 = over the LEFT shoulder, -1 = the RIGHT (picked from the leading leg)
    rollVar: f32 = 1, // this roll's imperfection magnitude (ROLL_VAR_LO..HI, cosmetic only)
    attacking: bool = false,
    atkT: f32 = 0, // seconds into the current swing
    queued: ?Queued = null, // the ER-style input buffer (see Queued)
    atkHeavy: bool = false,
    atkAlt: bool = false, // light-combo alternator: false = forehand slash, true = the RETURN backhand
    swings: u32 = 0,
    bladeA: rl.Vector3 = mathx.zero3, // blade capsule endpoints in WORLD space (guard → tip)
    bladeB: rl.Vector3 = mathx.zero3,
    bladeA0: rl.Vector3 = mathx.zero3,
    bladeB0: rl.Vector3 = mathx.zero3,
    hitWasActive: bool = false, // edge detector: sweep history (+ future hit list) resets on activation
    trail: foemod.Trail(TRAIL_N) = .{}, // the shared swing ribbon (foe.zig), which every blade in the game draws
    /// THE WAND'S OWN SPARKS — the shared particle pool (`foe.zig`), the same one every creature's FX ride.
    fx: [FX_N]foemod.Particle = [_]foemod.Particle{.{}} ** FX_N,
    fxHead: usize = 0,
    /// THE CHARACTER SHEET, and the source of the three maxima below — re-read wherever he is made whole (`makeWhole`), which is the only moment a sheet can have changed and the only moment a bar may resize.
    sheet: statsmod.Sheet = .{},
    vit: combat.Vitals = freshVitals(.{}),
    stam: combat.Stamina = .{}, // ER's third bar — the hero's alone; foes don't carry one
    fp: combat.Focus = .{},
    runes: combat.Runes = .{},
    flasks: combat.Flasks = .{}, // Crimson + Cerulean, sharing the quick-item slot
    /// …and the ARROWS, which are finite: an empty quiver refuses the shot (see `startShot`).
    quiver: combat.Quiver = .{},
    regen: combat.Regen = .{},
    drinking: bool = false,
    drinkT: f32 = 0,
    poured: bool = false,
    /// Seconds left on the "that was refused" flash.
    stamRefused: f32 = 0,
    sprinting: bool = false, // hold-B RUN, resolved by the caller — the only CONTINUOUS drain
    // Shaped like the GUARD, not like an attack: `aiming` is re-derived from the button every frame, and only the LOOSE is committed.
    /// HOW FAR HE IS FOLDED ONTO WHAT HE IS SWINGING AT (deg, + = down over a low mark, − = arched back under a high one), eased toward `aimLeanWant`.
    aimLean: f32 = 0,
    aimLeanWant: f32 = 0,
    arm: Arm = .sword,
    aiming: bool = false,
    aimB: f32 = 0,
    shooting: bool = false, // a committed loose is running
    shotT: f32 = 0,
    shotAimed: bool = false,
    /// WHICH ARROW THIS SHOT SPENT, latched when it was drawn rather than read at the loose: the shaft leaves a few frames later, and cycling the quiver in between must not change what is already on the string.
    shotArrow: combat.ArrowKind = .plain,
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
    off: Off = .shield,
    /// WHICH SORCERY THE ROD IS SET TO. NOT latched at `startCast` the way `shotArrow` is, and it does not
    /// need to be: `cycleSpell` refuses while a cast is running, so what starts is what throws.
    spell: combat.Spell = .bolt,
    /// A cast is running — COMMITTED, so it lives in `committed()` beside the swing and the loose.
    casting: bool = false,
    castT: f32 = 0,
    /// THE SWEEP ALTERNATOR, the light combo's `atkAlt` for the same reason: repeated casts must be a PAIR
    /// of strokes sweeping opposite ways, not one animation replayed. Flipped at the START of each cast, so
    /// it never depends on how the last one ended.
    castAlt: bool = false,
    /// Counted like `swings`/`shots`: a chained cast clears `casting` and sets it again inside one frame.
    casts: u32 = 0,
    /// ONE FRAME, the frame the bolt leaves — game.zig throws it from `wandTipWorld()`.
    thrown: bool = false,
    /// WHERE THE GROUND IS SPLIT, and for how much longer — a ring, so a second cast before the first has sunk
    /// leaves two holes in the ground rather than teleporting the first one.
    rootSites: [ROOT_SITES]RootSite = [_]RootSite{.{}} ** ROOT_SITES,
    rootHead: usize = 0,
    /// Fractional motes the gather owes, carried between frames so a ramped rate is honest at any frame time.
    moteAcc: f32 = 0,
    /// Last frame's stone, differenced in `gatherMotes` for the tip's velocity. Written and read only there.
    tipPrev: rl.Vector3 = mathx.zero3,
    /// Seconds left on the "there was not enough FP for that" flash, the stamina refusal's twin on the
    /// other bar. Its own field because flashing the stamina frame for a dry FP pool would point at the
    /// wrong meter, and the player reads the ring to learn WHICH resource said no.
    fpRefused: f32 = 0,
    guarding: bool = false,
    guardB: f32 = 0,
    /// Seconds since the last blow caught on the shield — the recoil clock, and the ONLY record a block leaves.
    /// A PARRY LANDING STAMPS IT TOO: a caught blow is driven into the body exactly as a blocked one is (THE MAN
    /// MOVES, THE SHIELD HOLDS), and a second clock alongside it could only ever disagree with this one.
    blockT: f32 = mathx.LONG_AGO,
    /// L2, THE SHIELD'S OWN SKILL — a COMMITTED window, unlike the held guard it shares an arm with, so it sits
    /// in `committed()` beside the swing and the cast, is never buffered, and takes any block off him while it
    /// runs.
    parrying: bool = false,
    parryT: f32 = 0,
    /// Counted like `swings`/`casts`: the game reads the EDGE for the shove's own effort, and a chained parry
    /// clears `parrying` and sets it again inside one frame.
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
        var mat = rl.loadMaterialDefault() catch @panic("hero material");
        mat.shader = shader;
        return .{
            .mesh = buildMeshes(),
            .bow = archer.bowMesh(),
            .bowString = archer.stringMesh(),
            .bowNock = archer.nockArrowMesh(),
            .shield = shieldMesh(),
            .wand = wandMesh(),
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
        self.attacking = false;
        self.rolling = false;
        self.drinking = false;
        self.casting = false;
        self.queued = null;
        self.sprinting = false;
        self.guarding = false;
        self.guardB = 0;
        self.parrying = false;
        self.dropAim();
        self.stun = .none;
        self.hurtFlash = 0;
        self.makeWhole(); // the same restoration a respawn makes
    }

    /// WHOLE AGAIN — a grace, and a death is a return to one. The three bars take their SIZE from the sheet here and nowhere else, so a raised attribute cannot leave one at its old length.
    fn makeWhole(self: *Hero) void {
        const res = self.vit.res; // …but NOT his resistances: those are what he IS, not a meter to refill
        self.vit = freshVitals(self.sheet);
        self.vit.res = res;
        self.stam.max = self.sheet.stamina();
        self.fp.max = self.sheet.fp();
        self.stam.reset();
        self.fp.reset();
        self.regen.reset();
        // FLASKS REFILL AT THE GRACE, and a death IS a return to one — same event, same rule as ER.
        self.flasks.refill();
        self.quiver.refill();
    }

    fn tickClocks(self: *Hero, dt: f32) void {
        // The one-frame loose flag is cleared HERE, not in `updateShot`: a frame long enough to cross both the release knot and the end of the shot sets it and drops `shooting` in the same call, and nothing would ever run `updateShot` again to clear it — so game.zig loosed a fresh shaft every frame after. Every advance path passes through this prologue.
        self.loosed = false;
        self.thrown = false; // the cast's own one-frame edge, cleared here for the reason `loosed` is
        self.elapsed += dt;
        self.trail.age(dt);
        self.blendT = @min(self.blendT + dt, mathx.LONG_AGO);
        // Stamina belongs in the prologue for the same reason the others do: it must advance exactly ONCE per frame whichever path is running, and hanging it off the live loop instead would leave --shot draining every swing it takes and never refilling.
        // The cast is in the PAUSE list beside the swing and the roll: a committed action does not refill the
        // bar under itself. It is not in the DRAIN argument, because a cast bills FP and never stamina.
        if (!self.held) self.stam.tick(dt, self.sprinting, self.attacking or self.rolling or self.guarding or self.casting or self.parrying);
        self.stamRefused = @max(0, self.stamRefused - dt);
        self.fpRefused = @max(0, self.fpRefused - dt);
        // The stance blend and the recoil clock, in the prologue with the rest: exactly one advance path runs each frame and both have to move under all of them, or the shield hangs mid-raise through a stagger and the recoil freezes on whatever frame the block landed.
        // The PARRY holds the stance blend up as the held guard does: the boards are still up, they are being
        // SHOVED at something. Without it the shield visibly sinks through a window it is the whole point of.
        self.guardB = mathx.approach(self.guardB, if (self.guarding or self.parrying) 1.0 else 0.0, dt * GUARD_BLEND_RATE);
        self.aimB = mathx.approach(self.aimB, if (self.aiming) 1.0 else 0.0, dt * BOW_BLEND_RATE);
        self.aimLean = mathx.approach(self.aimLean, self.aimLeanWant, dt * AIM_LEAN_RATE);
        self.blockT = @min(self.blockT + dt, mathx.LONG_AGO);
        self.runes.tick(dt);
        // In the prologue with the other clocks, for the other clocks' reason: exactly one advance path runs
        // each frame, and sparks that only aged inside `updateCast` would hang in the air after the cast.
        foemod.tickParticles(&self.fx, dt, self.pos.y);
        // …and the splits in the ground, in the prologue for the particles' reason: aged only inside
        // `updateCast` they would freeze at whatever the cast ended on and stand there for good.
        for (&self.rootSites) |*s| s.t = @min(s.t + dt, mathx.LONG_AGO);
    }

    pub fn update(self: *Hero, dt: f32, movedDist: f32, speed: f32, moveYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = speed;
        advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist, speed, moveYaw, self.facing);
    }

    pub fn startRoll(self: *Hero, dir: rl.Vector3) void {
        if (self.committed()) return;
        if (!self.stam.canAct()) {
            self.refuse();
            return;
        }
        self.stam.spend(combat.STAM_ROLL);
        var d = v3(dir.x, 0, dir.z);
        if (mathx.lenXZ(d) < 0.1) d = mathx.headingDir(self.facing);
        d = mathx.normV(d);
        self.rolling = true;
        self.rolls +%= 1; // every roll, chained ones included — see the field
        self.rollT = 0;
        self.rollDir = d;
        self.rollYaw = mathx.headingXZ(d); // heading committed NOW; the visible yaw whips onto it
        const leadL = sampleCurve(HIP_FLEX, self.phase) > sampleCurve(HIP_FLEX, self.phase + 0.5);
        self.rollSide = if (self.moving > 0.5 and leadL) 1.0 else -1.0;
        // elapsed in the mix so standstill rolls (frozen phase) still vary roll to roll.
        const h = (self.phase + self.elapsed * 0.61) * 7.31;
        self.rollVar = mathx.lerpF(ROLL_VAR_LO, ROLL_VAR_HI, h - @floor(h));
        self.startXfade(); // last frame's pose cross-fades into the dive — no snap
    }

    pub fn updateRoll(self: *Hero, dt: f32, bounds: f32) void {
        self.tickClocks(dt);
        self.facing = mathx.approachAngle(self.facing, self.rollYaw, dt * ROLL_YAW_RATE); // whip, don't teleport
        const u = mathx.clampF(self.rollT / ROLL_DUR, 0, 1);
        const peak = ROLL_DIST / (ROLL_DUR * 0.5 * (ROLL_BRAKE_A + ROLL_BRAKE_B));
        const speed = peak * (1.0 - mathx.smoothstep(ROLL_BRAKE_A, ROLL_BRAKE_B, u));
        const moved = speed * dt;
        mathx.stepXZ(&self.pos, self.rollDir, moved, bounds);
        self.speed = speed;
        self.speedS = mathx.approach(self.speedS, speed, dt * SPEED_SMOOTH);
        self.rollT += dt;
        // Pose BEFORE clearing `rolling`: on the frame the roll completes, poseRoll (with u clamped to 1 = a fully-risen stand) must still run, else pose() falls to the walk branch and pops a stale-phase stance for one frame.
        self.pose();
        if (self.rollT >= ROLL_DUR) {
            self.rolling = false;
            self.startXfade(); // the rise cross-fades into whatever comes next
            self.fireQueued(); // a buffered attack/roll chains straight off the rise
        }
    }


    pub fn committed(self: *const Hero) bool {
        return self.rolling or self.attacking or self.drinking or self.shooting or self.casting or self.parrying;
    }

    pub fn bowOut(self: *const Hero) bool {
        return self.arm == .bow;
    }

    /// IS THE LEFT-HAND ARMAMENT ACTUALLY IN HIS HAND? Not the same question as which one is EQUIPPED: a
    /// raised bow takes that hand to the string, and one hand cannot haul a string while holding boards or
    /// a rod. Asked here rather than cleared on the swap, so the answer cannot go stale (the guard's rule).
    pub fn offInHand(self: *const Hero) bool {
        return self.arm != .bow;
    }

    pub fn wandOut(self: *const Hero) bool {
        return self.off == .wand and self.offInHand();
    }

    /// D-pad LEFT — ER's own binding for the left-hand slot, and the right hand's `swapArm` from the other
    /// side. Nothing is cleared: `canGuard` and `canCast` both ASK what is in the hand every frame.
    pub fn swapOff(self: *Hero) bool {
        if (self.committed() or self.staggered() or self.dead or self.resting) return false;
        self.off = if (self.off == .wand) .shield else .wand;
        self.startXfade();
        return true;
    }

    /// D-pad Right.
    pub fn swapArm(self: *Hero) bool {
        if (self.committed() or self.staggered() or self.dead or self.resting) return false;
        self.arm = if (self.arm == .bow) .sword else .bow;
        self.drawAmt = 0; // the string goes home whichever way the swap went
        self.startXfade();
        return true;
    }

    /// L2, HELD — called EVERY frame with the button's level, re-deriving the stance from scratch.
    pub fn setAim(self: *Hero, want: bool) void {
        self.aiming = want and self.canAim();
    }

    /// WHAT HE IS SWINGING AT, in degrees off his own eye line (+ = below him).
    pub fn aimAtPitch(self: *Hero, deg: ?f32) void {
        self.aimLeanWant = mathx.clampF(AIM_LEAN_BIAS + (deg orelse 0), -AIM_LEAN_UP, AIM_LEAN_DOWN);
    }

    /// Everything the bow was doing, down — but never the ARM.
    fn dropAim(self: *Hero) void {
        self.aiming = false;
        self.aimB = 0;
        self.shooting = false;
        self.loosed = false;
        self.drawAmt = 0;
        self.nockVis = false;
    }

    /// `shooting` is the ONE committed action this allows: a loose out of a held aim must not cost the aim, or the second shot of a pair is a different action from the first.
    pub fn canAim(self: *const Hero) bool {
        return self.bowOut() and !self.rolling and !self.attacking and !self.drinking and
            !self.staggered() and !self.dead and !self.sprinting and self.stam.canAct();
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
        self.stam.spend(if (aimed) combat.STAM_AIMED else combat.STAM_SHOT);
        self.shooting = true;
        self.shotAimed = aimed;
        self.shotT = 0;
        self.loosed = false;
        self.shots +%= 1; // every shaft, chained ones included — see the field
        self.startXfade();
    }

    /// Call in place of move/attack while `shooting`.
    pub fn updateShot(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt); // clears `loosed`
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        const dur: f32 = if (self.shotAimed) BOW_SHOT_DUR else BOW_QUICK_DUR;
        const at: f32 = if (self.shotAimed) BOW_SHOT_AT else BOW_QUICK_AT;
        const was = self.shotT / dur;
        self.shotT += dt;
        // A one-frame EDGE: a long frame cannot fire twice, a short one cannot miss the knot.
        if (was < at and self.shotT / dur >= at) self.loosed = true;
        self.pose();
        if (self.shotT >= dur) {
            self.shooting = false;
            self.startXfade();
            self.fireQueued(); // anything buffered during the loose leaves the moment it ends
        }
    }

    /// WHERE THE SHAFT LEAVES — the live string's own nock, not the fist (see `archer.poseBow`).
    pub fn nockWorld(self: *const Hero) rl.Vector3 {
        return self.lastNock;
    }

    fn bowLevels(self: *const Hero) struct { up: f32, pull: f32 } {
        if (!self.bowOut()) return .{ .up = 0, .pull = 0 };
        if (self.shooting) {
            const dur: f32 = if (self.shotAimed) BOW_SHOT_DUR else BOW_QUICK_DUR;
            const at: f32 = if (self.shotAimed) BOW_SHOT_AT else BOW_QUICK_AT;
            const u = mathx.clampF(self.shotT / dur, 0, 1);
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

    /// IS THE SHIELD ARM FREE TO DO ANYTHING AT ALL — everything the guard asks BAR the stamina, because that
    /// is the one clause the parry answers differently: an empty bar leaves the shield quietly down, where a
    /// parry the player pressed for has to say NO out loud (`hero.stamRefused` → the red ring).
    fn shieldArm(self: *const Hero) bool {
        return self.arm == .sword and self.off == .shield and !self.committed() and !self.staggered() and !self.dead and !self.sprinting;
    }

    /// AN EMPTY BAR CANNOT HOLD A SHIELD UP — and neither can a hand with a wand in it. The wand clause is
    /// the same ANATOMY the bow clause is, asked of the other slot: there is one left hand.
    pub fn canGuard(self: *const Hero) bool {
        return self.shieldArm() and self.stam.canAct();
    }

    /// L2 WITH BOARDS IN THE HAND — and it asks nothing about whether they are RAISED. The shield's skill is not
    /// a follow-up to blocking, it is the other thing you can do with the same arm, so the question is exactly
    /// the guard's own: is that arm free, and is there anything in the bar. Answering it through `canGuard`
    /// rather than restating it is what stops the two drifting apart.
    pub fn canParry(self: *const Hero) bool {
        return self.canGuard();
    }

    /// PRESSED, and NEVER BUFFERED (the loose's rule, and the cast's): a parry is a window the player picked a
    /// moment for, and one fired out of the input queue would open it at a moment he did not. Reports whether
    /// one actually started, so the caller's tell cannot sound for a shove the bar refused.
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
        self.parries +%= 1; // every shove, chained ones included — see the field
        // …and if he WAS blocking, that block is off for the window's duration: one arm, one job. Written here
        // as well as re-derived by `canGuard` because a parry can be started without going through `setGuard`.
        self.guarding = false;
        self.startXfade();
        return true;
    }

    /// Call in place of move/attack while `parrying`. PLANTED, like the cast and the quick shot: catching a
    /// blow is something you stand still and do.
    pub fn updateParry(self: *Hero, dt: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        if (faceYaw) |ty| self.facing = mathx.approachAngle(self.facing, ty, TURN_TO_SHOT * dt);
        self.parryT += dt;
        // Pose BEFORE clearing `parrying` — the roll's one-frame contract.
        self.pose();
        if (self.parryT >= PARRY_DUR) {
            self.parrying = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    /// THE FRAMES THAT ACTUALLY CATCH. Its own predicate rather than a span read off the pose, because the
    /// mechanic and the animation are not one clock: the shove keeps playing for a third of a second after the
    /// window has shut, and that tail is the risk the parry is priced on.
    pub fn parryLive(self: *const Hero) bool {
        return self.parrying and self.parryT >= PARRY_OPEN and self.parryT < PARRY_SHUT;
    }

    /// A BLOW CAUGHT. NO stamina, no chip, no flinch: refusing one outright is what the window was for, and it
    /// was paid for at the press. What it leaves is the shield's own recoil clock — `blockHit`'s, so a catch
    /// drives into the body exactly as a block does — and the sparks that say iron, not wood on flesh.
    pub fn noteParry(self: *Hero) void {
        self.blockT = 0;
        self.parrySparks();
    }

    /// THE MIDDLE OF THE BOARDS AND THE WAY THEY FACE, in world space — MEASURED off the fit matrix's own
    /// constants (the ogre's `clubLowWorld` law) rather than transcribed, so re-hanging the shield keeps the
    /// sparks on its face instead of in the air beside it.
    pub fn shieldFaceWorld(self: *const Hero) struct { at: rl.Vector3, n: rl.Vector3 } {
        const at = rl.math.vector3Transform(SHIELD_HUB, self.xf[WRL]);
        const out = rl.math.vector3Transform(mathx.addV(SHIELD_HUB, SHIELD_N), self.xf[WRL]);
        return .{ .at = at, .n = mathx.normV(mathx.subV(out, at)) };
    }

    /// A FAN OF STRUCK IRON OFF THE BOSS, thrown about the boards' own normal — the collar's construction in
    /// `castSparks`, for its reason: a spray built on world axes reads as a puddle round his hand the moment
    /// the shield is not square to the camera.
    fn parrySparks(self: *Hero) void {
        const f = self.shieldFaceWorld();
        var side = mathx.perpXZ(f.n);
        if (mathx.lenV(side) < 1e-3) side = v3(1, 0, 0); // boards facing straight up or down have no perp
        side = mathx.normV(side);
        const up = mathx.normV(mathx.crossV(f.n, side));
        // A hair PROUD of the face, or the first frame's sparks are half-buried in the boards they came off.
        const at = mathx.addV(f.at, mathx.scaleV(f.n, 0.02));
        var rng = foemod.fxStream(@floatFromInt(self.parries), 733.0, 0x8B04);
        var i: u32 = 0;
        while (i < PARRY_SPARKS) : (i += 1) {
            const a = rng.angle();
            const fan = rng.range(0.35, 1.0) * PARRY_SPARK_FAN;
            const v = mathx.addV(
                mathx.scaleV(f.n, rng.range(PARRY_SPARK_OUT_LO, PARRY_SPARK_OUT_HI)),
                mathx.addV(mathx.scaleV(side, mathx.cosf(a) * fan), mathx.scaleV(up, mathx.sinf(a) * fan)),
            );
            // A WIDE SPREAD OF LIVES, not one: struck iron throws a few that die instantly and a few that arc
            // right down to the grass, and it is the long ones that make the shower read as a shower rather
            // than as one frame of confetti.
            foemod.emitParticle(&self.fx, &self.fxHead, at, v, rng.range(0.16, 0.72), rng.range(PARRY_SPARK_R0_LO, PARRY_SPARK_R0_HI), 0.003, if (rng.float() < 0.45) PARRY_SPARK_HOT else PARRY_SPARK, PARRY_SPARK_GRAV);
        }
        // The bloom DRIFTS off the boards rather than sitting on them, or it reads as a sphere switched on.
        foemod.emitParticle(&self.fx, &self.fxHead, at, mathx.scaleV(f.n, 0.8), PARRY_FLASH_LIFE, PARRY_FLASH_R, PARRY_FLASH_R * 0.25, PARRY_SPARK_HOT, 0);
    }

    /// L1 with a wand in the left hand — the guard's own button, routed by what that hand is holding.
    /// STAMINA IS NOT ASKED: a cast is billed in FP alone (owner's call), so an empty stamina bar still
    /// leaves him a spell, which is the whole point of the pool being a second resource.
    pub fn canCast(self: *const Hero) bool {
        return self.wandOut() and !self.committed() and !self.staggered() and !self.dead and
            !self.resting and !self.sprinting;
    }

    /// L1, PRESSED — a cast is committed, so unlike the guard this is an edge and not a level. Reports
    /// whether one actually STARTED, so the caller's tell cannot sound for a cast the FP refused.
    pub fn requestCast(self: *Hero) bool {
        if (!self.canCast()) return false;
        return self.startCast();
    }

    /// WHAT THE ROD WOULD BILL FOR THE SPELL IT IS SET TO — the HUD's "could he?" and the cast itself both
    /// ask this, so a dearer second spell cannot light the slot it is too expensive to cast.
    pub fn castCost(self: *const Hero) f32 {
        return combat.spellFp(self.spell);
    }

    /// D-pad Up — WHICH SORCERY IS SET. Refused mid-cast for the reason `shotArrow` is latched: the FP for the
    /// one already running is spent, and swapping under it would throw a spell he did not pay for.
    pub fn cycleSpell(self: *Hero) bool {
        if (self.dead or self.casting) return false;
        self.spell = switch (self.spell) {
            .bolt => .roots,
            .roots => .bolt,
        };
        return true;
    }

    fn startCast(self: *Hero) bool {
        // PAY OR CAST NOTHING (`combat.Focus.spend`) — and the refusal lights the FP bar, not the stamina
        // one: a ring on the wrong meter tells the player to go and rest when what he needs is a Cerulean.
        if (!self.fp.spend(self.castCost())) {
            self.refuseFp();
            return false;
        }
        self.casting = true;
        self.castT = 0;
        self.thrown = false;
        self.moteAcc = 0;
        self.castAlt = !self.castAlt; // …so the next one sweeps back the other way
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
        self.castT += dt;
        // A one-frame EDGE, `updateShot`'s: a long frame cannot throw twice, a short one cannot miss it.
        if (was < CAST_AT and self.castT / CAST_DUR >= CAST_AT) self.thrown = true;
        self.pose();
        // AFTER the pose: the gather emits at the posed stone, so earlier draws this frame's motes onto last
        // frame's wand.
        if (self.castT / CAST_DUR < CAST_AT) self.gatherMotes(dt);
        if (self.castT >= CAST_DUR) {
            self.casting = false;
            self.startXfade();
            self.fireQueued();
        }
    }

    /// How far through the current cast, 0..1 (0 when there is none).
    fn castU(self: *const Hero) f32 {
        if (!self.casting) return 0;
        return mathx.clampF(self.castT / CAST_DUR, 0, 1);
    }

    /// 0..1 across the raise, and 0 EITHER SIDE of it — past the throw as well as before the cast, so a caller
    /// pulsing on it (`rumble.castCharge`) stops of its own accord when the stone lets go.
    pub fn chargeFill(self: *const Hero) f32 {
        if (!self.casting or self.castT / CAST_DUR >= CAST_AT) return 0;
        return mathx.clampF(self.castT / (CAST_DUR * CAST_AT), 0, 1);
    }

    /// Where the bolt leaves, off the posed left wrist. MEASURED from the mesh's own constants (the ogre's
    /// `clubLowWorld` law), so re-shaping the wand keeps the bolt on its tip.
    pub fn wandTipWorld(self: *const Hero) rl.Vector3 {
        return rl.math.vector3Transform(wandAt(WAND_TIP_T), self.xf[WRL]);
    }

    pub fn castBlow(_: *const Hero) combat.Hit {
        return combat.BOLT_HIT;
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
        if (self.committed()) return;
        const cost: f32 = if (kind == .heavy) combat.STAM_HEAVY else combat.STAM_LIGHT;
        if (!self.stam.canAct()) {
            self.refuse();
            return;
        }
        self.stam.spend(cost);
        self.attacking = true;
        self.swings +%= 1; // every cut, including a chained one — see the field
        self.atkHeavy = kind == .heavy;
        self.atkAlt = false; // a fresh light is always the forehand; chaining flips it (see updateAttack)
        self.atkT = 0;
        self.startXfade(); // whatever pose we were in cross-fades into the windup
    }

    pub fn updateAttack(self: *Hero, dt: f32, bounds: f32, faceYaw: ?f32) void {
        self.tickClocks(dt);
        const dur: f32 = if (self.atkHeavy) ATK_HEAVY_DUR else ATK_LIGHT_DUR;
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
            self.fireQueued(); // start* runs its own cross-fade out of this pose
            self.alternateChain(wasLight, wasAlt);
            self.pose(); // first frame of the new action (windup or dive)
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
            self.fireQueued(); // anything still buffered leaves the gate instantly
            self.alternateChain(wasLight, wasAlt); // late-buffered lights still alternate
        }
    }

    fn alternateChain(self: *Hero, wasLight: bool, wasAlt: bool) void {
        if (self.attacking and !self.atkHeavy and wasLight) self.atkAlt = !wasAlt;
    }


    /// Swap which flask is up (D-pad down).
    pub fn cycleFlask(self: *Hero) void {
        if (self.dead or self.drinking) return;
        self.flasks.cycle();
    }

    /// WHICH ARROW IS NOCKED NEXT. Refused mid-loose for the reason `shotArrow` exists — and it does not need the bow to be out, because choosing your ammunition is not an action.
    pub fn cycleArrow(self: *Hero) bool {
        if (self.dead or self.shooting) return false;
        self.quiver.cycle();
        return true;
    }

    pub fn shotBlow(self: *const Hero) combat.Hit {
        return arrowBlow(self.shotArrow, self.shotAimed);
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

    /// THE DRAUGHT'S OWN CLOCK, and nothing else — the caller still MOVES him (`DRINK_SPEED`) and poses
    /// him, because he walks through a draught now and the gait owns the legs. Do not tick the shared
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
            self.fireQueued(); // anything buffered during the draught leaves the moment it ends
        }
    }

    /// HOW FAR THE FLASK IS UP AND HOW FAR IT IS TIPPED, 0 unless he is drinking — `bowLevels`' twin, so
    /// the gait can read the draught's shape without knowing its clock.
    fn drinkLevels(self: *const Hero) struct { lift: f32, tip: f32 } {
        if (!self.drinking) return .{ .lift = 0, .tip = 0 };
        const u = mathx.clampF(self.drinkT / combat.FLASK_DRINK_DUR, 0, 1);
        // Up fast, HOLD at the mouth through the pour, down slower — a flask is emptied, not waved.
        return .{ .lift = mathx.pulse(u, 0, 0.26, 0.72, 1.0), .tip = mathx.pulse(u, 0.22, 0.46, 0.66, 0.92) };
    }

    // TAE-events equivalent: the blade only HITS inside the strike's active window.
    pub fn hitActive(self: *const Hero) bool {
        if (!self.attacking) return false;
        const dur: f32 = if (self.atkHeavy) ATK_HEAVY_DUR else ATK_LIGHT_DUR;
        const u = self.atkT / dur;
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

    /// The gather is the TELL (the sling's rule). Emitted from `updateCast` rather than the pose, because a pose
    /// also runs in the shot harness and under the menu.
    fn gatherMotes(self: *Hero, dt: f32) void {
        const at = self.wandTipWorld();
        // Each mote is solved to ARRIVE at the stone, and the stone crosses ~5 m/s through the lift — so without
        // the tip's own velocity they converge on where it WAS, a clump of violet hanging off the rod.
        // Skipped on the first gather frame: `startCast` cannot prime `tipPrev`, since it runs off an input edge
        // and `xf` is `undefined` until `pose` has run once. There, `castT` is exactly this call's `dt`.
        const tipV = if (self.castT > dt and dt > 0)
            mathx.scaleV(mathx.subV(at, self.tipPrev), 1.0 / dt)
        else
            mathx.zero3;
        self.tipPrev = at;
        // Squared on the rate: the ramp belongs at the END of the raise, or it reads as one steady stream.
        const fill = self.chargeFill();
        self.moteAcc += dt * mathx.lerpF(CAST_MOTE_RATE, CAST_MOTE_RATE_HI, fill * fill);
        const shell = mathx.lerpF(CAST_MOTE_R, CAST_MOTE_R_HI, fill);
        var rng = foemod.fxStream(self.castT + @as(f32, @floatFromInt(self.casts)), 977.0, 0x8B01);
        var n: u32 = 0;
        while (self.moteAcc >= 1.0 and n < CAST_MOTE_CAP) : (n += 1) {
            self.moteAcc -= 1.0;
            const a = rng.angle();
            const el = rng.range(-0.5, 1.0);
            const rr = rng.range(shell * 0.5, shell);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + el * rr, at.z + mathx.sinf(a) * rr);
            // …and its velocity points BACK at the stone, which is what makes it a gather and not a spray. NO
            // gravity either way: it is being pulled in, and a float term left it drifting after it arrived.
            const life = rng.range(CAST_MOTE_LIFE_LO, CAST_MOTE_LIFE_HI);
            const v = mathx.addV(mathx.scaleV(mathx.subV(at, from), 1.0 / life), tipV);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, life, CAST_MOTE_R0, CAST_MOTE_R1, CHAOS_MOTE, 0);
        }
        if (n == CAST_MOTE_CAP) self.moteAcc = 0; // the frame was long enough to be a hitch: drop the arrears
    }

    /// The release: a cone down the bolt line, a collar sideways out of it, one flash on the stone.
    pub fn castSparks(self: *Hero, dir: rl.Vector3) void {
        const at = self.wandTipWorld();
        // The collar's plane is the BOLT LINE's perpendicular pair, not world axes — cast uphill it has to stand
        // square to the shaft or it reads as a puddle round his hand.
        var side = mathx.perpXZ(dir);
        if (mathx.lenV(side) < 1e-3) side = v3(1, 0, 0); // a bolt straight up or down has no horizontal perp
        side = mathx.normV(side);
        const up = mathx.normV(mathx.crossV(dir, side));
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

    /// The stone, wherever the left wrist has it — the one light in the game that MOVES. `env.uploadLights`
    /// takes it as a RESERVED slot so a torch he stands beside can never evict his own spell.
    pub fn wandLight(self: *const Hero) ?gfx.Light {
        if (!self.wandOut() or self.resting) return null; // at a grace the rod is stowed for the guitar
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

    /// THE GROUND SPLITTING. `bit` is whether the grip closed on anything: it does not change WHAT erupts,
    /// only how much of the earth goes up with it.
    pub fn rootsBurst(self: *Hero, at: rl.Vector3, bit: bool) void {
        self.rootHead = (self.rootHead + 1) % ROOT_SITES;
        self.rootSites[self.rootHead] = .{ .at = at, .t = 0, .seed = @floatFromInt(self.casts) };
        var rng = foemod.fxStream(@floatFromInt(self.casts), 331.0, 0x8B04);
        // The EARTH first — thrown out and up, and it falls back, which is what says something came THROUGH it.
        const dust: u32 = if (bit) ROOT_DUST else ROOT_DUST / 2;
        var i: u32 = 0;
        while (i < dust) : (i += 1) {
            const a = rng.angle();
            const rr = rng.range(0.1, combat.ROOT_R * 0.8);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + 0.03, at.z + mathx.sinf(a) * rr);
            const sp = rng.range(1.1, 3.0);
            const v = v3(mathx.cosf(a) * sp, rng.range(2.4, 5.4), mathx.sinf(a) * sp);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, rng.range(0.38, 0.78), rng.range(0.045, 0.100), 0.014, ROOT_SOIL, 7.0);
        }
        // …then the element, which is the only thing here that says WHOSE roots these are. They FLOAT off the
        // wood (a negative grav) rather than arcing like the dirt does — chaos coming off it, not more earth.
        var j: u32 = 0;
        while (j < ROOT_MOTES) : (j += 1) {
            const a = rng.angle();
            const rr = rng.range(0.2, combat.ROOT_R);
            const from = v3(at.x + mathx.cosf(a) * rr, at.y + rng.range(0.05, 0.6), at.z + mathx.sinf(a) * rr);
            const v = v3(rng.signed() * 0.9, rng.range(0.8, 2.4), rng.signed() * 0.9);
            foemod.emitParticle(&self.fx, &self.fxHead, from, v, rng.range(0.45, 1.00), rng.range(0.038, 0.072), 0.010, if (rng.float() < 0.4) CHAOS_HOT else CHAOS_MOTE, -0.6);
        }
    }

    /// THE TENDRILS, standing where the ground was split. ONE mesh thrown `ROOT_FANS` times per site through a
    /// seeded yaw / offset / scale / lean, each on its OWN delay — the stagger is what stops seven of them
    /// reading as one welded object coming up on a single frame (the rig's lag law, applied to a prop).
    pub fn drawRoots(self: *const Hero) void {
        for (self.rootSites) |s| {
            if (s.t >= ROOT_SITE_LIFE) continue;
            var rng = foemod.fxStream(s.seed + 1.0, 613.0, 0x8B05);
            for (0..ROOT_FANS) |k| {
                // Drawn from the stream FIRST and unconditionally, so a tendril that is not up yet still
                // advances it and the fan does not reshuffle itself as the site rises.
                const jitter = rng.range(-0.34, 0.34);
                // Out to two thirds of the grab radius, so the ring reads across the ground the spell actually
                // took rather than as a clump about the mark.
                const out = rng.range(0.22, combat.ROOT_R * 0.66);
                const sc = rng.range(0.62, 1.46); // WIDE: nine of one height is a garden rake
                const lean = rng.range(4.0, 24.0); // the mesh already curls; the transform only tips it OFF plumb
                const kind = @as(usize, @intFromFloat(rng.range(0, ROOT_KINDS)));
                const u = s.t - ROOT_RISE * ROOT_LAG * (@as(f32, @floatFromInt(k)) / ROOT_FANS);
                if (u <= 0) continue;
                // TORN up, overshooting its own height and settling onto it, held, then drawn back slower —
                // a root sinks, it is never popped away.
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

    /// …and a bigger one WHEREVER IT LANDS, which is the half of it the player is actually looking at.
    pub fn boltBurst(self: *Hero, at: rl.Vector3, salt: u32) void {
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

    pub fn attackHit(self: *const Hero) combat.Hit {
        return if (self.atkHeavy) ATK_HEAVY_HIT else ATK_LIGHT_HIT;
    }
    pub fn setSpawn(self: *Hero, pos: rl.Vector3, facing: f32) void {
        self.spawnPos = pos;
        self.spawnFacing = facing;
    }
    pub fn staggered(self: *const Hero) bool {
        return self.stun != .none;
    }
    /// The grace's restock, reachable from a test without running the whole death animation.
    pub fn respawnForTest(self: *Hero) void {
        self.respawn();
    }

    pub fn iFramed(self: *const Hero) bool {
        return self.rolling and self.rollT < ROLL_IFRAME_END;
    }

    pub fn guardCovers(self: *const Hero, fromDir: rl.Vector3) bool {
        if (!self.guarding or mathx.lenXZ(fromDir) < 1e-4) return false;
        const off = mathx.wrapPi(mathx.headingXZ(fromDir) - self.facing);
        return @abs(mathx.degrees(off)) <= combat.GUARD_ARC;
    }

    pub fn takeHit(self: *Hero, h: combat.Hit, fromDir: rl.Vector3) combat.HitOutcome {
        if (self.dead) return .ignored;
        if (self.iFramed()) return .ignored; // rolled through it — no damage, no flinch, nothing
        if (self.guardCovers(fromDir)) return self.blockHit(h);
        const r = self.vit.hit(h);
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

    /// THE GROUND HURTING HIM — the brood mother's acid today, and whatever else the floor does later. It takes a whole `Hit` because a floor has an ELEMENT (hers is chaos): a bare number would be the one damage path in the game that could not say what it was.
    pub fn burn(self: *Hero, h: combat.Hit) combat.HitOutcome {
        if (self.dead or h.raw() <= 0) return .ignored;
        const r = self.vit.hit(h);
        self.hurtFlash = mathx.maxF(self.hurtFlash, 0.45);
        if (r == .death) self.enterDeath();
        return .taken;
    }

    fn blockHit(self: *Hero, h: combat.Hit) combat.HitOutcome {
        self.blockT = 0;
        self.stam.spend(combat.guardStamina(h));
        const r = self.vit.hit(combat.guardChip(h));
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

    fn enterStun(self: *Hero, kind: combat.StunKind) void {
        self.attacking = false; // the reaction drops whatever he was committed to
        self.rolling = false;
        // …the draught included, AND THE CHARGE IS ALREADY GONE.
        self.drinking = false;
        // …and the cast, whose FP is already gone for the same reason. A stagger through the sweep is a
        // spell you paid for and did not get, exactly as it is a flask you paid for and did not drink.
        self.casting = false;
        self.guarding = false;
        // …and the shield's window, whose stamina is already gone for the cast's reason. A catch he was one
        // frame short of is a catch he does not get.
        self.parrying = false;
        self.dropAim();
        self.queued = null;
        self.stun = kind;
        self.stunT = 0;
        self.speed = 0;
        // …and the poise immunity that comes with a reaction (combat.Vitals).
        self.vit.beginStun(kind);
        self.startXfade();
    }
    fn enterDeath(self: *Hero) void {
        self.attacking = false;
        self.rolling = false;
        self.drinking = false;
        self.casting = false;
        self.guarding = false;
        self.parrying = false;
        self.dropAim();
        self.stun = .none;
        self.queued = null;
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
        const dur: f32 = if (self.stun == .heavy) combat.HEAVY_STUN_DUR else combat.LIGHT_STUN_DUR;
        self.pose();
        if (self.stunT >= dur) {
            self.stun = .none;
            self.startXfade(); // ease out of the reel into whatever's next
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
        self.drinking = false;
        self.casting = false;
        self.stamRefused = 0; // a respawn must not inherit the last life's refusal flash
        self.fpRefused = 0;
        self.sprinting = false;
        self.guarding = false;
        self.guardB = 0;
        self.parrying = false;
        self.dropAim();
        self.blockT = mathx.LONG_AGO;
        self.pos = self.spawnPos;
        self.facing = self.spawnFacing;
        self.moving = 0;
        self.speed = 0;
        self.speedS = 0;
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
        if (self.rolling) return self.poseRoll();
        if (self.attacking) return self.poseAttack();
        if (self.casting) return self.poseCast();
        if (self.parrying) return self.poseParry();
        const m = self.moving;
        const ph = self.phase;
        const twoPi = std.math.tau;
        // Travel direction in the body frame (locked-on strafe/backpedal — see the locked-on footing note above STRIDE). fw signs the sagittal gait (negative = the time-reversed backpedal), lat drives the sidestep.
        const fw = self.fwdB;
        const lat = self.latB;
        const fwPos = mathx.clampF(fw, 0, 1);
        const runB = mathx.clampF((self.speedS - RUN_SPEED_LO) / (RUN_SPEED_HI - RUN_SPEED_LO), 0, 1) * fwPos;
        const sprintB = mathx.clampF((self.speedS - RUN_SPEED_HI) / (SPRINT_REF_SPEED - RUN_SPEED_HI), 0, 1) * fwPos;
        const gB = mathx.clampF(self.guardB, 0, 1);
        const rec = self.blockRecoil();
        const guardBack = BLOCK_STEP * rec;
        const dk = self.drinkLevels(); // zero unless he has a flask up — see poseDrinkArm
        const crouch = (RUN_CROUCH * runB + 0.5 * RUN_CROUCH * sprintB) * m +
            STRAFE_DIP * @abs(lat) * m + // low centre of gravity; strafing settles onto its soft knees
            GUARD_CROUCH * gB + BLOCK_SINK * rec + DRINK_SINK * H * dk.lift;

        const walkBob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * ph); // twice/stride, symmetric
        const runBounce = A_RUN_BOUNCE * (0.5 - 0.5 * mathx.cosf(2.0 * twoPi * (ph - 0.2))); // up-only, peaks at flight
        const fwAbs = @abs(fw);
        const bob = mathx.lerpF(walkBob, runBounce, runB) * m * fwAbs + 0.006 * H * mathx.sinf(self.elapsed * 2.2) * (1.0 - m);
        const latW = @abs(lat) * m;
        const sway = strafeSway(latW, runB) * mathx.sinf(twoPi * ph) * m; // weight sits over the single-support foot; a strafe just opens the amplitude
        const prot = A_PROT * mathx.sinf(twoPi * ph) * m * @abs(fw) + strafeProt(ph, lat, m);
        const list = A_LIST * mathx.sinf(twoPi * ph) * m * fwAbs; // pelvic frontal drop (sagittal gait's)

        // Root: place at world pos, at hip height (crouched when running), swayed/bobbed in body frame, PITCHED FORWARD ABOUT THE FEET (so the centre of gravity leads the base — the driving, falling-forward run), then faced.
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const bodyPitch = (BODY_PITCH_RUN * runB + (BODY_PITCH_SPRINT - BODY_PITCH_RUN) * sprintB) * m + self.slopePitch;
        var wx: [N]rl.Matrix = undefined;
        const pelvY = hipY - crouch + bob;
        wx[ROOT] = mul3(
            mul(rz(list), ry(prot)), // tilt/rotate pelvis about its centre
            mul(tr(sway, pelvY, -guardBack), mul(rx(bodyPitch), ry(facingDeg))), // crouch, driven back off a caught blow, pitch whole body forward about the feet, then face
            rootAt(self.pos), // place in the world, ON the ground under him
        );

        const lean = (mathx.lerpF(TORSO_LEAN * fw, RUN_LEAN, runB) + sprintB * (SPRINT_LEAN - RUN_LEAN)) * m;
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
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity()); // blade rides the fist

        // …and the shield goes up OVER all of it (see poseGuard) — the gait keeps running underneath.
        if (gB > 0.001) self.poseGuard(&wx, gB, rec, lean, prot, bank);

        if (self.wandOut()) self.poseWandArm(&wx);
        if (self.bowOut()) self.poseBowArms(&wx, lean, prot, bank);
        // LAST, so the flask wins the off hand off a raised bow — that hand was on the string.
        if (self.drinking) self.poseDrinkArm(&wx, dk.lift, dk.tip);
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// The off arm only, laid over whatever gait just ran (the guard and bow arm's pattern). The head leads AWAY
    /// from the fist (`WAND_AX`), so an arm hanging at the side aims the lit end at the dirt and reads as a cane
    /// — the elbow is what lifts it. KEEPS the gait swing, damped: three flat joints is a welded arm.
    fn poseWandArm(self: *const Hero, wx: *[N]rl.Matrix) void {
        const swing = ARM_SWING * mathx.cosf(std.math.tau * self.phase) * self.moving * self.fwdB;
        var p = wx.*;
        setLocal(&p, SHL, self.rest, mul(rx(-WAND_CARRY_FLEX + WAND_CARRY_SWING * swing), rz(ARM_ABD + WAND_CARRY_ABD)));
        setLocal(&p, ELL, self.rest, rx(-(WAND_CARRY_ELBOW + WAND_CARRY_ELBOW_SWING * swing)));
        setLocal(&p, WRL, self.rest, rz(WAND_CARRY_WRIST));
        for ([_]usize{ SHL, ELL, WRL }) |i| wx[i] = p[i];
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
        // The bow arm stays LONG — a folded one is a bow held at your own face.
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
        return mathx.clampF(self.shotT / (if (self.shotAimed) BOW_SHOT_DUR else BOW_QUICK_DUR), 0, 1);
    }
    /// Has THIS shot already let the shaft go? (`loosed` is the one FRAME it happened on.)
    fn loosedAlready(self: *const Hero) bool {
        if (!self.shooting) return false;
        return self.shotU() >= (if (self.shotAimed) BOW_SHOT_AT else BOW_QUICK_AT);
    }

    fn blockRecoil(self: *const Hero) f32 {
        if (self.blockT >= BLOCK_RECOIL_DUR) return 0;
        const u = mathx.clampF(self.blockT / BLOCK_RECOIL_DUR, 0, 1);
        return (1.0 - u) * (1.0 - u);
    }

    fn poseGuard(self: *const Hero, wx: *[N]rl.Matrix, k: f32, rec: f32, lean: f32, prot: f32, bank: f32) void {
        var gp = wx.*;
        const blade = -(GUARD_BLADE + BLOCK_TRUNK * rec);
        setLocal(&gp, SPINE, self.rest, mul3(rx(lean * 0.5), ry(-0.3 * prot + blade), rz(0.5 * bank)));
        setLocal(&gp, CHEST, self.rest, mul3(rx(lean * 0.5 + 5.0 * rec), ry(-0.5 * prot + blade), rz(0.5 * bank)));
        setLocal(&gp, NECK, self.rest, ry(-blade));
        setLocal(&gp, HEAD, self.rest, mul(rx(GUARD_HEAD), ry(-blade)));
        setLocal(&gp, SHL, self.rest, mul3(rx(-(GUARD_SH_FLEX - BLOCK_SHIELD_BACK * rec)), rz(GUARD_SH_ABD), ry(-GUARD_SH_CROSS)));
        setLocal(&gp, ELL, self.rest, rx(-(GUARD_ELBOW + BLOCK_SHIELD_FOLD * rec)));
        setLocal(&gp, WRL, self.rest, rl.math.matrixIdentity());
        setLocal(&gp, SHR, self.rest, mul(rx(GUARD_SWORD_BACK), rz(-ARM_ABD)));
        setLocal(&gp, ELR, self.rest, rx(-GUARD_SWORD_ELBOW));
        setLocal(&gp, WRR, self.rest, rx(GUARD_SWORD_WRIST));
        setLocal(&gp, SWORD, self.rest, rl.math.matrixIdentity());
        for ([_]usize{ SPINE, CHEST, NECK, HEAD, SHL, ELL, WRL, SHR, ELR, WRR, SWORD }) |i| {
            wx[i] = lerpM(wx[i], gp[i], k);
        }
    }

    /// ONE CHANNEL DRIVES THE WHOLE SHOVE: out hard to `PARRY_PUNCH_AT`, then a damped swing that crosses its
    /// own rest and settles exactly on it (a mass in motion overshoots — the reactions law, on the player's own
    /// arm). At the end it is 0, which IS the guard pose, so the window eases back into the stance it came out
    /// of rather than snapping there.
    fn parryDrive(u: f32) f32 {
        if (u <= PARRY_PUNCH_AT) return mathx.smoothstep(0, PARRY_PUNCH_AT, u);
        const w = mathx.clampF((u - PARRY_PUNCH_AT) / (1.0 - PARRY_PUNCH_AT), 0, 1);
        const fall = (1.0 - w) * (1.0 - w); // …and it dies AT w = 1, so there is nothing left to snap out of
        return fall * mathx.cosf(std.math.tau * PARRY_REBOUND * w);
    }

    /// THE SWIPE ITSELF: −1 fully coiled the other way, +1 followed all the way through, crossing CENTRE about
    /// where the thrust peaks — which is the frame that catches. It comes home to 0, so the shove ends on the
    /// stance it started from and the exit has nothing to unwind.
    fn parrySweep(u: f32) f32 {
        const coil = mathx.smoothstep(0, PARRY_COIL_AT, u); // wind up, fast
        const whip = mathx.smoothstep(PARRY_COIL_AT, PARRY_SWEEP_END, u); // …then the arc, crossing at half
        const settle = 1.0 - mathx.smoothstep(PARRY_SWEEP_END, 1.0, u); // …and the follow-through unwinds
        return (2.0 * whip - coil) * settle;
    }

    /// THE BAT-AWAY — the guard's own stance with the boards shoved out of it, driven by the trunk and rocked
    /// back onto rest. A CAUGHT blow lands on top of it through `blockRecoil`, the block's own channel: the man
    /// moves and the shield holds, so the recoil goes into the body and only a little into the arm.
    fn poseParry(self: *Hero) void {
        const u = mathx.clampF(self.parryT / PARRY_DUR, 0, 1);
        const k = parryDrive(u); // the THRUST: boards out and back
        const s = parrySweep(u); // …and the SWIPE they travel on, −1 coiled through to +1 followed through
        const rec = self.blockRecoil();
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        // The guard's own trunk yaw toward the shield side, with the swipe turning through it: negative winds
        // him up onto that side, positive carries the whole arm — and the boards square on it — across his front.
        const blade = -(GUARD_BLADE + BLOCK_TRUNK * rec) + PARRY_TRUNK * s;
        const sink = GUARD_CROUCH + PARRY_SINK * k + BLOCK_SINK * rec;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(PARRY_PELVIS * blade), // the pelvis takes a share of the turn; the rest is waist
            mul(tr(0, hipY - sink, PARRY_LEAD * k - BLOCK_STEP * rec), mul(rx(PARRY_PITCH * k), ry(facingDeg))),
            rootAt(self.pos),
        );
        setLocal(&wx, SPINE, self.rest, ry(0.5 * blade));
        setLocal(&wx, CHEST, self.rest, mul(rx(5.0 * rec), ry(0.5 * blade)));
        setLocal(&wx, NECK, self.rest, ry(-0.45 * blade));
        setLocal(&wx, HEAD, self.rest, mul(rx(PARRY_HEAD), ry(-0.55 * blade))); // chin stays behind the rim
        // BRACED, NOT SQUATTING: the feet are set and the shove takes up in soft knees.
        setLocal(&wx, HIPL, self.rest, mul(rx(-5.0 * k), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 12.0 * k + 8.0 * rec));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(4.0 * k), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 8.0 * k + 8.0 * rec));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        // THE BOARDS, driven at the blow and squaring onto it. The shoulder gains what the elbow gives back, so
        // the FOLD `shieldFit` inverts is untouched and the face keeps pointing where the guard was pointing it
        // — see PARRY_PUNCH. Everything that actually turns the boards is deliberate: the shoulder's own yaw
        // unwinding the cross, and a small roll in the fist.
        setLocal(&wx, SHL, self.rest, mul3(
            rx(-(GUARD_SH_FLEX + PARRY_PUNCH * k - BLOCK_SHIELD_BACK * rec)),
            rz(GUARD_SH_ABD),
            ry(-(GUARD_SH_CROSS - PARRY_SWEEP * k) + PARRY_ARM_LEAD * s),
        ));
        setLocal(&wx, ELL, self.rest, rx(-(GUARD_ELBOW - PARRY_PUNCH * k + BLOCK_SHIELD_FOLD * rec)));
        setLocal(&wx, WRL, self.rest, rz(PARRY_WRIST * k));
        // …and the sword hand DRAWS BACK behind them, off the guard's own carry: the riposte, loading.
        setLocal(&wx, SHR, self.rest, mul(rx(GUARD_SWORD_BACK + PARRY_SWORD_COCK * k), rz(-ARM_ABD)));
        setLocal(&wx, ELR, self.rest, rx(-(GUARD_SWORD_ELBOW + 14.0 * k)));
        setLocal(&wx, WRR, self.rest, rx(GUARD_SWORD_WRIST));
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity());
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
            rootAt(self.pos), // place in the world, ON the ground under him
        );
        setLocal(&wx, SPINE, self.rest, rx(ROLL_SPINE * tuck)); // curl forward
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
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity()); // blade stays in the fist through the tuck
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseAttack(self: *Hero) void {
        if (self.atkHeavy) return self.poseHeavy();
        self.poseLight();
    }

    fn poseLight(self: *Hero) void {
        const u = mathx.clampF(self.atkT / ATK_LIGHT_DUR, 0, 1);
        const rec = 1.0 - mathx.smoothstep(AL_RECOV_A, 1.0, u); // 1 until recovery, draining to 0
        const wind = mathx.smoothstep(0, AL_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AL_STRIKE_A, AL_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_STRIKE_B + AL_LAG, u) * rec;
        const sElb = mathx.smoothstep(AL_WIND_B, AL_HIT_A + 0.04, u) * rec;
        const sWr = mathx.smoothstep(AL_STRIKE_A + 2 * AL_LAG, AL_STRIKE_B + 2 * AL_LAG, u) * rec;
        const sw: f32 = if (self.atkAlt) -1.0 else 1.0; // swing side: +1 forehand, -1 backhand return
        const amp: f32 = if (self.atkAlt) 0.8 else 1.0; // the cross-body windup can't coil as deep

        const os = AL_OVER * bump(u, AL_STRIKE_B + 2 * AL_LAG, AL_RECOV_A + 0.15);
        const yawP = sw * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sPelv);
        const yawC = sw * (1.35 * (-AL_BODY_YAW * wind + (AL_BODY_YAW_THRU + AL_BODY_YAW) * sChest) + os);
        const crunch = AL_SPINE_CRUNCH * sChest;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yawP),
            mul(tr(0, hipY - AL_LOAD * wind - AL_DIP * sPelv, 0), mul(rx(1.5 * sChest), ry(facingDeg))), // knees coil under the windup; only a WHISKER of forward pitch (the swipe plane stays flat)
            rootAt(self.pos),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(crunch + self.aimLean * 0.5), ry(0.35 * yawC)));
        setLocal(&wx, CHEST, self.rest, mul(rx(crunch + self.aimLean * 0.5), ry(0.65 * yawC)));
        setLocal(&wx, NECK, self.rest, ry(-0.4 * (yawP + yawC)));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK), ry(-0.35 * (yawP + yawC)))); // eyes stay on the target
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
        setLocal(&wx, SHL, self.rest, mul(rx(-10.0 * wind + 24.0 * sChest), rz(ARM_ABD)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 12.0 * wind)));
        setLocal(&wx, WRL, self.rest, rl.math.matrixIdentity());
        const windAmp: f32 = if (self.atkAlt) AL_ALT_WIND else 1.0;
        const sRaise = mathx.smoothstep(AL_WIND_B - 0.06, AL_HIT_A - 0.02, u) * rec;
        const elev = AL_SH_ELEV_WIND * wind + (AL_SH_ELEV - AL_SH_ELEV_WIND) * sRaise;
        // The sweep fires ONE lag after the pelvis (with the chest, not after it) and runs to the END of the hit window — the blade is flying for every active frame: no pre-window hang, no dead beat at the tail.
        const sSweep = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_HIT_B - 0.01, u) * rec;
        const sweep = sw * (-AL_SWEEP_WIND * windAmp * wind + (AL_SWEEP_WIND * windAmp + AL_SWEEP_END) * sSweep + 0.9 * os);
        setLocal(&wx, SHR, self.rest, mul3(rx(-elev), ry(sweep), rz(-ARM_ABD - 10.0 * amp * wind)));
        const elb = IDLE_ELBOW + (AL_ELBOW_WIND - IDLE_ELBOW) * wind - (AL_ELBOW_WIND - AL_ELBOW_STRIKE) * sElb;
        setLocal(&wx, ELR, self.rest, rx(-elb));
        const lvl = mathx.smoothstep(0.05, AL_STRIKE_A, u) * rec;
        const lay = sw * (AL_WRIST_LAY * wind - (AL_WRIST_LAY + AL_WRIST_WHIP) * sWr);
        setLocal(&wx, WRR, self.rest, mul3(ry(sw * AL_EDGE_ROLL * lvl), rx(-AL_TIP_UP * lvl), rz(lay)));
        setLocal(&wx, SWORD, self.rest, rx(GRIP_PITCH * lvl));
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseHeavy(self: *Hero) void {
        const u = mathx.clampF(self.atkT / ATK_HEAVY_DUR, 0, 1);
        const rec = 1.0 - mathx.smoothstep(AH_RECOV_A, 1.0, u);
        const wind = mathx.smoothstep(0, AH_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AH_STRIKE_A, AH_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AH_STRIKE_A + AH_LAG, AH_STRIKE_B + AH_LAG, u) * rec;
        const sSh = mathx.smoothstep(AH_STRIKE_A + 2 * AH_LAG, AH_STRIKE_B + 2 * AH_LAG, u) * rec;
        const sElb = mathx.smoothstep(AH_STRIKE_A + 3 * AH_LAG, AH_STRIKE_B + 3 * AH_LAG, u) * rec;
        const sWr = mathx.smoothstep(AH_STRIKE_A + 4 * AH_LAG, AH_STRIKE_B + 4 * AH_LAG, u) * rec;

        const gather = mathx.smoothstep(AH_WIND_B - 0.05, AH_STRIKE_A + 2 * AH_LAG, u) * (1.0 - sSh) * rec;
        const rcl = bump(u, AH_STRIKE_B + 2 * AH_LAG, AH_RECOV_A) * rec;

        const yaw = -AH_BODY_YAW * wind + 2.0 * AH_BODY_YAW * sPelv;
        const spineX = -AH_LEAN_BACK * wind + (AH_LEAN_BACK + AH_SPINE_CRUNCH) * sChest;
        const tilt = -AH_SPINE_TILT * wind + 1.5 * AH_SPINE_TILT * sChest;
        const dip = AH_LOAD * wind + (AH_DIP - AH_LOAD) * sPelv - 0.008 * H * rcl;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yaw),
            mul(tr(0, hipY - dip, 0), mul(rx(AH_PITCH * sPelv), ry(facingDeg))),
            rootAt(self.pos),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), rz(0.5 * tilt)));
        setLocal(&wx, CHEST, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), rz(0.5 * tilt)));
        setLocal(&wx, NECK, self.rest, rx(-0.3 * spineX)); // head counters the lean-back, tucks on the drop
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK + 4.0 * sChest), ry(-0.4 * yaw)));
        setLocal(&wx, HIPL, self.rest, mul(rx(-14.0 * wind - 8.0 * sPelv), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 8.0 * wind + 6.0 * sPelv));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(2.0 * wind + 5.0 * sPelv), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 17.0 * wind + 4.0 * sPelv));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, SHL, self.rest, mul(rx(-22.0 * wind + 30.0 * sChest), rz(ARM_ABD + 6.0 * wind)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 16.0 * wind)));
        setLocal(&wx, WRL, self.rest, rl.math.matrixIdentity());
        const shX = -AH_SH_UP * wind - AH_GATHER * gather + (AH_SH_UP - AH_SH_DOWN) * sSh + AH_RECOIL * rcl;
        setLocal(&wx, SHR, self.rest, mul(rx(shX), rz(-ARM_ABD - 8.0 * wind)));
        const elb = IDLE_ELBOW + (AH_ELBOW_WIND - IDLE_ELBOW) * wind + 5.0 * gather - (AH_ELBOW_WIND - AH_ELBOW_STRIKE) * sElb;
        setLocal(&wx, ELR, self.rest, rx(-elb));
        setLocal(&wx, WRR, self.rest, rx(AH_WRIST_COCK * wind - (AH_WRIST_COCK + AH_WRIST_SNAP) * sWr + 8.0 * rcl));
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// THE CAST — a whole-body committed pose, the light slash's shape worked onto the OTHER arm: load,
    /// throw the wand hand OVERHEAD, sweep it across the top, let the bolt go at the middle of that sweep,
    /// unwind. It is a full pose and not an over-the-gait overlay like the draught because he is PLANTED
    /// for it (`updateCast` takes no travel), and `castAlt` is what makes a repeated cast a pair of strokes
    /// sweeping opposite ways instead of one animation played twice.
    fn poseCast(self: *Hero) void {
        const u = self.castU();
        const rec = 1.0 - mathx.smoothstep(CAST_RECOV_A, 1.0, u); // 1 until recovery, draining to 0
        const wind = mathx.smoothstep(0, CAST_WIND_B, u) * rec; // the raise, and the anticipation in it
        const sSweep = mathx.smoothstep(CAST_WIND_B, CAST_RECOV_A, u) * rec;
        const sThrow = mathx.smoothstep(CAST_AT - 0.08, CAST_AT + 0.06, u) * rec;
        const kick = bump(u, CAST_AT + 0.06, CAST_RECOV_A) * rec; // the rod bounces off the throw
        const sw: f32 = if (self.castAlt) -1.0 else 1.0;

        // `wind` lifts, `sSweep` twirls — separate channels, so the alternator only picks the twirl's side.
        // `wind` 0 must be the CARRY (`poseWandArm`) or the cast snaps out of it on frame one.
        const shRz = mathx.lerpF(ARM_ABD + WAND_CARRY_ABD, CAST_LIFT_ABD, wind);
        const shRy = sw * CAST_SWEEP * (1.0 - 2.0 * sSweep) * wind;
        const yaw = sw * (-CAST_TRUNK * wind + 1.6 * CAST_TRUNK * sSweep);
        const dip = CAST_DIP * wind - 0.4 * CAST_DIP * sThrow;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(yaw),
            mul(tr(0, hipY - dip, 0), mul(rx(2.0 * sThrow), ry(facingDeg))),
            rootAt(self.pos),
        );
        // He ARCHES under the raised arm and folds back over the throw — the waist hinge, not a root lean.
        const spineX = -CAST_LEAN * wind + 2.0 * CAST_LEAN * sThrow;
        setLocal(&wx, SPINE, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), ry(0.35 * yaw)));
        setLocal(&wx, CHEST, self.rest, mul(rx(0.5 * (spineX + self.aimLean)), ry(0.65 * yaw)));
        setLocal(&wx, NECK, self.rest, rx(-0.35 * spineX));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK + CAST_HEAD * sThrow), ry(-0.4 * yaw))); // the eyes stay on what he is throwing it at
        setLocal(&wx, HIPL, self.rest, mul(rx(-6.0 * wind - 4.0 * sThrow), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 12.0 * wind + 4.0 * sThrow));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(4.0 * wind + 3.0 * sThrow), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 9.0 * wind + 3.0 * sThrow));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        // The arm goes LONG as the bolt leaves: an elbow still folded at the throw keeps the stone inside his
        // own silhouette however far overhead the numbers say it is.
        const elb = mathx.lerpF(WAND_CARRY_ELBOW, CAST_ELBOW, wind) - CAST_ELBOW_SNAP * sThrow + 6.0 * kick;
        setLocal(&wx, SHL, self.rest, mul3(rx(-mathx.lerpF(WAND_CARRY_FLEX, CAST_SH_FWD, wind)), ry(shRy), rz(shRz)));
        setLocal(&wx, ELL, self.rest, rx(-elb));
        setLocal(&wx, WRL, self.rest, rz(mathx.lerpF(WAND_CARRY_WRIST, CAST_WRIST, wind) - 1.5 * CAST_WRIST * sThrow - 8.0 * kick));
        // …and the sword arm keeps out of its way, the guard's own answer to a busy off hand.
        setLocal(&wx, SHR, self.rest, mul(rx(GUARD_SWORD_BACK * wind), rz(-ARM_ABD)));
        setLocal(&wx, ELR, self.rest, rx(-(IDLE_ELBOW + (GUARD_SWORD_ELBOW - IDLE_ELBOW) * wind)));
        setLocal(&wx, WRR, self.rest, rx(GUARD_SWORD_WRIST * wind));
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    /// THE DRAUGHT — the OFF hand does all of it, laid OVER whatever gait just ran, which is the pattern
    /// the guard and the bow arms already use. It replaced the whole body once, and that is why he could
    /// not take a step with a flask up: the legs were a standing stance, so travel would have SKATED them.
    /// Only the off arm and the head are the flask's; the legs, the pelvis and the sword arm stay the
    /// walk's, so the phase is still driven by the distance he actually covered.
    fn poseDrinkArm(self: *const Hero, wx: *[N]rl.Matrix, lift: f32, tip: f32) void {
        var dp = wx.*;
        setLocal(&dp, NECK, self.rest, rx(-14.0 * tip));
        setLocal(&dp, HEAD, self.rest, rx(HEAD_WALK - 30.0 * tip));
        setLocal(&dp, SHL, self.rest, mul(rx(-58.0 * lift - 14.0 * tip), rz(ARM_ABD + 16.0 * lift)));
        setLocal(&dp, ELL, self.rest, rx(-(IDLE_ELBOW + 96.0 * lift + 22.0 * tip)));
        setLocal(&dp, WRL, self.rest, rx(-28.0 * tip)); // the wrist rolls the bottle up at the lips
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
            rootAt(self.pos),
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
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity()); // not drawn while resting
        // NO CROSS-FADE, and this is the bug worth recording: `applyXfade` reads `blendT`, which only `tickClocks` advances — and no rest path ticks it, so every frame lerped at k = 0 and the hero was drawn in the STANDING pose captured where he had been standing, several metres off camera.
        self.xf = wx;
    }

    fn poseStun(self: *Hero) void {
        const heavy = self.stun == .heavy;
        const dur: f32 = if (heavy) combat.HEAVY_STUN_DUR else combat.LIGHT_STUN_DUR;
        const u = mathx.clampF(self.stunT / dur, 0, 1);
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
        // Knocked back off the blow: the body shifts along -^'facing (the flinch reads as impact, not a lean). +Z in the pre-facing frame is the facing dir, so a -^'Z offset = backward.
        const backMag: f32 = if (heavy) 0.10 * H else HURT_STEP;
        const back = backMag * amt;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rz(wob),
            mul(tr(0, hipY - sink, -back), mul(rx(-0.55 * lean), ry(facingDeg))), // whole body snaps back
            rootAt(self.pos),
        );
        setLocal(&wx, SPINE, self.rest, mul(rx(-0.55 * lean), rz(0.3 * wob))); // arch BACK hard
        setLocal(&wx, CHEST, self.rest, mul(rx(-0.55 * lean), rz(0.3 * wob)));
        const headBackMag: f32 = if (heavy) HURT_HEAD * 1.3 else HURT_HEAD;
        const headBack = headBackMag * amt;
        setLocal(&wx, NECK, self.rest, rx(-0.4 * headBack));
        setLocal(&wx, HEAD, self.rest, rx(-headBack)); // thrown back / lolling
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
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    fn poseDeath(self: *Hero) void {
        const u = mathx.clampF(self.deathT / DEATH_DUR, 0, 1);
        const k = mathx.smoothstep(0, 0.5, u); // the collapse
        const settle = mathx.smoothstep(0.5, 0.85, u); // the final slump onto the ground
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const y = mathx.lerpF(hipY, DEATH_SINK * hipY, k);
        const pitch = 22.0 * k + 20.0 * settle; // fold forward as he sinks
        const twist = 12.0 * k; // slump to one side

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rz(twist),
            mul(tr(0, y, 0), mul(rx(pitch), ry(facingDeg))),
            rootAt(self.pos),
        );
        setLocal(&wx, SPINE, self.rest, rx(28.0 * k)); // curl down
        setLocal(&wx, CHEST, self.rest, rx(28.0 * k));
        setLocal(&wx, NECK, self.rest, rx(20.0 * k));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK + 26.0 * k)); // head hangs
        setLocal(&wx, HIPL, self.rest, mul(rx(-70.0 * k), rz(-HIP_ADDUCT - 10.0 * k)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 110.0 * k)); // legs buckle under
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(-60.0 * k), rz(HIP_ADDUCT + 8.0 * k)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 100.0 * k));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        setLocal(&wx, SHL, self.rest, mul(rx(-14.0 * k), rz(ARM_ABD + 14.0 * k))); // arms splay/drop
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 30.0 * k)));
        setLocal(&wx, WRL, self.rest, rl.math.matrixIdentity());
        setLocal(&wx, SHR, self.rest, mul(rx(-10.0 * k), rz(-ARM_ABD - 10.0 * k)));
        setLocal(&wx, ELR, self.rest, rx(-(IDLE_ELBOW + 24.0 * k)));
        setLocal(&wx, WRR, self.rest, rl.math.matrixIdentity());
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    pub fn draw(self: *const Hero) void {
        const stowSword = self.resting or self.bowOut();
        for (0..N) |i| {
            if (stowSword and i == SWORD) continue;
            rl.drawMesh(self.mesh[i], self.mat, self.xf[i]);
        }
        if (self.resting) {
            rl.drawMesh(self.guitar, self.mat, self.xf[ROOT]);
            return;
        }
        if (self.bowOut()) {
            rl.drawMesh(self.bow, self.mat, self.xf[HELD]);
            for (self.stringXf) |sm| rl.drawMesh(self.bowString, self.mat, sm);
            if (self.nockVis) rl.drawMesh(self.bowNock, self.mat, self.nockXf);
            return;
        }
        // WHAT IS IN THE LEFT HAND, and it is one or the other — both ride that wrist rather than a bone of
        // their own (see the fields), and only the shield needs turning onto the arm.
        switch (self.off) {
            .shield => rl.drawMesh(self.shield, self.mat, mul(shieldFit(), self.xf[WRL])),
            .wand => rl.drawMesh(self.wand, self.mat, self.xf[WRL]),
        }
    }

    /// Eye/target point for the camera: the base of the neck, measured from `pos.y`
    pub fn shoulderPoint(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + self.rest[CHEST].y, self.pos.z);
    }
};

pub fn setHumanoid(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    setJoint(wx, &rest, i, @intCast(PARENT[i]), animRot);
}
const setLocal = setHumanoid;

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
    // The foot's world +X displacement from directly under its OWN hip: rz(+) swings a leg toward +X, and lat > 0 is travel to his RIGHT, which is world -^'X.
    const dx = -lat * s * m;
    const crossing = side * lat > 0;
    const inSwing = w >= 0;
    const arc = if (inSwing) mathx.sinf(std.math.pi * w) else 0.0; // 0→1→0, swing only
    const passF = (if (crossing) @as(f32, STRAFE_CROSS) else -STRAFE_BEHIND) * arc * latW;
    const landF = if (inSwing or !crossing) 0.0 else STRAFE_LAND * (1.0 - 2.0 * q / STRAFE_STANCE) * latW;
    const latHip = passF + landF; // this leg's sagittal angle, LATERAL contribution only
    // The one part of a sidestep that cannot be constants.
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
        // Rotating about the ankle's own X lifts that corner at a rate set by its HORIZONTAL distance from the joint — measured, not taken from the foot's length, because an already steeply pitched foot (toe-off plantarflexion) has most of that length pointing DOWN and a length-based step then badly undershoots.
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

// THE HERO'S EDGES ARE FILLETED, AND THE OLD HERO IS ONE CONSTANT AWAY (owner: keep it around in case).
// Every body part's box goes through `slab`, so `ROUND_EDGES = false` restores the hard-edged mesh
// EXACTLY — `addRoundBox` takes the same FULL size `addCube` does and keeps the six face planes where
// they were, so the anthropometry (which is measured, not styled) does not move either way.
// THE BLADES STAY SHARP: `swordMesh`'s oriented boxes are steel with an edge on them, which is the one
// thing in here that is supposed to read as a hard rim (see AGENTS.md's FLESH IS ROUND).
const ROUND_EDGES = true;
/// 1 is a plain ellipsoid, 0 the hard cube. Low enough that a shoulder cap still reads as a plate and
/// the head still reads as a skull rather than an egg — the flats have to survive the fillet.
pub const ROUND_E: f32 = 0.34;
/// A fillet costs a box 6 quads → segs×sides, so the TESSELLATION IS SIZED TO THE PART. The head, torso
/// and thighs are what a fillet is for and they get the fine grid; a buckle, a nose or a pouch flap is a
/// couple of centimetres across, where the same grid is a dozen quads a pixel. Measured off the part's
/// largest dimension in units of stature, so it holds if the rig is ever rescaled.
pub fn roundGrid(size: rl.Vector3) struct { segs: i32, sides: i32 } {
    const big = @max(@max(@abs(size.x), @abs(size.y)), @abs(size.z)) / H;
    if (big >= 0.12) return .{ .segs = 6, .sides = 12 };
    if (big >= 0.05) return .{ .segs = 5, .sides = 10 };
    return .{ .segs = 3, .sides = 6 };
}

/// One body box. The ONE place ANY body on this rig chooses between a filleted and a hard edge — the folk
/// build through it too (`npc.zig`), or `ROUND_EDGES` would put the hero back to hard rims and leave every
/// other human in the world filleted.
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

// The drawn arming sword, authored in the RIGHT-WRIST frame about the fist centre (0, FIST_Y, FIST_Z), blade canted GRIP_PITCH forward of the forearm line (held at an angle, never straight along it); at rest the tip leads down-forward, clear of the ground (souls low-ready), and attacks whip the wrist/arm while the blade just rides.
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

// THE SMALL ROUND SHIELD, authored FACE-ON — a disc in XY with its face along +Z, centred on the grip — and turned onto the arm by `shieldFit`.
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

/// THE BOLT IN FLIGHT — a chaos mote, drawn along +Z because `archer.arrowXform` orients that axis down
/// the flight. Authored as a core inside a cooler shell and STRETCHED along the line of travel, so a
/// side-on shot reads as a streak rather than a ball; the vertex alpha is the emissive channel, which is
/// what makes it lit from inside instead of a painted purple pebble.
pub fn boltMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(0.070, 0.070, 0.155), 7, 11, CHAOS_MOTE);
    b.addBlob(v3(0, 0, 0.020), v3(0.040, 0.040, 0.095), 6, 9, CHAOS_HOT);
    return b.toModel(shader);
}

/// ONE ROOT TENDRIL, authored at the origin coming UP out of the earth along +Y with a lean into +Z, so a yaw
/// about the site fans a ring of them outward. It starts BELOW zero, or a tendril on sloping ground shows the
/// flat disc of its own bottom cap where it meets the dirt.
///
/// NOTHING DEAD IS STRAIGHT AND NOTHING ENDS IN A POINT: it leaves the earth on one line, breaks at a knee,
/// carries on off that line, and snaps off blunt in pale heartwood. A single tapered run to a needle is a
/// spear, and seven of those about a point is a hub of spokes.
fn rootTendrilMesh(variant: u32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x600751 +% variant *% 7919);
    b.setMat(.wood);
    // ONE TONE PER SHAFT, and the two bark values separate the three VARIANTS instead. Alternated per segment
    // they striped every tendril like a barber's pole — which is the thing the note under them forbids, and it
    // only showed once the shaft was fat enough to see it. Wabi-sabi belongs BETWEEN the nine, not along one.
    const bark = mathx.lerpColor(ROOT_BARK, ROOT_BARK_LT, @as(f32, @floatFromInt(variant)) / @as(f32, ROOT_KINDS - 1));
    // The CURL is drawn ONCE and applied every segment, so the thing arcs. Re-rolled per segment it wanders
    // instead, and a wander made of straight capsules is a chain of elbows — which is what reads as a caltrop.
    // BRACKETED FROM BOTH SIDES: at 0.03–0.065 they stood up as posts with a crossbar and read as grave
    // markers; far past this they arc to near-horizontal and read as croquet hoops in the lawn. These claw up
    // out of the earth and turn over through the last third — the only band that reads as a root at all.
    // PER SEGMENT, so it is re-bracketed whenever `ROOT_LEN` moves: the total arc is `curl` × the segment
    // count, and at 0.055–0.095 over the 1.05 m shaft the same bend spread over 1.7× the run read as a STAKE.
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
        // It falls away from plumb a little MORE each segment — steep out of the earth, curling over by the
        // tip, and never straight. The jitter on top is small: it roughens the arc, it does not make it.
        dir = mathx.normV(v3(
            dir.x + (sway + rng.range(-0.05, 0.05)) * (0.4 + k),
            dir.y - curl * (0.4 + k),
            dir.z + (curl * 0.45 + rng.range(-0.05, 0.05)) * (0.4 + k),
        ));
    }
    // …and the BLUNT SNAP it ends in, a touch fatter than the shaft so it reads as a break and not a taper.
    b.addBlob(p, v3(r * 1.30, r * 0.95, r * 1.30), 4, 9, ROOT_HEART);
    // THREE STUBS off the outer half — a bare shaft is a cane, and a root that tore up through packed
    // earth brings its own broken side-growth with it. Blunt too: `addCapsule` domes both ends.
    var s: u32 = 0;
    while (s < 3) : (s += 1) {
        const base = mathx.lerpV(v3(0, 0, 0), p, rng.range(0.40, 0.78));
        const a = rng.angle();
        const len = ROOT_LEN * rng.range(0.11, 0.19);
        // They RUN WITH the shaft, not across it: thrown out level they read as the crossbar of a grave marker,
        // which is the single thing that turned an upright tendril into a headstone.
        const out = v3(base.x + mathx.cosf(a) * len * 0.55, base.y + rng.range(0.75, 1.15) * len, base.z + mathx.sinf(a) * len * 0.55);
        const sr = ROOT_R1 * rng.range(1.0, 1.5);
        b.addCapsule(base, out, sr * 1.5, sr, 7, bark);
    }
    return b.toMesh();
}

/// THE WAND — a knotted rod, iron-ferruled, with a chaos-lit stone caught in three claws at its head.
/// Authored in the LEFT WRIST's frame on `WAND_AX` — head leading out of the fist, a stub of butt back out of
/// it — so it needs no fit matrix. Wabi-sabi off a FIXED seed: crooked, and the same crookedness every frame.
fn wandMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x7A4D91);
    const segs = 5;
    // Nothing dead is straight, and nothing ends in a point. The drift stays SMALL: "cut from a hedge", not
    // "broken" — a rod bent a third of its length is a banana.
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

    // The bound grip. Short fat capsules ALONG the shaft, because a turn has to be perpendicular to the rod and
    // the rod is not a world axis (`WAND_AX`).
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
    // Barely proud of the rod it bands: at 1.15 of the shaft radius over a length this short it is a bulge, and
    // against the sky the pair of them read as a lampshade.
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

const scaleV = mathx.scaleV; // shared vector scale (was a local re-implementation)

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
    return .{
        .mesh = undefined,
        .bow = undefined,
        .bowString = undefined,
        .bowNock = undefined,
        .shield = undefined,
        .wand = undefined,
        .roots = undefined,
        .guitar = undefined,
        .mat = undefined,
        .rest = restPositions(),
    };
}

test "the DRAUGHT is committed like the other two: inputs buffer, they do not fire through it" {
    var h = testHero();
    try std.testing.expect(h.startDrink());
    const stamAtDrink = h.stam.cur;

    h.requestAttack(.light);
    try std.testing.expect(h.drinking); // still drinking…
    try std.testing.expect(!h.attacking);
    try std.testing.expectEqual(stamAtDrink, h.stam.cur);
    try std.testing.expect(h.queued != null); // it went where it belongs: the queue

    h.requestRoll(v3(0, 0, 1));
    try std.testing.expect(!h.rolling and h.drinking);

    var guard: u32 = 0;
    while (h.drinking and guard < 500) : (guard += 1) h.tickDrink(0.016);
    try std.testing.expect(!h.drinking);
    try std.testing.expect(h.rolling);
    try std.testing.expect(h.queued == null);
}

test "A DRAUGHT IS A SHUFFLE, and the legs stay the gait's" {
    // The old draught replaced the whole body with a standing stance, so travelling through one would
    // have skated the feet. It is an overlay now: only the off arm and head are the flask's.
    try std.testing.expect(DRINK_SPEED > 0.0 and DRINK_SPEED < GUARD_SPEED);
    var h = testHero();
    try std.testing.expect(h.startDrink());
    h.tickDrink(combat.FLASK_DRINK_DUR * 0.4); // flask at the lips
    const dk = h.drinkLevels();
    try std.testing.expect(dk.lift > 0.5 and dk.tip > 0.0);
    h.drinking = false;
    const dry = h.drinkLevels();
    try std.testing.expectEqual(@as(f32, 0), dry.lift);
    try std.testing.expectEqual(@as(f32, 0), dry.tip);
}

test "THE BOW TAKES THE SHIELD, and it takes it by being asked rather than by clearing a flag" {
    // The mechanic in one test: the left hand is on the string, so there is no hand for the boards.
    var h = testHero();
    h.setGuard(true);
    try std.testing.expect(h.guarding); // sword out: the shield goes up as always

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
    try std.testing.expect(!h.aiming); // sword out

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
    try std.testing.expect(!s.aiming); // no running full draw, same as the guard
    var e = testHero();
    _ = e.swapArm();
    e.stam.cur = 0;
    e.setAim(true);
    try std.testing.expect(!e.aiming); // you cannot hold a draw on an empty bar
}

test "an AIMED shot is refused without an aim, which is what makes L2 a stance and not a modifier" {
    var h = testHero();
    _ = h.swapArm();
    h.requestShot(true);
    try std.testing.expect(!h.shooting); // R2 alone does nothing…
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
    // `loosed` is a ONE-FRAME edge, and both halves matter: a long frame must not fire twice and a short one must not skip the knot and never fire at all.
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
    // The quiver is checked BEFORE the stamina is charged: a loose that never happened must not bill him.
    try std.testing.expectApproxEqAbs(stamBefore, h.stam.cur, 1e-5);
    h.respawnForTest();
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.ready());
}

test "THE FIRE ARROW ADDS FIRE and takes nothing off the shaft's own physical" {
    for ([_]combat.Hit{ BOW_QUICK_HIT, BOW_AIMED_HIT }) |base| {
        const tipped = fireTipped(base);
        try std.testing.expectApproxEqAbs(base.dmg, tipped.dmg, 1e-5); // physical UNTOUCHED — it is added damage
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
    try std.testing.expect(wet.damageFrom(tipped) > BOW_AIMED_HIT.dmg); // still better than a plain shaft
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
    h.respawnForTest();
    try std.testing.expectEqual(combat.FIRE_ARROWS_MAX, h.quiver.count(.fire));
    try std.testing.expectEqual(combat.ARROWS_MAX, h.quiver.count(.plain));
}

test "the two shots are a jab and a payoff, and every number says which is which" {
    try std.testing.expect(combat.STAM_SHOT < combat.STAM_LIGHT); // cheaper than a slash…
    try std.testing.expect(combat.STAM_AIMED > combat.STAM_HEAVY);
    // A BOW CHIPS; IT DOES NOT WIN (owner's call).
    try std.testing.expect(BOW_QUICK_HIT.dmg < ATK_LIGHT_HIT.dmg);
    try std.testing.expect(BOW_AIMED_HIT.dmg < ATK_HEAVY_HIT.dmg);
    try std.testing.expect(BOW_QUICK_HIT.poise < ATK_LIGHT_HIT.poise);
    try std.testing.expect(BOW_AIMED_HIT.poise < ATK_HEAVY_HIT.poise);
    try std.testing.expect(BOW_AIMED_HIT.poise * 2 <= ATK_HEAVY_HIT.poise);
    try std.testing.expect(BOW_AIMED_HIT.stance > 0 and BOW_QUICK_HIT.stance == 0); // only one breaks stance
    try std.testing.expect(BOW_AIMED_SPEED > BOW_QUICK_SPEED and BOW_QUICK_SPEED > 15.0);
    try std.testing.expect(BOW_AIM_SPEED < GUARD_SPEED and BOW_AIM_SPEED > 0.2);
    try std.testing.expect(BOW_QUICK_DUR > BOW_SHOT_DUR);
}

test "a stagger drops the bow but never the CHOICE of weapon" {
    // `dropAim` is the one call the five transitions that drop the shield share, and what it must not touch is the arm: which weapon he picked survives a reaction, and survives a death.
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

test "a Cerulean is refused into a full bar rather than pouring a charge away" {
    var h = testHero();
    h.flasks.sel = .cerulean;
    const before = h.flasks.ready();
    try std.testing.expect(!h.startDrink()); // refused…
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


/// A hero facing +Z with the shield already up.
fn testGuarded() Hero {
    var h = testHero();
    h.facing = 0; // +Z
    h.guarding = true;
    return h;
}

/// The world direction a blow `deg` off his facing comes FROM (facing 0 = +Z).
fn fromAngle(deg: f32) rl.Vector3 {
    return v3(mathx.sinf(radians(deg)), 0, mathx.cosf(radians(deg)));
}

test "the shield is a DIRECTION: it catches the front and not the flank" {
    var h = testGuarded();
    try std.testing.expect(h.guardCovers(fromAngle(0))); // dead ahead
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
    try std.testing.expectApproxEqAbs(HP_MAX - combat.guardChip(club).dmg, h.vit.hp, 1e-3);
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
    // The shield is live the frame the button goes down (ZERO INPUT LAG); only the POSE eases in.
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
    try std.testing.expect(h.committed() and !h.canGuard()); // the held block is off while it runs
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
    // And nothing is caught outside it: the window is the ONLY thing that refuses a blow, so a mistimed parry
    // eats the hit at full weight (the shield is not up either — see requestParry).
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
    // …and THE SWIPE it travels on: nothing on frame one, coiled the OTHER way, then all the way across, and
    // home on centre at the end so the exit has nothing left to unwind.
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1), Hero.parrySweep(PARRY_COIL_AT), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), Hero.parrySweep(PARRY_SWEEP_END), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(1.0), 1e-5);
    // …and it crosses CENTRE exactly where the thrust peaks, which is the frame that catches: the boards have
    // to be travelling their fastest THROUGH the blow, not still winding up when it arrives.
    try std.testing.expectApproxEqAbs(@as(f32, 0), Hero.parrySweep(PARRY_PUNCH_AT), 1e-5);
    try std.testing.expect(PARRY_SWEEP_END > PARRY_PUNCH_AT and PARRY_SWEEP_END < 1.0);
    // …and the STANCE BLEND is held up for the whole window: a shield that visibly sinks through a parry is
    // the animation contradicting the mechanic.
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
    // L2 is the shield's own skill, not a follow-up to blocking: from a standing carry it goes straight out.
    var h = testHero();
    try std.testing.expect(!h.guarding);
    try std.testing.expect(h.canParry());
    try std.testing.expect(h.requestParry());
    // The boards come up for the shove whether or not he was holding them there…
    while (h.parrying) h.updateParry(1.0 / 60.0, null);
    try std.testing.expect(h.guardB > 0.95);
    // …and with nothing on the button they EASE back down, which is a settle and not a latched guard. Snapped
    // to 0 instead it would pop; left at 1 he would stand there blocking off a parry he never asked to hold.
    var t: f32 = 0;
    while (t < 0.4) : (t += 1.0 / 60.0) {
        h.setGuard(false);
        h.tickClocks(1.0 / 60.0);
    }
    try std.testing.expect(h.guardB < 0.05);
}

test "THERE IS ONE LEFT HAND: the wand and the boards can never both be in it, and a bow takes it outright" {
    var h = testHero();
    try std.testing.expect(h.canGuard()); // sword and shield, the default
    try std.testing.expect(!h.canCast());
    try std.testing.expect(h.swapOff());
    try std.testing.expectEqual(Off.wand, h.off);
    // The wand is in the hand, so the boards cannot be — and this is `canGuard` ASKING, not a flag a swap
    // remembered to clear, so it cannot go stale.
    try std.testing.expect(!h.canGuard());
    h.setGuard(true);
    try std.testing.expect(!h.guarding);
    try std.testing.expect(h.canCast());
    // …AND A RAISED BOW TAKES THAT HAND TO THE STRING, so it holds neither. The wand stays EQUIPPED (`off`
    // is untouched); it is simply not in his hand, which is what `wandOut` is for.
    try std.testing.expect(h.swapArm());
    try std.testing.expect(h.bowOut());
    try std.testing.expectEqual(Off.wand, h.off);
    try std.testing.expect(!h.offInHand() and !h.wandOut());
    try std.testing.expect(!h.canCast() and !h.canGuard());
    // …and it comes straight back when the sword does.
    try std.testing.expect(h.swapArm());
    try std.testing.expect(h.wandOut() and h.canCast());
}

test "A CAST IS BILLED IN FP AND NOTHING ELSE — and pay-or-nothing, unlike the panic roll" {
    var h = testHero();
    h.off = .wand;
    const stamBefore = h.stam.cur;
    try std.testing.expect(h.requestCast());
    try std.testing.expectApproxEqAbs(combat.FP_MAX - combat.BOLT_FP, h.fp.cur, 1e-4);
    try std.testing.expectApproxEqAbs(stamBefore, h.stam.cur, 1e-4); // the stamina bar is not touched
    try std.testing.expect(h.casting and h.committed());
    // A HALF-FULL COST BUYS NOTHING. The roll's asymmetry is deliberate and this is deliberately its
    // opposite: below the cost the cast is refused outright, and the FP bar is the one that says so.
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
    try std.testing.expect(h.attacking); // the buffered light left the moment the cast ended
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
        h.fp.cur = combat.FP_MAX; // the economy is not what this test is about
        try std.testing.expect(h.requestCast());
        side.* = h.castAlt;
        var throws: u32 = 0;
        var guard: u32 = 0;
        while (h.casting and guard < 500) : (guard += 1) {
            h.updateCast(1.0 / 60.0, null);
            if (h.thrown) {
                throws += 1;
                // THE ARM IS UP: the stone the bolt leaves is over the CROWN, not out at his chest. Measured
                // off the posed wrist rather than asserted about an angle, so a retune of the sweep is still
                // held to "above his head" — which is the whole of what the pose was asked for.
                const tip = h.wandTipWorld();
                try std.testing.expect(tip.y > h.pos.y + h.rest[HEAD].y);
                peak = mathx.maxF(peak, tip.y);
            }
        }
        try std.testing.expectEqual(@as(u32, 1), throws); // one frame, one bolt — never two, never none
        try std.testing.expectEqual(@as(u32, @intCast(n + 1)), h.casts);
    }
    try std.testing.expect(sides[0] != sides[1]); // the second stroke sweeps back the other way
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
    // A FULL POOL IS A COUNTABLE NUMBER OF CASTS — if this stops dividing sensibly the wand has become
    // either a spammable or a one-shot without anybody deciding to change it.
    const casts = combat.FP_MAX / combat.BOLT_FP;
    try std.testing.expect(casts >= 4 and casts <= 8);
}

test "a grace gives the FP back, and a respawn does not inherit the refusal flash" {
    var h = testHero();
    h.off = .wand;
    _ = h.requestCast();
    h.fp.cur = 0;
    h.fpRefused = combat.STAM_REFUSE_FLASH;
    h.makeWhole();
    try std.testing.expectApproxEqAbs(combat.FP_MAX, h.fp.cur, 1e-4);
    h.respawn();
    try std.testing.expectApproxEqAbs(@as(f32, 0), h.fpRefused, 1e-6);
    // The LOADOUT survives a death: what is in his hands is not a meter to refill (`makeWhole`'s rule
    // about resistances), so he comes back holding the wand he died holding.
    try std.testing.expectEqual(Off.wand, h.off);
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
    try std.testing.expect(crossedL.x < crossedR.x - 0.05); // genuinely crossed, not merely touching
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
                worstPlanted = mathx.maxF(worstPlanted, err); // planted: pinned to the ground
            } else {
                bestSwing = mathx.maxF(bestSwing, a.y - restFootY); // swing: gets real daylight
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
