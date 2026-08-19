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
const sfx = @import("../core/audio.zig");


const rgba = mathx.rgba;
const v3 = mathx.v3;

pub const Page = enum {
    equipment,
    inventory,
    stats,
    tree,

    fn label(p: Page) [:0]const u8 {
        return switch (p) {
            .equipment => "EQUIPMENT",
            .inventory => "INVENTORY",
            .stats => "STATS",
            .tree => "PASSIVE TREE",
        };
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
    inCombat: bool = false,
    arm: heromod.Armament,
    off: heromod.Armament,
    armAlt: heromod.Armament = .bow,
    offAlt: heromod.Armament = .wand,
    spell: combat.Spell,
    fp: f32,
    souls: u32,
    worn: heromod.Worn = .{},

    pub fn holds(self: *const View, a: heromod.Armament) bool {
        return heromod.handsHold(self.arm, self.off, a);
    }
    pub fn offInHand(self: *const View) bool {
        return !heromod.armTwoHanded(self.arm) and !heromod.armTwoHanded(self.off);
    }
};

pub const Portrait = struct { hero: *const heromod.Hero, scene: *gfx.Scene };


const Loadout = struct {
    arm: heromod.Arm,
    off: heromod.Off,
    ammo: combat.ArrowKind,
    quick: ?item.Kind,
    spell: combat.Spell,
    worn: heromod.Worn = .{},
};

const Unit = enum { flat, pct, count };

const Der = enum {
    light,
    heavy,
    fire,
    poise,
    stance,
    stam_light,
    stam_heavy,
    guard,
    arc,
    armour,
    spell,
    spell_fp,
    quick,
    ammo,
};
const ND = @typeInfo(Der).@"enum".fields.len;

fn worth(d: [ND]f32, k: Der) f32 {
    return d[@intFromEnum(k)];
}

const DerivedRow = struct { name: [:0]const u8, unit: Unit, cost: bool = false };

const DER = blk: {
    var rows: [ND]DerivedRow = undefined;
    rows[@intFromEnum(Der.light)] = .{ .name = "Light attack", .unit = .flat };
    rows[@intFromEnum(Der.heavy)] = .{ .name = "Heavy attack", .unit = .flat };
    rows[@intFromEnum(Der.fire)] = .{ .name = "Fire damage", .unit = .flat };
    rows[@intFromEnum(Der.poise)] = .{ .name = "Poise damage", .unit = .flat };
    rows[@intFromEnum(Der.stance)] = .{ .name = "Stance damage", .unit = .flat };
    rows[@intFromEnum(Der.stam_light)] = .{ .name = "Stamina, light", .unit = .flat, .cost = true };
    rows[@intFromEnum(Der.stam_heavy)] = .{ .name = "Stamina, heavy", .unit = .flat, .cost = true };
    rows[@intFromEnum(Der.guard)] = .{ .name = "Guard negation", .unit = .pct };
    rows[@intFromEnum(Der.arc)] = .{ .name = "Guard arc", .unit = .flat };
    rows[@intFromEnum(Der.armour)] = .{ .name = "Armour, vs heavy", .unit = .pct };
    rows[@intFromEnum(Der.spell)] = .{ .name = "Sorcery damage", .unit = .flat };
    rows[@intFromEnum(Der.spell_fp)] = .{ .name = "Focus, per cast", .unit = .flat, .cost = true };
    rows[@intFromEnum(Der.quick)] = .{ .name = "Quick item restores", .unit = .flat };
    rows[@intFromEnum(Der.ammo)] = .{ .name = "Ammunition", .unit = .count };
    break :blk rows;
};

const armourOf = heromod.armourOf;

fn sheetOf(l: Loadout, perk: ptree.Bonus) stats.Sheet {
    var s = perk.sheet();
    heromod.boonsOnto(l.worn, &s);
    return s;
}

fn castFp(s: combat.Spell, perk: ptree.Bonus) f32 {
    return combat.spellFp(s) * perk.spellCost;
}

fn derive(l: Loadout, v: View) [ND]f32 {
    const bow = heromod.handsHold(l.arm, l.off, .bow);
    // …AND WHETHER THAT HAND HAS AN ATTACK AT ALL (`hero.armSwings`). `bow` alone was the whole question while
    // there were two armaments; the BELL has neither a light nor a heavy, so every row below came off the
    // SWORD and the page priced a swing he cannot take. Zero is the honest figure, and the arm's own tip
    // already says it in words.
    const attacks = bow or heromod.armSwings(l.arm) or heromod.armSwings(l.off);
    const row = heromod.armRow(l.worn, if (bow) .hand_bow else .hand_sword);
    const perk = v.tree.bonus();
    const sheet = sheetOf(l, perk);
    const light = heromod.weigh(if (bow) heromod.arrowBlow(l.ammo, false, perk) else heromod.ATK_LIGHT_HIT, row, sheet);
    const heavy = heromod.weigh(if (bow) heromod.arrowBlow(l.ammo, true, perk) else heromod.ATK_HEAVY_HIT, row, sheet);
    var d: [ND]f32 = undefined;
    d[@intFromEnum(Der.light)] = if (attacks) light.dmg else 0;
    d[@intFromEnum(Der.heavy)] = if (attacks) heavy.dmg else 0;
    d[@intFromEnum(Der.fire)] = if (attacks) heavy.elem.total() else 0;
    d[@intFromEnum(Der.poise)] = if (attacks) heavy.poise else 0;
    d[@intFromEnum(Der.stance)] = if (attacks) heavy.stance else 0;
    d[@intFromEnum(Der.stam_light)] = if (!attacks) 0 else @as(f32, if (bow) combat.STAM_SHOT else combat.STAM_LIGHT) * row.stam;
    d[@intFromEnum(Der.stam_heavy)] = if (!attacks) 0 else @as(f32, if (bow) combat.STAM_AIMED else combat.STAM_HEAVY) * row.stam;
    const guards = heromod.handsHold(l.arm, l.off, .shield);
    const board = heromod.armRow(l.worn, .hand_shield);
    // THE BOARD'S OWN NEGATION **PLUS THE TREE'S**, capped where the fight caps it (`hero.blockHit`, and
    // `combat.GUARD_NEGATE_CAP`) — a page promising 97% behind a door the fight holds to 95 is a page lying
    // about the one number it exists to compare, and one that leaves the guard node out lies the other way.
    d[@intFromEnum(Der.guard)] = if (guards) @min(combat.GUARD_NEGATE_CAP, combat.GUARD_NEGATE * board.negate + perk.guard) * 100.0 else 0;
    d[@intFromEnum(Der.arc)] = if (guards) combat.GUARD_ARC * board.arc else 0;
    d[@intFromEnum(Der.armour)] = 100.0 * (1.0 - combat.armourTaken(armourOf(l.worn), heromod.ATK_HEAVY_HIT.dmg) / heromod.ATK_HEAVY_HIT.dmg);
    // …and what he bought with it. Zero on both rows unless a wand is actually in that hand, because a spell
    // he cannot cast is not worth a number — and it is the SORCERY THAT IS LOADED that is priced, through
    // `combat`'s own two answers: the rod carries FIVE, and no two of them cost or deal the same.
    const casts = heromod.handsHold(l.arm, l.off, .wand);
    // …through the WHOLE multiple the cast itself takes (`hero.castBlow`: the sorcery node times INTELLIGENCE),
    // and **ONLY FOR THE THREE THAT ARE SCALED AT ALL**. `spellBlow` is null for the roots and the rime because
    // neither lands a blow — their chaos and their cold are billed flat, a frame at a time, by `combat.Root.tick`
    // and `combat.Chill.tick`, which read no sheet and no perk. Multiplied here, the page promised an Intelligence
    // build a stronger grip and a colder breath than it was ever going to get.
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

/// A socket`s ordinal, for the shot harness — so a frame is aimed at a NAME and not at a number that moves.
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
        .chest => "Nothing you are carrying goes on the body.",
        .ring, .ring2 => "Nothing you are carrying goes on a finger.",
        .helm => "Nothing you are carrying goes on your head.",
        .neck => "Nothing you are carrying hangs at the throat.",
        .belt => "Nothing you are carrying goes round the waist.",
        .feet => "Nothing you are carrying goes on your feet.",
        .hand_sword, .hand_bow, .hand_shield => "Nothing you are carrying fills that hand.",
    };
}

fn locked(s: SlotId, v: View) ?[:0]const u8 {
    if (wearOf(s)) |w| return if (!carriesFor(w, v)) emptyHanded(w) else null;
    return switch (s) {
        .left => if (!v.offInHand()) "Both hands are on the bow. The other comes back when the bow goes away." else null,
        // AN ALTERNATE IS NEVER LOCKED: it is what he is NOT holding, so nothing he is holding can deny it.
        .left2, .right2 => null,
        .sorcery => if (v.holds(.bow))
            "Both hands are on the bow. Nothing is free to hold a wand."
        else if (!v.holds(.wand))
            "No wand in his hand to cast a sorcery with."
        else
            "The rod is turned to its other sorcery with D-pad Up.",
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
        .sorcery => v.holds(.wand),
        .arrows => v.quiver.count(v.quiver.sel) > 0,
        else => quickAt(s, v) != null,
    };
}

const EMPTY = "-";

fn armName(a: heromod.Armament) [:0]const u8 {
    return switch (a) {
        .sword => "Straight Sword",
        .bow => "Short Bow",
        .bell => "Summoning Bell",
        .shield => "Small Shield",
        .wand => "Knotted Wand",
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
        .crimson => hpMax * combat.FLASK_HP_FRAC,
        .cerulean => heromod.fpMaxOf(sheet, worn, perk) * combat.FLASK_FP_FRAC,
    };
    return switch (item.use(k)) {
        .none => 0,
        .regen => |r| hpMax * r.frac,
        .lob => |b| b.dmg + b.fire + b.lightning,
        .ward, .wind, .grease, .souls, .brew, .purge, .steady => 0,
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

/// The longest candidate list any slot can offer, off the enums themselves — the scratch every caller
/// hands `candidates` is sized from this, so a third arrow cannot write past the end of one.
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
    // THE WORN SOCKETS, ASKED THROUGH `wearOf` AND NOT LISTED AGAIN — `locked`, `slotHas`, `slotFilled` and
    // `slotTally` all open on exactly this line. Written out as a seven-tag prong instead, a socket added to
    // `wearOf` fell through to the `else` below and offered a helm the QUICK BAR's rows.
    // What he carries for it, plus an EMPTY row: a coat you cannot take off is a coat the player is stuck in.
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
                out[n] = .{ .name = armName(a), .act = handAct(s, .{ .a = a }) };
                n += 1;
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

/// **THE SET ACTUALLY IN FORCE** — what the NOW column prices, and `withCand`'s starting point. Named because it
/// is every axis of the loadout and leaving ONE of them out is silent: built inline with `worn` left at its
/// default, the whole column priced a bare body, so a greatclub in his fist read the plain sword's damage, a door
/// read the small shield's negation and arc, and "Armour, vs heavy" read 0% over a full suit.
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

/// Where a picker opens: on what is ALREADY equipped, never on row 0 — landing the cursor somewhere other
/// than the current choice is how a menu tricks you into swapping something you meant to look at.
///
/// **ASKED OF THE LIST ITSELF, NEVER COUNTED A SECOND TIME.** Three of these were hand-walked copies of
/// `candidates`' own ordering — a hand's two interleaved axes, a worn socket's "(nothing)" row, the quick bar's
/// filtered one — parallel lists kept in lockstep by hand, and a cursor that opens on the wrong row is exactly
/// the failure this function exists to prevent. `equipped` already answers "is THIS row the one in force" for
/// every action there is, so the row is where that first says yes, and the two cannot drift apart.
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
        const bag = @max(v.bag.distinct(), 1);
        self.cur[idx(.inventory)] = @min(self.cur[idx(.inventory)], bag - 1);
        self.cur[idx(.equipment)] = @min(self.cur[idx(.equipment)], NSLOT - 1);
        self.cur[idx(.stats)] = @min(self.cur[idx(.stats)], stats.NA - 1);
        const rows = (bag + BAG_COLS - 1) / BAG_COLS;
        self.scroll = @min(self.scroll, rows -| BAG_ROWS);
        const row = self.cur[idx(.inventory)] / BAG_COLS;
        if (row < self.scroll) self.scroll = row;
        if (row >= self.scroll + BAG_ROWS) self.scroll = row - BAG_ROWS + 1;
    }

    fn thump(self: *Book) void {
        self.pop = POP_DUR;
    }

    pub fn onTab(self: *Book, dir: i32) void {
        if (self.picking != null) return; // a page cannot change under an open picker
        const n: i32 = NPAGE;
        const i: i32 = @intCast(@intFromEnum(self.page));
        self.page = @enumFromInt(@as(usize, @intCast(@mod(i + dir + n, n))));
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
        const i = idx(self.page);
        const next = switch (self.page) {
            .equipment => slotStep(self.cur[i], sx, sy),
            .inventory => grid(self.cur[i], @max(v.bag.distinct(), 1), BAG_COLS, sx, sy),
            .stats => if (sy == 0) self.cur[i] else @as(usize, @intCast(@mod(
                @as(i32, @intCast(self.cur[i])) + sy + @as(i32, stats.NA),
                @as(i32, stats.NA),
            ))),
            .tree => unreachable,
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
        if (self.page != .tree or self.picking != null or dv == 0) return;
        self.wheel.zoomBy(dv, dt);
    }

    pub fn panBy(self: *Book, v: rl.Vector2, dt: f32) void {
        if (self.page != .tree or self.picking != null) return;
        self.wheel.panBy(v, dt);
    }

    pub fn wheelUp(self: *const Book) bool {
        return self.page == .tree and self.picking == null;
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
                if (v.bag.nth(self.cur[idx(.inventory)])) |k| {
                    if (item.usable(k) and !v.inCombat) {
                        self.thump();
                        sfx.play(.menu_pick);
                        return .{ .use = k };
                    }
                }
                sfx.play(.menu_back);
            },
            .stats => sfx.play(.menu_back),
            .tree => sfx.play(.menu_back),
        }
        return .none;
    }

    /// Stage a page for the shot harness, `ogre.debugStagger`'s pattern: a photograph of the picker open
    /// on the second candidate cannot be got by pretending to press buttons at 1/60 s a frame.
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
            .tree => return ptree.nodeRect(self.wheel, body.x, body.y, body.w, body.h),
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

/// Where socket `i` sits. One table (`SLOT_CELL`) feeds this and the cursor, so the picture and the walk
/// cannot disagree.
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
    return rowFloor() * @as(i32, ND) + hud.lineH(hud.TINY) + 4 + hud.lineH(hud.HINT) * 2 + 22 + 28;
}

fn pickBox(col: Box, n: usize) Box {
    const want = pickRowH() * @as(i32, @intCast(n)) + titleH() + 24;
    // …and never under a quarter of the column, or a narrow window squeezes the list being chosen FROM to
    // nothing in order to protect numbers nobody can read on it either.
    const room = @max(@divTrunc(col.h, 4), col.h - derivedNeedH() - GUTTER);
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

fn statsCols(body: Box) [3]Box {
    const portW = @min(@divTrunc(body.w * 34, 100), 470);
    const rest = body.cut(body.w - portW - GUTTER);
    const two = rest[0].cut(@divTrunc(rest[0].w - GUTTER, 2));
    return .{ two[0], two[1], rest[1] };
}

fn attrStep() i32 {
    return hud.lineH(hud.BODY) + 16;
}

fn attrRow(col: Box, i: usize) rl.Rectangle {
    const inner = panelInner(col, true);
    return rect(inner.x - 10, inner.y + @as(i32, @intCast(i)) * attrStep() - 6, inner.w + 20, attrStep() - 4);
}


var scratch: [16][160]u8 = undefined;
var scratchAt: usize = 0;

fn fmt(comptime f: []const u8, args: anytype) [:0]const u8 {
    scratchAt = (scratchAt + 1) % scratch.len;
    return std.fmt.bufPrintZ(&scratch[scratchAt], f, args) catch "?";
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

/// THE PITCH `n` ROWS GET IN `space` PIXELS: their natural one, tightened to fit, and NEVER under the GLYPH
/// height. A panel too short for its rows spills off the bottom, which is ugly, where a negative pitch stacks
/// them backwards up through the heading, which is unreadable. The floor used to be `lineH`, which twelve
/// rows cannot make fit in the half-panel a picker leaves them: they overran the foot and the divider drew
/// straight through the last row.
fn rowStep(space: i32, n: usize) i32 {
    const natural = hud.lineH(hud.SMALL) + 7;
    // A picker CAN be open on a slot with nothing to offer (`candidates` returns an empty slice for a locked
    // one), and that reaches here through `pickStep` as a divide by zero.
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
        .flat => if (x <= 0.005) "-" else fmt("{d:.0}", .{x}),
        .pct => if (x <= 0.005) "-" else fmt("{d:.0}%", .{x}),
        .count => fmt("{d:.0}", .{x}),
    };
}

const PROSE_LINES = 8;
const PROSE_BUF = 768;
var proseLines: [PROSE_LINES][:0]const u8 = undefined;
var proseBuf: [PROSE_BUF]u8 = undefined;

fn proseWrap(s: []const u8, w: i32, size: i32) []const [:0]const u8 {
    return hud.wrap(s, size, w, &proseBuf, &proseLines);
}

fn prose(s: []const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color) i32 {
    var yy = y;
    for (proseWrap(s, w, size)) |line| {
        hud.text(line, x, yy, size, col);
        yy += hud.lineH(size);
    }
    return yy;
}

fn proseH(s: []const u8, w: i32, size: i32) i32 {
    return @as(i32, @intCast(proseWrap(s, w, size).len)) * hud.lineH(size);
}

pub fn draw(self: *const Book, v: View, portrait: ?Portrait) void {
    const card = cardBox();
    uiart.seat(card.x, card.y, card.w, card.h);
    uiart.plate(card.x, card.y, card.w, card.h, 236);
    uiart.frame(card.x, card.y, card.w, card.h, uiart.flick(200, card.x));

    drawTabs(self, card, v);
    const body = bodyBox(card);
    switch (self.page) {
        .equipment => drawEquipment(self, body, v),
        .inventory => drawInventory(self, body, v),
        .stats => drawStats(self, body, v, portrait),
        .tree => drawTree(self, body, v),
    }

    if (self.at.width > 1 and self.page != .tree) {
        uiart.slotCursor(
            @intFromFloat(self.at.x),
            @intFromFloat(self.at.y),
            @intFromFloat(self.at.width),
            @intFromFloat(self.at.height),
            self.press,
            1.0,
        );
    }

    const PAGE = hud.Hint{ .glyph = .{ .bumper = "LB/RB" }, .label = "Page" };
    const CLOSE = hud.Hint{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Close" };
    const CANCEL = hud.Hint{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Cancel" };
    var buf: [6]hud.Hint = undefined;
    const hints: []const hud.Hint = switch (self.page) {
        .equipment => if (self.picking) |ps| blk: {
            buf[0] = .{ .glyph = .{ .dpad = .updown }, .label = "Choose" };
            buf[1] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = if (quickIndex(ps) != null) "Socket" else "Equip" };
            buf[2] = CANCEL;
            break :blk buf[0..3];
        } else blk: {
            buf[0] = .{ .glyph = .{ .dpad = .updown }, .label = "Move" };
            buf[1] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Open" };
            buf[2] = PAGE;
            buf[3] = CLOSE;
            break :blk buf[0..4];
        },
        .inventory => blk: {
            buf[0] = .{ .glyph = .{ .dpad = .updown }, .label = "Move" };
            buf[1] = .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Use" };
            buf[2] = PAGE;
            buf[3] = CLOSE;
            break :blk buf[0..4];
        },
        .stats => blk: {
            buf[0] = .{ .glyph = .{ .dpad = .updown }, .label = "Read" };
            buf[1] = .{ .glyph = .{ .dpad = .leftright }, .label = "Turn" };
            buf[2] = PAGE;
            buf[3] = CLOSE;
            break :blk buf[0..4];
        },
        .tree => blk: {
            buf[0] = .{ .glyph = .{ .bumper = "LS" }, .label = "Walk" };
            buf[1] = .{ .glyph = .{ .bumper = "RS" }, .label = "Zoom" };
            buf[2] = PAGE;
            buf[3] = CLOSE;
            break :blk buf[0..4];
        },
    };
    const hw = hud.hintRowW(hints, hud.HINT);
    hud.hintRowAt(
        hints,
        card.x + @divTrunc(card.w - hw, 2),
        card.y + card.h - footH() + 2 + @divTrunc(hud.lineH(hud.HINT), 2),
        hud.HINT,
        uiart.TEXT_HINT,
    );
}

fn drawTabs(self: *const Book, card: Box, v: View) void {
    const y = card.y + 12;
    var w: [NPAGE]i32 = undefined;
    var total: i32 = 0;
    inline for (0..NPAGE) |i| {
        const p: Page = @enumFromInt(i);
        w[i] = hud.textW(p.label(), hud.TITLE);
        total += w[i];
    }
    const gap: i32 = @max(40, @divTrunc(card.w - total - 260, @as(i32, NPAGE) + 1));
    var x = card.x + @divTrunc(card.w - (total + gap * (@as(i32, NPAGE) - 1)), 2);
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
    const souls = fmt("{d}", .{v.souls});
    const rx = card.right() - PAD - hud.textW(souls, hud.BODY);
    hud.text(souls, rx, y + 8, hud.BODY, uiart.TEXT_VALUE);
    hud.text("SOULS", rx - hud.textW("SOULS", hud.TINY) - 10, y + 12, hud.TINY, uiart.TEXT_DIM);
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
    hud.text(
        name,
        inner.x + @divTrunc(inner.w - hud.textW(name, hud.BODY), 2),
        @as(i32, @intFromFloat(q.y + q.height)) + 12,
        hud.BODY,
        uiart.HOT,
    );

    var buf: [CAND_MAX]Cand = undefined;
    const cs = if (self.picking) |s| candidates(s, v, &buf) else buf[0..0];
    if (self.picking) |s| drawPicker(self, cols[1], s, v);
    drawDerived(derivedBox(body, cs.len), v, if (self.pick < cs.len) cs[self.pick] else null);
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
    if (heromod.heldGear(a, worn)) |k| return itemart.drawHeld(k, cx, cy, px, true);
    armArt(a, cx, cy, px);
}

fn drawDerived(box: Box, v: View, cand: ?Cand) void {
    const inner = panel(box, "");
    const base = inForce(v);
    const now = derive(base, v);
    const then = if (cand) |c| derive(withCand(base, c), v) else now;

    const says = if (cand) |c| candSays(c, v) else armSays(v.arm, v.off);
    const foot = proseH(says, inner.w, hud.HINT) + 22;
    const step0 = rowStep(inner.h - foot - hud.lineH(hud.SMALL) - 4, ND);
    const size = rowSize(step0);
    const head: i32 = if (cand == null) 0 else hud.lineH(size) + 4;
    const step = rowStep(inner.h - foot - head, ND);
    const colB = inner.right();
    const colA = colB - @divTrunc(inner.w, 3);
    var y = inner.y;
    if (cand != null) {
        rowValueAt("NOW", colA, y, size, uiart.TEXT_DIM);
        rowValueAt("THEN", colB, y, size, mathx.withAlpha(uiart.GILT, 220));
        y += head;
    }
    for (DER, 0..) |row, i| {
        const moved = @abs(then[i] - now[i]) > 0.005;
        rowLabelAt(row.name, inner.x, y, size, if (moved) uiart.TEXT_VALUE else uiart.TEXT_DIM);
        if (cand == null) {
            rowValueAt(unitStr(row.unit, now[i]), colB, y, size, uiart.TEXT_VALUE);
        } else {
            rowValueAt(unitStr(row.unit, now[i]), colA, y, size, mathx.withAlpha(uiart.TEXT_DIM, 200));
            const rose = then[i] > now[i];
            const col = if (!moved) uiart.TEXT_DIM else if (rose != row.cost) uiart.GOOD else uiart.BAD;
            rowValueAt(unitStr(row.unit, then[i]), colB, y, size, col);
            if (moved) uiart.diamond(fi(colA + 20), fi(y) + fi(hud.lineH(size)) * 0.45, if (rose) 3.4 else 2.2, col);
        }
        y += step;
    }
    const footY = @max(inner.y + inner.h - foot + 22, y + 8);
    uiart.divider(inner.x + @divTrunc(inner.w, 2), @max(footY - 12, y + 2), @divTrunc(inner.w, 2) - 10, 120);
    _ = prose(says, inner.x, footY, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn armArt(a: heromod.Armament, cx: f32, cy: f32, px: f32) void {
    switch (a) {
        .sword => itemart.sword(cx, cy, px),
        .bow => itemart.bow(cx, cy, px),
        .bell => itemart.bell(cx, cy, px),
        .shield => itemart.shield(cx, cy, px),
        .wand => itemart.wand(cx, cy, px),
    }
}

fn armSays(a: heromod.Armament, o: heromod.Armament) []const u8 {
    if (heromod.armTwoHanded(a)) return "The bow takes both hands, so nothing is on his other arm and nothing can be blocked.";
    if (o == .shield or a == .shield) return "He can guard, and a guard is worth more than any number on this page.";
    if (o == .wand or a == .wand) return "He casts with a hand that could have blocked, and pays in Focus instead of stamina.";
    return "Two hands, and neither of them is going to stop anything.";
}

fn armCandSays(a: heromod.Armament) []const u8 {
    return switch (a) {
        .sword => "A blade. It is the only thing he carries that swings.",
        .bow => "Both hands go to the bow, and whatever was in the other one goes with them.",
        .bell => "Ring it and what the scroll names comes. Nothing else: a bell has no attack in it.",
        .shield => "Boards on the arm. He can guard, which is worth more than any number on this page.",
        .wand => "The wand takes a hand that could have blocked - and L1 casts instead.",
    };
}

fn gearSays(k: item.Kind) [:0]const u8 {
    var tmp: [item.EFFECT_BUF]u8 = undefined;
    return fmt("{s}", .{item.effect(k, &tmp)});
}

fn candSays(c: Cand, _: View) []const u8 {
    return switch (c.act) {
        .arm, .off, .armAlt, .offAlt => |h| if (h.kind) |k| gearSays(k) else armCandSays(h.a),
        .wear => |wr| if (wr.kind) |k| gearSays(k) else "Take it off. Whatever it was giving you goes with it.",
        .ammo => |a| switch (a) {
            .plain => "A plain shaft. Ten of them, and nothing in these ruins resists the hole one leaves.",
            .fire => "Fire rides on top of the shaft's own damage. Five of them, so pick the target.",
        },
        .quick => |q| if (q.kind == null)
            "Leave the socket empty."
        else
            "On the belt, which is the only reach he has in a fight.",
        else => "",
    };
}

fn drawPicker(self: *const Book, col: Box, s: SlotId, v: View) void {
    var buf: [CAND_MAX]Cand = undefined;
    const cs = candidates(s, v, &buf);
    const box = pickBox(col, cs.len);
    const step = pickStep(box, cs.len);
    const inner = panel(box, fmt("{s}  >", .{slotName(s)}));
    for (cs, 0..) |c, i| {
        const y = inner.y + @as(i32, @intCast(i)) * step;
        const on = self.pick == i;
        if (on) uiart.rowHilite(inner.x - 8, y - 6, inner.w + 16, step - 2);
        const size = pickSize(step);
        hud.text(c.name, inner.x + 10, y, size, if (on) uiart.HOT else uiart.TEXT_DIM);
        if (equipped(c, v)) {
            const tag = "EQUIPPED";
            hud.text(tag, inner.right() - hud.textW(tag, hud.TINY) - 46, y + 3, hud.TINY, mathx.withAlpha(uiart.GILT, 200));
        }
        if (c.tally) |n| {
            const str = fmt("{d}", .{n});
            hud.text(str, inner.right() - hud.textW(str, size), y, size, if (n > 0) uiart.TEXT_VALUE else uiart.BAD);
        }
    }
}


fn drawInventory(self: *const Book, body: Box, v: View) void {
    const cols = bagCols(body);
    const n = v.bag.distinct();
    _ = panel(cols[0], fmt("CARRIED    {d} kinds, {d} in all", .{ n, v.bag.total() }));
    const g = bagGrid(body);
    for (0..BAG_ROWS * BAG_COLS) |cell| {
        const at = cell + self.scroll * BAG_COLS;
        const kind = v.bag.nth(at);
        drawBagCell(self, g.at(cell), kind, if (kind) |k| v.bag.count(k) else 0, self.cur[idx(.inventory)] == at and kind != null);
    }
    const rows = (@max(n, 1) + BAG_COLS - 1) / BAG_COLS;
    uiart.rail(
        g.x + g.stepX * @as(i32, BAG_COLS) - CELL_GAP + 4,
        g.y,
        g.stepY * @as(i32, BAG_ROWS) - CELL_GAP,
        @as(f32, BAG_ROWS) / @as(f32, @floatFromInt(@max(rows, BAG_ROWS))),
        if (rows > BAG_ROWS) @as(f32, @floatFromInt(self.scroll)) / @as(f32, @floatFromInt(rows - BAG_ROWS)) else 0,
    );
    drawItemDetail(cols[1], v.bag.nth(self.cur[idx(.inventory)]), v);
}

fn drawBagCell(self: *const Book, r: rl.Rectangle, kind: ?item.Kind, count: u16, sel: bool) void {
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
        _ = prose(
            "Chests hold most of what there is, and the dead drop the rest.",
            inner.x,
            inner.y + 8 + hud.lineH(hud.BODY),
            inner.w,
            hud.HINT,
            uiart.TEXT_HINT,
        );
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
    hud.text(fmt("Held: {d}", .{v.bag.count(k)}), tx, y, hud.SMALL, uiart.TEXT_DIM);

    y = prose(item.describe(k), inner.x, inner.y + plateH + 16, inner.w, hud.SMALL, uiart.TEXT_VALUE) + 10;
    uiart.divider(inner.x + @divTrunc(inner.w, 2), y, @divTrunc(inner.w, 2) - 10, 120);
    y += 12;
    if (item.wearable(k)) {
        hud.text(gearSays(k), inner.x, y, hud.SMALL, uiart.GOOD);
        const hy = y + hud.lineH(hud.SMALL) + 6;
        hud.text("Put it on from the Equipment page.", inner.x, hy, hud.HINT, uiart.TEXT_HINT);
        return;
    }
    switch (item.use(k)) {
        .none => hud.text("It does nothing you can do here.", inner.x, y, hud.HINT, uiart.TEXT_HINT),
        .regen => |r| hud.text(fmt("Restores {d:.0} HP over {d:.0} seconds.", .{ v.sheet.hp() * r.frac, r.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .lob => |l| hud.text(fmt("Thrown at the reticle; bursts for {d:.0} + {d:.0} {s}.", .{ l.dmg, l.fire + l.lightning, if (l.lightning > 0) @as([]const u8, "lightning") else "fire" }), inner.x, y, hud.SMALL, uiart.GOOD),
        .ward => |w| hud.text(fmt("Chaos slides off you (+{d:.0}) for {d:.0} seconds.", .{ w.chaos, w.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .wind => |w| hud.text(fmt("Half your wind back at once ({d:.0} stamina), and the lockout with it.", .{ v.sheet.stamina() * w.share }), inner.x, y, hud.SMALL, uiart.GOOD),
        .grease => |gr| hud.text(fmt("The sword hangs {d:.0}% of its blow as fire for {d:.0} seconds.", .{ gr.frac * 100, gr.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .souls => |so| hud.text(fmt("Crushed for {d} souls, on the spot.", .{so.n}), inner.x, y, hud.SMALL, uiart.GOOD),
        .brew => |b| hud.text(fmt("Your wind returns {d:.1}x as fast for {d:.0} seconds.", .{ b.mult, b.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .purge => hud.text("Takes the poison back out of you, filling or already running.", inner.x, y, hud.SMALL, uiart.GOOD),
        .steady => |s| hud.text(fmt("Your footing returns {d:.1}x as fast for {d:.0} seconds.", .{ s.mult, s.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
    }
    if (item.usable(k)) {
        const hy = y + hud.lineH(hud.SMALL) + 6;
        if (v.inCombat) {
            hud.text("Not with something on you - load it on the quick bar.", inner.x, hy, hud.HINT, uiart.BAD);
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


fn drawTree(self: *const Book, body: Box, v: View) void {
    ptree.drawPage(v.tree, self.wheel, body.x, body.y, body.w, body.h, false, v.souls);
}

fn drawStats(self: *const Book, body: Box, v: View, portrait: ?Portrait) void {
    const cols = statsCols(body);
    drawAttributes(self, cols[0], v);
    drawBody(cols[1], v);
    drawPortrait(self, cols[2], portrait, fmt("Level {d}    {d} souls    Left / Right turns him", .{ v.tree.level(), v.souls }));
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
        hud.text(val, inner.right() - hud.textW(val, hud.BODY), y, hud.BODY, col2);
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
    const says = if (v.sheet.barFor(a)) |t|
        fmt("{s}  Yours: {d:.0}.", .{ stats.governs(a), t })
    else if (!stats.inert(a))
        fmt("{s}  Yours: {d:.2}x damage.", .{ stats.governs(a), v.sheet.scale(a) })
    else
        stats.governs(a);
    _ = prose(says, inner.x, y + 12, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn drawBody(col: Box, v: View) void {
    const inner = panel(col, "BODY");
    const pools = [_]struct { [:0]const u8, f32 }{
        .{ "HP", heromod.hpMaxOf(v.sheet.*, v.worn, v.tree.bonus()) },
        .{ "FP", heromod.fpMaxOf(v.sheet.*, v.worn, v.tree.bonus()) },
        .{ "Stamina", v.sheet.stamina() },
        .{ "Poise", heromod.POISE_MAX },
        .{ "Stance", heromod.STANCE_MAX },
    };
    const costs = [_]struct { [:0]const u8, f32 }{
        .{ "Roll", combat.STAM_ROLL },
        .{ "Light swing", combat.STAM_LIGHT },
        .{ "Heavy swing", combat.STAM_HEAVY },
        .{ "Quick shot", combat.STAM_SHOT },
        .{ "Aimed shot", combat.STAM_AIMED },
        .{ "Sprint, a second", combat.STAM_SPRINT },
    };
    var granted = false;
    for (0..combat.NELEM) |i| {
        if (@abs(v.res.at(@enumFromInt(i))) > 0.05) granted = true;
    }
    const says = if (granted)
        fmt("Capped at {d:.0}%. What is over the cap is stacked, not spent.", .{combat.RES_CAP})
    else
        "Nothing he owns grants any, so all four sit at nothing.";

    // THE THREE BLOCKS ARE FITTED TO THE COLUMN. Fifteen rows at a fixed pitch ran off the bottom of it,
    // which is a readout the player cannot read — so the pitch gives way before the content does.
    const sect = hud.lineH(hud.TINY) + 6 + 22;
    const nRows = pools.len + costs.len + combat.NELEM;
    const fixed = sect * 2 + proseH(says, inner.w, hud.HINT) + 10;
    const step = rowStep(inner.h - fixed, nRows);

    var y = inner.y;
    const rows = struct {
        fn draw(list: anytype, x: i32, right: i32, at: i32, pitch: i32) i32 {
            var yy = at;
            for (list) |r| {
                rowLabel(r[0], x, yy, uiart.TEXT_DIM);
                rowValue(fmt("{d:.0}", .{r[1]}), right, yy, uiart.TEXT_VALUE);
                yy += pitch;
            }
            return yy;
        }
    }.draw;
    y = rows(pools, inner.x, inner.right(), y, step);
    y = section(inner, y, "STAMINA SPENT");
    y = rows(costs, inner.x, inner.right(), y, step);
    y = section(inner, y, "RESISTANCE");
    for (0..combat.NELEM) |i| {
        const e: combat.Elem = @enumFromInt(i);
        const raw = v.res.raw(e);
        const eff = v.res.at(e);
        rowLabel(combat.elemName(e), inner.x, y, uiart.TEXT_DIM);
        const s = if (@abs(raw - eff) < 0.05) fmt("{d:.0}%", .{raw}) else fmt("{d:.0}% ({d:.0}%)", .{ raw, eff });
        rowValue(s, inner.right(), y, if (eff > 0.05) uiart.GOOD else if (eff < -0.05) uiart.BAD else uiart.TEXT_DIM);
        y += step;
    }
    _ = prose(says, inner.x, y + 6, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn section(inner: Box, y: i32, title: [:0]const u8) i32 {
    uiart.divider(inner.x + @divTrunc(inner.w, 2), y + 6, @divTrunc(inner.w, 2) - 10, 120);
    hud.text(title, inner.x, y + 14, hud.TINY, mathx.withAlpha(uiart.GILT, 200));
    return y + 14 + hud.lineH(hud.TINY) + 6;
}

// The hero himself, rendered off-screen and blitted into the panel — the trick the editor's object viewer
// plays, for the same reason: it is the actual model in the actual pose, so it cannot go stale.

const PORT_W: i32 = 460;
const PORT_H: i32 = 760;
var portRT: ?rl.RenderTexture2D = null;

/// The doll's own framing — head-to-boots at arm's length, where `hud.PORTRAIT_*` is a face.
const DOLL_EYE: f32 = 0.94;
const DOLL_DIST: f32 = 3.5;
const DOLL_PITCH: f32 = 0.14;
const DOLL_FOV: f32 = 40.0;
const DOLL_CLEAR = rgba(14, 12, 10, 255);

fn drawDoll(ctx: *const anyopaque) void {
    const h: *const heromod.Hero = @ptrCast(@alignCast(ctx));
    h.draw();
}

pub fn unload() void {
    if (portRT) |t| rl.unloadRenderTexture(t);
    portRT = null;
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

    // THROUGH THE ONE PATH (`hud.renderIntoTarget`), which is the law AGENTS.md already states — the book's
    // doll, the conversation's speaker and the spirit panel are one way of photographing a body. Only the
    // TARGET is the book's, because a full-length doll is not a head shot's aspect.
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
    club.worn.put(.hand_sword, .greatclub);
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

    v.worn.put(.hand_sword, .greatclub);
    v.worn.put(.hand_shield, .tower_shield);
    v.worn.put(.chest, .quilted_gambeson);
    const geared = derive(inForce(v), v);
    try std.testing.expect(worth(geared, .heavy) > worth(bareRows, .heavy));
    try std.testing.expect(worth(geared, .poise) > worth(bareRows, .poise));
    try std.testing.expect(worth(geared, .stam_heavy) > worth(bareRows, .stam_heavy));
    try std.testing.expect(worth(geared, .guard) > worth(bareRows, .guard));
    try std.testing.expect(worth(geared, .arc) > worth(bareRows, .arc));
    // …and the armour row, which off a bare loadout could only ever print 0.
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
    try std.testing.expect(worth(bow, .fire) == 0 and worth(fire, .fire) > 0);
    try std.testing.expectApproxEqAbs(worth(bow, .heavy) * heromod.FIRE_ARROW_FRAC, worth(fire, .fire), 1e-3);
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
    // …and what he got for it. Zero behind a shield, because a spell he cannot cast is not worth a number.
    try std.testing.expect(worth(board, .spell) == 0 and worth(rod, .spell) > 0);
    try std.testing.expect(worth(board, .spell_fp) == 0 and worth(rod, .spell_fp) > 0);
    const bowRod = derive(.{ .arm = .bow, .off = .wand, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    try std.testing.expect(worth(bowRod, .spell) == 0 and worth(bowRod, .guard) == 0);
    for ([_]Der{ .light, .heavy, .poise, .stance, .stam_light, .stam_heavy }) |k| {
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
    try std.testing.expectEqualStrings(combat.spellName(.roots), slotFilled(.sorcery, v));
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
    try std.testing.expectApproxEqAbs(
        combat.spellDamage(.bolt) * perk.spellDmg * sheet.scale(.intelligence),
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
    var b = Book{ .page = .inventory, .cur = .{ 0, 2, 0, 0 } };
    b.clamp(testView(&bag, &sheet, &res, &flasks, &quiver, .sword));
    try std.testing.expectEqual(@as(usize, 2), b.cur[idx(.inventory)]);
    _ = bag.take(.iron_key, 1);
    b.clamp(testView(&bag, &sheet, &res, &flasks, &quiver, .sword));
    try std.testing.expectEqual(@as(usize, 1), b.cur[idx(.inventory)]);
    bag.clear();
    b.clamp(testView(&bag, &sheet, &res, &flasks, &quiver, .sword));
    try std.testing.expectEqual(@as(usize, 0), b.cur[idx(.inventory)]);
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
    b.cur[idx(.inventory)] = 0;
    try std.testing.expectEqual(item.Kind.mushroom_jerky, bag.nth(0).?);
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
    // `CAND_MAX` sized the buffer at `item.NK` and the quick picker writes `item.NK + 1` rows in the worst
    // case — the "(empty)" one is a row like the others. It cannot be reached with today's six quickable
    // kinds, which is exactly why it has to be arithmetic and not a count of what happens to be in the table.
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
