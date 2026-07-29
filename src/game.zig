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
const foemod = @import("foe.zig"); // THE FOE STANDARD — the shared Blade/strike contract
const collision = @import("collision.zig");
const rumblemod = @import("rumble.zig");
const archermod = @import("archer.zig");
const ogremod = @import("ogre.zig");

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
const STICK_DEADZONE = 0.16; // left-stick move deadzone
const LOOK_DEADZONE = 0.12; // right-stick look deadzone
const PAD_LOOK_RATE = 2.7; // rad/sec camera orbit at full right-stick deflection
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
const RESPAWN_FADE = 0.9; // seconds of black → world after a respawn (the YOU DIED tail)

// Hero movement clamp: world bounds inset by a margin so travel/rolls can't reach the edge.
// Single source for moveHero, roll updates, and the --shot harness.
const PLAY_HALF = envmod.HALF - 2.0;

// Hero footprint radius for ground collision (see collision.zig). Defined in foe.zig alongside
// foe.HERO_REACH, so a foe's attack shapes can be reasoned about against how close he can GET.
const HERO_R = foemod.HERO_R;

// Skeletal-archer arrows: shared pool of in-flight + stuck shafts, plus the hero centre-of-
// mass height archers aim at and arrows test strikes against.
const MAX_ARROWS = 24;
const HERO_CENTER_Y = 1.0;

// Collision correction is rate-limited so a large depenetration eases in over a few frames
// (smooth slide, not a choppy warp). Set above the fastest actor speed so wall contact
// still resolves firmly (no sinking).
const COLLIDE_RATE = 11.0; // world units / sec

// Depth clip planes, set once at startup (see run()): tight near/far so the hero's
// overlapping boxes don't z-fight. Invariant: projectToScreen's near-cull (PROJECT_NEAR)
// MUST equal CLIP_NEAR — both read this, never the literal.
// DEPTH PRECISION IS SET BY THE NEAR PLANE, and it is what makes distant detail FLICKER. Resolution
// at depth z goes roughly as z²·(1/near − 1/far)/2^24, so at 0.2 the gap between depth steps out at
// 250 m was ~1.9 cm — and props.zig deliberately OVERLAPS its facing blocks by a couple of cm
// ("blocks OVERLAP their slot"), so those overlaps fell inside one depth step and z-fought.
// 0.55 buys 2.5x the precision (~0.75 cm at 250 m) and costs nothing: the orbit rig never puts the
// eye nearer than camera.MIN_DIST (2.4) to its look-at, and the closest --shot framing is 2.0.
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

const Game = struct {
    scene: gfx.Scene,
    sky: gfx.Sky,
    vignette: gfx.Vignette,
    retro: gfx.Retro,
    menu: menumod.Menu,
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

    // Built IN PLACE rather than returned by value: Env alone is ~450 KB of flat prop/grid
    // arrays, and a by-value Game would copy all of it across the stack on the way out.
    fn init(g: *Game) void {
        g.scene = gfx.Scene.init();
        g.sky = gfx.Sky.init();
        g.vignette = gfx.Vignette.init();
        g.retro = gfx.Retro.init(rl.getScreenWidth(), rl.getScreenHeight());
        g.menu = .{}; // opens on the main screen: Continue / Debug / Quit
        g.env.build(g.scene.shader);
        g.hero = heromod.Hero.init(g.scene.shader);
        g.hero.pos = mathx.ground(0, 4); // start just south of the ruin avenue
        g.hero.facing = std.math.pi; // facing -Z, into the columns
        g.hero.setSpawn(g.hero.pos, g.hero.facing); // where a death returns him
        g.hero.pose();
        g.warren = frogmod.Knot.init(g.scene.shader);
        g.line = archermod.Line.init(g.scene.shader);
        g.grief = ogremod.Grief.init(g.scene.shader);
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
        // Fields that would otherwise take their struct-literal defaults; set explicitly
        // because there is no literal to default from any more.
        g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
        g.lock = null;
        g.rumble = .{};
        g.deathFade = 0;
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
    if (rl.isGamepadAvailable(PAD)) {
        if (rl.isGamepadButtonDown(PAD, .right_face_right)) sprint = true;
        const gx = axisDZ(rl.getGamepadAxisMovement(PAD, .left_x), STICK_DEADZONE);
        const gz = -axisDZ(rl.getGamepadAxisMovement(PAD, .left_y), STICK_DEADZONE); // stick up = forward
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
    const sprinting = isMoving and mv.speed > RUN_SPEED + 0.01;
    if (isMoving) {
        dir = v3(dir.x / l, 0, dir.z / l);
        speed = mv.speed;
        moveYaw = mathx.headingXZ(dir);
        // Locked-on ANISOTROPY (ER does this too): sideways travel runs a little slower than
        // forward. It is not an input gate — the stick still maps straight to speed the same frame,
        // it is the DIRECTION that costs. This is also what lets the sidestep keep a walking
        // CADENCE: step rate is speed / hero.STRAFE_CYCLE and the cycle is capped by real hip ROM,
        // so pure lateral travel at full forward speed needs ~20% more steps per second than a
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
// Casters = the hero + the stone props. NOT the ground (receives only) and NOT the flora (a
// non-caster, lit pass only, swayed by wind). BOTH passes draw through this one function so
// transforms can't drift; only the CULL differs, and each pass hands in its own (env.Cull).
// The depth pass culls by SHADOW REACH, not distance from focus — a tall caster well outside
// the box still throws into it at this sun angle, so a plain distance cull clips real shadows.
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
fn arrowCover(g: *const Game, ar: *const archermod.Arrow, dt: f32) []const collision.Solid {
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

fn drawScene(g: *Game) void {
    g.env.resetStats(); // culling counters for the debug overlay, both passes together
    // Sun depth pass into the shadow map (before beginDrawing). Ortho box tracks the hero, and
    // the pass draws only what can throw INTO that box (env.Cull.sun).
    g.scene.beginShadowPass(g.hero.pos);
    setCasterShaders(g, g.scene.depthShader);
    drawCasters(g, .{ .sun = g.hero.pos });
    setCasterShaders(g, g.scene.shader);
    g.scene.endShadowPass();

    rl.beginDrawing();
    // With any retro filter live, sky + 3D render into the capture RT and blit back through
    // the filter shader; vignette/HUD/menu stay crisp on top.
    const filtered = g.retro.begin();
    rl.clearBackground(CLEAR);
    g.sky.draw(g.rig.cam);

    // ONE view frustum for the whole lit pass, built from the settled camera — props and flora
    // must cull against the same one or a prop can be in for the shadow and out for the light.
    const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
    const view = envmod.View.fromCamera(g.rig.cam, aspect);

    rl.beginMode3D(g.rig.cam);
    g.scene.bind(g.rig.cam.position);
    // Torchlight: the fires nearest the camera, guttering. Must land before anything draws —
    // the uniforms are read by every subsequent draw through the scene shader.
    g.env.uploadLights(&g.scene, g.rig.cam.position, @floatCast(rl.getTime()));
    g.scene.setGround(true);
    g.env.drawGround();
    g.scene.setGround(false);
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
    // Debug: the blade hit capsule (menu > Debug > Hitboxes) — red while ACTIVE, dim
    // otherwise. Unlit, default shader on purpose.
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
        for (&g.grief.ogres) |*o| {
            if (!o.alive()) continue;
            const col = if (o.flash > 0) rl.Color.orange else mathx.withAlpha(rl.Color.yellow, 80);
            rl.drawSphereWires(o.centerWorld(), o.hurtRadius(), 8, 10, col);
        }
    }
    rl.endMode3D();

    if (filtered) g.retro.end();
    g.vignette.draw();
    drawHurtFlash(g); // red screen-edge pulse when the hero is hit (peripheral feedback)
    drawFoeBars(g, &g.warren.frogs); // floating foe HP bars, crisp over the finished frame…
    drawFoeBars(g, &g.line.archers); // …one shared path for every foe group…
    drawFoeBars(g, &g.grief.ogres); // …the ogre included (a regular foe, not a boss — owner's call)
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
    // ASCII only — the Balthazar atlas is loaded with the default (ASCII) glyph set, so a "·"
    // or "—" would render as a tofu "?". Every size comes from hud_'s type scale, never a literal.
    hud_.text("zig-soulslike", 16, 12, hud_.TITLE, rgba(232, 222, 198, 255));
    const subY = 12 + hud_.lineH(hud_.TITLE);
    // Not a "locomotion demo" any more — that subtitle outlived the swordplay, three foes, the
    // stagger model and five regions, and it was the first line of text in every screenshot.
    hud_.text("a fallen kingdom - sword, roll, lock-on; toads, skeletons, a giant", 16, subY, hud_.SMALL, rgba(164, 154, 134, 255));

    // Hero HP bar (ER puts player health top-left). Death card is drawDeathOverlay's — no
    // mini YOU DIED here.
    const barY = subY + hud_.lineH(hud_.SMALL) + 4;
    healthBar(16, @floatFromInt(barY), 340, 18, g.hero.vit.hpFrac(), rgba(24, 20, 16, 220));
    if (!g.menu.isOpen()) {
        const help: [:0]const u8 = if (rl.isGamepadAvailable(PAD))
            "L-stick move (tilt = speed)   R-stick look   R1 slash   R2 heavy   B: sprint / tap roll   R3 recenter   Start menu"
        else
            "WASD move   mouse look   LMB slash   Shift+LMB heavy   Shift sprint   Space roll   Esc menu";
        hud_.text(help, 16, rl.getScreenHeight() - hud_.lineH(hud_.SMALL) - 14, hud_.SMALL, rgba(188, 178, 158, 255));
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
    const w = hud_.textW(s, hud_.BODY);
    hud_.text(s, rl.getScreenWidth() - w - 16, 14, hud_.BODY, rgba(150, 156, 164, 255));

    // Debug stats overlay (menu > Debug > Stats) — perf line + internal combat meters.
    // Poise/stance stay internal (ER-style); only HP shows on the bars.
    if (g.menu.stats) {
        // Three stacked rows, positioned off the type scale rather than off hard-coded Y values —
        // at literal 116/136/156 with the larger face they overlapped each other.
        const row0 = barY + 30;
        const step = hud_.lineH(hud_.SMALL);
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
        hud_.text(st, 16, row0, hud_.SMALL, rgba(170, 190, 150, 255));
        // World + culling line: how much of the world exists vs how much of it this frame drew.
        // The expansion's whole perf claim is "thousands of props, a few hundred draws" — this is
        // where you check it while playing instead of taking a comment's word for it.
        var wbuf: [200]u8 = undefined;
        const wt = std.fmt.bufPrintZ(&wbuf, "world  props {d}  solids {d}  fires {d}   drawn {d} in {d} cells (both passes)", .{
            g.env.propCount(), g.env.solidCount(), g.env.lightCount(), g.env.stat_draws, g.env.stat_cells,
        }) catch "";
        hud_.text(wt, 16, row0 + step * 2, hud_.SMALL, rgba(150, 175, 195, 255));
        const h = &g.hero;
        var cbuf: [200]u8 = undefined;
        // Foe counts span EVERY group (the combat beats already do) — a toads-only "hits" read
        // silently ignored every blow landed on a skeleton or the giant.
        const foesLeft = g.warren.aliveCount() + g.line.aliveCount() + g.grief.aliveCount();
        const foeHits = g.warren.totalHits() + g.line.totalHits() + g.grief.totalHits();
        const ct = std.fmt.bufPrintZ(&cbuf, "hero  hp {d:.0}/{d:.0}  poise {d:.0}/{d:.0}  stance {d:.0}/{d:.0}   foes {d} left  hits {d}", .{
            h.vit.hp, h.vit.hpMax, h.vit.poise, h.vit.poiseMax, h.vit.stance, h.vit.stanceMax,
            foesLeft, foeHits,
        }) catch "";
        hud_.text(ct, 16, row0 + step, hud_.SMALL, rgba(150, 180, 190, 255));
    }
}

fn gaitLabel(moving: f32, speed: f32) [:0]const u8 {
    if (moving < 0.5) return "idle";
    if (speed >= SPRINT_SPEED - 0.3) return "sprinting";
    if (speed >= RUN_SPEED - 0.3) return "running";
    return "walking";
}

pub fn run(shot: bool) void {
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

    const alloc = std.heap.c_allocator;
    const g = alloc.create(Game) catch return;
    defer alloc.destroy(g);
    g.init();

    // Tight near/far for real depth precision — the default 0.01..1000 makes the hero's
    // overlapping boxes z-fight and flicker/invert as the camera moves. BeginMode3D reads
    // these; the shadow pass saves/restores them around its ortho slab, so setting them
    // once here sticks. Set BEFORE the --shot branch so headless captures match.
    rl.gl.rlSetClipPlanes(CLIP_NEAR, CLIP_FAR);

    if (shot) {
        runShots(g);
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
    // Rising-edge trackers for rumble: pulse the frame an action BEGINS. Watching committed
    // state (not the input press) catches queued actions too.
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
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .middle_right)) g.menu.onStartButton();

        // Alt+Enter toggles borderless-windowed fullscreen (no exclusive mode-switch, so the
        // mouse stays usable elsewhere). Keep the retro capture RT matched to the window on
        // the toggle AND on any manual resize.
        if (rl.isKeyPressed(.enter) and (rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt))) {
            rl.toggleBorderlessWindowed();
            g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());
        }
        if (rl.isWindowResized()) g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());

        if (g.menu.isOpen()) {
            // World holds while the menu is up: no camera/move input, but the hero keeps
            // breathing (idle update, zero travel) so the scene stays alive.
            if (g.menu.update(&g.retro, rawDt) == .quit) break;
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
            drawScene(g);
            hud(g);
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
            if (inside and wasInside) g.rig.rotate(md.x, md.y);
            if (rl.isGamepadAvailable(PAD)) {
                const rx = axisDZ(padRX, LOOK_DEADZONE);
                const ry = axisDZ(rl.getGamepadAxisMovement(PAD, .right_y), LOOK_DEADZONE);
                g.rig.orbit(-rx * PAD_LOOK_RATE * dt, ry * PAD_LOOK_RATE * dt);
            }
        }
        wasInside = inside;
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .left_face_up)) wheel += 1; // D-pad up = zoom in
            if (rl.isGamepadButtonPressed(PAD, .left_face_down)) wheel -= 1; // D-pad down = zoom out
        }
        if (wheel != 0) g.rig.zoom(wheel);

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

        const mv = gatherMove();
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
        }

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
        const hitsBefore = g.warren.totalHits() + g.line.totalHits() + g.grief.totalHits();
        // ONE snapshot of the blade for every group this frame — the hero's pose is already
        // resolved above, so re-deriving it per group only invited the three to disagree.
        const bladeNow = heroBlade(g);
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |h| {
            g.hero.takeHit(h);
            // The lunge carries stance damage; the chomp doesn't — split the felt blow by that.
            const slammed = h.stance > 0;
            g.rumble.play(if (slammed) rumblemod.hurt_heavy else rumblemod.hurt);
            g.rig.addShake(if (slammed) SHAKE_HURT_HEAVY else SHAKE_HURT);
        }
        // The lone ogre hunts, slams and side-swipes. The overhead crush is the full heavy beat; the
        // faster swipe hurts less and is FELT less, so the two read apart through the pad and camera
        // as well as on screen (split off the blow's own stance damage, like the toad's above).
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |h| {
            g.hero.takeHit(h);
            const crushed = h.stance >= ogremod.SLAM_HIT.stance;
            g.rumble.play(if (crushed) rumblemod.hurt_heavy else rumblemod.hurt);
            g.rig.addShake(if (crushed) SHAKE_HURT_HEAVY else SHAKE_HURT);
        }
        // Blade lands on the skeletons; then they act — kite and loose from the nock at the
        // hero's centre of mass (arrow homing + arc finish the job). A blade hit mid-draw
        // interrupts the shot (enterStun clears the draw).
        for (&g.line.archers) |*a| {
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
            if (ar.hit and !g.hero.dead) {
                g.hero.takeHit(archermod.ARROW_HIT);
                g.rumble.play(rumblemod.hurt);
                g.rig.addShake(SHAKE_HURT);
            }
        }
        // Blade connected this frame (a foe's hit count climbed) → hit pulse + frame crack
        // sized to the swing; a kill adds the thunk (via justDied, since dissipation delays
        // the aliveCount drop). Strongest-wins blends them.
        if (g.warren.totalHits() + g.line.totalHits() + g.grief.totalHits() > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
        }
        if (g.warren.anyDied() or g.line.anyDied() or g.grief.anyDied()) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_KILL);
        }
        // ER lock-on across a kill: the lock leaves a corpse the FRAME it dies (not after the
        // death anim), snapping to the next valid target (nearest screen-centre, like a fresh
        // acquire) or dropping if none.
        if (g.lock) |li| {
            if (!foeLockable(g, li)) g.lock = acquireLock(g); // corpse the frame it dies → switch/drop
        }
        collideActors(g, dt);
        g.rig.tickShake(rawDt); // impact shake decays on wall-clock time (bakes this frame's jitter)
        g.rig.follow(g.hero.shoulderPoint());

        // Rising-edge action pulses: roll whump, swing effort (heavy > light), death swell.
        // Watching committed state catches queued actions too.
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
        g.rumble.update(rawDt, rl.isGamepadAvailable(PAD));

        drawScene(g);
        hud(g);
        rl.endDrawing();
    }
}

// The hero's blade this frame as plain data for the foe hit test (endpoints guard→tip, plus
// last frame's for the swept test; active only inside the strike window). Typed on the FOE
// STANDARD directly (foe.Blade), not on frog.zig's re-export — the blade is every foe's business.
fn heroBlade(g: *const Game) foemod.Blade {
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
    for (&g.warren.frogs) |*f| {
        if (f.alive() and !f.airborne()) hp = collision.pushOutCircle(hp, HERO_R, f.pos, f.bodyR());
    }
    for (&g.line.archers) |*a| {
        if (a.alive()) hp = collision.pushOutCircle(hp, HERO_R, a.pos, a.bodyR());
    }
    for (&g.grief.ogres) |*o| {
        if (o.alive()) hp = collision.pushOutCircle(hp, HERO_R, o.pos, o.bodyR());
    }
    g.hero.pos = mathx.approachV(g.hero.pos, inBounds(hp), step);

    for (&g.warren.frogs, 0..) |*f, i| {
        if (!f.alive() or f.airborne()) continue;
        var fp = g.env.resolveActor(f.pos, f.bodyR());
        fp = collision.pushOutCircle(fp, f.bodyR(), g.hero.pos, HERO_R);
        for (&g.warren.frogs, 0..) |*o, j| {
            if (i == j or !o.alive() or o.airborne()) continue;
            fp = collision.pushOutCircle(fp, f.bodyR(), o.pos, o.bodyR());
        }
        f.pos = mathx.approachV(f.pos, inBounds(fp), step);
    }

    // Archers yield last: each pushed out of world, hero, every grounded toad, and fellow
    // archers (same easing so a kite step into a wall slides, not warps).
    for (&g.line.archers, 0..) |*a, i| {
        if (!a.alive()) continue;
        var ap = g.env.resolveActor(a.pos, a.bodyR());
        ap = collision.pushOutCircle(ap, a.bodyR(), g.hero.pos, HERO_R);
        for (&g.warren.frogs) |*f| {
            if (f.alive() and !f.airborne()) ap = collision.pushOutCircle(ap, a.bodyR(), f.pos, f.bodyR());
        }
        for (&g.line.archers, 0..) |*o, j| {
            if (i == j or !o.alive()) continue;
            ap = collision.pushOutCircle(ap, a.bodyR(), o.pos, o.bodyR());
        }
        a.pos = mathx.approachV(a.pos, inBounds(ap), step);
    }

    // The ogre yields to the WORLD (walls/columns) only, never to the tiny hero (who yields
    // above), so it reads as immovable bulk.
    for (&g.grief.ogres) |*o| {
        if (!o.alive()) continue;
        const op = g.env.resolveActor(o.pos, o.bodyR());
        o.pos = mathx.approachV(o.pos, inBounds(op), step);
    }
}

// ── lock-on helpers (generic over ANY foe — toads AND skeletons — via FoeRef) ──────────
// A reference to a locked foe across the heterogeneous groups; the lock-on + reticle systems
// dispatch through the foe* accessors so every foe type is lockable (the foe standard, foe.zig).
// A dying/dissipating foe is NEVER a target: the kill handler in run() drops/switches the lock
// the frame it dies, and no acquire/cycle may pick a corpse back up.
const FoeKind = enum { toad, archer, ogre };
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
    considerLock(g, &g.warren.frogs, .toad, cx, &best, &bestScore);
    considerLock(g, &g.line.archers, .archer, cx, &best, &bestScore);
    considerLock(g, &g.grief.ogres, .ogre, cx, &best, &bestScore);
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
    considerCycle(g, &g.warren.frogs, .toad, cur, curX, dir, &best, &bestGap);
    considerCycle(g, &g.line.archers, .archer, cur, curX, dir, &best, &bestGap);
    considerCycle(g, &g.grief.ogres, .ogre, cur, curX, dir, &best, &bestGap);
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

// The world-reload half of a hero death (ER: dying resets the field). Every group re-homes
// fresh instances (full HP, home positions, slain restored), the arrow pool empties, the
// lock drops. Instance state only — shared Models are permanent, never rebuilt.
fn resetFoes(g: *Game) void {
    g.warren.reset();
    g.line.reset();
    g.grief.reset();
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
        const w: f32 = 54;
        const border: ?rl.Color = if (f.staggered()) rgba(232, 196, 90, 255) else null;
        healthBar(s.x - w * 0.5, s.y - 16, w, 5, f.vit.hpFrac(), border);
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

// ── headless capture ───────────────────────────────────────────────────────────────
// The harness steps on a FIXED timestep so every capture is reproducible frame-for-frame; the
// per-stage frame counts in runShots are all quoted against it, so it is one constant, not six
// scattered `1.0 / 60.0` literals.
const SHOT_DT: f32 = 1.0 / 60.0;
// Walk the hero along a FIXED world direction (−Z, into the ruins) and shoot it from
// several true camera angles + stride phases into shots/ (window hidden). Movement is
// world-fixed here (not camera-relative like the live loop) so we can orbit the camera to
// a real side/front profile and actually judge the gait. Mirrors the siblings' --shot.
fn stepWorld(g: *Game, dt: f32, speed: f32) void {
    const moved = speed * dt;
    g.hero.pos.z = mathx.clampF(g.hero.pos.z - moved, -PLAY_HALF, PLAY_HALF); // travel −Z
    g.hero.facing = std.math.pi; // face −Z (no turning)
    g.hero.update(dt, moved, speed, if (moved > 0) std.math.pi else null);
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
}

// Locked-on counterpart of stepWorld: travel a world direction while FACING holds on a
// target heading — the strafe / backpedal gaits, framed like the walk stages.
fn stepLocked(g: *Game, dt: f32, speed: f32, dir: rl.Vector3, faceYaw: f32) void {
    const moved = speed * dt;
    g.hero.pos.x = mathx.clampF(g.hero.pos.x + dir.x * moved, -PLAY_HALF, PLAY_HALF);
    g.hero.pos.z = mathx.clampF(g.hero.pos.z + dir.z * moved, -PLAY_HALF, PLAY_HALF);
    g.hero.facing = faceYaw;
    g.hero.update(dt, moved, speed, mathx.headingXZ(dir));
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
}

// Render the current world + HUD and write one screenshot. Shared idiom for every non-menu
// shot (menu shots interpose g.menu.draw before endDrawing, so they stay inline below).
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
        g.hero.updateAttack(dt, PLAY_HALF, null);
        g.rig.follow(g.hero.shoulderPoint());
    }
}

// Advance ANY foe `frames` steps against a sensed hero position (kept FAR along the action's
// heading so its AI holds the forced state and the coil/gape/head-track re-aim doesn't fight the
// framing), no blade. Generic over the foe contract — one loop for toads, archers and the ogre.
fn stepFoe(f: anytype, frames: i32, hero: rl.Vector3) void {
    var k: i32 = 0;
    while (k < frames) : (k += 1) _ = f.update(SHOT_DT, hero, PLAY_HALF, .{});
}

// Plant the hero at a world spot facing `faceYaw`, settled and posed. The WORLD TOUR shots
// below all start here — and they must, because the sun's shadow ortho box tracks the hero, so
// a landscape framed far from him comes back with no cast shadows in it at all.
fn standHero(g: *Game, x: f32, z: f32, faceYaw: f32) void {
    g.hero.pos = mathx.ground(x, z);
    g.hero.facing = faceYaw;
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
}

// Frame an arbitrary world point and shoot it — the landscape counterpart of shootFoe.
fn shootAt(g: *Game, name: [:0]const u8, at: rl.Vector3, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.follow(at);
    shoot(g, name);
}

// Frame ANY foe on its body-mass centre and shoot it. Generic for the same reason as stepFoe —
// the toad / archer / ogre versions of this were byte-identical bar the parameter type. (The ogre
// just wants a bigger `dist`: it's ~2x the hero.)
fn shootFoe(g: *Game, f: anytype, name: [:0]const u8, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.follow(f.centerWorld());
    shoot(g, name);
}

fn runShots(g: *Game) void {
    std.fs.cwd().makePath("shots") catch {};
    const dt: f32 = SHOT_DT;
    // Shots 1-9 judge geometry/animation — run CLEAN of the default filter stack; the filter
    // shots below set their own explicit stacks.
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

    // Locked-on footing: facing HOLDS on −Z while travel goes sideways/backward — the strafe
    // sidestep from the front and the backpedal in side profile. Each capture SEEKS its
    // stride phase (a fixed frame count lands on dead phases).
    const lockedStages = [_]struct { name: [:0]const u8, yaw: f32, pitch: f32, dist: f32, phTgt: f32, dx: f32, dz: f32 }{
        // The strafe cycle, ONE SHOT PER BEAT of the grapevine (strafing his RIGHT, so the LEFT
        // leg is the one that crosses). Each leg plants at its own phase 0 — the left at ph 0, the
        // right at ph 0.5 — and stays down for hero.STRAFE_STANCE of the cycle, so the beats are:
        //   ph .50  right foot lands WIDE      ph .81  left leg airborne, crossing IN FRONT
        //   ph .02  left foot lands ACROSS     ph .31  right leg airborne, passing BEHIND
        // Retarget these together with STRAFE_STANCE — they are that constant's beats, not free knobs.
        .{ .name = "shots/38a_strafe_stepout.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.50, .dx = 1, .dz = 0 }, // the out-step LANDS: right foot wide, widest straddle
        .{ .name = "shots/38b_strafe_apart.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.57, .dx = 1, .dz = 0 }, // double support, planted APART, weight transferring
        .{ .name = "shots/38c_strafe_crossing.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.81, .dx = 1, .dz = 0 }, // LEFT leg airborne mid-CROSS: hip flexed, knee up, passing in FRONT
        .{ .name = "shots/38d_strafe_crossed.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.02, .dx = 1, .dz = 0 }, // CROSSED: left foot planted PAST the right — the X
        .{ .name = "shots/38e_strafe_uncross.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.31, .dx = 1, .dz = 0 }, // the UNCROSS: right leg airborne, passing BEHIND the crossed leg
        .{ .name = "shots/38f_strafe_crossed_3q.png", .yaw = 40, .pitch = 0.13, .dist = 4.2, .phTgt = 0.02, .dx = 1, .dz = 0 }, // the X again from three-quarters — the cross must read off-axis too
        .{ .name = "shots/38g_strafe_crossing_3q.png", .yaw = 40, .pitch = 0.13, .dist = 4.2, .phTgt = 0.81, .dx = 1, .dz = 0 }, // …and the front-pass, where a behind-pass would look identical head-on
        .{ .name = "shots/39a_backpedal_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .phTgt = 0.05, .dx = 0, .dz = 1 }, // backpedal: the toe-reach plant
        .{ .name = "shots/39b_backpedal_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .phTgt = 0.55, .dx = 0, .dz = 1 }, // …the counter-step
    };
    for (lockedStages) |st| {
        g.rig.yaw = mathx.radians(st.yaw);
        g.rig.pitch = st.pitch;
        g.rig.dist = st.dist;
        var k: i32 = 0;
        while (k < 14) : (k += 1) stepLocked(g, dt, WALK_SPEED, v3(st.dx, 0, st.dz), std.math.pi); // settle the direction blends
        var seek: i32 = 0;
        while (seek < 90) : (seek += 1) {
            const d = @abs(g.hero.phase - st.phTgt);
            if (@min(d, 1.0 - d) < 0.022) break;
            stepLocked(g, dt, WALK_SPEED, v3(st.dx, 0, st.dz), std.math.pi);
        }
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

    // Sword swings: light slash from the SWORD side (right profile — left hides the windup
    // behind the torso), heavy from the left in silhouette (an overhead is sagittal) at
    // windup apex + buried impact, then heavy again with the hit capsule visible (menu >
    // Debug > Hitboxes) to verify it rides the blade.
    g.hero.pos = mathx.ground(0, 4);
    g.rig.yaw = mathx.radians(30); // front 3/4 — the hero faces -Z, so this shows the sword-arm arc (270 hid it behind the torso)
    g.rig.pitch = 0.13;
    g.rig.dist = 4.2;
    g.hero.startAttack(.light);
    advanceAttack(g, dt, 10); // ~u 0.28: windup apex — fist at shoulder height, blade LEVEL back over the shoulder
    shoot(g, "shots/15a_atk_light_wind.png");
    advanceAttack(g, dt, 5); // ~u 0.42: mid-arc — blade horizontal, tip OUTWARD, sweeping across
    shoot(g, "shots/15_atk_light_strike.png");
    advanceAttack(g, dt, 4); // ~u 0.53: the whip PEAK — wrist fired, blade level through contact
    shoot(g, "shots/15p_atk_light_peak.png");
    advanceAttack(g, dt, 3); // ~u 0.61: follow-through — blade carried across past the OFF shoulder, still level
    shoot(g, "shots/15b_atk_light_thru.png");
    g.hero.requestAttack(.light); // buffered past the chain knot → the ALTERNATE backhand
    advanceAttack(g, dt, 12); // chain fires at ~u 0.80, then into the backhand WINDUP (the chamber)
    shoot(g, "shots/15r_atk_return_wind.png"); // verify the return chamber clears the torso (no arm buried in the chest)
    advanceAttack(g, dt, 10); // ~u 0.42 into the return swipe
    shoot(g, "shots/15c_atk_light_return.png");
    advanceAttack(g, dt, 999); // run the combo out
    // TOP-DOWN — the SLASH must sweep a clean horizontal ARC across the hero's FRONT (a
    // swipe, not a downward poke); the swing-trail ribbon reads the arc from above.
    g.rig.yaw = mathx.radians(0);
    g.rig.pitch = 1.48; // near-straight-down (follow() doesn't clamp pitch like the live paths)
    g.rig.dist = 6.5;
    g.hero.startAttack(.light);
    advanceAttack(g, dt, 17); // ~u 0.47, deep in the active window — the trail fan painted across the front
    shoot(g, "shots/15t_atk_light_top.png");
    advanceAttack(g, dt, 999);
    g.rig.pitch = 0.13;
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
        const f = &g.warren.frogs[0];
        // Hero stands a couple metres off — a scale reference that also keeps the toad inside
        // the sun's shadow ortho box (which tracks the hero).
        g.hero.pos = mathx.ground(2.0, 0.9);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z); // face the toad at origin
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();

        const behind = mathx.ground(0, -60); // "hero" down the hop heading (−Z): coil re-aim ≈ heading
        const front = mathx.ground(0, 60); // "hero" out front (+Z): idle/gape keep facing the camera side

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z; profiled from the side
        stepFoe(f, 8, front); // settle to idle (far → won't wake)
        shootFoe(g, f, "shots/20_frog_idle.png", 90, 0.10, 2.7);
        shootFoe(g, f, "shots/21_frog_scale.png", 35, 0.16, 4.7); // with the hero, for size read

        // A hop: coil → leap → land (side profile shows the arc + squash/stretch).
        // Hops LAUNCH ALONG THE BODY now (max turn speed), so spawn facing the heading.
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -2.2), PLAY_HALF, false);
        stepFoe(f, 6, behind); // mid coil (loaded, knees stacked)
        shootFoe(g, f, "shots/22_frog_coil.png", 90, 0.08, 3.0);
        stepFoe(f, 22, behind); // arc apex (stretched, airborne)
        shootFoe(g, f, "shots/23_frog_leap.png", 90, 0.05, 3.4);
        stepFoe(f, 22, behind); // landing splat
        shootFoe(g, f, "shots/24_frog_land.png", 90, 0.09, 3.1);

        // A lunge into its recovery (the wide-open window).
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -3.6), PLAY_HALF, true);
        stepFoe(f, 26, behind); // deep into the long telegraph coil (loaded, dust flying, throat charged)
        shootFoe(g, f, "shots/25_frog_lunge_wind.png", 55, 0.09, 3.3);
        stepFoe(f, 60, behind); // through flight + heavy landing, ~0.3 s into recovery
        shootFoe(g, f, "shots/26_frog_recover.png", 70, 0.13, 3.2);

        // A chomp: gape (sac balloons, jaws yawn) → snap. Framed front-quarter to see the maw.
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.startChomp();
        stepFoe(f, 22, front); // near full gape (charge gathering, drool stringing)
        shootFoe(g, f, "shots/27_frog_gape.png", 162, 0.06, 2.2); // front 3/4, close — peer into the maw
        stepFoe(f, 6, front); // jaws slamming
        shootFoe(g, f, "shots/28_frog_snap.png", 162, 0.06, 2.2);

        // A TRACKED hit: the swept blade capsule meets the hurt sphere and the counter ticks
        // (Debug > Hitboxes draws both; Stats shows "frog hits N"). Detection only, no
        // consequence yet.
        g.menu.hitboxes = true;
        g.menu.stats = true;
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        g.hero.pos = mathx.ground(0, 0.85);
        g.hero.facing = std.math.pi; // face -Z, toward the toad at the origin
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.hero.startAttack(.light);
        var hk: i32 = 0;
        while (hk < 999 and g.hero.attacking) : (hk += 1) {
            g.hero.updateAttack(dt, PLAY_HALF, null);
            _ = f.update(dt, mathx.ground(0, 60), PLAY_HALF, heroBlade(g));
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
        stepFoe(f, 8, front);
        g.hero.pos = mathx.ground(1.7, 3.6);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.lock = .{ .kind = .toad, .idx = 0 };
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
        stepFoe(f, 13, front); // flinch PEAK (reared back and up off the blow)
        shootFoe(g, f, "shots/31_frog_flinch.png", 70, 0.12, 3.2);
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.debugStagger(true);
        stepFoe(f, 24, front); // deep in the crumple — splayed, wide open
        shootFoe(g, f, "shots/32_frog_stagger.png", 55, 0.12, 3.4);
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.debugKill();
        stepFoe(f, 42, front); // collapsed
        shootFoe(g, f, "shots/33_frog_death.png", 60, 0.10, 3.4);

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
        stepFoe(f, 4, front);
        g.hero.pos = mathx.ground(2.4, 4.2);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.rig.yaw = mathx.radians(202);
        g.rig.pitch = 0.16;
        g.rig.dist = 6.4;
        g.rig.follow(f.centerWorld());
        shoot(g, "shots/37_hp_bars.png");
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // reset the slot
    }

    // ── the skeletal archer: the bare-bones rig driven to a full-draw aim ──────────────────
    {
        g.warren.frogs[0] = frogmod.Frog.spawn(mathx.ground(0, 60), 0, 1.0, 0.0); // shoo the origin toad out of the archer portraits
        const a = &g.line.archers[0];
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
        // A "hero" in-band ahead (+Z) so the archer decides to shoot and pulls to full draw
        // naturally; stop at the hold (full draw) for the portrait.
        g.hero.pos = mathx.ground(3.0, 2.5); // near enough to keep the shadow ortho box over the archer
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        var k: i32 = 0;
        while (k < 140 and a.drawAmt < 0.98) : (k += 1) _ = a.update(dt, mathx.ground(0, 12), PLAY_HALF, .{});
        shootFoe(g, a, "shots/40_archer_aim_side.png", 90, 0.06, 4.8); // profile: draw arm folded back, bow arm out
        shootFoe(g, a, "shots/41_archer_aim_front.png", 6, 0.12, 4.4); // front: skull + ribcage + the aim
        shootFoe(g, a, "shots/42_archer_aim_3q.png", 48, 0.10, 4.8); // three-quarter
        // An arrow leaving the bow: loose from the nock toward a target ahead and step it into
        // its arc, parked in the pool so drawArrows renders the oriented, arcing shaft.
        g.arrows[0] = archermod.launchArrow(a.nockWorld(), mathx.ground(0, 15));
        var m: i32 = 0;
        while (m < 8) : (m += 1) archermod.stepArrow(&g.arrows[0], mathx.ground(0, 15), HERO_CENTER_Y, false, arrowCover(g, &g.arrows[0], dt), dt);
        shootFoe(g, a, "shots/44_archer_loose.png", 90, 0.05, 5.2); // side-on: the shaft crosses the frame
        g.arrows[0] = .{};
        // A lowered/idle read too, to check the skeleton stands cleanly with the bow at rest.
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var j: i32 = 0;
        while (j < 20) : (j += 1) _ = a.update(dt, mathx.ground(0, 60), PLAY_HALF, .{}); // hero far → stays idle
        shootFoe(g, a, "shots/43_archer_idle_side.png", 90, 0.08, 4.6);
        // The SHARED walk/strafe (hero.legChain): crowd it so it kites, catch it mid-backpedal.
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var w2: i32 = 0;
        while (w2 < 60) : (w2 += 1) _ = a.update(dt, mathx.ground(0, 3), PLAY_HALF, .{}); // hero crowds → back off
        shootFoe(g, a, "shots/45_archer_kite.png", 90, 0.09, 5.4);
        // THE BACKSTEP: crowd it inside sword reach to trigger the panic leap, then catch the
        // apex and the landing absorb. Side-on — from the front you cannot see it leave the
        // ground.
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var bs: i32 = 0;
        while (bs < 400 and !a.airborne()) : (bs += 1) _ = a.update(dt, mathx.ground(0, 2.2), PLAY_HALF, .{});
        var bp: i32 = 0;
        while (bp < 7) : (bp += 1) _ = a.update(dt, mathx.ground(0, 2.2), PLAY_HALF, .{}); // …on to the apex
        shootFoe(g, a, "shots/45b_archer_backstep.png", 90, 0.06, 6.0);
        var bl: i32 = 0;
        while (bl < 18) : (bl += 1) _ = a.update(dt, mathx.ground(0, 2.2), PLAY_HALF, .{});
        shootFoe(g, a, "shots/45c_archer_backstep_land.png", 90, 0.06, 6.0);
        // Lock-on onto a SKELETON — the reticle rides ANY foe now (FoeRef over both groups).
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var lk: i32 = 0;
        while (lk < 24) : (lk += 1) _ = a.update(dt, mathx.ground(0, 60), PLAY_HALF, .{}); // settle to idle
        g.hero.pos = mathx.ground(1.8, 6.0);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.lock = .{ .kind = .archer, .idx = 0 };
        g.rig.yaw = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.rig.pitch = 0.16;
        g.rig.dist = 6.2;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/46_archer_lockon.png");
        g.lock = null;
        // Restore both foes near their homes so they don't intrude on the retro/menu shots below.
        a.* = archermod.Archer.spawn(mathx.ground(-16.0, -22.0), mathx.radians(60), 1.0, 0.2);
        g.warren.frogs[0] = frogmod.Frog.spawn(mathx.ground(13.5, -14.0), mathx.radians(215), 1.08, 0.0);
    }

    // ── the one-eyed ogre: scale, the overhead-slam beats, and the reactions ────────────────
    // Framed out on the OPEN plain north-east of the start (oc), clear of the x≈0 colonnade so
    // the columns don't block the giant. `far` keeps its AI holding the forced state (facing +Z).
    {
        const o = &g.grief.ogres[0];
        const oc = mathx.ground(24.0, 30.0); // portrait spot — open ground, off the ruins
        const far = v3(oc.x, 0, oc.z + 80.0); // sensed hero far ahead → holds state, faces +Z

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 54, far); // settle into idle, landing mid weight-shift (one leg relaxed)
        // Idle — a CLEAN standing read (hero shoved out of frame), pitched down a touch to see
        // the full stooped-but-towering silhouette and the legs on the ground.
        g.hero.pos = mathx.ground(oc.x - 22.0, oc.z);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootFoe(g, o, "shots/47_ogre_idle.png", 55, 0.14, 13.0);
        // Scale — the hero standing clearly to the ogre's side (it looms ~1.9x over him).
        g.hero.pos = mathx.ground(oc.x + 4.8, oc.z + 1.4);
        g.hero.facing = std.math.atan2(oc.x - g.hero.pos.x, oc.z - g.hero.pos.z); // face the ogre
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootFoe(g, o, "shots/48_ogre_scale.png", 30, 0.16, 15.5);
        // The approach — the shared gait, side-on, to judge the LUMBER (trunk roll + swagger +
        // footfall catch) and the ARM SWING. Sensed hero sits inside aggro dead ahead. Sampled at
        // THREE points a quarter-stride apart (the ogre's cycle is ~138 frames): one frame can't
        // show a swing, and a gait that only reads at one phase isn't a gait.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 100, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/56_ogre_walk.png", 90, 0.06, 12.0);
        // …and b/c from yaw 270 — the OFF profile. Yaw 90 puts the club arm nearest the camera and
        // buries the free arm behind the barrel, so the big contralateral swing is invisible from
        // it: judging the swing off that side is judging an arm you cannot see. Half a stride
        // apart, so between them the free arm is caught at BOTH extremes of its swing.
        stepFoe(o, 34, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/57_ogre_walk_b.png", 270, 0.06, 12.0);
        stepFoe(o, 69, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/58_ogre_walk_c.png", 270, 0.06, 12.0);
        stepFoe(o, 17, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/59_ogre_walk_3q.png", 320, 0.08, 12.5); // front-left 3/4: free arm, lit
        // THE HEAD CRANE — the sensed hero sits hard off his LEFT while his body still points +Z,
        // so the eye is craned to the neck's limit a beat before the slow body can follow. Shot
        // from behind-ish (yaw 20) where the head being turned off the shoulder line reads.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 14, v3(oc.x + 9.0, 0, oc.z + 1.0)); // 14 frames: the head is AT its 55 deg
        //   clamp while the ponderous body has only come round ~30 — any later and the body has
        //   caught up and there is no lead left to see.
        shootFoe(g, o, "shots/60_ogre_headtrack.png", 20, 0.20, 11.0);

        // Face close-up — the single eye + heavy sad brow. Ogre faces +Z, so FRONT is yaw ~180
        // (like the toad maw shots); look slightly DOWN onto the brow. RESPAWNED to a settled
        // IDLE first: taken off the WALKING ogre above, this framed the swinging club head
        // instead of the face — a portrait has no business being shot mid-stride.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 30, far);
        g.rig.yaw = mathx.radians(182);
        g.rig.pitch = 0.16;
        g.rig.dist = 3.2;
        g.rig.follow(o.headWorld());
        shoot(g, "shots/55_ogre_face.png");

        // The overhead slam: windup (club reared high) → crash (impact dust) → spent recovery.
        // FRAME COUNTS ARE DERIVED FROM THE STATE MACHINE, not eyeballed — a shot that lands in the
        // windup while calling itself the slam means the swing is being judged from a frame that does
        // not contain it (AGENTS.md: framing is part of the test). debugSlam enters .windup at t=0, so
        // at 1/60: windup ends / slam begins at 72, the club meets the earth at 84, slam ends at 86.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugSlam();
        stepFoe(o, 64, far); // f64: deep in the loaded peak HOLD — club overhead, arched back, trembling
        shootFoe(g, o, "shots/49_ogre_windup.png", 55, 0.00, 13.0);
        stepFoe(o, 21, far); // f85: one frame past IMPACT — club at the crater, the dust burst still tight
        shootFoe(g, o, "shots/50_ogre_slam.png", 60, 0.06, 13.0);
        stepFoe(o, 25, far); // f110: ~0.4 s into recovery — doubled over the buried club, wide open
        shootFoe(g, o, "shots/51_ogre_recover.png", 48, 0.10, 12.5);

        // The SIDE SWIPE — his fast answer to a hero who won't stand in front of him. The sensed
        // hero sits round on his LEFT FLANK (that bearing is exactly what makes him choose the
        // swipe), so these frames also show the PIVOT: he is still coming round as the club goes.
        // Two ground-level frames for the pose + one steep top-down, which is the only angle a
        // HORIZONTAL arc actually reads from.
        {
            // Derived like the slam's, off debugSwipe entering .swipewind at t=0: at 1/60 the
            // cock-back ends / the sweep begins at frame 28, the club crosses his centre line
            // (impact) at 34, and the sweep ends at 40.
            const flank = v3(oc.x + 3.6, 0, oc.z - 1.2); // ~108 deg off his facing, inside SWIPE_R
            o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
            o.debugSwipe();
            stepFoe(o, 24, flank); // f24: the top of the short cock-back — coiled, snarling
            shootFoe(g, o, "shots/61_ogre_swipewind.png", 35, 0.12, 12.0);
            stepFoe(o, 11, flank); // f35: one frame past IMPACT — the club crossing his centre line
            shootFoe(g, o, "shots/62_ogre_swipe.png", 35, 0.12, 12.0);
            shootFoe(g, o, "shots/63_ogre_swipe_top.png", 35, 0.60, 15.0); // same frame, from above
        }

        // Reactions: the rare light flinch, the heavy stance-break, the weighty death topple.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugStagger(false);
        stepFoe(o, 13, far); // flinch peak (recoiled back, arm flung up)
        shootFoe(g, o, "shots/52_ogre_flinch.png", 55, 0.04, 12.5);
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugStagger(true);
        stepFoe(o, 42, far); // deep in the stance-break — sagged onto a knee, wide open
        shootFoe(g, o, "shots/53_ogre_stagger.png", 50, 0.10, 13.0);
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugKill();
        stepFoe(o, 72, far); // the slow topple, well into the collapse
        shootFoe(g, o, "shots/54_ogre_death.png", 55, 0.12, 13.5);

        // Restore it to its home deep in the ruins so it doesn't loom over the retro/menu shots.
        o.* = ogremod.Ogre.spawn(mathx.ground(3.0, -50.0), 0, 1.0, 0.4);
    }

    // ── THE WORLD TOUR ── one capture per region, plus the interiors that only exist because
    // the scene shader grew point lights. These are the shots that verify the EXPANSION: that
    // each direction reads as its own place, that the culling isn't eating geometry, that the
    // torches light a roofed room, and that the tarn reads as water.
    {
        // The avenue from the start, looking north up the processional way into the city.
        standHero(g, 0, 12, std.math.pi);
        shootAt(g, "shots/70_avenue_north.png", g.hero.shoulderPoint(), 180, 0.16, 9.0);
        // A high, wide vista north — the whole depth of the world in one frame: avenue, plaza,
        // city wall, the colossal gate, and the cliffs behind it dissolving into haze.
        shootAt(g, "shots/71_vista_north.png", mathx.ground(0, 6), 180, 0.30, 9.0);

        // THE FALLEN CITY: the plaza, then the chapel from the road, then INSIDE it.
        standHero(g, 2.0, -66.0, std.math.pi);
        shootAt(g, "shots/72_city_plaza.png", mathx.ground(0, -74), 180, 0.26, 9.0);
        // The chapel sits at (-30, -66) turned to yaw 270, which maps its local +Z (the altar
        // end) to world −X and its doorway to world +X: the nave runs along X from -33.6 (altar)
        // to -26.4 (door). All three framings below are DERIVED from that, not guessed — the
        // first pass guessed the mapping and shot the outside of a wall.
        standHero(g, -22.0, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/73_chapel_outside.png", mathx.ground(-30, -66), 270, 0.22, 17.0);
        // Looking WEST down the nave from the doorway: the roofed altar end gets NO sun, so what
        // you can see of it is the standing torches — the whole reason gfx grew point lights.
        // The camera has to end up AT the doorway (x ≈ -26.4), so target + dist must land there;
        // aiming deeper buries it in the altar, which is what the first two attempts did.
        standHero(g, -29.6, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/74_chapel_torchlit.png", v3(-30.7, 1.4, -66.0), 270, 0.05, 4.4);
        // …and closer on the altar itself, still outside its 1.25 m half-depth.
        standHero(g, -30.6, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/75_chapel_altar.png", v3(-32.6, 1.0, -66.0), 270, 0.10, 4.8);

        // A watchtower: the drum with its door brazier, then the dark room inside it. Placed at
        // yaw 20, so its local −Z doorway faces world (−sin20, −cos20) ≈ (−0.34, −0.94): out to
        // the south-west. The camera has to sit on THAT side or the shot is just a wall of blocks:
        // `back` is (−sin yaw, ·, −cos yaw), so yaw 20 is the bearing that puts the eye out in front
        // of the door. (This was yaw 168 — the opposite side — and only ever looked like a doorway
        // because towerDoorway's arithmetic was opening the drum on +Z instead of −Z.)
        standHero(g, 34.0, -95.0, mathx.radians(20));
        shootAt(g, "shots/76_watchtower.png", mathx.ground(36, -88), 20, 0.16, 27.0);
        // Inside the drum: the camera must sit within the 2.35 m wall radius, so target the
        // middle and keep dist under it or the eye ends up embedded in masonry.
        standHero(g, 36.4, -88.4, 0);
        shootAt(g, "shots/77_watchtower_inside.png", v3(35.7, 1.7, -87.6), 200, 0.06, 2.0);

        // THE TARN. gfx.SUN_DIR points (−0.60, +0.50, −0.46) from the surface TOWARD the sun, so
        // the sun is low in the WEST: the glitter path only exists looking WEST across the water.
        // Standing on the west shore looking east (the first framing) is the one angle guaranteed
        // to show none of it.
        standHero(g, 130.0, 14.0, -std.math.pi * 0.5);
        shootAt(g, "shots/78_tarn.png", mathx.ground(122, 12), 268, 0.10, 13.0);
        standHero(g, 70.0, 8.0, std.math.pi * 0.5);
        shootAt(g, "shots/79_tarn_causeway.png", mathx.ground(78, 8), 100, 0.18, 12.0);

        // THE OLD WOOD: under the canopy, then one great tree whole (for judging the model),
        // then the stone circle and the woodcutter's cottage with its fire.
        standHero(g, -84.0, 4.0, -std.math.pi * 0.5);
        shootAt(g, "shots/80_wood.png", mathx.ground(-90, 4), 260, 0.12, 11.0);
        shootAt(g, "shots/81_bigtree.png", v3(-90.0, 5.0, 6.0), 300, -0.10, 17.0);
        standHero(g, -90.0, -16.0, -std.math.pi * 0.5);
        shootAt(g, "shots/82_stone_circle.png", mathx.ground(-98, -16), 265, 0.14, 15.0);
        standHero(g, -66.0, 30.0, -std.math.pi * 0.5);
        shootAt(g, "shots/83_cottage.png", mathx.ground(-72, 30), 258, 0.10, 12.0);

        // THE DOWNS: open and sparse, with the tower on the rise.
        standHero(g, 22.0, 82.0, 0);
        shootAt(g, "shots/84_downs.png", mathx.ground(22, 92), 8, 0.14, 14.0);

        // THE EDGE: the cliff wall that the movement clamp now hides behind. Pitch must stay
        // POSITIVE — at -0.05 with dist 15 the camera drops below y=0 and the shot is half
        // underside-of-terrain (a mis-framed capture, not a broken cliff).
        standHero(g, 40.0, 140.0, 0);
        shootAt(g, "shots/85_cliffs.png", mathx.ground(40, 152), 4, 0.22, 22.0);
        // …and a long raking view ALONG the wall, which is the angle that shows whether it reads
        // as one escarpment or as a row of separate rocks.
        standHero(g, 10.0, 150.0, std.math.pi * 0.5);
        shootAt(g, "shots/85b_cliffs_along.png", mathx.ground(30, 158), 80, 0.16, 26.0);

        // MAP SHOTS — one steep overhead per region. Ground-level framings are what you judge
        // a MODEL from, but they cannot show you layout, spacing or relative SCALE, which is
        // where a procedurally-placed region actually goes wrong.
        // Distances kept near 55: the haze is deliberately thick, and a camera 85 m up looks at
        // everything THROUGH 85 m of it, so a higher map shot grades its own subject into murk.
        const maps = [_]struct { name: [:0]const u8, x: f32, z: f32, dist: f32 }{
            .{ .name = "shots/86_map_city.png", .x = 0, .z = -80, .dist = 58 },
            .{ .name = "shots/87_map_tarn.png", .x = 92, .z = 8, .dist = 58 },
            .{ .name = "shots/88_map_wood.png", .x = -92, .z = 6, .dist = 55 },
            .{ .name = "shots/89_map_downs.png", .x = 20, .z = 92, .dist = 58 },
            .{ .name = "shots/90_map_start.png", .x = 0, .z = 0, .dist = 52 },
        };
        for (maps) |m| {
            standHero(g, m.x, m.z, std.math.pi);
            shootAt(g, m.name, mathx.ground(m.x, m.z), 180, 1.02, m.dist);
        }

        // PERF READOUT — the debug Stats overlay from ground level in the two busiest places, so
        // the culling numbers are captured, not assumed. Read the "world" line: props in the
        // world vs draws issued this frame across BOTH passes.
        g.menu.stats = true;
        standHero(g, 2.0, -72.0, std.math.pi);
        shootAt(g, "shots/91_stats_city.png", g.hero.shoulderPoint(), 180, 0.22, 8.0);
        standHero(g, -88.0, 8.0, -std.math.pi * 0.5);
        shootAt(g, "shots/92_stats_wood.png", g.hero.shoulderPoint(), 265, 0.20, 8.0);
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
