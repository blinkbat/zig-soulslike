const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const gfx = @import("gfx.zig");
const envmod = @import("env.zig");
const heromod = @import("hero.zig");
const cameramod = @import("camera.zig");
const hud_ = @import("hud.zig");
const menumod = @import("menu.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

const SCREEN_W = 1280;
const SCREEN_H = 800;

const WALK_SPEED = 1.7; // world units/sec — keyboard walk / gentle left-stick tilt
const RUN_SPEED = 3.0; // full left-stick tilt (Elden Ring analog: light=walk, full=run)
const SPRINT_SPEED = 4.6; // hold Circle/B (or Shift): dash/sprint
const TURN_RATE = 12.0; // rad/sec the hero yaws toward its heading (souls turn briskly)
const STICK_DEADZONE = 0.16; // left-stick move deadzone
const LOOK_DEADZONE = 0.12; // right-stick look deadzone
const PAD_LOOK_RATE = 2.7; // rad/sec camera orbit at full right-stick deflection

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
            .rig = cameramod.newCamRig(hero.shoulderPoint(), hero.facing),
        };
    }
};

// ── input → intent ─────────────────────────────────────────────────────────────────
// fx = camera-right axis, fz = camera-forward axis (pre-normalization); speed = resolved
// ground speed this frame (0 = idle). Keyboard is digital (walk, Shift = sprint); the left
// stick is analog (tilt → speed, light = walk / full = run), Elden-Ring style.
const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

// Rescale a raw stick axis past its deadzone into a clean 0..±1.
fn axisDZ(v: f32, dz: f32) f32 {
    const a = @abs(v);
    if (a < dz) return 0;
    return std.math.sign(v) * (a - dz) / (1.0 - dz);
}

fn gatherMove() Move {
    var sprint = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    // Gamepad first (analog left stick; Circle/B held = dash/sprint). A pushed stick wins
    // over the keyboard so its analog speed is honoured.
    if (rl.isGamepadAvailable(0)) {
        if (rl.isGamepadButtonDown(0, .right_face_right)) sprint = true;
        const gx = axisDZ(rl.getGamepadAxisMovement(0, .left_x), STICK_DEADZONE);
        const gz = -axisDZ(rl.getGamepadAxisMovement(0, .left_y), STICK_DEADZONE); // stick up = forward
        const gmag = mathx.minF(@sqrt(gx * gx + gz * gz), 1.0);
        if (gmag > 0.001) {
            return .{ .fx = gx, .fz = gz, .speed = if (sprint) SPRINT_SPEED else gmag * RUN_SPEED };
        }
    }
    // Keyboard (digital walk).
    var kx: f32 = 0;
    var kz: f32 = 0;
    if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) kz += 1;
    if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) kz -= 1;
    if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) kx += 1;
    if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) kx -= 1;
    if (kx != 0 or kz != 0) {
        return .{ .fx = kx, .fz = kz, .speed = if (sprint) SPRINT_SPEED else WALK_SPEED };
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
        const half = envmod.HALF - 2.0;
        g.hero.pos.x = mathx.clampF(g.hero.pos.x + dir.x * moved, -half, half);
        g.hero.pos.z = mathx.clampF(g.hero.pos.z + dir.z * moved, -half, half);
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
// Casters = the hero + the stone props (NOT the ground, which only receives). Drawn by
// BOTH the sun depth pass and the lit pass through this one function so transforms match.
fn drawCasters(g: *Game) void {
    g.env.drawProps();
    g.hero.draw();
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
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
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
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
            "L-stick move   R-stick look   B: hold sprint / tap roll   R3 recenter   Start menu"
        else
            "WASD move   hold RMB to look   Shift sprint   Space roll   Esc menu";
        hud_.text(help, 16, rl.getScreenHeight() - 30, 16, rgba(188, 178, 158, 255));
    }

    const label: [:0]const u8 = if (g.hero.rolling) "rolling" else gaitLabel(g.hero.moving, g.hero.speed);
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{s}   {d:.1} m/s", .{ label, g.hero.speed }) catch "";
    const w = hud_.textW(s, 16);
    hud_.text(s, rl.getScreenWidth() - w - 16, 14, 16, rgba(150, 156, 164, 255));

    // Debug stats overlay (menu > Debug > Stats).
    if (g.menu.stats) {
        var sbuf: [128]u8 = undefined;
        const st = std.fmt.bufPrintZ(&sbuf, "{d} fps   {d:.1} ms   pos {d:.1},{d:.1}   yaw {d:.2}   pitch {d:.2}   time x{d:.2}", .{
            rl.getFPS(),
            rl.getFrameTime() * 1000.0,
            g.hero.pos.x,
            g.hero.pos.z,
            g.rig.yaw,
            g.rig.pitch,
            g.menu.timeScale,
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
            bWasDown = false;
            bHeldT = 0;
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
            bHeldT += dt;
        } else {
            if (bWasDown and bHeldT < 0.22) rollReq = true;
            bHeldT = 0;
        }
        bWasDown = bDown;

        const mv = gatherMove();
        if (rollReq and !g.hero.rolling) g.hero.startRoll(rollDir(g, mv));

        if (g.hero.rolling) {
            g.hero.updateRoll(dt, envmod.HALF - 2.0); // committed — ignores move input
        } else {
            moveHero(g, dt, mv);
        }
        g.rig.follow(g.hero.shoulderPoint());

        drawScene(g);
        hud(g);
        rl.endDrawing();
    }
}

// ── headless capture ───────────────────────────────────────────────────────────────
// Walk the hero along a FIXED world direction (−Z, into the ruins) and shoot it from
// several true camera angles + stride phases into shots/ (window hidden). Movement is
// world-fixed here (not camera-relative like the live loop) so we can orbit the camera to
// a real side/front profile and actually judge the gait. Mirrors the siblings' --shot.
fn stepWorld(g: *Game, dt: f32, speed: f32) void {
    const moved = speed * dt;
    const half = envmod.HALF - 2.0;
    g.hero.pos.z = mathx.clampF(g.hero.pos.z - moved, -half, half); // travel −Z
    g.hero.facing = std.math.pi; // face −Z (no turning)
    g.hero.update(dt, moved, speed);
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
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
        drawScene(g);
        hud(g);
        rl.endDrawing();
        rl.takeScreenshot(st.name);
    }

    // Dodge roll (side profile): capture the crouch → somersault → recover of a −Z roll.
    g.hero.pos = mathx.ground(0, 8);
    g.rig.yaw = mathx.radians(90);
    g.rig.pitch = 0.10;
    g.rig.dist = 4.4;
    g.hero.startRoll(v3(0, 0, -1));
    const rollStages = [_]struct { name: [:0]const u8, adv: i32 }{
        .{ .name = "shots/7_roll_tuck.png", .adv = 5 }, // ~u 0.14
        .{ .name = "shots/8_roll_over.png", .adv = 11 }, // ~u 0.44 (inverted)
        .{ .name = "shots/9_roll_recover.png", .adv = 11 }, // ~u 0.75
    };
    for (rollStages) |st| {
        var k: i32 = 0;
        while (k < st.adv) : (k += 1) {
            if (g.hero.rolling) g.hero.updateRoll(dt, envmod.HALF - 2.0) else stepWorld(g, dt, WALK_SPEED);
            g.rig.follow(g.hero.shoulderPoint());
        }
        drawScene(g);
        hud(g);
        rl.endDrawing();
        rl.takeScreenshot(st.name);
    }

    // Retro filters + menu verification: two filter stacks over the current framing,
    // then the menu cards over the veiled scene. Filters/menu reset when done.
    g.retro.values[gfx.RF_SCANLINES] = 0.6;
    g.retro.values[gfx.RF_CHROMA] = 0.45;
    g.retro.values[gfx.RF_CURVE] = 0.55;
    g.retro.values[gfx.RF_GRAIN] = 0.25;
    drawScene(g);
    hud(g);
    rl.endDrawing();
    rl.takeScreenshot("shots/10_retro_crt.png");

    g.retro.allOff();
    g.retro.values[gfx.RF_PIXELATE] = 0.35;
    g.retro.values[gfx.RF_DITHER] = 0.55;
    g.retro.values[gfx.RF_POSTERIZE] = 0.25;
    drawScene(g);
    hud(g);
    rl.endDrawing();
    rl.takeScreenshot("shots/11_retro_ps1.png");
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
    drawScene(g);
    hud(g);
    rl.endDrawing();
    rl.takeScreenshot("shots/14_retro_default.png");
    g.retro.allOff();
}
