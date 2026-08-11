const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");


pub const PAD = 0;

/// THE PAD IS ASKED THROUGH THESE TWO. Every read has to clear `isGamepadAvailable` first, and the guard
/// was written out longhand at twenty-five sites across `game.zig` and `menu.zig` — twenty-five places for
/// a new binding to forget it. They sit beside `PAD` because that is what they are: the one place the pad
/// index is named. The AXIS reads keep their own guard: they wrap a stick, not a button.
pub fn padPressed(b: rl.GamepadButton) bool {
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, b);
}
pub fn padDown(b: rl.GamepadButton) bool {
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonDown(PAD, b);
}

pub const Event = struct { low: f32 = 0, high: f32 = 0, dur: f32 = 0 };

pub const swing_light = Event{ .low = 0.08, .high = 0.20, .dur = 0.06 }; // your R1 whips out — a light tick
pub const swing_heavy = Event{ .low = 0.30, .high = 0.34, .dur = 0.13 }; // the committed R2 effort — a heavy wind
pub const hit_light = Event{ .low = 0.22, .high = 0.42, .dur = 0.10 }; // your light slash lands
pub const hit_heavy = Event{ .low = 0.48, .high = 0.60, .dur = 0.17 }; // your heavy crunches home
pub const hurt = Event{ .low = 0.55, .high = 0.32, .dur = 0.22 }; // a chomp catches you
pub const hurt_heavy = Event{ .low = 0.90, .high = 0.45, .dur = 0.34 }; // the lunge SLAMs you
pub const guard_block = Event{ .low = 0.30, .high = 0.42, .dur = 0.09 };
pub const guard_block_heavy = Event{ .low = 0.62, .high = 0.55, .dur = 0.18 };
pub const guard_break = Event{ .low = 0.95, .high = 0.52, .dur = 0.42 };
/// A BLOW REFUSED, not absorbed — so it sits over the heavy block, and mostly in the HIGH motor and SHORT: this
/// is iron ringing off iron, not a mass arriving on you.
pub const parry = Event{ .low = 0.52, .high = 0.92, .dur = 0.15 };
pub const roll = Event{ .low = 0.16, .high = 0.40, .dur = 0.10 }; // the dodge whump
/// HIS OWN WEIGHT ARRIVING. Mostly in the LOW motor, which is where mass lives — the roll is the other way
/// round because a roll is cloth and grit passing under you, and this is a body stopping.
pub const land = Event{ .low = 0.34, .high = 0.14, .dur = 0.12 };
pub const cast_throw = Event{ .low = 0.28, .high = 0.50, .dur = 0.14 }; // the stone lets go — a crack, not a thud
/// A RISING rumble, which a single `Event` cannot be: `Motor` decays from its peak. Pulse this every frame and
/// the envelope walks UP, since `pulse` re-arms on any peak at or above the live level. Mostly in the HIGH
/// motor — a spell building is a fizz in the grip, and the low pair belongs to the ogre's footfalls.
pub fn castCharge(fill: f32) Event {
    return .{ .low = 0.10 * fill, .high = 0.34 * fill, .dur = 0.10 };
}
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

// Windows / XInput backend.
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
