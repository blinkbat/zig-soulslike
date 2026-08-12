const rl = @import("raylib");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const sfx = @import("audio.zig");
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const ptree = @import("passivetree.zig");
const daynight = @import("daynight.zig"); // the two named hours the fire will hold you until

const v3 = mathx.v3;


/// How many bonfires one world may hold.
pub const CAP: usize = 32;

/// How close you have to stand for the prompt (metres, XZ from the camp's own origin).
pub const REACH: f32 = 3.2;

const FADE_DOWN: f32 = 0.75; // to black, on the way in
const FADE_UP: f32 = 1.10;
const FADE_OUT: f32 = 0.60; // to black again on the way back to the field
const FADE_RETURN: f32 = 0.90;
const BED_IN: f32 = 2.6;
const BED_OUT: f32 = 0.55;
/// A nudge OFF the fire, toward the lens.
const SEAT_TURN: f32 = 0.20;

// THE BONFIRE IS A SCREEN NOW, not a pause with a fade. He sits on the RIGHT of the frame and the fire's own
// menu is a list down the LEFT — the shape every bonfire in the genre has. GETTING UP IS A ROW ON THAT LIST
// **OR BACK** (owner's call), and never "any button": what the old any-button rule guaranteed was a press
// that both chose a row and stood him up, and Back is the one button that can never also pick.
//
// THE FIRE DOES NOT TOUCH THE CLOCK ON ITS OWN (owner's call). Sitting down used to pull the whole world
// into a local dusk whatever hour it was; the hour you walked in at is the hour you sit in, and the two
// `Rest until…` rows are the only thing at a fire that moves the light.

/// What the fire offers. Two rows for now, and Leave is deliberately the LAST of them: it is the one you
/// arrive at by pushing down, which is where a hand that means to leave already is.
///
/// NO GLOSS UNDER THEM (owner's call). "Level Up" and "Leave Bonfire" are two verbs that say exactly what
/// they do, and a sentence explaining a verb is a sentence nobody reads twice.
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

    /// The hour this row waits for, or null for the rows that are not about the clock — EXHAUSTIVE, so a third
    /// named hour is a row here and a row in `daynight.Until` and nothing else.
    pub fn until(r: Row) ?daynight.Until {
        return switch (r) {
            .level, .leave => null,
            .untilMorning => .morning,
            .untilEvening => .evening,
        };
    }
};

pub const NROW = @typeInfo(Row).@"enum".fields.len;

/// Which of the fire's screens is up. The tree is shown ONLY once Level Up is chosen (owner's call) — the
/// list is what a bonfire looks like, and a wheel behind it every time you sat down would bury that.
pub const Screen = enum { list, tree };

/// WHAT A PRESS AT THE FIRE ASKED FOR. The bonfire owns none of the game's state — the souls and the tree
/// belong to the loop, exactly as the book's own `Action` does.
pub const Pick = union(enum) {
    none,
    /// Take the node the wheel's cursor is on — which IS the level-up, souls and all.
    take: usize,
    /// SIT UNTIL A NAMED HOUR. The fire asks; only the loop owns the clock, which is the same split the
    /// level-up keeps with the souls.
    wait: daynight.Until,
    /// Stand up.
    leave,
};

pub const Site = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own — the camp's layout is authored in its local frame
};

pub const Phase = enum {
    off, // out in the field
    in, // fading down to black, still standing
    sit, // at the fire
    out, // fading down to black again, on the way back
};

pub const Rest = struct {
    list: [CAP]Site = undefined,
    n: usize = 0,
    near: ?usize = null,

    phase: Phase = .off,
    /// Seconds INTO the current phase.
    t: f32 = mathx.LONG_AGO,
    site: Site = .{},

    /// EDGES, true for exactly the one frame the transition happens on.
    justEntered: bool = false,
    justLeft: bool = false,

    /// THE FIRE'S OWN MENU. Reset on every sit (`begin`), because a bonfire opens on its first row: coming
    /// back to a fire already sat on Leave is one press from standing straight back up.
    screen: Screen = .list,
    row: usize = 0,
    /// …and the bonfire's own view of the tree, kept apart from the book's for the reason written at that one.
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
    /// True while the rest scene — not the field — is what is being drawn.
    pub fn scene(self: *const Rest) bool {
        return self.phase == .sit or self.phase == .out;
    }

    /// HOW BLACK THE SCREEN IS, 0..1.
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

    /// BEGIN, if there is a fire in reach.
    pub fn begin(self: *Rest) bool {
        if (self.phase != .off or self.fadeRunning()) return false;
        const i = self.near orelse return false;
        self.site = self.list[i];
        self.phase = .in;
        self.t = 0;
        self.near = null;
        self.screen = .list; // a bonfire opens on its FIRST row, never on the one you left it on
        self.row = 0;
        return true;
    }

    /// IS THE MENU TAKING INPUT — sat down, AND far enough through the fade for the list to be readable.
    /// Live from the first frame of `.sit`, a press aimed at the world before the screen went black picks a
    /// row nobody has seen yet; the chrome's own alpha is `1 - fade()`, so this is the same clock it draws on.
    pub fn listening(self: *const Rest) bool {
        return self.phase == .sit and self.fade() <= 0.35;
    }

    /// LEAVE — the list's own last row. There is no minimum sit any more: that existed to stop the
    /// ANY-BUTTON rule standing him up on the frame he sat down, and against a row you have to move to and
    /// confirm, all it could do was make that row silently do nothing for its first two seconds.
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

    /// WHERE THE HERO SITS, and which way he faces.
    pub fn seat(self: *const Rest) struct { pos: rl.Vector3, facing: f32, axis: f32 } {
        const yaw = mathx.radians(self.site.yaw);
        const c = mathx.cosf(yaw);
        const s = mathx.sinf(yaw);
        const lx: f32 = 1.25;
        const lz: f32 = -1.95;
        const pos = v3(self.site.pos.x + c * lx + s * lz, self.site.pos.y, self.site.pos.z - s * lx + c * lz);
        // `axis` points at the fire and is what the camera stands broadside to.
        const axis = mathx.headingXZ(mathx.subV(self.site.pos, pos));
        return .{ .pos = pos, .facing = axis + SEAT_TURN, .axis = axis };
    }
};

pub fn siteFromProp(pos: rl.Vector3, yaw: f32) Site {
    return .{ .pos = pos, .yaw = yaw };
}

// THE BONFIRE'S SCREEN. The state and the walk live here; the game loop reads the buttons and hands the
// results in, exactly as it does for the character book — this file owns no bindings.

/// Move the cursor on whichever screen is up. `dx`/`dy` are one step, from a d-pad, a key or the left stick.
pub fn navigate(self: *Rest, dx: i32, dy: i32) void {
    if (dx == 0 and dy == 0) return;
    switch (self.screen) {
        .list => {
            if (dy == 0) return;
            const n: i32 = NROW;
            const at: i32 = @intCast(self.row);
            const next = @mod(at + dy + n, n);
            if (next == at) return;
            self.row = @intCast(next);
            sfx.play(.menu_move);
        },
        // THE WHEEL IS WALKED BY DIRECTION, never cycled (`ptree.step`'s law).
        .tree => if (self.wheel.move(dx, dy)) sfx.play(.menu_move),
    }
}

/// The CROSS's up and down (`menu.dpadZoom`), on the tree screen and nowhere else — never the bumpers, which
/// are the character book's page turn.
pub fn zoom(self: *Rest, dv: f32, dt: f32) void {
    if (self.screen == .tree and dv != 0) self.wheel.zoomBy(dv, dt);
}

/// …and the RIGHT STICK, which slides the view (owner's call). Same gate: the list has nothing to pan.
pub fn pan(self: *Rest, v: rl.Vector2, dt: f32) void {
    if (self.screen == .tree) self.wheel.panBy(v, dt);
}

/// CONFIRM. On the list it picks a row; on the wheel it asks for the node under the cursor.
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
                // …answered by `until()` above, which is the one place the clock rows are named.
                .untilMorning, .untilEvening => unreachable,
            }
        },
        .tree => {
            const i = self.wheel.cursor;
            // THE MIDDLE TAKES NO PRESS. It is a place to stand, not a thing to buy, and `locked` is only
            // ever asked about a real node.
            if (i >= ptree.N or t.locked(i, souls) != null) {
                sfx.play(.menu_back); // refused, and the column beside it already says why
                return .none;
            }
            return .{ .take = i };
        },
    }
}

/// BACK. Off the wheel and onto the list; on the list it stands him up, which is what the one button that
/// means "the screen before this one" has to do when the screen before this one is the field.
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
    // CLAMPED, because `confirm` turns this into a `Row` and an out-of-range `@enumFromInt` is illegal
    // behaviour rather than a wrong row. `navigate` keeps it in range with its own `@mod`; this is the
    // other writer, and the wheel's cursor is already bounded at every read (`ptree.HUB`).
    self.row = @min(row, NROW - 1);
    self.wheel = .{ .cursor = node, .zoom = mag };
}

/// How much of the screen's width the fire's own chrome takes down the left. The seat camera is panned so
/// the man and the flame compose in what is left (`game.restCamera`).
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

/// THE FIRE'S CHROME, over the scene and under nothing. Drawn only once he is actually SAT: through the two
/// fades the screen is going black, and a panel at full strength over that reads as a card that arrived
/// early. `t` and `souls` are the live ones — the bonfire holds no copy of either.
pub fn drawScreen(self: *const Rest, t: *const Tree, souls: u32) void {
    if (self.phase != .sit) return;
    const a: f32 = 1.0 - self.fade(); // the fade is the scene coming UP; the chrome comes up with it
    if (a <= 0.02) return;
    switch (self.screen) {
        .list => drawList(self, a),
        .tree => drawTree(self, t, souls, a),
    }
}

fn ink(c: rl.Color, a: f32) rl.Color {
    return mathx.withAlpha(c, mathx.u8f(@as(f32, @floatFromInt(c.a)) * mathx.clampF(a, 0, 1)));
}

const PAD_X: i32 = 24;

fn drawList(self: *const Rest, a: f32) void {
    const w = panelW();
    const sh = rl.getScreenHeight();
    const head = hud.lineH(hud.TITLE) + 40;
    const body = rowH() * @as(i32, NROW);
    // NO HINT ROW HERE (owner's call) — four verbs down a list is the whole of it, and a crib under them
    // was telling you which button picks a row on the one screen where every row says what it does.
    const foot: i32 = 26;
    const h = head + body + foot;
    const x = MARGIN;
    const y = @divTrunc(sh - h, 2);

    uiart.seat(x, y, w, h);
    uiart.plate(x, y, w, h, mathx.u8f(236.0 * mathx.clampF(a, 0, 1)));
    uiart.frame(x, y, w, h, mathx.u8f(200.0 * mathx.clampF(a, 0, 1)));

    hud.engraved("BONFIRE", x + PAD_X, y + 20, hud.TITLE, ink(uiart.TEXT_TITLE, a));
    uiart.divider(x + @divTrunc(w, 2), y + hud.lineH(hud.TITLE) + 30, @divTrunc(w, 2) - PAD_X, mathx.u8f(170.0 * a));

    var ry = y + head;
    for (0..NROW) |i| {
        const r: Row = @enumFromInt(i);
        const on = i == self.row;
        if (on) uiart.rowHilite(x + 14, ry - 4, w - 28, rowH() - 8);
        hud.text(r.label(), x + PAD_X + 6, ry, hud.BODY, ink(if (on) uiart.HOT else uiart.TEXT_VALUE, a));
        ry += rowH();
    }
}

/// THE WHEEL, and at a fire it is SPENDABLE — this is the one screen in the game that can charge him souls.
/// It takes the whole card rather than the left strip: the tree is a picture, and a picture in a third of
/// the screen is one you cannot find a node on.
fn drawTree(self: *const Rest, t: *const Tree, souls: u32, a: f32) void {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const x = MARGIN;
    const y = @max(30, @divTrunc(sh, 16));
    const w = sw - MARGIN * 2;
    const h = sh - y * 2;

    rl.drawRectangle(0, 0, sw, sh, mathx.withAlpha(rl.Color.black, mathx.u8f(150.0 * mathx.clampF(a, 0, 1))));
    uiart.seat(x, y, w, h);
    uiart.plate(x, y, w, h, mathx.u8f(240.0 * mathx.clampF(a, 0, 1)));
    uiart.frame(x, y, w, h, mathx.u8f(200.0 * mathx.clampF(a, 0, 1)));

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

/// THE KINDS YOU CAN SIT AT. The bonfire camp, and the lit campfire — a camp you can pitch anywhere,
/// and it is a FULL bonfire (owner's call): the same restore and the same world reload, because the one
/// thing worse than a second rest kind is a second rest kind with its own half-rules.
pub fn isRestKind(k: props.Kind) bool {
    return k == .bonfire or k == .campfire_lit;
}
