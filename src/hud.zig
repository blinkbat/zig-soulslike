const rl = @import("raylib");
const mathx = @import("mathx.zig");

const rgba = mathx.rgba;

// ALL UI text goes through here, in BALTHAZAR (assets/, OFL alongside). Never call
// rl.drawText/measureText directly in UI code or layout drifts between the font and the
// fallback. Two atlases of the same face — ATLAS_PX for the HUD, ATLAS_BIG_PX for the
// cinematic captions — both sized ABOVE the largest type drawn at them, so every draw
// DOWNscales (an upscaled glyph is the jagged one). Falls back to raylib's default font if
// the asset is missing; the path is CWD-relative, so run from the repo root.
var haveFont = false;
var font: rl.Font = undefined;
var haveBig = false;
var fontBig: rl.Font = undefined;

const FONT_PATH = "assets/Balthazar-Regular.ttf";
// Atlas resolution. Must stay comfortably ABOVE the largest size anything draws at (TITLE), so
// every draw DOWNscales — an upscaled glyph is the jagged one. 44 px was sized for a HUD that
// topped out at 24; at the current sizes it was being magnified and the thin strokes of this face
// broke up into stair-steps.
const ATLAS_PX = 96;
const ATLAS_BIG_PX = 160; // the cinematic caption atlas (YOU DIED draws near 90 px)

// ── THE TYPE SCALE ── every size in the game comes from here. Scattered literals at call sites
// drift, and "make the text bigger" then becomes fifteen separate edits with no consistency at the
// end of it. Balthazar is a light serif with fine strokes, so it wants to be set LARGER than a
// UI sans would: below ~18 px its detail simply falls apart.
pub const TITLE: i32 = 34; // menu card headings (the HUD carries no title — see THE ELDEN RING HUD)
pub const BODY: i32 = 22; // primary readouts — the debug gait/speed line, menu rows
pub const SMALL: i32 = 20; // secondary readouts — the debug corner's rows
pub const HINT: i32 = 19; // the least important line on screen (the menu's control crib)

pub fn init() void {
    if (rl.loadFontEx(FONT_PATH, ATLAS_PX, null)) |f| {
        font = f;
        rl.setTextureFilter(font.texture, .bilinear);
        haveFont = true;
    } else |_| {}
    if (rl.loadFontEx(FONT_PATH, ATLAS_BIG_PX, null)) |f| {
        fontBig = f;
        rl.setTextureFilter(fontBig.texture, .bilinear);
        haveBig = true;
    } else |_| {}
}

pub fn deinit() void {
    if (haveFont) rl.unloadFont(font);
    haveFont = false;
    if (haveBig) rl.unloadFont(fontBig);
    haveBig = false;
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

// Text with a drop shadow for legibility over the 3D scene. Shadow tracks the face alpha so
// fading text doesn't leave a black ghost, and its OFFSET SCALES with the size — a fixed 1 px
// shadow under 30 px type reads as a smudge on the glyph edge rather than as depth, which is
// half of what "jagged" looks like at a glance.
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
// ER puts its screen furniture in three corners and nowhere else: the three vitals bars
// TOP-LEFT, the armament / ammo / quick-item slot grid BOTTOM-LEFT, and (ours, in place of
// ER's boss bar and compass) the debug readout TOP-RIGHT. No title, no subtitle, no control
// crib — the game names itself in the menu.
//
// Colours here are LITERAL screen values. The HUD draws after the retro blit and outside the
// scene shader, so the author-dark / gamma rules that govern every mesh colour do not apply —
// what is written is what appears.
//
// Widths are ER's PROPORTIONS, not its pixels: HP longest and thickest, FP shortest, stamina
// between them. That silhouette is most of what makes the corner read as Elden Ring at a
// glance, so the three must stay different lengths even if the numbers are retuned.

/// How far every HUD corner sits off the screen edge. Public because the debug corner is drawn
/// by game.zig and inset by the same amount — two separately-tuned margins is how one corner
/// ends up not lining up with the other.
pub const MARGIN: i32 = 30;
const BAR_TOP: i32 = 24;
const BAR_GAP: i32 = 6;
const HP_W: i32 = 268;
const HP_H: i32 = 15;
const FP_W: i32 = 182;
const FP_H: i32 = 11;
const ST_W: i32 = 232;
const ST_H: i32 = 11;

const TRACK = rgba(16, 13, 11, 232); // the empty channel behind every fill
const FRAME = rgba(116, 104, 84, 238); // the tarnished-metal rim, a hairline outside the track
// Each bar is three values, not one: a flat body, a shaded bottom third, and a lit hairline
// along the top. A single flat colour is the tell that a bar was drawn rather than designed —
// and a fat centred gradient is the other one, reading as a plastic tube.
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

// THE CHIP BAR is the single most ER-identifying thing on the screen: the red fill snaps to
// the new HP the instant you are hit, and a paler bar hangs at the OLD value for a beat before
// draining down to meet it — so you read how much that blow cost after it has already landed.
// It is cosmetic and frame-local, hence module state rather than anything the hero carries.
var chip: f32 = 1;
var chipHold: f32 = 0;
var chipLast: f32 = 1;
const CHIP_HOLD = 0.42; // seconds the trail hangs before it starts draining
const CHIP_RATE = 0.55; // …then drains this fraction of the bar per second

/// The three vitals bars, top-left. `dt` drives the chip trail only — pass the fixed shot
/// timestep under --shot and it stays reproducible.
pub fn vitals(dt: f32, hp: f32, fp: f32, stam: f32) void {
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
}

fn bar(x: i32, y: i32, w: i32, h: i32, frac: f32, chipFrac: f32, hi: rl.Color, lo: rl.Color, tp: rl.Color) void {
    // The rim goes OUTSIDE the fill, between the black edge and the track. Laid over the fill
    // instead it just muddies the lit hairline below and the bar loses its top edge.
    rl.drawRectangle(x - 3, y - 3, w + 6, h + 6, rgba(0, 0, 0, 70)); // a soft seat off the sky…
    rl.drawRectangle(x - 2, y - 2, w + 4, h + 4, rgba(0, 0, 0, 215)); // …the hard black edge…
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
        // The leading edge catches the light: this is what makes a draining bar read as MOVING
        // rather than as a rectangle that got shorter.
        if (fw > 2 and frac < 0.999) rl.drawRectangle(x + fw - 2, y, 2, h, rgba(255, 244, 226, 64));
    }
}

// ── the floating HP bar over a hurt foe ─────────────────────────────────────────────────
// Lives here with the rest of the HUD so there is ONE blood red in the game: this and the
// hero's HP bar were separately-authored near-identical values, which is a drift waiting to
// happen the first time either is retuned. Its own track stays its own — 5 px of bar over a
// head wants more contrast than a 15 px bar against the sky.
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

// ── the equipment cross, bottom-left ────────────────────────────────────────────────────
// ER's bottom-left is a D-PAD CROSS of exactly four slots and nothing else: sorcery UP,
// left-hand armament LEFT, right-hand armament RIGHT, quick item DOWN. Only the right hand's
// is filled, because the hero carries exactly one sword and there are no spells or
// consumables — an empty ER slot is a real part of that HUD, and inventing a flask count for
// flasks that don't exist would be a lie told in the corner of every screenshot.
// A slot is PORTRAIT — taller than it is wide, ER's own proportion (an armament icon is a long
// thing stood on end). Square slots were the tell that this was a generic grid, and at 34 px
// they read as a keypad in the corner rather than as the game's equipment. The GAP is wide
// enough to be read as a gap at a glance: the four arms have to look like a cross, and a tight
// gap closes them back into a block.
const SLOT_W: i32 = 44;
const SLOT_H: i32 = 60;
const SLOT_GAP: i32 = 8; // between the LEFT/RIGHT arms and the centre column
// The vertical pitch is DELIBERATELY LESS THAN A SLOT IS TALL, and it is not derived from
// SLOT_GAP. Stepping down by a full slot plus a gap leaves a void up the middle taller than the
// slots themselves — the four read as scattered rather than as one cross. Pulled in, the top and
// bottom slots overlap the side slots' rows and the group closes up into a single shape.
const PITCH_Y: i32 = 48;
const BOTTOM: i32 = 26;

// An ER slot is a faint WELL under a visible thin rim — get that round the wrong way and the
// cross reads as solid black tiles stamped on the corner.
const WELL_ON: u8 = 148;
const WELL_OFF: u8 = 68;
const SLOT_ON = rgba(180, 168, 140, 240); // an occupied slot's brighter rim
const SLOT_OFF = rgba(124, 115, 98, 122);
const STEEL = rgba(232, 234, 238, 255);
const STEEL_DK = rgba(126, 132, 140, 255);
const BRASS = rgba(182, 146, 78, 255);
const GRIP = rgba(112, 82, 56, 255); // …light enough to READ against the well, not true leather

pub fn equipment() void {
    // Three columns wide, the corners left out, seated against the same margins as everything
    // else in this corner. The two axes are pitched SEPARATELY (see PITCH_Y) — one shared step
    // either splays the cross apart vertically or crushes the side arms together.
    const stepX = SLOT_W + SLOT_GAP;
    const left = MARGIN;
    const bottom = rl.getScreenHeight() - BOTTOM;
    const midX = left + stepX; // the centre cell of the three
    const midY = bottom - SLOT_H - PITCH_Y; // …the side arms' top edge
    slot(midX, midY - PITCH_Y, false); // UP — sorcery/incantation
    slot(left, midY, false); // LEFT — left hand
    slot(midX + stepX, midY, true); // RIGHT — right hand, the sword
    slot(midX, midY + PITCH_Y, false); // DOWN — quick item
}

fn slot(x: i32, y: i32, on: bool) void {
    rl.drawRectangle(x, y, SLOT_W, SLOT_H, rgba(8, 7, 6, if (on) WELL_ON else WELL_OFF)); // the well
    const r = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(SLOT_W),
        .height = @floatFromInt(SLOT_H),
    };
    rl.drawRectangleLinesEx(r, 1, if (on) SLOT_ON else SLOT_OFF);
    if (on) sword(@floatFromInt(x + @divTrunc(SLOT_W, 2)), @floatFromInt(y + @divTrunc(SLOT_H, 2)));
}

// The one armament he carries, on ER's icon diagonal (tip up-left, pommel down-right). Drawn as
// strokes, not boxes: a slot this size wants a legible SILHOUETTE, and a little model of a sword
// just turns to mud. It is sized off the slot's WIDTH — the narrow axis — because the icon sits
// on the diagonal and so spans the same distance both ways; hanging it off the height instead
// would push the tip and pommel out through the sides.
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
