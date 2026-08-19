const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const ASH = art.ASH;
const ASH_DK = art.ASH_DK;
const ASH_LT = art.ASH_LT;
const BARK_DK = art.BARK_DK;
const CLIFF_LT = art.CLIFF_LT;
const CLIFF_ROCK = art.CLIFF_ROCK;
const COAL = art.COAL;
const IRON = art.IRON;
const STEEL = art.STEEL;
const WATER_DEEP = art.WATER_DEEP;
const WATER_MID = art.WATER_MID;
const WATER_MUD = art.WATER_MUD;
const WATER_SHALLOW = art.WATER_SHALLOW;
const flameInto = art.flameInto;



pub fn torchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9001);
    b.setMat(.steel);
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 3.0 + 0.4;
        b.addCapsule(v3(0, 0.30, 0), v3(mathx.cosf(a) * 0.34, 0.015, mathx.sinf(a) * 0.34), 0.045, 0.03, 5, IRON);
    }
    b.addCapsule(v3(0, 0.12, 0), v3(rng.signed() * 0.04, 1.72, rng.signed() * 0.04), 0.055, 0.042, 6, IRON); // shaft
    var u: i32 = 0;
    while (u < 4) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 4.0;
        b.addCapsule(v3(mathx.cosf(a) * 0.07, 1.68, mathx.sinf(a) * 0.07), v3(mathx.cosf(a) * 0.17, 2.02, mathx.sinf(a) * 0.17), 0.022, 0.016, 4, IRON);
    }
    b.addCylinder(v3(0, 1.74, 0), v3(0, 1.79, 0), 0.115, 0.115, 8, IRON);
    b.addCylinder(v3(0, 1.96, 0), v3(0, 2.00, 0), 0.165, 0.165, 8, IRON);
    b.setMat(.wood);
    b.addBlob(v3(0, 1.82, 0), v3(0.11, 0.10, 0.11), 3, 6, BARK_DK); // the pitch-soaked bundle
    flameInto(&b, &rng, 0, 1.90, 0, 1.0);
    return b.toModel(shader);
}

pub fn brazierMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9002);
    b.setMat(.steel);
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 3.0 + 0.7;
        b.addCapsule(v3(mathx.cosf(a) * 0.44, 0.02, mathx.sinf(a) * 0.44), v3(mathx.cosf(a) * 0.16, 0.88, mathx.sinf(a) * 0.16), 0.055, 0.04, 5, IRON);
        b.addCapsule(v3(mathx.cosf(a) * 0.30, 0.42, mathx.sinf(a) * 0.30), v3(mathx.cosf(a + 2.09) * 0.30, 0.42, mathx.sinf(a + 2.09) * 0.30), 0.022, 0.022, 4, IRON); // cross-brace
    }
    b.addCylinder(v3(0, 0.86, 0), v3(0, 1.04, 0), 0.34, 0.54, 10, IRON); // the bowl
    b.addCylinder(v3(0, 1.02, 0), v3(0, 1.08, 0), 0.55, 0.55, 10, STEEL); // rolled rim
    b.addDome(v3(0, 0.86, 0), v3(0, -1, 0), 0.34, 10, IRON); // closes the bowl's underside
    b.setMat(.plain);
    b.addBlob(v3(0, 1.00, 0), v3(0.44, 0.10, 0.44), 3, 8, COAL); // banked coals
    flameInto(&b, &rng, 0, 1.06, 0, 1.45);
    flameInto(&b, &rng, 0.16, 1.02, -0.12, 0.85); // a second tongue off-centre — fire is not symmetric
    return b.toModel(shader);
}

/// THE HEARTH BOTH CAMPFIRES SHARE: the stone ring and the crossed logs, off ONE seed, so the lit fire
/// and the dead one are recognisably the SAME fire at two different hours rather than two props.
fn hearthInto(b: *Builder, rng: *mathx.Rng, cold: bool) void {
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        if (i == 3) continue;
        const kicked = i == 6;
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / 9.0 + rng.signed() * 0.22;
        const d = if (kicked) rng.range(0.95, 1.15) else rng.range(0.48, 0.68);
        const r = rng.range(0.10, 0.26);
        b.addBlob(v3(mathx.cosf(a) * d, r * (if (kicked) @as(f32, 0.55) else 0.72), mathx.sinf(a) * d), v3(r, r * rng.range(0.6, 0.95), r * rng.range(0.9, 1.3)), 4, 8, if (rng.float() < 0.4) CLIFF_LT else CLIFF_ROCK);
    }
    b.setMat(.wood);
    var l: i32 = 0;
    while (l < 4) : (l += 1) {
        const a = rng.angle();
        const lift = rng.range(0.10, 0.30);
        // DRAWN UNCONDITIONALLY. `cold or rng.float() < 0.5` SHORT-CIRCUITS, so the cold hearth would
        // pull one fewer number per log and every stone after it would land somewhere else — which is
        // the one thing the shared seed exists to prevent.
        const charred = rng.float() < 0.5;
        b.addCapsule(
            v3(mathx.cosf(a) * 0.55, 0.10, mathx.sinf(a) * 0.55),
            v3(mathx.cosf(a + 3.0) * 0.30, if (cold) lift * 0.62 else lift, mathx.sinf(a + 3.0) * 0.30),
            0.085,
            0.06,
            5,
            // Burnt out, they are ALL char; still burning, half of them are.
            if (cold or charred) BARK_DK else IRON,
        );
    }
}

pub fn campfireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9003);
    hearthInto(&b, &rng, false);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.06, 0), v3(0.34, 0.06, 0.34), 3, 7, COAL); // the ember bed
    flameInto(&b, &rng, 0, 0.10, 0, 1.15);
    flameInto(&b, &rng, -0.13, 0.08, 0.10, 0.7);
    // **A FIRE YOU CAN SIT AT HAS A GUITAR AGAINST A ROCK** (owner: "they all should") — the bonfire's own
    // arrangement, and the reason it belongs on this row and not the dead one is `rest.isRestKind`: what the
    // instrument is FOR is the sitting, and nobody sits at a cold hearth. Drawn AFTER the flames so the ember
    // bed's `.plain` run is not broken in two by a material swap in the middle of it.
    art.guitarRockInto(&b, &rng, GUITAR_CX, GUITAR_CZ);
    return b.toModel(shader);
}

/// Where this camp's rock and guitar sit, in the campfire's own local frame — read by BOTH meshes, exactly as
/// the bonfire's are, so the instrument cannot drift off the rock. **Further out than the bonfire's**: this
/// hearth's kicked stone reaches 1.15 m, so a guitar at the bonfire's 1.62 m radius would be standing in it.
const GUITAR_CX: f32 = -1.44;
const GUITAR_CZ: f32 = 0.98;
const GUITAR_YAW: f32 = -1.56;
/// …and SMALLER than the bonfire's 1.5. A camp you pitch anywhere is a smaller stage than a lit landmark, and
/// at the bonfire's scale the instrument was taller than the ring of stones it sat beside.
const GUITAR_S: f32 = 1.18;

/// THE CAMPFIRE'S GUITAR, as its `stow`: a second mesh that stops being drawn the moment the hero picks the
/// instrument up (`env.stowed`), which is the same contract the bonfire's has.
pub fn campfireGuitarMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    art.guitarLeaningInto(&b, GUITAR_CX, GUITAR_CZ, GUITAR_YAW, GUITAR_S);
    return b.toModel(shader);
}

// ── THE ITEM PICKUP — ER's glowing thing on the ground ────────────────────────────────────────────────
//
// **IT SAYS "SOMETHING IS HERE" FROM ACROSS A FIELD AND NOTHING ELSE.** Elden Ring's own: a wisp of light
// standing on the ground that you walk into and press. It carries 1+ items like a chest does (`Op.loot`) and
// is deliberately NOT the items' own shapes — thirty item kinds would be thirty world meshes, and the glow
// exists to read at a distance where a dropped dirk is four pixels.
const GLOW_EMISSIVE: u8 = 22;
const GLOW_HOT = mathx.rgba(240, 236, 212, GLOW_EMISSIVE); // the core — blows out to near-white
const GLOW = mathx.rgba(204, 200, 166, GLOW_EMISSIVE); // the wisp itself
const GLOW_DIM = mathx.rgba(150, 146, 112, GLOW_EMISSIVE); // where it thins out at the top
/// How tall the wisp stands. Chest-high on the hero would make it a landmark; ankle-high hides it in grass.
pub const PICKUP_H: f32 = 0.62;
/// **AND IT IS A WISP, NOT A POST.** The first pass ran 0.048 of radius the whole way up and read as a bollard
/// — the shape said "solid thing" and no amount of brightness argues with a silhouette. It is thin at the foot,
/// thinner still at the head, and most of what the eye finds is the CORE and the motes.
const GLOW_R0: f32 = 0.022;
const GLOW_R1: f32 = 0.007;

/// **THE PILLAR: A SHAFT OF LIGHT STANDING IN THE AIR OVER IT** (owner's call). What the wisp cannot do is say
/// "here" from behind a rock or across a rise, and a taller wisp would only be the bollard again — so the thing
/// that carries the distance is a column you can see THROUGH.
const PILLAR_H: f32 = 1.48;
const PILLAR_R0: f32 = 0.105;
const PILLAR_R1: f32 = 0.048;
/// **THE ALPHA IS SOLVED AGAINST THE SHADER'S OWN STEP, NOT CHOSEN.** `outA` lerps TIP→CORE across
/// `smoothstep(0.62, 0.90, emis)` and `emis = 1 - a/255`, so the translucent end wants `emis <= 0.62`, i.e.
/// any `a >= 97`.
///
/// **AND IT FADES OUT AS IT GOES UP** (owner's call). Both ends used to sit on one alpha, so only the COLOUR
/// dimmed and the shaft was uniformly `FLAME_A_TIP` from foot to head — a column of even translucency, which
/// reads as a cut-off cylinder rather than as light dispersing. Since the shader FLOORS opacity at the tip
/// value, the only way to get a gradient is to make the FOOT more solid, so the foot is solved and the head
/// is left on the floor: `a = 63` → `emis = 0.753` → `outA ≈ 0.62`, easing to the tip's 0.42 by the top. It
/// is deliberately short of `FLAME_A_CORE` (0.86) — you still see THROUGH the thing, which is the whole of
/// what makes it a shaft of light and not a post.
const PILLAR_A_FOOT: u8 = 63;
const PILLAR_A_HEAD: u8 = 104;
const PILLAR = mathx.rgba(212, 208, 176, PILLAR_A_FOOT);
const PILLAR_TOP = mathx.rgba(150, 148, 118, PILLAR_A_HEAD); // it dies out upward rather than ending on a rim

/// The `a` at which `emis` reaches the shader's own translucent floor — `emis = 1 - a/255 <= 0.62`.
const FLAME_TIP_A: u8 = 97;
comptime {
    // **THE FADE'S DIRECTION IS THE ONE THING THAT CAN BE WRITTEN BACKWARDS AND STILL COMPILE.** Alpha is the
    // EMISSIVE channel and LOWER is more self-lit, so the SOLID end of a shaft of light is the SMALLER number
    // — put these two the other way round and the pillar fades out at the bottom, which reads as a column
    // hanging in the air off nothing.
    std.debug.assert(PILLAR_A_FOOT < PILLAR_A_HEAD);
    // …and the head has to actually REACH the floor, or the top is merely dimmer rather than thinner.
    std.debug.assert(PILLAR_A_HEAD >= FLAME_TIP_A);
    // …while the foot stays clear of it, or there is no gradient at all — which is what both ends sharing one
    // alpha was.
    std.debug.assert(PILLAR_A_FOOT < FLAME_TIP_A);
}
/// How far above the ground the whole thing reaches — what `props.INFO` has to declare as its `top`, or the
/// culler measures the prop by its wisp and pops the pillar out at the screen edge.
pub const PICKUP_TOP: f32 = PILLAR_H + 0.10;

pub fn pickupMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9007);
    // **`.plain`, WHICH IS WHAT THE SOULS DROP'S OWN GOLD USES.** `.ember` is the bonfire's tiny motes and it
    // came back INVISIBLE at this size in both the world frame and the object viewer; `.plain` with a low vertex
    // alpha is the emissive path the drop is already solved against, and it is the one proven to arrive.
    b.setMat(.plain);
    // **THE CORE IS THE READ** — a bright ball just off the earth, and it is the thing the eye finds from
    // across a field. Everything above it is decoration on that.
    b.addBlob(v3(0, 0.085, 0), v3(0.062, 0.072, 0.062), 4, 10, GLOW_HOT);
    b.addBlob(v3(0, 0.032, 0), v3(0.088, 0.030, 0.084), 3, 10, GLOW); // …and the light lying on the ground
    // The wisp: a thin tapering thread, LEANING and kinked, because nothing here is straight. One curl applied
    // every segment (the staff's law) so it rises rather than wandering.
    var prev = v3(0, 0.115, 0);
    var lean: f32 = 0;
    var i: i32 = 0;
    const SEGS: i32 = 6;
    const SEGF: f32 = @floatFromInt(SEGS);
    while (i < SEGS) : (i += 1) {
        lean += 0.10;
        const f = @as(f32, @floatFromInt(i)) / SEGF;
        const next = v3(
            prev.x + mathx.sinf(lean) * 0.026 + rng.signed() * 0.007,
            prev.y + PICKUP_H / SEGF,
            prev.z + mathx.cosf(lean * 0.6) * 0.010 + rng.signed() * 0.007,
        );
        const ra = mathx.lerpF(GLOW_R0, GLOW_R1, f) * rng.range(0.88, 1.12);
        const rb = mathx.lerpF(GLOW_R0, GLOW_R1, f + 1.0 / SEGF);
        b.addCapsule(prev, next, ra, rb, 6, if (f < 0.5) GLOW else GLOW_DIM);
        prev = next;
    }
    // …and it ENDS BLUNT, not in a needle: the dead-wood law, on light.
    b.addBlob(v3(prev.x, prev.y + 0.008, prev.z), v3(0.016, 0.020, 0.016), 3, 7, GLOW_HOT);
    // MOTES HANGING ROUND IT at their own heights and sizes — the other half of "a glow", and asymmetric, or
    // the whole thing is a lamp on a post. **THEY GO ALL THE WAY UP THE PILLAR, not just round the wisp**
    // (owner: maybe some motes): the drift is what says the column is made of the same stuff. Off a SEEDED
    // rng rather than a table, so the count is one number and not a hand-written row per mote.
    var m: i32 = 0;
    while (m < 14) : (m += 1) {
        const f = @as(f32, @floatFromInt(m)) / 14.0;
        // Higher up they are FEWER, SMALLER and DIMMER — the shaft thins into the air rather than stopping.
        const h = mathx.lerpF(0.10, PILLAR_H * 0.94, f * f) + rng.signed() * 0.05;
        const r = mathx.lerpF(0.027, 0.009, f) * rng.range(0.7, 1.25);
        // Out of the axis by more than the pillar's own radius at that height, or they hide inside it.
        const a = rng.angle();
        const d = mathx.lerpF(PILLAR_R0, PILLAR_R1, f) + rng.range(0.02, 0.10);
        b.addBlob(v3(mathx.cosf(a) * d, h, mathx.sinf(a) * d), v3(r, r * 1.3, r), 3, 6, if (f < 0.30) GLOW_HOT else if (f < 0.68) GLOW else GLOW_DIM);
    }

    // **THE PILLAR LAST**, because `.flame` and `setAnimY` are both sticky on the Builder and this is the only
    // run that wants either — set once at the end, handed back at the end, and nothing above it is touched.
    b.setMat(.flame);
    b.setAnimY(0);
    var prevP = v3(0, 0.06, 0);
    var s: i32 = 0;
    // **NINE, NOT FIVE.** A capsule carries ONE colour, so the segment count IS the resolution of the fade —
    // at five the shaft went up in five flat BANDS, which is a stack of tubes rather than light thinning out.
    const PSEGS: i32 = 9;
    const PSEGF: f32 = @floatFromInt(PSEGS);
    while (s < PSEGS) : (s += 1) {
        const f = @as(f32, @floatFromInt(s)) / PSEGF;
        // A LEAN, not a plumb line: the wabi-sabi law, and a perfectly vertical shaft reads as a UI decal
        // standing in the world. Small enough that it is still obviously upright.
        const nextP = v3(
            prevP.x + rng.signed() * 0.016,
            prevP.y + PILLAR_H / PSEGF,
            prevP.z + rng.signed() * 0.016,
        );
        // **THE COLOUR IS THE SEGMENT'S MIDDLE, EASED.** Taken at its FOOT the last segment sampled 0.8 and the
        // head never reached the top colour at all — the shaft simply stopped, one band short of gone. And the
        // ease is what makes it a DISPERSAL rather than a ramp: it holds near full through the lower third,
        // where a shaft of light is still a shaft, then gives out over the top — reaching the shader's own
        // translucent floor a little before the tip, so the head goes to nothing instead of ending on a rim.
        const fm = (f + 0.5 / PSEGF);
        const t = fm * @sqrt(fm);
        b.addCapsule(
            prevP,
            nextP,
            mathx.lerpF(PILLAR_R0, PILLAR_R1, f),
            mathx.lerpF(PILLAR_R0, PILLAR_R1, f + 1.0 / PSEGF),
            7,
            mathx.lerpColor(PILLAR, PILLAR_TOP, t),
        );
        prevP = nextP;
    }
    b.setAnimY(0);
    return b.toModel(shader);
}

/// THE SAME FIRE, DAYS LATER: no flame, no embers, no light — a cold drift of ash in a ring of stones
/// with the logs collapsed into it. It is a piece of DRESSING and nothing more, which is exactly the
/// difference between it and the one above (see `props.INFO`: this row carries no `light`).
pub fn deadCampfireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9003); // …the SAME seed: it is the same ring of stones
    hearthInto(&b, &rng, true);
    b.setMat(.stone);
    b.addBlob(v3(rng.signed() * 0.06, 0.035, rng.signed() * 0.06), v3(0.36, 0.035, 0.33), 3, 8, ASH);
    b.addBlob(v3(0.13, 0.052, -0.08), v3(0.17, 0.028, 0.15), 3, 7, ASH_LT); // raked over, paler
    b.addBlob(v3(-0.16, 0.030, 0.14), v3(0.20, 0.022, 0.17), 3, 7, ASH_DK); // trodden, or rained on
    b.setMat(.wood);
    var e: i32 = 0;
    while (e < 3) : (e += 1) {
        const a = rng.angle();
        b.addCapsule(
            v3(mathx.cosf(a) * 0.20, 0.055, mathx.sinf(a) * 0.20),
            v3(mathx.cosf(a) * rng.range(0.44, 0.60), 0.075, mathx.sinf(a) * rng.range(0.44, 0.60)),
            0.052,
            0.040,
            5,
            BARK_DK,
        );
    }
    return b.toModel(shader);
}

pub fn waterMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(5555);
    const SEG = 30;
    const RINGS = 5;
    const Y = 0.055; // a hair over env.GROUND_Y — you wade in ankle-deep
    const MUD_Y = 0.030;
    var rad: [SEG]f32 = undefined;
    for (&rad) |*r| r.* = rng.range(0.78, 1.0);
    var smooth: [SEG]f32 = undefined;
    for (0..SEG) |i| {
        const a = rad[(i + SEG - 1) % SEG];
        const c = rad[i];
        const d = rad[(i + 1) % SEG];
        smooth[i] = (a + 2 * c + d) * 0.25;
    }
    const band = struct {
        fn go(bb: *Builder, w: *const [SEG]f32, r0: f32, r1: f32, y: f32, col: rl.Color) void {
            var i: usize = 0;
            while (i < SEG) : (i += 1) {
                const j = (i + 1) % SEG;
                const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, SEG);
                const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, SEG);
                const at = struct {
                    fn p(ang: f32, r: f32, ww: f32, yy: f32) rl.Vector3 {
                        return v3(mathx.cosf(ang) * r * ww, yy, mathx.sinf(ang) * r * ww);
                    }
                }.p;
                const w0 = if (r0 <= 0.001) 1.0 else w[i];
                const w1 = if (r0 <= 0.001) 1.0 else w[j];
                bb.quad(at(a0, r0, w0, y), at(a1, r0, w1, y), at(a1, r1, w[j], y), at(a0, r1, w[i], y), v3(0, 1, 0), col);
            }
        }
    }.go;

    b.setMat(.stone);
    band(&b, &smooth, 12.4, 14.3, MUD_Y, WATER_MUD);

    b.setMat(.water);
    const ringT = [RINGS + 1]f32{ 0.0, 0.30, 0.55, 0.75, 0.90, 1.0 };
    const ringC = [RINGS + 1]rl.Color{ WATER_DEEP, WATER_DEEP, WATER_DEEP, WATER_MID, WATER_MID, WATER_SHALLOW };
    var ring: usize = 0;
    while (ring < RINGS) : (ring += 1) {
        band(&b, &smooth, 13.0 * ringT[ring], 13.0 * ringT[ring + 1], Y, mathx.lerpColor(ringC[ring], ringC[ring + 1], 0.5));
    }
    return b.toModel(shader);
}

