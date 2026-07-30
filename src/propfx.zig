// ── PROPS: FIRE + WATER ── the two surfaces that MOVE. Both are here because both are animated by
// the renderer rather than by their geometry: a flame's tongues writhe on the vertex shader's
// `animY` channel and burn through shadow and haze as EMISSIVE geometry (vertex alpha < 255), and
// the tarn's sheet is flat — every ripple you see is the water material's normal (gfx.waterNormal).
//
// The fires also each carry a gfx.Light (see INFO): the geometry is the flame, the light is what
// puts that fire on the walls, the floor and the hero. The flame builder itself is shared with the
// grace ember, so it lives in propart.zig.
const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
// The shared vocabulary this file draws on, aliased so a mesh body still reads as a recipe
// (`art.STONE_DK` in front of every colour buries the shape in namespace). GENERATED from what
// the file actually references — the list IS the dependency, so it is worth reading.
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

// ── FIRE ── each of these carries a gfx.Light (see INFO). The flame itself is EMISSIVE
// geometry (vertex alpha < 255) so it burns through shadow and haze; the light is what puts
// that fire onto the walls, the floor and the hero.


// A standing iron TORCH: three splayed feet, a twisted shaft, a cage of iron straps holding
// the pitch head, and the flame above it. Tall enough to light a room from the wall.
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

// A BRAZIER: a wide iron bowl on three raking legs, banked coals under a broad flame — the
// biggest of the fires, for a courtyard or a gateway.
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

// A CAMPFIRE: a ring of hearth stones, crossed half-burnt logs, embers between them, and a
// low flame. Somebody camped in the wood and did not come back for it.
pub fn campfireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9003);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        // One stone MISSING and one kicked out of the ring — a complete even circle of
        // same-sized hexagonal gumdrops read as placed by a compass. More sides so each
        // stone reads round, and a wider size spread so no two match.
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
        b.addCapsule(
            v3(mathx.cosf(a) * 0.55, 0.10, mathx.sinf(a) * 0.55),
            v3(mathx.cosf(a + 3.0) * 0.30, lift, mathx.sinf(a + 3.0) * 0.30),
            0.085,
            0.06,
            5,
            if (rng.float() < 0.5) BARK_DK else IRON, // half of them burnt to char
        );
    }
    b.setMat(.plain);
    b.addBlob(v3(0, 0.06, 0), v3(0.34, 0.06, 0.34), 3, 7, COAL); // the ember bed
    flameInto(&b, &rng, 0, 0.10, 0, 1.15);
    flameInto(&b, &rng, -0.13, 0.08, 0.10, 0.7);
    return b.toModel(shader);
}

// ── WATER ── the tarn's surface: a flat irregular sheet. Everything that makes it read as
// water is in the shader (gfx.Mat.water — animated ripple normals, the shattered sun streak,
// a sky reflection at grazing angles); the MESH only supplies the outline and the silt
// gradient, dark in the middle and pale where it shallows out at the rim.
//
// SCALE 1 is a ~13 m radius pool; env scales instances up for the big tarn.
pub fn waterMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(5555);
    const SEG = 30;
    const RINGS = 5;
    const Y = 0.055; // a hair over env.GROUND_Y — you wade in ankle-deep
    const MUD_Y = 0.030; // …and the wet margin sits BETWEEN the two, so nothing z-fights
    // An irregular shoreline: per-spoke radius wobble, smoothed by averaging neighbours so
    // the outline undulates in bays instead of jittering vertex to vertex.
    var rad: [SEG]f32 = undefined;
    for (&rad) |*r| r.* = rng.range(0.78, 1.0);
    var smooth: [SEG]f32 = undefined;
    for (0..SEG) |i| {
        const a = rad[(i + SEG - 1) % SEG];
        const c = rad[i];
        const d = rad[(i + 1) % SEG];
        smooth[i] = (a + 2 * c + d) * 0.25;
    }
    // A flat annulus of `SEG` quads between two radii, at height `y`. Used for the water sheet
    // AND for the wet mud margin under its rim.
    //
    // WINDING: inner@a0 → inner@a1 → outer@a1 → outer@a0, which is the order whose right-hand
    // normal points UP. Sweeping outward first instead (the obvious way to write it) faces the
    // whole sheet at the LAKEBED, raylib culls it, and the tarn is simply not there — which is
    // exactly what the first version of this did.
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
                // The innermost ring collapses to the centre, so its quad is a triangle (the
                // duplicated corner contributes a zero-area tri — harmless, and it keeps ONE
                // code path for the whole sheet).
                const w0 = if (r0 <= 0.001) 1.0 else w[i];
                const w1 = if (r0 <= 0.001) 1.0 else w[j];
                bb.quad(at(a0, r0, w0, y), at(a1, r0, w1, y), at(a1, r1, w[j], y), at(a0, r1, w[i], y), v3(0, 1, 0), col);
            }
        }
    }.go;

    // The WET MARGIN first, a little wider than the sheet and a little lower: dark saturated
    // mud that the water's edge dies into, so the shoreline isn't a hard line ruled across dry
    // grass. Stone material, not water — it doesn't ripple, it's just soaked.
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

