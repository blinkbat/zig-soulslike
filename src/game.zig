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
const item = @import("item.zig"); // …and what is in them
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
const STRAFE_SPEED = heromod.STRAFE_SPEED; // LOCKED-ON sideways travel, as a fraction of forward —
//   the rig's number, beside the three speeds above, because the SIDESTEP CADENCE it sets is a
//   property of the rig and hero.zig's own cadence test needs it (it used to hold a second copy of
//   the literal, with a comment pointing here). See moveHero.
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
// A CAUGHT blow cracks the frame less than one that lands — he HELD, and the shake says so. Scaled
// at the call site by the weight of what was caught, so this is the ogre's club and a toad's bite is
// a quarter of it.
const SHAKE_BLOCK = 0.40;
// …and the guard BREAKING is worse than any single hit bar the last one: it is the moment you find
// out the next blow is free.
const SHAKE_GUARD_BREAK = 0.72;
// THE HEAVIEST BLOW IN THE GAME, which is what a caught one is weighed against — read off the ogre's
// own table rather than typed as a number, so re-tuning his club re-scales the block feedback with
// it instead of quietly pinning every block at full weight.
const BLOW_HEAVIEST = ogremod.SLAM_HIT.dmg;
const BLOCK_FELT_MIN = 0.25; // …even the smallest blow is FELT: a block you cannot feel reads as a whiff
const BLOCK_FELT_HEAVY = 0.5; // …and past half the club, the pad's heavier signature takes over
const SHAKE_DEATH = 0.85;
// …and the ONE non-combat beat: a chest coming open. Here with the rest of the ladder rather than as a
// literal at the call site, because that ladder is how the whole game's impact weight is read against
// itself — a bare number in `interact` is a felt weight nobody can compare to a landed hit.
const SHAKE_CHEST = 0.12;
// The YOU DIED tail, in two beats. The HOLD is the important one: black used to be reached on
// exactly the frame the respawn fired and to start lifting on the very next one, so the card cut
// straight into a lit meadow and the whole sequence read as a glitch rather than as a death. A beat
// of solid nothing is what lets it land.
const RESPAWN_HOLD = 0.55; // seconds of FULL black after the respawn…
const RESPAWN_FADE = 0.9; // …then this long fading up into the fresh world

// Hero movement clamp: the MAP's bounds inset so travel and rolls cannot reach the edge. One source for
// moveHero, the roll/attack updates, every foe and the --shot harness. A `var` refreshed from the live map
// each frame, NOT a comptime constant: the map owns the world's size and the editor can swap it mid-frame.
pub var PLAY_HALF: f32 = worldfmt.DEFAULT_HALF - envmod.PLAY_INSET;

// Hero footprint radius for ground collision (see collision.zig). Defined in foe.zig alongside
// foe.HERO_REACH, so a foe's attack shapes can be reasoned about against how close he can GET.
const HERO_R = foemod.HERO_R;

// Skeletal-archer arrows: shared pool of in-flight + stuck shafts, plus the hero centre-of-
// mass height archers aim at and arrows test strikes against.
const MAX_ARROWS = 24;
/// The hero's centre of mass ABOVE HIS OWN FEET — not a world height. It was both while the world was
/// flat, and reading it as a world height on sculpted terrain aims every arrow at the datum: an archer
/// on the plain shooting a hero on a 10 m bank puts the shaft through the hillside below him.
pub const HERO_CENTER_Y = 1.0;

// Collision correction is rate-limited so a large depenetration eases in over a few frames
// (smooth slide, not a choppy warp). Set above the fastest actor speed so wall contact
// still resolves firmly (no sinking).
const COLLIDE_RATE = 11.0; // world units / sec

// ── STANDING ON SCULPTED GROUND ────────────────────────────────────────────────────────
// An actor's `pos.y` is the ground under them, written HERE for the hero and every foe (`groundActor`);
// the rigs only read it. EASED, NOT SNAPPED — a step is a discontinuity the moment you cross it and the
// camera rides the hero's shoulder, so a snap kicks the whole frame. Asymmetric on purpose: walking off
// a lip must drop faster than a climb lifts, or he moon-walks off it.
const GROUND_RISE_RATE = 9.0; // m/s the body climbs onto higher ground…
const GROUND_FALL_RATE = 16.0; // …and falls onto lower (gravity-ish, no real fall state yet)
/// Past this the ease is abandoned and the actor is planted: a teleport (respawn, F5 playtest, the shot
/// harness) must not spend a second sliding up out of the earth, and no real step is anywhere near it.
const GROUND_SNAP: f32 = 2.5;

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

/// What the two look devices said this frame, which one owns the camera, and what the camera actually
/// DID with them. RAW values on purpose — the point is what arrives before the deadzone eats it — plus
/// `mag` (the only number that separates a resting deflection from a real push) and `dyaw` (zero with
/// your hands off means nothing drifts and the complaint is sensitivity).
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
    bag: item.Bag = .{}, // …and what came out of them. The hero's, but held here with the rest of the run
    arrowModel: rl.Model, // shared arrow mesh, drawn per live/stuck arrow with its own matrix
    stoneModel: rl.Model, // …and the slingers' stone, drawn from the SAME pool (see Arrow.stone)
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
        // …AND THE SCULPTED GROUND, which `materialize` needs even more urgently than the water: every
        // prop is planted at the height under it, so replaying the ops against a flat field stands the
        // whole world at the wrong elevation.
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
        // Foes come from the MAP, so the groups can only be homed once it is loaded — init
        // builds the shared meshes and nothing else.
        g.warren.reset(&g.map);
        g.line.reset(&g.map);
        g.grief.reset(&g.map);
        g.band.reset(&g.map);
        // …and the chests come from the PROPS, so this goes after `materialize` rather than beside the
        // foe groups: a chest's position is where env actually planted it (see `env.chestSites`).
        rehomeChests(g);
        g.bag = .{};
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.stoneModel = koboldmod.stoneMesh(g.scene.shader);
        g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
        // Fields that would otherwise take their struct-literal defaults; set explicitly
        // because there is no literal to default from any more.
        g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
        g.editor = .{};
        g.lock = null;
        g.rumble = .{};
        g.deathFade = 0;
        // …the look probe included: `Game` is built in place from `alloc.create`, so a field this block
        // misses never gets its default at all — and `pad` is a bool, where raw heap bytes are illegal
        // behaviour rather than merely a wrong caption.
        g.probe = .{};
    }
};

// ── input → intent ─────────────────────────────────────────────────────────────────
// fx = camera-right axis, fz = camera-forward axis (pre-normalization); speed = resolved
// ground speed this frame (0 = idle). ZERO input lag (owner's rule): the analog tilt maps
// STRAIGHT to ground speed every frame — light tilt walks, full tilt runs, NOW — and
// keyboard movement is an immediate run (hold sprint for the dash). No hold gates.
const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

/// A STICK, DEADZONED RADIALLY — direction and magnitude kept apart, which is what a twin-stick camera
/// (ER's included) does. Per-AXIS deadzoning is a square gate and wrong twice over: it eats the small
/// component whole, so a stick held 15° off horizontal comes out 3° off it and everything creeps toward
/// the cardinals; and a full diagonal rescales to ~0.88, so the stick is slower diagonally than axially.
///
/// `curve` shapes the magnitude only: 1 = linear, >1 = fine near the centre, same top rate at the rim.
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

/// PLANT AN ACTOR ON THE GROUND: ease `pos.y` toward the terrain height under its feet. See the rate
/// constants above for why this is eased rather than assigned. Returns nothing — it writes `pos.y`,
/// which is the one place any actor's height comes from.
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

/// …and PLANT ONE NOW, with no ease: a spawn, a respawn, an editor playtest drop. Anything that decides
/// where an actor IS rather than where it is going.
fn plantActor(g: *const Game, pos: *rl.Vector3) void {
    pos.y = g.env.groundAt(pos.x, pos.z);
}

/// The ground height, as the camera rig wants it: a plain function over a context, so `camera.zig` can
/// keep the eye out of the terrain without knowing what a height field is. PUBLIC because the `--shot`
/// harness frames through the same `followClear` the live loop does — a shot camera that clipped into
/// terrain the real one avoids would be photographing a bug that isn't there.
pub fn envGroundAt(e: *const envmod.Env, x: f32, z: f32) f32 {
    return e.groundAt(x, z);
}

/// Where each live foe stands, for the terrain gate below. Generic over any group's `live()` slice.
fn snapshotPos(foes: anytype, out: []rl.Vector3) void {
    for (foes, 0..) |*f, i| {
        if (i >= out.len) return;
        out[i] = f.pos;
    }
}

/// THE FOES GET THE SAME GROUND RULES THE HERO DOES. Each moved itself during its own update, knowing
/// nothing about the terrain; this re-takes that displacement through `env.walkStep`, so a hunting toad
/// or a kiting archer is held off ground too steep to walk exactly as the player is — and cannot chase
/// you up a cliff face.
///
/// AIRBORNE FOES ARE LEFT ALONE: a toad's lunge and an archer's backstep are committed leaps, and a leap
/// is entitled to cross ground you could not walk. Their landing is grounded by `groundActor` like
/// everything else.
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
        // THE TERRAIN DECIDES WHETHER THE STEP HAPPENS (env.walkStep): a slight step or an incline
        // inside the slope limit is taken, anything steeper has its uphill component refused and the
        // hero slides along the face. `moved` is left alone on purpose — it drives the STRIDE PHASE,
        // and shortening it because a cliff refused the step would slow the leg cycle to a crawl while
        // he pushes against it, which reads as the animation breaking rather than as the hill winning.
        const stepped = g.env.walkStep(g.hero.pos, dir, moved);
        g.hero.pos.x = mathx.clampF(stepped.x, -PLAY_HALF, PLAY_HALF);
        g.hero.pos.z = mathx.clampF(stepped.z, -PLAY_HALF, PLAY_HALF);
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

/// The hero's posture on the ground he is standing on: ease the whole-body lean toward what the slope
/// under him asks for. Measured along his FACING, not his travel, so backing down a bank leans back —
/// the lean is about the hill, not about the direction he happens to be going.
///
/// Runs for EVERY hero state, not just walking: standing still on a bank is exactly when you notice an
/// upright body, and `pose()` is what draws him then too.
fn leanToGround(g: *Game, dt: f32) void {
    const face = mathx.headingDir(g.hero.facing);
    const want = heromod.slopeLean(g.env.slopeAlong(g.hero.pos.x, g.hero.pos.z, face));
    g.hero.slopePitch = mathx.approach(g.hero.slopePitch, want, heromod.SLOPE_LEAN_RATE * dt);
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
    // THE CHEST LIDS, with the props and not after them: a lid is a caster like the box under it, and
    // drawn outside this function it would be missing from the shadow map — a chest with its lid thrown
    // back would cast the shadow of a closed one.
    g.chests.draw();
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
    g.band.draw(&g.scene);
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
    g.warren.setShader(sh);
    g.line.setShader(sh);
    g.grief.setShader(sh);
    g.band.setShader(sh);
    // THE CHEST LIDS TOO. `drawCasters` draws them in BOTH passes, so a lid left on the scene shader is
    // rasterized into the shadow map through a shader that SAMPLES that same map — and pays the whole
    // point-light loop per fragment for a pass whose colour is thrown away. `Chests.setShader` existed
    // for exactly this and had no caller.
    g.chests.setShader(sh);
}

/// The WORLD height of the hero's centre of mass — his feet plus `HERO_CENTER_Y`. What an archer aims
/// at and what an arrow tests its strike against; one definition, so the aim and the hit can't disagree.
pub fn heroCenterY(g: *const Game) f32 {
    return g.hero.pos.y + HERO_CENTER_Y;
}

/// …and that centre as a point, which is what a loose is aimed at.
fn heroAimPoint(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, heroCenterY(g), g.hero.pos.z);
}

// Launch an arrow from a free pool slot (the loose event). Pool-full is rare (24 slots vs a
// ~1.5s reload on two archers); overwrite slot 0 rather than silently drop the shot.
fn spawnArrow(g: *Game, from: rl.Vector3, target: rl.Vector3) void {
    poolPut(g, archermod.launchArrow(from, target));
}

/// A SLINGER'S STONE into the SAME pool — see `archer.Arrow.stone`. Passed to `Warband.update` as the
/// comptime `loose` callback, which is how the kobolds reach a projectile pool they know nothing about.
pub fn spawnStone(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchStone(from, heroAimPoint(g), koboldmod.STONE_SPEED));
}

// A chest is a PROP with a lid and a state, so the list is rebuilt from the props whenever the world is.
// RE-HOMING SHUTS EVERY LID — the honest trade for no per-instance save, and only a load or an editor
// edit re-materializes.
fn rehomeChests(g: *Game) void {
    var sites: [chestmod.CAP]chestmod.Site = undefined;
    const n = g.env.chestSites(&sites);
    g.chests.reset(sites[0..n]);
}

/// Shims for the shot harness, so it drives the same two calls the loop does.
pub fn rehomeChestsForShot(g: *Game) void {
    rehomeChests(g);
}
pub fn openChestForShot(g: *Game) bool {
    const had = g.chests.near != null;
    interact(g);
    return had;
}

/// OPEN THE CHEST IN REACH. The whole interaction: `chest.zig` decides whether there is one (so the reach
/// test lives in one place), and what comes back goes into the bag HERE, because the bag is the hero's and
/// a chest has no business knowing he exists.
fn interact(g: *Game) void {
    const got = g.chests.openNear(&g.map) orelse return;
    for (got.loot) |it| g.bag.add(it, 1);
    if (got.loot.len > 0) sfx.world(.item_get, got.at);
    // The same beat a landed blow gets, at a fraction of it: a chest is a good thing happening, and under
    // the NO HITSTOP law the way anything is felt here is shake and rumble, never a pause.
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

// Pool-full is rare (24 slots against a ~1.5 s reload); overwrite slot 0 rather than silently drop the
// shot. One place, so an arrow and a stone can never disagree about what a full pool means.
fn poolPut(g: *Game, a: archermod.Arrow) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) {
            ar.* = a;
            return;
        }
    }
    g.arrows[0] = a;
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
        const m = if (ar.stone) &g.stoneModel else &g.arrowModel;
        rl.drawMesh(m.meshes[0], m.materials[0], archermod.arrowXform(ar));
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
    // The GROUND under the editor's aim, not the datum: the shadow box tracks its focus in all three
    // axes now (gfx.beginShadowPass), and dressing a hilltop with the box 20 m below it drops every
    // cast shadow up there.
    if (!g.editor.on) return g.hero.pos;
    const t = g.editor.cam.target;
    return v3(t.x, g.env.groundAt(t.x, t.z), t.z);
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
    g.env.drawGround(&view); // sculpted terrain is tiled, so it culls against the same frustum
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
    g.band.drawFx(); // kobold blood, death motes, and the priest's cast gathering into its staff
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
    drawFoeBars(g, g.band.live()); // …and the whole warband, roles mixed in one array
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
        hud_.vitals(dt, g.hero.vit.hpFrac(), g.hero.fp.frac(), g.hero.stam.frac(), g.hero.stamRefused / combat.STAM_REFUSE_FLASH, g.hero.stam.windedTo());
        // The one-line translation combat.FlaskKind → hud.FlaskTint: hud takes plain values and
        // knows nothing about the combat layer, so the mapping belongs on this side of the fence.
        hud_.equipment(switch (g.hero.flasks.sel) {
            .crimson => hud_.FlaskTint.crimson,
            .cerulean => hud_.FlaskTint.cerulean,
        }, g.hero.flasks.ready());
        hud_.runes(g.hero.runes.display()); // the ROLLING value, not the banked total
        // …and the INTERACT prompt, when there is something to interact with. ER's own place for it:
        // low centre, above the bars' line, plain and small. It is not on the object in the world,
        // because a floating world-space label is a different game's UI language.
        if (g.chests.near != null) hud_.prompt("E / A  Open");
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

    // POS CARRIES ITS HEIGHT, and the ground carries its SLOPE — the two numbers you need to tell "the
    // hill refused my step" from "something else is wrong". `slope` is degrees under his feet against
    // env.MAX_SLOPE's 40; `lean` is what the rig is doing about it.
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

    // ── THE LOOK PROBE ── stick drift, cursor jitter and too-high sensitivity all look identical on
    // screen. Take your hands off both devices and read the row: `dyaw` 0 means nothing drifts and what
    // feels wrong is the RATE; `mag` over LOOK_DEADZONE means hardware drift is getting through; `mouse`
    // non-zero at rest means something is driving the OS cursor (a pad through a mouse-emulation layer).
    // `look PAD/MOUSE` is the latch that says who owns the camera, not a preference.
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

/// WHICH GAIT A GROUND SPEED IS, in one place. Two callers ask it — the debug readout's caption and
/// the footstep VOICE — and each wrote out the same pair of `>= X_SPEED - 0.3` tests with the same
/// unnamed slack. Two copies of a threshold that is only ever meant to mean one thing, so the boot
/// you hear and the word on screen could disagree about what you are doing after any retune of
/// either. The slack is named here as well: it exists because `speed` is the frame's RAW travel rate
/// and a stick held at full tilt lands a hair under the constant it is nominally clamped to.
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
        // …EXCEPT while its jukebox is up, which is a sound tool and would otherwise play into a mute.
        sfx.mute(g.editor.on and !g.editor.auditioning());

        // Pad SELECT opens the GAME menu, pad START the CHARACTER one; TAB is START's keyboard twin.
        // NOT WHILE THE EDITOR IS UP: Esc is the editor's own back-out key and this runs before its
        // branch, so an odd number of them used to leave the pause card open behind it.
        if (!g.editor.on) {
            if (rl.isKeyPressed(.escape)) g.menu.onEscape();
            if (rl.isKeyPressed(.tab)) g.menu.onStartButton();
            if (rl.isGamepadAvailable(PAD)) {
                if (rl.isGamepadButtonPressed(PAD, .middle_left)) g.menu.onSelectButton();
                if (rl.isGamepadButtonPressed(PAD, .middle_right)) g.menu.onStartButton();
            }
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
                    plantActor(g, &g.hero.pos); // …on the ground, AFTER the push-out moved him in XZ
                    g.hero.setSpawn(g.hero.pos, g.hero.facing);
                    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
                    wasInside = false; // swallow the mouse delta the editor's look accumulated
                },
            }
            g.hero.held = true;
            // …and the shield comes DOWN. `setGuard` only runs on the live path, so a hero who was
            // guarding when Editor was opened stands in the dressing scene braced behind a shield —
            // and then F5s into a playtest still holding it. Nothing here gives him input; he should
            // not be holding a stance either. It comes straight back on the first live frame, since
            // the guard is read as a LEVEL and not an edge.
            g.hero.setGuard(false);
            g.hero.pose();
            // Re-home the foes from the map every frame the editor is up, so moving a spawn
            // moves the thing you can SEE. They are not updated while editing, so re-spawning
            // them costs nothing and there is no animation state to lose.
            g.warren.reset(&g.map);
            g.line.reset(&g.map);
            g.grief.reset(&g.map);
            g.band.reset(&g.map);
            // …and the chests with them, for the same reason and off the same source of truth: moving,
            // adding or deleting a box has to move the box you can SEE. Off `env`'s prop list rather than
            // the map's ops, so it follows the world the editor has actually rebuilt.
            //
            // MEASURED AND LEFT: this is a full scan of the prop list (~17k byte compares, tens of µs)
            // once a frame, and it is paid only while the editor is open — the same order as the Ground
            // panel's own grid scan, and for the same reason. Gating it on "the world rebuilt this frame"
            // would mean a flag the editor sets and four edit paths must remember, to save µs in a tool.
            rehomeChests(g);
            // …AND THE GRIP GOES QUIET, envelopes still decaying — the same call the pause card makes,
            // for the same reason. Without it the editor branch never ticks the rumble at all: a live
            // envelope froze for the whole editing session and then replayed as a phantom buzz on the
            // frame you left, which is precisely what `update`'s `active` flag exists to prevent.
            g.rumble.update(rawDt, false);
            drawScene(g);
            editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, rawDt);
            rl.endDrawing();
            continue;
        }

        g.hero.held = g.menu.isOpen();
        if (g.menu.isOpen()) {
            // World holds while the menu is up: no camera/move input, but the hero keeps
            // breathing (idle update, zero travel) so the scene stays alive.
            switch (g.menu.update(&g.retro, rawDt, &g.bag)) {
                .quit => break,
                .editor => {
                    // Drop the lock on the way in: the reticle rides a FoeRef into groups the
                    // editor re-homes from the map every frame, so a held lock survives into a
                    // world where its index means something else.
                    g.lock = null;
                    g.editor.enter(g.hero.pos);
                },
                // AN ITEM USED FROM THE BAG. The menu decides WHICH and this decides what that means
                // — it is the loop that owns both the bag and the hero. Spent only if a charge
                // actually came out, and the menu stays open, so eating two is two presses.
                .use => |k| useItem(g, k),
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
            g.menu.draw(&g.retro, &g.bag);
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
            // ── ONE LOOK DEVICE AT A TIME ── never the SUM of mouse and stick: a pad through a
            // mouse-emulation layer puts a stick on the OS cursor, and a resting deflection on one
            // device must not add to the other. The last device to give a REAL look input owns the
            // camera and the other is dead until it gives one of its own — a latch, not a lockout.
            const look = stickRadial(padRX, padRY, LOOK_DEADZONE, LOOK_CURVE);
            lookMag = padMag;
            // MOUSE_WAKE, not zero: a hidden-but-uncaptured cursor picks up a pixel of jitter from
            // the desk, and one pixel used to be enough to take the camera off the stick.
            const mouseLook = inside and wasInside and (@abs(md.x) + @abs(md.y)) > MOUSE_WAKE;
            // ── CLAIMING THE CAMERA IS A DIFFERENT QUESTION FROM TURNING IT. A worn right stick RESTS
            // at 0.15-0.25, past LOOK_DEADZONE, so claiming on anything that merely clears the deadzone
            // pins the latch to PAD on frame one and the mouse never works again. The CLAIM takes a
            // decisive push (LOOK_CLAIM); the TURN still starts at the deadzone. Drift reaches the
            // second and never the first.
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

        // ── INTERACT (ER) ── A / Cross, or E on the keyboard, which is ER's own default for it. The only
        // free face button and the one every soulslike puts this on. Nothing but chests answers it yet, and
        // `interact` is a no-op when there is nothing in reach — so no gating here beyond being alive.
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

        // ── GUARD (ER/DS layout) ── L1/LB, or the RIGHT MOUSE BUTTON, which is ER's own keyboard
        // default for the left hand. HELD, not toggled, and read as a level rather than an edge: the
        // shield is up exactly while the button is down and the hero decides whether he may have it
        // (hero.setGuard, called once below after the sprint is settled).
        var guardHeld = rl.isMouseButtonDown(.right);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonDown(PAD, .left_trigger_1)) guardHeld = true;

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
        // …and anything he ATE drips HP back. Here beside `vit.tick` and not in `hero.tickClocks`
        // for the reason the field says: it is a combat clock and it must hold under the menu.
        g.hero.regen.tick(dt, &g.hero.vit);
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
        // …and the shield, AFTER the sprint (there is no running block — see hero.setGuard). Nothing
        // here has to un-set it: an attack, a roll, a sprint or a stagger all fail `canGuard` on the
        // frame they start, so the guard drops itself.
        g.hero.setGuard(guardHeld);
        // BEHIND THE SHIELD HE SHUFFLES. Capped at the source like the sprint denial above, so the
        // one Move every downstream reader sees already knows about it — and the cap is on the WALK,
        // never a zero: guarding slows you, it does not root you.
        if (g.hero.guarding) mv.speed = @min(mv.speed, WALK_SPEED * heromod.GUARD_SPEED);

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        // The slope under him, eased into the rig BEFORE it poses — every branch below ends in a
        // `pose()`, so this has to be settled first or the lean is always one frame stale.
        leanToGround(g, dt);
        // WHERE EVERY FOE STOOD BEFORE IT ACTED. The terrain gate below re-takes each one's step
        // through `env.walkStep`, which is how a foe inherits the hero's slope limit and step height
        // without every rig having to learn about the world. Snapshotting is the price of the AI
        // moving itself: the alternative is threading the Env through three creatures' update paths.
        var wasToad: [worldfmt.MAX_PER_KIND]rl.Vector3 = undefined;
        var wasArcher: [worldfmt.MAX_PER_KIND]rl.Vector3 = undefined;
        var wasOgre: [worldfmt.MAX_PER_KIND]rl.Vector3 = undefined;
        // The warband is THREE kinds in one array, so its snapshot is three times the per-kind cap —
        // sized off `kobold.CAP` rather than restating the arithmetic.
        var wasBand: [koboldmod.CAP]rl.Vector3 = undefined;
        snapshotPos(g.warren.live(), &wasToad);
        snapshotPos(g.line.live(), &wasArcher);
        snapshotPos(g.grief.live(), &wasOgre);
        snapshotPos(g.band.live(), &wasBand);
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
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            // The lunge carries stance damage; the chomp doesn't — split the felt blow by that.
            _ = heroTakes(g, b, b.hit.stance > 0, true);
        }
        // The lone ogre hunts, slams and side-swipes. The overhead crush is the full heavy beat; the
        // faster swipe hurts less and is FELT less, so the two read apart through the pad and camera
        // as well as on screen (split off the blow's own stance damage, like the toad's above).
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= ogremod.SLAM_HIT.stance, true);
        }
        // Blade lands on the skeletons; then they act — kite and loose from the nock at the
        // hero's centre of mass (arrow homing + arc finish the job). A blade hit mid-draw
        // interrupts the shot (enterStun clears the draw).
        for (g.line.live()) |*a| {
            if (a.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), heroAimPoint(g));
            }
        }
        // THE WARBAND acts as one group, because the priest's heal has to see the whole band (see
        // kobold.Warband). It hands back at most one blow a frame — a berserker's axe or a slinger's
        // teeth, both already latched to land once per swing — and looses its stones through
        // `spawnStone`, passed as the comptime callback so kobold.zig never learns what a pool is.
        if (g.band.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnStone)) |b| {
            // A chop is the heavier of the two, and it is the one that carries poise — split the felt
            // weight on the blow's own numbers rather than on which creature threw it.
            _ = heroTakes(g, b, b.hit.poise >= koboldmod.ZERK_HIT.poise, true);
        }
        // The lids swing and the "which one is in reach" answer is recomputed — once, here, so the prompt
        // the player reads and the button they then press cannot disagree about which box they mean.
        g.chests.update(dt, g.hero.pos);
        // …and the ground has its say about all of them: every step a foe just took is re-taken through
        // the slope limit, so none of them walks up anything the hero couldn't.
        gateTerrain(g, g.warren.live(), &wasToad);
        gateTerrain(g, g.line.live(), &wasArcher);
        gateTerrain(g, g.grief.live(), &wasOgre);
        gateTerrain(g, g.band.live(), &wasBand);
        // Arrows in flight: gentle homing + arc, then a strike lands a chomp-weight blow.
        // A hero inside the roll's i-frames is NOT a target (shaft passes through). World
        // solids BLOCK shots (cover works) — a blocked arrow thunks into stone.
        for (&g.arrows) |*ar| {
            if (!ar.live) continue;
            ar.hit = false;
            // The GROUND under the shaft, so it plants in a hillside instead of diving through it to
            // find y = 0 — and the hero's centre measured from HIS ground, not from the datum, or an
            // archer shooting up a bank aims at the hero's knees.
            archermod.stepArrow(ar, g.hero.pos, heroCenterY(g), g.env.groundAt(ar.pos.x, ar.pos.z), g.hero.iFramed(), arrowCover(g, ar, dt), dt);
            if (ar.hit) {
                // It found the hero. A STONE IS NOT AN ARROW: `Arrow.stone` decides which blow it deals. A shaft's
                // direction comes off its own FLIGHT, reversed — by the frame it connects the arrow
                // is standing in him, so its POSITION says nothing about where it was shot from, and
                // the shield has to answer exactly that.
                const blow = foemod.Blow{
                    .hit = if (ar.stone) koboldmod.STONE_HIT else archermod.ARROW_HIT,
                    .from = mathx.addV(g.hero.pos, mathx.scaleV(ar.vel, -1)),
                };
                // The BEAT is skipped on a corpse. It takes the grip and the camera and no grunt — the
                // rip IS this blow's voice (heroTakes' `voice`).
                const out: combat.HitOutcome = if (g.hero.dead) .ignored else heroTakes(g, blow, false, false);
                // …and WHAT IT STRUCK picks that voice: boards if the shield caught it, flesh if not.
                // The SOUND is never skipped on a corpse — the shaft still landed in him, and testing
                // `!dead` on the whole branch once dropped a hit on a dying hero into the world-impact
                // arm below, which scuffed DIRT for an arrow standing in his chest.
                if (out == .taken or out == .ignored) sfx.play(.arrow_hit);
            } else if (ar.stuck and ar.age == 0) {
                // It STUCK without connecting — into cover or into the earth, and that gets its own
                // sound: a shaft thunking off the pillar you ducked behind is the game telling you the
                // cover WORKED. `age == 0` is the sticking frame exactly and needs no state of its own.
                // WHICH thunk is chosen by the SURFACE, beside the voices it picks from
                // (`sfx.arrowImpact`), not here.
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
        // …and EVERYTHING SETTLES ONTO THE GROUND, last: collision moves actors in XZ (out of walls,
        // off each other), so their height is only known once that is done. Before it, a hero pushed
        // out of a wall onto lower ground would spend the frame at the wall's height.
        groundActor(g, &g.hero.pos, dt);
        for (g.warren.live()) |*f| groundActor(g, &f.pos, dt);
        for (g.line.live()) |*a| groundActor(g, &a.pos, dt);
        for (g.grief.live()) |*o| groundActor(g, &o.pos, dt);
        for (g.band.live()) |*k| groundActor(g, &k.pos, dt);
        g.rig.tickShake(rawDt); // impact shake decays on wall-clock time (bakes this frame's jitter)
        // …and the boom shortens rather than burying the eye in the hillside behind him (see
        // camera.followClear). On sculpted ground this is not an edge case: it happens on every climb.
        g.rig.followClear(g.hero.shoulderPoint(), &g.env, envGroundAt);
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
    const id: sfx.Id = switch (gaitOf(h.speed)) {
        .sprint => .step_sprint,
        .run => .step_hard,
        .walk => .step_soft,
    };
    // Quieter the slower he goes, on top of the voice change — a careful walk should not land as
    // hard as a sprint that happens to be crossing the same phase.
    sfx.playAt(id, mathx.clampF(0.45 + 0.55 * h.speed / SPRINT_SPEED, 0.35, 1.0));
}

// ── THE HERO WAS HURT ── the rumble + camera crack + voice for one blow landing on him, in ONE place,
// so the felt weight of a hit is retuned here and nowhere else. Each caller still decides for ITSELF
// what counts as heavy — that test is per-attack and is deliberately not shared.
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

/// ── EAT SOMETHING ── the bag's side of `item.Use`. The kind names an EFFECT and this is where the
/// effect happens, so item.zig can stay a vocabulary that knows nothing about HP.
///
/// The charge goes only if one actually came out (`Bag.take` reports it) — the same "ask by doing"
/// shape as `Flasks.take` and `Vitals.heal`, and the reason a dry row cannot be eaten twice.
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

/// ── A BLOW ARRIVES ── apply it and feel it, in ONE place, because what a blow FEELS like now
/// depends on what became of it and there are four callers who must not each decide that for
/// themselves. Returns the outcome so a caller with its own impact voice (the arrow) can pick the
/// right one.
///
/// The i-framed case is why this returns anything at all: every caller used to fire the hurt beat
/// the moment a foe REPORTED a blow, so rolling cleanly through a slam still grunted, shook the
/// camera and kicked the pad — the one thing a dodge must never do.
fn heroTakes(g: *Game, b: foemod.Blow, heavy: bool, voice: bool) combat.HitOutcome {
    const out = g.hero.takeHit(b.hit, mathx.dirXZ(g.hero.pos, b.from));
    switch (out) {
        .ignored => {}, // rolled through it, or he was already gone
        .taken => heroHurtBeat(g, heavy, voice),
        .blocked => heroBlockBeat(g, b.hit),
        .guardBroken => {
            // The break is a stagger and gets the stagger's weight — plus the boards going, which is
            // the sound that says WHY you are suddenly wide open. `.stagger` itself still plays off
            // the stun's rising edge in the loop, so this is not doubled.
            g.rumble.play(rumblemod.guard_break);
            g.rig.addShake(SHAKE_GUARD_BREAK);
            sfx.play(.guard_break);
        },
    }
    return out;
}

/// ── HELD ── the felt weight of a caught blow. It has to land HARD (owner's law: reactions are
/// huge) and read as a WIN: a woody crack instead of a grunt, a real shake, and a shorter pad kick
/// than being hit. Scaled by what was caught, so a kobold's teeth and an ogre's club do not feel
/// the same through the shield — which is the only warning you get that the next one breaks you.
fn heroBlockBeat(g: *Game, h: combat.Hit) void {
    const w = mathx.clampF(h.dmg / BLOW_HEAVIEST, BLOCK_FELT_MIN, 1.0);
    g.rumble.play(if (w >= BLOCK_FELT_HEAVY) rumblemod.guard_block_heavy else rumblemod.guard_block);
    g.rig.addShake(SHAKE_BLOCK * w);
    sfx.play(.guard_block);
}

// ── THE FOE ROLL-UPS ── the three groups, summed in ONE place each. Every one of these was written
// out as `g.warren.X() + g.line.X() + g.grief.X()` at each site — `totalHits` three separate times —
// which is the parallel-list-in-lockstep failure the FoeRef switch was already fixed for: a fourth
// foe means editing every copy, and a copy you miss silently stops counting (the debug read-out once
// ignored every blow landed on anything but a toad, for exactly this reason).
fn allHits(g: *const Game) u32 {
    return g.warren.totalHits() + g.line.totalHits() + g.grief.totalHits() + g.band.totalHits();
}
fn allAlive(g: *const Game) u32 {
    return g.warren.aliveCount() + g.line.aliveCount() + g.grief.aliveCount() + g.band.aliveCount();
}
fn anyFoeDied(g: *const Game) bool {
    return g.warren.anyDied() or g.line.anyDied() or g.grief.anyDied() or g.band.anyDied();
}
fn allRunes(g: *const Game) u32 {
    // The band's payout is PER ROLE (a priest is worth the most), so its own `runesDropped` does the
    // summing rather than taking a flat per-group figure like the other three.
    return g.warren.runesDropped() + g.line.runesDropped() + g.grief.runesDropped() + g.band.runesDropped();
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
    // the prop grid). The world holds THOUSANDS of solids; scanning all of them per actor, twice a
    // frame, was the other thing that would not have survived the expansion. (No count here on
    // purpose — the number said "~700" when the map had grown past 1,800, and the live figure is on
    // the debug Stats line where it cannot go stale.)
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

    // THE WARBAND yields to everything, itself included — a pack that walked through each other would
    // stack three kobolds on one spot, and a knot of them is the whole point of the encounter. Bumping
    // each other apart is also what keeps the priest from being safely buried inside the front line.
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
// THE THREE KOBOLD ROLES ALL LIVE IN ONE ARRAY (`kobold.Warband` — the priest has to be able to see
// its friends), so unlike the other groups a FoeRef's `kind` does not pick the array: all three index
// `g.band.band`. `kobold.roleOf` is what says a kind is a kobold at all.
fn bandIdx(r: FoeRef) ?usize {
    return if (koboldmod.roleOf(r.kind) != null) r.idx else null;
}
fn foePos(g: *const Game, r: FoeRef) rl.Vector3 {
    if (bandIdx(r)) |i| return g.band.band[i].pos;
    return switch (r.kind) {
        .toad => g.warren.frogs[r.idx].pos,
        .archer => g.line.archers[r.idx].pos,
        .ogre => g.grief.ogres[r.idx].pos,
        .berserker, .priest, .slinger => unreachable, // handled above
    };
}
fn foeLockPoint(g: *const Game, r: FoeRef) rl.Vector3 {
    if (bandIdx(r)) |i| return g.band.band[i].lockPoint();
    return switch (r.kind) {
        .toad => g.warren.frogs[r.idx].lockPoint(),
        .archer => g.line.archers[r.idx].lockPoint(),
        .ogre => g.grief.ogres[r.idx].lockPoint(),
        .berserker, .priest, .slinger => unreachable,
    };
}
// A live, non-dissipating foe (both a fresh acquire and a held lock require this).
fn foeLockable(g: *const Game, r: FoeRef) bool {
    if (bandIdx(r)) |i| return g.band.band[i].alive() and !g.band.band[i].dying();
    return switch (r.kind) {
        .toad => g.warren.frogs[r.idx].alive() and !g.warren.frogs[r.idx].dying(),
        .archer => g.line.archers[r.idx].alive() and !g.line.archers[r.idx].dying(),
        .ogre => g.grief.ogres[r.idx].alive() and !g.grief.ogres[r.idx].dying(),
        .berserker, .priest, .slinger => unreachable,
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
    // The band's members carry DIFFERENT kinds in one array, so each contributes under its own role's
    // kind rather than the group's — `considerLock`'s single-kind signature cannot say that.
    for (g.band.live(), 0..) |*k, i| {
        if (!k.alive() or k.dying() or mathx.distXZ(g.hero.pos, k.pos) > MAX_LOCK_R) continue;
        const r = FoeRef{ .kind = kindOfRole(k.role), .idx = i };
        const sx = lockScreenX(g, r) orelse continue;
        const score = @abs(sx - cx);
        if (score < bestScore) {
            bestScore = score;
            best = r;
        }
    }
    return best;
}

/// A kobold role → the map foe kind that posts it. The inverse of `kobold.roleOf`, and it lives here
/// because a `FoeRef` is game.zig's idea, not the creature's.
fn kindOfRole(r: koboldmod.Role) FoeKind {
    return @enumFromInt(@intFromEnum(FoeKind.berserker) + @intFromEnum(r));
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
    // …and the band, per member's own role kind (see acquireLock).
    for (g.band.live(), 0..) |*k, i| {
        const r = FoeRef{ .kind = kindOfRole(k.role), .idx = i };
        if ((koboldmod.roleOf(cur.kind) != null and cur.idx == i) or !k.alive() or k.dying()) continue;
        if (mathx.distXZ(g.hero.pos, k.pos) > MAX_LOCK_R) continue;
        const sx = lockScreenX(g, r) orelse continue;
        const gap = (sx - curX) * dir;
        if (gap > 5.0 and gap < bestGap) {
            bestGap = gap;
            best = r;
        }
    }
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
    g.band.reset(&g.map);
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

