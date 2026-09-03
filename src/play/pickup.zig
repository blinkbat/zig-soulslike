const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const fx = @import("../props/propfx.zig");
const wf = @import("../world/worldfmt.zig");
const item = @import("item.zig");
// For their `REACH` alone — the two other rings this one is sized against (see the comptime block).
const chestmod = @import("chest.zig");
const soulsmod = @import("souls.zig");

const v3 = mathx.v3;


pub const CAP: usize = 96;

/// METRES on XZ from the glow's own origin. **Wider than the box and narrower than the drop**: `souls.REACH` is wider because you come back for that one under pressure, and this is narrower because a wisp of light has no body to bump into. NOT the widest ring in the game — `rest.REACH` is.
pub const REACH: f32 = 2.4;

pub const FADE_DUR: f32 = 0.42;

pub const DROP_MAX: usize = 2;

pub const Pickup = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own
    scale: f32 = 1,
    op: u16 = 0,
    loot: [DROP_MAX]item.Kind = undefined,
    nloot: u8 = 0,
    /// **COIN THIS GLOW IS CARRYING.** On a MAP glow the purse is the placing op's (`wf.Op.gold`); on a BODY
    /// drop it is what the corpse was worth, and it rides the SAME glow as the loot.
    gold: u32 = 0,
    taken: bool = false,
    fade: f32 = 0,

    pub fn topWorld(self: *const Pickup) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + (fx.PICKUP_H + 0.28) * self.scale, self.pos.z);
    }

    pub fn spent(self: *const Pickup) bool {
        return self.taken and self.fade >= 1.0;
    }

    pub fn sizeLeft(self: *const Pickup) f32 {
        return 1.0 - self.fade;
    }

    /// but money read as a map glow and `takeNear` went looking for a placing op that was never there.
    pub fn dropped(self: *const Pickup) bool {
        return self.nloot > 0 or self.gold > 0;
    }
};

pub const Taken = struct {
    at: rl.Vector3,
    loot: []const item.Kind,
    gold: u32 = 0,
};

pub const Pickups = struct {
    list: [CAP]Pickup = undefined,
    n: usize = 0,
    near: ?usize = null,
    mapped: usize = 0,

    pub fn live(self: *Pickups) []Pickup {
        return self.list[0..self.n];
    }
    pub fn liveConst(self: *const Pickups) []const Pickup {
        return self.list[0..self.n];
    }

    pub fn reset(self: *Pickups, sites: []const Site) void {
        self.n = 0;
        self.near = null;
        for (sites) |s| {
            if (self.n >= CAP) break;
            self.list[self.n] = .{ .pos = s.pos, .yaw = s.yaw, .scale = s.scale, .op = s.op };
            self.n += 1;
        }
        self.mapped = self.n;
    }

    /// **THE MAP'S HALF ALONE, AND IT IS ONE ACCESSOR BECAUSE TWO CALLERS NEED EXACTLY IT.** Its ORDER is the placing order — what `env.setPickupDraw` is indexed by and what a save slot's `pickups` bits are keyed to. Handed the whole list, both walk off the end and start reading body drops as map glows.
    pub fn mappedOnes(self: *Pickups) []Pickup {
        return self.list[0..@min(self.mapped, self.n)];
    }
    pub fn mappedConst(self: *const Pickups) []const Pickup {
        return self.list[0..@min(self.mapped, self.n)];
    }

    pub fn droppedOnes(self: *Pickups) []Pickup {
        return self.list[@min(self.mapped, self.n)..self.n];
    }
    pub fn droppedConst(self: *const Pickups) []const Pickup {
        return self.list[@min(self.mapped, self.n)..self.n];
    }

    pub fn clearDropped(self: *Pickups) void {
        self.n = @min(self.mapped, self.n);
        self.near = null;
    }

    /// Refuses an empty list, so `nloot > 0` stays the honest test for "this one is a drop".
    /// **A FULL LIST RECYCLES A SPENT SLOT BEFORE IT REFUSES** — a session kills far more than the 96 the cap shares with the map's glows, and a picked-up glow is a slot nobody can see. With none spendable the drop is DROPPED rather than overwriting a glow standing in front of you.
    pub fn spawn(self: *Pickups, at: rl.Vector3, kinds: []const item.Kind, gold: u32) void {
        if (kinds.len == 0 and gold == 0) return;
        const n = @min(kinds.len, DROP_MAX);
        var p: *Pickup = undefined;
        if (self.n < CAP) {
            p = &self.list[self.n];
            self.n += 1;
        } else {
            p = blk: {
                for (self.list[self.mapped..self.n]) |*q| {
                    if (q.spent()) break :blk q;
                }
                return;
            };
        }
        p.* = .{ .pos = at, .yaw = 0, .scale = 1, .op = 0, .nloot = @intCast(n), .gold = gold };
        for (kinds[0..n], 0..) |k, i| p.loot[i] = k;
    }

    pub fn update(self: *Pickups, dt: f32, heroPos: rl.Vector3) void {
        var near = mathx.Nearest.within(REACH);
        for (self.live(), 0..) |*p, i| {
            if (p.taken and p.fade < 1.0) p.fade = @min(1.0, p.fade + dt / FADE_DUR);
            if (p.taken) continue;
            near.offer(i, p.pos, heroPos);
        }
        self.near = near.best;
    }

    pub fn takeNear(self: *Pickups, m: *const wf.Map) ?Taken {
        const i = self.near orelse return null;
        var p = &self.list[i];
        if (p.taken) return null;
        p.taken = true;
        self.near = null;
        if (p.dropped()) return .{ .at = p.topWorld(), .loot = p.loot[0..p.nloot], .gold = p.gold };
        const op = p.op;
        const loot: []const item.Kind = if (op < m.nops) m.ops[op].loot[0..m.ops[op].nloot] else &.{};
        return .{ .at = p.topWorld(), .loot = loot, .gold = if (op < m.nops) m.ops[op].gold else 0 };
    }
};

pub const Site = struct {
    pos: rl.Vector3,
    yaw: f32,
    scale: f32,
    op: u16,
};

comptime {
    std.debug.assert(REACH > chestmod.REACH);
    std.debug.assert(REACH < soulsmod.REACH);
}

test "only an untaken glow in reach is one you can press, and it is spent exactly once" {
    var ps = Pickups{};
    ps.reset(&.{
        .{ .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 },
        .{ .pos = v3(40, 0, 0), .yaw = 0, .scale = 1, .op = 1 },
    });
    try std.testing.expectEqual(@as(usize, 2), ps.n);
    ps.update(1.0 / 60.0, v3(20, 0, 0));
    try std.testing.expect(ps.near == null);
    ps.update(1.0 / 60.0, v3(1.0, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), ps.near.?);
    ps.list[0].taken = true;
    ps.update(1.0 / 60.0, v3(1.0, 0, 0));
    try std.testing.expect(ps.near == null);
}

test "taking one hands back the placing op's loot, and only once" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("pickup");
    m.ops[0] = wf.defaults(.at);
    m.ops[0].kind = .pickup;
    m.ops[0].loot[0] = .mushroom_jerky;
    m.ops[0].loot[1] = .nameless_soul;
    m.ops[0].loot[2] = .nameless_soul;
    m.ops[0].nloot = 3;
    m.nops = 1;

    var ps = Pickups{};
    ps.reset(&.{.{ .pos = mathx.zero3, .yaw = 0, .scale = 1, .op = 0 }});
    ps.update(1.0 / 60.0, v3(0.5, 0, 0));
    const got = ps.takeNear(m).?;
    try std.testing.expectEqual(@as(usize, 3), got.loot.len);
    try std.testing.expectEqual(item.Kind.mushroom_jerky, got.loot[0]);
    ps.update(1.0 / 60.0, v3(0.5, 0, 0));
    try std.testing.expect(ps.takeNear(m) == null);
}

test "an out-of-range op index yields no loot rather than reading past the map" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("pickup");
    m.nops = 0;
    var ps = Pickups{};
    ps.reset(&.{.{ .pos = mathx.zero3, .yaw = 0, .scale = 1, .op = 900 }});
    ps.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expectEqual(@as(usize, 0), ps.takeNear(m).?.loot.len);
}

test "THE GLOW GOES OUT OVER ITS OWN FADE, and only then stops being drawn" {
    var ps = Pickups{};
    ps.reset(&.{.{ .pos = mathx.zero3, .yaw = 0, .scale = 1, .op = 0 }});
    const p = &ps.list[0];
    try std.testing.expect(!p.spent() and p.sizeLeft() == 1.0);
    p.taken = true;
    ps.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expect(!p.spent());
    try std.testing.expect(p.sizeLeft() < 1.0 and p.sizeLeft() > 0.9);
    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expect(p.spent());
    try std.testing.expectApproxEqAbs(@as(f32, 0), p.sizeLeft(), 1e-6);
}

test "THE FADE IS A FACTOR, NOT A SCALE — an oversized glow keeps its own size while it goes" {
    var ps = Pickups{};
    ps.reset(&.{.{ .pos = mathx.zero3, .yaw = 0, .scale = 2.5, .op = 0 }});
    const p = &ps.list[0];
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), p.sizeLeft(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), p.scale, 1e-6);
    p.taken = true;
    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), p.sizeLeft(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), p.scale, 1e-6);
}

test "A DROPPED GLOW IS A GLOW — it stands where the body fell, hands back its own list, and goes out" {
    var ps = Pickups{};
    ps.reset(&.{.{ .pos = v3(50, 0, 0), .yaw = 0, .scale = 1, .op = 0 }});
    try std.testing.expectEqual(@as(usize, 1), ps.mapped);
    try std.testing.expectEqual(@as(usize, 0), ps.droppedOnes().len);

    ps.spawn(v3(0, 0, 0), &.{ .bloodgrass, .toadflesh_broth }, 0);
    try std.testing.expectEqual(@as(usize, 2), ps.n);
    try std.testing.expectEqual(@as(usize, 1), ps.mapped);
    try std.testing.expectEqual(@as(usize, 1), ps.droppedOnes().len);
    try std.testing.expect(ps.droppedOnes()[0].dropped());
    try std.testing.expect(!ps.liveConst()[0].dropped());

    ps.spawn(v3(9, 0, 9), &.{}, 0);
    try std.testing.expectEqual(@as(usize, 2), ps.n);

    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("drop");
    m.nops = 0;
    ps.update(1.0 / 60.0, v3(0.4, 0, 0));
    const got = ps.takeNear(m).?;
    try std.testing.expectEqual(@as(usize, 2), got.loot.len);
    try std.testing.expectEqual(item.Kind.bloodgrass, got.loot[0]);
    try std.testing.expectEqual(item.Kind.toadflesh_broth, got.loot[1]);
    ps.update(1.0 / 60.0, v3(0.4, 0, 0));
    try std.testing.expect(ps.takeNear(m) == null);

    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, v3(0.4, 0, 0));
    try std.testing.expect(ps.droppedOnes()[0].spent());
    try std.testing.expectApproxEqAbs(@as(f32, 0), ps.droppedOnes()[0].sizeLeft(), 1e-6);
}

test "A FULL LIST RECYCLES A SPENT SLOT AND NEVER OVERWRITES ONE YOU CAN STILL SEE" {
    var ps = Pickups{};
    ps.reset(&.{});
    for (0..CAP) |_| ps.spawn(v3(0, 0, 0), &.{.bloodgrass}, 0);
    try std.testing.expectEqual(CAP, ps.n);
    ps.spawn(v3(1, 0, 1), &.{.kobold_fang}, 0);
    for (ps.liveConst()) |p| try std.testing.expectEqual(item.Kind.bloodgrass, p.loot[0]);
    ps.list[7].taken = true;
    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, v3(900, 0, 900));
    try std.testing.expect(ps.list[7].spent());
    ps.spawn(v3(1, 0, 1), &.{.kobold_fang}, 0);
    try std.testing.expectEqual(item.Kind.kobold_fang, ps.list[7].loot[0]);
    try std.testing.expect(!ps.list[7].taken);
    try std.testing.expectEqual(CAP, ps.n);
}

test "A PURSE ALONE IS A DROP — coin lands on the ground and is carried by the glow, not credited on the kill" {
    var ps = Pickups{};
    ps.reset(&.{});
    ps.spawn(v3(0, 0, 0), &.{}, 0);
    try std.testing.expectEqual(@as(usize, 0), ps.n);

    ps.spawn(v3(0, 0, 0), &.{}, 30);
    try std.testing.expectEqual(@as(usize, 1), ps.n);
    try std.testing.expect(ps.list[0].dropped());
    try std.testing.expectEqual(@as(u32, 30), ps.list[0].gold);

    // **ONE GLOW PER BODY**: coin and loot ride the same one, so a corpse leaves one thing to walk over.
    ps.spawn(v3(20, 0, 0), &.{.bloodgrass}, 45);
    try std.testing.expectEqual(@as(usize, 2), ps.n);
    try std.testing.expectEqual(@as(u8, 1), ps.list[1].nloot);
    try std.testing.expectEqual(@as(u32, 45), ps.list[1].gold);

    var m: wf.Map = undefined;
    m.nops = 0;
    ps.update(1.0 / 60.0, v3(20, 0, 0));
    const got = ps.takeNear(&m) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 45), got.gold);
    try std.testing.expectEqual(@as(usize, 1), got.loot.len);
}
