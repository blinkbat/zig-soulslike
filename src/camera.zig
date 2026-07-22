const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const clampF = mathx.clampF;

// Third-person OVER-THE-SHOULDER camera, souls-style: it orbits a point near the hero's
// shoulders at a fixed distance, fully rotatable by the mouse (yaw + clamped pitch) with
// scroll zoom. The hero is framed slightly off-centre (a lateral shoulder offset) so the
// view ahead is unobstructed. The rig also exposes the camera-relative ground basis that
// WASD movement steers by.

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

pub const CamRig = struct {
    cam: rl.Camera3D,
    yaw: f32, // azimuth (radians); 0 = camera behind a +Z-facing hero
    pitch: f32, // elevation (radians); + looks down
    dist: f32,

    // Ground-plane forward the camera looks along (for camera-relative movement).
    pub fn forwardXZ(c: *const CamRig) rl.Vector3 {
        return v3(mathx.sinf(c.yaw), 0, mathx.cosf(c.yaw));
    }
    // Ground-plane right (screen-right) of the camera. The camera sits behind the hero
    // looking +forward, so screen-right = cross(up, eye−target) = −(cos yaw, 0, −sin yaw):
    // at yaw 0 that's −X, which is what pressing D must push toward.
    pub fn rightXZ(c: *const CamRig) rl.Vector3 {
        return v3(-mathx.cosf(c.yaw), 0, mathx.sinf(c.yaw));
    }

    // Add to yaw/pitch in radians (clamped). Shared by mouse and right-stick paths.
    pub fn orbit(c: *CamRig, dYaw: f32, dPitch: f32) void {
        c.yaw = mathx.wrapPi(c.yaw + dYaw);
        c.pitch = clampF(c.pitch + dPitch, PITCH_MIN, PITCH_MAX);
    }

    // Mouse look (per-pixel). Mouse-right orbits the camera right → looks right.
    pub fn rotate(c: *CamRig, dxPx: f32, dyPx: f32) void {
        c.orbit(-dxPx * LOOK_SENS, dyPx * LOOK_SENS);
    }

    // Snap the camera back behind the hero (Elden Ring R3 with no lock-on target).
    pub fn recenter(c: *CamRig, heroFacing: f32) void {
        c.yaw = heroFacing;
        c.pitch = DEFAULT_PITCH;
    }

    pub fn zoom(c: *CamRig, wheel: f32) void {
        c.dist = clampF(c.dist - wheel * ZOOM_STEP, MIN_DIST, MAX_DIST);
    }

    // Re-aim at the hero's shoulder point. Call every frame after input + movement.
    pub fn follow(c: *CamRig, shoulder: rl.Vector3) void {
        const cp = mathx.cosf(c.pitch);
        const sp = mathx.sinf(c.pitch);
        // Unit vector from target toward the camera (behind + above by pitch).
        const back = v3(-mathx.sinf(c.yaw) * cp, sp, -mathx.cosf(c.yaw) * cp);
        const right = c.rightXZ();
        const target = v3(
            shoulder.x + right.x * SHOULDER,
            shoulder.y + TARGET_RAISE,
            shoulder.z + right.z * SHOULDER,
        );
        c.cam.target = target;
        c.cam.position = mathx.addV(target, mathx.scaleV(back, c.dist));
    }
};

test "ground basis holds the strafe-sign invariant" {
    // AGENTS.md hard invariant: the camera looks +Z from behind at yaw 0, so screen-right
    // is world -X. Flipping rightXZ mirrors L/R walking.
    const rig = CamRig{ .cam = undefined, .yaw = 0, .pitch = 0, .dist = 4 };
    const f = rig.forwardXZ();
    const r = rig.rightXZ();
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), f.z, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1), r.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.z, 1e-6);
}

// `yaw0` should match the hero's initial facing so the camera starts BEHIND them
// (camera-forward aligned with the hero's heading), souls-style.
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
