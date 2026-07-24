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
// A fully articulated human, proportioned from real anthropometry and animated with a
// real gait cycle. Two things make him read as HUMAN rather than a mannequin:
//
//  1. ANATOMY. Every bone length is a fixed fraction of stature H, taken from the
//     Drillis & Contini (1966) body-segment table as tabulated in Winter, "Biomechanics
//     and Motor Control of Human Movement" — copied verbatim below. This is why the
//     half-way point of the body sits at the pubis, the elbow at the navel, etc.
//
//  2. GAIT. The legs are driven by normative sagittal-plane joint-angle curves (hip,
//     knee, ankle over one stride) after Perry, "Gait Analysis" / Winter's normative
//     kinematics — with contralateral arm swing, a twice-per-stride vertical pelvis bob,
//     once-per-stride lateral sway, and pelvic transverse rotation with torso counter-
//     rotation. These are the invariants of human walking, not eyeballed keyframes.
//
// Rendering: a forward-kinematics skeleton. Each bone is a small procedural mesh authored
// in its joint's local frame; per frame `pose()` chains matrices down the hierarchy to a
// world matrix per bone, and `draw()` replays them. Depth pass and lit pass call the same
// `draw()`, so the cast shadow always matches the lit silhouette.

pub const H: f32 = 1.8; // stature (world units ≈ metres)

// Locomotion speeds (world units/sec) — the SINGLE source of truth, shared with game.zig
// (which drives movement + the --shot harness) and with the gait blends below. Elden-Ring
// analog feel: light left-stick = walk, full = run; hold sprint for the dash.
pub const WALK_SPEED: f32 = 1.7;
pub const RUN_SPEED: f32 = 3.4;
pub const SPRINT_SPEED: f32 = 5.1; // hold-B RUN — a touch faster than a full-stick walk-sprint

// Body-segment lengths as a fraction of stature H (Drillis & Contini 1966; Winter).
// Reference joint HEIGHTS off the floor these imply, for sanity: ankle .039, knee .285,
// hip(trochanter) .530, wrist .485, elbow .630, shoulder(acromion) .818, chin .870,
// crown 1.0 — each below is the difference between two of these.
const SEG_THIGH = 0.245; // hip → knee   (femur)   .530-.285
const SEG_SHANK = 0.246; // knee → ankle (tibia)   .285-.039
const SEG_UPARM = 0.188; // shoulder → elbow        .818-.630
const SEG_FOREARM = 0.145; // elbow → wrist         .630-.485

// Skeleton joints (indices). Every joint owns exactly one drawn bone mesh.
const N = 18;
const ROOT = 0; // pelvis
const SPINE = 1; // lumbar / mid-torso pivot
const CHEST = 2; // thorax / shoulder girdle
const NECK = 3;
const HEAD = 4;
const HIPL = 5;
const KNEEL = 6;
const ANKL = 7;
const HIPR = 8;
const KNEER = 9;
const ANKR = 10;
const SHL = 11; // shoulder L
const ELL = 12; // elbow L
const WRL = 13; // wrist L
const SHR = 14;
const ELR = 15;
const WRR = 16;
const SWORD = 17; // the drawn blade, parented to the RIGHT wrist — rides every pose

const parent = [N]i32{ -1, ROOT, SPINE, CHEST, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CHEST, SHL, ELL, CHEST, SHR, ELR, WRR };

// Rest positions in the hero's local standing frame (X = hero's left/+, Y up, Z forward),
// in world units. Limbs hang straight down so each bone mesh aligns with -Y; the small
// A-pose splay and stance width come from constant abduction in the pose, not the rest
// pose (so a bone mesh and its child joint never separate).
fn restPositions() [N]rl.Vector3 {
    const hx = 0.090; // hip half-separation (a touch under half the bi-iliac breadth so the stance isn't splayed)
    const sx = 0.150; // shoulder half-separation (~half the biacromial breadth, plus pauldron room)
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
    r[SWORD] = v3(-sx, 0.485, 0); // zero offset from the wrist; the mesh is authored in the wrist frame
    for (&r) |*p| p.* = v3(p.x * H, p.y * H, p.z * H);
    return r;
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

// ══ ANIMATION ART DIRECTION — the DESIRED LOOK of each state (read before retuning) ══════
// These are the intent; the numeric knobs below are only tuned to hit them. If you change a
// knob, keep it serving the description — and update the description if the intent changes.
//
//  IDLE   : upright, still, but alive — only a slow breathing bob + faint weight settle.
//           No limb motion. Reads "at rest, ready."
//  WALK   : unhurried, grounded, calm. Near-upright torso (~3° lean). RESTRAINED arms — a
//           small swing, the rear arm nearly straight (never both forearms out front, the
//           "zombie arms" failure). LOW hip sway (no waddle). Clear heel→toe stride with a
//           readable knee bend. Feet toe-out slightly; head carries a gentle downward gaze.
//  RUN    : low and aggressive. DEEP forward lean over a LOW centre of gravity (pelvis
//           crouched), the WHOLE body pitched forward about the feet so the COG leads the
//           base — driving, coiled. The HEAD lifts so the gaze lands a few metres AHEAD
//           (~20° down) — off the floor, but NOT craned level/up (capped, natural neck).
//           NORMAL pumping arms bent ~90° (explicitly NOT
//           swept-back "naruto" arms — that was tried and rejected). A real flight phase
//           (both feet airborne) via an up-only bounce; big swing-knee flexion.
//  SPRINT : the run dialled up — even deeper forward tilt (near-diving), lower, longer
//           stride, faster turnover. "Falling forward and catching it."
//  ROLL   : a committed dodge in three beats, souls-style — DIVE into a tight tuck (barely
//           any spin yet), ONE full forward somersault about a low ball centre with the
//           spin EASED (front-loaded: fast over, slower unroll; the 360° lands BEFORE the
//           stand-up), then a spin-free RECOVERY: legs extend to plant, the body rises to
//           stance while the lunge brakes. WABI-SABI, not machined: it goes over ONE
//           shoulder (picked from the leading leg) — banked into that shoulder, slightly
//           off-square, squaring up only as he rises — with the guide arm tucked hard
//           across and the push arm loose, the lead leg balled tighter than the trail,
//           and the magnitudes drifting a touch roll to roll (no two identical). Travel
//           stays DEAD-STRAIGHT — the dodge must feel exact; the imperfection lives
//           entirely in the body. Never a constant-rate spin (a pivoting mannequin), and
//           still snappy — no float/hang.
//  CARRY  : the sword is HELD, never splinted to the arm — the hammer grip cants the
//           blade ~34° forward of the forearm line (tip leading down-forward at rest,
//           clear of the ground: the souls low-ready). The sword arm is a CARRY, not a
//           mirror of the free arm: damped swing, a readier elbow. A WALK keeps that
//           restrained low-ready; a RUN opens it up — the arm eases a touch out to the
//           side, the fore/aft pump mostly stills, and the wrist pitches the blade UP so
//           it rides level with the TIP pointing away from the body, clear of the floor.
//  ATTACK : committed sword cuts, KINETIC-CHAIN sequenced — pelvis rotation, trunk
//           rotation, trunk flexion, shoulder, elbow extension, wrist, each a beat late,
//           so the arm WHIPS (never one rigid unit). LIGHT (R1): a real DESCENDING
//           DIAGONAL — sabre Cut One / kesa-giri (see the CUT MECHANICS note above the
//           AL_* block): an EXAGGERATED readable windup (trunk coiled, knees loaded,
//           fist by the ear, blade lying back over the shoulder), then the hand drops
//           ACROSS the front — high-outside to low-inside, the diagonal carried by
//           ADDUCTION (never a flat shoulder-height "helicopter" sweep) — the wrist
//           ROLLS the cutting edge into the plane of motion and SNAPS the tip down
//           through the line, finishing low past the off hip; the cut ARRESTS and
//           lifts into recovery (an overshoot that settles, never a park). CHAINED
//           lights ALTERNATE, Elden Ring-style: the buffered follow-up comes BACKHAND
//           out of where the last cut landed (Cut Two, the mirrored diagonal, slightly
//           damped — a moulinet re-chamber). HEAVY (R2): slow
//           overhead — the EDGE comes down vertical (grip carries edges fore/aft — a
//           cut, never a flat smack), a big readable
//           windup past vertical over a STAGGERED load (brace leg up, sword-side leg
//           sat back), a breathing "gather" at the top of the raise, a violent trunk-
//           driven drop with a lateral coil whipping past, the blade BURIED low and
//           BITING (a recoil judder) through the held follow-through, then a slow rise.
//           Feet planted (the step is root translation); facing locked at commit. Hit
//           capsule rides the blade, active only inside the strike window (souls
//           TAE-style), swept frame-to-frame. NOTHING parks dead at an end pose.
//  Blends : idle↔walk by a `moving` ease; walk↔run↔sprint by ground SPEED — runB/sprintB
//           chase a short-EASED speed (speedS) so posture never steps when speed does.
//           Stride LENGTH scales with speed so one leg-cycle reads at every pace. Any
//           pose DISCONTINUITY (roll start/end) cross-fades over POSE_XFADE, and the roll
//           heading is eased onto fast (ROLL_YAW_RATE), never teleport-snapped. NOTHING
//           SNAPS — but movement/mechanics stay instant; only the visible pose smooths.
//
// ── gait: normative sagittal joint angles over one stride, sampled every 12.5% (deg) ──
// phase 0 = heel strike of that leg; stance ≈ 0..0.60, swing ≈ 0.60..1.0.
// hip: +flexion (thigh forward). knee: +flexion (bend). ankle: +dorsiflexion (toe up).
const HIP_FLEX = [8]f32{ 25, 13, 3, -5, -10, -3, 12, 22 };
const KNEE_FLEX = [8]f32{ 5, 18, 10, 4, 10, 38, 62, 30 };
const ANK_DORSI = [8]f32{ -2, -6, 2, 9, 6, -14, -6, -1 };

// ── running gait (a distinct cycle, not a sped-up walk) ────────────────────────────
// Sagittal joint angles after Novacheck, "The biomechanics of running" (Gait & Posture
// 1998) and Physiopedia's running-biomechanics normatives: much larger ranges than
// walking, forefoot contact, stance ≈ 40% (toe-off near phase 0.4), a big swing-knee
// flexion (heel toward buttock), and a genuine flight phase (both feet airborne).
const RUN_HIP = [8]f32{ 42, 25, 8, -8, 5, 35, 60, 55 };
const RUN_KNEE = [8]f32{ 26, 48, 40, 28, 62, 98, 80, 44 }; // deeper bend throughout — coiled + low
const RUN_ANK = [8]f32{ -3, 10, 22, 2, -18, -6, 0, -2 };
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

// ── dodge roll (committed tuck-and-somersault) ────────────────────────────────────
// Phased like the FromSoft rolls: dive + somersault up front, then a spin-free recovery
// (their "recovery frames") — NOT one linear spin/tuck/lunge smeared over the duration.
// Knots below are normalized time u = rollT / ROLL_DUR.
const ROLL_DUR = 0.70; // seconds, start to finish (souls medium-roll pacing, recovery included)
const ROLL_DIST = 3.5; // ground units travelled
const ROLL_BALL_Y = 0.50; // pelvis/pivot height at mid-roll (the tucked "ball" centre)
const ROLL_TUCK_IN = 0.16; // dive: crouched + balled by here, spin barely begun
const ROLL_SPIN_A = 0.05; // somersault sweep, two OVERLAPPED eases so the tumble is
const ROLL_SPIN_M0 = 0.40; //   front-loaded, not a metronome: the over-the-shoulder
const ROLL_SPIN_M1 = 0.45; //   tumble (A..M1, ROLL_SPIN_OVER deg) hands off to the
const ROLL_SPIN_B = 0.80; //   slower unroll (M0..B); the full 360° lands here, BEFORE the stand-up
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
// Wabi-sabi: the somersault is imperfect the way a real one is — over ONE shoulder,
// banked and briefly off-square, limbs uneven, magnitudes drifting a touch from roll to
// roll. COSMETIC ONLY: none of these touch duration, distance, heading, or timing — the
// dodge FEELS identical every time.
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
// Anatomy: a cut is a KINETIC CHAIN, released proximal → distal (pelvis rotation → trunk
// rotation → trunk flexion → shoulder → elbow extension, wrist last — Bunn's summation-
// of-speed). Each segment's strike span below fires one LAG beat after the segment
// before it, so the arm WHIPS instead of moving as one rigid unit. Souls pacing: R1 is
// fast and light (contact ~0.2s in, quick recovery); R2 is a slow committed overhead —
// a big readable windup, a violent drop, the blade BURIED through a held follow-through.
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
//   resolved (overshoot settled) but the stand-down tail is skippable, so mashed R1s
//   flow into a continuous combo instead of stuttering through idle each time.
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
const ATK_RETRACK = 9.0; // rad/s — LOCKED-ON only: once a swing is past RECOV_A (the strike
//   has resolved), the hero re-squares onto the lock target through the tail, so a WHIFF
//   doesn't leave him pointing into empty air. The cut itself stays fully committed.
// ── CUT MECHANICS (the light slash) — grounded in period cutting instruction ─────────
// The R1 is the HORIZONTAL cut — sabre Cuts III/IV, the level pair (Roworth, "Art of
// Defence on Foot", 1798; kendo's dō-giri, the flat cut across the trunk): a one-handed
// LEVEL SWIPE that sweeps a wide arc ACROSS THE FRONT at chest height (owner's law: a
// swipe, never a downward poke). What the sources dictate, and where it lives below:
//  - THE ARC LIVES IN ROTATION, NOT ELEVATION: hips → trunk rotate through the cut and
//    the shoulder YAWS the raised arm around the body's vertical axis (SWEEP_WIND →
//    SWEEP_END, ~125° of horizontal travel + ~50° of trunk). The arm's forward-raise
//    (ELEV) holds the swipe PLANE at chest height and barely moves during the strike.
//  - THE BLADE LIES FLAT IN THE PLANE, EDGE LEADING (Hutton, "Cold Steel", 1889: "the
//    edge leads during the passage of the blade along the line"): the swipe RE-GRIPS —
//    the SWORD bone cancels the baked grip cant (GRIP_PITCH) exactly, the wrist then
//    ROLLS the blade a quarter-turn about its own axis (EDGE_ROLL, cone-free by that
//    cancel) so the edge faces the travel and the flat lies horizontal, riding a
//    whisker tip-high (TIP_UP). Ramped in with the raise, drained through recovery —
//    the low-ready carry never changes.
//  - PROXIMAL → DISTAL, WRIST LAST (kendo kinematics; Bunn's summation of speed): the
//    AL_LAG chain fires pelvis → chest → shoulder → elbow → wrist. The blade CHAMBERS
//    laid back over the sword shoulder (WRIST_LAY, trailing the hand like a moulinet
//    passage) and the wrist whips it THROUGH the line last (WRIST_WHIP), in plane.
//  - THE CUT ARRESTS, NEVER PARKS (tenouchi): a small overshoot (AL_OVER) settles out
//    through recovery — and chained lights come BACKHAND out of the finish (Cut IV out
//    of Cut III, the mirrored horizontal) like a moulinet: the return chambers SHALLOW
//    across the chest (ALT_WIND), right where the forehand landed.
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
const AL_EDGE_ROLL = 90.0; // the swipe RE-GRIPS: roll the blade a quarter-turn about its OWN axis
//   so the EDGE LEADS the horizontal pass and the FLAT lies in the swipe plane (edge-horiz,
//   owner's law + Hutton's rule) — cone-free because the SWORD bone first cancels the grip
//   cant exactly, putting the blade dead on the wrist's roll axis
const AL_TIP_UP = 10.0; // then a whisker of tip-high (applied −rx: more-negative = higher in the
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
// Blade hitbox, souls-style: a capsule riding the SWORD bone's dummy points (guard →
// tip), ACTIVE only inside the HIT window (the TAE-events equivalent), with last-frame
// endpoints kept for swept tests so a fast arc can't tunnel through a target between
// frames. One hit per swing per target: the (future) hit list clears on the activation
// edge, where the sweep history also resets.
pub const BLADE_R = 0.34; // capsule radius (world units) — a FAT hit volume, far past the
// visible mesh (invisible in play, only debug-wired). This is the swipe's VERTICAL forgiveness:
// the level arc rides at chest height (~1.25m) while a toad's hurt sphere tops out near ~1.1m
// (lower on small ones), so the pill must reach well below the blade to land on LOW enemies —
// and above it for tall ones — within reason. Thin pills read as whiffs on clean-looking hits.

// ── the swing trail (juice: a fading steel ribbon the blade paints through a cut) ──────
// Samples the outer blade span each frame the TIP really moves; drawn as unlit alpha
// strips in the lit pass only (no shadow, never in the depth pass). Short-lived on
// purpose — a crack of motion behind the edge, not a smoke plume.
const TRAIL_N = 20; // ring capacity (~0.3 s of samples at 60 fps)
const TRAIL_LIFE = 0.20; // seconds a sample persists (long enough that the full level arc
//   still reads as one sheet at the swing's exit)
const TRAIL_MIN_SWEEP = 0.05; // world units the tip must move in a frame to leave a sample
const TRAIL_ROOT = 0.35; // ribbon spans this fraction down the blade → the tip
const TRAIL_COL = rgba(224, 230, 244, 255); // pale steel flash (alpha set per segment)
const TrailSample = struct { a: rl.Vector3 = mathx.zero3, b: rl.Vector3 = mathx.zero3, age: f32 = 1e9 };

// ── combat vitals + what the hero's cuts deal (Elden Ring model, see docs/ELDEN_RING.md) ─
// The hero is sturdier than a toad: mid-weight poise (~ER's Knight-set 51) so a couple of
// bites shrug off, but sustained pressure still flinches then staggers him.
pub const HP_MAX = 100.0;
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
const STAG_STEP = 0.34 * H; // …and the trailing leg shoots back to catch balance (rx deg via knee)
const DEATH_SINK = 0.30; // death: pelvis sinks to this fraction of stance height
pub const DEATH_DUR = 3.6; // collapse + lie still before the hero respawns — long enough for
//   the full YOU DIED choreography (game.zig's overlay reads deathT against this)

// ── the grip (how the sword is HELD) ────────────────────────────────────────────────
// A relaxed hammer grip cants the blade GRIP_PITCH forward of the forearm line — a sword
// is held at an angle to the forearm, never splinted straight along it. Baked into the
// sword MESH about the fist centre (so the grip stays glued in the glove), and into the
// capsule dummy points below; every pose and swing inherits the cant for free.
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
//   walk↔run↔sprint↔stop lean/crouch/arm-pump glide instead of stepping. Movement itself
//   (and stride phase) stays on the RAW speed — responsiveness is untouched. Owner's call:
//   VERY fast (~0.04s full swing) — the stick IS the speed; the glide only kills the step.

// ── locked-on footing: strafe + backpedal (the gait follows travel RELATIVE TO FACING) ──
// While locked the hero faces the foe and walks any direction, so the gait splits by the
// travel direction in the BODY frame: the sagittal leg/arm work scales with the forward
// component — played TIME-REVERSED for a backpedal (backward walking ≈ forward walking
// run backward, Thorstensson 1986) — and the lateral component drives a frontal-plane
// SIDESTEP instead: each leg on its own half-beat swings toward the travel side (near
// leg reaches out, far leg gathers across — a shuffle, no crossover), knee lifting
// through its step so it never drags. Feet keep pointing AT THE TARGET — that is what
// sells the strafe. The direction blends ease fast (visuals only, ~0.1 s per FEEL RULES;
// position answers the stick raw, same frame).
const GAIT_DIR_EASE = 22.0; // 1/s — fwdB/latB chase the body-frame travel direction
const STRAFE_OUT = 16.0; // the LEAD leg's out-step: frontal swing toward the travel side (deg)
const STRAFE_XRZ = 12.0; // the TRAIL leg's cross: frontal swing PAST the midline (deg)…
const STRAFE_CROSS = 13.0; // …with this much forward hip flex, so it plants across the FRONT
//   of the stance leg — the grapevine beat, kept SUBTLE (owner: big splays stick out)
const STRAFE_SPLIT = 1.5; // slight constant stance widening while strafing (never a foot pole)
const STRAFE_STEP_W = 0.22; // width of each leg's step WINDOW (fraction of the cycle). The two
//   legs' windows are offset a QUARTER cycle, so they can never overlap: exactly ONE leg is
//   ever in motion — step, plant, step, plant. Half-cycle offsets with mirrored waves made
//   both legs move at the same instants, mirrored — legs that "can't move separately", the
//   parallel fail (owner's diagnosis, and the actual structural cause).
const STRAFE_KNEE = 17.0; // knee lift through the moving leg's step window (deg)
const STRAFE_SOFT = 8.0; // constant SOFT KNEE in both legs while strafing — the stance stays
//   athletic and springy between steps, never stiff straight poles (owner's note)
const STRAFE_DIP = 0.012 * H; // matching pelvis drop so the soft-kneed legs stay planted
const STRAFE_SWAY = 0.012 * H; // pelvis rides ONTO each planting foot (the weight transfer
//   is what makes a shuffle read as steps, not a slide) — a bit above the walk's sway
const STRAFE_LEAN = 2.5; // torso banks gently INTO the travel side (deg, cosmetic)
const STRAFE_STRIDE = 0.85; // sidestep cycle length (stride-length scale at full lateral) —
//   kept LONG so the gait takes few, big, readable steps instead of a rapid parallel patter
const BACK_STRIDE = 0.85; // backpedal steps shorten a touch too (cautious, toe-reaching)

const STRIDE = 0.85 * H; // ground distance per full (two-step) cycle at walk pace — ties phase to travel, no foot-skate
const WALK_REF_SPEED = WALK_SPEED; // reference walk speed the stride is tuned for
const ARM_SWING = 9.0; // shoulder flex amplitude (deg) at walk — restrained, contralateral to the legs
const A_BOB = 0.024 * H; // vertical pelvis travel (peak-to-peak ~ realistic 4-5 cm at H=1.8)
const A_SWAY = 0.009 * H; // lateral pelvis sway toward the stance foot (subtle — no waddle)
const A_PROT = 3.5; // pelvic transverse rotation (deg)
const A_LIST = 2.0; // pelvic frontal drop toward the swing leg (deg)
const TORSO_LEAN = 3.0; // forward torso lean while walking (deg) — walking is near-upright
const HIP_ADDUCT = 2.0; // constant leg-toward-midline angle so the stance narrows (deg)
const FOOT_TOEOUT = 6.0; // feet splay slightly outward (Fick angle) — a real standing/gait detail
const ARM_ABD = 9.0; // constant arm abduction so arms clear the torso (deg)
const IDLE_KNEE = 4.0;
const IDLE_ELBOW = 6.0;
const MOVING_EASE = 10.0; // idle↔walk blend rate (1/s) — the `moving` fade in update(); fast, so gait answers the stick NOW

fn sampleCurve(tbl: [8]f32, phase: f32) f32 {
    const ph = phase - @floor(phase); // 0..1
    const t = ph * 8.0;
    const base: usize = @intFromFloat(@floor(t));
    const a = base % 8;
    const b = (base + 1) % 8;
    const f = t - @floor(t);
    return tbl[a] + (tbl[b] - tbl[a]) * f;
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
    pos: rl.Vector3 = mathx.zero3, // feet on Y=0
    facing: f32 = 0, // yaw radians, 0 = +Z
    phase: f32 = 0, // stride phase [0,1) (left-leg reference)
    moving: f32 = 0, // eased 0..1 walk blend
    speed: f32 = 0, // this frame's ground speed (world units/sec) — for HUD + stride scaling
    fwdB: f32 = 1, // eased travel-vs-facing FORWARD component (+1 ahead … −1 backpedal)
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
    bladeA: rl.Vector3 = mathx.zero3, // blade capsule endpoints in WORLD space (guard → tip)
    bladeB: rl.Vector3 = mathx.zero3,
    bladeA0: rl.Vector3 = mathx.zero3, // …last frame's endpoints, for swept-capsule hit tests
    bladeB0: rl.Vector3 = mathx.zero3,
    hitWasActive: bool = false, // edge detector: sweep history (+ future hit list) resets on activation
    trail: [TRAIL_N]TrailSample = [_]TrailSample{.{}} ** TRAIL_N, // swing-trail ring (newest at trailHead)
    trailHead: usize = 0,
    // combat
    vit: combat.Vitals = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX),
    stun: combat.StunKind = .none, // .light flinch / .heavy stagger (a committed reaction)
    stunT: f32 = 0, // seconds into the current stagger
    hurtFlash: f32 = 0, // 0..1 red damage-flash intensity (set on any hit, decays) — HUD reads it
    dead: bool = false,
    deathT: f32 = 0, // seconds into the death collapse (respawns at DEATH_DUR)
    spawnPos: rl.Vector3 = mathx.zero3, // where a death respawns the hero
    spawnFacing: f32 = 0,

    // transition smoothing
    speedS: f32 = 0, // short-eased ground speed driving POSTURE blends only
    blendT: f32 = 1e9, // seconds since the last pose discontinuity (≥ POSE_XFADE = no blend)
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
    pub fn update(self: *Hero, dt: f32, movedDist: f32, speed: f32, moveYaw: ?f32) void {
        self.elapsed += dt;
        self.ageTrail(dt);
        self.speed = speed;
        self.speedS = mathx.approach(self.speedS, speed, dt * SPEED_SMOOTH);
        self.blendT = @min(self.blendT + dt, 1e9);
        const target: f32 = if (speed > 0.05) 1.0 else 0.0;
        self.moving = mathx.approach(self.moving, target, dt * MOVING_EASE);
        // Which way travel points in the BODY frame (fast-eased; idle settles forward so
        // the next start from rest begins as a clean forward gait).
        if (moveYaw) |my| {
            const rel = mathx.wrapPi(my - self.facing);
            self.fwdB = mathx.approach(self.fwdB, mathx.cosf(rel), dt * GAIT_DIR_EASE);
            self.latB = mathx.approach(self.latB, -mathx.sinf(rel), dt * GAIT_DIR_EASE);
        } else {
            self.fwdB = mathx.approach(self.fwdB, 1.0, dt * GAIT_DIR_EASE);
            self.latB = mathx.approach(self.latB, 0.0, dt * GAIT_DIR_EASE);
        }
        if (movedDist > 0) {
            // Longer strides at higher speed (as people do), so run/sprint reuse this walk
            // cycle at a believable cadence instead of a frantic shuffle. Sidesteps and
            // backpedal steps run shorter (quicker feet for the same ground).
            const dirScale = mathx.lerpF(1.0, STRAFE_STRIDE, @abs(self.latB)) *
                mathx.lerpF(1.0, BACK_STRIDE, mathx.maxF(0, -self.fwdB));
            const strideLen = STRIDE * mathx.clampF(0.55 + 0.45 * speed / WALK_REF_SPEED, 0.8, 2.0) * dirScale;
            self.phase += movedDist / strideLen;
        }
        self.phase -= @floor(self.phase);
    }

    // Begin a dodge roll in world direction `dir` (falls back to current facing). Ignored
    // while already rolling OR mid-attack — both are committed (mirrors startAttack's guard,
    // so a stray call can't leave rolling+attacking latched together).
    pub fn startRoll(self: *Hero, dir: rl.Vector3) void {
        if (self.rolling or self.attacking) return;
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
        self.elapsed += dt;
        self.ageTrail(dt);
        self.blendT = @min(self.blendT + dt, 1e9);
        self.facing = mathx.approachAngle(self.facing, self.rollYaw, dt * ROLL_YAW_RATE); // whip, don't teleport
        const u = mathx.clampF(self.rollT / ROLL_DUR, 0, 1);
        // Lunge: full speed through the dive + somersault, smooth-braked through the
        // recovery. The profile's integral over u is (BRAKE_A+BRAKE_B)/2, so the peak
        // normalizes to keep total travel = ROLL_DIST.
        const peak = ROLL_DIST / (ROLL_DUR * 0.5 * (ROLL_BRAKE_A + ROLL_BRAKE_B));
        const speed = peak * (1.0 - mathx.smoothstep(ROLL_BRAKE_A, ROLL_BRAKE_B, u));
        const moved = speed * dt;
        self.pos.x = mathx.clampF(self.pos.x + self.rollDir.x * moved, -bounds, bounds);
        self.pos.z = mathx.clampF(self.pos.z + self.rollDir.z * moved, -bounds, bounds);
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
    pub fn requestAttack(self: *Hero, kind: Attack) void {
        if (self.rolling or self.attacking) {
            self.queued = .{ .attack = kind };
        } else self.startAttack(kind);
    }
    pub fn requestRoll(self: *Hero, dir: rl.Vector3) void {
        if (self.rolling or self.attacking) {
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

    // Begin a committed sword attack in the current facing. Ignored while rolling or
    // already mid-swing (player input goes through requestAttack, which buffers instead).
    pub fn startAttack(self: *Hero, kind: Attack) void {
        if (self.rolling or self.attacking) return;
        self.attacking = true;
        self.atkHeavy = kind == .heavy;
        self.atkAlt = false; // a fresh light is always the forehand; chaining flips it (see updateAttack)
        self.atkT = 0;
        self.startXfade(); // whatever pose we were in cross-fades into the windup
    }

    // Advance an in-progress attack: a short committed step into the cut + pose + blade
    // capsule refresh. Call in place of move/update while `attacking`; `bounds` clamps
    // like moveHero. Movement input is ignored — cuts are committed, souls-style.
    // `faceYaw` (the lock target's heading, null unlocked) re-squares the hero through
    // the RECOVERY tail only (ATK_RETRACK): a locked whiff recovers its turning fast.
    pub fn updateAttack(self: *Hero, dt: f32, bounds: f32, faceYaw: ?f32) void {
        self.elapsed += dt;
        self.ageTrail(dt);
        self.blendT = @min(self.blendT + dt, 1e9);
        const dur: f32 = if (self.atkHeavy) ATK_HEAVY_DUR else ATK_LIGHT_DUR;
        const sa: f32 = if (self.atkHeavy) AH_STRIKE_A else AL_STRIKE_A;
        const sb: f32 = if (self.atkHeavy) AH_STRIKE_B else AL_STRIKE_B;
        const lunge: f32 = if (self.atkHeavy) AH_LUNGE else AL_LUNGE;
        const u = mathx.clampF(self.atkT / dur, 0, 1);
        // Step into the cut: the lunge is spread evenly across the strike span.
        const speed: f32 = if (u >= sa and u < sb) lunge / ((sb - sa) * dur) else 0;
        const moved = speed * dt;
        self.pos.x = mathx.clampF(self.pos.x + mathx.sinf(self.facing) * moved, -bounds, bounds);
        self.pos.z = mathx.clampF(self.pos.z + mathx.cosf(self.facing) * moved, -bounds, bounds);
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
            // ER combo naturalism: a light chained off a light ALTERNATES — the return
            // swipe comes backhand out of where the last one landed.
            if (self.attacking and !self.atkHeavy and wasLight) self.atkAlt = !wasAlt;
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
            if (self.attacking and !self.atkHeavy and wasLight) self.atkAlt = !wasAlt; // late-buffered lights still alternate
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
        // Trail sample — only inside the strike's ACTIVE window (the cut paints its arc;
        // the windup/recovery leave nothing) and only while the tip is really sweeping.
        if (self.hitActive() and mathx.lenV(mathx.subV(self.bladeB, self.bladeB0)) > TRAIL_MIN_SWEEP) {
            self.trailHead = (self.trailHead + 1) % TRAIL_N;
            self.trail[self.trailHead] = .{ .a = mathx.lerpV(self.bladeA, self.bladeB, TRAIL_ROOT), .b = self.bladeB, .age = 0 };
        }
        const act = self.hitActive();
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

    // Apply a blow. HP drains; poise/stance drive the flinch/stagger. Any reaction INTERRUPTS
    // the current action (attack/roll) — souls commitment cuts both ways. Call from game.zig
    // after the knot resolves its attacks.
    pub fn takeHit(self: *Hero, h: combat.Hit) void {
        if (self.dead) return;
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
        for (&self.trail) |*s| s.age = mathx.minF(s.age + dt, 1e9);
    }
    fn enterStun(self: *Hero, kind: combat.StunKind) void {
        self.attacking = false; // the reaction drops whatever he was committed to
        self.rolling = false;
        self.queued = null;
        self.stun = kind;
        self.stunT = 0;
        self.speed = 0;
        self.startXfade();
    }
    fn enterDeath(self: *Hero) void {
        self.attacking = false;
        self.rolling = false;
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
        self.elapsed += dt;
        self.ageTrail(dt);
        self.blendT = @min(self.blendT + dt, 1e9);
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
        self.elapsed += dt;
        self.ageTrail(dt);
        self.blendT = @min(self.blendT + dt, 1e9);
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
        // Walk→run blend from the short-EASED ground speed (speedS) so posture (lean,
        // crouch, arm pump) glides across stance changes instead of stepping the frame
        // speed does; sprintB adds extra lean/crouch past full run. Both are gated by
        // FORWARDNESS: the run/sprint presentation (deep lean, crouch, pump, ninja carry)
        // belongs to forward travel — a fast strafe/backpedal stays an upright walk.
        const runB = mathx.clampF((self.speedS - RUN_SPEED_LO) / (RUN_SPEED_HI - RUN_SPEED_LO), 0, 1) * fwPos;
        const sprintB = mathx.clampF((self.speedS - RUN_SPEED_HI) / (SPRINT_REF_SPEED - RUN_SPEED_HI), 0, 1) * fwPos;
        const crouch = (RUN_CROUCH * runB + 0.5 * RUN_CROUCH * sprintB) * m +
            STRAFE_DIP * @abs(lat) * m; // low centre of gravity; strafing settles onto its soft knees

        // ── pelvis oscillations (walk bob ↔ run airtime bounce) ──
        const walkBob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * ph); // twice/stride, symmetric
        const runBounce = A_RUN_BOUNCE * (0.5 - 0.5 * mathx.cosf(2.0 * twoPi * (ph - 0.2))); // up-only, peaks at flight
        const bob = mathx.lerpF(walkBob, runBounce, runB) * m + 0.006 * H * mathx.sinf(self.elapsed * 2.2) * (1.0 - m);
        const sway = A_SWAY * mathx.sinf(twoPi * ph) * m * (1.0 - 0.6 * runB) +
            STRAFE_SWAY * lat * mathx.cosf(twoPi * ph) * m; // strafe: weight sits OVER the planted leg, off the stepping one (cos peaks mid-window)
        const prot = A_PROT * mathx.sinf(twoPi * ph) * m; // pelvic transverse rotation
        const list = A_LIST * mathx.sinf(twoPi * ph) * m; // pelvic frontal drop

        // Root: place at world pos, at hip height (crouched when running), swayed/bobbed in
        // body frame, PITCHED FORWARD ABOUT THE FEET (so the centre of gravity leads the
        // base — the driving, falling-forward run), then faced.
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const bodyPitch = (BODY_PITCH_RUN * runB + (BODY_PITCH_SPRINT - BODY_PITCH_RUN) * sprintB) * m;
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(rz(list), ry(prot)), // tilt/rotate pelvis about its centre
            mul(tr(sway, hipY - crouch + bob, 0), mul(rx(bodyPitch), ry(facingDeg))), // crouch, pitch whole body forward about the feet, then face
            tr(self.pos.x, 0, self.pos.z), // place in the world
        );

        // Spine chain — lean deepens through run into sprint + counter-rotation vs pelvis.
        // The walk lean follows the SIGNED forward blend (a backpedal leans slightly back,
        // a pure strafe stays upright), and the torso banks gently INTO a sidestep.
        const lean = (mathx.lerpF(TORSO_LEAN * fw, RUN_LEAN, runB) + sprintB * (SPRINT_LEAN - RUN_LEAN)) * m;
        const bank = STRAFE_LEAN * lat * m;
        setLocal(&wx, SPINE, self.rest, mul3(rx(lean * 0.5), ry(-0.3 * prot), rz(0.5 * bank)));
        setLocal(&wx, CHEST, self.rest, mul3(rx(lean * 0.5), ry(-0.5 * prot), rz(0.5 * bank)));
        // Idle/walk carries a gentle downward gaze (HEAD_WALK). When running, the body pitch
        // + spine lean would drive the face at the floor, so counter that accumulated tilt
        // down toward ~GAZE_AHEAD — a few metres ahead, NOT level/up — capped so the neck
        // never hyperextends. Split across neck + head so the lift curves naturally.
        const fwdTilt = bodyPitch + lean;
        const gazeCounter = mathx.clampF(fwdTilt - GAZE_AHEAD, 0, NECK_EXT_MAX);
        setLocal(&wx, NECK, self.rest, mul(rx(-0.45 * gazeCounter), ry(-0.2 * prot)));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK - 0.55 * gazeCounter)); // +rx = gaze down (walk); the counter lifts it toward ahead when running

        // Legs — left uses phase, right is half a stride out.
        legChain(&wx, self.rest, ph, m, runB, fw, lat, 1.0, HIPL, KNEEL, ANKL);
        legChain(&wx, self.rest, ph + 0.5, m, runB, fw, lat, -1.0, HIPR, KNEER, ANKR);

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

    // Roll pose, three overlapping beats (the knots above): DIVE — crouch + ball up fast
    // while the spin is barely started; SOMERSAULT — the tucked body tumbles forward about
    // a pivot at ball height, front-loaded (fast over the shoulder, slower unroll) and
    // landing the full 360° early; RECOVERY — spin done, legs extend to plant, pelvis
    // rises back to stance. Wabi-sabi rides on top, all cosmetic: banked into the
    // roll-side shoulder, a few degrees off-square through the recovery (the eyes finding
    // the true heading first), guide arm hard / push arm loose, lead leg tighter than
    // trail, magnitudes drifting per roll (rollVar). After facing, the body's +Z is
    // rollDir, so a +X-axis rotation is a forward roll along it.
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
            tr(self.pos.x, 0, self.pos.z), // place in the world
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

    // R1 — the LEVEL SWIPE (see CUT MECHANICS above), kinetic-chain sequenced: the trunk
    // winds toward the sword side, then pelvis → chest → shoulder → elbow → wrist release
    // in that order (each one AL_LAG late), the blade sweeping one wide horizontal arc
    // across the front at chest height, and the whole load unwinds through the tail.
    // Chained lights ALTERNATE (atkAlt): the FOREHAND sweeps right → left, the RETURN
    // comes backhand out of where it landed — left → right — by mirroring the yaw/sweep
    // terms (chambered shallower: the body blocks a full cross windup).
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
            tr(self.pos.x, 0, self.pos.z),
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
        // Sword arm: the swipe, per the CUT MECHANICS note. rx RAISES the arm into the
        // chest-height plane — on its OWN early ramp (sRaise), fully arrived BEFORE the
        // hit window opens, so the ENTIRE active arc is level (no rising half-vertical
        // early frames). ry is the star — the hand wound around behind the sword
        // shoulder, then SWEPT around the front to past the off shoulder (the overshoot
        // rides it); rz only keeps the arm clear of the torso. The elbow extends late
        // (contact at full reach out front) and the wrist fires LAST.
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
        // Wrist + blade, the RE-GRIP (ramped by lvl through the raise, drained by rec —
        // the low-ready carry outside the swing is untouched): the SWORD bone cancels the
        // baked grip cant EXACTLY, laying the blade dead along the wrist's roll axis;
        // then the wrist rolls it a quarter-turn about that axis (EDGE_ROLL — edge
        // leading, flat in the plane, no cone), tips it a whisker high (TIP_UP), and the
        // LAY→WHIP deviation trails the blade behind the hand through the chamber only,
        // releasing early in the pass — the window sweeps near-RADIAL (blade in line
        // with the long arm, tip at the outer edge), whipping just past straight at the
        // exit. All in the swipe plane.
        const lvl = mathx.smoothstep(0.05, AL_STRIKE_A, u) * rec;
        const lay = sw * (AL_WRIST_LAY * wind - (AL_WRIST_LAY + AL_WRIST_WHIP) * sWr);
        setLocal(&wx, WRR, self.rest, mul3(ry(sw * AL_EDGE_ROLL * lvl), rx(-AL_TIP_UP * lvl), rz(lay)));
        setLocal(&wx, SWORD, self.rest, rx(GRIP_PITCH * lvl)); // +rx maps the baked cant back onto the wrist's −Y exactly (rx(+34)·cant ≡ blade dead on the roll axis)
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
            tr(self.pos.x, 0, self.pos.z),
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

    // Stagger — the reaction when poise (light) or stance (heavy) breaks. The torso RECOILS
    // back, the head snaps with it, the arms fly out and balance goes; the LIGHT flinch is a
    // quick sin pulse, the HEAVY stagger a deep sustained reel (trailing leg thrown back to
    // catch himself) with a wobble — wide open, souls-committed. NOTHING parks: it eases out.
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
        // Knocked back off the blow: the body shifts along −facing (the flinch reads as impact,
        // not a lean). +Z in the pre-facing frame is the facing dir, so a −Z offset = backward.
        const backMag: f32 = if (heavy) 0.10 * H else HURT_STEP;
        const back = backMag * amt;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rz(wob),
            mul(tr(0, hipY - sink, -back), mul(rx(-0.55 * lean), ry(facingDeg))), // whole body snaps back
            tr(self.pos.x, 0, self.pos.z),
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
            tr(self.pos.x, 0, self.pos.z),
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

    // Eye/target point for the camera: roughly the base of the neck, in world space.
    pub fn shoulderPoint(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.rest[CHEST].y, self.pos.z);
    }
};

// offset(child) in the parent's frame = restPos(child) - restPos(parent), since all rest
// orientations are identity. world(child) = local(child) ∘ world(parent), where
// local = animRot ∘ translate(offset) (animRot applied first, about the joint).
fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    const p: usize = @intCast(parent[i]);
    const off = mathx.subV(rest[i], rest[p]);
    const local = mul(animRot, tr(off.x, off.y, off.z));
    wx[i] = mul(local, wx[p]);
}

fn legChain(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, ph: f32, m: f32, runB: f32, sag: f32, lat: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    // Sagittal gait weighted by the forward blend `sag`; a backpedal (sag < 0) samples
    // the SAME normative tables with phase run backward — reversed walking. The lateral
    // blend `lat` drives the CROSSING sidestep instead (the scissor below).
    const phS = if (sag >= 0) ph else -ph;
    const sagW = @abs(sag) * m;
    const hipFlex = mathx.lerpF(sampleCurve(HIP_FLEX, phS), sampleCurve(RUN_HIP, phS), runB) * sagW;
    const kneeWR = mathx.lerpF(sampleCurve(KNEE_FLEX, phS), sampleCurve(RUN_KNEE, phS), runB);
    const ankDorsi = mathx.lerpF(sampleCurve(ANK_DORSI, phS), sampleCurve(RUN_ANK, phS), runB) * sagW;
    // The sidestep scissor: a FULL-wave frontal swing per leg, half a cycle apart — one
    // leg reaches OUT toward the travel side while the other CROSSES past neutral in
    // front of it (the grapevine beat): at any instant the legs oppose, so the gait
    // reads as real crossing steps, never two parallel legs sliding. The crossing leg
    // gets forward hip flex (STRAFE_CROSS) so it visibly steps ACROSS THE FRONT of the
    // stance leg, and each leg's knee lifts through its own step (reach OR cross).
    const latW = @abs(lat) * m;
    // THE SIDESTEP, grapevine-structured: each leg owns a PRIVATE step window, a quarter
    // cycle apart — the lead (travel-side) leg steps OUT first, then the trail leg steps
    // ACROSS the stance leg (the cross), each returning on its own second window (the
    // uncross) — and every leg is PLANTED, dead still, outside its windows. The windows
    // can never overlap, so the legs are fully INDEPENDENT: exactly one moves at any
    // instant. (Half-cycle-offset mirrored waves moved both legs at the same instants —
    // legs that couldn't move separately, the parallel fail: owner's diagnosis.)
    const pShared = blk: { // undo the sagittal half-cycle phase offset — windows share ONE clock
        const raw = ph - (if (side > 0) @as(f32, 0.0) else 0.5);
        break :blk raw - @floor(raw);
    };
    const lead = side * lat < 0; // the leg on the travel side steps first
    const a: f32 = if (lead) 0.0 else 0.25;
    const wave = mathx.smoothstep(a, a + STRAFE_STEP_W, pShared) -
        mathx.smoothstep(a + 0.5, a + 0.5 + STRAFE_STEP_W, pShared);
    const amp: f32 = if (lead) STRAFE_OUT else STRAFE_XRZ;
    const reach = -lat * amp * wave * m; // toward the travel side; the trail leg passes the midline
    const crossF = (if (lead) @as(f32, 0.0) else STRAFE_CROSS) * wave * latW; // trail plants across the FRONT
    // Knee lifts only inside THIS leg's step windows (a half-sine pulse over each); the
    // planted leg's knee stays quiet. The alternation is structural, not tuned.
    const k1 = mathx.clampF((pShared - a) / STRAFE_STEP_W, 0, 1);
    const k2 = mathx.clampF((pShared - a - 0.5) / STRAFE_STEP_W, 0, 1);
    const pulse = mathx.sinf(std.math.pi * k1) + mathx.sinf(std.math.pi * k2);
    const kneeFlex = mathx.lerpF(IDLE_KNEE, kneeWR, sagW) +
        STRAFE_SOFT * latW + STRAFE_KNEE * pulse * latW;
    // hip: sagittal flexion (−rx = thigh forward; the cross adds its own), adduction
    // toward midline, the slight strafe stance-widening, then the step swing.
    setLocal(wx, hip, rest, mul(rx(-hipFlex - crossF), rz(-side * HIP_ADDUCT + side * STRAFE_SPLIT * latW + reach)));
    setLocal(wx, knee, rest, rx(kneeFlex)); // +rx = knee bends (shank swings back/up)
    setLocal(wx, ank, rest, mul(rx(-ankDorsi), ry(side * FOOT_TOEOUT))); // dorsiflex + toe-out splay
}

fn armChain(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, swing: f32, m: f32, runB: f32, sprintB: f32, side: f32, carry: f32, sh: usize, el: usize, wr: usize) void {
    // Contralateral fore/aft swing; the walking elbow tracks the FORWARD swing only (back
    // arm stays nearly straight — no "zombie arms"), and running bends both to ~90° pumping.
    // The sword arm (carry=1) CARRIES instead of mirroring: swing damped, a readier elbow.
    // Carry-arm presentation splits in two: the low tip-LIFT rides on `carryMove` (any stick
    // movement = WALK), while the dramatic "ninja" open-up — the fuller tip-lift, the blade
    // yawed out to the right, the wider abduction, the mostly-stilled pump — rides on `sprint`
    // (RUN = hold-B). So ALL stick speeds keep the humble walk carry; only a hold-B RUN opens
    // it out. (See AGENTS.md: WALK = all stick, RUN = hold-B.)
    const carryMove = carry * m; // any stick movement (WALK)
    const sprint = carry * mathx.clampF(sprintB, 0, 1) * m; // hold-B RUN only
    const sw = swing * (1.0 - CARRY_DAMP * carry) * (1.0 - CARRY_SWING_STILL * sprint);
    const walkElbow = mathx.maxF(6.0, 4.0 + 0.8 * sw);
    const runElbow = mathx.lerpF(RUN_ELBOW, CARRY_ELBOW_RUN, carry);
    const elbow = mathx.maxF(mathx.lerpF(IDLE_ELBOW, mathx.lerpF(walkElbow, runElbow, runB), m), CARRY_ELBOW * carry);
    const abd = ARM_ABD + CARRY_ABD_RUN * sprint; // arm eases out to the side only on a hold-B RUN
    setLocal(wx, sh, rest, mul(rx(-sw), rz(side * abd))); // −rx forward, ±side rz outward
    setLocal(wx, el, rest, rx(-elbow)); // −rx = forearm forward (elbow flexes)
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
// (glove centre (0, FIST_Y, FIST_Z)), with the blade canted GRIP_PITCH forward of the
// forearm line — a sword is HELD at an angle to the forearm, never straight along it. At
// rest (arm hanging) the tip leads down-forward, clear of the ground: the souls
// low-ready. Attacks whip the wrist/arm; the blade just rides. Keep BLADE_BASE/BLADE_TIP
// (the hit capsule dummy points) matched to this geometry.
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
    b.addCube(v3(0, -0.005 * H, 0), v3(0.285 * H, 0.12 * H, 0.165 * H), TUNIC); // 0.695–0.815 H
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

// Asymmetric pauldrons, souls-style: the sword-side (left) shoulder carries the big
// layered leather + steel-rim pauldron; the right makes do with a plain cap.
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

test "gait curves wrap continuously across the stride seam" {
    inline for (.{ HIP_FLEX, KNEE_FLEX, ANK_DORSI, RUN_HIP, RUN_KNEE, RUN_ANK }) |tbl| {
        const nearEnd = sampleCurve(tbl, 0.9999);
        const start = sampleCurve(tbl, 0.0);
        try std.testing.expect(@abs(nearEnd - start) < 1.0);
    }
}
