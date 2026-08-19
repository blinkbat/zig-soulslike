const std = @import("std");
const item = @import("item.zig");
const mathx = @import("mathx.zig");
const stats = @import("stats.zig");
const wf = @import("worldfmt.zig");

// WHAT A BODY LEAVES BEHIND BESIDES ITS SOULS. Every creature in the game has been worth exactly one number
// since souls landed, and a number is not a reason to fight a particular thing — it is a reason to fight
// whatever is cheapest. A TABLE is: you go to the marsh for the mantle and to the ogres for the club.
//
// **IT GOES ON THE GROUND, NOT INTO HIS HANDS** (owner's call) — a glow where the body fell, on exactly the
// terms the map's own placed ones stand on (`pickup.Pickups.spawn`). A thing that arrived in the bag with a
// toast would be a number going up; a thing lying in the grass is somewhere to walk.
//
// **AND IT IS ROLLED OFF A SEEDED STREAM** (`game.dropRng`), never wall time — `--shot` has to stay
// reproducible, and a drop table read off `rl.getTime()` is the one thing that could not be.

// **HOW OFTEN A BODY LEAVES ANYTHING AT ALL — THREE NUMBERS, AND THE LADDER IS THE SOULS LADDER.** What a
// creature is worth already ranks every one of them (60 for a toad, 2400 for the knight), so the drop rate
// rides that rather than being a fourth ranking somebody has to keep in step. A fight is five or six bodies:
// at `COMMON` that is a glow every second fight, which is what makes one worth walking to.

/// The wayside things — toads, broodlings, sporelings, flies, the rank and file.
pub const COMMON: f32 = 0.06;
/// …the ones that take a real fight: the skeletons, the delver, the lurker, the mage.
pub const UNCOMMON: f32 = 0.10;
/// …and the ones you go looking for. Still not a certainty: a giant is a fight, not a vending machine.
pub const BIG: f32 = 0.22;
/// **THE BOSS IS THE ONE ROW THAT NEVER ROLLS.**
pub const BOSS_ALWAYS: f32 = 1.0;

/// ONE ROW. `rare` is the half LUCK reads and the only half it reads: scale a body's guaranteed drop too and
/// the attribute does nothing at all, since what a weight means is only ever its share of the total.
pub const Row = struct {
    /// WHOSE ROW THIS IS, written out so the table can be read (and reordered) without counting — the
    /// comptime walk below pins it against `wf.FoeKind`'s own order.
    foe: wf.FoeKind,
    /// What it leaves when it leaves anything. `null` for the thing that is not a body.
    common: ?item.Kind,
    /// **HOW OFTEN IT ACTUALLY LEAVES IT.** Guaranteed first time out and it was far too much — every corpse
    /// in a warband a glow, so the ground after a fight was a row of lights and none of them meant anything.
    /// A drop has to be a small event. The boss is the one row that never rolls (`BOSS_ALWAYS`): a 2400-soul
    /// body that leaves nothing is the worst outcome this table has.
    odds: f32 = COMMON,
    /// …and what it MIGHT, on top of that. `chance` is at the starting sheet's luck; `stats.findFor`
    /// multiplies it and `roll` clamps, so a maxed-luck hero can never be promised something.
    rare: ?item.Kind = null,
    chance: f32 = 0,
};

/// **NO ROW MAY EVER BE A CERTAINTY** however much luck is stacked behind it — the guaranteed drop is the
/// guaranteed drop, and a rare that always lands is just a second one of those.
pub const RARE_CAP: f32 = 0.85;

/// **THE MOST ONE BODY CAN LEAVE**, and it is this table's own arithmetic rather than a round number: a row
/// is one common and at most one rare. `pickup.DROP_MAX` is the same fact one module along — the glow has to
/// be able to hold whatever this hands it — and `game.zig` pins the two together, since it is the one file
/// that can see both ends (`env.HERO_R_PIN`'s arrangement).
pub const MAX_PER_BODY: usize = 2;

/// THE TABLE, one row per `wf.FoeKind` IN ITS ORDER — a comptime walk below pins it, so a creature added to
/// that enum is a compile error here until it has said what it leaves.
///
/// **WHAT EACH ONE DROPS IS WHAT IT IS.** Most of these were already written into the item's own description
/// long before anything dropped: the signet is "cut from a leech's beak", the broth is toadflesh, the fang is
/// a kobold's, the cap is a sporeling's, and the club is the thing the ogre is swinging at you.
pub const TABLE = [_]Row{
    // THE MARSH. A toad is the cheapest thing in the world and the broth is cut out of one, so it is the one
    // rank-and-file body with a rare worth walking over for.
    .{ .foe = .toad, .common = .bloodgrass, .rare = .toadflesh_broth, .chance = 0.14 },

    // THE SKELETON ARCHER — dry bone and a bundle of sticks. There is nothing on it.
    .{ .foe = .archer, .common = .bloodgrass },

    // THE OGRE. A giant is a fight, so it is on the `BIG` rate — and what it leaves is the breath you needed
    // halfway through having it.
    .{ .foe = .ogre, .common = .second_wind, .odds = BIG },

    // THE WARBAND. Two of the three leave a fang; the PRIEST is the one worth picking out of the pack, which
    // is the same thing the fight already says about him.
    .{ .foe = .berserker, .common = .kobold_fang },
    .{ .foe = .priest, .common = .pilgrims_salt, .odds = UNCOMMON },
    .{ .foe = .slinger, .common = .kobold_fang },

    // THE BROOD. Venom answers venom: the mother is where the purgeleaf comes from.
    .{ .foe = .brood_mother, .common = .purgeleaf, .odds = UNCOMMON },
    .{ .foe = .broodling, .common = .bloodgrass },
    // …AND THE SAC IS NOT A BODY. It is a fixture that bursts, its deaths are billed by the COUNT rather than
    // through `justDied` (`game.zig`'s burst tally), and a thing that hatches has nothing to leave.
    .{ .foe = .brood_sac, .common = null },

    // THE MUSTER. Each of the two leaves the piece it is actually wearing.
    .{ .foe = .shieldman, .common = .pitted_helm, .odds = UNCOMMON },
    .{ .foe = .greatsword, .common = .quilted_gambeson, .odds = UNCOMMON },

    // THE SHADE — the one thing that drains focus, and the one body that is nothing BUT a soul.
    .{ .foe = .shade, .common = .nameless_soul, .odds = UNCOMMON },

    // THE LEECHFLY. Chitin and a beak, and the signet cut from one is not the fly's to give.
    .{ .foe = .leechfly, .common = .bloodgrass },

    // THE ROOTED. A snag is where the tallow comes from, and fire is what answers half the wood.
    .{ .foe = .rooted, .common = .fire_tallow, .odds = UNCOMMON },

    // THE SPORELING. Its own CAP is the rare, which is what that item was always drawn as: the thing that
    // wards the cloud, off the thing that lays it.
    .{ .foe = .shroom, .common = .purgeleaf, .rare = .sporeling_cap, .chance = 0.18 },

    // THE BONE KNIGHT — the one row that never rolls. A 2400-soul body that leaves nothing is the worst
    // outcome this table has.
    .{ .foe = .bone_knight, .common = .soul_binding_ring, .odds = BOSS_ALWAYS },

    // THE DELVER, which comes up through the ground and brings some of it with it.
    .{ .foe = .delver, .common = .smithing_stone, .odds = UNCOMMON },

    // THE NECROMANCER. It spends its fight handing bodies back their souls; on the `BIG` rate, because it is
    // the hardest thing out here that is not the boss.
    .{ .foe = .necromancer, .common = .nameless_soul, .odds = BIG },

    // THE WOOD'S OWN THREE — plant flesh, and two of them are mushrooms.
    .{ .foe = .florid_ravager, .common = .bloodgrass },
    .{ .foe = .mushroom_mage, .common = .purgeleaf, .odds = UNCOMMON },

    // THE FEN LURKER, which lives in the water the ironwort grows out of.
    .{ .foe = .fen_lurker, .common = .ironwort_tea, .odds = UNCOMMON },
};

pub const NFOE = @typeInfo(wf.FoeKind).@"enum".fields.len;

comptime {
    // EVERY KIND HAS SAID SOMETHING, AND EVERY ROW IS THE ONE IT NAMES. A row inserted into `FoeKind` shifts
    // a positional list silently and every creature starts dropping its neighbour's item, so each row carries
    // its own `foe` and this is what checks it — `props.INFO`'s arrangement one table along.
    if (TABLE.len != NFOE) @compileError("drops: TABLE is not one row per FoeKind");
    for (TABLE, 0..) |row, i| {
        const k: wf.FoeKind = @enumFromInt(i);
        if (row.foe != k) {
            @compileError("drops: row " ++ @tagName(row.foe) ++ " sits where " ++ @tagName(k) ++ " should be");
        }
        if (row.common == null and k != .brood_sac) {
            @compileError("drops: " ++ @tagName(k) ++ " leaves nothing — say `.common = null` on purpose");
        }
        // A rare row and its odds only mean anything together.
        if ((row.rare != null) != (row.chance > 0)) {
            @compileError("drops: " ++ @tagName(k) ++ " names a rare and its chance disagree");
        }
        if (row.chance > RARE_CAP) @compileError("drops: " ++ @tagName(k) ++ " is rarer than its own cap");
    }
}

/// WHAT ONE DEATH LEAVES — its own row if the roll takes it, and the rare on top if the second one does.
/// Written into `out` and returned as a slice, so the caller puts the whole handful in one glow.
///
/// **TWO DRAWS, ALWAYS, WHATEVER THE ROW SAYS** — even for the sac, which has nothing to leave, and even for
/// the boss, which never rolls. A table where one creature spent a number and another did not would make the
/// sequence a function of what you chose to fight, which is not a thing a seeded stream may be.
///
/// …AND THEY ARE TWO SEPARATE DRAWS. Read off one number the rare would ride the common: with the rare's odds
/// above the common's, every body that dropped anything would drop both.
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
        // THROUGH `rareOdds`, not a second copy of it: the page prints that number and the roll has to be it.
        if (rr < rareOdds(k, luck)) {
            out[n] = rare;
            n += 1;
        }
    }
    return out[0..n];
}

/// **THE ODDS A RARE ACTUALLY LANDS — the one place luck is multiplied in and the one place the cap bites.**
/// Read by the roll itself, by the page that prints it and by the tests, so none of the three can advertise a
/// figure another of them does not use.
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
                // Whatever came out is one of the two things this row names, and never another creature's.
                try std.testing.expect(got == TABLE[i].common or got == TABLE[i].rare);
            }
        }
        // The sac leaves nothing ever; the boss leaves something every time; everything else sometimes.
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
    try std.testing.expectEqual(@as(f32, 0), rareOdds(.ogre, stats.MAX)); // no rare row, unmoved by any of it
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
    _ = roll(.brood_sac, stats.START, &a, &buf); // nothing to leave, and it still spends its two numbers…
    _ = roll(.bone_knight, stats.START, &b, &buf); // …as does the one that never rolls
    try std.testing.expectEqual(a.float(), b.float());
}
