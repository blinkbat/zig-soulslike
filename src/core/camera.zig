const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const clampF = mathx.clampF;


pub const MIN_DIST = 2.4;
pub const MAX_DIST = 9.0;
pub const DEFAULT_DIST = 4.6;
pub const DEFAULT_PITCH = 0.28;
const ZOOM_STEP = 0.6;
/// Radians per pixel of mouse motion. The editor's fly camera looks with the same hand.
pub const LOOK_SENS = 0.0032;
/// ~ -22 deg, looking UP from below. Wider than the -0.20 the free look ever asked for, because the LOCK tilts the rig onto whatever it is fixed on (`game.lockPitch`).
const PITCH_MIN = -0.38;
const PITCH_MAX = 1.15; // ~  66 deg (looking down)
pub const SHOULDER = 0.55;
pub const TARGET_RAISE = 0.15;
pub const FOVY: f32 = 55.0;

/// The sky is smaller than it looks — 0.200 rad, 11.5 deg.
pub fn skyTop() f32 {
    return std.math.degreesToRadians(FOVY * 0.5) - DEFAULT_PITCH;
}
const GROUND_CLEAR = 0.7;
const GROUND_PROBE = 0.25;
const GROUND_RISE = 0.2;
/// Halvings of the step the march stopped on, so the boom lands within 8 mm of what stopped it instead of on a 0.25 m rung.
const PROBE_HALVINGS = 5;
/// FLOOR on the metres the eye keeps off masonry — the near plane's own half-DIAGONAL at the AUTHORED window, which
/// at `game.CLIP_NEAR` on this lens is 0.540 m. The window resizes, so `game.eyeR` widens it to the live aspect and
/// `game.zig` owns the lens, the near plane and both asserts.
pub const EYE_R = 0.55;
/// A CEILING IN METRES A SECOND on the boom being GIVEN BACK, not a rate: shortening is immediate, because the eye
/// may never be in the rock. `REGAIN_SECS` is the spring's own time constant under it.
const CLEAR_REGAIN = 8.0;
const REGAIN_SECS = 0.28;

/// Seconds the focus takes to cover a step in his footing. A tread is a STEP in `pos.y` even after `game.groundActor`
/// eases it, and the eye may not inherit that sawtooth.
const FOCUS_RISE = 0.16;
/// The flat axes are damped only enough to take the edge off a corrected step — a roll may not leave the man behind.
const FOCUS_FLAT = 0.05;
const FOCUS_CAP = 14.0;
/// Past this his footing did not change, the world did (a fall, a load, a level) — the focus goes at once.
const FOCUS_SNAP = 2.5;

const AIM_DIST = 0.7;
const AIM_SHOULDER = 0.30;
const AIM_RAISE = 0.42;

pub const LIFT_SHARE: f32 = 0.55;
const LIFT_SECS: f32 = 0.10;

const SHAKE_MAX = 0.13;
const SHAKE_DECAY = 2.6;
const SHAKE_FREQ = 33.0;

pub const CamRig = struct {
    cam: rl.Camera3D,
    yaw: f32, // azimuth (radians); 0 = camera behind a +Z-facing hero
    pitch: f32, // elevation (radians); + looks down
    dist: f32,
    aimB: f32 = 0,
    lift: f32 = 0,
    liftVel: f32 = 0,
    trauma: f32 = 0,
    shakeT: f32 = 0,
    shakeOff: rl.Vector3 = mathx.zero3,
    eased: f32 = -1,
    easedVel: f32 = 0,
    focus: ?rl.Vector3 = null,
    focusVel: rl.Vector3 = mathx.zero3,

    pub fn forwardXZ(c: *const CamRig) rl.Vector3 {
        return mathx.headingDir(c.yaw);
    }
    pub fn rightXZ(c: *const CamRig) rl.Vector3 {
        return v3(-mathx.cosf(c.yaw), 0, mathx.sinf(c.yaw));
    }

    pub fn orbit(c: *CamRig, dYaw: f32, dPitch: f32) void {
        c.yaw = mathx.wrapPi(c.yaw + dYaw);
        c.pitch = clampF(c.pitch + dPitch, PITCH_MIN, PITCH_MAX);
    }

    pub fn rotate(c: *CamRig, dxPx: f32, dyPx: f32) void {
        c.orbit(-dxPx * LOOK_SENS, dyPx * LOOK_SENS);
    }

    pub fn recenter(c: *CamRig, heroFacing: f32) void {
        c.yaw = heroFacing;
        c.pitch = DEFAULT_PITCH;
    }

    pub fn aim(c: *CamRig, targetYaw: f32, targetPitch: f32, dt: f32, rate: f32) void {
        const k = 1.0 - @exp(-rate * dt);
        c.yaw = mathx.wrapPi(c.yaw + mathx.wrapPi(targetYaw - c.yaw) * k);
        c.pitch = clampF(c.pitch + (targetPitch - c.pitch) * k, PITCH_MIN, PITCH_MAX);
    }

    pub fn zoom(c: *CamRig, wheel: f32) void {
        c.dist = clampF(c.dist - wheel * ZOOM_STEP, MIN_DIST, MAX_DIST);
    }

    pub fn addShake(c: *CamRig, amt: f32) void {
        c.trauma = clampF(c.trauma + amt, 0, 1);
    }

    pub fn tickShake(c: *CamRig, dt: f32) void {
        c.trauma = clampF(c.trauma - SHAKE_DECAY * dt, 0, 1);
        c.shakeT += dt;
        const s = c.trauma * c.trauma * SHAKE_MAX;
        if (s < 0.0005) {
            c.shakeOff = mathx.zero3;
            return;
        }
        const t = c.shakeT;
        c.shakeOff = v3(
            (mathx.sinf(t * SHAKE_FREQ) + 0.5 * mathx.sinf(t * SHAKE_FREQ * 2.31 + 1.7)) * s,
            (mathx.sinf(t * SHAKE_FREQ * 1.17 + 4.2) + 0.5 * mathx.sinf(t * SHAKE_FREQ * 2.87 + 0.6)) * s * 0.6,
            (mathx.sinf(t * SHAKE_FREQ * 0.93 + 2.9) + 0.5 * mathx.sinf(t * SHAKE_FREQ * 2.53 + 3.8)) * s,
        );
    }

    pub fn backDir(c: *const CamRig) rl.Vector3 {
        const cp = mathx.cosf(c.pitch);
        return v3(-mathx.sinf(c.yaw) * cp, mathx.sinf(c.pitch), -mathx.cosf(c.yaw) * cp);
    }

    pub fn targetFor(c: *const CamRig, shoulder: rl.Vector3) rl.Vector3 {
        const right = c.rightXZ();
        const k = mathx.clampF(c.aimB, 0, 1);
        const off = mathx.lerpF(SHOULDER, AIM_SHOULDER, k);
        return v3(
            shoulder.x + right.x * off,
            shoulder.y + mathx.lerpF(TARGET_RAISE, AIM_RAISE, k) + c.lift,
            shoulder.z + right.z * off,
        );
    }

    pub fn boom(c: *const CamRig) f32 {
        return mathx.lerpF(c.dist, AIM_DIST, mathx.clampF(c.aimB, 0, 1));
    }

    fn boomFloor(c: *const CamRig) f32 {
        return mathx.minF(MIN_DIST, c.boom());
    }

    pub fn tickLift(c: *CamRig, heroLift: f32, share: f32, dt: f32) void {
        c.lift = mathx.smoothCD(c.lift, share * heroLift, &c.liftVel, LIFT_SECS, 0, dt);
    }

    /// A SPRING IS TWO NUMBERS, SO A SNAP WRITES BOTH — left behind, `liftVel` carries the speed the lens had before
    /// the footing jumped straight back into the frame the snap exists to make continuous.
    pub fn snapLift(c: *CamRig, lift: f32) void {
        c.lift = lift;
        c.liftVel = 0;
    }

    /// The focus is a SPRING, so seating it is two writes and they go together — `null` is "seat it wherever the
    /// next frame finds him".
    fn seatFocus(c: *CamRig, at: ?rl.Vector3) void {
        c.focus = at;
        c.focusVel = mathx.zero3;
    }

    /// A SHOT HAS NO PREVIOUS FRAME — every eased term is dropped so the next `followRoofed` solves the rig whole.
    pub fn solveFresh(c: *CamRig) void {
        c.eased = -1;
        c.easedVel = 0;
        c.seatFocus(null);
    }

    pub fn follow(c: *CamRig, shoulder: rl.Vector3) void {
        c.seatFocus(shoulder);
        c.place(c.targetFor(shoulder), c.boom());
    }

    pub fn followCentred(c: *CamRig, at: rl.Vector3) void {
        c.seatFocus(null);
        c.place(v3(at.x, at.y + TARGET_RAISE, at.z), c.dist);
    }

    /// THE EYE DOES NOT INHERIT THE STAIR — the boom hangs off a point that walks to his shoulder on a spring, so a
    /// flight of treads reads as a ramp. The flat axes are damped far less than the rise; past `FOCUS_SNAP` nothing
    /// is damped at all.
    fn focusOn(c: *CamRig, shoulder: rl.Vector3, dt: f32) rl.Vector3 {
        const was = c.focus orelse {
            c.seatFocus(shoulder);
            return shoulder;
        };
        if (@abs(shoulder.y - was.y) > FOCUS_SNAP or mathx.dist2XZ(shoulder, was) > FOCUS_SNAP * FOCUS_SNAP) {
            c.seatFocus(shoulder);
            return shoulder;
        }
        const now = mathx.smoothCDV(was, shoulder, &c.focusVel, v3(FOCUS_FLAT, FOCUS_RISE, FOCUS_FLAT), FOCUS_CAP, dt);
        c.focus = now;
        return now;
    }

    pub fn centreRay(c: *const CamRig) struct { origin: rl.Vector3, dir: rl.Vector3 } {
        return .{ .origin = c.cam.position, .dir = mathx.normV(mathx.subV(c.cam.target, c.cam.position)) };
    }

    /// UNDER A ROOF THE EYE IS PINNED BOTH WAYS: the floor it may not sink through is the chamber's, and the ceiling
    /// it may not rise through is the rock. `world` answers three questions about a point — `at(x, z)` the floor
    /// under it, `roof(x, z)` the rock over it or `null` under the sky, and `wall(p)` whether masonry stands there.
    ///
    /// THE BOOM IS MARCHED OUT, NOT IN: it stops at the NEAREST thing in the way, so a wall is never jumped for the
    /// open ground behind it, and the step it stopped on is halved down to a continuous length.
    pub fn followRoofed(c: *CamRig, shoulder: rl.Vector3, world: anytype, dt: f32) void {
        const target = c.targetFor(c.focusOn(shoulder, dt));
        const back = c.backDir();
        const shortest = c.boomFloor();
        const want = c.boom();
        const g0 = world.at(target.x, target.z);
        var free = shortest;
        var stop: ?f32 = null;
        var d = shortest;
        while (d < want) {
            d = mathx.minF(d + GROUND_PROBE, want);
            if (clearAt(target, back, d, g0, world)) {
                free = d;
            } else {
                stop = d;
                break;
            }
        }
        if (stop) |blocked| {
            var lo = free;
            var hi = blocked;
            for (0..PROBE_HALVINGS) |_| {
                const mid = (lo + hi) * 0.5;
                if (clearAt(target, back, mid, g0, world)) lo = mid else hi = mid;
            }
            free = lo;
        }
        if (c.eased < 0 or free <= c.eased) {
            c.eased = free;
            c.easedVel = 0;
        } else {
            c.eased = mathx.smoothCD(c.eased, free, &c.easedVel, REGAIN_SECS, CLEAR_REGAIN, dt);
        }
        c.place(target, c.eased);
        const floor = world.at(c.cam.position.x, c.cam.position.z) + GROUND_CLEAR;
        if (c.cam.position.y < floor) c.cam.position.y = floor;
        if (world.roof(c.cam.position.x, c.cam.position.z)) |r| {
            const lid = r - GROUND_CLEAR;
            if (c.cam.position.y > lid) c.cam.position.y = mathx.maxF(lid, floor);
        }
    }

    fn clearAt(target: rl.Vector3, back: rl.Vector3, d: f32, g0: f32, world: anytype) bool {
        const p = mathx.addV(target, mathx.scaleV(back, d));
        const floor = world.at(p.x, p.z) + GROUND_CLEAR;
        // **MASONRY IS ASKED AT THE HEIGHT THE EYE WILL END AT**, which the floor lifts it to. Asked at the raw `p.y`
        // a hard up-tilt runs the line along the turf and a chest or a campfire behind him shortens the boom.
        // Asked BEFORE the roof, because a chamber's ceiling costs a second `supportAt` and a wall answers for free.
        if (world.wall(v3(p.x, mathx.maxF(p.y, floor), p.z))) return false;
        if (world.roof(p.x, p.z)) |r| {
            if (p.y > r - GROUND_CLEAR) return false;
        }
        // It gives way to ground standing PROUD of him, never to its own pitch: an up-tilt puts the eye low on purpose.
        return p.y >= floor or floor - GROUND_CLEAR <= g0 + GROUND_RISE;
    }

    fn place(c: *CamRig, target: rl.Vector3, dist: f32) void {
        c.cam.target = mathx.addV(target, c.shakeOff);
        c.cam.position = mathx.addV(mathx.addV(target, mathx.scaleV(c.backDir(), dist)), c.shakeOff);
    }
};

test "THE AIM PUSHES THE EYE IN PAST HIM, and gives the player's own zoom back afterwards" {
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.2, .dist = 7.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), rig.boom(), 1e-5);
    rig.aimB = 1.0;
    try std.testing.expect(rig.boom() < MIN_DIST);
    try std.testing.expectApproxEqAbs(AIM_DIST, rig.boom(), 1e-5);
    const shoulder = v3(0, 1.4, 0);
    rig.aimB = 0;
    const wide = rig.targetFor(shoulder);
    rig.aimB = 1.0;
    const tight = rig.targetFor(shoulder);
    try std.testing.expect(mathx.distXZ(tight, shoulder) < mathx.distXZ(wide, shoulder));
    try std.testing.expect(tight.y > wide.y);
    rig.aimB = 0;
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), rig.boom(), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), rig.dist, 1e-5);
    rig.aimB = 1.0;
    try std.testing.expect(rig.boomFloor() <= rig.boom());
}

const Probe = struct {
    const Box = struct { x0: f32, x1: f32, z0: f32, z1: f32, top: f32 };

    var floors: usize = 0;

    ground: *const fn (f32, f32) f32,
    ceil: ?*const fn (f32, f32) ?f32 = null,
    box: ?Box = null,

    fn at(p: Probe, x: f32, z: f32) f32 {
        floors += 1;
        return p.ground(x, z);
    }
    fn roof(p: Probe, x: f32, z: f32) ?f32 {
        return if (p.ceil) |f| f(x, z) else null;
    }
    fn wall(p: Probe, q: rl.Vector3) bool {
        const b = p.box orelse return false;
        return q.y <= b.top and q.x >= b.x0 and q.x <= b.x1 and q.z >= b.z0 and q.z <= b.z1;
    }
};

fn flatGround(_: f32, _: f32) f32 {
    return 0;
}

fn boomOf(rig: CamRig) f32 {
    return mathx.lenV(mathx.subV(rig.cam.position, rig.cam.target));
}

test "AN UP-TILT IS NOT A ZOOM — flat ground costs no boom, a hill behind still does" {
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = PITCH_MIN, .dist = DEFAULT_DIST };
    rig.followRoofed(v3(0, 1.4, 0), Probe{ .ground = flatGround }, 1.0);
    try std.testing.expect(boomOf(rig) > DEFAULT_DIST * 0.9);
    try std.testing.expect(rig.cam.position.y >= GROUND_CLEAR - 1e-4);
    const Hill = struct {
        fn ground(_: f32, z: f32) f32 {
            return mathx.maxF(0, -z - 1.0);
        }
    };
    var rig2 = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.1, .dist = MAX_DIST };
    rig2.followRoofed(v3(0, 1.4, 0), Probe{ .ground = Hill.ground }, 1.0);
    try std.testing.expect(boomOf(rig2) < MAX_DIST - GROUND_PROBE);
}

test "A WALL BEHIND HIM SHORTENS THE BOOM AT ONCE, AND GIVES IT BACK AT A RATE" {
    const Hill = struct {
        var on: bool = true;
        fn ground(_: f32, z: f32) f32 {
            return if (on and z < -3.5) 6.0 else 0.0;
        }
    };
    const world = Probe{ .ground = Hill.ground };
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.1, .dist = MAX_DIST };
    Hill.on = false;
    rig.followRoofed(v3(0, 1.4, 0), world, 1.0 / 60.0);
    const open = boomOf(rig);
    Hill.on = true;
    rig.followRoofed(v3(0, 1.4, 0), world, 1.0 / 60.0);
    const walled = boomOf(rig);
    try std.testing.expect(walled < open - 3.0);
    try std.testing.expect(rig.cam.position.z > -3.5);
    Hill.on = false;
    rig.followRoofed(v3(0, 1.4, 0), world, 1.0 / 60.0);
    const regained = boomOf(rig);
    try std.testing.expect(regained > walled);
    try std.testing.expect(regained < walled + CLEAR_REGAIN / 60.0 + 0.2);
    var i: usize = 0;
    while (i < 120) : (i += 1) rig.followRoofed(v3(0, 1.4, 0), world, 1.0 / 60.0);
    try std.testing.expect(boomOf(rig) > open - 0.3);
}

test "MASONRY PULLS THE EYE IN — the boom stops at the near face of a wall it will not thin, not past it" {
    const world = Probe{ .ground = flatGround, .box = .{ .x0 = -6, .x1 = 6, .z0 = -3.4, .z1 = -2.6, .top = 4.0 } };
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.1, .dist = MAX_DIST };
    rig.followRoofed(v3(0, 1.4, 0), world, 1.0 / 60.0);
    try std.testing.expect(rig.cam.position.z > -2.6);
    try std.testing.expect(boomOf(rig) < 2.7);
    std.debug.print(
        "\n  wall face at z -2.60: the eye stops at z {d:.3} on a {d:.2} m boom (asked for {d:.2})\n",
        .{ rig.cam.position.z, boomOf(rig), MAX_DIST },
    );
    // Over the wall's head the boom is its own again.
    var over = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.9, .dist = MAX_DIST };
    over.followRoofed(v3(0, 1.4, 0), world, 1.0 / 60.0);
    try std.testing.expect(boomOf(over) > MAX_DIST - 0.1);
}

test "WHAT THE MARCH COSTS A FRAME — the floor is sampled once a rung, plus the halvings" {
    const open = Probe{ .ground = flatGround };
    for ([_]f32{ DEFAULT_DIST, MAX_DIST }) |dist| {
        var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = DEFAULT_PITCH, .dist = dist };
        Probe.floors = 0;
        rig.followRoofed(v3(0, 1.4, 0), open, 1.0 / 60.0);
        const rungs = @ceil((dist - MIN_DIST) / GROUND_PROBE);
        std.debug.print("  boom {d:.1} m over open ground: {d} floor samples for {d:.0} rungs\n", .{ dist, Probe.floors, rungs });
        // Nothing stops it, so no halving runs: one sample a rung, one for the target and one for the placed eye.
        try std.testing.expect(@as(f32, @floatFromInt(Probe.floors)) <= rungs + 2);
    }
    const walled = Probe{ .ground = flatGround, .box = .{ .x0 = -6, .x1 = 6, .z0 = -3.4, .z1 = -2.6, .top = 4.0 } };
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.1, .dist = MAX_DIST };
    Probe.floors = 0;
    rig.followRoofed(v3(0, 1.4, 0), walled, 1.0 / 60.0);
    std.debug.print("  the same boom stopped by a wall at 2.6 m: {d} floor samples\n", .{Probe.floors});
    // Stopping early is CHEAPER than the open case — the march never walks past what blocks it.
    try std.testing.expect(Probe.floors < 12);
}

test "AN UP-TILT RUNS THE LINE ALONG THE TURF, and a chest standing in it costs no boom" {
    // The eye ends at GROUND_CLEAR whatever the pitch asked for, so masonry is asked at THAT height, not the line's.
    const low = Probe{ .ground = flatGround, .box = .{ .x0 = -6, .x1 = 6, .z0 = -3.4, .z1 = -2.6, .top = 0.6 } };
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = PITCH_MIN, .dist = DEFAULT_DIST };
    rig.followRoofed(v3(0, 1.4, 0), low, 1.0 / 60.0);
    try std.testing.expect(boomOf(rig) > DEFAULT_DIST * 0.9);
    const tall = Probe{ .ground = flatGround, .box = .{ .x0 = -6, .x1 = 6, .z0 = -3.4, .z1 = -2.6, .top = 4.0 } };
    var walled = CamRig{ .cam = undefined, .yaw = 0, .pitch = PITCH_MIN, .dist = DEFAULT_DIST };
    walled.followRoofed(v3(0, 1.4, 0), tall, 1.0 / 60.0);
    try std.testing.expect(walled.cam.position.z > -2.6);
}

test "THE BOOM IS A LENGTH, NOT A RUNG — what stops it is resolved past the march step" {
    var worst: f32 = 0;
    // Stopping short of `boomFloor` is the min-boom clamp, not the march — the wall stays outside it.
    var z: f32 = -8.0;
    while (z < -4.0) : (z += 0.013) {
        const world = Probe{ .ground = flatGround, .box = .{ .x0 = -6, .x1 = 6, .z0 = z, .z1 = z + 0.8, .top = 4.0 } };
        var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.1, .dist = MAX_DIST };
        rig.followRoofed(v3(0, 1.4, 0), world, 1.0 / 60.0);
        worst = mathx.maxF(worst, @abs(rig.cam.position.z - (z + 0.8)));
    }
    std.debug.print("  a wall walked in 13 mm steps: the eye lands within {d:.4} m of its face\n", .{worst});
    try std.testing.expect(worst < GROUND_PROBE / 16.0);
}

test "THE EYE DOES NOT INHERIT THE STAIR — a tread steps his footing, the focus ramps" {
    const world = Probe{ .ground = flatGround };
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = DEFAULT_PITCH, .dist = DEFAULT_DIST };
    var shoulder = v3(0, 1.4, 0);
    rig.followRoofed(shoulder, world, 1.0 / 60.0);
    var wasY = rig.cam.position.y;
    var jag: f32 = 0;
    var rise: f32 = 0;
    var f: usize = 0;
    // A flight climbed at 1.1 m/s: a 0.18 m tread arrives whole every ten frames.
    while (f < 180) : (f += 1) {
        if (f % 10 == 0) shoulder.y += 0.18;
        rig.followRoofed(shoulder, world, 1.0 / 60.0);
        const step = rig.cam.position.y - wasY;
        jag = mathx.maxF(jag, step);
        rise += step;
        wasY = rig.cam.position.y;
    }
    std.debug.print(
        "  eighteen 0.18 m treads: the eye rose {d:.2} m, worst single frame {d:.4} m ({d:.2} m/s)\n",
        .{ rise, jag, jag * 60.0 },
    );
    try std.testing.expect(jag < 0.18 / 4.0);
    try std.testing.expect(rise > 2.8);
}

test "the centre ray is the line the reticle marks" {
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0, .dist = 4 };
    rig.cam.position = v3(1, 2, -5);
    rig.cam.target = v3(1, 2, 0);
    const ray = rig.centreRay();
    try std.testing.expectApproxEqAbs(@as(f32, 1), ray.dir.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), ray.origin.x, 1e-5);
}

test "ground basis holds the strafe-sign invariant" {
    // AGENTS.md hard invariant: at yaw 0 the camera looks +Z from behind, so screen-right is world −X.
    const rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0, .dist = 4 };
    const f = rig.forwardXZ();
    const r = rig.rightXZ();
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), f.z, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1), r.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.z, 1e-6);
}

pub fn newCamRig(shoulder: rl.Vector3, yaw0: f32) CamRig {
    var c = CamRig{
        .cam = .{
            .position = mathx.zero3,
            .target = mathx.zero3,
            .up = v3(0, 1, 0),
            .fovy = FOVY,
            .projection = .perspective,
        },
        .yaw = yaw0,
        .pitch = DEFAULT_PITCH,
        .dist = DEFAULT_DIST,
    };
    c.follow(shoulder);
    return c;
}

test "UNDER A ROOF THE BOOM DOES NOT GO THROUGH IT, and it does not go into the rock either" {
    const Cave = struct {
        fn ground(x: f32, z: f32) f32 {
            return if (@sqrt(x * x + z * z) > 6.0) 10.0 else -3.0;
        }
        fn roof(x: f32, z: f32) ?f32 {
            return if (@sqrt(x * x + z * z) > 6.0) null else 0.0;
        }
    };
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.55, .dist = 7.0 };
    rig.solveFresh();
    const shoulder = v3(0, -3.0 + 1.4, 0);
    var i: usize = 0;
    while (i < 120) : (i += 1) rig.followRoofed(shoulder, Probe{ .ground = Cave.ground, .ceil = Cave.roof }, 1.0 / 60.0);

    const p = rig.cam.position;
    try std.testing.expect(p.y <= 0.0);
    try std.testing.expect(p.y >= -3.0);
    try std.testing.expect(@sqrt(p.x * p.x + p.z * p.z) <= 6.0);
    std.debug.print(
        "\ncave boom: eye at {d:.2} m under a 0.00 m ceiling, {d:.2} m out from the man\n",
        .{ p.y, mathx.distXZ(p, shoulder) },
    );
}
