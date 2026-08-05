const std = @import("std");


pub const Kind = enum(u8) {
    crimson_flask, // the ones the HUD already draws
    cerulean_flask,
    rune_arc,
    golden_seed,
    smithing_stone,
    bloodgrass, // wayside pickings — the common, worthless drop
    kobold_fang,
    iron_key,
    mushroom_jerky, // THE FIRST ITEM THAT DOES ANYTHING — see `Use`
};

pub const NK = @typeInfo(Kind).@"enum".fields.len;

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

/// WHAT SHELF IT BELONGS ON. The bag is one grid and always will be — this is what the detail panel calls
/// the thing, and what a sort would go on the day the bag is big enough to need one.
pub const Class = enum {
    tool, // spent for an effect: the flasks, the jerky
    treasure, // spent for a permanent gain, or for something the game has not built yet
    material, // it is worth what a smith or a merchant will give for it
    key, // it opens exactly one thing

    pub fn label(c: Class) [:0]const u8 {
        return switch (c) {
            .tool => "Tool",
            .treasure => "Treasure",
            .material => "Material",
            .key => "Key Item",
        };
    }
};

pub fn class(k: Kind) Class {
    return switch (k) {
        .crimson_flask, .cerulean_flask, .mushroom_jerky => .tool,
        .rune_arc, .golden_seed => .treasure,
        .smithing_stone, .bloodgrass, .kobold_fang => .material,
        .iron_key => .key,
    };
}

/// WHAT IT IS, IN THE PLAYER'S HANDS — the description the character book prints beside the picture.
/// Two sentences at most, and the SECOND one is always what it is honestly worth right now: half of
/// these do nothing yet, and a description that hides that is the same lie as an inert attribute with no
/// note under it (`stats.governs`). The day one of them gains an effect, its line is edited here.
pub fn describe(k: Kind) [:0]const u8 {
    return switch (k) {
        .crimson_flask => "A flask of clouded red glass, refilled at any grace. The draught it holds closes wounds that ought to have killed you.",
        .cerulean_flask => "The blue twin of the crimson. It returns the focus a sorcery costs — and there are no sorceries yet, so it returns nothing you can spend.",
        .rune_arc => "A shard of a shattered great rune, still lit from the inside. Whatever it once carried leaks out of the break; nothing here can catch it yet.",
        .golden_seed => "A sprout of gilded stalk, pulled up whole. In another age these bought another swallow from the flask. This one is only precious.",
        .smithing_stone => "A shard off a bigger stone, hard enough to bite steel. No smith has set up in these ruins to grind it against.",
        .bloodgrass => "A tuft of the red grass that grows thickest where something bled out. Common as dirt, and worth about as much.",
        .kobold_fang => "A tooth taken out of a jaw that was still using it. The crack across the root says how.",
        .iron_key => "Cold, heavy, and eaten with rust. It was cut for one lock, and that lock is somewhere in the ruins.",
        .mushroom_jerky => "Cap flesh, salted and dried until it is more leather than mushroom. Chewing it staunches you slowly, for a long while.",
    };
}

/// WHAT USING IT DOES — named here, done elsewhere.
pub const Use = union(enum) {
    /// Nothing yet.
    none,
    /// HP back slowly over time (`combat.Regen` is the mechanism): `frac` of MAX HP spread over `secs` seconds.
    regen: struct { frac: f32, secs: f32 },
};

pub fn use(k: Kind) Use {
    return switch (k) {
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

/// Is this row worth pressing Confirm on?
pub fn usable(k: Kind) bool {
    return std.meta.activeTag(use(k)) != .none;
}

/// The SHORT tag the map file writes, and the only name a hand-edited world has to get right.
pub fn tag(k: Kind) []const u8 {
    return @tagName(k);
}

pub fn fromTag(s: []const u8) ?Kind {
    return std.meta.stringToEnum(Kind, s);
}

pub const CAP: u16 = 999;

pub const Bag = struct {
    counts: [NK]u16 = [_]u16{0} ** NK,

    pub fn add(self: *Bag, k: Kind, n: u16) void {
        const i = @intFromEnum(k);
        self.counts[i] = @min(CAP, self.counts[i] +| n);
    }

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

    /// The `i`th non-empty kind, in Kind order.
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


test "every kind has a name, and no two share one" {
    for (0..NK) |i| {
        const a: Kind = @enumFromInt(i);
        try std.testing.expect(displayName(a).len > 0);
        for (i + 1..NK) |j| {
            try std.testing.expect(!std.mem.eql(u8, displayName(a), displayName(@enumFromInt(j))));
        }
    }
}

test "every kind is described and shelved, and no two share a description" {
    for (0..NK) |i| {
        const a: Kind = @enumFromInt(i);
        try std.testing.expect(describe(a).len > 20); // a stub is worse than no panel at all
        try std.testing.expect(class(a).label().len > 0);
        for (i + 1..NK) |j| {
            try std.testing.expect(!std.mem.eql(u8, describe(a), describe(@enumFromInt(j))));
        }
    }
    // …and the one kind that DOES something is shelved as a tool, which is the promise that row makes.
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (usable(k)) try std.testing.expectEqual(Class.tool, class(k));
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
    try std.testing.expect(found >= 1);
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
    const last: Kind = @enumFromInt(NK - 1);
    b.add(last, 1);
    try std.testing.expectEqual(Kind.golden_seed, b.nth(0).?);
    try std.testing.expectEqual(last, b.nth(1).?);
    try std.testing.expect(b.nth(2) == null);
    // Emptying a row closes the gap rather than leaving a hole a cursor can land in.
    _ = b.take(.golden_seed, 1);
    try std.testing.expectEqual(last, b.nth(0).?);
    try std.testing.expectEqual(@as(usize, 1), b.distinct());
}
