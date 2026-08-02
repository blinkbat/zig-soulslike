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
const chestmod = @import("chest.zig"); // the openable boxes
const restmod = @import("rest.zig"); // sitting at a bonfire
const item = @import("item.zig"); // …and what is in them
const sfx = @import("audio.zig"); // the procedural sound bank — every voice synthesized at launch

const v3 = mathx.v3;
const rgba = mathx.rgba;

// THE pad index, from rumble.zig — input polling and the XInput vibration calls MUST target the same controller, and rumble.PAD says so.
const PAD = rumblemod.PAD;

const SCREEN_W = 1280;
const SCREEN_H = 800;

// Locomotion speeds live with the hero rig (single source of truth); gait blends tune to these, so reference them here to prevent drift.
const WALK_SPEED = heromod.WALK_SPEED; // keyboard walk / gentle left-stick tilt
const RUN_SPEED = heromod.RUN_SPEED; // full left-stick tilt (light tilt scales down toward walk)
const SPRINT_SPEED = heromod.SPRINT_SPEED; // hold Circle/B (or Shift): dash/sprint
const TURN_RATE = 12.0; // rad/sec the hero yaws toward its heading (souls turn briskly)
const STRAFE_SPEED = heromod.STRAFE_SPEED; // LOCKED-ON sideways travel, as a fraction of forward —
const STICK_DEADZONE = 0.16; // left-stick move deadzone — RADIAL, see stickRadial
// Right-stick LOOK deadzone.
const LOOK_DEADZONE = 0.14;
/// How hard the right stick must be pushed to TAKE THE CAMERA off the mouse — a different question from how hard it must be pushed to turn (`LOOK_DEADZONE`), and keeping them the same number is what let a worn pad kill mouse look outright (see the latch in run()).
const LOOK_CLAIM = 0.40;
// Pixels of mouse travel in one frame that count as the player REACHING FOR THE MOUSE — see the look-device latch.
const MOUSE_WAKE: f32 = 2.0;
// YAW is unbounded and a full turn at this rate takes ~2.3 s.
const LOOK_RATE_YAW = 3.4; // rad/sec orbit at full right-stick deflection
const LOOK_RATE_PITCH = 2.0; // …and vertical, deliberately slower (see above)
// Response shape past the deadzone: 1 = linear, >1 = fine aim near the centre with the SAME top rate still reached at the rim.
const LOOK_CURVE = 1.7;
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
// …and the guard BREAKING is worse than any single hit bar the last one: it is the moment you find out the next blow is free.
const SHAKE_GUARD_BREAK = 0.72;
// THE HEAVIEST BLOW IN THE GAME, which is what a caught one is weighed against — read off the ogre's own table rather than typed as a number, so re-tuning his club re-scales the block feedback with it instead of quietly pinning every block at full weight.
const BLOW_HEAVIEST = ogremod.SLAM_HIT.dmg;
const BLOCK_FELT_MIN = 0.25; // …even the smallest blow is FELT: a block you cannot feel reads as a whiff
const BLOCK_FELT_HEAVY = 0.5; // …and past half the club, the pad's heavier signature takes over
const SHAKE_DEATH = 0.85;
// …and the ONE non-combat beat: a chest coming open.
const SHAKE_CHEST = 0.12;
// The YOU DIED tail, in two beats.
const RESPAWN_HOLD = 0.55; // seconds of FULL black after the respawn…
const RESPAWN_FADE = 0.9; // …then this long fading up into the fresh world

// Hero movement clamp: the MAP's bounds inset so travel and rolls cannot reach the edge.
pub var PLAY_HALF: f32 = worldfmt.DEFAULT_HALF - envmod.PLAY_INSET;

// Hero footprint radius for ground collision (see collision.zig).
const HERO_R = foemod.HERO_R;

// Skeletal-archer arrows: shared pool of in-flight + stuck shafts, plus the hero centre-of- mass height archers aim at and arrows test strikes against.
const MAX_ARROWS = 24;
/// The hero's centre of mass ABOVE HIS OWN FEET — not a world height.
pub const HERO_CENTER_Y = 1.0;

// Collision correction is rate-limited so a large depenetration eases in over a few frames (smooth slide, not a choppy warp).
const COLLIDE_RATE = 11.0; // world units / sec

// An actor's `pos.y` is the ground under them, written HERE for the hero and every foe (`groundActor`); the rigs only read it.
const GROUND_RISE_RATE = 9.0; // m/s the body climbs onto higher ground…
const GROUND_FALL_RATE = 16.0; // …and falls onto lower (gravity-ish, no real fall state yet)
/// Past this the ease is abandoned and the actor is planted: a teleport (respawn, F5 playtest, the shot harness) must not spend a second sliding up out of the earth, and no real step is anywhere near it.
const GROUND_SNAP: f32 = 2.5;

// Depth clip planes, set once in run().
const CLIP_NEAR = 0.55;
const CLIP_FAR = 320.0;

const MAX_LOCK_R = 17.0; // won't acquire, and drops, a foe beyond this
const LOCK_CAM_EASE = 9.0; // exponential ease rate for the lock-on camera swing (quick, snap-free)
const LOCK_PITCH = 0.24; // framing pitch while locked (the toads sit low)
const LOCK_FLICK = 0.65; // right-stick |x| past this cycles to the next target

// Framebuffer clear tone — matches the sky shader's horizon band (displayed gfx.HAZE) so any sliver the sky quad misses stays invisible.
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
    chests: chestmod.Chests, // the openable boxes — props with a lid and a state (chest.zig)
    rest: restmod.Rest = .{}, // sitting at a bonfire: the state machine and the fade (rest.zig)
    /// The player's own retro stack, parked while a rest borrows the screen for its VHS look.
    restRetro: [gfx.RETRO_COUNT]f32 = [_]f32{0} ** gfx.RETRO_COUNT,
    bag: item.Bag = .{}, // …and what came out of them. The hero's, but held here with the rest of the run
    arrowModel: rl.Model, // shared arrow mesh, drawn per live/stuck arrow with its own matrix
    stoneModel: rl.Model, // …and the slingers' stone, drawn from the SAME pool (see Arrow.stone)
    arrows: [MAX_ARROWS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_ARROWS,
    rig: cameramod.CamRig,
    lock: ?FoeRef = null, // ER lock-on: which foe (toad or skeleton) is locked, or null
    rumble: rumblemod.Rumble = .{}, // controller vibration, keyed to combat beats
    deathFade: f32 = 0, // post-respawn fade-from-black seconds remaining (armed while dead)
    /// THE LOOK-INPUT PROBE — raw, per frame, straight onto the debug readout.
    probe: LookProbe = .{},

    // Built IN PLACE rather than returned by value: Env alone is ~450 KB of flat prop/grid arrays, and a by-value Game would copy all of it across the stack on the way out.
    fn init(g: *Game) void {
        g.scene = gfx.Scene.init();
        g.sky = gfx.Sky.init();
        g.vignette = gfx.Vignette.init();
        g.retro = gfx.Retro.init(rl.getScreenWidth(), rl.getScreenHeight());
        g.menu = .{}; // opens on the main screen: Continue / Debug / Quit
        worldfmt.loadOrPanic(worldfmt.START_MAP, &g.map);
        PLAY_HALF = g.map.half - envmod.PLAY_INSET; // before anything spawns against it
        g.env.build(&g.scene); // meshes once…
        // THE PAINTED FIELDS GO UP FIRST.
        g.env.uploadSoil(&g.map);
        g.env.uploadWater(&g.map);
        // …AND THE SCULPTED GROUND, which `materialize` needs even more urgently than the water: every prop is planted at the height under it, so replaying the ops against a flat field stands the whole world at the wrong elevation.
        g.env.uploadHeight(&g.map);
        g.env.materialize(&g.map); // …then the world from the map, re-runnable per edit
        g.hero = heromod.Hero.init(g.scene.shader);
        g.hero.pos = mathx.ground(0, 4); // start just south of the ruin avenue
        plantActor(g, &g.hero.pos); // …standing ON it, whatever the ground there was sculpted to
        g.hero.facing = std.math.pi; // facing -Z, into the columns
        g.hero.setSpawn(g.hero.pos, g.hero.facing); // where a death returns him
        g.hero.pose();
        g.warren = frogmod.Knot.init(g.scene.shader);
        g.line = archermod.Line.init(g.scene.shader);
        g.grief = ogremod.Grief.init(g.scene.shader);
        g.band = koboldmod.Warband.init(g.scene.shader);
        g.chests = chestmod.Chests.init(g.scene.shader);
        // Foes come from the MAP, so the groups can only be homed once it is loaded — init builds the shared meshes and nothing else.
        rehomeFoes(g);
        // …and the chests come from the PROPS, so this goes after `materialize` rather than beside the foe groups: a chest's position is where env actually planted it (see `env.chestSites`).
        g.rest = .{};
        rehomeChests(g);
        g.bag = .{};
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.stoneModel = koboldmod.stoneMesh(g.scene.shader);
        g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
        // Fields that would otherwise take their struct-literal defaults; set explicitly because there is no literal to default from any more.
        g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
        g.editor = .{};
        g.lock = null;
        g.rumble = .{};
        g.deathFade = 0;
        g.restRetro = [_]f32{0} ** gfx.RETRO_COUNT;
        // …the look probe included: `Game` is built in place from `alloc.create`, so a field this block misses never gets its default at all — and `pad` is a bool, where raw heap bytes are illegal behaviour rather than merely a wrong caption.
        g.probe = .{};
    }
};

/// THE FOE GROUPS, WRITTEN DOWN ONCE. Every "do this to every group" walks this list, so a fifth creature is one entry here rather than a line in eleven places — and the old layout's failure mode was SILENT (miss the re-home and that group simply never comes back).
const FOE_GROUPS = [_][]const u8{ "warren", "line", "grief", "band" };

/// RE-HOME EVERY GROUP FROM THE MAP.
fn rehomeFoes(g: *Game) void {
    inline for (FOE_GROUPS) |f| @field(g, f).reset(&g.map);
}

const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

/// A STICK, DEADZONED RADIALLY — direction and magnitude kept apart, which is what a twin-stick camera (ER's included) does.
const Stick = struct { x: f32 = 0, y: f32 = 0, mag: f32 = 0 };

fn stickRadial(x: f32, y: f32, dz: f32, curve: f32) Stick {
    const m = @sqrt(x * x + y * y);
    if (m < dz) return .{};
    // Clamped, because a real pad reports past 1 on the diagonals (a square gate on a round stick).
    const t = mathx.minF((m - dz) / (1.0 - dz), 1.0);
    return .{ .x = x / m, .y = y / m, .mag = std.math.pow(f32, t, curve) };
}

test "a radial stick keeps the thumb's ANGLE and does not favour the cardinals" {
    // The bug this pins: per-axis deadzoning eats the small component whole, so a stick pushed just off horizontal comes out very nearly horizontal.
    const ang = 0.26; // ~15°, the case that used to collapse to ~3°
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
    // THE bug this pins, and it presented as three separate complaints at once ("stick drift?", "camera drifting?", "too sensitive?").
    try std.testing.expect(LOOK_CLAIM > LOOK_DEADZONE);
    // …and the gap has to clear a real resting deflection.
    const WORN_STICK_REST: f32 = 0.25;
    try std.testing.expect(LOOK_CLAIM > WORN_STICK_REST);
    // …while staying nowhere near a deliberate push, or reaching for the stick stops working.
    try std.testing.expect(LOOK_CLAIM < 0.7);
    // A stick resting at a typical drift still produces a SMALL turn rate, not a fast one — that is the deadzone doing its half of the job, and it is why drift reads as a slow creep rather than a spin.
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
    try std.testing.expect(half.mag > 0.2); // …but it is still a curve, not a dead zone with a lip
}

fn gatherMove() Move {
    var sprint = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    // Gamepad first (analog left stick; Circle/B held = dash/sprint).
    if (rl.isGamepadAvailable(PAD)) {
        if (rl.isGamepadButtonDown(PAD, .right_face_right)) sprint = true;
        // LINEAR curve here, and that is the FEEL RULE, not an oversight: the move stick's tilt maps STRAIGHT to ground speed with nothing shaping it in between.
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
    // Keyboard (digital → an immediate run; walking is the stick's analog privilege).
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

// THE hold-B/Shift SPRINT test, read straight off the raw Move: a real heading plus a speed past a full-tilt walk.
fn sprintingMove(mv: Move) bool {
    return mv.speed > RUN_SPEED + 0.01 and (mv.fx * mv.fx + mv.fz * mv.fz) > 1e-6;
}

const WADE_KNEE: f32 = 0.75; // mid-thigh on the H=1.8 rig — where a leg starts pushing instead of swinging
const WADE_DEEP: f32 = 1.5; // …shoulder, where the walk is as slow as it gets
const WADE_SLOWEST: f32 = 0.8; // …as a fraction of the WALK, not of the run he has already lost

/// How much the water is holding him back, as a fraction of the walk. 1.0 means it is not.
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

/// The drag curve alone, off a depth — `wadeDrag` is that plus the world lookup, which a test has no Env to do.
fn wadeDragAt(d: f32) f32 {
    if (d <= WADE_KNEE) return 1.0;
    return mathx.lerpF(1.0, WADE_SLOWEST, mathx.smoothstep(WADE_KNEE, WADE_DEEP, d));
}

/// PLANT AN ACTOR ON THE GROUND: ease `pos.y` toward the terrain height under its feet.
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

/// …and PLANT ONE NOW, with no ease: a spawn, a respawn, an editor playtest drop.
fn plantActor(g: *const Game, pos: *rl.Vector3) void {
    pos.y = g.env.groundAt(pos.x, pos.z);
}

/// The ground height, as the camera rig wants it: a plain function over a context, so `camera.zig` can keep the eye out of the terrain without knowing what a height field is.
pub fn envGroundAt(e: *const envmod.Env, x: f32, z: f32) f32 {
    return e.groundAt(x, z);
}

/// Where each live foe stands, for the terrain gate below.
fn snapshotPos(foes: anytype, out: []rl.Vector3) void {
    for (foes, 0..) |*f, i| {
        if (i >= out.len) return;
        out[i] = f.pos;
    }
}

/// THE FOES GET THE SAME GROUND RULES THE HERO DOES.
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

// Move + steer the hero from a camera-relative Move, advance the walk anim, and pose the skeleton.
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
        // THE TERRAIN DECIDES WHETHER THE STEP HAPPENS (env.walkStep): a slight step or an incline inside the slope limit is taken, anything steeper has its uphill component refused and the hero slides along the face.
        const stepped = g.env.walkStep(g.hero.pos, dir, moved);
        g.hero.pos.x = mathx.clampF(stepped.x, -PLAY_HALF, PLAY_HALF);
        g.hero.pos.z = mathx.clampF(stepped.z, -PLAY_HALF, PLAY_HALF);
    }
    // Facing: toward the LOCKED foe (hero strafes/backpedals facing it, ER-style), else toward travel.
    if (faceYaw != null and !sprinting) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, faceYaw.?, TURN_RATE * dt);
    } else if (isMoving) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, moveYaw.?, TURN_RATE * dt);
    }
    g.hero.update(dt, moved, speed, moveYaw);
    g.hero.pose();
}

/// The hero's posture on the ground he is standing on: ease the whole-body lean toward what the slope under him asks for.
fn leanToGround(g: *Game, dt: f32) void {
    const face = mathx.headingDir(g.hero.facing);
    const want = heromod.slopeLean(g.env.slopeAlong(g.hero.pos.x, g.hero.pos.z, face));
    g.hero.slopePitch = mathx.approach(g.hero.slopePitch, want, heromod.SLOPE_LEAN_RATE * dt);
}

// World direction to roll: the camera-relative move intent if any, else the hero's facing (a forward roll).
fn rollDir(g: *Game, mv: Move) rl.Vector3 {
    const fwd = g.rig.forwardXZ();
    const right = g.rig.rightXZ();
    const d = v3(fwd.x * mv.fz + right.x * mv.fx, 0, fwd.z * mv.fz + right.z * mv.fx);
    if (mathx.lenXZ(d) > 0.01) return d;
    return mathx.headingDir(g.hero.facing);
}

// Casters = the hero + the stone props.
fn drawCasters(g: *Game, cull: envmod.Cull) void {
    g.env.drawProps(cull);
    // THE CHEST LIDS, with the props and not after them: a lid is a caster like the box under it, and drawn outside this function it would be missing from the shadow map — a chest with its lid thrown back would cast the shadow of a closed one.
    g.chests.draw();
    // Combat flash rides the scene shader's per-actor hitFlash uniform: the hero reddens on a suffered blow, and every struck FOE on a landed one (each Group's draw sets it per instance from foe.FLASH_GAIN).
    g.scene.setFlash(0.6 * g.hero.hurtFlash);
    g.hero.draw();
    g.scene.setFlash(0);
    inline for (FOE_GROUPS) |f| @field(g, f).draw(&g.scene);
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
    inline for (FOE_GROUPS) |f| @field(g, f).setShader(sh);
    // THE CHEST LIDS TOO.
    g.chests.setShader(sh);
}

/// The WORLD height of the hero's centre of mass — his feet plus `HERO_CENTER_Y`.
pub fn heroCenterY(g: *const Game) f32 {
    return g.hero.pos.y + HERO_CENTER_Y;
}

/// …and that centre as a point, which is what a loose is aimed at.
fn heroAimPoint(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, heroCenterY(g), g.hero.pos.z);
}

// Launch an arrow from a free pool slot (the loose event).
fn spawnArrow(g: *Game, from: rl.Vector3, target: rl.Vector3) void {
    poolPut(g, archermod.launchArrow(from, target));
}

/// A SLINGER'S STONE into the SAME pool — see `archer.Arrow.stone`.
pub fn spawnStone(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchStone(from, heroAimPoint(g), koboldmod.STONE_SPEED));
}

// A chest is a PROP with a lid and a state, so the list is rebuilt from the props whenever the world is.
fn rehomeChests(g: *Game) void {
    var sites: [chestmod.CAP]chestmod.Site = undefined;
    const n = g.env.chestSites(&sites);
    g.chests.reset(sites[0..n]);
    // The bonfires ride along: same source of truth, same moment, so a re-materialized world can never leave a rest site pointing at where a camp used to be.
    var fires: [restmod.CAP]restmod.Site = undefined;
    g.rest.reset(fires[0..g.env.restSites(&fires)]);
}

/// Shims for the shot harness, so it drives the same two calls the loop does.
pub fn rehomeChestsForShot(g: *Game) void {
    rehomeChests(g);
}

/// …and the same for a REST: the harness runs the real state machine rather than staging a pose, so a shot cannot flatter a scene the game does not actually produce.
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

/// OPEN THE CHEST IN REACH.
fn interact(g: *Game) void {
    if (g.rest.begin()) return; // a bonfire beats a chest — you cannot be in reach of both
    const got = g.chests.openNear(&g.map) orelse return;
    for (got.loot) |it| g.bag.add(it, 1);
    if (got.loot.len > 0) sfx.world(.item_get, got.at);
    // The same beat a landed blow gets, at a fraction of it: a chest is a good thing happening, and under the NO HITSTOP law the way anything is felt here is shake and rumble, never a pause.
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

fn tickRest(g: *Game, dt: f32) void {
    g.rest.update(dt);
    if (g.rest.justEntered) {
        inline for (FOE_GROUPS) |f| {
            @field(g, f).n = 0;
        }
        for (&g.arrows) |*a| a.live = false;
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
        // EVERY FOE BACK, whole, from the map — the groups are re-homed rather than healed in place, which is also what makes the ones you killed return.
        rehomeFoes(g);
    }
    // ANY BUTTON GETS YOU UP.
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

/// The dusk dial, pushed to BOTH shaders that read it — see gfx.Scene.setDim.
fn applyDim(g: *Game) void {
    const d = g.rest.dim();
    g.scene.setDim(d);
    g.sky.setDim(d);
    // …and the propped guitar goes off the rock for exactly as long as he is holding one.
    g.env.stowed = g.hero.resting;
}

/// THE REST'S CAMERA — a fixed low three-quarter on the seated hero with the fire between him and the lens, drifting a couple of degrees so it breathes without becoming a shot of the scenery.
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

// Pool-full is rare (24 slots against a ~1.5 s reload); overwrite slot 0 rather than silently drop the shot.
fn poolPut(g: *Game, a: archermod.Arrow) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) {
            ar.* = a;
            return;
        }
    }
    g.arrows[0] = a;
}

// The world solids one arrow could hit THIS frame: everything within its own travel distance, pulled from the prop grid. stepArrow samples the midpoint and endpoint of the step, so the query has to cover a whole frame of flight plus enough slop that a capsule whose CENTRE LINE sits in the next cell along is still handed back.
/// …and that slop, which is a solid's own half-width and NOT `archer.ARROW_COVER_MARGIN` — the comment here used to call it "the fattest margin it tests with", which is the shaft's 4 cm and thirty times too small a number to be doing this job.
const ARROW_QUERY_PAD: f32 = 1.5;
var arrow_cover_buf: [envmod.MAX_NEAR]collision.Solid = undefined;
pub fn arrowCover(g: *const Game, ar: *const archermod.Arrow, dt: f32) []const collision.Solid {
    return g.env.nearSolids(ar.pos, mathx.lenV(ar.vel) * dt + ARROW_QUERY_PAD, &arrow_cover_buf);
}

// Draw every live/stuck arrow, oriented along its flight (shrinking as a stuck one fades).
fn drawArrows(g: *Game) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) continue;
        const m = if (ar.stone) &g.stoneModel else &g.arrowModel;
        rl.drawMesh(m.meshes[0], m.materials[0], archermod.arrowXform(ar));
    }
}

// The camera the frame is rendered from.
fn sceneCam(g: *const Game) rl.Camera3D {
    return if (g.editor.on) g.editor.cam else g.rig.cam;
}

// What the sun's ortho box tracks.
fn sunFocus(g: *const Game) rl.Vector3 {
    // The GROUND under the editor's aim, not the datum: the shadow box tracks its focus in all three axes now (gfx.beginShadowPass), and dressing a hilltop with the box 20 m below it drops every cast shadow up there.
    if (!g.editor.on) return g.hero.pos;
    const t = g.editor.cam.target;
    return v3(t.x, g.env.groundAt(t.x, t.z), t.z);
}

pub fn drawScene(g: *Game) void {
    g.env.resetStats(); // culling counters for the debug overlay, both passes together
    applyDim(g); // before the depth pass: the uniform is read by every draw below it
    const cam = sceneCam(g);
    const focus = sunFocus(g);
    // Sun depth pass into the shadow map (before beginDrawing).
    g.scene.beginShadowPass(focus);
    setCasterShaders(g, g.scene.depthShader);
    drawCasters(g, .{ .sun = focus });
    setCasterShaders(g, g.scene.shader);
    g.scene.endShadowPass();

    rl.beginDrawing();
    // With any filter live, sky + 3D render into the capture RT and blit back through the filter shader; vignette/HUD/menu stay crisp on top.
    const filtered = if (g.editor.on) false else g.retro.begin();
    rl.clearBackground(CLEAR);
    g.sky.draw(cam);

    // ONE view frustum for the whole lit pass, built from the settled camera — props and flora must cull against the same one or a prop can be in for the shadow and out for the light.
    const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
    const view = envmod.View.fromCamera(cam, aspect);

    rl.beginMode3D(cam);
    g.scene.bind(cam.position);
    // Torchlight: the fires whose pool is ON SCREEN, nearest first, guttering.
    g.env.uploadLights(&g.scene, &view, @floatCast(rl.getTime()));
    g.scene.setGround(true);
    g.env.drawGround(&view); // sculpted terrain is tiled, so it culls against the same frustum
    g.scene.setGround(false);
    // THE PAINTED WATER, straight after the ground it lies on: one quad whose dry fragments the shader discards, so everything standing in a lake (reeds, drowned columns) draws over it by depth test in the passes below rather than needing to be sorted against it.
    g.env.drawWater();
    if (g.menu.wireframe) rl.gl.rlEnableWireMode();
    drawCasters(g, .{ .view = view });
    // Flora last: non-casting, and swayed by the scene shader's wind term (props/hero rigid).
    g.scene.setWind(true);
    g.env.drawFlora(&view);
    g.scene.setWind(false);
    drawArrows(g); // in-flight + stuck arrows (lit, rigid, non-casting)
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
    // THE VEILS — the bonfire smoke, and the first thing after the last opaque draw.
    g.env.drawVeils(&view);
    // Toad telegraph FX (dust / charge / spit / blood / death motes) — unlit spheres over the opaque geometry.
    g.warren.drawFx();
    g.grief.drawFx();
    g.band.drawFx(); // kobold blood, death motes, and the priest's cast gathering into its staff
    g.hero.drawTrail();
    // Arrow flight streaks — alpha ribbons like the swing trail, so they belong in this unlit group after the opaque geometry, not up with the shafts themselves.
    archermod.drawArrowTrails(&g.arrows);
    // Debug: the blade hit capsule (menu > Debug > Hitboxes) — red while ACTIVE, dim otherwise.
    if (g.menu.hitboxes and g.hero.attacking) {
        const col = if (g.hero.hitActive()) rl.Color.red else mathx.withAlpha(rl.Color.red, 90);
        rl.drawCapsuleWires(g.hero.bladeA, g.hero.bladeB, heromod.BLADE_R, 6, 3, col);
    }
    // Frog hurt spheres (menu > Debug > Hitboxes): dim normally, flaring on a tracked hit.
    if (g.menu.hitboxes) {
        for (g.warren.live()) |*f| {
            if (!f.alive()) continue;
            const col = if (f.flash > 0) rl.Color.orange else mathx.withAlpha(rl.Color.yellow, 80);
            rl.drawSphereWires(f.centerWorld(), f.hurtRadius(), 6, 8, col);
        }
        for (g.grief.live()) |*o| {
            if (!o.alive()) continue;
            const col = if (o.flash > 0) rl.Color.orange else mathx.withAlpha(rl.Color.yellow, 80);
            rl.drawSphereWires(o.centerWorld(), o.hurtRadius(), 8, 10, col);
        }
    }
    // Editor gizmos: op outlines, the selection's instances, the drag in progress.
    if (g.editor.on) g.editor.draw3D(&g.map, &g.env);
    rl.endMode3D();

    if (filtered) g.retro.end();
    // THE GAMEPLAY OVERLAY IS GAMEPLAY'S.
    if (g.editor.on) return;
    g.vignette.draw(); // the vignette darkens the corners the chrome lives in
    drawRestFade(g); // …and the rest's black, under the HUD so the prompt is never on top of it
    drawHurtFlash(g); // red screen-edge pulse when the hero is hit (peripheral feedback)
    // Floating foe HP bars, crisp over the finished frame — one shared path for every group, the ogre included (a regular foe, not a boss — owner's call) and the whole warband with its roles mixed in one array.
    inline for (FOE_GROUPS) |f| drawFoeBars(g, @field(g, f).live());
    drawLockDot(g); // the ER lock-on reticle
    drawDeathOverlay(g); // the YOU DIED card + respawn fade, over everything
}

// The rest's fade to and from black.
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
        // HOLD, then fade.
        const k = if (g.deathFade > RESPAWN_FADE) 1.0 else mathx.clampF(g.deathFade / RESPAWN_FADE, 0, 1);
        rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * k))); // wake at the bonfire
    }
}

// A red damage flash bleeding in from the screen edges, scaled by hero.hurtFlash — Elden Ring's "you got hit" cue.
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

// THE HUD IS ELDEN RING'S, and only in ER's places: vitals bars top-left, the armament grid bottom-left, the debug readout top-right (where ER keeps its compass).
pub fn hud(g: *Game, dt: f32) void {
    // NO HUD INSIDE A REST.
    if (g.rest.active()) return;
    // ER hides the HUD behind its menus and under the death card, and both want the corners clear — a chip trail hanging across an empty HP bar under YOU DIED reads as a fault.
    if (!g.menu.isOpen() and !g.hero.dead) {
        // All three bars are LIVE now.
        hud_.vitals(dt, g.hero.vit.hpFrac(), g.hero.fp.frac(), g.hero.stam.frac(), g.hero.stamRefused / combat.STAM_REFUSE_FLASH, g.hero.stam.windedTo());
        // The one-line translation combat.FlaskKind → hud.FlaskTint: hud takes plain values and knows nothing about the combat layer, so the mapping belongs on this side of the fence.
        hud_.equipment(switch (g.hero.flasks.sel) {
            .crimson => hud_.FlaskTint.crimson,
            .cerulean => hud_.FlaskTint.cerulean,
        }, g.hero.flasks.ready());
        hud_.runes(g.hero.runes.display()); // the ROLLING value, not the banked total
        // …and the INTERACT prompt, when there is something to interact with.
        if (g.rest.near != null) hud_.prompt("E / A  Rest") else if (g.chests.near != null) hud_.prompt("E / A  Open");
    }
    if (g.menu.stats) debugCorner(g);
}

// The debug readout, top-right, toggled by menu > Debug > Stats.
const DBG_ROW = 200; // …the widest debug row, in bytes

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
    else
        gaitLabel(g.hero.moving, g.hero.speed);
    dbgRow(std.fmt.bufPrintZ(&buf, "{s}   {d:.1} m/s", .{ label, g.hero.speed }) catch "", y, hud_.BODY, rgba(150, 156, 164, 255));
    y += hud_.lineH(hud_.BODY) + 4;

    // POS CARRIES ITS HEIGHT, and the ground carries its SLOPE — the two numbers you need to tell "the hill refused my step" from "something else is wrong".
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

    // Foe counts span EVERY group (the combat beats already do) — a toads-only "hits" read silently ignored every blow landed on a skeleton or the giant.
    const h = &g.hero;
    const foesLeft = allAlive(g);
    const foeHits = allHits(g);
    dbgRow(std.fmt.bufPrintZ(&buf, "hero  hp {d:.0}/{d:.0}  poise {d:.0}/{d:.0}  stance {d:.0}/{d:.0}  stam {d:.0}/{d:.0}   foes {d} left  hits {d}", .{
        h.vit.hp,   h.vit.hpMax, h.vit.poise, h.vit.poiseMax, h.vit.stance, h.vit.stanceMax,
        h.stam.cur, h.stam.max,  foesLeft,    foeHits,
    }) catch "", y, hud_.SMALL, rgba(150, 180, 190, 255));
    y += step;

    // World + culling line: how much of the world EXISTS vs how much of it this frame drew.
    dbgRow(std.fmt.bufPrintZ(&buf, "world  props {d}  solids {d}  fires {d}   drawn {d} in {d} cells (both passes)", .{
        g.env.propCount(), g.env.solidCount(), g.env.lightCount(), g.env.stat_draws, g.env.stat_cells,
    }) catch "", y, hud_.SMALL, rgba(150, 175, 195, 255));
    y += step;

    // screen.
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

// One right-aligned debug row, inset by the HUD's own margin so the corner lines up with the bars opposite it.
fn dbgRow(s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    hud_.textRight(s, hud_.MARGIN, y, size, col);
}

/// WHICH GAIT A GROUND SPEED IS, in one place.
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
    // …and the object viewer's two off-screen targets, which are created lazily the first time the gallery opens.
    defer objviewmod.unload();

    const alloc = std.heap.c_allocator;
    const g = alloc.create(Game) catch return;
    defer alloc.destroy(g);
    g.init();

    // Tight near/far for real depth precision — the default 0.01..1000 makes the hero's overlapping boxes z-fight and flicker/invert as the camera moves.
    rl.gl.rlSetClipPlanes(CLIP_NEAR, CLIP_FAR);

    if (mode == .shots) {
        @import("shots.zig").runShots(g);
        return;
    }
    if (mode == .props) {
        @import("shots.zig").runPropShots(g);
        return;
    }

    // Mouse HIDDEN over the window (GLFW_CURSOR_HIDDEN — invisible but NOT locked) and drives the camera; past the window edge it reappears as a normal cursor.
    rl.hideCursor();
    var wasInside = false;
    var bWasDown = false; // gamepad Circle/B: a TAP rolls, a HOLD sprints
    var bHeldT: f32 = 0;
    var lockCycleReady = true; // debounce so one flick cycles the lock-on target once
    // Which device owns the camera.
    var lookPad = false;
    // Rising-edge trackers for rumble: pulse the frame an action BEGINS.
    var wasRolling = false;
    // The swing COUNT, not the `attacking` flag: a chained combo clears that flag and sets it again within one frame, so its rising edge missed every cut after the first (see hero.swings).
    var wasSwings: u32 = 0;
    var wasDead = false;
    var wasRefused: f32 = 0; // …and the refusal flash, whose rising edge IS the ignored input
    var wasStun: combat.StunKind = .none;
    // Footfalls key off the stride phase, not a timer: `hero.phase` is driven by DISTANCE travelled, so a step lands exactly when a foot does at any speed, and slowing down lengthens the gap between them for free.
    var lastPhase: f32 = 0.75;
    defer g.rumble.stop(); // never leave a motor latched after we exit the loop
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime(); // wall-clock dt: feel systems (shake, rumble, fades, tap windows)
        const dt = rawDt * g.menu.timeScale;
        // The map can be swapped under us at any moment (the editor's New / Open / Reload / undo), and the clamp is the one piece of world size that lives outside `materialize`.
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

        // Alt+Enter toggles borderless-windowed fullscreen (no exclusive mode-switch, so the mouse stays usable elsewhere).
        if (rl.isKeyPressed(.enter) and (rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt))) {
            rl.toggleBorderlessWindowed();
            g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());
        }
        if (rl.isWindowResized()) g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());

        // Set from the menu in ONE place, before the branch, so the flag can never disagree with which path actually ran: a held hero breathes but his combat clocks stop (see hero.held).
        if (g.editor.on) {
            // THE CURSOR COMES BACK.
            rl.showCursor();
            switch (g.editor.update(&g.map, &g.env, rawDt)) {
                .none => {},
                .leave => {
                    g.editor.on = false;
                    g.menu.screen = .main;
                    rl.hideCursor(); // back to the gameplay rule: the mouse IS the camera
                },
                // F5 PLAYTEST: drop straight into the live world at the editor's viewpoint, so the thing you just dressed is the thing you are standing in.
                .playtest => {
                    g.editor.on = false;
                    rl.hideCursor();
                    g.hero.pos = mathx.ground(g.editor.cam.target.x, g.editor.cam.target.z);
                    g.hero.pos = g.env.resolveActor(g.hero.pos, HERO_R);
                    plantActor(g, &g.hero.pos); // …on the ground, AFTER the push-out moved him in XZ
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
            // …and the chests with them, for the same reason and off the same source of truth: moving, adding or deleting a box has to move the box you can SEE.
            rehomeChests(g);
            // …AND THE GRIP GOES QUIET, envelopes still decaying — the same call the pause card makes, for the same reason.
            g.rumble.update(rawDt, false);
            drawScene(g);
            editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, rawDt);
            rl.endDrawing();
            continue;
        }

        g.hero.held = g.menu.isOpen();
        if (g.menu.isOpen()) {
            // World holds while the menu is up: no camera/move input, but the hero keeps breathing (idle update, zero travel) so the scene stays alive.
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
            // Poison the pad-B tap window: B both backs out of the menu AND rolls, so without this the release of the B that closed the menu fires an instant roll.
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
            g.menu.draw(&g.retro, &g.bag);
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
        // …and the tail of it: the field fading back up under your feet, which is ordinary gameplay with a black veil over it, so it runs THROUGH the loop rather than around it.
        g.rest.update(rawDt);
        g.rest.look(g.hero.pos);
        sfx.tickStreams();

        // Lock-on toggle: R3 (pad) / middle-mouse (kb+m).
        const lockPressed = rl.isMouseButtonPressed(.middle) or
            (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .right_thumb));
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
        var wheel = rl.getMouseWheelMove();
        const padRX: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_x) else @as(f32, 0);
        // Both look axes are read HERE, before the lock branch, because the PROBE is written for both paths below.
        const padRY: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_y) else @as(f32, 0);
        // The yaw BEFORE any look input lands, so the probe can report what the camera actually turned this frame rather than what the devices claimed.
        const yawBefore = g.rig.yaw;
        // RAW stick magnitude, before any deadzone.
        const padMag = @sqrt(padRX * padRX + padRY * padRY);
        if (g.lock) |li| {
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
            // MOUSE_WAKE, not zero: a hidden-but-uncaptured cursor picks up a pixel of jitter from the desk, and one pixel used to be enough to take the camera off the stick.
            const mouseLook = inside and wasInside and (@abs(md.x) + @abs(md.y)) > MOUSE_WAKE;
            // at 0.15-0.25, past LOOK_DEADZONE, so claiming on anything that merely clears the deadzone pins the latch to PAD on frame one and the mouse never works again.
            const padClaim = padMag > LOOK_CLAIM;
            // …and LAST DEVICE WINS has to be resolved as a TIE, not by statement order.
            if (padClaim and !mouseLook) lookPad = true;
            if (mouseLook and !padClaim) lookPad = false;
            if (lookPad) {
                // rawDt, NOT dt: looking around is a FEEL system like the shake and the rumble, and it lives on the wall clock.
                g.rig.orbit(
                    -look.x * look.mag * LOOK_RATE_YAW * rawDt,
                    look.y * look.mag * LOOK_RATE_PITCH * rawDt,
                );
            } else if (inside and wasInside) {
                g.rig.rotate(md.x, md.y);
            }
        }
        // …and record what BOTH devices said, deadzone or no, for the debug readout — on EITHER path, so the readout still tracks the sticks while locked on.
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
        // PAD ZOOM MOVED TO D-PAD LEFT/RIGHT.
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .left_face_right)) wheel += 1; // D-pad right = zoom in
            if (rl.isGamepadButtonPressed(PAD, .left_face_left)) wheel -= 1; // D-pad left = zoom out
        }
        if (wheel != 0) g.rig.zoom(wheel);

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

        // Sword attacks (ER layout): R1/RB or LMB = light, R2/RT or Shift+LMB = heavy.
        var lightReq = false;
        var heavyReq = false;
        if (rl.isMouseButtonPressed(.left)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) heavyReq = true else lightReq = true;
        }
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_1)) lightReq = true;
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_2)) heavyReq = true;
        }

        // STAMINA GATES THE SPRINT AT THE SOURCE.
        var mv = gatherMove();
        if (!g.hero.stam.canSprint()) mv.speed = @min(mv.speed, RUN_SPEED);
        // …and WATER caps it the same way, for the same reason: past the knee a leg stops swinging and starts pushing.
        const wade = wadeDrag(g);
        if (wade < 1.0) mv.speed = @min(mv.speed, WALK_SPEED * wade);
        // Poise/stance regenerate every frame (relent and pressure resets — Elden Ring).
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
            }
            g.hero.steerQueuedRoll(rollDir(g, mv));
            // The draught is NOT buffered — it is the one action you should never find yourself committed to because of a press you made a second ago in a panic.
            if (drinkReq and g.hero.startDrink()) sfx.play(.flask_drink);
        }
        // The sprint is the only CONTINUOUS drain, and only while he is actually running on his feet — a roll's lunge and an attack's step travel fast but are not sprints.
        g.hero.sprinting = sprintingMove(mv) and
            !g.hero.rolling and !g.hero.attacking and !g.hero.dead and !g.hero.staggered();
        // …and the shield, AFTER the sprint (there is no running block — see hero.setGuard).
        g.hero.setGuard(guardHeld);
        // BEHIND THE SHIELD HE SHUFFLES.
        if (g.hero.guarding) mv.speed = @min(mv.speed, WALK_SPEED * heromod.GUARD_SPEED);

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        // The slope under him, eased into the rig BEFORE it poses — every branch below ends in a `pose()`, so this has to be settled first or the lean is always one frame stale.
        leanToGround(g, dt);
        // WHERE EVERY FOE STOOD BEFORE IT ACTED — one row per group, walked off FOE_GROUPS like every other per-group pass here. Four buffers named by hand and eight calls kept in lockstep is exactly the shape FOE_GROUPS exists to kill, and this one's failure mode is the silent one: a group whose snapshot nobody took is a group the slope limit never gates, so it walks up cliffs.
        // Every row is sized to the WIDEST group (the warband carries three kinds in one array); `snapshotPos` and `gateTerrain` both stop at the buffer's own length.
        var wasPos: [FOE_GROUPS.len][koboldmod.CAP]rl.Vector3 = undefined;
        inline for (FOE_GROUPS, 0..) |f, gi| snapshotPos(@field(g, f).live(), &wasPos[gi]);
        if (g.hero.dead) {
            g.hero.updateDeath(dt); // collapse → respawn
            // The frame he returns, the WORLD reloads with him (ER-style): every foe re-homed at full health, arrows cleared, lock dropped.
            if (!g.hero.dead) resetFoes(g);
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt); // reeling — wide open
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.drinking) {
            g.hero.updateDrink(dt); // committed, and planted — the flask's whole cost
        } else if (g.hero.attacking) {
            // Committed — a short step into the cut; while LOCKED the recovery tail re-squares onto the target (a whiffed swing recovers turning fast).
            g.hero.updateAttack(dt, PLAY_HALF, lockYaw);
        } else {
            moveHero(g, dt, mv, lockYaw);
        }
        // Knot hunts, skeletons kite + loose; the hero's swept blade damages/staggers both sides, and a connecting chomp/lunge/arrow returns its blow to the hero.
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
        // Blade lands on the skeletons; then they act — kite and loose from the nock at the hero's centre of mass (arrow homing + arc finish the job).
        for (g.line.live()) |*a| {
            if (a.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), heroAimPoint(g));
            }
        }
        // THE WARBAND acts as one group, because the priest's heal has to see the whole band (see kobold.Warband).
        if (g.band.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnStone)) |b| {
            // A chop is the heavier of the two, and it is the one that carries poise — split the felt weight on the blow's own numbers rather than on which creature threw it.
            _ = heroTakes(g, b, b.hit.poise >= koboldmod.ZERK_HIT.poise, true);
        }
        // The lids swing and the "which one is in reach" answer is recomputed — once, here, so the prompt the player reads and the button they then press cannot disagree about which box they mean.
        g.chests.update(dt, g.hero.pos);
        // …and the ground has its say about all of them: every step a foe just took is re-taken through the slope limit, so none of them walks up anything the hero couldn't.
        inline for (FOE_GROUPS, 0..) |f, gi| gateTerrain(g, @field(g, f).live(), &wasPos[gi]);
        // Arrows in flight: gentle homing + arc, then a strike lands a chomp-weight blow.
        for (&g.arrows) |*ar| {
            if (!ar.live) continue;
            ar.hit = false;
            // The GROUND under the shaft, so it plants in a hillside instead of diving through it to find y = 0 — and the hero's centre measured from HIS ground, not from the datum, or an archer shooting up a bank aims at the hero's knees.
            archermod.stepArrow(ar, g.hero.pos, heroCenterY(g), g.env.groundAt(ar.pos.x, ar.pos.z), g.hero.iFramed(), arrowCover(g, ar, dt), dt);
            if (ar.hit) {
                // It found the hero.
                const blow = foemod.Blow{
                    .hit = if (ar.stone) koboldmod.STONE_HIT else archermod.ARROW_HIT,
                    .from = mathx.addV(g.hero.pos, mathx.scaleV(ar.vel, -1)),
                };
                // The BEAT is skipped on a corpse.
                const out: combat.HitOutcome = if (g.hero.dead) .ignored else heroTakes(g, blow, false, false);
                // …and WHAT IT STRUCK picks that voice: boards if the shield caught it, flesh if not.
                if (out == .taken or out == .ignored) sfx.play(.arrow_hit);
            } else if (ar.stuck and ar.age == 0) {
                // It STUCK without connecting — into cover or into the earth, and that gets its own sound: a shaft thunking off the pillar you ducked behind is the game telling you the cover WORKED.
                sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
            }
        }
        // Blade connected this frame (a foe's hit count climbed) → hit pulse + frame crack sized to the swing; a kill adds the thunk (via justDied, since dissipation delays the aliveCount drop).
        if (allHits(g) > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
            sfx.play(if (g.hero.atkHeavy) .hit_heavy else .hit_light);
        }
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
        // …and EVERYTHING SETTLES ONTO THE GROUND, last: collision moves actors in XZ (out of walls, off each other), so their height is only known once that is done.
        groundActor(g, &g.hero.pos, dt);
        inline for (FOE_GROUPS) |f| {
            for (@field(g, f).live()) |*a| groundActor(g, &a.pos, dt);
        }
        g.rig.tickShake(rawDt); // impact shake decays on wall-clock time (bakes this frame's jitter)
        // …and the boom shortens rather than burying the eye in the hillside behind him (see camera.followClear).
        g.rig.followClear(g.hero.shoulderPoint(), &g.env, envGroundAt);
        // THE EARS RIDE THE CAMERA, not the hero — the pan has to agree with what is on screen, and the camera is the eye.
        sfx.listen(g.rig.cam.position, g.rig.rightXZ());
        sfx.ambience(rawDt); // keep the wind bed alive, and let the odd bird call over it
        footsteps(g, &lastPhase);

        // Rising-edge action pulses: roll whump, swing effort (heavy > light), death swell.
        if (g.hero.rolling and !wasRolling) {
            g.rumble.play(rumblemod.roll);
            sfx.play(.roll);
        }
        // EVERY cut is heard, chained ones included: the counter ticks in hero.startAttack, which is the one door a swing can come through.
        if (g.hero.swings != wasSwings) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.swing_heavy else rumblemod.swing_light);
            sfx.play(if (g.hero.atkHeavy) .swing_heavy else .swing_light);
            wasSwings = g.hero.swings;
        }
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
        wasRolling = g.hero.rolling;
        wasDead = g.hero.dead;
        g.rumble.update(rawDt, rl.isGamepadAvailable(PAD));

        drawScene(g);
        hud(g, rawDt);
        rl.endDrawing();
    }
}

fn footsteps(g: *Game, last: *f32) void {
    const h = &g.hero;
    // Nothing plants during a roll, a stagger or a death — those anims move the feet on their own terms and a stride-phase step under them lands nowhere near a foot.
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
    // Quieter the slower he goes, on top of the voice change — a careful walk should not land as hard as a sprint that happens to be crossing the same phase.
    const vol = mathx.clampF(0.45 + 0.55 * h.speed / SPRINT_SPEED, 0.35, 1.0);
    sfx.playAt(id, vol);
    if (stepOverlay(g, h.pos.x, h.pos.z)) |over| sfx.playAt(over, vol);
}

/// WHAT HE IS STANDING ON, as an extra voice STACKED on the boot rather than a boot of its own.
fn stepOverlay(g: *const Game, x: f32, z: f32) ?sfx.Id {
    // WATER FIRST, and whatever is painted under it loses: you are standing in the lake, not on its bed.
    if (g.env.inWater(x, z, 1.0)) return .step_water;
    const i = g.map.soilIndex(x, z) orelse return null;
    const v = g.map.soil[i];
    if (v >= worldfmt.Soil.N) return null;
    return switch (@as(worldfmt.Soil, @enumFromInt(v))) {
        .stone => .step_stone,
        else => null, // dirt, turf, silt, ash, moss and unpainted ground are all the plain boot
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
        .none => {}, // the menu will not offer it (item.usable), so this is unreachable in practice
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
            // The break is a stagger and gets the stagger's weight — plus the boards going, which is the sound that says WHY you are suddenly wide open.
            g.rumble.play(rumblemod.guard_break);
            g.rig.addShake(SHAKE_GUARD_BREAK);
            sfx.play(.guard_break);
        },
    }
    return out;
}

fn heroBlockBeat(g: *Game, h: combat.Hit) void {
    const w = mathx.clampF(h.dmg / BLOW_HEAVIEST, BLOCK_FELT_MIN, 1.0);
    g.rumble.play(if (w >= BLOCK_FELT_HEAVY) rumblemod.guard_block_heavy else rumblemod.guard_block);
    g.rig.addShake(SHAKE_BLOCK * w);
    sfx.play(.guard_block);
}

fn allHits(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f).totalHits();
    return n;
}
fn allAlive(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f).aliveCount();
    return n;
}
fn anyFoeDied(g: *const Game) bool {
    inline for (FOE_GROUPS) |f| {
        if (@field(g, f).anyDied()) return true;
    }
    return false;
}
fn allRunes(g: *const Game) u32 {
    // The band's payout is PER ROLE (a priest is worth the most), so its own `runesDropped` does the summing rather than taking a flat per-group figure like the other three.
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f).runesDropped();
    return n;
}

// The hero's blade this frame as plain data for the foe hit test (endpoints guard→tip, plus last frame's for the swept test; active only inside the strike window).
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
    // Each actor resolves against the solids in its OWN neighbourhood (env.resolveActor queries the prop grid).
    var hp = g.env.resolveActor(g.hero.pos, HERO_R);
    for (g.warren.live()) |*f| {
        if (f.alive() and !f.airborne()) hp = collision.pushOutCircle(hp, HERO_R, f.pos, f.bodyR());
    }
    for (g.line.live()) |*a| {
        if (a.alive()) hp = collision.pushOutCircle(hp, HERO_R, a.pos, a.bodyR());
    }
    for (g.grief.live()) |*o| {
        if (o.alive()) hp = collision.pushOutCircle(hp, HERO_R, o.pos, o.bodyR());
    }
    g.hero.pos = mathx.approachV(g.hero.pos, inBounds(hp), step);

    for (g.warren.live(), 0..) |*f, i| {
        if (!f.alive() or f.airborne()) continue;
        var fp = g.env.resolveActor(f.pos, f.bodyR());
        fp = collision.pushOutCircle(fp, f.bodyR(), g.hero.pos, HERO_R);
        for (g.warren.live(), 0..) |*o, j| {
            if (i == j or !o.alive() or o.airborne()) continue;
            fp = collision.pushOutCircle(fp, f.bodyR(), o.pos, o.bodyR());
        }
        f.pos = mathx.approachV(f.pos, inBounds(fp), step);
    }

    // Archers yield last: each pushed out of world, hero, every grounded toad, and fellow archers (same easing so a kite step into a wall slides, not warps).
    for (g.line.live(), 0..) |*a, i| {
        if (!a.alive()) continue;
        var ap = g.env.resolveActor(a.pos, a.bodyR());
        ap = collision.pushOutCircle(ap, a.bodyR(), g.hero.pos, HERO_R);
        for (g.warren.live()) |*f| {
            if (f.alive() and !f.airborne()) ap = collision.pushOutCircle(ap, a.bodyR(), f.pos, f.bodyR());
        }
        for (g.line.live(), 0..) |*o, j| {
            if (i == j or !o.alive()) continue;
            ap = collision.pushOutCircle(ap, a.bodyR(), o.pos, o.bodyR());
        }
        a.pos = mathx.approachV(a.pos, inBounds(ap), step);
    }

    // The ogre yields to the WORLD (walls/columns) only, never to the tiny hero (who yields above), so it reads as immovable bulk.
    for (g.grief.live()) |*o| {
        if (!o.alive()) continue;
        const op = g.env.resolveActor(o.pos, o.bodyR());
        o.pos = mathx.approachV(o.pos, inBounds(op), step);
    }

    // THE WARBAND yields to everything, itself included — a pack that walked through each other would stack three kobolds on one spot, and a knot of them is the whole point of the encounter.
    for (g.band.live(), 0..) |*k, i| {
        if (!k.alive()) continue;
        var kp = g.env.resolveActor(k.pos, k.bodyR());
        kp = collision.pushOutCircle(kp, k.bodyR(), g.hero.pos, HERO_R);
        for (g.band.live(), 0..) |*o, j| {
            if (i == j or !o.alive()) continue;
            kp = collision.pushOutCircle(kp, k.bodyR(), o.pos, o.bodyR());
        }
        k.pos = mathx.approachV(k.pos, inBounds(kp), step);
    }
}

// A reference to a locked foe across the heterogeneous groups; lock-on and the reticle dispatch through the foe* accessors, so every foe type is lockable.
const FoeKind = worldfmt.FoeKind;
const FoeRef = struct { kind: FoeKind, idx: usize };
// THE THREE KOBOLD ROLES ALL LIVE IN ONE ARRAY (`kobold.Warband` — the priest has to be able to see its friends), so unlike the other groups a FoeRef's `kind` does not pick the array: all three index `g.band.band`.
fn bandIdx(r: FoeRef) ?usize {
    return if (koboldmod.roleOf(r.kind) != null) r.idx else null;
}
/// ASK ONE QUESTION OF WHATEVER A `FoeRef` POINTS AT. The three accessors below were this same `bandIdx` + four-arm switch written out three times over, differing only in the method they called — so a fifth creature was three identical edits in three places, which is exactly the silent-miss shape `FOE_GROUPS` exists to kill for the per-group passes above.
fn askFoe(comptime T: type, g: *const Game, r: FoeRef, comptime ask: anytype) T {
    if (bandIdx(r)) |i| return ask(&g.band.band[i]);
    return switch (r.kind) {
        .toad => ask(&g.warren.frogs[r.idx]),
        .archer => ask(&g.line.archers[r.idx]),
        .ogre => ask(&g.grief.ogres[r.idx]),
        .berserker, .priest, .slinger => unreachable, // handled above
    };
}
fn foePos(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype) rl.Vector3 {
            return f.pos;
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
fn lockValid(g: *const Game, r: FoeRef) bool {
    return foeLockable(g, r) and mathx.distXZ(g.hero.pos, foePos(g, r)) <= MAX_LOCK_R + 2.0;
}

// A world point projected to the screen, or null if nearer than the near-clip plane — the shared front-of-camera cull for the lock reticle, foe HP bars, and lock-screen-x.
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

// The foe nearest screen-centre and in range (ER locks what you look at); null if none, so the caller recenters.
fn acquireLock(g: *Game) ?FoeRef {
    const cx = @as(f32, @floatFromInt(rl.getScreenWidth())) * 0.5;
    var best: ?FoeRef = null;
    var bestScore: f32 = 1e9;
    considerLock(g, g.warren.live(), .toad, cx, &best, &bestScore);
    considerLock(g, g.line.live(), .archer, cx, &best, &bestScore);
    considerLock(g, g.grief.live(), .ogre, cx, &best, &bestScore);
    // …and the band through the SAME helper, on a null group kind (see `memberKind`) — it used to be a hand-copied inline loop here and a second one in `cycleLock`, because the helpers took one kind for a whole group.
    considerLock(g, g.band.live(), null, cx, &best, &bestScore);
    return best;
}

/// WHICH KIND ONE MEMBER OF A GROUP IS. The warband carries three kinds in ONE array (the priest has to see its friends), so for it the member answers and not the group; every other array holds one kind and passes it in.
fn memberKind(f: anytype, group: ?FoeKind) FoeKind {
    if (comptime @hasField(std.meta.Child(@TypeOf(f)), "role")) return koboldmod.kindOf(f.role);
    return group.?;
}

// One group's contribution to acquireLock — generic over the foe type (the shared contract).
fn considerLock(g: *Game, foes: anytype, kind: ?FoeKind, cx: f32, best: *?FoeRef, bestScore: *f32) void {
    for (foes, 0..) |*f, i| {
        if (!f.alive() or f.dying() or mathx.distXZ(g.hero.pos, f.pos) > MAX_LOCK_R) continue;
        const r = FoeRef{ .kind = memberKind(f, kind), .idx = i };
        const sx = lockScreenX(g, r) orelse continue;
        const score = @abs(sx - cx);
        if (score < bestScore.*) {
            bestScore.* = score;
            best.* = r;
        }
    }
}

// Switch to the next in-range foe whose screen-x lies on `dir` side (-1 left / +1 right) of the current target — the right-stick / mouse flick cycle, across both groups.
fn cycleLock(g: *Game, dir: f32) void {
    const cur = g.lock orelse return;
    const curX = lockScreenX(g, cur) orelse return;
    var best: ?FoeRef = null;
    var bestGap: f32 = 1e9;
    considerCycle(g, g.warren.live(), .toad, cur, curX, dir, &best, &bestGap);
    considerCycle(g, g.line.live(), .archer, cur, curX, dir, &best, &bestGap);
    considerCycle(g, g.grief.live(), .ogre, cur, curX, dir, &best, &bestGap);
    considerCycle(g, g.band.live(), null, cur, curX, dir, &best, &bestGap);
    if (best) |b| g.lock = b;
}
fn considerCycle(g: *Game, foes: anytype, kind: ?FoeKind, cur: FoeRef, curX: f32, dir: f32, best: *?FoeRef, bestGap: *f32) void {
    for (foes, 0..) |*f, i| {
        const r = FoeRef{ .kind = memberKind(f, kind), .idx = i };
        // Against the MEMBER's own kind, which is what makes one test serve the warband too: a slot in the band array is one creature of one role, so `cur` naming that role at that index is `cur` naming that creature.
        if ((cur.kind == r.kind and cur.idx == i) or !f.alive() or f.dying()) continue;
        if (mathx.distXZ(g.hero.pos, f.pos) > MAX_LOCK_R) continue;
        const sx = lockScreenX(g, r) orelse continue;
        const gap = (sx - curX) * dir;
        if (gap > 5.0 and gap < bestGap.*) {
            bestGap.* = gap;
            best.* = r;
        }
    }
}

// The world-reload half of a hero death (ER: dying resets the field).
fn resetFoes(g: *Game) void {
    rehomeFoes(g);
    g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
    g.lock = null;
}

// A foe's bar only appears once you've HURT it, and lingers this long after the last hit — so untouched foes stay unmarked and the bar fades from view when you disengage.
const HURT_BAR_WINDOW = 5.0;

// Floating HP bars over ANY foe group (shared foe contract, one loop for all).
fn drawFoeBars(g: *Game, foes: anytype) void {
    const cam = g.rig.cam;
    for (foes) |*f| {
        if (!f.alive() or f.dying()) continue; // no bar over a corpse dissolving out
        if (f.vit.sinceHit > HURT_BAR_WINDOW) continue; // only after a recent hit
        const s = projectToScreen(cam, f.topWorld()) orelse continue; // skip if behind the camera
        hud_.foeBar(s.x, s.y, f.vit.hpFrac(), f.staggered()); // size/colour/lift all live in hud
    }
}

// The glowing white reticle on the locked foe (ER's dot) — 2D + crisp, drawn after the 3D pass.
fn drawLockDot(g: *Game) void {
    const li = g.lock orelse return;
    const s = projectToScreen(g.rig.cam, foeLockPoint(g, li)) orelse return; // skip if behind the camera
    const x: i32 = @intFromFloat(s.x);
    const y: i32 = @intFromFloat(s.y);
    // A glowing white dot — a radial GRADIENT glow (bright centre → transparent edge) with a small crisp core, no dark halo.
    rl.drawCircleGradient(x, y, 15, rgba(255, 255, 255, 175), rgba(255, 255, 255, 0));
    rl.drawCircle(x, y, 2, rl.Color.white); // crisp hot centre
}

