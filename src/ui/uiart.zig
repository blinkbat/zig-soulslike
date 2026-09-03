const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");


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
pub const CATCH = rgba(255, 244, 226, 255);
pub const HOT = rgba(236, 210, 150, 255);

pub const TEXT_TITLE = rgba(232, 222, 198, 255);
pub const TEXT_VALUE = rgba(216, 206, 184, 255);
pub const TEXT_DIM = rgba(150, 146, 138, 255);
pub const TEXT_HINT = rgba(128, 122, 110, 255);
pub const GOOD = rgba(146, 194, 118, 255);
pub const BAD = rgba(206, 96, 78, 255);

// **ONE PAIR OF MARKS, DEFINED HERE AND NOWHERE ELSE** (owner: use global). Souls and gold are both GILT — the
// drop itself is authored gold (`play/souls.zig`) — so they cannot be told apart by HUE.
// They separate on SHAPE and on VALUE instead, which survives both the retro filters and a 26 px plate:

/// The radius both marks are authored at. A plate is 26–32 px tall, so this is about a third of it.
pub const MARK_R: f32 = 5.2;

fn ray(cx: f32, cy: f32, ang: f32, len: f32, wid: f32, col: rl.Color) void {
    const c = mathx.cosf(ang);
    const s = mathx.sinf(ang);
    const tip = rl.Vector2.init(cx + c * len, cy + s * len);
    const a = rl.Vector2.init(cx - s * wid, cy + c * wid);
    const b = rl.Vector2.init(cx + s * wid, cy - c * wid);
    rl.drawTriangle(tip, a, b, col);
    rl.drawTriangle(tip, b, a, col);
}

/// `drawTriangle` is single-sided and the winding flips as the angle passes 180.
pub fn soulMark(cx: f32, cy: f32, r: f32, a: u8) void {
    const bloom = withAlpha(GILT, u8f(@as(f32, @floatFromInt(a)) * 0.26));
    rl.drawCircleV(rl.Vector2.init(cx, cy), r * 0.92, bloom);
    const long = withAlpha(GILT_BRIGHT, a);
    const short = withAlpha(GILT, a);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const q = std.math.pi * 0.5 * @as(f32, @floatFromInt(i));
        ray(cx, cy, q, r * 1.62, r * 0.30, long);
        ray(cx, cy, q + std.math.pi * 0.25, r * 0.86, r * 0.20, short);
    }
    rl.drawCircleV(rl.Vector2.init(cx, cy), r * 0.40, withAlpha(CATCH, a));
}

pub fn coinMark(cx: f32, cy: f32, r: f32, a: u8) void {
    const xi: i32 = @intFromFloat(cx);
    const yi: i32 = @intFromFloat(cy);
    // **WIDER THAN THE SOUL IS TALL, OR THE PAIR IS UNBALANCED.** The spark throws rays to 1.62 r, so a disc
    // at 1.0 r came back half its visual mass and read as the lesser of the two currencies. Measured against it
    // rather than picked: 1.30 r across puts the two bounding boxes within a few pixels of each other.
    const rx = r * 1.30;
    // **FLAT, OR IT IS A BALL.** The first cut ran 0.80 of the width with a big central catch-light and came
    const ry = rx * 0.60;
    rl.drawEllipse(xi, yi + 2, rx, ry, withAlpha(STONE_DK, u8f(@as(f32, @floatFromInt(a)) * 0.9)));
    rl.drawEllipse(xi, yi, rx, ry, withAlpha(GILT, a));
    rl.drawEllipse(xi, yi, rx * 0.74, ry * 0.66, withAlpha(GILT_BRIGHT, a));
    rl.drawEllipse(xi, yi, rx * 0.30, ry * 0.30, withAlpha(GILT, a));
    rl.drawCircleV(rl.Vector2.init(cx - rx * 0.50, cy - ry * 0.46), r * 0.16, withAlpha(CATCH, a));
}

pub fn fi(v: i32) f32 {
    return @floatFromInt(v);
}

pub fn flick(base: u8, x: i32) u8 {
    const t: f32 = @floatCast(rl.getTime());
    return u8f(fi(base) * (0.88 + 0.12 * mathx.sinf(t * 1.9 + fi(x) * 0.31)));
}

pub fn numeral(i: usize) [:0]const u8 {
    const N = [_][:0]const u8{ "I", "II", "III", "IV", "V", "VI", "VII", "VIII" };
    return if (i < N.len) N[i] else "-";
}

/// raylib wants ONE winding and silently drops the other.
pub fn triangle(a: rl.Vector2, b: rl.Vector2, c: rl.Vector2, col: rl.Color) void {
    const cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (cross > 0) rl.drawTriangle(a, c, b, col) else rl.drawTriangle(a, b, c, col);
}

pub fn diamond(cx: f32, cy: f32, r: f32, col: rl.Color) void {
    rl.drawPoly(.{ .x = cx, .y = cy }, 4, r, 0, col);
}

pub fn finial(cx: f32, cy: f32, r: f32, col: rl.Color) void {
    diamond(cx, cy, r + 1.6, withAlpha(INK, @intCast(@as(u16, 210) * col.a / 255)));
    diamond(cx, cy, r, col);
    if (r >= 3) diamond(cx, cy, r * 0.42, withAlpha(GILT_BRIGHT, col.a));
}

pub fn cornerJewels(x: i32, y: i32, w: i32, h: i32, r: f32, col: rl.Color) void {
    for ([_][2]i32{ .{ x, y }, .{ x + w, y }, .{ x, y + h }, .{ x + w, y + h } }) |c| {
        diamond(fi(c[0]), fi(c[1]), r, col);
    }
}

pub fn seat(x: i32, y: i32, w: i32, h: i32) void {
    rl.drawRectangle(x + 8, y + 11, w, h, withAlpha(rl.Color.black, 34));
    rl.drawRectangle(x + 4, y + 6, w, h, withAlpha(rl.Color.black, 56));
    rl.drawRectangle(x + 1, y + 2, w, h, withAlpha(rl.Color.black, 72));
}

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

pub fn rect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{ .x = fi(x), .y = fi(y), .width = fi(w), .height = fi(h) };
}

pub fn frame(x: i32, y: i32, w: i32, h: i32, a: u8) void {
    rl.drawRectangleLinesEx(rect(x, y, w, h), 1, withAlpha(INK, 235));
    rl.drawRectangleLinesEx(rect(x + 2, y + 2, w - 4, h - 4), 2, withAlpha(GILT_DIM, a));
    rl.drawRectangleLinesEx(rect(x + 6, y + 6, w - 12, h - 12), 1, withAlpha(GILT, @intCast(@as(u16, a) * 100 / 255)));
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

pub fn well(x: i32, y: i32, w: i32, h: i32, a: u8) void {
    rl.drawRectangleGradientV(x, y, w, h, withAlpha(rgba(13, 11, 9, 255), a), withAlpha(rgba(6, 5, 4, 255), a));
    const lip = @min(@divTrunc(h, 5), 9);
    rl.drawRectangleGradientV(x + 1, y + 1, w - 2, lip, withAlpha(rl.Color.black, 130), withAlpha(rl.Color.black, 0));
    rl.drawRectangle(x + 2, y + h - 2, w - 4, 1, withAlpha(GILT_DIM, 56));
}

const CANDLE = rgba(255, 176, 90, 255);
pub fn candle(cx: i32, cy: i32, r: f32, a: u8) void {
    rl.drawCircleGradient(cx, cy, r, withAlpha(CANDLE, a), withAlpha(CANDLE, 0));
}


const WELL_ON: u8 = 148;
const WELL_OFF: u8 = 68;
const SLOT_ON = rgba(180, 168, 140, 240);
const SLOT_OFF = rgba(124, 115, 98, 122);

pub fn socket(x: i32, y: i32, w: i32, h: i32, on: bool) void {
    rl.drawRectangle(x - 1, y - 1, w + 2, h + 2, withAlpha(rl.Color.black, if (on) 150 else 80));
    well(x, y, w, h, if (on) WELL_ON else WELL_OFF);
}

pub fn socketRim(x: i32, y: i32, w: i32, h: i32, on: bool) void {
    rl.drawRectangleLinesEx(rect(x, y, w, h), 1, if (on) SLOT_ON else SLOT_OFF);
}

pub fn slot(x: i32, y: i32, w: i32, h: i32, on: bool) void {
    socket(x, y, w, h, on);
    if (on) candle(x + @divTrunc(w, 2), y + @divTrunc(h, 2), fi(@min(w, h)) * 0.55, 16);
    socketRim(x, y, w, h, on);
    if (on) cornerJewels(x, y, w, h, 2.4, withAlpha(GILT_DIM, 220));
}

pub fn slotCursor(x: i32, y: i32, w: i32, h: i32, press: f32, travel: f32) void {
    const a: u8 = u8f(255.0 * mathx.clampF(travel, 0, 1));
    if (a == 0) return;
    const t: f32 = @floatCast(rl.getTime());
    const breathe = 2.2 + 1.1 * mathx.sinf(t * 3.1);
    const off: i32 = @intFromFloat(mathx.lerpF(breathe, -1.0, mathx.clampF(press, 0, 1)));
    const bx = x - off;
    const by = y - off;
    const bw = w + off * 2;
    const bh = h + off * 2;
    const arm: i32 = @max(@divTrunc(@min(bw, bh), 4), 7);
    const lit = withAlpha(GILT_BRIGHT, a);
    const under = withAlpha(rl.Color.black, @intCast(@as(u16, 190) * a / 255));
    for ([_][4]i32{
        .{ bx, by, 1, 1 },
        .{ bx + bw, by, -1, 1 },
        .{ bx, by + bh, 1, -1 },
        .{ bx + bw, by + bh, -1, -1 },
    }) |c| {
        const cx = c[0];
        const cy = c[1];
        const dx = c[2];
        const dy = c[3];
        const hx = if (dx > 0) cx else cx - arm;
        const vy = if (dy > 0) cy else cy - arm;
        rl.drawRectangle(hx + 1, cy + 1, arm, 2, under);
        rl.drawRectangle(cx + 1, vy + 1, 2, arm, under);
        rl.drawRectangle(hx, cy, arm, 2, lit);
        rl.drawRectangle(cx, vy, 2, arm, lit);
        finial(fi(cx), fi(cy), 2.8, lit);
    }
}

/// **THE CURSOR IS A LEADING BAR, AND IT IS THE ONLY THING THAT MARKS A ROW** (owner's call). Every list in the game used to set a `>` glyph in the row's left margin on TOP of the bar this same wash was already drawing — one cursor said twice, in two places that had to be kept in step. The bar is drawn HERE and nowhere else.
pub const CARET_W: i32 = 3;

pub fn caret(x: i32, y: i32, h: i32, a: u8) void {
    rl.drawRectangle(x, y, CARET_W, h, withAlpha(GILT_BRIGHT, a));
}

const ROW_WASH = rgba(255, 232, 170, 23);
pub const CARET_DIM: u8 = 120;

pub fn rowHilite(x: i32, y: i32, w: i32, h: i32) void {
    rl.drawRectangle(x, y, w, h, ROW_WASH);
    caret(x, y, h, flick(230, y));
    sheen(rect(x, y, w, h), 3.8, 24);
}

pub fn rail(x: i32, y: i32, h: i32, shown: f32, at: f32) void {
    if (shown >= 0.999) return;
    rl.drawRectangle(x, y, 3, h, withAlpha(rl.Color.black, 150));
    const nub: i32 = @intFromFloat(@max(fi(h) * mathx.clampF(shown, 0.06, 1.0), 16.0));
    const top: i32 = @intFromFloat(fi(h - nub) * mathx.clampF(at, 0, 1));
    rl.drawRectangle(x, y + top, 3, nub, withAlpha(GILT, 190));
    rl.drawRectangle(x, y + top, 3, 1, withAlpha(CATCH, 160));
}

pub fn tallyShelf(x: i32, y: i32, w: i32, h: i32) void {
    rl.drawRectangle(x, y, w, h, withAlpha(rl.Color.black, 170));
    rl.drawRectangle(x, y, w, 1, withAlpha(GILT_DIM, 70));
}
