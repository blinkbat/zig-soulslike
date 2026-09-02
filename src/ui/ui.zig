const std = @import("std");
const rl = @import("raylib");
const hud = @import("hud.zig");
const mathx = @import("../core/mathx.zig");
const icons = @import("icons.zig");
const uiart = @import("uiart.zig");

pub const Icon = icons.Icon;

const rgba = mathx.rgba;


pub const MSG_CAP = 120;

pub const ROW_H: i32 = hud.monoLineH(hud.MONO) + 6;

pub const DRAG_PX: f32 = 4.0;

pub const INK = rgba(10, 9, 8, 232);
pub const PANEL_FILL = rgba(16, 15, 13, 235);
pub const TRIM = uiart.GILT_DIM;
pub const LABEL = uiart.TEXT_DIM;
pub const VALUE = rgba(228, 216, 194, 255);
pub const TITLE = rgba(236, 226, 202, 255);
pub const HOT = uiart.HOT;
pub const LIVE = rgba(110, 178, 168, 255);
pub const ACTIVE_FILL = rgba(96, 74, 40, 235);
pub const IDLE_FILL = rgba(26, 22, 18, 228);
pub const HOVER_FILL = rgba(42, 34, 26, 235);

pub const alpha = mathx.withAlpha;

pub const col = rgba;

var dragOwner: ?rl.Rectangle = null;

pub const Ctx = struct {
    mouse: rl.Vector2,
    pressed: bool,
    down: bool,
    wheel: f32, // wheel notches this frame (read ONCE — widgets must not poll raylib again)
    anyHot: bool = false,
    t: f32 = 0,

    tipBuf: [MSG_CAP]u8 = undefined,
    tipLen: usize = 0,

    pub fn begin(t: f32) Ctx {
        if (!rl.isMouseButtonDown(.left)) dragOwner = null;
        if (!kbSeen) kbOwner = null;
        kbSeen = false;
        kbTaken = false;
        var c = Ctx{ .mouse = rl.getMousePosition(), .pressed = false, .down = false, .wheel = 0, .t = t };
        c.setLive(true);
        return c;
    }

    pub fn setLive(ctx: *Ctx, live: bool) void {
        ctx.pressed = live and rl.isMouseButtonPressed(.left);
        ctx.down = live and rl.isMouseButtonDown(.left);
        ctx.wheel = if (live) rl.getMouseWheelMove() else 0;
    }

    pub fn owns(ctx: *Ctx, r: rl.Rectangle) bool {
        if (ctx.pressed and rl.checkCollisionPointRec(ctx.mouse, r)) dragOwner = r;
        const o = dragOwner orelse return false;
        return o.x == r.x and o.y == r.y and o.width == r.width and o.height == r.height;
    }

    pub fn hot(ctx: *Ctx, r: rl.Rectangle) bool {
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

const TIP_MAX_W: i32 = 420;
const TIP_LINES = 6;
var tipWrapBuf: [MSG_CAP + TIP_LINES]u8 = undefined;
var tipWrapLines: [TIP_LINES][:0]const u8 = undefined;

pub fn drawTip(ctx: *Ctx) void {
    if (ctx.tipLen == 0) return;
    const lines = hud.wrapMono(ctx.tipBuf[0..ctx.tipLen], hud.MONO, TIP_MAX_W, &tipWrapBuf, &tipWrapLines);
    if (lines.len == 0) return;
    const lh = hud.monoLineH(hud.MONO);
    var w: i32 = 0;
    for (lines) |ln| w = @max(w, hud.monoW(ln, hud.MONO));
    const h = lh * @as(i32, @intCast(lines.len));
    var x: i32 = @as(i32, @intFromFloat(ctx.mouse.x)) + 16;
    var y: i32 = @as(i32, @intFromFloat(ctx.mouse.y)) + 22;
    x = @max(0, @min(x, rl.getScreenWidth() - w - 22));
    y = @max(0, @min(y, rl.getScreenHeight() - h - 14));
    rl.drawRectangle(x - 8, y - 5, w + 16, h + 10, INK);
    rl.drawRectangleLines(x - 8, y - 5, w + 16, h + 10, alpha(TRIM, 110));
    for (lines, 0..) |ln, i| hud.mono(ln, x, y + lh * @as(i32, @intCast(i)), hud.MONO, VALUE);
}

pub fn panel(ctx: *Ctx, r: rl.Rectangle, title: ?[:0]const u8) void {
    _ = ctx.hot(r);
    uiart.plate(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height), PANEL_FILL.a);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 110));
    rl.drawRectangle(@intFromFloat(r.x + 1), @intFromFloat(r.y + 1), @intFromFloat(r.width - 2), 1, alpha(TRIM, 60));
    if (title) |t| {
        hud.mono(t, @intFromFloat(r.x + 10), @intFromFloat(r.y + 6), hud.MONO, alpha(TRIM, 235));
    }
}

/// A tip is not optional: a button has four characters of room ("lean", "take", "r1") and what a thing DOES lives here or
/// nowhere. Zig has no default arguments, which is the point: a widget added without a tip does not compile.
pub fn button(ctx: *Ctx, r: rl.Rectangle, label: [:0]const u8, size: i32, active: bool, tip: [:0]const u8) bool {
    tipFor(ctx, r, tip);
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

pub fn iconButton(ctx: *Ctx, r: rl.Rectangle, ic: Icon, label: [:0]const u8, size: i32, active: bool, tip: [:0]const u8) bool {
    tipFor(ctx, r, tip);
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

pub const LayerHit = enum { none, select, toggle };

pub fn layerButtonW(label: [:0]const u8, size: i32) i32 {
    if (label.len == 0) return ICON_PAD * 2 + size + EYE_SLOT;
    return iconButtonW(label, size) + EYE_SLOT;
}

/// **THE SLOT IS THE HIT AREA; THE GLYPH IS DRAWN BIGGER THAN IT.** The glyph overhangs into the label's own right-hand `ICON_PAD`, so the eye reads at `EYE_DRAW` while the layout only pays `EYE_SLOT`.
const EYE_SLOT: i32 = 15;
const EYE_DRAW: f32 = 19.0;

pub fn layerButton(ctx: *Ctx, r: rl.Rectangle, ic: Icon, label: [:0]const u8, size: i32, active: bool, shown: bool) LayerHit {
    const slot: f32 = @floatFromInt(EYE_SLOT);
    const eyeR = rl.Rectangle{ .x = r.x + r.width - slot, .y = r.y, .width = slot, .height = r.height };
    const overEye = ctx.hot(eyeR);
    const h = ctx.hot(r);
    const face = if (active) ACTIVE_FILL else if (h) HOVER_FILL else IDLE_FILL;
    rl.drawRectangleRec(r, face);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (active) 220 else if (h) 170 else 80));
    // A HIDDEN LAYER READS AS HIDDEN FROM THE LABEL, not only from the glyph: the whole row goes dim, which is the state you need to spot at a glance when you have forgotten why the wood is missing.
    const fg = if (!shown) LABEL else if (active) HOT else VALUE;
    const isz: f32 = @floatFromInt(size);
    icons.draw(ic, r.x + @as(f32, @floatFromInt(ICON_PAD)) + isz * 0.5, r.y + r.height * 0.5, isz, fg);
    if (label.len > 0) {
        const tx: i32 = @as(i32, @intFromFloat(r.x)) + ICON_PAD + size + ICON_GAP;
        const ty: i32 = @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(hud.monoLineH(size)))) * 0.5);
        hud.mono(label, tx, ty, size, fg);
    }
    rl.drawLineEx(
        .{ .x = eyeR.x, .y = r.y + 3 },
        .{ .x = eyeR.x, .y = r.y + r.height - 3 },
        1,
        alpha(TRIM, if (overEye) 190 else 70),
    );
    icons.draw(
        if (shown) .eye else .eyeOff,
        eyeR.x + slot * 0.5,
        eyeR.y + eyeR.height * 0.5,
        @min(EYE_DRAW, eyeR.height),
        if (overEye) HOT else if (shown) VALUE else LABEL,
    );
    if (!ctx.pressed) return .none;
    if (overEye) return .toggle;
    return if (h) .select else .none;
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

pub fn swatchButton(ctx: *Ctx, r: rl.Rectangle, paint: rl.Color, label: [:0]const u8, size: i32, active: bool, tip: [:0]const u8) bool {
    tipFor(ctx, r, tip);
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

pub fn disabled(ctx: *Ctx, r: rl.Rectangle, label: [:0]const u8, size: i32, tip: [:0]const u8) void {
    tipFor(ctx, r, tip);
    _ = ctx.hot(r);
    rl.drawRectangleRec(r, IDLE_FILL);
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, 40));
    const tw = hud.monoW(label, size);
    const tx: i32 = @intFromFloat(r.x + (r.width - @as(f32, @floatFromInt(tw))) * 0.5);
    const ty: i32 = @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(hud.monoLineH(size)))) * 0.5);
    hud.mono(label, tx, ty, size, alpha(LABEL, 90));
}

pub const TAB_H: i32 = 24;

/// **A ROW OF TABS THAT OPENS INTO WHAT IS UNDER IT** — evenly divided over `w`, and the live one is the one
pub fn tabs(ctx: *Ctx, x: i32, y: i32, w: i32, labels: []const [:0]const u8, sel: usize, tips: []const [:0]const u8) ?usize {
    std.debug.assert(tips.len == labels.len);
    var hit: ?usize = null;
    const n: i32 = @intCast(labels.len);
    if (n == 0) return null;
    const rule = alpha(TRIM, 150);
    rl.drawRectangle(x, y + TAB_H - 1, w, 1, rule);
    for (labels, 0..) |lab, i| {
        const ix: i32 = @intCast(i);
        const x0 = x + @divTrunc(w * ix, n);
        const x1 = x + @divTrunc(w * (ix + 1), n);
        const tw = x1 - x0;
        const r = rect(x0, y, tw, TAB_H);
        const on = i == sel;
        tipFor(ctx, r, tips[i]);
        const h = ctx.hot(r);
        rl.drawRectangleRec(r, if (on) ACTIVE_FILL else if (h) HOVER_FILL else IDLE_FILL);
        const trim = alpha(TRIM, if (on) 220 else if (h) 170 else 80);
        rl.drawRectangle(x0, y, tw, 1, trim);
        rl.drawRectangle(x0, y, 1, TAB_H, trim);
        rl.drawRectangle(x1 - 1, y, 1, TAB_H, trim);
        if (!on) rl.drawRectangle(x0, y + TAB_H - 1, tw, 1, rule);
        const lw = hud.monoW(lab, hud.MONO);
        hud.mono(lab, x0 + @divTrunc(tw - lw, 2), y + @divTrunc(TAB_H - hud.monoLineH(hud.MONO), 2), hud.MONO, if (on) HOT else VALUE);
        if (h and ctx.pressed) hit = i;
    }
    return hit;
}

pub fn chip(ctx: *Ctx, x: i32, y: i32, label: [:0]const u8, active: bool, usedW: *i32, tip: [:0]const u8) bool {
    const w = hud.monoW(label, hud.MONO) + 16;
    usedW.* = w + 5;
    return button(ctx, rect(x, y, w, 24), label, hud.MONO, active, tip);
}

fn stepper(comptime T: type, ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *T, step: T, lo: T, hi: T, tip: [:0]const u8) bool {
    const clampfn = comptime if (T == f32) mathx.clampF else mathx.clampI;
    tipFor(ctx, rect(x, y, w, 22), tip);
    hud.mono(label, x, y + 4, hud.MONO, LABEL);
    const bw: i32 = 20;
    // Wide enough for the WIDEST world coordinate ("-152.0"), or the sign and last digit clip and the readout lies about where the op is.
    const vw: i32 = 62;
    const bx = x + w - bw * 2 - vw;
    var changed = false;
    if (button(ctx, rect(bx, y, bw, 22), "-", hud.MONO, false, tip)) {
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
    if (button(ctx, rect(bx + bw + vw, y, bw, 22), "+", hud.MONO, false, tip)) {
        const nv = clampfn(v.* + step, lo, hi);
        if (nv != v.*) {
            v.* = nv;
            changed = true;
        }
    }
    return changed;
}

pub fn stepperF(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *f32, step: f32, lo: f32, hi: f32, tip: [:0]const u8) bool {
    return stepper(f32, ctx, x, y, w, label, v, step, lo, hi, tip);
}

pub fn stepperI(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *i32, step: i32, lo: i32, hi: i32, tip: [:0]const u8) bool {
    return stepper(i32, ctx, x, y, w, label, v, step, lo, hi, tip);
}

pub fn slider(ctx: *Ctx, x: i32, y: i32, w: i32, label: [:0]const u8, v: *f32, lo: f32, hi: f32, tip: [:0]const u8) bool {
    hud.mono(label, x, y, hud.MONO, LABEL);
    const barY = y + hud.monoLineH(hud.MONO) + 3;
    tipFor(ctx, rect(x, y, w, barY + 12 - y), tip);
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

pub fn checkbox(ctx: *Ctx, x: i32, y: i32, label: [:0]const u8, v: *bool, tip: [:0]const u8) bool {
    const box = rect(x, y, 16, 16);
    tipFor(ctx, rect(x, y, 24 + hud.monoW(label, hud.MONO), 16), tip);
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

/// **ONE FIELD OWNS THE KEYBOARD, AND IT IS CLAIMED BY BEING CLICKED.** `rl.getCharPressed` DRAINS a global
var kbOwner: ?u32 = null;
var kbSeen = false;
var kbTaken = false;

pub fn textField(ctx: *Ctx, r: rl.Rectangle, buf: []u8, len: *usize, id: u32, eligible: bool, tip: [:0]const u8) bool {
    tipFor(ctx, r, tip);
    _ = ctx.hot(r);
    if (eligible) {
        if (ctx.pressed and rl.checkCollisionPointRec(ctx.mouse, r)) kbOwner = id;
        if (kbOwner) |o| {
            if (o == id) kbSeen = true;
        }
    }
    const focused = eligible and !kbTaken and (kbOwner == null or kbOwner.? == id);
    if (focused) kbTaken = true;
    rl.drawRectangleRec(r, rgba(14, 12, 10, 245));
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (focused) 220 else 100));
    if (focused) {
        var ch = rl.getCharPressed();
        while (ch != 0) : (ch = rl.getCharPressed()) {
            if (ch >= 32 and ch < 127 and len.* < buf.len - 1) {
                buf[len.*] = @intCast(ch);
                len.* += 1;
            }
        }
        if ((rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) and len.* > 0) len.* -= 1;
    }
    len.* = @min(len.*, buf.len - 1);
    buf[len.*] = 0;
    const s: [:0]const u8 = buf[0..len.* :0];

    // **THE FIELD SCROLLS, IT DOES NOT SPILL.** A `worldfmt.TALK_SAY_CAP` greeting is 240 characters in a box
    // 60 wide; unclipped, the tail and the caret both ran out over the panel and off the window. Editing only
    const bx: i32 = @intFromFloat(r.x);
    const bw: i32 = @intFromFloat(r.width);
    const bh: i32 = @intFromFloat(r.height);
    const tw = hud.monoW(s, hud.MONO);
    const off: i32 = if (focused) @max(0, tw - (bw - 16 - CARET_W)) else 0;
    rl.beginScissorMode(bx + 1, @as(i32, @intFromFloat(r.y)) + 1, bw - 2, bh - 2);
    hud.mono(s, bx + 8 - off, @intFromFloat(r.y + 5), hud.MONO, VALUE);
    if (focused and @mod(ctx.t, 1.0) < 0.55) {
        rl.drawRectangle(bx + 9 + tw - off, @intFromFloat(r.y + 6), CARET_W, hud.monoLineH(hud.MONO) - 2, HOT);
    }
    rl.endScissorMode();
    return focused;
}

const CARET_W: i32 = 2;

pub fn listRows(heightPx: i32) i32 {
    return @divTrunc(heightPx - 6, ROW_H);
}

pub fn list(ctx: *Ctx, r: rl.Rectangle, labels: []const [:0]const u8, sel: usize, scroll: *i32, tip: [:0]const u8) ?usize {
    tipFor(ctx, r, tip);
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


const DD_ROW_H: i32 = ROW_H;
const DD_MAX_SHOWN: i32 = 10;

var openId: ?u32 = null;
var openScroll: i32 = 0;
var pending: ?Pending = null;

const DD_ROWS_CAP: usize = 128;
var ddRows: [DD_ROWS_CAP][:0]const u8 = undefined;

const Pending = struct {
    r: rl.Rectangle,
    n: usize,
    sel: usize,

    fn labels(self: Pending) []const [:0]const u8 {
        return ddRows[0..self.n];
    }
};

fn ddPanel(r: rl.Rectangle, n: usize) rl.Rectangle {
    const rows: i32 = @min(@as(i32, @intCast(@max(n, 1))), DD_MAX_SHOWN);
    const h: f32 = @floatFromInt(rows * DD_ROW_H + 6);
    const below = r.y + r.height;
    const room = @as(f32, @floatFromInt(rl.getScreenHeight())) - below;
    const y = if (room < h) r.y - h else below;
    return .{ .x = r.x, .y = y, .width = @max(r.width, 168), .height = h };
}

pub fn dropdown(ctx: *Ctx, r: rl.Rectangle, id: u32, labels: []const [:0]const u8, sel: usize, tip: [:0]const u8) ?usize {
    tipFor(ctx, r, tip);
    const isOpen = openId != null and openId.? == id;
    const h = ctx.hot(r);
    rl.drawRectangleRec(r, if (isOpen) ACTIVE_FILL else if (h) HOVER_FILL else rgba(18, 16, 14, 225));
    rl.drawRectangleLinesEx(r, 1, alpha(TRIM, if (isOpen or h) 180 else 90));
    const shown: [:0]const u8 = if (sel < labels.len) labels[sel] else "(none)";
    hud.mono(shown, @as(i32, @intFromFloat(r.x)) + 6, @as(i32, @intFromFloat(r.y)) + 2, hud.MONO, if (isOpen) HOT else VALUE);
    const cx = r.x + r.width - 10;
    const cy = r.y + r.height * 0.5;
    const d: f32 = if (isOpen) -1 else 1;
    rl.drawTriangle(
        rl.Vector2.init(cx - 4, cy - 2 * d),
        rl.Vector2.init(cx + 4, cy - 2 * d),
        rl.Vector2.init(cx, cy + 3 * d),
        alpha(TRIM, 210),
    );
    if (h and ctx.pressed) {
        openId = if (isOpen) null else id;
        openScroll = if (isOpen) 0 else @max(0, @as(i32, @intCast(sel)) - DD_MAX_SHOWN + 1);
        return null;
    }
    if (!isOpen) return null;

    const nRows = @min(labels.len, DD_ROWS_CAP);
    const box = ddPanel(r, nRows);
    ctx.anyHot = true;
    if (rl.checkCollisionPointRec(ctx.mouse, box)) {
        openScroll -= @intFromFloat(ctx.wheel * 3);
        const maxScroll = @max(0, @as(i32, @intCast(nRows)) - DD_MAX_SHOWN);
        openScroll = @max(0, @min(maxScroll, openScroll));
    }
    var picked: ?usize = null;
    if (ctx.pressed) {
        if (rl.checkCollisionPointRec(ctx.mouse, box)) {
            const rel = ctx.mouse.y - (box.y + 3);
            const row = @divFloor(@as(i32, @intFromFloat(rel)), DD_ROW_H);
            const idx: usize = @intCast(@max(row, 0) + openScroll);
            const drawn: i32 = @min(@as(i32, @intCast(nRows)), DD_MAX_SHOWN);
            if (row >= 0 and row < drawn and idx < nRows) {
                picked = idx;
                openId = null;
                openScroll = 0;
            }
        } else {
            openId = null;
            openScroll = 0;
        }
    }
    if (openId != null) {
        @memcpy(ddRows[0..nRows], labels[0..nRows]);
        pending = .{ .r = r, .n = nRows, .sel = sel };
    }
    return picked;
}

pub fn endDropdowns() void {
    const p = pending orelse return;
    pending = null;
    const rows_ = p.labels();
    const box = ddPanel(p.r, rows_.len);
    uiart.seat(@intFromFloat(box.x), @intFromFloat(box.y), @intFromFloat(box.width), @intFromFloat(box.height));
    rl.drawRectangleRec(box, rgba(0, 0, 0, 255));
    rl.drawRectangleRec(box, rgba(20, 18, 15, 255));
    rl.drawRectangleLinesEx(box, 1, alpha(TRIM, 190));
    const rows: i32 = @min(@as(i32, @intCast(rows_.len)), DD_MAX_SHOWN);
    var i: i32 = 0;
    while (i < rows) : (i += 1) {
        const idx: usize = @intCast(i + openScroll);
        if (idx >= rows_.len) break;
        const rowR = rect(
            @as(i32, @intFromFloat(box.x)) + 3,
            @as(i32, @intFromFloat(box.y)) + 3 + i * DD_ROW_H,
            @as(i32, @intFromFloat(box.width)) - 6,
            DD_ROW_H - 2,
        );
        const hot = rl.checkCollisionPointRec(mouseNow(), rowR);
        if (idx == p.sel) rl.drawRectangleRec(rowR, ACTIVE_FILL) else if (hot) rl.drawRectangleRec(rowR, HOVER_FILL);
        hud.mono(rows_[idx], @as(i32, @intFromFloat(rowR.x)) + 6, @as(i32, @intFromFloat(rowR.y)) + 2, hud.MONO, if (idx == p.sel) HOT else VALUE);
    }
    if (rows_.len > DD_MAX_SHOWN) {
        var nb: [24]u8 = undefined;
        const more = std.fmt.bufPrintZ(&nb, "+{d} more", .{rows_.len - @as(usize, @intCast(rows))}) catch "";
        hud.mono(more, @as(i32, @intFromFloat(box.x)) + 6, @as(i32, @intFromFloat(box.y + box.height)) - 2, hud.MONO, alpha(TRIM, 200));
    }
}

fn mouseNow() rl.Vector2 {
    return rl.getMousePosition();
}

pub fn dropdownOpen() bool {
    return openId != null;
}

pub fn openDropdownForShot(id: u32) void {
    openId = id;
    openScroll = 0;
}

pub fn closeDropdown() void {
    openId = null;
    openScroll = 0;
    pending = null;
}

/// **A STABLE ID FROM WHAT THE ROW EDITS.** Hashed off a tag and two indices, so act row 3 of trigger 7 keeps
/// its identity while the panel is open and cannot collide with condition row 3 of the same trigger.
pub fn ddId(tag: u8, a: usize, b: usize) u32 {
    return (@as(u32, tag) << 24) ^ (@as(u32, @truncate(a)) << 12) ^ @as(u32, @truncate(b));
}

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
