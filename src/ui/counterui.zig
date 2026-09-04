const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const itemart = @import("itemart.zig");
const item = @import("../play/item.zig");
const heromod = @import("../play/hero.zig");
const counter = @import("../play/counter.zig");
const dialogmod = @import("../world/dialog.zig");
const book = @import("book.zig");

const rgba = mathx.rgba;
const fi = uiart.fi;


const PAD: i32 = 18;
const ROW_H: i32 = 34;
const HEAD_H: i32 = 58;
/// THE FOOT IS TWO LINES, NOT ONE: what he said and the hints are both drawn from `x + PAD`.
const FOOT_GAP: i32 = 6;
const FOOT_H: i32 = hud.lineH(hud.HINT) * 2 + FOOT_GAP + 4;
const W: i32 = 700;
const PORT_W = dialogmod.PORT_W;
const PORT_H = dialogmod.PORT_H;
const PORT_GAP = dialogmod.PORT_GAP;
const CARD_PAD: i32 = 10;
const CARD_NAME_Y: i32 = CARD_PAD;
const CARD_LINE_Y: i32 = CARD_NAME_Y + hud.lineH(hud.BODY);
const CARD_PROSE_Y: i32 = CARD_LINE_Y + hud.lineH(hud.MONO);
const CARD_PROSE_LINES: usize = 2;
const CARD_H: i32 = CARD_PROSE_Y + hud.lineH(hud.HINT) * @as(i32, CARD_PROSE_LINES) + CARD_PAD;
const VIS_ROWS: usize = 9;
const ROW_ART: f32 = 20;
const CARD_ART: f32 = 46;

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

const MASTERED_LINE = "There is nothing more I can do to it.";

fn saidLine(s: counter.Counter.Said, t: counter.Trade) [:0]const u8 {
    return switch (s) {
        .none => "",
        .bought => "Taken.",
        .sold => "Sold.",
        .forged => "Held in the fire, and folded.",
        .no_coin => "Not enough gold.",
        .no_stones => "I need smithing stone for that.",
        .maxed => MASTERED_LINE,
        .nothing => if (t == .shop) "You have nothing I want." else "Nothing to work on.",
    };
}

fn tierGain(a: heromod.Armament, h: *const heromod.Hero) f32 {
    const w = heromod.wearFor(a) orelse return 0;
    const row = heromod.armRow(h.worn, w);
    const t = h.tierOf(a);
    const now = heromod.weigh(heromod.ATK_LIGHT_HIT, row, h.sheet, t).dmg;
    const next = heromod.weigh(heromod.ATK_LIGHT_HIT, row, h.sheet, t + 1).dmg;
    return next - now;
}

fn tierPips(x: i32, cy: i32, tier: u8, r: f32) void {
    var p: u8 = 0;
    while (p < heromod.TIER_MAX) : (p += 1) {
        const px = fi(x) + fi(p) * (r * 2.0 + 2.6);
        if (p < tier) {
            uiart.diamond(px, fi(cy), r, mathx.withAlpha(uiart.GILT, 235));
        } else {
            uiart.diamond(px, fi(cy), r * 0.72, mathx.withAlpha(uiart.GILT_DIM, 96));
        }
    }
}

fn pipsW(r: f32) i32 {
    return @intFromFloat(fi(heromod.TIER_MAX) * (r * 2.0 + 2.6));
}

const Mark = enum { coin, stone };

fn priceBlock(right: i32, cy: i32, n: u32, col: rl.Color, mark: Mark) i32 {
    var b: [24]u8 = undefined;
    const s = std.fmt.bufPrintZ(&b, "{d}", .{n}) catch "0";
    const tw = hud.textW(s, hud.BODY);
    hud.text(s, right - tw, cy, hud.BODY, col);
    switch (mark) {
        .coin => uiart.coinMark(fi(right - tw - 13), fi(cy + 11), uiart.MARK_R * 0.92, col.a),
        .stone => itemart.draw(counter.STONE, fi(right - tw - 13), fi(cy + 11), 17),
    }
    return right - tw - 26;
}

pub fn draw(c: *const counter.Counter, h: *const heromod.Hero, bag: *const item.Bag, t: f32, port: ?dialogmod.Portrait) void {
    if (!c.open) return;
    var buf: [counter.MAX_ROWS]counter.Row = undefined;
    const list = c.rows(h, bag, &buf);
    const len = list.len;
    const sel = if (len == 0) 0 else @min(c.sel, len - 1);
    const vis = @min(len, VIS_ROWS);
    const shown: i32 = @intCast(@max(vis, 3));

    const hasPort = port != null;
    var listH = shown * ROW_H + 10;
    if (hasPort) listH = @max(listH, PORT_H + 10);
    const height = HEAD_H + listH + CARD_H + FOOT_H + 8;

    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const raise = mathx.smoothstep(0, RAISE, t);
    const x = @divTrunc(sw - W, 2);
    const y = @divTrunc(sh - height, 2) + @as(i32, @intFromFloat((1.0 - raise) * 26.0));

    rl.drawRectangle(0, 0, sw, sh, rgba(0, 0, 0, uiart.flick(96, 0)));
    uiart.plate(x, y, W, height, PANEL_A);
    uiart.frame(x, y, W, height, 220);

    hud.engraved(title(c.trade, c.selling), x + PAD, y + 13, hud.BODY, NAME);
    const right = priceBlock(x + W - PAD, y + 13, h.gold.display(), COIN_OK, .coin);
    if (c.trade == .smithy) _ = priceBlock(right - 14, y + 13, bag.count(counter.STONE), mathx.withAlpha(NAME, 235), .stone);
    uiart.divider(x + @divTrunc(W, 2), y + HEAD_H - 8, @divTrunc(W - PAD * 2, 2), 220);

    const ly = y + HEAD_H + 4;
    const lx = if (hasPort) x + PAD + PORT_W + PORT_GAP else x + PAD;
    const lw = x + W - PAD - lx;
    if (hasPort) dialogmod.drawPortrait(port.?, x + PAD, ly, PORT_W, @min(PORT_H, listH - 8));

    if (len == 0) {
        hud.text(
            if (c.selling) "Nothing in your bag is worth coin to me." else "Nothing on the shelf today.",
            lx + 8,
            ly + 10,
            hud.BODY,
            NAME_OFF,
        );
    }

    const first = if (len <= VIS_ROWS) 0 else @min(sel -| VIS_ROWS / 2, len - VIS_ROWS);
    var i: usize = first;
    while (i < first + vis) : (i += 1) {
        const r = list[i];
        const ry = ly + @as(i32, @intCast(i - first)) * ROW_H;
        const on = i == sel;
        if (on) uiart.rowHilite(lx - 8, ry - 2, lw + 10, ROW_H - 4);
        const rx = lx + (if (on) @as(i32, 6) else 0);
        const cyMid = ry + @divTrunc(ROW_H, 2) - 2;

        if (r.kind) |k| {
            itemart.draw(k, fi(rx + 12), fi(cyMid), ROW_ART);
            const nm = item.displayName(k);
            hud.text(nm, rx + 30, ry + 4, hud.BODY, if (r.done) NAME_OFF else NAME);
            const n = bag.count(k);
            if (n > 0) {
                var nb: [24]u8 = undefined;
                const have = std.fmt.bufPrintZ(&nb, "x{d}", .{n}) catch "";
                hud.mono(have, rx + 34 + hud.textW(nm, hud.BODY), ry + 8, hud.MONO, uiart.GILT_DIM);
            }
        } else if (r.arm) |a| {
            itemart.heldArt(book.armPic(a), heromod.heldGear(a, h.worn), fi(rx + 12), fi(cyMid), ROW_ART);
            const nm = book.armName(a);
            hud.text(nm, rx + 30, ry + 4, hud.BODY, if (r.done) NAME_OFF else NAME);
            tierPips(rx + 38 + hud.textW(nm, hud.BODY), cyMid, h.tierOf(a), 2.6);
        }

        if (r.done) {
            hud.text("mastered", x + W - PAD - hud.textW("mastered", hud.HINT), ry + 6, hud.HINT, NAME_OFF);
        } else {
            const affordCoin = c.selling or h.gold.total >= r.coin;
            const cright = priceBlock(x + W - PAD, ry + 4, r.coin, if (affordCoin) COIN_OK else COIN_NO, .coin);
            if (r.stones > 0) {
                const hasStones = bag.count(counter.STONE) >= r.stones;
                _ = priceBlock(cright - 10, ry + 4, r.stones, if (hasStones) mathx.withAlpha(NAME, 225) else COIN_NO, .stone);
            }
        }
    }
    if (len > VIS_ROWS) {
        uiart.rail(
            x + W - 11,
            ly,
            @as(i32, @intCast(vis)) * ROW_H,
            fi(@intCast(vis)) / fi(@intCast(len)),
            fi(@intCast(first)) / fi(@intCast(len - VIS_ROWS)),
        );
    }

    const cy = y + HEAD_H + listH + 2;
    uiart.well(x + PAD, cy, W - PAD * 2, CARD_H, 205);
    if (len > 0) drawCard(list[sel], h, x + PAD, cy);

    const said = saidLine(c.said, c.trade);
    if (said.len > 0) {
        hud.text(said, x + PAD, y + height - FOOT_H, hud.HINT, if (counter.Counter.refused(c.said)) COIN_NO else SAID);
    }

    var hints: [4]hud.Hint = undefined;
    var nh: usize = 0;
    if (len > 1) {
        hints[nh] = hud.HINT_CHOOSE;
        nh += 1;
    }
    hints[nh] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = if (c.trade == .smithy) "Forge" else if (c.selling) "Sell" else "Buy" };
    nh += 1;
    if (c.trade == .shop) {
        hints[nh] = .{ .glyph = .{ .face = hud.BTN_QUICK }, .label = if (c.selling) "Buy list" else "Sell list" };
        nh += 1;
    }
    hints[nh] = .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Leave" };
    nh += 1;
    hud.hintRowAt(hints[0..nh], x + PAD, y + height - @divTrunc(hud.lineH(hud.HINT), 2) - 4, hud.HINT, uiart.GILT_DIM);
}

fn drawCard(r: counter.Row, h: *const heromod.Hero, cx: i32, cy: i32) void {
    const cell = CARD_H - 24;
    uiart.slot(cx + 12, cy + 12, cell, cell, true);
    const tx = cx + 12 + cell + 16;
    const tw = W - PAD * 2 - (12 + cell + 16) - 14;

    if (r.kind) |k| {
        itemart.draw(k, fi(cx + 12 + @divTrunc(cell, 2)), fi(cy + 12 + @divTrunc(cell, 2)), CARD_ART);
        hud.text(item.displayName(k), tx, cy + CARD_NAME_Y, hud.BODY, NAME);
        var eb: [item.EFFECT_BUF]u8 = undefined;
        hud.mono(item.effect(k, &eb), tx, cy + CARD_LINE_Y, hud.MONO, uiart.TEXT_VALUE);
        proseClipped(item.describe(k), tx, cy + CARD_PROSE_Y, tw, CARD_PROSE_LINES);
    } else if (r.arm) |a| {
        itemart.heldArt(book.armPic(a), heromod.heldGear(a, h.worn), fi(cx + 12 + @divTrunc(cell, 2)), fi(cy + 12 + @divTrunc(cell, 2)), CARD_ART);
        const t = h.tierOf(a);
        var nb: [48]u8 = undefined;
        const nm = std.fmt.bufPrintZ(&nb, "{s}  +{d}", .{ book.armName(a), t }) catch "?";
        hud.text(nm, tx, cy + CARD_NAME_Y, hud.BODY, NAME);
        tierPips(tx, cy + CARD_LINE_Y + @divTrunc(hud.lineH(hud.MONO), 2), t, 3.2);
        if (r.done) {
            hud.text(MASTERED_LINE, tx, cy + CARD_PROSE_Y, hud.HINT, NAME_OFF);
        } else {
            var gb: [64]u8 = undefined;
            const gain = std.fmt.bufPrintZ(&gb, "damage +{d:.1} a stroke", .{tierGain(a, h)}) catch "";
            hud.mono(gain, tx + pipsW(3.2) + 18, cy + CARD_LINE_Y, hud.MONO, uiart.GOOD);
            proseClipped("Stone is the gate and coin is the tax; the edge keeps what the fire teaches it.", tx, cy + CARD_PROSE_Y, tw, 1);
        }
    }
}

fn proseClipped(s: []const u8, x: i32, y: i32, w: i32, maxLines: usize) void {
    const lines = hud.proseWrap(s, w, hud.HINT);
    const n = @min(lines.len, maxLines);
    var i: usize = 0;
    var yy = y;
    while (i < n) : (i += 1) {
        hud.text(lines[i], x, yy, hud.HINT, uiart.TEXT_DIM);
        if (i + 1 == n and lines.len > n) {
            hud.text("...", x + hud.textW(lines[i], hud.HINT) + 4, yy, hud.HINT, uiart.TEXT_DIM);
        }
        yy += hud.lineH(hud.HINT);
    }
}

test "NOTHING ON THE COUNTER IS DRAWN OVER ANYTHING ELSE — every band solved off the type scale" {
    const said = [2]i32{ FOOT_H - 0, FOOT_H - hud.lineH(hud.HINT) };
    const hintsTop = @divTrunc(hud.lineH(hud.HINT), 2) + 4 + @divTrunc(hud.lineH(hud.HINT), 2);
    // Both are measured UP from the panel's bottom edge, so the said line's floor must sit above the hints' ceiling.
    try std.testing.expect(said[1] > hintsTop);

    const bands = [_]struct { top: i32, h: i32 }{
        .{ .top = CARD_NAME_Y, .h = hud.lineH(hud.BODY) },
        .{ .top = CARD_LINE_Y, .h = hud.lineH(hud.MONO) },
        .{ .top = CARD_PROSE_Y, .h = hud.lineH(hud.HINT) * @as(i32, CARD_PROSE_LINES) },
    };
    for (bands[0 .. bands.len - 1], bands[1..]) |a, b| try std.testing.expect(a.top + a.h <= b.top);
    const last = bands[bands.len - 1];
    try std.testing.expect(last.top + last.h + CARD_PAD <= CARD_H);
    try std.testing.expect(12 + (CARD_H - 24) <= CARD_H);

    // The widest thing a row has to fit between its picture and its price, in characters.
    var widest: usize = 0;
    for (std.enums.values(item.Kind)) |k| widest = @max(widest, item.displayName(k).len);
    const lx = PAD + PORT_W + PORT_GAP;
    const field = W - PAD - lx - 30 - 26;
    std.debug.print(
        "\n  counter foot: said {d}..{d} px up from the sill, hints to {d} — {d} px clear\n" ++
            "  counter card: name {d}, line {d}, prose {d}x{d}, well {d} px deep\n" ++
            "  counter row: {d} px of name field beside a portrait for the widest of {d} names ({d} chars)\n",
        .{
            said[1],           said[0],           hintsTop,          said[1] - hintsTop,
            CARD_NAME_Y,       CARD_LINE_Y,       CARD_PROSE_Y,      CARD_PROSE_LINES,
            CARD_H,            field,             std.enums.values(item.Kind).len,
            widest,
        },
    );
}
