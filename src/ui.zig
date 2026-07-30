const std = @import("std");
const rl = @import("raylib");
const hud = @import("hud.zig");
const mathx = @import("mathx.zig");
const icons = @import("icons.zig");

pub const Icon = icons.Icon;

const rgba = mathx.rgba;

// UI — a tiny immediate-mode widget kit for the editor: each widget hit-tests AND draws in one call.
// `Ctx.anyHot` accumulates "the pointer is over some widget this frame" and the editor gates world clicks
// on it NEXT frame, since a one-frame lag is imperceptible and the alternative is splitting every widget
// into a layout pass and an interaction pass.
//
// Text goes through hud.mono/monoW, NOT the game's Balthazar: an editor is columns of numbers, and a
// proportional face shoves a row about every time a value grows a digit. The chrome draws with the retro
// pass BYPASSED, so these colours are LITERAL screen values and the author-dark rule does not apply.

pub const MSG_CAP = 120; // shared cap for short UI strings (tips, toasts, prompts)

/// POINTER TRAVEL that separates a CLICK from a DRAG, in pixels. One number for every gesture in the
/// editor that has to tell those apart — the map's right button (context menu vs. orbit) and the object
/// viewer's left button (open vs. spin). It was a bare `4.0` in both files: two thresholds meant to feel
/// identical, written down twice, eventually stop being identical.
pub const DRAG_PX: f32 = 4.0;

// ── palette ── iron and brass, so the chrome sits against the golden-hour world without
// competing with it. Kept here rather than at call sites: one place to retune the whole editor.
pub const INK = rgba(10, 9, 8, 232);
pub const PANEL_FILL = rgba(16, 15, 13, 235);
pub const TRIM = rgba(146, 124, 82, 255);
pub const LABEL = rgba(150, 146, 138, 255);
pub const VALUE = rgba(228, 216, 194, 255);
pub const TITLE = rgba(236, 226, 202, 255);
pub const HOT = rgba(236, 210, 150, 255);
pub const ACTIVE_FILL = rgba(96, 74, 40, 235);
pub const IDLE_FILL = rgba(26, 22, 18, 228);
pub const HOVER_FILL = rgba(42, 34, 26, 235);

pub fn alpha(c: rl.Color, a: u8) rl.Color {
    return rgba(c.r, c.g, c.b, a);
}

/// Literal screen colour, for the one-off swatches the editor mixes (minimap soil, op dots).
pub const col = rgba;

// The rect the live left-drag STARTED on, at file scope because a Ctx is rebuilt every frame. Without it a
// widget reading "hovered AND held" is driven by ANY press: hold the button down on a button, sweep across
// the properties panel, and every slider you crossed took the value under the pointer. An immediate-mode
// kit has no widget ids, but a panel lays out to the same rect frame after frame — identity enough for one
// drag.
var dragOwner: ?rl.Rectangle = null;

pub const Ctx = struct {
    mouse: rl.Vector2,
    pressed: bool, // LMB went down this frame
    down: bool, // LMB held
    wheel: f32, // wheel notches this frame (read ONCE — widgets must not poll raylib again)
    anyHot: bool = false, // pointer over any widget (accumulated)
    t: f32 = 0, // seconds, for the caret blink

    // Deferred tooltip: the last hover this frame wins and is drawn on top by drawTip. Copied
    // into a buffer so a formatted tip may live on the caller's stack.
    tipBuf: [MSG_CAP]u8 = undefined,
    tipLen: usize = 0,

    pub fn begin(t: f32) Ctx {
        if (!rl.isMouseButtonDown(.left)) dragOwner = null;
        var c = Ctx{ .mouse = rl.getMousePosition(), .pressed = false, .down = false, .wheel = 0, .t = t };
        c.setLive(true);
        return c;
    }

    /// Turn widget INPUT off while leaving hit-testing (and so `anyHot`) alive. A modal or context menu is
    /// drawn LAST but sits over chrome drawn FIRST, so without muting that chrome a click "through" the
    /// dialog lands on the top bar or the kind list and edits the map behind it.
    pub fn setLive(ctx: *Ctx, live: bool) void {
        ctx.pressed = live and rl.isMouseButtonPressed(.left);
        ctx.down = live and rl.isMouseButtonDown(.left);
        ctx.wheel = if (live) rl.getMouseWheelMove() else 0;
    }

    /// Does the live drag belong to this rect? Claimed on the press that lands inside it.
    fn owns(ctx: *Ctx, r: rl.Rectangle) bool {
        if (ctx.pressed and rl.checkCollisionPointRec(ctx.mouse, r)) dragOwner = r;
        const o = dragOwner orelse return false;
        return o.x == r.x and o.y == r.y and o.width == r.width and o.height == r.height;
    }

    fn hot(ctx: *Ctx, r: rl.Rectangle) bool {
        const h = rl.checkCollisionPointRec(ctx.mouse, r);
        if (h) ctx.anyHot = true;
        return h;
    }

    pub fn setTip(ctx: *Ctx, text: []const u8) void {
        const n = @min(text.len, ctx.tipBuf.len - 1);
        @memcpy(ctx.tipBuf[0..n], text[0..n]);
        ctx.tipLen = n;
    }
};

pub fn rect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) };
}

/// Attach a tooltip to any rectangle.
pub fn tipFor(ctx: *Ctx, r: rl.Rectangle, text: [:0]const u8) void {
    if (rl.checkCollisionPointRec(ctx.mouse, r)) ctx.setTip(text);
}

/// Draw the pending tooltip at the cursor, clamped on-screen. Call LAST.
pub fn drawTip(ctx: *Ctx) void {
    if (ctx.tipLen == 0) return;
    ctx.tipBuf[ctx.tipLen] = 0;
    const s: [:0]const u8 = ctx.tipBuf[0..ctx.tipLen :0];
    const w = hud.monoW(s, hud.MONO);
    const h = hud.monoLineH(hud.MONO);
    var x: i32 = @as(i32, @intFromFloat(ctx.mouse.x)) + 16;
    var y: i32 = @as(i32, @intFromFloat(ctx.mouse.y)) + 22;
    x = @min(x, rl.getScreenWidth() - w - 22);
    y = @min(y, rl.getScreenHeight() - h - 14);
    rl.drawRectangle(x - 8, y - 5, w + 16, h + 10, INK);
    rl.drawRectangleLines(x - 8, y - 5, w + 16, h + 10, alpha(TRIM, 110));
    hud.mono(s, x, y, hud.MONO, VALUE);
}

/// A panel that also CLAIMS its rect as chrome. Without the claim, world clicks fall through the padding
/// between widgets onto the map behind — so claim and panel travel together and the hole can't reopen.
pub fn panel(ctx: *Ctx, r: rl.Rectangle, title: ?[:0]const u8) void {
    _ = ctx.hot(r);
    rl.drawRectangleRec(r, PANEL_FILL);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 110));
    if (title) |t| {
        hud.mono(t, @intFromFloat(r.x + 10), @intFromFloat(r.y + 6), hud.MONO, alpha(TRIM, 235));
    }
}

/// Clickable text button; `active` latches it (brass fill) for palettes and tabs.
pub fn button(ctx: *Ctx, r: rl.Rectangle, label: [:0]const u8, size: i32, active: bool) bool {
    const h = ctx.hot(r);
    const face = if (active) ACTIVE_FILL else if (h) HOVER_FILL else IDLE_FILL;
    rl.drawRectangleRec(r, face);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (active) 220 else if (h) 170 else 80));
    const tw = hud.monoW(label, size);
    const tx: i32 = @intFromFloat(r.x + (r.width - @as(f32, @floatFromInt(tw))) * 0.5);
    const ty: i32 = @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(hud.monoLineH(size)))) * 0.5);
    hud.mono(label, tx, ty, size, if (active) HOT else VALUE);
    return h and ctx.pressed;
}

// ── ICON BUTTONS ── the same button, with a glyph. Two shapes, and which one to use is decided by
// whether the label earns its width: a LAYER is a place you go and wants its name, a file action is
// a verb everyone already knows the picture for and wants the room back.
/// Inset from a button's left edge to its icon, and from the icon to its label.
const ICON_PAD: i32 = 8;
const ICON_GAP: i32 = 7;

/// How wide `iconButton` needs to be for this label — so a row of them can lay itself out without
/// each call site re-deriving the same sum and drifting from it.
pub fn iconButtonW(label: [:0]const u8, size: i32) i32 {
    return ICON_PAD * 2 + size + ICON_GAP + hud.monoW(label, size);
}

/// Icon on the left, label after it. The icon is sized to the label's type size, so the two scale
/// together and a button never ends up with a glyph twice the height of its own text.
pub fn iconButton(ctx: *Ctx, r: rl.Rectangle, ic: Icon, label: [:0]const u8, size: i32, active: bool) bool {
    const h = ctx.hot(r);
    const face = if (active) ACTIVE_FILL else if (h) HOVER_FILL else IDLE_FILL;
    rl.drawRectangleRec(r, face);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (active) 220 else if (h) 170 else 80));
    const fg = if (active) HOT else VALUE;
    const isz: f32 = @floatFromInt(size);
    icons.draw(ic, r.x + @as(f32, @floatFromInt(ICON_PAD)) + isz * 0.5, r.y + r.height * 0.5, isz, fg);
    const tx: i32 = @as(i32, @intFromFloat(r.x)) + ICON_PAD + size + ICON_GAP;
    const ty: i32 = @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(hud.monoLineH(size)))) * 0.5);
    hud.mono(label, tx, ty, size, fg);
    return h and ctx.pressed;
}

/// Icon ONLY, square, explaining itself on hover. For the verbs — a row of seven file buttons
/// spelled out fills the whole top bar at 1280 and leaves the document readout nowhere to go.
pub fn iconOnly(ctx: *Ctx, r: rl.Rectangle, ic: Icon, active: bool, tip: [:0]const u8) bool {
    tipFor(ctx, r, tip);
    const h = ctx.hot(r);
    const face = if (active) ACTIVE_FILL else if (h) HOVER_FILL else IDLE_FILL;
    rl.drawRectangleRec(r, face);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (active) 220 else if (h) 170 else 80));
    icons.draw(ic, r.x + r.width * 0.5, r.y + r.height * 0.5, @min(r.width, r.height) * 0.62, if (active) HOT else if (h) HOT else VALUE);
    return h and ctx.pressed;
}

/// A colour SWATCH button — the soil brushes, where the paint itself is the only honest icon. A
/// drawn glyph for "moss" would be a picture of a word; the colour is the thing.
pub fn swatchButton(ctx: *Ctx, r: rl.Rectangle, paint: rl.Color, label: [:0]const u8, size: i32, active: bool) bool {
    const h = ctx.hot(r);
    const face = if (active) ACTIVE_FILL else if (h) HOVER_FILL else IDLE_FILL;
    rl.drawRectangleRec(r, face);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (active) 220 else if (h) 170 else 80));
    const sw: f32 = @floatFromInt(size);
    const sr = rl.Rectangle{ .x = r.x + @as(f32, @floatFromInt(ICON_PAD)), .y = r.y + (r.height - sw) * 0.5, .width = sw, .height = sw };
    rl.drawRectangleRec(sr, paint);
    rl.drawRectangleLinesEx(sr, 1, alpha(TRIM, 150));
    const tx: i32 = @as(i32, @intFromFloat(r.x)) + ICON_PAD + size + ICON_GAP;
    const ty: i32 = @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(hud.monoLineH(size)))) * 0.5);
    hud.mono(label, tx, ty, size, if (active) HOT else VALUE);
    return h and ctx.pressed;
}

/// Looks like a button, cannot be pressed — for an action that doesn't apply to what is selected. Drawn
/// rather than omitted, so the menu keeps its shape and a missing row isn't read as the menu having moved.
pub fn disabled(ctx: *Ctx, r: rl.Rectangle, label: [:0]const u8, size: i32) void {
    _ = ctx.hot(r);
    rl.drawRectangleRec(r, IDLE_FILL);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 40));
    const tw = hud.monoW(label, size);
    const tx: i32 = @intFromFloat(r.x + (r.width - @as(f32, @floatFromInt(tw))) * 0.5);
    const ty: i32 = @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(hud.monoLineH(size)))) * 0.5);
    hud.mono(label, tx, ty, size, alpha(LABEL, 90));
}

/// A button that explains itself on hover.
pub fn buttonTip(ctx: *Ctx, r: rl.Rectangle, label: [:0]const u8, size: i32, active: bool, tp: [:0]const u8) bool {
    tipFor(ctx, r, tp);
    return button(ctx, r, label, size, active);
}

/// Auto-width chip for variant pickers; writes the width it used so callers can flow a row.
pub fn chip(ctx: *Ctx, x: i32, y: i32, label: [:0]const u8, active: bool, usedW: *i32) bool {
    const w = hud.monoW(label, hud.MONO) + 16;
    usedW.* = w + 5;
    return button(ctx, rect(x, y, w, 24), label, hud.MONO, active);
}

// A [-] value [+] stepper row. ONE geometry and one clamp guard for both value types, so the float and int
// rows stacked in a panel can't drift apart. A change is reported only when the CLAMPED value actually
// moved: +/− at a bound must not bank an undo step or raise the dirty flag, or the editor asks you to save
// work you didn't do.
fn stepper(comptime T: type, ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *T, step: T, lo: T, hi: T) bool {
    const clampfn = comptime if (T == f32) mathx.clampF else clampI;
    hud.mono(label, x, y + 4, hud.MONO, LABEL);
    const bw: i32 = 20;
    // Wide enough for the WIDEST world coordinate ("-152.0"), or the sign and last digit clip and the
    // readout lies about where the op is. One decimal: this is metres, and the second is never the edit.
    const vw: i32 = 62;
    const bx = x + w - bw * 2 - vw;
    var changed = false;
    if (button(ctx, rect(bx, y, bw, 22), "-", hud.MONO, false)) {
        const nv = clampfn(v.* - step, lo, hi);
        if (nv != v.*) {
            v.* = nv;
            changed = true;
        }
    }
    var buf: [24]u8 = undefined;
    const fmt = comptime if (T == f32) "{d:.1}" else "{d}";
    const s = std.fmt.bufPrintZ(&buf, fmt, .{v.*}) catch "?";
    hud.mono(s, bx + bw + @divTrunc(vw - hud.monoW(s, hud.MONO), 2), y + 4, hud.MONO, VALUE);
    if (button(ctx, rect(bx + bw + vw, y, bw, 22), "+", hud.MONO, false)) {
        const nv = clampfn(v.* + step, lo, hi);
        if (nv != v.*) {
            v.* = nv;
            changed = true;
        }
    }
    return changed;
}

fn clampI(v: i32, lo: i32, hi: i32) i32 {
    return @max(lo, @min(hi, v));
}

pub fn stepperF(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *f32, step: f32, lo: f32, hi: f32) bool {
    return stepper(f32, ctx, x, y, w, label, v, step, lo, hi);
}

pub fn stepperI(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *i32, step: i32, lo: i32, hi: i32) bool {
    return stepper(i32, ctx, x, y, w, label, v, step, lo, hi);
}

/// For the dials you want to FEEL (density, radius), where one notch at a time tells you nothing about the
/// shape of the range.
pub fn slider(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *f32, lo: f32, hi: f32) bool {
    hud.mono(label, x, y, hud.MONO, LABEL);
    const barY = y + hud.monoLineH(hud.MONO) + 3;
    const r = rect(x, barY, w, 12);
    const h = ctx.hot(r);
    rl.drawRectangleRec(r, IDLE_FILL);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (h) 170 else 90));
    const frac = mathx.clampF((v.* - lo) / (hi - lo), 0, 1);
    const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(w - 2)) * frac);
    if (fill > 0) rl.drawRectangle(x + 1, barY + 1, fill, 10, alpha(TRIM, 200));
    var buf: [24]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{d:.2}", .{v.*}) catch "?";
    hud.mono(s, x + w - hud.monoW(s, hud.MONO), y, hud.MONO, VALUE);
    // Driven by the drag that GRABBED this bar, not "hovered while held": a press that began elsewhere
    // can't set it, and a grab that wanders off the bar keeps hold of it.
    if (ctx.owns(r) and ctx.down) {
        const t = mathx.clampF((ctx.mouse.x - r.x) / r.width, 0, 1);
        const nv = lo + t * (hi - lo);
        if (nv != v.*) {
            v.* = nv;
            return true;
        }
    }
    return false;
}

/// A tick box.
pub fn checkbox(ctx: *Ctx, x: i32, y: i32, label: [:0]const u8, v: *bool) bool {
    const box = rect(x, y, 16, 16);
    const h = ctx.hot(box);
    rl.drawRectangleRec(box, IDLE_FILL);
    rl.drawRectangleLinesEx(box, 1, alpha(TRIM, if (h) 190 else 100));
    if (v.*) rl.drawRectangle(x + 4, y + 4, 8, 8, HOT);
    hud.mono(label, x + 24, y - 1, hud.MONO, if (v.*) VALUE else LABEL);
    const labelHit = rect(x, y, 24 + hud.monoW(label, hud.MONO), 16);
    if (ctx.hot(labelHit) and ctx.pressed) {
        v.* = !v.*;
        return true;
    }
    return false;
}

/// Single-line text field. The caller owns focus; while focused it consumes typed characters
/// and backspace, and draws a breathing caret.
pub fn textField(ctx: *Ctx, r: rl.Rectangle, buf: []u8, len: *usize, focused: bool) void {
    _ = ctx.hot(r);
    rl.drawRectangleRec(r, rgba(14, 12, 10, 245));
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (focused) 220 else 100));
    if (focused) {
        var ch = rl.getCharPressed();
        while (ch != 0) : (ch = rl.getCharPressed()) {
            // The atlas is ASCII-ONLY — a typed 'é' renders as tofu, so it never enters the buffer.
            if (ch >= 32 and ch < 127 and len.* < buf.len - 1) {
                buf[len.*] = @intCast(ch);
                len.* += 1;
            }
        }
        if ((rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) and len.* > 0) len.* -= 1;
    }
    buf[len.*] = 0;
    const s: [:0]const u8 = buf[0..len.* :0];
    hud.mono(s, @intFromFloat(r.x + 8), @intFromFloat(r.y + 5), hud.MONO, VALUE);
    if (focused and @mod(ctx.t, 1.0) < 0.55) {
        const cx: i32 = @as(i32, @intFromFloat(r.x)) + 9 + hud.monoW(s, hud.MONO);
        rl.drawRectangle(cx, @intFromFloat(r.y + 6), 2, hud.monoLineH(hud.MONO) - 2, HOT);
    }
}

/// A scrolling list of labels; returns the index clicked, if any. `scroll` is in ROWS.
pub fn list(ctx: *Ctx, r: rl.Rectangle, labels: []const [:0]const u8, sel: usize, scroll: *i32) ?usize {
    _ = ctx.hot(r);
    rl.drawRectangleRec(r, rgba(12, 11, 10, 240));
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 90));
    const rowH: i32 = hud.monoLineH(hud.MONO) + 6;
    const rows: i32 = @divTrunc(@as(i32, @intFromFloat(r.height)) - 6, rowH);
    const maxScroll = @max(0, @as(i32, @intCast(labels.len)) - rows);
    if (rl.checkCollisionPointRec(ctx.mouse, r)) {
        scroll.* -= @intFromFloat(ctx.wheel * 3);
    }
    scroll.* = @max(0, @min(maxScroll, scroll.*));
    var clicked: ?usize = null;
    var i: i32 = 0;
    while (i < rows) : (i += 1) {
        const idx: usize = @intCast(i + scroll.*);
        if (idx >= labels.len) break;
        const rowR = rect(
            @as(i32, @intFromFloat(r.x)) + 3,
            @as(i32, @intFromFloat(r.y)) + 3 + i * rowH,
            @as(i32, @intFromFloat(r.width)) - 6,
            rowH - 2,
        );
        const h = rl.checkCollisionPointRec(ctx.mouse, rowR);
        if (idx == sel) rl.drawRectangleRec(rowR, ACTIVE_FILL) else if (h) rl.drawRectangleRec(rowR, HOVER_FILL);
        hud.mono(labels[idx], @as(i32, @intFromFloat(rowR.x)) + 6, @as(i32, @intFromFloat(rowR.y)) + 2, hud.MONO, if (idx == sel) HOT else VALUE);
        if (h and ctx.pressed) clicked = idx;
    }
    // A nub, so a long list looks scrollable instead of truncated.
    if (maxScroll > 0) {
        const trackH = r.height - 6;
        const nubH = @max(18.0, trackH * @as(f32, @floatFromInt(rows)) / @as(f32, @floatFromInt(labels.len)));
        const t = @as(f32, @floatFromInt(scroll.*)) / @as(f32, @floatFromInt(maxScroll));
        rl.drawRectangle(
            @as(i32, @intFromFloat(r.x + r.width)) - 5,
            @as(i32, @intFromFloat(r.y + 3 + (trackH - nubH) * t)),
            3,
            @intFromFloat(nubH),
            alpha(TRIM, 170),
        );
    }
    return clicked;
}

/// Dim the screen, centre a panel, return its top-left. The backdrop eats the pointer wholesale, so
/// nothing behind a modal is ever clickable.
pub const ModalBox = struct { x: i32, y: i32, w: i32, h: i32 };

pub fn beginModal(ctx: *Ctx, w: i32, h: i32, title: [:0]const u8) ModalBox {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    rl.drawRectangle(0, 0, sw, sh, rgba(0, 0, 0, 150));
    ctx.anyHot = true;
    const x = @divTrunc(sw - w, 2);
    const y = @divTrunc(sh - h, 2);
    const r = rect(x, y, w, h);
    rl.drawRectangleRec(r, PANEL_FILL);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 160));
    hud.mono(title, x + @divTrunc(w - hud.monoW(title, hud.MONO), 2), y + 12, hud.MONO, TITLE);
    rl.drawRectangle(x + 16, y + hud.monoLineH(hud.MONO) + 18, w - 32, 1, alpha(TRIM, 90));
    return .{ .x = x, .y = y, .w = w, .h = h };
}
