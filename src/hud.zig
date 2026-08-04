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
const STEEL_MID = rgba(178, 184, 192, 255); // a blade's BODY: polished steel in a black well reads light
const STEEL_DK = rgba(126, 132, 140, 255);
const BRASS = rgba(182, 146, 78, 255);
const GRIP = rgba(112, 82, 56, 255);
const BOARD_JOINT = rgba(78, 56, 38, 255); // the shield icon's plank seams — a shade under GRIP
const GRIP_LT = rgba(146, 110, 76, 255); // …and the lit lip below one, which is what makes a seam an EDGE
const WAX = rgba(126, 34, 30, 255); // the flask's seal over its stopper
const GLASS_LIT = rgba(238, 236, 230, 255);
const CORD = rgba(158, 142, 108, 255); // the tie round its neck, and the bow's own wrap

pub const Slot = enum { empty, sword, bow, shield, flask };

pub const FlaskTint = enum { crimson, cerulean };

/// `left`/`right` are what is IN HIS HANDS this frame, not what he owns — the cross is four slots and it `tint` picks which flask is drawn in the DOWN slot, `charges` how many are left — the cross is where ER shows both, and a charge count you have to open a menu for is a charge count you play without.
pub fn equipment(left_hand: Slot, right_hand: Slot, tint: FlaskTint, charges: u8, ammo: ?Ammo) void {
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
const AMMO_FIRE = rgba(255, 158, 62, 255);
const AMMO_FIRE_DIM = rgba(226, 108, 30, 150);

/// WHAT IS ON THE STRING, and how many are left of it.
pub const Ammo = struct { n: u8, fire: bool = false };

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

fn ammoBox(x: i32, y: i32, a: Ammo) void {
    const on = a.n > 0;
    socket(x, y, SLOT_W, AMMO_H, on);
    socketRim(x, y, SLOT_W, AMMO_H, on);
    const cy: f32 = @floatFromInt(y + @divTrunc(AMMO_H, 2));
    arrowIcon(@floatFromInt(x + eq(13)), cy, on, a.fire);
    var buf: [8]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{a.n}) catch return;
    const col = if (!on) AMMO_DRY else if (a.fire) AMMO_FIRE else rgba(232, 224, 202, 255);
    text(s, x + SLOT_W - textW(s, HINT) - 6, y + @divTrunc(AMMO_H - lineH(HINT), 2), HINT, col);
}

fn arrowIcon(cx: f32, cy: f32, on: bool, fire: bool) void {
    const s: f32 = @floatFromInt(ICON);
    const k = strokeK();
    const half = s * 0.16;
    const shaft = if (on) BOWWOOD else rgba(BOWWOOD.r, BOWWOOD.g, BOWWOOD.b, 120);
    const plainHead = if (on) STEEL else rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 140);
    const head = if (fire) (if (on) AMMO_FIRE else rgba(AMMO_FIRE.r, AMMO_FIRE.g, AMMO_FIRE.b, 140)) else plainHead;
    // THE PITCHED HEAD IS TONGUES STREAMING BACK OFF THE PILE, as the mesh is — a disc behind the head
    // swallowed it and read as a ball on a stick.
    if (fire) {
        const hot = if (on) AMMO_FIRE else rgba(AMMO_FIRE.r, AMMO_FIRE.g, AMMO_FIRE.b, 90);
        const dim = if (on) AMMO_FIRE_DIM else rgba(AMMO_FIRE_DIM.r, AMMO_FIRE_DIM.g, AMMO_FIRE_DIM.b, 70);
        const root = cx + half - 0.8 * k;
        for ([_]f32{ -1, 0, 1 }) |sy| {
            const reach = if (sy == 0) 5.6 * k else 4.0 * k;
            rl.drawTriangle(
                .{ .x = root - reach, .y = cy + sy * 2.5 * k },
                .{ .x = root, .y = cy - 1.5 * k },
                .{ .x = root, .y = cy + 1.5 * k },
                if (sy == 0) hot else dim,
            );
        }
    }
    rl.drawLineEx(.{ .x = cx - half, .y = cy }, .{ .x = cx + half, .y = cy }, 2.0 * k, shaft);
    rl.drawLineEx(.{ .x = cx - half, .y = cy - 0.7 * k }, .{ .x = cx + half * 0.7, .y = cy - 0.7 * k }, 0.7 * k, rgba(GRIP_LT.r, GRIP_LT.g, GRIP_LT.b, if (on) 160 else 70)); // the lit top of the shaft
    // THE PILE: a long bodkin, and a SOCKET behind it where it is bound to the shaft.
    rl.drawTriangle(
        .{ .x = cx + half + 3.0 * k, .y = cy },
        .{ .x = cx + half - 1.6 * k, .y = cy - 2.3 * k },
        .{ .x = cx + half - 1.6 * k, .y = cy + 2.3 * k },
        head,
    );
    rl.drawLineEx(.{ .x = cx + half - 2.2 * k, .y = cy }, .{ .x = cx + half - 1.0 * k, .y = cy }, 3.0 * k, rgba(head.r / 2, head.g / 2, head.b / 2, head.a));
    // Fletches splay BACKWARD, and the two are not the same length.
    for ([_]f32{ -1, 1 }) |sy| {
        rl.drawLineEx(
            .{ .x = cx - half + 3.4 * k, .y = cy },
            .{ .x = cx - half - 0.6 * k, .y = cy + sy * (2.4 + 0.5 * sy) * k },
            1.5 * k,
            shaft,
        );
    }
    // …and the NOCK: the notch the string sits in, which is what makes the tail an end and not a stub.
    rl.drawLineEx(.{ .x = cx - half - 1.0 * k, .y = cy - 1.5 * k }, .{ .x = cx - half - 1.0 * k, .y = cy + 1.5 * k }, 1.2 * k, rgba(CORD.r, CORD.g, CORD.b, if (on) 235 else 110));
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
// (the flask's own highlight is GLASS_LIT, up with the rest of the icon palette)
const CORK = rgba(150, 118, 74, 255);

fn flask(cx: f32, cy: f32, tint: FlaskTint, full: bool) void {
    const s: f32 = @floatFromInt(ICON);
    const k = strokeK();
    var rng = mathx.Rng.init(0xF1A5C);
    const lit = switch (tint) {
        .crimson => CRIMSON,
        .cerulean => CERULEAN,
    };
    const dk = switch (tint) {
        .crimson => CRIMSON_DK,
        .cerulean => CERULEAN_DK,
    };
    const fill = if (full) lit else rgba(dk.r, dk.g, dk.b, 150);
    const deep = if (full) rgba(dk.r, dk.g, dk.b, 255) else rgba(dk.r, dk.g, dk.b, 120);
    const body = s * 0.265; // half-width of the bulb — narrowed, so the silhouette is a FLASK not a ball
    const bodyY = cy + s * 0.13;
    // The whole flask leans: hand-blown glass does not stand plumb, and nor does the way it is carried.
    const lean = rng.range(-0.9, 0.9) * k;

    rl.drawCircleV(.{ .x = cx + 1.0 * k, .y = bodyY + 1.1 * k }, body, rgba(0, 0, 0, 120)); // off the plate
    // THE BULB, SHADED FROM THE DARK SIDE OUT: the deep tone is the whole ball and the lit fill is a
    // slightly smaller one set up and left inside it, so what shows of the deep is a crescent along the
    // bottom-right rim. THERE IS NO CLIPPING HERE, which is what killed the three attempts before it —
    // a concentric dark circle is a bubble, a sector cuts the flask in half, and a big offset circle
    // (the obvious way round) spills its far side across the HUD and the world behind it.
    rl.drawCircleV(.{ .x = cx, .y = bodyY }, body, deep);
    rl.drawCircleV(.{ .x = cx - body * 0.11, .y = bodyY - body * 0.13 }, body * 0.90, fill);
    // THE SHOULDERS as a taper up to the neck. A rounded BOX here (the first pass) pokes its corners out
    // past the bulb's arc and reads as a flange bolted to the glass; a shoulder is a cone.
    const neckHalf = s * 0.062;
    const shoulderY = bodyY - body * 0.42;
    quad(
        .{ .x = cx + lean * 0.5 - neckHalf, .y = cy + s * 0.015 },
        .{ .x = cx + lean * 0.5 + neckHalf, .y = cy + s * 0.015 },
        .{ .x = cx + body * 0.88, .y = shoulderY },
        .{ .x = cx - body * 0.88, .y = shoulderY },
        fill,
    );
    // THE NECK, taller than it was and leaning with the rest of it…
    rl.drawLineEx(
        .{ .x = cx + lean * 0.4, .y = cy + s * 0.02 },
        .{ .x = cx + lean, .y = cy - s * 0.31 },
        neckHalf * 2.0,
        fill,
    );
    // …and the COLLAR where it flares out to take the stopper.
    rl.drawLineEx(
        .{ .x = cx + lean - s * 0.070, .y = cy - s * 0.295 },
        .{ .x = cx + lean + s * 0.070, .y = cy - s * 0.295 },
        2.0 * k,
        deep,
    );
    // THE LIQUID LINE sits DOWN IN THE BULB and stops short of the left, because the specular runs there:
    // laid across the shoulder and full width, the two of them crossed and read as a label on the glass.
    if (full) {
        rl.drawLineEx(
            .{ .x = cx - body * 0.20, .y = bodyY - body * 0.60 },
            .{ .x = cx + body * 0.72, .y = bodyY - body * 0.68 },
            1.4 * k,
            rgba(255, 255, 255, 80),
        );
    }
    // THE SPECULAR: one long streak down the left shoulder of the bulb, and nothing on the neck (a second
    // highlight there made a cross with the liquid line).
    rl.drawLineEx(
        .{ .x = cx - body * 0.52, .y = bodyY - body * 0.62 },
        .{ .x = cx - body * 0.66, .y = bodyY + body * 0.28 },
        2.0 * k,
        rgba(GLASS_LIT.r, GLASS_LIT.g, GLASS_LIT.b, if (full) 200 else 90),
    );

    // THE STOPPER: cork, and a blob of WAX over it that ran down one side further than the other.
    const sx = cx + lean * 1.15;
    rl.drawRectangleV(.{ .x = sx - s * 0.062, .y = cy - s * 0.395 }, .{ .x = s * 0.124, .y = s * 0.105 }, CORK);
    rl.drawCircleV(.{ .x = sx, .y = cy - s * 0.335 }, s * 0.075, WAX);
    rl.drawCircleV(
        .{ .x = sx + rng.range(-0.6, 0.6) * s * 0.05, .y = cy - s * 0.30 },
        s * 0.048,
        WAX, // the run
    );
    rl.drawCircleV(.{ .x = sx - 1.2 * k, .y = cy - s * 0.355 }, 1.0 * k, rgba(255, 210, 190, 120)); // its gloss
    // AND A TIE round the neck, ends uneven.
    const ty = cy - s * 0.245;
    rl.drawLineEx(.{ .x = sx - s * 0.075, .y = ty }, .{ .x = sx + s * 0.075, .y = ty - 0.6 * k }, 1.4 * k, CORD);
    rl.drawLineEx(
        .{ .x = sx + s * 0.055, .y = ty },
        .{ .x = sx + s * 0.055 + rng.range(1.4, 3.0) * k, .y = ty + rng.range(1.6, 3.4) * k },
        1.0 * k,
        CORD,
    );
}

const ICON = SLOT_W;
/// THE SLOT WIDTH EVERY ICON'S STROKES WERE TUNED AT. It was written out at five call sites, each with a
/// comment pointing at the other four — which is four chances to carry the set to a new size unevenly.
const ICON_TUNED_AT: f32 = 34.0;
fn strokeK() f32 {
    return @as(f32, @floatFromInt(ICON)) / ICON_TUNED_AT;
}

// ── THE EQUIPMENT ICONS ───────────────────────────────────────────────────────────────────────────
// These are the four pictures a player looks at for the whole game, so they are drawn as OBJECTS rather
// than as glyphs: a blade has a taper, a fuller and an edge that catches the light; a shield has boards,
// a binding and rivets; a flask has glass, a liquid line and a wax seal. Two rules hold the set together:
//
// - **STROKES SCALE OFF `k`.** Everything was tuned at a 34 px slot and multiplies up, so the HUD stays
//   itself at any resolution.
// - **WABI-SABI, BUT DETERMINISTIC.** Nothing in the set is machined: unequal guard arms, planks of
//   different widths, a nicked edge, a stopper off plumb. Every one of those offsets comes out of a
//   FIXED-SEED `mathx.Rng` re-seeded on each call, so the icon is imperfect and *the same imperfection
//   every frame*. Drawing from a live stream would make the HUD crawl.

/// Two triangles making one quad, WOUND WHICHEVER WAY RAYLIB WILL ACTUALLY RASTERISE. It culls a
/// back-facing 2D triangle (see `arrowIcon`, which is the one that proved it), so a quad handed over the
/// wrong way round is silently not drawn — and that is exactly how the sword icon's blade body went
/// missing: the picture was its point triangle plus two hairlines, which is to say a dagger. Callers give
/// the four corners in order and stop caring.
fn quad(a: rl.Vector2, b: rl.Vector2, c: rl.Vector2, d: rl.Vector2, col: rl.Color) void {
    // Signed area of a→b→c in SCREEN space, where y runs down: raylib draws the NEGATIVE one.
    if ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) <= 0) {
        rl.drawTriangle(a, b, c, col);
        rl.drawTriangle(a, c, d, col);
    } else {
        rl.drawTriangle(a, d, c, col);
        rl.drawTriangle(a, c, b, col);
    }
}

/// A point `along` the axis from `from` to `to`, pushed `off` sideways across it.
fn onAxis(from: rl.Vector2, to: rl.Vector2, along: f32, off: f32) rl.Vector2 {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const len = @max(@sqrt(dx * dx + dy * dy), 1e-4);
    const nx = -dy / len;
    const ny = dx / len;
    return .{ .x = from.x + dx * along + nx * off, .y = from.y + dy * along + ny * off };
}

/// ELDEN RING'S OWN PATTERN, and the owner's call: MOSTLY HILT, AND THE BLADE FADES OUT. A whole sword
/// scaled to fit a 44×60 socket is a dagger — that is what it read as — because everything that says
/// LONG about a longsword is the part there is no room for. So the hilt is drawn big and jewelled down
/// in the frame and the steel runs off the top losing itself, which reads as a blade that continues.
fn sword(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = strokeK();
    var rng = mathx.Rng.init(0x5B1AD3);
    const d = s * 0.72; // …and the blade's end is the FRAME, which is what says it carries on past it
    const u = 0.70711; // the diagonal axis, pommel-ward…
    // The whole sword leans a degree or so off the true diagonal: nothing forged is square to a grid.
    const lean = rng.range(-0.035, 0.035);
    // NOT a tip: where the steel has faded to nothing. The blade has no point in this picture.
    const gone = rl.Vector2{ .x = cx - u * d * (1.0 + lean), .y = cy - u * d * (1.0 - lean) };
    // THE POMMEL HAS TO FIT ITS OWN SOCKET, and off the diagonal that is not free: at the shipped 150%
    // equipment scale the obvious 0.92 of the axis put its far side 3 px out over the rim. Held in off
    // the wheel's own radius, so it cannot spill again at whatever scale the HUD is next drawn at.
    const pomR = 2.7 * k;
    const pomOut = @min(u * d * 0.92, @as(f32, @floatFromInt(@divTrunc(ICON, 2))) - pomR - 1.5);
    const pom = rl.Vector2{ .x = cx + pomOut, .y = cy + pomOut };
    const guard = onAxis(gone, pom, 0.60, 0); // the hilt: the bottom 40%, drawn big and jewelled
    const shoulder = onAxis(gone, pom, 0.565, 0); // where the blade meets the guard

    // THE BLADE: a stack of segments losing alpha as it climbs, because raylib's 2D triangles are flat and
    // a gradient is the only thing that says "this goes on past the frame". Widest at the shoulder, and it
    // does NOT taper to a point — a taper plus a fade reads as a blade that broke.
    const wBase = 2.7 * k; // a LONGSWORD: any wider over this length and it reads as a cleaver
    const wFar = 2.1 * k;
    const SEGS = 18;
    const runTo = 0.565; // the blade's whole run, as a fraction of the frame's diagonal…
    const FADE_FROM = 0.28; // …SOLID for this much of it, then losing itself into the corner. Faded from
    // the GUARD outward instead — which is how the first pass went in — a longsword reads as a lit stub.
    for (0..SEGS) |i| {
        const t0 = @as(f32, @floatFromInt(i)) / SEGS; // 0 AT THE GUARD, 1 where the steel has gone
        const t1 = @as(f32, @floatFromInt(i + 1)) / SEGS;
        const w0 = mathx.lerpF(wBase, wFar, t0);
        const w1 = mathx.lerpF(wBase, wFar, t1);
        const col = mathx.withAlpha(STEEL_MID, mathx.u8f(255.0 * (1.0 - mathx.smoothstep(FADE_FROM, 1.0, (t0 + t1) * 0.5))));
        quad(
            onAxis(gone, pom, runTo * (1.0 - t1), w1),
            onAxis(gone, pom, runTo * (1.0 - t0), w0),
            onAxis(gone, pom, runTo * (1.0 - t0), -w0),
            onAxis(gone, pom, runTo * (1.0 - t1), -w1),
            col,
        );
    }
    // …the FULLER and the two edges, over the part of the steel that is still solid enough to show them.
    const solid = runTo * (1.0 - FADE_FROM); // the near end of the fade: no detail survives past it
    rl.drawLineEx(onAxis(gone, pom, solid + 0.01, 0), onAxis(shoulder, pom, -0.02, 0), 1.1 * k, rgba(64, 68, 74, 170));
    rl.drawLineEx(onAxis(gone, pom, solid, -wBase * 0.84), onAxis(shoulder, pom, 0, -wBase * 0.88), 1.1 * k, mathx.withAlpha(STEEL, 215));
    rl.drawLineEx(onAxis(gone, pom, solid, wBase * 0.84), onAxis(shoulder, pom, 0, wBase * 0.88), 0.9 * k, rgba(88, 92, 98, 180));
    // A NICK, low on the edge where the steel is still opaque — up in the fade it is invisible anyway.
    const nickAt = rng.range(0.33, 0.43);
    rl.drawTriangle(
        onAxis(gone, pom, nickAt, -wBase * 0.72),
        onAxis(gone, pom, nickAt + 0.022, -wBase * 0.26),
        onAxis(gone, pom, nickAt - 0.016, -wBase * 0.26),
        rgba(20, 18, 16, 190),
    );

    // THE GRIP: a leather core with unevenly spaced wrap turns over it — hairline, or they read as segments
    // of a rod rather than as cord over leather. It is the LONG grip of a weapon held in two hands.
    rl.drawLineEx(guard, pom, 3.2 * k, GRIP);
    var band: f32 = 0.14;
    while (band < 0.88) : (band += rng.range(0.16, 0.24)) {
        const c = onAxis(guard, pom, band, 0);
        rl.drawLineEx(
            .{ .x = c.x + u * 1.55 * k, .y = c.y - u * 1.55 * k },
            .{ .x = c.x - u * 1.55 * k, .y = c.y + u * 1.55 * k },
            0.7 * k,
            rgba(66, 48, 33, 230),
        );
    }

    // THE CROSSGUARD — two arms of different length, and WIDE now that it is the read: the hilt is what
    // this picture is of. The first pass ran it at 0.215·s and 2.9 px, which is a warhammer's head.
    const q = s * 0.17;
    for ([_]f32{ -1, 1 }) |side| {
        const armLen = q * rng.range(0.84, 1.08);
        const droop = -side * 0.9 * k; // both arms sweep the same way about the axis
        const outer = rl.Vector2{
            .x = guard.x + side * u * armLen + u * droop,
            .y = guard.y - side * u * armLen + u * droop,
        };
        rl.drawLineEx(guard, outer, 2.1 * k, BRASS);
        rl.drawCircleV(outer, 1.15 * k, uiart.GILT);
    }
    rl.drawCircleV(guard, 1.35 * k, uiart.GILT); // the block the arms leave from

    // THE POMMEL: a wheel with its highlight up and left, and a shadow under it.
    rl.drawCircleV(.{ .x = pom.x + 0.6 * k, .y = pom.y + 0.7 * k }, pomR, rgba(0, 0, 0, 150));
    rl.drawCircleV(pom, pomR, BRASS);
    rl.drawCircleV(.{ .x = pom.x - 0.8 * k, .y = pom.y - 0.9 * k }, 1.1 * k, uiart.GILT_BRIGHT);
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
const BOWWOOD_LT = rgba(140, 102, 66, 255); // the lit BACK of a limb — a bow has a front and a back
const BOWNOCK = rgba(196, 188, 168, 255); // the horn nock the string sits in
const BOWSTRING = rgba(214, 206, 184, 255);
fn bowIcon(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = strokeK();
    var rng = mathx.Rng.init(0xB0FF12);
    const d = s * 0.55;
    const u = 0.70711;
    // THE UPPER LIMB IS THE LONGER ONE. That is true of every real bow (the grip sits above centre so the
    // arrow can pass through it) and it is the cheapest honest asymmetry in the whole set.
    const upper = d * 1.06;
    const lower = d * 0.90;
    const tx = cx - u * upper;
    const ty = cy - u * upper;
    const bx = cx + u * lower;
    const by = cy + u * lower;
    const belly = s * 0.17; // how far the grip stands off the string line, across the axis
    const mx = cx - u * belly;
    const my = cy + u * belly;

    // Each limb in THREE segments, tapering out to the nock, with the recurve kicking back at the tip.
    for ([_][3]f32{ .{ tx, ty, 1 }, .{ bx, by, -1 } }) |limb| {
        const tip = rl.Vector2{ .x = limb[0], .y = limb[1] };
        const grip = rl.Vector2{ .x = mx, .y = my };
        const bend = rng.range(0.28, 0.40);
        const knee = onAxis(grip, tip, 0.52, -belly * bend);
        const outer = onAxis(grip, tip, 0.84, -belly * bend * 0.55);
        rl.drawLineEx(grip, knee, 3.5 * k, BOWWOOD);
        rl.drawLineEx(knee, outer, 2.7 * k, BOWWOOD);
        rl.drawLineEx(outer, tip, 2.0 * k, BOWWOOD); // the recurve, thinnest at the tip…
        // …a lit back along the bending part, so the limb has a front and a back…
        rl.drawLineEx(onAxis(grip, knee, 0.25, -1.1 * k), onAxis(knee, outer, 0.7, -0.9 * k), 0.9 * k, BOWWOOD_LT);
        // …and a HORN NOCK: a small knob the string sits in.
        rl.drawCircleV(tip, 1.7 * k, BOWNOCK);
        rl.drawCircleV(.{ .x = tip.x - 0.4 * k, .y = tip.y - 0.5 * k }, 0.7 * k, uiart.CATCH);
    }

    // THE GRIP: leather over the belly, with two wrap turns, unevenly placed.
    rl.drawLineEx(
        .{ .x = mx - u * s * 0.075, .y = my - u * s * 0.075 },
        .{ .x = mx + u * s * 0.085, .y = my + u * s * 0.085 },
        4.4 * k,
        GRIP,
    );
    for ([_]f32{ rng.range(0.22, 0.38), rng.range(0.62, 0.80) }) |f| {
        const p = onAxis(
            .{ .x = mx - u * s * 0.075, .y = my - u * s * 0.075 },
            .{ .x = mx + u * s * 0.085, .y = my + u * s * 0.085 },
            f,
            0,
        );
        rl.drawLineEx(
            .{ .x = p.x - u * 2.2 * k, .y = p.y + u * 2.2 * k },
            .{ .x = p.x + u * 2.2 * k, .y = p.y - u * 2.2 * k },
            1.0 * k,
            CORD,
        );
    }

    // THE STRING: nock to nock, and a SERVING at its centre — the bound patch the arrow nocks onto.
    rl.drawLineEx(.{ .x = tx, .y = ty }, .{ .x = bx, .y = by }, 1.2 * k, BOWSTRING);
    const serveA = onAxis(.{ .x = tx, .y = ty }, .{ .x = bx, .y = by }, 0.44, 0);
    const serveB = onAxis(.{ .x = tx, .y = ty }, .{ .x = bx, .y = by }, 0.58, 0);
    rl.drawLineEx(serveA, serveB, 2.0 * k, CORD);
}

fn shield(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = strokeK();
    var rng = mathx.Rng.init(0x5C1E1D);
    const c = rl.Vector2{ .x = cx, .y = cy };
    const r = s * 0.40; // ~80% of the slot's width, matching the sword's own fill
    const boards = r - 2.6 * k;

    // THE BINDING is a 17-GON, not a circle: this thing was hammered round a wooden disc by hand, and a
    // perfect circle is the one shape that says machine. 17 sides at a lazy rotation is round at a glance
    // and hand-cut when you look.
    rl.drawCircleV(.{ .x = cx + 0.8 * k, .y = cy + 1.0 * k }, r, rgba(0, 0, 0, 130)); // it sits off the plate
    rl.drawPoly(c, 17, r, rng.range(0, 20), STEEL_DK);
    rl.drawPoly(c, 17, boards, rng.range(0, 20), GRIP);

    // THE BOARDS: three planks of UNEQUAL width, so the joints are not a symmetric pair.
    const j1 = rng.range(-0.50, -0.30);
    const j2 = rng.range(0.24, 0.46);
    for ([_]f32{ j1, j2 }) |f| {
        const dy = boards * f;
        const half = @sqrt(@max(boards * boards - dy * dy, 1.0));
        rl.drawLineEx(.{ .x = cx - half, .y = cy + dy }, .{ .x = cx + half, .y = cy + dy }, 1.7 * k, BOARD_JOINT);
        // …and a lit lip under each joint, which is what makes them read as EDGES rather than as lines.
        rl.drawLineEx(
            .{ .x = cx - half * 0.94, .y = cy + dy + 1.2 * k },
            .{ .x = cx + half * 0.94, .y = cy + dy + 1.2 * k },
            0.8 * k,
            rgba(GRIP_LT.r, GRIP_LT.g, GRIP_LT.b, 150),
        );
    }
    // GRAIN — a few short strokes along the planks, nowhere near evenly spaced.
    var gi: u32 = 0;
    while (gi < 5) : (gi += 1) {
        const gy = boards * rng.range(-0.78, 0.78);
        const half = @sqrt(@max(boards * boards - gy * gy, 1.0)) * rng.range(0.35, 0.8);
        const x0 = cx + rng.range(-0.4, 0.4) * half;
        rl.drawLineEx(
            .{ .x = x0 - half * 0.5, .y = cy + gy },
            .{ .x = x0 + half * 0.5, .y = cy + gy },
            0.7 * k,
            rgba(BOARD_JOINT.r, BOARD_JOINT.g, BOARD_JOINT.b, 110),
        );
    }

    // RIVETS round the binding — FIVE, unevenly spaced, and one of them has been lost.
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        if (i == 3) continue; // the missing one
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) / 5.0) + rng.range(-0.22, 0.22);
        const rr = r - 1.4 * k;
        const px = cx + mathx.cosf(a) * rr;
        const py = cy + mathx.sinf(a) * rr;
        rl.drawCircleV(.{ .x = px, .y = py }, 1.35 * k, STEEL);
        rl.drawCircleV(.{ .x = px - 0.4 * k, .y = py - 0.5 * k }, 0.6 * k, uiart.CATCH);
    }

    // THE BOSS: a dome, off-centre because the hand behind it is, with a shadow crescent under it and a
    // catch of light up and left.
    const bx = cx + rng.range(-1.2, 1.2) * k;
    const by = cy + rng.range(-1.2, 1.2) * k;
    const br = s * 0.125;
    rl.drawCircleV(.{ .x = bx + 0.7 * k, .y = by + 0.9 * k }, br, rgba(0, 0, 0, 160));
    rl.drawCircleV(.{ .x = bx, .y = by }, br, STEEL_DK);
    rl.drawCircleV(.{ .x = bx - 0.6 * k, .y = by - 0.7 * k }, br - 2.0 * k, STEEL);
    rl.drawCircleV(.{ .x = bx - 1.5 * k, .y = by - 1.7 * k }, br * 0.30, uiart.CATCH);
}
