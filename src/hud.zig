const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const uiart = @import("uiart.zig");

const rgba = mathx.rgba;

var haveFont = false;
var font: rl.Font = undefined;
var haveBig = false;
var fontBig: rl.Font = undefined;

const FONT_PATH = "assets/Balthazar-Regular.ttf";
const ATLAS_PX = 96;
const ATLAS_BIG_PX = 160; // the cinematic caption atlas (YOU DIED draws near 90 px)

pub const TITLE: i32 = 34; // menu card headings (the HUD carries no title — see THE ELDEN RING HUD)
pub const BODY: i32 = 22; // primary readouts — the debug gait/speed line, menu rows
pub const SMALL: i32 = 20; // secondary readouts — the debug corner's rows
pub const HINT: i32 = 19; // the least important line on screen (the menu's control crib)

fn atlas(path: [:0]const u8, px: i32) ?rl.Font {
    var f = rl.loadFontEx(path, px, null) catch return null;
    if (f.glyphCount == 0) return null;
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

/// Metal-leaf engraving: the same string re-drawn through two scissored bands so
/// the grade rides the letterforms. Collapses below ~20 px — titles only.
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

// A REAL system monospace face
const MONO_CANDIDATES = [_][:0]const u8{
    "C:/Windows/Fonts/consola.ttf", // Consolas — the good one
    "C:/Windows/Fonts/lucon.ttf", // Lucida Console
    "C:/Windows/Fonts/cour.ttf", // Courier New
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
};
const MONO_ATLAS_PX = 40; // >= 2x MONO, so the editor's text always downscales

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

/// Right-aligned text ending `pad` px from the right screen edge — the debug corner's row idiom.
pub fn textRight(s: [:0]const u8, pad: i32, y: i32, size: i32, col: rl.Color) void {
    text(s, rl.getScreenWidth() - textW(s, size) - pad, y, size, col);
}

// Huge letter-spaced caption, CENTERED on (cx, cy) — the cinematic text path (YOU DIED).
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


pub const MARGIN: i32 = 30;
const BAR_TOP: i32 = 24;
const BAR_GAP: i32 = 6;
const HP_W: i32 = 268;
const HP_H: i32 = 15;
const FP_W: i32 = 182;
const FP_H: i32 = 11;
const ST_W: i32 = 232;
const ST_H: i32 = 11;

const TRACK = rgba(16, 13, 11, 186); // the empty channel behind every fill
/// The tarnished-metal rim, one tone at whatever alpha the surface wants — the bars' hairline and the
/// rune plate's edge were two names for the same three channels.
const RIM = rgba(116, 104, 84, 255);
const FRAME = mathx.withAlpha(RIM, 210);
// Each bar is THREE values: a flat body, a shaded bottom third, a lit hairline on top.
const HP_HI = rgba(158, 36, 28, 255);
const HP_LO = rgba(96, 20, 16, 255);
const HP_TP = rgba(204, 66, 52, 255);
const FP_HI = rgba(50, 102, 140, 255);
const FP_LO = rgba(24, 56, 84, 255);
const FP_TP = rgba(88, 148, 188, 255);
const ST_HI = rgba(112, 136, 58, 255);
const ST_LO = rgba(60, 78, 28, 255);
const ST_TP = rgba(154, 178, 88, 255);
const CHIP = rgba(180, 98, 58, 226); // the recent-damage trail behind the HP fill
const WARN = rgba(232, 96, 72, 255);
const WARN_LT = rgba(240, 150, 120, 255);

var chip: f32 = 1;
var chipHold: f32 = 0;
var chipLast: f32 = 1;
const CHIP_HOLD = 0.42; // seconds the trail hangs before it starts draining
const CHIP_RATE = 0.55;

pub fn vitals(dt: f32, hp: f32, fp: f32, stam: f32, stamRefused: f32, windedTo: f32) void {
    if (hp > chip) {
        chip = hp; // healing (and a respawn) snaps it — never strand a trail across the bar
        chipHold = 0;
    } else {
        if (hp < chipLast - 1e-4) chipHold = CHIP_HOLD; // a fresh wound re-arms the hang
        if (chipHold > 0) chipHold -= dt else chip = mathx.maxF(hp, chip - CHIP_RATE * dt);
    }
    chipLast = hp;
    var y = BAR_TOP;
    bar(MARGIN, y, HP_W, HP_H, hp, chip, HP_HI, HP_LO, HP_TP);
    y += HP_H + BAR_GAP;
    bar(MARGIN, y, FP_W, FP_H, fp, 0, FP_HI, FP_LO, FP_TP);
    y += FP_H + BAR_GAP;
    bar(MARGIN, y, ST_W, ST_H, stam, 0, ST_HI, ST_LO, ST_TP);
    if (windedTo > 0.001) {
        const wf: f32 = @floatFromInt(ST_W);
        const owed: i32 = @intFromFloat(wf * mathx.clampF(windedTo, 0, 1));
        const fill: i32 = @intFromFloat(wf * mathx.clampF(stam, 0, 1));
        if (owed > fill) rl.drawRectangle(MARGIN + fill, y, owed - fill, ST_H, mathx.withAlpha(WARN, 46));
        rl.drawRectangle(MARGIN + owed - 1, y - 1, 2, ST_H + 2, mathx.withAlpha(WARN_LT, 210)); // the threshold
    }
    // The refusal flag lights the stamina bar's own FRAME, over the finished bar and outside its fill — so an empty bar, which is exactly when this fires and has no fill to tint, still reads loudly.
    const k = mathx.clampF(stamRefused, 0, 1);
    if (k > 0.001) {
        const a: u8 = @intFromFloat(230 * k);
        rl.drawRectangleLines(MARGIN - 2, y - 2, ST_W + 4, ST_H + 4, mathx.withAlpha(WARN, a));
        rl.drawRectangleLines(MARGIN - 3, y - 3, ST_W + 6, ST_H + 6, mathx.withAlpha(WARN, a / 2));
    }
}

/// THE FILL ITSELF — three values (a flat body, a shaded bottom band, a lit hairline on top) plus the
/// catchlight on the leading edge while the bar is short of full. The ONE copy: the vitals bars and the
/// floating foe bars each grew their own, which is three constants and a `< 0.999` test kept in step by
/// hand. `shade` is how deep the bottom band runs; `tipW`/`tipA` size the leading edge.
fn fillThree(x: i32, y: i32, fw: i32, h: i32, frac: f32, hi: rl.Color, lo: rl.Color, tp: rl.Color, shade: i32, tipW: i32, tipA: u8) void {
    if (fw <= 0) return;
    rl.drawRectangle(x, y, fw, h - shade, hi); // a flat body…
    rl.drawRectangleGradientV(x, y + h - shade, fw, shade, hi, lo);
    rl.drawRectangle(x, y, fw, 1, tp);
    if (fw > tipW and frac < 0.999) rl.drawRectangle(x + fw - tipW, y, tipW, h, mathx.withAlpha(uiart.CATCH, tipA));
}

fn bar(x: i32, y: i32, w: i32, h: i32, frac: f32, chipFrac: f32, hi: rl.Color, lo: rl.Color, tp: rl.Color) void {
    rl.drawRectangle(x - 3, y - 3, w + 6, h + 6, rgba(0, 0, 0, 50)); // a soft seat off the sky…
    rl.drawRectangle(x - 2, y - 2, w + 4, h + 4, rgba(0, 0, 0, 165));
    rl.drawRectangle(x - 1, y - 1, w + 2, h + 2, FRAME);
    // Lit top rim, shadowed bottom — the channel reads carved, not printed.
    rl.drawRectangle(x - 1, y - 1, w + 2, 1, mathx.withAlpha(uiart.GILT, 130));
    rl.drawRectangle(x - 1, y + h, w + 2, 1, rgba(0, 0, 0, 140));
    rl.drawRectangle(x + w + 1, y - 2, 2, h + 4, uiart.IRON); // the far end post
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
const STAGGER_RIM = rgba(232, 196, 90, 255); // ER's gold crit-opening cue on a stance break

pub fn foeBar(sx: f32, sy: f32, frac: f32, staggered: bool) void {
    const wf: f32 = @floatFromInt(FOE_W);
    const x: i32 = @intFromFloat(sx - wf * 0.5);
    const y: i32 = @as(i32, @intFromFloat(sy)) - FOE_LIFT;
    rl.drawRectangle(x - 2, y - 2, FOE_W + 4, FOE_H + 4, rgba(0, 0, 0, 90)); // a soft seat
    rl.drawRectangle(x - 1, y - 1, FOE_W + 2, FOE_H + 2, rgba(0, 0, 0, 170)); // backing
    rl.drawRectangle(x, y, FOE_W, FOE_H, FOE_TRACK);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    // 5 px tall, so the shade band is 2 rather than the vitals bars' third and the tip is a single column.
    fillThree(x, y, fw, FOE_H, frac, HP_HI, HP_LO, mathx.withAlpha(HP_TP, 200), 2, 1, 120);
    if (staggered) rl.drawRectangleLines(x - 1, y - 1, FOE_W + 2, FOE_H + 2, STAGGER_RIM);
}

const RUNE_W: i32 = 122;
const RUNE_H: i32 = 32;
const RUNE_FILL_A: u8 = 170;
const RUNE_TEXT = rgba(228, 216, 190, 255);

pub fn runes(n: u32) void {
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch return;
    const x = rl.getScreenWidth() - RUNE_W - MARGIN;
    const y = rl.getScreenHeight() - RUNE_H - BOTTOM;
    rl.drawRectangle(x - 2, y - 2, RUNE_W + 4, RUNE_H + 4, rgba(0, 0, 0, 128)); // the hard black seat
    uiart.plate(x, y, RUNE_W, RUNE_H, RUNE_FILL_A);
    rl.drawRectangleLines(x, y, RUNE_W, RUNE_H, mathx.withAlpha(RIM, 186));
    rl.drawRectangle(x + 1, y + 1, RUNE_W - 2, 1, mathx.withAlpha(uiart.GILT, 90)); // lit top rim
    uiart.cornerJewels(x + 1, y + 1, RUNE_W - 2, RUNE_H - 2, 2.0, mathx.withAlpha(uiart.GILT_DIM, 200));
    uiart.diamond(@floatFromInt(x + 12), @floatFromInt(y + @divTrunc(RUNE_H, 2)), 2.8, mathx.withAlpha(uiart.GILT_DIM, 220));
    text(s, x + RUNE_W - textW(s, BODY) - 11, y + @divTrunc(RUNE_H - lineH(BODY), 2) + 1, BODY, RUNE_TEXT);
}

const PROMPT_LIFT: i32 = 76;

pub fn prompt(s: [:0]const u8) void {
    const w = textW(s, BODY);
    const x = @divTrunc(rl.getScreenWidth() - w, 2);
    const y = rl.getScreenHeight() - lineH(BODY) - BOTTOM - PROMPT_LIFT;
    const bh = lineH(BODY) + 12;
    const by = y - 6;
    const ear: i32 = 34; // the band and its gilt rules fade out, never end square
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
    text(s, x, y, BODY, rgba(226, 214, 186, 240));
}

const EQ_SCALE: i32 = 150; // percent
fn eq(v: i32) i32 {
    return @divTrunc(v * EQ_SCALE, 100);
}
const SLOT_W: i32 = eq(44);
const SLOT_H: i32 = eq(60);
const SLOT_GAP: i32 = eq(8); // between the LEFT/RIGHT arms and the centre column
const PITCH_Y: i32 = eq(48);
const BOTTOM: i32 = 26;

const WELL_ON: u8 = 148;
const WELL_OFF: u8 = 68;
const SLOT_ON = rgba(180, 168, 140, 240); // an occupied slot's brighter rim
const SLOT_OFF = rgba(124, 115, 98, 122);
const STEEL = rgba(232, 234, 238, 255);
const STEEL_DK = rgba(126, 132, 140, 255);
const BRASS = rgba(182, 146, 78, 255);
const GRIP = rgba(112, 82, 56, 255);
const BOARD_JOINT = rgba(78, 56, 38, 255); // the shield icon's plank seams — a shade under GRIP

pub const Slot = enum { empty, sword, bow, shield, flask };

pub const FlaskTint = enum { crimson, cerulean };

/// `left`/`right` are what is IN HIS HANDS this frame, not what he owns — the cross is four slots and it `tint` picks which flask is drawn in the DOWN slot, `charges` how many are left — the cross is where ER shows both, and a charge count you have to open a menu for is a charge count you play without.
pub fn equipment(left_hand: Slot, right_hand: Slot, tint: FlaskTint, charges: u8, ammo: ?u8) void {
    // Three columns wide, corners left out.
    const stepX = SLOT_W + SLOT_GAP;
    const left = MARGIN;
    const bottom = rl.getScreenHeight() - BOTTOM;
    const midX = left + stepX; // the centre cell of the three
    const midY = bottom - SLOT_H - PITCH_Y;
    slot(midX, midY - PITCH_Y, .empty, .crimson, 0); // UP — sorcery/incantation
    slot(left, midY, left_hand, .crimson, 0); // LEFT — left hand: the shield, or nothing behind a bow
    slot(midX + stepX, midY, right_hand, .crimson, 0); // RIGHT — right hand: the sword or the bow
    slot(midX, midY + PITCH_Y, .flask, tint, charges); // DOWN — the quick item
    if (ammo) |n| ammoBox(midX + stepX, midY + SLOT_H + AMMO_GAP, n);
}

const AMMO_H: i32 = eq(26);
const AMMO_GAP: i32 = eq(5);
const AMMO_DRY = rgba(150, 96, 88, 220);

/// A HARD SEAT, A SUNK WELL AND A RIM — the socket every cross cell and the ammo box sit in, written
/// once because there were two copies differing only in which height they passed.
fn socket(x: i32, y: i32, w: i32, h: i32, on: bool) void {
    rl.drawRectangle(x - 1, y - 1, w + 2, h + 2, rgba(0, 0, 0, if (on) 150 else 80));
    uiart.well(x, y, w, h, if (on) WELL_ON else WELL_OFF);
}

fn socketRim(x: i32, y: i32, w: i32, h: i32, on: bool) void {
    const r = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(w),
        .height = @floatFromInt(h),
    };
    rl.drawRectangleLinesEx(r, 1, if (on) SLOT_ON else SLOT_OFF);
}

fn ammoBox(x: i32, y: i32, n: u8) void {
    const on = n > 0;
    socket(x, y, SLOT_W, AMMO_H, on);
    socketRim(x, y, SLOT_W, AMMO_H, on);
    const cy: f32 = @floatFromInt(y + @divTrunc(AMMO_H, 2));
    arrowIcon(@floatFromInt(x + eq(13)), cy, on);
    var buf: [8]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch return;
    text(s, x + SLOT_W - textW(s, HINT) - 6, y + @divTrunc(AMMO_H - lineH(HINT), 2), HINT, if (on) rgba(232, 224, 202, 255) else AMMO_DRY);
}

fn arrowIcon(cx: f32, cy: f32, on: bool) void {
    const s: f32 = @floatFromInt(ICON);
    const k = s / 34.0; // the icon set's shared stroke scale (see `sword`)
    const half = s * 0.16;
    const shaft = if (on) BOWWOOD else rgba(BOWWOOD.r, BOWWOOD.g, BOWWOOD.b, 120);
    const head = if (on) STEEL else rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 140);
    rl.drawLineEx(.{ .x = cx - half, .y = cy }, .{ .x = cx + half, .y = cy }, 2.0 * k, shaft);
    rl.drawTriangle(
        .{ .x = cx + half + 2.4 * k, .y = cy },
        .{ .x = cx + half - 1.2 * k, .y = cy - 2.2 * k },
        .{ .x = cx + half - 1.2 * k, .y = cy + 2.2 * k },
        head,
    );
    // Fletches splay BACKWARD.
    for ([_]f32{ -1, 1 }) |sy| {
        rl.drawLineEx(
            .{ .x = cx - half + 3.2 * k, .y = cy },
            .{ .x = cx - half - 0.6 * k, .y = cy + sy * 2.6 * k },
            1.4 * k,
            shaft,
        );
    }
}

fn slot(x: i32, y: i32, holds: Slot, tint: FlaskTint, charges: u8) void {
    const on = holds != .empty;
    socket(x, y, SLOT_W, SLOT_H, on);
    if (on) uiart.candle(x + @divTrunc(SLOT_W, 2), y + @divTrunc(SLOT_H, 2), @as(f32, @floatFromInt(SLOT_W)) * 0.55, 16);
    socketRim(x, y, SLOT_W, SLOT_H, on);
    if (on) uiart.cornerJewels(x, y, SLOT_W, SLOT_H, 2.4, mathx.withAlpha(uiart.GILT_DIM, 220));
    const cx: f32 = @floatFromInt(x + @divTrunc(SLOT_W, 2));
    const cy: f32 = @floatFromInt(y + @divTrunc(SLOT_H, 2));
    switch (holds) {
        .empty => {},
        .sword => sword(cx, cy),
        .bow => bowIcon(cx, cy),
        .shield => shield(cx, cy),
        .flask => {
            flask(cx, cy, tint, charges > 0);
            var buf: [8]u8 = undefined;
            const s = std.fmt.bufPrintZ(&buf, "{d}", .{charges}) catch return;
            const col = if (charges > 0) rgba(232, 224, 202, 255) else rgba(150, 96, 88, 220);
            text(s, x + SLOT_W - textW(s, HINT) - 5, y + SLOT_H - lineH(HINT) + 1, HINT, col);
        },
    }
}

const CRIMSON = rgba(196, 46, 40, 255); // Flask of Crimson Tears
const CRIMSON_DK = rgba(104, 24, 22, 255);
const CERULEAN = rgba(64, 128, 200, 255);
const CERULEAN_DK = rgba(28, 62, 118, 255);
const GLASS = rgba(206, 202, 192, 255);
const CORK = rgba(150, 118, 74, 255);

fn flask(cx: f32, cy: f32, tint: FlaskTint, full: bool) void {
    const s: f32 = @floatFromInt(ICON);
    const k = s / 34.0; // the sword icon's stroke scale — the set has to match
    const lit = switch (tint) {
        .crimson => CRIMSON,
        .cerulean => CERULEAN,
    };
    const dk = switch (tint) {
        .crimson => CRIMSON_DK,
        .cerulean => CERULEAN_DK,
    };
    const fill = if (full) lit else rgba(dk.r, dk.g, dk.b, 150);
    const body = s * 0.30; // half-width of the bulb
    const bodyY = cy + s * 0.10;
    rl.drawCircleV(.{ .x = cx, .y = bodyY }, body, fill);
    rl.drawRectangleRounded(.{
        .x = cx - body * 0.86,
        .y = bodyY - body * 0.95,
        .width = body * 1.72,
        .height = body * 1.30,
    }, 0.45, 6, fill);
    rl.drawRectangleV(
        .{ .x = cx - s * 0.085, .y = cy - s * 0.30 },
        .{ .x = s * 0.17, .y = s * 0.30 },
        fill,
    );
    rl.drawLineEx(
        .{ .x = cx - body * 0.52, .y = bodyY - body * 0.55 },
        .{ .x = cx - body * 0.62, .y = bodyY + body * 0.35 },
        1.8 * k,
        rgba(GLASS.r, GLASS.g, GLASS.b, if (full) 190 else 90),
    );
    rl.drawRectangleV(
        .{ .x = cx - s * 0.065, .y = cy - s * 0.40 },
        .{ .x = s * 0.13, .y = s * 0.11 },
        CORK,
    );
}

const ICON = SLOT_W;
fn sword(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = s / 34.0; // stroke widths were tuned at a 34 px slot; carry them up with the size
    const d = s * 0.55; // half the icon's diagonal — ~78% of the slot's width, ER's own fill
    const u = 0.70711; // the diagonal axis, pommel-ward…
    const tip = rl.Vector2{ .x = cx - u * d, .y = cy - u * d };
    const gx = cx + u * d * 0.34;
    const gy = cy + u * d * 0.34;
    const guard = rl.Vector2{ .x = gx, .y = gy };
    const pom = rl.Vector2{ .x = cx + u * d * 0.92, .y = cy + u * d * 0.92 };
    const q = s * 0.22; // crossguard half-width, ACROSS the axis — the BLADE has to dominate
    rl.drawLineEx(tip, guard, 3.6 * k, STEEL_DK); // blade body…
    rl.drawLineEx(tip, guard, 1.4 * k, STEEL);
    rl.drawLineEx(guard, pom, 3.0 * k, GRIP); // grip UNDER the guard, so the cross reads on top
    rl.drawLineEx(.{ .x = gx + u * q, .y = gy - u * q }, .{ .x = gx - u * q, .y = gy + u * q }, 3.2 * k, BRASS);
    rl.drawCircleV(pom, 2.6 * k, BRASS);
}

/// Dead screen centre, because that is literally where an aimed shot goes.
pub fn reticle(k: f32) void {
    const a = mathx.clampF(k, 0, 1);
    if (a <= 0.02) return;
    const cx = @divTrunc(rl.getScreenWidth(), 2);
    const cy = @divTrunc(rl.getScreenHeight(), 2);
    const gap: i32 = 5;
    const len: i32 = @intFromFloat(3.0 + 7.0 * a);
    const col = rgba(236, 228, 206, mathx.u8f(210.0 * a));
    const dim = rgba(0, 0, 0, mathx.u8f(120.0 * a)); // a seat, so it reads over pale ground too
    for ([_][4]i32{
        .{ cx - gap - len, cy - 1, len, 2 }, // left
        .{ cx + gap, cy - 1, len, 2 }, // right
        .{ cx - 1, cy - gap - len, 2, len }, // up
        .{ cx - 1, cy + gap, 2, len }, // down
    }) |r| {
        rl.drawRectangle(r[0] - 1, r[1] - 1, r[2] + 2, r[3] + 2, dim);
        rl.drawRectangle(r[0], r[1], r[2], r[3], col);
    }
}

const BOWWOOD = rgba(96, 68, 44, 255);
const BOWSTRING = rgba(214, 206, 184, 255);
fn bowIcon(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = s / 34.0; // the icon set's shared stroke scale (see `sword`)
    const d = s * 0.55;
    const u = 0.70711;
    const tx = cx - u * d;
    const ty = cy - u * d;
    const bx = cx + u * d;
    const by = cy + u * d;
    const belly = s * 0.17; // how far the grip stands off the string line, across the axis
    const mx = cx - u * belly;
    const my = cy + u * belly;
    for ([_][2]f32{ .{ tx, ty }, .{ bx, by } }) |tip| {
        const midx = (tip[0] + mx) * 0.5 - u * belly * 0.34;
        const midy = (tip[1] + my) * 0.5 + u * belly * 0.34;
        rl.drawLineEx(.{ .x = tip[0], .y = tip[1] }, .{ .x = midx, .y = midy }, 2.9 * k, BOWWOOD);
        rl.drawLineEx(.{ .x = midx, .y = midy }, .{ .x = mx, .y = my }, 3.4 * k, BOWWOOD);
    }
    rl.drawLineEx(
        .{ .x = mx - u * s * 0.07, .y = my - u * s * 0.07 },
        .{ .x = mx + u * s * 0.07, .y = my + u * s * 0.07 },
        4.2 * k,
        GRIP,
    );
    rl.drawLineEx(.{ .x = tx, .y = ty }, .{ .x = bx, .y = by }, 1.3 * k, BOWSTRING);
}

fn shield(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = s / 34.0; // the icon set's shared stroke scale (see `sword`)
    const c = rl.Vector2{ .x = cx, .y = cy };
    const r = s * 0.40; // ~80% of the slot's width, matching the sword's own fill
    const boards = r - 2.4 * k;
    rl.drawCircleV(c, r, STEEL_DK); // the iron binding…
    rl.drawCircleV(c, boards, GRIP);
    for ([_]f32{ -0.42, 0.42 }) |f| {
        const dy = boards * f;
        const half = @sqrt(@max(boards * boards - dy * dy, 1.0));
        rl.drawLineEx(
            .{ .x = cx - half, .y = cy + dy },
            .{ .x = cx + half, .y = cy + dy },
            1.6 * k,
            BOARD_JOINT,
        );
    }
    rl.drawCircleV(c, s * 0.115, STEEL_DK);
    rl.drawCircleV(.{ .x = cx - 0.5 * k, .y = cy - 0.6 * k }, s * 0.115 - 2.4 * k, STEEL);
}
