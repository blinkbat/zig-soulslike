const std = @import("std");
const rl = @import("raylib");

// Gameplay math on the XZ ground plane (Y up); the *XZ helpers ignore Y. Copied verbatim
// from zig-rts, extended with the vector/angle helpers the movement + FK rig need.

/// Vector3 constructor shorthand: v3(x, y, z).
pub const v3 = rl.Vector3.init;
/// Color constructor shorthand: rgba(r, g, b, a).
pub const rgba = rl.Color.init;
/// The zero vector — used as a struct-field default (Go's zero value).
pub const zero3 = rl.Vector3{ .x = 0, .y = 0, .z = 0 };

/// Fixed-capacity inline string: stored in-struct (no alloc, no dangle when the owner
/// moves). set() truncates to cap; slice() is the live view.
pub fn StrBuf(comptime cap: usize) type {
    return struct {
        buf: [cap]u8 = [_]u8{0} ** cap,
        len: usize = 0,
        const Self = @This();
        pub fn set(self: *Self, s: []const u8) void {
            const n = @min(s.len, cap);
            @memcpy(self.buf[0..n], s[0..n]);
            self.len = n;
        }
        pub fn slice(self: *const Self) []const u8 {
            return self.buf[0..self.len];
        }
    };
}

pub fn clampF(v: f32, lo: f32, hi: f32) f32 {
    // NaN passes both `<` and `>`, so it'd escape unclamped and blow up a downstream
    // @intFromFloat; pin it to lo (safe, no meaningful clamp position for NaN).
    if (std.math.isNan(v)) return lo;
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

pub fn clampI(v: i32, lo: i32, hi: i32) i32 {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

pub fn maxF(a: f32, b: f32) f32 {
    return if (a > b) a else b;
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

/// Right-hand perpendicular of a facing direction in the XZ plane.
pub fn perpXZ(f: rl.Vector3) rl.Vector3 {
    return v3(f.z, 0, -f.x);
}

/// Unit forward direction on the ground for a yaw angle (yaw 0 → +Z) — the single source for
/// the `v3(sinf, 0, cosf)` idiom, and the inverse of headingXZ.
pub fn headingDir(yaw: f32) rl.Vector3 {
    return v3(sinf(yaw), 0, cosf(yaw));
}

/// Yaw angle of a ground direction (`atan2(x, z)`); the inverse of headingDir, Y ignored.
/// A zero vector yields 0 (call sites that care guard the length first).
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

// ── full 3D vector helpers (FK rig, camera) ───────────────────────────────────────────
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
pub fn lerpV(a: rl.Vector3, b: rl.Vector3, t: f32) rl.Vector3 {
    return v3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}
pub fn lerpF(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

// ── raylib TRS matrix shorthand (MatrixMultiply(a,b) applies a FIRST then b) ─────────────
// The FK rigs (hero, frog) build every bone/part transform from these; centralised here so
// the "a-first" convention lives in ONE place instead of a duplicated set per rig file.
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

/// Ease `cur` toward `target` by a rate-limited step of `rate*dt` (frame-rate independent
/// enough for smoothing camera/gait blends). Not an exponential — a linear approach.
pub fn approach(cur: f32, target: f32, maxStep: f32) f32 {
    const d = target - cur;
    if (@abs(d) <= maxStep) return target;
    return cur + std.math.sign(d) * maxStep;
}

/// Move `cur` toward `target` by at most `maxStep` (full 3D). Reaches `target` outright when
/// it's within a step; otherwise steps straight toward it. Used to EASE large collision
/// depenetrations over a few frames (a slide) instead of snapping there in one (a choppy warp).
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
    // Guard non-finite: +inf/-inf would spin the reduction loops forever (inf±tau==inf),
    // and there's no meaningful wrapped angle for them (matches clampF's NaN guard).
    if (!std.math.isFinite(a)) return 0;
    var x = a;
    while (x > std.math.pi) x -= std.math.tau;
    while (x <= -std.math.pi) x += std.math.tau;
    return x;
}

/// Shortest-arc ease of a radian angle toward target by at most `maxStep`.
pub fn approachAngle(cur: f32, target: f32, maxStep: f32) f32 {
    const d = wrapPi(target - cur);
    if (@abs(d) <= maxStep) return target;
    return cur + std.math.sign(d) * maxStep;
}

/// Returns f if it has a horizontal heading, else the fallback (fx, fz).
pub fn orFacing(f: rl.Vector3, fx: f32, fz: f32) rl.Vector3 {
    if (lenXZ(f) < 1e-3) return v3(fx, 0, fz);
    return f;
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

/// sin/cos on f32, computed via f64 (mirrors Go's float32(math.Sin(float64(x)))).
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

/// A time-based seed (Go's time.Now().UnixNano()).
pub fn timeSeed() u64 {
    const ns: u128 = @bitCast(std.time.nanoTimestamp());
    return @truncate(ns);
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

test "smoothstep clamps outside [a,b] and passes its midpoint" {
    try std.testing.expectEqual(@as(f32, 0), smoothstep(0.2, 0.8, 0.0));
    try std.testing.expectEqual(@as(f32, 1), smoothstep(0.2, 0.8, 1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), smoothstep(0, 1, 0.5), 1e-6);
}
