const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

// ── CONTROLLER RUMBLE ───────────────────────────────────────────────────────────────────
// Ported from zig-diablo's rumble.zig. raylib's GLFW desktop backend STUBS OUT
// SetGamepadVibration (this game runs GLFW — see the --shot log), so on Windows we drive
// XInput directly, resolving XInputSetState at runtime from whichever xinput DLL is present
// (cached) — sidestepping import-lib/ABI concerns and leaving build.zig untouched. Elsewhere
// we fall back to raylib's API (works under SDL, a harmless no-op otherwise).
//
// Each combat beat is an `Event`: a peak per motor plus a duration. Motors fade linearly, and
// overlapping events blend "strongest-wins" so a big SLAM takes over a lingering buzz without
// a weak tick cutting a strong one short. Because each beat has its own low/high/dur SIGNATURE,
// the grip teaches the fight — a light poke, a heavy crunch, and the lunge slam all feel
// distinct, so the player builds pattern memory through the hands, not just the eyes.
//
// XInput has a low-frequency ("heavy") motor and a high-frequency ("buzz") motor. The player's
// own actions lean on buzz; blows SUFFERED lean on the heavy motor; death swells both.

// input polling (game.zig) and this module's XInput calls must target the SAME pad.
pub const PAD = 0;

pub const Event = struct { low: f32 = 0, high: f32 = 0, dur: f32 = 0 };

// ── the combat vocabulary (distinct signatures → pattern memory) ────────────────────────
pub const swing_light = Event{ .low = 0.08, .high = 0.20, .dur = 0.06 }; // your R1 whips out — a light tick
pub const swing_heavy = Event{ .low = 0.30, .high = 0.34, .dur = 0.13 }; // the committed R2 effort — a heavy wind
pub const hit_light = Event{ .low = 0.22, .high = 0.42, .dur = 0.10 }; // your light slash lands
pub const hit_heavy = Event{ .low = 0.48, .high = 0.60, .dur = 0.17 }; // your heavy crunches home
pub const hurt = Event{ .low = 0.55, .high = 0.32, .dur = 0.22 }; // a chomp catches you
pub const hurt_heavy = Event{ .low = 0.90, .high = 0.45, .dur = 0.34 }; // the lunge SLAMs you
pub const roll = Event{ .low = 0.16, .high = 0.40, .dur = 0.10 }; // the dodge whump
pub const kill = Event{ .low = 0.34, .high = 0.20, .dur = 0.14 }; // a toad falls
pub const death = Event{ .low = 1.00, .high = 0.60, .dur = 0.70 }; // you die

// One motor's fading envelope: `peak` at t=dur, ramping to 0 at t=0.
const Motor = struct {
    peak: f32 = 0,
    t: f32 = 0,
    dur: f32 = 0,

    fn level(m: Motor) f32 {
        if (m.dur <= 0 or m.t <= 0) return 0;
        return m.peak * (m.t / m.dur);
    }
    // A new pulse takes over only if at least as strong, right now, as what's still playing —
    // a big impact overrides a fading buzz; a small tick never truncates a bigger event.
    fn pulse(m: *Motor, peak: f32, dur: f32) void {
        if (dur <= 0) return;
        if (peak >= m.level()) {
            m.peak = peak;
            m.dur = dur;
            m.t = dur;
        }
    }
    fn tick(m: *Motor, dt: f32) void {
        if (m.t > 0) m.t -= dt;
    }
};

pub const Rumble = struct {
    low: Motor = .{},
    high: Motor = .{},

    pub fn play(self: *Rumble, e: Event) void {
        self.low.pulse(e.low, e.dur);
        self.high.pulse(e.high, e.dur);
    }

    // Advance envelopes by dt and command the motors. `active` gates OUTPUT: pass false with
    // no controller or while paused, so the grip is silent while envelopes still decay in the
    // background (unpausing doesn't replay a stale buzz).
    pub fn update(self: *Rumble, dt: f32, active: bool) void {
        self.low.tick(dt);
        self.high.tick(dt);
        setMotors(if (active) self.low.level() else 0, if (active) self.high.level() else 0);
    }

    // Cut all vibration immediately (on quit, so a motor never latches after exit).
    pub fn stop(self: *Rumble) void {
        self.low = .{};
        self.high = .{};
        setMotors(0, 0);
    }
};

fn setMotors(low: f32, high: f32) void {
    const l = std.math.clamp(low, 0, 1);
    const h = std.math.clamp(high, 0, 1);
    if (builtin.os.tag == .windows) {
        win.set(l, h);
    } else {
        // Best effort: works under raylib's SDL backend, a no-op under GLFW.
        rl.setGamepadVibration(PAD, l, h, 0.1);
    }
}

// Windows / XInput backend. Resolved lazily from the first xinput DLL that loads.
const win = struct {
    const WINAPI = std.os.windows.WINAPI;
    const XINPUT_VIBRATION = extern struct { wLeftMotor: u16 = 0, wRightMotor: u16 = 0 };
    const SetStateFn = *const fn (dwUserIndex: u32, pVibration: *XINPUT_VIBRATION) callconv(WINAPI) u32;

    var resolved = false;
    var func: ?SetStateFn = null;

    fn resolve() ?SetStateFn {
        if (resolved) return func;
        resolved = true;
        // Newest first; xinput9_1_0 ships on every Windows since Vista (fallback).
        for ([_][]const u8{ "xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll" }) |name| {
            var lib = std.DynLib.open(name) catch continue;
            if (lib.lookup(SetStateFn, "XInputSetState")) |f| {
                func = f; // keep `lib` loaded for the process lifetime (never FreeLibrary)
                break;
            }
            lib.close(); // loaded but lacks the symbol — release before trying the next
        }
        return func;
    }

    fn set(l: f32, h: f32) void {
        const f = resolve() orelse return;
        var vib = XINPUT_VIBRATION{
            .wLeftMotor = @intFromFloat(l * 65535.0),
            .wRightMotor = @intFromFloat(h * 65535.0),
        };
        _ = f(PAD, &vib); // the first controller (rumble.PAD), matching game.zig's input polling
    }
};
