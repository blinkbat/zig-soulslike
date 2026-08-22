const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
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
    b.addCapsule(v3(0, 0.12, 0), v3(rng.signed() * 0.04, 1.72, rng.signed() * 0.04), 0.055, 0.042, 6, IRON);
    var u: i32 = 0;
    while (u < 4) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 4.0;
        b.addCapsule(v3(mathx.cosf(a) * 0.07, 1.68, mathx.sinf(a) * 0.07), v3(mathx.cosf(a) * 0.17, 2.02, mathx.sinf(a) * 0.17), 0.022, 0.016, 4, IRON);
    }
    b.addCylinder(v3(0, 1.74, 0), v3(0, 1.79, 0), 0.115, 0.115, 8, IRON);
    b.addCylinder(v3(0, 1.96, 0), v3(0, 2.00, 0), 0.165, 0.165, 8, IRON);
    b.setMat(.wood);
    b.addBlob(v3(0, 1.82, 0), v3(0.11, 0.10, 0.11), 3, 6, BARK_DK);
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
        b.addCapsule(v3(mathx.cosf(a) * 0.30, 0.42, mathx.sinf(a) * 0.30), v3(mathx.cosf(a + 2.09) * 0.30, 0.42, mathx.sinf(a + 2.09) * 0.30), 0.022, 0.022, 4, IRON);
    }
    b.addCylinder(v3(0, 0.86, 0), v3(0, 1.04, 0), 0.34, 0.54, 10, IRON);
    b.addCylinder(v3(0, 1.02, 0), v3(0, 1.08, 0), 0.55, 0.55, 10, STEEL);
    b.addDome(v3(0, 0.86, 0), v3(0, -1, 0), 0.34, 10, IRON);
    b.setMat(.plain);
    b.addBlob(v3(0, 1.00, 0), v3(0.44, 0.10, 0.44), 3, 8, COAL);
    flameInto(&b, &rng, 0, 1.06, 0, 1.45);
    flameInto(&b, &rng, 0.16, 1.02, -0.12, 0.85);
    return b.toModel(shader);
}

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
        // DRAWN UNCONDITIONALLY. `cold or rng.float() < 0.5` SHORT-CIRCUITS, so the cold hearth would pull one fewer number per log and every stone after it would land somewhere else.
        const charred = rng.float() < 0.5;
        b.addCapsule(
            v3(mathx.cosf(a) * 0.55, 0.10, mathx.sinf(a) * 0.55),
            v3(mathx.cosf(a + 3.0) * 0.30, if (cold) lift * 0.62 else lift, mathx.sinf(a + 3.0) * 0.30),
            0.085,
            0.06,
            5,
            if (cold or charred) BARK_DK else IRON,
        );
    }
}

pub fn campfireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9003);
    hearthInto(&b, &rng, false);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.06, 0), v3(0.34, 0.06, 0.34), 3, 7, COAL);
    flameInto(&b, &rng, 0, 0.10, 0, 1.15);
    flameInto(&b, &rng, -0.13, 0.08, 0.10, 0.7);
    art.guitarRockInto(&b, &rng, GUITAR_CX, GUITAR_CZ);
    return b.toModel(shader);
}

/// Where this camp's rock and guitar sit, in the campfire's own local frame — read by BOTH meshes, so the instrument cannot drift off the rock. **Further out than the bonfire's**: this hearth's kicked stone reaches 1.15 m, so a guitar at the bonfire's 1.62 m radius would be standing in it.
const GUITAR_CX: f32 = -1.44;
const GUITAR_CZ: f32 = 0.98;
const GUITAR_YAW: f32 = -1.56;
/// …and SMALLER than the bonfire's 1.5. At the bonfire's scale the instrument was taller than the ring of stones it sat beside.
const GUITAR_S: f32 = 1.18;

pub fn campfireGuitarMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    art.guitarLeaningInto(&b, GUITAR_CX, GUITAR_CZ, GUITAR_YAW, GUITAR_S);
    return b.toModel(shader);
}

const GLOW_EMISSIVE: u8 = 22;
const GLOW_HOT = mathx.rgba(240, 236, 212, GLOW_EMISSIVE);
const GLOW = mathx.rgba(204, 200, 166, GLOW_EMISSIVE);
const GLOW_DIM = mathx.rgba(150, 146, 112, GLOW_EMISSIVE);
pub const PICKUP_H: f32 = 0.62;
/// **AND IT IS A WISP, NOT A POST.** The first pass ran 0.048 of radius the whole way up and read as a bollard — the shape said "solid thing" and no amount of brightness argues with a silhouette.
const GLOW_R0: f32 = 0.022;
const GLOW_R1: f32 = 0.007;

/// **THE PILLAR: A SHAFT OF LIGHT STANDING IN THE AIR OVER IT** (owner's call). What the wisp cannot do is say "here" from behind a rock, and a taller wisp would only be the bollard again — so the thing that carries the distance is a column you can see THROUGH.
const PILLAR_H: f32 = 1.48;
const PILLAR_R0: f32 = 0.105;
const PILLAR_R1: f32 = 0.048;
/// **THE ALPHA IS SOLVED AGAINST THE SHADER'S OWN STEP, NOT CHOSEN.** `outA` lerps TIP→CORE across
/// `smoothstep(0.62, 0.90, emis)` with `emis = 1 - a/255`, so the translucent end wants `emis <= 0.62`, any
/// `a >= 97`. **AND IT FADES OUT AS IT GOES UP** (owner's call): the shader FLOORS opacity at the tip value, so
/// the gradient comes from a more solid FOOT — `a = 63` → `emis = 0.753` → `outA ≈ 0.62`, easing to the tip's 0.42.
const PILLAR_A_FOOT: u8 = 63;
const PILLAR_A_HEAD: u8 = 104;
const PILLAR = mathx.rgba(212, 208, 176, PILLAR_A_FOOT);
const PILLAR_TOP = mathx.rgba(150, 148, 118, PILLAR_A_HEAD);

/// The `a` at which `emis` reaches the shader's own translucent floor — `emis = 1 - a/255 <= 0.62`.
const FLAME_TIP_A: u8 = 97;
comptime {
    std.debug.assert(PILLAR_A_FOOT < PILLAR_A_HEAD);
    std.debug.assert(PILLAR_A_HEAD >= FLAME_TIP_A);
    std.debug.assert(PILLAR_A_FOOT < FLAME_TIP_A);
}
pub const PICKUP_TOP: f32 = PILLAR_H + 0.10;

pub fn pickupMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9007);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.085, 0), v3(0.062, 0.072, 0.062), 4, 10, GLOW_HOT);
    b.addBlob(v3(0, 0.032, 0), v3(0.088, 0.030, 0.084), 3, 10, GLOW);
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
    b.addBlob(v3(prev.x, prev.y + 0.008, prev.z), v3(0.016, 0.020, 0.016), 3, 7, GLOW_HOT);
    var m: i32 = 0;
    while (m < 14) : (m += 1) {
        const f = @as(f32, @floatFromInt(m)) / 14.0;
        const h = mathx.lerpF(0.10, PILLAR_H * 0.94, f * f) + rng.signed() * 0.05;
        const r = mathx.lerpF(0.027, 0.009, f) * rng.range(0.7, 1.25);
        const a = rng.angle();
        const d = mathx.lerpF(PILLAR_R0, PILLAR_R1, f) + rng.range(0.02, 0.10);
        b.addBlob(v3(mathx.cosf(a) * d, h, mathx.sinf(a) * d), v3(r, r * 1.3, r), 3, 6, if (f < 0.30) GLOW_HOT else if (f < 0.68) GLOW else GLOW_DIM);
    }

    b.setMat(.flame);
    b.setAnimY(0);
    var prevP = v3(0, 0.06, 0);
    var s: i32 = 0;
    const PSEGS: i32 = 9;
    const PSEGF: f32 = @floatFromInt(PSEGS);
    while (s < PSEGS) : (s += 1) {
        const f = @as(f32, @floatFromInt(s)) / PSEGF;
        const nextP = v3(
            prevP.x + rng.signed() * 0.016,
            prevP.y + PILLAR_H / PSEGF,
            prevP.z + rng.signed() * 0.016,
        );
        // **THE SEGMENT'S MIDDLE, EASED.** Taken at its FOOT the last segment sampled 0.8 and the head never reached the top colour — the shaft stopped one band short of gone. The ease holds near full through the lower third and reaches the shader's translucent floor before the tip.
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

pub fn deadCampfireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9003);
    hearthInto(&b, &rng, true);
    b.setMat(.stone);
    b.addBlob(v3(rng.signed() * 0.06, 0.035, rng.signed() * 0.06), v3(0.36, 0.035, 0.33), 3, 8, ASH);
    b.addBlob(v3(0.13, 0.052, -0.08), v3(0.17, 0.028, 0.15), 3, 7, ASH_LT);
    b.addBlob(v3(-0.16, 0.030, 0.14), v3(0.20, 0.022, 0.17), 3, 7, ASH_DK);
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
    const Y = 0.055;
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


// Authored at the size of a real door (`FOG_W` x `FOG_H`), so the editor's `scale` reads as a multiple of one.
//
// **IT IS A VEIL, NOT A PROP MESH** (`props.INFO`): laid down AFTER everything opaque, or its own depth punches a hole in what stands behind it.
pub const FOG_W: f32 = 3.4;
pub const FOG_H: f32 = 4.2;
/// Half-thickness of the WARD behind the sheet (`props.Info.ward`) — not of the curtain, whose three panes span 0.22 m. A push-out is a position test, so a wall thinner than one frame of travel is one a charge steps clean through: the knight's 12.4 m/s covers 0.21 m at 60 fps and 0.41 m at 30.
pub const FOG_WARD_R: f32 = 0.40;
// THE UNDULATION IS PER-VERTEX, so the grid IS the amplitude it can carry: at 10x9 the roll had two and a half
// cells to bend through and read as a flag.
//
// **AND THIS IS THE EXPENSIVE PROP IN THE GAME, ON PURPOSE**: 16x14x5x2 = 2240 quads, 4480 tris (it was 1080),
// five ALPHA-BLENDED layers over three value-noise octaves, on a sheet that fills the frame. If it has to come down, the sheet COUNT is the dial — it multiplies fill, where the grid only costs vertices.
const FOG_COLS: i32 = 16;
const FOG_ROWS: i32 = 14;
const FOG_SHEETS: i32 = 5; // depth: five curtains a hand apart, so the billow has something to move THROUGH
// COLD AND HEAVY: everything outdoors here is warm, so the one thing between you and a boss is the one that is
// not. **SOLVED AGAINST THE RENDER** — at (190,198,210) it measured 220,209,201 beside a cliff at 151,137,105,
// so far up the curve that the curdle and billow clipped flat. 220 → 130 wants (130/220)^2.2 = 0.314 on the
// albedo, and the BLUE is pushed past neutral because the warm key drags it back. Alpha is EMISSIVE, not opacity.
const FOG_PALE = mathx.rgba(38, 44, 58, 176);
const FOG_DEEP = mathx.rgba(20, 24, 36, 176);
/// **THE MOTES THE SHEET SHEDS AS HE CROSSES** (`hero.fogWake`), DERIVED from the curtain's own colours or a retune of the wall leaves them the wrong colour silently. A mote draws lit and the sheet translucent emissive, so the same albedo reads several times darker on the mote and the lift puts them back on one value.
const WAKE_LIFT: f32 = 0.40;
const WHITE = mathx.rgba(255, 255, 255, 255);
pub const FOG_WAKE_PALE = mathx.withAlpha(mathx.lerpColor(FOG_PALE, WHITE, WAKE_LIFT), 168);
pub const FOG_WAKE_DEEP = mathx.withAlpha(mathx.lerpColor(FOG_DEEP, WHITE, WAKE_LIFT), 148);

/// **WHAT A SHUT GATE IS TINTED** (owner: gate changes colour to signify it's closed) — a per-draw multiply on the sheet's albedo, so it is the same wall in a different light. Alpha MUST be 255: the shader reads that channel as emissive.
pub const FOG_SHUT_TINT = mathx.rgba(255, 132, 58, 255);

/// The curtain. Vertex ALPHA is left near-solid on purpose — the scene shader reads `1 - alpha` as emissive, and a fog wall lit only by the sun goes black at night. What actually fades is the OUTPUT alpha, off the height fraction this mesh writes into `animY`.
pub fn fogGateMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.fog);
    var s: i32 = 0;
    while (s < FOG_SHEETS) : (s += 1) {
        const z = (@as(f32, @floatFromInt(s)) - 0.5 * @as(f32, @floatFromInt(FOG_SHEETS - 1))) * 0.105;
        var r: i32 = 0;
        while (r < FOG_ROWS) : (r += 1) {
            const t0 = @as(f32, @floatFromInt(r)) / @as(f32, FOG_ROWS);
            const t1 = @as(f32, @floatFromInt(r + 1)) / @as(f32, FOG_ROWS);
            const y0 = t0 * FOG_H;
            const y1 = t1 * FOG_H;
            const c0 = mathx.lerpColor(FOG_PALE, FOG_DEEP, t0);
            const c1 = mathx.lerpColor(FOG_PALE, FOG_DEEP, t1);
            var c: i32 = 0;
            while (c < FOG_COLS) : (c += 1) {
                const x0 = (@as(f32, @floatFromInt(c)) / @as(f32, FOG_COLS) - 0.5) * FOG_W;
                const x1 = (@as(f32, @floatFromInt(c + 1)) / @as(f32, FOG_COLS) - 0.5) * FOG_W;
                // BOTH FACES, because a gate is walked at from both sides and a one-sided sheet vanishes the moment you turn round inside it.
                b.quadFadeAnim(v3(x0, y0, z), v3(x1, y0, z), v3(x1, y1, z), v3(x0, y1, z), v3(0, 0, 1), c0, c1, t0, t1);
                b.quadFadeAnim(v3(x1, y0, z), v3(x0, y0, z), v3(x0, y1, z), v3(x1, y1, z), v3(0, 0, -1), c0, c1, t0, t1);
            }
        }
    }
    b.setAnimY(0);
    return b.toModel(shader);
}

/// …AND THE THRESHOLD IT HANGS IN. Two worn stones at the jambs and nothing overhead: a fog gate is dropped into somebody else's archway as often as it stands on its own, and a lintel of mine would fight theirs.
pub fn fogGateStoneMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0A7E);
    b.setMat(.stone);
    for ([_]f32{ -1, 1 }) |side| {
        const x = side * FOG_W * 0.5;
        b.addBox(
            v3(x, 0.26, 0),
            v3(0.19, 0, 0),
            v3(0, 0.26, 0),
            v3(0, 0, 0.21),
            CLIFF_ROCK,
        );
        b.addBlob(v3(x, 0.52, rng.signed() * 0.03), v3(0.17, 0.10, 0.19), 3, 7, CLIFF_LT);
    }
    return b.toModel(shader);
}
