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
    /// WHOSE ROW THIS IS, written out so the table can be read (and reordered) without counting — the comptime walk below pins it against `wf.FoeKind`'s own order.
    foe: wf.FoeKind,
    common: ?item.Kind,
    /// **HOW OFTEN IT ACTUALLY LEAVES IT.** Guaranteed first time out and it was far too much — every corpse in a warband a glow. A drop has to be a small event. The boss is the one row that never rolls (`BOSS_ALWAYS`): a 2400-soul body that leaves nothing is the worst outcome this table has.
    odds: f32 = COMMON,
    rare: ?item.Kind = null,
    chance: f32 = 0,
};

pub const RARE_CAP: f32 = 0.85;

pub const MAX_PER_BODY: usize = 2;

/// One row per `wf.FoeKind` IN ITS ORDER — a comptime walk pins it, so a creature added to that enum is a compile error here until it has said what it leaves. **WHAT EACH ONE DROPS IS WHAT IT IS**, and most were already written into the item's own description long before anything dropped.
pub const TABLE = [_]Row{
    .{ .foe = .toad, .common = .bloodgrass, .rare = .toadflesh_broth, .chance = 0.14 },

    // **THE ONE BODY IN THE GAME THAT IS CARRYING ARROWS.** Nothing dropped them at all, and with the bonfire's
    // free refill gone that left the whole map holding four sheaves in two containers — a bow with 40 shots in it
    // and then never again. `BIG` because this is the only tap: a sheaf is 10, and the archer is common.
    // Bloodgrass is not lost with it — the toad, the broodling and the ravager all still leave it.
    .{ .foe = .archer, .common = .plain_arrows, .odds = BIG, .rare = .fire_arrows, .chance = 0.14 },

    .{ .foe = .ogre, .common = .second_wind, .odds = BIG, .rare = .bloodtinge_signet, .chance = 0.12 },

    .{ .foe = .berserker, .common = .kobold_fang },
    // The same purse a rung up: the body that leaves a brick of salt is the one that sometimes leaves the whole offering.
    .{ .foe = .priest, .common = .pilgrims_salt, .odds = UNCOMMON, .rare = .pilgrims_offering, .chance = 0.10 },
    // THE ANSWER TO THE SLING IS ON THE SLINGER — the one body in the warband that throws fire is where the draught that turns it comes from.
    .{ .foe = .slinger, .common = .kobold_fang, .rare = .kiln_draught, .chance = 0.16 },

    .{ .foe = .brood_mother, .common = .purgeleaf, .odds = UNCOMMON, .rare = .spidersilk_moccasins, .chance = 0.14 },
    .{ .foe = .broodling, .common = .bloodgrass },
    .{ .foe = .brood_sac, .common = null },

    .{ .foe = .shieldman, .common = .pitted_helm, .odds = UNCOMMON },
    .{ .foe = .greatsword, .common = .quilted_gambeson, .odds = UNCOMMON },

    .{ .foe = .shade, .common = .nameless_soul, .odds = UNCOMMON, .rare = .loop_of_chance, .chance = 0.14 },

    // …and the gut packed into the dirk's groove is the leechfly's own (`item.describe`).
    .{ .foe = .leechfly, .common = .bloodgrass, .rare = .envenomed_dagger, .chance = 0.12 },

    .{ .foe = .rooted, .common = .fire_tallow, .odds = UNCOMMON },

    .{ .foe = .shroom, .common = .purgeleaf, .rare = .sporeling_cap, .chance = 0.18 },

    // THE BONE KNIGHT — the one row that never rolls.
    .{ .foe = .bone_knight, .common = .soul_binding_ring, .odds = BOSS_ALWAYS },

    .{ .foe = .delver, .common = .smithing_stone, .odds = UNCOMMON },

    // The one thing in the world that deals cold carries the coating that gives it back.
    .{ .foe = .necromancer, .common = .nameless_soul, .odds = BIG, .rare = .rimewax, .chance = 0.20 },

    .{ .foe = .florid_ravager, .common = .bloodgrass },
    .{ .foe = .mushroom_mage, .common = .purgeleaf, .odds = UNCOMMON },

    .{ .foe = .fen_lurker, .common = .ironwort_tea, .odds = UNCOMMON },
    .{ .foe = .spore_golem, .common = .purgeleaf, .odds = UNCOMMON },

    // **THE ONE BODY A PRIEST CAN MAKE MORE OF LEAVES NOTHING** — the supply is a cooldown (`ancientpriest.RAISE_CD`), so any odds at all here is a farm with a timer on it rather than a drop.
    .{ .foe = .bone_skitterer, .common = null },
    .{ .foe = .ancient_priest, .common = .rimeward_mantle, .odds = UNCOMMON },
    // …and the hollow leaves the bronze off its own bell, with the jar of lightning that answers it behind.
    .{ .foe = .tolling_hollow, .common = .gravebell_amulet, .odds = UNCOMMON, .rare = .thundercrock, .chance = 0.16 },
    // **THE THING THAT ADDLES YOU CARRIES WHAT STOPS IT** — the hood came off a body a mile from any bell.
    .{ .foe = .mourner, .common = .wax_stopped_hood, .odds = UNCOMMON, .rare = .wakers_nail, .chance = 0.12 },
    // **THE FAT IN THE JAR IS RENDERED OFF ONE OF THESE** (`item.describe`).
    .{ .foe = .slumber_bloom, .common = .purgeleaf, .rare = .nightcap_grease, .chance = 0.20 },
    // **IT CARRIES ITS OWN ANSWER** — the draught is the fire ward, off the one body whose whole threat is fire.
    .{ .foe = .cinder_wake, .common = .ashen_amulet, .odds = UNCOMMON, .rare = .kiln_draught, .chance = 0.18 },
    .{ .foe = .rotgorger, .common = .sporeling_cap, .odds = UNCOMMON, .rare = .sporecrown, .chance = 0.14 },
    // **BARK THAT LIGHTS WET IS TALLOW BY ANOTHER NAME** — the thing that burns it is what it leaves.
    .{ .foe = .birchwight, .common = .fire_tallow, .odds = UNCOMMON, .rare = .rimewax, .chance = 0.14 },
    // **THE SALT IS THE CREATURE** — it leaves the crust it was wearing.
    .{ .foe = .salt_husk, .common = .pilgrims_salt, .rare = .ironwort_tea, .chance = 0.12 },
    .{ .foe = .fish_spearman, .common = .bloodgrass, .rare = .fang_dirk, .chance = 0.10 },
    .{ .foe = .fish_netter, .common = .spidersilk_moccasins, .odds = UNCOMMON, .rare = .marchboots, .chance = 0.12 },
    // **THE ONE WHO PUTS HEALTH BACK IS CARRYING SOME** — the biggest purse in the band, and it earns it.
    .{ .foe = .fish_shaman, .common = .crimson_flask, .odds = UNCOMMON, .rare = .second_wind, .chance = 0.14 },
};

pub const NFOE = @typeInfo(wf.FoeKind).@"enum".fields.len;

/// **THE BODIES THAT ARE ALLOWED TO LEAVE NOTHING, AND WHY** — an egg sac is not a corpse, and a skitterer a priest clawed out of the ground is a body whose supply is a cooldown. Everything else must say what it drops or the table refuses to compile.
pub const LEAVES_NOTHING = [_]wf.FoeKind{ .brood_sac, .bone_skitterer };

pub fn leavesNothing(k: wf.FoeKind) bool {
    for (LEAVES_NOTHING) |n| {
        if (n == k) return true;
    }
    return false;
}

comptime {
    if (TABLE.len != NFOE) @compileError("drops: TABLE is not one row per FoeKind");
    for (TABLE, 0..) |row, i| {
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
    // A row with no rare on it stays at zero however lucky he is. **NOT THE ARCHER ANY MORE** — it carries the
    // fire sheaf now that it is the only body in the game dropping arrows at all; the broodling leaves grass.
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
