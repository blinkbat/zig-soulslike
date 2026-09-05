const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const props = @import("../props/props.zig");
const envmod = @import("../world/env.zig");
const collision = @import("../core/collision.zig");
const wf = @import("../world/worldfmt.zig");
const gfx = @import("../gfx/gfx.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");

const Kind = props.Kind;
const rgba = mathx.rgba;
const v3 = mathx.v3;
const fi = uiart.fi;

/// The one wall/water classification, read by the editor's minimap and by the book's chart.
pub const Mark = enum { water, wall, tree, fire };

/// A wall is solid AND long — measured, a cliff is 16.6 m across, a ruined wall 6.8, and a pillar 1.6.
pub const WALL_W: f32 = 4.0;

fn footprintW(k: Kind) f32 {
    var w: f32 = 0;
    // The row's own parts, not `partsOf`: this classifies a glyph at comptime, and a cliff's fitted set is a runtime build.
    for (props.info(k).parts) |p| {
        const dx = @abs(p.bx - p.ax);
        const dz = @abs(p.bz - p.az);
        w = @max(w, @max(dx, dz) + 2.0 * p.r);
    }
    return w;
}

fn markOf(k: Kind) ?Mark {
    return switch (props.group(k)) {
        .fire => .fire,
        .water => .water,
        .trees => .tree,
        else => if (props.info(k).solid and footprintW(k) >= WALL_W) .wall else null,
    };
}

const MARK_OF = blk: {
    @setEvalBranchQuota(200000);
    var out: [props.NK]?Mark = undefined;
    for (0..props.NK) |i| out[i] = markOf(@enumFromInt(i));
    break :blk out;
};

const WIDTH_OF = blk: {
    @setEvalBranchQuota(200000);
    var out: [props.NK]f32 = undefined;
    for (0..props.NK) |i| out[i] = footprintW(@enumFromInt(i));
    break :blk out;
};

pub fn markFor(k: Kind) ?Mark {
    return MARK_OF[@intFromEnum(k)];
}

pub fn widthFor(k: Kind) f32 {
    return WIDTH_OF[@intFromEnum(k)];
}

/// `props.INFO` bounds: sapling 3.8, tree 5.3 | willow 8.0, snag 8.2, birch 10.0, conifer 12.5, bigtree 13-14.
pub const BIG_TREE_R: f32 = 7.0;

const BIG_TREE_OF = blk: {
    @setEvalBranchQuota(200000);
    var out: [props.NK]bool = undefined;
    for (0..props.NK) |i| {
        const k: Kind = @enumFromInt(i);
        out[i] = markOf(k) == .tree and props.info(k).bound >= BIG_TREE_R;
    }
    break :blk out;
};

pub fn bigTree(k: Kind) bool {
    return BIG_TREE_OF[@intFromEnum(k)];
}

pub const GROUND = rgba(18, 20, 14, 255);
pub const WALL = rgba(146, 140, 126, 235);

pub fn liquidSwatch(l: wf.Liquid) rl.Color {
    return switch (l) {
        .water => rgba(32, 55, 62, 255),
        .oil => rgba(26, 24, 22, 255),
        .fungal => rgba(158, 84, 66, 255),
        .lava => rgba(206, 88, 30, 255),
    };
}

/// `wf.Liquid` PLUS ONE — `blitField` reads 0 as "nothing here", so water (ordinal 0) needs the shift.
pub fn liquidByte(v: u8) rl.Color {
    return liquidSwatch(@enumFromInt(@min(v -| 1, wf.Liquid.N - 1)));
}

pub fn toFlat(wx: f32, wz: f32, half: f32, ox: i32, oy: i32, across: f32) rl.Vector2 {
    const per = perMetre(half, across);
    return .{
        .x = fi(ox) + (wx + half) * per,
        .y = fi(oy) + (wz + half) * per,
    };
}

pub fn onFlat(wx: f32, wz: f32, half: f32) bool {
    return @abs(wx) <= half and @abs(wz) <= half;
}

pub fn perMetre(half: f32, across: f32) f32 {
    return if (half > 0) across / (2.0 * half) else 0;
}

pub fn blitField(cells: []const u8, n: usize, px: i32, py: i32, inner: f32, swatch: *const fn (u8) rl.Color) void {
    // Unreachable today (every caller passes a comptime grid width); the same shape was a live crash in `book.rowStep`.
    if (n == 0) return;
    const cellPx = inner / @as(f32, @floatFromInt(n));
    for (0..n) |cz| {
        const row = cells[cz * n ..][0..n];
        var cx: usize = 0;
        while (cx < n) {
            const id = row[cx];
            if (id == 0) {
                cx += 1;
                continue;
            }
            var run: usize = 1;
            while (cx + run < n and row[cx + run] == id) run += 1;
            rl.drawRectangleRec(.{
                .x = fi(px) + @as(f32, @floatFromInt(cx)) * cellPx,
                .y = fi(py) + @as(f32, @floatFromInt(cz)) * cellPx,
                .width = @ceil(@as(f32, @floatFromInt(run)) * cellPx),
                .height = @ceil(cellPx),
            }, swatch(id));
            cx += run;
        }
    }
}

pub const ZOOM_MIN: f32 = 1.0;
pub const ZOOM_MAX: f32 = 5.0;
const ZOOM_RATE: f32 = 2.4;
const PAN_RATE: f32 = 1.6;
const PAN_STEP: f32 = 0.15;

/// `pan` is in MAP UNITS: ±1 is the map's own edge, whatever `half` is.
pub const Lens = struct {
    zoom: f32 = ZOOM_MIN,
    pan: rl.Vector2 = .{ .x = 0, .y = 0 },

    /// THE ONLY READ OF `zoom`: `Book.debugMap` writes the field straight through, so a magnification out of range reached the scale bar and the grid pitch while the blit was clamped.
    pub fn mag(self: Lens) f32 {
        return mathx.clampF(self.zoom, ZOOM_MIN, ZOOM_MAX);
    }

    pub fn zoomBy(self: *Lens, dv: f32, dt: f32) void {
        if (dv == 0) return;
        self.zoom = mathx.clampF(self.zoom + dv * ZOOM_RATE * dt, ZOOM_MIN, ZOOM_MAX);
        self.clampPan();
    }

    pub fn panBy(self: *Lens, v: rl.Vector2, dt: f32) void {
        if (v.x == 0 and v.y == 0) return;
        const k = PAN_RATE * dt / self.mag();
        self.pan.x += v.x * k;
        self.pan.y += v.y * k;
        self.clampPan();
    }

    pub fn panStep(self: *Lens, dx: f32, dy: f32) void {
        if (dx == 0 and dy == 0) return;
        const k = PAN_STEP / self.mag();
        self.pan.x += dx * k;
        self.pan.y += dy * k;
        self.clampPan();
    }

    pub fn centreOn(self: *Lens, wx: f32, wz: f32, half: f32) void {
        if (!(half > 0)) return;
        self.pan = .{ .x = wx / half, .y = wz / half };
        self.clampPan();
    }

    fn clampPan(self: *Lens) void {
        const lim = mathx.maxF(0, 1.0 - 1.0 / self.mag());
        self.pan.x = mathx.clampF(self.pan.x, -lim, lim);
        self.pan.y = mathx.clampF(self.pan.y, -lim, lim);
    }
};

/// One bit a cell: 4.38 m on the default 560 m map, 16,384 characters in the save.
pub const SEEN_N: usize = 128;
pub const SEEN_CELLS: usize = SEEN_N * SEEN_N;

/// Metres. Over the widest creature ring (`fungalduo`'s 30), under a third of the 320 m draw distance.
pub const REVEAL_R: f32 = 48.0;

/// **THE CHART IS WHAT HE HAS SEEN, NOT WHERE HE HAS BEEN.** The look is taken from his eye down onto the
/// ground out there, so this is how far under the eye the far end sits — knee height on his own body.
pub const EYE_DROP: f32 = 0.65;

/// How far the look STOPS SHORT of the cell it is asking about, as a share of a cell. The near face of a wall
/// is a thing you can stand and look at, so the cell holding it charts; the ground behind it does not.
pub const NEAR_FACE: f32 = 0.5;

/// `look` answers `sees(from, to)` — the `Env` in the game, and `{}` where there is no world to be blocked by.
fn clearTo(look: anytype, from: rl.Vector3, to: rl.Vector3) bool {
    if (comptime @TypeOf(look) == void) return true;
    return look.sees(from, to);
}

/// `to` hauled back toward `from` by `d`, and never past `from` itself.
fn shortOf(from: rl.Vector3, to: rl.Vector3, d: f32) rl.Vector3 {
    const len = mathx.lenV(mathx.subV(to, from));
    if (len <= d) return from;
    return mathx.lerpV(from, to, (len - d) / len);
}

pub const Seen = struct {
    cell: [SEEN_CELLS]bool = [_]bool{false} ** SEEN_CELLS,
    /// Bumped only when a cell TURNS — the fog sheet repaints off this and nothing else.
    gen: u64 = 1,
    /// Last reveal's centre cell; -1 forces one.
    at: i32 = -1,

    pub fn clear(self: *Seen) void {
        self.cell = [_]bool{false} ** SEEN_CELLS;
        self.gen +%= 1;
        self.at = -1;
    }

    pub fn count(self: *const Seen) usize {
        var n: usize = 0;
        for (self.cell) |c| {
            if (c) n += 1;
        }
        return n;
    }

    /// Asked once a CELL, not once a frame: re-marking the same disc is 380 cells of nothing. `at` is his EYE.
    pub fn walked(self: *Seen, at: rl.Vector3, half: f32, look: anytype) void {
        if (!(half > 0)) return;
        const here = cellOf(at.x, at.z, half) orelse return;
        if (self.at == @as(i32, @intCast(here))) return;
        self.at = @intCast(here);
        // The cell he is standing in, whatever he is standing in: a doorway is inside a solid.
        if (!self.cell[here]) {
            self.cell[here] = true;
            self.gen +%= 1;
        }
        const per = 2.0 * half / @as(f32, @floatFromInt(SEEN_N));
        // Capped at the sheet: uncapped, a map smaller than the radius walks (2n+1)^2 cells of nothing.
        const reach: i32 = @min(@as(i32, @intFromFloat(@ceil(REVEAL_R / per))), @as(i32, @intCast(SEEN_N)));
        const cx: i32 = @intCast(here % SEEN_N);
        const cz: i32 = @intCast(here / SEEN_N);
        const r2 = REVEAL_R * REVEAL_R;
        var dz: i32 = -reach;
        while (dz <= reach) : (dz += 1) {
            const z = cz + dz;
            if (z < 0 or z >= SEEN_N) continue;
            var dx: i32 = -reach;
            while (dx <= reach) : (dx += 1) {
                const x = cx + dx;
                if (x < 0 or x >= SEEN_N) continue;
                // Cell CENTRES, or the disc is a diamond of whole cells.
                const wx = (@as(f32, @floatFromInt(x)) + 0.5) * per - half;
                const wz = (@as(f32, @floatFromInt(z)) + 0.5) * per - half;
                const ex = wx - at.x;
                const ez = wz - at.z;
                if (ex * ex + ez * ez > r2) continue;
                const i = @as(usize, @intCast(z)) * SEEN_N + @as(usize, @intCast(x));
                // BEFORE the look, not after: re-treading known ground would pay for the whole disc again.
                if (self.cell[i]) continue;
                const onto = v3(wx, at.y - EYE_DROP, wz);
                if (!clearTo(look, at, shortOf(at, onto, per * NEAR_FACE))) continue;
                self.cell[i] = true;
                self.gen +%= 1;
            }
        }
    }
};

fn cellOf(wx: f32, wz: f32, half: f32) ?usize {
    if (!onFlat(wx, wz, half)) return null;
    const p = toFlat(wx, wz, half, 0, 0, @floatFromInt(SEEN_N));
    const x: usize = @intFromFloat(mathx.clampF(p.x, 0, @floatFromInt(SEEN_N - 1)));
    const z: usize = @intFromFloat(mathx.clampF(p.y, 0, @floatFromInt(SEEN_N - 1)));
    return z * SEEN_N + x;
}

pub const World = struct {
    map: *const wf.Map,
    env: *const envmod.Env,
    seen: *const Seen,
    at: rl.Vector3,
    facing: f32,
};

/// Painted ONCE in world space and blitted through the lens: per-prop it would be one rect an op a frame, a bill that grows with whatever the author has put on the map.
const CHART_N: i32 = 2048;

var chartRT: ?rl.RenderTexture2D = null;
var chartOf: [wf.NAME_CAP]u8 = [_]u8{0} ** wf.NAME_CAP;
var chartHalf: f32 = 0;
var chartStaged: bool = false;

var fogRT: ?rl.RenderTexture2D = null;
var fogAt: u64 = 0;

pub fn restage() void {
    chartStaged = false;
}

pub fn unload() void {
    if (chartRT) |t| rl.unloadRenderTexture(t);
    chartRT = null;
    chartStaged = false;
    if (fogRT) |t| rl.unloadRenderTexture(t);
    fogRT = null;
    fogAt = 0;
}

const CANOPY = rgba(58, 84, 46, 255);
const CANOPY_CORE = rgba(36, 56, 30, 255);
/// The culling sphere overshoots the crown; three quarters of it reads as the canopy.
const CANOPY_K: f32 = 0.75;

const WALL_EDGE = rgba(6, 6, 5, 255);
/// Metres. ALL the haloes before ANY fill, or each prop's outline lands on its neighbour's.
const HALO_M: f32 = 1.5;
const PAPER = rgba(26, 25, 20, 255);
const GRID = rgba(120, 108, 84, 42);
const GRID_STEP_M: f32 = 50.0;

fn chart(m: *const wf.Map, env: *const envmod.Env) ?rl.RenderTexture2D {
    if (chartRT == null) chartRT = rl.loadRenderTexture(CHART_N, CHART_N) catch null;
    const rt = chartRT orelse return null;
    const swapped = !std.mem.eql(u8, &chartOf, &m.name) or chartHalf != m.half;
    if (chartStaged and !swapped) return rt;
    chartStaged = true;
    chartOf = m.name;
    chartHalf = m.half;
    rl.setTextureFilter(rt.texture, .bilinear);
    rl.beginTextureMode(rt);
    paint(m, env);
    rl.endTextureMode();
    return rt;
}

const SHEET: f32 = @floatFromInt(CHART_N);

var liquidCells: [wf.WATER_CELLS]u8 = [_]u8{0} ** wf.WATER_CELLS;

/// THE PAINTED POOLS AND THE THINGS STANDING IN THEM, ONE IMPLEMENTATION: the chart and the editor's minimap are two scales of the same layer, and it was written twice.
pub fn blitWater(m: *const wf.Map, env: *const envmod.Env, px: i32, py: i32, across: f32) void {
    for (m.water, m.waterKind, 0..) |wet, k, i| liquidCells[i] = if (wet != 0) k + 1 else 0;
    blitField(liquidCells[0..], wf.WATER_N, px, py, across, liquidByte);

    const perM = perMetre(m.half, across);
    for (env.placed()) |*pr| {
        if (pr.gone or markFor(pr.kind) != .water) continue;
        if (!onFlat(pr.pos.x, pr.pos.z, m.half)) continue;
        const p = toFlat(pr.pos.x, pr.pos.z, m.half, px, py, across);
        rl.drawCircleV(p, props.info(pr.kind).bound * pr.scale * perM, liquidSwatch(.water));
    }
}

fn paint(m: *const wf.Map, env: *const envmod.Env) void {
    rl.drawRectangle(0, 0, CHART_N, CHART_N, PAPER);
    const perM = perMetre(m.half, SHEET);
    blitWater(m, env, 0, 0, SHEET);

    for (env.placed()) |*pr| {
        if (pr.gone or !bigTree(pr.kind)) continue;
        if (!onFlat(pr.pos.x, pr.pos.z, m.half)) continue;
        const p = toFlat(pr.pos.x, pr.pos.z, m.half, 0, 0, SHEET);
        const r = props.info(pr.kind).bound * pr.scale * perM * CANOPY_K;
        rl.drawCircleV(p, r, CANOPY);
        rl.drawCircleV(p, r * 0.45, CANOPY_CORE);
    }

    for ([2]bool{ true, false }) |halo| {
        for (env.placed()) |*pr| {
            if (pr.gone or markFor(pr.kind) != .wall) continue;
            if (!onFlat(pr.pos.x, pr.pos.z, m.half)) continue;
            strokeProp(pr, m.half, perM, halo);
        }
    }
}

fn strokeProp(pr: *const envmod.Prop, half: f32, perM: f32, halo: bool) void {
    const nfo = props.info(pr.kind);
    const col = if (halo) WALL_EDGE else WALL;
    const grow: f32 = if (halo) HALO_M else 0;
    const parts = props.partsOf(pr.kind);
    if (parts.len == 0) {
        const p = toFlat(pr.pos.x, pr.pos.z, half, 0, 0, SHEET);
        rl.drawCircleV(p, (nfo.bound * pr.scale + grow) * perM, col);
        return;
    }
    const fr = envmod.PropFrame.of(pr);
    for (parts) |part| {
        const a3 = fr.at(part.ax, 0, part.az);
        const b3 = fr.at(part.bx, 0, part.bz);
        const r = mathx.maxF((part.r * pr.scale + grow) * perM, 1.0);
        if (part.flat) {
            // Square ends: the box is one thick line run out by its own radius, no caps.
            var sol = collision.capsule(a3.x, a3.z, b3.x, b3.z, part.r * pr.scale + grow);
            sol.flat = true;
            const f = collision.frameOf(sol);
            const p0 = toFlat(f.cx - f.ux * f.hl, f.cz - f.uz * f.hl, half, 0, 0, SHEET);
            const p1 = toFlat(f.cx + f.ux * f.hl, f.cz + f.uz * f.hl, half, 0, 0, SHEET);
            rl.drawLineEx(p0, p1, r * 2.0, col);
            continue;
        }
        const a = toFlat(a3.x, a3.z, half, 0, 0, SHEET);
        const b = toFlat(b3.x, b3.z, half, 0, 0, SHEET);
        rl.drawCircleV(a, r, col);
        if (mathx.dist2XZ(a3, b3) > 1e-6) {
            rl.drawCircleV(b, r, col);
            rl.drawLineEx(a, b, r * 2.0, col);
        }
    }
}

const UNSEEN = rgba(13, 12, 10, 255);

/// `GL_ONE, GL_ZERO`: raylib blends a target's OWN alpha by `SRC_ALPHA`, so a hole punched with ordinary blending comes back half-opaque. BILINEAR is what makes a binary mask a soft edge.
fn fogSheet(seen: *const Seen) ?rl.RenderTexture2D {
    const n: i32 = @intCast(SEEN_N);
    if (fogRT == null) {
        fogRT = rl.loadRenderTexture(n, n) catch null;
        if (fogRT) |t| rl.setTextureFilter(t.texture, .bilinear);
        fogAt = 0;
    }
    const rt = fogRT orelse return null;
    if (fogAt == seen.gen) return rt;
    fogAt = seen.gen;
    rl.beginTextureMode(rt);
    rl.gl.rlSetBlendFactors(gfx.GL_ONE, gfx.GL_ZERO, gfx.GL_FUNC_ADD);
    rl.beginBlendMode(.custom);
    rl.drawRectangle(0, 0, n, n, UNSEEN);
    // A `bool` IS a byte of 0 or 1 — exactly the "0 is nothing here" `blitField` already encodes.
    blitField(std.mem.sliceAsBytes(seen.cell[0..]), SEEN_N, 0, 0, @floatFromInt(SEEN_N), holePunch);
    rl.endBlendMode();
    rl.endTextureMode();
    return rt;
}

fn holePunch(v: u8) rl.Color {
    _ = v;
    return mathx.withAlpha(UNSEEN, 0);
}

const HERE = rgba(255, 236, 190, 255);
const HERE_HALO = rgba(236, 178, 70, 255);
const MARK_PX: f32 = 11.0;

/// Hero yaw 0 faces +Z and +Z is DOWN the sheet, so the bearing on paper is `(sin yaw, cos yaw)`.
fn drawHere(cx: f32, cy: f32, facing: f32) void {
    const dx = mathx.sinf(facing);
    const dy = mathx.cosf(facing);
    const px = -dy;
    const py = dx;
    rl.drawCircleGradient(@intFromFloat(cx), @intFromFloat(cy), MARK_PX * 3.0, mathx.withAlpha(HERE_HALO, 90), mathx.withAlpha(HERE_HALO, 0));
    const tip = rl.Vector2{ .x = cx + dx * MARK_PX * 1.35, .y = cy + dy * MARK_PX * 1.35 };
    const back = rl.Vector2{ .x = cx - dx * MARK_PX * 0.75, .y = cy - dy * MARK_PX * 0.75 };
    const l = rl.Vector2{ .x = back.x + px * MARK_PX * 0.80, .y = back.y + py * MARK_PX * 0.80 };
    const r = rl.Vector2{ .x = back.x - px * MARK_PX * 0.80, .y = back.y - py * MARK_PX * 0.80 };
    const notch = rl.Vector2{ .x = cx - dx * MARK_PX * 0.18, .y = cy - dy * MARK_PX * 0.18 };
    uiart.triangle(tip, l, notch, WALL_EDGE);
    uiart.triangle(tip, notch, r, WALL_EDGE);
    const k: f32 = 0.80;
    const tipI = rl.Vector2{ .x = cx + dx * MARK_PX * 1.35 * k, .y = cy + dy * MARK_PX * 1.35 * k };
    const lI = rl.Vector2{ .x = back.x + px * MARK_PX * 0.80 * k, .y = back.y + py * MARK_PX * 0.80 * k };
    const rI = rl.Vector2{ .x = back.x - px * MARK_PX * 0.80 * k, .y = back.y - py * MARK_PX * 0.80 * k };
    uiart.triangle(tipI, lI, notch, HERE);
    uiart.triangle(tipI, notch, rI, HERE);
}

pub fn niceMetres(want: f32) f32 {
    if (!(want > 0)) return 1;
    const p = @floor(std.math.log10(want));
    const pow = std.math.pow(f32, 10, p);
    const n = want / pow;
    const step: f32 = if (n < 1.5) 1 else if (n < 3.5) 2 else if (n < 7.5) 5 else 10;
    return step * pow;
}

/// TEXELS, top-down. A render texture reads bottom-up: source `y` is off the far edge and the height negative.
fn windowIn(lens: Lens, across: f32) rl.Rectangle {
    const w = across / lens.mag();
    const cx = (lens.pan.x + 1.0) * 0.5 * across;
    const cy = (lens.pan.y + 1.0) * 0.5 * across;
    const x = mathx.clampF(cx - w * 0.5, 0, across - w);
    const yTop = mathx.clampF(cy - w * 0.5, 0, across - w);
    return .{ .x = x, .y = across - yTop - w, .width = w, .height = -w };
}

fn window(lens: Lens) rl.Rectangle {
    return windowIn(lens, SHEET);
}

pub fn draw(x: i32, y: i32, w: i32, h: i32, world: ?World, lens: Lens) void {
    // A square map gets a square face, WELL included, or the scale bar is a lie.
    const side = @min(w, h);
    const fx = x + @divTrunc(w - side, 2);
    const fy = y + @divTrunc(h - side, 2);
    uiart.well(fx, fy, side, side, 220);
    const wd = world orelse {
        const s = "(no chart)";
        hud.text(s, fx + @divTrunc(side - hud.textW(s, hud.SMALL), 2), fy + @divTrunc(side, 2), hud.SMALL, uiart.TEXT_DIM);
        rl.drawRectangleLinesEx(uiart.rect(fx, fy, side, side), 1, mathx.withAlpha(uiart.GILT_DIM, 90));
        return;
    };
    const m = wd.map;
    // BOTH targets before any draw: `endTextureMode` restores the DEFAULT framebuffer, not the one before it.
    const rt = chart(m, wd.env) orelse return;
    const fog = fogSheet(wd.seen) orelse return;

    const src = window(lens);
    const dst = uiart.rect(fx, fy, side, side);

    rl.beginScissorMode(fx, fy, side, side);
    rl.drawRectangle(fx, fy, side, side, PAPER);
    rl.gl.rlSetBlendFactors(gfx.GL_ONE, gfx.GL_ZERO, gfx.GL_FUNC_ADD);
    rl.beginBlendMode(.custom);
    rl.drawTexturePro(rt.texture, src, dst, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
    rl.endBlendMode();

    rl.drawTexturePro(fog.texture, windowIn(lens, @floatFromInt(SEEN_N)), dst, .{ .x = 0, .y = 0 }, 0, rl.Color.white);

    const pxPerM = perMetre(m.half, @as(f32, @floatFromInt(side)) * lens.mag());
    drawGrid(fx, fy, side, m.half, lens);

    if (onFlat(wd.at.x, wd.at.z, m.half)) {
        const p = lensPoint(wd.at.x, wd.at.z, m.half, fx, fy, side, lens);
        drawHere(p.x, p.y, wd.facing);
    }
    rl.endScissorMode();

    rl.drawRectangleLinesEx(dst, 1, mathx.withAlpha(uiart.GILT_DIM, 110));
    uiart.cornerJewels(fx + 2, fy + 2, side - 4, side - 4, 2.4, mathx.withAlpha(uiart.GILT, 170));
    drawScale(fx, fy, side, pxPerM);
    drawLegend(fx, fy, m);
}

fn lensPoint(wx: f32, wz: f32, half: f32, fx: i32, fy: i32, side: i32, lens: Lens) rl.Vector2 {
    const src = window(lens);
    const inSheet = toFlat(wx, wz, half, 0, 0, SHEET);
    const yTop = SHEET - src.y + src.height;
    const k = @as(f32, @floatFromInt(side)) / src.width;
    return .{ .x = fi(fx) + (inSheet.x - src.x) * k, .y = fi(fy) + (inSheet.y - yTop) * k };
}

/// Screen space, AFTER the blit: one pixel wide at every zoom, and the pitch stays a round number of metres.
fn drawGrid(fx: i32, fy: i32, side: i32, half: f32, lens: Lens) void {
    const step = GRID_STEP_M * @max(1.0, @round(2.0 / lens.mag()));
    var wx = -half + @mod(half, step);
    while (wx <= half) : (wx += step) {
        const p = lensPoint(wx, 0, half, fx, fy, side, lens);
        rl.drawLineEx(.{ .x = p.x, .y = fi(fy) }, .{ .x = p.x, .y = fi(fy + side) }, 1, GRID);
    }
    var wz = -half + @mod(half, step);
    while (wz <= half) : (wz += step) {
        const p = lensPoint(0, wz, half, fx, fy, side, lens);
        rl.drawLineEx(.{ .x = fi(fx), .y = p.y }, .{ .x = fi(fx + side), .y = p.y }, 1, GRID);
    }
}

fn label(x: i32, y: i32, s: [:0]const u8, size: i32, col: rl.Color) void {
    const w = hud.textW(s, size);
    rl.drawRectangle(x - 6, y - 3, w + 12, hud.lineH(size) + 4, mathx.withAlpha(PAPER, 215));
    hud.text(s, x, y, size, col);
}

fn drawScale(fx: i32, fy: i32, side: i32, pxPerM: f32) void {
    if (!(pxPerM > 0)) return;
    const metres = niceMetres(@as(f32, @floatFromInt(side)) * 0.22 / pxPerM);
    const barW: i32 = @intFromFloat(@round(metres * pxPerM));
    if (barW < 8 or barW > side - 40) return;
    const bx = fx + 14;
    const by = fy + side - 20;
    rl.drawRectangle(bx - 6, by - 9, barW + 12, 20, mathx.withAlpha(PAPER, 215));
    rl.drawRectangle(bx, by, barW, 2, mathx.withAlpha(uiart.GILT, 210));
    rl.drawRectangle(bx, by - 4, 2, 10, mathx.withAlpha(uiart.GILT, 210));
    rl.drawRectangle(bx + barW - 2, by - 4, 2, 10, mathx.withAlpha(uiart.GILT, 210));
    var buf: [24]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d:.0} m", .{metres}) catch return;
    label(bx + barW + 8, by - hud.lineH(hud.TINY) + 4, s, hud.TINY, uiart.TEXT_VALUE);
}

fn drawLegend(fx: i32, fy: i32, m: *const wf.Map) void {
    var buf: [wf.NAME_CAP + 1]u8 = undefined;
    const name = std.fmt.bufPrintZ(&buf, "{s}", .{m.label()}) catch return;
    if (name.len == 0) return;
    label(fx + 14, fy + 12, name, hud.SMALL, mathx.withAlpha(uiart.GILT, 235));
}

test "the lens window never leaves the sheet, and a corner is still reachable" {
    var l = Lens{};
    for (0..64) |_| l.panStep(1, 1);
    try std.testing.expectEqual(@as(f32, 0), l.pan.x);
    try std.testing.expectEqual(@as(f32, 0), l.pan.y);

    l.zoom = ZOOM_MAX;
    for (0..64) |_| l.panStep(1, 1);
    const lim = 1.0 - 1.0 / ZOOM_MAX;
    try std.testing.expectApproxEqAbs(lim, l.pan.x, 1e-5);
    try std.testing.expectApproxEqAbs(lim, l.pan.y, 1e-5);

    const win = window(l);
    try std.testing.expect(win.x >= 0);
    try std.testing.expect(win.x + win.width <= SHEET + 1e-3);
    try std.testing.expect(win.height < 0);
    const corner = toFlat(280, 280, 280, 0, 0, SHEET);
    try std.testing.expect(corner.x >= win.x - 1e-3 and corner.x <= win.x + win.width + 1e-3);
}

test "the window is the whole sheet at rest, and the flip is raylib's own" {
    const win = window(.{});
    try std.testing.expectEqual(@as(f32, 0), win.x);
    try std.testing.expectEqual(@as(f32, 0), win.y);
    try std.testing.expectEqual(SHEET, win.width);
    try std.testing.expectEqual(-SHEET, win.height);
}

test "A MAGNIFICATION OUT OF RANGE IS THE SAME PICTURE AND THE SAME RULER — the blit and the scale bar clamp together" {
    for ([_]f32{ 0, -3, 1e9, std.math.nan(f32) }) |z| {
        const wild = Lens{ .zoom = z };
        try std.testing.expect(wild.mag() >= ZOOM_MIN and wild.mag() <= ZOOM_MAX);
        const win = windowIn(wild, SHEET);
        const same = windowIn(.{ .zoom = wild.mag() }, SHEET);
        try std.testing.expectEqual(same.width, win.width);
        try std.testing.expectEqual(same.x, win.x);
        try std.testing.expectEqual(same.y, win.y);
    }
    var l = Lens{ .zoom = 0 };
    l.panStep(1, 1);
    try std.testing.expect(std.math.isFinite(l.pan.x) and std.math.isFinite(l.pan.y));
}

test "a point maps to the same place through the lens as it does on the sheet" {
    const half: f32 = 280;
    const side: i32 = 700;
    const flat = toFlat(-140, 70, half, 0, 0, @floatFromInt(side));
    const lens = lensPoint(-140, 70, half, 0, 0, side, .{});
    try std.testing.expectApproxEqAbs(flat.x, lens.x, 1e-3);
    try std.testing.expectApproxEqAbs(flat.y, lens.y, 1e-3);

    var l = Lens{ .zoom = 3 };
    l.centreOn(0, 0, half);
    const mid = lensPoint(0, 0, half, 0, 0, side, l);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(side)) * 0.5, mid.x, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(side)) * 0.5, mid.y, 1e-3);
}

test "the hero's bearing on paper is his bearing in the world" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.sinf(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), mathx.cosf(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), mathx.sinf(std.math.pi * 0.5), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.cosf(std.math.pi * 0.5), 1e-6);
    const half: f32 = 100;
    const east = toFlat(10, 0, half, 0, 0, 200);
    const mid = toFlat(0, 0, half, 0, 0, 200);
    try std.testing.expect(east.x > mid.x);
    const south = toFlat(0, 10, half, 0, 0, 200);
    try std.testing.expect(south.y > mid.y);
}

test "a scale bar is only ever 1, 2 or 5 of something" {
    for ([_]f32{ 0.4, 1.2, 3.0, 6.0, 9.0, 40.0, 120.0, 900.0 }) |want| {
        const got = niceMetres(want);
        const p = std.math.pow(f32, 10, @floor(std.math.log10(got)));
        const n = @round(got / p);
        try std.testing.expect(n == 1 or n == 2 or n == 5);
        try std.testing.expect(got > 0);
    }
}

test "EVERY PLACEABLE PROP ANSWERS THE CHART, and a wall is the thing you cannot walk through" {
    var walls: usize = 0;
    var waters: usize = 0;
    for (0..props.NK) |i| {
        const k: Kind = @enumFromInt(i);
        const mk = markFor(k) orelse continue;
        if (mk == .wall) {
            try std.testing.expect(props.info(k).solid);
            try std.testing.expect(widthFor(k) >= WALL_W);
            walls += 1;
        }
        if (mk == .water) waters += 1;
    }
    std.debug.print("\n  chart: {d} of {d} prop kinds draw as WALL, {d} as WATER\n", .{ walls, props.NK, waters });
    try std.testing.expect(walls > 0);
}

test "THE SHEET STARTS BLANK, AND WALKING IT REVEALS A DISC — not a square, and not the whole map" {
    const half: f32 = 280;
    var seen = Seen{};
    try std.testing.expectEqual(@as(usize, 0), seen.count());

    seen.walked(mathx.zero3, half, {});
    const first = seen.count();
    try std.testing.expect(first > 0);

    // pi r^2 over the cell area, against the (2r)^2 a square sweep would give.
    const per = 2.0 * half / @as(f32, @floatFromInt(SEEN_N));
    const disc = std.math.pi * REVEAL_R * REVEAL_R / (per * per);
    const square = 4.0 * REVEAL_R * REVEAL_R / (per * per);
    try std.testing.expect(@as(f32, @floatFromInt(first)) < square * 0.90);
    try std.testing.expectApproxEqRel(disc, @as(f32, @floatFromInt(first)), 0.12);

    const gen = seen.gen;
    seen.walked(mathx.zero3, half, {});
    try std.testing.expectEqual(first, seen.count());
    try std.testing.expectEqual(gen, seen.gen);

    seen.walked(v3(90, 0, 0), half, {});
    try std.testing.expect(seen.count() > first);
    try std.testing.expect(seen.gen > gen);
    std.debug.print("\n  chart reveal: {d} m radius is {d} of {d} cells ({d:.1}% of the sheet), cell {d:.2} m\n", .{
        REVEAL_R, first, SEEN_CELLS, 100.0 * @as(f32, @floatFromInt(first)) / @as(f32, @floatFromInt(SEEN_CELLS)), per,
    });

    seen.clear();
    try std.testing.expectEqual(@as(usize, 0), seen.count());
}

test "A REVEAL IS ASKED ONCE A CELL — sixty frames on one spot is one sweep" {
    const half: f32 = 280;
    var seen = Seen{};
    const per = 2.0 * half / @as(f32, @floatFromInt(SEEN_N));
    var timer = try std.time.Timer.start();
    const FRAMES = 600;
    for (0..FRAMES) |i| {
        const x = @as(f32, @floatFromInt(i)) * per * 0.1;
        seen.walked(v3(x, 0, 0), half, {});
    }
    const us = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, @floatFromInt(FRAMES));
    std.debug.print("  reveal costs {d:.3} us a frame — {d:.4}% of a 16.7 ms frame\n", .{ us, us / 16700.0 * 100.0 });
    try std.testing.expect(us < 16700.0 * 0.01);
}

test "A MAP SMALLER THAN THE RADIUS IS ONE SWEEP, NOT MILLIONS OF CELLS OF NOTHING" {
    var seen = Seen{};
    var timer = try std.time.Timer.start();
    seen.walked(mathx.zero3, 4.0, {});
    const us = @as(f64, @floatFromInt(timer.read())) / 1000.0;
    try std.testing.expectEqual(SEEN_CELLS, seen.count());
    try std.testing.expect(us < 20000.0);
}

test "THE EDGE OF THE MAP IS NOT A CLIFF THE MASK FALLS OFF" {
    const half: f32 = 280;
    var seen = Seen{};
    seen.walked(v3(-half, 0, -half), half, {});
    try std.testing.expect(seen.count() > 0);
    seen.walked(v3(half, 0, half), half, {});
    try std.testing.expect(seen.count() > 0);
    const was = seen.count();
    seen.walked(v3(half * 4, 0, 0), half, {});
    try std.testing.expectEqual(was, seen.count());
}

test "A BIG TREE IS A LANDMARK AND A SAPLING IS SCENERY" {
    try std.testing.expect(bigTree(.bigtree) and bigTree(.bigtree2) and bigTree(.bigtree3));
    try std.testing.expect(bigTree(.conifer) and bigTree(.birch) and bigTree(.willow) and bigTree(.snag));
    try std.testing.expect(!bigTree(.tree) and !bigTree(.sapling));
    var n: usize = 0;
    for (0..props.NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (!bigTree(k)) continue;
        n += 1;
        try std.testing.expectEqual(Mark.tree, markFor(k).?);
    }
    std.debug.print("  chart: {d} prop kinds draw as a CANOPY (bound >= {d:.0} m)\n", .{ n, BIG_TREE_R });
    try std.testing.expect(n > 0);
}

/// One wall across the world, `at` metres out on +Z, standing `high` metres tall — everything `Seen` asks of a world.
const OneWall = struct {
    at: f32,
    high: f32 = 6.0,
    r: f32 = 0.4,
    asked: usize = 0,

    fn sees(self: *OneWall, from: rl.Vector3, to: rl.Vector3) bool {
        self.asked += 1;
        var wall = collision.capsule(-260, self.at, 260, self.at, self.r);
        wall.h = self.high;
        return !collision.blocksSight(from, to, wall);
    }
};

test "A WALL IS THE EDGE OF THE CHART — the near face is drawn, the ground behind it is not" {
    const half: f32 = 280;
    const per = 2.0 * half / @as(f32, @floatFromInt(SEEN_N));
    var wall = OneWall{ .at = 12.0 };
    var seen = Seen{};
    seen.walked(v3(0, EYE_DROP + 1.25, 0), half, &wall);

    const Q = struct {
        fn on(s: *const Seen, x: f32, z: f32) bool {
            const i = cellOf(x, z, half) orelse return false;
            return s.cell[i];
        }
    };
    // In front of it, and the face itself.
    try std.testing.expect(Q.on(&seen, 0, 0));
    try std.testing.expect(Q.on(&seen, 0, 8));
    try std.testing.expect(Q.on(&seen, 0, wall.at - per * 0.5));
    // …and nothing beyond, out to the reveal ring, either straight ahead or off the shoulder.
    try std.testing.expect(!Q.on(&seen, 0, wall.at + per * 2.0));
    try std.testing.expect(!Q.on(&seen, 0, 40));
    try std.testing.expect(!Q.on(&seen, 20, 40));
    // Behind him is his own side of the wall, so it charts.
    try std.testing.expect(Q.on(&seen, 0, -40));

    // The whole disc against what the wall leaves: a look now costs cells, so the count IS the mechanic.
    var open = Seen{};
    open.walked(v3(0, EYE_DROP + 1.25, 0), half, {});
    std.debug.print("\n  chart LoS: a wall {d:.0} m out leaves {d} of {d} cells, {d} looks taken\n", .{ wall.at, seen.count(), open.count(), wall.asked });
    try std.testing.expect(seen.count() < open.count());
    try std.testing.expect(seen.count() > open.count() / 4);

    // A KERB IS NOT A WALL: the look passes over anything shorter than both ends of it.
    var kerb = OneWall{ .at = 12.0, .high = 0.30 };
    var over = Seen{};
    over.walked(v3(0, EYE_DROP + 1.25, 0), half, &kerb);
    try std.testing.expectEqual(open.count(), over.count());
}

test "AND THE LOOK IS PAID FOR ONCE A CELL, so the cold disc is the whole bill" {
    const ta = std.testing.allocator;
    const m = try ta.create(wf.Map);
    defer ta.destroy(m);
    const e = try ta.create(envmod.Env);
    defer ta.destroy(e);
    const text = try wf.readForTest(ta, wf.START_MAP, wf.TEXT_CAP);
    defer ta.free(text);
    var line: usize = 0;
    try wf.parse(text, m, &line);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);

    var seen = Seen{};
    var t = try std.time.Timer.start();
    seen.walked(v3(0, e.groundAt(0, 0) + 1.25, 0), m.half, e);
    const cold = @as(f64, @floatFromInt(t.read())) / 1000.0;
    const first = seen.count();

    // A step to the next cell over: the crescent, which is what walking actually costs.
    const per = 2.0 * m.half / @as(f32, @floatFromInt(SEEN_N));
    t.reset();
    seen.walked(v3(per, e.groundAt(per, 0) + 1.25, 0), m.half, e);
    const step = @as(f64, @floatFromInt(t.read())) / 1000.0;
    std.debug.print("\n  chart cost over {d} solids: {d:.0} us for the cold disc ({d} cells), {d:.0} us for a step ({d} more)\n", .{ e.solidCount(), cold, first, step, seen.count() - first });
    try std.testing.expect(cold < 8000.0);
    try std.testing.expect(step < cold);
}
