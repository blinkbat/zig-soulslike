const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const gfx = @import("gfx.zig");
const envmod = @import("env.zig");
const heromod = @import("hero.zig");
const cameramod = @import("camera.zig");
const hud_ = @import("hud.zig");
const menumod = @import("menu.zig");
const frogmod = @import("frog.zig");
const collision = @import("collision.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

const SCREEN_W = 1280;
const SCREEN_H = 800;

// Locomotion speeds live with the hero rig (single source of truth) — the gait blends are
// tuned to these same values, so keep them from drifting by referencing them here.
const WALK_SPEED = heromod.WALK_SPEED; // keyboard walk / gentle left-stick tilt
const RUN_SPEED = heromod.RUN_SPEED; // full left-stick tilt once RUN_HOLD unlocks the run (light tilt stays walk)
const SPRINT_SPEED = heromod.SPRINT_SPEED; // hold Circle/B (or Shift): dash/sprint
const TURN_RATE = 12.0; // rad/sec the hero yaws toward its heading (souls turn briskly)
const STICK_DEADZONE = 0.16; // left-stick move deadzone
const LOOK_DEADZONE = 0.12; // right-stick look deadzone
const PAD_LOOK_RATE = 2.7; // rad/sec camera orbit at full right-stick deflection
const ROLL_TAP_MAX = 0.22; // Circle/B released before this (real seconds) = a dodge tap; longer = a sprint hold
const RUN_HOLD = 0.5; // seconds of HELD movement before walk breaks into a run (sprint bypasses this)

// The hero's movement clamp: the world bounds inset by a margin so travel/rolls can't reach
// the literal edge. Single source for moveHero, the roll updates, and the --shot harness.
const PLAY_HALF = envmod.HALF - 2.0;

// Hero footprint radius for ground collision (see collision.zig).
const HERO_R = 0.36;

// Framebuffer clear tone — matches the sky shader's horizon band (displayed gfx.HAZE)
// so any sliver the sky quad misses stays invisible.
const CLEAR = rgba(80, 76, 69, 255);

const Game = struct {
    scene: gfx.Scene,
    sky: gfx.Sky,
    vignette: gfx.Vignette,
    retro: gfx.Retro,
    menu: menumod.Menu,
    env: envmod.Env,
    hero: heromod.Hero,
    warren: frogmod.Knot, // the knot of gaping toads
    rig: cameramod.CamRig,

    fn init() Game {
        const scene = gfx.Scene.init();
        var hero = heromod.Hero.init(scene.shader);
        hero.pos = mathx.ground(0, 4); // start just south of the ruin avenue
        hero.facing = std.math.pi; // facing -Z, into the columns
        hero.pose();
        return .{
            .scene = scene,
            .sky = gfx.Sky.init(),
            .vignette = gfx.Vignette.init(),
            .retro = gfx.Retro.init(rl.getScreenWidth(), rl.getScreenHeight()),
            .menu = .{}, // opens on the main screen: Continue / Debug / Quit
            .env = envmod.Env.init(scene.shader),
            .hero = hero,
            .warren = frogmod.Knot.init(scene.shader),
            .rig = cameramod.newCamRig(hero.shoulderPoint(), hero.facing),
        };
    }
};

// ── input → intent ─────────────────────────────────────────────────────────────────
// fx = camera-right axis, fz = camera-forward axis (pre-normalization); speed = resolved
// ground speed this frame (0 = idle). Keyboard is digital; the left stick is analog
// (tilt → speed), Elden-Ring style. Movement starts at a WALK and breaks into a RUN only
// once it has been HELD for RUN_HOLD (`runUnlocked`); holding sprint bypasses the gate.
const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

// Rescale a raw stick axis past its deadzone into a clean 0..±1.
fn axisDZ(v: f32, dz: f32) f32 {
    const a = @abs(v);
    if (a < dz) return 0;
    return std.math.sign(v) * (a - dz) / (1.0 - dz);
}

fn gatherMove(runUnlocked: bool) Move {
    var sprint = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    // Gamepad first (analog left stick; Circle/B held = dash/sprint). A pushed stick wins
    // over the keyboard so its analog speed is honoured.
    if (rl.isGamepadAvailable(0)) {
        if (rl.isGamepadButtonDown(0, .right_face_right)) sprint = true;
        const gx = axisDZ(rl.getGamepadAxisMovement(0, .left_x), STICK_DEADZONE);
        const gz = -axisDZ(rl.getGamepadAxisMovement(0, .left_y), STICK_DEADZONE); // stick up = forward
        const gmag = mathx.minF(@sqrt(gx * gx + gz * gz), 1.0);
        if (gmag > 0.001) {
            var sp = if (sprint) SPRINT_SPEED else gmag * RUN_SPEED;
            if (!sprint and !runUnlocked) sp = mathx.minF(sp, WALK_SPEED); // full tilt still walks until held
            return .{ .fx = gx, .fz = gz, .speed = sp };
        }
    }
    // Keyboard (digital: walk, then run once held).
    var kx: f32 = 0;
    var kz: f32 = 0;
    if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) kz += 1;
    if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) kz -= 1;
    if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) kx += 1;
    if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) kx -= 1;
    if (kx != 0 or kz != 0) {
        const sp: f32 = if (sprint) SPRINT_SPEED else if (runUnlocked) RUN_SPEED else WALK_SPEED;
        return .{ .fx = kx, .fz = kz, .speed = sp };
    }
    return .{};
}

// Move + steer the hero from a camera-relative Move, advance its walk anim, and pose the
// skeleton. Camera basis is read BEFORE this (so movement follows the current view).
fn moveHero(g: *Game, dt: f32, mv: Move) void {
    const fwd = g.rig.forwardXZ();
    const right = g.rig.rightXZ();
    var dir = v3(fwd.x * mv.fz + right.x * mv.fx, 0, fwd.z * mv.fz + right.z * mv.fx);
    const l = mathx.lenXZ(dir);
    var moved: f32 = 0;
    var speed: f32 = 0;
    if (l > 0.001 and mv.speed > 0.001) {
        dir = v3(dir.x / l, 0, dir.z / l);
        speed = mv.speed;
        moved = speed * dt;
        g.hero.pos.x = mathx.clampF(g.hero.pos.x + dir.x * moved, -PLAY_HALF, PLAY_HALF);
        g.hero.pos.z = mathx.clampF(g.hero.pos.z + dir.z * moved, -PLAY_HALF, PLAY_HALF);
        const targetYaw = std.math.atan2(dir.x, dir.z);
        g.hero.facing = mathx.approachAngle(g.hero.facing, targetYaw, TURN_RATE * dt);
    }
    g.hero.update(dt, moved, speed);
    g.hero.pose();
}

// The world direction to roll: the current camera-relative move intent if any, else the
// hero's current facing (a forward roll).
fn rollDir(g: *Game, mv: Move) rl.Vector3 {
    const fwd = g.rig.forwardXZ();
    const right = g.rig.rightXZ();
    const d = v3(fwd.x * mv.fz + right.x * mv.fx, 0, fwd.z * mv.fz + right.z * mv.fx);
    if (mathx.lenXZ(d) > 0.01) return d;
    return v3(mathx.sinf(g.hero.facing), 0, mathx.cosf(g.hero.facing));
}

// ── render ───────────────────────────────────────────────────────────────────────
// Casters = the hero + the stone props (NOT the ground, which only receives; NOT the
// flora, which is a non-caster drawn only in the lit pass and swayed by wind). Drawn by
// BOTH the sun depth pass and the lit pass through this one function so transforms match.
// Deliberately NO distance culling for the depth pass: with the low sun, a tall caster
// far OUTSIDE the shadow ortho box still throws its shadow INTO it (reach ~ 1.5x height
// at ~33 deg), so cull-by-distance-from-focus would clip real shadows. The ~300 extra
// depth draws are immaterial.
fn drawCasters(g: *Game) void {
    g.env.drawProps();
    g.hero.draw();
    g.warren.draw();
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
    g.warren.setShader(sh);
}

fn drawScene(g: *Game) void {
    // Sun depth pass into the shadow map (before beginDrawing). Ortho box tracks the hero.
    g.scene.beginShadowPass(g.hero.pos);
    setCasterShaders(g, g.scene.depthShader);
    drawCasters(g);
    setCasterShaders(g, g.scene.shader);
    g.scene.endShadowPass();

    rl.beginDrawing();
    // With any retro filter live, the sky + 3D render into the capture RT and blit
    // back through the filter shader; the vignette/HUD/menu stay crisp on top.
    const filtered = g.retro.begin();
    rl.clearBackground(CLEAR);
    g.sky.draw(g.rig.cam);

    rl.beginMode3D(g.rig.cam);
    g.scene.bind(g.rig.cam.position);
    g.scene.setGround(true);
    g.env.drawGround();
    g.scene.setGround(false);
    if (g.menu.wireframe) rl.gl.rlEnableWireMode();
    drawCasters(g);
    // Flora last: non-casting, and swayed by the scene shader's wind term (props/hero rigid).
    g.scene.setWind(true);
    g.env.drawFlora();
    g.scene.setWind(false);
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
    // Debug: the blade hit capsule (menu > Debug > Hitboxes) — red while ACTIVE, dim
    // through the rest of the swing. Drawn with the default shader, unlit on purpose.
    if (g.menu.hitboxes and g.hero.attacking) {
        const col = if (g.hero.hitActive()) rl.Color.red else mathx.withAlpha(rl.Color.red, 90);
        rl.drawCapsuleWires(g.hero.bladeA, g.hero.bladeB, heromod.BLADE_R, 6, 3, col);
    }
    // Frog hurt spheres (menu > Debug > Hitboxes): dim normally, flaring on a tracked hit.
    if (g.menu.hitboxes) {
        for (&g.warren.frogs) |*f| {
            const col = if (f.flash > 0) rl.Color.orange else mathx.withAlpha(rl.Color.yellow, 80);
            rl.drawSphereWires(f.centerWorld(), f.hurtRadius(), 6, 8, col);
        }
    }
    rl.endMode3D();

    if (filtered) g.retro.end();
    g.vignette.draw();
}

fn hud(g: *Game) void {
    // ASCII only — the Exo atlas is loaded with the default (ASCII) glyph set, so a "·"
    // or "—" would render as a tofu "?".
    hud_.text("zig-soulslike", 16, 12, 24, rgba(232, 222, 198, 255));
    hud_.text("locomotion demo - anatomical rig, walk / run / sprint gait", 16, 40, 16, rgba(164, 154, 134, 255));
    if (!g.menu.isOpen()) {
        const help: [:0]const u8 = if (rl.isGamepadAvailable(0))
            "L-stick move (hold to run)   R-stick look   R1 slash   R2 heavy   B: sprint / tap roll   R3 recenter   Start menu"
        else
            "WASD move (hold to run)   mouse look   LMB slash   Shift+LMB heavy   Shift sprint   Space roll   Esc menu";
        hud_.text(help, 16, rl.getScreenHeight() - 30, 16, rgba(188, 178, 158, 255));
    }

    const label: [:0]const u8 = if (g.hero.rolling)
        "rolling"
    else if (g.hero.attacking)
        (if (g.hero.atkHeavy) "striking" else "slashing")
    else
        gaitLabel(g.hero.moving, g.hero.speed);
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{s}   {d:.1} m/s", .{ label, g.hero.speed }) catch "";
    const w = hud_.textW(s, 16);
    hud_.text(s, rl.getScreenWidth() - w - 16, 14, 16, rgba(150, 156, 164, 255));

    // Debug stats overlay (menu > Debug > Stats).
    if (g.menu.stats) {
        var sbuf: [160]u8 = undefined;
        const st = std.fmt.bufPrintZ(&sbuf, "{d} fps   {d:.1} ms   pos {d:.1},{d:.1}   yaw {d:.2}   pitch {d:.2}   time x{d:.2}   frog hits {d}", .{
            rl.getFPS(),
            rl.getFrameTime() * 1000.0,
            g.hero.pos.x,
            g.hero.pos.z,
            g.rig.yaw,
            g.rig.pitch,
            g.menu.timeScale,
            g.warren.totalHits(),
        }) catch "";
        hud_.text(st, 16, 64, 15, rgba(170, 190, 150, 255));
    }
}

fn gaitLabel(moving: f32, speed: f32) [:0]const u8 {
    if (moving < 0.5) return "idle";
    if (speed >= SPRINT_SPEED - 0.3) return "sprinting";
    if (speed >= RUN_SPEED - 0.3) return "running";
    return "walking";
}

pub fn run(shot: bool) void {
    rl.setConfigFlags(.{ .msaa_4x_hint = true, .window_hidden = shot });
    rl.initWindow(SCREEN_W, SCREEN_H, "zig-soulslike");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    hud_.init();
    defer hud_.deinit();

    const alloc = std.heap.c_allocator;
    const g = alloc.create(Game) catch return;
    defer alloc.destroy(g);
    g.* = Game.init();

    // Tight near/far so the perspective depth buffer has real precision — the default
    // 0.01..1000 (100000:1) makes the hero's overlapping boxes z-fight and flicker/invert
    // as the camera moves. BeginMode3D reads these cull distances; the shadow pass
    // saves/restores them around its own ortho slab, so setting them once here sticks.
    // Set BEFORE the --shot branch so headless captures get the same depth precision.
    rl.gl.rlSetClipPlanes(0.2, 320.0);

    if (shot) {
        runShots(g);
        return;
    }

    // The mouse is HIDDEN while over the window (GLFW_CURSOR_HIDDEN — invisible but NOT
    // locked) and moves the camera; push it past the window edge and it reappears as a
    // normal cursor usable on other monitors / windows. No capture, ever. Esc quits.
    rl.hideCursor();
    var wasInside = false;
    var bWasDown = false; // gamepad Circle/B: a TAP rolls, a HOLD sprints
    var bHeldT: f32 = 0;
    var moveHeldT: f32 = 0; // continuous held-movement time; ≥ RUN_HOLD unlocks the run
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime() * g.menu.timeScale;

        // Esc backs the menu out one level (opens it when closed); pad Start toggles.
        // Quit lives in the menu now.
        if (rl.isKeyPressed(.escape)) g.menu.onEscape();
        if (rl.isGamepadAvailable(0) and rl.isGamepadButtonPressed(0, .middle_right)) g.menu.onStartButton();

        if (g.menu.isOpen()) {
            // The world holds while the menu is up: no camera/move input, but the hero
            // keeps breathing (idle update with zero travel) so the scene stays alive.
            if (g.menu.update(&g.retro, rl.getFrameTime()) == .quit) break;
            // Poison the pad-B tap window while the menu is up: B both BACKS OUT of the
            // menu and dodge-rolls, so a zeroed window would turn the release of the very
            // B press that closed the menu into an instant roll. Poisoned, that release
            // reads as a hold (no tap); a fresh press after release taps normally.
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            moveHeldT = 0;
            wasInside = false; // swallow the mouse delta accumulated while in the menu
            g.hero.update(rl.getFrameTime(), 0, 0);
            g.hero.pose();
            g.rig.follow(g.hero.shoulderPoint());
            drawScene(g);
            hud(g);
            g.menu.draw(&g.retro);
            rl.endDrawing();
            continue;
        }

        // Camera look: mouse while its cursor is over the window + right stick; wheel/D-pad
        // zoom; R3 recenters behind the hero.
        const inside = rl.isWindowFocused() and rl.isCursorOnScreen();
        if (inside) {
            const md = rl.getMouseDelta();
            if (wasInside) g.rig.rotate(md.x, md.y); // skip the position jump on re-entry
        }
        wasInside = inside;
        var wheel = rl.getMouseWheelMove();
        if (rl.isGamepadAvailable(0)) {
            const rx = axisDZ(rl.getGamepadAxisMovement(0, .right_x), LOOK_DEADZONE);
            const ry = axisDZ(rl.getGamepadAxisMovement(0, .right_y), LOOK_DEADZONE);
            g.rig.orbit(-rx * PAD_LOOK_RATE * dt, ry * PAD_LOOK_RATE * dt);
            if (rl.isGamepadButtonPressed(0, .right_thumb)) g.rig.recenter(g.hero.facing);
            if (rl.isGamepadButtonPressed(0, .left_face_up)) wheel += 1; // D-pad up = zoom in
            if (rl.isGamepadButtonPressed(0, .left_face_down)) wheel -= 1; // D-pad down = zoom out
        }
        if (wheel != 0) g.rig.zoom(wheel);

        // Dodge roll: Space, or a short TAP of Circle/B (holding B sprints instead).
        var rollReq = rl.isKeyPressed(.space);
        const bDown = rl.isGamepadAvailable(0) and rl.isGamepadButtonDown(0, .right_face_right);
        if (bDown) {
            bHeldT += rl.getFrameTime(); // REAL time: tap-vs-hold is a wall-clock decision, unaffected by debug time-scale
        } else {
            if (bWasDown and bHeldT < ROLL_TAP_MAX) rollReq = true;
            bHeldT = 0;
        }
        bWasDown = bDown;

        // Sword attacks (ER layout): pad R1/RB = light slash, R2/RT = heavy; keyboard
        // LMB = light, Shift+LMB = heavy (ER's kb default). Actions are committed (no
        // mid-swing cancels), but input BUFFERS like Elden Ring: pressed mid-action, a
        // request queues in the hero's one slot and fires at the earliest exit.
        var lightReq = false;
        var heavyReq = false;
        if (rl.isMouseButtonPressed(.left)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) heavyReq = true else lightReq = true;
        }
        if (rl.isGamepadAvailable(0)) {
            if (rl.isGamepadButtonPressed(0, .right_trigger_1)) lightReq = true;
            if (rl.isGamepadButtonPressed(0, .right_trigger_2)) heavyReq = true;
        }

        const mv = gatherMove(moveHeldT >= RUN_HOLD);
        // REAL time like bHeldT (a wall-clock feel decision). Keeps accumulating through a
        // roll, so holding the stick rolls you back out into the run you were in.
        moveHeldT = if (mv.speed > 0.001) moveHeldT + rl.getFrameTime() else 0;
        // A roll press claims the whole frame (rolls win a same-frame conflict), and a
        // queued roll re-steers every frame so it leaves in the direction HELD when it
        // fires, not the one pressed — both Elden Ring behaviors.
        if (rollReq) {
            g.hero.requestRoll(rollDir(g, mv));
        } else if (heavyReq) {
            g.hero.requestAttack(.heavy);
        } else if (lightReq) {
            g.hero.requestAttack(.light);
        }
        g.hero.steerQueuedRoll(rollDir(g, mv));

        if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.attacking) {
            g.hero.updateAttack(dt, PLAY_HALF); // committed — a short step into the cut
        } else {
            moveHero(g, dt, mv);
        }
        // The knot hunts the hero; the hero's swept blade is tested against each toad (hits
        // counted only — no damage/flinch yet). Then resolve every footprint collision, then
        // aim the camera at the SETTLED hero position.
        g.warren.update(dt, g.hero.pos, PLAY_HALF, heroBlade(g));
        collideActors(g);
        g.rig.follow(g.hero.shoulderPoint());

        drawScene(g);
        hud(g);
        rl.endDrawing();
    }
}

// The hero's blade this frame as plain data for the toads' hit test (endpoints guard→tip,
// with last frame's for the swept test; active only inside the strike window).
fn heroBlade(g: *const Game) frogmod.Blade {
    return .{
        .active = g.hero.hitActive(),
        .r = heromod.BLADE_R,
        .a = g.hero.bladeA,
        .b = g.hero.bladeB,
        .a0 = g.hero.bladeA0,
        .b0 = g.hero.bladeB0,
    };
}

// Resolve footprint collisions on the XZ plane (see collision.zig). The hero keeps priority
// — pushed out of world solids, then out of any GROUNDED toad; the toads then yield, each
// pushed out of the world, the hero, and its grounded neighbours. Airborne toads (mid-hop)
// are skipped so a leap arcs over you cleanly instead of shoving you around.
fn collideActors(g: *Game) void {
    const solids = g.env.solids();
    var hp = collision.resolve(g.hero.pos, HERO_R, solids);
    for (&g.warren.frogs) |*f| {
        if (!f.airborne()) hp = collision.pushOutCircle(hp, HERO_R, f.pos, f.bodyR());
    }
    g.hero.pos.x = mathx.clampF(hp.x, -PLAY_HALF, PLAY_HALF);
    g.hero.pos.z = mathx.clampF(hp.z, -PLAY_HALF, PLAY_HALF);

    for (&g.warren.frogs, 0..) |*f, i| {
        if (f.airborne()) continue;
        var fp = collision.resolve(f.pos, f.bodyR(), solids);
        fp = collision.pushOutCircle(fp, f.bodyR(), g.hero.pos, HERO_R);
        for (&g.warren.frogs, 0..) |*o, j| {
            if (i == j or o.airborne()) continue;
            fp = collision.pushOutCircle(fp, f.bodyR(), o.pos, o.bodyR());
        }
        f.pos.x = mathx.clampF(fp.x, -PLAY_HALF, PLAY_HALF);
        f.pos.z = mathx.clampF(fp.z, -PLAY_HALF, PLAY_HALF);
    }
}

// ── headless capture ───────────────────────────────────────────────────────────────
// Walk the hero along a FIXED world direction (−Z, into the ruins) and shoot it from
// several true camera angles + stride phases into shots/ (window hidden). Movement is
// world-fixed here (not camera-relative like the live loop) so we can orbit the camera to
// a real side/front profile and actually judge the gait. Mirrors the siblings' --shot.
fn stepWorld(g: *Game, dt: f32, speed: f32) void {
    const moved = speed * dt;
    g.hero.pos.z = mathx.clampF(g.hero.pos.z - moved, -PLAY_HALF, PLAY_HALF); // travel −Z
    g.hero.facing = std.math.pi; // face −Z (no turning)
    g.hero.update(dt, moved, speed);
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
}

// Render the current world + HUD and write one screenshot. The shared capture idiom for
// every non-menu shot (menu shots interpose g.menu.draw before endDrawing, so they stay
// inline below).
fn shoot(g: *Game, name: [:0]const u8) void {
    drawScene(g);
    hud(g);
    rl.endDrawing();
    rl.takeScreenshot(name);
}

// Advance an in-progress attack up to `frames` frames (stopping early when it ends),
// keeping the camera following — the attack-shot counterpart of the roll-stage loop.
fn advanceAttack(g: *Game, dt: f32, frames: i32) void {
    var k: i32 = 0;
    while (k < frames and g.hero.attacking) : (k += 1) {
        g.hero.updateAttack(dt, PLAY_HALF);
        g.rig.follow(g.hero.shoulderPoint());
    }
}

// Advance one toad `frames` steps against a sensed hero position `hero` (kept FAR so its
// AI holds the state we forced rather than auto-deciding; placed along the action's heading
// so the coil/gape re-aim doesn't fight the framing) and no blade — for the frog shots.
fn stepFrog(f: *frogmod.Frog, frames: i32, hero: rl.Vector3) void {
    const dt: f32 = 1.0 / 60.0;
    var k: i32 = 0;
    while (k < frames) : (k += 1) f.update(dt, hero, PLAY_HALF, .{});
}

// Frame a toad and shoot it.
fn shootFrog(g: *Game, f: *frogmod.Frog, name: [:0]const u8, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.follow(f.centerWorld());
    shoot(g, name);
}

fn runShots(g: *Game) void {
    std.fs.cwd().makePath("shots") catch {};
    const dt: f32 = 1.0 / 60.0;
    // Shots 1-9 judge geometry/animation — run them CLEAN of the default filter stack;
    // the filter shots below set their own explicit stacks.
    g.retro.allOff();

    g.hero.pos = mathx.ground(0, 26); // long runway of −Z travel ahead
    var i: i32 = 0;
    while (i < 40) : (i += 1) stepWorld(g, dt, WALK_SPEED); // warm up: moving→1, phase settles

    // (name, yaw°, pitch, dist, frames before the shot, speed). yaw 90 = profile (best for
    // gait), 0 = front, 180 = back, 45 = three-quarter. Speed selects walk/run/sprint pose.
    const stages = [_]struct { name: [:0]const u8, yaw: f32, pitch: f32, dist: f32, adv: i32, speed: f32 }{
        .{ .name = "shots/1_walk_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .adv = 0, .speed = WALK_SPEED },
        .{ .name = "shots/2_walk_front.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .adv = 22, .speed = WALK_SPEED },
        .{ .name = "shots/3_run_side.png", .yaw = 90, .pitch = 0.06, .dist = 4.9, .adv = 24, .speed = RUN_SPEED },
        .{ .name = "shots/4_run_threequarter.png", .yaw = 45, .pitch = 0.16, .dist = 4.9, .adv = 12, .speed = RUN_SPEED },
        .{ .name = "shots/5_sprint_side.png", .yaw = 90, .pitch = 0.04, .dist = 5.4, .adv = 16, .speed = SPRINT_SPEED },
        .{ .name = "shots/6_sprint_back.png", .yaw = 180, .pitch = 0.22, .dist = 5.2, .adv = 14, .speed = SPRINT_SPEED },
    };
    for (stages) |st| {
        g.rig.yaw = mathx.radians(st.yaw);
        g.rig.pitch = st.pitch;
        g.rig.dist = st.dist;
        var k: i32 = 0;
        while (k < st.adv) : (k += 1) stepWorld(g, dt, st.speed);
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, st.name);
    }

    // Dodge roll (side profile): capture the crouch → somersault → recover of a −Z roll.
    g.hero.pos = mathx.ground(0, 8);
    g.rig.yaw = mathx.radians(90);
    g.rig.pitch = 0.10;
    g.rig.dist = 4.4;
    g.hero.startRoll(v3(0, 0, -1));
    const rollStages = [_]struct { name: [:0]const u8, adv: i32 }{
        .{ .name = "shots/7_roll_tuck.png", .adv = 6 }, // ~u 0.14 (dive: balled + banked, spin barely begun)
        .{ .name = "shots/8_roll_over.png", .adv = 8 }, // ~u 0.33 (front-loaded tumble — inverted)
        .{ .name = "shots/9_roll_recover.png", .adv = 19 }, // ~u 0.79 (spin landed — planting, rising, off-square)
    };
    for (rollStages) |st| {
        var k: i32 = 0;
        while (k < st.adv) : (k += 1) {
            if (g.hero.rolling) g.hero.updateRoll(dt, PLAY_HALF) else stepWorld(g, dt, WALK_SPEED);
            g.rig.follow(g.hero.shoulderPoint());
        }
        shoot(g, st.name);
    }

    // Run the roll OUT first — startAttack is (rightly) ignored while rolling.
    while (g.hero.rolling) {
        g.hero.updateRoll(dt, PLAY_HALF);
        g.rig.follow(g.hero.shoulderPoint());
    }

    // Sword swings: the light slash from the SWORD side (right profile — from the left
    // the windup hides behind the torso), the heavy from the left in silhouette (an
    // overhead is sagittal) at its windup apex and buried impact, then the heavy again
    // with the hit capsule visible (menu > Debug > Hitboxes) to verify it rides the blade.
    g.hero.pos = mathx.ground(0, 4);
    g.rig.yaw = mathx.radians(270);
    g.hero.startAttack(.light);
    advanceAttack(g, dt, 10); // ~u 0.28: windup apex — fist by the ear, blade over the shoulder
    shoot(g, "shots/15a_atk_light_wind.png");
    advanceAttack(g, dt, 5); // ~u 0.42: blade mid-arc, elbow whipping through
    shoot(g, "shots/15_atk_light_strike.png");
    advanceAttack(g, dt, 7); // ~u 0.61: follow-through — blade swept across past the off hip
    shoot(g, "shots/15b_atk_light_thru.png");
    g.hero.requestAttack(.light); // buffered past the chain knot → the ALTERNATE backhand
    advanceAttack(g, dt, 22); // chain fires at ~u 0.80, then ~u 0.42 into the return swipe
    shoot(g, "shots/15c_atk_light_return.png");
    advanceAttack(g, dt, 999); // run the combo out
    g.rig.yaw = mathx.radians(90);
    g.hero.startAttack(.heavy);
    advanceAttack(g, dt, 20); // ~u 0.33: overhead windup apex (the R2 tell)
    shoot(g, "shots/16_atk_heavy_windup.png");
    advanceAttack(g, dt, 14); // ~u 0.57: buried impact, follow-through holding
    shoot(g, "shots/17_atk_heavy_impact.png");
    advanceAttack(g, dt, 999);
    g.menu.hitboxes = true;
    g.hero.startAttack(.heavy);
    advanceAttack(g, dt, 28); // ~u 0.47: inside the active window — capsule red on the blade
    shoot(g, "shots/18_atk_hitbox.png");
    advanceAttack(g, dt, 999);
    g.menu.hitboxes = false;

    // The carry: settle to a stand and frame the sword side — the held low-ready.
    var idleK: i32 = 0;
    while (idleK < 55) : (idleK += 1) stepWorld(g, dt, 0);
    g.rig.yaw = mathx.radians(300);
    g.rig.pitch = 0.14;
    g.rig.dist = 3.4;
    g.rig.follow(g.hero.shoulderPoint());
    shoot(g, "shots/19_idle_hold.png");

    // ── the gaping toad: model + each state, then a tracked hit landing on it ──────────
    {
        const dt2: f32 = 1.0 / 60.0;
        const f = &g.warren.frogs[0];
        // The hero stands a couple of metres off — a scale reference, and it keeps the toad
        // inside the sun's shadow ortho box (which tracks the hero's position).
        g.hero.pos = mathx.ground(2.0, 0.9);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z); // face the toad at origin
        g.hero.update(dt2, 0, 0);
        g.hero.pose();

        const behind = mathx.ground(0, -60); // "hero" down the hop heading (−Z): coil re-aim ≈ heading
        const front = mathx.ground(0, 60); // "hero" out front (+Z): idle/gape keep facing the camera side

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z; profiled from the side
        stepFrog(f, 8, front); // settle to idle (far → won't wake)
        shootFrog(g, f, "shots/20_frog_idle.png", 90, 0.10, 2.7);
        shootFrog(g, f, "shots/21_frog_scale.png", 35, 0.16, 4.7); // with the hero, for size read

        // A hop: coil → leap → land (side profile shows the arc + squash/stretch).
        f.startHop(mathx.ground(0, -2.2), PLAY_HALF, false);
        stepFrog(f, 6, behind); // mid coil (loaded, knees stacked)
        shootFrog(g, f, "shots/22_frog_coil.png", 90, 0.08, 3.0);
        stepFrog(f, 22, behind); // arc apex (stretched, airborne)
        shootFrog(g, f, "shots/23_frog_leap.png", 90, 0.05, 3.4);
        stepFrog(f, 22, behind); // landing splat
        shootFrog(g, f, "shots/24_frog_land.png", 90, 0.09, 3.1);

        // A lunge into its recovery (the wide-open window).
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.startHop(mathx.ground(0, -3.6), PLAY_HALF, true);
        stepFrog(f, 12, behind); // the deep telegraph coil
        shootFrog(g, f, "shots/25_frog_lunge_wind.png", 55, 0.09, 3.3);
        stepFrog(f, 67, behind); // through flight + heavy landing, ~0.3 s into recovery
        shootFrog(g, f, "shots/26_frog_recover.png", 70, 0.13, 3.2);

        // A chomp: gape (sac balloons, jaws yawn) → snap. Framed front-quarter to see the maw.
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.startChomp();
        stepFrog(f, 15, front); // near full gape
        shootFrog(g, f, "shots/27_frog_gape.png", 205, 0.05, 2.8);
        stepFrog(f, 6, front); // jaws slamming
        shootFrog(g, f, "shots/28_frog_snap.png", 205, 0.05, 2.8);

        // A TRACKED hit: the hero strikes; the swept blade capsule meets the hurt sphere and
        // the counter ticks (Debug > Hitboxes draws both; Stats shows "frog hits N"). No
        // consequence yet — detection only.
        g.menu.hitboxes = true;
        g.menu.stats = true;
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        g.hero.pos = mathx.ground(0, 0.85);
        g.hero.facing = std.math.pi; // face -Z, toward the toad at the origin
        g.hero.update(dt2, 0, 0);
        g.hero.pose();
        g.hero.startAttack(.light);
        var hk: i32 = 0;
        while (hk < 999 and g.hero.attacking) : (hk += 1) {
            g.hero.updateAttack(dt2, PLAY_HALF);
            f.update(dt2, mathx.ground(0, 60), PLAY_HALF, heroBlade(g));
            if (hk == 15) { // mid the active window
                g.rig.yaw = mathx.radians(60);
                g.rig.pitch = 0.12;
                g.rig.dist = 3.6;
                g.rig.follow(f.centerWorld());
                shoot(g, "shots/29_frog_hit.png");
            }
        }
        g.menu.hitboxes = false;
        g.menu.stats = false;
    }

    // Restore the idle-hold framing for the filter/menu verification shots below.
    g.hero.pos = mathx.ground(0, 4);
    g.hero.facing = std.math.pi;
    var restoreK: i32 = 0;
    while (restoreK < 40) : (restoreK += 1) stepWorld(g, dt, 0);
    g.rig.yaw = mathx.radians(300);
    g.rig.pitch = 0.14;
    g.rig.dist = 3.4;
    g.rig.follow(g.hero.shoulderPoint());

    // Retro filters + menu verification: two filter stacks over the current framing,
    // then the menu cards over the veiled scene. Filters/menu reset when done.
    g.retro.applyPreset(&gfx.PRESET_CRT);
    shoot(g, "shots/10_retro_crt.png");

    g.retro.applyPreset(&gfx.PRESET_PS1);
    shoot(g, "shots/11_retro_ps1.png");
    g.retro.allOff();

    g.menu.screen = .main;
    g.menu.cursor = 0;
    drawScene(g);
    hud(g);
    g.menu.draw(&g.retro);
    rl.endDrawing();
    rl.takeScreenshot("shots/12_menu_main.png");

    g.retro.values[gfx.RF_GAMEBOY] = 1.0; // show a live gauge on the retro card
    g.menu.screen = .retro;
    g.menu.cursor = gfx.RF_GAMEBOY;
    drawScene(g);
    hud(g);
    g.menu.draw(&g.retro);
    rl.endDrawing();
    rl.takeScreenshot("shots/13_menu_retro.png");
    g.menu.screen = .closed;

    // The owner-tuned default stack — the look the game actually launches with.
    g.retro.values = gfx.RETRO_DEFAULTS;
    shoot(g, "shots/14_retro_default.png");
    g.retro.allOff();
}
