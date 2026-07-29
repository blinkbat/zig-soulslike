const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;

// ── GROUND-PLANE COLLISION ──────────────────────────────────────────────────────────────
// A flat arena with no verticality worth simulating, so collision is purely 2D on XZ. Every
// solid is a CAPSULE (segment a→b, radius r; a==b is a plain circle) and actors are circles
// PUSHED OUT along the shortest exit. A wall is one fat capsule down its length, a pillar a
// circle, a ruin block a short capsule. Cheap, allocation-free, robust for footprints.

pub const Solid = struct {
    a: rl.Vector3, // segment start (XZ; Y ignored)
    b: rl.Vector3, // segment end
    r: f32, // capsule radius
    // Blocking HEIGHT for projectiles (world Y of the obstacle's top): an arrow above flies
    // clear, below thunks in; footprint push-out stays 2D and ignores it. Defaults sky-high
    // so a Solid built without one blocks everything.
    h: f32 = 1e9,
};

/// A circular obstacle (a==b).
pub fn circle(x: f32, z: f32, r: f32) Solid {
    return .{ .a = v3(x, 0, z), .b = v3(x, 0, z), .r = r };
}

/// A capsule from (ax,az) to (bx,bz) with radius r.
pub fn capsule(ax: f32, az: f32, bx: f32, bz: f32, r: f32) Solid {
    return .{ .a = v3(ax, 0, az), .b = v3(bx, 0, bz), .r = r };
}

/// Push a circle (centre `p`, radius `pr`) out of one solid; returns the corrected centre
/// (Y preserved). No-op when already clear.
pub fn pushOut(p: rl.Vector3, pr: f32, s: Solid) rl.Vector3 {
    const q = mathx.closestOnSegXZ(p, s.a, s.b);
    const dx = p.x - q.x;
    const dz = p.z - q.z;
    const mind = pr + s.r;
    const d2 = dx * dx + dz * dz;
    if (d2 >= mind * mind) return p;
    const d = @sqrt(d2);
    if (d < 1e-5) return v3(p.x + mind, p.y, p.z); // dead centre: shove out along +X (arbitrary but stable)
    const k = (mind - d) / d;
    return v3(p.x + dx * k, p.y, p.z + dz * k);
}

/// Push a circle out of a plain circular obstacle (actor-vs-actor).
pub fn pushOutCircle(p: rl.Vector3, pr: f32, c: rl.Vector3, cr: f32) rl.Vector3 {
    return pushOut(p, pr, .{ .a = c, .b = c, .r = cr });
}

/// Resolve a circle against many solids. Two passes settle the common case of overlapping
/// two solids at once (an inside corner) without a full iterative solver.
pub fn resolve(p: rl.Vector3, pr: f32, solids: []const Solid) rl.Vector3 {
    var out = p;
    var pass: u32 = 0;
    while (pass < 2) : (pass += 1) {
        for (solids) |s| out = pushOut(out, pr, s);
    }
    return out;
}

/// Is the point `p` (a projectile in flight) inside solid `s` on XZ *and* below its blocking
/// height? The projectile counterpart of pushOut — this is what makes COVER work: an arrow
/// tests its flight against the same solids feet resolve against.
pub fn blocksPoint(p: rl.Vector3, margin: f32, s: Solid) bool {
    if (p.y > s.h) return false; // over the top — clears it
    const q = mathx.closestOnSegXZ(p, s.a, s.b);
    const dx = p.x - q.x;
    const dz = p.z - q.z;
    const rr = s.r + margin;
    return dx * dx + dz * dz < rr * rr;
}

/// Does ANY of these solids block the point? (Yes/no only — it deliberately doesn't say which,
/// because no caller has ever needed to know: arrow flight embeds the shaft along its own velocity
/// and the flora scatter just rejects the spot.)
pub fn blockedBy(p: rl.Vector3, margin: f32, solids: []const Solid) bool {
    for (solids) |s| {
        if (blocksPoint(p, margin, s)) return true;
    }
    return false;
}

test "pushOut clears a circle overlap to exactly touching" {
    const s = circle(0, 0, 1.0);
    const out = pushOut(v3(0.3, 0, 0), 0.5, s); // centres 0.3 apart, need 1.5
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), @sqrt(out.x * out.x + out.z * out.z), 1e-4);
}

test "pushOut leaves a clear circle untouched" {
    const s = circle(0, 0, 1.0);
    const out = pushOut(v3(5, 0, 0), 0.5, s);
    try std.testing.expectApproxEqAbs(@as(f32, 5), out.x, 1e-6);
}

test "pushOut against a capsule exits perpendicular to its length" {
    const s = capsule(-2, 0, 2, 0, 0.5); // along X at z=0
    const out = pushOut(v3(0, 0, 0.6), 0.4, s); // above the middle, need 0.9 of clearance in z
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), out.z, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), out.x, 1e-4);
}

test "dead-centre push is finite and separates" {
    const s = circle(0, 0, 1.0);
    const out = pushOut(v3(0, 0, 0), 0.5, s);
    try std.testing.expect(std.math.isFinite(out.x) and out.x > 1.0);
}

test "blocksPoint respects the blocking height: hits below the top, clears above it" {
    var s = circle(0, 0, 1.0);
    s.h = 3.0;
    try std.testing.expect(blocksPoint(v3(0.5, 1.2, 0), 0.05, s)); // chest-high shot into the pier
    try std.testing.expect(!blocksPoint(v3(0.5, 3.5, 0), 0.05, s)); // lobbed clean over the top
    try std.testing.expect(!blocksPoint(v3(2.0, 1.2, 0), 0.05, s)); // wide of it entirely
}
