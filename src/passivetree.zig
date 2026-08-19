const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const stats = @import("stats.zig");
const combat = @import("combat.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");

// THE PASSIVE TREE — PoE2's, radially. You stand in the MIDDLE and three arms run out of it: WARRIOR,
// ROGUE, WIZARD. Any arm is open from the first point, so nothing here is a class; what gates you is
// DEPTH: you CLIMB to the capstone you want, one node at a time, and a node opens as soon as something it
// hangs off is yours (`feeders`). No counts and no tolls — only a path.

const rgba = mathx.rgba;

/// THE THREE ARMS, AND THEY ARE NEVER NAMED ON SCREEN (owner's call) — no "WARRIOR" caption, no blurb, no
/// arm in a lock message. What an arm is, is what its nodes DO, and the colour and the direction carry which
/// one you are on. A label naming it as well is the picture and a word for the picture.
pub const Arm = enum {
    warrior,
    rogue,
    wizard,

    /// PoE's own three, muted onto warm stone — a saturated red on this plate reads as an error light. This
    /// is the ONLY thing that tells the three apart on the page, which is why the hues are so far apart.
    pub fn ink(a: Arm) rl.Color {
        return switch (a) {
            .warrior => rgba(196, 104, 84, 255),
            .rogue => rgba(132, 184, 112, 255),
            .wizard => rgba(120, 154, 214, 255),
        };
    }

    /// **THE ONE CLASS NODE THE WHOLE ARM RADIATES OUT OF** (owner: you start each branch from one classlike
    /// node — strength, dexterity, int — and radiate out from there). It is the arm said in one attribute,
    /// and it is what both of that arm's branches hang off, so committing to an arm is ONE purchase and
    /// choosing between its two ideas is the next one.
    pub fn stat(a: Arm) stats.Attr {
        return switch (a) {
            .warrior => .strength,
            .rogue => .dexterity,
            .wizard => .intelligence,
        };
    }
};

pub const NARM = @typeInfo(Arm).@"enum".fields.len;

/// **TWO BRANCHES PER ARM, AND THE BRANCH IS THE THING YOU ACTUALLY CLIMB** (owner: 2 "branches" per
/// "class" now, with bespoke ideas and stat boosts alike). An arm used to be one fan of seven whose two
/// strands met at a single tip, so "warrior" was one destination wearing two routes. Each arm now opens on
/// its own class node and RADIATES from it into two SEPARATE climbs, each ending in its OWN keystone —
/// which is what lets one arm hold two ideas that do not belong together.
///
/// **IN ARM ORDER, TWO AT A TIME** — a comptime walk below pins that, so `Branch.arm` is arithmetic and
/// never a table somebody has to keep in step.
pub const Branch = enum {
    /// WARRIOR — what keeps him standing: armour, the slow refill, and blood taken back off the blade.
    warrior_life,
    /// …and what spends him: the bargain, the cull, and what a body is worth the moment it drops.
    warrior_berserk,
    /// ROGUE — the roll, the bar behind it, and ground covered.
    rogue_evade,
    /// …and everything that leaves his hand rather than staying in it.
    rogue_ranged,
    /// WIZARD — the pool itself: how deep, how fast it comes back, and what it wards.
    wizard_well,
    /// …and what he does with it: how fast, how hard, and what the bolt leaves standing.
    wizard_cast,

    pub fn arm(b: Branch) Arm {
        return @enumFromInt(@intFromEnum(b) / 2);
    }
    /// Which of its arm's two it is — 0 takes the anticlockwise lane, 1 the clockwise (`angleOf`).
    pub fn lane(b: Branch) usize {
        return @intFromEnum(b) % 2;
    }
};

pub const NBRANCH = @typeInfo(Branch).@"enum".fields.len;

/// How many nodes each ring of a BRANCH fans into, counting outward from the arm's class node. It opens on
/// ONE — the branch has a mouth, and it is what the root radiates INTO — widens to a real choice through the
/// middle, and closes on the keystone both strands climb to. A tip only one strand could reach would make
/// the other a dead end nobody would ever walk.
const BRANCH_RINGS = [_]u8{ 1, 2, 2, 1 };

pub const PER_BRANCH: usize = blk: {
    var n: usize = 0;
    for (BRANCH_RINGS) |s| n += s;
    break :blk n;
};
/// The class node, then both of its branches.
pub const PER_ARM: usize = 1 + PER_BRANCH * 2;
pub const N: usize = NARM * PER_ARM;
/// Rings out from the hub, the class node being the first — what the wheel is framed on.
pub const RINGS: u8 = @intCast(1 + BRANCH_RINGS.len);

pub fn armFirst(a: Arm) usize {
    return @intFromEnum(a) * PER_ARM;
}
/// A branch's first node — past its arm's class node, and past the other branch if it is the second.
pub fn branchFirst(b: Branch) usize {
    return armFirst(b.arm()) + 1 + b.lane() * PER_BRANCH;
}

/// WHAT A NODE HANGS OFF — the node or nodes its own link runs back to, one ring in. THE ARM'S CLASS NODE
/// hangs off the hub, which you are always standing on, so all three arms are open from the first souls you
/// spend; a branch's first node hangs off that class node, which is what "radiate out from there" means in
/// links. THE KEYSTONE IS THE ONE NODE WITH TWO: both strands of a branch climb to it.
pub fn feeders(i: usize, out: *[2]usize) []const usize {
    const n = NODES[i];
    if (n.ring == 0) return out[0..0]; // the class node, and the hub is always yours
    const br = n.ring - 1; // its index into the BRANCH's own rings
    const b = n.branch.?;
    if (br == 0) { // the mouth of the branch: it radiates out of its arm's class node
        out[0] = armFirst(b.arm());
        return out[0..1];
    }
    const base = branchFirst(b);
    var at: usize = 0;
    for (0..br - 1) |r| at += BRANCH_RINGS[r];
    const prev = BRANCH_RINGS[br - 1];
    if (BRANCH_RINGS[br] == 1) {
        out[0] = base + at;
        if (prev > 1) {
            out[1] = base + at + 1;
            return out[0..2];
        }
        return out[0..1];
    }
    out[0] = base + at + @min(n.slot, prev - 1);
    return out[0..1];
}

/// WHAT ONE NODE HANDS OVER. One grant per node: a node that did two things could never be named on the row
/// that names it, and this whole page is read at a glance. A BARGAIN is still ONE grant — `sacrifice` is a
/// single decision with a price attached, not two grants stapled together.
pub const Grant = union(enum) {
    attr: struct { a: stats.Attr, n: u8 },
    res: combat.Resists,
    /// Added to `combat.GUARD_NEGATE`.
    guard: f32,
    /// Seconds added to the roll's invulnerable window.
    iframe: f32,
    /// Multiplier on poison buildup TAKEN.
    poison: f32,
    /// Multipliers on what the roll costs, what a cast costs, and what a cast deals.
    rollStam: f32,
    spellCost: f32,
    spellDmg: f32,

    // ── WARRIOR, THE LIFE BRANCH ────────────────────────────────────────────────────────────────────────
    /// Added to the suit's own `A` (`combat.armourTaken`), so a node and a coat are one number and one curve.
    armour: f32,
    /// HP a second, always — the first thing in the game that gives health back without an item.
    hpRegen: f32,
    /// HP back on every blow of his that lands — the leech signet's own dial, added to it.
    leech: f32,

    // ── WARRIOR, THE BERSERKER BRANCH ───────────────────────────────────────────────────────────────────
    /// **THE BARGAIN**, and it is ONE grant because it is one decision: a share of his max HP given up for a
    /// share more damage on everything he owns.
    sacrifice: struct { hpFrac: f32, dmg: f32 },
    /// A body struck under this share of its own HP dies outright.
    cull: f32,
    /// …and what a body is WORTH the moment it drops: HP straight back.
    onKill: f32,

    // ── ROGUE ───────────────────────────────────────────────────────────────────────────────────────────
    /// Multiplier on ground speed. Small numbers: this one is spent every frame of the game.
    moveSpeed: f32,
    /// Multiplier on the stamina refill.
    stamRegen: f32,
    /// Multipliers on what leaves the string and what leaves the hand.
    bowDmg: f32,
    thrownDmg: f32,

    // ── WIZARD ──────────────────────────────────────────────────────────────────────────────────────────
    /// FP a second, always — the blue bar's own answer to `hpRegen`.
    fpRegen: f32,
    /// Multiplier on the pool itself.
    fpMax: f32,
    /// Multiplier on how fast a cast comes out.
    castSpeed: f32,
    /// **THE ONE SPELL-SPECIFIC GRANT** (owner's own example): the chaos bolt leaves a cloud where it lands.
    /// A FLAG rather than a number, because what it buys is a MECHANIC and not a dial — which is what a
    /// keystone is for.
    boltCloud,
};

pub const Node = struct {
    arm: Arm,
    /// **NULL FOR THE ARM'S OWN CLASS NODE** — the one thing on an arm that belongs to both its branches.
    branch: ?Branch = null,
    /// 0 is the class node; 1 and up are the branch's own rings, counting outward.
    ring: u8,
    slot: u8 = 0,
    name: [:0]const u8,
    grant: Grant,
    /// The tip of a branch. Drawn bigger, and the only node worth walking a whole branch for.
    key: bool = false,
};

fn attr(a: stats.Attr, n: u8) Grant {
    return .{ .attr = .{ .a = a, .n = n } };
}

/// **THE ARM'S OWN NODE**, written once rather than three times — it is the arm said in one attribute.
fn classNode(a: Arm, name: [:0]const u8) Node {
    return .{ .arm = a, .ring = 0, .name = name, .grant = attr(a.stat(), 3) };
}

/// IN ARM ORDER — the class node, then its first branch, then its second, each in ring/slot order. A
/// comptime walk below pins every one of those, so a node in the wrong place is a compile error rather than
/// a wheel with a hole in it.
pub const NODES = [N]Node{
    // ══ WARRIOR ════════════════════════════════════════════════════════════════════════════════════════
    classNode(.warrior, "Iron Thews"),

    // ── LIFE — the refill, the blood off the blade, and what a blow does not get through ────────────────
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 1, .name = "Warrior's Blood", .grant = attr(.vitality, 2) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 2, .slot = 0, .name = "Thick Hide", .grant = .{ .armour = 10.0 } },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 2, .slot = 1, .name = "Slow Mending", .grant = .{ .hpRegen = 0.6 } },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 3, .slot = 0, .name = "Stalwart", .grant = .{ .guard = 0.05 } },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 3, .slot = 1, .name = "Bloodfeast", .grant = .{ .leech = 0.6 } },
    // **THE KEYSTONE, AND THE WHOLE BRANCH IS WORTH THE RING — NOT TWICE IT** (owner: HP on hit nodes are super
    // OP). It WAS 4.0 on top of Bloodfeast's 1.5, and the number that indicts that is the FLASK: the red bar is
    // 70 at the start (`stats.HP_BASE`) and two crimson charges of `FLASK_HP_FRAC` are the entire 63 HP a man
    // has between bonfires. At 5.5 a hit that was a flask charge every SIX blows, without limit and without a
    // sip — which does not make the flask weak, it retires it. The branch now sums to the leech signet's own
    // 2.0, and the RING is the bigger dial for one hit because it charges a permanent 6% of the bar to be it:
    // points buy the trickle, health buys the size. A flask charge is ~16 blows on the branch alone.
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 4, .name = "Sanguine Pact", .grant = .{ .leech = 1.4 }, .key = true },

    // ── BERSERKER — what he spends, what he finishes, and what a body is worth ──────────────────────────
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 1, .name = "Reaver", .grant = .{ .onKill = 2.0 } },
    // THE BARGAIN, small enough to take early: a twelfth of the bar for a tenth more on every blow.
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 2, .slot = 0, .name = "Blood Price", .grant = .{ .sacrifice = .{ .hpFrac = 0.08, .dmg = 1.10 } } },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 2, .slot = 1, .name = "Culling Blow", .grant = .{ .cull = 0.10 } },
    // **A BODY IS WORTH A FIFTH OF A FLASK CHARGE, NOT TWO THIRDS OF ONE** (owner: HP on death nodes are too
    // strong too). Reaver's 6 and this row's 14 summed to 20 a kill against a 70 HP bar — so a six-body fight
    // handed back 120 HP, which is nearly TWICE the 63 a man carries between bonfires, off one fight. At 2 and
    // 4 the pair is 6 a body: a fight is worth about one charge, which is a branch paying out and not a branch
    // replacing the flask. It only ever pays when something actually dies, which is the honest half of it.
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 3, .slot = 0, .name = "Red Harvest", .grant = .{ .onKill = 4.0 } },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 3, .slot = 1, .name = "Reckless", .grant = .{ .sacrifice = .{ .hpFrac = 0.06, .dmg = 1.08 } } },
    // THE KEYSTONE: a fifth of his health, permanently, for a third more on everything he owns.
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 4, .name = "Berserk", .grant = .{ .sacrifice = .{ .hpFrac = 0.20, .dmg = 1.34 } }, .key = true },

    // ══ ROGUE ══════════════════════════════════════════════════════════════════════════════════════════
    classNode(.rogue, "Quick Hands"),

    // ── EVASION — the roll, the bar behind it, and ground covered ───────────────────────────────────────
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 1, .name = "Fleet", .grant = .{ .iframe = 0.05 } },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 2, .slot = 0, .name = "Second Wind", .grant = attr(.endurance, 2) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 2, .slot = 1, .name = "Light Step", .grant = .{ .moveSpeed = 1.06 } },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 3, .slot = 0, .name = "Wind at Heel", .grant = .{ .stamRegen = 1.25 } },
    // POISON IS THE ONE STATUS AND IT IS HIS ALONE, so the branch about not being hurt is where it answers.
    // (It was a second  node here, a hair off the one beside it — which is a duplicate wearing a
    // different name, not a choice.)
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 3, .slot = 1, .name = "Warded Blood", .grant = .{ .poison = 0.70 } },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 4, .name = "Misty Step", .grant = .{ .rollStam = 0.65 }, .key = true },

    // ── RANGED — everything that leaves his hand rather than staying in it ──────────────────────────────
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 1, .name = "Keen Eye", .grant = .{ .bowDmg = 1.16 } },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 2, .slot = 0, .name = "Practised Arm", .grant = .{ .thrownDmg = 1.20 } },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 2, .slot = 1, .name = "Wayfinder", .grant = attr(.luck, 2) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 3, .slot = 0, .name = "Broadhead", .grant = .{ .bowDmg = 1.18 } },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 3, .slot = 1, .name = "Steady Hand", .grant = attr(.dexterity, 2) },
    // THE KEYSTONE: the jars, which are the one thing he throws that he cannot make more of.
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 4, .name = "Hail", .grant = .{ .thrownDmg = 1.55 }, .key = true },

    // ══ WIZARD ═════════════════════════════════════════════════════════════════════════════════════════
    classNode(.wizard, "Lore"),

    // ── THE WELL — how deep the pool is, how fast it fills, and what it wards ───────────────────────────
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 1, .name = "Open Mind", .grant = attr(.mind, 2) },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 2, .slot = 0, .name = "Deep Well", .grant = .{ .fpMax = 1.15 } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 2, .slot = 1, .name = "Slow Tide", .grant = .{ .fpRegen = 0.9 } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 3, .slot = 0, .name = "Veil", .grant = .{ .res = combat.resists(.{ .chaos = 20, .lightning = 10 }) } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 3, .slot = 1, .name = "Warded", .grant = .{ .res = combat.resists(.{ .fire = 15, .cold = 15 }) } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 4, .name = "Wellspring", .grant = .{ .fpRegen = 2.4 }, .key = true },

    // ── CASTING — how fast, how hard, and what the bolt leaves standing ─────────────────────────────────
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 1, .name = "Attuned", .grant = .{ .spellCost = 0.80 } },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 2, .slot = 0, .name = "Quick Tongue", .grant = .{ .castSpeed = 1.18 } },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 2, .slot = 1, .name = "Arcana", .grant = .{ .spellDmg = 1.25 } },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 3, .slot = 0, .name = "Deeper Lore", .grant = attr(.intelligence, 2) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 3, .slot = 1, .name = "Inner Quiet", .grant = .{ .spellCost = 0.88 } },
    // THE KEYSTONE, and the only grant in the tree that is a MECHANIC rather than a dial (owner's own
    // example): the bolt stops being a projectile that lands and becomes ground you have denied.
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 4, .name = "Chaos Bloom", .grant = .boltCloud, .key = true },
};

comptime {
    // THE TABLE IS THE ORDER, and every index the geometry and the links use is arithmetic off it.
    var i: usize = 0;
    for (0..NARM) |a| {
        const arm: Arm = @as(Arm, @enumFromInt(a));
        // THE CLASS NODE FIRST, and it belongs to no branch: it is what both of them radiate out of.
        std.debug.assert(i == armFirst(arm));
        std.debug.assert(NODES[i].arm == arm and NODES[i].branch == null and NODES[i].ring == 0);
        std.debug.assert(!NODES[i].key);
        switch (NODES[i].grant) {
            .attr => |x| std.debug.assert(x.a == arm.stat()),
            else => @compileError("passivetree: an arm's class node must be its own attribute"),
        }
        i += 1;
        for (0..2) |lane| {
            const b: Branch = @as(Branch, @enumFromInt(a * 2 + lane));
            std.debug.assert(b.arm() == arm and b.lane() == lane);
            std.debug.assert(i == branchFirst(b));
            for (BRANCH_RINGS, 0..) |slots, br| {
                for (0..slots) |slot| {
                    const n = NODES[i];
                    std.debug.assert(n.arm == arm);
                    std.debug.assert(n.branch.? == b);
                    std.debug.assert(n.ring == br + 1);
                    std.debug.assert(n.slot == slot);
                    std.debug.assert(n.key == (br == BRANCH_RINGS.len - 1));
                    i += 1;
                }
            }
        }
    }
    std.debug.assert(i == N);
    // EVERY BRANCH ENDS IN EXACTLY ONE KEYSTONE, which is the whole of what two branches per class buys.
    var keys: usize = 0;
    for (NODES) |n| {
        if (n.key) keys += 1;
    }
    std.debug.assert(keys == NBRANCH);
}

/// WHAT A NODE IS WORTH, said the way the panel wants to read it.
pub fn grantSays(g: Grant) [:0]const u8 {
    return switch (g) {
        .attr => |x| fmt("+{d} {s}", .{ x.n, stats.displayName(x.a) }),
        .res => |r| blk: {
            var buf: [96]u8 = undefined;
            var at: usize = 0;
            for (0..combat.NELEM) |i| {
                const e: combat.Elem = @enumFromInt(i);
                if (r.raw(e) == 0) continue;
                const part = std.fmt.bufPrint(buf[at..], "{s}+{d:.0}% ", .{ combat.elemName(e), r.raw(e) }) catch break;
                at += part.len;
            }
            break :blk fmt("{s}resistance", .{buf[0..at]});
        },
        .guard => |x| fmt("Guard turns aside {d:.0}% more of a blow", .{x * 100.0}),
        .iframe => |x| fmt("The roll is invulnerable {d:.2}s longer", .{x}),
        .poison => |x| fmt("Poison builds on you {d:.0}% slower", .{(1.0 - x) * 100.0}),
        .rollStam => |x| fmt("The roll costs {d:.0}% less stamina", .{(1.0 - x) * 100.0}),
        .spellCost => |x| fmt("A cast costs {d:.0}% less FP", .{(1.0 - x) * 100.0}),
        .spellDmg => |x| fmt("Sorcery deals {d:.0}% more", .{(x - 1.0) * 100.0}),
        .armour => |x| fmt("+{d:.0} armour", .{x}),
        .hpRegen => |x| fmt("Recover {d:.1} HP a second", .{x}),
        .leech => |x| fmt("+{d:.1} HP back on every blow that lands", .{x}),
        .sacrifice => |x| fmt("{d:.0}% less max HP; every blow deals {d:.0}% more", .{ x.hpFrac * 100.0, (x.dmg - 1.0) * 100.0 }),
        .cull => |x| fmt("A body struck under {d:.0}% HP dies outright", .{x * 100.0}),
        .onKill => |x| fmt("+{d:.0} HP whenever something dies to you", .{x}),
        .moveSpeed => |x| fmt("Move {d:.0}% faster", .{(x - 1.0) * 100.0}),
        .stamRegen => |x| fmt("Stamina returns {d:.0}% faster", .{(x - 1.0) * 100.0}),
        .bowDmg => |x| fmt("The bow deals {d:.0}% more", .{(x - 1.0) * 100.0}),
        .thrownDmg => |x| fmt("Thrown things deal {d:.0}% more", .{(x - 1.0) * 100.0}),
        .fpRegen => |x| fmt("Recover {d:.1} FP a second", .{x}),
        .fpMax => |x| fmt("+{d:.0}% Focus", .{(x - 1.0) * 100.0}),
        .castSpeed => |x| fmt("Casts come out {d:.0}% faster", .{(x - 1.0) * 100.0}),
        .boltCloud => "The Chaos Bolt bursts into a lingering cloud",
    };
}

/// EVERYTHING THE TREE IS WORTH, folded into one value the rest of the game reads FIELDS off. Nothing
/// outside here walks the node list: a perk is a number on this struct or it does not exist.
///
/// **THE IDENTITY IS THE FIELD'S OWN** — 0 for anything ADDED, 1 for anything MULTIPLIED, false for a flag.
/// Get one wrong and every hero starts the game either wearing the keystone or unable to move at all.
pub const Bonus = struct {
    attrs: [stats.NA]u8 = [_]u8{0} ** stats.NA,
    res: combat.Resists = .{},
    guard: f32 = 0,
    iframe: f32 = 0,
    poison: f32 = 1,
    rollStam: f32 = 1,
    spellCost: f32 = 1,
    spellDmg: f32 = 1,

    armour: f32 = 0,
    hpRegen: f32 = 0,
    leech: f32 = 0,
    /// The bargain, folded: how much of the bar is gone, and what every blow is multiplied by for it.
    hpFrac: f32 = 0,
    dmg: f32 = 1,
    cull: f32 = 0,
    onKill: f32 = 0,

    moveSpeed: f32 = 1,
    stamRegen: f32 = 1,
    bowDmg: f32 = 1,
    thrownDmg: f32 = 1,

    fpRegen: f32 = 0,
    fpMax: f32 = 1,
    castSpeed: f32 = 1,
    boltCloud: bool = false,

    /// THE LIVE CHARACTER SHEET — the starting sheet plus every attribute node taken, and the ONLY way an
    /// attribute here ever moves. `stats.Sheet.set` clamps, so a maxed attribute cannot be pushed past 99.
    pub fn sheet(self: Bonus) stats.Sheet {
        var s = stats.Sheet{};
        for (self.attrs, 0..) |n, i| {
            s.add(@enumFromInt(i), n);
        }
        return s;
    }
};

/// SOULS FOR THE NEXT NODE, off the level you are standing on. Quadratic, ER's shape.
///
/// MEASURED AGAINST WHAT A BODY IS WORTH, not picked for looking like money: a toad is 60, an archer 130, a
/// brood mother 240. **THE FIRST NODE COSTS `costAt(1)`, WHICH IS 360** — never `costAt(0)`: `Tree.cost`
/// prices the LEVEL you are standing on, and you stand on level 1 before you have spent anything at all.
pub fn costAt(level: u32) u32 {
    return 280 + 62 * level + 18 * level * level;
}

pub const Tree = struct {
    taken: [N]bool = [_]bool{false} ** N,

    /// TAKING A NODE IS THE LEVEL (owner's call) — there is no pool of points between the two, because a
    /// point you are holding is a decision you have already paid for and not yet made, and that is a state
    /// with nothing to show for itself. LEVEL IS COUNTED, never stored (`stats.Sheet.level`'s law): it is
    /// the nodes on the board plus one.
    pub fn spent(self: *const Tree) u32 {
        var n: u32 = 0;
        for (self.taken) |t| n += @intFromBool(t);
        return n;
    }

    pub fn level(self: *const Tree) u32 {
        return self.spent() + 1;
    }

    /// What the NEXT node costs, whichever it turns out to be. One price per level, not per node: what you
    /// are buying is the level, and which node it lands on is the choice rather than the bill.
    pub fn cost(self: *const Tree) u32 {
        return costAt(self.level());
    }

    /// CAN YOU GET TO IT — is ANY one of the things it hangs off already yours. That is the whole rule: you
    /// climb a node at a time to the capstone you want, either strand of an arm reaches its own tip, and no
    /// count and no toll comes into it.
    pub fn reached(self: *const Tree, i: usize) bool {
        var buf: [2]usize = undefined;
        const fs = feeders(i, &buf);
        if (fs.len == 0) return true; // hangs off the hub
        for (fs) |f| {
            if (self.taken[f]) return true;
        }
        return false;
    }

    pub fn spentIn(self: *const Tree, a: Arm) u32 {
        var n: u32 = 0;
        for (self.taken[armFirst(a)..][0..PER_ARM]) |t| n += @intFromBool(t);
        return n;
    }

    /// Nothing left to take.
    pub fn full(self: *const Tree) bool {
        return self.spent() >= N;
    }

    /// WHY YOU CANNOT TAKE THIS ONE, or null if you can. A sentence rather than a bool: a node that refuses
    /// silently is one the player presses again. An EMPTY string refuses without printing — for the reasons
    /// the page is already showing somewhere better.
    /// **CAN HE TAKE THIS ONE — THE QUESTION WITHOUT THE SENTENCE.** The wheel asks it of EVERY node every
    /// frame to decide open-or-shut (`draw`), and `locked` answers by FORMATTING a string, so a page nobody
    /// is reading spent 39 `bufPrintZ`s a frame and cycled the shared `scratch` ring under any caller still
    /// holding a line off it. The reason is wanted at ONE node — the one the cursor is on.
    pub fn canTake(self: *const Tree, i: usize, souls: u32) bool {
        return !self.taken[i] and self.reached(i) and souls >= self.cost();
    }

    /// WHY YOU CANNOT TAKE THIS ONE, or null if you can — the same rule as `canTake`, said out loud. Asked of
    /// the ONE node being read, never of the board.
    pub fn locked(self: *const Tree, i: usize, souls: u32) ?[:0]const u8 {
        if (self.taken[i]) return ""; // the page marks it TAKEN in its own words
        if (!self.reached(i)) return "Take the one before it first.";
        const c = self.cost();
        if (souls < c) return fmt("{d} souls. You are carrying {d}.", .{ c, souls });
        return null;
    }

    /// TAKE IT, AND THAT IS THE LEVEL. Hands back the souls it cost, or null if it refused — the caller holds
    /// the counter, so the tree never reaches into it (`souls.take`'s shape).
    pub fn take(self: *Tree, i: usize, souls: u32) ?u32 {
        if (!self.canTake(i, souls)) return null;
        const c = self.cost();
        self.taken[i] = true;
        return c;
    }

    pub fn bonus(self: *const Tree) Bonus {
        var b = Bonus{};
        for (self.taken, 0..) |on, i| {
            if (!on) continue;
            switch (NODES[i].grant) {
                .attr => |x| b.attrs[@intFromEnum(x.a)] += x.n,
                .res => |r| for (r.v, 0..) |amt, e| {
                    b.res.v[e] += amt;
                },
                .guard => |x| b.guard += x,
                .iframe => |x| b.iframe += x,
                .poison => |x| b.poison *= x,
                .rollStam => |x| b.rollStam *= x,
                .spellCost => |x| b.spellCost *= x,
                .spellDmg => |x| b.spellDmg *= x,
                // **THE FOLD IS THE FIELD'S OWN ARITHMETIC** — added, multiplied or latched, and which one
                // each is, is written at `Bonus`. An exhaustive switch is what makes a new grant a compile
                // error here rather than a node that quietly does nothing.
                .armour => |x| b.armour += x,
                .hpRegen => |x| b.hpRegen += x,
                .leech => |x| b.leech += x,
                // A BARGAIN FOLDS AS BOTH ITS HALVES: the costs ADD (two of them take a quarter of the bar
                // between them) and the gains MULTIPLY, which is what keeps stacking them a real decision
                // rather than a straight line.
                .sacrifice => |x| {
                    b.hpFrac += x.hpFrac;
                    b.dmg *= x.dmg;
                },
                // THE CULL TAKES THE BEST, never the sum: two thresholds are one threshold, and adding them
                // would make a pair of small nodes an execute on half health.
                .cull => |x| b.cull = mathx.maxF(b.cull, x),
                .onKill => |x| b.onKill += x,
                .moveSpeed => |x| b.moveSpeed *= x,
                .stamRegen => |x| b.stamRegen *= x,
                .bowDmg => |x| b.bowDmg *= x,
                .thrownDmg => |x| b.thrownDmg *= x,
                .fpRegen => |x| b.fpRegen += x,
                .fpMax => |x| b.fpMax *= x,
                .castSpeed => |x| b.castSpeed *= x,
                .boltCloud => b.boltCloud = true,
            }
        }
        return b;
    }
};

// THE WHEEL. Positions are solved in UNITS about a centre — one ring apart — so the walk and the draw read
// the same geometry and a resized card cannot move a node out from under the cursor.

/// 0 is straight UP and the angle runs CLOCKWISE, which is the sense a screen's +y already has.
fn armAngle(a: Arm) f32 {
    return switch (a) {
        .wizard => 0,
        .rogue => std.math.tau / 3.0,
        .warrior => 2.0 * std.math.tau / 3.0,
    };
}

/// **HOW FAR OFF ITS ARM'S OWN BEARING EACH OF THE TWO BRANCHES SITS.** The three arms are 120° apart, so
/// each has 60° either side to itself before it starts arguing with its neighbour; the two branches take
/// half of that and leave the rest as the gap that says WHICH ARM you are looking at. Wider and the six
/// read as six unrelated spokes with no arms at all; narrower and an arm's two branches smear into one fan.
const BRANCH_SPLIT: f32 = 0.42;

/// A BRANCH'S OWN BEARING — its arm's, stepped off it by `BRANCH_SPLIT`, lane 0 anticlockwise.
fn branchAngle(b: Branch) f32 {
    const side: f32 = if (b.lane() == 0) -1.0 else 1.0;
    return armAngle(b.arm()) + side * BRANCH_SPLIT;
}

/// How wide a ring's fan opens. It WIDENS outward — a constant spread draws parallel rails, which is a
/// ladder and not a branch. **AND IT IS NARROWER THAN IT WAS**: a branch now has half an arm's lane rather
/// than the whole of it, so a fan sized for the old three would put one branch's ring-2 pair on top of its
/// neighbour's. Solved against `BRANCH_SPLIT` rather than picked — the widest fan may not reach the lane's
/// own half-width, or the two branches of an arm cross.
fn spreadAt(ring: u8) f32 {
    return 0.155 + 0.045 * @as(f32, @floatFromInt(ring));
}

comptime {
    // THE TWO BRANCHES OF AN ARM MAY NOT TOUCH. The outermost fan is the widest, and it has to stay inside
    // the gap the split bought it or a keystone sits in its own twin's lane.
    std.debug.assert(spreadAt(RINGS - 1) < BRANCH_SPLIT);
}

fn angleOf(n: Node) f32 {
    // THE CLASS NODE SITS ON ITS ARM'S OWN BEARING — it is what both branches radiate out of, so it may not
    // lean toward either of them.
    const b = n.branch orelse return armAngle(n.arm);
    const slots = BRANCH_RINGS[n.ring - 1];
    if (slots == 1) return branchAngle(b);
    const t = @as(f32, @floatFromInt(n.slot)) / @as(f32, @floatFromInt(slots - 1)); // 0..1 across the fan
    return branchAngle(b) + (t * 2.0 - 1.0) * spreadAt(n.ring);
}

/// In RINGS from the hub.
fn radiusOf(n: Node) f32 {
    return @as(f32, @floatFromInt(n.ring)) + 1.0;
}

/// THE MIDDLE, as a cursor position. It is not a node and nothing is ever spent on it — but it IS where you
/// start, and a cursor that cannot rest on the one place the whole tree is described from is a cursor with a
/// hole in it. Indexed one past the last node, so every `NODES[i]` site is untouched.
pub const HUB: usize = N;
/// Every place the cursor may sit: the nodes, and the middle.
pub const SPOTS: usize = N + 1;

fn unitPos(i: usize) rl.Vector2 {
    if (i >= N) return .{ .x = 0, .y = 0 };
    const n = NODES[i];
    const a = angleOf(n);
    const r = radiusOf(n);
    return .{ .x = mathx.sinf(a) * r, .y = -mathx.cosf(a) * r };
}

/// THE WEDGE a push has to land in, as the cosine of its half-angle — 60°, which is what the three arms at
/// 120° need: from the middle, DOWN has to reach the two lower arms and their ring-0 nodes sit 45-60° off
/// straight down. Tighter and the cursor simply refuses to go that way; wider and opposite arms start
/// competing for the same push.
const STEP_CONE: f32 = 0.5;
/// …and how much being off-axis costs once you are inside the wedge, as a share of the distance. It only
/// breaks ties between candidates at similar range: dead ahead beats a near-miss 45° off, but a node right
/// under your thumb still beats one on the far side of the wheel.
const STEP_BIAS: f32 = 1.0;

/// MOVE BY GEOMETRY, not by ordinal (`book.slotStep`'s law) — on a wheel an ordinal walk steps between
/// nodes that are nowhere near each other, and crossing from one arm to its neighbour has no arithmetic.
pub fn step(cur: usize, dx: f32, dy: f32) usize {
    const push = std.math.hypot(dx, dy);
    if (push < 1e-6) return cur;
    const from = unitPos(cur);
    const fdx = dx / push;
    const fdy = dy / push;
    var best = cur;
    var score: f32 = std.math.floatMax(f32);
    for (0..SPOTS) |i| {
        if (i == cur) continue;
        const p = unitPos(i);
        const ax = p.x - from.x;
        const ay = p.y - from.y;
        const dist = std.math.hypot(ax, ay);
        if (dist < 1e-5) continue;
        const cos = (ax * fdx + ay * fdy) / dist; // 1 = dead on the push, 0 = square across it
        if (cos < STEP_CONE) continue; // not in that direction at all
        const s = dist * (1.0 + STEP_BIAS * (1.0 - cos));
        if (s < score) {
            score = s;
            best = i;
        }
    }
    return best;
}

pub const ZOOM_MIN: f32 = 1.0;
pub const ZOOM_MAX: f32 = 3.2;
/// Zoom travel a second, held. Slow enough to stop where you meant to.
pub const ZOOM_RATE: f32 = 1.7;
/// How far the view slides a second at full stick, in units of the wheel AT ZOOM_MIN — divided by the zoom
/// where it is spent, so the pan crosses the same amount of SCREEN however far in you are.
pub const PAN_RATE: f32 = 3.4;
/// …and how far it may slide at all, in units, at full zoom.
const PAN_SPAN: f32 = 6.0;
/// **AND IT IS LIVE FROM THE FRAME THE PAGE OPENS** (owner: "so it starts pannable"). It used to be pinned to
/// nothing at `ZOOM_MIN`, on the argument that a box-fitted wheel has nothing off-screen to go and look at —
/// which stopped being true the moment the framing became a SQUARE ON THE HUB (`VIEW_R`): the two lower arms
/// now run out into the long axis' own slack and the wizard's keystone sits at the top of the square, so
/// sliding the view is the thing that brings a tip fully into the middle to read it. Sized well under the
/// square's own half-extent, which is what still stops a player sliding the tree out of its panel entirely.
const PAN_FLOOR: f32 = 1.6;

/// WHERE THE WHEEL IS BEING LOOKED AT FROM — the cursor, how far in, and where the view has been slid to.
pub const Wheel = struct {
    /// It opens in the MIDDLE, which is where the player is standing before he has spent anything.
    cursor: usize = HUB,
    zoom: f32 = ZOOM_MIN,
    /// THE VIEW'S OWN OFFSET, in units, on top of the framing the zoom picks. Additive rather than a mode:
    /// walking the cursor still pulls the view along (that is what keeps the thing you are choosing on
    /// screen), and this is the player saying "and a bit that way" over the top of it.
    pan: rl.Vector2 = .{ .x = 0, .y = 0 },

    /// Directional, never cyclic (`step`'s law). `dx`/`dy` are a HEADING, not a pair of steps — a cardinal
    /// from the cross and the keys, the thumb's own bearing from the stick. True if it actually went somewhere.
    pub fn move(self: *Wheel, dx: f32, dy: f32) bool {
        const next = step(self.cursor, dx, dy);
        if (next == self.cursor) return false;
        self.cursor = next;
        return true;
    }

    pub fn zoomBy(self: *Wheel, dv: f32, dt: f32) void {
        self.zoom = mathx.clampF(self.zoom + dv * ZOOM_RATE * dt, ZOOM_MIN, ZOOM_MAX);
        self.clampPan(); // …and zooming back OUT has to walk the pan home with it, or the wheel is left off-centre with nowhere off-screen to justify it
    }

    /// THE RIGHT STICK, as a view slide. `v` is the raw thumb, so a lazy push moves it slowly.
    pub fn panBy(self: *Wheel, v: rl.Vector2, dt: f32) void {
        if (v.x == 0 and v.y == 0) return;
        const k = PAN_RATE * dt / self.zoom;
        self.pan.x += v.x * k;
        self.pan.y += v.y * k;
        self.clampPan();
    }

    /// How far the view may slide: a FLOOR that is live at `ZOOM_MIN` (`PAN_FLOOR` — the page opens pannable),
    /// growing with whatever the zoom has pushed off the edge on top of it.
    fn panLimit(self: *const Wheel) f32 {
        return PAN_FLOOR + PAN_SPAN * (1.0 - 1.0 / mathx.clampF(self.zoom, ZOOM_MIN, ZOOM_MAX));
    }

    fn clampPan(self: *Wheel) void {
        const lim = self.panLimit();
        self.pan.x = mathx.clampF(self.pan.x, -lim, lim);
        self.pan.y = mathx.clampF(self.pan.y, -lim, lim);
    }
};

const Lay = struct { cx: f32, cy: f32, unit: f32 };

/// The hub's own disc, in units — read by the draw AND by the cursor that can now land on it.
const HUB_R: f32 = 0.26;

/// A KEYSTONE'S OWN DISC, in units, and the halo an OPEN node wears over it as a multiple of that disc.
const KEY_R: f32 = 0.30;
const HALO_K: f32 = 2.1;

/// A SQUARE WINDOW ON THE HUB, and this is its half-extent in units (owner: "square with central node in
/// center, so it starts pannable, not bottom heavy").
const VIEW_R: f32 = @as(f32, @floatFromInt(RINGS)) + KEY_R * HALO_K;

/// A SQUARE WINDOW CENTRED ON THE HUB — see `VIEW_R`. `unit` comes off the panel's SHORT axis so the square
/// fits either way up, and the long axis simply shows more of the world than the square asked for; on the wide
/// box this page gets, that room is exactly where the two lower arms run.
fn layout(wh: Wheel, x: i32, y: i32, w: i32, h: i32) Lay {
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    const zoom = mathx.clampF(wh.zoom, ZOOM_MIN, ZOOM_MAX);
    const unit = @min(fw, fh) / (2.0 * VIEW_R) * zoom;
    // THE ZOOM WALKS THE VIEW ONTO THE CURSOR. Scaled about the hub instead, the first notch in pushes whatever
    // you were reading off the edge of the panel — which is a zoom that fights you. At ZOOM_MIN the blend is 0
    // and the middle of the panel is the HUB, which is where the page opens and where the cursor starts.
    const k = mathx.clampF((zoom - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN), 0, 1);
    const on = unitPos(@min(wh.cursor, HUB));
    // …AND THE PLAYER'S OWN SLIDE ON TOP OF IT (`Wheel.pan`). Pushing the stick RIGHT moves the VIEW right,
    // which is the content going left — the same sense the cursor walks in, so the two thumbs agree.
    const fx = on.x * k + wh.pan.x;
    const fy = on.y * k + wh.pan.y;
    return .{
        .cx = @as(f32, @floatFromInt(x)) + fw * 0.5 - fx * unit,
        .cy = @as(f32, @floatFromInt(y)) + fh * 0.5 - fy * unit,
        .unit = unit,
    };
}

fn place(l: Lay, i: usize) rl.Vector2 {
    const p = unitPos(i);
    return .{ .x = l.cx + p.x * l.unit, .y = l.cy + p.y * l.unit };
}

fn radiusPx(l: Lay, i: usize) f32 {
    if (i >= N) return l.unit * HUB_R;
    return l.unit * (if (NODES[i].key) KEY_R else switch (NODES[i].grant) {
        .attr => @as(f32, 0.15),
        else => @as(f32, 0.21),
    });
}

/// WHERE THE CURSOR'S BRACKETS GO — off the same layout the wheel is drawn from, so they cannot drift off
/// the node they are naming however far it is zoomed.
pub fn nodeRect(wh: Wheel, x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    const l = layout(wh, x, y, w, h);
    const i = @min(wh.cursor, HUB);
    const p = place(l, i);
    const r = radiusPx(l, i) + 6.0;
    return .{ .x = p.x - r, .y = p.y - r, .width = r * 2, .height = r * 2 };
}

/// THE WHEEL ITSELF, inside its own box. SCISSORED: zoomed in, the arms run well past the panel, and
/// spilling them over the card's frame reads as a draw bug rather than as a magnified view.
pub fn draw(t: *const Tree, wh: Wheel, x: i32, y: i32, w: i32, h: i32, spendable: bool, souls: u32) void {
    rl.beginScissorMode(x, y, w, h);
    defer rl.endScissorMode();
    const l = layout(wh, x, y, w, h);
    const hub = rl.Vector2{ .x = l.cx, .y = l.cy };

    // The rings first, under everything — they are what says the gates are CONCENTRIC.
    for (0..RINGS) |r| {
        rl.drawCircleLinesV(hub, l.unit * @as(f32, @floatFromInt(r + 1)), mathx.withAlpha(uiart.GILT_DIM, 26));
    }

    // EXACTLY ONE LINE PER NODE, back to the single thing that feeds it — its own arm one ring in, or the
    // hub for the first ring. One parent each is the whole rule: the first pass gave the keystone TWO and
    // wired the hub to six separate nodes, and a web that dense is one the eye has to read past.
    for (0..N) |i| {
        const n = NODES[i];
        const to = place(l, i);
        var buf: [2]usize = undefined;
        const fs = feeders(i, &buf);
        // A LINK IS LIT WHEN IT HAS BEEN WALKED, and merely OPEN when the end you would come from is yours —
        // which is the whole of the rule, drawn. Nothing else on the page says what is reachable.
        if (fs.len == 0) {
            rl.drawLineEx(hub, to, l.unit * (if (t.taken[i]) @as(f32, 0.055) else 0.038), mathx.withAlpha(n.arm.ink(), if (t.taken[i]) 225 else 130));
            continue;
        }
        for (fs) |f| {
            const walked = t.taken[i] and t.taken[f];
            const open = t.taken[f];
            rl.drawLineEx(
                place(l, f),
                to,
                l.unit * (if (walked) @as(f32, 0.055) else if (open) @as(f32, 0.038) else @as(f32, 0.022)),
                mathx.withAlpha(n.arm.ink(), if (walked) 225 else if (open) 130 else 44),
            );
        }
    }

    // THE HUB — where you start, and it is not a node: nothing is spent on it and nothing can be. The
    // cursor may still SIT on it (`HUB`), which is what the reading column describes the tree itself from.
    rl.drawCircleV(hub, l.unit * HUB_R, mathx.withAlpha(uiart.INK, 235));
    rl.drawCircleLinesV(hub, l.unit * HUB_R, mathx.withAlpha(uiart.GILT, 200));
    uiart.finial(hub.x, hub.y, l.unit * 0.11, uiart.GILT_BRIGHT);

    for (0..N) |i| {
        const n = NODES[i];
        const p = place(l, i);
        const r = radiusPx(l, i);
        const ink = n.arm.ink();
        const open = spendable and t.canTake(i, souls);
        // THREE STATES AND THEY SEPARATE ON FILL, not on hue: taken is solid, open is a lit rim over the
        // seat, and locked is the rim gone to nothing. Read at arm's length, a hue shift is one state.
        rl.drawCircleV(p, r + 2.0, mathx.withAlpha(uiart.INK, 210));
        if (t.taken[i]) {
            rl.drawCircleV(p, r, ink);
            rl.drawCircleV(p, r * 0.42, mathx.withAlpha(uiart.CATCH, 220));
        } else {
            rl.drawCircleV(p, r, mathx.withAlpha(uiart.STONE_DK, 235));
            rl.drawCircleLinesV(p, r, mathx.withAlpha(ink, if (open) 235 else 80));
        }
        if (open and !t.taken[i]) uiart.candle(@intFromFloat(p.x), @intFromFloat(p.y), r * HALO_K, 26);
        if (n.key) rl.drawCircleLinesV(p, r + 3.5, mathx.withAlpha(if (t.taken[i]) uiart.GILT_BRIGHT else uiart.GILT_DIM, 150));
    }

    // WHERE YOU ARE, and it is drawn LAST so nothing can be laid over it. On a wheel there are no rows to
    // wash, so the mark has to be built out of the node itself: a halo standing off the disc, a hard rim on
    // the disc, and the chrome's own corner brackets around it. All three, because one of them alone is
    // either lost against a taken node's fill (the rim) or against the ring circles behind it (the halo).
    const sel = @min(wh.cursor, HUB);
    const sp = place(l, sel);
    const sr = radiusPx(l, sel);
    const beat = 0.5 + 0.5 * mathx.sinf(@as(f32, @floatCast(rl.getTime())) * 3.4);
    rl.drawCircleLinesV(sp, sr + 5.0 + 3.0 * beat, mathx.withAlpha(uiart.CATCH, mathx.u8f(90.0 + 70.0 * beat)));
    rl.drawCircleLinesV(sp, sr + 1.5, uiart.CATCH);
    rl.drawCircleLinesV(sp, sr + 2.5, mathx.withAlpha(uiart.CATCH, 170));
    const br = sr + 7.0;
    uiart.slotCursor(
        @intFromFloat(sp.x - br),
        @intFromFloat(sp.y - br),
        @intFromFloat(br * 2),
        @intFromFloat(br * 2),
        0,
        1.0,
    );

    // NO TALLY AT THE SPOKE TIPS (owner's call). How deep an arm is, is already drawn twice over — in how
    // far its links are lit, and in the nodes that are filled in — so a digit floating past the end of each
    // branch was a third copy of it, and the one that reads as a label rather than as the tree.
}

// THE PAGE — the wheel and the column that reads it. ONE copy, because the tree is looked at from two
// places now (the book's page and the bonfire's own screen) and two transcriptions of a readout is two
// readouts one edit apart.

/// Sunk panel, `book.panel`'s dressing without book's layout types — this file cannot import that one.
fn well(x: i32, y: i32, w: i32, h: i32) void {
    uiart.well(x, y, w, h, 210);
    rl.drawRectangleLinesEx(uiart.rect(x, y, w, h), 1, mathx.withAlpha(uiart.GILT_DIM, 90));
}

var proseLines: [8][:0]const u8 = undefined;
var proseBuf: [768]u8 = undefined;

fn prose(s: []const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color) i32 {
    var yy = y;
    for (hud.wrap(s, size, w, &proseBuf, &proseLines)) |line| {
        hud.text(line, x, yy, size, col);
        yy += hud.lineH(size);
    }
    return yy;
}

/// How wide the reading column wants to be inside `w`. The wheel is a PICTURE: a column half the page wide
/// leaves it too small to find a node on.
pub fn readW(w: i32) i32 {
    return @min(@divTrunc(w * 30, 100), 430);
}

const GUT: i32 = 18;

pub fn wheelBox(x: i32, y: i32, w: i32, h: i32) [4]i32 {
    return .{ x, y, w - readW(w) - GUT, h };
}

/// EVERYTHING THE PAGE SAYS. `spendable` is the bonfire and nothing else: away from a fire this is a thing you
/// read, and the caller's crib must not offer what a press would refuse.
pub fn drawPage(t: *const Tree, wh: Wheel, x: i32, y: i32, w: i32, h: i32, spendable: bool, souls: u32) void {
    const rw = readW(w);
    const box = wheelBox(x, y, w, h);
    well(box[0], box[1], box[2], box[3]);
    draw(t, wh, box[0], box[1], box[2], box[3], spendable, souls);

    const cx = x + w - rw;
    well(cx, y, rw, h);
    const head = fmt("LEVEL {d}", .{t.level()});
    hud.text(head, cx + 14, y + 8, hud.TINY, mathx.withAlpha(uiart.GILT, 220));
    rl.drawRectangle(cx + 14, y + hud.lineH(hud.TINY) + 10, rw - 28, 1, mathx.withAlpha(uiart.GILT_DIM, 80));

    const ix = cx + 14;
    const iw = rw - 28;
    const right = ix + iw;
    var yy = y + hud.lineH(hud.TINY) + 22;

    // WHAT THE NEXT NODE COSTS against what he is carrying, coloured by whether he can afford it rather than
    // said twice. It is ONE price whichever node he picks — what he is buying is the level, and which node it
    // lands on is the choice and not the bill. A FULL TREE prices nothing.
    const c = t.cost();
    hud.text("Required", ix, yy, hud.SMALL, uiart.TEXT_DIM);
    const cs: [:0]const u8 = if (t.full()) "all spent" else fmt("{d}", .{c});
    const ccol = if (t.full()) uiart.TEXT_DIM else if (souls >= c) uiart.GOOD else uiart.BAD;
    hud.text(cs, right - hud.textW(cs, hud.SMALL), yy, hud.SMALL, ccol);
    yy += hud.lineH(hud.SMALL) + 4;
    hud.text("Souls", ix, yy, hud.SMALL, uiart.TEXT_DIM);
    const rs = fmt("{d}", .{souls});
    hud.text(rs, right - hud.textW(rs, hud.SMALL), yy, hud.SMALL, uiart.TEXT_VALUE);
    yy += hud.lineH(hud.SMALL) + 10;
    uiart.divider(ix + @divTrunc(iw, 2), yy, @divTrunc(iw, 2) - 10, 120);
    yy += 14;

    const i = @min(wh.cursor, HUB);
    // THE MIDDLE IS A PLACE THE CURSOR MAY REST, and it describes the tree rather than a node. It is not a
    // purchase and it never becomes one, so it prints no price and refuses nothing — there is nothing here
    // to refuse.
    if (i == HUB) {
        hud.text("The Middle", ix, yy, hud.BODY, uiart.TEXT_TITLE);
        yy += hud.lineH(hud.BODY) + 6;
        _ = prose(
            "Where you begin, and the one place all three branches are open from. Nothing to take.",
            ix,
            yy,
            iw,
            hud.SMALL,
            uiart.TEXT_VALUE,
        );
        return;
    }
    const n = NODES[i];
    hud.text(n.name, ix, yy, hud.BODY, if (t.taken[i]) uiart.HOT else uiart.TEXT_TITLE);
    yy += hud.lineH(hud.BODY) + 6;
    yy = prose(grantSays(n.grant), ix, yy, iw, hud.SMALL, uiart.TEXT_VALUE) + 8;

    // WHY IT IS SHUT, in the tree's own words — and away from a fire the reason IS the fire, which outranks
    // the node's: a lock naming a missing point at that moment sends him grinding for one he already has.
    if (t.taken[i]) {
        hud.text("TAKEN", ix, yy, hud.HINT, uiart.GOOD);
    } else if (!spendable) {
        _ = prose("Sit at a bonfire to level up and to spend what you have.", ix, yy, iw, hud.HINT, uiart.TEXT_HINT);
    } else if (t.locked(i, souls)) |whyNot| {
        if (whyNot.len > 0) _ = prose(whyNot, ix, yy, iw, hud.HINT, uiart.TEXT_HINT);
    }
}

var scratch: [8][160]u8 = undefined;
var scratchAt: usize = 0;

/// `book.fmt`'s own scratch, at this file's own size — good until seven more have been made, which is what
/// every caller here needs and no more.
fn fmt(comptime f: []const u8, args: anytype) [:0]const u8 {
    scratchAt = (scratchAt + 1) % scratch.len;
    return std.fmt.bufPrintZ(&scratch[scratchAt], f, args) catch "?";
}

const RICH: u32 = 1_000_000; // enough souls that the tests are never about the purse

test "EVERY GRANT IS ON THE BOARD, and an EMPTY bonus changes nothing" {
    // **NO DEAD VARIANT.** A `Grant` nobody grants is a mechanic wired into the game that no node can ever
    // reach — which is exactly what a half-landed tree looks like from the outside.
    inline for (@typeInfo(Grant).@"union".fields) |f| {
        var seen = false;
        for (NODES) |n| {
            if (std.mem.eql(u8, @tagName(n.grant), f.name)) seen = true;
        }
        if (!seen) {
            std.debug.print("  passive tree: nothing grants {s}\n", .{f.name});
            try std.testing.expect(false);
        }
    }

    // **THE IDENTITY.** Get one of these backwards and every hero starts the game either wearing a keystone
    // or unable to move: a multiplier defaulted to 0 is a man with no speed, no damage and no pool at all.
    const none = Bonus{};
    try std.testing.expectEqual(@as(f32, 0), none.guard + none.iframe + none.armour + none.hpRegen +
        none.leech + none.hpFrac + none.cull + none.onKill + none.fpRegen);
    inline for (.{ none.poison, none.rollStam, none.spellCost, none.spellDmg, none.dmg, none.moveSpeed, none.stamRegen, none.bowDmg, none.thrownDmg, none.fpMax, none.castSpeed }) |m| {
        try std.testing.expectEqual(@as(f32, 1), m);
    }
    try std.testing.expect(!none.boltCloud);
    try std.testing.expectEqual(stats.Sheet{}, none.sheet()); // …and it is the starting sheet, exactly

    // …AND THE WHOLE TREE MOVES EVERY ONE OF THEM OFF IT, which is what says each is actually granted.
    var t = Tree{};
    for (0..N) |i| _ = t.take(i, RICH);
    const all = t.bonus();
    try std.testing.expect(all.guard > 0 and all.iframe > 0 and all.armour > 0 and all.hpRegen > 0);
    try std.testing.expect(all.leech > 0 and all.hpFrac > 0 and all.cull > 0 and all.onKill > 0 and all.fpRegen > 0);
    try std.testing.expect(all.rollStam < 1 and all.spellCost < 1); // the two that buy CHEAPNESS
    try std.testing.expect(all.spellDmg > 1 and all.dmg > 1 and all.moveSpeed > 1 and all.stamRegen > 1);
    try std.testing.expect(all.bowDmg > 1 and all.thrownDmg > 1 and all.fpMax > 1 and all.castSpeed > 1);
    try std.testing.expect(all.boltCloud);
    // THE BARGAIN MAY NEVER EAT THE WHOLE BAR — both sacrifices taken together, against `hero.hpMaxOf`'s floor.
    try std.testing.expect(all.hpFrac < 0.9);
    std.debug.print("  every branch taken: {d:.0}% of the red bar sold for {d:.2}x damage, cull at {d:.0}%\n", .{ all.hpFrac * 100, all.dmg, all.cull * 100 });
}

test "you start in the MIDDLE: every arm's CLASS NODE hangs off the hub, and nothing else does" {
    var t = Tree{};
    for (0..NARM) |ai| {
        const a: Arm = @enumFromInt(ai);
        const root = armFirst(a);
        try std.testing.expect(t.locked(root, RICH) == null); // the one thing open from a standing start
        try std.testing.expect(NODES[root].branch == null);
        // …and BOTH of its branches are shut until it is taken. That is what "radiate out from there" means.
        for (0..2) |lane| {
            const b: Branch = @enumFromInt(ai * 2 + lane);
            try std.testing.expect(t.locked(branchFirst(b), RICH) != null);
        }
    }
    // EXACTLY THREE WAYS IN, one per arm — six branches behind three doors.
    var open: usize = 0;
    for (0..N) |i| {
        if (t.locked(i, RICH) == null) open += 1;
    }
    try std.testing.expectEqual(NARM, open);
}

test "YOU CLIMB: the class node opens BOTH branches, and each rung opens only its own" {
    var t = Tree{};
    const root = armFirst(.rogue);
    const ev = branchFirst(.rogue_evade);
    const rg = branchFirst(.rogue_ranged);
    try std.testing.expect(t.locked(ev, RICH) != null);
    // THE CLASS NODE IS THE ONE PURCHASE THAT BUYS THE ARM — after it, both branches are a live choice.
    try std.testing.expect(t.take(root, RICH) != null);
    try std.testing.expect(t.locked(ev, RICH) == null);
    try std.testing.expect(t.locked(rg, RICH) == null);
    // …and nothing past each branch's mouth is open yet.
    try std.testing.expect(t.locked(ev + 1, RICH) != null);
    try std.testing.expect(t.locked(rg + 1, RICH) != null);
    // One rung up the evasion branch opens ITS ring-2 pair and nothing on the other branch.
    try std.testing.expect(t.take(ev, RICH) != null);
    try std.testing.expect(t.locked(ev + 1, RICH) == null);
    try std.testing.expect(t.locked(ev + 2, RICH) == null);
    try std.testing.expect(t.locked(ev + 3, RICH) != null); // …ring 3 is still a link away
    try std.testing.expect(t.locked(rg + 1, RICH) != null);
    // …and no arm reaches into another one.
    try std.testing.expect(t.locked(branchFirst(.warrior_life), RICH) != null);
}

test "EVERY BRANCH HAS ITS OWN KEYSTONE, and either strand climbs to it" {
    for (0..NBRANCH) |bi| {
        const b: Branch = @enumFromInt(bi);
        const base = branchFirst(b);
        const key = base + PER_BRANCH - 1;
        try std.testing.expect(NODES[key].key);
        try std.testing.expectEqual(b, NODES[key].branch.?);
        for ([_]usize{ 0, 1 }) |strand| {
            var t = Tree{};
            // The arm's class node, the branch's mouth, then ONE side of its fan to the top.
            try std.testing.expect(t.take(armFirst(b.arm()), RICH) != null);
            try std.testing.expect(t.take(base, RICH) != null);
            try std.testing.expect(t.locked(key, RICH) != null);
            try std.testing.expect(t.take(base + 1 + strand, RICH) != null);
            try std.testing.expect(t.locked(key, RICH) != null);
            try std.testing.expect(t.take(base + 3 + strand, RICH) != null);
            // …and from EITHER ring-3 node the keystone is open. Five nodes, not nine.
            try std.testing.expect(t.locked(key, RICH) == null);
            try std.testing.expect(t.take(key, RICH) != null);
            try std.testing.expectEqual(@as(u32, 5), t.spentIn(b.arm()));
        }
    }
}

test "SIX BRANCHES, TWO PER CLASS — and each one is its own idea end to end" {
    try std.testing.expectEqual(@as(usize, 2), NBRANCH / NARM);
    for (0..NBRANCH) |bi| {
        const b: Branch = @enumFromInt(bi);
        // Every node of a branch belongs to that branch's arm, and the branch is contiguous in the table.
        for (branchFirst(b)..branchFirst(b) + PER_BRANCH) |i| {
            try std.testing.expectEqual(b, NODES[i].branch.?);
            try std.testing.expectEqual(b.arm(), NODES[i].arm);
        }
    }
    // …and an ARM is its class node plus both of its branches, with nothing left over.
    try std.testing.expectEqual(PER_ARM, 1 + PER_BRANCH * 2);
    try std.testing.expectEqual(N, NARM * PER_ARM);
    std.debug.print("\n  passive tree: {d} nodes - {d} arms x (1 class node + 2 branches of {d})\n", .{ N, NARM, PER_BRANCH });
}

test "THE LINK IS THE RULE — every feeder is its own arm's, one ring in, and the tip alone has two" {
    for (0..N) |i| {
        var buf: [2]usize = undefined;
        const fs = feeders(i, &buf);
        for (fs) |f| {
            try std.testing.expectEqual(NODES[i].arm, NODES[f].arm);
            try std.testing.expectEqual(NODES[i].ring - 1, NODES[f].ring);
        }
        if (NODES[i].ring == 0) {
            try std.testing.expectEqual(@as(usize, 0), fs.len); // the hub, and it is always yours
        } else if (NODES[i].key) {
            try std.testing.expectEqual(@as(usize, 2), fs.len); // both strands climb to it
        } else {
            try std.testing.expectEqual(@as(usize, 1), fs.len);
        }
    }
}

test "EVERY NODE IS REACHABLE from a standing start, given souls" {
    var t = Tree{};
    var got: usize = 0;
    var progress = true;
    while (progress) {
        progress = false;
        for (0..N) |i| {
            if (t.taken[i]) continue;
            if (t.take(i, RICH) == null) continue;
            got += 1;
            progress = true;
        }
    }
    try std.testing.expectEqual(N, got); // nothing is walled off behind a path that does not exist
}

test "TAKING A NODE IS THE LEVEL — one press, and nothing is taken twice" {
    var t = Tree{};
    try std.testing.expectEqual(@as(u32, 1), t.level());
    try std.testing.expect(t.take(0, RICH) != null);
    try std.testing.expectEqual(@as(u32, 2), t.level()); // the node IS the level: no pool in between
    try std.testing.expectEqual(@as(u32, 1), t.spent());
    try std.testing.expect(t.take(0, RICH) == null); // already yours
    try std.testing.expectEqual(@as(u32, 1), t.spent());
}

test "IT IS PAID FOR IN SOULS, and one short buys nothing" {
    var t = Tree{};
    const c = t.cost();
    try std.testing.expect(t.locked(0, c - 1) != null); // …and it says so rather than refusing in silence
    // **AND THE PREDICATE AND THE SENTENCE MAY NEVER DISAGREE** — `canTake` is what the board is drawn from
    // and `locked` is what the one node under the cursor says, so a node drawn open that refuses a press (or
    // the reverse) is the page and the rule contradicting each other on screen.
    for (0..N) |i| {
        for ([_]u32{ 0, 100, 359, 360, 1000, RICH }) |purse| {
            try std.testing.expectEqual(t.canTake(i, purse), t.locked(i, purse) == null);
        }
    }
    try std.testing.expect(t.take(0, c - 1) == null);
    try std.testing.expectEqual(@as(u32, 0), t.spent()); // nothing moved
    try std.testing.expectEqual(c, t.take(0, c).?); // exactly the price is enough, and it hands back what it took
}

test "…and every node after it costs more than the one before" {
    var t = Tree{};
    var last: u32 = 0;
    for (0..N) |i| {
        const c = t.take(i, RICH).?;
        try std.testing.expect(c > last);
        last = c;
    }
    try std.testing.expectEqual(@as(u32, N + 1), t.level());
}

test "THE TREE IS THE CEILING — nothing left to buy however many souls he is carrying" {
    var t = Tree{};
    for (0..N) |i| _ = t.take(i, RICH).?;
    try std.testing.expect(t.full());
    try std.testing.expectEqual(@as(u32, N), t.spent());
    for (0..N) |i| try std.testing.expect(t.take(i, RICH) == null);
}

test "EVERY ATTRIBUTE PAST THE STARTING SHEET CAME OFF A NODE" {
    var t = Tree{};
    for (0..N) |i| _ = t.take(i, 1_000_000);
    const s = t.bonus().sheet();
    // THE WHOLE TREE TAKEN, counted off the table rather than transcribed — a node retuned or moved must
    // not need this test edited, and a hand-written figure here is a second copy of `NODES` to keep in step.
    var want = [_]u32{0} ** stats.NA;
    for (NODES) |n| switch (n.grant) {
        .attr => |x| want[@intFromEnum(x.a)] += x.n,
        else => {},
    };
    for (0..stats.NA) |i| {
        const a: stats.Attr = @enumFromInt(i);
        try std.testing.expectEqual(@as(u8, @intCast(stats.START + want[i])), s.at(a));
        // …AND NO ATTRIBUTE IS LEFT OUT OF THE TREE ENTIRELY: a row nothing can raise is a dead row.
        try std.testing.expect(want[i] > 0);
    }
    try std.testing.expect(s.hp() > (stats.Sheet{}).hp());
}

test "an EMPTY tree is worth exactly nothing — every multiplier is 1 and every sum is 0" {
    const b = (Tree{}).bonus();
    try std.testing.expectApproxEqAbs(@as(f32, 1), b.poison, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), b.rollStam, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), b.spellCost, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), b.spellDmg, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b.guard, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b.iframe, 1e-6);
    for (0..combat.NELEM) |e| try std.testing.expectApproxEqAbs(@as(f32, 0), b.res.raw(@enumFromInt(e)), 1e-6);
    const s = b.sheet();
    for (0..stats.NA) |i| try std.testing.expectEqual(stats.START, s.at(@enumFromInt(i)));
}

test "the guard perk cannot hand a shield a hundred percent" {
    var t = Tree{};
    for (0..N) |i| _ = t.take(i, 1_000_000);
    try std.testing.expect(combat.GUARD_NEGATE + t.bonus().guard < 1.0);
}

test "every node has a name and a legible grant, and A NAME IS A PROMISE ABOUT THE GRANT" {
    // Two nodes MAY share a name — PoE's own tree repeats its small passives, and this one repeats a stat
    // twice up an arm on purpose. What they may not do is share a name and hand over different things: the
    // panel names the node and then says what it gives, and those two lines have to agree everywhere.
    for (NODES, 0..) |n, i| {
        try std.testing.expect(n.name.len > 0);
        try std.testing.expect(grantSays(n.grant).len > 0);
        for (NODES[i + 1 ..]) |m| {
            if (!std.mem.eql(u8, n.name, m.name)) continue;
            try std.testing.expect(std.meta.eql(n.grant, m.grant));
        }
    }
}

test "THE WALK IS GEOMETRIC: pressing a direction lands on something in that direction" {
    // From the wizard's own tip, DOWN has to come back down the wheel and never leave it.
    const key = armFirst(.wizard) + PER_ARM - 1;
    const back = step(key, 0, 1);
    try std.testing.expect(back != key);
    try std.testing.expect(unitPos(back).y > unitPos(key).y);
    // …and off the end of a spoke there is nothing further out, so the cursor stays where it is.
    try std.testing.expectEqual(key, step(key, 0, -1));
}

// THE MISSING PIN, and the reason the bug lived: the tests below check that the walk GOES somewhere and
// that it reaches everything, and the old scoring satisfied both while sending you 75° off your own thumb.
test "IT OPENS PANNABLE, and the zoom only ever buys MORE slide" {
    var w = Wheel{};
    // ZOOMED ALL THE WAY OUT IT STILL SLIDES (owner: "so it starts pannable"). The framing is a square on the
    // HUB now, not a fit of the bounding box, so there genuinely is wheel outside the panel from frame one.
    try std.testing.expect(w.panLimit() >= PAN_FLOOR - 1e-6);
    for (0..600) |_| w.panBy(.{ .x = 1, .y = 1 }, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(PAN_FLOOR, w.pan.x, 1e-4);
    try std.testing.expectApproxEqAbs(PAN_FLOOR, w.pan.y, 1e-4);
    // …but never so far that the wheel leaves its own panel: the slide stays well inside the square.
    try std.testing.expect(w.panLimit() < VIEW_R);
    // Zoomed IN it slides FURTHER, and stops at the edge of what is off screen rather than running away.
    w.zoomBy(1, 10.0);
    try std.testing.expectApproxEqAbs(ZOOM_MAX, w.zoom, 1e-5);
    try std.testing.expect(w.panLimit() > PAN_FLOOR);
    for (0..600) |_| w.panBy(.{ .x = 1, .y = -1 }, 1.0 / 60.0);
    try std.testing.expect(w.pan.x > PAN_FLOOR and w.pan.x <= w.panLimit() + 1e-5);
    try std.testing.expect(w.pan.y < -PAN_FLOOR and w.pan.y >= -w.panLimit() - 1e-5);
    // …and ZOOMING BACK OUT walks it in with it, down to the floor rather than past it.
    w.zoomBy(-1, 10.0);
    try std.testing.expectApproxEqAbs(ZOOM_MIN, w.zoom, 1e-5);
    try std.testing.expectApproxEqAbs(PAN_FLOOR, w.pan.x, 1e-4);
    try std.testing.expectApproxEqAbs(-PAN_FLOOR, w.pan.y, 1e-4);
}

test "THE MIDDLE IS THE MIDDLE — the hub sits dead centre of the panel on the frame it opens" {
    // THE COMPLAINT, as arithmetic (owner: "square with central node in center … not bottom heavy"). Fitted to
    // the bounding box the framing centred on a shape whose own centre is nowhere near the hub — three arms at
    // 120° reach four rings UP and two DOWN — so the one spot the whole page is described from opened well below
    // the middle. Now: the square is on the hub, and the hub is the centre of the box whatever shape the box is.
    const wh = Wheel{};
    for ([_][4]i32{ .{ 0, 0, 800, 600 }, .{ 40, 20, 600, 800 }, .{ -30, 90, 512, 512 } }) |b| {
        const l = layout(wh, b[0], b[1], b[2], b[3]);
        const mid = place(l, HUB);
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(b[0])) + @as(f32, @floatFromInt(b[2])) * 0.5, mid.x, 1e-3);
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(b[1])) + @as(f32, @floatFromInt(b[3])) * 0.5, mid.y, 1e-3);
        // …and it IS square: one unit of world is one unit of screen either way, off the SHORT axis, so the
        // square fits whichever way up the box is.
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@min(b[2], b[3]))) / (2.0 * VIEW_R), l.unit, 1e-3);
    }
    // …and nothing DRAWN is outside the square, which is what makes `VIEW_R` the right radius rather than a
    // number that happens to look right: the keystone's own halo is the outermost thing on the page.
    for (0..N) |i| {
        const p = unitPos(i);
        try std.testing.expect(std.math.hypot(p.x, p.y) + KEY_R * HALO_K <= VIEW_R + 1e-4);
    }
}

/// THE FOUR THE CROSS AND THE KEYS HAVE, which is what the reachability pins below are about: a STICK hands
/// `step` its own bearing (`menu.stickPush`), so the tests that matter for it are the bearing ones further down.
const CARDINALS = [_][2]f32{ .{ 0, -1 }, .{ 0, 1 }, .{ -1, 0 }, .{ 1, 0 } };

test "THE WALK GOES WHERE YOU PUSHED — every step from every spot lands inside the wedge" {
    for (0..SPOTS) |from| {
        for (CARDINALS) |d| {
            const to = step(from, d[0], d[1]);
            if (to == from) continue; // nothing that way at all is a legal answer
            const a = unitPos(from);
            const b = unitPos(to);
            const ax = b.x - a.x;
            const ay = b.y - a.y;
            const cos = (ax * d[0] + ay * d[1]) / std.math.hypot(ax, ay);
            try std.testing.expect(cos >= STEP_CONE - 1e-5);
        }
    }
}

test "…and from the MIDDLE each arm is under the thumb that points at it" {
    // The three spokes run UP, down-LEFT and down-RIGHT (`armAngle`), so those three pushes have to find
    // them — this is the first thing anybody does on the page and the first thing they would notice broken.
    try std.testing.expectEqual(Arm.wizard, NODES[step(HUB, 0, -1)].arm);
    try std.testing.expectEqual(Arm.warrior, NODES[step(HUB, -1, 0)].arm);
    try std.testing.expectEqual(Arm.rogue, NODES[step(HUB, 1, 0)].arm);
    // …and each lands on the FIRST ring, not somewhere out on the spoke.
    for ([_][2]f32{ .{ 0, -1 }, .{ -1, 0 }, .{ 1, 0 } }) |d| {
        try std.testing.expectEqual(@as(u8, 0), NODES[step(HUB, d[0], d[1])].ring);
    }
}

test "POINT AT A NODE AND YOU GO TO THAT NODE — the stick's bearing IS the step" {
    // THE COMPLAINT, as arithmetic (owner: walking the tree with the stick "feels horrible"). The arms run out
    // at 0, 120 and 240 degrees, so from the middle the ring-0 nodes sit at ∓15, 105, 135, 225 and 255 — and
    // every outward step along the two lower arms runs down a bearing near 96 or 216. Snapped to four screen
    // axes and gated by a 32-degree dead cone (`menu.STICK_CONE`), the push aimed AT a node landed in the cone
    // and did nothing on two arms out of three. `stickPush`'s `radial` hands the bearing over instead, so:
    //   1. from the MIDDLE, a push aimed at any ring-0 node reaches THAT node and not its neighbour…
    for (0..N) |i| {
        if (NODES[i].ring != 0) continue;
        const p = unitPos(i);
        try std.testing.expectEqual(i, step(HUB, p.x, p.y));
    }
    //   2. …and from any node, a push aimed down the LINK THE PAGE DRAWS reaches what it feeds. That is the
    //      whole of climbing an arm, on every strand and into both ways in at each capstone (`feeders`).
    for (0..N) |i| {
        var buf: [2]usize = undefined;
        for (feeders(i, &buf)) |f| {
            const a = unitPos(f);
            const b = unitPos(i);
            try std.testing.expectEqual(i, step(f, b.x - a.x, b.y - a.y));
        }
    }
    //   3. …and it is not required to arrive normalised: a raw node-minus-node delta is a bearing, and its own
    //      LENGTH must not decide how wide the wedge is.
    const up = unitPos(14); // wizard ring 0, straight up off the hub
    try std.testing.expectEqual(step(HUB, up.x, up.y), step(HUB, up.x * 40.0, up.y * 40.0));
    // …and a push of nothing at all moves nothing, rather than dividing by it.
    try std.testing.expectEqual(HUB, step(HUB, 0, 0));
    try std.testing.expectEqual(HUB, step(HUB, 1e-9, -1e-9));
}

test "AND A ROUGH PUSH IS ENOUGH — a thumb within 20 degrees of an arm finds that arm" {
    // A player does not aim to the degree; what he does is shove the thumb at the branch he wants. Each arm's
    // own axis and twenty degrees either side of it, which is the width of a shove — a bearing that reached the
    // WRONG arm would be the old failure back in a new shape.
    for (0..NARM) |a| {
        const arm: Arm = @enumFromInt(a);
        for ([_]f32{ -20.0, -8.0, 0.0, 8.0, 20.0 }) |off| {
            const ang = armAngle(arm) + mathx.radians(off);
            const to = step(HUB, mathx.sinf(ang), -mathx.cosf(ang));
            try std.testing.expect(to < N);
            try std.testing.expectEqual(arm, NODES[to].arm);
            try std.testing.expectEqual(@as(u8, 0), NODES[to].ring); // …and the near end of it, never the tip
        }
    }
}

test "NO NODE IS UNREACHABLE — four directions get you from any one of them to all twenty-one" {
    // A wheel is not a grid, and a node the cursor cannot be walked onto is a node nobody can take. Flooded
    // from every start, because a walk that only works from the middle is a walk that strands the tips.
    for (0..SPOTS) |from| {
        var seen = [_]bool{false} ** SPOTS;
        var stack: [SPOTS]usize = undefined;
        var top: usize = 1;
        stack[0] = from;
        seen[from] = true;
        var found: usize = 1;
        while (top > 0) {
            top -= 1;
            const at = stack[top];
            for (CARDINALS) |d| {
                const next = step(at, d[0], d[1]);
                if (seen[next]) continue;
                seen[next] = true;
                found += 1;
                stack[top] = next;
                top += 1;
            }
        }
        try std.testing.expectEqual(SPOTS, found);
    }
}

test "the wheel's geometry cannot collide two nodes, and every node hangs off its own arm" {
    for (0..N) |i| {
        const a = unitPos(i);
        try std.testing.expect(radiusOf(NODES[i]) >= 1.0); // nothing sits on the hub
        for (i + 1..N) |j| {
            const b = unitPos(j);
            const d = std.math.hypot(a.x - b.x, a.y - b.y);
            try std.testing.expect(d > 0.30);
        }
        // …and it hangs off its OWN arm's spine and nobody else's. The spine is the only line drawn now, so
        // a node that strayed past halfway to the neighbouring arm would read as belonging to that one.
        // A BRANCH NODE LEANS OFF ITS BRANCH'S bearing, never off its arm's — the split is the whole point.
        const n = NODES[i];
        const own = if (n.branch) |b| branchAngle(b) else armAngle(n.arm);
        const off = @abs(mathx.wrapPi(angleOf(n) - own));
        try std.testing.expect(off <= (if (n.branch == null) 1e-5 else spreadAt(n.ring)) + 1e-5);
        // …and it never strays past its arm's own half-lane, or two arms share a node.
        const fromArm = @abs(mathx.wrapPi(angleOf(n) - armAngle(n.arm)));
        try std.testing.expect(fromArm < std.math.tau / 6.0);
        try std.testing.expect(off < std.math.tau / @as(f32, NARM) * 0.5);
    }
}


test "SUSTAIN IS PRICED AGAINST THE FLASK, WHICH IS THE ONLY OTHER HEALING IN THE GAME" {
    // **THE BUG WAS A NUMBER WITH NO ANCHOR** (owner: HP on hit nodes are super OP; HP on death nodes are too
    // strong too). A flat "+4 HP a hit" reads as small next to a damage number; against the BAR it is enormous,
    // because the red bar is 70 at the start and TWO crimson charges are every point of healing a man carries
    // out of a bonfire. So the rule is written down here in the unit that matters: how many blows, and how many
    // bodies, one flask charge is worth.
    const bar = stats.hpFor(stats.START);
    const charge = bar * combat.FLASK_HP_FRAC;
    const budget = charge * @as(f32, @floatFromInt(combat.FLASK_CRIMSON));

    var tree = Tree{};
    for (&tree.taken) |*t| t.* = true; // every node, which is the ceiling nobody actually reaches
    const all = tree.bonus();
    const hitsPerCharge = charge / all.leech;
    const killsPerCharge = charge / all.onKill;
    std.debug.print(
        "\n  sustain: bar {d:.0}, flask charge {d:.0} ({d:.0} HP between fires) | leech {d:.1}/hit = {d:.0} blows a charge, onKill {d:.1} = {d:.1} bodies\n",
        .{ bar, charge, budget, all.leech, hitsPerCharge, all.onKill, killsPerCharge },
    );

    // **A BLOW MAY NOT BE A SIP.** At the old 5.5 this was six blows a charge — unlimited healing that did not
    // make the flask weak, it retired it. A dozen at the very least, with every node in the tree taken.
    try std.testing.expect(hitsPerCharge >= 12.0);
    // …AND A BODY IS NOT A FLASK EITHER. The old 20 a kill made a six-body fight worth nearly twice the whole
    // between-bonfires budget, off one fight.
    try std.testing.expect(killsPerCharge >= 4.0);
    const sixBodies = all.onKill * 6.0;
    try std.testing.expect(sixBodies < budget); // a fight pays out; it does not out-earn the flask itself
    // …and the RING is still the bigger dial for one hit, because it is the one that charges health to be it
    // (`item.leech_signet`: 2.0 and a permanent 6% of the bar). Points buy the trickle, health buys the size.
    try std.testing.expect(all.leech <= 2.0);
    // Both still WORTH taking, or the fix is a deletion wearing a retune's clothes.
    try std.testing.expect(all.leech > 0.5 and all.onKill >= 4.0);
}
