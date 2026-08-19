const rl = @import("raylib");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const sfx = @import("audio.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const ptree = @import("passivetree.zig");
const daynight = @import("daynight.zig");

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
            .untilMorning => daynight.Until.morning.label(),
            .untilEvening => daynight.Until.evening.label(),
            .leave => "Leave Bonfire",
        };
    }

    pub fn until(r: Row) ?daynight.Until {
        return switch (r) {
            .level, .leave => null,
            .untilMorning => .morning,
            .untilEvening => .evening,
        };
    }
};

pub const NROW = @typeInfo(Row).@"enum".fields.len;

pub const Screen = enum { list, tree };

pub const Pick = union(enum) {
    none,
    take: usize,
    wait: daynight.Until,
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
    }
}

pub fn zoom(self: *Rest, dv: f32, dt: f32) void {
    if (self.screen == .tree and dv != 0) self.wheel.zoomBy(dv, dt);
}

pub fn pan(self: *Rest, v: rl.Vector2, dt: f32) void {
    if (self.screen == .tree) self.wheel.panBy(v, dt);
}

pub fn confirm(self: *Rest, t: *const Tree, souls: u32) Pick {
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
                .leave => return .leave,
                .untilMorning, .untilEvening => unreachable,
            }
        },
        .tree => {
            const i = self.wheel.cursor;
            if (i >= ptree.N or !t.canTake(i, souls)) {
                sfx.play(.menu_back);
                return .none;
            }
            return .{ .take = i };
        },
    }
}

pub fn back(self: *Rest) void {
    if (self.screen == .tree) {
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

pub fn drawScreen(self: *const Rest, t: *const Tree, souls: u32) void {
    if (self.phase != .sit) return;
    const a: f32 = 1.0 - self.fade();
    if (a <= 0.02) return;
    switch (self.screen) {
        .list => drawList(self, a),
        .tree => drawTree(self, t, souls, a),
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

fn drawTree(self: *const Rest, t: *const Tree, souls: u32, a: f32) void {
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
    hud.engraved("PASSIVE TREE", x + 24, headY, hud.TITLE, ink(uiart.TEXT_TITLE, a));
    const foot = hud.lineH(hud.HINT) + 20;
    const bodyY = headY + hud.lineH(hud.TITLE) + 12;
    ptree.drawPage(t, self.wheel, x + 22, bodyY, w - 44, y + h - bodyY - foot - 8, true, souls);

    const hints = [_]hud.Hint{
        .{ .glyph = .{ .bumper = "LS" }, .label = "Walk" },
        .{ .glyph = .{ .bumper = "RS" }, .label = "Pan" },
        .{ .glyph = .{ .dpad = .updown }, .label = "Zoom" },
        .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Take" },
        .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Back" },
    };
    const hw = hud.hintRowW(&hints, hud.HINT);
    hud.hintRowAt(&hints, x + @divTrunc(w - hw, 2), y + h - foot + 2, hud.HINT, ink(uiart.TEXT_HINT, a));
}

pub fn isRestKind(k: props.Kind) bool {
    return k == .bonfire or k == .campfire_lit;
}
