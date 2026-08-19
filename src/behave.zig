const std = @import("std");
const rl = @import("raylib");

const mathx = @import("mathx.zig");
const foe = @import("foe.zig");

const v3 = mathx.v3;


pub const Ctx = struct {
    at: rl.Vector3,
    facing: f32,
    quarry: rl.Vector3,
    /// How wide that thing is. EVERY radius in a `Step` is measured to its SKIN, so one script reads the
    /// same on a toad and on the knight instead of being re-tuned per quarry.
    quarryR: f32 = 0,
    nav: foe.Nav = .{},
};

pub const Want = struct {
    go: ?rl.Vector3 = null,
    look: ?rl.Vector3 = null,
    done: bool = false,
};

const ARRIVE: f32 = 0.45;
const SHIFT_BAIL: f32 = 2.2;
const BAND_SLOP: f32 = 0.35;

pub const Step = union(enum) {
    close: struct { to: f32 },
    open: struct { to: f32 },
    orbit: struct { r: f32, secs: f32 },
    dwell: struct { secs: f32 },
    /// **LEAVE THIS SPOT.** Walk to a place `d` away on a bearing `turn` radians off the line back to the
    /// quarry, eyes on it the whole way. THE DESTINATION IS COMMITTED AT THE FIRST FRAME (`mark`) — a
    /// reposition that re-derived its target every frame as the quarry moved would be a chase, and what
    /// makes this legible is that you can watch where it has decided to go.
    shift: struct { d: f32, turn: f32 },
};

pub const Routine = struct {
    script: []const Step = &.{},
    i: usize = 0,
    t: f32 = 0,
    side: f32 = 1,
    mark: rl.Vector3 = mathx.zero3,
    marked: bool = false,
    running: bool = false,

    /// ARM IT. `side` is +1 or -1 and is what makes two creatures running the same script orbit opposite
    /// ways — a seeded roll at the call site, never inside here, so a routine stays pure of dice.
    pub fn start(self: *Routine, script: []const Step, side: f32) void {
        self.* = .{
            .script = script,
            .side = if (side >= 0) 1 else -1,
            .running = script.len > 0,
        };
    }

    pub fn stop(self: *Routine) void {
        self.running = false;
    }

    pub fn current(self: *const Routine) ?Step {
        if (!self.running or self.i >= self.script.len) return null;
        return self.script[self.i];
    }

    pub fn walkTo(self: *const Routine, at: rl.Vector3, quarry: rl.Vector3) ?rl.Vector3 {
        return switch (self.current() orelse return null) {
            .close, .orbit => quarry,
            .open => mathx.addV(at, mathx.dirXZ(quarry, at)),
            .shift => if (self.marked) self.mark else quarry,
            .dwell => null,
        };
    }

    fn advance(self: *Routine) void {
        self.i += 1;
        self.t = 0;
        self.marked = false;
        if (self.i >= self.script.len) self.running = false;
    }

    pub fn step(self: *Routine, dt: f32, c: Ctx) Want {
        if (!self.running) return .{};
        self.t += dt;
        var guard: usize = 0;
        while (guard <= self.script.len) : (guard += 1) {
            if (!self.running or self.i >= self.script.len) {
                self.running = false;
                return .{ .done = true };
            }
            const dist = mathx.distXZ(c.at, c.quarry);
            switch (self.script[self.i]) {
                .close => |s| {
                    const want = c.quarryR + s.to;
                    if (dist <= want or (!self.marked and dist <= want + BAND_SLOP)) {
                        self.advance();
                        continue;
                    }
                    self.marked = true;
                    return .{ .go = c.nav.aim(c.at, c.quarry), .look = c.quarry };
                },
                .open => |s| {
                    const want = c.quarryR + s.to;
                    if (dist >= want or (!self.marked and dist >= want - BAND_SLOP)) {
                        self.advance();
                        continue;
                    }
                    self.marked = true;
                    const away = mathx.dirXZ(c.quarry, c.at);
                    const to = if (mathx.lenXZ(away) < 1e-3) mathx.headingDir(c.facing) else away;
                    return .{
                        .go = mathx.addV(c.at, c.nav.along(to)),
                        .look = c.quarry,
                    };
                },
                .orbit => |s| {
                    if (self.t >= s.secs) {
                        self.advance();
                        continue;
                    }
                    return .{ .go = self.ring(c, c.quarryR + s.r), .look = c.quarry };
                },
                .dwell => |s| {
                    if (self.t >= s.secs) {
                        self.advance();
                        continue;
                    }
                    return .{ .look = c.quarry };
                },
                .shift => |s| {
                    if (!self.marked) {
                        self.mark = self.spot(c, s.d, s.turn);
                        self.marked = true;
                    }
                    if (mathx.distXZ(c.at, self.mark) <= ARRIVE or self.t >= SHIFT_BAIL) {
                        self.advance();
                        continue;
                    }
                    return .{ .go = c.nav.aim(c.at, self.mark), .look = c.quarry };
                },
            }
        }
        return .{};
    }

    fn ring(self: *const Routine, c: Ctx, r: f32) rl.Vector3 {
        const out = mathx.dirXZ(c.quarry, c.at);
        const o = if (mathx.lenXZ(out) < 1e-3) mathx.headingDir(c.facing) else out;
        const tan = v3(o.z * self.side, 0, -o.x * self.side);
        const want = v3(c.quarry.x + o.x * r, c.at.y, c.quarry.z + o.z * r);
        return mathx.addV(want, c.nav.along(tan));
    }

    fn spot(self: *const Routine, c: Ctx, d: f32, turn: f32) rl.Vector3 {
        const out = mathx.dirXZ(c.quarry, c.at);
        const o = if (mathx.lenXZ(out) < 1e-3) mathx.headingDir(c.facing) else out;
        const a = mathx.headingXZ(o) + turn * self.side;
        const dir = mathx.headingDir(a);
        return v3(c.quarry.x + dir.x * d, c.at.y, c.quarry.z + dir.z * d);
    }
};


pub const DISENGAGE = [_]Step{
    .{ .shift = .{ .d = 6.5, .turn = 1.15 } },
    .{ .dwell = .{ .secs = 0.35 } },
    .{ .close = .{ .to = 1.6 } },
};

pub const FLANK = [_]Step{
    .{ .orbit = .{ .r = 3.4, .secs = 1.1 } },
    .{ .close = .{ .to = 1.4 } },
};

pub const KITE = [_]Step{
    .{ .open = .{ .to = 9.0 } },
    .{ .dwell = .{ .secs = 0.8 } },
};

test "a script runs its steps in order and ENDS — the done edge fires exactly once" {
    var r = Routine{};
    r.start(&[_]Step{ .{ .dwell = .{ .secs = 0.1 } }, .{ .dwell = .{ .secs = 0.1 } } }, 1);
    const c = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 4) };
    try std.testing.expect(r.running);
    _ = r.step(0.05, c);
    try std.testing.expectEqual(@as(usize, 0), r.i);
    _ = r.step(0.08, c);
    try std.testing.expectEqual(@as(usize, 1), r.i);
    var w = r.step(0.2, c);
    try std.testing.expect(w.done);
    try std.testing.expect(!r.running);
    w = r.step(0.2, c);
    try std.testing.expect(!w.done);
    try std.testing.expect(w.go == null and w.look == null);
}

test "A SHIFT COMMITS TO ONE SPOT — a reposition that chased would be a charge with no tell" {
    var r = Routine{};
    r.start(&[_]Step{.{ .shift = .{ .d = 6.0, .turn = 1.0 } }}, 1);
    var c = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 4) };
    const first = r.step(1.0 / 60.0, c).go.?;
    c.quarry = mathx.ground(9, 9);
    const second = r.step(1.0 / 60.0, c).go.?;
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(first, second), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(c.quarry, r.step(1.0 / 60.0, c).look.?), 1e-5);
}

test "A REFUSED DESTINATION IS GIVEN UP ON — a routine may not be the rest of a creature's life" {
    var r = Routine{};
    r.start(&[_]Step{.{ .shift = .{ .d = 6.0, .turn = 1.0 } }}, 1);
    const c = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 4) };
    var t: f32 = 0;
    while (t < SHIFT_BAIL * 2 and r.running) : (t += 1.0 / 60.0) _ = r.step(1.0 / 60.0, c);
    try std.testing.expect(!r.running);
    try std.testing.expect(t <= SHIFT_BAIL + 0.1);
}

test "the bands are measured to the quarry's SKIN, so one script reads the same on a toad and on a boss" {
    var r = Routine{};
    const script = [_]Step{.{ .close = .{ .to = 1.5 } }};
    // Standing 2 m off. Against a body with no width that is still outside the band, so it keeps walking…
    r.start(&script, 1);
    const thin = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 2.0), .quarryR = 0 };
    _ = r.step(1.0 / 60.0, thin);
    try std.testing.expect(r.running);
    // …and against a body 1.4 m through, the same 2 m is already inside reach of its SKIN and the step is
    // over. Written as a world distance instead, one script would walk a toad's range into a boss's chest.
    r.start(&script, 1);
    const wide = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 2.0), .quarryR = 1.4 };
    _ = r.step(1.0 / 60.0, wide);
    try std.testing.expect(!r.running);
}

test "A STEP ALREADY ON ITS BAND DOES NOT TWITCH — the slop is an entry tolerance, not a new band" {
    var r = Routine{};
    r.start(&[_]Step{.{ .close = .{ .to = 2.0 } }}, 1);
    const c = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 2.0 + BAND_SLOP * 0.6) };
    try std.testing.expect(r.step(1.0 / 60.0, c).done);
    var r2 = Routine{};
    r2.start(&[_]Step{.{ .close = .{ .to = 2.0 } }}, 1);
    var at = mathx.ground(0, 0);
    const q = mathx.ground(0, 6.0);
    var k: i32 = 0;
    while (k < 900 and r2.running) : (k += 1) {
        const w = r2.step(1.0 / 60.0, .{ .at = at, .facing = 0, .quarry = q });
        if (w.go) |g| at = mathx.approachV(at, g, 2.4 / 60.0);
    }
    try std.testing.expect(!r2.running);
    try std.testing.expect(mathx.distXZ(at, q) <= 2.0 + 0.05);
}

test "AN ORBIT HOLDS ITS RADIUS rather than spiralling out of the fight" {
    var r = Routine{};
    r.start(&[_]Step{.{ .orbit = .{ .r = 3.0, .secs = 99 } }}, 1);
    const quarry = mathx.ground(0, 0);
    var at = mathx.ground(5.0, 0);
    const dt = 1.0 / 60.0;
    var swept: f32 = 0; // …how far round it actually got, accumulated so a full lap cannot read as none
    var was = mathx.headingXZ(mathx.dirXZ(quarry, at));
    var k: i32 = 0;
    while (k < 400) : (k += 1) {
        const w = r.step(dt, .{ .at = at, .facing = 0, .quarry = quarry });
        const go = w.go orelse break;
        at = mathx.approachV(at, go, 2.4 * dt);
        const now = mathx.headingXZ(mathx.dirXZ(quarry, at));
        swept += @abs(mathx.wrapPi(now - was));
        was = now;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), mathx.distXZ(at, quarry), 0.35);
    try std.testing.expect(swept > 2.0);
}

test "THE STEP SAYS WHERE THE FEET GO, and a dwell asks for none" {
    const at = mathx.ground(0, 0);
    const q = mathx.ground(0, 6);
    var idle = Routine{};
    try std.testing.expect(idle.walkTo(at, q) == null);

    var c = Routine{};
    c.start(&[_]Step{.{ .close = .{ .to = 1.0 } }}, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(q, c.walkTo(at, q).?), 1e-5);

    var o = Routine{};
    o.start(&[_]Step{.{ .open = .{ .to = 9.0 } }}, 1);
    const away = o.walkTo(at, mathx.ground(0, 2)).?;
    try std.testing.expect(away.z < at.z);

    var d = Routine{};
    d.start(&[_]Step{.{ .dwell = .{ .secs = 1.0 } }}, 1);
    try std.testing.expect(d.current() != null and d.walkTo(at, q) == null);

    var s = Routine{};
    s.start(&[_]Step{.{ .shift = .{ .d = 6.0, .turn = 1.0 } }}, 1);
    _ = s.step(1.0 / 60.0, .{ .at = at, .facing = 0, .quarry = q });
    try std.testing.expect(s.marked);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(s.mark, s.walkTo(at, q).?), 1e-6);
}

test "THE UNSTAMPED WAY CHANGES NOTHING HERE EITHER — steering is a bend, never a layer" {
    var a = Routine{};
    var b = Routine{};
    a.start(&DISENGAGE, 1);
    b.start(&DISENGAGE, 1);
    const at = mathx.ground(0, 0);
    const c = Ctx{ .at = at, .facing = 0, .quarry = mathx.ground(0, 3) };
    const plain = a.step(1.0 / 60.0, c).go.?;
    const stamped = b.step(1.0 / 60.0, .{ .at = at, .facing = 0, .quarry = c.quarry, .nav = .{} }).go.?;
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(plain, stamped), 1e-6);
}
