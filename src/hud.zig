const rl = @import("raylib");
const mathx = @import("mathx.zig");

// ALL UI text goes through here in Exo (assets/, OFL license alongside) — zig-rts's hud
// discipline: never call rl.drawText/measureText directly in UI code or layout drifts
// between the font and the fallback. One 44 px atlas: every HUD size is <= 22, so draws
// only ever downscale. Falls back to raylib's default font if the asset is missing (path
// is CWD-relative — run from repo root).
var haveFont = false;
var font: rl.Font = undefined;

const FONT_PATH = "assets/Exo-Regular.ttf";
const ATLAS_PX = 44;

pub fn init() void {
    if (rl.loadFontEx(FONT_PATH, ATLAS_PX, null)) |f| {
        font = f;
        rl.setTextureFilter(font.texture, .bilinear);
        haveFont = true;
    } else |_| {}
}

pub fn deinit() void {
    if (haveFont) rl.unloadFont(font);
    haveFont = false;
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

// Text with a 1 px drop shadow for legibility over the 3D scene. Shadow tracks the face
// alpha so fading text doesn't leave a black ghost.
pub fn text(s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
    drawStr(s, x + 1, y + 1, size, mathx.withAlpha(rl.Color.black, @intCast(@as(u16, 200) * col.a / 255)));
    drawStr(s, x, y, size, col);
}
