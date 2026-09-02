const std = @import("std");
const combat = @import("combat.zig");
const counter = @import("counter.zig");
const drops = @import("drops.zig");
const item = @import("item.zig");
const liquid = @import("liquid.zig");
const passivetree = @import("passivetree.zig");
const heromod = @import("hero.zig");
const foestat = @import("../foes/foestat.zig");
const ancientpriestmod = @import("../foes/ancientpriest.zig");
const archermod = @import("../foes/archer.zig");
const birchwightmod = @import("../foes/birchwight.zig");
const blinkbatmod = @import("../foes/blinkbat.zig");
const cinderwakemod = @import("../foes/cinderwake.zig");
const delvermod = @import("../foes/delver.zig");
const fenlurkermod = @import("../foes/fenlurker.zig");
const fishmanmod = @import("../foes/fishman.zig");
const frogmod = @import("../foes/frog.zig");
const fungaldeermod = @import("../foes/fungaldeer.zig");
const fungalduomod = @import("../foes/fungalduo.zig");
const hollowmod = @import("../foes/hollow.zig");
const knightmod = @import("../foes/knight.zig");
const koboldmod = @import("../foes/kobold.zig");
const leechflymod = @import("../foes/leechfly.zig");
const necromod = @import("../foes/necro.zig");
const ogremod = @import("../foes/ogre.zig");
const owlbearmod = @import("../foes/owlbear.zig");
const rootedmod = @import("../foes/rooted.zig");
const rotgorgermod = @import("../foes/rotgorger.zig");
const salthuskmod = @import("../foes/salthusk.zig");
const shademod = @import("../foes/shade.zig");
const shroommod = @import("../foes/shroom.zig");
const shroommagemod = @import("../foes/shroommage.zig");
const skitterermod = @import("../foes/skitterer.zig");
const slumberbloommod = @import("../foes/slumberbloom.zig");
const sporegolemmod = @import("../foes/sporegolem.zig");
const warriormod = @import("../foes/warrior.zig");
const wolfmod = @import("../foes/wolf.zig");
const mathx = @import("../core/mathx.zig");
const wf = @import("../world/worldfmt.zig");

/// **A CHOICE, NOT A DIAL** — one `f32` through the table's own `get`/`set`, but an ORDINAL into a named list,
/// and the FILE carries the NAME: an ordinal written against 59 item kinds lands on a different item the day one is added.
pub const Pick = struct {
    n: usize,
    label: *const fn (usize) [:0]const u8,
    key: *const fn (usize) []const u8,

    fn find(self: Pick, token: []const u8) ?usize {
        for (0..self.n) |i| {
            if (std.mem.eql(u8, self.key(i), token)) return i;
        }
        return null;
    }
};

pub const Col = struct {
    name: [:0]const u8,
    hi: f32,
    lo: f32 = 0,
    step: f32 = 1,
    int: bool = false,
    pick: ?Pick = null,
    ratio: bool = false,
    tip: [:0]const u8 = "",
};

pub const Face = enum { none, foe, item };

pub const Table = struct {
    name: [:0]const u8,
    key: [:0]const u8,
    tip: [:0]const u8 = "",
    n: usize,
    cols: []const Col,
    rowName: *const fn (usize) [:0]const u8,
    rowKey: *const fn (usize) []const u8,
    get: *const fn (usize, usize) f32,
    set: *const fn (usize, usize, f32) void,
    face: Face = .none,
    faceOf: ?*const fn (usize) u32 = null,
    has: ?*const fn (usize, usize) bool = null,
    limits: ?*const fn (usize, usize) Col = null,
    codeValue: ?*const fn (usize, usize) f32 = null,
    setRatio: ?*const fn (usize, usize, f32) void = null,
};

pub const Knob = struct {
    name: [:0]const u8,
    key: []const u8,
    p: Ptr,
    hi: f32,
    lo: f32 = 0,
    step: f32 = 1,
    int: bool = false,
    tip: [:0]const u8 = "",
};

pub const Ptr = union(enum) {
    f: *f32,
    u: *u32,
    b: *u8,

    fn read(self: Ptr) f32 {
        return switch (self) {
            .f => |q| q.*,
            .u => |q| @floatFromInt(q.*),
            .b => |q| @floatFromInt(q.*),
        };
    }

    fn write(self: Ptr, v: f32) void {
        switch (self) {
            .f => |q| q.* = v,
            .u => |q| q.* = @intFromFloat(@max(0, @round(v))),
            .b => |q| q.* = @intFromFloat(mathx.clampF(@round(v), 0, 255)),
        }
    }
};

const KNOB_COL = [_]Col{.{ .name = "value", .hi = 1 }};

fn Knobs(comptime bank: []const Knob) type {
    return struct {
        fn name(i: usize) [:0]const u8 {
            return bank[i].name;
        }
        fn key(i: usize) []const u8 {
            return bank[i].key;
        }
        fn get(r: usize, _: usize) f32 {
            return bank[r].p.read();
        }
        fn set(r: usize, _: usize, v: f32) void {
            bank[r].p.write(v);
        }
        fn limit(r: usize, _: usize) Col {
            const k = bank[r];
            return .{ .name = KNOB_COL[0].name, .lo = k.lo, .hi = k.hi, .step = k.step, .int = k.int, .tip = k.tip };
        }
    };
}

const SPELL_COLS = [_]Col{
    .{ .name = "fp", .hi = 60, .step = 1, .tip = "Focus the cast bills" },
    .{ .name = "reach", .hi = 80, .step = 0.5, .tip = "Metres it carries. 0 on the two that have no reach of their own" },
    .{ .name = "dmg", .hi = 200, .step = 1, .tip = "Physical damage on the blow" },
    .{ .name = "poise", .hi = 120, .step = 1, .tip = "What it takes off a body's flinch pool" },
    .{ .name = "stance", .hi = 160, .step = 1, .tip = "What it takes off a guard" },
    .{ .name = "fire", .hi = 120, .step = 0.5 },
    .{ .name = "cold", .hi = 120, .step = 0.5 },
    .{ .name = "lightning", .hi = 120, .step = 0.5 },
    .{ .name = "chaos", .hi = 120, .step = 0.5 },
    .{ .name = "drip", .hi = 200, .step = 1, .tip = "What a held spell pays out over its whole run, for the ladder to price it" },
};

fn spellName(i: usize) [:0]const u8 {
    return combat.SPELLS[i].name;
}

fn spellKey(i: usize) []const u8 {
    return @tagName(combat.SPELLS[i].spell);
}

fn spellGet(r: usize, c: usize) f32 {
    const row = combat.SPELLS[r];
    const blow = row.blow orelse combat.Hit{};
    return switch (c) {
        0 => row.fp,
        1 => row.reach orelse 0,
        2 => blow.dmg,
        3 => blow.poise,
        4 => blow.stance,
        5...8 => blow.elem.v[c - 5],
        else => row.drip,
    };
}

fn spellHas(r: usize, c: usize) bool {
    const row = combat.SPELLS[r];
    return switch (c) {
        0 => true,
        1 => row.reach != null,
        9 => row.blow == null,
        else => row.blow != null,
    };
}

fn spellSet(r: usize, c: usize, v: f32) void {
    const row = &combat.SPELLS[r];
    switch (c) {
        0 => row.fp = v,
        1 => if (row.reach != null) {
            row.reach = v;
        },
        else => {
            if (c == 9) {
                row.drip = v;
                return;
            }
            if (row.blow == null) return;
            switch (c) {
                2 => row.blow.?.dmg = v,
                3 => row.blow.?.poise = v,
                4 => row.blow.?.stance = v,
                else => row.blow.?.elem.v[c - 5] = v,
            }
        },
    }
}

const AIL_COLS = [_]Col{
    .{ .name = "max", .hi = 300, .step = 1, .tip = "The meter's own size — what a full bar is worth in buildup" },
    .{ .name = "decay", .hi = 120, .step = 0.5, .tip = "Meter a second it empties at once nothing is filling it" },
    .{ .name = "delay", .hi = 6, .step = 0.1, .tip = "Seconds after the last dose before it starts emptying" },
    .{ .name = "dur", .hi = 30, .step = 0.2, .tip = "Seconds the proc runs for" },
    .{ .name = "hpFrac", .hi = 1.0, .step = 0.01, .tip = "Share of max HP the whole clock bleeds" },
    .{ .name = "flat", .hi = 300, .step = 1, .tip = "A burst's flat payout, which no armour and no column answers" },
};

fn ailName(i: usize) [:0]const u8 {
    return combat.AILS[i].name;
}

fn ailKey(i: usize) []const u8 {
    return @tagName(combat.AILS[i].ail);
}

fn ailGet(r: usize, c: usize) f32 {
    const row = combat.AILS[r];
    return switch (c) {
        0 => row.max,
        1 => row.decay,
        2 => row.decayDelay,
        3 => row.dur,
        4 => row.hpFrac,
        else => row.flat,
    };
}

fn ailSet(r: usize, c: usize, v: f32) void {
    const row = &combat.AILS[r];
    switch (c) {
        0 => row.max = v,
        1 => row.decay = v,
        2 => row.decayDelay = v,
        3 => row.dur = v,
        4 => row.hpFrac = v,
        else => row.flat = v,
    }
}

fn kindsWhere(comptime want: fn (item.Kind) bool) []const item.Kind {
    comptime {
        var out: [item.NK]item.Kind = undefined;
        var n: usize = 0;
        for (0..item.NK) |i| {
            const k: item.Kind = @enumFromInt(i);
            if (want(k)) {
                out[n] = k;
                n += 1;
            }
        }
        const final = out[0..n].*;
        return &final;
    }
}

fn isArm(k: item.Kind) bool {
    return std.meta.activeTag(item.equipBank(k)) == .arm;
}

fn isPlate(k: item.Kind) bool {
    return std.meta.activeTag(item.equipBank(k)) == .plate;
}

fn isTrinket(k: item.Kind) bool {
    return switch (item.equipBank(k)) {
        .charm, .boon, .bind => true,
        else => false,
    };
}

fn isUsed(k: item.Kind) bool {
    return std.meta.activeTag(item.useBank(k)) != .none;
}

const ARM_ROWS = kindsWhere(isArm);
const PLATE_ROWS = kindsWhere(isPlate);
const TRINKET_ROWS = kindsWhere(isTrinket);
const USE_ROWS = kindsWhere(isUsed);

fn priceGet(k: item.Kind) f32 {
    return @floatFromInt(item.PRICE[@intFromEnum(k)]);
}

fn priceSet(k: item.Kind, v: f32) void {
    item.PRICE[@intFromEnum(k)] = @intFromFloat(@max(0, @round(v)));
}

const PRICE_COL = Col{ .name = "price", .hi = 4000, .step = 10, .int = true, .tip = "What a counter charges. 0 is untradeable" };

/// The getter, the setter and the `has` of each sheet each carried their own literal 5, 7, 8 and 12.
fn priceAt(comptime cols: []const Col) usize {
    comptime {
        if (!std.mem.eql(u8, cols[cols.len - 1].name, PRICE_COL.name))
            @compileError("tune: an item sheet does not end in its price column");
        return cols.len - 1;
    }
}

const ARM_PRICE = priceAt(&ARM_COLS);
const PLATE_PRICE = priceAt(&PLATE_COLS);
const TRINKET_PRICE = priceAt(&TRINKET_COLS);
const USE_PRICE = priceAt(&USE_COLS);

fn elemBlockAt(comptime cols: []const Col, comptime at: usize) void {
    comptime {
        for (std.enums.values(combat.Elem), 0..) |e, i| {
            if (!std.mem.eql(u8, cols[at + i].name, @tagName(e)))
                @compileError("tune: the element block is not at " ++ std.fmt.comptimePrint("{d}", .{at}) ++
                    " in `Elem` order — a spread would be read off the wrong columns");
        }
    }
}

comptime {
    elemBlockAt(&SPELL_COLS, 5);
    elemBlockAt(&BLOW_COLS, 3);
}

const ARM_COLS = [_]Col{
    .{ .name = "dmg", .hi = 4, .step = 0.02, .tip = "Multiplier on the bare stroke's damage — the straight sword is 1 on every dial" },
    .{ .name = "poise", .hi = 4, .step = 0.02, .tip = "Multiplier on what the stroke takes off a body's flinch pool" },
    .{ .name = "dur", .hi = 3, .step = 0.02, .tip = "Multiplier on how long the swing takes" },
    .{ .name = "stam", .hi = 3, .step = 0.02, .tip = "Multiplier on what the swing bills in stamina" },
    .{ .name = "negate", .hi = 2, .step = 0.02, .tip = "Shields only: multiplier on how much a block turns aside" },
    .{ .name = "arc", .hi = 2, .step = 0.02, .tip = "Shields only: multiplier on the compass the guard covers" },
    .{ .name = "walk", .hi = 2, .step = 0.02, .tip = "Shields only: multiplier on how fast he walks with it up" },
    .{ .name = "venom", .hi = 100, .step = 1, .tip = "Poison a landed stroke puts in the body, absolute and out of 100" },
    PRICE_COL,
};

fn armRowName(i: usize) [:0]const u8 {
    return item.displayName(ARM_ROWS[i]);
}

fn armRowKey(i: usize) []const u8 {
    return @tagName(ARM_ROWS[i]);
}

fn armFace(i: usize) u32 {
    return @intFromEnum(ARM_ROWS[i]);
}

fn armOf(k: item.Kind) item.Arm {
    return switch (item.LIVE[@intFromEnum(k)].equip) {
        .arm => |a| a,
        else => item.Arm{ .slot = .hand_sword },
    };
}

fn armGet(r: usize, c: usize) f32 {
    const k = ARM_ROWS[r];
    const a = armOf(k);
    return switch (c) {
        0 => a.dmg,
        1 => a.poise,
        2 => a.dur,
        3 => a.stam,
        4 => a.negate,
        5 => a.arc,
        6 => a.walk,
        7 => a.venom,
        else => priceGet(k),
    };
}

fn armSet(r: usize, c: usize, v: f32) void {
    const k = ARM_ROWS[r];
    if (c == ARM_PRICE) {
        priceSet(k, v);
        return;
    }
    const g = &item.LIVE[@intFromEnum(k)];
    if (std.meta.activeTag(g.equip) != .arm) return;
    switch (c) {
        0 => g.equip.arm.dmg = v,
        1 => g.equip.arm.poise = v,
        2 => g.equip.arm.dur = v,
        3 => g.equip.arm.stam = v,
        4 => g.equip.arm.negate = v,
        5 => g.equip.arm.arc = v,
        6 => g.equip.arm.walk = v,
        else => g.equip.arm.venom = v,
    }
}

fn armHas(r: usize, c: usize) bool {
    const shield = armOf(ARM_ROWS[r]).slot == .hand_shield;
    return switch (c) {
        0, 1, 7 => !shield,
        4, 5, 6 => shield,
        else => true,
    };
}

const PLATE_COLS = [_]Col{
    .{ .name = "armour", .hi = 60, .step = 0.5, .tip = "The `a` in a/(a + 5*dmg). A whole suit is worth 25" },
    .{ .name = "fire", .hi = 75, .step = 1, .tip = "Per cent taken off the fire column" },
    .{ .name = "cold", .hi = 75, .step = 1 },
    .{ .name = "lightning", .hi = 75, .step = 1 },
    .{ .name = "chaos", .hi = 75, .step = 1 },
    .{ .name = "move", .hi = 1.5, .lo = 0.5, .step = 0.01, .tip = "Multiplier on how fast he walks wearing it" },
    .{ .name = "ailrate", .hi = 2, .step = 0.01, .tip = "Multiplier on the ONE meter this piece slows" },
    PRICE_COL,
};

fn plateRowName(i: usize) [:0]const u8 {
    return item.displayName(PLATE_ROWS[i]);
}

fn plateRowKey(i: usize) []const u8 {
    return @tagName(PLATE_ROWS[i]);
}

fn plateFace(i: usize) u32 {
    return @intFromEnum(PLATE_ROWS[i]);
}

fn plateOf(k: item.Kind) item.Plate {
    return switch (item.LIVE[@intFromEnum(k)].equip) {
        .plate => |q| q,
        else => item.Plate{ .slot = .chest },
    };
}

fn plateGet(r: usize, c: usize) f32 {
    const k = PLATE_ROWS[r];
    const q = plateOf(k);
    return switch (c) {
        0 => q.a,
        1 => q.res.fire,
        2 => q.res.cold,
        3 => q.res.lightning,
        4 => q.res.chaos,
        5 => q.move,
        6 => if (q.rate) |rt| rt.k else 0,
        else => priceGet(k),
    };
}

fn plateSet(r: usize, c: usize, v: f32) void {
    const k = PLATE_ROWS[r];
    if (c == PLATE_PRICE) {
        priceSet(k, v);
        return;
    }
    const g = &item.LIVE[@intFromEnum(k)];
    if (std.meta.activeTag(g.equip) != .plate) return;
    switch (c) {
        0 => g.equip.plate.a = v,
        1 => g.equip.plate.res.fire = v,
        2 => g.equip.plate.res.cold = v,
        3 => g.equip.plate.res.lightning = v,
        4 => g.equip.plate.res.chaos = v,
        5 => g.equip.plate.move = v,
        6 => if (g.equip.plate.rate != null) {
            g.equip.plate.rate.?.k = v;
        },
        else => {},
    }
}

fn plateHas(r: usize, c: usize) bool {
    return c != 6 or plateOf(PLATE_ROWS[r]).rate != null;
}

const TRINKET_COLS = [_]Col{
    .{ .name = "leech", .hi = 20, .step = 0.1, .tip = "Health a landed stroke gives back" },
    .{ .name = "hpFrac", .hi = 1, .step = 0.01, .tip = "Share added to the health pool" },
    .{ .name = "spiritFp", .hi = 2, .step = 0.01, .tip = "Multiplier on what calling a spirit bills" },
    .{ .name = "fpFrac", .hi = 1, .step = 0.01, .tip = "Share added to the focus pool" },
    .{ .name = "boon", .hi = 20, .step = 1, .int = true, .tip = "Points of the attribute the boon grants" },
    PRICE_COL,
};

fn trinketRowName(i: usize) [:0]const u8 {
    return item.displayName(TRINKET_ROWS[i]);
}

fn trinketRowKey(i: usize) []const u8 {
    return @tagName(TRINKET_ROWS[i]);
}

fn trinketFace(i: usize) u32 {
    return @intFromEnum(TRINKET_ROWS[i]);
}

fn trinketGet(r: usize, c: usize) f32 {
    const k = TRINKET_ROWS[r];
    if (c == TRINKET_PRICE) return priceGet(k);
    return switch (item.LIVE[@intFromEnum(k)].equip) {
        .charm => |q| switch (c) {
            0 => q.leech,
            1 => q.hpFrac,
            2 => q.spiritFp,
            3 => q.fpFrac,
            else => 0,
        },
        .boon => |q| if (c == 4) @floatFromInt(q.n) else 0,
        else => 0,
    };
}

fn trinketSet(r: usize, c: usize, v: f32) void {
    const k = TRINKET_ROWS[r];
    if (c == TRINKET_PRICE) {
        priceSet(k, v);
        return;
    }
    const g = &item.LIVE[@intFromEnum(k)];
    switch (g.equip) {
        .charm => switch (c) {
            0 => g.equip.charm.leech = v,
            1 => g.equip.charm.hpFrac = v,
            2 => g.equip.charm.spiritFp = v,
            3 => g.equip.charm.fpFrac = v,
            else => {},
        },
        .boon => if (c == 4) {
            g.equip.boon.n = @intFromFloat(mathx.clampF(@round(v), 0, 255));
        },
        else => {},
    }
}

fn trinketHas(r: usize, c: usize) bool {
    if (c == TRINKET_PRICE) return true;
    return switch (item.LIVE[@intFromEnum(TRINKET_ROWS[r])].equip) {
        .charm => c < 4,
        .boon => c == 4,
        else => false,
    };
}

const USE_COLS = [_]Col{
    .{ .name = "dmg", .hi = 200, .step = 1, .tip = "What a thrown one does on impact" },
    .{ .name = "poise", .hi = 120, .step = 1 },
    .{ .name = "fire", .hi = 200, .step = 1 },
    .{ .name = "lightning", .hi = 200, .step = 1 },
    .{ .name = "dose", .hi = 200, .step = 1, .tip = "Meter it puts in whatever it lands on" },
    .{ .name = "ward", .hi = 100, .step = 1, .tip = "Points of resistance the tonic wards for" },
    .{ .name = "secs", .hi = 300, .step = 1, .tip = "Seconds the effect runs" },
    .{ .name = "frac", .hi = 4, .step = 0.01, .tip = "The share this one deals in — of the bar, of the blow, of what is left" },
    .{ .name = "mult", .hi = 6, .step = 0.05, .tip = "What it multiplies while it runs" },
    .{ .name = "n", .hi = 4000, .step = 1, .int = true, .tip = "How many: arrows in a sheaf, souls in a stone" },
    .{ .name = "radius", .hi = 20, .step = 0.1, .tip = "Metres the burst reaches, and 0 where the blow is the shaft's own" },
    .{ .name = "fp", .hi = 100, .step = 1, .tip = "Focus a ring of the bell bills" },
    PRICE_COL,
};

fn useRowName(i: usize) [:0]const u8 {
    return item.displayName(USE_ROWS[i]);
}

fn useRowKey(i: usize) []const u8 {
    return @tagName(USE_ROWS[i]);
}

fn useFace(i: usize) u32 {
    return @intFromEnum(USE_ROWS[i]);
}

fn useGet(r: usize, c: usize) f32 {
    const k = USE_ROWS[r];
    if (c == USE_PRICE) return priceGet(k);
    return switch (item.LIVE[@intFromEnum(k)].use) {
        .none, .purge => 0,
        .arrows => |q| if (c == 9) @floatFromInt(q.n) else 0,
        .regen => |q| switch (c) {
            6 => q.secs,
            7 => q.frac,
            else => 0,
        },
        .lob => |q| switch (c) {
            0 => q.dmg,
            1 => q.poise,
            2 => q.fire,
            3 => q.lightning,
            4 => if (q.dose) |d| d.amt else 0,
            10 => q.r,
            else => 0,
        },
        .ward => |q| switch (c) {
            5 => q.amount,
            6 => q.secs,
            else => 0,
        },
        .wind => |q| if (c == 7) q.share else 0,
        .grease => |q| switch (c) {
            6 => q.secs,
            7 => q.frac,
            else => 0,
        },
        .souls => |q| if (c == 9) @floatFromInt(q.n) else 0,
        .brew => |q| switch (c) {
            6 => q.secs,
            8 => q.mult,
            else => 0,
        },
        .steady => |q| switch (c) {
            6 => q.secs,
            8 => q.mult,
            else => 0,
        },
        .dose => |q| if (c == 4) q.amt else 0,
        .coat => |q| switch (c) {
            4 => q.amt,
            6 => q.secs,
            else => 0,
        },
        .toll => |q| switch (c) {
            4 => q.amt,
            10 => q.r,
            11 => q.fp,
            else => 0,
        },
    };
}

fn useSet(r: usize, c: usize, v: f32) void {
    const k = USE_ROWS[r];
    if (c == USE_PRICE) {
        priceSet(k, v);
        return;
    }
    const g = &item.LIVE[@intFromEnum(k)];
    const whole: u32 = @intFromFloat(@max(0, @round(v)));
    switch (g.use) {
        .none, .purge => {},
        .arrows => if (c == 9) {
            g.use.arrows.n = @intCast(@min(whole, 255));
        },
        .regen => switch (c) {
            6 => g.use.regen.secs = v,
            7 => g.use.regen.frac = v,
            else => {},
        },
        .lob => switch (c) {
            0 => g.use.lob.dmg = v,
            1 => g.use.lob.poise = v,
            2 => g.use.lob.fire = v,
            3 => g.use.lob.lightning = v,
            4 => if (g.use.lob.dose != null) {
                g.use.lob.dose.?.amt = v;
            },
            10 => g.use.lob.r = v,
            else => {},
        },
        .ward => switch (c) {
            5 => g.use.ward.amount = v,
            6 => g.use.ward.secs = v,
            else => {},
        },
        .wind => if (c == 7) {
            g.use.wind.share = v;
        },
        .grease => switch (c) {
            6 => g.use.grease.secs = v,
            7 => g.use.grease.frac = v,
            else => {},
        },
        .souls => if (c == 9) {
            g.use.souls.n = whole;
        },
        .brew => switch (c) {
            6 => g.use.brew.secs = v,
            8 => g.use.brew.mult = v,
            else => {},
        },
        .steady => switch (c) {
            6 => g.use.steady.secs = v,
            8 => g.use.steady.mult = v,
            else => {},
        },
        .dose => if (c == 4) {
            g.use.dose.amt = v;
        },
        .coat => switch (c) {
            4 => g.use.coat.amt = v,
            6 => g.use.coat.secs = v,
            else => {},
        },
        .toll => switch (c) {
            4 => g.use.toll.amt = v,
            10 => g.use.toll.r = v,
            11 => g.use.toll.fp = v,
            else => {},
        },
    }
}

fn useHas(r: usize, c: usize) bool {
    if (c == USE_PRICE) return true;
    return switch (item.LIVE[@intFromEnum(USE_ROWS[r])].use) {
        .none, .purge => false,
        .arrows, .souls => c == 9,
        .regen, .grease => c == 6 or c == 7,
        .lob => |q| switch (c) {
            0, 1, 2, 3, 10 => true,
            4 => q.dose != null,
            else => false,
        },
        .ward => c == 5 or c == 6,
        .wind => c == 7,
        .brew, .steady => c == 6 or c == 8,
        .dose => c == 4,
        .coat => c == 4 or c == 6,
        .toll => c == 4 or c == 10 or c == 11,
    };
}

const NODE_COLS = [_]Col{
    .{ .name = "grant", .hi = 400, .step = 0.05, .tip = "What the node gives. Its own units — a share, a multiplier, a flat pool, or points of an attribute" },
    .{ .name = "rider", .hi = 20, .step = 1, .int = true, .tip = "The stat-up riding it, in points" },
};

fn nodeName(i: usize) [:0]const u8 {
    return passivetree.NODES[i].name;
}

fn nodeKey(i: usize) []const u8 {
    return passivetree.NODES_BANK[i].name;
}

fn grantValue(g: passivetree.Grant) ?f32 {
    return switch (g) {
        .attr => |x| @floatFromInt(x.n),
        .sacrifice => |x| x.dmg,
        .res, .boltCloud => null,
        inline else => |x| if (@TypeOf(x) == f32) x else null,
    };
}

fn nodeGet(r: usize, c: usize) f32 {
    const n = passivetree.NODES[r];
    if (c == 1) return if (n.bump) |b| @floatFromInt(b.n) else 0;
    return grantValue(n.grant) orelse 0;
}

fn nodeSet(r: usize, c: usize, v: f32) void {
    const n = &passivetree.NODES[r];
    if (c == 1) {
        if (n.bump) |*b| b.n = @intFromFloat(mathx.clampF(@round(v), 0, 255));
        return;
    }
    switch (n.grant) {
        .attr => n.grant.attr.n = @intFromFloat(mathx.clampF(@round(v), 0, 255)),
        .sacrifice => n.grant.sacrifice.dmg = v,
        .res, .boltCloud => {},
        inline else => |_, tag| {
            const field = &@field(n.grant, @tagName(tag));
            if (@TypeOf(field.*) == f32) field.* = v;
        },
    }
}

fn nodeHas(r: usize, c: usize) bool {
    const n = passivetree.NODES[r];
    return if (c == 1) n.bump != null else grantValue(n.grant) != null;
}

/// **AN ATTRIBUTE GRANT IS POINTS, AND POINTS ARE WHOLE** — `Grant.attr.n` is a `u8`, so the column's 0.05 step
/// moved nothing at all on those rows: twenty nudges rounded straight back to where they started, and the 400
fn nodeLimit(r: usize, c: usize) Col {
    if (c == 0 and std.meta.activeTag(passivetree.NODES[r].grant) == .attr) {
        return .{ .name = NODE_COLS[0].name, .hi = NODE_COLS[1].hi, .step = 1, .int = true, .tip = NODE_COLS[0].tip };
    }
    return NODE_COLS[c];
}

/// `play/hero.zig` and `play/combat.zig` call the place to retune feel. A creature's pace is NOT here: every
/// foe solves its walk off `hero.WALK_SPEED_BANK` at comptime, so this moves the man and not the field.
const HERO_KNOBS = [_]Knob{
    .{ .name = "walk", .key = "walk", .p = .{ .f = &heromod.WALK_SPEED }, .lo = 0.2, .hi = 12, .step = 0.1, .tip = "Metres a second with the stick eased over" },
    .{ .name = "run", .key = "run", .p = .{ .f = &heromod.RUN_SPEED }, .lo = 0.5, .hi = 16, .step = 0.1, .tip = "Metres a second at a full stick" },
    .{ .name = "sprint", .key = "sprint", .p = .{ .f = &heromod.SPRINT_SPEED }, .lo = 0.5, .hi = 20, .step = 0.1, .tip = "Metres a second holding the sprint" },
    .{ .name = "roll dist", .key = "roll_dist", .p = .{ .f = &heromod.ROLL_DIST }, .lo = 0.5, .hi = 12, .step = 0.1, .tip = "How far one roll carries him" },
    .{ .name = "roll dur", .key = "roll_dur", .p = .{ .f = &heromod.ROLL_DUR }, .lo = 0.2, .hi = 2, .step = 0.02, .tip = "Seconds the whole roll takes" },
    .{ .name = "roll iframes", .key = "roll_iframe", .p = .{ .f = &heromod.ROLL_IFRAME_END }, .lo = 0, .hi = 2, .step = 0.02, .tip = "Seconds into the roll that he stops being untouchable" },
    .{ .name = "tier damage", .key = "tier_flat", .p = .{ .f = &heromod.TIER_FLAT }, .hi = 20, .step = 0.1, .tip = "Flat damage a smithing tier adds" },
    .{ .name = "stam roll", .key = "stam_roll", .p = .{ .f = &combat.STAM_ROLL }, .hi = 80, .step = 0.5 },
    .{ .name = "stam light", .key = "stam_light", .p = .{ .f = &combat.STAM_LIGHT }, .hi = 80, .step = 0.5 },
    .{ .name = "stam heavy", .key = "stam_heavy", .p = .{ .f = &combat.STAM_HEAVY }, .hi = 80, .step = 0.5 },
    .{ .name = "stam shot", .key = "stam_shot", .p = .{ .f = &combat.STAM_SHOT }, .hi = 80, .step = 0.5 },
    .{ .name = "stam aimed", .key = "stam_aimed", .p = .{ .f = &combat.STAM_AIMED }, .hi = 80, .step = 0.5 },
    .{ .name = "stam sprint", .key = "stam_sprint", .p = .{ .f = &combat.STAM_SPRINT }, .hi = 80, .step = 0.5, .tip = "Per second held" },
    .{ .name = "stam parry", .key = "stam_parry", .p = .{ .f = &combat.STAM_PARRY }, .hi = 80, .step = 0.5 },
    .{ .name = "guard negate", .key = "guard_negate", .p = .{ .f = &combat.GUARD_NEGATE }, .hi = 1, .step = 0.01, .tip = "Share of a blow a raised guard turns aside, before the shield's own dial" },
    .{ .name = "guard stam flat", .key = "guard_stam_flat", .p = .{ .f = &combat.GUARD_STAM_FLAT }, .hi = 40, .step = 0.5, .tip = "Stamina a block bills before the damage term" },
    .{ .name = "guard stam per dmg", .key = "guard_stam_dmg", .p = .{ .f = &combat.GUARD_STAM_PER_DMG }, .hi = 5, .step = 0.05 },
    .{ .name = "foe poise per dmg", .key = "foe_poise_dmg", .p = .{ .f = &combat.FOE_POISE_PER_DMG }, .hi = 4, .step = 0.02, .tip = "How much of the damage done to a creature goes into its flinch pool" },
};

const HeroSheet = Knobs(&HERO_KNOBS);

const Blow = struct {
    of: ?wf.FoeKind,
    move: [:0]const u8,
    p: *combat.Hit,
};

const BLOWS = [_]Blow{
    .{ .of = null, .move = "hero light", .p = &heromod.ATK_LIGHT_HIT },
    .{ .of = null, .move = "hero heavy", .p = &heromod.ATK_HEAVY_HIT },
    .{ .of = .toad, .move = "lunge", .p = &frogmod.LUNGE_HIT },
    .{ .of = .archer, .move = "arrow", .p = &archermod.ARROW_HIT },
    .{ .of = .ogre, .move = "slam", .p = &ogremod.SLAM_HIT },
    .{ .of = .ogre, .move = "swipe", .p = &ogremod.SWIPE_HIT },
    .{ .of = .ogre, .move = "drive", .p = &ogremod.DRIVE_HIT },
    .{ .of = .shieldman, .move = "mace", .p = &warriormod.MOVES_SHIELDMAN[0].hit },
    .{ .of = .greatsword, .move = "slam", .p = &warriormod.MOVES_GREATSWORD[0].hit },
    .{ .of = .greatsword, .move = "lunge", .p = &warriormod.MOVES_GREATSWORD[1].hit },
    .{ .of = .greatsword, .move = "sweep", .p = &warriormod.MOVES_GREATSWORD[2].hit },
    .{ .of = .shade, .move = "grasp", .p = &shademod.MOVES[shademod.GRASP].hit },
    .{ .of = .shade, .move = "wisp", .p = &shademod.MOVES[shademod.WISP].hit },
    .{ .of = .leechfly, .move = "stab", .p = &leechflymod.STAB_HIT },
    .{ .of = .rooted, .move = "slam", .p = &rootedmod.MOVES[rootedmod.SLAM].hit },
    .{ .of = .rooted, .move = "sweep", .p = &rootedmod.MOVES[rootedmod.SWEEP].hit },
    .{ .of = .rooted, .move = "hook", .p = &rootedmod.MOVES[rootedmod.HOOK].hit },
    .{ .of = .shroom, .move = "fling", .p = &shroommod.FLING_HIT },
    .{ .of = .bone_knight, .move = "sweep", .p = &knightmod.MOVES[knightmod.SWEEP_I].hit },
    .{ .of = .bone_knight, .move = "overhead", .p = &knightmod.MOVES[knightmod.OVER_I].hit },
    .{ .of = .bone_knight, .move = "thrust", .p = &knightmod.MOVES[knightmod.THRUST_I].hit },
    .{ .of = .bone_knight, .move = "bash", .p = &knightmod.MOVES[knightmod.BASH_I].hit },
    .{ .of = .bone_knight, .move = "sweep two", .p = &knightmod.MOVES[knightmod.SWEEP2_I].hit },
    .{ .of = .bone_knight, .move = "swat", .p = &knightmod.MOVES[knightmod.SWAT_I].hit },
    .{ .of = .delver, .move = "claw", .p = &delvermod.CLAW_HIT },
    .{ .of = .delver, .move = "burst", .p = &delvermod.BURST_HIT },
    .{ .of = .delver, .move = "plough", .p = &delvermod.PLOUGH_HIT },
    .{ .of = .delver, .move = "rake", .p = &delvermod.RAKE_HIT },
    .{ .of = .necromancer, .move = "frost", .p = &necromod.FROST_HIT },
    .{ .of = .fungal_deer, .move = "spore", .p = &fungaldeermod.SPORE_HIT },
    .{ .of = .mushroom_mage, .move = "ember", .p = &shroommagemod.EMBER_HIT },
    .{ .of = .fen_lurker, .move = "lash", .p = &fenlurkermod.LASH_HIT },
    .{ .of = .spore_golem, .move = "slam", .p = &sporegolemmod.SLAM_HIT },
    .{ .of = .spore_golem, .move = "smash", .p = &sporegolemmod.SMASH_HIT },
    .{ .of = .spore_golem, .move = "sac", .p = &sporegolemmod.SAC_HIT },
    .{ .of = .tolling_hollow, .move = "spark", .p = &hollowmod.SPARK_HIT },
    .{ .of = .cinder_wake, .move = "rake", .p = &cinderwakemod.RAKE_HIT },
    .{ .of = .rotgorger, .move = "bite", .p = &rotgorgermod.BITE_HIT },
    .{ .of = .birchwight, .move = "bough", .p = &birchwightmod.BOUGH_HIT },
    .{ .of = .salt_husk, .move = "clout", .p = &salthuskmod.CLOUT_HIT },
    .{ .of = .salt_husk, .move = "shatter", .p = &salthuskmod.SHATTER_HIT },
    .{ .of = .blinkbat, .move = "bite", .p = &blinkbatmod.BITE_HIT },
    .{ .of = .owlbear, .move = "rake", .p = &owlbearmod.MOVES[owlbearmod.RAKE].hit },
    .{ .of = .owlbear, .move = "slam", .p = &owlbearmod.MOVES[owlbearmod.SLAM].hit },
    .{ .of = null, .move = "wolf bite", .p = &wolfmod.BITE_HIT },
};

/// Built once at comptime, because a name is a `[:0]const u8` and a row is drawn every frame.
const BLOW_NAMES = blk: {
    var out: [BLOWS.len][:0]const u8 = undefined;
    for (BLOWS, 0..) |b, i| {
        out[i] = if (b.of) |k| wf.foeName(k) ++ " - " ++ b.move else b.move;
    }
    const final = out;
    break :blk final;
};

const BLOW_KEYS = blk: {
    var out: [BLOWS.len][]const u8 = undefined;
    for (BLOWS, 0..) |b, i| {
        out[i] = if (b.of) |k| @tagName(k) ++ "_" ++ b.move else b.move;
    }
    const final = out;
    break :blk final;
};

const BLOW_COLS = [_]Col{
    .{ .name = "dmg", .hi = 400, .step = 1, .tip = "Physical damage, before armour" },
    .{ .name = "poise", .hi = 300, .step = 1, .tip = "What it takes off the flinch pool" },
    .{ .name = "stance", .hi = 300, .step = 1, .tip = "What it takes off a guard. Zero means the blow is not heavy" },
    .{ .name = "fire", .hi = 300, .step = 1 },
    .{ .name = "cold", .hi = 300, .step = 1 },
    .{ .name = "lightning", .hi = 300, .step = 1 },
    .{ .name = "chaos", .hi = 300, .step = 1 },
    .{ .name = "gore", .hi = 300, .step = 1, .tip = "Damage no armour and no column answers" },
    .{ .name = "launch", .hi = 8, .step = 0.1, .tip = "Metres off the ground it throws him. A LARGE SLAM only" },
};

fn blowName(i: usize) [:0]const u8 {
    return BLOW_NAMES[i];
}

fn blowKey(i: usize) []const u8 {
    return BLOW_KEYS[i];
}

fn blowFace(i: usize) u32 {
    return if (BLOWS[i].of) |k| @intFromEnum(k) else std.math.maxInt(u32);
}

fn blowGet(r: usize, c: usize) f32 {
    const h = BLOWS[r].p;
    return switch (c) {
        0 => h.dmg,
        1 => h.poise,
        2 => h.stance,
        3...6 => h.elem.v[c - 3],
        7 => h.gore,
        else => h.launch,
    };
}

fn blowSet(r: usize, c: usize, v: f32) void {
    const h = BLOWS[r].p;
    switch (c) {
        0 => h.dmg = v,
        1 => h.poise = v,
        2 => h.stance = v,
        3...6 => h.elem.v[c - 3] = v,
        7 => h.gore = v,
        else => h.launch = v,
    }
}

fn foeAggro(k: wf.FoeKind) ?*f32 {
    return switch (k) {
        .toad => &frogmod.AGGRO_R,
        .archer => &archermod.AGGRO_R,
        .ogre => &ogremod.AGGRO_R,
        .berserker, .priest, .slinger => &koboldmod.AGGRO_R,
        .brood_mother, .broodling, .brood_sac => null,
        .shieldman, .greatsword => &warriormod.AGGRO_R,
        .shade, .mourner => &shademod.AGGRO_R,
        .leechfly => &leechflymod.AGGRO_R,
        .rooted => &rootedmod.AGGRO_R,
        .shroom => &shroommod.AGGRO_R,
        .bone_knight => &knightmod.AGGRO_R,
        .delver => &delvermod.AGGRO_R,
        .necromancer => &necromod.AGGRO_R,
        .fungal_deer => &fungaldeermod.AGGRO_R,
        .mushroom_mage => &shroommagemod.AGGRO_R,
        .fen_lurker => &fenlurkermod.AGGRO_R,
        .spore_golem => &sporegolemmod.AGGRO_R,
        .bone_skitterer => &skitterermod.AGGRO_R,
        .ancient_priest => &ancientpriestmod.AGGRO_R,
        .tolling_hollow => &hollowmod.AGGRO_R,
        .slumber_bloom => &slumberbloommod.AGGRO_R,
        .cinder_wake => &cinderwakemod.AGGRO_R,
        .rotgorger => &rotgorgermod.AGGRO_R,
        .birchwight => &birchwightmod.AGGRO_R,
        .salt_husk => &salthuskmod.AGGRO_R,
        .fish_spearman, .fish_netter, .fish_shaman => &fishmanmod.AGGRO_R,
        .blinkbat => &blinkbatmod.AGGRO_R,
        .fungal_swordsman, .fungal_magus => &fungalduomod.AGGRO_R,
        .owlbear => &owlbearmod.AGGRO_R,
    };
}

fn foeSouls(k: wf.FoeKind) ?*u32 {
    return switch (k) {
        .toad => &frogmod.SOULS,
        .archer => &archermod.SOULS,
        .ogre => &ogremod.SOULS,
        .shade, .mourner => &shademod.SOULS,
        .leechfly => &leechflymod.SOULS,
        .rooted => &rootedmod.SOULS,
        .shroom => &shroommod.SOULS,
        .bone_knight => &knightmod.SOULS,
        .delver => &delvermod.SOULS,
        .necromancer => &necromod.SOULS,
        .mushroom_mage => &shroommagemod.SOULS,
        .fen_lurker => &fenlurkermod.SOULS,
        .spore_golem => &sporegolemmod.SOULS,
        .ancient_priest => &ancientpriestmod.SOULS,
        .tolling_hollow => &hollowmod.SOULS,
        .slumber_bloom => &slumberbloommod.SOULS,
        .cinder_wake => &cinderwakemod.SOULS,
        .rotgorger => &rotgorgermod.SOULS,
        .birchwight => &birchwightmod.SOULS,
        .salt_husk => &salthuskmod.SOULS,
        .blinkbat => &blinkbatmod.SOULS,
        .owlbear => &owlbearmod.SOULS,
        .fungal_deer => &fungaldeermod.SOULS,
        .bone_skitterer => &skitterermod.SOULS,
        .fungal_swordsman => &fungalduomod.SW_SOULS,
        .fungal_magus => &fungalduomod.MG_SOULS,
        // **THE FOUR ROLE GROUPS ARE NAMED, NOT LEFT TO AN `else`.** They keep theirs in a comptime role table,
        .berserker, .priest, .slinger => null,
        .brood_mother, .broodling, .brood_sac => null,
        .shieldman, .greatsword => null,
        .fish_spearman, .fish_netter, .fish_shaman => null,
    };
}

/// **THE POOLS ARE ABSOLUTE ON THE SCREEN AND A MULTIPLIER UNDERNEATH** (`foestat`). Typing 200 into a 96 HP
/// creature stores ×2.08, which is what makes the dial survive the creature being re-authored in code: the
/// bench's edit is "twice as tough", not "96 was wrong".
const FOE_COLS = [_]Col{
    .{ .name = "hp", .hi = 8000, .step = 5, .ratio = true, .tip = "The body's health, as the code's own number times the bench's dial" },
    .{ .name = "poise", .hi = 400, .step = 1, .ratio = true, .tip = "What a stroke has to beat to flinch it" },
    .{ .name = "stance", .hi = 600, .step = 1, .ratio = true, .tip = "What has to be broken for a critical" },
    .{ .name = "souls", .hi = 20000, .step = 10, .int = true, .tip = "What the body is worth" },
    .{ .name = "aggro", .hi = 80, .step = 0.5, .tip = "Metres at which it notices you" },
};

fn foeName(i: usize) [:0]const u8 {
    return wf.foeName(@enumFromInt(i));
}

fn foeKey(i: usize) []const u8 {
    return @tagName(@as(wf.FoeKind, @enumFromInt(i)));
}

fn foeFace(i: usize) u32 {
    return @intCast(i);
}

fn foeGet(r: usize, c: usize) f32 {
    const k: wf.FoeKind = @enumFromInt(r);
    const p = foestat.live(k);
    return switch (c) {
        0 => p.hp,
        1 => p.poise,
        2 => p.stance,
        3 => if (foeSouls(k)) |q| @floatFromInt(q.*) else 0,
        else => if (foeAggro(k)) |q| q.* else 0,
    };
}

fn foeSet(r: usize, c: usize, v: f32) void {
    const k: wf.FoeKind = @enumFromInt(r);
    const i = @intFromEnum(k);
    const code = foestat.pools(k);
    switch (c) {
        0 => if (code.hp > 0) {
            foestat.mult[i].hp = v / code.hp;
        },
        1 => if (code.poise > 0) {
            foestat.mult[i].poise = v / code.poise;
        },
        2 => if (code.stance > 0) {
            foestat.mult[i].stance = v / code.stance;
        },
        3 => if (foeSouls(k)) |q| {
            q.* = @intFromFloat(@max(0, @round(v)));
        },
        else => if (foeAggro(k)) |q| {
            q.* = v;
        },
    }
}

fn foeCode(r: usize, c: usize) f32 {
    const p = foestat.pools(@enumFromInt(r));
    return switch (c) {
        0 => p.hp,
        1 => p.poise,
        2 => p.stance,
        else => 0,
    };
}

fn foeRatio(r: usize, c: usize, v: f32) void {
    const m = &foestat.mult[r];
    switch (c) {
        0 => m.hp = v,
        1 => m.poise = v,
        2 => m.stance = v,
        else => {},
    }
}

fn foeHas(r: usize, c: usize) bool {
    const k: wf.FoeKind = @enumFromInt(r);
    return switch (c) {
        0, 1, 2 => foestat.known(k),
        3 => foeSouls(k) != null,
        else => foeAggro(k) != null,
    };
}

const NOTHING: [:0]const u8 = "- nothing -";
const NOTHING_KEY = "-";

fn itemPickLabel(i: usize) [:0]const u8 {
    return if (i == 0) NOTHING else item.displayName(@enumFromInt(i - 1));
}

fn itemPickKey(i: usize) []const u8 {
    return if (i == 0) NOTHING_KEY else item.tag(@enumFromInt(i - 1));
}

const ITEM_PICK = Pick{ .n = item.NK + 1, .label = itemPickLabel, .key = itemPickKey };

pub fn itemOrdinal(k: ?item.Kind) f32 {
    return if (k) |v| @floatFromInt(@intFromEnum(v) + 1) else 0;
}

fn itemAt(v: f32) ?item.Kind {
    const i = @as(usize, @intFromFloat(mathx.clampF(v, 0, @floatFromInt(item.NK))));
    return if (i == 0) null else @enumFromInt(@as(u8, @intCast(i - 1)));
}

const NCOIN = @typeInfo(drops.Coin).@"enum".fields.len;

fn coinPickLabel(i: usize) [:0]const u8 {
    return switch (@as(drops.Coin, @enumFromInt(i))) {
        .none => "no purse",
        .few => "a few coins",
        .purse => "a purse",
        .heavy => "heavy",
        .hoard => "a hoard",
    };
}

fn coinPickKey(i: usize) []const u8 {
    return @tagName(@as(drops.Coin, @enumFromInt(i)));
}

const COIN_PICK = Pick{ .n = NCOIN, .label = coinPickLabel, .key = coinPickKey };

const DROP_COLS = [_]Col{
    .{ .name = "common", .hi = item.NK, .int = true, .pick = ITEM_PICK, .tip = "What this body usually leaves. Pick `- nothing -` and it drops no item at all" },
    .{ .name = "odds", .hi = 1, .step = 0.01, .tip = "How often the body leaves its common item at all" },
    .{ .name = "rare", .hi = item.NK, .int = true, .pick = ITEM_PICK, .tip = "The second, rarer thing on the body. Name one and its chance appears below - at 0 it never drops" },
    .{ .name = "chance", .hi = 0.85, .step = 0.01, .tip = "How often it leaves the rare one. Luck moves this and nothing else" },
    .{ .name = "purse", .hi = NCOIN - 1, .int = true, .pick = COIN_PICK, .tip = "Which coin band the body carries. A separate roll from the item, and luck does not touch it" },
};

fn dropRowName(i: usize) [:0]const u8 {
    return wf.foeName(@enumFromInt(i));
}

fn dropRowKey(i: usize) []const u8 {
    return @tagName(@as(wf.FoeKind, @enumFromInt(i)));
}

fn dropFace(i: usize) u32 {
    return @intCast(i);
}

fn dropGet(r: usize, c: usize) f32 {
    const row = &drops.TABLE[r];
    return switch (c) {
        0 => itemOrdinal(row.common),
        1 => row.odds,
        2 => itemOrdinal(row.rare),
        3 => row.chance,
        else => @floatFromInt(@intFromEnum(row.gold)),
    };
}

fn dropSet(r: usize, c: usize, v: f32) void {
    const row = &drops.TABLE[r];
    switch (c) {
        0 => row.common = itemAt(v),
        1 => row.odds = v,
        2 => row.rare = itemAt(v),
        3 => row.chance = v,
        else => row.gold = @enumFromInt(@as(u8, @intFromFloat(mathx.clampF(v, 0, NCOIN - 1)))),
    }
}

fn dropHas(r: usize, c: usize) bool {
    return switch (c) {
        1 => drops.TABLE[r].common != null,
        3 => drops.TABLE[r].rare != null,
        else => true,
    };
}

const SOAK_ROWS = blk: {
    var out: [wf.Liquid.N]usize = undefined;
    var n: usize = 0;
    for (liquid.SOAK_BANK, 0..) |row, i| {
        if (row != null) {
            out[n] = i;
            n += 1;
        }
    }
    const final = out[0..n].*;
    break :blk final;
};

const SOAK_COLS = [_]Col{
    .{ .name = "build", .hi = 100, .step = 0.1, .tip = "Meter a second standing in it. max/build is the seconds to break" },
    .{ .name = "dpsFrac", .hi = 0.5, .step = 0.005, .tip = "Share of max HP a second on top of the meter" },
};

fn soakRowName(i: usize) [:0]const u8 {
    return @as(wf.Liquid, @enumFromInt(SOAK_ROWS[i])).label();
}

fn soakRowKey(i: usize) []const u8 {
    return @tagName(@as(wf.Liquid, @enumFromInt(SOAK_ROWS[i])));
}

fn soakGet(r: usize, c: usize) f32 {
    const row = liquid.SOAK[SOAK_ROWS[r]] orelse return 0;
    return if (c == 0) row.build else row.dpsFrac;
}

fn soakSet(r: usize, c: usize, v: f32) void {
    const slot = &liquid.SOAK[SOAK_ROWS[r]];
    if (slot.* == null) return;
    if (c == 0) slot.*.?.build = v else slot.*.?.dpsFrac = v;
}

const TRADE_KNOBS = [_]Knob{
    .{ .name = "stone base", .key = "stone_base", .p = .{ .u = &counter.STONE_BASE }, .lo = 1, .hi = 20, .int = true, .tip = "Stones for the first tier" },
    .{ .name = "stone per tier", .key = "stone_per", .p = .{ .u = &counter.STONE_PER }, .hi = 20, .int = true, .tip = "Halved into the step, so the early tiers are one stone apiece" },
    .{ .name = "coin base", .key = "coin_base", .p = .{ .u = &counter.COIN_BASE }, .lo = 1, .hi = 4000, .step = 5, .int = true, .tip = "Coin for the first tier" },
    .{ .name = "coin per tier", .key = "coin_per", .p = .{ .u = &counter.COIN_PER }, .hi = 4000, .step = 5, .int = true, .tip = "Coin added to every tier after it" },
    .{ .name = "sell share", .key = "sell_share", .p = .{ .f = &item.SELL_SHARE }, .hi = 1, .step = 0.01, .tip = "What a counter pays for what you sell it, as a share of the shelf price" },
};

const TradeSheet = Knobs(&TRADE_KNOBS);

pub const TABLES = [_]Table{
    .{
        .name = "Spells",
        .key = "spell",
        .tip = "The rod's nine. The FP column is the ladder every other number is priced against",
        .n = combat.SPELLS_BANK.len,
        .cols = &SPELL_COLS,
        .rowName = spellName,
        .rowKey = spellKey,
        .get = spellGet,
        .set = spellSet,
        .has = spellHas,
    },
    .{
        .name = "Ailments",
        .key = "ail",
        .tip = "One row per meter: how big it is, how fast it empties, and what filling it costs",
        .n = combat.AILS_BANK.len,
        .cols = &AIL_COLS,
        .rowName = ailName,
        .rowKey = ailKey,
        .get = ailGet,
        .set = ailSet,
    },
    .{
        .name = "Armaments",
        .key = "arm",
        .tip = "Every dial is a multiple of the bare stroke — the straight sword is 1 on all of them",
        .n = ARM_ROWS.len,
        .cols = &ARM_COLS,
        .rowName = armRowName,
        .rowKey = armRowKey,
        .get = armGet,
        .set = armSet,
        .face = .item,
        .faceOf = armFace,
        .has = armHas,
    },
    .{
        .name = "Armour",
        .key = "plate",
        .tip = "The armour value, the four columns, the pace and the one meter a piece slows",
        .n = PLATE_ROWS.len,
        .cols = &PLATE_COLS,
        .rowName = plateRowName,
        .rowKey = plateRowKey,
        .get = plateGet,
        .set = plateSet,
        .face = .item,
        .faceOf = plateFace,
        .has = plateHas,
    },
    .{
        .name = "Trinkets",
        .key = "trinket",
        .tip = "Rings, charms and the neck — what they give and what they cost",
        .n = TRINKET_ROWS.len,
        .cols = &TRINKET_COLS,
        .rowName = trinketRowName,
        .rowKey = trinketRowKey,
        .get = trinketGet,
        .set = trinketSet,
        .face = .item,
        .faceOf = trinketFace,
        .has = trinketHas,
    },
    .{
        .name = "Bag",
        .key = "use",
        .tip = "Everything the bag spends. Each row shows only the dials its own payload has",
        .n = USE_ROWS.len,
        .cols = &USE_COLS,
        .rowName = useRowName,
        .rowKey = useRowKey,
        .get = useGet,
        .set = useSet,
        .face = .item,
        .faceOf = useFace,
        .has = useHas,
    },
    .{
        .name = "Foes",
        .key = "foe",
        .tip = "What a creature is made of: its pools, its worth, and the ring it notices you at",
        .n = foestat.N,
        .cols = &FOE_COLS,
        .rowName = foeName,
        .rowKey = foeKey,
        .get = foeGet,
        .set = foeSet,
        .face = .foe,
        .faceOf = foeFace,
        .has = foeHas,
        .codeValue = foeCode,
        .setRatio = foeRatio,
    },
    .{
        .name = "Hero",
        .key = "hero",
        .tip = "The man himself: his pace, his roll, what a swing bills and what a guard turns aside",
        .n = HERO_KNOBS.len,
        .cols = &KNOB_COL,
        .rowName = HeroSheet.name,
        .rowKey = HeroSheet.key,
        .get = HeroSheet.get,
        .set = HeroSheet.set,
        .limits = HeroSheet.limit,
    },
    .{
        .name = "Blows",
        .key = "blow",
        .tip = "Every named stroke in the game, and what it is worth",
        .n = BLOWS.len,
        .cols = &BLOW_COLS,
        .rowName = blowName,
        .rowKey = blowKey,
        .get = blowGet,
        .set = blowSet,
        .face = .foe,
        .faceOf = blowFace,
    },
    .{
        .name = "Passives",
        .key = "node",
        .tip = "The wheel, one row per node: what it grants and what rides it",
        .n = passivetree.N,
        .cols = &NODE_COLS,
        .rowName = nodeName,
        .rowKey = nodeKey,
        .get = nodeGet,
        .set = nodeSet,
        .has = nodeHas,
        .limits = nodeLimit,
    },
    .{
        .name = "Drops",
        .key = "drop",
        .tip = "How often a body leaves what it carries. One row per creature",
        .n = drops.BANK.len,
        .cols = &DROP_COLS,
        .rowName = dropRowName,
        .rowKey = dropRowKey,
        .get = dropGet,
        .set = dropSet,
        .face = .foe,
        .faceOf = dropFace,
        .has = dropHas,
    },
    .{
        .name = "Liquids",
        .key = "soak",
        .tip = "What standing in a painted pool costs a body",
        .n = SOAK_ROWS.len,
        .cols = &SOAK_COLS,
        .rowName = soakRowName,
        .rowKey = soakRowKey,
        .get = soakGet,
        .set = soakSet,
    },
    .{
        .name = "Trade",
        .key = "trade",
        .tip = "The smith's ladder and what a shop pays for what you sell it",
        .n = TRADE_KNOBS.len,
        .cols = &KNOB_COL,
        .rowName = TradeSheet.name,
        .rowKey = TradeSheet.key,
        .get = TradeSheet.get,
        .set = TradeSheet.set,
        .limits = TradeSheet.limit,
    },
};

pub const NT = TABLES.len;

/// Where each table's cells start in `base`. Comptime, so a cell is one add away and nothing walks the list.
const OFF = blk: {
    var out: [NT + 1]usize = undefined;
    var at: usize = 0;
    for (TABLES, 0..) |t, i| {
        out[i] = at;
        at += t.n * t.cols.len;
    }
    out[NT] = at;
    break :blk out;
};

pub const NCELL = OFF[NT];

var base: [NCELL]f32 = [_]f32{0} ** NCELL;
var armed = false;

fn cell(t: usize, r: usize, c: usize) usize {
    return OFF[t] + r * TABLES[t].cols.len + c;
}

pub fn init() void {
    inline for (TABLES, 0..) |tb, ti| {
        for (0..tb.n) |r| {
            for (0..tb.cols.len) |c| base[cell(ti, r, c)] = tb.get(r, c);
        }
    }
    armed = true;
}

pub fn table(t: usize) Table {
    return TABLES[t];
}

pub fn tableIndex(key: []const u8) ?usize {
    for (TABLES, 0..) |tb, i| {
        if (std.mem.eql(u8, tb.key, key)) return i;
    }
    return null;
}

pub fn colIndex(t: usize, name: []const u8) ?usize {
    for (TABLES[t].cols, 0..) |col, i| {
        if (std.mem.eql(u8, col.name, name)) return i;
    }
    return null;
}

pub fn value(t: usize, r: usize, c: usize) f32 {
    return TABLES[t].get(r, c);
}

pub fn baseValue(t: usize, r: usize, c: usize) f32 {
    if (TABLES[t].cols[c].ratio) {
        if (TABLES[t].codeValue) |f| return f(r, c);
    }
    return base[cell(t, r, c)];
}

pub fn colSpec(t: usize, r: usize, c: usize) Col {
    if (TABLES[t].limits) |f| return f(r, c);
    return TABLES[t].cols[c];
}

pub fn shows(t: usize, r: usize, c: usize) bool {
    if (TABLES[t].has) |f| return f(r, c);
    return true;
}

pub fn setValue(t: usize, r: usize, c: usize, v: f32) void {
    const col = colSpec(t, r, c);
    var k = mathx.clampF(v, col.lo, col.hi);
    if (col.int) k = @round(k);
    TABLES[t].set(r, c, k);
}

pub fn edited(t: usize, r: usize, c: usize) bool {
    return value(t, r, c) != baseValue(t, r, c);
}

pub fn rowEdited(t: usize, r: usize) bool {
    for (0..TABLES[t].cols.len) |c| {
        if (edited(t, r, c)) return true;
    }
    return false;
}

pub fn tableEdited(t: usize) bool {
    for (0..TABLES[t].n) |r| {
        if (rowEdited(t, r)) return true;
    }
    return false;
}

pub fn anyEdited() bool {
    for (0..NT) |t| {
        if (tableEdited(t)) return true;
    }
    return false;
}

pub fn revertRow(t: usize, r: usize) void {
    for (0..TABLES[t].cols.len) |c| TABLES[t].set(r, c, baseValue(t, r, c));
}

pub fn revertTable(t: usize) void {
    for (0..TABLES[t].n) |r| revertRow(t, r);
}

pub fn revertAll() void {
    for (0..NT) |t| revertTable(t);
}

pub const PATH = "tuning.cfg";

fn writeToken(w: anytype, s: []const u8) !void {
    for (s) |ch| {
        try w.writeByte(switch (ch) {
            ' ' => '_',
            '\'', '"' => continue,
            else => ch,
        });
    }
}

fn tokenEql(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        const x = a[i];
        const y = b[j];
        if (x == '\'' or x == '"') {
            i += 1;
            continue;
        }
        if (y == '\'' or y == '"') {
            j += 1;
            continue;
        }
        const xa: u8 = if (x == ' ') '_' else x;
        const ya: u8 = if (y == ' ') '_' else y;
        if (xa != ya) return false;
        i += 1;
        j += 1;
    }
    return i == a.len and j == b.len;
}

pub fn writeDiff(w: anytype) !void {
    for (TABLES, 0..) |tb, ti| {
        for (0..tb.n) |r| {
            if (!rowEdited(ti, r)) continue;
            for (0..tb.cols.len) |c| {
                if (!edited(ti, r, c)) continue;
                var out = value(ti, r, c);
                if (tb.cols[c].ratio) {
                    const code = baseValue(ti, r, c);
                    if (code <= 0) continue;
                    out /= code;
                }
                try w.print("{s}.", .{tb.key});
                try writeToken(w, tb.rowKey(r));
                if (tb.cols[c].pick) |p| {
                    const at = @as(usize, @intFromFloat(mathx.clampF(out, 0, @floatFromInt(p.n - 1))));
                    try w.print(".{s} {s}\n", .{ tb.cols[c].name, p.key(at) });
                } else {
                    try w.print(".{s} {d:.4}\n", .{ tb.cols[c].name, out });
                }
            }
        }
    }
}

const TMP = PATH ++ ".tmp";

pub fn save() void {
    if (writeTmp()) {
        std.fs.cwd().rename(TMP, PATH) catch {
            std.fs.cwd().deleteFile(TMP) catch {};
        };
        return;
    }
    std.fs.cwd().deleteFile(TMP) catch {};
}

fn writeTmp() bool {
    const f = std.fs.cwd().createFile(TMP, .{}) catch return false;
    defer f.close();
    var bw = std.io.bufferedWriter(f.writer());
    writeDiff(bw.writer()) catch return false;
    bw.flush() catch return false;
    return true;
}

pub const LOAD_CAP: usize = NCELL * 72 + 64;

pub fn load() void {
    if (!armed) init();
    var buf: [LOAD_CAP]u8 = undefined;
    const f = std.fs.cwd().openFile(PATH, .{}) catch return;
    defer f.close();
    const n = f.readAll(&buf) catch return;
    if (n == buf.len) return;
    var lines = std.mem.tokenizeAny(u8, buf[0..n], "\r\n");
    while (lines.next()) |line| {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const path = it.next() orelse continue;
        const tok = it.next() orelse continue;
        var parts = std.mem.tokenizeScalar(u8, path, '.');
        const tkey = parts.next() orelse continue;
        const rkey = parts.next() orelse continue;
        const ckey = parts.next() orelse continue;
        applyText(tkey, rkey, ckey, tok);
    }
}

/// inside the column, so a hand-edited `hp 1e9` was the one door in with no bound on it at all — and `load`
/// runs before any body exists, so the code value is usually 0 and there is no absolute to clamp through.
/// Bounded by the column's own span in that case, which at least refuses a NaN, an infinity and a negative.
fn ratioIn(t: usize, r: usize, c: usize, v: f32) f32 {
    const col = colSpec(t, r, c);
    const code = baseValue(t, r, c);
    if (code > 0) return mathx.clampF(v * code, col.lo, col.hi) / code;
    return if (std.math.isNan(v)) 0 else mathx.clampF(v, 0, col.hi);
}

fn find(tkey: []const u8, rkey: []const u8, ckey: []const u8) ?[3]usize {
    for (TABLES, 0..) |tb, ti| {
        if (!std.mem.eql(u8, tkey, tb.key)) continue;
        for (0..tb.n) |r| {
            if (!tokenEql(tb.rowKey(r), rkey)) continue;
            for (tb.cols, 0..) |col, c| {
                if (std.mem.eql(u8, ckey, col.name)) return .{ ti, r, c };
            }
            return null;
        }
        return null;
    }
    return null;
}

fn land(t: usize, r: usize, c: usize, v: f32) void {
    if (TABLES[t].cols[c].ratio) {
        if (TABLES[t].setRatio) |f| f(r, c, ratioIn(t, r, c, v));
        return;
    }
    setValue(t, r, c, v);
}

fn apply(tkey: []const u8, rkey: []const u8, ckey: []const u8, v: f32) void {
    const at = find(tkey, rkey, ckey) orelse return;
    land(at[0], at[1], at[2], v);
}

fn applyText(tkey: []const u8, rkey: []const u8, ckey: []const u8, tok: []const u8) void {
    const at = find(tkey, rkey, ckey) orelse return;
    if (TABLES[at[0]].cols[at[2]].pick) |p| {
        const i = p.find(tok) orelse return;
        land(at[0], at[1], at[2], @floatFromInt(i));
        return;
    }
    land(at[0], at[1], at[2], std.fmt.parseFloat(f32, tok) catch return);
}

test "the bench reads every cell back off the code, and a revert is exact" {
    init();
    for (TABLES, 0..) |tb, ti| {
        try std.testing.expect(tb.n > 0);
        try std.testing.expect(tb.cols.len > 0);
        for (0..tb.n) |r| {
            try std.testing.expect(tb.rowName(r).len > 0);
            try std.testing.expect(tb.rowKey(r).len > 0);
            for (0..tb.cols.len) |c| try std.testing.expect(!edited(ti, r, c));
        }
    }
    try std.testing.expect(!anyEdited());
}

test "a cell edits, clamps to its own column and comes back on a revert" {
    init();
    defer revertAll();
    const t: usize = 0;
    const was = value(t, 0, 0);
    setValue(t, 0, 0, was + 3);
    try std.testing.expectEqual(was + 3, value(t, 0, 0));
    try std.testing.expect(edited(t, 0, 0) and rowEdited(t, 0) and anyEdited());
    setValue(t, 0, 0, 1e9);
    try std.testing.expectEqual(TABLES[t].cols[0].hi, value(t, 0, 0));
    revertRow(t, 0);
    try std.testing.expectEqual(was, value(t, 0, 0));
    try std.testing.expect(!anyEdited());
}

test "a table key, a row key and a column name are unique, or a tuning file lands on the wrong number" {
    inline for (TABLES, 0..) |tb, ti| {
        inline for (TABLES, 0..) |other, oi| {
            if (ti != oi) try std.testing.expect(!std.mem.eql(u8, tb.key, other.key));
        }
        for (0..tb.n) |r| {
            for (0..tb.n) |q| {
                if (r != q) try std.testing.expect(!tokenEql(tb.rowKey(r), tb.rowKey(q)));
            }
        }
        for (tb.cols, 0..) |col, c| {
            for (tb.cols, 0..) |o, k| {
                if (c != k) try std.testing.expect(!std.mem.eql(u8, col.name, o.name));
            }
        }
    }
}

test "an edited cell writes one line, and reading it back puts the number where it was" {
    init();
    defer revertAll();
    setValue(0, 1, 0, value(0, 1, 0) + 2);
    const want = value(0, 1, 0);
    var buf: [256]u8 = undefined;
    var st = std.io.fixedBufferStream(&buf);
    try writeDiff(st.writer());
    revertAll();
    try std.testing.expect(!anyEdited());

    var lines = std.mem.tokenizeAny(u8, st.getWritten(), "\r\n");
    const line = lines.next().?;
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    var parts = std.mem.tokenizeScalar(u8, it.next().?, '.');
    const v = std.fmt.parseFloat(f32, it.next().?) catch unreachable;
    apply(parts.next().?, parts.next().?, parts.next().?, v);
    try std.testing.expectApproxEqAbs(want, value(0, 1, 0), 1e-3);
}

test "a pool is typed in absolute and kept as a ratio, so a re-authored creature stays as tough as you made it" {
    init();
    defer revertAll();
    const foes = blk: {
        for (TABLES, 0..) |tb, i| {
            if (std.mem.eql(u8, tb.key, "foe")) break :blk i;
        }
        unreachable;
    };
    const deer: usize = @intFromEnum(wf.FoeKind.fungal_deer);
    foestat.mult[deer] = .{};

    var vit = combat.Vitals.initFoe(96, 14, 44);
    foestat.arm(&vit, .fungal_deer);
    try std.testing.expect(shows(foes, deer, 0));
    try std.testing.expectEqual(@as(f32, 96), value(foes, deer, 0));
    try std.testing.expect(!edited(foes, deer, 0));

    setValue(foes, deer, 0, 192);
    try std.testing.expectEqual(@as(f32, 192), value(foes, deer, 0));
    try std.testing.expect(edited(foes, deer, 0));
    // …and what lands in the file is the RATIO, which is what survives the 96 being re-authored.
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), foestat.mult[deer].hp, 1e-4);

    revertRow(foes, deer);
    try std.testing.expectEqual(@as(f32, 96), value(foes, deer, 0));
    apply("foe", "fungal_deer", "hp", 1.5);
    try std.testing.expectApproxEqAbs(@as(f32, 144), value(foes, deer, 0), 1e-3);
    foestat.mult[deer] = .{};
}

test "a dial writes the field its own getter reads, at its own step, and moves nothing beside it" {
    init();
    defer revertAll();
    var bad: usize = 0;
    for (0..NT) |t| {
        const tb = TABLES[t];
        for (0..tb.n) |r| {
            for (0..tb.cols.len) |c| {
                if (!shows(t, r, c)) continue;
                const col = colSpec(t, r, c);
                const v0 = value(t, r, c);
                var want = if (v0 + col.step <= col.hi) v0 + col.step else v0 - col.step;
                if (col.int) want = @round(want);
                want = mathx.clampF(want, col.lo, col.hi);
                if (want == v0) continue;

                var before: [64]f32 = undefined;
                var n: usize = 0;
                for (0..tb.cols.len) |q| {
                    if (q >= before.len) break;
                    before[q] = value(t, r, q);
                    n = q + 1;
                }

                setValue(t, r, c, want);
                const got = value(t, r, c);
                if (@abs(got - want) > 1e-3 * @max(1, @abs(want))) {
                    std.debug.print("SET/GET MISMATCH {s}.{s}.{s}: set {d} got {d}\n", .{ tb.key, tb.rowKey(r), col.name, want, got });
                    bad += 1;
                }
                for (0..n) |q| {
                    if (q == c) continue;
                    if (value(t, r, q) != before[q]) {
                        std.debug.print("BLEED {s}.{s}: writing {s} moved {s} ({d} -> {d})\n", .{ tb.key, tb.rowKey(r), col.name, tb.cols[q].name, before[q], value(t, r, q) });
                        bad += 1;
                    }
                }
                revertRow(t, r);
            }
        }
    }
    if (bad != 0) {
        std.debug.print("bench: {d} bad cells\n", .{bad});
        return error.BenchCellMismatch;
    }
}

test "WHAT A BODY LEAVES IS A CHOICE ON THE SHEET, AND THE FILE CARRIES ITS NAME" {
    init();
    defer revertAll();
    const dt = tableIndex("drop").?;
    const cCommon = colIndex(dt, "common").?;
    const cRare = colIndex(dt, "rare").?;
    const cChance = colIndex(dt, "chance").?;
    const cPurse = colIndex(dt, "purse").?;

    const toad: usize = @intFromEnum(wf.FoeKind.toad);
    try std.testing.expectEqual(item.Kind.bloodgrass, drops.TABLE[toad].common.?);
    try std.testing.expect(!edited(dt, toad, cCommon));
    setValue(dt, toad, cCommon, itemOrdinal(.smithing_stone));
    try std.testing.expectEqual(item.Kind.smithing_stone, drops.TABLE[toad].common.?);
    try std.testing.expect(edited(dt, toad, cCommon));

    // **NOTHING IS A VALUE YOU CAN LAND ON**, not a missing one: the sac leaves nothing and its cell reads 0.
    const sac: usize = @intFromEnum(wf.FoeKind.brood_sac);
    try std.testing.expectEqual(@as(f32, 0), value(dt, sac, cCommon));
    try std.testing.expectEqual(@as(?item.Kind, null), drops.TABLE[sac].rare);
    try std.testing.expect(!shows(dt, sac, cChance));
    setValue(dt, sac, cRare, itemOrdinal(.golden_seed));
    try std.testing.expectEqual(item.Kind.golden_seed, drops.TABLE[sac].rare.?);
    try std.testing.expect(shows(dt, sac, cChance));
    try std.testing.expectEqual(@as(f32, 0), value(dt, sac, cChance));
    setValue(dt, sac, cChance, 0.25);
    setValue(dt, sac, cPurse, @floatFromInt(@intFromEnum(drops.Coin.heavy)));
    try std.testing.expectEqual(drops.Coin.heavy, drops.TABLE[sac].gold);

    var buf: [4096]u8 = undefined;
    var st = std.io.fixedBufferStream(&buf);
    try writeDiff(st.writer());
    const text = st.getWritten();
    std.debug.print("\n  drop sheet writes:\n{s}", .{text});
    try std.testing.expect(std.mem.indexOf(u8, text, "drop.toad.common smithing_stone") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "drop.brood_sac.rare golden_seed") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "drop.brood_sac.purse heavy") != null);

    revertAll();
    try std.testing.expectEqual(item.Kind.bloodgrass, drops.TABLE[toad].common.?);
    try std.testing.expectEqual(@as(?item.Kind, null), drops.TABLE[sac].rare);
    try std.testing.expectEqual(drops.Coin.none, drops.TABLE[sac].gold);
    try std.testing.expect(!anyEdited());

    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        var parts = std.mem.tokenizeScalar(u8, it.next().?, '.');
        applyText(parts.next().?, parts.next().?, parts.next().?, it.next().?);
    }
    try std.testing.expectEqual(item.Kind.smithing_stone, drops.TABLE[toad].common.?);
    try std.testing.expectEqual(item.Kind.golden_seed, drops.TABLE[sac].rare.?);
    try std.testing.expectEqual(drops.Coin.heavy, drops.TABLE[sac].gold);

    applyText("drop", "toad", "common", "a_thing_that_was_cut");
    try std.testing.expectEqual(item.Kind.smithing_stone, drops.TABLE[toad].common.?);
}

test "EVERY PICK COLUMN'S KEYS ARE UNIQUE AND ITS CLAMP REACHES ITS WHOLE LIST" {
    var picks: usize = 0;
    inline for (TABLES, 0..) |tb, ti| {
        for (tb.cols, 0..) |col, ci| {
            const p = col.pick orelse continue;
            picks += 1;
            try std.testing.expectEqual(@as(f32, @floatFromInt(p.n - 1)), col.hi);
            try std.testing.expectEqual(@as(f32, 0), col.lo);
            try std.testing.expect(col.int);
            for (0..p.n) |i| {
                try std.testing.expect(p.key(i).len > 0);
                for (p.key(i)) |ch| try std.testing.expect(ch != ' ');
                for (0..p.n) |j| {
                    if (i != j) try std.testing.expect(!std.mem.eql(u8, p.key(i), p.key(j)));
                }
                try std.testing.expectEqual(@as(?usize, i), p.find(p.key(i)));
            }
            std.debug.print("  pick {s}.{s}: {d} choices, \"{s}\" .. \"{s}\"\n", .{
                tb.key, col.name, p.n, p.key(0), p.key(p.n - 1),
            });
            _ = ti;
            _ = ci;
        }
    }
    try std.testing.expect(picks > 0);
}
