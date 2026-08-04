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
    // The basket: four uprights curving out, plus two hoops.
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
    // The ash drift, and it is not a disc: rain and wind have pulled it out one side of the ring.
    b.addBlob(v3(rng.signed() * 0.06, 0.035, rng.signed() * 0.06), v3(0.36, 0.035, 0.33), 3, 8, ASH);
    b.addBlob(v3(0.13, 0.052, -0.08), v3(0.17, 0.028, 0.15), 3, 7, ASH_LT); // raked over, paler
    b.addBlob(v3(-0.16, 0.030, 0.14), v3(0.20, 0.022, 0.17), 3, 7, ASH_DK); // trodden, or rained on
    // …and the ends of the logs that did not burn, sticking out of it.
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
    // A flat annulus of `SEG` quads between two radii, at height `y`.
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

