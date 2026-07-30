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
const sfx = @import("audio.zig"); // the procedural sound bank — every voice synthesized at launch

const v3 = mathx.v3;
const rgba = mathx.rgba;

// THE pad index, from rumble.zig — input polling and the XInput vibration calls MUST target the
// same controller, and rumble.PAD says so. It was said in a comment while 23 call sites here (and
// 12 in menu.zig) hardcoded a literal 0, so honouring it meant finding all 35 by hand.
const PAD = rumblemod.PAD;

const SCREEN_W = 1280;
const SCREEN_H = 800;

// Locomotion speeds live with the hero rig (single source of truth); gait blends tune to
// these, so reference them here to prevent drift.
const WALK_SPEED = heromod.WALK_SPEED; // keyboard walk / gentle left-stick tilt
const RUN_SPEED = heromod.RUN_SPEED; // full left-stick tilt (light tilt scales down toward walk)
const SPRINT_SPEED = heromod.SPRINT_SPEED; // hold Circle/B (or Shift): dash/sprint
const TURN_RATE = 12.0; // rad/sec the hero yaws toward its heading (souls turn briskly)
const STRAFE_SPEED = 0.85; // LOCKED-ON sideways travel, as a fraction of forward (ER is anisotropic
//   too). Deliberately mild — the owner wants the cadence calmed WITHOUT slowing him down much —
//   and it is the last 15% that lands the sidestep's step rate on the forward walk's. See moveHero.
const STICK_DEADZONE = 0.16; // left-stick move deadzone — RADIAL, see stickRadial
// Right-stick LOOK deadzone. Still bigger than the move stick's: a look stick's resting deflection
// turns the whole world, where the move stick's only nudges the hero a few centimetres. It had been
// pushed to 0.22 to stop "moving right rotates the cam right a bit as well" — but that was the
// mouse-emulation cross-talk the look-device LATCH below now kills at the source, and a radial 0.22
// throws away a quarter of the stick's travel before anything happens, which is what a look stick
// reads as DEAD.
const LOOK_DEADZONE = 0.14;
/// How hard the right stick must be pushed to TAKE THE CAMERA off the mouse — a different question
/// from how hard it must be pushed to turn (`LOOK_DEADZONE`), and keeping them the same number is what
/// let a worn pad kill mouse look outright (see the latch in run()).
///
/// Sits well clear of any resting deflection ON PURPOSE. A tired analogue stick rests anywhere up to
/// ~0.25 and the deadzone is 0.14, so a claim gated on the deadzone is a claim a drifting stick makes
/// on every frame for ever. 0.40 is past anything a stick does sitting still and nowhere near a real
/// push, so a player reaching for the stick still gets the camera on the first flick.
const LOOK_CLAIM = 0.40;
// Pixels of mouse travel in one frame that count as the player REACHING FOR THE MOUSE — see the
// look-device latch. A hidden, uncaptured cursor collects a pixel of jitter from the desk, and
// without a floor here that jitter takes the camera away from the stick mid-fight.
const MOUSE_WAKE: f32 = 2.0;
// ── THE LOOK STICK (ER's) ── three dials, and the split between the first two is the point.
// YAW is unbounded and a full turn at this rate takes ~2.3 s. PITCH is CLAMPED to 1.35 rad end to
// end (camera.PITCH_MIN..PITCH_MAX), so running it at the yaw rate slams the camera from the sky to
// the dirt in half a second — the stick has no fine vertical range at all. Every third-person
// console camera, ER included, runs vertical appreciably slower than horizontal for exactly this.
const LOOK_RATE_YAW = 2.7; // rad/sec orbit at full right-stick deflection
const LOOK_RATE_PITCH = 1.6; // …and vertical, deliberately slower (see above)
// Response shape past the deadzone: 1 = linear, >1 = fine aim near the centre with the SAME top
// rate still reached at the rim. A linear look stick has one usable speed — its fastest.
const LOOK_CURVE = 1.5;
const ROLL_TAP_MAX = 0.22; // Circle/B released before this (real seconds) = a dodge tap; longer = a sprint hold
// NO run-unlock hold, ever (owner's rule, see AGENTS.md): the stick IS the speed — tilt
// maps straight to ground speed every frame, and keyboard movement runs immediately.

// Impact shake fed to the camera rig (trauma² response in camera.zig), sized so a light
// reads as a tick and a slam cracks the frame. NO hitstop — impact weight is shake +
// rumble + reaction anims only.
const SHAKE_HIT_LIGHT = 0.16;
const SHAKE_HIT_HEAVY = 0.26;
const SHAKE_KILL = 0.38;
const SHAKE_HURT = 0.42;
const SHAKE_HURT_HEAVY = 0.62;
const SHAKE_DEATH = 0.85;
// The YOU DIED tail, in two beats. The HOLD is the important one: black used to be reached on
// exactly the frame the respawn fired and to start lifting on the very next one, so the card cut
// straight into a lit meadow and the whole sequence read as a glitch rather than as a death. A beat
// of solid nothing is what lets it land.
const RESPAWN_HOLD = 0.55; // seconds of FULL black after the respawn…
const RESPAWN_FADE = 0.9; // …then this long fading up into the fresh world

// Hero movement clamp: the MAP's bounds inset so travel/rolls can't reach the edge. One source for
// moveHero, the roll and attack updates, every foe's update and the --shot harness.
//
// A `var` refreshed from the live map each frame, because the map decides the world's size and the editor
// can swap it at any moment. It was a COMPILE-TIME `envmod.HALF - 2`, which is why a map's `half:` governed
// the cliff ring, the cover and the soil grid but NOT where the player could walk — resize and the hero
// still stopped at the old bound with the rock a hundred metres out. Two dozen call sites read this name,
// so keeping it a name rather than threading a parameter kept the fix to one line.
pub var PLAY_HALF: f32 = worldfmt.DEFAULT_HALF - envmod.PLAY_INSET;

// Hero footprint radius for ground collision (see collision.zig). Defined in foe.zig alongside
// foe.HERO_REACH, so a foe's attack shapes can be reasoned about against how close he can GET.
const HERO_R = foemod.HERO_R;

// Skeletal-archer arrows: shared pool of in-flight + stuck shafts, plus the hero centre-of-
// mass height archers aim at and arrows test strikes against.
const MAX_ARROWS = 24;
pub const HERO_CENTER_Y = 1.0;

// Collision correction is rate-limited so a large depenetration eases in over a few frames
// (smooth slide, not a choppy warp). Set above the fastest actor speed so wall contact
// still resolves firmly (no sinking).
const COLLIDE_RATE = 11.0; // world units / sec

// Depth clip planes, set once in run(). Invariant: projectToScreen's PROJECT_NEAR must EQUAL CLIP_NEAR —
// both read this, never the literal.
//
// DEPTH PRECISION IS SET BY THE NEAR PLANE, and it is what makes distant detail FLICKER: resolution at
// depth z goes as z²·(1/near − 1/far)/2^24, so at 0.2 the gap between steps at 250 m was ~1.9 cm — and
// props.zig deliberately overlaps its facing blocks by a couple of cm, so those overlaps fell inside one
// step and z-fought. 0.55 buys 2.5x the precision (~0.75 cm at 250 m) for nothing: the orbit rig never puts
// the eye nearer than camera.MIN_DIST (2.4), and the closest --shot framing is 2.0.
const CLIP_NEAR = 0.55;
const CLIP_FAR = 320.0;

// ── lock-on (Elden Ring) ──
const MAX_LOCK_R = 17.0; // won't acquire, and drops, a foe beyond this
const LOCK_CAM_EASE = 9.0; // exponential ease rate for the lock-on camera swing (quick, snap-free)
const LOCK_PITCH = 0.24; // framing pitch while locked (the toads sit low)
const LOCK_FLICK = 0.65; // right-stick |x| past this cycles to the next target

// Framebuffer clear tone — matches the sky shader's horizon band (displayed gfx.HAZE) so
// any sliver the sky quad misses stays invisible.
const CLEAR = rgba(80, 76, 69, 255);

/// What the two look devices were saying this frame, and which one owns the camera. Raw values,
/// deliberately — the point is to see what arrives BEFORE the deadzone eats it.
/// …plus what the camera ACTUALLY DID with them. The raw pair alone cannot separate the three things
/// that feel identical on screen — a stick resting off centre, a cursor collecting desk jitter, or a
/// rate that is simply too high — because all three show up as numbers moving. So the probe also
/// carries `mag` (the stick's RAW magnitude, which is the only number that can tell a resting
/// deflection from a real push — read it against LOOK_DEADZONE and LOOK_CLAIM) and `dyaw` (degrees the
/// camera turned this frame: zero with your hands off means nothing in here is drifting and the
/// problem is sensitivity).
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
    arrowModel: rl.Model, // shared arrow mesh, drawn per live/stuck arrow with its own matrix
    arrows: [MAX_ARROWS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_ARROWS,
    rig: cameramod.CamRig,
    lock: ?FoeRef = null, // ER lock-on: which foe (toad or skeleton) is locked, or null
    rumble: rumblemod.Rumble = .{}, // controller vibration, keyed to combat beats
    deathFade: f32 = 0, // post-respawn fade-from-black seconds remaining (armed while dead)
    /// THE LOOK-INPUT PROBE — raw, per frame, straight onto the debug readout. The camera yaw is
    /// written in exactly four places and none of them can see the movement stick, so "walking
    /// forward turns the camera" cannot come from the code: it is one of the two INPUT DEVICES
    /// saying something the player is not. This is how you find out which, in one glance, instead
    /// of guessing: walk straight with Stats up and read which pair is non-zero.
    probe: LookProbe = .{},

    // Built IN PLACE rather than returned by value: Env alone is ~450 KB of flat prop/grid
    // arrays, and a by-value Game would copy all of it across the stack on the way out.
    fn init(g: *Game) void {
        g.scene = gfx.Scene.init();
        g.sky = gfx.Sky.init();
        g.vignette = gfx.Vignette.init();
        g.retro = gfx.Retro.init(rl.getScreenWidth(), rl.getScreenHeight());
        g.menu = .{}; // opens on the main screen: Continue / Debug / Quit
        worldfmt.loadOrPanic(worldfmt.START_MAP, &g.map);
        PLAY_HALF = g.map.half - envmod.PLAY_INSET; // before anything spawns against it
        g.env.build(&g.scene); // meshes once…
        // THE PAINTED FIELDS GO UP FIRST. `materialize`'s cover scatter asks `env.inWater` where it may
        // sow, and that reads the water field — uploaded after, the first world off a map with a painted
        // lake grows grass across the middle of it, and stays that way until something else rebuilds.
        g.env.uploadSoil(&g.map);
        g.env.uploadWater(&g.map);
        g.env.materialize(&g.map); // …then the world from the map, re-runnable per edit
        g.hero = heromod.Hero.init(g.scene.shader);
        g.hero.pos = mathx.ground(0, 4); // start just south of the ruin avenue
        g.hero.facing = std.math.pi; // facing -Z, into the columns
        g.hero.setSpawn(g.hero.pos, g.hero.facing); // where a death returns him
        g.hero.pose();
        g.warren = frogmod.Knot.init(g.scene.shader);
        g.line = archermod.Line.init(g.scene.shader);
        g.grief = ogremod.Grief.init(g.scene.shader);
        // Foes come from the MAP, so the groups can only be homed once it is loaded — init
        // builds the shared meshes and nothing else.
        g.warren.reset(&g.map);
        g.line.reset(&g.map);
        g.grief.reset(&g.map);
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
        // Fields that would otherwise take their struct-literal defaults; set explicitly
        // because there is no literal to default from any more.
        g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
        g.editor = .{};
        g.lock = null;
        g.rumble = .{};
        g.deathFade = 0;
        // …the look probe included. It was the one field this block missed, and `Game` is built in
        // place from `alloc.create`, so its default never ran: the readout printed raw heap bytes as
        // floats, and `pad` is a BOOL — reading one that is neither 0 nor 1 is illegal behaviour, not
        // just a wrong caption.
        g.probe = .{};
    }
};

// ── input → intent ─────────────────────────────────────────────────────────────────
// fx = camera-right axis, fz = camera-forward axis (pre-normalization); speed = resolved
// ground speed this frame (0 = idle). ZERO input lag (owner's rule): the analog tilt maps
// STRAIGHT to ground speed every frame — light tilt walks, full tilt runs, NOW — and
// keyboard movement is an immediate run (hold sprint for the dash). No hold gates.
const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

/// A STICK, DEADZONED RADIALLY — direction and magnitude, kept apart.
///
/// Deadzoning each axis on its own is a SQUARE deadzone and it is wrong twice over. It chops the
/// axes independently, so the angle you get is NOT the angle the thumb pushed: at a 0.22 deadzone a
/// stick held 15° off horizontal comes out 3° off it, because the small axis is eaten whole while
/// the big one barely notices — the camera (and the hero) creep toward the cardinals and every
/// diagonal fights you. And a full-deflection diagonal rescales to ~0.88 magnitude, so the stick is
/// measurably slower on the diagonals than on the axes. Radial keeps the DIRECTION exactly and
/// reshapes only the MAGNITUDE, which is what a twin-stick camera — ER's included — actually does.
///
/// `curve` shapes that magnitude: 1 = linear, >1 = fine control near the centre with the same top
/// rate still reached at the rim.
const Stick = struct { x: f32 = 0, y: f32 = 0, mag: f32 = 0 };

fn stickRadial(x: f32, y: f32, dz: f32, curve: f32) Stick {
    const m = @sqrt(x * x + y * y);
    if (m < dz) return .{};
    // Clamped, because a real pad reports past 1 on the diagonals (a square gate on a round stick).
    const t = mathx.minF((m - dz) / (1.0 - dz), 1.0);
    return .{ .x = x / m, .y = y / m, .mag = std.math.pow(f32, t, curve) };
}

test "a radial stick keeps the thumb's ANGLE and does not favour the cardinals" {
    // The bug this pins: per-axis deadzoning eats the small component whole, so a stick pushed just
    // off horizontal comes out very nearly horizontal. Here it must come out where it was pushed,
    // deadzone or no.
    const ang = 0.26; // ~15°, the case that used to collapse to ~3°
    const s = stickRadial(mathx.cosf(ang), mathx.sinf(ang), LOOK_DEADZONE, 1.0);
    try std.testing.expectApproxEqAbs(ang, std.math.atan2(s.y, s.x), 1e-5);
    // …and a full-deflection DIAGONAL is as fast as a full-deflection cardinal. Square deadzoning
    // left the diagonal at ~0.88 of the axis, which is the "diagonals drag" half of the same fault.
    const diag = stickRadial(0.7071, 0.7071, LOOK_DEADZONE, 1.0);
    const card = stickRadial(1.0, 0.0, LOOK_DEADZONE, 1.0);
    try std.testing.expectApproxEqAbs(card.mag, diag.mag, 1e-4);
    // Dead centre is dead, and a pad reading past 1 on the gate corners still clamps to 1.
    try std.testing.expectEqual(@as(f32, 0), stickRadial(0.05, -0.05, LOOK_DEADZONE, 1.0).mag);
    try std.testing.expectApproxEqAbs(@as(f32, 1), stickRadial(1.0, 1.0, LOOK_DEADZONE, 1.0).mag, 1e-4);
}

test "A DRIFTING STICK CANNOT CLAIM THE CAMERA — the two look thresholds are not the same number" {
    // THE bug this pins, and it presented as three separate complaints at once ("stick drift?", "camera
    // drifting?", "too sensitive?"). The device latch claimed the camera on anything that cleared
    // LOOK_DEADZONE, and a worn analogue stick RESTS past that — so on such a pad the claim was true
    // every frame, mouse look was dead for the whole session, and the camera crept at whatever the
    // leftover deflection asked for.
    //
    // The fix is two thresholds: LOOK_DEADZONE decides what TURNS the camera, LOOK_CLAIM decides what
    // TAKES it off the other device. Collapse them back into one and the fault returns silently, so the
    // gap is asserted rather than commented.
    try std.testing.expect(LOOK_CLAIM > LOOK_DEADZONE);
    // …and the gap has to clear a real resting deflection. A tired stick sits up to ~0.25; anything
    // under that for LOOK_CLAIM means drift can still steal the camera while you are using the mouse.
    const WORN_STICK_REST: f32 = 0.25;
    try std.testing.expect(LOOK_CLAIM > WORN_STICK_REST);
    // …while staying nowhere near a deliberate push, or reaching for the stick stops working.
    try std.testing.expect(LOOK_CLAIM < 0.7);
    // A stick resting at a typical drift still produces a SMALL turn rate, not a fast one — that is the
    // deadzone doing its half of the job, and it is why drift reads as a slow creep rather than a spin.
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
    // Gamepad first (analog left stick; Circle/B held = dash/sprint). A pushed stick wins
    // over the keyboard so its analog speed is honoured.
    if (rl.isGamepadAvailable(PAD)) {
        if (rl.isGamepadButtonDown(PAD, .right_face_right)) sprint = true;
        // LINEAR curve here, and that is the FEEL RULE, not an oversight: the move stick's tilt maps
        // STRAIGHT to ground speed with nothing shaping it in between. The look stick gets a curve;
        // this one must not.
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

// THE hold-B/Shift SPRINT test, read straight off the raw Move: a real heading plus a speed
// past a full-tilt walk. ONE definition — moveHero's two ER facing exceptions and the stamina
// bleed both go through it, and they must never disagree about what a sprint is.
fn sprintingMove(mv: Move) bool {
    return mv.speed > RUN_SPEED + 0.01 and (mv.fx * mv.fx + mv.fz * mv.fz) > 1e-6;
}

// Move + steer the hero from a camera-relative Move, advance the walk anim, and pose the
// skeleton. Camera basis is read BEFORE this so movement follows the current view.
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
        // Locked-on ANISOTROPY (ER's too): sideways travel runs slower than forward. Not an input gate —
        // the stick still maps straight to speed the same frame, it is the DIRECTION that costs. Also what
        // lets the sidestep keep a walking CADENCE: step rate is speed / hero.STRAFE_CYCLE and the cycle is
        // capped by real hip ROM, so pure lateral travel at full speed needs ~20% more steps/sec than a
        // walk — geometry, not tuning, and unfixable in the animation without skating the foot.
        if (faceYaw != null and !sprinting) {
            const latAmt = @abs(mathx.sinf(mathx.wrapPi(moveYaw.? - g.hero.facing)));
            speed *= mathx.lerpF(1.0, STRAFE_SPEED, latAmt);
        }
        moved = speed * dt;
        g.hero.pos.x = mathx.clampF(g.hero.pos.x + dir.x * moved, -PLAY_HALF, PLAY_HALF);
        g.hero.pos.z = mathx.clampF(g.hero.pos.z + dir.z * moved, -PLAY_HALF, PLAY_HALF);
    }
    // Facing: toward the LOCKED foe (hero strafes/backpedals facing it, ER-style), else
    // toward travel. ER exception: a hold-B SPRINT while locked faces travel — no sideways
    // sprint exists.
    if (faceYaw != null and !sprinting) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, faceYaw.?, TURN_RATE * dt);
    } else if (isMoving) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, moveYaw.?, TURN_RATE * dt);
    }
    g.hero.update(dt, moved, speed, moveYaw);
    g.hero.pose();
}

// World direction to roll: the camera-relative move intent if any, else the hero's facing
// (a forward roll).
fn rollDir(g: *Game, mv: Move) rl.Vector3 {
    const fwd = g.rig.forwardXZ();
    const right = g.rig.rightXZ();
    const d = v3(fwd.x * mv.fz + right.x * mv.fx, 0, fwd.z * mv.fz + right.z * mv.fx);
    if (mathx.lenXZ(d) > 0.01) return d;
    return mathx.headingDir(g.hero.facing);
}

// ── render ───────────────────────────────────────────────────────────────────────
// Casters = the hero + the stone props. NOT the ground (receives only) and NOT the flora (lit pass only,
// swayed by wind). BOTH passes draw through this ONE function so transforms can't drift; only the CULL
// differs, and each pass hands in its own. The depth pass culls by SHADOW REACH, not distance from focus —
// a tall caster well outside the box still throws into it at this sun angle.
fn drawCasters(g: *Game, cull: envmod.Cull) void {
    g.env.drawProps(cull);
    // Combat flash rides the scene shader's per-actor hitFlash uniform: the hero reddens on a
    // suffered blow, and every struck FOE on a landed one (each Group's draw sets it per instance
    // from foe.FLASH_GAIN). Inert during the depth pass — the uniform lives on the scene shader,
    // not the swapped-in depth shader.
    g.scene.setFlash(0.6 * g.hero.hurtFlash);
    g.hero.draw();
    g.scene.setFlash(0);
    g.warren.draw(&g.scene);
    g.line.draw(&g.scene);
    g.grief.draw(&g.scene);
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
    g.warren.setShader(sh);
    g.line.setShader(sh);
    g.grief.setShader(sh);
}

// Launch an arrow from a free pool slot (the loose event). Pool-full is rare (24 slots vs a
// ~1.5s reload on two archers); overwrite slot 0 rather than silently drop the shot.
fn spawnArrow(g: *Game, from: rl.Vector3, target: rl.Vector3) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) {
            ar.* = archermod.launchArrow(from, target);
            return;
        }
    }
    g.arrows[0] = archermod.launchArrow(from, target);
}

// The world solids one arrow could hit THIS frame: everything within its own travel distance,
// pulled from the prop grid. stepArrow samples the midpoint and endpoint of the step, so the
// query radius has to cover a whole frame of flight plus the fattest margin it tests with.
// Static buffer because it is refilled per arrow per frame and never outlives the call.
var arrow_cover_buf: [envmod.MAX_NEAR]collision.Solid = undefined;
pub fn arrowCover(g: *const Game, ar: *const archermod.Arrow, dt: f32) []const collision.Solid {
    return g.env.nearSolids(ar.pos, mathx.lenV(ar.vel) * dt + 1.5, &arrow_cover_buf);
}

// Draw every live/stuck arrow, oriented along its flight (shrinking as a stuck one fades).
// Opaque lit geometry, drawn after the casters; non-casting.
fn drawArrows(g: *Game) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) continue;
        rl.drawMesh(g.arrowModel.meshes[0], g.arrowModel.materials[0], archermod.arrowXform(ar));
    }
}

// The camera the frame is rendered from. The editor flies its own; everything else in the
// render path reads THIS rather than g.rig.cam, so the two can never disagree about which eye
// the frustum was built for (a cull against the wrong camera empties the screen).
fn sceneCam(g: *const Game) rl.Camera3D {
    return if (g.editor.on) g.editor.cam else g.rig.cam;
}

// What the sun's ortho box tracks. Normally the hero; in the editor, whatever the camera is
// looking at — otherwise flying away from the hero to dress a corner of the map loses every
// cast shadow there, and the lighting you are judging is not the lighting the player gets.
fn sunFocus(g: *const Game) rl.Vector3 {
    return if (g.editor.on) mathx.ground(g.editor.cam.target.x, g.editor.cam.target.z) else g.hero.pos;
}

pub fn drawScene(g: *Game) void {
    g.env.resetStats(); // culling counters for the debug overlay, both passes together
    const cam = sceneCam(g);
    const focus = sunFocus(g);
    // Sun depth pass into the shadow map (before beginDrawing). Ortho box tracks the focus, and
    // the pass draws only what can throw INTO that box (env.Cull.sun).
    g.scene.beginShadowPass(focus);
    setCasterShaders(g, g.scene.depthShader);
    drawCasters(g, .{ .sun = focus });
    setCasterShaders(g, g.scene.shader);
    g.scene.endShadowPass();

    rl.beginDrawing();
    // With any filter live, sky + 3D render into the capture RT and blit back through the filter shader;
    // vignette/HUD/menu stay crisp on top. THE EDITOR NEVER FILTERS: pixelate and chroma fringe are exactly
    // what makes a thin gizmo line and a distant prop unjudgeable, and you cannot dress a world through a
    // lens that is lying about it. Filters are PRESENTATION; editing is not.
    const filtered = if (g.editor.on) false else g.retro.begin();
    rl.clearBackground(CLEAR);
    g.sky.draw(cam);

    // ONE view frustum for the whole lit pass, built from the settled camera — props and flora
    // must cull against the same one or a prop can be in for the shadow and out for the light.
    const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
    const view = envmod.View.fromCamera(cam, aspect);

    rl.beginMode3D(cam);
    g.scene.bind(cam.position);
    // Torchlight: the fires whose pool is ON SCREEN, nearest first, guttering. Must land before
    // anything draws — the uniforms are read by every subsequent draw through the scene shader.
    // It takes the same frustum the prop cull uses, so a light and the geometry it lights can
    // never disagree about whether they are in frame.
    g.env.uploadLights(&g.scene, &view, @floatCast(rl.getTime()));
    g.scene.setGround(true);
    g.env.drawGround();
    g.scene.setGround(false);
    // THE PAINTED WATER, straight after the ground it lies on: one quad whose dry fragments the shader
    // discards, so everything standing in a lake (reeds, drowned columns) draws over it by depth test
    // in the passes below rather than needing to be sorted against it.
    g.env.drawWater();
    if (g.menu.wireframe) rl.gl.rlEnableWireMode();
    drawCasters(g, .{ .view = view });
    // Flora last: non-casting, and swayed by the scene shader's wind term (props/hero rigid).
    g.scene.setWind(true);
    g.env.drawFlora(&view);
    g.scene.setWind(false);
    drawArrows(g); // in-flight + stuck arrows (lit, rigid, non-casting)
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
    // Toad telegraph FX (dust / charge / spit / blood / death motes) — unlit spheres over
    // the opaque geometry. The hero's swing trail joins them (same unlit layer).
    g.warren.drawFx();
    g.grief.drawFx();
    g.hero.drawTrail();
    // Arrow flight streaks — alpha ribbons like the swing trail, so they belong in this unlit
    // group after the opaque geometry, not up with the shafts themselves.
    archermod.drawArrowTrails(&g.arrows);
    // Debug: the blade hit capsule (menu > Debug > Hitboxes) — red while ACTIVE, dim
    // otherwise. Unlit, default shader on purpose.
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
    // Editor gizmos: op outlines, the selection's instances, the drag in progress. Inside the
    // 3D pass so they sit in the world, but AFTER everything else so nothing occludes them.
    if (g.editor.on) g.editor.draw3D(&g.map, &g.env);
    rl.endMode3D();

    if (filtered) g.retro.end();
    // THE GAMEPLAY OVERLAY IS GAMEPLAY'S. Every line below either projects against `g.rig.cam`
    // (which is NOT the eye this frame was rendered from once the editor flies its own — see
    // sceneCam) or reads a hero clock the editor path deliberately never ticks: hurtFlash froze a
    // red screen-edge wash over the whole editing session if you entered right after being hit,
    // and a lock left over from before Menu > Editor drew its reticle at a stale screen position.
    if (g.editor.on) return;
    g.vignette.draw(); // the vignette darkens the corners the chrome lives in
    drawHurtFlash(g); // red screen-edge pulse when the hero is hit (peripheral feedback)
    drawFoeBars(g, g.warren.live()); // floating foe HP bars, crisp over the finished frame…
    drawFoeBars(g, g.line.live()); // …one shared path for every foe group…
    drawFoeBars(g, g.grief.live()); // …the ogre included (a regular foe, not a boss — owner's call)
    drawLockDot(g); // the ER lock-on reticle
    drawDeathOverlay(g); // the YOU DIED card + respawn fade, over everything
}

// ── the YOU DIED screen ── Elden Ring's death card: the world dims, a black band slides
// across mid-screen, and huge blood-red letters fade in wide-spaced, swelling a touch;
// the tail runs to full black that the respawn hides behind, then g.deathFade lifts the
// black off the fresh world. All timing rides hero.deathT against heromod.DEATH_DUR.
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
        const ta = mathx.smoothstep(0.16, 0.48, u) * (1.0 - mathx.smoothstep(0.90, 1.0, u));
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
        // …reaching FULL black a little BEFORE the respawn rather than on the same frame, so the
        // hold starts while the card is still up and the cut itself is buried inside it.
        const blackK = mathx.smoothstep(0.82, 0.94, u);
        if (blackK > 0.001) rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * blackK)));
    } else if (g.deathFade > 0) {
        // HOLD, then fade. `deathFade` runs RESPAWN_HOLD + RESPAWN_FADE; everything above the fade
        // length is the held beat of solid black, and only the last RESPAWN_FADE of it lifts.
        const k = if (g.deathFade > RESPAWN_FADE) 1.0 else mathx.clampF(g.deathFade / RESPAWN_FADE, 0, 1);
        rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * k))); // wake at the bonfire
    }
}

// A red damage flash bleeding in from the screen edges, scaled by hero.hurtFlash — Elden
// Ring's "you got hit" cue. Gradient bars so the edges feather instead of framing the view.
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

// THE HUD IS ELDEN RING'S, and only in ER's places: vitals bars top-left, the armament grid
// bottom-left, the debug readout top-right (where ER keeps its compass). Nothing else — the
// old title / subtitle / control-crib lines are gone, so a screenshot is the game, not a
// caption over it. `dt` only drives the HP chip trail; --shot passes SHOT_DT.
pub fn hud(g: *Game, dt: f32) void {
    // ER hides the HUD behind its menus and under the death card, and both want the corners
    // clear — a chip trail hanging across an empty HP bar under YOU DIED reads as a fault.
    if (!g.menu.isOpen() and !g.hero.dead) {
        // All three bars are LIVE now. FP still has nothing to SPEND it on (no spells, no skills),
        // so it sits full — but it is a real meter rather than a literal 1.0, because the Cerulean
        // flask pours into it and a flask whose target is a constant cannot be seen to work.
        hud_.vitals(dt, g.hero.vit.hpFrac(), g.hero.fp.frac(), g.hero.stam.frac(), g.hero.stamRefused / combat.STAM_REFUSE_FLASH);
        // The one-line translation combat.FlaskKind → hud.FlaskTint: hud takes plain values and
        // knows nothing about the combat layer, so the mapping belongs on this side of the fence.
        hud_.equipment(switch (g.hero.flasks.sel) {
            .crimson => hud_.FlaskTint.crimson,
            .cerulean => hud_.FlaskTint.cerulean,
        }, g.hero.flasks.ready());
        hud_.runes(g.hero.runes.display()); // the ROLLING value, not the banked total
    }
    if (g.menu.stats) debugCorner(g);
}

// The debug readout, top-right, toggled by menu > Debug > Stats. Right-aligned rows stepped
// off the type scale (hard-coded Y values overlapped the moment the face grew). Poise, stance
// and the stamina NUMBERS stay in here rather than on the bars — ER keeps its meters hidden,
// and this is the one place you get to look behind them.
const DBG_ROW = 200; // …the widest debug row, in bytes

fn debugCorner(g: *Game) void {
    // ASCII only — the Balthazar atlas is the default (ASCII) glyph set, so a "·" or "—" is tofu.
    // ONE scratch buffer for all four rows: each is formatted, drawn, and finished with before
    // the next overwrites it, so four separate arrays only cost stack and invite a fifth.
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

    dbgRow(std.fmt.bufPrintZ(&buf, "{d} fps   {d:.1} ms   pos {d:.1},{d:.1}   yaw {d:.2}   pitch {d:.2}   time x{d:.2}", .{
        rl.getFPS(),
        rl.getFrameTime() * 1000.0,
        g.hero.pos.x,
        g.hero.pos.z,
        g.rig.yaw,
        g.rig.pitch,
        g.menu.timeScale,
    }) catch "", y, hud_.SMALL, rgba(170, 190, 150, 255));
    y += step;

    // Foe counts span EVERY group (the combat beats already do) — a toads-only "hits" read
    // silently ignored every blow landed on a skeleton or the giant.
    const h = &g.hero;
    const foesLeft = allAlive(g);
    const foeHits = allHits(g);
    dbgRow(std.fmt.bufPrintZ(&buf, "hero  hp {d:.0}/{d:.0}  poise {d:.0}/{d:.0}  stance {d:.0}/{d:.0}  stam {d:.0}/{d:.0}   foes {d} left  hits {d}", .{
        h.vit.hp,   h.vit.hpMax, h.vit.poise, h.vit.poiseMax, h.vit.stance, h.vit.stanceMax,
        h.stam.cur, h.stam.max,  foesLeft,    foeHits,
    }) catch "", y, hud_.SMALL, rgba(150, 180, 190, 255));
    y += step;

    // World + culling line: how much of the world EXISTS vs how much of it this frame drew.
    // The expansion's whole perf claim is "thousands of props, a few hundred draws" — this is
    // where you check it while playing instead of taking a comment's word for it.
    dbgRow(std.fmt.bufPrintZ(&buf, "world  props {d}  solids {d}  fires {d}   drawn {d} in {d} cells (both passes)", .{
        g.env.propCount(), g.env.solidCount(), g.env.lightCount(), g.env.stat_draws, g.env.stat_cells,
    }) catch "", y, hud_.SMALL, rgba(150, 175, 195, 255));
    y += step;

    // ── THE LOOK PROBE ── and it exists to settle ONE question in a glance: the camera feels wrong,
    // and stick drift, cursor jitter and too-high sensitivity all look identical on screen. Put your
    // hands OFF both devices and read the row:
    //
    //   dyaw 0.00 with everything at rest  → nothing is drifting. The camera is only moving when you
    //                                        move it, so what feels wrong is the RATE, not a fault.
    //   mag above 0.14 (LOOK_DEADZONE)     → the stick rests far enough off centre to TURN the camera.
    //                                        That is hardware drift getting through; raise the
    //                                        deadzone (radial, so it costs no diagonal range).
    //   mag under 0.14 but non-zero        → drift exists, the deadzone is already eating it, and it
    //                                        is NOT what you are feeling.
    //   mag above 0.40 (LOOK_CLAIM) at rest→ the stick is bad enough to CLAIM the camera off the
    //                                        mouse while sitting still. Raise both dials.
    //   mouse non-zero while you hold still→ something is driving the OS cursor. A pad running through
    //                                        a mouse-emulation layer (Steam Input's desktop fallback,
    //                                        DS4Windows) puts a STICK on it, which is exactly this.
    //
    // `look PAD/MOUSE` says which device currently owns the camera — the latch, not a preference.
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

// One right-aligned debug row, inset by the HUD's own margin so the corner lines up with the
// bars opposite it.
fn dbgRow(s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    hud_.textRight(s, hud_.MARGIN, y, size, col);
}

fn gaitLabel(moving: f32, speed: f32) [:0]const u8 {
    if (moving < 0.5) return "idle";
    if (speed >= SPRINT_SPEED - 0.3) return "sprinting";
    if (speed >= RUN_SPEED - 0.3) return "running";
    return "walking";
}

/// How the process runs: the game, or one of the two headless capture modes in `shots.zig`.
pub const Mode = enum { play, shots, props };

pub fn run(mode: Mode) void {
    const shot = mode != .play;
    // VSYNC is why fullscreen was tearing. setTargetFPS is a CPU-side frame LIMITER — it paces how
    // often we draw but never tells the driver to swap during vblank, so the swap lands mid-scan and
    // the seam shows. Windowed mode hid it because Windows' compositor effectively syncs for us;
    // exclusive fullscreen bypasses the compositor and the tear appears. vsync_hint asks GLFW for
    // swap interval 1, which is the actual fix. It must be set BEFORE initWindow to take effect.
    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true, .window_hidden = shot, .window_resizable = true });
    rl.initWindow(SCREEN_W, SCREEN_H, "zig-soulslike");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    // No setTargetFPS alongside vsync: the two limiters fight on any display that isn't 60 Hz (vsync
    // paces to the refresh, then raylib's own busy-wait throttles on top, which reads as judder).
    // Everything is dt-driven, so presenting at the panel's rate is simply smoother.

    hud_.init();
    defer hud_.deinit();

    // NO AUDIO UNDER --shot. The harness renders hundreds of frames as fast as it can with no
    // wall clock behind them, so every beat it stages would fire at once into a device nobody is
    // listening to — and opening one costs a second of startup for a run that only writes PNGs.
    // The defer carries its own guard: inside an `if` block it would run at the end of the BLOCK,
    // tearing the device down on the line after it opened.
    if (!shot) sfx.init();
    defer if (!shot) sfx.deinit();
    // …and the object viewer's two off-screen targets, which are created lazily the first time the
    // gallery opens. It had a `unload` nobody called — a GPU resource with no release path is the kind
    // of loose end that becomes a real leak the moment something starts reopening the window.
    defer objviewmod.unload();

    const alloc = std.heap.c_allocator;
    const g = alloc.create(Game) catch return;
    defer alloc.destroy(g);
    g.init();

    // Tight near/far for real depth precision — the default 0.01..1000 makes the hero's
    // overlapping boxes z-fight and flicker/invert as the camera moves. BeginMode3D reads
    // these; the shadow pass saves/restores them around its ortho slab, so setting them
    // once here sticks. Set BEFORE the --shot branch so headless captures match.
    rl.gl.rlSetClipPlanes(CLIP_NEAR, CLIP_FAR);

    if (mode == .shots) {
        @import("shots.zig").runShots(g);
        return;
    }
    if (mode == .props) {
        @import("shots.zig").runPropShots(g);
        return;
    }

    // Mouse HIDDEN over the window (GLFW_CURSOR_HIDDEN — invisible but NOT locked) and
    // drives the camera; past the window edge it reappears as a normal cursor. No capture,
    // ever.
    rl.hideCursor();
    var wasInside = false;
    var bWasDown = false; // gamepad Circle/B: a TAP rolls, a HOLD sprints
    var bHeldT: f32 = 0;
    var lockCycleReady = true; // debounce so one flick cycles the lock-on target once
    // Which device owns the camera. Starts on the MOUSE, so a keyboard+mouse player never has to
    // wiggle a stick to get look working; the first real right-stick deflection takes it.
    var lookPad = false;
    // Rising-edge trackers for rumble: pulse the frame an action BEGINS. Watching committed
    // state (not the input press) catches queued actions too.
    var wasRolling = false;
    // The swing COUNT, not the `attacking` flag: a chained combo clears that flag and sets it again
    // within one frame, so its rising edge missed every cut after the first (see hero.swings).
    var wasSwings: u32 = 0;
    var wasDead = false;
    var wasRefused: f32 = 0; // …and the refusal flash, whose rising edge IS the ignored input
    var wasStun: combat.StunKind = .none;
    // Footfalls key off the stride phase, not a timer: `hero.phase` is driven by DISTANCE
    // travelled, so a step lands exactly when a foot does at any speed, and slowing down
    // lengthens the gap between them for free. Seeded past 0.5 so the first step is a fresh one.
    var lastPhase: f32 = 0.75;
    defer g.rumble.stop(); // never leave a motor latched after we exit the loop
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime(); // wall-clock dt: feel systems (shake, rumble, fades, tap windows)
        const dt = rawDt * g.menu.timeScale;
        // The map can be swapped under us at any moment (the editor's New / Open / Reload / undo),
        // and the clamp is the one piece of world size that lives outside `materialize`.
        PLAY_HALF = g.map.half - envmod.PLAY_INSET;
        // THE WORLD GOES QUIET IN THE EDITOR. `sfx.mute`'s own doc said "the editor uses it, since a
        // map you are dressing should not be croaking at you" — and nothing called it, so the claim
        // was simply untrue and the wind bed ran on until its buffer ended and then stopped, which
        // reads as the audio having died. Driven off the flag once a frame rather than hooked onto the
        // three ways in and out (menu > Editor, Leave, F5 playtest): `mute` early-outs when the state
        // is unchanged, and one line here cannot be the transition somebody forgot.
        sfx.mute(g.editor.on);

        // Esc backs the menu out one level (opens it when closed); pad Start toggles. NOT WHILE THE EDITOR
        // IS UP: Esc is the editor's own back-out key, and this runs BEFORE the editor branch, so every Esc
        // pressed in there also toggled the pause card behind it — an odd number left the menu open and an
        // F5 playtest dropped the player into a paused world.
        if (!g.editor.on) {
            if (rl.isKeyPressed(.escape)) g.menu.onEscape();
            if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .middle_right)) g.menu.onStartButton();
        }

        // Alt+Enter toggles borderless-windowed fullscreen (no exclusive mode-switch, so the
        // mouse stays usable elsewhere). Keep the retro capture RT matched to the window on
        // the toggle AND on any manual resize.
        if (rl.isKeyPressed(.enter) and (rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt))) {
            rl.toggleBorderlessWindowed();
            g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());
        }
        if (rl.isWindowResized()) g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());

        // Set from the menu in ONE place, before the branch, so the flag can never disagree with
        // which path actually ran: a held hero breathes but his combat clocks stop (see hero.held).
        // THE EDITOR is its own scene over the same world: no gameplay, no hero input, no foes
        // thinking. It runs before the menu branch so Esc reaches the editor rather than
        // reopening the pause card behind it.
        if (g.editor.on) {
            // THE CURSOR COMES BACK. Gameplay hides it because the mouse IS the camera there;
            // the editor is a pointer tool — palettes, sliders, a brush you aim — and hiding the
            // pointer in a pointer tool makes it unusable. Re-hidden on the way out.
            rl.showCursor();
            switch (g.editor.update(&g.map, &g.env, rawDt)) {
                .none => {},
                .leave => {
                    g.editor.on = false;
                    g.menu.screen = .main;
                    rl.hideCursor(); // back to the gameplay rule: the mouse IS the camera
                },
                // F5 PLAYTEST: drop straight into the live world at the editor's viewpoint, so
                // the thing you just dressed is the thing you are standing in. Esc brings the
                // menu back and Editor returns you here.
                .playtest => {
                    g.editor.on = false;
                    rl.hideCursor();
                    g.hero.pos = mathx.ground(g.editor.cam.target.x, g.editor.cam.target.z);
                    g.hero.pos = g.env.resolveActor(g.hero.pos, HERO_R);
                    g.hero.setSpawn(g.hero.pos, g.hero.facing);
                    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
                    wasInside = false; // swallow the mouse delta the editor's look accumulated
                },
            }
            g.hero.held = true;
            g.hero.pose();
            // Re-home the foes from the map every frame the editor is up, so moving a spawn
            // moves the thing you can SEE. They are not updated while editing, so re-spawning
            // them costs nothing and there is no animation state to lose.
            g.warren.reset(&g.map);
            g.line.reset(&g.map);
            g.grief.reset(&g.map);
            drawScene(g);
            editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, rawDt);
            rl.endDrawing();
            continue;
        }

        g.hero.held = g.menu.isOpen();
        if (g.menu.isOpen()) {
            // World holds while the menu is up: no camera/move input, but the hero keeps
            // breathing (idle update, zero travel) so the scene stays alive.
            switch (g.menu.update(&g.retro, rawDt)) {
                .quit => break,
                .editor => {
                    // Drop the lock on the way in: the reticle rides a FoeRef into groups the
                    // editor re-homes from the map every frame, so a held lock survives into a
                    // world where its index means something else.
                    g.lock = null;
                    g.editor.enter(g.hero.pos);
                },
                .none => {},
            }
            // Poison the pad-B tap window: B both backs out of the menu AND rolls, so without
            // this the release of the B that closed the menu fires an instant roll. Poisoned,
            // that release reads as a hold; a fresh press after release taps normally.
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false; // swallow the mouse delta accumulated while in the menu
            g.hero.update(rawDt, 0, 0, null);
            g.hero.pose();
            g.rig.tickShake(rawDt); // any live shake decays out under the pause
            g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false); // motors silent while paused (envelopes still decay)
            // THE WIND KEEPS BLOWING UNDER THE PAUSE CARD. Ambience was only ticked on the gameplay
            // path, so the bed ran out mid-gust a few seconds into any pause and the world went
            // completely silent behind the menu — which reads as the audio having crashed. The ears
            // stay where the camera left them, which is right: nothing has moved.
            sfx.ambience(rawDt);
            drawScene(g);
            hud(g, rawDt);
            g.menu.draw(&g.retro);
            rl.endDrawing();
            continue;
        }

        // Lock-on toggle: R3 (pad) / middle-mouse (kb+m). Locked → drop; else acquire the
        // best foe in view, or pad R3 recenters if there is none.
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

        // Camera look. LOCKED: auto-swings onto the foe, manual look suppressed, and stick/
        // mouse CYCLE targets instead. Unlocked: free look.
        const inside = rl.isWindowFocused() and rl.isCursorOnScreen();
        const md = rl.getMouseDelta();
        var wheel = rl.getMouseWheelMove();
        const padRX: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_x) else @as(f32, 0);
        // Both look axes are read HERE, before the lock branch, because the PROBE is written for both
        // paths below. It used to be recorded only on the unlocked one, so locking on froze the
        // readout on whatever it last said — a diagnostic that lies is worse than no diagnostic.
        const padRY: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_y) else @as(f32, 0);
        // The yaw BEFORE any look input lands, so the probe can report what the camera actually turned
        // this frame rather than what the devices claimed. Measured across every path below (locked
        // aim included), because "the camera drifts" has to be answerable without knowing which one ran.
        const yawBefore = g.rig.yaw;
        // RAW stick magnitude, before any deadzone. Both the drift diagnosis and the device latch below
        // need the untouched number: how far the stick is actually pushed is the only thing that can
        // tell a resting deflection apart from a real one.
        const padMag = @sqrt(padRX * padRX + padRY * padRY);
        var lookMag: f32 = 0;
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
            // ── ONE LOOK DEVICE AT A TIME ── the mouse delta and the right stick used to be SUMMED
            // every frame, which is wrong twice over. It means a pad player is still steering with
            // whatever the OS cursor happens to do (and a pad running through a mouse-emulation
            // layer — Steam Input's desktop fallback, DS4Windows — puts the LEFT stick on that
            // cursor, so moving right turns the camera right); and it means the tiniest resting
            // deflection on one device adds to the other rather than being ignored.
            //
            // So: the last device to give a REAL look input owns the camera, and the other is dead
            // until it gives one of its own. Switching costs nothing and is instant — this is a
            // latch, not a lockout.
            const look = stickRadial(padRX, padRY, LOOK_DEADZONE, LOOK_CURVE);
            lookMag = padMag;
            // MOUSE_WAKE, not zero: a hidden-but-uncaptured cursor picks up a pixel of jitter from
            // the desk, and one pixel used to be enough to take the camera off the stick.
            const mouseLook = inside and wasInside and (@abs(md.x) + @abs(md.y)) > MOUSE_WAKE;
            // ── CLAIMING THE CAMERA IS A DIFFERENT QUESTION FROM TURNING IT, and conflating the two
            // is what made a worn stick disable the mouse for the whole session.
            //
            // It used to claim on `look.mag > 0` — i.e. on ANYTHING that cleared LOOK_DEADZONE. A worn
            // right stick RESTS at 0.15-0.25, which is past the 0.14 deadzone, so on such a pad the
            // claim was true on every single frame: the latch pinned itself to PAD on frame one, the
            // mouse never worked again, and the camera crept at the fraction of a degree per second the
            // leftover deflection asks for. All three of the owner's symptoms — "stick drift", "camera
            // drifting", "too sensitive" — are that one line.
            //
            // So the CLAIM takes a decisive push (LOOK_CLAIM, well past any resting deflection) while
            // the TURN still starts at LOOK_DEADZONE. Drift can reach the second and never the first,
            // so a drifting pad can no longer take the camera off a mouse that is being used.
            const padClaim = padMag > LOOK_CLAIM;
            // …and LAST DEVICE WINS has to be resolved as a TIE, not by statement order. Written as two
            // independent ifs the second one always won, so "the last device to give a real look input
            // owns the camera" actually meant "the pad owns the camera whenever it says anything at
            // all". Both talking at once now keeps whoever already had it.
            if (padClaim and !mouseLook) lookPad = true;
            if (mouseLook and !padClaim) lookPad = false;
            if (lookPad) {
                // rawDt, NOT dt: looking around is a FEEL system like the shake and the rumble, and
                // it lives on the wall clock. On `dt` the debug time scale quartered the stick's
                // camera speed while leaving the mouse's (per-PIXEL, no dt at all) untouched — the
                // two devices disagreed about how fast the world turns.
                g.rig.orbit(
                    -look.x * look.mag * LOOK_RATE_YAW * rawDt,
                    look.y * look.mag * LOOK_RATE_PITCH * rawDt,
                );
            } else if (inside and wasInside) {
                g.rig.rotate(md.x, md.y);
            }
        }
        // …and record what BOTH devices said, deadzone or no, for the debug readout — on EITHER
        // path, so the readout still tracks the sticks while locked on.
        g.probe = .{
            .mdx = md.x,
            .mdy = md.y,
            .rx = padRX,
            .ry = padRY,
            .mag = lookMag,
            // Wrapped: yaw lives in (−pi, pi] so a turn across the seam is a small delta, not a full
            // circle. This is the line that says whether the camera moved AT ALL.
            .dyaw = mathx.degrees(mathx.wrapPi(g.rig.yaw - yawBefore)),
            .pad = lookPad,
        };
        wasInside = inside;
        // PAD ZOOM MOVED TO D-PAD LEFT/RIGHT. Down is ER's quick-item cycle (the flasks, below) and
        // up is ER's spell cycle, which this build has nothing to put on yet — so the vertical pair
        // belongs to the item slots and the horizontal one takes the zoom it displaced.
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .left_face_right)) wheel += 1; // D-pad right = zoom in
            if (rl.isGamepadButtonPressed(PAD, .left_face_left)) wheel -= 1; // D-pad left = zoom out
        }
        if (wheel != 0) g.rig.zoom(wheel);

        // ── THE FLASKS (ER) ── X / Square drinks the one in the quick-item slot, D-pad DOWN cycles
        // which one that is. On the keyboard: R drinks, T cycles (ER's own KB default puts "use
        // item" on R, and T is its unclaimed neighbour).
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

        // Sword attacks (ER layout): R1/RB or LMB = light, R2/RT or Shift+LMB = heavy.
        // Committed (no mid-swing cancels), but input BUFFERS ER-style: a mid-action press
        // queues in the hero's one slot and fires at the earliest exit.
        var lightReq = false;
        var heavyReq = false;
        if (rl.isMouseButtonPressed(.left)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) heavyReq = true else lightReq = true;
        }
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_1)) lightReq = true;
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_2)) heavyReq = true;
        }

        // STAMINA GATES THE SPRINT AT THE SOURCE. Denying it here rather than downstream keeps
        // `sprintingMove` the ONE definition of a sprint: the speed the hero travels at, the two
        // ER facing exceptions and the continuous bleed all read the same Move, so they cannot
        // disagree about whether he is sprinting. Capped to the walk ceiling, never zeroed —
        // running out of stamina drops you to a walk, it does not root you to the spot.
        var mv = gatherMove();
        if (!g.hero.stam.canSprint()) mv.speed = @min(mv.speed, RUN_SPEED);
        // Poise/stance regenerate every frame (relent and pressure resets — Elden Ring).
        g.hero.vit.tick(dt);
        g.hero.tickFlash(dt); // fade the red damage flash
        // Action input is dead while staggered or dead (a reaction is committed). Otherwise a
        // roll press wins a same-frame conflict, and a queued roll re-steers every frame so it
        // leaves in the direction HELD at fire time, not pressed — both ER behaviors.
        if (!g.hero.dead and !g.hero.staggered()) {
            if (rollReq) {
                g.hero.requestRoll(rollDir(g, mv));
            } else if (heavyReq) {
                g.hero.requestAttack(.heavy);
            } else if (lightReq) {
                g.hero.requestAttack(.light);
            }
            g.hero.steerQueuedRoll(rollDir(g, mv));
            // The draught is NOT buffered — it is the one action you should never find yourself
            // committed to because of a press you made a second ago in a panic. It either starts
            // now, on a free hero, or it does not happen.
            if (drinkReq and g.hero.startDrink()) sfx.play(.flask_drink);
        }
        // The sprint is the only CONTINUOUS drain, and only while he is actually running on his feet — a
        // roll's lunge and an attack's step travel fast but are not sprints. The roll/swing bites are
        // charged at their start and the meter advances inside hero.tickClocks, so it ticks exactly once
        // whichever path runs below. Set AFTER the requests above, so rolling/attacking already reflect
        // anything that fired this frame.
        g.hero.sprinting = sprintingMove(mv) and
            !g.hero.rolling and !g.hero.attacking and !g.hero.dead and !g.hero.staggered();

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        if (g.hero.dead) {
            g.hero.updateDeath(dt); // collapse → respawn
            // The frame he returns, the WORLD reloads with him (ER-style): every foe re-homed
            // at full health, arrows cleared, lock dropped. Under the death card's full black,
            // so it's a cut, never a pop.
            if (!g.hero.dead) resetFoes(g);
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt); // reeling — wide open
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.drinking) {
            g.hero.updateDrink(dt); // committed, and planted — the flask's whole cost
        } else if (g.hero.attacking) {
            // Committed — a short step into the cut; while LOCKED the recovery tail re-squares
            // onto the target (a whiffed swing recovers turning fast).
            g.hero.updateAttack(dt, PLAY_HALF, lockYaw);
        } else {
            moveHero(g, dt, mv, lockYaw);
        }
        // Knot hunts, skeletons kite + loose; the hero's swept blade damages/staggers both
        // sides, and a connecting chomp/lunge/arrow returns its blow to the hero. Resolve all,
        // settle collisions, then aim the camera at the SETTLED hero position.
        const hitsBefore = allHits(g);
        // ONE snapshot of the blade for every group this frame — the hero's pose is already
        // resolved above, so re-deriving it per group only invited the three to disagree.
        const bladeNow = heroBlade(g);
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |h| {
            g.hero.takeHit(h);
            // The lunge carries stance damage; the chomp doesn't — split the felt blow by that.
            heroHurtBeat(g, h.stance > 0, true);
        }
        // The lone ogre hunts, slams and side-swipes. The overhead crush is the full heavy beat; the
        // faster swipe hurts less and is FELT less, so the two read apart through the pad and camera
        // as well as on screen (split off the blow's own stance damage, like the toad's above).
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |h| {
            g.hero.takeHit(h);
            heroHurtBeat(g, h.stance >= ogremod.SLAM_HIT.stance, true);
        }
        // Blade lands on the skeletons; then they act — kite and loose from the nock at the
        // hero's centre of mass (arrow homing + arc finish the job). A blade hit mid-draw
        // interrupts the shot (enterStun clears the draw).
        for (g.line.live()) |*a| {
            if (a.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), v3(g.hero.pos.x, HERO_CENTER_Y, g.hero.pos.z));
            }
        }
        // Arrows in flight: gentle homing + arc, then a strike lands a chomp-weight blow.
        // A hero inside the roll's i-frames is NOT a target (shaft passes through). World
        // solids BLOCK shots (cover works) — a blocked arrow thunks into stone.
        for (&g.arrows) |*ar| {
            if (!ar.live) continue;
            ar.hit = false;
            archermod.stepArrow(ar, g.hero.pos, HERO_CENTER_Y, g.hero.iFramed(), arrowCover(g, ar, dt), dt);
            if (ar.hit) {
                // It found the hero. The BEAT is skipped on a corpse, but the shaft still landed in
                // him — so the sound is the flesh one either way. Testing `!dead` on the whole
                // branch dropped a hit on a dying hero through to the world-impact arm below, which
                // then played a scuff of DIRT for an arrow that was standing in his chest.
                if (!g.hero.dead) {
                    g.hero.takeHit(archermod.ARROW_HIT);
                    heroHurtBeat(g, false, false); // …the rip below is this blow's own voice
                }
                sfx.play(.arrow_hit);
            } else if (ar.stuck and ar.age == 0) {
                // It STUCK without connecting — into cover, or into the earth. Worth its own
                // sound: an arrow thunking off the pillar you ducked behind is the game telling
                // you the cover WORKED, which is the whole reason arrows test the solids at all.
                // `age == 0` is the sticking frame exactly, and it needs no state of its own:
                // stepArrow zeroes the age when it plants and adds dt on every frame after.
                //
                // WHICH thunk comes from what it went into — timber knocks, iron rings, masonry
                // cracks dead, and a miss into the earth just scuffs. The mapping lives beside the
                // four voices it picks from (`sfx.arrowImpact`), not here.
                sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
            }
        }
        // Blade connected this frame (a foe's hit count climbed) → hit pulse + frame crack
        // sized to the swing; a kill adds the thunk (via justDied, since dissipation delays
        // the aliveCount drop). Strongest-wins blends them.
        if (allHits(g) > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
            sfx.play(if (g.hero.atkHeavy) .hit_heavy else .hit_light);
        }
        if (anyFoeDied(g)) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_KILL);
            // The kill beat: a THUD, and nothing else (owner's call — no bell, no jingle). Each foe
            // already cries out in the world where it died; this is the weight landing, played at
            // the listener so a kill across the plaza still registers.
            sfx.play(.kill);
        }
        // …and the kill PAYS. Same one-frame `justDied` flag the beat above reads, so the runes, the
        // rumble and the shake all fire together or not at all; each group knows its own worth.
        // …and it pays SILENTLY: the kill thud above is the whole beat (owner's call — no jingle).
        g.hero.runes.gain(allRunes(g));
        // ER lock-on across a kill: the lock leaves a corpse the FRAME it dies (not after the
        // death anim), snapping to the next valid target (nearest screen-centre, like a fresh
        // acquire) or dropping if none.
        if (g.lock) |li| {
            if (!foeLockable(g, li)) g.lock = acquireLock(g); // corpse the frame it dies → switch/drop
        }
        collideActors(g, dt);
        g.rig.tickShake(rawDt); // impact shake decays on wall-clock time (bakes this frame's jitter)
        g.rig.follow(g.hero.shoulderPoint());
        // THE EARS RIDE THE CAMERA, not the hero — the pan has to agree with what is on screen, and
        // the camera is the eye. Set after `follow`, so a foe's sound is panned against the settled
        // view rather than against last frame's.
        sfx.listen(g.rig.cam.position, g.rig.rightXZ());
        sfx.ambience(rawDt); // keep the wind bed alive, and let the odd bird call over it
        footsteps(g, &lastPhase);

        // Rising-edge action pulses: roll whump, swing effort (heavy > light), death swell.
        // Watching committed state catches queued actions too.
        if (g.hero.rolling and !wasRolling) {
            g.rumble.play(rumblemod.roll);
            sfx.play(.roll);
        }
        // EVERY cut is heard, chained ones included: the counter ticks in hero.startAttack, which is
        // the one door a swing can come through. `atkHeavy` already describes the NEW swing here.
        if (g.hero.swings != wasSwings) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.swing_heavy else rumblemod.swing_light);
            sfx.play(if (g.hero.atkHeavy) .swing_heavy else .swing_light);
            wasSwings = g.hero.swings;
        }
        // A REFUSED action is heard as well as seen. `stamRefused` is set by hero.startRoll /
        // startAttack the instant they decline, so its rising edge is exactly the input that did
        // nothing — the one thing a ZERO INPUT LAG game must never leave silent.
        if (g.hero.stamRefused > wasRefused) sfx.play(.refused);
        wasRefused = g.hero.stamRefused;
        // The stagger is its own beat: the blow that caused it already played, this is his footing
        // going. Only the HEAVY one — a light flinch is over before a scuff could read.
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

// ── FOOTFALLS ── a step on every heel strike, which the gait already tells us about: `hero.phase`
// is the stride cycle, the LEFT foot plants at 0 and the right at 0.5, and the phase advances by
// DISTANCE. So the crossing test below is the whole thing — no timer, no per-speed tuning, and a
// hero slowing to a crawl gets his steps spaced out for nothing. (`ogre.footfalls` reads the same
// crossing for its dust, which is where the idiom comes from.)
//
// The VOICE is chosen by ground speed, not by the gait blend: walk, run and sprint each have their
// own boot, and hearing which one you are in is a real part of knowing how fast you are going.
fn footsteps(g: *Game, last: *f32) void {
    const h = &g.hero;
    // Nothing plants during a roll, a stagger or a death — those anims move the feet on their own
    // terms and a stride-phase step under them lands nowhere near a foot.
    if (h.moving < 0.45 or h.rolling or h.dead or h.staggered()) {
        last.* = h.phase;
        return;
    }
    const crossed = (last.* < 0.5 and h.phase >= 0.5) or (h.phase < last.*); // 0.5, or the wrap past 0
    last.* = h.phase;
    if (!crossed) return;
    const id: sfx.Id = if (h.speed >= SPRINT_SPEED - 0.3)
        .step_sprint
    else if (h.speed >= RUN_SPEED - 0.3)
        .step_hard
    else
        .step_soft;
    // Quieter the slower he goes, on top of the voice change — a careful walk should not land as
    // hard as a sprint that happens to be crossing the same phase.
    sfx.playAt(id, mathx.clampF(0.45 + 0.55 * h.speed / SPRINT_SPEED, 0.35, 1.0));
}

// ── THE HERO WAS HURT ── the rumble + camera crack + voice for one blow landing on him, in ONE
// place. Three call sites (a toad's chomp/lunge, the ogre's swipe/slam, an arrow) each wrote out the
// same three-line trio with the same `if (heavy)` ternary repeated on each line — so retuning the
// felt weight of a heavy hit meant finding nine lines and there was nothing to say when you found
// eight. Each caller still decides for ITSELF what counts as heavy: that test is per-attack (stance
// damage for the toad, the slam's own stance for the ogre, never for an arrow) and is not shared.
//
// `voice` false means the caller has its OWN sound and this must not double it: an arrow landing in
// him plays `.arrow_hit` — the rip through flesh IS the sound of that blow — so it takes the grip and
// the camera and leaves the grunt alone. That exception is why the sound stays inside the helper
// rather than being left to each caller: written out at the call site it is three more copies of the
// same ternary, and hidden behind a flag it is one line that says which blows get a voice.
//
// NO HITSTOP here or anywhere (owner's law): impact weight is shake + rumble + FX + reaction anims.
fn heroHurtBeat(g: *Game, heavy: bool, voice: bool) void {
    g.rumble.play(if (heavy) rumblemod.hurt_heavy else rumblemod.hurt);
    g.rig.addShake(if (heavy) SHAKE_HURT_HEAVY else SHAKE_HURT);
    if (voice) sfx.play(if (heavy) .hurt_heavy else .hurt);
}

// ── THE FOE ROLL-UPS ── the three groups, summed in ONE place each. Every one of these was written
// out as `g.warren.X() + g.line.X() + g.grief.X()` at each site — `totalHits` three separate times —
// which is the parallel-list-in-lockstep failure the FoeRef switch was already fixed for: a fourth
// foe means editing every copy, and a copy you miss silently stops counting (the debug read-out once
// ignored every blow landed on anything but a toad, for exactly this reason).
fn allHits(g: *const Game) u32 {
    return g.warren.totalHits() + g.line.totalHits() + g.grief.totalHits();
}
fn allAlive(g: *const Game) u32 {
    return g.warren.aliveCount() + g.line.aliveCount() + g.grief.aliveCount();
}
fn anyFoeDied(g: *const Game) bool {
    return g.warren.anyDied() or g.line.anyDied() or g.grief.anyDied();
}
fn allRunes(g: *const Game) u32 {
    return g.warren.runesDropped() + g.line.runesDropped() + g.grief.runesDropped();
}

// The hero's blade this frame as plain data for the foe hit test (endpoints guard→tip, plus
// last frame's for the swept test; active only inside the strike window). Typed on the FOE
// STANDARD directly (foe.Blade), not on frog.zig's re-export — the blade is every foe's business.
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

// Resolve XZ footprint collisions (see collision.zig). Hero has priority (pushed out of
// solids, then grounded toads); toads then yield to world/hero/grounded neighbours.
// Airborne toads (mid-hop) are skipped so a leap arcs over you cleanly.
// Clamp a resolved XZ position back inside the play bounds. Four actor loops in collideActors each
// had their own copy of this pair of clampF lines.
fn inBounds(p: rl.Vector3) rl.Vector3 {
    return v3(mathx.clampF(p.x, -PLAY_HALF, PLAY_HALF), p.y, mathx.clampF(p.z, -PLAY_HALF, PLAY_HALF));
}

fn collideActors(g: *Game, dt: f32) void {
    const step = COLLIDE_RATE * dt; // max correction this frame — bigger pushes ease in (no warp)
    // Each actor resolves against the solids in its OWN neighbourhood (env.resolveActor queries
    // the prop grid). The world holds ~700 solids now; scanning all of them per actor, twice a
    // frame, was the other thing that would not have survived the expansion.
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

    // Archers yield last: each pushed out of world, hero, every grounded toad, and fellow
    // archers (same easing so a kite step into a wall slides, not warps).
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

    // The ogre yields to the WORLD (walls/columns) only, never to the tiny hero (who yields
    // above), so it reads as immovable bulk.
    for (g.grief.live()) |*o| {
        if (!o.alive()) continue;
        const op = g.env.resolveActor(o.pos, o.bodyR());
        o.pos = mathx.approachV(o.pos, inBounds(op), step);
    }
}

// ── lock-on helpers (generic over ANY foe via FoeRef) ──────────────────────────────────
// A reference to a locked foe across the heterogeneous groups; lock-on and the reticle dispatch through the
// foe* accessors, so every foe type is lockable. A dying foe is NEVER a target — run()'s kill handler
// drops or switches the lock the frame it dies, and no acquire/cycle may pick a corpse back up.
//
// THE MAP'S own foe enum, not a second one: a local `enum { toad, archer, ogre }` sat beside
// `worldfmt.FoeKind`'s identical tags, two parallel lists kept in lockstep by hand where a fourth foe means
// editing both and nothing catches the one you miss.
const FoeKind = worldfmt.FoeKind;
const FoeRef = struct { kind: FoeKind, idx: usize };
fn foePos(g: *const Game, r: FoeRef) rl.Vector3 {
    return switch (r.kind) {
        .toad => g.warren.frogs[r.idx].pos,
        .archer => g.line.archers[r.idx].pos,
        .ogre => g.grief.ogres[r.idx].pos,
    };
}
fn foeLockPoint(g: *const Game, r: FoeRef) rl.Vector3 {
    return switch (r.kind) {
        .toad => g.warren.frogs[r.idx].lockPoint(),
        .archer => g.line.archers[r.idx].lockPoint(),
        .ogre => g.grief.ogres[r.idx].lockPoint(),
    };
}
// A live, non-dissipating foe (both a fresh acquire and a held lock require this).
fn foeLockable(g: *const Game, r: FoeRef) bool {
    return switch (r.kind) {
        .toad => g.warren.frogs[r.idx].alive() and !g.warren.frogs[r.idx].dying(),
        .archer => g.line.archers[r.idx].alive() and !g.line.archers[r.idx].dying(),
        .ogre => g.grief.ogres[r.idx].alive() and !g.grief.ogres[r.idx].dying(),
    };
}
fn lockValid(g: *const Game, r: FoeRef) bool {
    return foeLockable(g, r) and mathx.distXZ(g.hero.pos, foePos(g, r)) <= MAX_LOCK_R + 2.0;
}

// A world point projected to the screen, or null if nearer than the near-clip plane — the
// shared front-of-camera cull for the lock reticle, foe HP bars, and lock-screen-x. The
// threshold must be the near clip distance, not just depth > 0: a point at depth ~0+
// projects to an unbounded coord, so callers' @intFromFloat(s.x) would panic (out-of-range
// cast) in safe builds.
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

// The foe nearest screen-centre and in range (ER locks what you look at); null if none, so
// the caller recenters. Considers all groups so any foe is lockable.
fn acquireLock(g: *Game) ?FoeRef {
    const cx = @as(f32, @floatFromInt(rl.getScreenWidth())) * 0.5;
    var best: ?FoeRef = null;
    var bestScore: f32 = 1e9;
    considerLock(g, g.warren.live(), .toad, cx, &best, &bestScore);
    considerLock(g, g.line.live(), .archer, cx, &best, &bestScore);
    considerLock(g, g.grief.live(), .ogre, cx, &best, &bestScore);
    return best;
}
// One group's contribution to acquireLock — generic over the foe type (the shared contract).
fn considerLock(g: *Game, foes: anytype, kind: FoeKind, cx: f32, best: *?FoeRef, bestScore: *f32) void {
    for (foes, 0..) |*f, i| {
        if (!f.alive() or f.dying() or mathx.distXZ(g.hero.pos, f.pos) > MAX_LOCK_R) continue;
        const r = FoeRef{ .kind = kind, .idx = i };
        const sx = lockScreenX(g, r) orelse continue;
        const score = @abs(sx - cx);
        if (score < bestScore.*) {
            bestScore.* = score;
            best.* = r;
        }
    }
}

// Switch to the next in-range foe whose screen-x lies on `dir` side (-1 left / +1 right) of
// the current target — the right-stick / mouse flick cycle, across both groups.
fn cycleLock(g: *Game, dir: f32) void {
    const cur = g.lock orelse return;
    const curX = lockScreenX(g, cur) orelse return;
    var best: ?FoeRef = null;
    var bestGap: f32 = 1e9;
    considerCycle(g, g.warren.live(), .toad, cur, curX, dir, &best, &bestGap);
    considerCycle(g, g.line.live(), .archer, cur, curX, dir, &best, &bestGap);
    considerCycle(g, g.grief.live(), .ogre, cur, curX, dir, &best, &bestGap);
    if (best) |b| g.lock = b;
}
fn considerCycle(g: *Game, foes: anytype, kind: FoeKind, cur: FoeRef, curX: f32, dir: f32, best: *?FoeRef, bestGap: *f32) void {
    for (foes, 0..) |*f, i| {
        const r = FoeRef{ .kind = kind, .idx = i };
        if ((cur.kind == kind and cur.idx == i) or !f.alive() or f.dying()) continue;
        if (mathx.distXZ(g.hero.pos, f.pos) > MAX_LOCK_R) continue;
        const sx = lockScreenX(g, r) orelse continue;
        const gap = (sx - curX) * dir;
        if (gap > 5.0 and gap < bestGap.*) {
            bestGap.* = gap;
            best.* = r;
        }
    }
}

// The world-reload half of a hero death (ER: dying resets the field). Every group re-homes
// fresh instances (full HP, home positions, slain restored), the arrow pool empties, the
// lock drops. Instance state only — shared Models are permanent, never rebuilt.
fn resetFoes(g: *Game) void {
    g.warren.reset(&g.map);
    g.line.reset(&g.map);
    g.grief.reset(&g.map);
    g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
    g.lock = null;
}

// A foe's bar only appears once you've HURT it, and lingers this long after the last hit —
// so untouched foes stay unmarked and the bar fades from view when you disengage.
const HURT_BAR_WINDOW = 5.0;

// Floating HP bars over ANY foe group (shared foe contract, one loop for all). Shown only
// for a live foe hit within HURT_BAR_WINDOW; flashes gold while staggered (the wide-open
// cue). Untouched foes stay unmarked.
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
    // A glowing white dot — a radial GRADIENT glow (bright centre → transparent edge) with a
    // small crisp core, no dark halo. Pure light (owner's call).
    rl.drawCircleGradient(x, y, 15, rgba(255, 255, 255, 175), rgba(255, 255, 255, 0));
    rl.drawCircle(x, y, 2, rl.Color.white); // crisp hot centre
}

