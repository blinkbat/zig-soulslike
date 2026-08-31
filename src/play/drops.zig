const std = @import("std");
const item = @import("item.zig");
const mathx = @import("../core/mathx.zig");
const stats = @import("stats.zig");
const wf = @import("../world/worldfmt.zig");
const foe = @import("../foes/foe.zig");



pub const COMMON: f32 = 0.06;
pub const UNCOMMON: f32 = 0.10;
pub const BIG: f32 = 0.22;
/// **THE BOSS IS THE ONE ROW THAT NEVER ROLLS.**
pub const BOSS_ALWAYS: f32 = 1.0;

/// **WHAT A BODY IS CARRYING.** A band and its odds, not a number, so a purse reads as a find rather than as a
/// wage — and so the whole economy retunes by moving five rows instead of thirty-seven.
pub const Coin = enum {
    none,
    few,
    purse,
    heavy,
    hoard,

    /// Coins, low and high. **THE BANDS DO NOT OVERLAP**, or a `heavy` that rolls low is a `purse` and the tier
    /// stops meaning anything on the body it came off.
    pub fn band(self: Coin) [2]u32 {
        return switch (self) {
            .none => .{ 0, 0 },
            .few => .{ 4, 11 },
            .purse => .{ 14, 34 },
            .heavy => .{ 40, 85 },
            .hoard => .{ 120, 260 },
        };
    }

    /// How often it actually leaves it. **OFTEN, WHICH IS THE POINT** (owner) — a purse is the drop that is
    /// supposed to be ordinary, where `Row.common` is the one that is supposed to be an event.
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
pub const TABLE = [_]Row{
    .{ .foe = .toad, .common = .bloodgrass, .rare = .toadflesh_broth, .chance = 0.14 },

    // **THE ONE BODY IN THE GAME THAT IS CARRYING ARROWS.** Nothing dropped them at all, and with the bonfire's
    // free refill gone that left the whole map holding four sheaves in two containers — a bow with 40 shots in it
    // and then never again. `BIG` because this is the only tap: a sheaf is 10, and the archer is common.
    // Bloodgrass is not lost with it — the toad, the broodling and the fungal deer all still leave it.
    .{ .foe = .archer, .common = .plain_arrows, .odds = BIG, .rare = .fire_arrows, .chance = 0.14, .gold = .few },

    .{ .foe = .ogre, .common = .second_wind, .odds = BIG, .rare = .bloodtinge_signet, .chance = 0.12, .gold = .heavy },

    .{ .foe = .berserker, .common = .kobold_fang, .gold = .few },
    // The same purse a rung up: the body that leaves a brick of salt is the one that sometimes leaves the whole offering.
    .{ .foe = .priest, .common = .pilgrims_salt, .odds = UNCOMMON, .rare = .pilgrims_offering, .chance = 0.10, .gold = .purse },
    // THE ANSWER TO THE SLING IS ON THE SLINGER — the one body in the warband that throws fire is where the draught that turns it comes from.
    .{ .foe = .slinger, .common = .kobold_fang, .rare = .kiln_draught, .chance = 0.16, .gold = .few },

    .{ .foe = .brood_mother, .common = .purgeleaf, .odds = UNCOMMON, .rare = .spidersilk_moccasins, .chance = 0.14 },
    .{ .foe = .broodling, .common = .bloodgrass },
    .{ .foe = .brood_sac, .common = null },

    // **THE BODIES CARRYING MADE IRON ARE WHERE THE STONE COMES FROM** (owner). A soldier keeps a stone for
    // his own edge, so the two skeletal warriors and the knight over them are the tap the DELVER's common row
    // was carrying alone — 30 stones takes an armament to `hero.TIER_MAX` and one uncommon body could not pay it.
    .{ .foe = .shieldman, .common = .pitted_helm, .odds = UNCOMMON, .rare = .smithing_stone, .chance = 0.12, .gold = .few },
    .{ .foe = .greatsword, .common = .quilted_gambeson, .odds = UNCOMMON, .rare = .smithing_stone, .chance = 0.14, .gold = .purse },

    .{ .foe = .shade, .common = .nameless_soul, .odds = UNCOMMON, .rare = .loop_of_chance, .chance = 0.14 },

    // …and the gut packed into the dirk's groove is the leechfly's own (`item.describe`).
    .{ .foe = .leechfly, .common = .bloodgrass, .rare = .envenomed_dagger, .chance = 0.12 },

    .{ .foe = .rooted, .common = .fire_tallow, .odds = UNCOMMON },

    .{ .foe = .shroom, .common = .purgeleaf, .rare = .sporeling_cap, .chance = 0.18 },

    // THE BONE KNIGHT — the one row that never rolls, and the best single stone in the game: he is the body
    // the whole armoury of the bone court answers to, and a boss is the one place a tier is worth a walk back.
    .{ .foe = .bone_knight, .common = .soul_binding_ring, .odds = BOSS_ALWAYS, .rare = .smithing_stone, .chance = 0.5, .gold = .hoard },

    // **THE ONE THAT DIGS IS THE ONE THAT FINDS IT**, and it is the only body carrying stone in its COMMON row.
    .{ .foe = .delver, .common = .smithing_stone, .odds = UNCOMMON, .gold = .few },

    // The one thing in the world that deals cold carries the coating that gives it back.
    .{ .foe = .necromancer, .common = .nameless_soul, .odds = BIG, .rare = .rimewax, .chance = 0.20, .gold = .purse },

    .{ .foe = .fungal_deer, .common = .bloodgrass },
    .{ .foe = .mushroom_mage, .common = .purgeleaf, .odds = UNCOMMON },

    .{ .foe = .fen_lurker, .common = .ironwort_tea, .odds = UNCOMMON, .gold = .few },
    .{ .foe = .spore_golem, .common = .purgeleaf, .odds = UNCOMMON },

    // **THE ONE BODY A PRIEST CAN MAKE MORE OF LEAVES NOTHING** — the supply is a cooldown (`ancientpriest.RAISE_CD`), so any odds at all here is a farm with a timer on it rather than a drop.
    .{ .foe = .bone_skitterer, .common = null },
    .{ .foe = .ancient_priest, .common = .rimeward_mantle, .odds = UNCOMMON, .gold = .purse },
    // …and the hollow leaves the bronze off its own bell, with the jar of lightning that answers it behind.
    .{ .foe = .tolling_hollow, .common = .gravebell_amulet, .odds = UNCOMMON, .rare = .thundercrock, .chance = 0.16, .gold = .few },
    // **THE THING THAT ADDLES YOU CARRIES WHAT STOPS IT** — the hood came off a body a mile from any bell.
    .{ .foe = .mourner, .common = .wax_stopped_hood, .odds = UNCOMMON, .rare = .wakers_nail, .chance = 0.12, .gold = .few },
    // **THE FAT IN THE JAR IS RENDERED OFF ONE OF THESE** (`item.describe`).
    .{ .foe = .slumber_bloom, .common = .purgeleaf, .rare = .nightcap_grease, .chance = 0.20 },
    // **IT CARRIES ITS OWN ANSWER** — the draught is the fire ward, off the one body whose whole threat is fire.
    .{ .foe = .cinder_wake, .common = .ashen_amulet, .odds = UNCOMMON, .rare = .kiln_draught, .chance = 0.18 },
    .{ .foe = .rotgorger, .common = .sporeling_cap, .odds = UNCOMMON, .rare = .sporecrown, .chance = 0.14, .gold = .few },
    // **BARK THAT LIGHTS WET IS TALLOW BY ANOTHER NAME** — the thing that burns it is what it leaves.
    .{ .foe = .birchwight, .common = .fire_tallow, .odds = UNCOMMON, .rare = .rimewax, .chance = 0.14 },
    // **THE SALT IS THE CREATURE** — it leaves the crust it was wearing.
    .{ .foe = .salt_husk, .common = .pilgrims_salt, .rare = .ironwort_tea, .chance = 0.12, .gold = .few },
    .{ .foe = .fish_spearman, .common = .bloodgrass, .rare = .fang_dirk, .chance = 0.10, .gold = .few },
    .{ .foe = .fish_netter, .common = .spidersilk_moccasins, .odds = UNCOMMON, .rare = .marchboots, .chance = 0.12, .gold = .few },
    // **THE ONE WHO PUTS HEALTH BACK IS CARRYING SOME** — the biggest purse in the band, and it earns it.
    .{ .foe = .fish_shaman, .common = .crimson_flask, .odds = UNCOMMON, .rare = .second_wind, .chance = 0.14, .gold = .purse },
    .{ .foe = .blinkbat, .common = .bloodgrass, .odds = UNCOMMON, .rare = .crimson_flask, .chance = 0.16 },
    // A BOSS PAYS ONCE AND PAYS WELL — the pair drop the two halves of what the fight teaches: the venom that
    // was on the blade, and the ward against what the caps do.
    .{ .foe = .fungal_swordsman, .common = .purgeleaf, .odds = BOSS_ALWAYS, .rare = .envenomed_dagger, .chance = 0.5, .gold = .hoard },
    .{ .foe = .fungal_magus, .common = .purgeleaf, .odds = BOSS_ALWAYS, .rare = .scroll_babble, .chance = 0.5, .gold = .hoard },
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

/// **THE HUMANOIDS WITH EMPTY POCKETS, AND WHY.** Nothing is on it: every body that walks upright and fights
/// with a made weapon carries coin, which is the whole of what the owner asked for. A humanoid added here has
/// to earn it in words, the way `LEAVES_NOTHING` does.
pub const NO_PURSE = [_]wf.FoeKind{};

pub fn noPurse(k: wf.FoeKind) bool {
    for (NO_PURSE) |n| {
        if (n == k) return true;
    }
    return false;
}

comptime {
    if (TABLE.len != NFOE) @compileError("drops: TABLE is not one row per FoeKind");
    // **A MAN HAS POCKETS** — the rule the owner gave, enforced rather than written out thirty-seven times.
    for (TABLE) |row| {
        if (foe.traitsOf(row.foe).nature == .humanoid and row.gold == .none and !noPurse(row.foe)) {
            @compileError("drops: " ++ @tagName(row.foe) ++ " is a humanoid carrying no gold — give it a `.gold`" ++
                " band, or name it in `NO_PURSE` with a reason");
        }
    }
    // …and the bands may not overlap, or a tier stops meaning anything on the body it came off: each rung's
    // floor has to clear the ceiling of the one under it.
    const rungs = [_]Coin{ .few, .purse, .heavy, .hoard };
    for (rungs[1..], 0..) |hi, i| {
        if (hi.band()[0] <= rungs[i].band()[1]) @compileError("drops: the coin bands overlap");
    }
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

/// **WHAT THE BODY'S PURSE ACTUALLY HELD**, or 0. **LUCK DOES NOT READ THIS** — `stats.inert`'s note and
/// AGENTS.md both say LUCK is the rare-item weight and nothing else, so a purse is the one roll on a corpse
/// that a build cannot lean on.
pub fn rollGold(k: wf.FoeKind, rng: *mathx.Rng) u32 {
    // **AND BOTH DRAWS ARE SPENT WHATEVER DIED** (`game`'s own note at the kill site). Returning early on a
    // `.none` body would leave the stream a function of which corpse you chose to make, which silently
    // re-seeds every drop after it.
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
        // **A BOSS ALWAYS LEAVES ITS COMMON ROW, AND MAY LEAVE ITS RARE ON TOP.** Pinned as a floor rather than
        // as an equality: the knight carries a stone at `.chance` now, so an exact 4000 was the old table's
        // shape and not the rule (`BOSS_ALWAYS`).
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
    // **THE RULE, AS A NUMBER, AND IT IS A FREQUENCY AND NOT AN AMOUNT.** The owner asked for humanoids to drop
    // gold OFTEN, so what is pinned is how many corpses pay — not coins a body, which the BOSSES own outright:
    // the two fungal magi are `.plant` and always pay, which is why plants average more per corpse than a
    // kobold warband does while paying less than half as often.
    std.debug.print("  humanoids pay on {d:.0}% of corpses against {d:.0}% for the next nature up\n", .{ humanTotal, best });
    try std.testing.expect(humanTotal > best);
    // …and every purse lands inside its own band, never between two.
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

    // **THE LADDER, PRICED IN CORPSES.** `counter.ladderCost` is the stones one armament needs end to end; the
    // mean over the bodies that carry any is what a run actually has to kill for it.
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
    // …and a body that carries stone is one that carries IRON or DIGS — never a plant or a fish.
    for (0..NFOE) |i| {
        const k: wf.FoeKind = @enumFromInt(i);
        if (TABLE[i].common != item.Kind.smithing_stone and TABLE[i].rare != item.Kind.smithing_stone) continue;
        const nat = foe.traitsOf(k).nature;
        try std.testing.expect(nat == .undead or nat == .beast);
    }
}
