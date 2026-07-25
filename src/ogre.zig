const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// ── THE ONE-EYED OGRE ───────────────────────────────────────────────────────────────────
// The third foe: a GIANT — roughly twice the hero's height — hunched, humanoid-LEANING but
// misshapen, hefting an enormous knotted club at his side. A sad figure (heavy brow, downcast single
// eye, a slumped weary carriage) that is nonetheless a real threat: HIGH POISE (it shrugs off
// single lights — you must land sustained pressure to stagger it) and a slow, ground-eating
// approach into a big committed OVERHEAD CLUB SLAM. Only the one attack for now (the brief
// promises a tricky array later — the state machine is laid out so more drop in beside it).
//
// FOUNDED ON THE HUMANOID MODEL (owner's rule, see AGENTS.md + archer.zig): it reuses the
// hero's real anthropometry scaffold — the same 18-bone parent hierarchy + FK convention —
// and, crucially, LOCOMOTES ON THE HERO'S NORMATIVE GAIT (heromod.advanceGait + legChain),
// never a bespoke walk. What differs is the SKIN (a hulking mis-proportioned frame: barrel
// chest, long heavy arms, a low small head with ONE eye) and the UPPER body (the club carry +
// the overhead slam ride on top of the shared legs). The weapon slot is repurposed as the
// CLUB. Because the whole rig scales up (SCALE), the stride phase is fed a scale-corrected
// distance so the giant's long legs don't skate (see update()).
//
// The upper body ARTICULATES on the walk as hard as the legs do (AGENTS.md's second humanoid
// rule): contralateral arm swing, a shoulder girdle counter-rotating against the pelvis, a trunk
// nod per footfall, and a chain of deliberate LAGS — the loaded club arm trails the stride, the
// club trails the arm. Shared legs under a rigid trunk is what reads as moving in ONE PIECE.
//
// Rendering discipline matches hero/frog/archer: procedural Builder meshes drawn with drawMesh
// through one scene-shader material, so it lights + casts shadows like everything else.

// ── palette (pre-gamma dark — the scene shader gammas output, so mid values lift) ──────────
// Ashen grey-tan hide, paler scarred belly, near-black hollows, pale bone tusks + nails, and
// ONE eye of dull, tired amber — a lonely lamp, not a fierce glare (the sad read).
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

// ── rig: an 18-bone humanoid, the hero's exact joint layout + parenting (the shared model),
// with the weapon slot repurposed as the CLUB, parented to the RIGHT wrist. ────────────────
const N = 18;
const ROOT = 0; // pelvis
const SPINE = 1; // lumbar
const CHEST = 2; // barrel ribcage + shoulder girdle
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

const parent = [N]i32{ -1, ROOT, SPINE, CHEST, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CHEST, SHL, ELL, CHEST, SHR, ELR, WRR };

const H: f32 = heromod.H;
// Ogre proportions (fractions of H): LEGS keep the hero's segment lengths so the shared gait
// reads honestly; ARMS run long + heavy, the frame wide. Bulk comes from the meshes + the
// hunch, not from warping the leg chain the gait expects.
const SEG_THIGH = 0.245;
const SEG_SHANK = 0.246;
const SEG_UPARM = 0.210; // long, heavy arms — but not so long they knuckle-drag + hide the legs
const SEG_FOREARM = 0.170;

fn restPositions() [N]rl.Vector3 {
    const hx = 0.135; // wide hip half-separation (a broad base)
    const sx = 0.235; // wide, slumped shoulders
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.645, 0);
    r[CHEST] = v3(0, 0.775, 0);
    // The neck JUTS FORWARD out of the hump (vulture-set) so the low head + eye read clear of
    // the shoulder silhouette. Burying the skull in the trapezius was the old fail — no head.
    r[NECK] = v3(0, 0.822, 0.045);
    r[SKULL] = v3(0, 0.878, 0.105);
    r[HIPL] = v3(hx, 0.530, 0);
    r[KNEEL] = v3(hx, 0.285, 0);
    r[ANKL] = v3(hx, 0.039, 0);
    r[HIPR] = v3(-hx, 0.530, 0);
    r[KNEER] = v3(-hx, 0.285, 0);
    r[ANKR] = v3(-hx, 0.039, 0);
    // The CLUB shoulder rides higher, the off shoulder slumps — a permanent working skew
    // (each chain shifts wholesale, so segment lengths stay identical; cosmetic wabi-sabi).
    r[SHL] = v3(sx, 0.791, 0);
    r[ELL] = v3(sx, 0.556, 0);
    r[WRL] = v3(sx, 0.361, 0);
    r[SHR] = v3(-sx, 0.809, 0);
    r[ELR] = v3(-sx, 0.574, 0);
    r[WRR] = v3(-sx, 0.379, 0);
    r[CLUB] = v3(-sx, 0.379, 0); // zero offset from the wrist; club mesh authored in the wrist frame
    for (&r) |*p| p.* = v3(p.x * H, p.y * H, p.z * H);
    return r;
}

// matrix shorthand (shared mathx TRS — mul(a,b) applies a FIRST then b)
const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;

// world(child) = animRot ∘ translate(offset) ∘ world(parent) — the hero's exact convention.
fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    const p: usize = @intCast(parent[i]);
    const off = mathx.subV(rest[i], rest[p]);
    const local = mul(animRot, tr(off.x, off.y, off.z));
    wx[i] = mul(local, wx[p]);
}

// ── scale / locomotion / senses ───────────────────────────────────────────────────────────
pub const SCALE = 2.1; // a hulking giant — ~1.9x the hero to the crown (owner: shrunk from 2.5)
const WALK_SPEED = heromod.WALK_SPEED * 0.72; // a slow, ground-eating lumber (long legs cover it)
const AGGRO_R = 18.0; // it sees you coming from far off (it's huge)
const SLAM_R = 3.5; // starts the overhead slam within this — kept INSIDE the crush strip's true end
//   (SLAM_LEN x scale + HERO_REACH = 3.70) so committing to the 0.9 s windup at max range doesn't
//   guarantee a whiff on a hero who simply stands still.
const TURN_RATE = 2.4; // rad/s — PONDEROUS: a giant is out-turned, so circling it is the counter
const BODY_R = 0.55; // ground footprint (pre-scale) — broad
const HURT_R = 0.72; // hurt-sphere radius the hero's blade tests against (pre-scale) — a big target
// Pelvis walk oscillation — the hero's amplitudes (heavier), scaled with the body at draw.
const A_BOB = 0.030 * H;
const A_SWAY = 0.014 * H;
const A_LUMBER = 6.5; // deg the trunk rolls toward the stance foot through each stride
const A_PROT = 6.0; // deg of pelvic TRANSVERSE rotation — the swagger (the hero walks on 3.5)
const TRUNK_NOD = 5.5; // deg the trunk flexes twice a stride as the mass settles onto each foot

// ── slam timing (seconds) — a LONG readable wind-up (the tell lands early), a fast crash, and
// a long winded recovery (the punish window a giant's slow attack must give). ───────────────
const WINDUP_DUR = 0.90; // rear the club overhead — the unmistakable tell
const SLAM_DUR = 0.22; // …then FIRE: a fast downward crash
const SLAM_IMPACT_K = 0.72; // fraction into the slam the club meets the ground (impact frame)
const RECOVER_DUR = 1.20; // hunched over the buried club, spent + wide open
const SLAM_CD = 1.3; // beat between slams
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 6.0;

// ── combat vitals (a mini-boss: high poise so single lights won't interrupt it — the brief's
// "higher poise" — a long HP bar, and a stance meter that only breaks under sustained pressure) ─
const HP_MAX = 300.0;
const POISE_MAX = 30.0; // 3 fast hero-lights (poise 10) to flinch once; a lone light is shrugged off
const STANCE_MAX = 90.0; // keep the pressure on to reach the heavy stance-break
pub const SLAM_HIT = combat.Hit{ .dmg = 28, .poise = 44, .stance = 20 }; // a crushing body-blow (heavy); dmg eased down from 34
const DEATH_DUR = 1.7; // a slow, weighty topple — a giant falls hard (and sadly)
const DISS_DUR = 1.1; // dissipation into grace-gold motes (ER-consistent with frog/archer)

// hero.attackHit() decides the hero's own blows; these constants are what the OGRE lands. The
// slam crush zone is the CLUB'S LINE — a strip down the facing axis, NOT a half-disc fan (the
// old shape was an unfair AoE); flank the line and you're safe.
const HERO_REACH = 0.55; // hero footprint added to the strip on both axes
const SLAM_LEN = 1.50; // crush strip length ahead of the seat (pre-scale). MEASURED, not guessed:
//   clubLowWorld() puts the crater centre 2.43 out at impact and the studded drum's own footprint
//   carries ~0.7 further, so 1.50 x scale lands the strip's end on the club's actual outer edge.
//   Retune the club or the slam arc and this has to be re-measured with it.
const SLAM_HALF_W = 0.45; // crush strip HALF-width (pre-scale) — about the club head + shock

// ── posture channel constants (degrees) — the club carry + the slam arc + the sad idle ─────
const HUNCH = 9.0; // base forward stoop — stooped + weary, but still standing TALL (imposing)
// THE CARRY (owner's call): the club is HEFTED AT HIS SIDE, never dragged. The arm hangs
// plumb-and-a-hair-back under the weight and the club is RAKED BACK in the fist so the stone
// head trails behind him, hovering a hand's breadth clear of the grass — it must never touch
// (a club ploughing through the dirt was the old goof), and only the SLAM reaches the earth.
const CARRY_SH = 5.0; // club arm hangs plumb, a hair BACK — the head's weight pulls it behind
const CARRY_EL = -13.0; // a heavy arm keeps some natural flex — never a straight pole
// NB the club's world rake is the SUM of every ancestor's pitch — the body's hunch/lean and the
// spine + chest flexion all rake it further back before the arm chain even starts. So this is a
// small number and still lands the club ~35 deg off vertical: don't read it as the final angle.
const CARRY_TILT = 20.0; // the club raked back in the fist (deg off the forearm) — the hover
const WIND_TILT = 30.0; // cocked back off the shoulder at the top of the windup
const SLAM_TILT = -10.0; // whipped through AHEAD of the haft at impact (the head leads)
const OVER_SH = -158.0; // upper arm thrown up-and-back — the club COCKS diagonally over the
const WIND_EL = -78.0; //   shoulder like a headsman's backswing, not a vertical telescope
const SLAM_SH = -52.0; // club crashed forward-and-down into the earth, FOLLOWING THROUGH past
//   vertical so the head lands out ahead of him (a strike that ends straight down has no reach)
const SLAM_EL = -6.0; // elbow driven near-straight through the blow
const OFF_SH = -14.0; // off arm rests low
const OFF_EL = -18.0;
const HEAD_DROOP = 15.0; // downcast, sad at rest (+ = looks down) — low, but the face still shows
// THE EYE TRACKS YOU. A giant is OUT-TURNED (TURN_RATE is only ~137 deg/s), so the head has to
// get there first: it swivels onto your bearing well ahead of the body, craning to the limit of a
// neck and no further. Circling him, that swivel is the single biggest "he is alive and he has
// noticed" cue — and a free, honest telegraph of who he has decided to crush.
const HEAD_YAW_MAX = 55.0; // deg the neck cranes before the body has to come round with it
const HEAD_TRACK_RATE = 220.0; // deg/s — comfortably faster than the body's turn, so it LEADS
const HEAD_SCAN = 26.0; // deg of the slow, sad idle sweep when nothing is in range
const HEAD_LOOK_DOWN = 16.0; // extra downward pitch at arm's length: he has to look DOWN at you

// ── the WALK's upper-body articulation (owner's law: a humanoid must NOT move in one piece) ──
// Contralateral swing, giant-scaled, with every link arriving LATE by its own weight: the FREE
// arm swings huge and loose, the CLUB arm is loaded with a hundredweight of stone so it swings
// SHORT and BEHIND the stride, and the club keeps rocking in the fist after the arm has already
// turned over — a pendulum hung off a pendulum. THE LAGS ARE THE POINT: every joint peaking on
// the same frame is exactly what reads as one welded block, however big the amplitudes get.
const OFF_ARM_SWING = 26.0; // deg the free shoulder swings (the hero walks on 9 — a giant lumbers)
const OFF_ELBOW_SWING = 22.0; // deg the free elbow flexes through its forward swing
const CLUB_ARM_SWING = 9.0; // the loaded shoulder swings short — the club's mass damps it
const CLUB_ELBOW_SWING = 6.0; // and its elbow barely gives (locked round the haft)
const CLUB_LAG = 0.6; // rad the loaded arm trails the stride — heavy limbs arrive late
const CLUB_PEND = 7.0; // deg the club rocks in the fist, trailing the arm in its turn
const PEND_LAG = 1.0; // rad the club's own rock trails the arm's swing
// ABDUCTION — the club arm is held OUT from the body, and this is load-bearing in both senses:
// a giant hefts a hundredweight of stone clear of his own legs, AND the whole chain's vertical
// drop scales by cos(abduction), which is most of what lifts the head off the grass. It has to
// come back IN for the slam, though, or the club crashes down beside the facing line instead of
// on it — so it's a resolved channel like the rest, not a constant.
const CLUB_ABD = 34.0; // carried: held well out, taking the weight off his stride
const WIND_ABD = 16.0; // cocked overhead, coming in over the centre
const SLAM_ABD = -14.0; // NEGATIVE = adducted ACROSS the body: the shoulder sits ~0.9 out to his
//   right, so an arm that merely hangs drops the club a metre off the facing line the crush strip
//   is drawn down. Swinging it across brings the crater back under the line the hitbox claims.
const OFF_ABD = 14.0; // the empty arm just hangs clear of the barrel
const ARM_ABD_SWING = 0.35; // fraction of a swing bled into abduction (arms sweep arcs, not planes)
const WRIST_FLOP = 0.30; // fraction of the swing the empty hand lags by — passive dead weight
const CLUB_HOLD = 0.6; // fraction of the arm swing the FIST pays back into the club's rake, so the
//   head keeps its hover all stride instead of dipping into the grass on every forward swing —
//   which is what a grip physically does: he is holding the angle, not letting the thing flop.

// ── idle life + attack footwork (a big fella is never a frozen statue) ─────────────────────
// The leg rest-stance constants are the hero's (legChain uses these), re-stated so the idle /
// braced legs line up exactly with the shared walk when it kicks in (no jump at the hand-off).
const HIP_ADDUCT = heromod.HIP_ADDUCT;
const FOOT_TOEOUT = heromod.FOOT_TOEOUT;
const IDLE_KNEE = heromod.IDLE_KNEE;
const IDLE_RATE = 1.5; // rad/s of the slow weight-shift cycle (~4.2 s period — heavy, unhurried)
const BREATHE_RATE = 1.05; // rad/s of the breathing bob
const A_BREATHE = 0.012 * H; // idle breathing rise/fall of the pelvis
const A_IDLE_SWAY = 0.020 * H; // idle lateral weight-sway (rocks foot to foot)
const IDLE_ROLL = 3.2; // deg the torso rolls toward the weighted foot
const STANCE_WIDEN = 9.0; // deg the feet plant wider when bracing for a slam
// A BRACE is a giant DROPPING HIS WEIGHT into the blow, so the legs have to fold deep enough to
// swallow BRACE_SINK of pelvis height — and the pelvis has to actually come down by it, or the
// knees bend around feet that never move (the club then can't reach the earth it's aimed at).
// The three are one triangle: change the angles and BRACE_SINK must follow, or the soles leave
// the ground. thigh 0.245 H + shank 0.246 H, so span = 0.245 cos(hip) + 0.246 cos(knee − hip).
const BRACE_HIP = 26.0; // deg of hip flexion at full brace
const BRACE_KNEE = 56.0; // deg of knee flexion at full brace
const BRACE_SINK = 0.066 * H; // …the pelvis drop those two angles absorb exactly

// ── telegraph FX (a small unlit particle pool — dust, blood, death motes; like the toad's) ──
const FX_MAX = 56;
const DUST = rgba(150, 132, 96, 175); // kicked-up dust (warm tan; unlit, so lift the value)
const BLOOD = rgba(84, 20, 16, 235); // dark ichor spray on a landed blow
const MOTE = rgba(252, 198, 92, 170); // death dissipation — grace-gold motes

const Particle = struct {
    p: rl.Vector3 = mathx.zero3,
    v: rl.Vector3 = mathx.zero3,
    life: f32 = 0,
    max: f32 = 1,
    r0: f32 = 0.05,
    r1: f32 = 0.05,
    col: rl.Color = DUST,
    grav: f32 = 0,
};

// The hero's blade as plain data (the shared foe standard). Re-exported for symmetry.
pub const Blade = foe.Blade;

// idle/approach/windup/slam/recover are the live behaviours; the last three are REACTIONS
// (interrupts) — a light flinch, the heavy stance-break, and death.
const State = enum { idle, approach, windup, slam, recover, stunlight, stunheavy, dead };

// Pure attack decision — a function of range + cooldown, so it's unit-testable without a world.
const Choice = enum { slam, approach, wait, idle };
fn classify(dist: f32, slamReady: bool) Choice {
    if (dist > AGGRO_R) return .idle; // hasn't noticed / has disengaged
    if (dist <= SLAM_R) return if (slamReady) .slam else .wait; // in reach: crush when ready, else loom
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
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    slamCd: f32 = 0,
    elapsed: f32 = 0,
    slammed: bool = false, // one crush per slam (the impact burst + hero hit are latched)
    returning: bool = false, // .approach is trudging back HOME (disengaged), not chasing the hero

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

    // combat
    vit: combat.Vitals = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX),
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
        o.rest = restPositions();
        o.fxRng = mathx.Rng.init(@as(u64, @intFromFloat(seed * 88883.0)) +% 7);
        o.pose();
        return o;
    }

    // ── foe-contract accessors (heights in world units, so they ride the giant scale) ───────
    pub fn centerWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 0.60 * H * self.scale, self.pos.z); // chest-ish mass centre
    }
    pub fn hurtRadius(self: *const Ogre) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ogre) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 0.62 * H * self.scale, self.pos.z);
    }
    pub fn topWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 1.02 * H * self.scale, self.pos.z);
    }
    // The head, roughly — for framing the face close-up (the single eye) in --shot.
    pub fn headWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 0.86 * H * self.scale, self.pos.z);
    }
    // The club's business end in world space, straight off the posed bone. Carried, its Y is the
    // hover the whole CARRY tuning exists to protect (it must stay clear of the grass); slamming,
    // it is the crater. Reads last frame's pose, which at 60 fps is close enough for a dust burst.
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
        return mathx.clampF(self.flash / FLASH_DUR, 0, 1);
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
        const d = mathx.dirXZ(self.pos, target);
        if (mathx.lenXZ(d) < 1e-3) return;
        self.facing = mathx.approachAngle(self.facing, mathx.headingXZ(d), TURN_RATE * dt);
    }

    // ── per-frame update; returns the blow the ogre landed on the HERO this frame (null if
    // none / corpse). Mirrors the toad: vitals tick, state machine, shared gait, pose(), then
    // the hero's blade LAST (tryHit) — a kill sets justDied for this frame's beat. ────────────
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
        self.flash = mathx.maxF(0, self.flash - dt);
        self.t += dt;
        self.updateFx(dt);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;

        // Hit shove — a jolt off a landed blow (a giant barely budges, so it decays fast).
        if (mathx.lenXZ(self.shove) > 0.01) {
            self.pos.x = mathx.clampF(self.pos.x + self.shove.x * dt, -bounds, bounds);
            self.pos.z = mathx.clampF(self.pos.z + self.shove.z * dt, -bounds, bounds);
            self.shove = mathx.scaleV(self.shove, mathx.maxF(0, 1.0 - SHOVE_DECAY * dt));
        }

        const d = mathx.distXZ(self.pos, hero);
        self.trackHead(hero, d, dt); // the eye leads the body — every state, not just the idle
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                if (self.t >= 0.2) self.decide(d);
            },
            .approach => {
                // Chasing → face/move toward the HERO; disengaged (returning) → toward HOME.
                const tgt = if (self.returning) self.home else hero;
                self.faceToward(tgt, dt);
                const f = self.fdir();
                const moved = WALK_SPEED * dt;
                self.pos.x = mathx.clampF(self.pos.x + f.x * moved, -bounds, bounds);
                self.pos.z = mathx.clampF(self.pos.z + f.z * moved, -bounds, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(f); // travels along facing → forward gait
                self.setCarry(dt);
                if (self.returning) {
                    // Re-aggro if the hero wanders back into range; else stop once home.
                    if (d <= AGGRO_R) {
                        self.returning = false;
                        self.decide(d);
                    } else if (mathx.distXZ(self.pos, self.home) <= 2.0) self.enterIdle();
                } else if (d <= SLAM_R or d > AGGRO_R) self.decide(d);
            },
            .windup => {
                self.faceToward(hero, dt * 0.4); // a little tracking while rearing (committed tell)
                // Rear to the peak by ~82% of the windup, then HOLD the loaded beat — a still,
                // trembling hover is a scarier and fairer tell than a ramp that fires on topping out.
                const k = mathx.smoothstep(0, WINDUP_DUR * 0.82, self.t);
                self.setWindup(k);
                self.emitStrain(dt, k); // gravel trickles as it plants + loads
                if (self.t >= WINDUP_DUR) self.enter(.slam);
            },
            .slam => {
                const k = mathx.smoothstep(0, SLAM_DUR, self.t);
                self.setSlam(k);
                if (self.t >= SLAM_DUR * SLAM_IMPACT_K) {
                    self.tryImpact(hero, SLAM_HIT); // the club meets the earth — FRONT crush zone
                    if (!self.slammed) {
                        self.slammed = true;
                        self.judder = 1.0; // the club BOUNCES off the earth (rings through recover)
                        // Dust kept TIGHT to the landing so the ring doesn't oversell the narrow
                        // crush strip — a 4 m ring over a 1.5 m kill line taught the wrong dodge.
                        self.dustBurst(self.impactWorld(), 36, 3.8, 0.38);
                    }
                }
                if (self.t >= SLAM_DUR) {
                    self.slamCd = SLAM_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.setRecover(mathx.clampF(self.t / RECOVER_DUR, 0, 1));
                if (self.t >= RECOVER_DUR) self.enterIdle();
            },
            // The stuns keep easing the carry channels toward neutral UNDER the big stun deltas
            // — else a flinch mid-windup freezes the reared-back pose beneath the recoil (wrong).
            .stunlight => {
                self.easeChannelsNeutral(dt);
                if (self.t >= combat.LIGHT_STUN_DUR) self.enterIdle();
            },
            .stunheavy => {
                self.easeChannelsNeutral(dt);
                if (self.t >= combat.HEAVY_STUN_DUR) self.enterIdle();
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

        // Drive the SHARED humanoid gait. The stride phase is fed a SCALE-CORRECTED distance so
        // the giant's long legs cycle at the right cadence for their reach (no skating).
        const gaitSpeed: f32 = if (movedDist > 0) WALK_SPEED else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.footfalls(); // heavy dust puffs + the pelvis CATCH as each foot plants
        self.pose();
        self.tryHit(blade); // hero's blade AFTER the state machine (like the toad); a kill here
        //   flags justDied for this frame's kill beat, cleared at the top of the next update.
        return self.heroHit;
    }

    fn enter(self: *Ogre, s: State) void {
        self.state = s;
        self.t = 0;
        if (s == .slam) {
            self.slammed = false;
            self.heroLatch = false; // a fresh slam gets one chance to crush the hero
        }
    }
    fn enterIdle(self: *Ogre) void {
        self.state = .idle;
        self.t = 0;
        self.returning = false;
    }
    fn enterStun(self: *Ogre, s: State) void {
        self.state = s; // the interrupt drops any in-progress slam (nothing lands)
        self.t = 0;
        self.slammed = false;
        self.returning = false;
    }
    fn enterDeath(self: *Ogre) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
        self.returning = false;
    }

    // Pick the next action from range + cooldown. In reach + ready → the overhead slam; in reach
    // but cooling → loom (a short idle beat, menacing); too far → close in; disengaged → drift home.
    fn decide(self: *Ogre, dist: f32) void {
        switch (classify(dist, self.slamCd <= 0)) {
            .slam => self.enter(.windup),
            .approach => {
                self.returning = false; // chasing the hero
                self.enter(.approach);
            },
            .wait => self.enterIdle(),
            .idle => {
                if (mathx.distXZ(self.pos, self.home) > 3.0) {
                    self.returning = true; // wandered — trudge back toward HOME (approach handles it)
                    self.enter(.approach);
                } else self.enterIdle();
            },
        }
    }

    // ── the hero's blade lands on the ogre (the SHARED foe.strike behaviour) ────────────────
    fn tryHit(self: *Ogre, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        self.bloodBurst(s.contact, s.dir, if (heavyBlow) 16 else 10, if (heavyBlow) 2.8 else 2.0);
        // A giant barely gives — a much smaller shove than the toad's, so hits read as glancing off bulk.
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 0.7 else 0.4);
        switch (s.reaction) {
            .death => {
                self.bloodBurst(s.contact, s.dir, 14, 2.4);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {}, // shrugged off (its high poise) — the slam windup rolls on
        }
    }

    // The slam CRUSH: the club's ground footprint — a STRIP down the facing line. `axial` = how
    // far ahead along the facing, `lateral` = off that line; both must be inside the club's span
    // (beside the landing or behind is CLEAR — sidestep off the line).
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
    }

    // Debug hooks for the --shot harness (force a pose in isolation).
    pub fn debugSlam(self: *Ogre) void {
        self.enter(.windup);
    }
    pub fn debugStagger(self: *Ogre, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Ogre) void {
        self.enterDeath();
    }

    // The head aims itself, independently of the body — see the HEAD_YAW_MAX block. In range it
    // cranes onto your BEARING (clamped to a neck's travel, so past that he must turn his whole
    // body and you can keep out-circling him) and pitches DOWN the closer you get; out of range it
    // falls back to the slow sad sweep of the ruins. Reeling or dead, the head is not his to aim.
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

    // ── posture resolvers (set the channel fields for the current beat) ─────────────────────
    fn setCarry(self: *Ogre, dt: f32) void {
        // Ease toward the weary carry; breathing + a heavy weight-sway keep it ALIVE at rest (the
        // club rocks, the head lolls), with an occasional long sad sigh. WALKING (moving→1) the
        // trunk pitches INTO the travel and the eye lifts to fix on the prey — the stalk.
        const e = dt * 6.0;
        const breathe = mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28);
        const rock = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28); // the weight-shift phase
        const sigh = mathx.smoothstep(0.80, 1.0, mathx.sinf(self.elapsed * 0.42 + self.seed * 11.0)); // a slow swell every ~15 s
        const stalk = self.moving; // 0 idle → 1 mid-approach
        self.clubShoulder = mathx.approach(self.clubShoulder, CARRY_SH + 3.0 * rock + 2.0 * sigh, e); // the heavy club swings
        self.clubElbow = mathx.approach(self.clubElbow, CARRY_EL + 2.5 * breathe, e);
        self.offShoulder = mathx.approach(self.offShoulder, OFF_SH - 2.5 * rock, e);
        self.offElbow = mathx.approach(self.offElbow, OFF_EL, e);
        self.bodyLean = mathx.approach(self.bodyLean, HUNCH + 1.5 * breathe + 4.0 * sigh + 7.5 * stalk, e);
        self.headPitch = mathx.approach(self.headPitch, HEAD_DROOP + 2.0 * breathe + 2.5 * rock + 5.0 * sigh - 7.0 * stalk, e);
        self.twist = mathx.approach(self.twist, 0, e * 8.0);
        // GRAVITY sets a hung club's angle, not posture: back out however far the trunk is stooping
        // (breath, sigh, and above all the stalk lean) so the rake — and with it the ground
        // clearance — stays put whether he's standing weary or pitched forward into a walk.
        self.clubTilt = mathx.approach(self.clubTilt, CARRY_TILT - (self.bodyLean - HUNCH) + 3.0 * rock, e * 8.0);
        self.clubAbd = mathx.approach(self.clubAbd, CLUB_ABD + 2.0 * breathe, e);
        self.legBrace = mathx.approach(self.legBrace, 0, e);
    }
    // Ease the carry channels toward a slack neutral while a stun/death owns the body — so an
    // interrupt mid-windup doesn't FREEZE the reared-back arm under the recoil.
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
        self.legBrace = mathx.approach(self.legBrace, 0, e);
    }
    fn setWindup(self: *Ogre, k: f32) void {
        // SEQUENCED, not lockstep: legs plant + trunk arch FIRST (kBody), the coil winds through
        // the middle (k), the club arm trails to the top LAST (kArm) — loading link by link.
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
        self.legBrace = lerpF(0, 0.55, kBody); // set the feet + sink into the load
    }
    fn setSlam(self: *Ogre, k: f32) void {
        // FIRE: the club LEADS (fast quad-out, overshooting the seat), the mass follows a beat
        // behind it, the coil releases, the wrist snaps the head through the arc.
        const kArm = 1.0 - (1.0 - k) * (1.0 - k); // fast out — the club leads
        self.clubShoulder = lerpF(OVER_SH, SLAM_SH + 6.0, kArm); // overshoots past the seat…
        self.clubElbow = lerpF(WIND_EL, SLAM_EL, kArm);
        self.offShoulder = lerpF(-74.0, 8.0, kArm);
        self.offElbow = lerpF(-44.0, -22.0, kArm);
        self.bodyLean = lerpF(-24.0, 44.0, k); // …the trunk drives through behind it
        self.headPitch = lerpF(-20.0, 24.0, kArm);
        self.twist = lerpF(-26.0, 12.0, kArm); // the coil releases through the strike
        self.clubTilt = lerpF(WIND_TILT, SLAM_TILT, kArm); // wrist whip — the head leads the haft at impact
        self.clubAbd = lerpF(WIND_ABD, SLAM_ABD, kArm); // …and comes down ON the facing line
        self.legBrace = lerpF(0.55, 0.95, k); // drive off the deeply-bent legs, sinking his weight in
    }
    fn setRecover(self: *Ogre, u: f32) void {
        // Spent + doubled over the buried club for most of it, gathering upright only at the end
        // (the big wide-open punish window). The impact JUDDER rings through the arm; heaving
        // breaths sell the exhaustion after.
        const spent = 1.0 - mathx.smoothstep(0.7, 1.0, u);
        const heave = 3.0 * mathx.sinf(self.elapsed * 7.0) * spent;
        const ring = self.judder * mathx.sinf(self.t * 44.0);
        self.clubShoulder = lerpF(CARRY_SH, SLAM_SH, spent) + heave * 0.4 + 6.5 * ring; // the club bounces, settles
        self.clubElbow = lerpF(CARRY_EL, SLAM_EL, spent) + 3.0 * ring;
        self.offShoulder = lerpF(OFF_SH, -8.0, spent);
        self.offElbow = lerpF(OFF_EL, -34.0, spent);
        self.bodyLean = lerpF(HUNCH, 46.0, spent) + 2.2 * ring;
        self.headPitch = lerpF(HEAD_DROOP, 34.0 + heave, spent);
        self.twist = lerpF(0, 6.0, spent); // still slung a touch through from the blow
        self.clubTilt = lerpF(CARRY_TILT, SLAM_TILT, spent) + 4.0 * ring;
        self.clubAbd = lerpF(CLUB_ABD, SLAM_ABD, spent); // still splayed over the planted club
        self.legBrace = lerpF(0, 1.0, spent); // splayed + buckled, bearing weight on the club
    }

    fn stunAmount(self: *const Ogre) f32 {
        if (self.state == .stunlight) {
            const u = mathx.clampF(self.t / combat.LIGHT_STUN_DUR, 0, 1);
            return mathx.sinf(u * std.math.pi);
        } else if (self.state == .stunheavy) {
            const u = mathx.clampF(self.t / combat.HEAVY_STUN_DUR, 0, 1);
            return mathx.smoothstep(0, 0.12, u) * (1.0 - mathx.smoothstep(0.78, 1.0, u));
        }
        return 0;
    }

    // ── pose: build the 18 bone matrices for this frame ─────────────────────────────────────
    pub fn pose(self: *Ogre) void {
        const fs = self.scale * (1.0 - 0.55 * self.fade);
        const sink = -0.95 * self.scale * self.fade; // the corpse sinks as it dissipates
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        // Death in TWO beats, not one smooth fold: the knees GIVE first (dk1 — the pelvis
        // drops, legs buckle), THEN the mass pitches forward and CRASHES (dk2), with a small
        // settle-bounce as it comes to rest. One curve read as "sinks over"; two read as falls.
        const du = if (dead) mathx.clampF(self.t / DEATH_DUR, 0, 1) else 0;
        const dk1 = mathx.smoothstep(0, 0.32, du);
        const dk2 = mathx.smoothstep(0.22, 0.62, du);
        const settle = mathx.smoothstep(0.62, 0.72, du) * (1.0 - mathx.smoothstep(0.72, 0.88, du)); // the bounce
        const stun = self.stunAmount();
        const light = self.state == .stunlight;
        const heavy = self.state == .stunheavy;
        const lstun: f32 = if (light) stun else 0;
        const hstun: f32 = if (heavy) stun else 0;

        // Shared humanoid walk bob + weight-sway on the pelvis (quieting on collapse), plus
        // the footfall CATCH — a sharp drop as each foot takes the mass, releasing fast.
        const m = self.moving * (1.0 - dk1);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const catchDip = -0.020 * H * self.jolt * m;
        const braceSink = -BRACE_SINK * self.legBrace; // he DROPS his weight into a slam (legPose folds to match)
        const sway = A_SWAY * mathx.sinf(twoPi * self.phase) * m +
            A_SWAY * self.latB * mathx.cosf(twoPi * self.phase) * m;

        // Idle LIFE (fades out as the walk takes over): a slow breathing bob + a heavy weight-
        // shift that rocks the pelvis foot to foot and rolls the torso — so it's never a statue.
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk1);
        const wshift = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28); // −1..1 weight phase
        const idleBob = A_BREATHE * mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 3.0) * idleAmt;
        const idleSway = A_IDLE_SWAY * wshift * idleAmt;

        var wx: [N]rl.Matrix = undefined;
        // Body pitch: base hunch/attack lean, a huge RECOIL back on a light flinch, a heavy
        // forward SAG on a stance-break, a nod into each footfall, and the death crash (dk2 +
        // the settle-bounce past flat and back).
        const leanX = self.bodyLean * (1.0 - dk2) - 40.0 * lstun + 34.0 * hstun + 2.2 * self.jolt * m + 84.0 * dk2 + 5.0 * settle;
        // The LUMBER: walking, the trunk rolls with the stride and the pelvis YAWS with it (the
        // swagger, offset off the roll so the two never peak together). poseUpper winds the
        // shoulder girdle back AGAINST both so the trunk articulates instead of riding rigid.
        const lumber = A_LUMBER * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase + 0.5) * m;
        const rollZ = 16.0 * dk2 + 9.0 * hstun + IDLE_ROLL * wshift * idleAmt + lumber + 1.5 * self.judder * mathx.sinf(self.t * 44.0);
        const drop = -0.24 * H * hstun; // pelvis sinks on the heavy stagger (toward a knee)
        const collapse = lerpF(hipY, 0.32 * H, dk1); // the knees give — the pelvis comes down on dk1
        const pelvY = (if (dead) collapse else hipY + bob + catchDip + idleBob + braceSink + drop) + sink;
        // The pelvis HEIGHT (and sway) must scale by `fs` too — the leg-offset children ride
        // through scaleM, so the pelvis world height must scale in lockstep or the legs sink at
        // SCALE≠1. The placement tr(pos) stays unscaled; scaleM FIRST → it scales about its pelvis.
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(rollZ), rx(leanX), ry(prot)),
            mul(tr((sway + idleSway) * fs, pelvY * fs, 0), ry(facingDeg)),
            tr(self.pos.x, 0, self.pos.z),
        ));

        // Legs. WALKING → the SHARED hero gait (alternating, independent — the owner's humanoid
        // rule). Otherwise (idle / mid-attack) → an independent weight-SHIFT (the free leg's knee
        // softens as weight rocks off it) plus a braced stance when loading a slam — so the legs
        // are never two frozen pillars. DEAD → the crumple in poseUpper owns them.
        if (!dead) {
            if (self.moving > 0.25) {
                heromod.legChain(&wx, self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, ANKL);
                heromod.legChain(&wx, self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, ANKR);
            } else {
                const leftFree = mathx.clampF(-wshift, 0, 1) * idleAmt; // left leg relaxes when weight rocks right
                const rightFree = mathx.clampF(wshift, 0, 1) * idleAmt;
                self.legPose(&wx, 1.0, leftFree, self.legBrace, HIPL, KNEEL, ANKL);
                self.legPose(&wx, -1.0, rightFree, self.legBrace, HIPR, KNEER, ANKR);
            }
        }
        self.poseUpper(&wx, dk1, dk2, lstun, hstun, dead, lumber, prot);
        self.xf = wx;
    }

    // One leg posed for the standing beats (idle / mid-attack), NOT the walk (legChain does that).
    // `free` 0→1 = how unweighted (knee softens, heel eases); `brace` 0→1 = slam load (both legs
    // sink + plant wider) — matches legChain's rest constants so the hand-off doesn't pop.
    fn legPose(self: *const Ogre, wx: *[N]rl.Matrix, side: f32, free: f32, brace: f32, hip: usize, knee: usize, ank: usize) void {
        const hipFlex = BRACE_HIP * brace + 5.0 * free;
        const kneeFlex = IDLE_KNEE + BRACE_KNEE * brace + 18.0 * free;
        const splay = STANCE_WIDEN * brace; // feet plant wider under the load
        setLocal(wx, hip, self.rest, mul(rx(-hipFlex), rz(-side * HIP_ADDUCT + side * splay)));
        setLocal(wx, knee, self.rest, rx(kneeFlex));
        // The ankle tracks the SHANK's angle under a brace so the sole stays flat on the ground —
        // a knee this deep with a token ankle angle stands the giant on his toes.
        const ankFlex = lerpF(hipFlex * 0.5, kneeFlex - hipFlex, brace) - 8.0 * free; // free heel eases up
        setLocal(wx, ank, self.rest, mul(rx(ankFlex), ry(side * FOOT_TOEOUT)));
    }

    // Spine, low head, arms + club, and (only DEAD or a HEAVY sag) the buckling legs; alive,
    // legChain owns the legs and this lays the body on top. Death is two-beat: `dk1` = knees give
    // (folds the spine), `dk2` = the forward crash (throws the arms + lolls the head).
    fn poseUpper(self: *Ogre, wx: *[N]rl.Matrix, dk1: f32, dk2: f32, lstun: f32, hstun: f32, dead: bool, lumber: f32, prot: f32) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk1);
        const armPh = std.math.tau * self.phase;
        // The trunk NODS twice a stride as the mass settles onto each planted foot, and the
        // footfall CATCH spikes it further — the sagittal life the trunk had none of.
        const nod = TRUNK_NOD * (0.5 - 0.5 * mathx.cosf(2.0 * armPh)) * m + 1.6 * self.jolt * m;
        // Curl the spine into the hunch; the stance-break folds it further, a flinch throws it
        // back. The torso WINDS about its axis through windup→slam (self.twist) — and WALKING,
        // the shoulder girdle COUNTER-ROTATES against the pelvis every stride and counter-rolls
        // its lumber. That counter-wind is most of why a walking trunk reads as a jointed spine
        // instead of one welded block (the pelvis alone yawing just swings the whole slab).
        const spineFlex = 6.0 + 26.0 * dk1 + 18.0 * hstun - 22.0 * lstun;
        setLocal(wx, SPINE, rest, mul3(rx(spineFlex * 0.5 + nod * 0.45), ry(self.twist * 0.4 - 0.45 * prot), rz(-0.30 * lumber)));
        setLocal(wx, CHEST, rest, mul3(rx(spineFlex * 0.4 + nod * 0.55), ry(self.twist * 0.6 - 0.75 * prot), rz(-0.45 * lumber)));
        // Head: hangs low + sad, scanning at idle, sighting on a windup, lolling on death/stagger;
        // walking it counter-rolls, counter-yaws AND counter-nods the heaving trunk, so the mass
        // pitches and swaggers under a skull whose eye stays on YOU (as a real head barely moves).
        setLocal(wx, NECK, rest, mul3(rx(self.headPitch * 0.35 + self.headLook * 0.3 + 8.0 * dk1 - 0.55 * nod), ry(0.55 * prot + 0.30 * self.headYaw), rz(-lumber * 0.5)));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.6 + self.headLook * 0.7 + 14.0 * dk2 + 16.0 * hstun - 26.0 * lstun - 0.45 * nod),
            ry(0.70 * self.headYaw + 0.65 * prot), // the crane is SHARED with the neck above (0.30 there)
            rz(-lumber * 0.35 + 18.0 * dk2),
        ));

        // Legs buckle under a full collapse (death, dk1 — the knees give FIRST) or a heavy
        // stance-break (drops toward a knee).
        const buckle = mathx.maxF(dk1, 0.7 * hstun);
        if (dead or hstun > 0.05) {
            setLocal(wx, HIPL, rest, mul(rx(-58.0 * buckle), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(6.0 + 104.0 * buckle));
            setLocal(wx, ANKL, rest, ry(6.0));
            setLocal(wx, HIPR, rest, mul(rx(-44.0 * buckle), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(6.0 + 88.0 * buckle));
            setLocal(wx, ANKR, rest, ry(-6.0));
        }

        // ── the ARMS: a real CONTRALATERAL swing, and every link arriving late by its own mass ──
        // Signs: −rx swings a shoulder FORWARD, so at phase 0 (that leg's heel strike, its thigh
        // forward) the same-side arm must go BACK. The free arm takes the big amplitude, the club
        // arm a short one CLUB_LAG behind the stride, and the club itself PEND_LAG behind that —
        // three staggered pendulums where there used to be one 4-degree twitch on both shoulders.
        const freeSwing = OFF_ARM_SWING * mathx.cosf(armPh) * m;
        const clubSwing = CLUB_ARM_SWING * mathx.cosf(armPh - CLUB_LAG) * m;
        // The club's own rock is ONE-SIDED — it only ever rakes FURTHER back, never toward the
        // grass: the carry angle already IS its lowest hang, so a symmetric pendulum would swing
        // the head straight through the dirt on every other step.
        const clubPend = CLUB_PEND * (0.5 - 0.5 * mathx.cosf(armPh - CLUB_LAG - PEND_LAG)) * m;
        // Elbows flex through the FORWARD half of each swing only (a trailing arm hangs straight
        // — the hero's rule), the club elbow barely giving at all, locked round its haft.
        const freeFlex = OFF_ELBOW_SWING * (0.5 - 0.5 * mathx.cosf(armPh - 0.5)) * m;
        const clubFlex = CLUB_ELBOW_SWING * (0.5 - 0.5 * mathx.cosf(armPh - CLUB_LAG - 0.5)) * m;
        // Off arm (left): rests low, flings out for balance on the windup, thrown up on a flinch.
        const armFly = -66.0 * lstun;
        setLocal(wx, SHL, rest, mul(rx(self.offShoulder + armFly * 0.6 - 18.0 * dk2 + freeSwing), rz(OFF_ABD + ARM_ABD_SWING * freeSwing)));
        setLocal(wx, ELL, rest, rx(self.offElbow - freeFlex));
        setLocal(wx, WRL, rest, rx(-WRIST_FLOP * freeSwing)); // the empty hand lags — dead weight
        // Club arm (right): the whole slam arc rides this shoulder + elbow; the flinch flings it up.
        setLocal(wx, SHR, rest, mul(rx(self.clubShoulder + armFly - 22.0 * dk2 - clubSwing), rz(-self.clubAbd - ARM_ABD_SWING * clubSwing)));
        setLocal(wx, ELR, rest, rx(self.clubElbow - clubFlex));
        setLocal(wx, WRR, rest, rl.math.matrixIdentity());
        // The club rides the wrist frame; clubTilt rakes it back for the carry and whips it
        // through the blow, clubPend rocks it on the walk (a fixed tilt read as welded-on), and
        // clubHold gives the fist back what the arm's swing took off the rake (the hover survives).
        // …and −nod cancels the trunk's stride flexion exactly (spine 0.45 + chest 0.55 = 1.0), the
        // same gravity argument as setCarry's lean back-out. It self-zeroes when he stops walking,
        // so the windup/slam — which DO want the club welded to the arm's arc — never feel it.
        const clubHold = CLUB_HOLD * mathx.maxF(0, clubSwing + clubFlex); // only pays back the DIPS
        setLocal(wx, CLUB, rest, rx(self.clubTilt + clubPend + clubHold - nod));
    }

    // ── telegraph FX (emit / integrate / draw) ──────────────────────────────────────────────
    // Where the crush burst goes: straight under the club's own head, not a guessed distance out
    // front — so retuning the club's length or its arc can never leave the dust in the wrong place.
    fn impactWorld(self: *const Ogre) rl.Vector3 {
        const low = self.clubLowWorld();
        return v3(low.x, 0.05, low.z);
    }
    fn emit(self: *Ogre, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        self.fx[self.fxHead] = .{ .p = p, .v = vel, .life = life, .max = life, .r0 = r0, .r1 = r1, .col = col, .grav = grav };
        self.fxHead = (self.fxHead + 1) % FX_MAX;
    }
    fn updateFx(self: *Ogre, dt: f32) void {
        for (&self.fx) |*q| {
            if (q.life <= 0) continue;
            q.life -= dt;
            q.p.x += q.v.x * dt;
            q.p.y += q.v.y * dt;
            q.p.z += q.v.z * dt;
            q.v.y -= q.grav * dt;
            if (q.p.y < 0) q.p.y = 0;
        }
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
            const side: f32 = if (self.phase < 0.5) 1.0 else -1.0; // which foot just landed
            const f = self.fdir();
            const rr = 0.13 * H * self.scale;
            const foot = v3(self.pos.x - f.z * side * rr, 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(foot, 6, 1.4, 0.14);
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
        for (&self.fx) |*q| {
            if (q.life <= 0) continue;
            const frac = mathx.clampF(q.life / q.max, 0, 1);
            const rad = lerpF(q.r1, q.r0, frac);
            const a = mathx.u8f(@as(f32, @floatFromInt(q.col.a)) * frac);
            rl.drawSphereEx(q.p, rad, 6, 8, mathx.withAlpha(q.col, a));
        }
    }

    pub fn draw(self: *const Ogre, model: *const Model) void {
        model.draw(&self.xf);
    }
};

// ── a lone ogre (a "Grief" — one sorrowful giant haunting the deep ruins). The Group shell
// mirrors the Knot/Line so game.zig iterates it generically; COUNT stays 1 for now (bump it
// and add homes to field more). ────────────────────────────────────────────────────────────
const COUNT = 1;
const Home = struct { x: f32, z: f32, yaw: f32, scale: f32, seed: f32 };
const homes = [COUNT]Home{
    // Deep down the avenue, past the toads + archers — the climax of the approach. Faces back
    // up the avenue (+Z) so the hero meets its eye as they close in.
    .{ .x = 3.0, .z = -50.0, .yaw = 0.0, .scale = 1.0, .seed = 0.4 },
};

pub const Grief = struct {
    model: Model,
    ogres: [COUNT]Ogre = undefined,

    pub fn init(shader: rl.Shader) Grief {
        var g = Grief{ .model = Model.init(shader) };
        g.reset();
        return g;
    }
    // Re-home the giant, alive and fresh (a hero death reloads the world, ER-style).
    pub fn reset(self: *Grief) void {
        for (homes, 0..) |h, i| self.ogres[i] = Ogre.spawn(mathx.ground(h.x, h.z), h.yaw, h.scale, h.seed);
    }
    pub fn setShader(self: *Grief, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    // Advance the group; returns the STRONGEST blow any ogre landed on the hero this frame.
    pub fn update(self: *Grief, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        var worst: ?combat.Hit = null;
        for (&self.ogres) |*o| {
            if (o.update(dt, hero, bounds, blade)) |h| {
                if (worst == null or h.dmg > worst.?.dmg) worst = h;
            }
        }
        return worst;
    }
    pub fn draw(self: *const Grief, scene: ?*gfx.Scene) void {
        for (&self.ogres) |*o| {
            if (!o.alive()) continue;
            if (scene) |sc| sc.setFlash(0.85 * o.flashFrac());
            o.draw(&self.model);
        }
        if (scene) |sc| sc.setFlash(0);
    }
    pub fn drawFx(self: *const Grief) void {
        for (&self.ogres) |*o| o.drawFx();
    }
    pub fn anyDied(self: *const Grief) bool {
        for (&self.ogres) |*o| {
            if (o.justDied) return true;
        }
        return false;
    }
    pub fn totalHits(self: *const Grief) u32 {
        var n: u32 = 0;
        for (&self.ogres) |*o| n += o.hits;
        return n;
    }
    pub fn aliveCount(self: *const Grief) u32 {
        var n: u32 = 0;
        for (&self.ogres) |*o| {
            if (o.alive()) n += 1;
        }
        return n;
    }
};

// ── bone meshes (authored at the joint origin, hero-local axes; lengths in units of H) ──────
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
    return mesh;
}

// A thick limb segment `a`→`e` that BULGES mid-length and swells into the far joint — same hide
// tone throughout so the body reads as one flesh, not a michelin stack of rings (the old fail).
fn limb(b: *Builder, a: rl.Vector3, e: rl.Vector3, r0: f32, r1: f32, col: rl.Color) void {
    const mid = mathx.lerpV(a, e, 0.42);
    b.addCylinder(a, mid, r0, r0 * 1.07, 9, col);
    b.addCylinder(mid, e, r0 * 1.07, r1, 9, col);
    b.addCylinder(v3(e.x, e.y + r1 * 0.45, e.z), v3(e.x, e.y - r1 * 0.45, e.z), r1 * 1.14, r1 * 1.14, 8, col);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // A ROUNDED hip mass (a barrel, not a crate) with real glutes behind and a slung groin.
    b.addCylinder(v3(0, 0.052 * H, 0.005 * H), v3(0, -0.048 * H, 0.01 * H), 0.145 * H, 0.155 * H, 10, HIDE);
    b.addCylinder(v3(0.068 * H, 0.005 * H, -0.055 * H), v3(0.062 * H, -0.03 * H, -0.125 * H), 0.082 * H, 0.045 * H, 9, HIDE); // L glute
    b.addCylinder(v3(-0.068 * H, 0.01 * H, -0.055 * H), v3(-0.062 * H, -0.025 * H, -0.118 * H), 0.078 * H, 0.042 * H, 9, HIDE); // R glute, a touch higher
    b.addCylinder(v3(0, -0.055 * H, 0.05 * H), v3(0, -0.095 * H, 0.055 * H), 0.085 * H, 0.05 * H, 9, BELLY); // low groin
    b.setMat(.leather);
    // a plaited rope belt cinched crooked round the hips — the rag hangs off it
    b.addCylinder(v3(0.10 * H, 0.048 * H, 0), v3(-0.10 * H, 0.058 * H, 0), 0.145 * H, 0.145 * H, 9, ROPE);
    b.setMat(.cloth);
    // the filthy loin-rag — TORN STRIPS of uneven length, front + back (pathos, not tailoring)
    b.addBox(v3(0.055 * H, -0.045 * H, 0.15 * H), v3(0.055 * H, 0, 0), v3(0.004 * H, -0.135 * H, 0.012 * H), v3(0, 0, 0.016 * H), RAG);
    b.addBox(v3(-0.065 * H, -0.03 * H, 0.145 * H), v3(0.045 * H, 0, 0), v3(-0.006 * H, -0.105 * H, 0.008 * H), v3(0, 0, 0.016 * H), RAG);
    b.addBox(v3(0.0, -0.04 * H, -0.14 * H), v3(0.12 * H, 0, 0), v3(0, -0.125 * H, -0.012 * H), v3(0, 0, 0.018 * H), RAG);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCylinder(v3(0, 0, 0), v3(0, 0.13 * H, 0), 0.15 * H, 0.19 * H, 10, HIDE); // thick waist widening to the chest
    b.addCylinder(v3(0, 0.01 * H, 0.05 * H), v3(0, 0.105 * H, 0.032 * H), 0.145 * H, 0.115 * H, 10, BELLY); // the sagging gut, slung forward
    b.addCylinder(v3(0, 0.002 * H, 0.05 * H), v3(0, -0.018 * H, 0.045 * H), 0.138 * H, 0.12 * H, 10, HIDE_DK); // the fold where the gut overhangs the belt
    b.addCube(v3(0, 0.045 * H, 0.162 * H), v3(0.045 * H, 0.016 * H, 0.02 * H), HIDE_DK); // navel crease
    return b.toMesh();
}

fn torsoMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // A barrel chest humped over the shoulders (the hunch) — ROUNDED masses throughout: a domed
    // hump kept below the nape so the jutting head stays clear, heavy pecs (club side bigger).
    b.addCylinder(v3(0, -0.02 * H, -0.01 * H), v3(0, 0.10 * H, -0.03 * H), 0.235 * H, 0.185 * H, 12, HIDE);
    b.addCylinder(v3(0, -0.045 * H, -0.095 * H), v3(0, 0.075 * H, -0.115 * H), 0.155 * H, 0.085 * H, 10, HIDE_DK); // the hump — a dome, not a box
    b.addCylinder(v3(0.065 * H, 0.045 * H, 0.10 * H), v3(0.058 * H, -0.035 * H, 0.135 * H), 0.088 * H, 0.055 * H, 9, HIDE); // L pec, sagging
    b.addCylinder(v3(-0.065 * H, 0.05 * H, 0.10 * H), v3(-0.06 * H, -0.04 * H, 0.14 * H), 0.095 * H, 0.06 * H, 9, HIDE); // R pec (club side) — heavier
    b.addCube(v3(0, -0.005 * H, 0.145 * H), v3(0.035 * H, 0.10 * H, 0.04 * H), BELLY); // sternum line between the pecs
    b.addCube(v3(0, -0.055 * H, 0.135 * H), v3(0.11 * H, 0.035 * H, 0.045 * H), SCAR); // old scar under the ribs
    // heavy shoulders SLOPING DOWN-AND-OUT (weary, not epaulettes) — the CLUB side carried
    // visibly higher + bigger (its working arm), the off side slumped (matches the rig skew)
    b.addCylinder(v3(0.155 * H, 0.04 * H, 0), v3(0.265 * H, -0.025 * H, 0), 0.10 * H, 0.072 * H, 9, HIDE); // L trapezius, slumped
    b.addCylinder(v3(-0.155 * H, 0.062 * H, 0), v3(-0.275 * H, 0.0, 0), 0.118 * H, 0.085 * H, 9, HIDE); // R trapezius (club arm), carried high
    // a scatter of warty lumps riding the SURFACE of the barrel (seeded — wabi-sabi)
    var rng = mathx.Rng.init(7321);
    var w: i32 = 0;
    while (w < 14) : (w += 1) {
        const a = rng.angle();
        const yy = rng.range(-0.03, 0.10) * H;
        const rr = (0.235 - (yy / H + 0.02) * 0.38) * H; // follow the barrel's taper — proud, not buried
        b.addCube(v3(mathx.cosf(a) * rr, yy, mathx.sinf(a) * rr * 0.82 - 0.02 * H), v3(rng.range(0.02, 0.045) * H, rng.range(0.015, 0.03) * H, rng.range(0.02, 0.045) * H), if (rng.float() < 0.5) HIDE_DK else HIDE_LT);
    }
    // an old broken SWORD BLADE left buried in the hump, rust bleeding down the hide —
    // someone hunted this giant long ago, and only wounded it (the Forsaken's history).
    b.setMat(.steel);
    b.addBox(v3(0.055 * H, 0.075 * H, -0.13 * H), v3(0.028 * H, 0.007 * H, 0.0), v3(-0.006 * H, 0.052 * H, -0.024 * H), v3(0, 0, 0.006 * H), CLUB_IRON);
    b.setMat(.skin);
    b.addCube(v3(0.055 * H, 0.01 * H, -0.153 * H), v3(0.022 * H, 0.055 * H, 0.008 * H), IRON_RUST); // the rust-bleed streak
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // A thick bull neck angled FORWARD along the jut (rest offset carries the head out front);
    // a heavy nape fold where it leaves the hump.
    b.addCylinder(v3(0, -0.01 * H, -0.01 * H), v3(0, 0.045 * H, 0.05 * H), 0.10 * H, 0.085 * H, 9, HIDE);
    b.addCube(v3(0, 0.01 * H, -0.055 * H), v3(0.11 * H, 0.05 * H, 0.045 * H), HIDE_DK); // nape fold
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // The sorrowful lamp: a low-browed head on the jutting neck — heavy asymmetric brow above
    // the eye, ONE self-lit amber eye pushed proud so it reads at range, sunken cheeks, a sagging
    // tusked underbite, drooped ears. Sad — and scary.
    b.addCylinder(v3(0, 0.02 * H, 0.005 * H), v3(0, 0.105 * H, -0.005 * H), 0.12 * H, 0.075 * H, 10, HIDE); // cranium
    b.addCube(v3(0, 0.03 * H, 0.03 * H), v3(0.125 * H, 0.075 * H, 0.115 * H), HIDE); // face block
    b.addCube(v3(0.01 * H, 0.09 * H, 0.02 * H), v3(0.05 * H, 0.02 * H, 0.09 * H), SCAR); // an old scalp scar across the dome
    // the great brow — one heavy bar, one end drooped lower than the other (the sad frown)
    b.addBox(v3(0, 0.076 * H, 0.088 * H), v3(0.078 * H, -0.007 * H, 0.0), v3(0.0, 0.024 * H, 0.006 * H), v3(0, 0, 0.030 * H), HIDE_DK);
    // ── the EYE — a deep wet rim, then the amber dome PROUD of the face (emissive) ──
    b.addCube(v3(0, 0.034 * H, 0.098 * H), v3(0.098 * H, 0.075 * H, 0.022 * H), EYE_RIM); // socket backing
    b.setMat(.plain); // glassy — no hide-material blotch over the glow
    b.addCylinder(v3(0, 0.034 * H, 0.100 * H), v3(0, 0.034 * H, 0.148 * H), 0.062 * H, 0.046 * H, 12, EYE); // the amber orb
    b.addCylinder(v3(0, 0.034 * H, 0.148 * H), v3(0, 0.034 * H, 0.160 * H), 0.046 * H, 0.020 * H, 12, EYE); // its rounded crown
    b.addCube(v3(0, 0.022 * H, 0.157 * H), v3(0.020 * H, 0.026 * H, 0.010 * H), PUPIL); // pupil set LOW — downcast
    b.setMat(.skin);
    b.addCube(v3(0, -0.012 * H, 0.112 * H), v3(0.096 * H, 0.020 * H, 0.026 * H), HIDE_DK); // the weary bag under it
    // squat nose + sunken cheeks
    b.addCube(v3(0.004 * H, -0.028 * H, 0.128 * H), v3(0.048 * H, 0.026 * H, 0.032 * H), HIDE_DK);
    b.addCube(v3(0.07 * H, -0.01 * H, 0.075 * H), v3(0.03 * H, 0.035 * H, 0.04 * H), HIDE_DK); // L cheek hollow
    b.addCube(v3(-0.07 * H, -0.015 * H, 0.075 * H), v3(0.03 * H, 0.04 * H, 0.04 * H), HIDE_DK); // R cheek hollow, deeper
    // the heavy sagging underbite + the DOWNTURNED mouth shadow above it
    b.addCube(v3(0, -0.058 * H, 0.085 * H), v3(0.105 * H, 0.032 * H, 0.085 * H), HIDE);
    b.addCube(v3(0, -0.041 * H, 0.122 * H), v3(0.062 * H, 0.010 * H, 0.014 * H), HIDE_DK); // mouth gap, centre
    b.addCube(v3(0.052 * H, -0.048 * H, 0.118 * H), v3(0.022 * H, 0.009 * H, 0.012 * H), HIDE_DK); // corner, slumped lower
    b.addCube(v3(-0.050 * H, -0.050 * H, 0.118 * H), v3(0.024 * H, 0.009 * H, 0.012 * H), HIDE_DK); // corner, slumped lower
    // drooped little ears, pinned back-and-down (a beaten dog's set)
    b.addBox(v3(0.128 * H, 0.005 * H, 0.0), v3(0.014 * H, 0.0, -0.020 * H), v3(0.014 * H, -0.052 * H, -0.012 * H), v3(0, 0, 0.032 * H), HIDE);
    b.addBox(v3(-0.128 * H, 0.012 * H, 0.0), v3(0.014 * H, 0.0, 0.020 * H), v3(-0.012 * H, -0.046 * H, -0.010 * H), v3(0, 0, 0.030 * H), HIDE);
    b.setMat(.stone);
    // two pale tusks jutting up from the underbite (uneven — one bigger, wabi-sabi)
    b.addCylinder(v3(0.048 * H, -0.045 * H, 0.135 * H), v3(0.056 * H, 0.018 * H, 0.148 * H), 0.017 * H, 0.004 * H, 6, TUSK);
    b.addCylinder(v3(-0.052 * H, -0.05 * H, 0.135 * H), v3(-0.062 * H, 0.042 * H, 0.150 * H), 0.020 * H, 0.005 * H, 6, TUSK_DK);
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.10 * H, 0.075 * H, HIDE); // massive thigh
    b.addCube(v3(0.055 * H, -0.11 * H, 0.05 * H), v3(0.05 * H, 0.045 * H, 0.03 * H), SCAR); // an old calloused gouge
    return b.toMesh();
}

fn shinMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_SHANK * H, 0), 0.072 * H, 0.055 * H, HIDE); // thick calf
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const ay = 0.039 * H;
    // A ROUND elephantine foot: a fat tapering pad from heel to toes + a domed ankle boss,
    // three stubby toe lobes out front (uneven), each capped with a blunt cracked nail.
    b.addCylinder(v3(0, -ay + 0.032 * H, -0.03 * H), v3(0, -ay + 0.026 * H, 0.115 * H), 0.068 * H, 0.055 * H, 9, HIDE); // the pad
    b.addCylinder(v3(0, -ay + 0.062 * H, -0.025 * H), v3(0, -ay + 0.012 * H, -0.032 * H), 0.058 * H, 0.066 * H, 9, HIDE_DK); // heel / ankle boss
    for ([_]f32{ -1, 0, 1 }) |t| { // toe lobes, middle one longest
        const tl: f32 = if (t == 0) 0.175 else 0.16;
        b.addCylinder(v3(t * 0.040 * H * side, -ay + 0.026 * H, 0.10 * H), v3(t * 0.048 * H * side, -ay + 0.020 * H, tl * H), 0.030 * H, 0.022 * H, 7, HIDE);
    }
    b.setMat(.stone);
    for ([_]f32{ -1, 0, 1 }) |t| { // blunt nails, one cracked shorter (wabi-sabi)
        const nl: f32 = if (t * side > 0.5) 0.012 else 0.018;
        const tz: f32 = if (t == 0) 0.178 else 0.163;
        b.addCube(v3(t * 0.048 * H * side, -ay + 0.024 * H, tz * H), v3(0.022 * H, 0.016 * H, nl * H), TUSK_DK);
    }
    return b.toMesh();
}

fn upperArmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.088 * H, 0.072 * H, HIDE); // heavy upper arm
    b.addCube(v3(-0.02 * H, -0.09 * H, 0.075 * H), v3(0.04 * H, 0.06 * H, 0.02 * H), SCAR); // old brand / callous
    return b.toMesh();
}

fn forearmMesh(seed: u64, corded: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_FOREARM * H, 0), 0.075 * H, 0.06 * H, HIDE); // thick forearm
    var rng = mathx.Rng.init(seed);
    b.addCube(v3(rng.range(-0.03, 0.03) * H, -rng.range(0.06, 0.12) * H, 0.055 * H), v3(0.035 * H, 0.03 * H, 0.02 * H), if (rng.float() < 0.5) SCAR else HIDE_DK); // a wart / old weal
    if (corded) { // the CLUB forearm: wound with old rope — the grip it never lets go of
        b.setMat(.leather);
        b.addCylinder(v3(0, -0.075 * H, 0), v3(0, -0.105 * H, 0), 0.075 * H, 0.073 * H, 8, ROPE);
        b.addCylinder(v3(0, -0.125 * H, 0), v3(0, -0.145 * H, 0), 0.070 * H, 0.068 * H, 8, ROPE);
    }
    return b.toMesh();
}

fn fistMesh(shackled: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCube(v3(0, -0.03 * H, 0.01 * H), v3(0.065 * H, 0.06 * H, 0.06 * H), HIDE); // big fist
    b.addCube(v3(0, -0.008 * H, 0.042 * H), v3(0.052 * H, 0.02 * H, 0.02 * H), HIDE_LT); // knuckle ridge
    b.setMat(.stone);
    // four blunt knuckle-nails
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |k| {
        b.addCube(v3(k * 0.028 * H, -0.02 * H, 0.062 * H), v3(0.014 * H, 0.02 * H, 0.016 * H), TUSK_DK);
    }
    if (shackled) {
        // the FORSAKEN's iron: a rusted manacle still riveted round the wrist, three links of
        // snapped chain swinging beneath — someone chained this giant, once, long ago.
        b.setMat(.steel);
        b.addCylinder(v3(0, 0.040 * H, 0.005 * H), v3(0, 0.012 * H, 0.005 * H), 0.062 * H, 0.060 * H, 8, CLUB_IRON);
        b.addCube(v3(0, 0.026 * H, 0.070 * H), v3(0.020 * H, 0.024 * H, 0.014 * H), IRON_RUST); // the rivet boss
        var li: i32 = 0;
        while (li < 3) : (li += 1) {
            const fi = @as(f32, @floatFromInt(li));
            b.addCube(
                v3(0.005 * H * fi, (-0.005 - 0.036 * fi) * H, (0.072 + 0.007 * fi) * H),
                v3(0.013 * H, 0.026 * H, 0.009 * H),
                if (li == 1) IRON_RUST else CLUB_IRON,
            );
        }
    }
    return b.toMesh();
}

// The great club — authored in the RIGHT-WRIST frame, gripped near the top of the haft and
// extending DOWN the arm line (−Y), so the raked carry trails it behind him and the swing rears
// it overhead. A gnarled bog-oak haft swelling into a knotted studded head; wabi-sabi, all uneven.
//
// LENGTH IS A HARD CONSTRAINT, not taste: a hanging fist sits ~0.38 H off the ground, so a club
// that hangs further than that CANNOT clear the grass at any believable rake — which is exactly
// how the old one ended up ploughing the dirt like a tripod leg. Everything below the grip
// therefore lives inside CLUB_DROP; the mass it lost in LENGTH went back in as WIDTH (a fatter,
// stubbier, more brutal head reads heavier anyway than a long pole ever did).
const CLUB_DROP = 0.42 * H; // grip → the club's LOWEST point. The clearance budget; nothing below it.
const CLUB_HEAD_R = 0.150 * H; // the drum's radius…
const CLUB_HEAD_HH = 0.098 * H; // …and half its height (wide and short, not long)
const gy = -0.03 * H; // grip centre in the wrist frame (at the fist)
const gz = 0.02 * H; // a touch out front of the palm
// The club's lowest authored point, in the wrist frame — ride it through xf[CLUB] and you get the
// business end in world space (see clubLowWorld). Two things read it: the ground-clearance check
// the CARRY exists to satisfy, and the slam's impact burst, which lands where the CLUB lands
// rather than at a guessed distance ahead (the dust used to burst ~2 m past the real crater).
const CLUB_LOW = v3(0, gy - CLUB_DROP - 0.014 * H, gz + 0.022 * H);
fn clubMesh() rl.Mesh {
    var b = Builder.init();
    const headY = gy - CLUB_DROP + CLUB_HEAD_HH; // drum UNDERSIDE lands exactly on the budget line
    const drumTop = headY + CLUB_HEAD_HH; // where the haft's flare has to meet the head
    b.setMat(.leather);
    b.addCylinder(v3(0, gy + 0.19 * H, gz), v3(0, gy + 0.11 * H, gz), 0.038 * H, 0.042 * H, 8, ROPE); // rope-bound butt, proud of the fist
    b.setMat(.wood);
    b.addCylinder(v3(0, gy + 0.11 * H, gz), v3(0, gy, gz), 0.042 * H, 0.048 * H, 8, CLUB_WOOD_LT); // the worn grip
    b.addCylinder(v3(0, gy, gz), v3(0, drumTop + 0.055 * H, gz + 0.010 * H), 0.052 * H, 0.070 * H, 8, CLUB_WOOD); // haft, gently bowed
    b.addCylinder(v3(0, drumTop + 0.055 * H, gz + 0.010 * H), v3(0, drumTop - 0.012 * H, gz + 0.022 * H), 0.070 * H, 0.104 * H, 8, CLUB_WOOD); // flare into the head
    b.setMat(.steel);
    b.addCylinder(v3(0, gy - 0.062 * H, gz + 0.005 * H), v3(0, gy - 0.086 * H, gz + 0.006 * H), 0.072 * H, 0.072 * H, 8, CLUB_IRON); // iron lashing band
    b.addCylinder(v3(0, drumTop + 0.022 * H, gz + 0.013 * H), v3(0, drumTop - 0.004 * H, gz + 0.015 * H), 0.092 * H, 0.094 * H, 8, IRON_RUST); // rusted band
    // the head: a fat knotted DRUM — wider than it is tall, so it reads heavy from any angle
    b.setMat(.stone);
    b.addCylinder(v3(0, headY + CLUB_HEAD_HH, gz + 0.022 * H), v3(0, headY - CLUB_HEAD_HH, gz + 0.022 * H), CLUB_HEAD_R, CLUB_HEAD_R * 0.96, 11, CLUB_STONE);
    b.addCube(v3(0, headY, gz + 0.022 * H), v3(0.166 * H, CLUB_HEAD_HH * 0.95, 0.166 * H), CLUB_STONE);
    // lashed-on stones, rusted iron lumps + DRIVEN SPIKES (seeded scatter — wabi-sabi). The stud
    // band is kept inside the head's own span so nothing juts below CLUB_DROP and re-breaks the hover.
    b.setMat(.steel);
    var rng = mathx.Rng.init(5119);
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const yy = headY + rng.range(-0.03, 0.085) * H; // banded round the drum, never slung under it
        const rr = CLUB_HEAD_R;
        const cx = mathx.cosf(a) * rr;
        const cz = gz + 0.022 * H + mathx.sinf(a) * rr;
        const sz = rng.range(0.034, 0.064) * H;
        const roll = rng.float();
        b.addCube(v3(cx, yy, cz), v3(sz, sz * rng.range(0.7, 1.25), sz), if (roll < 0.35) CLUB_IRON else if (roll < 0.5) IRON_RUST else CLUB_STONE);
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

// ── invariants under test (pure logic only) ──────────────────────────────────────────────
test "slam AI: too close crushes when ready, else looms; too far closes; out of aggro idles" {
    try std.testing.expectEqual(Choice.idle, classify(AGGRO_R + 1, true)); // disengaged
    try std.testing.expectEqual(Choice.slam, classify(SLAM_R - 0.5, true)); // in reach, ready
    try std.testing.expectEqual(Choice.wait, classify(SLAM_R - 0.5, false)); // in reach, cooling → loom
    try std.testing.expectEqual(Choice.approach, classify((SLAM_R + AGGRO_R) * 0.5, true)); // gap to close
}

test "range band is ordered and sits inside aggro" {
    try std.testing.expect(SLAM_R < AGGRO_R);
}

test "higher poise: a single hero light does NOT flinch the ogre (only sustained pressure does)" {
    var vit = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX);
    // One hero light (poise 10) vs the ogre's 30 poise → no reaction (it shrugs it off).
    try std.testing.expectEqual(combat.HitResult.none, vit.hit(heromod.ATK_LIGHT_HIT));
    // Three quick lights (no regen between) empty the 30 poise → the first flinch.
    _ = vit.hit(heromod.ATK_LIGHT_HIT);
    try std.testing.expectEqual(combat.HitResult.light, vit.hit(heromod.ATK_LIGHT_HIT));
}

test "slam crush is the club's LINE: hits ahead on the axis, clears the flanks + behind" {
    var front = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
    front.tryImpact(v3(0, 0, 3.0), SLAM_HIT); // dead ahead, in reach — under the falling club
    try std.testing.expect(front.heroHit != null);

    var beside = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    beside.tryImpact(v3(3.0, 0, 0.6), SLAM_HIT); // close, but well OFF the club's line — the
    try std.testing.expect(beside.heroHit == null); //   old half-disc fan wrongly crushed this

    var grazing = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    grazing.tryImpact(v3(1.0, 0, 3.0), SLAM_HIT); // ahead and only a stride off the line — clipped
    try std.testing.expect(grazing.heroHit != null);

    var behind = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.tryImpact(v3(0, 0, -3.0), SLAM_HIT); // same distance, behind
    try std.testing.expect(behind.heroHit == null);

    var far = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.tryImpact(v3(0, 0, 99), SLAM_HIT); // on the line but way out of reach
    try std.testing.expect(far.heroHit == null);
}
