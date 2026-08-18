const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");
const anim = @import("anim.zig");
const wf = @import("worldfmt.zig");
const elemfx = @import("elemfx.zig"); // the elements' particle LANGUAGE — the fire's palette is its, not ours
const shroommod = @import("shroom.zig"); // THE SPORELING — the same kingdom, and the cap it wears is ITS constant
const archermod = @import("archer.zig"); // THE POOL EVERYTHING THAT FLIES LIVES IN — the fireball included
const koboldmod = @import("kobold.zig"); // …only for the SLING SPEED this one is bracketed against, in tests

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

// THE MUSHROOM MAGE (owner's creature, owner's brief) — a cloaked fungal caster that throws SLOW, BOUNCING
// fireballs.
//
// **THE CAP IS THE HOOD.** That is the whole read and it is why this is not just a robed man: from behind it
// is a cowled figure like any other, and when it turns round the cowl is a mushroom, with a dark hollow of
// gills where a face should be. Authored as a hood WITH a mushroom under it there would be two silhouettes
// fighting; as one shape there is only the one, and it is a shape nothing else in the world has.
//
// **AND THE FIREBALL IS THE FIGHT.** Slow enough to walk out of the way of once, and it BOUNCES
// (`archer.bouncesOf`), so the ground it threatens is not one spot but a LINE of them running on away from
// the caster: measured, a ball aimed at 11 m touches at 11.9, 18.1 and 21.0 and rests at 22.4.
//
// **WHICH MEANS WHAT IT PUNISHES IS BACKING OFF**, and that is the whole reason the thing is slow. The
// obvious answer to a projectile you can see coming for a second and a half is to walk backwards out of it —
// and walking backwards is walking down the bounce line, so the arc you dodged is the one that catches you
// on the second touch. The answer it wants is sideways, or forwards into its face, where it has no melee at
// all. Nothing else in this game asks you to think about where a shot is going to be TWICE.

/// **SHORT AND SQUAT** — the necromancer's two dials with both signs flipped. That creature is the tall
/// gaunt caster and a second one of those is a reskin; this one is knee-high to it, wide, and low to the
/// ground, so a pair of casters on the same field are two silhouettes rather than two palettes. The STATURE
/// is the scale on the whole rig and the SQUAT is `restHumanoid`'s own `hx`/`sx`, which are the only two
/// numbers honestly per-creature on the shared scaffold.
pub const SCALE = (heromod.H - 0.32) / heromod.H;
const HIP_HALF = heromod.HIP_HALF * 1.26;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 1.14;
const H: f32 = heromod.H;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
/// The skull's slot, and on this creature the skull IS THE CAP.
const CAP = heromod.HEAD;
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
/// **THE HELD SLOT IS EMPTY AND THAT IS A DECISION.** A staff is the necromancer's and the wanderer's; this
/// one conjures BETWEEN ITS TWO HANDS, which is what makes the gather a thing you watch grow rather than a
/// glow on the end of a pole. Bone 17 is therefore never posed and never drawn — `Model.draw` walks `0..HELD`
/// for exactly that reason, and nothing reads `xf[HELD]`.
const HELD = heromod.HELD;

/// Its own boots, which are what `legChain` levels the ankle against — SHORT AND BROAD, because the whole
/// creature is. The archer's are a skeleton's long bare feet and would read as stilts under this hem.
const SOLES = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.045 * H, .toe = 0.180 * H, .halfW = 0.058 * H, .drop = 0.036 * H },
    .{ .bone = ANKR, .heel = 0.045 * H, .toe = 0.180 * H, .halfW = 0.058 * H, .drop = 0.036 * H },
};

// ── THE PALETTE ────────────────────────────────────────────────────────────────────────────────────────
//
// **AUTHOR DARK AND SOLVE IT** — the chain is albedo x 1.72 -> linear -> gamma 1/2.2, so screen goes as
// albedo^(1/2.2) and the bigger and smoother the mass the darker it has to start. The cloak is the biggest
// face on the creature, so it is the one that bites hardest.

/// THE CLOAK. Damp and GREEN-BLACK — the world outdoors is warm and a caster has to separate from the
/// bracken it stands in, but this one may not go blue-black: that is the necromancer's separation and two
/// dark robed things reading the same colour is two things you cannot tell apart at the range they are
/// fought from. Cold-green against his cold-blue.
///
/// **SOLVED OFF THE RENDER, NOT PICKED.** At (16,22,15) the cloak sampled 83 luma against ground at 102 —
/// only 0.81 of the field it stands in, which is the knight's "one more slab of the cliffs" a shade under
/// rather than a shade over. Wanted ~0.64 of it, and screen goes as albedo^(1/2.2), so the albedo factor is
/// 0.79^2.2 = 0.59 — hence these.
const CLOAK = rgba(10, 13, 9, 255);
const CLOAK_LT = rgba(15, 19, 13, 255);
/// The HEM, darker again: the biggest single face on it, and it is in its own shadow all day.
const HEM = rgba(6, 9, 6, 255);
/// The cord at the waist — the one warm note, the wanderer's sash trick.
const CORD = rgba(78, 62, 40, 255);

/// **THE CAP IS THE SPORELING'S, AND IT IS ITS CONSTANT AND NOT A COPY OF IT** (`shroom.CAP_COL`). These two
/// share a wood and a kingdom, and a player who has learned that a red-brown dome in the bracken is a
/// mushroom should read this one the same way before it moves — which is a claim that has to be STRUCTURAL,
/// because written out here as its own three literals it was already a shade off the thing it named.
const CAP_COL = shroommod.CAP_COL;
const CAP_DK = shroommod.CAP_DK;
/// The GILLS under the rim, which are the face — near-black, so what the eye finds under the cap is a hollow.
const GILL = rgba(14, 9, 8, 255);
/// …and the cream flecks, the sporeling's own again, faintly lit the same way (vertex alpha is the emissive
/// channel and LOWER is more self-lit): the same hint in the dark, on the same kingdom.
const WART = shroommod.WART;
/// The bare stalk-flesh of its hands and shins, pale and damp where everything else is dark.
const FLESH = rgba(58, 52, 42, 255);

/// **THE EYES, AND THEY ARE THE ONLY THING IN THE HOLLOW.** Set well back under the rim so the cap's own
/// shadow is what they are found in. Emissive — it is the one part of the creature that lights itself, and
/// after dark under a canopy it is the whole of what says a mage is standing there.
const EYE = rgba(232, 148, 62, 44);

/// THE FIRE IT MAKES — the ELEMENT'S own core, so the kindling in its hands, the ball in the air and the
/// burst on the ground are one substance. A caster with its own private orange is a caster whose spell does
/// not look like fire.
const FIRE_CORE = elemfx.sig(.fire).core;
const FIRE_EDGE = elemfx.sig(.fire).edge;

// ── THE NUMBERS ────────────────────────────────────────────────────────────────────────────────────────

pub const AGGRO_R: f32 = 22.0;
const TURN_RATE: f32 = 2.6; // rad/s — it is squat and unhurried, and being out-turned is part of the answer
const WALK_SPEED: f32 = heromod.WALK_SPEED * 0.80;

const BODY_R: f32 = 0.36;
/// **THE HURT SPHERE HAS TO HOLD THE CAP, NOT JUST THE BARREL** — the ravager's lesson one creature along.
/// The cap is the widest thing on this creature, it is what the reticle rides (`lockPoint`) and it is what
/// the player is aiming at; fitted to the body alone the sphere stopped at 1.45 m and the mark sat 1.35 m up
/// on its own rim, OUTSIDE anything a sword could reach — a reticle on a place you cannot hit. MEASURED off
/// the posed rig: the head bone is at 0.885·H, the dome's crown 0.17·H above that, so the pair is solved to
/// span the barrel's middle up past the mark and a test pins it.
const HURT_R: f32 = 0.62;
const CENTER_F: f32 = 0.66;
/// …and the CROWN is the top of the DOME, which is what a bar hangs over and what a flyer clears. Left at
/// the head bone's own height it sat inside the mushroom.
const TOP_F: f32 = 1.10;

const HP_MAX: f32 = 58.0;
/// **IT FLINCHES OFF ALMOST ANYTHING**, which is the whole counter to a caster: the answer to the fireball
/// is to be standing next to it, and standing next to it has to be worth something.
const POISE_MAX: f32 = 13.0;
const STANCE_MAX: f32 = 32.0;
/// FUNGAL FLESH, and **IT IS NOT KILLED BY ITS OWN ELEMENT.** The sporeling's sheet with the fire arm turned
/// round: a thing that throws fire and then dies to a fire arrow faster than to a sword is a joke at its own
/// expense. Chaos still goes straight through it, which is the kingdom's, and cold it barely notices.
const RESISTS = combat.resists(.{ .fire = 55, .cold = 20, .lightning = -20, .chaos = -45 });

pub const SOULS: u32 = 145;

const DEATH_DUR: f32 = 1.15;
const DISS_DUR: f32 = 1.0;
/// It sheds SPORE-DUST, not bone or chitin.
const DISSOLVE = foe.Dissolve{ .rate = 54.0, .spread = 0.8, .rise = 0.95, .flake = WART };
const NPART = 60;
const SHOVE_DECAY: f32 = 6.5;
const A_PROT: f32 = 3.2; // deg of pelvic transverse rotation — a short waddle turns less than a stride

// ── THE LOB ────────────────────────────────────────────────────────────────────────────────────────────

/// **THE GATHER IS THE LONGEST THING IT DOES, AND IT HAS TO BE.** What the player is reading is not the
/// throw — a slow ball is legible in the air by itself — it is WHICH WAY the thing is facing when it lets
/// go, because the bounce line is committed at the release and nothing steers it after. Well over
/// `foe.TELL_MIN`, and the fire kindling between its hands is what says so from across a field.
pub const LOB_WIND: f32 = 0.66;
const LOB_THROW: f32 = 0.16;
const LOB_RECOVER: f32 = 0.54;
const LOB_CD: f32 = 2.4;
/// Where in the throw the ball actually leaves — early, so the arm is still travelling when it goes. A
/// release at the end of the swing is a hand stopping and a ball appearing.
const RELEASE_K: f32 = 0.34;

/// **SLOW** (owner's word, and the whole design). Under the sling's 11 and well under a shaft's 15: the ball
/// has to be a thing you can watch, decide about, and walk away from — once.
pub const EMBER_SPEED: f32 = 8.0;
/// All of it BURNS, like the slinger's clump — so a fire resistance is a real answer to this creature, and
/// the poise is what makes eating one while you are mid-swing a mistake rather than a rounding error.
pub const EMBER_HIT = combat.Hit{ .poise = 12, .elem = combat.elems(.{ .fire = 16 }) };

/// The band it wants to fight in. It has NO melee at all, so being close is only ever a mistake it is
/// trying to correct — and the far end is short of `AGGRO_R` so it closes rather than plinking from the edge
/// of its own notice ring.
const LOB_MIN: f32 = 4.5;
const LOB_MAX: f32 = 16.0;
/// Inside this it stops casting and simply backs off: a caster that kept throwing with a sword in its face
/// is a caster the fight never has to move for.
const FLEE_R: f32 = 3.6;
const DRIFT_DUR: f32 = 0.75; // …and it re-decides on its own clock rather than steering every frame

comptime {
    // **NO ATTACK COMES OUT OF NOWHERE.**
    std.debug.assert(LOB_WIND >= foe.TELL_MIN);
    // …and the release is inside the throw it is a fraction of.
    std.debug.assert(RELEASE_K > 0 and RELEASE_K < 1.0);
    // The flee ring is inside the band, or the two rules fight and it jitters on the boundary.
    std.debug.assert(FLEE_R < LOB_MIN);
}

// ── THE POSE, AS KEYED TRACKS ──────────────────────────────────────────────────────────────────────────
//
// **AN ATTACK IS A SEQUENCE OF KEY POSES CHASED BY SPRINGS, NEVER TWO CONSTANTS AND A LERP.** The channels
// are flattened ROOT-most to TIP-most and the bank's falloff is what lags the hands behind the trunk, so
// the mass flows outward without any of these tracks saying a word about it.

const CHAN_N = 7;
const Chan = [CHAN_N]f32;
const CH_LEAN = 0;
const CH_TWIST = 1;
const CH_HEAD = 2;
const CH_SH = 3;
const CH_ABD = 4;
const CH_EL = 5;
const CH_CUP = 6;

/// The carry — what it stands in, and every key below says only what MOVES off it.
const CARRY_LEAN: f32 = 8.0;
const CARRY_HEAD: f32 = 5.0;
const CARRY_SH: f32 = 14.0;
const CARRY_ABD: f32 = 13.0;
const CARRY_EL: f32 = 44.0;

/// **BOTH ARMS ON ONE SET OF CHANNELS, BECAUSE THE CAST IS TWO-HANDED.** It cups the thing it is making, so
/// the two arms are one gesture and a left/right pair of every channel would be two numbers that have to be
/// kept equal by hand. The asymmetry that stops it reading as a machine is the instance's own seeded `wonk`
/// in `poseUpper`, which is where wabi-sabi belongs: BETWEEN the instances, not along one.
const P = struct {
    lean: f32 = CARRY_LEAN,
    twist: f32 = 0,
    head: f32 = CARRY_HEAD,
    sh: f32 = CARRY_SH,
    abd: f32 = CARRY_ABD,
    el: f32 = CARRY_EL,
    /// How much fire is cupped between the hands, 0..1 — a POSE channel and not a clock beside one, so the
    /// picture of the spell cannot promise a throw the mechanic is not making.
    cup: f32 = 0,

    pub fn chan(self: P) Chan {
        var c: Chan = undefined;
        c[CH_LEAN] = self.lean;
        c[CH_TWIST] = self.twist;
        c[CH_HEAD] = self.head;
        c[CH_SH] = self.sh;
        c[CH_ABD] = self.abd;
        c[CH_EL] = self.el;
        c[CH_CUP] = self.cup;
        return c;
    }
};

const PoseKey = anim.Pose(P).PoseKey;
const samplePose = anim.Pose(P).sample;

const SPRING_STIFF: f32 = 1500.0; // period ~0.16 s — inside the 0.16 s throw, so the snap survives the bank
const SPRING_ZETA: f32 = 0.70; // under 1: every pose it takes carries past its rest and settles back onto it
const SPRING_FALLOFF: f32 = 0.93;

/// **IT HUNCHES OVER WHAT IT IS MAKING.** The gather folds the whole creature down around its own hands —
/// which is what gives the throw somewhere to uncoil FROM — and the fire comes up under it on a curve that
/// spends most of itself late, so the last third of the tell is the loudest part of it.
/// **THE HEAD BARELY MOVES, AND THAT IS BECAUSE OF THE CAP.** Authored as a proper bow over its own hands
/// (`head` 18-21) the brim — half a metre of it — came down across the chest and hid the hollow, the eyes and
/// the fire the pose exists to show. On a creature whose head is a parasol a GLANCE is worth what a bow is
/// worth on anything else, so the gather leans at the WAIST and only nods at the neck.
///
/// …and the hands go OUT IN FRONT rather than up under the chin, for the same reason: a ball cupped against
/// the chest is a ball drawn inside the cap's own shadow.
const WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{} },
    .{ .t = 0.38, .p = .{ .lean = 15.0, .head = 7.0, .sh = 38.0, .abd = 10.0, .el = 70.0, .cup = 0.30 }, .ease = .accel },
    .{ .t = 0.78, .p = .{ .lean = 21.0, .head = 10.0, .sh = 50.0, .abd = 12.5, .el = 80.0, .cup = 0.88 }, .ease = .decel },
    // …and it SETTLES on the loaded pose rather than arriving at it, which is the frame you throw off.
    .{ .t = 1.00, .p = .{ .lean = 18.0, .head = 8.5, .sh = 46.0, .abd = 11.0, .el = 77.0, .cup = 1.0 } },
};

/// THE THROW — a LOB, so the arms go up and over rather than out: the hands finish above the cap. `snap` on
/// the first key is most of the travel in the first fifth, which is what a throw is.
const THROW_KEYS = [_]PoseKey{
    // **THE SEAM IS THE WIND'S OWN END POSE** — a test pins the two, because a stroke authored as two
    // functions that happen to line up is a stroke that pops on the frame it crosses.
    .{ .t = 0.00, .p = .{ .lean = 18.0, .head = 8.5, .sh = 46.0, .abd = 11.0, .el = 77.0, .cup = 1.0 } },
    .{ .t = 0.34, .p = .{ .lean = -5.0, .head = -4.0, .sh = 116.0, .abd = 19.0, .el = 24.0, .cup = 0.30 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = -10.0, .head = -9.0, .sh = 132.0, .abd = 24.0, .el = 13.0, .cup = 0 } },
};

/// …and the recovery is only the walk back to the carry. **THE OVERSHOOT IS THE BANK'S, NOT THIS TRACK'S**
/// — hand-authored here it would be a second, disagreeing copy of what the springs already do for free.
/// **THE POSE IT STANDS IN**, named once. Written out as a one-key track at the three states that simply
/// hold it, `P{}`'s own defaults were being run back through the sampler to get a value the struct already
/// had — three copies of "nothing is happening", and three places to forget when a carry channel moves.
const CARRY: Chan = (P{}).chan();

const RECOVER_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -10.0, .head = -9.0, .sh = 132.0, .abd = 24.0, .el = 13.0, .cup = 0 } },
    .{ .t = 1.00, .p = .{}, .ease = .decel },
};

const State = enum { idle, drift, lob_wind, lob_throw, recover, stunlight, stunheavy, dead };

/// Pure, so it is testable without a world (the knight's rule — a decision function whose only varying
/// inputs are numbers is a decision a test can pin).
const Choice = enum { hold, back, lob, keep };
fn classify(dist: f32, lobReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist < FLEE_R) return .back; // it has no melee: close is a mistake, and the only answer is feet
    if (lobReady and dist >= LOB_MIN and dist <= LOB_MAX) return .lob;
    return .keep;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    cloak: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "mushroom mage");
        return .{ .bone = buildBones(), .cloak = cloakMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Mage) void {
        // **`0..HELD`, NOT `0..N`** — bone 17 is the weapon slot and this creature carries nothing, so it
        // was never built and never posed. Walked to `N` the draw hands raylib an undefined mesh.
        for (0..HELD) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        rl.drawMesh(self.cloak, self.mat, k.cloakXf());
    }
};

pub const Mage = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    /// ITS EYES ON HIM (`foe.Leash`) — embedded by the creature, stamped by the game.
    leash: foe.Leash = .{},
    /// The wand's roots and the rime's cold, both stamped from outside and both billed through `foe.grip`.
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    /// …and THE HERO'S SHIELD (`game.markParry`). Declared because the contract's fold keys off the FIELD,
    /// and read by `parryable` alone: **the lob is not parryable and that is a decision** — there is nothing
    /// to catch in a thrown ball, and boards that batted one aside would be the answer to the whole creature.
    parry: foe.Parry = .{},
    /// WHO IT IS FIGHTING, and THE WAY ROUND WHAT IS IN THE WAY.
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    lobCd: f32 = 0,
    /// **A FIREBALL LEFT ITS HANDS THIS FRAME** — a one-frame edge (`justDied`'s law), reset at the TOP of
    /// `update` and read by the game after it, because the pool the ball flies in belongs to nobody here.
    /// Latched inside the throw so a long frame cannot fire two and a short one cannot miss it.
    lobbed: bool = false,
    lobFrom: rl.Vector3 = mathx.zero3,
    /// …and the voices' own edges, cleared with it. The creature says WHEN; `game.zig` owns the speaker, or
    /// a creature would play through the pause card and the shot harness.
    kindled: bool = false,
    yelped: bool = false,

    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,

    // posture channels (degrees, and `cup` a fraction) — written by the state and settled by the bank
    bodyLean: f32 = CARRY_LEAN,
    twist: f32 = 0,
    headPitch: f32 = CARRY_HEAD,
    armSh: f32 = CARRY_SH,
    armAbd: f32 = CARRY_ABD,
    armEl: f32 = CARRY_EL,
    cup: f32 = 0,
    springs: anim.SpringBank(CHAN_N) = .{},

    /// THE CLOAK'S OWN LEAN, and its velocity — a spring, because cloth that eases to a stop glides and
    /// cloth that overshoots and settles has weight (the reactions law).
    cloakLean: f32 = 0,
    cloakVel: f32 = 0,

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

    xf: [N]rl.Matrix = undefined,
    cloakMat: rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Mage {
        var k = Mage{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 44927.0, 0x2C1);
        k.lobCd = 0.5 + seed * 1.4; // stagger a ring of them so they do not throw in lockstep
        // **SEAT THE SPRINGS AT SPAWN.** A bank comes up at 0 and 0 is a real pose — arms straight down, no
        // lean, no cup. Drawn before it settled the thing stood there like a dropped coat.
        k.springs.seat(CARRY);
        k.chanSet(CARRY);
        k.pose();
        return k;
    }

    pub fn kind(_: *const Mage) wf.FoeKind {
        return .mushroom_mage;
    }

    pub fn centerWorld(self: *const Mage) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn topWorld(self: *const Mage) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    /// THE MARK RIDES THE CAP — the part of it you are watching anyway, and it dips when the cap dips.
    pub fn lockPoint(self: *const Mage) rl.Vector3 {
        return foe.markOn(self.xf[CAP], v3(0, 0.03 * H, 0));
    }
    pub fn hurtRadius(self: *const Mage) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Mage) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Mage) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Mage) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Mage) bool {
        return switch (self.state) {
            .stunlight, .stunheavy, .dead => true,
            else => false,
        };
    }
    /// It never leaves the ground: it has no leap and no hop, and the roots hold it unconditionally.
    pub fn airborne(_: *const Mage) bool {
        return false;
    }
    pub fn flashFrac(self: *const Mage) f32 {
        return foe.flashFrac(self.flash);
    }

    /// **WHERE THE BALL IS MADE AND WHERE IT LEAVES FROM** — the midpoint of the two wrists, pushed a little
    /// forward of them. ONE definition, because the picture (`drawCup`) and the launch both need it, and as
    /// two copies the fire would kindle somewhere the ball did not come out of.
    pub fn cupWorld(self: *const Mage) rl.Vector3 {
        const l = foe.markOn(self.xf[WRL], v3(0, -0.02 * H, 0.05 * H));
        const r = foe.markOn(self.xf[WRR], v3(0, -0.02 * H, 0.05 * H));
        return mathx.lerpV(l, r, 0.5);
    }

    /// **HOW MUCH FIRE IS IN ITS HANDS**, 0..1 — the settled channel and not the raw track, so the picture
    /// is the one the springs actually put there.
    pub fn cupAmt(self: *const Mage) f32 {
        return mathx.clampF(self.cup, 0, 1);
    }

    /// **NOTHING IT DOES IS PARRYABLE, AND THAT IS A DECISION** — written down rather than omitted, because
    /// a creature with no windows looks like a creature nobody got round to (`necro.parryable`'s note). There
    /// is no edge in a thrown ball to catch; its counter is your feet on the first arc and the bounce line on
    /// the second, and the answer to the creature itself is closing the distance.
    fn parryable(_: *const Mage) ?f32 {
        return null;
    }

    fn fdir(self: *const Mage) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Mage, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    /// WHERE IT IS TRYING TO WALK (`game.markWay`) — **ONLY THE DRIFT.** A heading bent under a committed
    /// throw aims the whole bounce line at a wall.
    pub fn navWant(self: *const Mage, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    fn chanGet(self: *const Mage) Chan {
        var c: Chan = undefined;
        c[CH_LEAN] = self.bodyLean;
        c[CH_TWIST] = self.twist;
        c[CH_HEAD] = self.headPitch;
        c[CH_SH] = self.armSh;
        c[CH_ABD] = self.armAbd;
        c[CH_EL] = self.armEl;
        c[CH_CUP] = self.cup;
        return c;
    }
    fn chanSet(self: *Mage, c: Chan) void {
        self.bodyLean = c[CH_LEAN];
        self.twist = c[CH_TWIST];
        self.headPitch = c[CH_HEAD];
        self.armSh = c[CH_SH];
        self.armAbd = c[CH_ABD];
        self.armEl = c[CH_EL];
        self.cup = c[CH_CUP];
    }

    /// THE FRAME'S TARGET POSE, chased by the bank — written by whatever the state machine decided and then
    /// settled ONCE, at the end of `update`, so no move can forget to be continuous. This is what makes a
    /// stagger arriving mid-throw a continuous thing for free.
    fn settlePose(self: *Mage, dt: f32) void {
        var want = self.chanGet();
        self.springs.chase(&want, SPRING_STIFF, SPRING_ZETA, SPRING_FALLOFF, dt);
        self.chanSet(want);
    }

    fn enter(self: *Mage, s: State) void {
        self.state = s;
        self.t = 0;
    }

    /// ONE FRAME. Returns the blow it landed on whoever it is fighting, or null — **and it is ALWAYS null**,
    /// because everything this creature does to you arrives as a ball out of `archer`'s pool, minutes of
    /// flight-time after its hands are empty. The signature is the shared one (`foe.groupBlow`) all the same:
    /// a group that answered a different shape would be a group nothing could fold over.
    pub fn update(self: *Mage, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        // **CLEARED BEFORE THE `gone` BRANCH, NOT AFTER IT** (the necromancer's, and `justDied`'s own law).
        // They come out false today only because `foe.dissipate` happens to set `gone` on a frame that had
        // already reset them — an ordering nothing states and nothing enforces, and the one it would catch is
        // a body that left the field mid-throw holding `lobbed` true forever.
        self.justDied = false;
        self.lobbed = false;
        self.kindled = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        // AFTER THE POSE, so the swept test meets the body where it is drawn this frame rather than where it
        // stood last.
        self.tryHit(blade);
        return null;
    }

    fn stateStep(self: *Mage, dt: f32, hero: rl.Vector3, bounds: f32) void {
        // THE ROOTS HAVE THE FEET (`foe.grip`) — it never leaves the ground, so the hold is unconditional.
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.lobCd = mathx.maxF(0, self.lobCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.chanSet(CARRY);
                if (self.t >= 0.18) self.decide(d);
            },
            .drift => {
                // IT WALKS WATCHING HIM — the eyes stay on the hero and the feet go where they are told,
                // which is `Nav.along`'s whole reason for existing beside `aim`.
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = WALK_SPEED;
                const moved = moveSpeed * dt * self.chill.travel();
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.chanSet(CARRY);
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= DRIFT_DUR) self.decide(d);
            },
            .lob_wind => {
                // IT AIMS THROUGH THE GATHER AND NOT AFTER IT: the ball's whole line is committed at the
                // release, so the turn has to be spent where the player can see it being spent.
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / LOB_WIND, 0, 1);
                self.chanSet(samplePose(&WIND_KEYS, u));
                self.kindle(dt, u);
                if (self.t >= LOB_WIND) self.enter(.lob_throw);
            },
            .lob_throw => {
                // **THE LINE IS COMMITTED AT THE THROW** (the delver's law, the knight's charge's). It may
                // still turn a little into the release and not at all after it.
                if (self.t < LOB_THROW * RELEASE_K) self.faceToward(hero, dt * 0.35);
                const u = mathx.clampF(self.t / LOB_THROW, 0, 1);
                self.chanSet(samplePose(&THROW_KEYS, u));
                // THE RELEASE IS AN EDGE, caught by the clock CROSSING it — a long frame cannot fire it
                // twice and a short one cannot miss it (`hero.updateShot`'s rule).
                const at = LOB_THROW * RELEASE_K;
                if (self.t - dt < at and self.t >= at) {
                    self.lobbed = true;
                    self.lobFrom = self.cupWorld();
                    self.burstCup();
                }
                if (self.t >= LOB_THROW) {
                    self.lobCd = LOB_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                if (d <= AGGRO_R) self.faceToward(hero, dt * 0.6);
                self.chanSet(samplePose(&RECOVER_KEYS, mathx.clampF(self.t / LOB_RECOVER, 0, 1)));
                if (self.t >= LOB_RECOVER) self.enter(.idle);
            },
            .stunlight, .stunheavy => {
                self.chanSet(CARRY);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .dead => {
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        // **THE CLOAK OPPOSES THE TRAVEL AND THEN OVERSHOOTS ITS REST** — a mass in motion settles back onto
        // its rest, and cloth that glides to a stop is what reads as weightless.
        const wantLean = -CLOAK_DRAG * mathx.clampF(moveSpeed / WALK_SPEED, 0, 1) * self.fwdB;
        self.cloakVel += (CLOAK_STIFF * (wantLean - self.cloakLean) - CLOAK_DAMP * self.cloakVel) * dt;
        self.cloakLean += self.cloakVel * dt;
        self.settlePose(dt);
        self.pose();
    }

    /// WHAT IT DOES NEXT. The pick is `classify`'s and the plumbing is here, so the decision can be pinned
    /// by a test without a world anywhere near it.
    /// **IT MOVES OFF ITS OWN BEARING, NEVER OFF HIS POSITION** (the necromancer's `decide`, and the reason
    /// it holds): every branch above this one has already spent the frame facing him, so `fdir()` IS "toward
    /// the hero" — and asked that way the creature never reaches out for a body it is not allowed to know
    /// about. Which way it circles is its own, and it is SEEDED: a ring of them must not drift as one body.
    fn decide(self: *Mage, dist: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.drift);
        }
        self.homing = false;
        const f = self.fdir();
        const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
        const lat = mathx.scaleV(mathx.perpXZ(f), side);
        switch (classify(dist, self.lobCd <= 0)) {
            .lob => {
                self.kindled = true; // ON THE GATHER: the fire is the tell, and it leads the ball
                self.enter(.lob_wind);
            },
            // TOO CLOSE — straight back and a little across, because backing off down his own line is
            // backing off in a straight run he simply walks up.
            .back => {
                self.moveDir = mathx.normV(mathx.addV(mathx.scaleV(f, -1.0), mathx.scaleV(lat, 0.55)));
                self.enter(.drift);
            },
            // …too far, or nothing to spend: it walks to where it wants to be standing, which is its own
            // band rather than his face, and it sidles while it waits.
            .keep => {
                self.moveDir = if (dist > LOB_MAX)
                    mathx.normV(mathx.addV(f, mathx.scaleV(lat, 0.4)))
                else
                    lat;
                self.enter(.drift);
            },
            .hold => {
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, self.home);
                    self.enter(.drift);
                } else self.enter(.idle);
            },
        }
    }

    /// THE FIRE COMING UP BETWEEN ITS HANDS, thickening as the gather runs. Off the ELEMENT'S own verb, so
    /// this is the same fire the ball and the burst are made of.
    fn kindle(self: *Mage, dt: f32, u: f32) void {
        const rate = lerpF(KINDLE_RATE_0, KINDLE_RATE_1, u * u);
        self.fxAccum += rate * dt;
        const n: usize = @intFromFloat(@floor(self.fxAccum));
        if (n == 0) return;
        self.fxAccum -= @floatFromInt(n);
        elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, self.cupWorld(), .fire, @min(n, KINDLE_CAP), BALL_R * (0.4 + 0.6 * u) * self.scale, self.scale);
    }

    /// …and the puff off the release, thrown down the line the ball just went.
    fn burstCup(self: *Mage) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, self.cupWorld(), self.fdir(), .fire, THROW_PUFF, self.scale);
    }

    /// A BLOW LANDING ON IT. **TWO SHARED CALLS AND THEN WHAT IS MINE.**
    pub fn tryHit(self: *Mage, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SHOVE);
        self.puff(s.contact, if (heavy) 9 else 4);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Mage, heavy: bool) void {
        self.enter(if (heavy) .stunheavy else .stunlight);
        self.yelped = true;
        // **AND WHATEVER WAS IN ITS HANDS GOES OUT.** Left standing, an interrupted mage keeps a fireball
        // cupped in its fists through the whole flinch and the player who earned the interrupt cannot tell
        // it worked. The channel is the picture and the picture has to agree with the mechanic.
        self.cup = 0;
    }

    fn enterDeath(self: *Mage) void {
        if (self.state == .dead) return;
        self.enter(.dead);
        self.cup = 0;
        self.justDied = true;
    }

    pub fn debugStagger(self: *Mage, heavy: bool) void {
        self.enterStun(heavy);
    }

    /// Stage the GATHER, for the harness and for the measurement — a pose and nothing else: no ball, no
    /// cooldown spent (`wolf.stagePounce`'s pattern). `u` is how far through the tell.
    pub fn stageGather(self: *Mage, u: f32) void {
        self.state = .lob_wind;
        self.t = mathx.clampF(u, 0, 1) * LOB_WIND;
        const want = samplePose(&WIND_KEYS, mathx.clampF(u, 0, 1));
        self.springs.seat(want); // …AT the pose, not chasing it: a still frame cannot show a spring settling
        self.chanSet(want);
        self.pose();
    }

    fn puff(self: *Mage, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        const total = foe.hitParts(n);
        while (i < total) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.5);
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                at,
                v3(mathx.cosf(a) * sp, self.fxRng.range(0.4, 1.7), mathx.sinf(a) * sp),
                self.fxRng.range(0.28, 0.58),
                self.fxRng.range(0.020, 0.044) * self.scale,
                0.004,
                if (self.fxRng.float() < 0.5) WART else CAP_DK,
                1.4, // spore dust HANGS: it is not a spark and it is not blood
            );
        }
    }

    pub fn cloakXf(self: *const Mage) rl.Matrix {
        return self.cloakMat;
    }

    fn stunAmount(self: *const Mage) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn pose(self: *Mage) void {
        const fs = self.scale * (1.0 - 0.62 * self.fade);
        const sink = -0.42 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();

        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.16 * H, dk);
        // NO PITCH AT THE ROOT while it is standing (the wanderer's law and the hero's): a root pitch turns
        // the LEGS and levers a planted foot through the floor. The whole lean is spine and chest below.
        // **A SCALE≠1 HUMANOID MUST SCALE ITS PELVIS HEIGHT** or the legs sink and it reads as a crouch.
        const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(11.0 * dk), rx(20.0 * dk), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, SOLES[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, SOLES[1]);
        }
        self.poseUpper(&wx, dk, stun, dead, pel.prot);
        self.xf = wx;
        self.chainCloak();
    }

    /// **THE UPPER BODY ARTICULATES TOO — LEGS ALONE ARE NOT A GAIT.** The girdle counter-rotates against
    /// the pelvis, the trunk nods twice a stride, and the CAP counter-rolls the lot — **with the lags
    /// staggered**, or every joint peaks on one frame and the whole thing reads as one welded block.
    fn poseUpper(self: *Mage, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        // Seeded wonk — each stands a little crooked and each cap sits a little askew. WABI-SABI BETWEEN the
        // instances, which is also what breaks the two-handed cast's own symmetry.
        const wonk = (self.seed - 0.5) * 6.5;
        // It BREATHES, unlike the dead things: a slow swell on two rates that never line up, so the loop
        // never shows. Damped right down while it is moving, where the gait owns the body.
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const swayArg = self.elapsed * (0.55 + 0.22 * (0.5 + 0.5 * mathx.sinf(self.seed * 31.7))) + self.seed * 6.28;
        const swy = mathx.sinf(swayArg) * idleAmt;
        const swyLag = mathx.sinf(swayArg - 0.85) * idleAmt;

        const nod = 1.8 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const lean = self.bodyLean - 22.0 * stun + 26.0 * dk;
        setLocal(wx, SPINE, rest, mul3(
            rx(lean * 0.42 + nod + 0.8 * swy),
            ry(-0.35 * prot + self.twist * 0.4),
            rz(wonk * 0.5 + 1.1 * swy),
        ));
        setLocal(wx, CHEST, rest, mul3(
            rx(lean * 0.58 + nod * 0.6 + 0.6 * swyLag),
            ry(-0.5 * prot + self.twist * 0.6),
            rz(-wonk * 0.3 - 0.8 * swyLag),
        ));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.30 + 9.0 * dk - 6.0 * stun));
        // …AND THE CAP COUNTER-ROLLS ALL OF IT. It is the widest thing on the creature, so a degree here is
        // worth three anywhere else — which is exactly why it is the joint the eye reads the body off.
        setLocal(wx, CAP, rest, mul3(
            rx(self.headPitch * 0.70 + 17.0 * dk - 30.0 * stun),
            ry(-0.5 * prot),
            rz(wonk * 1.4 - 1.3 * swyLag - 0.9 * nod),
        ));

        if (dead) heromod.deadLegs(wx, rest, dk);

        // **BOTH ARMS OFF ONE SET OF CHANNELS, MIRRORED, AND THEN BROKEN.** The cast is one two-handed
        // gesture, so the channels are shared; `wonk` is what stops the pair being a machine, and it is
        // applied with OPPOSITE sign either side so the difference is between the hands rather than a lean
        // on both. The contralateral swing is the walk's and dies away the moment the arms have a job.
        const armStun = -58.0 * stun;
        const busy = mathx.clampF(self.cup + mathx.smoothstep(CARRY_SH, CARRY_SH + 30.0, self.armSh), 0, 1);
        const swing = 13.0 * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) * (1.0 - busy);
        const fwdHalf = mathx.maxF(0, mathx.sinf(twoPi * self.phase)) * m * (1.0 - busy);
        inline for (.{ .{ SHL, ELL, WRL, @as(f32, 1.0) }, .{ SHR, ELR, WRR, @as(f32, -1.0) } }) |arm| {
            const sh = arm[0];
            const el = arm[1];
            const wr = arm[2];
            const side: f32 = arm[3];
            const flex = self.armSh + side * swing + armStun - 26.0 * dk + 1.7 * swyLag + wonk * 0.35 * side;
            setLocal(wx, sh, rest, mul(rx(-flex), rz(side * (self.armAbd + wonk * 0.5 * side))));
            setLocal(wx, el, rest, rx(-(self.armEl - 12.0 * fwdHalf * side + wonk * 0.8 * side)));
            // The wrists turn the palms UP and IN, which is what makes a pair of hands a CUP rather than two
            // hands that happen to be near each other.
            setLocal(wx, wr, rest, mul(rz(side * -22.0 * self.cupAmt()), rx(-14.0 * self.cupAmt())));
        }
    }

    fn chainCloak(self: *Mage) void {
        const swayLag = CLOAK_SWAY * mathx.sinf(std.math.tau * self.phase - 0.85) * self.moving;
        self.cloakMat = mul(mul(rx(self.cloakLean), rz(swayLag)), self.xf[ROOT]);
    }

    pub fn draw(self: *const Mage, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    /// The unlit pass — the fire in its hands and the spore dust. Drawn here rather than baked into the mesh
    /// for the leechfly's reason: vertex alpha is a FIXED emissive channel and cannot brighten, and
    /// brightening from nothing to a held ball is the whole cue.
    pub fn drawFx(self: *const Mage) void {
        self.drawCup();
        foe.drawParticles(&self.parts);
    }

    /// THE BALL IT IS HOLDING — two shells, a hot core inside a wider cooler halo, because a single sphere at
    /// one value reads as a painted dot where what is wanted is something with depth down it.
    fn drawCup(self: *const Mage) void {
        const k = self.cupAmt();
        if (k <= 0.02) return;
        const at = self.cupWorld();
        // …and it BREATHES on its own fast clock, so a held gather is never a still object. `k` is what makes
        // it GROW: the ball the player is looking at is the gather's own channel, not a clock beside it.
        const s = self.scale * k * (1.0 + 0.10 * mathx.sinf(self.elapsed * 13.0));
        rl.drawSphereEx(at, BALL_R * s, 8, 8, mathx.withAlpha(FIRE_EDGE, mathx.u8f(120.0 * k)));
        rl.drawSphereEx(at, BALL_CORE * s, 8, 8, mathx.withAlpha(FIRE_CORE, mathx.u8f(220.0 * k)));
    }
};

/// How far the cloak is dragged back by walking, in degrees, and the spring that gets it there.
const CLOAK_DRAG: f32 = 9.0;
const CLOAK_SWAY: f32 = 4.0;
const CLOAK_STIFF: f32 = 90.0;
const CLOAK_DAMP: f32 = 11.0;

/// **THE BALL'S OWN RADIUS, AND IT IS ONE NUMBER FOR BOTH ENDS OF THE MOVE** — the thing cupped in its hands
/// and the thing flying at you are the SAME OBJECT, and the whole point of showing the gather is that the
/// player recognises what leaves it. Written out twice they were already 0.178 and 0.170 apart, which is a
/// spell that visibly changes size on the frame it is thrown. Metres, before the creature's own scale, and
/// sized against the hands holding it: measured off the crop at 0.178 it was two thirds of the cap's whole
/// width and read as a pumpkin.
pub const BALL_R: f32 = 0.145;
/// …and its hot core inside that, which is what makes it a thing with depth rather than a painted dot.
pub const BALL_CORE: f32 = BALL_R * 0.64;
/// Motes a second into the gather, at the start and at the end. The curve is `u*u`, so most of the growth is
/// LATE: a linear ramp spends its first half at a rate the player reads as ambient and has nowhere left to go.
const KINDLE_RATE_0: f32 = 8.0;
const KINDLE_RATE_1: f32 = 74.0;
/// …and a ceiling per frame, so a hitched frame cannot spend the whole pool on one gather.
const KINDLE_CAP: usize = 6;
const THROW_PUFF: usize = 14;

pub const SHOVE = foe.Push{ .light = 1.35, .heavy = 3.10 };

// ── THE MESHES ─────────────────────────────────────────────────────────────────────────────────────────
//
// **FLESH IS ROUND**: every mass here is `addBlob`/`addCapsule`. The only near-flat things are the gills,
// which are a shadow rather than a body.

fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = chestMesh();
    mesh[NECK] = neckMesh();
    mesh[CAP] = capMesh();
    mesh[HIPL] = thighMesh(201);
    mesh[KNEEL] = shinMesh(202);
    mesh[ANKL] = bootMesh(1.0, 203);
    mesh[HIPR] = thighMesh(204);
    mesh[KNEER] = shinMesh(205);
    mesh[ANKR] = bootMesh(-1.0, 206);
    mesh[SHL] = upperArmMesh(1.0, 207);
    mesh[ELL] = forearmMesh(1.0, 208);
    mesh[WRL] = handMesh(1.0, 209);
    mesh[SHR] = upperArmMesh(-1.0, 210);
    mesh[ELR] = forearmMesh(-1.0, 211);
    mesh[WRR] = handMesh(-1.0, 212);
    // `mesh[HELD]` is deliberately left undefined — see the alias block. `Model.draw` never reaches it.
    return mesh;
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.005 * H, 0), v3(0.105 * H, 0.075 * H, 0.088 * H), 9, 6, CLOAK);
    // The cord, sunk most of the way in — relief is a few PERCENT of the mass, not a tenth.
    b.addBlob(v3(0, 0.030 * H, 0.004 * H), v3(0.100 * H, 0.016 * H, 0.086 * H), 8, 5, CORD);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.085 * H, 0), 0.098 * H, 0.108 * H, 9, CLOAK);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3F17);
    b.setMat(.cloth);
    // A STOUT BARREL — this creature is wide, and the cloak over it is one continuous mass.
    b.addBlob(v3(0, 0.045 * H, 0.004 * H), v3(0.132 * H, 0.098 * H, 0.108 * H), 10, 7, CLOAK);
    b.addBlob(v3(0, -0.010 * H, 0.012 * H), v3(0.118 * H, 0.062 * H, 0.098 * H), 9, 6, CLOAK_LT);
    // THE COWL'S SHOULDERS — the cloak gathered up round the neck, which is what makes the cap read as
    // sitting IN a hood rather than balanced on a pole.
    b.addBlob(v3(0, 0.100 * H, -0.006 * H), v3(0.116 * H, 0.042 * H, 0.100 * H), 9, 6, HEM);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const rr = 0.104 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.088 * H + rng.range(-0.010, 0.012) * H, mathx.sinf(a) * rr * 0.9),
            v3(rng.range(0.018, 0.032) * H, rng.range(0.020, 0.036) * H, 0.016 * H),
            5,
            4,
            if (rng.float() < 0.5) HEM else CLOAK,
        );
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // SHORT AND THICK — a stalk, not a neck, and most of it is inside the cowl anyway.
    b.addCapsule(v3(0, 0, 0), v3(0, 0.040 * H, 0), 0.046 * H, 0.052 * H, 8, FLESH);
    return b.toMesh();
}

/// **THE CAP'S HALF-WIDTH**, and every mass under the dome is a share of it — so the brim, the gills, the
/// hollow and the flecks keep their proportion through a retune instead of four literals that have to be
/// moved together by hand. Comptime-checked against the shoulders it has to overhang.
const RIM: f32 = 0.150 * H;
comptime {
    // **IT MUST OVERHANG THE BODY, AND IT MUST NOT BE THE BODY.** Under the first it is a hat; over the
    // second it is a parasol with a creature hiding under it, which is the failure the first pass had.
    std.debug.assert(RIM > SHOULDER_HALF * 1.35);
    std.debug.assert(RIM < SHOULDER_HALF * 2.4);
}

/// **THE CAP, AND IT IS THE HOOD.** A wide dome over a dark hollow of gills, with the eyes set well back in
/// it. The dome's own overhang is what shades the face — the hollow is not painted on, it is a mass sitting
/// under a bigger mass, which is why it stays a hollow from every bearing.
fn capMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x9C4B);
    b.setMat(.skin);
    // The dome. WIDE — wider than the shoulders under it, because the silhouette is the whole read; a hair
    // oblong and leaning a few degrees, because nothing here is turned on a lathe.
    //
    // **AND WIDE HAS A CEILING, WHICH IS THE BODY.** At 0.196·H the brim was 0.35 m of half-width on a 1.48 m
    // creature — as broad as the whole cloak, sitting at chin height, and it swallowed the hollow, the eyes
    // and the fire in its own hands. Measured off the crop, not argued: the cap has to be the widest thing on
    // the creature and it may not be the ONLY thing on it. `RIM` is that half-width and everything under the
    // dome is a share of it, so the proportion holds if it is ever retuned again.
    b.addBlob(v3(0, 0.072 * H, 0.004 * H), v3(RIM, 0.090 * H, RIM * 0.94), 11, 9, CAP_COL);
    // …and its crown lump, off-centre. One asymmetry near the top does more than ten round the rim.
    b.addBlob(v3(0.016 * H, 0.114 * H, -0.012 * H), v3(RIM * 0.56, 0.052 * H, RIM * 0.53), 8, 6, CAP_COL);
    // THE GILLS: a dark disc under the rim, sunk just proud of the dome's own underside.
    b.addBlob(v3(0, 0.042 * H, 0.006 * H), v3(RIM * 0.90, 0.022 * H, RIM * 0.85), 7, 7, GILL);
    // …and the FACE-HOLLOW under them, which is where the eyes live. Deeper in than the gills, so what the
    // player finds under the cap is a shadow with two lights in it.
    b.addBlob(v3(0, 0.018 * H, 0.048 * H), v3(RIM * 0.50, 0.036 * H, RIM * 0.36), 7, 6, GILL);
    b.setMat(.plain);
    // THE EYES — small, emissive, and set BACK: any further forward and they stop being found in a hollow.
    b.addBlob(v3(RIM * 0.24, 0.022 * H, RIM * 0.56), v3(0.016 * H, 0.013 * H, 0.011 * H), 5, 5, EYE);
    b.addBlob(v3(-RIM * 0.22, 0.020 * H, RIM * 0.56), v3(0.015 * H, 0.012 * H, 0.011 * H), 5, 5, EYE);
    b.setMat(.skin);
    // The cream flecks, dealt over the dome and sunk most of the way in. No two alike, none of them near the
    // rim — a fleck on the edge reads as a chip out of it.
    var w: u32 = 0;
    while (w < 11) : (w += 1) {
        const a = rng.angle();
        const rr = rng.range(0.20, 0.88) * RIM;
        const sz = rng.range(0.11, 0.22) * RIM;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.086 * H + 0.042 * H * (1.0 - rr / RIM), mathx.sinf(a) * rr * 0.94),
            v3(sz, sz * 0.42, sz),
            5,
            4,
            WART,
        );
    }
    // …and ONE old bite out of the rim, the sporeling's own note: something tried this mushroom once.
    b.addBlob(v3(-RIM * 0.72, 0.058 * H, -RIM * 0.56), v3(RIM * 0.26, 0.026 * H, RIM * 0.24), 5, 4, CAP_DK);
    return b.toMesh();
}

/// **THE CLOAK, AND IT IS NOT A BONE** — one mass from the shoulders to below the soles, chained off the
/// root in `chainCloak` so it drags and sways as one thing. Built as three stacked skirts opening slowly,
/// which is what a cloak does and what a single cone never looks like.
fn cloakMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1D55);
    b.setMat(.cloth);
    const top = 0.075 * H;
    // BELOW the sole plane on purpose: that is the drag, and a hem stopping at the ankle is a smock.
    const bot = -0.022 * H - REST[ROOT].y;
    const waist = -0.16 * REST[ROOT].y;
    const knee = -0.58 * REST[ROOT].y;
    skirt(&b, v3(0, top, 0), 0.112 * H, top - waist, 0.104 * H, 11, CLOAK, &rng);
    skirt(&b, v3(0, waist, 0), 0.104 * H, waist - knee, 0.122 * H, 12, HEM, &rng);
    skirt(&b, v3(0, knee, 0), 0.122 * H, knee - bot, 0.156 * H, 13, HEM, &rng);
    return b.toMesh();
}

/// One band of the cloak: a ring of overlapping vertical folds from `r0` to `r1` over `drop`. **AUTHORED AS
/// FOLDS AND NOT AS A CONE** — a turned surface reads as a lampshade however good the colour is, and the
/// unevenness between the folds is what makes it cloth. Cut in AMPLITUDE, never in irregularity.
fn skirt(b: *Builder, at: rl.Vector3, r0: f32, drop: f32, r1: f32, n: u32, col: rl.Color, rng: *mathx.Rng) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * std.math.tau + rng.range(-0.09, 0.09);
        const wob = rng.range(0.90, 1.12);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        b.addCapsule(
            v3(at.x + ca * r0, at.y, at.z + sa * r0),
            v3(at.x + ca * r1 * wob, at.y - drop, at.z + sa * r1 * wob),
            r0 * 0.34,
            r1 * 0.36 * wob,
            5,
            col,
        );
    }
}

fn thighMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const len = REST[HIPL].y - REST[KNEEL].y;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.052 * H * rng.range(0.95, 1.08), 0.044 * H, 7, HEM);
    return b.toMesh();
}

fn shinMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    const len = REST[KNEEL].y - REST[ANKL].y;
    // Bare stalk-flesh below the cloak — thin, and it is what makes the hem read as a hem and not a plinth.
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.038 * H * rng.range(0.94, 1.1), 0.031 * H, 7, FLESH);
    return b.toMesh();
}

fn bootMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    // SHORT AND BROAD, matching `SOLES` — a splayed fungal foot, blunt at the front like everything else.
    b.addBlob(v3(side * 0.004 * H, -0.020 * H, 0.058 * H), v3(0.054 * H, 0.026 * H, 0.098 * H), 8, 5, FLESH);
    b.addBlob(v3(0, -0.012 * H, -0.020 * H), v3(0.044 * H, 0.028 * H, 0.038 * H), 6, 4, FLESH);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const x = (@as(f32, @floatFromInt(i)) - 1.0) * 0.030 * H;
        b.addBlob(v3(x, -0.026 * H, 0.140 * H + rng.range(-0.006, 0.006) * H), v3(0.017 * H, 0.013 * H, 0.020 * H), 4, 4, FLESH);
    }
    return b.toMesh();
}

fn upperArmMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const len = mathx.lenV(mathx.subV(REST[SHL], REST[ELL]));
    // THE SLEEVE, and it is loose: it widens toward the elbow rather than tapering, which is what says cloth.
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.046 * H * rng.range(0.95, 1.06), 0.054 * H, 7, CLOAK);
    b.addBlob(v3(side * 0.006 * H, 0.012 * H, 0), v3(0.058 * H, 0.046 * H, 0.052 * H), 7, 5, CLOAK_LT);
    return b.toMesh();
}

fn forearmMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const len = mathx.lenV(mathx.subV(REST[ELL], REST[WRL]));
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.050 * H, 0.038 * H * rng.range(0.94, 1.08), 7, CLOAK);
    // …and the cuff it comes out of, which is where the sleeve ENDS and the hand begins.
    b.addBlob(v3(side * 0.004 * H, -len * 0.94, 0), v3(0.044 * H, 0.020 * H, 0.042 * H), 6, 4, HEM);
    return b.toMesh();
}

fn handMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    b.addBlob(v3(0, -0.026 * H, 0.010 * H), v3(0.030 * H, 0.034 * H, 0.028 * H), 6, 5, FLESH);
    // Four short blunt fingers, none of them the same length and **none of them ending in a point**.
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const x = side * ((@as(f32, @floatFromInt(i)) - 1.5) * 0.015 * H);
        const l = 0.038 * H * rng.range(0.8, 1.2);
        b.addCapsule(
            v3(x, -0.046 * H, 0.016 * H),
            v3(x + side * rng.range(-0.004, 0.004) * H, -0.046 * H - l * 0.35, 0.016 * H + l),
            0.011 * H,
            0.009 * H,
            5,
            FLESH,
        );
    }
    // The thumb, off to its own side and shorter.
    b.addCapsule(v3(side * 0.026 * H, -0.036 * H, 0.008 * H), v3(side * 0.040 * H, -0.048 * H, 0.030 * H), 0.011 * H, 0.009 * H, 5, FLESH);
    return b.toMesh();
}

/// **THE BALL ITSELF**, and it is drawn as its own model in the shot pool rather than as anything of this
/// creature's — by the time you are looking at it the mage may well be dead. Round, because it is the one
/// thing that flies here that is not a shaft, and it is what `arrowXform` orients down its velocity: a
/// SPHERE ignores that outright, which is exactly right for a thing tumbling on a bounce.
///
/// Two shells like the cup it came out of, so the ball in the air is visibly the ball in its hands.
pub fn emberMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    // **`BALL_R`, THE SAME NUMBER ITS HANDS WERE HOLDING** — a spell that changes size on the frame it is
    // thrown is a spell whose gather taught the player nothing.
    b.addBlob(mathx.zero3, v3(BALL_R, BALL_R, BALL_R), 8, 12, mathx.withAlpha(FIRE_EDGE, 110));
    b.addBlob(mathx.zero3, v3(BALL_CORE, BALL_CORE, BALL_CORE), 7, 10, mathx.withAlpha(FIRE_CORE, 36));
    return b.toModel(shader);
}

// ── THE GROUP ──────────────────────────────────────────────────────────────────────────────────────────

const CAP_N = wf.MAX_PER_KIND;

/// Sized off what feeds it: at most a handful of balls in the air at once, `BURST_PUFF` on the last touch of
/// each and `BOUNCE_PUFF` on the ones before, against a fire mote's own ~0.5 s life.
const EMBER_PARTS = 120;
const BOUNCE_PUFF: usize = 10;
const BURST_PUFF: usize = 26;

/// **A FAIRY RING** — what a group of these is called, and what a group of them posted round a clearing
/// actually looks like. `reset` and `draw` are ONE-LINE DELEGATES to the shared pair; the `setFlash(0)` tail
/// is what a hand-rolled copy would forget.
pub const Ring = struct {
    model: Model,
    mages: [CAP_N]Mage = undefined,
    n: usize = 0,
    /// **THE BALL'S OWN FX LIVE ON THE GROUP, NOT ON THE CASTER** — the knight's `Gas` rule, and here it is
    /// not a nicety: a fireball is six seconds in the air over three bounces and the mage that threw it can
    /// be gold motes long before the last one lands. Borrowed off "the nearest live member" (`kobold.splash`)
    /// the embers would simply stop the moment the last mage in a ring died, which is exactly the fight where
    /// there are the most balls still in the sky.
    parts: [EMBER_PARTS]foe.Particle = [_]foe.Particle{.{}} ** EMBER_PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x8E11),

    pub fn init(shader: rl.Shader) Ring {
        return .{ .model = Model.init(shader) };
    }

    /// ONE BOUNCE — the thud's own puff. Small, and it FLOORS on the ground the ball actually came off
    /// (`foe.floorBurst`) rather than on any mage's feet: the ball is off doing this somewhere else entirely.
    pub fn bounce(self: *Ring, at: rl.Vector3) void {
        const from = self.fxHead;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .fire, BOUNCE_PUFF, 1.0);
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    /// …and the last one, where it stops being a threat and is a fire on the ground for a moment. Bigger by
    /// a clear margin: a bounce is a thing still coming and this is the thing being over.
    pub fn splash(self: *Ring, at: rl.Vector3) void {
        const from = self.fxHead;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .fire, BURST_PUFF, 1.0);
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }
    pub fn live(self: *Ring) []Mage {
        return self.mages[0..self.n];
    }
    pub fn liveConst(self: *const Ring) []const Mage {
        return self.mages[0..self.n];
    }
    pub fn reset(self: *Ring, m: *const wf.Map) void {
        foe.resetGroup(Mage, &self.mages, &self.n, m, .mushroom_mage);
    }
    pub fn clear(self: *Ring) void {
        self.n = 0;
    }
    pub fn setShader(self: *Ring, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(self: *Ring, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        // The group's own embers age here — every one of them named its own floor at the burst, so the
        // argument is the fallback nothing in this pool ever uses.
        foe.tickParticles(&self.parts, dt, hero.y);
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Ring, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Ring) void {
        for (self.liveConst()) |*k| k.drawFx();
        foe.drawParticles(&self.parts);
    }
    pub fn pierce(self: *Ring, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Ring) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Ring) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Ring) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Ring) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

// ── TESTS ──────────────────────────────────────────────────────────────────────────────────────────────

test "THE GATHER IS A REAL TELL, and the ball leaves inside the throw that follows it" {
    try std.testing.expect(LOB_WIND >= foe.TELL_MIN);
    // …and it is the LONGEST part of the move by a clear margin: the thing being read is the FACING at the
    // release, and a gather you can only just see is a facing you cannot read at all.
    try std.testing.expect(LOB_WIND > LOB_THROW * 3.0);
    // The release is inside the throw, and early in it — a hand that stops before the ball appears is a
    // hand that did not throw anything.
    try std.testing.expect(RELEASE_K > 0 and RELEASE_K < 0.5);
}

test "THE SEAM IS THE END POSE — wind[1.0] and throw[0.0] are the same pose, and so are throw[1] and recover[0]" {
    // A move authored as three tracks that only line up because somebody kept them in step by hand is how
    // `setSweepWind` and `setSweep` drifted apart, and a seam in a pose is a POP on the frame it crosses.
    const windEnd = samplePose(&WIND_KEYS, 1.0);
    const throwStart = samplePose(&THROW_KEYS, 0.0);
    for (windEnd, throwStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    const throwEnd = samplePose(&THROW_KEYS, 1.0);
    const recStart = samplePose(&RECOVER_KEYS, 0.0);
    for (throwEnd, recStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    // …and the recovery ends back on the carry, so an idle mage stands in the pose it started in.
    const recEnd = samplePose(&RECOVER_KEYS, 1.0);
    for (CARRY, recEnd) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
}

test "THE THROW HAS A SHAPE — most of its travel in the first third, and the fire is out of its hands by the end" {
    // The strike law: over half the travel in the first third, or it is a glide with a new name.
    const a = samplePose(&THROW_KEYS, 0.0);
    const mid = samplePose(&THROW_KEYS, 1.0 / 3.0);
    const b = samplePose(&THROW_KEYS, 1.0);
    var moved: f32 = 0;
    var total: f32 = 0;
    for (a, mid, b) |v0, vm, v1| {
        moved += @abs(vm - v0);
        total += @abs(v1 - v0);
    }
    try std.testing.expect(total > 1e-3);
    try std.testing.expect(moved > total * 0.5);
    // …AND THE CUP EMPTIES. The picture may not still be holding a fireball after the ball has gone.
    try std.testing.expectApproxEqAbs(@as(f32, 0), b[CH_CUP], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), a[CH_CUP], 1e-6);
}

test "IT KEEPS ITS DISTANCE: it throws from its band, backs off inside it, and closes from outside it" {
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, true));
    try std.testing.expectEqual(Choice.lob, classify((LOB_MIN + LOB_MAX) * 0.5, true));
    // A sword in its face outranks a ready spell — it has no melee, so close is a mistake and feet are the
    // only answer it owns.
    try std.testing.expectEqual(Choice.back, classify(FLEE_R - 0.5, true));
    // …and with nothing to spend it is still walking to where it wants to be standing.
    try std.testing.expectEqual(Choice.keep, classify((LOB_MIN + LOB_MAX) * 0.5, false));
    try std.testing.expectEqual(Choice.keep, classify(LOB_MAX + 2.0, true));
}

test "THE FIREBALL IS SLOW, IT BOUNCES, AND IT IS THE ONLY THING IN THE POOL THAT DOES" {
    // SLOW is the owner's word and the whole design: under the sling's lump and well under a shaft.
    try std.testing.expect(EMBER_SPEED < koboldmod.CLUMP_SPEED);
    try std.testing.expect(archermod.bouncesOf(.emberball) >= 2); // one bounce is a skip, not a threat
    // …and nothing else in the pool moved. A shaft, a glob and a jar all still end where they first land.
    inline for (.{ .arrow, .firearrow, .clump, .crock, .venom, .bolt, .wisp }) |s| {
        try std.testing.expectEqual(@as(u8, 0), archermod.bouncesOf(s));
    }
    // ALL OF IT BURNS, so a fire resistance is a real answer to this creature.
    try std.testing.expectApproxEqAbs(@as(f32, 0), EMBER_HIT.dmg, 1e-6);
    try std.testing.expectApproxEqAbs(EMBER_HIT.raw(), EMBER_HIT.elem.at(.fire), 1e-6);
}

test "IT IS NOT KILLED BY ITS OWN ELEMENT, and chaos is what answers it" {
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(combat.Hit{ .elem = combat.elems(.{ .fire = 30 }) });
    const afterFire = HP_MAX - v.hp;
    v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(combat.Hit{ .elem = combat.elems(.{ .chaos = 30 }) });
    const afterChaos = HP_MAX - v.hp;
    try std.testing.expect(afterFire < 30.0); // it handles the stuff — it throws it
    try std.testing.expect(afterChaos > 30.0); // …and the kingdom's own weakness is untouched
    try std.testing.expect(afterChaos > afterFire * 1.8);
    std.debug.print("\n  mushroom mage: 30 fire takes {d:.1} HP, 30 chaos takes {d:.1}\n", .{ afterFire, afterChaos });
}

test "AN INTERRUPTED MAGE DROPS WHAT IT WAS HOLDING — the picture may not keep a spell the mechanic lost" {
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.4);
    k.stageGather(1.0);
    try std.testing.expect(k.cupAmt() > 0.9); // a full ball, right at the throw
    k.debugStagger(false);
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.cupAmt(), 1e-6);
    try std.testing.expect(k.staggered());
}

test "THE BALL LEAVES ITS HANDS ONCE, however the frame falls" {
    const hero = mathx.ground(0, 9.0);
    var fired: u32 = 0;
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .lob_throw;
    k.t = 0;
    // A LONG frame that steps clean over the release must still fire it exactly once, and a normal one too.
    for ([_]f32{ 1.0 / 60.0, 1.0 / 12.0 }) |dt| {
        var m = k;
        var t: f32 = 0;
        while (t < LOB_THROW + dt) : (t += dt) {
            _ = m.update(dt, hero, 200.0, .{});
            if (m.lobbed) fired += 1;
        }
        try std.testing.expectEqual(@as(u32, 1), fired);
        fired = 0;
    }
}

test "THE CAP CARRIES THE MARK AND THE HURT SPHERE HOLDS IT" {
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.5);
    k.pose();
    const mark = k.lockPoint();
    const c = k.centerWorld();
    const r = k.hurtRadius();
    // The mark rides the posed cap, so it is above the hurt centre and inside the sphere — a mark outside
    // what a sword can reach is a reticle on a place you cannot hit.
    try std.testing.expect(mark.y > c.y);
    try std.testing.expect(mathx.lenV(mathx.subV(mark, c)) <= r);
    // …and the crown clears the cap, so the bar hangs over it rather than inside it.
    try std.testing.expect(k.topWorld().y > mark.y);
    std.debug.print("  mushroom mage: crown {d:.2} m, mark {d:.2} m, hurt centre {d:.2} m (r {d:.2})\n", .{
        k.topWorld().y, mark.y, c.y, r,
    });
}

test "THE CUP IS BETWEEN THE HANDS AND IN FRONT OF THE BODY, at the frame it throws off" {
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.2);
    k.stageGather(1.0);
    const at = k.cupWorld();
    // In FRONT of it (it faces +Z at yaw 0) and up at its own chest — a ball conjured behind or below the
    // creature is one the player never sees being made.
    try std.testing.expect(at.z > 0.10);
    try std.testing.expect(at.y > 0.55 and at.y < 1.35);
    // …and it is genuinely BETWEEN the two hands: within a hand's width of each.
    const l = foe.markOn(k.xf[WRL], v3(0, -0.02 * H, 0.05 * H));
    const r = foe.markOn(k.xf[WRR], v3(0, -0.02 * H, 0.05 * H));
    try std.testing.expect(mathx.lenV(mathx.subV(l, r)) < 0.55);
    std.debug.print("  mushroom mage cup: {d:.2} m up, {d:.2} m out, hands {d:.2} m apart\n", .{
        at.y, at.z, mathx.lenV(mathx.subV(l, r)),
    });
}
