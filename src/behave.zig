const std = @import("std");
const rl = @import("raylib");

const mathx = @import("mathx.zig");
const foe = @import("foe.zig");

const v3 = mathx.v3;

// THE BEHAVIOUR LIBRARY — the multi-frame routines a creature's brain is written out of, in one place and
// adoptable by any of them.
//
// **A BEHAVIOUR IS A COROUTINE WITHOUT THE LANGUAGE'S HELP.** Zig 0.14 has no async, so a routine that spans
// frames is a struct that keeps its own stack: `script` is the code, `i` is the program counter, `t` is the
// local clock and `mark` is the one local that has to survive a suspend. `step` is the resume. That is the
// whole trick, and it is what makes these shareable — a routine written once runs identically on a kobold
// and on a boss, because none of its state lives in either of them.
//
// **A BEHAVIOUR NEVER TOUCHES THE CREATURE.** It reads a `Ctx` and hands back a `Want` — a point to walk at
// and a point to look at — and the creature applies it. A routine that wrote `pos` would have to know about
// `foe.grip`, the nav stamp, `game.gateTerrain` and the ground pass, none of which are the same on two
// creatures and all of which are the game's business. The Want is the whole contract.
//
// **AND IT DECIDES NOTHING.** Which routine to run, and when, is the creature's own `decide` — that is where
// a fight's character lives and it is deliberately not generalised. What is generalised is the WALKING:
// close, open, orbit, dwell, shift.

/// What a routine is given each frame. Everything in it is world state a body standing there could read —
/// the NO INPUT READING law is kept by there being nothing else on offer.
pub const Ctx = struct {
    at: rl.Vector3,
    facing: f32,
    /// Whatever it is actually fighting (`foe.Threat.aim`), never "the hero" by name.
    quarry: rl.Vector3,
    /// How wide that thing is. EVERY radius in a `Step` is measured to its SKIN, so one script reads the
    /// same on a toad and on the knight instead of being re-tuned per quarry.
    quarryR: f32 = 0,
    /// The steering stamp (`game.markWay`), so a routine bends round a wall rather than pressing into it.
    /// Unstamped it changes nothing, which is what lets a creature with no `nav` field adopt one anyway.
    nav: foe.Nav = .{},
};

/// …and what it hands back. Both fields are OPTIONAL and null means "not my business this frame": a routine
/// that only wants a facing leaves the feet alone rather than asking for the spot they are already on.
pub const Want = struct {
    go: ?rl.Vector3 = null,
    look: ?rl.Vector3 = null,
    /// The script ran off its end this frame. An EDGE — the routine is not running afterwards.
    done: bool = false,
};

/// How close counts as arrived, for the one step that walks at a fixed point.
const ARRIVE: f32 = 0.45;
/// …and how long it may try before it gives up on getting there. A `shift` commits to a destination and the
/// world may simply refuse it — a wall, a bank, the deep — and a routine with no bail is a creature stuck
/// walking into masonry for the rest of the fight.
const SHIFT_BAIL: f32 = 2.2;
/// The slop either side of an `open`/`close` band. Without it a creature sitting exactly on the boundary
/// steps in and out of it every frame, which is the twitch that reads as broken.
const BAND_SLOP: f32 = 0.35;

pub const Step = union(enum) {
    /// Walk at it until inside `to` of its skin.
    close: struct { to: f32 },
    /// …and back off until outside `to` of its skin — the archer's kite, and the knight's answer to being
    /// crowded, written once.
    open: struct { to: f32 },
    /// Walk a circle round it at `r` from its skin for `secs`, eyes on it the whole way.
    orbit: struct { r: f32, secs: f32 },
    /// Stand and watch. The beat between two committed things, and the only step that asks for no feet.
    dwell: struct { secs: f32 },
    /// **LEAVE THIS SPOT.** Walk to a place `d` away on a bearing `turn` radians off the line back to the
    /// quarry, eyes on it the whole way. THE DESTINATION IS COMMITTED AT THE FIRST FRAME (`mark`) — a
    /// reposition that re-derived its target every frame as the quarry moved would be a chase, and what
    /// makes this legible is that you can watch where it has decided to go.
    shift: struct { d: f32, turn: f32 },
};

pub const Routine = struct {
    script: []const Step = &.{},
    /// The program counter.
    i: usize = 0,
    /// …and the current step's own clock.
    t: f32 = 0,
    /// Which way round it went, picked at `start` and held for the whole script — `foe.Nav.side`'s reason:
    /// a creature that re-picks a side mid-routine shivers instead of committing.
    side: f32 = 1,
    /// The `shift`'s committed destination, and whether it has been taken yet.
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

    /// Which step is on, for a creature that gates its kit on it — a swing thrown mid-`shift` is a swing
    /// aimed at where it used to be standing.
    pub fn current(self: *const Routine) ?Step {
        if (!self.running or self.i >= self.script.len) return null;
        return self.script[self.i];
    }

    /// **WHERE THE RUNNING STEP WANTS THE FEET** — `game.markWay`'s question, answered off the routine.
    /// Null when nothing is running and null for a `dwell`, which asks for no feet at all.
    ///
    /// It lives here because it is the STEP's own meaning, not the creature's: the archer and the warrior
    /// each carried a byte-identical copy of this switch, so a sixth `Step` was two edits in lockstep with
    /// nothing holding them level — and a third creature adopting a script would have made it three.
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

    /// ONE FRAME — the resume. Returns what the creature should do with its feet and its eyes.
    ///
    /// A step that finishes mid-frame falls straight through to the next one rather than costing a frame of
    /// standing still, which is why this is a loop and not a switch. Bounded by the script's own length, so
    /// a script of nothing but zero-length dwells terminates instead of spinning.
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
                    // `BAND_SLOP` is an ENTRY tolerance: standing within a slop of the band, the step is
                    // already satisfied and never starts walking — the boundary twitch. Once WALKING
                    // (`marked`, the step's one local) it finishes at the band it was asked for.
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
                    // Straight back down the line it came in on, and it keeps WATCHING: a creature that
                    // turns its back to make ground is a creature that has stopped fighting.
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
                    // ARRIVED, or the world would not let it — either way the step is over. The bail is what
                    // stops a refused destination from being the rest of the creature's life.
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

    /// A point on the circle of radius `r` about the quarry, one step round from where it is standing. Taken
    /// as a TANGENT off its current bearing rather than as an absolute angle, so the orbit works from
    /// wherever the creature happens to be when the step starts.
    fn ring(self: *const Routine, c: Ctx, r: f32) rl.Vector3 {
        const out = mathx.dirXZ(c.quarry, c.at);
        const o = if (mathx.lenXZ(out) < 1e-3) mathx.headingDir(c.facing) else out;
        const tan = v3(o.z * self.side, 0, -o.x * self.side);
        // The goal is re-projected ONTO the ring every frame and only THEN stepped sideways, which is what
        // pulls a drifting orbit back to its own radius instead of letting it spiral out of the fight. The
        // metre of tangent puts the equilibrium a hair outside `r` (sqrt(r²+1)) — the test says so.
        const want = v3(c.quarry.x + o.x * r, c.at.y, c.quarry.z + o.z * r);
        return mathx.addV(want, c.nav.along(tan));
    }

    /// Where a `shift` is going: `d` metres from the quarry, on a bearing `turn` off the line it is standing
    /// on. Measured from the QUARRY rather than from its own feet, so the step ends at a known distance from
    /// the fight instead of a known distance from wherever it started.
    fn spot(self: *const Routine, c: Ctx, d: f32, turn: f32) rl.Vector3 {
        const out = mathx.dirXZ(c.quarry, c.at);
        const o = if (mathx.lenXZ(out) < 1e-3) mathx.headingDir(c.facing) else out;
        const a = mathx.headingXZ(o) + turn * self.side;
        const dir = mathx.headingDir(a);
        return v3(c.quarry.x + dir.x * d, c.at.y, c.quarry.z + dir.z * d);
    }
};

// ── SCRIPTS ──────────────────────────────────────────────────────────────────────────────────────────────
// Named routines, so a creature adopts a BEHAVIOUR by name rather than by copying five numbers. A creature
// that wants its own shape writes its own table; these are the ones more than one of them wanted.

/// **BREAK OFF AND COME BACK IN.** The general reposition: leave the spot you are being hurt in, watch from
/// a beat's distance, then walk back onto it. The knight's leap answers the same question with his own
/// silhouette; this is what everything without a five-metre bound does instead.
pub const DISENGAGE = [_]Step{
    .{ .shift = .{ .d = 6.5, .turn = 1.15 } },
    .{ .dwell = .{ .secs = 0.35 } },
    .{ .close = .{ .to = 1.6 } },
};

/// **TAKE THE FLANK.** Round to its side rather than backing off — for a creature that is losing a straight
/// trade but has no reason to leave the fight.
pub const FLANK = [_]Step{
    .{ .orbit = .{ .r = 3.4, .secs = 1.1 } },
    .{ .close = .{ .to = 1.4 } },
};

/// **THE KITE**: open to a shooting band, hold it, and open again the moment it is closed on. The archer's
/// whole movement, and the slinger's.
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
    _ = r.step(0.08, c); // …the first dwell is up, so it is already standing in the second
    try std.testing.expectEqual(@as(usize, 1), r.i);
    var w = r.step(0.2, c);
    try std.testing.expect(w.done);
    try std.testing.expect(!r.running);
    // …and a stopped routine asks for nothing at all rather than repeating its last frame.
    w = r.step(0.2, c);
    try std.testing.expect(!w.done);
    try std.testing.expect(w.go == null and w.look == null);
}

test "A SHIFT COMMITS TO ONE SPOT — a reposition that chased would be a charge with no tell" {
    var r = Routine{};
    r.start(&[_]Step{.{ .shift = .{ .d = 6.0, .turn = 1.0 } }}, 1);
    var c = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 4) };
    const first = r.step(1.0 / 60.0, c).go.?;
    // The quarry walks a long way; the destination does not follow it.
    c.quarry = mathx.ground(9, 9);
    const second = r.step(1.0 / 60.0, c).go.?;
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(first, second), 1e-5);
    // …but its EYES do, which is the half that has to keep tracking.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(c.quarry, r.step(1.0 / 60.0, c).look.?), 1e-5);
}

test "A REFUSED DESTINATION IS GIVEN UP ON — a routine may not be the rest of a creature's life" {
    var r = Routine{};
    r.start(&[_]Step{.{ .shift = .{ .d = 6.0, .turn = 1.0 } }}, 1);
    // Pinned against a wall: it never arrives, so only the bail can end this.
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
    // Standing a hand's width off the asked band: not worth walking, the step is already satisfied.
    var r = Routine{};
    r.start(&[_]Step{.{ .close = .{ .to = 2.0 } }}, 1);
    const c = Ctx{ .at = mathx.ground(0, 0), .facing = 0, .quarry = mathx.ground(0, 2.0 + BAND_SLOP * 0.6) };
    try std.testing.expect(r.step(1.0 / 60.0, c).done);
    // …but a step that has genuinely STARTED walking finishes at the band it was asked for.
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
    var at = mathx.ground(5.0, 0); // started WIDE of the ring
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
    // It settles a hair OUTSIDE the named radius and that is the tangent's doing, not drift: the goal is one
    // metre round the ring, so the equilibrium is sqrt(r²+1).
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), mathx.distXZ(at, quarry), 0.35);
    // …and it actually went ROUND: a body that held its radius without travelling is a body standing still.
    try std.testing.expect(swept > 2.0);
}

test "THE STEP SAYS WHERE THE FEET GO, and a dwell asks for none" {
    // One answer for every creature running a script: as a copy in the archer and another in the warrior, a
    // sixth `Step` was two edits nothing held level.
    const at = mathx.ground(0, 0);
    const q = mathx.ground(0, 6);
    var idle = Routine{};
    try std.testing.expect(idle.walkTo(at, q) == null); // nothing running asks for nothing

    // CLOSE walks AT it…
    var c = Routine{};
    c.start(&[_]Step{.{ .close = .{ .to = 1.0 } }}, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(q, c.walkTo(at, q).?), 1e-5);

    // …OPEN straight back down the line it came in on, and it is a POINT one step out, not the quarry.
    var o = Routine{};
    o.start(&[_]Step{.{ .open = .{ .to = 9.0 } }}, 1);
    const away = o.walkTo(at, mathx.ground(0, 2)).?;
    try std.testing.expect(away.z < at.z);

    // …and a DWELL is running and asks for no feet at all, which is not the same as no routine.
    var d = Routine{};
    d.start(&[_]Step{.{ .dwell = .{ .secs = 1.0 } }}, 1);
    try std.testing.expect(d.current() != null and d.walkTo(at, q) == null);

    // A `shift` hands back its COMMITTED mark once it has taken one, never the quarry it is watching.
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
