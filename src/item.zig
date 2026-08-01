const std = @import("std");

// ── ITEMS AND THE BAG ───────────────────────────────────────────────────────────────────
// A vocabulary of kinds, a name each, and counts. Nothing here affects the hero yet — the loop (chest →
// interaction → a line in a menu) is what is being built first.
//
// `displayName` is an EXHAUSTIVE SWITCH, like `props.INFO`: a kind added without a name is a compile
// error, not a blank row. A bag is COUNTS, not slots — twenty of a thing is a number beside it.

pub const Kind = enum(u8) {
    crimson_flask, // the ones the HUD already draws
    cerulean_flask,
    rune_arc,
    golden_seed,
    smithing_stone,
    bloodgrass, // wayside pickings — the common, worthless drop
    kobold_fang, // …and a trophy off the warband
    iron_key,
    mushroom_jerky, // THE FIRST ITEM THAT DOES ANYTHING — see `Use`
};

pub const NK = @typeInfo(Kind).@"enum".fields.len;

/// What an item is CALLED. Enum tags are terse identifiers (`rune_arc`, `iron_key`) which are right in
/// code and wrong in a menu — the underscore alone gives it away as a symbol rather than a name.
pub fn displayName(k: Kind) [:0]const u8 {
    return switch (k) {
        .crimson_flask => "Flask of Crimson Tears",
        .cerulean_flask => "Flask of Cerulean Tears",
        .rune_arc => "Rune Arc",
        .golden_seed => "Golden Seed",
        .smithing_stone => "Smithing Stone",
        .bloodgrass => "Bloodgrass",
        .kobold_fang => "Kobold Fang",
        .iron_key => "Iron Key",
        .mushroom_jerky => "Mushroom Jerky",
    };
}

/// WHAT USING IT DOES — named here, done elsewhere. This file is the vocabulary and the counts and
/// it knows nothing about HP, so it says WHICH effect and `combat`/`game` own what that means; the
/// same split `props.stock` uses to shelve a kind without knowing what a brush is.
///
/// EXHAUSTIVE, like `displayName`: a new kind is a compile error until somebody has decided whether
/// it does anything, which is the question that is easiest to forget and worst to get wrong.
pub const Use = union(enum) {
    /// Nothing yet. Most of the list — trophies, keys, upgrade material with nothing to upgrade.
    none,
    /// HP back slowly over time (`combat.Regen` is the mechanism): `frac` of MAX HP spread over
    /// `secs` seconds.
    ///
    /// THE NUMBERS RIDE THE EFFECT, not the mechanism, and that is the point of the payload: as a
    /// bare `.regen` tag with the dials kept next to `Regen`, the second edible anybody adds gets
    /// the jerky's potency in silence — the mapping from kind to numbers lived in one `switch` arm
    /// that never mentioned the kind. Potency is what tells one consumable from another, so it
    /// belongs where the name does.
    regen: struct { frac: f32, secs: f32 },
};

pub fn use(k: Kind) Use {
    return switch (k) {
        // More total than a Crimson flask (0.45, instant) at a fifth of the rate — worth eating
        // BEFORE a fight and close to worthless inside one.
        .mushroom_jerky => .{ .regen = .{ .frac = 0.60, .secs = 20.0 } },
        .crimson_flask,
        .cerulean_flask,
        .rune_arc,
        .golden_seed,
        .smithing_stone,
        .bloodgrass,
        .kobold_fang,
        .iron_key,
        => .none,
    };
}

/// Is this row worth pressing Confirm on? The inventory asks exactly this — a "Use" that silently
/// does nothing is worse than a list you can only read (which is what this list WAS).
pub fn usable(k: Kind) bool {
    return std.meta.activeTag(use(k)) != .none;
}

/// The SHORT tag the map file writes, and the only name a hand-edited world has to get right. The enum
/// tag itself, so the format and the code cannot drift — and parsed back by the same name below.
pub fn tag(k: Kind) []const u8 {
    return @tagName(k);
}

pub fn fromTag(s: []const u8) ?Kind {
    return std.meta.stringToEnum(Kind, s);
}

/// THE BAG. Counts per kind, capped so a count cannot wrap round to nothing on a stuck spawner.
pub const CAP: u16 = 999;

pub const Bag = struct {
    counts: [NK]u16 = [_]u16{0} ** NK,

    pub fn add(self: *Bag, k: Kind, n: u16) void {
        const i = @intFromEnum(k);
        self.counts[i] = @min(CAP, self.counts[i] +| n);
    }

    /// Take up to `n` and report how many actually came out — a caller that wants "did this work"
    /// checks the count rather than asking first, which is the same shape `combat.Vitals.heal` uses.
    pub fn take(self: *Bag, k: Kind, n: u16) u16 {
        const i = @intFromEnum(k);
        const got = @min(self.counts[i], n);
        self.counts[i] -= got;
        return got;
    }

    pub fn count(self: *const Bag, k: Kind) u16 {
        return self.counts[@intFromEnum(k)];
    }

    /// How many DIFFERENT things are in here — the number of rows a menu has to draw.
    pub fn distinct(self: *const Bag) usize {
        var n: usize = 0;
        for (self.counts) |c| {
            if (c > 0) n += 1;
        }
        return n;
    }

    pub fn total(self: *const Bag) u32 {
        var n: u32 = 0;
        for (self.counts) |c| n += c;
        return n;
    }

    /// The `i`th non-empty kind, in Kind order. What an inventory list iterates: the bag is a fixed
    /// array and the menu wants only the rows that have something in them, so this is the one place
    /// that mapping lives (a menu doing its own skip-the-zeroes walk gets the cursor wrong the first
    /// time a count reaches zero while the list is open).
    pub fn nth(self: *const Bag, i: usize) ?Kind {
        var seen: usize = 0;
        for (self.counts, 0..) |c, ki| {
            if (c == 0) continue;
            if (seen == i) return @enumFromInt(ki);
            seen += 1;
        }
        return null;
    }

    pub fn clear(self: *Bag) void {
        self.counts = [_]u16{0} ** NK;
    }
};

// ── tests ───────────────────────────────────────────────────────────────────────────────

test "every kind has a name, and no two share one" {
    // The exhaustive switch already forces a name to EXIST; this catches the copy-paste that gives two
    // kinds the same one, which a switch cannot see.
    for (0..NK) |i| {
        const a: Kind = @enumFromInt(i);
        try std.testing.expect(displayName(a).len > 0);
        for (i + 1..NK) |j| {
            try std.testing.expect(!std.mem.eql(u8, displayName(a), displayName(@enumFromInt(j))));
        }
    }
}

test "a tag round-trips, and a bad one is rejected rather than guessed" {
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        try std.testing.expectEqual(k, fromTag(tag(k)).?);
    }
    try std.testing.expect(fromTag("no_such_item") == null);
    try std.testing.expect(fromTag("") == null);
}

test "every usable kind carries its OWN dose, and the rest do nothing" {
    // The guard against the next edible: `usable` and `use` must agree (they are one expression, and
    // the inventory offers Confirm off the first while `game.useItem` acts on the second), and a
    // regen's numbers must be real — a 0-second drip divides by zero in `Regen.start`'s rate and a
    // 0-fraction one is a row you can press that heals nothing.
    var found: usize = 0;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        switch (use(k)) {
            .none => try std.testing.expect(!usable(k)),
            .regen => |r| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(r.frac > 0 and r.frac <= 1.0);
                try std.testing.expect(r.secs > 0);
            },
        }
    }
    try std.testing.expect(found >= 1); // …and at least one item in the game still does something
}

test "the bag counts, caps, and never wraps" {
    var b = Bag{};
    try std.testing.expectEqual(@as(usize, 0), b.distinct());
    b.add(.rune_arc, 2);
    b.add(.rune_arc, 3);
    try std.testing.expectEqual(@as(u16, 5), b.count(.rune_arc));
    try std.testing.expectEqual(@as(usize, 1), b.distinct());
    // Saturating, both ways: a count may not wrap to zero at the top nor underflow at the bottom.
    b.add(.rune_arc, CAP);
    try std.testing.expectEqual(CAP, b.count(.rune_arc));
    try std.testing.expectEqual(@as(u16, 0), b.take(.golden_seed, 1));
    try std.testing.expectEqual(@as(u16, 4), b.take(.rune_arc, 4));
}

test "nth walks only the rows that have something in them" {
    var b = Bag{};
    b.add(.golden_seed, 1);
    b.add(.iron_key, 1); // the LAST kind, so a broken walk would run off the end
    try std.testing.expectEqual(Kind.golden_seed, b.nth(0).?);
    try std.testing.expectEqual(Kind.iron_key, b.nth(1).?);
    try std.testing.expect(b.nth(2) == null);
    // Emptying a row closes the gap rather than leaving a hole a cursor can land in.
    _ = b.take(.golden_seed, 1);
    try std.testing.expectEqual(Kind.iron_key, b.nth(0).?);
    try std.testing.expectEqual(@as(usize, 1), b.distinct());
}
