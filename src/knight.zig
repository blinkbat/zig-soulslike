const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");
const archermod = @import("archer.zig"); // the dead man's own bone palette, chips and dissolve
const ogremod = @import("ogre.zig"); // …and the giant this one has to stand taller than
const propart = @import("propart.zig"); // the world's own ironwork, so his plate is the world's iron

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// THE PLATE IS NEAR-BLACK, and that is the big-mass law rather than a taste call: a cuirass is the largest
// sunward face on the creature, and anything mid-dark comes back off it pale (`albedo^(1/2.2)`). What breaks
// it up is FORM — fluting, rivets, a shoulder line — never a lighter tone.
// **THE IRON IS COLD, AND THE SEPARATION IS ALL HUE** — the ogre's own lesson, one creature along. Authored
// at the world's neutral ironwork (`propart.IRON`, 30/28/26) the door SAMPLED at 144,126,102 against ground
// at 117,107,91: barely a value apart and the same warm hue, so five metres of armour read as one more slab
// of the cliffs behind it. Everything outdoors here is warm, so the one thing that separates a mass this
// large is to be BLUE-BLACK. The value stays near-black; the rust is what keeps it from being a silhouette.
const IRON = rgba(18, 21, 30, 255);
const IRON_LT = rgba(38, 43, 55, 255); // caught-light edges and rolled rims
const IRON_DK = rgba(10, 12, 18, 255); // the shadowed inside of a plate
/// HIS OWN RUST, SOLVED, not the world's. `propart.RUST` (58,38,24) is right on a prop's fleck and wrong on
/// this creature: the door's rim capsules are 2.5 m long, and sampled off the render they came back at
/// 178,129,83 — brighter and far warmer than the ground behind him (129,117,100) and than his own plate
/// (109,107,109). That inverts the whole value hierarchy the plate was solved for, and it competes with the
/// visor's ember, which nothing on him may do. Solved back down the chain (albedo x 1.72 -> gamma 1/2.2) to
/// land near 120 on screen: still visibly rust, no longer trim.
const RUST = rgba(24, 16, 10, 255);
const BRASS = rgba(66, 51, 22, 255); // fittings, gone dull
const VERDI = rgba(40, 58, 48, 255); // …and where the brass has gone green
const STRAP = rgba(34, 26, 19, 255);
// THE BONE UNDERNEATH IS THE ARCHER'S, because it is the archer's body at four times the mass — and a second
// copy of what old bone looks like is a second thing to retune.
const BONE = rgba(126, 116, 92, 255);
const BONE_DK = rgba(74, 67, 53, 255);
const BONE_LT = rgba(152, 142, 118, 255);
/// THE ONE THING ON HIM THAT IS ALIVE: a cold ember down the visor slit. Low alpha IS the emissive channel,
/// so this is the only part of the creature that reads at night or in his own shadow.
const EMBER = rgba(228, 118, 52, 54);
const SOCKET = rgba(12, 10, 9, 255); // the dark behind the slit, so the helm reads as HOLLOW

const DUST = foe.DUST;
const CHIP = archermod.BONE_CHIP;
const SPARK = rgba(255, 206, 126, 240);

/// **THE PLATE IS MATTE, AND THAT IS NOT A TASTE CALL.** `gfx.Mat.steel` carries a deliberately blinding
/// tight specular lobe (`shaders.zig`: "steel POPS"), which is exactly right on a blade and catastrophic on a
/// face the size of a door: the first pass authored the whole suit in it and the tower shield came back as a
/// blank white sheet with the creature invisible behind it. Blackened iron is matte anyway. `.steel` is kept
/// for what is SMALL AND PROUD — rims, rivets, quillons, the blade — which is where a glint says "metal".
const PLATE = gfx.Mat.plain;
const BRIGHT = gfx.Mat.steel;

/// The CLEAVE's ribbon only. A shield bash points down the camera and has no edge to leave a wake.
// **SIZED AGAINST THIS CREATURE, NOT COPIED OFF THE WARRIOR.** These began as his dials, and on a 2.86 m
// blade sweeping 110 deg they came out as an opaque pale SHEET wider and taller than the knight — the
// feedback law's other failure exactly: it hid the creature it exists to point at, and a strip of the stroke
// showed four frames in which the swing was completely invisible behind its own wake. The AREA is not
// negotiable on a blade this long, so the three dials that are: span only the outer half of the edge, live
// well inside the stroke so the whole arc is never resident at once, and carry half the alpha.
const TRAIL_N = 24;
const TRAIL_LIFE = 0.18; // under the 0.26 s strike, so what is on screen is a wake and not the whole sweep
const TRAIL_ROOT = 0.46; // fraction down the blade the ribbon spans from → the point
const TRAIL_PEAK = 88.0;

// THE SHARED 18-BONE SCAFFOLD (hero.zig). Only `hx`, `sx` and the stature are honestly this creature's; the
// joint layout is not transcribed here on purpose.
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
const SHL = heromod.SHL; // the SHIELD arm
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR; // the SWORD arm
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const WPN = heromod.HELD;

const H: f32 = heromod.H;
const HIP_HALF = 0.112; // a broad base — he is a wall on legs
const SHOULDER_HALF = 0.216; // …and pauldrons wide enough to carry the door on one of them
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

/// BIGGER THAN THE OGRE (owner's call), and DERIVED off him so the one fact that makes this creature what it
/// is cannot quietly stop being true the next time the giant's dial is walked. A test pins the crowns.
pub const SCALE = ogremod.SCALE * 1.28;

/// Where a sabaton meets the earth, MEASURED off `footMesh` — `hero.legChain` levels the ankle against this
/// every frame so the plate cannot rake through the ground.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.058 * H, .toe = 0.176 * H, .halfW = 0.058 * H, .drop = 0.039 * H },
    .{ .bone = ANKR, .heel = 0.058 * H, .toe = 0.176 * H, .halfW = 0.058 * H, .drop = 0.039 * H },
};

pub const AGGRO_R = 22.0; // he is a landmark: you are in his fight well before you are in his reach
/// SLOW OFF THE MARK AND SLOWER ROUND (owner: you have to keep getting behind him). This is the number the
/// whole creature is built on, and it is sized against the ANGULAR rate a walking player can carry round a
/// body this wide — which is small, because the radius is: at his own closest approach the hero circles him
/// at only 0.80 rad/s, so anything near a normal creature's turn (the ogre's 3.4) leaves him no back at all.
/// A test brackets it from above. At 33 deg/s a full about-face costs him five seconds.
const TURN_RATE = 0.58; // rad/s
/// …and this much while a stroke is already committed. STILL under `TURN_RATE` — commitment has to cost him
/// tracking or there is no window — but it was 0.40, and against a hero carrying 0.80 rad/s round him a
/// committed stroke shed 32 deg of bearing before it ever arrived, on top of whatever it committed at. So it
/// missed a walking player every time (owner: the swings don't often hit). A test measures the LATERAL miss at
/// the impact frame against the kit's own half-width rather than arguing about the rate.
const SWING_TURN = 0.55;
/// HOW FAST HE PUTS HIS BACK TO YOU as the fall loads. Deliberately the slowest of the three: the strip has
/// to be something a moving player can step out of, and this is the dial that decides how long he gets.
const FALL_AIM = 0.34;
const WALK_SPEED = heromod.WALK_SPEED * 0.66; // a slow, ground-eating tread behind a door of iron

const BODY_R = 0.60; // ground footprint, pre-scale — broad
const HURT_R = 0.78; // the hurt sphere the hero's blade tests, pre-scale
/// WHERE THAT SPHERE IS CENTRED, in the PELVIS BONE's own frame. It is not a height off his feet, and that is
/// the whole point: he spends real seconds of every fight flat on his back, and a sphere pinned to 2.9 m would
/// hang in the air over a body lying on the ground. Read off the posed bone, it goes down when he does.
const CENTER_AT = v3(0, 0.02 * H, 0);
/// THE RETICLE RIDES THE CHEST, NOT THE SKULL — the ogre's rule and its reason: his crown is over five metres
/// up and a mark bolted to it would have the camera craning at the sky all fight.
const LOCK_AT = v3(0, -0.03 * H, 0);
/// …and the HP bar's anchor, off the HELM's own bone for `CENTER_AT`'s reason.
const TOP_AT = v3(0, 0.088 * H, 0);

// THE TOWER SHIELD. The creature IS this thing: everything else about him exists to make you walk round it.
//
// **IT IS WIDER THAN A MAN'S BOARDS AND IT DOES NOT BREAK** (owner's call). The shieldman's guard is a
// stamina pool you empty and then punish; this one has no pool at all, because a shield that breaks turns
// "get behind him" into "hit the front until it falls off", which is the fight this creature is not.
const TOWER_ARC = 105.0; // deg either side of his facing that the door covers
/// …and what it eats. Over the hero's own `GUARD_NEGATE` (0.85) on purpose: chipping him down from the front
/// is possible, tedious, and never staggers him — `combat.guardChip` carries no poise and no stance, so the
/// only way to a punish window is round the side.
const TOWER_NEGATE: f32 = 0.93;

/// HOW FAR OFF DEAD-BEHIND THE HERO MUST BE for the fall to be worth throwing. NOT `TOWER_ARC`: the crush
/// strip is a STRIP, about a metre and a half either side of his spine, so at three metres out it subtends
/// nothing like the whole sector his shield cannot face. A MOVE THAT CANNOT LAND IS NOT A DECISION.
/// The gap between this and `TOWER_ARC` is the safe pocket, and it is his QUARTER rather than his back.
const FALL_SECTOR = 44.0;

/// …AND HOW FAR OFF HIS FACING A STROKE CAN LAND, for the same law one move up. Both his swings are aimed
/// down his own front — the bash goes straight forward and the cleave comes over the top — and neither is a
/// sector test, it is the SWEPT kit. At a bearing past this the kit simply travels past you, so a swing
/// chosen there is a second and a half spent on a guaranteed miss. He turns instead.
/// At 50 he committed from half a sector out and then DRIFTED, so the initial error and the drift added up to
/// a guaranteed miss. The drift is what the swing has to pay for; the error it starts with is free to refuse,
/// so he squares up properly first and turning is what he does instead.
const SWING_BEARING = 24.0;

const Attack = struct {
    /// The AI's TRIGGER RANGE and the parry window's reach — pre-scale, MEASURED off the posed kit at the
    /// impact frame (a test at the foot of this file re-measures it). What the blow actually HITS is the swept
    /// kit, so this can never grow a hurt box the stroke never enters.
    reachOut: f32,
    windDur: f32,
    strikeDur: f32,
    /// Fraction into the stroke the kit goes live.
    impactK: f32,
    recoverDur: f32,
    cd: f32,
    hit: combat.Hit,
    /// The kit really does reach the earth, so the earth answers.
    crash: bool = false,
};

/// THE SHIELD RAMMED FORWARD — the answer to standing in front of him, and the reason the front is not a
/// place to farm chip damage from. Quick, because it is the move he does not have to gather anything for.
const BASH = Attack{
    // MEASURED: the door's own face arrives 2.17 m off his axis. It was 2.92 m while the door was carried at
    // arm's length; pulling it onto his chest (`GUARD_*`, `SH_STANDOFF`) took three quarters of a metre off
    // the ram, so the trigger radius comes down with it — a gate the kit cannot cross is a committed second
    // spent on a guaranteed miss, and this number is BOTH that gate and the parry window's reach.
    .reachOut = 0.74,
    .windDur = 0.78, // …and the gather needs time to be READ, not just to be large
    .strikeDur = 0.22,
    .impactK = 0.44,
    .recoverDur = 0.78,
    .cd = 2.40,
    .hit = BASH_HIT,
};

/// THE GREATSWORD OVERHEAD — a long haul, a crater at the end of it, and the one move that takes the door off
/// his front while it runs (`guardUp`). Baiting this is the other way in.
const CLEAVE = Attack{
    .reachOut = 1.83, // MEASURED: the point crosses 5.39 m out, which is where the blade's length was set from
    .windDur = 1.18,
    .strikeDur = 0.26,
    .impactK = 0.80,
    .recoverDur = 1.55,
    .cd = 3.60,
    .hit = CLEAVE_HIT,
    .crash = true,
};

pub const BASH_HIT = combat.Hit{ .dmg = 27, .poise = 36, .stance = 12 };
pub const CLEAVE_HIT = combat.Hit{ .dmg = 42, .poise = 50, .stance = 24 };
/// THE HARDEST THING TO READ, SO NOT THE HARDEST HIT (owner: it does too much damage). At 50 it took 71% of
/// a 70 HP bar in one blow you cannot parry — two of them from full, off a move whose only counter is having
/// read a tell. It keeps the biggest POISE and STANCE on him, because a body landing on you is still the
/// heaviest thing that happens; what came off is the damage, which now sits under both his own cleave and the
/// ogre's slam. Its price to the player is position, and its price to HIM is the longest opening in the game.
pub const FALL_HIT = combat.Hit{ .dmg = 34, .poise = 64, .stance = 32 };

// THE FALL — he goes over BACKWARD to squash whatever is behind him, lies there, rolls onto his front and
// levers himself up. It is the whole of what makes his back dangerous, and its aftermath is the whole of what
// makes his back worth getting to.
/// HE STOPS TURNING, ROCKS FORWARD AND PUTS HIS BACK TO YOU — the tell, and it is **the longest thing he
/// does** (owner: it needs more tell). At 0.82 it was shorter than his own cleave's 1.18 s haul, so the one
/// move with no parry and no block behind it was read in less time than the one you can catch on the boards.
/// A test now pins it above every swing he has rather than merely above `foe.TELL_MIN`.
const FALL_WIND_DUR = 1.45;
const FALL_DUR = 0.44; // …and then goes, accelerating the whole way
const FALL_IMPACT_K = 0.86; // fraction into the topple his shoulders meet the earth (MEASURED off the pose)
const DOWN_DUR = 2.10; // flat on his back. THIS IS THE PUNISH WINDOW and it is the longest in the game
const ROLL_DUR = 0.72; // over onto his front, in one heave
const RISE_DUR = 1.15; // …and up off the shield, slowly
const FALL_CD = 8.00;
/// HOW FAR BEHIND HIM THE BODY LANDS and HOW WIDE IT LIES — both DERIVED off the rig, in the same
/// times-`scale` units the reaches use, because the strip is not a number chosen beside the creature: it is
/// exactly the ground five metres of armour covers when it goes over. A test brackets the length against his
/// own crown from both sides.
const FALL_LEN = 0.95 * H; // his own standing length
const FALL_HALF_W = SHOULDER_HALF * H * 1.05; // …and his own shoulders, plus the door on one of them
const FALL_BACK_SLACK = 0.30; // times `scale`: how far IN FRONT of his heels the strip still bites
const TOPPLE_DEG = 92.0; // deg of rotation from standing to flat — a hair past, so he is truly down
const LIE_LIFT = 0.34; // pre-scale: half the thickness of an armoured body, so he lies ON the ground
const ROLL_SHIFT = 0.30; // pre-scale: the ground a body crosses rolling over its own thickness
/// …and how far it HEAVES UP over its own side to cross it. Without this the roll was a rotation with no
/// vertical in it at all — the helm moved 13 cm across the whole move, which is a crate turning over rather
/// than a body getting its front under itself.
const ROLL_HUMP = 0.26; // pre-scale
/// How far PAST upright the rise carries before it settles back (`TOPPLE_DEG` units, so 0.06 is ~5.5 deg).
/// A MASS IN MOTION OVERSHOOTS ITS REST — a `smoothstep` that arrives exactly on it is the glide the law
/// forbids, and it was what the old rise did.
const RISE_OVERSHOOT = 0.07;

const HP_MAX = 520.0;
const POISE_MAX = 46.0; // five hero lights to flinch him once — and none of them from the front
const STANCE_MAX = 130.0; // three caught strokes (`combat.PARRY_HIT`) breaks it
/// DRY BONE IN A SUIT — the archer's own table, because it is the archer's body (see AGENTS.md). Fire is the
/// answer to him and the wand is very nearly useless, which is an honest trade and not an oversight.
const RESISTS = combat.resists(.{ .fire = -35, .cold = 60, .chaos = 45 });
/// SOULS the Bone Knight is worth — near three ogres.
pub const SOULS: u32 = 2400;
const DEATH_DUR = 2.20; // a slow, weighty topple — and this one goes over FORWARD, onto his face
const DISS_DUR = 1.40;
/// Sized to the mass going out in it: five metres of armoured skeleton sheds a far wider cloud than a man.
const DISSOLVE = foe.Dissolve{ .rate = 82.0, .spread = 1.15, .rise = 0.72, .flake = CHIP };

const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 6.0;
const HERO_REACH = foe.HERO_REACH;
const PARRY_LEAD = foe.PARRY_LEAD;

/// Per knight, and it is a RING, so its size is arithmetic over the worst frame anything here emits: the
/// FALL's impact is `dustBurst(48)` + `grit(20)` + `plantBurst` (2 x 10) = 88 slots on one frame. At 88 the
/// head lands back where it started and `floorBurst`'s walk would read as empty, so it is the next size up.
const NPART = 112;

const PELVIS_SHARE = 0.14; // BIG BODIES HINGE AT THE WAIST: what the pelvis may take of any body pitch
const STUN_EASE_DEG = 240.0; // how fast a staggered body gives its posture back (the ogre's law: DEGREES)
const STUN_EASE_FRAC = 4.0;
const A_BOB = heromod.A_BOB;
const A_PROT = 5.0; // deg of pelvic transverse rotation — a heavy, square tread

// THE CARRY. The sword rides on the right shoulder, the door is up on the left arm, always.
// A GREATSWORD RIDES POINT-BACK OVER THE SHOULDER LINE, OR IT DRAGS (`warrior.GS_CARRY_*`, and the same
// reason): hung off a plumb arm this blade is 3 m long and came out as a lance held under one elbow.
// **AND IT RIDES ON HIS OWN SIDE, NOT ACROSS HIS BACK** (owner: the sword holding anim is bad). MEASURED:
// at sh−20/el−16/abd24 the fist sat 1.68 m out from his axis — half a metre outside his own shoulder — and
// the point crossed the midline to x +0.18, so a 2.9 m blade lay DIAGONALLY across his back with the pommel
// out one side and the point out the other. That is a plank strapped to a man, not a greatsword shouldered.
// The arm comes IN to the shoulder line and UP, and the blade then stands just behind his sword-side
// pauldron and leans back over it. A test now pins that the point never crosses onto his shield side.
const CARRY_SH = -48.0; // …so the arm is UP, not hanging
const CARRY_EL = -42.0;
const CARRY_ABD = 4.0;
/// `wpnTilt` is deg the blade leads FORWARD of the forearm. MEASURED off the posed bone at six values: at the
/// warrior's own 120 the point sat two metres out in FRONT of him at chest height — a three-metre lance under
/// one elbow — and it comes back over the shoulder at 205. Written as −155 rather than 205, which is the same
/// angle: every wind lerps AWAY from this number, and from +205 the short way round is the wrong way, so the
/// blade windmilled a full turn before the cock.
const CARRY_TILT = -158.0;
// **THE DOOR IS CARRIED AGAINST HIM, NOT OUT ON AN ARM** (owner: it has to keep the shield close to the body
// if it is going to block all frontal). MEASURED at sh52/el−92/abd44 the shield hand stood 1.82 m in front of
// his own chest bone and the door's hub 2.15 m — a wall held at arm's length, with daylight between it and
// the man it is supposed to be shutting. The shoulder comes down out of the reach, the elbow folds the
// forearm across his chest instead of out in front of it, and `SH_STANDOFF` takes the rest.
const GUARD_SH = 6.0; // the shield arm folded hard ACROSS — the door is carried on his middle…
const GUARD_EL = -126.0;
const GUARD_ABD = 12.0;
const GUARD_TWIST = -18.0; // …and he turns his sword side away, presenting the door
const GUARD_LEAN = 7.0;

// THE BASH: gather back onto the rear foot, then the whole body behind the shield.
// **THE GATHER IS THE TELL, SO IT IS BIG** (owner: the telegraphs need more). Authored a few degrees off the
// carry it moved the shoulder 22 deg and the lean 16 across the whole wind — a strip of the wind frame by
// frame showed SIX frames in which nothing visibly happened, which under this game's own reaction law is a
// committed action that shows nothing. Every channel now travels clearly AWAY from where the strike takes it:
// the door hauled back and across, the elbow deeply folded, the shoulders wound off, the weight over the heels.
// …and these are the SAME HAULS as before off the new carry (−44 deg of shoulder, −24 of elbow, +8 of
// abduction). Written as absolutes they are the one thing that quietly loses a tell when the guard pose
// moves: at the old GUARD_SH of 52 a wind to 8 was a 44 deg gather, and at the new 6 it would be nothing.
const BASH_WIND_SH = -38.0;
const BASH_WIND_EL = -150.0;
const BASH_WIND_ABD = 20.0;
const BASH_WIND_TWIST = -58.0;
const BASH_WIND_LEAN = -22.0;
const BASH_HIT_SH = 74.0; // the arm goes LONG — this is where the reach comes from
const BASH_HIT_EL = -14.0;
const BASH_HIT_ABD = 6.0;
const BASH_HIT_TWIST = 30.0;
const BASH_HIT_LEAN = 22.0;
const BASH_STEP = 0.52; // metres of ground the shove carries him, pre-scale

// THE CLEAVE: hauled up and back over the skull in BOTH hands — which is what takes the door off his front.
const CLV_WIND_SH = -152.0;
const CLV_WIND_EL = -46.0;
const CLV_WIND_ABD = 30.0;
const CLV_WIND_TWIST = -44.0;
const CLV_WIND_LEAN = -20.0;
const CLV_WIND_TILT = -58.0;
const CLV_HIT_SH = 78.0;
const CLV_HIT_EL = -12.0;
const CLV_HIT_ABD = -10.0;
const CLV_HIT_TWIST = 40.0;
const CLV_HIT_SWEEP = 20.0;
const CLV_HIT_LEAN = 38.0; // the fold at the waist is what carries the point to the earth
const CLV_END_ATT = 40.0;
const CLV_WIND_ATT = CLV_WIND_SH + CLV_WIND_TILT + 360.0;
const CLV_END_TILT = CLV_END_ATT - CLV_HIT_SH;
/// …and the off hand comes onto the grip for it. The shield stays on the arm; the HAND leaves the strap.
const CLV_OFF_SH = -128.0;
const CLV_OFF_EL = -70.0;
const CLV_OFF_ABD = -16.0;

// THE FALL's own posture. He goes RIGID — a felled statue, not a man tripping.
// **AND THE TELL TRAVELS, not just lasts** (owner: it needs more tell). At −13 deg of hang-back off a 7 deg
// carry the whole gather moved the trunk twenty degrees across the longest wind in the game, which is a
// committed move showing almost nothing. He now rocks a clear 24 deg FORWARD over his toes and then hangs
// 30 deg back past the vertical — a mass visibly going over before it goes.
const FALL_WIND_LEAN = -30.0; // rocks FORWARD first (anticipation), then hangs back over his heels
const FALL_WIND_GATHER = 24.0;
// BOTH ARMS CLAMP IN OVER THE CHEST as he goes — and these are read against the GUARD pose, so they moved
// with it. Authored at 24/−38 against a guard of 52/−92 they were a fold INWARD; against the new 6/−126 the
// same numbers OPENED the arm and swung the door out edge-on beside him through the whole tell, which is the
// one move where the door is what lands on you.
const FALL_SH = 4.0;
const FALL_EL = -100.0;
const FLOORED_TILT = -122.0; // where the blade sits while he is off his feet — a short walk from the carry
const RISE_KNEE = 92.0; // the knee that comes under him
const RISE_HIP = 72.0;
const CRASH_LOW = 0.14; // times `scale`: how low the point must get before the earth answers (0.41 m)

const GATHER_HEAVY = 1.5; // grit a tell drags up, by what is loading
const GATHER_FALL = 1.9;
const GATHER_PLAIN = 0.95;

const State = enum {
    idle,
    approach,
    bashwind,
    bash,
    cleavewind,
    cleave,
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

/// Which stroke a swing/recovery belongs to. The FALL is deliberately in here: its recovery is three states
/// of its own rather than a row of `.recover`, because getting up is not the same shape as unwinding a swing.
const Blow = enum { bash, cleave, fall };

const MOVES = [_]Attack{ BASH, CLEAVE };
const BASH_I = 0;
const CLEAVE_I = 1;

const Choice = enum { fall, strike, approach, wait, hold };

/// Pure, so the whole of his decision-making is testable without a world. `strike` carries WHICH move in a
/// second return, because "he swings" and "he swings the sword" are one decision and splitting them lets the
/// pick fall through onto a move `classify` already refused.
const Decision = struct { what: Choice, mv: usize = BASH_I };

fn classify(dist: f32, bearingDeg: f32, scale: f32, fallReady: bool, ready: []const bool) Decision {
    if (dist > AGGRO_R) return .{ .what = .hold };
    // BEHIND HIM IS WHERE HE FALLS. Dead behind and inside his own length: anywhere else in the sector his
    // shield cannot face, the strip does not reach, so he simply turns instead.
    if (@abs(bearingDeg) >= 180.0 - FALL_SECTOR) {
        if (fallReady and dist <= crushLen(scale)) return .{ .what = .fall };
        return .{ .what = .wait }; // …and turning is what shuts the flank
    }
    // A stroke aimed down his front cannot reach round his shoulder, so on his quarter he only ever turns —
    // asked INSIDE the reach test, or a knight across the field would stand still rather than close.
    const squared = @abs(bearingDeg) <= SWING_BEARING;
    var reached = false;
    for (MOVES, 0..) |a, i| {
        if (dist > triggerR(a, scale)) continue;
        reached = true;
        if (ready[i] and squared) return .{ .what = .strike, .mv = i };
    }
    if (!reached) return .{ .what = .approach };
    return .{ .what = .wait }; // in reach with nothing gathered: he looms, and he keeps turning
}

fn triggerR(a: Attack, scale: f32) f32 {
    return a.reachOut * scale + HERO_REACH;
}

/// HOW FAR BEHIND HIM THE FALL REACHES, hero footprint included — the crush test, the AI's own band and the
/// length test all ask this one function.
fn crushLen(scale: f32) f32 {
    return FALL_LEN * scale + HERO_REACH;
}

/// Grip end -> far end of the sword, in the mesh's own authored frame: ridden through `xf[WPN]` this IS the
/// blade's world segment, and it is the only thing the cleave hits with.
const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;
const SW_GUARD = 0.130 * H; // fist -> crossguard
/// GUARD -> POINT, and it is bracketed from ABOVE by what the cleave is allowed to reach. Authored at 0.84·H
/// — the warrior's own proportion — the blade measured 4.45 m and the stroke arrived 6.9 m off his axis,
/// which out-ranges the ogre's whole sweep and makes walking round him pointless. At 0.54·H it is still a
/// greatsword by proportion (56% of his stature) and the stroke lands where a boss's stroke should.
const SW_BLADE = 0.54 * H;
/// …and the blade at its broadest, which is also the cleave's hurt radius. Narrow enough that `BRIGHT`'s
/// specular reads as an EDGE rather than as a white sheet (see `PLATE`): at 0.046·H the flat was a third of a
/// metre across at scale and blew out solid.
const SW_HALF_W = 0.032 * H;
const SW_SEG = [2]rl.Vector3{
    v3(0, FIST_Y + SW_GUARD, FIST_Z),
    v3(0, FIST_Y + SW_GUARD + SW_BLADE, FIST_Z),
};

/// The sword is authored pointing UP off the grip, so the fit flips it. After that `wpnTilt` means what
/// `hero.GRIP_PITCH` means: degrees the blade leads forward of the forearm line.
fn wpnFit(tilt: f32) rl.Matrix {
    return mul(ry(180.0), rx(180.0 - tilt));
}

/// Authors where the blade POINTS in the world (deg forward of straight down) and bills the wrist for
/// whatever that costs — `warrior.swingTilt`'s law, and for its reason: a tilt held steady through a 200 deg
/// sweep leaves the point buried in the turf beside his own boot.
fn swingTilt(windAtt: f32, endAtt: f32, k: f32, armSh: f32) f32 {
    return lerpF(windAtt, endAtt, k) - armSh;
}

/// For the shot harness to aim its beats with — a portrait pinned to a literal 0.6 s silently photographs a
/// different beat the next time the timing moves.
pub fn moveClock(mv: usize) foe.Clock {
    const a = MOVES[@min(mv, MOVES.len - 1)];
    return .{ .wind = a.windDur, .strike = a.strikeDur, .recover = a.recoverDur };
}
/// …and the FALL's, whose recovery is three states rather than one.
pub const FallClock = struct { wind: f32, drop: f32, down: f32, roll: f32, rise: f32 };
pub fn fallClock() FallClock {
    return .{ .wind = FALL_WIND_DUR, .drop = FALL_DUR, .down = DOWN_DUR, .roll = ROLL_DUR, .rise = RISE_DUR };
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    shield: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("knight material");
        mat.shader = shader;
        return .{ .bone = buildMeshes(), .shield = shieldMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Knight) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        // THE DOOR IS NOT A BONE — it rides the left wrist, `hero.shieldFit`'s pattern (see `shieldXf`).
        rl.drawMesh(self.shield, self.mat, k.shXf);
    }
};

pub const Knight = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS (combat.Root) — stamped from outside, like the leash's eyes. They do NOT gate the
    /// fall: holding a man's feet is very nearly how you make him fall over.
    root: combat.Root = .{},
    /// …and THE HERO'S SHIELD, stamped the same way (`game.markParry`). Read only inside his own windows.
    parry: foe.Parry = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    /// Which move is in progress — an index into `MOVES` — and which family the recovery is serving.
    atk: usize = BASH_I,
    blow: Blow = .bash,
    cds: [MOVES.len]f32 = [_]f32{0} ** MOVES.len,
    fallCd: f32 = 0,
    /// Seconds the sword HANGS at the top of a cleave before it falls, rolled fresh per swing (the ogre's
    /// `windHold`): the tell varies, the parry does not, since the window reads the DROP.
    windHold: f32 = 0,
    dealt: bool = false, // one blow per stroke, latched
    crashed: bool = false, // …and one crater
    /// Where his body already WAS when he died — both channels, see `enterDeath`.
    deathFrom: f32 = 0,
    rollFrom: f32 = 0,
    thud: f32 = 0, // the body's ground-bounce after the fall lands (a decaying ring)
    heroHit: ?combat.Hit = null,
    homing: bool = false,
    strokeDone: f32 = 0, // ground already covered by a bash's shove, so travel integrates once

    /// THE HERO'S SHIELD CAUGHT A STROKE THIS FRAME — a ONE-FRAME flag (`justDied`'s), reset at the top of
    /// `update` and read by the group after.
    parried: bool = false,
    /// Was the door UP at the top of THIS frame. The BEARING is not in it: that belongs to the blow.
    covered: bool = false,
    /// HOW MANY BLOWS THE DOOR HAS EATEN. Not a `hits` — a block is not a body taking a blow — but it IS a
    /// blow that stopped here, which is the only way `foe.pierceGroup` can know a shaft was spent.
    blocks: u32 = 0,
    blockT: f32 = mathx.LONG_AGO,

    // posture channels (degrees), resolved by the state and read by pose()
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
    /// The DECISION stream, its own so a dust-budget change cannot re-deal the fight.
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,
    /// The rig's ORIENTATION alone — yaw, topple and roll, with none of the spine in it. Stamped by `pose`
    /// and read by `shieldXf`, so the door can never be derived from a second copy of where his body is.
    bodyXf: rl.Matrix = undefined,
    shXf: rl.Matrix = undefined,
    /// Where the sword and the door were and are. The hurt tests run BETWEEN them: a stroke this size covers
    /// most of a metre in a frame, and an endpoint-only test passes clean through a body.
    wpnWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    wpnIs: ?[2]rl.Vector3 = null,
    shWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    shIs: ?[2]rl.Vector3 = null,
    /// Set by the stroke, spent AFTER `pose()`: the hurt shape IS the posed kit.
    live: bool = false,
    trail: foe.Trail(TRAIL_N) = .{},

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Knight {
        var k = Knight{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 64871.0, 23);
        k.aiRng = foe.fxStream(seed, 39079.0, 29);
        for (&k.cds) |*c| c.* = 0.3 + seed * 0.8;
        k.pose();
        return k;
    }

    fn move(self: *const Knight) Attack {
        return MOVES[@min(self.atk, MOVES.len - 1)];
    }

    // EVERY WORLD POINT ON HIM COMES OFF A POSED BONE, not off a height above his feet — see `CENTER_AT`.
    pub fn centerWorld(self: *const Knight) rl.Vector3 {
        return foe.markOn(self.xf[ROOT], CENTER_AT);
    }
    pub fn hurtRadius(self: *const Knight) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Knight) f32 {
        return BODY_R * self.scale;
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
    /// He never leaves the ground: the topple is a ROTATION, and his feet are on the earth all through it.
    pub fn airborne(self: *const Knight) bool {
        _ = self;
        return false;
    }
    pub fn kind(self: *const Knight) wf.FoeKind {
        _ = self;
        return .bone_knight;
    }
    pub fn blocksTaken(self: *const Knight) u32 {
        return self.blocks;
    }
    /// IS THE DOOR BETWEEN YOU AND HIM THIS FRAME. The CLEAVE is what takes it away — both hands go on the
    /// grip — and so does every state where he is not standing behind it.
    pub fn guardUp(self: *const Knight) bool {
        if (self.gone) return false;
        return switch (self.state) {
            .idle, .approach, .bashwind, .bash, .fallwind => true,
            .recover => self.blow == .bash, // it never left his arm for a bash; it did for a cleave
            .cleavewind, .cleave, .fall, .downed, .rollover, .rise, .stunlight, .stunheavy, .dead => false,
        };
    }
    /// HOW FAR OVER HE IS: 0 standing, 1 flat on his back, and NEGATIVE is forward — which is the only
    /// direction this creature ever dies in. ONE channel, so the picture, the mark, the bar and the crush
    /// strip cannot tell four different stories about where his body is.
    fn toppleAmt(self: *const Knight) f32 {
        return switch (self.state) {
            // A TOPPLE ACCELERATES. A symmetric ease reads as a controlled lie-down; `u^2` is the arc a mass
            // going over its own base actually takes, and it arrives a hair PAST flat.
            .fall => mathx.minF(1.0, mathx.clampF(self.t / FALL_DUR, 0, 1) * mathx.clampF(self.t / FALL_DUR, 0, 1) * 1.08),
            .downed, .rollover => 1.0,
            // **HE COMES UP OFF HIS FRONT, WHICH IS THE SIDE THE ROLL LEFT HIM ON** — so the topple comes off
            // the NEGATIVE side. `enter(.rise)` turned him about for it; see `turnAbout`.
            // Up in ONE heave off the shield, overshooting upright and settling back onto it (the reactions law).
            .rise => -(1.0 - mathx.smoothstep(RISE_DUR * 0.30, RISE_DUR * 0.84, self.t)) +
                RISE_OVERSHOOT * mathx.pulse(self.t / RISE_DUR, 0.74, 0.86, 0.90, 1.0),
            // **AND A BODY ALREADY ON THE GROUND DOES NOT GET UP TO FALL OVER.** Starting the crumple from
            // `deathFrom` is only half of it: a plain lerp to −1 from a body flat on its BACK passes through
            // ZERO on the way, and zero is STANDING — so a knight killed in his own punish window rose to his
            // feet and toppled forward, which is the exact frame `deathFrom` was added to stop. Past halfway
            // over he is already lying down, and lying down is where he stays.
            .dead => if (@abs(self.deathFrom) > 0.5)
                self.deathFrom
            else
                lerpF(self.deathFrom, -1.0, mathx.smoothstep(0, DEATH_DUR * 0.62, self.t)),
            else => 0,
        };
    }
    /// …AND HOW FAR ROUND HIS OWN LONG AXIS: 0 on his back, 1 face-down. Applied inside the rig's local
    /// frame, so standing it would be a spin on the spot and lying down it is a barrel roll — one rotation,
    /// two readings, and the topple above is what picks which.
    ///
    /// **THE RISE DOES NOT UNWIND IT** (owner: the rolling / getting up part is bad). It used to, and that is
    /// exactly what the move looked like: he heaved onto his front and then rolled straight back onto his
    /// back to stand up off it, so the roll bought nothing and read as a crate rocking twice. Lying on his
    /// back with his head behind his heels, a barrel roll leaves him face-DOWN with his head still behind
    /// them — which in his OWN frame is a body fallen FORWARD and turned about. `turnAbout` writes it as
    /// that, exactly, and the two descriptions are the same matrix, so nothing moves on the frame it swaps.
    fn rollAmt(self: *const Knight) f32 {
        return switch (self.state) {
            // Gathered, then over in one heave — a linear ramp is a body on a rotisserie.
            .rollover => mathx.smoothstep(ROLL_DUR * 0.12, ROLL_DUR * 0.92, self.t),
            // …and killed MID-HEAVE the barrel stays where it got to, `deathFrom`'s reason on the other
            // channel: unwound to square, a body caught half on its side snapped flat on the death frame.
            .dead => self.rollFrom,
            else => 0,
        };
    }
    /// HOW FAR THE DOOR IS OFF HIS FRONT: 0 square to it, 1 turned edge-on and swung out of the way.
    ///
    /// **IT IS THE PICTURE OF `guardUp`, AND IT MAY NEVER DISAGREE WITH IT.** Both hands go onto the grip for
    /// a cleave, so the door has to be seen to leave: the first pass had `guardUp` false through the whole
    /// stroke while the shield still sat square across his chest, which is a mechanic and a picture telling
    /// the player opposite things. It stays 0 for everything he does off his FEET — the topple carries the
    /// door with the body, which is the one time the shield is out of the way by lying down.
    fn stowAmt(self: *const Knight) f32 {
        return switch (self.state) {
            .cleavewind => mathx.smoothstep(0, MOVES[CLEAVE_I].windDur * 0.45, self.t),
            .cleave => 1.0,
            .recover => if (self.blow == .cleave) 1.0 - mathx.smoothstep(0, MOVES[CLEAVE_I].recoverDur * 0.72, self.t) else 0,
            else => 0,
        };
    }

    /// Is he off his feet at all — the one predicate the legs, the gait and the FX all branch on.
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
    /// The hero's bearing off his facing, in degrees (0 dead ahead, +-180 behind).
    fn bearingTo(self: *const Knight, hero: rl.Vector3) f32 {
        const d = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(d) < 1e-3) return 0;
        return mathx.degrees(mathx.wrapPi(mathx.headingXZ(d) - self.facing));
    }

    /// WHERE HE IS TRYING TO WALK, or null when he is not walking anywhere (`game.markWay`). The APPROACH
    /// only: he walks where he is LOOKING and he never strafes, so a bent heading under a committed stroke
    /// would aim the blow at the wall.
    pub fn navWant(self: *const Knight, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .approach) return null;
        return if (self.homing) self.home else hero;
    }

    pub fn update(self: *Knight, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        self.live = false;
        // THE ROOTS HAVE THE FEET AND NOTHING ELSE. Held unconditionally: he cannot leave the ground.
        const grip = foe.grip(&self.root, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.blockT += dt;
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        self.fallCd = mathx.maxF(0, self.fallCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.thud = mathx.maxF(0, self.thud - dt * 2.8);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        self.trail.age(dt);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const a = self.move();
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const bearing = self.bearingTo(hero);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        // THE SHIELD, asked BEFORE the state machine runs this frame's stroke — a catch has to kill the blow
        // it caught, and by the time the hurt test has run the blow is already dealt.
        self.takeParry();
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
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
                } else if (d <= self.longestTrigger() or d > AGGRO_R or self.wantsFall(d, bearing)) {
                    self.decide(d, bearing);
                }
            },
            .bashwind, .cleavewind => {
                self.faceToward(hero, dt * 0.45);
                const dur = self.windDur();
                self.setWind(mathx.smoothstep(0, dur * 0.9, self.t));
                const load: f32 = if (a.crash) GATHER_HEAVY else GATHER_PLAIN;
                self.emitGather(dt, mathx.clampF(self.t / dur, 0, 1) * load);
                if (self.t >= dur) self.enter(if (self.state == .bashwind) .bash else .cleave);
            },
            .bash, .cleave => {
                foe.faceToward(self.pos, &self.facing, hero, SWING_TURN, dt);
                const k = mathx.clampF(self.t / a.strikeDur, 0, 1);
                self.setStrike(foe.swingCurve(k));
                self.driveStroke(k, bounds);
                if (self.t >= a.strikeDur * a.impactK) self.live = true;
                if (self.t >= a.strikeDur) {
                    // EVERY COOLDOWN IS DEALT WITH JITTER (the ogre's law): a boss whose two moves beat in
                    // phase is a boss you learn once and never read again.
                    self.cds[self.atk] = a.cd * self.aiRng.range(0.82, 1.45);
                    self.enter(.recover);
                }
            },
            .recover => {
                const dur = MOVES[@min(self.atk, MOVES.len - 1)].recoverDur;
                self.setRecover(mathx.clampF(self.t / dur, 0, 1));
                if (self.t >= dur) self.decide(d, bearing);
            },
            // HE PUTS HIS BACK TO YOU. Nothing else in the game steers AWAY from the hero, and that is the
            // whole tell: the moment he stops tracking and starts presenting his spine, the strip is loading.
            .fallwind => {
                foe.faceToward(self.pos, &self.facing, self.awayFrom(hero), FALL_AIM, dt);
                self.setFallWind(mathx.clampF(self.t / FALL_WIND_DUR, 0, 1));
                self.emitGather(dt, mathx.clampF(self.t / FALL_WIND_DUR, 0, 1) * GATHER_FALL);
                if (self.t >= FALL_WIND_DUR) self.enter(.fall);
            },
            .fall => {
                self.setFalling(mathx.clampF(self.t / FALL_DUR, 0, 1));
                if (self.t >= FALL_DUR * FALL_IMPACT_K) {
                    self.tryCrush(hero, FALL_HIT);
                    if (!self.dealt) {
                        self.dealt = true;
                        self.thud = 1.0;
                        self.slamGround();
                    }
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
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        // Settled BEFORE the blade, so a hit this frame is judged against the guard he actually held.
        self.covered = self.guardUp();

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.footfalls();
        self.pose();
        // THE BLOW IS JUDGED AFTER THE POSE, because the hurt shape IS the posed kit.
        if (self.live) self.tryReach(hero);
        if (self.state == .cleave) {
            self.crashIn();
            const seg = self.wpnHere();
            self.trail.push(seg[0], seg[1], self.wpnWas[1], TRAIL_ROOT);
        }
        self.tryHit(blade); // the hero's blade LAST, so a kill flags justDied for this frame's beat
        return self.heroHit;
    }

    /// The point on the far side of him from the hero — what the fall steers at.
    fn awayFrom(self: *const Knight, hero: rl.Vector3) rl.Vector3 {
        const back = mathx.dirXZ(hero, self.pos);
        return v3(self.pos.x + back.x, self.pos.y, self.pos.z + back.z);
    }

    fn windDur(self: *const Knight) f32 {
        return self.move().windDur + (if (self.state == .cleavewind) self.windHold else 0);
    }
    fn longestTrigger(self: *const Knight) f32 {
        var r: f32 = 0;
        for (MOVES) |a| r = mathx.maxF(r, triggerR(a, self.scale));
        return r;
    }
    fn wantsFall(self: *const Knight, dist: f32, bearingDeg: f32) bool {
        return self.fallCd <= 0 and @abs(bearingDeg) >= 180.0 - FALL_SECTOR and dist <= crushLen(self.scale);
    }

    /// The bash's shove forward. INTEGRATED off a curve rather than added per frame, so the ground covered is
    /// exact however the frame rate wobbles (the archer's backstep's law).
    fn driveStroke(self: *Knight, k: f32, bounds: f32) void {
        if (self.state != .bash) return;
        const e = 1.0 - (1.0 - k) * (1.0 - k);
        const want = BASH_STEP * self.scale * e;
        mathx.stepXZ(&self.pos, self.fdir(), want - self.strokeDone, bounds);
        self.strokeDone = want;
    }

    /// …AND THE GROUND THE ROLL CROSSES GOES THROUGH `pos` TOO, for the same reason and one more: as an
    /// offset inside the pose it was a body DRAWN a metre from where its hurt sphere and its collider stood,
    /// and it had to snap back to nothing the instant `turnAbout` cleared the roll. Integrated off the roll's
    /// own curve there is nothing to snap and the body is where it looks.
    fn driveRoll(self: *Knight, bounds: f32) void {
        if (self.state != .rollover) return;
        const f = self.fdir();
        const want = ROLL_SHIFT * self.scale * self.rollAmt();
        mathx.stepXZ(&self.pos, v3(f.z, 0, -f.x), want - self.strokeDone, bounds);
        self.strokeDone = want;
    }

    fn enter(self: *Knight, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.crashed = false;
        self.live = false;
        self.strokeDone = 0;
        switch (s) {
            .bashwind => {
                self.blow = .bash;
                sfx.world(.swing_light, self.pos);
            },
            .cleavewind => {
                self.blow = .cleave;
                // Rolled at the REAR, not authored: two cleaves in five fall on the beat and the rest hang.
                self.windHold = if (self.aiRng.float() < 0.45) 0 else self.aiRng.range(0.14, 0.60);
                sfx.world(.swing_heavy, self.pos);
            },
            .fallwind => {
                self.blow = .fall;
                sfx.world(.ogre_roar, self.pos);
                self.plantBurst();
            },
            // THE MOMENT HE COMMITS, in all three channels the parry's law asks for: a heave, dust off both
            // feet (legible from every angle a five-metre stroke foreshortens to nothing in), and the
            // shoulders driving over in the pose behind it.
            .bash, .cleave => {
                sfx.world(.ogre_heave, self.pos);
                self.plantBurst();
            },
            .rollover => sfx.world(.step_hard, self.pos),
            .rise => {
                self.turnAbout();
                sfx.world(.ogre_step, self.pos);
            },
            else => {},
        }
    }

    /// **THE ROLL IS WRITTEN OFF AT THE RISE, NOT UNWOUND BY IT** (see `rollAmt`). Face-down with his head
    /// still behind his heels IS a body fallen forward and turned about, so that is what he becomes: the yaw
    /// takes the half turn and the topple takes the sign. The two poses are the same matrix — `Ry(180)·Rx(θ)`
    /// is `Rx(−θ)·Ry(180)` — so the swap is invisible on the frame it happens, which is the only reason it
    /// may be done at all. He therefore stands up FACING the man he just landed on, which is honest: the head
    /// that went over backward is the end of him that is now nearest you.
    fn turnAbout(self: *Knight) void {
        self.facing = mathx.wrapPi(self.facing + std.math.pi);
    }
    fn enterIdle(self: *Knight) void {
        self.state = .idle;
        self.t = 0;
        self.homing = false;
    }
    fn enterStun(self: *Knight, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.crashed = false;
        self.live = false;
        self.strokeDone = 0;
        self.homing = false;
    }
    /// WHERE HIS BODY ALREADY WAS when it died, so the crumple starts from there. Killed during the punish
    /// window the death began from STANDING — a corpse flat on its back snapped upright and then fell over
    /// forwards, which is the one frame that undoes the whole opening it was killed in.
    fn enterDeath(self: *Knight) void {
        self.deathFrom = self.toppleAmt();
        self.rollFrom = self.rollAmt();
        self.enterStun(.dead);
        self.justDied = true;
    }

    fn decide(self: *Knight, dist: f32, bearingDeg: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            return self.enter(.approach);
        }
        var ready: [MOVES.len]bool = undefined;
        for (&ready, 0..) |*r, i| r.* = self.cds[i] <= 0;
        const dec = classify(dist, bearingDeg, self.scale, self.fallCd <= 0, &ready);
        switch (dec.what) {
            .fall => self.enter(.fallwind),
            .strike => {
                self.atk = dec.mv;
                self.enter(if (dec.mv == BASH_I) .bashwind else .cleavewind);
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
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.enter(.approach);
                } else self.enterIdle();
            },
        }
    }

    /// Off the stamp `pose()` already took — recomputing it is a second place for "where the kit is".
    fn wpnHere(self: *const Knight) [2]rl.Vector3 {
        return self.wpnIs orelse self.weaponSeg();
    }
    fn shieldHere(self: *const Knight) [2]rl.Vector3 {
        return self.shIs orelse self.shieldSeg();
    }
    /// Straight off the posed bone (the ogre's `clubLowWorld` law): nothing about a blow is guessed from yaw.
    pub fn weaponSeg(self: *const Knight) [2]rl.Vector3 {
        return .{
            rl.math.vector3Transform(SW_SEG[0], self.xf[WPN]),
            rl.math.vector3Transform(SW_SEG[1], self.xf[WPN]),
        };
    }
    /// …and the door's own leading face, bottom to top, off the matrix `pose` built for it.
    pub fn shieldSeg(self: *const Knight) [2]rl.Vector3 {
        return .{
            rl.math.vector3Transform(SH_LOW, self.shXf),
            rl.math.vector3Transform(SH_HIGH, self.shXf),
        };
    }

    /// The hurt shape IS the kit: what it swept this frame, against the column the hero stands in, latched to
    /// one blow per stroke — never a yaw-guessed sector.
    fn tryReach(self: *Knight, hero: rl.Vector3) void {
        if (self.dealt) return;
        const bashing = self.state == .bash;
        const r = (if (bashing) SH_HALF else SW_HALF_W) * self.scale + HERO_REACH;
        const was = if (bashing) self.shWas else self.wpnWas;
        const now = if (bashing) self.shieldHere() else self.wpnHere();
        if (!foe.weaponReaches(was, now, hero, r)) return;
        self.heroHit = self.move().hit;
        self.dealt = true;
        self.leash.noteCombat();
    }

    /// THE CRUSH: the ground his body sweeps as it goes over — a STRIP down the line BEHIND him, from a hair
    /// in front of his heels out to his own length. The whole reason his back is not a free ride.
    fn tryCrush(self: *Knight, hero: rl.Vector3, h: combat.Hit) void {
        const to = v3(hero.x - self.pos.x, 0, hero.z - self.pos.z);
        const back = mathx.scaleV(self.fdir(), -1);
        const axial = to.x * back.x + to.z * back.z;
        const lateral = @abs(to.x * back.z - to.z * back.x);
        if (axial < -FALL_BACK_SLACK * self.scale or axial > crushLen(self.scale)) return;
        if (lateral > FALL_HALF_W * self.scale + HERO_REACH) return;
        self.heroHit = h;
        self.leash.noteCombat();
    }

    /// The crater at the end of a cleave: the blade really does reach the earth, so the earth answers — AT
    /// THE POSED POINT, which is where the steel actually is, not a fraction of a reach number.
    fn crashIn(self: *Knight) void {
        if (self.crashed or !self.move().crash) return;
        const tip = self.wpnHere()[1];
        if (tip.y > self.pos.y + CRASH_LOW * self.scale) return;
        self.crashed = true;
        const at = v3(tip.x, self.pos.y, tip.z);
        self.dustBurst(at, 38, 5.4, 0.44);
        self.grit(at, 16);
        sfx.world(.ogre_slam, at); // the game's one "heavy thing meets earth" voice, at the crater
    }

    /// SECONDS UNTIL THIS STROKE'S BLOW LANDS, counted ACROSS the wind->strike boundary so the tell and the
    /// stroke are ONE continuous countdown. EXHAUSTIVE, so a state added later has to say whether it carries
    /// a blow — and the FALL's rows say NULL on purpose: see `parryable`.
    fn toImpact(self: *const Knight) ?f32 {
        const a = self.move();
        const live = a.strikeDur * a.impactK;
        return switch (self.state) {
            .bashwind, .cleavewind => (self.windDur() - self.t) + live,
            .bash, .cleave => live - self.t,
            .idle, .approach, .recover, .fallwind, .fall, .downed, .rollover, .rise, .stunlight, .stunheavy, .dead => null,
        };
    }

    /// THE INSTANT THE KIT CAN BE CAUGHT IN, and how far out it reaches then.
    ///
    /// **THE FALL IS NOT PARRYABLE, AND THAT IS A DECISION.** A parry catches a swing on the boards and turns
    /// it aside; there is nothing to catch in five metres of armour going over, and a shield that stopped one
    /// would make the boards the answer to the one move this creature is built round. Its counter is the ROLL
    /// and reading the tell — which is why the tell is the longest in the game.
    fn parryable(self: *const Knight) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return self.parryReach(self.move());
    }
    /// Where the kit ARRIVES at the impact frame, hero footprint included — the MOVE's own, never one number
    /// for the creature.
    fn parryReach(self: *const Knight, a: Attack) f32 {
        return a.reachOut * self.scale + HERO_REACH;
    }

    /// THE HERO'S SHIELD TAKES THE STROKE. `enterStun` is what kills it — the kit goes dead and nothing
    /// lands. THE ATTACK ALWAYS DIES; THE HEAVY STUN IS EARNED: the boards deal STANCE and nothing else, so
    /// whether a catch is a stumble or a punish window is the same bar the sword has been chipping — and 130
    /// takes three of them.
    fn takeParry(self: *Knight) void {
        const reach = self.parryable() orelse return;
        if (!self.parry.catches(self.pos, reach)) return;
        self.parried = true;
        self.flash = FLASH_DUR;
        self.leash.noteCombat();
        // The move goes on its own cooldown though it never finished: the kit has to be gathered again, or he
        // walks out of the stumble straight into the stroke he was just denied.
        self.cds[self.atk] = self.move().cd;
        // THE SWING VISIBLY STARTS (the ogre's rule): caught in the last instant of a WIND, a plain stun ate
        // the whole stroke and he reeled off a blade that never moved — a parry on empty air.
        switch (self.state) {
            .bashwind => self.setStrike(0.32),
            .cleavewind => self.setStrike(0.28),
            else => {},
        }
        // STRUCK IRON off the kit's own far end, thrown back the way it came.
        const far = if (self.state == .bash or self.state == .bashwind) self.shieldHere()[1] else self.wpnHere()[1];
        self.sparks(far, mathx.dirXZ(self.parry.at, self.pos), 18);
        sfx.world(.bone_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    /// DID THE DOOR STAND BETWEEN HIM AND *THIS* BLOW. The shield is a DIRECTION, so what decides a block is
    /// where the blow CAME FROM, never where he is looking — asked of the BLADE's own segment, since with a
    /// spirit on the field he may be squared up to the wolf.
    fn shielded(self: *const Knight, blade: foe.Blade) bool {
        if (!self.covered) return false;
        const at = mathx.lerpV(blade.a, blade.b, 0.5);
        const d = mathx.dirXZ(self.pos, at);
        if (mathx.lenXZ(d) < 1e-4) return true; // no bearing to be wrong about — the harness's forced block
        return combat.withinArc(mathx.headingXZ(d), self.facing, TOWER_ARC);
    }

    pub fn tryHit(self: *Knight, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const blocked = self.shielded(blade);
        var b = blade;
        if (blocked) b.hit = combat.guardChip(blade.hit, TOWER_NEGATE);
        const s = foe.reached(self, b) orelse return;
        if (blocked) return self.caught(s);
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 0.30, .heavy = 0.55 });
        self.chips(s.contact, s.dir, if (heavyBlow) 22 else 13, if (heavyBlow) 3.6 else 2.5);
        sfx.world(.bone_hurt, self.pos);
        // **ALREADY ON THE GROUND IS THE REACTION.** A flinch state carries no topple, so a heavy landing on
        // a body flat on its back SNAPPED him upright — and that is the one window the whole creature is
        // built to hand you, so the reward for using it was the reward ending. The damage, the flash, the
        // chips and the stance all still land; only the state change is refused, and death still goes
        // through because `enterDeath` now crumples from where the body already lay.
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, 26, 3.2);
                sfx.world(.bone_die, self.pos);
                self.enterDeath();
            },
            .heavy => if (!self.floored()) self.enterStun(.stunheavy),
            .light => if (!self.floored()) self.enterStun(.stunlight),
            .none => {},
        }
    }

    /// THE DOOR TOOK IT. No stamina pool and no break: he gives a hand's width of ground and nothing else,
    /// which is exactly what makes the front the wrong place to be.
    fn caught(self: *Knight, s: foe.Strike) void {
        self.blockT = 0;
        self.blocks += 1;
        self.shove = mathx.scaleV(self.fdir(), -0.35);
        self.sparks(s.contact, s.dir, 16);
        if (s.reaction == .death) {
            // Chipped to death behind his own shield — that is a death, not a block.
            self.hits += 1;
            self.flash = FLASH_DUR;
            sfx.world(.bone_die, self.pos);
            return self.enterDeath();
        }
        sfx.world(.guard_block, self.pos);
    }

    // Debug hooks for the --shot harness (force a beat in isolation).
    pub fn debugBash(self: *Knight) void {
        self.atk = BASH_I;
        self.enter(.bashwind);
    }
    pub fn debugCleave(self: *Knight) void {
        self.atk = CLEAVE_I;
        self.enter(.cleavewind);
        self.windHold = 0; // a framing counted in frames has to land on the same pose every run
    }
    pub fn debugFall(self: *Knight) void {
        self.enter(.fallwind);
    }
    pub fn debugStagger(self: *Knight, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Knight) void {
        self.enterDeath();
    }

    fn setCarry(self: *Knight, dt: f32) void {
        const e = dt * 6.0;
        const breathe = mathx.sinf(self.elapsed * 0.95 + self.seed * 6.28);
        const stalk = self.moving;
        // THE RECOIL OF A CAUGHT BLOW GOES INTO THE MAN, NOT THE ARM (hero.zig's rule): a sink and a step
        // back, so a blow the door CAUGHT never looks like one that knocked it aside.
        const rec = mathx.maxF(0, 1.0 - self.blockT / 0.26);
        self.armSh = mathx.approach(self.armSh, CARRY_SH + 2.5 * breathe - 4.0 * stalk, e);
        self.armEl = mathx.approach(self.armEl, CARRY_EL, e);
        self.armAbd = mathx.approach(self.armAbd, CARRY_ABD + 2.0 * breathe, e);
        self.armSweep = mathx.approach(self.armSweep, 0, e);
        self.wpnTilt = mathx.approach(self.wpnTilt, CARRY_TILT, e);
        self.offSh = mathx.approach(self.offSh, GUARD_SH + 14.0 * rec, e);
        self.offEl = mathx.approach(self.offEl, GUARD_EL - 8.0 * rec, e);
        self.offAbd = mathx.approach(self.offAbd, GUARD_ABD + 1.5 * breathe, e);
        self.bodyLean = mathx.approach(self.bodyLean, GUARD_LEAN + 1.0 * breathe + 5.0 * stalk + 10.0 * rec, e);
        self.twist = mathx.approach(self.twist, GUARD_TWIST, e);
        self.headPitch = mathx.approach(self.headPitch, 3.0 + 1.4 * breathe - 5.0 * stalk + 8.0 * rec, e);
        self.legBrace = mathx.approach(self.legBrace, 0.16 + 0.5 * rec, e);
    }

    /// A STAGGERED BODY GIVES UP ITS POSTURE, and `approach` steps in the units of what it is moving — so ONE
    /// rate cannot serve an angle and a fraction (the ogre's forty-second club arm).
    fn easeNeutral(self: *Knight, dt: f32) void {
        const d = dt * STUN_EASE_DEG;
        self.armSh = mathx.approach(self.armSh, CARRY_SH, d);
        self.armEl = mathx.approach(self.armEl, CARRY_EL, d);
        self.armAbd = mathx.approach(self.armAbd, CARRY_ABD, d);
        self.armSweep = mathx.approach(self.armSweep, 0, d);
        self.wpnTilt = mathx.approach(self.wpnTilt, CARRY_TILT, d * 2.0);
        self.offSh = mathx.approach(self.offSh, GUARD_SH, d);
        self.offEl = mathx.approach(self.offEl, GUARD_EL, d);
        self.offAbd = mathx.approach(self.offAbd, GUARD_ABD, d);
        self.bodyLean = mathx.approach(self.bodyLean, GUARD_LEAN, d);
        self.twist = mathx.approach(self.twist, GUARD_TWIST, d * 2.0);
        self.headPitch = mathx.approach(self.headPitch, 3.0, d);
        self.legBrace = mathx.approach(self.legBrace, 0, dt * STUN_EASE_FRAC);
    }

    /// …and a FLOORED one gives it up differently: the arms stay clamped over the chest and the legs stay
    /// straight, because what says "he is down" is the whole body being one rigid thing on the ground.
    fn easeFloored(self: *Knight, dt: f32) void {
        const d = dt * 120.0;
        self.armSh = mathx.approach(self.armSh, FALL_SH, d);
        self.armEl = mathx.approach(self.armEl, FALL_EL, d);
        self.armAbd = mathx.approach(self.armAbd, 8.0, d);
        self.armSweep = mathx.approach(self.armSweep, 0, d);
        // The blade barely moves as he goes over: a falling knight does not rearrange his sword, and the
        // topple carries it with the arm. A long travel from the carry would windmill it through the fall.
        self.wpnTilt = mathx.approach(self.wpnTilt, FLOORED_TILT, d);
        self.offSh = mathx.approach(self.offSh, FALL_SH, d);
        self.offEl = mathx.approach(self.offEl, FALL_EL, d);
        self.offAbd = mathx.approach(self.offAbd, 6.0, d);
        self.bodyLean = mathx.approach(self.bodyLean, 2.0, d);
        self.twist = mathx.approach(self.twist, 0, d);
        self.headPitch = mathx.approach(self.headPitch, -6.0, d); // the helm tips back off the ground
        self.legBrace = mathx.approach(self.legBrace, 0, dt * STUN_EASE_FRAC);
    }

    fn setWind(self: *Knight, k: f32) void {
        const kArm = k * @sqrt(k); // the loaded arm trails the body and arrives late
        if (self.state == .cleavewind) return self.setCleaveWind(k, kArm);
        self.setBashWind(k, kArm);
    }

    /// Three beats, not one lerp: a GATHER back onto the rear foot, the shield drawn in, a held shiver at the
    /// top. Without the gather an arm travels on frame one, which reads weightless whatever the clock says.
    fn setBashWind(self: *Knight, k: f32, kArm: f32) void {
        const gather = mathx.pulse(k, 0, 0.18, 0.32, 0.56);
        const load = mathx.smoothstep(0.22, 1.0, kArm);
        const shiver = mathx.sinf(self.t * 32.0) * 1.4 * mathx.smoothstep(0.78, 1.0, k);
        self.offSh = lerpF(GUARD_SH, BASH_WIND_SH, load) + shiver;
        self.offEl = lerpF(GUARD_EL, BASH_WIND_EL, load);
        self.offAbd = lerpF(GUARD_ABD, BASH_WIND_ABD, load);
        self.armSh = lerpF(CARRY_SH, CARRY_SH - 12.0, load); // the sword arm is only counterweight here
        self.armEl = lerpF(CARRY_EL, CARRY_EL - 10.0, load);
        self.armAbd = lerpF(CARRY_ABD, CARRY_ABD + 8.0, load);
        self.wpnTilt = lerpF(CARRY_TILT, CARRY_TILT + 10.0, load);
        self.bodyLean = lerpF(GUARD_LEAN, GUARD_LEAN + 8.0, gather) + (BASH_WIND_LEAN - GUARD_LEAN) * load;
        self.twist = lerpF(GUARD_TWIST, BASH_WIND_TWIST, load);
        self.headPitch = lerpF(3.0, -6.0, load);
        self.legBrace = lerpF(0.16, 0.36, gather) + 0.34 * load;
    }

    fn setCleaveWind(self: *Knight, k: f32, kArm: f32) void {
        const shiver = mathx.sinf(self.t * 28.0) * 1.7 * mathx.smoothstep(0.70, 1.0, k);
        self.armSh = lerpF(CARRY_SH, CLV_WIND_SH, kArm) + shiver;
        self.armEl = lerpF(CARRY_EL, CLV_WIND_EL, kArm);
        self.armAbd = lerpF(CARRY_ABD, CLV_WIND_ABD, kArm);
        self.armSweep = lerpF(0, -28.0, kArm); // cocked round BEHIND his sword side, breaking his outline
        self.wpnTilt = lerpF(CARRY_TILT, CLV_WIND_TILT, kArm) + shiver * 0.7;
        // THE SECOND HAND COMES ONTO THE GRIP, which is what takes the door off his front.
        self.offSh = lerpF(GUARD_SH, CLV_OFF_SH, kArm);
        self.offEl = lerpF(GUARD_EL, CLV_OFF_EL, kArm);
        self.offAbd = lerpF(GUARD_ABD, CLV_OFF_ABD, kArm);
        self.bodyLean = lerpF(GUARD_LEAN, CLV_WIND_LEAN, k);
        self.twist = lerpF(GUARD_TWIST, CLV_WIND_TWIST, k);
        self.headPitch = lerpF(3.0, -14.0, k);
        self.legBrace = lerpF(0.16, 0.66, k);
    }

    fn setStrike(self: *Knight, k: f32) void {
        const kW = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k); // the whip: nearly all of it up front
        if (self.state == .cleave or self.state == .cleavewind) return self.setCleave(kW, k);
        self.setBash(kW, k);
    }

    fn setBash(self: *Knight, kW: f32, k: f32) void {
        const over = mathx.smoothstep(0.74, 1.0, k);
        self.offSh = lerpF(BASH_WIND_SH, BASH_HIT_SH, kW) + 5.0 * over;
        self.offEl = lerpF(BASH_WIND_EL, BASH_HIT_EL, kW);
        self.offAbd = lerpF(BASH_WIND_ABD, BASH_HIT_ABD, kW);
        self.armSh = lerpF(CARRY_SH - 12.0, CARRY_SH + 18.0, kW);
        self.armEl = lerpF(CARRY_EL - 10.0, CARRY_EL, kW);
        self.armAbd = lerpF(CARRY_ABD + 8.0, CARRY_ABD - 6.0, kW);
        self.wpnTilt = lerpF(CARRY_TILT + 10.0, CARRY_TILT, kW);
        self.bodyLean = lerpF(BASH_WIND_LEAN, BASH_HIT_LEAN, k);
        self.twist = lerpF(BASH_WIND_TWIST, BASH_HIT_TWIST, kW);
        self.headPitch = lerpF(-6.0, 14.0, kW);
        self.legBrace = lerpF(0.50, 0.72, k);
    }

    fn setCleave(self: *Knight, kW: f32, k: f32) void {
        // THE POINT CROSSES CHEST HEIGHT AND GOES ON INTO THE EARTH: the hit pose is the MIDDLE of the arc.
        self.armSh = lerpF(CLV_WIND_SH, CLV_HIT_SH, kW);
        self.armEl = lerpF(CLV_WIND_EL, CLV_HIT_EL, kW);
        self.armAbd = lerpF(CLV_WIND_ABD, CLV_HIT_ABD, kW);
        self.armSweep = lerpF(-28.0, CLV_HIT_SWEEP, kW); // ACROSS him — this is the diagonal
        self.wpnTilt = swingTilt(CLV_WIND_ATT, CLV_END_ATT, k, self.armSh);
        self.offSh = lerpF(CLV_OFF_SH, CLV_HIT_SH - 22.0, kW);
        self.offEl = lerpF(CLV_OFF_EL, -30.0, kW);
        self.offAbd = lerpF(CLV_OFF_ABD, -40.0, kW);
        self.bodyLean = lerpF(CLV_WIND_LEAN, CLV_HIT_LEAN, k); // the fold drives the point down
        self.twist = lerpF(CLV_WIND_TWIST, CLV_HIT_TWIST, kW);
        self.headPitch = lerpF(-14.0, 28.0, kW);
        self.legBrace = lerpF(0.66, 0.94, k);
    }

    fn setRecover(self: *Knight, u: f32) void {
        const over = 1.0 - mathx.smoothstep(0.30, 1.0, u);
        const heave = mathx.sinf(self.elapsed * 7.0) * 2.6 * over;
        if (self.blow == .cleave) {
            self.armSh = lerpF(CARRY_SH, CLV_HIT_SH, over) + heave * 0.5;
            self.armEl = lerpF(CARRY_EL, CLV_HIT_EL, over);
            self.armAbd = lerpF(CARRY_ABD, CLV_HIT_ABD, over);
            self.armSweep = lerpF(0, CLV_HIT_SWEEP, over);
            self.wpnTilt = lerpF(CARRY_TILT, CLV_END_TILT, over);
            self.offSh = lerpF(GUARD_SH, CLV_HIT_SH - 22.0, over);
            self.offEl = lerpF(GUARD_EL, -30.0, over);
            self.offAbd = lerpF(GUARD_ABD, -40.0, over);
            self.bodyLean = lerpF(GUARD_LEAN, CLV_HIT_LEAN + 6.0, over) + heave;
            self.twist = lerpF(GUARD_TWIST, CLV_HIT_TWIST, over);
            self.headPitch = lerpF(3.0, 32.0, over);
            self.legBrace = lerpF(0.16, 0.92, over);
            return;
        }
        self.offSh = lerpF(GUARD_SH, BASH_HIT_SH + 5.0, over);
        self.offEl = lerpF(GUARD_EL, BASH_HIT_EL, over);
        self.offAbd = lerpF(GUARD_ABD, BASH_HIT_ABD, over);
        self.armSh = lerpF(CARRY_SH, CARRY_SH + 18.0, over);
        self.armEl = lerpF(CARRY_EL, CARRY_EL, over);
        self.armAbd = lerpF(CARRY_ABD, CARRY_ABD - 6.0, over);
        self.wpnTilt = lerpF(CARRY_TILT, CARRY_TILT, over);
        self.bodyLean = lerpF(GUARD_LEAN, BASH_HIT_LEAN, over) + heave * 0.5;
        self.twist = lerpF(GUARD_TWIST, BASH_HIT_TWIST, over);
        self.headPitch = lerpF(3.0, 16.0, over);
        self.legBrace = lerpF(0.16, 0.56, over);
    }

    /// THE TELL. He rocks FORWARD over his toes first — the anticipation every mass owes — and then hangs
    /// back over his heels with the door clamped across his chest, and the knees LOCK. Nothing else on him
    /// straightens its legs to attack.
    fn setFallWind(self: *Knight, k: f32) void {
        const gather = mathx.pulse(k, 0, 0.22, 0.34, 0.62);
        const lock = mathx.smoothstep(0.30, 1.0, k);
        const shiver = mathx.sinf(self.t * 24.0) * 1.6 * mathx.smoothstep(0.66, 1.0, k);
        self.offSh = lerpF(GUARD_SH, FALL_SH, lock);
        self.offEl = lerpF(GUARD_EL, FALL_EL, lock);
        self.offAbd = lerpF(GUARD_ABD, 10.0, lock);
        self.armSh = lerpF(CARRY_SH, FALL_SH, lock);
        self.armEl = lerpF(CARRY_EL, FALL_EL, lock);
        self.armAbd = lerpF(CARRY_ABD, 8.0, lock);
        self.armSweep = lerpF(0, 0, lock);
        self.wpnTilt = lerpF(CARRY_TILT, 110.0, lock);
        self.bodyLean = lerpF(GUARD_LEAN, FALL_WIND_GATHER, gather) + (FALL_WIND_LEAN - GUARD_LEAN) * lock + shiver;
        self.twist = lerpF(GUARD_TWIST, 0, lock);
        self.headPitch = lerpF(3.0, -30.0, lock); // the helm comes up: he is not looking at you any more
        self.legBrace = lerpF(0.16, 0.40, gather) * (1.0 - lock); // …and the knees LOCK OUT
    }

    fn setFalling(self: *Knight, k: f32) void {
        self.bodyLean = lerpF(FALL_WIND_LEAN, 4.0, k); // he straightens as he goes: a felled statue
        self.offSh = FALL_SH;
        self.offEl = FALL_EL;
        self.armSh = FALL_SH;
        self.armEl = FALL_EL;
        self.headPitch = lerpF(-18.0, -4.0, k);
        self.legBrace = 0;
    }

    /// THE HEAVE ONTO HIS FRONT. **A RIGID BODY CANNOT ROLL** — both arms clamped over the chest and both
    /// legs straight is why this read as a crate turning over (owner). The sword arm is THROWN across him
    /// first and the body follows it, the shield elbow drives him off the ground, and the shoulders lead the
    /// hips (`twist`), which is what a roll actually is.
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
        self.twist = -24.0 * throwArm; // the shoulders go first and the hips are dragged after them
        self.headPitch = -6.0 + 18.0 * throwArm;
        self.legBrace = 0;
    }

    /// UP OFF THE SHIELD, and it is the slowest thing he does. He is on his FRONT by now (`turnAbout`), so
    /// the knee that comes under him is what makes it a rise and not a hoist.
    fn setRise(self: *Knight, u: f32) void {
        const push = mathx.pulse(u, 0.10, 0.40, 0.58, 0.92); // the heave on the shield arm
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

    /// The whole rig's scale, dissipation included. ONE definition: the door is not a bone and has to arrive
    /// at the same number `pose` did, or it shrinks on a different curve to the arm holding it.
    pub fn rigScale(self: *const Knight) f32 {
        return self.scale * (1.0 - 0.62 * self.fade);
    }

    pub fn pose(self: *Knight) void {
        const fs = self.rigScale();
        const sink = -0.9 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const stun = self.stunAmount();
        const topple = self.toppleAmt();
        const roll = self.rollAmt();
        const down = @abs(topple);

        const m = self.moving * (1.0 - down);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const sway = heromod.strafeSway(0, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB);
        // THE LEGS TAKE THE BRACE IN THE KNEES, they do not squat: only the small pelvis drop a real knee
        // bend costs.
        const braceSink = 0.034 * H * self.legBrace;

        var wx: [N]rl.Matrix = undefined;
        const bodyPitch = self.bodyLean * (1.0 - down) - 26.0 * stun;
        const pitchRoot = bodyPitch * PELVIS_SHARE;
        // …and once he is over, the RING: a mass in motion overshoots its rest and settles back onto it, so
        // the body bounces once off the earth rather than arriving and stopping.
        // **ITS PHASE IS THE DECAY ITSELF, NOT A CLOCK BESIDE IT.** Read off `self.t` the ring restarted from
        // zero on every state change while `thud` was still ringing, and `.fall`→`.downed` lands inside it —
        // which snapped the whole body a quarter of a metre down its own length on that frame. Driven off
        // `thud` it starts at 0 when the thud is armed, rings out over exactly three half-cycles, and is back
        // at 0 when the decay is: continuous at both ends and blind to which state is holding it.
        const ring = self.thud * mathx.sinf((1.0 - self.thud) * 3.0 * std.math.pi);
        // …and the roll HEAVES the body up over its own side and drops it on the far one. Half a period of a
        // sine over the roll, so it is back on the ground at both ends of it.
        const hump = ROLL_HUMP * mathx.sinf(std.math.pi * roll);
        const lieLift = (LIE_LIFT * down + 0.10 * ring + hump) * self.scale;
        const pelvY = hipY + bob - braceSink;

        // ONE ORIENTATION FOR THE WHOLE BODY — the roll about his own long axis inside the rig, the topple
        // about the ground between his feet, then his yaw. Stamped, because the door reads it back.
        self.bodyXf = mul3(ry(180.0 * roll), rx(-TOPPLE_DEG * topple), ry(facingDeg));
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(0), rx(pitchRoot), ry(prot + self.twist * 0.20 + 180.0 * roll)),
            mul3(tr(sway * fs, pelvY * fs + sink, 0), rx(-TOPPLE_DEG * topple), tr(0, lieLift, 0)),
            mul(ry(facingDeg), heromod.rootAt(self.pos)),
        ));

        // `hero.legChain` owns the legs whenever nothing else has taken them: the fall, the rise and the
        // death crumple each pose them outright, and they are mutually exclusive by construction.
        if (!dead and !self.floored()) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, 0, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, 0, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, stun, dead, prot, bodyPitch);
        self.xf = wx;
        // …and the kit's own sweep is stamped LAST, off the pose that was just built.
        self.shXf = shieldXf(self);
        const seg = self.weaponSeg();
        self.wpnWas = self.wpnIs orelse seg;
        self.wpnIs = seg;
        const sh = self.shieldSeg();
        self.shWas = self.shIs orelse sh;
        self.shIs = sh;
    }

    fn poseUpper(self: *Knight, wx: *[N]rl.Matrix, stun: f32, dead: bool, prot: f32, bodyPitch: f32) void {
        const rest = self.rest;
        const wonk = (self.seed - 0.5) * 5.0; // each one stands its own crooked way (cosmetic only)
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
            // He goes over FORWARD onto his face, which is the one thing that separates a death from the
            // fall he does on purpose — and the legs buckle rather than staying locked.
            setLocal(wx, HIPL, rest, mul(rx(34.0 * dk), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + 74.0 * dk));
            setLocal(wx, ANKL, rest, rx(18.0 * dk));
            setLocal(wx, HIPR, rest, mul(rx(28.0 * dk), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + 62.0 * dk));
            setLocal(wx, ANKR, rest, rx(14.0 * dk));
        } else if (self.floored()) {
            // ONE KNEE COMES UNDER HIM on the rise and the other stays out — symmetric legs would be a
            // sit-up. Flat, both are straight: a felled statue does not bend. …and the TOP LEG is thrown
            // over on the roll, because that is the half of a roll the arms cannot do.
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

        setLocal(wx, SHL, rest, mul3(
            rx(-self.offSh + armStun - 16.0 * dk),
            rz(-self.offAbd - wonk * 0.4),
            ry(self.armSweep * 0.30),
        ));
        setLocal(wx, ELL, rest, rx(self.offEl));
        setLocal(wx, WRL, rest, rz(5.0));
    }

    // He does not bleed: every burst here is DUST, BONE or struck IRON.

    fn emit(self: *Knight, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }

    fn dustBurst(self: *Knight, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.45, 1.0) * spd * self.scale;
            self.emit(
                v3(c.x, self.pos.y + 0.06, c.z),
                v3(mathx.cosf(a) * s, self.fxRng.range(0.8, 3.0), mathx.sinf(a) * s),
                self.fxRng.range(0.42, 0.76),
                self.fxRng.range(0.08, 0.17) * self.scale,
                big * self.fxRng.range(0.8, 1.35) * self.scale,
                DUST,
                4.4,
            );
        }
    }
    fn grit(self: *Knight, c: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(1.3, 3.6) * self.scale;
            self.emit(
                v3(c.x, self.pos.y + 0.09, c.z),
                v3(mathx.cosf(a) * s, self.fxRng.range(2.6, 5.6), mathx.sinf(a) * s),
                self.fxRng.range(0.48, 0.9),
                self.fxRng.range(0.026, 0.058) * self.scale,
                0.012,
                CHIP,
                9.0,
            );
        }
    }
    fn chips(self: *Knight, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            self.emit(
                at,
                v3(dir.x * sp + mathx.cosf(a) * self.fxRng.range(0.2, 1.2), self.fxRng.range(0.9, 3.2), dir.z * sp + mathx.sinf(a) * self.fxRng.range(0.2, 1.2)),
                self.fxRng.range(0.34, 0.64),
                self.fxRng.range(0.024, 0.055) * self.scale,
                0.008,
                CHIP,
                8.0,
            );
        }
    }
    fn sparks(self: *Knight, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.5, 4.4);
            self.emit(
                at,
                v3(-dir.x * sp * 0.5 + mathx.cosf(a) * sp * 0.6, self.fxRng.range(1.2, 3.8), -dir.z * sp * 0.5 + mathx.sinf(a) * sp * 0.6),
                self.fxRng.range(0.16, 0.34),
                self.fxRng.range(0.015, 0.032),
                0.002,
                SPARK,
                6.0,
            );
        }
    }
    /// BOTH FEET SETTING as a stroke is thrown — the visible half of the commit tell. Off the FEET rather
    /// than the kit: a giant swings by planting, and dust on the ground is legible from every angle a
    /// five-metre stroke foreshortens to nothing in.
    fn plantBurst(self: *Knight) void {
        const f = self.fdir();
        for ([_]f32{ -1, 1 }) |side| {
            const rr = 0.40 * self.scale;
            const at = v3(self.pos.x - f.z * side * rr, self.pos.y + 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(at, 10, 2.1, 0.22);
        }
    }
    /// THE BODY MEETING THE EARTH — a wall of dust down the whole strip he has just filled, not a puff at his
    /// feet: what has to read is the LENGTH of what landed on you.
    fn slamGround(self: *Knight) void {
        const back = mathx.scaleV(self.fdir(), -1);
        const mid = v3(self.pos.x + back.x * 0.55 * FALL_LEN * self.scale, self.pos.y, self.pos.z + back.z * 0.55 * FALL_LEN * self.scale);
        const from = self.fxHead;
        self.dustBurst(mid, 48, 5.8, 0.52);
        self.grit(mid, 20);
        foe.floorBurst(&self.parts, from, self.fxHead, self.pos.y);
        sfx.world(.ogre_slam, mid);
    }
    fn emitGather(self: *Knight, dt: f32, k: f32) void {
        self.fxAccum += (6.0 + 28.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 0.8) * self.scale;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.05, self.pos.z + mathx.sinf(a) * rr),
                v3(self.fxRng.signed() * 0.5, self.fxRng.range(0.3, 1.4), self.fxRng.signed() * 0.5),
                self.fxRng.range(0.28, 0.52),
                self.fxRng.range(0.035, 0.08) * self.scale,
                0.014,
                DUST,
                3.2,
            );
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
        self.dustBurst(at, 7, 1.5, 0.16);
        sfx.world(.ogre_step, at);
    }
    pub fn drawFx(self: *const Knight) void {
        foe.drawParticles(&self.parts);
        self.trail.draw(TRAIL_LIFE, foe.WAKE, TRAIL_PEAK);
    }

    pub fn draw(self: *const Knight, model: *const Model) void {
        model.draw(self);
    }
};

const CAP = wf.MAX_PER_KIND;

/// THE VIGIL — what is left standing watch over the fallen city.
pub const Vigil = struct {
    model: Model,
    knights: [CAP]Knight = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Vigil {
        return .{ .model = Model.init(shader) };
    }
    /// The knights this map posted — never iterate the whole array, the tail is `undefined`.
    pub fn live(self: *Vigil) []Knight {
        return self.knights[0..self.n];
    }
    pub fn liveConst(self: *const Vigil) []const Knight {
        return self.knights[0..self.n];
    }
    pub fn reset(self: *Vigil, m: *const wf.Map) void {
        foe.resetGroup(Knight, &self.knights, &self.n, m, .bone_knight);
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
    pub fn update(self: *Vigil, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Vigil, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Vigil) void {
        for (self.liveConst()) |*k| k.drawFx();
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

// Plate over old bone. `addBox`/`addCube` is right here — this is iron, and the round-mass law is about
// FLESH — but a cuirass is still the biggest sunward face in the game, so it is near-black and what breaks
// it up is fluting and rivets rather than a lighter tone.

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
    mesh[SHR] = upperArmMesh(-1.0, 1.06); // the sword arm carries the heavier plate
    mesh[ELR] = forearmMesh(-1.0, 1.06);
    mesh[WRR] = gauntletMesh(false);
    mesh[WPN] = swordMesh();
    return mesh;
}

/// A FEW POINTS OF VALUE EITHER SIDE OF ONE TONE — hammer marks, not a second colour. This is what keeps a
/// wall of bands one substance instead of a barber's pole (see `shieldMesh`).
fn shade(c: rl.Color, d: f32) rl.Color {
    return rgba(
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.r)) + d, 0, 255)),
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.g)) + d, 0, 255)),
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.b)) + d, 0, 255)),
        c.a,
    );
}

/// A PLATE: a shallow box with a rolled rim along its top, so a limb reads as armoured rather than as a
/// cylinder painted grey. The rim is the FORM BREAK the dark albedo needs.
fn plate(b: *Builder, c: rl.Vector3, half: rl.Vector3, col: rl.Color) void {
    b.addRoundBox(c, v3(half.x * 2, half.y * 2, half.z * 2), mathx.minF(half.x, half.z) * 0.55, 3, 8, col);
    b.addCapsule(
        v3(c.x - half.x * 0.9, c.y + half.y, c.z),
        v3(c.x + half.x * 0.9, c.y + half.y, c.z),
        half.z * 0.34,
        half.z * 0.30,
        7,
        IRON_LT,
    );
}

/// The old bone showing through a gap in the plate — what says this is a corpse in a suit rather than a suit.
fn shaft(b: *Builder, rng: *mathx.Rng, a: rl.Vector3, e: rl.Vector3, r: f32) void {
    const mid = mathx.lerpV(a, e, 0.5);
    b.addCylinder(a, mid, r, r * rng.range(0.78, 0.9), 7, BONE);
    b.addCylinder(mid, e, r * 0.84, r * 0.94, 7, BONE_DK);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4201);
    b.setMat(.plain);
    b.addCube(v3(0, 0.004 * H, -0.018 * H), v3(0.10 * H, 0.098 * H, 0.086 * H), BONE_DK); // the sacrum wedge
    // THE ILIAC BLADES STAY INSIDE THE SUIT — the limbs' law (bone shows at the JOINTS) one bone along.
    // Authored at ±0.095·H they reached 0.169·H, out past the belt and the faulds both, and old bone renders
    // near-white: two cream fins stood off the hips of a blue-black creature.
    b.addBox(v3(0.046 * H, 0.020 * H, 0), v3(0.040 * H, 0.026 * H, 0), v3(0.012 * H, 0.070 * H, 0), v3(0, 0, 0.062 * H), BONE);
    b.addBox(v3(-0.044 * H, 0.016 * H, 0), v3(0.038 * H, 0.022 * H, 0), v3(-0.010 * H, 0.064 * H, 0), v3(0, 0, 0.058 * H), BONE_DK);
    b.setMat(PLATE);
    // THE WAIST HAS A CORE, and it is the masonry law on a body: the faulds and the belt are only the FACING,
    // and a hoop of leather round nothing is a hoop you see the sunlit inside of. It is a CLOSED box (an
    // `addCylinder` here is one more open cut-pipe end) sized just inside the belt's 0.140·H, and it overlaps
    // well past both the top lame below it and the cuirass above.
    b.addRoundBox(v3(0, 0.036 * H, 0), v3(0.216 * H, 0.150 * H, 0.180 * H), 0.048 * H, 3, 11, IRON_DK);
    // THE FAULDS: overlapping lames round the hips, each its own width and none of them level. Uneven is
    // what stops a skirt of plates reading as a lampshade.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const y = -0.010 * H - fi * 0.036 * H;
        const rr = (0.132 - fi * 0.008) * H * rng.range(0.97, 1.03);
        b.addCylinder(v3(0, y, 0), v3(0, y - 0.040 * H, 0), rr, rr * 0.96, 11, if (i % 2 == 0) IRON else IRON_DK);
        b.addCylinder(v3(0, y, 0), v3(0, y - 0.006 * H, 0), rr * 1.03, rr * 1.03, 11, IRON_LT); // the rolled lip
    }
    b.setMat(.leather);
    // A BELT GOES ROUND HIM, SO ITS AXIS IS VERTICAL. Authored across his hips instead it was a 1.5 m drum
    // wider than it was long, and its two flat caps — sunlit, and the only warm thing on a blue-black
    // creature — filled his whole BACK: the one side of him the fight is about. Radius over the faulds'
    // 0.132·H so the band sits proud of the skirt, and 11 sides to match theirs.
    b.addCylinder(v3(0, 0.034 * H, 0), v3(0, 0.078 * H, 0), 0.140 * H, 0.140 * H, 11, STRAP);
    b.setMat(BRIGHT);
    b.addBox(v3(0, 0.056 * H, 0.138 * H), v3(0.036 * H, 0, 0), v3(0, 0.030 * H, 0), v3(0, 0, 0.010 * H), BRASS); // the buckle
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4229);
    b.setMat(.plain);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const y = 0.012 * H + @as(f32, @floatFromInt(i)) * 0.030 * H;
        const ox = rng.range(-0.005, 0.005) * H;
        b.addCube(v3(ox, y, -0.016 * H), v3(0.062 * H, 0.022 * H, 0.056 * H), if (@mod(i, 2) == 0) BONE else BONE_DK);
        b.addCube(v3(ox, y, -0.050 * H), v3(0.030 * H, 0.015 * H, 0.034 * H), BONE_DK);
    }
    b.setMat(PLATE);
    // A short mail skirt over the gap, hanging in strips rather than as one bib.
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

/// THE CUIRASS — the biggest single face on the creature. Near-black, fluted, and BROKEN: a raised medial
/// ridge, a rolled neck line, rivets down the sides, and one pauldron riding proud of each shoulder.
/// THE CUIRASS'S OWN BOX, named because the DOOR is measured against its front face and a hand-derived
/// `0.208/2 − 0.006` at the test site is a number that silently stops describing his chest the first time the
/// breastplate is re-authored. `addRoundBox` takes a FULL size (`addCube`'s rule), hence the halving.
const CUIRASS_C = v3(0, 0.016 * H, -0.006 * H);
const CUIRASS_SIZE = v3(0.318 * H, 0.176 * H, 0.208 * H);
/// …and where the front of him actually is, in the CHEST bone's own frame.
pub const CHEST_FRONT_Z = CUIRASS_C.z + CUIRASS_SIZE.z * 0.5;

fn cuirassMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4243);
    b.setMat(PLATE);
    b.addRoundBox(CUIRASS_C, CUIRASS_SIZE, 0.048 * H, 4, 12, IRON);
    b.addRoundBox(v3(0, -0.058 * H, 0.004 * H), v3(0.268 * H, 0.084 * H, 0.184 * H), 0.038 * H, 3, 11, IRON_DK); // the ribs into the waist
    // THE MEDIAL RIDGE, sunk most of the way in — a few percent of the mass's own radius (relief is subtle).
    b.addBox(v3(0, 0.020 * H, 0.104 * H), v3(0.022 * H, 0, 0), v3(0, 0.150 * H, 0), v3(0, 0, 0.012 * H), IRON_LT);
    // …and the flutes either side of it, shallower still and NOT evenly spaced.
    for ([_]f32{ -0.135, -0.082, 0.074, 0.140 }) |fx| {
        b.addBox(
            v3(fx * H * rng.range(0.94, 1.06), 0.010 * H, 0.096 * H),
            v3(0.008 * H, 0, 0),
            v3(0, rng.range(0.100, 0.140) * H, 0),
            v3(0, 0, 0.007 * H),
            IRON_DK,
        );
    }
    // THE PAULDRONS, on the chest rather than the arm so a stroke cannot swing them off the shoulder.
    for ([_]f32{ 1, -1 }) |side| {
        const big: f32 = if (side < 0) 1.10 else 1.0; // the sword side is bigger, and asymmetry is the point
        b.addRoundBox(
            v3(side * SHOULDER_HALF * H * 0.96, 0.052 * H, -0.008 * H),
            v3(0.104 * H * big, 0.084 * H * big, 0.144 * H * big),
            0.036 * H,
            3,
            11,
            IRON,
        );
    }
    // …and everything PROUD of the plate is where the metal is allowed to glint.
    b.setMat(BRIGHT);
    b.addCylinder(v3(0, 0.176 * H, -0.006 * H), v3(0, 0.190 * H, -0.006 * H), 0.106 * H, 0.094 * H, 11, IRON_LT); // the neck's rolled rim
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
        ); // the rolled crest along it
    }
    // …and the brass fittings go back to PLATE. Under `BRIGHT` a pair of warm studs at shoulder height read
    // as two lit eyes on the front of him — the one thing on this creature that is supposed to be a light is
    // the ember down the visor, and nothing else may compete with it.
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
        ); // rivets
    }
    return b.toMesh();
}

fn gorgetMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCylinder(v3(0, -0.006 * H, 0), v3(0, 0.052 * H, 0), 0.040 * H, 0.036 * H, 8, BONE_DK); // the vertebrae inside
    b.addCylinder(v3(0, 0.002 * H, -0.002 * H), v3(0, 0.048 * H, -0.002 * H), 0.070 * H, 0.062 * H, 11, IRON);
    b.setMat(BRIGHT);
    b.addCylinder(v3(0, 0.048 * H, -0.002 * H), v3(0, 0.058 * H, -0.002 * H), 0.066 * H, 0.058 * H, 11, IRON_LT);
    return b.toMesh();
}

/// THE GREAT HELM. A near-black shell with a rolled brow, one narrow slit, and a cold ember behind it — the
/// only part of the creature that reads at night or in its own shadow. The jaw of the skull shows below it.
fn helmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4271);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, 0.010 * H, 0.004 * H), v3(0.088 * H, 0.098 * H, 0.096 * H), 0.032 * H, 4, 11, IRON);
    b.addDome(v3(0, 0.066 * H, 0.004 * H), v3(0, 1, 0), 0.082 * H, 11, IRON_DK); // the skull of it
    // THE VISOR: the slit is a SOCKET-dark box sunk into the face, with the ember laid inside it.
    b.addBox(v3(0, 0.022 * H, 0.096 * H), v3(0.066 * H, 0, 0), v3(0, 0.011 * H, 0), v3(0, 0, 0.010 * H), SOCKET);
    b.addBox(v3(0, 0.022 * H, 0.090 * H), v3(0.050 * H, 0, 0), v3(0, 0.006 * H, 0), v3(0, 0, 0.006 * H), EMBER);
    // Breaths cut low on the face, uneven and none of them the same length.
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const y = -0.014 * H - @as(f32, @floatFromInt(i)) * 0.014 * H;
        const w = rng.range(0.020, 0.046) * H;
        b.addBox(v3(rng.range(-0.012, 0.012) * H, y, 0.092 * H), v3(w, 0, 0), v3(0, 0.004 * H, 0), v3(0, 0, 0.006 * H), SOCKET);
    }
    // The crest. NOTHING ENDS IN A POINT: it rises and stops in a blunt swelling.
    b.addBox(v3(0, 0.096 * H, -0.004 * H), v3(0.008 * H, 0, 0), v3(0, 0.036 * H, 0), v3(0, 0, 0.078 * H), IRON_DK);
    b.setMat(BRIGHT);
    b.addCapsule(v3(-0.084 * H, 0.048 * H, 0.056 * H), v3(0.084 * H, 0.048 * H, 0.056 * H), 0.016 * H, 0.013 * H, 8, IRON_LT); // the brow, rolled
    b.addCapsule(v3(0, 0.132 * H, -0.030 * H), v3(0, 0.140 * H, -0.058 * H), 0.014 * H, 0.017 * H, 8, RUST);
    b.setMat(PLATE);
    b.addBox(v3(0, -0.050 * H, 0.060 * H), v3(0.052 * H, 0, 0), v3(0, 0.018 * H, 0), v3(0, 0, 0.044 * H), BONE); // the jaw, showing
    b.addBlob(v3(-0.048 * H, -0.048 * H, 0.030 * H), v3(0.016 * H, 0.020 * H, 0.018 * H), 5, 9, BONE_LT);
    b.addBlob(v3(0.046 * H, -0.052 * H, 0.026 * H), v3(0.015 * H, 0.019 * H, 0.017 * H), 5, 9, BONE_DK); // and uneven either side
    return b.toMesh();
}

// EVERY LIMB IS A CLOSED PLATE WITH THE BONE ONLY SHOWING AT ITS JOINTS. The first pass left the shafts
// proud of a front-only plate, and old bone comes back off this sun at 237 of 255 — so a five-metre knight in
// black iron read as four pale posts with dark strips on them. What says "a corpse in a suit" is a HAND'S
// WIDTH of bone at each gap, not a bare limb.
fn thighMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const len = REST[HIPL].y - REST[KNEEL].y;
    b.setMat(PLATE);
    shaft(&b, &rng, v3(0, -0.02 * H, 0), v3(0, -len + 0.02 * H, 0), 0.026 * H);
    plate(&b, v3(side * 0.006 * H, -len * 0.46, 0.010 * H), v3(0.064 * H, len * 0.40, 0.052 * H), IRON);
    b.addRoundBox(v3(side * 0.012 * H, -len * 0.92, 0.012 * H), v3(0.100 * H, 0.056 * H, 0.098 * H), 0.028 * H, 3, 10, IRON_DK); // the poleyn over the knee
    b.setMat(BRIGHT);
    b.addBlob(v3(side * 0.054 * H, -len * 0.92, 0.044 * H), v3(0.026 * H, 0.026 * H, 0.020 * H), 5, 9, if (rng.float() < 0.4) RUST else IRON_LT);
    b.setMat(.leather);
    for ([_]f32{ 0.22, 0.68 }) |t| {
        b.addCylinder(v3(0, -len * t, 0), v3(0, -len * t - 0.010 * H, 0), 0.068 * H, 0.068 * H, 8, STRAP);
    }
    return b.toMesh();
}

fn shinMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const len = REST[KNEEL].y - REST[ANKL].y;
    b.setMat(PLATE);
    shaft(&b, &rng, v3(0, -0.014 * H, 0), v3(0, -len + 0.016 * H, 0), 0.020 * H);
    plate(&b, v3(0, -len * 0.50, 0.008 * H), v3(0.054 * H, len * 0.42, 0.044 * H), IRON);
    b.setMat(BRIGHT);
    b.addCylinder(v3(0, -len * 0.96, 0.006 * H), v3(0, -len, 0.006 * H), 0.052 * H, 0.046 * H, 9, IRON_LT);
    b.setMat(.leather);
    b.addCylinder(v3(0, -len * 0.40, 0), v3(0, -len * 0.40 - 0.009 * H, 0), 0.058 * H, 0.058 * H, 8, STRAP);
    return b.toMesh();
}

/// THE SABATON — the footprint `solePatches` is measured off. Its underside sits on the ankle plane.
fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4283);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, -0.020 * H, 0.056 * H), v3(0.108 * H, 0.038 * H, 0.216 * H), 0.020 * H, 3, 10, IRON);
    // Overlapping lames across the toes, each a hair narrower and NOT evenly spaced.
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const z = 0.086 * H + @as(f32, @floatFromInt(i)) * 0.032 * H * rng.range(0.9, 1.12);
        b.addBox(v3(0, -0.008 * H, z), v3(0.050 * H - @as(f32, @floatFromInt(i)) * 0.005 * H, 0, 0), v3(0, 0.014 * H, 0), v3(0, 0, 0.009 * H), if (i % 2 == 0) IRON_LT else IRON_DK);
    }
    b.addBlob(v3(side * 0.044 * H, -0.006 * H, -0.030 * H), v3(0.032 * H, 0.030 * H, 0.030 * H), 5, 10, IRON_DK); // the heel
    b.setMat(BRIGHT);
    b.addCapsule(v3(0, -0.014 * H, 0.164 * H), v3(0, -0.006 * H, 0.196 * H), 0.026 * H, 0.020 * H, 8, RUST); // a blunt toe cap
    return b.toMesh();
}

fn upperArmMesh(side: f32, big: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 4297 else 4327);
    const len = REST[SHL].y - REST[ELL].y;
    b.setMat(.plain);
    shaft(&b, &rng, v3(0, -0.014 * H, 0), v3(0, -len + 0.014 * H, 0), 0.018 * H * big);
    plate(&b, v3(0, -len * 0.48, 0.006 * H), v3(0.048 * H * big, len * 0.40, 0.042 * H * big), IRON);
    b.addRoundBox(v3(0, -len * 0.94, 0.008 * H), v3(0.072 * H * big, 0.046 * H, 0.070 * H), 0.020 * H, 3, 10, IRON_DK); // the couter
    return b.toMesh();
}

fn forearmMesh(side: f32, big: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 4337 else 4349);
    const len = REST[ELL].y - REST[WRL].y;
    b.setMat(.plain);
    shaft(&b, &rng, v3(0, -0.012 * H, 0), v3(0, -len + 0.012 * H, 0), 0.016 * H * big);
    // The vambrace, in two halves with a seam down the outside — one tube reads as a pipe.
    plate(&b, v3(0, -len * 0.50, 0.014 * H), v3(0.044 * H * big, len * 0.44, 0.030 * H * big), IRON);
    plate(&b, v3(0, -len * 0.50, -0.018 * H), v3(0.038 * H * big, len * 0.40, 0.024 * H * big), IRON_DK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -len * 0.30, 0), v3(0, -len * 0.30 - 0.008 * H, 0), 0.050 * H * big, 0.050 * H * big, 8, STRAP);
    return b.toMesh();
}

fn gauntletMesh(off: bool) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (off) 4357 else 4363);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, FIST_Y * 0.5, FIST_Z), v3(0.062 * H, 0.070 * H, 0.058 * H), 0.020 * H, 3, 10, IRON);
    b.setMat(BRIGHT);
    // Knuckle plates, uneven, blunt — no fingers ending in points.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const x = (-0.030 + @as(f32, @floatFromInt(i)) * 0.020) * H;
        const r = rng.range(0.011, 0.016) * H;
        b.addBlob(v3(x, FIST_Y - 0.010 * H, FIST_Z + 0.036 * H), v3(r, r, r * 1.2), 5, 9, if (i % 2 == 0) IRON_LT else IRON_DK);
    }
    b.addCylinder(v3(0, FIST_Y * 0.5 + 0.070 * H, FIST_Z), v3(0, FIST_Y * 0.5 + 0.082 * H, FIST_Z), 0.058 * H, 0.050 * H, 10, IRON_LT); // the cuff
    if (off) {
        b.setMat(.leather);
        b.addCylinder(v3(-0.056 * H, FIST_Y * 0.5, FIST_Z), v3(0.056 * H, FIST_Y * 0.5, FIST_Z), 0.020 * H, 0.020 * H, 7, STRAP); // the shield strap
    }
    return b.toMesh();
}

/// HIS SWORD. A broad, tired blade — authored in the RIGHT-WRIST frame about the fist, pointing UP off the
/// grip, so `wpnFit` turns it onto the arm. The hurt segment (`SW_SEG`) reads the same numbers.
fn swordMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4373);
    const fy = FIST_Y;
    const fz = FIST_Z;
    const guardY = fy + SW_GUARD;
    const tipY = guardY + SW_BLADE;

    b.setMat(.leather);
    b.addCylinder(v3(0, fy + 0.090 * H, fz), v3(0, fy - 0.150 * H, fz), 0.019 * H, 0.019 * H, 8, STRAP); // the long grip
    // …AND THE BLADE IS PLATE TOO. A glint is right on a sword and this one is three metres long: under
    // `BRIGHT` its flat came back as a white plank longer than the hero is tall. Only its EDGES glint.
    b.setMat(PLATE);
    b.addBlob(v3(0, fy - 0.166 * H, fz), v3(0.030 * H, 0.024 * H, 0.030 * H), 6, 10, IRON_LT); // the pommel
    for ([_]f32{ 1, -1 }) |side| {
        const armLen = 0.104 * H * (if (side > 0) @as(f32, 1.0) else 0.88); // uneven quillons
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
        ); // …turning down and blunting off
    }
    b.addCylinder(v3(0, guardY, fz), v3(0, guardY + 0.034 * H, fz), 0.020 * H, 0.016 * H, 8, IRON_DK);
    // The blade in three tapering runs. `addBox` is a parallelepiped, so a taper is boxes meeting at width.
    // Fractions of the BLADE's own length, so shortening it re-spaces the runs instead of leaving a stub
    // with a full-length fuller down it.
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
    // THE FULLER IS SUNK, not stood off — only its edge breaks the flat.
    b.addBox(v3(0, guardY + 0.42 * SW_BLADE, fz), v3(0.015 * H, 0, 0), v3(0, 0.32 * SW_BLADE, 0), v3(0, 0, 0.009 * H), IRON_DK);
    // …and the GROUND EDGES either side of it, which is the one part of a blade that should catch the sun.
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
        ); // notches out of the edge — nothing dead is unmarked
    }
    return b.toMesh();
}

// Authored FACE-ON: its face along +Z, the grip at the origin, the top at +SH_TOP and the foot at -SH_BOT.
// It is a RECTANGLE, not a kite — a kite is a horseman's shield and this thing is a wall you stand behind.

// SIZED BETWEEN TWO FAILURES, the feedback law's: under, it is a buckler on a giant; over, it HIDES THE
// CREATURE IT EXISTS TO DEFINE. The first pass ran 4.0 m tall by 2.4 m wide and every portrait came back as a
// blank door with nothing behind it. At 3.0 x 1.8 m it is still taller than the hero and wider than he is,
// against a body 5.1 m tall and 2.3 m across the shoulders — a wall you walk round, with a knight above it.
// …and it is GRIPPED HIGH, the way a pavise is, so it hangs from his fist rather than being balanced on it.
// MEASURED against the rig it has to cover: his shoulder is 4.28 m up, his knee 1.51 m, and the grip lands at
// the wrist's own 3.92 m. Authored symmetric about the grip the door's top edge came out at 5.58 m — over his
// own 5.11 m crown, so every portrait was a blank slab with the creature hidden behind it.
const SH_TOP = 0.091 * H; // → the top edge at ~4.4 m: his shoulder line, and clear of the helm
const SH_BOT = 0.540 * H; // → the foot of it at ~1.1 m: down onto the shin, and clear of the sabatons
/// HALF-WIDTH, AND IT IS SIZED OFF `SHOULDER_HALF` RATHER THAN CHOSEN (owner: it does not cover enough).
/// At 0.165·H it measured 1.75 m across a body 2.29 m over the pauldrons — a door narrower than the man
/// behind it, so his own shoulders stood out either side of it and the front was never actually shut. A
/// pavise covers what it is in front of: this is his shoulder span with a hand's breadth to spare.
/// Read by the bash's hurt test as well as by the mesh, so the blow widens with the picture.
pub const SH_HALF = SHOULDER_HALF * H * 1.07;
const SH_THICK = 0.030 * H;
const SH_ROWS = 7;
/// How far off his FIST the door rides, along his own front. It is CENTRE-GRIPPED behind a boss, not strapped
/// to the forearm, so it needs a hand's depth and no more: the fist sits behind the boss and the face is the
/// next thing along. At 0.108·H it stood 0.57 m off the hand and at 0.062·H 0.33 m — both a door carried at
/// arm's length rather than a man sheltering behind one (owner, twice). The arm coming back onto his chest
/// (`GUARD_*`) is the other and larger half of the same fix.
const SH_STANDOFF = 0.028 * H;

/// The two points on its leading FACE that the bash's swept hurt test runs between (`shieldSeg`).
/// **THEY SPAN THE WHOLE DOOR, because the whole door is what arrives.** At 0.78 of it the segment's bottom
/// measured 1.29 m off the ground against a hero whose chest is at 1.12 m and whose crown is 1.80 m — so three
/// metres of iron came at him and the hurt test clipped the top of his head (owner: the swings go right over
/// my head). The mesh reached his shins the whole time: the PICTURE was right and the mechanic disagreed with
/// it, which is the failure `stowAmt` was written for one layer up. A test now pins the height as well as the
/// reach, because outward reach was measured and this never was.
const SH_LOW = v3(0, -SH_BOT, SH_THICK);
const SH_HIGH = v3(0, SH_TOP, SH_THICK);

fn shieldMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4391);
    b.setMat(PLATE);
    // THE FACE, in horizontal bands rather than one slab: each its own height, so the door reads as a made
    // thing. A DISH, too — the middle stands proud of the rim toward whatever is coming.
    //
    // **THE BANDS ARE ONE SUBSTANCE.** Alternated between three tones band by band — which is what the first
    // pass did — they came out as a barber's pole across the biggest flat in the game (`AGENTS.md`: the same
    // dial, opposite result). The variation is a few points of VALUE inside one iron, which reads as hammered
    // plate; what separates one knight from the next is his seed, not his own shield's stripes.
    var i: usize = 0;
    while (i < SH_ROWS) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SH_ROWS;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SH_ROWS;
        const y0 = mathx.lerpF(SH_TOP, -SH_BOT, t0);
        const y1 = mathx.lerpF(SH_TOP, -SH_BOT, t1);
        const w = SH_HALF * (1.0 - 0.16 * std.math.pow(f32, mathx.maxF(0, (t0 + t1) * 0.5 - 0.5) * 2.0, 1.4)) * rng.range(0.985, 1.01);
        const dish = 0.030 * H * (1.0 - std.math.pow(f32, @abs((t0 + t1) - 0.90), 1.5));
        const v = rng.range(-5.0, 5.0);
        b.addBox(
            v3(0, (y0 + y1) * 0.5, dish),
            v3(w, 0, 0),
            v3(0, (y0 - y1) * 0.5 + 0.003 * H, 0), // bands overlap a hair, or the seams leak daylight
            v3(0, 0, SH_THICK * 0.5),
            shade(IRON, v),
        );
    }
    // The rim, hammered round the edge, with a length of it lost to the centuries. Still PLATE: these are two
    // metres long, and under `BRIGHT` the top binding came back as a bar of pure white across the door.
    for ([_]f32{ 1, -1 }) |side| {
        b.addCapsule(
            v3(side * SH_HALF, SH_TOP - 0.004 * H, 0.006 * H),
            v3(side * SH_HALF * 0.86, -SH_BOT + 0.010 * H, 0.006 * H),
            0.014 * H,
            0.012 * H,
            8,
            if (rng.float() < 0.4) RUST else IRON_LT,
        );
    }
    b.addCapsule(v3(-SH_HALF * 0.97, SH_TOP - 0.006 * H, 0.006 * H), v3(SH_HALF * 0.97, SH_TOP - 0.006 * H, 0.006 * H), 0.016 * H, 0.013 * H, 8, IRON_LT);
    b.addCapsule(v3(-SH_HALF * 0.80, -SH_BOT + 0.006 * H, 0.006 * H), v3(SH_HALF * 0.72, -SH_BOT + 0.006 * H, 0.006 * H), 0.013 * H, 0.011 * H, 8, RUST);
    // The reinforcing braces across it — and only the BOSS is small enough to be allowed a real glint.
    for ([_]f32{ 0.02, -0.34 }) |ty| {
        b.addBox(v3(0, ty * H, 0.024 * H), v3(SH_HALF * 0.94, 0, 0), v3(0, 0.020 * H, 0), v3(0, 0, 0.008 * H), IRON_DK);
    }
    b.setMat(BRIGHT);
    b.addDome(v3(0, 0.020 * H, 0.030 * H), v3(0, 0, 1), 0.062 * H, 11, IRON_LT);
    var r: i32 = 0;
    while (r < 12) : (r += 1) {
        b.addBlob(
            v3(rng.range(-0.85, 0.85) * SH_HALF, rng.range(-SH_BOT * 0.85, SH_TOP * 0.9), 0.030 * H),
            v3(0.010 * H, 0.010 * H, 0.008 * H),
            4,
            8,
            if (rng.float() < 0.4) RUST else IRON_LT,
        ); // rivets
    }
    b.setMat(.leather);
    b.addCylinder(v3(-0.060 * H, 0.020 * H, -0.014 * H), v3(0.060 * H, 0.020 * H, -0.014 * H), 0.014 * H, 0.014 * H, 7, STRAP);
    return b.toMesh();
}

/// THE DOOR IS SQUARE TO THE MAN, NOT TO HIS FOREARM (`hero.shieldFit`'s law and `warrior.shieldXf`'s):
/// POSITION off the fist, ORIENTATION off the rig's own body frame — which for this creature includes the
/// TOPPLE, or the shield would stand up on end while the body it belongs to lies on the ground.
fn shieldXf(k: *const Knight) rl.Matrix {
    const fs = k.rigScale();
    const stow = k.stowAmt();
    // THE GRIP IS AT THE WRIST AND THE STANDOFF IS ALONG HIS OWN FRONT — never along the forearm's local Z,
    // which the guard pose has pointing at the sky: taken from the wrist frame it carried the grip 0.67 m
    // ABOVE his own wrist and put the door's top edge over his crown. So the position is the fist and the
    // offset is rotated by the BODY, which is the same frame the face is squared to.
    const fist = rl.math.vector3Transform(v3(0, FIST_Y, FIST_Z), k.xf[WRL]);
    // …and the door is DRAWN BACK as it turns, or an edge-on shield still stands where his chest is.
    // …AND PULLED ONTO HIS CENTRE LINE. The grip is out on the end of an arm, and a door left hanging where
    // the hand is covers one leg — it has to cover the MAN. Derived off the shoulder half-width, so it stays
    // on the middle of him if the frame is ever rebuilt.
    const off = rl.math.vector3Transform(
        mathx.scaleV(v3(-SHOULDER_HALF * H * 0.95, 0, SH_STANDOFF * (1.0 - 0.85 * stow)), fs),
        k.bodyXf,
    );
    const hub = mathx.addV(fist, off);
    return mul3(
        scaleM(fs, fs, fs),
        mul3(ry(-SH_STOW_DEG * stow), mul(rx(-6.0), rz(3.0)), k.bodyXf),
        tr(hub.x, hub.y, hub.z),
    );
}
/// How far round its own grip the door turns when it is stowed — just past square, so nothing of the face is
/// left pointing at the hero.
const SH_STOW_DEG = 96.0;

test "HE ROLLS ONTO HIS FRONT AND STAYS THERE — the rise does not roll him back onto his back first" {
    // Owner: the rolling / getting up part is bad. It WAS: `rollAmt` unwound across the first 42% of the
    // rise, so he heaved onto his face and immediately rolled back onto his spine to stand up off it — the
    // roll bought nothing and the whole move read as a crate rocking twice. Measured on the ONE channel that
    // says where his body is, plus the helm, which is what the eye actually follows.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.debugFall();
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    var rollPeak: f32 = 0;
    var seam: f32 = 0; // the biggest one-frame jump of the helm anywhere in the move
    var humpTop: f32 = 0; // …and how far the body heaves up over its own side to cross it
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
        // THE ROLL IS NEVER UNDONE: once he is on his front he stays on it until he is standing.
        if (k.state == .rise) try std.testing.expectApproxEqAbs(@as(f32, 0), k.rollAmt(), 1e-6);
        if (k.state == .rise and k.toppleAmt() > 0.01) overshot = true;
        if (t > FALL_WIND_DUR) seam = mathx.maxF(seam, @sqrt((helm.x - prev.x) * (helm.x - prev.x) +
            (helm.y - prev.y) * (helm.y - prev.y) + (helm.z - prev.z) * (helm.z - prev.z)));
        prev = helm;
    }
    try std.testing.expect(rollPeak > 0.99); // he really does go all the way over…
    try std.testing.expect(humpTop > flat + 0.4); // …heaving up over his own side to do it…
    try std.testing.expect(overshot); // …and the rise carries PAST upright and settles back onto it.
    // **AND THE SWAP IS INVISIBLE.** `turnAbout` describes one pose two ways (`Ry(180)·Rx(θ)` is
    // `Rx(−θ)·Ry(180)`), so nothing may move on the frame it happens — a seam here is a body teleporting.
    std.debug.print("\n  roll/rise: flat helm {d:.2}, hump to {d:.2}, worst one-frame move {d:.3} m\n", .{ flat, humpTop, seam });
    try std.testing.expect(seam < 0.35);
    // …and he ends up on his feet, facing the man he landed on rather than away from him.
    try std.testing.expectEqual(State.idle, k.state);
    try std.testing.expect(@abs(mathx.wrapPi(k.facing - std.math.pi)) < 0.5);
}

test "A BODY ALREADY ON THE GROUND CANNOT BE FLINCHED UPRIGHT — the punish window survives being used" {
    // A stun state carries NO topple, so a heavy landing on a downed knight snapped five metres of armour
    // instantly upright: the reward for reading the fall was the reward ending the moment you took it.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .downed;
    k.t = DOWN_DUR * 0.4;
    k.easeFloored(1.0);
    k.pose();
    const before = k.vit.hp;
    const p = k.centerWorld();
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 30, .poise = 99, .stance = 60 } });
    try std.testing.expectEqual(State.downed, k.state); // still down…
    try std.testing.expect(k.vit.hp < before); // …and it still hurt him, which is the whole point
    try std.testing.expectEqual(@as(u32, 1), k.hits);
    // …but a killing blow is still a death, and the corpse crumples from where the body already LAY.
    k.hitLatch = false; // a second swing, not the same one twice (`foe.reached`'s one-hit latch)
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = HP_MAX, .poise = 1, .stance = 1 } });
    try std.testing.expectEqual(State.dead, k.state);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), k.deathFrom, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), k.toppleAmt(), 1e-6); // no snap upright on frame one…
    // …AND NOT ON ANY FRAME AFTER IT EITHER. Pinning only frame one is what let the first pass through: the
    // crumple started correctly at 1.0 and then lerped to −1, passing through ZERO — which is standing — so
    // the corpse rose to its feet in the middle of its own death and fell forward off them.
    var t: f32 = 0;
    var nearest: f32 = 1e9;
    while (t < DEATH_DUR) : (t += 1.0 / 60.0) {
        k.t = t;
        nearest = mathx.minF(nearest, @abs(k.toppleAmt()));
    }
    std.debug.print("\n  killed flat: the body never comes back closer than {d:.2} of upright\n", .{nearest});
    try std.testing.expect(nearest > 0.8);
    // …and a knight killed ON HIS FEET still goes over forward, which is the whole picture of his death.
    var up = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    up.debugKill();
    up.t = DEATH_DUR;
    try std.testing.expect(up.toppleAmt() < -0.8);
}

test "THE SWORD IS SHOULDERED, NOT COUCHED — a three-metre blade held out front is a lance" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3); // faces +Z, sword arm on his right (−X)
    k.setCarry(1.0);
    k.pose();
    const tip = k.weaponSeg()[1];
    const fist = rl.math.vector3Transform(v3(0, FIST_Y, FIST_Z), k.xf[WRR]);
    // MEASURED off the posed bone rather than argued from the angle: the point rides BEHIND his own shoulder
    // and ABOVE his own crown. At the warrior's 120 it sat 2.0 m out in FRONT of him at chest height.
    try std.testing.expect(tip.z < 0);
    try std.testing.expect(tip.y > k.topWorld().y);
    // **AND IT STAYS ON HIS SWORD SIDE** (owner: the sword holding anim is bad). `@abs(tip.x) < bodyR` is his
    // ground FOOTPRINT — 1.77 m — so it passed happily on a point 0.18 m over onto his SHIELD side, which is
    // what made a 2.9 m blade lie diagonally across his back with an end sticking out either flank. His sword
    // arm is −X, so the point may not cross the midline, and it may not stand outside his own shoulders.
    const half = SHOULDER_HALF * H * k.scale;
    try std.testing.expect(tip.x <= 0.05 * k.scale);
    try std.testing.expect(@abs(tip.x) < half);
    // …and the HAND is brought in to the shoulder line rather than held out at half an arm again.
    try std.testing.expect(@abs(fist.x) < half);
}

test "THE DOOR COVERS HIM SHOULDER TO SHIN AND LEAVES THE CREATURE VISIBLE" {
    // Both halves of the feedback law, MEASURED off the posed rig rather than eyeballed off a portrait: the
    // first pass ran the door's top edge to 5.58 m over a 5.11 m crown and every framing came back as a blank
    // slab. It has to cover the body it is there to defend, and it may not BE the creature.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.setCarry(1.0);
    k.pose();
    const hub = rl.math.vector3Transform(mathx.zero3, k.shXf);
    const low = hub.y - SH_BOT * k.scale;
    const high = hub.y + SH_TOP * k.scale;
    const crown = k.topWorld().y;
    const knee = k.xf[KNEEL].m13;
    const shoulder = k.xf[SHL].m13;
    try std.testing.expect(low <= knee + 0.20); // …down to the knee
    try std.testing.expect(high > shoulder * 0.95); // …up to the shoulder line
    try std.testing.expect(high < crown - 0.3); // …and the helm stands clear of it
    try std.testing.expect(low > 0.6); // …and it is not resting on the ground

    // **AND IT IS HELD AGAINST HIM** (owner: it has to keep the shield close to the body if it is going to
    // block all frontal). BRACKETED FROM BOTH SIDES and measured off the CHEST, not off `bodyR` — the old
    // assertion asked only that the hub stood past 0.8 of his ground FOOTPRINT, which is 1.4 m and is not a
    // fact about his chest at all: it PINNED the door at arm's length, and it passed with 2.15 m of daylight
    // behind it. Under, the face is inside his own cuirass; over, it is a wall he is walking behind.
    const chestZ = k.xf[CHEST].m14;
    const front = chestZ + CHEST_FRONT_Z * k.scale; // the cuirass's own face, off its own box
    const back = hub.z - SH_THICK * k.scale; // …and the door's back face, which is what closes on it
    std.debug.print("\n  door: cuirass face {d:.2}, door back face {d:.2} → {d:.2} m of daylight\n", .{ front, back, back - front });
    try std.testing.expect(back > front); // it is not worn inside his chest…
    // …and the gap is a FIST, not an arm. A centre-gripped door cannot come closer than his own folded fist,
    // which for a body this size is about two thirds of a metre; it was 1.6 m.
    try std.testing.expect(back < front + 0.25 * k.scale);
    // …and it is pulled onto his CENTRE LINE rather than left out where the hand is.
    try std.testing.expect(@abs(hub.x) < SH_HALF * k.scale * 0.35);
}

test "HE IS BIGGER THAN THE OGRE, and that is the one fact the creature is built on" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(k.topWorld().y > giant.topWorld().y);
    // …and by a real margin, not by a rounding: a boss the same height as a field enemy is not a boss.
    try std.testing.expect(k.topWorld().y > giant.topWorld().y * 1.15);
    // THE CRUSH STRIP IS HIS OWN LENGTH, so the ground the fall bills is the ground the body lands on.
    try std.testing.expect(crushLen(k.scale) >= k.topWorld().y * 0.85);
    try std.testing.expect(crushLen(k.scale) <= k.topWorld().y * 1.15);
}

test "THE DOOR COVERS HIS FRONT AND NOTHING ELSE — and the fall answers exactly the sector it cannot" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3); // faces +Z
    k.covered = true;
    const at = struct {
        fn it(deg: f32, r: f32) foe.Blade {
            const a = mathx.radians(deg);
            const p = v3(mathx.sinf(a) * r, 1.0, mathx.cosf(a) * r);
            return .{ .active = true, .a = p, .b = p };
        }
    }.it;
    try std.testing.expect(k.shielded(at(0, 4.0))); // dead ahead
    try std.testing.expect(k.shielded(at(TOWER_ARC - 3.0, 4.0)));
    try std.testing.expect(!k.shielded(at(TOWER_ARC + 3.0, 4.0))); // past the edge of the door
    try std.testing.expect(!k.shielded(at(180.0, 4.0))); // NOTHING ON HIS BACK
    // …and the door is genuinely wider than a man's boards, which is the whole of why you walk round it.
    try std.testing.expect(TOWER_ARC > combat.GUARD_ARC);
    // The FALL's sector lies strictly outside the door's, so the two never claim one bearing…
    try std.testing.expect(180.0 - FALL_SECTOR > TOWER_ARC);
    // …and the gap between them is the SAFE POCKET: his quarter, not his back.
    try std.testing.expect(180.0 - FALL_SECTOR - TOWER_ARC > 20.0);
    // A dropped guard is a dropped guard whatever the bearing.
    k.covered = false;
    try std.testing.expect(!k.shielded(at(0, 4.0)));
}

test "A BLOW ON THE DOOR TAKES NO POISE AND NO STANCE — the front cannot be staggered, only chipped" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .idle;
    k.covered = true;
    const before = k.vit.hp;
    // A heavy, square onto the front, from just outside his hurt sphere's own centre.
    const p = v3(0, 2.6, k.hurtRadius() * 0.5);
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 40, .poise = 90, .stance = 60 } });
    try std.testing.expectEqual(@as(u32, 1), k.blocks);
    try std.testing.expectEqual(State.idle, k.state); // not a flinch, not a stance break — he did not move
    try std.testing.expect(k.vit.hp < before); // …but chip got through, and chip can kill
    try std.testing.expect(k.vit.hp > before - 40.0 * 0.5);
    // …and the same blow ROUND THE BACK is the whole thing.
    var back = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    back.state = .idle;
    back.covered = true;
    const q = v3(0, 2.6, -k.hurtRadius() * 0.5);
    back.tryHit(.{ .active = true, .r = 0.2, .a = q, .b = q, .a0 = q, .b0 = q, .hit = .{ .dmg = 40, .poise = 90, .stance = 60 } });
    try std.testing.expectEqual(@as(u32, 0), back.blocks);
    try std.testing.expectEqual(@as(u32, 1), back.hits);
    try std.testing.expect(back.staggered());
}

test "THE FALL LANDS BEHIND HIM AND NOWHERE ELSE" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3); // faces +Z, so his back is -Z
    const reach = crushLen(k.scale);
    // Dead behind, inside his own length: crushed.
    k.heroHit = null;
    k.tryCrush(v3(0, 0, -reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit != null);
    // Dead AHEAD of him: the strip does not go that way.
    k.heroHit = null;
    k.tryCrush(v3(0, 0, reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
    // Behind but past his length.
    k.heroHit = null;
    k.tryCrush(v3(0, 0, -reach - 1.5), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
    // Behind but off to the SIDE of the strip — which is what makes rolling sideways the answer.
    k.heroHit = null;
    k.tryCrush(v3(FALL_HALF_W * k.scale + HERO_REACH + 1.2, 0, -reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
}

test "HE FALLS ON A FLANK AND TURNS ON EVERYTHING ELSE" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const ready = [_]bool{ true, true };
    const cold = [_]bool{ false, false };
    const near = crushLen(k.scale) * 0.7;
    // Dead behind him with the fall gathered: he falls.
    try std.testing.expectEqual(Choice.fall, classify(near, 180.0, k.scale, true, &ready).what);
    // …with it cooling, he TURNS — which is what shuts the flank, and it is not an attack.
    try std.testing.expectEqual(Choice.wait, classify(near, 180.0, k.scale, false, &ready).what);
    // Out in the pocket between the door and the strip: no fall, and nothing else reaches round there either.
    try std.testing.expectEqual(Choice.wait, classify(near, TOWER_ARC + 12.0, k.scale, true, &ready).what);
    // Squared up in reach: the quick move first, and the long one when it is spent.
    try std.testing.expectEqual(Choice.strike, classify(triggerR(BASH, k.scale) * 0.8, 0, k.scale, true, &ready).what);
    try std.testing.expectEqual(@as(usize, BASH_I), classify(triggerR(BASH, k.scale) * 0.8, 0, k.scale, true, &ready).mv);
    try std.testing.expectEqual(@as(usize, CLEAVE_I), classify(triggerR(BASH, k.scale) * 0.8, 0, k.scale, true, &[_]bool{ false, true }).mv);
    // At sword length only the cleave reaches at all.
    const mid = (triggerR(BASH, k.scale) + triggerR(CLEAVE, k.scale)) * 0.5;
    try std.testing.expectEqual(@as(usize, CLEAVE_I), classify(mid, 0, k.scale, true, &ready).mv);
    // In reach with nothing gathered he looms; out of reach he closes; out of his world he holds.
    try std.testing.expectEqual(Choice.wait, classify(triggerR(BASH, k.scale) * 0.8, 0, k.scale, false, &cold).what);
    try std.testing.expectEqual(Choice.approach, classify(triggerR(CLEAVE, k.scale) + 4.0, 0, k.scale, true, &ready).what);
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, 0, k.scale, true, &ready).what);
}

test "THE WINDOW IS AN INSTANT BEFORE THE HIT, on both strokes — and the FALL has none" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    for (MOVES, 0..) |a, mv| {
        const impact = a.strikeDur * a.impactK;
        // It is an INSTANT, not a slice of the tell: a 1.2 s haul may not be catchable for a fifth of it.
        try std.testing.expect(PARRY_LEAD < a.windDur * 0.4);
        const step = 1.0 / 600.0;
        var open: f32 = -1;
        var shut: f32 = -1;
        var elapsed: f32 = 0;
        k.atk = mv;
        k.windHold = 0;
        while (elapsed <= a.windDur + impact) : (elapsed += step) {
            if (elapsed > a.windDur) {
                k.state = if (mv == BASH_I) .bash else .cleave;
                k.t = elapsed - a.windDur;
            } else {
                k.state = if (mv == BASH_I) .bashwind else .cleavewind;
                k.t = elapsed;
            }
            if (k.parryable() != null) {
                if (open < 0) open = elapsed;
                shut = elapsed;
            }
        }
        try std.testing.expect(open > 0);
        // …and it SHUTS AT THE IMPACT FRAME by construction, so a caught blow is one that never landed.
        try std.testing.expectApproxEqAbs(a.windDur + impact, shut, 2.0 * step);
        try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);
    }
    // NOTHING ABOUT THE FALL IS PARRYABLE — its own tell, its topple, and the whole of the aftermath.
    for ([_]State{ .fallwind, .fall, .downed, .rollover, .rise, .idle, .approach, .recover, .stunlight, .stunheavy, .dead }) |s| {
        k.state = s;
        k.t = 0;
        try std.testing.expect(k.parryable() == null);
        k.t = 0.2;
        try std.testing.expect(k.parryable() == null);
    }
}

test "EACH STROKE'S DECLARED REACH IS WHAT THE KIT ACTUALLY ARRIVES AT" {
    // `reachOut` is the AI's trigger radius AND the parry window's reach, so it may never promise LESS than
    // the blow delivers (a stroke that reaches past its own window is unparryable at its own tip) and never
    // much more (a trigger radius the kit cannot cross is a committed second spent on a guaranteed miss).
    const dt = 1.0 / 600.0;
    for (MOVES, 0..) |a, mv| {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
        k.atk = mv;
        k.windHold = 0;
        k.state = if (mv == BASH_I) .bash else .cleave;
        k.t = 0;
        var reached: f32 = 0;
        while (k.t <= a.strikeDur) : (k.t += dt) {
            k.setStrike(foe.swingCurve(mathx.clampF(k.t / a.strikeDur, 0, 1)));
            k.pose();
            const seg = if (mv == BASH_I) k.shieldSeg() else k.weaponSeg();
            for (seg) |p| reached = mathx.maxF(reached, mathx.distXZ(k.pos, p));
        }
        const declared = a.reachOut * k.scale;
        try std.testing.expect(declared >= reached - 0.05);
        try std.testing.expect(declared <= reached + 0.65);
    }
}

test "EVERY STROKE COMES DOWN INTO THE HERO'S OWN HEIGHT BAND — a giant's kit swung at a giant's height MISSES" {
    // A five-metre creature authored entirely in its own units sweeps its kit through ITS chest, which is
    // 2.5 m over the head of the man it is swinging at (owner: the swings go right over my head). Outward
    // reach was measured and pinned; the HEIGHT never was, and it is the half that decides whether a blow can
    // land at all. Every live stroke must dip to somewhere a 1.8 m body actually occupies.
    const dt = 1.0 / 120.0;
    for (MOVES, 0..) |a, mv| {
        var k = Knight.spawn(mathx.ground(0, 0), 0, 1.0, 0.33);
        k.windHold = 0;
        k.state = if (mv == BASH_I) .bash else .cleave;
        k.t = 0;
        var lowest: f32 = 1e9;
        while (k.t <= a.strikeDur) : (k.t += dt) {
            k.setStrike(foe.swingCurve(mathx.clampF(k.t / a.strikeDur, 0, 1)));
            k.pose();
            const seg = if (mv == BASH_I) k.shieldSeg() else k.weaponSeg();
            for (seg) |p| lowest = mathx.minF(lowest, p.y - k.pos.y);
        }
        // NOT "below his crown" — that is a graze off the top of his head and it is what the bash was doing.
        // It has to arrive where a body IS, so: chest height on a standing hero.
        std.debug.print("\n  {s}: kit dips to {d:.2} m (hero crown {d:.2}, chest {d:.2})\n", .{
            if (mv == BASH_I) "bash " else "cleave",
            lowest,
            heromod.H,
            heromod.H * 0.62,
        });
        try std.testing.expect(lowest < heromod.H * 0.62);
    }
}

test "EVERY BONE GETS A MATRIX IN EVERY STATE, and the body really does go over and come back up" {
    var k = Knight.spawn(mathx.ground(3, -2), mathx.radians(40), 1.0, 0.41);
    const crown = k.topWorld().y - k.pos.y;
    // Drive the whole fall through the state machine with the hero parked dead behind him.
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
    // FLAT ON HIS BACK the helm is near the ground and the body is BEHIND him — not standing, not sunk.
    try std.testing.expect(lowest < crown * 0.35);
    try std.testing.expect(lowest > -0.6);
    // …and he is back on his feet at the end of it, with the fall on its cooldown.
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
    // …and the body is behind his feet, which is where the player has to stand to use the window.
    try std.testing.expect(k.centerWorld().z < -k.bodyR() * 0.5);
    // The door is DOWN the whole time he is off his feet: this window is not one you have to walk round.
    for ([_]State{ .fall, .downed, .rollover, .rise }) |s| {
        k.state = s;
        try std.testing.expect(!k.guardUp());
    }
    // …and the CLEAVE is the other way in, because both hands go on the grip.
    k.state = .cleave;
    try std.testing.expect(!k.guardUp());
    k.state = .bash;
    try std.testing.expect(k.guardUp());
}

test "THE DOOR IS SEEN TO LEAVE — the picture of the guard cannot disagree with the guard" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    // Square to his front for everything he does standing behind it, on every frame of it.
    for ([_]State{ .idle, .approach, .bashwind, .bash, .fallwind }) |s| {
        k.state = s;
        for ([_]f32{ 0, 0.2, 0.6 }) |t| {
            k.t = t;
            try std.testing.expect(k.guardUp());
            try std.testing.expectApproxEqAbs(@as(f32, 0), k.stowAmt(), 1e-6);
        }
    }
    // …and TURNED OFF IT for the whole of the cleave, which is the one thing that opens his front.
    k.state = .cleave;
    k.t = 0;
    try std.testing.expect(!k.guardUp());
    try std.testing.expectApproxEqAbs(@as(f32, 1), k.stowAmt(), 1e-6);
    // It is already most of the way round by the time the stroke starts — a door that turned ON the impact
    // frame would be a front that was never open.
    k.state = .cleavewind;
    k.t = MOVES[CLEAVE_I].windDur * 0.45;
    try std.testing.expect(!k.guardUp());
    try std.testing.expectApproxEqAbs(@as(f32, 1), k.stowAmt(), 1e-6);
    // A bash's recovery keeps it up (it never left his arm); a cleave's brings it back over the recovery.
    k.state = .recover;
    k.t = 0;
    k.blow = .bash;
    try std.testing.expect(k.guardUp() and k.stowAmt() == 0);
    k.blow = .cleave;
    try std.testing.expect(!k.guardUp());
    try std.testing.expect(k.stowAmt() > 0.9);
    k.t = MOVES[CLEAVE_I].recoverDur;
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.stowAmt(), 1e-6);
    // Off his feet the door goes down WITH him, so it is never stowed there — the topple is what moves it.
    for ([_]State{ .fall, .downed, .rollover, .rise }) |s| {
        k.state = s;
        k.t = 0.3;
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.stowAmt(), 1e-6);
    }
}

test "NO ATTACK COMES OUT OF NOWHERE, and the fall's tell is the longest thing he does" {
    for (MOVES) |a| try std.testing.expect(a.windDur >= foe.TELL_MIN);
    try std.testing.expect(FALL_WIND_DUR >= foe.TELL_MIN);
    // **AND IT IS LONGER THAN EVERY SWING HE HAS** (owner: it needs more tell). The old assertion asked only
    // that the whole countdown beat 0.65 of a wind, which 0.82 s satisfied while sitting well UNDER the
    // cleave's 1.18 s haul — so the one move with no parry and no block behind it was the one you got least
    // time to read. Its counter is the ROLL and the read, so the read has to be worth more than any of them.
    for (MOVES) |a| try std.testing.expect(FALL_WIND_DUR > a.windDur);
    // AND THE AFTERMATH IS THE REWARD: the longest opening in the game, and longer than any recovery he has.
    const opening = DOWN_DUR + ROLL_DUR + RISE_DUR;
    for (MOVES) |a| try std.testing.expect(opening > a.recoverDur * 2.0);
    try std.testing.expect(opening > combat.FOE_HEAVY_STUN_DUR);
    // …and he cannot spend it twice in a row: the cooldown outlasts getting up.
    try std.testing.expect(FALL_CD > opening);
}

test "HE IS OUT-TURNED, which is the only reason a flank exists at all" {
    // A hero walking a circle at his own closest approach must out-turn him, or there is no getting behind.
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const r = k.bodyR() + foe.HERO_R;
    const heroRate = heromod.WALK_SPEED / r; // rad/s the player can carry round him on foot
    try std.testing.expect(heroRate > TURN_RATE * 1.15);
    // …and a committed stroke lets go of the tracking, which is where the window actually opens.
    try std.testing.expect(SWING_TURN < TURN_RATE);
    try std.testing.expect(FALL_AIM < TURN_RATE);

    // **AND THE BASH MUST STILL LAND ON A MAN WHO IS WALKING**, which is the half nothing measured. A swing
    // that cannot reach a moving target is not a difficulty dial, it is a move that does not exist: he shed
    // 32 deg of bearing across a commit and started up to 50 deg out, so it missed every circling player.
    // Measured as the LATERAL miss at the impact frame against the kit's own half-width.
    // THE ANGLE THE DOOR ITSELF SUBTENDS at the range it arrives — the one honest measure of "aimed at him",
    // because a stroke is only ever as accurate as the thing on the end of it is wide.
    const kitHalf = std.math.asin(SH_HALF / BASH.reachOut);
    const commit = BASH.windDur + BASH.strikeDur * BASH.impactK;
    const drift = (heroRate - SWING_TURN) * commit; // rad of bearing the stroke loses while committed
    std.debug.print("\n  hero {d:.2} rad/s, bash commit {d:.2} s → drift {d:.0} deg; the door subtends {d:.0} deg\n", .{
        heroRate, commit, mathx.degrees(drift), mathx.degrees(kitHalf),
    });
    // ONE: the drift a commit sheds may not BY ITSELF carry the door off a man who was squared up. It was 32
    // deg against a 25 deg door, so a player who did nothing but walk was missed by geometry alone.
    try std.testing.expect(drift < kitHalf);
    // TWO: he may not commit at a bearing his own kit does not already cover. Anything wider is a swing thrown
    // at a place the door was never going to arrive, which is a second and a half spent on a guaranteed miss.
    try std.testing.expect(mathx.radians(SWING_BEARING) <= kitHalf);
    // …and the two together are what leaves the DODGE intact: squared up you are hit, and circling out through
    // the sector edge you are not. That is the fight, and neither half of it is an accident now.

    // THE CLEAVE IS NOT HELD TO THAT, AND THAT IS THE DESIGN. Its commit is 1.18 s and its kit is a blade's
    // edge, so a walking player leaves it — the slow overhead is the one you step out of, and the bash is the
    // punish for standing in front of him. Pinned so the pair cannot quietly become one move twice.
    try std.testing.expect(CLEAVE.windDur > BASH.windDur * 1.4);
}
