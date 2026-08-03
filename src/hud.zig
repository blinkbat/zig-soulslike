const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

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

// A REAL system monospace face — Consolas, then the other Windows-stock fixed-pitch faces, then whatever a non-Windows box has.
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
        // `atlas` also rejects a face that "loaded" as raylib's 0-glyph default — take one of those and every string in the editor measures as nothing.
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

// ALPHAS ARE DELIBERATELY SHORT OF OPAQUE (owner's call — the bars and the rune plate read as solid furniture sat on top of the game).
const TRACK = rgba(16, 13, 11, 186); // the empty channel behind every fill
const FRAME = rgba(116, 104, 84, 210); // the tarnished-metal rim, a hairline outside the track
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
// THE BAR'S ONE WARNING RED, named like every other colour in this file: the WINDED mark and the REFUSED ring are the same cue said twice (this bar owes you something), and they were three inline literals — a drift waiting for the first retune.
const WARN = rgba(232, 96, 72, 255);
const WARN_LT = rgba(240, 150, 120, 255); // …the threshold tick itself, a stop brighter

// THE CHIP BAR, the most ER-identifying thing on screen: the red fill snaps to the new HP the instant you are hit and a paler bar hangs at the OLD value for a beat before draining to meet it, so you read what the blow cost after it has landed.
var chip: f32 = 1;
var chipHold: f32 = 0;
var chipLast: f32 = 1;
const CHIP_HOLD = 0.42; // seconds the trail hangs before it starts draining
const CHIP_RATE = 0.55; // …then drains this fraction of the bar per second

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
    // WINDED: the bar carries the mark it has to refill PAST before the sprint comes back, and the track behind it reads as owed rather than as spare.
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

fn bar(x: i32, y: i32, w: i32, h: i32, frac: f32, chipFrac: f32, hi: rl.Color, lo: rl.Color, tp: rl.Color) void {
    // The rim goes OUTSIDE the fill, between the black edge and the track: over the fill it muddies the lit hairline below and the bar loses its top edge.
    rl.drawRectangle(x - 3, y - 3, w + 6, h + 6, rgba(0, 0, 0, 50)); // a soft seat off the sky…
    rl.drawRectangle(x - 2, y - 2, w + 4, h + 4, rgba(0, 0, 0, 165)); // …the hard black edge…
    rl.drawRectangle(x - 1, y - 1, w + 2, h + 2, FRAME); // …and one warm metal hairline
    rl.drawRectangle(x, y, w, h, TRACK);
    const wf: f32 = @floatFromInt(w);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    const cw: i32 = @intFromFloat(wf * mathx.clampF(chipFrac, 0, 1));
    if (cw > fw) rl.drawRectangle(x + fw, y, cw - fw, h, CHIP);
    if (fw > 0) {
        const third = @max(@divTrunc(h, 3), 1);
        rl.drawRectangle(x, y, fw, h - third, hi); // a flat body…
        rl.drawRectangleGradientV(x, y + h - third, fw, third, hi, lo); // …shaded into its floor
        rl.drawRectangle(x, y, fw, 1, tp); // …under one lit hairline
        // The leading edge catches the light — what makes a draining bar read as MOVING rather than as a rectangle that got shorter.
        if (fw > 2 and frac < 0.999) rl.drawRectangle(x + fw - 2, y, 2, h, rgba(255, 244, 226, 64));
    }
}

const FOE_W: i32 = 54;
const FOE_H: i32 = 5;
const FOE_LIFT: i32 = 16; // …how far above the projected crown it rides
const FOE_TRACK = rgba(38, 12, 10, 230);
const STAGGER_RIM = rgba(232, 196, 90, 255); // ER's gold crit-opening cue on a stance break

pub fn foeBar(sx: f32, sy: f32, frac: f32, staggered: bool) void {
    const wf: f32 = @floatFromInt(FOE_W);
    const x: i32 = @intFromFloat(sx - wf * 0.5);
    const y: i32 = @as(i32, @intFromFloat(sy)) - FOE_LIFT;
    rl.drawRectangle(x - 1, y - 1, FOE_W + 2, FOE_H + 2, rgba(0, 0, 0, 170)); // backing
    rl.drawRectangle(x, y, FOE_W, FOE_H, FOE_TRACK);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    if (fw > 0) rl.drawRectangle(x, y, fw, FOE_H, HP_HI);
    if (staggered) rl.drawRectangleLines(x - 1, y - 1, FOE_W + 2, FOE_H + 2, STAGGER_RIM);
}

const RUNE_W: i32 = 122;
const RUNE_H: i32 = 32;
const RUNE_FILL = rgba(14, 12, 10, 170); // …pulled back with the bars (see TRACK) — owner's call
const RUNE_EDGE = rgba(116, 104, 84, 186); // …the vitals bars' FRAME colour, deliberately
const RUNE_TEXT = rgba(228, 216, 190, 255);

pub fn runes(n: u32) void {
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch return;
    const x = rl.getScreenWidth() - RUNE_W - MARGIN;
    const y = rl.getScreenHeight() - RUNE_H - BOTTOM;
    rl.drawRectangle(x - 2, y - 2, RUNE_W + 4, RUNE_H + 4, rgba(0, 0, 0, 128)); // the hard black seat
    rl.drawRectangle(x, y, RUNE_W, RUNE_H, RUNE_FILL);
    rl.drawRectangleLines(x, y, RUNE_W, RUNE_H, RUNE_EDGE);
    text(s, x + RUNE_W - textW(s, BODY) - 11, y + @divTrunc(RUNE_H - lineH(BODY), 2) + 1, BODY, RUNE_TEXT);
}

const PROMPT_LIFT: i32 = 76;

pub fn prompt(s: [:0]const u8) void {
    const w = textW(s, BODY);
    const x = @divTrunc(rl.getScreenWidth() - w, 2);
    const y = rl.getScreenHeight() - lineH(BODY) - BOTTOM - PROMPT_LIFT;
    rl.drawRectangle(x - 14, y - 6, w + 28, lineH(BODY) + 12, rgba(0, 0, 0, 132));
    text(s, x, y, BODY, rgba(226, 214, 186, 240));
}

// ER's bottom-left is a D-PAD CROSS of exactly four slots: sorcery UP, left hand LEFT, right hand RIGHT, quick item DOWN.
const EQ_SCALE: i32 = 150; // percent
fn eq(v: i32) i32 {
    return @divTrunc(v * EQ_SCALE, 100);
}
const SLOT_W: i32 = eq(44);
const SLOT_H: i32 = eq(60);
const SLOT_GAP: i32 = eq(8); // between the LEFT/RIGHT arms and the centre column
// The vertical pitch is DELIBERATELY LESS THAN A SLOT IS TALL, and it is not derived from SLOT_GAP.
const PITCH_Y: i32 = eq(48);
// The seat off the bottom does NOT scale — it is a screen margin like MARGIN, and doubling it would just push the cross inward.
const BOTTOM: i32 = 26;

const WELL_ON: u8 = 148;
const WELL_OFF: u8 = 68;
const SLOT_ON = rgba(180, 168, 140, 240); // an occupied slot's brighter rim
const SLOT_OFF = rgba(124, 115, 98, 122);
const STEEL = rgba(232, 234, 238, 255);
const STEEL_DK = rgba(126, 132, 140, 255);
const BRASS = rgba(182, 146, 78, 255);
const GRIP = rgba(112, 82, 56, 255); // …light enough to READ against the well, not true leather
const BOARD_JOINT = rgba(78, 56, 38, 255); // the shield icon's plank seams — a shade under GRIP

pub const Slot = enum { empty, sword, bow, shield, flask };

pub const FlaskTint = enum { crimson, cerulean };

/// `left`/`right` are what is IN HIS HANDS this frame, not what he owns — the cross is four slots and it
/// `tint` picks which flask is drawn in the DOWN slot, `charges` how many are left — the cross is where ER shows both, and a charge count you have to open a menu for is a charge count you play without.
pub fn equipment(left_hand: Slot, right_hand: Slot, tint: FlaskTint, charges: u8, ammo: ?u8) void {
    // Three columns wide, corners left out.
    const stepX = SLOT_W + SLOT_GAP;
    const left = MARGIN;
    const bottom = rl.getScreenHeight() - BOTTOM;
    const midX = left + stepX; // the centre cell of the three
    const midY = bottom - SLOT_H - PITCH_Y; // …the side arms' top edge
    slot(midX, midY - PITCH_Y, .empty, .crimson, 0); // UP — sorcery/incantation
    slot(left, midY, left_hand, .crimson, 0); // LEFT — left hand: the shield, or nothing behind a bow
    slot(midX + stepX, midY, right_hand, .crimson, 0); // RIGHT — right hand: the sword or the bow
    slot(midX, midY + PITCH_Y, .flask, tint, charges); // DOWN — the quick item
    // …and the AMMO the armament above it eats, in a short box UNDER that slot (ER's own place for it), only
    // when something is loaded.
    if (ammo) |n| ammoBox(midX + stepX, midY + SLOT_H + AMMO_GAP, n);
}

// HALF-HEIGHT, so it reads as a subordinate of the weapon slot rather than a fifth slot in a cross of four.
const AMMO_H: i32 = eq(26);
const AMMO_GAP: i32 = eq(5);
const AMMO_DRY = rgba(150, 96, 88, 220); // …the dry flask's own red, so "out of it" reads the same everywhere

fn ammoBox(x: i32, y: i32, n: u8) void {
    const on = n > 0;
    rl.drawRectangle(x, y, SLOT_W, AMMO_H, rgba(8, 7, 6, if (on) WELL_ON else WELL_OFF));
    const r = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(SLOT_W),
        .height = @floatFromInt(AMMO_H),
    };
    rl.drawRectangleLinesEx(r, 1, if (on) SLOT_ON else SLOT_OFF);
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
    // Fletches splay BACKWARD. Drawn the other way they open toward the head and the icon reads as a
    // double-headed arrow.
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
    // A slot with a DRY flask in it is still occupied — it lights as a filled slot and the flask is drawn dim, because "empty flask" and "no flask" have to look different or you cannot tell whether to go and rest.
    const on = holds != .empty;
    rl.drawRectangle(x, y, SLOT_W, SLOT_H, rgba(8, 7, 6, if (on) WELL_ON else WELL_OFF)); // the well
    const r = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(SLOT_W),
        .height = @floatFromInt(SLOT_H),
    };
    rl.drawRectangleLinesEx(r, 1, if (on) SLOT_ON else SLOT_OFF);
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
const CERULEAN = rgba(64, 128, 200, 255); // …of Cerulean Tears
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
    // The BULB, as three stacked rounded bands — a circle alone reads as a bauble, and the taper into the neck is most of what says "bottle".
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
    // A lit highlight down the left of the glass — one stroke, and it is what stops the icon reading as a flat blob at 66 px.
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

const ICON = SLOT_W; // …the square the diagonal is drawn in
fn sword(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = s / 34.0; // stroke widths were tuned at a 34 px slot; carry them up with the size
    const d = s * 0.55; // half the icon's diagonal — ~78% of the slot's width, ER's own fill
    const u = 0.70711; // the diagonal axis, pommel-ward…
    const tip = rl.Vector2{ .x = cx - u * d, .y = cy - u * d };
    const gx = cx + u * d * 0.34; // …the guard sits low on it
    const gy = cy + u * d * 0.34;
    const guard = rl.Vector2{ .x = gx, .y = gy };
    const pom = rl.Vector2{ .x = cx + u * d * 0.92, .y = cy + u * d * 0.92 };
    const q = s * 0.22; // crossguard half-width, ACROSS the axis — the BLADE has to dominate
    rl.drawLineEx(tip, guard, 3.6 * k, STEEL_DK); // blade body…
    rl.drawLineEx(tip, guard, 1.4 * k, STEEL); // …with a lit core down the middle
    rl.drawLineEx(guard, pom, 3.0 * k, GRIP); // grip UNDER the guard, so the cross reads on top
    rl.drawLineEx(.{ .x = gx + u * q, .y = gy - u * q }, .{ .x = gx - u * q, .y = gy + u * q }, 3.2 * k, BRASS);
    rl.drawCircleV(pom, 2.6 * k, BRASS);
}

/// Dead screen centre, because that is literally where an aimed shot goes. Four ticks and a GAP: the middle
/// is the part of the screen you are trying to look at. `k` grows it in with the stance.
pub fn reticle(k: f32) void {
    const a = mathx.clampF(k, 0, 1);
    if (a <= 0.02) return;
    const cx = @divTrunc(rl.getScreenWidth(), 2);
    const cy = @divTrunc(rl.getScreenHeight(), 2);
    const gap: i32 = 5;
    const len: i32 = @intFromFloat(3.0 + 7.0 * a); // …the ticks reach out as the bow comes up
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

// THE BOW, in the right hand's slot when it is the bow he is holding — on the SAME diagonal as the sword,
// Its OWN two values, NOT the mesh's in `archer.zig`: these are literal screen values drawn after the retro
// blit, where the mesh's are albedos bound for a 1.72 key and a 1/2.2 gamma.
const BOWWOOD = rgba(96, 68, 44, 255);
const BOWSTRING = rgba(214, 206, 184, 255);
fn bowIcon(cx: f32, cy: f32) void {
    const s: f32 = @floatFromInt(ICON);
    const k = s / 34.0; // the icon set's shared stroke scale (see `sword`)
    const d = s * 0.55; // …and its diagonal reach, so bow and sword fill the slot alike
    const u = 0.70711;
    const tx = cx - u * d;
    const ty = cy - u * d;
    const bx = cx + u * d;
    const by = cy + u * d;
    // The LIMBS, as two short chords off the belly point — rounder at this size than a real curve costs.
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
    rl.drawCircleV(c, boards, GRIP); // …with the boards inside it
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
