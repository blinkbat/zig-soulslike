const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const itemart = @import("itemart.zig");
const item = @import("item.zig");
const stats = @import("stats.zig");
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

    fn label(p: Page) [:0]const u8 {
        return switch (p) {
            .equipment => "EQUIPMENT",
            .inventory => "INVENTORY",
            .stats => "STATS",
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
    flask: combat.FlaskKind,
    use: item.Kind,
};

/// EVERYTHING THE BOOK READS, borrowed for the frame — all of it the live state the game plays with.
pub const View = struct {
    bag: *const item.Bag,
    sheet: *const stats.Sheet,
    res: *const combat.Resists,
    flasks: *const combat.Flasks,
    quiver: *const combat.Quiver,
    arm: heromod.Arm,
    off: heromod.Off,
    /// The live FP pool, so the sorcery slot can say how many casts are actually in it.
    fp: f32,
    runes: u32,
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
    flask: combat.FlaskKind,
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
    rows[@intFromEnum(Der.spell)] = .{ .name = "Chaos bolt", .unit = .flat };
    rows[@intFromEnum(Der.spell_fp)] = .{ .name = "Focus, per cast", .unit = .flat, .cost = true };
    rows[@intFromEnum(Der.quick)] = .{ .name = "Quick item restores", .unit = .flat };
    rows[@intFromEnum(Der.ammo)] = .{ .name = "Ammunition", .unit = .count };
    break :blk rows;
};

fn derive(l: Loadout, v: View) [ND]f32 {
    const bow = l.arm == .bow;
    const light = if (bow) heromod.BOW_QUICK_HIT else heromod.ATK_LIGHT_HIT;
    const heavy = if (bow) heromod.arrowBlow(l.ammo, true) else heromod.ATK_HEAVY_HIT;
    var d: [ND]f32 = undefined;
    d[@intFromEnum(Der.light)] = light.dmg;
    d[@intFromEnum(Der.heavy)] = heavy.dmg;
    d[@intFromEnum(Der.fire)] = heavy.elem.total();
    d[@intFromEnum(Der.poise)] = heavy.poise;
    d[@intFromEnum(Der.stance)] = heavy.stance;
    d[@intFromEnum(Der.stam_light)] = if (bow) combat.STAM_SHOT else combat.STAM_LIGHT;
    d[@intFromEnum(Der.stam_heavy)] = if (bow) combat.STAM_AIMED else combat.STAM_HEAVY;
    // THE BOW COSTS HIM THE SHIELD, and so does the WAND — this is the row where that is a number rather
    // than lore, and it is the same number for both because it is the same left hand being spent.
    const guards = !bow and l.off == .shield;
    d[@intFromEnum(Der.guard)] = if (guards) combat.GUARD_NEGATE * 100.0 else 0;
    // …and what he bought with it. Zero on both rows unless a wand is actually in that hand, because a
    // spell he cannot cast is not worth a number (`stats.governs`' rule about an inert attribute).
    const casts = !bow and l.off == .wand;
    d[@intFromEnum(Der.spell)] = if (casts) combat.SPELL_HIT.raw() else 0;
    d[@intFromEnum(Der.spell_fp)] = if (casts) combat.SPELL_FP else 0;
    d[@intFromEnum(Der.quick)] = switch (l.flask) {
        .crimson => v.sheet.hp() * combat.FLASK_HP_FRAC,
        .cerulean => v.sheet.fp() * combat.FLASK_FP_FRAC,
    };
    d[@intFromEnum(Der.ammo)] = @floatFromInt(v.quiver.count(l.ammo));
    return d;
}


const SlotId = enum { right, left, sorcery, arrows, quick };
const NSLOT = @typeInfo(SlotId).@"enum".fields.len;
const SLOT_COLS: usize = 3;

fn slotName(s: SlotId) [:0]const u8 {
    return switch (s) {
        .right => "Right Hand",
        .left => "Left Hand",
        .sorcery => "Sorcery",
        .arrows => "Arrows",
        .quick => "Quick Item",
    };
}

/// WHY A SLOT CANNOT BE CHANGED, or null when it can. Said in words on the panel, because a slot that
/// only refuses the button is a slot the player decides is broken.
fn locked(s: SlotId, v: View) ?[:0]const u8 {
    return switch (s) {
        // The left hand is a real choice now — boards or a wand — and the only thing that takes the choice
        // away is a bow, which takes the hand itself.
        .left => if (v.arm == .bow) "Both hands are on the bow. The left one comes back when the sword does." else null,
        // …and the sorcery slot is only empty while nothing that could cast is in that hand. It says which
        // of the two reasons it is, because "locked" with no reason is a slot the player calls broken.
        .sorcery => if (v.arm == .bow)
            "Both hands are on the bow. Nothing is free to hold a wand."
        else if (v.off != .wand)
            "One sorcery known, and no wand in his hand to cast it with."
        else
            // FILLED AND STILL UNCHANGEABLE, which is a different sentence from being empty: there is
            // exactly one sorcery, so there is nothing to change it TO. The day there is a second, this arm
            // goes away and the slot grows a picker like every other one.
            "Chaos Bolt, and the only sorcery he knows.",
        else => null,
    };
}

/// Is there anything in it? The socket lights off this, and an empty one stays cold.
fn slotHas(s: SlotId, v: View) bool {
    return switch (s) {
        .right, .quick => true,
        .left => v.arm != .bow,
        .sorcery => v.arm != .bow and v.off == .wand,
        .arrows => v.quiver.count(v.quiver.sel) > 0,
    };
}

// WHAT EACH THING IS CALLED, once. The slot caption and the picker row are the same armament named twice,
// and two copies of a name are two names the day one of them is edited.
const EMPTY = "-";

fn armName(a: heromod.Arm) [:0]const u8 {
    return switch (a) {
        .sword => "Straight Sword",
        .bow => "Short Bow",
    };
}

fn offName(o: heromod.Off) [:0]const u8 {
    return switch (o) {
        .shield => "Small Shield",
        .wand => "Knotted Wand",
    };
}

/// The one sorcery, named once. Not walked off an enum yet because there is only one of it — the day there
/// is a second, that name goes beside this one and the slot grows a picker like the others.
const SPELL_NAME = "Chaos Bolt";

fn ammoName(k: combat.ArrowKind) [:0]const u8 {
    return switch (k) {
        .plain => "Arrow",
        .fire => "Fire Arrow",
    };
}

fn flaskName(k: combat.FlaskKind) [:0]const u8 {
    return switch (k) {
        .crimson => "Crimson Tears",
        .cerulean => "Cerulean Tears",
    };
}

fn slotFilled(s: SlotId, v: View) [:0]const u8 {
    return switch (s) {
        .right => armName(v.arm),
        .left => if (v.arm == .bow) EMPTY else offName(v.off),
        .sorcery => if (slotHas(.sorcery, v)) SPELL_NAME else EMPTY,
        .arrows => ammoName(v.quiver.sel),
        .quick => flaskName(v.flasks.sel),
    };
}

fn slotTally(s: SlotId, v: View) ?u8 {
    return switch (s) {
        .arrows => v.quiver.count(v.quiver.sel),
        .quick => v.flasks.charges(v.flasks.sel),
        // HOW MANY CASTS ARE ACTUALLY IN THE POOL — the same question the arrow tally answers, and the one
        // thing about a spell the player needs at a glance.
        .sorcery => if (slotHas(.sorcery, v)) castsLeft(v.fp) else null,
        else => null,
    };
}

fn castsLeft(fp: f32) u8 {
    if (combat.SPELL_FP <= 0) return 0;
    return @intFromFloat(@max(0, @floor(fp / combat.SPELL_FP)));
}

/// THE CANDIDATES a slot can be filled from — the picker's rows. Names and counts only; what a choice is
/// WORTH is `derive`'s job.
const Cand = struct { name: [:0]const u8, tally: ?u8 = null, act: Action };

/// The longest candidate list any slot can offer, off the enums themselves — the scratch every caller
/// hands `candidates` is sized from this, so a third arrow cannot write past the end of one.
const CAND_MAX = blk: {
    var n: usize = 0;
    for ([_]type{ heromod.Arm, heromod.Off, combat.ArrowKind, combat.FlaskKind }) |T| {
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
        .quick => {
            inline for (@typeInfo(combat.FlaskKind).@"enum".fields, 0..) |f, i| {
                const k: combat.FlaskKind = @enumFromInt(f.value);
                out[i] = .{ .name = flaskName(k), .tally = v.flasks.charges(k), .act = .{ .flask = k } };
            }
            return out[0..@typeInfo(combat.FlaskKind).@"enum".fields.len];
        },
        else => return out[0..0],
    }
}

/// The loadout that WOULD be in force if this candidate were taken — what the delta column prices.
fn withCand(base: Loadout, c: Cand) Loadout {
    var l = base;
    switch (c.act) {
        .arm => |a| l.arm = a,
        .off => |o| l.off = o,
        .ammo => |a| l.ammo = a,
        .flask => |f| l.flask = f,
        else => {},
    }
    return l;
}

fn equipped(c: Cand, v: View) bool {
    return switch (c.act) {
        .arm => |a| a == v.arm,
        .off => |o| o == v.off,
        .ammo => |a| a == v.quiver.sel,
        .flask => |f| f == v.flasks.sel,
        else => false,
    };
}

/// Where a picker opens: on what is ALREADY equipped, never on row 0. Landing the cursor somewhere other
/// than the current choice is how a menu tricks you into swapping something you meant to look at.
/// The rows are built in enum order, so the equipped thing's ORDINAL is its row — no second table to keep
/// in step with the first.
fn pickIndexOf(s: SlotId, v: View) usize {
    return switch (s) {
        .right => @intFromEnum(v.arm),
        .left => @intFromEnum(v.off),
        .arrows => @intFromEnum(v.quiver.sel),
        .quick => @intFromEnum(v.flasks.sel),
        else => 0,
    };
}


const MOVE_EASE: f32 = 17.0; // how hard the cursor is pulled toward the slot it just moved to
const PRESS_RATE: f32 = 9.0;
const POP_DUR: f32 = 0.30; // the seat thump a slot gives when something lands in it
const SPIN_RATE: f32 = 1.7; // radians a second, the portrait turntable under Left/Right

pub const Book = struct {
    page: Page = .equipment,
    /// The cursor per page, kept so coming back to one finds it where you left it.
    cur: [NPAGE]usize = [_]usize{0} ** NPAGE,
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

    pub fn move(self: *Book, dx: i32, dy: i32, v: View) void {
        if (self.picking) |s| {
            var buf: [CAND_MAX]Cand = undefined;
            const cs = candidates(s, v, &buf);
            if (cs.len == 0 or dy == 0) return;
            const n: i32 = @intCast(cs.len);
            self.pick = @intCast(@mod(@as(i32, @intCast(self.pick)) + dy + n, n));
            self.moved();
            return;
        }
        const i = idx(self.page);
        const next = switch (self.page) {
            .equipment => grid(self.cur[i], NSLOT, SLOT_COLS, dx, dy),
            .inventory => grid(self.cur[i], @max(v.bag.distinct(), 1), BAG_COLS, dx, dy),
            // Up/Down walks the attributes; Left/Right is the turntable, so it must not move the cursor.
            .stats => if (dy == 0) self.cur[i] else @as(usize, @intCast(@mod(
                @as(i32, @intCast(self.cur[i])) + dy + @as(i32, stats.NA),
                @as(i32, stats.NA),
            ))),
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
            .inventory => {
                if (v.bag.nth(self.cur[idx(.inventory)])) |k| {
                    if (item.usable(k)) {
                        self.thump();
                        sfx.play(.menu_pick);
                        return .{ .use = k };
                    }
                }
                sfx.play(.menu_back);
            },
            .stats => sfx.play(.menu_back), // nothing to spend here: there is no leveling yet
        }
        return .none;
    }

    /// Stage a page for the shot harness, `ogre.debugStagger`'s pattern: a photograph of the picker open
    /// on the second candidate cannot be got by pretending to press buttons at 1/60 s a frame.
    pub fn debugShow(self: *Book, p: Page, cursor: usize, pickSlot: ?usize, row: usize) void {
        self.page = p;
        self.cur[idx(p)] = cursor;
        self.picking = if (pickSlot) |s| @enumFromInt(s) else null;
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
                return equipGrid(body).at(self.cur[idx(.equipment)]);
            },
            .inventory => {
                const g = bagGrid(body);
                return g.at(self.cur[idx(.inventory)] - self.scroll * BAG_COLS);
            },
            .stats => return attrRow(statsCols(body)[0], self.cur[idx(.stats)]),
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
    return body.cut(@divTrunc(body.w * 52, 100));
}

fn equipGrid(body: Box) Grid {
    const left = panelInner(equipCols(body)[0], true);
    const cw = @divTrunc(left.w - (@as(i32, SLOT_COLS) - 1) * 16, @as(i32, SLOT_COLS));
    const rows: i32 = (NSLOT + @as(i32, SLOT_COLS) - 1) / @as(i32, SLOT_COLS);
    const capH = hud.lineH(hud.TINY) + hud.lineH(hud.SMALL) + 10;
    const w = @min(cw, 152);
    const h = @min(@divTrunc(w * 5, 4), @divTrunc(left.h, rows) - capH - 12);
    const stepX = w + 16;
    const stepY = h + capH + 14;
    return .{
        .x = left.x + @divTrunc(left.w - (stepX * @as(i32, SLOT_COLS) - 16), 2),
        .y = left.y + hud.lineH(hud.TINY) + 2, // the slot NAME sits above the socket
        .cw = w,
        .ch = h,
        .stepX = stepX,
        .stepY = stepY,
        .cols = SLOT_COLS,
    };
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

/// THE PITCH `n` ROWS GET IN `space` PIXELS: their natural one, tightened to fit, and NEVER under the
/// line height — a panel too short for its rows spills off the bottom, which is ugly, where a negative
/// pitch stacks them backwards up through the heading, which is unreadable.
fn rowStep(space: i32, n: usize) i32 {
    const natural = hud.lineH(hud.SMALL) + 7;
    return mathx.clampI(@divTrunc(space, @as(i32, @intCast(n))), hud.lineH(hud.SMALL), natural);
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

/// Wrapped prose, returning the y it ended on — the panels' one paragraph idiom.
fn prose(s: []const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color) i32 {
    var lines: [8][:0]const u8 = undefined;
    var buf: [768]u8 = undefined;
    var yy = y;
    for (hud.wrap(s, size, w, &buf, &lines)) |line| {
        hud.text(line, x, yy, size, col);
        yy += hud.lineH(size);
    }
    return yy;
}

/// How tall a paragraph will be BEFORE it is drawn, so a panel can anchor it to its own floor instead of
/// letting it run out over the crib line — which is what the picker's short column did.
fn proseH(s: []const u8, w: i32, size: i32) i32 {
    var lines: [8][:0]const u8 = undefined;
    var buf: [768]u8 = undefined;
    return @as(i32, @intCast(hud.wrap(s, size, w, &buf, &lines).len)) * hud.lineH(size);
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
    }

    // THE CURSOR LAST, over everything: it is in front of the page, not part of it.
    if (self.at.width > 1) {
        uiart.slotCursor(
            @intFromFloat(self.at.x),
            @intFromFloat(self.at.y),
            @intFromFloat(self.at.width),
            @intFromFloat(self.at.height),
            self.press,
            1.0,
        );
    }

    const hint: [:0]const u8 = switch (self.page) {
        .equipment => if (self.picking != null)
            "Up/Down choose    A/Enter equip    B/Esc cancel"
        else
            "Arrows move    A/Enter open a slot    Q/E or LB/RB page    B/Esc close",
        .inventory => "Arrows move    A/Enter use    Q/E or LB/RB page    B/Esc close",
        .stats => "Up/Down read an attribute    Left/Right turn him    Q/E or LB/RB page    B/Esc close",
    };
    hud.text(
        hint,
        card.x + @divTrunc(card.w - hud.textW(hint, hud.HINT), 2),
        card.y + card.h - footH() + 2,
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
    // The runes he is carrying ride the header's right end, which is ER's own corner for them.
    const runes = fmt("{d}", .{v.runes});
    const rx = card.right() - PAD - hud.textW(runes, hud.BODY);
    hud.text(runes, rx, y + 8, hud.BODY, uiart.TEXT_VALUE);
    hud.text("RUNES", rx - hud.textW("RUNES", hud.TINY) - 10, y + 12, hud.TINY, uiart.TEXT_DIM);
    uiart.divider(card.x + @divTrunc(card.w, 2), card.y + headH(), @divTrunc(card.w, 2) - 30, 170);
}


fn drawEquipment(self: *const Book, body: Box, v: View) void {
    const cols = equipCols(body);
    _ = panel(cols[0], "WHAT HE CARRIES");
    const g = equipGrid(body);
    for (0..NSLOT) |i| {
        const r = g.at(i);
        drawSlot(self, r, @enumFromInt(i), v, self.cur[idx(.equipment)] == i and self.picking == null);
    }
    if (self.picking) |s| drawPicker(self, cols[1], s, v) else drawDerived(cols[1], v, null);
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

    hud.text(slotName(s), x, y - hud.lineH(hud.TINY) - 2, hud.TINY, mathx.withAlpha(uiart.TEXT_DIM, if (sel) 235 else 150));
    uiart.slot(x, sy, w, h, on);
    if (sel) uiart.sheen(rect(x, sy, w, h), 3.4, 22);
    if (pop > 0) rl.drawRectangleLinesEx(rect(x - 1, sy - 1, w + 2, h + 2), 2, mathx.withAlpha(uiart.GILT_BRIGHT, mathx.u8f(200.0 * pop)));

    const lift: f32 = if (sel) 2.0 - self.press * 3.0 else 0;
    drawSlotArt(s, v, fi(x + @divTrunc(w, 2)), fi(sy + @divTrunc(h, 2)) - lift, fi(@min(w, h)) * 0.84);

    if (slotTally(s, v)) |n| hud.tally(fmt("{d}", .{n}), x + w, sy + h, hud.SMALL, if (n > 0) uiart.TEXT_VALUE else uiart.BAD);

    const name = slotFilled(s, v);
    hud.text(name, x + @divTrunc(w - hud.textW(name, hud.SMALL), 2), sy + h + 5, hud.SMALL, if (sel) uiart.HOT else uiart.TEXT_DIM);
}

fn drawSlotArt(s: SlotId, v: View, cx: f32, cy: f32, px: f32) void {
    switch (s) {
        .right => if (v.arm == .bow) itemart.bow(cx, cy, px) else itemart.sword(cx, cy, px),
        .left => if (v.arm != .bow) switch (v.off) {
            .shield => itemart.shield(cx, cy, px),
            .wand => itemart.wand(cx, cy, px),
        },
        .sorcery => if (slotHas(.sorcery, v)) itemart.spell(cx, cy, px, v.fp >= combat.SPELL_FP),
        // The arrow is drawn LONG for its box (a shaft is 0.3 of what it is handed, where a blade is 1.4),
        // so it is given a bigger one — at the slot's own size it is a twig in a cupboard.
        .arrows => itemart.arrow(cx, cy, px * 1.5, v.quiver.count(v.quiver.sel) > 0, v.quiver.sel == .fire),
        .quick => itemart.flask(cx, cy, px, switch (v.flasks.sel) {
            .crimson => .crimson,
            .cerulean => .cerulean,
        }, v.flasks.charges(v.flasks.sel) > 0),
    }
}

/// The right-hand column: what the set is worth. With a candidate, every row gains a second value and an
/// arrow — which is the whole reason the equipment page shows numbers at all.
fn drawDerived(box: Box, v: View, cand: ?Cand) void {
    const inner = panel(box, if (cand == null) "WHAT IT IS WORTH" else "IF HE TAKES IT UP");
    const base = Loadout{ .arm = v.arm, .off = v.off, .ammo = v.quiver.sel, .flask = v.flasks.sel };
    const now = derive(base, v);
    const then = if (cand) |c| derive(withCand(base, c), v) else now;

    // THE ROWS ARE FITTED TO THE PANEL, not the other way round: with a picker open this column is half
    // the height it has to itself, and ten rows at a fixed pitch walked straight off the bottom of it.
    const says = if (cand) |c| candSays(c) else armSays(v.arm, v.off);
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
    const footY = inner.y + inner.h - foot + 22;
    uiart.divider(inner.x + @divTrunc(inner.w, 2), footY - 12, @divTrunc(inner.w, 2) - 10, 120);
    _ = prose(says, inner.x, footY, inner.w, hud.HINT, uiart.TEXT_HINT);
}

fn armSays(a: heromod.Arm, o: heromod.Off) []const u8 {
    if (a == .bow) return "The bow takes both hands, so nothing is on his left arm and nothing can be blocked.";
    return switch (o) {
        .shield => "Sword and shield: he can guard, and a guard is worth more than any number on this page.",
        .wand => "Sword and wand. He casts with the hand that used to block, and pays in Focus instead of stamina.",
    };
}

fn candSays(c: Cand) []const u8 {
    return switch (c.act) {
        .arm => |a| switch (a) {
            .sword => "Back to sword and shield, and back to being able to guard.",
            .bow => "Both hands go to the bow, and the shield goes with them.",
        },
        .off => |o| switch (o) {
            .shield => "Boards back on the arm. He can guard again, and the wand goes away with the sorcery.",
            .wand => "The wand takes the shield's hand, so there is no guarding — and L1 casts instead of blocks.",
        },
        .ammo => |a| switch (a) {
            .plain => "A plain shaft. Ten of them, and nothing in these ruins resists the hole one leaves.",
            .fire => "Fire rides on top of the shaft's own damage. Five of them, so pick the target.",
        },
        .flask => |f| switch (f) {
            .crimson => "The red one closes wounds.",
            .cerulean => "The blue one returns focus, and there is nothing yet that spends focus.",
        },
        else => "",
    };
}

fn drawPicker(self: *const Book, col: Box, s: SlotId, v: View) void {
    // The picker takes the TOP of the column and the pricing keeps the rest, so the numbers under a
    // candidate never jump about when the cursor moves.
    var buf: [CAND_MAX]Cand = undefined;
    const cs = candidates(s, v, &buf);
    const top = pickBox(col, cs.len);
    const inner = panel(top, fmt("{s}  >", .{slotName(s)}));
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
    const rest = Box{ .x = col.x, .y = top.y + top.h + GUTTER, .w = col.w, .h = col.h - top.h - GUTTER };
    drawDerived(rest, v, if (self.pick < cs.len) cs[self.pick] else null);
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
    switch (item.use(k)) {
        .none => hud.text("It does nothing you can do here.", inner.x, y, hud.HINT, uiart.TEXT_HINT),
        .regen => |r| {
            hud.text(fmt("Restores {d:.0} HP over {d:.0} seconds.", .{ v.sheet.hp() * r.frac, r.secs }), inner.x, y, hud.SMALL, uiart.GOOD);
            hud.text("A / Enter    Use", inner.x, y + hud.lineH(hud.SMALL) + 6, hud.HINT, mathx.withAlpha(uiart.GILT, 220));
        },
    }
}


fn drawStats(self: *const Book, body: Box, v: View, portrait: ?Portrait) void {
    const cols = statsCols(body);
    drawAttributes(self, cols[0], v);
    drawBody(cols[1], v);
    drawPortrait(self, cols[2], v, portrait);
}

fn drawAttributes(self: *const Book, col: Box, v: View) void {
    const inner = panel(col, fmt("ATTRIBUTES    LEVEL {d}", .{v.sheet.level()}));
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

fn drawPortrait(self: *const Book, col: Box, v: View, portrait: ?Portrait) void {
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

    const caption = fmt("Level {d}    {d} runes    Left / Right turns him", .{ v.sheet.level(), v.runes });
    hud.text(
        caption,
        inner.x + @divTrunc(inner.w - hud.textW(caption, hud.HINT), 2),
        inner.y + inner.h - hud.lineH(hud.HINT),
        hud.HINT,
        uiart.TEXT_HINT,
    );
}


fn testView(bag: *const item.Bag, sheet: *const stats.Sheet, res: *const combat.Resists, flasks: *const combat.Flasks, quiver: *const combat.Quiver, arm: heromod.Arm) View {
    return testViewOff(bag, sheet, res, flasks, quiver, arm, .shield);
}

fn testViewOff(bag: *const item.Bag, sheet: *const stats.Sheet, res: *const combat.Resists, flasks: *const combat.Flasks, quiver: *const combat.Quiver, arm: heromod.Arm, off: heromod.Off) View {
    return .{ .bag = bag, .sheet = sheet, .res = res, .flasks = flasks, .quiver = quiver, .arm = arm, .off = off, .fp = combat.FP_MAX, .runes = 0 };
}

test "the grid walk never leaves the slots, and a ragged last row cannot swallow the cursor" {
    // Five slots in rows of three: down from the last cell of row 0 lands on the ragged row's end.
    try std.testing.expectEqual(@as(usize, 4), grid(2, NSLOT, SLOT_COLS, 0, 1));
    try std.testing.expectEqual(@as(usize, 0), grid(0, NSLOT, SLOT_COLS, -1, 0)); // hard rails, no wrap
    try std.testing.expectEqual(@as(usize, 2), grid(2, NSLOT, SLOT_COLS, 1, 0));
    try std.testing.expectEqual(@as(usize, 1), grid(4, NSLOT, SLOT_COLS, 0, -1));
    for (0..NSLOT) |i| {
        for ([_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |d| {
            try std.testing.expect(grid(i, NSLOT, SLOT_COLS, d[0], d[1]) < NSLOT);
        }
    }
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
    for ([_]SlotId{ .right, .arrows, .quick }) |s| {
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
    const sword = derive(.{ .arm = .sword, .off = .shield, .ammo = .plain, .flask = .crimson }, v);
    const bow = derive(.{ .arm = .bow, .off = .shield, .ammo = .plain, .flask = .crimson }, v);
    try std.testing.expect(worth(sword, .guard) > 0 and worth(bow, .guard) == 0); // the bow's real cost
    try std.testing.expect(worth(sword, .light) > worth(bow, .light)); // …and the sword hits harder up close
    // FIRE SHOWS ONLY ON A FIRE ARROW, and it is a fraction of that shaft's own physical.
    const fire = derive(.{ .arm = .bow, .off = .shield, .ammo = .fire, .flask = .crimson }, v);
    try std.testing.expect(worth(bow, .fire) == 0 and worth(fire, .fire) > 0);
    try std.testing.expectApproxEqAbs(worth(bow, .heavy) * heromod.FIRE_ARROW_FRAC, worth(fire, .fire), 1e-3);
    // The quick-item row follows the flask, and the two draughts do not fill the same bar.
    const cer = derive(.{ .arm = .sword, .off = .shield, .ammo = .plain, .flask = .cerulean }, v);
    try std.testing.expectApproxEqAbs(sheet.hp() * combat.FLASK_HP_FRAC, worth(sword, .quick), 1e-3);
    try std.testing.expectApproxEqAbs(sheet.fp() * combat.FLASK_FP_FRAC, worth(cer, .quick), 1e-3);
    // A ROW MOVES ONLY WHEN THE THING THAT FEEDS IT DOES: behind a sword, choosing the other arrow moves
    // the tally it counts and not one number he swings with.
    const swordFire = derive(.{ .arm = .sword, .off = .shield, .ammo = .fire, .flask = .crimson }, v);
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
    const board = derive(.{ .arm = .sword, .off = .shield, .ammo = .plain, .flask = .crimson }, v);
    const rod = derive(.{ .arm = .sword, .off = .wand, .ammo = .plain, .flask = .crimson }, v);
    // The left hand's price, and it is the SAME row the bow is billed on, because it is the same hand.
    try std.testing.expect(worth(board, .guard) > 0 and worth(rod, .guard) == 0);
    // …and what he got for it. Zero behind a shield, because a spell he cannot cast is not worth a number.
    try std.testing.expect(worth(board, .spell) == 0 and worth(rod, .spell) > 0);
    try std.testing.expect(worth(board, .spell_fp) == 0 and worth(rod, .spell_fp) > 0);
    // A BOW SILENCES IT WHICHEVER WAY THE LEFT SLOT IS SET — both hands are on the string.
    const bowRod = derive(.{ .arm = .bow, .off = .wand, .ammo = .plain, .flask = .crimson }, v);
    try std.testing.expect(worth(bowRod, .spell) == 0 and worth(bowRod, .guard) == 0);
    // …and the swing rows do not move: taking a wand changes nothing about the sword in the other hand.
    for ([_]Der{ .light, .heavy, .poise, .stance, .stam_light, .stam_heavy }) |k| {
        try std.testing.expectEqual(worth(board, k), worth(rod, k));
    }
    // THE TALLY IS CASTS, NOT POINTS — a full pool reads as a countable number in the slot.
    try std.testing.expectEqual(@as(u8, 0), castsLeft(combat.SPELL_FP - 0.01));
    try std.testing.expectEqual(@as(u8, 1), castsLeft(combat.SPELL_FP));
    try std.testing.expect(castsLeft(combat.FP_MAX) >= 4);
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
    var b = Book{ .page = .inventory, .cur = .{ 0, 2, 0 } };
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
