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

/// Ease `cur` toward `target` by a rate-limited step of `rate*dt` (frame-rate independent
/// enough for smoothing camera/gait blends). Not an exponential — a linear approach.
pub fn approach(cur: f32, target: f32, maxStep: f32) f32 {
    const d = target - cur;
    if (@abs(d) <= maxStep) return target;
    return cur + std.math.sign(d) * maxStep;
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
