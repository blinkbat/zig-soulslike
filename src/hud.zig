const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const rgba = mathx.rgba;

// ALL UI text goes through here, in BALTHAZAR (assets/, OFL alongside). Never call rl.drawText or
// measureText directly, or layout drifts between the font and the fallback. Two atlases of the same face,
// both sized ABOVE the largest type drawn at them so every draw DOWNscales (an upscaled glyph is the
// jagged one). Falls back to raylib's default font if the asset is missing; the path is CWD-relative.
var haveFont = false;
var font: rl.Font = undefined;
var haveBig = false;
var fontBig: rl.Font = undefined;

const FONT_PATH = "assets/Balthazar-Regular.ttf";
// Atlas resolution, comfortably ABOVE the largest size drawn (TITLE). It was 44, sized for a HUD topping
// out at 24; at the current sizes that was being magnified and this face's thin strokes broke into
// stair-steps.
const ATLAS_PX = 96;
const ATLAS_BIG_PX = 160; // the cinematic caption atlas (YOU DIED draws near 90 px)

// ── THE TYPE SCALE ── every size comes from here. Scattered literals drift, and "make the text bigger"
// becomes fifteen edits with no consistency at the end. Balthazar is a light serif, so it wants to be set
// LARGER than a UI sans would — below ~18 px its detail falls apart.
pub const TITLE: i32 = 34; // menu card headings (the HUD carries no title — see THE ELDEN RING HUD)
pub const BODY: i32 = 22; // primary readouts — the debug gait/speed line, menu rows
pub const SMALL: i32 = 20; // secondary readouts — the debug corner's rows
pub const HINT: i32 = 19; // the least important line on screen (the menu's control crib)

// MIPMAP THE ATLAS. This is what "jagged" actually was, and the old comment had exactly half the
// rule: an UPscaled glyph is jagged, yes — but a 96 px glyph drawn at 20 is a 4.8x DOWNscale, and a
// bilinear fetch only ever reads the four texels nearest one sample point. At that ratio it is
// skipping four texels out of five, so which part of a thin serif stroke survives is luck, and it
// changes when the text moves a pixel. That is the shimmer, and it is the same undersampling the
// scene shader's detail-LOD block exists to fix — a procedural pattern and a font atlas alias for
// one reason.
//
// The fix is the same one too: give it a mip chain and let the hardware pick the level that matches
// the footprint. Trilinear then blends between levels so a size between two mips doesn't pop.
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

// Drop shadow for legibility over the 3D scene. It tracks the face alpha, so fading text leaves no black
// ghost, and its OFFSET SCALES with the size — a fixed 1 px shadow under 30 px type reads as a smudge on
// the glyph edge rather than depth, which is half of what "jagged" looks like at a glance.
pub fn text(s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
    const off: i32 = @max(@divTrunc(size, 14), 1);
    drawStr(s, x + off, y + off, size, mathx.withAlpha(rl.Color.black, @intCast(@as(u16, 200) * col.a / 255)));
    drawStr(s, x, y, size, col);
}

/// Line height for a given size — the vertical step between stacked lines of text. One place, so
/// a size change doesn't leave the debug overlay's rows overlapping.
pub fn lineH(size: i32) i32 {
    return size + @divTrunc(size, 3);
}

// ── MONOSPACE (the EDITOR only) ────────────────────────────────────────────────────────
// A REAL system monospace face — Consolas, then the other Windows-stock fixed-pitch faces, then whatever
// a non-Windows box has. Numbers line up in a column and a value that grows a digit doesn't shove its row
// about, which is what an editor needs and what Balthazar (a proportional display serif) is exactly wrong
// for. Kept OUT of the game's own UI, which stays Balthazar by owner's pick. One atlas well above the
// drawn size, same rule as the HUD face. raylib's built-in bitmap font is the LAST resort: it is a 10 px
// pixel font and smears at anything other than an exact integer multiple of its cell.
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

/// The editor's one type size. A TTF now, so this is a free choice rather than a multiple of a
/// bitmap cell — 18 is where Consolas is dense enough for a panel and still crisp.
pub const MONO: i32 = 18;

fn initMono() void {
    for (MONO_CANDIDATES) |path| {
        // `atlas` also rejects a face that "loaded" as raylib's 0-glyph default — take one of those
        // and every string in the editor measures as nothing.
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

/// Row pitch for stacked monospace rows.
pub fn monoLineH(size: i32) i32 {
    return size + @divTrunc(size, 4);
}

/// Right-aligned text ending `pad` px from the right screen edge — the debug corner's row
/// idiom. Measuring at the call site is how a right-aligned column ends up ragged.
pub fn textRight(s: [:0]const u8, pad: i32, y: i32, size: i32, col: rl.Color) void {
    text(s, rl.getScreenWidth() - textW(s, size) - pad, y, size, col);
}

// Huge letter-spaced caption, CENTERED on (cx, cy) — the cinematic text path (YOU DIED).
// Drawn from the big atlas; `spacing` is extra px between glyphs at this size.
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

// ══ THE ELDEN RING HUD ═══════════════════════════════════════════════════════════════════
// ER puts its furniture in three corners and nowhere else: the vitals bars TOP-LEFT, the armament slot
// grid BOTTOM-LEFT, and (ours, in place of ER's boss bar and compass) the debug readout TOP-RIGHT. No
// title, no subtitle, no control crib — the game names itself in the menu.
//
// Colours here are LITERAL screen values: the HUD draws after the retro blit and outside the scene
// shader, so the author-dark / gamma rules governing every mesh colour do not apply.
//
// Widths are ER's PROPORTIONS, not its pixels — HP longest and thickest, FP shortest, stamina between.
// That silhouette is most of what makes the corner read as Elden Ring, so the three must stay different
// lengths even if the numbers are retuned.

/// How far every HUD corner sits off the screen edge. Public because game.zig draws the debug corner and
/// insets it by the same amount — two separately-tuned margins is how one corner stops lining up with the
/// other.
pub const MARGIN: i32 = 30;
const BAR_TOP: i32 = 24;
const BAR_GAP: i32 = 6;
const HP_W: i32 = 268;
const HP_H: i32 = 15;
const FP_W: i32 = 182;
const FP_H: i32 = 11;
const ST_W: i32 = 232;
const ST_H: i32 = 11;

// ALPHAS ARE DELIBERATELY SHORT OF OPAQUE (owner's call — the bars and the rune plate read as
// solid furniture sat on top of the game). ER's own HUD lets the world through its chrome, which is
// most of why it feels like part of the frame rather than a layer above it. Everything below is
// pulled back about a fifth: still legible against dry grass, no longer a sticker.
const TRACK = rgba(16, 13, 11, 186); // the empty channel behind every fill
const FRAME = rgba(116, 104, 84, 210); // the tarnished-metal rim, a hairline outside the track
// Each bar is THREE values: a flat body, a shaded bottom third, a lit hairline on top. One flat colour is
// the tell that a bar was drawn rather than designed; a fat centred gradient is the other, reading as a
// plastic tube.
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

// THE CHIP BAR, the most ER-identifying thing on screen: the red fill snaps to the new HP the instant you
// are hit and a paler bar hangs at the OLD value for a beat before draining to meet it, so you read what
// the blow cost after it has landed. Cosmetic and frame-local, hence module state, not the hero's.
var chip: f32 = 1;
var chipHold: f32 = 0;
var chipLast: f32 = 1;
const CHIP_HOLD = 0.42; // seconds the trail hangs before it starts draining
const CHIP_RATE = 0.55; // …then drains this fraction of the bar per second

/// The three vitals bars, top-left. `dt` drives the chip trail only — pass the fixed shot timestep under
/// --shot and it stays reproducible. `stamRefused` in 0..1 is how hot the "that action was refused" flag
/// burns: an empty-bar input does nothing at all in ER, and nothing is indistinguishable from a DROPPED
/// input, so this is the one place that can say which it was.
pub fn vitals(dt: f32, hp: f32, fp: f32, stam: f32, stamRefused: f32) void {
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
    // The refusal flag lights the stamina bar's own FRAME, over the finished bar and outside its fill —
    // so an empty bar, which is exactly when this fires and has no fill to tint, still reads loudly.
    const k = mathx.clampF(stamRefused, 0, 1);
    if (k > 0.001) {
        const a: u8 = @intFromFloat(230 * k);
        rl.drawRectangleLines(MARGIN - 2, y - 2, ST_W + 4, ST_H + 4, rgba(232, 96, 72, a));
        rl.drawRectangleLines(MARGIN - 3, y - 3, ST_W + 6, ST_H + 6, rgba(232, 96, 72, a / 2));
    }
}

fn bar(x: i32, y: i32, w: i32, h: i32, frac: f32, chipFrac: f32, hi: rl.Color, lo: rl.Color, tp: rl.Color) void {
    // The rim goes OUTSIDE the fill, between the black edge and the track: over the fill it muddies the
    // lit hairline below and the bar loses its top edge.
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
        // The leading edge catches the light — what makes a draining bar read as MOVING rather than as a
        // rectangle that got shorter.
        if (fw > 2 and frac < 0.999) rl.drawRectangle(x + fw - 2, y, 2, h, rgba(255, 244, 226, 64));
    }
}

// ── the floating HP bar over a hurt foe ─────────────────────────────────────────────────
// Here with the rest of the HUD so there is ONE blood red in the game: this and the hero's bar were
// separately-authored near-identical values, a drift waiting for the first retune. Its TRACK stays its
// own — 5 px of bar over a head wants more contrast than 15 px against the sky.
const FOE_W: i32 = 54;
const FOE_H: i32 = 5;
const FOE_LIFT: i32 = 16; // …how far above the projected crown it rides
const FOE_TRACK = rgba(38, 12, 10, 230);
const STAGGER_RIM = rgba(232, 196, 90, 255); // ER's gold crit-opening cue on a stance break

/// `sx`/`sy` are the foe's crown PROJECTED to screen; the bar centres on it and lifts clear.
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

// ── THE RUNE COUNTER, bottom-right ──────────────────────────────────────────────────────
// ER's fourth and last piece of furniture, in ER's own corner — also the last FREE corner, so the HUD's
// "three places and nowhere else" becomes four and stops there. The number ROLLS (combat.Runes owns that;
// this prints what it is handed) on a plate dark enough to hold digits against dry grass, hairlined in the
// vitals frames' metal, RIGHT-ALIGNED — a counter that grows a digit and shoves itself sideways is the one
// thing you cannot read at a glance mid-fight. Seated off the bottom by `BOTTOM`, the equipment cross's
// own margin, so the two bottom corners sit on one line.
const RUNE_W: i32 = 122;
const RUNE_H: i32 = 32;
const RUNE_FILL = rgba(14, 12, 10, 170); // …pulled back with the bars (see TRACK) — owner's call
const RUNE_EDGE = rgba(116, 104, 84, 186); // …the vitals bars' FRAME colour, deliberately
const RUNE_TEXT = rgba(228, 216, 190, 255);

/// `n` is the ROLLING value (`combat.Runes.display()`), not the banked total: a number that snaps is a
/// readout where one that counts up is a reward.
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

// ── the equipment cross, bottom-left ────────────────────────────────────────────────────
// ER's bottom-left is a D-PAD CROSS of exactly four slots: sorcery UP, left hand LEFT, right hand RIGHT,
// quick item DOWN. Only the right hand's is filled — the hero carries one sword and there are no spells or
// consumables, and an empty ER slot is a real part of that HUD, where inventing a flask count for flasks
// that don't exist would be a lie in the corner of every screenshot.
//
// A slot is PORTRAIT, ER's own proportion (an armament icon is a long thing stood on end); square slots
// read as a keypad rather than as equipment. The GAP has to be readable as a gap at a glance, or the four
// arms close back into a block.
//
// THE WHOLE CROSS SCALES OFF ONE NUMBER. Every size below is a TUNED PROPORTION with a reason — the
// portrait slot, the readable gap, a vertical pitch deliberately tighter than a slot is tall — so resizing
// by editing them individually is how those relationships get lost. Change EQ_SCALE. (A PERCENTAGE, not an
// integer multiplier: as `2` it could only say 1x or 2x, so "a bit smaller" was not expressible through it
// at all. 150 is the owner's 2x eased back a quarter.) The sword icon needs nothing — it sizes off SLOT_W
// and carries its stroke widths up.
const EQ_SCALE: i32 = 150; // percent
fn eq(v: i32) i32 {
    return @divTrunc(v * EQ_SCALE, 100);
}
const SLOT_W: i32 = eq(44);
const SLOT_H: i32 = eq(60);
const SLOT_GAP: i32 = eq(8); // between the LEFT/RIGHT arms and the centre column
// The vertical pitch is DELIBERATELY LESS THAN A SLOT IS TALL, and it is not derived from
// SLOT_GAP. A full slot plus a gap leaves a void up the middle taller than the slots themselves and the
// four read as scattered; pulled in, top and bottom overlap the side slots' rows and the group closes into
// one shape.
const PITCH_Y: i32 = eq(48);
// The seat off the bottom does NOT scale — it is a screen margin like MARGIN, and doubling it would just
// push the cross inward.
const BOTTOM: i32 = 26;

// An ER slot is a faint WELL under a visible thin rim. The other way round, the cross reads as solid black
// tiles stamped on the corner.
const WELL_ON: u8 = 148;
const WELL_OFF: u8 = 68;
const SLOT_ON = rgba(180, 168, 140, 240); // an occupied slot's brighter rim
const SLOT_OFF = rgba(124, 115, 98, 122);
const STEEL = rgba(232, 234, 238, 255);
const STEEL_DK = rgba(126, 132, 140, 255);
const BRASS = rgba(182, 146, 78, 255);
const GRIP = rgba(112, 82, 56, 255); // …light enough to READ against the well, not true leather

/// What is in a slot. The cross has exactly four and only two of them hold anything, so this is an
/// exhaustive little enum rather than an icon-id system for a game with two icons.
pub const Slot = enum { empty, sword, flask };

/// WHICH flask is in the quick-item slot. Its own enum for the same reason `Slot` is one, and
/// deliberately NOT `combat.FlaskKind`: this file takes plain values and knows nothing about the
/// hero or the combat layer (AGENTS.md), so the caller does the one-line translation. It replaces a
/// `crimson: bool` threaded through three functions — a two-variant type flattened to a boolean,
/// where every `false` silently means "the other one" and a third flask would land as Cerulean
/// everywhere without a single compile error.
pub const FlaskTint = enum { crimson, cerulean };

/// `tint` picks which flask is drawn in the DOWN slot, `charges` how many are left — the cross is
/// where ER shows both, and a charge count you have to open a menu for is a charge count you play
/// without.
pub fn equipment(tint: FlaskTint, charges: u8) void {
    // Three columns wide, corners left out. The two axes pitch SEPARATELY (see PITCH_Y) — one shared step
    // either splays the cross apart vertically or crushes the side arms together.
    const stepX = SLOT_W + SLOT_GAP;
    const left = MARGIN;
    const bottom = rl.getScreenHeight() - BOTTOM;
    const midX = left + stepX; // the centre cell of the three
    const midY = bottom - SLOT_H - PITCH_Y; // …the side arms' top edge
    slot(midX, midY - PITCH_Y, .empty, .crimson, 0); // UP — sorcery/incantation
    slot(left, midY, .empty, .crimson, 0); // LEFT — left hand
    slot(midX + stepX, midY, .sword, .crimson, 0); // RIGHT — right hand, the sword
    slot(midX, midY + PITCH_Y, .flask, tint, charges); // DOWN — the quick item
}

fn slot(x: i32, y: i32, holds: Slot, tint: FlaskTint, charges: u8) void {
    // A slot with a DRY flask in it is still occupied — it lights as a filled slot and the flask is
    // drawn dim, because "empty flask" and "no flask" have to look different or you cannot tell
    // whether to go and rest.
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
        .flask => {
            flask(cx, cy, tint, charges > 0);
            // The charge count, bottom-right of the slot like ER's. Small, and it goes RED-dim at
            // zero rather than vanishing — a missing number reads as a HUD fault.
            var buf: [8]u8 = undefined;
            const s = std.fmt.bufPrintZ(&buf, "{d}", .{charges}) catch return;
            const col = if (charges > 0) rgba(232, 224, 202, 255) else rgba(150, 96, 88, 220);
            text(s, x + SLOT_W - textW(s, HINT) - 5, y + SLOT_H - lineH(HINT) + 1, HINT, col);
        },
    }
}

// ── THE FLASK ICON ── a round-shouldered bottle with a stopper: ER's own silhouette, and the one
// shape that cannot be mistaken for the sword in the slot above it. Drawn from primitives at the
// same stroke scale the sword uses, so the two read as one icon set.
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
    // Dry flasks keep their shape and lose their contents, which is exactly what you need to read.
    const fill = if (full) lit else rgba(dk.r, dk.g, dk.b, 150);
    const body = s * 0.30; // half-width of the bulb
    const bodyY = cy + s * 0.10;
    // The BULB, as three stacked rounded bands — a circle alone reads as a bauble, and the taper
    // into the neck is most of what says "bottle".
    rl.drawCircleV(.{ .x = cx, .y = bodyY }, body, fill);
    rl.drawRectangleRounded(.{
        .x = cx - body * 0.86,
        .y = bodyY - body * 0.95,
        .width = body * 1.72,
        .height = body * 1.30,
    }, 0.45, 6, fill);
    // The NECK and the shoulders.
    rl.drawRectangleV(
        .{ .x = cx - s * 0.085, .y = cy - s * 0.30 },
        .{ .x = s * 0.17, .y = s * 0.30 },
        fill,
    );
    // A lit highlight down the left of the glass — one stroke, and it is what stops the icon
    // reading as a flat blob at 66 px.
    rl.drawLineEx(
        .{ .x = cx - body * 0.52, .y = bodyY - body * 0.55 },
        .{ .x = cx - body * 0.62, .y = bodyY + body * 0.35 },
        1.8 * k,
        rgba(GLASS.r, GLASS.g, GLASS.b, if (full) 190 else 90),
    );
    // The STOPPER, proud of the neck.
    rl.drawRectangleV(
        .{ .x = cx - s * 0.065, .y = cy - s * 0.40 },
        .{ .x = s * 0.13, .y = s * 0.11 },
        CORK,
    );
}

// The one armament he carries, on ER's icon diagonal (tip up-left, pommel down-right). STROKES, not boxes:
// a slot this size wants a legible silhouette and a little model of a sword turns to mud. Sized off the
// slot's WIDTH, the narrow axis, because a diagonal icon spans the same distance both ways — off the height
// it would push the tip and pommel out through the sides.
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
