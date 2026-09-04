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


pub const Row = enum {
    level,
    memorize,
    flasks,
    rest,
    leave,

    pub fn label(r: Row) [:0]const u8 {
        return switch (r) {
            .level => "Level Up",
            .memorize => "Memorize Spells",
            .flasks => "Allot Flasks",
            .rest => "Rest...",
            .leave => "Leave Bonfire",
        };
    }
};

pub const NROW = @typeInfo(Row).@"enum".fields.len;

pub const NWAIT = @typeInfo(daynight.Until).@"enum".fields.len;

pub const Screen = enum { list, tree, spells, flasks, waits };

pub const Pick = union(enum) {
    none,
    take: usize,
    wait: daynight.Until,
    memorize: struct { slot: usize, spell: ?combat.Spell },
    /// How many of the pool go to CRIMSON; the rest are cerulean (`combat.Flasks.allot`).
    allot: u8,
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

    memRow: usize = 0,
    memPick: ?usize = null,

    waitRow: usize = 0,
    /// The split being STAGED on the flask screen — nothing moves until it is confirmed.
    allotCrimson: u8 = combat.FLASK_CRIMSON,
    allotTotal: u8 = combat.FLASK_TOTAL,

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


pub const View = struct {
    tree: *const Tree,
    souls: u32,
    mem: *const combat.Memory,
    bag: *const item.Bag,
    flasks: *const combat.Flasks,
};

/// +1 for the EMPTY row: a slot you cannot clear is a slot the player is stuck with.
const MEM_CANDS = combat.SPELLS.len + 1;

fn memCands(v: View, out: *[MEM_CANDS]?combat.Spell) []const ?combat.Spell {
    out[0] = null;
    var n: usize = 1;
    for (combat.SPELLS) |row| {
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

fn cycleRow(row: *usize, dy: f32, n: i32) bool {
    const dv = mathx.signI(dy);
    if (dv == 0 or n <= 0) return false;
    const at: i32 = @intCast(row.*);
    const next = @mod(at + dv + n, n);
    if (next == at) return false;
    row.* = @intCast(next);
    return true;
}

pub fn navigate(self: *Rest, dx: f32, dy: f32) void {
    switch (self.screen) {
        .list => if (cycleRow(&self.row, dy, NROW)) sfx.play(.menu_move),
        .waits => if (cycleRow(&self.waitRow, dy, NWAIT)) sfx.play(.menu_move),
        .tree => if (self.wheel.move(dx, dy)) sfx.play(.menu_move),
        .spells => {},
        .flasks => {
            const dv = mathx.signI(dx);
            if (dv == 0) return;
            const at: i32 = @intCast(self.allotCrimson);
            const want = mathx.clampI(at + dv, 0, @intCast(self.allotTotal));
            if (want == at) return;
            self.allotCrimson = @intCast(want);
            sfx.play(.menu_move);
        },
    }
}

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
            switch (@as(Row, @enumFromInt(self.row))) {
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
                .flasks => {
                    self.screen = .flasks;
                    self.allotTotal = v.flasks.total();
                    self.allotCrimson = @min(v.flasks.allotted(.crimson), self.allotTotal);
                    sfx.play(.menu_pick);
                    return .none;
                },
                .rest => {
                    self.screen = .waits;
                    self.waitRow = 0;
                    sfx.play(.menu_pick);
                    return .none;
                },
                .leave => return .leave,
            }
        },
        .waits => return .{ .wait = @enumFromInt(self.waitRow) },
        .flasks => {
            sfx.play(.item_get);
            return .{ .allot = self.allotCrimson };
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

/// Stage a screen for the shot harness (`book.debugShow`'s pattern).
pub fn debugShow(self: *Rest, screen: Screen, row: usize, node: usize, mag: f32) void {
    self.screen = screen;
    self.row = @min(row, NROW - 1);
    self.waitRow = @min(row, NWAIT - 1);
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
        .waits => drawWaits(self, a),
        .flasks => drawFlasks(self, a),
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

/// The bonfire panel: a title and `n` rows, one of them under the cursor. The list and both of its sub-lists are the same picture, so a sub-option cannot grow its own shape.
const Panel = struct {
    x: i32,
    y: i32,
    w: i32,
    body: i32,

    fn open(title: [:0]const u8, rows: i32, a: f32) Panel {
        const w = panelW();
        const head = hud.lineH(hud.TITLE) + 40;
        const foot: i32 = 26;
        const h = head + rowH() * rows + foot;
        const x = MARGIN;
        const y = @divTrunc(rl.getScreenHeight() - h, 2);

        uiart.seat(x, y, w, h);
        uiart.plate(x, y, w, h, alpha(236.0, a));
        uiart.frame(x, y, w, h, alpha(200.0, a));

        hud.engraved(title, x + PAD_X, y + 20, hud.TITLE, ink(uiart.TEXT_TITLE, a));
        uiart.divider(x + @divTrunc(w, 2), y + hud.lineH(hud.TITLE) + 30, @divTrunc(w, 2) - PAD_X, alpha(170.0, a));
        return .{ .x = x, .y = y + head, .w = w, .body = 0 };
    }

    fn row(self: *Panel, label: [:0]const u8, on: bool, a: f32) i32 {
        const ry = self.y + self.body;
        if (on) uiart.rowHilite(self.x + 14, ry - 4, self.w - 28, rowH() - 8);
        hud.text(label, self.x + PAD_X + 6, ry, hud.BODY, ink(if (on) uiart.HOT else uiart.TEXT_VALUE, a));
        self.body += rowH();
        return ry;
    }
};

fn drawList(self: *const Rest, a: f32) void {
    var p = Panel.open("BONFIRE", NROW, a);
    for (0..NROW) |i| _ = p.row(@as(Row, @enumFromInt(i)).label(), i == self.row, a);
}

fn drawWaits(self: *const Rest, a: f32) void {
    var p = Panel.open("REST", NWAIT, a);
    for (0..NWAIT) |i| _ = p.row(@as(daynight.Until, @enumFromInt(i)).label(), i == self.waitRow, a);
}

/// ONE POOL, TWO ROWS, AND THE ARROWS ARE ON THE ONE THAT MOVES: the cerulean row is the remainder and carries no cursor of its own.
fn drawFlasks(self: *const Rest, a: f32) void {
    var p = Panel.open("FLASKS", 3, a);
    var buf: [48]u8 = undefined;
    const cerulean = self.allotTotal - @min(self.allotCrimson, self.allotTotal);
    const crimsonRow = std.fmt.bufPrintZ(&buf, "< Crimson  {d} >", .{self.allotCrimson}) catch "Crimson";
    _ = p.row(crimsonRow, true, a);
    var b2: [48]u8 = undefined;
    _ = p.row(std.fmt.bufPrintZ(&b2, "  Cerulean {d}", .{cerulean}) catch "Cerulean", false, a);
    var b3: [48]u8 = undefined;
    const foot = std.fmt.bufPrintZ(&b3, "{d} charges in all", .{self.allotTotal}) catch "";
    hud.text(foot, p.x + PAD_X + 6, p.y + p.body + 4, hud.SMALL, ink(uiart.TEXT_HINT, a));
}

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
        hud.HINT_WALK,
        hud.HINT_PAN,
        hud.HINT_ZOOM,
        .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Take" },
        hud.HINT_BACK,
    }, box, foot, a);
}

const RACK_CELL: i32 = 84;
const RACK_GAP: i32 = 16;

const fmt = hud.fmt;

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
    var flasks = combat.Flasks{};
    const v = View{ .tree = &tree, .souls = 0, .mem = &mem, .bag = &bag, .flasks = &flasks };

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
    const bare = View{ .tree = &tree, .souls = 0, .mem = &none, .bag = &empty, .flasks = &flasks };
    var r2 = Rest{ .phase = .sit, .screen = .spells };
    try std.testing.expectEqual(Pick.none, confirm(&r2, bare));
    try std.testing.expect(r2.memPick == null);
    back(&r2);
    try std.testing.expectEqual(Screen.list, r2.screen);
    try std.testing.expectEqual(Phase.sit, r2.phase);
}
