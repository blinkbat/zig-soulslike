const rl = @import("raylib");
const mathx = @import("mathx.zig");

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
pub const TITLE: i32 = 34; // the game title, card headings
pub const BODY: i32 = 22; // primary readouts — the gait/speed line, menu rows
pub const SMALL: i32 = 20; // secondary readouts — subtitle, control hints, debug lines
pub const HINT: i32 = 19; // the least important line on screen

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
