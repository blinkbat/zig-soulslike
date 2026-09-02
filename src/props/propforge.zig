const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// **THE FORGE YARD** — the smith's four pieces (`npc.zig`'s `.smith`), the way `propmarket` is the caravaneer's.
// A 0.6 m capsule of `art.TIMBER` reads at 180 on screen where the same albedo on a fence rail reads at 130: a
// large sunward face takes the full key and the gamma lift does the rest. Solved down the chain
// (screen = (albedo/255 x 1.72)^(1/2.2) x 255):
//     16 -> 93    26 -> 114    38 -> 136    58 -> 172    96 -> 210
const OAK = rgba(26, 20, 13, 255);
const OAK_LT = rgba(38, 29, 19, 255);
const OAK_DK = rgba(15, 12, 8, 255);
const MASON = rgba(26, 25, 22, 255);
const MASON_LT = rgba(38, 36, 32, 255);
const MASON_DK = rgba(15, 14, 13, 255);
const IRON = art.IRON;
const IRON_LT = rgba(38, 36, 34, 255);
const FACE = rgba(58, 62, 68, 255);
const FACE_DK = rgba(30, 32, 36, 255);
const SOOT = rgba(12, 11, 10, 255);
const LEATHER = rgba(30, 22, 15, 255);
const LEATHER_LT = rgba(44, 33, 22, 255);
const SLAG = rgba(18, 16, 14, 255);
const COAL = rgba(216, 88, 22, 52);
const COAL_HOT = rgba(250, 182, 84, 20);
const WATER = rgba(20, 27, 29, 255);

/// **`Builder.addCube` AND `addRoundBox` TAKE A FULL SIZE, NOT HALF-EXTENTS** (`gfx.zig`: `hx = size.x / 2`).
/// Authored as half-extents every box came out at half its span: the anvil's foot floated 25 mm over its own stump.
fn boxH(b: *Builder, c: rl.Vector3, half: rl.Vector3, col: rl.Color) void {
    b.addCube(c, v3(half.x * 2, half.y * 2, half.z * 2), col);
}
fn roundBoxH(b: *Builder, c: rl.Vector3, half: rl.Vector3, round: f32, segs: i32, sides: i32, col: rl.Color) void {
    b.addRoundBox(c, v3(half.x * 2, half.y * 2, half.z * 2), round, segs, sides, col);
}


pub const ANVIL_FACE: f32 = 0.98;
pub const ANVIL_TOP: f32 = ANVIL_FACE + 0.02;
pub const ANVIL_R: f32 = 0.70;
const ANVIL_LEN: f32 = 0.98;
const WAIST_H: f32 = 0.20;
const WAIST_HW: f32 = 0.130;
pub const STUMP_R: f32 = 0.370;
const STUMP_H: f32 = 0.52;

pub fn anvilMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A17);
    stumpInto(&b, &rng, STUMP_H, STUMP_R);
    anvilBodyInto(&b, STUMP_H);
    // **NO SCATTER ON THE FLOOR.** Hammer scale was authored here as sixteen 6 mm discs and came back as a
    return b.toModel(shader);
}

fn stumpInto(b: *Builder, rng: *mathx.Rng, top: f32, r: f32) void {
    b.setMat(.wood);
    b.addCylinder(v3(0, 0, 0), v3(0, top, 0), r * 1.12, r, 11, OAK);
    b.addBlob(v3(0, top - 0.012, 0), v3(r * 0.99, 0.016, r * 0.99), 3, 11, OAK);
    b.addBlob(v3(0, 0.012, 0), v3(r * 1.11, 0.016, r * 1.11), 3, 11, OAK_DK);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = r * rng.range(0.86, 1.04);
        b.addCapsule(
            v3(mathx.cosf(a) * d, rng.range(0.0, 0.06), mathx.sinf(a) * d),
            v3(mathx.cosf(a) * d * 1.06, top * rng.range(0.55, 0.98), mathx.sinf(a) * d * 1.06),
            rng.range(0.024, 0.046),
            rng.range(0.018, 0.036),
            6,
            if (rng.float() < 0.5) OAK_DK else art.BARK_OLD,
        );
    }
    b.addBlob(v3(0, top - 0.004, 0), v3(r * 0.94, 0.010, r * 0.94), 3, 11, OAK_LT);
}

fn anvilBodyInto(b: *Builder, base: f32) void {
    b.setMat(.steel);
    const halfL = ANVIL_LEN * 0.5;
    const faceY = ANVIL_FACE;
    const footTop = base + 0.100;
    const waistTop = footTop + WAIST_H;
    boxH(b, v3(0, (base + footTop) * 0.5, 0), v3(halfL * 0.62, (footTop - base) * 0.5, 0.135), IRON);
    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sz| {
            boxH(b, v3(sx * halfL * 0.56, base + 0.020, sz * 0.112), v3(0.062, 0.022, 0.036), IRON_LT);
        }
    }
    boxH(b, v3(0, (footTop + waistTop) * 0.5, 0), v3(WAIST_HW, WAIST_H * 0.5, 0.082), IRON);
    b.addBox(
        v3(0, (waistTop + faceY - 0.048) * 0.5, 0),
        v3(halfL * 0.60, 0, 0),
        v3(0, (faceY - 0.048 - waistTop) * 0.5, 0),
        v3(0, 0, 0.112),
        IRON,
    );
    boxH(b, v3(0, faceY - 0.030, 0), v3(halfL * 0.72, 0.020, 0.122), FACE_DK);
    boxH(b, v3(0, faceY - 0.006, 0), v3(halfL * 0.70, 0.008, 0.116), FACE);
    b.setMat(.plain);
    boxH(b, v3(halfL * 0.40, faceY - 0.008, 0), v3(0.024, 0.014, 0.024), SOOT);
    b.addCylinder(v3(halfL * 0.56, faceY - 0.016, 0), v3(halfL * 0.56, faceY + 0.002, 0), 0.013, 0.013, 6, SOOT);
    b.setMat(.steel);
    boxH(b, v3(-halfL * 0.80, faceY - 0.058, 0), v3(0.070, 0.028, 0.096), IRON_LT);
    b.addCylinder(v3(-halfL * 0.70, faceY - 0.040, 0), v3(-halfL * 1.36, faceY - 0.026, 0), 0.086, 0.018, 9, IRON_LT);
    b.addDome(v3(-halfL * 1.36, faceY - 0.026, 0), v3(-1, 0, 0), 0.018, 8, IRON_LT);
    boxH(b, v3(halfL * 0.84, faceY - 0.052, 0), v3(0.058, 0.032, 0.104), IRON);
}


pub const FORGE_TOP: f32 = 2.05;
pub const FORGE_R: f32 = 1.05;
const HEARTH_Y: f32 = 0.86;
const HEARTH_HW: f32 = 0.72;
const HEARTH_HD: f32 = 0.56;
pub const FORGE_LIGHT_Y: f32 = HEARTH_Y + 0.16;
pub const FORGE_LIGHT_R: f32 = 7.2;

pub fn forgeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0B6);
    // THE BLOCK: one dark mass, with the courses cut INTO its faces rather than glued onto them.
    b.setMat(.stone);
    boxH(&b, v3(0, HEARTH_Y * 0.5, 0), v3(HEARTH_HW, HEARTH_Y * 0.5, HEARTH_HD), MASON_DK);
    var course: i32 = 0;
    while (course < 4) : (course += 1) {
        const y = 0.12 + @as(f32, @floatFromInt(course)) * 0.205;
        if (y > HEARTH_Y - 0.08) break;
        var s: i32 = 0;
        while (s < 4) : (s += 1) {
            const u = (@as(f32, @floatFromInt(s)) / 3.0 - 0.5) * 2.0;
            const w = rng.range(0.150, 0.205);
            for ([_]f32{ 1, -1 }) |sz| {
                roundBoxH(&b, 
                    v3(u * HEARTH_HW * 0.72, y + rng.signed() * 0.010, sz * (HEARTH_HD - 0.025)),
                    v3(w, 0.086, 0.030),
                    0.024,
                    2,
                    6,
                    if (rng.float() < 0.25) MASON else MASON_DK,
                );
            }
        }
    }
    // THE TABLE, and a RIM rather than a wall: 0.03 m proud, so the bed inside it is visible from a standing
    boxH(&b, v3(0, HEARTH_Y + 0.022, 0), v3(HEARTH_HW + 0.04, 0.022, HEARTH_HD + 0.04), MASON);
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |d| {
        boxH(&b, 
            v3(d[0] * (HEARTH_HW - 0.02), HEARTH_Y + 0.058, d[1] * (HEARTH_HD - 0.02)),
            v3(if (d[0] == 0) HEARTH_HW + 0.03 else 0.055, 0.030, if (d[1] == 0) HEARTH_HD + 0.03 else 0.055),
            MASON_LT,
        );
    }
    b.setMat(.plain);
    b.addBlob(v3(0, HEARTH_Y + 0.048, 0), v3(HEARTH_HW * 0.70, 0.030, HEARTH_HD * 0.68), 4, 10, SLAG);
    b.setMat(.flame);
    b.setAnimY(HEARTH_Y + 0.09);
    var c: i32 = 0;
    while (c < 22) : (c += 1) {
        const a = rng.angle();
        const d = @sqrt(rng.float());
        const rr = rng.range(0.050, 0.090);
        b.addBlob(
            v3(mathx.cosf(a) * d * HEARTH_HW * 0.58, HEARTH_Y + 0.078 + (1.0 - d) * 0.040, mathx.sinf(a) * d * HEARTH_HD * 0.56),
            v3(rr, rr * 0.58, rr),
            3,
            7,
            if (d < 0.50) COAL_HOT else COAL,
        );
    }
    b.setAnimY(0);
    art.flameInto(&b, &rng, 0, HEARTH_Y + 0.115, 0, 0.62);
    b.setMat(.stone);
    b.setMat(.stone);
    const hz = -HEARTH_HD * 0.30;
    const hoodBase = HEARTH_Y + 0.52;
    b.addCylinder(v3(0, hoodBase, hz - 0.06), v3(0, HEARTH_Y + 1.02, hz - 0.26), HEARTH_HW * 0.82, 0.185, 10, MASON_DK);
    b.addCylinder(v3(0, HEARTH_Y + 0.98, hz - 0.25), v3(0, HEARTH_Y + 1.06, hz - 0.27), 0.215, 0.215, 10, MASON);
    b.addCylinder(v3(0, HEARTH_Y + 1.02, hz - 0.26), v3(0, FORGE_TOP, hz - 0.30), 0.185, 0.155, 9, MASON);
    b.addBlob(v3(0, FORGE_TOP - 0.02, hz - 0.30), v3(0.170, 0.030, 0.170), 3, 9, MASON_DK);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCylinder(
            v3(sx * HEARTH_HW * 0.74, HEARTH_Y + 0.09, -HEARTH_HD * 0.72),
            v3(sx * HEARTH_HW * 0.60, hoodBase + 0.04, hz - 0.20),
            0.052,
            0.046,
            7,
            MASON,
        );
    }
    b.setMat(.plain);
    boxH(&b, v3(0, HEARTH_Y + 0.14, hz), v3(HEARTH_HW * 0.86, 0.030, HEARTH_HD * 0.50), SOOT);

    const bx = -HEARTH_HW - 0.30;
    b.setMat(.leather);
    b.addBlob(v3(bx, HEARTH_Y - 0.18, 0.02), v3(0.115, 0.155, 0.27), 4, 9, LEATHER);
    var rib: i32 = 0;
    while (rib < 4) : (rib += 1) {
        const t = -0.11 + 0.075 * @as(f32, @floatFromInt(rib));
        b.addCylinder(v3(bx - 0.10, HEARTH_Y - 0.18 + t, -0.25), v3(bx - 0.10, HEARTH_Y - 0.18 + t, 0.29), 0.014, 0.014, 6, LEATHER_LT);
    }
    b.setMat(.wood);
    b.addBox(v3(bx - 0.02, HEARTH_Y - 0.02, 0.02), v3(0.028, 0, 0), v3(0, 0.030, 0), v3(0, 0, 0.26), OAK);
    b.addBox(v3(bx - 0.02, HEARTH_Y - 0.34, 0.02), v3(0.028, 0, 0), v3(0, 0.030, 0), v3(0, 0, 0.24), OAK_DK);
    b.addCapsule(v3(bx - 0.04, HEARTH_Y + 0.02, 0.02), v3(bx - 0.30, HEARTH_Y + 0.34, 0.02), 0.030, 0.024, 7, OAK_LT);
    b.setMat(.steel);
    b.addCylinder(v3(bx + 0.10, HEARTH_Y - 0.10, 0.02), v3(-HEARTH_HW * 0.40, HEARTH_Y + 0.04, 0.0), 0.036, 0.028, 7, IRON);
    return b.toModel(shader);
}


pub const QUENCH_TOP: f32 = 0.62;
pub const QUENCH_R: f32 = 0.92;
const QUENCH_HL: f32 = 0.72;
const QUENCH_HW: f32 = 0.185;
const LOG_R: f32 = 0.285;

pub fn quenchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x9CE7);
    const axis = QUENCH_TOP - LOG_R;
    b.setMat(.wood);
    b.addCylinder(v3(-QUENCH_HL, axis, 0), v3(QUENCH_HL, axis, 0), LOG_R, LOG_R * 0.97, 11, OAK);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCylinder(v3(sx * QUENCH_HL, axis, 0), v3(sx * (QUENCH_HL + 0.012), axis, 0), LOG_R * 0.99, LOG_R * 0.94, 11, OAK_LT);
    }
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const a = rng.range(0.4, 2.7);
        const t0 = rng.range(-0.95, 0.2);
        const t1 = t0 + rng.range(0.5, 1.4);
        b.addCapsule(
            v3(t0 * QUENCH_HL, axis - mathx.sinf(a) * LOG_R * 0.96, mathx.cosf(a) * LOG_R * 0.96),
            v3(@min(t1, 0.98) * QUENCH_HL, axis - mathx.sinf(a) * LOG_R * 0.96, mathx.cosf(a) * LOG_R * 0.96),
            rng.range(0.018, 0.034),
            rng.range(0.014, 0.028),
            5,
            if (rng.float() < 0.5) OAK_DK else art.BARK_OLD,
        );
    }
    b.setMat(.plain);
    boxH(&b, v3(0, QUENCH_TOP - 0.075, 0), v3(QUENCH_HL * 0.90, 0.085, QUENCH_HW), SOOT);
    b.setMat(.wood);
    for ([_]f32{ -1, 1 }) |sz| {
        b.addCapsule(
            v3(-QUENCH_HL * 0.94, QUENCH_TOP - 0.030, sz * (QUENCH_HW + 0.040)),
            v3(QUENCH_HL * 0.94, QUENCH_TOP - 0.030, sz * (QUENCH_HW + 0.040)),
            0.042,
            0.042,
            7,
            OAK_LT,
        );
    }
    for ([_]f32{ -1, 1 }) |sx| {
        boxH(&b, v3(sx * QUENCH_HL * 0.60, 0.055, 0), v3(0.095, 0.055, 0.24), OAK_DK);
    }
    b.setMat(.steel);
    for ([_]f32{ -0.56, 0.56 }) |t| {
        b.addCylinder(v3(t * QUENCH_HL - 0.020, axis, 0), v3(t * QUENCH_HL + 0.020, axis, 0), LOG_R * 1.03, LOG_R * 1.03, 11, IRON);
    }
    // **THE WATER, AND IT IS THE ONE GLOSS IN THE YARD** (`Mat.water`, the only real specular besides steel).
    b.setMat(.water);
    boxH(&b, v3(0, QUENCH_TOP - 0.062, 0), v3(QUENCH_HL * 0.88, 0.004, QUENCH_HW * 0.94), WATER);
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 6) : (g += 1) {
        const a = rng.angle();
        const rr = rng.range(0.040, 0.075);
        b.addBlob(v3(mathx.cosf(a) * QUENCH_HL * 0.9, rr * 0.5, mathx.sinf(a) * 0.30), v3(rr, rr * 0.6, rr), 3, 6, art.MOSS_DK);
    }
    return b.toModel(shader);
}


pub const RACK_TOP: f32 = 1.72;
pub const RACK_HW: f32 = 0.62;

pub fn toolRackMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x700D);
    b.setMat(.wood);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCapsule(v3(sx * RACK_HW, 0, 0.02), v3(sx * RACK_HW + rng.signed() * 0.02, RACK_TOP, 0), 0.062, 0.052, 8, OAK);
    }
    b.addCylinder(v3(-RACK_HW, RACK_TOP - 0.16, 0), v3(RACK_HW, RACK_TOP - 0.16, 0), 0.046, 0.046, 7, OAK_DK);
    b.addCylinder(v3(-RACK_HW, RACK_TOP * 0.40, 0.02), v3(RACK_HW, RACK_TOP * 0.40, 0.02), 0.040, 0.040, 7, OAK_DK);
    // display. **THE HEADS ARE BIG**: at 18 m a hammer head under 0.10 m is four grey pixels and says nothing.
    const Tool = enum { hammer, tongs, sledge };
    const hang = [_]struct { x: f32, drop: f32, head: f32, kind: Tool }{
        .{ .x = -0.44, .drop = 0.46, .head = 0.115, .kind = .hammer },
        .{ .x = -0.16, .drop = 0.66, .head = 0.090, .kind = .hammer },
        .{ .x = 0.08, .drop = 0.84, .head = 0.070, .kind = .tongs },
        .{ .x = 0.33, .drop = 0.56, .head = 0.135, .kind = .sledge },
        .{ .x = 0.53, .drop = 0.74, .head = 0.062, .kind = .tongs },
    };
    for (hang) |t| {
        const topY = RACK_TOP - 0.16;
        const botY = topY - t.drop;
        b.setMat(.wood);
        b.addCapsule(v3(t.x, topY, 0.01), v3(t.x + rng.signed() * 0.03, botY + t.head, 0.01), 0.024, 0.020, 6, if (rng.float() < 0.4) OAK_LT else OAK);
        b.setMat(.steel);
        switch (t.kind) {
            .hammer => {
                boxH(&b, v3(t.x, botY + t.head * 0.5, 0.01), v3(t.head * 1.5, t.head * 0.60, t.head * 0.60), IRON);
                boxH(&b, v3(t.x + t.head * 1.5, botY + t.head * 0.5, 0.01), v3(t.head * 0.14, t.head * 0.52, t.head * 0.52), FACE_DK);
            },
            .tongs => {
                for ([_]f32{ -1, 1 }) |sx| {
                    b.addCapsule(
                        v3(t.x, botY + t.head, 0.01),
                        v3(t.x + sx * t.head * 1.4, botY - t.head * 2.4, 0.01),
                        0.017,
                        0.012,
                        5,
                        IRON,
                    );
                }
                b.addCylinder(v3(t.x, botY + t.head, -0.01), v3(t.x, botY + t.head, 0.03), 0.024, 0.024, 6, IRON_LT);
            },
            .sledge => {
                boxH(&b, v3(t.x, botY + t.head * 0.5, 0.01), v3(t.head * 0.85, t.head * 0.95, t.head * 0.75), IRON);
                boxH(&b, v3(t.x, botY - t.head * 0.42, 0.01), v3(t.head * 0.50, t.head * 0.14, t.head * 0.50), FACE_DK);
            },
        }
    }
    b.setMat(.wood);
    b.addCylinder(v3(RACK_HW + 0.32, 0, -0.12), v3(RACK_HW + 0.32, 0.48, -0.12), 0.245, 0.225, 9, OAK);
    for ([_]f32{ 0.10, 0.36 }) |t| {
        b.setMat(.steel);
        b.addCylinder(v3(RACK_HW + 0.32, t, -0.12), v3(RACK_HW + 0.32, t + 0.035, -0.12), 0.252, 0.252, 9, IRON);
        b.setMat(.wood);
    }
    b.setMat(.steel);
    for ([_]f32{ 0, 1, 2, 3, 4, 5, 6 }) |k| {
        const a = k * 0.90 + 0.4;
        const d = rng.range(0.03, 0.16);
        const lean = rng.range(0.08, 0.26);
        const foot = v3(RACK_HW + 0.32 + mathx.cosf(a) * d, 0.42, -0.12 + mathx.sinf(a) * d);
        b.addCylinder(
            foot,
            v3(foot.x + mathx.cosf(a) * lean, 0.42 + rng.range(0.28, 0.62), foot.z + mathx.sinf(a) * lean),
            0.019,
            0.017,
            5,
            IRON,
        );
    }
    return b.toModel(shader);
}

test "THE ANVIL'S FACE IS THE NUMBER THE SMITH IS BUILT AGAINST, and its waist is a real pinch" {
    try std.testing.expect(ANVIL_TOP >= ANVIL_FACE);
    try std.testing.expect(ANVIL_FACE > STUMP_H);
    try std.testing.expect(ANVIL_R >= ANVIL_LEN * 0.5 * 1.36 + 0.02);
// The pinch has to be TALL to be a pinch: at 0.054 m between a foot and a body it read as a step.
    try std.testing.expect(WAIST_H > (ANVIL_FACE - STUMP_H) * 0.4);
    try std.testing.expect(WAIST_HW < ANVIL_LEN * 0.5 * 0.60);
    std.debug.print("\n  anvil: face {d:.2} m, stump {d:.2} m x r{d:.2}, waist {d:.2} m tall and {d:.2} m wide, horn out to {d:.2} m\n", .{
        ANVIL_FACE, STUMP_H, STUMP_R, WAIST_H, WAIST_HW * 2.0, ANVIL_LEN * 0.5 * 1.36,
    });
}

test "THE FORGE'S FIRE IS VISIBLE FROM ABOVE — the bed stands proud of its own rim" {
    // The rim tops out at `HEARTH_Y + 0.088` and the coal heap at `HEARTH_Y + 0.12`+. A bed sunk behind its lip
    const rimTop = HEARTH_Y + 0.058 + 0.030;
    const bedTop = HEARTH_Y + 0.075 + 0.045 + 0.082 * 0.62;
    try std.testing.expect(bedTop > rimTop);
    try std.testing.expect(FORGE_LIGHT_Y > HEARTH_Y and FORGE_LIGHT_Y < bedTop + 0.2);
    try std.testing.expect(FORGE_LIGHT_R < 9.0);
    try std.testing.expect(FORGE_TOP > HEARTH_Y + 1.0);
    std.debug.print("  forge: table {d:.2} m, rim tops {d:.2} m, coal tops {d:.2} m ({d:.0} mm proud), flue to {d:.2} m, light {d:.1} m\n", .{
        HEARTH_Y, rimTop, bedTop, (bedTop - rimTop) * 1000.0, FORGE_TOP, FORGE_LIGHT_R,
    });
}

test "THE TROUGH IS A HOLLOW YOU CAN SEE THE WATER IN, and the water is under the rim" {
    try std.testing.expect(QUENCH_HW > LOG_R * 0.55);
    // …and the sheet sits below the rim, or the thing is a solid block with a gloss on top.
    const rim = QUENCH_TOP - 0.030 + 0.042;
    try std.testing.expect(QUENCH_TOP - 0.062 < rim);
    try std.testing.expect(QUENCH_R > QUENCH_HL + LOG_R * 0.5);
    std.debug.print("  trough: {d:.2} m long, opening {d:.2} m across of a {d:.2} m log, water {d:.0} mm under the rim\n", .{
        QUENCH_HL * 2.0, QUENCH_HW * 2.0, LOG_R * 2.0, (rim - (QUENCH_TOP - 0.062)) * 1000.0,
    });
}
