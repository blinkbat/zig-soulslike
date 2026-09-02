const std = @import("std");
const item = @import("item.zig");
const heromod = @import("hero.zig");
const combat = @import("combat.zig");
const mathx = @import("../core/mathx.zig");


pub const Trade = enum { shop, smithy };

pub const STONE_BASE_BANK: u32 = 1;
pub const STONE_PER_BANK: u32 = 1;
pub const COIN_BASE_BANK: u32 = 40;
pub const COIN_PER_BANK: u32 = 55;

pub var STONE_BASE: u32 = STONE_BASE_BANK;
pub var STONE_PER: u32 = STONE_PER_BANK;
pub var COIN_BASE: u32 = COIN_BASE_BANK;
pub var COIN_PER: u32 = COIN_PER_BANK;

/// Stones to take an armament from `tier` to `tier + 1`. `STONE_PER` is halved into the step so the early
pub fn stoneCost(tier: u8) u32 {
    return STONE_BASE + (STONE_PER * tier) / 2;
}

pub fn coinCost(tier: u8) u32 {
    return COIN_BASE + COIN_PER * @as(u32, tier);
}

comptime {
    std.debug.assert(STONE_BASE_BANK > 0 and COIN_BASE_BANK > 0);
}

pub fn ladderCost(from: u8, to: u8) struct { stones: u32, coin: u32 } {
    var st: u32 = 0;
    var co: u32 = 0;
    var t = from;
    while (t < @min(to, heromod.TIER_MAX)) : (t += 1) {
        st += stoneCost(t);
        co += coinCost(t);
    }
    return .{ .stones = st, .coin = co };
}

pub const STONE: item.Kind = .smithing_stone;

pub const Row = struct {
    kind: ?item.Kind = null,
    arm: ?heromod.Armament = null,
    coin: u32 = 0,
    stones: u32 = 0,
    done: bool = false,
};

pub const MAX_ROWS: usize = item.NK;

pub const STOCK = [_]item.Kind{
    .mushroom_jerky,
    .toadflesh_broth,
    .plain_arrows,
    .fire_arrows,
    .purgeleaf,
    .pilgrims_salt,
    .ironwort_tea,
    .fire_tallow,
    .thundercrock,
    .ember_candle,
    .smithing_stone,
};

comptime {
    if (STOCK.len > MAX_ROWS) @compileError("counter: the shop stocks more than the screen can list");
    for (STOCK) |k| {
        if (item.priceBank(k) == 0) @compileError("counter: " ++ @tagName(k) ++ " is stocked but does not trade");
    }
}

pub const FORGEABLE = [_]heromod.Armament{ .sword, .dagger, .club, .bow };

pub const Counter = struct {
    trade: Trade = .shop,
    open: bool = false,
    sel: usize = 0,
    selling: bool = false,
    said: Said = .none,

    pub const Said = enum { none, bought, sold, forged, no_coin, no_stones, maxed, nothing };

    pub fn refused(s: Said) bool {
        return switch (s) {
            .no_coin, .no_stones, .maxed, .nothing => true,
            .none, .bought, .sold, .forged => false,
        };
    }

    pub fn begin(self: *Counter, t: Trade) void {
        self.trade = t;
        self.open = true;
        self.sel = 0;
        self.selling = false;
        self.said = .none;
    }

    pub fn close(self: *Counter) void {
        self.open = false;
        self.said = .none;
    }

    pub fn rows(self: *const Counter, h: *const heromod.Hero, bag: *const item.Bag, out: *[MAX_ROWS]Row) []const Row {
        var n: usize = 0;
        switch (self.trade) {
            .shop => {
                if (self.selling) {
                    for (0..item.NK) |ki| {
                        if (n >= MAX_ROWS) break;
                        const k: item.Kind = @enumFromInt(ki);
                        const held = bag.count(k);
                        if (held == 0 or item.sellPrice(k) == 0) continue;
                        if (held == 1 and h.worn.wears(k)) continue;
                        out[n] = .{ .kind = k, .coin = item.sellPrice(k) };
                        n += 1;
                    }
                } else {
                    for (STOCK) |k| {
                        if (n >= MAX_ROWS) break;
                        out[n] = .{ .kind = k, .coin = item.price(k) };
                        n += 1;
                    }
                }
            },
            .smithy => {
                for (FORGEABLE) |a| {
                    if (n >= MAX_ROWS) break;
                    const t = h.tierOf(a);
                    const maxed = t >= heromod.TIER_MAX;
                    out[n] = .{
                        .arm = a,
                        .coin = if (maxed) 0 else coinCost(t),
                        .stones = if (maxed) 0 else stoneCost(t),
                        .done = maxed,
                    };
                    n += 1;
                }
            },
        }
        return out[0..n];
    }

    pub fn take(self: *Counter, h: *heromod.Hero, bag: *item.Bag) void {
        var buf: [MAX_ROWS]Row = undefined;
        const list = self.rows(h, bag, &buf);
        if (list.len == 0) {
            self.said = .nothing;
            return;
        }
        const r = list[@min(self.sel, list.len - 1)];
        switch (self.trade) {
            .shop => {
                const k = r.kind orelse return;
                if (self.selling) {
                    if (bag.take(k, 1) == 0) {
                        self.said = .nothing;
                        return;
                    }
                    h.gold.gain(r.coin);
                    self.said = .sold;
                    return;
                }
                if (h.gold.total < r.coin) {
                    self.said = .no_coin;
                    return;
                }
                if (bag.count(k) >= item.CAP) {
                    self.said = .maxed;
                    return;
                }
                if (!spend(&h.gold, r.coin)) {
                    self.said = .no_coin;
                    return;
                }
                bag.add(k, 1);
                self.said = .bought;
            },
            .smithy => {
                const a = r.arm orelse return;
                if (h.tierOf(a) >= heromod.TIER_MAX) {
                    self.said = .maxed;
                    return;
                }
                if (bag.count(STONE) < r.stones) {
                    self.said = .no_stones;
                    return;
                }
                if (h.gold.total < r.coin) {
                    self.said = .no_coin;
                    return;
                }
                const took = bag.take(STONE, @intCast(r.stones));
                if (took < r.stones) {
                    bag.add(STONE, took);
                    self.said = .no_stones;
                    return;
                }
                if (!spend(&h.gold, r.coin)) {
                    bag.add(STONE, @intCast(r.stones));
                    self.said = .no_coin;
                    return;
                }
                _ = h.raiseTier(a);
                self.said = .forged;
            },
        }
    }

    fn spend(purse: *combat.Gold, n: u32) bool {
        if (purse.total < n) return false;
        purse.total -= n;
        purse.shown = @min(purse.shown, @as(f32, @floatFromInt(purse.total)));
        return true;
    }

    pub fn move(self: *Counter, delta: i32, len: usize) void {
        if (len == 0) return;
        const cur: i32 = @intCast(@min(self.sel, len - 1));
        const n: i32 = @intCast(len);
        self.sel = @intCast(@mod(cur + delta + n, n));
        self.said = .none;
    }
};

test "A SHOP TAKES COIN AND GIVES A THING, AND WILL NOT DO IT ON AN EMPTY PURSE" {
    var h = std.mem.zeroInit(heromod.Hero, .{});
    var bag = item.Bag{};
    var c = Counter{};
    c.begin(.shop);
    var buf: [MAX_ROWS]Row = undefined;
    const list = c.rows(&h, &bag, &buf);
    try std.testing.expect(list.len == STOCK.len);

    c.sel = 0;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.no_coin, c.said);
    try std.testing.expectEqual(@as(u32, 0), bag.count(list[0].kind.?));

    h.gold.total = 1000;
    const before = h.gold.total;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.bought, c.said);
    try std.testing.expectEqual(@as(u32, 1), bag.count(list[0].kind.?));
    try std.testing.expectEqual(before - list[0].coin, h.gold.total);

    c.selling = true;
    c.sel = 0;
    var sbuf: [MAX_ROWS]Row = undefined;
    const sell = c.rows(&h, &bag, &sbuf);
    try std.testing.expect(sell.len > 0);
    const paid = h.gold.total;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.sold, c.said);
    try std.testing.expect(h.gold.total - paid < item.price(sell[0].kind.?));
}

test "THE SMITH EATS STONES AND COIN, ONE TIER AT A TIME, AND STOPS AT THE CAP" {
    var h = std.mem.zeroInit(heromod.Hero, .{});
    var bag = item.Bag{};
    var c = Counter{};
    c.begin(.smithy);
    c.sel = 0; // the sword

    h.gold.total = 100_000;
    const full = h.gold.total;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.no_stones, c.said);
    try std.testing.expectEqual(full, h.gold.total);
    try std.testing.expectEqual(@as(u8, 0), h.tierOf(.sword));

    bag.add(STONE, 99);
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.forged, c.said);
    try std.testing.expectEqual(@as(u8, 1), h.tierOf(.sword));
    try std.testing.expectEqual(full - coinCost(0), h.gold.total);
    try std.testing.expectEqual(@as(u32, 99 - stoneCost(0)), bag.count(STONE));
    try std.testing.expectEqual(@as(u8, 0), h.tierOf(.bow));

    bag.add(STONE, 9999);
    for (0..heromod.TIER_MAX) |_| c.take(&h, &bag);
    try std.testing.expectEqual(heromod.TIER_MAX, h.tierOf(.sword));
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.maxed, c.said);

    const run = ladderCost(0, heromod.TIER_MAX);
    std.debug.print("\n  +{d} costs {d} stones and {d} coin all told; the last tier alone is {d} stones / {d} coin\n", .{
        heromod.TIER_MAX, run.stones, run.coin, stoneCost(heromod.TIER_MAX - 1), coinCost(heromod.TIER_MAX - 1),
    });
    // **THE LADDER HAS TO BE PAYABLE OFF WHAT THE WORLD DROPS.** Humanoids pay ~13 coins a body
    std.debug.print("  ...which is about {d:.0} humanoid corpses at 12.9 coins a body\n", .{
        @as(f64, @floatFromInt(run.coin)) / 12.9,
    });
}

test "THE WORN COPY IS NOT ON THE SHELF — a spare sells, the last one stays his" {
    var h = std.mem.zeroInit(heromod.Hero, .{});
    var bag = item.Bag{};
    var c = Counter{};
    c.begin(.shop);
    c.selling = true;
    var buf: [MAX_ROWS]Row = undefined;

    h.worn.put(.chest, .quilted_gambeson);
    bag.add(.quilted_gambeson, 2);
    var found: u32 = 0;
    for (c.rows(&h, &bag, &buf)) |r| {
        if (r.kind == .quilted_gambeson) found += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), found);

    _ = bag.take(.quilted_gambeson, 1);
    found = 0;
    for (c.rows(&h, &bag, &buf)) |r| {
        if (r.kind == .quilted_gambeson) found += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), found);
}

test "A TIER IS FLAT ON THE BASE, SO THE PERCENTAGES GET BETTER AS IT CLIMBS" {
    const row = item.Arm{ .slot = .hand_sword };
    const sheet = std.mem.zeroInit(@import("stats.zig").Sheet, .{});
    const bare = heromod.weigh(heromod.ATK_LIGHT_HIT, row, sheet, 0);
    const keen = heromod.weigh(heromod.ATK_LIGHT_HIT, row, sheet, heromod.TIER_MAX);
    const PCT: f32 = 1.20;
    const bareGain = bare.dmg * PCT - bare.dmg;
    const keenGain = keen.dmg * PCT - keen.dmg;
    std.debug.print("  a +20% perk is worth {d:.2} damage on a bare sword and {d:.2} at +{d} — {d:.2}x\n", .{
        bareGain, keenGain, heromod.TIER_MAX, keenGain / bareGain,
    });
    try std.testing.expect(keen.dmg > bare.dmg);
    try std.testing.expect(keenGain > bareGain * 1.5);
}

test "AN EMPTY PURSE HIDES NO PRICES — a shelf you cannot afford is a shelf you are saving up for" {
    var h = std.mem.zeroInit(heromod.Hero, .{});
    var bag = item.Bag{};
    var c = Counter{};
    c.begin(.shop);
    var buf: [MAX_ROWS]Row = undefined;

    const poor = c.rows(&h, &bag, &buf);
    for (poor) |r| {
        try std.testing.expect(!r.done);
        try std.testing.expect(r.coin > 0);
    }
    c.sel = 0;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.no_coin, c.said);

    c.begin(.smithy);
    for (&h.tiers) |*t| t.* = heromod.TIER_MAX;
    const maxed = c.rows(&h, &bag, &buf);
    for (maxed) |r| try std.testing.expect(r.done);
}
