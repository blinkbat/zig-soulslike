const rl = @import("raylib");
const mathx = @import("mathx.zig");

// The chrome's dressing — stone plates, gilt frames, jewels — shared by the HUD,
// the menu and the editor, the way propart.zig is shared by the props.
// Drawn AFTER the retro blit in literal screen colours (hud.zig's rule).

const rgba = mathx.rgba;
const withAlpha = mathx.withAlpha;
const u8f = mathx.u8f;

pub const INK = rgba(8, 7, 6, 255);
pub const STONE_DK = rgba(16, 14, 12, 255);
pub const STONE_LT = rgba(35, 30, 24, 255);
pub const IRON = rgba(62, 55, 46, 255);
pub const GILT_DIM = rgba(146, 124, 82, 255);
pub const GILT = rgba(198, 162, 98, 255);
pub const GILT_BRIGHT = rgba(240, 212, 146, 255);
/// THE CATCHLIGHT — the near-white every lit leading edge and fill tip is struck with. One tone,
/// carried at whatever alpha the surface wants, so a bar, a foe bar and a menu gauge agree.
pub const CATCH = rgba(255, 244, 226, 255);
/// THE HIGHLIGHTED ROW'S INK, wherever a cursor sits — the game menu and the editor's widgets each
/// held their own copy of it, which is two highlights one repaint apart.
pub const HOT = rgba(236, 210, 150, 255);

fn fi(v: i32) f32 {
    return @floatFromInt(v);
}

/// Candle-breathing alpha, phase-keyed by x so surfaces never pulse in lockstep.
pub fn flick(base: u8, x: i32) u8 {
    const t: f32 = @floatCast(rl.getTime());
    return u8f(fi(base) * (0.88 + 0.12 * mathx.sinf(t * 1.9 + fi(x) * 0.31)));
}

pub fn diamond(cx: f32, cy: f32, r: f32, col: rl.Color) void {
    rl.drawPoly(.{ .x = cx, .y = cy }, 4, r, 0, col);
}

/// A gilt jewel: dark seat, gold body, bright heart.
pub fn finial(cx: f32, cy: f32, r: f32, col: rl.Color) void {
    diamond(cx, cy, r + 1.6, withAlpha(INK, @intCast(@as(u16, 210) * col.a / 255)));
    diamond(cx, cy, r, col);
    if (r >= 3) diamond(cx, cy, r * 0.42, withAlpha(GILT_BRIGHT, col.a));
}

/// A jewel at each of a rect's four corners — the chrome's way of saying "this panel is mounted".
/// The one copy: the menu's frame, the equipment slots and the rune plate all struck their own.
pub fn cornerJewels(x: i32, y: i32, w: i32, h: i32, r: f32, col: rl.Color) void {
    for ([_][2]i32{ .{ x, y }, .{ x + w, y }, .{ x, y + h }, .{ x + w, y + h } }) |c| {
        diamond(fi(c[0]), fi(c[1]), r, col);
    }
}

/// Stacked offset shadows, widest and faintest first — lifts a card off the scene.
pub fn seat(x: i32, y: i32, w: i32, h: i32) void {
    rl.drawRectangle(x + 8, y + 11, w, h, withAlpha(rl.Color.black, 34));
    rl.drawRectangle(x + 4, y + 6, w, h, withAlpha(rl.Color.black, 56));
    rl.drawRectangle(x + 1, y + 2, w, h, withAlpha(rl.Color.black, 72));
}

/// A stone slab: lit top falling to dark, scorched edges, faint bedding courses.
pub fn plate(x: i32, y: i32, w: i32, h: i32, a: u8) void {
    rl.drawRectangleGradientV(x, y, w, h, withAlpha(STONE_LT, a), withAlpha(STONE_DK, a));
    const n = @max(@divTrunc(h, 26), 2);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const f = fi(i) + fi(x) * 0.07;
        const yy = y + 4 + @as(i32, @intFromFloat(@mod(f * 0.618, 1.0) * fi(@max(h - 8, 1))));
        const inset = 8 + @as(i32, @intFromFloat(@mod(f * 0.377, 1.0) * 26.0));
        const gw = w - inset * 2;
        if (gw <= 8) continue;
        const half = @divTrunc(gw, 2);
        const ca = u8f(24.0 * fi(a) / 255.0);
        rl.drawRectangleGradientH(x + inset, yy, half, 1, withAlpha(rl.Color.black, 0), withAlpha(rl.Color.black, ca));
        rl.drawRectangleGradientH(x + inset + half, yy, gw - half, 1, withAlpha(rl.Color.black, ca), withAlpha(rl.Color.black, 0));
    }
    if (w < 40 or h < 26) return;
    const ea = u8f(66.0 * fi(a) / 255.0);
    const eb = @min(@divTrunc(h, 4), 16);
    rl.drawRectangleGradientV(x, y, w, eb, withAlpha(rl.Color.black, ea), withAlpha(rl.Color.black, 0));
    rl.drawRectangleGradientV(x, y + h - eb, w, eb, withAlpha(rl.Color.black, 0), withAlpha(rl.Color.black, ea));
    const es = @min(@divTrunc(w, 6), 22);
    rl.drawRectangleGradientH(x, y, es, h, withAlpha(rl.Color.black, ea), withAlpha(rl.Color.black, 0));
    rl.drawRectangleGradientH(x + w - es, y, es, h, withAlpha(rl.Color.black, 0), withAlpha(rl.Color.black, ea));
}

fn rectF(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{ .x = fi(x), .y = fi(y), .width = fi(w), .height = fi(h) };
}

/// The gilt frame: hard outer edge, tarnished band, inner hairline, jewelled
/// corners — with the corner brackets gated off small surfaces.
pub fn frame(x: i32, y: i32, w: i32, h: i32, a: u8) void {
    rl.drawRectangleLinesEx(rectF(x, y, w, h), 1, withAlpha(INK, 235));
    rl.drawRectangleLinesEx(rectF(x + 2, y + 2, w - 4, h - 4), 2, withAlpha(GILT_DIM, a));
    rl.drawRectangleLinesEx(rectF(x + 6, y + 6, w - 12, h - 12), 1, withAlpha(GILT, @intCast(@as(u16, a) * 100 / 255)));
    if (w < 130 or h < 70) {
        cornerJewels(x + 3, y + 3, w - 6, h - 6, 2.6, withAlpha(GILT, a));
        return;
    }
    const arm: i32 = 13;
    const inset: i32 = 3;
    const corners = [_][4]i32{
        .{ x + inset, y + inset, 1, 1 },
        .{ x + w - inset, y + inset, -1, 1 },
        .{ x + inset, y + h - inset, 1, -1 },
        .{ x + w - inset, y + h - inset, -1, -1 },
    };
    for (corners) |c| {
        const cxi = c[0];
        const cyi = c[1];
        const dx = c[2];
        const dy = c[3];
        const hx = if (dx > 0) cxi else cxi - arm;
        const vy = if (dy > 0) cyi else cyi - arm;
        // A 1 px dark offset copy under each bracket, so it reads as raised cast metal.
        rl.drawRectangle(hx + 1, cyi + 1, arm, 2, withAlpha(rl.Color.black, 160));
        rl.drawRectangle(cxi + 1, vy + 1, 2, arm, withAlpha(rl.Color.black, 160));
        rl.drawRectangle(hx, cyi, arm, 2, withAlpha(GILT, a));
        rl.drawRectangle(cxi, vy, 2, arm, withAlpha(GILT, a));
        finial(fi(cxi) + fi(dx), fi(cyi) + fi(dy), 3.4, withAlpha(GILT, a));
        diamond(fi(cxi + dx * arm), fi(cyi) + 1, 1.7, withAlpha(GILT_DIM, a));
        diamond(fi(cxi) + 1, fi(cyi + dy * arm), 1.7, withAlpha(GILT_DIM, a));
    }
}

/// A gilt rule fading at both ends, a jewel at its heart, two attendants beside it.
pub fn divider(cx: i32, y: i32, halfW: i32, a: u8) void {
    const gap: i32 = 30;
    if (halfW > gap + 8) {
        rl.drawRectangleGradientH(cx - halfW, y, halfW - gap, 1, withAlpha(GILT, 0), withAlpha(GILT, a));
        rl.drawRectangleGradientH(cx + gap, y, halfW - gap, 1, withAlpha(GILT, a), withAlpha(GILT, 0));
    }
    finial(fi(cx), fi(y), 3.6, withAlpha(GILT, a));
    diamond(fi(cx - 20), fi(y), 2.1, withAlpha(GILT_DIM, a));
    diamond(fi(cx + 20), fi(y), 2.1, withAlpha(GILT_DIM, a));
}

/// A gilt band sweeping across `r` on a slow clock — scissored, so only the row lights.
pub fn sheen(r: rl.Rectangle, period: f32, peakA: u8) void {
    if (r.width < 48) return;
    const band = mathx.clampF(r.width * 0.30, 36, 110);
    const t: f32 = @floatCast(@mod(rl.getTime(), @as(f64, period)));
    const sx = r.x - band + (t / period) * (r.width + 2 * band);
    const half: i32 = @intFromFloat(band * 0.5);
    const clear = withAlpha(GILT_BRIGHT, 0);
    const peak = withAlpha(GILT_BRIGHT, peakA);
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
    rl.drawRectangleGradientH(@intFromFloat(sx), @intFromFloat(r.y), half, @intFromFloat(r.height), clear, peak);
    rl.drawRectangleGradientH(@intFromFloat(sx + band * 0.5), @intFromFloat(r.y), half, @intFromFloat(r.height), peak, clear);
    rl.endScissorMode();
}

/// The recessed well behind an icon or a fill: sunk fill, top-lip shadow, bottom catch.
pub fn well(x: i32, y: i32, w: i32, h: i32, a: u8) void {
    rl.drawRectangleGradientV(x, y, w, h, withAlpha(rgba(13, 11, 9, 255), a), withAlpha(rgba(6, 5, 4, 255), a));
    const lip = @min(@divTrunc(h, 5), 9);
    rl.drawRectangleGradientV(x + 1, y + 1, w - 2, lip, withAlpha(rl.Color.black, 130), withAlpha(rl.Color.black, 0));
    rl.drawRectangle(x + 2, y + h - 2, w - 4, 1, withAlpha(GILT_DIM, 56));
}

/// A warm candle pool, for the heart of an occupied slot.
const CANDLE = rgba(255, 176, 90, 255);
pub fn candle(cx: i32, cy: i32, r: f32, a: u8) void {
    rl.drawCircleGradient(cx, cy, r, withAlpha(CANDLE, a), withAlpha(CANDLE, 0));
}
