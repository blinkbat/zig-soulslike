const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const IRON = art.IRON;
const MORTAR = art.MORTAR;
const PAVE = art.PAVE;
const PAVE_DK = art.PAVE_DK;
const PAVE_LT = art.PAVE_LT;
const SOIL = art.SOIL;
const STONE = art.STONE;
const STONE_DK = art.STONE_DK;
const STONE_LT = art.STONE_LT;
const STONE_MOSS = art.STONE_MOSS;
const THATCH = art.THATCH;
const THATCH_DK = art.THATCH_DK;
const TIMBER = art.TIMBER;
const TIMBER_DK = art.TIMBER_DK;
const TOWER_R = art.TOWER_R;
const TOWER_SIDES = art.TOWER_SIDES;
const courseInto = art.courseInto;
const lichenInto = art.lichenInto;
const towerDoorway = art.towerDoorway;
const tuftInto = art.tuftInto;


pub fn chapelMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(5150);
    b.setMat(.stone);
    const hw: f32 = 2.6; // wall centre-lines
    const hl: f32 = 3.6;
    const wt: f32 = 0.42; // wall half-thickness
    const wh: f32 = 4.4; // wall height

    b.addCube(v3(0, 0.06, 0), v3(2 * hw + 0.5, 0.12, 2 * hl + 0.5), STONE_DK);
    var fx: i32 = 0;
    while (fx < 4) : (fx += 1) {
        var fz: i32 = 0;
        while (fz < 6) : (fz += 1) {
            const x = (@as(f32, @floatFromInt(fx)) - 1.5) * 1.28;
            const z = (@as(f32, @floatFromInt(fz)) - 2.5) * 1.20;
            if (rng.float() < 0.18) continue; // stones lifted / lost
            b.addCube(v3(x + rng.signed() * 0.05, 0.13, z + rng.signed() * 0.05), v3(rng.range(1.0, 1.2), 0.06, rng.range(0.95, 1.14)), if (rng.float() < 0.4) STONE else STONE_DK);
        }
    }
    courseInto(&b, &rng, -hw, -hl, hw, -hl, .{ .thick = wt, .height = wh, .gapLo = -1.15, .gapHi = 1.15, .sillY = -0.1, .headY = 2.9 });
    b.addCube(v3(0, 3.05, -hl), v3(2.9, 0.30, 2 * wt + 0.06), STONE_LT); // door lintel
    courseInto(&b, &rng, -hw, hl, hw, hl, .{ .thick = wt, .height = wh, .gapLo = -0.45, .gapHi = 0.45, .sillY = 2.5, .headY = 3.7 });
    courseInto(&b, &rng, -hw, -hl, -hw, hl, .{ .thick = wt, .height = wh, .gapLo = -0.7, .gapHi = 0.8, .sillY = 1.5, .headY = 3.1 });
    courseInto(&b, &rng, hw, -hl, hw, hl, .{ .thick = wt, .height = wh, .gapLo = 0.2, .gapHi = 1.7, .sillY = 1.6, .headY = 3.2 });
    // Corner quoins tie the runs together (four bare wall ends read as a flat-pack kit).
    for ([_]f32{ -hw, hw }) |cx| {
        for ([_]f32{ -hl, hl }) |cz| {
            var c: i32 = 0;
            while (c < 5) : (c += 1) {
                const yy = 0.3 + @as(f32, @floatFromInt(c)) * 0.95;
                if (yy > wh) break;
                b.addCube(v3(cx, yy, cz), v3(1.0 + rng.signed() * 0.06, 0.62, 1.0 + rng.signed() * 0.06), if (@mod(c, 2) == 0) STONE else STONE_DK);
            }
        }
    }
    var rf: i32 = 0;
    while (rf < 7) : (rf += 1) {
        const z = -hl + 0.55 + @as(f32, @floatFromInt(rf)) * 1.05;
        b.setMat(.wood);
        for ([_]f32{ -1, 1 }) |sgn| {
            b.addBox(v3(sgn * (hw + 0.15) * 0.5, wh + 0.55, z), v3(sgn * (hw + 0.15) * 0.5, -0.42, 0), v3(0, 0.10, 0), v3(0, 0, 0.10), TIMBER_DK);
        }
        if (z < -1.3) continue; // the south end has lost its covering; the altar two thirds keeps it
        b.setMat(.stone);
        for ([_]f32{ -1, 1 }) |sgn| {
            const run = (hw + 0.25) * 0.5;
            b.addBox(
                v3(sgn * run, wh + 0.48, z),
                v3(sgn * run, -0.42, 0),
                v3(0, 0.09, 0),
                v3(0, 0, 0.55 * rng.range(0.94, 1.04)),
                if (rng.float() < 0.3) STONE_DK else STONE,
            );
        }
    }
    b.setMat(.stone);
    b.addCube(v3(0, 0.55, 2.9), v3(2.5, 0.85, 1.0), STONE_DK);
    b.addCube(v3(0, 1.02, 2.9), v3(2.9, 0.20, 1.25), STONE_LT);
    b.addCylinder(v3(0.65, 1.12, 2.9), v3(0.65, 1.34, 2.9), 0.26, 0.30, 8, STONE);
    b.addCube(v3(-0.75, 1.20, 2.86), v3(0.35, 0.16, 0.35), STONE_DK); // a fallen fragment on the mensa
    for ([_]f32{ -1.55, 1.55 }) |cx| {
        var ci: i32 = 0;
        while (ci < 3) : (ci += 1) {
            const z = -1.9 + @as(f32, @floatFromInt(ci)) * 1.9;
            const h = rng.range(1.1, 2.4);
            b.addCylinder(v3(cx, 0.16, z), v3(cx + rng.signed() * 0.04, 0.16 + h, z), 0.24, 0.21, 8, STONE);
            if (rng.float() < 0.4) b.addCube(v3(cx, 0.16 + h + 0.08, z), v3(0.6, 0.16, 0.6), STONE_LT);
        }
    }
    var d: i32 = 0;
    while (d < 9) : (d += 1) {
        const x = rng.range(-hw + 0.5, hw - 0.5);
        const z = rng.range(-hl + 0.6, hl - 0.8);
        const s = rng.range(0.22, 0.62);
        b.addBox(v3(x, 0.16 + s * 0.4, z), v3(s, 0, rng.signed() * 0.1), v3(rng.signed() * 0.08, s * 0.42, 0), v3(0, 0, s * rng.range(0.5, 1.0)), if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, -1.9, -2.6, 0.8); // grass coming up through the floor
    tuftInto(&b, &rng, 2.0, 0.4, 0.7);
    return b.toModel(shader);
}

pub fn watchtowerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7788);
    b.setMat(.stone);
    const sides: i32 = TOWER_SIDES;
    const R: f32 = TOWER_R;
    const courses: i32 = 15;
    const ch: f32 = 0.76;
    const radial = struct {
        fn v(a: f32, len: f32) rl.Vector3 {
            return v3(mathx.sinf(a) * len, 0, -mathx.cosf(a) * len);
        }
    }.v;
    const tangent = struct {
        fn v(a: f32, len: f32) rl.Vector3 {
            return v3(mathx.cosf(a) * len, 0, mathx.sinf(a) * len);
        }
    }.v;
    // Splayed plinth — a tower that meets the ground at a right angle reads as pasted on.
    var p: i32 = 0;
    while (p < sides) : (p += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(p)) / @as(f32, @floatFromInt(sides));
        const base = radial(a, R + 0.28);
        b.addBox(v3(base.x, 0.22, base.z), tangent(a, 0.58), v3(0, 0.22, 0), radial(a, 0.42), STONE_DK);
    }
    var cr: i32 = 0;
    while (cr < 12) : (cr += 1) {
        var ci: i32 = 0;
        while (ci < sides) : (ci += 1) {
            if (cr < 4 and towerDoorway(ci)) continue; // the core dodges the doorway too
            const a = std.math.tau * (@as(f32, @floatFromInt(ci)) + 0.5) / @as(f32, @floatFromInt(sides));
            const at = radial(a, R);
            b.addBox(
                v3(at.x, 0.44 + (@as(f32, @floatFromInt(cr)) + 0.5) * ch * 1.25, at.z),
                tangent(a, std.math.tau * R / @as(f32, @floatFromInt(sides)) * 0.80),
                v3(0, ch * 0.66, 0),
                radial(a, 0.24),
                MORTAR,
            );
        }
    }
    var c: i32 = 0;
    while (c < courses) : (c += 1) {
        const yc = 0.44 + (@as(f32, @floatFromInt(c)) + 0.5) * ch;
        const skew: f32 = if (@mod(c, 2) == 0) 0.0 else 0.5;
        const crumble: f32 = if (c >= 12) 0.42 else 0.03;
        var i: i32 = 0;
        while (i < sides) : (i += 1) {
            const fi = @as(f32, @floatFromInt(i)) + skew;
            const a = std.math.tau * fi / @as(f32, @floatFromInt(sides));
            if (c < 4 and towerDoorway(i)) continue;
            if ((c == 7 or c == 8) and (i == 2 or i == 9)) continue;
            if (rng.float() < crumble) continue;
            const at = radial(a, R);
            const bw = (std.math.tau * R / @as(f32, @floatFromInt(sides))) * rng.range(1.24, 1.52); // blocks OVERLAP their slot
            b.addBox(
                v3(at.x, yc + rng.signed() * 0.02, at.z),
                tangent(a, bw * 0.5),
                v3(0, ch * 0.5 * rng.range(0.95, 1.02), 0),
                radial(a, 0.34),
                if (rng.float() < 0.22) STONE_LT else if (rng.float() < 0.35) STONE_DK else STONE,
            );
        }
    }
    b.addBox(v3(0, 3.55, -R), v3(1.30, 0, 0), v3(0, 0.28, 0), v3(0, 0, 0.42), STONE_LT);
    for ([_]f32{ -1.18, 1.18 }) |jx| b.addBox(v3(jx, 1.85, -R), v3(0.22, 0, 0), v3(0, 1.85, 0), v3(0, 0, 0.40), STONE_DK);
    b.addCylinder(v3(0, 0.02, 0), v3(0, 0.16, 0), R + 0.1, R + 0.1, sides, STONE_DK);
    b.setMat(.wood);
    var pl: i32 = 0;
    while (pl < 8) : (pl += 1) {
        const x = (@as(f32, @floatFromInt(pl)) - 3.5) * 0.60;
        const halfSpan = @sqrt(@max(R * R - x * x, 0.04));
        if (rng.float() < 0.16) continue; // planks fallen through
        b.addCube(v3(x, 4.62, 0), v3(0.56, 0.14, halfSpan * 2.0), if (@mod(pl, 2) == 0) TIMBER else TIMBER_DK);
    }
    b.addCylinder(v3(0, 4.42, 0), v3(0, 4.54, 0), R * 0.94, R * 0.94, sides, TIMBER_DK); // ring beam
    b.setMat(.stone);
    var m: i32 = 0;
    while (m < sides) : (m += 1) {
        if (rng.float() < 0.45) continue;
        const a = std.math.tau * @as(f32, @floatFromInt(m)) / @as(f32, @floatFromInt(sides));
        const at = radial(a, R);
        const h = rng.range(0.4, 0.95);
        b.addBox(v3(at.x, 11.9 + h * 0.5, at.z), tangent(a, 0.42), v3(0, h * 0.5, 0), radial(a, 0.34), STONE_DK);
    }
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.range(0.6, 2.0);
        const d = rng.range(R + 0.2, R + 1.9);
        const r = rng.range(0.20, 0.55);
        b.addBlob(v3(mathx.sinf(a) * d, r * 0.6, -mathx.cosf(a) * d), v3(r, r * 0.7, r), 3, 5, if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, R + 1.0, 0.8, 0.85);
    return b.toModel(shader);
}

pub fn cottageMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2626);
    b.setMat(.stone);
    const hw: f32 = 2.3;
    const hl: f32 = 1.9;
    const run = struct {
        fn go(bb: *Builder, r: *mathx.Rng, ax: f32, az: f32, bx: f32, bz: f32, height: f32, gapLo: f32, gapHi: f32) void {
            const dx = bx - ax;
            const dz = bz - az;
            const L = @sqrt(dx * dx + dz * dz);
            const ux = dx / L;
            const uz = dz / L;
            const openTop: f32 = @min(2.05, height);
            for ([_][2]f32{ .{ -L * 0.5, gapLo }, .{ gapHi, L * 0.5 } }) |sp| {
                const w = @min(sp[1], L * 0.5) - @max(sp[0], -L * 0.5);
                if (w <= 0.02) continue;
                const mid = (@max(sp[0], -L * 0.5) + @min(sp[1], L * 0.5)) * 0.5;
                bb.addBox(
                    v3(ax + ux * (L * 0.5 + mid), openTop * 0.5, az + uz * (L * 0.5 + mid)),
                    v3(ux * w * 0.5, 0, uz * w * 0.5),
                    v3(0, openTop * 0.5, 0),
                    v3(-uz * 0.17, 0, ux * 0.17),
                    MORTAR,
                );
            }
            if (height > openTop + 0.02) {
                bb.addBox(
                    v3(ax + ux * L * 0.5, (openTop + height) * 0.5, az + uz * L * 0.5),
                    v3(ux * L * 0.5, 0, uz * L * 0.5),
                    v3(0, (height - openTop) * 0.5, 0),
                    v3(-uz * 0.17, 0, ux * 0.17),
                    MORTAR,
                );
            }
            var y: f32 = 0.05;
            while (y < height) {
                const ch = r.range(0.24, 0.36);
                var t: f32 = 0.04;
                while (t < 0.98) {
                    const w = r.range(0.26, 0.46);
                    const s = (t - 0.5) * L;
                    if (!(s > gapLo and s < gapHi and y < 2.05)) {
                        bb.addBlob(
                            v3(ax + ux * t * L + r.signed() * 0.04, y + ch * 0.5, az + uz * t * L + r.signed() * 0.04),
                            v3(@abs(ux) * w * 0.68 + @abs(uz) * 0.22 + 0.07, ch * 0.62, @abs(uz) * w * 0.68 + @abs(ux) * 0.22 + 0.07),
                            3,
                            5,
                            if (r.float() < 0.3) STONE_LT else if (r.float() < 0.45) STONE_MOSS else STONE,
                        );
                    }
                    t += w / L * 0.72; // stones OVERLAP; a butted row seams round each one
                }
                y += ch * 0.78;
            }
        }
    }.go;
    run(&b, &rng, -hw, hl, hw, hl, 2.55, 9, 9); // back wall, no opening
    run(&b, &rng, -hw, -hl, -hw, hl, 2.55, -0.4, 0.7); // west wall, window
    run(&b, &rng, hw, -hl, hw, hl, 2.55, 9, 9); // east wall
    run(&b, &rng, -hw, -hl, hw, -hl, 1.15, -0.85, 0.85); // front wall, tumbled + a doorway gap
    var g: i32 = 0;
    while (g < 5) : (g += 1) {
        const t = @as(f32, @floatFromInt(g)) / 5.0;
        b.addCube(v3(0, 2.6 + t * 1.2, hl), v3((2 * hw) * (1.0 - t) * 0.92, 0.3, 0.42), if (@mod(g, 2) == 0) STONE else STONE_DK);
    }
    b.addCube(v3(1.35, 1.7, hl + 0.34), v3(1.1, 3.4, 0.62), STONE_DK);
    b.addCube(v3(1.35, 3.55, hl + 0.34), v3(0.86, 0.5, 0.5), STONE);
    b.addCube(v3(1.35, 0.55, hl - 0.1), v3(0.72, 1.1, 0.5), IRON); // the sooted hearth opening
    b.setMat(.wood);
    b.addCapsule(v3(0, 3.66, hl - 0.1), v3(0, 3.30, -hl + 0.6), 0.10, 0.08, 6, TIMBER_DK);
    var rf: i32 = 0;
    while (rf < 5) : (rf += 1) {
        if (rng.float() < 0.3) continue;
        const z = hl - 0.3 - @as(f32, @floatFromInt(rf)) * 0.85;
        const sgn: f32 = if (@mod(rf, 2) == 0) 1 else -1;
        b.addCapsule(v3(0, 3.5, z), v3(sgn * hw * rng.range(0.7, 1.02), rng.range(2.1, 2.7), z + rng.signed() * 0.2), 0.075, 0.055, 5, TIMBER_DK);
    }
    var th: i32 = 0;
    while (th < 5) : (th += 1) {
        b.addBlob(
            v3(rng.range(-1.5, 1.5), rng.range(2.6, 3.3), rng.range(-0.4, hl - 0.2)),
            v3(rng.range(0.3, 0.7), 0.14, rng.range(0.2, 0.45)),
            3,
            5,
            if (rng.float() < 0.5) THATCH else THATCH_DK,
        );
    }
    b.setMat(.stone);
    var d: i32 = 0;
    while (d < 8) : (d += 1) {
        const r = rng.range(0.16, 0.38);
        b.addBlob(v3(rng.range(-hw, hw), r * 0.6, rng.range(-hl - 1.2, hl)), v3(r, r * 0.7, r), 3, 5, if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.range(-1.4, 1.2), 0.9);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.range(-1.4, 1.2), 0.75);
    return b.toModel(shader);
}

pub fn causewayMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3939);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 14) : (i += 1) {
        const x = -5.0 + (@as(f32, @floatFromInt(i)) + 0.5) * (10.0 / 14.0);
        if (i == 8 or i == 9) continue; // the collapsed span
        const sink = if (i == 7 or i == 10) rng.range(0.02, 0.06) else 0.0; // slabs slumping toward the gap
        b.addBox(
            v3(x, 0.14 - sink, rng.signed() * 0.05),
            v3(0.36 * rng.range(0.9, 1.1), rng.signed() * 0.012, 0),
            v3(0, 0.13, rng.signed() * 0.02),
            v3(0, 0, 1.35 * rng.range(0.95, 1.02)),
            if (rng.float() < 0.3) STONE_LT else if (rng.float() < 0.5) STONE_MOSS else STONE,
        );
    }
    for ([_]f32{ -1.45, 1.45 }) |z| {
        var k: i32 = 0;
        while (k < 16) : (k += 1) {
            if (rng.float() < 0.22) continue;
            const x = -5.0 + (@as(f32, @floatFromInt(k)) + 0.5) * (10.0 / 16.0);
            b.addBox(v3(x, 0.30, z + rng.signed() * 0.04), v3(0.30, rng.signed() * 0.02, 0), v3(0, rng.range(0.14, 0.22), 0), v3(0, 0, 0.22), if (rng.float() < 0.35) STONE_DK else STONE);
        }
    }
    var f: i32 = 0;
    while (f < 6) : (f += 1) {
        const r = rng.range(0.16, 0.34);
        b.addBlob(v3(rng.range(-1.0, 2.4), r * 0.5, rng.range(-2.2, 2.2)), v3(r, r * 0.6, r * 1.1), 3, 5, STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-4.5, 4.5), 1.75, 0.7); // weeds in the kerb joints
    tuftInto(&b, &rng, rng.range(-4.5, 4.5), -1.75, 0.6);
    return b.toModel(shader);
}

pub fn pavingMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(1234);
    b.setMat(.stone);
    b.addCylinder(v3(0, 0.006, 0), v3(0, 0.020, 0), 2.35, 2.20, 14, SOIL);
    var holes: [3][3]f32 = undefined;
    for (&holes) |*h| {
        const a = rng.angle();
        const d = rng.range(0.4, 1.7);
        h.* = .{ mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.30, 0.62) };
    }
    // A ROAD IS LAID, NOT SCATTERED.
    const PITCH: f32 = 0.30;
    const HALFN: i32 = 8; // cells each way from centre — covers the 2.2 m disc
    var gz: i32 = -HALFN;
    while (gz <= HALFN) : (gz += 1) {
        const rowOff: f32 = if (@mod(gz, 2) == 0) 0 else PITCH * 0.5; // the running bond
        var gx: i32 = -HALFN;
        while (gx <= HALFN) : (gx += 1) {
            const px = @as(f32, @floatFromInt(gx)) * PITCH + rowOff + rng.signed() * 0.035;
            const pz = @as(f32, @floatFromInt(gz)) * PITCH + rng.signed() * 0.035;
            if (px * px + pz * pz > 2.2 * 2.2) continue; // keep the patch round
            var lost = rng.float() < 0.07; // the odd sett prised out
            for (holes) |h| {
                const dx = px - h[0];
                const dz = pz - h[1];
                if (dx * dx + dz * dz < h[2] * h[2]) lost = true;
            }
            if (lost) continue;
            const w = PITCH * rng.range(1.02, 1.20); // butted, then some — the joint is a shadow
            const l = PITCH * rng.range(0.95, 1.25);
            const wob = rng.signed() * 0.09; // a few degrees of wander off the course line
            b.addBox(
                v3(px, rng.range(0.010, 0.026), pz),
                v3(w * 0.5, rng.signed() * 0.012, wob * w * 0.5),
                v3(0, 0.020, 0),
                v3(-wob * l * 0.5, rng.signed() * 0.010, l * 0.5),
                if (rng.float() < 0.14) STONE_MOSS else if (rng.float() < 0.3) SOIL else if (rng.float() < 0.5) PAVE_LT else if (rng.float() < 0.75) PAVE_DK else PAVE,
            );
        }
    }
    const ra = rng.angle();
    for ([_]f32{ -0.42, 0.42 }) |o| {
        var r: i32 = 0;
        while (r < 7) : (r += 1) {
            const t = (@as(f32, @floatFromInt(r)) - 3.0) * 0.60;
            b.addBox(
                v3(mathx.cosf(ra) * t - mathx.sinf(ra) * o, 0.026, mathx.sinf(ra) * t + mathx.cosf(ra) * o),
                v3(mathx.cosf(ra) * 0.32, 0, mathx.sinf(ra) * 0.32),
                v3(0, 0.005, 0),
                v3(-mathx.sinf(ra) * 0.11, 0, mathx.cosf(ra) * 0.11),
                PAVE_LT,
            );
        }
    }
    var k: i32 = 0;
    while (k < 3) : (k += 1) {
        const a = rng.angle();
        b.addBox(
            v3(mathx.cosf(a) * 2.05, 0.038, mathx.sinf(a) * 2.05),
            v3(mathx.cosf(a + 1.57) * 0.42, rng.signed() * 0.015, mathx.sinf(a + 1.57) * 0.42),
            v3(0, 0.038, 0),
            v3(mathx.cosf(a) * 0.14, 0, mathx.sinf(a) * 0.14),
            if (rng.float() < 0.4) STONE_DK else PAVE,
        );
    }
    b.setMat(.plant);
    for (holes) |h| tuftInto(&b, &rng, h[0], h[1], 0.5);
    lichenInto(&b, &rng, v3(rng.signed() * 1.5, 0.045, rng.signed() * 1.5), v3(0.42, 0.012, 0.38), 4);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.8, rng.signed() * 1.8, 0.55);
    tuftInto(&b, &rng, rng.signed() * 1.8, rng.signed() * 1.8, 0.45);
    return b.toModel(shader);
}

