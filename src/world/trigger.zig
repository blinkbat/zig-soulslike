const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const wf = @import("worldfmt.zig");

const v3 = mathx.v3;


pub const REPEAT_GUARD: f32 = 0.5;

pub const BANNER_DUR: f32 = 4.5;
pub const BANNER_CAP: usize = 120;

const NFOE = @typeInfo(wf.FoeKind).@"enum".fields.len;

comptime {
    std.debug.assert(wf.MAX_TRIGGERS <= std.math.maxInt(u8) + 1);
    std.debug.assert(wf.MAX_ACTS <= std.math.maxInt(u8) + 1);
}

/// What the conditions need to know about the world this frame. Handed IN, because the machine must not reach into the game to find a foe list — the same rule the creatures' `Leash` follows.
pub const World = struct {
    heroPos: rl.Vector3 = mathx.zero3,
    npcs: []const rl.Vector3 = &.{},
    alive: [NFOE]u32 = [_]u32{0} ** NFOE,
};

pub const Runtime = struct {
    flags: [wf.MAX_FLAGS]bool = [_]bool{false} ** wf.MAX_FLAGS,
    counters: [wf.MAX_COUNTERS]i32 = [_]i32{0} ** wf.MAX_COUNTERS,
    /// Seconds left on each countdown. A timer nobody started reads as NOT done, so `timer x=done` cannot pass before something armed it — the alternative makes every unstarted timer a free `always`.
    timers: [wf.MAX_TIMERS]f32 = [_]f32{0} ** wf.MAX_TIMERS,
    armed: [wf.MAX_TIMERS]bool = [_]bool{false} ** wf.MAX_TIMERS,
    deaths: [NFOE]u32 = [_]u32{0} ** NFOE,
    elapsed: f32 = 0,

    talked: [wf.MAX_DIALOGS]bool = [_]bool{false} ** wf.MAX_DIALOGS,

    fired: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,
    since: [wf.MAX_TRIGGERS]f32 = [_]f32{mathx.LONG_AGO} ** wf.MAX_TRIGGERS,
    running: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,
    actAt: [wf.MAX_TRIGGERS]u8 = [_]u8{0} ** wf.MAX_TRIGGERS,
    waitLeft: [wf.MAX_TRIGGERS]f32 = [_]f32{0} ** wf.MAX_TRIGGERS,
    inDialog: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,
    preserved: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,

    order: [wf.MAX_TRIGGERS]u8 = undefined,
    n: usize = 0,

    banner: [BANNER_CAP]u8 = [_]u8{0} ** BANNER_CAP,
    bannerLen: usize = 0,
    bannerLeft: f32 = 0,

    pub fn arm(self: *Runtime, m: *const wf.Map) void {
        self.* = .{};
        self.n = @min(m.ntrigs, wf.MAX_TRIGGERS);
        for (0..self.n) |i| self.order[i] = @intCast(i);
        const ord = self.order[0..self.n];
        var i: usize = 1;
        while (i < ord.len) : (i += 1) {
            const v = ord[i];
            var j = i;
            while (j > 0 and m.trigs[ord[j - 1]].pri < m.trigs[v].pri) : (j -= 1) ord[j] = ord[j - 1];
            ord[j] = v;
        }
    }

    pub fn died(self: *Runtime, k: wf.FoeKind) void {
        self.deaths[@intFromEnum(k)] += 1;
    }

    pub fn finished(self: *Runtime, dlg: u16) void {
        if (dlg < wf.MAX_DIALOGS) self.talked[dlg] = true;
    }

    pub fn dialogClosed(self: *Runtime) void {
        self.inDialog = [_]bool{false} ** wf.MAX_TRIGGERS;
    }

    pub fn bannerText(self: *const Runtime) []const u8 {
        return if (self.bannerLeft > 0) self.banner[0..self.bannerLen] else "";
    }

    /// A LINE THE ENGINE ITSELF HAS TO SAY — the binding ring snapping, and nothing else yet. Down the `text` action's OWN channel and not a second banner beside it: SC1's Display Text Message is exactly this, and one line of prose on screen may only ever come from one place.
    pub fn say(self: *Runtime, line: []const u8) void {
        self.bannerLen = @min(line.len, BANNER_CAP);
        @memcpy(self.banner[0..self.bannerLen], line[0..self.bannerLen]);
        self.bannerLeft = BANNER_DUR;
    }

    pub fn flagOn(self: *const Runtime, slot: u16) bool {
        return slot < wf.MAX_FLAGS and self.flags[slot];
    }
    pub fn counterAt(self: *const Runtime, slot: u16) i32 {
        return if (slot < wf.MAX_COUNTERS) self.counters[slot] else 0;
    }

    pub fn tick(self: *Runtime, m: *const wf.Map, w: World, dt: f32, busy: bool) ?u16 {
        self.elapsed += dt;
        if (self.bannerLeft > 0) self.bannerLeft -= dt;
        for (&self.timers, 0..) |*t, i| {
            if (self.armed[i] and t.* > 0) t.* = @max(0, t.* - dt);
        }
        for (&self.since) |*s| s.* = @min(s.* + dt, mathx.LONG_AGO);

        var open: ?u16 = null;
        for (self.order[0..self.n]) |ti| {
            const t = &m.trigs[ti];
            if (t.wip) continue;
            if (self.running[ti]) {
                if (self.advance(m, ti, dt, busy or open != null)) |d| open = open orelse d;
                continue;
            }
            if (t.once and self.fired[ti]) continue;
            if (self.since[ti] < REPEAT_GUARD) continue;
            if (!self.satisfied(t, w)) continue;
            self.running[ti] = true;
            self.actAt[ti] = 0;
            self.waitLeft[ti] = 0;
            self.preserved[ti] = false;
            if (self.advance(m, ti, dt, busy or open != null)) |d| open = open orelse d;
        }
        return open;
    }

    fn satisfied(self: *const Runtime, t: *const wf.Trigger, w: World) bool {
        // AN EMPTY CONDITION LIST NEVER FIRES. `always` is a condition you have to write down — a trigger whose `when:` lines were still to come would otherwise go off the moment the map loaded.
        if (t.nconds == 0) return false;
        for (t.condSlice()) |*c| {
            if (!self.holds(c, w)) return false;
        }
        return true;
    }

    pub fn holds(self: *const Runtime, c: *const wf.Cond, w: World) bool {
        return switch (c.kind) {
            .always => true,
            .never => false,
            .flag => self.flagOn(c.slot) == c.on,
            .counter => c.cmp.holds(self.counterAt(c.slot), c.n),
            .timer => if (c.on)
                c.slot < wf.MAX_TIMERS and self.armed[c.slot] and self.timers[c.slot] <= 0
            else
                c.slot < wf.MAX_TIMERS and self.armed[c.slot] and self.timers[c.slot] > 0,
            .elapsed => c.cmp.holdsF(self.elapsed, c.r),
            .region => wf.inRect(w.heroPos.x, w.heroPos.z, c.x, c.z, c.x1, c.z1),
            .near => c.slot < w.npcs.len and mathx.dist2XZ(w.npcs[c.slot], w.heroPos) <= c.r * c.r,
            .talked => c.slot < wf.MAX_DIALOGS and self.talked[c.slot],
            .deaths => c.cmp.holds(self.deaths[@intFromEnum(c.foe)], c.n),
            .alive => c.cmp.holds(w.alive[@intFromEnum(c.foe)], c.n),
        };
    }

    fn advance(self: *Runtime, m: *const wf.Map, ti: usize, dt: f32, busy: bool) ?u16 {
        if (self.inDialog[ti]) return null;
        if (self.waitLeft[ti] > 0) {
            self.waitLeft[ti] -= dt;
            if (self.waitLeft[ti] > 0) return null;
        }
        const t = &m.trigs[ti];
        while (self.actAt[ti] < t.nacts) {
            const a = &t.acts[self.actAt[ti]];
            if (a.kind == .dialog) {
                if (busy) return null;
                self.actAt[ti] += 1;
                self.inDialog[ti] = true;
                return a.slot;
            }
            self.actAt[ti] += 1;
            if (a.kind == .wait) {
                self.waitLeft[ti] = a.v;
                if (a.v > 0) return null;
                continue;
            }
            if (a.kind == .preserve) {
                self.preserved[ti] = true;
                continue;
            }
            self.apply(m, a);
        }
        self.running[ti] = false;
        self.since[ti] = 0;
        if (!self.preserved[ti]) self.fired[ti] = true;
        return null;
    }

    pub fn apply(self: *Runtime, m: *const wf.Map, a: *const wf.Act) void {
        switch (a.kind) {
            .dialog, .wait, .preserve => {},
            .text => self.say(m.spanText(a.line)),
            .flag => if (a.slot < wf.MAX_FLAGS) {
                self.flags[a.slot] = switch (a.setop) {
                    .off => false,
                    .on => true,
                    .flip => !self.flags[a.slot],
                };
            },
            .counter => if (a.slot < wf.MAX_COUNTERS) {
                const cur = self.counters[a.slot];
                self.counters[a.slot] = switch (a.countop) {
                    .set => a.n,
                    .add => cur +| a.n,
                    .sub => cur -| a.n,
                };
            },
            .timer => if (a.slot < wf.MAX_TIMERS) {
                self.timers[a.slot] = a.v;
                self.armed[a.slot] = true;
            },
        }
    }

    pub fn applyAll(self: *Runtime, m: *const wf.Map, acts: []const wf.Act) void {
        for (acts) |*a| self.apply(m, a);
    }
};


const testMap = wf.testMap;
const HEAD = wf.TEST_HEAD;

test "every condition must hold, and an empty when-list never fires" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: both
        \\  when: flag a=1
        \\  when: flag b=1
        \\  do: counter hits add 1
        \\trig: naked
        \\  do: counter hits add 100
    );
    defer alloc.destroy(m);

    var rt = Runtime{};
    rt.arm(m);
    const hits = m.findCounter("hits").?;
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 0), rt.counters[hits]);

    rt.flags[m.findFlag("a").?] = true;
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 0), rt.counters[hits]);

    rt.flags[m.findFlag("b").?] = true;
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[hits]);
}

test "a one-shot fires once; preserve puts it back on the guard" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: once
        \\  when: always
        \\  do: counter a add 1
        \\trig: kept
        \\  when: always
        \\  do: counter b add 1
        \\  do: preserve
    );
    defer alloc.destroy(m);

    var rt = Runtime{};
    rt.arm(m);
    const a = m.findCounter("a").?;
    const b = m.findCounter("b").?;
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[a]);
    try std.testing.expectEqual(@as(i32, 1 + @as(i32, @intFromFloat(2.0 / REPEAT_GUARD))), rt.counters[b]);
}

test "priority decides who runs first, and file order breaks the tie" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: low pri=1
        \\  when: always
        \\  do: counter seq set 1
        \\trig: high pri=9
        \\  when: always
        \\  do: counter seq set 2
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    try std.testing.expectEqual(@as(u8, 1), rt.order[0]);
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[m.findCounter("seq").?]);
}

test "a wait blocks its own trigger's list and nothing else" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: slow
        \\  when: always
        \\  do: counter a set 1
        \\  do: wait 0.5
        \\  do: counter a set 2
        \\trig: quick
        \\  when: always
        \\  do: counter b set 1
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    const a = m.findCounter("a").?;
    const b = m.findCounter("b").?;
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[a]);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[b]);
    var t: f32 = 0;
    while (t < 0.4) : (t += 1.0 / 60.0) _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[a]);
    while (t < 0.7) : (t += 1.0 / 60.0) _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 2), rt.counters[a]);
}

test "a dialog action holds its own list until the conversation closes" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\dlg: chat
        \\  node: root
        \\  say: Well met.
        \\  then: end
        \\trig: talk
        \\  when: always
        \\  do: dialog chat
        \\  do: flag done=1
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    const done = m.findFlag("done").?;
    try std.testing.expectEqual(@as(?u16, 0), rt.tick(m, .{}, 1.0 / 60.0, false));
    _ = rt.tick(m, .{}, 1.0 / 60.0, true);
    try std.testing.expect(!rt.flags[done]);
    rt.dialogClosed();
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expect(rt.flags[done]);
    try std.testing.expect(rt.tick(m, .{}, 1.0 / 60.0, false) == null);
}

test "a busy screen defers the dialog rather than dropping it" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\dlg: chat
        \\  node: root
        \\  say: Hm.
        \\  then: end
        \\trig: talk
        \\  when: always
        \\  do: dialog chat
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    try std.testing.expect(rt.tick(m, .{}, 1.0 / 60.0, true) == null);
    try std.testing.expectEqual(@as(?u16, 0), rt.tick(m, .{}, 1.0 / 60.0, false));
}

test "a timer nobody started is not done, and one that ran out is" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: ring
        \\  when: timer dusk=done
        \\  do: flag rang=1
        \\trig: start
        \\  when: elapsed >= 0.2
        \\  do: timer dusk=0.3
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    const rang = m.findFlag("rang").?;
    var t: f32 = 0;
    while (t < 0.15) : (t += 1.0 / 60.0) _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expect(!rt.flags[rang]);
    while (t < 0.4) : (t += 1.0 / 60.0) _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expect(!rt.flags[rang]);
    while (t < 0.8) : (t += 1.0 / 60.0) _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expect(rt.flags[rang]);
}

test "region is LIVE, and near measures from the npc it names" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\dlg: hi
        \\  node: root
        \\  say: Ho.
        \\  then: end
        \\npc: wanderer 10 0 0 1 0 dlg=hi
        \\trig: inbox once=0
        \\  when: region -5 -5 5 5
        \\  do: counter inbox add 1
        \\  do: preserve
        \\trig: close
        \\  when: near npc=0 r=2.0
        \\  do: flag met=1
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    const inbox = m.findCounter("inbox").?;
    const met = m.findFlag("met").?;
    const post = [_]rl.Vector3{v3(10, 0, 0)};

    _ = rt.tick(m, .{ .heroPos = v3(30, 0, 30), .npcs = &post }, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 0), rt.counters[inbox]);
    _ = rt.tick(m, .{ .heroPos = v3(1, 0, 1), .npcs = &post }, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[inbox]);
    var t: f32 = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) _ = rt.tick(m, .{ .heroPos = v3(30, 0, 30), .npcs = &post }, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(i32, 1), rt.counters[inbox]);

    try std.testing.expect(!rt.flags[met]);
    _ = rt.tick(m, .{ .heroPos = v3(9.2, 0, 0), .npcs = &post }, 1.0 / 60.0, false);
    try std.testing.expect(rt.flags[met]);
}

test "deaths counts what the engine reports and alive what the world says" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: cleared
        \\  when: deaths toad >= 2
        \\  when: alive archer <= 0
        \\  do: flag done=1
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    const done = m.findFlag("done").?;
    var w = World{};
    w.alive[@intFromEnum(wf.FoeKind.archer)] = 1;
    rt.died(.toad);
    _ = rt.tick(m, w, 1.0 / 60.0, false);
    try std.testing.expect(!rt.flags[done]);
    rt.died(.toad);
    _ = rt.tick(m, w, 1.0 / 60.0, false);
    try std.testing.expect(!rt.flags[done]);
    w.alive[@intFromEnum(wf.FoeKind.archer)] = 0;
    _ = rt.tick(m, w, 1.0 / 60.0, false);
    try std.testing.expect(rt.flags[done]);
}

test "a counter saturates rather than wrapping" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: big
        \\  when: always
        \\  do: counter n set 2147483647
        \\  do: counter n add 5
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(std.math.maxInt(i32), rt.counters[m.findCounter("n").?]);
}

test "a wip trigger is never evaluated" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: draft wip=1
        \\  when: always
        \\  do: flag oops=1
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expect(!rt.flags[m.findFlag("oops").?]);
}

test "a text action puts a line up and it times out" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, HEAD ++
        \\trig: shout
        \\  when: always
        \\  do: text The gate grinds open somewhere to the north.
    );
    defer alloc.destroy(m);
    var rt = Runtime{};
    rt.arm(m);
    _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expect(std.mem.startsWith(u8, rt.bannerText(), "The gate grinds"));
    var t: f32 = 0;
    while (t < BANNER_DUR + 0.2) : (t += 1.0 / 60.0) _ = rt.tick(m, .{}, 1.0 / 60.0, false);
    try std.testing.expectEqual(@as(usize, 0), rt.bannerText().len);
}
