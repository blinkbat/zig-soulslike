const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const clampF = mathx.clampF;


pub const MIN_DIST = 2.4;
pub const MAX_DIST = 9.0;
const DEFAULT_DIST = 4.6;
const DEFAULT_PITCH = 0.28; // gentle downward framing; recenter (R3) returns here too
const ZOOM_STEP = 0.6;
const LOOK_SENS = 0.0032; // radians per pixel of mouse motion
const PITCH_MIN = -0.20; // ~ -11 deg (looking up from just below)
const PITCH_MAX = 1.15; // ~  66 deg (looking down)
const SHOULDER = 0.55; // lateral offset (world units): hero sits left of centre
const TARGET_RAISE = 0.15; // lift the look-at a touch above the shoulder point
/// How far the eye stays clear of the ground (see `followClear`).
const GROUND_CLEAR = 0.7;

// AIMING PUSHES THE EYE IN PAST HIM (L2 / RMB with the bow).
const AIM_DIST = 0.7; // right up past his head — near enough that he is behind the lens, not in front of it
const AIM_SHOULDER = 0.30;
const AIM_RAISE = 0.42;

const SHAKE_MAX = 0.13; // world-unit jitter amplitude at full trauma
const SHAKE_DECAY = 2.6; // trauma drained per second — shakes die fast (a crack, not a wobble)
const SHAKE_FREQ = 33.0; // base jitter frequency (layered sines, incommensurate)

pub const CamRig = struct {
    cam: rl.Camera3D,
    yaw: f32, // azimuth (radians); 0 = camera behind a +Z-facing hero
    pitch: f32, // elevation (radians); + looks down
    dist: f32,
    /// HOW FAR THE AIM VIEW IS BLENDED IN, 0..1 — pushed in from the hero's own stance blend every frame.
    aimB: f32 = 0,
    trauma: f32 = 0, // 0..1 impact charge; addShake() feeds it, tickShake() drains it
    shakeT: f32 = 0, // running phase for the jitter noise
    shakeOff: rl.Vector3 = mathx.zero3, // this frame's world-space jitter (zero when calm)

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
        const s = c.trauma * c.trauma * SHAKE_MAX; // trauma² — big hits crack, small ones whisper
        if (s < 0.0005) {
            c.shakeOff = mathx.zero3;
            return;
        }
        // Layered incommensurate sines ≈ smooth noise, and no RNG to reseed or replay.
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
            shoulder.y + mathx.lerpF(TARGET_RAISE, AIM_RAISE, k),
            shoulder.z + right.z * off,
        );
    }

    /// The player's own zoom, pulled in past the hero by the aim blend.
    pub fn boom(c: *const CamRig) f32 {
        return mathx.lerpF(c.dist, AIM_DIST, mathx.clampF(c.aimB, 0, 1));
    }

    fn boomFloor(c: *const CamRig) f32 {
        return mathx.minF(MIN_DIST, c.boom());
    }

    pub fn follow(c: *CamRig, shoulder: rl.Vector3) void {
        c.place(c.targetFor(shoulder), c.boom());
    }

    pub fn followCentred(c: *CamRig, at: rl.Vector3) void {
        c.place(v3(at.x, at.y + TARGET_RAISE, at.z), c.dist);
    }

    pub fn centreRay(c: *const CamRig) struct { origin: rl.Vector3, dir: rl.Vector3 } {
        return .{ .origin = c.cam.position, .dir = mathx.normV(mathx.subV(c.cam.target, c.cam.position)) };
    }

    pub fn followClear(c: *CamRig, shoulder: rl.Vector3, ctx: anytype, comptime groundAt: fn (@TypeOf(ctx), f32, f32) f32) void {
        const target = c.targetFor(shoulder);
        const back = c.backDir();
        const shortest = c.boomFloor();
        var d = c.boom();
        while (d > shortest) {
            const p = mathx.addV(target, mathx.scaleV(back, d));
            if (p.y >= groundAt(ctx, p.x, p.z) + GROUND_CLEAR) break;
            d = mathx.maxF(d - 0.25, shortest);
        }
        c.place(target, d);
        const floor = groundAt(ctx, c.cam.position.x, c.cam.position.z) + GROUND_CLEAR;
        if (c.cam.position.y < floor) c.cam.position.y = floor;
    }

    fn place(c: *CamRig, target: rl.Vector3, dist: f32) void {
        // Impact jitter rides BOTH ends so the whole frame kicks (a shake, not a re-aim).
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
            .fovy = 55,
            .projection = .perspective,
        },
        .yaw = yaw0,
        .pitch = DEFAULT_PITCH,
        .dist = DEFAULT_DIST,
    };
    c.follow(shoulder);
    return c;
}
