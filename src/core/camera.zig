const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const clampF = mathx.clampF;


pub const MIN_DIST = 2.4;
pub const MAX_DIST = 9.0;
const DEFAULT_DIST = 4.6;
const DEFAULT_PITCH = 0.28;
const ZOOM_STEP = 0.6;
const LOOK_SENS = 0.0032; // radians per pixel of mouse motion
/// ~ -22 deg, looking UP from below. Wider than the -0.20 the free look ever asked for, because the LOCK
/// now tilts the rig onto whatever it is fixed on (`game.lockPitch`): an ogre's chest is two and a half
/// metres up and eleven degrees of lift clipped short of framing it, which put the one thing you are locked
/// to against the top edge of the screen.
const PITCH_MIN = -0.38;
const PITCH_MAX = 1.15; // ~  66 deg (looking down)
const SHOULDER = 0.55;
const TARGET_RAISE = 0.15;
const GROUND_CLEAR = 0.7;
/// …and how much boom one probe of that search gives up. Named beside the clearance it is searching for:
/// the two are only ever chosen against each other, and a bare 0.25 in the loop reads as arbitrary.
const GROUND_PROBE = 0.25;
/// How far the ground under the eye must stand PROUD of the ground under the hero before it counts as a
/// hill worth paying boom for — just under one terrain riser (`wf.HEIGHT_STEP` 0.25), so quantisation
/// noise never bills a step of zoom.
const GROUND_RISE = 0.2;

const AIM_DIST = 0.7;
const AIM_SHOULDER = 0.30;
const AIM_RAISE = 0.42;

const LIFT_SHARE: f32 = 0.55;
const LIFT_RATE: f32 = 10.0;

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
    trauma: f32 = 0,
    shakeT: f32 = 0,
    shakeOff: rl.Vector3 = mathx.zero3,

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

    pub fn tickLift(c: *CamRig, heroLift: f32, dt: f32) void {
        c.lift = mathx.approach(c.lift, LIFT_SHARE * heroLift, LIFT_RATE * dt);
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

    /// THE BOOM GIVES WAY TO TERRAIN, NEVER TO ITS OWN PITCH — an up-tilt puts the eye low ON PURPOSE
    /// (`game.lockPitch`), and shortening to buy that altitude back read as a hard zoom onto every ogre.
    /// Only ground PROUD of the hero's own level is paid for in boom; the skim clamp does the rest.
    pub fn followClear(c: *CamRig, shoulder: rl.Vector3, ctx: anytype, comptime groundAt: fn (@TypeOf(ctx), f32, f32) f32) void {
        const target = c.targetFor(shoulder);
        const back = c.backDir();
        const shortest = c.boomFloor();
        const g0 = groundAt(ctx, target.x, target.z);
        var d = c.boom();
        while (d > shortest) {
            const p = mathx.addV(target, mathx.scaleV(back, d));
            const g = groundAt(ctx, p.x, p.z);
            if (p.y >= g + GROUND_CLEAR or g <= g0 + GROUND_RISE) break;
            d = mathx.maxF(d - GROUND_PROBE, shortest);
        }
        c.place(target, d);
        const floor = groundAt(ctx, c.cam.position.x, c.cam.position.z) + GROUND_CLEAR;
        if (c.cam.position.y < floor) c.cam.position.y = floor;
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

test "AN UP-TILT IS NOT A ZOOM — flat ground costs no boom, a hill behind still does" {
    const Flat = struct {
        fn ground(_: void, _: f32, _: f32) f32 {
            return 0;
        }
    };
    var rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = PITCH_MIN, .dist = DEFAULT_DIST };
    rig.followClear(v3(0, 1.4, 0), {}, Flat.ground);
    // The skim clamp lifts the eye a little, so measure against 0.9.
    const boomKept = mathx.lenV(mathx.subV(rig.cam.position, rig.cam.target));
    try std.testing.expect(boomKept > DEFAULT_DIST * 0.9);
    try std.testing.expect(rig.cam.position.y >= GROUND_CLEAR - 1e-4);
    const Hill = struct {
        fn ground(_: void, _: f32, z: f32) f32 {
            return mathx.maxF(0, -z - 1.0);
        }
    };
    var rig2 = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0.1, .dist = MAX_DIST };
    rig2.followClear(v3(0, 1.4, 0), {}, Hill.ground);
    const boomPaid = mathx.lenV(mathx.subV(rig2.cam.position, rig2.cam.target));
    try std.testing.expect(boomPaid < MAX_DIST - GROUND_PROBE);
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
