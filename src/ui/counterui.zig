const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const itemart = @import("itemart.zig");
const item = @import("../play/item.zig");
const heromod = @import("../play/hero.zig");
const counter = @import("../play/counter.zig");

const rgba = mathx.rgba;

// **THE COUNTER'S PANEL, AND NOTHING ELSE.** Every number on it comes off `play/counter.zig`, which is where the
// arithmetic and the tests live; this file decides only where things sit. Two screens share it because a shop
// and a smithy are one interaction (`counter.Trade`).
//
// **IT IS THE DIALOG PANEL'S SHAPE, NOT THE BOOK'S.** A counter opens in the WORLD off a trigger, so it is a
// panel over a running frame like `world/dialog.zig` — not a page of the pause book. That is why it draws its
// own purse line: the HUD is hidden behind it.

const PAD: i32 = 18;
const ROW_H: i32 = 26;
const HEAD_H: i32 = 64;
const FOOT_H: i32 = 30;
const W: i32 = 560;

const PANEL_A: u8 = 232;
const NAME = rgba(226, 214, 188, 255);
const NAME_OFF = rgba(150, 140, 122, 255);
const COIN_OK = rgba(238, 216, 158, 255);
const COIN_NO = rgba(176, 96, 78, 255);
const SAID = rgba(198, 186, 160, 255);

pub const RAISE: f32 = 0.16;

fn title(t: counter.Trade, selling: bool) [:0]const u8 {
    return switch (t) {
        .shop => if (selling) "What will you give me?" else "What can I sell you?",
        .smithy => "Bring me stone and I will work",
    };
}

/// The one line the panel says back after a press. **EVERY REFUSAL SAYS WHY** — a button that does nothing and
/// explains nothing is one the player decides is broken.
fn saidLine(s: counter.Counter.Said, t: counter.Trade) [:0]const u8 {
    return switch (s) {
        .none => "",
        .bought => "Taken.",
        .sold => "Sold.",
        .forged => "Held in the fire, and folded.",
        .no_coin => "Not enough gold.",
        .no_stones => "I need smithing stone for that.",
        .maxed => "There is nothing more I can do to it.",
        .nothing => if (t == .shop) "You have nothing I want." else "Nothing to work on.",
    };
}

/// **WHAT A ROW IS CALLED.** A shop row is an item; a smithy row is a hand and the tier it is on, which is the
/// number the player is actually buying.
fn rowLabel(buf: []u8, r: counter.Row, h: *const heromod.Hero) [:0]const u8 {
    if (r.kind) |k| return std.fmt.bufPrintZ(buf, "{s}", .{item.displayName(k)}) catch "?";
    const a = r.arm orelse return "?";
    const t = h.tierOf(a);
    if (r.done) return std.fmt.bufPrintZ(buf, "{s}  +{d}  (finished)", .{ @tagName(a), t }) catch "?";
    return std.fmt.bufPrintZ(buf, "{s}  +{d} -> +{d}", .{ @tagName(a), t, t + 1 }) catch "?";
}

pub fn draw(c: *const counter.Counter, h: *const heromod.Hero, bag: *const item.Bag, t: f32) void {
    if (!c.open) return;
    var buf: [counter.MAX_ROWS]counter.Row = undefined;
    const list = c.rows(h, bag, &buf);
    const rows: i32 = @intCast(@max(list.len, 1));
    const height = HEAD_H + rows * ROW_H + FOOT_H;

    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const raise = mathx.smoothstep(0, RAISE, t);
    const x = @divTrunc(sw - W, 2);
    const y = @divTrunc(sh - height, 2) + @as(i32, @intFromFloat((1.0 - raise) * 26.0));

    rl.drawRectangle(0, 0, sw, sh, rgba(0, 0, 0, uiart.flick(96, 0)));
    uiart.plate(x, y, W, height, PANEL_A);
    uiart.frame(x, y, W, height, 220);
    hud.text(title(c.trade, c.selling), x + PAD, y + 14, hud.BODY, NAME);

    // **THE PURSE IS ON THE PANEL**, because the HUD's own plates are behind it and a shop you cannot read your
    // gold on is a shop you have to close to make a decision.
    var pb: [48]u8 = undefined;
    const purse = std.fmt.bufPrintZ(&pb, "{d}", .{h.gold.display()}) catch "0";
    uiart.coinMark(uiart.fi(x + W - PAD - 86), uiart.fi(y + 22), uiart.MARK_R, 240);
    hud.text(purse, x + W - PAD - hud.textW(purse, hud.BODY), y + 14, hud.BODY, COIN_OK);
    if (c.trade == .smithy) {
        var sb: [48]u8 = undefined;
        const st = std.fmt.bufPrintZ(&sb, "stone x{d}", .{bag.count(counter.STONE)}) catch "";
        hud.mono(st, x + PAD, y + 40, hud.MONO, uiart.GILT_DIM);
    }

    // **AN EMPTY LIST SAYS SO.** Only the SELL side can be empty (`STOCK` and `FORGEABLE` never are), and an
    // empty plate with a button strip under it reads as a screen that failed to load rather than as a bag with
    // nothing in it worth coin.
    if (list.len == 0) {
        hud.text(
            if (c.selling) "Nothing in your bag is worth coin to me." else "Nothing on the shelf today.",
            x + PAD + 8,
            y + HEAD_H,
            hud.BODY,
            NAME_OFF,
        );
    }

    var i: usize = 0;
    while (i < list.len) : (i += 1) {
        const r = list[i];
        const ry = y + HEAD_H + @as(i32, @intCast(i)) * ROW_H;
        const on = i == @min(c.sel, list.len - 1);
        if (on) uiart.rowHilite(x + PAD - 6, ry - 3, W - 2 * PAD + 12, ROW_H - 2);
        uiart.caret(x + PAD - 12, ry, ROW_H - 6, if (on) 235 else 0);

        var lb: [64]u8 = undefined;
        hud.text(rowLabel(&lb, r, h), x + PAD + 8, ry, hud.BODY, if (r.done) NAME_OFF else NAME);

        if (!r.done) {
            var cb: [48]u8 = undefined;
            const cost = if (r.stones > 0)
                std.fmt.bufPrintZ(&cb, "{d} stone   {d}", .{ r.stones, r.coin }) catch ""
            else
                std.fmt.bufPrintZ(&cb, "{d}", .{r.coin}) catch "";
            const afford = h.gold.total >= r.coin and (r.stones == 0 or bag.count(counter.STONE) >= r.stones);
            // Selling shows what he is PAID, which is never unaffordable.
            const col = if (c.selling or afford) COIN_OK else COIN_NO;
            hud.text(cost, x + W - PAD - hud.textW(cost, hud.BODY), ry, hud.BODY, col);
        }
        // How many he already holds, for the shop only — a shelf without it is one you buy a fourth of.
        if (r.kind) |k| {
            const n = bag.count(k);
            if (n > 0) {
                var nb: [24]u8 = undefined;
                const have = std.fmt.bufPrintZ(&nb, "x{d}", .{n}) catch "";
                hud.mono(have, x + W - PAD - 120, ry + 4, hud.MONO, uiart.GILT_DIM);
            }
        }
    }

    const said = saidLine(c.said, c.trade);
    if (said.len > 0) hud.text(said, x + PAD, y + height - FOOT_H - 4, hud.HINT, SAID);

    // The button strip, in the house's own pictograms — no key captions anywhere in the GAME (AGENTS.md).
    var hints: [3]hud.Hint = undefined;
    var nh: usize = 0;
    hints[nh] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = if (c.trade == .smithy) "Forge" else if (c.selling) "Sell" else "Buy" };
    nh += 1;
    if (c.trade == .shop) {
        hints[nh] = .{ .glyph = .{ .face = hud.BTN_QUICK }, .label = if (c.selling) "Buy list" else "Sell list" };
        nh += 1;
    }
    hints[nh] = .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Leave" };
    nh += 1;
    hud.hintRowAt(hints[0..nh], x + PAD, y + height - FOOT_H + 16, hud.HINT, uiart.GILT_DIM);
}
