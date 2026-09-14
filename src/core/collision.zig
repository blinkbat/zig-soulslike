const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;


pub const Surface = enum { stone, wood, metal };

pub const Solid = struct {
    a: rl.Vector3,
    b: rl.Vector3,
    r: f32,
    h: f32 = 1e9,
    /// **AND WHERE IT STARTS** — 0 for every wall in the world, positive only for a LINTEL.
    y0: f32 = 0,
    surf: Surface = .stone,
    /// The gate's slot in `env.wardProps` PLUS ONE, so 0 is an ordinary solid. A wall to every BODY but the hero's
    /// own side, in both directions, and to every LOOK without exception; only `env.resolveHeroSide` opens one.
    ward: u8 = 0,
    /// An illusory wall's slot in `env.illusionProps` PLUS ONE; `env.eachSolid` drops it the frame the wall is struck.
    illusion: u8 = 0,
    /// SQUARE ENDS: the solid is the capsule's bounding rectangle in the segment's frame — `r` across, the segment plus `r` each way along.
    flat: bool = false,
    /// MASONRY — `env.masonry` (`Info.solid`, less the one veil that thins) and the cliff stamps. The boom shortens
    /// on these and on nothing else; everything else answers the lens by going thin (`env.markOccluders`).
    arch: bool = false,
};

pub fn circle(x: f32, z: f32, r: f32) Solid {
    return .{ .a = v3(x, 0, z), .b = v3(x, 0, z), .r = r };
}

pub fn capsule(ax: f32, az: f32, bx: f32, bz: f32, r: f32) Solid {
    return .{ .a = v3(ax, 0, az), .b = v3(bx, 0, bz), .r = r };
}

pub fn box(ax: f32, az: f32, bx: f32, bz: f32, r: f32) Solid {
    return .{ .a = v3(ax, 0, az), .b = v3(bx, 0, bz), .r = r, .flat = true };
}

/// A flat solid's rectangle: centre, unit axis along the segment, and half-length INCLUDING the end radius (the half-width is `r`).
pub const Frame = struct { cx: f32, cz: f32, ux: f32, uz: f32, hl: f32 };

pub fn frameOf(s: Solid) Frame {
    const dx = s.b.x - s.a.x;
    const dz = s.b.z - s.a.z;
    const l = @sqrt(dx * dx + dz * dz);
    const ux: f32 = if (l > 1e-5) dx / l else 1.0;
    const uz: f32 = if (l > 1e-5) dz / l else 0.0;
    return .{ .cx = (s.a.x + s.b.x) * 0.5, .cz = (s.a.z + s.b.z) * 0.5, .ux = ux, .uz = uz, .hl = l * 0.5 + s.r };
}

/// **THE BOX ROUND A SOLID, AND A SQUARE END DOES NOT FIT IN `r`** — the rectangle is turned with the segment, so
/// its corner stands `r*(|ux| + |uz|)` outside the segment's own box, up to `r*sqrt2` at 45 deg. Every broad phase asks it.
pub fn padXZ(s: Solid) f32 {
    if (!s.flat) return s.r;
    const f = frameOf(s);
    return s.r * (@abs(f.ux) + @abs(f.uz));
}

const Gap = struct { d: f32, nx: f32, nz: f32 };

/// Signed distance from `p` to a flat solid's edge, negative inside, with the way out.
fn rectGap(p: rl.Vector3, s: Solid) Gap {
    const f = frameOf(s);
    const rx = p.x - f.cx;
    const rz = p.z - f.cz;
    const t = rx * f.ux + rz * f.uz;
    const w = -rx * f.uz + rz * f.ux;
    const dt = f.hl - @abs(t);
    const dw = s.r - @abs(w);
    if (dt >= 0 and dw >= 0) {
        if (dw <= dt) {
            const sg: f32 = if (w >= 0) 1.0 else -1.0;
            return .{ .d = -dw, .nx = -f.uz * sg, .nz = f.ux * sg };
        }
        const sg: f32 = if (t >= 0) 1.0 else -1.0;
        return .{ .d = -dt, .nx = f.ux * sg, .nz = f.uz * sg };
    }
    const qt = mathx.clampF(t, -f.hl, f.hl);
    const qw = mathx.clampF(w, -s.r, s.r);
    const ex = (t - qt) * f.ux - (w - qw) * f.uz;
    const ez = (t - qt) * f.uz + (w - qw) * f.ux;
    const d = @sqrt(ex * ex + ez * ez);
    return .{ .d = d, .nx = ex / d, .nz = ez / d };
}

/// Signed distance from `p` to the solid's edge in XZ: past 0 is outside, whatever its shape.
pub fn gap(p: rl.Vector3, s: Solid) f32 {
    if (s.flat) return rectGap(p, s).d;
    const q = mathx.closestOnSegXZ(p, s.a, s.b);
    return mathx.distXZ(p, q) - s.r;
}

pub fn pushOut(p: rl.Vector3, pr: f32, s: Solid) rl.Vector3 {
    if (s.flat) {
        const g = rectGap(p, s);
        if (g.d >= pr) return p;
        const k = pr - g.d;
        return v3(p.x + g.nx * k, p.y, p.z + g.nz * k);
    }
    const q = mathx.closestOnSegXZ(p, s.a, s.b);
    const dx = p.x - q.x;
    const dz = p.z - q.z;
    const mind = pr + s.r;
    const d2 = dx * dx + dz * dz;
    if (d2 >= mind * mind) return p;
    const d = @sqrt(d2);
    if (d < 1e-5) return v3(p.x + mind, p.y, p.z);
    const k = (mind - d) / d;
    return v3(p.x + dx * k, p.y, p.z + dz * k);
}

pub fn pushOutCircle(p: rl.Vector3, pr: f32, c: rl.Vector3, cr: f32) rl.Vector3 {
    return pushOut(p, pr, .{ .a = c, .b = c, .r = cr });
}

pub fn resolve(p: rl.Vector3, pr: f32, solids: []const Solid) rl.Vector3 {
    var out = p;
    for (solids) |s| out = pushOut(out, pr, s);
    if (out.x == p.x and out.z == p.z) return out;
    for (solids) |s| out = pushOut(out, pr, s);
    return out;
}

pub fn blocksPoint(p: rl.Vector3, margin: f32, s: Solid) bool {
    if (p.y > s.h or p.y < s.y0) return false;
    if (s.flat) return rectGap(p, s).d < margin;
    const q = mathx.closestOnSegXZ(p, s.a, s.b);
    const dx = p.x - q.x;
    const dz = p.z - q.z;
    const rr = s.r + margin;
    return dx * dx + dz * dz < rr * rr;
}

pub fn blockedBy(p: rl.Vector3, margin: f32, solids: []const Solid) bool {
    return blockerAt(p, margin, solids) != null;
}

pub fn blockerAt(p: rl.Vector3, margin: f32, solids: []const Solid) ?Surface {
    for (solids) |s| {
        if (blocksPoint(p, margin, s)) return s.surf;
    }
    return null;
}

// A LOOK IS A SEGMENT, TESTED EXACTLY: sampling means a step that costs real time over 20 m, or one a fence post fits through.

/// SQUARED, because its one caller compares against a radius: the four ends each cost a root otherwise, and `env.sees`
/// asks this of every solid along a 20 m line.
fn segDist2XZ(a0: rl.Vector3, a1: rl.Vector3, b0: rl.Vector3, b1: rl.Vector3) f32 {
    if (segsCrossXZ(a0, a1, b0, b1)) return 0;
    var best = mathx.dist2XZ(a0, mathx.closestOnSegXZ(a0, b0, b1));
    best = @min(best, mathx.dist2XZ(a1, mathx.closestOnSegXZ(a1, b0, b1)));
    best = @min(best, mathx.dist2XZ(b0, mathx.closestOnSegXZ(b0, a0, a1)));
    return @min(best, mathx.dist2XZ(b1, mathx.closestOnSegXZ(b1, a0, a1)));
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

pub fn blocksSight(a: rl.Vector3, b: rl.Vector3, s: Solid) bool {
    if (@min(a.y, b.y) >= s.h) return false;
    if (@max(a.y, b.y) < s.y0) return false;
    const pad = padXZ(s);
    if (@min(s.a.x, s.b.x) - pad > @max(a.x, b.x) or @max(s.a.x, s.b.x) + pad < @min(a.x, b.x)) return false;
    if (@min(s.a.z, s.b.z) - pad > @max(a.z, b.z) or @max(s.a.z, s.b.z) + pad < @min(a.z, b.z)) return false;
    if (s.flat) {
        if (rectGap(a, s).d < 0) return true;
        const f = frameOf(s);
        var c: [4]rl.Vector3 = undefined;
        for ([_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 } }, 0..) |k, i| {
            c[i] = v3(f.cx + f.ux * f.hl * k[0] - f.uz * s.r * k[1], 0, f.cz + f.uz * f.hl * k[0] + f.ux * s.r * k[1]);
        }
        for (0..4) |i| {
            if (segsCrossXZ(a, b, c[i], c[(i + 1) % 4])) return true;
        }
        return false;
    }
    return segDist2XZ(a, b, s.a, s.b) < s.r * s.r;
}

test "A FLAT SOLID HAS CORNERS — a body reaches the corner of a wall a round end cut off, and a look through it is stopped" {
    const wall = box(-3, 0, 3, 0, 0.4);
    const at = pushOut(v3(3.45, 0, 0.45), 0.3, wall);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), @sqrt((at.x - 3.4) * (at.x - 3.4) + (at.z - 0.4) * (at.z - 0.4)), 1e-4);
    const round = capsule(-3, 0, 3, 0, 0.4);
    const rounded = pushOut(v3(3.45, 0, 0.45), 0.3, round);
    try std.testing.expect(at.x > rounded.x + 0.05);
    const out = pushOut(v3(2.9, 0, 0.1), 0.3, wall);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), out.z, 1e-4);
    try std.testing.expect(blocksSight(v3(0, 1, -3), v3(0, 1, 3), wall));
    try std.testing.expect(blocksSight(v3(3.35, 1, -3), v3(3.35, 1, 3), wall));
    try std.testing.expect(!blocksSight(v3(3.45, 1, -3), v3(3.45, 1, 3), wall));
    try std.testing.expect(gap(v3(0, 0, 0), wall) < 0 and gap(v3(0, 0, 1), wall) > 0.59);
}

test "A TURNED SQUARE END STANDS OUTSIDE THE SEGMENT'S OWN BOX — the broad phase is padded to the corner, not to `r`" {
    const half: f32 = 3.85; // the 7.7 m keep AGENTS sizes `flat` off
    var worst: f32 = 0;
    var worstDeg: f32 = 0;
    var deg: f32 = 0;
    while (deg <= 90.0) : (deg += 0.5) {
        const a = mathx.radians(deg);
        const wall = box(-half * @cos(a), -half * @sin(a), half * @cos(a), half * @sin(a), 1.2);
        const f = frameOf(wall);
        var reach: f32 = 0;
        for ([_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 } }) |k| {
            const cx = f.ux * f.hl * k[0] - f.uz * wall.r * k[1];
            const cz = f.uz * f.hl * k[0] + f.ux * wall.r * k[1];
            reach = @max(reach, @max(@abs(cx) - half * @abs(@cos(a)), @abs(cz) - half * @abs(@sin(a))));
        }
        const over = reach - wall.r;
        if (over > worst) {
            worst = over;
            worstDeg = deg;
        }
        try std.testing.expect(padXZ(wall) >= reach - 1e-4);
        // A look that clips the corner is a look the prefilter may not throw away.
        const at = f.ux * f.hl - f.uz * wall.r * 0.999;
        const az = f.uz * f.hl + f.ux * wall.r * 0.999;
        try std.testing.expect(blocksSight(v3(at, 1, az - 4), v3(at, 1, az + 4), wall));
    }
    std.debug.print(
        "\n  a {d:.1} m square-ended wall of r {d:.2}: its corner stands {d:.3} m past the segment's box at {d:.0} deg — the pad now covers it\n",
        .{ half * 2, @as(f32, 1.2), worst, worstDeg },
    );
    try std.testing.expect(worst > 0.4);
    // A round end never leaves its own radius, so nothing there moves.
    try std.testing.expectEqual(@as(f32, 0.4), padXZ(capsule(-3, -3, 3, 3, 0.4)));
}

test "a look is stopped by what stands in it and by nothing else" {
    const wall = capsule(-3, 0, 3, 0, 0.4);
    const eye = v3(0, 1.3, -6);
    try std.testing.expect(blocksSight(eye, v3(0, 1.3, 6), wall));
    try std.testing.expect(!blocksSight(eye, v3(0, 1.3, -1), wall));
    try std.testing.expect(!blocksSight(v3(9, 1.3, -6), v3(9, 1.3, 6), wall));
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
    const s = capsule(-2, 0, 2, 0, 0.5);
    const out = pushOut(v3(0, 0, 0.6), 0.4, s); // above the middle, need 0.9 of clearance in z
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), out.z, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), out.x, 1e-4);
}

test "dead-centre push is finite and separates" {
    const s = circle(0, 0, 1.0);
    const out = pushOut(v3(0, 0, 0), 0.5, s);
    try std.testing.expect(std.math.isFinite(out.x) and out.x > 1.0);
}

test "resolve returns a clear actor UNTOUCHED, and pushes an overlapping one out of everything" {
    const world = [_]Solid{ circle(0, 0, 1.0), capsule(-6, 8, 6, 8, 0.5), circle(4, 0, 0.8) };
    const p = v3(0, 0, -6);
    const clear = resolve(p, 0.4, &world);
    try std.testing.expectEqual(p.x, clear.x);
    try std.testing.expectEqual(p.z, clear.z);
    const out = resolve(v3(0.3, 0, 0.1), 0.4, &world);
    for (world) |s| try std.testing.expect(!blocksPoint(out, -1e-3, s));
}

test "a lintel is a wall to what is up at its level and open to what walks under it" {
    var head = circle(0, 0, 1.0);
    head.y0 = 3.5;
    head.h = 11.0;
    try std.testing.expect(!blocksPoint(v3(0.5, 1.2, 0), 0.05, head));
    try std.testing.expect(blocksPoint(v3(0.5, 4.7, 0), 0.05, head));
    try std.testing.expect(!blocksSight(v3(0, 1.3, -4), v3(0, 1.4, 4), head));
    try std.testing.expect(blocksSight(v3(0, 4.7, -4), v3(0, 4.7, 4), head));
}

test "blocksPoint respects the blocking height: hits below the top, clears above it" {
    var s = circle(0, 0, 1.0);
    s.h = 3.0;
    try std.testing.expect(blocksPoint(v3(0.5, 1.2, 0), 0.05, s));
    try std.testing.expect(!blocksPoint(v3(0.5, 3.5, 0), 0.05, s));
    try std.testing.expect(!blocksPoint(v3(2.0, 1.2, 0), 0.05, s));
}

// MEASURED, AND IT IS THE SHAPE THAT MATTERS: `game.settleGroup` shoulders every body in a group against every
// other, and a group's slab holds `wf.MAX_PER_KIND` — a map may legally spend the whole foe budget on one kind.
// The fix is not a distance reject guessed here: a body is a SEGMENT when it lies down, and a bound too tight is
// a walk-through (`padXZ`'s lesson). It wants a real broad phase or a smaller cap, which is the owner's call.
test "WHAT ALL-PAIRS SHOULDERING COSTS A FRAME — `game.settleGroup` walks its own group for every body in it" {
    var rng = mathx.Rng.init(0x5E77);
    var bodies: [512]Solid = undefined;
    for (&bodies) |*s| {
        const x = rng.range(-40, 40);
        const z = rng.range(-40, 40);
        s.* = .{ .a = v3(x, 0, z), .b = v3(x, 0, z), .r = 0.55, .h = 1.9 };
    }
    std.debug.print("\n", .{});
    for ([_]usize{ 16, 64, 256, 512 }) |n| {
        var t = try std.time.Timer.start();
        var sink: f32 = 0;
        for (bodies[0..n], 0..) |*a, i| {
            var p = a.a;
            for (bodies[0..n], 0..) |*o, j| {
                if (i == j) continue;
                p = pushOut(p, 0.55, o.*);
            }
            sink += p.x;
        }
        const us = @as(f64, @floatFromInt(t.read())) / 1000.0;
        std.mem.doNotOptimizeAway(sink);
        std.debug.print("  all-pairs shoulder, {d:>3} bodies: {d:>8.1} us a frame — {d:.3}% of a 16.7 ms frame ({d} pairs)\n", .{ n, us, us / 16700.0 * 100.0, n * (n - 1) });
    }
}
