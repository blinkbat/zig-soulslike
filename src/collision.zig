const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;

// A flat arena with no verticality worth simulating, so this is purely 2D on XZ.

/// WHAT A SOLID IS MADE OF — carried for the benefit of whatever HITS it.
pub const Surface = enum { stone, wood, metal };

pub const Solid = struct {
    a: rl.Vector3, // segment start (XZ; Y ignored)
    b: rl.Vector3, // segment end
    r: f32, // capsule radius
    h: f32 = 1e9,
    surf: Surface = .stone,
};

pub fn circle(x: f32, z: f32, r: f32) Solid {
    return .{ .a = v3(x, 0, z), .b = v3(x, 0, z), .r = r };
}

pub fn capsule(ax: f32, az: f32, bx: f32, bz: f32, r: f32) Solid {
    return .{ .a = v3(ax, 0, az), .b = v3(bx, 0, bz), .r = r };
}

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

pub fn resolve(p: rl.Vector3, pr: f32, solids: []const Solid) rl.Vector3 {
    var out = p;
    var pass: u32 = 0;
    while (pass < 2) : (pass += 1) {
        for (solids) |s| out = pushOut(out, pr, s);
    }
    return out;
}

/// Inside `s` on XZ *and* below its blocking height?
pub fn blocksPoint(p: rl.Vector3, margin: f32, s: Solid) bool {
    if (p.y > s.h) return false; // over the top — clears it
    const q = mathx.closestOnSegXZ(p, s.a, s.b);
    const dx = p.x - q.x;
    const dz = p.z - q.z;
    const rr = s.r + margin;
    return dx * dx + dz * dz < rr * rr;
}

pub fn blockedBy(p: rl.Vector3, margin: f32, solids: []const Solid) bool {
    return blockerAt(p, margin, solids) != null;
}

/// …and WHICH KIND of thing blocked it.
pub fn blockerAt(p: rl.Vector3, margin: f32, solids: []const Solid) ?Surface {
    for (solids) |s| {
        if (blocksPoint(p, margin, s)) return s.surf;
    }
    return null;
}

// A LOOK IS A SEGMENT, AND IT IS TESTED EXACTLY. An arrow's flight is walked in steps because it is a
// path being simulated anyway (`archer.coverHit`); a sight line is one question, and sampling it would
// mean either a step fine enough to cost real time over 20 m or a step a fence post fits through.

fn segDistXZ(a0: rl.Vector3, a1: rl.Vector3, b0: rl.Vector3, b1: rl.Vector3) f32 {
    if (segsCrossXZ(a0, a1, b0, b1)) return 0;
    // Not crossing: the closest approach is at one of the four ENDPOINTS, against the other segment.
    var best = mathx.distXZ(a0, mathx.closestOnSegXZ(a0, b0, b1));
    best = @min(best, mathx.distXZ(a1, mathx.closestOnSegXZ(a1, b0, b1)));
    best = @min(best, mathx.distXZ(b0, mathx.closestOnSegXZ(b0, a0, a1)));
    return @min(best, mathx.distXZ(b1, mathx.closestOnSegXZ(b1, a0, a1)));
}

fn crossXZ(o: rl.Vector3, p: rl.Vector3, q: rl.Vector3) f32 {
    return (p.x - o.x) * (q.z - o.z) - (p.z - o.z) * (q.x - o.x);
}

fn segsCrossXZ(a0: rl.Vector3, a1: rl.Vector3, b0: rl.Vector3, b1: rl.Vector3) bool {
    const d1 = crossXZ(a0, a1, b0);
    const d2 = crossXZ(a0, a1, b1);
    const d3 = crossXZ(b0, b1, a0);
    const d4 = crossXZ(b0, b1, a1);
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0));
}

/// Does this one solid stand in the way of a look from `a` to `b`? The look passes OVER anything whose
/// blocking height is under both ends of it, which is what keeps a kerb from hiding a man behind it.
pub fn blocksSight(a: rl.Vector3, b: rl.Vector3, s: Solid) bool {
    if (@min(a.y, b.y) >= s.h) return false;
    // A BOX REJECT BEFORE THE EXACT TEST. A sight line is asked of every solid in the cells it crosses,
    // and in a wood that is a hundred trunks the look misses by twenty metres — four comparisons throw
    // nearly all of them out for a fifth of what the segment-vs-segment answer costs.
    if (@min(s.a.x, s.b.x) - s.r > @max(a.x, b.x) or @max(s.a.x, s.b.x) + s.r < @min(a.x, b.x)) return false;
    if (@min(s.a.z, s.b.z) - s.r > @max(a.z, b.z) or @max(s.a.z, s.b.z) + s.r < @min(a.z, b.z)) return false;
    return segDistXZ(a, b, s.a, s.b) < s.r;
}

test "a look is stopped by what stands in it and by nothing else" {
    const wall = capsule(-3, 0, 3, 0, 0.4); // a run of wall across z = 0
    const eye = v3(0, 1.3, -6);
    try std.testing.expect(blocksSight(eye, v3(0, 1.3, 6), wall)); // straight through it
    try std.testing.expect(!blocksSight(eye, v3(0, 1.3, -1), wall)); // stops short of it
    try std.testing.expect(!blocksSight(v3(9, 1.3, -6), v3(9, 1.3, 6), wall)); // wide of its end
    // A THIN POST CANNOT BE TUNNELLED: the test is exact, so a 0.2 m pillar at 20 m still stops the look.
    const post = circle(0, 0, 0.2);
    try std.testing.expect(blocksSight(v3(0, 1.3, -20), v3(0, 1.3, 20), post));
    try std.testing.expect(!blocksSight(v3(0.5, 1.3, -20), v3(0.5, 1.3, 20), post));
}

test "a look passes over a kerb and is stopped by a wall of the same footprint" {
    var kerb = circle(0, 0, 1.0);
    kerb.h = 0.5;
    var wall = circle(0, 0, 1.0);
    wall.h = 3.0;
    const from = v3(0, 1.3, -4);
    const to = v3(0, 1.4, 4);
    try std.testing.expect(!blocksSight(from, to, kerb));
    try std.testing.expect(blocksSight(from, to, wall));
    // …and a look taken from the DIRT (a body on the ground) does not clear the kerb.
    try std.testing.expect(blocksSight(v3(0, 0.2, -4), to, kerb));
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
