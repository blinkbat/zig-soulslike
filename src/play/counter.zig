const std = @import("std");
const item = @import("item.zig");
const heromod = @import("hero.zig");
const combat = @import("combat.zig");
const mathx = @import("../core/mathx.zig");

// **THE COUNTER — ONE SCREEN, TWO TRADES** (owner: basic trading and smithing screens we can use for trader and
// smith). A shop and a smithy are the same interaction wearing different stock: a list of rows, a price in coin
// beside each, a purse at the top and one button that spends it. Written as one thing because the alternative
// was two files that would have drifted the first time either grew a column.
//
// **THE MODEL IS HEADLESS AND THE PANEL IS NOT IN IT.** Everything a shop DOES — what it stocks, what a row
// costs, whether he can afford it, what happens when he takes it — is here and testable with no window open.
// `ui/counterui.zig` draws it. `world/dialog.zig` keeps its panel in with its walk, but a shop has real
// arithmetic in it and that arithmetic is the part worth pinning.

/// Which counter he is standing at. The two differ in their ROWS and in what a row costs, and in nothing else.
pub const Trade = enum { shop, smithy };

/// **WHAT THE SMITH CHARGES TO GO ONE TIER UP.** Stones AND coin, per the owner: the stone is the gate (you
/// cannot buy your way past a tier without finding them) and the coin is the tax (you cannot bank ten tiers'
/// worth of stones and spend nothing).
///
/// Both curves are LINEAR IN THE TIER and deliberately so — a smith who charges quadratically stops being used
/// at +4, and the flat damage a tier gives (`hero.TIER_FLAT`) is linear too, so a linear price keeps the coin
/// per point of damage flat across the whole run.
pub const STONE_BASE: u32 = 1;
pub const STONE_PER: u32 = 1;
pub const COIN_BASE: u32 = 40;
pub const COIN_PER: u32 = 55;

/// Stones to take an armament from `tier` to `tier + 1`. `STONE_PER` is halved into the step so the early
/// tiers are one stone apiece and the last are five — a run's worth of the delver's drop, not a mine.
pub fn stoneCost(tier: u8) u32 {
    return STONE_BASE + (STONE_PER * tier) / 2;
}

pub fn coinCost(tier: u8) u32 {
    return COIN_BASE + COIN_PER * @as(u32, tier);
}

comptime {
    // A tier may never be free in either currency, or the screen has a button that always works.
    std.debug.assert(stoneCost(0) > 0 and coinCost(0) > 0);
}

/// What the whole ladder costs, for the test that prints it and for anything that wants to price a run.
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

/// **THE STONE IS ONE NAMED ITEM AND THE SMITHY IS ITS ONLY EATER.** Spelled once here so the screen, the cost
/// and the test cannot disagree about which material a tier is paid in.
pub const STONE: item.Kind = .smithing_stone;

/// One row on the counter. A shop row is an ITEM at a price; a smithy row is an ARMAMENT at a price in two
/// currencies. The union is flat rather than tagged because the screen already knows which trade it is in.
pub const Row = struct {
    /// Shop: what is on the shelf. Smithy: null.
    kind: ?item.Kind = null,
    /// Smithy: whose edge this row sharpens. Shop: null.
    arm: ?heromod.Armament = null,
    coin: u32 = 0,
    stones: u32 = 0,
    /// Already at `hero.TIER_MAX`, or a shelf he has nothing of to sell. The row still DRAWS — a counter that
    /// hides what it cannot do today is a counter you cannot plan against.
    done: bool = false,
};

/// One row per `item.Kind` — the sell list is the BAG, and a bag can hold every kind at once, so a smaller
/// buffer silently dropped the kinds past its cutoff. The panel scrolls; this is model capacity, not screen.
pub const MAX_ROWS: usize = item.NK;

/// **WHAT A SHOP SELLS.** Not a per-map stock list yet: the caravaneer carries what a body on the road carries,
/// which is the consumables and the arrows, and nothing that would let a player skip a boss for it. A map that
/// wants its own stock is a `Span` on the act and a table here, and neither exists until it is asked for.
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
        if (item.price(k) == 0) @compileError("counter: " ++ @tagName(k) ++ " is stocked but does not trade");
    }
}

/// **WHICH HANDS A SMITH WILL WORK ON.** The three blades and the bow — what `hero.weigh` actually reads a tier
/// for. A bell, a shield, a wand and a torch deal no weapon damage, so a tier on one would be a price with
/// nothing behind it.
pub const FORGEABLE = [_]heromod.Armament{ .sword, .dagger, .club, .bow };

/// The live counter. **IT OWNS NO STOCK AND NO PURSE** — it reads the hero and the bag every time it is asked,
/// so nothing here can go stale against the thing it is spending.
pub const Counter = struct {
    trade: Trade = .shop,
    open: bool = false,
    sel: usize = 0,
    /// **SELLING IS THE SAME SCREEN WITH THE LIST TURNED ROUND**, not a second modal: one key flips it, which is
    /// how every shop in the genre does it and how a player expects to find it.
    selling: bool = false,
    /// What the last press did, for the panel to say out loud. It stands until the next press or move clears it.
    said: Said = .none,

    pub const Said = enum { none, bought, sold, forged, no_coin, no_stones, maxed, nothing };

    /// Which `Said`s are the counter saying NO — one list, because the panel's ink and the game's refusal
    /// knock must never disagree about what a refusal is.
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

    /// **THE ROWS, BUILT FRESH.** A shop's sell list is the BAG, which changes under the screen every time he
    /// takes something, so a held list would show him things he no longer has.
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
                        // The worn copy is not on the shelf: sold, the socket would keep stats the bag
                        // no longer owns. Spares sell fine.
                        if (held == 1 and h.worn.wears(k)) continue;
                        out[n] = .{ .kind = k, .coin = item.sellPrice(k) };
                        n += 1;
                    }
                } else {
                    for (STOCK) |k| {
                        if (n >= MAX_ROWS) break;
                        // **BROKE IS NOT `done`.** `done` means the row can never do anything again, and
                        // `counterui` draws such a row with NO PRICE AT ALL — so set off the purse, every item
                        // he could not yet afford stopped telling him what to save up for. `take` reads the
                        // purse itself, so the transaction is unchanged.
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

    /// **ONE DOOR, AND IT IS THE ONLY THING THAT SPENDS.** Every refusal is a `Said` rather than a silent
    /// no-op: a counter that does nothing and says nothing is one the player thinks is broken.
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
                // `Bag.add` SATURATES at `item.CAP`, so a full shelf takes the coin and hands back nothing —
                // the smithy's all-or-nothing rule owed the other way round.
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
                // **THE STONES GO FIRST AND BOTH GO BEFORE THE TIER.** Ordered so a refusal in the middle
                // cannot leave him charged for work that never happened.
                // `Bag.take` hands back how many it ACTUALLY took, so all-or-nothing is a comparison and not
                // a boolean — a partial take would charge him stones for no tier.
                const took = bag.take(STONE, @intCast(r.stones));
                if (took < r.stones) {
                    bag.add(STONE, took);
                    self.said = .no_stones;
                    return;
                }
                if (!spend(&h.gold, r.coin)) {
                    // Put the stones back rather than eat them: this branch is unreachable given the check
                    // above, and an unreachable branch that silently robs the player is not one to leave open.
                    bag.add(STONE, @intCast(r.stones));
                    self.said = .no_coin;
                    return;
                }
                _ = h.raiseTier(a);
                self.said = .forged;
            },
        }
    }

    /// **THE PURSE IS A COUNTER AND COUNTERS ONLY GO UP** (`combat.Souls.gain`), so spending is here rather than
    /// on the type: souls are never spent this way and giving them a `spend` would invite it.
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

    // Broke: the press is refused and it SAYS so.
    c.sel = 0;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.no_coin, c.said);
    try std.testing.expectEqual(@as(u32, 0), bag.count(list[0].kind.?));

    // Funded: the coin goes, the thing arrives.
    h.gold.total = 1000;
    const before = h.gold.total;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.bought, c.said);
    try std.testing.expectEqual(@as(u32, 1), bag.count(list[0].kind.?));
    try std.testing.expectEqual(before - list[0].coin, h.gold.total);

    // …and selling it back pays less than it cost, or the shelf is a free warehouse.
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

    // No stones: refused, and the purse is untouched.
    h.gold.total = 100_000;
    const full = h.gold.total;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.no_stones, c.said);
    try std.testing.expectEqual(full, h.gold.total);
    try std.testing.expectEqual(@as(u8, 0), h.tierOf(.sword));

    // Stones and coin: one tier, and exactly one.
    bag.add(STONE, 99);
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.forged, c.said);
    try std.testing.expectEqual(@as(u8, 1), h.tierOf(.sword));
    try std.testing.expectEqual(full - coinCost(0), h.gold.total);
    try std.testing.expectEqual(@as(u32, 99 - stoneCost(0)), bag.count(STONE));
    // …and it sharpened the SWORD and nothing else.
    try std.testing.expectEqual(@as(u8, 0), h.tierOf(.bow));

    // All the way up, then refused at the cap.
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
    // (`drops`' own test), so this is the number of corpses a full upgrade is worth.
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
    // **THE OWNER'S REASON, AS ARITHMETIC.** A flat bonus on the base is multiplied by everything downstream,
    // so the SAME percentage modifier is worth more coin-for-coin at +10 than at +0. Tacked on after the
    // multipliers it would have been worth exactly the same at both, which is the thing to prove it is not.
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
    // …and the press is still refused, because the door reads the PURSE and not the row.
    c.sel = 0;
    c.take(&h, &bag);
    try std.testing.expectEqual(Counter.Said.no_coin, c.said);

    // Only the SMITHY has a row that is genuinely finished, and only at the cap.
    c.begin(.smithy);
    for (&h.tiers) |*t| t.* = heromod.TIER_MAX;
    const maxed = c.rows(&h, &bag, &buf);
    for (maxed) |r| try std.testing.expect(r.done);
}
