const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const fx = @import("propfx.zig");
const wf = @import("worldfmt.zig");
const item = @import("item.zig");
// For their `REACH` alone — the two other rings this one is sized against (see the comptime block).
const chestmod = @import("chest.zig");
const soulsmod = @import("souls.zig");

const v3 = mathx.v3;

// **A GLOW IN THE MAP → A PROMPT IN REACH → ITEMS IN THE BAG.** Elden Ring's item pickup: the thing standing
// on the ground that says something is here, holding 1+ items exactly as a chest does (`Op.loot`).

/// How many pickups one world may hold. Generously above the chest's cap: a glow is a handful of triangles and
/// scattering them is the cheap way to dress a ruin, where a chest is furniture you place deliberately.
pub const CAP: usize = 96;

/// How close you have to be for the prompt (metres, on XZ from the glow's own origin). **Wider than the box
/// and narrower than the drop** — `souls.REACH` is 2.6 because you come back for that one under pressure, and
/// this is 2.4 for the other half of that reason: the thing is a wisp of light with no body to bump into, so
/// a ring sized like a box's makes you hunt for the spot it answers on. It is NOT the widest ring in the game
/// and the asserts below do not claim it is — `rest.REACH` is 3.2, and a bonfire is a thing you walk at rather
/// than a thing you have to find the spot of.
pub const REACH: f32 = 2.4;

/// How long the glow takes to go once it is taken — it does not vanish on the frame you press.
pub const FADE_DUR: f32 = 0.42;

pub const Pickup = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own
    scale: f32 = 1,
    /// The op that placed it — where the contents come from, the chest's own arrangement.
    op: u16 = 0,
    taken: bool = false,
    /// 0 standing … 1 gone. The mesh is scaled off this, so a taken glow shrinks out rather than blinking.
    fade: f32 = 0,

    /// Where the prompt hangs — over the wisp's own head, so the label is not buried in the light.
    pub fn topWorld(self: *const Pickup) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + (fx.PICKUP_H + 0.28) * self.scale, self.pos.z);
    }

    /// **GONE FOR GOOD ONLY ONCE THE FADE IS OUT.** `taken` is the mechanic and this is the picture: the prop
    /// grid stops drawing it here, so the two cannot disagree about whether there is still something to see.
    pub fn spent(self: *const Pickup) bool {
        return self.taken and self.fade >= 1.0;
    }

    /// **HOW MUCH OF ITS SIZE IS LEFT, 1..0 — a FACTOR and not a scale.** It shrinks out as it goes, which is a
    /// light being taken up rather than one switched off. Deliberately does NOT multiply in `self.scale`: the
    /// prop keeps its own authored scale and this is applied on top (`env.Prop.shrink`), or the fade compounds
    /// into the authoring the moment anything reads the prop's scale back.
    pub fn sizeLeft(self: *const Pickup) f32 {
        return 1.0 - self.fade;
    }
};

pub const Taken = struct {
    at: rl.Vector3,
    loot: []const item.Kind,
};

pub const Pickups = struct {
    list: [CAP]Pickup = undefined,
    n: usize = 0,
    near: ?usize = null,

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
    }

    pub fn update(self: *Pickups, dt: f32, heroPos: rl.Vector3) void {
        var near = mathx.Nearest.within(REACH);
        for (self.live(), 0..) |*p, i| {
            if (p.taken and p.fade < 1.0) p.fade = @min(1.0, p.fade + dt / FADE_DUR);
            if (p.taken) continue; // taken is taken — no prompt, nothing to press
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
        const op = p.op;
        // An out-of-range op yields NO loot rather than reading past the map — the chest's own guard.
        const loot: []const item.Kind = if (op < m.nops) m.ops[op].loot[0..m.ops[op].nloot] else &.{};
        return .{ .at = p.topWorld(), .loot = loot };
    }
};

pub const Site = struct {
    pos: rl.Vector3,
    yaw: f32,
    scale: f32,
    op: u16,
};

comptime {
    // It has to out-reach the box, for the reason written at `REACH`: there is no body here to walk into.
    std.debug.assert(REACH > chestmod.REACH);
    // …and it stays UNDER the souls drop's, which is the widest ring in the game and is meant to stay that way:
    // that one you come back for under pressure.
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
    // **1+ ITEMS, AND REPEATS COUNT** — the chest's own list semantics: two cracked runes is two.
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
    // Taken but still standing: the prop grid keeps drawing it while it shrinks out.
    ps.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expect(!p.spent());
    try std.testing.expect(p.sizeLeft() < 1.0 and p.sizeLeft() > 0.9);
    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expect(p.spent());
    try std.testing.expectApproxEqAbs(@as(f32, 0), p.sizeLeft(), 1e-6);
}

test "THE FADE IS A FACTOR, NOT A SCALE — an oversized glow keeps its own size while it goes" {
    // THE BUG this guards: the shrink used to be `scale * (1 - fade)` written straight into the prop's `scale`,
    // which `env.pickupSites` reads back out as the site's authored scale — so a glow taken in play came home
    // from the editor permanently shrunken. `sizeLeft` is 1..0 whatever the prop was placed at.
    var ps = Pickups{};
    ps.reset(&.{.{ .pos = mathx.zero3, .yaw = 0, .scale = 2.5, .op = 0 }});
    const p = &ps.list[0];
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), p.sizeLeft(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), p.scale, 1e-6); // …and the authored scale is untouched
    p.taken = true;
    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), p.sizeLeft(), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), p.scale, 1e-6);
}
