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
const rumblemod = @import("rumble.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

const SCREEN_W = 1280;
const SCREEN_H = 800;

// Locomotion speeds live with the hero rig (single source of truth) — the gait blends are
// tuned to these same values, so keep them from drifting by referencing them here.
const WALK_SPEED = heromod.WALK_SPEED; // keyboard walk / gentle left-stick tilt
const RUN_SPEED = heromod.RUN_SPEED; // full left-stick tilt (light tilt scales down toward walk)
const SPRINT_SPEED = heromod.SPRINT_SPEED; // hold Circle/B (or Shift): dash/sprint
const TURN_RATE = 12.0; // rad/sec the hero yaws toward its heading (souls turn briskly)
const STICK_DEADZONE = 0.16; // left-stick move deadzone
const LOOK_DEADZONE = 0.12; // right-stick look deadzone
const PAD_LOOK_RATE = 2.7; // rad/sec camera orbit at full right-stick deflection
const ROLL_TAP_MAX = 0.22; // Circle/B released before this (real seconds) = a dodge tap; longer = a sprint hold
// NO run-unlock hold, ever (owner's rule, see AGENTS.md): the stick IS the speed — tilt
// maps straight to ground speed every frame, and keyboard movement runs immediately.

// Impact shake fed to the camera rig (trauma² response lives in camera.zig). Sized so a
// landed light reads as a tick and a lunge slam genuinely cracks the frame. NO hitstop —
// impact weight comes from shake + rumble + the huge reaction anims only.
const SHAKE_HIT_LIGHT = 0.16;
const SHAKE_HIT_HEAVY = 0.26;
const SHAKE_KILL = 0.38;
const SHAKE_HURT = 0.42;
const SHAKE_HURT_HEAVY = 0.62;
const SHAKE_DEATH = 0.85;
const RESPAWN_FADE = 0.9; // seconds of black → world after a respawn (the YOU DIED tail)

// The hero's movement clamp: the world bounds inset by a margin so travel/rolls can't reach
// the literal edge. Single source for moveHero, the roll updates, and the --shot harness.
const PLAY_HALF = envmod.HALF - 2.0;

// Hero footprint radius for ground collision (see collision.zig).
const HERO_R = 0.36;

// Collision correction is rate-limited so a large depenetration eases in over a few frames
// (a smooth slide) rather than snapping there in one (a choppy warp); set above the fastest
// actor speed so ordinary wall contact still resolves firmly (no sinking).
const COLLIDE_RATE = 11.0; // world units / sec

// Depth clip planes, set once at startup (see run()): a tight near/far so the hero's
// overlapping boxes don't z-fight. Single source — projectToScreen's near-cull (PROJECT_NEAR)
// MUST equal CLIP_NEAR, so both read this rather than repeating the literal.
const CLIP_NEAR = 0.2;
const CLIP_FAR = 320.0;

// ── lock-on (Elden Ring) ──
const MAX_LOCK_R = 17.0; // won't acquire, and drops, a foe beyond this
const LOCK_CAM_EASE = 9.0; // exponential ease rate for the lock-on camera swing (quick, snap-free)
const LOCK_PITCH = 0.24; // framing pitch while locked (the toads sit low)
const LOCK_FLICK = 0.65; // right-stick |x| past this cycles to the next target

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
    lock: ?usize = null, // ER lock-on: index into warren.frogs, or null
    rumble: rumblemod.Rumble = .{}, // controller vibration, keyed to combat beats
    deathFade: f32 = 0, // post-respawn fade-from-black seconds remaining (armed while dead)

    fn init() Game {
        const scene = gfx.Scene.init();
        var hero = heromod.Hero.init(scene.shader);
        hero.pos = mathx.ground(0, 4); // start just south of the ruin avenue
        hero.facing = std.math.pi; // facing -Z, into the columns
        hero.setSpawn(hero.pos, hero.facing); // where a death returns him
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
// ground speed this frame (0 = idle). ZERO input lag (owner's rule): the analog tilt maps
// STRAIGHT to ground speed every frame — light tilt walks, full tilt runs, NOW — and
// keyboard movement is an immediate run (hold sprint for the dash). No hold gates.
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
            const sp = if (sprint) SPRINT_SPEED else gmag * RUN_SPEED; // tilt IS the speed, this frame
            return .{ .fx = gx, .fz = gz, .speed = sp };
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

// Move + steer the hero from a camera-relative Move, advance its walk anim, and pose the
// skeleton. Camera basis is read BEFORE this (so movement follows the current view).
fn moveHero(g: *Game, dt: f32, mv: Move, faceYaw: ?f32) void {
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
    }
    // Facing: toward the LOCKED foe if locked (so the hero strafes/backpedals facing it,
    // Elden-Ring style); otherwise toward the travel direction.
    if (faceYaw) |ty| {
        g.hero.facing = mathx.approachAngle(g.hero.facing, ty, TURN_RATE * dt);
    } else if (l > 0.001 and mv.speed > 0.001) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, mathx.headingXZ(dir), TURN_RATE * dt);
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
    return mathx.headingDir(g.hero.facing);
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
    // Combat flash rides the scene shader's hitFlash uniform per actor: the hero pops red
    // on a suffered blow, each struck toad on a landed one. Inert during the depth pass
    // (the uniform lives on the scene shader, not the swapped-in depth shader).
    g.scene.setFlash(0.6 * g.hero.hurtFlash);
    g.hero.draw();
    g.scene.setFlash(0);
    g.warren.draw(&g.scene);
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
    // Toad telegraph FX (dust / charge / spit / blood / death motes) — unlit spheres,
    // over the opaque geometry. The hero's swing trail joins them (same unlit layer).
    g.warren.drawFx();
    g.hero.drawTrail();
    // Debug: the blade hit capsule (menu > Debug > Hitboxes) — red while ACTIVE, dim
    // through the rest of the swing. Drawn with the default shader, unlit on purpose.
    if (g.menu.hitboxes and g.hero.attacking) {
        const col = if (g.hero.hitActive()) rl.Color.red else mathx.withAlpha(rl.Color.red, 90);
        rl.drawCapsuleWires(g.hero.bladeA, g.hero.bladeB, heromod.BLADE_R, 6, 3, col);
    }
    // Frog hurt spheres (menu > Debug > Hitboxes): dim normally, flaring on a tracked hit.
    if (g.menu.hitboxes) {
        for (&g.warren.frogs) |*f| {
            if (!f.alive()) continue;
            const col = if (f.flash > 0) rl.Color.orange else mathx.withAlpha(rl.Color.yellow, 80);
            rl.drawSphereWires(f.centerWorld(), f.hurtRadius(), 6, 8, col);
        }
    }
    rl.endMode3D();

    if (filtered) g.retro.end();
    g.vignette.draw();
    drawHurtFlash(g); // red screen-edge pulse when the hero is hit (peripheral feedback)
    drawFrogBars(g); // floating foe HP bars, crisp over the finished frame
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
        const blackK = mathx.smoothstep(0.86, 1.0, u); // swallow the respawn snap
        if (blackK > 0.001) rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * blackK)));
    } else if (g.deathFade > 0) {
        const k = mathx.clampF(g.deathFade / RESPAWN_FADE, 0, 1);
        rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * k))); // wake at the grace
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

fn hud(g: *Game) void {
    // ASCII only — the Exo atlas is loaded with the default (ASCII) glyph set, so a "·"
    // or "—" would render as a tofu "?".
    hud_.text("zig-soulslike", 16, 12, 24, rgba(232, 222, 198, 255));
    hud_.text("locomotion demo - anatomical rig, walk / run / sprint gait", 16, 40, 16, rgba(164, 154, 134, 255));

    // Hero HP bar (ER puts the player's health top-left). The death card itself is
    // drawDeathOverlay's — no mini YOU DIED here.
    healthBar(16, 66, 300, 16, g.hero.vit.hpFrac(), rgba(24, 20, 16, 220));
    if (!g.menu.isOpen()) {
        const help: [:0]const u8 = if (rl.isGamepadAvailable(0))
            "L-stick move (tilt = speed)   R-stick look   R1 slash   R2 heavy   B: sprint / tap roll   R3 recenter   Start menu"
        else
            "WASD move   mouse look   LMB slash   Shift+LMB heavy   Shift sprint   Space roll   Esc menu";
        hud_.text(help, 16, rl.getScreenHeight() - 30, 16, rgba(188, 178, 158, 255));
    }

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
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "{s}   {d:.1} m/s", .{ label, g.hero.speed }) catch "";
    const w = hud_.textW(s, 16);
    hud_.text(s, rl.getScreenWidth() - w - 16, 14, 16, rgba(150, 156, 164, 255));

    // Debug stats overlay (menu > Debug > Stats) — perf line + the internal combat meters
    // (poise/stance stay internal, ER-style; only HP shows on the bars).
    if (g.menu.stats) {
        var sbuf: [200]u8 = undefined;
        const st = std.fmt.bufPrintZ(&sbuf, "{d} fps   {d:.1} ms   pos {d:.1},{d:.1}   yaw {d:.2}   pitch {d:.2}   time x{d:.2}", .{
            rl.getFPS(),
            rl.getFrameTime() * 1000.0,
            g.hero.pos.x,
            g.hero.pos.z,
            g.rig.yaw,
            g.rig.pitch,
            g.menu.timeScale,
        }) catch "";
        hud_.text(st, 16, 116, 15, rgba(170, 190, 150, 255));
        const h = &g.hero;
        var cbuf: [200]u8 = undefined;
        const ct = std.fmt.bufPrintZ(&cbuf, "hero  hp {d:.0}/{d:.0}  poise {d:.0}/{d:.0}  stance {d:.0}/{d:.0}   toads {d} left  hits {d}", .{
            h.vit.hp, h.vit.hpMax, h.vit.poise, h.vit.poiseMax, h.vit.stance, h.vit.stanceMax,
            g.warren.aliveCount(), g.warren.totalHits(),
        }) catch "";
        hud_.text(ct, 16, 136, 15, rgba(150, 180, 190, 255));
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
    rl.gl.rlSetClipPlanes(CLIP_NEAR, CLIP_FAR);

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
    var lockCycleReady = true; // debounce so one flick cycles the lock-on target once
    // Rising-edge trackers for rumble: fire a pulse the frame an action BEGINS (catches
    // queued actions too, since we watch the hero's committed state, not the input press).
    var wasRolling = false;
    var wasAttacking = false;
    var wasDead = false;
    defer g.rumble.stop(); // never leave a motor latched after we exit the loop
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime(); // wall-clock dt: feel systems (shake, rumble, fades, tap windows)
        const dt = rawDt * g.menu.timeScale;

        // Esc backs the menu out one level (opens it when closed); pad Start toggles.
        // Quit lives in the menu now.
        if (rl.isKeyPressed(.escape)) g.menu.onEscape();
        if (rl.isGamepadAvailable(0) and rl.isGamepadButtonPressed(0, .middle_right)) g.menu.onStartButton();

        if (g.menu.isOpen()) {
            // The world holds while the menu is up: no camera/move input, but the hero
            // keeps breathing (idle update with zero travel) so the scene stays alive.
            if (g.menu.update(&g.retro, rawDt) == .quit) break;
            // Poison the pad-B tap window while the menu is up: B both BACKS OUT of the
            // menu and dodge-rolls, so a zeroed window would turn the release of the very
            // B press that closed the menu into an instant roll. Poisoned, that release
            // reads as a hold (no tap); a fresh press after release taps normally.
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false; // swallow the mouse delta accumulated while in the menu
            g.hero.update(rawDt, 0, 0);
            g.hero.pose();
            g.rig.tickShake(rawDt); // any live shake decays out under the pause
            g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false); // motors silent while paused (envelopes still decay)
            drawScene(g);
            hud(g);
            g.menu.draw(&g.retro);
            rl.endDrawing();
            continue;
        }

        // Lock-on toggle: R3 (pad) / middle-mouse (kb+m). With a foe locked it drops the lock;
        // else it acquires the best foe in view — and if there is none, pad R3 recenters.
        const lockPressed = rl.isMouseButtonPressed(.middle) or
            (rl.isGamepadAvailable(0) and rl.isGamepadButtonPressed(0, .right_thumb));
        if (lockPressed) {
            if (g.lock != null) {
                g.lock = null;
            } else {
                g.lock = acquireLock(g);
                if (g.lock == null and rl.isGamepadAvailable(0)) g.rig.recenter(g.hero.facing);
            }
        }
        if (g.lock) |li| {
            if (!lockValid(g, li)) g.lock = null; // target wandered out of range
        }

        // Camera look. LOCKED: the camera auto-swings onto the foe and manual look is
        // suppressed — the right stick / mouse instead CYCLE targets. Unlocked: free look.
        const inside = rl.isWindowFocused() and rl.isCursorOnScreen();
        const md = rl.getMouseDelta();
        var wheel = rl.getMouseWheelMove();
        const padRX: f32 = if (rl.isGamepadAvailable(0)) rl.getGamepadAxisMovement(0, .right_x) else @as(f32, 0);
        if (g.lock) |li| {
            const dir = mathx.dirXZ(g.hero.pos, g.warren.frogs[li].pos);
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
            if (inside and wasInside) g.rig.rotate(md.x, md.y);
            if (rl.isGamepadAvailable(0)) {
                const rx = axisDZ(padRX, LOOK_DEADZONE);
                const ry = axisDZ(rl.getGamepadAxisMovement(0, .right_y), LOOK_DEADZONE);
                g.rig.orbit(-rx * PAD_LOOK_RATE * dt, ry * PAD_LOOK_RATE * dt);
            }
        }
        wasInside = inside;
        if (rl.isGamepadAvailable(0)) {
            if (rl.isGamepadButtonPressed(0, .left_face_up)) wheel += 1; // D-pad up = zoom in
            if (rl.isGamepadButtonPressed(0, .left_face_down)) wheel -= 1; // D-pad down = zoom out
        }
        if (wheel != 0) g.rig.zoom(wheel);

        // Dodge roll: Space, or a short TAP of Circle/B (holding B sprints instead).
        var rollReq = rl.isKeyPressed(.space);
        const bDown = rl.isGamepadAvailable(0) and rl.isGamepadButtonDown(0, .right_face_right);
        if (bDown) {
            bHeldT += rawDt; // REAL time: tap-vs-hold is a wall-clock decision, unaffected by debug time-scale
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

        const mv = gatherMove();
        // Poise/stance regenerate every frame (relent and pressure resets — Elden Ring).
        g.hero.vit.tick(dt);
        g.hero.tickFlash(dt); // fade the red damage flash
        // Action input is dead while the hero is staggered or dead (a reaction is committed;
        // souls commitment cuts both ways). Otherwise: a roll press claims the whole frame
        // (rolls win a same-frame conflict), and a queued roll re-steers every frame so it
        // leaves in the direction HELD when it fires, not the one pressed — both ER behaviors.
        if (!g.hero.dead and !g.hero.staggered()) {
            if (rollReq) {
                g.hero.requestRoll(rollDir(g, mv));
            } else if (heavyReq) {
                g.hero.requestAttack(.heavy);
            } else if (lightReq) {
                g.hero.requestAttack(.light);
            }
            g.hero.steerQueuedRoll(rollDir(g, mv));
        }

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, g.warren.frogs[li].pos);
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        if (g.hero.dead) {
            g.hero.updateDeath(dt); // collapse → respawn
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt); // reeling — wide open
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.attacking) {
            g.hero.updateAttack(dt, PLAY_HALF); // committed — a short step into the cut
        } else {
            moveHero(g, dt, mv, lockYaw);
        }
        // The knot hunts the hero; the hero's swept blade damages + staggers the toads, and a
        // toad's chomp/lunge that connects returns the blow it lands ON the hero. Apply it,
        // resolve every footprint collision, then aim the camera at the SETTLED hero position.
        const hitsBefore = g.warren.totalHits();
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, heroBlade(g))) |h| {
            g.hero.takeHit(h);
            // The lunge carries stance damage; the chomp doesn't — split the felt blow by that.
            const slammed = h.stance > 0;
            g.rumble.play(if (slammed) rumblemod.hurt_heavy else rumblemod.hurt);
            g.rig.addShake(if (slammed) SHAKE_HURT_HEAVY else SHAKE_HURT);
        }
        // Your blade connected this frame (hit count climbed) → a hit pulse + frame crack
        // sized to the swing; a toad going down on top adds the kill thunk (justDied — the
        // dissipation means aliveCount only drops much later). Strongest-wins blends them.
        if (g.warren.totalHits() > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
        }
        if (g.warren.anyDied()) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_KILL);
        }
        // ER lock-on across a kill: the lock leaves a corpse the FRAME it dies — never
        // waiting out the death anim/dissipation — snapping to the next valid target in
        // view (nearest screen-centre, like a fresh acquire) or dropping if there's none.
        if (g.lock) |li| {
            const lf = &g.warren.frogs[li];
            if (!lf.alive() or lf.dying()) g.lock = acquireLock(g);
        }
        collideActors(g, dt);
        g.rig.tickShake(rawDt); // impact shake decays on wall-clock time (bakes this frame's jitter)
        g.rig.follow(g.hero.shoulderPoint());

        // Rising-edge action pulses: a roll whump, the swing effort (heavy reads heavier than
        // light), and the death swell. Watching committed state catches queued actions too.
        if (g.hero.rolling and !wasRolling) g.rumble.play(rumblemod.roll);
        if (g.hero.attacking and !wasAttacking) g.rumble.play(if (g.hero.atkHeavy) rumblemod.swing_heavy else rumblemod.swing_light);
        if (g.hero.dead and !wasDead) {
            g.rumble.play(rumblemod.death);
            g.rig.addShake(SHAKE_DEATH);
        }
        // The YOU DIED tail: armed while dead, drains after the respawn (fade from black).
        if (g.hero.dead) {
            g.deathFade = RESPAWN_FADE;
        } else if (g.deathFade > 0) {
            g.deathFade -= rawDt;
        }
        wasRolling = g.hero.rolling;
        wasAttacking = g.hero.attacking;
        wasDead = g.hero.dead;
        g.rumble.update(rawDt, rl.isGamepadAvailable(0));

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
        .hit = g.hero.attackHit(), // HP/poise/stance for THIS swing (light vs heavy)
    };
}

// Resolve footprint collisions on the XZ plane (see collision.zig). The hero keeps priority
// — pushed out of world solids, then out of any GROUNDED toad; the toads then yield, each
// pushed out of the world, the hero, and its grounded neighbours. Airborne toads (mid-hop)
// are skipped so a leap arcs over you cleanly instead of shoving you around.
fn collideActors(g: *Game, dt: f32) void {
    const solids = g.env.solids();
    const step = COLLIDE_RATE * dt; // max correction this frame — bigger pushes ease in (no warp)
    var hp = collision.resolve(g.hero.pos, HERO_R, solids);
    for (&g.warren.frogs) |*f| {
        if (f.alive() and !f.airborne()) hp = collision.pushOutCircle(hp, HERO_R, f.pos, f.bodyR());
    }
    hp.x = mathx.clampF(hp.x, -PLAY_HALF, PLAY_HALF);
    hp.z = mathx.clampF(hp.z, -PLAY_HALF, PLAY_HALF);
    g.hero.pos = mathx.approachV(g.hero.pos, hp, step);

    for (&g.warren.frogs, 0..) |*f, i| {
        if (!f.alive() or f.airborne()) continue;
        var fp = collision.resolve(f.pos, f.bodyR(), solids);
        fp = collision.pushOutCircle(fp, f.bodyR(), g.hero.pos, HERO_R);
        for (&g.warren.frogs, 0..) |*o, j| {
            if (i == j or !o.alive() or o.airborne()) continue;
            fp = collision.pushOutCircle(fp, f.bodyR(), o.pos, o.bodyR());
        }
        fp.x = mathx.clampF(fp.x, -PLAY_HALF, PLAY_HALF);
        fp.z = mathx.clampF(fp.z, -PLAY_HALF, PLAY_HALF);
        f.pos = mathx.approachV(f.pos, fp, step);
    }
}

// ── lock-on helpers ─────────────────────────────────────────────────────────────────
// A dying toad is NOT a lock target anywhere below: the kill handler in run() switches
// or drops the lock the frame it dies, and no acquire/cycle may pick a corpse back up.
fn lockValid(g: *const Game, i: usize) bool {
    const f = &g.warren.frogs[i];
    return f.alive() and !f.dying() and mathx.distXZ(g.hero.pos, f.pos) <= MAX_LOCK_R + 2.0;
}

// A world point projected to the screen, or null if it sits nearer than the near-clip
// plane — the shared front-of-camera cull for the lock reticle, the foe HP bars, and
// lock-screen-x. The threshold must be the near clip distance, not just depth > 0: a point
// at depth ~0+ (a foe right at the camera plane, e.g. lunging past the hero as the camera
// swings) projects to an unbounded screen coordinate, and the callers' @intFromFloat(s.x)
// would then be an out-of-range cast (a panic in safe builds). Below near, nothing renders.
const PROJECT_NEAR = CLIP_NEAR; // must equal the near clip plane set in run()
fn projectToScreen(cam: rl.Camera3D, p: rl.Vector3) ?rl.Vector2 {
    const to = mathx.subV(p, cam.position);
    const fwd = mathx.normV(mathx.subV(cam.target, cam.position)); // camera forward (unit)
    const depth = to.x * fwd.x + to.y * fwd.y + to.z * fwd.z; // signed distance along the view axis
    if (depth < PROJECT_NEAR) return null;
    return rl.getWorldToScreen(p, cam);
}

// Screen-x of a foe's lock point (null if it's behind the camera).
fn lockScreenX(g: *const Game, i: usize) ?f32 {
    const s = projectToScreen(g.rig.cam, g.warren.frogs[i].lockPoint()) orelse return null;
    return s.x;
}

// The foe nearest screen-centre and in range (Elden Ring locks what you're looking at); null
// if none — the caller recenters instead.
fn acquireLock(g: *Game) ?usize {
    const cx = @as(f32, @floatFromInt(rl.getScreenWidth())) * 0.5;
    var best: ?usize = null;
    var bestScore: f32 = 1e9;
    for (g.warren.frogs, 0..) |f, i| {
        if (!f.alive() or f.dying() or mathx.distXZ(g.hero.pos, f.pos) > MAX_LOCK_R) continue;
        const sx = lockScreenX(g, i) orelse continue;
        const score = @abs(sx - cx);
        if (score < bestScore) {
            bestScore = score;
            best = i;
        }
    }
    return best;
}

// Switch to the next in-range foe whose screen-x lies on `dir` side (-1 left / +1 right) of
// the current target — the right-stick / mouse flick cycle.
fn cycleLock(g: *Game, dir: f32) void {
    const cur = g.lock orelse return;
    const curX = lockScreenX(g, cur) orelse return;
    var best: ?usize = null;
    var bestGap: f32 = 1e9;
    for (g.warren.frogs, 0..) |f, i| {
        if (i == cur or !f.alive() or f.dying()) continue;
        if (mathx.distXZ(g.hero.pos, f.pos) > MAX_LOCK_R) continue;
        const sx = lockScreenX(g, i) orelse continue;
        const gap = (sx - curX) * dir;
        if (gap > 5.0 and gap < bestGap) {
            bestGap = gap;
            best = i;
        }
    }
    if (best) |b| g.lock = b;
}

// A 2D health bar: black backing, a dark empty track, a red fill. `border` outlines it
// (used to flash gold on a stance-broken foe — ER's crit-opening cue).
fn healthBar(x: f32, y: f32, w: f32, h: f32, frac: f32, border: ?rl.Color) void {
    const xi: i32 = @intFromFloat(x);
    const yi: i32 = @intFromFloat(y);
    const wi: i32 = @intFromFloat(w);
    const hi: i32 = @intFromFloat(h);
    rl.drawRectangle(xi - 1, yi - 1, wi + 2, hi + 2, rgba(0, 0, 0, 170)); // backing
    rl.drawRectangle(xi, yi, wi, hi, rgba(38, 12, 10, 230)); // empty track
    const fw: i32 = @intFromFloat(w * mathx.clampF(frac, 0, 1));
    if (fw > 0) rl.drawRectangle(xi, yi, fw, hi, rgba(158, 32, 28, 255)); // blood-red fill
    if (border) |c| rl.drawRectangleLines(xi - 1, yi - 1, wi + 2, hi + 2, c);
}

// A foe's bar only appears once you've HURT it, and lingers this long after the last hit —
// so untouched foes stay unmarked and the bar fades from view when you disengage.
const HURT_BAR_WINDOW = 5.0;

// Floating HP bars over the toads (ER shows bars for foes). Shown ONLY for a live toad you've
// hit within HURT_BAR_WINDOW; the bar flashes gold while the toad is staggered (wide-open cue).
fn drawFrogBars(g: *Game) void {
    const cam = g.rig.cam;
    for (&g.warren.frogs) |*f| {
        if (!f.alive() or f.dying()) continue; // no bar over a corpse dissolving out
        if (f.vit.sinceHit > HURT_BAR_WINDOW) continue; // only after a recent hit
        const s = projectToScreen(cam, f.topWorld()) orelse continue; // skip if behind the camera
        const w: f32 = 54;
        const border: ?rl.Color = if (f.staggered()) rgba(232, 196, 90, 255) else null;
        healthBar(s.x - w * 0.5, s.y - 16, w, 5, f.vit.hpFrac(), border);
    }
}

// The glowing white reticle on the locked foe (ER's dot) — 2D + crisp, drawn after the 3D pass.
fn drawLockDot(g: *Game) void {
    const li = g.lock orelse return;
    const s = projectToScreen(g.rig.cam, g.warren.frogs[li].lockPoint()) orelse return; // skip if behind the camera
    const x: i32 = @intFromFloat(s.x);
    const y: i32 = @intFromFloat(s.y);
    rl.drawCircle(x, y, 9, rgba(255, 255, 255, 40)); // soft halo
    rl.drawCircle(x, y, 4, rgba(255, 255, 255, 230)); // bright core
    rl.drawCircle(x, y, 2, rl.Color.white);
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
    while (k < frames) : (k += 1) _ = f.update(dt, hero, PLAY_HALF, .{});
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
    g.rig.yaw = mathx.radians(30); // front 3/4 — the hero faces -Z, so this shows the sword-arm arc (270 hid it behind the torso)
    g.rig.pitch = 0.13;
    g.rig.dist = 4.2;
    g.hero.startAttack(.light);
    advanceAttack(g, dt, 10); // ~u 0.28: windup apex — fist by the ear, blade over the shoulder
    shoot(g, "shots/15a_atk_light_wind.png");
    advanceAttack(g, dt, 5); // ~u 0.42: blade mid-arc, elbow whipping through
    shoot(g, "shots/15_atk_light_strike.png");
    advanceAttack(g, dt, 4); // ~u 0.53: the whip PEAK — wrist snapped, blade level through contact
    shoot(g, "shots/15p_atk_light_peak.png");
    advanceAttack(g, dt, 3); // ~u 0.61: follow-through — blade swept across past the off hip
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
        stepFrog(f, 26, behind); // deep into the long telegraph coil (loaded, dust flying, throat charged)
        shootFrog(g, f, "shots/25_frog_lunge_wind.png", 55, 0.09, 3.3);
        stepFrog(f, 60, behind); // through flight + heavy landing, ~0.3 s into recovery
        shootFrog(g, f, "shots/26_frog_recover.png", 70, 0.13, 3.2);

        // A chomp: gape (sac balloons, jaws yawn) → snap. Framed front-quarter to see the maw.
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.startChomp();
        stepFrog(f, 22, front); // near full gape (charge gathering, drool stringing)
        shootFrog(g, f, "shots/27_frog_gape.png", 162, 0.06, 2.2); // front 3/4, close — peer into the maw
        stepFrog(f, 6, front); // jaws slamming
        shootFrog(g, f, "shots/28_frog_snap.png", 162, 0.06, 2.2);

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
            _ = f.update(dt2, mathx.ground(0, 60), PLAY_HALF, heroBlade(g));
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

        // Lock-on: the glowing white reticle riding a locked foe (ER-style).
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        stepFrog(f, 8, front);
        g.hero.pos = mathx.ground(1.7, 3.6);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.hero.update(1.0 / 60.0, 0, 0);
        g.hero.pose();
        g.lock = 0;
        g.rig.yaw = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.rig.pitch = 0.16;
        g.rig.dist = 5.4;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/30_lockon.png");
        g.lock = null;
    }

    // ── combat reactions: the two-tier stagger + death, both sides, then the HP bars ──────
    {
        const f = &g.warren.frogs[0];
        const front = mathx.ground(0, 60); // "hero" out front so a reeling toad faces the camera

        // FROG — light flinch, heavy stance-break crumple, death collapse.
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.debugStagger(false);
        stepFrog(f, 13, front); // flinch PEAK (reared back and up off the blow)
        shootFrog(g, f, "shots/31_frog_flinch.png", 70, 0.12, 3.2);
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.debugStagger(true);
        stepFrog(f, 24, front); // deep in the crumple — splayed, wide open
        shootFrog(g, f, "shots/32_frog_stagger.png", 55, 0.12, 3.4);
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.debugKill();
        stepFrog(f, 42, front); // collapsed
        shootFrog(g, f, "shots/33_frog_death.png", 60, 0.10, 3.4);

        // HERO — force each reaction with a synthetic blow, framed from the sword 3/4.
        g.hero.pos = mathx.ground(0, 4);
        g.hero.facing = std.math.pi;
        g.hero.takeHit(.{ .poise = 999 }); // empty poise → the light flinch
        var sk: i32 = 0;
        while (sk < 13) : (sk += 1) g.hero.updateStun(dt); // flinch PEAK
        g.rig.yaw = mathx.radians(60);
        g.rig.pitch = 0.12;
        g.rig.dist = 4.6;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/34_hero_flinch.png");
        while (g.hero.staggered()) g.hero.updateStun(dt);

        g.hero.takeHit(.{ .stance = 999 }); // empty stance → the heavy stagger
        sk = 0;
        while (sk < 26) : (sk += 1) g.hero.updateStun(dt);
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/35_hero_stagger.png");
        while (g.hero.staggered()) g.hero.updateStun(dt);

        g.hero.takeHit(.{ .dmg = 999 }); // lethal → the death collapse
        sk = 0;
        while (sk < 130) : (sk += 1) g.hero.updateDeath(dt); // deep into the card: heap + YOU DIED full
        g.rig.pitch = 0.22;
        g.rig.dist = 5.2;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/36_hero_death.png");
        while (g.hero.dead) g.hero.updateDeath(dt); // run out → respawn (restores clean state)

        // HP BARS: a half-health foe's floating bar + the hero's top-left bar, together.
        g.hero.hurtFlash = 0; // clear any leftover flash from the death shot (harness never ticks it)
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.vit.hp = f.vit.hpMax * 0.45;
        stepFrog(f, 4, front);
        g.hero.pos = mathx.ground(2.4, 4.2);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.hero.update(dt, 0, 0);
        g.hero.pose();
        g.rig.yaw = mathx.radians(202);
        g.rig.pitch = 0.16;
        g.rig.dist = 6.4;
        g.rig.follow(f.centerWorld());
        shoot(g, "shots/37_hp_bars.png");
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // reset the slot
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
