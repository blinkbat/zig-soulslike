const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const heromod = @import("../play/hero.zig");
const wolf = @import("wolf.zig");
const wood = @import("../props/propwood.zig");
const knightmod = @import("knight.zig");

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

// THE FUNGAL DEER (owner's creature, owner's name) — a leggy stag with a LARGE FLOWER growing out of its back.
//
// **THE QUADRUPED RIG'S FOURTH USER**, and the second one to carry the florid bloom: the bone layout, rest
// chain, gait dials and limb solver come from `wolf.zig`, and the corolla — seven quills, seven tongues, the
// lit throat behind a ring of fangs — is the ravager's, moved off the head and onto the WITHERS. What it left
// behind is a real head: a muzzle, a jaw, ears, and a rack of antlers.
//
// **THE FLOWER IS NOT ITS FACE, IT IS ITS ARTILLERY.** Furled it lies along the spine and the animal is a deer.
// It RISES — that is the whole tell — opens, and spits a handful of spores straight up. They HANG in the air,
// drifting, for long enough to be read and walked out of; then they turn over and come down at you.
//
// **AND IT DOES NOT WANT TO BE NEAR YOU.** It keeps its band and backs off when you close. The antlers are what
// it does when backing off has stopped working — its own gap, its own clock, and never a read of him.

/// Height at the WITHERS. Over the ravager's 1.34 and leggier with it: the barrel is the same animal's, the
/// legs are longer, and the flower stands over the top of the hero when it rises.
pub const W: f32 = 1.46;

/// **A RANGED BODY SEES FURTHER THAN A BITING ONE** — twice the ravager's 11, because a volley thrown from
/// inside its own keep-band is the only thing this creature does at all.
pub const AGGRO_R: f32 = 22.0;
const HOME_R: f32 = 1.2;

const BODY_R: f32 = 0.46;
/// **IT HAS TO HOLD THE BLOOM AT BOTH ENDS OF ITS TRAVEL** (the ravager's lesson) — the flower is the WEAK
/// POINT and a weak point a blade cannot reach is not one. MEASURED off the posed rig and solved, not picked:
/// the bloom rides 1.66 m furled and stands to 2.30 m, so a centre at 1.39 m needs 1.05 m to reach the risen
/// one — and that is EXACTLY it, which is a sphere the flower leaves on the next pose. 1.12 is the same solve
/// with 0.07 m of daylight in it, and the barrel sits 0.44 m the other side of the centre. A quadruped's nose and hooves stay OUTSIDE, as the
/// wolf's do at 0.42 on a 1.12 body — a sphere that swallowed a 1.37 m neck would be a sphere you could hit
/// by swinging at open ground.
const HURT_R: f32 = 1.12;
const CENTER_F: f32 = 0.95;
/// **METRES OF `W` THE HURT SPHERE SITS FORWARD OF THE BODY'S OWN POSITION.** `wolf.restPose` puts the ROOT at
/// `HIP_Z` and the chest at `CHEST_Z`, and `wx[ROOT]` translates in Y ONLY — so the whole trunk hangs 0.84 W
/// FORWARD of `pos` and a ball over `pos` sits on the animal's tail. MEASURED: the withers came out 1.23 m in
/// front of the centre and outside a 1.12 m sphere, which on a body you have to chase is a front half no blade
/// answers. Half the trunk would be 0.42; 0.30 is what keeps the risen flower inside as well.
const BARREL_MID: f32 = 0.30;
const TOP_F: f32 = 1.62;

/// Tough in the barrel and nothing in the stalk — the ravager's arrangement, and the same reason: the fight is
/// break the stance, then burst the open throat.
const HP_MAX: f32 = 96.0;
/// **BETWEEN THE HERO'S TWO SWINGS, NOT UNDER BOTH.** His light is 10 poise and his heavy 22, so a light poke
/// may not interrupt the volley and a committed swing must.
const POISE_MAX: f32 = 14.0;
const STANCE_MAX: f32 = 44.0;
const RESISTS = combat.resists(.{ .fire = -45, .cold = 30, .lightning = 0, .chaos = 20 });

const SOULS: u32 = 210;

const DEATH_DUR: f32 = 1.25;
const DISS_DUR: f32 = 1.05;
const DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 0.85, .flake = PETAL_LT };
const SINK_DEPTH: f32 = 0.34;

const PARTS = 58;

// **THE VOLLEY.** The rise and the open ARE the wind-up — there is nothing else to read, and there does not
// need to be: it takes most of a second and the flower is a metre across at the end of it.

const SPIT_WIND: f32 = 0.95;
const SPIT_DUR: f32 = 0.22;
const SPIT_REC: f32 = 0.70;
const SPIT_COOL: f32 = 4.2;
/// Where in the puff the spores actually leave the throat, as a share of it.
const SPIT_RELEASE_K: f32 = 0.30;
/// **IT WILL NOT SPIT INTO YOUR FACE.** Inside this the flower is no use and the antlers are the answer, which
/// is what keeps the two moves off each other's ground.
const SPIT_MIN: f32 = 4.5;
const SPIT_MAX: f32 = 20.0;
pub const SPORES_PER_VOLLEY: usize = 5;

// **A BLOW YOU CAN SEE COMING FOR A SECOND AND A HALF.** The spore goes UP, hangs, and only then turns over.
// Everything about it is built so the answer is your feet: it is slow, it is bright, and the hang is long.

pub const SPORE_R: f32 = 0.20;
/// Seconds of the climb out of the throat, and how far up and out it carries.
const SPORE_RISE: f32 = 0.55;
const SPORE_UP: f32 = 2.1;
const SPORE_SPREAD: f32 = 1.5;
/// **THE HANG IS THE WHOLE POINT** (owner: they hover for a bit before homing in). Long enough to count them,
/// pick a direction and be somewhere else — a volley that turned over instantly would just be five arrows.
pub const SPORE_HANG: f32 = 1.55;
/// …and it BOBS while it waits, or five motes holding station read as a bug and not as a threat. **METRES OF
/// AMPLITUDE, AND THE RATE HAS TO BE IN THE STEP OR IT IS NOT**: added to `at.y` as `A·cos(wt)·dt` this is the
/// integral of the wave, not the wave — 0.16 m authored arrived as 0.02 m of wobble. The step carries `w`.
const SPORE_BOB: f32 = 0.16;
const SPORE_BOB_HZ: f32 = 1.3;
const SPORE_BOB_W: f32 = SPORE_BOB_HZ * std.math.tau;
/// **SLOWER THAN HE SPRINTS, AND THAT IS DELIBERATE.** `hero.SPRINT_SPEED` is 5.1, so a spore at 4.4 cannot
/// run him down in a straight line at all — it is a thing you must not stand still in front of, not a thing
/// that kills you for being outdoors.
pub const SPORE_HOME: f32 = 4.4;
/// Radians a second the homing steer may bend. Capped, so a ROLL beats it: at 2.2 it needs 1.43 s to reverse.
const SPORE_TURN: f32 = 2.2;
pub const SPORE_LIFE: f32 = 8.0;
/// Five of these land for 45 raw, under the bone knight's own overhead — and no volley ever lands whole.
pub const SPORE_HIT = combat.Hit{ .dmg = 3, .poise = 12, .elem = combat.elems(.{ .chaos = 6 }) };

comptime {
    std.debug.assert(SPIT_WIND >= foe.TELL_MIN);
    std.debug.assert(SPORE_HANG > SPORE_RISE);
    std.debug.assert(SPORE_LIFE > SPORE_RISE + SPORE_HANG);
    // It may never outrun him in a straight line, or the hang buys nothing.
    std.debug.assert(SPORE_HOME < heromod.SPRINT_SPEED);
}

// **THE ANTLERS, AND THEY ARE WHAT IT DOES WHEN IT IS CORNERED** (owner). Not a second attack it picks between:
// the flower is the creature, and this is the creature with its back to something.

const BUTT_WIND: f32 = 0.55;
const BUTT_STRIKE: f32 = 0.24;
const BUTT_RECOVER: f32 = 0.62;
const BUTT_COOL: f32 = 2.6;
/// Metres of forward drive across the strike. It puts its weight behind the rack; it does not leave the ground.
const BUTT_DRIVE: f32 = 1.05;
const BUTT_R: f32 = 1.70;
/// Where in the strike the crown arrives, as a share of it — the one frame the boards are asked about.
const BUTT_IMPACT_K: f32 = 0.45;
/// The cosine of the cone the rack covers: a head-down charge answers for what is in front of it, cos 62 deg.
const BUTT_FRONT_DOT: f32 = 0.47;
/// **NO LAUNCH AND A BIG SHOVE.** A stag puts you on your back foot, not in the air; the only thing in this
/// game that throws a man is a two-handed overhead.
const BUTT_HIT = combat.Hit{ .dmg = 20, .poise = 34, .stance = 12 };

/// **CORNERED IS TWO FACTS ABOUT WHERE TWO BODIES ARE, AND A CLOCK** (the LAW): he is inside the ring the
/// flower is useless in, AND the gap did not open this frame — it is backing off and not getting away. Held
/// for this long, the rack comes down. Never a read of what he is holding or pressing.
const CORNER_HOLD: f32 = 1.15;
const CORNER_R: f32 = BUTT_R + 1.1;
/// It drains faster than it fills, so breaking off for a moment genuinely spends the clock.
const CORNER_DECAY: f32 = 1.6;

comptime {
    std.debug.assert(BUTT_WIND >= foe.TELL_MIN);
    std.debug.assert(CORNER_R < SPIT_MIN);
    std.debug.assert(BUTT_R < CORNER_R);
}

/// **THE GATE IS MEASURED FROM THE QUARRY'S HIDE** (`wolf.triggerR`'s law): asked centre-to-centre a flat
/// radius is unsatisfiable on anything broad, because `env.resolveActor` holds the body `bodyR + its own` out.
pub fn buttR(quarryR: f32) f32 {
    return BUTT_R + quarryR;
}

// **THE BAND IT KEEPS.** A deer's whole plan is not being where you are. Inside `FLEE_R` it walks away from
// you; past `KEEP_R` it closes enough to throw. Between them it holds and spits.
const FLEE_R: f32 = 6.5;
const KEEP_R: f32 = 13.0;

comptime {
    std.debug.assert(FLEE_R < KEEP_R and KEEP_R < SPIT_MAX);
    std.debug.assert(SPIT_MIN < FLEE_R);
}

const TURN_RATE: f32 = 4.0;
const ACCEL: f32 = 8.5;
const GAIT_BLEND: f32 = 8.0;
/// **IT RUNS FROM YOU FASTER THAN IT WALKS AT YOU.** The flight is the animal; the approach is only bookkeeping.
const FLEE_SPEED: f32 = wolf.GALLOP_SPEED * 0.92;
const CLOSE_SPEED: f32 = wolf.TROT_SPEED * 1.15;

pub const SHOVE = foe.Push{ .light = 1.20, .heavy = 2.90 };
const SHOVE_DECAY: f32 = 6.0;

// **THE RIG.** Wolf's 27, and eleven more: the stalk out of the withers, the bloom on top of it, seven petals
// hung off the bloom, and a beam of antler on each side of a head this creature actually kept.
/// The corolla's count, and every bone after it is measured off it: written out it sat in five places.
const NPETAL = 7;

const STALK = wolf.N + 0;
const BLOOM = STALK + 1;
const PET0 = BLOOM + 1;
const ANTL = PET0 + NPETAL;
const ANTR = ANTL + 1;
const N = ANTR + 1;

const ROOT = wolf.ROOT;
const SPINE = wolf.SPINE;
const CHEST = wolf.CHEST;
const NECK = wolf.NECK;
const HEAD = wolf.HEAD;
const JAW = wolf.JAW;
const TAIL0 = wolf.TAIL0;
const TAIL1 = wolf.TAIL1;
const TAIL2 = wolf.TAIL2;
const EARL = wolf.EARL;
const EARR = wolf.EARR;

const PARENT = wolf.PARENT ++ [_]i32{ CHEST, STALK } ++ [_]i32{BLOOM} ** NPETAL ++ [_]i32{ HEAD, HEAD };

comptime {
    std.debug.assert(PARENT.len == N);
}

/// The reticle rides the BARREL and never the flower — on the bloom it would travel a metre and a half every
/// time the stalk rose (the ravager's own finding, and the same fix).
const LOCK_AT = v3(0, 0.30 * W, 0.10 * W);

// **THE STALK LEAVES THE WITHERS AND LEANS BACK OVER THE LOINS.** Furled, that is a hump along the spine and
// the animal reads as a deer with something growing on it; risen, it stands over the shoulders.
const STALK_UP: f32 = 0.62;
const STALK_BACK: f32 = 0.30;
/// **DEGREES FURTHER BACK THAN ITS OWN REST LEAN, AND IT IS SOLVED.** The STALK→BLOOM rest vector is already
/// 26 deg off plumb (`STALK_UP` against `STALK_BACK`), so a furl authored as an absolute angle folds the
/// flower the WRONG WAY: at +74 it laid over the animal's HEAD, 1.65 m in front of its own hip. 49 deg is
/// what puts the axis at 75 deg off plumb — lying back down the loins, which is where a furled thing on a
/// back belongs.
const FURL_DEG: f32 = 49.0;
/// …and how much of its own length the stalk takes back while furled, so the rise is a TELESCOPE and not only
/// a hinge. Solved against the sheath's own overlap in `buildStalk`: the bloom's collar hangs 0.35 W down the
/// bore, so anything under that never shows a gap.
const STALK_FURL_IN: f32 = 0.26;
const STALK_STRETCH: f32 = 0.16;

/// Degrees the head lowers and the rack comes forward across the charge. The crown has to arrive at chest
/// height on him or it is a nod: reared it rides at 1.9 m, and 64 degrees brings it into his column.
const BUTT_DUCK: f32 = 64.0;
const BUTT_LOAD: f32 = 26.0;
/// Fraction of `W` the body sinks loading the charge, and how far the forequarters drop into it.
const CROUCH: f32 = 0.10;
const GATHER_PITCH: f32 = 13.0;
const DRIVE_PITCH: f32 = 18.0;

/// Degrees of idle drift and how slowly it runs — `mathx.gutter`'s three incommensurate rates, so a standing
/// herd never falls into step.
const SWAY_DEG: f32 = 4.6;
const SWAY_RATE: f32 = 0.42;
/// …and how far the HEAD turns at him while it grazes. POSITION and BEARING only — the law.
const LOOK_DEG: f32 = 24.0;
const LOOK_RATE: f32 = 2.4;

/// Death, in two acts: the stalk gives out over the first third, then the barrel rolls off its legs.
const WILT_FOLD: f32 = 122.0;
const DEAD_ROLL: f32 = 70.0;
const DEAD_BUCKLE: f32 = 0.20;

// The bloom's own clock, 0 shut to 1 wide, out of range at both ends: a bud tightens before it bursts and a
// mass in motion overshoots its rest. The ravager's numbers, on the volley's clock instead of a leap's.
const CLAMP_BY: f32 = 0.15;
const BLOOM_CLAMP: f32 = 0.17;
/// **WIDE BEFORE ANYTHING LEAVES IT.** The release is at `SPIT_WIND + SPIT_DUR * 0.30`, so the burst has to
/// finish well inside the wind or the spores are in the air before the flower has said anything.
const OPEN_BY: f32 = 0.46;
const SETTLE_BY: f32 = 0.68;
const BLOOM_SNAP: f32 = 0.15;
const SHUT_BY: f32 = 0.75;
/// **A HEAVY STUN BLOWS IT OPEN** (the ravager's, and the reason the window is worth aiming for). A LIGHT
/// flinch leaves it shut.
const BLOOM_STUN: f32 = 1.06;
const SHIVER_DEG: f32 = 7.0;
const SHIVER_HZ: f32 = 9.5;
const WILT_DUR: f32 = 0.55;

comptime {
    std.debug.assert(CLAMP_BY < OPEN_BY and OPEN_BY < SETTLE_BY and SETTLE_BY < 1.0);
}

/// **THE OPEN BLOOM IS THE WEAK POINT** — 1.9x while it is wide. DAMAGE ONLY: `poise` and `stance` are left
/// alone, because `POISE_MAX` is solved to sit between the hero's two swings and a multiplier here would
/// quietly put a light poke through it.
const BLOOM_FRAIL: f32 = 0.90;

/// One petal. `ang` is degrees round the bloom's axis with 0 at the top; `bias` is degrees of fold this one
/// carries at every open value; `gain` is its share of the shared swing, so the ring never arrives as one plate.
const Petal = struct {
    bone: usize,
    ang: f32,
    root: f32,
    len: f32,
    wide: f32,
    bias: f32,
    gain: f32,
    /// Degrees the quill bends SIDEWAYS out of its own plane, progressively along the blade — what turns a
    /// wheel of seven spokes into a swirl. SMALL, because it is bought with radius.
    sweep: f32,
    notch: f32 = 0,
    notchAt: f32 = 0.5,
    /// Degrees it hangs by once it is dead. Uneven, because a wilted corolla is never a cone.
    sag: f32 = 0,
    /// **THE VARIATION IS BETWEEN THE SEVEN, NOT ALONG ONE** (AGENTS.md). 0 the dark, 1 the mid, 2 the bleached.
    tone: u8 = 1,
};

/// **HAND-AUTHORED, NOT STEPPED ROUND A CIRCLE** — a ring off `k/7 * 360` reads as a gear however good the
/// quill is. Gaps of 34 to 64 against a mean of 51, and no gap over 64 or the open corolla comes back with a
/// bald sector in it. The angles are the one thing `restPose` and `pose` must agree on, so they are a table.
const PETALS = [NPETAL]Petal{
    .{ .bone = PET0 + 0, .ang = 196, .root = 1.00, .len = 1.34, .wide = 1.16, .bias = 0, .gain = 1.10, .sweep = 13, .sag = 34, .tone = 1 },
    .{ .bone = PET0 + 1, .ang = 96, .root = 0.94, .len = 1.04, .wide = 0.98, .bias = -3, .gain = 0.95, .sweep = 9, .sag = 21, .tone = 0 },
    .{ .bone = PET0 + 2, .ang = 248, .root = 1.06, .len = 0.92, .wide = 0.93, .bias = 4, .gain = 1.01, .sweep = 16, .sag = 29, .tone = 1 },
    .{ .bone = PET0 + 3, .ang = 10, .root = 0.98, .len = 1.18, .wide = 1.05, .bias = -2, .gain = 1.04, .sweep = 7, .notch = 0.34, .notchAt = 0.68, .sag = 16, .tone = 2 },
    .{ .bone = PET0 + 4, .ang = 44, .root = 1.10, .len = 0.72, .wide = 0.82, .bias = 13, .gain = 0.84, .sweep = 11, .notch = 0.52, .notchAt = 0.44, .sag = 12, .tone = 0 },
    .{ .bone = PET0 + 5, .ang = 306, .root = 0.90, .len = 1.10, .wide = 1.00, .bias = -5, .gain = 0.99, .sweep = -8, .sag = 25, .tone = 1 },
    .{ .bone = PET0 + 6, .ang = 148, .root = 1.02, .len = 0.86, .wide = 0.88, .bias = 6, .gain = 0.92, .sweep = 14, .sag = 31, .tone = 2 },
};

comptime {
    var seen = [_]bool{false} ** N;
    for (PETALS) |q| {
        if (seen[q.bone]) @compileError("fungaldeer: two petals on one bone");
        seen[q.bone] = true;
    }
    for (0..NPETAL) |k| {
        if (!seen[PET0 + k]) @compileError("fungaldeer: a petal bone carries nothing");
    }
}

/// Degrees off the bloom's own axis. SHUT is NEGATIVE — a bud's petals converge PAST parallel, which is what
/// closes the tip, and it is solved: the quill bows 0.42 of its own length off-axis, so the tip's radial is
/// `|BLOOM_RIM + len*(0.42*cos f + sin f)|` and landing that on the axis is -33 deg.
const PETAL_SHUT: f32 = -33.0;
/// …and at the other end. **A BIGGER NUMBER HERE MAKES A SMALLER FLOWER PAST A POINT**: that same radial peaks
/// at `atan(1/0.42)` = 67 deg and falls away after. 95 puts the ring at 86..108 — straddling flat, so the
/// throat faces OUT, which is what a flower spitting straight up needs.
const PETAL_WIDE: f32 = 95.0;

/// **QUILLED, NOT BLADED.** Flat oriented boxes come back as pale cardboard — this renderer is flat-shaded and
/// a 4 cm slab has no gradient across it. A round tapering quill has its own shading and needs no faces.
const PETAL_LEN: f32 = 0.48 * W;
/// **THIN, OR SEVEN OF THEM ARE ONE LUMP** — the gaps between them are what read as a bud.
const QUILL_R: f32 = 0.021 * W;
const PETAL_SEGS: u32 = 8;
/// How far the quill bows off the axis over its length and again over the last of it — the RECURVE. Their SUM,
/// 0.42, is the tip's own off-axis share and it is what `PETAL_SHUT` and the width peak are solved against.
const PETAL_BOW: f32 = 0.24;
const PETAL_RECURVE: f32 = 0.18;

/// **THE SECOND TIER, AND IT COSTS NO BONES.** Each petal bone carries a short broad TONGUE as well as its
/// quill, pitched this many degrees further in and baked into the mesh, so one fold drives both.
const INNER_TILT: f32 = 24.0;
/// Solved so the tongue lands ON the axis and not through it: `|y'| = ilen*(0.30*cos f + sin f)` = `BLOOM_RIM`.
const INNER_LEN: f32 = 0.34;
/// …and its half-width is ABSOLUTE metres, not a multiple of the quill's: the tongues are the seal.
const INNER_W: f32 = 0.075 * W;

/// Where the quills root, and how far forward of the receptacle. The throat's own size sets this.
const BLOOM_RIM: f32 = 0.112 * W;
const CALYX_Z: f32 = 0.052 * W;
fn ringDir(angDeg: f32) rl.Vector3 {
    const a = mathx.radians(angDeg);
    return v3(-mathx.sinf(a), mathx.cosf(a), 0);
}

fn petalRoot(head: rl.Vector3, q: Petal) rl.Vector3 {
    const d = ringDir(q.ang);
    const rr = BLOOM_RIM * q.root;
    return v3(head.x + d.x * rr, head.y + d.y * rr, head.z + CALYX_Z);
}

fn foldOf(q: Petal, open: f32) f32 {
    return PETAL_SHUT + q.bias + (PETAL_WIDE - PETAL_SHUT) * q.gain * open;
}

fn rowFor(bone: usize) Petal {
    for (PETALS) |q| {
        if (q.bone == bone) return q;
    }
    unreachable;
}

/// **A DEER CARRIES ITS HEAD HIGH AND FORWARD, NOT SLUNG LIKE A DOG'S.** Wolf's chain puts the skull at 0.82 W
/// on a level neck; this lifts it to 1.16 and pushes it out, which is the whole difference between the two
/// silhouettes before a single mesh is built.
const HEAD_UP: f32 = 1.10;
const HEAD_OUT: f32 = 0.52;
const NECK_MID: f32 = 0.46;

fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    const base = wolf.restPose(W);
    for (base, 0..) |p, i| r[i] = p;
    const sh = base[CHEST];
    r[HEAD] = v3(0, HEAD_UP * W, sh.z + HEAD_OUT * W);
    r[NECK] = v3(0, lerpF(sh.y, r[HEAD].y, NECK_MID), lerpF(sh.z, r[HEAD].z, NECK_MID * 0.75));
    r[JAW] = v3(0, r[HEAD].y - 0.052 * W, r[HEAD].z + 0.086 * W);
    r[EARL] = v3(0.062 * W, r[HEAD].y + 0.070 * W, r[HEAD].z - 0.048 * W);
    r[EARR] = v3(-0.062 * W, r[HEAD].y + 0.070 * W, r[HEAD].z - 0.048 * W);
    r[ANTL] = v3(0.050 * W, r[HEAD].y + 0.086 * W, r[HEAD].z - 0.010 * W);
    r[ANTR] = v3(-0.050 * W, r[HEAD].y + 0.086 * W, r[HEAD].z - 0.010 * W);
    // OUT OF THE BACK: the socket sits on the withers and the bloom stands up and a little behind it.
    r[STALK] = v3(0, sh.y + 0.150 * W, sh.z - 0.030 * W);
    r[BLOOM] = v3(0, r[STALK].y + STALK_UP * W, r[STALK].z - STALK_BACK * W);
    for (PETALS) |q| r[q.bone] = petalRoot(r[BLOOM], q);
    return r;
}

// **AUTHOR DARK, AND SOLVE IT RATHER THAN GUESS** — screen goes as albedo^(1/2.2), and a big smooth mass comes
// back brighter than the field it stands in. **AND ALPHA IS INVERSE EMISSIVE, NOT OPACITY** (`shaders.zig`:
// `emis = 1 - fragColor.a`): matter goes to 248+, and only the throat and the stamens keep the low alpha,
// because they are the only things here that are light.
const HIDE = rgba(13, 11, 9, 250);
const HIDE_DK = rgba(7, 6, 6, 252);
const HIDE_LT = rgba(20, 17, 13, 248);
const BELLY = rgba(10, 11, 13, 250);

const STALKC = rgba(21, 20, 14, 250);
const STALK_LT = rgba(34, 33, 22, 248);
const STALK_DK = rgba(12, 12, 9, 252);
const LIMB = rgba(14, 13, 11, 250);
const LIMB_LT = rgba(22, 20, 16, 248);
const CALYX = rgba(19, 22, 15, 250);
const CALYX_LT = rgba(31, 34, 22, 248);

const PETAL_DK = rgba(15, 11, 16, 250);
const PETAL = rgba(26, 16, 23, 250);
const PETAL_LT = rgba(40, 27, 33, 248);
const PETAL_TIP = rgba(58, 45, 48, 246);
const PETAL_IN = rgba(30, 12, 14, 246);

const THROAT_HALO = rgba(46, 20, 26, 236);
const THROAT_LIP = rgba(120, 38, 50, 168);
const THROAT_DEEP = rgba(188, 48, 62, 96);
const THROAT = rgba(255, 132, 128, 22);

const STAMEN = rgba(146, 122, 76, 196);
const FANG = rgba(29, 26, 22, 250);
const TOOTH = rgba(78, 74, 65, 242);
const HUSK = rgba(36, 31, 24, 250);
/// The rack. Dead bone weathered green at the base — the one PALE thing on a body authored this dark, so the
/// silhouette has a crown on it from across a field.
const HORN = rgba(52, 49, 38, 250);
const HORN_LT = rgba(74, 70, 55, 248);
const MUZZLE = rgba(9, 8, 8, 251);
const EYE = rgba(96, 108, 62, 200);

/// **THE SPORE IS A LIGHT, NOT A PEBBLE** — it has to be findable against dark ground for a second and a half.
const SPORE_CORE = rgba(214, 230, 150, 40);
const SPORE_SKIN = rgba(126, 158, 78, 150);

pub const State = enum { idle, move, flee, spit, butt, hurt, dead };

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .mesh = buildMeshes(), .mat = gfx.material(shader, "fungal deer") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, d: *const Deer) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, d.xf[i]);
    }
};

pub const Deer = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    state: State = .idle,
    t: f32 = 0,
    /// A clock no state resets, because the idle drift may not restart every time it stops walking.
    elapsed: f32 = 0,
    phase: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    spitCool: f32 = 0,
    buttCool: f32 = 0,
    /// **HOW LONG IT HAS BEEN CORNERED**, in seconds, and the only thing that asks for the antlers.
    pinned: f32 = 0,
    /// Last frame's gap to him. A distance, remembered — which is how "backing off is not working" is said
    /// without reading one thing about him.
    lastGap: f32 = 1e9,
    /// -1..1, how far round the head is turned AT him. Eased, and off his BEARING alone.
    look: f32 = 0,
    /// The bloom's own value on the frame it died. A corpse wilts from whatever the blow caught it wearing.
    deathOpen: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    heroHit: ?combat.Hit = null,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    /// One-frame edges the loop reads for its voices, and the volley the herd's pool reads.
    opened: bool = false,
    spat: bool = false,
    spatFrom: rl.Vector3 = mathx.zero3,
    charged: bool = false,
    gored: bool = false,
    yelped: bool = false,
    parry: foe.Parry = .{},
    parried: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    /// Read by `foe.dissipate` — the death fade's own emit accumulator, and part of the contract rather than
    /// this creature's state. It looks unused from inside the file and is not.
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Deer {
        var d = Deer{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale,
            .seed = seed,
            .rest = restPose(),
        };
        d.fxRng = foe.fxStream(seed, 51787.0, 0x1F10);
        d.spitCool = seed * SPIT_COOL * 0.5;
        d.pose();
        return d;
    }

    pub fn kind(_: *const Deer) wf.FoeKind {
        return .fungal_deer;
    }

    pub fn centerWorld(self: *const Deer) rl.Vector3 {
        const fwd = mathx.headingDir(self.facing);
        const mid = BARREL_MID * W * self.scale;
        return v3(self.pos.x + fwd.x * mid, self.pos.y + CENTER_F * W * self.scale, self.pos.z + fwd.z * mid);
    }
    pub fn lockPoint(self: *const Deer) rl.Vector3 {
        return foe.markOn(self.xf[SPINE], LOCK_AT);
    }
    pub fn topWorld(self: *const Deer) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * W, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Deer) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Deer) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Deer) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Deer) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Deer) bool {
        return self.state == .hurt or self.state == .dead;
    }
    pub fn airborne(_: *const Deer) bool {
        return false;
    }
    pub fn flashFrac(self: *const Deer) f32 {
        return foe.flashFrac(self.flash);
    }

    /// The throat's own mouth, off the posed bloom — where a volley leaves from.
    pub fn bloomPoint(self: *const Deer) rl.Vector3 {
        return foe.markOn(self.xf[BLOOM], v3(0, 0, CALYX_Z + 0.03 * W));
    }
    /// …and where a portrait points. **THE FACE IS THE FACE** — unlike the ravager, this one has one.
    pub fn facePoint(self: *const Deer) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0, 0.06 * W));
    }

    /// 0 shut, 1 wide, **read off the volley's own clock or the stun's and nowhere else**. Out of range at both
    /// ends on purpose — under 0 through the tightening, over 1 through the fling.
    pub fn openAmt(self: *const Deer) f32 {
        switch (self.state) {
            .dead => return self.deathOpen * (1.0 - mathx.smoothstep(0, WILT_DUR, self.t)),
            .hurt => return if (self.heavyStun) BLOOM_STUN * foe.stunCurve(self.t, true) else 0,
            .spit => {},
            .idle, .move, .flee, .butt => return 0,
        }
        const clampEnd = SPIT_WIND * CLAMP_BY;
        const openEnd = SPIT_WIND * OPEN_BY;
        const setEnd = SPIT_WIND * SETTLE_BY;
        const shutEnd = SPIT_WIND + SPIT_DUR + SPIT_REC * SHUT_BY;
        if (self.t < clampEnd) return -BLOOM_CLAMP * mathx.smoothstep(0, clampEnd, self.t);
        if (self.t < openEnd) return lerpF(-BLOOM_CLAMP, 1.0 + BLOOM_SNAP, mathx.smoothstep(clampEnd, openEnd, self.t));
        if (self.t < setEnd) return lerpF(1.0 + BLOOM_SNAP, 1.0, mathx.smoothstep(openEnd, setEnd, self.t));
        if (self.t < SPIT_WIND + SPIT_DUR) return 1.0;
        return 1.0 - (1.0 + BLOOM_CLAMP * 0.5) * mathx.smoothstep(SPIT_WIND + SPIT_DUR, shutEnd, self.t);
    }

    /// **THE OPEN THROAT IS THE PRICE OF THE MOVE.** 1 shut, up to 1.9 wide. Damage only — see `BLOOM_FRAIL`.
    pub fn frailty(self: *const Deer) f32 {
        return 1.0 + BLOOM_FRAIL * mathx.clampF(self.openAmt(), 0, 1);
    }

    /// **HOW FAR THE FLOWER HAS RISEN OUT OF ITS BACK**, 0 furled to 1 standing. Off the volley's clock — never
    /// off `openAmt`, or a heavy stun would raise a stalk it is meant to leave lying.
    pub fn riseAmt(self: *const Deer) f32 {
        if (self.state != .spit) return 0;
        if (self.t < SPIT_WIND) return mathx.smoothstep(0, SPIT_WIND * OPEN_BY, self.t);
        if (self.t < SPIT_WIND + SPIT_DUR) return 1.0;
        return 1.0 - mathx.smoothstep(SPIT_WIND + SPIT_DUR, SPIT_WIND + SPIT_DUR + SPIT_REC * SHUT_BY, self.t);
    }

    /// The GATHER, 0..1 — the load under the charge, spent by the drive.
    fn gatherAmt(self: *const Deer) f32 {
        if (self.state != .butt) return 0;
        return mathx.pulse(self.t, 0, BUTT_WIND * 0.74, BUTT_WIND * 0.90, BUTT_WIND + BUTT_STRIKE);
    }

    /// **HOW FAR INTO THE DRIVE IT IS**, -1 cocked through +1 followed through. One signed channel, so the head
    /// coming up cannot promise a charge the body does not throw.
    pub fn driveAmt(self: *const Deer) f32 {
        if (self.state != .butt) return 0;
        if (self.t < BUTT_WIND) return -mathx.smoothstep(0, BUTT_WIND * 0.88, self.t);
        if (self.t < BUTT_WIND + BUTT_STRIKE) {
            return lerpF(-1.0, 1.0, foe.swingCurve((self.t - BUTT_WIND) / BUTT_STRIKE));
        }
        return 1.0 - mathx.smoothstep(BUTT_WIND + BUTT_STRIKE, BUTT_WIND + BUTT_STRIKE + BUTT_RECOVER * 0.7, self.t);
    }

    /// Three incommensurate rates off one never-reset clock, offset by the map's own seed.
    fn swayAt(self: *const Deer) f32 {
        return mathx.gutter(self.elapsed * SWAY_RATE + self.seed * 9.7, self.seed * 6.1);
    }

    pub fn navWant(self: *const Deer, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .move and self.state != .flee) return null;
        if (self.state == .flee) return mathx.addV(self.pos, mathx.scaleV(mathx.dirXZ(self.pos, hero), -1.0));
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        if (foe.postAim(self)) |go| return go;
        return if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Deer, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    /// +1 its left, -1 its right, and the magnitude is how far round. POSITION and BEARING, nothing else.
    fn sideOf(self: *const Deer, hero: rl.Vector3) f32 {
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = mathx.headingDir(self.facing);
        return fwd.z * to.x - fwd.x * to.z;
    }

    pub fn update(self: *Deer, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.heroHit = null;
        self.opened = false;
        self.spat = false;
        self.charged = false;
        self.gored = false;
        self.yelped = false;
        self.parried = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Deer, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.t += dt;
        self.elapsed += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.spitCool = mathx.maxF(0, self.spitCool - dt);
        self.buttCool = mathx.maxF(0, self.buttCool - dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        if (self.state == .dead) {
            foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            self.look = mathx.approach(self.look, 0, dt * LOOK_RATE);
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }

        const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const gap = mathx.distXZ(self.pos, hero);

        // **CORNERED: HE IS INSIDE THE RING AND THE GAP IS NOT OPENING.** Two distances and a clock — the world
        // as any body standing in it could see it, and never a read of his state machine.
        const closing = gap <= self.lastGap + 1e-4;
        if (sensed <= AGGRO_R and gap <= CORNER_R * self.scale + foe.HERO_R and closing) {
            self.pinned += dt;
        } else self.pinned = mathx.maxF(0, self.pinned - dt * CORNER_DECAY);
        self.lastGap = gap;

        // THE HEAD TURNS AT HIM WHILE IT GRAZES — his bearing, and nothing else about him.
        const wantLook: f32 = if (sensed <= AGGRO_R and self.state != .butt and self.state != .spit)
            mathx.clampF(self.sideOf(hero) * 1.6, -1, 1)
        else
            0;
        self.look = mathx.approach(self.look, wantLook, dt * LOOK_RATE);

        if (self.state == .hurt) {
            if (self.t >= combat.foeStunDur(self.heavyStun)) self.state = .idle;
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }

        if (self.state == .spit) {
            // It aims while the flower is still coming up, and not one degree after.
            if (self.t < SPIT_WIND * OPEN_BY) self.faceToward(hero, dt);
            self.speed = 0;
            const at = SPIT_WIND + SPIT_DUR * SPIT_RELEASE_K;
            // The release is an EDGE, caught by the clock crossing it: a long frame cannot fire two volleys.
            if (self.t - dt < at and self.t >= at) {
                self.spat = true;
                self.spatFrom = self.bloomPoint();
            }
            if (self.t >= SPIT_WIND + SPIT_DUR + SPIT_REC) {
                self.state = .idle;
                self.t = 0;
                self.spitCool = SPIT_COOL;
            }
            self.settle(dt);
            return self.pose();
        }

        if (self.state == .butt) {
            // IT DOES NOT TURN INTO IT. A head-down charge is committed to the line it loaded on, so stepping
            // off that line is the answer — the same bargain every commitment in this game makes.
            // **IT AIMS WHILE THE HEAD IS COMING DOWN AND COMMITS WHEN IT LEAVES** — the ravager's bargain.
            // Aimed only by the single snap at the commit, a charge could be thrown 90 deg off him and the
            // one move a cornered animal owns would answer nothing.
            if (self.t < BUTT_WIND) self.faceToward(hero, dt);
            if (self.t >= BUTT_WIND and self.t < BUTT_WIND + BUTT_STRIKE) {
                mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), BUTT_DRIVE * self.scale * (dt / BUTT_STRIKE), bounds);
                self.tryButt(hero);
            }
            if (self.t >= BUTT_WIND + BUTT_STRIKE + BUTT_RECOVER) {
                self.state = .idle;
                self.t = 0;
                self.buttCool = BUTT_COOL;
                self.pinned = 0;
                self.heroLatch = false;
            }
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }

        const hunting = sensed <= AGGRO_R;
        const round = foe.postWant(self, dt, sensed, AGGRO_R);

        // **THE ANTLERS COME FIRST AND THEY ARE THE ONLY BRANCH THAT LOOKS INWARD.** Everything else this
        // creature does is about not being here.
        if (hunting and self.pinned >= CORNER_HOLD and self.buttCool <= 0) {
            self.state = .butt;
            self.t = 0;
            self.heroLatch = false;
            self.speed = 0;
            self.charged = true;
        } else if (hunting and self.spitCool <= 0 and gap >= SPIT_MIN and gap <= SPIT_MAX) {
            self.state = .spit;
            self.t = 0;
            self.speed = 0;
            self.opened = true;
        } else if (hunting and gap < FLEE_R) {
            // **IT WALKS AWAY FROM YOU, AND IT WALKS OFF THE LINE AS WELL AS BACK DOWN IT.** A straight
            // backpedal is a thing you simply keep pace with; a quartering run is one you have to cut off.
            const away = mathx.scaleV(mathx.dirXZ(self.pos, hero), -1.0);
            const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
            const way = mathx.normV(mathx.addV(away, mathx.scaleV(mathx.perpXZ(away), side * 0.45)));
            self.faceToward(self.nav.aim(self.pos, mathx.addV(self.pos, way)), dt);
            self.speed = mathx.approach(self.speed, FLEE_SPEED, ACCEL * dt);
            self.travel(dt, bounds);
            self.state = .flee;
        } else if (hunting and gap > KEEP_R) {
            self.faceToward(self.nav.aim(self.pos, hero), dt);
            self.speed = mathx.approach(self.speed, CLOSE_SPEED, ACCEL * dt);
            self.travel(dt, bounds);
            self.state = .move;
        } else if (!hunting and (round != null or mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R)) {
            const want = round orelse foe.homeFor(self);
            const stop: f32 = if (round != null) foe.ARRIVE else HOME_R;
            if (mathx.distXZ(self.pos, want) > stop) {
                self.faceToward(self.nav.aim(self.pos, want), dt);
                self.speed = mathx.approach(self.speed, wolf.TROT_SPEED, ACCEL * dt);
                self.travel(dt, bounds);
                self.state = .move;
            } else {
                self.speed = mathx.approach(self.speed, 0, ACCEL * dt);
                self.state = .idle;
            }
        } else {
            if (hunting) self.faceToward(hero, dt);
            self.speed = mathx.approach(self.speed, 0, ACCEL * dt);
            self.state = .idle;
        }
        self.settle(dt);
        self.pose();
    }

    fn travel(self: *Deer, dt: f32, bounds: f32) void {
        const step = self.speed * dt * self.chill.travel();
        mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
        self.phase = wolf.wrap01(self.phase + step / wolf.strideFor(self.speed));
    }

    fn tryButt(self: *Deer, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(BUTT_R, self.scale), BUTT_FRONT_DOT)) return;
        self.heroHit = BUTT_HIT;
        self.heroLatch = true;
        self.gored = true;
        self.leash.noteCombat();
    }

    fn settle(self: *Deer, dt: f32) void {
        self.speedS = mathx.approach(self.speedS, self.speed, GAIT_BLEND * dt);
    }

    pub fn tryHit(self: *Deer, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        // **THE OPEN BLOOM IS PAID FOR HERE**, on the blade and not in the body's own bar, so the cull, the
        // threat and the shield all see the blow that actually landed. `poise`/`stance` ride through untouched.
        var blade = blade_;
        const k = self.frailty();
        if (k > 1.0) {
            blade.hit.dmg = blade_.hit.dmg * k;
            blade.hit.elem = blade_.hit.elem.scaled(k);
        }
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, SHOVE);
        const torn: i32 = if (heavy) 7 else 3;
        self.emitPetals(s.contact, torn + @as(i32, @intFromFloat(6.0 * mathx.clampF(self.openAmt(), 0, 1))));
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    /// SECONDS BACK FROM THE CROWN ARRIVING, or null. **THE CHARGE ONLY** — a volley is not a stroke and there
    /// is nothing for a board to be braced against.
    fn toImpact(self: *const Deer) ?f32 {
        const at = BUTT_WIND + BUTT_STRIKE * BUTT_IMPACT_K;
        return switch (self.state) {
            .butt => at - self.t,
            .idle, .move, .flee, .spit, .hurt, .dead => null,
        };
    }

    /// THE INSTANT THE RACK CAN BE CAUGHT IN, and how far out it reaches then — `tryButt`'s OWN extent through
    /// the same `foe.hurtReach`, so a charge the boards could not have met is never offered as one.
    fn parryable(self: *const Deer) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(BUTT_R, self.scale);
    }

    fn takeParry(self: *Deer) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.buttCool = BUTT_COOL;
        self.pinned = 0;
        self.heroLatch = true;
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light, .none => self.enterStun(false),
        }
    }

    fn enterStun(self: *Deer, heavy: bool) void {
        self.state = .hurt;
        self.t = 0;
        self.heavyStun = heavy;
        self.yelped = true;
    }

    fn enterDeath(self: *Deer) void {
        if (self.state == .dead) return;
        self.deathOpen = mathx.clampF(self.openAmt(), 0, 1.0 + BLOOM_SNAP);
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn stagger(self: *Deer, heavy: bool) void {
        self.enterStun(heavy);
    }

    /// The flower at full stand. **`stageGather` AND NOT `stageRise`**: `shots.runMapShots` finds a creature's
    /// signature move off `@hasDecl` of this ONE name, and under any other the deer went unshot.
    pub fn stageGather(self: *Deer, u: f32) void {
        self.state = .spit;
        self.t = mathx.clampF(u, 0, 1) * SPIT_WIND;
        self.pose();
    }
    /// …and the other half of it: the rack down and the body loaded.
    pub fn stageCharge(self: *Deer, u: f32) void {
        self.state = .butt;
        self.t = mathx.clampF(u, 0, 1) * (BUTT_WIND + BUTT_STRIKE);
        self.pose();
    }

    fn emitPetals(self: *Deer, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.6, 1.7);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.3, 1.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.38, 0.78),
                .r0 = self.fxRng.range(0.030, 0.058) * self.scale,
                .r1 = 0.006,
                .col = if (self.fxRng.float() < 0.5) PETAL else PETAL_LT,
                .grav = 2.2,
                // Petals FLUTTER — heavy drag against a light pull.
                .drag = 2.8,
            });
        }
    }

    pub fn drawFx(self: *const Deer) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Deer, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    pub fn pose(self: *Deer) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(SINK_DEPTH, self.scale, self.fade);
        const g = wolf.gaitAt(self.speedS);
        const stride = wolf.strideFor(self.speedS);
        const ph = wolf.limbPhases(self.phase, g);
        const m = mathx.clampF(self.speedS / wolf.WALK_SPEED, 0, 1);

        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const wilt: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.34), 0, 1) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF((self.t - DEATH_DUR * 0.26) / (DEATH_DUR * 0.58), 0, 1) else 0;

        const rise = self.riseAmt();
        const gather = self.gatherAmt();
        const drive = self.driveAmt();
        const sway = self.swayAt();

        const crouch = CROUCH * gather + DEAD_BUCKLE * wilt;
        const pitch = GATHER_PITCH * gather + DRIVE_PITCH * mathx.maxF(drive, 0);
        // Two rates, so the swell is a body breathing and not a metronome.
        const breath = (mathx.sinf(self.elapsed * 1.7) * 0.006 + mathx.sinf(self.elapsed * 0.61 + self.seed * 4.0) * 0.004) * W;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(scaleM(fs, fs, fs), mul(rx(-pitch), rz(-DEAD_ROLL * mathx.smoothstep(0, 1, fall) + SWAY_DEG * 0.35 * sway))),
            mul(tr(0, (self.rest[ROOT].y + breath - crouch * W) * fs + sink, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        const flex = mathx.sinf(self.phase * std.math.tau) * m * (4.0 + 9.0 * mathx.clampF((self.speedS - wolf.TROT_SPEED) / (wolf.GALLOP_SPEED - wolf.TROT_SPEED), 0, 1));
        const duck: f32 = 8.0 * react;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, mul(rx(-flex * 0.5 - duck * 0.3), rz(SWAY_DEG * 0.5 * sway)));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, mul(rx(-flex * 0.5 - duck * 0.3 - 9.0 * wilt), rz(-SWAY_DEG * 0.35 * sway)));

        // **THE NECK IS A DEER'S: HIGH, AND IT DROPS FOR THE CHARGE.** A stag levels its rack by folding at the
        // withers, not by nodding at the poll — the whole chain comes down and the crown arrives at his chest.
        const neckPitch = flex * 0.4 + 3.0 * m - duck * 1.2 - BUTT_LOAD * gather + BUTT_DUCK * mathx.maxF(drive, 0) - WILT_FOLD * wilt;
        const neckYaw = LOOK_DEG * self.look + SWAY_DEG * sway;
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, mul3(rz(SWAY_DEG * 0.8 * sway), rx(neckPitch), ry(neckYaw)));
        heromod.setJoint(&wx, &self.rest, HEAD, NECK, mul3(
            rx(flex * 0.2 - duck * 0.6 + 20.0 * react - 30.0 * wilt + BUTT_DUCK * 0.35 * mathx.maxF(drive, 0)),
            ry(LOOK_DEG * 0.5 * self.look),
            rz(SWAY_DEG * 0.6 * sway),
        ));
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(-6.0 - 10.0 * react - 8.0 * wilt));
        const earFlick = 6.0 * mathx.sinf(self.elapsed * 2.3 + self.seed * 5.0) + 14.0 * react;
        heromod.setJoint(&wx, &self.rest, EARL, HEAD, mul(rx(-8.0 - earFlick), rz(22.0 - LOOK_DEG * 0.3 * self.look)));
        heromod.setJoint(&wx, &self.rest, EARR, HEAD, mul(rx(-8.0 + earFlick), rz(-22.0 - LOOK_DEG * 0.3 * self.look)));
        heromod.setJoint(&wx, &self.rest, ANTL, HEAD, rz(3.0 * sway));
        heromod.setJoint(&wx, &self.rest, ANTR, HEAD, rz(-3.0 * sway));

        // **THE STALK RISES OUT OF THE BACK, AND IT IS A HINGE AND A TELESCOPE AT ONCE.** Furled it lies back
        // along the loins at `FURL_DEG` with a quarter of its length pulled down inside the sheath; risen it
        // stands and stretches. `setJoint` takes the bone length from the DISTANCE between two rest points, so
        // the reach is a translate on top — and the bloom's collar hangs inside the bore to cover the slide.
        const furl = FURL_DEG * (1.0 - rise);
        const reach = (STALK_STRETCH * rise - STALK_FURL_IN * (1.0 - rise)) * W;
        const stalkOff = mathx.subV(self.rest[BLOOM], self.rest[STALK]);
        const up = if (mathx.lenV(stalkOff) > 1e-5) mathx.normV(stalkOff) else v3(0, 1, 0);
        heromod.setJoint(&wx, &self.rest, STALK, CHEST, mul3(
            rx(-furl - 6.0 * rise + 14.0 * react + 110.0 * wilt),
            ry(SWAY_DEG * 1.4 * sway),
            rz(SWAY_DEG * 0.9 * sway),
        ));
        wx[BLOOM] = mul(
            mul(
                mul3(rx(-8.0 * rise + 18.0 * react - 26.0 * wilt), ry(0), rz(SWAY_DEG * 0.6 * sway)),
                tr(stalkOff.x + up.x * reach, stalkOff.y + up.y * reach, stalkOff.z + up.z * reach),
            ),
            wx[STALK],
        );

        const open = self.openAmt();
        const shiver = SHIVER_DEG * react * mathx.sinf(self.elapsed * SHIVER_HZ * std.math.tau);
        const flutter = 1.3 * sway;
        for (PETALS) |q| {
            const fold = foldOf(q, open) + q.sag * wilt + shiver * q.gain + flutter * (0.4 + 0.6 * mathx.clampF(open, 0, 1));
            heromod.setJoint(&wx, &self.rest, q.bone, BLOOM, mul(rx(-fold), rz(q.ang + shiver * 0.3)));
        }

        // A deer's tail is a flag: up when it runs, clamped when it charges.
        const tailSwing = mathx.sinf(self.phase * std.math.tau + 1.1) * 6.0 * m + SWAY_DEG * 1.2 * sway;
        const tailUp = 34.0 * m - 26.0 * gather - 22.0 * wilt;
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(rx(-10.0 * m + 24.0 * react + tailUp), ry(tailSwing)));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(rx(6.0 + 10.0 * react + tailUp * 0.6), ry(tailSwing * 0.7)));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(rx(9.0 + 8.0 * react + tailUp * 0.35), ry(tailSwing * 0.5)));

        wolf.legs(wx[0..wolf.N], self.rest[0..wolf.N], W, ph, g, stride, m, crouch, 0);
        self.xf = wx;
    }
};

/// **A SPORE IN THE AIR.** Its whole life is one clock: it climbs out of the throat, it HANGS, and then it
/// turns over and comes at where he is standing. No owner and no spirit — it is weather, and it answers for
/// the hero and for nothing else.
pub const Spore = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    vel: rl.Vector3 = mathx.zero3,
    /// Where it drifts to over the hang — chosen at the launch, so the five of them spread instead of stacking.
    drift: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    seed: f32 = 0,
    /// The ground under the animal that spat it — what `foe.landed` measures against.
    floor: f32 = 0,

    /// 0 while it is still climbing or hanging, 1 once it has turned over.
    pub fn homing(self: *const Spore) bool {
        return self.live and self.t >= SPORE_RISE + SPORE_HANG;
    }
    /// How lit it is: it BRIGHTENS as it turns over, which is the second half of the tell.
    pub fn heat(self: *const Spore) f32 {
        const start = SPORE_RISE + SPORE_HANG;
        return mathx.smoothstep(start - 0.35, start + 0.15, self.t);
    }
};

pub const SPORE_N: usize = 32;

const CAP_N = wf.MAX_PER_KIND;
const HERD_PARTS: usize = 72;

/// An airborne spore belongs to nobody standing anywhere — a `Threat` with no spirit and no owner says so.
const AIR_THREAT = foe.Threat{};

pub const Herd = struct {
    model: Model,
    deer: [CAP_N]Deer = undefined,
    n: usize = 0,

    /// **SIZED FOR A HANDFUL OF ANIMALS AND A FULL POOL DROPS RATHER THAN WRAPS**: wrapping would put a spore
    /// in the air that nothing had spat. Six volleys of five before it degrades, which is more than a herd
    /// this size ever has in flight at once.
    spores: [SPORE_N]Spore = [_]Spore{.{}} ** SPORE_N,

    parts: [HERD_PARTS]foe.Particle = [_]foe.Particle{.{}} ** HERD_PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0xDEE7),

    pub fn init(shader: rl.Shader) Herd {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Herd) []Deer {
        return self.deer[0..self.n];
    }
    pub fn liveConst(self: *const Herd) []const Deer {
        return self.deer[0..self.n];
    }
    pub fn reset(self: *Herd, m: *const wf.Map) void {
        self.clearAir();
        foe.resetGroup(Deer, &self.deer, &self.n, m, .fungal_deer);
    }
    /// **`clear` EMPTIES THE FIELD** — the bodies AND what they left in the air over it, or a reload comes up
    /// standing under a volley nothing spat.
    pub fn clear(self: *Herd) void {
        self.n = 0;
        self.clearAir();
    }
    fn clearAir(self: *Herd) void {
        self.spores = [_]Spore{.{}} ** SPORE_N;
    }
    pub fn setShader(self: *Herd, sh: rl.Shader) void {
        self.model.setShader(sh);
    }

    pub fn update(self: *Herd, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var worst: ?foe.Blow = null;
        for (self.live()) |*d| {
            if (d.update(dt, d.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&worst, h, d.pos, &d.threat);
            if (d.spat) self.volley(d.spatFrom, d.facing, d.pos.y);
        }
        self.tickSpores(dt, hero, &worst);
        foe.tickParticles(&self.parts, dt, hero.y);
        return worst;
    }

    /// **A HANDFUL, THROWN UP AND OUT — NOT AT HIM.** The launch reads no direction to the hero at all: they go
    /// where the flower is pointing and spread, and the aim happens a second and a half later.
    fn volley(self: *Herd, from: rl.Vector3, facing: f32, floor: f32) void {
        var placed: usize = 0;
        for (&self.spores) |*s| {
            if (placed >= SPORES_PER_VOLLEY) break;
            if (s.live) continue;
            const a = self.fxRng.angle();
            const r = self.fxRng.range(0.35, 1.0) * SPORE_SPREAD;
            const fwd = mathx.headingDir(facing);
            s.* = .{
                .live = true,
                .at = from,
                .vel = v3(
                    mathx.cosf(a) * r * 0.5 + fwd.x * 0.6,
                    SPORE_UP,
                    mathx.sinf(a) * r * 0.5 + fwd.z * 0.6,
                ),
                .drift = v3(mathx.cosf(a) * r, 0, mathx.sinf(a) * r),
                .seed = self.fxRng.float(),
                .floor = floor,
            };
            placed += 1;
        }
    }

    fn tickSpores(self: *Herd, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        const chest = foe.heroChest(hero);
        for (&self.spores) |*s| {
            if (!s.live) continue;
            s.t += dt;
            if (s.t < SPORE_RISE) {
                // OUT OF THE THROAT: it decelerates as it climbs, so the top of the arc is where it stalls.
                const u = s.t / SPORE_RISE;
                s.vel = v3(s.vel.x, SPORE_UP * (1.0 - u), s.vel.z);
                s.at = mathx.addV(s.at, mathx.scaleV(s.vel, dt));
            } else if (s.t < SPORE_RISE + SPORE_HANG) {
                // THE HANG: it drifts on its own bearing and bobs. Nothing here reads the hero at all.
                const bob = SPORE_BOB * SPORE_BOB_W * mathx.cosf((s.t + s.seed * 3.0) * SPORE_BOB_W) * dt;
                s.at = mathx.addV(s.at, mathx.scaleV(s.drift, dt * 0.35));
                s.at.y += bob;
            } else {
                // AND THEN IT TURNS OVER. The steer is CAPPED, so a roll beats it and a walk does not.
                const want = mathx.normV(mathx.subV(chest, s.at));
                const have = if (mathx.lenV(s.vel) > 1e-4) mathx.normV(s.vel) else want;
                s.vel = mathx.scaleV(mathx.turnToward(have, want, SPORE_TURN * dt), SPORE_HOME);
                s.at = mathx.addV(s.at, mathx.scaleV(s.vel, dt));
            }
            if (mathx.lenV(mathx.subV(s.at, chest)) <= SPORE_R + foe.HERO_R) {
                s.live = false;
                self.puff(s.at, 8);
                foe.worseBlow(worst, SPORE_HIT, s.at, &AIR_THREAT);
                continue;
            }
            if (s.t >= SPORE_LIFE or foe.landed(s.at.y, s.floor, hero.y)) {
                s.live = false;
                self.puff(s.at, 6);
            }
        }
    }

    fn puff(self: *Herd, at: rl.Vector3, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.3);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.1, 0.9), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.34, 0.72),
                .r0 = self.fxRng.range(0.024, 0.052),
                .r1 = 0.005,
                .col = if (self.fxRng.float() < 0.5) SPORE_SKIN else PETAL_LT,
                .grav = 0.9,
                .drag = 3.2,
            });
        }
    }

    pub fn draw(self: *const Herd, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }

    pub fn drawFx(self: *const Herd) void {
        for (self.liveConst()) |*d| d.drawFx();
        for (&self.spores) |*s| {
            if (!s.live) continue;
            const heat = s.heat();
            const pulse = 1.0 + 0.12 * mathx.sinf((s.t + s.seed * 2.0) * 7.0);
            rl.drawSphereEx(s.at, SPORE_R * pulse, 7, 6, mathx.lerpColor(mathx.withAlpha(SPORE_SKIN, 255), mathx.withAlpha(SPORE_CORE, 255), heat));
            // The halo is what carries at range, and it SWELLS as the thing turns over.
            rl.drawSphereEx(s.at, SPORE_R * (1.9 + 0.9 * heat) * pulse, 8, 6, mathx.withAlpha(SPORE_CORE, mathx.u8f(40.0 + 46.0 * heat)));
        }
        foe.drawParticles(&self.parts);
    }

    pub fn setParry(self: *Herd, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Herd) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn pierce(self: *Herd, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Herd) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Herd) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Herd) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Herd) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    const rest = restPose();
    for (0..N) |i| {
        var b = Builder.init();
        buildBone(&b, i, rest);
        mesh[i] = b.toMesh();
    }
    return mesh;
}

fn buildBone(b: *Builder, i: usize, rest: [N]rl.Vector3) void {
    var rng = mathx.Rng.init(0xDEE5 + @as(u64, @intCast(i)));
    switch (i) {
        ROOT => buildPelvis(b, &rng),
        SPINE => buildLoin(b, &rng, rest),
        CHEST => buildChest(b, &rng, rest),
        NECK => buildNeck(b, &rng, rest),
        HEAD => buildSkull(b, &rng),
        JAW => buildJaw(b, &rng),
        EARL => buildEar(b, 1.0),
        EARR => buildEar(b, -1.0),
        ANTL => buildAntler(b, &rng, 1.0),
        ANTR => buildAntler(b, &rng, -1.0),
        STALK => buildStalk(b, &rng, rest),
        BLOOM => buildBloom(b, &rng, rest),
        TAIL0, TAIL1, TAIL2 => buildTail(b, &rng, i, rest),
        else => {
            if (i >= PET0 and i < PET0 + NPETAL) buildPetal(b, &rng, rowFor(i)) else buildLimbBone(b, i, rest, &rng);
        },
    }
}

fn buildPelvis(b: *Builder, rng: *mathx.Rng) void {
    b.setMat(.hide);
    b.addBlob(v3(0, 0.006 * W, 0.02 * W), v3(0.150 * W, 0.166 * W, 0.216 * W), 6, 10, HIDE);
    b.addBlob(v3(0, 0.104 * W, -0.01 * W), v3(0.118 * W, 0.070 * W, 0.142 * W), 5, 9, HIDE_DK);
    // THE HAUNCHES STAND PROUD of the croup: a deer's drive is all behind, and buried in one blob the rump
    // reads as the end of a barrel.
    b.addBlob(v3(0.120 * W, -0.014 * W, -0.01 * W), v3(0.084 * W, 0.150 * W, 0.146 * W), 5, 9, HIDE_LT);
    b.addBlob(v3(-0.116 * W, -0.006 * W, 0.00 * W), v3(0.080 * W, 0.144 * W, 0.142 * W), 5, 9, HIDE_LT);
    b.addBlob(v3(0, -0.098 * W, 0.05 * W), v3(0.102 * W, 0.054 * W, 0.142 * W), 4, 8, BELLY);
    b.setMat(.bark);
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const x = (@as(f32, @floatFromInt(k)) - 1.5) * 0.058 * W;
        b.addCapsule(
            v3(x, 0.066 * W + rng.range(-0.012, 0.012) * W, -0.136 * W),
            v3(x * 1.25, -0.033 * W, 0.146 * W),
            0.016 * W * rng.range(0.7, 1.3),
            0.010 * W,
            5,
            STALK_DK,
        );
    }
    // …and a cluster of shut buds over ONE hip. Asymmetric on purpose; a pair reads as anatomy.
    b.setMat(.plant);
    var j: u32 = 0;
    while (j < 3) : (j += 1) {
        const at = v3(0.112 * W + rng.range(-0.03, 0.03) * W, 0.070 * W + @as(f32, @floatFromInt(j)) * 0.034 * W, -0.06 * W + rng.range(-0.04, 0.04) * W);
        const rr = 0.022 * W * rng.range(0.7, 1.35);
        b.addBlob(at, v3(rr, rr * 1.9, rr), 4, 6, CALYX);
        b.addBlob(v3(at.x, at.y + rr * 1.7, at.z), v3(rr * 0.5, rr * 0.7, rr * 0.5), 3, 6, HUSK);
    }
}

/// The loin, and **IT IS A WAIST OR THE WHOLE TRUNK IS ONE TUBE** — a real pinch between chest and hip is what
/// lets the haunches read as haunches. A deer's is deeper than a hound's: the barrel is shallower and the
/// coupling longer.
fn buildLoin(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    const off = mathx.subV(rest[CHEST], rest[SPINE]);
    const len = mathx.lenV(off);
    b.setMat(.hide);
    b.addCapsule(v3(0, 0, -0.03 * W), mathx.scaleV(off, 1.04), 0.118 * W, 0.148 * W, 11, HIDE);
    b.addBlob(v3(0, -0.078 * W, len * 0.55), v3(0.096 * W, 0.042 * W, len * 0.48), 4, 9, BELLY);
    // FOUR vertebral knuckles, graded and uneven. Relief is a few PERCENT of the mass, no more.
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const u = (@as(f32, @floatFromInt(k)) + 0.5) / 4.0;
        const rr = 0.034 * W * rng.range(0.78, 1.25) * (1.10 - 0.25 * u);
        b.addBlob(
            v3(rng.signed() * 0.006 * W, 0.126 * W + 0.012 * W * u, len * u),
            v3(rr * 0.8, rr, rr * 1.35),
            4,
            7,
            HIDE_DK,
        );
    }
}

fn buildChest(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    b.setMat(.hide);
    b.addBlob(v3(0, -0.010 * W, 0.02 * W), v3(0.190 * W, 0.238 * W, 0.228 * W), 7, 11, HIDE);
    b.addBlob(v3(0, 0.112 * W, -0.04 * W), v3(0.150 * W, 0.088 * W, 0.172 * W), 5, 9, HIDE_DK);
    b.addBlob(v3(0, -0.144 * W, 0.03 * W), v3(0.140 * W, 0.080 * W, 0.176 * W), 5, 9, BELLY);
    b.addBlob(v3(0.136 * W, 0.030 * W, 0.02 * W), v3(0.054 * W, 0.126 * W, 0.136 * W), 4, 8, HIDE_LT);
    b.addBlob(v3(-0.132 * W, 0.024 * W, 0.03 * W), v3(0.051 * W, 0.120 * W, 0.132 * W), 4, 8, HIDE_LT);
    // **THE SOCKET, AND IT IS ON THE WITHERS.** The stalk is 0.12 m through where it leaves a 0.28 m chest, and
    // a stem that thin butted onto a mass that thick reads as stuck on. Sunk, not stood on: proud it comes back
    // as a ball bolted to the back, and relief is a few percent of the mass.
    const socket = mathx.subV(rest[STALK], rest[CHEST]);
    b.addBlob(v3(0, socket.y * 0.72, socket.z * 0.72), v3(0.124 * W, 0.076 * W, 0.120 * W), 5, 10, HIDE);
    b.setMat(.bark);
    b.addBlob(v3(0, socket.y, socket.z), v3(0.092 * W, 0.058 * W, 0.090 * W), 4, 10, STALK_DK);
    // THE COLLAR OF SPENT FLOWERS lodged where the stalk leaves the shoulders. Round the BACK three-quarters
    // only: the front is where a blade lands and a ruff there would read as armour it does not have.
    b.setMat(.plant);
    var k: u32 = 0;
    while (k < 9) : (k += 1) {
        const a = std.math.pi * 0.35 + std.math.pi * 1.30 * (@as(f32, @floatFromInt(k)) + rng.range(-0.3, 0.3)) / 9.0;
        const rr = 0.122 * W;
        const at = v3(mathx.cosf(a) * rr, socket.y - 0.020 * W + rng.range(-0.02, 0.02) * W, socket.z + mathx.sinf(a) * rr * 0.5);
        const l = 0.066 * W * rng.range(0.55, 1.35);
        b.addCapsule(
            at,
            v3(at.x * 1.30, at.y - l * 0.75, at.z - l * 0.55),
            0.019 * W * rng.range(0.7, 1.2),
            0.008 * W,
            5,
            if (rng.float() < 0.45) HUSK else CALYX,
        );
    }
}

/// A DEER'S NECK IS MUSCLE, NOT A STALK — a graded column of hide with the crest standing along the top of it
/// and the windpipe under. It is the one part of this animal that is only animal.
fn buildNeck(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    const off = mathx.subV(rest[HEAD], rest[NECK]);
    const len = mathx.lenV(off);
    const dir = if (len > 1e-5) mathx.scaleV(off, 1.0 / len) else v3(0, 1, 0);
    b.setMat(.hide);
    b.addCapsule(v3(0, 0, 0), mathx.scaleV(dir, len * 1.04), 0.098 * W, 0.062 * W, 10, HIDE);
    // The CREST along the top and the throat-line under: two ridges of a few percent, which is all relief is.
    b.addCapsule(
        v3(0, 0.052 * W, -0.014 * W),
        v3(dir.x * len * 0.92, dir.y * len * 0.92 + 0.030 * W, dir.z * len * 0.92 - 0.008 * W),
        0.032 * W,
        0.018 * W,
        6,
        HIDE_LT,
    );
    b.addCapsule(
        v3(0, -0.048 * W, 0.028 * W),
        v3(dir.x * len * 0.86, dir.y * len * 0.86 - 0.024 * W, dir.z * len * 0.86 + 0.018 * W),
        0.030 * W,
        0.020 * W,
        6,
        BELLY,
    );
    // A few shut buds along the crest — the fungus has run up the neck as well as out of the back.
    b.setMat(.plant);
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const u = 0.18 + 0.62 * @as(f32, @floatFromInt(k)) / 3.0;
        const rr = 0.018 * W * rng.range(0.7, 1.4);
        const at = v3(rng.signed() * 0.022 * W, dir.y * len * u + 0.056 * W, dir.z * len * u - 0.012 * W);
        b.addBlob(at, v3(rr, rr * 1.7, rr), 4, 6, if (k & 1 == 0) CALYX else CALYX_LT);
    }
}

/// **A SKULL, NOT A MUZZLE ON A BALL.** A deer's head is a long wedge: braincase at the back, a straight nasal
/// run forward of it, and the whole thing narrower than the neck that carries it.
fn buildSkull(b: *Builder, rng: *mathx.Rng) void {
    b.setMat(.hide);
    b.addBlob(v3(0, 0.010 * W, -0.012 * W), v3(0.064 * W, 0.070 * W, 0.078 * W), 6, 10, HIDE);
    b.addBlob(v3(0, -0.006 * W, 0.062 * W), v3(0.044 * W, 0.048 * W, 0.082 * W), 6, 10, HIDE_DK);
    b.addBlob(v3(0, -0.020 * W, 0.126 * W), v3(0.034 * W, 0.036 * W, 0.036 * W), 5, 9, MUZZLE);
    // The brow ridges and the cheek: a few percent proud, which is what a skull under hide looks like.
    b.addBlob(v3(0.042 * W, 0.038 * W, 0.018 * W), v3(0.026 * W, 0.020 * W, 0.030 * W), 4, 7, HIDE_LT);
    b.addBlob(v3(-0.042 * W, 0.038 * W, 0.018 * W), v3(0.026 * W, 0.020 * W, 0.030 * W), 4, 7, HIDE_LT);
    b.setMat(.plain);
    b.addBlob(v3(0.052 * W, 0.012 * W, 0.026 * W), v3(0.019 * W, 0.021 * W, 0.017 * W), 5, 8, EYE);
    b.addBlob(v3(-0.052 * W, 0.012 * W, 0.026 * W), v3(0.019 * W, 0.021 * W, 0.017 * W), 5, 8, EYE);
    // …and the fungus has taken the poll. Small buds crowding the base of the rack, which is where it started.
    b.setMat(.plant);
    var k: u32 = 0;
    while (k < 5) : (k += 1) {
        const a = rng.angle();
        const rr = 0.014 * W * rng.range(0.7, 1.5);
        b.addBlob(
            v3(mathx.cosf(a) * 0.038 * W, 0.062 * W + rng.range(-0.01, 0.02) * W, -0.020 * W + mathx.sinf(a) * 0.030 * W),
            v3(rr, rr * 1.6, rr),
            4,
            6,
            if (k & 1 == 0) CALYX else HUSK,
        );
    }
}

fn buildJaw(b: *Builder, rng: *mathx.Rng) void {
    b.setMat(.hide);
    b.addCapsule(v3(0, 0, 0), v3(0, -0.008 * W, 0.092 * W), 0.030 * W, 0.022 * W, 7, HIDE_DK);
    b.addBlob(v3(0, -0.012 * W, 0.092 * W), v3(0.024 * W, 0.020 * W, 0.026 * W), 4, 7, MUZZLE);
    _ = rng;
}

fn buildEar(b: *Builder, side: f32) void {
    b.setMat(.hide);
    // A deer's ear is a big cupped leaf — the one part of the animal that is bigger than a dog's.
    b.addCapsule(v3(0, 0, 0), v3(side * 0.036 * W, 0.078 * W, -0.030 * W), 0.020 * W, 0.030 * W, 7, HIDE);
    b.addBlob(v3(side * 0.030 * W, 0.064 * W, -0.024 * W), v3(0.026 * W, 0.044 * W, 0.014 * W), 5, 8, HIDE_LT);
}

/// **THE RACK, AND IT IS A DEAD LIMB — SO IT USES THE ONE THE TREES USE** (`propwood.deadLimbTinted`): out on
/// its own axis, up to an elbow, then DROOPING off the line to a blunt snap. Nothing dead is straight and
/// nothing ends in a point (AGENTS.md), and an antler is the most dead-limb-shaped thing on any animal.
fn buildAntler(b: *Builder, rng: *mathx.Rng, side: f32) void {
    b.setMat(.bark);
    // THE BEAM: up and out, sweeping back. Three links so it curves instead of leaning.
    const p0 = v3(0, 0, 0);
    const p1 = v3(side * 0.052 * W, 0.104 * W, -0.030 * W);
    const p2 = v3(side * 0.108 * W, 0.196 * W, -0.014 * W);
    const p3 = v3(side * 0.132 * W, 0.262 * W, 0.052 * W);
    b.addCapsule(p0, p1, 0.024 * W, 0.019 * W, 6, HORN);
    b.addCapsule(p1, p2, 0.019 * W, 0.015 * W, 6, HORN);
    b.addCapsule(p2, p3, 0.015 * W, 0.011 * W, 6, HORN_LT);
    // …and a blunt crown, because nothing ends in a point.
    b.addBlob(p3, v3(0.013 * W, 0.012 * W, 0.013 * W), 4, 7, HORN_LT);
    // THREE TINES, uneven, off the outer half of the beam — the wabi-sabi is BETWEEN them, not along one.
    const AT = [3]rl.Vector3{ p1, p2, v3(side * 0.120 * W, 0.230 * W, 0.018 * W) };
    const REACH = [3]f32{ 0.118, 0.086, 0.062 };
    for (AT, REACH, 0..) |root, reach, k| {
        const a = mathx.radians(side * (56.0 + 30.0 * @as(f32, @floatFromInt(k)) + rng.range(-14, 14)));
        wood.deadLimbTinted(b, rng, root, a, reach * W * rng.range(0.82, 1.20), 0.052 * W, 0.013 * W, 0, HORN, HORN_LT);
    }
    // The velvet has rotted and the fungus is in it: a few buds crowding the burr.
    b.setMat(.plant);
    var k: u32 = 0;
    while (k < 3) : (k += 1) {
        const rr = 0.012 * W * rng.range(0.7, 1.4);
        b.addBlob(
            v3(side * (0.020 + rng.range(0, 0.03)) * W, 0.024 * W + @as(f32, @floatFromInt(k)) * 0.024 * W, rng.signed() * 0.016 * W),
            v3(rr, rr * 1.5, rr),
            4,
            6,
            if (k & 1 == 0) CALYX else HUSK,
        );
    }
}

/// **THE STALK IS WOOD, AND IT IS A CHAIN AND NOT A PIPE.** Five sheaths overlapping well past their own
/// joints, radii grading down, each leaning its own hair off the axis — and the top is DELIBERATELY thin,
/// because the bloom's collar sleeves down over it and that is what covers the furl and the stretch.
fn buildStalk(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    const off = mathx.subV(rest[BLOOM], rest[STALK]);
    const len = mathx.lenV(off);
    const dir = if (len > 1e-5) mathx.scaleV(off, 1.0 / len) else v3(0, 1, 0);
    var side = mathx.crossV(dir, v3(0, 0, 1));
    side = if (mathx.lenV(side) > 1e-4) mathx.normV(side) else v3(1, 0, 0);
    const fwd = mathx.normV(mathx.crossV(side, dir));

    const at = struct {
        fn on(d: rl.Vector3, s: rl.Vector3, f: rl.Vector3, l: f32, u: f32, sx: f32, sz: f32) rl.Vector3 {
            return v3(
                d.x * l * u + s.x * sx + f.x * sz,
                d.y * l * u + s.y * sx + f.y * sz,
                d.z * l * u + s.z * sx + f.z * sz,
            );
        }
    }.on;

    const SHEATH = 5;
    const RAD = [SHEATH + 1]f32{ 0.086, 0.080, 0.074, 0.066, 0.058, 0.050 };
    // The S: a lean of 0.024 W either way over the run, which is under 4% of the length — enough to read, not
    // enough to leave the bloom off its own stalk.
    const LEAN = [SHEATH + 1]f32{ 0.000, 0.018, 0.024, 0.008, -0.014, 0.000 };
    b.setMat(.bark);
    var k: u32 = 0;
    while (k < SHEATH) : (k += 1) {
        const ua = @as(f32, @floatFromInt(k)) / SHEATH;
        const ub = @as(f32, @floatFromInt(k + 1)) / SHEATH + (if (k + 1 < SHEATH) @as(f32, 0.09) else 0.0);
        b.addCapsule(
            at(dir, side, fwd, len, ua, LEAN[k] * W, LEAN[k] * W * 0.4),
            at(dir, side, fwd, len, ub, LEAN[k + 1] * W, LEAN[k + 1] * W * 0.4),
            RAD[k] * W,
            RAD[k + 1] * W,
            10,
            if (k == 0) STALK_DK else STALKC,
        );
    }
    const NODE = [4]f32{ 0.19, 0.42, 0.63, 0.84 };
    for (NODE, 0..) |u, ni| {
        const c = at(dir, side, fwd, len, u, lerpF(LEAN[0], LEAN[SHEATH], u) * W, 0);
        const rr = lerpF(0.086, 0.050, u) * W * rng.range(1.12, 1.40);
        b.addBlob(c, v3(rr, rr * 0.62, rr), 4, 9, if (ni & 1 == 0) STALK_LT else STALKC);
        // **A SPUR LEAVES ON ITS AXIS, REACHES AN ELBOW AND DROOPS OFF THE LINE** — two links, and the second
        // one hangs. One straight capsule reads as a thorn and shouts louder than the flower.
        const a = rng.angle();
        const outx = mathx.cosf(a);
        const outz = mathx.sinf(a);
        const sl = rr * rng.range(0.62, 1.05);
        const out = struct {
            fn spur(cc: rl.Vector3, sd: rl.Vector3, fd: rl.Vector3, d: rl.Vector3, ox: f32, oz: f32, reach: f32, drop: f32) rl.Vector3 {
                return v3(
                    cc.x + sd.x * ox * reach + fd.x * oz * reach - d.x * drop,
                    cc.y + sd.y * ox * reach + fd.y * oz * reach - d.y * drop,
                    cc.z + sd.z * ox * reach + fd.z * oz * reach - d.z * drop,
                );
            }
        }.spur;
        const elbow = out(c, side, fwd, dir, outx, outz, rr * 0.85 + sl * 0.60, sl * 0.20);
        b.addCapsule(out(c, side, fwd, dir, outx, outz, rr * 0.70, 0), elbow, rr * 0.24, rr * 0.15, 5, HUSK);
        b.addCapsule(elbow, out(c, side, fwd, dir, outx, outz, rr * 0.85 + sl * 0.95, sl * 0.90), rr * 0.15, rr * 0.06, 4, HUSK);
    }
    // …and the FIBRES up the outside. Three, all in one tone: two alternated segment by segment band a shaft
    // like a barber's pole (AGENTS.md).
    var f: u32 = 0;
    while (f < 3) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 3.0 + rng.range(-0.4, 0.4);
        const rr = 0.064 * W;
        const ox = mathx.cosf(a) * rr;
        const oz = mathx.sinf(a) * rr;
        b.addCapsule(
            at(dir, side, fwd, len, 0.06, ox, oz),
            at(dir, side, fwd, len, 0.94, ox * 0.52, oz * 0.52),
            0.016 * W * rng.range(0.75, 1.25),
            0.008 * W,
            5,
            STALK_LT,
        );
    }
}

fn buildBloom(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    const dn = mathx.normV(mathx.subV(rest[STALK], rest[BLOOM]));
    // **DOWN THE STALK'S BORE BY THE WHOLE TRAVEL PLUS A HAND.** The furl pulls the bloom 0.26 W INTO the
    // sheath and the rise pushes it 0.16 W out, so the collar has to be longer than their sum or one end of the
    // move shows daylight between flower and stem.
    b.setMat(.bark);
    b.addCapsule(
        mathx.scaleV(dn, (STALK_FURL_IN + STALK_STRETCH + 0.09) * W),
        mathx.scaleV(dn, 0.012 * W),
        0.054 * W,
        0.064 * W,
        9,
        STALK_DK,
    );
    b.addBlob(mathx.scaleV(dn, 0.026 * W), v3(0.076 * W, 0.068 * W, 0.074 * W), 5, 10, STALKC);

    b.setMat(.plant);
    // Small and set BACK: standing in the middle of the open corolla it reads as a hole punched through the
    // flower. It is a knuckle behind the light, not part of the light.
    b.addBlob(v3(0, 0, -0.044 * W), v3(0.084 * W, 0.082 * W, 0.056 * W), 6, 10, CALYX_LT);
    // FIVE SEPALS clasping from behind, each a three-link chain that leaves on its axis, reaches an elbow and
    // DROOPS. One is broken short, which is the only thing that says this flower has been open before.
    const SEP = [5]f32{ 1.00, 0.82, 1.16, 0.38, 0.92 };
    for (SEP, 0..) |share, k| {
        const a = std.math.tau * (@as(f32, @floatFromInt(k)) + rng.range(-0.20, 0.20)) / 5.0;
        const d = ringDir(mathx.degrees(a));
        const l = 0.062 * W * share;
        var pt = v3(d.x * 0.078 * W, d.y * 0.078 * W, 0.006 * W);
        const col = if (k & 1 == 0) CALYX_LT else CALYX;
        var seg: u32 = 0;
        var rr = 0.020 * W * rng.range(0.85, 1.15);
        while (seg < 3) : (seg += 1) {
            const droop = (0.10 + 0.55 * @as(f32, @floatFromInt(seg))) * l;
            const to = v3(
                pt.x + d.x * l * (0.62 - 0.22 * @as(f32, @floatFromInt(seg))),
                pt.y + d.y * l * (0.62 - 0.22 * @as(f32, @floatFromInt(seg))) - droop * 0.30,
                pt.z - l * 0.55 - droop * 0.35,
            );
            b.addCapsule(pt, to, rr, rr * 0.62, 5, col);
            pt = to;
            rr *= 0.62;
        }
    }

    // **THE ONE LIGHT ON THE ANIMAL, AND IT HAS TO BE FOUND FROM ACROSS A FIELD.** Built as a PROUD BOSS and
    // not a cup: a closed ellipsoid has no inside, so a sunk "throat" shows the player its dark back. Four
    // shells stepping out and up the axis, each hotter and smaller — a cone of light rather than a hole.
    // **AND IT GRADES, OR EMISSIVE FLATTENS IT TO A LAMP**: form has to come from the ALBEDO STEPS.
    b.setMat(.plain);
    b.addBlob(v3(0, 0, 0.000 * W), v3(0.100 * W, 0.100 * W, 0.052 * W), 7, 11, THROAT_HALO);
    b.addBlob(v3(0, 0, 0.026 * W), v3(0.070 * W, 0.070 * W, 0.052 * W), 7, 11, THROAT_LIP);
    b.addBlob(v3(0, 0, 0.050 * W), v3(0.048 * W, 0.048 * W, 0.044 * W), 6, 10, THROAT_DEEP);
    b.addBlob(v3(0, 0, 0.070 * W), v3(0.027 * W, 0.027 * W, 0.026 * W), 5, 9, THROAT);
    // **THE FANGS ARE THE IRIS.** Nine, arching in and forward OVER the light — dark horn for two-thirds of
    // their reach and pale only at the point, so the light is read BETWEEN them and not as a badge.
    var k: u32 = 0;
    while (k < 9) : (k += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(k)) + rng.range(-0.26, 0.26)) / 9.0;
        const d = ringDir(mathx.degrees(a));
        const rr = 0.100 * W;
        const l = 0.054 * W * rng.range(0.62, 1.36);
        const bend = v3(d.x * rr * 0.52, d.y * rr * 0.52, 0.006 * W + l * 0.60);
        b.addCapsule(v3(d.x * rr, d.y * rr, 0.000 * W), bend, 0.019 * W * rng.range(0.85, 1.15), 0.009 * W, 6, FANG);
        b.addCapsule(bend, v3(d.x * rr * 0.20, d.y * rr * 0.20, 0.006 * W + l), 0.009 * W, 0.0035 * W, 5, TOOTH);
    }
    // …and the ANTHERS, a TUFT and not a wheel: seven leaning FORWARD, clustered inside the fang ring, which
    // reads as pollen standing in the gullet. **THIS IS WHAT THE VOLLEY COMES OUT OF.**
    var f: u32 = 0;
    while (f < 7) : (f += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(f)) + rng.range(-0.30, 0.30)) / 7.0;
        const d = ringDir(mathx.degrees(a));
        const l = 0.048 * W * rng.range(0.58, 1.42);
        const tip = v3(d.x * (0.036 * W + l * 0.26), d.y * (0.036 * W + l * 0.26), 0.044 * W + l * 0.92);
        b.addCapsule(v3(d.x * 0.038 * W, d.y * 0.038 * W, 0.030 * W), tip, 0.0055 * W, 0.0038 * W, 5, STAMEN);
        const ar = 0.0080 * W * rng.range(0.75, 1.3);
        b.addBlob(tip, v3(ar, ar, ar * 1.5), 3, 6, STAMEN);
    }
}

fn petalTone(t: u8) rl.Color {
    return switch (t) {
        0 => PETAL_DK,
        2 => PETAL_LT,
        else => PETAL,
    };
}

/// **A QUILL AND A TONGUE, ON ONE BONE.** The outer quill is the silhouette — round in section, tapering,
/// bowing out and recurving at the tip. The tongue is the second tier: short, broad, flattened, and pitched
/// `INNER_TILT` further in by a rotation baked into its SPINE rather than into the rig, so one fold drives both.
fn buildPetal(b: *Builder, rng: *mathx.Rng, q: Petal) void {
    const len = PETAL_LEN * q.len;
    b.setMat(.plant);

    // THE QUILL. One tone up its whole length; only the last link is bleached.
    const tone = petalTone(q.tone);
    var at = sweptAt(len, 0, q.sweep);
    var j: u32 = 1;
    while (j <= PETAL_SEGS) : (j += 1) {
        const u = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(PETAL_SEGS));
        const to = sweptAt(len, u, q.sweep);
        const last = j == PETAL_SEGS;
        b.addCapsule(at, to, quillAt(u - 1.0 / @as(f32, @floatFromInt(PETAL_SEGS)), q), quillAt(u, q), 6, if (last) PETAL_TIP else tone);
        at = to;
    }
    // …and a blunt swelling at the tip, because nothing ends in a point.
    b.addBlob(at, v3(QUILL_R * 0.9, QUILL_R * 0.9, QUILL_R * 0.9), 4, 6, PETAL_TIP);

    // THE TONGUE, pitched further in and flattened across.
    const tilt = mathx.radians(INNER_TILT);
    const ilen = len * INNER_LEN;
    var s: u32 = 0;
    while (s < 5) : (s += 1) {
        const ua = @as(f32, @floatFromInt(s)) / 5.0;
        const ub = @as(f32, @floatFromInt(s + 1)) / 5.0;
        const pa = v3(0, ilen * ua * mathx.cosf(tilt), ilen * ua * mathx.sinf(tilt));
        const pb = v3(0, ilen * ub * mathx.cosf(tilt), ilen * ub * mathx.sinf(tilt));
        const wa = INNER_W * q.wide * (0.55 + 0.45 * mathx.sinf(ua * std.math.pi));
        const wb = INNER_W * q.wide * (0.55 + 0.45 * mathx.sinf(ub * std.math.pi));
        b.addCapsule(pa, pb, wa * 0.42, wb * 0.42, 5, PETAL_IN);
    }
    _ = rng;
}

fn sweptAt(len: f32, u: f32, sweepDeg: f32) rl.Vector3 {
    const p = spineAt(len, u);
    const a = mathx.radians(sweepDeg) * u * u;
    return v3(p.x * mathx.cosf(a) - p.z * mathx.sinf(a) + mathx.sinf(a) * p.y * 0.35, p.y, p.z * mathx.cosf(a) + mathx.sinf(a) * p.y * 0.9);
}

fn quillAt(u: f32, q: Petal) f32 {
    const uu = mathx.clampF(u, 0, 1);
    var r = QUILL_R * q.wide * (1.0 - 0.62 * uu);
    if (q.notch > 0) {
        const d = @abs(uu - q.notchAt);
        r *= 1.0 - q.notch * mathx.clampF(1.0 - d * 8.0, 0, 1);
    }
    return mathx.maxF(r, QUILL_R * 0.16);
}

fn spineAt(len: f32, u: f32) rl.Vector3 {
    const bow = PETAL_BOW * u * u + PETAL_RECURVE * u * u * u * u * u;
    return v3(0, len * u, len * bow);
}

fn buildTail(b: *Builder, rng: *mathx.Rng, i: usize, rest: [N]rl.Vector3) void {
    const len: f32 = switch (i) {
        TAIL0 => mathx.lenV(mathx.subV(rest[TAIL0], rest[TAIL1])),
        TAIL1 => mathx.lenV(mathx.subV(rest[TAIL1], rest[TAIL2])),
        else => 0.14 * W,
    };
    const r0: f32 = 0.042 * W * (if (i == TAIL0) @as(f32, 1.0) else if (i == TAIL1) @as(f32, 0.76) else @as(f32, 0.56));
    const to = v3(0, -len * 0.35, -len * 0.9);
    b.setMat(.hide);
    b.addCapsule(v3(0, 0, 0), to, r0, r0 * 0.74, 8, HIDE_DK);
    if (i != TAIL2) return;
    // THE FLAG: a deer's tail ends pale, and it is the one bright thing at the back of a very dark animal.
    b.addBlob(v3(to.x, to.y - 0.012 * W, to.z - 0.022 * W), v3(0.034 * W, 0.048 * W, 0.056 * W), 5, 8, HIDE_LT);
    b.setMat(.plant);
    var k: u32 = 0;
    while (k < 5) : (k += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(k)) + rng.range(-0.3, 0.3)) / 5.0;
        const l = 0.046 * W * rng.range(0.5, 1.4);
        b.addCapsule(
            v3(to.x + mathx.cosf(a) * 0.018 * W, to.y - 0.028 * W, to.z - 0.054 * W),
            v3(to.x + mathx.cosf(a) * (0.018 * W + l), to.y - 0.028 * W + mathx.sinf(a) * l * 0.6, to.z - 0.054 * W - l * 0.8),
            0.008 * W,
            0.0025 * W,
            4,
            HUSK,
        );
    }
}

/// Off the rest chain's own segment lengths, so a resized animal cannot grow a leg the solver does not believe
/// in. **THE LEGS ARE THE SEAM BETWEEN THE TWO HALVES**: hide over the shoulder, wood from the elbow down —
/// and a deer's are longer and thinner than a hound's, which is most of the silhouette.
fn buildLimbBone(b: *Builder, i: usize, rest: [N]rl.Vector3, rng: *mathx.Rng) void {
    const child: ?usize = blk: {
        for (0..N) |c| {
            if (PARENT[c] == @as(i32, @intCast(i))) break :blk c;
        }
        break :blk null;
    };
    if (child == null) {
        buildHoof(b, rng);
        return;
    }
    const len: f32 = mathx.lenV(mathx.subV(rest[i], rest[child.?]));
    const upper = i == wolf.SHL or i == wolf.SHR or i == wolf.HIPL or i == wolf.HIPR;
    if (upper) {
        b.setMat(.hide);
        b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.062 * W, 0.038 * W, 9, HIDE);
        b.addBlob(v3(rng.signed() * 0.006 * W, -len * 0.20, 0.006 * W), v3(0.070 * W, 0.062 * W, 0.066 * W), 4, 9, HIDE_LT);
        b.setMat(.bark);
        b.addCapsule(v3(0, -len * 0.10, -0.048 * W), v3(0, -len * 0.96, -0.028 * W), 0.014 * W, 0.009 * W, 5, STALK_DK);
        return;
    }
    b.setMat(.bark);
    // **SLENDER, BECAUSE IT IS A DEER.** 0.034 W against the hound's 0.042 is a cannon bone you can see the
    // ground through, and it is what makes the animal read as leggy rather than merely tall.
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.034 * W, 0.024 * W, 8, LIMB);
    // The joint above it and the fetlock swelling at the bottom — SMALL, or they read as bamboo nodes.
    b.addBlob(v3(0, -0.006 * W, 0.004 * W), v3(0.040 * W, 0.034 * W, 0.038 * W), 4, 8, LIMB_LT);
    b.addBlob(v3(0, -len * 0.94, 0.004 * W), v3(0.032 * W, 0.026 * W, 0.032 * W), 4, 8, LIMB_LT);
    var k: u32 = 0;
    while (k < 2) : (k += 1) {
        const a = rng.angle();
        const rr = 0.032 * W;
        b.addCapsule(
            v3(mathx.cosf(a) * rr, -len * 0.12, mathx.sinf(a) * rr),
            v3(mathx.cosf(a) * rr * 0.5, -len * 0.92, mathx.sinf(a) * rr * 0.5),
            0.009 * W * rng.range(0.7, 1.3),
            0.004 * W,
            4,
            STALK_DK,
        );
    }
}

/// **A CLOVEN HOOF, NOT A PAW** — two toes with a split between them and the dewclaws behind. It is the last
/// thing that would still say "dog" if it were left alone.
fn buildHoof(b: *Builder, rng: *mathx.Rng) void {
    b.setMat(.bark);
    const spread = 0.019 * W;
    for ([_]f32{ 1.0, -1.0 }) |side| {
        const l = 0.062 * W * rng.range(0.92, 1.10);
        const tip = v3(side * spread * 1.15, -0.052 * W, 0.030 * W + l);
        b.addCapsule(v3(side * spread, -0.006 * W, 0.006 * W), tip, 0.020 * W, 0.013 * W, 6, LIMB);
        // Blunt at the toe: nothing ends in a point, and a hoof least of all.
        b.addBlob(tip, v3(0.013 * W, 0.011 * W, 0.012 * W), 4, 7, LIMB_LT);
    }
    // The dewclaws, high and behind, and only one of them is worth seeing.
    b.addCapsule(v3(0.024 * W, 0.010 * W, -0.026 * W), v3(0.030 * W, -0.020 * W, -0.040 * W), 0.009 * W, 0.004 * W, 4, LIMB);
    b.addCapsule(v3(-0.022 * W, 0.008 * W, -0.024 * W), v3(-0.027 * W, -0.016 * W, -0.036 * W), 0.008 * W, 0.004 * W, 4, LIMB);
}

test "THE FLOWER RISES OUT OF ITS BACK, AND ONLY FOR THE VOLLEY" {
    // **THE RISE IS THE WHOLE TELL** (owner: a large flower that rises out of its back). Measured off the
    // posed bloom, in metres, at every state a player can catch it in — a stalk that stood up for a stagger
    // or a charge would be a tell that means nothing.
    var d = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
    d.pose();
    const furled = rl.math.vector3Transform(mathx.zero3, d.xf[BLOOM]).y;
    d.stageGather(1.0);
    const risen = rl.math.vector3Transform(mathx.zero3, d.xf[BLOOM]).y;
    // **AND IT MUST STAND OVER ITS OWN BACK, NOT OVER THE ANIMAL'S HEAD.** The lean is where a rest chain
    // authored in one frame and a rotation applied in another can quietly disagree, and a photograph cannot
    // settle it: measured against the WITHERS, the flower has to end up BEHIND them at both ends of the rise.
    var up = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
    up.stageGather(1.0);
    const withers = rl.math.vector3Transform(mathx.zero3, up.xf[CHEST]).z;
    const bloomZ = rl.math.vector3Transform(mathx.zero3, up.xf[BLOOM]).z;
    var down = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
    down.pose();
    const furledZ = rl.math.vector3Transform(mathx.zero3, down.xf[BLOOM]).z;
    std.debug.print("\n  deer: the bloom rides {d:.2} m furled and stands to {d:.2} m — {d:.2} m of rise on a {d:.2} m animal\n", .{ furled, risen, risen - furled, W });
    std.debug.print("    fore-aft: withers at {d:.2} m, the flower at {d:.2} m risen and {d:.2} m furled — {d:.2} m and {d:.2} m BEHIND the shoulder\n", .{ withers, bloomZ, furledZ, withers - bloomZ, withers - furledZ });
    try std.testing.expect(bloomZ < withers and furledZ < withers);
    try std.testing.expect(risen > furled + 0.35);
    // …and it clears the top of a man, which is what makes a volley come from over his head.
    try std.testing.expect(risen > heromod.H);

    // Furled everywhere else, on its own clock and nothing else's.
    for ([_]State{ .idle, .move, .flee, .butt }) |st| {
        var k = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
        k.state = st;
        k.t = 0.4;
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.riseAmt(), 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.openAmt(), 1e-6);
    }
    // A HEAVY stun blows the bud open and a light one does not — the window is worth aiming for or it is not
    // a window — but neither one raises the stalk.
    var hurt = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
    hurt.stagger(true);
    hurt.t = combat.foeStunDur(true) * 0.4;
    try std.testing.expect(hurt.openAmt() > 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), hurt.riseAmt(), 1e-6);
    hurt.stagger(false);
    hurt.t = combat.foeStunDur(false) * 0.4;
    try std.testing.expectApproxEqAbs(@as(f32, 0), hurt.openAmt(), 1e-6);
}

test "THE SPORES HANG IN THE AIR BEFORE THEY COME AT YOU — measured, and it is the whole move" {
    // **THE HANG IS THE ANSWER** (owner: they hover for a bit before homing in to you). Through the real pool:
    // not one of them may be steering before its hang is out, and every one must be after.
    var h = Herd{ .model = undefined };
    h.volley(v3(0, 2.2, 0), 0, 0);
    var lit: usize = 0;
    for (&h.spores) |*s| lit += @intFromBool(s.live);
    try std.testing.expectEqual(SPORES_PER_VOLLEY, lit);

    const dt = 1.0 / 120.0;
    var worst: ?foe.Blow = null;
    var t: f32 = 0;
    var firstHoming: f32 = -1;
    // The man is far enough off that nothing lands: this test is about the CLOCK, not the blow.
    const away = mathx.ground(0, 60);
    while (t < SPORE_LIFE) : (t += dt) {
        h.tickSpores(dt, away, &worst);
        var any = false;
        for (&h.spores) |*s| {
            if (s.homing()) any = true;
        }
        if (any and firstHoming < 0) firstHoming = t;
        if (t < SPORE_RISE + SPORE_HANG - dt) {
            for (&h.spores) |*s| try std.testing.expect(!s.homing());
        }
    }
    std.debug.print("  spore: {d} thrown, hangs {d:.2} s and turns over at {d:.2} s — a walking man covers {d:.1} m in that\n", .{ SPORES_PER_VOLLEY, SPORE_HANG, firstHoming, firstHoming * heromod.WALK_SPEED });
    try std.testing.expect(firstHoming >= SPORE_RISE + SPORE_HANG - 0.02);
    // …and the hang is worth having: long enough to WALK out of the volley, not merely to roll.
    try std.testing.expect(firstHoming * heromod.WALK_SPEED > 2.0);
    // …and the pool is empty again, or a herd that throws for a minute stops being able to.
    for (&h.spores) |*s| try std.testing.expect(!s.live);
}

test "A SPORE LANDS ON HIM, IS SPENT, AND CANNOT RUN HIM DOWN" {
    var h = Herd{ .model = undefined };
    const hero = mathx.ground(0, 6);
    h.volley(v3(0, 2.2, 0), 0, 0);
    const dt = 1.0 / 120.0;
    var worst: ?foe.Blow = null;
    var t: f32 = 0;
    while (t < SPORE_LIFE and worst == null) : (t += dt) h.tickSpores(dt, hero, &worst);
    const b = worst orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(SPORE_HIT.elem.at(.chaos), b.hit.elem.at(.chaos));
    std.debug.print("  spore: {d:.1} m/s against a {d:.1} m/s sprint — {d:.0}% of it, so a straight line is never the answer to him\n", .{ SPORE_HOME, heromod.SPRINT_SPEED, 100.0 * SPORE_HOME / heromod.SPRINT_SPEED });
    // **IT MAY NOT CHASE HIM DOWN A STRAIGHT LINE.** The hang is what makes the move fair, and a spore faster
    // than his sprint would take that back.
    try std.testing.expect(SPORE_HOME < heromod.SPRINT_SPEED);
    // A whole volley on one man is under the first boss's biggest single stroke.
    const volley = SPORE_HIT.raw() * @as(f32, @floatFromInt(SPORES_PER_VOLLEY));
    std.debug.print("  damage: one spore {d:.0}, a whole volley {d:.0}, the antlers {d:.0} | knight sweep {d:.0}, overhead {d:.0}\n", .{ SPORE_HIT.raw(), volley, BUTT_HIT.raw(), knightmod.SWEEP_HIT.raw(), knightmod.OVERHEAD_HIT.raw() });
    try std.testing.expect(volley < knightmod.OVERHEAD_HIT.raw());
    try std.testing.expect(BUTT_HIT.raw() < knightmod.SWEEP_HIT.raw());
    try std.testing.expectEqual(@as(f32, 0), BUTT_HIT.launch);
}

test "A VOLLEY THROWN FROM BELOW HIM SURVIVES THE THROAT — the earth is not wherever he is standing" {
    // **THE WORLD IS A SCULPTED HEIGHTFIELD** (AGENTS.md's Elevation), so `pos.y` is the ground under a body
    // and the two bodies' are different numbers. Read off the hero's alone, the despawn floor sat ABOVE the
    // bloom whenever he stood on a rise, and the deer's only ranged move died at the mouth of the flower.
    const dt = 1.0 / 120.0;
    const rise = 3.0;
    var worst: ?foe.Blow = null;
    // Where the throat actually is at the release, off the posed rig rather than a guess.
    var d = Deer.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.stageGather(1.0);
    const mouth = d.bloomPoint().y;

    var h = Herd{ .model = undefined };
    h.volley(v3(0, mouth, 0), 0, 0);
    const hero = v3(0, rise, 40);
    h.tickSpores(dt, hero, &worst);
    var lit: usize = 0;
    for (&h.spores) |*sp| lit += @intFromBool(sp.live);
    std.debug.print("\n  deer on ground {d:.2} m under him: throat at {d:.2} m, floor was {d:.2} m — {d} of {d} spores still in the air\n", .{ rise, mouth, rise + 0.05, lit, SPORES_PER_VOLLEY });
    try std.testing.expect(mouth < rise);
    try std.testing.expectEqual(SPORES_PER_VOLLEY, lit);

    // …and it still dies on earth: run it out and the pool empties inside one life.
    var t: f32 = 0;
    while (t < SPORE_LIFE + 0.5) : (t += dt) h.tickSpores(dt, hero, &worst);
    for (&h.spores) |*sp| try std.testing.expect(!sp.live);
}

test "THE STEER IS A CAP AND NOT A LERP — a spore he rolled behind still comes round inside its own life" {
    // The lerp form this replaced took 5.15 s to reverse against the 1.43 s `SPORE_TURN` claims, on a
    // post-hang life of 5.90 s — so the one bearing the hang exists for was the one that did not work.
    const dt = 1.0 / 60.0;
    const hero = mathx.ground(0, 0);
    var s = Spore{ .live = true, .at = v3(0, foe.HERO_CHEST, -12.0), .vel = v3(0, 0, -SPORE_HOME), .t = SPORE_RISE + SPORE_HANG };
    var turned: f32 = 0;
    var t: f32 = 0;
    while (t < SPORE_LIFE - (SPORE_RISE + SPORE_HANG)) : (t += dt) {
        const want = mathx.normV(mathx.subV(hero, s.at));
        const have = mathx.normV(s.vel);
        s.vel = mathx.scaleV(mathx.turnToward(have, want, SPORE_TURN * dt), SPORE_HOME);
        turned = t;
        if (mathx.lenV(mathx.subV(mathx.normV(s.vel), want)) < 0.02) break;
    }
    const ideal = std.math.pi / SPORE_TURN;
    std.debug.print("\n  spore steer: 180 deg round in {d:.2} s against the {d:.2} s the cap allows, on {d:.2} s of life after the hang\n", .{ turned, ideal, SPORE_LIFE - (SPORE_RISE + SPORE_HANG) });
    try std.testing.expect(turned < ideal * 1.1);
    try std.testing.expect(turned < SPORE_LIFE - (SPORE_RISE + SPORE_HANG));
}

test "IT NEVER SPITS INTO YOUR FACE, AND IT NEVER CLOSES INSIDE ITS OWN SKIRT" {
    // The two moves own different ground: inside `CORNER_R` the flower is no use, and the volley's band
    // starts outside it. A ring where neither is the answer would be ground you could simply stand on.
    const dt = 1.0 / 60.0;
    var near = Deer.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    const close = mathx.ground(0, 2.0);
    var t: f32 = 0;
    var spat = false;
    while (t < 6.0) : (t += dt) {
        near.leash.noteSeen();
        _ = near.update(dt, close, 400.0, .{});
        // He walks it down: the deer is put back on its post every frame, so the GAP is what is under test and
        // not whether a fleeing animal eventually gets far enough away to throw.
        near.pos = mathx.ground(0, 0);
        if (near.state == .spit) spat = true;
    }
    try std.testing.expect(!spat);
    std.debug.print("  bands: antlers to {d:.1} m, cornered inside {d:.1}, the volley {d:.1}..{d:.1}, keeps to {d:.1}\n", .{ BUTT_R, CORNER_R, SPIT_MIN, SPIT_MAX, KEEP_R });

    // …and stood on, it walks AWAY. A ranged animal that held its ground would be a melee one.
    var shy = Deer.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    const start = mathx.distXZ(shy.pos, close);
    var u: f32 = 0;
    while (u < 1.4) : (u += dt) {
        shy.leash.noteSeen();
        _ = shy.update(dt, close, 400.0, .{});
    }
    std.debug.print("  flight: pressed at {d:.1} m it is {d:.1} m off a second and a half later\n", .{ start, mathx.distXZ(shy.pos, close) });
    try std.testing.expect(mathx.distXZ(shy.pos, close) > start);
}

test "CORNERED IS A GAP AND A CLOCK — it gores when backing off stops working, and not before" {
    // **THE LAW**: `pinned` reads how far apart two bodies are and whether that distance opened. It reads
    // nothing about him. Held on it, the rack comes down; let it go and the clock is spent.
    const dt = 1.0 / 120.0;
    var d = Deer.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    var t: f32 = 0;
    var gored = false;
    var at: f32 = -1;
    while (t < 8.0 and !gored) : (t += dt) {
        d.leash.noteSeen();
        // He walks it down: the hero is held at a fixed short gap whatever the deer does, which is exactly
        // what a corner is. Nothing here touches the deer's own state.
        const hero = mathx.addV(d.pos, mathx.scaleV(mathx.headingDir(d.facing), 1.4));
        if (d.update(dt, hero, 400.0, .{}) != null) {
            gored = true;
            at = t;
        }
        if (d.state == .butt and at < 0) at = t;
    }
    std.debug.print("  cornered: held at 1.4 m, the rack came down at {d:.2} s (hold {d:.2} s)\n", .{ at, CORNER_HOLD });
    try std.testing.expect(gored);

    // …and a deer that is being LET GO never reaches the clock, however long the fight is.
    var free = Deer.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    var u: f32 = 0;
    var charged = false;
    while (u < 8.0) : (u += dt) {
        free.leash.noteSeen();
        // The gap OPENS every frame — he is backing off, so it is never cornered.
        const hero = mathx.ground(0, 3.0 + u * 1.2);
        _ = free.update(dt, hero, 400.0, .{});
        if (free.state == .butt) charged = true;
    }
    try std.testing.expect(!charged);
    try std.testing.expectApproxEqAbs(@as(f32, 0), free.pinned, 1e-4);
}

test "THE RACK LANDS ON THE MAN WHERE HE STANDS — thrown for real, at every stand its own gate allows" {
    // The knight's judge, asked of this one (AGENTS.md): the charge goes through the REAL `update` at a hero
    // stood across its own band, with the man shoved out to `closestApproach` as `env.resolveActor` would.
    const dt = 1.0 / 120.0;
    const probe = Deer.spawn(mathx.zero3, 0, 1.0, 0.0);
    const apart = foe.closestApproach(probe.bodyR());
    var misses: usize = 0;
    var thrown: usize = 0;
    for ([_]f32{ 0, 20, 40 }) |deg| {
        for ([_]f32{ 0.0, 0.4, 0.8, 1.0 }) |u| {
            const stand = mathx.lerpF(apart + 0.05, BUTT_R * 0.97, u);
            const off = mathx.radians(deg);
            thrown += 1;
            var d = Deer.spawn(mathx.zero3, 0, 1.0, 0.0);
            var hero = v3(@sin(off) * stand, 0, @cos(off) * stand);
            d.facing = off;
            d.state = .butt;
            d.t = 0;
            var hit = false;
            var guard: usize = 0;
            while (guard < 2000) : (guard += 1) {
                if (d.update(dt, hero, 400.0, .{}) != null) {
                    hit = true;
                    break;
                }
                // The drive SHOVES a man it runs into, as `env.resolveActor` does in the game.
                if (mathx.distXZ(d.pos, hero) < apart) {
                    const out = mathx.dirXZ(d.pos, hero);
                    hero = v3(d.pos.x + out.x * apart, 0, d.pos.z + out.z * apart);
                }
                if (d.state != .butt) break;
            }
            if (!hit) {
                misses += 1;
                std.debug.print("\n  charge at {d:.2} m, {d:.0} deg off: MISSED\n", .{ stand, deg });
            }
        }
    }
    std.debug.print("  rack: {d} stands thrown for real and landed\n", .{thrown});
    try std.testing.expectEqual(@as(usize, 0), misses);
}

test "THE OPEN THROAT COSTS IT, and the sphere holds the flower at both ends of its travel" {
    // **THE BLOOM IS THE WEAK POINT** — the same swing takes near twice off a bloomed body, and NOT off its
    // poise: `POISE_MAX` is solved to sit between the hero's two swings and a multiplier there would put a
    // light poke through it.
    var shut = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
    var open = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
    open.stageGather(1.0);
    open.t = SPIT_WIND;
    try std.testing.expectApproxEqAbs(@as(f32, 1), shut.frailty(), 1e-6);
    try std.testing.expect(open.frailty() > 1.8);
    std.debug.print("  throat: a blow is worth {d:.2}x on an open bloom, {d:.2}x on a shut one\n", .{ open.frailty(), shut.frailty() });

    // **AND THE SPHERE HAS TO HOLD IT** — a weak point no blade reaches is not one. The claim is the FLOWER
    // and the barrel, not every bone: a quadruped's nose and hooves live outside its hurt sphere here (the
    // wolf's at 0.42 on a 1.12 body), and swallowing a 1.37 m neck would mean hitting it by swinging at air.
    var probe = Deer.spawn(mathx.zero3, 0, 1.0, 1.0);
    probe.stageGather(1.0);
    const c = probe.centerWorld();
    const r = probe.hurtRadius();
    var worst: f32 = 0;
    var worstName: []const u8 = "";
    std.debug.print("  hurt sphere: r {d:.2} m about a centre {d:.2} m up\n", .{ r, c.y - probe.pos.y });
    for ([_]struct { i: usize, name: []const u8 }{
        .{ .i = BLOOM, .name = "bloom" },
        .{ .i = ANTL, .name = "antler" },
        .{ .i = HEAD, .name = "head" },
        .{ .i = JAW, .name = "muzzle" },
        .{ .i = wolf.HPAWL, .name = "hind hoof" },
        .{ .i = wolf.PAWL, .name = "fore hoof" },
        .{ .i = TAIL2, .name = "tail" },
    }) |row| {
        const at = rl.math.vector3Transform(mathx.zero3, probe.xf[row.i]);
        const out = mathx.lenV(mathx.subV(at, c)) - r;
        std.debug.print("    {s:<11}{d:6.2} m out ({d:.2} against the sphere)\n", .{ row.name, out + r, out });
        if (out > worst) {
            worst = out;
            worstName = row.name;
        }
    }
    std.debug.print("    furthest out is the {s}, {d:.2} m past the skin\n", .{ worstName, worst });
    // THE FLOWER, RISEN, IS INSIDE IT. That is the claim, and it is the one the fight depends on.
    const bloomOut = mathx.lenV(mathx.subV(rl.math.vector3Transform(mathx.zero3, probe.xf[BLOOM]), c)) - r;
    try std.testing.expect(bloomOut <= 0.0);
    // …and so is it furled, and so is the barrel between them.
    var low = Deer.spawn(mathx.zero3, 0, 1.0, 1.0);
    low.pose();
    const lowC = low.centerWorld();
    // **THE BARREL AND THE FLOWER. NOT THE NOSE, NOT THE HOOVES** — a quadruped's extremities live outside its
    // hurt sphere here (the wolf's is 0.42 on a 1.12 body), and a ball big enough to swallow a 1.37 m neck is a
    // ball you hit by swinging at open ground.
    for ([_]struct { i: usize, name: []const u8 }{
        .{ .i = BLOOM, .name = "furled bloom" },
        .{ .i = SPINE, .name = "loin" },
        .{ .i = CHEST, .name = "withers" },
        .{ .i = ROOT, .name = "croup" },
    }) |row| {
        const at = rl.math.vector3Transform(mathx.zero3, low.xf[row.i]);
        std.debug.print("    {s:<13}({d:.2},{d:.2},{d:.2}) {d:.2} m from the centre\n", .{ row.name, at.x, at.y, at.z, mathx.lenV(mathx.subV(at, lowC)) });
        try std.testing.expect(mathx.lenV(mathx.subV(at, lowC)) <= low.hurtRadius());
    }
}

test "PLANT FLESH: fire is the answer to it and cold is not, and it is a FOE with its own souls" {
    try std.testing.expect(RESISTS.at(.fire) < 0);
    try std.testing.expect(RESISTS.at(.cold) > 0);
    var d = Deer.spawn(mathx.zero3, 0, 1.0, 0.30);
    try std.testing.expectEqual(wf.FoeKind.fungal_deer, d.kind());
    try std.testing.expect(SOULS > 0);
    // **BETWEEN THE HERO'S TWO SWINGS**: a light poke may not interrupt a volley and a committed swing must.
    std.debug.print("  deer: {d:.0} HP / {d:.0} poise, {d:.2} m at the withers, aggro {d:.0} m\n", .{ HP_MAX, POISE_MAX, W, AGGRO_R });
    try std.testing.expect(POISE_MAX > 10.0 and POISE_MAX < 22.0);
}

test "A HERD CLEARS THE AIR WITH THE BODIES, not just the bodies" {
    // `game.clearFoes` calls this on every group and reads nothing back — a `clear` that swept only the
    // animals leaves a volley hanging over a field with nothing on it.
    var h = Herd{ .model = undefined };
    h.deer[0] = Deer.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.n = 1;
    h.volley(v3(0, 2.0, 0), 0, 0);
    try std.testing.expect(h.spores[0].live);
    h.clear();
    try std.testing.expectEqual(@as(usize, 0), h.liveConst().len);
    for (&h.spores) |*s| try std.testing.expect(!s.live);
}
