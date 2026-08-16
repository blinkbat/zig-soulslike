const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const heromod = @import("hero.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;

// It has no `foe.Leash` — a leash is a creature's eyes on the HERO, and this one's eyes are on everything
// else. What it shares with the foes it shares through `foe.zig`: the swept `Blade`, `stunCurve`, `dissipate`.
//
// ## The gait is Hildebrand's, and it is TWO NUMBERS
//
// Every symmetrical quadruped gait is fully specified by a DUTY FACTOR (the fraction of the stride a foot is
// on the ground) and a LIMB PHASE (how far the forefoot's strike lags the hind foot on the same side) —
// Hildebrand 1965/1968. So walk, trot and gallop are one footfall machine at three points on one line:
//
//   gait     duty   lag    speed (m/s)
//   walk     0.65   0.84   0.4 - 2.0     lateral sequence
//   trot     0.55   0.50   0.8 - 5.3     diagonal couplets, and a wolf's travelling gait
//   gallop   0.42   0.63   3.2 - 10.0    transverse, with a real aerial phase
//
// Figures from steady-state dog locomotion (Bertram et al., J. Exp. Biol. 211:138) and working-dog trotting
// (J. Exp. Biol. 228:jeb250523), which puts a 34 kg German Shepherd at 2.14 m/s, a 0.52 s cycle and a 1.21 m
// stride. Fore and hind stride lengths there are identical to two decimals — a trotting dog tracking up — so
// this rig uses ONE stride length for all four limbs, never one per pair.

/// Height at the WITHERS, in metres — everything below is a fraction of it. A gray wolf runs 66-84 cm; this
/// is a dire wolf and stands over the real range (owner: bigger, and chunkier), which puts its back above the
/// hero's own hip. It scales the animal UNIFORMLY: stocky is the proportions under it (`SHOULDER_Y`,
/// `BRISKET_Y`), so reaching for `W` when the answer is "chunkier" only makes a bigger animal of one build.
pub const W: f32 = 1.12;
/// HOW FAR THE SPIRIT PANEL STANDS OFF ITS FACE. The subject owns its own distance (`npc.PORTRAIT_DIST` is
/// the man's) — a wolf's head is longer than a face and carried further forward, so it wants more room.
pub const PORTRAIT_DIST: f32 = 1.05;

// The forelimbs hang off the CHEST and the hindlimbs off the ROOT, which is the pelvis.
pub const ROOT = 0; // pelvis — the body's anchor
pub const SPINE = 1; // lumbar
pub const CHEST = 2; // thorax, and where the forelimbs hang
pub const NECK = 3;
pub const HEAD = 4;
pub const JAW = 5; // …and the bite comes off this one
pub const TAIL0 = 6;
pub const TAIL1 = 7;
pub const TAIL2 = 8;
pub const EARL = 9;
pub const EARR = 10;
pub const SHL = 11; // fore left: shoulder, elbow, carpus, paw
pub const ELL = 12;
pub const CAL = 13;
pub const PAWL = 14;
pub const SHR = 15;
pub const ELR = 16;
pub const CAR = 17;
pub const PAWR = 18;
pub const HIPL = 19; // hind left: hip, stifle, hock, paw
pub const STL = 20;
pub const HKL = 21;
pub const HPAWL = 22;
pub const HIPR = 23;
pub const STR = 24;
pub const HKR = 25;
pub const HPAWR = 26;
pub const N = 27;

pub const PARENT = [N]i32{
    -1,    ROOT,  SPINE, CHEST, NECK,  HEAD, // ROOT SPINE CHEST NECK HEAD JAW
    ROOT,  TAIL0, TAIL1, // the tail
    HEAD,  HEAD, // the ears
    CHEST, SHL,   ELL,   CAL, // fore left
    CHEST, SHR,   ELR,   CAR, // fore right
    ROOT,  HIPL,  STL,   HKL, // hind left
    ROOT,  HIPR,  STR,   HKR, // hind right
};

/// ONE LIMB'S WHOLE DESCRIPTION: its four bones (joint → middle → cannon → paw), the two segment lengths the
/// solver spans, which way the middle joint folds, and the height its own joint hangs at.
const Limb = struct { bones: [4]usize, upper: f32, lower: f32, bend: f32, jointY: f32 };

/// IN `limbPhases`' OWN ORDER — hind left, hind right, fore left, fore right — so a limb's index IS its phase.
const LIMBS = [4]Limb{
    .{ .bones = .{ HIPL, STL, HKL, HPAWL }, .upper = FEMUR, .lower = HIND_LOWER, .bend = -1.0, .jointY = HIP_Y },
    .{ .bones = .{ HIPR, STR, HKR, HPAWR }, .upper = FEMUR, .lower = HIND_LOWER, .bend = -1.0, .jointY = HIP_Y },
    .{ .bones = .{ SHL, ELL, CAL, PAWL }, .upper = HUMERUS, .lower = FORE_LOWER, .bend = 1.0, .jointY = SHOULDER_Y },
    .{ .bones = .{ SHR, ELR, CAR, PAWR }, .upper = HUMERUS, .lower = FORE_LOWER, .bend = 1.0, .jointY = SHOULDER_Y },
};

comptime {
    // A limb renumbered in `PARENT` alone is a compile error here rather than a leg on the wrong bone.
    for (LIMBS) |L| {
        if (@as(usize, @intCast(PARENT[L.bones[1]])) != L.bones[0] or
            @as(usize, @intCast(PARENT[L.bones[2]])) != L.bones[1] or
            @as(usize, @intCast(PARENT[L.bones[3]])) != L.bones[2]) @compileError("wolf: a limb chain disagrees with PARENT");
    }
}

// Segment lengths as fractions of `W`, summing to the stature they are measured against. The CHEST IS HALF
// THE HEIGHT and that is what stops it being leggy: a canid's brisket sits at ~0.55 of the withers, so the
// body is nearly as deep as the leg under it is long. Built with the shoulder at 0.62 the trunk floated on
// stilts and read as a deer.
const SHOULDER_Y = 0.70; // the shoulder JOINT, which is well up inside the body's own mass
const HIP_Y = 0.72; // …and the hip a touch above it: a wolf stands very slightly croup-high
const BRISKET_Y = 0.46; // the bottom of the chest — the line the elbow drops out of
const HUMERUS = 0.24;
const FORE_LOWER = 0.50; // radius + metacarpus, solved as ONE link (see `limbChain`)
const FEMUR = 0.29;
const HIND_LOWER = 0.52; // tibia + metatarsus — the hock stands well back, which is what makes the zig-zag
const TRACK = 0.145; // half the distance between the left and right feet — a wide, planted stance
const CHEST_Z = 0.42; // the shoulder, forward of the body's centre…
const HIP_Z = -0.42; // …and the pelvis behind it: a 0.84 W trunk
const HEAD_LEN = 0.26;
/// The head is carried at or below the WITHERS, on a short thick neck reaching FORWARD — one that lifts the
/// skull above the shoulder is a llama. The neck's length has no constant: it falls out of `restPose`.
const HEAD_Y = 0.82; // …a hair over the shoulder joint and under the top of the back
const HEAD_Z = 0.72;

/// In the wolf's own standing frame (X its left, Y up, Z forward), as fractions of `W`.
pub fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, HIP_Y, HIP_Z);
    r[SPINE] = v3(0, HIP_Y - 0.005, HIP_Z + 0.27);
    r[CHEST] = v3(0, SHOULDER_Y, CHEST_Z);
    r[NECK] = v3(0, SHOULDER_Y + 0.045, CHEST_Z + 0.12);
    r[HEAD] = v3(0, HEAD_Y, HEAD_Z);
    r[JAW] = v3(0, HEAD_Y - 0.035, HEAD_Z + HEAD_LEN * 0.28);
    r[TAIL0] = v3(0, HIP_Y + 0.015, HIP_Z - 0.07);
    r[TAIL1] = v3(0, HIP_Y - 0.075, HIP_Z - 0.27);
    r[TAIL2] = v3(0, HIP_Y - 0.185, HIP_Z - 0.45);
    r[EARL] = v3(0.050, HEAD_Y + 0.075, HEAD_Z - 0.055);
    r[EARR] = v3(-0.050, HEAD_Y + 0.075, HEAD_Z - 0.055);
    // THE REST CHAIN CARRIES THE TRUE SEGMENT LENGTHS, so its paw hangs BELOW the ground — that surplus is
    // the zig-zag. `setJoint` takes each bone's length from the DISTANCE between two rest points, so laying
    // the paw at y = 0 tells the solver a lower segment 4-10% longer than the bones are, and it over-bends
    // every limb and stands the animal on four feet hanging in the air.
    inline for (.{ .{ SHL, ELL, CAL, PAWL, TRACK }, .{ SHR, ELR, CAR, PAWR, -TRACK } }) |c| {
        r[c[0]] = v3(c[4], SHOULDER_Y, CHEST_Z);
        r[c[1]] = v3(c[4], SHOULDER_Y - HUMERUS, CHEST_Z);
        r[c[2]] = v3(c[4], SHOULDER_Y - HUMERUS - FORE_LOWER * 0.68, CHEST_Z);
        r[c[3]] = v3(c[4], SHOULDER_Y - HUMERUS - FORE_LOWER, CHEST_Z);
    }
    inline for (.{ .{ HIPL, STL, HKL, HPAWL, TRACK }, .{ HIPR, STR, HKR, HPAWR, -TRACK } }) |c| {
        r[c[0]] = v3(c[4], HIP_Y, HIP_Z);
        r[c[1]] = v3(c[4], HIP_Y - FEMUR, HIP_Z);
        r[c[2]] = v3(c[4], HIP_Y - FEMUR - HIND_LOWER * 0.62, HIP_Z);
        r[c[3]] = v3(c[4], HIP_Y - FEMUR - HIND_LOWER, HIP_Z);
    }
    for (&r) |*p| p.* = v3(p.x * W, p.y * W, p.z * W);
    return r;
}

/// Hildebrand's two dials, and the whole of what separates one symmetrical gait from another.
pub const Gait = struct {
    /// Fraction of the stride each foot is ON THE GROUND. Above 0.5 something is always down (a walk); below
    /// it there are moments with no feet on the earth at all, which is what an aerial phase IS.
    duty: f32,
    /// How far the FOREfoot's strike lags the hind foot on the SAME SIDE, as a fraction of the stride. 0.5 is
    /// the trot's diagonal couplets; 0.84 is the lateral-sequence walk.
    lag: f32,
};

/// The three measured anchors. Speeds are the m/s each gait is actually used at.
pub const WALK = Gait{ .duty = 0.65, .lag = 0.84 };
pub const TROT = Gait{ .duty = 0.55, .lag = 0.50 };
pub const GALLOP = Gait{ .duty = 0.42, .lag = 0.63 };
pub const WALK_SPEED: f32 = 1.1;
/// A WOLF'S TRAVELLING GAIT, and the speed it will hold for hours: 2.2-2.7 m/s. Just over the hero's walk,
/// which is why it can pace him without breaking into anything.
pub const TROT_SPEED: f32 = 2.4;
pub const GALLOP_SPEED: f32 = 5.2;

/// LERPED, never switched: Hildebrand's diagram is a continuous surface, and a creature that snapped between
/// two duty factors would be changing its legs mid-stride.
pub fn gaitAt(speed: f32) Gait {
    if (speed <= WALK_SPEED) return WALK;
    if (speed >= GALLOP_SPEED) return GALLOP;
    if (speed <= TROT_SPEED) {
        const t = (speed - WALK_SPEED) / (TROT_SPEED - WALK_SPEED);
        return .{ .duty = mathx.lerpF(WALK.duty, TROT.duty, t), .lag = mathx.lerpF(WALK.lag, TROT.lag, t) };
    }
    const t = (speed - TROT_SPEED) / (GALLOP_SPEED - TROT_SPEED);
    return .{ .duty = mathx.lerpF(TROT.duty, GALLOP.duty, t), .lag = mathx.lerpF(TROT.lag, GALLOP.lag, t) };
}

/// STRIDE LENGTH IN METRES AT A GIVEN SPEED, and it is LINEAR — measured, across every gait a dog uses. The
/// intercept is what keeps a near-stationary creature's phase from running away to nothing.
pub fn strideFor(speed: f32) f32 {
    return mathx.clampF(0.55 * speed + 0.06, 0.34, 1.70);
}

/// THE FOUR LIMBS' PHASES, given the hind-left's. A symmetrical gait is symmetrical: the two hinds are half a
/// stride apart by definition, and each fore lags the hind on ITS OWN SIDE by `lag`.
pub fn limbPhases(p: f32, g: Gait) [4]f32 {
    return .{
        wrap01(p), // hind left
        wrap01(p + 0.5), // hind right
        wrap01(p + g.lag), // fore left
        wrap01(p + g.lag + 0.5), // fore right
    };
}

fn wrap01(x: f32) f32 {
    const f = x - @floor(x);
    return if (f < 0) f + 1.0 else f;
}

/// IS THIS FOOT ON THE GROUND — the duty factor's entire meaning, and the one place it is compared.
pub fn planted(phase: f32, g: Gait) bool {
    return phase < g.duty;
}

/// In the BODY's frame: `z` along the direction of travel, `y` off the ground. Pure functions of PHASE, so
/// nothing here knows what time it is — and the stance sweep is linear in phase, which is linear in DISTANCE,
/// so in world space a planted paw does not move at all.
pub fn pawAt(phase: f32, g: Gait, stride: f32) struct { z: f32, y: f32 } {
    // The stance excursion is `stride × duty`, NOT `stride`: a stride is print to print, but the foot is only
    // down for `duty` of that cycle. Written as the whole stride the offset ran back 1/duty times too fast
    // and every foot slid backwards through its own contact.
    const half = stride * g.duty * 0.5;
    if (planted(phase, g)) {
        const s = phase / g.duty; // 0 at touchdown, 1 at lift-off
        return .{ .z = half * (1.0 - 2.0 * s), .y = 0 };
    }
    const s = (phase - g.duty) / (1.0 - g.duty); // 0 at lift-off, 1 at the next touchdown
    return .{ .z = half * (-1.0 + 2.0 * s), .y = SWING_LIFT * W * mathx.sinf(s * std.math.pi) };
}

const SWING_LIFT: f32 = 0.115; // of W — how high a paw clears the ground at the top of its swing

/// Two-link IK in the sagittal plane: a limb of segments `a` and `b` hung from a joint at the origin, paw at
/// (`dy` below, `dz` forward), reporting the two rotations about X.
///
/// `bend` is ANATOMY, not a preference: a wolf's elbow points BACK and its stifle points FORWARD, which is why
/// front and back legs read as different machines. Get it the same on both and it is a horse's front legs.
pub fn limbChain(a: f32, b: f32, dy: f32, dz: f32, bend: f32) struct { upper: f32, lower: f32 } {
    // Clamped inside the limb's own span: past `a + b` there is no solution, inside `|a - b|` it folds
    // through itself.
    const want = @sqrt(dy * dy + dz * dz);
    const d = mathx.clampF(want, @abs(a - b) + 1e-4, a + b - 1e-4);
    const t = std.math.atan2(dz, @max(dy, 1e-4)); // the target's bearing off straight-down
    const alpha = std.math.acos(mathx.clampF((a * a + d * d - b * b) / (2.0 * a * d), -1, 1));
    const knee = std.math.acos(mathx.clampF((a * a + b * b - d * d) / (2.0 * a * b), -1, 1));
    return .{
        .upper = mathx.degrees(t + bend * alpha),
        .lower = -bend * mathx.degrees(std.math.pi - knee),
    };
}

// GREY, AND COUNTERSHADED. A wolf is not one colour: a dark saddle over the back, pale down the throat, belly
// and inside the legs. That gradient is most of what makes the shape read at distance — a flat grey animal is
// a dog-shaped smudge. Solved against the render the way `npc.zig`'s palette was: the chain is albedo × 1.72 →
// linear → gamma 1/2.2, so these sit where a lit flank lands near the ground's own value and the THROAT is
// the one high note.
// SOLVED AGAINST THE RENDER, NOT PICKED. The first pass authored a neutral grey (96, 92, 88) and sampled back
// at 217/193/161 on the lit flank against ground at 107/99/65 — a CREAM animal, which is a husky and not a
// wolf. Two corrections, both off the chain (albedo × 1.72 → linear → gamma 1/2.2, so screen ∝ albedo^(1/2.2)):
//
//  - VALUE: to bring a lit 217 down to about 150 is a factor 0.69 on screen, so albedo × 0.69^2.2 ≈ 0.44.
//  - HUE: this sun is warm and everything outdoors here comes back warm, so a NEUTRAL albedo cannot render
//    neutral. The pelt is authored BLUE-SHIFTED and the sun brings it back to grey; author it grey and the
//    sun takes it to sand.
// **AND IT IS NOT ALL THE WAY HERE.** Two channels do that and they are different things:
//
//  - TRANSPARENCY is the scene's `fade` uniform (`SPIRIT_FADE`), applied by the draw. Vertex alpha CANNOT do
//    it — in this renderer alpha is the emissive channel, so a "transparent" colour authored here would come
//    back as a brighter opaque one.
//  - THE SHEEN is that emissive channel, and it is what makes a spirit read as lit from the inside rather
//    than as a grey animal somebody turned the opacity down on. LOWER alpha is MORE emissive (the leechfly's
//    eyes are 110), so these sit just under solid — enough that it holds its own value in shadow, where a
//    purely lit body would go to nothing and the thinning would finish it off.
const SHEEN: u8 = 206;
const SHEEN_LT: u8 = 188; // the raised parts glow a touch harder, which is what makes it look wet-cold
const PELT = rgba(44, 47, 55, SHEEN);
const PELT_LT = rgba(66, 70, 79, SHEEN_LT);
const SADDLE = rgba(27, 29, 35, SHEEN); // the dark cape over the shoulders and back
/// The pale underside — still cool, and still well under the old flank: a wolf's belly is light AGAINST THE
/// WOLF, not light against the field.
const BELLY = rgba(84, 84, 86, SHEEN_LT);
const MUZZLE_DK = rgba(24, 25, 29, SHEEN);
const PAW = rgba(28, 29, 34, SHEEN);
/// THE FUR ITSELF, and it is the coldest thing on him: the tufts catch what light there is and they are what
/// the eye reads the silhouette's EDGE off, so they glow hardest of anything but the eyes.
const FUR = rgba(78, 86, 98, 172);
const FUR_DK = rgba(40, 44, 52, SHEEN);

/// How solid he draws in the lit pass. Raised from 0.72: with depth writes ON the far side of him is already
/// gone, so the remaining alpha is doing ONE job — letting a little of the world through his near face — and
/// at 0.72 that read as a jellyfish. This is "you can tell he is not quite here", not "you can see through
/// him".
pub const SPIRIT_FADE: f32 = 0.86;
const NOSE = rgba(22, 20, 19, 255);
/// THE EYES, and they are the one thing on it that is not an animal's colour: a called spirit is lit from
/// inside. Vertex alpha is the emissive channel, so this reads as GLOWING rather than painted — the leechfly's
/// own trick, and the only cue that says the thing running at you is on your side.
const EYE = rgba(150, 180, 210, 110);

/// The pelt at a height up the body, 0 at the belly and 1 along the spine — countershading as a function
/// rather than as three hand-placed patches, so every mesh call reads the same gradient.
fn peltAt(k: f32) rl.Color {
    if (k > 0.72) return SADDLE;
    if (k < 0.28) return BELLY;
    return PELT;
}

/// **FUR IS BROKEN SILHOUETTE, NOT TEXTURE.** There is no fur shader here and there should not be one: what
/// makes a coat read at forty metres is that the OUTLINE is ragged, so the fur is geometry — a ring of tapered
/// tufts standing off the mass, sunk most of their length into it (the relief rule) so only the tips show.
///
/// The variation goes BETWEEN the tufts and never along one: each gets its own length, lean and angle off a
/// seeded rng, because a ring of identical spikes is a cog and a ring of uneven ones is hair. `n` is kept low
/// for the same reason the props are — a mass wants more SIDES before it wants more spines on top of it.
fn furRing(b: *Builder, rng: *mathx.Rng, at: rl.Vector3, r: f32, len: f32, n: i32, col: rl.Color) void {
    var k: i32 = 0;
    while (k < n) : (k += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n)) + rng.range(-0.30, 0.30);
        const c = mathx.cosf(a);
        const sn = mathx.sinf(a);
        const l = len * rng.range(0.55, 1.30);
        // **FUR LIES BACK ALONG THE BODY. IT DOES NOT RADIATE.** Standing straight out, tufts this size came
        // out as a ring of glass shards round the shoulders — a sea urchin, not a coat. Almost all of a
        // tuft's length is SWEPT (−Z, toward the tail) and only a little of it lifts off the surface, which is
        // what hair does under its own weight and what makes an edge look soft rather than spiked.
        const OUT = 0.34; // the share of the tuft that stands proud; the rest goes backward
        // Rooted INSIDE the mass and reaching past it: a tuft starting at the surface is a bristle glued on,
        // and one starting at the centre is a spoke.
        const from = v3(at.x + c * r * 0.55, at.y + sn * r * 0.55, at.z + rng.range(-0.25, 0.25) * r);
        const to = v3(
            at.x + c * (r + l * OUT),
            at.y + sn * (r + l * OUT) - l * 0.16, // …and it droops, because everything dead or heavy does
            at.z - l * rng.range(0.72, 1.05),
        );
        // THIN, and tapering to nothing but never TO A POINT — five sides is enough at this size and the tip
        // keeps a radius, the house rule about what may end in a needle.
        b.addCapsule(from, to, r * 0.16, r * 0.055, 5, col);
    }
}

/// ONE BONE'S MESH. Built per-bone like the hero's, so `draw` only ever replays `pose()`'s matrices and the
/// shadow can never disagree with the silhouette.
fn boneMesh(i: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1F0 +% @as(u64, i));
    b.setMat(.hide);
    const s = W;
    switch (i) {
        // THE TRUNK, and it is ROUND: a wolf is flesh, so blobs and capsules and never a box. Two masses, the
        // deep chest and the tucked loin, because one even barrel is what reads as a sausage.
        // **THE TRUNK IS ONE MASS, NOT THREE.** Three blobs at three joints came out as a caterpillar of
        // separate balls with a waist between each: the fix is that every section OVERLAPS its neighbour well
        // past the joint (the packed-stone rule — a facing without a substrate leaks) and the radii GRADE, so
        // what reads is one barrel deepening toward the chest. Each is drawn from its own bone so the spine
        // still bends; what changed is that they intersect instead of abutting.
        //
        // …and the chest is DEEP: from the brisket at 0.55 W up to the withers at 1.00 it is nearly half the
        // animal's height, which is what a wolf's silhouette actually is.
        // **A COUNTERSHADING PATCH IS RELIEF, SO IT IS SUNK MOST OF THE WAY IN.** Sized close to the mass it
        // sits on it does not read as a darker back — it reads as a separate flat slab poking through the
        // flank, because two ellipsoids of similar Z extent only nest at their centres and cross at their
        // ends. The rule is the house one: cut the patch's REACH along the body hard (0.6-0.7 of its parent's)
        // and pull it toward the centre, so it is inside the silhouette everywhere and only the colour shows.
        // **CHUNK** (owner's word). The barrel is WIDE — a wolf in winter coat is far broader than the skeleton
        // under it, and the first pass authored the skeleton. The X radii carry most of it: depth alone reads
        // as a slab from the side and changes nothing head-on, where a heavy animal is heavy.
        CHEST => {
            const dep = (SHOULDER_Y - BRISKET_Y) + 0.26; // brisket to withers, through the shoulder joint
            b.addBlob(v3(0, -0.015 * s, -0.10 * s), v3(0.205 * s, dep * 0.5 * s, 0.36 * s), 6, 11, peltAt(0.5));
            b.addBlob(v3(0, 0.105 * s, -0.12 * s), v3(0.160 * s, 0.090 * s, 0.22 * s), 5, 10, SADDLE); // the cape over the withers
            b.addBlob(v3(0, -0.135 * s, -0.09 * s), v3(0.140 * s, 0.072 * s, 0.19 * s), 4, 9, BELLY); // …and the brisket under it
            // The withers' own hackle — the ridge that stands up between the shoulder blades.
            furRing(&b, &rng, v3(0, 0.075 * s, -0.16 * s), 0.150 * s, 0.080 * s, 9, FUR);
            furRing(&b, &rng, v3(0, 0.020 * s, 0.09 * s), 0.185 * s, 0.055 * s, 8, FUR_DK);
        },
        // The waist, and it is DRAWN IN — the tuck behind the ribs is the wolf's own line and a barrel has
        // none. Narrower than either neighbour and buried in both, but still thick: a chunky animal's waist is
        // a suggestion, not a wasp's.
        SPINE => {
            b.addBlob(v3(0, 0.005 * s, 0), v3(0.172 * s, 0.160 * s, 0.26 * s), 5, 10, peltAt(0.55));
            b.addBlob(v3(0, -0.092 * s, 0), v3(0.120 * s, 0.055 * s, 0.16 * s), 4, 9, BELLY);
        },
        // …and the HAUNCH is the heaviest thing on it — this is where a canid's drive comes from and it should
        // look like it does.
        ROOT => {
            b.addBlob(v3(0, -0.01 * s, 0.06 * s), v3(0.196 * s, 0.180 * s, 0.28 * s), 5, 10, peltAt(0.5));
            b.addBlob(v3(0, 0.095 * s, 0.05 * s), v3(0.145 * s, 0.078 * s, 0.18 * s), 4, 9, SADDLE);
            // The trousers — the long hair off the back of the haunch, which is where a wolf's rear
            // silhouette actually comes from.
            furRing(&b, &rng, v3(0, -0.020 * s, -0.10 * s), 0.190 * s, 0.090 * s, 10, FUR);
        },
        // THE NECK IS SHORT AND THICK, and it is mostly RUFF — the mane is wider than the neck inside it, and
        // that mass is what makes the shoulders read as heavy. Buried well back into the chest at one end and
        // into the skull at the other, so there is no seam at either joint.
        // THE RUFF IS THE CHUNK. On a heavy canid the mane is the widest thing above the ribs and it is what
        // makes the shoulders read as a mass rather than as the top of four legs.
        NECK => {
            b.addCapsule(v3(0, -0.03 * s, -0.10 * s), v3(0, 0.02 * s, 0.16 * s), 0.165 * s, 0.100 * s, 10, peltAt(0.6));
            b.addBlob(v3(0, 0.005 * s, -0.02 * s), v3(0.195 * s, 0.150 * s, 0.140 * s), 4, 10, SADDLE); // the ruff's mass…
            // …AND ITS EDGE, which is the whole point of a ruff: a mane reads because it is RAGGED against the
            // sky, so the tufts stand off the mass and out past the shoulder line behind it.
            furRing(&b, &rng, v3(0, 0.005 * s, -0.03 * s), 0.190 * s, 0.105 * s, 11, FUR);
            furRing(&b, &rng, v3(0, 0.000 * s, 0.055 * s), 0.155 * s, 0.070 * s, 9, FUR);
            b.addCapsule(v3(0, -0.085 * s, -0.02 * s), v3(0, -0.050 * s, 0.14 * s), 0.088 * s, 0.058 * s, 8, BELLY); // the pale throat
        },
        // THE HEAD. A wolf's skull is a WEDGE: a broad braincase, a SHALLOW stop, and a muzzle that is deep
        // and blunt rather than thin and long — a needle-nosed canid is a fox, and nothing here ends in a
        // point. The cheek mass under the eye is what carries the jaw and it is most of the front-on read.
        HEAD => {
            b.addBlob(v3(0, 0.005 * s, -0.01 * s), v3(0.082 * s, 0.078 * s, 0.098 * s), 4, 10, peltAt(0.7)); // braincase
            b.addBlob(v3(0.048 * s, -0.018 * s, 0.045 * s), v3(0.034 * s, 0.040 * s, 0.055 * s), 3, 8, peltAt(0.5)); // cheeks
            b.addBlob(v3(-0.048 * s, -0.018 * s, 0.045 * s), v3(0.034 * s, 0.040 * s, 0.055 * s), 3, 8, peltAt(0.5));
            b.addCapsule(v3(0, -0.018 * s, 0.045 * s), v3(0, -0.036 * s, 0.150 * s), 0.058 * s, 0.044 * s, 9, peltAt(0.55));
            b.addBlob(v3(0, -0.038 * s, 0.162 * s), v3(0.040 * s, 0.035 * s, 0.030 * s), 3, 8, MUZZLE_DK); // the blunt snap of it
            b.addBlob(v3(0, -0.028 * s, 0.178 * s), v3(0.020 * s, 0.017 * s, 0.014 * s), 3, 7, NOSE);
            // The eyes, set FORWARD and close — a hunter's, and the one lit thing on the animal.
            b.addBlob(v3(0.042 * s, 0.024 * s, 0.070 * s), v3(0.016 * s, 0.014 * s, 0.013 * s), 3, 7, EYE);
            b.addBlob(v3(-0.042 * s, 0.024 * s, 0.070 * s), v3(0.016 * s, 0.014 * s, 0.013 * s), 3, 7, EYE);
        },
        JAW => {
            b.addCapsule(v3(0, 0, 0.02 * s), v3(0, -0.010 * s, 0.125 * s), 0.032 * s, 0.024 * s, 7, MUZZLE_DK);
            b.addBlob(v3(0, 0.004 * s, 0.060 * s), v3(0.026 * s, 0.016 * s, 0.055 * s), 3, 7, BELLY);
        },
        EARL, EARR => {
            // PRICKED, SET BACK, and BLUNT at the tip. Slightly different heights left and right: variation
            // between the parts, which is what stops a symmetrical head reading as a decal.
            // BIGGER THAN THEY LOOK ON A PHOTOGRAPH. At the first pass's size they were two chips nobody could
            // see, and the ears are the single cheapest thing that says "wolf" from forty metres.
            const lean: f32 = if (i == EARL) 1.0 else -1.0;
            const h = 0.105 * s * rng.range(0.94, 1.06);
            b.addCapsule(v3(0, 0, 0), v3(lean * 0.020 * s, h, -0.014 * s), 0.044 * s, 0.020 * s, 7, peltAt(0.8));
            b.addCapsule(v3(0, 0.008 * s, 0.006 * s), v3(lean * 0.015 * s, h * 0.80, -0.006 * s), 0.030 * s, 0.011 * s, 6, MUZZLE_DK);
        },
        // **A BRUSH, NOT A ROPE.** The tail's whole read is fur, so each segment is far fatter than the bone
        // in it and carries its own ring of tufts. The first pass drew three tapering sausages.
        TAIL0, TAIL1, TAIL2 => {
            const r0: f32 = switch (i) {
                TAIL0 => 0.082,
                TAIL1 => 0.076,
                else => 0.058,
            };
            const tip = v3(0, -0.055 * s, -0.150 * s);
            b.addCapsule(v3(0, 0, 0), tip, r0 * s, r0 * s * 0.88, 8, peltAt(0.62));
            furRing(&b, &rng, v3(0, -0.028 * s, -0.075 * s), r0 * s * 0.92, 0.070 * s, 7, FUR);
            if (i == TAIL2) {
                b.addBlob(tip, v3(0.052 * s, 0.052 * s, 0.058 * s), 3, 8, MUZZLE_DK); // the black tip, blunt
                furRing(&b, &rng, tip, r0 * s * 0.80, 0.055 * s, 6, FUR_DK);
            }
        },
        // THE LIMBS. Upper segments carry real muscle and taper hard into the lower ones, which are nearly
        // bone — that taper is a canid's leg and a set of even cylinders is a table's.
        // THE LIMBS, and the upper segments are nearly as thick as they are long — that is where the muscle
        // is, and the first pass drew four broom handles. The taper into the cannon bone is what sells it: a
        // leg of even thickness reads as furniture whatever its radius.
        SHL, SHR => b.addCapsule(v3(0, 0.02 * s, 0), v3(0, -HUMERUS * s, 0), 0.105 * s, 0.062 * s, 8, peltAt(0.45)),
        HIPL, HIPR => b.addCapsule(v3(0, 0.02 * s, 0), v3(0, -FEMUR * s, 0), 0.125 * s, 0.068 * s, 8, peltAt(0.45)),
        ELL, ELR => b.addCapsule(v3(0, 0, 0), v3(0, -FORE_LOWER * 0.68 * s, 0), 0.062 * s, 0.036 * s, 7, peltAt(0.3)),
        STL, STR => b.addCapsule(v3(0, 0, 0), v3(0, -HIND_LOWER * 0.62 * s, 0), 0.078 * s, 0.038 * s, 7, peltAt(0.3)),
        // The cannon bones, and their length comes off the SAME fraction the rest pose splits the lower limb
        // at — written as a literal it was a third number that had to agree with two others.
        CAL, CAR => b.addCapsule(v3(0, 0, 0), v3(0, -FORE_LOWER * 0.32 * s, 0), 0.038 * s, 0.032 * s, 6, peltAt(0.2)),
        HKL, HKR => b.addCapsule(v3(0, 0, 0), v3(0, -HIND_LOWER * 0.38 * s, 0), 0.040 * s, 0.033 * s, 6, peltAt(0.2)),
        // BIG FEET. A heavy canid's paws are out of proportion to its legs and that is most of what says the
        // animal has weight on the ground.
        PAWL, PAWR, HPAWL, HPAWR => {
            b.addBlob(v3(0, 0.020 * s, 0.016 * s), v3(0.052 * s, 0.034 * s, 0.064 * s), 3, 8, PAW);
        },
        else => {},
    }
    return b.toMesh();
}

pub const SCALE: f32 = 1.0;
pub const BODY_R: f32 = 0.34;
pub const HURT_R: f32 = 0.42;
/// How high up its own body the hurt sphere and the bar sit, as a fraction of `W`.
const CENTER_H: f32 = 0.62;
const TOP_H: f32 = 1.05;

/// WHAT IT CAN TAKE. A spirit is not a second hero: it dies, and it is MEANT to — what the player buys with
/// thirty focus is a body between him and the thing coming, for as long as that body lasts.
pub const HP: f32 = 88.0;
pub const POISE: f32 = 26.0;
pub const STANCE: f32 = 52.0;

pub const DEATH_DUR: f32 = 1.05;
pub const DISS_DUR: f32 = 1.25;
/// Its own dissolve: a spirit does not shed bone or chitin, it comes APART — faster and wider than a body,
/// and the flake takes the pelt's own grey so what falls is recognisably what was standing there.
pub const DISSOLVE = foe.Dissolve{ .rate = 62.0, .spread = 1.05, .rise = 0.85, .flake = PELT_LT };

/// HOW FAR IT RANGES LOOKING FOR SOMETHING TO FIGHT. Generous, because a spirit that has to be walked onto its
/// target is one the player is babysitting.
pub const HUNT_R: f32 = 16.0;
/// **A FOE THE HERO HAS WALKED AWAY FROM IS NOT THIS SPIRIT'S PROBLEM** (owner's call). Its tether is to HIM,
/// not to a post — that is the whole difference between a summon and a creature — so a body only counts as
/// quarry while the HERO is still this close to it. Tightened from 19 m: at that range it would stay behind
/// worrying at an archer the player had long since left, which is a summon you have to come back for.
pub const TETHER_R: f32 = 12.0;
/// …and the hard recall. Past this from him, NOTHING is worth chasing: it breaks off whatever it is doing and
/// comes back. Above `TETHER_R` so the two rules cannot fight — the first stops it TAKING distant work, this
/// one drops work it is already on.
pub const RECALL_R: f32 = 15.0;
/// How close it heels when there is nothing to kill…
pub const HEEL_R: f32 = 3.2;
/// …and how far behind it has to fall before it RUNS to catch up rather than trots. A spirit that ambles back
/// to heel from thirty metres is one the player out-walks forever.
pub const RUN_GAP: f32 = 7.0;
/// HOW LONG IT MAY BE OUT PAST `RECALL_R` BEFORE THE BOND MOVES IT ITSELF (owner's call). Running home is the
/// first answer and this is the one for when running cannot work — a bank it may not climb, a wall with no way
/// round inside its probe, or a man who simply out-sprints it. Measured against the recall ring rather than
/// against a distance of its own, so the clock only runs while it has already been told to come back.
pub const LOST_DWELL: f32 = 3.0;
/// …and how close it gets before the jaws go in.
pub const BITE_R: f32 = 1.35;

const BITE_WIND: f32 = 0.26;
const BITE_STRIKE: f32 = 0.16;
const BITE_RECOVER: f32 = 0.34;
const BITE_COOL: f32 = 0.55;
/// **THE BITE IS A HOP** (owner's call). A wolf does not stand still and open its mouth: it gathers on its
/// hindquarters and THROWS itself the last half-metre, and the jaws arrive because the whole animal did. The
/// travel is what makes the blow feel like it came from a body — and it is also, mechanically, what closes a
/// gap the approach left, so the strike is not a lunge that whiffs at the edge of `BITE_R`.
const BITE_HOP: f32 = 0.62; // metres of forward travel across the wind and the strike
/// HOW FAR OUT THE JAWS OPEN — ONE definition, because it is the gate the whole behaviour turns on and a
/// second copy at the call site is a number nothing can measure against.
const BITE_TRIGGER_R: f32 = BITE_R + BITE_HOP * 0.8;

/// WHAT IT IS SET ON: a point AND HOW BROAD IT IS. The radius is the whole reason this is not just a point.
pub const Quarry = struct { at: rl.Vector3, r: f32 = 0 };

/// **THE GATE IS MEASURED FROM THE QUARRY'S HIDE, NOT ITS CENTRE** — the knight's `triggerR` idiom, and for
/// the same reason. Asked centre-to-centre, a flat 1.85 m is unsatisfiable on anything broad: `env.resolveActor`
/// holds the wolf `bodyR + its own` out, which on the Bone Knight is 2.11 m, so the jaws opened 0.26 m closer
/// than the animal was ever allowed to stand and it circled a creature it could not trigger on for ever. The
/// ogre had 0.24 m of margin, which is why that one only ever "struggled" (owner). A test pins both.
pub fn triggerR(quarryR: f32) f32 {
    return BITE_TRIGGER_R + quarryR;
}

/// …and how close it TRIES to get, which has to sit inside the gate or it walks into a collider for ever.
fn stopR(quarryR: f32) f32 {
    return BITE_R * 0.85 + quarryR;
}
const BITE_HOP_UP: f32 = 0.14; // …and how far off the ground it gets, as a fraction of W
/// The gather: it SINKS before it goes, which is the wind-up you read the hop off.
const BITE_CROUCH: f32 = 0.09;
/// THE JAWS. Real damage — it is a wolf, and a summon that tickles is a summon nobody rings for — but almost
/// no stance: what it does for you is TIME and attention, not stagger. Getting the punish is still your job.
pub const BITE_HIT = combat.Hit{ .dmg = 21, .poise = 16, .stance = 3 };

/// How often it will growl while it is running something down. Long — the growl is presence, not a siren, and
/// a spirit that snarled continuously would be the loudest thing in a fight it is only assisting in.
const GROWL_EVERY: f32 = 2.6;

/// THE DISSOLVE'S RING, named like every sibling's (`archer.NPART`, `frog.FX_MAX`, `shade.PARTS`) rather than
/// left as a bare literal in the field's own type — a ring overwrites its oldest SILENTLY, so its size is a
/// thing to argue rather than a number that looked big enough. `foe.dissolveMotes` is the only emitter that
/// feeds it: `DISSOLVE.rate` 62 a second against a mean life of ~0.72 s (0.55-1.05 for a mote, 0.32-0.65 for
/// a flake, three in four being motes) stands about 45 at the fade's start, and the rate only falls from
/// there as `thinning` closes.
/// The rift's two bursts share it and cannot crowd it out: `2 × RIFT_N` is 24, and the two emitters can never
/// run at once (a spirit that is coming apart is not one the bond can move).
const PARTS = 48;
/// Motes at ONE end of a rematerialize — the shade's own count, on a ring half the size.
const RIFT_N = 12;

/// How far down the jaw bone the teeth sit, as a fraction of `W` — where the bite's blade is measured from.
const JAW_REACH: f32 = 0.10;

/// HOW HARD A BLOW KNOCKS IT BACK, by whether the blow was heavy — `foe.Push`, the same PAIR every wounded
/// creature is shoved by, because the two are only ever chosen against each other.
///
/// **IT IS A SPEED, in the unit every sibling's is** (`foe.applyShove`, which steps by `shove·dt` and bleeds
/// the vector off at `SHOVE_DECAY`): the ground actually covered is that speed OVER the decay, so these two
/// work out at the 4 cm and 9.4 cm of give-ground they were tuned to. Written as a hand-rolled step here the
/// decay was multiplied INTO the travel as well, so the same pair the shared type names meant METRES on this
/// one creature and m/s on the other nine — one struct, two units, and nothing to say which you were reading.
pub const SHOVE = foe.Push{ .light = 1.44, .heavy = 3.30 };
/// …and how fast that shove bleeds off, named like every sibling's.
const SHOVE_DECAY: f32 = 6.0;

const TURN_RATE: f32 = 5.6; // rad/s — a wolf turns on its own length
const ACCEL: f32 = 9.0;
/// How fast the SHOWN speed chases the real one — the gait's own smoothing, and the only thing `pose` reads.
/// It is not `ACCEL`: that is the animal accelerating, this is the legs catching up with it.
const GAIT_BLEND: f32 = 8.0;

pub const State = enum { idle, move, bite, hurt, dead };

pub const Wolf = struct {
    pos: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    scale: f32 = SCALE,
    vit: combat.Vitals = combat.Vitals.initFoe(HP, POISE, STANCE),
    state: State = .idle,
    t: f32 = 0,
    /// Gait phase, 0..1, and it is advanced by DISTANCE — never by time (the hero's law, and the reason the
    /// paws do not skate).
    phase: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    justDied: bool = false,
    /// ITS VOICES' OWN ONE-FRAME EDGES (`justDied`'s idiom, and cleared with it at the top of `update`). The
    /// creature says WHEN; game.zig owns the speaker, because a creature that called `sfx` itself would be a
    /// creature that plays through the pause card and the shot harness.
    bit: bool = false,
    growled: bool = false,
    yelped: bool = false,
    /// Seconds until it may growl again — a wolf that growled every frame it had something in its sights
    /// would be a chainsaw.
    growlCool: f32 = 0,
    hitLatch: bool = false,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    /// WHICH BODY IT IS GOING FOR. An index into the field, handed in by game.zig — the creature never reaches
    /// out for the foe list, exactly as a foe never reaches out for the hero's shield (`foe.Parry`'s law).
    quarry: ?Quarry = null,
    /// THE WAY ROUND WHAT IS IN FRONT OF IT — stamped by `game.markWay` like every creature's on the field, and
    /// read in the one place this one travels.
    nav: foe.Nav = .{},
    /// SECONDS IT HAS BEEN OUT PAST `RECALL_R`, and the creature's own because the creature is the thing that
    /// knows how far off it is standing. `LOST_DWELL` is what it is measured against.
    lostT: f32 = 0,
    biteCool: f32 = 0,
    /// WHERE IT STOOD BEFORE IT MOVED THIS FRAME — what the game's terrain gate measures the step against
    /// (`game.tickPack`). Carried by the creature rather than snapshotted from outside because the pack
    /// COMPACTS: a slot's occupant can change inside one `Pack.update`, and a `was` array taken before it
    /// would gate one spirit's step against another's ground.
    wasAt: rl.Vector3 = mathx.zero3,
    /// Last frame's jaw, for the swept bite — `foe.Blade`'s `a0`/`b0`.
    jaw0: rl.Vector3 = mathx.zero3,
    jaw1: rl.Vector3 = mathx.zero3,
    /// The collapse and the coming-apart, `foe.dissipate`'s own fields.
    fade: f32 = 0,
    gone: bool = false,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0xD16E),
    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn alive(self: *const Wolf) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Wolf) bool {
        return self.state == .dead;
    }
    pub fn airborne(_: *const Wolf) bool {
        return false;
    }
    pub fn bodyR(self: *const Wolf) f32 {
        return BODY_R * self.scale;
    }
    pub fn hurtRadius(self: *const Wolf) f32 {
        return HURT_R * self.scale;
    }
    pub fn centerWorld(self: *const Wolf) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_H * W, self.scale, 0);
    }
    pub fn topWorld(self: *const Wolf) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_H * W, self.scale, 0);
    }
    /// THE MARK RIDES THE BODY — the skull, like the three humanoids', so it dips when the head dips.
    pub fn lockPoint(self: *const Wolf) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.02 * W, 0.05 * W));
    }
    pub fn flashFrac(self: *const Wolf) f32 {
        return self.flash;
    }
    /// ITS FACE, for the spirit panel — off the posed skull like `lockPoint`, and a little further down the
    /// muzzle so the picture is a wolf's head and not the back of its braincase.
    pub fn facePoint(self: *const Wolf) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.02 * W, 0.24 * W));
    }

    pub fn spawn(at: rl.Vector3, facing: f32) Wolf {
        var w = Wolf{ .pos = at, .facing = facing, .rest = restPose() };
        w.pose();
        // THE JAW STARTS WHERE THE JAW IS. Left at the origin, the first frame's swept bite is a segment from
        // world zero to its teeth — a blade across the entire map. It cannot bite that early today (it spawns
        // idle and has to reach something first), which is exactly what makes it the kind of latent blade that
        // goes off the day the spirit is ever called ON TOP of a foe.
        w.jaw1 = w.jawPoint();
        w.jaw0 = w.jaw1;
        return w;
    }

    /// WHERE THE TEETH ARE, in the world — the point the bite's swept blade is built from. Its OWN function
    /// because two places need it (the spawn, and the game's per-frame stamp) and as two copies the offset
    /// down the jaw bone was a literal that had to agree with itself.
    pub fn jawPoint(self: *const Wolf) rl.Vector3 {
        return foe.markOn(self.xf[JAW], v3(0, 0, JAW_REACH * W));
    }

    /// A BLOW LANDING ON IT. Its own entry point rather than the foe contract's `tryHit`: what swings at this
    /// creature is a CREATURE, and game.zig hands the blow over already knowing who it was aimed at.
    pub fn takeHit(self: *Wolf, h: combat.Hit) combat.HitOutcome {
        if (self.state == .dead or self.gone) return .ignored;
        const r = self.vit.hit(h);
        self.flash = 1.0;
        switch (r) {
            .death => {
                self.enterDeath();
                return .taken;
            },
            .heavy, .light => {
                self.state = .hurt;
                self.t = 0;
                self.heavyStun = r == .heavy;
                self.yelped = true;
            },
            .none => {},
        }
        return .taken;
    }

    fn enterDeath(self: *Wolf) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    /// THE BLADE ITS JAWS ARE, live only through the strike window.
    ///
    /// **IT IS A `pierce`, AND THAT IS NOT A LIE ABOUT WHAT IT IS.** `pierce` is what tells `foe.strike` to
    /// leave the victim's `hitLatch` ALONE — and that latch belongs to the HERO'S SWING. Shared, a bite landing
    /// mid-swing latches the foe and eats the sword blow the player actually paid stamina for, and the wolf's
    /// window closing then CLEARS the latch and lets one swing land twice. The latch for this blow is the
    /// wolf's own (`hitLatch` here, taken at the call site), which is exactly the split `pierce` exists for.
    ///
    /// So the segment is the shaft's too: `a`→`b` is the ground the jaws crossed THIS FRAME, which is both the
    /// swept test that stops a lunge tunnelling through a body and the direction the shove reads along.
    ///
    /// **AND BECAUSE THE BITE IS A HOP, IT REACHES MID-HEIGHT — the hero's own jump rule, on jaws** (owner's
    /// call). Nothing here tests a height: the blade is the jaw's REAL WORLD POINT, and the jaw is a child of
    /// a root the hop lifts, so at the top of the throw the teeth are about a metre up and a body whose middle
    /// is up there is simply in the way. That is the whole mechanism — a creature standing tall enough that a
    /// ground-level snap would pass under its belly can be caught by the leap, exactly as he clears a toad by
    /// jumping. It does NOT reach a perched leechfly at 4.6 m, and it should not: that trade is the bow's.
    pub fn blade(self: *const Wolf) foe.Blade {
        const live = self.state == .bite and self.t >= BITE_WIND and self.t < BITE_WIND + BITE_STRIKE;
        return .{
            .active = live,
            .r = 0.20 * self.scale,
            .a = self.jaw0,
            .b = self.jaw1,
            .a0 = self.jaw0,
            .b0 = self.jaw1,
            .pierce = true,
            .by = .spirit, // …and this is what buys it the creature's attention (`foe.reached`)
            .hit = BITE_HIT,
        };
    }

    /// ONE FRAME. `quarry` is stamped from outside before this runs; `heel` is where to stand when there is
    /// nothing to go for, which is the hero.
    pub fn update(self: *Wolf, dt: f32, heel: rl.Vector3, bounds: f32) void {
        self.justDied = false; // the one-frame flag, reset at the TOP (the foe contract's own rule)
        self.wasAt = self.pos; // …and the ground it is stepping OFF, for the gate that runs after this
        self.bit = false;
        self.growled = false;
        self.yelped = false;
        self.growlCool = mathx.maxF(0, self.growlCool - dt);
        self.t += dt;
        self.vit.tick(dt);
        self.flash = mathx.maxF(0, self.flash - dt * 4.0);
        self.biteCool = mathx.maxF(0, self.biteCool - dt);
        // HOW LONG IT HAS BEEN OUT OF HIS REACH. Up here with the other clocks and BEFORE the early returns,
        // because a spirit stuck 20 m off worrying at something is exactly as lost as one stuck against a bank.
        if (mathx.distXZ(self.pos, heel) > RECALL_R) self.lostT += dt else self.lostT = 0;
        foe.tickParticles(&self.parts, dt, self.pos.y);
        self.jaw0 = self.jaw1;

        if (self.state == .dead) {
            foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            self.speed = 0;
            self.pose();
            return;
        }
        if (self.state == .hurt) {
            if (self.t >= combat.foeStunDur(self.heavyStun)) self.state = .idle;
            self.speed = 0;
            self.settle(dt, bounds);
            self.pose();
            return;
        }
        if (self.state == .bite) {
            self.faceToward(if (self.quarry) |q| q.at else heel, dt);
            self.speed = 0;
            // THE HOP CARRIES IT IN. The travel is spread across the wind and the strike and stops dead at the
            // recovery — it is a throw of the whole body, not a glide, so it goes through `stepXZ` like any
            // other committed travel and the terrain gate still gets the last word.
            const hopEnd = BITE_WIND + BITE_STRIKE;
            if (self.t < hopEnd) {
                const step = BITE_HOP * (dt / hopEnd);
                mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
            }
            if (self.t >= hopEnd + BITE_RECOVER) {
                self.state = .idle;
                self.t = 0;
                self.biteCool = BITE_COOL;
                self.hitLatch = false;
            }
            self.settle(dt, bounds);
            self.pose();
            return;
        }

        // NOTHING TO KILL: heel. Something to kill: go at it, and bite when the jaws will reach.
        const want = self.wants(heel);
        const gap = mathx.distXZ(self.pos, want);
        const stop: f32 = if (self.quarry) |q| stopR(q.r) else HEEL_R;
        // …and the bite opens a little further out than it lands, because the HOP closes the rest.
        if (self.quarry != null and gap <= triggerR(self.quarry.?.r) and self.biteCool <= 0) {
            self.state = .bite;
            self.t = 0;
            self.hitLatch = false;
            self.speed = 0;
            self.bit = true; // ON THE GATHER, not the impact: the snarl is the tell, and it leads the jaws
        } else if (gap > stop) {
            // …and it warns whatever it is running at, now and then.
            if (self.quarry != null and self.growlCool <= 0) {
                self.growled = true;
                self.growlCool = GROWL_EVERY;
            }
            // WHICH GAIT IS THE SPEED'S OWN BUSINESS — the gait itself comes out of `gaitAt` off the speed,
            // never chosen here. **AND IT RUNS WHENEVER IT IS A LONG WAY OFF**, chasing or heeling alike
            // (owner's call): a spirit that trots back from thirty metres is one you out-walk forever, so the
            // gap decides before the errand does.
            const far = gap > RUN_GAP;
            const want_speed: f32 = if (far or self.quarry != null)
                GALLOP_SPEED * 0.82
            else if (gap > HEEL_R * 2.0) TROT_SPEED else WALK_SPEED;
            self.speed = mathx.approach(self.speed, want_speed, ACCEL * dt);
            self.state = .move;
            // …AND IT TURNS ROUND WHAT IS IN THE WAY RATHER THAN INTO IT (`foe.Nav`). It walks where it is
            // LOOKING, so the way through is read at the FACING and the step below is untouched — the GAP is
            // still measured to the real target, so a detour cannot talk it into biting a wall or ambling home
            // as though it had arrived.
            self.faceToward(self.nav.aim(self.pos, want), dt);
            const step = self.speed * dt;
            mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
            // THE PHASE IS DRIVEN BY THE DISTANCE ACTUALLY TRAVELLED — never by `dt` — so a paw that is down
            // is down at a fixed world point however the speed changes under it.
            self.phase = wrap01(self.phase + step / strideFor(self.speed));
        } else {
            self.speed = mathx.approach(self.speed, 0, ACCEL * 2.0 * dt);
            self.state = .idle;
            if (self.quarry == null) self.faceToward(heel, dt);
        }
        self.settle(dt, bounds);
        self.pose();
    }

    /// The gait blend, and the shove a blow put into it bleeding off — the one thing that moves it that is not
    /// its own legs, through the SHARED step every wounded creature's goes through.
    fn settle(self: *Wolf, dt: f32, bounds: f32) void {
        self.speedS = mathx.approach(self.speedS, self.speed, GAIT_BLEND * dt);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
    }

    /// WHERE IT IS GOING: the body it is going for, else HIM. One definition, because game.zig needs the same
    /// answer to stamp the way through and two copies of a choice this small still drift.
    pub fn wants(self: *const Wolf, heel: rl.Vector3) rl.Vector3 {
        return if (self.quarry) |q| q.at else heel;
    }

    /// …and the same thing as the steering asks it (`foe.Nav`): null while it is not walking anywhere, so a
    /// stale heading cannot bend the bite's own hop or a stun.
    pub fn navWant(self: *const Wolf, heel: rl.Vector3) ?rl.Vector3 {
        if (self.state == .dead or self.state == .hurt or self.state == .bite) return null;
        return self.wants(heel);
    }

    /// **HAS THE BOND BEEN STRETCHED PAST WHAT WALKING CAN FIX.** Running home is the first answer and it is
    /// nearly always the right one; this is for the cases where it cannot work — a bank it may not climb, a
    /// pocket with no way out inside its own probe, or a man who simply out-sprints it.
    pub fn lost(self: *const Wolf) bool {
        return self.lostT >= LOST_DWELL and self.state != .dead and !self.gone;
    }

    /// THE BOND CLOSING THE GAP ITSELF (owner's call): a summon the player has to walk back and fetch is one he
    /// has lost. The SPOT is handed in, because the only thing that knows what is standing there is the file
    /// that owns the world (`game.spiritSpot` — the bell's own spot, so it arrives where it was first called).
    pub fn reappear(self: *Wolf, at: rl.Vector3, facing: f32) void {
        const was = self.pos;
        const from = self.fxHead;
        self.rift(was);
        // The departure's motes are floored on the ground it LEFT, not on the one it arrives over — a burst
        // fired clear of its owner is exactly what `foe.floorBurst` is for.
        foe.floorBurst(&self.parts, from, self.fxHead, was.y);
        self.pos = at;
        self.facing = facing;
        self.state = .idle;
        self.t = 0;
        self.speed = 0;
        self.speedS = 0;
        self.shove = mathx.zero3;
        self.lostT = 0;
        self.nav = .{};
        self.wasAt = at; // the terrain gate measures a STEP off this, and a rematerialize is not a step
        self.rift(at);
        self.pose();
        // THE JAWS ARRIVE WITH IT (`spawn`'s own law): left where they were, this frame's swept bite is a blade
        // from one side of the map to the other.
        self.jaw1 = self.jawPoint();
        self.jaw0 = self.jaw1;
    }

    /// THE TEAR AT BOTH ENDS OF A REMATERIALIZE — the shade's `rift`, on a body that does not thin out. A spirit
    /// that simply stood somewhere else between two frames reads as a dropped frame rather than as a thing that
    /// moved, and the motes are the only cue there is.
    fn rift(self: *Wolf, at: rl.Vector3) void {
        var i: i32 = 0;
        while (i < RIFT_N) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.4, 3.0) * self.scale;
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                v3(at.x, at.y + (CENTER_H * W + self.fxRng.range(-0.32, 0.42)) * self.scale, at.z),
                v3(mathx.cosf(a) * sp, self.fxRng.range(-0.3, 1.5), mathx.sinf(a) * sp),
                self.fxRng.range(0.18, 0.32),
                self.fxRng.range(0.030, 0.058) * self.scale,
                0.006,
                if (self.fxRng.float() < 0.4) EYE else PELT_LT,
                1.2, // …and they fall INWARD, which is the place closing after it (the shade's own trick)
            );
        }
    }

    fn faceToward(self: *Wolf, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    /// Stage the bite's own GATHER at `u` (0..1 of the wind) for the harness — `hero.stageRing`'s pattern, and
    /// a POSE and nothing else: no blow, no hop travel, no cooldown spent. It is the only frame the crouch can
    /// be judged on, and a crouch is judged by whether the PAWS stayed where the animal was standing.
    pub fn stageGather(self: *Wolf, u: f32) void {
        self.state = .bite;
        self.t = mathx.clampF(u, 0, 1) * BITE_WIND;
        self.pose();
    }

    /// THE POSE. One world matrix per bone, once a frame — `draw` only replays them.
    pub fn pose(self: *Wolf) void {
        const g = gaitAt(self.speedS);
        const stride = strideFor(self.speedS);
        const ph = limbPhases(self.phase, g);
        // How much gait to show at all: standing still, the legs are straight and only the breath moves.
        const m = mathx.clampF(self.speedS / WALK_SPEED, 0, 1);
        const s = self.scale;
        const breath = mathx.sinf(self.t * 2.1) * 0.006 * W;
        // THE REACTION, and it is the game's one curve — never a private copy of it.
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        // …and the collapse: it goes down on its side and STAYS there while it comes apart.
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;

        // THE HOP'S OWN HEIGHT AND ITS GATHER. It SINKS through the wind, leaves the ground across the strike,
        // and is back down by the end of it — one arc off the bite's own clock, so the lift and the travel
        // cannot drift apart the way a second timer would let them.
        var hop: f32 = 0;
        var crouch: f32 = 0;
        if (self.state == .bite) {
            const hopEnd = BITE_WIND + BITE_STRIKE;
            crouch = BITE_CROUCH * mathx.smoothstep(0, BITE_WIND * 0.8, self.t) * (1.0 - mathx.smoothstep(BITE_WIND, hopEnd, self.t));
            if (self.t > BITE_WIND * 0.55 and self.t < hopEnd) {
                const u = (self.t - BITE_WIND * 0.55) / (hopEnd - BITE_WIND * 0.55);
                hop = BITE_HOP_UP * mathx.sinf(u * std.math.pi);
            }
        }
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rz(-72.0 * mathx.smoothstep(0, 1, fall)), // over onto its shoulder
            mul(tr(0, self.rest[ROOT].y * s + breath + (hop - crouch) * W - 0.10 * W * fall, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        // THE SPINE FLEXES WITH THE GAIT. A galloping canid's back is half its stride — it bows and extends
        // once a cycle — and at a walk it barely moves. Twice the phase would be a trot's two beats; this is
        // ONE bow per stride, which is what a bounding spine does.
        const flex = mathx.sinf(self.phase * std.math.tau) * m * (4.0 + 9.0 * mathx.clampF((self.speedS - TROT_SPEED) / (GALLOP_SPEED - TROT_SPEED), 0, 1));
        const duck: f32 = 8.0 * react;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, rx(-flex * 0.5 - duck * 0.3));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, rx(-flex * 0.5 - duck * 0.3));
        // The neck carries the head LEVEL through the bow — a wolf's eyes stay on what it is running at.
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, rx(flex * 0.7 + 6.0 * m - duck));
        heromod.setJoint(&wx, &self.rest, HEAD, NECK, rx(flex * 0.3 - 4.0 * m - duck * 0.6));
        // THE JAWS open through the wind and SNAP shut on the strike.
        const gape: f32 = if (self.state == .bite) blk: {
            if (self.t < BITE_WIND) break :blk 34.0 * mathx.smoothstep(0, BITE_WIND, self.t);
            break :blk 34.0 * (1.0 - mathx.smoothstep(BITE_WIND, BITE_WIND + BITE_STRIKE * 0.5, self.t));
        } else 0;
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(gape));
        // The ears go FLAT on a reaction and prick the rest of the time — the cheapest read on the whole animal.
        const ear: f32 = -58.0 * react;
        heromod.setJoint(&wx, &self.rest, EARL, HEAD, mul(rx(ear), rz(-6.0)));
        heromod.setJoint(&wx, &self.rest, EARR, HEAD, mul(rx(ear), rz(6.0)));
        // The tail swings against the gait and drops when it is hurt.
        const tailSwing = mathx.sinf(self.phase * std.math.tau + 1.1) * 7.0 * m;
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(rx(-12.0 * m + 26.0 * react), ry(tailSwing)));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(rx(-6.0 * m + 10.0 * react), ry(tailSwing * 0.8)));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(rx(-3.0 * m), ry(tailSwing * 0.6)));

        // THE FOUR COLUMNS, each solved to where its paw has to be this frame — off the ONE table that carries
        // the bones, the lengths and the fold (`LIMBS`), whose index is the limb's own phase.
        // …and the fold signs go WITH the solver's negation: in the rig's own sense the elbow has to end up
        // behind the column and the stifle in front of it, which is the opposite pair to the one the solver's
        // own +Z-forward convention names. Straight legs with a kink at the top was this.
        // …AND THE FEET COME UP WITH IT. `hop` raises the body, so without this the paws stay nailed to the
        // ground and the legs simply stretch — the body floats off four stilts instead of the animal leaving
        // the earth. Folding the reach by the same lift is what makes it a jump.
        // **ONE MECHANISM, NOT TWO.** The tuck is `tuck` and nothing else: the joint heights stay what they
        // are. Written with the hop ALSO subtracted from `jointY` it was applied twice over — and the first
        // application had the sign backwards on top of that, since a body rising by `hop` needs its planted
        // foot to reach `+hop` FURTHER, not less. Between the two the legs folded to the chest on a 15 cm hop.
        // …AND THE GATHER GOES THE OTHER WAY. `crouch` LOWERS the whole animal (the root's own `-crouch`), so
        // the joint it hangs from is that much nearer the ground and the leg has that much LESS to span: the
        // sink is what folds the limbs, which is the whole of what a gather looks like. Added instead, the
        // reach ran past the ground by twice the crouch — and past the limb's own span, so `limbChain` clamped
        // it dead straight and stood the animal 20 cm into the earth on four locked stilts for the whole of
        // every wind-up. Level the LEG, never the body (the hero's ankle law) — this is that law at the hip.
        const tuck = hop / @max(HIP_Y, 0.001);
        inline for (LIMBS, 0..) |L, i| self.column(&wx, L, ph[i], g, stride, m, crouch, tuck);
        self.xf = wx;
    }

    /// ONE LIMB, from its own joint down to the paw. Shared by all four because the only things that differ
    /// are the two segment lengths, the fold direction and the phase — which is the whole point of solving a
    /// limb rather than authoring one.
    fn column(
        self: *Wolf,
        wx: *[N]rl.Matrix,
        L: Limb,
        phase: f32,
        g: Gait,
        stride: f32,
        m: f32,
        /// How far the whole animal has SUNK this frame — the gather. It comes off the joint's own height,
        /// because a body that is lower has that much less leg to span (see `pose`).
        crouch: f32,
        /// How far the paw is drawn UP under the body, 0..1 of the limb's own reach — the hop's tuck.
        tuck: f32,
    ) void {
        const top = L.bones[0];
        const mid = L.bones[1];
        const low = L.bones[2];
        const paw = L.bones[3];
        const at = pawAt(phase, g, stride);
        // At a standstill the paw sits under its own joint; the gait fades in with `m` so an idle wolf is not
        // walking on the spot.
        //
        // **THE FORWARD AXIS IS NEGATED GOING INTO THE SOLVER, AND THAT ONE SIGN IS THE WHOLE MOONWALK.**
        // `pawAt` works in the world's sense (+z is the way the animal is travelling) but `rx(+)` swings a
        // bone hanging straight down toward −Z in this matrix convention, so a paw asked to reach FORWARD was
        // rendered reaching BACK. Every limb then ran its cycle in reverse under a body moving the right way,
        // which is exactly the "feet sliding the wrong way" a moonwalk is. Negated HERE, once, rather than
        // inside `limbChain` — that function is pure sagittal geometry with +Z forward and its tests pin it
        // that way; this is the rig's own handedness and it belongs at the rig.
        const dz = -at.z * m;
        // `tuck` folds the reach itself, so a hopping wolf draws its feet up under it instead of hanging them.
        const dy = ((L.jointY - crouch) * W - at.y * m) * (1.0 - mathx.clampF(tuck, 0, 0.6));
        const sol = limbChain(L.upper * W, L.lower * W, dy, dz, L.bend);
        // …and it hangs off whatever the LAYOUT says it hangs off (the forelimbs on the chest, the hinds on the
        // pelvis), rather than a `top == SHL or top == SHR` restating the table two hundred lines below it.
        heromod.setJoint(wx, &self.rest, top, @intCast(PARENT[top]), rx(sol.upper));
        heromod.setJoint(wx, &self.rest, mid, top, rx(sol.lower));
        // The carpus/hock takes a share of the lower segment's fold back the other way — that second bend is
        // the zig-zag a canid's leg has and a two-link solve on its own cannot show.
        heromod.setJoint(wx, &self.rest, low, mid, rx(-sol.lower * 0.45));
        // …and the paw levels itself against the ground, the hero's own ankle rule: level the FOOT, never lift
        // the body. It is flat while it is planted and points as it leaves.
        const lift: f32 = if (planted(phase, g)) 0 else 26.0 * m;
        heromod.setJoint(wx, &self.rest, paw, low, rx(-sol.upper - sol.lower * 0.55 + lift));
    }

    pub fn draw(self: *const Wolf, mesh: *const [N]rl.Mesh, mat: rl.Material) void {
        if (self.gone) return;
        for (0..N) |i| rl.drawMesh(mesh[i], mat, self.xf[i]);
    }

    /// THE COMING-APART, drawn as unlit spheres over the opaque pass like every other creature's
    /// (`foe.drawParticles`). `foe.dissipate` fills this pool every frame of the death whether or not anybody
    /// draws it, so with no call anywhere the spirit was the one body in the game that went out into nothing —
    /// the ARCHER's missing emitter again, one layer further on.
    pub fn drawFx(self: *const Wolf) void {
        foe.drawParticles(&self.parts);
    }
};

/// THE BOND — everything the bell has standing, and the cap on it. Sized off `combat.SUMMON_MAX` rather than
/// held as a `?Wolf`, so raising the cap to two is that constant and nothing here.
pub const Pack = struct {
    wolves: [combat.SUMMON_MAX]Wolf = undefined,
    n: usize = 0,
    mesh: [N]rl.Mesh = undefined,
    mat: rl.Material = undefined,
    ready: bool = false,

    /// The meshes are built ONCE and shared by every wolf — a per-instance mesh is a per-instance upload.
    pub fn load(self: *Pack, shader: rl.Shader) void {
        var mat = rl.loadMaterialDefault() catch @panic("wolf material");
        mat.shader = shader;
        for (0..N) |i| self.mesh[i] = boneMesh(i);
        self.mat = mat;
        self.ready = true;
    }
    /// The depth pass swaps every caster onto the shadow shader and back (`game.setCasterShaders`).
    pub fn setShader(self: *Pack, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    pub fn live(self: *Pack) []Wolf {
        return self.wolves[0..self.n];
    }
    pub fn liveConst(self: *const Pack) []const Wolf {
        return self.wolves[0..self.n];
    }
    /// IS THERE ROOM — the one question the bell asks before it spends anything.
    pub fn room(self: *const Pack) bool {
        return self.n < combat.SUMMON_MAX;
    }
    /// …and the one standing, if any. `SUMMON_MAX` is 1 today, so this is the whole of what the HUD needs.
    pub fn firstConst(self: *const Pack) ?*const Wolf {
        if (self.n == 0) return null;
        return &self.wolves[0];
    }

    /// **SEND EVERYTHING HOME WITHOUT UNLOADING THE MESHES** — a new game, and the one caller
    /// (`game.beginGame`). It exists because `= .{}` does NOT do this: `mesh`/`mat`/`ready` sit in this
    /// struct beside `wolves`/`n`, so resetting the whole thing puts `ready` back to false and `draw`
    /// returns at its first line — a spirit that is called, walks, fights and is INVISIBLE. That is the
    /// mirror of `foe.zig`'s rule (a group is emptied through its own `clear`, never by zeroing `n`), and
    /// the reason is the same one: only the group knows what it owns.
    ///
    /// **AND IT IS THE ONLY NAME FOR IT.** A `reset` sat beside this doing the identical `self.n = 0` with
    /// none of the note above, and both were live — `game.beginGame` took this door and the shot harness took
    /// the other. Every OTHER group's `reset` means "re-home from the map", so the twin was the same word
    /// promising a different contract, one keystroke from the `= .{}` this comment exists to forbid.
    pub fn clear(self: *Pack) void {
        self.n = 0;
    }

    pub fn call(self: *Pack, at: rl.Vector3, facing: f32) bool {
        if (!self.room()) return false;
        self.wolves[self.n] = Wolf.spawn(at, facing);
        self.n += 1;
        return true;
    }

    /// A spirit that has finished coming apart leaves the field, and the slot comes back with it — which is
    /// what makes "until killed" a real cost rather than a permanent second body.
    pub fn update(self: *Pack, dt: f32, heel: rl.Vector3, bounds: f32) void {
        var i: usize = 0;
        while (i < self.n) {
            self.wolves[i].update(dt, heel, bounds);
            if (self.wolves[i].gone) {
                // Compacted, because unlike a foe row this list is not indexed from outside between frames.
                self.wolves[i] = self.wolves[self.n - 1];
                self.n -= 1;
                continue;
            }
            i += 1;
        }
    }

    pub fn draw(self: *const Pack) void {
        if (!self.ready) return;
        for (self.liveConst()) |*w| w.draw(&self.mesh, self.mat);
    }

    /// JUST THE FIRST ONE, for the spirit toast's portrait — the real body in its real pose, so the face in
    /// the panel is the animal that is actually standing there (`npc.Folk.drawOne`'s reason).
    pub fn drawFirst(self: *const Pack) void {
        if (!self.ready or self.n == 0) return;
        self.wolves[0].draw(&self.mesh, self.mat);
    }

    /// …and its FX, which are NOT part of `draw`: they go over the whole opaque pass, once, with every other
    /// creature's (`game.drawScene`) — inside `draw` they would be drawn twice and once into the depth pass.
    pub fn drawFx(self: *const Pack) void {
        for (self.liveConst()) |*w| w.drawFx();
    }

};

test "ONE SPIRIT STANDS AT A TIME, and its slot comes back when it is gone" {
    var p = Pack{};
    try std.testing.expect(p.room());
    try std.testing.expect(p.call(mathx.zero3, 0));
    try std.testing.expectEqual(@as(usize, combat.SUMMON_MAX), p.n);
    // A second ringing is refused while one is up — the cap is the Pack's, not the bell's.
    try std.testing.expect(!p.room());
    try std.testing.expect(!p.call(v3(3, 0, 3), 0));
    // …and killing it hands the slot back, which is what "until killed" has to mean.
    p.wolves[0].gone = true;
    p.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expectEqual(@as(usize, 0), p.n);
    try std.testing.expect(p.room());
}

test "a spirit dies and stops being a collider before it stops being drawn" {
    var w = Wolf.spawn(mathx.zero3, 0);
    try std.testing.expect(foe.corporeal(&w));
    _ = w.takeHit(.{ .dmg = HP * 2 });
    try std.testing.expect(w.justDied);
    // A CORPSE IS NOT A COLLIDER (the foe contract's own law) — but it is still drawn while it comes apart.
    try std.testing.expect(!foe.corporeal(&w));
    try std.testing.expect(w.alive());
    // …and `justDied` is a ONE-FRAME flag, not a latch that bills the death every frame after.
    w.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expect(!w.justDied);
}

test "THE EDGES A BLOW SETS DO NOT SURVIVE THE UPDATE — so they have to be read above it" {
    // `takeHit` runs with the FIELD's blows and `update` clears every one-frame edge at the top of its body,
    // so a caller reading these two AFTER `Pack.update` reads false on every frame — which is what left
    // `wolf_hurt` and `wolf_die` silent. Pinned here rather than in game.zig: the contract is the creature's.
    var hurt = Wolf.spawn(mathx.zero3, 0);
    _ = hurt.takeHit(.{ .dmg = 1, .poise = 999 });
    try std.testing.expect(hurt.yelped);
    hurt.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expect(!hurt.yelped);

    var slain = Wolf.spawn(mathx.zero3, 0);
    _ = slain.takeHit(.{ .dmg = HP * 2 });
    try std.testing.expect(slain.justDied);
    slain.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expect(!slain.justDied);
}

test "IT WALKS THE STAMPED WAY, and the gap is still measured to the real target" {
    var w = Wolf.spawn(mathx.zero3, 0);
    const heel = mathx.ground(0, 30); // straight ahead (+Z) and a long way off, so it runs
    // Stamped hard to one side: the body has to end up going THAT way, not at him.
    w.nav.dir = v3(1, 0, 0);
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) w.update(1.0 / 60.0, heel, 100);
    try std.testing.expect(w.pos.x > 1.0);
    try std.testing.expect(@abs(w.pos.z) < w.pos.x); // …and it did not simply carry on toward him

    // …AND A DETOUR MAY NOT TALK IT INTO ARRIVING. Standing off him with the way bent sideways it must still
    // read as far away — the gap is the real one, so it keeps running rather than settling to heel.
    try std.testing.expectEqual(State.move, w.state);
    try std.testing.expect(w.speed > TROT_SPEED);
}

test "A SPIRIT THAT CANNOT GET HOME IS MOVED HOME" {
    var w = Wolf.spawn(mathx.ground(0, RECALL_R + 8.0), 0);
    const heel = mathx.zero3;
    // Held where it stands (a bank, a wall — here simply a test that never lets it move) the clock fills.
    var t: f32 = 0;
    while (t < LOST_DWELL) : (t += 1.0 / 60.0) {
        const at = w.pos;
        w.update(1.0 / 60.0, heel, 100);
        w.pos = at; // the gate's refusal, stood in for
        try std.testing.expect(!w.lost() or t >= LOST_DWELL - 1.0 / 30.0);
    }
    w.update(1.0 / 60.0, heel, 100);
    w.pos = mathx.ground(0, RECALL_R + 8.0);
    try std.testing.expect(w.lost());

    // …and the bond puts it down where it is told, with its jaws and its clock.
    const spot = mathx.ground(1.5, 0.5);
    w.reappear(spot, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(spot, w.pos), 1e-5);
    try std.testing.expectEqual(State.idle, w.state);
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.lostT, 1e-6);
    try std.testing.expect(!w.lost());
    // THE JAWS ARRIVED WITH IT. Left behind, the swept bite is a blade from the old spot to the new one —
    // `spawn`'s own law, and the reason this is measured rather than trusted.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(w.jaw0, w.jaw1), 1e-5);
    try std.testing.expect(mathx.distXZ(w.jaw1, spot) < 2.0);
    // …and it is inside the ring the moment it lands, so the clock cannot fire again next frame.
    w.update(1.0 / 60.0, heel, 100);
    try std.testing.expect(!w.lost());
}

test "a dead spirit is never moved — the bond does not fetch a corpse" {
    var w = Wolf.spawn(mathx.ground(0, RECALL_R + 8.0), 0);
    _ = w.takeHit(.{ .dmg = HP * 2 });
    w.lostT = LOST_DWELL * 2.0;
    try std.testing.expect(!w.lost());
}

test "HILDEBRAND'S TWO DIALS ARE THE GAIT — the anchors are the published ones and the blend is continuous" {
    // The measured figures, so a retune has to argue with the papers rather than with a comment.
    try std.testing.expectApproxEqAbs(@as(f32, 0.65), WALK.duty, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.84), WALK.lag, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.50), TROT.lag, 1e-6); // diagonal couplets, by definition
    // A WALK ALWAYS HAS A FOOT DOWN and a gallop does not — that is what duty factor 0.5 divides.
    try std.testing.expect(WALK.duty > 0.5);
    try std.testing.expect(GALLOP.duty < 0.5);
    // …and nothing jumps on the way between them.
    var prev = gaitAt(0);
    var s: f32 = 0;
    while (s < 7.0) : (s += 0.05) {
        const g = gaitAt(s);
        try std.testing.expect(@abs(g.duty - prev.duty) < 0.02);
        try std.testing.expect(@abs(g.lag - prev.lag) < 0.03);
        prev = g;
    }
}

test "A PLANTED PAW IS WORLD-FIXED — the whole of why the feet do not skate" {
    const g = TROT;
    const stride = strideFor(TROT_SPEED);
    // Walk the phase forward by a real distance and carry the body forward by that same distance. A paw that
    // is down must come out at the SAME world point both times, or the animal is sliding on it.
    const p0: f32 = 0.10;
    const advance: f32 = 0.06; // metres
    const p1 = p0 + advance / stride;
    try std.testing.expect(planted(p0, g) and planted(p1, g));
    const a = pawAt(p0, g, stride);
    const b = pawAt(p1, g, stride);
    // Body-frame z moved back by exactly what the body moved forward…
    try std.testing.expectApproxEqAbs(advance, a.z - b.z, 1e-4);
    // …so world z (body z + offset) is unchanged. That subtraction IS the law.
    try std.testing.expectApproxEqAbs(@as(f32, 0), (a.z) - (b.z + advance), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.y, 1e-6); // and it stayed on the ground the whole time
}

test "THE HIND FOOT LANDS IN THE FOREFOOT'S PRINT — one stride length for all four limbs" {
    // Fore and hind stride lengths in the working-dog data are equal to two decimals. Here that is structural:
    // every limb reads the same `stride`, so tracking up cannot drift.
    const g = TROT;
    const stride = strideFor(TROT_SPEED);
    // Through its STANCE a paw sweeps the share of the stride the body covers while it is down…
    const swept = pawAt(0, g, stride).z - pawAt(g.duty - 1e-5, g, stride).z;
    try std.testing.expectApproxEqAbs(stride * g.duty, swept, 1e-3);
    // …and the offset is PERIODIC, so over one whole cycle the paw advances in the world by exactly the
    // stride it is named after. THAT is the print-to-print distance, and it is the same number for all four
    // limbs because they all read one `stride` — which is what makes the hind foot land in the fore's print.
    try std.testing.expectApproxEqAbs(pawAt(0, g, stride).z, pawAt(1.0 - 1e-6, g, stride).z, 1e-3);

    const ph = limbPhases(0.0, g);
    // …and at a trot the diagonal pairs are exactly together, which is what a trot IS.
    try std.testing.expectApproxEqAbs(ph[0], wrap01(ph[3]), 1e-5); // hind-left with fore-right
    try std.testing.expectApproxEqAbs(ph[1], wrap01(ph[2]), 1e-5); // hind-right with fore-left
}

/// The lowest of the four paw bones' origins, in world Y — what "standing on the ground" is measured off.
fn deepestPaw(w: *const Wolf) f32 {
    var low: f32 = 1e9;
    for ([_]usize{ PAWL, PAWR, HPAWL, HPAWR }) |p| low = mathx.minF(low, foe.markOn(w.xf[p], mathx.zero3).y);
    return low;
}

test "A GATHER FOLDS THE LEGS, IT DOES NOT SINK THE ANIMAL — the paws stay where they were standing" {
    var w = Wolf.spawn(mathx.zero3, 0);
    const standing = deepestPaw(&w);
    // Walk the whole wind-up, which is where `crouch` lives. Added to the joint height instead of taken off it
    // the reach ran past the limb's own span, `limbChain` clamped it straight, and the animal stood 20 cm into
    // the earth on four locked stilts — so a few centimetres of give is a crouch and a fifth of a metre is this.
    w.state = .bite;
    var t: f32 = 0;
    var worst: f32 = standing;
    while (t <= BITE_WIND) : (t += 1.0 / 240.0) {
        w.t = t;
        w.pose();
        worst = mathx.minF(worst, deepestPaw(&w));
    }
    try std.testing.expect(worst > standing - 0.05);
}

test "CLEARING THE PACK SENDS IT HOME, IT DOES NOT UNLOAD IT" {
    // The bug this pins was silent and total: `= .{}` in a new-game reset put `ready` back to false, and
    // `draw` returns at its first line — the bell called a spirit that walked, fought and could not be seen.
    // Nothing about the wolf's behaviour changes when its meshes go, which is why only an eye caught it.
    var p = Pack{};
    p.ready = true; // stands in for `load`, which needs a GL context
    p.n = 1;
    p.clear();
    try std.testing.expectEqual(@as(usize, 0), p.n);
    try std.testing.expect(p.ready);
}

test "the two-link solver reaches what it is given and folds the right way round" {
    const a: f32 = 0.30;
    const b: f32 = 0.40;
    // Straight down at full stretch: near enough no bend anywhere. NOT exactly zero, and deliberately not
    // tested as such — `limbChain` clamps the reach a hair inside `a + b`, because a limb solved at exactly
    // full extension has a singular knee and the angle either side of it is arbitrarily sensitive. A degree
    // of residual fold at full stretch is a real leg; a solver that locks is one that snaps.
    const straight = limbChain(a, b, a + b, 0, -1);
    try std.testing.expect(@abs(straight.upper) < 3.0);
    try std.testing.expect(@abs(straight.lower) < 4.0);
    // Drawn up short, the middle joint has to fold — and the two signs are opposite, which is the fore/hind
    // difference the whole silhouette rests on.
    const fore = limbChain(a, b, 0.55, 0.05, -1);
    const hind = limbChain(a, b, 0.55, 0.05, 1);
    try std.testing.expect(fore.lower > 0); // elbow back…
    try std.testing.expect(hind.lower < 0); // …stifle forward
    try std.testing.expect(@abs(fore.lower) > 5.0);
}
