const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const hud = @import("hud.zig");
const mathx = @import("../core/mathx.zig");
const rumblemod = @import("../core/rumble.zig");
const sfx = @import("../core/audio.zig");
const item = @import("../play/item.zig");
const uiart = @import("uiart.zig");
const bookmod = @import("book.zig");
const daynight = @import("../world/daynight.zig");
const weathermod = @import("../world/weather.zig");
const savemod = @import("../save.zig");

const rgba = mathx.rgba;

const padPressed = rumblemod.padPressed;
const padDown = rumblemod.padDown;


pub const Action = union(enum) {
    none,
    quit,
    toTitle,
    editor,
    newGame: usize,
    loadGame: usize,
    deleteSlot: usize,
    use: item.Kind,
    arm: bookmod.Action,
};

const Screen = enum {
    closed,
    boot,
    slots,
    main,
    options,
    debug,
    retro,
    character,
};

const OPT_MIX = [_]sfx.Submix{ .ambience, .sfx, .combat };
comptime {
    if (OPT_MIX.len != @typeInfo(sfx.Submix).@"enum".fields.len) @compileError("Options is missing a submix row");
}
const OPT_CLOSE = OPT_MIX.len;
const OPT_COUNT = OPT_CLOSE + 1;

const DBG_RETRO = 0;
const DBG_STATS = 1;
const DBG_WIREFRAME = 2;
const DBG_HITBOX = 3;
const DBG_HOUR = 4;
const DBG_DAYRATE = 5;
const DBG_TIMESCALE = 6;
/// **THE SKY'S OWN EVENTS, ON DEMAND** — `DBG_HOUR`'s arrangement one system along, and for its exact reason.
/// Weather arrives on a clock measured in MINUTES, so "is the rain working" is not a question anybody can sit
/// and answer; Confirm cycles dry → gentle → moderate → dry (`weather.Weather.cycleForce`). A row and not a
/// submenu, because the whole point is to watch the sky while you turn it.
const DBG_WEATHER = 7;
const DBG_FOG = 8;
const DBG_CLOSE = 9;
const DBG_COUNT = DBG_CLOSE + 1;

const Fog = enum { auto, off, thick, soup };
fn fogMulOf(f: Fog) f32 {
    return switch (f) {
        .auto => 1.0,
        .off => 0.0,
        .thick => 2.5,
        .soup => 6.0,
    };
}

const HOUR_TAP: f32 = 0.25;
const HOUR_COARSE: f32 = 1.0;
const HOUR_GLIDE: f32 = 6.0;

const RET_PRESET_PS1 = gfx.RETRO_COUNT + 0;
const RET_PRESET_CRT = gfx.RETRO_COUNT + 1;
const RET_PRESET_VHS = gfx.RETRO_COUNT + 2;
const RET_PRESET_GB = gfx.RETRO_COUNT + 3;
const RET_RESET = gfx.RETRO_COUNT + 4;
const RET_ALL_OFF = gfx.RETRO_COUNT + 5;
const RET_CLOSE = gfx.RETRO_COUNT + 6;
const RET_COUNT = RET_CLOSE + 1;

const ADJ_TAP: f32 = 0.01;
const ADJ_COARSE: f32 = 0.10;
const ADJ_GLIDE_DELAY: f32 = 0.35;
const ADJ_GLIDE_RATE: f32 = 0.25;

const MAIN_CONTINUE = 0;
const MAIN_OPTIONS = 1;
const MAIN_EDITOR = 2;
const MAIN_DEBUG = 3;
const MAIN_TITLE = 4;
const MAIN_COUNT = MAIN_TITLE + 1;

const BOOT_NEW = 0;
const BOOT_LOAD = 1;
const BOOT_OPTIONS = 2;
const BOOT_EDITOR = 3;
const BOOT_QUIT = 4;
const BOOT_COUNT = BOOT_QUIT + 1;

const SLOT_BACK = savemod.SLOTS;
const SLOT_COUNT = SLOT_BACK + 1;

const SlotIntent = enum { load, new };

const CARD_INSET: i32 = 14;

const SLOT_THUMB_W: i32 = 144;
const SLOT_THUMB_H: i32 = 90;
const SLOT_H: i32 = SLOT_THUMB_H + 16;
const SLOT_GAP: i32 = 8;
const SLOT_TEXT_GAP: i32 = 18;
/// WHERE A ROW'S CONTENT SITS, measured from the HILITE's left edge and shared by both kinds of card — so the
/// picker's thumbnail starts exactly where an ordinary row's label starts. Written once rather than at each
/// call site: the picker laid its picture out at the hilite inset instead and it came out over the cursor bar
/// (`uiart.caret`, which is what marks a row).
const ROW_LABEL: i32 = 26;

const VEIL = rgba(6, 6, 9, 150);
const BOOT_VEIL = rgba(5, 5, 8, 168);
const CARD = rgba(16, 15, 13, 232);
// THE INK IS `uiart`'s, not a second copy of it — that file's four weights exist so the menu card and the
// character book cannot drift into two greys.
const TEXT_DIM = uiart.TEXT_DIM;
/// A row that cannot be pressed, at the character book's own inert weight rather than a fifth grey.
const TEXT_OFF = mathx.withAlpha(uiart.TEXT_DIM, 70);
const TEXT_HOT = uiart.HOT;
const TITLE_COL = uiart.TEXT_TITLE;
const HINT_COL = uiart.TEXT_HINT;
const BAR_EDGE = rgba(120, 104, 74, 160);
const BAR_FILL = rgba(198, 164, 96, 220);

pub const Menu = struct {
    screen: Screen = .boot,
    home: Screen = .boot,
    slotIntent: SlotIntent = .load,
    askDelete: bool = false,
    cursor: usize = 0,
    stats: bool = false,
    wireframe: bool = false,
    hitboxes: bool = false,
    timeScale: f32 = 1.0,
    fog: Fog = .auto,
    adjHoldT: f32 = 0,
    book: bookmod.Book = .{},

    pub fn isOpen(self: *const Menu) bool {
        return self.screen != .closed;
    }

    pub fn booting(self: *const Menu) bool {
        return self.root() == .boot;
    }

    fn root(self: *const Menu) Screen {
        return switch (self.screen) {
            .closed => .closed,
            .boot, .slots => .boot,
            .main, .debug, .retro => .main,
            .options => self.home,
            .character => .character,
        };
    }

    fn leavingSound(self: *Menu) void {
        if (self.screen == .options) sfx.saveSettings();
    }

    pub fn onEscape(self: *Menu) void {
        if (self.screen == .boot) return;
        if (self.screen == .character and self.book.onBack()) return;
        self.leavingSound();
        self.cursor = 0;
        if (self.screen == .slots) unloadShots();
        self.screen = switch (self.screen) {
            .boot => .boot,
            .closed => .main,
            .main, .character => .closed,
            .options => self.home,
            .slots => .boot,
            .debug => .main,
            .retro => .debug,
        };
    }

    pub fn toTitle(self: *Menu) void {
        self.home = .boot;
        self.cursor = 0;
        self.screen = .boot;
    }

    pub fn onSelectButton(self: *Menu) void {
        if (self.booting()) return; // a game that has not been started cannot be paused
        self.leavingSound();
        self.cursor = 0;
        self.screen = if (self.root() == .main) .closed else .main;
    }

    pub fn onStartButton(self: *Menu) void {
        if (self.booting()) return;
        self.leavingSound();
        self.cursor = 0;
        if (self.root() == .character) {
            self.screen = .closed;
            return;
        }
        self.screen = .character;
        self.book.opened();
    }

    pub fn started(self: *Menu) void {
        unloadShots();
        self.home = .main;
        self.cursor = 0;
        self.screen = .closed;
    }

    fn rowLive(self: *const Menu, i: usize, shelf: *const savemod.Shelf) bool {
        return switch (self.screen) {
            .boot => switch (i) {
                BOOT_LOAD => shelf.any(),
                BOOT_NEW => !shelf.full(),
                else => true,
            },
            .slots => i >= savemod.SLOTS or switch (self.slotIntent) {
                .load => shelf.head[i] != null,
                .new => shelf.head[i] == null,
            },
            else => true,
        };
    }

    fn rowCount(self: *const Menu) usize {
        return switch (self.screen) {
            .closed, .character => 0,
            .boot => BOOT_COUNT,
            .slots => SLOT_COUNT,
            .main => MAIN_COUNT,
            .options => OPT_COUNT,
            .debug => DBG_COUNT,
            .retro => RET_COUNT,
        };
    }

    // dt is the REAL frame time (not time-scaled) so the glide speed never changes.
    pub fn update(self: *Menu, retro: *gfx.Retro, day: *daynight.Clock, sky: *weathermod.Weather, dt: f32, v: bookmod.View, shelf: *const savemod.Shelf) Action {
        if (self.screen == .closed) return .none;
        if (self.screen == .character) return self.updateBook(dt, v);
        const rows = self.rowCount();
        if (rows == 0) return .none;
        const wasRow = self.cursor;
        if (navPressed(.up)) {
            self.cursor = (self.cursor + rows - 1) % rows;
            sfx.play(.menu_move);
        }
        if (navPressed(.down)) {
            self.cursor = (self.cursor + 1) % rows;
            sfx.play(.menu_move);
        }
        if (self.cursor != wasRow) self.askDelete = false;

        if (self.screen == .slots) {
            if (self.askDelete) {
                if (backPressed()) {
                    self.askDelete = false;
                    sfx.play(.menu_back);
                    return .none;
                }
                if (confirmPressed()) {
                    self.askDelete = false;
                    if (self.cursor < savemod.SLOTS and shelf.head[self.cursor] != null) {
                        sfx.play(.menu_pick);
                        return .{ .deleteSlot = self.cursor };
                    }
                    sfx.play(.menu_back);
                }
                return .none;
            }
            if (deletePressed() and self.cursor < savemod.SLOTS and shelf.head[self.cursor] != null) {
                self.askDelete = true;
                sfx.play(.menu_pick);
                return .none;
            }
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
        if (self.screen == .debug and self.cursor == DBG_DAYRATE) {
            if (adjTapped(.left) or adjTapped(.right)) day.cycleSpeed();
        }
        if (self.screen == .debug and self.cursor == DBG_FOG) {
            if (adjTapped(.left) or adjTapped(.right)) self.cycleFog();
        }
        // THE HOUR. Its own delta rather than `adjustDelta`'s, which is scaled for a 0..1 dial: an hour is not
        // a hundredth of anything, and a tap of 0.01 h is nine game seconds — a control that does nothing.
        if (self.screen == .debug and self.cursor == DBG_HOUR) {
            const step: f32 = if (coarseHeld()) HOUR_COARSE else HOUR_TAP;
            if (adjTapped(.left)) day.nudge(-step);
            if (adjTapped(.right)) day.nudge(step);
            const dir = adjHeldDir();
            if (dir != 0) {
                self.adjHoldT += dt;
                if (self.adjHoldT > ADJ_GLIDE_DELAY) day.nudge(@as(f32, @floatFromInt(dir)) * HOUR_GLIDE * dt);
            }
        }

        if (confirmPressed()) {
            if (!self.rowLive(self.cursor, shelf)) {
                sfx.play(.menu_back);
                return .none;
            }
            sfx.play(.menu_pick);
            return self.confirm(retro, day, sky);
        }
        if (backPressed()) {
            sfx.play(.menu_back);
            self.onEscape();
        }
        return .none;
    }

    fn updateBook(self: *Menu, dt: f32, v: bookmod.View) Action {
        if (tabPressed(-1)) self.book.onTab(-1);
        if (tabPressed(1)) self.book.onTab(1);
        const nav = navFor(self.book.wheelUp());
        if (nav(.up)) self.book.move(0, -1, v);
        if (nav(.down)) self.book.move(0, 1, v);
        if (nav(.left)) self.book.move(-1, 0, v);
        if (nav(.right)) self.book.move(1, 0, v);
        if (stickPush(dt, self.book.wheelUp())) |d| self.book.move(d.x, d.y, v);
        self.book.spinBy(adjHeldDir(), dt);
        self.book.panBy(stickPan(), dt);
        self.book.zoomBy(dpadZoom(), dt);
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

    fn openSlots(self: *Menu, why: SlotIntent) void {
        self.slotIntent = why;
        self.screen = .slots;
        self.cursor = 0;
        self.askDelete = false;
        loadShots();
    }

    pub fn slotsChanged(self: *Menu) void {
        self.askDelete = false;
        if (self.screen == .slots) loadShots();
    }

    pub fn showSlotsForShot(self: *Menu, why: SlotIntent, row: usize) void {
        self.openSlots(why);
        self.cursor = row;
    }

    pub fn armDeleteForShot(self: *Menu) void {
        self.askDelete = true;
    }

    fn confirm(self: *Menu, retro: *gfx.Retro, day: *daynight.Clock, sky: *weathermod.Weather) Action {
        switch (self.screen) {
            .closed => {},
            .boot => switch (self.cursor) {
                BOOT_NEW => self.openSlots(.new),
                BOOT_LOAD => self.openSlots(.load),
                BOOT_OPTIONS => {
                    self.home = .boot;
                    self.screen = .options;
                    self.cursor = 0;
                },
                BOOT_EDITOR => return .editor,
                BOOT_QUIT => return .quit,
                else => {},
            },
            .slots => {
                if (self.cursor >= savemod.SLOTS) {
                    unloadShots();
                    self.screen = .boot;
                    self.cursor = 0;
                } else return switch (self.slotIntent) {
                    .load => .{ .loadGame = self.cursor },
                    .new => .{ .newGame = self.cursor },
                };
            },
            .main => switch (self.cursor) {
                MAIN_CONTINUE => self.screen = .closed,
                MAIN_OPTIONS => {
                    self.home = .main;
                    self.screen = .options;
                    self.cursor = 0;
                },
                MAIN_EDITOR => {
                    self.screen = .closed;
                    return .editor;
                },
                MAIN_DEBUG => {
                    self.screen = .debug;
                    self.cursor = 0;
                },
                MAIN_TITLE => return .toTitle,
                else => {},
            },
            .options => {
                if (self.cursor == OPT_CLOSE) {
                    self.leavingSound();
                    self.screen = self.home;
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
                DBG_HOUR => day.freeze(!day.frozen()),
                DBG_DAYRATE => day.cycleSpeed(),
                DBG_TIMESCALE => self.cycleTimeScale(),
                DBG_WEATHER => sky.cycleForce(),
                DBG_FOG => self.cycleFog(),
                DBG_CLOSE => {
                    self.screen = .main;
                    self.cursor = 0;
                },
                else => {},
            },
            .character => {},
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
                else => {},
            },
        }
        return .none;
    }

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

    pub fn forceFog(self: *Menu, on: bool) void {
        self.fog = if (on) .soup else .auto;
    }

    fn cycleFog(self: *Menu) void {
        self.fog = switch (self.fog) {
            .auto => .off,
            .off => .thick,
            .thick => .soup,
            .soup => .auto,
        };
    }

    pub fn fogK(self: *const Menu) f32 {
        return fogMulOf(self.fog);
    }

    pub fn fogAmt(self: *const Menu, wet: f32) f32 {
        return switch (self.fog) {
            .auto => wet,
            .off => 0,
            .thick => 0.65,
            .soup => 1.0,
        };
    }

    fn debugLabels(self: *const Menu, day: *const daynight.Clock, sky: *const weathermod.Weather) [DBG_COUNT][:0]const u8 {
        var out: [DBG_COUNT][:0]const u8 = undefined;
        out[DBG_RETRO] = "Retro Filters >";
        out[DBG_STATS] = if (self.stats) "Stats: On" else "Stats: Off";
        out[DBG_WIREFRAME] = if (self.wireframe) "Wireframe: On" else "Wireframe: Off";
        out[DBG_HITBOX] = if (self.hitboxes) "Hitboxes: On" else "Hitboxes: Off";
        var clock: [8]u8 = undefined;
        out[DBG_HOUR] = std.fmt.bufPrintZ(&dbgHourBuf, "Hour: {s} {s}{s}", .{
            daynight.clockText(day.hour, &clock),
            daynight.phaseName(day.hour),
            if (day.frozen()) " (held)" else "",
        }) catch "?";
        // …and the SPEED, said as a day's length rather than as a multiplier: what you are about to watch is the
        // sky going round, and "10 s/day" is that where "120x" is arithmetic.
        var len: [12]u8 = undefined;
        out[DBG_DAYRATE] = std.fmt.bufPrintZ(&dbgRateBuf, "Day Speed: {d:.0}x — {s}/day{s}", .{
            day.speed(),
            daynight.dayLenText(day, &len),
            if (day.frozen()) " (held)" else "",
        }) catch "?";
        out[DBG_TIMESCALE] = std.fmt.bufPrintZ(&dbgTimeBuf, "Time Scale: {d:.0}%", .{self.timeScale * 100}) catch "?";
        // Read off the STORM itself rather than a flag kept here, so the row cannot say one thing while the
        // sky does another — `DBG_HOUR`'s own rule, which reads the clock rather than remembering it.
        out[DBG_WEATHER] = sky.says();
        out[DBG_FOG] = switch (self.fog) {
            .auto => "Fog: Auto (weather)",
            .off => "Fog: Off",
            .thick => "Fog: Thick",
            .soup => "Fog: Soup",
        };
        out[DBG_CLOSE] = "Back";
        return out;
    }

    pub fn draw(self: *const Menu, retro: *const gfx.Retro, day: *const daynight.Clock, sky: *const weathermod.Weather, v: bookmod.View, portrait: ?bookmod.Portrait, shelf: *const savemod.Shelf) void {
        if (self.screen == .closed) return;
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        const boot = self.booting();
        rl.drawRectangle(0, 0, sw, sh, if (boot) BOOT_VEIL else VEIL);
        const lb = @divTrunc(sh, if (boot) @as(i32, 6) else 8);
        const lbA: u8 = if (boot) 180 else 140;
        rl.drawRectangleGradientV(0, 0, sw, lb, rgba(0, 0, 0, lbA), rgba(0, 0, 0, 0));
        rl.drawRectangleGradientV(0, sh - lb, sw, lb, rgba(0, 0, 0, 0), rgba(0, 0, 0, lbA));
        if (self.screen == .character) {
            bookmod.draw(&self.book, v, portrait);
            return;
        }
        switch (self.screen) {
            .closed, .character => {},
            .boot => self.drawCard("SOULSLIKE", &bootLabels(), .{
                .dim = &bootDim(self, shelf),
                .note = if (shelf.full()) BOOT_NOTE_FULL else if (shelf.any()) BOOT_NOTE else BOOT_NOTE_EMPTY,
            }),
            .slots => self.drawSlots(shelf),
            .main => self.drawCard("SOULSLIKE", &mainLabels(), .{}),
            .options => self.drawCard("SOUND", &optionLabels(), .{ .gauges = &soundLevels() }),
            .debug => self.drawCard("DEBUG", &self.debugLabels(day, sky), .{}),
            .retro => self.drawCard("RETRO FILTERS", &retroLabels(retro), .{ .gauges = retro.values[0..gfx.RETRO_COUNT] }),
        }
        const bootHints = [_]hud.Hint{
            .{ .glyph = .{ .dpad = .updown }, .label = "Move" },
            .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Select" },
        };
        const slotHints = [_]hud.Hint{
            .{ .glyph = .{ .dpad = .updown }, .label = "Move" },
            .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Select" },
            .{ .glyph = .{ .face = hud.BTN_QUICK }, .label = "Delete" },
            .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Back" },
        };
        const askHints = [_]hud.Hint{
            .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Delete" },
            .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Keep" },
        };
        const hints = [_]hud.Hint{
            .{ .glyph = .{ .dpad = .updown }, .label = "Move" },
            .{ .glyph = .{ .dpad = .leftright }, .label = "Adjust" },
            .{ .glyph = .{ .bumper = "LB" }, .label = "Coarse" },
            .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Select" },
            .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Back" },
            .{ .glyph = .menu, .label = "Character" },
        };
        const row: []const hud.Hint = switch (self.screen) {
            .boot => &bootHints,
            .slots => if (self.askDelete) &askHints else &slotHints,
            else => &hints,
        };
        hud.hintRow(row, sh - @divTrunc(hud.lineH(hud.HINT), 2) - 14, hud.HINT, HINT_COL);
    }

    fn drawSlots(self: *const Menu, shelf: *const savemod.Shelf) void {
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        const headerH: i32 = hud.lineH(hud.TITLE) + 22;
        const backH: i32 = hud.lineH(hud.BODY) + 14;
        const cardW: i32 = 640;
        const cardH: i32 = headerH + (SLOT_H + SLOT_GAP) * @as(i32, savemod.SLOTS) + backH + 30;
        const cx = @divTrunc(sw - cardW, 2);
        const cy = @divTrunc(sh - cardH, 2);
        uiart.seat(cx, cy, cardW, cardH);
        uiart.plate(cx, cy, cardW, cardH, CARD.a);
        uiart.frame(cx, cy, cardW, cardH, uiart.flick(200, cx));
        uiart.divider(cx + @divTrunc(cardW, 2), cy + hud.lineH(hud.TITLE) + 10, @divTrunc(cardW, 2) - 24, 180);
        const title: [:0]const u8 = if (self.slotIntent == .new) "NEW GAME" else "LOAD GAME";
        const tw = hud.textW(title, hud.TITLE);
        hud.engraved(title, cx + @divTrunc(cardW - tw, 2), cy + 12, hud.TITLE, TITLE_COL);

        for (0..savemod.SLOTS) |i| {
            const y = cy + headerH + (SLOT_H + SLOT_GAP) * @as(i32, @intCast(i));
            self.drawSlotRow(i, shelf.head[i], !self.rowLive(i, shelf), cx + CARD_INSET, y, cardW - CARD_INSET * 2);
        }
        const by = cy + headerH + (SLOT_H + SLOT_GAP) * @as(i32, savemod.SLOTS) + 8;
        const onBack = self.cursor == SLOT_BACK;
        if (onBack) uiart.rowHilite(cx + CARD_INSET, by - 3, cardW - CARD_INSET * 2, backH);
        hud.text("Back", cx + CARD_INSET + ROW_LABEL, by, hud.BODY, if (onBack) TEXT_HOT else TEXT_DIM);
    }

    fn drawSlotRow(self: *const Menu, i: usize, head: ?savemod.Head, dead: bool, x: i32, y: i32, w: i32) void {
        const on = self.cursor == i;
        if (on and !dead) {
            uiart.rowHilite(x, y, w, SLOT_H);
            rl.drawRectangle(x, y, w, 1, mathx.withAlpha(uiart.GILT, 70));
            rl.drawRectangle(x, y + SLOT_H - 1, w, 1, mathx.withAlpha(uiart.GILT, 46));
            uiart.diamond(@floatFromInt(x + 2), @floatFromInt(y + 3), 2.6, uiart.GILT_BRIGHT);
            uiart.diamond(@floatFromInt(x + 2), @floatFromInt(y + SLOT_H - 3), 2.6, uiart.GILT_BRIGHT);
        } else if (on) {
            uiart.caret(x, y, SLOT_H, uiart.CARET_DIM);
        }
        const px = x + ROW_LABEL;
        const py = y + @divTrunc(SLOT_H - SLOT_THUMB_H, 2);
        rl.drawRectangle(px, py, SLOT_THUMB_W, SLOT_THUMB_H, rgba(6, 5, 4, 220));
        if (if (head == null) null else slotTex[i]) |tex| {
            const src = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(tex.width), .height = @floatFromInt(tex.height) };
            const dst = rl.Rectangle{
                .x = @floatFromInt(px),
                .y = @floatFromInt(py),
                .width = @floatFromInt(SLOT_THUMB_W),
                .height = @floatFromInt(SLOT_THUMB_H),
            };
            const tint = if (dead or !on) mathx.withAlpha(rl.Color.white, 190) else rl.Color.white;
            rl.drawTexturePro(tex, src, dst, .{ .x = 0, .y = 0 }, 0, tint);
        }
        rl.drawRectangleLines(px, py, SLOT_THUMB_W, SLOT_THUMB_H, BAR_EDGE);

        const tx = px + SLOT_THUMB_W + SLOT_TEXT_GAP;
        const col = if (dead) TEXT_OFF else if (on) TEXT_HOT else TEXT_DIM;
        var nameBuf: [24]u8 = undefined;
        const name = std.fmt.bufPrintZ(&nameBuf, "Slot {d}", .{i + 1}) catch "Slot";
        hud.text(name, tx, py + 2, hud.BODY, col);

        if (self.askDelete and on and head != null) {
            hud.text("Delete this slot?", tx, py + hud.lineH(hud.BODY) + 6, hud.SMALL, uiart.BAD);
            return;
        }
        if (head) |h| {
            var timeBuf: [16]u8 = undefined;
            var lineBuf: [64]u8 = undefined;
            const line = std.fmt.bufPrintZ(&lineBuf, "Level {d}   {d} souls   {s}", .{
                h.level,
                h.souls,
                playtimeText(h.playtime, &timeBuf),
            }) catch "?";
            hud.text(line, tx, py + hud.lineH(hud.BODY) + 6, hud.SMALL, if (on) uiart.TEXT_VALUE else TEXT_DIM);
        } else {
            hud.text("Empty", tx, py + hud.lineH(hud.BODY) + 6, hud.SMALL, TEXT_OFF);
        }
    }

    fn drawCard(self: *const Menu, title: [:0]const u8, labels: []const [:0]const u8, card: Card) void {
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        const compact = labels.len > 8;
        const fontSize: i32 = if (compact) hud.SMALL else hud.BODY;
        const rowH: i32 = hud.lineH(fontSize) + (if (compact) @as(i32, 2) else @as(i32, 14));
        const rowGap: i32 = if (compact) 2 else 8;
        const headerH: i32 = hud.lineH(hud.TITLE) + 22;
        const noteH: i32 = if (card.note != null) hud.lineH(hud.HINT) + 14 else 0;
        const footH: i32 = 20 + noteH;
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
            const dead = if (card.dim) |d| i < d.len and d[i] else false;
            const col = if (dead) TEXT_OFF else if (selected) TEXT_HOT else TEXT_DIM;
            if (selected and !dead) {
                uiart.rowHilite(cx + CARD_INSET, y - 3, cardW - CARD_INSET * 2, rowH);
                rl.drawRectangle(cx + CARD_INSET, y - 3, cardW - CARD_INSET * 2, 1, mathx.withAlpha(uiart.GILT, 70));
                rl.drawRectangle(cx + CARD_INSET, y - 4 + rowH, cardW - CARD_INSET * 2, 1, mathx.withAlpha(uiart.GILT, 46));
                uiart.diamond(@floatFromInt(cx + CARD_INSET + 2), @floatFromInt(y), 2.6, uiart.GILT_BRIGHT);
                uiart.diamond(@floatFromInt(cx + CARD_INSET + 2), @floatFromInt(y - 3 + rowH), 2.6, uiart.GILT_BRIGHT);
            }
            if (selected and dead) uiart.caret(cx + CARD_INSET, y - 3, rowH, uiart.CARET_DIM);
            hud.text(label, cx + CARD_INSET + ROW_LABEL, y, fontSize, col);
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

const Card = struct {
    gauges: ?[]const f32 = null,
    note: ?[:0]const u8 = null,
    /// Drawn faint and with no hilite under it, but the cursor still LANDS on it: a row the cursor skips is
    /// a row you cannot read the reason for, and the reason is the whole of what the footnote is saying.
    dim: ?[]const bool = null,
};

fn drawGauge(x: i32, y: i32, w: i32, h: i32, v: f32, selected: bool) void {
    rl.drawRectangle(x, y, w, h, rgba(6, 5, 4, 200));
    rl.drawRectangleLines(x, y, w, h, BAR_EDGE);
    rl.drawRectangle(x + 1, y + 1, w - 2, 1, rgba(0, 0, 0, 130));
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

const BOOT_NOTE: [:0]const u8 = "Three slots. A bonfire saves over the one you are playing.";
const BOOT_NOTE_EMPTY: [:0]const u8 = "No save yet. Rest at a bonfire to write one.";
/// …and the one that says WHY New Game is dim. A greyed row the player cannot read the reason for is the
/// thing `Card.dim`'s own comment refuses, and "all three are written" is not visible from the boot screen.
const BOOT_NOTE_FULL: [:0]const u8 = "All three slots are written. Delete one to start a new game.";

fn bootLabels() [BOOT_COUNT][:0]const u8 {
    var out: [BOOT_COUNT][:0]const u8 = undefined;
    out[BOOT_NEW] = "New Game";
    out[BOOT_LOAD] = "Load Game";
    out[BOOT_OPTIONS] = "Options";
    out[BOOT_EDITOR] = "Editor";
    out[BOOT_QUIT] = "Quit";
    return out;
}

fn bootDim(self: *const Menu, shelf: *const savemod.Shelf) [BOOT_COUNT]bool {
    var out = [_]bool{false} ** BOOT_COUNT;
    for (0..BOOT_COUNT) |i| out[i] = !self.rowLive(i, shelf);
    return out;
}


var slotTex: [savemod.SLOTS]?rl.Texture2D = [_]?rl.Texture2D{null} ** savemod.SLOTS;

fn loadShots() void {
    unloadShots();
    for (0..savemod.SLOTS) |i| {
        slotTex[i] = rl.loadTexture(savemod.shotPath(i)) catch null;
    }
}

fn unloadShots() void {
    for (&slotTex) |*t| {
        if (t.*) |tex| rl.unloadTexture(tex);
        t.* = null;
    }
}

pub fn unload() void {
    unloadShots();
}

/// "2h 14m" — hours and minutes, never seconds. What a slot row is answering is "which of these have I
/// played", and a number that ticks is not what that question is asking.
fn playtimeText(secs: f32, buf: []u8) [:0]const u8 {
    const total: u32 = @intFromFloat(@max(0, secs));
    const h = total / 3600;
    const m = (total % 3600) / 60;
    if (h > 0) return std.fmt.bufPrintZ(buf, "{d}h {d}m", .{ h, m }) catch "?";
    return std.fmt.bufPrintZ(buf, "{d}m", .{m}) catch "?";
}

fn mainLabels() [MAIN_COUNT][:0]const u8 {
    var out: [MAIN_COUNT][:0]const u8 = undefined;
    out[MAIN_CONTINUE] = "Continue";
    out[MAIN_OPTIONS] = "Options >";
    out[MAIN_EDITOR] = "Editor";
    out[MAIN_DEBUG] = "Debug";
    out[MAIN_TITLE] = "Back to Title";
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

fn soundLevels() [OPT_MIX.len]f32 {
    var out: [OPT_MIX.len]f32 = undefined;
    for (OPT_MIX, 0..) |m, i| out[i] = sfx.volume(m);
    return out;
}

var dbgTimeBuf: [48]u8 = undefined;
var dbgHourBuf: [48]u8 = undefined;
var dbgRateBuf: [48]u8 = undefined;

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

// THE LEFT STICK AS A WALK, and getting this wrong is a known genre of bug — a stick is a LEVEL where a walk
// wants EDGES, so the naive reading fires a step every frame the stick is anywhere but centre. Four standard
// pieces, all of them here:
//  1. A RADIAL magnitude, never per-axis. Testing the axes separately is the "snap to grid" mistake: the
//     corner of the square passes at 0.62 on each axis while the true deflection is 0.88, so a lazy diagonal
//     reads as a hard push.
const STICK_FIRE: f32 = 0.72;
const STICK_REARM: f32 = 0.42;
const STICK_CONE: f32 = 0.848;
const STICK_DAS: f32 = 0.42;
const STICK_ARR: f32 = 0.20;
const AIM_TURN: f32 = 0.766;

var stickDir: ?rl.Vector2 = null;
var stickWait: f32 = 0;
var stickArmed: bool = true;

pub fn stickPush(dt: f32, radial: bool) ?rl.Vector2 {
    if (!rl.isGamepadAvailable(0)) {
        stickDir = null;
        stickArmed = true;
        return null;
    }
    const x = rl.getGamepadAxisMovement(0, .left_x);
    const y = rl.getGamepadAxisMovement(0, .left_y);
    const mag = @sqrt(x * x + y * y);
    if (mag < STICK_REARM) {
        stickDir = null;
        stickArmed = true;
        return null;
    }
    if (mag < STICK_FIRE) return null;

    const nx = x / mag;
    const ny = y / mag;
    const d: rl.Vector2 = if (radial)
        .{ .x = nx, .y = ny }
    else if (@abs(nx) >= STICK_CONE)
        .{ .x = std.math.sign(nx), .y = 0 }
    else if (@abs(ny) >= STICK_CONE)
        .{ .x = 0, .y = std.math.sign(ny) }
    else
        return null;

    const turned = if (stickDir) |was| (was.x * d.x + was.y * d.y) < AIM_TURN else true;
    if (turned) {
        stickDir = d;
        stickWait = STICK_DAS;
        if (!radial and !stickArmed) return null;
        stickArmed = false;
        return d;
    }
    stickWait -= dt;
    if (stickWait > 0) return null;
    stickWait = STICK_ARR;
    stickDir = d;
    return d;
}

const PAN_DEAD: f32 = 0.18;
pub fn stickPan() rl.Vector2 {
    if (!rl.isGamepadAvailable(0)) return .{ .x = 0, .y = 0 };
    const x = rl.getGamepadAxisMovement(0, .right_x);
    const y = rl.getGamepadAxisMovement(0, .right_y);
    const m = @sqrt(x * x + y * y);
    if (m < PAN_DEAD) return .{ .x = 0, .y = 0 };
    return .{ .x = x, .y = y };
}

pub fn dpadZoom() f32 {
    var v: f32 = 0;
    if (padDown(.left_face_up)) v += 1;
    if (padDown(.left_face_down)) v -= 1;
    const notch = rl.getMouseWheelMove();
    if (notch != 0) v = mathx.clampF(v + notch * 0.6, -1, 1);
    return v;
}

pub fn navPressedNoPad(dir: NavDir) bool {
    const k = keyNav(dir);
    return rl.isKeyPressed(k.a) or rl.isKeyPressed(k.b) or rl.isKeyPressedRepeat(k.a) or rl.isKeyPressedRepeat(k.b);
}

pub fn navFor(onWheel: bool) *const fn (NavDir) bool {
    return if (onWheel) &navPressedNoPad else &navPressed;
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

fn confirmHeld() bool {
    const altHeld = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    if ((rl.isKeyDown(.enter) and !altHeld) or rl.isKeyDown(.space)) return true;
    return padDown(hud.padOf(hud.BTN_CONFIRM));
}

fn deletePressed() bool {
    return rl.isKeyPressed(.delete) or padPressed(hud.padOf(hud.BTN_QUICK));
}

pub fn confirmPressed() bool {
    const altHeld = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    if ((rl.isKeyPressed(.enter) and !altHeld) or rl.isKeyPressed(.space)) return true;
    return padPressed(hud.padOf(hud.BTN_CONFIRM));
}

pub fn backPressed() bool {
    return padPressed(hud.padOf(hud.BTN_BACK));
}

test "A NEW CHARACTER NEEDS AN EMPTY SLOT, and Load needs a written one — exact inverses" {
    var m = Menu{};
    var sh = savemod.Shelf{};
    sh.head[0] = .{ .level = 7, .souls = 1240, .playtime = 8100 };

    m.screen = .slots;
    m.slotIntent = .load;
    try std.testing.expect(m.rowLive(0, &sh));
    try std.testing.expect(!m.rowLive(1, &sh));

    m.slotIntent = .new;
    try std.testing.expect(!m.rowLive(0, &sh));
    try std.testing.expect(m.rowLive(1, &sh));
    for (0..savemod.SLOTS) |i| {
        m.slotIntent = .load;
        const onLoad = m.rowLive(i, &sh);
        m.slotIntent = .new;
        try std.testing.expect(onLoad != m.rowLive(i, &sh));
    }
    try std.testing.expect(m.rowLive(SLOT_BACK, &sh));

    m.screen = .boot;
    try std.testing.expect(m.rowLive(BOOT_NEW, &sh));
    sh.head[1] = .{ .level = 1, .souls = 0, .playtime = 1 };
    sh.head[2] = .{ .level = 1, .souls = 0, .playtime = 1 };
    try std.testing.expect(!m.rowLive(BOOT_NEW, &sh));
    try std.testing.expect(m.rowLive(BOOT_LOAD, &sh));
    const dim = bootDim(&m, &sh);
    try std.testing.expect(dim[BOOT_NEW] and !dim[BOOT_LOAD]);

    const bare = savemod.Shelf{};
    try std.testing.expect(m.rowLive(BOOT_NEW, &bare));
    try std.testing.expect(!m.rowLive(BOOT_LOAD, &bare));
}
