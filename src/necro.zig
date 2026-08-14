const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");
const archermod = @import("archer.zig"); // THE SAME DEAD MAN under the robe — his bones, his chips, his dissolve
const propart = @import("propart.zig"); // the world's own dead wood — a crooked staff IS a dead limb

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
const BONE_LT = archermod.BONE_LT;

// THE ROBE IS COLD WHERE THE WORLD IS WARM — the ogre's hue lesson and the knight's, on a mass that is mostly
// cloth. Everything outdoors here is warm, so a tall dark figure separates by being BLUE-BLACK rather than by
// being darker: at the wanderer's own wool (50,42,33) this thing sampled as one more shadow under a tree.
/// …**AND THE HUE HAS TO BE LAID ON THICK, because the sun cancels it.** Authored at 26,28,38 — a value that
/// looks decently blue in a swatch — the hem SAMPLED at 83,79,81 on the render: dead neutral grey, because the
/// key here is warm and multiplies through. The blue channel has to run at better than twice the red in the
/// ALBEDO for any of it to survive to the screen.
const ROBE = rgba(14, 19, 36, 255);
const ROBE_LT = rgba(22, 28, 48, 255);
const ROBE_DK = rgba(9, 12, 22, 255);
/// The HEM, which is the part that drags: darker again, and it is the biggest single face on him, so the
/// dark-albedo rule bites hardest here — a big smooth mass has to start near-black or the gamma lift makes
/// it pale whatever the swatch said.
const HEM = rgba(8, 12, 26, 255);
const CORD = rgba(74, 62, 44, 255); // the one warm note, at the waist — the wanderer's SASH trick

/// THE FROST IS ONE SUBSTANCE (the brood's rule, and the wand's one violet): the sigil on the ground, the
/// gather at the staff head, the burst and the rime on the hem are all this pair. Two kinds of ice in one
/// world reads as two different things happening.
/// **AND IT NEEDS TWO PALETTES, BECAUSE THE TWO HALVES ARE ON DIFFERENT SCALES** — the delver's `CLOD`-against-
/// `SOIL` law, and the knight's `.steel`. What goes into a MESH is an ALBEDO and runs through ×1.72 → gamma;
/// what is drawn UNLIT after the opaque pass (the ring, the gather, every particle) is a LITERAL SCREEN VALUE.
/// One constant serving both means one of them is wrong: at 150 the staff head's ice comes back a blown white
/// knuckle, and at an albedo the ring on the ground would be invisible grey grit.
const RIME_ALB = rgba(44, 58, 72, 255); // MESH — solved to read ~170 on screen: pale ice, not a white sheet
const RIME_ALB_LT = rgba(62, 80, 96, 255);
const RIME = rgba(150, 200, 226, 255); // UNLIT — literal screen values
const RIME_LT = rgba(206, 234, 246, 255);
const FROST_MOTE = rgba(212, 238, 250, 225);
const FROST_SHARD = rgba(168, 208, 228, 240);
/// The raise's own colour, and it is deliberately NOT the frost's: what the two moves do to you is
/// different, so the two must never be one wash of light. Gold is the world's dying colour (`foe.MOTE`),
/// so a RAISE — the undoing of a death — reads as that gold running backwards, down into the body.
const RAISE_GLOW = rgba(236, 198, 104, 200);

const DUST = foe.DUST;
const CHIP = archermod.BONE_CHIP;

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
/// The FREE hand, which is what casts…
const SHL = heromod.SHL;
const ELL = heromod.ELL;
const WRL = heromod.WRL;
/// …and the STAFF arm, which must be the RIGHT one: `heromod.PARENT[HELD]` is `WRR`, so the held slot hangs
/// off that wrist and off no other. Authored the other way round the staff's matrix was built against a
/// `wx[WRR]` nothing had written yet — undefined memory, and the whole pole transformed to a point at the
/// world origin. `poseUpper` therefore poses this arm LAST, with the staff after its own wrist.
const SHR = heromod.SHR;
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const STAFF = heromod.HELD;

const H: f32 = heromod.H;

/// **TALL AND SKINNY** (owner's call), and the two halves of that are different dials. The STATURE is a
/// scale on the whole rig — a head and a half over the archer, which makes him the second tallest thing on
/// foot after the ogre — and the SKINNY is `restHumanoid`'s own `hx`/`sx`, which are the only two numbers
/// honestly per-creature on the shared scaffold. Scaling him up alone gives a big archer; narrowing the
/// hips and shoulders is what makes the height read as gaunt instead of as bulk.
pub const SCALE = (H + 0.62) / H;
const HIP_HALF = heromod.HIP_HALF * 0.80;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.78;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
/// His feet are the archer's feet — the same dead man's boots, and `footMesh` is what a sole patch is
/// measured off, so a second copy is a second thing to retune.
const solePatches = archermod.solePatches;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;

const FIST_Y = -0.05 * H; // the fist centre in the wrist frame — the archer's grip anchor, same hand
const FIST_Z = 0.02 * H;

pub const AGGRO_R = 26.0; // the widest ring in the game bar none: it opens the fight and never closes it
const TURN_RATE = 3.2; // rad/s — slower than a soldier; it turns like something that does not expect to be rushed
const WALK_SPEED = heromod.WALK_SPEED * 0.72; // it never hurries and it never runs
const SPEED = 1.0;
const BODY_R = 0.34;
const HURT_R = 0.42;
pub const SOULS: u32 = 320; // dearer than a greatsword: it is the priority target and the price says so

const HP_MAX: f32 = 78.0; // FRAIL — the kobold priest's bargain, one tier up: what it costs you is time, not HP
const POISE_MAX: f32 = 12.0; // …and it flinches off almost anything, which is what makes interrupting it work
const STANCE_MAX: f32 = 34.0;

/// DRY BONE IN A COLD ROBE. The archer's table with the COLD arm taken to the cap: it is the one thing in
/// the world that deals cold, and a creature you can freeze with its own element is a creature whose whole
/// identity the resistance sheet argues against. Fire is still the answer, as it is to every skeleton.
const RESISTS = combat.resists(.{ .fire = -35, .cold = 75, .chaos = 45 });

const DEATH_DUR = archermod.DEATH_DUR;
const DISS_DUR = archermod.DISS_DUR;
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 7.0;
const A_BOB = heromod.A_BOB;
const A_PROT = 2.6; // deg of pelvic rotation — narrow hips and a robe: it barely swings at all

// ─── THE RAISE ────────────────────────────────────────────────────────────────────────────────────────
//
// **THE CORPSE IS THE MECHANIC, AND THE WINDOW HAD TO BE MADE TO EXIST.** A skeleton is `DEATH_DUR +
// DISS_DUR` = 2.05 s from the blow that killed it to the last mote going up, and a raise with a tell you
// can read does not fit inside that — so as a race against the dissolve the move would essentially never
// fire, and when it did it would be unreadable.
//
// So a body inside `RAISE_R` of a living necromancer **STOPS DISSIPATING** (`vigil`, stamped by
// `game.markVigil` and read by `foe.dissipate`). That is the whole design:
//
//   - **THE HELD CORPSE IS THE TELL, and it comes before the cast.** Every other body in the game goes to
//     gold on its own clock; one lying there NOT going is a thing the player can see, from the frame it
//     lands, without knowing what a necromancer is yet. The cast's own gather is the second warning.
//   - **IT IS A PLACE, NOT A LIST.** Nothing is remembered and nothing is reserved: the stamp is re-taken
//     every frame off where the bodies actually are, so walking the fight away from the corpses is an
//     answer, and so is killing things where it cannot reach.
//   - **AND A BODY MAY BE RAISED ONCE** (`wasRaised`, a latch on the corpse). Twice is a fight that cannot
//     be won by killing things, which is the only thing the player is holding.
/// How far it reaches for a body — comfortably past its own frost band, so the ground it defends and the
/// ground it fights on are the same ground.
pub const RAISE_R: f32 = 11.0;
/// **THE LONGEST TELL IN THE GAME** and it is meant to be (the Bone Knight's lesson): this is the move that
/// undoes the last thirty seconds of the player's work, so it owes the most warning of anything on the
/// field. It is also the whole of the punish window — it is PLANTED for every frame of it.
pub const RAISE_WIND: f32 = 1.90;
const RAISE_DUR: f32 = 0.42; // the body comes up on this, and the staff is still down for it
const RAISE_RECOVER: f32 = 1.15; // …and it is wide open after, which is the reward for reading the gather
const RAISE_CD: f32 = 7.5;
/// WHAT COMES BACK UP. Not full: a raised body is a body that has already been killed once, and a fight
/// where the graveyard refills at full strength is one the player cannot see themselves winning.
pub const RAISE_HP_FRAC: f32 = 0.55;
/// **HOW NEAR THE MARK THE BODY HAS TO BE LYING to be the one that comes up.** Generous: it is the same point
/// the hold was stamped at and nothing has moved it, so this only ever absorbs the shove a corpse took off the
/// blow that finished it.
///
/// Read by `game.markVigil` and `game.applyRaises`, which is where the SEARCH lives — but the number belongs
/// here beside `RAISE_R` and `RAISE_HP_FRAC`, or somebody retuning this creature's raise has two files to find
/// and will only think to open one.
pub const RAISE_MATCH_R: f32 = 1.2;

// ─── THE FROST ────────────────────────────────────────────────────────────────────────────────────────
//
// **A DELAYED RING ON THE GROUND UNDER HIM** (owner's call), and every rule it keeps is the delver's
// surge's, one creature along:
//
//   - **THE SPOT IS COMMITTED THE FRAME IT IS CAST.** It lands at his feet and then it does not follow him.
//     What is drawn on the ground IS where the blow lands, so the read is honest and the counter is his own
//     feet — and a ring that tracked would be a tax on standing anywhere rather than a thing you answer.
//   - **IT OUTLIVES THE CASTER'S OWN ANIMATION.** The sigil keeps its own clock, so killing the necromancer
//     after the cast does NOT un-cast it: the thing is in the ground by then. That is the honest reading of
//     a laid trap and it is also what stops the move being free.
//   - **IT IS NOT PARRYABLE AND THE BOARDS CANNOT ANSWER IT.** There is nothing to catch in the ground going
//     hard, and its blow carries the SIGIL as its origin rather than the caster (`hitFrom`), so stood on the
//     mark there is no bearing at all — the zero-`fromDir` rule, the delver's burst exactly.
//   - **AND IT IS THE FIRST COLD IN THE GAME.** `combat.Elem` has carried four arms since it was written and
//     thirteen creatures resist all four; nothing had ever dealt this one. All-cold, no physical, for the
//     wand's own reason: an element with one source in the world should be unmistakable when it lands.
pub const FROST_HIT = combat.Hit{ .poise = 18, .stance = 8, .elem = combat.elems(.{ .cold = 26 }) };
/// HOW WIDE THE RING BITES. Bigger than the delver's burst because the DELAY is longer and the caster is
/// nowhere near it: what makes it fair is the time on the ground, not the size of it.
pub const FROST_R: f32 = 2.4;
/// The cast — the staff comes up and the hand goes out over the mark. PUBLIC because the harness aims a beat
/// with it (`shots.FROST_TELL_AT`): a portrait pinned to a literal 0.65 s photographs somewhere else the next
/// time this is tuned.
pub const FROST_WIND: f32 = 0.72;
const FROST_CAST_DUR: f32 = 0.30; // …and the sigil is laid at the end of it
const FROST_RECOVER: f32 = 0.70;
/// **THE FUSE**, and it is the whole move. **SOLVED, NOT CHOSEN**: long enough that a WALK clears the ring
/// from dead centre — deliberately, and this is where it parts company with the delver's burst, which a walk
/// is deliberately NOT enough for. That one arrives from under the floor with a mound as its only warning;
/// this one is drawn on the ground in front of him in a colour nothing else in the world is, so what it asks
/// for is that you look down and step off, not that you sprint.
///
/// The first pass authored 1.30 s beside a 2.4 m radius and the comptime assert caught it: the ring is
/// `FROST_R * scale` — 3.2 m on this rig, not 2.4 — so a walk covered 2.2 m of the 3.6 m it had to, and the
/// one thing the move promises was false. Move either dial and the assert below re-solves it.
pub const FROST_FUSE: f32 = 2.20;
const FROST_CD: f32 = 4.2;
/// The band it is thrown in. It has no melee at all, so the near edge is only "not while he is on top of
/// me" — laying a fuse at the feet of a man already swinging is a move spent on nothing.
const FROST_R_MIN: f32 = 3.0;
const FROST_R_MAX: f32 = 18.0;

comptime {
    // A COMMITTED SPOT HE CAN GET OFF, and the price of standing still. The ring lands centred on him, so
    // what he has to clear is its whole radius plus his own footprint. A WALK does it here (see `FROST_FUSE`)
    // and that is the decision; the hero's own figures are written out rather than imported for
    // `foe.HERO_*`'s reason — this file sits below `hero.zig` in the import graph.
    //
    // **MEASURED AT THE SCALE IT IS ACTUALLY DRAWN AT**, unlike the delver's own version of this assert: the
    // radius on the field is `FROST_R * scale`, so asserting the bare `FROST_R` would pass on a ring a third
    // wider than the one tested. A map that posts an oversized one widens the ring without lengthening the
    // fuse, which is the same trade every scaled creature already makes with its reach.
    std.debug.assert(FROST_FUSE * 1.7 > FROST_R * SCALE + foe.HERO_R); // WALK_SPEED
    // …and the cast in front of it still has to be readable on its own, before the fuse is even lit.
    std.debug.assert(FROST_WIND >= foe.TELL_MIN);
    // THE RAISE IS THE LONGER TELL OF THE TWO, because it is the move with the bigger consequence.
    std.debug.assert(RAISE_WIND > FROST_WIND + FROST_CAST_DUR);
    // …and it may not be spendable twice inside its own opening, or the punish window is not one.
    std.debug.assert(RAISE_CD > RAISE_WIND + RAISE_DUR + RAISE_RECOVER);
    // The frost carries NO physical at all — an element with one source in the world has to arrive as
    // itself, and a mixed blow would read as an ordinary hit with a blue flash on it.
    std.debug.assert(FROST_HIT.dmg == 0 and FROST_HIT.elem.at(.cold) > 0);
    // …and it reaches for a body from further off than it throws ice at one, or there is ground it will
    // defend that it cannot fight on.
    std.debug.assert(RAISE_R > FROST_R_MIN);
    // **THE RANGE IT WANTS TO STAND AT MUST SIT INSIDE THE RANGE IT CAN CAST FROM.** Two independently authored
    // bands (`WANT_*` for the drift, `FROST_R_*` for the throw) that only happen to overlap is a creature that
    // walks to the one place it cannot use its own move — `A MOVE THAT CANNOT LAND IS NOT A DECISION`, arrived
    // at from the movement's side instead of the attack's.
    std.debug.assert(WANT_MIN >= FROST_R_MIN and WANT_MAX <= FROST_R_MAX);
    std.debug.assert(WANT_MIN < WANT_MAX);
    // …and it must WANT to stand outside the ring it lays at his feet, or it drops one on itself.
    std.debug.assert(WANT_MIN > FROST_R * SCALE);
}

/// Per necromancer. Sized off the raise's own bloom, which is the worst burst it has — the frost's ring
/// lays fewer motes over a longer clock.
const NPART = 72;
const RAISE_BLOOM: u32 = 40;
const FROST_BLOOM: u32 = 30;
/// The ring going off. NAMED and asserted like the other two: as a literal `34` inside `burst` it was the one
/// emitter of the three that nothing checked against the pool.
const FROST_SHARDS: u32 = 34;
comptime {
    // **ONE BURST MUST BE SMALLER THAN THE POOL** — at exactly `parts.len` the head lands back where it
    // started and `floorBurst`'s walk reads as empty. Arithmetic over every emitter's worst frame, not a round
    // number that looked big enough.
    std.debug.assert(RAISE_BLOOM < NPART and FROST_BLOOM < NPART and FROST_SHARDS < NPART);
}

/// THE DRAGGING HEM (owner's call). It is NOT A BONE — it rides the ROOT through a lag matrix, exactly as
/// the shield rides a wrist and the delver's mound is built in world space. Cloth on the ground does not
/// travel with the body that is wearing it: it is left behind and hauled after, so the whole read is that
/// the hem's lean OPPOSES the direction of travel and then OVERSHOOTS its rest and settles back onto it
/// (the reactions law, on cloth).
const HEM_DRAG = 15.0; // deg the skirt is hauled back at a full walk
const HEM_EASE = 6.5; // how fast the lean chases the travel — slow, it is heavy wet cloth
const HEM_SETTLE = 3.4; // …and the spring that carries it past its rest on the way back
const HEM_SWAY = 2.2; // deg it swings side to side on the stride, a beat behind the pelvis

const State = enum { idle, drift, raise_wind, raise_up, frost_wind, frost_cast, recover, stunlight, stunheavy, dead };

/// WHICH OF THE TWO IT LAST SPENT. Its own type rather than a bool, because the recovery reads it through an
/// exhaustive switch — a third move then cannot be added without saying how long its opening is.
const Spent = enum { raise, frost };

/// Pure, so it is testable without a world. **THE RAISE OUTRANKS THE FROST WHENEVER IT IS OFFERED** — a
/// body on the ground is a decision with a clock on it and the ice is always there to throw. `keep` is the
/// answer that is neither: it is holding its distance with nothing worth spending.
const Choice = enum { raise, frost, keep, hold };
fn classify(dist: f32, hasBody: bool, raiseReady: bool, frostReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (hasBody and raiseReady) return .raise;
    if (frostReady and dist >= FROST_R_MIN and dist <= FROST_R_MAX) return .frost;
    return .keep;
}

/// WHERE IT WANTS TO STAND. It has no melee, so being close is only ever a mistake it is trying to correct.
const WANT_MIN: f32 = 8.0;
const WANT_MAX: f32 = 15.0;
const DRIFT_DUR: f32 = 0.9; // …and it re-decides on its own clock rather than steering every frame

/// A CORPSE THIS CREATURE IS HOLDING OPEN, stamped by the game (`game.markVigil`) — `Leash`'s law: the
/// creature reads the field and never reaches out for the state. Null is the ordinary case and it means
/// there is nothing on the ground worth standing over.
///
/// It is a POINT and an INDEX INTO NOTHING: what the necromancer needs to know is where to face and whether
/// there is anything at all. WHICH body it is belongs to the game, which is the only thing that can see
/// across two groups (the archers' `Line` and the warriors' `Muster` are different arrays of different
/// types), and the game is also the only thing that can put one back on its feet.
pub const Vigil = struct {
    at: ?rl.Vector3 = null,

    pub fn any(self: *const Vigil) bool {
        return self.at != null;
    }
};

/// THE RING ON THE GROUND, with its own clock. On the NECROMANCER rather than on the group because it is a
/// thing this caster laid and its blow is billed through this caster's `heroHit` — but its LIFE is its own,
/// which is what makes killing the caster afterwards no answer at all.
const Sigil = struct {
    at: rl.Vector3 = mathx.zero3,
    /// Seconds left on the fuse. Zero is no sigil; it is set to `FROST_FUSE` at the cast and counts down.
    left: f32 = 0,
    /// How long the burst has been playing, for the FX to ring out on — an effect's phase is its own decay
    /// and never a clock beside it (the knight's landing ring).
    blew: f32 = mathx.LONG_AGO,

    fn live(self: *const Sigil) bool {
        return self.left > 0;
    }
    /// **0 AT THE CAST, 1 AT THE BURST** — what the ring on the ground is drawn off, so the picture and the
    /// fuse are one number and cannot disagree about how long is left.
    fn fill(self: *const Sigil) f32 {
        return mathx.clampF(1.0 - self.left / FROST_FUSE, 0, 1);
    }
};

pub const Model = struct {
    bone: [N]rl.Mesh,
    hem: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("necro material");
        mat.shader = shader;
        var bone: [N]rl.Mesh = undefined;
        bone[ROOT] = pelvisMesh();
        bone[SPINE] = abdomenMesh();
        bone[CHEST] = chestMesh();
        bone[NECK] = neckMesh();
        bone[SKULL] = helmMesh();
        bone[HIPL] = thighMesh();
        bone[KNEEL] = shankMesh();
        bone[ANKL] = archermod.footMesh(1.0, 211);
        bone[HIPR] = thighMesh();
        bone[KNEER] = shankMesh();
        bone[ANKR] = archermod.footMesh(-1.0, 214);
        bone[SHL] = sleeveMesh();
        bone[ELL] = forearmMesh();
        bone[WRL] = handMesh();
        bone[SHR] = sleeveMesh();
        bone[ELR] = forearmMesh();
        bone[WRR] = handMesh();
        bone[STAFF] = staffMesh();
        return .{ .bone = bone, .hem = hemMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Necro) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        // THE HEM IS NOT A BONE — see `HEM_DRAG`. Drawn off the root with the drag on top of it, so it is in
        // both passes and the shadow it casts is the one you can see.
        rl.drawMesh(self.hem, self.mat, k.hemXf());
    }
};

pub const Necro = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS (`combat.Root`), stamped from outside like the leash's eyes. It never leaves the
    /// ground, so the grip holds it unconditionally — the ogre's and the Rooted's arrangement.
    root: combat.Root = .{},
    /// …and THE HERO'S SHIELD (`game.markParry`). Declared because the contract's fold keys off the field,
    /// and read by nothing: **neither of its moves is parryable and that is a decision** — see `parryable`.
    parry: foe.Parry = .{},
    /// …and WHAT IT IS STANDING OVER (`game.markVigil`), which is the one thing about this creature that
    /// cannot be seen from inside its own file.
    vigil: Vigil = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    raiseCd: f32 = 0,
    frostCd: f32 = 0,
    /// **THE BODY IT RAISED THIS FRAME** — a one-frame flag (`justDied`'s rule), reset at the TOP of
    /// `update` and read by the game after it. The creature cannot do the raising itself: the body is in
    /// another group, in another array, of another type.
    raised: bool = false,
    /// Where it was standing when it did, which is what the game matches a corpse against — the point the
    /// vigil was stamped with, latched at the CAST so a body that finished falling mid-gather is still the
    /// one that comes up.
    raiseAt: rl.Vector3 = mathx.zero3,
    /// WHICH MOVE IT LAST SPENT, latched at the moment it lands — the recovery's own length is read off this
    /// and nothing else. See `recoverDur` for what inferring it from a cooldown cost.
    spent: Spent = .frost,
    sigil: Sigil = .{},
    /// **A RING WENT INTO THE GROUND THIS FRAME** — a one-frame edge (`justDied`'s law), reset at the TOP of
    /// `update`. As a window on the fuse's own clock (`left > FROST_FUSE - 0.05`) it read true for three frames
    /// running at 60 fps, so the pad and the frame shake fired three times for one cast.
    laid: bool = false,
    /// This frame's blow ON the hero, and WHERE IT CAME FROM. The pair is why this creature does not use
    /// `foe.groupBlow`: that one reports the CREATURE's `pos` as the origin, and the frost's origin is the
    /// ring in the ground twelve metres away from it.
    heroHit: ?combat.Hit = null,
    hitFrom: rl.Vector3 = mathx.zero3,
    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,
    parried: bool = false,

    // posture channels (degrees), resolved by the state and read by pose()
    staffSh: f32 = STAFF_CARRY_SH,
    staffEl: f32 = STAFF_CARRY_EL,
    staffAbd: f32 = STAFF_CARRY_ABD,
    staffTilt: f32 = STAFF_CARRY_TILT,
    castSh: f32 = FREE_CARRY_SH,
    castEl: f32 = FREE_CARRY_EL,
    castAbd: f32 = FREE_CARRY_ABD,
    bodyLean: f32 = 6.0,
    twist: f32 = 0,
    headPitch: f32 = 4.0,
    headYaw: f32 = 0,
    /// THE HEM'S OWN LEAN, and its velocity — a spring, because cloth that eases to a stop glides and cloth
    /// that overshoots and settles has weight (the reactions law).
    hemLean: f32 = 0,
    hemVel: f32 = 0,

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
    /// THE WAY ROUND WHAT IS IN FRONT OF IT (`foe.Nav`), stamped by the game. It faces the hero while it
    /// backs away, so it reads `along` and not `aim` — the kobold's and the shade's reading.
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    /// The body's own trickle — the cast gather, and `foe.dissolveMotes`, which reads this field by name.
    fxAccum: f32 = 0,
    /// **AND THE RING'S OWN, BECAUSE THE RING IS NOT THE BODY.** Three emitters were sharing `fxAccum`: the
    /// gather, the sigil's creep and the dissolve. Any two of them live in one frame (cast the ice, then start a
    /// raise; or die while the fuse burns) and each `while` loop drains whatever the other had just added — the
    /// rates summed but the SHAPES came out split arbitrarily between them, so a corpse visibly stopped shedding
    /// bone while a ring of its own was counting down. A separate accumulator per independent effect.
    sigAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    /// The dragging hem's own matrix — not a bone, so not in `xf`, but chained in `pose` with them all the same.
    hemMat: rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Necro {
        var k = Necro{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 68041.0, 23);
        k.raiseCd = 0.4 + seed * 1.1; // stagger a pair of them out of lockstep
        k.frostCd = 0.9 + seed * 1.3;
        k.pose();
        return k;
    }

    pub fn centerWorld(self: *const Necro) rl.Vector3 {
        return foe.bodyPoint(self.pos, archermod.CENTER_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Necro) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Necro) f32 {
        return BODY_R * self.scale;
    }
    /// The HELM's own frame — the archer's skull mark, on a head that hangs a long way forward through a
    /// gather and drops through a flinch. A height off the feet would leave the mark in the air over it.
    pub fn lockPoint(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], archermod.LOCK_AT);
    }
    pub fn topWorld(self: *const Necro) rl.Vector3 {
        return foe.bodyPoint(self.pos, archermod.TOP_F * H, self.scale, 0);
    }
    pub fn alive(self: *const Necro) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Necro) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Necro) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn flashFrac(self: *const Necro) f32 {
        return foe.flashFrac(self.flash);
    }
    /// It never leaves the ground: no hop, no leap, no blink. The one creature here with nothing the roots
    /// refuse outright — what they take from it is the walk, and it has nowhere to walk to anyway.
    pub fn airborne(self: *const Necro) bool {
        _ = self;
        return false;
    }
    pub fn soulValue(self: *const Necro) u32 {
        _ = self;
        return SOULS;
    }

    /// **IS IT CASTING** — read by the game to decide whether a raise is still in flight, and by nothing
    /// else. A stagger drops the cast with the whole gather spent, which IS the interrupt.
    pub fn casting(self: *const Necro) bool {
        return self.state == .raise_wind or self.state == .raise_up;
    }

    /// HOW FAR THROUGH THE GATHER IT IS, 0..1 — the picture of the tell, and the only thing the HUD or the
    /// harness may know about how close the raise is to landing.
    pub fn raiseFill(self: *const Necro) f32 {
        return switch (self.state) {
            .raise_wind => mathx.clampF(self.t / RAISE_WIND, 0, 1),
            .raise_up => 1.0,
            else => 0,
        };
    }

    fn fdir(self: *const Necro) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Necro, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    /// WHERE IT IS TRYING TO WALK, or null (`game.markWay`). **ONLY THE DRIFT** — a cast is committed and a
    /// bent heading under one aims the sigil at a wall.
    pub fn navWant(self: *const Necro, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero; // it is BACKING AWAY: where it wants to go is never where he is
        if (self.state != .drift) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    pub fn update(self: *Necro, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        // **CLEARED BEFORE THE `gone` BRANCH, NOT AFTER IT.** The ring outlives its caster, so this function
        // keeps billing a blow from a body that has left the field — and reset only on the live path, the
        // corpse's own branch returned the SAME hit every frame from the burst onward. Cold damage forever,
        // off one ring, silently: `justDied`'s law (a one-frame flag is reset at the TOP) applied to the one
        // creature whose blow can outlast it.
        self.heroHit = null;
        self.laid = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            self.tickSigil(dt, hero); // …AND THE RING IT LAID OUTLIVES IT. That is the whole of the move.
            return self.heroHit;
        }
        self.justDied = false;
        self.raised = false;
        self.parried = false;
        // THE ROOTS HAVE THE FEET (`foe.grip`) — it never leaves the ground, so the hold is unconditional.
        // The cast is untouched: a held necromancer raises the dead just fine, which is the trade for the
        // spell being the answer to everything that jumps.
        const grip = foe.grip(&self.root, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.raiseCd = mathx.maxF(0, self.raiseCd - dt);
        self.frostCd = mathx.maxF(0, self.frostCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
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
                self.setCarry(dt);
                if (self.t >= 0.20) self.decide(d);
            },
            .drift => {
                // IT WALKS BACKWARD WATCHING HIM — the eyes stay on the hero and the feet go where they are
                // told, which is `Nav.along`'s whole reason for existing beside `aim`.
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = WALK_SPEED * SPEED;
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.setCarry(dt);
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= DRIFT_DUR) self.decide(d);
            },
            .raise_wind => {
                // **IT TURNS TO THE BODY IT COMMITTED TO, NOT TO HIM** — the one move here besides the
                // knight's fall that looks away from the hero, and that IS the tell: a necromancer squaring
                // up to a corpse announces exactly what is about to happen and where. `raiseAt` and never
                // `vigil.at`: the spot is committed at the START of the gather (see `enter`), so a nearer
                // body falling mid-tell cannot swing 1.9 s of announcement onto somewhere else.
                self.faceToward(self.raiseAt, dt);
                const u = mathx.clampF(self.t / RAISE_WIND, 0, 1);
                self.setRaiseWind(u);
                self.gather(dt, u);
                if (self.t >= RAISE_WIND) self.enter(.raise_up);
            },
            .raise_up => {
                self.setRaiseUp(mathx.clampF(self.t / RAISE_DUR, 0, 1));
                if (self.t >= RAISE_DUR) {
                    // The FLAG goes up here and the game does the raising: the corpse is another group's.
                    self.raised = true;
                    self.spent = .raise;
                    self.raiseCd = RAISE_CD;
                    self.bloom(self.raiseAt, RAISE_BLOOM);
                    sfx.world(.shade_gather, self.raiseAt);
                    self.enter(.recover);
                }
            },
            .frost_wind => {
                self.faceToward(hero, dt);
                self.setFrostWind(mathx.clampF(self.t / FROST_WIND, 0, 1));
                if (self.t >= FROST_WIND) self.enter(.frost_cast);
            },
            .frost_cast => {
                self.faceToward(hero, dt * 0.4);
                const u = mathx.clampF(self.t / FROST_CAST_DUR, 0, 1);
                self.setFrostCast(u);
                if (self.t >= FROST_CAST_DUR) {
                    self.lay(hero);
                    self.spent = .frost;
                    self.frostCd = FROST_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.setRecover(mathx.clampF(self.t / self.recoverDur(), 0, 1));
                if (self.t >= self.recoverDur()) self.decide(d);
            },
            .stunlight => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                self.easeNeutral(dt);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, archermod.DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.footfalls();
        self.tickHem(dt, moveSpeed);
        self.pose();
        self.tickSigil(dt, hero);
        self.tryHit(blade); // the hero's blade LAST, so a kill flags justDied for this frame's beat
        return self.heroHit;
    }

    /// Which opening it is standing in depends on which move it just spent, and the raise's is the long one:
    /// the reward for reading the longest tell in the game has to be bigger than the reward for reading the ice.
    ///
    /// **LATCHED, NOT INFERRED FROM THE COOLDOWN.** The first pass asked `raiseCd >= RAISE_CD - 0.001`, which is
    /// true on the frame the raise lands and FALSE on the very next one — the cooldown ticks down by `dt`. So
    /// the punish window the whole creature is built around collapsed to the frost's 0.70 s after a single
    /// frame, and nothing about the state machine looked wrong.
    fn recoverDur(self: *const Necro) f32 {
        return switch (self.spent) {
            .raise => RAISE_RECOVER,
            .frost => FROST_RECOVER,
        };
    }

    /// **THE RING'S OWN CLOCK.** Ticked from `update` whether the caster is alive, staggered, or a corpse:
    /// the thing is in the ground, and the only creature that could take it back out is the one that put it
    /// there. Its blow is billed through `heroHit`/`hitFrom` like any other, so a shield still gets to try
    /// and still gets no bearing to try it on.
    fn tickSigil(self: *Necro, dt: f32, hero: rl.Vector3) void {
        // Clamped like `Trail.age`: this runs for the whole life of the creature, and an unbounded accumulator
        // is a number that eventually stops meaning anything.
        self.sigil.blew = mathx.minF(self.sigil.blew + dt, mathx.LONG_AGO);
        if (!self.sigil.live()) return;
        self.sigil.left -= dt;
        // Rime creeping out along the ground as the fuse burns down — the sigil says how long is left in
        // the one channel a player looking at his own feet can read.
        self.creep(dt);
        if (self.sigil.left > 0) return;
        self.sigil.left = 0;
        self.sigil.blew = 0;
        self.burst();
        if (mathx.distXZ(self.sigil.at, hero) <= FROST_R * self.scale + foe.HERO_R) {
            // THE ORIGIN IS THE RING, NOT THE CASTER (the delver's burst): stood on the mark there is no
            // bearing, so the boards cannot answer it, and caught at the rim they can.
            self.bill(FROST_HIT, self.sigil.at);
        }
    }

    /// **A BLOW AND WHERE IT CAME FROM, SET TOGETHER OR NOT AT ALL.** `Rite.update` reports `hitFrom` as the
    /// blow's origin, so a future move that set `heroHit` and forgot the other half would bill a hit from the
    /// WORLD ORIGIN — which on this creature means a bearing the shield can answer, on the one blow that must
    /// never have one. One writer, so the pair cannot come apart.
    fn bill(self: *Necro, hit: combat.Hit, from: rl.Vector3) void {
        self.heroHit = hit;
        self.hitFrom = from;
        self.leash.noteCombat(); // a blow landed is a fight in progress — the tether waits
    }

    /// THE SPOT IS COMMITTED HERE AND NOWHERE ELSE — and it takes **THE GROUND AT THE MARK, WHICH IS THE
    /// TARGET'S OWN `pos.y`**, never the caster's.
    ///
    /// `pos.y` IS the ground under an actor (`game.groundActor` is its only writer), so the target's is exactly
    /// the height the ring has to be drawn at. The first pass used the CASTER's, on the argument that a foe's
    /// own datum is the safe one — which is true of a point on the creature's own body and false of a mark laid
    /// twelve metres away: on this sculpted patch the two grounds differ by more than the ring's 3 cm of
    /// clearance, and the whole band was depth-culled UNDER the terrain. The one move the player is meant to
    /// read off the floor drew nothing at all, twice.
    fn lay(self: *Necro, hero: rl.Vector3) void {
        self.sigil = .{ .at = v3(hero.x, hero.y, hero.z), .left = FROST_FUSE, .blew = mathx.LONG_AGO };
        self.laid = true;
        sfx.world(.wand_cast, self.sigil.at);
        self.mark(FROST_BLOOM);
    }

    fn enter(self: *Necro, s: State) void {
        self.state = s;
        self.t = 0;
        switch (s) {
            .raise_wind => {
                // **THE SPOT IS COMMITTED THE FRAME THE GATHER STARTS** (the delver's law). Latched here and
                // not at the turn, so the whole tell points at one place and `game.markVigil` holds THAT
                // body open rather than whichever is nearest by the end of it.
                self.raiseAt = self.vigil.at orelse self.pos;
                sfx.world(.shade_reach, self.pos);
            },
            .frost_wind => sfx.world(.wand_charge, self.pos),
            else => {},
        }
    }
    fn enterStun(self: *Necro, s: State) void {
        self.state = s;
        self.t = 0;
        self.homing = false;
    }
    fn enterDeath(self: *Necro) void {
        self.enterStun(.dead);
        self.justDied = true;
    }

    fn decide(self: *Necro, dist: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.drift);
        }
        self.homing = false;
        switch (classify(dist, self.vigil.any(), self.raiseCd <= 0, self.frostCd <= 0)) {
            .raise => self.enter(.raise_wind),
            .frost => self.enter(.frost_wind),
            .keep => {
                // It has nothing to spend, so it spends the time putting distance between them. Which way
                // round it circles is its own and it is SEEDED — a pair must not drift as one body.
                const f = self.fdir();
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                const out = mathx.scaleV(f, -1.0); // straight back, away from him
                const lat = mathx.scaleV(mathx.perpXZ(f), side);
                self.moveDir = if (dist < WANT_MIN)
                    mathx.normV(mathx.addV(out, mathx.scaleV(lat, 0.5)))
                else if (dist > WANT_MAX)
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

    /// **NEITHER MOVE IS PARRYABLE, AND BOTH FOR THE SAME REASON WRITTEN TWICE.** There is nothing to catch
    /// in a ring going off in the ground — its counter is the fuse and his feet — and there is nothing to
    /// catch in a raise, which never touches him at all: its counter is the sword, on the longest tell in
    /// the game. Written down rather than omitted, because a creature with no windows looks like a creature
    /// nobody got round to (`knight.parryable`'s note).
    fn parryable(self: *const Necro) ?f32 {
        _ = self;
        return null;
    }

    pub fn tryHit(self: *Necro, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 1.5, .heavy = 2.3 });
        self.chips(s.contact, s.dir, if (heavyBlow) 18 else 11, if (heavyBlow) 3.2 else 2.2);
        sfx.world(.bone_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, 20, 2.8);
                sfx.world(.bone_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    // Debug hooks for the --shot harness (force a beat in isolation).
    pub fn debugRaise(self: *Necro, at: rl.Vector3) void {
        self.vigil.at = at;
        self.raiseCd = 0;
        self.enter(.raise_wind);
    }
    pub fn debugFrost(self: *Necro) void {
        self.frostCd = 0;
        self.enter(.frost_wind);
    }
    pub fn debugLay(self: *Necro, hero: rl.Vector3) void {
        self.lay(hero);
    }
    pub fn debugStagger(self: *Necro, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Necro) void {
        self.enterDeath();
    }

    // ── POSTURE ───────────────────────────────────────────────────────────────────────────────────────

    fn setCarry(self: *Necro, dt: f32) void {
        const e = dt * 6.0;
        self.staffSh = approach(self.staffSh, STAFF_CARRY_SH, e);
        self.staffEl = approach(self.staffEl, STAFF_CARRY_EL, e);
        self.staffAbd = approach(self.staffAbd, STAFF_CARRY_ABD, e);
        self.staffTilt = approach(self.staffTilt, STAFF_CARRY_TILT, e);
        self.castSh = approach(self.castSh, FREE_CARRY_SH, e);
        self.castEl = approach(self.castEl, FREE_CARRY_EL, e);
        self.castAbd = approach(self.castAbd, FREE_CARRY_ABD, e);
        self.bodyLean = approach(self.bodyLean, 6.0, e);
        self.twist = approach(self.twist, 0, e);
        self.headPitch = approach(self.headPitch, 4.0, e);
        self.headYaw = approach(self.headYaw, 0, e);
    }

    /// **THE GATHER TRAVELS HARD, AND IT TRAVELS AWAY FROM WHERE IT ENDS** (the knight's tell lesson): the
    /// staff is driven DOWN and planted, the free hand is hauled up and back over the shoulder, and the
    /// whole trunk arches back off the body it is about to reach into. Every channel is moving for the whole
    /// 1.9 s, because a committed action that shows nothing is indistinguishable from one that never began.
    fn setRaiseWind(self: *Necro, u: f32) void {
        const e = mathx.smoothstep(0, 0.92, u);
        self.staffSh = lerpF(STAFF_CARRY_SH, RAISE_STAFF_SH, e);
        self.staffEl = lerpF(STAFF_CARRY_EL, RAISE_STAFF_EL, e);
        self.staffAbd = lerpF(STAFF_CARRY_ABD, RAISE_STAFF_ABD, e);
        self.staffTilt = lerpF(STAFF_CARRY_TILT, RAISE_STAFF_TILT, e);
        self.castSh = lerpF(FREE_CARRY_SH, RAISE_FREE_SH, e);
        self.castEl = lerpF(FREE_CARRY_EL, RAISE_FREE_EL, e);
        self.castAbd = lerpF(FREE_CARRY_ABD, RAISE_FREE_ABD, e);
        self.bodyLean = lerpF(6.0, RAISE_LEAN, e);
        self.twist = lerpF(0, RAISE_TWIST, e);
        // …AND THE HELM COMES DOWN ONTO THE BODY. It is looking at the thing it is raising, which is the
        // one channel that says WHERE as well as WHAT.
        self.headPitch = lerpF(4.0, RAISE_HEAD, e);
        self.headYaw = lerpF(0, RAISE_HEAD_YAW, e);
    }

    /// The turn: the free hand is thrown DOWN and out over the corpse and the trunk snaps forward over it —
    /// the opposite of everything the gather did, which is what makes 1.9 s of hauling resolve.
    fn setRaiseUp(self: *Necro, u: f32) void {
        const e = foe.swingCurve(u);
        self.castSh = lerpF(RAISE_FREE_SH, RAISE_THROW_SH, e);
        self.castEl = lerpF(RAISE_FREE_EL, RAISE_THROW_EL, e);
        self.castAbd = lerpF(RAISE_FREE_ABD, RAISE_THROW_ABD, e);
        self.bodyLean = lerpF(RAISE_LEAN, RAISE_THROW_LEAN, e);
        self.twist = lerpF(RAISE_TWIST, -RAISE_TWIST * 0.4, e);
        self.headPitch = lerpF(RAISE_HEAD, RAISE_HEAD + 12.0, e);
    }

    fn setFrostWind(self: *Necro, u: f32) void {
        const e = mathx.smoothstep(0, 0.9, u);
        // The staff comes UP off the ground — the one thing it does with the staff besides lean on it, and
        // the reason the two casts cannot be confused for one another at a glance.
        self.staffSh = lerpF(STAFF_CARRY_SH, FROST_STAFF_SH, e);
        self.staffEl = lerpF(STAFF_CARRY_EL, FROST_STAFF_EL, e);
        self.staffAbd = lerpF(STAFF_CARRY_ABD, FROST_STAFF_ABD, e);
        self.staffTilt = lerpF(STAFF_CARRY_TILT, FROST_STAFF_TILT, e);
        self.castSh = lerpF(FREE_CARRY_SH, FROST_FREE_SH, e);
        self.castEl = lerpF(FREE_CARRY_EL, FROST_FREE_EL, e);
        self.castAbd = lerpF(FREE_CARRY_ABD, FROST_FREE_ABD, e);
        self.bodyLean = lerpF(6.0, FROST_LEAN, e);
        self.twist = lerpF(0, FROST_TWIST, e);
        self.headPitch = lerpF(4.0, -8.0, e);
    }

    /// The throw: the free hand is driven forward and DOWN at the ground it is marking. It points at the
    /// spot — the sigil is committed to that ground, so the arm may not be pointing anywhere else.
    fn setFrostCast(self: *Necro, u: f32) void {
        const e = foe.swingCurve(u);
        self.castSh = lerpF(FROST_FREE_SH, FROST_THROW_SH, e);
        self.castEl = lerpF(FROST_FREE_EL, FROST_THROW_EL, e);
        self.castAbd = lerpF(FROST_FREE_ABD, FROST_THROW_ABD, e);
        self.bodyLean = lerpF(FROST_LEAN, FROST_THROW_LEAN, e);
        self.twist = lerpF(FROST_TWIST, -FROST_TWIST * 0.5, e);
        self.headPitch = lerpF(-8.0, 16.0, e);
    }

    fn setRecover(self: *Necro, u: f32) void {
        const e = mathx.smoothstep(0, 1, u);
        self.staffSh = lerpF(self.staffSh, STAFF_CARRY_SH, e * 0.22);
        self.staffEl = lerpF(self.staffEl, STAFF_CARRY_EL, e * 0.22);
        self.staffAbd = lerpF(self.staffAbd, STAFF_CARRY_ABD, e * 0.22);
        self.staffTilt = lerpF(self.staffTilt, STAFF_CARRY_TILT, e * 0.22);
        self.castSh = lerpF(self.castSh, FREE_CARRY_SH, e * 0.22);
        self.castEl = lerpF(self.castEl, FREE_CARRY_EL, e * 0.22);
        self.castAbd = lerpF(self.castAbd, FREE_CARRY_ABD, e * 0.22);
        self.bodyLean = lerpF(self.bodyLean, 6.0, e * 0.22);
        self.twist = lerpF(self.twist, 0, e * 0.22);
        self.headPitch = lerpF(self.headPitch, 4.0, e * 0.22);
        self.headYaw = lerpF(self.headYaw, 0, e * 0.22);
    }

    fn easeNeutral(self: *Necro, dt: f32) void {
        self.setCarry(dt * 1.4);
    }

    /// **THE HEM IS A SPRING, NOT AN EASE.** `want` is where the cloth would hang at this travel speed and
    /// the lean chases it through a damped spring, so it lags going out, OVERSHOOTS coming back and settles
    /// onto its rest — which is the whole difference between cloth and a cone bolted to a pelvis.
    fn tickHem(self: *Necro, dt: f32, speed: f32) void {
        const want = HEM_DRAG * mathx.clampF(speed / (heromod.WALK_SPEED * SPEED), 0, 1);
        const accel = (want - self.hemLean) * HEM_EASE * HEM_SETTLE;
        self.hemVel += accel * dt;
        self.hemVel *= mathx.maxF(0, 1.0 - HEM_EASE * dt); // the damping — under 1 or it rings forever
        self.hemLean += self.hemVel * dt;
    }

    /// The hem's matrix: the root's, with the drag laid on top. `rx` here is a lean BACKWARD in the rig's own
    /// frame, which is away from the facing — and it walks backward, so the cloth is hauled toward the hero, in
    /// front of it. That is the picture: a thing retreating inside a robe that will not keep up.
    ///
    /// **CHAINED IN `pose`, REPLAYED BY `draw`** — the rig's own law, and the hem is not exempt for being a
    /// matrix rather than a bone. `draw` runs TWICE a frame (the depth pass and the lit one), so solving it
    /// there did the work twice and, worse, left the shadow free to disagree with the silhouette the first time
    /// anything moved between the passes.
    pub fn hemXf(self: *const Necro) rl.Matrix {
        return self.hemMat;
    }

    fn chainHem(self: *Necro) void {
        const swayLag = HEM_SWAY * mathx.sinf(std.math.tau * self.phase - 0.9) * self.moving;
        self.hemMat = mul(mul(rx(self.hemLean), rz(swayLag)), self.xf[ROOT]);
    }

    fn stunAmount(self: *const Necro) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn pose(self: *Necro) void {
        const fs = self.scale * (1.0 - 0.7 * self.fade);
        const sink = -0.55 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();

        const m = self.moving * (1.0 - dk);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const latW = @abs(self.latB) * m;
        const sway = heromod.strafeSway(latW, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) +
            heromod.strafeProt(self.phase, self.latB, m);
        const dip = heromod.STRAFE_DIP * latW;

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.20 * H, dk);
        // NO PITCH AT THE ROOT while it is standing (the wanderer's law and the hero's): a root pitch turns
        // the LEGS and levers a planted foot through the floor. The whole lean is spine and chest below.
        const pitchBody = 18.0 * dk;
        // **A SCALE≠1 HUMANOID MUST SCALE ITS PELVIS HEIGHT** or the legs sink and it reads as a crouch —
        // and on a rig this tall that is a metre of it.
        const pelvY = if (dead) collapse else hipY + bob - dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(9.0 * dk), rx(pitchBody), ry(prot)),
            mul(tr(sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stun, dead, prot);
        self.xf = wx;
        self.chainHem(); // …and the hem, off the root that was just written
    }

    /// **THE UPPER BODY ARTICULATES TOO — LEGS ALONE ARE NOT A GAIT.** A contralateral swing on the free
    /// arm at full amplitude, the elbow flexing through the forward half only, the shoulder girdle
    /// counter-rotating against the pelvis (`prot`), a trunk nod twice a stride and a head that counter-rolls
    /// the lot — **with the LAGS STAGGERED**, or every joint peaks on one frame and the whole thing reads as
    /// one welded block however big the numbers are.
    ///
    /// **AND THE STAFF ARM IS THE OTHER HALF OF THE GAIT** (the wanderer's staff law): a leaned-on staff
    /// plants with the OPPOSITE foot, so that arm does not swing freely — it drives the pole down once a
    /// stride while the free arm swings for both of them.
    fn poseUpper(self: *Necro, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        // Seeded wonk — each stands a little crooked, and on a rig this tall a degree reads as a stoop.
        const wonk = (self.seed - 0.5) * 5.0;
        // It does not breathe. The bones BALANCE (the archer's rule), on two rates that never line up so the
        // loop never shows — and on this one the robe amplifies it, which is why the amplitude is smaller.
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const swayArg = self.elapsed * (0.42 + 0.20 * (0.5 + 0.5 * mathx.sinf(self.seed * 27.3))) + self.seed * 6.28;
        const swy = mathx.sinf(swayArg) * idleAmt;
        const swyLag = mathx.sinf(swayArg - 0.9) * idleAmt;

        // THE TRUNK NOD, twice a stride, and the lean the state asked for on top of it.
        const nod = 1.6 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const lean = self.bodyLean - 20.0 * stun + 24.0 * dk;
        setLocal(wx, SPINE, rest, mul3(
            rx(lean * 0.45 + nod + 0.7 * swy),
            ry(-0.35 * prot + self.twist * 0.4),
            rz(wonk * 0.5 + 1.0 * swy),
        ));
        setLocal(wx, CHEST, rest, mul3(
            rx(lean * 0.55 + nod * 0.6 + 0.5 * swyLag),
            ry(-0.5 * prot + self.twist * 0.6),
            rz(-wonk * 0.3 - 0.7 * swyLag),
        ));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.35 + 10.0 * dk - 7.0 * stun));
        // …AND THE HEAD COUNTER-ROLLS ALL OF IT.
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.65 + 18.0 * dk - 28.0 * stun),
            ry(self.headYaw - 0.5 * prot),
            rz(wonk - 1.2 * swyLag - 0.8 * nod),
        ));

        if (dead) {
            setLocal(wx, HIPL, rest, mul(rx(-58.0 * dk), rz(-3.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + 98.0 * dk));
            setLocal(wx, ANKL, rest, ry(7.0));
            setLocal(wx, HIPR, rest, mul(rx(-50.0 * dk), rz(3.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + 90.0 * dk));
            setLocal(wx, ANKR, rest, ry(-7.0));
        }

        const armStun = -66.0 * stun;
        // THE STAFF ARM: the pole is driven down once a stride, contralateral to the leg that is planting.
        // THE FREE ARM — the caster, and the LEFT one. Full contralateral amplitude, and the ELBOW FLEXES
        // THROUGH THE FORWARD HALF ONLY, which is the half of an arm swing that is actually a swing.
        const swing = 11.0 * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB);
        const fwdHalf = mathx.maxF(0, mathx.sinf(twoPi * self.phase));
        const castSh = self.castSh + swing + armStun - 30.0 * dk + 2.0 * swyLag;
        setLocal(wx, SHL, rest, mul3(rx(-castSh), ry(0), rz(self.castAbd + wonk * 0.4)));
        setLocal(wx, ELL, rest, rx(-self.castEl - 14.0 * fwdHalf * m));
        setLocal(wx, WRL, rest, rz(-5.0));

        // THE STAFF ARM, POSED LAST AND THE STAFF AFTER IT — the held slot's parent is THIS wrist and no
        // other (see the alias block), so the pole's matrix is only defined once this chain is written. The
        // pole is driven down once a stride, contralateral to the planting leg: a leaned-on staff plants with
        // the OPPOSITE foot, which is what makes it the other half of the gait instead of a carried prop.
        const plant = mathx.maxF(0, mathx.sinf(twoPi * self.phase + std.math.pi)) * m;
        const staffSh = self.staffSh - 7.0 * plant + armStun - 26.0 * dk + 1.6 * swy;
        const staffEl = self.staffEl - 5.0 * plant;
        setLocal(wx, SHR, rest, mul3(rx(-staffSh), ry(0), rz(-self.staffAbd - wonk * 0.4)));
        setLocal(wx, ELR, rest, rx(-staffEl));
        setLocal(wx, WRR, rest, rz(4.0));
        // WHERE THE STAFF POINTS IS AUTHORED IN THE WORLD, NOT IN THE WRIST (`hero.shieldFit`'s law and the
        // wanderer's): the fit BILLS THE ARM for its own flexion, so `staffTilt` means degrees the head leads
        // FORWARD OF PLUMB in the world, and a retune of the carry cannot lay the pole out flat like a lance.
        // The arm's own rx down this chain is `-(staffSh + staffEl)`, so that is what is BILLED BACK — and the
        // sign was measured, not argued: added instead, the test read the pole out at 93 degrees, horizontal
        // and pointing forward like a lance.
        setLocal(wx, STAFF, rest, staffFit(self.staffTilt - staffSh - staffEl));
    }

    pub fn draw(self: *const Necro, model: *const Model) void {
        model.draw(self);
    }

    /// The unlit pass — the sigil on the ground, the gather at the free hand, and the particles. Drawn here
    /// rather than in the mesh for the leechfly's reason: vertex alpha is a FIXED emissive channel and
    /// cannot brighten, and brightening is the whole cue.
    pub fn drawFx(self: *const Necro) void {
        self.drawSigil();
        self.drawGather();
        foe.drawParticles(&self.parts);
    }

    /// **THE RING SAYS HOW LONG IS LEFT IN ITS OWN PICTURE.** One ring at the full radius, so what is drawn
    /// is exactly the ground that is about to go — a ring that grew to its reach would promise safety at the
    /// rim it had not got to yet — and a SECOND, filling one inside it that is the fuse. It brightens as it
    /// closes: the last quarter of a second is the loudest thing on screen at the hero's feet.
    fn drawSigil(self: *const Necro) void {
        const r = FROST_R * self.scale;
        const at = self.sigil.at;
        // Clear of the ground by more than the terrain's own quantisation can wobble under it: laid coplanar,
        // every grain z-fights the turf it is sitting on.
        const y = at.y + 0.06;
        const grain = RUNE_GRAIN * self.scale;
        if (self.sigil.live()) {
            const f = self.sigil.fill();
            // THE RIM, at the full radius from the first frame: what is drawn is exactly the ground that is
            // about to go, and a ring that GREW to its reach would promise safety at a rim it had not got to.
            ringOfGrains(v3(at.x, y, at.z), r, grain * 0.62, mathx.withAlpha(RIME, 150));
            // …AND THE RUNES TAKE ONE BY ONE ROUND IT. `lit` is how many have caught; the LEADING one comes up
            // over its own share of the fuse rather than snapping on, so the ring never looks like it is
            // counting in steps — and the last of them lighting IS the blow.
            const march = f * @as(f32, @floatFromInt(RUNE_N));
            const lit = @floor(march);
            var i: i32 = 0;
            while (i < RUNE_N) : (i += 1) {
                const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RUNE_N)) * std.math.tau;
                const fi = @as(f32, @floatFromInt(i));
                const heat: f32 = if (fi < lit) 1.0 else if (fi < lit + 1.0) march - lit else 0.0;
                // A dark rune is still a rune: it is drawn at its own low level, or the ring appears to grow
                // round the circle instead of lighting up, and there is nothing left to count.
                const col = if (heat > 0.02) RIME_LT else RIME;
                const alpha: f32 = if (heat > 0.02) 130.0 + 125.0 * heat else 95.0;
                runeAt(v3(at.x, y + 0.008, at.z), a, r * RUNE_R, grain * (1.0 + 0.5 * heat), mathx.withAlpha(col, mathx.u8f(alpha)));
            }
            return;
        }
        // …AND THE BURST'S OWN RING RIDES ITS OWN DECAY, never a clock beside it (the knight's landing): it
        // starts at 0 the frame the fuse runs out and it is blind to what the caster is doing by then.
        const age = self.sigil.blew;
        if (age >= FROST_BURST_RING) return;
        const u = age / FROST_BURST_RING;
        const fade = (1.0 - u) * (1.0 - u);
        // The whole ring thrown OUTWARD past its own rim and thinning — the runes go with it, so what comes
        // apart is the thing that was standing there and not a new effect on top of it.
        ringOfGrains(v3(at.x, y, at.z), r * (1.0 + 0.38 * u), grain * (0.62 + 0.5 * u), mathx.withAlpha(RIME_LT, mathx.u8f(235.0 * fade)));
        var i: i32 = 0;
        while (i < RUNE_N) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RUNE_N)) * std.math.tau;
            runeAt(v3(at.x, y + 0.008, at.z), a, r * RUNE_R * (1.0 + 0.44 * u), grain * (1.5 - 0.6 * u), mathx.withAlpha(RIME_LT, mathx.u8f(255.0 * fade)));
        }
    }

    /// The light gathering in the free hand through a cast. Both moves get one and they are DIFFERENT
    /// COLOURS, because what the two do to you is different — see `RAISE_GLOW`.
    fn drawGather(self: *const Necro) void {
        const at = self.castPoint();
        switch (self.state) {
            .raise_wind, .raise_up => {
                const f = if (self.state == .raise_up) 1.0 else mathx.smoothstep(0.15, 1.0, self.t / RAISE_WIND);
                rl.drawSphereEx(at, 0.085 * self.scale * (0.4 + 0.6 * f), 7, 9, mathx.withAlpha(RAISE_GLOW, mathx.u8f(210.0 * f)));
            },
            .frost_wind, .frost_cast => {
                const f = if (self.state == .frost_cast) 1.0 else mathx.smoothstep(0.1, 1.0, self.t / FROST_WIND);
                rl.drawSphereEx(at, 0.075 * self.scale * (0.4 + 0.6 * f), 7, 9, mathx.withAlpha(RIME_LT, mathx.u8f(220.0 * f)));
            },
            else => {},
        }
    }

    /// WHERE A CAST LEAVES FROM — the free hand's fist, straight off the posed bone (the ogre's
    /// `clubLowWorld` law). Nothing about a spell is guessed from a yaw and a radius.
    pub fn castPoint(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[WRL], v3(0, FIST_Y, FIST_Z));
    }
    /// …and THE STAFF, as the segment it actually occupies — ferrule to head, measured off the mesh's own
    /// constants (the ogre's `clubLowWorld` law). Nothing about where the pole is may be guessed from a yaw.
    pub fn staffSeg(self: *const Necro) [2]rl.Vector3 {
        return .{
            foe.markOn(self.xf[STAFF], v3(0, FIST_Y - STAFF_DOWN, FIST_Z)),
            foe.markOn(self.xf[STAFF], v3(0, FIST_Y + STAFF_UP, FIST_Z)),
        };
    }
    pub fn staffTopWorld(self: *const Necro) rl.Vector3 {
        return self.staffSeg()[1];
    }

    // ── FX ────────────────────────────────────────────────────────────────────────────────────────────

    fn emit(self: *Necro, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }

    /// The gather's drip: motes falling INTO the hand rather than out of it, which is what a thing being
    /// taken up looks like (the souls drop's construction). Rate rises through the tell.
    fn gather(self: *Necro, dt: f32, u: f32) void {
        self.fxAccum += (10.0 + 26.0 * u) * dt;
        const at = self.castPoint();
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.35, 1.0) * 0.55 * self.scale;
            const p = v3(at.x + mathx.cosf(a) * rr, at.y + self.fxRng.range(-0.2, 0.5) * self.scale, at.z + mathx.sinf(a) * rr);
            // Solved to ARRIVE at the hand inside its own life — short lives bought back with RADIUS, since
            // `drawParticles` fades radius with alpha (the wand gather's law).
            const life = self.fxRng.range(0.20, 0.34);
            self.emit(p, mathx.scaleV(mathx.subV(at, p), 1.0 / life), life, self.fxRng.range(0.020, 0.042) * self.scale, 0.004, RAISE_GLOW, 0);
        }
    }

    /// The bloom at the body when it comes up — gold running DOWN into it, which is `foe.MOTE` rising put
    /// the other way round. It is sized to the BODY it is raising, not to the necromancer that raised it.
    fn bloom(self: *Necro, at: rl.Vector3, n: u32) void {
        const from = self.fxHead;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 1.0) * 1.15;
            self.emit(
                v3(at.x + mathx.cosf(a) * rr, at.y + self.fxRng.range(1.0, 2.2), at.z + mathx.sinf(a) * rr),
                v3(mathx.cosf(a) * -0.5, -self.fxRng.range(1.6, 3.2), mathx.sinf(a) * -0.5),
                self.fxRng.range(0.42, 0.78),
                self.fxRng.range(0.05, 0.10),
                0.006,
                RAISE_GLOW,
                -1.4, // NEGATIVE grav: it is driven DOWN into the ground it is pouring into
            );
        }
        // …ON THE CORPSE'S OWN GROUND, not the caster's — `floorBurst`'s whole reason, and on sculpted
        // terrain the two are metres apart.
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    /// The mark going down: a flat scatter of rime thrown out along the ground it has just claimed.
    fn mark(self: *Necro, n: u32) void {
        const from = self.fxHead;
        const at = self.sigil.at;
        const r = FROST_R * self.scale;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.1, 1.0) * r;
            self.emit(
                v3(at.x + mathx.cosf(a) * rr, at.y + 0.05, at.z + mathx.sinf(a) * rr),
                v3(mathx.cosf(a) * 0.7, self.fxRng.range(0.3, 0.9), mathx.sinf(a) * 0.7),
                self.fxRng.range(0.30, 0.60),
                self.fxRng.range(0.03, 0.06) * self.scale,
                0.008,
                FROST_MOTE,
                1.4,
            );
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    /// Rime creeping while the fuse burns. TEXTURE IS THINNED IN COUNT, not just in level (the audio law's
    /// sibling): a steady stream over a second and a third is a fog machine, so this is a trickle.
    fn creep(self: *Necro, dt: f32) void {
        self.sigAccum += 9.0 * dt;
        while (self.sigAccum >= 1.0) {
            self.sigAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.25, 1.0) * FROST_R * self.scale;
            const from = self.fxHead;
            self.emit(
                v3(self.sigil.at.x + mathx.cosf(a) * rr, self.sigil.at.y + 0.04, self.sigil.at.z + mathx.sinf(a) * rr),
                v3(0, self.fxRng.range(0.25, 0.7), 0),
                self.fxRng.range(0.35, 0.70),
                self.fxRng.range(0.018, 0.038) * self.scale,
                0.006,
                FROST_MOTE,
                0.5,
            );
            foe.floorBurst(&self.parts, from, self.fxHead, self.sigil.at.y);
        }
    }

    /// The ring going off: shards thrown UP and OUT off the ground, over the rim it has been drawing.
    fn burst(self: *Necro) void {
        const from = self.fxHead;
        const at = self.sigil.at;
        const r = FROST_R * self.scale;
        sfx.world(.shade_touch, at);
        var i: u32 = 0;
        while (i < FROST_SHARDS) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 1.05) * r;
            const s = self.fxRng.range(0.6, 1.0) * 4.4;
            self.emit(
                v3(at.x + mathx.cosf(a) * rr, at.y + 0.06, at.z + mathx.sinf(a) * rr),
                v3(mathx.cosf(a) * s * 0.45, self.fxRng.range(2.6, 5.4), mathx.sinf(a) * s * 0.45),
                self.fxRng.range(0.34, 0.62),
                self.fxRng.range(0.05, 0.11) * self.scale,
                0.012,
                FROST_SHARD,
                5.4,
            );
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    fn chips(self: *Necro, at: rl.Vector3, dir: rl.Vector3, n: u32, spd: f32) void {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.4, 1.0) * spd;
            self.emit(
                v3(at.x + self.fxRng.signed() * 0.06, at.y + self.fxRng.signed() * 0.06, at.z + self.fxRng.signed() * 0.06),
                v3(dir.x * s + mathx.cosf(a) * s * 0.5, self.fxRng.range(0.9, 3.0), dir.z * s + mathx.sinf(a) * s * 0.5),
                self.fxRng.range(0.28, 0.55),
                self.fxRng.range(0.02, 0.05) * self.scale,
                0.008,
                CHIP,
                6.4,
            );
        }
    }

    /// The hem sweeping the ground rather than a boot striking it — this thing is barefoot bone under a
    /// metre of wet cloth, so the footfall is a DRAG. At or under the fight's floor (the audio law): it is
    /// texture, and texture never competes with what is about to hit you.
    fn footfalls(self: *Necro) void {
        const ph = self.phase;
        const crossed = @floor(ph * 2.0) != @floor(self.prevPhase * 2.0);
        self.prevPhase = ph;
        if (!crossed or self.moving < 0.25) return;
        sfx.world(.step_soft, self.pos);
        const f = self.fdir();
        var i: u32 = 0;
        while (i < 4) : (i += 1) {
            const a = self.fxRng.angle();
            self.emit(
                v3(self.pos.x + self.fxRng.signed() * 0.26 * self.scale, self.pos.y + 0.03, self.pos.z + self.fxRng.signed() * 0.26 * self.scale),
                v3(-f.x * 0.5 + mathx.cosf(a) * 0.35, self.fxRng.range(0.15, 0.5), -f.z * 0.5 + mathx.sinf(a) * 0.35),
                self.fxRng.range(0.30, 0.55),
                self.fxRng.range(0.05, 0.10) * self.scale,
                0.22 * self.scale,
                DUST,
                2.2,
            );
        }
    }
};

fn approach(cur: f32, want: f32, e: f32) f32 {
    return lerpF(cur, want, mathx.clampF(e, 0, 1));
}

// ── THE RUNE RING ─────────────────────────────────────────────────────────────────────────────────────
//
// **AN ICY RUNE RING, AND IT IS BUILT OUT OF THE ONE PRIMITIVE THIS PASS IS KNOWN TO DRAW** (owner's call).
// Two earlier attempts drew nothing at all on the render: `rl.drawLine3D` is one pixel however close you stand,
// and a `drawTriangleStrip3D` annulus came back invisible beside PARTICLES that were landing on the same spot
// on the same frame — so the strip is not something to keep guessing at here. `drawSphereEx` is what
// `foe.drawParticles` uses and what demonstrably arrives, so the whole mark is made of it.
//
// **AND THE FUSE BURNS ROUND THE RING RATHER THAN FILLING IT.** A disc closing from the middle is a shape you
// have to be looking down at to read; runes LIGHTING ONE BY ONE round the rim is a countdown legible from any
// bearing the camera happens to be on, and it says how long is left in a way a brightness ramp cannot — you
// can COUNT the dark ones. When the last one takes, it goes off.
// **WHAT THE MARK COSTS, MEASURED AND LEFT ALONE** (`foe.drawParticles`' own note, arrived at differently). One
// live sigil is 46 grains plus 14 runes of 5 = 116 `drawSphereEx` calls at 4x6, about 5.6k CPU-transformed
// triangles a frame. Where the particle pool gets away with this because a slot is dead unless something emitted
// into it, this draws its full count for every frame a fuse is burning — so the bound is how many are actually
// casting, not how many are posted, and an encounter with two or three of them pays ~17k. It early-outs to
// nothing the moment no sigil is live or lately burst, which is the overwhelming majority of frames.
//
// Left as it is deliberately: the alternative is a real annulus MESH, which is exactly the geometry that came
// back invisible twice, and trading a legible tell for a few thousand triangles is the wrong way round.
const RUNE_N: i32 = 14;
/// Where the runes stand, as a fraction of the reach. Inside the rim, because the rim is what the blow claims
/// and a glyph drawn ON the boundary reads as safe ground.
const RUNE_R: f32 = 0.90;
/// The inscribed circle, as a dotted line of grains — the thing that makes the runes read as one ring rather
/// than as a scatter of marks. Its count is the arithmetic that keeps the dots touching at this radius.
const RING_DOTS: i32 = 46;
/// The size of one grain of the mark, in the creature's own scale — every dot and rune is a multiple of this,
/// so the whole sigil is retuned from one number rather than from six literals scattered down `drawSigil`.
const RUNE_GRAIN: f32 = 0.055;
/// How long the burst's own ring rings out for. Beside the constants it belongs to rather than adrift among
/// the drawing helpers, where it read as part of the ring geometry.
const FROST_BURST_RING: f32 = 0.34;

/// One rune: a short radial tick with a cross bar, both laid flat on the ground. Deliberately NOT a letter —
/// it has to read at a glance from a standing camera, and detail at this size is noise.
fn runeAt(at: rl.Vector3, ang: f32, r: f32, size: f32, col: rl.Color) void {
    const ca = mathx.cosf(ang);
    const sa = mathx.sinf(ang);
    // Along the radius…
    var i: i32 = -1;
    while (i <= 1) : (i += 1) {
        const rr = r + @as(f32, @floatFromInt(i)) * size * 0.9;
        rl.drawSphereEx(v3(at.x + ca * rr, at.y, at.z + sa * rr), size * 0.5, 4, 6, col);
    }
    // …and across it, which is what makes a tick a glyph.
    for ([_]f32{ -1.0, 1.0 }) |s| {
        rl.drawSphereEx(
            v3(at.x + ca * r - sa * s * size * 0.95, at.y, at.z + sa * r + ca * s * size * 0.95),
            size * 0.42,
            4,
            6,
            col,
        );
    }
}

/// The inscribed circle the runes stand on, as grains of ice.
fn ringOfGrains(at: rl.Vector3, r: f32, size: f32, col: rl.Color) void {
    var i: i32 = 0;
    while (i < RING_DOTS) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RING_DOTS)) * std.math.tau;
        rl.drawSphereEx(v3(at.x + mathx.cosf(a) * r, at.y, at.z + mathx.sinf(a) * r), size, 4, 6, col);
    }
}

// ── THE CARRY AND THE TWO CASTS, in degrees ───────────────────────────────────────────────────────────
//
// Sign is POSITIVE-IS-FORWARD on both shoulders — `poseUpper` negates on the way in, exactly as the
// warriors' does, because authored the obvious way round the arms hang behind him.

const STAFF_CARRY_SH = -14.0; // the pole is LEANED ON: the arm hangs and the hand is low on the shaft
const STAFF_CARRY_EL = -26.0;
const STAFF_CARRY_ABD = 9.0;
/// **180 IS PLUMB IN THE WORLD, and less than that rakes the head FORWARD** — the arm is billed for its own
/// flexion at the fit (see `poseUpper`), which is what makes this a world angle rather than a wrist angle.
/// The first pass read it as "degrees OFF plumb" and authored 12, which drove the whole 1.5 m of pole down
/// through the floor where nothing in the picture could show it was wrong. A walking staff stands near
/// upright, raked a little forward.
const STAFF_CARRY_TILT = 172.0;

const FREE_CARRY_SH = -6.0;
const FREE_CARRY_EL = -22.0;
const FREE_CARRY_ABD = 7.0;

// THE RAISE. Everything travels AWAY from where the turn takes it, and it travels for the whole 1.9 s.
const RAISE_STAFF_SH = 26.0; // the staff is driven DOWN and PLANTED, both hands committed to the ground
const RAISE_STAFF_EL = -12.0;
/// KEPT IN AGAINST THE BODY. At 22 the pole swung out on the abduction and crossed his own front diagonally,
/// which is the Bone Knight's sword failure on a staff: a planted pole stands beside the man, not across him.
const RAISE_STAFF_ABD = 8.0;
/// **THE TRUNK IS NOT BILLED BY THE FIT, ONLY THE ARM IS — so a pose that arches the spine has to pay for it
/// here.** `RAISE_LEAN` takes the chest back 22 degrees and the staff inherits every one of them, so the same
/// 180-is-plumb number that stands the pole up at the carry laid it out at nearly 50 degrees through the
/// gather. Solved against this pose's own trunk rather than nudged, and the measurement test pins it.
const RAISE_STAFF_TILT = 150.0;
const RAISE_FREE_SH = -128.0; // the free arm hauled up and back over the shoulder — the whole of the tell
const RAISE_FREE_EL = -58.0;
const RAISE_FREE_ABD = 34.0;
const RAISE_LEAN = -22.0; // it ARCHES BACK, which is what makes the fold forward read
const RAISE_TWIST = -26.0;
const RAISE_HEAD = 26.0; // the helm comes DOWN onto the body — the channel that says WHERE
const RAISE_HEAD_YAW = -14.0;
const RAISE_THROW_SH = 74.0; // and it is thrown down and OUT over the corpse
const RAISE_THROW_EL = -10.0; // THE ARM GOES LONG AT THE THROW (the warriors' law)
const RAISE_THROW_ABD = -8.0;
const RAISE_THROW_LEAN = 30.0;

// THE FROST. A smaller gather and a different SHAPE — the staff comes UP where the raise plants it, so the
// two tells are never one picture at a glance.
const FROST_STAFF_SH = -74.0;
const FROST_STAFF_EL = -34.0;
const FROST_STAFF_ABD = 16.0;
const FROST_STAFF_TILT = 138.0; // the head raked well forward, out over the ground it is marking
const FROST_FREE_SH = -86.0;
const FROST_FREE_EL = -66.0;
const FROST_FREE_ABD = 26.0;
const FROST_LEAN = -14.0;
const FROST_TWIST = -18.0;
const FROST_THROW_SH = 58.0; // driven forward and DOWN at the ground: it POINTS at the spot it is claiming
const FROST_THROW_EL = -8.0;
const FROST_THROW_ABD = -6.0;
const FROST_THROW_LEAN = 24.0;

// ── THE MESHES ────────────────────────────────────────────────────────────────────────────────────────

/// The staff is authored pointing UP off the grip in the wrist's frame (the warriors' kit convention), so
/// the fit FLIPS it. After it, `staffTilt` means degrees the head leads FORWARD of plumb in the world.
fn staffFit(tilt: f32) rl.Matrix {
    return mul(ry(180.0), rx(180.0 - tilt));
}

// **BOTH ENDS ARE SOLVED AGAINST THE BODY, not chosen.** The fist rides at `rest[WRR].y` = 0.485·H, which on
// this rig is 1.17 m off the ground, so: the ferrule is the drop that puts it ON the ground (a staff is being
// leaned on, and 0.30·H left it floating half a metre up), and the head is the rise that puts it just over the
// helm without becoming the read itself. The measurement test brackets both.
const STAFF_UP = 0.65 * H; // fist → the head of the staff, landing ~2.74 m: a hand over the crown
const STAFF_DOWN = 0.46 * H; // …and on down past the fist to the ferrule, which lands ~0.06 m: on the ground
const STAFF_SEGS = 7;
/// **A CURVED SHAFT DRAWS ITS CURL ONCE AND APPLIES IT EVERY SEGMENT** — re-rolled per segment it wanders,
/// and a wander made of straight capsules is a chain of elbows. The total arc is this TIMES the count, so
/// moving either the length or the count re-brackets the curl.
const STAFF_CURL = 0.055;

/// THE CROOKED STAFF (owner's call). It obeys the dead-wood law because that is what it is: **nothing dead
/// is straight and nothing ends in a point.** It leans off its own axis the whole way up, thickens and thins
/// unevenly, and it does NOT taper to a needle — the head is a blunt swelling of pale heartwood with the
/// frost caught in the split of it.
fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4409);
    const fz = FIST_Z;

    b.setMat(.bark);
    // The shaft, one curl applied every segment. Below the fist as well as above: a staff a hand is
    // gripping halfway up is a staff, and one that starts at the fist is a wand held wrong.
    const total = STAFF_UP + STAFF_DOWN;
    const seg = total / @as(f32, @floatFromInt(STAFF_SEGS));
    var prev = v3(0, FIST_Y - STAFF_DOWN, fz);
    var lean: f32 = -STAFF_CURL * @as(f32, @floatFromInt(STAFF_SEGS)) * 0.5;
    var i: i32 = 0;
    while (i < STAFF_SEGS) : (i += 1) {
        lean += STAFF_CURL;
        const wob = rng.range(-0.010, 0.010) * H; // wabi-sabi BETWEEN the joints, not along one
        const next = v3(
            prev.x + mathx.sinf(lean) * seg * 0.42 + wob,
            prev.y + seg,
            prev.z + mathx.cosf(lean * 0.7) * seg * 0.10 + wob * 0.5,
        );
        const ra = (0.0150 - 0.0008 * @as(f32, @floatFromInt(i))) * H * rng.range(0.93, 1.09);
        const rb = (0.0142 - 0.0008 * @as(f32, @floatFromInt(i))) * H * rng.range(0.93, 1.09);
        b.addCapsule(prev, next, ra, rb, 7, if (rng.float() < 0.34) propart.BARK_DK else propart.BARK_OLD);
        // A knot or a snapped stub every other joint or so — dead wood keeps what it lost.
        if (rng.float() < 0.42) {
            const a = rng.angle();
            const out = rng.range(0.030, 0.062) * H;
            const elb = v3(next.x + mathx.cosf(a) * out * 0.6, next.y + rng.range(0.004, 0.020) * H, next.z + mathx.sinf(a) * out * 0.6);
            b.addCapsule(next, elb, 0.0075 * H, 0.0062 * H, 6, propart.BARK_DK);
            // …and it DROOPS off its own line to a BLUNT snap of pale heartwood, never on to a needle tip.
            b.addCapsule(elb, v3(elb.x + mathx.cosf(a) * out * 0.5, elb.y - rng.range(0.014, 0.034) * H, elb.z + mathx.sinf(a) * out * 0.5), 0.0062 * H, 0.0058 * H, 6, propart.TIMBER);
        }
        prev = next;
    }
    // THE HEAD: a blunt swelling of pale heartwood, split, with the cold caught in the split. Not a crystal
    // bolted on — one substance for the whole spell (the wand's law), and this is where it lives at rest.
    b.addBlob(v3(prev.x, prev.y + 0.010 * H, prev.z), v3(0.030 * H, 0.040 * H, 0.028 * H), 4, 9, propart.TIMBER);
    b.setMat(.marble);
    b.addBlob(v3(prev.x + 0.004 * H, prev.y + 0.030 * H, prev.z), v3(0.016 * H, 0.024 * H, 0.014 * H), 3, 8, RIME_ALB);
    b.addBlob(v3(prev.x - 0.008 * H, prev.y + 0.016 * H, prev.z + 0.006 * H), v3(0.009 * H, 0.013 * H, 0.008 * H), 3, 7, RIME_ALB_LT);
    // The ferrule at the bottom — a blunt cap, because a cylinder is CAPLESS and an open end shows its
    // culled interior.
    b.setMat(.steel);
    const foot = v3(0, FIST_Y - STAFF_DOWN, fz);
    b.addCapsule(foot, v3(foot.x, foot.y + 0.030 * H, foot.z), 0.0150 * H, 0.0165 * H, 7, rgba(44, 42, 40, 255));
    return b.toMesh();
}

/// THE ROBE'S SHOULDERS AND CHEST. Cloth over a frame with nothing in it — the mass has to read as HANGING,
/// so nothing here is a box: a mantle is a CONE that flares as it falls (the wanderer's law), and a wide
/// flat slab across the shoulders reads as a pauldron pair however soft the colour.
fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(9111);
    b.setMat(.cloth);
    // The ribcage under it, narrow — this is the SKINNY half of the brief and it has to be legible through
    // the cloth or the height reads as bulk.
    b.addBlob(v3(0, -0.012 * H, 0), v3(0.072 * H, 0.082 * H, 0.056 * H), 4, 10, ROBE);
    b.addBlob(v3(0, 0.048 * H, 0), v3(0.082 * H, 0.052 * H, 0.060 * H), 4, 10, ROBE_LT);
    // **THE YOKE, and without it the arms hang in mid-air.** `restHumanoid` puts the shoulder joints at
    // ±`sx` = ±0.117·H while this chest is 0.072·H across, so there is a clear 0.045·H of daylight either side
    // between the torso and the top of a sleeve 0.023·H thick — the sleeves read as two tubes floating beside
    // the body. The yoke spans joint to joint and closes it, and it is the ONE place this creature may carry
    // width: a shoulder line is not a pauldron.
    const shx = SHOULDER_HALF * H;
    const shy = (0.818 - 0.760) * H; // the shoulder joints' own height in the chest's frame, off the scaffold
    b.addCapsule(v3(-shx, shy, 0), v3(shx, shy, 0), 0.030 * H, 0.030 * H, 8, ROBE);
    // The mantle: a SHORT, SHALLOW cape off the collar, barely proud of the chest under it. It flares by a few
    // centimetres and stops well above the waist — authored deeper it was a drum round the chest, and authored
    // WIDER it stood off as a shelf, which is the same failure read from below instead of from the side.
    skirt(&b, v3(0, 0.062 * H, 0), 0.058 * H, 0.082 * H, 0.082 * H, 9, ROBE_DK, &rng);
    // A fold of cloth thrown over the staff shoulder and left hanging down the back — the wabi-sabi is
    // BETWEEN the halves of him, not banded along one.
    b.addCapsule(v3(-0.088 * H, 0.052 * H, -0.014 * H), v3(-0.070 * H, -0.088 * H, -0.040 * H), 0.030 * H, 0.038 * H, 8, ROBE_DK);
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    // OVERLAPPED WELL PAST the chest above and the pelvis below: at their authored heights the three blobs
    // met edge to edge and the trunk read as a stack of plates with a step at every joint.
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.070 * H, 0.086 * H, 0.058 * H), 4, 10, ROBE);
    b.addBlob(v3(0, 0.048 * H, 0), v3(0.074 * H, 0.056 * H, 0.060 * H), 4, 9, ROBE);
    // THE CORD at the waist — the one warm note against a cold robe (`CORD`), and knotted off to one side
    // with both tails left hanging at different lengths.
    b.setMat(.leather);
    b.addCapsule(v3(-0.080 * H, -0.020 * H, 0), v3(0.080 * H, -0.024 * H, 0), 0.011 * H, 0.011 * H, 7, CORD);
    b.addCapsule(v3(0.052 * H, -0.026 * H, 0.050 * H), v3(0.062 * H, -0.120 * H, 0.054 * H), 0.008 * H, 0.006 * H, 6, CORD);
    b.addCapsule(v3(0.038 * H, -0.026 * H, 0.052 * H), v3(0.030 * H, -0.078 * H, 0.058 * H), 0.007 * H, 0.005 * H, 6, CORD);
    return b.toMesh();
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    // THE PELVIS IS THE BODY AND NOTHING ELSE. It carried a second skirt of its own in the first pass, which
    // put a cone inside the hem's cone: two rims a hand apart read as one thick bell, and the hem — the part
    // that is supposed to be the read — could not be told from the part that moves with the hips.
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.064 * H, 0.070 * H, 0.054 * H), 4, 10, ROBE);
    return b.toMesh();
}

/// **THE DRAGGING HEM.** Its own mesh because it is its own matrix (see `HEM_DRAG`): a long, uneven,
/// heavy-bottomed cone that reaches BELOW the sole plane, so the cloth is on the ground and the last of it
/// is trailing. It is the biggest single face on him, which is why it carries the darkest albedo in the
/// palette — the hot key plus the gamma lift turns any mid-dark value pale on a face this size.
fn hemMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(7717);
    b.setMat(.cloth);
    // From the hip down past the feet. `-0.030·H` is BELOW the sole plane on purpose: that is the drag, and a
    // hem stopping at the ankle is a dress.
    //
    // **NARROW AT THE TOP AND THE FLARE KEPT LOW.** Authored at 0.185·H across the rim off a 0.100·H waist it
    // came out a bell wider than the creature's own shoulders, which read as a chess pawn — the height went
    // into the skirt instead of into the body. So the fall is nearly straight for its upper two thirds and
    // only opens near the ground, which is what a heavy robe on a thin frame actually does.
    // **THREE RINGS, EACH STARTING AT THE LAST ONE'S RADIUS**, so the fall is continuous: two rings a hand
    // apart at mismatched radii left a visible SHELF halfway down, which reads as two garments.
    const top = 0.010 * H;
    const bot = -0.030 * H - REST[ROOT].y;
    const hip = -0.20 * REST[ROOT].y;
    const knee = -0.55 * REST[ROOT].y;
    skirt(&b, v3(0, top, 0), 0.060 * H, top - hip, 0.066 * H, 10, HEM, &rng); // off the pelvis, near-straight…
    skirt(&b, v3(0, hip, 0), 0.066 * H, hip - knee, 0.080 * H, 11, HEM, &rng); // …opening slowly…
    skirt(&b, v3(0, knee, 0), 0.080 * H, knee - bot, 0.116 * H, 13, HEM, &rng); // …and the flare on the ground
    // A longer TRAIN behind it — this is what actually reads as dragging, and it is off to one side because a
    // train that fanned evenly is a lampshade.
    b.addBox(
        v3(-0.018 * H, (knee + bot) * 0.5, -0.112 * H),
        v3(0.086 * H, 0, 0.010 * H),
        v3(0, (knee - bot) * 0.5, 0.026 * H),
        v3(0, 0, 0.042 * H),
        HEM,
    );
    // …and the rime the cloth has picked up off its own ground, caught in the folds at the very bottom.
    // A FEW PERCENT of the mass, sunk most of the way in: RELIEF IS SUBTLE.
    b.setMat(.marble);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const rr = 0.112 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, bot + rng.range(0.004, 0.040) * H, mathx.sinf(a) * rr),
            v3(rng.range(0.010, 0.022) * H, rng.range(0.006, 0.016) * H, rng.range(0.008, 0.018) * H),
            3,
            7,
            if (rng.float() < 0.4) RIME_ALB_LT else RIME_ALB,
        );
    }
    return b.toMesh();
}

/// A cone of cloth that FLARES as it falls, uneven round its rim.
///
/// **EACH PANEL IS A THIN WALL AT THE RIM, NOT A WEDGE OFF THE AXIS**, and getting that wrong is what made the
/// first pass a stack of barrels. `addBox` takes HALF-AXIS vectors, so a radial half-extent of `rBot/2` centred
/// at `rBot/2` spans the whole way from the axis out to the rim: every panel came out a solid pie slice and the
/// twelve of them a drum. The radial axis is the CLOTH'S THICKNESS and nothing else; what carries the panel
/// from the bottom rim up to the top one is the SLANT (`ay`), and the tangential axis is its width.
fn skirt(b: *Builder, c: rl.Vector3, rTop: f32, drop: f32, rBot: f32, sides: i32, col: rl.Color, rng: *mathx.Rng) void {
    const thick = 0.008 * H;
    var i: i32 = 0;
    while (i < sides) : (i += 1) {
        const a0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sides)) * std.math.tau;
        const a1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(sides)) * std.math.tau;
        const am = (a0 + a1) * 0.5;
        // WABI-SABI BETWEEN THE PANELS: each hangs to its own length and swings to its own radius, so the rim
        // is a ragged hem rather than a turned lampshade. Cut in AMPLITUDE, never in irregularity.
        const wob = rng.range(0.88, 1.12);
        const sag = rng.range(0.90, 1.10);
        const rb = rBot * wob;
        const fall = drop * sag;
        const mid = (rTop + rb) * 0.5;
        const half = (a1 - a0) * 0.5;
        b.addBox(
            v3(c.x + mathx.cosf(am) * mid, c.y - fall * 0.5, c.z + mathx.sinf(am) * mid),
            v3(mathx.cosf(am) * thick, 0, mathx.sinf(am) * thick), // the cloth's THICKNESS, radial
            v3(mathx.cosf(am) * (rTop - rb) * 0.5, fall * 0.5, mathx.sinf(am) * (rTop - rb) * 0.5), // the slant
            v3(-mathx.sinf(am) * mid * half * 1.25, 0, mathx.cosf(am) * mid * half * 1.25), // …and its width
            col,
        );
    }
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // Vertebrae, bare between the mantle and the helm — the one place the body under the robe is visible,
    // and on a rig this tall it is a long neck.
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const y = @as(f32, @floatFromInt(i)) * 0.014 * H;
        b.addBlob(v3(0, y, -0.002 * H), v3(0.014 * H, 0.008 * H, 0.014 * H), 3, 7, if (@mod(i, 2) == 0) BONE else BONE_DK);
    }
    return b.toMesh();
}

/// **THE BONE HELM** (owner's call). Not a bare skull and not a steel helm: bone WORKED into a helm — a
/// skullcap over the cranium, a brow ridge standing proud of it, a nasal down the middle and cheek plates
/// hanging either side, with the eye sockets left as HOLES. The hole is the one place a hard value break is
/// free (the wanderer's `HOOD_IN` law): it cannot blow out, and the contrast against the shell is the whole
/// read of a face at this distance.
fn helmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(5153);
    b.setMat(.plain);
    // The cranium under it. FLESH IS ROUND — and so is bone: no cubes anywhere on a head.
    b.addBlob(v3(0, 0.014 * H, 0.002 * H), v3(0.046 * H, 0.052 * H, 0.052 * H), 5, 11, BONE_DK);
    // The skullcap, a shade lighter and set a little askew — wabi-sabi BETWEEN the pieces.
    b.addBlob(v3(0.002 * H, 0.026 * H, 0), v3(0.050 * H, 0.046 * H, 0.054 * H), 5, 11, BONE);
    // THE BROW RIDGE. Proud, but only by a few percent of the mass's radius — sunk most of the way in.
    b.addCapsule(
        v3(-0.042 * H, 0.014 * H, 0.036 * H),
        v3(0.042 * H, 0.016 * H, 0.036 * H),
        0.013 * H,
        0.012 * H,
        8,
        BONE_LT,
    );
    // The nasal, down the centre line, stopping in a blunt end and not a point.
    b.addCapsule(v3(0.001 * H, 0.012 * H, 0.044 * H), v3(-0.001 * H, -0.026 * H, 0.040 * H), 0.008 * H, 0.010 * H, 7, BONE_LT);
    // The cheek plates, hung either side and at slightly different lengths.
    for ([_]f32{ -1.0, 1.0 }) |s| {
        const drop = rng.range(0.052, 0.070) * H;
        b.addCapsule(
            v3(s * 0.040 * H, 0.006 * H, 0.020 * H),
            v3(s * 0.036 * H, -drop, 0.024 * H),
            0.014 * H,
            0.011 * H,
            7,
            if (s > 0) BONE else BONE_DK,
        );
    }
    // A crest of short bone spurs over the crown, uneven and none of them ending in a needle.
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const z = 0.030 * H - @as(f32, @floatFromInt(i)) * 0.016 * H;
        const up = rng.range(0.014, 0.030) * H;
        b.addCapsule(
            v3(rng.signed() * 0.003 * H, 0.062 * H, z),
            v3(rng.signed() * 0.006 * H, 0.062 * H + up, z - 0.006 * H),
            0.009 * H,
            0.0075 * H,
            6,
            if (rng.float() < 0.5) BONE_LT else BONE,
        );
    }
    // THE EYES ARE HOLES. Near-black, sunk in, and the only hard value break on him.
    b.setMat(.plain);
    for ([_]f32{ -1.0, 1.0 }) |s| {
        b.addBlob(
            v3(s * 0.020 * H, -0.002 * H, 0.038 * H),
            v3(0.012 * H, 0.010 * H, 0.008 * H),
            3,
            8,
            rgba(7, 8, 10, 255),
        );
    }
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_THIGH * H, 0), 0.044 * H, 0.036 * H, 9, ROBE_DK);
    b.addDome(v3(0, 0, 0), v3(0, 1, 0), 0.044 * H, 9, ROBE_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.090 * H, 0), 0.034 * H, 0.028 * H, 9, ROBE_DK);
    // Bare shin bone below the robe — thin, and it is what makes the hem read as a hem and not as a plinth.
    b.setMat(.plain);
    b.addCapsule(v3(0, -0.085 * H, 0), v3(0, -heromod.SEG_SHANK * H, 0), 0.017 * H, 0.014 * H, 8, BONE_DK);
    return b.toMesh();
}

/// **THE SLEEVES ARE THE THINNEST THING ON HIM, and the first pass had them the fattest.** At 0.038·H of
/// radius each arm was 0.14 wide against a 0.26 chest, so the pair hung off the shoulders as bolsters and
/// turned a gaunt silhouette into a barrel — the pauldron failure the wanderer's note warns about, arriving as
/// a sleeve instead of a plate. A robe on a skeleton has almost nothing inside the cloth.
fn sleeveMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.024 * H, 0.026 * H, 0.024 * H), 4, 9, ROBE);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_UPARM * H, 0), 0.023 * H, 0.027 * H, 8, ROBE);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    // The sleeve flares to a cuff and then STOPS: the bone comes out of it, which is what makes the hand read
    // at all against a dark sleeve. The flare is a few centimetres, not a bell.
    b.addCylinder(v3(0, 0, 0), v3(0, -0.070 * H, 0), 0.027 * H, 0.034 * H, 8, ROBE);
    b.setMat(.plain);
    b.addCapsule(v3(0, -0.062 * H, 0), v3(0, -heromod.SEG_FOREARM * H, 0), 0.012 * H, 0.010 * H, 8, BONE_DK);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(2801);
    b.setMat(.plain);
    b.addBlob(v3(0, FIST_Y, FIST_Z), v3(0.019 * H, 0.023 * H, 0.017 * H), 4, 8, BONE);
    // Long thin fingers, none of them the same length and none ending in a point.
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const x = (-1.5 + @as(f32, @floatFromInt(i))) * 0.009 * H;
        const len = rng.range(0.030, 0.044) * H;
        const knuckle = v3(x, FIST_Y - 0.016 * H, FIST_Z + 0.012 * H);
        const mid = v3(x + rng.signed() * 0.002 * H, knuckle.y - len * 0.6, knuckle.z + 0.008 * H);
        b.addCapsule(knuckle, mid, 0.0050 * H, 0.0044 * H, 6, if (@mod(i, 2) == 0) BONE else BONE_LT);
        b.addCapsule(mid, v3(mid.x, mid.y - len * 0.4, mid.z - 0.004 * H), 0.0044 * H, 0.0042 * H, 6, BONE_DK);
    }
    b.addCapsule(
        v3(0.016 * H, FIST_Y - 0.006 * H, FIST_Z + 0.004 * H),
        v3(0.026 * H, FIST_Y - 0.026 * H, FIST_Z + 0.014 * H),
        0.0052 * H,
        0.0046 * H,
        6,
        BONE,
    );
    return b.toMesh();
}

// ── THE GROUP ─────────────────────────────────────────────────────────────────────────────────────────

const CAP = wf.MAX_PER_KIND;

pub const Rite = struct {
    model: Model,
    band: [CAP]Necro = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Rite {
        return .{ .model = Model.init(shader) };
    }
    /// The posted necromancers — never iterate the whole array, the tail is `undefined`.
    pub fn live(self: *Rite) []Necro {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Rite) []const Necro {
        return self.band[0..self.n];
    }

    pub fn reset(self: *Rite, m: *const wf.Map) void {
        foe.resetGroup(Necro, &self.band, &self.n, m, .necromancer);
    }
    pub fn setShader(self: *Rite, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Rite, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Rite) void {
        for (self.liveConst()) |*k| k.drawFx();
    }
    pub fn pierce(self: *Rite, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Rite) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Rite) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Rite) u32 {
        return foe.aliveCount(self.liveConst());
    }
    pub fn soulsDropped(self: *const Rite) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    /// ONE OF THEM PUT A RING IN THE GROUND THIS FRAME — a ONE-FRAME edge (`anyDied`'s shape), since a fuse
    /// being lit at your feet is the moment the move has to be felt as well as seen. Read off the creature's
    /// own `laid` flag and never off the fuse's remaining time, which is a WINDOW and fired three frames deep.
    pub fn anyLaid(self: *const Rite) bool {
        for (self.liveConst()) |*k| {
            if (k.laid) return true;
        }
        return false;
    }

    /// **NOT `foe.groupBlow`, AND THE REASON IS ONE FIELD.** That helper reports the CREATURE's `pos` as the
    /// blow's origin, which is right for everything that swings something — and wrong for the only blow in
    /// the game whose origin is a place rather than a body. The frost is billed from the RING, twelve metres
    /// from the caster, so the boards get no bearing to answer it on.
    pub fn update(self: *Rite, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*k| {
            if (k.update(dt, k.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&blow, h, k.hitFrom, k.threat.on);
        }
        return blow;
    }
};

// ── TESTS ─────────────────────────────────────────────────────────────────────────────────────────────

test "TALL AND SKINNY is two dials, and the RATIO is what either of them alone cannot say" {
    const scaffold = heromod.restHumanoid(heromod.HIP_HALF, heromod.SHOULDER_HALF, H);
    // TALL: over two and a third metres, and the tallest thing on two legs bar the ogre.
    try std.testing.expect(SCALE > archermod.SCALE);
    try std.testing.expect(SCALE * H > 2.3);
    // SKINNY: narrower than the shared scaffold at the shoulder AND at the hip. Measured off the rest pose
    // rather than off the constants, so a change to `restHumanoid` cannot pass this while breaking it — and
    // against the SCAFFOLD's own rest, never against the bare fraction, which is not a length at all.
    try std.testing.expect(REST[SHL].x < scaffold[SHL].x);
    try std.testing.expect(@abs(REST[HIPL].x) < @abs(scaffold[HIPL].x));
    // **AND THE RATIO IS THE CLAIM**, because either dial alone is satisfiable by the wrong creature: scaled
    // up on the scaffold's own width it is a big archer, and narrowed without the height it is a child. So
    // stature over shoulder SPAN, in world metres, against the archer it is standing next to — this thing is
    // TALLER and yet absolutely NARROWER across the shoulders than a creature 30 cm shorter.
    const mySpan = 2.0 * REST[SHL].x * SCALE;
    const archerSpan = 2.0 * scaffold[SHL].x * archermod.SCALE;
    try std.testing.expect(mySpan < archerSpan);
    try std.testing.expect((SCALE * H) / mySpan > (archermod.SCALE * H) / archerSpan);
    // The pelvis still sits at the SCAFFOLD's own fraction of stature — the scale carries the height, and a
    // hand-nudged pelvis puts the legs through the floor (`legChain` solves straight down from a hip).
    try std.testing.expectApproxEqAbs(scaffold[ROOT].y, REST[ROOT].y, 1e-5);
}

test "THE STAFF STANDS UP, ON ITS OWN SIDE, AND ITS FOOT IS ON THE GROUND — measured, not argued" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    var j: u32 = 0;
    while (j < 30) : (j += 1) _ = k.update(1.0 / 60.0, v3(0, 0, 40), 400, .{}); // let the carry settle
    const seg = k.staffSeg();
    const foot = seg[0];
    const head = seg[1];
    const crown = k.topWorld().y;
    std.debug.print(
        "\n  necro: crown {d:.2} | staff foot y {d:.2} head y {d:.2} | foot out {d:.2} head out {d:.2} | lean {d:.1} deg\n",
        .{
            crown,
            foot.y,
            head.y,
            mathx.lenXZ(mathx.subV(foot, k.pos)),
            mathx.lenXZ(mathx.subV(head, k.pos)),
            mathx.degrees(std.math.atan2(mathx.lenXZ(mathx.subV(head, foot)), head.y - foot.y)),
        },
    );
    // **IT STANDS UP.** The head is above the foot, which is the whole of "a staff and not a lance" — the
    // first pass had `staffFit` driving the entire pole DOWN the forearm, so 1.5 m of it was underground and
    // there was nothing in the picture at all.
    try std.testing.expect(head.y > foot.y);
    // Its FOOT is ON THE GROUND, near his own feet: this thing leans on the pole as it walks, and a ferrule
    // floating half a metre up is a staff being carried like a torch.
    try std.testing.expect(foot.y < 0.30);
    try std.testing.expect(mathx.lenXZ(mathx.subV(foot, k.pos)) < 0.90);
    // …and its HEAD is up past the shoulders and BARELY over the creature's own crown — a staff standing a
    // metre above the helm would be the read instead of the creature.
    try std.testing.expect(head.y > k.centerWorld().y);
    try std.testing.expect(head.y < crown + 0.20);
    // NEAR PLUMB, and never laid out flat: past about 35 degrees off vertical it stops being carried and
    // starts being pointed.
    const lean = mathx.degrees(std.math.atan2(mathx.lenXZ(mathx.subV(head, foot)), head.y - foot.y));
    try std.testing.expect(lean < 35.0);
    // …and the whole pole stays on the STAFF ARM'S side of the midline, so it never crosses the body it is
    // beside (the Bone Knight's sword lesson, one creature along).
    const side = mathx.headingDir(k.facing);
    const right = mathx.perpXZ(side);
    const footSide = foot.x * right.x + foot.z * right.z;
    const headSide = head.x * right.x + head.z * right.z;
    try std.testing.expect(footSide * headSide > 0);
}

test "…AND IT STAYS A STAFF THROUGH BOTH CASTS — the trunk's own lean is billed, or it becomes a lance" {
    const at = struct {
        fn lean(k: *Necro) f32 {
            const s = k.staffSeg();
            return mathx.degrees(std.math.atan2(mathx.lenXZ(mathx.subV(s[1], s[0])), s[1].y - s[0].y));
        }
    }.lean;
    const dt = 1.0 / 60.0;

    // THE RAISE. `RAISE_LEAN` arches the chest back 22 degrees and the pole inherits all of it, so the carry's
    // own 180-is-plumb number laid it out diagonally across his front. Planted, it must still stand.
    var r = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    r.debugRaise(v3(2, 0, 2));
    var t: f32 = 0;
    while (t < RAISE_WIND * 0.95) : (t += dt) {
        r.vigil.at = v3(2, 0, 2);
        _ = r.update(dt, v3(0, 0, 9), 400, .{});
    }
    const rSeg = r.staffSeg();
    std.debug.print("  necro raise: staff lean {d:.1} deg, ferrule y {d:.2}\n", .{ at(&r), rSeg[0].y });
    try std.testing.expect(rSeg[1].y > rSeg[0].y); // still the right way up
    try std.testing.expect(at(&r) < 34.0); // PLANTED, not pointed
    try std.testing.expect(rSeg[0].y < 0.45); // …and its foot is still near the ground

    // THE FROST, whose whole point is to be a DIFFERENT picture: the staff comes UP where the raise plants it,
    // so the two tells cannot be confused at a glance. A test, because that is a claim and not a taste.
    var f = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    f.debugFrost();
    t = 0;
    while (t < FROST_WIND * 0.95) : (t += dt) _ = f.update(dt, v3(0, 0, 9), 400, .{});
    const fSeg = f.staffSeg();
    std.debug.print("  necro frost: staff lean {d:.1} deg, ferrule y {d:.2}\n", .{ at(&f), fSeg[0].y });
    try std.testing.expect(fSeg[1].y > fSeg[0].y);
    // **THE FERRULE IS OFF THE GROUND**, which is the whole read: the raise leans on the pole and this one
    // lifts it. A margin, not a hair — two poses a couple of centimetres apart are one pose twice.
    try std.testing.expect(fSeg[0].y > rSeg[0].y + 0.30);
}

test "THE HEM REACHES THE GROUND AND PAST IT — that is what dragging means" {
    // The hem hangs off the ROOT, so its bottom in the rig's own frame must be BELOW the sole plane.
    const bot = -0.030 * H - REST[ROOT].y;
    try std.testing.expect(bot + REST[ROOT].y < heromod.SOLE_Y);
    // …and it must reach past the ankle, or the shin is bare down to the boot and there is no hem at all.
    try std.testing.expect(bot + REST[ROOT].y < REST[ANKL].y);
}

test "THE HEM IS A SPRING: it lags going out, and it OVERSHOOTS its rest coming back" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt = 1.0 / 60.0;
    // Walking: the lean builds toward the drag and does NOT arrive on the first frame.
    k.tickHem(dt, heromod.WALK_SPEED * SPEED);
    try std.testing.expect(k.hemLean > 0 and k.hemLean < HEM_DRAG * 0.5);
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) k.tickHem(dt, heromod.WALK_SPEED * SPEED);
    try std.testing.expect(@abs(k.hemLean - HEM_DRAG) < 1.5); // settled onto the travelling rest
    // He stops. A MASS IN MOTION OVERSHOOTS ITS REST AND SETTLES BACK ONTO IT — so somewhere on the way
    // home the lean must go PAST zero, which an ease can never do.
    var least: f32 = 999;
    t = 0;
    while (t < 2.5) : (t += dt) {
        k.tickHem(dt, 0);
        least = mathx.minF(least, k.hemLean);
    }
    try std.testing.expect(least < -0.05); // it went past
    try std.testing.expect(@abs(k.hemLean) < 1.0); // …and came back to rest
}

test "THE RAISE OUTRANKS THE FROST whenever a body is offered, and distance decides the rest" {
    // A corpse on the ground with the raise off cooldown beats everything, at any range in its ring.
    try std.testing.expectEqual(Choice.raise, classify(6.0, true, true, true));
    try std.testing.expectEqual(Choice.raise, classify(16.0, true, true, false));
    // No body, or the raise still cooling: the ice, inside its own band.
    try std.testing.expectEqual(Choice.frost, classify(6.0, false, true, true));
    try std.testing.expectEqual(Choice.frost, classify(6.0, true, false, true));
    // …and OUTSIDE that band it throws nothing. A move that cannot land is not a decision.
    try std.testing.expectEqual(Choice.keep, classify(FROST_R_MIN - 0.5, false, true, true));
    try std.testing.expectEqual(Choice.keep, classify(FROST_R_MAX + 1.0, false, true, true));
    // Nothing ready at all: it backs off, which is the only other thing it knows how to do.
    try std.testing.expectEqual(Choice.keep, classify(9.0, false, false, false));
    // Out of its senses entirely: it goes back to its post.
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, true, true, true));
}

test "THE SPOT IS COMMITTED: the sigil does not follow him, and it goes off where it was laid" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const stood = v3(4, 0, 5);
    k.debugLay(stood);
    try std.testing.expect(k.sigil.live());
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(stood, k.sigil.at), 1e-5);
    // He walks away. The ring stays exactly where it was drawn…
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var fired = false;
    var ranAt = mathx.zero3;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        ranAt = v3(stood.x + 40.0 * t, 0, stood.z);
        _ = k.update(dt, ranAt, 400, .{});
        if (k.heroHit != null) fired = true;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(stood, k.sigil.at), 1e-5);
    // …and it never touched him, because he was not standing on it.
    try std.testing.expect(!fired);
}

test "A WALK CLEARS THE RING and standing still does not — the counter is his feet" {
    const dt = 1.0 / 60.0;
    // Standing on the mark: it lands.
    var stay = Necro.spawn(v3(0, 0, 20), 0, 1.0, 0.2);
    const at = v3(0, 0, 0);
    stay.debugLay(at);
    var hit = false;
    var t: f32 = 0;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        _ = stay.update(dt, at, 400, .{});
        if (stay.heroHit != null) hit = true;
    }
    try std.testing.expect(hit);
    // …and the hit carries the RING as its origin rather than the caster twenty metres away, which is what
    // leaves the boards no bearing to answer it on (the zero-`fromDir` rule).
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(at, stay.hitFrom), 1e-5);

    // Walking off it from the centre at the hero's own walk: he clears it, with the radius plus his own
    // footprint to cover. This is the assert at the top of the file, played out through the real clock.
    var walk = Necro.spawn(v3(0, 0, 20), 0, 1.0, 0.2);
    walk.debugLay(at);
    var caught = false;
    t = 0;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        const he = v3(heromod.WALK_SPEED * t, 0, 0);
        _ = walk.update(dt, he, 400, .{});
        if (walk.heroHit != null) caught = true;
    }
    try std.testing.expect(!caught);
}

test "THE RING BILLS ITS BLOW ONCE, even from a caster that has left the field" {
    var k = Necro.spawn(v3(0, 0, 12), 0, 1.0, 0.2);
    const at = mathx.zero3;
    k.debugLay(at);
    k.debugKill();
    const dt = 1.0 / 60.0;
    var bills: u32 = 0;
    var t: f32 = 0;
    while (t < DEATH_DUR + DISS_DUR + FROST_FUSE + 1.5) : (t += dt) {
        if (k.update(dt, at, 400, .{}) != null) bills += 1;
    }
    // **EXACTLY ONE.** The corpse's own early-return path used to hand back the SAME `heroHit` every frame from
    // the burst onward — cold damage forever off one ring, and nothing in the state machine looked wrong.
    try std.testing.expectEqual(@as(u32, 1), bills);
}

test "THE RAISE'S OPENING IS THE LONG ONE, and it stays long past the frame it landed on" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    const hero = v3(0, 0, 9);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < RAISE_WIND + RAISE_DUR + 0.05) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expectEqual(State.recover, k.state);
    // Read a good few frames INTO the recovery, which is where the bug lived: the length was inferred from
    // `raiseCd`, and that ticks down by `dt`, so the whole punish window collapsed to the frost's after one frame.
    var n: u32 = 0;
    while (n < 20) : (n += 1) {
        k.vigil.at = null;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expectEqual(State.recover, k.state); // still standing in it…
    try std.testing.expect(RAISE_RECOVER > FROST_RECOVER * 1.5); // …and it IS the longer of the two
    // Run out the rest of it and it finally decides again.
    t = 0;
    while (t < RAISE_RECOVER) : (t += dt) {
        k.vigil.at = null;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expect(k.state != State.recover);
}

test "A FUSE LIT IS A ONE-FRAME EDGE — the pad is not struck three times for one cast" {
    var k = Necro.spawn(v3(0, 0, 9), 0, 1.0, 0.2);
    const dt = 1.0 / 60.0;
    k.debugFrost();
    var edges: u32 = 0;
    var t: f32 = 0;
    while (t < FROST_WIND + FROST_CAST_DUR + 0.5) : (t += dt) {
        _ = k.update(dt, mathx.zero3, 400, .{});
        if (k.laid) edges += 1;
    }
    // As a window on the fuse's own remaining time this read true for three frames running at 60 fps.
    try std.testing.expectEqual(@as(u32, 1), edges);
}

test "THE RING OUTLIVES THE CASTER — killing it after the cast does not un-cast it" {
    var k = Necro.spawn(v3(0, 0, 12), 0, 1.0, 0.2);
    const at = mathx.zero3;
    k.debugLay(at);
    k.debugKill();
    const dt = 1.0 / 60.0;
    var hit = false;
    var t: f32 = 0;
    // Long enough for the body to fall, dissipate and leave the field entirely — the sigil is still ticking.
    while (t < DEATH_DUR + DISS_DUR + FROST_FUSE + 0.4) : (t += dt) {
        _ = k.update(dt, at, 400, .{});
        if (k.heroHit != null) hit = true;
    }
    try std.testing.expect(!k.alive()); // it is gone…
    try std.testing.expect(hit); // …and the ring it laid still went off on him
}

test "THE FROST IS THE FIRST COLD IN THE GAME, and it arrives as cold and nothing else" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), FROST_HIT.dmg, 1e-6);
    try std.testing.expect(FROST_HIT.elem.at(.cold) > 0);
    try std.testing.expectApproxEqAbs(FROST_HIT.elem.at(.cold), FROST_HIT.elem.total(), 1e-6);
    // …and its own hide is what its element cannot touch: a creature you freeze with its own frost is one
    // whose whole identity the resistance sheet argues against.
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(FROST_HIT);
    try std.testing.expect(v.hp > HP_MAX - 8.0); // 75 resist, capped: a quarter of twenty-six
    // FIRE is the answer, as it is to every skeleton in the game.
    var f = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = f.hit(combat.Hit{ .dmg = 10, .elem = combat.elems(.{ .fire = 5 }) });
    try std.testing.expect(f.hp < HP_MAX - 16.0);
}

test "THE RAISE IS THE LONGEST TELL IT HAS, it is PLANTED for all of it, and it reports rather than acts" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    const hero = v3(0, 0, 9);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    const startedAt = k.pos;
    var t: f32 = 0;
    var raisedOn: f32 = -1;
    while (t < RAISE_WIND + RAISE_DUR + 0.2) : (t += dt) {
        k.vigil.at = body; // the game re-stamps this every frame
        _ = k.update(dt, hero, 400, .{});
        if (k.raised) raisedOn = t;
    }
    // It fired ONCE, at the end of the gather plus the turn, and not before.
    try std.testing.expect(raisedOn > RAISE_WIND);
    try std.testing.expect(raisedOn < RAISE_WIND + RAISE_DUR + 0.05);
    // PLANTED for the whole thing — the punish window is a body standing still, or it is not one.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(startedAt, k.pos), 1e-4);
    // …and it named the BODY, not itself: the game raises what the necromancer only points at.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(body, k.raiseAt), 1e-5);
    // The flag is a ONE-FRAME edge. A latch here would raise the same corpse sixty times a second.
    _ = k.update(dt, hero, 400, .{});
    try std.testing.expect(!k.raised);
}

test "INTERRUPTING THE GATHER SPENDS IT — a staggered necromancer raises nothing" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < RAISE_WIND * 0.8) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
    }
    try std.testing.expect(k.casting());
    k.debugStagger(true);
    try std.testing.expect(!k.casting());
    var raisedEver = false;
    t = 0;
    while (t < combat.FOE_HEAVY_STUN_DUR + 0.5) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
        if (k.raised) raisedEver = true;
    }
    try std.testing.expect(!raisedEver);
}

test "IT NEVER MELEES, AND IT NEVER CLOSES — it holds the range its ice works at" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const dt = 1.0 / 60.0;
    // The hero walks right up to it. With nothing to raise it must back off, never step in.
    const near = v3(0, 0, 1.2);
    var t: f32 = 0;
    var closest: f32 = 999;
    while (t < 6.0) : (t += dt) {
        _ = k.update(dt, near, 400, .{});
        closest = mathx.minF(closest, mathx.distXZ(k.pos, near));
    }
    // It has opened the gap rather than closed it.
    try std.testing.expect(mathx.distXZ(k.pos, near) > 1.2);
    // …and there is no state in it that deals a blow by reaching him: every hit it lands comes off a sigil.
    try std.testing.expect(k.heroHit == null or k.sigil.blew < 1.0);
}

test "IT IS FRAIL, AND THE PRICE SAYS IT IS THE PRIORITY TARGET" {
    // Softer than either skeletal warrior and worth more than both: what it costs you is time, not HP.
    try std.testing.expect(HP_MAX < 92.0);
    try std.testing.expect(POISE_MAX < 15.0); // …and it flinches off almost anything, so interrupts work
    try std.testing.expect(SOULS > 280);
    // The widest notice ring in the game: it opens the fight, from further off than the thing it raises.
    try std.testing.expect(AGGRO_R > archermod.AGGRO_R);
}

test "A CORPSE IS HELD OPEN WITHIN REACH AND NOWHERE ELSE, so walking the fight away is an answer" {
    // `RAISE_R` is the whole of the rule and it is a PLACE: the vigil is re-stamped off where the bodies
    // actually are, so nothing is reserved and nothing is remembered.
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    try std.testing.expect(!k.vigil.any());
    k.vigil.at = v3(3, 0, 3);
    try std.testing.expect(k.vigil.any());
    k.vigil.at = null;
    try std.testing.expect(!k.vigil.any());
    // …and it reaches for a body from further off than it throws ice, or there is ground it defends and
    // cannot fight on.
    try std.testing.expect(RAISE_R > FROST_R_MIN);
}
