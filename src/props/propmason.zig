const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const Rng = mathx.Rng;

const BARK_DK = art.BARK_DK;
const IRON = art.IRON;
const LEAF = art.LEAF;
const LEAF_DK = art.LEAF_DK;
const LEAF_GOLD = art.LEAF_GOLD;
const IVY_GRN = art.IVY_GRN;
const MARBLE = art.MARBLE;
const MARBLE_DK = art.MARBLE_DK;
const MARBLE_LT = art.MARBLE_LT;
const MORTAR = art.MORTAR;
const ROCK_DEEP = art.ROCK_DEEP;
const SLATE = art.STONE_DK;
const STONE = art.STONE;
const STONE_DK = art.STONE_DK;
const STONE_LT = art.STONE_LT;
const STONE_MOSS = art.STONE_MOSS;
const THATCH = art.THATCH;
const THATCH_DK = art.THATCH_DK;
const TIMBER = art.TIMBER;
const TIMBER_DK = art.TIMBER_DK;

const chipsInto = art.chipsInto;
const crackInto = art.crackInto;
const lichenInto = art.lichenInto;
const tuftInto = art.tuftInto;

/// ONE GRID, AND EVERY PIECE IN THE KIT IS CUT TO IT: a long run is `MOD`, a short one half of that, a storey `WALL_H`. The editor's own snap is
/// the only thing holding pieces together, so a piece off the grid leaves a gap nothing can close.
pub const MOD: f32 = 6.0;
pub const HALF: f32 = 3.0;
pub const WALL_H: f32 = 4.20;
pub const TALL_H: f32 = 6.60;
pub const LOW_H: f32 = 1.60;
pub const STUB_H: f32 = 0.62;
pub const TH: f32 = 0.46;
const COURSE_H: f32 = 0.46;

pub const DOOR_W: f32 = 1.80;
pub const DOOR_H: f32 = 2.90;
const WIN_W: f32 = 1.30;
const WIN_SILL: f32 = 1.55;
const WIN_HEAD: f32 = 3.05;

/// The break's low end, as a share of the wall's height. `broken` falls from full at one end to this at the other.
const BREAK_LOW: f32 = 0.26;

/// THE COPING ON AN INTACT HEAD — where its slab sits over the wall's own height and how thick it is.
const CAP_Y: f32 = 0.09;
const CAP_HALF: f32 = 0.10;
/// What a capped piece reaches over its own height, and the only thing `props.INFO` has to know about the coping.
pub const CAP_PROUD: f32 = 0.30;

comptime {
    std.debug.assert(CAP_PROUD >= CAP_Y + CAP_HALF);
}

pub fn wallTop(h: f32) f32 {
    return h + CAP_PROUD;
}

pub const Ruin = enum { intact, worn, broken, stub };

const Wall = struct {
    run: f32,
    h: f32 = WALL_H,
    ruin: Ruin = .intact,
    door: bool = false,
    arched: bool = false,
    window: bool = false,
    pilaster: bool = false,
    ivy: bool = false,
    cap: bool = true,
};

fn coursesFor(h: f32) i32 {
    return @max(1, @as(i32, @intFromFloat(@round(h / COURSE_H))));
}

fn crumbleOf(r: Ruin) f32 {
    return switch (r) {
        .intact => 0.04,
        .worn => 0.38,
        .broken => 0.46,
        .stub => 0.34,
    };
}

/// THE BREAK IS A CURVE, NOT A PER-BAY ROLL OF THE DICE — the ragged edge is the courses' own missing stones (`crumbleTop`); the LINE runs smooth end to end.
fn breakAt(t: f32) f32 {
    return mathx.lerpF(1.0, BREAK_LOW, mathx.smoothstep(0.12, 1.0, t));
}

fn wallInto(b: *Builder, rng: *Rng, w: Wall) void {
    const half = w.run * 0.5;
    const crumble = crumbleOf(w.ruin);
    const h: f32 = switch (w.ruin) {
        .stub => STUB_H,
        else => w.h,
    };

    if (w.ruin == .broken) {
        const BAYS: i32 = 6;
        const bw = w.run / @as(f32, BAYS);
        var i: i32 = 0;
        while (i < BAYS) : (i += 1) {
            const fi = @as(f32, @floatFromInt(i));
            const x0 = -half + fi * bw;
            const bh = h * breakAt((fi + 0.5) / @as(f32, BAYS));
            art.courseInto(b, rng, x0, 0, x0 + bw, 0, .{
                .thick = TH,
                .height = bh,
                .courses = coursesFor(bh),
                .blockW = 0.60,
                .crumbleTop = crumble,
            });
        }
    } else {
        var spec = art.Course{
            .thick = TH,
            .height = h,
            .courses = coursesFor(h),
            .blockW = 0.62,
            .crumbleTop = crumble,
        };
        if (w.door) {
            spec.gapLo = -DOOR_W * 0.5;
            spec.gapHi = DOOR_W * 0.5;
            spec.sillY = -0.1;
            spec.headY = DOOR_H;
        } else if (w.window) {
            spec.gapLo = -WIN_W * 0.5;
            spec.gapHi = WIN_W * 0.5;
            spec.sillY = WIN_SILL;
            spec.headY = WIN_HEAD;
        }
        art.courseInto(b, rng, -half, 0, half, 0, spec);
    }

    b.setMat(.stone);
    if (w.door) {
        jambsInto(b, rng, DOOR_W, DOOR_H);
        if (w.arched) ringInto(b, rng, .{ .y = DOOR_H - 0.06, .r = DOOR_W * 0.5 + 0.10, .dep = TH * 1.06 }) else lintelInto(b, rng, 0, DOOR_H, DOOR_W + 0.74);
    }
    if (w.window) {
        b.addBox(v3(0, WIN_SILL - 0.10, 0), v3(WIN_W * 0.5 + 0.22, rng.signed() * 0.008, 0), v3(0, 0.11, 0), v3(0, 0, TH * 1.14), STONE_LT);
        ringInto(b, rng, .{ .y = WIN_HEAD - 0.06, .r = WIN_W * 0.5 + 0.08, .dep = TH * 1.02 });
    }
    if (w.pilaster) {
        for ([_]f32{ -half * 0.62, half * 0.62 }) |px| {
            _ = art.courseStack(b, rng, px, 0, TH * 0.86, 0.72, 0.44, 0.52, coursesFor(h * 0.92), 0.07, null);
        }
    }
    if (w.cap and w.ruin == .intact) {
        b.setMat(.stone);
        b.addBox(v3(0, h + CAP_Y, 0), v3(half + 0.05, rng.signed() * 0.010, 0), v3(0, CAP_HALF, 0), v3(0, 0, TH * 1.18), STONE_LT);
    }

    weatherInto(b, rng, w.run, h, w.ruin);
    if (w.ivy) ivyCoatInto(b, rng, w.run, h);
}

/// ONE RING, AND EVERY ARCH IN THE KIT IS CUT FROM IT — a window head, a doorhead and a gate span are the same stones at three radii. `n` is ODD so
/// the crown is a KEYSTONE and not a joint, and the defaults are the wall head's: a bay hands over its own stone size, count and jitter.
const Ring = struct {
    cx: f32 = 0,
    y: f32,
    r: f32,
    dep: f32,
    rad: f32 = 0.30,
    n: i32 = 11,
    jit: f32 = 0.012,
    lt: f32 = 0.28,
    dk: f32 = 0.46,
};

fn ringInto(b: *Builder, rng: *Rng, s: Ring) void {
    b.setMat(.stone);
    const nf: f32 = @floatFromInt(s.n);
    var i: i32 = 0;
    while (i < s.n) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / nf;
        const a = std.math.pi * t;
        const key = i == @divTrunc(s.n, 2);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const halfW = (std.math.pi * s.r / nf) * 0.5 * rng.range(1.05, 1.18);
        const rad = s.rad * (if (key) @as(f32, 1.26) else rng.range(0.94, 1.06));
        b.addBox(
            v3(s.cx - ca * (s.r + rad * 0.10), s.y + sa * (s.r + rad * 0.10), rng.signed() * s.jit),
            v3(sa * halfW, ca * halfW, 0),
            v3(-ca * rad, sa * rad, 0),
            v3(0, 0, s.dep * (if (key) @as(f32, 1.10) else 1.0)),
            if (key) STONE_LT else if (rng.float() < s.lt) STONE_LT else if (rng.float() < s.dk) STONE_DK else STONE,
        );
    }
}

fn lintelInto(b: *Builder, rng: *Rng, cx: f32, y: f32, w: f32) void {
    b.setMat(.stone);
    b.addBox(v3(cx, y + 0.17, 0), v3(w * 0.5, rng.signed() * 0.008, 0), v3(0, 0.17, 0), v3(0, 0, TH * 1.08), STONE_LT);
}

fn jambsInto(b: *Builder, rng: *Rng, w: f32, h: f32) void {
    for ([_]f32{ -1, 1 }) |s| {
        const x = s * (w * 0.5 + 0.16);
        _ = art.courseStack(b, rng, x, 0, 0, 0.34, TH * 1.10, 0.42, coursesFor(h), 0.03, null);
    }
}

fn weatherInto(b: *Builder, rng: *Rng, run: f32, h: f32, ruin: Ruin) void {
    const half = run * 0.5;
    const n: i32 = switch (ruin) {
        .intact => 0,
        .worn => 3,
        .broken => 6,
        .stub => 5,
    };
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        chipsInto(b, rng, rng.range(-half, half), rng.signed() * 0.9, 1.5, 0.10, 0.34, 5);
    }
    b.setMat(.stone);
    var k: i32 = 0;
    while (k < n) : (k += 1) {
        const r = rng.range(0.16, 0.40);
        b.addBlob(
            v3(rng.range(-half, half), r * 0.58, rng.signed() * (TH * 0.5 + rng.range(0.20, 1.10))),
            v3(r, r * rng.range(0.55, 0.80), r * rng.range(0.85, 1.25)),
            3,
            5,
            if (rng.float() < 0.35) STONE_MOSS else if (rng.float() < 0.5) ROCK_DEEP else STONE_DK,
        );
    }
    crackInto(b, v3(rng.range(-half * 0.7, half * 0.7), rng.range(0.15, h * 0.35), TH * 0.52), v3(rng.signed() * 0.3, 0.95, 0), v3(1, 0, 0), rng.range(0.9, 1.9), 0.024, 0.04);
    lichenInto(b, rng, v3(rng.range(-half, half), rng.range(h * 0.45, h * 0.85), TH * 0.5), v3(0.62, 0.06, 0.30), 4);
    lichenInto(b, rng, v3(rng.range(-half, half), rng.range(0.30, h * 0.5), -TH * 0.5), v3(0.44, 0.34, 0.02), 4);
    tuftInto(b, rng, rng.range(-half, half), rng.range(0.42, 0.95), 0.82);
    tuftInto(b, rng, rng.range(-half, half), rng.range(-0.95, -0.42), 0.66);
}

/// UP THE FACE, NOT HUNG OFF THE TOP — a creeper roots at the foot and thins as it climbs, which is the only thing that tells it from a curtain (`flora.vineCurtainMesh`).
fn ivyCoatInto(b: *Builder, rng: *Rng, run: f32, h: f32) void {
    const half = run * 0.5;
    const STRANDS = 9;
    var s: i32 = 0;
    while (s < STRANDS) : (s += 1) {
        const fs = (@as(f32, @floatFromInt(s)) + 0.5) / @as(f32, STRANDS);
        const face: f32 = if (rng.float() < 0.78) 1.0 else -1.0;
        var x = -half + fs * run + rng.signed() * 0.22;
        const z = face * (TH * 0.5 + 0.03);
        const top = h * rng.range(0.55, 1.02);
        const SEGS = 9;
        var y: f32 = 0.04;
        var drift = rng.signed() * 0.10;
        var i: i32 = 0;
        while (i < SEGS) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, SEGS);
            const step = top / @as(f32, SEGS);
            const nx = x + drift * step;
            const ny = y + step;
            b.setMat(.bark);
            b.addCapsule(v3(x, y, z), v3(nx, ny, z), 0.020 * (1.0 - 0.55 * t), 0.020 * (1.0 - 0.55 * (t + 0.11)), 4, if (rng.float() < 0.3) art.BARK else BARK_DK);
            b.setMat(.plant);
            const nl: i32 = if (t < 0.6) 4 else 2;
            var l: i32 = 0;
            while (l < nl) : (l += 1) {
                const u = rng.range(0.1, 0.9);
                const lr = rng.range(0.070, 0.135) * (1.0 - 0.35 * t);
                b.addBlob(
                    v3(mathx.lerpF(x, nx, u) + rng.signed() * lr * 1.2, mathx.lerpF(y, ny, u), z + face * lr * 0.30),
                    v3(lr, lr * 0.88, lr * 0.28),
                    3,
                    4,
                    if (rng.float() < 0.07) LEAF_GOLD else if (rng.float() < 0.35) LEAF_DK else if (rng.float() < 0.5) IVY_GRN else LEAF,
                );
            }
            drift += rng.signed() * 0.09;
            x = nx;
            y = ny;
        }
    }
}

fn wallModel(shader: rl.Shader, seed: u64, w: Wall) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(seed);
    wallInto(&b, &rng, w);
    return b.toModel(shader);
}

/// Named once: `illusoryLongMesh` and friends build the SAME seed and the SAME spec, which is the whole of the
/// disguise. Written out at both ends the twins drift apart the first time either is retuned.
const PLAIN_LONG = Twin{ .seed = 7101, .wall = .{ .run = MOD } };
const PLAIN_SHORT = Twin{ .seed = 7105, .wall = .{ .run = HALF } };
const PLAIN_TALL = Twin{ .seed = 7109, .wall = .{ .run = MOD, .h = TALL_H } };

const Twin = struct { seed: u64, wall: Wall };

pub fn longWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, PLAIN_LONG.seed, PLAIN_LONG.wall);
}
pub fn longWornMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7102, .{ .run = MOD, .ruin = .worn });
}
pub fn longBrokenMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7103, .{ .run = MOD, .ruin = .broken });
}
pub fn footingMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7104, .{ .run = MOD, .ruin = .stub, .cap = false });
}
pub fn shortWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, PLAIN_SHORT.seed, PLAIN_SHORT.wall);
}
pub fn shortWornMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7106, .{ .run = HALF, .ruin = .worn });
}
pub fn shortBrokenMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7107, .{ .run = HALF, .ruin = .broken });
}
pub fn lowWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7108, .{ .run = MOD, .h = LOW_H });
}
pub fn tallWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, PLAIN_TALL.seed, PLAIN_TALL.wall);
}
pub fn ivyWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7110, .{ .run = MOD, .ruin = .worn, .ivy = true });
}
pub fn windowWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7111, .{ .run = MOD, .window = true });
}
pub fn pilasterWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7112, .{ .run = MOD, .pilaster = true });
}
pub fn doorWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7113, .{ .run = MOD, .door = true });
}
pub fn archDoorWallMesh(shader: rl.Shader) rl.Model {
    return wallModel(shader, 7114, .{ .run = MOD, .door = true, .arched = true });
}

/// THE WASH IS THE ONLY DIFFERENCE (`art.ILLUSION_WASH`) — an illusory piece must be the same masonry as the piece beside it.
fn illusionOf(shader: rl.Shader, t: Twin) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(t.seed);
    wallInto(&b, &rng, t.wall);
    b.wash(art.ILLUSION_WASH, art.ILLUSION_WASH_T);
    return b.toModel(shader);
}

pub fn illusoryLongMesh(shader: rl.Shader) rl.Model {
    return illusionOf(shader, PLAIN_LONG);
}
pub fn illusoryShortMesh(shader: rl.Shader) rl.Model {
    return illusionOf(shader, PLAIN_SHORT);
}
pub fn illusoryTallMesh(shader: rl.Shader) rl.Model {
    return illusionOf(shader, PLAIN_TALL);
}

// A corner is two half runs meeting on the local origin, opening toward +x and +z.
fn cornerModel(shader: rl.Shader, seed: u64, ruin: Ruin) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(seed);
    const h: f32 = if (ruin == .stub) STUB_H else WALL_H;
    const crumble = crumbleOf(ruin);
    for ([_]bool{ true, false }) |alongX| {
        const bh = if (ruin == .broken) h * BREAK_LOW * 1.6 else h;
        const n: i32 = if (ruin == .broken) 4 else 1;
        const seg = HALF / @as(f32, @floatFromInt(n));
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const fi = @as(f32, @floatFromInt(i));
            const t0 = fi * seg;
            const t1 = t0 + seg;
            const hh = if (ruin == .broken) mathx.lerpF(h, bh, (fi + 0.5) / @as(f32, @floatFromInt(n))) else h;
            const spec = art.Course{ .thick = TH, .height = hh, .courses = coursesFor(hh), .blockW = 0.60, .crumbleTop = crumble };
            if (alongX) art.courseInto(&b, &rng, t0, 0, t1, 0, spec) else art.courseInto(&b, &rng, 0, t0, 0, t1, spec);
        }
    }
    art.quoinsInto(&b, &rng, 0, 0, 0, COURSE_H, coursesFor(h), TH * 1.30, TH * 0.95);
    weatherInto(&b, &rng, MOD, h, ruin);
    return b.toModel(shader);
}

pub fn cornerMesh(shader: rl.Shader) rl.Model {
    return cornerModel(shader, 7120, .intact);
}
pub fn cornerBrokenMesh(shader: rl.Shader) rl.Model {
    return cornerModel(shader, 7121, .broken);
}

pub const FRAME_W: f32 = DOOR_W + 0.90;
pub const FRAME_H: f32 = DOOR_H + 0.62;

pub fn doorframeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7130);
    jambsInto(&b, &rng, DOOR_W, DOOR_H);
    lintelInto(&b, &rng, 0, DOOR_H, FRAME_W);
    b.setMat(.stone);
    b.addBox(v3(0, DOOR_H + 0.44, 0), v3(FRAME_W * 0.44, rng.signed() * 0.008, 0), v3(0, 0.12, 0), v3(0, 0, TH * 1.24), STONE_LT);
    b.setMat(.wood);
    b.addBox(v3(-DOOR_W * 0.30, DOOR_H * 0.46, TH * 0.44), v3(DOOR_W * 0.26, 0, 0), v3(0, DOOR_H * 0.46, 0), v3(0, 0, 0.05), TIMBER_DK);
    b.addCube(v3(-DOOR_W * 0.30, DOOR_H * 0.70, TH * 0.52), v3(DOOR_W * 0.50, 0.09, 0.06), IRON);
    weatherInto(&b, &rng, FRAME_W, FRAME_H, .worn);
    return b.toModel(shader);
}

pub fn archDoorframeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7131);
    jambsInto(&b, &rng, DOOR_W, DOOR_H);
    ringInto(&b, &rng, .{ .y = DOOR_H - 0.06, .r = DOOR_W * 0.5 + 0.16, .dep = TH * 1.14 });
    weatherInto(&b, &rng, FRAME_W, FRAME_H, .worn);
    return b.toModel(shader);
}

pub const GATE_SPAN: f32 = 3.40;
pub const GATE_SPRING: f32 = 3.20;
pub const GATE_PIER: f32 = 0.90;
pub const GATE_TOP: f32 = GATE_SPRING + GATE_SPAN * 0.5 + 0.90;

fn bayArchInto(b: *Builder, rng: *Rng, cx: f32, pierW: f32, span: f32, spring: f32, dep: f32) void {
    b.setMat(.stone);
    for ([_]f32{ -1, 1 }) |s| {
        const x = cx + s * (span * 0.5 + pierW * 0.5);
        _ = art.courseStack(b, rng, x, 0, 0, pierW, dep, 0.52, coursesFor(spring), 0.05, null);
        b.setMat(.stone);
        b.addBox(v3(x, spring + 0.10, 0), v3(pierW * 0.62, rng.signed() * 0.010, 0), v3(0, 0.12, 0), v3(0, 0, dep * 0.64), STONE_LT);
    }
    ringInto(b, rng, .{
        .cx = cx,
        .y = spring + 0.22,
        .r = span * 0.5,
        .dep = dep * 0.5,
        .rad = 0.40,
        .n = 13,
        .jit = 0.014,
        .lt = 0.26,
        .dk = 0.45,
    });
}

pub fn gateArchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7140);
    bayArchInto(&b, &rng, 0, GATE_PIER, GATE_SPAN, GATE_SPRING, TH * 1.6);
    b.setMat(.stone);
    b.addBox(v3(0, GATE_SPRING + GATE_SPAN * 0.5 + 0.72, 0), v3(GATE_SPAN * 0.5 + 0.95, rng.signed() * 0.012, 0), v3(0, 0.22, 0), v3(0, 0, TH * 0.86), STONE_LT);
    weatherInto(&b, &rng, GATE_SPAN + 1.8, GATE_TOP, .worn);
    return b.toModel(shader);
}

pub const ARCADE_BAYS: i32 = 3;
pub const ARCADE_PIER: f32 = 0.86;
pub const ARCADE_SPAN: f32 = 2.40;
pub const ARCADE_SPRING: f32 = 2.60;
pub const ARCADE_PITCH: f32 = ARCADE_SPAN + ARCADE_PIER;
pub const ARCADE_RUN: f32 = ARCADE_PITCH * @as(f32, ARCADE_BAYS);
pub const ARCADE_TOP: f32 = ARCADE_SPRING + ARCADE_SPAN * 0.5 + 0.86;

pub fn arcadeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7141);
    var i: i32 = 0;
    while (i < ARCADE_BAYS) : (i += 1) {
        const cx = (@as(f32, @floatFromInt(i)) + 0.5 - @as(f32, ARCADE_BAYS) * 0.5) * ARCADE_PITCH;
        bayArchInto(&b, &rng, cx, ARCADE_PIER, ARCADE_SPAN, ARCADE_SPRING, TH * 1.3);
    }
    b.setMat(.stone);
    b.addBox(v3(0, ARCADE_SPRING + ARCADE_SPAN * 0.5 + 0.66, 0), v3(ARCADE_RUN * 0.5, rng.signed() * 0.012, 0), v3(0, 0.20, 0), v3(0, 0, TH * 0.78), STONE_LT);
    weatherInto(&b, &rng, ARCADE_RUN, ARCADE_TOP, .worn);
    return b.toModel(shader);
}

pub const SLAB: f32 = MOD;
pub const SLAB_T: f32 = 0.38;

/// A CEILING IS PLACED ON `r1`, THE OP'S OWN LIFT — nothing here knows how high the room under it is, so the piece is authored with its UNDERSIDE on y=0.
fn slabInto(b: *Builder, rng: *Rng, hole: bool) void {
    b.setMat(.stone);
    const halfS = SLAB * 0.5;
    const CELLS = 4;
    const cw = SLAB / @as(f32, CELLS);
    var i: i32 = 0;
    while (i < CELLS) : (i += 1) {
        var j: i32 = 0;
        while (j < CELLS) : (j += 1) {
            const cx = -halfS + (@as(f32, @floatFromInt(i)) + 0.5) * cw;
            const cz = -halfS + (@as(f32, @floatFromInt(j)) + 0.5) * cw;
            if (hole and i >= 2 and j >= 2 and rng.float() < 0.72) continue;
            b.addBox(
                v3(cx + rng.signed() * 0.012, SLAB_T * 0.5, cz + rng.signed() * 0.012),
                v3(cw * 0.5 * rng.range(0.97, 1.0), 0, 0),
                v3(0, SLAB_T * 0.5, 0),
                v3(0, 0, cw * 0.5 * rng.range(0.97, 1.0)),
                if (rng.float() < 0.18) STONE_LT else if (rng.float() < 0.36) STONE_DK else STONE,
            );
        }
    }
    b.setMat(.wood);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const z = -halfS + (@as(f32, @floatFromInt(r)) + 0.5) * (SLAB / 5.0);
        if (hole and z > 0 and rng.float() < 0.6) continue;
        b.addBox(v3(0, -0.11, z), v3(halfS, 0, 0), v3(0, 0.11, 0), v3(0, 0, 0.13), if (rng.float() < 0.4) TIMBER_DK else TIMBER);
    }
}

pub fn ceilingMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7150);
    slabInto(&b, &rng, false);
    return b.toModel(shader);
}

pub fn ceilingBrokenMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7151);
    slabInto(&b, &rng, true);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const rr = rng.range(0.12, 0.30);
        b.addBlob(v3(rng.range(0, SLAB * 0.5), SLAB_T + rr * 0.4, rng.range(0, SLAB * 0.5)), v3(rr, rr * 0.7, rr), 3, 5, if (rng.float() < 0.4) STONE_DK else STONE);
    }
    return b.toModel(shader);
}

pub const VAULT_SPAN: f32 = MOD;
pub const VAULT_RISE: f32 = MOD * 0.5;
pub const VAULT_DEPTH: f32 = 2.40;

pub fn vaultMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7152);
    b.setMat(.stone);
    const NV = 17;
    const r = VAULT_SPAN * 0.5;
    var i: i32 = 0;
    while (i < NV) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, NV);
        const a = std.math.pi * t;
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const halfW = (std.math.pi * r / @as(f32, NV)) * 0.5 * rng.range(1.04, 1.14);
        b.addBox(
            v3(-ca * r, sa * r, 0),
            v3(sa * halfW, ca * halfW, 0),
            v3(-ca * 0.34, sa * 0.34, 0),
            v3(0, 0, VAULT_DEPTH * 0.5),
            if (rng.float() < 0.18) STONE_LT else if (rng.float() < 0.36) STONE_DK else STONE,
        );
    }
    for ([_]f32{ -1, 1 }) |s| {
        b.addBox(v3(s * (r + 0.24), VAULT_RISE * 0.22, 0), v3(0.24, 0, 0), v3(0, VAULT_RISE * 0.22, 0), v3(0, 0, VAULT_DEPTH * 0.52), STONE_DK);
    }
    return b.toModel(shader);
}


pub const MANOR_HW: f32 = 5.40;
pub const MANOR_HL: f32 = 4.20;
pub const MANOR_EAVE: f32 = 6.30;
pub const MANOR_TOP: f32 = 10.60;

/// A SHELL YOU WALK INTO: the door gap in the mesh and the gap in `props.INFO`'s colliders are the same two numbers.
pub const MANOR_DOOR_X0: f32 = -0.95;
pub const MANOR_DOOR_X1: f32 = 0.95;

fn storeyRun(b: *Builder, rng: *Rng, ax: f32, az: f32, bx: f32, bz: f32, h: f32, y0: f32, gapLo: f32, gapHi: f32, sillY: f32, headY: f32) void {
    art.courseInto(b, rng, ax, az, bx, bz, .{
        .thick = TH,
        .height = h,
        .y0 = y0,
        .courses = coursesFor(h),
        .blockW = 0.64,
        .crumbleTop = 0.05,
        .gapLo = gapLo,
        .gapHi = gapHi,
        .sillY = sillY,
        .headY = headY,
    });
}

fn gableInto(b: *Builder, rng: *Rng, z: f32, hw: f32, eave: f32, ridge: f32) void {
    b.setMat(.stone);
    const STEPS = 7;
    var i: i32 = 0;
    while (i < STEPS) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, STEPS);
        const y = mathx.lerpF(eave, ridge, t);
        const w = hw * (1.0 - t);
        b.addBox(v3(0, y, z), v3(w, rng.signed() * 0.012, 0), v3(0, (ridge - eave) / (2.0 * @as(f32, STEPS)), 0), v3(0, 0, TH * 0.9), if (rng.float() < 0.25) STONE_LT else STONE);
    }
}

fn roofInto(b: *Builder, rng: *Rng, hw: f32, hl: f32, eave: f32, ridge: f32) void {
    b.setMat(.stone);
    const COURSES = 8;
    for ([_]f32{ -1, 1 }) |s| {
        var i: i32 = 0;
        while (i < COURSES) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, COURSES);
            const y = mathx.lerpF(eave, ridge, t);
            const x = s * hw * (1.0 - t);
            b.addBox(
                v3(x, y, 0),
                v3(hw / @as(f32, COURSES) * 0.62, -(ridge - eave) / @as(f32, COURSES) * 0.5 * s, 0),
                v3(0, 0.055, 0),
                v3(0, 0, hl + 0.34),
                if (rng.float() < 0.3) SLATE else if (rng.float() < 0.5) STONE_DK else STONE,
            );
        }
    }
    b.setMat(.wood);
    b.addBox(v3(0, ridge + 0.06, 0), v3(0.16, 0, 0), v3(0, 0.10, 0), v3(0, 0, hl + 0.30), TIMBER_DK);
}

pub fn manorMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7160);
    const hw = MANOR_HW;
    const hl = MANOR_HL;
    const s1: f32 = 3.10;
    const s2: f32 = MANOR_EAVE - s1;

    storeyRun(&b, &rng, -hw, -hl, hw, -hl, s1, 0, MANOR_DOOR_X0, MANOR_DOOR_X1, -0.1, 2.55);
    storeyRun(&b, &rng, -hw, hl, hw, hl, s1, 0, -0.75, 0.75, 1.25, 2.55);
    storeyRun(&b, &rng, -hw, -hl, -hw, hl, s1, 0, -0.70, 0.70, 1.25, 2.55);
    storeyRun(&b, &rng, hw, -hl, hw, hl, s1, 0, -0.70, 0.70, 1.25, 2.55);

    storeyRun(&b, &rng, -hw, -hl, hw, -hl, s2, s1, -0.70, 0.70, s1 + 0.9, s1 + 2.3);
    storeyRun(&b, &rng, -hw, hl, hw, hl, s2, s1, -0.70, 0.70, s1 + 0.9, s1 + 2.3);
    storeyRun(&b, &rng, -hw, -hl, -hw, hl, s2, s1, -0.70, 0.70, s1 + 0.9, s1 + 2.3);
    storeyRun(&b, &rng, hw, -hl, hw, hl, s2, s1, -0.70, 0.70, s1 + 0.9, s1 + 2.3);

    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sz| {
            art.quoinsInto(&b, &rng, sx * hw, sz * hl, 0, COURSE_H, coursesFor(MANOR_EAVE), TH * 1.36, TH * 0.98);
        }
    }
    b.setMat(.stone);
    b.addBox(v3(0, s1 + 0.12, -hl), v3(hw + 0.12, rng.signed() * 0.010, 0), v3(0, 0.11, 0), v3(0, 0, TH * 1.24), STONE_LT);
    lintelInto(&b, &rng, 0, 2.55, (MANOR_DOOR_X1 - MANOR_DOOR_X0) + 0.80);

    for ([_]f32{ -hl, hl }) |z| gableInto(&b, &rng, z, hw, MANOR_EAVE, MANOR_TOP - 0.90);
    roofInto(&b, &rng, hw, hl, MANOR_EAVE, MANOR_TOP - 0.90);

    _ = art.courseStack(&b, &rng, hw - 1.30, MANOR_EAVE - 0.4, hl + 0.34, 1.05, 0.95, 0.52, 4, 0.10, null);
    b.setMat(.stone);
    b.addCube(v3(hw - 1.30, MANOR_TOP - 0.30, hl + 0.34), v3(1.24, 0.26, 1.10), STONE_LT);

    weatherInto(&b, &rng, hw * 2, MANOR_EAVE, .worn);
    return b.toModel(shader);
}

pub const HALL_HW: f32 = 4.60;
pub const HALL_HL: f32 = 9.00;
pub const HALL_EAVE: f32 = 5.40;
pub const HALL_TOP: f32 = 8.90;
pub const HALL_DOOR_X0: f32 = -1.05;
pub const HALL_DOOR_X1: f32 = 1.05;
/// Side-wall panels per side and the share of the half-length each one runs; the gaps between them are the hall's light slots, so the run must stay under the pitch.
const HALL_BAYS: i32 = 4;
const HALL_BAY_RUN: f32 = 0.42;
const HALL_PIERS: i32 = 5;

comptime {
    std.debug.assert(HALL_BAY_RUN < 2.0 / @as(f32, HALL_BAYS));
}

pub fn greatHallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7161);
    const hw = HALL_HW;
    const hl = HALL_HL;
    storeyRun(&b, &rng, -hw, -hl, hw, -hl, HALL_EAVE, 0, HALL_DOOR_X0, HALL_DOOR_X1, -0.1, 3.20);
    storeyRun(&b, &rng, -hw, hl, hw, hl, HALL_EAVE, 0, -0.80, 0.80, 2.2, 4.1);
    for ([_]f32{ -1, 1 }) |s| {
        var i: i32 = 0;
        while (i < HALL_BAYS) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, HALL_BAYS);
            const z0 = -hl + t * 2 * hl - HALL_BAY_RUN * hl * 0.5;
            const z1 = z0 + HALL_BAY_RUN * hl;
            storeyRun(&b, &rng, s * hw, z0, s * hw, z1, HALL_EAVE, 0, -0.62, 0.62, 2.3, 4.2);
        }
        var p: i32 = 0;
        while (p < HALL_PIERS) : (p += 1) {
            const z = -hl + (@as(f32, @floatFromInt(p)) + 0.5) * (2 * hl / @as(f32, HALL_PIERS));
            _ = art.courseStack(&b, &rng, s * (hw + 0.40), 0, z, 0.72, 0.70, 0.52, coursesFor(HALL_EAVE * 0.72), 0.16, null);
        }
    }
    for ([_]f32{ -hl, hl }) |z| gableInto(&b, &rng, z, hw, HALL_EAVE, HALL_TOP - 0.70);
    roofInto(&b, &rng, hw, hl, HALL_EAVE, HALL_TOP - 0.70);
    lintelInto(&b, &rng, 0, 3.20, (HALL_DOOR_X1 - HALL_DOOR_X0) + 0.90);
    weatherInto(&b, &rng, hw * 2, HALL_EAVE, .worn);
    return b.toModel(shader);
}

pub const TOWERHOUSE_HALF: f32 = 3.30;
pub const TOWERHOUSE_EAVE: f32 = 9.20;
pub const TOWERHOUSE_TOP: f32 = 10.60;
pub const TOWERHOUSE_DOOR_X0: f32 = -0.85;
pub const TOWERHOUSE_DOOR_X1: f32 = 0.85;

pub fn towerHouseMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = Rng.init(7162);
    const h = TOWERHOUSE_HALF;
    storeyRun(&b, &rng, -h, -h, h, -h, TOWERHOUSE_EAVE, 0, TOWERHOUSE_DOOR_X0, TOWERHOUSE_DOOR_X1, -0.1, 2.45);
    storeyRun(&b, &rng, -h, h, h, h, TOWERHOUSE_EAVE, 0, -0.62, 0.62, 3.6, 5.0);
    storeyRun(&b, &rng, -h, -h, -h, h, TOWERHOUSE_EAVE, 0, -0.62, 0.62, 6.1, 7.5);
    storeyRun(&b, &rng, h, -h, h, h, TOWERHOUSE_EAVE, 0, -0.62, 0.62, 3.6, 5.0);
    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sz| {
            art.quoinsInto(&b, &rng, sx * h, sz * h, 0, COURSE_H, coursesFor(TOWERHOUSE_EAVE), TH * 1.40, TH * 1.00);
        }
    }
    b.setMat(.stone);
    b.addBox(v3(0, TOWERHOUSE_EAVE + 0.16, 0), v3(h + 0.42, rng.signed() * 0.012, 0), v3(0, 0.16, 0), v3(0, 0, h + 0.42), STONE_LT);
    const MERLONS = 5;
    for ([_]f32{ -1, 1 }) |s| {
        var i: i32 = 0;
        while (i < MERLONS) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, MERLONS);
            const p = -h + t * 2 * h;
            const mh = rng.range(0.82, 1.06);
            b.addCube(v3(p, TOWERHOUSE_EAVE + 0.32 + mh * 0.5, s * (h + 0.26)), v3(0.72, mh, 0.42), if (rng.float() < 0.3) STONE_DK else STONE);
            b.addCube(v3(s * (h + 0.26), TOWERHOUSE_EAVE + 0.32 + mh * 0.5, p), v3(0.42, mh, 0.72), if (rng.float() < 0.3) STONE_DK else STONE);
        }
    }
    lintelInto(&b, &rng, 0, 2.45, (TOWERHOUSE_DOOR_X1 - TOWERHOUSE_DOOR_X0) + 0.80);
    weatherInto(&b, &rng, h * 2, TOWERHOUSE_EAVE, .worn);
    return b.toModel(shader);
}

test "the kit is cut to one grid" {
    try std.testing.expectEqual(MOD, HALF * 2);
    try std.testing.expectEqual(MOD, SLAB);
    try std.testing.expectEqual(MOD, VAULT_SPAN);
}

test "a broken wall falls from full height to a stub and never rises again" {
    var prev: f32 = 2.0;
    var i: i32 = 0;
    while (i <= 10) : (i += 1) {
        const f = breakAt(@as(f32, @floatFromInt(i)) / 10.0);
        try std.testing.expect(f <= prev + 1e-6);
        prev = f;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), breakAt(0), 1e-5);
    try std.testing.expectApproxEqAbs(BREAK_LOW, breakAt(1.0), 1e-5);
}
