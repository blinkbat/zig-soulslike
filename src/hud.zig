const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const uiart = @import("uiart.zig");
const daynight = @import("daynight.zig"); // the clock dial reads the hour's own arithmetic, never its own
const itemart = @import("itemart.zig"); // the pictures in the cross — shared with the character book
const item = @import("item.zig"); // …and what the DOWN cell holds is a bag item, off the quick bar
const gfx = @import("gfx.zig"); // …and a LIVE PORTRAIT is drawn through the world's own scene shader

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
    // A face that loaded but carries nothing is still an atlas texture and a glyph array; dropped on the
    // floor it leaks both. `unloadFont` refuses raylib's own default, which is what a FAILED load hands back.
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

// **THE HUD GOES OUT AS A WHOLE PICTURE, NOT AS A LIST OF THINGS THAT EACH KNOW AN ALPHA** (owner: gradually
// fade the HUD away when you die instead of removing it immediately). Every colour here is a LITERAL screen
// value — the bars, the dial's sky, the gilt rules, the pad glyphs, and the item pictures `itemart` draws into
// the cross, which are not this file's colours at all. Threading a factor through all of them is dozens of
// call sites and ONE of them missed is a slot left solid over a chrome that has gone, which reads worse than
// the hard cut it replaced. So the block is drawn once into a target and composited at one alpha: nothing can
// be missed, because nothing is asked.
//
// It costs a screen-sized target and one blit, and it is only paid WHILE a fade is running — at full chrome
// `begin` refuses and the draws go straight at the backbuffer exactly as they always did.
var veil: ?rl.RenderTexture2D = null;

fn veilFree() void {
    if (veil) |rt| rl.unloadRenderTexture(rt);
    veil = null;
}

/// Sized to the screen, rebuilt only when that changes (`gfx.Retro.resize`'s guard, and for its reason: a
/// reload every frame is a texture allocation every frame).
fn veilFor(w: i32, h: i32) ?rl.RenderTexture2D {
    if (w <= 0 or h <= 0) return null;
    if (veil) |rt| {
        if (rt.texture.width == w and rt.texture.height == h) return rt;
        veilFree();
    }
    veil = rl.loadRenderTexture(w, h) catch return null;
    return veil;
}

/// Redirect the chrome into the target, or refuse. TRUE means the caller MUST call `endChrome(k)` after it.
/// Refused at full — there is nothing to fade and the backbuffer is one blit cheaper.
pub fn beginChrome(k: f32) bool {
    if (k >= 0.999) return false;
    const rt = veilFor(rl.getScreenWidth(), rl.getScreenHeight()) orelse return false;
    rl.beginTextureMode(rt);
    rl.clearBackground(rgba(0, 0, 0, 0)); // …and it must start EMPTY, or the last frame's chrome is under it
    return true;
}

/// …and lay it down at `k`. A render target reads back FLIPPED, hence the negative source height — raylib's
/// own idiom, and the same one `gfx.Retro.end` uses.
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


// THE PAD IS THE ONLY THING THIS UI NAMES (owner's call). Every prompt, crib and footer in the game shows the
// BUTTON that does the thing — drawn, not spelled — and no keyboard key appears anywhere in it. Keys still
// work; they simply are not what the chrome talks about. The editor is the one exception and is not this UI:
// it is a mouse-and-keyboard authoring tool with no pad bindings at all.
//
// Xbox lettering and colours, because that is what a pad in a hand actually says. The glyphs live HERE rather
// than in `uiart` for one reason: a face button is a letter, and this file is the ONLY path to draw text.

pub const PadBtn = enum { a, b, x, y };
/// Which way a D-pad prompt points; the paired ones light two arms for a "move" or "adjust" line.
pub const Dir = enum { up, down, left, right, leftright, updown };

/// What a hint's picture IS. A `bumper` carries its own label (L1/R2/R3…), which is what makes one pill do
/// for every shoulder and stick press without six near-identical drawers.
pub const Glyph = union(enum) {
    face: PadBtn,
    dpad: Dir,
    bumper: [:0]const u8,
    /// The Start/Select pictogram — three bars on a pill, since the physical button carries no letter.
    menu: void,
};

/// One "[picture] what it does" prompt. The picture is the button; the label is plain English and never
/// names a key.
pub const Hint = struct { glyph: Glyph, label: [:0]const u8 };

/// THE BUTTONS THE GAME ACTUALLY BINDS, named once so a caption and the press cannot drift. `game.zig` reads
/// these for its own bindings, and every crib in the UI draws them.
pub const BTN_INTERACT: PadBtn = .y;
pub const BTN_CONFIRM: PadBtn = .a;
/// …and A AGAIN, in the WORLD (ER's own). Not a clash: every screen that takes Confirm — the menus, the book,
/// a conversation, a bonfire — holds the world still while it is up, so the two can never be asked at once.
/// Named apart from `BTN_CONFIRM` because they are two bindings that happen to agree, and a rebind of one is
/// not a rebind of the other.
pub const BTN_JUMP: PadBtn = .a;
pub const BTN_BACK: PadBtn = .b;
pub const BTN_QUICK: PadBtn = .x;

/// …AND THE PRESS ITSELF COMES OFF THE SAME NAME, which is what makes "a button is named once" true rather than
/// merely written down. Every site held its own copy of a binding beside the letter drawn for it — the interact
/// press, both halves of Confirm, Back, and the roll/sprint B in `game.gatherMove` and the input queue — so a
/// rebind moved the press and left every crib in the game drawing the old letter.
/// raylib names a face button by its POSITION, which is where the Xbox letters this UI draws happen to sit.
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
        .a => rgba(94, 178, 66, 255), // green
        .b => rgba(214, 62, 52, 255), // red
        .x => rgba(46, 120, 205, 255), // blue
        .y => rgba(234, 190, 58, 255), // amber
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

/// The iron a pad pictogram is cast in — a hair warmer than `uiart.IRON`, so the controller glyphs recolour
/// together rather than one at a time.
const PAD_BODY = rgba(27, 23, 19, 255);
const PAD_INK = rgba(226, 210, 180, 245);

/// A short label centred ON a point rather than laid off its top-left — the glyphs are round and the text is
/// not, so every one of them wants the same correction and gets it here.
fn glyphLabel(s: [:0]const u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
    const w = textW(s, size);
    const y = cy - @divTrunc(size * 62, 100);
    drawStr(s, cx - @divTrunc(w, 2) + 1, y + 1, size, rgba(0, 0, 0, 150));
    drawStr(s, cx - @divTrunc(w, 2), y, size, col);
}

/// A ROUND FACE BUTTON: a dark raised dome, a ring in the button's own colour, and the letter in it. The
/// COLOUR names the button; the body stays in the chrome's palette, because a full coloured disc reads as
/// modern plastic against gilt and stone.
pub fn padFace(cx: i32, cy: i32, r: i32, b: PadBtn) void {
    const col = padBtnColor(b);
    const rf: f32 = @floatFromInt(r);
    const cv = rl.Vector2{ .x = @floatFromInt(cx), .y = @floatFromInt(cy) };
    rl.drawCircleV(cv, rf + 1.5, mathx.withAlpha(uiart.INK, 235)); // the seat
    rl.drawCircleV(cv, rf, PAD_BODY);
    rl.drawCircleV(.{ .x = cv.x, .y = cv.y - rf * 0.16 }, rf * 0.80, rgba(40, 34, 28, 255)); // the dome
    rl.drawCircleLines(cx, cy, rf - 1.0, mathx.withAlpha(col, 245));
    rl.drawCircleLines(cx, cy, rf - 2.2, mathx.withAlpha(col, 150));
    glyphLabel(padBtnLetter(b), cx, cy, @max(@divTrunc(r * 5, 4), 11), mathx.lerpColor(col, rl.Color.white, 0.38));
}

/// THE D-PAD as a rounded iron tile with four chevrons: the direction being asked for burns gilt and the rest
/// stay dim. A tile reads cleaner than a cross at crib sizes, and the dim arms are what say it is a D-pad.
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

/// The dark rounded pill the shoulder and menu pictograms share.
fn padPill(r: rl.Rectangle) void {
    rl.drawRectangleRounded(r, 0.6, 6, rgba(34, 29, 24, 235));
    rl.drawRectangleRoundedLinesEx(r, 0.6, 6, 1, mathx.withAlpha(uiart.GILT_DIM, 160));
}

const PAD_GLYPH_TEXT: i32 = 12;
const PAD_MENU_W: i32 = 24;
/// Measured, not guessed: the layout pass and the drawer read the SAME width, or the column a crib reserves
/// and the pill it paints drift apart on the first label anybody lengthens.
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

/// A shoulder or stick press, sized to its own label: L1, R2, R3 and the rest are one pill and one drawer.
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

/// The radius every crib draws its glyphs at, and the two gaps that lay a row out. One set, so the menu's
/// footer, the book's and the dialog panel's are the same strip at the same rhythm.
pub const GLYPH_R: i32 = 9;
const GLYPH_GAP: i32 = 7; // picture → its own label
const HINT_PAD: i32 = 24; // one hint → the next

/// How wide a row of hints comes out — the measure the centring and the plate-fitting both read.
pub fn hintRowW(hints: []const Hint, size: i32) i32 {
    var total: i32 = 0;
    for (hints, 0..) |h, i| {
        total += glyphW(h.glyph, GLYPH_R) + GLYPH_GAP + textW(h.label, size);
        if (i + 1 < hints.len) total += HINT_PAD;
    }
    return total;
}

/// A row of prompts laid left to right, VERTICALLY CENTRED on `cy` — the glyphs are round and the text is
/// not, so a row hung off a top edge always sits a pixel or two out of true.
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

/// …and the same row centred on the screen, with the chrome's own diamond termini stitching it closed.
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
/// THE WORLD CLOCK'S DIAL, and the ONLY thing on this side of the HUD that is not about him — so it sits
/// OUTSIDE the three bars rather than under them, and the bars step right to make room (`BARS_X`).
const DIAL_R: i32 = 21;
const DIAL_GAP: i32 = 14;
/// …and where the bars now start. Held as its own name because `MARGIN` is still the screen's edge and four
/// other things measure off it — the soul plate, the banner and the debug corner among them.
const BARS_X: i32 = MARGIN + DIAL_R * 2 + DIAL_GAP;
const HP_W: i32 = 268;
const HP_H: i32 = 15;
const FP_W: i32 = 182;
const FP_H: i32 = 11;
const ST_W: i32 = 232;
const ST_H: i32 = 11;

const TRACK = rgba(16, 13, 11, 186); // the empty channel behind every fill
/// The tarnished-metal rim, one tone at whatever alpha the surface wants — the bars' hairline and the
/// soul plate's edge were two names for the same three channels.
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
/// THE STATUS METER, and it has TWO faces off ONE number: a sickly violet while it FILLS (a threat), and a
/// hot toxic YELLOW once it has GONE OFF (a thing happening to you). Filling and poisoned must not read as
/// the same bar at different lengths — that is the one thing this meter cannot afford, since the number
/// itself means opposite things either side of the proc.
///
/// AND THE ACTIVE FACE IS NOT GREEN, though poison green is the genre's own: it sits DIRECTLY UNDER the
/// stamina bar, and measured off the first pass (108,150,44 against stamina's 112,136,58) the two were the
/// same bar. Separated on HUE *and* VALUE — yellow, and much lighter than the olive above it.
const PSN_HI = rgba(96, 62, 118, 255);
const PSN_LO = rgba(52, 32, 66, 255);
const PSN_TP = rgba(146, 106, 172, 255);
const PSN_ON_HI = rgba(196, 202, 44, 255);
const PSN_ON_LO = rgba(112, 112, 16, 255);
const PSN_ON_TP = rgba(232, 240, 132, 255);
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

/// A STATUS METER: how full, and whether it has already gone off. `frac` means both things (see
/// `combat.Status`), so the flag is the only thing that says which — and it is what picks the colour.
pub const Status = struct { frac: f32 = 0, on: bool = false };

/// THE STATUS BAR, and it is only there when it has something to say — an empty meter draws NOTHING. A row
/// of dead track under the stamina bar is chrome the player learns to stop reading, and this is a bar that
/// has to be noticed the first frame it moves.
const PSN_W: i32 = 196; // narrower than stamina: it is not one of the three
const PSN_H: i32 = 9;
fn statusBar(x: i32, y: i32, s: Status) void {
    if (s.frac <= 0.001) return;
    if (s.on) {
        bar(x, y, PSN_W, PSN_H, s.frac, 0, PSN_ON_HI, PSN_ON_LO, PSN_ON_TP);
        return;
    }
    bar(x, y, PSN_W, PSN_H, s.frac, 0, PSN_HI, PSN_LO, PSN_TP);
}

// ── THE LIVE PORTRAIT ───────────────────────────────────────────────────────────────────────────────────
//
// The actual rig, rendered off-screen into a target and blitted into a UI box — `book.zig`'s paper-doll
// trick, and it lives HERE because there are three callers now (the book's doll, the conversation panel's
// speaker, the spirit toast) and three copies of a camera-and-target is three things to retune separately.
// It is the real model in the real pose, so no picture in this game can go stale.
//
// ONE TARGET, sized to the LARGEST use and scaled down for the rest: a render target is video memory and
// the two smaller callers are the same head with fewer pixels round it.

const PORT_RT_W: i32 = 320;
const PORT_RT_H: i32 = 360;
var portRT: ?rl.RenderTexture2D = null;

// HOW A FACE IS FRAMED, and it lives with the renderer rather than with any one SUBJECT. It was the
// wanderer's (`npc.PORTRAIT_*`) while he was the only thing photographed; the spirit panel then read the
// wanderer's constants to frame a WOLF, which is a creature's house style governing another creature.
// The ANGLE is the house's and belongs here; the DISTANCE is the subject's and stays with the subject
// (`npc.PORTRAIT_DIST`, `wolf.PORTRAIT_DIST`), because a wolf's muzzle and a man's face want different room.
/// Degrees off the subject's own front. Three-quarters: enough to give the head a near side and a far side —
/// dead on, a low-poly head with no shading break in it reads as a passport photo.
pub const PORTRAIT_YAW: f32 = 34.0;
/// A shade above the eye line, looking down — the one that reads as a portrait and not as a camera on the floor.
pub const PORTRAIT_PITCH: f32 = 0.05;
pub const PORTRAIT_FOV: f32 = 34.0;

/// Called on the way out of the program, beside `book.unload` and `menu.unload`.
pub fn unloadPortrait() void {
    if (portRT) |t| rl.unloadRenderTexture(t);
    portRT = null;
}

/// WHAT IT TAKES TO PHOTOGRAPH A BODY: the scene to draw it through, the point to frame on, where the camera
/// stands relative to that point, and how to draw the thing. `drawFn` is a callback so this file never has to
/// know what a wanderer or a wolf is — the same reason `dialog.zig` does not import one.
pub const LivePortrait = struct {
    scene: *gfx.Scene,
    /// The FACE, off a posed bone — never a height above the feet, or the picture drifts the moment it moves.
    focus: rl.Vector3,
    /// WORLD yaw the camera stands at around `focus`, and it is the caller's because only the caller knows
    /// which way the subject is pointing (`npc.PORTRAIT_YAW` is hung off the speaker's own facing).
    yaw: f32,
    pitch: f32,
    dist: f32,
    fov: f32 = 34.0,
    ctx: *const anyopaque,
    drawFn: *const fn (*const anyopaque) void,
};

/// **TAKING THE PICTURE AND MOUNTING IT ARE TWO CALLS, AND THE SPLIT IS LOAD-BEARING.** `endTextureMode`
/// restores the DEFAULT framebuffer — not whatever target was bound before it — so a render nested inside
/// another target silently redirects the whole rest of the frame at the backbuffer, which is then
/// overwritten by the outer target's own blit. The chrome fade (`beginChrome`) is exactly such a target and
/// the spirit toast is drawn inside it, so the toast RENDERS before the chrome opens and only BLITS within.
/// `dialog.zig` draws outside any target and may use `livePortrait`, which is simply the two in order.
///
/// Returns false when the target could not be made, so a caller can leave the frame bare rather than mount
/// a stale picture.
///
/// **IT IS RE-TAKEN EVERY FRAME AND THAT IS MEASURED, NOT ASSUMED.** One target switch, one shader bind and
/// the subject's own meshes — 27 for the wolf, 18 for a wanderer — against a world frame that runs a full
/// shadow pass over hundreds. Well under a percent, and only while a panel is actually up. A refresh clock
/// was considered and REFUSED: the target is shared, so a throttle has to carry a subject tag to avoid
/// mounting the wrong face, and the `--shot` harness steps the sim faster than any wall-clock gate, which
/// would photograph a stale pose. Not worth either for 27 draw calls.
pub fn renderPortrait(p: LivePortrait) bool {
    if (portRT == null) portRT = rl.loadRenderTexture(PORT_RT_W, PORT_RT_H) catch null;
    const rt = portRT orelse return false;
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
    rl.clearBackground(rgba(13, 12, 11, 255));
    rl.beginMode3D(cam);
    p.scene.bind(cam.position);
    p.scene.shadowsOff();
    p.scene.setLights(&.{});
    p.scene.setGround(false);
    p.drawFn(p.ctx);
    rl.endMode3D();
    rl.endTextureMode();
    return true;
}

/// Mount what `renderPortrait` last took. Safe inside any target — it is one textured quad.
pub fn blitPortrait(dst: rl.Rectangle, tint: rl.Color) void {
    const rt = portRT orelse return;
    // NEGATIVE HEIGHT: a render target is bottom-up, and blitted straight it is an upside-down head.
    rl.drawTexturePro(
        rt.texture,
        .{ .x = 0, .y = 0, .width = @floatFromInt(PORT_RT_W), .height = -@as(f32, @floatFromInt(PORT_RT_H)) },
        dst,
        .{ .x = 0, .y = 0 },
        0,
        tint,
    );
}

/// Both in order — for callers that are NOT inside a render target (the conversation panel).
pub fn livePortrait(p: LivePortrait, dst: rl.Rectangle, tint: rl.Color) void {
    if (renderPortrait(p)) blitPortrait(dst, tint);
}

// ── THE SPIRIT PANEL ────────────────────────────────────────────────────────────────────────────────────
//
// **WHAT IS STANDING WITH YOU, UNDER WHAT IS KEEPING YOU ALIVE** (owner: their portrait and HP below your
// HP). It is not a slot and not part of the cross: the cross is the four things the pad's directions do,
// and a companion is not something you press.
//
// **IT IS NOT A TOAST AND HAS NO TIMER** (owner, in as many words: it should stay on screen as long as they
// are alive). It is shaped like one — a face, a name and a life, sliding in under his own bars — but what
// takes it off is the BODY going, never a clock. `k` fades it at both ends and nothing else moves it.

const SP_FACE: i32 = 52; // the portrait square…
const SP_BAR_H: i32 = 9; // …and its life, the status meter's own height so the stack reads as one column
const SP_GAP: i32 = 6;
const SP_TOP: i32 = 12; // clear of the status meter above it
const SP_SLIDE: f32 = 14.0; // px it rises through on the way in — it ARRIVES, it does not appear
/// The spirit's own colour: the pale blue everything summoned is thinned to (`wolf.SPIRIT_FADE`), so the bar
/// and the body it belongs to are obviously the same thing.
const SP_LIFE_HI = rgba(150, 200, 226, 255);
const SP_LIFE_LO = rgba(58, 92, 116, 255);
const SP_LIFE_TP = rgba(206, 234, 248, 255);

/// Where the bars finish, the status meter included — DERIVED, so retuning any bar's height carries the
/// toast under it instead of leaving it overlapping or floating.
const BARS_BOTTOM: i32 = BAR_TOP + BARS_H + BAR_GAP + 2 + PSN_H;

/// `k` is the fade, 0..1 — held by the game because the spirit's body is gone before the toast has finished
/// leaving, and a panel that reads its own subject cannot outlive it.
///
/// `hasFace` says whether `renderPortrait` was run for it THIS frame, before the chrome target opened. The
/// picture is only blitted here, never taken (see `renderPortrait`).
pub fn spiritPanel(hasFace: bool, name: [:0]const u8, hp: f32, k: f32) void {
    if (k <= 0.004) return;
    const kk = mathx.clampF(k, 0, 1);
    const a: u8 = @intFromFloat(255.0 * kk);
    const lift: i32 = @intFromFloat((1.0 - kk) * SP_SLIDE);
    const x = BARS_X;
    const y = BARS_BOTTOM + SP_TOP + lift;
    const dst = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(SP_FACE),
        .height = @floatFromInt(SP_FACE),
    };
    // THE FRAME FOLLOWS THE FACE. On the way out the body is gone, so there is no picture to take and the
    // shared target holds whoever was photographed last — an empty well, or worse a wanderer's head in the
    // spirit's box. So the mount is drawn only while there is something to mount, and what fades is the
    // NAME and the LIFE, which is the part that was ever about the animal rather than of it.
    const tx = if (hasFace) x + SP_FACE + SP_GAP else x;
    const tw = if (hasFace) HP_W - SP_FACE - SP_GAP else HP_W;
    if (hasFace) {
        uiart.well(x, y, SP_FACE, SP_FACE, a);
        blitPortrait(dst, mathx.withAlpha(rl.Color.white, a));
        rl.drawRectangleLinesEx(dst, 1, mathx.withAlpha(uiart.GILT_DIM, @min(a, 110)));
    }
    text(name, tx, y + 2, TINY, mathx.withAlpha(uiart.GILT, a));
    const by = y + SP_FACE - SP_BAR_H;
    bar(tx, by, tw, SP_BAR_H, mathx.clampF(hp, 0, 1), 0, SP_LIFE_HI, SP_LIFE_LO, SP_LIFE_TP);
}

pub fn vitals(dt: f32, hp: f32, fp: f32, stam: f32, stamRefused: f32, fpRefused: f32, windedTo: f32, psn: Status) void {
    if (hp > chip) {
        chip = hp; // healing (and a respawn) snaps it — never strand a trail across the bar
        chipHold = 0;
    } else {
        if (hp < chipLast - 1e-4) chipHold = CHIP_HOLD; // a fresh wound re-arms the hang
        if (chipHold > 0) chipHold -= dt else chip = mathx.maxF(hp, chip - CHIP_RATE * dt);
    }
    chipLast = hp;
    var y = BAR_TOP;
    bar(BARS_X, y, HP_W, HP_H, hp, chip, HP_HI, HP_LO, HP_TP);
    y += HP_H + BAR_GAP;
    bar(BARS_X, y, FP_W, FP_H, fp, 0, FP_HI, FP_LO, FP_TP);
    refuseRing(BARS_X, y, FP_W, FP_H, fpRefused); // a cast the pool could not cover
    y += FP_H + BAR_GAP;
    bar(BARS_X, y, ST_W, ST_H, stam, 0, ST_HI, ST_LO, ST_TP);
    if (windedTo > 0.001) {
        const wf: f32 = @floatFromInt(ST_W);
        const owed: i32 = @intFromFloat(wf * mathx.clampF(windedTo, 0, 1));
        const fill: i32 = @intFromFloat(wf * mathx.clampF(stam, 0, 1));
        if (owed > fill) rl.drawRectangle(BARS_X + fill, y, owed - fill, ST_H, mathx.withAlpha(WARN, 46));
        rl.drawRectangle(BARS_X + owed - 1, y - 1, 2, ST_H + 2, mathx.withAlpha(WARN_LT, 210)); // the threshold
    }
    refuseRing(BARS_X, y, ST_W, ST_H, stamRefused);
    // …and the status meter UNDER the three, because it is not one of them: the bars above are what he
    // spends, this is what is being done to him.
    y += ST_H + BAR_GAP + 2;
    statusBar(BARS_X, y, psn);
}

/// How tall the three bars stand together — what the dial beside them is centred on, DERIVED rather than
/// guessed, so a retune of any bar's height carries the dial with it.
const BARS_H: i32 = HP_H + BAR_GAP + FP_H + BAR_GAP + ST_H;

const DIAL_SKY = rgba(74, 104, 148, 210); // the lit half of the face…
const DIAL_SKY_NIGHT = rgba(28, 36, 60, 214);
const DIAL_GROUND = rgba(20, 17, 14, 214); // …and the earth under the horizon, whatever hour it is
const SUN_COL = rgba(244, 206, 118, 255);
const MOON_COL = rgba(206, 216, 234, 255);

/// THE WORLD CLOCK, drawn as the thing it actually is: a horizon, and the key light travelling across it left to
/// right. The hour is the ONLY input and every shape here comes off `daynight`'s own arithmetic (`spanU`,
/// `isDay`, `dayAmt`), so the dial cannot tell a different time than the sun the scene is lit by.
///
/// **THE MARKER IS WHATEVER IS CASTING** — the sun while it is up and the moon once it is not, which is
/// `daynight.keyDir`'s own split. One body on the face rather than two, because at this size two would be two
/// dots nobody could tell apart, and the one that matters is the one making the shadows.
pub fn dayDial(hour: f32) void {
    const cx = MARGIN + DIAL_R;
    const cy = BAR_TOP + @divTrunc(BARS_H, 2);
    const r: f32 = @floatFromInt(DIAL_R);
    const fx: f32 = @floatFromInt(cx);
    const fy: f32 = @floatFromInt(cy);
    const day = daynight.isDay(hour);

    rl.drawCircle(cx, cy, r + 2, rgba(0, 0, 0, 60)); // the bars' own soft seat, on a round thing
    rl.drawCircle(cx, cy, r, DIAL_GROUND);
    // THE SKY IS THE TOP HALF, cut with a SCISSOR rather than a circle sector: raylib's sector sweeps in screen
    // space and the angle convention is one more thing to get backwards, where a clipped rectangle is not.
    rl.beginScissorMode(cx - DIAL_R, cy - DIAL_R, DIAL_R * 2, DIAL_R);
    rl.drawCircle(cx, cy, r, if (day) DIAL_SKY else DIAL_SKY_NIGHT);
    rl.endScissorMode();
    // …and how BRIGHT that sky is follows the daylight itself, so dawn and noon are not the same picture.
    if (day) {
        const k: u8 = @intFromFloat(90.0 * daynight.dayAmt(hour));
        rl.beginScissorMode(cx - DIAL_R, cy - DIAL_R, DIAL_R * 2, DIAL_R);
        rl.drawCircle(cx, cy, r, mathx.withAlpha(rgba(150, 190, 236, 255), k));
        rl.endScissorMode();
    }
    rl.drawLineEx(.{ .x = fx - r, .y = fy }, .{ .x = fx + r, .y = fy }, 1.6, mathx.withAlpha(RIM, 220));
    rl.drawCircleLines(cx, cy, r, FRAME);

    // THE BODY, on the arc: 0 through its span is the horizon it rose over and 1 the one it is setting behind,
    // which is east on the left and west on the right — the same sweep for the moon, since it is the anti-sun.
    const a = std.math.pi * (1.0 - daynight.spanU(hour));
    const rr = r - 5.5;
    const mx = fx + mathx.cosf(a) * rr;
    const my = fy - mathx.sinf(a) * rr;
    const col = if (day) SUN_COL else MOON_COL;
    rl.drawCircleV(.{ .x = mx, .y = my }, 6.5, mathx.withAlpha(col, 70)); // the halo…
    rl.drawCircleV(.{ .x = mx, .y = my }, 3.6, col);
    if (!day) {
        // …and the moon is bitten into a crescent by the face behind it, which is the cheapest thing that stops
        // a pale dot reading as a dim sun.
        rl.drawCircleV(.{ .x = mx + 2.2, .y = my - 1.4 }, 2.9, DIAL_SKY_NIGHT);
    }

    // THE READOUT UNDER IT. A dial says where in the day you are and this says which day-hour that is; the pair
    // is what makes "has the clock moved" a question you can answer at a glance.
    var buf: [8]u8 = undefined;
    const s = daynight.clockTextZ(hour, &buf);
    text(s, cx - @divTrunc(textW(s, TINY), 2), cy + DIAL_R + 3, TINY, mathx.withAlpha(uiart.GILT_DIM, 236));
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
const CHILL_STRIP = rgba(148, 202, 232, 235); // the rime hold's own row — cold, against the bar's warm red
/// A BAR MAY NOT CLIMB OUT OF THE FRAME. Over the head is right at every distance you can see the whole
/// creature at, and wrong the moment you close on a TALL one: the ogre's crown is 4.4 m up, so through the
/// whole fight you are near enough to need the bar it is drawn off the top of the screen, gold rim and all.
///
/// So the bar has a CEILING in screen space, three quarters of the way up: far off it rides the head exactly
/// as before, and walking in it stops climbing and hangs against the body. ONE rule for every creature.
const FOE_CEIL: f32 = 0.25; // …measured from the TOP, so 0.25 is three quarters up

pub fn foeBar(sx: f32, sy: f32, frac: f32, staggered: bool, chill: f32) void {
    const wf: f32 = @floatFromInt(FOE_W);
    const x: i32 = @intFromFloat(sx - wf * 0.5);
    const ceiling = @as(f32, @floatFromInt(rl.getScreenHeight())) * FOE_CEIL;
    const y: i32 = @intFromFloat(mathx.maxF(sy - @as(f32, @floatFromInt(FOE_LIFT)), ceiling));
    rl.drawRectangle(x - 2, y - 2, FOE_W + 4, FOE_H + 4, rgba(0, 0, 0, 90)); // a soft seat
    rl.drawRectangle(x - 1, y - 1, FOE_W + 2, FOE_H + 2, rgba(0, 0, 0, 170)); // backing
    rl.drawRectangle(x, y, FOE_W, FOE_H, FOE_TRACK);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    // 5 px tall, so the shade band is 2 rather than the vitals bars' third and the tip is a single column.
    fillThree(x, y, fw, FOE_H, frac, HP_HI, HP_LO, mathx.withAlpha(HP_TP, 200), 2, 1, 120);
    // THE COLD ON IT, under the health: a rime strip draining with the hold (`combat.Chill.frac`). Its own
    // row rather than a tint on the fill — a tint on a red bar at 54 px is a hue nobody can name.
    if (chill > 0.001) {
        const cw: i32 = @intFromFloat(wf * mathx.clampF(chill, 0, 1));
        rl.drawRectangle(x, y + FOE_H + 1, cw, 2, CHILL_STRIP);
    }
    if (staggered) rl.drawRectangleLines(x - 1, y - 1, FOE_W + 2, FOE_H + 2, STAGGER_RIM);
}
// ── THE BOSS BAR — the one creature on a field big enough to own the bottom of the screen ────────────────
const BOSS_H: i32 = 13;
/// Clear of the prompt band (`PROMPT_LIFT`) and the corners' furniture — ER's own register: the boss's
/// name and health lie across the bottom, under the fight and over the chrome.
const BOSS_LIFT: i32 = 158;
var bossChip: f32 = 0;
var bossHold: f32 = 0;
var bossLast: f32 = 0;

/// THE BOSS'S OWN BAR: bottom-centre, NAMED, with the vitals bars' recent-damage trail and the same gold
/// stagger rim the floating bars wear — the punish cue, finally somewhere the eye already is. `k` fades the
/// whole plate in and out as the fight starts and ends; the caller owns that clock (and suppresses the
/// floating bar over the same body, or one number is read twice).
pub fn bossBar(dt: f32, name: [:0]const u8, frac: f32, staggered: bool, k: f32) void {
    if (k <= 0.001) {
        bossChip = frac; // parked: a fight that ended does not leave a trail armed for the next one
        bossLast = frac;
        return;
    }
    const w: i32 = @min(760, @divTrunc(rl.getScreenWidth() * 62, 100));
    const x = @divTrunc(rl.getScreenWidth() - w, 2);
    const y = rl.getScreenHeight() - BOSS_LIFT;
    if (frac > bossChip) {
        bossChip = frac;
        bossHold = 0;
    } else {
        if (frac < bossLast - 1e-4) bossHold = CHIP_HOLD;
        if (bossHold > 0) bossHold -= dt else bossChip = mathx.maxF(frac, bossChip - CHIP_RATE * dt);
    }
    bossLast = frac;
    const a = mathx.clampF(k, 0, 1);
    const au8 = struct {
        fn of(base: u16, kk: f32) u8 {
            return @intFromFloat(@as(f32, @floatFromInt(base)) * kk);
        }
    }.of;
    // The seat, the frame and the track — the vitals bars' chrome at the boss's width.
    rl.drawRectangle(x - 3, y - 3, w + 6, BOSS_H + 6, rgba(0, 0, 0, au8(60, a)));
    rl.drawRectangle(x - 2, y - 2, w + 4, BOSS_H + 4, rgba(0, 0, 0, au8(165, a)));
    rl.drawRectangle(x - 1, y - 1, w + 2, BOSS_H + 2, mathx.withAlpha(RIM, au8(210, a)));
    rl.drawRectangle(x - 1, y - 1, w + 2, 1, mathx.withAlpha(uiart.GILT, au8(130, a)));
    rl.drawRectangle(x - 1, y + BOSS_H, w + 2, 1, rgba(0, 0, 0, au8(140, a)));
    rl.drawRectangle(x, y, w, BOSS_H, mathx.withAlpha(TRACK, au8(186, a)));
    const wf: f32 = @floatFromInt(w);
    const fw: i32 = @intFromFloat(wf * mathx.clampF(frac, 0, 1));
    const cw: i32 = @intFromFloat(wf * mathx.clampF(bossChip, 0, 1));
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
    // THE STAGGER RIM IS THE PUNISH CUE (ER's gold), on the bar the eye is actually reading.
    if (staggered) {
        rl.drawRectangleLines(x - 1, y - 1, w + 2, BOSS_H + 2, mathx.withAlpha(STAGGER_RIM, au8(255, a)));
        rl.drawRectangleLines(x - 2, y - 2, w + 4, BOSS_H + 4, mathx.withAlpha(STAGGER_RIM, au8(130, a)));
    }
    // …and the NAME, above the bar's left end: a boss is somebody.
    engraved(name, x, y - lineH(SMALL) - 3, SMALL, rgba(230, 218, 190, au8(244, a)));
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
    rl.drawRectangle(x - 2, y - 2, SOUL_W + 4, SOUL_H + 4, rgba(0, 0, 0, 128)); // the hard black seat
    uiart.plate(x, y, SOUL_W, SOUL_H, SOUL_FILL_A);
    rl.drawRectangleLines(x, y, SOUL_W, SOUL_H, mathx.withAlpha(RIM, 186));
    rl.drawRectangle(x + 1, y + 1, SOUL_W - 2, 1, mathx.withAlpha(uiart.GILT, 90)); // lit top rim
    uiart.cornerJewels(x + 1, y + 1, SOUL_W - 2, SOUL_H - 2, 2.0, mathx.withAlpha(uiart.GILT_DIM, 200));
    uiart.diamond(@floatFromInt(x + 12), @floatFromInt(y + @divTrunc(SOUL_H, 2)), 2.8, mathx.withAlpha(uiart.GILT_DIM, 220));
    text(s, x + SOUL_W - textW(s, BODY) - 11, y + @divTrunc(SOUL_H - lineH(BODY), 2) + 1, BODY, SOUL_TEXT);
}

const PROMPT_LIFT: i32 = 76;

/// WHAT THE BUTTON IN REACH WOULD DO — the picture of the button, then the verb. The band is measured off
/// BOTH, so a longer verb or a wider glyph moves the plate rather than spilling off it.
pub fn prompt(h: Hint) void {
    const gw = glyphW(h.glyph, GLYPH_R);
    const w = gw + GLYPH_GAP + textW(h.label, BODY);
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
    drawGlyph(h.glyph, x + @divTrunc(gw, 2), by + @divTrunc(bh, 2), GLYPH_R);
    text(h.label, x + gw + GLYPH_GAP, y, BODY, rgba(226, 214, 186, 240));
}

/// Where a trigger's line sits: high on the screen, clear of the prompt band and of everything in the four
/// corners. SC1 put its text message top-left; centred reads as narration rather than as a debug log.
const BANNER_TOP: i32 = 96;
const BANNER_ROWS: usize = 3;
const BANNER_WIDE: i32 = 620;

/// A LINE THE WORLD IS SAYING, not a thing you can answer — no frame, no plate, just words with a shadow
/// under them, so it never reads as a panel you have missed a button on. Wrapped with the real face, since a
/// script's sentence is written to be read and not to fit.
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

const EQ_SCALE: i32 = 150; // percent
fn eq(v: i32) i32 {
    return @divTrunc(v * EQ_SCALE, 100);
}
const SLOT_W: i32 = eq(44);
const SLOT_H: i32 = eq(60);
const SLOT_GAP: i32 = eq(8); // between the LEFT/RIGHT arms and the centre column
const PITCH_Y: i32 = eq(48);
const BOTTOM: i32 = 26;

/// WHAT A HAND OR THE SORCERY CELL IS SHOWING. The cross`s DOWN cell is NOT here: it holds an `item.Kind`
/// off the quick bar (`quickSlot`), which is a wider thing than the handful his hands can be doing.
pub const Slot = enum { empty, sword, bow, bell, shield, wand, spell, roots, rime };

/// `left`/`right` are what is IN HIS HANDS this frame, not what he owns.
/// `up` is the SORCERY slot, and `castable` is whether the pool would cover one — it stays `.empty` while
/// nothing he is holding could cast, because an empty ER slot is a real part of this HUD.
/// DOWN is whatever the QUICK BAR is turned to (`combat.Quick`) and how many of it are left — the cross is
/// where ER shows both, and a count you have to open a menu for is a count you play without.
pub fn equipment(left_hand: Slot, right_hand: Slot, up: Slot, castable: bool, quick: ?item.Kind, charges: u8, ammo: ?Ammo) void {
    const stepX = SLOT_W + SLOT_GAP;
    const left = MARGIN;
    const bottom = rl.getScreenHeight() - BOTTOM;
    const midX = left + stepX; // the centre cell of the three
    const midY = bottom - SLOT_H - PITCH_Y;
    slot(midX, midY - PITCH_Y, up, if (castable) 1 else 0); // UP — sorcery/incantation
    slot(left, midY, left_hand, 0); // LEFT — left hand: the shield, or nothing behind a bow
    slot(midX + stepX, midY, right_hand, 0); // RIGHT — right hand: the sword or the bow
    quickSlot(midX, midY + PITCH_Y, quick, charges); // DOWN — whatever is up on the quick bar
    if (ammo) |n| ammoBox(midX + stepX, midY + SLOT_H + AMMO_GAP, n);
}

/// THE CROSS'S DOWN CELL. Its own function and not a `Slot`, because unlike the other three it holds an
/// `item.Kind` off the bar rather than one of a fixed handful of things his hands can be doing.
fn quickSlot(x: i32, y: i32, k: ?item.Kind, n: u8) void {
    uiart.slot(x, y, SLOT_W, SLOT_H, k != null);
    const kind = k orelse return; // a bar with nothing on it is an empty socket, and no tally under it
    const cx: f32 = @floatFromInt(x + @divTrunc(SLOT_W, 2));
    const cy: f32 = @floatFromInt(y + @divTrunc(SLOT_H, 2));
    itemart.drawHeld(kind, cx, cy, @floatFromInt(ICON), n > 0);
    var buf: [8]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch return;
    tally(s, x + SLOT_W, y + SLOT_H + 6, HINT, if (n > 0) TALLY_OK else TALLY_DRY);
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

fn slot(x: i32, y: i32, holds: Slot, charges: u8) void {
    uiart.slot(x, y, SLOT_W, SLOT_H, holds != .empty);
    const cx: f32 = @floatFromInt(x + @divTrunc(SLOT_W, 2));
    const cy: f32 = @floatFromInt(y + @divTrunc(SLOT_H, 2));
    const px: f32 = @floatFromInt(ICON);
    switch (holds) {
        .empty => {},
        .sword => itemart.sword(cx, cy, px),
        .bow => itemart.bow(cx, cy, px),
        .bell => itemart.bell(cx, cy, px),
        .shield => itemart.shield(cx, cy, px),
        .wand => itemart.wand(cx, cy, px),
        // The sorcery slot's picture greys out when the FP will not cover a cast, which is the ammo box's
        // own rule: a thing you cannot use has to LOOK like a thing you cannot use.
        .spell => itemart.spell(cx, cy, px, charges > 0),
        // …and the rod's other sorcery, greyed by the same rule: a thing you cannot afford has to LOOK it.
        .roots => itemart.roots(cx, cy, px, charges > 0),
        // …and the third, on the same rule. The CONE is what the picture has to carry: it is the one spell
        // that is a direction and a width rather than a mark thrown at somebody.
        .rime => itemart.rime(cx, cy, px, charges > 0),
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

/// …and the same wrap measured in the MONO face, for the editor's own chrome (`ui.drawTip`). Its own entry
/// point rather than a flag, because which font a string will be DRAWN in is not something a wrap may guess.
pub fn wrapMono(s: []const u8, size: i32, maxW: i32, buf: []u8, lines: [][:0]const u8) [][:0]const u8 {
    return wrapBy(monoW, s, size, maxW, buf, lines);
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

