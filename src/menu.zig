const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const hud = @import("hud.zig");
const mathx = @import("mathx.zig");
const rumblemod = @import("rumble.zig");
const sfx = @import("audio.zig");
const item = @import("item.zig");
const uiart = @import("uiart.zig");
const bookmod = @import("book.zig"); // pad START opens the CHARACTER BOOK, which is its own three pages

const rgba = mathx.rgba;

const padPressed = rumblemod.padPressed;
const padDown = rumblemod.padDown;


/// The three swap actions are the BOOK's, passed straight through: the menu owns no game state and never
/// has, and an equipment screen that reached into the hero would be the first place it did.
pub const Action = union(enum) {
    none,
    quit,
    editor,
    use: item.Kind,
    arm: bookmod.Action,
};

const Screen = enum {
    closed,
    main, // ── the GAME menu (Select) …
    options,
    debug,
    retro,
    // THE SOUND FILTER RACK IS NOT HERE ANY MORE — it moved to the EDITOR, beside the jukebox, because it
    // is an authoring tool and not a setting: you turn a dial to hear what a voice becomes, and the one
    // place you can hear a voice on demand is the jukebox. The RETRO rack stays: that one is a LOOK the
    // player picks. See `editor.zig`'s `.jukebox` modal.
    character, // …and the CHARACTER BOOK (Start), which is `book.zig` end to end

    fn root(s: Screen) Screen {
        return switch (s) {
            .closed => .closed,
            .main, .options, .debug, .retro => .main,
            .character => .character,
        };
    }
};

const OPT_MIX = [_]sfx.Submix{ .ambience, .sfx, .combat };
comptime {
    if (OPT_MIX.len != @typeInfo(sfx.Submix).@"enum".fields.len) @compileError("Options is missing a submix row");
}
const OPT_CLOSE = OPT_MIX.len;
const OPT_COUNT = OPT_CLOSE + 1;

// Debug rows (the retro list gets a submenu; the rest toggle/cycle in place). The SOUND filter rack used to
// sit here and is now the editor's — see the note on `Screen`.
const DBG_RETRO = 0;
const DBG_STATS = 1;
const DBG_WIREFRAME = 2;
const DBG_HITBOX = 3;
const DBG_TIMESCALE = 4;
const DBG_CLOSE = 5;
const DBG_COUNT = DBG_CLOSE + 1;

const RET_PRESET_PS1 = gfx.RETRO_COUNT + 0;
const RET_PRESET_CRT = gfx.RETRO_COUNT + 1;
const RET_PRESET_VHS = gfx.RETRO_COUNT + 2;
const RET_PRESET_GB = gfx.RETRO_COUNT + 3;
const RET_RESET = gfx.RETRO_COUNT + 4;
const RET_ALL_OFF = gfx.RETRO_COUNT + 5;
const RET_CLOSE = gfx.RETRO_COUNT + 6;
const RET_COUNT = RET_CLOSE + 1;

// Slider feel: a TAP steps fine, Shift/LB-tap steps coarse, and HOLDING a direction glides continuously after a short delay — frame-rate-fine adjustment.
const ADJ_TAP: f32 = 0.01;
const ADJ_COARSE: f32 = 0.10;
const ADJ_GLIDE_DELAY: f32 = 0.35; // seconds held before the glide kicks in
const ADJ_GLIDE_RATE: f32 = 0.25; // intensity per second while gliding

const MAIN_CONTINUE = 0;
const MAIN_OPTIONS = 1;
const MAIN_EDITOR = 2;
const MAIN_DEBUG = 3;
const MAIN_QUIT = 4;
const MAIN_COUNT = MAIN_QUIT + 1;

const VEIL = rgba(6, 6, 9, 150);
const CARD = rgba(16, 15, 13, 232);
// THE INK IS `uiart`'s, not a second copy of it — that file's four weights exist so the menu card and the
// character book cannot drift into two greys, and these three were byte-identical restatements of them.
const TEXT_DIM = uiart.TEXT_DIM;
const TEXT_HOT = uiart.HOT;
const TITLE_COL = uiart.TEXT_TITLE;
const HINT_COL = uiart.TEXT_HINT;
const BAR_EDGE = rgba(120, 104, 74, 160);
const BAR_FILL = rgba(198, 164, 96, 220);

pub const Menu = struct {
    screen: Screen = .main, // the menu IS the start screen
    cursor: usize = 0,
    // debug toggles the game loop reads
    stats: bool = false,
    wireframe: bool = false,
    hitboxes: bool = false, // draw the blade hit capsule during attacks
    timeScale: f32 = 1.0,
    adjHoldT: f32 = 0, // seconds an adjust direction has been held (glide timer)
    /// The CHARACTER BOOK, which keeps its own cursor per page and its own animation.
    book: bookmod.Book = .{},

    pub fn isOpen(self: *const Menu) bool {
        return self.screen != .closed;
    }

    /// Esc, and pad SELECT. The sound screen persists on the way out — the levels live in `settings.cfg`
    /// and are written when the screen closes, never per nudge. (The racks are written the same way by the
    /// editor's own rack panel, into the same file.)
    fn leavingSound(self: *Menu) void {
        if (self.screen == .options) sfx.saveSettings();
    }

    pub fn onEscape(self: *Menu) void {
        // Inside the book, Back closes an open picker first — one press, one level, like every other screen.
        if (self.screen == .character and self.book.onBack()) return;
        self.leavingSound();
        self.cursor = 0;
        self.screen = switch (self.screen) {
            .closed => .main,
            .main, .character => .closed,
            .options => .main,
            .debug => .main,
            .retro => .debug,
        };
    }

    pub fn onSelectButton(self: *Menu) void {
        self.leavingSound();
        self.cursor = 0;
        self.screen = if (self.screen.root() == .main) .closed else .main;
    }

    /// Pad START — the CHARACTER BOOK (owner's call: "start menu will be character-driven").
    pub fn onStartButton(self: *Menu) void {
        self.leavingSound();
        self.cursor = 0;
        if (self.screen.root() == .character) {
            self.screen = .closed;
            return;
        }
        self.screen = .character;
        self.book.opened();
    }

    /// HOW MANY ROWS THE LIVE SCREEN HAS — asked by the cursor wrap AND by "is the cursor on Back".
    /// The book is not a row list and answers 0; it is driven whole, below.
    fn rowCount(self: *const Menu) usize {
        return switch (self.screen) {
            .closed, .character => 0,
            .main => MAIN_COUNT,
            .options => OPT_COUNT,
            .debug => DBG_COUNT,
            .retro => RET_COUNT,
        };
    }

    // dt is the REAL frame time (not time-scaled) so the glide speed never changes.
    pub fn update(self: *Menu, retro: *gfx.Retro, dt: f32, v: bookmod.View) Action {
        if (self.screen == .closed) return .none;
        if (self.screen == .character) return self.updateBook(dt, v);
        const rows = self.rowCount();
        if (rows == 0) return .none; // a screen with no rows has no cursor to wrap (and no modulo to do)
        if (navPressed(.up)) {
            self.cursor = (self.cursor + rows - 1) % rows;
            sfx.play(.menu_move);
        }
        if (navPressed(.down)) {
            self.cursor = (self.cursor + 1) % rows;
            sfx.play(.menu_move);
        }

        if (self.screen == .retro and self.cursor < gfx.RETRO_COUNT) {
            const dial = &retro.values[self.cursor];
            dial.* = mathx.clampF(dial.* + self.adjustDelta(dt), 0, 1);
        } else if (self.screen == .options and self.cursor < OPT_MIX.len) {
            const m = OPT_MIX[self.cursor];
            const d = self.adjustDelta(dt);
            if (d != 0) sfx.setVolume(m, sfx.volume(m) + d);
        } else {
            self.adjHoldT = 0;
        }
        if (self.screen == .debug and self.cursor == DBG_TIMESCALE) {
            if (adjTapped(.left) or adjTapped(.right)) self.cycleTimeScale();
        }

        if (confirmPressed()) {
            sfx.play(.menu_pick);
            return self.confirm(retro);
        }
        if (backPressed()) {
            sfx.play(.menu_back);
            self.onEscape();
        }
        return .none;
    }

    /// THE BOOK'S OWN INPUT. It is a grid, not a row list: four directions move a cursor, the shoulders
    /// turn the page, and Left/Right doubles as the portrait's turntable — none of which the card
    /// screens' one-dimensional nav can express.
    fn updateBook(self: *Menu, dt: f32, v: bookmod.View) Action {
        if (tabPressed(-1)) self.book.onTab(-1);
        if (tabPressed(1)) self.book.onTab(1);
        if (navPressed(.up)) self.book.move(0, -1, v);
        if (navPressed(.down)) self.book.move(0, 1, v);
        if (navPressed(.left)) self.book.move(-1, 0, v);
        if (navPressed(.right)) self.book.move(1, 0, v);
        // …and the LEFT STICK drives the same four, which is what walking a wheel wants.
        if (stickStep(dt)) |d| switch (d) {
            .up => self.book.move(0, -1, v),
            .down => self.book.move(0, 1, v),
            .left => self.book.move(-1, 0, v),
            .right => self.book.move(1, 0, v),
        };
        self.book.spinBy(adjHeldDir(), dt);
        self.book.zoomBy(stickZoom(), dt);
        var act: Action = .none;
        if (confirmPressed()) {
            const a = self.book.confirm(v);
            act = switch (a) {
                .none => .none,
                .use => |k| .{ .use = k },
                else => .{ .arm = a },
            };
        }
        if (backPressed()) self.onEscape();
        self.book.tick(dt, confirmHeld(), v);
        return act;
    }

    fn confirm(self: *Menu, retro: *gfx.Retro) Action {
        switch (self.screen) {
            .closed => {},
            .main => switch (self.cursor) {
                MAIN_CONTINUE => self.screen = .closed,
                MAIN_OPTIONS => {
                    self.screen = .options;
                    self.cursor = 0;
                },
                MAIN_EDITOR => {
                    self.screen = .closed; // the editor is its own scene; the menu gets out of the way
                    return .editor;
                },
                MAIN_DEBUG => {
                    self.screen = .debug;
                    self.cursor = 0;
                },
                MAIN_QUIT => return .quit,
                else => {},
            },
            .options => {
                // Confirm on a level row does nothing (Left/Right adjust it) — only Back acts.
                if (self.cursor == OPT_CLOSE) {
                    self.leavingSound();
                    self.screen = .main;
                    self.cursor = 0;
                }
            },
            .debug => switch (self.cursor) {
                DBG_RETRO => {
                    self.screen = .retro;
                    self.cursor = 0;
                },
                DBG_STATS => self.stats = !self.stats,
                DBG_WIREFRAME => self.wireframe = !self.wireframe,
                DBG_HITBOX => self.hitboxes = !self.hitboxes,
                DBG_TIMESCALE => self.cycleTimeScale(),
                DBG_CLOSE => {
                    self.screen = .main;
                    self.cursor = 0;
                },
                else => {},
            },
            .character => {}, // the book handles its own confirm — see `updateBook`
            .retro => switch (self.cursor) {
                RET_PRESET_PS1 => retro.applyPreset(&gfx.PRESET_PS1),
                RET_PRESET_CRT => retro.applyPreset(&gfx.PRESET_CRT),
                RET_PRESET_VHS => retro.applyPreset(&gfx.PRESET_VHS),
                RET_PRESET_GB => retro.applyPreset(&gfx.PRESET_GB),
                RET_RESET => retro.values = gfx.RETRO_DEFAULTS,
                RET_ALL_OFF => retro.allOff(),
                RET_CLOSE => {
                    self.screen = .debug;
                    self.cursor = 0;
                },
                else => {}, // confirm on a slider row: nothing (Left/Right adjust)
            },
        }
        return .none;
    }

    /// How far the adjust inputs want the value under the cursor to move THIS FRAME: a TAP steps fine, Shift/LB-tap steps coarse, and holding a direction glides continuously after a short delay.
    fn adjustDelta(self: *Menu, dt: f32) f32 {
        const step: f32 = if (coarseHeld()) ADJ_COARSE else ADJ_TAP;
        var d: f32 = 0;
        if (adjTapped(.left)) d -= step;
        if (adjTapped(.right)) d += step;
        const dir = adjHeldDir();
        if (dir != 0) {
            self.adjHoldT += dt;
            if (self.adjHoldT > ADJ_GLIDE_DELAY) d += @as(f32, @floatFromInt(dir)) * ADJ_GLIDE_RATE * dt;
        } else {
            self.adjHoldT = 0;
        }
        return d;
    }

    fn cycleTimeScale(self: *Menu) void {
        self.timeScale = if (self.timeScale > 0.75) 0.5 else if (self.timeScale > 0.35) 0.25 else 1.0;
    }

    fn debugLabels(self: *const Menu) [DBG_COUNT][:0]const u8 {
        var out: [DBG_COUNT][:0]const u8 = undefined;
        out[DBG_RETRO] = "Retro Filters >";
        out[DBG_STATS] = if (self.stats) "Stats: On" else "Stats: Off";
        out[DBG_WIREFRAME] = if (self.wireframe) "Wireframe: On" else "Wireframe: Off";
        out[DBG_HITBOX] = if (self.hitboxes) "Hitboxes: On" else "Hitboxes: Off";
        out[DBG_TIMESCALE] = std.fmt.bufPrintZ(&dbgTimeBuf, "Time Scale: {d:.0}%", .{self.timeScale * 100}) catch "?";
        out[DBG_CLOSE] = "Back";
        return out;
    }

    pub fn draw(self: *const Menu, retro: *const gfx.Retro, v: bookmod.View, portrait: ?bookmod.Portrait) void {
        if (self.screen == .closed) return;
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        rl.drawRectangle(0, 0, sw, sh, VEIL);
        const lb = @divTrunc(sh, 8); // dusk gathers at the frame's edges
        rl.drawRectangleGradientV(0, 0, sw, lb, rgba(0, 0, 0, 140), rgba(0, 0, 0, 0));
        rl.drawRectangleGradientV(0, sh - lb, sw, lb, rgba(0, 0, 0, 0), rgba(0, 0, 0, 140));
        // THE BOOK IS NOT A CARD. It fills the frame and carries its own crib line, so it returns here
        // rather than falling through to the row-list chrome below.
        if (self.screen == .character) {
            bookmod.draw(&self.book, v, portrait);
            return;
        }
        switch (self.screen) {
            .closed, .character => {},
            .main => self.drawCard("SOULSLIKE", &mainLabels(), .{}),
            .options => self.drawCard("SOUND", &optionLabels(), .{ .gauges = &soundLevels() }),
            .debug => self.drawCard("DEBUG", &self.debugLabels(), .{}),
            .retro => self.drawCard("RETRO FILTERS", &retroLabels(retro), .{ .gauges = retro.values[0..gfx.RETRO_COUNT] }),
        }
        // THE CRIB NAMES BUTTONS AND NOTHING ELSE (owner's call) — one strip, whether a pad is plugged in or
        // not. The keys still work; they are simply not what the chrome talks about, so there is no second
        // caption to keep in step with this one and no branch that can show the wrong half.
        const hints = [_]hud.Hint{
            .{ .glyph = .{ .dpad = .updown }, .label = "Move" },
            .{ .glyph = .{ .dpad = .leftright }, .label = "Adjust" },
            .{ .glyph = .{ .bumper = "LB" }, .label = "Coarse" },
            .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Select" },
            .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Back" },
            .{ .glyph = .menu, .label = "Character" },
        };
        hud.hintRow(&hints, sh - @divTrunc(hud.lineH(hud.HINT), 2) - 14, hud.HINT, HINT_COL);
    }

    fn drawCard(self: *const Menu, title: [:0]const u8, labels: []const [:0]const u8, card: Card) void {
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        const compact = labels.len > 8; // the long retro list packs tighter than the short menus
        const fontSize: i32 = if (compact) hud.SMALL else hud.BODY;
        const rowH: i32 = hud.lineH(fontSize) + (if (compact) @as(i32, 2) else @as(i32, 14));
        const rowGap: i32 = if (compact) 2 else 8;
        const headerH: i32 = hud.lineH(hud.TITLE) + 22;
        const noteH: i32 = if (card.note != null) hud.lineH(hud.HINT) + 14 else 0;
        const footH: i32 = 20 + noteH;
        // THE CARD IS AT LEAST AS WIDE AS ITS FOOTNOTE. The note is centred on the plate, so one longer
        // than the plate spills out over the world on BOTH sides — measure it rather than hoping.
        const noteW: i32 = if (card.note) |n| hud.textW(n, hud.HINT) else 0;
        const cardW: i32 = @max(if (card.gauges != null or card.note != null) @as(i32, 620) else @as(i32, 470), noteW + 72);
        const cardH: i32 = headerH + (rowH + rowGap) * @as(i32, @intCast(labels.len)) + footH;
        const cx = @divTrunc(sw - cardW, 2);
        const cy = @divTrunc(sh - cardH, 2);
        uiart.seat(cx, cy, cardW, cardH);
        uiart.plate(cx, cy, cardW, cardH, CARD.a);
        uiart.frame(cx, cy, cardW, cardH, uiart.flick(200, cx));
        uiart.divider(cx + @divTrunc(cardW, 2), cy + hud.lineH(hud.TITLE) + 10, @divTrunc(cardW, 2) - 24, 180);
        const tw = hud.textW(title, hud.TITLE);
        hud.engraved(title, cx + @divTrunc(cardW - tw, 2), cy + 12, hud.TITLE, TITLE_COL);
        for (labels, 0..) |label, i| {
            const y = cy + headerH + (rowH + rowGap) * @as(i32, @intCast(i));
            const selected = self.cursor == i;
            const col = if (selected) TEXT_HOT else TEXT_DIM;
            if (selected) {
                uiart.rowHilite(cx + 14, y - 3, cardW - 28, rowH);
                // …and the card's own two hairlines and jewelled spine-ends on top of the shared wash.
                rl.drawRectangle(cx + 14, y - 3, cardW - 28, 1, mathx.withAlpha(uiart.GILT, 70));
                rl.drawRectangle(cx + 14, y - 4 + rowH, cardW - 28, 1, mathx.withAlpha(uiart.GILT, 46));
                uiart.diamond(@floatFromInt(cx + 16), @floatFromInt(y), 2.6, uiart.GILT_BRIGHT);
                uiart.diamond(@floatFromInt(cx + 16), @floatFromInt(y - 3 + rowH), 2.6, uiart.GILT_BRIGHT);
            }
            hud.text(label, cx + 40, y, fontSize, col);
            if (selected) hud.text(">", cx + 24, y, fontSize, TEXT_HOT);
            if (card.gauges) |g| {
                if (i < g.len) drawGauge(cx + cardW - 40 - 130, y + @divTrunc(fontSize, 2) - 3, 130, 10, g[i], selected);
            }
        }
        if (card.note) |n| {
            if (n.len > 0) {
                const ny = cy + cardH - noteH - 4;
                uiart.divider(cx + @divTrunc(cardW, 2), ny - 8, @divTrunc(cardW, 2) - 40, 120);
                const nw = hud.textW(n, hud.HINT);
                hud.text(n, cx + @divTrunc(cardW - nw, 2), ny, hud.HINT, HINT_COL);
            }
        }
    }
};

/// The optional columns a card can carry: a GAUGE per row (the two slider screens) and a footnote about whichever row the cursor is on. A slice shorter than the row list simply leaves the tail bare, which is how Back gets no gauge.
const Card = struct {
    gauges: ?[]const f32 = null,
    note: ?[:0]const u8 = null,
};

fn drawGauge(x: i32, y: i32, w: i32, h: i32, v: f32, selected: bool) void {
    rl.drawRectangle(x, y, w, h, rgba(6, 5, 4, 200));
    rl.drawRectangleLines(x, y, w, h, BAR_EDGE);
    rl.drawRectangle(x + 1, y + 1, w - 2, 1, rgba(0, 0, 0, 130)); // sunk top lip
    const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(w - 2)) * mathx.clampF(v, 0, 1));
    if (fill > 0) {
        rl.drawRectangleGradientH(x + 1, y + 1, fill, h - 2, mathx.lerpColor(BAR_FILL, rl.Color.black, 0.45), BAR_FILL);
        rl.drawRectangle(x + 1, y + 1, fill, 1, mathx.withAlpha(uiart.GILT_BRIGHT, 90));
        if (v < 0.999 and fill > 4) rl.drawRectangle(x + fill - 1, y + 2, 2, h - 4, mathx.withAlpha(uiart.CATCH, 150));
    }
    if (selected) {
        hud.text("<", x - 20, y - 7, hud.SMALL, TEXT_HOT);
        hud.text(">", x + w + 7, y - 7, hud.SMALL, TEXT_HOT);
    } else {
        uiart.diamond(@floatFromInt(x - 7), @floatFromInt(y + @divTrunc(h, 2)), 2.0, mathx.withAlpha(uiart.GILT_DIM, 150));
        uiart.diamond(@floatFromInt(x + w + 7), @floatFromInt(y + @divTrunc(h, 2)), 2.0, mathx.withAlpha(uiart.GILT_DIM, 150));
    }
}

fn mainLabels() [MAIN_COUNT][:0]const u8 {
    var out: [MAIN_COUNT][:0]const u8 = undefined;
    out[MAIN_CONTINUE] = "Continue";
    out[MAIN_OPTIONS] = "Options >";
    out[MAIN_EDITOR] = "Editor";
    out[MAIN_DEBUG] = "Debug";
    out[MAIN_QUIT] = "Quit";
    return out;
}

fn optionName(m: sfx.Submix) [:0]const u8 {
    return switch (m) {
        .ambience => "Ambient",
        .sfx => "Sound Effects",
        .combat => "Combat",
    };
}

fn optionLabels() [OPT_COUNT][:0]const u8 {
    var out: [OPT_COUNT][:0]const u8 = undefined;
    for (OPT_MIX, 0..) |m, i| {
        const v = sfx.volume(m);
        out[i] = if (v <= 0.001)
            std.fmt.bufPrintZ(&optBufs[i], "{s}: Off", .{optionName(m)}) catch "?"
        else
            std.fmt.bufPrintZ(&optBufs[i], "{s}: {d:.0}%", .{ optionName(m), v * 100 }) catch "?";
    }
    out[OPT_CLOSE] = "Back";
    return out;
}
var optBufs: [OPT_MIX.len][48]u8 = undefined;

/// The same three numbers as bars, for `drawCard`'s gauge column.
fn soundLevels() [OPT_MIX.len]f32 {
    var out: [OPT_MIX.len]f32 = undefined;
    for (OPT_MIX, 0..) |m, i| out[i] = sfx.volume(m);
    return out;
}

var dbgTimeBuf: [48]u8 = undefined;

fn retroLabels(retro: *const gfx.Retro) [RET_COUNT][:0]const u8 {
    var out: [RET_COUNT][:0]const u8 = undefined;
    for (0..gfx.RETRO_COUNT) |i| {
        const v = retro.values[i];
        if (v <= gfx.RETRO_EPS) {
            out[i] = std.fmt.bufPrintZ(&retroBufs[i], "{s}: Off", .{gfx.RETRO_NAMES[i]}) catch "?";
        } else {
            out[i] = std.fmt.bufPrintZ(&retroBufs[i], "{s}: {d:.1}%", .{ gfx.RETRO_NAMES[i], v * 100 }) catch "?";
        }
    }
    out[RET_PRESET_PS1] = "Preset: PS1";
    out[RET_PRESET_CRT] = "Preset: CRT";
    out[RET_PRESET_VHS] = "Preset: VHS";
    out[RET_PRESET_GB] = "Preset: Game Boy";
    out[RET_RESET] = "Reset to Default";
    out[RET_ALL_OFF] = "All Off";
    out[RET_CLOSE] = "Close";
    return out;
}
var retroBufs: [gfx.RETRO_COUNT][48]u8 = undefined;


/// PUBLIC because this file is where full-screen UI navigation lives — the pause card's rows, the character
/// book's grid, and now the dialog panel's answer list all read the pad and the keyboard through here. A
/// second private copy of "is Down pressed" is a second thing to drift out of step with this one.
pub const NavDir = enum { up, down, left, right };

fn keyNav(dir: NavDir) struct { a: rl.KeyboardKey, b: rl.KeyboardKey } {
    return switch (dir) {
        .up => .{ .a = .up, .b = .w },
        .down => .{ .a = .down, .b = .s },
        .left => .{ .a = .left, .b = .a },
        .right => .{ .a = .right, .b = .d },
    };
}

fn padNav(dir: NavDir) rl.GamepadButton {
    return switch (dir) {
        .up => .left_face_up,
        .down => .left_face_down,
        .left => .left_face_left,
        .right => .left_face_right,
    };
}

fn dirPressed(dir: NavDir, autoRepeat: bool) bool {
    const k = keyNav(dir);
    if (rl.isKeyPressed(k.a) or rl.isKeyPressed(k.b)) return true;
    if (autoRepeat and (rl.isKeyPressedRepeat(k.a) or rl.isKeyPressedRepeat(k.b))) return true;
    return padPressed(padNav(dir));
}

pub fn navPressed(dir: NavDir) bool {
    return dirPressed(dir, true);
}

// THE LEFT STICK AS A D-PAD, and getting this wrong is a known genre of bug — a stick is a LEVEL where a
// walk wants EDGES, so the naive reading fires a step every frame the stick is anywhere but centre. Four
// standard pieces, all of them here:
//
//  1. A RADIAL magnitude, never per-axis. Testing the axes separately is the "snap to grid" mistake: the
//     corner of the square passes at 0.62 on each axis while the true deflection is 0.88, so a lazy diagonal
//     reads as a hard push.
//  2. A SCHMITT TRIGGER, not one threshold. It arms at `STICK_FIRE` and does not re-arm until the stick has
//     fallen back under `STICK_REARM`; one threshold chatters across itself on the way past.
//  3. DAS then ARR (the falling-block idiom): a held push waits `STICK_DAS` before it repeats and then goes
//     every `STICK_ARR`, so a nudge is exactly one step and a hold is a readable crawl.
//  4. A DEAD CONE AT THE DIAGONALS. Inside 32° of an axis is that direction; outside it is NOTHING. Letting
//     the bigger component win means a 46° push picks one of two nodes that are nowhere near each other on
//     a wheel, which is the whole of "imprecise".
//
// …plus one this layout needed: a direction CHANGE without returning to centre does not fire on the frame it
// turns. Rolling a thumb round the rim crosses all four quadrants, and firing each one is the twitch.
const STICK_FIRE: f32 = 0.72;
const STICK_REARM: f32 = 0.42;
const STICK_CONE: f32 = 0.848; // cos 32° — the half-angle a push must sit inside to count as an axis
const STICK_DAS: f32 = 0.42; // seconds a held push waits before it starts repeating
const STICK_ARR: f32 = 0.20; // …and the gap between repeats after that

var stickDir: ?NavDir = null;
var stickWait: f32 = 0;
/// Has the stick been back to centre since the last step — what makes the FIRST push instant and every
/// direction rolled into after it deliberate.
var stickArmed: bool = true;

/// The direction the left stick is asking for THIS frame, or null. Call once a frame; it owns its own clock.
pub fn stickStep(dt: f32) ?NavDir {
    if (!rl.isGamepadAvailable(0)) {
        stickDir = null;
        stickArmed = true;
        return null;
    }
    const x = rl.getGamepadAxisMovement(0, .left_x);
    const y = rl.getGamepadAxisMovement(0, .left_y);
    const mag = @sqrt(x * x + y * y);
    if (mag < STICK_REARM) { // home again: everything resets, and the next push is instant
        stickDir = null;
        stickArmed = true;
        return null;
    }
    if (mag < STICK_FIRE) return null; // inside the hysteresis band: neither fires nor resets

    const nx = x / mag;
    const ny = y / mag;
    const dir: ?NavDir = if (@abs(nx) >= STICK_CONE)
        (if (nx > 0) .right else .left)
    else if (@abs(ny) >= STICK_CONE)
        (if (ny > 0) .down else .up)
    else
        null; // a diagonal is not a direction — hold, and step nothing
    const d = dir orelse return null;

    if (stickDir != d) {
        stickDir = d;
        stickWait = STICK_DAS;
        if (!stickArmed) return null; // rolled into it: it costs a full DAS, exactly as a repeat would
        stickArmed = false;
        return d;
    }
    stickWait -= dt;
    if (stickWait > 0) return null;
    stickWait = STICK_ARR;
    return d;
}

/// The RIGHT stick's zoom axis, −1 (out) … +1 (in). Pushing UP zooms IN. VERTICAL-DOMINANT: a sideways push
/// on the look stick is not a request to zoom, and on this screen there is nothing else for it to mean.
pub fn stickZoom() f32 {
    var v: f32 = 0;
    if (rl.isGamepadAvailable(0)) {
        const x = rl.getGamepadAxisMovement(0, .right_x);
        const y = rl.getGamepadAxisMovement(0, .right_y);
        if (@abs(y) > 0.22 and @abs(y) > @abs(x)) v = -y;
    }
    // …and the wheel, because the tree is read on a desk as often as on a pad.
    const notch = rl.getMouseWheelMove();
    if (notch != 0) v = mathx.clampF(v + notch * 0.6, -1, 1);
    return v;
}

fn adjTapped(dir: NavDir) bool {
    return dirPressed(dir, false);
}

fn adjHeldDir() i32 {
    var dir: i32 = 0;
    const l = keyNav(.left);
    const r = keyNav(.right);
    if (rl.isKeyDown(l.a) or rl.isKeyDown(l.b)) dir -= 1;
    if (rl.isKeyDown(r.a) or rl.isKeyDown(r.b)) dir += 1;
    if (dir == 0) {
        if (padDown(padNav(.left))) dir -= 1;
        if (padDown(padNav(.right))) dir += 1;
    }
    return dir;
}

fn coarseHeld() bool {
    if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) return true;
    return padDown(.left_trigger_1);
}

/// THE PAGE TURN — the shoulders, and Q/E for the keyboard. It cannot be Left/Right: those move a grid
/// cursor in the book, and on the stats page they turn him on the spot.
fn tabPressed(dir: i32) bool {
    const back = dir < 0;
    if (rl.isKeyPressed(if (back) .q else .e)) return true;
    return padPressed(if (back) .left_trigger_1 else .right_trigger_1);
}

/// Confirm HELD, not tapped — the book's slots sink for as long as the button is down.
fn confirmHeld() bool {
    const altHeld = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    if ((rl.isKeyDown(.enter) and !altHeld) or rl.isKeyDown(.space)) return true;
    return padDown(hud.padOf(hud.BTN_CONFIRM)); // the HELD half off the same name as the tap
}

/// THE QUICK BUTTON, off the same name the cribs draw. The tree page's Level Up, and nothing else in the
/// menu asks for it yet. R is the keyboard's, free because the book has no other letter binding.
pub fn quickPressed() bool {
    if (rl.isKeyPressed(.r)) return true;
    return padPressed(hud.padOf(hud.BTN_QUICK));
}

pub fn confirmPressed() bool {
    // ALT+Enter is the game loop's borderless-fullscreen toggle, so Enter must not ALSO confirm the highlighted row while Alt is down.
    const altHeld = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    if ((rl.isKeyPressed(.enter) and !altHeld) or rl.isKeyPressed(.space)) return true;
    // …and the pad press comes off the NAME the cribs draw (`hud.BTN_CONFIRM`), not a second literal beside it.
    return padPressed(hud.padOf(hud.BTN_CONFIRM));
}

pub fn backPressed() bool {
    // Esc is routed by the game loop (onEscape); pad B backs out here — off `hud.BTN_BACK`, as above.
    return padPressed(hud.padOf(hud.BTN_BACK));
}
