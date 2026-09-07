const std = @import("std");
const rl = @import("raylib");

const mathx = @import("../core/mathx.zig");
const foe = @import("foe.zig");

const v3 = mathx.v3;


pub const Ctx = struct {
    at: rl.Vector3,
    facing: f32,
    quarry: rl.Vector3,
    /// How wide that thing is. EVERY radius in a `Step` is measured to its SKIN, so one script reads the same on a toad and on the knight instead of being re-tuned per quarry.
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
/// How often a walk to a band is asked whether it is going anywhere, and the least ground that answers yes. A creature held where it stands — cornered, shoved, wading — must come back to its own mind, while one chasing a man who runs just as fast is getting nowhere and is not stuck.
const STALL_BAIL: f32 = 1.2;
const STALL_GO: f32 = 0.35;

pub const Step = union(enum) {
    close: struct { to: f32 },
    open: struct { to: f32 },
    orbit: struct { r: f32, secs: f32 },
    dwell: struct { secs: f32 },
    shift: struct { d: f32, turn: f32 },
    /// **HOLD THE RANGE YOU ARE ON AND CIRCLE.** An orbit whose radius is taken from where the creature ALREADY stands, committed at the first frame — so one script serves a skirmisher at 9 m and at 19 without walking either of them to an authored ring.
    strafe: struct { secs: f32 },
    /// **HOLD A RANGE AND CIRCLE IT.** Inside the band it strafes; outside it walks to the near edge and keeps circling on the way. Every caster and skirmisher used to spell this as `forward ± lateral` on a timer, which walks a heading committed before the quarry moved.
    band: struct { min: f32, max: f32, secs: f32 },
    /// **PLAY ANOTHER SCRIPT HERE**, `times` over, then carry on. The one part that makes the rest compose: a flow is written out of the flows already named.
    run: struct { script: []const Step, times: u8 = 1 },
};

/// A script may call into two more. Deeper than that is a behaviour tree, not a script.
const DEPTH = 3;
/// Steps one frame may finish and walk past. Held against a budget rather than the script in hand, which changes under a `run`.
const BUDGET = 32;

const Frame = struct { script: []const Step = &.{}, call: usize = 0, left: u8 = 0 };

pub const Routine = struct {
    script: []const Step = &.{},
    i: usize = 0,
    t: f32 = 0,
    side: f32 = 1,
    mark: rl.Vector3 = mathx.zero3,
    markR: f32 = 0,
    stall: f32 = 0,
    marked: bool = false,
    running: bool = false,
    up: [DEPTH]Frame = [_]Frame{.{}} ** DEPTH,
    nup: usize = 0,

    /// ARM IT. `side` is +1 or -1 and is what makes two creatures running the same script orbit opposite ways — a seeded roll at the call site, never inside here, so a routine stays pure of dice.
    pub fn start(self: *Routine, script: []const Step, side: f32) void {
        self.* = .{
            .script = script,
            .side = if (side >= 0) 1 else -1,
            .running = script.len > 0,
        };
        self.enterRuns();
    }

    /// A script that opens on a `run` is descended into before anyone asks what it wants, so `current` never answers with a call.
    fn enterRuns(self: *Routine) void {
        var guard: usize = 0;
        while (guard <= DEPTH) : (guard += 1) {
            if (!self.running or self.i >= self.script.len) return;
            switch (self.script[self.i]) {
                .run => |s| if (!self.descend(s.script, s.times)) return,
                else => return,
            }
        }
    }

    fn descend(self: *Routine, script: []const Step, times: u8) bool {
        if (self.nup >= DEPTH or script.len == 0 or times == 0) return false;
        self.up[self.nup] = .{ .script = self.script, .call = self.i, .left = times - 1 };
        self.nup += 1;
        self.script = script;
        self.i = 0;
        self.t = 0;
        self.stall = 0;
        self.marked = false;
        return true;
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
            .close, .orbit, .strafe, .band, .run => quarry,
            .open => mathx.addV(at, mathx.dirXZ(quarry, at)),
            .shift => if (self.marked) self.mark else quarry,
            .dwell => null,
        };
    }

    fn advance(self: *Routine) void {
        self.i += 1;
        self.t = 0;
        self.stall = 0;
        self.marked = false;
        while (self.i >= self.script.len) {
            if (self.nup == 0) {
                self.running = false;
                return;
            }
            const f = self.up[self.nup - 1];
            if (f.left > 0) {
                self.up[self.nup - 1] = .{ .script = f.script, .call = f.call, .left = f.left - 1 };
                self.script = f.script[f.call].run.script;
                self.i = 0;
                return;
            }
            self.nup -= 1;
            self.script = f.script;
            self.i = f.call + 1;
        }
        self.enterRuns();
    }

    pub fn step(self: *Routine, dt: f32, c: Ctx) Want {
        if (!self.running) return .{};
        self.t += dt;
        var guard: usize = 0;
        while (guard < BUDGET) : (guard += 1) {
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
                    if (self.gaveUp(dt, c.at)) {
                        self.advance();
                        continue;
                    }
                    return .{ .go = c.nav.aim(c.at, c.quarry), .look = c.quarry };
                },
                .open => |s| {
                    const want = c.quarryR + s.to;
                    if (dist >= want or (!self.marked and dist >= want - BAND_SLOP)) {
                        self.advance();
                        continue;
                    }
                    if (self.gaveUp(dt, c.at)) {
                        self.advance();
                        continue;
                    }
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
                .strafe => |s| {
                    if (!self.marked) {
                        self.marked = true;
                        self.markR = mathx.maxF(dist - c.quarryR, 0.5);
                    }
                    if (self.t >= s.secs) {
                        self.advance();
                        continue;
                    }
                    return .{ .go = self.ring(c, c.quarryR + self.markR), .look = c.quarry };
                },
                .band => |s| {
                    std.debug.assert(s.min <= s.max);
                    if (self.t >= s.secs) {
                        self.advance();
                        continue;
                    }
                    const gap = mathx.maxF(dist - c.quarryR, 0.5);
                    return .{ .go = self.ring(c, c.quarryR + mathx.clampF(gap, s.min, s.max)), .look = c.quarry };
                },
                .run => |s| {
                    if (!self.descend(s.script, s.times)) self.advance();
                    continue;
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

    /// Measured on the creature's OWN travel, never on the gap: a chase against a man who runs as fast closes nothing and is still a chase.
    fn gaveUp(self: *Routine, dt: f32, at: rl.Vector3) bool {
        if (!self.marked) {
            self.marked = true;
            self.mark = at;
            self.stall = 0;
            return false;
        }
        self.stall += dt;
        if (self.stall < STALL_BAIL) return false;
        const went = mathx.distXZ(self.mark, at);
        self.mark = at;
        self.stall = 0;
        return went < STALL_GO;
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


/// The heading a `Want` asks for, or nothing when it asks for no ground. Split from `walk` so a creature with a last word on where it may tread — a room to stay inside, a shore to keep off — can bend the way before it takes it.
pub fn heading(w: Want, at: rl.Vector3) ?rl.Vector3 {
    const g = w.go orelse return null;
    const way = mathx.dirXZ(at, g);
    return if (mathx.lenXZ(way) > 1e-3) way else null;
}

/// Take the stride and fill in the figures the gait reads. `moveSpeed` is optional the way `foe.postDrive`'s is: a creature that reads its gait speed back off the distance keeps no channel for it.
pub fn walk(pos: *rl.Vector3, way: rl.Vector3, dt: f32, bounds: f32, speed: f32, movedDist: *f32, moveSpeed: ?*f32, moveYaw: *?f32) void {
    const moved = speed * dt;
    mathx.stepXZ(pos, way, moved, bounds);
    movedDist.* = moved;
    if (moveSpeed) |ms| ms.* = speed;
    moveYaw.* = mathx.headingXZ(way);
}

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
    r.start(&script, 1);
    const thin = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 2.0), .quarryR = 0 };
    _ = r.step(1.0 / 60.0, thin);
    try std.testing.expect(r.running);
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

test "A STRAFE CIRCLES AT THE RANGE IT STOOD AT — committed at the first frame, whatever range that was" {
    for ([_]f32{ 4.0, 9.0, 17.0 }) |start| {
        var r = Routine{};
        r.start(&[_]Step{.{ .strafe = .{ .secs = 99 } }}, 1);
        const quarry = mathx.ground(0, 0);
        var at = mathx.ground(start, 0);
        const dt = 1.0 / 60.0;
        var swept: f32 = 0;
        var was = mathx.headingXZ(mathx.dirXZ(quarry, at));
        var k: i32 = 0;
        while (k < 300) : (k += 1) {
            const w = r.step(dt, .{ .at = at, .facing = 0, .quarry = quarry });
            at = mathx.approachV(at, w.go.?, 2.4 * dt);
            const now = mathx.headingXZ(mathx.dirXZ(quarry, at));
            swept += @abs(mathx.wrapPi(now - was));
            was = now;
        }
        try std.testing.expectApproxEqAbs(start, mathx.distXZ(at, quarry), 0.4);
        try std.testing.expect(swept * start > 3.0);
    }
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

test "A WALK THAT GETS NOWHERE IS GIVEN UP ON TOO — a creature held off its band still comes back to its own mind" {
    const dt = 1.0 / 60.0;
    for ([_]Step{ .{ .close = .{ .to = 2.0 } }, .{ .open = .{ .to = 12.0 } } }) |held| {
        var r = Routine{};
        r.start(&[_]Step{held}, 1);
        const c = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 6) };
        var t: f32 = 0;
        while (t < STALL_BAIL * 3 and r.running) : (t += dt) _ = r.step(dt, c);
        try std.testing.expect(!r.running);
        try std.testing.expect(t <= STALL_BAIL + 0.1);
    }
}

test "A BAND IS KEPT FROM EITHER SIDE — too close pushes out, too far pulls in, and between them it only circles" {
    const quarry = mathx.ground(0, 0);
    const dt = 1.0 / 60.0;
    for ([_]f32{ 3.0, 10.0, 20.0 }) |start| {
        var r = Routine{};
        r.start(&[_]Step{.{ .band = .{ .min = 7.0, .max = 13.0, .secs = 99 } }}, 1);
        var at = mathx.ground(start, 0);
        var swept: f32 = 0;
        var was = mathx.headingXZ(mathx.dirXZ(quarry, at));
        var k: i32 = 0;
        while (k < 600) : (k += 1) {
            const w = r.step(dt, .{ .at = at, .facing = 0, .quarry = quarry });
            at = mathx.approachV(at, w.go.?, 3.2 * dt);
            const now = mathx.headingXZ(mathx.dirXZ(quarry, at));
            swept += @abs(mathx.wrapPi(now - was));
            was = now;
        }
        const held = mathx.distXZ(at, quarry);
        std.debug.print("\n  band: stood at {d:.1} m, held {d:.1} m, swept {d:.2} rad", .{ start, held, swept });
        try std.testing.expect(held >= 7.0 - 0.4 and held <= 13.0 + 0.4);
        try std.testing.expect(swept * held > 3.0);
    }
    std.debug.print("\n", .{});
}

test "A BAND MEASURES TO THE QUARRY'S SKIN like every other step" {
    var r = Routine{};
    r.start(&[_]Step{.{ .band = .{ .min = 4.0, .max = 4.0, .secs = 99 } }}, 1);
    const quarry = mathx.ground(0, 0);
    var at = mathx.ground(12.0, 0);
    const dt = 1.0 / 60.0;
    var k: i32 = 0;
    while (k < 600) : (k += 1) {
        const w = r.step(dt, .{ .at = at, .facing = 0, .quarry = quarry, .quarryR = 2.5 });
        at = mathx.approachV(at, w.go.?, 3.2 * dt);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 6.5), mathx.distXZ(at, quarry), 0.4);
}

test "A SCRIPT IS BUILT OUT OF SCRIPTS — a run plays another flow through and comes back to the step after it" {
    const inner = [_]Step{ .{ .dwell = .{ .secs = 0.1 } }, .{ .dwell = .{ .secs = 0.1 } } };
    var r = Routine{};
    r.start(&[_]Step{ .{ .run = .{ .script = &inner, .times = 2 } }, .{ .dwell = .{ .secs = 0.1 } } }, 1);
    var visited: usize = 0;
    var was: ?[2]usize = null;
    var k: i32 = 0;
    while (k < 200 and r.running) : (k += 1) {
        _ = r.step(0.06, .{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 4) });
        if (!r.running) break;
        const now = [2]usize{ r.nup, r.i };
        if (was == null or !std.mem.eql(usize, &was.?, &now)) visited += 1;
        was = now;
    }
    try std.testing.expect(!r.running);
    try std.testing.expectEqual(@as(usize, 5), visited); // twice through the inner script, then the step after the call
}

const D4 = [_]Step{.{ .dwell = .{ .secs = 0.05 } }};
const D3 = [_]Step{ .{ .run = .{ .script = &D4 } }, .{ .dwell = .{ .secs = 0.05 } } };
const D2 = [_]Step{ .{ .run = .{ .script = &D3 } }, .{ .dwell = .{ .secs = 0.05 } } };
const D1 = [_]Step{ .{ .run = .{ .script = &D2 } }, .{ .dwell = .{ .secs = 0.05 } } };

test "A RUN PAST THE DEPTH IS SKIPPED, never a routine that stops answering" {
    var deep = Routine{};
    deep.start(&D1, 1);
    var k: i32 = 0;
    while (k < 2000 and deep.running) : (k += 1) {
        _ = deep.step(0.1, .{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 4) });
    }
    try std.testing.expect(!deep.running);
    try std.testing.expect(k < 2000);
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
