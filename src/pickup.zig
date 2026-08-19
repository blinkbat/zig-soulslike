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

/// **HOW MANY KINDS ONE DROPPED GLOW CAN CARRY** — a body leaves its guaranteed row and at most one rare
/// (`drops.roll`), so this is that arithmetic and not a round number.
pub const DROP_MAX: usize = 2;

pub const Pickup = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own
    scale: f32 = 1,
    /// The op that placed it — where the contents come from, the chest's own arrangement.
    op: u16 = 0,
    /// **WHAT A DROPPED ONE IS CARRYING, INLINE.** A glow the MAP placed reads its contents back off the op
    /// that placed it; one a BODY left has no op to read, so it carries the list itself. `nloot > 0` is the
    /// whole of the distinction, and it is also what says this glow has no prop in `env` behind it.
    loot: [DROP_MAX]item.Kind = undefined,
    nloot: u8 = 0,
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

    /// **IS THIS ONE A BODY'S, RATHER THAN THE MAP'S.** The map's have a prop in `env` drawing them and take
    /// their contents off an op; a dropped one is drawn by the loop off its own model and carries its list.
    pub fn dropped(self: *const Pickup) bool {
        return self.nloot > 0;
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
    /// **HOW MANY OF THE LIST THE MAP PLACED.** Everything below it has a prop in `env` drawing it (and is fed
    /// `sizeLeft`/`spent` through `env.setPickupDraw`, which is indexed by exactly this order); everything at
    /// or above it was dropped by a body and is drawn by the loop instead. Written by `reset` and by nothing
    /// else, so the two halves cannot get interleaved.
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
        // A WORLD RELOAD CLEARS THE GROUND, drops included: they belong to the world that was standing.
        self.mapped = self.n;
    }

    /// **THE MAP'S HALF ALONE, AND IT IS ONE ACCESSOR BECAUSE TWO CALLERS NEED EXACTLY IT.** Its ORDER is the
    /// placing order — which is what `env.setPickupDraw` is indexed by (`game.hidePickups`) and what a save
    /// slot's `pickups` bits are keyed to (`save.gather`/`scatter`). Handed the whole list, both of those walk
    /// off the end of the thing they mean and start reading body drops as map glows.
    pub fn mappedOnes(self: *Pickups) []Pickup {
        return self.list[0..@min(self.mapped, self.n)];
    }
    pub fn mappedConst(self: *const Pickups) []const Pickup {
        return self.list[0..@min(self.mapped, self.n)];
    }

    /// The dropped half alone, for the loop that has to draw them itself.
    pub fn droppedOnes(self: *Pickups) []Pickup {
        return self.list[@min(self.mapped, self.n)..self.n];
    }

    /// **A BODY LEFT SOMETHING ON THE GROUND** (`drops.roll` → `game.billDeaths`). Refuses an empty list, so
    /// `nloot > 0` stays the honest test for "this one is a drop".
    ///
    /// **A FULL LIST RECYCLES A SPENT SLOT BEFORE IT REFUSES.** The cap is shared with the map's own glows and
    /// a long session kills far more than 96 things — but a glow that has been picked up is a slot nobody can
    /// see, so the ground never silently loses something you could still walk to. With none spendable the
    /// drop is DROPPED, which is the honest failure: better than overwriting a glow standing in front of you.
    pub fn spawn(self: *Pickups, at: rl.Vector3, kinds: []const item.Kind) void {
        if (kinds.len == 0) return;
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
                return; // every slot is a glow somebody can still see
            };
        }
        p.* = .{ .pos = at, .yaw = 0, .scale = 1, .op = 0, .nloot = @intCast(n) };
        for (kinds[0..n], 0..) |k, i| p.loot[i] = k;
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
        // A DROPPED ONE CARRIES ITS OWN LIST; only a map-placed glow has an op to read it off.
        if (p.dropped()) return .{ .at = p.topWorld(), .loot = p.loot[0..p.nloot] };
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

test "A DROPPED GLOW IS A GLOW — it stands where the body fell, hands back its own list, and goes out" {
    var ps = Pickups{};
    // One placed by the MAP first, so the two halves are actually mixed rather than tested apart.
    ps.reset(&.{.{ .pos = v3(50, 0, 0), .yaw = 0, .scale = 1, .op = 0 }});
    try std.testing.expectEqual(@as(usize, 1), ps.mapped);
    try std.testing.expectEqual(@as(usize, 0), ps.droppedOnes().len);

    ps.spawn(v3(0, 0, 0), &.{ .bloodgrass, .toadflesh_broth });
    try std.testing.expectEqual(@as(usize, 2), ps.n);
    try std.testing.expectEqual(@as(usize, 1), ps.mapped); // the map's half did not move
    try std.testing.expectEqual(@as(usize, 1), ps.droppedOnes().len);
    try std.testing.expect(ps.droppedOnes()[0].dropped());
    try std.testing.expect(!ps.liveConst()[0].dropped()); // …and the map's one still reads its op

    // AN EMPTY HANDFUL IS NOT A GLOW: `nloot > 0` has to stay the honest test for "this one is a drop".
    ps.spawn(v3(9, 0, 9), &.{});
    try std.testing.expectEqual(@as(usize, 2), ps.n);

    // Walk to it and take it — the loot is the drop's OWN list, with no map to read it off.
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("drop");
    m.nops = 0;
    ps.update(1.0 / 60.0, v3(0.4, 0, 0));
    const got = ps.takeNear(m).?;
    try std.testing.expectEqual(@as(usize, 2), got.loot.len);
    try std.testing.expectEqual(item.Kind.bloodgrass, got.loot[0]);
    try std.testing.expectEqual(item.Kind.toadflesh_broth, got.loot[1]);
    // …and it is spent exactly once, whatever else is standing about.
    ps.update(1.0 / 60.0, v3(0.4, 0, 0));
    try std.testing.expect(ps.takeNear(m) == null);

    // THE GLOW GOES OUT AND STOPS BEING DRAWN — `game.drawDrops` skips a spent one, which is what takes it
    // off the ground rather than leaving a zero-sized wisp standing in it.
    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, v3(0.4, 0, 0));
    try std.testing.expect(ps.droppedOnes()[0].spent());
    try std.testing.expectApproxEqAbs(@as(f32, 0), ps.droppedOnes()[0].sizeLeft(), 1e-6);
}

test "A FULL LIST RECYCLES A SPENT SLOT AND NEVER OVERWRITES ONE YOU CAN STILL SEE" {
    var ps = Pickups{};
    ps.reset(&.{});
    for (0..CAP) |_| ps.spawn(v3(0, 0, 0), &.{.bloodgrass});
    try std.testing.expectEqual(CAP, ps.n);
    // Full, and every one of them still standing: the drop is DROPPED rather than eating a live glow.
    ps.spawn(v3(1, 0, 1), &.{.kobold_fang});
    for (ps.liveConst()) |p| try std.testing.expectEqual(item.Kind.bloodgrass, p.loot[0]);
    // …and once one has been taken and faded out, its slot is what the next drop lands in.
    ps.list[7].taken = true;
    var t: f32 = 0;
    while (t < FADE_DUR * 2.0) : (t += 1.0 / 60.0) ps.update(1.0 / 60.0, v3(900, 0, 900));
    try std.testing.expect(ps.list[7].spent());
    ps.spawn(v3(1, 0, 1), &.{.kobold_fang});
    try std.testing.expectEqual(item.Kind.kobold_fang, ps.list[7].loot[0]);
    try std.testing.expect(!ps.list[7].taken); // a fresh glow, not a spent one wearing new loot
    try std.testing.expectEqual(CAP, ps.n);
}
