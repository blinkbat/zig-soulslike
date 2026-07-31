const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const radians = mathx.radians;

// ── THE HERO ────────────────────────────────────────────────────────────────────────
// He reads as human because of two tables, not polygon count: ANATOMY (every bone a fixed fraction of
// stature H, Drillis & Contini 1966 as tabulated in Winter) and GAIT (normative sagittal joint curves,
// Perry / Winter, plus contralateral arm swing, a twice-per-stride bob, sway and pelvic rotation under
// torso counter-rotation). Invariants of human walking, not keyframes.
//
// FK skeleton: each bone is a mesh in its joint's local frame; `pose()` chains matrices once per frame
// and `draw()` replays them, so the depth pass and the lit pass cannot disagree.

pub const H: f32 = 1.8; // stature (world units ≈ metres)

// Locomotion speeds (world units/sec) — the SINGLE source of truth, shared with game.zig
// and the gait blends below. Elden-Ring analog feel: light stick = walk, full = run, hold sprint = dash.
pub const WALK_SPEED: f32 = 1.7;
pub const RUN_SPEED: f32 = 3.4;
pub const SPRINT_SPEED: f32 = 5.1; // hold-B RUN — a touch faster than a full-stick walk-sprint
/// LOCKED-ON sideways travel, as a fraction of forward (ER is anisotropic too). Here rather than in
/// game.zig because the sidestep CADENCE is a property of this rig (`STRAFE_CYCLE`) and its test cannot
/// import game.zig without a cycle.
pub const STRAFE_SPEED: f32 = 0.85;

// Body-segment lengths as a fraction of stature H (Drillis & Contini 1966; Winter). The joint HEIGHTS
// they imply, for sanity: ankle .039, knee .285, hip .530, wrist .485, elbow .630, shoulder .818,
// chin .870, crown 1.0 — each length below is the difference between two of those.
//
// ALL FOUR ARE PUB AND MUST BE READ, NEVER RE-STATED. Every humanoid foe keeps the hero's leg
// fractions (`legChain`'s strafe geometry is measured off LEG_LEN, and a test re-asserts it), so a
// local copy that drifted is a foe whose planted feet skate. Arms may be genuinely per-creature — the
// ogre's are heavier — but a rig documented as carrying the hero's anthropometry reads these.
pub const SEG_THIGH = 0.245; // hip → knee   (femur)
pub const SEG_SHANK = 0.246; // knee → ankle (tibia)
pub const SEG_UPARM = 0.188; // shoulder → elbow
pub const SEG_FOREARM = 0.145; // elbow → wrist

// ── THE SHARED HUMANOID SCAFFOLD ────────────────────────────────────────────────────────
// The 18-bone layout, its parent table and its rest pose — the model every biped is founded on, PUBLIC
// so no creature transcribes it again. Do not re-state these seventeen Y values in a new rig.
//
// BONE 17 IS THE WEAPON SLOT on the right wrist, whatever hangs off it: sword, bow, axe, staff, sling.
// Only the mesh differs, which is why the scaffold is shareable at all.
//
// The OGRE is deliberately off it — 24 bones with three inserted ABOVE existing joints is a different
// layout, not a wider one. It still keeps the leg indices, which `legChain` requires of everything.
pub const N = 18;
pub const ROOT = 0; // pelvis
pub const SPINE = 1; // lumbar / mid-torso pivot
pub const CHEST = 2; // thorax / shoulder girdle
pub const NECK = 3;
pub const HEAD = 4;
// THE LEG INDICES ARE FIXED AT 5..10 for every humanoid, ogre included (AGENTS.md's rule): a foe rig
// may carry MORE bones than these 18, but it must keep its legs here or `legChain` drives the wrong
// joints.
pub const HIPL = 5;
pub const KNEEL = 6;
pub const ANKL = 7;
pub const HIPR = 8;
pub const KNEER = 9;
pub const ANKR = 10;
pub const SHL = 11; // shoulder L
pub const ELL = 12; // elbow L
pub const WRL = 13; // wrist L
pub const SHR = 14;
pub const ELR = 15;
pub const WRR = 16;
/// The WEAPON slot — whatever this creature holds in its right hand, parented to that wrist so it
/// rides every pose for free. `SWORD` is the hero's name for it.
pub const HELD = 17;
const SWORD = HELD;

pub const PARENT = [N]i32{ -1, ROOT, SPINE, CHEST, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CHEST, SHL, ELL, CHEST, SHR, ELR, WRR };
const parent = PARENT;

/// THE REST POSE for any humanoid on this scaffold: joint positions in the creature's own standing
/// frame (X = its left, Y up, Z forward), as fractions of stature scaled by `stature`. Limbs hang
/// straight down — A-pose splay and stance width come from pose abduction, not from here, so a bone
/// mesh and its child joint can never separate.
///
/// `hx` / `sx` are the hip and shoulder half-separations, in the SAME fractional units, because that
/// pair is the one honest per-creature difference in a humanoid's proportions: a kobold is narrower
/// across the shoulders than the Tarnished and it should not have to restate seventeen other numbers
/// to say so.
pub fn restHumanoid(hx: f32, sx: f32, stature: f32) [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.640, 0);
    r[CHEST] = v3(0, 0.760, 0);
    r[NECK] = v3(0, 0.815, 0); // neck base sits just at the shoulder line…
    r[HEAD] = v3(0, 0.885, 0); // …head raised a touch so a real neck shows (crown ≈ 1.02 H)
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

/// The HERO's own proportions on the shared scaffold above.
pub const HIP_HALF = 0.090; // hip half-separation (a touch under half the bi-iliac breadth so the stance isn't splayed)
pub const SHOULDER_HALF = 0.150; // shoulder half-separation (~half the biacromial breadth, plus pauldron room)

fn restPositions() [N]rl.Vector3 {
    return restHumanoid(HIP_HALF, SHOULDER_HALF, H);
}

// ── palette (pre-gamma dark: the scene shader gammas output, so these lift a lot) ──────
// A worn Tarnished: dark iron-blue wool under oxblood leather, a faded crimson tabard and
// short cape, steel at the guard/pauldron, brass at buckle and pommel.
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

// ── ANIMATION ART DIRECTION — the intent every knob below is tuned to hit. AGENTS.md carries the
// locomotion look; CARRY and ATTACK live only here.
//
//  IDLE   : upright, still, alive — a breathing bob and nothing else.
//  WALK   : near-upright (~3°), RESTRAINED arms (never both forearms front — "zombie arms"), low hip
//           sway, heel→toe with a slight toe-out.
//  RUN    : deep lean over a crouched pelvis, pitched about the FEET so the COG leads the base. Arms
//           pump at ~90°, NOT swept back ("naruto" — tried, rejected). Real flight phase.
//  SPRINT : the run deeper, lower, longer, faster.
//  ROLL   : dive into a tuck → ONE front-loaded somersault about a low ball centre → a spin-free rise.
//           Over one shoulder, banked, limbs uneven and drifting roll to roll. Travel DEAD STRAIGHT:
//           the imperfection is entirely in the body.
//  CARRY  : the sword is HELD, not splinted to the arm — the hammer grip cants it ~34° forward of the
//           forearm (souls low-ready, tip clear of the ground). A damped carry, not a mirror of the
//           free arm; a RUN opens it out to the side and pitches the blade level.
//  ATTACK : KINETIC-CHAIN sequenced — pelvis → trunk rotation → trunk flexion → shoulder → elbow →
//           wrist, each a beat late, so the arm WHIPS rather than moving as one block.
//           LIGHT (R1): the HORIZONTAL cut — sabre Cuts III/IV, level and outward across the front
//           (see CUT MECHANICS above the AL_* block). Never a downward poke. Chained lights ALTERNATE
//           backhand, ER-style. (This line said "descending diagonal / Cut One" and contradicted both
//           that block and AGENTS.md — the swipe replaced the diagonal and only one of the three moved.)
//           HEAVY (R2): a slow overhead whose EDGE lands vertical, over a staggered load, buried low
//           and biting through the follow-through. Nothing parks dead at an end pose.
//  BLENDS : by `moving` into walk, by ground SPEED above it (posture chases an eased `speedS`, so it
//           never steps when speed does). Only the VISIBLE pose smooths; mechanics stay instant.
//
// ── gait: normative sagittal joint angles over one stride, sampled every 12.5% (deg) ──
// phase 0 = heel strike; stance ≈ 0..0.60, swing ≈ 0.60..1.0 (signs: hip/knee +flexion,
// ankle +dorsiflexion). pub so the skeletal archer walks the SAME tables — the shared humanoid model.
pub const HIP_FLEX = [8]f32{ 25, 13, 3, -5, -10, -3, 12, 22 };
pub const KNEE_FLEX = [8]f32{ 5, 18, 10, 4, 10, 38, 62, 30 };
pub const ANK_DORSI = [8]f32{ -2, -6, 2, 9, 6, -14, -6, -1 };

// ── running gait (a distinct cycle, not a sped-up walk) ────────────────────────────
// Sagittal angles after Novacheck (1998) / Physiopedia running normatives: much larger
// ranges than walking, forefoot contact, stance ≈ 40% (toe-off near phase 0.4), big
// swing-knee flexion (heel toward buttock), a genuine flight phase (both feet airborne).
pub const RUN_HIP = [8]f32{ 42, 25, 8, -8, 5, 35, 60, 55 };
pub const RUN_KNEE = [8]f32{ 26, 48, 40, 28, 62, 98, 80, 44 }; // deeper bend throughout — coiled + low
pub const RUN_ANK = [8]f32{ -3, 10, 22, 2, -18, -6, 0, -2 };
// The run reads low + aggressive: a deep forward tilt over a low centre of gravity, with
// normal pumping arms (bent ~90°).
const RUN_LEAN = 24.0; // deep forward trunk lean when running (deg)
const RUN_ARM_SWING = 30.0; // shoulder swing amplitude when running (deg)
const RUN_ELBOW = 85.0; // elbows bent ~90° and pumping
const RUN_CROUCH = 0.06 * H; // pelvis drops — a low centre of gravity
const BODY_PITCH_RUN = 9.0; // whole-body forward pitch about the FEET at run — moves the centre of gravity ahead of the base
const BODY_PITCH_SPRINT = 18.0; // …more at sprint (falling-forward drive)
const HEAD_WALK = 7.0; // gentle downward head tilt at idle/walk — a natural "looking a few steps ahead" gaze
const GAZE_AHEAD = 15.0; // running: counter the lean down to ~this chain angle; final gaze ≈ GAZE_AHEAD+HEAD_WALK below horizontal (a few metres ahead), never craned up
const NECK_EXT_MAX = 34.0; // cap total head+neck extension so lifting the gaze can't hyperextend the neck
const A_RUN_BOUNCE = 0.05 * H; // vertical airtime lift during flight (up-only, so planted feet don't sink)
const RUN_SPEED_LO = 2.1; // blend walk→run across this ground-speed band
const RUN_SPEED_HI = RUN_SPEED; // …saturating exactly at run speed (sprintB takes over above)
const SPRINT_LEAN = 40.0; // near-horizontal forward tilt at full sprint (deg)
const SPRINT_REF_SPEED = SPRINT_SPEED; // speed the extra sprint lean/crouch saturate at

// ── THE SLOPE LEAN ── standing on or walking up sculpted ground, the whole body folds toward the hill
// (`Hero.slopePitch`, added to the run lean because it is the same motion about the same hinge — the
// feet). Without it a climb is an upright body sliding up a ramp, and a descent is the same thing
// backwards; the lean is most of what makes a hill read as a hill you are ON rather than in front of.
//
// A FRACTION of the slope, not a match. A body that pitched the full angle would be normal to the
// ground, i.e. leaning the same amount whether it is climbing or standing still, which reads as the
// character being welded to the terrain. Half of it is the posture of someone taking a hill on.
const SLOPE_LEAN: f32 = 0.55;
/// …capped, because the hero can stand on ground far steeper than he can walk up (`env.MAX_SLOPE`
/// governs travel, not standing), and a 40 deg fold at the waist reads as a stumble.
const SLOPE_LEAN_MAX: f32 = 16.0;
/// How fast the lean chases the ground, in degrees a second. Fast enough to be honest about a ridge,
/// slow enough that the 2.5 m lattice's slope changes do not step — and a VISUAL blend only, so the
/// FEEL RULES' ~0.1 s ceiling applies: at this rate the full 16 deg takes 0.13 s and any real change
/// in ground far less.
pub const SLOPE_LEAN_RATE: f32 = 120.0;

/// The body pitch a given uphill gradient asks for, in degrees. `rise` is metres of climb per metre
/// travelled along the facing (`env.slopeAlong`), so it is signed: downhill leans back.
pub fn slopeLean(rise: f32) f32 {
    const deg = mathx.degrees(std.math.atan(rise)) * SLOPE_LEAN;
    return mathx.clampF(deg, -SLOPE_LEAN_MAX, SLOPE_LEAN_MAX);
}

// ── dodge roll (committed tuck-and-somersault) ────────────────────────────────────
// Phased like FromSoft rolls: dive + somersault up front, then a spin-free recovery — NOT
// one linear spin/tuck/lunge smeared over the duration. Knots below are u = rollT / ROLL_DUR.
const ROLL_DUR = 0.70; // seconds, start to finish (souls medium-roll pacing, recovery included)
const ROLL_IFRAME_END = 0.46; // invulnerable from the FIRST frame to here (~ER medium, a shade
//   generous). The recovery tail stays vulnerable, so roll-catching still works on the hero.
const ROLL_DIST = 3.5; // ground units travelled
const ROLL_BALL_Y = 0.50; // pelvis/pivot height at mid-roll (the tucked "ball" centre)
const ROLL_TUCK_IN = 0.16; // dive: crouched + balled by here, spin barely begun
const ROLL_SPIN_A = 0.05; // somersault sweep: two OVERLAPPED eases, front-loaded. The
const ROLL_SPIN_M0 = 0.40; //   over-the-shoulder tumble (A..M1, ROLL_SPIN_OVER deg) hands
const ROLL_SPIN_M1 = 0.45; //   off to the slower unroll (M0..B); the full 360° lands here,
const ROLL_SPIN_B = 0.80; //   BEFORE the stand-up.
const ROLL_SPIN_OVER = 220.0; // degrees covered by the fast tumble segment
const ROLL_UNTUCK_A = 0.62; // legs extend to plant as the last of the spin lands…
const ROLL_UNTUCK_B = 0.97; // …spine/arms still settling as the roll hands off — never a parked stand
const ROLL_RISE_A = 0.70; // recovery: pelvis rises from ball height…
const ROLL_RISE_B = 1.00; // …back to full stance right at the end
const ROLL_BRAKE_A = 0.50; // travel: full lunge speed until here…
const ROLL_BRAKE_B = 0.92; // …then smooth-braked to a stop (ease-out, no float)
const ROLL_HIP = 95.0; // tuck: thighs to chest (deg)
const ROLL_KNEE = 115.0; // tuck: heels toward glutes (deg)
const ROLL_SPINE = 30.0; // forward spine curl per segment (deg)
const ROLL_HEAD = 32.0; // chin to chest (deg)
const ROLL_SHOULDER = 45.0; // arms tuck forward (deg)
const ROLL_ELBOW = 100.0; // elbows tucked (deg)
// Wabi-sabi: the somersault is imperfect like a real one — over ONE shoulder, banked and
// briefly off-square, limbs uneven, magnitudes drifting roll to roll. COSMETIC ONLY: none
// touch duration/distance/heading/timing — the dodge FEELS identical every time.
const ROLL_LEAN = 8.0; // bank toward the roll-side shoulder while balled (deg)
const ROLL_SKEW = 7.0; // peak off-square yaw through the recovery, squared up by the end (deg)
const ROLL_ARM_GUIDE = 1.25; // roll-side arm tucks harder across the body…
const ROLL_ARM_PUSH = 0.80; // …the other arm stays looser (factors on the arm tuck)
const ROLL_LEG_LEAD = 1.08; // lead leg balls tighter…
const ROLL_LEG_TRAIL = 0.92; // …trail leg lags looser (factors on the leg tuck)
const ROLL_VAR_LO = 0.7; // per-roll drift of the imperfection magnitudes (never of
const ROLL_VAR_HI = 1.3; //   duration/distance/heading — mechanics stay exact)
const ROLL_YAW_RATE = 22.0; // rad/s — the body whips onto the roll heading instead of teleport-snapping

// ── sword attacks (committed, one-handed) ───────────────────────────────────────────
// A cut is a KINETIC CHAIN released proximal → distal (pelvis → trunk rotation → trunk
// flexion → shoulder → elbow → wrist last, Bunn's summation-of-speed); each segment's strike
// span fires one LAG beat after the one before, so the arm WHIPS. Souls pacing: R1 fast/light
// (contact ~0.2s in, quick recovery), R2 a slow committed overhead — big windup, violent drop, blade BURIED through a held follow-through.
const ATK_LIGHT_DUR = 0.60; // R1: diagonal high-right → low-left slash (seconds)
const ATK_HEAVY_DUR = 1.00; // R2: overhead chop (seconds)
// light knots (u = atkT / dur)
const AL_WIND_B = 0.28; // a READABLE windup — long enough to register as anticipation
const AL_STRIKE_A = 0.28; // pelvis fires; chest/shoulder/elbow/wrist each lag AL_LAG more
const AL_STRIKE_B = 0.48;
const AL_LAG = 0.03;
const AL_RECOV_A = 0.62; // unwind to a stand across the tail
const AL_HIT_A = 0.32; // TAE-style ACTIVE window — the blade only hits inside it
const AL_HIT_B = 0.56;
const AL_LUNGE = 0.55; // ground units stepped into the cut — a real committed step-in (ER R1 pressure)
const AL_CHAIN = 0.80; // u where a BUFFERED action may take over: the swing has visually
//   resolved but the stand-down tail is skippable, so mashed R1s flow into a combo.
// heavy knots
const AH_WIND_B = 0.34; // slow raise to overhead — the R2 anticipation "tell"
const AH_STRIKE_A = 0.38; // …a beat of hang at the top, then the drop
const AH_STRIKE_B = 0.52;
const AH_LAG = 0.025;
const AH_RECOV_A = 0.72; // impact holds buried 0.52..0.72, then the slow rise
const AH_HIT_A = 0.40;
const AH_HIT_B = 0.58;
const AH_LUNGE = 1.05; // the chop LEAPS forward through the drop — committed reach, ER-style
const AH_CHAIN = 0.86; // the heavy earns a longer commitment before a buffered exit
const ATK_RETRACK = 9.0; // rad/s — LOCKED-ON only: past RECOV_A the hero re-squares onto the
//   lock target through the tail, so a WHIFF doesn't leave him facing empty air. The cut itself stays fully committed.
// ── CUT MECHANICS (the light slash) — from period cutting instruction ────────────────
// The R1 is the HORIZONTAL cut: sabre Cuts III/IV (Roworth 1798; kendo's dō-giri), a one-handed LEVEL
// swipe across the front at chest height. Owner's law: a swipe, never a downward poke. Four rules:
//  - THE ARC IS ROTATION, NOT ELEVATION — hips/trunk rotate and the shoulder YAWS about the body's
//    vertical axis (~125° plus ~50° of trunk). The forward-raise only holds the plane at chest height.
//  - THE BLADE LIES FLAT, EDGE LEADING (Hutton 1889). The SWORD bone cancels the baked grip cant
//    exactly, then the wrist rolls a quarter-turn about the blade's own axis — cone-free BECAUSE of
//    that cancel. Ramped in with the raise and drained through recovery, so the carry never changes.
//  - PROXIMAL → DISTAL, WRIST LAST (Bunn's summation of speed): the AL_LAG chain, pelvis → wrist.
//  - IT ARRESTS, NEVER PARKS (tenouchi). A chained light comes BACKHAND out of the finish (Cut IV out
//    of Cut III), chambering shallow where the forehand landed.
// light amplitudes (deg unless noted)
const AL_BODY_YAW = 26.0; // trunk winds HARD toward the sword side (the exaggerated tell)…
const AL_BODY_YAW_THRU = 24.0; // …and releases through past neutral (rotation IS the cut's width)
const AL_SH_ELEV_WIND = 55.0; // forward-raise at the chamber: fist at shoulder height…
const AL_SH_ELEV = 79.0; // …rising to hold the sword OUT near-horizontal through the strike —
//   the swipe plane (the fat BLADE_R pill supplies the low-toad reach below it)
const AL_SWEEP_WIND = 72.0; // shoulder yaw wound around BEHIND the sword shoulder at the chamber…
const AL_SWEEP_END = 64.0; // …released to past the OFF shoulder — ~136° of pure horizontal sweep
const AL_ALT_WIND = 0.62; // the backhand return chambers SHALLOWER (a cross-body wind out of the forehand's finish — full depth would bury the fist in the chest)
const AL_ELBOW_WIND = 96.0; // deep fold — the blade lies back over the shoulder at the chamber
const AL_ELBOW_STRIKE = 8.0; // arm out LONG for the whole pass (fires with the raise): the blade
//   rides the OUTER EDGE of the swipe radius, tip farthest out — never hilt-first
const AL_WRIST_LAY = 18.0; // wrist deviation: the blade trails back at the CHAMBER only, released
//   early in the pass so the window sweeps near-RADIAL (blade in line with the long arm)…
const AL_WRIST_WHIP = 12.0; // …whipping to lead a touch past straight at the exit
const AL_EDGE_ROLL = 90.0; // the swipe RE-GRIPS: roll the blade a quarter-turn about its OWN
//   axis so the EDGE LEADS and the FLAT lies in the swipe plane (owner's law + Hutton's rule).
//   Cone-free because the SWORD bone first cancels the grip cant exactly, putting the blade dead on the wrist's roll axis.
const AL_TIP_UP = 10.0; // then a whisker of tip-high (applied -^'rx: more-negative = higher in the
//   chain's pitch sum) so the line sits just above level after the body's forward commit
const AL_SPINE_CRUNCH = 2.5; // a horizontal cut ROTATES — barely any forward commit (keeps the
//   swipe PLANE flat instead of tipping it toward the ground mid-strike)
const AL_OVER = 6.0; // follow-through overshoot past the end pose, settling through recovery (the arrest, not a park)
const AL_LOAD = 0.016 * H; // the knees coil DOWN under the windup (anticipation you can feel)…
const AL_DIP = 0.015 * H; // …and a slight settle into the stance on release
// heavy amplitudes
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
const AH_DIP = 0.05 * H; // …and the weight drops into the impact
const AH_PITCH = 9.0; // whole-body forward pitch about the feet through the strike
// Blade hitbox, souls-style: a capsule on the SWORD bone's dummy points (guard → tip),
// ACTIVE only inside the HIT window, with last-frame endpoints kept for swept tests so a
// fast arc can't tunnel between frames. One hit per swing per target: the (future) hit list clears on the activation edge, where the sweep history also resets.
pub const BLADE_R = 0.34; // capsule radius (world units) — a FAT hit volume, far past the
// visible mesh (invisible in play, debug-wired only). VERTICAL forgiveness: the chest-height
// arc (~1.25m) must reach well below the blade to land LOW enemies (a toad's hurt sphere tops ~1.1m) and above for tall ones — thin pills read as whiffs on clean-looking hits.

// ── the swing trail (juice: a fading steel ribbon the blade paints through a cut) ──────
// Samples the outer blade span each frame the TIP moves; drawn as unlit alpha strips in
// the lit pass only (no shadow, never the depth pass). Short-lived — a crack of motion, not a smoke plume.
const TRAIL_N = 20; // ring capacity (~0.3 s of samples at 60 fps)
const TRAIL_LIFE = 0.20; // seconds a sample persists (long enough that the full level arc
//   still reads as one sheet at the swing's exit)
const TRAIL_MIN_SWEEP = 0.05; // world units the tip must move in a frame to leave a sample
const TRAIL_ROOT = 0.35; // ribbon spans this fraction down the blade → the tip
const TRAIL_COL = rgba(224, 230, 244, 255); // pale steel flash (alpha set per segment)
const TrailSample = struct { a: rl.Vector3 = mathx.zero3, b: rl.Vector3 = mathx.zero3, age: f32 = mathx.LONG_AGO };

// ── combat vitals + what the hero's cuts deal (Elden Ring model, see docs/ELDEN_RING.md) ─
// The hero is sturdier than a toad: mid-weight poise (~ER's Knight-set 51) so a couple of
// bites shrug off, but sustained pressure still flinches then staggers him.
pub const HP_MAX = 70.0; // lowered from 100 — a few solid blows now kill (owner: raise the stakes)
pub const POISE_MAX = 55.0;
pub const STANCE_MAX = 90.0;
// Poise/stance dealt by the cuts (HP damage rides alongside). The R2 is the heavier hit and
// chips STANCE directly (ER: heavies break stance far faster than lights).
pub const ATK_LIGHT_HIT = combat.Hit{ .dmg = 13, .poise = 10 };
pub const ATK_HEAVY_HIT = combat.Hit{ .dmg = 27, .poise = 22, .stance = 14 };

// ── stagger + death anims (the reactions; committed like attacks/rolls) ──────────────────
// A flinch is a BIG, unmistakable jolt — the whole upper body snaps back, the head whips,
// the arms fly up, the knees buckle and he stagger-steps back off the blow. Not a lean.
const HURT_LEAN = 40.0; // light flinch: torso snaps back this far (deg)
const HURT_HEAD = 52.0; // …head whips back with it
const HURT_STEP = 0.18 * H; // …and he's knocked a step back off the blow
const STAG_LEAN = 42.0; // heavy stagger: a deep reeling arch back (deg)
const DEATH_SINK = 0.30; // death: pelvis sinks to this fraction of stance height
pub const DEATH_DUR = 3.6; // collapse + lie still before the hero respawns — long enough for
//   the full YOU DIED choreography (game.zig's overlay reads deathT against this)

// ── the grip (how the sword is HELD) ────────────────────────────────────────────────
// A hammer grip cants the blade GRIP_PITCH forward of the forearm line — held at an angle,
// never splinted straight along it. Baked into the sword MESH (about the fist centre) and the capsule dummy points, so every pose and swing inherits the cant.
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
// HIT capsule endpoints — extended PAST the visible blade for reach forgiveness (the mesh is
// unchanged): the base pulls back through the fist so close-in swipes connect, and the tip
// reaches beyond the point so the far end of the arc lands.
const BLADE_BASE = bladeAt(-0.06); // guard end, pulled back toward/through the fist
const BLADE_TIP = bladeAt(0.64); // point, extended past the visible tip for reach (the far end of the arc lands)

// The sword arm is a CARRY, not a mirror of the free arm (see armChain).
const CARRY_DAMP = 0.45; // fraction of the gait swing the sword arm gives up
const CARRY_ELBOW = 14.0; // readier standing/walking elbow on the sword side
const CARRY_ELBOW_RUN = 30.0; // at a run the carry arm keeps a readier bend (kept close to the body, not folded to the chest)
const CARRY_WRIST_LIFT = -54.0; // the RUN tip-lift — pitches the wrist so the blade rides off the floor, tip AWAY; kept modest so it stays a bit low, not skyward
const CARRY_LIFT_WALK = 0.4; // a WALK gets only this fraction of the run's tip-lift — blade sits LOWER at a walk, rising to full at a run
const CARRY_ABD_RUN = 12.0; // only a small extra abduction at a run — the ARM stays tight to the body (the blade points out via the WRIST, not by flinging the arm)
const CARRY_WRIST_YAW = -48.0; // at a run, YAW the wrist so the BLADE alone angles out to the RIGHT off the flank (the "ninja run" read) — the arm doesn't move
const CARRY_SWING_STILL = 0.6; // damp — but don't kill — the carry arm's fore/aft pump at a run: it still swings a bit (he's only human), just less than the free arm

// ── short transition blends (nothing snaps between stances) ────────────────────────
const POSE_XFADE = 0.09; // seconds — cross-fade over any pose discontinuity (roll start/end)
const SPEED_SMOOTH = 80.0; // units/s² — posture-blend speed chases ground speed, so
//   lean/crouch/arm-pump glide instead of stepping. Movement + stride phase stay on RAW
//   speed (responsiveness untouched). Owner's call: VERY fast (~0.04s) — the stick IS the speed; the glide only kills the step.

// ── locked-on footing: strafe + backpedal (the gait follows travel RELATIVE TO FACING) ──
// Gait splits by travel in the BODY frame: the forward component scales the sagittal
// leg/arm work (TIME-REVERSED for a backpedal, Thorstensson 1986), the lateral component
// drives a real CROSSING SIDESTEP (the grapevine below). Direction blends ease fast (visuals
// only, ~0.1s; position answers the stick raw, same frame).
const GAIT_DIR_EASE = 22.0; // 1/s — fwdB/latB chase the body-frame travel direction
//
// ── THE CROSSING SIDESTEP (grapevine): GEOMETRY, NOT TUNED ANGLES ──────────────────────────
// Two facts drive it, and either one wrong is what makes a sidestep slide:
//
// 1. A PLANTED FOOT IS WORLD-FIXED. Its offset from the pelvis sweeps backward through stance LINEAR
//    IN DISTANCE. A constant joint angle is only still in JOINT space; in world space the foot is
//    dragged under the body, and that skate — not the amplitude — is the bug.
// 2. THE CROSS IS FREE, out of the HIP OFFSETS. Both legs take the SAME symmetric ±STRAFE_ABD sweep
//    half a cycle apart; because each hip sits `hx` off the midline the far leg lands PAST the near
//    foot. No lead/trail split — giving the crossing leg less reach is backwards, since it has ~2·hx
//    further to go.
//
// Peak hip abduction through a lateral shuffle is ~17-20 deg (Sinclair et al. 2016), so STRAFE_ABD is
// a measured range, not a splay.
const STRAFE_ABD = 22.0; // peak frontal hip swing either side of the hip (deg) — the sweep is
//   symmetric, so this is BOTH the out-step's abduction and the cross's adduction
const STRAFE_STANCE = 0.52; // fraction of the cycle each foot is planted (~4% double support)
//   CADENCE HAS EXACTLY ONE DIAL: phase is driven by DISTANCE, so cadence = speed / STRAFE_CYCLE.
//   Pace it any other way and the planted foot skates. Slowing a too-fast sidestep means LENGTHENING
//   the cycle — and the cycle is capped by hip ROM with no double support left to trade, so pure
//   lateral travel still costs ~20% more steps/sec than walking forward. That residue is geometry.
const STRAFE_CROSS = 38.0; // the crossing leg's hip FLEXION peak — it must pass IN FRONT of the stance
//   leg, and this big because the knee flexion that buys clearance drags the ankle BACKWARDS (~24 left
//   the foot trailing while the thigh crossed in front of it).
const STRAFE_BEHIND = 10.0; // …and its partner's hip EXTENSION peak, passing BEHIND on the uncross.
//   One leg front-crossing plus one passing behind IS the grapevine, structurally.
const STRAFE_LAND = 7.0; // fore/aft hip offset at plant (deg), swept out linearly through stance:
//   a front cross lands a little AHEAD of the stance foot, then the body travels past it
const STRAFE_CLEAR = 0.035 * H; // DAYLIGHT under the swing foot at mid-swing. Asked for as a
//   HEIGHT and solved for (see legChain), not tuned as a knee angle: hip flexion and knee flexion
//   fight each other vertically, so a "knee lift" constant does not mean a foot leaves the ground.
const STRAFE_SINK = 0.0055 * H; // how much SHORTER than dead-straight the leg is left at full
//   abduction — i.e. the residual knee bend at the widest point of the step (~12 deg). Feeds
//   STRAFE_DIP, and it is what keeps the stance springy rather than locked out on straight poles
//   (owner's note); the knee opens up further as the leg comes back under the body.
const STRAFE_PROT = 7.0; // pelvic TRANSVERSE rotation (deg): the crossing hip swings FORWARD to
//   carry that leg around the stance leg. Real crossovers are pelvis-driven, not hip-driven.
const STRAFE_SWAY = 0.012 * H; // pelvis rides ONTO each planting foot (the weight transfer
//   is what makes a sidestep read as steps, not a slide) — a bit above the walk's sway
const STRAFE_LEAN = 2.5; // torso banks gently INTO the travel side (deg, cosmetic)
const BACK_STRIDE = 0.85; // backpedal steps shorten a touch too (cautious, toe-reaching)

// Rest hip→ankle span: the strafe geometry is all measured off this, so it scales with the rig.
// (`unit_leg_len_matches_rig` re-asserts it against restPositions, and the archer/ogre keep the
// hero's leg fractions on purpose, so their rest-derived leg length agrees — scale aside.)
pub const LEG_LEN = (0.530 - 0.039) * H;
// ── derived, so a retune of STRAFE_ABD/STANCE can never silently desync the three of them ──
const STRAFE_REACH = LEG_LEN * @sin(mathx.radians(STRAFE_ABD)); // half the stance sweep, in units
const STRAFE_CYCLE = 2.0 * STRAFE_REACH / STRAFE_STANCE; // body travel per FULL cycle. advanceGait
//   MUST use this as the stride length for a pure sidestep: phase and sweep are two views of the
//   same distance, and if they disagree by any factor the skate comes straight back.
// Pelvis drop, SOLVED not picked: at full abduction the foot is STRAFE_REACH out to the side and
// still has to touch the floor, so the pelvis must sit low enough that a near-straight leg spans
// the hypotenuse. Falls out as ~4% of H — which is also where the soft knee comes from. legChain's
// vertical solve assumes the caller dropped the pelvis by exactly this much; that is the contract,
// and `strafe: planted feet stay ON the ground` holds both ends to it. pub because every humanoid
// that strafes owes the same drop, scaled by its own rig (the archer once had none, and hovered).
pub const STRAFE_DIP = LEG_LEN - @sqrt((LEG_LEN - STRAFE_SINK) * (LEG_LEN - STRAFE_SINK) - STRAFE_REACH * STRAFE_REACH);

const STRIDE = 0.85 * H; // ground distance per full (two-step) cycle at walk pace — ties phase to travel, no foot-skate
const WALK_REF_SPEED = WALK_SPEED; // reference walk speed the stride is tuned for
const ARM_SWING = 9.0; // shoulder flex amplitude (deg) at walk — restrained, contralateral to the legs
/// Vertical pelvis travel (peak-to-peak ~ realistic 4-5 cm at H=1.8). pub for the same reason
/// SEG_THIGH/SEG_SHANK and HIP_ADDUCT are: a humanoid foe that wants the hero's walk needs the
/// hero's AMPLITUDE too, and archer.zig held a byte-identical copy under a comment saying so —
/// which is a number that must agree, written down twice, waiting for the first retune. (The
/// OGRE's 0.030 is deliberately its own: a giant's swagger, like its wider A_PROT.)
pub const A_BOB = 0.024 * H;
const A_SWAY = 0.009 * H; // lateral pelvis sway toward the stance foot (subtle — no waddle)
const A_PROT = 3.5; // pelvic transverse rotation (deg)
const A_LIST = 2.0; // pelvic frontal drop toward the swing leg (deg)
const TORSO_LEAN = 3.0; // forward torso lean while walking (deg) — walking is near-upright
// pub: humanoid enemies (the ogre's braced idle stance) reuse these so their standing legs
// line up EXACTLY with the shared walk (legChain) at the hand-off — no silent drift.
pub const HIP_ADDUCT = 2.0; // constant leg-toward-midline angle so the stance narrows (deg)
pub const FOOT_TOEOUT = 6.0; // feet splay slightly outward (Fick angle) — a real standing/gait detail
const ARM_ABD = 9.0; // constant arm abduction so arms clear the torso (deg)
pub const IDLE_KNEE = 4.0;
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

// Advance the shared humanoid GAIT STATE one frame — the single source of walk/strafe for the
// hero AND every humanoid enemy (AGENTS.md humanoid rule); eases the posture blends (`moving`,
// `speedS`) and body-frame travel direction (`fwdB`/`latB`, splitting sagittal walk from the
// strafe in legChain), and accumulates stride `phase` by DISTANCE (never time) so feet never
// skate. Pointers, not a struct, so a caller's gait fields plug in with no refactor.
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
        // Sagittal strides lengthen with speed; the SIDESTEP's cycle is FIXED at STRAFE_CYCLE,
        // because legChain's stance sweep is measured in UNITS off the leg — scale one without the
        // other and the planted foot skates again. So a faster sidestep raises the CADENCE, not the
        // step length, which is also how a real shuffle answers speed once abduction is maxed out.
        const sagLen = STRIDE * mathx.clampF(0.55 + 0.45 * speed / WALK_REF_SPEED, 0.8, 2.0) *
            mathx.lerpF(1.0, BACK_STRIDE, mathx.maxF(0, -fwdB.*));
        const strideLen = mathx.lerpF(sagLen, STRAFE_CYCLE, @abs(latB.*));
        phase.* += movedDist / strideLen;
    }
    phase.* -= @floor(phase.*);
}

// ── FOOT PLANT: keep soles ON the ground instead of through it ─────────────────────────────────
// An FK gait drives JOINT ANGLES, so pelvis height and feet only relate through the bob curve, and
// wherever they disagree the sole goes under the world. Worst where a rotating foot digs a corner in:
// the boot is ~0.19·H long, so 15 deg of ankle pitch buries a toe 4 cm with the ankle sitting right.
//
// LEVEL THE ANKLE, NEVER LIFT THE BODY (`legChain`, and AGENTS.md's law). Measure the deepest sole
// corner against the rig's patch and rotate the ANKLE just enough to clear it. Both whole-body fixes
// were tried and reverted: translating the skeleton judders, because which corner is deepest changes
// frame to frame, and holding the pelvis up cancels RUN_CROUCH. A whole-body correction to a local
// problem always reads as a tremor.
//
// A rig declares each ground-contact bone as a sole PATCH — the rectangle its sole occupies in that
// bone's local frame. MEASURE it off the mesh (`addCube` takes a FULL size, `addCapsule`/`addBlob`
// take true RADII — mixing those up put the ogre's foot pad 0.036·H below its own sole plane).
//
// Soles are authored at y = 0 while the ground surface sits a hair above at `env.GROUND_Y`, so
// planting to 0 keeps the deliberate ~1 cm embed: planted, never floating.
pub const SOLE_Y: f32 = 0.0;

pub const SolePatch = struct {
    bone: usize,
    heel: f32, // how far the sole reaches BEHIND the bone origin (-^'z)
    toe: f32, //  …and ahead of it (+z)
    halfW: f32,
    drop: f32, // how far BELOW the bone origin the sole plane sits (the ankle joint height)
};

// The deepest point any of these soles reaches. Measurement only — nothing is moved.
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

// The hero's own boot footprint, measured off `footMesh`: the sole cube spans z −0.05·H…+0.14·H and
// x ±0.0425·H, and its underside lands exactly on the ankle-height plane.
pub const BOOT_SOLE = [_]SolePatch{
    .{ .bone = ANKL, .heel = 0.05 * H, .toe = 0.14 * H, .halfW = 0.0425 * H, .drop = 0.039 * H },
    .{ .bone = ANKR, .heel = 0.05 * H, .toe = 0.14 * H, .halfW = 0.0425 * H, .drop = 0.039 * H },
};

// The sidestep's PELVIS drive — pub so the hero and every humanoid foe counter-rotate identically
// (AGENTS.md's humanoid rule covers the TRUNK, not just the legs). A real crossover is pelvis-led:
// the CROSSING hip swings FORWARD to carry that leg around the stance leg, and legs alone under a
// square pelvis is what leaves a sidestep looking like the feet are doing it by themselves.
// Returns degrees of pelvic ry, peaking on the crossing foot's plant. It needs no `lat` sign flip:
// the crossing leg swaps sides at exactly the phase where cos(tau·ph) swaps sign, so one
// expression covers both directions (left leg crosses travelling right, right leg travelling left).
pub fn strafeProt(ph: f32, lat: f32, m: f32) f32 {
    return -STRAFE_PROT * mathx.cosf(std.math.tau * ph) * @abs(lat) * m;
}

// The sidestep's pelvic SWAY amplitude. Weight has to sit over whichever foot is in single support,
// and which leg that is does NOT depend on travel direction — so a strafe keeps the walk's sway
// PHASE and only opens the amplitude up. (The old term was `lat`-signed and cos-phased, i.e. it
// leaned the wrong way half the cycle and peaked in double support, when the weight is centred.)
pub fn strafeSway(latW: f32, runB: f32) f32 {
    return mathx.lerpF(A_SWAY * (1.0 - 0.6 * runB), STRAFE_SWAY, latW);
}

// matrix shorthand — the shared raylib TRS helpers (MatrixMultiply(a,b) applies a FIRST
// then b); defined once in mathx so the convention can't drift between the rigs.
const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
// Component-wise matrix blend — fine for the few frames of a POSE_XFADE cross-fade (the
// tiny mid-blend shear is invisible that briefly, and both endpoints are exact poses).
fn lerpM(a: rl.Matrix, b: rl.Matrix, t: f32) rl.Matrix {
    var out: rl.Matrix = undefined;
    inline for (@typeInfo(rl.Matrix).@"struct".fields) |f| {
        @field(out, f.name) = mathx.lerpF(@field(a, f.name), @field(b, f.name), t);
    }
    return out;
}

/// WHERE THE FEET ARE, as the last matrix of every root chain. It was `tr(pos.x, 0, pos.z)` written out
/// in all seven poses (walk, roll, attack, drink, stun, death…), which is seven places to forget when
/// the ground stopped being flat — and a rig that misses one sinks into the hill in exactly one state.
/// Any rig whose actor stands on terrain uses this; there is nothing hero-specific about it.
pub fn rootAt(pos: rl.Vector3) rl.Matrix {
    return tr(pos.x, pos.y, pos.z);
}

// A smooth 0→1→0 pulse over [a, b] — the overshoot/recoil grace notes that keep a strike
// from parking dead at its end pose (the wooden-mannequin failure).
fn bump(u: f32, a: f32, b: f32) f32 {
    const mid = 0.5 * (a + b);
    return mathx.smoothstep(a, mid, u) * (1.0 - mathx.smoothstep(mid, b, u));
}

pub const Attack = enum { light, heavy };

// One buffered action, ER-style: an attack/roll pressed while mid-action QUEUES here —
// ONE slot, the LAST press wins (a new press replaces the old) — and fires at the
// current action's earliest legal exit (the attack's chain knot, or the roll's end).
// Nothing cancels mid-flight: souls commitment, souls leniency.
pub const Queued = union(enum) { attack: Attack, roll: rl.Vector3 };

pub const Hero = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,
    rest: [N]rl.Vector3,
    xf: [N]rl.Matrix = undefined, // per-bone world matrix, recomputed each frame by pose()

    // gameplay/anim state
    /// Feet on the GROUND: x/z where he stands, y the terrain height under him (0 on a flat map, so
    /// this is unchanged for an unsculpted world). Every pose translates the root by all three — see
    /// `rootAt` — and the camera, the blade capsule and every world point follow from that.
    pos: rl.Vector3 = mathx.zero3,
    /// Whole-body pitch from the SLOPE he is standing on, in degrees, + = uphill ahead (lean into the
    /// climb). Set by the loop from the terrain gradient along his facing and eased there, not here:
    /// the rig is told what the ground is doing, it does not go looking.
    slopePitch: f32 = 0,
    facing: f32 = 0, // yaw radians, 0 = +Z
    phase: f32 = 0, // stride phase [0,1) (left-leg reference)
    moving: f32 = 0, // eased 0..1 walk blend
    speed: f32 = 0, // this frame's ground speed (world units/sec) — for HUD + stride scaling
    fwdB: f32 = 1, // eased travel-vs-facing FORWARD component (+1 ahead … -^'1 backpedal)
    latB: f32 = 0, // eased travel-vs-facing LATERAL component (+1 = stepping to his RIGHT)
    elapsed: f32 = 0,
    // dodge roll
    rolling: bool = false,
    rollT: f32 = 0, // seconds into the current roll
    rollDir: rl.Vector3 = mathx.zero3, // world XZ unit direction of the roll
    rollYaw: f32 = 0, // committed heading of the roll; the visible yaw eases onto it fast
    rollSide: f32 = -1, // +1 = over the LEFT shoulder, -1 = the RIGHT (picked from the leading leg)
    rollVar: f32 = 1, // this roll's imperfection magnitude (ROLL_VAR_LO..HI, cosmetic only)
    // sword attack
    attacking: bool = false,
    atkT: f32 = 0, // seconds into the current swing
    queued: ?Queued = null, // the ER-style input buffer (see Queued)
    atkHeavy: bool = false, // which cut: R1 slash (false) or R2 overhead (true)
    atkAlt: bool = false, // light-combo alternator: false = forehand slash, true = the RETURN backhand
    /// HOW MANY SWINGS HE HAS THROWN, ever. Wraps, and nothing minds — it exists so a caller can see
    /// a swing BEGIN, which the `attacking` flag cannot tell it: a chained combo clears that flag and
    /// sets it again inside ONE frame (see `updateAttack`'s buffered exit), so watching its rising
    /// edge heard the first R1 of a mashed combo and none of the rest. Counted, like `stamRefused`.
    swings: u32 = 0,
    bladeA: rl.Vector3 = mathx.zero3, // blade capsule endpoints in WORLD space (guard → tip)
    bladeB: rl.Vector3 = mathx.zero3,
    bladeA0: rl.Vector3 = mathx.zero3, // …last frame's endpoints, for swept-capsule hit tests
    bladeB0: rl.Vector3 = mathx.zero3,
    hitWasActive: bool = false, // edge detector: sweep history (+ future hit list) resets on activation
    trail: [TRAIL_N]TrailSample = [_]TrailSample{.{}} ** TRAIL_N, // swing-trail ring (newest at trailHead)
    trailHead: usize = 0,
    // combat
    vit: combat.Vitals = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX),
    stam: combat.Stamina = .{}, // ER's third bar — the hero's alone; foes don't carry one
    fp: combat.Focus = .{}, // …the blue one, likewise. Nothing spends it yet; the Cerulean fills it
    runes: combat.Runes = .{}, // …and ER's currency, likewise his alone (souls, by ER's name)
    flasks: combat.Flasks = .{}, // Crimson + Cerulean, sharing the quick-item slot
    // THE DRINK, committed like an attack (see combat.Flasks): the charge is spent at the START,
    // the restore lands at FLASK_POUR_AT, and a stagger mid-draught costs you the flask.
    drinking: bool = false,
    drinkT: f32 = 0,
    poured: bool = false,
    /// Seconds left on the "that was refused" flash. An empty-bar input does NOTHING in ER, and
    /// nothing is indistinguishable from a dropped frame — which, under a ZERO INPUT LAG law, is
    /// the one thing the player must never have to wonder about. So the refusal is SHOWN, on the
    /// bar that caused it. It changes no mechanics: this is a light on the dashboard.
    /// Set it through `refuse()`, never by hand — see there.
    stamRefused: f32 = 0,
    sprinting: bool = false, // hold-B RUN, resolved by the caller — the only CONTINUOUS drain
    // THE WORLD IS HELD (menu up). He keeps breathing, but his COMBAT clocks must not run:
    // the live loop already freezes vit/hurtFlash by simply not ticking them, and stamina rides
    // tickClocks instead, so without this it is the one meter that keeps moving under a pause —
    // bleeding on a sprint you paused mid-stride, and refilling for free the rest of the time.
    held: bool = false,
    stun: combat.StunKind = .none, // .light flinch / .heavy stagger (a committed reaction)
    stunT: f32 = 0, // seconds into the current stagger
    hurtFlash: f32 = 0, // 0..1 red damage-flash intensity (set on any hit, decays) — HUD reads it
    dead: bool = false,
    deathT: f32 = 0, // seconds into the death collapse (respawns at DEATH_DUR)
    spawnPos: rl.Vector3 = mathx.zero3, // where a death respawns the hero
    spawnFacing: f32 = 0,

    // transition smoothing
    speedS: f32 = 0, // short-eased ground speed driving POSTURE blends only
    blendT: f32 = mathx.LONG_AGO, // seconds since the last pose discontinuity (… POSE_XFADE = no blend)
    blendXf: [N]rl.Matrix = undefined, // frozen source pose for the cross-fade

    pub fn init(shader: rl.Shader) Hero {
        var mat = rl.loadMaterialDefault() catch @panic("hero material");
        mat.shader = shader;
        return .{
            .mesh = buildMeshes(),
            .mat = mat,
            .rest = restPositions(),
        };
    }

    pub fn setShader(self: *Hero, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    // Advance the walk. `movedDist` = ground distance travelled this frame; `speed` its
    // rate; `moveYaw` the world heading of travel (null when idle) — against `facing` it
    // shapes the locked-on strafe/backpedal gait. Phase is driven by DISTANCE (not time)
    // so the feet never skate.
    // The prologue EVERY per-frame advance path owes: the clock, the swing trail's fade, and the
    // cross-fade timer. Exactly one of update/updateRoll/updateAttack/updateStun/updateDeath runs
    // each frame, and each had its own copy of these three lines.
    fn tickClocks(self: *Hero, dt: f32) void {
        self.elapsed += dt;
        self.ageTrail(dt);
        self.blendT = @min(self.blendT + dt, mathx.LONG_AGO);
        // Stamina belongs in the prologue for the same reason the others do: it must advance
        // exactly ONCE per frame whichever path is running, and hanging it off the live loop
        // instead would leave --shot draining every swing it takes and never refilling.
        // ER pauses the refill while attacking, sprinting or blocking. ROLLING counts too: the
        // bite is charged at the dive and the pool must not start climbing back before he is on
        // his feet, or a roll chain costs less than the sum of its rolls.
        if (!self.held) self.stam.tick(dt, self.sprinting, self.attacking or self.rolling);
        self.stamRefused = @max(0, self.stamRefused - dt);
        // The rune counter's ROLL. In the prologue for the same reason as the rest: it must advance
        // exactly once per frame whichever path is running. NOT gated on `held` — it is a display
        // animation, not a combat clock, and a counter frozen mid-tally under the pause menu reads
        // as the payout having been dropped.
        self.runes.tick(dt);
    }

    pub fn update(self: *Hero, dt: f32, movedDist: f32, speed: f32, moveYaw: ?f32) void {
        self.tickClocks(dt);
        self.speed = speed;
        // The shared humanoid gait engine drives phase + the posture/direction blends (also
        // used by the skeletal archer + any humanoid foe — one source of walk/strafe feel).
        advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist, speed, moveYaw, self.facing);
    }

    // Begin a dodge roll in world direction `dir` (falls back to current facing). Ignored
    // while already rolling OR mid-attack — both are committed (mirrors startAttack's guard,
    // so a stray call can't leave rolling+attacking latched together).
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
        self.rollT = 0;
        self.rollDir = d;
        self.rollYaw = mathx.headingXZ(d); // heading committed NOW; the visible yaw whips onto it
        // Wabi-sabi, cosmetic only: roll over the shoulder of whichever leg is leading
        // (as a real forward roll does; right by habit from a standstill), and drift the
        // imperfection magnitudes so no two rolls read identical.
        const leadL = sampleCurve(HIP_FLEX, self.phase) > sampleCurve(HIP_FLEX, self.phase + 0.5);
        self.rollSide = if (self.moving > 0.5 and leadL) 1.0 else -1.0;
        // elapsed in the mix so standstill rolls (frozen phase) still vary roll to roll.
        const h = (self.phase + self.elapsed * 0.61) * 7.31;
        self.rollVar = mathx.lerpF(ROLL_VAR_LO, ROLL_VAR_HI, h - @floor(h));
        self.startXfade(); // last frame's pose cross-fades into the dive — no snap
    }

    // Advance an in-progress roll: committed ease-out travel + pose. Call in place of the
    // normal move/update while `rolling` is true; `bounds` clamps position like moveHero.
    pub fn updateRoll(self: *Hero, dt: f32, bounds: f32) void {
        self.tickClocks(dt);
        self.facing = mathx.approachAngle(self.facing, self.rollYaw, dt * ROLL_YAW_RATE); // whip, don't teleport
        const u = mathx.clampF(self.rollT / ROLL_DUR, 0, 1);
        // Lunge: full speed through the dive + somersault, smooth-braked through the
        // recovery. The profile's integral over u is (BRAKE_A+BRAKE_B)/2, so the peak
        // normalizes to keep total travel = ROLL_DIST.
        const peak = ROLL_DIST / (ROLL_DUR * 0.5 * (ROLL_BRAKE_A + ROLL_BRAKE_B));
        const speed = peak * (1.0 - mathx.smoothstep(ROLL_BRAKE_A, ROLL_BRAKE_B, u));
        const moved = speed * dt;
        mathx.stepXZ(&self.pos, self.rollDir, moved, bounds);
        self.speed = speed;
        self.speedS = mathx.approach(self.speedS, speed, dt * SPEED_SMOOTH);
        self.rollT += dt;
        // Pose BEFORE clearing `rolling`: on the frame the roll completes, poseRoll (with u
        // clamped to 1 = a fully-risen stand) must still run, else pose() falls to the
        // walk branch and pops a stale-phase stance for one frame.
        self.pose();
        if (self.rollT >= ROLL_DUR) {
            self.rolling = false;
            // `moving` is deliberately NOT reset: held input keeps trucking straight out
            // of the rise (update() eases it down naturally if the stick is free).
            self.startXfade(); // the rise cross-fades into whatever comes next
            self.fireQueued(); // a buffered attack/roll chains straight off the rise
        }
    }

    // ── ER-style input queue ─────────────────────────────────────────────────────────
    // The public entry for player action input: act NOW if free, else buffer the press
    // (one slot, last press wins). game.zig routes a same-frame roll press here INSTEAD
    // of the attack press (rolls win the frame), and steers a queued roll every frame so
    // it leaves in the direction held when it fires — both Elden Ring behaviors.

    /// IS HE COMMITTED TO SOMETHING? The one place that answers it, because the three committed
    /// actions have to be asked about together or one of them gets forgotten — and the DRAUGHT was.
    /// It was absent from every guard below, so an attack or roll pressed mid-drink skipped the
    /// buffer and started immediately: the swing charged its stamina and sat latched behind the
    /// drink, and a ROLL actually ran (the frame dispatch tries `rolling` first) with `drinking`
    /// still set, so the draught silently resumed — and could still pour — once the roll ended.
    /// `updateDrink` calling `fireQueued` was the tell: nothing could ever be in the queue.
    pub fn committed(self: *const Hero) bool {
        return self.rolling or self.attacking or self.drinking;
    }

    /// THAT INPUT DID NOTHING, and the player is told so. Four call sites were each re-stating
    /// `self.stamRefused = combat.STAM_REFUSE_FLASH`, which is the sort of line that gets copied
    /// into a fifth refusal and then quietly left out of a sixth — and a refusal nobody can see is
    /// exactly the failure the flash exists to prevent.
    fn refuse(self: *Hero) void {
        self.stamRefused = combat.STAM_REFUSE_FLASH;
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
            else => {},
        };
    }
    // Fire whatever is buffered the moment an exit opens. Callers clear their own
    // action flag first, so start* sees a free hero.
    fn fireQueued(self: *Hero) void {
        const q = self.queued orelse return;
        self.queued = null;
        switch (q) {
            .attack => |k| self.startAttack(k),
            .roll => |d| self.startRoll(d),
        }
    }

    // Begin a committed sword attack in the current facing. Ignored while committed to anything
    // else (player input goes through requestAttack, which buffers instead).
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

    // Advance an in-progress attack (committed step into the cut + pose + blade refresh);
    // call in place of move/update while `attacking` (`bounds` clamps like moveHero), movement
    // ignored. `faceYaw` (lock target heading, null unlocked) re-squares through the RECOVERY tail only (ATK_RETRACK), so a locked whiff recovers its turning fast.
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
        // Buffered exit: past the chain knot the stand-down tail is skippable — a queued
        // action takes over NOW (this is what makes mashed inputs FLOW, souls-style).
        const chain: f32 = if (self.atkHeavy) AH_CHAIN else AL_CHAIN;
        const wasLight = !self.atkHeavy;
        const wasAlt = self.atkAlt;
        if (self.atkT / dur >= chain and self.queued != null) {
            self.attacking = false;
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

    // ER combo naturalism: a light chained off a light ALTERNATES — the return swipe comes
    // backhand out of where the last one landed. Call right after fireQueued() (both exits
    // — the chain knot and the anim's end — owe it, and startAttack has just zeroed atkAlt).
    fn alternateChain(self: *Hero, wasLight: bool, wasAlt: bool) void {
        if (self.attacking and !self.atkHeavy and wasLight) self.atkAlt = !wasAlt;
    }

    // ── THE FLASK ───────────────────────────────────────────────────────────────────────
    // ER's quick item, committed. The charge goes the instant you commit — that is what makes a
    // panicked drink a real mistake rather than something you can back out of — and the restore
    // arrives partway through, so the window is a cost you pay before you get anything.

    /// Swap which flask is up (D-pad down). Free, and legal at any time except mid-draught: it is
    /// a belt gesture, not an action, and gating it behind combat state would make it feel sticky.
    pub fn cycleFlask(self: *Hero) void {
        if (self.dead or self.drinking) return;
        self.flasks.cycle();
    }

    /// Start a draught. Refused (and flagged, like an empty stamina bar) when the flask is dry;
    /// ignored outright while committed to something else, exactly as `startAttack` is.
    pub fn startDrink(self: *Hero) bool {
        if (self.committed() or self.dead or self.staggered()) return false;
        // THE CHARGE MUST NOT GO INTO A BAR THAT CANNOT TAKE IT — and only the CERULEAN is gated.
        // Wasting a Crimson at full health is ER's own behaviour and stays; the blue one is the
        // exception because nothing spends FP yet, so it could only EVER be wasted.
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

    /// Advance the draught; call in place of move/attack/roll while `drinking`. The pour lands once,
    /// at FLASK_POUR_AT — before that you have spent the charge and got nothing, which is the whole
    /// shape of the decision.
    pub fn updateDrink(self: *Hero, dt: f32) void {
        self.tickClocks(dt);
        self.drinkT += dt;
        self.speed = 0;
        self.speedS = mathx.approach(self.speedS, 0, dt * SPEED_SMOOTH);
        const u = self.drinkT / combat.FLASK_DRINK_DUR;
        if (!self.poured and u >= combat.FLASK_POUR_AT) {
            self.poured = true;
            switch (self.flasks.sel) {
                .crimson => self.vit.hp = mathx.minF(self.vit.hpMax, self.vit.hp + self.vit.hpMax * combat.FLASK_HP_FRAC),
                .cerulean => _ = self.fp.restore(self.fp.max * combat.FLASK_FP_FRAC),
            }
        }
        self.pose();
        if (self.drinkT >= combat.FLASK_DRINK_DUR) {
            self.drinking = false;
            self.startXfade();
            self.fireQueued(); // anything buffered during the draught leaves the moment it ends
        }
    }

    // TAE-events equivalent: the blade only HITS inside the strike's active window.
    pub fn hitActive(self: *const Hero) bool {
        if (!self.attacking) return false;
        const dur: f32 = if (self.atkHeavy) ATK_HEAVY_DUR else ATK_LIGHT_DUR;
        const u = self.atkT / dur;
        return if (self.atkHeavy) (u >= AH_HIT_A and u < AH_HIT_B) else (u >= AL_HIT_A and u < AL_HIT_B);
    }

    // Refresh the blade capsule from the SWORD bone. Keeps last frame's endpoints for
    // swept tests; the sweep history resets on the activation edge (which is also where
    // the per-swing hit list will clear once there are targets to record).
    fn updateBlade(self: *Hero) void {
        self.bladeA0 = self.bladeA;
        self.bladeB0 = self.bladeB;
        self.bladeA = rl.math.vector3Transform(BLADE_BASE, self.xf[SWORD]);
        self.bladeB = rl.math.vector3Transform(BLADE_TIP, self.xf[SWORD]);
        const act = self.hitActive(); // sampled ONCE — both the trail and the edge test read it
        // Trail sample — only inside the strike's ACTIVE window (the cut paints its arc;
        // the windup/recovery leave nothing) and only while the tip is really sweeping.
        if (act and mathx.lenV(mathx.subV(self.bladeB, self.bladeB0)) > TRAIL_MIN_SWEEP) {
            self.trailHead = (self.trailHead + 1) % TRAIL_N;
            self.trail[self.trailHead] = .{ .a = mathx.lerpV(self.bladeA, self.bladeB, TRAIL_ROOT), .b = self.bladeB, .age = 0 };
        }
        if (act and !self.hitWasActive) {
            self.bladeA0 = self.bladeA;
            self.bladeB0 = self.bladeB;
        }
        self.hitWasActive = act;
    }

    // The swing trail: unlit alpha ribbon between consecutive blade samples, newest →
    // oldest, each strip fading with its samples' age. Call INSIDE the 3D lit pass,
    // after the opaque geometry (it never casts — draw() stays trail-free on purpose).
    pub fn drawTrail(self: *const Hero) void {
        rl.gl.rlDisableBackfaceCulling(); // the ribbon must read from both sides of the arc
        defer rl.gl.rlEnableBackfaceCulling();
        var i: usize = 0;
        while (i + 1 < TRAIL_N) : (i += 1) {
            const s0 = &self.trail[(self.trailHead + TRAIL_N - i) % TRAIL_N];
            const s1 = &self.trail[(self.trailHead + TRAIL_N - i - 1) % TRAIL_N];
            if (s0.age >= TRAIL_LIFE or s1.age >= TRAIL_LIFE) break; // the rest is older still
            const f = 1.0 - 0.5 * (s0.age + s1.age) / TRAIL_LIFE;
            const strip = [4]rl.Vector3{ s0.a, s0.b, s1.a, s1.b };
            rl.drawTriangleStrip3D(&strip, mathx.withAlpha(TRAIL_COL, mathx.u8f(84.0 * f * f)));
        }
    }

    // ── taking a hit (HP + the two-tier Elden Ring stagger) ─────────────────────────────
    // The poise/stance dealt by the hero's own cuts, handed to the toads' hit test.
    pub fn attackHit(self: *const Hero) combat.Hit {
        return if (self.atkHeavy) ATK_HEAVY_HIT else ATK_LIGHT_HIT;
    }
    // Remember where a death respawns the hero (called once after init sets his start pose).
    pub fn setSpawn(self: *Hero, pos: rl.Vector3, facing: f32) void {
        self.spawnPos = pos;
        self.spawnFacing = facing;
    }
    pub fn staggered(self: *const Hero) bool {
        return self.stun != .none;
    }

    // True through the roll's front-loaded invulnerability window — blows pass clean through.
    pub fn iFramed(self: *const Hero) bool {
        return self.rolling and self.rollT < ROLL_IFRAME_END;
    }

    // Apply a blow: HP drains, poise/stance drive the flinch/stagger. Any reaction INTERRUPTS
    // the current action — souls commitment cuts both ways; call from game.zig after the knot resolves its attacks.
    pub fn takeHit(self: *Hero, h: combat.Hit) void {
        if (self.dead) return;
        if (self.iFramed()) return; // rolled through it — no damage, no flinch, nothing
        const r = self.vit.hit(h);
        // Red damage-flash on ANY blow, punchier the harder the reaction (peripheral feedback).
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
    }
    // Decay the damage-flash. Call every frame (independent of which update path runs).
    pub fn tickFlash(self: *Hero, dt: f32) void {
        self.hurtFlash = mathx.maxF(0, self.hurtFlash - dt * 2.6);
    }

    // Age the swing trail. Called by EVERY per-frame advance path (update/attack/roll/
    // stun/death — exactly one runs each frame), so samples fade for the --shot harness
    // too, not just the live loop (stale ribbons otherwise haunt later captures).
    fn ageTrail(self: *Hero, dt: f32) void {
        for (&self.trail) |*s| s.age = mathx.minF(s.age + dt, mathx.LONG_AGO);
    }
    fn enterStun(self: *Hero, kind: combat.StunKind) void {
        self.attacking = false; // the reaction drops whatever he was committed to
        self.rolling = false;
        // …the draught included, AND THE CHARGE IS ALREADY GONE. That is ER's rule and it is the
        // sharpest edge on the whole system: drink in the wrong window and you lose the flask AND
        // the health it was going to give you.
        self.drinking = false;
        self.queued = null;
        self.stun = kind;
        self.stunT = 0;
        self.speed = 0;
        self.startXfade();
    }
    fn enterDeath(self: *Hero) void {
        self.attacking = false;
        self.rolling = false;
        self.drinking = false;
        self.stun = .none;
        self.queued = null;
        self.dead = true;
        self.deathT = 0;
        self.speed = 0;
        self.startXfade();
    }

    // Advance a stagger; clears back to normal control when it finishes. Call in place of
    // move/attack/roll while `staggered()`.
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

    // Advance the death collapse; respawns the hero at full vitals when it completes.
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
        self.vit = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX);
        self.stam.reset();
        self.fp.reset();
        // FLASKS REFILL AT THE GRACE, and a death IS a return to one — same event, same rule as ER.
        self.flasks.refill();
        self.drinking = false;
        self.stamRefused = 0; // a respawn must not inherit the last life's refusal flash
        self.sprinting = false;
        self.pos = self.spawnPos;
        self.facing = self.spawnFacing;
        self.moving = 0;
        self.speed = 0;
        self.speedS = 0;
        self.startXfade();
    }

    // Compute every bone's world matrix for this frame's pose. Call once before drawing.
    pub fn pose(self: *Hero) void {
        if (self.dead) return self.poseDeath();
        if (self.stun != .none) return self.poseStun();
        if (self.rolling) return self.poseRoll();
        if (self.drinking) return self.poseDrink();
        if (self.attacking) return self.poseAttack();
        const m = self.moving;
        const ph = self.phase;
        const twoPi = std.math.tau;
        // Travel direction in the body frame (locked-on strafe/backpedal — see the
        // locked-on footing note above STRIDE). fw signs the sagittal gait (negative =
        // the time-reversed backpedal), lat drives the sidestep.
        const fw = self.fwdB;
        const lat = self.latB;
        const fwPos = mathx.clampF(fw, 0, 1);
        // Walk→run blend from the short-EASED ground speed (speedS) so posture glides across
        // stance changes instead of stepping; sprintB adds extra lean/crouch past full run.
        // Both gated by FORWARDNESS: the run/sprint presentation belongs to forward travel — a fast strafe/backpedal stays an upright walk.
        const runB = mathx.clampF((self.speedS - RUN_SPEED_LO) / (RUN_SPEED_HI - RUN_SPEED_LO), 0, 1) * fwPos;
        const sprintB = mathx.clampF((self.speedS - RUN_SPEED_HI) / (SPRINT_REF_SPEED - RUN_SPEED_HI), 0, 1) * fwPos;
        const crouch = (RUN_CROUCH * runB + 0.5 * RUN_CROUCH * sprintB) * m +
            STRAFE_DIP * @abs(lat) * m; // low centre of gravity; strafing settles onto its soft knees

        // ── pelvis oscillations (walk bob — run airtime bounce) ──
        const walkBob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * ph); // twice/stride, symmetric
        const runBounce = A_RUN_BOUNCE * (0.5 - 0.5 * mathx.cosf(2.0 * twoPi * (ph - 0.2))); // up-only, peaks at flight
        // Both the bob and the pelvic list belong to the SAGITTAL compass gait, so they fade out with
        // forwardness. A pure sidestep has its own vertical story — legChain solves those feet against
        // an assumed pelvis height (STRAFE_DIP) and knows nothing about a bob laid on top, so leaving
        // the walk's ±0.012·H running through a strafe drove the planted foot ~7 cm under.
        const fwAbs = @abs(fw);
        const bob = mathx.lerpF(walkBob, runBounce, runB) * m * fwAbs + 0.006 * H * mathx.sinf(self.elapsed * 2.2) * (1.0 - m);
        const latW = @abs(lat) * m;
        const sway = strafeSway(latW, runB) * mathx.sinf(twoPi * ph) * m; // weight sits over the single-support foot; a strafe just opens the amplitude
        // Pelvic transverse rotation: the walk's, plus the sidestep's own crossing drive (which
        // peaks on the crossing foot's plant). Both counter-rotate up the spine below.
        const prot = A_PROT * mathx.sinf(twoPi * ph) * m * @abs(fw) + strafeProt(ph, lat, m);
        const list = A_LIST * mathx.sinf(twoPi * ph) * m * fwAbs; // pelvic frontal drop (sagittal gait's)

        // Root: place at world pos, at hip height (crouched when running), swayed/bobbed in
        // body frame, PITCHED FORWARD ABOUT THE FEET (so the centre of gravity leads the
        // base — the driving, falling-forward run), then faced.
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        // …plus the SLOPE he is standing on. Same rx term as the run lean because it is the same
        // motion — the trunk folding forward over planted feet — and it hinges about the FEET here
        // (the rx is applied before the world translate), which is what a climb actually looks like.
        // Set by the loop and already eased, so nothing snaps as the ground changes under him.
        const bodyPitch = (BODY_PITCH_RUN * runB + (BODY_PITCH_SPRINT - BODY_PITCH_RUN) * sprintB) * m + self.slopePitch;
        var wx: [N]rl.Matrix = undefined;
        // Pelvis height. NOTE: a "pelvis floor" that held this up off the legs' own reach was tried
        // here and REVERTED — it is arithmetically right and wrong for the character. The run's crouch
        // is deliberately deeper than the legs can pay for, so the floor cancelled most of RUN_CROUCH
        // and the run stood up and read slow and floaty (owner's verdict). The remaining sink is NOT
        // this term anyway: see the bodyPitch note below.
        const pelvY = hipY - crouch + bob;
        wx[ROOT] = mul3(
            mul(rz(list), ry(prot)), // tilt/rotate pelvis about its centre
            mul(tr(sway, pelvY, 0), mul(rx(bodyPitch), ry(facingDeg))), // crouch, pitch whole body forward about the feet, then face
            rootAt(self.pos), // place in the world, ON the ground under him
        );

        // Spine chain — lean deepens through run into sprint + counter-rotation vs pelvis.
        // The walk lean follows the SIGNED forward blend (a backpedal leans slightly back,
        // a pure strafe stays upright), and the torso banks gently INTO a sidestep.
        const lean = (mathx.lerpF(TORSO_LEAN * fw, RUN_LEAN, runB) + sprintB * (SPRINT_LEAN - RUN_LEAN)) * m;
        const bank = STRAFE_LEAN * lat * m;
        setLocal(&wx, SPINE, self.rest, mul3(rx(lean * 0.5), ry(-0.3 * prot), rz(0.5 * bank)));
        setLocal(&wx, CHEST, self.rest, mul3(rx(lean * 0.5), ry(-0.5 * prot), rz(0.5 * bank)));
        // Idle/walk carries a gentle downward gaze (HEAD_WALK). Running, the body pitch + spine
        // lean would drive the face at the floor, so counter that tilt toward ~GAZE_AHEAD (a few
        // metres ahead, NOT level/up, capped so the neck never hyperextends), split across neck + head so the lift curves naturally.
        const fwdTilt = bodyPitch + lean;
        const gazeCounter = mathx.clampF(fwdTilt - GAZE_AHEAD, 0, NECK_EXT_MAX);
        setLocal(&wx, NECK, self.rest, mul(rx(-0.45 * gazeCounter), ry(-0.2 * prot)));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK - 0.55 * gazeCounter)); // +rx = gaze down (walk); the counter lifts it toward ahead when running

        // Legs — left uses phase, right is half a stride out.
        legChain(&wx, &self.rest, ph, m, runB, fw, lat, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
        legChain(&wx, &self.rest, ph + 0.5, m, runB, fw, lat, -1.0, HIPR, KNEER, BOOT_SOLE[1]);

        // Arms — contralateral swing (cos: same-side arm is BACK when its leg is forward);
        // bigger swing + ~90° elbows when running. The swing follows the SIGNED forward
        // blend: it flips for a backpedal (counter-swing stays honest against the
        // reversed legs) and quiets to a guarded stillness across a strafe.
        const armAmp = mathx.lerpF(ARM_SWING, RUN_ARM_SWING, runB);
        const armL = -armAmp * mathx.cosf(twoPi * ph) * m * fw;
        const armR = armAmp * mathx.cosf(twoPi * ph) * m * fw;
        armChain(&wx, self.rest, armL, m, runB, sprintB, 1.0, 0.0, SHL, ELL, WRL);
        armChain(&wx, self.rest, armR, m, runB, sprintB, -1.0, 1.0, SHR, ELR, WRR); // right hand carries the sword
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity()); // blade rides the fist

        self.applyXfade(&wx);
        self.xf = wx;
    }


    // Freeze the current pose as the source of a short cross-fade — call at any pose
    // DISCONTINUITY (roll start/end). pose()/poseRoll() blend out of it over POSE_XFADE.
    fn startXfade(self: *Hero) void {
        self.blendXf = self.xf;
        self.blendT = 0;
    }

    fn applyXfade(self: *const Hero, wx: *[N]rl.Matrix) void {
        if (self.blendT >= POSE_XFADE) return;
        const k = mathx.smoothstep(0, POSE_XFADE, self.blendT);
        for (0..N) |i| wx[i] = lerpM(self.blendXf[i], wx[i], k);
    }

    // Roll pose, three overlapping beats (the knots above): DIVE (crouch + ball up fast),
    // SOMERSAULT (tucked body tumbles forward about a ball-height pivot, front-loaded, 360°
    // landing early), RECOVERY (legs extend to plant, pelvis rises to stance); wabi-sabi rides
    // on top, all cosmetic. After facing, the body's +Z is rollDir, so a +X-axis rotation is a forward roll along it.
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
            mathx.smoothstep(0.30, 0.75, u) * (1.0 - mathx.smoothstep(0.85, 1.0, u));
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

    // R1 — the LEVEL SWIPE (see CUT MECHANICS above), kinetic-chain sequenced: trunk winds
    // toward the sword side, then pelvis → chest → shoulder → elbow → wrist release (each
    // AL_LAG late), the blade sweeping one wide horizontal arc across the front at chest height.
    // Chained lights ALTERNATE (atkAlt): forehand right → left, the RETURN backhand left → right by mirroring the yaw/sweep terms (chambered shallower — the body blocks a full cross windup).
    fn poseLight(self: *Hero) void {
        const u = mathx.clampF(self.atkT / ATK_LIGHT_DUR, 0, 1);
        const rec = 1.0 - mathx.smoothstep(AL_RECOV_A, 1.0, u); // 1 until recovery, draining to 0
        const wind = mathx.smoothstep(0, AL_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AL_STRIKE_A, AL_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_STRIKE_B + AL_LAG, u) * rec;
        // The elbow shoots out WITH the raise, fully long right as the hit window opens:
        // the blade must ride the OUTER EDGE of the swipe radius for the whole pass — a
        // bent arm sweeps hilt-first (the "hitting them with the hilt" fail).
        const sElb = mathx.smoothstep(AL_WIND_B, AL_HIT_A + 0.04, u) * rec;
        const sWr = mathx.smoothstep(AL_STRIKE_A + 2 * AL_LAG, AL_STRIKE_B + 2 * AL_LAG, u) * rec;
        const sw: f32 = if (self.atkAlt) -1.0 else 1.0; // swing side: +1 forehand, -1 backhand return
        const amp: f32 = if (self.atkAlt) 0.8 else 1.0; // the cross-body windup can't coil as deep

        // Trunk: wind toward the swing's origin side, release through past neutral.
        // `os` is the follow-through overshoot — the swing whips a few degrees PAST the
        // end pose just as recovery starts pulling home, so it settles instead of parking.
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
        setLocal(&wx, SPINE, self.rest, mul(rx(crunch), ry(0.35 * yawC)));
        setLocal(&wx, CHEST, self.rest, mul(rx(crunch), ry(0.65 * yawC)));
        setLocal(&wx, NECK, self.rest, ry(-0.4 * (yawP + yawC)));
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK), ry(-0.35 * (yawP + yawC)))); // eyes stay on the target
        // Stance brace: the leg opposite the swing's LANDING side steps up as the cut releases.
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
        // Left arm counterbalances: drifts forward on the wind, sweeps back through.
        setLocal(&wx, SHL, self.rest, mul(rx(-10.0 * wind + 24.0 * sChest), rz(ARM_ABD)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 12.0 * wind)));
        setLocal(&wx, WRL, self.rest, rl.math.matrixIdentity());
        // Sword arm, the swipe (per CUT MECHANICS). rx RAISES the arm into the chest-height
        // plane on its OWN early ramp (sRaise), fully arrived BEFORE the hit window so the
        // ENTIRE active arc is level; ry is the star — hand wound behind the sword shoulder,
        // then SWEPT around the front past the off shoulder (overshoot rides it), rz just
        // clears the torso, the elbow extends late and the wrist fires LAST.
        const windAmp: f32 = if (self.atkAlt) AL_ALT_WIND else 1.0;
        const sRaise = mathx.smoothstep(AL_WIND_B - 0.06, AL_HIT_A - 0.02, u) * rec;
        const elev = AL_SH_ELEV_WIND * wind + (AL_SH_ELEV - AL_SH_ELEV_WIND) * sRaise;
        // The sweep fires ONE lag after the pelvis (with the chest, not after it) and runs
        // to the END of the hit window — the blade is flying for every active frame: no
        // pre-window hang, no dead beat at the tail.
        const sSweep = mathx.smoothstep(AL_STRIKE_A + AL_LAG, AL_HIT_B - 0.01, u) * rec;
        const sweep = sw * (-AL_SWEEP_WIND * windAmp * wind + (AL_SWEEP_WIND * windAmp + AL_SWEEP_END) * sSweep + 0.9 * os);
        setLocal(&wx, SHR, self.rest, mul3(rx(-elev), ry(sweep), rz(-ARM_ABD - 10.0 * amp * wind)));
        const elb = IDLE_ELBOW + (AL_ELBOW_WIND - IDLE_ELBOW) * wind - (AL_ELBOW_WIND - AL_ELBOW_STRIKE) * sElb;
        setLocal(&wx, ELR, self.rest, rx(-elb));
        // Wrist + blade, the RE-GRIP (ramped by lvl through the raise, drained by rec — the
        // low-ready carry is untouched): the SWORD bone cancels the baked grip cant EXACTLY
        // (blade dead on the wrist's roll axis), then the wrist rolls it a quarter-turn
        // (EDGE_ROLL, edge leading, no cone), tips it a whisker high (TIP_UP), and the
        // LAY→WHIP deviation trails the blade through the chamber only, releasing early so
        // the window sweeps near-RADIAL, whipping past straight at the exit. All in the swipe plane.
        const lvl = mathx.smoothstep(0.05, AL_STRIKE_A, u) * rec;
        const lay = sw * (AL_WRIST_LAY * wind - (AL_WRIST_LAY + AL_WRIST_WHIP) * sWr);
        setLocal(&wx, WRR, self.rest, mul3(ry(sw * AL_EDGE_ROLL * lvl), rx(-AL_TIP_UP * lvl), rz(lay)));
        setLocal(&wx, SWORD, self.rest, rx(GRIP_PITCH * lvl)); // +rx maps the baked cant back onto the wrist's -^'Y exactly (rx(+34)·cant … blade dead on the roll axis)
        self.applyXfade(&wx);
        self.xf = wx;
    }

    // R2 — the overhead chop: a slow raise past vertical (the tell), knees loading,
    // then trunk flexion drives the drop (chain-sequenced like the light), the weight
    // falling into a buried impact that HOLDS before the slow rise.
    fn poseHeavy(self: *Hero) void {
        const u = mathx.clampF(self.atkT / ATK_HEAVY_DUR, 0, 1);
        const rec = 1.0 - mathx.smoothstep(AH_RECOV_A, 1.0, u);
        const wind = mathx.smoothstep(0, AH_WIND_B, u) * rec;
        const sPelv = mathx.smoothstep(AH_STRIKE_A, AH_STRIKE_B, u) * rec;
        const sChest = mathx.smoothstep(AH_STRIKE_A + AH_LAG, AH_STRIKE_B + AH_LAG, u) * rec;
        const sSh = mathx.smoothstep(AH_STRIKE_A + 2 * AH_LAG, AH_STRIKE_B + 2 * AH_LAG, u) * rec;
        const sElb = mathx.smoothstep(AH_STRIKE_A + 3 * AH_LAG, AH_STRIKE_B + 3 * AH_LAG, u) * rec;
        const sWr = mathx.smoothstep(AH_STRIKE_A + 4 * AH_LAG, AH_STRIKE_B + 4 * AH_LAG, u) * rec;

        // Grace notes that keep the chop ORGANIC: `gather` drifts the blade a touch
        // further back through the top-of-raise hang (a breath before the violence, gone
        // once the shoulder fires); `rcl` is the impact judder inside the buried hold —
        // the blade bites, the body bounces a hair, and it re-settles.
        const gather = mathx.smoothstep(AH_WIND_B - 0.05, AH_STRIKE_A + 2 * AH_LAG, u) * (1.0 - sSh) * rec;
        const rcl = bump(u, AH_STRIKE_B + 2 * AH_LAG, AH_RECOV_A) * rec;

        const yaw = -AH_BODY_YAW * wind + 2.0 * AH_BODY_YAW * sPelv;
        const spineX = -AH_LEAN_BACK * wind + (AH_LEAN_BACK + AH_SPINE_CRUNCH) * sChest;
        // Frontal coil: bend toward the sword side under the raise, whip past on the drop.
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
        setLocal(&wx, SPINE, self.rest, mul(rx(0.5 * spineX), rz(0.5 * tilt)));
        setLocal(&wx, CHEST, self.rest, mul(rx(0.5 * spineX), rz(0.5 * tilt)));
        setLocal(&wx, NECK, self.rest, rx(-0.3 * spineX)); // head counters the lean-back, tucks on the drop
        setLocal(&wx, HEAD, self.rest, mul(rx(HEAD_WALK + 4.0 * sChest), ry(-0.4 * yaw)));
        // Staggered load, not a symmetric squat: the off-side (left) leg steps up to
        // brace while the sword-side leg sits BACK and loads under the raise.
        setLocal(&wx, HIPL, self.rest, mul(rx(-14.0 * wind - 8.0 * sPelv), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 8.0 * wind + 6.0 * sPelv));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(2.0 * wind + 5.0 * sPelv), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 17.0 * wind + 4.0 * sPelv));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        // Left arm rises for balance under the raise, drops with the blow.
        setLocal(&wx, SHL, self.rest, mul(rx(-22.0 * wind + 30.0 * sChest), rz(ARM_ABD + 6.0 * wind)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 16.0 * wind)));
        setLocal(&wx, WRL, self.rest, rl.math.matrixIdentity());
        // Sword arm: up past vertical, blade hanging back (sinking further through the
        // gather) — then the chop, recoiling a few degrees off the bite before settling.
        const shX = -AH_SH_UP * wind - AH_GATHER * gather + (AH_SH_UP - AH_SH_DOWN) * sSh + AH_RECOIL * rcl;
        setLocal(&wx, SHR, self.rest, mul(rx(shX), rz(-ARM_ABD - 8.0 * wind)));
        const elb = IDLE_ELBOW + (AH_ELBOW_WIND - IDLE_ELBOW) * wind + 5.0 * gather - (AH_ELBOW_WIND - AH_ELBOW_STRIKE) * sElb;
        setLocal(&wx, ELR, self.rest, rx(-elb));
        setLocal(&wx, WRR, self.rest, rx(AH_WRIST_COCK * wind - (AH_WRIST_COCK + AH_WRIST_SNAP) * sWr + 8.0 * rcl));
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    // THE DRAUGHT — the OFF hand does all of it. The sword stays in the right fist at its low-ready
    // the whole time, which is the read that matters: he is drinking WITH HIS GUARD DOWN but he has
    // not put the weapon away, and that is why the window is dangerous rather than merely slow.
    //
    // Three beats out of one `lift` curve — raise, tip and drink, lower — so the pour (which lands
    // on the game's clock at FLASK_POUR_AT) coincides with the head being back. The legs hold the
    // idle stance: he plants to drink.
    fn poseDrink(self: *Hero) void {
        const u = mathx.clampF(self.drinkT / combat.FLASK_DRINK_DUR, 0, 1);
        // Up fast, HOLD at the mouth through the pour, down slower — a flask is emptied, not waved.
        const lift = mathx.smoothstep(0, 0.26, u) * (1.0 - mathx.smoothstep(0.72, 1.0, u));
        // …and the tip is a separate, later curve riding on top, so the wrist rolls the bottle up
        // only once it has arrived. Both peaking together reads as one stiff gesture.
        const tip = mathx.smoothstep(0.22, 0.46, u) * (1.0 - mathx.smoothstep(0.66, 0.92, u));
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        // He settles onto his heels to drink, and rocks back a touch as the flask goes up.
        const sink = 0.012 * H * lift;
        const lean = -6.0 * tip;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            ry(4.0 * lift), // …turning the drinking shoulder a little toward the camera side
            mul(tr(0, hipY - sink, 0), mul(rx(lean * 0.35), ry(facingDeg))),
            rootAt(self.pos),
        );
        setLocal(&wx, SPINE, self.rest, rx(lean * 0.35));
        setLocal(&wx, CHEST, self.rest, rx(lean * 0.30));
        // The head tips BACK to drink — the single most legible part of the whole action, and the
        // reason this reads at all from the over-the-shoulder camera.
        setLocal(&wx, NECK, self.rest, rx(-14.0 * tip));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK - 30.0 * tip));
        // Legs: the standing stance, knees soft. A drink is not a squat.
        setLocal(&wx, HIPL, self.rest, mul(rx(-2.0 * lift), rz(-HIP_ADDUCT)));
        setLocal(&wx, KNEEL, self.rest, rx(IDLE_KNEE + 4.0 * lift));
        setLocal(&wx, ANKL, self.rest, ry(FOOT_TOEOUT));
        setLocal(&wx, HIPR, self.rest, mul(rx(-1.0 * lift), rz(HIP_ADDUCT)));
        setLocal(&wx, KNEER, self.rest, rx(IDLE_KNEE + 3.0 * lift));
        setLocal(&wx, ANKR, self.rest, ry(-FOOT_TOEOUT));
        // THE FLASK ARM (left): shoulder forward and across, elbow folded hard so the hand comes to
        // the face rather than out in front of it — an unfolded elbow is what makes a "drink" read
        // as a salute.
        setLocal(&wx, SHL, self.rest, mul(rx(-58.0 * lift - 14.0 * tip), rz(ARM_ABD + 16.0 * lift)));
        setLocal(&wx, ELL, self.rest, rx(-(IDLE_ELBOW + 96.0 * lift + 22.0 * tip)));
        setLocal(&wx, WRL, self.rest, rx(-28.0 * tip)); // the wrist rolls the bottle up at the lips
        // The sword arm just carries, quietly, exactly as it does at idle.
        setLocal(&wx, SHR, self.rest, mul(rx(2.0 * lift), rz(-ARM_ABD)));
        setLocal(&wx, ELR, self.rest, rx(-(IDLE_ELBOW + CARRY_ELBOW)));
        setLocal(&wx, WRR, self.rest, rl.math.matrixIdentity());
        setLocal(&wx, SWORD, self.rest, rl.math.matrixIdentity());
        self.applyXfade(&wx);
        self.xf = wx;
    }

    // Stagger — the reaction when poise (light) or stance (heavy) breaks: torso RECOILS back,
    // head snaps, arms fly out, balance goes. LIGHT is a quick sin pulse, HEAVY a deep sustained
    // reel (trailing leg thrown back) with a wobble — wide open, souls-committed, easing out (nothing parks).
    fn poseStun(self: *Hero) void {
        const heavy = self.stun == .heavy;
        const dur: f32 = if (heavy) combat.HEAVY_STUN_DUR else combat.LIGHT_STUN_DUR;
        const u = mathx.clampF(self.stunT / dur, 0, 1);
        const amt = if (heavy)
            mathx.smoothstep(0, 0.12, u) * (1.0 - mathx.smoothstep(0.68, 1.0, u)) // ramp, hold, release
        else
            mathx.sinf(u * std.math.pi); // a single flinch pulse
        const leanMag: f32 = if (heavy) STAG_LEAN else HURT_LEAN;
        const lean = leanMag * amt;
        const wob: f32 = if (heavy) 3.0 * mathx.sinf(self.elapsed * 13.0) * amt else 0;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const sinkMag: f32 = if (heavy) 0.06 else 0.05;
        const sink = sinkMag * H * amt;
        // Knocked back off the blow: the body shifts along -^'facing (the flinch reads as impact,
        // not a lean). +Z in the pre-facing frame is the facing dir, so a -^'Z offset = backward.
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

    // Death — a crumple: the pelvis SINKS as the legs buckle under, the trunk folds and
    // topples forward, the head hangs, arms splay. Holds the heap until respawn.
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
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, self.xf[i]);
    }

    /// Eye/target point for the camera: the base of the neck, measured from `pos.y` — THE GROUND HE IS
    /// STANDING ON, not the datum, or the rig frames the bottom of the hill he is up. The REST height
    /// rather than the posed bone, so the camera does not bob with the gait or dip through a roll.
    pub fn shoulderPoint(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + self.rest[CHEST].y, self.pos.z);
    }
};

// offset(child) in the parent's frame = restPos(child) - restPos(parent), since all rest
// orientations are identity. world(child) = local(child) -^~ world(parent), where
// local = animRot -^~ translate(offset) (animRot applied first, about the joint).
fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    const p: usize = @intCast(parent[i]);
    const off = mathx.subV(rest[i], rest[p]);
    const local = mul(animRot, tr(off.x, off.y, off.z));
    wx[i] = mul(local, wx[p]);
}

// A joint set that names its PARENT explicitly and takes SLICES, so a rig with more bones than the
// hero's 18 can still drive its legs through `legChain`. The only layout it assumes is bone 0 = pelvis.
//
// THE one statement of the matrix convention (`mul(a, b)` applies a FIRST — backwards and the skeleton
// explodes). Every rig's own `setLocal` delegates here with its own `parent[i]`, so there is exactly
// one place the convention can be got wrong.
pub fn setJoint(wx: []rl.Matrix, rest: []const rl.Vector3, i: usize, p: usize, animRot: rl.Matrix) void {
    const off = mathx.subV(rest[i], rest[p]);
    wx[i] = mul(mul(animRot, tr(off.x, off.y, off.z)), wx[p]);
}

// pub: humanoid enemies drive their legs through this same walk + locked-on strafe/backpedal
// footing (AGENTS.md humanoid rule). Rig-size agnostic — the caller passes its own hip/knee/ankle
// indices and its whole bone array; only "pelvis is bone 0" is assumed.
// `sole` carries BOTH the ankle bone index and that foot's sole footprint, because the ankle's pitch
// has to be clamped against the ground (see ankleLimits) and only the rig knows how long its own boot
// is. Each humanoid passes its own measured patch.
pub fn legChain(wx: []rl.Matrix, rest: []const rl.Vector3, ph: f32, m: f32, runB: f32, sag: f32, lat: f32, side: f32, hip: usize, knee: usize, sole: SolePatch) void {
    const ank = sole.bone;
    // Sagittal gait weighted by the forward blend `sag`; a backpedal (sag < 0) samples
    // the SAME normative tables with phase run backward — reversed walking. The lateral
    // blend `lat` drives the CROSSING sidestep instead (the scissor below).
    const phS = if (sag >= 0) ph else -ph;
    const sagW = @abs(sag) * m;
    const hipFlex = mathx.lerpF(sampleCurve(HIP_FLEX, phS), sampleCurve(RUN_HIP, phS), runB) * sagW;
    const kneeWR = mathx.lerpF(sampleCurve(KNEE_FLEX, phS), sampleCurve(RUN_KNEE, phS), runB);
    const ankDorsi = mathx.lerpF(sampleCurve(ANK_DORSI, phS), sampleCurve(RUN_ANK, phS), runB) * sagW;
    // ── THE CROSSING SIDESTEP. See the geometry note above STRAFE_ABD for WHY it is shaped this
    // way: ONE symmetric sweep per leg, half a cycle apart, and the hip offsets alone turn that
    // into a front cross followed by an outside uncross. Nothing here is a tuned amplitude.
    const latW = @abs(lat) * m;
    const thigh = rest[hip].y - rest[knee].y;
    const shank = rest[knee].y - rest[ank].y;
    const legLen = thigh + shank;
    const rigS = legLen / LEG_LEN; // rig-relative, so the 2x ogre would get a 2x sidestep
    const reach = STRAFE_REACH * rigS; // the measured sweep, scaled onto THIS rig
    const q = ph - @floor(ph); // leg-local phase; q = 0 is the instant this foot PLANTS
    // Foot travel along the travel direction, -^'reach..+reach. Through STANCE it is LINEAR in phase
    // (= linear in distance = the foot stays put while the body passes over it — the whole point).
    // Through SWING a Hermite carries it back, LEAVING at the stance velocity (so toe-off keeps
    // drifting back a beat, as a real foot does) and ARRIVING at rest (a landing foot is still).
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
    // The foot's world +X displacement from directly under its OWN hip: rz(+) swings a leg toward
    // +X, and lat > 0 is travel to his RIGHT, which is world -^'X. Note `dx` (a DISTANCE) is what the
    // sweep keeps linear, never an angle — that is what stops the planted foot creeping.
    const dx = -lat * s * m;
    // Which leg CROSSES: the one whose hip is on the far side from travel has further to go, so it
    // comes around the other IN FRONT (hip flexion) while its partner passes BEHIND it on the
    // uncross. That front/behind pairing is the grapevine — it isn't optional, a leg cannot
    // adduct THROUGH the leg it is standing next to.
    const crossing = side * lat > 0;
    const inSwing = w >= 0;
    const arc = if (inSwing) mathx.sinf(std.math.pi * w) else 0.0; // 0→1→0, swing only
    const passF = (if (crossing) @as(f32, STRAFE_CROSS) else -STRAFE_BEHIND) * arc * latW;
    // A front cross lands a little AHEAD of the stance foot; that offset then sweeps out linearly
    // through stance for exactly the same no-skate reason as the frontal sweep above.
    const landF = if (inSwing or !crossing) 0.0 else STRAFE_LAND * (1.0 - 2.0 * q / STRAFE_STANCE) * latW;
    const latHip = passF + landF; // this leg's sagittal angle, LATERAL contribution only
    // ── THE VERTICAL SOLVE: ask for a foot HEIGHT, solve the knee for it ────────────────────────
    // The one part of a sidestep that cannot be constants. Hip and knee flexion fight each other
    // vertically, so a "knee lift" angle does NOT lift a foot — 17 deg over 13 deg of hip netted
    // about a CENTIMETRE and the swing foot skimmed the grass. So state the heights that matter
    // (planted feet ON the ground, swing foot STRAFE_CLEAR above it) and solve the knee that puts
    // the ankle there. Feet then stay planted at EVERY abduction angle, not just the tuned one.
    const clear = STRAFE_CLEAR * rigS * arc * latW;
    // MEASURE the hip's real height rather than assuming the caller dropped the pelvis by exactly
    // STRAFE_DIP. That held for a pure sidestep and broke on a DIAGONAL, where the sagittal bob and
    // the run crouch move the pelvis too. Reading it makes the plant exact under any pelvis motion,
    // and turns STRAFE_DIP from a contract into advice about giving the leg room.
    const rootS = mathx.maxF(1e-4, @sqrt(wx[ROOT].m0 * wx[ROOT].m0 + wx[ROOT].m1 * wx[ROOT].m1 + wx[ROOT].m2 * wx[ROOT].m2));
    const hipW = rl.math.vector3Transform(mathx.subV(rest[hip], rest[ROOT]), wx[ROOT]);
    // …down to the ANKLE JOINT, which rides rest[ank].y above the sole plane — not down to the floor.
    const vert = mathx.maxF(0.1 * legLen, (hipW.y - SOLE_Y) / rootS - rest[ank].y - clear);
    // The hip composes rx (sagittal) FIRST then rz (frontal), so the frontal swing acts on the
    // ALREADY-SHORTENED leg: abduction is atan(sideways / height), NOT asin over the full leg,
    // and the links span the HYPOTENUSE. Get it wrong and the planted foot floats a centimetre.
    const span = @sqrt(vert * vert + dx * dx); // hip→ankle length the two links must make up
    const abd = mathx.degrees(std.math.atan2(dx, vert));
    // Solve against the leg's FULL sagittal angle, not just the lateral part: on a DIAGONAL the walk's
    // own hip flexion is in there too, and ignoring it left the foot 14 cm under.
    const totalHip = hipFlex + latHip;
    const cosK = mathx.clampF((span - thigh * mathx.cosf(mathx.radians(totalHip))) / shank, -1.0, 1.0);
    const latKnee = totalHip + mathx.degrees(std.math.acos(cosK));
    // Blend to the normative sagittal knee as the sidestep fades out, so a forward walk is untouched —
    // but hand over EARLY, because a half-and-half knee satisfies neither the gait tables nor the
    // ground. Past ~half-lateral the solve owns it outright.
    const kneeW = mathx.smoothstep(0.10, 0.55, latW);
    const kneeFlex = mathx.lerpF(mathx.lerpF(IDLE_KNEE, kneeWR, sagW), mathx.maxF(0, latKnee), kneeW);
    // Ankle levels the SOLE in BOTH planes — rz undoes the frontal swing, rx undoes the shank's
    // pitch — so a strafing foot lands flat instead of on a corner. Both release through mid-swing,
    // where a real foot is free to hang.
    const held = if (inSwing) 1.0 - arc else 1.0;
    const flat = (latHip - kneeFlex) * held * latW;
    // The solved `abd` REPLACES the walk's constant adduction rather than adding to it — the solve
    // already accounts for every degree of frontal rotation, so leaving HIP_ADDUCT on top
    // double-counts it and lifts the planted foot about a centimetre off the floor at full stride.
    const frontal = mathx.lerpF(-side * HIP_ADDUCT, abd, latW);
    const roll = -frontal * held;
    // hip: sagittal flexion (-^'rx = thigh forward; the cross/behind pass and the plant offset add
    // their own), then the frontal angle — the walk's adduction, or the sidestep's swept swing.
    setJoint(wx, rest, hip, ROOT, mul(rx(-hipFlex - latHip), rz(frontal)));
    setJoint(wx, rest, knee, hip, rx(kneeFlex)); // +rx = knee bends (shank swings back/up)
    // ── Ankle: dorsiflex + toe-out splay + keep the sole out of the dirt ────────────────────────
    // LEVELLED BY MEASURING, because the foot's world pitch is not just this joint's — body pitch,
    // spine lean and pelvis roll all stack on top, so a clamp on the LOCAL angle misses every one of
    // them and changes nothing. Pose the foot, find its deepest sole corner, rotate the ankle just
    // enough to lift it to the floor. Two passes converge, and the correction is zero the moment the
    // foot is clear, so swing, flight and roll are untouched.
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
        // Rotating about the ankle's own X lifts that corner at a rate set by its HORIZONTAL distance
        // from the joint — measured, not taken from the foot's length, because an already steeply
        // pitched foot (toe-off plantarflexion) has most of that length pointing DOWN and a
        // length-based step then badly undershoots. A corner ahead of the ankle rises as the toe
        // comes up, one behind as it goes down.
        const ankW = rl.math.vector3Transform(v3(0, 0, 0), wx[ank]);
        const lever = mathx.maxF(0.02 * wscale, mathx.lenXZ(mathx.subV(worst, ankW)));
        const step = mathx.degrees(std.math.asin(mathx.clampF((SOLE_Y - deepest) / lever, -1, 1)));
        pitch += if (worstZ > 0) -step else step;
    }
}

fn armChain(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, swing: f32, m: f32, runB: f32, sprintB: f32, side: f32, carry: f32, sh: usize, el: usize, wr: usize) void {
    // Contralateral fore/aft swing; the walking elbow tracks the FORWARD swing only (back arm
    // nearly straight — no "zombie arms"), running bends both to ~90° pumping. The sword arm
    // (carry=1) CARRIES instead of mirroring (swing damped, readier elbow): the low tip-LIFT
    // rides on `carryMove` (any stick = WALK), the "ninja" open-up (fuller lift, blade yawed
    // right, wider abduction, stilled pump) rides on `sprint` (RUN = hold-B), so all stick speeds keep the walk carry and only hold-B RUN opens it out (AGENTS.md: WALK = all stick, RUN = hold-B).
    const carryMove = carry * m; // any stick movement (WALK)
    const sprint = carry * mathx.clampF(sprintB, 0, 1) * m; // hold-B RUN only
    const sw = swing * (1.0 - CARRY_DAMP * carry) * (1.0 - CARRY_SWING_STILL * sprint);
    const walkElbow = mathx.maxF(6.0, 4.0 + 0.8 * sw);
    const runElbow = mathx.lerpF(RUN_ELBOW, CARRY_ELBOW_RUN, carry);
    const elbow = mathx.maxF(mathx.lerpF(IDLE_ELBOW, mathx.lerpF(walkElbow, runElbow, runB), m), CARRY_ELBOW * carry);
    const abd = ARM_ABD + CARRY_ABD_RUN * sprint; // arm eases out to the side only on a hold-B RUN
    setLocal(wx, sh, rest, mul(rx(-sw), rz(side * abd))); // -^'rx forward, ±side rz outward
    setLocal(wx, el, rest, rx(-elbow)); // -^'rx = forearm forward (elbow flexes)
    // Wrist shapes the BLADE only (the arm stays put): a WALK holds it LOW off the floor;
    // a hold-B RUN raises it to the full angle AND yaws it out to the right off the flank
    // (the ninja read). Off the floor either way, but only the RUN reads higher/out.
    const lift = CARRY_WRIST_LIFT * mathx.lerpF(CARRY_LIFT_WALK, 1.0, mathx.clampF(sprintB, 0, 1)) * carryMove;
    setLocal(wx, wr, rest, mul(rx(lift), ry(CARRY_WRIST_YAW * sprint)));
}

// Roll tuck: thighs to chest, heels toward glutes, arms hugged in front — all scaled by
// `tuck` so the crouch eases in and the stand eases out, and by a per-limb wabi-sabi
// factor `f` (lead/trail leg, guide/push arm) so the ball is never mirror-perfect.
// Knee/elbow blend to their IDLE micro-bends (not dead-straight zero) so the plant/rise
// flows into the standing pose.
fn rollLeg(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, tuck: f32, f: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    setLocal(wx, hip, rest, mul(rx(-ROLL_HIP * f * tuck), rz(-side * HIP_ADDUCT)));
    setLocal(wx, knee, rest, rx(mathx.lerpF(IDLE_KNEE, ROLL_KNEE * f, tuck)));
    setLocal(wx, ank, rest, ry(side * FOOT_TOEOUT));
}
fn rollArm(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, tuck: f32, f: f32, side: f32, sh: usize, el: usize, wr: usize) void {
    setLocal(wx, sh, rest, mul(rx(-ROLL_SHOULDER * f * tuck), rz(side * ARM_ABD)));
    setLocal(wx, el, rest, rx(-mathx.lerpF(IDLE_ELBOW, ROLL_ELBOW * f, tuck)));
    setLocal(wx, wr, rest, rl.math.matrixIdentity());
}

// ── bone meshes (authored at the joint origin, hero-local axes; lengths in units of H) ──
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

// The drawn arming sword, authored in the RIGHT-WRIST frame about the fist centre
// (0, FIST_Y, FIST_Z), blade canted GRIP_PITCH forward of the forearm line (held at an
// angle, never straight along it); at rest the tip leads down-forward, clear of the ground
// (souls low-ready), and attacks whip the wrist/arm while the blade just rides.
// Keep BLADE_BASE/BLADE_TIP (the hit capsule dummy points) matched to this geometry.
fn swordMesh() rl.Mesh {
    var b = Builder.init();
    // EDGE ORIENTATION matters: a hammer grip carries the cutting edges FORWARD/BACK
    // (knuckles forward), so the wide edge-to-edge plane is the SAGITTAL `n` axis and the
    // flats face the sides (`s`). An overhead chop then leads with the edge coming down
    // vertically — never a flat "blade smack" — and the quillons lie along the edge line.
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

const scaleV = mathx.scaleV; // shared vector scale (was a local re-implementation)

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    b.addCube(v3(0, -0.01 * H, 0), v3(0.235 * H, 0.16 * H, 0.175 * H), BELT);
    b.setMat(.cloth);
    b.addCube(v3(0, 0.055 * H, 0), v3(0.215 * H, 0.07 * H, 0.16 * H), TUNIC_DK); // hip skirt of the tunic
    b.setMat(.steel);
    b.addCube(v3(0, -0.005 * H, 0.0925 * H), v3(0.035 * H, 0.035 * H, 0.012 * H), BRASS); // buckle
    b.setMat(.leather);
    // leather tassets over the hips + a supply pouch on the right
    b.addCube(v3(0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    b.addCube(v3(-0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    b.addCube(v3(-0.115 * H, -0.045 * H, -0.03 * H), v3(0.05 * H, 0.06 * H, 0.045 * H), LEATHER_DK); // pouch
    b.addCube(v3(-0.115 * H, -0.028 * H, -0.03 * H), v3(0.054 * H, 0.02 * H, 0.05 * H), LEATHER); // pouch flap
    // EMPTY scabbard at the left hip, riding the pelvis bone, raked down-and-back — the
    // sword itself is DRAWN (the SWORD bone in the right fist), so no hilt shows here.
    // d = unit lean of the scabbard; p1/p2 its cross-section axes.
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
    // Slight waist taper: a lower belly block under a broader ribcage base.
    b.addCube(v3(0, -0.01 * H, 0), v3(0.205 * H, 0.13 * H, 0.145 * H), TUNIC);
    b.addCube(v3(0, 0.075 * H, 0), v3(0.235 * H, 0.09 * H, 0.16 * H), TUNIC);
    // tabard front — hangs over the belly, bends with the spine
    b.addCube(v3(0, -0.012 * H, 0.079 * H), v3(0.135 * H, 0.155 * H, 0.014 * H), CAPE);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    // Thorax topping out AT the shoulder line (~0.815 H) so the neck stays clear — the
    // broad-shouldered read comes from the pauldrons on the arms, not a tall chest block.
    b.addCube(v3(0, -0.005 * H, 0), v3(0.285 * H, 0.12 * H, 0.165 * H), TUNIC); // 0.695—0.815 H
    b.setMat(.leather);
    b.addCube(v3(0, 0.035 * H, -0.005 * H), v3(0.305 * H, 0.06 * H, 0.18 * H), LEATHER_DK); // collar/mantle at the shoulders
    b.setMat(.cloth);
    b.addCube(v3(0, -0.01 * H, 0.086 * H), v3(0.135 * H, 0.11 * H, 0.012 * H), CAPE); // tabard chest panel
    b.addCube(v3(0, -0.035 * H, -0.098 * H), v3(0.24 * H, 0.115 * H, 0.016 * H), CAPE); // short cape at the back
    b.setMat(.leather);
    b.addCube(v3(0, 0.042 * H, -0.10 * H), v3(0.25 * H, 0.035 * H, 0.02 * H), LEATHER); // cape yoke
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
    // Cranium, jaw, nose (facing cue), swept-back hair with a nape knot, and a thin
    // leather headband. Head joint sits at the chin line (~0.875 H); crown lands ~1.0 H.
    b.addCube(v3(0, 0.075 * H, -0.005 * H), v3(0.135 * H, 0.115 * H, 0.15 * H), SKIN); // cranium
    b.addCube(v3(0, 0.018 * H, 0.012 * H), v3(0.10 * H, 0.055 * H, 0.125 * H), SKIN); // jaw
    b.addCube(v3(0, 0.05 * H, 0.082 * H), v3(0.028 * H, 0.03 * H, 0.03 * H), SKIN_DK); // nose
    b.setMat(.leather); // hair reads through the leather pore stipple (strand-ish, not plastic)
    b.addCube(v3(0, 0.118 * H, -0.025 * H), v3(0.145 * H, 0.05 * H, 0.15 * H), HAIR); // hair cap
    b.addCube(v3(0, 0.055 * H, -0.078 * H), v3(0.135 * H, 0.125 * H, 0.035 * H), HAIR); // back of hair
    b.addCube(v3(0, 0.012 * H, -0.092 * H), v3(0.05 * H, 0.05 * H, 0.035 * H), HAIR); // nape knot
    b.addCube(v3(0, 0.092 * H, 0.0 * H), v3(0.142 * H, 0.018 * H, 0.152 * H), LEATHER_DK); // headband
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
    // Calf bulge, then a leather boot shaft tapering to the ankle.
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.09 * H, 0), 0.058 * H, 0.062 * H, 10, CLOTHDK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -0.09 * H, 0), v3(0, -SEG_SHANK * H, 0), 0.064 * H, 0.036 * H, 10, BOOT);
    b.addCube(v3(0, -0.02 * H, 0.052 * H), v3(0.062 * H, 0.06 * H, 0.026 * H), LEATHER); // kneecap
    return b.toMesh();
}

fn footMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    // Boot: sole rests on the ground (ankle joint is ANKLE_Y=0.039 H up), toes forward +Z.
    const ay = 0.039 * H;
    b.addCube(v3(0, -ay + 0.028 * H, 0.045 * H), v3(0.085 * H, 0.056 * H, 0.19 * H), BOOT);
    b.addCube(v3(0, -ay + 0.075 * H, -0.02 * H), v3(0.075 * H, 0.05 * H, 0.09 * H), BOOT); // ankle cuff
    return b.toMesh();
}

// Asymmetric pauldrons, souls-style: the LEFT (shield/off-hand) shoulder carries the big
// layered leather + steel-rim pauldron; the right (the sword hand — SWORD rides WRR) makes
// do with a plain cap, leaving the cutting arm freer.
fn upperArmMesh(big: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    if (big) {
        b.addCube(v3(0, -0.005 * H, 0), v3(0.125 * H, 0.10 * H, 0.13 * H), LEATHER);
        b.setMat(.steel);
        b.addCube(v3(0, 0.048 * H, 0), v3(0.105 * H, 0.045 * H, 0.115 * H), STEEL_DK); // steel rim cap
    } else {
        b.addCube(v3(0, 0.005 * H, 0), v3(0.105 * H, 0.085 * H, 0.115 * H), LEATHER);
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
    b.addCube(v3(0, -0.05 * H, 0.005 * H), v3(0.05 * H, 0.10 * H, 0.045 * H), BOOT); // glove
    return b.toMesh();
}

// ── invariants under test (pure math only — meshes/poses need a GPU window) ──────────

/// A Hero for the STATE tests. `mesh`/`mat` are GPU handles and stay `undefined` — nothing here
/// draws — but `rest` is real, because `pose()` reads it and a pose over undefined joints is
/// arithmetic on garbage.
fn testHero() Hero {
    return .{ .mesh = undefined, .mat = undefined, .rest = restPositions() };
}

test "the DRAUGHT is committed like the other two: inputs buffer, they do not fire through it" {
    // The bug: `drinking` was missing from every committed-action guard, so an attack pressed
    // mid-drink skipped the buffer and started on the spot (charging its stamina), and a roll
    // actually RAN while the draught stayed latched behind it.
    var h = testHero();
    try std.testing.expect(h.startDrink());
    const stamAtDrink = h.stam.cur;

    h.requestAttack(.light);
    try std.testing.expect(h.drinking); // still drinking…
    try std.testing.expect(!h.attacking); // …and the swing did NOT start…
    try std.testing.expectEqual(stamAtDrink, h.stam.cur); // …nor charge for one
    try std.testing.expect(h.queued != null); // it went where it belongs: the queue

    // A roll press replaces it in the one slot (last press wins) and likewise waits.
    h.requestRoll(v3(0, 0, 1));
    try std.testing.expect(!h.rolling and h.drinking);

    // …and it leaves the instant the draught ends — which is what `updateDrink`'s fireQueued is
    // for, a call nothing could reach before this fix.
    var guard: u32 = 0;
    while (h.drinking and guard < 500) : (guard += 1) h.updateDrink(0.016);
    try std.testing.expect(!h.drinking);
    try std.testing.expect(h.rolling);
    try std.testing.expect(h.queued == null);
}

test "a Cerulean is refused into a full bar rather than pouring a charge away" {
    // Nothing spends FP in this build, so the blue bar is permanently full: taking the charge at
    // the press and only discovering the pour was a no-op a second later meant EVERY Cerulean
    // draught was wasted. `combat.Focus`'s own test states the contract as "the caller keeps the
    // charge" — this is the caller actually keeping it.
    var h = testHero();
    h.flasks.sel = .cerulean;
    const before = h.flasks.ready();
    try std.testing.expect(!h.startDrink()); // refused…
    try std.testing.expectEqual(before, h.flasks.ready()); // …and it cost nothing
    try std.testing.expect(h.stamRefused > 0); // …and it SAID so, like an empty bar

    // Spend some, and it is a normal drink again.
    h.fp.cur = 10;
    try std.testing.expect(h.startDrink());
    try std.testing.expectEqual(before - 1, h.flasks.ready());

    // The CRIMSON keeps ER's behaviour: drinking at full health wastes it, and that is correct.
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
        // Attack chains: every lagged strike span lands before its recovery begins, and
        // the hit window sits inside the swing.
        std.debug.assert(AL_WIND_B <= AL_STRIKE_A and AL_STRIKE_B + 4 * AL_LAG <= AL_RECOV_A);
        std.debug.assert(AH_WIND_B <= AH_STRIKE_A and AH_STRIKE_B + 4 * AH_LAG <= AH_RECOV_A);
        std.debug.assert(AL_HIT_A >= AL_STRIKE_A and AL_HIT_B <= AL_RECOV_A);
        std.debug.assert(AH_HIT_A >= AH_STRIKE_A and AH_HIT_B <= AH_RECOV_A);
        // Buffered-exit chain knots live in the skippable tail: after recovery starts
        // AND after the overshoot/recoil pulses have died, before the anim ends.
        std.debug.assert(AL_CHAIN >= AL_RECOV_A + 0.15 and AL_CHAIN < 1.0);
        std.debug.assert(AH_CHAIN >= AH_RECOV_A and AH_CHAIN < 1.0);
    }
    // The two overlapped spin eases must sum to one full revolution at ROLL_SPIN_B and
    // STAY there — a spin-free stand-up is the roll's core promise.
    inline for (.{ ROLL_SPIN_B, 0.9, 1.0 }) |u| {
        const spin = ROLL_SPIN_OVER * mathx.smoothstep(ROLL_SPIN_A, ROLL_SPIN_M1, u) +
            (360.0 - ROLL_SPIN_OVER) * mathx.smoothstep(ROLL_SPIN_M0, ROLL_SPIN_B, u);
        try std.testing.expectApproxEqAbs(@as(f32, 360), spin, 1e-4);
    }
}

test "roll travel: the brake profile integrates to ROLL_DIST" {
    // Numeric check of updateRoll's normalization claim (profile integral over u is
    // (BRAKE_A+BRAKE_B)/2, so peak * integral * DUR == DIST).
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

// ── THE CROSSING SIDESTEP, measured off the posed rig ───────────────────────────────────────────
// Each of these guards a failure the old sidestep actually shipped — invisible in review, obvious
// on screen. They pose the real legChain and read the real ankle matrices: the same "measure it,
// don't guess it" discipline as ogre.zig's club tests.
//
// Pose ONE leg mid-sidestep and return its ankle in the PELVIS-CENTRED frame (+x = his LEFT,
// +z = forward, y = height above ground), with the pelvis lowered by exactly STRAFE_DIP.
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
    // Sidestepping to his RIGHT (lat > 0 → travel is world -^'x), so the LEFT leg is the crosser.
    // Its foot must end up PAST the right foot — i.e. further -^'x than the right foot — at its plant.
    const crossedL = testStrafeAnkle(0.0, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const crossedR = testStrafeAnkle(0.0 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(crossedL.x < crossedR.x - 0.05); // genuinely crossed, not merely touching
    // …and half a cycle later the same pair must be UNCROSSED and wide: left back on his left side.
    const openL = testStrafeAnkle(0.5, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const openR = testStrafeAnkle(0.5 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(openL.x > openR.x + 2.0 * hx); // uncrossed AND wider than the hips
    // Mirror it: sidestepping LEFT must cross the other way, or the gait only works one direction.
    const mCrossR = testStrafeAnkle(0.5 + 0.5, -1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    const mCrossL = testStrafeAnkle(0.5, -1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    try std.testing.expect(mCrossR.x > mCrossL.x + 0.05);
}

test "strafe: the crossing leg passes IN FRONT and its partner passes BEHIND" {
    // A leg cannot adduct THROUGH the leg it is standing beside, so the cross has to go around one
    // side or the other. Mid-swing (peak clearance) the crosser's ankle must be forward of the
    // pelvis and the uncrosser's behind it — that pairing IS the grapevine.
    const crossMid = testStrafeAnkle(0.52 + 0.48 * 0.5, 1.0, 1.0, HIPL, KNEEL, BOOT_SOLE[0]);
    const behindMid = testStrafeAnkle(0.52 + 0.48 * 0.5 + 0.5, 1.0, -1.0, HIPR, KNEER, BOOT_SOLE[1]);
    try std.testing.expect(crossMid.z > 0.05);
    try std.testing.expect(behindMid.z < -0.05);
    try std.testing.expect(crossMid.z > behindMid.z + 0.25); // and unmistakably on opposite sides
}

test "strafe: planted feet stay ON the ground and the swing foot actually leaves it" {
    // The failure this catches is the one that shipped: 17 deg of "knee lift" over 13 deg of hip
    // flex netted ~1 cm of clearance once the pelvis dip was subtracted, so the swing foot skimmed
    // the grass and the sidestep read as a slide. It also holds the STRAFE_DIP contract: legChain's
    // vertical solve assumes the caller dropped the pelvis by exactly STRAFE_DIP, and if the two
    // ever disagree the planted feet hover or sink at some abduction angle.
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
    // THE headline bug. Phase advances by DISTANCE, so over a slice of stance the body travels
    // (dPhase · STRAFE_CYCLE) and the planted foot must slide back through the pelvis frame by
    // exactly that much, leaving it fixed in the world. Holding a constant joint angle instead —
    // what "planted dead still" used to mean — drags the foot along under the body.
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
    // Step rate = speed / cycle length, and the sidestep is the SHORTER cycle, so without help it
    // patters. Two things close the gap: STRAFE_CYCLE pushed to the hip-ROM ceiling, and game.zig's
    // mild locked-on lateral speed factor. Pin the result so a retune of either can't quietly
    // reintroduce the patter (or overcorrect into a moonwalk).
    const walkCycle = STRIDE; // at the reference walk speed the stride scale is exactly 1
    const walkCadence = 1.0 / walkCycle; // cycles per unit time at unit speed
    // Off the SHARED constant, not a re-stated literal: this test and `moveHero` have to be talking
    // about the same lateral factor or the ratio it pins is a ratio nothing in the game runs at.
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
    // Bare rig, through the shared `testHero()` — `init` wants a live shader, and pose() only ever
    // touches `rest`. (This was a second copy of that literal five lines below the helper.)
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
    // The owner's report, pinned. An FK gait has no idea where the ground is: the pelvis rides a bob
    // curve while the feet ride joint angles, and every disagreement between them buries a sole.
    // legChain's ankle levelling takes out the big one — a long boot pitching its toe or heel under —
    // so hold it to a shallow residue rather than the several centimetres it used to dig.
    // The WALK is the case the owner reported and the one now genuinely fixed: it used to rake 8.6 cm
    // under; the ankle levelling brings it inside the deliberate hair of embed. Sidesteps are held to
    // the same bar, since legChain's vertical solve pins those feet outright.
    try std.testing.expect(deepestSole(WALK_SPEED, 0.0) > SOLE_Y - 0.015);
    try std.testing.expect(deepestSole(WALK_SPEED, 1.0) > SOLE_Y - 0.015);
    try std.testing.expect(deepestSole(WALK_SPEED, -1.0) > SOLE_Y - 0.015);
    // A DIAGONAL keeps a larger residue: there the normative sagittal gait and the sidestep solve are
    // both driving one leg, and no single knee angle satisfies the gait tables AND the ground. Down
    // from 14 cm by solving against the full hip angle; the rest waits on real foot IK.
    try std.testing.expect(deepestSole(WALK_SPEED, 0.7) > SOLE_Y - 0.08);
    try std.testing.expect(deepestSole(WALK_SPEED, -0.7) > SOLE_Y - 0.08); // …and diagonally
    // RUN and SPRINT keep a KNOWN, larger clip, and its cause is not the feet at all: `rx(bodyPitch)`
    // in pose() rotates the whole body about the WORLD ORIGIN, not about the support foot as its own
    // comment claims, so under a deep run lean any foot swung forward is levered straight down. No
    // ankle angle can undo that — the foot is not mis-angled, it is in the wrong PLACE. Fixing it
    // means pitching about the stance foot, which reshapes the run's signature pose, so it is left
    // alone deliberately (AGENTS.md already records the run-crouch clip as a known gap, and the owner
    // has called a small clip preferable to any float). This bound only stops it getting WORSE.
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
