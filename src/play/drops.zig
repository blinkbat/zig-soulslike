const std = @import("std");
const item = @import("item.zig");
const mathx = @import("../core/mathx.zig");
const stats = @import("stats.zig");
const wf = @import("../world/worldfmt.zig");
const foe = @import("../foes/foe.zig");



pub const COMMON: f32 = 0.06;
pub const UNCOMMON: f32 = 0.10;
pub const BIG: f32 = 0.22;
pub const BOSS_ALWAYS: f32 = 1.0;

pub const Coin = enum {
    none,
    few,
    purse,
    heavy,
    hoard,

    pub fn band(self: Coin) [2]u32 {
        return switch (self) {
            .none => .{ 0, 0 },
            .few => .{ 4, 11 },
            .purse => .{ 14, 34 },
            .heavy => .{ 40, 85 },
            .hoard => .{ 120, 260 },
        };
    }

    pub fn odds(self: Coin) f32 {
        return switch (self) {
            .none => 0,
            .few => 0.55,
            .purse => 0.62,
            .heavy => 0.70,
            .hoard => 1.0,
        };
    }
};

pub const Row = struct {
    /// WHOSE ROW THIS IS, written out so the table can be read (and reordered) without counting — the comptime walk below pins it against `wf.FoeKind`'s own order.
    foe: wf.FoeKind,
    common: ?item.Kind,
    /// **HOW OFTEN IT ACTUALLY LEAVES IT.** Guaranteed first time out and it was far too much — every corpse in a warband a glow. A drop has to be a small event. The boss is the one row that never rolls (`BOSS_ALWAYS`): a 2400-soul body that leaves nothing is the worst outcome this table has.
    odds: f32 = COMMON,
    rare: ?item.Kind = null,
    chance: f32 = 0,
    /// **A PURSE, AND IT IS A SEPARATE ROLL FROM THE ITEM.** Defaults to `.none`, which the comptime block below
    /// refuses for anything `foe.Nature.humanoid` — a man with pockets and nothing in them has to say why.
    gold: Coin = .none,
};

pub const RARE_CAP: f32 = 0.85;

pub const MAX_PER_BODY: usize = 2;

/// One row per `wf.FoeKind` IN ITS ORDER — a comptime walk pins it, so a creature added to that enum is a compile error here until it has said what it leaves. **WHAT EACH ONE DROPS IS WHAT IT IS**, and most were already written into the item's own description long before anything dropped.
pub const BANK = [_]Row{
    .{ .foe = .toad, .common = .bloodgrass, .rare = .toadflesh_broth, .chance = 0.14 },

    // free refill gone that left the whole map holding four sheaves in two containers — a bow with 40 shots in it
    // and then never again. `BIG` because this is the only tap: a sheaf is 10, and the archer is common.
    .{ .foe = .archer, .common = .plain_arrows, .odds = BIG, .rare = .fire_arrows, .chance = 0.14, .gold = .few },

    .{ .foe = .ogre, .common = .second_wind, .odds = BIG, .rare = .bloodtinge_signet, .chance = 0.12, .gold = .heavy },

    .{ .foe = .berserker, .common = .kobold_fang, .gold = .few },
    .{ .foe = .priest, .common = .pilgrims_salt, .odds = UNCOMMON, .rare = .pilgrims_offering, .chance = 0.10, .gold = .purse },
    .{ .foe = .slinger, .common = .kobold_fang, .rare = .kiln_draught, .chance = 0.16, .gold = .few },

    .{ .foe = .brood_mother, .common = .purgeleaf, .odds = UNCOMMON, .rare = .spidersilk_moccasins, .chance = 0.14 },
    .{ .foe = .broodling, .common = .bloodgrass },
    .{ .foe = .brood_sac, .common = null },

    // was carrying alone — 30 stones takes an armament to `hero.TIER_MAX` and one uncommon body could not pay it.
    .{ .foe = .shieldman, .common = .pitted_helm, .odds = UNCOMMON, .rare = .smithing_stone, .chance = 0.12, .gold = .few },
    .{ .foe = .greatsword, .common = .quilted_gambeson, .odds = UNCOMMON, .rare = .smithing_stone, .chance = 0.14, .gold = .purse },

    .{ .foe = .shade, .common = .nameless_soul, .odds = UNCOMMON, .rare = .loop_of_chance, .chance = 0.14 },

    .{ .foe = .leechfly, .common = .bloodgrass, .rare = .envenomed_dagger, .chance = 0.12 },

    .{ .foe = .rooted, .common = .fire_tallow, .odds = UNCOMMON },

    .{ .foe = .shroom, .common = .purgeleaf, .rare = .sporeling_cap, .chance = 0.18 },

    .{ .foe = .bone_knight, .common = .soul_binding_ring, .odds = BOSS_ALWAYS, .rare = .smithing_stone, .chance = 0.5, .gold = .hoard },

    .{ .foe = .delver, .common = .smithing_stone, .odds = UNCOMMON, .gold = .few },

    .{ .foe = .necromancer, .common = .nameless_soul, .odds = BIG, .rare = .rimewax, .chance = 0.20, .gold = .purse },

    .{ .foe = .fungal_deer, .common = .bloodgrass },
    .{ .foe = .mushroom_mage, .common = .purgeleaf, .odds = UNCOMMON },

    .{ .foe = .fen_lurker, .common = .ironwort_tea, .odds = UNCOMMON, .gold = .few },
    .{ .foe = .spore_golem, .common = .purgeleaf, .odds = UNCOMMON },

    .{ .foe = .bone_skitterer, .common = null },
    .{ .foe = .ancient_priest, .common = .rimeward_mantle, .odds = UNCOMMON, .gold = .purse },
    .{ .foe = .tolling_hollow, .common = .gravebell_amulet, .odds = UNCOMMON, .rare = .thundercrock, .chance = 0.16, .gold = .few },
    .{ .foe = .mourner, .common = .wax_stopped_hood, .odds = UNCOMMON, .rare = .wakers_nail, .chance = 0.12, .gold = .few },
    .{ .foe = .slumber_bloom, .common = .purgeleaf, .rare = .nightcap_grease, .chance = 0.20 },
    .{ .foe = .cinder_wake, .common = .ashen_amulet, .odds = UNCOMMON, .rare = .kiln_draught, .chance = 0.18 },
    .{ .foe = .rotgorger, .common = .sporeling_cap, .odds = UNCOMMON, .rare = .sporecrown, .chance = 0.14, .gold = .few },
    .{ .foe = .birchwight, .common = .fire_tallow, .odds = UNCOMMON, .rare = .rimewax, .chance = 0.14 },
    .{ .foe = .salt_husk, .common = .pilgrims_salt, .rare = .ironwort_tea, .chance = 0.12, .gold = .few },
    .{ .foe = .fish_spearman, .common = .bloodgrass, .rare = .fang_dirk, .chance = 0.10, .gold = .few },
    .{ .foe = .fish_netter, .common = .spidersilk_moccasins, .odds = UNCOMMON, .rare = .marchboots, .chance = 0.12, .gold = .few },
    .{ .foe = .fish_shaman, .common = .crimson_flask, .odds = UNCOMMON, .rare = .second_wind, .chance = 0.14, .gold = .purse },
    .{ .foe = .blinkbat, .common = .bloodgrass, .odds = UNCOMMON, .rare = .crimson_flask, .chance = 0.16 },
    .{ .foe = .fungal_swordsman, .common = .purgeleaf, .odds = BOSS_ALWAYS, .rare = .envenomed_dagger, .chance = 0.5, .gold = .hoard },
    .{ .foe = .fungal_magus, .common = .purgeleaf, .odds = BOSS_ALWAYS, .rare = .scroll_babble, .chance = 0.5, .gold = .hoard },
    .{ .foe = .owlbear, .common = null },
};

pub const NFOE = @typeInfo(wf.FoeKind).@"enum".fields.len;

pub const LEAVES_NOTHING = [_]wf.FoeKind{ .brood_sac, .bone_skitterer, .owlbear };

pub fn leavesNothing(k: wf.FoeKind) bool {
    for (LEAVES_NOTHING) |n| {
        if (n == k) return true;
    }
    return false;
}

pub const NO_PURSE = [_]wf.FoeKind{};

pub fn noPurse(k: wf.FoeKind) bool {
    for (NO_PURSE) |n| {
        if (n == k) return true;
    }
    return false;
}

/// The live thirty-seven. `BANK` above is the revert (`play/tune.zig`), and it is what the walk below reads.
pub var TABLE: [BANK.len]Row = BANK;

comptime {
    if (BANK.len != NFOE) @compileError("drops: BANK is not one row per FoeKind");
    for (BANK) |row| {
        if (foe.traitsOf(row.foe).nature == .humanoid and row.gold == .none and !noPurse(row.foe)) {
            @compileError("drops: " ++ @tagName(row.foe) ++ " is a humanoid carrying no gold — give it a `.gold`" ++
                " band, or name it in `NO_PURSE` with a reason");
        }
    }
    const rungs = [_]Coin{ .few, .purse, .heavy, .hoard };
    for (rungs[1..], 0..) |hi, i| {
        if (hi.band()[0] <= rungs[i].band()[1]) @compileError("drops: the coin bands overlap");
    }
    for (BANK, 0..) |row, i| {
        const k: wf.FoeKind = @enumFromInt(i);
        if (row.foe != k) {
            @compileError("drops: row " ++ @tagName(row.foe) ++ " sits where " ++ @tagName(k) ++ " should be");
        }
        if (row.common == null and !leavesNothing(k)) {
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

/// **WHAT THE BODY'S PURSE ACTUALLY HELD**, or 0. **LUCK DOES NOT READ THIS** (`stats.inert`'s note).
pub fn rollGold(k: wf.FoeKind, rng: *mathx.Rng) u32 {
    const hit = rng.float();
    const pick = rng.float();
    const c = TABLE[@intFromEnum(k)].gold;
    if (c == .none or hit >= c.odds()) return 0;
    const b = c.band();
    const span: f32 = @floatFromInt(b[1] - b[0] + 1);
    return b[0] + @min(b[1] - b[0], @as(u32, @intFromFloat(pick * span)));
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
        // NOT an equality: the knight carries a stone at `.chance`, so the count is a range.
        if (k == .bone_knight) {
            try std.testing.expect(seen >= 4000);
            try std.testing.expect(seen <= 8000);
        }
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
    // …and the thing that made it "way too common" cannot come back: nothing on the rank and file is a certainty, and a six-body fight leaves a glow well under half the time.
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
    try std.testing.expectEqual(@as(f32, 0), rareOdds(.broodling, stats.MAX));
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

test "A MAN CARRIES COIN AND A MUSHROOM DOES NOT — what each nature actually pays a body" {
    var rng = mathx.Rng.init(0xC0FFEE);
    const NATS = [_]foe.Nature{ .humanoid, .undead, .beast, .plant, .demon };
    std.debug.print("\n", .{});
    var humanTotal: f64 = 0;
    var plantTotal: f64 = 0;
    var best: f64 = 0;
    for (NATS) |nat| {
        var bodies: usize = 0;
        var paid: u64 = 0;
        var dropped: usize = 0;
        const ROUNDS = 3000;
        for (0..NFOE) |i| {
            const k: wf.FoeKind = @enumFromInt(i);
            if (foe.traitsOf(k).nature != nat) continue;
            bodies += 1;
            for (0..ROUNDS) |_| {
                const g = rollGold(k, &rng);
                if (g > 0) dropped += 1;
                paid += g;
            }
        }
        const rolls: f64 = @floatFromInt(bodies * ROUNDS);
        const per = @as(f64, @floatFromInt(paid)) / rolls;
        std.debug.print("  {s: <9} {d:2} kinds | {d:4.0}% of corpses pay | {d:6.1} coins a body\n", .{
            @tagName(nat), bodies, 100.0 * @as(f64, @floatFromInt(dropped)) / rolls, per,
        });
        const freq = 100.0 * @as(f64, @floatFromInt(dropped)) / rolls;
        if (nat == .humanoid) humanTotal = freq else best = @max(best, freq);
        _ = &plantTotal;
    }
    std.debug.print("  humanoids pay on {d:.0}% of corpses against {d:.0}% for the next nature up\n", .{ humanTotal, best });
    try std.testing.expect(humanTotal > best);
    for (0..NFOE) |i| {
        const k: wf.FoeKind = @enumFromInt(i);
        const c = TABLE[i].gold;
        const b = c.band();
        for (0..500) |_| {
            const g = rollGold(k, &rng);
            if (g == 0) continue;
            try std.testing.expect(g >= b[0] and g <= b[1]);
        }
    }
}

test "WHAT A TIER COSTS IN BODIES — every row that carries stone, and the walk to +10" {
    const counter = @import("counter.zig");
    const heromod = @import("hero.zig");

    var carriers: usize = 0;
    var perBody: f64 = 0;
    std.debug.print("\n", .{});
    for (0..NFOE) |i| {
        const k: wf.FoeKind = @enumFromInt(i);
        const row = TABLE[i];
        const common: f64 = if (row.common == item.Kind.smithing_stone) row.odds else 0;
        const rare: f64 = if (row.rare == item.Kind.smithing_stone) rareOdds(k, stats.START) else 0;
        if (common + rare == 0) continue;
        carriers += 1;
        perBody += common + rare;
        std.debug.print("  {s: <16} {d:5.1}% a body\n", .{ wf.foeName(k), 100.0 * (common + rare) });
    }
    try std.testing.expect(carriers >= 4);

    const run = counter.ladderCost(0, heromod.TIER_MAX);
    const mean = perBody / @as(f64, @floatFromInt(carriers));
    std.debug.print("  {d} kinds carry stone, {d:.1}% a body on average\n", .{ carriers, 100.0 * mean });
    std.debug.print("  +{d} wants {d} stones = about {d:.0} stone-carrying bodies (was {d:.0} on the delver alone)\n", .{
        heromod.TIER_MAX,
        run.stones,
        @as(f64, @floatFromInt(run.stones)) / mean,
        @as(f64, @floatFromInt(run.stones)) / UNCOMMON,
    });
    try std.testing.expectEqual(item.Kind.smithing_stone, TABLE[@intFromEnum(wf.FoeKind.delver)].common.?);
    for (0..NFOE) |i| {
        const k: wf.FoeKind = @enumFromInt(i);
        if (TABLE[i].rare == item.Kind.smithing_stone) try std.testing.expect(rareOdds(k, stats.MAX) <= RARE_CAP);
    }
    for (0..NFOE) |i| {
        const k: wf.FoeKind = @enumFromInt(i);
        if (TABLE[i].common != item.Kind.smithing_stone and TABLE[i].rare != item.Kind.smithing_stone) continue;
        const nat = foe.traitsOf(k).nature;
        try std.testing.expect(nat == .undead or nat == .beast);
    }
}
