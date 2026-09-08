const std = @import("std");
const rl = @import("raylib");


pub const v3 = rl.Vector3.init;
pub const rgba = rl.Color.init;
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

pub fn clampI(v: i32, lo: i32, hi: i32) i32 {
    return @max(lo, @min(hi, v));
}

pub fn signI(v: f32) i32 {
    if (v > 0) return 1;
    if (v < 0) return -1;
    return 0;
}

pub fn minF(a: f32, b: f32) f32 {
    return if (a < b) a else b;
}

pub fn ground(x: f32, z: f32) rl.Vector3 {
    return v3(x, 0, z);
}

pub fn distXZ(a: rl.Vector3, b: rl.Vector3) f32 {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return @sqrt(dx * dx + dz * dz);
}

pub fn dist2XZ(a: rl.Vector3, b: rl.Vector3) f32 {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return dx * dx + dz * dz;
}

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

pub const Nearest = struct {
    best: ?usize = null,
    d2: f32,

    pub fn within(reach: f32) Nearest {
        return .{ .d2 = reach * reach };
    }

    pub fn offer(self: *Nearest, i: usize, at: rl.Vector3, from: rl.Vector3) void {
        const d = dist2XZ(at, from);
        if (d >= self.d2) return;
        self.d2 = d;
        self.best = i;
    }
};

pub fn clampXZ(p: rl.Vector3, bounds: f32) rl.Vector3 {
    return v3(clampF(p.x, -bounds, bounds), p.y, clampF(p.z, -bounds, bounds));
}

pub fn stepXZ(pos: *rl.Vector3, dir: rl.Vector3, dist: f32, bounds: f32) void {
    pos.* = clampXZ(v3(pos.x + dir.x * dist, pos.y, pos.z + dir.z * dist), bounds);
}

pub fn holdXZ(pos: *rl.Vector3, bounds: f32) void {
    pos.* = clampXZ(pos.*, bounds);
}

pub fn perpXZ(f: rl.Vector3) rl.Vector3 {
    return v3(f.z, 0, -f.x);
}

pub fn headingDir(yaw: f32) rl.Vector3 {
    return v3(sinf(yaw), 0, cosf(yaw));
}

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

pub const TwoBone = struct { joint: rl.Vector3, end: rl.Vector3 };

pub fn twoBone(root: rl.Vector3, target: rl.Vector3, upper: f32, lower: f32, hint: rl.Vector3) TwoBone {
    var to = subV(target, root);
    var distance = lenV(to);
    if (distance < 1e-4) {
        to = v3(0, -1e-4, 0);
        distance = 1e-4;
    }
    const reach = clampF(distance, @abs(upper - lower) + 1e-3, upper + lower - 1e-3);
    const along = scaleV(to, 1 / distance);
    var side = subV(hint, scaleV(along, dotV(hint, along)));
    if (lenV(side) < 1e-4) side = crossV(along, if (@abs(along.y) < 0.9) v3(0, 1, 0) else v3(1, 0, 0));
    side = normV(side);
    const cosine = clampF((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1, 1);
    const direction = addV(scaleV(along, cosine), scaleV(side, @sqrt(@max(0, 1 - cosine * cosine))));
    return .{ .joint = addV(root, scaleV(direction, upper)), .end = addV(root, scaleV(along, reach)) };
}

pub const LegAngles = struct { hip: f32, knee: f32 };

/// THE PLANAR PAIR A STRAIGHT-DOWN LEG STANDS AT, in DEGREES: `hip` off the vertical, `knee` as flexion (0 straight). `height` is root to end-joint, and the caller bounds it — `twoBone` is the same triangle when the target is a POINT rather than a height.
pub fn legAngles(upper: f32, lower: f32, height: f32) LegAngles {
    return .{
        .hip = degrees(std.math.acos(clampF((upper * upper + height * height - lower * lower) / (2 * upper * height), -1, 1))),
        .knee = 180 - degrees(std.math.acos(clampF((upper * upper + lower * lower - height * height) / (2 * upper * lower), -1, 1))),
    };
}
pub fn closestOnSegV(p: rl.Vector3, a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    const ab = subV(b, a);
    const denom = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z;
    if (denom < 1e-12) return a;
    const ap = subV(p, a);
    const t = clampF((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / denom, 0, 1);
    return v3(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t);
}

pub fn segmentGapV(a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3) f32 {
    const ab = subV(b, a);
    const cd = subV(d, c);
    const ac = subV(a, c);
    const aa = dotV(ab, ab);
    const cc = dotV(cd, cd);
    if (aa < 1e-12) return lenV(subV(a, closestOnSegV(a, c, d)));
    if (cc < 1e-12) return lenV(subV(c, closestOnSegV(c, a, b)));
    const cross = dotV(ab, cd);
    const ar = dotV(ab, ac);
    const cr = dotV(cd, ac);
    const denom = aa * cc - cross * cross;
    var u = if (denom > 1e-8 * aa * cc) clampF((cross * cr - ar * cc) / denom, 0, 1) else @as(f32, 0);
    var v = (cross * u + cr) / cc;
    if (v < 0) {
        v = 0;
        u = clampF(-ar / aa, 0, 1);
    } else if (v > 1) {
        v = 1;
        u = clampF((cross - ar) / aa, 0, 1);
    }
    return lenV(subV(lerpV(a, b, u), lerpV(c, d, v)));
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
    return normVOr(a, v3(0, 0, 0));
}
pub fn normVOr(a: rl.Vector3, fallback: rl.Vector3) rl.Vector3 {
    const l = lenV(a);
    if (l < 1e-6) return fallback;
    return v3(a.x / l, a.y / l, a.z / l);
}
pub fn dotV(a: rl.Vector3, b: rl.Vector3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
pub fn crossV(a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
pub fn lerpV(a: rl.Vector3, b: rl.Vector3, t: f32) rl.Vector3 {
    return v3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}

/// At dead opposite `(1-2k)*from` is a fixed point: measured, a 2.2 rad/s steer took 5.15 s to reverse against the 1.43 s a cap gives. Dead opposite also has no slerp axis (`sin(ang)` -> 0 -> NaN), so any perpendicular does for one step.
pub fn turnToward(from: rl.Vector3, want: rl.Vector3, maxRad: f32) rl.Vector3 {
    const a = normV(from);
    const b = normV(want);
    if (lenV(a) < 0.5) return b;
    if (lenV(b) < 0.5) return a;
    const ang = std.math.acos(clampF(dotV(a, b), -1, 1));
    if (ang <= maxRad or ang < 1e-5) return b;
    const sn = @sin(ang);
    if (sn < 1e-3) {
        var axis = crossV(a, v3(0, 1, 0));
        if (lenV(axis) < 1e-4) axis = crossV(a, v3(0, 0, 1));
        const side = normV(crossV(axis, a));
        return normV(addV(scaleV(a, @cos(maxRad)), scaleV(side, @sin(maxRad))));
    }
    const k = maxRad / ang;
    return normV(addV(scaleV(a, @sin((1.0 - k) * ang) / sn), scaleV(b, @sin(k * ang) / sn)));
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

pub fn placeAt(off: rl.Vector3, anim: rl.Matrix, parent: rl.Matrix) rl.Matrix {
    return mul3(anim, tr(off.x, off.y, off.z), parent);
}

pub fn smoothstep(a: f32, b: f32, x: f32) f32 {
    const t = clampF((x - a) / (b - a), 0, 1);
    return t * t * (3.0 - 2.0 * t);
}

pub fn pulse(x: f32, a: f32, b: f32, c: f32, d: f32) f32 {
    return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x));
}

test "pulse rises, holds and falls, and is flat outside its span" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(-1, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(0, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), pulse(0.5, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), pulse(0.3, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(1.0, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), pulse(9, 0, 0.2, 0.8, 1.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), pulse(0.5, 0, 0.5, 0.5, 1.0), 1e-6);
    try std.testing.expect(pulse(0.4, 0, 0.5, 0.5, 1.0) < 1.0);
    try std.testing.expect(pulse(0.6, 0, 0.5, 0.5, 1.0) < 1.0);
}

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

pub fn wrapPi(a: f32) f32 {
    if (!std.math.isFinite(a)) return 0;
    var x = a;
        // Past ~2^23·tau an f32 subtraction of tau is a no-op and the loop never terminates; the threshold sits far above every live caller.
    const REDUCE_OVER: f32 = std.math.tau * 1024.0;
    if (@abs(x) > REDUCE_OVER) x = @rem(x, std.math.tau);
    while (x > std.math.pi) x -= std.math.tau;
    while (x <= -std.math.pi) x += std.math.tau;
    return x;
}

pub fn wrapDeg(a: f32) f32 {
    return degrees(wrapPi(radians(a)));
}

/// ONE TURN, [0, 360) — in degrees the whole way, because the radian round-trip `wrapDeg` takes puts float noise on
/// a yaw the editor writes to a text file. `@mod` is the floored modulus over a positive divisor, so it already answers
/// inside the turn for a negative angle.
pub fn wrapDeg360(a: f32) f32 {
    if (!std.math.isFinite(a)) return 0;
    return @mod(a, 360.0);
}

test "ONE TURN, AND THE DEGREES COME BACK EXACT" {
    for ([_][2]f32{
        .{ 0, 0 },      .{ 15, 15 },  .{ 180, 180 },
        .{ -15, 345 },  .{ 360, 0 },  .{ 450, 90 },
        .{ 720, 0 },    .{ -370, 350 },
    }) |row| {
        try std.testing.expectEqual(row[1], wrapDeg360(row[0]));
    }
    try std.testing.expectEqual(@as(f32, 0), wrapDeg360(std.math.inf(f32)));
    try std.testing.expectEqual(@as(f32, 0), wrapDeg360(std.math.nan(f32)));
}

pub fn approachAngle(cur: f32, target: f32, maxStep: f32) f32 {
    const d = wrapPi(target - cur);
    if (@abs(d) <= maxStep) return target;
    return cur + std.math.sign(d) * maxStep;
}

/// HOW FAR THE SEGMENT `a`->`b` LEANS OFF WORLD UP, in degrees — 0 is plumb, 90 is flat, past 90 is upside down.
pub fn tiltDeg(a: rl.Vector3, b: rl.Vector3) f32 {
    const d = subV(b, a);
    return degrees(std.math.atan2(lenXZ(d), d.y));
}

pub fn withAlpha(col: rl.Color, a: u8) rl.Color {
    var out = col;
    out.a = a;
    return out;
}

pub fn u8f(v: f32) u8 {
    return @intFromFloat(clampF(v, 0, 255));
}

pub fn colVec(c: rl.Color) rl.Vector3 {
    const f = 1.0 / 255.0;
    return v3(@as(f32, @floatFromInt(c.r)) * f, @as(f32, @floatFromInt(c.g)) * f, @as(f32, @floatFromInt(c.b)) * f);
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

pub fn lerpColor(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const tt = clampF(t, 0, 1);
    return rgba(
        lerpU8(a.r, b.r, tt),
        lerpU8(a.g, b.g, tt),
        lerpU8(a.b, b.b, tt),
        lerpU8(a.a, b.a, tt),
    );
}

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

pub fn radians(deg: f32) f32 {
    return deg * std.math.pi / 180.0;
}

pub fn degrees(rad: f32) f32 {
    return rad * 180.0 / std.math.pi;
}

// A flame's guttering, in [-1, 1]: three incommensurate rates so it never reads as a pulse.
pub fn gutter(t: f32, phase: f32) f32 {
    return 0.30 * sinf(t * 4.3 + phase) + 0.14 * sinf(t * 8.9 + phase * 2.3) + 0.56 * sinf(t * 1.7 + phase * 0.6);
}


test "signI is one step, and a NaN axis walks no cursor" {
    try std.testing.expectEqual(@as(i32, 1), signI(0.0001));
    try std.testing.expectEqual(@as(i32, -1), signI(-40.0));
    try std.testing.expectEqual(@as(i32, 0), signI(0));
    try std.testing.expectEqual(@as(i32, 0), signI(std.math.nan(f32)));
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
    try std.testing.expectApproxEqAbs(@as(f32, 1), d(v3(1, 1, 0), a, b), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), d(v3(-1, 0, 0), a, b), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), d(v3(1, 0, 0), a, b), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3), d(v3(5, 0, 0), a, b), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 5), d(v3(5, 0, 0), a, a), 1e-5);
}

test "Nearest takes the closest inside its ring and nothing outside it" {
    const at = zero3;
    var n = Nearest.within(3.0);
    try std.testing.expect(n.best == null);
    n.offer(0, v3(9, 0, 0), at);
    try std.testing.expect(n.best == null);
    n.offer(1, v3(2.5, 0, 0), at);
    try std.testing.expectEqual(@as(usize, 1), n.best.?);
    n.offer(2, v3(0, 0, 1.0), at);
    try std.testing.expectEqual(@as(usize, 2), n.best.?);
    n.offer(3, v3(0, 0, 1.0), at);
    try std.testing.expectEqual(@as(usize, 2), n.best.?);
    var edge = Nearest.within(3.0);
    edge.offer(0, v3(3, 0, 0), at);
    try std.testing.expect(edge.best == null);
    var high = Nearest.within(3.0);
    high.offer(0, v3(1, 40, 0), at);
    try std.testing.expectEqual(@as(usize, 0), high.best.?);
}

test "smoothstep clamps outside [a,b] and passes its midpoint" {
    try std.testing.expectEqual(@as(f32, 0), smoothstep(0.2, 0.8, 0.0));
    try std.testing.expectEqual(@as(f32, 1), smoothstep(0.2, 0.8, 1.0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), smoothstep(0, 1, 0.5), 1e-6);
}

test "two-bone solve preserves lengths at reach limits and parallel hints" {
    for ([_]f32{ 0.5, 1, 1.8 }) |size| {
        const root = v3(2, 3, -4);
        const upper = 0.45 * size;
        const lower = 0.62 * size;
        for ([_]rl.Vector3{ root, addV(root, v3(0, -0.5 * size, 0)), addV(root, v3(0, -8, 0)) }) |target| {
            const solved = twoBone(root, target, upper, lower, v3(0, -1, 0));
            try std.testing.expectApproxEqAbs(upper, lenV(subV(solved.joint, root)), 0.0001);
            try std.testing.expectApproxEqAbs(lower, lenV(subV(solved.end, solved.joint)), 0.0001);
            try std.testing.expect(lenV(subV(solved.end, root)) < upper + lower);
        }
    }
}
test "segmentGapV handles crossing, skew, parallel and collapsed segments" {
    for ([_]f32{ 0.5, 1, 3 }) |s| {
        try std.testing.expectApproxEqAbs(@as(f32, 0), segmentGapV(v3(-s, 0, 0), v3(s, 0, 0), v3(0, -s, 0), v3(0, s, 0)), 1e-5);
        try std.testing.expectApproxEqAbs(s, segmentGapV(v3(-s, 0, 0), v3(s, 0, 0), v3(0, -s, s), v3(0, s, s)), 1e-5);
        try std.testing.expectApproxEqAbs(s, segmentGapV(v3(-s, 0, 0), v3(s, 0, 0), v3(-s, s, 0), v3(s, s, 0)), 1e-5);
        try std.testing.expectApproxEqAbs(s, segmentGapV(zero3, zero3, v3(-s, s, 0), v3(s, s, 0)), 1e-5);
        try std.testing.expectApproxEqAbs(s, segmentGapV(v3(-s, s, 0), v3(s, s, 0), zero3, zero3), 1e-5);
        try std.testing.expectApproxEqAbs(s * @sqrt(@as(f32, 2)), segmentGapV(zero3, v3(s, 0, 0), v3(2 * s, s, 0), v3(3 * s, s, 0)), 1e-5);
    }
}