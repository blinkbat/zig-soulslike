const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");

pub const Style = enum { auto, grain, smoke, spore, flame, frost, spark, chaos, blood, flash, glow };
const CELL = 96;
const COLS = 4;
const ROWS = std.enums.values(Style).len;
var atlas: ?rl.Texture2D = null;

fn hash(x: i32, y: i32, seed: u32) f32 {
    var n = @as(u32, @bitCast(x)) *% 374761393 +% @as(u32, @bitCast(y)) *% 668265263 +% seed *% 2246822519;
    n = (n ^ (n >> 13)) *% 1274126177;
    return @as(f32, @floatFromInt((n ^ (n >> 16)) & 65535)) / 65535.0;
}

fn noise(x: f32, y: f32, seed: u32) f32 {
    const ix: i32 = @intFromFloat(@floor(x));
    const iy: i32 = @intFromFloat(@floor(y));
    const u = mathx.smoothstep(0, 1, x - @floor(x));
    const v = mathx.smoothstep(0, 1, y - @floor(y));
    return mathx.lerpF(mathx.lerpF(hash(ix, iy, seed), hash(ix + 1, iy, seed), u),
        mathx.lerpF(hash(ix, iy + 1, seed), hash(ix + 1, iy + 1, seed), u), v);
}

pub fn pixel(style: Style, x: f32, y: f32) rl.Color {
    return variantPixel(style, x, y, 0);
}

fn variantPixel(style: Style, x: f32, y: f32, variant: u32) rl.Color {
    const d = @sqrt(x * x + y * y);
    const n = noise(x * 4 + 13, y * 4 + 8, @as(u32, @intFromEnum(style)) + variant * 173);
    const fine = noise(x * 11 + 5, y * 11 + 4, 71);
    const edge = 1 - mathx.smoothstep(0.70, 0.98, d);
    var a: f32 = 0;
    var light: f32 = 1;
    switch (style) {
        .smoke, .spore, .chaos => {
            const body = mathx.clampF(1 - d * d * (1.12 + 0.42 * n), 0, 1);
            a = body * edge * (0.40 + 0.60 * n) * (0.78 + 0.22 * fine);
            light = mathx.clampF(0.69 - y * 0.23 - x * 0.13 + (n - 0.5) * 0.30, 0.32, 1);
            if (style == .chaos) a *= 0.62 + 0.38 * @sin(d * 18 + n * 7);
        },
        .flame => {
            const bend = x + (n - 0.5) * 0.48;
            const width = 0.29 + (y + 1) * 0.20;
            a = mathx.clampF(1 - @abs(bend) / width, 0, 1) * edge * (0.24 + 0.76 * n);
            light = 0.72 + 0.28 * mathx.clampF(1 - d, 0, 1);
        },
        .frost => {
            const diamond = @abs(x) + @abs(y) * 0.70;
            a = (1 - mathx.smoothstep(0.24, 0.85, diamond)) * edge;
            light = if (x > 0) 0.75 else 1;
        },
        .spark => a = @exp(-x * x * 28 - y * y * 3.8) * edge,
        .blood => {
            const ragged = d + (n - 0.5) * 0.27;
            a = 1 - mathx.smoothstep(0.28, 0.66, ragged);
            for (0..5) |i| {
                const k: i32 = @intCast(i);
                const angle = hash(k, 4, variant + 27) * std.math.tau;
                const r = 0.54 + hash(k, 6, variant + 27) * 0.24;
                const dx = x - mathx.cosf(angle) * r;
                const dy = y - mathx.sinf(angle) * r;
                const spot = @sqrt(dx * dx + dy * dy * 1.6);
                a = @max(a, 1 - mathx.smoothstep(0.025, 0.055 + hash(k, 9, variant + 27) * 0.08, spot));
            }
            a *= edge;
            light = mathx.clampF(0.75 - y * 0.30 + fine * 0.12, 0.4, 1);
        },
        .flash => {
            const rays = @exp(-@abs(x) * 65) * @exp(-@abs(y) * 2.5) +
                @exp(-@abs(y) * 65) * @exp(-@abs(x) * 2.5);
            a = mathx.clampF(@exp(-d * d * 32) + rays, 0, 1) * edge;
        },
        .grain => a = (1 - mathx.smoothstep(0.35, 0.90, d + (n - 0.5) * 0.23)) * edge,
        .auto, .glow => a = @exp(-d * d * 5.5) * edge,
    }
    const c = mathx.u8f(light * 255);
    return .{ .r = c, .g = c, .b = c, .a = mathx.u8f(a * 255) };
}

pub fn texture() rl.Texture2D {
    if (atlas) |t| return t;
    const img = rl.genImageColor(CELL * COLS, CELL * ROWS, rl.Color.blank);
    defer rl.unloadImage(img);
    const pixels: [*]rl.Color = @ptrCast(@alignCast(img.data));
    for (std.enums.values(Style)) |style| {
        const row: usize = @intFromEnum(style);
        for (0..COLS) |variant| {
            for (0..CELL) |y| {
                for (0..CELL) |x| {
                    const fx = (@as(f32, @floatFromInt(x)) + 0.5) / CELL * 2 - 1;
                    const fy = (@as(f32, @floatFromInt(y)) + 0.5) / CELL * 2 - 1;
                    pixels[(row * CELL + y) * (CELL * COLS) + variant * CELL + x] = variantPixel(style, fx, fy, @intCast(variant));
                }
            }
        }
    }
    atlas = rl.loadTextureFromImage(img) catch @panic("particle atlas");
    rl.setTextureFilter(atlas.?, .bilinear);
    return atlas.?;
}

pub fn quad(style: Style, seed: f32, corners: [4]rl.Vector3) void {
    const du = 1.0 / @as(f32, COLS);
    const dv = 1.0 / @as(f32, ROWS);
    const u = @mod(@floor(@abs(seed) * 7), COLS) * du;
    const v = @as(f32, @floatFromInt(@intFromEnum(style))) * dv;
    const coords = [4][2]f32{ .{ u, v }, .{ u + du, v }, .{ u + du, v + dv }, .{ u, v + dv } };
    for (corners, coords) |p, uv| {
        rl.gl.rlTexCoord2f(uv[0], uv[1]);
        rl.gl.rlVertex3f(p.x, p.y, p.z);
    }
}

test "particle atlas has transparent borders and distinct silhouettes" {
    for (std.enums.values(Style)) |style| {
        try std.testing.expectEqual(@as(u8, 0), pixel(style, 1, 0).a);
        try std.testing.expectEqual(@as(u8, 0), pixel(style, 0, -1).a);
        try std.testing.expect(pixel(style, 0, 0).a > 0);
    }
    try std.testing.expect(pixel(.flash, 0, 0.6).a > pixel(.flash, 0.4, 0.4).a);
    try std.testing.expect(pixel(.spark, 0, 0.5).a > pixel(.spark, 0.5, 0).a);
}

