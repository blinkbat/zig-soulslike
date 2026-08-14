const std = @import("std");


/// **APPEND-ONLY.** `save.Data.seen` is a POSITIONAL bit run over this enum — one character per kind, read
/// back by index and never by tag — so a kind inserted or moved anywhere above the end silently re-points
/// every discovery bit in every save on disk. `ORDER` below pins it; add new kinds at the BOTTOM and add the
/// tag to the end of that list.
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
    ember_candle, // thrown fire — the quiver's answer without the quiver
    sporeling_cap, // chewed: chaos slides off you for a while
    second_wind, // one sharp breath — the winded latch let go at once
    tower_shield, // gear waiting on an equip system: registered, described honestly, inert
    greatclub,
    leech_signet,
    soul_binding_ring, // it breaks in place of you: a death spills no souls while one is on you
    fire_tallow, // wiped on the blade: the fire arrow's rule, moved to the swing
    thundercrock, // thrown lightning — the first of it anywhere in the world
    nameless_soul, // souls, straight onto the counter
    toadflesh_broth, // the stamina refill runs faster for a while
    fang_dirk, // more gear waiting on the equip system, the tower shield's shelf
    grave_warbow,
    quilted_gambeson,
    spirit_scroll_wolf, // THE FIRST SPIRIT — carried, not used: the bell reads the bag (`combat.spiritOf`)
};

pub const NK = @typeInfo(Kind).@"enum".fields.len;

/// **THE ORDER, WRITTEN DOWN, because a save file depends on it and nothing else could see that.** A reorder
/// or an insert is a legal-looking edit that corrupts every `seen:` run on disk (`save.Data.seen`), and it
/// fails SILENTLY — the file still parses, it just describes a different set of items. Pinning the tags is
/// the only guard that catches it, and it costs one line per kind at the one moment it matters.
const ORDER = [_][]const u8{
    "crimson_flask",   "cerulean_flask", "rune_arc",     "golden_seed",
    "smithing_stone",  "bloodgrass",     "kobold_fang",  "iron_key",
    "mushroom_jerky",  "ember_candle",   "sporeling_cap", "second_wind",
    "tower_shield",    "greatclub",      "leech_signet", "soul_binding_ring",
    "fire_tallow",     "thundercrock",   "nameless_soul", "toadflesh_broth",
    "fang_dirk",       "grave_warbow",   "quilted_gambeson", "spirit_scroll_wolf",
};

comptime {
    if (ORDER.len != NK) @compileError("item: a kind was added or removed without updating ORDER — a save's " ++
        "`seen:` run is positional over this enum, so the new kind must go at the END of both");
    for (ORDER, 0..) |name, i| {
        const tagName = @tagName(@as(Kind, @enumFromInt(i)));
        if (!std.mem.eql(u8, name, tagName)) @compileError("item: kind " ++ tagName ++ " is at index " ++
            std.fmt.comptimePrint("{d}", .{i}) ++ " where ORDER says " ++ name ++ " — a MOVED or INSERTED " ++
            "kind silently re-points every discovery bit in every save on disk (`save.Data.seen`). Append instead.");
    }
}

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
        .ember_candle => "Emberfat Candle",
        .sporeling_cap => "Dried Sporeling Cap",
        .second_wind => "Second Wind",
        .tower_shield => "Cracked Tower Shield",
        .greatclub => "Bog-Oak Greatclub",
        .leech_signet => "Leech Signet",
        .soul_binding_ring => "Soul Binding Ring",
        .fire_tallow => "Fire Tallow",
        .thundercrock => "Thundercrock",
        .nameless_soul => "Nameless Soul",
        .toadflesh_broth => "Toadflesh Broth",
        .fang_dirk => "Fang Dirk",
        .grave_warbow => "Grave Warbow",
        .quilted_gambeson => "Quilted Gambeson",
        .spirit_scroll_wolf => "Spirit Scroll: Hildebrand",
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
        // **ONE PER LINE.** This is the table you read to find out where a thing shelves, and both of the long
        // arms ran past 200 columns — a row you cannot find is a row you re-add by mistake.
        .crimson_flask,
        .cerulean_flask,
        .mushroom_jerky,
        .ember_candle,
        .sporeling_cap,
        .second_wind,
        .fire_tallow,
        .thundercrock,
        .nameless_soul,
        .toadflesh_broth,
        => .tool,
        // The pieces of GEAR shelve as treasure until there is an arm to take them up — the shelf
        // whose own definition is "something the game has not built yet".
        .rune_arc,
        .golden_seed,
        .tower_shield,
        .greatclub,
        .leech_signet,
        .fang_dirk,
        .grave_warbow,
        .quilted_gambeson,
        => .treasure,
        // NOT a tool, though it is the one carried thing that DOES something: a tool is spent by pressing
        // Confirm on it, and this one is spent by dying. `usable` stays false and the shelf says so.
        .soul_binding_ring => .treasure,
        // …and the scroll for the ring's reason, read the other way: finding it is a PERMANENT gain (the bell
        // knows the wolf from here on), which is what this shelf means. Nothing is spent by pressing Confirm.
        .spirit_scroll_wolf => .treasure,
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
        .crimson_flask => "A flask of clouded red glass, refilled at any bonfire. The draught it holds closes wounds that ought to have killed you.",
        .cerulean_flask => "The blue twin of the crimson. It gives back half the focus a rod spends, which is two more casts of the wand before you have to walk back to a bonfire.",
        .rune_arc => "A shard of a shattered great rune, still lit from the inside. Whatever it once carried leaks out of the break; nothing here can catch it yet.",
        .golden_seed => "A sprout of gilded stalk, pulled up whole. In another age these bought another swallow from the flask. This one is only precious.",
        .smithing_stone => "A shard off a bigger stone, hard enough to bite steel. No smith has set up in these ruins to grind it against.",
        .bloodgrass => "A tuft of the red grass that grows thickest where something bled out. Common as dirt, and worth about as much.",
        .kobold_fang => "A tooth taken out of a jaw that was still using it. The crack across the root says how.",
        .iron_key => "Cold, heavy, and eaten with rust. It was cut for one lock, and that lock is somewhere in the ruins.",
        .mushroom_jerky => "Cap flesh, salted and dried until it is more leather than mushroom. Chewing it staunches you slowly, for a long while.",
        .ember_candle => "A dollop of rendered fire-fat around a wick, made to be thrown lit. It bursts on whatever it lands on; the fat still burns out too fast to pool.",
        .sporeling_cap => "A sporeling's cap, dried until the violet in it went quiet. Chewed, it steeps you in its element, and for a minute chaos slides off you.",
        .second_wind => "A curl of pale bark that smells of cold air after rain. One sharp breath of it and your legs remember themselves.",
        .tower_shield => "A door of a shield, cracked through and banded in old iron. No arm here has learned to carry it yet.",
        .greatclub => "Bog-oak shod with iron, heavier than it looks, and it looks heavy. No hand here knows its heft yet.",
        .leech_signet => "A signet cut from a leech's beak, warm against the skin. Whatever bargain it offers, nothing here can seal it yet.",
        .soul_binding_ring => "A thin gold band with a hairline already run through it. Die with one on you and the RING gives instead: it snaps, and what you were carrying stays carried.",
        .fire_tallow => "Rendered fire-fat, unlit, in a waxed twist of cloth. Wiped along an edge it clings and burns: for a minute the sword hangs fire on top of what it always did.",
        .thundercrock => "A squat clay jar that hums against the palm, thrown like the candle. It cracks on what it lands on and the sky's own spark gets out - the only lightning anywhere in these ruins.",
        .nameless_soul => "Someone's whole worth, gone cold and hard enough to carry. Crushed in the fist it is worth a middling foe's souls, and nobody walks back for these.",
        .toadflesh_broth => "Toad shanks boiled pale, drunk cold from the skin they cooked in. It sits heavy and warm, and for a minute your wind comes back the faster for it.",
        .fang_dirk => "A dirk ground out of the longest fang in a kobold's jaw, hafted in cord. Quick, and hungry for nothing; no hand here has learned to fight with it yet.",
        .grave_warbow => "A warbow of grave-oak, its draw twice the skeletons' hunting bows. It would loose a shaft worth stopping for; no arm here can bend it yet.",
        .quilted_gambeson => "A coat of rag-stuffed linen, stitched in diamonds and stained by whoever wore it last. It would turn the edge off a blow, if anything here knew how to wear armour.",
        .spirit_scroll_wolf => "A hide scroll gone stiff as board, the wolf on it drawn in one unbroken line. A name is written under it - Hildebrand - and a bell that knows the name can call the shape; what answers is grey, half there, and already running.",
    };
}

/// WHAT USING IT DOES — named here, done elsewhere. Plain numbers only: this file imports nothing but
/// std, so an effect that needs a `combat` type is described here in floats and assembled at the apply
/// site (`game.useItem`).
pub const Use = union(enum) {
    /// Nothing yet.
    none,
    /// HP back slowly over time (`combat.Regen` is the mechanism): `frac` of MAX HP spread over `secs` seconds.
    regen: struct { frac: f32, secs: f32 },
    /// LOBBED at the reticle through the shafts' own pool — one victim, like everything thrown here.
    lob: struct { dmg: f32, fire: f32 = 0, lightning: f32 = 0, poise: f32 },
    /// A timed ward: `chaos` resistance for `secs` seconds. Refreshes, never stacks (the status law).
    ward: struct { chaos: f32, secs: f32 },
    /// `share` of the stamina pool back at once, through the winded latch's own gate.
    wind: struct { share: f32 },
    /// WIPED ON THE BLADE: the sword hangs `frac` of its own physical as fire for `secs` — the fire
    /// arrow's rule (`hero.FIRE_ARROW_FRAC`), moved to the swing. Refreshes, never stacks.
    grease: struct { frac: f32, secs: f32 },
    /// Souls, straight onto the counter.
    souls: struct { n: u32 },
    /// The stamina refill runs `mult` times its rate for `secs` seconds. Refreshes, never stacks.
    brew: struct { mult: f32, secs: f32 },
};

pub fn use(k: Kind) Use {
    return switch (k) {
        .mushroom_jerky => .{ .regen = .{ .frac = 0.60, .secs = 20.0 } },
        // Under both melee swings in damage (the bow's own restraint), but it is fire, and fire is the
        // answer to half the wood.
        .ember_candle => .{ .lob = .{ .dmg = 8, .fire = 22, .poise = 12 } },
        .sporeling_cap => .{ .ward = .{ .chaos = 40, .secs = 60 } },
        .second_wind => .{ .wind = .{ .share = 0.5 } },
        // The fire arrow's own fraction: the tallow makes a sword of the burning shaft, not a bigger one.
        .fire_tallow => .{ .grease = .{ .frac = 0.5, .secs = 60 } },
        // The candle's weights with the element swapped — the pair teach one throw, and the tables in
        // `combat` decide which jar answers which creature.
        .thundercrock => .{ .lob = .{ .dmg = 8, .lightning = 22, .poise = 12 } },
        // A middling foe's worth (the Rooted's own figure) — found money, not a farm.
        .nameless_soul => .{ .souls = .{ .n = 150 } },
        .toadflesh_broth => .{ .brew = .{ .mult = 1.5, .secs = 60 } },
        .crimson_flask,
        .cerulean_flask,
        .rune_arc,
        .golden_seed,
        .smithing_stone,
        .bloodgrass,
        .kobold_fang,
        .iron_key,
        .tower_shield,
        .greatclub,
        .leech_signet,
        .soul_binding_ring,
        .fang_dirk,
        .grave_warbow,
        .quilted_gambeson,
        // CARRIED, NOT USED — the `soul_binding_ring`'s shape: what it does, it does by being in the bag.
        // The bell reads it (`combat.spiritOf`), so a Confirm on this row would be a press that did nothing.
        .spirit_scroll_wolf,
        => .none,
    };
}

/// Is this row worth pressing Confirm on?
pub fn usable(k: Kind) bool {
    return std.meta.activeTag(use(k)) != .none;
}

/// **WHAT IT DOES, IN ONE LINE OF MECHANIC** — the answer to "which of these two flasks did I just put in the
/// box", which the flavour prose (`describe`) deliberately does not give. Read off `use` wherever there is a
/// `Use` to read, so a dose retuned there reads here and the two cannot drift.
///
/// The numbers are the ITEM'S OWN — a fraction stays a fraction, because nothing here knows a hero's max HP.
/// `book.zig` prints the same doses resolved against the sheet, which is the right thing for a player holding
/// one and the wrong thing on a row that exists before there is a hero at all.
///
/// The three things that DO something without a `Use` are named: they are spent by dying, by carrying, and by
/// a lock, and "no effect" on any of those rows is a lie the author would place loot on.
pub fn effect(k: Kind, buf: []u8) [:0]const u8 {
    if (isFlask(k)) return switch (k) {
        .crimson_flask => "Heals. Charges refill at a bonfire, not from the bag.",
        else => "Restores Focus. Charges refill at a bonfire, not from the bag.",
    };
    if (bindsSouls(k)) return "Carried: a death spills no souls. The ring breaks instead.";
    if (k == .spirit_scroll_wolf) return "Carried: the bell can call Hildebrand.";
    if (k == .iron_key) return "Opens the one lock it was cut for.";
    return switch (use(k)) {
        .none => "No effect yet.",
        .regen => |r| std.fmt.bufPrintZ(buf, "Heals {d:.0}% of max HP over {d:.0}s.", .{ r.frac * 100, r.secs }) catch "Heals over time.",
        .lob => |l| std.fmt.bufPrintZ(buf, "Thrown at the reticle: {d:.0} physical + {d:.0} {s}, {d:.0} poise.", .{
            l.dmg,
            l.fire + l.lightning,
            if (l.lightning > 0) @as([]const u8, "lightning") else "fire",
            l.poise,
        }) catch "Thrown for damage.",
        .ward => |w| std.fmt.bufPrintZ(buf, "+{d:.0} Chaos resistance for {d:.0}s. Refreshes, never stacks.", .{ w.chaos, w.secs }) catch "Wards off Chaos.",
        .wind => |w| std.fmt.bufPrintZ(buf, "Gives back {d:.0}% of stamina at once, and lets the winded lockout go.", .{w.share * 100}) catch "Gives stamina back.",
        .grease => |gr| std.fmt.bufPrintZ(buf, "Sword hangs +{d:.0}% of its blow as fire for {d:.0}s. Refreshes, never stacks.", .{ gr.frac * 100, gr.secs }) catch "Sets the blade alight.",
        .souls => |s| std.fmt.bufPrintZ(buf, "Crushed for {d} souls, on the spot.", .{s.n}) catch "Worth souls.",
        .brew => |b| std.fmt.bufPrintZ(buf, "Stamina comes back {d:.1}x as fast for {d:.0}s. Refreshes, never stacks.", .{ b.mult, b.secs }) catch "Stamina returns faster.",
    };
}

/// How big a buffer `effect` needs. The longest line is the `lob`'s, and a `bufPrintZ` that does not fit falls
/// back to a bare phrase — legible, but it drops the numbers, which are the whole point of the line.
pub const EFFECT_BUF: usize = 128;

/// THE TWO THE FLASK SYSTEM OWNS. They sit on the quick bar like anything else, but their charges live in
/// `combat.Flasks` and come back at a bonfire, so spending one never touches the bag. Named here rather than
/// in `combat` because it is a fact about the ITEM; `combat.flaskOf` is the same question answered as a
/// `FlaskKind`, and it cannot live here — `combat` imports this file and not the other way about.
pub fn isFlask(k: Kind) bool {
    return k == .crimson_flask or k == .cerulean_flask;
}

/// THE ONE THING IN THE BAG THAT SPENDS ITSELF WITHOUT BEING USED — DS's Ring of Sacrifice. A death takes
/// the RING instead of the souls, so what you were carrying stays carried and nothing is left on the ground
/// to walk back for. Named here rather than tested for by kind at the death site, exactly as `isFlask` is:
/// it is a fact about the ITEM, and a second binding charm should be one row here and no edit at all there.
pub fn bindsSouls(k: Kind) bool {
    return k == .soul_binding_ring;
}

/// …and WHAT MAY GO ON THE QUICK BAR: a flask, or anything with an effect. There is no point carrying a
/// kobold fang into a fight on the one bar you are allowed to reach during it.
pub fn quickable(k: Kind) bool {
    return isFlask(k) or usable(k);
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

test "EVERY KIND SAYS WHAT IT DOES, and a kind with a dose says it in NUMBERS" {
    var buf: [EFFECT_BUF]u8 = undefined;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        const s = effect(k, &buf);
        try std.testing.expect(s.len > 10);
        // A dose that fell back to the bare phrase has lost its numbers, which is the whole line.
        if (usable(k)) {
            var digit = false;
            for (s) |c| digit = digit or std.ascii.isDigit(c);
            try std.testing.expect(digit);
        }
        // …and the three that work without a `Use` may not read as inert.
        if (isFlask(k) or bindsSouls(k) or k == .spirit_scroll_wolf or k == .iron_key) {
            try std.testing.expect(!std.mem.eql(u8, s, "No effect yet."));
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
            .lob => |l| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(l.dmg + l.fire + l.lightning > 0);
            },
            .ward => |w| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(w.chaos > 0 and w.secs > 0);
            },
            .wind => |w| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(w.share > 0 and w.share <= 1.0);
            },
            .grease => |gr| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(gr.frac > 0 and gr.frac <= 1.0);
                try std.testing.expect(gr.secs > 0);
            },
            .souls => |s| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(s.n > 0);
            },
            .brew => |b| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(b.mult > 1.0);
                try std.testing.expect(b.secs > 0);
            },
        }
    }
    try std.testing.expect(found >= 1);
}

test "THE BINDING RING IS NOT A TOOL — it is spent by DYING, and nothing else in the bag is" {
    var n: usize = 0;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (!bindsSouls(k)) continue;
        n += 1;
        // It must not offer a Confirm: pressing Use on it would promise something the mechanic never does.
        try std.testing.expect(!usable(k));
        try std.testing.expect(!quickable(k)); // …nor a socket on the bar it can never be spent from
        try std.testing.expectEqual(Use.none, use(k));
    }
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expect(bindsSouls(.soul_binding_ring));
    try std.testing.expect(!bindsSouls(.leech_signet)); // the other ring binds nothing
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
