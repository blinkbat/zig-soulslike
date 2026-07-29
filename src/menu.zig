const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const hud = @import("hud.zig");
const mathx = @import("mathx.zig");
const rumblemod = @import("rumble.zig");

const rgba = mathx.rgba;

// THE pad index (rumble.PAD) — the menu must poll the same controller the game loop and the
// vibration calls do, so it reads the shared constant rather than repeating a literal 0.
const PAD = rumblemod.PAD;

// The pause/debug menu, OPEN AT LAUNCH (it doubles as the start screen): Continue / Debug /
// Quit. Debug holds the dev toggles; Retro Filters is a slider list over gfx.Retro.values.
// All chrome is primitive rects + hud text (Balthazar, ASCII only), drawn crisp AFTER the
// retro pass so menus never crunch. Esc/B backs out one level; Esc/Start toggles.

pub const Action = enum { none, quit };

const Screen = enum { closed, main, debug, retro };

// Debug rows (Retro Filters gets a submenu; the rest toggle/cycle in place).
const DBG_RETRO = 0;
const DBG_STATS = 1;
const DBG_WIREFRAME = 2;
const DBG_HITBOX = 3;
const DBG_TIMESCALE = 4;
const DBG_CLOSE = 5;
const DBG_COUNT = 6;

// Retro rows: the filter sliders, then presets, then Reset / All Off / Close.
const RET_PRESET_PS1 = gfx.RETRO_COUNT + 0;
const RET_PRESET_CRT = gfx.RETRO_COUNT + 1;
const RET_PRESET_VHS = gfx.RETRO_COUNT + 2;
const RET_PRESET_GB = gfx.RETRO_COUNT + 3;
const RET_RESET = gfx.RETRO_COUNT + 4;
const RET_ALL_OFF = gfx.RETRO_COUNT + 5;
const RET_CLOSE = gfx.RETRO_COUNT + 6;
const RET_COUNT = gfx.RETRO_COUNT + 7;

// Slider feel: a TAP steps fine, Shift/LB-tap steps coarse, and HOLDING a direction
// glides continuously after a short delay — frame-rate-fine adjustment.
const ADJ_TAP: f32 = 0.01;
const ADJ_COARSE: f32 = 0.10;
const ADJ_GLIDE_DELAY: f32 = 0.35; // seconds held before the glide kicks in
const ADJ_GLIDE_RATE: f32 = 0.25; // intensity per second while gliding

// Main rows — mainLabels() keys each label by its row index (like DBG_*/RET_*), so the
// labels can't drift out of lockstep with these constants.
const MAIN_CONTINUE = 0;
const MAIN_DEBUG = 1;
const MAIN_QUIT = 2;
const MAIN_COUNT = 3;

// ── palette (display-space; menus draw over the finished frame) ──
const VEIL = rgba(6, 6, 9, 150);
const CARD = rgba(16, 15, 13, 232);
const CARD_EDGE = rgba(146, 124, 82, 130);
const TEXT_DIM = rgba(150, 146, 138, 255);
const TEXT_HOT = rgba(236, 210, 150, 255);
const TITLE_COL = rgba(232, 222, 198, 255);
const HINT_COL = rgba(128, 122, 110, 255);
const BAR_EDGE = rgba(120, 104, 74, 160);
const BAR_FILL = rgba(198, 164, 96, 220);
const ROW_HILITE = rgba(255, 232, 170, 22); // selected-row wash

pub const Menu = struct {
    screen: Screen = .main, // the menu IS the start screen
    cursor: usize = 0,
    // debug toggles the game loop reads
    stats: bool = false,
    wireframe: bool = false,
    hitboxes: bool = false, // draw the blade hit capsule during attacks
    timeScale: f32 = 1.0,
    adjHoldT: f32 = 0, // seconds an adjust direction has been held (glide timer)

    pub fn isOpen(self: *const Menu) bool {
        return self.screen != .closed;
    }

    // Esc / pad Start. Esc backs out one level; Start toggles open/closed outright.
    pub fn onEscape(self: *Menu) void {
        self.cursor = 0;
        self.screen = switch (self.screen) {
            .closed => .main,
            .main => .closed,
            .debug => .main,
            .retro => .debug,
        };
    }
    pub fn onStartButton(self: *Menu) void {
        self.cursor = 0;
        self.screen = if (self.screen == .closed) .main else .closed;
    }

    // dt is the REAL frame time (not time-scaled) so the glide speed never changes.
    pub fn update(self: *Menu, retro: *gfx.Retro, dt: f32) Action {
        const rows: usize = switch (self.screen) {
            .closed => return .none,
            .main => MAIN_COUNT,
            .debug => DBG_COUNT,
            .retro => RET_COUNT,
        };
        if (navPressed(.up)) self.cursor = (self.cursor + rows - 1) % rows;
        if (navPressed(.down)) self.cursor = (self.cursor + 1) % rows;

        // Slider adjust (retro screen, filter rows only): tap = fine step, Shift/LB-tap
        // = coarse step, hold = continuous glide after a short delay.
        if (self.screen == .retro and self.cursor < gfx.RETRO_COUNT) {
            const v = &retro.values[self.cursor];
            const step: f32 = if (coarseHeld()) ADJ_COARSE else ADJ_TAP;
            if (adjTapped(.left)) v.* = mathx.clampF(v.* - step, 0, 1);
            if (adjTapped(.right)) v.* = mathx.clampF(v.* + step, 0, 1);
            const dir = adjHeldDir();
            if (dir != 0) {
                self.adjHoldT += dt;
                if (self.adjHoldT > ADJ_GLIDE_DELAY) {
                    v.* = mathx.clampF(v.* + @as(f32, @floatFromInt(dir)) * ADJ_GLIDE_RATE * dt, 0, 1);
                }
            } else {
                self.adjHoldT = 0;
            }
        } else {
            self.adjHoldT = 0;
        }
        if (self.screen == .debug and self.cursor == DBG_TIMESCALE) {
            if (adjTapped(.left) or adjTapped(.right)) self.cycleTimeScale();
        }

        if (confirmPressed()) return self.confirm(retro);
        if (backPressed()) self.onEscape();
        return .none;
    }

    fn confirm(self: *Menu, retro: *gfx.Retro) Action {
        switch (self.screen) {
            .closed => {},
            .main => switch (self.cursor) {
                MAIN_CONTINUE => self.screen = .closed,
                MAIN_DEBUG => {
                    self.screen = .debug;
                    self.cursor = 0;
                },
                MAIN_QUIT => return .quit,
                else => {},
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

    // ── draw ─────────────────────────────────────────────────────────────────────
    pub fn draw(self: *const Menu, retro: *const gfx.Retro) void {
        if (self.screen == .closed) return;
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        rl.drawRectangle(0, 0, sw, sh, VEIL);
        switch (self.screen) {
            .closed => {},
            .main => self.drawCard("SOULSLIKE", &mainLabels(), null),
            .debug => self.drawCard("DEBUG", &self.debugLabels(), null),
            .retro => self.drawCard("RETRO FILTERS", &retroLabels(retro), retro),
        }
        const hint: [:0]const u8 = if (rl.isGamepadAvailable(PAD))
            "D-pad move / adjust (hold glides, LB coarse)   A select   B back   Start close"
        else
            "Up/Down move   Left/Right adjust (hold glides, Shift coarse)   Enter select   Esc back";
        const hw = hud.textW(hint, hud.HINT);
        hud.text(hint, @divTrunc(sw - hw, 2), sh - hud.lineH(hud.HINT) - 12, hud.HINT, HINT_COL);
    }

    fn drawCard(self: *const Menu, title: [:0]const u8, labels: []const [:0]const u8, sliders: ?*const gfx.Retro) void {
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        // Row height and card size are DERIVED from the font size, so growing the type scale
        // doesn't leave rows overlapping or labels running off the card edge.
        const compact = labels.len > 8; // the long retro list packs tighter than the short menus
        const fontSize: i32 = if (compact) hud.SMALL else hud.BODY;
        const rowH: i32 = hud.lineH(fontSize) + (if (compact) @as(i32, 2) else @as(i32, 14));
        const rowGap: i32 = if (compact) 2 else 8;
        const headerH: i32 = hud.lineH(hud.TITLE) + 22;
        const footH: i32 = 20;
        const cardW: i32 = if (sliders != null) 620 else 470;
        const cardH: i32 = headerH + (rowH + rowGap) * @as(i32, @intCast(labels.len)) + footH;
        const cx = @divTrunc(sw - cardW, 2);
        const cy = @divTrunc(sh - cardH, 2);
        rl.drawRectangle(cx, cy, cardW, cardH, CARD);
        rl.drawRectangleLines(cx, cy, cardW, cardH, CARD_EDGE);
        rl.drawRectangle(cx + 18, cy + hud.lineH(hud.TITLE) + 10, cardW - 36, 1, CARD_EDGE); // rule under the title
        const tw = hud.textW(title, hud.TITLE);
        hud.text(title, cx + @divTrunc(cardW - tw, 2), cy + 12, hud.TITLE, TITLE_COL);
        for (labels, 0..) |label, i| {
            const y = cy + headerH + (rowH + rowGap) * @as(i32, @intCast(i));
            const selected = self.cursor == i;
            const col = if (selected) TEXT_HOT else TEXT_DIM;
            if (selected) rl.drawRectangle(cx + 14, y - 3, cardW - 28, rowH, ROW_HILITE);
            hud.text(label, cx + 40, y, fontSize, col);
            if (selected) hud.text(">", cx + 20, y, fontSize, TEXT_HOT);
            // Intensity gauge on filter rows of the retro card.
            if (sliders) |r| {
                if (i < gfx.RETRO_COUNT) {
                    drawGauge(cx + cardW - 40 - 130, y + @divTrunc(fontSize, 2) - 3, 130, 10, r.values[i], selected);
                }
            }
        }
    }
};

fn drawGauge(x: i32, y: i32, w: i32, h: i32, v: f32, selected: bool) void {
    rl.drawRectangleLines(x, y, w, h, BAR_EDGE);
    const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(w - 2)) * mathx.clampF(v, 0, 1));
    if (fill > 0) rl.drawRectangle(x + 1, y + 1, fill, h - 2, BAR_FILL);
    if (selected) {
        hud.text("<", x - 20, y - 7, hud.SMALL, TEXT_HOT);
        hud.text(">", x + w + 7, y - 7, hud.SMALL, TEXT_HOT);
    }
}

// ── row labels ── static for main; debug/retro rebuild each frame into fixed buffers
// (values change live; row counts are comptime-known so no allocation).
fn mainLabels() [MAIN_COUNT][:0]const u8 {
    var out: [MAIN_COUNT][:0]const u8 = undefined;
    out[MAIN_CONTINUE] = "Continue";
    out[MAIN_DEBUG] = "Debug";
    out[MAIN_QUIT] = "Quit";
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

// ── input (keyboard + Elden-Ring-layout pad) ──────────────────────────────────────
const NavDir = enum { up, down, left, right };

fn keyNav(dir: NavDir) struct { a: rl.KeyboardKey, b: rl.KeyboardKey } {
    return switch (dir) {
        .up => .{ .a = .up, .b = .w },
        .down => .{ .a = .down, .b = .s },
        .left => .{ .a = .left, .b = .a },
        .right => .{ .a = .right, .b = .d },
    };
}

// The gamepad D-pad face button for a nav direction — the pad counterpart of keyNav, so the
// dir→button map lives in ONE place (navPressed, adjTapped, adjHeldDir all read it).
fn padNav(dir: NavDir) rl.GamepadButton {
    return switch (dir) {
        .up => .left_face_up,
        .down => .left_face_down,
        .left => .left_face_left,
        .right => .left_face_right,
    };
}

// A fresh press of a direction on EITHER device — the one place the key/pad pair for a NavDir is
// read. `autoRepeat` folds in the keyboard's held-key repeat: menu NAVIGATION wants it (hold Down
// to run the cursor), slider ADJUST does not (the glide covers held keys instead).
fn dirPressed(dir: NavDir, autoRepeat: bool) bool {
    const k = keyNav(dir);
    if (rl.isKeyPressed(k.a) or rl.isKeyPressed(k.b)) return true;
    if (autoRepeat and (rl.isKeyPressedRepeat(k.a) or rl.isKeyPressedRepeat(k.b))) return true;
    if (rl.isGamepadAvailable(PAD)) {
        if (rl.isGamepadButtonPressed(PAD, padNav(dir))) return true;
    }
    return false;
}

fn navPressed(dir: NavDir) bool {
    return dirPressed(dir, true);
}

// Slider adjust inputs: a TAP (no key-repeat), the held direction for the glide, and the
// coarse-step modifier (Shift / LB).
fn adjTapped(dir: NavDir) bool {
    return dirPressed(dir, false);
}

fn adjHeldDir() i32 {
    var dir: i32 = 0;
    const l = keyNav(.left);
    const r = keyNav(.right);
    if (rl.isKeyDown(l.a) or rl.isKeyDown(l.b)) dir -= 1;
    if (rl.isKeyDown(r.a) or rl.isKeyDown(r.b)) dir += 1;
    if (dir == 0 and rl.isGamepadAvailable(PAD)) {
        if (rl.isGamepadButtonDown(PAD, padNav(.left))) dir -= 1;
        if (rl.isGamepadButtonDown(PAD, padNav(.right))) dir += 1;
    }
    return dir;
}

fn coarseHeld() bool {
    if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) return true;
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonDown(PAD, .left_trigger_1);
}

fn confirmPressed() bool {
    // ALT+Enter belongs to the game loop's borderless-fullscreen toggle, so Enter must not ALSO
    // confirm the highlighted row while Alt is down. The menu is open at launch, so without this
    // the very first Alt+Enter selected whatever the cursor sat on — with the cursor one row off
    // Quit, toggling fullscreen could exit the game.
    const altHeld = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    if ((rl.isKeyPressed(.enter) and !altHeld) or rl.isKeyPressed(.space)) return true;
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .right_face_down);
}

fn backPressed() bool {
    // Esc is routed by the game loop (onEscape); pad B backs out here.
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .right_face_right);
}
