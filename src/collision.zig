const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;

// ── GROUND-PLANE COLLISION ──────────────────────────────────────────────────────────────
// A flat soulslike arena: no verticality worth simulating, so collision is purely 2D on the
// XZ plane. Every solid is a CAPSULE — a segment a→b with radius r (a plain circle is the
// a==b degenerate). Actors are circles that get PUSHED OUT of solids along the shortest
// exit. Walls are one fat capsule down their length; pillars/blocks/piers are circles; a
// long ruin block is a short capsule. Cheap, allocation-free, and robust for footprints.

pub const Solid = struct {
    a: rl.Vector3, // segment start (XZ; Y ignored)
    b: rl.Vector3, // segment end
    r: f32, // capsule radius
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
