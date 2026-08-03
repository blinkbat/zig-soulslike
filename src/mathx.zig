const std = @import("std");
const rl = @import("raylib");

// Gameplay math on the XZ ground plane (Y up); the *XZ helpers ignore Y.

/// Vector3 constructor shorthand: v3(x, y, z).
pub const v3 = rl.Vector3.init;
/// Color constructor shorthand: rgba(r, g, b, a).
pub const rgba = rl.Color.init;
/// The zero vector — used as a struct-field default (Go's zero value).
pub const zero3 = rl.Vector3{ .x = 0, .y = 0, .z = 0 };


pub const LONG_AGO: f32 = 1e9;

pub fn clampF(v: f32, lo: f32, hi: f32) f32 {
    if (std.math.isNan(v)) return lo;
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

pub fn maxF(a: f32, b: f32) f32 {
    return if (a > b) a else b;
}

/// `clampF`'s integer counterpart.
pub fn clampI(v: i32, lo: i32, hi: i32) i32 {
    return @max(lo, @min(hi, v));
}

pub fn minF(a: f32, b: f32) f32 {
    return if (a < b) a else b;
}

/// A position on the floor plane.
pub fn ground(x: f32, z: f32) rl.Vector3 {
    return v3(x, 0, z);
}

/// Horizontal distance between two points (Y ignored).
pub fn distXZ(a: rl.Vector3, b: rl.Vector3) f32 {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return @sqrt(dx * dx + dz * dz);
}

/// Squared horizontal distance (Y ignored).
pub fn dist2XZ(a: rl.Vector3, b: rl.Vector3) f32 {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return dx * dx + dz * dz;
}

/// Unit direction from a to b in the XZ plane (zero if coincident).
pub fn dirXZ(from: rl.Vector3, to: rl.Vector3) rl.Vector3 {
    const dx = to.x - from.x;
    const dz = to.z - from.z;
    const d = @sqrt(dx * dx + dz * dz);
    if (d < 1e-5) return v3(0, 0, 0);
    return v3(dx / d, 0, dz / d);
}

pub fn lenXZ(v: rl.Vector3) f32 {
    return @sqrt(v.x * v.x + v.z * v.z);
}

pub fn stepXZ(pos: *rl.Vector3, dir: rl.Vector3, dist: f32, bounds: f32) void {
    pos.x = clampF(pos.x + dir.x * dist, -bounds, bounds);
    pos.z = clampF(pos.z + dir.z * dist, -bounds, bounds);
}

/// Right-hand perpendicular of a facing direction in the XZ plane.
pub fn perpXZ(f: rl.Vector3) rl.Vector3 {
    return v3(f.z, 0, -f.x);
}

/// Unit forward direction on the ground for a yaw angle (yaw 0 → +Z) — the single source for the `v3(sinf, 0, cosf)` idiom, and the inverse of headingXZ.
pub fn headingDir(yaw: f32) rl.Vector3 {
    return v3(sinf(yaw), 0, cosf(yaw));
}

/// Yaw angle of a ground direction (`atan2(x, z)`); the inverse of headingDir, Y ignored.
pub fn headingXZ(v: rl.Vector3) f32 {
    return std.math.atan2(v.x, v.z);
}

/// Closest point on segment a-b to p, measured in the XZ plane (returned with Y = 0).
pub fn closestOnSegXZ(p: rl.Vector3, a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    const abx = b.x - a.x;
    const abz = b.z - a.z;
    const denom = abx * abx + abz * abz;
    if (denom < 1e-10) return v3(a.x, 0, a.z);
    const t = clampF(((p.x - a.x) * abx + (p.z - a.z) * abz) / denom, 0, 1);
    return v3(a.x + abx * t, 0, a.z + abz * t);
}

/// Closest point on segment a-b to p in full 3D (the swept-blade hit test rides this).
pub fn closestOnSegV(p: rl.Vector3, a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    const ab = subV(b, a);
    const denom = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z;
    if (denom < 1e-12) return a;
    const ap = subV(p, a);
    const t = clampF((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / denom, 0, 1);
    return v3(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t);
}

pub fn addV(a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    return v3(a.x + b.x, a.y + b.y, a.z + b.z);
}
pub fn subV(a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    return v3(a.x - b.x, a.y - b.y, a.z - b.z);
}
pub fn scaleV(a: rl.Vector3, s: f32) rl.Vector3 {
    return v3(a.x * s, a.y * s, a.z * s);
}
pub fn lenV(a: rl.Vector3) f32 {
    return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}
pub fn normV(a: rl.Vector3) rl.Vector3 {
    const l = lenV(a);
    if (l < 1e-6) return v3(0, 0, 0);
    return v3(a.x / l, a.y / l, a.z / l);
}
/// Cross product. env.zig and gfx.zig each carry a private copy for their own frustum/axis-frame work; this is the one every OTHER caller should reach for.
pub fn crossV(a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
pub fn lerpV(a: rl.Vector3, b: rl.Vector3, t: f32) rl.Vector3 {
    return v3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}
pub fn lerpF(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

pub fn rx(deg: f32) rl.Matrix {
    return rl.math.matrixRotateX(radians(deg));
}
pub fn ry(deg: f32) rl.Matrix {
    return rl.math.matrixRotateY(radians(deg));
}
pub fn rz(deg: f32) rl.Matrix {
    return rl.math.matrixRotateZ(radians(deg));
}
pub fn tr(x: f32, y: f32, z: f32) rl.Matrix {
    return rl.math.matrixTranslate(x, y, z);
}
pub fn scaleM(sx: f32, sy: f32, sz: f32) rl.Matrix {
    return rl.math.matrixScale(sx, sy, sz);
}
pub fn mul(a: rl.Matrix, b: rl.Matrix) rl.Matrix {
    return rl.math.matrixMultiply(a, b);
}
pub fn mul3(a: rl.Matrix, b: rl.Matrix, c: rl.Matrix) rl.Matrix {
    return mul(mul(a, b), c);
}

/// Hermite smoothstep of x across [a, b] → 0..1 (clamped; the GLSL smoothstep).
pub fn smoothstep(a: f32, b: f32, x: f32) f32 {
    const t = clampF((x - a) / (b - a), 0, 1);
    return t * t * (3.0 - 2.0 * t);
}

/// A RISE-HOLD-FALL PULSE, 0 → 1 → 0: in across [a, b], held to `c`, out across [c, d].
pub fn pulse(x: f32, a: f32, b: f32, c: f32, d: f32) f32 {
    return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x));
}

test "pulse rises, holds and falls, and is flat outside its span" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(-1, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(0, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), pulse(0.5, 0, 0.2, 0.8, 1.0), 1e-6); // the HOLD
    try std.testing.expectApproxEqAbs(@as(f32, 1), pulse(0.3, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(1.0, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(9, 0, 0.2, 0.8, 1.0), 1e-6);
    // …and b == c is a SPIKE: it peaks exactly at the knot and holds nowhere.
    try std.testing.expectApproxEqAbs(@as(f32, 1), pulse(0.5, 0, 0.5, 0.5, 1.0), 1e-6);
    try std.testing.expect(pulse(0.4, 0, 0.5, 0.5, 1.0) < 1.0);
    try std.testing.expect(pulse(0.6, 0, 0.5, 0.5, 1.0) < 1.0);
}

/// Ease `cur` toward `target` by a rate-limited step of `rate*dt` (frame-rate independent enough for smoothing camera/gait blends).
pub fn approach(cur: f32, target: f32, maxStep: f32) f32 {
    const d = target - cur;
    if (@abs(d) <= maxStep) return target;
    return cur + std.math.sign(d) * maxStep;
}

pub fn approachV(cur: rl.Vector3, target: rl.Vector3, maxStep: f32) rl.Vector3 {
    const dx = target.x - cur.x;
    const dy = target.y - cur.y;
    const dz = target.z - cur.z;
    const l = @sqrt(dx * dx + dy * dy + dz * dz);
    if (l <= maxStep or l < 1e-6) return target;
    const k = maxStep / l;
    return v3(cur.x + dx * k, cur.y + dy * k, cur.z + dz * k);
}

/// Wrap a radian angle into (-pi, pi].
pub fn wrapPi(a: f32) f32 {
    if (!std.math.isFinite(a)) return 0;
    var x = a;
    while (x > std.math.pi) x -= std.math.tau;
    while (x <= -std.math.pi) x += std.math.tau;
    return x;
}

/// Wrap a DEGREE angle into (-180, 180]
pub fn wrapDeg(a: f32) f32 {
    return degrees(wrapPi(radians(a)));
}

/// Shortest-arc ease of a radian angle toward target by at most `maxStep`.
pub fn approachAngle(cur: f32, target: f32, maxStep: f32) f32 {
    const d = wrapPi(target - cur);
    if (@abs(d) <= maxStep) return target;
    return cur + std.math.sign(d) * maxStep;
}

/// A copy of col with the given alpha (0..255).
pub fn withAlpha(col: rl.Color, a: u8) rl.Color {
    var out = col;
    out.a = a;
    return out;
}

/// Clamp a float to [0,255] and narrow to u8 (channel/alpha math).
pub fn u8f(v: f32) u8 {
    return @intFromFloat(clampF(v, 0, 255));
}

pub fn sinf(x: f32) f32 {
    return @floatCast(@sin(@as(f64, x)));
}
pub fn cosf(x: f32) f32 {
    return @floatCast(@cos(@as(f64, x)));
}

fn lerpU8(a: u8, b: u8, t: f32) u8 {
    const af: f32 = @floatFromInt(a);
    const bf: f32 = @floatFromInt(b);
    return u8f(af + (bf - af) * t);
}

/// Linearly interpolate between two colors.
pub fn lerpColor(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const tt = clampF(t, 0, 1);
    return rgba(
        lerpU8(a.r, b.r, tt),
        lerpU8(a.g, b.g, tt),
        lerpU8(a.b, b.b, tt),
        lerpU8(a.a, b.a, tt),
    );
}

/// Seeded RNG wrapper (subset of Go's math/rand the sibling games used).
pub const Rng = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Rng {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }
    fn rand(self: *Rng) std.Random {
        return self.prng.random();
    }
    pub fn float(self: *Rng) f32 {
        return self.rand().float(f32);
    }
    pub fn range(self: *Rng, lo: f32, hi: f32) f32 {
        return lo + self.float() * (hi - lo);
    }
    pub fn angle(self: *Rng) f32 {
        return self.float() * std.math.tau;
    }
    pub fn signed(self: *Rng) f32 {
        return self.float() * 2 - 1;
    }
    pub fn intn(self: *Rng, n: i32) i32 {
        if (n <= 0) return 0;
        return @intCast(self.rand().uintLessThan(u32, @intCast(n)));
    }
};

/// Degrees → radians.
pub fn radians(deg: f32) f32 {
    return deg * std.math.pi / 180.0;
}

/// Radians → degrees.
pub fn degrees(rad: f32) f32 {
    return rad * 180.0 / std.math.pi;
}


test "clampF pins NaN to lo and clamps both ends" {
    try std.testing.expectEqual(@as(f32, 1), clampF(std.math.nan(f32), 1, 5));
    try std.testing.expectEqual(@as(f32, 5), clampF(9, 1, 5));
    try std.testing.expectEqual(@as(f32, 1), clampF(-2, 1, 5));
    try std.testing.expectEqual(@as(f32, 3), clampF(3, 1, 5));
}

test "wrapPi lands in (-pi, pi] and guards non-finite input" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), wrapPi(std.math.tau), 1e-6);
    try std.testing.expectEqual(@as(f32, std.math.pi), wrapPi(std.math.pi));
    try std.testing.expectApproxEqAbs(-std.math.pi + 0.5, wrapPi(std.math.pi + 0.5), 1e-5);
    try std.testing.expectEqual(@as(f32, 0), wrapPi(std.math.inf(f32)));
}

test "approachAngle takes the shortest arc across the seam" {
    // 350 deg -> 10 deg is +20 deg through the seam, never -340 the long way round.
    const stepped = approachAngle(radians(350), radians(10), radians(5));
    try std.testing.expectApproxEqAbs(wrapPi(radians(355)), wrapPi(stepped), 1e-5);
}

test "closestOnSegV clamps to the ENDS, which is what makes the swept blade test honest" {
    const a = v3(0, 0, 0);
    const b = v3(2, 0, 0);
    const d = struct {
        fn to(p: rl.Vector3, aa: rl.Vector3, bb: rl.Vector3) f32 {
            return lenV(subV(p, closestOnSegV(p, aa, bb)));
        }
    }.to;
    try std.testing.expectApproxEqAbs(@as(f32, 1), d(v3(1, 1, 0), a, b), 1e-5); // perpendicular
    try std.testing.expectApproxEqAbs(@as(f32, 1), d(v3(-1, 0, 0), a, b), 1e-5); // past the end → to the endpoint
    try std.testing.expectApproxEqAbs(@as(f32, 0), d(v3(1, 0, 0), a, b), 1e-5); // on the segment
    try std.testing.expectApproxEqAbs(@as(f32, 3), d(v3(5, 0, 0), a, b), 1e-5);
    // A degenerate segment is a point, not a divide-by-zero.
    try std.testing.expectApproxEqAbs(@as(f32, 5), d(v3(5, 0, 0), a, a), 1e-5);
}

test "smoothstep clamps outside [a,b] and passes its midpoint" {
    try std.testing.expectEqual(@as(f32, 0), smoothstep(0.2, 0.8, 0.0));
    try std.testing.expectEqual(@as(f32, 1), smoothstep(0.2, 0.8, 1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), smoothstep(0, 1, 0.5), 1e-6);
}
