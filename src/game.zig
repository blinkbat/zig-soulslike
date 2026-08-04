const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const gfx = @import("gfx.zig");
const envmod = @import("env.zig");
const worldfmt = @import("worldfmt.zig");
const editormod = @import("editor.zig");
const objviewmod = @import("objview.zig"); // its two off-screen preview targets are freed on the way out
const heromod = @import("hero.zig");
const cameramod = @import("camera.zig");
const hud_ = @import("hud.zig");
const menumod = @import("menu.zig");
const frogmod = @import("frog.zig");
const foemod = @import("foe.zig"); // THE FOE STANDARD — the shared Blade/strike contract
const combat = @import("combat.zig");
const collision = @import("collision.zig");
const rumblemod = @import("rumble.zig");
const archermod = @import("archer.zig");
const ogremod = @import("ogre.zig");
const koboldmod = @import("kobold.zig"); // THE WARBAND — three roles in one group (the priest heals)
const broodmod = @import("brood.zig"); // THE BROOD — a mother, her sacs and what comes out of them
const warriormod = @import("warrior.zig"); // THE SKELETAL WARRIORS — the archer's bones, armed two ways
const chestmod = @import("chest.zig"); // the openable boxes
const restmod = @import("rest.zig"); // sitting at a bonfire
const item = @import("item.zig");
const sfx = @import("audio.zig"); // the procedural sound bank — every voice synthesized at launch

const v3 = mathx.v3;
const rgba = mathx.rgba;

const PAD = rumblemod.PAD;

const SCREEN_W = 1280;
const SCREEN_H = 800;

const WALK_SPEED = heromod.WALK_SPEED; // keyboard walk / gentle left-stick tilt
const RUN_SPEED = heromod.RUN_SPEED; // full left-stick tilt (light tilt scales down toward walk)
const SPRINT_SPEED = heromod.SPRINT_SPEED; // hold Circle/B (or Shift): dash/sprint
const TURN_RATE = 12.0; // rad/sec the hero yaws toward its heading (souls turn briskly)
const STRAFE_SPEED = heromod.STRAFE_SPEED; // LOCKED-ON sideways travel, as a fraction of forward
const STICK_DEADZONE = 0.16; // left-stick move deadzone
const LOOK_DEADZONE = 0.14;
const LOOK_CLAIM = 0.40;
// Pixels of mouse travel in one frame that count as the player REACHING FOR THE MOUSE — see the look-device latch.
const MOUSE_WAKE: f32 = 2.0;
// YAW is unbounded and a full turn at this rate takes ~2.3 s.
const LOOK_RATE_YAW = 3.4; // rad/sec orbit at full right-stick deflection
const LOOK_RATE_PITCH = 2.0;
const LOOK_CURVE = 1.7;
/// WHAT THE LOOK IS WORTH WITH THE BOW UP, mouse and stick alike.
const AIM_LOOK_SCALE = 0.42;
const ROLL_TAP_MAX = 0.22; // Circle/B released before this (real seconds) = a dodge tap; longer = a sprint hold
// NO run-unlock hold, ever (owner's rule, see AGENTS.md): the stick IS the speed — tilt maps straight to ground speed every frame, and keyboard movement runs immediately.

// Impact shake fed to the camera rig (trauma² response in camera.zig), sized so a light reads as a tick and a slam cracks the frame.
const SHAKE_HIT_LIGHT = 0.09;
const SHAKE_HIT_HEAVY = 0.15;
const SHAKE_KILL = 0.26;
const SHAKE_HURT = 0.42;
const SHAKE_HURT_HEAVY = 0.62;
// A CAUGHT blow cracks the frame less than one that lands — he HELD, and the shake says so.
const SHAKE_BLOCK = 0.40;
const SHAKE_GUARD_BREAK = 0.72;
const BLOW_HEAVIEST = ogremod.SLAM_HIT.raw(); // the whole blow, elements included — see `heroBlockBeat`
const BLOCK_FELT_MIN = 0.25;
const BLOCK_FELT_HEAVY = 0.5;
const SHAKE_DEATH = 0.85;
const SHAKE_CHEST = 0.12;
/// The debug corner's AMMO row, in its own warmer ink so the count reads apart from the stats above it.
const STAT_WARN = mathx.rgba(206, 150, 110, 255);
// A SAC SPLITTING is bad news arriving; a sac BURST is you having stopped it.
const SHAKE_HATCH = 0.30;
const SHAKE_SAC_BURST = 0.34;
const RESPAWN_HOLD = 0.55; // seconds of FULL black after the respawn…
const RESPAWN_FADE = 0.9;

pub var PLAY_HALF: f32 = worldfmt.DEFAULT_HALF - envmod.PLAY_INSET;

const HERO_R = foemod.HERO_R;

const MAX_ARROWS = 24;
/// His own quiver in flight.
const MAX_SHAFTS = 12;
/// The hero's centre of mass ABOVE HIS OWN FEET — not a world height.
pub const HERO_CENTER_Y = 1.0;

const COLLIDE_RATE = 11.0; // world units / sec

const GROUND_RISE_RATE = 9.0; // m/s the body climbs onto higher ground…
const GROUND_FALL_RATE = 16.0;
/// Past this the ease is abandoned and the actor is planted: a teleport (respawn, F5 playtest, the shot harness) must not spend a second sliding up out of the earth, and no real step is anywhere near it.
const GROUND_SNAP: f32 = 2.5;

// Depth clip planes, set once in run().
const CLIP_NEAR = 0.55;
const CLIP_FAR = 320.0;

const MAX_LOCK_R = 17.0; // won't acquire, and drops, a foe beyond this
const LOCK_CAM_EASE = 9.0; // exponential ease rate for the lock-on camera swing (quick, snap-free)
const LOCK_PITCH = 0.24; // framing pitch while locked (the toads sit low)
const LOCK_FLICK = 0.65; // right-stick |x| past this cycles to the next target

const CLEAR = rgba(80, 76, 69, 255);

/// What the two look devices said this frame, which one owns the camera, and what the camera actually DID with them.
const LookProbe = struct {
    mdx: f32 = 0,
    mdy: f32 = 0,
    rx: f32 = 0,
    ry: f32 = 0,
    mag: f32 = 0, // RAW stick magnitude, 0..1 — vs LOOK_DEADZONE (turns) and LOOK_CLAIM (claims)
    dyaw: f32 = 0, // degrees of yaw applied this frame, whichever device did it
    pad: bool = false,
};

pub const Game = struct {
    scene: gfx.Scene,
    sky: gfx.Sky,
    vignette: gfx.Vignette,
    retro: gfx.Retro,
    menu: menumod.Menu,
    map: worldfmt.Map, // THE WORLD, as data: env materializes this and the editor edits it
    editor: editormod.Editor,
    env: envmod.Env,
    hero: heromod.Hero,
    warren: frogmod.Knot, // the knot of gaping toads
    line: archermod.Line, // the skeletal archers perched in the ruins
    grief: ogremod.Grief, // the lone one-eyed ogre, deep in the ruins
    band: koboldmod.Warband, // the kobold warband — berserkers, priests and slingers, mixed
    brood: broodmod.Brood, // the brood mothers, their egg sacs, their hatchlings and their acid
    muster: warriormod.Muster, // the skeletal warriors — shieldmen and greatswords, mixed
    chests: chestmod.Chests, // the openable boxes — props with a lid and a state (chest.zig)
    rest: restmod.Rest = .{}, // sitting at a bonfire: the state machine and the fade (rest.zig)
    /// The player's own retro stack, parked while a rest borrows the screen for its VHS look.
    restRetro: [gfx.RETRO_COUNT]f32 = [_]f32{0} ** gfx.RETRO_COUNT,
    bag: item.Bag = .{},
    arrowModel: rl.Model, // shared arrow mesh, drawn per live/stuck arrow with its own matrix
    clumpModel: rl.Model,
    venomModel: rl.Model,
    fireArrowModel: rl.Model,
    arrows: [MAX_ARROWS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_ARROWS,
    /// …and the ones HE loosed (see MAX_SHAFTS).
    shafts: [MAX_SHAFTS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_SHAFTS,
    rig: cameramod.CamRig,
    lock: ?FoeRef = null, // ER lock-on: which foe (toad or skeleton) is locked, or null
    rumble: rumblemod.Rumble = .{}, // controller vibration, keyed to combat beats
    deathFade: f32 = 0, // post-respawn fade-from-black seconds remaining (armed while dead)
    probe: LookProbe = .{},
    /// The REAL frame time the DRAWING layer needs — the occluder fade's clock, and nothing else, since a
    /// fade paced off the time-scaled dt would crawl in slow motion. `--shot` parks it at a settle-size
    /// step (`shots.SETTLE_DT`): a still frame cannot show a fade, so a capture wants its END state.
    drawDt: f32 = 1.0 / 60.0,

    fn init(g: *Game) void {
        g.scene = gfx.Scene.init();
        g.sky = gfx.Sky.init();
        g.vignette = gfx.Vignette.init();
        g.retro = gfx.Retro.init(rl.getScreenWidth(), rl.getScreenHeight());
        g.menu = .{}; // opens on the main screen: Continue / Debug / Quit
        worldfmt.loadOrPanic(worldfmt.START_MAP, &g.map);
        PLAY_HALF = g.map.half - envmod.PLAY_INSET; // before anything spawns against it
        g.env.build(&g.scene); // meshes once…
        g.env.uploadSoil(&g.map);
        g.env.uploadWater(&g.map);
        g.env.uploadHeight(&g.map);
        g.env.materialize(&g.map);
        g.hero = heromod.Hero.init(g.scene.shader);
        g.hero.pos = mathx.ground(0, 4); // start just south of the ruin avenue
        plantActor(g, &g.hero.pos);
        g.hero.facing = std.math.pi; // facing -Z, into the columns
        g.hero.setSpawn(g.hero.pos, g.hero.facing); // where a death returns him
        g.hero.pose();
        g.warren = frogmod.Knot.init(g.scene.shader);
        g.line = archermod.Line.init(g.scene.shader);
        g.grief = ogremod.Grief.init(g.scene.shader);
        g.band = koboldmod.Warband.init(g.scene.shader);
        g.brood = broodmod.Brood.init(g.scene.shader);
        g.muster = warriormod.Muster.init(g.scene.shader);
        g.chests = chestmod.Chests.init(g.scene.shader);
        rehomeFoes(g);
        g.rest = .{};
        rehomeChests(g);
        g.bag = .{};
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.clumpModel = koboldmod.clumpMesh(g.scene.shader);
        g.venomModel = broodmod.venomMesh(g.scene.shader);
        g.fireArrowModel = archermod.fireArrowMesh(g.scene.shader);
        g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
        g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
        g.shafts = [_]archermod.Arrow{.{}} ** MAX_SHAFTS;
        g.editor = .{};
        g.lock = null;
        g.rumble = .{};
        g.deathFade = 0;
        g.restRetro = [_]f32{0} ** gfx.RETRO_COUNT;
        // …the look probe included: `Game` is built in place from `alloc.create`, so a field this block misses never gets its default at all — and `pad` is a bool, where raw heap bytes are illegal behaviour rather than merely a wrong caption.
        g.probe = .{};
    }
};

/// THE FOE GROUPS, WRITTEN DOWN ONCE.
const FoeGroup = struct { field: []const u8, kind: ?FoeKind };
const FOE_GROUPS = [_]FoeGroup{
    .{ .field = "warren", .kind = .toad },
    .{ .field = "line", .kind = .archer },
    .{ .field = "grief", .kind = .ogre },
    .{ .field = "band", .kind = null },
    .{ .field = "brood", .kind = null },
    .{ .field = "muster", .kind = null },
};

fn rehomeFoes(g: *Game) void {
    inline for (FOE_GROUPS) |f| @field(g, f.field).reset(&g.map);
}

/// EVERY LIST THE GAME TARGETS, walked ONCE: the five `FOE_GROUPS`, plus any SECOND list a group keeps on the field (`liveExtraConst` — the brood's sacs, which are real targets with their own HP). Spliced in by hand per site instead, the answers drift apart: four sites had the sacs and `rayFoeDist` never did, so an aimed shaft converged straight past a clutch.
fn eachTarget(g: *const Game, ctx: anytype, comptime visit: anytype) void {
    inline for (FOE_GROUPS) |gr| {
        visit(ctx, @field(g, gr.field).liveConst(), gr.kind);
        // The extra list answers for its own members' kinds (`Sac.kind()`), so the row carries none.
        if (comptime @hasDecl(@FieldType(Game, gr.field), "liveExtraConst")) {
            visit(ctx, @field(g, gr.field).liveExtraConst(), @as(?FoeKind, null));
        }
    }
}

fn groupCap(comptime field: []const u8) usize {
    const G = @FieldType(Game, field);
    for (@typeInfo(G).@"struct".fields) |f| {
        const info = @typeInfo(f.type);
        if (info != .array) continue;
        if (@typeInfo(info.array.child) != .@"struct") continue;
        if (@hasField(info.array.child, "pos")) return info.array.len;
    }
    @compileError("game: " ++ field ++ " has no foe array to size a position snapshot from");
}

const FOE_CAP = blk: {
    var w: usize = 0;
    for (FOE_GROUPS) |f| w = @max(w, groupCap(f.field));
    break :blk w;
};

const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

const Stick = struct { x: f32 = 0, y: f32 = 0, mag: f32 = 0 };

fn stickRadial(x: f32, y: f32, dz: f32, curve: f32) Stick {
    const m = @sqrt(x * x + y * y);
    if (m < dz) return .{};
    // Clamped, because a real pad reports past 1 on the diagonals (a square gate on a round stick).
    const t = mathx.minF((m - dz) / (1.0 - dz), 1.0);
    return .{ .x = x / m, .y = y / m, .mag = std.math.pow(f32, t, curve) };
}

test "a radial stick keeps the thumb's ANGLE and does not favour the cardinals" {
    const ang = 0.26;
    const s = stickRadial(mathx.cosf(ang), mathx.sinf(ang), LOOK_DEADZONE, 1.0);
    try std.testing.expectApproxEqAbs(ang, std.math.atan2(s.y, s.x), 1e-5);
    // …and a full-deflection DIAGONAL is as fast as a full-deflection cardinal.
    const diag = stickRadial(0.7071, 0.7071, LOOK_DEADZONE, 1.0);
    const card = stickRadial(1.0, 0.0, LOOK_DEADZONE, 1.0);
    try std.testing.expectApproxEqAbs(card.mag, diag.mag, 1e-4);
    // Dead centre is dead, and a pad reading past 1 on the gate corners still clamps to 1.
    try std.testing.expectEqual(@as(f32, 0), stickRadial(0.05, -0.05, LOOK_DEADZONE, 1.0).mag);
    try std.testing.expectApproxEqAbs(@as(f32, 1), stickRadial(1.0, 1.0, LOOK_DEADZONE, 1.0).mag, 1e-4);
}

test "A DRIFTING STICK CANNOT CLAIM THE CAMERA — the two look thresholds are not the same number" {
    try std.testing.expect(LOOK_CLAIM > LOOK_DEADZONE);
    // …and the gap has to clear a real resting deflection.
    const WORN_STICK_REST: f32 = 0.25;
    try std.testing.expect(LOOK_CLAIM > WORN_STICK_REST);
    // …while staying nowhere near a deliberate push, or reaching for the stick stops working.
    try std.testing.expect(LOOK_CLAIM < 0.7);
    const drift = stickRadial(WORN_STICK_REST, 0, LOOK_DEADZONE, LOOK_CURVE);
    try std.testing.expect(drift.mag < 0.10);
    // …and dead centre still claims nothing at all.
    try std.testing.expectEqual(@as(f32, 0), stickRadial(0, 0, LOOK_DEADZONE, LOOK_CURVE).mag);
}

test "the look curve is fine near centre and still reaches full rate at the rim" {
    // A curve that changed the TOP speed would be a sensitivity change wearing a curve's clothes.
    try std.testing.expectApproxEqAbs(@as(f32, 1), stickRadial(1.0, 0.0, LOOK_DEADZONE, LOOK_CURVE).mag, 1e-4);
    const half = stickRadial(0.5 * (1.0 - LOOK_DEADZONE) + LOOK_DEADZONE, 0.0, LOOK_DEADZONE, LOOK_CURVE);
    try std.testing.expect(half.mag < 0.5); // half throw gives LESS than half rate — that is the point
    try std.testing.expect(half.mag > 0.2);
}

fn gatherMove() Move {
    var sprint = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    if (rl.isGamepadAvailable(PAD)) {
        if (rl.isGamepadButtonDown(PAD, .right_face_right)) sprint = true;
        const s = stickRadial(
            rl.getGamepadAxisMovement(PAD, .left_x),
            rl.getGamepadAxisMovement(PAD, .left_y),
            STICK_DEADZONE,
            1.0,
        );
        if (s.mag > 0.001) {
            const sp = if (sprint) SPRINT_SPEED else s.mag * RUN_SPEED; // tilt IS the speed, this frame
            return .{ .fx = s.x, .fz = -s.y, .speed = sp }; // stick up (−y) = forward
        }
    }
    var kx: f32 = 0;
    var kz: f32 = 0;
    if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) kz += 1;
    if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) kz -= 1;
    if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) kx += 1;
    if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) kx -= 1;
    if (kx != 0 or kz != 0) {
        const sp: f32 = if (sprint) SPRINT_SPEED else RUN_SPEED;
        return .{ .fx = kx, .fz = kz, .speed = sp };
    }
    return .{};
}

fn sprintingMove(mv: Move) bool {
    return mv.speed > RUN_SPEED + 0.01 and (mv.fx * mv.fx + mv.fz * mv.fz) > 1e-6;
}

const WADE_KNEE: f32 = 0.75; // mid-thigh on the H=1.8 rig — where a leg starts pushing instead of swinging
const WADE_DEEP: f32 = 1.5;
const WADE_SLOWEST: f32 = 0.8;

fn wadeDrag(g: *const Game) f32 {
    return wadeDragAt(g.env.wadeDepth(g.hero.pos.x, g.hero.pos.z));
}

test "wading costs the run first and never roots him" {
    // Ankle-deep is FREE — the shallows must not read as glue.
    try std.testing.expectEqual(@as(f32, 1.0), wadeDragAt(0.2));
    // …and past the knee the WALK is what is left, dragged down but never to nothing.
    try std.testing.expect(wadeDragAt(WADE_DEEP) * WALK_SPEED < WALK_SPEED);
    try std.testing.expect(wadeDragAt(WADE_DEEP * 3) * WALK_SPEED > 0.1);
    // MONOTONIC: deeper is never faster.
    try std.testing.expect(wadeDragAt(0.7) > wadeDragAt(0.9));
}

/// The drag curve alone, off a depth
fn wadeDragAt(d: f32) f32 {
    if (d <= WADE_KNEE) return 1.0;
    return mathx.lerpF(1.0, WADE_SLOWEST, mathx.smoothstep(WADE_KNEE, WADE_DEEP, d));
}

fn groundActor(g: *const Game, pos: *rl.Vector3, dt: f32) void {
    const want = g.env.groundAt(pos.x, pos.z);
    const d = want - pos.y;
    if (@abs(d) > GROUND_SNAP) {
        pos.y = want; // a teleport, not a step
        return;
    }
    const rate: f32 = if (d > 0) GROUND_RISE_RATE else GROUND_FALL_RATE;
    pos.y = mathx.approach(pos.y, want, rate * dt);
}

fn plantActor(g: *const Game, pos: *rl.Vector3) void {
    pos.y = g.env.groundAt(pos.x, pos.z);
}

pub fn envGroundAt(e: *const envmod.Env, x: f32, z: f32) f32 {
    return e.groundAt(x, z);
}

fn snapshotPos(foes: anytype, out: []rl.Vector3) void {
    for (foes, 0..) |*f, i| {
        if (i >= out.len) return;
        out[i] = f.pos;
    }
}

fn gateTerrain(g: *const Game, foes: anytype, was: []const rl.Vector3) void {
    for (foes, 0..) |*f, i| {
        if (i >= was.len or !f.alive() or f.airborne()) continue;
        const dx = f.pos.x - was[i].x;
        const dz = f.pos.z - was[i].z;
        const d = @sqrt(dx * dx + dz * dz);
        if (d < 1e-5) continue;
        const stepped = g.env.walkStep(was[i], v3(dx / d, 0, dz / d), d);
        f.pos.x = stepped.x;
        f.pos.z = stepped.z;
    }
}

fn moveHero(g: *Game, dt: f32, mv: Move, faceYaw: ?f32) void {
    const fwd = g.rig.forwardXZ();
    const right = g.rig.rightXZ();
    var dir = v3(fwd.x * mv.fz + right.x * mv.fx, 0, fwd.z * mv.fz + right.z * mv.fx);
    const l = mathx.lenXZ(dir);
    const isMoving = l > 0.001 and mv.speed > 0.001;
    var moved: f32 = 0;
    var speed: f32 = 0;
    var moveYaw: ?f32 = null;
    // ER exception below: a hold-B SPRINT while locked faces TRAVEL, so it is not a strafe at all.
    const sprinting = isMoving and sprintingMove(mv);
    if (isMoving) {
        dir = v3(dir.x / l, 0, dir.z / l);
        speed = mv.speed;
        moveYaw = mathx.headingXZ(dir);
        // Locked-on ANISOTROPY (ER's too): sideways travel runs slower than forward.
        if (faceYaw != null and !sprinting) {
            const latAmt = @abs(mathx.sinf(mathx.wrapPi(moveYaw.? - g.hero.facing)));
            speed *= mathx.lerpF(1.0, STRAFE_SPEED, latAmt);
        }
        moved = speed * dt;
        const stepped = g.env.walkStep(g.hero.pos, dir, moved);
        g.hero.pos.x = mathx.clampF(stepped.x, -PLAY_HALF, PLAY_HALF);
        g.hero.pos.z = mathx.clampF(stepped.z, -PLAY_HALF, PLAY_HALF);
    }
    if (faceYaw != null and !sprinting) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, faceYaw.?, TURN_RATE * dt);
    } else if (isMoving) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, moveYaw.?, TURN_RATE * dt);
    }
    g.hero.update(dt, moved, speed, moveYaw);
    g.hero.pose();
}

fn leanToGround(g: *Game, dt: f32) void {
    const face = mathx.headingDir(g.hero.facing);
    const want = heromod.slopeLean(g.env.slopeAlong(g.hero.pos.x, g.hero.pos.z, face));
    g.hero.slopePitch = mathx.approach(g.hero.slopePitch, want, heromod.SLOPE_LEAN_RATE * dt);
}

fn rollDir(g: *Game, mv: Move) rl.Vector3 {
    const fwd = g.rig.forwardXZ();
    const right = g.rig.rightXZ();
    const d = v3(fwd.x * mv.fz + right.x * mv.fx, 0, fwd.z * mv.fz + right.z * mv.fx);
    if (mathx.lenXZ(d) > 0.01) return d;
    return mathx.headingDir(g.hero.facing);
}

/// Off the VISUAL stance blend, so he dissolves over the ~0.1 s the bow takes to come up.
const AIM_FADE: f32 = 0.0;
fn heroFade(g: *const Game) f32 {
    return mathx.lerpF(1.0, AIM_FADE, mathx.clampF(g.hero.aimB, 0, 1));
}

fn drawCasters(g: *Game, cull: envmod.Cull) void {
    g.env.drawProps(cull);
    g.chests.draw();
    g.scene.setFlash(0.6 * g.hero.hurtFlash);
    // LIT PASS ONLY — the depth pass has no alpha, and his shadow is still his.
    const fade = heroFade(g);
    const seeThrough = cull == .view and fade < 0.999;
    if (seeThrough) {
        g.scene.setFade(fade);
        rl.gl.rlDisableDepthMask();
    }
    g.hero.draw();
    if (seeThrough) {
        rl.gl.rlEnableDepthMask();
        g.scene.setFade(1);
    }
    g.scene.setFlash(0);
    inline for (FOE_GROUPS) |f| @field(g, f.field).draw(&g.scene);
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
    inline for (FOE_GROUPS) |f| @field(g, f.field).setShader(sh);
    g.chests.setShader(sh);
}

pub fn heroCenterY(g: *const Game) f32 {
    return g.hero.pos.y + HERO_CENTER_Y;
}

fn heroAimPoint(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, heroCenterY(g), g.hero.pos.z);
}

fn spawnArrow(g: *Game, from: rl.Vector3, target: rl.Vector3) void {
    poolPut(g, archermod.launchArrow(from, target));
}

pub fn spawnClump(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchClump(from, heroAimPoint(g), koboldmod.CLUMP_SPEED, koboldmod.CLUMP_HIT));
}

pub fn spawnVenom(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchVenom(from, heroAimPoint(g), broodmod.SPIT_SPEED, broodmod.M_SPIT_HIT));
}

fn rehomeChests(g: *Game) void {
    var sites: [chestmod.CAP]chestmod.Site = undefined;
    const n = g.env.chestSites(&sites);
    g.chests.reset(sites[0..n]);
    var fires: [restmod.CAP]restmod.Site = undefined;
    g.rest.reset(fires[0..g.env.restSites(&fires)]);
}

pub fn rehomeChestsForShot(g: *Game) void {
    rehomeChests(g);
}

/// EMPTY THE FIELD — through each group's own `clear()` where it has one, because zeroing `n` leaves everything a group owns BESIDES its members (the brood's sacs and acid) standing on the ground.
fn clearFoes(g: *Game) void {
    inline for (FOE_GROUPS) |f| {
        const G = @FieldType(Game, f.field);
        if (comptime @hasDecl(G, "clear")) @field(g, f.field).clear() else @field(g, f.field).n = 0;
    }
}

/// …and put it back FROM THE MAP — both off FOE_GROUPS.
pub fn clearFoesForShot(g: *Game) void {
    clearFoes(g);
}
pub fn rehomeFoesForShot(g: *Game) void {
    rehomeFoes(g);
}

/// …and the BOW's three, so the harness flies a real shaft rather than parking a mesh in the air.
pub fn shootShaftForShot(g: *Game, at: rl.Vector3, kind: combat.ArrowKind) void {
    const blow = heromod.arrowBlow(kind, true);
    putIn(&g.shafts, archermod.launchShaft(g.hero.nockWorld(), at, heromod.BOW_AIMED_SPEED, blow, false, heromod.arrowShot(kind)));
}
pub fn stepShaftsForShot(g: *Game, dt: f32) void {
    stepShafts(g, dt);
}
/// Where something in flight actually IS — a crop of a burning head or a slung clump has to be aimed at it, not guessed. Both quivers, because the hero's shafts are in one and everything thrown AT him is in the other.
pub fn flyingPointForShot(g: *Game, kind: archermod.Shot) ?rl.Vector3 {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (ar.live and ar.shot == kind) return ar.pos;
        }
    }
    return null;
}

/// One frame of flight for everything thrown AT him — the harness's own hook, since the game does this inline.
pub fn stepArrowsForShot(g: *Game, dt: f32) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) continue;
        ar.hit = false;
        archermod.stepArrow(ar, g.hero.pos, heroCenterY(g), g.env.groundAt(ar.pos.x, ar.pos.z), g.hero.iFramed(), arrowCover(g, ar, dt), dt);
    }
}
pub fn clearShaftsForShot(g: *Game) void {
    clearQuivers(g);
}

pub fn beginRestForShot(g: *Game) void {
    g.rest.look(g.hero.pos);
    _ = g.rest.begin();
}
pub fn tickRestForShot(g: *Game, dt: f32) void {
    tickRest(g, dt);
}
pub fn endRestForShot(g: *Game) void {
    g.rest = .{};
    g.retro.values = g.restRetro;
    g.hero.sit(false, g.hero.pos, g.hero.facing);
    sfx.restFireOn(false);
    var fires: [restmod.CAP]restmod.Site = undefined;
    g.rest.reset(fires[0..g.env.restSites(&fires)]);
    rehomeFoes(g);
}
pub fn openChestForShot(g: *Game) bool {
    const had = g.chests.near != null;
    interact(g);
    return had;
}

fn interact(g: *Game) void {
    if (g.rest.begin()) return; // a bonfire beats a chest — you cannot be in reach of both
    const got = g.chests.openNear(&g.map) orelse return;
    for (got.loot) |it| g.bag.add(it, 1);
    if (got.loot.len > 0) sfx.world(.item_get, got.at);
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

fn tickRest(g: *Game, dt: f32) void {
    g.rest.update(dt);
    if (g.rest.justEntered) {
        clearFoes(g);
        clearQuivers(g);
        g.lock = null;
        // THE PLAYER'S OWN FILTERS STAY (owner: keep our normal retro filters here, amp up warmth only).
        g.restRetro = g.retro.values;
        g.retro.values[gfx.RF_SEPIA] = mathx.maxF(g.retro.values[gfx.RF_SEPIA], REST_WARMTH);
        const s = g.rest.seat();
        var at = s.pos;
        plantActor(g, &at);
        g.hero.sit(true, at, s.facing);
    }
    if (g.rest.justLeft) {
        g.retro.values = g.restRetro;
        g.hero.sit(false, g.hero.pos, g.hero.facing);
        rehomeFoes(g);
    }
    if (rl.isKeyPressed(.escape) or rl.getKeyPressed() != .null or rl.isMouseButtonPressed(.left) or
        (rl.isGamepadAvailable(PAD) and rl.getGamepadButtonPressed() != .unknown))
    {
        g.rest.leave();
    }
    if (g.rest.scene()) {
        g.hero.poseRest(dt);
        restCamera(g);
    } else {
        g.hero.pose();
    }
    g.rig.tickShake(dt);
    g.rumble.update(dt, false);
}

fn applyDim(g: *Game) void {
    const d = g.rest.dim();
    g.scene.setDim(d);
    g.sky.setDim(d);
    // …and the propped guitar goes off the rock for exactly as long as he is holding one.
    g.env.stowed = g.hero.resting;
}

const REST_WARMTH: f32 = 0.14;

/// THE REST'S CAMERA, laid out to the owner's own plan sketch: hero bonfire ^ cam ^ The lens stands PAST the fire and off to one side, so the fire is the near thing on one half of the frame and the man is the far thing on the other — and because he is looking at the fire, that puts him three-quarters on to the camera rather than in profile.
fn restCamera(g: *Game) void {
    const s = g.rest.seat();
    const axis = mathx.headingDir(s.axis); // seat → fire, which is NOT quite his facing
    const side = mathx.perpXZ(axis);
    const drift = mathx.sinf(g.hero.restT * 0.18) * 0.30;
    g.rig.cam.position = v3(
        s.pos.x + axis.x * 3.95 + side.x * (2.05 + drift),
        s.pos.y + 1.30,
        s.pos.z + axis.z * 3.95 + side.z * (2.05 + drift),
    );
    // Aimed between them and biased toward the man, so the fire sits off to one side of frame rather than dead centre with him crowded against the edge.
    g.rig.cam.target = v3(s.pos.x + axis.x * 0.90, s.pos.y + 0.60, s.pos.z + axis.z * 0.90);
    g.rig.cam.up = v3(0, 1, 0);
}

fn poolPut(g: *Game, a: archermod.Arrow) void {
    putIn(&g.arrows, a);
}

fn putIn(pool: []archermod.Arrow, a: archermod.Arrow) void {
    for (pool) |*ar| {
        if (!ar.live) {
            ar.* = a;
            return;
        }
    }
    pool[0] = a;
}

fn looseShaft(g: *Game) void {
    const aimed = g.hero.shotAimed;
    const from = g.hero.nockWorld();
    const locked: ?rl.Vector3 = if (aimed) null else if (activeLock(g)) |li| foeLockPoint(g, li) else null;
    const target = locked orelse if (aimed) camAimPoint(g) else forwardAimPoint(g);
    const loft = locked != null or aimed;
    const speed: f32 = if (aimed) heromod.BOW_AIMED_SPEED else heromod.BOW_QUICK_SPEED;
    // The blow AND the shaft that carries it both come off what he actually drew (see `Hero.shotArrow`).
    putIn(&g.shafts, archermod.launchShaft(from, target, speed, g.hero.shotBlow(), loft, g.hero.shotShaft()));
    sfx.play(.bow_loose);
    g.rumble.play(rumblemod.swing_light); // the string going is a tick in the grip, not a swing
}

/// A point ON the camera's centre ray, at the distance the ray REACHES.
fn camAimPoint(g: *const Game) rl.Vector3 {
    const ray = g.rig.centreRay();
    var reach = heromod.BOW_AIM_REACH;
    if (rayFoeDist(g, ray.origin, ray.dir)) |d| {
        reach = d;
    } else if (g.env.rayGround(ray.origin, ray.dir)) |hitPoint| {
        // …else the ground it would land on, so a shot at the earth in front of you lands there.
        reach = mathx.minF(reach, mathx.lenV(mathx.subV(hitPoint, ray.origin)));
    }
    // Never converge INSIDE him: a target closer than the bow is a shaft aimed backwards.
    reach = mathx.maxF(reach, AIM_CONVERGE_MIN);
    return mathx.addV(ray.origin, mathx.scaleV(ray.dir, reach));
}

const AIM_CONVERGE_MIN: f32 = 3.0;

/// Nearest live target along `dir`, or null.
const RayCtx = struct {
    origin: rl.Vector3,
    dir: rl.Vector3,
    best: ?f32 = null,

    fn visit(self: *RayCtx, foes: anytype, _: ?FoeKind) void {
        for (foes) |*f| {
            if (!f.alive() or f.dying()) continue;
            const oc = mathx.subV(f.centerWorld(), self.origin);
            const along = oc.x * self.dir.x + oc.y * self.dir.y + oc.z * self.dir.z;
            if (along <= 0) continue; // behind the eye
            const r = f.hurtRadius();
            // The perpendicular gap, SQUARED throughout — `lenV(oc)*lenV(oc)` took two square roots to arrive back at the dot product it started from.
            const oc2 = oc.x * oc.x + oc.y * oc.y + oc.z * oc.z;
            if (oc2 - along * along > r * r) continue; // the ray misses it
            if (self.best == null or along < self.best.?) self.best = along;
        }
    }
};

fn rayFoeDist(g: *const Game, origin: rl.Vector3, dir: rl.Vector3) ?f32 {
    var ctx = RayCtx{ .origin = origin, .dir = dir };
    eachTarget(g, &ctx, RayCtx.visit);
    return ctx.best;
}

fn forwardAimPoint(g: *const Game) rl.Vector3 {
    const d = mathx.headingDir(g.hero.facing);
    const from = v3(g.hero.pos.x, heroCenterY(g), g.hero.pos.z);
    return mathx.addV(from, mathx.scaleV(d, heromod.BOW_AIM_REACH));
}

fn stepShafts(g: *Game, dt: f32) void {
    for (&g.shafts) |*ar| {
        if (!ar.live) continue;
        const seg = archermod.stepShaft(ar, g.env.groundAt(ar.pos.x, ar.pos.z), arrowCover(g, ar, dt), dt) orelse {
            // It STOPPED this frame — into cover or into the earth, and that gets the surface's own voice.
            if (ar.stuck and ar.age == 0) sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
            continue;
        };
        const blade = foemod.Blade{
            .active = true,
            .pierce = true,
            .r = archermod.SHAFT_R,
            .a = seg[0],
            .b = seg[1],
            .a0 = seg[0],
            .b0 = seg[1],
            .hit = ar.blow,
        };
        if (!pierceFoes(g, blade)) continue;
        archermod.plantShaft(ar); // spent on the first thing it reached — stands in it and fades
        sfx.world(.arrow_hit, ar.pos);
        g.rumble.play(rumblemod.hit_light);
        g.rig.addShake(SHAKE_HIT_LIGHT);
    }
}

fn pierceFoes(g: *Game, blade: foemod.Blade) bool {
    var hit = false;
    inline for (FOE_GROUPS) |f| {
        if (!hit and @field(g, f.field).pierce(blade)) hit = true;
    }
    return hit;
}

const ARROW_QUERY_PAD: f32 = 1.5;
var arrow_cover_buf: [envmod.MAX_NEAR]collision.Solid = undefined;
pub fn arrowCover(g: *const Game, ar: *const archermod.Arrow, dt: f32) []const collision.Solid {
    return g.env.nearSolids(ar.pos, mathx.lenV(ar.vel) * dt + ARROW_QUERY_PAD, &arrow_cover_buf);
}

fn quivers(g: *Game) [2][]archermod.Arrow {
    return .{ &g.arrows, &g.shafts };
}

/// WHAT A LANDED PROJECTILE LEAVES BEHIND, asked in ONE place because the two callers (it reached him /
/// it reached anything else) were already drifting apart: the acid glob pours a POOL, the sling's clump
/// throws EMBERS, and a shaft leaves only itself.
fn splashOf(g: *Game, ar: *const archermod.Arrow) void {
    const ground = v3(ar.pos.x, g.env.groundAt(ar.pos.x, ar.pos.z), ar.pos.z);
    switch (ar.shot) {
        .venom => g.brood.splash(ground),
        .clump => g.band.splash(ar.pos), // at the CONTACT, not the floor: it can burst against a chest
        .arrow, .firearrow => {},
    }
}

fn drawArrows(g: *Game) void {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (!ar.live) continue;
            const m = switch (ar.shot) {
                .arrow => &g.arrowModel,
                .clump => &g.clumpModel,
                .venom => &g.venomModel,
                .firearrow => &g.fireArrowModel,
            };
            rl.drawMesh(m.meshes[0], m.materials[0], archermod.arrowXform(ar));
        }
    }
}

fn clearQuivers(g: *Game) void {
    for (quivers(g)) |pool| {
        for (pool) |*ar| ar.* = .{};
    }
}

fn sceneCam(g: *const Game) rl.Camera3D {
    return if (g.editor.on) g.editor.cam else g.rig.cam;
}

fn sunFocus(g: *const Game) rl.Vector3 {
    if (!g.editor.on) return g.hero.pos;
    const t = g.editor.cam.target;
    return v3(t.x, g.env.groundAt(t.x, t.z), t.z);
}

pub fn drawScene(g: *Game) void {
    g.env.resetStats(); // culling counters for the debug overlay, both passes together
    applyDim(g); // before the depth pass: the uniform is read by every draw below it
    const cam = sceneCam(g);
    // WHAT STANDS BETWEEN THE LENS AND HIM, before either pass, since the marks are read by the draw
    // loop both of them go through. In the editor the line is degenerate on purpose — see markOccluders.
    g.env.markOccluders(cam.position, if (g.editor.on) cam.position else heroAimPoint(g), g.drawDt);
    const focus = sunFocus(g);
    g.scene.beginShadowPass(focus);
    setCasterShaders(g, g.scene.depthShader);
    drawCasters(g, .{ .sun = focus });
    setCasterShaders(g, g.scene.shader);
    g.scene.endShadowPass();

    rl.beginDrawing();
    const filtered = if (g.editor.on) false else g.retro.begin();
    rl.clearBackground(CLEAR);
    g.sky.draw(cam);

    const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
    const view = envmod.View.fromCamera(cam, aspect);

    rl.beginMode3D(cam);
    g.scene.bind(cam.position);
    g.env.uploadLights(&g.scene, &view, @floatCast(rl.getTime()));
    g.scene.setGround(true);
    g.env.drawGround(&view); // sculpted terrain is tiled, so it culls against the same frustum
    g.scene.setGround(false);
    g.env.drawWater();
    if (g.menu.wireframe) rl.gl.rlEnableWireMode();
    drawCasters(g, .{ .view = view });
    g.scene.setWind(true);
    g.env.drawFlora(&view);
    g.scene.setWind(false);
    drawArrows(g); // in-flight + stuck arrows (lit, rigid, non-casting)
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
    g.env.drawVeils(&view);
    // Unlit spheres over the opaque geometry.
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "drawFx")) @field(g, f.field).drawFx();
    }
    g.hero.drawTrail();
    for (quivers(g)) |pool| archermod.drawArrowTrails(pool);
    if (g.menu.hitboxes and g.hero.attacking) {
        const col = if (g.hero.hitActive()) rl.Color.red else mathx.withAlpha(rl.Color.red, 90);
        rl.drawCapsuleWires(g.hero.bladeA, g.hero.bladeB, heromod.BLADE_R, 6, 3, col);
    }
    if (g.menu.hitboxes) {
        inline for (FOE_GROUPS) |gr| {
            for (@field(g, gr.field).live()) |*f| {
                if (!f.alive()) continue;
                const col = if (f.flash > 0) rl.Color.orange else mathx.withAlpha(rl.Color.yellow, 80);
                rl.drawSphereWires(f.centerWorld(), f.hurtRadius(), 8, 10, col);
            }
        }
    }
    if (g.editor.on) g.editor.draw3D(&g.map, &g.env);
    rl.endMode3D();

    if (filtered) g.retro.end();
    if (g.editor.on) return;
    g.vignette.draw(); // the vignette darkens the corners the chrome lives in
    drawRestFade(g);
    drawHurtFlash(g); // red screen-edge pulse when the hero is hit (peripheral feedback)
    drawFoeBars(g);
    drawLockDot(g); // the ER lock-on reticle
    drawDeathOverlay(g); // the YOU DIED card + respawn fade, over everything
}

fn drawRestFade(g: *Game) void {
    const a = g.rest.fade();
    if (a <= 0.004) return;
    rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), rgba(0, 0, 0, mathx.u8f(255.0 * a)));
}

fn drawDeathOverlay(g: *Game) void {
    const w = rl.getScreenWidth();
    const h = rl.getScreenHeight();
    const wf: f32 = @floatFromInt(w);
    const hf: f32 = @floatFromInt(h);
    if (g.hero.dead) {
        const u = mathx.clampF(g.hero.deathT / heromod.DEATH_DUR, 0, 1);
        const dim = mathx.smoothstep(0.03, 0.30, u);
        rl.drawRectangle(0, 0, w, h, rgba(6, 3, 3, mathx.u8f(120.0 * dim))); // the world falls away
        const bandK = mathx.smoothstep(0.10, 0.34, u);
        const bh: i32 = @intFromFloat(0.30 * hf);
        const by: i32 = @intFromFloat(0.35 * hf);
        const third = @divTrunc(bh, 3);
        const bcol = rgba(0, 0, 0, mathx.u8f(170.0 * bandK));
        const bclear = rgba(0, 0, 0, 0);
        rl.drawRectangleGradientV(0, by, w, third, bclear, bcol); // feathered band edges
        rl.drawRectangle(0, by + third, w, bh - 2 * third, bcol);
        rl.drawRectangleGradientV(0, by + bh - third, w, third, bcol, bclear);
        const ta = mathx.pulse(u, 0.16, 0.48, 0.90, 1.0);
        if (ta > 0.01) {
            const size = 0.115 * hf * (0.97 + 0.06 * u); // the letters swell, barely
            const spacing = 0.22 * size; // ER's wide tracking (between glyphs only — measured exactly)
            const cx = 0.5 * wf;
            const cy = 0.35 * hf + 0.15 * hf; // band centre
            const glow = rgba(120, 14, 10, mathx.u8f(44.0 * ta));
            hud_.bigCentered("YOU DIED", cx - 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx + 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy - 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy + 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy, size, spacing, rgba(156, 22, 16, mathx.u8f(232.0 * ta)));
        }
        // …reaching FULL black a little BEFORE the respawn rather than on the same frame, so the hold starts while the card is still up and the cut itself is buried inside it.
        const blackK = mathx.smoothstep(0.82, 0.94, u);
        if (blackK > 0.001) rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * blackK)));
    } else if (g.deathFade > 0) {
        const k = if (g.deathFade > RESPAWN_FADE) 1.0 else mathx.clampF(g.deathFade / RESPAWN_FADE, 0, 1);
        rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * k))); // wake at the bonfire
    }
}

fn drawHurtFlash(g: *Game) void {
    const f = g.hero.hurtFlash;
    if (f <= 0.001) return;
    const w = rl.getScreenWidth();
    const h = rl.getScreenHeight();
    const t: i32 = @intFromFloat(0.16 * @as(f32, @floatFromInt(h))); // edge band thickness
    const edge = rgba(150, 20, 16, mathx.u8f(f * 150));
    const clear = rgba(150, 20, 16, 0);
    rl.drawRectangle(0, 0, w, h, rgba(150, 18, 14, mathx.u8f(f * 26))); // faint full-screen wash
    rl.drawRectangleGradientV(0, 0, w, t, edge, clear); // top
    rl.drawRectangleGradientV(0, h - t, w, t, clear, edge); // bottom
    rl.drawRectangleGradientH(0, 0, t, h, edge, clear); // left
    rl.drawRectangleGradientH(w - t, 0, t, h, clear, edge); // right
}

pub fn hud(g: *Game, dt: f32) void {
    if (g.rest.active()) return;
    if (!g.menu.isOpen() and !g.hero.dead) {
        hud_.vitals(dt, g.hero.vit.hpFrac(), g.hero.fp.frac(), g.hero.stam.frac(), g.hero.stamRefused / combat.STAM_REFUSE_FLASH, g.hero.stam.windedTo());
        const bowUp = g.hero.bowOut();
        hud_.equipment(
            if (bowUp) .empty else .shield,
            if (bowUp) .bow else .sword,
            switch (g.hero.flasks.sel) {
                .crimson => hud_.FlaskTint.crimson,
                .cerulean => hud_.FlaskTint.cerulean,
            },
            g.hero.flasks.ready(),
            if (bowUp) hud_.Ammo{ .n = g.hero.quiver.ready(), .fire = heromod.arrowBurns(g.hero.quiver.sel) } else null,
        );
        hud_.reticle(g.hero.aimB);
        hud_.runes(g.hero.runes.display()); // the ROLLING value, not the banked total
        if (g.rest.near != null) hud_.prompt("E / A  Rest") else if (g.chests.near != null) hud_.prompt("E / A  Open");
    }
    if (g.menu.stats) debugCorner(g);
}

const DBG_ROW = 200;

fn debugCorner(g: *Game) void {
    // ASCII only — the Balthazar atlas is the default (ASCII) glyph set, so a "·" or "—" is tofu.
    var buf: [DBG_ROW]u8 = undefined;
    const step = hud_.lineH(hud_.SMALL);
    var y: i32 = 18;

    const label: [:0]const u8 = if (g.hero.dead)
        "dead"
    else if (g.hero.staggered())
        (if (g.hero.stun == .heavy) "staggered" else "stunned")
    else if (g.hero.rolling)
        "rolling"
    else if (g.hero.attacking)
        (if (g.hero.atkHeavy) "striking" else "slashing")
    else if (g.hero.shooting)
        (if (g.hero.shotAimed) "loosing" else "snapshot")
    else if (g.hero.aiming)
        "aiming"
    else
        gaitLabel(g.hero.moving, g.hero.speed);
    dbgRow(std.fmt.bufPrintZ(&buf, "{s}   {d:.1} m/s", .{ label, g.hero.speed }) catch "", y, hud_.BODY, rgba(150, 156, 164, 255));
    y += hud_.lineH(hud_.BODY) + 4;

    dbgRow(std.fmt.bufPrintZ(&buf, "{d} fps   {d:.1} ms   pos {d:.1},{d:.1}  y {d:.2}  slope {d:.0}deg  lean {d:.0}   yaw {d:.2}   pitch {d:.2}   time x{d:.2}", .{
        rl.getFPS(),
        rl.getFrameTime() * 1000.0,
        g.hero.pos.x,
        g.hero.pos.z,
        g.hero.pos.y,
        mathx.degrees(std.math.atan(g.env.slopeAt(g.hero.pos.x, g.hero.pos.z))),
        g.hero.slopePitch,
        g.rig.yaw,
        g.rig.pitch,
        g.menu.timeScale,
    }) catch "", y, hud_.SMALL, rgba(170, 190, 150, 255));
    y += step;

    const h = &g.hero;
    const foesLeft = allAlive(g);
    const foeHits = allHits(g);
    dbgRow(std.fmt.bufPrintZ(&buf, "hero  hp {d:.0}/{d:.0}  poise {d:.0}/{d:.0}  stance {d:.0}/{d:.0}  stam {d:.0}/{d:.0}   foes {d} left  hits {d}", .{
        h.vit.hp,   h.vit.hpMax, h.vit.poise, h.vit.poiseMax, h.vit.stance, h.vit.stanceMax,
        h.stam.cur, h.stam.max,  foesLeft,    foeHits,
    }) catch "", y, hud_.SMALL, rgba(150, 180, 190, 255));
    y += step;

    // THE ARROW ON THE STRING, and — while something is locked — WHAT IT WOULD LAND ON. The four
    // resistances are only legible against a named target, so the row reads the lock rather than the hero
    // (nothing grants HIM any: there is no gear yet).
    const sel = h.quiver.sel;
    const rider: [:0]const u8 = if (sel == .fire) "  +fire" else "";
    if (g.lock) |li| {
        const r = foeResists(g, li);
        dbgRow(std.fmt.bufPrintZ(&buf, "arrow  {s} {d}/{d}{s}   lock res  fire {d:.0}  cold {d:.0}  lgt {d:.0}  chaos {d:.0}", .{
            @tagName(sel), h.quiver.ready(), combat.Quiver.cap(sel), rider,
            r.raw(.fire),  r.raw(.cold),     r.raw(.lightning),      r.raw(.chaos),
        }) catch "", y, hud_.SMALL, STAT_WARN);
    } else {
        dbgRow(std.fmt.bufPrintZ(&buf, "arrow  {s} {d}/{d}{s}", .{
            @tagName(sel), h.quiver.ready(), combat.Quiver.cap(sel), rider,
        }) catch "", y, hud_.SMALL, STAT_WARN);
    }
    y += step;

    dbgRow(std.fmt.bufPrintZ(&buf, "world  props {d}  solids {d}  fires {d}   drawn {d} in {d} cells (both passes)", .{
        g.env.propCount(), g.env.solidCount(), g.env.lightCount(), g.env.stat_draws, g.env.stat_cells,
    }) catch "", y, hud_.SMALL, rgba(150, 175, 195, 255));
    y += step;

    dbgRow(std.fmt.bufPrintZ(&buf, "look  {s}   mouse {d:.1},{d:.1}   stick {d:.3},{d:.3}   mag {d:.3}   dyaw {d:.2}", .{
        if (g.probe.pad) "PAD" else "MOUSE",
        g.probe.mdx,
        g.probe.mdy,
        g.probe.rx,
        g.probe.ry,
        g.probe.mag,
        g.probe.dyaw,
    }) catch "", y, hud_.SMALL, rgba(196, 170, 130, 255));
}

fn dbgRow(s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    hud_.textRight(s, hud_.MARGIN, y, size, col);
}

const GAIT_SLACK: f32 = 0.3;
const Gait = enum { walk, run, sprint };
fn gaitOf(speed: f32) Gait {
    if (speed >= SPRINT_SPEED - GAIT_SLACK) return .sprint;
    if (speed >= RUN_SPEED - GAIT_SLACK) return .run;
    return .walk;
}

fn gaitLabel(moving: f32, speed: f32) [:0]const u8 {
    if (moving < 0.5) return "idle";
    return switch (gaitOf(speed)) {
        .sprint => "sprinting",
        .run => "running",
        .walk => "walking",
    };
}

/// How the process runs: the game, or one of the two headless capture modes in `shots.zig`.
pub const Mode = enum { play, shots, props };

pub fn run(mode: Mode) void {
    const shot = mode != .play;
    // VSYNC is why fullscreen was tearing. setTargetFPS is a CPU-side frame LIMITER — it paces how often we draw but never tells the driver to swap during vblank, so the swap lands mid-scan and the seam shows.
    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true, .window_hidden = shot, .window_resizable = true });
    rl.initWindow(SCREEN_W, SCREEN_H, "zig-soulslike");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    // No setTargetFPS alongside vsync: the two limiters fight on any display that isn't 60 Hz (vsync paces to the refresh, then raylib's own busy-wait throttles on top, which reads as judder).

    hud_.init();
    defer hud_.deinit();

    // NO AUDIO UNDER --shot.
    if (!shot) sfx.init();
    defer if (!shot) sfx.deinit();
    defer objviewmod.unload();

    const alloc = std.heap.c_allocator;
    const g = alloc.create(Game) catch return;
    defer alloc.destroy(g);
    g.init();

    rl.gl.rlSetClipPlanes(CLIP_NEAR, CLIP_FAR);

    if (mode == .shots) {
        @import("shots.zig").runShots(g);
        return;
    }
    if (mode == .props) {
        @import("shots.zig").runPropShots(g);
        return;
    }

    rl.hideCursor();
    var wasInside = false;
    var bWasDown = false; // gamepad Circle/B: a TAP rolls, a HOLD sprints
    var bHeldT: f32 = 0;
    var lockCycleReady = true; // debounce so one flick cycles the lock-on target once
    var lookPad = false;
    // Rising-edge trackers for rumble: pulse the frame an action BEGINS.
    var wasRolls: u32 = 0;
    var wasSwings: u32 = 0;
    var wasDead = false;
    var wasRefused: f32 = 0;
    var wasAiming = false;
    var wasStun: combat.StunKind = .none;
    var lastPhase: f32 = 0.75;
    defer g.rumble.stop(); // never leave a motor latched after we exit the loop
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime(); // wall-clock dt: feel systems (shake, rumble, fades, tap windows)
        const dt = rawDt * g.menu.timeScale;
        g.drawDt = rawDt; // …including the occluder fade, which every branch below draws through
        PLAY_HALF = g.map.half - envmod.PLAY_INSET;
        // THE WORLD GOES QUIET IN THE EDITOR.
        sfx.mute(g.editor.on and !g.editor.auditioning());

        // Pad SELECT opens the GAME menu, pad START the CHARACTER one; TAB is START's keyboard twin.
        if (!g.editor.on and !g.rest.active()) {
            if (rl.isKeyPressed(.escape)) g.menu.onEscape();
            if (rl.isKeyPressed(.tab)) g.menu.onStartButton();
            if (rl.isGamepadAvailable(PAD)) {
                if (rl.isGamepadButtonPressed(PAD, .middle_left)) g.menu.onSelectButton();
                if (rl.isGamepadButtonPressed(PAD, .middle_right)) g.menu.onStartButton();
            }
        }

        if (rl.isKeyPressed(.enter) and (rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt))) {
            rl.toggleBorderlessWindowed();
            g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());
        }
        if (rl.isWindowResized()) g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());

        if (g.editor.on) {
            // THE CURSOR COMES BACK.
            rl.showCursor();
            switch (g.editor.update(&g.map, &g.env, rawDt)) {
                .none => {},
                .leave => {
                    // The last edit's rebuild may still be inside its quiet window, and nothing is going
                    // to draw the editor again to service it.
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    g.menu.screen = .main;
                    rl.hideCursor(); // back to the gameplay rule: the mouse IS the camera
                },
                .playtest => {
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    rl.hideCursor();
                    g.hero.pos = mathx.ground(g.editor.cam.target.x, g.editor.cam.target.z);
                    g.hero.pos = g.env.resolveActor(g.hero.pos, HERO_R);
                    plantActor(g, &g.hero.pos);
                    g.hero.setSpawn(g.hero.pos, g.hero.facing);
                    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
                    wasInside = false; // swallow the mouse delta the editor's look accumulated
                },
            }
            g.hero.held = true;
            // …and the shield comes DOWN.
            g.hero.setGuard(false);
            g.hero.pose();
            // Re-home the foes from the map every frame the editor is up, so moving a spawn moves the thing you can SEE.
            rehomeFoes(g);
            rehomeChests(g);
            g.rumble.update(rawDt, false);
            drawScene(g);
            editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, rawDt);
            rl.endDrawing();
            continue;
        }

        g.hero.held = g.menu.isOpen();
        if (g.menu.isOpen()) {
            switch (g.menu.update(&g.retro, rawDt, &g.bag)) {
                .quit => break,
                .editor => {
                    // Drop the lock on the way in: the reticle rides a FoeRef into groups the editor re-homes from the map every frame, so a held lock survives into a world where its index means something else.
                    g.lock = null;
                    g.editor.enter(g.hero.pos);
                },
                // AN ITEM USED FROM THE BAG.
                .use => |k| useItem(g, k),
                .none => {},
            }
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false; // swallow the mouse delta accumulated while in the menu
            g.hero.update(rawDt, 0, 0, null);
            g.hero.pose();
            g.rig.tickShake(rawDt); // any live shake decays out under the pause
            g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false); // motors silent while paused (envelopes still decay)
            // THE WIND KEEPS BLOWING UNDER THE PAUSE CARD.
            sfx.ambience(rawDt);
            drawScene(g);
            hud(g, rawDt);
            g.menu.draw(&g.retro, &g.bag, &g.hero.sheet, &g.hero.vit.res);
            rl.endDrawing();
            continue;
        }

        // own camera.
        if (g.rest.active()) {
            tickRest(g, rawDt);
            bWasDown = true; // poison the pad-B tap window, exactly as the menu branch does
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            hud(g, rawDt);
            rl.endDrawing();
            continue;
        }
        g.rest.update(rawDt);
        g.rest.look(g.hero.pos);
        sfx.tickStreams();

        const lockPressed = !g.hero.aiming and (rl.isMouseButtonPressed(.middle) or
            (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .right_thumb)));
        if (lockPressed) {
            if (g.lock != null) {
                g.lock = null;
            } else {
                g.lock = acquireLock(g);
                if (g.lock == null and rl.isGamepadAvailable(PAD)) g.rig.recenter(g.hero.facing);
            }
        }
        if (g.lock) |li| {
            if (!lockValid(g, li)) g.lock = null; // target wandered out of range
        }

        // Camera look.
        const inside = rl.isWindowFocused() and rl.isCursorOnScreen();
        const md = rl.getMouseDelta();
        const wheel = rl.getMouseWheelMove();
        const padRX: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_x) else @as(f32, 0);
        const padRY: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_y) else @as(f32, 0);
        // The yaw BEFORE any look input lands, so the probe can report what the camera actually turned this frame rather than what the devices claimed.
        const yawBefore = g.rig.yaw;
        // RAW stick magnitude, before any deadzone.
        const padMag = @sqrt(padRX * padRX + padRY * padRY);
        // …and the whole look SLOWS as the bow comes up, eased on the same blend the view rides in on.
        const lookScale = mathx.lerpF(1.0, AIM_LOOK_SCALE, mathx.clampF(g.rig.aimB, 0, 1));
        if (activeLock(g)) |li| {
            const dir = mathx.dirXZ(g.hero.pos, foePos(g, li));
            if (mathx.lenXZ(dir) > 0.001) {
                g.rig.aim(mathx.headingXZ(dir), LOCK_PITCH, dt, LOCK_CAM_EASE); // quick, snap-free swing
            }
            var flick: f32 = 0;
            if (inside and wasInside and @abs(md.x) > 40) flick = std.math.sign(md.x);
            if (@abs(padRX) > LOCK_FLICK) flick = std.math.sign(padRX);
            if (flick != 0 and lockCycleReady) {
                cycleLock(g, flick);
                lockCycleReady = false;
            } else if (@abs(md.x) < 12 and @abs(padRX) < 0.3) {
                lockCycleReady = true;
            }
        } else {
            // mouse-emulation layer puts a stick on the OS cursor, and a resting deflection on one device must not add to the other.
            const look = stickRadial(padRX, padRY, LOOK_DEADZONE, LOOK_CURVE);
            const mouseLook = inside and wasInside and (@abs(md.x) + @abs(md.y)) > MOUSE_WAKE;
            // at 0.15-0.25, past LOOK_DEADZONE, so claiming on anything that merely clears the deadzone pins the latch to PAD on frame one and the mouse never works again.
            const padClaim = padMag > LOOK_CLAIM;
            // …and LAST DEVICE WINS has to be resolved as a TIE, not by statement order.
            if (padClaim and !mouseLook) lookPad = true;
            if (mouseLook and !padClaim) lookPad = false;
            if (lookPad) {
                g.rig.orbit(
                    -look.x * look.mag * LOOK_RATE_YAW * lookScale * rawDt,
                    look.y * look.mag * LOOK_RATE_PITCH * lookScale * rawDt,
                );
            } else if (inside and wasInside) {
                g.rig.rotate(md.x * lookScale, md.y * lookScale);
            }
        }
        g.probe = .{
            .mdx = md.x,
            .mdy = md.y,
            .rx = padRX,
            .ry = padRY,
            // …the RAW magnitude, not the unlocked path's local copy of it.
            .mag = padMag,
            // Wrapped: yaw lives in (−pi, pi] so a turn across the seam is a small delta, not a full circle.
            .dyaw = mathx.degrees(mathx.wrapPi(g.rig.yaw - yawBefore)),
            .pad = lookPad,
        };
        wasInside = inside;
        if (wheel != 0) g.rig.zoom(wheel);

        // D-PAD RIGHT / Q: cycle the right-hand armament.
        var swapReq = rl.isKeyPressed(.q);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .left_face_right)) swapReq = true;
        if (swapReq and g.hero.swapArm()) sfx.play(.flask_cycle); // the same D-pad click the flask gets

        var drinkReq = rl.isKeyPressed(.r);
        var cycleReq = rl.isKeyPressed(.t);
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .right_face_left)) drinkReq = true;
            if (rl.isGamepadButtonPressed(PAD, .left_face_down)) cycleReq = true;
        }
        if (cycleReq and !g.hero.dead) {
            g.hero.cycleFlask();
            sfx.play(.flask_cycle);
        }

        // D-PAD UP / Y: cycle the ARROW — plain or fire. Up because it is the cross's one empty slot,
        // and it mirrors D-pad Down cycling the quick item.
        var arrowReq = rl.isKeyPressed(.y);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .left_face_up)) arrowReq = true;
        if (arrowReq and g.hero.cycleArrow()) sfx.play(.flask_cycle);

        // free face button and the one every soulslike puts this on.
        var useReq = rl.isKeyPressed(.e);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .right_face_down)) useReq = true;
        if (useReq and !g.hero.dead) interact(g);

        // Dodge roll: Space, or a short TAP of Circle/B (holding B sprints instead).
        var rollReq = rl.isKeyPressed(.space);
        const bDown = rl.isGamepadAvailable(PAD) and rl.isGamepadButtonDown(PAD, .right_face_right);
        if (bDown) {
            bHeldT += rawDt; // REAL time: tap-vs-hold is a wall-clock decision, unaffected by debug time-scale
        } else {
            if (bWasDown and bHeldT < ROLL_TAP_MAX) rollReq = true;
            bHeldT = 0;
        }
        bWasDown = bDown;

        // default for the left hand.
        var guardHeld = rl.isMouseButtonDown(.right);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonDown(PAD, .left_trigger_1)) guardHeld = true;

        var aimHeld = rl.isMouseButtonDown(.right);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonDown(PAD, .left_trigger_2)) aimHeld = true;

        // R1/RB or LMB, and R2/RT or Shift+LMB.
        var r1 = false;
        var r2 = false;
        if (rl.isMouseButtonPressed(.left)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) r2 = true else r1 = true;
        }
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_1)) r1 = true;
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_2)) r2 = true;
        }
        const bow = g.hero.bowOut();
        const lightReq = r1 and !bow;
        const heavyReq = r2 and !bow;
        const quickReq = r1 and bow;
        const aimedReq = r2 and bow;

        // STAMINA GATES THE SPRINT AT THE SOURCE.
        var mv = gatherMove();
        if (!g.hero.stam.canSprint()) mv.speed = @min(mv.speed, RUN_SPEED);
        const wade = wadeDrag(g);
        if (wade < 1.0) mv.speed = @min(mv.speed, WALK_SPEED * wade);
        // Poise/stance regenerate every frame (relent and pressure resets
        g.hero.vit.tick(dt);
        // …and anything he ATE drips HP back.
        g.hero.regen.tick(dt, &g.hero.vit);
        g.hero.tickFlash(dt); // fade the red damage flash
        // Action input is dead while staggered or dead (a reaction is committed).
        if (!g.hero.dead and !g.hero.staggered()) {
            if (rollReq) {
                g.hero.requestRoll(rollDir(g, mv));
            } else if (heavyReq) {
                g.hero.requestAttack(.heavy);
            } else if (lightReq) {
                g.hero.requestAttack(.light);
            } else if (aimedReq) {
                g.hero.requestShot(true);
            } else if (quickReq) {
                g.hero.requestShot(false);
            }
            g.hero.steerQueuedRoll(rollDir(g, mv));
            if (drinkReq and g.hero.startDrink()) sfx.play(.flask_drink);
        }
        // …and a DRAUGHT is not a sprint either: without it, Shift held through a flask drained the pool
        // at the sprint rate and denied him the shield for the whole shuffle, off a sprint he never got.
        g.hero.sprinting = sprintingMove(mv) and
            !g.hero.rolling and !g.hero.attacking and !g.hero.drinking and !g.hero.dead and !g.hero.staggered();
        // …and the shield, AFTER the sprint (there is no running block — see hero.setGuard).
        g.hero.setGuard(guardHeld);
        g.hero.setAim(aimHeld);
        // BEHIND THE SHIELD HE SHUFFLES.
        if (g.hero.guarding) mv.speed = @min(mv.speed, WALK_SPEED * heromod.GUARD_SPEED);
        // …AND BEHIND A RAISED BOW HE BARELY MOVES AT ALL.
        if (g.hero.aiming) mv.speed = @min(mv.speed, WALK_SPEED * heromod.BOW_AIM_SPEED);
        // …AND A DRAUGHT IS A SHUFFLE, not a stop (owner's call). Denied at the SOURCE like the other two.
        if (g.hero.drinking) mv.speed = @min(mv.speed, WALK_SPEED * heromod.DRINK_SPEED);

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        const faceYaw: ?f32 = if (g.hero.aiming) g.rig.yaw else lockYaw;
        // …AND HOW FAR DOWN (or up) THE THING HE IS SWINGING AT ACTUALLY IS.
        g.hero.aimAtPitch(meleePitch(g));
        // The slope under him, eased into the rig BEFORE it poses — every branch below ends in a `pose()`, so this has to be settled first or the lean is always one frame stale.
        leanToGround(g, dt);
        var wasPos: [FOE_GROUPS.len][FOE_CAP]rl.Vector3 = undefined;
        // …AND HOW MANY OF EACH ROW IS REAL.
        var wasN: [FOE_GROUPS.len]usize = undefined;
        inline for (FOE_GROUPS, 0..) |f, gi| {
            const row = @field(g, f.field).live();
            wasN[gi] = row.len;
            snapshotPos(row, &wasPos[gi]);
        }
        if (g.hero.dead) {
            g.hero.updateDeath(dt); // collapse → respawn
            // The frame he returns, the WORLD reloads with him (ER-style): every foe re-homed at full health, arrows cleared, lock dropped.
            if (!g.hero.dead) resetFoes(g);
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt); // reeling — wide open
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.drinking) {
            // COMMITTED, NOT PLANTED: the clock first, then the shuffle. Either way it goes through
            // `moveHero`, so the shared clocks still advance exactly ONCE this frame (see tickClocks) —
            // and on the frame the draught ends, whatever it buffered is already armed, so he takes no
            // travel rather than one stray walk step into the roll.
            g.hero.tickDrink(dt);
            moveHero(g, dt, if (g.hero.drinking) mv else .{}, faceYaw);
        } else if (g.hero.attacking) {
            g.hero.updateAttack(dt, PLAY_HALF, faceYaw);
        } else if (g.hero.shooting) {
            g.hero.updateShot(dt, faceYaw);
        } else {
            moveHero(g, dt, mv, faceYaw);
        }
        // THE SHAFT LEAVES on the one frame the loose says so.
        if (g.hero.loosed) looseShaft(g);
        const hitsBefore = allHits(g);
        // ONE snapshot of the blade for every group this frame — the hero's pose is already resolved above, so re-deriving it per group only invited the three to disagree.
        const bladeNow = heroBlade(g);
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            // The lunge carries stance damage; the chomp doesn't — split the felt blow by that.
            _ = heroTakes(g, b, b.hit.stance > 0, true);
        }
        // The lone ogre hunts, slams and side-swipes.
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= ogremod.SLAM_HIT.stance, true);
        }
        for (g.line.live()) |*a| {
            if (a.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), heroAimPoint(g));
            }
        }
        if (g.band.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnClump)) |b| {
            _ = heroTakes(g, b, b.hit.poise >= koboldmod.ZERK_HIT.poise, true);
        }
        // The skeletal warriors. Only the greatsword's diagonal carries stance, so that is the split.
        if (g.muster.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance > 0, true);
        }
        const hatchesBefore = g.brood.hatches;
        const burstsBefore = g.brood.bursts;
        if (g.brood.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnVenom)) |b| {
            _ = heroTakes(g, b, b.hit.stance > 0, true);
        }
        // THE TWO MOMENTS OF HERS THAT THE FRAME SHOULD FEEL.
        if (g.brood.hatches != hatchesBefore) {
            g.rumble.play(rumblemod.hit_heavy);
            g.rig.addShake(SHAKE_HATCH);
        }
        if (g.brood.bursts != burstsBefore) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_SAC_BURST);
        }
        // …and the floor she left.
        const burn = g.brood.burn(dt, g.hero.pos);
        if (burn > 0 and g.hero.burn(broodmod.acidPulse(burn)) == .taken) sfx.play(.acid_burn);
        g.chests.update(dt, g.hero.pos);
        inline for (FOE_GROUPS, 0..) |f, gi| gateTerrain(g, @field(g, f.field).live(), wasPos[gi][0..wasN[gi]]);
        // Arrows in flight: gentle homing + arc, then a strike lands a chomp-weight blow.
        for (&g.arrows) |*ar| {
            if (!ar.live) continue;
            ar.hit = false;
            // The GROUND under the shaft, so it plants in a hillside instead of diving through it to find y = 0 — and the hero's centre measured from HIS ground, not from the datum, or an archer shooting up a bank aims at the hero's knees.
            archermod.stepArrow(ar, g.hero.pos, heroCenterY(g), g.env.groundAt(ar.pos.x, ar.pos.z), g.hero.iFramed(), arrowCover(g, ar, dt), dt);
            if (ar.hit) {
                // It found the hero.
                const blow = foemod.Blow{
                    .hit = ar.blow,
                    .from = mathx.addV(g.hero.pos, mathx.scaleV(ar.vel, -1)),
                };
                // The BEAT is skipped on a corpse.
                const out: combat.HitOutcome = if (g.hero.dead) .ignored else heroTakes(g, blow, false, false);
                // …and WHAT IT STRUCK picks that voice: boards if the shield caught it, flesh if not.
                if (out == .taken or out == .ignored) sfx.play(.arrow_hit);
                splashOf(g, ar);
            } else if (ar.stuck and ar.age == 0) {
                // ONLY THE GLOB IS SILENT HERE, because `brood.splash` plays its own voice. A clump keeps
                // the thunk the stone it replaced had — dropping it lost the landing its sound entirely.
                if (ar.shot != .venom) sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
                splashOf(g, ar);
            }
        }
        // Blade connected this frame (a foe's hit count climbed) → hit pulse + frame crack sized to the swing; a kill adds the thunk (via justDied, since dissipation delays the aliveCount drop).
        if (allHits(g) > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
            sfx.play(if (g.hero.atkHeavy) .hit_heavy else .hit_light);
        }
        stepShafts(g, dt);
        if (anyFoeDied(g)) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_KILL);
            // The kill beat: a THUD, and nothing else (owner's call — no bell, no jingle).
            sfx.play(.kill);
        }
        // …and the kill PAYS.
        g.hero.runes.gain(allRunes(g));
        // ER lock-on across a kill: the lock leaves a corpse the FRAME it dies (not after the death anim), snapping to the next valid target (nearest screen-centre, like a fresh acquire) or dropping if none.
        if (g.lock) |li| {
            if (!foeLockable(g, li)) g.lock = acquireLock(g); // corpse the frame it dies → switch/drop
        }
        collideActors(g, dt);
        groundActor(g, &g.hero.pos, dt);
        inline for (FOE_GROUPS) |f| {
            for (@field(g, f.field).live()) |*a| groundActor(g, &a.pos, dt);
        }
        g.rig.tickShake(rawDt); // impact shake decays on wall-clock time (bakes this frame's jitter)
        // THE AIM PULLS THE EYE IN PAST HIM, off the hero's own stance blend — a VISUAL read of a visual, and set before the follow so the boom this frame is already the aim's (see camera.boom).
        g.rig.aimB = g.hero.aimB;
        g.rig.followClear(g.hero.shoulderPoint(), &g.env, envGroundAt);
        sfx.listen(g.rig.cam.position, g.rig.rightXZ());
        sfx.ambience(rawDt); // keep the wind bed alive, and let the odd bird call over it
        footsteps(g, &lastPhase);

        // Rising-edge action pulses: roll whump, swing effort (heavy > light), death swell.
        if (g.hero.rolls != wasRolls) {
            g.rumble.play(rumblemod.roll);
            sfx.play(.roll);
            wasRolls = g.hero.rolls;
        }
        if (g.hero.swings != wasSwings) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.swing_heavy else rumblemod.swing_light);
            sfx.play(if (g.hero.atkHeavy) .swing_heavy else .swing_light);
            wasSwings = g.hero.swings;
        }
        if (g.hero.aiming and !wasAiming) sfx.play(.bow_draw);
        wasAiming = g.hero.aiming;
        // A REFUSED action is heard as well as seen.
        if (g.hero.stamRefused > wasRefused) sfx.play(.refused);
        wasRefused = g.hero.stamRefused;
        // The stagger is its own beat: the blow that caused it already played, this is his footing going.
        if (g.hero.stun == .heavy and wasStun != .heavy) sfx.play(.stagger);
        wasStun = g.hero.stun;
        if (g.hero.dead and !wasDead) {
            g.rumble.play(rumblemod.death);
            g.rig.addShake(SHAKE_DEATH);
            sfx.play(.death);
        }
        if (!g.hero.dead and wasDead) sfx.play(.respawn); // waking at the grace
        // The YOU DIED tail: armed while dead, drains after the respawn (fade from black).
        if (g.hero.dead) {
            g.deathFade = RESPAWN_HOLD + RESPAWN_FADE;
        } else if (g.deathFade > 0) {
            g.deathFade -= rawDt;
        }
        wasDead = g.hero.dead;
        g.rumble.update(rawDt, rl.isGamepadAvailable(PAD));

        drawScene(g);
        hud(g, rawDt);
        rl.endDrawing();
    }
}

fn footsteps(g: *Game, last: *f32) void {
    const h = &g.hero;
    if (h.moving < 0.45 or h.rolling or h.dead or h.staggered()) {
        last.* = h.phase;
        return;
    }
    const crossed = (last.* < 0.5 and h.phase >= 0.5) or (h.phase < last.*); // 0.5, or the wrap past 0
    last.* = h.phase;
    if (!crossed) return;
    const id: sfx.Id = switch (gaitOf(h.speed)) {
        .sprint => .step_sprint,
        .run => .step_hard,
        .walk => .step_soft,
    };
    const vol = mathx.clampF(0.45 + 0.55 * h.speed / SPRINT_SPEED, 0.35, 1.0);
    sfx.playAt(id, vol);
    if (stepOverlay(g, h.pos.x, h.pos.z)) |over| sfx.playAt(over, vol);
}

/// WHAT HE IS STANDING ON, as an extra voice STACKED on the boot rather than a boot of its own.
fn stepOverlay(g: *const Game, x: f32, z: f32) ?sfx.Id {
    if (g.env.inWater(x, z, 1.0)) return .step_water;
    const i = g.map.soilIndex(x, z) orelse return null;
    const v = g.map.soil[i];
    if (v >= worldfmt.Soil.N) return null;
    return switch (@as(worldfmt.Soil, @enumFromInt(v))) {
        .stone => .step_stone,
        .none, .dirt, .turf, .silt, .ash, .moss => null, // the plain boot carries all of these
    };
}

fn heroHurtBeat(g: *Game, heavy: bool, voice: bool) void {
    g.rumble.play(if (heavy) rumblemod.hurt_heavy else rumblemod.hurt);
    g.rig.addShake(if (heavy) SHAKE_HURT_HEAVY else SHAKE_HURT);
    if (voice) sfx.play(if (heavy) .hurt_heavy else .hurt);
}

fn useItem(g: *Game, k: item.Kind) void {
    if (g.hero.dead) return;
    switch (item.use(k)) {
        .none => {},
        // The POTENCY comes off the effect, so a second edible brings its own (see `item.Use`).
        .regen => |r| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.regen.start(g.hero.vit.hpMax * r.frac, r.secs);
            sfx.play(.eat);
        },
    }
}

fn heroTakes(g: *Game, b: foemod.Blow, heavy: bool, voice: bool) combat.HitOutcome {
    const out = g.hero.takeHit(b.hit, mathx.dirXZ(g.hero.pos, b.from));
    switch (out) {
        .ignored => {}, // rolled through it, or he was already gone
        .taken => heroHurtBeat(g, heavy, voice),
        .blocked => heroBlockBeat(g, b.hit),
        .guardBroken => {
            g.rumble.play(rumblemod.guard_break);
            g.rig.addShake(SHAKE_GUARD_BREAK);
            sfx.play(.guard_break);
        },
    }
    return out;
}

fn heroBlockBeat(g: *Game, h: combat.Hit) void {
    // OFF THE RAW BLOW, like the stamina bill it is paid beside (`combat.guardStamina`): a blow with no
    // physical half at all — the mother's spit, the sling's burning clump — read as the lightest thing in
    // the game the moment those two were retyped, because this measured `dmg` alone.
    const w = mathx.clampF(h.raw() / BLOW_HEAVIEST, BLOCK_FELT_MIN, 1.0);
    g.rumble.play(if (w >= BLOCK_FELT_HEAVY) rumblemod.guard_block_heavy else rumblemod.guard_block);
    g.rig.addShake(SHAKE_BLOCK * w);
    sfx.play(.guard_block);
}

fn allHits(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f.field).totalHits();
    return n;
}
fn allAlive(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f.field).aliveCount();
    return n;
}
fn anyFoeDied(g: *const Game) bool {
    inline for (FOE_GROUPS) |f| {
        if (@field(g, f.field).anyDied()) return true;
    }
    return false;
}
fn allRunes(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f.field).runesDropped();
    return n;
}

// The hero's blade this frame as plain data for the foe hit test (endpoints guard→tip, plus last frame's for the swept test; active only inside the strike window).
/// HOW FAR THE HERO MUST FOLD TO PUT A FLAT CUT THROUGH WHAT IS IN FRONT OF HIM — degrees below his own eye line, or null for "nothing worth stooping for".
const MELEE_AIM_R: f32 = 3.6;
/// …and it must be in FRONT: cos of the half-angle off his facing.
const MELEE_AIM_DOT: f32 = 0.35;
/// The eye line the pitch is measured FROM — his shoulders, which is roughly where the flat arc lives.
const MELEE_AIM_EYE: f32 = 1.35;

const MarkCtx = struct {
    g: *const Game,
    fwd: rl.Vector3,
    best: ?rl.Vector3 = null,
    bestD: f32 = MELEE_AIM_R,

    fn visit(self: *MarkCtx, foes: anytype, _: ?FoeKind) void {
        for (foes) |*f| {
            if (!f.alive() or f.dying()) continue;
            const d = mathx.distXZ(self.g.hero.pos, f.pos);
            if (d >= self.bestD) continue;
            const to = mathx.dirXZ(self.g.hero.pos, f.pos);
            if (d > 0.2 and to.x * self.fwd.x + to.z * self.fwd.z < MELEE_AIM_DOT) continue;
            self.bestD = d;
            self.best = f.lockPoint();
        }
    }
};

fn meleeMark(g: *const Game) ?rl.Vector3 {
    if (activeLock(g)) |li| {
        if (mathx.distXZ(g.hero.pos, foePos(g, li)) <= MELEE_AIM_R * 2.0) return foeLockPoint(g, li);
    }
    var ctx = MarkCtx{ .g = g, .fwd = mathx.headingDir(g.hero.facing) };
    eachTarget(g, &ctx, MarkCtx.visit);
    return ctx.best;
}

fn meleePitch(g: *const Game) ?f32 {
    const mark = meleeMark(g) orelse return null;
    const flat = mathx.distXZ(g.hero.pos, mark);
    if (flat < 0.35) return null;
    return mathx.degrees(std.math.atan2(g.hero.pos.y + MELEE_AIM_EYE - mark.y, flat));
}

pub fn heroBlade(g: *const Game) foemod.Blade {
    return .{
        .active = g.hero.hitActive(),
        .r = heromod.BLADE_R,
        .a = g.hero.bladeA,
        .b = g.hero.bladeB,
        .a0 = g.hero.bladeA0,
        .b0 = g.hero.bladeB0,
        .hit = g.hero.attackHit(), // HP/poise/stance for THIS swing (light vs heavy)
    };
}

// Resolve XZ footprint collisions (see collision.zig).
fn inBounds(p: rl.Vector3) rl.Vector3 {
    return v3(mathx.clampF(p.x, -PLAY_HALF, PLAY_HALF), p.y, mathx.clampF(p.z, -PLAY_HALF, PLAY_HALF));
}

fn collideActors(g: *Game, dt: f32) void {
    const step = COLLIDE_RATE * dt; // max correction this frame — bigger pushes ease in (no warp)
    var hp = g.env.resolveActor(g.hero.pos, HERO_R);
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*a| {
            if (foemod.corporeal(a) and !a.airborne()) hp = collision.pushOutCircle(hp, HERO_R, a.pos, a.bodyR());
        }
    }
    g.hero.pos = mathx.approachV(g.hero.pos, inBounds(hp), step);

    settleGroup(g, g.warren.live(), .{}, step, true);
    settleGroup(g, g.line.live(), .{g.warren.live()}, step, true);
    settleGroup(g, g.grief.live(), .{}, step, false);
    settleGroup(g, g.band.live(), .{}, step, true);
    settleGroup(g, g.brood.live(), .{}, step, true);
    settleGroup(g, g.muster.live(), .{g.line.live()}, step, true);
}

fn settleGroup(g: *Game, foes: anytype, others: anytype, step: f32, toHero: bool) void {
    for (foes, 0..) |*a, i| {
        if (!foemod.corporeal(a)) continue;
        const r = a.bodyR();
        // THE MASONRY STOPS A LEAP TOO (owner's call). Being airborne exempts a committed jump from the
        // terrain step rule and from being shouldered by other bodies — never from the world's solids. A
        // pounce or a backstep that crossed a wall was a foe leaving the arena through it. Applied at
        // FULL STRENGTH rather than eased: the correction is only ever the one frame of travel that put
        // it inside, and a leap into stone has to stop at the stone or it grinds its way through anyway.
        if (a.airborne()) {
            a.pos = inBounds(g.env.resolveActor(a.pos, r));
            continue;
        }
        var p = g.env.resolveActor(a.pos, r);
        if (toHero) p = collision.pushOutCircle(p, r, g.hero.pos, HERO_R);
        for (foes, 0..) |*o, j| {
            if (i == j or !foemod.corporeal(o) or o.airborne()) continue;
            p = collision.pushOutCircle(p, r, o.pos, o.bodyR());
        }
        inline for (others) |grp| {
            for (grp) |*o| {
                if (foemod.corporeal(o) and !o.airborne()) p = collision.pushOutCircle(p, r, o.pos, o.bodyR());
            }
        }
        a.pos = mathx.approachV(a.pos, inBounds(p), step);
    }
}

const FoeKind = worldfmt.FoeKind;
const FoeRef = struct { kind: FoeKind, idx: usize };
fn bandIdx(r: FoeRef) ?usize {
    return if (koboldmod.roleOf(r.kind) != null) r.idx else null;
}
/// …and the BROOD is the same shape: mother and hatchling both index `g.brood.band`.
fn broodIdx(r: FoeRef) ?usize {
    return if (broodmod.roleOf(r.kind) != null) r.idx else null;
}
/// …and the MUSTER: shieldman and greatsword both index `g.muster.band`.
fn musterIdx(r: FoeRef) ?usize {
    return if (warriormod.roleOf(r.kind) != null) r.idx else null;
}
/// ASK ONE QUESTION OF WHATEVER A `FoeRef` POINTS AT.
fn askFoe(comptime T: type, g: *const Game, r: FoeRef, comptime ask: anytype) T {
    if (bandIdx(r)) |i| return ask(&g.band.band[i]);
    if (broodIdx(r)) |i| return ask(&g.brood.band[i]);
    if (musterIdx(r)) |i| return ask(&g.muster.band[i]);
    if (r.kind == .brood_sac) return ask(&g.brood.sacs[r.idx]);
    return switch (r.kind) {
        .toad => ask(&g.warren.frogs[r.idx]),
        .archer => ask(&g.line.archers[r.idx]),
        .ogre => ask(&g.grief.ogres[r.idx]),
        .berserker, .priest, .slinger => unreachable, // handled above
        .brood_mother, .broodling, .brood_sac => unreachable,
        .shieldman, .greatsword => unreachable,
    };
}
fn foePos(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype) rl.Vector3 {
            return f.pos;
        }
    }.ask);
}
fn foeResists(g: *const Game, r: FoeRef) combat.Resists {
    return askFoe(combat.Resists, g, r, struct {
        fn ask(f: anytype) combat.Resists {
            return f.vit.res;
        }
    }.ask);
}
fn foeLockPoint(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype) rl.Vector3 {
            return f.lockPoint();
        }
    }.ask);
}
// A live, non-dissipating foe (both a fresh acquire and a held lock require this).
fn foeLockable(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype) bool {
            return f.alive() and !f.dying();
        }
    }.ask);
}
/// IS THE REF STILL POINTING AT SOMETHING THAT EXISTS? Every group is fixed-size storage plus a LIVE
/// COUNT, so its tail is `undefined` — an index that outlived a re-home is a read of undefined memory,
/// not a stale target. `rehomeFoes` runs on a world reload, a respawn, a rest and every editor frame,
/// and only three of those four drop the lock. The bound belongs here, where the whole game asks
/// whether the lock is still good, rather than at each of them.
fn refInBounds(g: *const Game, r: FoeRef) bool {
    if (bandIdx(r)) |i| return i < g.band.liveConst().len;
    if (broodIdx(r)) |i| return i < g.brood.liveConst().len;
    if (musterIdx(r)) |i| return i < g.muster.liveConst().len;
    if (r.kind == .brood_sac) return r.idx < g.brood.liveSacsConst().len;
    return switch (r.kind) {
        .toad => r.idx < g.warren.liveConst().len,
        .archer => r.idx < g.line.liveConst().len,
        .ogre => r.idx < g.grief.liveConst().len,
        // …every kind handled by the three group checks above, named so a new one cannot slip past.
        .berserker, .priest, .slinger, .brood_mother, .broodling, .brood_sac, .shieldman, .greatsword => false,
    };
}
fn lockValid(g: *const Game, r: FoeRef) bool {
    if (!refInBounds(g, r)) return false;
    return foeLockable(g, r) and mathx.distXZ(g.hero.pos, foePos(g, r)) <= MAX_LOCK_R + 2.0;
}

/// THE LOCK THE GAME IS ACTING ON — none of it while the bow is up.
fn activeLock(g: *const Game) ?FoeRef {
    return if (g.hero.aiming) null else g.lock;
}

const PROJECT_NEAR = CLIP_NEAR; // must equal the near clip plane set in run()
fn projectToScreen(cam: rl.Camera3D, p: rl.Vector3) ?rl.Vector2 {
    const to = mathx.subV(p, cam.position);
    const fwd = mathx.normV(mathx.subV(cam.target, cam.position)); // camera forward (unit)
    const depth = to.x * fwd.x + to.y * fwd.y + to.z * fwd.z; // signed distance along the view axis
    if (depth < PROJECT_NEAR) return null;
    return rl.getWorldToScreen(p, cam);
}

// Screen-x of a foe's lock point (null if it's behind the camera).
fn lockScreenX(g: *const Game, r: FoeRef) ?f32 {
    const s = projectToScreen(g.rig.cam, foeLockPoint(g, r)) orelse return null;
    return s.x;
}

fn acquireLock(g: *const Game) ?FoeRef {
    var ctx = LockCtx{ .g = g, .cx = @as(f32, @floatFromInt(rl.getScreenWidth())) * 0.5 };
    eachTarget(g, &ctx, LockCtx.visit);
    return ctx.best;
}

fn memberKind(f: anytype, group: ?FoeKind) FoeKind {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "kind")) return f.kind();
    return group.?;
}

// A fresh acquire: nearest to screen-centre, across every target list.
const LockCtx = struct {
    g: *const Game,
    cx: f32,
    best: ?FoeRef = null,
    bestScore: f32 = 1e9,

    fn visit(self: *LockCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            if (!f.alive() or f.dying() or mathx.distXZ(self.g.hero.pos, f.pos) > MAX_LOCK_R) continue;
            const r = FoeRef{ .kind = memberKind(f, kind), .idx = i };
            const sx = lockScreenX(self.g, r) orelse continue;
            const score = @abs(sx - self.cx);
            if (score < self.bestScore) {
                self.bestScore = score;
                self.best = r;
            }
        }
    }
};

// …and the flick: the nearest target PAST the current one, in the flicked direction.
const CycleCtx = struct {
    g: *const Game,
    cur: FoeRef,
    curX: f32,
    dir: f32,
    best: ?FoeRef = null,
    bestGap: f32 = 1e9,

    fn visit(self: *CycleCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            const r = FoeRef{ .kind = memberKind(f, kind), .idx = i };
            if ((self.cur.kind == r.kind and self.cur.idx == i) or !f.alive() or f.dying()) continue;
            if (mathx.distXZ(self.g.hero.pos, f.pos) > MAX_LOCK_R) continue;
            const sx = lockScreenX(self.g, r) orelse continue;
            const gap = (sx - self.curX) * self.dir;
            if (gap > CYCLE_MIN_GAP and gap < self.bestGap) {
                self.bestGap = gap;
                self.best = r;
            }
        }
    }
};

/// Screen pixels a candidate must sit PAST the current target to count as "the next one".
const CYCLE_MIN_GAP: f32 = 5.0;

fn cycleLock(g: *Game, dir: f32) void {
    const cur = g.lock orelse return;
    const curX = lockScreenX(g, cur) orelse return;
    var ctx = CycleCtx{ .g = g, .cur = cur, .curX = curX, .dir = dir };
    eachTarget(g, &ctx, CycleCtx.visit);
    if (ctx.best) |b| g.lock = b;
}

// The world-reload half of a hero death (ER: dying resets the field).
fn resetFoes(g: *Game) void {
    rehomeFoes(g);
    clearQuivers(g);
    g.lock = null;
}

const HURT_BAR_WINDOW = 5.0;

// Floating HP bars over EVERY target (shared foe contract, one walk for all).
const BarCtx = struct {
    cam: rl.Camera3D,

    fn visit(self: *const BarCtx, foes: anytype, _: ?FoeKind) void {
        for (foes) |*f| {
            if (!f.alive() or f.dying()) continue; // no bar over a corpse dissolving out
            if (f.vit.sinceHit > HURT_BAR_WINDOW) continue; // only after a recent hit
            const s = projectToScreen(self.cam, f.topWorld()) orelse continue; // skip if behind the camera
            hud_.foeBar(s.x, s.y, f.vit.hpFrac(), f.staggered()); // size/colour/lift all live in hud
        }
    }
};

fn drawFoeBars(g: *const Game) void {
    const ctx = BarCtx{ .cam = g.rig.cam };
    eachTarget(g, &ctx, BarCtx.visit);
}

// The glowing white reticle on the locked foe (ER's dot) — 2D + crisp, drawn after the 3D pass.
fn drawLockDot(g: *Game) void {
    const li = activeLock(g) orelse return;
    const s = projectToScreen(g.rig.cam, foeLockPoint(g, li)) orelse return; // skip if behind the camera
    const x: i32 = @intFromFloat(s.x);
    const y: i32 = @intFromFloat(s.y);
    rl.drawCircleGradient(x, y, 15, rgba(255, 255, 255, 175), rgba(255, 255, 255, 0));
    rl.drawCircle(x, y, 2, rl.Color.white); // crisp hot centre
}

