const std = @import("std");
const rl = @import("raylib");
const wf = @import("../world/worldfmt.zig");
const mathx = @import("../core/mathx.zig");
const hud = @import("../ui/hud.zig");
const uiart = @import("../ui/uiart.zig");
const itemart = @import("../ui/itemart.zig");
const item = @import("item.zig");

const rgba = mathx.rgba;


/// How many first-time cards may be queued at once. `wf.MAX_LOOT` is the real bound — one chest cannot hand over more than it holds — and the queue only ever holds the NEW kinds out of one award.
pub const CARD_CAP: usize = 12;
pub const TOAST_CAP: usize = 5;

comptime {
    // ONE CONTAINER CAN NEVER FILL THE QUEUE. Past this the first-time card for something in the same chest would have to wait for a dismissal, which `gain` handles safely.
    std.debug.assert(CARD_CAP > wf.MAX_LOOT);
}

pub const TOAST_LIFE: f32 = 3.4;
const TOAST_IN: f32 = 0.22;
const TOAST_OUT: f32 = 0.45;

const TOAST_W: i32 = 268;
const TOAST_H: i32 = 46;
const TOAST_GAP: i32 = 6;
const TOAST_MARGIN: i32 = 18;
const TOAST_TOP: i32 = 132;

const CARD_W: i32 = 520;
const CARD_H: i32 = 300;
const PIC_BOX: i32 = 96;
const PIC_PX: f32 = 74.0;

/// A toast that is standing. `t` counts UP from the moment it was made, which is what both the slide and the fade are read off — one clock, so the two cannot disagree about when it is leaving.
const Toast = struct {
    kind: item.Kind = .crimson_flask,
    n: u16 = 1,
    t: f32 = 0,
    /// **NON-ZERO MAKES IT A PURSE AND NOT A THING** (`COIN_NAME`). Coin is the one drop with no `item.Kind`
    /// behind it — it never enters the bag — so it rides the strip on its own field rather than as a fake row
    /// in `item`, and `kind` means nothing on this toast.
    coin: u32 = 0,
};

/// What a purse on the ground is called, spelled once so the strip and anything after it cannot disagree.
pub const COIN_NAME: [:0]const u8 = "Pile of Coins";

const Card = struct {
    kind: item.Kind = .crimson_flask,
    n: u16 = 1,
};

pub const Award = struct {
    seen: [item.NK]bool = [_]bool{false} ** item.NK,

    cards: [CARD_CAP]Card = undefined,
    ncards: usize = 0,
    toasts: [TOAST_CAP]Toast = undefined,
    ntoasts: usize = 0,

    pub fn gain(self: *Award, k: item.Kind) void {
        const i = @intFromEnum(k);
        if (!self.seen[i]) {
            // **SEEN IS SET ONLY IF THE CARD IS ACTUALLY QUEUED.** Marked first and then dropped on a full queue, the kind would be silently discovered and its one first-time card LOST for the run. One container cannot fill the queue, but two opened before a single dismissal can, so the order matters.
            if (self.ncards >= CARD_CAP) return;
            self.seen[i] = true;
            self.cards[self.ncards] = .{ .kind = k, .n = 1 };
            self.ncards += 1;
            return;
        }
        for (self.cards[0..self.ncards]) |*c| {
            if (c.kind != k) continue;
            c.n += 1;
            return;
        }
        for (self.toasts[0..self.ntoasts]) |*t| {
            if (t.kind != k) continue;
            t.n += 1;
            t.t = 0;
            return;
        }
        self.push(.{ .kind = k, .n = 1, .t = 0 });
    }

    /// THE OLDEST GOES when the stack is full: a notice you cannot see because five newer ones are over it is worse than one that never appeared, and the newest is always the one being explained.
    fn push(self: *Award, t: Toast) void {
        if (self.ntoasts >= TOAST_CAP) {
            var i: usize = 1;
            while (i < self.ntoasts) : (i += 1) self.toasts[i - 1] = self.toasts[i];
            self.ntoasts -= 1;
        }
        self.toasts[self.ntoasts] = t;
        self.ntoasts += 1;
    }

    /// **A PURSE TOASTS, IT DOES NOT CARD.** There is no first-time card for money — nothing about the tenth
    /// pile is different from the first, and a modal over a running fight for 30 coin is an interruption and
    /// not news. Merges into the purse already standing rather than stacking a strip of them off one fight.
    pub fn gainCoin(self: *Award, n: u32) void {
        if (n == 0) return;
        for (self.toasts[0..self.ntoasts]) |*t| {
            if (t.coin == 0) continue;
            t.coin += n;
            t.t = 0;
            return;
        }
        if (self.ntoasts >= TOAST_CAP) {
            std.mem.copyForwards(Toast, self.toasts[0 .. TOAST_CAP - 1], self.toasts[1..TOAST_CAP]);
            self.ntoasts = TOAST_CAP - 1;
        }
        self.toasts[self.ntoasts] = .{ .coin = n };
        self.ntoasts += 1;
    }

    pub fn carding(self: *const Award) bool {
        return self.ncards > 0;
    }

    pub fn front(self: *const Award) ?item.Kind {
        if (self.ncards == 0) return null;
        return self.cards[0].kind;
    }

    pub fn frontCount(self: *const Award) u16 {
        if (self.ncards == 0) return 0;
        return self.cards[0].n;
    }

    pub fn dismiss(self: *Award) void {
        if (self.ncards == 0) return;
        var i: usize = 1;
        while (i < self.ncards) : (i += 1) self.cards[i - 1] = self.cards[i];
        self.ncards -= 1;
    }

    pub fn update(self: *Award, dt: f32) void {
        var i: usize = 0;
        while (i < self.ntoasts) {
            self.toasts[i].t += dt;
            if (self.toasts[i].t >= TOAST_LIFE + TOAST_OUT) {
                var j = i + 1;
                while (j < self.ntoasts) : (j += 1) self.toasts[j - 1] = self.toasts[j];
                self.ntoasts -= 1;
                continue;
            }
            i += 1;
        }
    }

    pub fn clearPending(self: *Award) void {
        self.ncards = 0;
        self.ntoasts = 0;
    }

    pub fn markKnown(self: *Award, k: item.Kind) void {
        self.seen[@intFromEnum(k)] = true;
    }


    pub fn drawToasts(self: *const Award) void {
        if (self.carding()) return;
        const sw = rl.getScreenWidth();
        var y = TOAST_TOP;
        for (self.toasts[0..self.ntoasts]) |*t| {
            const inK = mathx.smoothstep(0, TOAST_IN, t.t);
            const outK = 1.0 - mathx.smoothstep(TOAST_LIFE, TOAST_LIFE + TOAST_OUT, t.t);
            const a = mathx.u8f(235.0 * outK);
            const slide: i32 = @intFromFloat((1.0 - inK) * @as(f32, @floatFromInt(TOAST_W + TOAST_MARGIN)));
            const x = sw - TOAST_W - TOAST_MARGIN + slide;
            uiart.plate(x, y, TOAST_W, TOAST_H, mathx.u8f(212.0 * outK));
            uiart.frame(x, y, TOAST_W, TOAST_H, a);
            const ny = y + @divTrunc(TOAST_H - hud.lineH(hud.TINY), 2);
            if (t.coin > 0) {
                uiart.coinMark(@floatFromInt(x + 26), @floatFromInt(y + @divTrunc(TOAST_H, 2)), uiart.MARK_R, a);
                hud.text(COIN_NAME, x + 50, ny, hud.TINY, mathx.withAlpha(uiart.GILT, a));
                var gb: [16]u8 = undefined;
                const amt = std.fmt.bufPrintZ(&gb, "{d}g", .{t.coin}) catch "";
                hud.text(amt, x + TOAST_W - 18 - hud.textW(amt, hud.TINY), ny, hud.TINY, mathx.withAlpha(uiart.GILT_BRIGHT, a));
                y += TOAST_H + TOAST_GAP;
                continue;
            }
            itemart.draw(t.kind, @floatFromInt(x + 26), @floatFromInt(y + @divTrunc(TOAST_H, 2)), 30.0);
            const name = item.displayName(t.kind);
            hud.text(name, x + 50, ny, hud.TINY, mathx.withAlpha(uiart.GILT, a));
            if (t.n > 1) {
                var buf: [12]u8 = undefined;
                const s = std.fmt.bufPrintZ(&buf, "x{d}", .{t.n}) catch "";
                hud.text(s, x + TOAST_W - 18 - hud.textW(s, hud.TINY), ny, hud.TINY, mathx.withAlpha(uiart.GILT_BRIGHT, a));
            }
            y += TOAST_H + TOAST_GAP;
        }
    }


    var proseBuf: [512]u8 = undefined;
    var proseLines: [8][:0]const u8 = undefined;

    pub fn drawCard(self: *const Award) void {
        const k = self.front() orelse return;
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        rl.drawRectangle(0, 0, sw, sh, rgba(6, 5, 4, 168));

        const x = @divTrunc(sw - CARD_W, 2);
        const y = @divTrunc(sh - CARD_H, 2);
        uiart.seat(x, y, CARD_W, CARD_H);
        uiart.plate(x, y, CARD_W, CARD_H, 240);
        uiart.frame(x, y, CARD_W, CARD_H, 210);

        const px = x + 34;
        const py = y + 40;
        uiart.well(px, py, PIC_BOX, PIC_BOX, 210);
        itemart.draw(k, @floatFromInt(px + @divTrunc(PIC_BOX, 2)), @floatFromInt(py + @divTrunc(PIC_BOX, 2)), PIC_PX);

        const tx = px + PIC_BOX + 26;
        hud.text(item.displayName(k), tx, py + 2, hud.BODY, uiart.GILT_BRIGHT);
        const n = self.frontCount();
        if (n > 1) {
            var nbuf: [12]u8 = undefined;
            const ns = std.fmt.bufPrintZ(&nbuf, "x{d}", .{n}) catch "";
            hud.text(ns, tx + hud.textW(item.displayName(k), hud.BODY) + 12, py + 2, hud.BODY, uiart.GILT_BRIGHT);
        }
        hud.text(item.class(k).label(), tx, py + 4 + hud.lineH(hud.BODY), hud.SMALL, uiart.GILT_DIM);

        uiart.divider(x + @divTrunc(CARD_W, 2), py + PIC_BOX + 18, @divTrunc(CARD_W, 2) - 40, 170);

        const proseW = CARD_W - 68;
        const lines = hud.wrap(item.describe(k), hud.SMALL, proseW, &proseBuf, &proseLines);
        var ly = py + PIC_BOX + 34;
        for (lines) |ln| {
            hud.text(ln, x + 34, ly, hud.SMALL, uiart.TEXT_VALUE);
            ly += hud.lineH(hud.SMALL);
        }

        var foot: [48]u8 = undefined;
        const s: [:0]const u8 = if (self.ncards > 1)
            std.fmt.bufPrintZ(&foot, "Any key  -  {d} more", .{self.ncards - 1}) catch "Any key"
        else
            "Any key";
        hud.text(s, x + @divTrunc(CARD_W - hud.textW(s, hud.HINT), 2), y + CARD_H - 32, hud.HINT, uiart.GILT_DIM);
    }
};

test "a NEW kind cards and does not toast; a SEEN one toasts and does not card" {
    var a = Award{};
    a.gain(.mushroom_jerky);
    try std.testing.expect(a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ncards);
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
    try std.testing.expectEqual(item.Kind.mushroom_jerky, a.front().?);

    a.dismiss();
    try std.testing.expect(!a.carding());
    a.gain(.mushroom_jerky);
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts);
}

test "SEVERAL NEW KINDS QUEUE, and they are read in the order they were found" {
    var a = Award{};
    a.gain(.mushroom_jerky);
    a.gain(.nameless_soul);
    a.gain(.iron_key);
    try std.testing.expectEqual(@as(usize, 3), a.ncards);
    try std.testing.expectEqual(item.Kind.mushroom_jerky, a.front().?);
    a.dismiss();
    try std.testing.expectEqual(item.Kind.nameless_soul, a.front().?);
    a.dismiss();
    try std.testing.expectEqual(item.Kind.iron_key, a.front().?);
    a.dismiss();
    try std.testing.expect(!a.carding());
}

test "A REPEAT IS A COUNT ON ONE TOAST, and it refreshes rather than stacking" {
    var a = Award{};
    a.seen[@intFromEnum(item.Kind.nameless_soul)] = true;
    a.gain(.nameless_soul);
    a.update(1.0);
    a.gain(.nameless_soul);
    a.gain(.nameless_soul);
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts);
    try std.testing.expectEqual(@as(u16, 3), a.toasts[0].n);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.toasts[0].t, 1e-6);
}

test "TOASTS EXPIRE, and a full stack drops its OLDEST rather than refusing the newest" {
    var a = Award{};
    for (0..item.NK) |i| a.seen[i] = true;
    const kinds = [_]item.Kind{ .crimson_flask, .cerulean_flask, .rune_arc, .golden_seed, .smithing_stone, .bloodgrass, .kobold_fang };
    for (kinds) |k| a.gain(k);
    try std.testing.expectEqual(TOAST_CAP, a.ntoasts);
    try std.testing.expectEqual(item.Kind.kobold_fang, a.toasts[a.ntoasts - 1].kind);
    for (a.toasts[0..a.ntoasts]) |t| try std.testing.expect(t.kind != .crimson_flask);
    var t: f32 = 0;
    while (t < TOAST_LIFE + TOAST_OUT + 0.2) : (t += 1.0 / 60.0) a.update(1.0 / 60.0);
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
}

test "EVERY TOAST IS TICKED even when one in front of it expires the same frame" {
    var a = Award{};
    for (0..item.NK) |i| a.seen[i] = true;
    a.gain(.rune_arc);
    a.gain(.golden_seed);
    a.gain(.iron_key);
    try std.testing.expectEqual(@as(usize, 3), a.ntoasts);
    a.update(TOAST_LIFE + TOAST_OUT + 0.01);
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
}

test "A FULL CARD QUEUE DOES NOT SILENTLY DISCOVER — the kind cards next time instead" {
    var a = Award{};
    var n: usize = 0;
    while (n < CARD_CAP) : (n += 1) a.gain(@enumFromInt(n));
    try std.testing.expectEqual(CARD_CAP, a.ncards);
    const spare: item.Kind = @enumFromInt(CARD_CAP);
    a.gain(spare);
    try std.testing.expect(!a.seen[@intFromEnum(spare)]);
    try std.testing.expectEqual(CARD_CAP, a.ncards);
    a.dismiss();
    a.gain(spare);
    try std.testing.expect(a.seen[@intFromEnum(spare)]);
    try std.testing.expectEqual(spare, a.cards[a.ncards - 1].kind);
}

test "SEVERAL OF ONE NEW KIND IS ONE CARD SAYING x3, never a card and a toast under it" {
    var a = Award{};
    a.gain(.nameless_soul);
    a.gain(.nameless_soul);
    a.gain(.nameless_soul);
    try std.testing.expectEqual(@as(usize, 1), a.ncards);
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
    try std.testing.expectEqual(@as(u16, 3), a.frontCount());
    a.dismiss();
    try std.testing.expectEqual(@as(u16, 0), a.frontCount());
    a.gain(.nameless_soul);
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts);
}

test "ONE HANDFUL IS ONE NOTICE AT A TIME — a mixed chest holds its toast back behind the card" {
    var a = Award{};
    a.seen[@intFromEnum(item.Kind.nameless_soul)] = true;
    a.gain(.mushroom_jerky);
    a.gain(.nameless_soul);
    try std.testing.expect(a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.toasts[0].t, 1e-6);
    a.dismiss();
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts);
}

test "a copy arriving while ANOTHER kind's card is in front of it still lands on its own card" {
    var a = Award{};
    a.gain(.mushroom_jerky);
    a.gain(.nameless_soul);
    a.gain(.mushroom_jerky);
    try std.testing.expectEqual(@as(usize, 2), a.ncards);
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
    try std.testing.expectEqual(item.Kind.mushroom_jerky, a.front().?);
    try std.testing.expectEqual(@as(u16, 2), a.frontCount());
    a.dismiss();
    try std.testing.expectEqual(item.Kind.nameless_soul, a.front().?);
    try std.testing.expectEqual(@as(u16, 1), a.frontCount());
}

test "WHAT HE STARTED WITH IS NOT A DISCOVERY" {
    var a = Award{};
    a.markKnown(.crimson_flask);
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
    a.gain(.crimson_flask);
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts);
}

test "the pending notices clear without un-discovering anything" {
    var a = Award{};
    a.gain(.golden_seed);
    a.seen[@intFromEnum(item.Kind.iron_key)] = true;
    a.gain(.iron_key);
    try std.testing.expect(a.carding() and a.ntoasts == 1);
    a.clearPending();
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
    try std.testing.expect(a.seen[@intFromEnum(item.Kind.golden_seed)]);
    try std.testing.expect(a.seen[@intFromEnum(item.Kind.iron_key)]);
}
