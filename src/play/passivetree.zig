const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const stats = @import("stats.zig");
const combat = @import("combat.zig");
const hud = @import("../ui/hud.zig");
const uiart = @import("../ui/uiart.zig");


const rgba = mathx.rgba;

/// NEVER NAMED ON SCREEN (owner's call) — no caption, no blurb, no arm in a lock message. The colour and
/// the direction carry which one you are on.
pub const Arm = enum {
    warrior,
    rogue,
    wizard,

    pub fn ink(a: Arm) rl.Color {
        return switch (a) {
            .warrior => rgba(196, 104, 84, 255),
            .rogue => rgba(132, 184, 112, 255),
            .wizard => rgba(120, 154, 214, 255),
        };
    }

    pub fn stat(a: Arm) stats.Attr {
        return switch (a) {
            .warrior => .strength,
            .rogue => .dexterity,
            .wizard => .intelligence,
        };
    }
};

pub const NARM = @typeInfo(Arm).@"enum".fields.len;

/// **TWO BRANCHES PER ARM** (owner: 2 branches per class, bespoke ideas and stat boosts alike). Each arm
/// opens on its class node and radiates into two SEPARATE climbs, each with its OWN keystone. **IN ARM ORDER,
/// TWO AT A TIME** — a comptime walk pins it, so `Branch.arm` is arithmetic and never a hand-kept table.
pub const Branch = enum {
    warrior_life,
    warrior_berserk,
    rogue_evade,
    rogue_ranged,
    wizard_well,
    wizard_cast,

    pub fn arm(b: Branch) Arm {
        return @enumFromInt(@intFromEnum(b) / 2);
    }
    pub fn lane(b: Branch) usize {
        return @intFromEnum(b) % 2;
    }
};

pub const NBRANCH = @typeInfo(Branch).@"enum".fields.len;

/// A bridge in a seam is reachable from EITHER side and opens the other, so a warrior buys ACROSS instead of
/// paying for the rogue's first four rings again. The arms sit at DECREASING angle in enum order
/// (`armAngle`), so the seam is a NEGATIVE sixth of a turn off `from`, and the branch facing it is `from`'s
/// LANE 0 and `to`'s LANE 1.
pub const Seam = enum {
    warrior_rogue,
    rogue_wizard,
    wizard_warrior,

    pub fn from(s: Seam) Arm {
        return @enumFromInt(@intFromEnum(s));
    }
    pub fn to(s: Seam) Arm {
        return @enumFromInt((@intFromEnum(s) + 1) % NARM);
    }
};

pub const NSEAM = @typeInfo(Seam).@"enum".fields.len;

/// Both are rings where a branch is at least two slots wide, so a slot genuinely faces the seam. Ring 3 is
/// the cheap crossing, ring 5 the deep one — a LADDER, not two of the same thing.
const BRIDGE_RINGS = [_]u8{ 3, 5 };

pub const PER_SEAM: usize = BRIDGE_RINGS.len;
pub const NBRIDGE: usize = NSEAM * PER_SEAM;

/// The ONE table the wiring, the wheel, the feeder buffer and the comptime walk are all solved from.
const BRANCH_RINGS = [_]u8{ 1, 2, 3, 3, 2, 1 };

/// Off the table, never a number beside it: a buffer one short drops a parent in silence, which looks exactly
/// like a rung nobody linked. **PLUS ONE FOR THE BRIDGE** — an anchor keeps its in-arm parents and gains the
/// seam's edge on top.
pub const MAX_FEED: usize = blk: {
    var w: usize = 1;
    for (BRANCH_RINGS) |s| w = @max(w, s);
    break :blk w + 1;
};

pub const PER_BRANCH: usize = blk: {
    var n: usize = 0;
    for (BRANCH_RINGS) |s| n += s;
    break :blk n;
};
pub const PER_ARM: usize = 1 + PER_BRANCH * 2;

/// The bridges are indexed AFTER the arms' block, so adding a seam renumbers nothing — including a save's bit
/// run (`save.readBits`: a short run is legal, so an old file loads its new tail unspent).
pub const NTREE: usize = NARM * PER_ARM;
pub const N: usize = NTREE + NBRIDGE;
pub const RINGS: u8 = @intCast(1 + BRANCH_RINGS.len);

pub fn armFirst(a: Arm) usize {
    return @intFromEnum(a) * PER_ARM;
}
pub fn branchFirst(b: Branch) usize {
    return armFirst(b.arm()) + 1 + b.lane() * PER_BRANCH;
}
pub fn bridgeFirst(s: Seam) usize {
    return NTREE + @intFromEnum(s) * PER_SEAM;
}

/// The first index of the ring `BRANCH_RINGS[br]` describes, inside its own branch.
fn ringFirst(b: Branch, br: usize) usize {
    var at = branchFirst(b);
    for (0..br) |r| at += BRANCH_RINGS[r];
    return at;
}

/// The outermost slot on each side, SOLVED and never listed: on `from`'s lane-0 branch that is SLOT 0 and on
/// `to`'s lane-1 branch the LAST slot. A table of pairs goes stale the first time a ring changes width.
pub fn bridgeAnchors(s: Seam, ring: u8) [2]usize {
    const br: usize = ring - 1;
    const wide = BRANCH_RINGS[br];
    const near: Branch = @enumFromInt(@as(usize, @intFromEnum(s.from())) * 2);
    const far: Branch = @enumFromInt(@as(usize, @intFromEnum(s.to())) * 2 + 1);
    return .{ ringFirst(near, br), ringFirst(far, br) + wide - 1 };
}

/// **A RUNG IS FED BY WHATEVER IT OVERLAPS ONE RING IN.** Each ring cuts the branch's width into as many
/// equal intervals as it has slots and an edge exists where two intervals meet — ONE rule for every pairing
/// of widths, so no rung is a dead end whatever `BRANCH_RINGS` becomes.
fn overlaps(p: usize, wp: usize, s: usize, wc: usize) bool {
    return p * wc < (s + 1) * wp and s * wp < (p + 1) * wc;
}

/// **A BRIDGE'S EDGE RUNS BOTH WAYS.** `reached` asks whether any FEEDER is taken, so an edge on one end only
/// is a crossing you pay for and cannot walk. Every anchor keeps its in-arm parents AND names the bridge.
fn bridgeOn(i: usize, out: *[MAX_FEED]usize, k: usize) usize {
    var n = k;
    for (0..NSEAM) |si| {
        const s: Seam = @enumFromInt(si);
        for (BRIDGE_RINGS, 0..) |ring, bi| {
            const anchors = bridgeAnchors(s, ring);
            if (anchors[0] != i and anchors[1] != i) continue;
            out[n] = bridgeFirst(s) + bi;
            n += 1;
        }
    }
    return n;
}

pub fn feeders(i: usize, out: *[MAX_FEED]usize) []const usize {
    const n = NODES[i];
    if (n.seam) |s| {
        const a = bridgeAnchors(s, n.ring);
        out[0] = a[0];
        out[1] = a[1];
        return out[0..2];
    }
    if (n.ring == 0) return out[0..0];
    const br = n.ring - 1;
    const b = n.branch.?;
    if (br == 0) {
        out[0] = armFirst(b.arm());
        return out[0..bridgeOn(i, out, 1)];
    }
    const base = branchFirst(b);
    var at: usize = 0;
    for (0..br - 1) |r| at += BRANCH_RINGS[r];
    const wp: usize = BRANCH_RINGS[br - 1];
    const wc: usize = BRANCH_RINGS[br];
    var k: usize = 0;
    for (0..wp) |p| {
        if (!overlaps(p, wp, n.slot, wc)) continue;
        out[k] = base + at + p;
        k += 1;
    }
    return out[0..bridgeOn(i, out, k)];
}

pub const Grant = union(enum) {
    attr: struct { a: stats.Attr, n: u8 },
    res: combat.Resists,
    guard: f32,
    iframe: f32,
    poison: f32,
    rollStam: f32,
    spellCost: f32,
    spellDmg: f32,

    armour: f32,
    hpRegen: f32,
    leech: f32,
    poiseMax: f32,
    flaskHeal: f32,

    sacrifice: struct { hpFrac: f32, dmg: f32 },
    cull: f32,
    onKill: f32,
    strike: f32,

    moveSpeed: f32,
    stamRegen: f32,
    stamMax: f32,
    bowDmg: f32,
    thrownDmg: f32,

    fpRegen: f32,
    fpMax: f32,
    castSpeed: f32,
    boltCloud,
};

/// **A STAT-UP RIDING AN IDEA** (owner: at least half the nodes carry one). It may only ride a grant that is
/// not itself a stat-up: `+2 Strength` wearing a `+1 Strength` rider is one number written as two, and the
/// comptime walk refuses it.
pub const Bump = struct { a: stats.Attr, n: u8 };

pub const Node = struct {
    arm: Arm,
    branch: ?Branch = null,
    /// Set on a BRIDGE and on nothing else. `arm` is then the seam's `from` side, which is only what the node
    /// is filed under — a bridge is drawn in both arms' inks and counted in neither's `spentIn`.
    seam: ?Seam = null,
    ring: u8,
    slot: u8 = 0,
    name: [:0]const u8,
    grant: Grant,
    bump: ?Bump = null,
    key: bool = false,
};

fn rides(a: stats.Attr, n: u8) ?Bump {
    return .{ .a = a, .n = n };
}

fn attr(a: stats.Attr, n: u8) Grant {
    return .{ .attr = .{ .a = a, .n = n } };
}

fn classNode(a: Arm, name: [:0]const u8) Node {
    return .{ .arm = a, .ring = 0, .name = name, .grant = attr(a.stat(), 3) };
}

/// Grant is one stat, rider the other, so no new `Grant` arm is needed. `near` is the `from` arm's stat and
/// `far` the `to` arm's, in that order: the panel prints the grant first.
fn bridgeNode(s: Seam, ring: u8, name: [:0]const u8, near: stats.Attr, far: stats.Attr, n: u8) Node {
    return .{ .arm = s.from(), .seam = s, .ring = ring, .name = name, .grant = attr(near, n), .bump = rides(far, n) };
}

/// IN ARM ORDER — class node, first branch, second branch, each in ring/slot order. A comptime walk pins it,
/// so a node in the wrong place is a compile error.
pub const NODES = [N]Node{
    classNode(.warrior, "Iron Thews"),

    .{ .arm = .warrior, .branch = .warrior_life, .ring = 1, .name = "Warrior's Blood", .grant = attr(.vitality, 2) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 2, .slot = 0, .name = "Thick Hide", .grant = .{ .armour = 10.0 }, .bump = rides(.vitality, 1) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 2, .slot = 1, .name = "Slow Mending", .grant = .{ .hpRegen = 0.6 }, .bump = rides(.vitality, 1) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 3, .slot = 0, .name = "Boiled Leather", .grant = .{ .armour = 8.0 }, .bump = rides(.strength, 1) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 3, .slot = 1, .name = "Stubborn Flesh", .grant = attr(.vitality, 3) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 3, .slot = 2, .name = "Scar Tissue", .grant = .{ .hpRegen = 0.5 }, .bump = rides(.vitality, 1) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 4, .slot = 0, .name = "Stalwart", .grant = .{ .guard = 0.05 } },
    // **THE ONE THING IN THE TREE THAT BUYS THE STAGGER BAR** (`hero.POISE_MAX`). It lengthens the bar, never
    // the refill — moved together the two dials read as one.
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 4, .slot = 1, .name = "Unshaken", .grant = .{ .poiseMax = 1.20 }, .bump = rides(.strength, 1) },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 4, .slot = 2, .name = "Bloodfeast", .grant = .{ .leech = 0.3 } },
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 5, .slot = 0, .name = "Ironbound", .grant = .{ .armour = 14.0 }, .bump = rides(.vitality, 2) },
    // THE FLASK ITSELF, which every sustain node in the file is priced against.
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 5, .slot = 1, .name = "Long Draught", .grant = .{ .flaskHeal = 1.25 }, .bump = rides(.vitality, 1) },
    // **THE KEYSTONE IS WORTH HALF THE BRANCH'S RING** (owner, third time: lifesteal nodes are STILL op).
    // Priced by the RATE, not the hit: a light chain lands ~1.5 blows/s, so 5.5 → 2.0 → 1.0 per blow. At 2.0
    // that was 3 HP/s forever, refilling the whole 70 HP bar every 23 s; at 1.0 it is 1.5/s and a flask charge
    // is ~32 blows. The RING stays the bigger dial for ONE hit (`item.leech_signet`, 2.0).
    .{ .arm = .warrior, .branch = .warrior_life, .ring = 6, .name = "Sanguine Pact", .grant = .{ .leech = 0.7 }, .key = true },

    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 1, .name = "Reaver", .grant = .{ .onKill = 1.0 } },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 2, .slot = 0, .name = "Blood Price", .grant = .{ .sacrifice = .{ .hpFrac = 0.08, .dmg = 1.10 } } },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 2, .slot = 1, .name = "Culling Blow", .grant = .{ .cull = 0.10 } },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 3, .slot = 0, .name = "Brute Force", .grant = attr(.strength, 3) },
    // `strike` rides the same `Bonus.dmg` the sacrifices multiply, and is priced small because it asks for
    // nothing back.
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 3, .slot = 1, .name = "Heavy Hands", .grant = .{ .strike = 1.08 }, .bump = rides(.strength, 1) },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 3, .slot = 2, .name = "Butcher's Eye", .grant = .{ .cull = 0.14 }, .bump = rides(.dexterity, 1) },
    // **A BODY IS WORTH A TENTH OF A FLASK CHARGE**: 20 → 6 → 3 a kill. At 6 a six-body fight handed back 18
    // HP of the 63 a man carries between bonfires — most of a flask nobody had to sip.
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 4, .slot = 0, .name = "Red Harvest", .grant = .{ .onKill = 2.0 } },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 4, .slot = 1, .name = "Reckless", .grant = .{ .sacrifice = .{ .hpFrac = 0.06, .dmg = 1.08 } } },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 4, .slot = 2, .name = "Executioner", .grant = .{ .cull = 0.18 }, .bump = rides(.strength, 1) },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 5, .slot = 0, .name = "Frenzy", .grant = .{ .strike = 1.10 }, .bump = rides(.endurance, 1) },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 5, .slot = 1, .name = "Blood Rush", .grant = .{ .stamRegen = 1.15 }, .bump = rides(.strength, 2) },
    .{ .arm = .warrior, .branch = .warrior_berserk, .ring = 6, .name = "Berserk", .grant = .{ .sacrifice = .{ .hpFrac = 0.20, .dmg = 1.34 } }, .key = true },

    classNode(.rogue, "Quick Hands"),

    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 1, .name = "Fleet", .grant = .{ .iframe = 0.05 } },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 2, .slot = 0, .name = "Second Wind", .grant = attr(.endurance, 2) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 2, .slot = 1, .name = "Light Step", .grant = .{ .moveSpeed = 1.06 } },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 3, .slot = 0, .name = "Sure Feet", .grant = attr(.dexterity, 3) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 3, .slot = 1, .name = "Tumbler", .grant = .{ .rollStam = 0.88 }, .bump = rides(.endurance, 1) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 3, .slot = 2, .name = "Long Legs", .grant = .{ .moveSpeed = 1.05 }, .bump = rides(.endurance, 1) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 4, .slot = 0, .name = "Wind at Heel", .grant = .{ .stamRegen = 1.25 } },
    // **THE POOL'S SIZE, WHICH IS NOT ITS REFILL** (`stamRegen` paces a flurry). ENDURANCE owns the bar
    // (`stats.staminaFor`), so this MULTIPLIES what the attribute yields rather than replacing it.
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 4, .slot = 1, .name = "Deep Lungs", .grant = .{ .stamMax = 1.18 }, .bump = rides(.endurance, 2) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 4, .slot = 2, .name = "Warded Blood", .grant = .{ .poison = 0.70 } },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 5, .slot = 0, .name = "Slip", .grant = .{ .iframe = 0.04 }, .bump = rides(.dexterity, 1) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 5, .slot = 1, .name = "Clean Blood", .grant = .{ .poison = 0.80 }, .bump = rides(.vitality, 1) },
    .{ .arm = .rogue, .branch = .rogue_evade, .ring = 6, .name = "Misty Step", .grant = .{ .rollStam = 0.65 }, .key = true },

    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 1, .name = "Keen Eye", .grant = .{ .bowDmg = 1.16 } },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 2, .slot = 0, .name = "Practised Arm", .grant = .{ .thrownDmg = 1.20 } },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 2, .slot = 1, .name = "Wayfinder", .grant = attr(.luck, 2) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 3, .slot = 0, .name = "Fletcher", .grant = .{ .bowDmg = 1.10 }, .bump = rides(.dexterity, 1) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 3, .slot = 1, .name = "Steady Hand", .grant = attr(.dexterity, 2) },
    // LUCK is the one attribute nothing else reads (`stats.inert`); the drop table's rare column is all it buys.
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 3, .slot = 2, .name = "Lucky Find", .grant = attr(.luck, 3) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 4, .slot = 0, .name = "Broadhead", .grant = .{ .bowDmg = 1.18 } },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 4, .slot = 1, .name = "Strong Draw", .grant = attr(.strength, 2) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 4, .slot = 2, .name = "Oiled Rags", .grant = .{ .thrownDmg = 1.18 }, .bump = rides(.dexterity, 1) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 5, .slot = 0, .name = "Marksman", .grant = .{ .bowDmg = 1.12 }, .bump = rides(.dexterity, 2) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 5, .slot = 1, .name = "Pot-Hunter", .grant = attr(.luck, 3) },
    .{ .arm = .rogue, .branch = .rogue_ranged, .ring = 6, .name = "Hail", .grant = .{ .thrownDmg = 1.55 }, .key = true },

    classNode(.wizard, "Lore"),

    .{ .arm = .wizard, .branch = .wizard_well, .ring = 1, .name = "Open Mind", .grant = attr(.mind, 2) },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 2, .slot = 0, .name = "Deep Well", .grant = .{ .fpMax = 1.15 } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 2, .slot = 1, .name = "Slow Tide", .grant = .{ .fpRegen = 0.9 } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 3, .slot = 0, .name = "Wider Mind", .grant = attr(.mind, 3) },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 3, .slot = 1, .name = "Runic Skin", .grant = .{ .res = combat.resists(.{ .fire = 10, .cold = 10 }) }, .bump = rides(.vitality, 1) },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 3, .slot = 2, .name = "Still Water", .grant = .{ .fpRegen = 0.7 }, .bump = rides(.mind, 1) },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 4, .slot = 0, .name = "Veil", .grant = .{ .res = combat.resists(.{ .chaos = 20, .lightning = 10 }) } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 4, .slot = 1, .name = "Warded", .grant = .{ .res = combat.resists(.{ .fire = 15, .cold = 15 }) } },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 4, .slot = 2, .name = "Brimming", .grant = .{ .fpMax = 1.12 }, .bump = rides(.mind, 2) },
    // **CHAOS IS WHAT POISON IS BILLED AS** (`combat.poisonPulse`) — this row wards the spore creatures as
    // well as the knight's gas.
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 5, .slot = 0, .name = "Sealed Mind", .grant = .{ .res = combat.resists(.{ .chaos = 15 }) }, .bump = rides(.intelligence, 1) },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 5, .slot = 1, .name = "Stormproof", .grant = .{ .res = combat.resists(.{ .lightning = 20 }) }, .bump = rides(.vitality, 1) },
    .{ .arm = .wizard, .branch = .wizard_well, .ring = 6, .name = "Wellspring", .grant = .{ .fpRegen = 2.4 }, .key = true },

    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 1, .name = "Attuned", .grant = .{ .spellCost = 0.80 } },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 2, .slot = 0, .name = "Quick Tongue", .grant = .{ .castSpeed = 1.18 } },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 2, .slot = 1, .name = "Arcana", .grant = .{ .spellDmg = 1.25 } },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 3, .slot = 0, .name = "Deeper Lore", .grant = attr(.intelligence, 2) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 3, .slot = 1, .name = "Glib", .grant = .{ .castSpeed = 1.10 }, .bump = rides(.intelligence, 1) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 3, .slot = 2, .name = "Sigil Craft", .grant = .{ .spellDmg = 1.14 }, .bump = rides(.mind, 1) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 4, .slot = 0, .name = "Inner Quiet", .grant = .{ .spellCost = 0.88 } },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 4, .slot = 1, .name = "Focused", .grant = attr(.mind, 3) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 4, .slot = 2, .name = "Runewright", .grant = .{ .spellDmg = 1.16 }, .bump = rides(.intelligence, 1) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 5, .slot = 0, .name = "Adept", .grant = attr(.intelligence, 3) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 5, .slot = 1, .name = "Sharp Tongue", .grant = .{ .castSpeed = 1.12 }, .bump = rides(.intelligence, 1) },
    .{ .arm = .wizard, .branch = .wizard_cast, .ring = 6, .name = "Chaos Bloom", .grant = .boltCloud, .key = true },

    // THE SEAMS, in `Seam` order and shallow-to-deep. The shallow crossing trades what an arm supports itself
    // with, the deep one trades its CLASS STAT (`Arm.stat`). No two bridges spend the same pair.
    bridgeNode(.warrior_rogue, 3, "Rough Luck", .vitality, .luck, 1),
    bridgeNode(.warrior_rogue, 5, "Duellist", .strength, .dexterity, 2),
    bridgeNode(.rogue_wizard, 3, "Long Breath", .endurance, .mind, 1),
    bridgeNode(.rogue_wizard, 5, "Spellblade", .dexterity, .intelligence, 2),
    bridgeNode(.wizard_warrior, 3, "Stone Mind", .mind, .vitality, 1),
    bridgeNode(.wizard_warrior, 5, "Battlemage", .intelligence, .strength, 2),
};

comptime {
    var i: usize = 0;
    for (0..NARM) |a| {
        const arm: Arm = @as(Arm, @enumFromInt(a));
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
    std.debug.assert(i == NTREE);
    for (0..NSEAM) |si| {
        const s: Seam = @as(Seam, @enumFromInt(si));
        std.debug.assert(s.from() != s.to());
        std.debug.assert(i == bridgeFirst(s));
        for (BRIDGE_RINGS) |ring| {
            const n = NODES[i];
            std.debug.assert(n.seam.? == s and n.branch == null and !n.key);
            std.debug.assert(n.ring == ring);
            // Two rungs wide, or "the outermost slot" is the only slot and the crossing hangs off the centre.
            std.debug.assert(BRANCH_RINGS[ring - 1] >= 2);
            const a = bridgeAnchors(s, ring);
            std.debug.assert(NODES[a[0]].arm == s.from() and NODES[a[1]].arm == s.to());
            std.debug.assert(NODES[a[0]].ring == ring and NODES[a[1]].ring == ring);
            std.debug.assert(NODES[a[0]].slot == 0 and NODES[a[1]].slot == BRANCH_RINGS[ring - 1] - 1);
            std.debug.assert(NODES[a[0]].branch.?.lane() == 0 and NODES[a[1]].branch.?.lane() == 1);
            i += 1;
        }
    }
    std.debug.assert(i == N);
    var keys: usize = 0;
    for (NODES) |n| {
        if (n.key) keys += 1;
    }
    std.debug.assert(keys == NBRANCH);

    // **AT LEAST HALF THE BOARD PAYS A POINT** (owner's call), asserted so the rule survives the next node.
    // A rider may not double its grant on the SAME attribute; two DIFFERENT ones are a bridge's whole point.
    var carry: usize = 0;
    for (NODES) |n| {
        const pureOn: ?stats.Attr = switch (n.grant) {
            .attr => |x| x.a,
            else => null,
        };
        if (n.bump) |b| {
            if (b.n == 0) @compileError("passivetree: " ++ n.name ++ " rides a stat-up worth nothing");
            if (pureOn) |a| {
                if (a == b.a) @compileError("passivetree: " ++ n.name ++ " rides its own attribute twice");
            }
        }
        if (pureOn != null or n.bump != null) carry += 1;
    }
    if (carry * 2 < N) @compileError("passivetree: fewer than half the nodes carry a stat");
}

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
        .guard => |x| fmt("+{d:.0}% guard", .{x * 100.0}),
        .iframe => |x| fmt("+{d:.2}s roll invulnerability", .{x}),
        .poison => |x| fmt("-{d:.0}% poison buildup", .{(1.0 - x) * 100.0}),
        .rollStam => |x| fmt("-{d:.0}% roll stamina", .{(1.0 - x) * 100.0}),
        .spellCost => |x| fmt("-{d:.0}% FP per cast", .{(1.0 - x) * 100.0}),
        .spellDmg => |x| fmt("+{d:.0}% sorcery damage", .{(x - 1.0) * 100.0}),
        .armour => |x| fmt("+{d:.0} armour", .{x}),
        .hpRegen => |x| fmt("+{d:.1} HP a second", .{x}),
        .leech => |x| fmt("+{d:.1} HP per hit", .{x}),
        .poiseMax => |x| fmt("+{d:.0}% poise", .{(x - 1.0) * 100.0}),
        .flaskHeal => |x| fmt("+{d:.0}% crimson flask healing", .{(x - 1.0) * 100.0}),
        .sacrifice => |x| fmt("-{d:.0}% max HP, +{d:.0}% damage", .{ x.hpFrac * 100.0, (x.dmg - 1.0) * 100.0 }),
        .cull => |x| fmt("Kills anything under {d:.0}% HP", .{x * 100.0}),
        .onKill => |x| fmt("+{d:.0} HP per kill", .{x}),
        .strike => |x| fmt("+{d:.0}% damage", .{(x - 1.0) * 100.0}),
        .moveSpeed => |x| fmt("+{d:.0}% move speed", .{(x - 1.0) * 100.0}),
        .stamRegen => |x| fmt("+{d:.0}% stamina regen", .{(x - 1.0) * 100.0}),
        .stamMax => |x| fmt("+{d:.0}% stamina", .{(x - 1.0) * 100.0}),
        .bowDmg => |x| fmt("+{d:.0}% bow damage", .{(x - 1.0) * 100.0}),
        .thrownDmg => |x| fmt("+{d:.0}% thrown damage", .{(x - 1.0) * 100.0}),
        .fpRegen => |x| fmt("+{d:.1} FP a second", .{x}),
        .fpMax => |x| fmt("+{d:.0}% Focus", .{(x - 1.0) * 100.0}),
        .castSpeed => |x| fmt("+{d:.0}% cast speed", .{(x - 1.0) * 100.0}),
        .boltCloud => "Chaos Bolt leaves a cloud",
    };
}

/// Drawn UNDER the grant's line, never folded into it. THREE ASCII DOTS AND NOT AN ELLIPSIS: the Balthazar
/// atlas is ASCII-only and a `…` draws as tofu.
pub fn bumpSays(b: Bump) [:0]const u8 {
    return fmt("+{d} {s}", .{ b.n, stats.displayName(b.a) });
}

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
    poiseMax: f32 = 1,
    flaskHeal: f32 = 1,
    hpFrac: f32 = 0,
    dmg: f32 = 1,
    cull: f32 = 0,
    onKill: f32 = 0,

    moveSpeed: f32 = 1,
    stamRegen: f32 = 1,
    stamMax: f32 = 1,
    bowDmg: f32 = 1,
    thrownDmg: f32 = 1,

    fpRegen: f32 = 0,
    fpMax: f32 = 1,
    castSpeed: f32 = 1,
    boltCloud: bool = false,

    /// The starting sheet plus every attribute node taken, and the ONLY way an attribute here moves.
    /// `stats.Sheet.set` clamps, so a maxed attribute cannot be pushed past 99.
    pub fn sheet(self: Bonus) stats.Sheet {
        var s = stats.Sheet{};
        for (self.attrs, 0..) |n, i| {
            s.add(@enumFromInt(i), n);
        }
        return s;
    }
};

/// Off the level you are standing on. Quadratic, ER's shape, and MEASURED against what a body is worth: a
/// toad is 60, an archer 130, a brood mother 240. **THE FIRST NODE COSTS `costAt(1)`, WHICH IS 360** — never
/// `costAt(0)`: you stand on level 1 before you have spent anything.
pub fn costAt(level: u32) u32 {
    return 280 + 62 * level + 18 * level * level;
}

pub const Tree = struct {
    taken: [N]bool = [_]bool{false} ** N,

    /// TAKING A NODE IS THE LEVEL (owner's call) — no pool of points between the two. LEVEL IS COUNTED, never
    /// stored (`stats.Sheet.level`'s law): the nodes on the board plus one.
    pub fn spent(self: *const Tree) u32 {
        var n: u32 = 0;
        for (self.taken) |t| n += @intFromBool(t);
        return n;
    }

    pub fn level(self: *const Tree) u32 {
        return self.spent() + 1;
    }

    pub fn cost(self: *const Tree) u32 {
        return costAt(self.level());
    }

    pub fn reached(self: *const Tree, i: usize) bool {
        var buf: [MAX_FEED]usize = undefined;
        const fs = feeders(i, &buf);
        if (fs.len == 0) return true;
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

    pub fn full(self: *const Tree) bool {
        return self.spent() >= N;
    }

    pub fn canTake(self: *const Tree, i: usize, souls: u32) bool {
        return !self.taken[i] and self.reached(i) and souls >= self.cost();
    }

    pub fn locked(self: *const Tree, i: usize, souls: u32) ?[:0]const u8 {
        if (self.taken[i]) return "";
        if (!self.reached(i)) return "Locked.";
        const c = self.cost();
        if (souls < c) return fmt("Need {d} souls.", .{c});
        return null;
    }

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
                .armour => |x| b.armour += x,
                .hpRegen => |x| b.hpRegen += x,
                .leech => |x| b.leech += x,
                .poiseMax => |x| b.poiseMax *= x,
                .flaskHeal => |x| b.flaskHeal *= x,
                .sacrifice => |x| {
                    b.hpFrac += x.hpFrac;
                    b.dmg *= x.dmg;
                },
                .cull => |x| b.cull = mathx.maxF(b.cull, x),
                .onKill => |x| b.onKill += x,
                .strike => |x| b.dmg *= x,
                .moveSpeed => |x| b.moveSpeed *= x,
                .stamRegen => |x| b.stamRegen *= x,
                .stamMax => |x| b.stamMax *= x,
                .bowDmg => |x| b.bowDmg *= x,
                .thrownDmg => |x| b.thrownDmg *= x,
                .fpRegen => |x| b.fpRegen += x,
                .fpMax => |x| b.fpMax *= x,
                .castSpeed => |x| b.castSpeed *= x,
                .boltCloud => b.boltCloud = true,
            }
            // THE RIDER, after its own grant — one place, so a node cannot pay its point through the picture
            // and not through the sheet.
            if (NODES[i].bump) |x| b.attrs[@intFromEnum(x.a)] += x.n;
        }
        return b;
    }
};

// THE WHEEL. Positions are solved in UNITS about a centre — one ring apart — so the walk and the draw read
// the same geometry and a resized card cannot move a node out from under the cursor.

fn armAngle(a: Arm) f32 {
    return switch (a) {
        .wizard => 0,
        .rogue => std.math.tau / 3.0,
        .warrior => 2.0 * std.math.tau / 3.0,
    };
}

const BRANCH_SPLIT: f32 = 0.42;

fn branchAngle(b: Branch) f32 {
    const side: f32 = if (b.lane() == 0) -1.0 else 1.0;
    return armAngle(b.arm()) + side * BRANCH_SPLIT;
}

/// It WIDENS outward — a constant spread draws parallel rails, which is a ladder and not a branch. Solved
/// against `BRANCH_SPLIT`, never picked: the widest fan may not reach the lane's own half-width, or the two
/// branches of an arm cross.
fn spreadAt(ring: u8) f32 {
    return 0.130 + 0.032 * @as(f32, @floatFromInt(ring));
}

comptime {
    std.debug.assert(spreadAt(RINGS - 1) < BRANCH_SPLIT);
}

/// Halfway between `from` and `to`. The arms sit at DECREASING angle in enum order, so the next one round is
/// a third of a turn back and the seam is a sixth.
fn seamAngle(s: Seam) f32 {
    return armAngle(s.from()) - std.math.tau / 6.0;
}

comptime {
    // The seam has to clear the widest fan either lane can open, or a bridge sits on top of the rung it is
    // tied to. Half a turn's sixth is the room there is; the fan takes `BRANCH_SPLIT` plus its own spread.
    std.debug.assert(BRANCH_SPLIT + spreadAt(RINGS - 1) < std.math.tau / 6.0);
}

fn angleOf(n: Node) f32 {
    if (n.seam) |s| return seamAngle(s);
    const b = n.branch orelse return armAngle(n.arm);
    const slots = BRANCH_RINGS[n.ring - 1];
    if (slots == 1) return branchAngle(b);
    const t = @as(f32, @floatFromInt(n.slot)) / @as(f32, @floatFromInt(slots - 1));
    return branchAngle(b) + (t * 2.0 - 1.0) * spreadAt(n.ring);
}

fn radiusOf(n: Node) f32 {
    return @as(f32, @floatFromInt(n.ring)) + 1.0;
}

/// THE MIDDLE, as a cursor position. It is not a node and nothing is ever spent on it — but it IS where you
/// start, and a cursor that cannot rest on the one place the whole tree is described from is a cursor with a
/// hole in it. Indexed one past the last node, so every `NODES[i]` site is untouched.
pub const HUB: usize = N;
pub const SPOTS: usize = N + 1;

fn unitPos(i: usize) rl.Vector2 {
    if (i >= N) return .{ .x = 0, .y = 0 };
    const n = NODES[i];
    const a = angleOf(n);
    const r = radiusOf(n);
    return .{ .x = mathx.sinf(a) * r, .y = -mathx.cosf(a) * r };
}

const STEP_CONE: f32 = 0.5;

/// **THE PICK IS THE NODE NEAREST THE LINE YOU PUSHED, NOT THE NEAREST NODE INSIDE THE WEDGE.** On a lattice a
/// rung's children sit DIAGONALLY out while its siblings sit LEVEL, so a sibling is always the shorter hop and
/// a distance score landed on it every time. The PERPENDICULAR offset from the pushed ray decides; distance
/// ALONG it is only the tiebreak.
///
/// **THE WEIGHT IS BRACKETED AT BOTH ENDS, WHICH IS WHY IT IS SOLVED AND NOT PICKED.** Too small and pushing
/// UP from the warrior's class node aims within 3 degrees of the WIZARD's node two rings away, past the hub
/// one unit off the line — a middle you can leave and never re-enter, and a D-pad has only four bearings. Too
/// large and it degenerates to the distance walk. The cases bound it to (0.45, 0.86); tests pin both.
const STEP_ALONG: f32 = 0.65;

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
        const along = ax * fdx + ay * fdy;
        if (along / dist < STEP_CONE) continue;
        const s = @abs(ax * fdy - ay * fdx) + STEP_ALONG * along;
        if (s < score) {
            score = s;
            best = i;
        }
    }
    return best;
}

pub const ZOOM_MIN: f32 = 1.0;
pub const ZOOM_MAX: f32 = 3.2;
pub const ZOOM_RATE: f32 = 1.7;
pub const PAN_RATE: f32 = 3.4;
const PAN_SPAN: f32 = 6.0;
const PAN_FLOOR: f32 = 1.6;

pub const Wheel = struct {
    cursor: usize = HUB,
    zoom: f32 = ZOOM_MIN,
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
        self.clampPan();
    }

    pub fn panBy(self: *Wheel, v: rl.Vector2, dt: f32) void {
        if (v.x == 0 and v.y == 0) return;
        const k = PAN_RATE * dt / self.zoom;
        self.pan.x += v.x * k;
        self.pan.y += v.y * k;
        self.clampPan();
    }

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

const HUB_R: f32 = 0.26;

const KEY_R: f32 = 0.30;
/// Over an ordinary stat-up's 0.15 and under a keystone's, because a bridge is neither: bigger than the pip it
/// would otherwise be mistaken for, smaller than the thing a branch ends in.
const SEAM_R: f32 = 0.23;
const HALO_K: f32 = 2.1;

/// A SQUARE WINDOW ON THE HUB, and this is its half-extent in units (owner: "square with central node in
/// center, so it starts pannable, not bottom heavy").
const VIEW_R: f32 = @as(f32, @floatFromInt(RINGS)) + KEY_R * HALO_K;

fn layout(wh: Wheel, x: i32, y: i32, w: i32, h: i32) Lay {
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    const zoom = mathx.clampF(wh.zoom, ZOOM_MIN, ZOOM_MAX);
    const unit = @min(fw, fh) / (2.0 * VIEW_R) * zoom;
    const k = mathx.clampF((zoom - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN), 0, 1);
    const on = unitPos(@min(wh.cursor, HUB));
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
    if (NODES[i].seam != null) return l.unit * SEAM_R;
    return l.unit * (if (NODES[i].key) KEY_R else switch (NODES[i].grant) {
        .attr => @as(f32, 0.15),
        else => @as(f32, 0.21),
    });
}

/// **A BRIDGE IS DRAWN IN BOTH ARMS' INKS, HALF AND HALF** — it is the one node on the board that belongs to
/// two, and drawn in one arm's colour it reads as that arm having grown a rung out into open ground.
fn inkOf(i: usize) rl.Color {
    const n = NODES[i];
    const s = n.seam orelse return n.arm.ink();
    return mathx.lerpColor(s.from().ink(), s.to().ink(), 0.5);
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

pub fn draw(t: *const Tree, wh: Wheel, x: i32, y: i32, w: i32, h: i32, spendable: bool, souls: u32) void {
    rl.beginScissorMode(x, y, w, h);
    defer rl.endScissorMode();
    const l = layout(wh, x, y, w, h);
    const hub = rl.Vector2{ .x = l.cx, .y = l.cy };

    for (0..RINGS) |r| {
        rl.drawCircleLinesV(hub, l.unit * @as(f32, @floatFromInt(r + 1)), mathx.withAlpha(uiart.GILT_DIM, 26));
    }

    for (0..N) |i| {
        const n = NODES[i];
        const to = place(l, i);
        var buf: [MAX_FEED]usize = undefined;
        const fs = feeders(i, &buf);
        if (fs.len == 0) {
            rl.drawLineEx(hub, to, l.unit * (if (t.taken[i]) @as(f32, 0.055) else 0.038), mathx.withAlpha(n.arm.ink(), if (t.taken[i]) 225 else 130));
            continue;
        }
        for (fs) |f| {
            const walked = t.taken[i] and t.taken[f];
            const open = t.taken[f];
            // A SEAM'S EDGE TAKES THE COLOUR OF THE END IT IS COMING FROM, whichever end that is, so a
            // crossing reads as the neighbouring arm reaching in rather than as one arm owning both rails.
            const line = if (n.seam != null) inkOf(f) else if (NODES[f].seam != null) inkOf(f) else n.arm.ink();
            rl.drawLineEx(
                place(l, f),
                to,
                l.unit * (if (walked) @as(f32, 0.055) else if (open) @as(f32, 0.038) else @as(f32, 0.022)),
                mathx.withAlpha(line, if (walked) 225 else if (open) 130 else 44),
            );
        }
    }

    rl.drawCircleV(hub, l.unit * HUB_R, mathx.withAlpha(uiart.INK, 235));
    rl.drawCircleLinesV(hub, l.unit * HUB_R, mathx.withAlpha(uiart.GILT, 200));
    uiart.finial(hub.x, hub.y, l.unit * 0.11, uiart.GILT_BRIGHT);

    for (0..N) |i| {
        const n = NODES[i];
        const p = place(l, i);
        const r = radiusPx(l, i);
        const ink = inkOf(i);
        const open = spendable and t.canTake(i, souls);
        rl.drawCircleV(p, r + 2.0, mathx.withAlpha(uiart.INK, 210));
        if (t.taken[i]) {
            rl.drawCircleV(p, r, ink);
            rl.drawCircleV(p, r * 0.42, mathx.withAlpha(uiart.CATCH, 220));
        } else {
            rl.drawCircleV(p, r, mathx.withAlpha(uiart.STONE_DK, 235));
            rl.drawCircleLinesV(p, r, mathx.withAlpha(ink, if (open) 235 else 80));
        }
        // A BRIDGE WEARS A RING OF EACH SIDE, so which two arms it joins is legible without reading its name.
        if (n.seam) |s| {
            const a = mathx.u8f(if (t.taken[i]) 220.0 else if (open) 190.0 else 70.0);
            rl.drawCircleLinesV(p, r + 2.5, mathx.withAlpha(s.from().ink(), a));
            rl.drawCircleLinesV(p, r + 4.0, mathx.withAlpha(s.to().ink(), a));
        }
        if (open and !t.taken[i]) uiart.candle(@intFromFloat(p.x), @intFromFloat(p.y), r * HALO_K, 26);
        if (n.key) rl.drawCircleLinesV(p, r + 3.5, mathx.withAlpha(if (t.taken[i]) uiart.GILT_BRIGHT else uiart.GILT_DIM, 150));
    }

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

}


/// Sunk panel, `book.panel`'s dressing without book's layout types — this file cannot import that one.
fn well(x: i32, y: i32, w: i32, h: i32) void {
    uiart.well(x, y, w, h, 210);
    rl.drawRectangleLinesEx(uiart.rect(x, y, w, h), 1, mathx.withAlpha(uiart.GILT_DIM, 90));
}

pub fn readW(w: i32) i32 {
    return @min(@divTrunc(w * 30, 100), 430);
}

const GUT: i32 = 18;

pub fn wheelBox(x: i32, y: i32, w: i32, h: i32) [4]i32 {
    return .{ x, y, w - readW(w) - GUT, h };
}

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
    if (i == HUB) {
        hud.text("The Middle", ix, yy, hud.BODY, uiart.TEXT_TITLE);
        yy += hud.lineH(hud.BODY) + 6;
        _ = hud.prose(
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
    yy = hud.prose(grantSays(n.grant), ix, yy, iw, hud.SMALL, uiart.TEXT_VALUE);
    if (n.bump) |bp| yy = hud.prose(bumpSays(bp), ix, yy, iw, hud.SMALL, uiart.GOOD);
    yy += 8;

    if (t.taken[i]) {
        hud.text("TAKEN", ix, yy, hud.HINT, uiart.GOOD);
    } else if (!spendable) {
        hud.text("Bonfire only.", ix, yy, hud.HINT, uiart.TEXT_HINT);
    } else if (t.locked(i, souls)) |whyNot| {
        if (whyNot.len > 0) _ = hud.prose(whyNot, ix, yy, iw, hud.HINT, uiart.TEXT_HINT);
    }
}

var scratch: [8][160]u8 = undefined;
var scratchAt: usize = 0;

fn fmt(comptime f: []const u8, args: anytype) [:0]const u8 {
    scratchAt = (scratchAt + 1) % scratch.len;
    return std.fmt.bufPrintZ(&scratch[scratchAt], f, args) catch "?";
}

const RICH: u32 = 1_000_000;

test "EVERY GRANT IS ON THE BOARD, and an EMPTY bonus changes nothing" {
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

    const none = Bonus{};
    try std.testing.expectEqual(@as(f32, 0), none.guard + none.iframe + none.armour + none.hpRegen +
        none.leech + none.hpFrac + none.cull + none.onKill + none.fpRegen);
    inline for (.{ none.poison, none.rollStam, none.spellCost, none.spellDmg, none.dmg, none.moveSpeed, none.stamRegen, none.stamMax, none.bowDmg, none.thrownDmg, none.fpMax, none.castSpeed, none.poiseMax, none.flaskHeal }) |m| {
        try std.testing.expectEqual(@as(f32, 1), m);
    }
    try std.testing.expect(!none.boltCloud);
    try std.testing.expectEqual(stats.Sheet{}, none.sheet());

    var t = Tree{};
    for (0..N) |i| _ = t.take(i, RICH);
    const all = t.bonus();
    try std.testing.expect(all.guard > 0 and all.iframe > 0 and all.armour > 0 and all.hpRegen > 0);
    try std.testing.expect(all.leech > 0 and all.hpFrac > 0 and all.cull > 0 and all.onKill > 0 and all.fpRegen > 0);
    try std.testing.expect(all.rollStam < 1 and all.spellCost < 1 and all.poison < 1);
    try std.testing.expect(all.spellDmg > 1 and all.dmg > 1 and all.moveSpeed > 1 and all.stamRegen > 1);
    try std.testing.expect(all.bowDmg > 1 and all.thrownDmg > 1 and all.fpMax > 1 and all.castSpeed > 1);
    try std.testing.expect(all.poiseMax > 1 and all.stamMax > 1 and all.flaskHeal > 1);
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
        try std.testing.expect(t.locked(root, RICH) == null);
        try std.testing.expect(NODES[root].branch == null);
        for (0..2) |lane| {
            const b: Branch = @enumFromInt(ai * 2 + lane);
            try std.testing.expect(t.locked(branchFirst(b), RICH) != null);
        }
    }
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
    try std.testing.expect(t.take(root, RICH) != null);
    try std.testing.expect(t.locked(ev, RICH) == null);
    try std.testing.expect(t.locked(rg, RICH) == null);
    try std.testing.expect(t.locked(ev + 1, RICH) != null);
    try std.testing.expect(t.locked(rg + 1, RICH) != null);
    try std.testing.expect(t.take(ev, RICH) != null);
    try std.testing.expect(t.locked(ev + 1, RICH) == null);
    try std.testing.expect(t.locked(ev + 2, RICH) == null);
    try std.testing.expect(t.locked(ev + 3, RICH) != null);
    try std.testing.expect(t.locked(rg + 1, RICH) != null);
    try std.testing.expect(t.locked(branchFirst(.warrior_life), RICH) != null);
}

test "EVERY BRANCH HAS ITS OWN KEYSTONE, and EVERY line up the lattice climbs to it" {
    for (0..NBRANCH) |bi| {
        const b: Branch = @enumFromInt(bi);
        const base = branchFirst(b);
        const key = base + PER_BRANCH - 1;
        try std.testing.expect(NODES[key].key);
        try std.testing.expectEqual(b, NODES[key].branch.?);
        // ONE RUNG PER RING and no more — walked from the keystone DOWN through a feeder each time, which is
        // every distinct line through the branch rather than the two rails the shape used to have. The
        // shortest climb is `RINGS` presses whichever line it takes, and nothing off this branch is touched.
        for (0..MAX_FEED) |pick| {
            var t = Tree{};
            var line: [RINGS]usize = undefined;
            var at = key;
            var depth: usize = 0;
            while (true) {
                line[depth] = at;
                depth += 1;
                var buf: [MAX_FEED]usize = undefined;
                const all = feeders(at, &buf);
                // IN-ARM ONLY. A rung that anchors a bridge names it as a feeder too (`bridgeOn`), and this
                // walk is about the lines inside ONE branch — a climb that crossed the seam would be
                // measuring the far arm's depth.
                var own: usize = 0;
                for (all) |f| own += @intFromBool(NODES[f].seam == null);
                if (own == 0) break;
                at = all[@min(pick, own - 1)];
            }
            try std.testing.expectEqual(@as(usize, RINGS), depth);
            var k = depth;
            while (k > 0) {
                k -= 1;
                try std.testing.expect(t.locked(key, RICH) != null or line[k] == key);
                try std.testing.expect(t.take(line[k], RICH) != null);
            }
            try std.testing.expectEqual(@as(u32, RINGS), t.spentIn(b.arm()));
            try std.testing.expect(t.taken[key]);
        }
    }
}

test "SIX BRANCHES, TWO PER CLASS — and each one is its own idea end to end" {
    try std.testing.expectEqual(@as(usize, 2), NBRANCH / NARM);
    for (0..NBRANCH) |bi| {
        const b: Branch = @enumFromInt(bi);
        for (branchFirst(b)..branchFirst(b) + PER_BRANCH) |i| {
            try std.testing.expectEqual(b, NODES[i].branch.?);
            try std.testing.expectEqual(b.arm(), NODES[i].arm);
        }
    }
    try std.testing.expectEqual(PER_ARM, 1 + PER_BRANCH * 2);
    try std.testing.expectEqual(NTREE, NARM * PER_ARM);
    // THE BRIDGES ARE THE ONLY THING PAST THE ARMS, and every arm index still lands inside its own block.
    // **THAT IS NOT SAVE COMPATIBILITY AND MAY NOT BE READ AS ANY.** Appending the seams alone would have
    // been, but `BRANCH_RINGS` grew in the MIDDLE at the same time (39 nodes to 81), so every in-arm index
    // moved and `save.readBits` takes a short run in silence: an old `tree:` line loads a different set of
    // passives with nothing said. Only a save format bump answers that, and that is the owner's call.
    try std.testing.expectEqual(N, NTREE + NBRIDGE);
    for (0..NTREE) |i| try std.testing.expect(NODES[i].seam == null);
    for (NTREE..N) |i| try std.testing.expect(NODES[i].seam != null);
    std.debug.print("\n  passive tree: {d} nodes - {d} arms x (1 class node + 2 branches of {d}) + {d} bridges\n", .{ N, NARM, PER_BRANCH, NBRIDGE });
}

test "THE LINK IS THE RULE — every feeder is its own arm's and its own branch's, exactly one ring in" {
    var widest: usize = 0;
    for (0..N) |i| {
        var buf: [MAX_FEED]usize = undefined;
        const fs = feeders(i, &buf);
        for (fs) |f| {
            // **A SEAM IS THE ONE EDGE THAT BREAKS BOTH HALVES OF THIS RULE, AND THAT IS WHAT IT IS FOR** —
            // it crosses arms and it runs LEVEL rather than one ring in. Either end of it is exempt.
            if (NODES[i].seam != null or NODES[f].seam != null) {
                try std.testing.expectEqual(NODES[i].ring, NODES[f].ring);
                continue;
            }
            try std.testing.expectEqual(NODES[i].arm, NODES[f].arm);
            try std.testing.expectEqual(NODES[i].ring - 1, NODES[f].ring);
            // …and its own BRANCH, unless the feeder is the arm's own class node, which both branches share.
            if (NODES[f].ring > 0) try std.testing.expectEqual(NODES[i].branch.?, NODES[f].branch.?);
        }
        widest = @max(widest, fs.len);
        if (NODES[i].ring == 0) {
            try std.testing.expectEqual(@as(usize, 0), fs.len);
        } else {
            // **NOBODY IS AN ORPHAN AND NOBODY IS A DEAD END** — the two halves of the overlap rule, and the
            // pair a hand-written `min(slot, prev - 1)` rail cannot promise once a ring is three wide.
            try std.testing.expect(fs.len >= 1 and fs.len <= MAX_FEED);
        }
    }
    try std.testing.expect(widest > 1);

    for (0..N) |i| {
        if (NODES[i].ring + 1 >= RINGS) continue;
        var opens: usize = 0;
        for (0..N) |j| {
            var buf: [MAX_FEED]usize = undefined;
            for (feeders(j, &buf)) |f| {
                if (f == i) opens += 1;
            }
        }
        try std.testing.expect(opens >= 1);
    }
}

test "A BRIDGE CROSSES BOTH WAYS: taken from either arm, it opens the other" {
    for (NTREE..N) |bi| {
        const s = NODES[bi].seam.?;
        const a = bridgeAnchors(s, NODES[bi].ring);

        // Nothing taken, nothing reached: a seam is never free.
        var cold = Tree{};
        try std.testing.expect(!cold.reached(bi));

        // …and from EITHER end it opens, then opens the other end back.
        for (0..2) |side| {
            var t = Tree{};
            t.taken[a[side]] = true;
            try std.testing.expect(t.reached(bi));
            try std.testing.expect(!t.reached(a[1 - side]));
            t.taken[bi] = true;
            try std.testing.expect(t.reached(a[1 - side]));
        }
    }
}

test "…AND WHAT IT SAVES IS THE FAR ARM'S CLIMB, which is the whole reason to build one" {
    var saved: usize = 0;
    for (NTREE..N) |bi| {
        const s = NODES[bi].seam.?;
        const a = bridgeAnchors(s, NODES[bi].ring);
        for (0..2) |side| {
            const want = a[1 - side];

            // THE LONG WAY: the far anchor's own shortest climb from a standing start, counted by walking its
            // feeders down inside its own arm.
            var own: usize = 0;
            var at = want;
            while (true) {
                own += 1;
                var buf: [MAX_FEED]usize = undefined;
                var next: ?usize = null;
                for (feeders(at, &buf)) |f| {
                    if (NODES[f].seam == null and NODES[f].arm == NODES[want].arm) next = f;
                }
                at = next orelse break;
            }

            // THE CROSSING: standing on the near anchor, the bridge and the far rung. Two presses, whatever
            // ring it is at — which is what makes the deep seam worth more than the shallow one.
            var t = Tree{};
            t.taken[a[side]] = true;
            try std.testing.expect(t.take(bi, RICH) != null);
            try std.testing.expect(t.take(want, RICH) != null);
            try std.testing.expectEqual(@as(u32, 3), t.spent());
            try std.testing.expect(own > 2);
            saved += own - 2;
        }
    }
    std.debug.print("\n  passive tree: {d} bridges save {d} rungs of far-arm climbing between them\n", .{ NBRIDGE, saved });
}

test "A BRIDGE PAYS BOTH SIDES: the split lands two DIFFERENT attributes on the sheet" {
    for (NTREE..N) |bi| {
        const n = NODES[bi];
        const g = switch (n.grant) {
            .attr => |x| x,
            else => return error.TestUnexpectedResult,
        };
        const b = n.bump.?;
        try std.testing.expect(g.a != b.a);
        try std.testing.expect(g.n > 0 and b.n > 0);

        var t = Tree{};
        t.taken[bi] = true;
        const bonus = t.bonus();
        try std.testing.expectEqual(g.n, bonus.attrs[@intFromEnum(g.a)]);
        try std.testing.expectEqual(b.n, bonus.attrs[@intFromEnum(b.a)]);

        // NEITHER SIDE IS THE OTHER ARM'S LEFTOVER: a crossing spends a pair nothing else on the board does.
        for (NTREE..N) |oj| {
            if (oj == bi) continue;
            const o = NODES[oj];
            const og = switch (o.grant) {
                .attr => |x| x,
                else => continue,
            };
            const same = og.a == g.a and o.bump.?.a == b.a;
            try std.testing.expect(!same);
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
    try std.testing.expectEqual(N, got);
}

test "TAKING A NODE IS THE LEVEL — one press, and nothing is taken twice" {
    var t = Tree{};
    try std.testing.expectEqual(@as(u32, 1), t.level());
    try std.testing.expect(t.take(0, RICH) != null);
    try std.testing.expectEqual(@as(u32, 2), t.level());
    try std.testing.expectEqual(@as(u32, 1), t.spent());
    try std.testing.expect(t.take(0, RICH) == null);
    try std.testing.expectEqual(@as(u32, 1), t.spent());
}

test "IT IS PAID FOR IN SOULS, and one short buys nothing" {
    var t = Tree{};
    const c = t.cost();
    try std.testing.expect(t.locked(0, c - 1) != null);
    // **AND THE PREDICATE AND THE SENTENCE MAY NEVER DISAGREE** — `canTake` is what the board is drawn from
    // and `locked` is what the one node under the cursor says, so a node drawn open that refuses a press (or
    // the reverse) is the page and the rule contradicting each other on screen.
    for (0..N) |i| {
        for ([_]u32{ 0, 100, 359, 360, 1000, RICH }) |purse| {
            try std.testing.expectEqual(t.canTake(i, purse), t.locked(i, purse) == null);
        }
    }
    try std.testing.expect(t.take(0, c - 1) == null);
    try std.testing.expectEqual(@as(u32, 0), t.spent());
    try std.testing.expectEqual(c, t.take(0, c).?);
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
    var want = [_]u32{0} ** stats.NA;
    for (NODES) |n| {
        switch (n.grant) {
            .attr => |x| want[@intFromEnum(x.a)] += x.n,
            else => {},
        }
        // …AND OFF EVERY RIDER TOO. Counted only through the grant, a node that paid its point as a rider
        // would be a sheet the board cannot account for — which is the one thing this test exists to refuse.
        if (n.bump) |x| want[@intFromEnum(x.a)] += x.n;
    }
    for (0..stats.NA) |i| {
        const a: stats.Attr = @enumFromInt(i);
        try std.testing.expectEqual(@as(u8, @intCast(stats.START + want[i])), s.at(a));
        try std.testing.expect(want[i] > 0);
    }
    try std.testing.expect(s.hp() > (stats.Sheet{}).hp());
}

test "HALF THE BOARD PAYS A POINT, and a rider pays it through the SHEET and not just the card" {
    var carry: usize = 0;
    var pure: usize = 0;
    var ride: usize = 0;
    for (NODES) |n| {
        const isAttr = switch (n.grant) {
            .attr => true,
            else => false,
        };
        if (isAttr) pure += 1;
        if (n.bump != null) ride += 1;
        if (isAttr or n.bump != null) carry += 1;
    }
    std.debug.print(
        "\n  passive tree: {d} of {d} nodes carry a stat ({d} pure stat-ups, {d} ideas riding one) = {d:.0}%\n",
        .{ carry, N, pure, ride, @as(f32, @floatFromInt(carry)) * 100.0 / @as(f32, @floatFromInt(N)) },
    );
    try std.testing.expect(carry * 2 >= N);
    // …and BOTH kinds are actually on the board: all-pure would be a tree of nothing but stat-ups, and no
    // riders at all would make the whole `Bump` machinery a thing that compiles and never runs.
    try std.testing.expect(pure > 0 and ride > 0);

    // ONE RIDER, THROUGH THE SHEET. Taken alone, the node's own attribute must move by exactly its `n`.
    for (NODES, 0..) |n, i| {
        const bp = n.bump orelse continue;
        var t = Tree{};
        t.taken[i] = true;
        const s = t.bonus().sheet();
        try std.testing.expectEqual(@as(u8, stats.START + bp.n), s.at(bp.a));
        try std.testing.expect(bumpSays(bp).len > 0);
        // …and the card says both halves, never one: the grant's line AND the rider's.
        try std.testing.expect(grantSays(n.grant).len > 0);
    }
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

test "EVERY WORD ON THE CARD IS ASCII — the atlas has nothing else, and a tofu is silent" {
    // The Balthazar atlas is ASCII-only (AGENTS.md), so one `…` or `—` in a string draws as a `?` and nothing
    // says so: `bumpSays` shipped an ellipsis and the rider line read "?and +1 Vitality" in the shot. Every
    // sentence this file can put on screen, walked — the names, the grants, and the riders.
    const Chk = struct {
        fn ascii(s: []const u8) bool {
            for (s) |c| {
                if (c > 0x7e or c < 0x20) return false;
            }
            return true;
        }
    };
    for (NODES) |n| {
        try std.testing.expect(Chk.ascii(n.name));
        try std.testing.expect(Chk.ascii(grantSays(n.grant)));
        if (n.bump) |b| try std.testing.expect(Chk.ascii(bumpSays(b)));
    }
    inline for (@typeInfo(stats.Attr).@"enum".fields) |f| {
        try std.testing.expect(Chk.ascii(stats.displayName(@enumFromInt(f.value))));
    }
}

test "every node has a name and a legible grant, and A NAME IS A PROMISE ABOUT THE GRANT" {
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
    const key = armFirst(.wizard) + PER_ARM - 1;
    const back = step(key, 0, 1);
    try std.testing.expect(back != key);
    try std.testing.expect(unitPos(back).y > unitPos(key).y);
    try std.testing.expectEqual(key, step(key, 0, -1));
}

test "IT OPENS PANNABLE, and the zoom only ever buys MORE slide" {
    var w = Wheel{};
    try std.testing.expect(w.panLimit() >= PAN_FLOOR - 1e-6);
    for (0..600) |_| w.panBy(.{ .x = 1, .y = 1 }, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(PAN_FLOOR, w.pan.x, 1e-4);
    try std.testing.expectApproxEqAbs(PAN_FLOOR, w.pan.y, 1e-4);
    try std.testing.expect(w.panLimit() < VIEW_R);
    w.zoomBy(1, 10.0);
    try std.testing.expectApproxEqAbs(ZOOM_MAX, w.zoom, 1e-5);
    try std.testing.expect(w.panLimit() > PAN_FLOOR);
    for (0..600) |_| w.panBy(.{ .x = 1, .y = -1 }, 1.0 / 60.0);
    try std.testing.expect(w.pan.x > PAN_FLOOR and w.pan.x <= w.panLimit() + 1e-5);
    try std.testing.expect(w.pan.y < -PAN_FLOOR and w.pan.y >= -w.panLimit() - 1e-5);
    w.zoomBy(-1, 10.0);
    try std.testing.expectApproxEqAbs(ZOOM_MIN, w.zoom, 1e-5);
    try std.testing.expectApproxEqAbs(PAN_FLOOR, w.pan.x, 1e-4);
    try std.testing.expectApproxEqAbs(-PAN_FLOOR, w.pan.y, 1e-4);
}

test "THE MIDDLE IS THE MIDDLE — the hub sits dead centre of the panel on the frame it opens" {
    const wh = Wheel{};
    for ([_][4]i32{ .{ 0, 0, 800, 600 }, .{ 40, 20, 600, 800 }, .{ -30, 90, 512, 512 } }) |b| {
        const l = layout(wh, b[0], b[1], b[2], b[3]);
        const mid = place(l, HUB);
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(b[0])) + @as(f32, @floatFromInt(b[2])) * 0.5, mid.x, 1e-3);
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(b[1])) + @as(f32, @floatFromInt(b[3])) * 0.5, mid.y, 1e-3);
        try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@min(b[2], b[3]))) / (2.0 * VIEW_R), l.unit, 1e-3);
    }
    for (0..N) |i| {
        const p = unitPos(i);
        try std.testing.expect(std.math.hypot(p.x, p.y) + KEY_R * HALO_K <= VIEW_R + 1e-4);
    }
}

const CARDINALS = [_][2]f32{ .{ 0, -1 }, .{ 0, 1 }, .{ -1, 0 }, .{ 1, 0 } };

test "THE WALK GOES WHERE YOU PUSHED — every step from every spot lands inside the wedge" {
    for (0..SPOTS) |from| {
        for (CARDINALS) |d| {
            const to = step(from, d[0], d[1]);
            if (to == from) continue;
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
    try std.testing.expectEqual(Arm.wizard, NODES[step(HUB, 0, -1)].arm);
    try std.testing.expectEqual(Arm.warrior, NODES[step(HUB, -1, 0)].arm);
    try std.testing.expectEqual(Arm.rogue, NODES[step(HUB, 1, 0)].arm);
    for ([_][2]f32{ .{ 0, -1 }, .{ -1, 0 }, .{ 1, 0 } }) |d| {
        try std.testing.expectEqual(@as(u8, 0), NODES[step(HUB, d[0], d[1])].ring);
    }
}

test "POINT AT A NODE AND YOU GO TO THAT NODE — the stick's bearing IS the step" {
    // THE COMPLAINT, as arithmetic (owner: walking the tree with the stick "feels horrible"). Arms run out at
    // 0, 120 and 240 degrees, so ring-0 nodes sit at ∓15, 105, 135, 225 and 255 and every outward step on the
    // two lower arms runs near 96 or 216 — snapped to four screen axes inside a 32-degree dead cone
    // (`menu.STICK_CONE`), the push aimed AT a node did nothing on two arms of three. `stickPush`'s `radial`
    // hands the bearing over instead, so:
    //   1. from the MIDDLE, a push aimed at any ring-0 node reaches THAT node and not its neighbour…
    for (0..N) |i| {
        if (NODES[i].ring != 0) continue;
        const p = unitPos(i);
        try std.testing.expectEqual(i, step(HUB, p.x, p.y));
    }
    for (0..N) |i| {
        var buf: [MAX_FEED]usize = undefined;
        for (feeders(i, &buf)) |f| {
            const a = unitPos(f);
            const b = unitPos(i);
            try std.testing.expectEqual(i, step(f, b.x - a.x, b.y - a.y));
        }
    }
    //   3. …and it is not required to arrive normalised: a raw node-minus-node delta is a bearing, and its own
    //      LENGTH must not decide how wide the wedge is.
    const up = unitPos(14);
    try std.testing.expectEqual(step(HUB, up.x, up.y), step(HUB, up.x * 40.0, up.y * 40.0));
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
            try std.testing.expectEqual(@as(u8, 0), NODES[to].ring);
        }
    }
}

test "NO NODE IS UNREACHABLE — four directions get you from any one of them to every other spot" {
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
        try std.testing.expect(radiusOf(NODES[i]) >= 1.0);
        for (i + 1..N) |j| {
            const b = unitPos(j);
            const d = std.math.hypot(a.x - b.x, a.y - b.y);
            try std.testing.expect(d > 0.30);
        }
        const n = NODES[i];
        // A BRIDGE HANGS OFF THE SEAM, WHICH IS THE ONE PLACE THAT IS NOBODY'S ARM — dead on it, and exactly
        // half a gap from each of the two it joins.
        if (n.seam) |s| {
            try std.testing.expectApproxEqAbs(seamAngle(s), angleOf(n), 1e-5);
            const near = @abs(mathx.wrapPi(angleOf(n) - armAngle(s.from())));
            const far = @abs(mathx.wrapPi(angleOf(n) - armAngle(s.to())));
            try std.testing.expectApproxEqAbs(near, far, 1e-5);
            try std.testing.expectApproxEqAbs(std.math.tau / 6.0, near, 1e-5);
            continue;
        }
        const own = if (n.branch) |b| branchAngle(b) else armAngle(n.arm);
        const off = @abs(mathx.wrapPi(angleOf(n) - own));
        try std.testing.expect(off <= (if (n.branch == null) 1e-5 else spreadAt(n.ring)) + 1e-5);
        const fromArm = @abs(mathx.wrapPi(angleOf(n) - armAngle(n.arm)));
        try std.testing.expect(fromArm < std.math.tau / 6.0);
        try std.testing.expect(off < std.math.tau / @as(f32, NARM) * 0.5);
    }
}


test "SUSTAIN IS PRICED AGAINST THE FLASK, WHICH IS THE ONLY OTHER HEALING IN THE GAME" {
    const bar = stats.hpFor(stats.START);
    const charge = bar * combat.FLASK_HP_FRAC;
    const budget = charge * @as(f32, @floatFromInt(combat.FLASK_CRIMSON));

    var tree = Tree{};
    for (&tree.taken) |*t| t.* = true;
    const all = tree.bonus();
    const hitsPerCharge = charge / all.leech;
    const killsPerCharge = charge / all.onKill;
    std.debug.print(
        "\n  sustain: bar {d:.0}, flask charge {d:.0} ({d:.0} HP between fires) | leech {d:.1}/hit = {d:.0} blows a charge, onKill {d:.1} = {d:.1} bodies\n",
        .{ bar, charge, budget, all.leech, hitsPerCharge, all.onKill, killsPerCharge },
    );

    // **A BLOW MAY NOT BE A SIP, AND IT IS PRICED BY THE RATE AND NOT BY THE BLOW** (owner, three times over:
    // lifesteal is STILL op). 5.5 was six blows a charge, 2.0 was sixteen — and sixteen still reads as
    // unlimited, because a light chain lands about 1.5 blows a second and that made the bar refill itself
    // every 23 s while you fought. THIRTY at the very least now, with every node in the tree taken.
    try std.testing.expect(hitsPerCharge >= 30.0);
    try std.testing.expect(killsPerCharge >= 8.0);
    // …and a whole camp cleared may not be a charge, let alone two: it is the FIGHT that has to cost you.
    const sixBodies = all.onKill * 6.0;
    try std.testing.expect(sixBodies < budget * 0.4);
    // **AND THE RING IS NOW CLEAR OF THE WHOLE BRANCH FOR ONE HIT** (`item.leech_signet`: 2.0 for a permanent
    // 6% of the bar), where the tree used to draw level with it. Points buy the trickle, health buys the size.
    try std.testing.expect(all.leech <= 1.0);
    try std.testing.expect(all.leech > 0.25 and all.onKill >= 2.0);
    // …and the two together, at the rate a fight actually runs at, may not out-heal the poison ticking on you.
    const perSecond = all.leech * 1.5 + all.hpRegen;
    std.debug.print("  sustain: {d:.2} HP a second at 1.5 blows a second, against a {d:.0} bar\n", .{ perSecond, bar });
    try std.testing.expect(perSecond < bar * 0.06);
}
