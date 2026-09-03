const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const uiart = @import("uiart.zig");

pub const Icon = enum {
    ground,
    locations,
    decor,
    props,
    interact,
    units,
    select,
    erase,
    zone,
    location,
    arena,
    clearing,
    scatter,
    patch,
    single,
    stamp,
    row,
    ring,
    cluster,
    ivy,
    toad,
    archer,
    ogre,
    berserker,
    priest,
    slinger,
    brood_mother,
    broodling,
    brood_sac,
    shieldman,
    greatsword,
    shade,
    leechfly,
    rooted,
    shroom,
    bone_knight,
    delver,
    necromancer,
    fungal_deer,
    mushroom_mage,
    fen_lurker,
    spore_golem,
    bone_skitterer,
    ancient_priest,
    tolling_hollow,
    mourner,
    slumber_bloom,
    cinder_wake,
    rotgorger,
    birchwight,
    salt_husk,
    fish_spearman,
    fish_netter,
    fish_shaman,
    blinkbat,
    fungal_swordsman,
    fungal_magus,
    owlbear,
    wanderer,
    merchant,
    smith,
    new,
    open,
    save,
    saveas,
    reload,
    undo,
    redo,
    eye,
    eyeOff,
};

/// Filled silhouettes, drawn in ONE colour: the glyph sits on a button face that changes with state, so
/// every face. Every stroke is `s * 0.12` — 2.2 px at the 18 px the editor draws at.
pub fn draw(ic: Icon, cx: f32, cy: f32, size: f32, col: rl.Color) void {
    var g = G{ .cx = cx, .cy = cy, .s = size, .w = @max(2.0, size * 0.12), .col = col, .cut = cutOf(col), .soft = softOf(col) };
    g.glyph(ic);
}

fn cutOf(c: rl.Color) rl.Color {
    return rl.Color.init(0, 0, 0, @intCast(@as(u16, c.a) * 150 / 255));
}
fn softOf(c: rl.Color) rl.Color {
    return rl.Color.init(c.r, c.g, c.b, @intCast(@as(u16, c.a) * 120 / 255));
}

const V = rl.Vector2;

const triV = uiart.triangle;

const G = struct {
    cx: f32,
    cy: f32,
    s: f32,
    w: f32,
    col: rl.Color,
    cut: rl.Color,
    soft: rl.Color,

    fn p(g: *const G, x: f32, y: f32) V {
        return .{ .x = g.cx + x * g.s, .y = g.cy + y * g.s };
    }
    fn disc(g: *const G, x: f32, y: f32, r: f32, c: rl.Color) void {
        rl.drawCircleV(g.p(x, y), r * g.s, c);
    }
    fn bar(g: *const G, x0: f32, y0: f32, x1: f32, y1: f32, w: f32, c: rl.Color) void {
        rl.drawLineEx(g.p(x0, y0), g.p(x1, y1), w * g.s, c);
    }
    fn hbar(g: *const G, x: f32, y: f32, len: f32, w: f32, c: rl.Color) void {
        g.bar(x - len * 0.5, y, x + len * 0.5, y, w, c);
    }
    fn vbar(g: *const G, x: f32, y: f32, len: f32, w: f32, c: rl.Color) void {
        g.bar(x, y - len * 0.5, x, y + len * 0.5, w, c);
    }
    fn rect(g: *const G, x: f32, y: f32, bw: f32, bh: f32, c: rl.Color) void {
        const a = g.p(x - bw * 0.5, y - bh * 0.5);
        rl.drawRectangleRec(.{ .x = a.x, .y = a.y, .width = bw * g.s, .height = bh * g.s }, c);
    }
    fn frame(g: *const G, x: f32, y: f32, bw: f32, bh: f32, w: f32, c: rl.Color) void {
        const a = g.p(x - bw * 0.5, y - bh * 0.5);
        rl.drawRectangleLinesEx(.{ .x = a.x, .y = a.y, .width = bw * g.s, .height = bh * g.s }, w * g.s, c);
    }
    /// raylib culls the back face, so the winding is fixed here and nowhere else.
    fn tri(g: *const G, ax: f32, ay: f32, bx: f32, by: f32, cx_: f32, cy_: f32, c: rl.Color) void {
        triV(g.p(ax, ay), g.p(bx, by), g.p(cx_, cy_), c);
    }
    fn quad(g: *const G, ax: f32, ay: f32, bx: f32, by: f32, cx_: f32, cy_: f32, dx: f32, dy: f32, c: rl.Color) void {
        g.tri(ax, ay, bx, by, cx_, cy_, c);
        g.tri(ax, ay, cx_, cy_, dx, dy, c);
    }
    fn trap(g: *const G, x: f32, yt: f32, yb: f32, wt: f32, wb: f32, c: rl.Color) void {
        g.quad(x - wt * 0.5, yt, x + wt * 0.5, yt, x + wb * 0.5, yb, x - wb * 0.5, yb, c);
    }
    /// Fan from `pts[0]`, so the polygon has to be star-shaped from its first point.
    fn poly(g: *const G, pts: []const [2]f32, c: rl.Color) void {
        var i: usize = 1;
        while (i + 1 < pts.len) : (i += 1) g.tri(pts[0][0], pts[0][1], pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], c);
    }
    fn sector(g: *const G, x: f32, y: f32, r: f32, a0: f32, a1: f32, c: rl.Color) void {
        rl.drawCircleSector(g.p(x, y), r * g.s, a0, a1, 18, c);
    }
    fn dome(g: *const G, x: f32, y: f32, r: f32, c: rl.Color) void {
        g.sector(x, y, r, 180, 360, c);
    }
    fn ring(g: *const G, x: f32, y: f32, r: f32, w: f32, c: rl.Color) void {
        rl.drawRing(g.p(x, y), (r - w * 0.5) * g.s, (r + w * 0.5) * g.s, 0, 360, 28, c);
    }
    fn arc(g: *const G, x: f32, y: f32, r: f32, a0: f32, a1: f32, w: f32, c: rl.Color) void {
        rl.drawRing(g.p(x, y), (r - w * 0.5) * g.s, (r + w * 0.5) * g.s, a0, a1, 24, c);
    }
    fn ellipse(g: *const G, x: f32, y: f32, rx: f32, ry: f32, rotDeg: f32, c: rl.Color) void {
        const n = 20;
        const rot = mathx.radians(rotDeg);
        const cr = mathx.cosf(rot);
        const sr = mathx.sinf(rot);
        const c0 = g.p(x, y);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const t0 = std.math.tau * @as(f32, @floatFromInt(i)) / n;
            const t1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / n;
            const ex0 = rx * mathx.cosf(t0);
            const ey0 = ry * mathx.sinf(t0);
            const ex1 = rx * mathx.cosf(t1);
            const ey1 = ry * mathx.sinf(t1);
            const p0 = g.p(x + ex0 * cr - ey0 * sr, y + ex0 * sr + ey0 * cr);
            const p1 = g.p(x + ex1 * cr - ey1 * sr, y + ex1 * sr + ey1 * cr);
            triV(c0, p0, p1, c);
        }
    }
    fn ngonLines(g: *const G, x: f32, y: f32, n: i32, r: f32, rotDeg: f32, w: f32, c: rl.Color) void {
        rl.drawPolyLinesEx(g.p(x, y), n, r * g.s, rotDeg, w * g.s, c);
    }
    fn arrowHead(g: *const G, x: f32, y: f32, r: f32, dirDeg: f32, c: rl.Color) void {
        const a = mathx.radians(dirDeg);
        const tip = g.p(x + mathx.cosf(a) * r, y + mathx.sinf(a) * r);
        const l = g.p(x + mathx.cosf(a + 2.4) * r, y + mathx.sinf(a + 2.4) * r);
        const rr = g.p(x + mathx.cosf(a - 2.4) * r, y + mathx.sinf(a - 2.4) * r);
        triV(tip, l, rr, c);
    }

    // Shared bodies: a hooded figure and a fishman, each used by several glyphs.
    fn hooded(g: *const G, x: f32, headY: f32, headR: f32, hemY: f32, hemW: f32) void {
        g.disc(x, headY, headR, g.col);
        g.trap(x, headY, hemY, headR * 2.0, hemW, g.col);
        g.ellipse(x, headY + headR * 0.15, headR * 0.6, headR * 0.42, 0, g.cut);
    }
    fn fishman(g: *const G, x: f32) void {
        g.tri(x - 0.08, -0.36, x + 0.06, -0.40, x - 0.02, -0.60, g.col);
        g.disc(x, -0.28, 0.16, g.col);
        g.trap(x, -0.14, 0.30, 0.22, 0.34, g.col);
        g.bar(x, 0.28, x - 0.16, 0.50, 0.10, g.col);
        g.bar(x, 0.28, x + 0.14, 0.50, 0.10, g.col);
        g.disc(x + 0.06, -0.30, 0.045, g.cut);
    }
    fn legs(g: *const G, x: f32, y: f32, spread: f32, drop: f32, w: f32) void {
        g.bar(x, y, x - spread, y + drop, w, g.col);
        g.bar(x, y, x + spread, y + drop, w, g.col);
    }

    fn glyph(g: *G, ic: Icon) void {
        const col = g.col;
        const cut = g.cut;
        const soft = g.soft;
        const w = g.w / g.s;
        switch (ic) {
            .ground => {
                g.tri(-0.46, 0.30, 0.12, 0.30, -0.16, -0.36, col);
                g.tri(0.0, 0.30, 0.46, 0.30, 0.26, -0.08, col);
                g.hbar(0, 0.34, 0.92, 0.14, col);
            },
            .locations => {
                g.disc(0, -0.12, 0.30, col);
                g.tri(-0.24, 0.04, 0.24, 0.04, 0, 0.46, col);
                g.disc(0, -0.12, 0.12, cut);
            },
            .decor => {
                g.tri(-0.30, 0.40, -0.06, 0.40, -0.40, -0.22, col);
                g.tri(0.06, 0.40, 0.30, 0.40, 0.42, -0.16, col);
                g.tri(-0.11, 0.40, 0.11, 0.40, 0, -0.46, col);
                g.hbar(0, 0.40, 0.84, 0.10, col);
            },
            .props => {
                g.hbar(0, -0.38, 0.78, 0.14, col);
                g.rect(0, 0, 0.38, 0.62, col);
                g.hbar(0, 0.38, 0.78, 0.14, col);
                g.vbar(-0.09, 0, 0.50, 0.05, cut);
                g.vbar(0.09, 0, 0.50, 0.05, cut);
            },
            .interact => {
                g.ellipse(0, -0.12, 0.38, 0.24, 0, col);
                g.rect(0, 0.12, 0.76, 0.48, col);
                g.hbar(0, -0.12, 0.76, 0.05, cut);
                g.rect(0, -0.08, 0.14, 0.18, cut);
            },
            .units => {
                g.disc(0, -0.22, 0.20, col);
                g.dome(0, 0.44, 0.40, col);
            },
            .select => {
                g.poly(&.{ .{ -0.22, -0.44 }, .{ -0.22, 0.28 }, .{ -0.04, 0.12 }, .{ 0.10, 0.06 }, .{ 0.30, 0.02 } }, col);
                g.quad(-0.04, 0.12, 0.10, 0.42, 0.24, 0.35, 0.10, 0.06, col);
            },
            .erase => {
                const c = g.p(0.02, -0.02);
                rl.drawRectanglePro(.{ .x = c.x, .y = c.y, .width = 0.76 * g.s, .height = 0.36 * g.s }, .{ .x = 0.38 * g.s, .y = 0.18 * g.s }, -45, col);
                const d = g.p(0.02 - 0.20 * 0.7071, -0.02 + 0.20 * 0.7071);
                rl.drawRectanglePro(.{ .x = d.x, .y = d.y, .width = 0.26 * g.s, .height = 0.36 * g.s }, .{ .x = 0.13 * g.s, .y = 0.18 * g.s }, -45, cut);
                g.hbar(0.12, 0.44, 0.60, 0.08, soft);
            },

            .zone => {
                g.frame(0, 0, 0.74, 0.60, w, col);
                g.rect(-0.37, -0.30, 0.20, 0.20, col);
                g.rect(0.37, 0.30, 0.20, 0.20, col);
            },
            .location => {
                g.frame(0, 0, 0.74, 0.58, w, col);
                for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sy| g.rect(sx * 0.37, sy * 0.29, 0.20, 0.20, col);
            },
            .arena => {
                g.ngonLines(0, 0.04, 5, 0.42, -90, w, col);
                var k: u32 = 0;
                while (k < 5) : (k += 1) {
                    const a = mathx.radians(-90 + 72 * @as(f32, @floatFromInt(k)));
                    g.disc(mathx.cosf(a) * 0.42, 0.04 + mathx.sinf(a) * 0.42, 0.10, col);
                }
            },
            .clearing => {
                g.ring(0, 0, 0.34, w, col);
                g.disc(0, 0, 0.11, col);
            },
            .scatter => {
                g.frame(0, 0, 0.82, 0.66, 0.06, soft);
                for ([_][2]f32{ .{ -0.22, -0.14 }, .{ 0.12, -0.20 }, .{ 0.26, 0.10 }, .{ -0.04, 0.06 }, .{ -0.24, 0.20 } }) |q| g.disc(q[0], q[1], 0.085, col);
            },
            .patch => {
                g.ring(0, 0, 0.38, 0.07, soft);
                for ([_][2]f32{ .{ -0.15, -0.12 }, .{ 0.13, -0.15 }, .{ 0.17, 0.11 }, .{ -0.11, 0.15 }, .{ 0.01, 0.0 } }) |q| g.disc(q[0], q[1], 0.09, col);
            },
            .single => {
                g.disc(0, 0, 0.14, col);
                g.vbar(0, -0.30, 0.22, 0.10, col);
                g.vbar(0, 0.30, 0.22, 0.10, col);
                g.hbar(-0.30, 0, 0.22, 0.10, col);
                g.hbar(0.30, 0, 0.22, 0.10, col);
            },
            .stamp => {
                g.disc(0, -0.32, 0.13, col);
                g.vbar(0, -0.12, 0.30, 0.13, col);
                g.rect(0, 0.14, 0.58, 0.22, col);
                g.hbar(0, 0.42, 0.74, 0.08, soft);
            },
            .row => {
                g.hbar(0, 0, 0.86, 0.06, soft);
                for ([_]f32{ -0.29, 0, 0.29 }) |x| g.disc(x, 0, 0.12, col);
            },
            .ring => {
                g.ring(0, 0, 0.34, 0.05, soft);
                var k: u32 = 0;
                while (k < 6) : (k += 1) {
                    const a = mathx.radians(-90 + 60 * @as(f32, @floatFromInt(k)));
                    g.disc(mathx.cosf(a) * 0.34, mathx.sinf(a) * 0.34, 0.10, col);
                }
            },
            .cluster => {
                g.disc(0, 0, 0.16, col);
                var k: u32 = 0;
                while (k < 6) : (k += 1) {
                    const a = mathx.radians(30 + 60 * @as(f32, @floatFromInt(k)));
                    g.disc(mathx.cosf(a) * 0.33, mathx.sinf(a) * 0.33, 0.095, col);
                }
            },
            .ivy => {
                g.rect(0.30, 0, 0.24, 0.88, soft);
                g.vbar(0.02, 0, 0.88, 0.10, col);
                g.disc(-0.18, -0.28, 0.12, col);
                g.disc(-0.20, 0.0, 0.12, col);
                g.disc(-0.18, 0.28, 0.12, col);
                g.disc(0.16, -0.14, 0.10, col);
                g.disc(0.16, 0.16, 0.10, col);
            },

            .toad => {
                g.ellipse(0, 0.12, 0.42, 0.26, 0, col);
                g.disc(-0.18, -0.16, 0.13, col);
                g.disc(0.18, -0.16, 0.13, col);
                g.disc(-0.18, -0.17, 0.055, cut);
                g.disc(0.18, -0.17, 0.055, cut);
                g.hbar(0, 0.14, 0.44, 0.05, cut);
            },
            .archer => {
                g.arc(-0.02, 0, 0.40, 300, 420, 0.11, col);
                g.bar(0.18, -0.35, 0.18, 0.35, 0.05, col);
                g.hbar(-0.08, 0, 0.72, 0.08, col);
                g.tri(0.28, -0.11, 0.28, 0.11, 0.48, 0, col);
                g.tri(-0.44, -0.10, -0.30, 0, -0.44, 0.10, cut);
            },
            .ogre => {
                g.dome(0, 0.16, 0.44, col);
                g.rect(0, 0.26, 0.88, 0.20, col);
                g.disc(0, -0.32, 0.14, col);
                g.disc(-0.46, 0.30, 0.12, col);
                g.disc(0.46, 0.30, 0.12, col);
                g.rect(-0.22, 0.42, 0.18, 0.14, col);
                g.rect(0.22, 0.42, 0.18, 0.14, col);
                g.hbar(0, 0.22, 0.60, 0.05, cut);
            },
            .berserker => {
                g.bar(-0.30, 0.42, 0.30, -0.34, 0.11, col);
                g.bar(0.30, 0.42, -0.30, -0.34, 0.11, col);
                g.tri(0.12, -0.52, 0.50, -0.14, 0.26, -0.22, col);
                g.tri(-0.12, -0.52, -0.50, -0.14, -0.26, -0.22, col);
            },
            .priest => {
                g.trap(0, -0.04, 0.44, 0.24, 0.62, col);
                g.disc(0, -0.18, 0.15, col);
                g.tri(-0.15, -0.24, 0.15, -0.24, 0, -0.54, col);
                g.vbar(0, 0.22, 0.34, 0.05, cut);
            },
            .slinger => {
                g.bar(-0.30, -0.44, 0, 0.18, 0.10, col);
                g.bar(0.30, -0.44, 0, 0.18, 0.10, col);
                g.disc(0, 0.26, 0.17, col);
                g.disc(0, 0.24, 0.07, cut);
            },

            .brood_mother => {
                const L = [_][4]f32{ .{ 0.34, -0.30, 0.46, -0.06 }, .{ 0.38, -0.08, 0.48, 0.18 }, .{ 0.34, 0.12, 0.46, 0.38 }, .{ 0.26, 0.28, 0.34, 0.50 } };
                for ([_]f32{ -1, 1 }) |sx| for (L) |l| {
                    g.bar(sx * 0.06, l[1] * 0.5 + 0.02, sx * l[0], l[1], 0.08, col);
                    g.bar(sx * l[0], l[1], sx * l[2], l[3], 0.08, col);
                };
                g.disc(0, 0.14, 0.28, col);
                g.disc(0, -0.22, 0.16, col);
            },
            .broodling => {
                const L = [_][4]f32{ .{ 0.24, -0.20, 0.34, -0.02 }, .{ 0.26, 0.04, 0.36, 0.22 }, .{ 0.22, 0.22, 0.30, 0.40 } };
                for ([_]f32{ -1, 1 }) |sx| for (L) |l| {
                    g.bar(sx * 0.04, l[1] * 0.5 + 0.06, sx * l[0], l[1], 0.07, col);
                    g.bar(sx * l[0], l[1], sx * l[2], l[3], 0.07, col);
                };
                g.disc(0, 0.12, 0.17, col);
                g.disc(0, -0.12, 0.10, col);
            },
            .brood_sac => {
                g.bar(-0.14, -0.28, -0.32, -0.52, 0.06, soft);
                g.bar(0.14, -0.28, 0.32, -0.52, 0.06, soft);
                g.ellipse(0, 0.08, 0.34, 0.38, 0, col);
                for ([_][2]f32{ .{ -0.13, 0.0 }, .{ 0.11, -0.08 }, .{ -0.02, 0.18 }, .{ 0.15, 0.14 } }) |q| g.disc(q[0], q[1], 0.07, cut);
            },
            .shieldman => {
                g.bar(0.16, -0.52, 0.50, 0.32, 0.07, soft);
                g.tri(0.10, -0.46, 0.24, -0.50, 0.14, -0.62, soft);
                g.poly(&.{ .{ -0.34, -0.36 }, .{ 0.34, -0.36 }, .{ 0.34, 0.04 }, .{ 0, 0.46 }, .{ -0.34, 0.04 } }, col);
                g.disc(0, -0.04, 0.09, cut);
            },
            .greatsword => {
                g.rect(0, -0.10, 0.17, 0.60, col);
                g.tri(-0.085, -0.40, 0.085, -0.40, 0, -0.56, col);
                g.hbar(0, 0.22, 0.56, 0.11, col);
                g.vbar(0, 0.36, 0.20, 0.09, soft);
                g.disc(0, 0.49, 0.08, col);
                g.vbar(0, -0.12, 0.40, 0.04, cut);
            },

            .shade => {
                g.hooded(0, -0.20, 0.22, 0.30, 0.60);
                g.tri(-0.30, 0.29, -0.10, 0.29, -0.22, 0.48, col);
                g.tri(-0.06, 0.29, 0.14, 0.29, 0.04, 0.46, col);
                g.tri(0.16, 0.29, 0.30, 0.29, 0.26, 0.44, col);
            },
            .mourner => {
                g.dome(0, 0.10, 0.40, col);
                g.rect(0, 0.26, 0.80, 0.32, col);
                g.ellipse(-0.02, 0.08, 0.14, 0.08, 0, cut);
                g.hbar(0, 0.36, 0.60, 0.05, cut);
            },
            .wanderer => {
                g.hooded(-0.08, -0.24, 0.16, 0.34, 0.46);
                g.vbar(0.32, 0.0, 0.88, 0.09, col);
                g.disc(0.32, -0.40, 0.11, col);
            },
            .merchant => {
                g.ellipse(0.08, 0.06, 0.36, 0.20, 0, col);
                g.disc(0.06, -0.12, 0.17, col);
                g.bar(-0.20, 0.02, -0.36, -0.32, 0.13, col);
                g.bar(-0.42, -0.34, -0.20, -0.36, 0.12, col);
                for ([_]f32{ -0.18, -0.04, 0.16, 0.30 }) |x| g.vbar(x, 0.34, 0.28, 0.08, col);
                g.disc(-0.36, -0.36, 0.035, cut);
            },
            .smith => {
                // **THE MOUSTACHE AND THE RAISED HAMMER, AND NOTHING ELSE FITS AT 18 px.**
                g.trap(-0.04, -0.10, 0.46, 0.30, 0.44, col);
                g.disc(-0.02, -0.28, 0.19, col);
                g.bar(-0.16, -0.22, -0.28, 0.10, 0.075, col);
                g.bar(0.12, -0.22, 0.24, 0.12, 0.075, col);
                g.disc(-0.09, -0.33, 0.045, cut);
                g.disc(0.06, -0.33, 0.045, cut);
                g.bar(0.20, -0.02, 0.40, -0.34, 0.09, col);
                g.bar(0.40, -0.34, 0.34, -0.60, 0.075, col);
                g.rect(0.36, -0.68, 0.30, 0.15, col);
                g.bar(-0.18, 0.42, -0.36, 0.56, 0.08, col);
                g.bar(0.12, 0.42, 0.32, 0.56, 0.08, col);
            },

            .rooted => {
                g.rect(0, 0.08, 0.26, 0.56, col);
                g.tri(-0.13, 0.20, -0.13, 0.44, -0.44, 0.44, col);
                g.tri(0.13, 0.20, 0.44, 0.44, 0.13, 0.44, col);
                g.bar(0, -0.12, -0.34, -0.42, 0.10, col);
                g.bar(0.02, -0.06, 0.34, -0.34, 0.10, col);
                g.bar(0, -0.18, 0.06, -0.52, 0.08, col);
                g.disc(-0.07, -0.02, 0.045, cut);
                g.disc(0.07, -0.02, 0.045, cut);
            },
            .fish_spearman => {
                g.fishman(-0.14);
                g.vbar(0.30, 0.02, 0.92, 0.08, col);
                g.tri(0.21, -0.34, 0.39, -0.34, 0.30, -0.56, col);
            },
            .fish_netter => {
                g.fishman(-0.18);
                g.bar(0.26, 0.20, 0.26, 0.50, 0.07, col);
                g.ring(0.26, -0.04, 0.24, 0.07, col);
                g.hbar(0.26, -0.04, 0.44, 0.04, col);
                g.vbar(0.26, -0.04, 0.44, 0.04, col);
            },
            .fish_shaman => {
                g.fishman(-0.16);
                g.vbar(0.30, 0.04, 0.84, 0.08, col);
                g.bar(0.30, -0.32, 0.16, -0.52, 0.07, col);
                g.bar(0.30, -0.32, 0.44, -0.52, 0.07, col);
                g.disc(0.30, -0.30, 0.11, col);
                g.disc(0.30, -0.08, 0.08, col);
            },
            .salt_husk => {
                var k: u32 = 0;
                while (k < 6) : (k += 1) {
                    const a = mathx.radians(30 + 60 * @as(f32, @floatFromInt(k)));
                    const ca = mathx.cosf(a);
                    const sa = mathx.sinf(a);
                    g.tri(ca * 0.34 - sa * 0.07, sa * 0.34 + ca * 0.07, ca * 0.34 + sa * 0.07, sa * 0.34 - ca * 0.07, ca * 0.56, sa * 0.56, soft);
                }
                g.disc(0, -0.24, 0.14, col);
                g.trap(0, -0.12, 0.18, 0.24, 0.28, col);
                g.legs(0, 0.16, 0.16, 0.28, 0.10);
            },
            .birchwight => {
                g.rect(0, 0.04, 0.24, 0.84, col);
                g.bar(0, -0.16, -0.34, -0.48, 0.11, col);
                g.bar(0, -0.16, 0.34, -0.48, 0.11, col);
                g.hbar(0, 0.44, 0.46, 0.10, col);
                for ([_]f32{ -0.02, 0.14, 0.30 }) |y| g.hbar(0, y, 0.24, 0.05, cut);
            },
            .rotgorger => {
                g.ellipse(0.08, -0.04, 0.40, 0.22, 0, col);
                g.disc(0.16, -0.18, 0.18, col);
                g.bar(-0.20, -0.02, -0.34, 0.18, 0.17, col);
                g.disc(-0.36, 0.20, 0.15, col);
                for ([_]f32{ -0.10, 0.08, 0.28 }) |x| g.vbar(x, 0.28, 0.22, 0.10, col);
                g.hbar(-0.30, 0.38, 0.34, 0.08, soft);
            },
            .cinder_wake => {
                g.hbar(-0.26, 0.42, 0.50, 0.07, soft);
                g.disc(-0.18, 0.40, 0.09, soft);
                g.disc(-0.36, 0.42, 0.07, soft);
                g.disc(-0.50, 0.44, 0.05, soft);
                g.disc(0.20, -0.34, 0.13, col);
                g.bar(0.16, -0.22, 0.02, 0.08, 0.15, col);
                g.bar(0.02, 0.08, 0.24, 0.40, 0.10, col);
                g.bar(0.02, 0.08, -0.14, 0.38, 0.10, col);
                g.bar(0.12, -0.14, 0.40, 0.02, 0.08, col);
            },
            .slumber_bloom => {
                g.tri(-0.02, 0.32, -0.36, 0.46, -0.04, 0.48, soft);
                g.tri(0.02, 0.32, 0.04, 0.48, 0.36, 0.46, soft);
                g.vbar(0, 0.26, 0.42, 0.10, col);
                g.ellipse(0, -0.14, 0.26, 0.32, 0, col);
                g.tri(-0.11, -0.42, 0.11, -0.42, 0, -0.58, col);
                g.bar(-0.10, -0.38, -0.12, 0.10, 0.04, cut);
                g.bar(0.10, -0.38, 0.12, 0.10, 0.04, cut);
            },
            .shroom => {
                g.dome(0, 0.0, 0.42, col);
                g.rect(0, 0.22, 0.28, 0.44, col);
                g.hbar(0, 0.02, 0.72, 0.05, cut);
                g.disc(-0.18, -0.20, 0.06, cut);
                g.disc(0.08, -0.30, 0.06, cut);
                g.disc(0.24, -0.12, 0.06, cut);
            },
            .blinkbat => {
                for ([_]f32{ -1, 1 }) |sx| {
                    g.poly(&.{ .{ sx * 0.06, -0.10 }, .{ sx * 0.52, -0.36 }, .{ sx * 0.46, 0.02 }, .{ sx * 0.34, -0.04 }, .{ sx * 0.26, 0.20 }, .{ sx * 0.06, 0.16 } }, col);
                    g.tri(sx * 0.03, -0.20, sx * 0.13, -0.22, sx * 0.13, -0.46, col);
                }
                g.ellipse(0, 0.08, 0.12, 0.22, 0, col);
                g.disc(0, -0.16, 0.12, col);
                g.disc(-0.05, -0.17, 0.035, cut);
                g.disc(0.05, -0.17, 0.035, cut);
            },
            .owlbear => {
                g.trap(0, -0.02, 0.28, 0.34, 0.44, col);
                g.legs(0, 0.28, 0.17, 0.22, 0.10);
                for ([_]f32{ -1, 1 }) |sx| g.tri(sx * 0.13, -0.36, sx * 0.30, -0.30, sx * 0.27, -0.64, col);
                g.disc(0, -0.22, 0.34, col);
                g.disc(-0.13, -0.26, 0.075, cut);
                g.disc(0.13, -0.26, 0.075, cut);
                g.tri(-0.05, -0.14, 0.05, -0.14, 0, 0.02, cut);
                g.hbar(0, 0.14, 0.30, 0.04, cut);
            },
            .fungal_swordsman => {
                g.bar(0.14, 0.06, 0.44, -0.30, 0.09, col);
                g.tri(0.38, -0.30, 0.48, -0.20, 0.54, -0.42, col);
                g.trap(0, -0.10, 0.22, 0.22, 0.30, col);
                g.legs(0, 0.22, 0.14, 0.24, 0.09);
                g.ellipse(0, -0.18, 0.40, 0.17, 0, col);
                g.disc(-0.16, -0.22, 0.05, cut);
                g.disc(0.12, -0.26, 0.05, cut);
            },
            .fungal_magus => {
                g.vbar(0.32, 0.04, 0.84, 0.08, col);
                g.disc(0.32, -0.36, 0.12, col);
                g.disc(0.32, -0.36, 0.05, cut);
                g.trap(-0.04, -0.12, 0.22, 0.22, 0.30, col);
                g.legs(-0.04, 0.22, 0.14, 0.24, 0.09);
                g.trap(-0.04, -0.56, -0.16, 0.16, 0.46, col);
                g.hbar(-0.04, -0.14, 0.46, 0.05, cut);
            },
            .leechfly => {
                g.ellipse(-0.24, -0.10, 0.26, 0.10, -30, soft);
                g.ellipse(0.24, -0.10, 0.26, 0.10, 30, soft);
                g.ellipse(0, 0.08, 0.13, 0.26, 0, col);
                g.disc(0, -0.26, 0.11, col);
                g.bar(0.02, -0.34, 0.12, -0.54, 0.06, col);
                for ([_]f32{ 0.0, 0.12, 0.24 }) |y| g.hbar(0, y, 0.20, 0.04, cut);
            },
            .bone_knight => {
                g.rect(0, 0.36, 0.86, 0.22, col);
                g.dome(0, -0.14, 0.34, col);
                g.rect(0, 0.04, 0.68, 0.36, col);
                g.hbar(0, -0.06, 0.48, 0.07, cut);
                g.vbar(0, 0.10, 0.22, 0.06, cut);
                g.hbar(0, 0.25, 0.86, 0.04, cut);
            },
            .delver => {
                g.disc(-0.30, 0.34, 0.08, soft);
                g.disc(0.02, 0.38, 0.08, soft);
                g.disc(0.32, 0.32, 0.08, soft);
                g.dome(0, 0.10, 0.40, col);
                g.hbar(0, 0.14, 0.86, 0.10, col);
                g.tri(-0.28, -0.12, -0.10, -0.24, -0.34, -0.48, col);
                g.tri(-0.08, -0.28, 0.08, -0.28, 0.02, -0.58, col);
                g.tri(0.12, -0.22, 0.28, -0.10, 0.36, -0.44, col);
                g.disc(-0.14, 0.0, 0.05, cut);
                g.disc(0.14, 0.0, 0.05, cut);
            },
            .necromancer => {
                g.hooded(-0.10, -0.28, 0.16, 0.40, 0.52);
                g.vbar(0.30, 0.02, 0.88, 0.08, col);
                g.disc(0.30, -0.40, 0.12, col);
                g.hbar(0.30, -0.34, 0.14, 0.04, cut);
                g.disc(0.26, -0.43, 0.035, cut);
                g.disc(0.34, -0.43, 0.035, cut);
            },
            .fungal_deer => {
                // A QUADRUPED WITH A FLOWER OVER ITS BACK AND A RACK ON ITS HEAD. At 18 px the ring and the
                // antlers are the whole glyph — the body under them only has to say "four legs".
                g.hbar(-0.04, 0.08, 0.50, 0.13, col);
                for ([_]f32{ -0.22, -0.04, 0.16 }) |x| g.vbar(x, 0.34, 0.38, 0.06, col);
                g.bar(-0.28, 0.04, -0.40, -0.08, 0.06, col);
                g.bar(0.20, 0.04, 0.34, -0.22, 0.09, col);
                g.ellipse(0.44, -0.28, 0.13, 0.06, -20, col);
                g.bar(0.34, -0.34, 0.26, -0.62, 0.045, col);
                g.bar(0.30, -0.50, 0.42, -0.56, 0.040, col);
                g.bar(0.42, -0.32, 0.50, -0.58, 0.045, col);
                g.bar(-0.06, 0.02, -0.10, -0.24, 0.075, col);
                var k: u32 = 0;
                while (k < 6) : (k += 1) {
                    const a = mathx.radians(60 * @as(f32, @floatFromInt(k)) + 12);
                    g.disc(-0.12 + mathx.cosf(a) * 0.16, -0.40 + mathx.sinf(a) * 0.16, 0.075, col);
                }
                g.disc(-0.12, -0.40, 0.10, col);
                g.disc(-0.12, -0.40, 0.05, cut);
            },
            .mushroom_mage => {
                g.trap(0, -0.14, 0.40, 0.26, 0.44, col);
                g.trap(0, -0.46, -0.14, 0.22, 0.74, col);
                g.ellipse(0, -0.02, 0.10, 0.07, 0, cut);
                g.disc(0.40, -0.06, 0.07, col);
                g.disc(0.48, 0.14, 0.07, col);
                g.disc(0.32, 0.28, 0.07, col);
            },
            .fen_lurker => {
                g.hbar(-0.28, 0.36, 0.26, 0.06, soft);
                g.hbar(0.24, 0.36, 0.32, 0.06, soft);
                g.hbar(0, 0.22, 0.92, 0.10, col);
                g.bar(-0.08, 0.20, 0.02, -0.12, 0.16, col);
                g.bar(0.02, -0.12, -0.04, -0.34, 0.14, col);
                g.ellipse(0.10, -0.40, 0.24, 0.10, 0, col);
                g.disc(0.06, -0.42, 0.04, cut);
            },
            .spore_golem => {
                g.trap(0, -0.48, -0.26, 0.36, 0.92, col);
                g.hbar(0, -0.26, 0.98, 0.12, col);
                g.rect(0, 0.10, 0.56, 0.56, col);
                g.rect(-0.16, 0.44, 0.20, 0.16, col);
                g.rect(0.16, 0.44, 0.20, 0.16, col);
                g.hbar(0, 0.06, 0.56, 0.05, cut);
            },
            .bone_skitterer => {
                for ([_]f32{ -0.22, 0.0, 0.22 }) |x| {
                    g.bar(x, 0.08, x - 0.16, 0.36, 0.08, col);
                    g.bar(x, 0.08, x + 0.16, 0.36, 0.08, col);
                }
                g.ellipse(-0.02, 0.04, 0.36, 0.13, 0, col);
                for ([_]f32{ -0.22, -0.08, 0.06, 0.20 }) |x| g.vbar(x, 0.04, 0.20, 0.04, cut);
                g.bar(0.30, 0.02, 0.44, -0.24, 0.09, col);
                g.bar(0.44, -0.24, 0.30, -0.44, 0.09, col);
                g.disc(0.28, -0.46, 0.11, col);
                g.disc(0.30, -0.46, 0.05, cut);
            },
            .ancient_priest => {
                g.vbar(0.36, 0.06, 0.80, 0.08, col);
                g.disc(0.36, -0.40, 0.11, col);
                g.disc(0.36, -0.40, 0.045, cut);
                g.trap(-0.06, -0.08, 0.44, 0.26, 0.50, col);
                g.tri(-0.22, -0.30, -0.10, -0.30, -0.24, -0.58, col);
                g.tri(-0.06, -0.32, 0.06, -0.30, 0.04, -0.58, col);
                g.disc(-0.06, -0.22, 0.16, col);
                g.bar(-0.02, -0.16, 0.28, -0.10, 0.14, col);
                g.disc(-0.02, -0.25, 0.04, cut);
            },
            .tolling_hollow => {
                g.disc(-0.26, -0.22, 0.12, col);
                g.bar(-0.22, -0.10, -0.32, 0.24, 0.16, col);
                g.vbar(-0.36, 0.36, 0.24, 0.09, col);
                g.vbar(-0.22, 0.36, 0.24, 0.09, col);
                g.disc(0.18, -0.38, 0.06, col);
                g.dome(0.18, -0.10, 0.26, col);
                g.trap(0.18, -0.10, 0.20, 0.52, 0.62, col);
                g.hbar(0.18, 0.22, 0.70, 0.10, col);
                g.disc(0.18, 0.31, 0.07, col);
                g.hbar(0.18, 0.14, 0.44, 0.04, cut);
            },

            .new => {
                g.poly(&.{ .{ -0.26, -0.40 }, .{ 0.10, -0.40 }, .{ 0.26, -0.24 }, .{ 0.26, 0.40 }, .{ -0.26, 0.40 } }, col);
                g.tri(0.10, -0.40, 0.10, -0.24, 0.26, -0.24, cut);
                g.hbar(0, 0.02, 0.30, 0.05, cut);
                g.hbar(0, 0.16, 0.30, 0.05, cut);
            },
            .open => {
                g.rect(0, -0.02, 0.74, 0.52, soft);
                g.rect(-0.22, -0.30, 0.30, 0.10, soft);
                g.quad(-0.44, -0.04, 0.36, -0.04, 0.46, 0.34, -0.34, 0.34, col);
            },
            .save => {
                g.poly(&.{ .{ -0.34, -0.34 }, .{ 0.22, -0.34 }, .{ 0.34, -0.22 }, .{ 0.34, 0.34 }, .{ -0.34, 0.34 } }, col);
                g.rect(-0.02, -0.22, 0.36, 0.18, cut);
                g.rect(0, 0.20, 0.42, 0.20, cut);
            },
            .saveas => {
                g.poly(&.{ .{ -0.40, -0.26 }, .{ 0.06, -0.26 }, .{ 0.16, -0.16 }, .{ 0.16, 0.40 }, .{ -0.40, 0.40 } }, col);
                g.rect(-0.14, -0.16, 0.30, 0.14, cut);
                g.rect(-0.12, 0.26, 0.34, 0.16, cut);
                g.bar(0.10, 0.02, 0.44, -0.40, 0.13, col);
                g.tri(0.05, 0.08, 0.16, 0.14, 0.02, 0.18, col);
            },
            .reload => {
                g.arc(0, 0.02, 0.32, 40, 330, w, col);
                g.arrowHead(mathx.cosf(mathx.radians(40)) * 0.32, 0.02 + mathx.sinf(mathx.radians(40)) * 0.32, 0.18, -60, col);
            },
            .undo => {
                g.arc(0, 0.06, 0.30, 180, 360, w, col);
                g.vbar(-0.30, 0.16, 0.22, w, col);
                g.arrowHead(-0.30, 0.30, 0.18, 90, col);
            },
            .redo => {
                g.arc(0, 0.06, 0.30, 180, 360, w, col);
                g.vbar(0.30, 0.16, 0.22, w, col);
                g.arrowHead(0.30, 0.30, 0.18, 90, col);
            },
            .eye => g.eyeInto(false),
            .eyeOff => g.eyeInto(true),
        }
    }

    /// A lens and a solid pupil — the smallest glyph in the set, about a dozen pixels, where anything more came
    fn eyeInto(g: *const G, struck: bool) void {
        const body = if (struck) g.soft else g.col;
        const w = g.w / g.s;
        g.arc(0, 0.30, 0.46, 214, 326, w, body);
        g.arc(0, -0.30, 0.46, 34, 146, w, body);
        if (struck) {
            g.bar(-0.40, 0.34, 0.40, -0.34, w * 1.3, g.col);
        } else {
            g.disc(0, 0, @max(w * 0.55, 0.15), g.col);
        }
    }
};
