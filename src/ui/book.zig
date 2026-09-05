const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const itemart = @import("itemart.zig");
const item = @import("../play/item.zig");
const stats = @import("../play/stats.zig");
const ptree = @import("../play/passivetree.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const gfx = @import("../gfx/gfx.zig");
const mapart = @import("mapart.zig");
const sfx = @import("../core/audio.zig");


const rgba = mathx.rgba;
const v3 = mathx.v3;

pub const Page = enum {
    equipment,
    inventory,
    stats,
    spells,
    tree,
    map,

    fn label(p: Page) [:0]const u8 {
        return switch (p) {
            .equipment => "EQUIPMENT",
            .inventory => "INVENTORY",
            .stats => "STATS",
            .spells => "SPELLS",
            .tree => "PASSIVES",
            .map => "MAP",
        };
    }

    fn panned(p: Page) bool {
        return p == .tree or p == .map;
    }
};

const NPAGE = @typeInfo(Page).@"enum".fields.len;

pub const Hand = struct { a: heromod.Armament, kind: ?item.Kind = null };

pub const Action = union(enum) {
    none,
    arm: Hand,
    off: Hand,
    armAlt: Hand,
    offAlt: Hand,
    ammo: combat.ArrowKind,
    quick: struct { slot: usize, kind: ?item.Kind },
    wear: struct { slot: item.Wear, kind: ?item.Kind },
    use: item.Kind,
};

pub const View = struct {
    bag: *const item.Bag,
    sheet: *const stats.Sheet,
    res: *const combat.Resists,
    flasks: *const combat.Flasks,
    quick: *const combat.Quick,
    quiver: *const combat.Quiver,
    tree: *const ptree.Tree,
    mem: combat.Memory = .{},
    inCombat: bool = false,
    arm: heromod.Armament,
    off: heromod.Armament,
    armAlt: heromod.Armament = .bow,
    offAlt: heromod.Armament = .wand,
    spell: combat.Spell,
    fp: f32,
    souls: u32,
    gold: u32 = 0,
    worn: heromod.Worn = .{},
    tiers: [heromod.NARM]u8 = [_]u8{0} ** heromod.NARM,
    world: ?World = null,

    pub fn tierOf(self: *const View, a: heromod.Armament) u8 {
        return self.tiers[@intFromEnum(a)];
    }

    pub fn holds(self: *const View, a: heromod.Armament) bool {
        return heromod.handsHold(self.arm, self.off, a);
    }
    pub fn offInHand(self: *const View) bool {
        return !heromod.armTwoHanded(self.arm) and !heromod.armTwoHanded(self.off);
    }
};

pub const Portrait = struct { hero: *const heromod.Hero, scene: *gfx.Scene };

pub const World = mapart.World;


const Loadout = struct {
    arm: heromod.Arm,
    off: heromod.Off,
    ammo: combat.ArrowKind,
    quick: ?item.Kind,
    spell: combat.Spell,
    worn: heromod.Worn = .{},
    /// The smith's work on the hand this loadout is weighing (`hero.tiers`), 0 for a bare one.
    tier: u8 = 0,
};

const Unit = enum { flat, pct, count, secs };

const Der = enum {
    light,
    heavy,
    elem,
    swing,
    poise,
    stance,
    spell,
    spell_fp,
    quick,
    ammo,
    hp,
    fp,
    armour,
    negate,
    guard,
    arc,
    res_fire,
    res_cold,
    res_lightning,
    res_chaos,
};
const ND = @typeInfo(Der).@"enum".fields.len;

const DER_SPLIT: usize = @intFromEnum(Der.hp);
const DER_CAPS = [2][:0]const u8{ "OFFENCE", "BODY" };

comptime {
    // A column of nothing is a caption over blank panel, and a column of twenty is the overflow this split fixed.
    if (DER_SPLIT == 0 or DER_SPLIT >= ND) @compileError("book: `DER_SPLIT` leaves one of the two columns empty");
}

fn worth(d: [ND]f32, k: Der) f32 {
    return d[@intFromEnum(k)];
}

/// `short` is the word a picker row leads with ("+6 heavy"); empty means the name serves.
const DerivedRow = struct { name: [:0]const u8, unit: Unit, cost: bool = false, short: [:0]const u8 = "" };

const DER = blk: {
    var rows = [_]DerivedRow{.{ .name = "", .unit = .flat }} ** ND;
    rows[@intFromEnum(Der.light)] = .{ .name = "Light attack", .unit = .flat, .short = "light" };
    rows[@intFromEnum(Der.heavy)] = .{ .name = "Heavy attack", .unit = .flat, .short = "heavy" };
    rows[@intFromEnum(Der.elem)] = .{ .name = "Elemental damage", .unit = .flat, .short = "elemental" };
    rows[@intFromEnum(Der.swing)] = .{ .name = "Swing time", .unit = .secs, .cost = true, .short = "swing" };
    rows[@intFromEnum(Der.poise)] = .{ .name = "Poise damage", .unit = .flat, .short = "poise" };
    rows[@intFromEnum(Der.stance)] = .{ .name = "Stance damage", .unit = .flat, .short = "stance" };
    rows[@intFromEnum(Der.hp)] = .{ .name = "HP", .unit = .flat, .short = "HP" };
    rows[@intFromEnum(Der.fp)] = .{ .name = "Focus", .unit = .flat, .short = "Focus" };
    rows[@intFromEnum(Der.armour)] = .{ .name = "Armour", .unit = .flat, .short = "armour" };
    rows[@intFromEnum(Der.negate)] = .{ .name = "Damage negated", .unit = .pct, .short = "negated" };
    rows[@intFromEnum(Der.guard)] = .{ .name = "Guard negation", .unit = .pct, .short = "guard" };
    rows[@intFromEnum(Der.arc)] = .{ .name = "Guard arc", .unit = .flat, .short = "arc" };
    for (0..combat.NELEM) |i| {
        rows[@intFromEnum(Der.res_fire) + i] = .{ .name = combat.elemName(@enumFromInt(i)) ++ " resistance", .unit = .pct, .short = combat.elemName(@enumFromInt(i)) ++ " res" };
    }
    rows[@intFromEnum(Der.spell)] = .{ .name = "Sorcery damage", .unit = .flat, .short = "sorcery" };
    rows[@intFromEnum(Der.spell_fp)] = .{ .name = "Focus, per cast", .unit = .flat, .cost = true, .short = "FP a cast" };
    rows[@intFromEnum(Der.quick)] = .{ .name = "Quick item restores", .unit = .flat, .short = "restores" };
    rows[@intFromEnum(Der.ammo)] = .{ .name = "Ammunition", .unit = .count, .short = "shafts" };
    for (rows, 0..) |r, i| {
        if (r.name.len == 0) @compileError("book: `Der." ++ @typeInfo(Der).@"enum".fields[i].name ++
            "` has no row — the sheet would print a blank line with a number beside it");
    }
    break :blk rows;
};

comptime {
    if (@intFromEnum(Der.res_chaos) - @intFromEnum(Der.res_fire) != combat.NELEM - 1)
        @compileError("book: the `res_*` rows of `Der` are not one contiguous run of `combat.NELEM`");
}

const armourOf = heromod.armourOf;

fn sheetOf(l: Loadout, perk: ptree.Bonus) stats.Sheet {
    var s = perk.sheet();
    heromod.boonsOnto(l.worn, &s);
    return s;
}

fn castFp(s: combat.Spell, perk: ptree.Bonus) f32 {
    return combat.spellFp(s) * perk.spellCost;
}

fn resOf(l: Loadout, perk: ptree.Bonus) combat.Resists {
    var r = perk.res;
    const worn = combat.resistsOf(heromod.suitOf(l.worn).plate.res);
    for (&r.v, worn.v) |*x, w| x.* += w;
    return r;
}

fn derive(l: Loadout, v: View) [ND]f32 {
    const bow = heromod.handsHold(l.arm, l.off, .bow);
    const attacks = bow or heromod.armSwings(l.arm) or heromod.armSwings(l.off);
    const row = heromod.armRow(l.worn, if (bow) .hand_bow else heromod.swingSocket(l.arm, l.off));
    const perk = v.tree.bonus();
    const sheet = sheetOf(l, perk);
    const tier = l.tier;
    const light = heromod.weigh(if (bow) heromod.arrowBlow(l.ammo, false, perk) else heromod.ATK_LIGHT_HIT, row, sheet, tier);
    const heavy = heromod.weigh(if (bow) heromod.arrowBlow(l.ammo, true, perk) else heromod.ATK_HEAVY_HIT, row, sheet, tier);
    var d: [ND]f32 = undefined;
    d[@intFromEnum(Der.light)] = if (attacks) light.dmg else 0;
    d[@intFromEnum(Der.heavy)] = if (attacks) heavy.dmg else 0;
    d[@intFromEnum(Der.elem)] = if (attacks) heavy.elem.total() else 0;
    d[@intFromEnum(Der.poise)] = if (attacks) heavy.poise else 0;
    d[@intFromEnum(Der.stance)] = if (attacks) heavy.stance else 0;
    const blade: ?heromod.Blade = if (heromod.meleeArmOf(l.arm, l.off)) |a| heromod.bladeOf(a) else null;
    d[@intFromEnum(Der.swing)] = if (!attacks) 0 else if (bow)
        heromod.drawSecs(true, row)
    else if (blade) |b|
        heromod.swingSecs(b, true, row)
    else
        0;
    d[@intFromEnum(Der.hp)] = heromod.hpMaxOf(sheet, l.worn, perk);
    d[@intFromEnum(Der.fp)] = heromod.fpMaxOf(sheet, l.worn, perk);
    const res = resOf(l, perk);
    for (0..combat.NELEM) |i| d[@intFromEnum(Der.res_fire) + i] = res.at(@enumFromInt(i));
    const guards = heromod.handsHold(l.arm, l.off, .shield);
    const board = heromod.armRow(l.worn, .hand_shield);
    // THE BOARD'S OWN NEGATION PLUS THE TREE'S, capped where the fight caps it (`combat.GUARD_NEGATE_CAP`).
    d[@intFromEnum(Der.guard)] = if (guards) combat.guardNegation(board.negate, perk.guard) * 100.0 else 0;
    d[@intFromEnum(Der.arc)] = if (guards) combat.GUARD_ARC * board.arc else 0;
    const armour = armourOf(l.worn);
    d[@intFromEnum(Der.armour)] = armour;
    d[@intFromEnum(Der.negate)] = 100.0 * (1.0 - combat.armourTaken(armour, heromod.ATK_HEAVY_HIT.dmg) / heromod.ATK_HEAVY_HIT.dmg);
    const casts = heromod.handsHold(l.arm, l.off, .wand);
    const spellK: f32 = if (combat.spellBlow(l.spell) != null) perk.spellDmg * sheet.scale(.intelligence) else 1.0;
    d[@intFromEnum(Der.spell)] = if (casts) combat.spellDamage(l.spell) * spellK else 0;
    d[@intFromEnum(Der.spell_fp)] = if (casts) castFp(l.spell, perk) else 0;
    d[@intFromEnum(Der.quick)] = quickWorth(l.quick, l.worn, sheet, perk);
    d[@intFromEnum(Der.ammo)] = @floatFromInt(v.quiver.count(l.ammo));
    return d;
}


pub const SlotId = enum {
    helm,
    amulet,
    left,
    chest,
    right,
    ring1,
    belt,
    ring2,
    arrows,
    boots,
    sorcery,
    left2,
    right2,
    q0,
    q1,
    q2,
    q3,
    q4,
    q5,
    q6,
    q7,
    q8,
    q9,
};
const NSLOT = @typeInfo(SlotId).@"enum".fields.len;

pub fn slotOrdinal(s: SlotId) usize {
    return @intFromEnum(s);
}
const Q0: usize = @intFromEnum(SlotId.q0);
comptime {
    if (NSLOT - Q0 != combat.QUICK_SLOTS) @compileError("book: the quick sockets and combat.QUICK_SLOTS disagree");
}

fn quickIndex(s: SlotId) ?usize {
    const i = @intFromEnum(s);
    return if (i >= Q0) i - Q0 else null;
}

const SLOT_COLS: i32 = 5;
const SLOT_ROWS: i32 = 6;
const SLOT_MIN: i32 = 30;
const SLOT_MAX: i32 = 112;
const Cell = struct { col: i32, row: i32 };
const SLOT_CELL = blk: {
    var c = [_]Cell{.{ .col = 0, .row = 0 }} ** NSLOT;
    c[@intFromEnum(SlotId.helm)] = .{ .col = 2, .row = 0 };
    c[@intFromEnum(SlotId.amulet)] = .{ .col = 3, .row = 0 };
    c[@intFromEnum(SlotId.left)] = .{ .col = 1, .row = 1 };
    c[@intFromEnum(SlotId.chest)] = .{ .col = 2, .row = 1 };
    c[@intFromEnum(SlotId.right)] = .{ .col = 3, .row = 1 };
    c[@intFromEnum(SlotId.ring1)] = .{ .col = 1, .row = 2 };
    c[@intFromEnum(SlotId.belt)] = .{ .col = 2, .row = 2 };
    c[@intFromEnum(SlotId.ring2)] = .{ .col = 3, .row = 2 };
    c[@intFromEnum(SlotId.arrows)] = .{ .col = 1, .row = 3 };
    c[@intFromEnum(SlotId.boots)] = .{ .col = 2, .row = 3 };
    c[@intFromEnum(SlotId.sorcery)] = .{ .col = 3, .row = 3 };
    c[@intFromEnum(SlotId.left2)] = .{ .col = 0, .row = 1 };
    c[@intFromEnum(SlotId.right2)] = .{ .col = 4, .row = 1 };
    for (0..combat.QUICK_SLOTS) |i| {
        c[Q0 + i] = .{ .col = @intCast(i % 5), .row = 4 + @as(i32, @intCast(i / 5)) };
    }
    break :blk c;
};

fn slotName(s: SlotId) [:0]const u8 {
    return switch (s) {
        .helm => "Head",
        .amulet => "Neck",
        .left => "L Hand",
        .left2 => "L Alt",
        .chest => "Body",
        .right => "R Hand",
        .right2 => "R Alt",
        .ring1 => "Ring",
        .belt => "Belt",
        .ring2 => "Ring",
        .arrows => "Ammo",
        .boots => "Feet",
        .sorcery => "Spell",
        .q0 => "1",
        .q1 => "2",
        .q2 => "3",
        .q3 => "4",
        .q4 => "5",
        .q5 => "6",
        .q6 => "7",
        .q7 => "8",
        .q8 => "9",
        .q9 => "10",
    };
}

fn carriesFor(w: item.Wear, v: View) bool {
    if (v.worn.at(w) != null) return true;
    inline for (@typeInfo(item.Kind).@"enum".fields) |f| {
        const k: item.Kind = @enumFromInt(f.value);
        if (item.wearSlot(k) == w and v.bag.count(k) > 0) return true;
    }
    return false;
}

fn wearOf(s: SlotId) ?item.Wear {
    return switch (s) {
        .chest => .chest,
        .ring1 => .ring,
        .ring2 => .ring2,
        .helm => .helm,
        .amulet => .neck,
        .belt => .belt,
        .boots => .feet,
        else => null,
    };
}

fn emptyHanded(w: item.Wear) [:0]const u8 {
    return switch (w) {
        .chest => "No chest armour.",
        .ring, .ring2 => "No rings.",
        .helm => "No helm.",
        .neck => "No amulet.",
        .belt => "No belt.",
        .feet => "No boots.",
        .hand_sword, .hand_dagger, .hand_club, .hand_bow, .hand_shield => "Nothing to hold.",
    };
}

fn locked(s: SlotId, v: View) ?[:0]const u8 {
    if (wearOf(s)) |w| return if (!carriesFor(w, v)) emptyHanded(w) else null;
    return switch (s) {
        .left => if (v.offInHand())
            null
        else if (heromod.armTwoHanded(v.arm) or heromod.armTwoHanded(v.off))
            "The bow takes both hands."
        else
            "One weapon hand. The right takes it.",
        .left2, .right2 => null,
        .sorcery => if (v.holds(.bow))
            "The bow takes both hands."
        else if (!v.holds(.wand))
            "No wand equipped."
        else if (!v.mem.holds(v.spell))
            "Nothing memorized. Sit at a bonfire."
        else
            "D-pad Up switches sorcery.",
        else => null,
    };
}

fn quickAt(s: SlotId, v: View) ?item.Kind {
    return if (quickIndex(s)) |i| v.quick.slots[i] else null;
}

fn slotHas(s: SlotId, v: View) bool {
    if (wearOf(s)) |w| return v.worn.at(w) != null;
    return switch (s) {
        .right, .left2, .right2 => true,
        .left => v.offInHand(),
        .sorcery => v.holds(.wand) and v.mem.holds(v.spell),
        .arrows => v.quiver.count(v.quiver.sel) > 0,
        else => quickAt(s, v) != null,
    };
}

const EMPTY = "-";

pub fn armName(a: heromod.Armament) [:0]const u8 {
    return switch (a) {
        .sword => "Straight Sword",
        .dagger => "Dagger",
        .club => "Club",
        .bow => "Short Bow",
        .bell => "Summoning Bell",
        .shield => "Small Shield",
        .wand => "Knotted Wand",
        .torch => "Pitch Torch",
    };
}
fn ammoName(k: combat.ArrowKind) [:0]const u8 {
    return switch (k) {
        .plain => "Arrow",
        .fire => "Fire Arrow",
    };
}

fn handName(a: heromod.Armament, worn: heromod.Worn) [:0]const u8 {
    if (heromod.wearFor(a)) |w| {
        if (worn.at(w)) |k| return item.displayName(k);
    }
    return armName(a);
}

fn slotFilled(s: SlotId, v: View) [:0]const u8 {
    if (wearOf(s)) |w| return if (v.worn.at(w)) |k| item.displayName(k) else EMPTY;
    return switch (s) {
        .right => handName(v.arm, v.worn),
        .left => if (!v.offInHand()) EMPTY else handName(v.off, v.worn),
        .left2 => handName(v.offAlt, v.worn),
        .right2 => handName(v.armAlt, v.worn),
        .sorcery => if (slotHas(.sorcery, v)) combat.spellName(v.spell) else EMPTY,
        .arrows => ammoName(v.quiver.sel),
        else => if (quickAt(s, v)) |k| item.displayName(k) else EMPTY,
    };
}

fn slotTally(s: SlotId, v: View) ?u8 {
    if (wearOf(s) != null) return null;
    return switch (s) {
        .arrows => v.quiver.count(v.quiver.sel),
        .sorcery => if (slotHas(.sorcery, v)) castsLeft(v.fp, v.spell, v) else null,
        .left, .right, .left2, .right2 => null,
        else => if (quickAt(s, v)) |k| quickTally(k, v) else null,
    };
}

fn quickWorth(kind: ?item.Kind, worn: heromod.Worn, sheet: stats.Sheet, perk: ptree.Bonus) f32 {
    const k = kind orelse return 0;
    const hpMax = heromod.hpMaxOf(sheet, worn, perk);
    if (combat.flaskOf(k)) |f| return switch (f) {
        .crimson => hpMax * combat.FLASK_HP_FRAC * perk.flaskHeal,
        .cerulean => heromod.fpMaxOf(sheet, worn, perk) * combat.FLASK_FP_FRAC,
    };
    return switch (item.use(k)) {
        .none => 0,
        .regen => |r| hpMax * r.frac,
        .lob => |b| b.dmg + b.fire + b.lightning,
        .ward, .wind, .grease, .souls, .brew, .purge, .steady, .arrows, .dose, .coat, .toll => 0,
    };
}

fn quickOffered(k: item.Kind, v: View) bool {
    if (!item.quickable(k)) return false;
    return combat.flaskOf(k) != null or v.bag.count(k) > 0;
}

fn quickTally(k: item.Kind, v: View) u8 {
    return combat.quickCount(k, v.flasks, v.bag);
}

fn castsLeft(fp: f32, s: combat.Spell, v: View) u8 {
    const cost = castFp(s, v.tree.bonus());
    if (cost <= 0) return 0;
    return @intFromFloat(mathx.clampF(@floor(fp / cost), 0, 255));
}

const Cand = struct { name: [:0]const u8, tally: ?u8 = null, act: Action };

const CAND_MAX = blk: {
    var n: usize = item.NK + 1;
    for ([_]type{ heromod.Arm, heromod.Off, combat.ArrowKind }) |T| {
        n = @max(n, @typeInfo(T).@"enum".fields.len);
    }
    n = @max(n, @typeInfo(heromod.Armament).@"enum".fields.len + item.NK);
    break :blk n;
};

fn handAct(s: SlotId, h: Hand) Action {
    return switch (s) {
        .right => .{ .arm = h },
        .left => .{ .off = h },
        .right2 => .{ .armAlt = h },
        .left2 => .{ .offAlt = h },
        else => unreachable,
    };
}

fn candidates(s: SlotId, v: View, out: *[CAND_MAX]Cand) []const Cand {
    if (locked(s, v) != null) return out[0..0];
    if (wearOf(s)) |w| {
        var n: usize = 1;
        out[0] = .{ .name = "(nothing)", .act = .{ .wear = .{ .slot = w, .kind = null } } };
        inline for (@typeInfo(item.Kind).@"enum".fields) |f| {
            const k: item.Kind = @enumFromInt(f.value);
            if (item.wearSlot(k) == w and v.bag.count(k) > 0) {
                out[n] = .{ .name = item.displayName(k), .act = .{ .wear = .{ .slot = w, .kind = k } } };
                n += 1;
            }
        }
        return out[0..n];
    }
    switch (s) {
        .right, .left, .right2, .left2 => {
            var n: usize = 0;
            inline for (@typeInfo(heromod.Armament).@"enum".fields) |f| {
                const a: heromod.Armament = @enumFromInt(f.value);
                if (comptime !heromod.armSwings(a) or a == .sword) {
                    out[n] = .{ .name = armName(a), .act = handAct(s, .{ .a = a }) };
                    n += 1;
                }
                if (comptime heromod.wearFor(a)) |w| {
                    inline for (@typeInfo(item.Kind).@"enum".fields) |kf| {
                        const k: item.Kind = @enumFromInt(kf.value);
                        if (comptime item.wearSlot(k) == w) {
                            if (v.bag.count(k) > 0) {
                                out[n] = .{ .name = item.displayName(k), .tally = @intCast(@min(9, v.bag.count(k))), .act = handAct(s, .{ .a = a, .kind = k }) };
                                n += 1;
                            }
                        }
                    }
                }
            }
            return out[0..n];
        },
        .arrows => {
            inline for (@typeInfo(combat.ArrowKind).@"enum".fields, 0..) |f, i| {
                const k: combat.ArrowKind = @enumFromInt(f.value);
                out[i] = .{ .name = ammoName(k), .tally = v.quiver.count(k), .act = .{ .ammo = k } };
            }
            return out[0..@typeInfo(combat.ArrowKind).@"enum".fields.len];
        },
        else => {
            const qi = quickIndex(s) orelse return out[0..0];
            var n: usize = 1;
            out[0] = .{ .name = "(empty)", .act = .{ .quick = .{ .slot = qi, .kind = null } } };
            @setEvalBranchQuota(6000);
            inline for (@typeInfo(item.Kind).@"enum".fields) |f| {
                const k: item.Kind = @enumFromInt(f.value);
                if (quickOffered(k, v)) {
                    out[n] = .{ .name = item.displayName(k), .tally = quickTally(k, v), .act = .{ .quick = .{ .slot = qi, .kind = k } } };
                    n += 1;
                }
            }
            return out[0..n];
        },
    }
}

fn wearInto(worn: *heromod.Worn, h: Hand) void {
    if (heromod.wearFor(h.a)) |w| worn.put(w, h.kind);
}

fn inForce(v: View) Loadout {
    return .{
        .arm = v.arm,
        .off = v.off,
        .ammo = v.quiver.sel,
        .quick = v.quick.selected(),
        .spell = v.spell,
        .worn = v.worn,
    };
}

fn withCand(base: Loadout, c: Cand) Loadout {
    var l = base;
    switch (c.act) {
        .arm => |h| {
            l.arm = h.a;
            wearInto(&l.worn, h);
        },
        .off => |h| {
            l.off = h.a;
            wearInto(&l.worn, h);
        },
        .armAlt, .offAlt => |h| wearInto(&l.worn, h),
        .ammo => |a| l.ammo = a,
        .quick => |q| l.quick = q.kind,
        .wear => |wr| l.worn.put(wr.slot, wr.kind),
        .none, .use => {},
    }
    return l;
}

fn equipped(c: Cand, v: View) bool {
    return switch (c.act) {
        .arm => |h| h.a == v.arm and heldSame(h, v),
        .off => |h| h.a == v.off and heldSame(h, v),
        .armAlt => |h| h.a == v.armAlt and heldSame(h, v),
        .offAlt => |h| h.a == v.offAlt and heldSame(h, v),
        .ammo => |a| a == v.quiver.sel,
        .quick => |q| v.quick.slots[q.slot] == q.kind,
        .wear => |wr| v.worn.at(wr.slot) == wr.kind,
        .none, .use => false,
    };
}

fn heldSame(h: Hand, v: View) bool {
    const w = heromod.wearFor(h.a) orelse return true;
    return v.worn.at(w) == h.kind;
}

/// On what is ALREADY equipped, never row 0 — a cursor landing anywhere else tricks you into swapping something you meant to look at. ASKED OF THE LIST ITSELF, NEVER COUNTED A SECOND TIME.
fn pickIndexOf(s: SlotId, v: View) usize {
    var out: [CAND_MAX]Cand = undefined;
    for (candidates(s, v, &out), 0..) |c, i| {
        if (equipped(c, v)) return i;
    }
    return 0;
}


const MOVE_EASE: f32 = 17.0;
const PRESS_RATE: f32 = 9.0;
const POP_DUR: f32 = 0.30;
const SPIN_RATE: f32 = 1.7; // radians a second, the portrait turntable under Left/Right

pub const Book = struct {
    page: Page = .equipment,
    cur: [NPAGE]usize = blk: {
        var c = [_]usize{0} ** NPAGE;
        c[idx(.equipment)] = @intFromEnum(SlotId.right);
        break :blk c;
    },
    wheel: ptree.Wheel = .{},
    lens: mapart.Lens = .{},
    picking: ?SlotId = null,
    pick: usize = 0,
    scroll: usize = 0,
    press: f32 = 0,
    pop: f32 = 0,
    at: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    settled: bool = false,
    spin: f32 = 0.55,

    pub fn opened(self: *Book) void {
        self.picking = null;
        self.settled = false;
        self.press = 0;
        self.pop = 0;
        mapart.restage();
    }

    pub fn onMap(self: *Book, v: View) void {
        const w = v.world orelse return;
        self.lens.centreOn(w.at.x, w.at.z, w.map.half);
    }

    fn moved(self: *Book) void {
        self.settled = true;
        sfx.play(.menu_move);
    }

    pub fn tick(self: *Book, dt: f32, held: bool, v: View) void {
        self.clamp(v);
        self.press = mathx.clampF(self.press + (if (held) dt else -dt) * PRESS_RATE, 0, 1);
        self.pop = mathx.maxF(0, self.pop - dt);
        const want = self.cursorRect(v);
        if (!self.settled) {
            self.at = want;
            return;
        }
        const k = mathx.clampF(dt * MOVE_EASE, 0, 1);
        self.at.x += (want.x - self.at.x) * k;
        self.at.y += (want.y - self.at.y) * k;
        self.at.width += (want.width - self.at.width) * k;
        self.at.height += (want.height - self.at.height) * k;
    }

    fn clamp(self: *Book, v: View) void {
        const bag = bagCells(v);
        self.cur[idx(.inventory)] = @min(self.cur[idx(.inventory)], bag - 1);
        self.cur[idx(.equipment)] = @min(self.cur[idx(.equipment)], NSLOT - 1);
        self.cur[idx(.stats)] = @min(self.cur[idx(.stats)], stats.NA - 1);
        self.cur[idx(.spells)] = @min(self.cur[idx(.spells)], combat.SPELLS.len - 1);
        const rows = (bag + BAG_COLS - 1) / BAG_COLS;
        self.scroll = @min(self.scroll, rows -| BAG_ROWS);
        const row = self.cur[idx(.inventory)] / BAG_COLS;
        if (row < self.scroll) self.scroll = row;
        if (row >= self.scroll + BAG_ROWS) self.scroll = row - BAG_ROWS + 1;
    }

    fn thump(self: *Book) void {
        self.pop = POP_DUR;
    }

    pub fn onTab(self: *Book, dir: i32, v: View) void {
        if (self.picking != null) return; // a page cannot change under an open picker
        const n: i32 = NPAGE;
        const i: i32 = @intCast(@intFromEnum(self.page));
        self.page = @enumFromInt(@as(usize, @intCast(@mod(i + dir + n, n))));
        if (self.page == .map) self.onMap(v);
        self.settled = false;
        sfx.play(.flask_cycle);
    }

    pub fn onBack(self: *Book) bool {
        if (self.picking == null) return false;
        self.picking = null;
        self.settled = false;
        sfx.play(.menu_back);
        return true;
    }

    pub fn move(self: *Book, dx: f32, dy: f32, v: View) void {
        const sy = mathx.signI(dy);
        const sx = mathx.signI(dx);
        if (self.picking) |s| {
            var buf: [CAND_MAX]Cand = undefined;
            const cs = candidates(s, v, &buf);
            if (cs.len == 0 or sy == 0) return;
            const n: i32 = @intCast(cs.len);
            self.pick = @intCast(@mod(@as(i32, @intCast(self.pick)) + sy + n, n));
            self.moved();
            return;
        }
        if (self.page == .tree) {
            if (self.wheel.move(dx, dy)) self.moved();
            return;
        }
        if (self.page == .map) {
            self.lens.panStep(@floatFromInt(sx), @floatFromInt(sy));
            return;
        }
        const i = idx(self.page);
        const next = switch (self.page) {
            .equipment => slotStep(self.cur[i], sx, sy),
            .inventory => grid(self.cur[i], @max(v.bag.distinct(), 1), BAG_COLS, sx, sy),
            .stats => if (sy == 0) self.cur[i] else @as(usize, @intCast(@mod(
                @as(i32, @intCast(self.cur[i])) + sy + @as(i32, stats.NA),
                @as(i32, stats.NA),
            ))),
            .spells => if (sy == 0) self.cur[i] else @as(usize, @intCast(@mod(
                @as(i32, @intCast(self.cur[i])) + sy + @as(i32, combat.SPELLS.len),
                @as(i32, combat.SPELLS.len),
            ))),
            .tree, .map => unreachable,
        };
        if (next == self.cur[i]) return;
        self.cur[i] = next;
        self.moved();
    }

    pub fn spinBy(self: *Book, dir: i32, dt: f32) void {
        if (self.page != .stats or self.picking != null or dir == 0) return;
        self.spin += @as(f32, @floatFromInt(dir)) * SPIN_RATE * dt;
    }

    pub fn zoomBy(self: *Book, dv: f32, dt: f32) void {
        if (!self.page.panned() or self.picking != null or dv == 0) return;
        if (self.page == .map) return self.lens.zoomBy(dv, dt);
        self.wheel.zoomBy(dv, dt);
    }

    pub fn panBy(self: *Book, v: rl.Vector2, dt: f32) void {
        if (!self.page.panned() or self.picking != null) return;
        if (self.page == .map) return self.lens.panBy(v, dt);
        self.wheel.panBy(v, dt);
    }

    pub fn wheelUp(self: *const Book) bool {
        return self.page.panned() and self.picking == null;
    }

    pub fn confirm(self: *Book, v: View) Action {
        if (self.picking) |s| {
            var buf: [CAND_MAX]Cand = undefined;
            const cs = candidates(s, v, &buf);
            if (self.pick >= cs.len) return .none;
            const act = cs[self.pick].act;
            self.picking = null;
            self.settled = false;
            self.thump();
            sfx.play(.item_get);
            return act;
        }
        switch (self.page) {
            .equipment => {
                const s: SlotId = @enumFromInt(self.cur[idx(.equipment)]);
                if (locked(s, v) != null) {
                    sfx.play(.menu_back);
                    return .none;
                }
                self.picking = s;
                self.pick = pickIndexOf(s, v);
                self.settled = false;
                sfx.play(.menu_pick);
            },
            .inventory => {
                if (bagAt(v, self.cur[idx(.inventory)])) |k| {
                    if (item.usable(k) and !v.inCombat) {
                        self.thump();
                        sfx.play(.menu_pick);
                        return .{ .use = k };
                    }
                }
                sfx.play(.menu_back);
            },
            .stats, .spells, .tree, .map => sfx.play(.menu_back),
        }
        return .none;
    }

    /// Stage a page for the shot harness, `ogre.stagger`'s pattern: a photograph of the picker open on the second candidate cannot be got by pretending to press buttons at 1/60 s a frame.
    pub fn debugShow(self: *Book, p: Page, cursor: usize, pickSlot: ?usize, row: usize) void {
        self.page = p;
        self.cur[idx(p)] = cursor;
        if (p == .tree) self.wheel.cursor = cursor;
        self.picking = if (pickSlot) |s| @enumFromInt(@min(s, NSLOT - 1)) else null;
        self.pick = row;
        self.settled = false;
        self.press = 0;
        self.pop = 0;
    }

    pub fn debugMap(self: *Book, v: View, zoom: f32, onHero: bool) void {
        self.page = .map;
        self.picking = null;
        self.settled = false;
        self.lens = .{ .zoom = zoom };
        if (onHero) self.onMap(v);
    }

    fn cursorRect(self: *const Book, v: View) rl.Rectangle {
        const body = bodyBox(cardBox());
        switch (self.page) {
            .equipment => {
                if (self.picking) |s| {
                    var buf: [CAND_MAX]Cand = undefined;
                    const cs = candidates(s, v, &buf);
                    return pickRow(pickBox(equipCols(body)[1], cs.len), self.pick, cs.len);
                }
                return slotRect(body, self.cur[idx(.equipment)]);
            },
            .inventory => {
                const g = bagGrid(body);
                return g.at(self.cur[idx(.inventory)] - self.scroll * BAG_COLS);
            },
            .stats => return attrRow(statsCols(body)[0], self.cur[idx(.stats)]),
            .spells => return spellRow(spellCols(body)[0], self.cur[idx(.spells)]),
            .tree => return ptree.nodeRect(self.wheel, body.x, body.y, body.w, body.h),
            .map => return .{ .x = 0, .y = 0, .width = 0, .height = 0 },
        }
    }

};

fn idx(p: Page) usize {
    return @intFromEnum(p);
}

fn grid(cur: usize, n: usize, cols: usize, dx: i32, dy: i32) usize {
    if (n == 0) return 0;
    const rows = (n + cols - 1) / cols;
    var col: i32 = @intCast(cur % cols);
    var row: i32 = @intCast(cur / cols);
    col = mathx.clampI(col + dx, 0, @as(i32, @intCast(cols)) - 1);
    row = mathx.clampI(row + dy, 0, @as(i32, @intCast(rows)) - 1);
    return @min(@as(usize, @intCast(row)) * cols + @as(usize, @intCast(col)), n - 1);
}


const PAD: i32 = 22;
const GUTTER: i32 = 18;
const BAG_COLS: usize = 5;
const BAG_ROWS: usize = 4;
const CELL_GAP: i32 = 12;

const fi = uiart.fi;
const rect = uiart.rect;

const Box = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    fn inset(b: Box, d: i32) Box {
        return .{ .x = b.x + d, .y = b.y + d, .w = b.w - d * 2, .h = b.h - d * 2 };
    }
    fn cut(b: Box, w: i32) [2]Box {
        return .{
            .{ .x = b.x, .y = b.y, .w = w, .h = b.h },
            .{ .x = b.x + w + GUTTER, .y = b.y, .w = b.w - w - GUTTER, .h = b.h },
        };
    }
    fn right(b: Box) i32 {
        return b.x + b.w;
    }
    fn cutDown(b: Box, h: i32) [2]Box {
        return .{
            .{ .x = b.x, .y = b.y, .w = b.w, .h = h },
            .{ .x = b.x, .y = b.y + h + GUTTER, .w = b.w, .h = b.h - h - GUTTER },
        };
    }
};

const Grid = struct {
    x: i32,
    y: i32,
    cw: i32,
    ch: i32,
    stepX: i32,
    stepY: i32,
    cols: usize,

    fn at(g: Grid, i: usize) rl.Rectangle {
        return rect(
            g.x + @as(i32, @intCast(i % g.cols)) * g.stepX,
            g.y + @as(i32, @intCast(i / g.cols)) * g.stepY,
            g.cw,
            g.ch,
        );
    }
};

fn titleH() i32 {
    return hud.lineH(hud.TINY) + 8;
}

fn panelInner(b: Box, titled: bool) Box {
    var inner = b.inset(14);
    if (titled) {
        inner.y = b.y + titleH() + 12;
        inner.h = b.h - (titleH() + 12) - 14;
    }
    return inner;
}

fn cardBox() Box {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const mx = @max(30, @divTrunc(sw, 18));
    const my = @max(26, @divTrunc(sh, 16));
    return .{ .x = mx, .y = my, .w = sw - mx * 2, .h = sh - my * 2 };
}

fn headH() i32 {
    return hud.lineH(hud.TITLE) + 20;
}

fn footH() i32 {
    return hud.lineH(hud.HINT) + 14;
}

fn bodyBox(card: Box) Box {
    return .{
        .x = card.x + PAD,
        .y = card.y + headH() + 8,
        .w = card.w - PAD * 2,
        .h = card.h - headH() - footH() - PAD,
    };
}

fn equipCols(body: Box) [2]Box {
    return body.cut(@divTrunc(body.w * 44, 100));
}

fn labelH() i32 {
    return hud.lineH(hud.TINY) + 2;
}

const SlotFit = struct { px: i32, gap: i32, brk: i32, x: i32, y: i32 };

fn slotFit(body: Box) SlotFit {
    const inner = panelInner(equipCols(body)[0], false);
    const byW = @divTrunc(inner.w * 7, SLOT_COLS * 7 + (SLOT_COLS - 1));
    const spare = inner.h - SLOT_ROWS * (labelH() + 6) - hud.lineH(hud.BODY) - 14;
    const byH = @divTrunc(spare * 3, SLOT_ROWS * 3 + 1);
    const px = mathx.clampI(@min(byW, byH), SLOT_MIN, SLOT_MAX);
    const gap = @max(4, @divTrunc(px, 7));
    const run = SLOT_COLS * px + (SLOT_COLS - 1) * gap;
    return .{
        .px = px,
        .gap = gap,
        .brk = @divTrunc(px, 3),
        .x = inner.x + @divTrunc(inner.w - run, 2),
        .y = inner.y + labelH(),
    };
}

fn slotRect(body: Box, i: usize) rl.Rectangle {
    const f = slotFit(body);
    const c = SLOT_CELL[i];
    return rect(
        f.x + c.col * (f.px + f.gap),
        f.y + c.row * (f.px + labelH() + 6) + (if (c.row >= 4) f.brk else 0),
        f.px,
        f.px,
    );
}

fn slotStep(cur: usize, dx: i32, dy: i32) usize {
    if (dx == 0 and dy == 0) return cur;
    const from = SLOT_CELL[cur];
    var best = cur;
    var score: i32 = std.math.maxInt(i32);
    for (SLOT_CELL, 0..) |c, i| {
        if (i == cur) continue;
        const ax = c.col - from.col;
        const ay = c.row - from.row;
        const along = ax * dx + ay * dy;
        if (along <= 0) continue;
        const cross: i32 = @intCast(@abs(ax * dy - ay * dx));
        const s = along + cross * 6;
        if (s < score) {
            score = s;
            best = i;
        }
    }
    return best;
}

fn pickRowH() i32 {
    return hud.lineH(hud.BODY) + 14;
}

fn derivedNeedH() i32 {
    const tallest: i32 = @intCast(@max(DER_SPLIT, ND - DER_SPLIT));
    return rowFloor() * tallest + hud.lineH(hud.TINY) + 6 + hud.lineH(hud.HINT) * 2 + 22 + 28;
}

fn pickBox(col: Box, n: usize) Box {
    const rows: i32 = @intCast(n);
    const want = pickRowH() * rows + titleH() + 24;
    const least = @min(@min(want, col.h), rowFloor() * rows + titleH() + 24);
    const room = @max(least, col.h - derivedNeedH() - GUTTER);
    return .{ .x = col.x, .y = col.y, .w = col.w, .h = @min(room, want) };
}

fn pickStep(box: Box, n: usize) i32 {
    return @min(pickRowH(), rowStep(panelInner(box, true).h, n));
}

fn pickSize(step: i32) i32 {
    if (step >= hud.lineH(hud.BODY)) return hud.BODY;
    if (step >= hud.lineH(hud.SMALL)) return hud.SMALL;
    return hud.TINY;
}

fn pickRow(box: Box, i: usize, n: usize) rl.Rectangle {
    const inner = panelInner(box, true);
    const step = pickStep(box, n);
    return rect(inner.x - 8, inner.y + @as(i32, @intCast(i)) * step - 6, inner.w + 16, step - 2);
}

fn bagCols(body: Box) [2]Box {
    return body.cut(@divTrunc(body.w * 54, 100));
}

fn bagGrid(body: Box) Grid {
    const inner = panelInner(bagCols(body)[0], true);
    const cell = @min(
        @divTrunc(inner.w - CELL_GAP * (@as(i32, BAG_COLS) - 1) - 10, @as(i32, BAG_COLS)),
        @divTrunc(inner.h - CELL_GAP * (@as(i32, BAG_ROWS) - 1), @as(i32, BAG_ROWS)),
    );
    return .{
        .x = inner.x,
        .y = inner.y,
        .cw = cell,
        .ch = cell,
        .stepX = cell + CELL_GAP,
        .stepY = cell + CELL_GAP,
        .cols = BAG_COLS,
    };
}

/// FOUR PANELS, ER's status screen read left to right: the attributes, the body (vitals, attack, defence), the wards (resistance, ailments, passives), and the man himself.
fn statsCols(body: Box) [4]Box {
    const portW = @min(@divTrunc(body.w * 28, 100), 400);
    const rest = body.cut(body.w - portW - GUTTER);
    const attrW = @divTrunc((rest[0].w - GUTTER * 2) * 36, 100);
    const left = rest[0].cut(attrW);
    const two = left[1].cut(@divTrunc(left[1].w - GUTTER, 2));
    return .{ left[0], two[0], two[1], rest[1] };
}

fn attrStep() i32 {
    return hud.lineH(hud.BODY) + 16;
}

fn spellCols(body: Box) [2]Box {
    return body.cut(@divTrunc(body.w * 46, 100));
}

fn spellStep() i32 {
    return hud.lineH(hud.BODY) + 14;
}

fn spellRow(col: Box, i: usize) rl.Rectangle {
    const inner = panelInner(col, true);
    return rect(inner.x - 10, inner.y + @as(i32, @intCast(i)) * spellStep() - 6, inner.w + 20, spellStep() - 4);
}

fn attrRow(col: Box, i: usize) rl.Rectangle {
    const inner = panelInner(col, true);
    return rect(inner.x - 10, inner.y + @as(i32, @intCast(i)) * attrStep() - 6, inner.w + 20, attrStep() - 4);
}


const fmt = hud.fmt;

var saysBuf: [256]u8 = undefined;

fn saysOwn(s: []const u8) [:0]const u8 {
    const n = @min(s.len, saysBuf.len - 1);
    @memcpy(saysBuf[0..n], s[0..n]);
    saysBuf[n] = 0;
    return saysBuf[0..n :0];
}

var heldBuf: [256]u8 = undefined;

fn saysHeld(s: []const u8) [:0]const u8 {
    const n = @min(s.len, heldBuf.len - 1);
    @memcpy(heldBuf[0..n], s[0..n]);
    heldBuf[n] = 0;
    return heldBuf[0..n :0];
}

/// **THE PURSE IS A MIRROR, NOT A STACK.** Gold is a `u32` on the hero and `item.Bag`'s counts are `u16`, so it
/// could not live in the bag if it wanted to: it stands in the first cell and what the bag really holds follows it.
fn bagCells(v: View) usize {
    return v.bag.distinct() + 1;
}

fn bagAt(v: View, i: usize) ?item.Kind {
    return if (i == 0) .gold_purse else v.bag.nth(i - 1);
}

fn heldOf(v: View, k: item.Kind) u32 {
    return if (k == .gold_purse) v.gold else v.bag.count(k);
}

/// Both purses, where the tab strip used to carry the souls alone. `notAbove` keeps the line clear of whatever
/// the page has already written down there — the doll's panel is only as tall as the window is.
fn drawWealth(inner: Box, v: View, notAbove: i32) void {
    const souls = fmt("{d}", .{v.souls});
    const gold = fmt("{d}", .{v.gold});
    const gap: i32 = 22;
    const markW: i32 = 15;
    const w = (markW + hud.textW(souls, hud.BODY)) + gap + (markW + hud.textW(gold, hud.BODY));
    var x = inner.x + @divTrunc(inner.w - w, 2);
    const y = @max(inner.y + inner.h - hud.lineH(hud.BODY), notAbove);
    const mid = fi(y) + fi(hud.lineH(hud.BODY)) * 0.5;
    uiart.soulMark(fi(x) + 5, mid, uiart.MARK_R * 0.86, 225);
    x += markW;
    hud.text(souls, x, y, hud.BODY, uiart.TEXT_VALUE);
    x += hud.textW(souls, hud.BODY) + gap;
    uiart.coinMark(fi(x) + 5, mid, uiart.MARK_R * 0.86, 225);
    x += markW;
    hud.text(gold, x, y, hud.BODY, uiart.TEXT_VALUE);
}

fn panel(b: Box, title: [:0]const u8) Box {
    uiart.well(b.x, b.y, b.w, b.h, 210);
    rl.drawRectangleLinesEx(rect(b.x, b.y, b.w, b.h), 1, mathx.withAlpha(uiart.GILT_DIM, 90));
    if (title.len > 0) {
        hud.text(title, b.x + 14, b.y + 8, hud.TINY, mathx.withAlpha(uiart.GILT, 220));
        rl.drawRectangle(b.x + 14, b.y + titleH() + 2, b.w - 28, 1, mathx.withAlpha(uiart.GILT_DIM, 80));
    }
    return panelInner(b, title.len > 0);
}

/// Their natural pitch, tightened to fit, and NEVER under the GLYPH height: too short spills off the bottom, where a NEGATIVE pitch stacks them backwards up through the heading.
fn rowStep(space: i32, n: usize) i32 {
    const natural = hud.lineH(hud.SMALL) + 7;
    // A picker CAN be open on a slot with nothing to offer (`candidates` returns an empty slice for a locked one), and that reaches here through `pickStep` as a divide by zero.
    return mathx.clampI(@divTrunc(space, @as(i32, @intCast(@max(n, 1)))), rowFloor(), natural);
}

fn rowFloor() i32 {
    return hud.TINY + 1;
}

fn rowSize(step: i32) i32 {
    return if (step >= hud.lineH(hud.SMALL)) hud.SMALL else hud.TINY;
}

fn rowLabel(s: [:0]const u8, x: i32, y: i32, col: rl.Color) void {
    rowLabelAt(s, x, y, hud.SMALL, col);
}

fn rowLabelAt(s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
    hud.text(s, x, y, size, col);
}

fn rowValue(s: [:0]const u8, right: i32, y: i32, col: rl.Color) void {
    rowValueAt(s, right, y, hud.SMALL, col);
}

fn rowValueAt(s: [:0]const u8, right: i32, y: i32, size: i32, col: rl.Color) void {
    hud.text(s, right - hud.textW(s, size), y, size, col);
}

fn unitStr(u: Unit, x: f32) [:0]const u8 {
    return switch (u) {
        .flat => if (@abs(x) <= 0.005) "-" else fmt("{d:.0}", .{x}),
        .pct => if (@abs(x) <= 0.005) "-" else fmt("{d:.0}%", .{x}),
        .count => fmt("{d:.0}", .{x}),
        // Two places: the six strokes run 0.34 s to 1.02 s and a tenth of a second is the whole gap between two of them.
        .secs => if (x <= 0.0005) "-" else fmt("{d:.2}s", .{x}),
    };
}

pub fn draw(self: *const Book, v: View, portrait: ?Portrait) void {
    const card = cardBox();
    uiart.seat(card.x, card.y, card.w, card.h);
    uiart.plate(card.x, card.y, card.w, card.h, 236);
    uiart.frame(card.x, card.y, card.w, card.h, uiart.flick(200, card.x));

    drawTabs(self, card);
    const body = bodyBox(card);
    switch (self.page) {
        .equipment => drawEquipment(self, body, v),
        .inventory => drawInventory(self, body, v),
        .stats => drawStats(self, body, v, portrait),
        .spells => drawSpells(self, body, v),
        .tree => drawTree(self, body, v),
        .map => mapart.draw(body.x, body.y, body.w, body.h, v.world, self.lens),
    }

    if (self.at.width > 1 and !self.page.panned()) {
        uiart.slotCursor(
            @intFromFloat(self.at.x),
            @intFromFloat(self.at.y),
            @intFromFloat(self.at.width),
            @intFromFloat(self.at.height),
            self.press,
            1.0,
        );
    }

    var buf: [FOOT_CAP]hud.Hint = undefined;
    const hints = footHints(self, &buf);
    const hw = hud.hintRowW(hints, hud.HINT);
    hud.hintRowAt(
        hints,
        card.x + @divTrunc(card.w - hw, 2),
        card.y + card.h - footH() + 2 + @divTrunc(hud.lineH(hud.HINT), 2),
        hud.HINT,
        uiart.TEXT_HINT,
    );
}


/// THE CRIB IS A FUNCTION, NOT A LIMB OF `draw`: a page that pans must name both gestures, and a test now walks every page.
pub const FOOT_CAP: usize = 6;

fn footHints(self: *const Book, buf: *[FOOT_CAP]hud.Hint) []const hud.Hint {
    const PAGE = hud.Hint{ .glyph = .{ .bumper = "LB/RB" }, .label = "Page" };
    const CLOSE = hud.Hint{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Close" };
    const READ = hud.Hint{ .glyph = .{ .dpad = .updown }, .label = "Read" };
    const CANCEL = hud.HINT_CANCEL;
    return switch (self.page) {
        .equipment => if (self.picking) |ps| blk: {
            buf.*[0] = hud.HINT_CHOOSE;
            buf.*[1] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = if (quickIndex(ps) != null) "Socket" else "Equip" };
            buf.*[2] = CANCEL;
            break :blk buf.*[0..3];
        } else blk: {
            buf.*[0] = hud.HINT_MOVE;
            buf.*[1] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Open" };
            buf.*[2] = PAGE;
            buf.*[3] = CLOSE;
            break :blk buf.*[0..4];
        },
        .inventory => blk: {
            buf.*[0] = hud.HINT_MOVE;
            buf.*[1] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Use" };
            buf.*[2] = PAGE;
            buf.*[3] = CLOSE;
            break :blk buf.*[0..4];
        },
        .stats => blk: {
            buf.*[0] = READ;
            buf.*[1] = .{ .glyph = .{ .dpad = .leftright }, .label = "Turn" };
            buf.*[2] = PAGE;
            buf.*[3] = CLOSE;
            break :blk buf.*[0..4];
        },
        .spells => blk: {
            buf.*[0] = READ;
            buf.*[1] = PAGE;
            buf.*[2] = CLOSE;
            break :blk buf.*[0..3];
        },
        .tree => blk: {
            buf.*[0] = hud.HINT_WALK;
            buf.*[1] = hud.HINT_PAN;
            buf.*[2] = hud.HINT_ZOOM;
            buf.*[3] = PAGE;
            buf.*[4] = CLOSE;
            break :blk buf.*[0..5];
        },
        .map => blk: {
            buf.*[0] = hud.HINT_PAN;
            buf.*[1] = hud.HINT_ZOOM;
            buf.*[2] = PAGE;
            buf.*[3] = CLOSE;
            break :blk buf.*[0..4];
        },
    };
}

const TAB_GAP_MIN: i32 = 26;

fn drawTabs(self: *const Book, card: Box) void {
    const y = card.y + 12;
    var w: [NPAGE]i32 = undefined;
    var total: i32 = 0;
    inline for (0..NPAGE) |i| {
        const p: Page = @enumFromInt(i);
        w[i] = hud.textW(p.label(), hud.TITLE);
        total += w[i];
    }
    const room = card.w - PAD * 2;
    const gap: i32 = @max(TAB_GAP_MIN, @divTrunc(room - total, @as(i32, NPAGE) + 1));
    var x = card.x + PAD + @divTrunc(room - (total + gap * (@as(i32, NPAGE) - 1)), 2);
    inline for (0..NPAGE) |i| {
        const p: Page = @enumFromInt(i);
        if (self.page == p) {
            hud.engraved(p.label(), x, y, hud.TITLE, uiart.TEXT_TITLE);
            const uy = y + hud.lineH(hud.TITLE) - 4;
            rl.drawRectangle(x - 6, uy, w[i] + 12, 2, mathx.withAlpha(uiart.GILT, 210));
            uiart.diamond(fi(x - 15), fi(uy) + 1, 3.0, uiart.GILT_BRIGHT);
            uiart.diamond(fi(x + w[i] + 15), fi(uy) + 1, 3.0, uiart.GILT_BRIGHT);
        } else {
            hud.text(p.label(), x, y, hud.TITLE, mathx.withAlpha(uiart.TEXT_DIM, 140));
        }
        x += w[i] + gap;
    }
    uiart.divider(card.x + @divTrunc(card.w, 2), card.y + headH(), @divTrunc(card.w, 2) - 30, 170);
}


fn drawEquipment(self: *const Book, body: Box, v: View) void {
    const cols = equipCols(body);
    const inner = panel(cols[0], "");
    const cur = self.cur[idx(.equipment)];
    for (0..NSLOT) |i| {
        drawSlot(self, slotRect(body, i), @enumFromInt(i), v, cur == i and self.picking == null);
    }
    const on: SlotId = @enumFromInt(if (self.picking) |s| @intFromEnum(s) else cur);
    const name = slotFilled(on, v);
    const q = slotRect(body, NSLOT - 1);
    const nameY = @as(i32, @intFromFloat(q.y + q.height)) + 12;
    hud.text(
        name,
        inner.x + @divTrunc(inner.w - hud.textW(name, hud.BODY), 2),
        nameY,
        hud.BODY,
        uiart.HOT,
    );
    drawWealth(inner, v, nameY + hud.lineH(hud.BODY) + 6);

    var buf: [CAND_MAX]Cand = undefined;
    const cs = if (self.picking) |s| candidates(s, v, &buf) else buf[0..0];
    if (self.picking) |s| drawPicker(self, cols[1], s, v);
    const cand: ?Cand = if (self.pick < cs.len) cs[self.pick] else null;
    const box = derivedBox(body, cs.len);
    if (cand) |c| {
        if (facing(v, c)) |f| return drawGearCompare(box, v, c, f);
    }
    if (self.picking == null) {
        if (browsing(on, v)) |f| {
            const says = saysHeld(pieceSays(f.now, f.socket));
            const parts = box.cutDown(cardBoxIn(box, v, f, says).h);
            drawGearCard(parts[0], v, f, says);
            return drawDerived(parts[1], v, cand);
        }
    }
    drawDerived(box, v, cand);
}

fn derivedBox(body: Box, cands: usize) Box {
    const col = equipCols(body)[1];
    if (cands == 0) return col;
    const top = pickBox(col, cands);
    return .{ .x = col.x, .y = top.y + top.h + GUTTER, .w = col.w, .h = col.h - top.h - GUTTER };
}

fn drawSlot(self: *const Book, r: rl.Rectangle, s: SlotId, v: View, sel: bool) void {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    const h: i32 = @intFromFloat(r.height);
    const on = slotHas(s, v);
    const sink: i32 = if (sel) @intFromFloat(@round(self.press * 2.0)) else 0;
    const pop = if (sel) self.pop / POP_DUR else 0;
    const sy = y + sink - @as(i32, @intFromFloat(@round(pop * pop * 3.0)));

    const inert = locked(s, v) != null;
    const lab: u8 = if (sel) 235 else if (inert) 70 else 150;
    const nm = slotName(s);
    hud.text(nm, x + @divTrunc(w - hud.textW(nm, hud.TINY), 2), y - hud.lineH(hud.TINY) - 2, hud.TINY, mathx.withAlpha(uiart.TEXT_DIM, lab));
    uiart.slot(x, sy, w, h, on);
    if (inert) rl.drawRectangle(x, sy, w, h, mathx.withAlpha(rl.Color.black, 110));
    if (sel) uiart.sheen(rect(x, sy, w, h), 3.4, 22);
    if (pop > 0) rl.drawRectangleLinesEx(rect(x - 1, sy - 1, w + 2, h + 2), 2, mathx.withAlpha(uiart.GILT_BRIGHT, mathx.u8f(200.0 * pop)));

    const lift: f32 = if (sel) 2.0 - self.press * 3.0 else 0;
    drawSlotArt(s, v, fi(x + @divTrunc(w, 2)), fi(sy + @divTrunc(h, 2)) - lift, fi(@min(w, h)) * 0.84);

    if (slotTally(s, v)) |n| hud.tally(fmt("{d}", .{n}), x + w, sy + h, hud.SMALL, if (n > 0) uiart.TEXT_VALUE else uiart.BAD);
}

fn drawSlotArt(s: SlotId, v: View, cx: f32, cy: f32, px: f32) void {
    if (wearOf(s)) |w| return if (v.worn.at(w)) |k| itemart.drawHeld(k, cx, cy, px, true);
    switch (s) {
        .right => handArt(v.arm, v.worn, cx, cy, px),
        .left => if (v.offInHand()) handArt(v.off, v.worn, cx, cy, px),
        .right2 => handArt(v.armAlt, v.worn, cx, cy, px),
        .left2 => handArt(v.offAlt, v.worn, cx, cy, px),
        .sorcery => if (slotHas(.sorcery, v)) itemart.spellArt(v.spell, cx, cy, px, v.fp >= castFp(v.spell, v.tree.bonus())),
        // A shaft is drawn 0.3 of the box it is handed where a blade is 1.4, so it is given a bigger one.
        .arrows => itemart.arrow(cx, cy, px * 1.5, v.quiver.count(v.quiver.sel) > 0, v.quiver.sel == .fire),
        else => if (quickAt(s, v)) |k| itemart.drawHeld(k, cx, cy, px, quickTally(k, v) > 0),
    }
}

fn handArt(a: heromod.Armament, worn: heromod.Worn, cx: f32, cy: f32, px: f32) void {
    itemart.heldArt(armPic(a), heromod.heldGear(a, worn), cx, cy, px);
}

const GDial = enum {
    dmg_light,
    dmg_heavy,
    swing,
    poise,
    stance,
    venom,
    negate,
    arc,
    armour,
    res_fire,
    res_cold,
    res_lightning,
    res_chaos,
    rate_poison,
    rate_burning,
    rate_chill,
    rate_stun,
    rate_bleed,
    rate_sleep,
    rate_confusion,
    rate_charm,
    rate_berserk,
    rate_stupefy,
    walk,
    leech,
    hp_frac,
    spirit_fp,
    fp_frac,
    boon,
};

const NGD = @typeInfo(GDial).@"enum".fields.len;

const GROW = blk: {
    var rows = [_]DerivedRow{.{ .name = "", .unit = .flat }} ** NGD;
    rows[@intFromEnum(GDial.dmg_light)] = .{ .name = "Light attack", .unit = .flat };
    rows[@intFromEnum(GDial.dmg_heavy)] = .{ .name = "Heavy attack", .unit = .flat };
    rows[@intFromEnum(GDial.swing)] = .{ .name = "Swing time", .unit = .secs, .cost = true };
    rows[@intFromEnum(GDial.poise)] = .{ .name = "Poise damage", .unit = .flat };
    rows[@intFromEnum(GDial.stance)] = .{ .name = "Stance damage", .unit = .flat };
    rows[@intFromEnum(GDial.venom)] = .{ .name = "Poison a hit", .unit = .flat };
    rows[@intFromEnum(GDial.negate)] = .{ .name = "Guard negation", .unit = .pct };
    rows[@intFromEnum(GDial.arc)] = .{ .name = "Guard arc", .unit = .flat };
    rows[@intFromEnum(GDial.armour)] = .{ .name = "Armour", .unit = .flat };
    rows[@intFromEnum(GDial.res_fire)] = .{ .name = "Fire resistance", .unit = .pct };
    rows[@intFromEnum(GDial.res_cold)] = .{ .name = "Cold resistance", .unit = .pct };
    rows[@intFromEnum(GDial.res_lightning)] = .{ .name = "Lightning resistance", .unit = .pct };
    rows[@intFromEnum(GDial.res_chaos)] = .{ .name = "Chaos resistance", .unit = .pct };
    for (0..combat.NAIL) |i| {
        rows[@intFromEnum(GDial.rate_poison) + i] = .{ .name = combat.ailName(@enumFromInt(i)) ++ " fills at", .unit = .pct, .cost = true };
    }
    rows[@intFromEnum(GDial.walk)] = .{ .name = "Walk speed", .unit = .pct };
    rows[@intFromEnum(GDial.leech)] = .{ .name = "HP a swing landed", .unit = .flat };
    rows[@intFromEnum(GDial.hp_frac)] = .{ .name = "Max HP", .unit = .pct };
    rows[@intFromEnum(GDial.spirit_fp)] = .{ .name = "Spirit costs", .unit = .pct, .cost = true };
    rows[@intFromEnum(GDial.fp_frac)] = .{ .name = "Max Focus", .unit = .pct };
    rows[@intFromEnum(GDial.boon)] = .{ .name = "Attribute", .unit = .flat };
    for (rows, 0..) |r, i| {
        if (r.name.len == 0) @compileError("book: `GDial." ++ @typeInfo(GDial).@"enum".fields[i].name ++
            "` has no row — the picker would print a number with no name beside it");
    }
    break :blk rows;
};

const Dials = struct {
    v: [NGD]?f32 = [_]?f32{null} ** NGD,
    boonName: ?[:0]const u8 = null,

    fn set(self: *Dials, d: GDial, x: f32) void {
        self.v[@intFromEnum(d)] = x;
    }
    fn setAt(self: *Dials, i: usize, x: f32) void {
        self.v[i] = x;
    }
};

fn rateDial(a: combat.Ail) usize {
    return @intFromEnum(GDial.rate_poison) + @intFromEnum(a);
}

comptime {
    if (@intFromEnum(GDial.rate_stupefy) - @intFromEnum(GDial.rate_poison) != combat.NAIL - 1)
        @compileError("book: the `rate_*` dials are not one contiguous run of `combat.NAIL` — `rateDial` indexes off the first");
}

/// THE DIALS ARE READ IN SECTIONS, ER's way: a weapon's numbers under ATTACK, a board's under GUARD, a coat's under DEFENCE and RESISTANCE, and what it does to HIM under BODY. The switch is exhaustive, so a dial added without a home does not compile; `GDial` lists them in section order, which is what lets one pass insert the heads.
const GSection = enum { attack, guard, defence, resistance, ailments, body };
const NGS = @typeInfo(GSection).@"enum".fields.len;

fn gsectionOf(d: GDial) GSection {
    return switch (d) {
        .dmg_light, .dmg_heavy, .swing, .poise, .stance, .venom => .attack,
        .negate, .arc => .guard,
        .armour => .defence,
        .res_fire, .res_cold, .res_lightning, .res_chaos => .resistance,
        .rate_poison, .rate_burning, .rate_chill, .rate_stun, .rate_bleed, .rate_sleep, .rate_confusion, .rate_charm, .rate_berserk, .rate_stupefy => .ailments,
        .walk, .leech, .hp_frac, .spirit_fp, .fp_frac, .boon => .body,
    };
}

fn gsectionName(s: GSection) [:0]const u8 {
    return switch (s) {
        .attack => "ATTACK",
        .guard => "GUARD",
        .defence => "DEFENCE",
        .resistance => "RESISTANCE",
        .ailments => "AILMENTS",
        .body => "BODY",
    };
}

/// Whether two readings of one dial are DIFFERENT to a reader: a whole unit on a counted number, a hundredth on a clock.
fn moves(u: Unit, a: f32, b: f32) bool {
    const d = @abs(b - a);
    return switch (u) {
        .secs => d >= 0.005,
        .flat, .pct, .count => d >= 0.5,
    };
}

/// "+12", "-3", "+35%", "+0.08s": what a swap does to one number, with its sign.
fn deltaStr(u: Unit, a: f32, b: f32) [:0]const u8 {
    const d = b - a;
    const sign: []const u8 = if (d >= 0) "+" else "-";
    const m = @abs(d);
    return switch (u) {
        .pct => fmt("{s}{d:.0}%", .{ sign, m }),
        .secs => fmt("{s}{d:.2}s", .{ sign, m }),
        .flat, .count => fmt("{s}{d:.0}", .{ sign, m }),
    };
}

fn sectH() i32 {
    return hud.lineH(hud.TINY) + 8;
}

/// A section head: the title in small gilt caps, and a rule running from it to the panel's edge.
fn head(inner: Box, y: i32, title: [:0]const u8) i32 {
    const tw = hud.textW(title, hud.TINY);
    const ty = y + 4;
    hud.text(title, inner.x, ty, hud.TINY, mathx.withAlpha(uiart.GILT, 210));
    uiart.rule(inner.x + tw + 10, ty + @divTrunc(hud.lineH(hud.TINY), 2), inner.w - tw - 10, 110);
    return ty + hud.lineH(hud.TINY) + 4;
}

/// Where a comparison's four columns fall: the label at the left edge, NOW a quarter in from THEN, THEN clear of the difference, the difference at the right edge.
const Cols = struct { label: i32, now: i32, then: i32, delta: i32 };

fn colsFor(inner: Box) Cols {
    const dW = hud.textW("+100%", hud.TINY) + 8;
    const then = inner.right() - dW;
    return .{ .label = inner.x, .now = then - @divTrunc(inner.w, 4), .then = then, .delta = inner.right() };
}

fn unitStrOpt(u: Unit, x: ?f32) [:0]const u8 {
    return unitStr(u, x orelse 0);
}

/// One line of a comparison: the label, NOW dim, a chevron when it moves, THEN in the colour of the news, and the difference at the edge.
fn cmpRow(cols: Cols, y: i32, size: i32, label: [:0]const u8, u: Unit, av: ?f32, bv: ?f32, cost: bool, comptime show: fn (Unit, ?f32) [:0]const u8) void {
    const a = av orelse 0;
    const b = bv orelse 0;
    const moved = moves(u, a, b);
    rowLabelAt(label, cols.label, y, size, if (moved) uiart.TEXT_VALUE else uiart.TEXT_DIM);
    rowValueAt(show(u, av), cols.now, y, size, mathx.withAlpha(uiart.TEXT_DIM, 200));
    const rose = b > a;
    const col = if (!moved) uiart.TEXT_DIM else if (rose != cost) uiart.GOOD else uiart.BAD;
    rowValueAt(show(u, bv), cols.then, y, size, col);
    if (moved) {
        uiart.arrow(fi(cols.now + 14), fi(y) + fi(hud.lineH(size)) * 0.5, 5.0, mathx.withAlpha(col, 200));
        rowValueAt(deltaStr(u, a, b), cols.delta, y, hud.TINY, col);
    }
}

fn scalingTag(sc: item.Scaling) [:0]const u8 {
    return switch (sc) {
        .strength => stats.displayName(.strength),
        .dexterity => stats.displayName(.dexterity),
        .quality => "Quality",
    };
}

/// The words a piece wears on its sleeve: heft, reach and what drives it for an arm; the shelf it came off for anything else.
fn tagsOf(k: ?item.Kind, socket: ?item.Wear, out: *[5][:0]const u8) []const [:0]const u8 {
    var n: usize = 0;
    if (armIn(k, socket)) |a| {
        out[n] = a.heft.label();
        n += 1;
        out[n] = a.reach.label();
        n += 1;
        if (a.slot == .hand_shield) {
            out[n] = "Board";
            n += 1;
        } else {
            out[n] = scalingTag(a.scales);
            n += 1;
        }
        if (a.slot == .hand_bow) {
            out[n] = "Two-handed";
            n += 1;
        }
        if (a.venom > 0) {
            out[n] = "Coated";
            n += 1;
        }
        return out[0..n];
    }
    if (k) |kk| {
        out[0] = item.class(kk).label();
        return out[0..1];
    }
    return out[0..0];
}

fn tagsW(tags: []const [:0]const u8) i32 {
    var w: i32 = 0;
    for (tags, 0..) |t, i| w += hud.textW(t, hud.TINY) + 12 + (if (i > 0) @as(i32, 6) else 0);
    return w;
}

fn drawTags(x: i32, y: i32, tags: []const [:0]const u8) i32 {
    var cx = x;
    for (tags) |t| {
        const w = hud.textW(t, hud.TINY) + 12;
        uiart.pill(cx, y, w, hud.lineH(hud.TINY) + 2, 150);
        hud.text(t, cx + 6, y + 1, hud.TINY, mathx.withAlpha(uiart.TEXT_VALUE, 210));
        cx += w + 6;
    }
    return cx;
}

fn tagRowH() i32 {
    return hud.lineH(hud.TINY) + 10;
}

fn nowNameOf(f: Facing) [:0]const u8 {
    return f.nowName;
}

/// THE ONE NUMBER A PICKER ROW LEADS WITH: the sheet figure the swap moves most, as a share of what it is now, signed and named short. Resistances are left to the compare — they are never the headline of a coat.
const HEADLINE_ROWS = [_]Der{ .light, .heavy, .elem, .spell, .quick, .ammo, .hp, .fp, .armour, .negate, .guard };
const Headline = struct { text: [:0]const u8, good: bool };

fn headline(c: Cand, v: View, base: Loadout, now: [ND]f32) ?Headline {
    const then = derive(withCand(base, c), v);
    var best: ?Der = null;
    var bestShare: f32 = 0;
    for (HEADLINE_ROWS) |k| {
        const i = @intFromEnum(k);
        if (!moves(DER[i].unit, now[i], then[i])) continue;
        const share = @abs(then[i] - now[i]) / @max(@abs(now[i]), 1.0);
        if (best == null or share > bestShare) {
            bestShare = share;
            best = k;
        }
    }
    const k = best orelse return null;
    const i = @intFromEnum(k);
    const row = DER[i];
    const short = if (row.short.len > 0) row.short else row.name;
    return .{ .text = fmt("{s} {s}", .{ deltaStr(row.unit, now[i], then[i]), short }), .good = (then[i] > now[i]) != row.cost };
}

fn armInSocket(w: item.Wear) ?heromod.Armament {
    for (0..heromod.NARM) |i| {
        const a: heromod.Armament = @enumFromInt(i);
        if (heromod.wearFor(a)) |ww| {
            if (ww == w) return a;
        }
    }
    return null;
}

/// STANCE comes off the HEAVY: a light stroke carries none (`hero.ATK_LIGHT_HIT`), and the row would read 0.
fn setBlow(d: *Dials, lightHit: combat.Hit, heavyHit: combat.Hit, row: item.Arm, sheet: stats.Sheet, tier: u8) void {
    const lo = heromod.weigh(lightHit, row, sheet, tier);
    const hi = heromod.weigh(heavyHit, row, sheet, tier);
    d.set(.dmg_light, lo.dmg);
    d.set(.dmg_heavy, hi.dmg);
    d.set(.poise, hi.poise);
    d.set(.stance, hi.stance);
}

fn equipIn(k: ?item.Kind, socket: ?item.Wear) item.Equip {
    if (k) |kk| return item.equip(kk);
    const w = socket orelse return .none;
    return if (w.held()) item.Equip{ .arm = item.bareArm(w) } else .none;
}

fn armIn(k: ?item.Kind, socket: ?item.Wear) ?item.Arm {
    return switch (equipIn(k, socket)) {
        .arm => |a| a,
        else => null,
    };
}

fn scalingWords(sc: item.Scaling) [:0]const u8 {
    return switch (sc) {
        .strength => stats.displayName(.strength),
        .dexterity => stats.displayName(.dexterity),
        .quality => QUALITY_WORDS,
    };
}
const QUALITY_WORDS: [:0]const u8 = stats.displayName(.strength) ++ " and " ++ stats.displayName(.dexterity) ++ " both";

fn armWords(k: ?item.Kind, socket: ?item.Wear) [:0]const u8 {
    const a = armIn(k, socket) orelse return "";
    if (a.slot == .hand_shield) return fmt("{s} {s}. A board to stand behind, and slower on your feet for it.", .{ a.heft.label(), a.reach.label() });
    if (a.venom > 0) return fmt("{s} {s}, driven by {s}. The edge is coated.", .{ a.heft.label(), a.reach.label(), scalingWords(a.scales) });
    return fmt("{s} {s}, driven by {s}.", .{ a.heft.label(), a.reach.label(), scalingWords(a.scales) });
}

fn pieceSays(k: ?item.Kind, socket: ?item.Wear) []const u8 {
    if (armIn(k, socket) != null) return armWords(k, socket);
    if (k) |kk| return rowSays(kk);
    const w = socket orelse return "";
    return emptyHanded(w);
}

fn dialsOf(k: ?item.Kind, socket: ?item.Wear, v: View) Dials {
    var d = Dials{};
    const eq = equipIn(k, socket);
    const perk = v.tree.bonus();
    switch (eq) {
        .none, .bind => {},
        .arm => |a| {
            if (a.slot == .hand_bow) {
                setBlow(&d, heromod.arrowBlow(v.quiver.sel, false, perk), heromod.arrowBlow(v.quiver.sel, true, perk), a, v.sheet.*, v.tierOf(.bow));
                d.set(.swing, heromod.drawSecs(true, a));
            } else if (heromod.bladeForWear(a.slot)) |b| {
                setBlow(&d, heromod.ATK_LIGHT_HIT, heromod.ATK_HEAVY_HIT, a, v.sheet.*, v.tierOf(armInSocket(a.slot) orelse .sword));
                d.set(.swing, heromod.swingSecs(b, true, a));
            }
            if (a.venom > 0) d.set(.venom, a.venom);
            if (a.slot == .hand_shield) {
                d.set(.negate, combat.guardNegation(a.negate, perk.guard) * 100);
                d.set(.arc, combat.GUARD_ARC * a.arc);
                d.set(.walk, a.walk * 100);
            }
        },
        .plate => |pl| {
            d.set(.armour, pl.a);
            if (pl.res.fire != 0) d.set(.res_fire, pl.res.fire);
            if (pl.res.cold != 0) d.set(.res_cold, pl.res.cold);
            if (pl.res.lightning != 0) d.set(.res_lightning, pl.res.lightning);
            if (pl.res.chaos != 0) d.set(.res_chaos, pl.res.chaos);
            if (pl.rate) |r| d.setAt(rateDial(combat.ailOfName(r.ail)), r.k * 100);
            if (pl.move != 1) d.set(.walk, pl.move * 100);
        },
        .charm => |c| {
            if (c.leech != 0) d.set(.leech, c.leech);
            if (c.hpFrac != 0) d.set(.hp_frac, (1.0 - c.hpFrac) * 100);
            if (c.spiritFp != 1) d.set(.spirit_fp, c.spiritFp * 100);
            if (c.fpFrac != 0) d.set(.fp_frac, (1.0 - c.fpFrac) * 100);
        },
        .boon => |b| {
            d.set(.boon, @floatFromInt(b.n));
            d.boonName = stats.displayName(b.attr);
        },
    }
    return d;
}

/// `socket` is the CANDIDATE's class — the dials are read within it — while `nowName` is what is actually in the hand or on the body, which is not the same thing when a sword is being swapped for a dirk.
const Facing = struct { now: ?item.Kind, then: ?item.Kind, socket: ?item.Wear, nowName: [:0]const u8 };

fn wornName(v: View, w: item.Wear) [:0]const u8 {
    if (v.worn.at(w)) |k| return item.displayName(k);
    if (armInSocket(w)) |a| return armName(a);
    return "Nothing";
}

fn liveName(live: heromod.Armament, worn: heromod.Worn) [:0]const u8 {
    if (heromod.heldGear(live, worn)) |k| return item.displayName(k);
    return armName(live);
}

fn facing(v: View, c: Cand) ?Facing {
    const held = struct {
        fn of(live: heromod.Armament, h: Hand, w: heromod.Worn) Facing {
            return .{
                .now = heromod.heldGear(live, w),
                .then = h.kind,
                .socket = heromod.wearFor(h.a) orelse heromod.wearFor(live),
                .nowName = liveName(live, w),
            };
        }
    }.of;
    return switch (c.act) {
        .arm => |h| held(v.arm, h, v.worn),
        .off => |h| held(v.off, h, v.worn),
        .armAlt => |h| held(v.armAlt, h, v.worn),
        .offAlt => |h| held(v.offAlt, h, v.worn),
        .wear => |wr| .{ .now = v.worn.at(wr.slot), .then = wr.kind, .socket = wr.slot, .nowName = wornName(v, wr.slot) },
        else => null,
    };
}

/// **ALWAYS THE NUMBER, NEVER A DASH** — `unitStr` hides a zero, and a zero facing a 26 is the comparison.
fn dialStr(u: Unit, x: ?f32) [:0]const u8 {
    const val = x orelse return "-";
    return switch (u) {
        .pct => fmt("{d:.0}%", .{val}),
        .secs => fmt("{d:.2}s", .{val}),
        else => fmt("{d:.0}", .{val}),
    };
}

/// How many of the sheet's moving rows the compare shows under ON THE SHEET before it runs out of panel.
const SHEET_ROWS_MAX: usize = 6;

/// THE COMPARE, ER's way: the two names across the top, the candidate's tags under its own name, the piece's dials in sections with NOW, a chevron, THEN and the difference, then ON THE SHEET — every derived figure the swap moves, so a boon's +3 Strength is read as the damage it buys.
fn drawGearCompare(box: Box, v: View, c: Cand, f: Facing) void {
    const inner = panel(box, "");
    const a = dialsOf(f.now, f.socket, v);
    const b = dialsOf(f.then, f.socket, v);
    const base = inForce(v);
    const now = derive(base, v);
    const then = derive(withCand(base, c), v);

    // ONLY THE DIALS THAT CHANGE, or appear, or go — a like-for-like swap (the dirk for the dirk) falls back to reading the piece whole, so the card is never blank.
    var show = [_]bool{false} ** NGD;
    var shown: usize = 0;
    for (0..NGD) |i| {
        const av = a.v[i];
        const bv = b.v[i];
        if (av == null and bv == null) continue;
        const appears = (av == null) != (bv == null);
        if (!appears and !moves(GROW[i].unit, av orelse 0, bv orelse 0)) continue;
        show[i] = true;
        shown += 1;
    }
    var sheetRows: usize = 0;
    for (0..ND) |i| {
        if (moves(DER[i].unit, now[i], then[i])) sheetRows += 1;
    }
    if (shown == 0 and sheetRows == 0) {
        for (0..NGD) |i| {
            if (a.v[i] == null and b.v[i] == null) continue;
            show[i] = true;
            shown += 1;
        }
    }
    var sections: usize = 0;
    var last: ?GSection = null;
    for (0..NGD) |i| {
        if (!show[i]) continue;
        const s = gsectionOf(@enumFromInt(i));
        if (last != s) {
            sections += 1;
            last = s;
        }
    }
    var sheetShown: usize = @min(sheetRows, SHEET_ROWS_MAX);

    // FITTED TO THE PANEL, in this order of sacrifice: the prose goes first, then the sheet's tail. Rows never run under the footer.
    const says = saysOwn(if (armIn(f.then, f.socket) != null) armWords(f.then, f.socket) else candSays(c, v));
    const nameH = hud.lineH(hud.SMALL) + 4;
    var foot: i32 = if (says.len > 0) hud.proseH(says, inner.w, hud.HINT) + 14 else 0;
    const heads: i32 = @intCast(sections + @intFromBool(sheetShown > 0));
    const fixedNoFoot = nameH + tagRowH() + heads * sectH() + 6;
    var maxRows: usize = @intCast(@max(@divTrunc(inner.h - fixedNoFoot - foot, rowFloor()), 0));
    if (maxRows < shown + sheetShown and foot > 0) {
        foot = 0;
        maxRows = @intCast(@max(@divTrunc(inner.h - fixedNoFoot, rowFloor()), 0));
    }
    if (maxRows < shown + sheetShown) sheetShown = maxRows -| shown;
    const step = rowStep(inner.h - fixedNoFoot - foot, shown + sheetShown);
    const size = rowSize(step);
    const cols = colsFor(inner);

    var y = inner.y;
    const nowTag = "NOW";
    hud.text(nowTag, inner.x, y + 3, hud.TINY, uiart.TEXT_DIM);
    hud.text(nowNameOf(f), inner.x + hud.textW(nowTag, hud.TINY) + 8, y, hud.SMALL, uiart.TEXT_VALUE);
    const thenTag = "THEN";
    const thenW = hud.textW(c.name, hud.SMALL);
    hud.text(c.name, inner.right() - thenW, y, hud.SMALL, uiart.HOT);
    hud.text(thenTag, inner.right() - thenW - hud.textW(thenTag, hud.TINY) - 8, y + 3, hud.TINY, mathx.withAlpha(uiart.GILT, 220));
    y += nameH;
    var tb: [5][:0]const u8 = undefined;
    const tags = tagsOf(f.then, f.socket, &tb);
    if (tags.len > 0) _ = drawTags(inner.right() - tagsW(tags), y, tags);
    y += tagRowH();

    last = null;
    for (GROW, 0..) |row, i| {
        if (!show[i]) continue;
        const s = gsectionOf(@enumFromInt(i));
        if (last != s) {
            y = head(inner, y, gsectionName(s));
            last = s;
        }
        const label = if (i == @intFromEnum(GDial.boon)) (b.boonName orelse a.boonName orelse row.name) else row.name;
        cmpRow(cols, y, size, label, row.unit, a.v[i], b.v[i], row.cost, dialStr);
        y += step;
    }
    if (sheetShown > 0) {
        y = head(inner, y, "ON THE SHEET");
        var n: usize = 0;
        for (DER, 0..) |row, i| {
            if (!moves(row.unit, now[i], then[i])) continue;
            if (n == sheetShown) break;
            cmpRow(cols, y, size, row.name, row.unit, now[i], then[i], row.cost, unitStrOpt);
            y += step;
            n += 1;
        }
    }
    if (foot == 0) return;
    const footY = @max(inner.y + inner.h - foot + 14, y + 6);
    uiart.divider(inner.x + @divTrunc(inner.w, 2), @max(footY - 10, y + 2), @divTrunc(inner.w, 2) - 10, 120);
    _ = hud.prose(says, inner.x, footY, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn derSplitX(inner: Box, size: i32) i32 {
    var widest: i32 = 0;
    for (DER[0..DER_SPLIT]) |row| widest = @max(widest, hud.textW(row.name, size));
    return inner.x + mathx.clampI(widest + 96, @divTrunc(inner.w, 3), @divTrunc(inner.w, 2));
}

fn derHeadH(cand: ?Cand) i32 {
    return sectH() + (if (cand != null) hud.lineH(hud.TINY) + 4 else 0);
}

fn derColumn(inner: Box, x: i32, right: i32, cap: [:0]const u8, now: [ND]f32, then: [ND]f32, cand: ?Cand, size: i32, step: i32, lo: usize, hi: usize) i32 {
    const sub = Box{ .x = x, .y = inner.y, .w = right - x, .h = inner.h };
    var y = head(sub, inner.y, cap);
    const cols = colsFor(sub);
    if (cand != null) {
        rowValueAt("NOW", cols.now, y, hud.TINY, uiart.TEXT_DIM);
        rowValueAt("THEN", cols.then, y, hud.TINY, mathx.withAlpha(uiart.GILT, 220));
        y += hud.lineH(hud.TINY) + 4;
    }
    for (DER[lo..hi], lo..) |row, i| {
        if (cand == null) {
            rowLabelAt(row.name, x, y, size, uiart.TEXT_DIM);
            rowValueAt(unitStr(row.unit, now[i]), right, y, size, if (@abs(now[i]) > 0.005) uiart.TEXT_VALUE else uiart.TEXT_DIM);
        } else {
            cmpRow(cols, y, size, row.name, row.unit, now[i], then[i], row.cost, unitStrOpt);
        }
        y += step;
    }
    return y;
}

fn browsing(s: SlotId, v: View) ?Facing {
    if (wearOf(s)) |w| return .{ .now = v.worn.at(w), .then = null, .socket = w, .nowName = wornName(v, w) };
    const live: heromod.Armament = switch (s) {
        .right => v.arm,
        .left => if (v.offInHand()) v.off else return null,
        .right2 => v.armAlt,
        .left2 => v.offAlt,
        else => return null,
    };
    const w = heromod.wearFor(live) orelse return null;
    return .{ .now = heromod.heldGear(live, v.worn), .then = null, .socket = w, .nowName = liveName(live, v.worn) };
}

const CardShape = struct { rows: usize, sections: usize };

fn cardShape(v: View, f: Facing) CardShape {
    const d = dialsOf(f.now, f.socket, v);
    var out = CardShape{ .rows = 0, .sections = 0 };
    var last: ?GSection = null;
    for (0..NGD) |i| {
        if (d.v[i] == null) continue;
        out.rows += 1;
        const s = gsectionOf(@enumFromInt(i));
        if (last != s) {
            out.sections += 1;
            last = s;
        }
    }
    return out;
}

fn cardBoxIn(col: Box, v: View, f: Facing, says: [:0]const u8) Box {
    const shape = cardShape(v, f);
    const rows: i32 = @intCast(@max(shape.rows, 1));
    const foot: i32 = if (says.len > 0) hud.proseH(says, col.w - 28, hud.HINT) + 12 else 0;
    const want = 28 + hud.lineH(hud.BODY) + 4 + tagRowH() + @as(i32, @intCast(shape.sections)) * sectH() + (hud.lineH(hud.SMALL) + 7) * rows + foot;
    const room = @max(hud.lineH(hud.BODY) + 46, col.h - derivedNeedH() - GUTTER);
    return .{ .x = col.x, .y = col.y, .w = col.w, .h = @min(want, room) };
}

/// The piece in the socket under the cursor, read like a shop tag: its name, its tags, its dials by section.
fn drawGearCard(box: Box, v: View, f: Facing, says: [:0]const u8) void {
    const inner = panel(box, "");
    const d = dialsOf(f.now, f.socket, v);
    const shape = cardShape(v, f);

    const capH = hud.lineH(hud.BODY) + 4;
    const foot: i32 = if (says.len > 0) hud.proseH(says, inner.w, hud.HINT) + 12 else 0;
    const step = rowStep(inner.h - capH - tagRowH() - @as(i32, @intCast(shape.sections)) * sectH() - foot, @max(shape.rows, 1));
    const size = rowSize(step);

    var y = inner.y;
    hud.text(nowNameOf(f), inner.x, y, hud.BODY, uiart.HOT);
    y += capH;
    var tb: [5][:0]const u8 = undefined;
    _ = drawTags(inner.x, y, tagsOf(f.now, f.socket, &tb));
    y += tagRowH();
    var last: ?GSection = null;
    for (GROW, 0..) |row, i| {
        const val = d.v[i] orelse continue;
        const s = gsectionOf(@enumFromInt(i));
        if (last != s) {
            y = head(inner, y, gsectionName(s));
            last = s;
        }
        const label = if (i == @intFromEnum(GDial.boon)) (d.boonName orelse row.name) else row.name;
        rowLabelAt(label, inner.x, y, size, uiart.TEXT_DIM);
        rowValueAt(dialStr(row.unit, val), inner.right(), y, size, uiart.TEXT_VALUE);
        y += step;
    }
    if (says.len == 0) return;
    const footY = @max(inner.y + inner.h - foot + 12, y + 6);
    uiart.divider(inner.x + @divTrunc(inner.w, 2), @max(footY - 10, y + 2), @divTrunc(inner.w, 2) - 10, 120);
    _ = hud.prose(says, inner.x, footY, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn drawDerived(box: Box, v: View, cand: ?Cand) void {
    const inner = panel(box, "");
    const base = inForce(v);
    const now = derive(base, v);
    const then = if (cand) |c| derive(withCand(base, c), v) else now;

    // TAKEN OFF THE ROTATING SCRATCH BEFORE THE ROWS RUN: `rowSays` builds through `fmt`, which cycles a 16-slot buffer, and the loop below spends 28 slots on `unitStr`.
    const says = saysOwn(if (cand) |c| candSays(c, v) else armSays(v.arm, v.off));
    const foot = hud.proseH(says, inner.w, hud.HINT) + 22;
    const tallest = @max(DER_SPLIT, ND - DER_SPLIT);
    const step = rowStep(inner.h - foot - derHeadH(cand), tallest);
    const size = rowSize(step);
    const mid = derSplitX(inner, size);
    var y = derColumn(inner, inner.x, mid - GUTTER, DER_CAPS[0], now, then, cand, size, step, 0, DER_SPLIT);
    y = @max(y, derColumn(inner, mid, inner.right(), DER_CAPS[1], now, then, cand, size, step, DER_SPLIT, ND));

    const footY = @max(inner.y + inner.h - foot + 22, y + 8);
    uiart.divider(inner.x + @divTrunc(inner.w, 2), @max(footY - 12, y + 2), @divTrunc(inner.w, 2) - 10, 120);
    _ = hud.prose(says, inner.x, footY, inner.w, hud.HINT, uiart.TEXT_HINT);
}

comptime {
    const A = @typeInfo(heromod.Armament).@"enum".fields;
    const B = @typeInfo(itemart.Arm).@"enum".fields;
    if (A.len != B.len) @compileError("book: hero.Armament and itemart.Arm have drifted in LENGTH");
    for (A, B) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name)) {
            @compileError("book: hero.Armament." ++ a.name ++ " faces itemart.Arm." ++ b.name ++
                " — the two must stay name-for-name in order, or `armPic` maps a hand to the wrong picture");
        }
    }
}

pub fn armPic(a: heromod.Armament) itemart.Arm {
    return switch (a) {
        .sword => .sword,
        .dagger => .dagger,
        .club => .club,
        .bow => .bow,
        .bell => .bell,
        .shield => .shield,
        .wand => .wand,
        .torch => .torch,
    };
}

fn armSays(a: heromod.Armament, o: heromod.Armament) []const u8 {
    if (heromod.armTwoHanded(a)) return "Both hands. No off-hand, no block.";
    if (o == .shield or a == .shield) return "Can guard.";
    if (o == .wand or a == .wand) return "Casts on L1. Costs Focus, not stamina.";
    if (o == .torch or a == .torch) return "Lights what you walk into. No block.";
    return "No block.";
}

fn armCandSays(a: heromod.Armament) []const u8 {
    return switch (a) {
        .sword => "",
        .dagger => "Fastest in the kit. Least reach, least poise.",
        .club => "Slowest, heaviest. R2 comes down overhead.",
        .bow => "Takes both hands.",
        .bell => "Summons what the scroll names. No attack.",
        .shield => "Can guard.",
        .wand => "Casts on L1. Takes a hand.",
        .torch => "Lights the dark. No attack, no block.",
    };
}

fn rowSays(k: item.Kind) [:0]const u8 {
    var tmp: [item.EFFECT_BUF]u8 = undefined;
    return fmt("{s}", .{item.effect(k, &tmp)});
}

fn candSays(c: Cand, _: View) []const u8 {
    return switch (c.act) {
        .arm, .off, .armAlt, .offAlt => |h| if (h.kind) |k| rowSays(k) else armCandSays(h.a),
        .wear => |wr| if (wr.kind) |k| rowSays(k) else "Take it off.",
        .ammo => |a| switch (a) {
            .plain => "",
            .fire => "Adds fire to the shaft's damage.",
        },
        .quick => |q| if (q.kind == null)
            "Leave the socket empty."
        else
            "",
        else => "",
    };
}

fn drawPicker(self: *const Book, col: Box, s: SlotId, v: View) void {
    var buf: [CAND_MAX]Cand = undefined;
    const cs = candidates(s, v, &buf);
    const box = pickBox(col, cs.len);
    const step = pickStep(box, cs.len);
    const inner = panel(box, fmt("{s}  >", .{slotName(s)}));
    const base = inForce(v);
    const now = derive(base, v);
    for (cs, 0..) |c, i| {
        const y = inner.y + @as(i32, @intCast(i)) * step;
        const on = self.pick == i;
        if (on) uiart.rowHilite(inner.x - 8, y - 6, inner.w + 16, step - 2);
        const size = pickSize(step);
        hud.text(c.name, inner.x + 10, y, size, if (on) uiart.HOT else uiart.TEXT_DIM);
        if (c.tally) |n| {
            const str = fmt("{d}", .{n});
            hud.text(str, inner.right() - hud.textW(str, size), y, size, if (n > 0) uiart.TEXT_VALUE else uiart.BAD);
        }
        const right = inner.right() - 46;
        if (equipped(c, v)) {
            const tag = "EQUIPPED";
            hud.text(tag, right - hud.textW(tag, hud.TINY), y + 3, hud.TINY, mathx.withAlpha(uiart.GILT, 200));
        } else if (headline(c, v, base, now)) |h| {
            // THE ROW SAYS WHAT IT IS WORTH before it is picked: the biggest thing it moves, in the colour of the news.
            hud.text(h.text, right - hud.textW(h.text, hud.TINY), y + 3, hud.TINY, if (h.good) uiart.GOOD else uiart.BAD);
        }
    }
}


fn drawInventory(self: *const Book, body: Box, v: View) void {
    const cols = bagCols(body);
    const n = bagCells(v);
    _ = panel(cols[0], fmt("CARRIED    {d} kinds, {d} in all", .{ v.bag.distinct(), v.bag.total() }));
    const g = bagGrid(body);
    for (0..BAG_ROWS * BAG_COLS) |cell| {
        const at = cell + self.scroll * BAG_COLS;
        const kind = bagAt(v, at);
        drawBagCell(self, g.at(cell), kind, if (kind) |k| heldOf(v, k) else 0, self.cur[idx(.inventory)] == at and kind != null);
    }
    const rows = (n + BAG_COLS - 1) / BAG_COLS;
    uiart.rail(
        g.x + g.stepX * @as(i32, BAG_COLS) - CELL_GAP + 4,
        g.y,
        g.stepY * @as(i32, BAG_ROWS) - CELL_GAP,
        @as(f32, BAG_ROWS) / @as(f32, @floatFromInt(@max(rows, BAG_ROWS))),
        if (rows > BAG_ROWS) @as(f32, @floatFromInt(self.scroll)) / @as(f32, @floatFromInt(rows - BAG_ROWS)) else 0,
    );
    drawItemDetail(cols[1], bagAt(v, self.cur[idx(.inventory)]), v);
}

fn drawBagCell(self: *const Book, r: rl.Rectangle, kind: ?item.Kind, count: u32, sel: bool) void {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const cell: i32 = @intFromFloat(r.width);
    const sink: i32 = if (sel) @intFromFloat(@round(self.press * 2.0)) else 0;
    const pop = if (sel) self.pop / POP_DUR else 0;
    const sy = y + sink - @as(i32, @intFromFloat(@round(pop * pop * 3.0)));
    uiart.slot(x, sy, cell, cell, kind != null);
    if (sel) uiart.sheen(rect(x, sy, cell, cell), 3.4, 20);
    const k = kind orelse return;
    const lift: f32 = if (sel) 2.0 - self.press * 3.0 else 0;
    itemart.draw(k, fi(x + @divTrunc(cell, 2)), fi(sy + @divTrunc(cell, 2)) - lift, fi(cell) * 0.74);
    if (count > 1) hud.tally(fmt("{d}", .{count}), x + cell, sy + cell, hud.SMALL, uiart.TEXT_VALUE);
}

fn drawItemDetail(box: Box, kind: ?item.Kind, v: View) void {
    const inner = panel(box, "");
    const k = kind orelse {
        hud.text("Nothing carried.", inner.x, inner.y + 6, hud.BODY, uiart.TEXT_DIM);
        return;
    };
    const plateW = @min(@divTrunc(inner.w, 2), 200);
    const plateH = @min(@divTrunc(inner.h, 3), 180);
    uiart.slot(inner.x, inner.y, plateW, plateH, true);
    itemart.draw(k, fi(inner.x + @divTrunc(plateW, 2)), fi(inner.y + @divTrunc(plateH, 2)), fi(@min(plateW, plateH)) * 0.72);

    const tx = inner.x + plateW + 18;
    var y = inner.y + 2;
    hud.engraved(item.displayName(k), tx, y, hud.BODY, uiart.TEXT_TITLE);
    y += hud.lineH(hud.BODY) + 6;
    hud.text(item.class(k).label(), tx, y, hud.SMALL, mathx.withAlpha(uiart.GILT, 200));
    y += hud.lineH(hud.SMALL) + 2;
    hud.text(fmt("Held: {d}", .{heldOf(v, k)}), tx, y, hud.SMALL, uiart.TEXT_DIM);

    y = hud.prose(item.describe(k), inner.x, inner.y + plateH + 16, inner.w, hud.SMALL, uiart.TEXT_VALUE) + 10;
    uiart.divider(inner.x + @divTrunc(inner.w, 2), y, @divTrunc(inner.w, 2) - 10, 120);
    y += 12;
    if (item.wearable(k)) {
        const hy = hud.prose(rowSays(k), inner.x, y, inner.w, hud.SMALL, uiart.GOOD) + 6;
        hud.text("Put it on from the Equipment page.", inner.x, hy, hud.HINT, uiart.TEXT_HINT);
        return;
    }
    var after = y + hud.lineH(hud.SMALL);
    switch (item.use(k)) {
        .none => hud.text("Nothing to use here.", inner.x, y, hud.HINT, uiart.TEXT_HINT),
        .regen => |r| hud.text(fmt("+{d:.0} HP over {d:.0}s", .{ v.sheet.hp() * r.frac, r.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .wind => |w| hud.text(fmt("+{d:.0} stamina, clears the lockout", .{v.sheet.stamina() * w.share}), inner.x, y, hud.SMALL, uiart.GOOD),
        else => after = hud.prose(rowSays(k), inner.x, y, inner.w, hud.SMALL, uiart.GOOD),
    }
    if (item.usable(k)) {
        const hy = after + 6;
        if (v.inCombat) {
            hud.text("Load it on the quick bar.", inner.x, hy, hud.HINT, uiart.BAD);
        } else {
            hud.hintRowAt(
                &[_]hud.Hint{.{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Use" }},
                inner.x,
                hy + @divTrunc(hud.lineH(hud.HINT), 2),
                hud.HINT,
                mathx.withAlpha(uiart.GILT, 220),
            );
        }
    }
}


const RACK_CELL: i32 = 72;
fn drawSpells(self: *const Book, body: Box, v: View) void {
    const cols = spellCols(body);
    drawKnown(self, cols[0], v);
    const rows = cols[1].cutDown(RACK_CELL + titleH() + 12 + hud.lineH(hud.TINY) + 22);
    drawRack(rows[0], v);
    drawSpellRead(self, rows[1], v);
}

fn drawKnown(self: *const Book, col: Box, v: View) void {
    const inner = panel(col, fmt("SORCERIES    {d} of {d} carried", .{ carriedSpells(v), combat.SPELLS.len }));
    var y = inner.y;
    for (combat.SPELLS, 0..) |row, i| {
        const on = self.cur[idx(.spells)] == i;
        const carried = combat.carriesSpell(v.bag, row.spell);
        if (on) uiart.rowHilite(inner.x - 10, y - 6, inner.w + 20, spellStep() - 4);
        const tint = if (on) uiart.HOT else if (!carried) mathx.withAlpha(uiart.TEXT_DIM, 150) else uiart.TEXT_VALUE;
        hud.text(row.name, inner.x, y, hud.BODY, tint);
        if (v.mem.slotOf(row.spell)) |slot| {
            const mark = fmt("SLOT {s}", .{uiart.numeral(slot)});
            hud.text(mark, inner.right() - hud.textW(mark, hud.TINY), y + 4, hud.TINY, mathx.withAlpha(uiart.GILT, 220));
        } else {
            const cost = fmt("{d:.0} FP", .{row.fp});
            hud.text(cost, inner.right() - hud.textW(cost, hud.SMALL), y + 2, hud.SMALL, if (carried) uiart.TEXT_DIM else mathx.withAlpha(uiart.TEXT_DIM, 130));
        }
        y += spellStep();
    }
    y += 6;
    uiart.divider(inner.x + @divTrunc(inner.w, 2), y, @divTrunc(inner.w, 2) - 10, 120);
    _ = hud.prose("Memorized at a bonfire. The rod casts only what is in the rack.", inner.x, y + 12, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn carriedSpells(v: View) usize {
    var n: usize = 0;
    for (combat.SPELLS) |row| {
        if (combat.carriesSpell(v.bag, row.spell)) n += 1;
    }
    return n;
}

fn drawRack(box: Box, v: View) void {
    const inner = panel(box, fmt("MEMORY    {d} of {d} slots", .{ v.mem.filled(), combat.MEM_SLOTS }));
    const gap: i32 = 14;
    var x = inner.x;
    for (0..combat.MEM_SLOTS) |i| {
        const held = v.mem.at(i);
        uiart.slot(x, inner.y, RACK_CELL, RACK_CELL, held != null);
        if (held) |sp| itemart.spellArt(sp, fi(x + @divTrunc(RACK_CELL, 2)), fi(inner.y + @divTrunc(RACK_CELL, 2)), fi(RACK_CELL) * 0.78, v.fp >= castFp(sp, v.tree.bonus()));
        const lab = uiart.numeral(i);
        hud.text(lab, x + @divTrunc(RACK_CELL - hud.textW(lab, hud.TINY), 2), inner.y + RACK_CELL + 4, hud.TINY, mathx.withAlpha(uiart.TEXT_DIM, 200));
        x += RACK_CELL + gap;
    }
    if (v.mem.first() == null) hud.text("Nothing memorized.", x + 6, inner.y + @divTrunc(RACK_CELL, 2) - 8, hud.SMALL, uiart.BAD);
}

fn drawSpellRead(self: *const Book, box: Box, v: View) void {
    const row = combat.SPELLS[@min(self.cur[idx(.spells)], combat.SPELLS.len - 1)];
    const inner = panel(box, "");
    const plate = @min(@divTrunc(inner.w, 3), 150);
    uiart.slot(inner.x, inner.y, plate, plate, true);
    itemart.spellArt(row.spell, fi(inner.x + @divTrunc(plate, 2)), fi(inner.y + @divTrunc(plate, 2)), fi(plate) * 0.76, true);

    const tx = inner.x + plate + 18;
    var y = inner.y + 2;
    hud.engraved(row.name, tx, y, hud.BODY, uiart.TEXT_TITLE);
    y += hud.lineH(hud.BODY) + 6;
    const perk = v.tree.bonus();
    const scaled: f32 = if (row.blow != null) perk.spellDmg * v.sheet.scale(.intelligence) else 1.0;
    hud.text(fmt("{d:.0} focus a cast", .{castFp(row.spell, perk)}), tx, y, hud.SMALL, uiart.GILT);
    y += hud.lineH(hud.SMALL) + 2;
    hud.text(fmt("{d:.0} damage", .{combat.spellDamage(row.spell) * scaled}), tx, y, hud.SMALL, uiart.TEXT_VALUE);
    y += hud.lineH(hud.SMALL) + 2;
    hud.text(fmt("{d} casts off a full pool", .{castsLeft(heromod.fpMaxOf(v.sheet.*, v.worn, perk), row.spell, v)}), tx, y, hud.SMALL, uiart.TEXT_DIM);

    y = hud.prose(row.says, inner.x, inner.y + plate + 14, inner.w, hud.SMALL, uiart.TEXT_VALUE) + 10;
    uiart.divider(inner.x + @divTrunc(inner.w, 2), y, @divTrunc(inner.w, 2) - 10, 120);
    y += 12;
    const carried = combat.carriesSpell(v.bag, row.spell);
    if (v.mem.slotOf(row.spell)) |slot| {
        hud.text(fmt("Memorized in slot {s}.", .{uiart.numeral(slot)}), inner.x, y, hud.SMALL, uiart.GOOD);
    } else if (carried) {
        hud.text("Carried. Memorize it at a bonfire.", inner.x, y, hud.SMALL, uiart.TEXT_VALUE);
    } else {
        hud.text("Its scroll is not carried.", inner.x, y, hud.SMALL, uiart.BAD);
    }
}

fn drawTree(self: *const Book, body: Box, v: View) void {
    ptree.drawPage(v.tree, self.wheel, body.x, body.y, body.w, body.h, false, v.souls);
}

fn drawStats(self: *const Book, body: Box, v: View, portrait: ?Portrait) void {
    const cols = statsCols(body);
    drawAttributes(self, cols[0], v);
    drawBody(cols[1], v);
    drawWards(cols[2], v);
    drawPortrait(self, cols[3], portrait, fmt("Level {d}    {d} souls    {d} gold", .{ v.tree.level(), v.souls, v.gold }));
}

/// What one attribute is buying him right now, in the unit it governs.
fn attrFigure(a: stats.Attr, s: *const stats.Sheet) [:0]const u8 {
    return switch (a) {
        .vitality => fmt("{d:.0} HP", .{s.hp()}),
        .mind => fmt("{d:.0} FP", .{s.fp()}),
        .endurance => fmt("{d:.0} stamina", .{s.stamina()}),
        .strength, .dexterity, .intelligence => fmt("x{d:.2}", .{s.scale(a)}),
        .luck => fmt("x{d:.2} finds", .{s.finds()}),
    };
}

/// …and what the NEXT point would buy, so a level is spent with its eyes open.
fn nextPointSays(a: stats.Attr, s: *const stats.Sheet) [:0]const u8 {
    const p = s.at(a);
    if (p >= stats.MAX) return "At its ceiling.";
    var next = s.*;
    next.set(a, p + 1);
    return switch (a) {
        .vitality => fmt("The next point is +{d:.0} HP.", .{next.hp() - s.hp()}),
        .mind => fmt("The next point is +{d:.0} FP.", .{next.fp() - s.fp()}),
        .endurance => fmt("The next point is +{d:.0} stamina.", .{next.stamina() - s.stamina()}),
        .strength, .dexterity, .intelligence => fmt("The next point takes x{d:.2} to x{d:.2}.", .{ s.scale(a), next.scale(a) }),
        .luck => fmt("The next point takes finds from x{d:.2} to x{d:.2}.", .{ s.finds(), next.finds() }),
    };
}

fn drawAttributes(self: *const Book, col: Box, v: View) void {
    const inner = panel(col, fmt("ATTRIBUTES    LEVEL {d}", .{v.tree.level()}));
    var y = inner.y;
    for (0..stats.NA) |i| {
        const a: stats.Attr = @enumFromInt(i);
        const on = self.cur[idx(.stats)] == i;
        const inert = stats.inert(a);
        if (on) uiart.rowHilite(inner.x - 10, y - 6, inner.w + 20, attrStep() - 4);
        const col2 = if (on) uiart.HOT else if (inert) mathx.withAlpha(uiart.TEXT_DIM, 170) else uiart.TEXT_VALUE;
        hud.text(stats.displayName(a), inner.x, y, hud.BODY, col2);
        const val = fmt("{d}", .{v.sheet.at(a)});
        const valX = inner.right() - hud.textW(val, hud.BODY);
        hud.text(val, valX, y, hud.BODY, col2);
        // What the points are worth, in the unit they govern, beside the count.
        const fig = attrFigure(a, v.sheet);
        hud.text(fig, valX - 14 - hud.textW(fig, hud.TINY), y + @divTrunc(hud.lineH(hud.BODY) - hud.lineH(hud.TINY), 2), hud.TINY, mathx.withAlpha(uiart.TEXT_DIM, if (on) 230 else 170));
        const barY = y + hud.lineH(hud.BODY) + 1;
        uiart.well(inner.x, barY, inner.w, 3, 220);
        rl.drawRectangle(inner.x, barY, inner.w, 3, rgba(52, 46, 38, 190));
        const f = @as(f32, @floatFromInt(v.sheet.at(a))) / @as(f32, @floatFromInt(stats.MAX));
        rl.drawRectangle(inner.x, barY, @intFromFloat(fi(inner.w) * f), 3, mathx.withAlpha(if (inert) uiart.GILT_DIM else uiart.GILT, 220));
        const startAt: i32 = @intFromFloat(fi(inner.w) * @as(f32, @floatFromInt(stats.START)) / @as(f32, @floatFromInt(stats.MAX)));
        rl.drawRectangle(inner.x + startAt, barY - 2, 1, 7, mathx.withAlpha(uiart.CATCH, 120));
        y += attrStep();
    }
    y += 6;
    uiart.divider(inner.x + @divTrunc(inner.w, 2), y, @divTrunc(inner.w, 2) - 10, 120);
    const a: stats.Attr = @enumFromInt(@min(self.cur[idx(.stats)], stats.NA - 1));
    const says = saysOwn(fmt("{s} {s}", .{ stats.governs(a), nextPointSays(a, v.sheet) }));
    _ = hud.prose(says, inner.x, y + 12, inner.w, hud.HINT, uiart.TEXT_HINT);
}

/// A LIST OF FIGURES IN SECTIONS, built first and drawn after, so the pitch can be solved for the whole column. Values are printed into the list's own store: `fmt`'s ring is sixteen deep and a column is longer.
const StatList = struct {
    const Row = struct { name: [:0]const u8, val: [:0]const u8, col: rl.Color, sect: u8 };
    /// The longest column the sheet can ask for: every resistance, every ailment and every passive at once, plus the two "nothing" rows.
    const CAP = combat.NELEM + combat.NAIL + @typeInfo(ptree.Bonus).@"struct".fields.len + 2;
    rows: [CAP]Row = undefined,
    store: [CAP][24]u8 = undefined,
    n: usize = 0,
    sects: [8][:0]const u8 = undefined,
    nsect: usize = 0,

    fn section(self: *StatList, title: [:0]const u8) void {
        if (self.nsect >= self.sects.len) return;
        self.sects[self.nsect] = title;
        self.nsect += 1;
    }
    fn put(self: *StatList, name: [:0]const u8, comptime f: []const u8, args: anytype, col: rl.Color) void {
        if (self.n >= CAP or self.nsect == 0) return;
        const s = std.fmt.bufPrintZ(&self.store[self.n], f, args) catch "?";
        self.rows[self.n] = .{ .name = name, .val = s, .col = col, .sect = @intCast(self.nsect - 1) };
        self.n += 1;
    }
    fn draw(self: *const StatList, inner: Box, foot: i32) i32 {
        const step = rowStep(inner.h - @as(i32, @intCast(self.nsect)) * sectH() - foot, @max(self.n, 1));
        const size = rowSize(step);
        var y = inner.y;
        var cur: ?u8 = null;
        for (self.rows[0..self.n]) |r| {
            if (cur != r.sect) {
                y = head(inner, y, self.sects[r.sect]);
                cur = r.sect;
            }
            rowLabelAt(r.name, inner.x, y, size, uiart.TEXT_DIM);
            rowValueAt(r.val, inner.right(), y, size, r.col);
            y += step;
        }
        return y;
    }
};

fn goodIf(up: bool) rl.Color {
    return if (up) uiart.GOOD else uiart.BAD;
}

/// THE BODY, ER's Base Power and Attack Power: the pools, what the hands in force actually deal, and what stands between him and a blow.
fn drawBody(col: Box, v: View) void {
    const inner = panel(col, "BODY");
    const perk = v.tree.bonus();
    const d = derive(inForce(v), v);
    var L = StatList{};
    L.section("VITALS");
    L.put("HP", "{d:.0}", .{worth(d, .hp)}, uiart.TEXT_VALUE);
    L.put("Focus", "{d:.0}", .{worth(d, .fp)}, uiart.TEXT_VALUE);
    L.put("Stamina", "{d:.0}", .{v.sheet.stamina() * perk.stamMax}, uiart.TEXT_VALUE);
    L.put("Poise", "{d:.0}", .{heromod.POISE_MAX * perk.poiseMax}, uiart.TEXT_VALUE);
    L.put("Stance", "{d:.0}", .{heromod.STANCE_MAX}, uiart.TEXT_VALUE);
    if (perk.hpRegen > 0) L.put("HP regen", "{d:.1}/s", .{perk.hpRegen}, uiart.GOOD);
    if (perk.fpRegen > 0) L.put("Focus regen", "{d:.1}/s", .{perk.fpRegen}, uiart.GOOD);

    L.section("ATTACK");
    if (worth(d, .light) > 0) {
        L.put("Light attack", "{d:.0}", .{worth(d, .light)}, uiart.TEXT_VALUE);
        L.put("Heavy attack", "{d:.0}", .{worth(d, .heavy)}, uiart.TEXT_VALUE);
        if (worth(d, .elem) > 0.5) L.put("Elemental", "{d:.0}", .{worth(d, .elem)}, uiart.TEXT_VALUE);
        L.put("Swing time", "{d:.2}s", .{worth(d, .swing)}, uiart.TEXT_VALUE);
        L.put("Poise damage", "{d:.0}", .{worth(d, .poise)}, uiart.TEXT_VALUE);
        L.put("Stance damage", "{d:.0}", .{worth(d, .stance)}, uiart.TEXT_VALUE);
    } else {
        L.put("Nothing in hand swings", "-", .{}, uiart.TEXT_DIM);
    }
    if (worth(d, .spell) > 0) {
        L.put("Sorcery", "{d:.0}", .{worth(d, .spell)}, uiart.TEXT_VALUE);
        L.put("Focus a cast", "{d:.0}", .{worth(d, .spell_fp)}, uiart.TEXT_VALUE);
    }
    if (v.holds(.bow)) L.put("Arrows carried", "{d:.0}", .{worth(d, .ammo)}, if (worth(d, .ammo) > 0) uiart.TEXT_VALUE else uiart.BAD);

    L.section("DEFENCE");
    const armour = worth(d, .armour);
    L.put("Armour", "{d:.0}", .{armour}, if (armour > 0.5) uiart.TEXT_VALUE else uiart.TEXT_DIM);
    L.put("Damage negated", "{d:.0}%", .{worth(d, .negate)}, if (armour > 0.5) uiart.TEXT_VALUE else uiart.TEXT_DIM);
    if (worth(d, .guard) > 0) {
        L.put("Guard negation", "{d:.0}%", .{worth(d, .guard)}, uiart.TEXT_VALUE);
        L.put("Guard arc", "{d:.0} deg", .{worth(d, .arc)}, uiart.TEXT_VALUE);
    }
    L.put("Roll i-frames", "{d:.2}s", .{heromod.ROLL_IFRAME_END_BANK + perk.iframe}, if (perk.iframe > 0) uiart.GOOD else uiart.TEXT_VALUE);
    L.put("Roll costs", "{d:.0} stamina", .{combat.STAM_ROLL * perk.rollStam}, if (perk.rollStam < 1) uiart.GOOD else uiart.TEXT_VALUE);
    const move = heromod.moveRateOf(v.worn, perk);
    if (@abs(move - 1) > 0.005) L.put("Move speed", "{d:.0}%", .{move * 100}, goodIf(move > 1));
    _ = L.draw(inner, 0);
}

/// THE WARDS: what he shrugs off, what fills slower on him, and everything the tree has made of him in words — the passives, one line per `ptree.Bonus` field; `BONUS_SHOWN` refuses to compile a field no panel says.
fn drawWards(col: Box, v: View) void {
    const inner = panel(col, "WARDS");
    const perk = v.tree.bonus();
    var L = StatList{};
    L.section("RESISTANCE");
    for (0..combat.NELEM) |i| {
        const e: combat.Elem = @enumFromInt(i);
        const raw = v.res.raw(e);
        const eff = v.res.at(e);
        const col2 = if (eff > 0.05) uiart.GOOD else if (eff < -0.05) uiart.BAD else uiart.TEXT_DIM;
        if (@abs(raw - eff) < 0.05) L.put(combat.elemName(e), "{d:.0}%", .{raw}, col2) else L.put(combat.elemName(e), "{d:.0}% ({d:.0}%)", .{ raw, eff }, col2);
    }

    L.section("AILMENTS");
    const suit = heromod.suitOf(v.worn);
    var slowed = false;
    for (0..combat.NAIL) |i| {
        const a: combat.Ail = @enumFromInt(i);
        var k = suit.rates[i];
        if (a == .poison) k *= perk.poison;
        if (@abs(k - 1) < 0.005) continue;
        slowed = true;
        L.put(combat.ailName(a), "fills at {d:.0}%", .{k * 100}, goodIf(k < 1));
    }
    if (!slowed) L.put("Every meter fills at", "100%", .{}, uiart.TEXT_DIM);

    L.section("PASSIVES");
    var taken = false;
    if (perk.dmg != 1) {
        L.put("Damage", "x{d:.2}", .{perk.dmg}, goodIf(perk.dmg > 1));
        taken = true;
    }
    if (perk.bowDmg != 1) {
        L.put("Bow damage", "x{d:.2}", .{perk.bowDmg}, goodIf(perk.bowDmg > 1));
        taken = true;
    }
    if (perk.thrownDmg != 1) {
        L.put("Thrown damage", "x{d:.2}", .{perk.thrownDmg}, goodIf(perk.thrownDmg > 1));
        taken = true;
    }
    if (perk.spellDmg != 1) {
        L.put("Sorcery damage", "x{d:.2}", .{perk.spellDmg}, goodIf(perk.spellDmg > 1));
        taken = true;
    }
    if (perk.spellCost != 1) {
        L.put("Sorcery costs", "x{d:.2}", .{perk.spellCost}, goodIf(perk.spellCost < 1));
        taken = true;
    }
    if (perk.castSpeed != 1) {
        L.put("Cast speed", "x{d:.2}", .{perk.castSpeed}, goodIf(perk.castSpeed > 1));
        taken = true;
    }
    if (perk.guard != 0) {
        L.put("Guard", "+{d:.0}%", .{perk.guard * 100}, goodIf(perk.guard > 0));
        taken = true;
    }
    if (perk.iframe != 0) {
        L.put("Roll i-frames", "+{d:.2}s", .{perk.iframe}, goodIf(perk.iframe > 0));
        taken = true;
    }
    if (perk.rollStam != 1) {
        L.put("Roll costs", "x{d:.2}", .{perk.rollStam}, goodIf(perk.rollStam < 1));
        taken = true;
    }
    if (perk.stamMax != 1) {
        L.put("Stamina", "x{d:.2}", .{perk.stamMax}, goodIf(perk.stamMax > 1));
        taken = true;
    }
    if (perk.stamRegen != 1) {
        L.put("Stamina regen", "x{d:.2}", .{perk.stamRegen}, goodIf(perk.stamRegen > 1));
        taken = true;
    }
    if (perk.moveSpeed != 1) {
        L.put("Move speed", "x{d:.2}", .{perk.moveSpeed}, goodIf(perk.moveSpeed > 1));
        taken = true;
    }
    if (perk.armour != 0) {
        L.put("Armour", "+{d:.0}", .{perk.armour}, goodIf(perk.armour > 0));
        taken = true;
    }
    if (perk.leech != 0) {
        L.put("HP a swing landed", "+{d:.1}", .{perk.leech}, goodIf(perk.leech > 0));
        taken = true;
    }
    if (perk.poiseMax != 1) {
        L.put("Poise", "x{d:.2}", .{perk.poiseMax}, goodIf(perk.poiseMax > 1));
        taken = true;
    }
    if (perk.flaskHeal != 1) {
        L.put("Flask heals", "x{d:.2}", .{perk.flaskHeal}, goodIf(perk.flaskHeal > 1));
        taken = true;
    }
    if (perk.fpMax != 1) {
        L.put("Focus", "x{d:.2}", .{perk.fpMax}, goodIf(perk.fpMax > 1));
        taken = true;
    }
    if (perk.hpFrac != 0) {
        L.put("Max HP", "-{d:.0}%", .{perk.hpFrac * 100}, uiart.BAD);
        taken = true;
    }
    if (perk.poison != 1) {
        L.put("Poison fills at", "x{d:.2}", .{perk.poison}, goodIf(perk.poison < 1));
        taken = true;
    }
    if (perk.cull > 0) {
        L.put("Culls below", "{d:.0}% HP", .{perk.cull * 100}, uiart.GOOD);
        taken = true;
    }
    if (perk.onKill > 0) {
        L.put("On a kill", "+{d:.0}", .{perk.onKill}, uiart.GOOD);
        taken = true;
    }
    if (perk.boltCloud) {
        L.put("The bolt", "leaves a cloud", .{}, uiart.GOOD);
        taken = true;
    }
    if (!taken) L.put("Nothing taken yet", "-", .{}, uiart.TEXT_DIM);
    _ = L.draw(inner, 0);
}

/// Every `ptree.Bonus` field a panel prints: the PASSIVES rows above, VITALS for the regens, ATTRIBUTES for `attrs`, RESISTANCE for `res`.
const BONUS_SHOWN = [_][]const u8{
    "attrs",     "res",       "hpRegen",  "fpRegen",  "dmg",      "bowDmg",   "thrownDmg", "spellDmg", "spellCost",
    "castSpeed", "guard",     "iframe",   "rollStam", "stamMax",  "stamRegen", "moveSpeed", "armour",   "leech",
    "poiseMax",  "flaskHeal", "fpMax",    "hpFrac",   "poison",   "cull",     "onKill",    "boltCloud",
};

comptime {
    @setEvalBranchQuota(20000);
    for (@typeInfo(ptree.Bonus).@"struct".fields) |f| {
        var shown = false;
        for (BONUS_SHOWN) |name| shown = shown or std.mem.eql(u8, name, f.name);
        if (!shown) @compileError("book: `ptree.Bonus." ++ f.name ++ "` is on no panel — give it a row in drawWards or drawBody and name it in BONUS_SHOWN");
    }
    for (BONUS_SHOWN) |name| {
        if (!@hasField(ptree.Bonus, name)) @compileError("book: BONUS_SHOWN names `" ++ name ++ "`, which `ptree.Bonus` no longer has");
    }
}



const PORT_W: i32 = 460;
const PORT_H: i32 = 760;
var portRT: ?rl.RenderTexture2D = null;

const DOLL_EYE: f32 = 0.94;
const DOLL_DIST: f32 = 3.5;
const DOLL_PITCH: f32 = 0.14;
const DOLL_FOV: f32 = 40.0;
const DOLL_CLEAR = rgba(14, 12, 10, 255);

fn drawDoll(ctx: *const anyopaque) void {
    const h: *const heromod.Hero = @ptrCast(@alignCast(ctx));
    h.draw(true);
}

pub fn unload() void {
    if (portRT) |t| rl.unloadRenderTexture(t);
    portRT = null;
    mapart.unload();
}

fn drawPortrait(self: *const Book, col: Box, portrait: ?Portrait, caption: [:0]const u8) void {
    const inner = panel(col, "THE TARNISHED");
    const capH = hud.lineH(hud.HINT) + 6;
    const frameH = inner.h - capH;
    const scale = @min(fi(inner.w) / fi(PORT_W), fi(frameH) / fi(PORT_H));
    const dw: i32 = @intFromFloat(fi(PORT_W) * scale);
    const dh: i32 = @intFromFloat(fi(PORT_H) * scale);
    const dx = inner.x + @divTrunc(inner.w - dw, 2);
    const dy = inner.y + @divTrunc(frameH - dh, 2);
    const dst = rect(dx, dy, dw, dh);

    const p = portrait orelse {
        uiart.well(dx, dy, dw, dh, 220);
        hud.text("(no scene)", dx + 12, dy + 12, hud.SMALL, uiart.TEXT_DIM);
        return;
    };
    if (portRT == null) portRT = rl.loadRenderTexture(PORT_W, PORT_H) catch null;
    const rt = portRT orelse return;

    hud.renderIntoTarget(rt, .{
        .scene = p.scene,
        .focus = v3(p.hero.pos.x, p.hero.pos.y + DOLL_EYE, p.hero.pos.z),
        .yaw = p.hero.facing + self.spin,
        .pitch = DOLL_PITCH,
        .dist = DOLL_DIST,
        .fov = DOLL_FOV,
        .clear = DOLL_CLEAR,
        .ctx = @ptrCast(p.hero),
        .drawFn = drawDoll,
    });

    rl.drawTexturePro(rt.texture, .{ .x = 0, .y = 0, .width = fi(PORT_W), .height = -fi(PORT_H) }, dst, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
    uiart.candle(dx + @divTrunc(dw, 2), dy + dh - @divTrunc(dh, 7), fi(dw) * 0.44, 30);
    const band = @divTrunc(dh, 5);
    rl.drawRectangleGradientV(dx, dy, dw, band, rgba(0, 0, 0, 190), rgba(0, 0, 0, 0));
    rl.drawRectangleGradientV(dx, dy + dh - band, dw, band, rgba(0, 0, 0, 0), rgba(0, 0, 0, 205));
    const side = @divTrunc(dw, 5);
    rl.drawRectangleGradientH(dx, dy, side, dh, rgba(0, 0, 0, 170), rgba(0, 0, 0, 0));
    rl.drawRectangleGradientH(dx + dw - side, dy, side, dh, rgba(0, 0, 0, 0), rgba(0, 0, 0, 170));
    rl.drawRectangleLinesEx(dst, 1, mathx.withAlpha(uiart.GILT_DIM, 90));

    hud.text(
        caption,
        inner.x + @divTrunc(inner.w - hud.textW(caption, hud.HINT), 2),
        inner.y + inner.h - hud.lineH(hud.HINT),
        hud.HINT,
        uiart.TEXT_HINT,
    );
}


const TEST_QUICK = combat.Quick{};
const TEST_TREE = ptree.Tree{};

fn testView(bag: *const item.Bag, sheet: *const stats.Sheet, res: *const combat.Resists, flasks: *const combat.Flasks, quiver: *const combat.Quiver, arm: heromod.Arm) View {
    return testViewOff(bag, sheet, res, flasks, quiver, arm, .shield);
}

fn testViewOff(bag: *const item.Bag, sheet: *const stats.Sheet, res: *const combat.Resists, flasks: *const combat.Flasks, quiver: *const combat.Quiver, arm: heromod.Arm, off: heromod.Off) View {
    return .{ .bag = bag, .sheet = sheet, .res = res, .flasks = flasks, .quick = &TEST_QUICK, .quiver = quiver, .tree = &TEST_TREE, .arm = arm, .off = off, .spell = .bolt, .fp = combat.FP_MAX, .souls = 0 };
}

test "EVERY WORN SOCKET ON THE DOLL OPENS ONCE HE IS CARRYING SOMETHING FOR IT" {
    var bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    var out: [CAND_MAX]Cand = undefined;

    var worn: usize = 0;
    inline for (@typeInfo(SlotId).@"enum".fields) |f| {
        const s: SlotId = @enumFromInt(f.value);
        if (wearOf(s)) |w| {
            worn += 1;
            try std.testing.expect(locked(s, v) != null);
            try std.testing.expect(candidates(s, v, &out).len == 0);

            var found: ?item.Kind = null;
            for (0..item.NK) |i| {
                const k: item.Kind = @enumFromInt(i);
                if (item.wearSlot(k) == w) found = k;
            }
            const k = found.?; // the comptime table already guarantees one exists
            bag.add(k, 1);
            try std.testing.expect(locked(s, v) == null);
            try std.testing.expectEqual(@as(usize, 2), candidates(s, v, &out).len);

            try std.testing.expect(!slotHas(s, v));
            v.worn.put(w, k);
            try std.testing.expect(slotHas(s, v));
            try std.testing.expectEqualStrings(item.displayName(k), slotFilled(s, v));
            try std.testing.expectEqual(@as(usize, 1), pickIndexOf(s, v));
            try std.testing.expect(slotTally(s, v) == null);

            v.worn.put(w, null);
            _ = bag.take(k, 1);
        }
    }
    try std.testing.expectEqual(@as(usize, 7), worn);
}

test "A BOON IS PRICED INTO THE PAGE'S OWN DAMAGE ROWS, and only counted once" {
    var bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);

    const bare = Loadout{ .arm = .sword, .off = .shield, .ammo = .plain, .quick = null, .spell = .bolt };
    var belted = bare;
    belted.worn.put(.belt, .banded_warbelt);
    try std.testing.expect(worth(derive(belted, v), .heavy) > worth(derive(bare, v), .heavy));
    try std.testing.expect(worth(derive(belted, v), .light) > worth(derive(bare, v), .light));

    var live = v;
    var worn = stats.Sheet{};
    heromod.boonsOnto(belted.worn, &worn);
    live.sheet = &worn;
    try std.testing.expectApproxEqAbs(worth(derive(belted, v), .heavy), worth(derive(belted, live), .heavy), 1e-4);

    var club = bare;
    club.arm = .club;
    club.worn.put(.hand_club, .greatclub);
    var clubRing = club;
    clubRing.worn.put(.ring2, .deft_signet);
    try std.testing.expectApproxEqAbs(worth(derive(club, v), .heavy), worth(derive(clubRing, v), .heavy), 1e-4);
}

test "THE NOW COLUMN PRICES WHAT HE HAS ON — every axis of the set in force, `worn` included" {
    var bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    const bareRows = derive(inForce(v), v);

    v.arm = .club;
    v.worn.put(.hand_club, .greatclub);
    v.worn.put(.hand_shield, .tower_shield);
    v.worn.put(.chest, .quilted_gambeson);
    const geared = derive(inForce(v), v);
    try std.testing.expect(worth(geared, .heavy) > worth(bareRows, .heavy));
    try std.testing.expect(worth(geared, .poise) > worth(bareRows, .poise));
    try std.testing.expect(worth(geared, .swing) > worth(bareRows, .swing));
    try std.testing.expect(worth(geared, .guard) > worth(bareRows, .guard));
    try std.testing.expect(worth(geared, .arc) > worth(bareRows, .arc));
    try std.testing.expectApproxEqAbs(@as(f32, 0), worth(bareRows, .armour), 1e-6);
    try std.testing.expect(worth(geared, .armour) > 0);
}

test "the paper doll walks by geometry, and every step lands on a socket" {
    try std.testing.expectEqual(@intFromEnum(SlotId.chest), slotStep(@intFromEnum(SlotId.helm), 0, 1));
    try std.testing.expectEqual(@intFromEnum(SlotId.right), slotStep(@intFromEnum(SlotId.chest), 1, 0));
    try std.testing.expectEqual(@intFromEnum(SlotId.left), slotStep(@intFromEnum(SlotId.chest), -1, 0));
    try std.testing.expectEqual(@intFromEnum(SlotId.helm), slotStep(@intFromEnum(SlotId.helm), 0, -1));
    try std.testing.expectEqual(@intFromEnum(SlotId.q1), slotStep(@intFromEnum(SlotId.arrows), 0, 1));
    try std.testing.expectEqual(@intFromEnum(SlotId.q6), slotStep(@intFromEnum(SlotId.q1), 0, 1));
    try std.testing.expectEqual(@intFromEnum(SlotId.q9), slotStep(@intFromEnum(SlotId.q8), 1, 0));
    for (0..NSLOT) |i| {
        for ([_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |d| {
            try std.testing.expect(slotStep(i, d[0], d[1]) < NSLOT);
        }
    }
    try std.testing.expectEqual(@as(usize, 7), grid(2, 8, BAG_COLS, 0, 1));
    try std.testing.expectEqual(@as(usize, 0), grid(0, 0, BAG_COLS, 1, 1));
}

test "a picker opens on what is already equipped, never on the first row" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    var flasks = combat.Flasks{};
    var quiver = combat.Quiver{};
    flasks.sel = .cerulean;
    quiver.sel = .fire;
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .bow);
    var buf: [CAND_MAX]Cand = undefined;
    for ([_]SlotId{ .right, .arrows, .q0 }) |s| {
        const cs = candidates(s, v, &buf);
        try std.testing.expect(cs.len >= 2);
        try std.testing.expect(equipped(cs[pickIndexOf(s, v)], v));
    }
}

test "THE SWAP IS PRICED HONESTLY: taking up the bow shows the shield's guard going away" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    const sword = derive(.{ .arm = .sword, .off = .shield, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    const bow = derive(.{ .arm = .bow, .off = .shield, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    try std.testing.expect(worth(sword, .guard) > 0 and worth(bow, .guard) == 0);
    try std.testing.expect(worth(sword, .light) > worth(bow, .light));
    const fire = derive(.{ .arm = .bow, .off = .shield, .ammo = .fire, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    try std.testing.expect(worth(bow, .elem) == 0 and worth(fire, .elem) > 0);
    try std.testing.expectApproxEqAbs(worth(bow, .heavy) * heromod.FIRE_ARROW_FRAC, worth(fire, .elem), 1e-3);
    const cer = derive(.{ .arm = .sword, .off = .shield, .ammo = .plain, .quick = item.Kind.cerulean_flask, .spell = .bolt }, v);
    try std.testing.expectApproxEqAbs(sheet.hp() * combat.FLASK_HP_FRAC, worth(sword, .quick), 1e-3);
    try std.testing.expectApproxEqAbs(sheet.fp() * combat.FLASK_FP_FRAC, worth(cer, .quick), 1e-3);
    const swordFire = derive(.{ .arm = .sword, .off = .shield, .ammo = .fire, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    for (0..ND) |i| {
        const k: Der = @enumFromInt(i);
        if (k == .ammo) continue;
        try std.testing.expectEqual(worth(sword, k), worth(swordFire, k));
    }
    try std.testing.expect(worth(sword, .ammo) != worth(swordFire, .ammo));
}

test "every slot either offers a choice or says why it cannot" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var buf: [CAND_MAX]Cand = undefined;
    for ([_]heromod.Arm{ .sword, .bow }) |arm| {
        for ([_]heromod.Off{ .shield, .wand }) |off| {
            const v = testViewOff(&bag, &sheet, &res, &flasks, &quiver, arm, off);
            for (0..NSLOT) |i| {
                const s: SlotId = @enumFromInt(i);
                const cs = candidates(s, v, &buf);
                if (locked(s, v)) |why| {
                    try std.testing.expect(why.len > 0);
                    try std.testing.expectEqual(@as(usize, 0), cs.len);
                } else {
                    try std.testing.expect(cs.len >= 2);
                }
                try std.testing.expect(slotName(s).len > 0);
                try std.testing.expect(slotFilled(s, v).len > 0);
            }
            try std.testing.expectEqual(arm != .bow and off == .wand, slotHas(.sorcery, v));
        }
    }
}

test "THE WAND IS PRICED HONESTLY TOO: it buys a bolt and it costs him the guard" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    const board = derive(.{ .arm = .sword, .off = .shield, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    const rod = derive(.{ .arm = .sword, .off = .wand, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    try std.testing.expect(worth(board, .guard) > 0 and worth(rod, .guard) == 0);
    try std.testing.expect(worth(board, .spell) == 0 and worth(rod, .spell) > 0);
    try std.testing.expect(worth(board, .spell_fp) == 0 and worth(rod, .spell_fp) > 0);
    const bowRod = derive(.{ .arm = .bow, .off = .wand, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    try std.testing.expect(worth(bowRod, .spell) == 0 and worth(bowRod, .guard) == 0);
    for ([_]Der{ .light, .heavy, .poise, .stance, .swing }) |k| {
        try std.testing.expectEqual(worth(board, k), worth(rod, k));
    }
    try std.testing.expectEqual(@as(u8, 0), castsLeft(combat.BOLT_FP - 0.01, .bolt, v));
    try std.testing.expectEqual(@as(u8, 1), castsLeft(combat.BOLT_FP, .bolt, v));
    try std.testing.expect(castsLeft(combat.FP_MAX, .bolt, v) >= 4);
}

test "THE PAGE PRICES THE SORCERY THAT IS LOADED, not the first one ever written" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var v = testViewOff(&bag, &sheet, &res, &flasks, &quiver, .sword, .wand);
    const bolt = derive(.{ .arm = .sword, .off = .wand, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    const roots = derive(.{ .arm = .sword, .off = .wand, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .roots }, v);
    try std.testing.expect(worth(roots, .spell_fp) > worth(bolt, .spell_fp));
    try std.testing.expect(worth(roots, .spell) < worth(bolt, .spell));
    try std.testing.expectApproxEqAbs(combat.spellFp(.roots), worth(roots, .spell_fp), 1e-4);
    try std.testing.expectEqualStrings(combat.spellName(.bolt), slotFilled(.sorcery, v));
    v.spell = .roots;
    try std.testing.expectEqualStrings(EMPTY, slotFilled(.sorcery, v));
    try std.testing.expect(!slotHas(.sorcery, v));
    v.mem.put(1, .roots);
    try std.testing.expectEqualStrings(combat.spellName(.roots), slotFilled(.sorcery, v));
    try std.testing.expect(slotHas(.sorcery, v));
    try std.testing.expect(castsLeft(combat.FP_MAX, .roots, v) < castsLeft(combat.FP_MAX, .bolt, v));
}

test "THE DERIVED COLUMN PRICES THE TREE'S OWN MULTIPLES, not only its attribute points" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var tree = ptree.Tree{};
    for (ptree.NODES, 0..) |n, i| switch (n.grant) {
        .guard, .spellCost, .spellDmg => tree.taken[i] = true,
        else => {},
    };
    const perk = tree.bonus();
    try std.testing.expect(perk.guard > 0 and perk.spellCost < 1 and perk.spellDmg > 1);

    var v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    v.tree = &tree;
    const boards = Loadout{ .arm = .sword, .off = .shield, .ammo = .plain, .quick = null, .spell = .bolt };
    try std.testing.expectApproxEqAbs(
        @min(combat.GUARD_NEGATE_CAP, combat.GUARD_NEGATE + perk.guard) * 100.0,
        worth(derive(boards, v), .guard),
        1e-3,
    );

    var rod = boards;
    rod.off = .wand;
    const bolt = derive(rod, v);
    try std.testing.expectApproxEqAbs(combat.BOLT_FP * perk.spellCost, worth(bolt, .spell_fp), 1e-3);
    const perked = sheetOf(rod, perk);
    try std.testing.expect(perked.at(.intelligence) > sheet.at(.intelligence));
    try std.testing.expectApproxEqAbs(
        combat.spellDamage(.bolt) * perk.spellDmg * perked.scale(.intelligence),
        worth(bolt, .spell),
        1e-3,
    );
    try std.testing.expect(castsLeft(combat.FP_MAX, .bolt, v) > castsLeft(combat.FP_MAX, .bolt, testView(&bag, &sheet, &res, &flasks, &quiver, .sword)));

    for ([_]combat.Spell{ .roots, .rime }) |s| {
        var flat = rod;
        flat.spell = s;
        try std.testing.expectApproxEqAbs(combat.spellDamage(s), worth(derive(flat, v), .spell), 1e-3);
    }
}

test "the bag cursor is pulled back onto a real cell when the last of something is drunk" {
    var bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    bag.add(.bloodgrass, 1);
    bag.add(.kobold_fang, 1);
    bag.add(.iron_key, 1);
    // Named, not counted — a positional literal goes stale the moment a page is added. Cell 0 is the PURSE, so
    // three carried kinds are cells 1..3.
    var b = Book{ .page = .inventory };
    b.cur[idx(.inventory)] = 3;
    b.clamp(testView(&bag, &sheet, &res, &flasks, &quiver, .sword));
    try std.testing.expectEqual(@as(usize, 3), b.cur[idx(.inventory)]);
    _ = bag.take(.iron_key, 1);
    b.clamp(testView(&bag, &sheet, &res, &flasks, &quiver, .sword));
    try std.testing.expectEqual(@as(usize, 2), b.cur[idx(.inventory)]);
    bag.clear();
    b.clamp(testView(&bag, &sheet, &res, &flasks, &quiver, .sword));
    try std.testing.expectEqual(@as(usize, 0), b.cur[idx(.inventory)]);
    try std.testing.expectEqual(item.Kind.gold_purse, bagAt(testView(&bag, &sheet, &res, &flasks, &quiver, .sword), 0).?);
    try std.testing.expectEqual(@as(usize, 0), b.scroll);
}

test "IN COMBAT THE BAG IS SHUT: the inventory refuses Use and the panel says where to go instead" {
    var bag = item.Bag{};
    bag.add(.mushroom_jerky, 3);
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};

    const calm = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    var fighting = calm;
    fighting.inCombat = true;

    var b = Book{};
    b.page = .inventory;
    b.cur[idx(.inventory)] = 1;
    try std.testing.expectEqual(item.Kind.mushroom_jerky, bagAt(calm, 1).?);
    try std.testing.expectEqual(Action{ .use = .mushroom_jerky }, b.confirm(calm));
    try std.testing.expectEqual(Action.none, b.confirm(fighting));
}

test "THE QUICK PICKER OFFERS ONLY WHAT HE HAS — and the flasks, which are never the bag's" {
    var bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var buf: [CAND_MAX]Cand = undefined;

    const broke = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    const bare = candidates(.q0, broke, &buf);
    try std.testing.expectEqual(@as(usize, 3), bare.len);
    try std.testing.expectEqual(@as(?item.Kind, null), bare[0].act.quick.kind);
    for (bare[1..]) |c| try std.testing.expect(combat.flaskOf(c.act.quick.kind.?) != null);

    bag.add(.mushroom_jerky, 1);
    bag.add(.kobold_fang, 4);
    const fed = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    var sawJerky = false;
    for (candidates(.q0, fed, &buf)) |c| {
        try std.testing.expectEqual(@as(usize, 0), c.act.quick.slot);
        const k = c.act.quick.kind orelse continue;
        try std.testing.expect(item.quickable(k));
        try std.testing.expect(combat.flaskOf(k) != null or fed.bag.count(k) > 0);
        try std.testing.expectEqual(fed.quick.slots[0] == k, equipped(c, fed));
        if (k == .mushroom_jerky) sawJerky = true;
    }
    try std.testing.expect(sawJerky);
    const opens = pickIndexOf(.q0, fed);
    try std.testing.expectEqual(fed.quick.slots[0], candidates(.q0, fed, &buf)[opens].act.quick.kind);
}

test "THE SCRATCH FITS THE LONGEST LIST ANY SOCKET CAN OFFER, empty row and all" {
    // `CAND_MAX` sized the buffer at `item.NK` and the quick picker writes `item.NK + 1` rows in the worst case — the "(empty)" one is a row like the others. It cannot be reached with today's six quickable kinds, which is why it has to be arithmetic.
    try std.testing.expect(CAND_MAX >= item.NK + 1);
    var bag = item.Bag{};
    for (0..item.NK) |i| bag.add(@enumFromInt(i), 1);
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    var buf: [CAND_MAX]Cand = undefined;
    for (0..NSLOT) |i| {
        const s: SlotId = @enumFromInt(i);
        try std.testing.expect(candidates(s, v, &buf).len <= CAND_MAX);
    }
}

test "the quick row prices whatever the bar holds, flask or not" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    _ = v;
    const bare = heromod.Worn{};
    try std.testing.expectApproxEqAbs(sheet.hp() * combat.FLASK_HP_FRAC, quickWorth(.crimson_flask, bare, sheet, .{}), 1e-3);
    try std.testing.expectApproxEqAbs(sheet.fp() * combat.FLASK_FP_FRAC, quickWorth(.cerulean_flask, bare, sheet, .{}), 1e-3);
    const jerky = item.use(.mushroom_jerky).regen;
    try std.testing.expectApproxEqAbs(sheet.hp() * jerky.frac, quickWorth(.mushroom_jerky, bare, sheet, .{}), 1e-3);
    var ringed = heromod.Worn{};
    ringed.put(.ring, .leech_signet);
    try std.testing.expect(quickWorth(.crimson_flask, ringed, sheet, .{}) < quickWorth(.crimson_flask, bare, sheet, .{}));
}

test "the sockets are fitted to the panel, and never off the end of it" {
    for ([_][2]i32{ .{ 640, 400 }, .{ 1280, 800 }, .{ 2560, 1440 }, .{ 3840, 2160 } }) |wh| {
        const card = Box{ .x = 0, .y = 0, .w = wh[0], .h = wh[1] };
        const body = Box{ .x = card.x, .y = card.y + headH(), .w = card.w, .h = card.h - headH() - 40 };
        const inner = panelInner(equipCols(body)[0], false);
        const f = slotFit(body);
        try std.testing.expect(f.px >= SLOT_MIN and f.px <= SLOT_MAX);
        for (0..NSLOT) |i| {
            const r = slotRect(body, i);
            try std.testing.expect(r.x >= fi(inner.x) - 1);
            try std.testing.expect(r.x + r.width <= fi(inner.x + inner.w) + 1);
            try std.testing.expect(r.y >= fi(inner.y) - 1);
        }
    }
    const small = slotFit(.{ .x = 0, .y = 0, .w = 620, .h = 380 });
    const big = slotFit(.{ .x = 0, .y = 0, .w = 2400, .h = 1300 });
    try std.testing.expect(big.px > small.px);
}

test "BOTH PAGES SPEAK IN NUMBERS, and the three classes are told apart by them" {
    for ([_]Der{ .light, .heavy, .elem, .poise, .stance, .hp, .fp, .armour }) |k| {
        try std.testing.expectEqual(Unit.flat, DER[@intFromEnum(k)].unit);
    }
    try std.testing.expectEqual(Unit.secs, DER[@intFromEnum(Der.swing)].unit);
    try std.testing.expectEqual(Unit.flat, GROW[@intFromEnum(GDial.dmg_light)].unit);
    try std.testing.expectEqual(Unit.flat, GROW[@intFromEnum(GDial.dmg_heavy)].unit);
    try std.testing.expectEqual(Unit.secs, GROW[@intFromEnum(GDial.swing)].unit);

    for (DER) |row| {
        for ([_][]const u8{ "Stamina", "Roll", "Sprint" }) |bill| {
            if (std.mem.indexOf(u8, row.name, bill) != null) {
                std.debug.print("\n  the sheet still bills: {s}\n", .{row.name});
                return error.TestUnexpectedResult;
            }
        }
    }

    var bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);

    const rows = [_]struct { arm: heromod.Armament, socket: item.Wear, kind: ?item.Kind }{
        .{ .arm = .sword, .socket = .hand_sword, .kind = null },
        .{ .arm = .dagger, .socket = .hand_dagger, .kind = item.Kind.fang_dirk },
        .{ .arm = .club, .socket = .hand_club, .kind = item.Kind.greatclub },
        .{ .arm = .bow, .socket = .hand_bow, .kind = item.Kind.grave_warbow },
    };
    var dirk: f32 = 0;
    var club: f32 = 0;
    var dirkT: f32 = 0;
    var clubT: f32 = 0;
    std.debug.print("\n", .{});
    for (rows) |r| {
        const d = dialsOf(r.kind, r.socket, v);
        const hi = d.v[@intFromEnum(GDial.dmg_heavy)].?;
        const secs = d.v[@intFromEnum(GDial.swing)].?;
        std.debug.print("  {s: <8} light {d:.0}  heavy {d:.0}  poise {d:.0}  in {d:.2}s\n", .{
            @tagName(r.arm),
            d.v[@intFromEnum(GDial.dmg_light)].?,
            hi,
            d.v[@intFromEnum(GDial.poise)].?,
            secs,
        });
        try std.testing.expect(hi > 1.0 and secs > 0.05);
        if (r.arm == .dagger) {
            dirk = hi;
            dirkT = secs;
        }
        if (r.arm == .club) {
            club = hi;
            clubT = secs;
        }
    }
    try std.testing.expect(club > dirk and clubT > dirkT);

    const board = dialsOf(item.Kind.tower_shield, .hand_shield, v);
    try std.testing.expect(board.v[@intFromEnum(GDial.dmg_heavy)] == null);
    try std.testing.expect(board.v[@intFromEnum(GDial.swing)] == null);
    const neg = board.v[@intFromEnum(GDial.negate)].?;
    try std.testing.expectApproxEqAbs(combat.guardNegation(item.equip(.tower_shield).arm.negate, TEST_TREE.bonus().guard) * 100, neg, 1e-3);
    try std.testing.expect(neg <= combat.GUARD_NEGATE_CAP * 100 + 1e-3);
    try std.testing.expectApproxEqAbs(combat.GUARD_ARC * item.equip(.tower_shield).arm.arc, board.v[@intFromEnum(GDial.arc)].?, 1e-3);
    std.debug.print("  tower shield: negates {d:.0}% over a {d:.0} deg arc, and prices no swing\n", .{ neg, board.v[@intFromEnum(GDial.arc)].? });

    var held: usize = 0;
    for (0..NSLOT) |i| {
        const s: SlotId = @enumFromInt(i);
        const f = browsing(s, v) orelse {
            try std.testing.expect(wearOf(s) == null);
            continue;
        };
        try std.testing.expect(f.socket != null);
        if (f.socket.?.held()) {
            held += 1;
            try std.testing.expect(cardShape(v, f).rows > 0);
        }
    }
    try std.testing.expect(held >= 2);

    v.worn.put(.chest, .rimeward_mantle);
    const coat = browsing(.chest, v).?;
    try std.testing.expectEqual(item.Kind.rimeward_mantle, coat.now.?);
    const cd = dialsOf(coat.now, coat.socket, v);
    try std.testing.expectApproxEqAbs(item.equip(.rimeward_mantle).plate.a, cd.v[@intFromEnum(GDial.armour)].?, 1e-4);
    try std.testing.expectApproxEqAbs(item.equip(.rimeward_mantle).plate.res.cold, cd.v[@intFromEnum(GDial.res_cold)].?, 1e-4);
    try std.testing.expect(cd.v[@intFromEnum(GDial.walk)] == null);
}

test "THE SHEET CARRIES THE FOUR COLUMNS AND THE POOLS, and a swap moves them" {
    const bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);

    const bare = Loadout{ .arm = .sword, .off = .shield, .ammo = .plain, .quick = null, .spell = .bolt };
    var coated = bare;
    coated.worn.put(.chest, .rimeward_mantle);
    const b = derive(bare, v);
    const c = derive(coated, v);
    const cold = @intFromEnum(Der.res_fire) + @intFromEnum(combat.Elem.cold);
    std.debug.print("\n  sheet: bare cold {d:.0}%, in the mantle {d:.0}%; armour {d:.0} to {d:.0}, negating {d:.0}% to {d:.0}%\n", .{
        b[cold],           c[cold],
        worth(b, .armour), worth(c, .armour),
        worth(b, .negate), worth(c, .negate),
    });
    try std.testing.expect(c[cold] > b[cold]);
    try std.testing.expect(worth(c, .armour) > worth(b, .armour));
    try std.testing.expect(worth(c, .negate) > worth(b, .negate));
    try std.testing.expect(c[cold] <= combat.RES_CAP);

    var ringed = bare;
    ringed.worn.put(.ring, .bloodtinge_signet);
    try std.testing.expect(worth(derive(ringed, v), .hp) > worth(b, .hp));
    var belled = bare;
    belled.worn.put(.neck, .gravebell_amulet);
    try std.testing.expect(worth(derive(belled, v), .fp) < worth(b, .fp));

    try std.testing.expect(DER_SPLIT > 0 and DER_SPLIT < ND);
    for (DER) |row| try std.testing.expect(row.name.len > 0);
}

test "A DIFFERENCE IS SAID WITH ITS SIGN, and a hair of drift is not a difference" {
    try std.testing.expectEqualStrings("+12", deltaStr(.flat, 10, 22));
    try std.testing.expectEqualStrings("-3", deltaStr(.flat, 10, 7));
    try std.testing.expectEqualStrings("+35%", deltaStr(.pct, 0, 35));
    try std.testing.expectEqualStrings("+0.08s", deltaStr(.secs, 0.67, 0.75));
    try std.testing.expect(!moves(.flat, 10, 10.2));
    try std.testing.expect(moves(.flat, 10, 11));
    try std.testing.expect(!moves(.secs, 0.67, 0.672));
    try std.testing.expect(moves(.secs, 0.67, 0.69));
}

test "EVERY GEAR DIAL SITS IN ONE SECTION, the sections run in the enum's order, and none is empty" {
    var count = [_]usize{0} ** NGS;
    var last: ?GSection = null;
    for (0..NGD) |i| {
        const s = gsectionOf(@enumFromInt(i));
        count[@intFromEnum(s)] += 1;
        if (last) |l| try std.testing.expect(@intFromEnum(s) >= @intFromEnum(l));
        last = s;
    }
    for (count) |n| try std.testing.expect(n > 0);
}

test "A CANDIDATE LEADS WITH THE NUMBER IT MOVES MOST — the club its damage, the mantle its armour, and a swap for the same thing says nothing" {
    var bag = item.Bag{};
    bag.add(.greatclub, 1);
    bag.add(.rimeward_mantle, 1);
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    const v = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    const base = inForce(v);
    const now = derive(base, v);

    const club = Cand{ .name = "club", .act = .{ .arm = .{ .a = .club, .kind = .greatclub } } };
    const h = headline(club, v, base, now).?;
    const mantle = Cand{ .name = "mantle", .act = .{ .wear = .{ .slot = .chest, .kind = .rimeward_mantle } } };
    const m = headline(mantle, v, base, now).?;
    std.debug.print("\n  headlines: club '{s}', mantle '{s}'\n", .{ h.text, m.text });
    try std.testing.expect(std.mem.indexOf(u8, h.text, "heavy") != null or std.mem.indexOf(u8, h.text, "light") != null);
    try std.testing.expect(h.good);
    try std.testing.expect(std.mem.indexOf(u8, m.text, "armour") != null);
    try std.testing.expect(m.good);

    const same = Cand{ .name = "sword", .act = .{ .arm = .{ .a = .sword } } };
    try std.testing.expect(headline(same, v, base, now) == null);
}

test "the stats page is FOUR panels that tile the body, the attributes the widest of the three sheets" {
    const body = Box{ .x = 40, .y = 90, .w = 1200, .h = 600 };
    const c = statsCols(body);
    try std.testing.expectEqual(body.x, c[0].x);
    try std.testing.expectEqual(body.right(), c[3].right());
    try std.testing.expectEqual(c[0].right() + GUTTER, c[1].x);
    try std.testing.expectEqual(c[1].right() + GUTTER, c[2].x);
    try std.testing.expectEqual(c[2].right() + GUTTER, c[3].x);
    try std.testing.expect(c[0].w > c[1].w);
    try std.testing.expect(@abs(c[1].w - c[2].w) <= 1);
    for (c) |b| try std.testing.expectEqual(body.h, b.h);
}

test "the next point is priced in the unit the attribute governs, and a ceiling says so" {
    var s = stats.Sheet{};
    const says = nextPointSays(.vitality, &s);
    try std.testing.expect(std.mem.indexOf(u8, says, "HP") != null);
    try std.testing.expect(std.mem.indexOf(u8, attrFigure(.endurance, &s), "stamina") != null);
    s.set(.luck, stats.MAX);
    try std.testing.expectEqualStrings("At its ceiling.", nextPointSays(.luck, &s));
}

test "A PAGE THAT PANS SAYS SO — every gesture the book takes is named on the page that takes it" {
    var b = Book{};
    var buf: [FOOT_CAP]hud.Hint = undefined;
    var checked: usize = 0;
    inline for (@typeInfo(Page).@"enum".fields) |f| {
        b.page = @enumFromInt(f.value);
        b.picking = null;
        const hints = footHints(&b, &buf);
        try std.testing.expect(hints.len <= FOOT_CAP);
        var pan = false;
        var zoom = false;
        for (hints) |h| {
            if (std.mem.eql(u8, h.label, hud.HINT_PAN.label)) pan = true;
            if (std.mem.eql(u8, h.label, hud.HINT_ZOOM.label)) zoom = true;
        }
        if (b.page.panned()) {
            if (!pan or !zoom) std.debug.print("\n  the book's {s} page takes the stick and the d-pad and names pan={} zoom={}\n", .{ f.name, pan, zoom });
            try std.testing.expect(pan and zoom);
            checked += 1;
        } else {
            try std.testing.expect(!pan and !zoom);
        }
    }
    try std.testing.expect(checked > 0);
    std.debug.print("\n  book cribs: {d} pages, {d} of them panned and both gestures named on each\n", .{ NPAGE, checked });
}
