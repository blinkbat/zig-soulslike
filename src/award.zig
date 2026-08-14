const std = @import("std");
const rl = @import("raylib");
const wf = @import("worldfmt.zig");
const mathx = @import("mathx.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const itemart = @import("itemart.zig");
const item = @import("item.zig");

const rgba = mathx.rgba;

// **WHAT YOU JUST GOT, AND THE TWO WAYS IT IS SAID** (owner's call):
//
//  1. **THE FIRST TIME** a kind reaches your hands, the game STOPS and shows it to you — name, picture,
//     description, any key to close. More than one new kind in the same chest means one card after another, and
//     the world starts again on the last dismissal. It is the one moment a new thing is worth reading about,
//     and reading is not something you do while a kobold is behind you.
//  2. **EVERY TIME AFTER**, a TOAST on the right and nothing else. No pause, no card, no reading: you know what
//     a Mushroom Jerky is, so all you need is confirmation that one went in the bag. They STACK, because a
//     chest hands over three at once and three notices that overwrote each other would say "one item".
//
// **THE DISCOVERY SET IS THE WHOLE MECHANISM.** One bit per kind, and the ONLY thing that decides which of the
// two you get. It goes in the SAVE (`save.Data.seen`), or every reload turns the game back into a slideshow.

/// How many first-time cards may be queued at once. `wf.MAX_LOOT` is the real bound — one chest cannot hand
/// over more than it holds — and the queue only ever holds the NEW kinds out of one award, so this is
/// comfortably over the worst case and asserted against it in `worldfmt`'s own terms below.
pub const CARD_CAP: usize = 12;
/// …and how many toasts may stack before the oldest is pushed off the top. **A SCREEN LIMIT, NOT A BOUND ON
/// WHAT CAN ARRIVE** (owner's call): one chest may hold `wf.MAX_LOOT` distinct known kinds, which is more than
/// this, so the oldest DO get pushed off and that is the intended answer — five notices is as much as the
/// right-hand edge should ever be saying at once. The card queue below is the opposite case and is sized off
/// the loot bound instead, because a first-time card that never appears is a kind introduced twice.
pub const TOAST_CAP: usize = 5;

comptime {
    // ONE CONTAINER CAN NEVER FILL THE QUEUE. Past this the first-time card for something in the same chest
    // would have to wait for a dismissal, which `gain` handles safely — but it should not be the ordinary case.
    std.debug.assert(CARD_CAP > wf.MAX_LOOT);
}

/// How long a toast stands before it goes, and how long it takes to slide in and fade out.
pub const TOAST_LIFE: f32 = 3.4;
const TOAST_IN: f32 = 0.22;
const TOAST_OUT: f32 = 0.45;

const TOAST_W: i32 = 268;
const TOAST_H: i32 = 46;
const TOAST_GAP: i32 = 6;
/// Clear of the right edge, and BELOW the bars: the top-left is the character's own corner.
const TOAST_MARGIN: i32 = 18;
const TOAST_TOP: i32 = 132;

const CARD_W: i32 = 520;
const CARD_H: i32 = 300;
/// The picture's box on the card, and how many pixels tall the item is drawn at inside it.
const PIC_BOX: i32 = 96;
const PIC_PX: f32 = 74.0;

/// A toast that is standing. `t` counts UP from the moment it was made, which is what both the slide and the
/// fade are read off — one clock, so the two cannot disagree about when it is leaving.
const Toast = struct {
    kind: item.Kind = .crimson_flask,
    /// HOW MANY of it arrived. A chest holding three nameless souls is ONE toast saying three, not three toasts
    /// saying one — the stack is for DIFFERENT things, and repeats are a count.
    n: u16 = 1,
    t: f32 = 0,
};

/// A queued first-time card. It carries the SAME count a toast does, for the same reason: a chest holding three
/// of a kind you have never seen is one card saying three.
const Card = struct {
    kind: item.Kind = .crimson_flask,
    n: u16 = 1,
};

pub const Award = struct {
    /// **THE DISCOVERY SET.** One bool per kind rather than a packed bitset: `item.NK` is two dozen, and a
    /// bitset would buy three bytes at the cost of the one thing this has to be — legible in a save file you
    /// can read (`save.Data.seen`, one character per kind).
    ///
    /// That run is POSITIONAL, so `item.Kind`'s order is part of the save format and the enum is append-only.
    /// Read `save.Data.seen` before moving a row in it; `item.zig`'s own order test is the guard.
    seen: [item.NK]bool = [_]bool{false} ** item.NK,

    cards: [CARD_CAP]Card = undefined,
    ncards: usize = 0,
    toasts: [TOAST_CAP]Toast = undefined,
    ntoasts: usize = 0,

    /// **ONE ITEM REACHED HIS HANDS.** Called once per item, by whatever handed it over — a chest, a pickup,
    /// and whatever comes next. It does NOT touch the bag: adding is the caller's business, and this is only
    /// how the game SAYS what happened.
    pub fn gain(self: *Award, k: item.Kind) void {
        const i = @intFromEnum(k);
        if (!self.seen[i]) {
            // **SEEN IS SET ONLY IF THE CARD IS ACTUALLY QUEUED.** Marked first and then dropped on a full
            // queue, the kind would be silently discovered and its one first-time card LOST for the run — and
            // nothing anywhere would look wrong. One container cannot fill the queue (`MAX_LOOT` is asserted
            // under `CARD_CAP` below), but two opened before a single dismissal can, so the order matters.
            if (self.ncards >= CARD_CAP) return;
            self.seen[i] = true;
            // …and the CARD wins outright. A first-time kind never also toasts: it has just been shown to you
            // full-screen, and a notice underneath saying the same thing is the same fact twice.
            self.cards[self.ncards] = .{ .kind = k, .n = 1 };
            self.ncards += 1;
            return;
        }
        // **A COPY OF SOMETHING STILL ON A QUEUED CARD IS A COUNT ON THAT CARD** (owner's call). `seen` is set by
        // the first copy, so every further copy out of the same chest fell straight through to the toast path —
        // three of one NEW kind came up as a card AND an "x2" toast underneath it, which is two notices about
        // one handful and the exact thing the card is supposed to replace.
        for (self.cards[0..self.ncards]) |*c| {
            if (c.kind != k) continue;
            c.n += 1;
            return;
        }
        // A REPEAT WITHIN THE STACK IS A COUNT, NOT A SECOND TOAST — and it REFRESHES, so three runes out of
        // one chest read as "Nameless Soul x3" standing for its full life rather than one already leaving.
        for (self.toasts[0..self.ntoasts]) |*t| {
            if (t.kind != k) continue;
            t.n += 1;
            t.t = 0;
            return;
        }
        self.push(.{ .kind = k, .n = 1, .t = 0 });
    }

    /// THE OLDEST GOES when the stack is full: a notice you cannot see because five newer ones are over it is
    /// worse than one that never appeared, and the newest is always the one being explained.
    fn push(self: *Award, t: Toast) void {
        if (self.ntoasts >= TOAST_CAP) {
            var i: usize = 1;
            while (i < self.ntoasts) : (i += 1) self.toasts[i - 1] = self.toasts[i];
            self.ntoasts -= 1;
        }
        self.toasts[self.ntoasts] = t;
        self.ntoasts += 1;
    }

    /// **IS A CARD UP** — which is the same question as "is the world held", and the loop asks it exactly that
    /// way. While this is true nothing in the world ticks.
    pub fn carding(self: *const Award) bool {
        return self.ncards > 0;
    }

    /// The kind the card is showing, or null.
    pub fn front(self: *const Award) ?item.Kind {
        if (self.ncards == 0) return null;
        return self.cards[0].kind;
    }

    /// …and HOW MANY of it the card is announcing. 1 unless one container held several.
    pub fn frontCount(self: *const Award) u16 {
        if (self.ncards == 0) return 0;
        return self.cards[0].n;
    }

    /// ANY KEY CLOSES IT, and the next one comes up behind it. The queue is walked from the FRONT so the order
    /// items were found in is the order they are read in.
    pub fn dismiss(self: *Award) void {
        if (self.ncards == 0) return;
        var i: usize = 1;
        while (i < self.ncards) : (i += 1) self.cards[i - 1] = self.cards[i];
        self.ncards -= 1;
    }

    /// **THE TOASTS' OWN CLOCK, AND IT RUNS ON THE UNSCALED FRAME TIME.** Ticked only where the world ticks,
    /// so a toast does not expire behind a card that is holding everything else still.
    pub fn update(self: *Award, dt: f32) void {
        var i: usize = 0;
        while (i < self.ntoasts) {
            self.toasts[i].t += dt;
            if (self.toasts[i].t >= TOAST_LIFE + TOAST_OUT) {
                var j = i + 1;
                while (j < self.ntoasts) : (j += 1) self.toasts[j - 1] = self.toasts[j];
                self.ntoasts -= 1;
                continue; // …without advancing `i`: the one that moved down has not been ticked yet
            }
            i += 1;
        }
    }

    /// Nothing standing and nothing queued — what a new game and a fresh load both start at. The SEEN set is
    /// deliberately NOT cleared: a load restores it from the file, and a death must not un-discover anything.
    pub fn clearPending(self: *Award) void {
        self.ncards = 0;
        self.ntoasts = 0;
    }

    /// **WHAT HE STARTED WITH IS NOT A DISCOVERY.** Marked seen without a card and without a toast: he is
    /// holding it on the frame the game begins, so the first flask found in the world is the SECOND one he has
    /// owned, and carding it would be the game introducing him to something already on his belt.
    pub fn markKnown(self: *Award, k: item.Kind) void {
        self.seen[@intFromEnum(k)] = true;
    }

    // ── THE TOASTS ────────────────────────────────────────────────────────────────────────────────────

    /// **NOT WHILE A CARD IS UP** (owner's call). One handful is one notice at a time: a chest holding a new
    /// kind and a known one cards the first and toasts the second, and both were on screen together — a
    /// full-screen card with a notice standing beside it, out of one press.
    ///
    /// **HELD, NOT DROPPED.** The toast is still owed — you did pick the thing up — so it waits and stands its
    /// full life once the last card is dismissed. That costs nothing to arrange: the clock only runs where the
    /// world runs (`update`), and behind a card the world is held, so a queued toast is exactly as fresh when
    /// it finally appears.
    pub fn drawToasts(self: *const Award) void {
        if (self.carding()) return;
        const sw = rl.getScreenWidth();
        var y = TOAST_TOP;
        for (self.toasts[0..self.ntoasts]) |*t| {
            // ONE CLOCK, TWO EDGES: it slides in over `TOAST_IN` and fades over `TOAST_OUT` at the far end,
            // and in between it simply stands there.
            const inK = mathx.smoothstep(0, TOAST_IN, t.t);
            const outK = 1.0 - mathx.smoothstep(TOAST_LIFE, TOAST_LIFE + TOAST_OUT, t.t);
            const a = mathx.u8f(235.0 * outK);
            // It comes IN from off the right edge, which is the direction it will leave toward.
            const slide: i32 = @intFromFloat((1.0 - inK) * @as(f32, @floatFromInt(TOAST_W + TOAST_MARGIN)));
            const x = sw - TOAST_W - TOAST_MARGIN + slide;
            uiart.plate(x, y, TOAST_W, TOAST_H, mathx.u8f(212.0 * outK));
            uiart.frame(x, y, TOAST_W, TOAST_H, a);
            itemart.draw(t.kind, @floatFromInt(x + 26), @floatFromInt(y + @divTrunc(TOAST_H, 2)), 30.0);
            const name = item.displayName(t.kind);
            const ny = y + @divTrunc(TOAST_H - hud.lineH(hud.TINY), 2);
            hud.text(name, x + 50, ny, hud.TINY, mathx.withAlpha(uiart.GILT, a));
            if (t.n > 1) {
                var buf: [12]u8 = undefined;
                const s = std.fmt.bufPrintZ(&buf, "x{d}", .{t.n}) catch "";
                hud.text(s, x + TOAST_W - 18 - hud.textW(s, hud.TINY), ny, hud.TINY, mathx.withAlpha(uiart.GILT_BRIGHT, a));
            }
            y += TOAST_H + TOAST_GAP;
        }
    }

    // ── THE FIRST-TIME CARD ───────────────────────────────────────────────────────────────────────────

    var proseBuf: [512]u8 = undefined;
    var proseLines: [8][:0]const u8 = undefined;

    pub fn drawCard(self: *const Award) void {
        const k = self.front() orelse return;
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        // The world DIMS behind it — this is a stop, and a card floating over a live-looking scene reads as a
        // toast that got too big.
        rl.drawRectangle(0, 0, sw, sh, rgba(6, 5, 4, 168));

        const x = @divTrunc(sw - CARD_W, 2);
        const y = @divTrunc(sh - CARD_H, 2);
        uiart.seat(x, y, CARD_W, CARD_H);
        uiart.plate(x, y, CARD_W, CARD_H, 240);
        uiart.frame(x, y, CARD_W, CARD_H, 210);

        // THE PICTURE, in its own well on the left — the book's own arrangement, so an item looks the same
        // place it is found as it does in the bag.
        const px = x + 34;
        const py = y + 40;
        uiart.well(px, py, PIC_BOX, PIC_BOX, 210);
        itemart.draw(k, @floatFromInt(px + @divTrunc(PIC_BOX, 2)), @floatFromInt(py + @divTrunc(PIC_BOX, 2)), PIC_PX);

        // …and the NAME beside it, with what shelf it is on under it. SEVERAL of one kind is an "x3" after the
        // name and NOT a second card: one handful is one notice, however many of it there were.
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

        // THE DESCRIPTION, wrapped to the card — the same prose the character book prints, so the thing is
        // never described two ways.
        const proseW = CARD_W - 68;
        const lines = hud.wrap(item.describe(k), hud.SMALL, proseW, &proseBuf, &proseLines);
        var ly = py + PIC_BOX + 34;
        for (lines) |ln| {
            hud.text(ln, x + 34, ly, hud.SMALL, uiart.TEXT_VALUE);
            ly += hud.lineH(hud.SMALL);
        }

        // …AND WHAT TO PRESS, which is anything. The footer says so rather than naming a button, because for
        // once there is no wrong key — and if more are waiting it says HOW MANY, or the second card arriving
        // reads as the first one not having closed.
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
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts); // the card IS the notice
    try std.testing.expectEqual(item.Kind.mushroom_jerky, a.front().?);

    a.dismiss();
    try std.testing.expect(!a.carding());
    // …and the second one of the same kind is a toast, because the set remembers.
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
    try std.testing.expect(!a.carding()); // …and the world starts again on the LAST dismissal
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
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.toasts[0].t, 1e-6); // …and it stands its full life again
}

test "TOASTS EXPIRE, and a full stack drops its OLDEST rather than refusing the newest" {
    var a = Award{};
    for (0..item.NK) |i| a.seen[i] = true; // everything known: every gain is a toast
    // Distinct kinds, more than the stack holds.
    const kinds = [_]item.Kind{ .crimson_flask, .cerulean_flask, .rune_arc, .golden_seed, .smithing_stone, .bloodgrass, .kobold_fang };
    for (kinds) |k| a.gain(k);
    try std.testing.expectEqual(TOAST_CAP, a.ntoasts);
    // The FIRST is gone and the LAST is standing — the newest is the one being explained.
    try std.testing.expectEqual(item.Kind.kobold_fang, a.toasts[a.ntoasts - 1].kind);
    for (a.toasts[0..a.ntoasts]) |t| try std.testing.expect(t.kind != .crimson_flask);
    // …and they all go on their own clock.
    var t: f32 = 0;
    while (t < TOAST_LIFE + TOAST_OUT + 0.2) : (t += 1.0 / 60.0) a.update(1.0 / 60.0);
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
}

test "EVERY TOAST IS TICKED even when one in front of it expires the same frame" {
    // THE BUG this guards: removing an entry and then advancing the index skips the one that moved down into
    // the hole, so with two expiring together the second stood for an extra frame — and with a full stack of
    // them the tail crawled out one frame at a time.
    var a = Award{};
    for (0..item.NK) |i| a.seen[i] = true;
    a.gain(.rune_arc);
    a.gain(.golden_seed);
    a.gain(.iron_key);
    try std.testing.expectEqual(@as(usize, 3), a.ntoasts);
    a.update(TOAST_LIFE + TOAST_OUT + 0.01); // one enormous step: ALL of them are over their life at once
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
}

test "A FULL CARD QUEUE DOES NOT SILENTLY DISCOVER — the kind cards next time instead" {
    var a = Award{};
    // Fill the queue with distinct new kinds.
    var n: usize = 0;
    while (n < CARD_CAP) : (n += 1) a.gain(@enumFromInt(n));
    try std.testing.expectEqual(CARD_CAP, a.ncards);
    // One more NEW kind arrives with nowhere to go. It must NOT be marked seen: marked and dropped, its one
    // first-time card is lost for the whole run and nothing anywhere looks wrong.
    const spare: item.Kind = @enumFromInt(CARD_CAP);
    a.gain(spare);
    try std.testing.expect(!a.seen[@intFromEnum(spare)]);
    try std.testing.expectEqual(CARD_CAP, a.ncards);
    // Read one, and it goes in behind the rest.
    a.dismiss();
    a.gain(spare);
    try std.testing.expect(a.seen[@intFromEnum(spare)]);
    try std.testing.expectEqual(spare, a.cards[a.ncards - 1].kind);
}

test "SEVERAL OF ONE NEW KIND IS ONE CARD SAYING x3, never a card and a toast under it" {
    // THE BUG this guards: `seen` is set by the first copy, so copies 2..n of the same NEW kind fell through to
    // the toast path — a chest of three came up as a full-screen card AND an "x2" toast, two notices for one
    // handful. The card counts them instead.
    var a = Award{};
    a.gain(.nameless_soul);
    a.gain(.nameless_soul);
    a.gain(.nameless_soul);
    try std.testing.expectEqual(@as(usize, 1), a.ncards);
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts);
    try std.testing.expectEqual(@as(u16, 3), a.frontCount());
    // …and once it is read, the NEXT one found is an ordinary toast: the kind is known now.
    a.dismiss();
    try std.testing.expectEqual(@as(u16, 0), a.frontCount());
    a.gain(.nameless_soul);
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts);
}

test "ONE HANDFUL IS ONE NOTICE AT A TIME — a mixed chest holds its toast back behind the card" {
    // THE BUG this guards: a chest holding one NEW kind and one KNOWN one queued a card AND pushed a toast,
    // and `hud` draws the toasts over the held world — so a single press put a full-screen card and a notice
    // beside it on screen together. The toast is still owed and is not dropped: it waits.
    var a = Award{};
    a.seen[@intFromEnum(item.Kind.nameless_soul)] = true;
    a.gain(.mushroom_jerky); // new: cards
    a.gain(.nameless_soul); // known: toasts
    try std.testing.expect(a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts); // …made, and still standing
    // Behind the card the world is held, so the held toast does not age out while it waits.
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.toasts[0].t, 1e-6);
    a.dismiss();
    try std.testing.expect(!a.carding());
    try std.testing.expectEqual(@as(usize, 1), a.ntoasts); // …and it is there to be read once the card is gone
}

test "a copy arriving while ANOTHER kind's card is in front of it still lands on its own card" {
    var a = Award{};
    a.gain(.mushroom_jerky);
    a.gain(.nameless_soul);
    a.gain(.mushroom_jerky); // behind the front card, not on it
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
    try std.testing.expect(!a.carding()); // no card…
    try std.testing.expectEqual(@as(usize, 0), a.ntoasts); // …and no toast either
    // …and finding one later is a TOAST, because he already owned one.
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
    // …and both are still KNOWN, so neither cards again.
    try std.testing.expect(a.seen[@intFromEnum(item.Kind.golden_seed)]);
    try std.testing.expect(a.seen[@intFromEnum(item.Kind.iron_key)]);
}
