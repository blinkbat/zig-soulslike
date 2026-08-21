const std = @import("std");
const item = @import("item.zig");
const mathx = @import("../core/mathx.zig");
const stats = @import("stats.zig");
const wf = @import("../world/worldfmt.zig");



pub const COMMON: f32 = 0.06;
pub const UNCOMMON: f32 = 0.10;
pub const BIG: f32 = 0.22;
/// **THE BOSS IS THE ONE ROW THAT NEVER ROLLS.**
pub const BOSS_ALWAYS: f32 = 1.0;

pub const Row = struct {
    /// WHOSE ROW THIS IS, written out so the table can be read (and reordered) without counting — the
    /// comptime walk below pins it against `wf.FoeKind`'s own order.
    foe: wf.FoeKind,
    common: ?item.Kind,
    /// **HOW OFTEN IT ACTUALLY LEAVES IT.** Guaranteed first time out and it was far too much — every corpse
    /// in a warband a glow, so the ground after a fight was a row of lights and none of them meant anything.
    /// A drop has to be a small event. The boss is the one row that never rolls (`BOSS_ALWAYS`): a 2400-soul
    /// body that leaves nothing is the worst outcome this table has.
    odds: f32 = COMMON,
    rare: ?item.Kind = null,
    chance: f32 = 0,
};

pub const RARE_CAP: f32 = 0.85;

pub const MAX_PER_BODY: usize = 2;

/// One row per `wf.FoeKind` IN ITS ORDER — a comptime walk pins it, so a creature added to that enum is a
/// compile error here until it has said what it leaves. **WHAT EACH ONE DROPS IS WHAT IT IS**, and most were
/// already written into the item's own description long before anything dropped.
pub const TABLE = [_]Row{
    .{ .foe = .toad, .common = .bloodgrass, .rare = .toadflesh_broth, .chance = 0.14 },

    .{ .foe = .archer, .common = .bloodgrass },

    .{ .foe = .ogre, .common = .second_wind, .odds = BIG },

    .{ .foe = .berserker, .common = .kobold_fang },
    .{ .foe = .priest, .common = .pilgrims_salt, .odds = UNCOMMON },
    .{ .foe = .slinger, .common = .kobold_fang },

    .{ .foe = .brood_mother, .common = .purgeleaf, .odds = UNCOMMON },
    .{ .foe = .broodling, .common = .bloodgrass },
    .{ .foe = .brood_sac, .common = null },

    .{ .foe = .shieldman, .common = .pitted_helm, .odds = UNCOMMON },
    .{ .foe = .greatsword, .common = .quilted_gambeson, .odds = UNCOMMON },

    .{ .foe = .shade, .common = .nameless_soul, .odds = UNCOMMON },

    .{ .foe = .leechfly, .common = .bloodgrass },

    .{ .foe = .rooted, .common = .fire_tallow, .odds = UNCOMMON },

    .{ .foe = .shroom, .common = .purgeleaf, .rare = .sporeling_cap, .chance = 0.18 },

    // THE BONE KNIGHT — the one row that never rolls. A 2400-soul body that leaves nothing is the worst
    // outcome this table has.
    .{ .foe = .bone_knight, .common = .soul_binding_ring, .odds = BOSS_ALWAYS },

    .{ .foe = .delver, .common = .smithing_stone, .odds = UNCOMMON },

    .{ .foe = .necromancer, .common = .nameless_soul, .odds = BIG },

    .{ .foe = .florid_ravager, .common = .bloodgrass },
    .{ .foe = .mushroom_mage, .common = .purgeleaf, .odds = UNCOMMON },

    .{ .foe = .fen_lurker, .common = .ironwort_tea, .odds = UNCOMMON },
    .{ .foe = .spore_golem, .common = .purgeleaf, .odds = UNCOMMON },
};

pub const NFOE = @typeInfo(wf.FoeKind).@"enum".fields.len;

comptime {
    if (TABLE.len != NFOE) @compileError("drops: TABLE is not one row per FoeKind");
    for (TABLE, 0..) |row, i| {
        const k: wf.FoeKind = @enumFromInt(i);
        if (row.foe != k) {
            @compileError("drops: row " ++ @tagName(row.foe) ++ " sits where " ++ @tagName(k) ++ " should be");
        }
        if (row.common == null and k != .brood_sac) {
            @compileError("drops: " ++ @tagName(k) ++ " leaves nothing — say `.common = null` on purpose");
        }
        if ((row.rare != null) != (row.chance > 0)) {
            @compileError("drops: " ++ @tagName(k) ++ " names a rare and its chance disagree");
        }
        if (row.chance > RARE_CAP) @compileError("drops: " ++ @tagName(k) ++ " is rarer than its own cap");
    }
}

pub fn roll(k: wf.FoeKind, luck: u8, rng: *mathx.Rng, out: *[MAX_PER_BODY]item.Kind) []const item.Kind {
    const row = TABLE[@intFromEnum(k)];
    const rc = rng.float();
    const rr = rng.float();
    var n: usize = 0;
    if (row.common) |c| {
        if (rc < row.odds) {
            out[n] = c;
            n += 1;
        }
    }
    if (row.rare) |rare| {
        if (rr < rareOdds(k, luck)) {
            out[n] = rare;
            n += 1;
        }
    }
    return out[0..n];
}

pub fn rareOdds(k: wf.FoeKind, luck: u8) f32 {
    const row = TABLE[@intFromEnum(k)];
    if (row.rare == null) return 0;
    return mathx.minF(row.chance * stats.findFor(luck), RARE_CAP);
}


test "A BODY MOSTLY LEAVES NOTHING, and what it does leave is its own row" {
    var buf: [MAX_PER_BODY]item.Kind = undefined;
    var rng = mathx.Rng.init(0xD0D0);
    for (0..NFOE) |i| {
        const k: wf.FoeKind = @enumFromInt(i);
        var seen: usize = 0;
        for (0..4000) |_| {
            for (roll(k, stats.START, &rng, &buf)) |got| {
                seen += 1;
                try std.testing.expect(got == TABLE[i].common or got == TABLE[i].rare);
            }
        }
        if (k == .brood_sac) try std.testing.expectEqual(@as(usize, 0), seen);
        if (k == .bone_knight) try std.testing.expectEqual(@as(usize, 4000), seen);
    }
}

test "THE COMMON ROW LANDS AT ABOUT THE ODDS IT ADVERTISES, and a fight is mostly empty ground" {
    var buf: [MAX_PER_BODY]item.Kind = undefined;
    var rng = mathx.Rng.init(0xFA11);
    const N = 40000;
    var hits: usize = 0;
    for (0..N) |_| {
        for (roll(.toad, stats.START, &rng, &buf)) |got| {
            if (got == .bloodgrass) hits += 1;
        }
    }
    const seen = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(N));
    try std.testing.expectApproxEqAbs(COMMON, seen, 0.01);
    // …and the thing that made it "way too common" cannot come back: nothing on the rank and file is a
    // certainty, and a six-body fight leaves a glow well under half the time.
    try std.testing.expect(COMMON < 0.10);
    const emptyFight = std.math.pow(f32, 1.0 - COMMON, 6);
    try std.testing.expect(emptyFight > 0.5);
    std.debug.print(
        "\n  drops: toad {d:.1}% per body, a 6-body fight leaves nothing {d:.0}% of the time; boss {d:.0}%\n",
        .{ seen * 100, emptyFight * 100, BOSS_ALWAYS * 100 },
    );
}

test "LUCK IS THE RARE ROW AND NOTHING ELSE — the common's odds do not move with it" {
    try std.testing.expect(rareOdds(.toad, 1) < rareOdds(.toad, stats.START));
    try std.testing.expect(rareOdds(.toad, stats.START) < rareOdds(.toad, stats.MAX));
    try std.testing.expectEqual(@as(f32, 0), rareOdds(.ogre, stats.MAX));
    for (0..NFOE) |i| try std.testing.expect(rareOdds(@enumFromInt(i), stats.MAX) <= RARE_CAP);
    std.debug.print(
        "  rares: toad broth {d:.1}% -> {d:.1}%, sporeling cap {d:.1}% -> {d:.1}%\n",
        .{
            rareOdds(.toad, 1) * 100,           rareOdds(.toad, stats.MAX) * 100,
            rareOdds(.shroom, stats.START) * 100, rareOdds(.shroom, stats.MAX) * 100,
        },
    );
}

test "THE STREAM ADVANCES BY THE SAME AMOUNT PER KILL WHATEVER DIED" {
    var buf: [MAX_PER_BODY]item.Kind = undefined;
    var a = mathx.Rng.init(7);
    var b = mathx.Rng.init(7);
    _ = roll(.brood_sac, stats.START, &a, &buf);
    _ = roll(.bone_knight, stats.START, &b, &buf);
    try std.testing.expectEqual(a.float(), b.float());
}
