const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const uiart = @import("uiart.zig");
const daynight = @import("../world/daynight.zig");
const itemart = @import("itemart.zig");
const item = @import("../play/item.zig");
const combat = @import("../play/combat.zig");
const gfx = @import("../gfx/gfx.zig");

const rgba = mathx.rgba;

var haveFont = false;
var font: rl.Font = undefined;
var haveBig = false;
var fontBig: rl.Font = undefined;

const FONT_PATH = "assets/Balthazar-Regular.ttf";
const ATLAS_PX = 96;
const ATLAS_BIG_PX = 160; // the cinematic caption atlas (YOU DIED draws near 90 px)

pub const TITLE: i32 = 34;
pub const BODY: i32 = 22;
pub const SMALL: i32 = 20;
pub const HINT: i32 = 19;
pub const TINY: i32 = 16;

fn atlas(path: [:0]const u8, px: i32) ?rl.Font {
    var f = rl.loadFontEx(path, px, null) catch return null;
    if (f.glyphCount == 0) {
        rl.unloadFont(f);
        return null;
    }
    rl.genTextureMipmaps(&f.texture);
    rl.setTextureFilter(f.texture, .trilinear);
    return f;
}

pub fn init() void {
    if (atlas(FONT_PATH, ATLAS_PX)) |f| {
        font = f;
        haveFont = true;
    }
    if (atlas(FONT_PATH, ATLAS_BIG_PX)) |f| {
        fontBig = f;
        haveBig = true;
    }
    initMono();
}

pub fn deinit() void {
    if (haveFont) rl.unloadFont(font);
    haveFont = false;
    if (haveBig) rl.unloadFont(fontBig);
    haveBig = false;
    if (haveMono) rl.unloadFont(monoFont);
    haveMono = false;
    veilFree();
}

var veil: ?rl.RenderTexture2D = null;

fn veilFree() void {
    if (veil) |rt| rl.unloadRenderTexture(rt);
    veil = null;
}

fn veilFor(w: i32, h: i32) ?rl.RenderTexture2D {
    if (w <= 0 or h <= 0) return null;
    if (veil) |rt| {
        if (rt.texture.width == w and rt.texture.height == h) return rt;
        veilFree();
    }
    veil = rl.loadRenderTexture(w, h) catch return null;
    return veil;
}

pub fn beginChrome(k: f32) bool {
    if (k >= 0.999) return false;
    const rt = veilFor(rl.getScreenWidth(), rl.getScreenHeight()) orelse return false;
    rl.beginTextureMode(rt);
    rl.clearBackground(rgba(0, 0, 0, 0));
    return true;
}

pub fn endChrome(k: f32) void {
    rl.endTextureMode();
    const rt = veil orelse return;
    const w: f32 = @floatFromInt(rt.texture.width);
    const h: f32 = @floatFromInt(rt.texture.height);
    rl.drawTexturePro(
        rt.texture,
        .{ .x = 0, .y = 0, .width = w, .height = -h },
        .{ .x = 0, .y = 0, .width = w, .height = h },
        .{ .x = 0, .y = 0 },
        0,
        mathx.withAlpha(rl.Color.white, mathx.u8f(255.0 * mathx.clampF(k, 0, 1))),
    );
}

pub fn textW(s: [:0]const u8, size: i32) i32 {
    if (!haveFont) return rl.measureText(s, size);
    return @intFromFloat(rl.measureTextEx(font, s, @floatFromInt(size), 0).x);
}

fn drawStr(s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
    if (!haveFont) {
        rl.drawText(s, x, y, size, col);
        return;
    }
    rl.drawTextEx(font, s, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, @floatFromInt(size), 0, col);
}

pub fn text(s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
    const off: i32 = @max(@divTrunc(size, 14), 1);
    drawStr(s, x + off, y + off, size, mathx.withAlpha(rl.Color.black, @intCast(@as(u16, 200) * col.a / 255)));
    drawStr(s, x, y, size, col);
}

pub fn lineH(size: i32) i32 {
    return size + @divTrunc(size, 3);
}

/// Metal-leaf engraving: the same string re-drawn through two scissored bands so the grade rides the letterforms. Collapses below ~20 px — titles only.
pub fn engraved(s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
    text(s, x, y, size, col);
    const w = textW(s, size);
    var lit = mathx.lerpColor(col, rgba(255, 246, 218, 255), 0.34);
    lit.a = col.a;
    rl.beginScissorMode(x - 2, y, w + 4, @divTrunc(size * 45, 100));
    drawStr(s, x, y, size, lit);
    rl.endScissorMode();
    var deep = mathx.lerpColor(col, rl.Color.black, 0.38);
    deep.a = col.a;
    rl.beginScissorMode(x - 2, y + @divTrunc(size * 72, 100), w + 4, size);
    drawStr(s, x, y, size, deep);
    rl.endScissorMode();
}

const MONO_CANDIDATES = [_][:0]const u8{
    "C:/Windows/Fonts/consola.ttf",
    "C:/Windows/Fonts/lucon.ttf",
    "C:/Windows/Fonts/cour.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
};
const MONO_ATLAS_PX = 40;

var haveMono = false;
var monoFont: rl.Font = undefined;

pub const MONO: i32 = 18;

fn initMono() void {
    for (MONO_CANDIDATES) |path| {
        if (atlas(path, MONO_ATLAS_PX)) |f| {
            monoFont = f;
            haveMono = true;
            return;
        }
    }
}

pub fn mono(s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
    if (!haveMono) {
        rl.drawText(s, x, y, size, col);
        return;
    }
    rl.drawTextEx(monoFont, s, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, @floatFromInt(size), 0, col);
}

pub fn monoW(s: [:0]const u8, size: i32) i32 {
    if (!haveMono) return rl.measureText(s, size);
    return @intFromFloat(rl.measureTextEx(monoFont, s, @floatFromInt(size), 0).x);
}

pub fn monoLineH(size: i32) i32 {
    return size + @divTrunc(size, 4);
}

pub fn textRight(s: [:0]const u8, pad: i32, y: i32, size: i32, col: rl.Color) void {
    text(s, rl.getScreenWidth() - textW(s, size) - pad, y, size, col);
}

pub fn bigCentered(s: [:0]const u8, cx: f32, cy: f32, size: f32, spacing: f32, col: rl.Color) void {
    if (!haveBig) {
        const si: i32 = @intFromFloat(size);
        const w = rl.measureText(s, si);
        rl.drawText(s, @as(i32, @intFromFloat(cx)) - @divTrunc(w, 2), @as(i32, @intFromFloat(cy - size * 0.5)), si, col);
        return;
    }
    const m = rl.measureTextEx(fontBig, s, size, spacing);
    rl.drawTextEx(fontBig, s, .{ .x = cx - m.x * 0.5, .y = cy - m.y * 0.5 }, size, spacing, col);
}



pub const PadBtn = enum { a, b, x, y };
pub const Dir = enum { up, down, left, right, leftright, updown };

pub const Glyph = union(enum) {
    face: PadBtn,
    dpad: Dir,
    bumper: [:0]const u8,
    menu: void,
};

pub const Hint = struct { glyph: Glyph, label: [:0]const u8 };

/// THE BUTTONS THE GAME ACTUALLY BINDS, named once so a caption and the press cannot drift.
pub const BTN_INTERACT: PadBtn = .y;
pub const BTN_CONFIRM: PadBtn = .a;
pub const BTN_JUMP: PadBtn = .a;
pub const BTN_BACK: PadBtn = .b;
pub const BTN_QUICK: PadBtn = .x;

pub fn padOf(b: PadBtn) rl.GamepadButton {
    return switch (b) {
        .a => .right_face_down,
        .b => .right_face_right,
        .x => .right_face_left,
        .y => .right_face_up,
    };
}

fn padBtnColor(b: PadBtn) rl.Color {
    return switch (b) {
        .a => rgba(94, 178, 66, 255),
        .b => rgba(214, 62, 52, 255),
        .x => rgba(46, 120, 205, 255),
        .y => rgba(234, 190, 58, 255),
    };
}
fn padBtnLetter(b: PadBtn) [:0]const u8 {
    return switch (b) {
        .a => "A",
        .b => "B",
        .x => "X",
        .y => "Y",
    };
}

const PAD_BODY = rgba(27, 23, 19, 255);
const PAD_INK = rgba(226, 210, 180, 245);

fn glyphLabel(s: [:0]const u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
    const w = textW(s, size);
    const y = cy - @divTrunc(size * 62, 100);
    drawStr(s, cx - @divTrunc(w, 2) + 1, y + 1, size, rgba(0, 0, 0, 150));
    drawStr(s, cx - @divTrunc(w, 2), y, size, col);
}

pub fn padFace(cx: i32, cy: i32, r: i32, b: PadBtn) void {
    const col = padBtnColor(b);
    const rf: f32 = @floatFromInt(r);
    const cv = rl.Vector2{ .x = @floatFromInt(cx), .y = @floatFromInt(cy) };
    rl.drawCircleV(cv, rf + 1.5, mathx.withAlpha(uiart.INK, 235));
    rl.drawCircleV(cv, rf, PAD_BODY);
    rl.drawCircleV(.{ .x = cv.x, .y = cv.y - rf * 0.16 }, rf * 0.80, rgba(40, 34, 28, 255));
    rl.drawCircleLines(cx, cy, rf - 1.0, mathx.withAlpha(col, 245));
    rl.drawCircleLines(cx, cy, rf - 2.2, mathx.withAlpha(col, 150));
    glyphLabel(padBtnLetter(b), cx, cy, @max(@divTrunc(r * 5, 4), 11), mathx.lerpColor(col, rl.Color.white, 0.38));
}

pub fn padDpad(cx: i32, cy: i32, r: i32, dir: Dir) void {
    const rf: f32 = @floatFromInt(r);
    const tile = uiart.rect(cx - r + 1, cy - r + 1, r * 2 - 2, r * 2 - 2);
    rl.drawRectangleRounded(tile, 0.35, 6, PAD_BODY);
    rl.drawRectangleRoundedLinesEx(tile, 0.35, 6, 1, mathx.withAlpha(uiart.GILT_DIM, 150));
    const up = dir == .up or dir == .updown;
    const dn = dir == .down or dir == .updown;
    const lf = dir == .left or dir == .leftright;
    const rt = dir == .right or dir == .leftright;
    const gh = rf * 2;
    const cw = gh * 0.16;
    const off = gh * 0.30;
    const tip = gh * 0.40;
    const xf: f32 = @floatFromInt(cx);
    const yf: f32 = @floatFromInt(cy);
    const on = uiart.GILT_BRIGHT;
    const dim = mathx.withAlpha(uiart.GILT_DIM, 110);
    const chev = struct {
        fn v(ax: f32, ay: f32, bx: f32, by: f32, c: rl.Color) void {
            rl.drawLineEx(.{ .x = ax, .y = ay }, .{ .x = bx, .y = by }, 1.6, c);
        }
    }.v;
    chev(xf - cw, yf - off, xf, yf - tip, if (up) on else dim);
    chev(xf, yf - tip, xf + cw, yf - off, if (up) on else dim);
    chev(xf - cw, yf + off, xf, yf + tip, if (dn) on else dim);
    chev(xf, yf + tip, xf + cw, yf + off, if (dn) on else dim);
    chev(xf - off, yf - cw, xf - tip, yf, if (lf) on else dim);
    chev(xf - tip, yf, xf - off, yf + cw, if (lf) on else dim);
    chev(xf + off, yf - cw, xf + tip, yf, if (rt) on else dim);
    chev(xf + tip, yf, xf + off, yf + cw, if (rt) on else dim);
}

fn padPill(r: rl.Rectangle) void {
    rl.drawRectangleRounded(r, 0.6, 6, rgba(34, 29, 24, 235));
    rl.drawRectangleRoundedLinesEx(r, 0.6, 6, 1, mathx.withAlpha(uiart.GILT_DIM, 160));
}

const PAD_GLYPH_TEXT: i32 = 12;
const PAD_MENU_W: i32 = 24;
fn padBumperW(label: [:0]const u8) i32 {
    return textW(label, PAD_GLYPH_TEXT) + 12;
}

pub fn padMenu(cx: i32, cy: i32) void {
    const w = PAD_MENU_W;
    const h: i32 = 16;
    padPill(uiart.rect(cx - @divTrunc(w, 2), cy - @divTrunc(h, 2), w, h));
    var i: i32 = -1;
    while (i <= 1) : (i += 1) {
        const ly: f32 = @as(f32, @floatFromInt(cy)) + @as(f32, @floatFromInt(i)) * 3.5;
        rl.drawLineEx(
            .{ .x = @as(f32, @floatFromInt(cx)) - 5, .y = ly },
            .{ .x = @as(f32, @floatFromInt(cx)) + 5, .y = ly },
            1.5,
            PAD_INK,
        );
    }
}

pub fn padBumper(cx: i32, cy: i32, label: [:0]const u8) void {
    const w = padBumperW(label);
    const h: i32 = 18;
    padPill(uiart.rect(cx - @divTrunc(w, 2), cy - @divTrunc(h, 2), w, h));
    glyphLabel(label, cx, cy, PAD_GLYPH_TEXT, PAD_INK);
}

pub fn glyphW(g: Glyph, r: i32) i32 {
    return switch (g) {
        .face, .dpad => r * 2,
        .bumper => |b| padBumperW(b),
        .menu => PAD_MENU_W,
    };
}

pub fn drawGlyph(g: Glyph, cx: i32, cy: i32, r: i32) void {
    switch (g) {
        .face => |b| padFace(cx, cy, r, b),
        .dpad => |d| padDpad(cx, cy, r, d),
        .bumper => |b| padBumper(cx, cy, b),
        .menu => padMenu(cx, cy),
    }
}

pub const GLYPH_R: i32 = 9;
const GLYPH_GAP: i32 = 7;
const HINT_PAD: i32 = 24;

pub fn hintRowW(hints: []const Hint, size: i32) i32 {
    var total: i32 = 0;
    for (hints, 0..) |h, i| {
        total += glyphW(h.glyph, GLYPH_R) + GLYPH_GAP + textW(h.label, size);
        if (i + 1 < hints.len) total += HINT_PAD;
    }
    return total;
}

pub fn hintRowAt(hints: []const Hint, x0: i32, cy: i32, size: i32, col: rl.Color) void {
    const ty = cy - @divTrunc(lineH(size), 2);
    var x = x0;
    for (hints) |h| {
        const gw = glyphW(h.glyph, GLYPH_R);
        drawGlyph(h.glyph, x + @divTrunc(gw, 2), cy, GLYPH_R);
        x += gw + GLYPH_GAP;
        text(h.label, x, ty, size, col);
        x += textW(h.label, size) + HINT_PAD;
    }
}

pub fn hintRow(hints: []const Hint, cy: i32, size: i32, col: rl.Color) void {
    if (hints.len == 0) return;
    const total = hintRowW(hints, size);
    const x0 = @divTrunc(rl.getScreenWidth() - total, 2);
    hintRowAt(hints, x0, cy, size, col);
    const cyf: f32 = @floatFromInt(cy);
    const a: u8 = @intCast(@as(u16, 150) * @as(u16, col.a) / 255);
    uiart.diamond(@floatFromInt(x0 - 16), cyf, 2.4, mathx.withAlpha(uiart.GILT_DIM, a));
    uiart.diamond(@floatFromInt(x0 + total + 16), cyf, 2.4, mathx.withAlpha(uiart.GILT_DIM, a));
}

pub const MARGIN: i32 = 30;
const BAR_TOP: i32 = 24;
const BAR_GAP: i32 = 6;
const DIAL_R: i32 = 21;
const DIAL_GAP: i32 = 14;
const BARS_X: i32 = MARGIN + DIAL_R * 2 + DIAL_GAP;
/// **THE STATUS BUILDUP METERS SIT AT THE BOTTOM MIDDLE** (owner) — stacked upward off this margin, the
/// status word above them. The vitals keep the top-left corner beside the day dial.
const STATUS_BOTTOM_MARGIN: i32 = 34;
fn centreX(w: i32) i32 {
    return @divTrunc(rl.getScreenWidth() - w, 2);
}
const HP_W: i32 = 268;
const HP_H: i32 = 15;
const FP_W: i32 = 182;
const FP_H: i32 = 11;
const ST_W: i32 = 232;
const ST_H: i32 = 11;

const TRACK = rgba(16, 13, 11, 186);
const RIM = rgba(116, 104, 84, 255);
const FRAME = mathx.withAlpha(RIM, 210);
const HP_HI = rgba(158, 36, 28, 255);
const HP_LO = rgba(96, 20, 16, 255);
const HP_TP = rgba(204, 66, 52, 255);
const FP_HI = rgba(50, 102, 140, 255);
const FP_LO = rgba(24, 56, 84, 255);
const FP_TP = rgba(88, 148, 188, 255);
const ST_HI = rgba(112, 136, 58, 255);
const ST_LO = rgba(60, 78, 28, 255);
const ST_TP = rgba(154, 178, 88, 255);
const CHIP = rgba(180, 98, 58, 226);
const WARN = rgba(232, 96, 72, 255);
const WARN_LT = rgba(240, 150, 120, 255);

var chip: f32 = 1;
var chipHold: f32 = 0;
var chipLast: f32 = 1;
const CHIP_HOLD = 0.42;
const CHIP_RATE = 0.55;

fn refuseRing(x: i32, y: i32, w: i32, h: i32, k: f32) void {
    if (k <= 0.001) return;
    const a: u8 = @intFromFloat(230 * mathx.clampF(k, 0, 1));
    rl.drawRectangleLines(x - 2, y - 2, w + 4, h + 4, mathx.withAlpha(WARN, a));
    rl.drawRectangleLines(x - 3, y - 3, w + 6, h + 6, mathx.withAlpha(WARN, a / 2));
}

pub const Status = struct { frac: f32 = 0, on: bool = false };

/// **AN AILMENT IS ITS GLYPH.** Ten meters is more rows than any player will read as words, so the icon IS the
/// name (owner: make it synonymous with that status) — drawn beside its own bar here, and the same call is what
/// the book and an item's line use, so a status is never described two ways. **HERE AND NOT `uiart`**: that file
/// is dressing and knows nothing about the game, the same reason the pad glyphs live in this one.
/// Vector, from primitives, so it reads at 8 px and at 40.
pub fn ailTint(a: combat.Ail) rl.Color {
    return switch (a) {
        .poison => rgba(150, 96, 190, 255),
        .burning => rgba(236, 126, 48, 255),
        .chill => CHILL_STRIP,
        .stun => rgba(240, 228, 122, 255),
        .bleed => rgba(198, 44, 40, 255),
        .sleep => rgba(142, 152, 212, 255),
        .confusion => itemart.BABBLE_GILL,
        .charm => itemart.CHARM_ROSE,
        .berserk => rgba(242, 82, 40, 255),
        .stupefy => rgba(174, 162, 194, 255),
    };
}

fn gl(x0: f32, y0: f32, x1: f32, y1: f32, w: f32, c: rl.Color) void {
    rl.drawLineEx(.{ .x = x0, .y = y0 }, .{ .x = x1, .y = y1 }, w, c);
}

/// One silhouette apiece — told apart by SHAPE with the colour taken away, the way `elemfx`'s four are.
pub fn ailGlyph(a: combat.Ail, cx: f32, cy: f32, size: f32, col: rl.Color) void {
    const r = size * 0.5;
    const w = mathx.maxF(size * 0.13, 1.0);
    switch (a) {
        .poison => {
            rl.drawTriangle(
                .{ .x = cx, .y = cy - r },
                .{ .x = cx - r * 0.62, .y = cy + r * 0.15 },
                .{ .x = cx + r * 0.62, .y = cy + r * 0.15 },
                col,
            );
            rl.drawCircleV(.{ .x = cx, .y = cy + r * 0.22 }, r * 0.62, col);
        },
        // THREE drops falling off the line — the same fluid as the poison, told apart by count and slant.
        .bleed => {
            for ([_]f32{ -0.55, 0.05, 0.65 }, [_]f32{ 0.5, -0.1, 0.35 }) |dx, dy| {
                rl.drawCircleV(.{ .x = cx + r * dx, .y = cy + r * dy }, r * 0.28, col);
                gl(cx + r * dx, cy + r * dy - r * 0.30, cx + r * dx, cy + r * dy - r * 0.62, w * 0.8, col);
            }
        },
        // A TONGUE: two nested points, the inner one shorter, which is what reads as flame and not as an arrow.
        .burning => {
            rl.drawTriangle(
                .{ .x = cx, .y = cy - r },
                .{ .x = cx - r * 0.66, .y = cy + r * 0.7 },
                .{ .x = cx + r * 0.66, .y = cy + r * 0.7 },
                col,
            );
            rl.drawTriangle(
                .{ .x = cx, .y = cy + r * 0.7 },
                .{ .x = cx - r * 0.34, .y = cy - r * 0.15 },
                .{ .x = cx + r * 0.34, .y = cy - r * 0.15 },
                mathx.withAlpha(rl.Color.black, 120),
            );
        },
        // Six spokes. Not four: a cross is a plus sign, and a plus sign is already health everywhere.
        .chill => {
            var i: usize = 0;
            while (i < 3) : (i += 1) {
                const th = mathx.radians(60.0 * @as(f32, @floatFromInt(i)) + 90.0);
                const dx = mathx.cosf(th) * r;
                const dy = mathx.sinf(th) * r;
                gl(cx - dx, cy - dy, cx + dx, cy + dy, w, col);
            }
        },
        // The only glyph here with a hard corner in it.
        .stun => {
            gl(cx + r * 0.45, cy - r, cx - r * 0.30, cy - r * 0.05, w * 1.15, col);
            gl(cx - r * 0.30, cy - r * 0.05, cx + r * 0.25, cy - r * 0.05, w * 1.15, col);
            gl(cx + r * 0.25, cy - r * 0.05, cx - r * 0.45, cy + r, w * 1.15, col);
        },
        // **THE zZZ HE ASKED FOR**, and the one glyph that is a letter — it is the picture everyone already knows.
        .sleep => {
            const zs = [_][3]f32{ .{ -0.55, 0.55, 0.42 }, .{ 0.15, -0.05, 0.55 }, .{ 0.62, -0.62, 0.38 } };
            for (zs) |z| {
                const s = r * z[2];
                const x = cx + r * z[0];
                const y = cy + r * z[1];
                gl(x - s, y - s, x + s, y - s, w * 0.85, col);
                gl(x + s, y - s, x - s, y + s, w * 0.85, col);
                gl(x - s, y + s, x + s, y + s, w * 0.85, col);
            }
        },
        // Two arrows crossing: it is swinging, and not at what it meant to.
        .confusion => {
            gl(cx - r * 0.8, cy - r * 0.6, cx + r * 0.8, cy + r * 0.6, w, col);
            gl(cx + r * 0.8, cy - r * 0.6, cx - r * 0.8, cy + r * 0.6, w, col);
            rl.drawCircleV(.{ .x = cx + r * 0.8, .y = cy + r * 0.6 }, w * 1.3, col);
            rl.drawCircleV(.{ .x = cx - r * 0.8, .y = cy + r * 0.6 }, w * 1.3, col);
        },
        // A heart, because it has changed whose side it is on.
        .charm => {
            rl.drawCircleV(.{ .x = cx - r * 0.38, .y = cy - r * 0.28 }, r * 0.44, col);
            rl.drawCircleV(.{ .x = cx + r * 0.38, .y = cy - r * 0.28 }, r * 0.44, col);
            rl.drawTriangle(
                .{ .x = cx, .y = cy + r * 0.82 },
                .{ .x = cx - r * 0.80, .y = cy - r * 0.16 },
                .{ .x = cx + r * 0.80, .y = cy - r * 0.16 },
                col,
            );
        },
        // Two chevrons up — the same arrow a level-up wears, doubled, because it is a boost with a bill.
        .berserk => {
            for ([_]f32{ 0.30, -0.35 }) |off| {
                gl(cx - r * 0.75, cy + r * (off + 0.45), cx, cy + r * (off - 0.35), w * 1.1, col);
                gl(cx, cy + r * (off - 0.35), cx + r * 0.75, cy + r * (off + 0.45), w * 1.1, col);
            }
        },
        // A spiral going in: the one glyph with no straight line in it at all.
        .stupefy => {
            var i: usize = 0;
            const steps = 26;
            var prev = rl.Vector2{ .x = cx, .y = cy };
            while (i < steps) : (i += 1) {
                const u = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps));
                const th = u * std.math.tau * 1.6;
                const rr = r * u;
                const p = rl.Vector2{ .x = cx + mathx.cosf(th) * rr, .y = cy + mathx.sinf(th) * rr };
                rl.drawLineEx(prev, p, w * 0.9, col);
                prev = p;
            }
        },
    }
}

const PSN_W: i32 = 196;
const PSN_H: i32 = 9;
/// **A ROW PER METER, GLYPH FIRST** (owner: separate rows for each status buildup, along with an icon for each).
/// Centred at the bottom of the screen, laid UPWARD from `bottomY` in `Ail` order and only what is actually
/// filling — so the same status is always the same distance from the floor. Returns the top of the stack,
/// which is where the word goes.
fn statusBarsUp(bottomY: i32, ails: Ails) i32 {
    const x = centreX(PSN_W);
    var yy = bottomY - PSN_H;
    for (ails, 0..) |s, i| {
        if (s.frac <= 0.001) continue;
        const a: combat.Ail = @enumFromInt(i);
        const tint = ailTint(a);
        ailGlyph(a, @as(f32, @floatFromInt(x - PSN_GLYPH)), @as(f32, @floatFromInt(yy)) + @as(f32, PSN_H) * 0.5, PSN_GLYPH_S, tint);
        const hi = if (s.on) tint else mathx.withAlpha(tint, 165);
        bar(x, yy, PSN_W, PSN_H, s.frac, 0, hi, mathx.withAlpha(hi, 150), mathx.withAlpha(uiart.CATCH, 190));
        yy -= PSN_H + BAR_GAP;
    }
    return yy + PSN_H;
}
const PSN_GLYPH: i32 = 15;
const PSN_GLYPH_S: f32 = 13.0;


const PORT_RT_W: i32 = 320;
const PORT_RT_H: i32 = 360;
var portRT: ?rl.RenderTexture2D = null;

pub const PORTRAIT_YAW: f32 = 34.0;
pub const PORTRAIT_PITCH: f32 = 0.05;
pub const PORTRAIT_FOV: f32 = 34.0;

pub fn unloadPortrait() void {
    if (portRT) |t| rl.unloadRenderTexture(t);
    portRT = null;
    if (spiritRT) |t| rl.unloadRenderTexture(t);
    spiritRT = null;
    spiritHeld = false;
}

/// WHAT IT TAKES TO PHOTOGRAPH A BODY: the scene to draw it through, the point to frame on, where the camera stands relative to that point, and how to draw the thing. `drawFn` is a callback so this file never has to know what a wanderer or a wolf is.
pub const LivePortrait = struct {
    scene: *gfx.Scene,
    focus: rl.Vector3,
    yaw: f32,
    pitch: f32,
    dist: f32,
    fov: f32 = 34.0,
    /// What the target is wiped to before the subject goes in. A FIELD because the book's doll stands against its own near-black and the head shots against theirs.
    clear: rl.Color = PORT_CLEAR,
    ctx: *const anyopaque,
    drawFn: *const fn (*const anyopaque) void,
};

const PORT_CLEAR = rgba(13, 12, 11, 255);

/// **TAKING THE PICTURE AND MOUNTING IT ARE TWO CALLS, AND THE SPLIT IS LOAD-BEARING.** `endTextureMode`
/// restores the DEFAULT framebuffer, not whatever was bound before it, so a render nested inside another target
/// redirects the rest of the frame at the backbuffer. The chrome fade is such a target, so the toast RENDERS
/// before it opens and only BLITS within. **RE-TAKEN EVERY FRAME, AND THAT IS MEASURED**: one target switch, one
/// shader bind and the subject's own meshes — 27 for the wolf, 18 for a wanderer — against a full shadow pass over hundreds.
pub fn renderPortrait(p: LivePortrait) bool {
    if (portRT == null) portRT = rl.loadRenderTexture(PORT_RT_W, PORT_RT_H) catch null;
    const rt = portRT orelse return false;
    renderInto(rt, p);
    return true;
}

/// **THE PHOTOGRAPH ITSELF, INTO WHATEVER TARGET THE CALLER OWNS.** `renderPortrait` and `takeSpiritFace` are this plus a target of their own size; the book's doll is 460x760 against their 320x360 and so keeps its own — but it may not keep its own COPY of the nine calls, and the `endTextureMode` law is stated in exactly one place.
pub fn renderIntoTarget(rt: rl.RenderTexture2D, p: LivePortrait) void {
    renderInto(rt, p);
}

fn renderInto(rt: rl.RenderTexture2D, p: LivePortrait) void {
    const cp = mathx.cosf(p.pitch);
    const cam = rl.Camera3D{
        .position = mathx.v3(
            p.focus.x + mathx.sinf(p.yaw) * cp * p.dist,
            p.focus.y + mathx.sinf(p.pitch) * p.dist,
            p.focus.z + mathx.cosf(p.yaw) * cp * p.dist,
        ),
        .target = p.focus,
        .up = mathx.v3(0, 1, 0),
        .fovy = p.fov,
        .projection = .perspective,
    };
    rl.beginTextureMode(rt);
    rl.clearBackground(p.clear);
    rl.beginMode3D(cam);
    p.scene.bind(cam.position);
    p.scene.shadowsOff();
    p.scene.setLights(&.{});
    p.scene.setGround(false);
    p.drawFn(p.ctx);
    rl.endMode3D();
    rl.endTextureMode();
}

const SPIRIT_RT: i32 = 128;
var spiritRT: ?rl.RenderTexture2D = null;
var spiritHeld = false;

pub fn takeSpiritFace(p: LivePortrait) bool {
    if (spiritRT == null) spiritRT = rl.loadRenderTexture(SPIRIT_RT, SPIRIT_RT) catch null;
    const rt = spiritRT orelse return false;
    renderInto(rt, p);
    spiritHeld = true;
    return true;
}

pub fn hasSpiritFace() bool {
    return spiritHeld;
}

pub fn dropSpiritFace() void {
    spiritHeld = false;
}

fn blitSpiritFace(dst: rl.Rectangle, tint: rl.Color) void {
    const rt = spiritRT orelse return;
    const w: f32 = @floatFromInt(SPIRIT_RT);
    rl.drawTexturePro(rt.texture, .{ .x = 0, .y = 0, .width = w, .height = -w }, dst, .{ .x = 0, .y = 0 }, 0, tint);
}

pub fn blitPortrait(dst: rl.Rectangle, tint: rl.Color) void {
    const rt = portRT orelse return;
    rl.drawTexturePro(
        rt.texture,
        .{ .x = 0, .y = 0, .width = @floatFromInt(PORT_RT_W), .height = -@as(f32, @floatFromInt(PORT_RT_H)) },
        dst,
        .{ .x = 0, .y = 0 },
        0,
        tint,
    );
}

pub fn livePortrait(p: LivePortrait, dst: rl.Rectangle, tint: rl.Color) void {
    if (renderPortrait(p)) blitPortrait(dst, tint);
}


/// The portrait square (owner: shrink the summon's portrait and bar). It was 52 against a 268 px HP bar — a companion taking a third of the width of the thing keeping you alive.
const SP_FACE: i32 = 34;
const SP_BAR_H: i32 = 9;
const SP_BAR_W: i32 = @divTrunc(HP_W, 2);
const SP_GAP: i32 = 6;
const SP_TOP: i32 = 12;
const SP_SLIDE: f32 = 14.0;
const SP_LIFE_HI = rgba(150, 200, 226, 255);
const SP_LIFE_LO = rgba(58, 92, 116, 255);
const SP_LIFE_TP = rgba(206, 234, 248, 255);

const BARS_BOTTOM: i32 = BAR_TOP + BARS_H + BAR_GAP + 2;

/// `k` is the fade, 0..1 — held by the game because the spirit's body is gone before the toast has finished leaving, and a panel that reads its own subject cannot outlive it.
pub fn spiritPanel(hasFace: bool, name: [:0]const u8, hp: f32, k: f32) void {
    if (k <= 0.004) return;
    const kk = mathx.clampF(k, 0, 1);
    const a: u8 = @intFromFloat(255.0 * kk);
    const lift: i32 = @intFromFloat((1.0 - kk) * SP_SLIDE);
    const x = MARGIN;
    const y = BARS_BOTTOM + SP_TOP + lift;
    const dst = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(SP_FACE),
        .height = @floatFromInt(SP_FACE),
    };
    const tx = if (hasFace) x + SP_FACE + SP_GAP else x;
    if (hasFace) {
        uiart.well(x, y, SP_FACE, SP_FACE, a);
        blitSpiritFace(dst, mathx.withAlpha(rl.Color.white, a));
        rl.drawRectangleLinesEx(dst, 1, mathx.withAlpha(uiart.GILT_DIM, @min(a, 110)));
    }
    text(name, tx, y + 2, TINY, mathx.withAlpha(uiart.GILT, a));
    const by = y + SP_FACE - SP_BAR_H;
    bar(tx, by, SP_BAR_W, SP_BAR_H, mathx.clampF(hp, 0, 1), 0, SP_LIFE_HI, SP_LIFE_LO, SP_LIFE_TP);
}

/// **THE WORD A STATUS SAYS WHEN IT LANDS, AND THE ONE THAT SAYS NOTHING.** A stun is the one status the
/// player is already being told about by the thing that took his feet, and a caption on that frame is noise
/// laid over the frame he can least afford to read (owner: don't show one for stun/heavy stun).
fn ailWord(a: combat.Ail) ?[:0]const u8 {
    return switch (a) {
        .poison => "Poisoned!",
        .burning => "Burning!",
        .chill => "Chilled!",
        .bleed => "Bled!",
        .sleep => "Asleep!",
        .confusion => "Confused!",
        .charm => "Charmed!",
        .berserk => "Enraged!",
        .stupefy => "Stupefied!",
        .stun => null,
    };
}

const FLASH_IN: f32 = 0.16;
const FLASH_HOLD: f32 = 0.90;
const FLASH_OUT: f32 = 0.60;
const FLASH_DUR: f32 = FLASH_IN + FLASH_HOLD + FLASH_OUT;
/// How far the word drifts up over its life. It ARRIVES rather than appearing, which is what stops a caption
/// on a busy frame reading as a HUD element that was always there.
const FLASH_RISE: f32 = 9.0;
var flashLeft: f32 = 0;
var flashAil: combat.Ail = .poison;
var ailWas: [combat.NAIL]bool = [_]bool{false} ** combat.NAIL;

/// The rising edge of a meter actually PROCCING, watched here rather than plumbed in: `Status.on` is already
/// the fact, and the game hands it over every frame.
fn watchAils(dt: f32, psn: Ails) void {
    for (psn, 0..) |s, i| {
        const a: combat.Ail = @enumFromInt(i);
        if (s.on and !ailWas[i] and ailWord(a) != null) {
            flashLeft = FLASH_DUR;
            flashAil = a;
        }
        ailWas[i] = s.on;
    }
    if (flashLeft > 0) flashLeft = mathx.maxF(0, flashLeft - dt);
}

/// FADES IN AND THEN OUT (owner), off its own clock and nothing else.
fn flashAmt() f32 {
    if (flashLeft <= 0) return 0;
    const spent = FLASH_DUR - flashLeft;
    if (spent < FLASH_IN) return mathx.smoothstep(0, FLASH_IN, spent);
    if (flashLeft > FLASH_OUT) return 1;
    return mathx.smoothstep(0, FLASH_OUT, flashLeft);
}

fn statusFlash(topY: i32) void {
    const k = flashAmt();
    if (k <= 0.004) return;
    const s = ailWord(flashAil) orelse return;
    const a: u8 = @intFromFloat(255.0 * k);
    const lift: i32 = @intFromFloat((1.0 - k) * FLASH_RISE);
    const y = topY - lineH(SMALL) - 4 + lift;
    text(s, @divTrunc(rl.getScreenWidth() - textW(s, SMALL), 2), y, SMALL, mathx.withAlpha(ailTint(flashAil), a));
}

pub fn vitals(dt: f32, hp: f32, fp: f32, stam: f32, stamRefused: f32, fpRefused: f32, windedTo: f32, psn: Ails) void {
    if (hp > chip) {
        chip = hp;
        chipHold = 0;
    } else {
        if (hp < chipLast - 1e-4) chipHold = CHIP_HOLD;
        if (chipHold > 0) chipHold -= dt else chip = mathx.maxF(hp, chip - CHIP_RATE * dt);
    }
    chipLast = hp;
    watchAils(dt, psn);

    var y = BAR_TOP;
    bar(BARS_X, y, HP_W, HP_H, hp, chip, HP_HI, HP_LO, HP_TP);
    y += HP_H + BAR_GAP;
    bar(BARS_X, y, FP_W, FP_H, fp, 0, FP_HI, FP_LO, FP_TP);
    refuseRing(BARS_X, y, FP_W, FP_H, fpRefused);
    y += FP_H + BAR_GAP;
    bar(BARS_X, y, ST_W, ST_H, stam, 0, ST_HI, ST_LO, ST_TP);
    if (windedTo > 0.001) {
        const wf: f32 = @floatFromInt(ST_W);
        const owed: i32 = @intFromFloat(wf * mathx.clampF(windedTo, 0, 1));
        const fill: i32 = @intFromFloat(wf * mathx.clampF(stam, 0, 1));
        if (owed > fill) rl.drawRectangle(BARS_X + fill, y, owed - fill, ST_H, mathx.withAlpha(WARN, 46));
        rl.drawRectangle(BARS_X + owed - 1, y - 1, 2, ST_H + 2, mathx.withAlpha(WARN_LT, 210));
    }
    refuseRing(BARS_X, y, ST_W, ST_H, stamRefused);
    const stackTop = statusBarsUp(rl.getScreenHeight() - STATUS_BOTTOM_MARGIN, psn);
    statusFlash(stackTop);
}

const BARS_H: i32 = HP_H + BAR_GAP + FP_H + BAR_GAP + ST_H;

const DIAL_SKY = rgba(74, 104, 148, 210);
const DIAL_SKY_NIGHT = rgba(28, 36, 60, 214);
const DIAL_GROUND = rgba(20, 17, 14, 214);
const SUN_COL = rgba(244, 206, 118, 255);
const MOON_COL = rgba(206, 216, 234, 255);

/// THE WORLD CLOCK, drawn as the thing it actually is: a horizon, and the key light travelling across it left to right. The hour is the ONLY input and every shape comes off `daynight`'s own arithmetic, so the dial cannot tell a different time than the sun the scene is lit by.
pub fn dayDial(hour: f32) void {
    const cx = MARGIN + DIAL_R;
    const cy = BAR_TOP + @divTrunc(BARS_H, 2);
    const r: f32 = @floatFromInt(DIAL_R);
    const fx: f32 = @floatFromInt(cx);
    const fy: f32 = @floatFromInt(cy);
    const day = daynight.isDay(hour);

    rl.drawCircle(cx, cy, r + 2, rgba(0, 0, 0, 60));
    rl.drawCircle(cx, cy, r, DIAL_GROUND);
    rl.beginScissorMode(cx - DIAL_R, cy - DIAL_R, DIAL_R * 2, DIAL_R);
    rl.drawCircle(cx, cy, r, if (day) DIAL_SKY else DIAL_SKY_NIGHT);
    rl.endScissorMode();
    if (day) {
        const k: u8 = @intFromFloat(90.0 * daynight.dayAmt(hour));
        rl.beginScissorMode(cx - DIAL_R, cy - DIAL_R, DIAL_R * 2, DIAL_R);
        rl.drawCircle(cx, cy, r, mathx.withAlpha(rgba(150, 190, 236, 255), k));
        rl.endScissorMode();
    }
    rl.drawLineEx(.{ .x = fx - r, .y = fy }, .{ .x = fx + r, .y = fy }, 1.6, mathx.withAlpha(RIM, 220));
    rl.drawCircleLines(cx, cy, r, FRAME);

    const a = std.math.pi * (1.0 - daynight.spanU(hour));
    const rr = r - 5.5;
    const mx = fx + mathx.cosf(a) * rr;
    const my = fy - mathx.sinf(a) * rr;
    const col = if (day) SUN_COL else MOON_COL;
    rl.drawCircleV(.{ .x = mx, .y = my }, 6.5, mathx.withAlpha(col, 70));
    rl.drawCircleV(.{ .x = mx, .y = my }, 3.6, col);
    if (!day) {
        rl.drawCircleV(.{ .x = mx + 2.2, .y = my - 1.4 }, 2.9, DIAL_SKY_NIGHT);
    }

    var buf: [8]u8 = undefined;
    const s = daynight.clockTextZ(hour, &buf);
    text(s, cx - @divTrunc(textW(s, TINY), 2), cy + DIAL_R + 3, TINY, mathx.withAlpha(uiart.GILT_DIM, 236));
}

fn fillThree(x: i32, y: i32, fw: i32, h: i32, frac: f32, hi: rl.Color, lo: rl.Color, tp: rl.Color, shade: i32, tipW: i32, tipA: u8) void {
    if (fw <= 0) return;
    rl.drawRectangle(x, y, fw, h - shade, hi);
    rl.drawRectangleGradientV(x, y + h - shade, fw, shade, hi, lo);
    rl.drawRectangle(x, y, fw, 1, tp);
    if (fw > tipW and frac < 0.999) rl.drawRectangle(x + fw - tipW, y, tipW, h, mathx.withAlpha(uiart.CATCH, tipA));
}

fn bar(x: i32, y: i32, w: i32, h: i32, frac: f32, chipFrac: f32, hi: rl.Color, lo: rl.Color, tp: rl.Color) void {
    rl.drawRectangle(x - 3, y - 3, w + 6, h + 6, rgba(0, 0, 0, 50));
    rl.drawRectangle(x - 2, y - 2, w + 4, h + 4, rgba(0, 0, 0, 165));
    rl.drawRectangle(x - 1, y - 1, w + 2, h + 2, FRAME);
    rl.drawRectangle(x - 1, y - 1, w + 2, 1, mathx.withAlpha(uiart.GILT, 130));
    rl.drawRectangle(x - 1, y + h, w + 2, 1, rgba(0, 0, 0, 140));
    rl.drawRectangle(x + w + 1, y - 2, 2, h + 4, uiart.IRON);
    rl.drawRectangle(x, y, w, h, TRACK);
    const wf: f32 = @floatFromInt(w);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    const cw: i32 = @intFromFloat(wf * mathx.clampF(chipFrac, 0, 1));
    if (cw > fw) rl.drawRectangle(x + fw, y, cw - fw, h, CHIP);
    fillThree(x, y, fw, h, frac, hi, lo, tp, @max(@divTrunc(h, 3), 1), 2, 64);
    const hf: f32 = @floatFromInt(h);
    uiart.finial(@floatFromInt(x - 2), @as(f32, @floatFromInt(y)) + hf * 0.5, hf * 0.36 + 2.0, uiart.GILT_DIM);
}

const FOE_W: i32 = 54;
const FOE_H: i32 = 5;
const FOE_LIFT: i32 = 16;
const FOE_TRACK = rgba(38, 12, 10, 230);
const STAGGER_RIM = rgba(232, 196, 90, 255);
const CHILL_STRIP = rgba(148, 202, 232, 235);
/// A STATUS ROW under a foe's health: 2 px tall on a 5 px bar, one clear pixel above each.
const STRIP_H: i32 = 2;
const STRIP_GAP: i32 = 1;
/// A BAR MAY NOT CLIMB OUT OF THE FRAME. Over the head is right at every distance you can see the whole creature
/// at, and wrong the moment you close on a TALL one: the ogre's crown is 4.4 m up. So the bar has a CEILING in screen space — far off it rides the head, walking in it stops climbing and hangs against the body.
const FOE_CEIL: f32 = 0.25; // …measured from the TOP, so 0.25 is three quarters up

/// One entry per `combat.Ail`, in the enum's own order, so the caller hands over the body's meters and this
/// file decides what is worth a row. A meter reading zero costs a compare and nothing else.
pub const Ails = [combat.NAIL]Status;

/// **A ROW PER LIVE METER, AND THE GLYPH IS ITS LABEL** (owner). Rows are laid in `Ail` order so the same
/// ailment is always at the same height on the same creature, and only the ones that are actually filling take
/// a row — ten at once would be 30 px of strip under a 5 px bar.
pub fn foeBar(sx: f32, sy: f32, frac: f32, staggered: bool, ails: Ails) void {
    const wf: f32 = @floatFromInt(FOE_W);
    const x: i32 = @intFromFloat(sx - wf * 0.5);
    const ceiling = @as(f32, @floatFromInt(rl.getScreenHeight())) * FOE_CEIL;
    const y: i32 = @intFromFloat(mathx.maxF(sy - @as(f32, @floatFromInt(FOE_LIFT)), ceiling));
    rl.drawRectangle(x - 2, y - 2, FOE_W + 4, FOE_H + 4, rgba(0, 0, 0, 90));
    rl.drawRectangle(x - 1, y - 1, FOE_W + 2, FOE_H + 2, rgba(0, 0, 0, 170));
    rl.drawRectangle(x, y, FOE_W, FOE_H, FOE_TRACK);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    // 5 px tall, so the shade band is 2 rather than the vitals bars' third and the tip is a single column.
    fillThree(x, y, fw, FOE_H, frac, HP_HI, HP_LO, mathx.withAlpha(HP_TP, 200), 2, 1, 120);
    // A tint on a red bar at 54 px is a hue nobody can name, so every status is its OWN row under the health.
    // **A RUNNING METER IS BRIGHT AND A FILLING ONE IS NOT** — that flip is the only difference a player has to
    // read, and it is the same flip on every row rather than a colour pair per ailment.
    var row: i32 = 0;
    for (ails, 0..) |s, i| {
        if (s.frac <= 0.001) continue;
        const a: combat.Ail = @enumFromInt(i);
        const sw: i32 = @intFromFloat(wf * mathx.clampF(s.frac, 0, 1));
        const yy = y + FOE_H + STRIP_GAP * (row + 1) + STRIP_H * row;
        const tint = ailTint(a);
        rl.drawRectangle(x, yy, sw, STRIP_H, if (s.on) tint else mathx.withAlpha(tint, 150));
        // The glyph rides the left end of its own row, off the bar, so the row is readable without a legend.
        ailGlyph(a, @floatFromInt(x - FOE_GLYPH), @as(f32, @floatFromInt(yy)) + @as(f32, STRIP_H) * 0.5, FOE_GLYPH_S, tint);
        row += 1;
    }
    if (staggered) rl.drawRectangleLines(x - 1, y - 1, FOE_W + 2, FOE_H + 2, STAGGER_RIM);
}
const FOE_GLYPH: i32 = 6;
const FOE_GLYPH_S: f32 = 7.0;
const BOSS_H: i32 = 13;
const BOSS_LIFT: i32 = 158;
/// **A BAR PER BOSS ON THE FIELD, EACH KEEPING ITS OWN CHIP** — the delayed white tail is a memory of THAT
/// bar's last hit, so one set of module scratch across two bosses had the second replaying the first one's
/// damage. Rail 0 is the lowest. **A RAIL IS A ROW OF `game.BOSS_RAILS` AND NOT A PLACE IN A QUEUE** — it is
/// the same rail whether or not the ones under it are up, because a bar that slid down when another boss died
/// would move mid-fight. Three, because the shipped map holds three bosses.
pub const BOSS_SLOTS: usize = 3;
/// **THE PITCH BETWEEN TWO BARS IS THE BAR PLUS ITS OWN NAME, NOT A ROUND NUMBER.** The name is engraved ABOVE
/// the rail (`y - lineH(SMALL) - 3`), so at a 20 px pitch on a 13 px bar the upper bar sat straight on top of
/// the lower one's name. Derived, so restyling either the bar or the caption cannot leave the two overlapping.
const BOSS_NAME_LIFT: i32 = 3;
const BOSS_GAP: i32 = BOSS_H + BOSS_NAME_LIFT + 8 + lineH(SMALL);
var bossChip: [BOSS_SLOTS]f32 = [_]f32{0} ** BOSS_SLOTS;
var bossHold: [BOSS_SLOTS]f32 = [_]f32{0} ** BOSS_SLOTS;
var bossLast: [BOSS_SLOTS]f32 = [_]f32{0} ** BOSS_SLOTS;

/// **THE CHIP TAIL IS A MEMORY OF ONE RUN, AND A BLACK SCREEN ENDS THE RUN.** Module scratch, so without this
/// the last blow of the fight you died in was still on the rail when the bar next opened.
pub fn dropBossBars() void {
    bossChip = [_]f32{0} ** BOSS_SLOTS;
    bossHold = [_]f32{0} ** BOSS_SLOTS;
    bossLast = [_]f32{0} ** BOSS_SLOTS;
}

pub fn bossBarAt(tier: usize, dt: f32, name: [:0]const u8, frac: f32, staggered: bool, k: f32) void {
    if (k <= 0.001) {
        bossChip[tier] = frac;
        bossLast[tier] = frac;
        return;
    }
    const w: i32 = @min(760, @divTrunc(rl.getScreenWidth() * 62, 100));
    const x = @divTrunc(rl.getScreenWidth() - w, 2);
    // Slot 0 sits where the single tier always sat; each one above it is a tier and a gap higher.
    const y = rl.getScreenHeight() - BOSS_LIFT - @as(i32, @intCast(tier)) * BOSS_GAP;
    if (frac > bossChip[tier]) {
        bossChip[tier] = frac;
        bossHold[tier] = 0;
    } else {
        if (frac < bossLast[tier] - 1e-4) bossHold[tier] = CHIP_HOLD;
        if (bossHold[tier] > 0) bossHold[tier] -= dt else bossChip[tier] = mathx.maxF(frac, bossChip[tier] - CHIP_RATE * dt);
    }
    bossLast[tier] = frac;
    const a = mathx.clampF(k, 0, 1);
    rl.drawRectangle(x - 3, y - 3, w + 6, BOSS_H + 6, rgba(0, 0, 0, au8(60, a)));
    rl.drawRectangle(x - 2, y - 2, w + 4, BOSS_H + 4, rgba(0, 0, 0, au8(165, a)));
    rl.drawRectangle(x - 1, y - 1, w + 2, BOSS_H + 2, mathx.withAlpha(RIM, au8(210, a)));
    rl.drawRectangle(x - 1, y - 1, w + 2, 1, mathx.withAlpha(uiart.GILT, au8(130, a)));
    rl.drawRectangle(x - 1, y + BOSS_H, w + 2, 1, rgba(0, 0, 0, au8(140, a)));
    rl.drawRectangle(x, y, w, BOSS_H, mathx.withAlpha(TRACK, au8(186, a)));
    const wf: f32 = @floatFromInt(w);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    const cw: i32 = @intFromFloat(wf * mathx.clampF(bossChip[tier], 0, 1));
    if (cw > fw) rl.drawRectangle(x + fw, y, cw - fw, BOSS_H, mathx.withAlpha(CHIP, au8(226, a)));
    if (fw > 0) {
        const shadeH = @max(@divTrunc(BOSS_H, 3), 1);
        rl.drawRectangle(x, y, fw, BOSS_H - shadeH, mathx.withAlpha(HP_HI, au8(255, a)));
        rl.drawRectangleGradientV(x, y + BOSS_H - shadeH, fw, shadeH, mathx.withAlpha(HP_HI, au8(255, a)), mathx.withAlpha(HP_LO, au8(255, a)));
        rl.drawRectangle(x, y, fw, 1, mathx.withAlpha(HP_TP, au8(255, a)));
        if (fw > 2 and frac < 0.999) rl.drawRectangle(x + fw - 2, y, 2, BOSS_H, mathx.withAlpha(uiart.CATCH, au8(64, a)));
    }
    const hf: f32 = @floatFromInt(BOSS_H);
    uiart.finial(@floatFromInt(x - 2), @as(f32, @floatFromInt(y)) + hf * 0.5, hf * 0.36 + 2.0, mathx.withAlpha(uiart.GILT_DIM, au8(255, a)));
    uiart.finial(@floatFromInt(x + w + 2), @as(f32, @floatFromInt(y)) + hf * 0.5, hf * 0.36 + 2.0, mathx.withAlpha(uiart.GILT_DIM, au8(255, a)));
    if (staggered) {
        rl.drawRectangleLines(x - 1, y - 1, w + 2, BOSS_H + 2, mathx.withAlpha(STAGGER_RIM, au8(255, a)));
        rl.drawRectangleLines(x - 2, y - 2, w + 4, BOSS_H + 4, mathx.withAlpha(STAGGER_RIM, au8(130, a)));
    }
    engraved(name, x, y - lineH(SMALL) - BOSS_NAME_LIFT, SMALL, rgba(230, 218, 190, au8(244, a)));
}

fn au8(base: u8, k: f32) u8 {
    return @intFromFloat(@as(f32, @floatFromInt(base)) * mathx.clampF(k, 0, 1));
}

const SOUL_W: i32 = 122;
const SOUL_H: i32 = 32;
const SOUL_FILL_A: u8 = 170;
const SOUL_TEXT = rgba(228, 216, 190, 255);

pub fn souls(n: u32) void {
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch return;
    const x = rl.getScreenWidth() - SOUL_W - MARGIN;
    const y = rl.getScreenHeight() - SOUL_H - BOTTOM;
    rl.drawRectangle(x - 2, y - 2, SOUL_W + 4, SOUL_H + 4, rgba(0, 0, 0, 128));
    uiart.plate(x, y, SOUL_W, SOUL_H, SOUL_FILL_A);
    rl.drawRectangleLines(x, y, SOUL_W, SOUL_H, mathx.withAlpha(RIM, 186));
    rl.drawRectangle(x + 1, y + 1, SOUL_W - 2, 1, mathx.withAlpha(uiart.GILT, 90));
    uiart.cornerJewels(x + 1, y + 1, SOUL_W - 2, SOUL_H - 2, 2.0, mathx.withAlpha(uiart.GILT_DIM, 200));
    uiart.diamond(@floatFromInt(x + 12), @floatFromInt(y + @divTrunc(SOUL_H, 2)), 2.8, mathx.withAlpha(uiart.GILT_DIM, 220));
    text(s, x + SOUL_W - textW(s, BODY) - 11, y + @divTrunc(SOUL_H - lineH(BODY), 2) + 1, BODY, SOUL_TEXT);
}

// **THE ONE THING THAT SAYS THE DISK WAS TOUCHED** (owner: a save spinner, bottom right — a tree that grows; a
// DEAD one). Not a spinner: the file is on disk before the first frame of this draws.
//
// **IT IS FORLORN AND IT DOES NOT BOUNCE** (owner's call, and the one place in this codebase where **A MASS IN
// MOTION OVERSHOOTS ITS REST** does NOT apply — do not put the overshoot back).
//
// **AND IT IS BUILT TO THE DEAD-GROWTH LAW** (`propwood.deadLimbInto`, at HUD scale in two dimensions): NOTHING
// DEAD IS STRAIGHT AND NOTHING ENDS IN A POINT. No crown and no leaf anywhere — the fork at the top is finer limbs.

pub const SAVE_GROW: f32 = 0.92;
pub const SAVE_HOLD: f32 = 0.50;
pub const SAVE_OUT: f32 = 0.62;
pub const SAVE_SHOW: f32 = SAVE_GROW + SAVE_HOLD + SAVE_OUT;

const SAVE_W: i32 = 46;
const SAVE_H: i32 = 58;
const SAVE_GAP: i32 = 10;
const SAVE_LIMBS: usize = 4;
const SAVE_BARK = rgba(58, 47, 38, 255);
const SAVE_BARK_LT = rgba(92, 76, 58, 255);
const SAVE_HEART = rgba(142, 126, 100, 255);

/// **NO OVERSHOOT** (see above — the owner's exemption from the house law). Slow off the mark, slow onto its rest, and it never goes past it.
fn saveEase(p: f32) f32 {
    return mathx.smoothstep(0, 1, p);
}

const v2 = rl.Vector2.init;

pub fn saveTree(left: f32) void {
    if (left <= 0) return;
    const t = SAVE_SHOW - left;
    const grow = saveEase(mathx.clampF(t / SAVE_GROW, 0, 1));
    const a = 1.0 - mathx.smoothstep(SAVE_GROW + SAVE_HOLD, SAVE_SHOW, t);
    if (a <= 0.004 or grow <= 0.001) return;

    const x = rl.getScreenWidth() - MARGIN - SAVE_W;
    const baseY = rl.getScreenHeight() - BOTTOM - SOUL_H - SAVE_GAP;
    const bx = uiart.fi(x + @divTrunc(SAVE_W, 2));
    const by = uiart.fi(baseY);
    const h = uiart.fi(SAVE_H);

    var rng = mathx.Rng.init(0x54EED);
    const lean: f32 = -0.19;

    rl.drawEllipse(x + @divTrunc(SAVE_W, 2), baseY, 10.0 * grow, 2.4 * grow, rgba(0, 0, 0, au8(88, a)));

    const boleH = h * 0.62 * grow;
    const topY = by - boleH;
    const topX = bx + boleH * lean;
    var seg: usize = 0;
    while (seg < 4) : (seg += 1) {
        const f0 = uiart.fi(@intCast(seg)) / 4.0;
        const f1 = uiart.fi(@intCast(seg + 1)) / 4.0;
        const wob = rng.range(-1.0, 1.0) * grow;
        rl.drawLineEx(
            v2(mathx.lerpF(bx, topX, f0), mathx.lerpF(by, topY, f0)),
            v2(mathx.lerpF(bx, topX, f1) + wob, mathx.lerpF(by, topY, f1)),
            mathx.lerpF(5.6, 2.4, f0) * grow,
            mathx.lerpColor(SAVE_BARK, SAVE_BARK_LT, f0 * 0.7),
        );
    }
    inline for (.{ -1.0, 1.0 }) |sx| {
        rl.drawLineEx(v2(bx + 4.4 * sx * grow, by), v2(bx, by - 5.0 * grow), 2.2 * grow, SAVE_BARK);
    }

    var i: usize = 0;
    while (i < SAVE_LIMBS) : (i += 1) {
        const fi_ = uiart.fi(@intCast(i));
        const thr = 0.26 + 0.15 * fi_;
        const bg = saveEase(mathx.clampF((grow - thr) / (1.0 - thr), 0, 1));
        if (bg <= 0.001) continue;
        const up = 0.34 + 0.21 * fi_;
        const sx: f32 = if (i % 2 == 0) 1.0 else -1.0;
        const root = v2(mathx.lerpF(bx, topX, up), mathx.lerpF(by, topY, up));
        const len = h * rng.range(0.19, 0.29) * bg * (1.0 - 0.22 * fi_);
        const wide = 3.0 - 0.45 * fi_;

        const elbow = v2(root.x + len * 0.44 * sx, root.y - len * 0.44);
        rl.drawLineEx(root, elbow, wide * bg, SAVE_BARK);
        const snap = v2(elbow.x + len * 0.58 * sx, elbow.y + len * 0.30);
        rl.drawLineEx(elbow, snap, wide * 0.68 * bg, mathx.lerpColor(SAVE_BARK, SAVE_BARK_LT, 0.45));
        rl.drawCircleV(snap, wide * 0.34 * bg, mathx.withAlpha(SAVE_HEART, au8(228, a)));

        const twigs: usize = if (i < 2) 2 else 1;
        var k: usize = 0;
        while (k < twigs) : (k += 1) {
            const at = 0.45 + 0.32 * uiart.fi(@intCast(k));
            const from = v2(mathx.lerpF(elbow.x, snap.x, at), mathx.lerpF(elbow.y, snap.y, at));
            const tl = len * rng.range(0.22, 0.36) * bg;
            const to = v2(from.x + tl * sx * rng.range(0.7, 1.1), from.y - tl * rng.range(0.1, 0.6));
            rl.drawLineEx(from, to, mathx.maxF(1.0, wide * 0.30 * bg), SAVE_BARK);
        }
    }

    const cg = saveEase(mathx.clampF((grow - 0.58) / 0.42, 0, 1));
    if (cg > 0.001) {
        inline for (.{ -1.0, 1.0 }, .{ 0.86, 0.62 }) |sx, share| {
            const len = h * 0.20 * cg * share;
            const el = v2(topX + len * 0.42 * sx, topY - len * 0.62);
            const snap = v2(el.x + len * 0.52 * sx, el.y - len * 0.10);
            rl.drawLineEx(v2(topX, topY), el, 2.1 * cg, SAVE_BARK);
            rl.drawLineEx(el, snap, 1.5 * cg, mathx.lerpColor(SAVE_BARK, SAVE_BARK_LT, 0.45));
            rl.drawCircleV(snap, 1.15 * cg, mathx.withAlpha(SAVE_HEART, au8(222, a)));
        }
    }
}

const PROMPT_LIFT: i32 = 76;

/// WHAT THE BUTTON IN REACH WOULD DO — the picture of the button, then the verb. The band is measured off BOTH, so a longer verb or a wider glyph moves the plate rather than spilling off it.
pub fn prompt(h: Hint) void {
    const gw = glyphW(h.glyph, GLYPH_R);
    const w = gw + GLYPH_GAP + textW(h.label, BODY);
    const x = @divTrunc(rl.getScreenWidth() - w, 2);
    const y = rl.getScreenHeight() - lineH(BODY) - BOTTOM - PROMPT_LIFT;
    const bh = lineH(BODY) + 12;
    const by = y - 6;
    const ear: i32 = 34;
    const ink = rgba(0, 0, 0, 150);
    const clear = rgba(0, 0, 0, 0);
    rl.drawRectangle(x - 14, by, w + 28, bh, ink);
    rl.drawRectangleGradientH(x - 14 - ear, by, ear, bh, clear, ink);
    rl.drawRectangleGradientH(x + w + 14, by, ear, bh, ink, clear);
    const gilt = mathx.withAlpha(uiart.GILT, 120);
    const gclear = mathx.withAlpha(uiart.GILT, 0);
    for ([_]i32{ by, by + bh - 1 }) |ly| {
        rl.drawRectangle(x - 14, ly, w + 28, 1, gilt);
        rl.drawRectangleGradientH(x - 14 - ear, ly, ear, 1, gclear, gilt);
        rl.drawRectangleGradientH(x + w + 14, ly, ear, 1, gilt, gclear);
    }
    drawGlyph(h.glyph, x + @divTrunc(gw, 2), by + @divTrunc(bh, 2), GLYPH_R);
    text(h.label, x + gw + GLYPH_GAP, y, BODY, rgba(226, 214, 186, 240));
}

const BANNER_TOP: i32 = 96;
const BANNER_ROWS: usize = 3;
const BANNER_WIDE: i32 = 620;

/// A LINE THE WORLD IS SAYING, not a thing you can answer — no frame, no plate, just words with a shadow under them. Wrapped with the real face, since a script's sentence is written to be read and not to fit.
pub fn banner(s: []const u8) void {
    var buf: [320]u8 = undefined;
    var rows: [BANNER_ROWS][:0]const u8 = undefined;
    const maxW = @min(BANNER_WIDE, rl.getScreenWidth() - MARGIN * 2);
    const lines = wrap(s, BODY, maxW, &buf, &rows);
    var y = BANNER_TOP;
    for (lines) |ln| {
        const x = @divTrunc(rl.getScreenWidth() - textW(ln, BODY), 2);
        engraved(ln, x, y, BODY, rgba(232, 222, 198, 244));
        y += lineH(BODY);
    }
}

const EQ_SCALE: i32 = 150;
fn eq(v: i32) i32 {
    return @divTrunc(v * EQ_SCALE, 100);
}
const SLOT_W: i32 = eq(44);
const SLOT_H: i32 = eq(60);
const SLOT_GAP: i32 = eq(8);
const PITCH_Y: i32 = eq(48);
const BOTTOM: i32 = 26;

pub const Held = itemart.Arm;

/// **A HAND'S CELL KNOWS WHICH WEAPON IS IN IT, NOT JUST WHICH ARM.** The glyph was the armament's, so a dirk, a club and a warbow all drew as the plain sword and bow down here while the character book — which asks `hero.heldGear` — drew the gear.
pub const Slot = union(enum) { empty, held: struct { arm: Held, gear: ?item.Kind = null }, sorcery: combat.Spell };

pub fn equipment(left_hand: Slot, right_hand: Slot, up: Slot, castable: bool, quick: ?item.Kind, charges: u8, ammo: ?Ammo) void {
    const stepX = SLOT_W + SLOT_GAP;
    const left = MARGIN;
    const bottom = rl.getScreenHeight() - BOTTOM;
    const midX = left + stepX;
    const midY = bottom - SLOT_H - PITCH_Y;
    slot(midX, midY - PITCH_Y, up, if (castable) 1 else 0);
    slot(left, midY, left_hand, 0);
    slot(midX + stepX, midY, right_hand, 0);
    quickSlot(midX, midY + PITCH_Y, quick, charges);
    if (ammo) |n| ammoBox(midX + stepX, midY + SLOT_H + AMMO_GAP, n);
}

fn quickSlot(x: i32, y: i32, k: ?item.Kind, n: u8) void {
    uiart.slot(x, y, SLOT_W, SLOT_H, k != null);
    const kind = k orelse return;
    const cx: f32 = @floatFromInt(x + @divTrunc(SLOT_W, 2));
    const cy: f32 = @floatFromInt(y + @divTrunc(SLOT_H, 2));
    itemart.drawHeld(kind, cx, cy, @floatFromInt(ICON), n > 0);
    var buf: [8]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch return;
    tally(s, x + SLOT_W, y + SLOT_H + 6, HINT, if (n > 0) TALLY_OK else TALLY_DRY);
}

const AMMO_H: i32 = eq(26);
const AMMO_GAP: i32 = eq(5);
const TALLY_DRY = rgba(150, 96, 88, 220);
const TALLY_OK = rgba(232, 224, 202, 255);

pub const Ammo = struct { n: u8, fire: bool = false };


/// A count in a slot's bottom-right corner. Laid off the CORNER, not off the text's own height: the glyphs have descenders, and measured that way every tally sat on its rim.
pub fn tally(s: [:0]const u8, rightX: i32, bottomY: i32, size: i32, col: rl.Color) void {
    const tw = textW(s, size);
    const h = lineH(size);
    const x = rightX - tw - 12;
    const y = bottomY - h - 6;
    uiart.tallyShelf(x - 5, y - 1, tw + 12, h + 3);
    text(s, x, y, size, col);
}

fn ammoBox(x: i32, y: i32, a: Ammo) void {
    const on = a.n > 0;
    uiart.socket(x, y, SLOT_W, AMMO_H, on);
    uiart.socketRim(x, y, SLOT_W, AMMO_H, on);
    const cy: f32 = @floatFromInt(y + @divTrunc(AMMO_H, 2));
    itemart.arrow(@floatFromInt(x + eq(13)), cy, @floatFromInt(ICON), on, a.fire);
    var buf: [8]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{a.n}) catch return;
    const col = if (!on) TALLY_DRY else if (a.fire) itemart.FIRE else TALLY_OK;
    text(s, x + SLOT_W - textW(s, HINT) - 6, y + @divTrunc(AMMO_H - lineH(HINT), 2), HINT, col);
}

fn slot(x: i32, y: i32, holds: Slot, charges: u8) void {
    uiart.slot(x, y, SLOT_W, SLOT_H, holds != .empty);
    const cx: f32 = @floatFromInt(x + @divTrunc(SLOT_W, 2));
    const cy: f32 = @floatFromInt(y + @divTrunc(SLOT_H, 2));
    const px: f32 = @floatFromInt(ICON);
    switch (holds) {
        .empty => {},
        .held => |h| itemart.heldArt(h.arm, h.gear, cx, cy, px),
        // The sorcery cell's picture greys out when the FP will not cover a cast, which is the ammo box's own rule. WHICH picture is `itemart`'s one answer, shared with the character book's socket.
        .sorcery => |sp| itemart.spellArt(sp, cx, cy, px, charges > 0),
    }
}

const ICON = SLOT_W;

pub fn reticle(k: f32) void {
    const a = mathx.clampF(k, 0, 1);
    if (a <= 0.02) return;
    const cx = @divTrunc(rl.getScreenWidth(), 2);
    const cy = @divTrunc(rl.getScreenHeight(), 2);
    const gap: i32 = 5;
    const len: i32 = @intFromFloat(3.0 + 7.0 * a);
    const col = rgba(236, 228, 206, mathx.u8f(210.0 * a));
    const dim = rgba(0, 0, 0, mathx.u8f(120.0 * a));
    for ([_][4]i32{
        .{ cx - gap - len, cy - 1, len, 2 },
        .{ cx + gap, cy - 1, len, 2 },
        .{ cx - 1, cy - gap - len, 2, len },
        .{ cx - 1, cy + gap, 2, len },
    }) |r| {
        rl.drawRectangle(r[0] - 1, r[1] - 1, r[2] + 2, r[3] + 2, dim);
        rl.drawRectangle(r[0], r[1], r[2], r[3], col);
    }
}

/// Break `s` to `maxW` pixels at `size`, writing NUL-terminated lines into `buf`. MEASURED WITH THE REAL FACE per candidate word, not a characters-per-line guess: Balthazar is proportional. A word wider than the whole column is taken anyway and overhangs.
pub fn wrap(s: []const u8, size: i32, maxW: i32, buf: []u8, lines: [][:0]const u8) [][:0]const u8 {
    return wrapBy(textW, s, size, maxW, buf, lines);
}

/// **ONE ROTATING SCRATCH FOR EVERY PANEL'S LABELS.** The book, the bonfire and the passive tree each kept their own copy — and a slice into slot N is only good for the next fifteen calls, which is a rule worth having in ONE place next to the drawing it feeds.
var scratch: [16][160]u8 = undefined;
var scratchAt: usize = 0;

pub fn fmt(comptime f: []const u8, args: anytype) [:0]const u8 {
    scratchAt = (scratchAt + 1) % scratch.len;
    return std.fmt.bufPrintZ(&scratch[scratchAt], f, args) catch "?";
}

const PROSE_LINES = 8;
const PROSE_BUF = 768;
var proseLines: [PROSE_LINES][:0]const u8 = undefined;
var proseBuf: [PROSE_BUF]u8 = undefined;

/// Draws one wrapped paragraph; returns the y past the last line.
pub fn prose(s: []const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color) i32 {
    var yy = y;
    for (proseWrap(s, w, size)) |line| {
        text(line, x, yy, size, col);
        yy += lineH(size);
    }
    return yy;
}

/// The same wrap MEASURED and not drawn, for a layout that has to reserve the room first.
pub fn proseH(s: []const u8, w: i32, size: i32) i32 {
    return @as(i32, @intCast(proseWrap(s, w, size).len)) * lineH(size);
}

pub fn proseWrap(s: []const u8, w: i32, size: i32) []const [:0]const u8 {
    return wrap(s, size, w, &proseBuf, &proseLines);
}

/// …and the same wrap measured in the MONO face, for the editor's own chrome. Its own entry point rather than a flag, because which font a string will be DRAWN in is not something a wrap may guess.
pub fn wrapMono(s: []const u8, size: i32, maxW: i32, buf: []u8, lines: [][:0]const u8) [][:0]const u8 {
    return wrapBy(monoW, s, size, maxW, buf, lines);
}

/// …measured by whatever is passed in. A test binary opens no window and so loads no font, which makes every string zero wide and every wrap one line: the algorithm is only checkable against a ruler the test brings itself.
fn wrapBy(comptime measure: fn ([:0]const u8, i32) i32, s: []const u8, size: i32, maxW: i32, buf: []u8, lines: [][:0]const u8) [][:0]const u8 {
    var n: usize = 0;
    var used: usize = 0;
    var len: usize = 0;
    var it = std.mem.tokenizeAny(u8, s, " \n\t");
    while (it.next()) |word| {
        if (n >= lines.len) break;
        const sep: usize = if (len > 0) 1 else 0;
        if (used + len + sep + word.len + 1 > buf.len) break;
        if (sep == 1) buf[used + len] = ' ';
        @memcpy(buf[used + len + sep ..][0..word.len], word);
        buf[used + len + sep + word.len] = 0;
        const cand: [:0]const u8 = buf[used .. used + len + sep + word.len :0];
        if (len == 0 or measure(cand, size) <= maxW) {
            len += sep + word.len;
            continue;
        }
        buf[used + len] = 0;
        lines[n] = buf[used .. used + len :0];
        n += 1;
        used += len + 1;
        len = 0;
        if (n >= lines.len) break;
        if (used + word.len + 1 > buf.len) break;
        @memcpy(buf[used..][0..word.len], word);
        len = word.len;
    }
    if (len > 0 and n < lines.len) {
        buf[used + len] = 0;
        lines[n] = buf[used .. used + len :0];
        n += 1;
    }
    return lines[0..n];
}

fn perChar(s: [:0]const u8, size: i32) i32 {
    _ = size;
    return @intCast(s.len);
}

test "wrap breaks on words and keeps every one of them" {
    var buf: [512]u8 = undefined;
    var rows: [8][:0]const u8 = undefined;
    const src = "A tuft of the red grass that grows where something bled. Worthless, and everywhere.";
    const out = wrapBy(perChar, src, BODY, 24, &buf, &rows);
    try std.testing.expect(out.len > 1);
    var kept: usize = 0;
    for (out) |line| {
        try std.testing.expect(line.len > 0);
        try std.testing.expect(line.len <= 24);
        kept += line.len;
    }
    try std.testing.expectEqual(src.len - (out.len - 1), kept);
}

test "wrap stops at the caller's line count rather than overrunning it" {
    var buf: [512]u8 = undefined;
    var rows: [2][:0]const u8 = undefined;
    const out = wrapBy(perChar, "one two three four five six seven eight nine ten", BODY, 9, &buf, &rows);
    try std.testing.expectEqual(@as(usize, 2), out.len);
}

test "a word wider than the whole column is taken rather than dropped" {
    var buf: [128]u8 = undefined;
    var rows: [4][:0]const u8 = undefined;
    const out = wrapBy(perChar, "a supercalifragilistic b", BODY, 4, &buf, &rows);
    try std.testing.expectEqual(@as(usize, 3), out.len);
    try std.testing.expectEqualStrings("supercalifragilistic", out[1]);
}


test "A STATUS SAYS ITS OWN NAME — except a stun, which says nothing" {
    inline for (.{ combat.Ail.poison, .burning, .chill, .bleed, .sleep, .confusion, .charm, .berserk, .stupefy }) |a| {
        try std.testing.expect(ailWord(a) != null);
    }
    try std.testing.expect(ailWord(.stun) == null);
}

test "THE WORD FADES IN AND THEN OUT, and a stun never starts one" {
    flashLeft = 0;
    ailWas = [_]bool{false} ** combat.NAIL;
    var ails: Ails = [_]Status{.{}} ** combat.NAIL;

    ails[@intFromEnum(combat.Ail.stun)] = .{ .frac = 1, .on = true };
    watchAils(1.0 / 60.0, ails);
    try std.testing.expectApproxEqAbs(@as(f32, 0), flashAmt(), 1e-6);

    ails[@intFromEnum(combat.Ail.poison)] = .{ .frac = 1, .on = true };
    watchAils(0, ails);
    try std.testing.expectApproxEqAbs(@as(f32, 0), flashAmt(), 1e-3);
    var peak: f32 = 0;
    var t: f32 = 0;
    const dt = 1.0 / 60.0;
    while (t < FLASH_IN) : (t += dt) {
        watchAils(dt, ails);
        peak = mathx.maxF(peak, flashAmt());
    }
    try std.testing.expect(peak > 0.9);
    while (t < FLASH_DUR + 0.1) : (t += dt) watchAils(dt, ails);
    try std.testing.expectApproxEqAbs(@as(f32, 0), flashAmt(), 1e-6);
    // …and it does not re-fire while the meter simply STAYS on. Only the edge speaks.
    watchAils(dt, ails);
    try std.testing.expectApproxEqAbs(@as(f32, 0), flashAmt(), 1e-6);
    flashLeft = 0;
}
