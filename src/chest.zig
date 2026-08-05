const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const village = @import("propvillage.zig");
const wf = @import("worldfmt.zig");
const item = @import("item.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;

// A box in the map → a prompt in reach → a lid that swings → items in the bag.

/// How many chests one world may hold.
pub const CAP: usize = 64;

/// How close you have to be for the prompt (metres, measured on XZ from the box's own origin).
pub const REACH: f32 = 2.1;
/// …and the lid takes this long to come up.
pub const OPEN_DUR: f32 = 0.85;
/// How far back the lid falls, in degrees about the hinge.
pub const OPEN_DEG: f32 = 104.0;

pub const Chest = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own
    scale: f32 = 1,
    /// The op that placed it — where the contents come from.
    op: u16 = 0,
    /// 0 shut … 1 fully open.
    swing: f32 = 0,
    opened: bool = false,

    /// Where the prompt hangs. NOT what `Chests.update` measures reach from — that is the box's own
    /// origin, as `REACH` says.
    pub fn topWorld(self: *const Chest) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + (village.CHEST_TOP + 0.20) * self.scale, self.pos.z);
    }

    pub fn lidXf(self: *const Chest) rl.Matrix {
        const s = self.scale;
        return mathx.mul(mathx.mul3(
            mathx.rx(-OPEN_DEG * ease(self.swing)),
            mathx.tr(0, village.CHEST_HINGE_Y * s, village.CHEST_HINGE_Z * s),
            mathx.scaleM(s, s, s),
        ), mathx.mul(mathx.ry(self.yaw), mathx.tr(self.pos.x, self.pos.y, self.pos.z)));
    }
};

/// Ease-out on the swing: a lid is heavy, so it leaves fast and settles slow.
fn ease(u: f32) f32 {
    const t = mathx.clampF(u, 0, 1);
    return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
}

pub const Opened = struct {
    at: rl.Vector3,
    loot: []const item.Kind,
};

pub const Chests = struct {
    lid: rl.Model = undefined,
    list: [CAP]Chest = undefined,
    n: usize = 0,
    near: ?usize = null,

    pub fn init(shader: rl.Shader) Chests {
        return .{ .lid = village.chestLidMesh(shader) };
    }
    pub fn setShader(self: *Chests, sh: rl.Shader) void {
        self.lid.materials[0].shader = sh;
    }

    pub fn live(self: *Chests) []Chest {
        return self.list[0..self.n];
    }
    pub fn liveConst(self: *const Chests) []const Chest {
        return self.list[0..self.n];
    }

    pub fn reset(self: *Chests, sites: []const Site) void {
        self.n = 0;
        self.near = null;
        for (sites) |s| {
            if (self.n >= CAP) break;
            self.list[self.n] = .{ .pos = s.pos, .yaw = s.yaw, .scale = s.scale, .op = s.op };
            self.n += 1;
        }
    }

    pub fn update(self: *Chests, dt: f32, heroPos: rl.Vector3) void {
        var best: ?usize = null;
        var bestD: f32 = REACH * REACH;
        for (self.live(), 0..) |*c, i| {
            if (c.opened and c.swing < 1.0) c.swing = @min(1.0, c.swing + dt / OPEN_DUR);
            if (c.opened) continue; // an open chest is scenery again — no prompt, nothing to press
            const d = mathx.dist2XZ(c.pos, heroPos);
            if (d < bestD) {
                bestD = d;
                best = i;
            }
        }
        self.near = best;
    }

    pub fn openNear(self: *Chests, m: *const wf.Map) ?Opened {
        const i = self.near orelse return null;
        var c = &self.list[i];
        if (c.opened) return null;
        c.opened = true;
        self.near = null;
        sfx.world(.chest_open, c.pos);
        const op = c.op;
        const loot: []const item.Kind = if (op < m.nops) m.ops[op].loot[0..m.ops[op].nloot] else &.{};
        return .{ .at = c.topWorld(), .loot = loot };
    }

    /// The LIDS, drawn where the prop grid draws the bodies.
    pub fn draw(self: *const Chests) void {
        for (self.liveConst()) |*c| {
            rl.drawMesh(self.lid.meshes[0], self.lid.materials[0], c.lidXf());
        }
    }
};

pub const Site = struct {
    pos: rl.Vector3,
    yaw: f32,
    scale: f32,
    op: u16,
};

comptime {
    std.debug.assert(village.CHEST_HINGE_Z < 0);
    // …and the hinge must be at the RIM, i.e. clear of the feet the carcase stands on.
    std.debug.assert(village.CHEST_HINGE_Y > village.CHEST_BODY_H);
    std.debug.assert(village.CHEST_TOP >= village.CHEST_HINGE_Y + village.CHEST_LID_R);
}


test "the lid eases open and stops fully open" {
    var c = Chest{};
    try std.testing.expectEqual(@as(f32, 0), c.swing);
    c.opened = true;
    var t: f32 = 0;
    while (t < OPEN_DUR * 3.0) : (t += 1.0 / 60.0) {
        if (c.swing < 1.0) c.swing = @min(1.0, c.swing + (1.0 / 60.0) / OPEN_DUR);
    }
    try std.testing.expectEqual(@as(f32, 1.0), c.swing);
    try std.testing.expect(ease(0) == 0 and ease(1) == 1);
    try std.testing.expect(ease(0.5) > 0.5); // ease-OUT: most of the travel is early
}

test "only a shut chest in reach is the one you can open" {
    var cs = Chests{};
    cs.reset(&.{
        .{ .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 },
        .{ .pos = v3(40, 0, 0), .yaw = 0, .scale = 1, .op = 1 },
    });
    try std.testing.expectEqual(@as(usize, 2), cs.n);
    cs.update(1.0 / 60.0, v3(20, 0, 0));
    try std.testing.expect(cs.near == null);
    cs.update(1.0 / 60.0, v3(1.0, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), cs.near.?);
    cs.list[0].opened = true;
    cs.update(1.0 / 60.0, v3(1.0, 0, 0));
    try std.testing.expect(cs.near == null);
}

test "opening hands back the placing op's loot, and only once" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("chest");
    m.ops[0] = wf.defaults(.at);
    m.ops[0].kind = .chest;
    m.ops[0].loot[0] = .golden_seed;
    m.ops[0].loot[1] = .rune_arc;
    m.ops[0].nloot = 2;
    m.nops = 1;

    var cs = Chests{};
    cs.reset(&.{.{ .pos = mathx.zero3, .yaw = 0, .scale = 1, .op = 0 }});
    cs.update(1.0 / 60.0, v3(0.5, 0, 0));
    const got = cs.openNear(m).?;
    try std.testing.expectEqual(@as(usize, 2), got.loot.len);
    try std.testing.expectEqual(item.Kind.golden_seed, got.loot[0]);
    cs.update(1.0 / 60.0, v3(0.5, 0, 0));
    try std.testing.expect(cs.openNear(m) == null);
}

test "an out-of-range op index yields no loot rather than reading past the map" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("chest");
    m.nops = 0;
    var cs = Chests{};
    cs.reset(&.{.{ .pos = mathx.zero3, .yaw = 0, .scale = 1, .op = 900 }});
    cs.update(1.0 / 60.0, mathx.zero3);
    try std.testing.expectEqual(@as(usize, 0), cs.openNear(m).?.loot.len);
}
