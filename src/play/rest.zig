const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const props = @import("../props/props.zig");
const sfx = @import("../core/audio.zig");
const hud = @import("../ui/hud.zig");
const uiart = @import("../ui/uiart.zig");
const ptree = @import("passivetree.zig");
const daynight = @import("../world/daynight.zig");
const combat = @import("combat.zig");
const item = @import("item.zig");
const itemart = @import("../ui/itemart.zig");

const v3 = mathx.v3;


pub const CAP: usize = 32;

pub const REACH: f32 = 3.2;

const FADE_DOWN: f32 = 0.75;
const FADE_UP: f32 = 1.10;
const FADE_OUT: f32 = 0.60;
const FADE_RETURN: f32 = 0.90;
const BED_IN: f32 = 2.6;
const BED_OUT: f32 = 0.55;
const SEAT_TURN: f32 = 0.20;

// THE BONFIRE IS A SCREEN NOW, not a pause with a fade. He sits on the RIGHT of the frame and the fire's own
// menu is a list down the LEFT — the shape every bonfire in the genre has. GETTING UP IS A ROW ON THAT LIST
// **OR BACK** (owner's call), and never "any button": what the old any-button rule guaranteed was a press
// that both chose a row and stood him up, and Back is the one button that can never also pick.

pub const Row = enum {
    level,
    memorize,
    /// **WAIT OUT THE CLOCK.** A bonfire is where you stop, so it is the one place that may spend HOURS: the
    /// world's light is a thing you can now be in the wrong half of, and a fire you cannot wait at is a night
    /// you have to walk off. Two, and they are the two hours worth naming (`daynight.Until`) rather than a
    /// scrub — the fire is not an authoring tool, and "which light do I want to fight in" has two answers.
    untilMorning,
    untilEvening,
    leave,

    pub fn label(r: Row) [:0]const u8 {
        return switch (r) {
            .level => "Level Up",
            .memorize => "Memorize Spells",
            .untilMorning => daynight.Until.morning.label(),
            .untilEvening => daynight.Until.evening.label(),
            .leave => "Leave Bonfire",
        };
    }

    pub fn until(r: Row) ?daynight.Until {
        return switch (r) {
            .level, .memorize, .leave => null,
            .untilMorning => .morning,
            .untilEvening => .evening,
        };
    }
};

pub const NROW = @typeInfo(Row).@"enum".fields.len;

pub const Screen = enum { list, tree, spells };

pub const Pick = union(enum) {
    none,
    take: usize,
    wait: daynight.Until,
    /// A null spell EMPTIES the slot.
    memorize: struct { slot: usize, spell: ?combat.Spell },
    leave,
};

pub const Site = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own — the camp's layout is authored in its local frame
};

pub const Phase = enum {
    off,
    in,
    sit,
    out,
};

pub const Rest = struct {
    list: [CAP]Site = undefined,
    n: usize = 0,
    near: ?usize = null,

    phase: Phase = .off,
    t: f32 = mathx.LONG_AGO,
    site: Site = .{},

    justEntered: bool = false,
    justLeft: bool = false,

    screen: Screen = .list,
    row: usize = 0,
    wheel: ptree.Wheel = .{},

    /// `memPick` null is the slot list; set, the picker is open on that row (`book.picking`/`pick`'s pair).
    memRow: usize = 0,
    memPick: ?usize = null,

    pub fn reset(self: *Rest, sites: []const Site) void {
        self.n = 0;
        self.near = null;
        for (sites) |s| {
            if (self.n >= CAP) break;
            self.list[self.n] = s;
            self.n += 1;
        }
    }

    pub fn active(self: *const Rest) bool {
        return self.phase != .off;
    }
    pub fn scene(self: *const Rest) bool {
        return self.phase == .sit or self.phase == .out;
    }

    pub fn fade(self: *const Rest) f32 {
        return switch (self.phase) {
            .in => mathx.clampF(self.t / FADE_DOWN, 0, 1),
            .sit => 1.0 - mathx.smoothstep(0, FADE_UP, self.t),
            .out => mathx.clampF(self.t / FADE_OUT, 0, 1),
            .off => 1.0 - mathx.smoothstep(0, FADE_RETURN, self.t),
        };
    }

    pub fn bedLevel(self: *const Rest) f32 {
        return switch (self.phase) {
            .in, .off => 0,
            .sit => mathx.smoothstep(0, BED_IN, self.t),
            .out => 1.0 - mathx.smoothstep(0, BED_OUT, self.t),
        };
    }

    pub fn look(self: *Rest, heroPos: rl.Vector3) void {
        if (self.phase != .off or self.fadeRunning()) {
            self.near = null;
            return;
        }
        var near = mathx.Nearest.within(REACH);
        for (self.list[0..self.n], 0..) |*s, i| near.offer(i, s.pos, heroPos);
        self.near = near.best;
    }

    fn fadeRunning(self: *const Rest) bool {
        return self.phase == .off and self.t < FADE_RETURN;
    }

    pub fn begin(self: *Rest) bool {
        if (self.phase != .off or self.fadeRunning()) return false;
        const i = self.near orelse return false;
        self.site = self.list[i];
        self.phase = .in;
        self.t = 0;
        self.near = null;
        self.screen = .list;
        self.row = 0;
        self.memRow = 0;
        self.memPick = null;
        return true;
    }

    pub fn listening(self: *const Rest) bool {
        return self.phase == .sit and self.fade() <= 0.35;
    }

    pub fn leave(self: *Rest) void {
        if (self.phase != .sit) return;
        self.phase = .out;
        self.t = 0;
    }

    pub fn update(self: *Rest, dt: f32) void {
        self.justEntered = false;
        self.justLeft = false;
        // Clamped in `.off` so the idle clock cannot run away over a long session.
        self.t = if (self.phase == .off) @min(self.t + dt, mathx.LONG_AGO) else self.t + dt;
        switch (self.phase) {
            .off => {},
            .in => if (self.t >= FADE_DOWN) {
                self.phase = .sit;
                self.t = 0;
                self.justEntered = true;
                sfx.restFireOn(true);
            },
            .sit => {},
            .out => if (self.t >= FADE_OUT) {
                self.phase = .off;
                self.t = 0;
                self.justLeft = true;
                sfx.restFireOn(false);
            },
        }
        sfx.restFireLevel(self.bedLevel());
    }

    pub fn seat(self: *const Rest) struct { pos: rl.Vector3, facing: f32, axis: f32 } {
        const yaw = mathx.radians(self.site.yaw);
        const c = mathx.cosf(yaw);
        const s = mathx.sinf(yaw);
        const lx: f32 = 1.25;
        const lz: f32 = -1.95;
        const pos = v3(self.site.pos.x + c * lx + s * lz, self.site.pos.y, self.site.pos.z - s * lx + c * lz);
        const axis = mathx.headingXZ(mathx.subV(self.site.pos, pos));
        return .{ .pos = pos, .facing = axis + SEAT_TURN, .axis = axis };
    }
};

pub fn siteFromProp(pos: rl.Vector3, yaw: f32) Site {
    return .{ .pos = pos, .yaw = yaw };
}


/// What the fire is allowed to know (`game.bookView`'s shape): it owns no game state and reaches for nothing.
pub const View = struct {
    tree: *const Tree,
    souls: u32,
    mem: *const combat.Memory,
    bag: *const item.Bag,
};

/// +1 for the EMPTY row: a slot you cannot clear is a slot the player is stuck with.
const MEM_CANDS = combat.SPELLS.len + 1;

fn memCands(v: View, out: *[MEM_CANDS]?combat.Spell) []const ?combat.Spell {
    out[0] = null;
    var n: usize = 1;
    for (combat.SPELLS) |row| {
        // Memorizing never SPENDS the scroll: owned once, racked as often as you like (ER's own).
        if (!combat.carriesSpell(v.bag, row.spell)) continue;
        out[n] = row.spell;
        n += 1;
    }
    return out[0..n];
}

fn memPickRow(self: *const Rest, v: View) ?combat.Spell {
    const at = self.memPick orelse return v.mem.at(self.memRow);
    var buf: [MEM_CANDS]?combat.Spell = undefined;
    const cs = memCands(v, &buf);
    return if (at < cs.len) cs[at] else null;
}

pub fn navigate(self: *Rest, dx: f32, dy: f32) void {
    switch (self.screen) {
        .list => {
            const dv = mathx.signI(dy);
            if (dv == 0) return;
            const n: i32 = NROW;
            const at: i32 = @intCast(self.row);
            const next = @mod(at + dv + n, n);
            if (next == at) return;
            self.row = @intCast(next);
            sfx.play(.menu_move);
        },
        // THE WHEEL IS WALKED BY DIRECTION, never cycled (`ptree.step`'s law).
        .tree => if (self.wheel.move(dx, dy)) sfx.play(.menu_move),
        .spells => {},
    }
}

/// Its own door, not a prong of `navigate`: the walk needs the bag to measure the open list.
pub fn navigateSpells(self: *Rest, dy: f32, v: View) void {
    if (self.screen != .spells) return;
    const dv = mathx.signI(dy);
    if (dv == 0) return;
    const n: i32 = blk: {
        if (self.memPick == null) break :blk @intCast(combat.MEM_SLOTS);
        var buf: [MEM_CANDS]?combat.Spell = undefined;
        break :blk @intCast(memCands(v, &buf).len);
    };
    if (n <= 0) return;
    const at: i32 = @intCast(if (self.memPick) |i| i else self.memRow);
    const next = @mod(at + dv + n, n);
    // A one-row list does not click: a cursor that cannot move may not sound like it did.
    if (next == at) return;
    if (self.memPick != null) self.memPick = @intCast(next) else self.memRow = @intCast(next);
    sfx.play(.menu_move);
}

pub fn zoom(self: *Rest, dv: f32, dt: f32) void {
    if (self.screen == .tree and dv != 0) self.wheel.zoomBy(dv, dt);
}

pub fn pan(self: *Rest, v: rl.Vector2, dt: f32) void {
    if (self.screen == .tree) self.wheel.panBy(v, dt);
}

pub fn confirm(self: *Rest, v: View) Pick {
    switch (self.screen) {
        .list => {
            const r: Row = @enumFromInt(self.row);
            if (r.until()) |u| return .{ .wait = u };
            switch (r) {
                .level => {
                    self.screen = .tree;
                    sfx.play(.menu_pick);
                    return .none;
                },
                .memorize => {
                    self.screen = .spells;
                    self.memRow = 0;
                    self.memPick = null;
                    sfx.play(.menu_pick);
                    return .none;
                },
                .leave => return .leave,
                .untilMorning, .untilEvening => unreachable,
            }
        },
        .tree => {
            const i = self.wheel.cursor;
            if (i >= ptree.N or !v.tree.canTake(i, v.souls)) {
                sfx.play(.menu_back);
                return .none;
            }
            return .{ .take = i };
        },
        .spells => {
            var buf: [MEM_CANDS]?combat.Spell = undefined;
            const cs = memCands(v, &buf);
            if (self.memPick) |at| {
                if (at >= cs.len) {
                    sfx.play(.menu_back);
                    return .none;
                }
                const want = cs[at];
                self.memPick = null;
                sfx.play(.item_get);
                return .{ .memorize = .{ .slot = self.memRow, .spell = want } };
            }
            // Nothing to choose from opens no picker: the panel says so instead.
            if (cs.len <= 1 and v.mem.at(self.memRow) == null) {
                sfx.play(.menu_back);
                return .none;
            }
            self.memPick = pickIndexOf(v, self.memRow);
            sfx.play(.menu_pick);
            return .none;
        },
    }
}

/// COUNTED, never taken as an ordinal (`book.pickIndexOf`'s law): the list holds only carried scrolls.
fn pickIndexOf(v: View, slot: usize) usize {
    var buf: [MEM_CANDS]?combat.Spell = undefined;
    const cs = memCands(v, &buf);
    const has = v.mem.at(slot);
    for (cs, 0..) |c, i| {
        if (c == has) return i;
    }
    return 0;
}

pub fn back(self: *Rest) void {
    if (self.screen == .spells and self.memPick != null) {
        self.memPick = null;
        sfx.play(.menu_back);
        return;
    }
    if (self.screen != .list) {
        self.screen = .list;
        sfx.play(.menu_back);
        return;
    }
    if (self.phase != .sit) return;
    sfx.play(.menu_back);
    self.leave();
}

const Tree = ptree.Tree;

/// Stage a screen for the shot harness (`book.debugShow`'s pattern): a photograph of the wheel zoomed onto
/// a keystone cannot be got by pretending to press buttons at 1/60 s a frame.
pub fn debugShow(self: *Rest, screen: Screen, row: usize, node: usize, mag: f32) void {
    self.screen = screen;
    self.row = @min(row, NROW - 1);
    self.wheel = .{ .cursor = node, .zoom = mag };
}

pub fn debugMemory(self: *Rest, slot: usize, pick: ?usize) void {
    self.screen = .spells;
    self.row = @intFromEnum(Row.memorize);
    self.memRow = @min(slot, combat.MEM_SLOTS - 1);
    self.memPick = pick;
}

pub const PANEL_FRAC: f32 = 0.34;
const PANEL_MIN: i32 = 300;
const PANEL_MAX: i32 = 460;
const MARGIN: i32 = 46;

fn panelW() i32 {
    return mathx.clampI(@intFromFloat(@as(f32, @floatFromInt(rl.getScreenWidth())) * PANEL_FRAC), PANEL_MIN, PANEL_MAX);
}

fn rowH() i32 {
    return hud.lineH(hud.BODY) + 18;
}

pub fn drawScreen(self: *const Rest, v: View) void {
    if (self.phase != .sit) return;
    const a: f32 = 1.0 - self.fade();
    if (a <= 0.02) return;
    switch (self.screen) {
        .list => drawList(self, a),
        .tree => drawTree(self, v.tree, v.souls, a),
        .spells => drawSpells(self, v, a),
    }
}

fn alpha(v: f32, a: f32) u8 {
    return mathx.u8f(v * mathx.clampF(a, 0, 1));
}

fn ink(c: rl.Color, a: f32) rl.Color {
    return mathx.withAlpha(c, alpha(@floatFromInt(c.a), a));
}

const PAD_X: i32 = 24;

fn drawList(self: *const Rest, a: f32) void {
    const w = panelW();
    const sh = rl.getScreenHeight();
    const head = hud.lineH(hud.TITLE) + 40;
    const body = rowH() * @as(i32, NROW);
    const foot: i32 = 26;
    const h = head + body + foot;
    const x = MARGIN;
    const y = @divTrunc(sh - h, 2);

    uiart.seat(x, y, w, h);
    uiart.plate(x, y, w, h, alpha(236.0, a));
    uiart.frame(x, y, w, h, alpha(200.0, a));

    hud.engraved("BONFIRE", x + PAD_X, y + 20, hud.TITLE, ink(uiart.TEXT_TITLE, a));
    uiart.divider(x + @divTrunc(w, 2), y + hud.lineH(hud.TITLE) + 30, @divTrunc(w, 2) - PAD_X, alpha(170.0, a));

    var ry = y + head;
    for (0..NROW) |i| {
        const r: Row = @enumFromInt(i);
        const on = i == self.row;
        if (on) uiart.rowHilite(x + 14, ry - 4, w - 28, rowH() - 8);
        hud.text(r.label(), x + PAD_X + 6, ry, hud.BODY, ink(if (on) uiart.HOT else uiart.TEXT_VALUE, a));
        ry += rowH();
    }
}

/// One frame for both big screens; returns the BODY, which is all either of them draws into.
fn bigScreen(title: [:0]const u8, foot: i32, a: f32) struct { x: i32, y: i32, w: i32, h: i32, headY: i32, right: i32, bottom: i32 } {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const x = MARGIN;
    const y = @max(30, @divTrunc(sh, 16));
    const w = sw - MARGIN * 2;
    const h = sh - y * 2;

    rl.drawRectangle(0, 0, sw, sh, mathx.withAlpha(rl.Color.black, alpha(150.0, a)));
    uiart.seat(x, y, w, h);
    uiart.plate(x, y, w, h, alpha(240.0, a));
    uiart.frame(x, y, w, h, alpha(200.0, a));

    const headY = y + 14;
    hud.engraved(title, x + PAD_X, headY, hud.TITLE, ink(uiart.TEXT_TITLE, a));
    const bodyY = headY + hud.lineH(hud.TITLE) + 12;
    return .{
        .x = x + 22,
        .y = bodyY,
        .w = w - 44,
        .h = y + h - bodyY - foot - 8,
        .headY = headY,
        .right = x + w,
        .bottom = y + h,
    };
}

fn footRow(hints: []const hud.Hint, box: anytype, foot: i32, a: f32) void {
    const hw = hud.hintRowW(hints, hud.HINT);
    hud.hintRowAt(hints, box.x + @divTrunc(box.w - hw, 2), box.bottom - foot + 2, hud.HINT, ink(uiart.TEXT_HINT, a));
}

fn footH() i32 {
    return hud.lineH(hud.HINT) + 20;
}

fn drawTree(self: *const Rest, t: *const Tree, souls: u32, a: f32) void {
    const foot = footH();
    const box = bigScreen("PASSIVES", foot, a);
    ptree.drawPage(t, self.wheel, box.x, box.y, box.w, box.h, true, souls);
    footRow(&[_]hud.Hint{
        .{ .glyph = .{ .bumper = "LS" }, .label = "Walk" },
        .{ .glyph = .{ .bumper = "RS" }, .label = "Pan" },
        .{ .glyph = .{ .dpad = .updown }, .label = "Zoom" },
        .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Take" },
        .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Back" },
    }, box, foot, a);
}

const RACK_CELL: i32 = 84;
const RACK_GAP: i32 = 16;

var scratch: [8][160]u8 = undefined;
var scratchAt: usize = 0;

fn fmt(comptime f: []const u8, args: anytype) [:0]const u8 {
    scratchAt = (scratchAt + 1) % scratch.len;
    return std.fmt.bufPrintZ(&scratch[scratchAt], f, args) catch "?";
}

fn drawSpells(self: *const Rest, v: View, a: f32) void {
    const foot = footH();
    const box = bigScreen("MEMORY", foot, a);
    const tally = fmt("{d} of {d} slots", .{ v.mem.filled(), combat.MEM_SLOTS });
    hud.text(tally, box.right - PAD_X - hud.textW(tally, hud.BODY), box.headY + 8, hud.BODY, ink(uiart.TEXT_VALUE, a));

    const gut: i32 = 28;
    const colW = @divTrunc(box.w - gut, 2);
    drawRack(self, v, box.x, box.y, colW, a);
    drawRead(self, v, box.x + colW + gut, box.y, box.w - colW - gut, a);

    const picking = self.memPick != null;
    footRow(&[_]hud.Hint{
        .{ .glyph = .{ .dpad = .updown }, .label = if (picking) "Choose" else "Slot" },
        .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = if (picking) "Memorize" else "Open" },
        .{ .glyph = .{ .face = hud.BTN_BACK }, .label = if (picking) "Cancel" else "Back" },
    }, box, foot, a);
}

fn drawRack(self: *const Rest, v: View, x: i32, y: i32, w: i32, a: f32) void {
    var ry = y;
    for (0..combat.MEM_SLOTS) |i| {
        const on = i == self.memRow;
        const held = v.mem.at(i);
        if (on) uiart.rowHilite(x - 8, ry - 8, w + 16, RACK_CELL + 16);
        uiart.slot(x, ry, RACK_CELL, RACK_CELL, held != null);
        if (held) |sp| itemart.spellArt(sp, @floatFromInt(x + @divTrunc(RACK_CELL, 2)), @floatFromInt(ry + @divTrunc(RACK_CELL, 2)), @floatFromInt(RACK_CELL - 22), true);

        const tx = x + RACK_CELL + 18;
        hud.text(uiart.numeral(i), tx, ry + 2, hud.TINY, ink(uiart.GILT, a));
        const name: [:0]const u8 = if (held) |sp| combat.spellName(sp) else "(empty)";
        hud.text(name, tx, ry + hud.lineH(hud.TINY) + 4, hud.BODY, ink(if (on) uiart.HOT else if (held == null) uiart.TEXT_DIM else uiart.TEXT_VALUE, a));
        if (held) |sp| {
            hud.text(
                fmt("{d:.0} focus", .{combat.spellFp(sp)}),
                tx,
                ry + hud.lineH(hud.TINY) + hud.lineH(hud.BODY) + 6,
                hud.SMALL,
                ink(uiart.TEXT_DIM, a),
            );
        }
        ry += RACK_CELL + RACK_GAP;
    }
}

fn drawRead(self: *const Rest, v: View, x: i32, y: i32, w: i32, a: f32) void {
    var buf: [MEM_CANDS]?combat.Spell = undefined;
    const cs = memCands(v, &buf);
    var ry = y;
    if (self.memPick) |at| {
        hud.text(fmt("SLOT {s}", .{uiart.numeral(self.memRow)}), x, ry, hud.TINY, ink(uiart.GILT, a));
        ry += hud.lineH(hud.TINY) + 8;
        for (cs, 0..) |c, i| {
            const on = i == at;
            const step = hud.lineH(hud.BODY) + 10;
            if (on) uiart.rowHilite(x - 8, ry - 5, w + 16, step - 2);
            const name: [:0]const u8 = if (c) |sp| combat.spellName(sp) else "(nothing)";
            hud.text(name, x, ry, hud.BODY, ink(if (on) uiart.HOT else uiart.TEXT_DIM, a));
            if (c) |sp| {
                if (v.mem.slotOf(sp)) |had| {
                    const mark = fmt("SLOT {s}", .{uiart.numeral(had)});
                    hud.text(mark, x + w - hud.textW(mark, hud.TINY), ry + 3, hud.TINY, ink(uiart.GILT, a));
                } else {
                    const cost = fmt("{d:.0} FP", .{combat.spellFp(sp)});
                    hud.text(cost, x + w - hud.textW(cost, hud.SMALL), ry + 1, hud.SMALL, ink(uiart.TEXT_DIM, a));
                }
            }
            ry += step;
        }
        ry += 10;
    }
    const sp = memPickRow(self, v) orelse {
        const said: []const u8 = if (cs.len <= 1)
            "No sorcery scrolls carried. A scroll is what hands a spell over; without one there is nothing to memorize."
        else
            "Nothing memorized here. The rod holds only what is in the rack, and cycles between those.";
        _ = hud.prose(said, x, ry, w, hud.SMALL, ink(uiart.TEXT_HINT, a));
        return;
    };
    hud.engraved(combat.spellName(sp), x, ry, hud.BODY, ink(uiart.TEXT_TITLE, a));
    ry += hud.lineH(hud.BODY) + 6;
    hud.text(fmt("{d:.0} focus a cast, {d:.0} damage", .{ combat.spellFp(sp), combat.spellDamage(sp) }), x, ry, hud.SMALL, ink(uiart.GILT, a));
    ry += hud.lineH(hud.SMALL) + 8;
    ry = hud.prose(combat.spellSays(sp), x, ry, w, hud.SMALL, ink(uiart.TEXT_VALUE, a)) + 10;
    uiart.divider(x + @divTrunc(w, 2), ry, @divTrunc(w, 2) - 10, alpha(120.0, a));
    ry += 12;
    const scroll = combat.spellScroll(sp);
    const carried = combat.carriesSpell(v.bag, sp);
    _ = hud.prose(
        if (carried) item.displayName(scroll) else fmt("{s} - not carried", .{item.displayName(scroll)}),
        x,
        ry,
        w,
        hud.HINT,
        ink(if (carried) uiart.TEXT_HINT else uiart.BAD, a),
    );
}

pub fn isRestKind(k: props.Kind) bool {
    return k == .bonfire or k == .campfire_lit;
}

test "THE FIRE OFFERS ONLY THE SCROLLS HE CARRIES, and a slot is filled in two presses" {
    var mem = combat.Memory{};
    var bag = item.Bag{};
    const tree = Tree{};
    bag.add(combat.spellScroll(.bolt), 1);
    bag.add(combat.spellScroll(.sunder), 1);
    const v = View{ .tree = &tree, .souls = 0, .mem = &mem, .bag = &bag };

    var buf: [MEM_CANDS]?combat.Spell = undefined;
    const cs = memCands(v, &buf);
    try std.testing.expectEqual(@as(usize, 3), cs.len); // the empty row, plus two carried
    try std.testing.expectEqual(@as(?combat.Spell, null), cs[0]);
    try std.testing.expectEqual(combat.Spell.bolt, cs[1].?);
    try std.testing.expectEqual(combat.Spell.sunder, cs[2].?);

    var r = Rest{ .phase = .sit, .screen = .spells };
    try std.testing.expectEqual(Pick.none, confirm(&r, v));
    try std.testing.expectEqual(@as(?usize, 1), r.memPick);
    navigateSpells(&r, 1, v);
    try std.testing.expectEqual(@as(?usize, 2), r.memPick);
    const got = confirm(&r, v);
    try std.testing.expectEqual(combat.Spell.sunder, got.memorize.spell.?);
    try std.testing.expectEqual(@as(usize, 0), got.memorize.slot);
    try std.testing.expect(r.memPick == null);

    var none = combat.Memory{ .slots = [_]?combat.Spell{null} ** combat.MEM_SLOTS };
    var empty = item.Bag{};
    const bare = View{ .tree = &tree, .souls = 0, .mem = &none, .bag = &empty };
    var r2 = Rest{ .phase = .sit, .screen = .spells };
    try std.testing.expectEqual(Pick.none, confirm(&r2, bare));
    try std.testing.expect(r2.memPick == null);
    back(&r2);
    try std.testing.expectEqual(Screen.list, r2.screen);
    try std.testing.expectEqual(Phase.sit, r2.phase);
}
