const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const uiart = @import("uiart.zig");
const itemart = @import("itemart.zig"); // the pictures in the cross — shared with the character book

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
pub const TINY: i32 = 16; // the caption UNDER a slot — a name, not a readout

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

/// The FRAME of the bar that refused, drawn over the finished bar and OUTSIDE its fill — this fires exactly
/// when a bar is empty and has no fill left to tint. One body: two bars can refuse.
fn refuseRing(x: i32, y: i32, w: i32, h: i32, k: f32) void {
    if (k <= 0.001) return;
    const a: u8 = @intFromFloat(230 * mathx.clampF(k, 0, 1));
    rl.drawRectangleLines(x - 2, y - 2, w + 4, h + 4, mathx.withAlpha(WARN, a));
    rl.drawRectangleLines(x - 3, y - 3, w + 6, h + 6, mathx.withAlpha(WARN, a / 2));
}

pub fn vitals(dt: f32, hp: f32, fp: f32, stam: f32, stamRefused: f32, fpRefused: f32, windedTo: f32) void {
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
    refuseRing(MARGIN, y, FP_W, FP_H, fpRefused); // a cast the pool could not cover
    y += FP_H + BAR_GAP;
    bar(MARGIN, y, ST_W, ST_H, stam, 0, ST_HI, ST_LO, ST_TP);
    if (windedTo > 0.001) {
        const wf: f32 = @floatFromInt(ST_W);
        const owed: i32 = @intFromFloat(wf * mathx.clampF(windedTo, 0, 1));
        const fill: i32 = @intFromFloat(wf * mathx.clampF(stam, 0, 1));
        if (owed > fill) rl.drawRectangle(MARGIN + fill, y, owed - fill, ST_H, mathx.withAlpha(WARN, 46));
        rl.drawRectangle(MARGIN + owed - 1, y - 1, 2, ST_H + 2, mathx.withAlpha(WARN_LT, 210)); // the threshold
    }
    refuseRing(MARGIN, y, ST_W, ST_H, stamRefused);
}

/// Three values (flat body, shaded bottom band, lit hairline) plus a catchlight on the leading edge while the
/// bar is short of full. `shade` is how deep the bottom band runs; `tipW`/`tipA` size the leading edge.
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

pub const Slot = enum { empty, sword, bow, shield, wand, flask, spell };

pub const FlaskTint = itemart.FlaskTint;

/// `left`/`right` are what is IN HIS HANDS this frame, not what he owns — the cross is four slots and it `tint` picks which flask is drawn in the DOWN slot, `charges` how many are left — the cross is where ER shows both, and a charge count you have to open a menu for is a charge count you play without.
/// `up` is the SORCERY slot, and `castable` is whether the pool would cover one — it stays `.empty` while
/// nothing he is holding could cast, because an empty ER slot is a real part of this HUD.
pub fn equipment(left_hand: Slot, right_hand: Slot, up: Slot, castable: bool, tint: FlaskTint, charges: u8, ammo: ?Ammo) void {
    const stepX = SLOT_W + SLOT_GAP;
    const left = MARGIN;
    const bottom = rl.getScreenHeight() - BOTTOM;
    const midX = left + stepX; // the centre cell of the three
    const midY = bottom - SLOT_H - PITCH_Y;
    slot(midX, midY - PITCH_Y, up, .crimson, if (castable) 1 else 0); // UP — sorcery/incantation
    slot(left, midY, left_hand, .crimson, 0); // LEFT — left hand: the shield, or nothing behind a bow
    slot(midX + stepX, midY, right_hand, .crimson, 0); // RIGHT — right hand: the sword or the bow
    slot(midX, midY + PITCH_Y, .flask, tint, charges); // DOWN — the quick item
    if (ammo) |n| ammoBox(midX + stepX, midY + SLOT_H + AMMO_GAP, n);
}

const AMMO_H: i32 = eq(26);
const AMMO_GAP: i32 = eq(5);
/// A TALLY THAT HAS RUN OUT, and one that has not — the ammo box and the flask charges are the same
/// question asked twice, so they read the same two tones.
const TALLY_DRY = rgba(150, 96, 88, 220);
const TALLY_OK = rgba(232, 224, 202, 255);

/// WHAT IS ON THE STRING, and how many are left of it.
pub const Ammo = struct { n: u8, fire: bool = false };


/// A count in a slot's bottom-right corner (flask charges, quiver shafts, bag stacks). Laid off the CORNER, not
/// off the text's own height: the glyphs have descenders, and measured that way every tally sat on its rim.
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
    // The ammo box is a SHORT slot: its count sits on the middle line, not down in a corner it has none of.
    text(s, x + SLOT_W - textW(s, HINT) - 6, y + @divTrunc(AMMO_H - lineH(HINT), 2), HINT, col);
}

fn slot(x: i32, y: i32, holds: Slot, tint: FlaskTint, charges: u8) void {
    uiart.slot(x, y, SLOT_W, SLOT_H, holds != .empty);
    const cx: f32 = @floatFromInt(x + @divTrunc(SLOT_W, 2));
    const cy: f32 = @floatFromInt(y + @divTrunc(SLOT_H, 2));
    const px: f32 = @floatFromInt(ICON);
    switch (holds) {
        .empty => {},
        .sword => itemart.sword(cx, cy, px),
        .bow => itemart.bow(cx, cy, px),
        .shield => itemart.shield(cx, cy, px),
        .wand => itemart.wand(cx, cy, px),
        // The sorcery slot's picture greys out when the FP will not cover a cast, which is the ammo box's
        // own rule: a thing you cannot use has to LOOK like a thing you cannot use.
        .spell => itemart.spell(cx, cy, px, charges > 0),
        .flask => {
            itemart.flask(cx, cy, px, tint, charges > 0);
            var buf: [8]u8 = undefined;
            const s = std.fmt.bufPrintZ(&buf, "{d}", .{charges}) catch return;
            tally(s, x + SLOT_W, y + SLOT_H + 6, HINT, if (charges > 0) TALLY_OK else TALLY_DRY);
        },
    }
}

/// THE BOX THE CROSS'S PICTURES ARE DRAWN IN — the slot's own width. `itemart` scales every stroke off
/// whatever it is handed, so this is the HUD's size and nobody else's.
const ICON = SLOT_W;

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

/// Break `s` to `maxW` pixels at `size`, writing NUL-terminated lines into `buf` and returning the filled ones.
/// MEASURED WITH THE REAL FACE per candidate word, not a characters-per-line guess: Balthazar is proportional.
/// A word wider than the whole column is taken anyway and overhangs; running out of either buffer stops cleanly.
pub fn wrap(s: []const u8, size: i32, maxW: i32, buf: []u8, lines: [][:0]const u8) [][:0]const u8 {
    return wrapBy(textW, s, size, maxW, buf, lines);
}

/// …measured by whatever is passed in. A test binary opens no window and so loads no font, which makes
/// every string zero wide and every wrap one line: the algorithm is only checkable against a ruler the
/// test brings itself.
fn wrapBy(comptime measure: fn ([:0]const u8, i32) i32, s: []const u8, size: i32, maxW: i32, buf: []u8, lines: [][:0]const u8) [][:0]const u8 {
    var n: usize = 0;
    var used: usize = 0; // committed bytes of `buf`…
    var len: usize = 0; // …and the length of the line being built at buf[used..]
    var it = std.mem.tokenizeAny(u8, s, " \n\t");
    while (it.next()) |word| {
        if (n >= lines.len) break;
        const sep: usize = if (len > 0) 1 else 0;
        if (used + len + sep + word.len + 1 > buf.len) break;
        // The candidate is written into the scratch past the live line, so it costs nothing to reject.
        if (sep == 1) buf[used + len] = ' ';
        @memcpy(buf[used + len + sep ..][0..word.len], word);
        buf[used + len + sep + word.len] = 0;
        const cand: [:0]const u8 = buf[used .. used + len + sep + word.len :0];
        if (len == 0 or measure(cand, size) <= maxW) {
            len += sep + word.len;
            continue;
        }
        buf[used + len] = 0; // it did not fit: the line ends before this word…
        lines[n] = buf[used .. used + len :0];
        n += 1;
        used += len + 1;
        len = 0;
        if (n >= lines.len) break;
        if (used + word.len + 1 > buf.len) break;
        @memcpy(buf[used..][0..word.len], word); // …and the word opens the next one
        len = word.len;
    }
    if (len > 0 and n < lines.len) {
        buf[used + len] = 0;
        lines[n] = buf[used .. used + len :0];
        n += 1;
    }
    return lines[0..n];
}

/// A ruler with no font behind it: every glyph one unit wide, so a column is a character count.
fn perChar(s: [:0]const u8, size: i32) i32 {
    _ = size;
    return @intCast(s.len);
}

test "wrap breaks on words and keeps every one of them" {
    var buf: [512]u8 = undefined;
    var rows: [8][:0]const u8 = undefined;
    const src = "A tuft of the red grass that grows where something bled. Worthless, and everywhere.";
    const out = wrapBy(perChar, src, BODY, 24, &buf, &rows);
    try std.testing.expect(out.len > 1); // it DID break
    var kept: usize = 0;
    for (out) |line| {
        try std.testing.expect(line.len > 0);
        try std.testing.expect(line.len <= 24); // …and no line is wider than the column it was given
        kept += line.len;
    }
    // Every word survived: the joined lines are the source less the spaces that became breaks.
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

