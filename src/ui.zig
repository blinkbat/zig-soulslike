const std = @import("std");
const rl = @import("raylib");
const hud = @import("hud.zig");
const mathx = @import("mathx.zig");
const icons = @import("icons.zig");
const uiart = @import("uiart.zig");

pub const Icon = icons.Icon;

const rgba = mathx.rgba;


pub const MSG_CAP = 120; // shared cap for short UI strings (tips, toasts, prompts)

/// ONE ROW PITCH for every stacked row of editor chrome.
pub const ROW_H: i32 = hud.monoLineH(hud.MONO) + 6;

/// POINTER TRAVEL that separates a CLICK from a DRAG, in pixels.
pub const DRAG_PX: f32 = 4.0;

pub const INK = rgba(10, 9, 8, 232);
pub const PANEL_FILL = rgba(16, 15, 13, 235);
pub const TRIM = rgba(146, 124, 82, 255);
pub const LABEL = rgba(150, 146, 138, 255);
pub const VALUE = rgba(228, 216, 194, 255);
pub const TITLE = rgba(236, 226, 202, 255);
pub const HOT = uiart.HOT;
pub const ACTIVE_FILL = rgba(96, 74, 40, 235);
pub const IDLE_FILL = rgba(26, 22, 18, 228);
pub const HOVER_FILL = rgba(42, 34, 26, 235);

pub const alpha = mathx.withAlpha;

/// Literal screen colour, for the one-off swatches the editor mixes (minimap soil, op dots).
pub const col = rgba;

// The rect the live left-drag STARTED on, at file scope because a Ctx is rebuilt every frame.
var dragOwner: ?rl.Rectangle = null;

pub const Ctx = struct {
    mouse: rl.Vector2,
    pressed: bool, // LMB went down this frame
    down: bool, // LMB held
    wheel: f32, // wheel notches this frame (read ONCE — widgets must not poll raylib again)
    anyHot: bool = false, // pointer over any widget (accumulated)
    t: f32 = 0, // seconds, for the caret blink

    // Deferred tooltip: the last hover this frame wins and is drawn on top by drawTip.
    tipBuf: [MSG_CAP]u8 = undefined,
    tipLen: usize = 0,

    pub fn begin(t: f32) Ctx {
        if (!rl.isMouseButtonDown(.left)) dragOwner = null;
        var c = Ctx{ .mouse = rl.getMousePosition(), .pressed = false, .down = false, .wheel = 0, .t = t };
        c.setLive(true);
        return c;
    }

    /// Turn widget INPUT off while leaving hit-testing (and so `anyHot`) alive.
    pub fn setLive(ctx: *Ctx, live: bool) void {
        ctx.pressed = live and rl.isMouseButtonPressed(.left);
        ctx.down = live and rl.isMouseButtonDown(.left);
        ctx.wheel = if (live) rl.getMouseWheelMove() else 0;
    }

    /// Does the live drag belong to this rect?
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

pub const rect = uiart.rect;

pub fn tipFor(ctx: *Ctx, r: rl.Rectangle, text: [:0]const u8) void {
    if (rl.checkCollisionPointRec(ctx.mouse, r)) ctx.setTip(text);
}

/// Draw the pending tooltip at the cursor, clamped on-screen.
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

/// A panel that also CLAIMS its rect as chrome.
pub fn panel(ctx: *Ctx, r: rl.Rectangle, title: ?[:0]const u8) void {
    _ = ctx.hot(r);
    uiart.plate(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height), PANEL_FILL.a);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 110));
    rl.drawRectangle(@intFromFloat(r.x + 1), @intFromFloat(r.y + 1), @intFromFloat(r.width - 2), 1, alpha(TRIM, 60)); // lit top rim
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

const ICON_PAD: i32 = 8;
const ICON_GAP: i32 = 7;

pub fn iconButtonW(label: [:0]const u8, size: i32) i32 {
    return ICON_PAD * 2 + size + ICON_GAP + hud.monoW(label, size);
}

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

pub fn iconOnly(ctx: *Ctx, r: rl.Rectangle, ic: Icon, active: bool, tip: [:0]const u8) bool {
    tipFor(ctx, r, tip);
    const h = ctx.hot(r);
    const face = if (active) ACTIVE_FILL else if (h) HOVER_FILL else IDLE_FILL;
    rl.drawRectangleRec(r, face);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (active) 220 else if (h) 170 else 80));
    icons.draw(ic, r.x + r.width * 0.5, r.y + r.height * 0.5, @min(r.width, r.height) * 0.62, if (active) HOT else if (h) HOT else VALUE);
    return h and ctx.pressed;
}

/// A colour SWATCH button — the soil brushes, where the paint itself is the only honest icon.
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

/// Looks like a button, cannot be pressed — for an action that doesn't apply to what is selected.
pub fn disabled(ctx: *Ctx, r: rl.Rectangle, label: [:0]const u8, size: i32) void {
    _ = ctx.hot(r);
    rl.drawRectangleRec(r, IDLE_FILL);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 40));
    const tw = hud.monoW(label, size);
    const tx: i32 = @intFromFloat(r.x + (r.width - @as(f32, @floatFromInt(tw))) * 0.5);
    const ty: i32 = @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(hud.monoLineH(size)))) * 0.5);
    hud.mono(label, tx, ty, size, alpha(LABEL, 90));
}

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

fn stepper(comptime T: type, ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *T, step: T, lo: T, hi: T) bool {
    const clampfn = comptime if (T == f32) mathx.clampF else mathx.clampI;
    hud.mono(label, x, y + 4, hud.MONO, LABEL);
    const bw: i32 = 20;
    // Wide enough for the WIDEST world coordinate ("-152.0"), or the sign and last digit clip and the readout lies about where the op is.
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

pub fn stepperF(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *f32, step: f32, lo: f32, hi: f32) bool {
    return stepper(f32, ctx, x, y, w, label, v, step, lo, hi);
}

pub fn stepperI(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *i32, step: i32, lo: i32, hi: i32) bool {
    return stepper(i32, ctx, x, y, w, label, v, step, lo, hi);
}

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

/// A scrolling list of labels; returns the index clicked, if any.
pub fn listRows(heightPx: i32) i32 {
    return @divTrunc(heightPx - 6, ROW_H);
}

pub fn list(ctx: *Ctx, r: rl.Rectangle, labels: []const [:0]const u8, sel: usize, scroll: *i32) ?usize {
    _ = ctx.hot(r);
    rl.drawRectangleRec(r, rgba(12, 11, 10, 240));
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 90));
    const rowH: i32 = ROW_H;
    const rows: i32 = listRows(@intFromFloat(r.height));
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

/// Dim the screen, centre a panel, return its top-left.
pub const ModalBox = struct { x: i32, y: i32, w: i32, h: i32 };

pub fn beginModal(ctx: *Ctx, w: i32, h: i32, title: [:0]const u8) ModalBox {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    rl.drawRectangle(0, 0, sw, sh, rgba(0, 0, 0, 150));
    ctx.anyHot = true;
    const x = @divTrunc(sw - w, 2);
    const y = @divTrunc(sh - h, 2);
    uiart.seat(x, y, w, h);
    uiart.plate(x, y, w, h, PANEL_FILL.a);
    uiart.frame(x, y, w, h, 170);
    hud.mono(title, x + @divTrunc(w - hud.monoW(title, hud.MONO), 2), y + 12, hud.MONO, TITLE);
    uiart.divider(x + @divTrunc(w, 2), y + hud.monoLineH(hud.MONO) + 18, @divTrunc(w, 2) - 20, 140);
    return .{ .x = x, .y = y, .w = w, .h = h };
}
