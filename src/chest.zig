const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const village = @import("propvillage.zig");
const wf = @import("worldfmt.zig");
const item = @import("item.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;

// ── THE CHESTS ──────────────────────────────────────────────────────────────────────────
// A box in the map → a prompt in reach → a lid that swings → items in the bag.
//
// A CHEST IS A PROP PLUS A ROW HERE. The BODY is `props.chest`, placed/culled/collided/drawn by the prop
// grid like anything static. What that cannot hold is the two things a chest has and a column does not:
// a MOVING PART (a prop draws as one model at one matrix; the LID needs a second — same answer
// `kobold.Model` gives its jaw and tail) and per-instance STATE.
//
// CONTENTS COME FROM THE PLACING OP (`map.ops[op].loot`), so editing the op IS editing the chest and
// there is no second table of what-holds-what. NOT a foe: no HP, no poise, no hurt volume, no Group.

/// How many chests one world may hold. Generous — they are 6 floats and a byte each.
pub const CAP: usize = 64;

/// How close you have to be for the prompt (metres, measured on XZ from the box's own origin).
pub const REACH: f32 = 2.1;
/// …and the lid takes this long to come up. Slow enough to be an EVENT — the one moment in this game
/// that is not a fight, and the only thing on screen worth watching while it happens.
pub const OPEN_DUR: f32 = 0.85;
/// How far back the lid falls, in degrees about the hinge. Past vertical, so it rests open rather than
/// balancing — a lid stopped at 90 reads as held.
pub const OPEN_DEG: f32 = 104.0;

pub const Chest = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own
    scale: f32 = 1,
    /// The op that placed it — where the contents come from.
    op: u16 = 0,
    /// 0 shut … 1 fully open. Eased, so the lid swings rather than snapping.
    swing: f32 = 0,
    opened: bool = false,

    /// Where the prompt hangs, and the point a "which chest am I near" test measures from.
    pub fn topWorld(self: *const Chest) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + (village.CHEST_TOP + 0.20) * self.scale, self.pos.z);
    }

    /// THE LID'S MATRIX. The mesh is authored about its hinge, so this is: swing about local X, then the
    /// hinge's own offset up and back, then the prop's yaw and world place — and in this codebase's
    /// convention `mul(a, b)` applies a FIRST, so it reads in that order left to right.
    pub fn lidXf(self: *const Chest) rl.Matrix {
        const s = self.scale;
        return mathx.mul(mathx.mul3(
            mathx.rx(-OPEN_DEG * ease(self.swing)),
            mathx.tr(0, village.CHEST_HINGE_Y * s, village.CHEST_HINGE_Z * s),
            mathx.scaleM(s, s, s),
        ), mathx.mul(mathx.ry(self.yaw), mathx.tr(self.pos.x, self.pos.y, self.pos.z)));
    }
};

/// Ease-out on the swing: a lid is heavy, so it leaves fast and settles slow. Linear reads mechanical,
/// which is the one thing this beat must not.
fn ease(u: f32) f32 {
    const t = mathx.clampF(u, 0, 1);
    return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
}

/// What opening a chest did, handed back rather than applied: the BAG belongs to the hero and this file
/// has no business reaching into him — the same reason `kobold.Kobold.update` returns an `Act` instead of
/// loosing its own stones.
pub const Opened = struct {
    at: rl.Vector3,
    loot: []const item.Kind,
};

pub const Chests = struct {
    lid: rl.Model = undefined,
    list: [CAP]Chest = undefined,
    n: usize = 0,
    /// Which one the hero could open right now, recomputed each frame — the prompt and the button press
    /// must agree, and they only can if there is one answer computed once.
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

    /// RE-HOME from the world. Called after `env.materialize`, because the chests ARE props: this walks
    /// what was actually placed rather than re-reading the ops, so a chest inside a scatter (or one moved
    /// by a sculpt re-plant) is found wherever it really ended up.
    pub fn reset(self: *Chests, sites: []const Site) void {
        self.n = 0;
        self.near = null;
        for (sites) |s| {
            if (self.n >= CAP) break;
            self.list[self.n] = .{ .pos = s.pos, .yaw = s.yaw, .scale = s.scale, .op = s.op };
            self.n += 1;
        }
    }

    /// Advance every lid and pick the one in reach. `heroPos` on XZ only — a chest at the foot of a bank
    /// is still the chest you are standing over.
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

    /// OPEN THE ONE IN REACH. Returns what was in it, or null if there was nothing to open — so the
    /// caller can fire the interaction unconditionally and let this decide, rather than duplicating the
    /// reach test at the input site where it would drift.
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

    /// The LIDS, drawn where the prop grid draws the bodies. Every chest's lid, unconditionally: a chest
    /// is already distance- and frustum-culled as a PROP, and culling the lid separately would need a
    /// second copy of that logic to disagree with the first.
    pub fn draw(self: *const Chests) void {
        for (self.liveConst()) |*c| {
            rl.drawMesh(self.lid.meshes[0], self.lid.materials[0], c.lidXf());
        }
    }
};

/// One chest found in the world. `env` fills these because it owns the prop list; keeping the type here
/// means `env` does not have to know what a chest IS, only that something wants the `.chest` instances.
pub const Site = struct {
    pos: rl.Vector3,
    yaw: f32,
    scale: f32,
    op: u16,
};

comptime {
    // The lid is authored about the hinge and posed by `lidXf` alone, so the two files must agree that
    // the hinge is on the BACK edge at the rim. A positive Z here would open the lid toward the player.
    std.debug.assert(village.CHEST_HINGE_Z < 0);
    // …and the hinge must be at the RIM, i.e. clear of the feet the carcase stands on. It was
    // `CHEST_BODY_H` — a foot's height short — which sank the closed lid into the box and left its hasp
    // eye 8.5 cm above the hasp it closes over. Asserted rather than commented, because the two numbers
    // live in the other file and nothing else would have said so.
    std.debug.assert(village.CHEST_HINGE_Y > village.CHEST_BODY_H);
    // The crown has to be above the rim by at least the dome that makes it, or `INFO.top` is describing
    // a silhouette the lid does not have.
    std.debug.assert(village.CHEST_TOP >= village.CHEST_HINGE_Y + village.CHEST_LID_R);
}

// ── tests ───────────────────────────────────────────────────────────────────────────────

test "the lid eases open and stops fully open" {
    var c = Chest{};
    try std.testing.expectEqual(@as(f32, 0), c.swing);
    c.opened = true;
    // Driven past its own duration: the swing clamps at 1 rather than running on, or a chest left alone
    // for a minute has its lid a hundred turns round the hinge.
    var t: f32 = 0;
    while (t < OPEN_DUR * 3.0) : (t += 1.0 / 60.0) {
        if (c.swing < 1.0) c.swing = @min(1.0, c.swing + (1.0 / 60.0) / OPEN_DUR);
    }
    try std.testing.expectEqual(@as(f32, 1.0), c.swing);
    // …and the ease is monotone from shut to open, which is what stops the lid backing up mid-swing.
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
    // Out of reach of both.
    cs.update(1.0 / 60.0, v3(20, 0, 0));
    try std.testing.expect(cs.near == null);
    // In reach of the first.
    cs.update(1.0 / 60.0, v3(1.0, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), cs.near.?);
    // Opened, it stops being a candidate however close you stand — otherwise the prompt never leaves and
    // the button keeps firing on an empty box.
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
    // A SECOND press gives nothing. This is the latch that stops a held button emptying one chest into
    // the bag sixty times a second.
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
