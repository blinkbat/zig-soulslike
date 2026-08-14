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
const daynight = @import("daynight.zig"); // …and Debug carries the world clock's one scrub row
const savemod = @import("save.zig"); // …and the boot screen carries the three slots

const rgba = mathx.rgba;

const padPressed = rumblemod.padPressed;
const padDown = rumblemod.padDown;


/// The three swap actions are the BOOK's, passed straight through: the menu owns no game state and never
/// has, and an equipment screen that reached into the hero would be the first place it did. The two BOOT
/// actions keep the same split: this file says which row was pressed, `game.zig` is what starts a world.
pub const Action = union(enum) {
    none,
    quit,
    /// PUT THE TITLE BACK UP. Quit is the BOOT screen's row now — from inside a game the way out is the
    /// screen you came in through, and a running character is never more than a bonfire from being saved.
    toTitle,
    editor,
    /// …all three carrying WHICH SLOT, because with three of them the row pressed is only half the answer.
    newGame: usize,
    loadGame: usize,
    /// THROW A CHARACTER AWAY. Handed up like the other two rather than done here: the file is `save.zig`'s
    /// and the shelf is `game.zig`'s, and a menu that deleted one would be the first place this file touched
    /// the disk. It is already ARMED by the time it is returned — the picker asked, and this is the answer.
    deleteSlot: usize,
    use: item.Kind,
    arm: bookmod.Action,
};

const Screen = enum {
    closed,
    /// ── THE BOOT SCREEN, which is what the window opens on. It is NOT the pause card with different rows:
    /// there is no world behind it to go back to, so it has no Back and no Continue, and Select/Start are
    /// refused while it is up rather than gated at the call site.
    boot,
    /// THE THREE SLOTS, each shown by the picture taken at the fire it was written at. Reached from Load
    /// always, and from New Game only when all three are full — which is the one time starting a character
    /// is a decision about an existing one.
    slots,
    main, // ── the GAME menu (Select) …
    options,
    debug,
    retro,
    // THE SOUND FILTER RACK IS NOT HERE ANY MORE — it moved to the EDITOR, beside the jukebox, because it
    // is an authoring tool and not a setting: you turn a dial to hear what a voice becomes, and the one
    // place you can hear a voice on demand is the jukebox. The RETRO rack stays: that one is a LOOK the
    // player picks. See `editor.zig`'s `.jukebox` modal.
    character, // …and the CHARACTER BOOK (Start), which is `book.zig` end to end
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
/// THE WORLD CLOCK, scrubbed by hand: Left/Right walk the hour, Confirm holds it where it is. A row and not a
/// submenu, because there is exactly one number in it and the whole point is to watch the sky move while you
/// turn it — a card in the way would hide the thing being adjusted.
const DBG_HOUR = 4;
/// …AND HOW FAST IT RUNS ON ITS OWN, which is a different question from where it is pointed and gets its own
/// row for that reason. At the standard speed a day is twenty real minutes, so "does the clock move" is not a
/// thing you can sit and watch — this is the row that makes it one.
const DBG_DAYRATE = 5;
const DBG_TIMESCALE = 6;
const DBG_CLOSE = 7;
const DBG_COUNT = DBG_CLOSE + 1;

/// How far one tap of the hour row moves the clock, fine and coarse. A quarter hour is about the finest step
/// whose effect on the light you can actually see; an hour is the step for getting somewhere.
const HOUR_TAP: f32 = 0.25;
const HOUR_COARSE: f32 = 1.0;
/// …and how fast it runs while a direction is HELD — a whole day in about four seconds, so the sweep reads as
/// a sweep. This is the control the sky is really judged with.
const HOUR_GLIDE: f32 = 6.0;

const RET_PRESET_PS1 = gfx.RETRO_COUNT + 0;
const RET_PRESET_CRT = gfx.RETRO_COUNT + 1;
const RET_PRESET_VHS = gfx.RETRO_COUNT + 2;
const RET_PRESET_GB = gfx.RETRO_COUNT + 3;
const RET_RESET = gfx.RETRO_COUNT + 4;
const RET_ALL_OFF = gfx.RETRO_COUNT + 5;
const RET_CLOSE = gfx.RETRO_COUNT + 6;
const RET_COUNT = RET_CLOSE + 1;

// Slider feel: a TAP steps fine, Shift/LB-tap steps coarse, and HOLDING a direction glides after a delay.
const ADJ_TAP: f32 = 0.01;
const ADJ_COARSE: f32 = 0.10;
const ADJ_GLIDE_DELAY: f32 = 0.35; // seconds held before the glide kicks in
const ADJ_GLIDE_RATE: f32 = 0.25; // intensity per second while gliding

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

/// The picker: one row per slot, then Back.
const SLOT_BACK = savemod.SLOTS;
const SLOT_COUNT = SLOT_BACK + 1;

/// WHY THE PICKER IS UP, which is the whole of what a press on a row means.
const SlotIntent = enum { load, new };

/// HOW FAR A ROW'S HILITE IS INSET FROM THE PLATE. One number, because the picker lays itself out relative
/// to the hilite and the cards lay themselves out relative to the plate, and two literals that had to agree
/// is exactly how the caret ended up under the thumbnail.
const CARD_INSET: i32 = 14;

/// The thumbnail is the row's height, not the other way round: 16:10 to match the window the grab came off,
/// small enough that three of them and a Back row still centre on a short screen.
const SLOT_THUMB_W: i32 = 144;
const SLOT_THUMB_H: i32 = 90;
const SLOT_H: i32 = SLOT_THUMB_H + 16;
const SLOT_GAP: i32 = 8;
const SLOT_TEXT_GAP: i32 = 18; // picture to its two lines
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
    screen: Screen = .boot, // the window opens on the BOOT screen, and nothing is running behind it
    /// WHICH ROOT A SUB-SCREEN GOES BACK TO. Options hangs off both cards, so "one level up" is a different
    /// place depending on which one opened it — as a fixed `.main` it dropped you into the pause card of a
    /// game that had not been started.
    home: Screen = .boot,
    slotIntent: SlotIntent = .load,
    /// THE DELETE IS ARMED ON THE ROW THE CURSOR IS ON. Cleared by walking off it, by Back, and by opening
    /// the picker — an armed question that outlives the row it was asked about is one you answer by accident.
    askDelete: bool = false,
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

    /// IS THE BOOT SCREEN UP — this screen or anything hanging off it. The one predicate for "no world has
    /// been started yet", asked by every rule that must not fire before one has.
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

    /// Esc, and pad SELECT. The sound screen persists on the way out — the levels live in `settings.cfg`
    /// and are written when the screen closes, never per nudge. (The racks are written the same way by the
    /// editor's own rack panel, into the same file.)
    fn leavingSound(self: *Menu) void {
        if (self.screen == .options) sfx.saveSettings();
    }

    pub fn onEscape(self: *Menu) void {
        if (self.screen == .boot) return; // there is nothing behind it to escape to
        // Inside the book, Back closes an open picker first — one press, one level, like every other screen.
        if (self.screen == .character and self.book.onBack()) return;
        self.leavingSound();
        self.cursor = 0;
        if (self.screen == .slots) unloadShots(); // the three textures live no longer than the picker does
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

    /// FROM A RUNNING GAME BACK TO THE TITLE. The world behind is left exactly where it stood — nothing here
    /// tears it down, because the next New Game or Load builds one from scratch anyway, and until one of
    /// those is pressed the picture behind the card is as good a backdrop as any.
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

    /// Pad START — the CHARACTER BOOK (owner's call: "start menu will be character-driven").
    pub fn onStartButton(self: *Menu) void {
        if (self.booting()) return; // …and there is no character yet to open a book on
        self.leavingSound();
        self.cursor = 0;
        if (self.root() == .character) {
            self.screen = .closed;
            return;
        }
        self.screen = .character;
        self.book.opened();
    }

    /// A WORLD IS RUNNING NOW — the boot screen's one way out, taken by both New Game and Load Game.
    /// Options belongs to the pause card from here on, which is what `home` carries.
    pub fn started(self: *Menu) void {
        unloadShots(); // …and the picker's pictures go with it, whichever row started the world
        self.home = .main;
        self.cursor = 0;
        self.screen = .closed;
    }

    /// **CAN THIS ROW BE PRESSED** — the one predicate, read by the PRESS and by the card that draws it, so
    /// a row can never look available and do nothing. Two rows are ever refused and both for the same
    /// reason: there is no file behind them. NEW over an occupied slot is allowed — that is what the picker
    /// is being shown for.
    fn rowLive(self: *const Menu, i: usize, shelf: *const savemod.Shelf) bool {
        return switch (self.screen) {
            .boot => i != BOOT_LOAD or shelf.any(),
            .slots => i >= savemod.SLOTS or self.slotIntent == .new or shelf.head[i] != null,
            else => true,
        };
    }

    /// HOW MANY ROWS THE LIVE SCREEN HAS — asked by the cursor wrap AND by "is the cursor on Back".
    /// The book is not a row list and answers 0; it is driven whole, below.
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
    // `day` is handed in mutable for the retro dials' reason: the row adjusts a live thing, and the menu has no
    // business holding a second copy of the world's hour that would have to be pushed back on the way out.
    /// The `shelf` is handed in rather than surveyed off the disk here, for the reason nothing else in this
    /// file holds game state either: the menu draws what it is told. `game.zig` knows what is on the shelf,
    /// because writing a file is the only thing that puts anything on it.
    pub fn update(self: *Menu, retro: *gfx.Retro, day: *daynight.Clock, dt: f32, v: bookmod.View, shelf: *const savemod.Shelf) Action {
        if (self.screen == .closed) return .none;
        if (self.screen == .character) return self.updateBook(dt, v);
        const rows = self.rowCount();
        if (rows == 0) return .none; // a screen with no rows has no cursor to wrap (and no modulo to do)
        const wasRow = self.cursor;
        if (navPressed(.up)) {
            self.cursor = (self.cursor + rows - 1) % rows;
            sfx.play(.menu_move);
        }
        if (navPressed(.down)) {
            self.cursor = (self.cursor + 1) % rows;
            sfx.play(.menu_move);
        }
        // WALKING OFF THE ROW TAKES THE QUESTION WITH IT. Left armed, the next Confirm anywhere on the picker
        // would delete whatever the cursor had wandered onto.
        if (self.cursor != wasRow) self.askDelete = false;

        // **THE PICKER'S SECOND BUTTON, AND THE ONLY PRESS IN THE GAME THAT DESTROYS ANYTHING.** Armed on one
        // press and done on a second — and the second is the ordinary Confirm, because by then the row itself
        // has become the question and the button that answers a question is the one that answers this.
        if (self.screen == .slots) {
            if (self.askDelete) {
                if (backPressed()) {
                    self.askDelete = false;
                    sfx.play(.menu_back);
                    return .none;
                }
                if (confirmPressed()) {
                    self.askDelete = false;
                    // Re-asked at the press: the shelf is handed in fresh every frame, and a row that lost
                    // its file between the two presses is not a row to act on.
                    if (self.cursor < savemod.SLOTS and shelf.head[self.cursor] != null) {
                        sfx.play(.menu_pick);
                        return .{ .deleteSlot = self.cursor };
                    }
                    sfx.play(.menu_back);
                }
                return .none; // nothing else on this screen means anything while the question is up
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
            return self.confirm(retro, day);
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
        // The bumpers stay the PAGE TURN on every page, this one included — that is the whole reason the
        // zoom is not on them, and `navFor` is where the rest of that rule lives.
        const nav = navFor(self.book.wheelUp());
        if (nav(.up)) self.book.move(0, -1, v);
        if (nav(.down)) self.book.move(0, 1, v);
        if (nav(.left)) self.book.move(-1, 0, v);
        if (nav(.right)) self.book.move(1, 0, v);
        // …and the LEFT STICK. On the WHEEL it hands over the thumb's own bearing (`stickPush`'s `radial`) —
        // point at a node, go to that node; on every other page it is one of four, as those pages are.
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

    /// THE PICKER, AND THE PICTURES IT IS READ OFF. The textures are loaded HERE and dropped the moment it
    /// closes (`onEscape`, and the Back row): three screen-sized PNGs held for the life of the process to
    /// serve a screen nobody is on is the kind of thing that is never noticed and never freed.
    fn openSlots(self: *Menu, why: SlotIntent) void {
        self.slotIntent = why;
        self.screen = .slots;
        self.cursor = 0;
        self.askDelete = false;
        loadShots();
    }

    /// A SLOT WAS DELETED UNDER THE PICKER and its picture went with it, so the three textures are re-read.
    /// `game.zig`'s door: the shelf is its to re-survey and the pictures are this file's to hold.
    pub fn slotsChanged(self: *Menu) void {
        self.askDelete = false;
        if (self.screen == .slots) loadShots();
    }

    /// The harness's own door onto the picker: `--shot` never presses a row, and staging `screen = .slots`
    /// by hand skips the texture load, so the shot comes out with three empty plates.
    pub fn showSlotsForShot(self: *Menu, why: SlotIntent, row: usize) void {
        self.openSlots(why);
        self.cursor = row;
    }

    /// …and onto the ARMED delete, for the same reason: the harness presses no buttons, and this is the one
    /// state of this screen where a wrong press destroys something.
    pub fn armDeleteForShot(self: *Menu) void {
        self.askDelete = true;
    }

    /// The SHELF is not a parameter here any more: the only row that read it was New Game's first-free
    /// shortcut, and both boot rows now ask which slot instead. `rowLive` is where the shelf still decides
    /// anything, and that is asked before this is ever reached.
    fn confirm(self: *Menu, retro: *gfx.Retro, day: *daynight.Clock) Action {
        switch (self.screen) {
            .closed => {},
            // THE BOOT ROWS HAND BACK AN ACTION AND CHANGE NOTHING. Starting a world is `game.zig`'s, and
            // the screen only closes once it has actually started one (`started`) — a Load that finds a
            // broken file leaves you on the boot screen rather than in an empty world.
            .boot => switch (self.cursor) {
                // **BOTH ROWS ASK WHICH SLOT** (owner's call). New Game used to take the first empty one
                // without asking (ER's own) and only showed the picker when all three were full — so the
                // one press that decides where a character LIVES was the one press that never said where.
                // Three slots is few enough that choosing is the point of having them.
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
                    self.screen = .closed; // the editor is its own scene; the menu gets out of the way
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
                // Confirm on a level row does nothing (Left/Right adjust it) — only Back acts.
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
                // …and Confirm on the hour HOLDS it. Scrubbing to the light you want and then watching it walk
                // off again is the one thing this row must not do.
                DBG_HOUR => day.freeze(!day.frozen()),
                DBG_DAYRATE => day.cycleSpeed(),
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

    /// How far the adjust inputs want the value under the cursor to move THIS FRAME.
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

    fn debugLabels(self: *const Menu, day: *const daynight.Clock) [DBG_COUNT][:0]const u8 {
        var out: [DBG_COUNT][:0]const u8 = undefined;
        out[DBG_RETRO] = "Retro Filters >";
        out[DBG_STATS] = if (self.stats) "Stats: On" else "Stats: Off";
        out[DBG_WIREFRAME] = if (self.wireframe) "Wireframe: On" else "Wireframe: Off";
        out[DBG_HITBOX] = if (self.hitboxes) "Hitboxes: On" else "Hitboxes: Off";
        // The clock, the PHASE it is in, and whether it is running — the phase is what makes the number mean
        // something without having to remember when this world's sun comes up.
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
        out[DBG_CLOSE] = "Back";
        return out;
    }

    pub fn draw(self: *const Menu, retro: *const gfx.Retro, day: *const daynight.Clock, v: bookmod.View, portrait: ?bookmod.Portrait, shelf: *const savemod.Shelf) void {
        if (self.screen == .closed) return;
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        // THE BOOT SCREEN SITS DEEPER IN THE DUSK than the pause card. A pause is a held breath in a game you
        // are already looking at, so it stays legible under the veil; a title screen is a picture with a name
        // on it, and the world behind it is scenery.
        const boot = self.booting();
        rl.drawRectangle(0, 0, sw, sh, if (boot) BOOT_VEIL else VEIL);
        // …and the letterbox is DEEPER, not darker. A title screen wants the cinematic crop; what it does not
        // want is the picture it is drawn over gone, and at 205 over a wooded frame the world went black and
        // the card was floating on nothing. The separation is the CARD's job — that is what the plate is for.
        const lb = @divTrunc(sh, if (boot) @as(i32, 6) else 8); // dusk gathers at the frame's edges
        const lbA: u8 = if (boot) 180 else 140;
        rl.drawRectangleGradientV(0, 0, sw, lb, rgba(0, 0, 0, lbA), rgba(0, 0, 0, 0));
        rl.drawRectangleGradientV(0, sh - lb, sw, lb, rgba(0, 0, 0, 0), rgba(0, 0, 0, lbA));
        // THE BOOK IS NOT A CARD. It fills the frame and carries its own crib line, so it returns here
        // rather than falling through to the row-list chrome below.
        if (self.screen == .character) {
            bookmod.draw(&self.book, v, portrait);
            return;
        }
        switch (self.screen) {
            .closed, .character => {},
            .boot => self.drawCard("SOULSLIKE", &bootLabels(), .{
                .dim = &bootDim(shelf),
                .note = if (shelf.any()) BOOT_NOTE else BOOT_NOTE_EMPTY,
            }),
            .slots => self.drawSlots(shelf),
            .main => self.drawCard("SOULSLIKE", &mainLabels(), .{}),
            .options => self.drawCard("SOUND", &optionLabels(), .{ .gauges = &soundLevels() }),
            .debug => self.drawCard("DEBUG", &self.debugLabels(day), .{}),
            .retro => self.drawCard("RETRO FILTERS", &retroLabels(retro), .{ .gauges = retro.values[0..gfx.RETRO_COUNT] }),
        }
        // THE CRIB NAMES BUTTONS AND NOTHING ELSE (owner's call) — one strip, whether a pad is plugged in or
        // not. The keys still work; they are simply not what the chrome talks about, so there is no second
        // caption to keep in step with this one and no branch that can show the wrong half.
        // THE BOOT SCREEN'S IS SHORTER because its rows are: nothing there adjusts, there is nowhere to go
        // back to, and there is no character yet to open a book on. A crib that names three dead buttons is
        // three things to try before finding out they do nothing.
        const bootHints = [_]hud.Hint{
            .{ .glyph = .{ .dpad = .updown }, .label = "Move" },
            .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Select" },
        };
        // …and the picker's, which HAS a way back where the title screen has none, and one button the rest of
        // the game does not: the only press that can destroy a character.
        const slotHints = [_]hud.Hint{
            .{ .glyph = .{ .dpad = .updown }, .label = "Move" },
            .{ .glyph = .{ .face = hud.BTN_CONFIRM }, .label = "Select" },
            .{ .glyph = .{ .face = hud.BTN_QUICK }, .label = "Delete" },
            .{ .glyph = .{ .face = hud.BTN_BACK }, .label = "Back" },
        };
        // …and while the question is up the crib is only the two answers to it. Every other button on the
        // screen is refused there, so naming one would be naming a button that does nothing.
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

    /// **THE PICKER IS NOT A ROW LIST**, which is why it is not `drawCard` with a fourth optional column: a
    /// row here is a PICTURE with two lines beside it, and the plate has to be tall enough to hold one.
    /// Back is a plain row under the three, at the row height the rest of the game's lists use.
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
            self.drawSlotRow(i, shelf.head[i], cx + CARD_INSET, y, cardW - CARD_INSET * 2);
        }
        const by = cy + headerH + (SLOT_H + SLOT_GAP) * @as(i32, savemod.SLOTS) + 8;
        const onBack = self.cursor == SLOT_BACK;
        if (onBack) uiart.rowHilite(cx + CARD_INSET, by - 3, cardW - CARD_INSET * 2, backH);
        hud.text("Back", cx + CARD_INSET + ROW_LABEL, by, hud.BODY, if (onBack) TEXT_HOT else TEXT_DIM);
    }

    fn drawSlotRow(self: *const Menu, i: usize, head: ?savemod.Head, x: i32, y: i32, w: i32) void {
        const on = self.cursor == i;
        // A row you may not press: empty, under Load. Under New EVERY row is pressable — that screen only
        // comes up when all three are full, and picking one is the whole reason it is on the screen.
        const dead = head == null and self.slotIntent == .load;
        if (on and !dead) {
            uiart.rowHilite(x, y, w, SLOT_H);
            rl.drawRectangle(x, y, w, 1, mathx.withAlpha(uiart.GILT, 70));
            rl.drawRectangle(x, y + SLOT_H - 1, w, 1, mathx.withAlpha(uiart.GILT, 46));
            uiart.diamond(@floatFromInt(x + 2), @floatFromInt(y + 3), 2.6, uiart.GILT_BRIGHT);
            uiart.diamond(@floatFromInt(x + 2), @floatFromInt(y + SLOT_H - 3), 2.6, uiart.GILT_BRIGHT);
        } else if (on) {
            // AN EMPTY SLOT UNDER LOAD TAKES NO WASH, and it is the row you most want to see the cursor on:
            // "there is nothing here" is only an answer if you can tell you are asking about THIS one.
            uiart.caret(x, y, SLOT_H, uiart.CARET_DIM);
        }
        // THE PICTURE, in a sunk plate that is drawn WHETHER OR NOT there is one: an empty slot with no
        // frame around its gap makes the three rows read as two rows and a margin.
        const px = x + ROW_LABEL;
        const py = y + @divTrunc(SLOT_H - SLOT_THUMB_H, 2);
        rl.drawRectangle(px, py, SLOT_THUMB_W, SLOT_THUMB_H, rgba(6, 5, 4, 220));
        // THE PICTURE IS PART OF WHAT THE HEAD SAYS, so a slot with no head shows none — a file refused on
        // load leaves its PNG on disk, and a row reading "Empty" beside a photograph of somebody's game is
        // the two halves of one row disagreeing.
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

        // **ARE YOU SURE.** A save is the only thing in the game a press can destroy, so the row it is
        // standing on says what is about to happen and takes a SECOND press to do it — and the second press
        // is Confirm, on a row whose whole caption has become the question.
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
            const dead = if (card.dim) |d| i < d.len and d[i] else false;
            const col = if (dead) TEXT_OFF else if (selected) TEXT_HOT else TEXT_DIM;
            if (selected and !dead) {
                uiart.rowHilite(cx + CARD_INSET, y - 3, cardW - CARD_INSET * 2, rowH);
                // …and the card's own two hairlines and jewelled spine-ends on top of the shared wash.
                rl.drawRectangle(cx + CARD_INSET, y - 3, cardW - CARD_INSET * 2, 1, mathx.withAlpha(uiart.GILT, 70));
                rl.drawRectangle(cx + CARD_INSET, y - 4 + rowH, cardW - CARD_INSET * 2, 1, mathx.withAlpha(uiart.GILT, 46));
                uiart.diamond(@floatFromInt(cx + CARD_INSET + 2), @floatFromInt(y), 2.6, uiart.GILT_BRIGHT);
                uiart.diamond(@floatFromInt(cx + CARD_INSET + 2), @floatFromInt(y - 3 + rowH), 2.6, uiart.GILT_BRIGHT);
            }
            // …and a row too dim to take the wash still shows where the cursor is (`drawSlotRow`'s reason).
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

/// The optional columns a card can carry: a GAUGE per row, a footnote about the row the cursor is on, and
/// which rows are UNAVAILABLE. A slice shorter than the row list leaves the tail bare.
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

/// WHAT THE SAVE IS AND WHERE IT COMES FROM, said once on the one screen that can act on it. The empty case
/// is not an apology: it names the one place a save is made, which is a thing a soulslike has to teach.
/// ASCII ONLY, like every string in the game: the atlas has no em dash and one renders as tofu.
const BOOT_NOTE: [:0]const u8 = "Three slots. A bonfire saves over the one you are playing.";
const BOOT_NOTE_EMPTY: [:0]const u8 = "No save yet. Rest at a bonfire to write one.";

fn bootLabels() [BOOT_COUNT][:0]const u8 {
    var out: [BOOT_COUNT][:0]const u8 = undefined;
    out[BOOT_NEW] = "New Game";
    out[BOOT_LOAD] = "Load Game";
    out[BOOT_OPTIONS] = "Options";
    out[BOOT_EDITOR] = "Editor";
    out[BOOT_QUIT] = "Quit";
    return out;
}

fn bootDim(shelf: *const savemod.Shelf) [BOOT_COUNT]bool {
    var out = [_]bool{false} ** BOOT_COUNT;
    out[BOOT_LOAD] = !shelf.any();
    return out;
}


/// THE PICTURE EACH SLOT IS SHOWN BY, held only while the picker is up. File-scope like `book.zig`'s
/// portrait target and `objview.zig`'s two: a texture is chrome, and the menu owning one is not the menu
/// owning game state.
var slotTex: [savemod.SLOTS]?rl.Texture2D = [_]?rl.Texture2D{null} ** savemod.SLOTS;

fn loadShots() void {
    unloadShots();
    for (0..savemod.SLOTS) |i| {
        // A slot with no picture is not an error: the file predates the thumbnail, or the export failed.
        // The row draws an empty plate and still says everything that matters, which is the point of the
        // head being read off the SAVE rather than off the picture.
        slotTex[i] = rl.loadTexture(savemod.shotPath(i)) catch null;
    }
}

fn unloadShots() void {
    for (&slotTex) |*t| {
        if (t.*) |tex| rl.unloadTexture(tex);
        t.* = null;
    }
}

/// Called on the way out of the program, beside `book.unload` and `objview.unload`.
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

/// The same three numbers as bars, for `drawCard`'s gauge column.
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

// THE LEFT STICK AS A WALK, and getting this wrong is a known genre of bug — a stick is a LEVEL where a walk
// wants EDGES, so the naive reading fires a step every frame the stick is anywhere but centre. Four standard
// pieces, all of them here:
//
//  1. A RADIAL magnitude, never per-axis. Testing the axes separately is the "snap to grid" mistake: the
//     corner of the square passes at 0.62 on each axis while the true deflection is 0.88, so a lazy diagonal
//     reads as a hard push.
//  2. A SCHMITT TRIGGER, not one threshold. It arms at `STICK_FIRE` and does not re-arm until the stick has
//     fallen back under `STICK_REARM`; one threshold chatters across itself on the way past.
//  3. DAS then ARR (the falling-block idiom): a held push waits `STICK_DAS` before it repeats and then goes
//     every `STICK_ARR`, so a nudge is exactly one step and a hold is a readable crawl.
//  4. A DEAD CONE AT THE DIAGONALS — **ON A LIST OR A GRID, WHICH IS THE ONLY PLACE IT BELONGS.** Inside 32°
//     of an axis is that direction and outside it is nothing, because on a layout with four directions in it
//     a 46° push is a push the player has not finished making.
//
// **AND A RADIAL LAYOUT TAKES THE THUMB'S OWN BEARING, NOT ONE OF FOUR** (owner: walking the passive tree with
// the stick "feels horrible", and this is why). The wheel's three arms run out at 0, 120 and 240 degrees, so
// almost nothing on it is reachable along a screen axis: from the middle the ring-0 nodes sit at ∓15°, 105°,
// 135°, 225° and 255°, and every outward step along the two lower arms runs down a bearing near 216° or 96°.
// Snapped to four directions and then gated by a 32° dead cone, the natural push — the thumb pointed AT the
// node — landed in the cone and did NOTHING, twice out of three arms; what did work was pushing LEFT to reach
// the arm drawn down-and-right. The direction you travel and the direction you push had no relation.
//
// So `radial` hands `passivetree.step` the thumb's own unit heading and lets the wheel's own wedge search
// pick what lies along it (`STEP_CONE`, `STEP_BIAS` — the part that was already right). Point at a node, go to
// that node. Nothing about the LIST path moves: a row list still gets its four directions and its dead cone.
const STICK_FIRE: f32 = 0.72;
const STICK_REARM: f32 = 0.42;
const STICK_CONE: f32 = 0.848; // cos 32° — the half-angle a push must sit inside to count as an AXIS
const STICK_DAS: f32 = 0.42; // seconds a held push waits before it starts repeating
const STICK_ARR: f32 = 0.20; // …and the gap between repeats after that
/// HOW FAR THE THUMB HAS TO TURN TO COUNT AS A FRESH INTENT, as the cosine of the angle between the push that
/// fired last and the one on the stick now. cos 40°. Under it he is holding the same push and the DAS/ARR
/// clock governs; past it he has aimed somewhere else. ONE rule for both layouts: two cardinals are 90° apart,
/// so a list reads exactly as it always did, and a wheel gets a heading it can steer.
const AIM_TURN: f32 = 0.766;

/// The push that last fired, as a unit heading — null once the stick is home.
var stickDir: ?rl.Vector2 = null;
var stickWait: f32 = 0;
/// Has the stick been back to centre since the last step? A LIST makes you come back before it will take a new
/// direction — rolling a thumb round the rim crosses all four quadrants and firing each one is the twitch. A
/// WHEEL does not: steering to a new bearing without letting go IS how you cross a radial layout.
var stickArmed: bool = true;

/// WHAT THE LEFT STICK IS ASKING FOR THIS FRAME, as a unit heading in SCREEN space (+y down, which is the
/// stick's own sense and `passivetree.unitPos`'s), or null. Call ONCE a frame — it owns its own clock.
///
/// `radial` is the whole decision and it is `navFor`'s shape: a WHEEL takes the bearing, a list or a grid takes
/// one of four. See the note above for why a wheel cannot take one of four.
pub fn stickPush(dt: f32, radial: bool) ?rl.Vector2 {
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
    const d: rl.Vector2 = if (radial)
        .{ .x = nx, .y = ny } // the thumb's own bearing, and the wheel's wedge does the rest
    else if (@abs(nx) >= STICK_CONE)
        .{ .x = std.math.sign(nx), .y = 0 }
    else if (@abs(ny) >= STICK_CONE)
        .{ .x = 0, .y = std.math.sign(ny) }
    else
        return null; // a diagonal is not one of four directions — hold, and step nothing

    const turned = if (stickDir) |was| (was.x * d.x + was.y * d.y) < AIM_TURN else true;
    if (turned) {
        stickDir = d;
        stickWait = STICK_DAS;
        // A LIST costs a full DAS for a direction rolled into, exactly as a repeat would; a WHEEL is steered.
        if (!radial and !stickArmed) return null;
        stickArmed = false;
        return d;
    }
    stickWait -= dt;
    if (stickWait > 0) return null;
    stickWait = STICK_ARR;
    // …and the REPEAT goes down the heading the stick is on NOW, not the one that armed the clock: a thumb
    // easing round the rim under `AIM_TURN` should crawl round the wheel with it rather than off the old line.
    stickDir = d;
    return d;
}

/// THE RIGHT STICK AS A VIEW SLIDE, raw thumb in both axes (owner's call: the look stick pans the passive
/// tree). NOT run through `stickRadial`'s deadzone-and-curve: a pan is the one input here that wants to be
/// analogue all the way down, so a feather push creeps and a shove flies. Only the resting slop is cut.
const PAN_DEAD: f32 = 0.18;
pub fn stickPan() rl.Vector2 {
    if (!rl.isGamepadAvailable(0)) return .{ .x = 0, .y = 0 };
    const x = rl.getGamepadAxisMovement(0, .right_x);
    const y = rl.getGamepadAxisMovement(0, .right_y);
    const m = @sqrt(x * x + y * y);
    if (m < PAN_DEAD) return .{ .x = 0, .y = 0 };
    return .{ .x = x, .y = y };
}

/// THE CROSS'S UP AND DOWN AS A ZOOM, −1 (out) … +1 (in), read as a HELD level so it glides rather than
/// notching (owner's call). NOT the bumpers: those are the book's page turn, and the passive tree is one of
/// its pages — a zoom that took them would strand you on the wheel with no way to turn off it.
///
/// TWO DEVICES, AND NEITHER IS THE KEYBOARD'S ARROWS: the pad's cross, and the MOUSE WHEEL, which is why the
/// arrows keep WALKING the wheel on both screens (`navFor`) instead of being spent on a zoom a desk already has.
pub fn dpadZoom() f32 {
    var v: f32 = 0;
    if (padDown(.left_face_up)) v += 1;
    if (padDown(.left_face_down)) v -= 1;
    const notch = rl.getMouseWheelMove();
    if (notch != 0) v = mathx.clampF(v + notch * 0.6, -1, 1);
    return v;
}

/// …and the walk with the CROSS TAKEN OUT OF IT, for the two screens that have spent it on the zoom above.
/// The keys are untouched: only the pad's own d-pad is withheld.
pub fn navPressedNoPad(dir: NavDir) bool {
    const k = keyNav(dir);
    return rl.isKeyPressed(k.a) or rl.isKeyPressed(k.b) or rl.isKeyPressedRepeat(k.a) or rl.isKeyPressedRepeat(k.b);
}

/// WHICH WALK A SCREEN GETS, and the ONE copy of that decision. On a WHEEL the cross is the zoom (`dpadZoom`),
/// so it is withheld from the walk there and the left stick does it instead; on a plain LIST the cross is the
/// only sensible way to pick a row and it keeps it. Both wheel screens — the character book's tree page and the
/// bonfire's — read this; hand-rolled at each site the rule was two declarations of one fact, and moving it
/// meant editing two files.
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

/// Confirm HELD, not tapped — the book's slots sink for as long as the button is down.
fn confirmHeld() bool {
    const altHeld = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    if ((rl.isKeyDown(.enter) and !altHeld) or rl.isKeyDown(.space)) return true;
    return padDown(hud.padOf(hud.BTN_CONFIRM)); // the HELD half off the same name as the tap
}

/// THE PICKER'S THIRD BUTTON — named off the crib (`hud.BTN_QUICK`) like every other binding in the game, so
/// the glyph the hint row draws IS the button that arms the delete. It is bound nowhere else on this screen.
fn deletePressed() bool {
    return rl.isKeyPressed(.delete) or padPressed(hud.padOf(hud.BTN_QUICK));
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
