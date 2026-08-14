const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const itemart = @import("itemart.zig");
const item = @import("item.zig");
const stats = @import("stats.zig");
const ptree = @import("passivetree.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const gfx = @import("gfx.zig");
const sfx = @import("audio.zig");

// Every rectangle in here comes off the `Box`/`Grid` helpers below: the cursor computes where it is flying to
// independently of the draw pass, so two copies of the grid maths is a cursor half a slot off its own slot.

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

/// WHAT THE BOOK ASKS THE GAME TO DO. It changes nothing itself: the hero's arm, quiver and flasks are
/// the game loop's to move, exactly as the old inventory `use` was.
pub const Action = union(enum) {
    none,
    arm: heromod.Arm,
    off: heromod.Off,
    ammo: combat.ArrowKind,
    /// Put `kind` (or nothing) in quick socket `slot`.
    quick: struct { slot: usize, kind: ?item.Kind },
    use: item.Kind,
};

/// EVERYTHING THE BOOK READS, borrowed for the frame — all of it the live state the game plays with.
pub const View = struct {
    bag: *const item.Bag,
    sheet: *const stats.Sheet,
    res: *const combat.Resists,
    flasks: *const combat.Flasks,
    /// THE QUICK BAR, which the equipment page is where you load. Read AND edited here, unlike the rod.
    quick: *const combat.Quick,
    quiver: *const combat.Quiver,
    /// THE PASSIVE TREE. Read on every page (it owns the LEVEL now), spent on only at a bonfire.
    tree: *const ptree.Tree,
    /// IS A FIGHT ON (`game.inCombat`). The page reads it for one rule: in combat a consumable may only be
    /// spent off the bar, so the inventory's own Use is refused and says so.
    inCombat: bool = false,
    arm: heromod.Arm,
    off: heromod.Off,
    /// WHICH SORCERY THE ROD IS SET TO. Read, never chosen here — the rod is changed on the D-pad in play,
    /// and the page has to name and price the one that is actually loaded.
    spell: combat.Spell,
    /// The live FP pool, so the sorcery slot can say how many casts are actually in it.
    fp: f32,
    souls: u32,
};

/// The live hero and the scene to draw him in, for the stats page's turntable.
pub const Portrait = struct { hero: *const heromod.Hero, scene: *gfx.Scene };

// The equipment page's reason to exist: `derive` is a pure function of what is equipped, so the
// candidate under the cursor is priced by calling it again with one field changed. Every number in it is
// read from the module that owns it — not one is retyped here.

const Loadout = struct {
    arm: heromod.Arm,
    off: heromod.Off,
    ammo: combat.ArrowKind,
    /// What the quick slot is turned to, or nothing.
    quick: ?item.Kind,
    spell: combat.Spell,
};

const Unit = enum { flat, pct, count };

/// THE ROWS, NAMED. `derive` fills an array and the panel walks it, so the two are only in step as long
/// as nobody counts on their fingers: every row is written against this enum, and anything that wants one
/// row (the tests, and the delta colours) asks for it by name.
const Der = enum {
    light,
    heavy,
    fire,
    poise,
    stance,
    stam_light,
    stam_heavy,
    guard,
    spell,
    spell_fp,
    quick,
    ammo,
};
const ND = @typeInfo(Der).@"enum".fields.len;

fn worth(d: [ND]f32, k: Der) f32 {
    return d[@intFromEnum(k)];
}

/// `cost` marks the rows a SMALLER number is better on, which is what the delta colours read.
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
    rows[@intFromEnum(Der.spell)] = .{ .name = "Sorcery damage", .unit = .flat };
    rows[@intFromEnum(Der.spell_fp)] = .{ .name = "Focus, per cast", .unit = .flat, .cost = true };
    rows[@intFromEnum(Der.quick)] = .{ .name = "Quick item restores", .unit = .flat };
    rows[@intFromEnum(Der.ammo)] = .{ .name = "Ammunition", .unit = .count };
    break :blk rows;
};

fn derive(l: Loadout, v: View) [ND]f32 {
    const bow = l.arm == .bow;
    // …AND WHETHER THAT HAND HAS AN ATTACK AT ALL (`hero.armSwings`). `bow` alone was the whole question while
    // there were two armaments; the BELL has neither a light nor a heavy, so every row below came off the
    // SWORD and the page priced a swing he cannot take. Zero is the honest figure, and the arm's own tip
    // already says it in words.
    const attacks = heromod.armSwings(l.arm) or bow;
    const light = if (bow) heromod.BOW_QUICK_HIT else heromod.ATK_LIGHT_HIT;
    const heavy = if (bow) heromod.arrowBlow(l.ammo, true) else heromod.ATK_HEAVY_HIT;
    var d: [ND]f32 = undefined;
    d[@intFromEnum(Der.light)] = if (attacks) light.dmg else 0;
    d[@intFromEnum(Der.heavy)] = if (attacks) heavy.dmg else 0;
    d[@intFromEnum(Der.fire)] = if (attacks) heavy.elem.total() else 0;
    d[@intFromEnum(Der.poise)] = if (attacks) heavy.poise else 0;
    d[@intFromEnum(Der.stance)] = if (attacks) heavy.stance else 0;
    d[@intFromEnum(Der.stam_light)] = if (!attacks) 0 else if (bow) combat.STAM_SHOT else combat.STAM_LIGHT;
    d[@intFromEnum(Der.stam_heavy)] = if (!attacks) 0 else if (bow) combat.STAM_AIMED else combat.STAM_HEAVY;
    // THE BOW COSTS HIM THE SHIELD, and so does the WAND — this is the row where that is a number rather
    // than lore, and it is the same number for both because it is the same left hand being spent.
    const guards = !bow and l.off == .shield;
    d[@intFromEnum(Der.guard)] = if (guards) combat.GUARD_NEGATE * 100.0 else 0;
    // …and what he bought with it. Zero on both rows unless a wand is actually in that hand, because a spell
    // he cannot cast is not worth a number — and it is the SORCERY THAT IS LOADED that is priced, through
    // `combat`'s own two answers: the rod carries two now, and they neither cost nor deal the same.
    const casts = !bow and l.off == .wand;
    d[@intFromEnum(Der.spell)] = if (casts) combat.spellDamage(l.spell) else 0;
    d[@intFromEnum(Der.spell_fp)] = if (casts) combat.spellFp(l.spell) else 0;
    d[@intFromEnum(Der.quick)] = quickWorth(l.quick, v);
    d[@intFromEnum(Der.ammo)] = @floatFromInt(v.quiver.count(l.ammo));
    return d;
}


/// A Diablo paper doll. Six of these hold nothing yet — there is no armour or jewellery in the game — and
/// each says so in `locked`.
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

/// Which bar entry a socket is, or null for a gear slot.
fn quickIndex(s: SlotId) ?usize {
    const i = @intFromEnum(s);
    return if (i >= Q0) i - Q0 else null;
}

/// The socket grid: five across, six down (four of body, two of quick bar).
const SLOT_COLS: i32 = 5;
const SLOT_ROWS: i32 = 6;
/// …clamped so a small window keeps them usable and a huge one does not make dinner plates of them.
const SLOT_MIN: i32 = 30;
const SLOT_MAX: i32 = 112;
/// Where each socket sits, as (col, row). Rows 4 and 5 are the quick block and get `SlotFit.brk` above them.
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
    for (0..combat.QUICK_SLOTS) |i| {
        c[Q0 + i] = .{ .col = @intCast(i % 5), .row = 4 + @as(i32, @intCast(i / 5)) };
    }
    break :blk c;
};

fn slotName(s: SlotId) [:0]const u8 {
    return switch (s) {
        // SHORT: the label is fixed-size text (`hud`'s type scale) over a socket that is a share of the
        // window, so a long one runs into its neighbour the moment the card is anything but wide.
        .helm => "Head",
        .amulet => "Neck",
        .left => "L Hand",
        .chest => "Body",
        .right => "R Hand",
        .ring1 => "Ring",
        .belt => "Belt",
        .ring2 => "Ring",
        .arrows => "Ammo",
        .boots => "Feet",
        .sorcery => "Spell",
        // The quick sockets are NUMBERED, not named: what is in one changes, and the number is what the
        // player learns the cycle order by.
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

/// WHY A SLOT CANNOT BE CHANGED, or null when it can. Said in words on the panel, because a slot that
/// only refuses the button is a slot the player decides is broken.
fn locked(s: SlotId, v: View) ?[:0]const u8 {
    return switch (s) {
        .helm, .chest, .belt, .boots => "There is no armour in this world yet. The socket is here for the day there is.",
        .amulet, .ring1, .ring2 => "There is no jewellery in this world yet. The socket is here for the day there is.",
        .left => if (v.arm == .bow) "Both hands are on the bow. The left one comes back when the sword does." else null,
        // Which of the two reasons it is: "locked" with no reason is a slot the player calls broken.
        .sorcery => if (v.arm == .bow)
            "Both hands are on the bow. Nothing is free to hold a wand."
        else if (v.off != .wand)
            "No wand in his hand to cast a sorcery with."
        else
            // Filled and still unchangeable HERE — the rod is turned on the D-pad and the book does not own it.
            "The rod is turned to its other sorcery with D-pad Up.",
        else => null,
    };
}

/// What a quick socket holds, or null (also null for a gear slot).
fn quickAt(s: SlotId, v: View) ?item.Kind {
    return if (quickIndex(s)) |i| v.quick.slots[i] else null;
}

/// Is there anything in it? The socket lights off this, and an empty one stays cold.
fn slotHas(s: SlotId, v: View) bool {
    return switch (s) {
        .right => true,
        .left => v.arm != .bow,
        .sorcery => v.arm != .bow and v.off == .wand,
        .arrows => v.quiver.count(v.quiver.sel) > 0,
        .helm, .chest, .belt, .boots, .amulet, .ring1, .ring2 => false,
        else => quickAt(s, v) != null,
    };
}

// WHAT EACH THING IS CALLED, once. The slot caption and the picker row are the same armament named twice,
// and two copies of a name are two names the day one of them is edited.
const EMPTY = "-";

fn armName(a: heromod.Arm) [:0]const u8 {
    return switch (a) {
        .sword => "Straight Sword",
        .bow => "Short Bow",
        .bell => "Summoning Bell",
    };
}

fn offName(o: heromod.Off) [:0]const u8 {
    return switch (o) {
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

fn slotFilled(s: SlotId, v: View) [:0]const u8 {
    return switch (s) {
        .right => armName(v.arm),
        .left => if (v.arm == .bow) EMPTY else offName(v.off),
        .sorcery => if (slotHas(.sorcery, v)) combat.spellName(v.spell) else EMPTY,
        .arrows => ammoName(v.quiver.sel),
        .helm, .chest, .belt, .boots, .amulet, .ring1, .ring2 => EMPTY,
        else => if (quickAt(s, v)) |k| item.displayName(k) else EMPTY,
    };
}

fn slotTally(s: SlotId, v: View) ?u8 {
    return switch (s) {
        .arrows => v.quiver.count(v.quiver.sel),
        .sorcery => if (slotHas(.sorcery, v)) castsLeft(v.fp, v.spell) else null,
        .helm, .chest, .belt, .boots, .amulet, .ring1, .ring2, .left, .right => null,
        else => if (quickAt(s, v)) |k| quickTally(k, v) else null,
    };
}

/// What one press of the quick slot gives back. Off the SHEET, so the row moves when the attribute does.
fn quickWorth(kind: ?item.Kind, v: View) f32 {
    const k = kind orelse return 0;
    if (combat.flaskOf(k)) |f| return switch (f) {
        .crimson => v.sheet.hp() * combat.FLASK_HP_FRAC,
        .cerulean => v.sheet.fp() * combat.FLASK_FP_FRAC,
    };
    return switch (item.use(k)) {
        .none => 0,
        .regen => |r| v.sheet.hp() * r.frac,
        .lob => |l| l.dmg + l.fire + l.lightning, // what one press throws, in the only number a throw has
        .ward, .wind, .grease, .souls, .brew => 0, // none of these restores a bar the row could price
    };
}

/// IS THIS ROW EVEN OFFERED. He may not put on the bar a thing he does not own — an empty row is a cycle step
/// that does nothing, and the bar drops one the moment the last is spent (`combat.Quick.dropEmpty`), so
/// offering it here would be offering something that leaves again before he closes the book. THE FLASKS ARE
/// ALWAYS OFFERED: their charges are not the bag's, and an empty one is still carried.
fn quickOffered(k: item.Kind, v: View) bool {
    if (!item.quickable(k)) return false;
    return combat.flaskOf(k) != null or v.bag.count(k) > 0;
}

fn quickTally(k: item.Kind, v: View) u8 {
    return combat.quickCount(k, v.flasks, v.bag);
}

fn castsLeft(fp: f32, s: combat.Spell) u8 {
    const cost = combat.spellFp(s);
    if (cost <= 0) return 0;
    return @intFromFloat(@max(0, @floor(fp / cost)));
}

/// THE CANDIDATES a slot can be filled from — the picker's rows. Names and counts only; what a choice is
/// WORTH is `derive`'s job.
const Cand = struct { name: [:0]const u8, tally: ?u8 = null, act: Action };

/// The longest candidate list any slot can offer, off the enums themselves — the scratch every caller
/// hands `candidates` is sized from this, so a third arrow cannot write past the end of one.
const CAND_MAX = blk: {
    // The quick bar offers every kind that may go on it, so it is the long list — PLUS the "(empty)" row it
    // opens with, which is a row like any other and was not counted: at `item.NK` exactly, the day every kind
    // is quickable the last one writes past the end of the caller's scratch.
    var n: usize = item.NK + 1;
    for ([_]type{ heromod.Arm, heromod.Off, combat.ArrowKind }) |T| {
        n = @max(n, @typeInfo(T).@"enum".fields.len);
    }
    break :blk n;
};

fn candidates(s: SlotId, v: View, out: *[CAND_MAX]Cand) []const Cand {
    // A LOCKED SLOT OFFERS NOTHING, asked ONCE here rather than re-tested inside each branch. The left hand
    // is the reason it has to be structural: it grew a real picker the day the wand landed, and with a bow
    // out that picker would have offered two rows for a hand the panel had already said was not free.
    if (locked(s, v) != null) return out[0..0];
    switch (s) {
        // Each list is walked off the ENUM it offers, so a third arrow or a third armament is a row here
        // the day it exists rather than a row somebody remembered to add.
        .right => {
            inline for (@typeInfo(heromod.Arm).@"enum".fields, 0..) |f, i| {
                const a: heromod.Arm = @enumFromInt(f.value);
                out[i] = .{ .name = armName(a), .act = .{ .arm = a } };
            }
            return out[0..@typeInfo(heromod.Arm).@"enum".fields.len];
        },
        .left => {
            inline for (@typeInfo(heromod.Off).@"enum".fields, 0..) |f, i| {
                const o: heromod.Off = @enumFromInt(f.value);
                out[i] = .{ .name = offName(o), .act = .{ .off = o } };
            }
            return out[0..@typeInfo(heromod.Off).@"enum".fields.len];
        },
        .arrows => {
            inline for (@typeInfo(combat.ArrowKind).@"enum".fields, 0..) |f, i| {
                const k: combat.ArrowKind = @enumFromInt(f.value);
                out[i] = .{ .name = ammoName(k), .tally = v.quiver.count(k), .act = .{ .ammo = k } };
            }
            return out[0..@typeInfo(combat.ArrowKind).@"enum".fields.len];
        },
        // A quick socket: what he actually carries, plus an empty row to clear it with.
        else => {
            const qi = quickIndex(s) orelse return out[0..0];
            // An EMPTY row first, or a socket you filled by mistake can never be cleared.
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

/// The loadout that WOULD be in force if this candidate were taken — what the delta column prices.
fn withCand(base: Loadout, c: Cand) Loadout {
    var l = base;
    switch (c.act) {
        .arm => |a| l.arm = a,
        .off => |o| l.off = o,
        .ammo => |a| l.ammo = a,
        .quick => |q| l.quick = q.kind,
        // EXHAUSTIVE, not `else` (`hero.steerQueuedRoll`'s rule): a seventh action has to be asked whether
        // it changes the loadout, or its rows price themselves against the one already in force.
        .none, .use => {},
    }
    return l;
}

fn equipped(c: Cand, v: View) bool {
    return switch (c.act) {
        .arm => |a| a == v.arm,
        .off => |o| o == v.off,
        .ammo => |a| a == v.quiver.sel,
        .quick => |q| v.quick.slots[q.slot] == q.kind,
        .none, .use => false,
    };
}

/// Where a picker opens: on what is ALREADY equipped, never on row 0 — landing the cursor somewhere other
/// than the current choice is how a menu tricks you into swapping something you meant to look at. The rows
/// are built in enum order, so the equipped thing's ORDINAL is its row.
fn pickIndexOf(s: SlotId, v: View) usize {
    return switch (s) {
        .right => @intFromEnum(v.arm),
        .left => @intFromEnum(v.off),
        .arrows => @intFromEnum(v.quiver.sel),
        // The quick list is FILTERED and carries an "(empty)" row, so a kind's ordinal is not its row.
        else => quickRowOf(quickAt(s, v), v),
    };
}

fn quickRowOf(want: ?item.Kind, v: View) usize {
    const k0 = want orelse return 0;
    var n: usize = 1;
    inline for (@typeInfo(item.Kind).@"enum".fields) |f| {
        const k: item.Kind = @enumFromInt(f.value);
        if (k == k0) return n;
        if (quickOffered(k, v)) n += 1;
    }
    return 0;
}


const MOVE_EASE: f32 = 17.0; // how hard the cursor is pulled toward the slot it just moved to
const PRESS_RATE: f32 = 9.0;
const POP_DUR: f32 = 0.30; // the seat thump a slot gives when something lands in it
const SPIN_RATE: f32 = 1.7; // radians a second, the portrait turntable under Left/Right

pub const Book = struct {
    page: Page = .equipment,
    /// The cursor per page, kept so coming back to one finds it where you left it.
    cur: [NPAGE]usize = blk: {
        var c = [_]usize{0} ** NPAGE;
        c[idx(.equipment)] = @intFromEnum(SlotId.right); // opening on a socket nothing can go in reads as broken
        break :blk c;
    },
    /// THE TREE PAGE'S OWN CURSOR AND ZOOM. Not in `cur`, which is one ordinal per page: a wheel is walked by
    /// GEOMETRY and looked at from a distance, and the bonfire's screen holds a second one of these so the two
    /// views of the tree do not shove each other's cursor about.
    wheel: ptree.Wheel = .{},
    /// Which slot's picker is open, and where its own cursor sits.
    picking: ?SlotId = null,
    pick: usize = 0,
    scroll: usize = 0, // the inventory grid's first visible ROW
    press: f32 = 0,
    pop: f32 = 0,
    /// The cursor's live rectangle, eased toward the one it is naming.
    at: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    settled: bool = false,
    spin: f32 = 0.55,

    pub fn opened(self: *Book) void {
        self.picking = null;
        self.settled = false; // the cursor SNAPS to where it opens rather than flying in from a corner
        self.press = 0;
        self.pop = 0;
    }

    fn moved(self: *Book) void {
        self.settled = true;
        sfx.play(.menu_move);
    }

    /// Per frame, on REAL time — the book runs at full speed under a slowed game.
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

    /// The bag shrinks under the cursor when the last of something is drunk, so the cursor is pulled back
    /// onto a real cell every frame rather than only when it moves.
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

    /// Esc / B. True if the book swallowed it (a picker closing); false to close the book itself.
    pub fn onBack(self: *Book) bool {
        if (self.picking == null) return false;
        self.picking = null;
        self.settled = false;
        sfx.play(.menu_back);
        return true;
    }

    /// `dx`/`dy` ARE A HEADING, not a pair of steps (`menu.stickPush`). The wheel is the only page that can use
    /// a bearing; every other page here has four directions and nothing between them, so it takes the SIGN and
    /// the stick hands those pages a cardinal anyway (`radial` is false off the tree).
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
        // The wheel is not an ordinal, so it moves itself and says whether it went anywhere.
        if (self.page == .tree) {
            if (self.wheel.move(dx, dy)) self.moved();
            return;
        }
        const i = idx(self.page);
        const next = switch (self.page) {
            .equipment => slotStep(self.cur[i], sx, sy),
            .inventory => grid(self.cur[i], @max(v.bag.distinct(), 1), BAG_COLS, sx, sy),
            // Up/Down walks the attributes; Left/Right is the turntable, so it must not move the cursor.
            .stats => if (sy == 0) self.cur[i] else @as(usize, @intCast(@mod(
                @as(i32, @intCast(self.cur[i])) + sy + @as(i32, stats.NA),
                @as(i32, stats.NA),
            ))),
            .tree => unreachable, // handled above: the wheel is not an ordinal
        };
        if (next == self.cur[i]) return;
        self.cur[i] = next;
        self.moved();
    }

    /// Left/Right HELD on the stats page turns him — the one continuous input in the book.
    pub fn spinBy(self: *Book, dir: i32, dt: f32) void {
        if (self.page != .stats or self.picking != null or dir == 0) return;
        self.spin += @as(f32, @floatFromInt(dir)) * SPIN_RATE * dt;
    }

    /// …and the RIGHT stick pushed up and down zooms the wheel, on the tree page and nowhere else.
    pub fn zoomBy(self: *Book, dv: f32, dt: f32) void {
        if (self.page != .tree or self.picking != null or dv == 0) return;
        self.wheel.zoomBy(dv, dt);
    }

    /// …and the RIGHT STICK slides the view, the bonfire screen's own pair of thumbs on the book's copy.
    pub fn panBy(self: *Book, v: rl.Vector2, dt: f32) void {
        if (self.page != .tree or self.picking != null) return;
        self.wheel.panBy(v, dt);
    }

    /// IS THE CROSS SPENT ON THE ZOOM this frame — true on the wheel, where the walk is the left stick's.
    /// A picker open over it is a row list again and takes the cross back.
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
            sfx.play(.item_get); // a swap LANDS, and the seat thump has a sound on it
            return act;
        }
        switch (self.page) {
            .equipment => {
                const s: SlotId = @enumFromInt(self.cur[idx(.equipment)]);
                if (locked(s, v) != null) {
                    sfx.play(.menu_back); // refused, and the panel already says why
                    return .none;
                }
                self.picking = s;
                self.pick = pickIndexOf(s, v);
                self.settled = false;
                sfx.play(.menu_pick);
            },
            // IN COMBAT NOTHING IS SPENT FROM HERE. The bag is a rucksack, not a belt: with something coming
            // at you the only reach you have is the quick bar, which is why what is on it is a decision made
            // before the fight. Out of combat this page is the convenient way and the bar can stay empty.
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
            // THE SHEET IS READ-ONLY NOW AND ALWAYS WILL BE: every attribute past the start came off a node
            // on the TREE page, so there is nothing here a press could move.
            .stats => sfx.play(.menu_back),
            // NOTHING IS SPENT FROM THE BOOK. The wheel is readable here and committed at the fire, which
            // is the one screen that can charge him souls.
            .tree => sfx.play(.menu_back),
        }
        return .none;
    }

    /// Stage a page for the shot harness, `ogre.debugStagger`'s pattern: a photograph of the picker open
    /// on the second candidate cannot be got by pretending to press buttons at 1/60 s a frame.
    pub fn debugShow(self: *Book, p: Page, cursor: usize, pickSlot: ?usize, row: usize) void {
        self.page = p;
        self.cur[idx(p)] = cursor;
        if (p == .tree) self.wheel.cursor = cursor; // the wheel is not in `cur` — see the field
        // CLAMPED, for `rest.debugShow`'s reason: an out-of-range `@enumFromInt` is illegal behaviour, and
        // `clamp` never touches `picking` — it owns `cur`, which is why only this one needs it here.
        self.picking = if (pickSlot) |s| @enumFromInt(@min(s, NSLOT - 1)) else null;
        self.pick = row;
        self.settled = false;
        self.press = 0;
        self.pop = 0;
    }

    /// WHERE THE CURSOR IS FLYING TO, off the same layout helpers the draw pass uses.
    fn cursorRect(self: *const Book, v: View) rl.Rectangle {
        const body = bodyBox(cardBox());
        switch (self.page) {
            .equipment => {
                if (self.picking) |s| {
                    var buf: [CAND_MAX]Cand = undefined;
                    const cs = candidates(s, v, &buf);
                    return pickRow(pickBox(equipCols(body)[1], cs.len), self.pick);
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

/// Move within a grid whose last row may be RAGGED: a column that does not exist on the row you land on
/// takes you to the last cell of it rather than off the end.
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

// The chrome's own two, not a third copy of each: `uiart` is where hud/menu/book/ui share their dressing.
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
    /// Split into a `w`-wide column and the rest, a gutter apart.
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

/// A run of cells, and where the `i`th one sits. Both the draw pass and the cursor ask this.
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

/// `panel`'s geometry without its paint — the one copy of "where a panel's content starts".
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

/// THE SOCKETS ARE FITTED TO THE PANEL, not a fixed pixel size — the card is a fraction of the window
/// (`cardBox`), so a fixed socket is a different share of the page on every monitor. The gap and the break
/// between the body and the quick rows are fractions of the socket, so the whole block scales as one thing.
///
/// TEXT DOES NOT SCALE — sizes come from `hud`'s type scale, which is why the label height is subtracted.
const SlotFit = struct { px: i32, gap: i32, brk: i32, x: i32, y: i32 };

fn slotFit(body: Box) SlotFit {
    const inner = panelInner(equipCols(body)[0], false);
    // gap = px/7 and break = px/3, so both axes solve for px directly.
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

/// MOVE BY GEOMETRY, not by ordinal: a ragged paper doll over a five-wide block has no grid arithmetic, and
/// an ordinal walk steps between slots that are nowhere near each other on screen.
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
        const s = along + cross * 6; // the cross-axis is what disqualifies a candidate
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

fn pickBox(col: Box, n: usize) Box {
    const want = pickRowH() * @as(i32, @intCast(n)) + titleH() + 24;
    return .{ .x = col.x, .y = col.y, .w = col.w, .h = @min(@divTrunc(col.h, 2), want) };
}

fn pickRow(box: Box, i: usize) rl.Rectangle {
    const inner = panelInner(box, true);
    return rect(inner.x - 8, inner.y + @as(i32, @intCast(i)) * pickRowH() - 6, inner.w + 16, pickRowH() - 2);
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

/// A formatted string good until fifteen more have been made — every caller draws it on the next line.
fn fmt(comptime f: []const u8, args: anytype) [:0]const u8 {
    scratchAt = (scratchAt + 1) % scratch.len;
    return std.fmt.bufPrintZ(&scratch[scratchAt], f, args) catch "?";
}

/// A sunk panel with a heading. NOT the menu card's plate: a card sits on the world, a panel is a recess
/// cut into a card.
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
    return mathx.clampI(@divTrunc(space, @as(i32, @intCast(n))), hud.SMALL + 1, natural);
}

fn rowLabel(s: [:0]const u8, x: i32, y: i32, col: rl.Color) void {
    hud.text(s, x, y, hud.SMALL, col);
}

fn rowValue(s: [:0]const u8, right: i32, y: i32, col: rl.Color) void {
    hud.text(s, right - hud.textW(s, hud.SMALL), y, hud.SMALL, col);
}

fn unitStr(u: Unit, x: f32) [:0]const u8 {
    return switch (u) {
        .flat => if (x <= 0.005) "-" else fmt("{d:.0}", .{x}),
        .pct => if (x <= 0.005) "-" else fmt("{d:.0}%", .{x}),
        .count => fmt("{d:.0}", .{x}),
    };
}

/// ONE PARAGRAPH'S SCRATCH, sized once. As a pair of literals declared inside `prose` AND inside `proseH`,
/// the measure and the draw were the same paragraph only because two pairs of numbers happened to match.
const PROSE_LINES = 8;
const PROSE_BUF = 768;
var proseLines: [PROSE_LINES][:0]const u8 = undefined;
var proseBuf: [PROSE_BUF]u8 = undefined;

/// THE WRAP ITSELF, run ONCE. `hud.wrap` measures a candidate per word and the candidate grows through the
/// line, so it is O(words²) in glyph measurement — and every panel here anchored its floor with `proseH` and
/// then drew the identical string with `prose`, paying for it twice a frame.
fn proseWrap(s: []const u8, w: i32, size: i32) []const [:0]const u8 {
    return hud.wrap(s, size, w, &proseBuf, &proseLines);
}

/// Wrapped prose, returning the y it ended on — the panels' one paragraph idiom.
fn prose(s: []const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color) i32 {
    var yy = y;
    for (proseWrap(s, w, size)) |line| {
        hud.text(line, x, yy, size, col);
        yy += hud.lineH(size);
    }
    return yy;
}

/// How tall a paragraph will be BEFORE it is drawn, so a panel can anchor it to its own floor instead of
/// letting it run out over the crib line — which is what the picker's short column did.
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

    // THE CURSOR LAST, over everything: it is in front of the page, not part of it. THE WHEEL DRAWS ITS OWN
    // (`tree.draw`) — a node is a disc and its mark is built out of the disc, and the bonfire's screen needs
    // the same one without carrying the book's eased rectangle to get it.
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

    // THE CRIB IS BUTTONS, NOT KEYS (owner's call). One strip per state, drawn as the pad's own pictograms,
    // and the page-turn pair rides every one of them because it is the only way off a page.
    // ONE hint for the pair: two pills labelled "Page" side by side read as two different page turns.
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
        // THE CRIB DOES NOT OFFER WHAT THE PRESS WILL REFUSE (the `game.interact` law). Nothing is spent
        // here, so nothing on this strip says Allocate — the bonfire's own screen is where those live.
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
    // The souls he is carrying ride the header's right end, which is ER's own corner for them.
    const souls = fmt("{d}", .{v.souls});
    const rx = card.right() - PAD - hud.textW(souls, hud.BODY);
    hud.text(souls, rx, y + 8, hud.BODY, uiart.TEXT_VALUE);
    hud.text("SOULS", rx - hud.textW("SOULS", hud.TINY) - 10, y + 12, hud.TINY, uiart.TEXT_DIM);
    uiart.divider(card.x + @divTrunc(card.w, 2), card.y + headH(), @divTrunc(card.w, 2) - 30, 170);
}


/// EVERYTHING UP FRONT (owner's call, and ER's own shape): the sockets are a single row of small squares, the
/// list you choose from opens UNDER them, and the numbers hold the right-hand column whether a picker is open
/// or not. As one column, choosing something took the readout off the page at the moment you wanted it.
fn drawEquipment(self: *const Book, body: Box, v: View) void {
    const cols = equipCols(body);
    const inner = panel(cols[0], "");
    const cur = self.cur[idx(.equipment)];
    for (0..NSLOT) |i| {
        drawSlot(self, slotRect(body, i), @enumFromInt(i), v, cur == i and self.picking == null);
    }
    // What is IN the socket under the cursor, once — every socket carries its NAME, and a second caption
    // under each of twenty-one of them is a page of overlapping words.
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

/// The numbers keep the right column; an open picker takes the top of it and pushes them down.
fn derivedBox(body: Box, cands: usize) Box {
    const col = equipCols(body)[1];
    if (cands == 0) return col;
    const top = pickBox(col, cands);
    return .{ .x = col.x, .y = top.y + top.h + GUTTER, .w = col.w, .h = col.h - top.h - GUTTER };
}

/// One equipment cell: the socket, the picture, a tally, the slot's name above and what is in it below.
fn drawSlot(self: *const Book, r: rl.Rectangle, s: SlotId, v: View, sel: bool) void {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    const h: i32 = @intFromFloat(r.height);
    const on = slotHas(s, v);
    // THE PRESS SINKS THE WHOLE CELL — picture, tally and all. That is the difference between a button
    // that lights up and one that gives under a thumb.
    const sink: i32 = if (sel) @intFromFloat(@round(self.press * 2.0)) else 0;
    const pop = if (sel) self.pop / POP_DUR else 0;
    const sy = y + sink - @as(i32, @intFromFloat(@round(pop * pop * 3.0)));

    // A socket nothing can go in yet is drawn FAINT, not merely empty: half the doll is waiting on gear that
    // does not exist, and at full strength it reads as a page that has lost its contents.
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

    // THE COUNT IS ALL A SOCKET SAYS. What is IN it is named once, for the one under the cursor
    // (`drawEquipment`) — five captions at this pitch is a row of words running into each other.
    if (slotTally(s, v)) |n| hud.tally(fmt("{d}", .{n}), x + w, sy + h, hud.SMALL, if (n > 0) uiart.TEXT_VALUE else uiart.BAD);
}

fn drawSlotArt(s: SlotId, v: View, cx: f32, cy: f32, px: f32) void {
    switch (s) {
        // EXHAUSTIVE over the arm, like the HUD's own right-hand cell (`game.hud`): as a two-way `if` the
        // BELL drew a sword in his fist on the one page whose whole job is showing what he is carrying.
        .right => switch (v.arm) {
            .sword => itemart.sword(cx, cy, px),
            .bow => itemart.bow(cx, cy, px),
            .bell => itemart.bell(cx, cy, px),
        },
        .left => if (v.arm != .bow) switch (v.off) {
            .shield => itemart.shield(cx, cy, px),
            .wand => itemart.wand(cx, cy, px),
        },
        // THE PICTURE FOLLOWS THE ROD TOO, greyed by the pool the same way the cross's own slot is.
        .sorcery => if (slotHas(.sorcery, v)) switch (v.spell) {
            .bolt => itemart.spell(cx, cy, px, v.fp >= combat.spellFp(v.spell)),
            .roots => itemart.roots(cx, cy, px, v.fp >= combat.spellFp(v.spell)),
        },
        // A shaft is drawn 0.3 of the box it is handed where a blade is 1.4, so it is given a bigger one.
        .arrows => itemart.arrow(cx, cy, px * 1.5, v.quiver.count(v.quiver.sel) > 0, v.quiver.sel == .fire),
        .helm, .chest, .belt, .boots, .amulet, .ring1, .ring2 => {},
        else => if (quickAt(s, v)) |k| itemart.drawHeld(k, cx, cy, px, quickTally(k, v) > 0),
    }
}

/// The right-hand column: what the set is worth. With a candidate, every row gains a second value and an
/// arrow — which is the whole reason the equipment page shows numbers at all.
fn drawDerived(box: Box, v: View, cand: ?Cand) void {
    const inner = panel(box, "");
    const base = Loadout{ .arm = v.arm, .off = v.off, .ammo = v.quiver.sel, .quick = v.quick.selected(), .spell = v.spell };
    const now = derive(base, v);
    const then = if (cand) |c| derive(withCand(base, c), v) else now;

    // THE ROWS ARE FITTED TO THE PANEL, not the other way round: with a picker open this column is half
    // the height it has to itself, and ten rows at a fixed pitch walked straight off the bottom of it.
    const says = if (cand) |c| candSays(c, v) else armSays(v.arm, v.off);
    const foot = proseH(says, inner.w, hud.HINT) + 22;
    const head: i32 = if (cand == null) 0 else hud.lineH(hud.SMALL) + 4;
    const step = rowStep(inner.h - foot - head, ND);
    const colB = inner.right();
    const colA = colB - @divTrunc(inner.w, 3);
    var y = inner.y;
    if (cand != null) {
        rowValue("NOW", colA, y, uiart.TEXT_DIM);
        rowValue("THEN", colB, y, mathx.withAlpha(uiart.GILT, 220));
        y += head;
    }
    for (DER, 0..) |row, i| {
        const moved = @abs(then[i] - now[i]) > 0.005;
        rowLabel(row.name, inner.x, y, if (moved) uiart.TEXT_VALUE else uiart.TEXT_DIM);
        if (cand == null) {
            rowValue(unitStr(row.unit, now[i]), colB, y, uiart.TEXT_VALUE);
        } else {
            rowValue(unitStr(row.unit, now[i]), colA, y, mathx.withAlpha(uiart.TEXT_DIM, 200));
            // A COST IS NOT AN IMPROVEMENT: on the stamina rows, and only there, LESS is the better number.
            const rose = then[i] > now[i];
            const col = if (!moved) uiart.TEXT_DIM else if (rose != row.cost) uiart.GOOD else uiart.BAD;
            rowValue(unitStr(row.unit, then[i]), colB, y, col);
            if (moved) uiart.diamond(fi(colA + 20), fi(y) + fi(hud.lineH(hud.SMALL)) * 0.45, if (rose) 3.4 else 2.2, col);
        }
        y += step;
    }
    // THE FOOT GOES UNDER THE LAST ROW THAT WAS ACTUALLY DRAWN, not at a fixed drop from the panel's bottom.
    // `rowStep` FLOORS at one line height, so with a picker open the twelve rows can be taller than the space
    // left for them — which drew the divider through "Ammunition" and printed the blurb over the row above.
    const footY = @max(inner.y + inner.h - foot + 22, y + 8);
    uiart.divider(inner.x + @divTrunc(inner.w, 2), @max(footY - 12, y + 2), @divTrunc(inner.w, 2) - 10, 120);
    _ = prose(says, inner.x, footY, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn armSays(a: heromod.Arm, o: heromod.Off) []const u8 {
    if (a == .bow) return "The bow takes both hands, so nothing is on his left arm and nothing can be blocked.";
    return switch (o) {
        .shield => "Sword and shield: he can guard, and a guard is worth more than any number on this page.",
        .wand => "Sword and wand. He casts with the hand that used to block, and pays in Focus instead of stamina.",
    };
}

fn candSays(c: Cand, _: View) []const u8 {
    return switch (c.act) {
        .arm => |a| switch (a) {
            .sword => "Back to sword and shield, and back to being able to guard.",
            .bow => "Both hands go to the bow, and the shield goes with them.",
            .bell => "Ring it and what the scroll names comes. Nothing else: with the bell in his hand he has no attack at all.",
        },
        .off => |o| switch (o) {
            .shield => "Boards back on the arm. He can guard again, and the wand goes away with the sorcery.",
            .wand => "The wand takes the shield's hand, so there is no guarding - and L1 casts instead of blocks.",
        },
        .ammo => |a| switch (a) {
            .plain => "A plain shaft. Ten of them, and nothing in these ruins resists the hole one leaves.",
            .fire => "Fire rides on top of the shaft's own damage. Five of them, so pick the target.",
        },
        // Short on purpose: `item.describe` is a paragraph and the rows have nowhere to shrink to.
        .quick => |q| if (q.kind == null)
            "Leave the socket empty."
        else
            "On the belt, which is the only reach he has in a fight.",
        else => "",
    };
}

/// THE LIST, under the sockets it is choosing for. The pricing is NOT here any more — it holds the
/// right-hand column whether a picker is open or not, so the numbers do not move when the list appears.
fn drawPicker(self: *const Book, col: Box, s: SlotId, v: View) void {
    var buf: [CAND_MAX]Cand = undefined;
    const cs = candidates(s, v, &buf);
    const inner = panel(pickBox(col, cs.len), fmt("{s}  >", .{slotName(s)}));
    for (cs, 0..) |c, i| {
        const y = inner.y + @as(i32, @intCast(i)) * pickRowH();
        const on = self.pick == i;
        if (on) uiart.rowHilite(inner.x - 8, y - 6, inner.w + 16, pickRowH() - 2);
        hud.text(c.name, inner.x + 10, y, hud.BODY, if (on) uiart.HOT else uiart.TEXT_DIM);
        if (equipped(c, v)) {
            const tag = "EQUIPPED";
            hud.text(tag, inner.right() - hud.textW(tag, hud.TINY) - 46, y + 5, hud.TINY, mathx.withAlpha(uiart.GILT, 200));
        }
        if (c.tally) |n| {
            const str = fmt("{d}", .{n});
            hud.text(str, inner.right() - hud.textW(str, hud.BODY), y, hud.BODY, if (n > 0) uiart.TEXT_VALUE else uiart.BAD);
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
    // THE PICTURE LIFTS OFF ITS SOCKET under the cursor and goes back down under a press — a pixel of air
    // is the cheapest way to say "this is the one in your hand".
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
    // THE PICTURE BIG, on its own plate: this panel is the only place in the game the drawings are seen
    // at a size that shows what they are.
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
    // WHAT IT DOES, in the game's own numbers — read off `item.use`, so a dose tuned there reads here.
    // ONE effect line per arm; the use-or-refuse hint below is shared, because the refusal is the quick
    // bar's rule and not any one effect's.
    //
    // **THE OTHER RENDERER OF THE SAME UNION IS `item.effect`**, and the split is deliberate rather than
    // missed: this one RESOLVES the doses against the sheet in front of it ("Restores 42 HP"), which is what a
    // player holding the thing wants and what the editor's loot row cannot have — there is no hero there. Both
    // are exhaustive switches on `item.Use`, so a new arm cannot be added to one and forgotten in the other;
    // what can drift is the WORDING, so keep the two saying the same thing about the same effect.
    switch (item.use(k)) {
        .none => hud.text("It does nothing you can do here.", inner.x, y, hud.HINT, uiart.TEXT_HINT),
        .regen => |r| hud.text(fmt("Restores {d:.0} HP over {d:.0} seconds.", .{ v.sheet.hp() * r.frac, r.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .lob => |l| hud.text(fmt("Thrown at the reticle; bursts for {d:.0} + {d:.0} {s}.", .{ l.dmg, l.fire + l.lightning, if (l.lightning > 0) @as([]const u8, "lightning") else "fire" }), inner.x, y, hud.SMALL, uiart.GOOD),
        .ward => |w| hud.text(fmt("Chaos slides off you (+{d:.0}) for {d:.0} seconds.", .{ w.chaos, w.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .wind => |w| hud.text(fmt("Half your wind back at once ({d:.0} stamina), and the lockout with it.", .{ v.sheet.stamina() * w.share }), inner.x, y, hud.SMALL, uiart.GOOD),
        .grease => |gr| hud.text(fmt("The sword hangs {d:.0}% of its blow as fire for {d:.0} seconds.", .{ gr.frac * 100, gr.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
        .souls => |so| hud.text(fmt("Crushed for {d} souls, on the spot.", .{so.n}), inner.x, y, hud.SMALL, uiart.GOOD),
        .brew => |b| hud.text(fmt("Your wind returns {d:.1}x as fast for {d:.0} seconds.", .{ b.mult, b.secs }), inner.x, y, hud.SMALL, uiart.GOOD),
    }
    if (item.usable(k)) {
        const hy = y + hud.lineH(hud.SMALL) + 6;
        // THE REFUSAL SAYS WHY AND SAYS WHERE. A greyed prompt with no reason is a prompt the player
        // calls broken (`locked`'s rule, one page over).
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


/// THE WHEEL, READ-ONLY. The page itself is `tree.drawPage`, shared with the bonfire's own screen — the book
/// can no longer be opened at a fire, so `spendable` is false here and always will be: this is where you
/// plan a build and the bonfire is where you commit one.
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
    // THE LEVEL IS THE TREE'S, not the sheet's count of points past the start: a level spent on a PASSIVE
    // moves no attribute, and `Sheet.level` would quietly report a lower number than the fire charged for.
    const inner = panel(col, fmt("ATTRIBUTES    LEVEL {d}", .{v.tree.level()}));
    var y = inner.y;
    for (0..stats.NA) |i| {
        const a: stats.Attr = @enumFromInt(i);
        const on = self.cur[idx(.stats)] == i;
        const inert = v.sheet.barFor(a) == null;
        if (on) uiart.rowHilite(inner.x - 10, y - 6, inner.w + 20, attrStep() - 4);
        const col2 = if (on) uiart.HOT else if (inert) mathx.withAlpha(uiart.TEXT_DIM, 170) else uiart.TEXT_VALUE;
        hud.text(stats.displayName(a), inner.x, y, hud.BODY, col2);
        const val = fmt("{d}", .{v.sheet.at(a)});
        hud.text(val, inner.right() - hud.textW(val, hud.BODY), y, hud.BODY, col2);
        // The point on the 1…99 run, with the START marked: an attribute nobody has spent on says so.
        const barY = y + hud.lineH(hud.BODY) + 1;
        uiart.well(inner.x, barY, inner.w, 3, 220);
        rl.drawRectangle(inner.x, barY, inner.w, 3, rgba(52, 46, 38, 190)); // a track you can SEE the empty of
        const f = @as(f32, @floatFromInt(v.sheet.at(a))) / @as(f32, @floatFromInt(stats.MAX));
        rl.drawRectangle(inner.x, barY, @intFromFloat(fi(inner.w) * f), 3, mathx.withAlpha(if (inert) uiart.GILT_DIM else uiart.GILT, 220));
        const startAt: i32 = @intFromFloat(fi(inner.w) * @as(f32, @floatFromInt(stats.START)) / @as(f32, @floatFromInt(stats.MAX)));
        rl.drawRectangle(inner.x + startAt, barY - 2, 1, 7, mathx.withAlpha(uiart.CATCH, 120));
        y += attrStep();
    }
    y += 6;
    uiart.divider(inner.x + @divTrunc(inner.w, 2), y, @divTrunc(inner.w, 2) - 10, 120);
    const a: stats.Attr = @enumFromInt(@min(self.cur[idx(.stats)], stats.NA - 1));
    const says = if (v.sheet.barFor(a)) |t| fmt("{s}  Yours: {d:.0}.", .{ stats.governs(a), t }) else stats.governs(a);
    _ = prose(says, inner.x, y + 12, inner.w, hud.HINT, uiart.TEXT_HINT);
}

/// The middle column: the pools, WHAT EVERY ACTION SPENDS out of them (the other half of what Endurance
/// buys, and the only place the whole schedule can be read at once), and what he shrugs off.
fn drawBody(col: Box, v: View) void {
    const inner = panel(col, "BODY");
    const pools = [_]struct { [:0]const u8, f32 }{
        .{ "HP", v.sheet.hp() },
        .{ "FP", v.sheet.fp() },
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
    const sect = hud.lineH(hud.TINY) + 6 + 22; // a heading, its divider and the air round them
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
        // The stacked number, and the CAP beside it when they differ — PoE2's own display.
        const s = if (@abs(raw - eff) < 0.05) fmt("{d:.0}%", .{raw}) else fmt("{d:.0}% ({d:.0}%)", .{ raw, eff });
        rowValue(s, inner.right(), y, if (eff > 0.05) uiart.GOOD else if (eff < -0.05) uiart.BAD else uiart.TEXT_DIM);
        y += step;
    }
    _ = prose(says, inner.x, y + 6, inner.w, hud.HINT, uiart.TEXT_HINT);
}

/// A divider and a heading between two blocks of rows, returning where the next block starts.
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

pub fn unload() void {
    if (portRT) |t| rl.unloadRenderTexture(t);
    portRT = null;
}

fn drawPortrait(self: *const Book, col: Box, portrait: ?Portrait, caption: [:0]const u8) void {
    const inner = panel(col, "THE TARNISHED");
    const capH = hud.lineH(hud.HINT) + 6;
    const frameH = inner.h - capH;
    // The blit keeps the target's own aspect and is centred in what is left of the panel.
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

    const focus = v3(p.hero.pos.x, p.hero.pos.y + 0.94, p.hero.pos.z);
    const dist: f32 = 3.5;
    const pitch: f32 = 0.14;
    const cp = mathx.cosf(pitch);
    // THE TURNTABLE IS HUNG OFF HIS FACING, not off the world: he is photographed three-quarters from the
    // front wherever he happens to be standing and whichever way the fight left him pointing.
    const yaw = p.hero.facing + self.spin;
    const cam = rl.Camera3D{
        .position = v3(
            focus.x + mathx.sinf(yaw) * cp * dist,
            focus.y + mathx.sinf(pitch) * dist,
            focus.z + mathx.cosf(yaw) * cp * dist,
        ),
        .target = focus,
        .up = v3(0, 1, 0),
        .fovy = 40,
        .projection = .perspective,
    };
    rl.beginTextureMode(rt);
    rl.clearBackground(rgba(14, 12, 10, 255));
    rl.beginMode3D(cam);
    p.scene.bind(cam.position);
    p.scene.shadowsOff();
    p.scene.setLights(&.{});
    p.scene.setGround(false);
    p.hero.draw();
    rl.endMode3D();
    rl.endTextureMode();

    rl.drawTexturePro(rt.texture, .{ .x = 0, .y = 0, .width = fi(PORT_W), .height = -fi(PORT_H) }, dst, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
    // A candle under him and dusk at every edge, so he stands IN the panel instead of on top of it.
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


const TEST_QUICK = combat.Quick{}; // the default bar: the two flasks, crimson up
const TEST_TREE = ptree.Tree{}; // …and a fresh tree: level 1, no points, nothing taken

fn testView(bag: *const item.Bag, sheet: *const stats.Sheet, res: *const combat.Resists, flasks: *const combat.Flasks, quiver: *const combat.Quiver, arm: heromod.Arm) View {
    return testViewOff(bag, sheet, res, flasks, quiver, arm, .shield);
}

fn testViewOff(bag: *const item.Bag, sheet: *const stats.Sheet, res: *const combat.Resists, flasks: *const combat.Flasks, quiver: *const combat.Quiver, arm: heromod.Arm, off: heromod.Off) View {
    return .{ .bag = bag, .sheet = sheet, .res = res, .flasks = flasks, .quick = &TEST_QUICK, .quiver = quiver, .tree = &TEST_TREE, .arm = arm, .off = off, .spell = .bolt, .fp = combat.FP_MAX, .souls = 0 };
}

test "the paper doll walks by geometry, and every step lands on a socket" {
    // Hard rails: pushed at a wall the cursor STAYS PUT rather than wrapping to the far side of the body.
    try std.testing.expectEqual(@intFromEnum(SlotId.chest), slotStep(@intFromEnum(SlotId.helm), 0, 1));
    try std.testing.expectEqual(@intFromEnum(SlotId.right), slotStep(@intFromEnum(SlotId.chest), 1, 0));
    try std.testing.expectEqual(@intFromEnum(SlotId.left), slotStep(@intFromEnum(SlotId.chest), -1, 0));
    try std.testing.expectEqual(@intFromEnum(SlotId.helm), slotStep(@intFromEnum(SlotId.helm), 0, -1));
    // …and the two blocks JOIN: down off the doll's last row is the first quick socket under it.
    try std.testing.expectEqual(@intFromEnum(SlotId.q1), slotStep(@intFromEnum(SlotId.arrows), 0, 1));
    try std.testing.expectEqual(@intFromEnum(SlotId.q6), slotStep(@intFromEnum(SlotId.q1), 0, 1));
    try std.testing.expectEqual(@intFromEnum(SlotId.q9), slotStep(@intFromEnum(SlotId.q8), 1, 0));
    for (0..NSLOT) |i| {
        for ([_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |d| {
            try std.testing.expect(slotStep(i, d[0], d[1]) < NSLOT);
        }
    }
    // …and the BAG is still the ragged case: five across, so down from row 0 lands on the row below.
    try std.testing.expectEqual(@as(usize, 7), grid(2, 8, BAG_COLS, 0, 1));
    try std.testing.expectEqual(@as(usize, 0), grid(0, 0, BAG_COLS, 1, 1)); // an EMPTY bag still has a cell
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
    try std.testing.expect(worth(sword, .guard) > 0 and worth(bow, .guard) == 0); // the bow's real cost
    try std.testing.expect(worth(sword, .light) > worth(bow, .light)); // …and the sword hits harder up close
    // FIRE SHOWS ONLY ON A FIRE ARROW, and it is a fraction of that shaft's own physical.
    const fire = derive(.{ .arm = .bow, .off = .shield, .ammo = .fire, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    try std.testing.expect(worth(bow, .fire) == 0 and worth(fire, .fire) > 0);
    try std.testing.expectApproxEqAbs(worth(bow, .heavy) * heromod.FIRE_ARROW_FRAC, worth(fire, .fire), 1e-3);
    // The quick-item row follows the flask, and the two draughts do not fill the same bar.
    const cer = derive(.{ .arm = .sword, .off = .shield, .ammo = .plain, .quick = item.Kind.cerulean_flask, .spell = .bolt }, v);
    try std.testing.expectApproxEqAbs(sheet.hp() * combat.FLASK_HP_FRAC, worth(sword, .quick), 1e-3);
    try std.testing.expectApproxEqAbs(sheet.fp() * combat.FLASK_FP_FRAC, worth(cer, .quick), 1e-3);
    // A ROW MOVES ONLY WHEN THE THING THAT FEEDS IT DOES: behind a sword, choosing the other arrow moves
    // the tally it counts and not one number he swings with.
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
    // BOTH HANDS ARE SWEPT, all four combinations: the left hand is a real choice now, and the sorcery slot
    // answers differently to each of the two reasons it can be empty.
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
                    try std.testing.expect(cs.len >= 2); // a picker with one row has nothing to offer
                }
                try std.testing.expect(slotName(s).len > 0);
                try std.testing.expect(slotFilled(s, v).len > 0);
            }
            // …and the SORCERY slot is filled exactly when something that can cast is in that hand.
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
    // The left hand's price, and it is the SAME row the bow is billed on, because it is the same hand.
    try std.testing.expect(worth(board, .guard) > 0 and worth(rod, .guard) == 0);
    // …and what he got for it. Zero behind a shield, because a spell he cannot cast is not worth a number.
    try std.testing.expect(worth(board, .spell) == 0 and worth(rod, .spell) > 0);
    try std.testing.expect(worth(board, .spell_fp) == 0 and worth(rod, .spell_fp) > 0);
    // A BOW SILENCES IT WHICHEVER WAY THE LEFT SLOT IS SET — both hands are on the string.
    const bowRod = derive(.{ .arm = .bow, .off = .wand, .ammo = .plain, .quick = item.Kind.crimson_flask, .spell = .bolt }, v);
    try std.testing.expect(worth(bowRod, .spell) == 0 and worth(bowRod, .guard) == 0);
    // …and the swing rows do not move: taking a wand changes nothing about the sword in the other hand.
    for ([_]Der{ .light, .heavy, .poise, .stance, .stam_light, .stam_heavy }) |k| {
        try std.testing.expectEqual(worth(board, k), worth(rod, k));
    }
    // THE TALLY IS CASTS, NOT POINTS — a full pool reads as a countable number in the slot.
    try std.testing.expectEqual(@as(u8, 0), castsLeft(combat.BOLT_FP - 0.01, .bolt));
    try std.testing.expectEqual(@as(u8, 1), castsLeft(combat.BOLT_FP, .bolt));
    try std.testing.expect(castsLeft(combat.FP_MAX, .bolt) >= 4);
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
    // THE bug: both rows read the bolt's constants, so turning the rod moved nothing on the sheet.
    try std.testing.expect(worth(roots, .spell_fp) > worth(bolt, .spell_fp));
    try std.testing.expect(worth(roots, .spell) < worth(bolt, .spell));
    try std.testing.expectApproxEqAbs(combat.spellFp(.roots), worth(roots, .spell_fp), 1e-4);
    // …and so did the slot's name and its cast tally.
    try std.testing.expectEqualStrings(combat.spellName(.bolt), slotFilled(.sorcery, v));
    v.spell = .roots;
    try std.testing.expectEqualStrings(combat.spellName(.roots), slotFilled(.sorcery, v));
    try std.testing.expect(castsLeft(combat.FP_MAX, .roots) < castsLeft(combat.FP_MAX, .bolt));
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
    // …and an EMPTIED bag leaves it on the one cell that is drawn rather than off the grid.
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
    // Out of combat the page is the convenient way…
    try std.testing.expectEqual(Action{ .use = .mushroom_jerky }, b.confirm(calm));
    // …and in it, nothing at all comes off this page. The quick bar is the only reach he has.
    try std.testing.expectEqual(Action.none, b.confirm(fighting));
}

test "THE QUICK PICKER OFFERS ONLY WHAT HE HAS — and the flasks, which are never the bag's" {
    var bag = item.Bag{};
    const sheet = stats.Sheet{};
    const res = combat.Resists{};
    const flasks = combat.Flasks{};
    const quiver = combat.Quiver{};
    var buf: [CAND_MAX]Cand = undefined;

    // An empty bag still offers the two flasks — their charges come back at a bonfire — plus the empty row.
    const broke = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    const bare = candidates(.q0, broke, &buf);
    try std.testing.expectEqual(@as(usize, 3), bare.len);
    try std.testing.expectEqual(@as(?item.Kind, null), bare[0].act.quick.kind); // …and it is first
    for (bare[1..]) |c| try std.testing.expect(combat.flaskOf(c.act.quick.kind.?) != null);

    // …and an edible shows up exactly when one is in the bag.
    bag.add(.mushroom_jerky, 1);
    bag.add(.kobold_fang, 4); // owned, and still no business on a belt
    const fed = testView(&bag, &sheet, &res, &flasks, &quiver, .sword);
    var sawJerky = false;
    for (candidates(.q0, fed, &buf)) |c| {
        try std.testing.expectEqual(@as(usize, 0), c.act.quick.slot); // every row fills THIS socket
        const k = c.act.quick.kind orelse continue;
        try std.testing.expect(item.quickable(k));
        try std.testing.expect(combat.flaskOf(k) != null or fed.bag.count(k) > 0);
        try std.testing.expectEqual(fed.quick.slots[0] == k, equipped(c, fed));
        if (k == .mushroom_jerky) sawJerky = true;
    }
    try std.testing.expect(sawJerky);
    // It opens on what THAT socket holds; the rows are filtered and carry an empty one, so it is counted out.
    try std.testing.expectEqual(quickRowOf(fed.quick.slots[0], fed), pickIndexOf(.q0, fed));
}

test "THE SCRATCH FITS THE LONGEST LIST ANY SOCKET CAN OFFER, empty row and all" {
    // `CAND_MAX` sized the buffer at `item.NK` and the quick picker writes `item.NK + 1` rows in the worst
    // case — the "(empty)" one is a row like the others. It cannot be reached with today's six quickable
    // kinds, which is exactly why it has to be arithmetic and not a count of what happens to be in the table.
    try std.testing.expect(CAND_MAX >= item.NK + 1);
    // …and every slot's real list fits inside it, with a bag holding one of everything.
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
    try std.testing.expectApproxEqAbs(sheet.hp() * combat.FLASK_HP_FRAC, quickWorth(.crimson_flask, v), 1e-3);
    try std.testing.expectApproxEqAbs(sheet.fp() * combat.FLASK_FP_FRAC, quickWorth(.cerulean_flask, v), 1e-3);
    const jerky = item.use(.mushroom_jerky).regen;
    try std.testing.expectApproxEqAbs(sheet.hp() * jerky.frac, quickWorth(.mushroom_jerky, v), 1e-3);
}

test "the sockets are fitted to the panel, and never off the end of it" {
    // A window a quarter the size and one four times it both have to lay out: the socket is a share of the
    // card, which is itself a share of the screen.
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
    // …and it GROWS with the window rather than sitting at one size.
    const small = slotFit(.{ .x = 0, .y = 0, .w = 620, .h = 380 });
    const big = slotFit(.{ .x = 0, .y = 0, .w = 2400, .h = 1300 });
    try std.testing.expect(big.px > small.px);
}
