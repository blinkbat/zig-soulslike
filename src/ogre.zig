const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// A GIANT, ~2x the hero: hunched, misshapen, hefting a knotted club.

const HIDE = rgba(39, 34, 28, 255); // ashen grey-tan hide — earthen, darker than bone
const HIDE_DK = rgba(24, 20, 17, 255); // shadowed folds / warts — near-black
const HIDE_LT = rgba(56, 49, 40, 255); // caught-light ridges / knuckles
const BELLY = rgba(52, 46, 37, 255); // paler, scarred underside
const SCAR = rgba(74, 64, 50, 255); // old scar tissue / calloused patches
const EYE = rgba(242, 192, 96, 58); // the single eye — tired amber, SELF-LIT (low alpha = emissive)
const EYE_RIM = rgba(20, 16, 13, 255); // heavy wet socket rim
const PUPIL = rgba(8, 6, 5, 255);
const TUSK = rgba(140, 130, 106, 255); // pale bone tusks + nails, pop against the hide
const TUSK_DK = rgba(104, 96, 78, 255);
const RAG = rgba(38, 32, 26, 255); // a filthy loin-rag (a scrap of pathos, keeps it un-goofy)
const ROPE = rgba(52, 42, 29, 255); // plaited rope — belt + club lashings
const CLUB_WOOD = rgba(30, 21, 13, 255); // dark bog-oak haft
const CLUB_WOOD_LT = rgba(44, 32, 20, 255); // grain highlight
const CLUB_STONE = rgba(45, 43, 40, 255); // lashed-on stone lumps
const CLUB_IRON = rgba(50, 46, 42, 255); // old iron
const IRON_RUST = rgba(72, 46, 26, 255); // rust-bitten iron / old blood-stain bleed
const MAW = rgba(14, 8, 7, 255); // the dark of the mouth behind the teeth — so a gape reads as a
const TONGUE = rgba(58, 25, 23, 255); // MOUTH and not a hole punched in the head

const N = 24;
const ROOT = 0; // pelvis
const SPINE = 1; // lumbar
const CHEST = 2; // barrel ribcage
const NECK = 3;
const SKULL = 4;
const HIPL = 5;
const KNEEL = 6;
const ANKL = 7;
const HIPR = 8;
const KNEER = 9;
const ANKR = 10;
const SHL = 11; // shoulder L (the OFF arm)
const ELL = 12;
const WRL = 13;
const SHR = 14; // shoulder R (the CLUB arm)
const ELR = 15;
const WRR = 16;
const CLUB = 17; // the great club, parented to the right wrist
const JAW = 18; // the sagging tusked underbite
const TOEL = 19; // toe pad L — the foot ROLLS off the ground instead of slapping flat
const TOER = 20;
const HUMP = 21; // upper back / the dome between the shoulders (NECK's parent)
const CLAVL = 22; // shoulder girdle L (SHL's parent)
const CLAVR = 23;

const parent = [N]i32{ -1, ROOT, SPINE, HUMP, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CLAVL, SHL, ELL, CLAVR, SHR, ELR, WRR, SKULL, ANKL, ANKR, CHEST, CHEST, CHEST };

// Where this giant carries his weight, MEASURED off `footMesh`: the fat pad under each ankle, which `hero.legChain` levels every frame so the sole cannot rake through the ground.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.094 * H, .toe = 0.144 * H, .halfW = 0.082 * H, .drop = 0.039 * H },
    .{ .bone = ANKR, .heel = 0.094 * H, .toe = 0.144 * H, .halfW = 0.082 * H, .drop = 0.039 * H },
};

const H: f32 = heromod.H;
// Ogre proportions (fractions of H): LEGS keep the hero's segment lengths so the shared gait reads honestly; ARMS run long + heavy, the frame wide.
const SEG_THIGH = heromod.SEG_THIGH; // shared with the hero — legChain's geometry is measured off
const SEG_SHANK = heromod.SEG_SHANK; // these, so they must never drift from the source
// Owner's call: arms SHORTER and LEANER, hands BIGGER.
const SEG_UPARM = 0.194; // heavy arms, but no longer knuckle-draggers
const SEG_FOREARM = 0.153;

// COMPTIME, like the other two rigs': `spawn` runs it per instance and the editor re-homes every posted foe on every frame it is up.
const REST = restPositions();

fn restPositions() [N]rl.Vector3 {
    const hx = 0.135; // wide hip half-separation (a broad base)
    const sx = 0.235; // wide, slumped shoulders
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.645, 0);
    r[CHEST] = v3(0, 0.775, 0);
    r[NECK] = v3(0, 0.842, 0.026);
    r[SKULL] = v3(0, 0.925, 0.070); // MEASURED against the chest barrel's top, not eyeballed: the
    // skull's centre has to sit clear of it or the head reads as swallowed by the shoulders
    r[HIPL] = v3(hx, 0.530, 0);
    r[KNEEL] = v3(hx, 0.285, 0);
    r[ANKL] = v3(hx, 0.039, 0);
    r[HIPR] = v3(-hx, 0.530, 0);
    r[KNEER] = v3(-hx, 0.285, 0);
    r[ANKR] = v3(-hx, 0.039, 0);
    r[SHL] = v3(sx, 0.791, 0);
    r[ELL] = v3(sx, 0.556, 0);
    r[WRL] = v3(sx, 0.361, 0);
    r[SHR] = v3(-sx, 0.809, 0);
    r[ELR] = v3(-sx, 0.574, 0);
    r[WRR] = v3(-sx, 0.379, 0);
    r[CLUB] = v3(-sx, 0.379, 0); // zero offset from the wrist; club mesh authored in the wrist frame
    r[JAW] = v3(0, 0.905, 0.090); // = SKULL + (0, −0.020, +0.020); jawMesh is authored to that offset
    r[TOEL] = v3(hx, 0.026, 0.095);
    r[TOER] = v3(-hx, 0.026, 0.095);
    r[HUMP] = v3(0, 0.792, -0.020);
    r[CLAVL] = v3(0.075, 0.803, 0);
    r[CLAVR] = v3(-0.075, 0.812, 0); // the club side's yoke rides higher (the working shoulder)
    for (&r) |*p| p.* = v3(p.x * H, p.y * H, p.z * H);
    return r;
}

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;

fn stridePulse(x: f32, a: f32, b: f32) f32 {
    if (x <= a or x >= b) return 0;
    return mathx.sinf(std.math.pi * (x - a) / (b - a));
}

fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    heromod.setJoint(wx, &rest, i, @intCast(parent[i]), animRot);
}

// A hulking giant — ~2.2x the hero to the crown. It went 2.5 → 2.1 once (too big) and the owner has now
// asked for bigger again, so this is deliberately SHORT of the 2.5 that was rejected: judge it off
// `108_brood_scale`'s ogre framings before pushing it further.
pub const SCALE = 2.4;
const WALK_SPEED = heromod.WALK_SPEED * 0.72; // a slow, ground-eating lumber (long legs cover it)
const AGGRO_R = 18.0; // it sees you coming from far off (it's huge)
const SLAM_R = 2.3; // starts the overhead slam within this — kept INSIDE the crush strip's true end
const SWIPE_R = 4.4; // the side swipe's reach — longer than the slam's, it's a HORIZONTAL arc that
const TURN_RATE = 3.4; // rad/s (~195 deg/s) — still out-turned by the hero, but no longer a turret
const SWIPE_TURN = 5.4; // rad/s he PIVOTS while swiping — the swing is a turn, and it tracks into you
const BODY_R = 0.55; // ground footprint (pre-scale) — broad
const HURT_R = 0.72; // hurt-sphere radius the hero's blade tests against (pre-scale) — a big target
// Pelvis walk oscillation — the hero's amplitudes (heavier), scaled with the body at draw.
const A_BOB = 0.030 * H;
const A_SWAY = 0.014 * H;
const A_LUMBER = 6.5; // deg the trunk rolls toward the stance foot through each stride
const A_PROT = 6.0; // deg of pelvic TRANSVERSE rotation — the swagger (the hero walks on 3.5)
const TRUNK_NOD = 5.5; // deg the trunk flexes twice a stride as the mass settles onto each foot

const WINDUP_DUR = 1.20; // rear the club overhead — the unmistakable tell.
const SLAM_DUR = 0.22;
const SLAM_IMPACT_K = 0.85; // fraction into the slam the club meets the ground (impact frame)
// MEASURED off the posed club's arc, which first touches the earth at ~0.19 s of the 0.22 s crash
const RECOVER_DUR = 1.20; // hunched over the buried club, spent + wide open
const SLAM_CD = 1.3; // beat between slams

const SWIPE_WIND_DUR = 0.46; // the cock-back — still SHORT next to the slam's tell (about a third of
const SWIPE_DUR = 0.20;
const SWIPE_IMPACT_K = 0.42; // fraction into the sweep the club crosses his centre line
const SWIPE_REC_DUR = 0.52; // a brief overswung stagger — not the slam's wide-open collapse
const SWIPE_CD = 1.05; // its own cooldown, shorter than the slam's
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 6.0;

// "higher poise" — a long HP bar, and a stance meter that only breaks under sustained pressure) ─
const HP_MAX = 300.0;
const POISE_MAX = 30.0; // 3 fast hero-lights (poise 10) to flinch once; a lone light is shrugged off
const STANCE_MAX = 90.0; // keep the pressure on to reach the heavy stance-break
/// A QUARTER TON OF HIDE AND FAT: too much mass for any one element to get through quickly, and the
/// broadest resistances in the game — but it stands a giant in an open field, so lightning finds it.
/// See `frog.RESISTS` on why only fire is exercised yet.
const RESISTS = combat.resists(.{ .fire = 30, .cold = 30, .lightning = -15, .chaos = 20 });
pub const SLAM_HIT = combat.Hit{ .dmg = 36, .poise = 44, .stance = 20 }; // a crushing body-blow (heavy).
pub const SWIPE_HIT = combat.Hit{ .dmg = 23, .poise = 30, .stance = 11 }; // the swipe trades weight for
const DEATH_DUR = 1.7; // a slow, weighty topple — a giant falls hard (and sadly)
/// RUNES the one-eyed ogre is worth: fifteen toads.
pub const RUNES: u32 = 900;
const DISS_DUR = 1.1; // dissipation into grace-gold motes (ER-consistent with frog/archer)

const HERO_REACH = foe.HERO_REACH; // hero footprint added to the strip on both axes
const SLAM_LEN = 1.05; // crush strip length ahead of the seat (pre-scale).
const SLAM_HALF_W = 0.45; // crush strip HALF-width (pre-scale) — about the club head + shock
const SWIPE_INNER = 1.18; // pre-scale: nearer than this and the club passes over you.
const SWIPE_OUTER = 1.95;
// The sector is NOT centred on his facing: the club starts cocked behind his right shoulder and finishes past his left, so the swept bearings run ~−119..+22 (MEASURED off the posed bone, height 2.37 → 1.07 — head to hip on a hero).
const SWIPE_ARC_MID = -48.0; // deg (negative = his club side, his right)
const SWIPE_ARC = 144.0; // deg of total sweep — ±72 about SWIPE_ARC_MID

const HUNCH = 9.0; // base forward stoop — stooped + weary, but still standing TALL (imposing)
// HE HINGES AT THE WAIST (owner's law): the fraction of any body pitch the PELVIS may take.
const PELVIS_SHARE = 0.16;
// THE CARRY (owner's law): the club is HEFTED AT HIS SIDE, never dragged.
const CARRY_SH = 5.0; // club arm hangs plumb, a hair BACK — the head's weight pulls it behind
const CARRY_EL = -13.0; // a heavy arm keeps some natural flex — never a straight pole
const CARRY_TILT = 44.0; // the club raked back in the fist (deg off the forearm) — the hover
const WIND_TILT = 30.0; // cocked back off the shoulder at the top of the windup
const SLAM_TILT = -14.0; // whipped through AHEAD of the haft at impact (the head leads).
// REACH against DEPTH along one arc: rake it further ahead and the head lands further out but higher (measured, −30 put the crater 2.1 out and 0.66 in the air — a slam that missed the earth).
const OVER_SH = -158.0; // upper arm thrown up-and-back — the club COCKS diagonally over the
const WIND_EL = -78.0; // shoulder like a headsman's backswing, not a vertical telescope
const SLAM_SH = -56.0; // club crashed forward-and-down into the earth, FOLLOWING THROUGH past
const SLAM_EL = -6.0; // elbow driven near-straight through the blow
const OFF_SH = -14.0; // off arm rests low
const OFF_EL = -18.0;
const HEAD_DROOP = 8.0; // downcast, sad at rest (+ = looks down) — low, but the face still SHOWS
const HEAD_YAW_MAX = 55.0; // deg the neck cranes before the body has to come round with it
const HEAD_TRACK_RATE = 220.0; // deg/s — comfortably faster than the body's turn, so it LEADS
const HEAD_SCAN = 26.0; // deg of the slow, sad idle sweep when nothing is in range
const HEAD_LOOK_DOWN = 16.0; // extra downward pitch at arm's length: he has to look DOWN at you

const OFF_ARM_SWING = 26.0; // deg the free shoulder swings (the hero walks on 9 — a giant lumbers)
const OFF_ELBOW_SWING = 22.0; // deg the free elbow flexes through its forward swing
const CLUB_ARM_SWING = 9.0; // the loaded shoulder swings short — the club's mass damps it
const CLUB_ELBOW_SWING = 6.0;
const CLUB_LAG = 0.6; // rad the loaded arm trails the stride — heavy limbs arrive late
const CLUB_PEND = 7.0; // deg the club rocks in the fist, trailing the arm in its turn
const PEND_LAG = 1.0; // rad the club's own rock trails the arm's swing
const CLUB_ABD = 22.0; // carried: held clear of his stride, but AT his side — not splayed out like a
const WIND_ABD = 16.0; // cocked overhead, coming in over the centre
const SLAM_ABD = -14.0; // NEGATIVE = adducted ACROSS the body: the shoulder sits ~0.9 out to his
const OFF_ABD = 14.0; // the empty arm just hangs clear of the barrel
const ARM_ABD_SWING = 0.35; // fraction of a swing bled into abduction (arms sweep arcs, not planes)
const WRIST_FLOP = 0.30; // fraction of the swing the empty hand lags by — passive dead weight
const CLUB_HOLD = 0.6; // fraction of the arm swing the FIST pays back into the club's rake, so the

const JAW_REST = 5.0; // deg ajar at rest — a heavy underbite never quite closes
const JAW_BREATHE = 4.5; // deg it sags/lifts on the breath
const JAW_STALK = 7.0;
const JAW_ROAR = 36.0; // wide at the top of the windup — the bellow before the club falls
const JAW_GRIT = 6.0; // clamped almost shut as the blow lands (teeth set into the impact)
const JAW_PANT = 24.0; // hangs open, heaving, all through the spent recovery
const JAW_FLINCH = 26.0; // knocked open by a light hit
const JAW_DEATH = 32.0; // slack and wide as the body goes over
const JAW_JOSTLE = 5.0; // deg the slack jaw is jolted by each footfall / the club's ground-judder

const GIRDLE_HEAVE = 3.6; // deg the yoke lifts on each breath
const GIRDLE_SWING = 0.30; // fraction of an arm's swing the clavicle hitches back into
const GIRDLE_LAG = 0.85; // rad the hitch trails its arm — the yoke arrives after the limb
const GIRDLE_PROT = 0.40; // fraction of the pelvic counter-rotation the yoke protracts with
const GIRDLE_WIND = 15.0; // shrugged up as the club rears overhead
const GIRDLE_SPENT = -10.0; // slumped, wrung out over the buried club
const CLAV_DROOP = 6.0; // the club side rides permanently DRAGGED DOWN by the weight it carries
const CLAV_LOAD = 0.30;

const TOE_PUSH = 26.0; // deg of push-off plantarflexion, peaking through late stance
const TOE_LIFT = 15.0; // deg the toes hook up through the swing (ground clearance)
const TOE_GRIP = 22.0; // deg they claw into the dirt while bracing a slam
const TOE_CURL = 24.0; // deg they curl under as he collapses

const HIP_ADDUCT = heromod.HIP_ADDUCT;
const FOOT_TOEOUT = heromod.FOOT_TOEOUT;
const IDLE_KNEE = heromod.IDLE_KNEE;
const IDLE_RATE = 1.5; // rad/s of the slow weight-shift cycle (~4.2 s period — heavy, unhurried)
const BREATHE_RATE = 1.05; // rad/s of the breathing bob
const A_BREATHE = 0.012 * H; // idle breathing rise/fall of the pelvis
const A_IDLE_SWAY = 0.020 * H; // idle lateral weight-sway (rocks foot to foot)
const IDLE_ROLL = 3.2; // deg the torso rolls toward the weighted foot
const STANCE_WIDEN = 3.5; // deg the feet plant wider when bracing for a slam
// THE LEGS STAND PLANTED (owner's law).
const BRACE_HIP = 12.0; // deg of hip flexion at full brace
const BRACE_KNEE = 24.0; // deg of knee flexion at full brace
const BRACE_SINK = 0.011 * H;

const FX_MAX = 56;
const DUST = foe.DUST; // kicked-up dust — the SHARED one (see foe.zig: it was two copies)
const BLOOD = rgba(84, 20, 16, 235); // dark ichor spray on a landed blow — his OWN (the toad's is
const MOTE = foe.MOTE; // death dissipation — the shared grace-gold every corpse goes out in

// The SHARED particle shape + integrator + draw (foe.zig); only the bursts below are the ogre's.
const Particle = foe.Particle;

const State = enum { idle, approach, windup, slam, swipewind, swipe, recover, stunlight, stunheavy, dead };

const Choice = enum { slam, swipe, approach, wait, idle };
const SWIPE_BEARING = 32.0; // deg off his facing past which the hero counts as "not in front of me"
fn classify(dist: f32, bearingDeg: f32, slamReady: bool, swipeReady: bool) Choice {
    if (dist > AGGRO_R) return .idle; // hasn't noticed / has disengaged
    const offFront = @abs(bearingDeg) > SWIPE_BEARING;
    if (dist <= SWIPE_R and swipeReady and (offFront or !slamReady)) return .swipe;
    if (dist <= SLAM_R) return if (slamReady) .slam else .wait; // squared up in reach: crush it
    return .approach; // close the gap
}

// The shared ogre meshes + material (built once, like the toad's / archer's).
pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("ogre material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, xf: *const [N]rl.Matrix) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, xf[i]);
    }
};

pub const Ogre = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    /// ITS TETHER to `home`, and how hard the player has provoked it (see foe.Leash).
    leash: foe.Leash = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    slamCd: f32 = 0,
    swipeCd: f32 = 0,
    elapsed: f32 = 0,
    slammed: bool = false, // one crush per slam/swipe (the impact burst + hero hit are latched)
    swiped: bool = false, // the recovery being served belongs to a SWIPE (short) not a slam (long)
    /// `.approach` is trudging back HOME rather than chasing.
    homing: bool = false,

    // posture channels (degrees) resolved each frame by the state, read by pose().
    clubShoulder: f32 = CARRY_SH,
    clubElbow: f32 = CARRY_EL,
    offShoulder: f32 = OFF_SH,
    offElbow: f32 = OFF_EL,
    bodyLean: f32 = HUNCH,
    headPitch: f32 = HEAD_DROOP,
    twist: f32 = 0, // torso wind: shoulders coil BACK on the windup, whip THROUGH the slam
    clubTilt: f32 = CARRY_TILT, // club-in-fist rake: raked back for the carry, whips on the blow
    clubAbd: f32 = CLUB_ABD, // how far the club arm is held OUT (see CLUB_ABD)
    clubSweep: f32 = 0, // deg the club arm is swung HORIZONTALLY across his front (+ = forward).
    // The waist twist alone only rotates the arc, it can't carry an arm that is held out to the right across his centre line — this is the shoulder's own horizontal swing, and without it the "side swipe" only ever scythes his right flank (measured: −104..−23 of bearing).
    jawOpen: f32 = JAW_REST, // deg the mouth hangs open — breath, the roar, the grit, the loll
    girdle: f32 = 0, // deg the shoulder yoke is shrugged up (both clavicles, club side damped)
    legBrace: f32 = 0, // 0 = loose stance, 1 = feet planted + knees loaded (bracing a slam)
    jolt: f32 = 0, // footfall CATCH: spikes to 1 as a foot plants, decays fast — the mass landing
    judder: f32 = 0, // the club's ground-bounce after the slam impact (decaying oscillation)
    headYaw: f32 = 0, // where the eye is pointed (deg): your bearing when you're in range, a slow scan when not
    headLook: f32 = 0, // extra DOWNWARD pitch (deg) as you close — the height difference, read off his neck

    // shared humanoid GAIT STATE (hero.advanceGait drives these; hero.legChain animates the legs)
    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0, // for footfall dust on the stride half-cycles

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null, // this frame's blow ON THE HERO (the slam connects), read by game.zig
    heroLatch: bool = false, // one hero-hit per slam
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    // telegraph FX
    fx: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Ogre {
        var o = Ogre{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        o.rest = REST;
        o.fxRng = foe.fxStream(seed, 88883.0, 7);
        o.pose();
        return o;
    }

    // …and all measured from `pos.y`, THE GROUND UNDER HIM.
    pub fn centerWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.60 * H * self.scale, self.pos.z); // chest-ish mass centre
    }
    pub fn hurtRadius(self: *const Ogre) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ogre) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.62 * H * self.scale, self.pos.z);
    }
    pub fn topWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 1.02 * H * self.scale, self.pos.z);
    }
    // The head, roughly — for framing the face close-up (the single eye) in --shot.
    pub fn headWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.86 * H * self.scale, self.pos.z);
    }
    // The club's business end in world space, straight off the posed bone.
    pub fn clubLowWorld(self: *const Ogre) rl.Vector3 {
        return rl.math.vector3Transform(CLUB_LOW, self.xf[CLUB]);
    }
    pub fn alive(self: *const Ogre) bool {
        return !self.gone;
    }
    pub fn staggered(self: *const Ogre) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn dying(self: *const Ogre) bool {
        return self.state == .dead;
    }
    pub fn flashFrac(self: *const Ogre) f32 {
        return foe.flashFrac(self.flash);
    }
    // Grounded always (no hops) — collision keeps it out of the hero/world.
    pub fn airborne(self: *const Ogre) bool {
        _ = self;
        return false;
    }

    fn fdir(self: *const Ogre) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Ogre, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt); // shared — see foe.zig
    }

    // none / corpse).
    pub fn update(self: *Ogre, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            self.updateFx(dt);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.vit.tick(dt);
        self.elapsed += dt;
        self.slamCd = mathx.maxF(0, self.slamCd - dt);
        self.swipeCd = mathx.maxF(0, self.swipeCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.leash.tick(dt, mathx.distXZ(self.pos, self.home));
        self.t += dt;
        self.updateFx(dt);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;

        // Hit shove — a jolt off a landed blow (a giant barely budges, so it decays fast).
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.sensedDist(&self.leash, mathx.distXZ(self.pos, hero), AGGRO_R);
        const bearing = self.bearingTo(hero);
        self.trackHead(hero, d, dt); // the eye leads the body — every state, not just the idle
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                if (self.t >= 0.2) self.decide(d, bearing);
            },
            .approach => {
                // Chasing → face/move toward the HERO; disengaged (returning) → toward HOME.
                const tgt = if (self.homing) self.home else hero;
                self.faceToward(tgt, dt);
                const f = self.fdir();
                const moved = WALK_SPEED * dt;
                mathx.stepXZ(&self.pos, f, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(f); // travels along facing → forward gait
                self.setCarry(dt);
                if (self.homing) {
                    // Re-aggro if the hero wanders back into range; else stop once home.
                    if (d <= AGGRO_R) {
                        self.homing = false;
                        self.decide(d, bearing);
                    } else if (mathx.distXZ(self.pos, self.home) <= 2.0) self.enterIdle();
                } else if (d <= SWIPE_R or d > AGGRO_R) self.decide(d, bearing);
            },
            .windup => {
                self.faceToward(hero, dt * 0.4); // a little tracking while rearing (committed tell)
                const k = mathx.smoothstep(0, WINDUP_DUR * 0.82, self.t);
                self.setWindup(k);
                self.emitStrain(dt, k); // gravel trickles as it plants + loads
                if (self.t >= WINDUP_DUR) self.enter(.slam);
            },
            .slam => {
                const k = mathx.smoothstep(0, SLAM_DUR, self.t);
                self.setSlam(k);
                if (self.t >= SLAM_DUR * SLAM_IMPACT_K) {
                    self.tryImpact(hero, SLAM_HIT); // the club meets the earth
                    if (!self.slammed) {
                        self.slammed = true;
                        self.judder = 1.0; // the club BOUNCES off the earth (rings through recover)
                        self.dustBurst(self.impactWorld(), 36, 3.8, 0.38);
                        sfx.world(.ogre_slam, self.impactWorld()); // the crater, at the crater
                    }
                }
                if (self.t >= SLAM_DUR) {
                    self.slamCd = SLAM_CD;
                    self.enter(.recover);
                }
            },
            .swipewind => {
                self.faceToward(hero, dt * 1.4);
                self.setSwipeWind(mathx.smoothstep(0, SWIPE_WIND_DUR * 0.9, self.t));
                if (self.t >= SWIPE_WIND_DUR) self.enter(.swipe);
            },
            .swipe => {
                foe.faceToward(self.pos, &self.facing, hero, SWIPE_TURN, dt);
                const k = mathx.smoothstep(0, SWIPE_DUR, self.t);
                self.setSwipe(k);
                if (self.t >= SWIPE_DUR * SWIPE_IMPACT_K) {
                    self.trySwipe(hero, SWIPE_HIT); // the club scythes through the front SECTOR
                    if (!self.slammed) {
                        self.slammed = true;
                        // No crater — a swipe never touches the earth.
                        const low = self.clubLowWorld();
                        self.dustBurst(v3(low.x, self.pos.y + 0.05, low.z), 12, 2.2, 0.20);
                    }
                }
                if (self.t >= SWIPE_DUR) {
                    self.swipeCd = SWIPE_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                const dur: f32 = if (self.swiped) SWIPE_REC_DUR else RECOVER_DUR;
                self.setRecover(mathx.clampF(self.t / dur, 0, 1));
                if (self.t >= dur) self.enterIdle();
            },
            .stunlight => {
                self.easeChannelsNeutral(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle();
            },
            .stunheavy => {
                self.easeChannelsNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle();
            },
            .dead => {
                self.easeChannelsNeutral(dt); // arms/carry settle as the body goes over
                if (self.t >= DEATH_DUR) {
                    self.fade = mathx.smoothstep(DEATH_DUR, DEATH_DUR + DISS_DUR, self.t);
                    self.emitDissolve(dt);
                    if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
                }
            },
        }
        self.jolt = mathx.maxF(0, self.jolt - dt * 7.0); // the footfall catch releases fast
        self.judder = mathx.maxF(0, self.judder - dt * 3.2); // the club-bounce rings ~0.3 s

        // Drive the SHARED humanoid gait.
        const gaitSpeed: f32 = if (movedDist > 0) WALK_SPEED else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.footfalls(); // heavy dust puffs + the pelvis CATCH as each foot plants
        self.pose();
        self.tryHit(blade); // hero's blade AFTER the state machine (like the toad); a kill here
        // flags justDied for this frame's kill beat, cleared at the top of the next update.
        return self.heroHit;
    }

    fn enter(self: *Ogre, s: State) void {
        self.state = s;
        self.t = 0;
        if (s == .slam or s == .swipe) {
            self.slammed = false;
            self.heroLatch = false; // a fresh blow gets one chance to land on the hero
            self.swiped = s == .swipe;
        }
        if (s == .windup) sfx.world(.ogre_roar, self.pos);
        if (s == .swipewind) sfx.world(.ogre_swipe, self.pos);
    }
    fn enterIdle(self: *Ogre) void {
        self.state = .idle;
        self.t = 0;
        self.homing = false;
    }
    fn enterStun(self: *Ogre, s: State) void {
        self.state = s; // the interrupt drops any in-progress slam (nothing lands)
        self.t = 0;
        self.slammed = false;
        self.homing = false;
    }
    fn enterDeath(self: *Ogre) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
        self.homing = false;
    }

    // The hero's bearing off his facing, in degrees (0 = dead ahead, ±180 = behind) — what decides whether he can simply drop the club on you or has to SWEEP round to reach you.
    fn bearingTo(self: *const Ogre, hero: rl.Vector3) f32 {
        const d = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(d) < 1e-3) return 0;
        return mathx.degrees(mathx.wrapPi(mathx.headingXZ(d) - self.facing));
    }

    // Pick the next action from range + bearing + cooldowns.
    fn decide(self: *Ogre, dist: f32, bearingDeg: f32) void {
        switch (classify(dist, bearingDeg, self.slamCd <= 0, self.swipeCd <= 0)) {
            .slam => self.enter(.windup),
            .swipe => self.enter(.swipewind),
            .approach => {
                self.homing = false; // chasing the hero
                self.enter(.approach);
            },
            .wait => self.enterIdle(),
            .idle => {
                if (mathx.distXZ(self.pos, self.home) > 3.0) {
                    self.homing = true; // wandered — trudge back toward HOME (approach handles it)
                    self.enter(.approach);
                } else self.enterIdle();
            },
        }
    }

    pub fn tryHit(self: *Ogre, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.leash.noteCombat();
        if (blade.pierce) {
            self.leash.provoke();
            self.facing = mathx.headingXZ(mathx.scaleV(s.dir, -1));
        }
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        self.bloodBurst(s.contact, s.dir, if (heavyBlow) 16 else 10, if (heavyBlow) 2.8 else 2.0);
        // A giant barely gives — a much smaller shove than the toad's, so hits read as glancing off bulk.
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 0.7 else 0.4);
        sfx.world(.ogre_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.bloodBurst(s.contact, s.dir, 14, 2.4);
                sfx.world(.ogre_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {}, // shrugged off (its high poise) — the slam windup rolls on
        }
    }

    // The slam CRUSH: the club's ground footprint — a STRIP down the facing line.
    fn tryImpact(self: *Ogre, hero: rl.Vector3, h: combat.Hit) void {
        if (self.heroLatch) return;
        const to = v3(hero.x - self.pos.x, 0, hero.z - self.pos.z);
        const fwd = self.fdir();
        const axial = to.x * fwd.x + to.z * fwd.z;
        const lateral = @abs(to.x * fwd.z - to.z * fwd.x);
        if (axial < -0.2 or axial > SLAM_LEN * self.scale + HERO_REACH) return;
        if (lateral > SLAM_HALF_W * self.scale + HERO_REACH) return;
        self.heroHit = h;
        self.heroLatch = true;
        self.leash.noteCombat(); // a blow landed is a fight in progress — the tether waits
    }

    fn trySwipe(self: *Ogre, hero: rl.Vector3, h: combat.Hit) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d < SWIPE_INNER * self.scale - HERO_REACH or d > SWIPE_OUTER * self.scale + HERO_REACH) return;
        const slack = mathx.degrees(std.math.atan2(HERO_REACH, mathx.maxF(0.5, d)));
        // WRAPPED.
        if (@abs(mathx.wrapDeg(self.bearingTo(hero) - SWIPE_ARC_MID)) > SWIPE_ARC * 0.5 + slack) return;
        self.heroHit = h;
        self.heroLatch = true;
        self.leash.noteCombat(); // a blow landed is a fight in progress — the tether waits
    }

    // Debug hooks for the --shot harness (force a pose in isolation).
    pub fn debugSlam(self: *Ogre) void {
        self.enter(.windup);
    }
    pub fn debugSwipe(self: *Ogre) void {
        self.enter(.swipewind);
    }
    pub fn debugStagger(self: *Ogre, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Ogre) void {
        self.enterDeath();
    }

    // The head aims itself, independently of the body — see the HEAD_YAW_MAX block.
    fn trackHead(self: *Ogre, hero: rl.Vector3, d: f32, dt: f32) void {
        if (self.staggered()) { // a lolling head is the whole read of a stagger — don't fight it
            self.headYaw = mathx.approach(self.headYaw, 0, dt * 120.0);
            self.headLook = mathx.approach(self.headLook, 0, dt * 60.0);
            return;
        }
        if (d > AGGRO_R) {
            self.headYaw = mathx.approach(self.headYaw, HEAD_SCAN * mathx.sinf(self.elapsed * 0.33 + self.seed * 7.0), dt * 30.0);
            self.headLook = mathx.approach(self.headLook, 0, dt * 30.0);
            return;
        }
        const bearing = mathx.degrees(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(self.pos, hero)) - self.facing));
        self.headYaw = mathx.approach(self.headYaw, mathx.clampF(bearing, -HEAD_YAW_MAX, HEAD_YAW_MAX), dt * HEAD_TRACK_RATE);
        // Full look-down inside his own reach, easing off to level as you back away down the avenue.
        const near = 1.0 - mathx.smoothstep(SLAM_R, AGGRO_R * 0.6, d);
        self.headLook = mathx.approach(self.headLook, HEAD_LOOK_DOWN * near, dt * 40.0);
    }

    fn setCarry(self: *Ogre, dt: f32) void {
        const e = dt * 6.0;
        const breathe = mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28);
        const rock = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28); // the weight-shift phase
        const sigh = mathx.smoothstep(0.80, 1.0, mathx.sinf(self.elapsed * 0.42 + self.seed * 11.0)); // a slow swell every ~15 s
        const stalk = self.moving; // 0 idle → 1 mid-approach
        self.clubShoulder = mathx.approach(self.clubShoulder, CARRY_SH + 3.0 * rock + 2.0 * sigh, e); // the heavy club swings
        self.clubElbow = mathx.approach(self.clubElbow, CARRY_EL + 2.5 * breathe, e);
        self.offShoulder = mathx.approach(self.offShoulder, OFF_SH - 2.5 * rock, e);
        self.offElbow = mathx.approach(self.offElbow, OFF_EL, e);
        self.bodyLean = mathx.approach(self.bodyLean, HUNCH + 1.5 * breathe + 4.0 * sigh + 4.0 * stalk, e);
        self.headPitch = mathx.approach(self.headPitch, HEAD_DROOP + 2.0 * breathe + 2.5 * rock + 5.0 * sigh - 12.0 * stalk, e);
        self.twist = mathx.approach(self.twist, 0, e * 8.0);
        self.clubTilt = mathx.approach(self.clubTilt, CARRY_TILT - (self.bodyLean - HUNCH) + 3.0 * rock, e * 8.0);
        self.clubAbd = mathx.approach(self.clubAbd, CLUB_ABD + 2.0 * breathe, e);
        self.clubSweep = mathx.approach(self.clubSweep, 0, e);
        self.legBrace = mathx.approach(self.legBrace, 0, e);
        self.jawOpen = mathx.approach(self.jawOpen, JAW_REST + JAW_BREATHE * breathe + 6.0 * sigh + JAW_STALK * stalk, e * 0.8);
        self.girdle = mathx.approach(self.girdle, GIRDLE_HEAVE * mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28 - 0.7) - 2.0 * sigh, e);
    }
    fn easeChannelsNeutral(self: *Ogre, dt: f32) void {
        const e = dt * 4.0;
        self.clubShoulder = mathx.approach(self.clubShoulder, CARRY_SH, e);
        self.clubElbow = mathx.approach(self.clubElbow, CARRY_EL, e);
        self.offShoulder = mathx.approach(self.offShoulder, OFF_SH, e);
        self.offElbow = mathx.approach(self.offElbow, OFF_EL, e);
        self.bodyLean = mathx.approach(self.bodyLean, HUNCH, e);
        self.headPitch = mathx.approach(self.headPitch, HEAD_DROOP, e);
        self.twist = mathx.approach(self.twist, 0, e * 2.0);
        self.clubTilt = mathx.approach(self.clubTilt, CARRY_TILT, e * 2.0);
        self.clubAbd = mathx.approach(self.clubAbd, CLUB_ABD, e);
        self.clubSweep = mathx.approach(self.clubSweep, 0, e);
        self.legBrace = mathx.approach(self.legBrace, 0, e);
        self.jawOpen = mathx.approach(self.jawOpen, JAW_REST, e * 0.6); // the mouth is the LAST thing
        self.girdle = mathx.approach(self.girdle, 0, e); // to come back under him (poseUpper holds it slack)
    }
    fn setWindup(self: *Ogre, k: f32) void {
        const kBody = mathx.smoothstep(0, 0.7, k);
        const kArm = k * @sqrt(k); // trails the body, arrives late
        const shiver = mathx.sinf(self.t * 36.0) * 1.8 * mathx.smoothstep(0.75, 1.0, k);
        self.clubShoulder = lerpF(CARRY_SH, OVER_SH, kArm) + shiver;
        self.clubElbow = lerpF(CARRY_EL, WIND_EL, kArm);
        self.offShoulder = lerpF(OFF_SH, -74.0, kBody); // off arm flings out for balance
        self.offElbow = lerpF(OFF_EL, -44.0, kBody);
        self.bodyLean = lerpF(HUNCH, -24.0, kBody); // arch back
        self.headPitch = lerpF(HEAD_DROOP, -20.0, kBody); // the eye lifts to fix on YOU
        self.twist = lerpF(0, -26.0, k); // shoulders wind over the back hip
        self.clubTilt = lerpF(CARRY_TILT, WIND_TILT, kArm) + shiver * 0.6; // the head hangs back off the cock
        self.clubAbd = lerpF(CLUB_ABD, WIND_ABD, kArm); // the arm gathers IN as it rears
        self.clubSweep = lerpF(self.clubSweep, 0, kArm); // the overhead is a SAGITTAL blow — no sweep
        self.legBrace = lerpF(0, 0.55, kBody); // set the feet + sink into the load
        self.jawOpen = lerpF(JAW_REST, JAW_ROAR, mathx.smoothstep(0, 0.45, k)) + shiver * 0.8;
        self.girdle = lerpF(0, GIRDLE_WIND, kArm) + shiver * 0.5;
    }
    fn setSlam(self: *Ogre, k: f32) void {
        const kArm = 1.0 - (1.0 - k) * (1.0 - k); // fast out — the club leads
        self.clubShoulder = lerpF(OVER_SH, SLAM_SH + 6.0, kArm); // overshoots past the seat…
        self.clubElbow = lerpF(WIND_EL, SLAM_EL, kArm);
        self.offShoulder = lerpF(-74.0, 8.0, kArm);
        self.offElbow = lerpF(-44.0, -22.0, kArm);
        // …the trunk drives through behind it, and it drives DEEP: with the legs planted and the club shortened, the fold at the waist is the only thing that can still carry the head to the earth (arm straight down from a standing shoulder leaves it 0.46 short — measured). 62 deg of body pitch drops the shoulder the missing half-metre.
        self.bodyLean = lerpF(-24.0, 62.0, k);
        self.headPitch = lerpF(-20.0, 24.0, kArm);
        self.twist = lerpF(-26.0, 12.0, kArm); // the coil releases through the strike
        self.clubTilt = lerpF(WIND_TILT, SLAM_TILT, kArm); // wrist whip — the head leads the haft at impact
        self.clubAbd = lerpF(WIND_ABD, SLAM_ABD, kArm);
        self.clubSweep = lerpF(self.clubSweep, 0, kArm);
        self.legBrace = lerpF(0.55, 0.95, k); // drive off the deeply-bent legs, sinking his weight in
        self.jawOpen = lerpF(JAW_ROAR, JAW_GRIT, mathx.smoothstep(0.15, 0.8, k)); // the roar cuts off
        self.girdle = lerpF(GIRDLE_WIND, -6.0, kArm); // into set teeth as the yoke drives down
    }
    fn setSwipeWind(self: *Ogre, k: f32) void {
        const kArm = mathx.smoothstep(0, 1, k);
        self.twist = lerpF(0, -46.0, k); // coil hard over the back hip…
        self.clubShoulder = lerpF(CARRY_SH, -26.0, kArm);
        self.clubElbow = lerpF(CARRY_EL, -38.0, kArm); // height, elbow gathered in
        self.clubAbd = lerpF(CLUB_ABD, 58.0, kArm); // held OUT to the side — the plane of the sweep
        self.clubSweep = lerpF(0, -20.0, kArm);
        self.clubTilt = lerpF(CARRY_TILT, 34.0, kArm); // the head trails the fist round the coil
        self.offShoulder = lerpF(OFF_SH, -28.0, kArm); // the free arm counters across his front
        self.offElbow = lerpF(OFF_EL, -52.0, kArm);
        self.bodyLean = lerpF(HUNCH, HUNCH - 5.0, k); // he STANDS UP into it (not a stoop)
        self.headPitch = lerpF(HEAD_DROOP, -6.0, k); // eye up, fixed on you through the turn
        self.legBrace = lerpF(0, 0.30, k); // feet set — planted, barely bent
        self.jawOpen = lerpF(JAW_REST, JAW_ROAR * 0.55, k); // a snarl, not the slam's full bellow
        self.girdle = lerpF(0, 9.0, kArm);
    }
    fn setSwipe(self: *Ogre, k: f32) void {
        const kW = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k); // the whip: almost all of it up front
        self.twist = lerpF(-46.0, 52.0, kW);
        self.clubShoulder = lerpF(-26.0, -6.0, kW);
        self.clubElbow = lerpF(-38.0, -8.0, kW); // the arm straightens as it comes round (reach)
        self.clubAbd = lerpF(58.0, 66.0, kW); // stays out level through the sweep
        self.clubSweep = lerpF(-20.0, 52.0, kW);
        self.clubTilt = lerpF(34.0, -18.0, kW); // the head whips PAST the fist — it leads the arc
        self.offShoulder = lerpF(-28.0, 22.0, kW); // the free arm flings back as counterweight
        self.offElbow = lerpF(-52.0, -20.0, kW);
        self.bodyLean = lerpF(HUNCH - 5.0, HUNCH + 8.0, k);
        self.headPitch = lerpF(-6.0, 12.0, kW);
        self.legBrace = lerpF(0.30, 0.42, k); // still planted — the turn is at the waist
        self.jawOpen = lerpF(JAW_ROAR * 0.55, JAW_GRIT, mathx.smoothstep(0.1, 0.7, k));
        self.girdle = lerpF(9.0, -2.0, kW);
    }
    fn setRecover(self: *Ogre, u: f32) void {
        if (self.swiped) return self.setSwipeRecover(u);
        const spent = 1.0 - mathx.smoothstep(0.7, 1.0, u);
        const heave = 3.0 * mathx.sinf(self.elapsed * 7.0) * spent;
        const ring = self.judder * mathx.sinf(self.t * 44.0);
        self.clubShoulder = lerpF(CARRY_SH, SLAM_SH, spent) + heave * 0.4 + 6.5 * ring; // the club bounces, settles
        self.clubElbow = lerpF(CARRY_EL, SLAM_EL, spent) + 3.0 * ring;
        self.offShoulder = lerpF(OFF_SH, -8.0, spent);
        self.offElbow = lerpF(OFF_EL, -34.0, spent);
        self.bodyLean = lerpF(HUNCH, 58.0, spent) + 2.2 * ring; // still folded over the buried club
        self.headPitch = lerpF(HEAD_DROOP, 34.0 + heave, spent);
        self.twist = lerpF(0, 6.0, spent); // still slung a touch through from the blow
        self.clubTilt = lerpF(CARRY_TILT, SLAM_TILT, spent) + 4.0 * ring;
        self.clubAbd = lerpF(CLUB_ABD, SLAM_ABD, spent); // still splayed over the planted club
        self.clubSweep = 0; // the slam ended dead ahead of him — nothing to unwind sideways
        self.legBrace = lerpF(0, 1.0, spent); // splayed + buckled, bearing weight on the club
        self.jawOpen = lerpF(JAW_REST, JAW_PANT + 3.0 * heave, spent) + 2.0 * ring;
        self.girdle = lerpF(0, GIRDLE_SPENT, spent) + heave * 0.5;
    }

    // After a SWIPE: not the slam's collapse, an OVERSWING.
    fn setSwipeRecover(self: *Ogre, u: f32) void {
        const over = 1.0 - mathx.smoothstep(0.35, 1.0, u); // how much overswing is left in him
        const settle = mathx.sinf(u * std.math.pi * 2.0) * (1.0 - u) * 2.5; // he rocks back off the turn
        self.twist = lerpF(0, 52.0, over) + settle;
        self.clubShoulder = lerpF(CARRY_SH, -4.0, over);
        self.clubElbow = lerpF(CARRY_EL, -30.0, over); // the arm folds ACROSS him as it dies
        self.clubAbd = lerpF(CLUB_ABD, 40.0, over);
        self.clubSweep = lerpF(0, 52.0, over); // the arm is still out ACROSS him where the swing left it
        self.clubTilt = lerpF(CARRY_TILT, -14.0, over);
        self.offShoulder = lerpF(OFF_SH, 20.0, over);
        self.offElbow = lerpF(OFF_EL, -22.0, over);
        self.bodyLean = lerpF(HUNCH, HUNCH + 8.0, over) + settle * 0.4;
        self.headPitch = lerpF(HEAD_DROOP, 10.0, over);
        self.legBrace = lerpF(0, 0.42, over);
        self.jawOpen = lerpF(JAW_REST, JAW_PANT * 0.6, over);
        self.girdle = lerpF(0, -4.0, over);
    }

    fn stunAmount(self: *const Ogre) f32 {
        if (self.state == .stunlight) {
            const u = mathx.clampF(self.t / combat.FOE_LIGHT_STUN_DUR, 0, 1);
            return mathx.sinf(u * std.math.pi);
        } else if (self.state == .stunheavy) {
            const u = mathx.clampF(self.t / combat.FOE_HEAVY_STUN_DUR, 0, 1);
            return mathx.pulse(u, 0, 0.12, 0.78, 1.0);
        }
        return 0;
    }

    pub fn pose(self: *Ogre) void {
        const fs = self.scale * (1.0 - 0.55 * self.fade);
        const sink = -0.95 * self.scale * self.fade; // the corpse sinks as it dissipates
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const du = if (dead) mathx.clampF(self.t / DEATH_DUR, 0, 1) else 0;
        const dk1 = mathx.smoothstep(0, 0.32, du);
        const dk2 = mathx.smoothstep(0.22, 0.62, du);
        const settle = mathx.pulse(du, 0.62, 0.72, 0.72, 0.88); // the bounce
        const stun = self.stunAmount();
        const light = self.state == .stunlight;
        const heavy = self.state == .stunheavy;
        const lstun: f32 = if (light) stun else 0;
        const hstun: f32 = if (heavy) stun else 0;

        const m = self.moving * (1.0 - dk1);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const catchDip = -0.020 * H * self.jolt * m;
        const braceSink = -BRACE_SINK * self.legBrace; // he DROPS his weight into a slam (legPose folds to match)
        const sway = A_SWAY * mathx.sinf(twoPi * self.phase) * m +
            A_SWAY * self.latB * mathx.cosf(twoPi * self.phase) * m;

        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk1);
        const wshift = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28); // −1..1 weight phase
        const idleBob = A_BREATHE * mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 3.0) * idleAmt;
        const idleSway = A_IDLE_SWAY * wshift * idleAmt;

        var wx: [N]rl.Matrix = undefined;
        const bodyPitch = self.bodyLean * (1.0 - dk2) - 40.0 * lstun + 34.0 * hstun;
        const leanX = PELVIS_SHARE * bodyPitch + 2.2 * self.jolt * m + 84.0 * dk2 + 5.0 * settle;
        const waist = (1.0 - PELVIS_SHARE) * bodyPitch;
        const lumber = A_LUMBER * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase + 0.5) * m;
        const rollZ = 16.0 * dk2 + 9.0 * hstun + IDLE_ROLL * wshift * idleAmt + lumber + 1.5 * self.judder * mathx.sinf(self.t * 44.0);
        const drop = -0.24 * H * hstun; // pelvis sinks on the heavy stagger (toward a knee)
        const collapse = lerpF(hipY, 0.32 * H, dk1); // the knees give — the pelvis comes down on dk1
        const pelvY = if (dead) collapse else hipY + bob + catchDip + idleBob + braceSink + drop;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(rollZ), rx(leanX), ry(prot)),
            mul(tr((sway + idleSway) * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        // Legs.
        if (!dead) {
            if (self.moving > 0.25) {
                // NO LATERAL GAIT (owner's call): a giant does not cross its legs.
                heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, 0, 1.0, HIPL, KNEEL, solePatches[0]);
                heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, 0, -1.0, HIPR, KNEER, solePatches[1]);
            } else {
                const leftFree = mathx.clampF(-wshift, 0, 1) * idleAmt; // left leg relaxes when weight rocks right
                const rightFree = mathx.clampF(wshift, 0, 1) * idleAmt;
                self.legPose(&wx, 1.0, leftFree, self.legBrace, HIPL, KNEEL, ANKL);
                self.legPose(&wx, -1.0, rightFree, self.legBrace, HIPR, KNEER, ANKR);
            }
        }
        self.poseUpper(&wx, dk1, dk2, lstun, hstun, dead, lumber, prot, waist);
        // TOES last — they hang off whichever ankle the branches above resolved (walk, stand, brace or crumple), and every bone must get a matrix every frame.
        const curl = mathx.maxF(dk1, 0.6 * hstun);
        self.toePose(&wx, self.phase, m, curl, TOEL);
        self.toePose(&wx, self.phase + 0.5, m, curl, TOER);
        self.xf = wx;
    }

    fn toePose(self: *const Ogre, wx: *[N]rl.Matrix, ph: f32, m: f32, curl: f32, toe: usize) void {
        const p = ph - @floor(ph);
        const roll = (TOE_PUSH * stridePulse(p, 0.28, 0.62) - TOE_LIFT * stridePulse(p, 0.62, 1.0)) * m;
        setLocal(wx, toe, self.rest, rx(roll + TOE_GRIP * self.legBrace + TOE_CURL * curl + 2.0 * self.jolt * m));
    }

    // One leg posed for the standing beats (idle / mid-attack), NOT the walk (legChain does that).
    fn legPose(self: *const Ogre, wx: *[N]rl.Matrix, side: f32, free: f32, brace: f32, hip: usize, knee: usize, ank: usize) void {
        const hipFlex = BRACE_HIP * brace + 5.0 * free;
        const kneeFlex = IDLE_KNEE + BRACE_KNEE * brace + 18.0 * free;
        const splay = STANCE_WIDEN * brace; // feet plant wider under the load
        setLocal(wx, hip, self.rest, mul(rx(-hipFlex), rz(-side * HIP_ADDUCT + side * splay)));
        setLocal(wx, knee, self.rest, rx(kneeFlex));
        const ankFlex = lerpF(hipFlex * 0.5, kneeFlex - hipFlex, brace) - 8.0 * free; // free heel eases up
        setLocal(wx, ank, self.rest, mul(rx(ankFlex), ry(side * FOOT_TOEOUT)));
    }

    fn poseUpper(self: *Ogre, wx: *[N]rl.Matrix, dk1: f32, dk2: f32, lstun: f32, hstun: f32, dead: bool, lumber: f32, prot: f32, waist: f32) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk1);
        const armPh = std.math.tau * self.phase;
        // Is the club HANGING (carried) or committed to a swing?
        const hung: f32 = switch (self.state) {
            .windup, .slam, .swipewind, .swipe, .recover => 0,
            else => 1,
        };
        const nod = TRUNK_NOD * (0.5 - 0.5 * mathx.cosf(2.0 * armPh)) * m + 1.6 * self.jolt * m;
        // Curl the spine into the hunch; a stance-break folds it further, a flinch throws it back.
        const spineFlex = 6.0 + 26.0 * dk1 + 12.0 * hstun - 14.0 * lstun;
        // THE WAIST HINGE.
        setLocal(wx, SPINE, rest, mul3(rx(spineFlex * 0.40 + waist * 0.46 + nod * 0.45), ry(self.twist * 0.4 - 0.45 * prot), rz(-0.30 * lumber)));
        setLocal(wx, CHEST, rest, mul3(rx(spineFlex * 0.32 + waist * 0.34 + nod * 0.55), ry(self.twist * 0.6 - 0.75 * prot), rz(-0.45 * lumber)));
        // The HUMP: the mass between his shoulders, on its own hinge.
        const humpBreathe = mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28) * (1.0 - m);
        setLocal(wx, HUMP, rest, mul3(
            rx(spineFlex * 0.26 + waist * 0.20 + nod * 0.30 + 7.0 * hstun - 9.0 * lstun + 5.0 * dk2 + 1.3 * humpBreathe),
            ry(self.twist * 0.2 - 0.25 * prot),
            rz(-0.22 * lumber),
        ));
        // Head: hangs low and sad, scanning at idle, sighting on a windup, lolling on death.
        const level = 0.6 * hung * mathx.maxF(0, waist - (1.0 - PELVIS_SHARE) * HUNCH);
        setLocal(wx, NECK, rest, mul3(rx(self.headPitch * 0.35 + self.headLook * 0.3 + 8.0 * dk1 - 0.55 * nod - level * 0.45), ry(0.55 * prot + 0.30 * self.headYaw), rz(-lumber * 0.5)));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.6 + self.headLook * 0.7 + 14.0 * dk2 + 16.0 * hstun - 26.0 * lstun - 0.45 * nod - level * 0.55),
            ry(0.70 * self.headYaw + 0.65 * prot), // the crane is SHARED with the neck above (0.30 there)
            rz(-lumber * 0.35 + 18.0 * dk2),
        ));
        const jaw = self.jawOpen + JAW_FLINCH * lstun + 16.0 * hstun + JAW_DEATH * mathx.maxF(dk1, dk2) +
            JAW_JOSTLE * (0.8 * self.jolt * m + 0.6 * self.judder * mathx.sinf(self.t * 31.0));
        setLocal(wx, JAW, rest, rx(mathx.maxF(0, jaw)));

        const buckle = mathx.maxF(dk1, 0.7 * hstun);
        if (dead or hstun > 0.05) {
            setLocal(wx, HIPL, rest, mul(rx(-58.0 * buckle), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(6.0 + 104.0 * buckle));
            setLocal(wx, ANKL, rest, ry(6.0));
            setLocal(wx, HIPR, rest, mul(rx(-44.0 * buckle), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(6.0 + 88.0 * buckle));
            setLocal(wx, ANKR, rest, ry(-6.0));
        }

        const freeSwing = OFF_ARM_SWING * mathx.cosf(armPh) * m;
        const clubSwing = CLUB_ARM_SWING * mathx.cosf(armPh - CLUB_LAG) * m;
        const clubPend = CLUB_PEND * (0.5 - 0.5 * mathx.cosf(armPh - CLUB_LAG - PEND_LAG)) * m;
        const freeFlex = OFF_ELBOW_SWING * (0.5 - 0.5 * mathx.cosf(armPh - 0.5)) * m;
        const clubFlex = CLUB_ELBOW_SWING * (0.5 - 0.5 * mathx.cosf(armPh - CLUB_LAG - 0.5)) * m;
        const hitchL = GIRDLE_SWING * OFF_ARM_SWING * mathx.cosf(armPh - GIRDLE_LAG) * m;
        const hitchR = GIRDLE_SWING * CLUB_ARM_SWING * mathx.cosf(armPh - CLUB_LAG - GIRDLE_LAG) * m;
        const shrugL = self.girdle + hitchL + 5.0 * lstun - 8.0 * dk2;
        const shrugR = (self.girdle + hitchR) * lerpF(1.0, CLAV_LOAD, hung) - CLAV_DROOP * hung + 4.0 * lstun - 10.0 * dk2;
        // +rz lifts a LEFT-side point and −rz a right-side one; −ry protracts the left shoulder.
        setLocal(wx, CLAVL, rest, mul(rz(shrugL), ry(-GIRDLE_PROT * prot)));
        setLocal(wx, CLAVR, rest, mul(rz(-shrugR), ry(GIRDLE_PROT * prot)));
        // Off arm (left): rests low, flings out for balance on the windup, thrown up on a flinch.
        const armFly = -66.0 * lstun;
        setLocal(wx, SHL, rest, mul(rx(self.offShoulder + armFly * 0.6 - 18.0 * dk2 + freeSwing), rz(OFF_ABD + ARM_ABD_SWING * freeSwing)));
        setLocal(wx, ELL, rest, rx(self.offElbow - freeFlex));
        setLocal(wx, WRL, rest, rx(-WRIST_FLOP * freeSwing)); // the empty hand lags — dead weight
        // Club arm (right): the whole slam arc rides this shoulder + elbow; the flinch flings it up.
        setLocal(wx, SHR, rest, mul3(rx(self.clubShoulder + armFly - 22.0 * dk2 - clubSwing), rz(-self.clubAbd - ARM_ABD_SWING * clubSwing), ry(self.clubSweep)));
        setLocal(wx, ELR, rest, rx(self.clubElbow - clubFlex));
        setLocal(wx, WRR, rest, rl.math.matrixIdentity());
        // The club rides the wrist frame; clubTilt rakes it back for the carry and whips it through the blow, clubPend rocks it on the walk (a fixed tilt read as welded-on), and clubHold gives the fist back what the arm's swing took off the rake (the hover survives).
        const clubHold = CLUB_HOLD * mathx.maxF(0, clubSwing + clubFlex); // only pays back the DIPS
        setLocal(wx, CLUB, rest, rx(self.clubTilt + clubPend + clubHold - nod));
    }

    fn impactWorld(self: *const Ogre) rl.Vector3 {
        const low = self.clubLowWorld();
        return v3(low.x, self.pos.y + 0.05, low.z); // a hair over the ground HE stands on
    }
    // The pool plumbing is the shared one (foe.zig) — these just name the ogre's own ring.
    fn emit(self: *Ogre, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.fx, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }
    fn updateFx(self: *Ogre, dt: f32) void {
        foe.tickParticles(&self.fx, dt, self.pos.y); // dust settles on the ground HE is standing on
    }
    // A radial fan of dust from `c` (the slam crush; scaled up for the giant).
    fn dustBurst(self: *Ogre, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.5, 1.0) * spd * self.scale;
            const vel = v3(mathx.cosf(a) * s, self.fxRng.range(0.8, 3.0), mathx.sinf(a) * s);
            self.emit(v3(c.x, 0.06, c.z), vel, self.fxRng.range(0.4, 0.7), self.fxRng.range(0.08, 0.16) * self.scale, big * self.fxRng.range(0.8, 1.3) * self.scale, DUST, 4.5);
        }
    }
    // Windup STRAIN trickle: gravel + dust dug up around the feet as it plants and loads.
    fn emitStrain(self: *Ogre, dt: f32, k: f32) void {
        self.fxAccum += (6.0 + 22.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.3, 0.9) * self.scale;
            const bp = v3(self.pos.x + mathx.cosf(a) * rr, 0.05, self.pos.z + mathx.sinf(a) * rr);
            self.emit(bp, v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.3, 1.0), self.fxRng.signed() * 0.3), self.fxRng.range(0.3, 0.5), self.fxRng.range(0.05, 0.11) * self.scale, self.fxRng.range(0.1, 0.18) * self.scale, DUST, 3.5);
        }
    }
    // Heavy footfall dust: a puff under the planting foot as the stride phase crosses 0.0 / 0.5.
    fn footfalls(self: *Ogre) void {
        if (self.moving < 0.4) {
            self.prevPhase = self.phase;
            return;
        }
        const crossed = (self.prevPhase < 0.5 and self.phase >= 0.5) or (self.phase < self.prevPhase); // 0.5 or the wrap past 0.0
        if (crossed) {
            self.jolt = 1.0; // the pelvis CATCHES on the planting leg (pose dips + nods off this)
            const side: f32 = if (self.phase < 0.5) 1.0 else -1.0;
            const f = self.fdir();
            const rr = 0.13 * H * self.scale;
            const foot = v3(self.pos.x - f.z * side * rr, 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(foot, 6, 1.4, 0.14);
            sfx.world(.ogre_step, foot);
        }
        self.prevPhase = self.phase;
    }
    // Dark ichor flung from the contact point along the blade's sweep.
    fn bloodBurst(self: *Ogre, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            const vel = v3(
                dir.x * sp + mathx.cosf(a) * self.fxRng.range(0.2, 1.0),
                self.fxRng.range(0.8, 2.8),
                dir.z * sp + mathx.sinf(a) * self.fxRng.range(0.2, 1.0),
            );
            self.emit(at, vel, self.fxRng.range(0.3, 0.55), self.fxRng.range(0.04, 0.08) * self.scale, 0.01, BLOOD, 7.5);
        }
    }
    // Death dissipation: grace-gold motes rising off the sinking corpse (ER-consistent).
    fn emitDissolve(self: *Ogre, dt: f32) void {
        self.fxAccum += 70.0 * (1.0 - 0.6 * self.fade) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.1, 1.0) * self.scale * (1.0 - 0.6 * self.fade);
            const p = v3(self.pos.x + mathx.cosf(a) * rr, self.fxRng.range(0.05, 0.7) * self.scale, self.pos.z + mathx.sinf(a) * rr);
            if (self.fxRng.float() < 0.75) {
                self.emit(p, v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.5, 1.5), self.fxRng.signed() * 0.3), self.fxRng.range(0.6, 1.1), self.fxRng.range(0.04, 0.09) * self.scale, 0.004, MOTE, -0.7);
            } else {
                self.emit(p, v3(self.fxRng.signed() * 0.4, self.fxRng.range(0.1, 0.5), self.fxRng.signed() * 0.4), self.fxRng.range(0.35, 0.7), self.fxRng.range(0.06, 0.13) * self.scale, 0.012, DUST, 2.0);
            }
        }
    }
    pub fn drawFx(self: *const Ogre) void {
        foe.drawParticles(&self.fx);
    }

    pub fn draw(self: *const Ogre, model: *const Model) void {
        model.draw(&self.xf);
    }
};

const CAP = wf.MAX_PER_KIND;

pub const Grief = struct {
    model: Model,
    ogres: [CAP]Ogre = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Grief {
        return .{ .model = Model.init(shader) };
    }
    /// The ogres this map posted — never iterate the whole array, the tail is `undefined`.
    pub fn live(self: *Grief) []Ogre {
        return self.ogres[0..self.n];
    }
    /// Read-only view, for the `*const Grief` paths (draw, the roll-ups).
    pub fn liveConst(self: *const Grief) []const Ogre {
        return self.ogres[0..self.n];
    }
    // Re-home the giant, alive and fresh (a hero death reloads the world, ER-style).
    pub fn reset(self: *Grief, m: *const wf.Map) void {
        foe.resetGroup(Ogre, &self.ogres, &self.n, m, .ogre);
    }
    pub fn setShader(self: *Grief, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    // Advance the group; returns the STRONGEST blow any ogre landed on the hero this frame, and which ogre threw it (the hero's shield covers an arc — see foe.Blow).
    pub fn update(self: *Grief, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Grief, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Grief) void {
        for (self.liveConst()) |*o| o.drawFx();
    }
    // The shared Group roll-ups (foe.zig).
    /// ONE OF THE HERO'S SHAFTS through the group — the first member it reaches takes it.
    pub fn pierce(self: *Grief, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Grief) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn runesDropped(self: *const Grief) u32 {
        return foe.runesDropped(self.liveConst(), RUNES);
    }
    pub fn totalHits(self: *const Grief) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Grief) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = torsoMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = headMesh();
    mesh[HIPL] = thighMesh();
    mesh[KNEEL] = shinMesh();
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh();
    mesh[KNEER] = shinMesh();
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh();
    mesh[ELL] = forearmMesh(31, false);
    mesh[WRL] = fistMesh(true); // the off hand wears the FORSAKEN's broken manacle
    mesh[SHR] = upperArmMesh();
    mesh[ELR] = forearmMesh(77, true); // the club forearm, rope-lashed for the grip
    mesh[WRR] = fistMesh(false);
    mesh[CLUB] = clubMesh();
    mesh[JAW] = jawMesh();
    mesh[TOEL] = toeMesh(1.0);
    mesh[TOER] = toeMesh(-1.0);
    mesh[HUMP] = humpMesh();
    mesh[CLAVL] = clavicleMesh(1.0, false);
    mesh[CLAVR] = clavicleMesh(-1.0, true); // the club side: bigger, carried higher
    return mesh;
}

// FLESH IS ROUND.
fn limb(b: *Builder, a: rl.Vector3, e: rl.Vector3, r0: f32, r1: f32, col: rl.Color) void {
    const mid = mathx.lerpV(a, e, 0.42);
    b.addCapsule(a, mid, r0, r0 * 1.09, 12, col);
    b.addCapsule(mid, e, r0 * 1.09, r1, 12, col);
    b.addBlob(e, v3(r1 * 1.16, r1 * 1.02, r1 * 1.16), 6, 12, col); // the joint ball
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // A ROUNDED hip mass — one wide ellipsoid, real glutes swelling behind it, a slung groin.
    b.addBlob(v3(0, 0.002 * H, 0.005 * H), v3(0.152 * H, 0.086 * H, 0.132 * H), 8, 14, HIDE);
    b.addBlob(v3(0.070 * H, -0.010 * H, -0.080 * H), v3(0.082 * H, 0.070 * H, 0.072 * H), 7, 12, HIDE); // L glute
    b.addBlob(v3(-0.067 * H, -0.002 * H, -0.074 * H), v3(0.077 * H, 0.066 * H, 0.068 * H), 7, 12, HIDE); // R glute, a touch higher
    b.addBlob(v3(0, -0.072 * H, 0.042 * H), v3(0.084 * H, 0.050 * H, 0.070 * H), 7, 12, BELLY); // low groin
    b.addBlob(v3(0.095 * H, 0.048 * H, 0.020 * H), v3(0.050 * H, 0.032 * H, 0.048 * H), 5, 10, HIDE_LT); // hip crests
    b.addBlob(v3(-0.092 * H, 0.052 * H, 0.016 * H), v3(0.046 * H, 0.030 * H, 0.046 * H), 5, 10, HIDE_LT); // uneven
    b.setMat(.leather);
    // a plaited rope belt cinched crooked round the hips — the rag hangs off it
    b.addCylinder(v3(0.10 * H, 0.048 * H, 0), v3(-0.10 * H, 0.058 * H, 0), 0.145 * H, 0.145 * H, 9, ROPE);
    b.setMat(.cloth);
    const strips = [_][3]f32{ .{ 0.088, 0.150, 0.128 }, .{ 0.030, 0.155, 0.176 }, .{ -0.036, 0.152, 0.104 }, .{ -0.092, 0.146, 0.150 }, .{ -0.006, -0.148, 0.132 } };
    for (strips) |s| {
        const w = 0.030 + 0.010 * @abs(s[0]);
        b.addBox(
            v3(s[0] * H, (-0.030 - s[2] * 0.5) * H, s[1] * H),
            v3(w * H, 0, 0.004 * H),
            v3(s[0] * 0.06 * H, -s[2] * 0.5 * H, if (s[1] > 0) 0.014 * H else -0.014 * H),
            v3(0, 0, 0.009 * H),
            RAG,
        );
    }
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0.008 * H, 0), v3(0, 0.120 * H, -0.004 * H), 0.150 * H, 0.186 * H, 14, HIDE); // thick waist → chest
    b.addBlob(v3(0, 0.052 * H, 0.062 * H), v3(0.146 * H, 0.070 * H, 0.098 * H), 8, 13, BELLY); // the sagging gut, slung forward
    b.addBlob(v3(0, -0.004 * H, 0.052 * H), v3(0.136 * H, 0.032 * H, 0.088 * H), 6, 13, HIDE_DK); // the fold where it overhangs the belt
    b.addBlob(v3(0, 0.046 * H, 0.152 * H), v3(0.032 * H, 0.020 * H, 0.018 * H), 5, 9, HIDE_DK); // navel
    b.addBlob(v3(0.088 * H, 0.020 * H, -0.062 * H), v3(0.062 * H, 0.058 * H, 0.056 * H), 6, 11, HIDE); // slab of back muscle
    b.addBlob(v3(-0.084 * H, 0.028 * H, -0.058 * H), v3(0.058 * H, 0.062 * H, 0.052 * H), 6, 11, HIDE); // uneven either side
    return b.toMesh();
}

fn torsoMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.022 * H, -0.012 * H), v3(0.232 * H, 0.080 * H, 0.166 * H), 9, 15, HIDE);
    b.addBlob(v3(0, -0.036 * H, -0.005 * H), v3(0.206 * H, 0.062 * H, 0.150 * H), 7, 14, HIDE); // lower ribs into the waist
    b.addBlob(v3(0.070 * H, 0.012 * H, 0.108 * H), v3(0.090 * H, 0.070 * H, 0.078 * H), 8, 13, HIDE); // L pec, sagging
    b.addBlob(v3(-0.072 * H, 0.016 * H, 0.112 * H), v3(0.098 * H, 0.076 * H, 0.082 * H), 8, 13, HIDE); // R pec (club side) — heavier
    b.addBlob(v3(0, 0.000 * H, 0.140 * H), v3(0.030 * H, 0.088 * H, 0.030 * H), 6, 10, BELLY); // sternum valley
    b.addBlob(v3(0.010 * H, -0.060 * H, 0.126 * H), v3(0.098 * H, 0.026 * H, 0.040 * H), 6, 11, SCAR); // old scar under the ribs
    var rng = mathx.Rng.init(7321);
    var w: i32 = 0;
    while (w < 16) : (w += 1) {
        const a = rng.angle();
        const yy = rng.range(-0.05, 0.10) * H;
        const rr = (0.226 - (yy / H + 0.02) * 0.34) * H; // follow the barrel's taper — proud, not buried
        const sz = rng.range(0.016, 0.036) * H;
        b.addBlob(v3(mathx.cosf(a) * rr, yy, mathx.sinf(a) * rr * 0.72 - 0.012 * H), v3(sz, sz * rng.range(0.6, 1.1), sz * rng.range(0.7, 1.2)), 5, 9, if (rng.float() < 0.5) HIDE_DK else HIDE_LT);
    }
    return b.toMesh();
}

fn humpMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.012 * H, -0.088 * H), v3(0.142 * H, 0.078 * H, 0.088 * H), 9, 14, HIDE_DK);
    b.addBlob(v3(0.004 * H, 0.026 * H, -0.062 * H), v3(0.112 * H, 0.048 * H, 0.070 * H), 7, 13, HIDE); // its caught-light crown
    b.addBlob(v3(-0.058 * H, -0.048 * H, -0.104 * H), v3(0.058 * H, 0.044 * H, 0.044 * H), 6, 10, HIDE_DK); // an uneven second lump
    b.setMat(.steel);
    b.addBox(v3(0.055 * H, 0.050 * H, -0.118 * H), v3(0.028 * H, 0.007 * H, 0.0), v3(-0.006 * H, 0.052 * H, -0.024 * H), v3(0, 0, 0.006 * H), CLUB_IRON);
    b.setMat(.skin);
    b.addBlob(v3(0.055 * H, -0.020 * H, -0.138 * H), v3(0.020 * H, 0.052 * H, 0.014 * H), 6, 9, IRON_RUST); // the rust-bleed streak
    return b.toMesh();
}

// One half of the shoulder GIRDLE, authored in its clavicle frame: a heavy trapezius sloping DOWN-AND-OUT (weary, not epaulettes) into the rounded deltoid boss the arm swings from.
fn clavicleMesh(side: f32, load: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const r0: f32 = if (load) 0.118 else 0.100;
    const r1: f32 = if (load) 0.088 else 0.076;
    const outer: f32 = if (load) 0.198 else 0.188;
    b.addCapsule(v3(side * 0.070 * H, 0.020 * H, -0.004 * H), v3(side * outer * H, -0.046 * H, 0), r0 * H, r1 * H, 13, HIDE);
    b.addBlob(v3(side * 0.162 * H, -0.026 * H, 0.006 * H), v3(r1 * 1.22 * H, r1 * 1.28 * H, r1 * 1.18 * H), 8, 13, HIDE); // deltoid cap
    b.addBlob(v3(side * 0.112 * H, 0.030 * H, -0.030 * H), v3(0.060 * H, 0.030 * H, 0.050 * H), 6, 10, if (load) HIDE_LT else HIDE_DK); // the yoke ridge
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.014 * H, -0.014 * H), v3(0, 0.046 * H, 0.052 * H), 0.100 * H, 0.086 * H, 13, HIDE);
    b.addBlob(v3(0, 0.008 * H, -0.052 * H), v3(0.104 * H, 0.038 * H, 0.042 * H), 7, 12, HIDE_DK); // nape fold
    b.addBlob(v3(0.062 * H, 0.014 * H, 0.026 * H), v3(0.034 * H, 0.044 * H, 0.030 * H), 6, 10, HIDE); // L tendon cord
    b.addBlob(v3(-0.058 * H, 0.020 * H, 0.030 * H), v3(0.030 * H, 0.048 * H, 0.028 * H), 6, 10, HIDE); // R, uneven
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.055 * H, 0.000 * H), v3(0.120 * H, 0.078 * H, 0.108 * H), 9, 15, HIDE); // cranium
    b.addBlob(v3(0, 0.008 * H, 0.048 * H), v3(0.114 * H, 0.072 * H, 0.098 * H), 9, 15, HIDE); // face mass
    b.addBlob(v3(0.014 * H, 0.098 * H, 0.014 * H), v3(0.050 * H, 0.018 * H, 0.062 * H), 6, 11, SCAR); // old scalp scar
    // the great brow — one heavy roll over the eye, with a lower lump at one end (the sad frown)
    b.addBlob(v3(0.004 * H, 0.078 * H, 0.084 * H), v3(0.088 * H, 0.026 * H, 0.034 * H), 7, 13, HIDE_DK);
    b.addBlob(v3(-0.060 * H, 0.068 * H, 0.086 * H), v3(0.042 * H, 0.022 * H, 0.030 * H), 6, 11, HIDE_DK); // drooped end
    b.addBlob(v3(0, 0.032 * H, 0.084 * H), v3(0.090 * H, 0.066 * H, 0.030 * H), 7, 13, EYE_RIM); // socket backing
    b.setMat(.plain); // glassy — no hide-material blotch over the glow
    b.addBlob(v3(0, 0.030 * H, 0.106 * H), v3(0.046 * H, 0.044 * H, 0.042 * H), 9, 14, EYE); // the amber orb
    b.addBlob(v3(0, 0.020 * H, 0.138 * H), v3(0.024 * H, 0.025 * H, 0.014 * H), 6, 11, PUPIL); // pupil set LOW — downcast
    b.setMat(.skin);
    // A HEAVY LID hooding the top third of the orb.
    b.addBlob(v3(0, 0.062 * H, 0.100 * H), v3(0.062 * H, 0.024 * H, 0.038 * H), 7, 12, HIDE_DK);
    b.addBlob(v3(0.030 * H, 0.048 * H, 0.114 * H), v3(0.028 * H, 0.014 * H, 0.020 * H), 6, 10, HIDE_DK); // lid corner, uneven
    b.addBlob(v3(0, -0.014 * H, 0.104 * H), v3(0.092 * H, 0.020 * H, 0.026 * H), 6, 12, HIDE_DK); // the weary bag under it
    b.addBlob(v3(0.004 * H, -0.030 * H, 0.116 * H), v3(0.046 * H, 0.028 * H, 0.032 * H), 7, 12, HIDE_DK); // squat nose
    b.addBlob(v3(0.072 * H, -0.012 * H, 0.070 * H), v3(0.030 * H, 0.036 * H, 0.038 * H), 6, 11, HIDE_DK); // L cheek hollow
    b.addBlob(v3(-0.072 * H, -0.018 * H, 0.068 * H), v3(0.030 * H, 0.040 * H, 0.038 * H), 6, 11, HIDE_DK); // R, deeper
    b.addBlob(v3(0, -0.050 * H, 0.068 * H), v3(0.086 * H, 0.030 * H, 0.062 * H), 7, 12, MAW); // the dark of the mouth
    b.addBlob(v3(0, -0.036 * H, 0.104 * H), v3(0.084 * H, 0.016 * H, 0.026 * H), 6, 12, HIDE); // upper lip roll
    b.setMat(.stone);
    for ([_]f32{ -1.2, -0.45, 0.45, 1.2 }) |t| { // blunt upper teeth, uneven (wabi-sabi)
        const tl: f32 = if (t < 0) 0.028 else 0.021;
        b.addCapsule(v3(t * 0.030 * H, -0.046 * H, 0.096 * H), v3(t * 0.032 * H, (-0.046 - tl) * H, 0.098 * H), 0.013 * H, 0.006 * H, 8, if (t < 0) TUSK else TUSK_DK);
    }
    b.setMat(.skin);
    // drooped little ears, pinned back-and-down (a beaten dog's set)
    b.addBlob(v3(0.126 * H, -0.010 * H, -0.006 * H), v3(0.016 * H, 0.046 * H, 0.030 * H), 7, 10, HIDE);
    b.addBlob(v3(-0.126 * H, -0.002 * H, -0.004 * H), v3(0.015 * H, 0.042 * H, 0.028 * H), 7, 10, HIDE);
    return b.toMesh();
}

// THE JAW — authored in its own hinge frame (the mandible pivot, under the eye and level with the cheeks).
fn jawMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.040 * H, 0.060 * H), v3(0.100 * H, 0.038 * H, 0.076 * H), 9, 14, HIDE); // the underbite mass
    b.addBlob(v3(0, -0.056 * H, 0.020 * H), v3(0.086 * H, 0.030 * H, 0.056 * H), 7, 12, HIDE); // jowl under the hinge
    b.addBlob(v3(0, -0.019 * H, 0.100 * H), v3(0.066 * H, 0.014 * H, 0.020 * H), 6, 12, HIDE_DK); // the downturned lip
    b.addBlob(v3(0.052 * H, -0.028 * H, 0.096 * H), v3(0.024 * H, 0.012 * H, 0.015 * H), 5, 10, HIDE_DK); // corner, slumped
    b.addBlob(v3(-0.050 * H, -0.031 * H, 0.094 * H), v3(0.026 * H, 0.012 * H, 0.015 * H), 5, 10, HIDE_DK);
    b.setMat(.plain);
    b.addBlob(v3(0, -0.026 * H, 0.050 * H), v3(0.052 * H, 0.013 * H, 0.050 * H), 7, 12, TONGUE); // the slack tongue
    b.setMat(.stone);
    b.addCapsule(v3(0.048 * H, -0.025 * H, 0.115 * H), v3(0.056 * H, 0.038 * H, 0.128 * H), 0.017 * H, 0.005 * H, 8, TUSK);
    b.addCapsule(v3(-0.052 * H, -0.030 * H, 0.115 * H), v3(-0.062 * H, 0.062 * H, 0.130 * H), 0.020 * H, 0.006 * H, 8, TUSK_DK);
    for ([_]f32{ -0.6, 0.6 }) |t| { // a couple of blunt lower teeth beside them
        b.addCapsule(v3(t * 0.032 * H, -0.022 * H, 0.098 * H), v3(t * 0.034 * H, 0.006 * H, 0.100 * H), 0.012 * H, 0.006 * H, 7, TUSK_DK);
    }
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.10 * H, 0.075 * H, HIDE); // massive thigh
    b.addBlob(v3(0.058 * H, -0.100 * H, 0.048 * H), v3(0.044 * H, 0.042 * H, 0.030 * H), 6, 11, SCAR); // an old calloused gouge
    b.addBlob(v3(-0.010 * H, -0.062 * H, -0.062 * H), v3(0.060 * H, 0.070 * H, 0.040 * H), 7, 12, HIDE); // hamstring swell
    return b.toMesh();
}

fn shinMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_SHANK * H, 0), 0.072 * H, 0.055 * H, HIDE); // thick calf
    b.addBlob(v3(0, -0.070 * H, -0.048 * H), v3(0.062 * H, 0.070 * H, 0.038 * H), 7, 12, HIDE); // the calf belly, high + behind
    b.addBlob(v3(0, -0.190 * H, -0.030 * H), v3(0.036 * H, 0.052 * H, 0.024 * H), 6, 11, HIDE_DK); // the tendon narrowing to the heel
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const ay = 0.039 * H;
    const PAD_UP = 0.036 * H;
    b.addCapsule(v3(0, -ay + 0.032 * H + PAD_UP, -0.026 * H), v3(0, -ay + 0.026 * H + PAD_UP, 0.086 * H), 0.068 * H, 0.058 * H, 13, HIDE); // the pad
    b.addBlob(v3(0, -ay + 0.044 * H + PAD_UP, -0.030 * H), v3(0.062 * H, 0.052 * H, 0.058 * H), 8, 13, HIDE_DK); // heel / ankle boss
    b.addBlob(v3(side * 0.020 * H, -ay + 0.020 * H + PAD_UP, 0.030 * H), v3(0.062 * H, 0.034 * H, 0.062 * H), 7, 12, HIDE); // the sole pad, splayed
    return b.toMesh();
}

fn toeMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    for ([_]f32{ -1, 0, 1 }) |t| { // toe lobes, middle one longest
        const tl: f32 = if (t == 0) 0.082 else 0.066;
        b.addCapsule(v3(t * 0.040 * H * side, 0.002 * H, 0.002 * H), v3(t * 0.048 * H * side, -0.005 * H, tl * H), 0.031 * H, 0.024 * H, 11, HIDE);
    }
    b.setMat(.stone);
    for ([_]f32{ -1, 0, 1 }) |t| { // blunt nails, one cracked shorter (wabi-sabi)
        const nl: f32 = if (t * side > 0.5) 0.010 else 0.016;
        const tz: f32 = if (t == 0) 0.084 else 0.069;
        b.addBlob(v3(t * 0.048 * H * side, -0.004 * H, tz * H), v3(0.021 * H, 0.015 * H, nl * H), 6, 10, TUSK_DK);
    }
    return b.toMesh();
}

fn upperArmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // Leaner than it was (0.088/0.072): the mass moved to the fists.
    limb(&b, v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.077 * H, 0.063 * H, HIDE); // heavy upper arm
    b.addBlob(v3(0, -0.064 * H, 0.046 * H), v3(0.055 * H, 0.064 * H, 0.036 * H), 7, 12, HIDE); // biceps swell, front
    b.addBlob(v3(0, -0.078 * H, -0.043 * H), v3(0.050 * H, 0.070 * H, 0.032 * H), 7, 12, HIDE); // triceps, long + behind
    b.addBlob(v3(-0.018 * H, -0.082 * H, 0.062 * H), v3(0.030 * H, 0.047 * H, 0.018 * H), 6, 11, SCAR); // old brand / callous
    return b.toMesh();
}

fn forearmMesh(seed: u64, corded: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_FOREARM * H, 0), 0.066 * H, 0.053 * H, HIDE); // thick forearm
    b.addBlob(v3(0, -0.043 * H, 0.018 * H), v3(0.062 * H, 0.050 * H, 0.051 * H), 7, 12, HIDE); // the forearm's upper mass
    var rng = mathx.Rng.init(seed);
    b.addBlob(v3(rng.range(-0.027, 0.027) * H, -rng.range(0.055, 0.11) * H, 0.046 * H), v3(0.027 * H, 0.023 * H, 0.018 * H), 6, 10, if (rng.float() < 0.5) SCAR else HIDE_DK); // a wart / old weal
    if (corded) { // the CLUB forearm: wound with old rope — the grip it never lets go of
        // Bands hug the LEANER shaft and stay inside the shorter segment (ends at −SEG_FOREARM·H).
        b.setMat(.leather);
        b.addCylinder(v3(0, -0.066 * H, 0), v3(0, -0.093 * H, 0), 0.066 * H, 0.064 * H, 8, ROPE);
        b.addCylinder(v3(0, -0.111 * H, 0), v3(0, -0.129 * H, 0), 0.061 * H, 0.059 * H, 8, ROPE);
    }
    return b.toMesh();
}

fn fistMesh(shackled: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.032 * H, 0.009 * H), v3(0.078 * H, 0.073 * H, 0.070 * H), 9, 13, HIDE); // big fist
    b.addBlob(v3(0, -0.054 * H, 0.023 * H), v3(0.066 * H, 0.038 * H, 0.060 * H), 7, 12, HIDE); // the curled fingers' mass
    b.setMat(.skin);
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |k| { // four ROUND knuckles, uneven — not one flat ridge
        b.addBlob(v3(k * 0.034 * H, -0.010 * H, 0.050 * H), v3(0.022 * H, 0.020 * H, 0.020 * H), 6, 10, HIDE_LT);
    }
    b.setMat(.stone);
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |k| { // blunt knuckle-nails, one cracked short
        const nl: f32 = if (k > 1.0) 0.013 else 0.019;
        b.addBlob(v3(k * 0.034 * H, -0.015 * H, 0.070 * H), v3(0.016 * H, 0.020 * H, nl * H), 6, 10, TUSK_DK);
    }
    if (shackled) {
        b.setMat(.steel);
        b.addCylinder(v3(0, 0.040 * H, 0.005 * H), v3(0, 0.012 * H, 0.005 * H), 0.057 * H, 0.055 * H, 8, CLUB_IRON);
        b.addCube(v3(0, 0.026 * H, 0.064 * H), v3(0.020 * H, 0.024 * H, 0.014 * H), IRON_RUST); // the rivet boss
        var li: i32 = 0;
        while (li < 3) : (li += 1) {
            const fi = @as(f32, @floatFromInt(li));
            b.addCube(
                v3(0.005 * H * fi, (-0.005 - 0.036 * fi) * H, (0.066 + 0.007 * fi) * H),
                v3(0.013 * H, 0.026 * H, 0.009 * H),
                if (li == 1) IRON_RUST else CLUB_IRON,
            );
        }
    }
    return b.toMesh();
}

// The great club — authored in the RIGHT-WRIST frame, gripped near the top of the haft and extending DOWN the arm line (−Y), so the raked carry trails it behind him and the swing rears it overhead.
const CLUB_DROP = 0.30 * H; // grip → the club's LOWEST point.
const CLUB_HEAD_R = 0.118 * H; // the drum's radius…
const CLUB_HEAD_HH = 0.082 * H;
const gy = -0.03 * H; // grip centre in the wrist frame (at the fist)
const gz = 0.02 * H; // a touch out front of the palm
// The club's lowest authored point, in the wrist frame — ride it through xf[CLUB] and you get the business end in world space (see clubLowWorld).
const CLUB_LOW = v3(0, gy - CLUB_DROP - 0.014 * H, gz + 0.022 * H);
fn clubMesh() rl.Mesh {
    var b = Builder.init();
    const headY = gy - CLUB_DROP + CLUB_HEAD_HH; // drum UNDERSIDE lands exactly on the budget line
    const drumTop = headY + CLUB_HEAD_HH; // where the haft's flare has to meet the head
    b.setMat(.leather);
    b.addCapsule(v3(0, gy + 0.19 * H, gz), v3(0, gy + 0.11 * H, gz), 0.038 * H, 0.042 * H, 10, ROPE); // rope-bound butt, proud of the fist
    b.setMat(.wood);
    b.addCylinder(v3(0, gy + 0.11 * H, gz), v3(0, gy, gz), 0.042 * H, 0.048 * H, 10, CLUB_WOOD_LT); // the worn grip
    b.addCylinder(v3(0, gy, gz), v3(0, drumTop + 0.055 * H, gz + 0.010 * H), 0.052 * H, 0.070 * H, 10, CLUB_WOOD); // haft, gently bowed
    b.addCylinder(v3(0, drumTop + 0.055 * H, gz + 0.010 * H), v3(0, drumTop - 0.012 * H, gz + 0.022 * H), 0.070 * H, 0.104 * H, 10, CLUB_WOOD); // flare into the head
    b.setMat(.steel);
    b.addCylinder(v3(0, gy - 0.062 * H, gz + 0.005 * H), v3(0, gy - 0.086 * H, gz + 0.006 * H), 0.072 * H, 0.072 * H, 8, CLUB_IRON); // iron lashing band
    b.addCylinder(v3(0, drumTop + 0.022 * H, gz + 0.013 * H), v3(0, drumTop - 0.004 * H, gz + 0.015 * H), 0.092 * H, 0.094 * H, 8, IRON_RUST); // rusted band
    // the head: a fat knotted BOULDER — wider than it is tall, so it reads heavy from any angle.
    b.setMat(.stone);
    b.addBlob(v3(0, headY, gz + 0.022 * H), v3(CLUB_HEAD_R * 1.06, CLUB_HEAD_HH, CLUB_HEAD_R * 1.06), 10, 14, CLUB_STONE);
    b.addBlob(v3(0.034 * H, headY + 0.022 * H, gz + 0.004 * H), v3(CLUB_HEAD_R * 0.80, CLUB_HEAD_HH * 0.92, CLUB_HEAD_R * 0.86), 8, 12, CLUB_STONE);
    // lashed-on stones, rusted iron lumps + DRIVEN SPIKES (seeded scatter — wabi-sabi).
    b.setMat(.steel);
    var rng = mathx.Rng.init(5119);
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const yy = headY + rng.range(-0.03, 0.085) * H; // banded round the drum, never slung under it
        const rr = CLUB_HEAD_R;
        const cx = mathx.cosf(a) * rr;
        const cz = gz + 0.022 * H + mathx.sinf(a) * rr;
        const sz = rng.range(0.020, 0.036) * H;
        const roll = rng.float();
        b.addBlob(v3(cx, yy, cz), v3(sz, sz * rng.range(0.7, 1.25), sz), 6, 10, if (roll < 0.35) CLUB_IRON else if (roll < 0.5) IRON_RUST else CLUB_STONE);
        if (rng.float() < 0.5) { // a driven iron spike, long enough to mean it
            const sl = rng.range(1.7, 2.25);
            b.addCylinder(v3(cx, yy, cz), v3(cx * sl, yy + rng.range(-0.02, 0.03) * H, gz + 0.022 * H + (cz - (gz + 0.022 * H)) * sl), 0.027 * H, 0.002 * H, 5, CLUB_IRON);
        }
    }
    // two snapped sword blades buried in the head — the hunts it walked away from
    b.addBox(v3(0.12 * H, headY + 0.055 * H, gz + 0.10 * H), v3(0.05 * H, 0.014 * H, 0.03 * H), v3(-0.004 * H, 0.05 * H, -0.01 * H), v3(0, 0, 0.006 * H), CLUB_IRON);
    b.addBox(v3(-0.11 * H, headY - 0.04 * H, gz - 0.055 * H), v3(0.055 * H, 0.010 * H, -0.035 * H), v3(0.004 * H, 0.012 * H, 0.0), v3(0, 0, 0.005 * H), IRON_RUST);
    return b.toMesh();
}

test "the swipe leaves a REACHABLE pocket at his feet — the counter has to exist" {
    // SWIPE_INNER's whole job is "hug his legs and the arc passes over you".
    const o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    const closest = foe.closestApproach(o.bodyR()); // collision never lets him nearer than this
    const sectorInner = SWIPE_INNER * o.scale - HERO_REACH; // where trySwipe starts connecting
    try std.testing.expect(sectorInner > closest + 0.2); // a real pocket, not a rounding error
    try std.testing.expect(sectorInner < SWIPE_OUTER * o.scale);
}

test "the carried club NEVER touches the ground — standing or lumbering (owner's law)" {
    var idle = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    var k: i32 = 0;
    while (k < 90) : (k += 1) { // a full breath + weight-shift cycle, so the low point is sampled
        _ = idle.update(1.0 / 60.0, v3(0, 0, 80), 60, .{}); // hero far away → holds idle
        try std.testing.expect(idle.clubLowWorld().y > 0.15);
    }
    var walk = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    var j: i32 = 0;
    var minY: f32 = 99;
    while (j < 160) : (j += 1) {
        _ = walk.update(1.0 / 60.0, v3(0, 0, 15), 60, .{});
        if (walk.state == .approach) minY = mathx.minF(minY, walk.clubLowWorld().y);
    }
    try std.testing.expect(minY > 0.15);
}

test "the SLAM reaches the earth, and the crush strip ends where the club does" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    o.debugSlam();
    var deepest: f32 = 99;
    var axialAtEarth: f32 = 0; // where the head FIRST touches down — the far end of the crater
    var k: i32 = 0;
    while (k < 90) : (k += 1) {
        _ = o.update(1.0 / 60.0, v3(0, 0, 2), 60, .{});
        if (o.state != .slam) continue;
        const c = o.clubLowWorld();
        if (c.y < 0.25 and axialAtEarth == 0) axialAtEarth = mathx.distXZ(o.pos, c);
        deepest = mathx.minF(deepest, c.y);
    }
    try std.testing.expect(deepest < 0.12); // it CRATERS — a slam that stops in the air is a mime
    const stripEnd = SLAM_LEN * o.scale;
    try std.testing.expect(stripEnd > axialAtEarth and stripEnd < axialAtEarth + 1.2);
    try std.testing.expect(SLAM_R < stripEnd + HERO_REACH); // never commit to a swing that can't land
}

test "the head clears the chest barrel — a giant with no visible head is the fail this guards" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    var k: i32 = 0;
    while (k < 110) : (k += 1) _ = o.update(1.0 / 60.0, v3(0, 0, 15), 60, .{}); // lumbering (worst case)
    const chest = rl.math.vector3Transform(mathx.zero3, o.xf[CHEST]);
    const skull = rl.math.vector3Transform(mathx.zero3, o.xf[SKULL]);
    // torsoMesh's barrel tops out 0.102 H above the chest joint; the skull's centre must be clear.
    try std.testing.expect(skull.y - chest.y > 0.102 * H * SCALE);
}

test "the swipe's hurt SECTOR matches where the club actually goes (band + arc, measured)" {
    var o = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.4);
    o.debugSwipe();
    var lowest: f32 = 99;
    var highest: f32 = -99;
    var frames: u32 = 0;
    var fr: i32 = 0;
    while (fr < 40) : (fr += 1) {
        _ = o.update(1.0 / 60.0, v3(3.6, 0, -1.2), 60, .{}); // a hero round on his left flank
        if (o.state != .swipe) continue;
        frames += 1;
        const club = o.clubLowWorld();
        const rad = mathx.distXZ(o.pos, club);
        try std.testing.expect(rad >= SWIPE_INNER * o.scale and rad <= SWIPE_OUTER * o.scale);
        const bearing = mathx.degrees(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(o.pos, club)) - o.facing));
        try std.testing.expect(@abs(mathx.wrapDeg(bearing - SWIPE_ARC_MID)) <= SWIPE_ARC * 0.5);
        lowest = mathx.minF(lowest, club.y);
        highest = mathx.maxF(highest, club.y);
    }
    try std.testing.expect(frames > 6); // it really did swipe
    // …and it scythes THROUGH a hero-sized body (head 1.7 down to hip ~1.0), not over his hat.
    try std.testing.expect(highest > 1.6 and lowest < 1.3);
}

test "attack choice: squared up crushes, flanked SWIPES, cooling looms, far closes, out of aggro idles" {
    try std.testing.expectEqual(Choice.idle, classify(AGGRO_R + 1, 0, true, true)); // disengaged
    try std.testing.expectEqual(Choice.slam, classify(SLAM_R - 0.5, 0, true, true)); // dead ahead → crush
    // OFF HIS FRONT: the swipe is the whole point — it beats the slam even with the slam ready.
    try std.testing.expectEqual(Choice.swipe, classify(SLAM_R - 0.5, 80, true, true));
    try std.testing.expectEqual(Choice.swipe, classify(SWIPE_R - 0.2, -120, true, true));
    // …and it's also his answer while the slam is cooling, even to a hero standing dead ahead.
    try std.testing.expectEqual(Choice.swipe, classify(SLAM_R - 0.5, 0, false, true));
    try std.testing.expectEqual(Choice.wait, classify(SLAM_R - 0.5, 0, false, false)); // all cooling → loom
    // Flanked but OUT of swipe reach: close the gap first, don't swing at nothing.
    try std.testing.expectEqual(Choice.approach, classify(SWIPE_R + 1.0, 90, true, true));
    try std.testing.expectEqual(Choice.approach, classify((SWIPE_R + AGGRO_R) * 0.5, 0, true, true));
}

test "range bands are ordered and sit inside aggro" {
    try std.testing.expect(SLAM_R < SWIPE_R); // the horizontal arc outreaches the overhead drop
    try std.testing.expect(SWIPE_R < AGGRO_R);
}

test "swipe hurt SECTOR: sweeps the whole front arc, misses the flanks behind it and the legs" {
    var side = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z; his club side is −X
    side.trySwipe(v3(-2.4, 0, 2.4), SWIPE_HIT); // 45 deg off his front on the CLUB side — the arc's path
    try std.testing.expect(side.heroHit != null);

    var front = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    front.trySwipe(v3(0, 0, 3.0), SWIPE_HIT); // dead ahead, mid-band — the arc crosses his centre
    try std.testing.expect(front.heroHit != null);

    var offside = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    offside.trySwipe(v3(2.6, 0, 1.6), SWIPE_HIT); // round on his FREE side, past where the club ends
    try std.testing.expect(offside.heroHit == null); // (measured: the sweep dies at about +22 deg)

    var behind = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.trySwipe(v3(0, 0, -3.0), SWIPE_HIT); // dead behind — outside the sector
    try std.testing.expect(behind.heroHit == null);

    var under = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    under.trySwipe(v3(0, 0, 0.35), SWIPE_HIT); // hugging his legs — the club passes overhead
    try std.testing.expect(under.heroHit == null);

    var far = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.trySwipe(v3(0, 0, SWIPE_OUTER * SCALE + 2.0), SWIPE_HIT); // ahead but beyond the band
    try std.testing.expect(far.heroHit == null);
}

test "higher poise: a single hero light does NOT flinch the ogre (only sustained pressure does)" {
    var vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX);
    // One hero light (poise 10) vs the ogre's 30 poise → no reaction (it shrugs it off).
    try std.testing.expectEqual(combat.HitResult.none, vit.hit(heromod.ATK_LIGHT_HIT));
    // Three quick lights (no regen between) empty the 30 poise → the first flinch.
    _ = vit.hit(heromod.ATK_LIGHT_HIT);
    try std.testing.expectEqual(combat.HitResult.light, vit.hit(heromod.ATK_LIGHT_HIT));
}

test "slam crush is the club's LINE: hits ahead on the axis, clears the flanks + behind" {
    var front = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
    front.tryImpact(v3(0, 0, 2.0), SLAM_HIT); // dead ahead, in reach — under the falling club
    try std.testing.expect(front.heroHit != null);

    var beside = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    beside.tryImpact(v3(2.4, 0, 0.6), SLAM_HIT); // close, but well OFF the club's line — the
    try std.testing.expect(beside.heroHit == null); // old half-disc fan wrongly crushed this

    var grazing = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    grazing.tryImpact(v3(0.9, 0, 1.8), SLAM_HIT); // ahead and only a stride off the line — clipped
    try std.testing.expect(grazing.heroHit != null);

    var behind = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.tryImpact(v3(0, 0, -2.0), SLAM_HIT); // same distance, behind
    try std.testing.expect(behind.heroHit == null);

    var far = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.tryImpact(v3(0, 0, 99), SLAM_HIT); // on the line but way out of reach
    try std.testing.expect(far.heroHit == null);
}
