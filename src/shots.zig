const std = @import("std");
const rl = @import("raylib");

const game = @import("game.zig");
const combat = @import("combat.zig");
const gfx = @import("gfx.zig");
const editormod = @import("editor.zig");
const heromod = @import("hero.zig");
const frogmod = @import("frog.zig");
const archermod = @import("archer.zig");
const ogremod = @import("ogre.zig");
const koboldmod = @import("kobold.zig");
const mathx = @import("mathx.zig");
const objview = @import("objview.zig");
const props = @import("props.zig");
const worldfmt = @import("worldfmt.zig");

const Game = game.Game;
const v3 = mathx.v3;

// What the harness drives in game.zig.
const drawScene = game.drawScene;
const hud = game.hud;
const heroBlade = game.heroBlade;
const HERO_CENTER_Y = game.HERO_CENTER_Y;
const arrowCover = game.arrowCover;
const WALK_SPEED = heromod.WALK_SPEED;
const RUN_SPEED = heromod.RUN_SPEED;
const SPRINT_SPEED = heromod.SPRINT_SPEED;

pub const SHOT_DT: f32 = 1.0 / 60.0;
// Walk the hero along a FIXED world direction (−Z, into the ruins) and shoot it from several true camera angles + stride phases into shots/ (window hidden).
fn stepWorld(g: *Game, dt: f32, speed: f32) void {
    const moved = speed * dt;
    g.hero.pos.z = mathx.clampF(g.hero.pos.z - moved, -game.PLAY_HALF, game.PLAY_HALF); // travel −Z
    g.hero.facing = std.math.pi; // face −Z (no turning)
    g.hero.update(dt, moved, speed, if (moved > 0) std.math.pi else null);
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
}

// Locked-on counterpart of stepWorld: travel a world direction while FACING holds on a target heading — the strafe / backpedal gaits, framed like the walk stages.
fn stepLocked(g: *Game, dt: f32, speed: f32, dir: rl.Vector3, faceYaw: f32) void {
    const moved = speed * dt;
    g.hero.pos.x = mathx.clampF(g.hero.pos.x + dir.x * moved, -game.PLAY_HALF, game.PLAY_HALF);
    g.hero.pos.z = mathx.clampF(g.hero.pos.z + dir.z * moved, -game.PLAY_HALF, game.PLAY_HALF);
    g.hero.facing = faceYaw;
    g.hero.update(dt, moved, speed, mathx.headingXZ(dir));
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
}

/// CAPTURE THE FRAME THAT WAS JUST DRAWN — and the order here is the whole point. **THE SCREENSHOT MUST HAPPEN BEFORE `endDrawing`.** `endDrawing` SWAPS the buffers, and `takeScreenshot` reads the CURRENT framebuffer — so taken after the swap it reads the buffer that was just swapped in, which holds the PREVIOUS frame.
fn snap(name: [:0]const u8) void {
    rl.gl.rlDrawRenderBatchActive();
    rl.takeScreenshot(name);
    rl.endDrawing();
}

// Render the current world + HUD and write one screenshot.
fn shoot(g: *Game, name: [:0]const u8) void {
    drawScene(g);
    hud(g, SHOT_DT); // the fixed harness timestep — the HP chip trail stays reproducible
    snap(name);
}

// Advance an in-progress attack up to `frames` frames (stopping early when it ends), keeping the camera following — the attack-shot counterpart of the roll-stage loop.
fn advanceAttack(g: *Game, dt: f32, frames: i32) void {
    var k: i32 = 0;
    while (k < frames and g.hero.attacking) : (k += 1) {
        g.hero.updateAttack(dt, game.PLAY_HALF, null);
        g.rig.follow(g.hero.shoulderPoint());
    }
}

// Advance ANY foe `frames` steps against a sensed hero position (kept FAR along the action's heading so its AI holds the forced state and the coil/gape/head-track re-aim doesn't fight the framing), no blade.
fn stepFoe(f: anytype, frames: i32, hero: rl.Vector3) void {
    var k: i32 = 0;
    while (k < frames) : (k += 1) _ = f.update(SHOT_DT, hero, game.PLAY_HALF, .{});
}

/// THE CAMERA YAW WITH THE SUN BEHIND IT — `gfx.SUN_DIR` in the rig's terms, so ~233 shoots into it.
pub const LIT_YAW: f32 = 53.0;
pub const LIT_BACK = v3(-0.794, 0, -0.608);

// Plant the hero at a world spot facing `faceYaw`, settled and posed.
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

/// A PORTRAIT — `at` DEAD CENTRE, which no other helper here does.
fn shootPortrait(g: *Game, name: [:0]const u8, at: rl.Vector3, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.followCentred(at);
    shoot(g, name);
}

/// Frame the hero the way the LIVE camera does — through `followClear`, so the boom shortens instead of ending up inside a hillside.
fn shootClear(g: *Game, name: [:0]const u8, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.followClear(g.hero.shoulderPoint(), &g.env, game.envGroundAt);
    shoot(g, name);
}

// Frame ANY foe on its body-mass centre and shoot it.
fn shootFoe(g: *Game, f: anytype, name: [:0]const u8, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.follow(f.centerWorld());
    shoot(g, name);
}

// The harness photographs ANIMATIONS, not the stamina economy, so it tops the pool up before every action it stages.
fn stagedAttack(g: *Game, kind: heromod.Attack) void {
    g.hero.stam.reset();
    g.hero.startAttack(kind);
}

fn stagedRoll(g: *Game, dir: rl.Vector3) void {
    g.hero.stam.reset();
    g.hero.startRoll(dir);
}

// The world tour judges REGIONS; retuning one MODEL needs the model by itself.
pub fn runPropShots(g: *Game) void {
    std.fs.cwd().makePath("shots/props") catch {};
    g.menu.screen = .closed;
    g.retro.allOff();
    // No foes in the portraits — a toad idling into a wide framing reads as part of the model.
    g.warren.n = 0;
    g.line.n = 0;
    g.grief.n = 0;
    for (props.INFO, 0..) |row, i| {
        g.env.stageOne(row.kind);
        const r = mathx.maxF(row.bound, 0.9);
        standHero(g, -(r + 1.1), 0.35 * r + 0.9, mathx.radians(115));
        const aim = v3(0, mathx.clampF(row.top * 0.45, 0.4, 9.0), 0);
        const dist = mathx.clampF(mathx.maxF(r * 2.1, row.top * 1.7), 3.2, 60.0);
        var buf: [96]u8 = undefined;
        const name = std.fmt.bufPrintZ(&buf, "shots/props/{d:0>2}_{s}.png", .{ i, @tagName(row.kind) }) catch unreachable;
        shootAt(g, name, aim, 35, 0.30, dist);
    }
}

pub fn runShots(g: *Game) void {
    std.fs.cwd().makePath("shots") catch {};
    // The foe portraits pose group member [0] directly, and the groups are sized by the MAP now — so a map that posts no toads used to read undefined memory here.
    if (g.warren.n == 0 or g.line.n == 0 or g.grief.n == 0) {
        std.debug.print(
            "--shot needs at least one of each foe in {s} (have {d} toads, {d} archers, {d} ogres)\n",
            .{ worldfmt.START_MAP, g.warren.n, g.line.n, g.grief.n },
        );
        @panic("shot harness: the map posts no foes to photograph");
    }
    const dt: f32 = SHOT_DT;
    // The menu OPENS AT LAUNCH, and the HUD hides behind it (ER does the same) — so the harness has to close it or every capture is of a game sitting in its pause screen.
    g.menu.screen = .closed;
    // Shots 1-9 judge geometry/animation — run CLEAN of the default filter stack; the filter shots below set their own explicit stacks.
    g.retro.allOff();

    g.hero.pos = mathx.ground(0, 26); // long runway of −Z travel ahead
    var i: i32 = 0;
    while (i < 40) : (i += 1) stepWorld(g, dt, WALK_SPEED); // warm up: moving→1, phase settles

    // (name, yaw°, pitch, dist, frames before the shot, speed). yaw 90 = profile (best for gait), 0 = front, 180 = back, 45 = three-quarter.
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

    // Locked-on footing: facing HOLDS on −Z while travel goes sideways/backward — the strafe sidestep from the front and the backpedal in side profile.
    const lockedStages = [_]struct { name: [:0]const u8, yaw: f32, pitch: f32, dist: f32, phTgt: f32, dx: f32, dz: f32 }{
        // The strafe cycle, ONE SHOT PER BEAT of the grapevine (strafing his RIGHT, so the LEFT leg is the one that crosses).
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
    stagedRoll(g, v3(0, 0, -1));
    const rollStages = [_]struct { name: [:0]const u8, adv: i32 }{
        .{ .name = "shots/7_roll_tuck.png", .adv = 6 }, // ~u 0.14 (dive: balled + banked, spin barely begun)
        .{ .name = "shots/8_roll_over.png", .adv = 8 }, // ~u 0.33 (front-loaded tumble — inverted)
        .{ .name = "shots/9_roll_recover.png", .adv = 19 }, // ~u 0.79 (spin landed — planting, rising, off-square)
    };
    for (rollStages) |st| {
        var k: i32 = 0;
        while (k < st.adv) : (k += 1) {
            if (g.hero.rolling) g.hero.updateRoll(dt, game.PLAY_HALF) else stepWorld(g, dt, WALK_SPEED);
            g.rig.follow(g.hero.shoulderPoint());
        }
        shoot(g, st.name);
    }

    // Run the roll OUT first — startAttack is (rightly) ignored while rolling.
    while (g.hero.rolling) {
        g.hero.updateRoll(dt, game.PLAY_HALF);
        g.rig.follow(g.hero.shoulderPoint());
    }

    // Sword swings: light slash from the SWORD side (right profile — left hides the windup behind the torso), heavy from the left in silhouette (an overhead is sagittal) at windup apex + buried impact, then heavy again with the hit capsule visible (menu > Debug > Hitboxes) to verify it rides the blade.
    g.hero.pos = mathx.ground(0, 4);
    g.rig.yaw = mathx.radians(30); // front 3/4 — the hero faces -Z, so this shows the sword-arm arc (270 hid it behind the torso)
    g.rig.pitch = 0.13;
    g.rig.dist = 4.2;
    stagedAttack(g, .light);
    advanceAttack(g, dt, 10); // ~u 0.28: windup apex — fist at shoulder height, blade LEVEL back over the shoulder
    shoot(g, "shots/15a_atk_light_wind.png");
    advanceAttack(g, dt, 5); // ~u 0.42: mid-arc — blade horizontal, tip OUTWARD, sweeping across
    shoot(g, "shots/15_atk_light_strike.png");
    advanceAttack(g, dt, 4); // ~u 0.53: the whip PEAK — wrist fired, blade level through contact
    shoot(g, "shots/15p_atk_light_peak.png");
    advanceAttack(g, dt, 3); // ~u 0.61: follow-through — blade carried across past the OFF shoulder, still level
    shoot(g, "shots/15b_atk_light_thru.png");
    g.hero.stam.reset(); // staged like the rest — the buffering is what this shot is about
    g.hero.requestAttack(.light); // buffered past the chain knot → the ALTERNATE backhand
    advanceAttack(g, dt, 12); // chain fires at ~u 0.80, then into the backhand WINDUP (the chamber)
    shoot(g, "shots/15r_atk_return_wind.png"); // verify the return chamber clears the torso (no arm buried in the chest)
    advanceAttack(g, dt, 10); // ~u 0.42 into the return swipe
    shoot(g, "shots/15c_atk_light_return.png");
    advanceAttack(g, dt, 999); // run the combo out
    // TOP-DOWN — the SLASH must sweep a clean horizontal ARC across the hero's FRONT (a swipe, not a downward poke); the swing-trail ribbon reads the arc from above.
    g.rig.yaw = mathx.radians(0);
    g.rig.pitch = 1.48; // near-straight-down (follow() doesn't clamp pitch like the live paths)
    g.rig.dist = 6.5;
    stagedAttack(g, .light);
    advanceAttack(g, dt, 17); // ~u 0.47, deep in the active window — the trail fan painted across the front
    shoot(g, "shots/15t_atk_light_top.png");
    advanceAttack(g, dt, 999);
    g.rig.pitch = 0.13;
    g.rig.yaw = mathx.radians(90);
    stagedAttack(g, .heavy);
    advanceAttack(g, dt, 20); // ~u 0.33: overhead windup apex (the R2 tell)
    shoot(g, "shots/16_atk_heavy_windup.png");
    advanceAttack(g, dt, 14); // ~u 0.57: buried impact, follow-through holding
    shoot(g, "shots/17_atk_heavy_impact.png");
    advanceAttack(g, dt, 999);
    g.menu.hitboxes = true;
    stagedAttack(g, .heavy);
    advanceAttack(g, dt, 28); // ~u 0.47: inside the active window — capsule red on the blade
    shoot(g, "shots/18_atk_hitbox.png");
    advanceAttack(g, dt, 999);
    g.menu.hitboxes = false;

    // the shield is BETWEEN him and the threat, the sword is OUT OF THE WAY (a guard still presenting the blade reads as a wind-up), and a caught blow drives him back rather than through him.
    {
        var k: i32 = 0;
        while (k < 45) : (k += 1) stepWorld(g, dt, 0); // out of the last swing's recovery first
        g.hero.pos = mathx.ground(0, 4);
        g.hero.stam.reset();
        g.hero.facing = mathx.headingXZ(LIT_BACK); // …looking down the lens: this is the FRONT view
        g.hero.setGuard(true);
        k = 0;
        while (k < 16) : (k += 1) { // let the stance blend settle (guardB eases in over ~0.1 s)
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20a_guard_front.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20b_guard_3q.png", g.hero.shoulderPoint(), LIT_YAW + 42, 0.09, 3.0);
        shootPortrait(g, "shots/20c_guard_side.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.09, 3.0);
        // A BLOW CAUGHT, straight into the shield: the frame right after the recoil fires, which is the one that has to say HELD rather than hurt.
        _ = g.hero.takeHit(ogremod.SWIPE_HIT, mathx.headingDir(g.hero.facing));
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootPortrait(g, "shots/20d_guard_block.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        // …and the shield's own BACK: the grip bar and the arm pad, which only ever show from here.
        g.hero.facing = mathx.headingXZ(LIT_BACK) + std.math.pi;
        k = 0;
        while (k < 30) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20e_guard_back.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        // PUT IT AWAY.
        g.hero.setGuard(false);
        g.hero.stam.reset();
        // …and the damage flash with it.
        g.hero.hurtFlash = 0;
        g.hero.vit = heromod.freshVitals();
        k = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
    }

    // The carry: settle to a stand and frame the sword side — the held low-ready.
    var idleK: i32 = 0;
    while (idleK < 55) : (idleK += 1) stepWorld(g, dt, 0);
    g.rig.yaw = mathx.radians(300);
    g.rig.pitch = 0.14;
    g.rig.dist = 3.4;
    g.rig.follow(g.hero.shoulderPoint());
    shoot(g, "shots/19_idle_hold.png");

    {
        const f = &g.warren.frogs[0];
        // Hero stands a couple metres off — a scale reference that also keeps the toad inside the sun's shadow ortho box (which tracks the hero).
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
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -2.2), game.PLAY_HALF, false);
        stepFoe(f, 6, behind); // mid coil (loaded, knees stacked)
        shootFoe(g, f, "shots/22_frog_coil.png", 90, 0.08, 3.0);
        stepFoe(f, 22, behind); // arc apex (stretched, airborne)
        shootFoe(g, f, "shots/23_frog_leap.png", 90, 0.05, 3.4);
        stepFoe(f, 22, behind); // landing splat
        shootFoe(g, f, "shots/24_frog_land.png", 90, 0.09, 3.1);

        // A lunge into its recovery (the wide-open window).
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -3.6), game.PLAY_HALF, true);
        stepFoe(f, 26, behind); // deep into the long telegraph coil (loaded, dust flying, throat charged)
        shootFoe(g, f, "shots/25_frog_lunge_wind.png", 55, 0.09, 3.3);
        stepFoe(f, 60, behind); // through flight + heavy landing, ~0.3 s into recovery
        shootFoe(g, f, "shots/26_frog_recover.png", 70, 0.13, 3.2);

        // A chomp: gape (sac balloons, jaws yawn) → snap.
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.startChomp();
        stepFoe(f, 22, front); // near full gape (charge gathering, drool stringing)
        shootFoe(g, f, "shots/27_frog_gape.png", 162, 0.06, 2.2); // front 3/4, close — peer into the maw
        stepFoe(f, 6, front); // jaws slamming
        shootFoe(g, f, "shots/28_frog_snap.png", 162, 0.06, 2.2);

        // A TRACKED hit: the swept blade capsule meets the hurt sphere and the counter ticks (Debug > Hitboxes draws both; Stats shows "frog hits N").
        g.menu.hitboxes = true;
        g.menu.stats = true;
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        g.hero.pos = mathx.ground(0, 0.85);
        g.hero.facing = std.math.pi; // face -Z, toward the toad at the origin
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        stagedAttack(g, .light);
        var hk: i32 = 0;
        while (hk < 999 and g.hero.attacking) : (hk += 1) {
            g.hero.updateAttack(dt, game.PLAY_HALF, null);
            _ = f.update(dt, mathx.ground(0, 60), game.PLAY_HALF, heroBlade(g));
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
        // …UNDIRECTED (a zero `fromDir`), which is what the harness wants: these photograph the REACTIONS, and a blow with no direction cannot be caught on the shield however he is standing (hero.guardCovers), so the flinch is guaranteed to be the thing in frame.
        _ = g.hero.takeHit(.{ .poise = 999 }, mathx.zero3); // empty poise → the light flinch
        var sk: i32 = 0;
        while (sk < 13) : (sk += 1) g.hero.updateStun(dt); // flinch PEAK
        g.rig.yaw = mathx.radians(60);
        g.rig.pitch = 0.12;
        g.rig.dist = 4.6;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/34_hero_flinch.png");
        while (g.hero.staggered()) g.hero.updateStun(dt);

        _ = g.hero.takeHit(.{ .stance = 999 }, mathx.zero3); // empty stance → the heavy stagger
        sk = 0;
        while (sk < 26) : (sk += 1) g.hero.updateStun(dt);
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/35_hero_stagger.png");
        while (g.hero.staggered()) g.hero.updateStun(dt);

        _ = g.hero.takeHit(.{ .dmg = 999 }, mathx.zero3); // lethal → the death collapse
        sk = 0;
        while (sk < 130) : (sk += 1) g.hero.updateDeath(dt); // deep into the card: heap + YOU DIED full
        g.rig.pitch = 0.22;
        g.rig.dist = 5.2;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/36_hero_death.png");
        while (g.hero.dead) g.hero.updateDeath(dt); // run out → respawn (restores clean state)

        // THE BARS: a half-health foe's floating bar plus the hero's whole top-left corner — and the corner has to be WORKING, not full.
        g.hero.hurtFlash = 0; // clear any leftover flash from the death shot (harness never ticks it)
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.vit.hp = f.vit.hpMax * 0.45;
        // …and mark it RECENTLY hurt. drawFoeBars gates on HURT_BAR_WINDOW, and only vit.hit() moves sinceHit — so setting hp straight left this shot, the one named for the bars, with no foe bar in it at all.
        f.vit.sinceHit = 0;
        stepFoe(f, 4, front);
        g.hero.pos = mathx.ground(2.4, 4.2);
        g.hero.facing = std.math.atan2(-g.hero.pos.x, -g.hero.pos.z);
        g.hero.vit.hp = g.hero.vit.hpMax * 0.55;
        g.hero.stam.spend(combat.STAM_ROLL + combat.STAM_HEAVY);
        // …and BANK SOME RUNES, part-rolled.
        g.hero.runes.gain(ogremod.RUNES + 2 * frogmod.RUNES);
        var rk: i32 = 0;
        while (rk < 14) : (rk += 1) g.hero.runes.tick(SHOT_DT);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.rig.yaw = mathx.radians(202);
        g.rig.pitch = 0.16;
        g.rig.dist = 6.4;
        g.rig.follow(f.centerWorld());
        shoot(g, "shots/37_hp_bars.png");

        // THE LOCKOUT, on an empty bar: the stamina bar flags a refused action so an input that does nothing can't be mistaken for a dropped one.
        g.hero.stam.spend(combat.STAM_MAX);
        g.hero.startRoll(v3(0, 0, -1));
        std.debug.assert(!g.hero.rolling); // the whole point: an empty pool cannot roll
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shoot(g, "shots/37b_stam_locked.png");

        // …and WINDED with stamina in the bar, which is the state the empty one above cannot show: a pool refilling after being run dry, denied the SPRINT until it reaches half, with the owed band and the threshold mark saying how much is left to wait for.
        var st: usize = 0;
        while (g.hero.stam.frac() < 0.2 and st < 600) : (st += 1) g.hero.stam.tick(SHOT_DT, false, false);
        std.debug.assert(g.hero.stam.cur > 0 and !g.hero.stam.canSprint());
        g.hero.stamRefused = 0; // no refusal flash — the mark has to carry this on its own
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shoot(g, "shots/37c_stam_winded.png");

        g.hero.vit.hp = g.hero.vit.hpMax; // …back to full for everything downstream (the chip snaps up with it)
        g.hero.stam.reset();
        g.hero.stamRefused = 0;
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // reset the slot
    }

    {
        g.warren.frogs[0] = frogmod.Frog.spawn(mathx.ground(0, 60), 0, 1.0, 0.0); // shoo the origin toad out of the archer portraits
        const a = &g.line.archers[0];
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
        // A "hero" in-band ahead (+Z) so the archer decides to shoot and pulls to full draw naturally; stop at the hold (full draw) for the portrait.
        g.hero.pos = mathx.ground(3.0, 2.5); // near enough to keep the shadow ortho box over the archer
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        var k: i32 = 0;
        while (k < 140 and a.drawAmt < 0.98) : (k += 1) _ = a.update(dt, mathx.ground(0, 12), game.PLAY_HALF, .{});
        shootFoe(g, a, "shots/40_archer_aim_side.png", 90, 0.06, 4.8); // profile: draw arm folded back, bow arm out
        shootFoe(g, a, "shots/41_archer_aim_front.png", 6, 0.12, 4.4); // front: skull + ribcage + the aim
        shootFoe(g, a, "shots/42_archer_aim_3q.png", 48, 0.10, 4.8); // three-quarter
        // An arrow leaving the bow: loose from the nock toward a target ahead and step it into its arc, parked in the pool so drawArrows renders the oriented, arcing shaft.
        g.arrows[0] = archermod.launchArrow(a.nockWorld(), mathx.ground(0, 15));
        var m: i32 = 0;
        while (m < 8) : (m += 1) archermod.stepArrow(&g.arrows[0], mathx.ground(0, 15), HERO_CENTER_Y, g.env.groundAt(g.arrows[0].pos.x, g.arrows[0].pos.z), false, arrowCover(g, &g.arrows[0], dt), dt);
        shootFoe(g, a, "shots/44_archer_loose.png", 90, 0.05, 5.2); // side-on: the shaft crosses the frame
        g.arrows[0] = .{};
        // A lowered/idle read too, to check the skeleton stands cleanly with the bow at rest.
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var j: i32 = 0;
        while (j < 20) : (j += 1) _ = a.update(dt, mathx.ground(0, 60), game.PLAY_HALF, .{}); // hero far → stays idle
        shootFoe(g, a, "shots/43_archer_idle_side.png", 90, 0.08, 4.6);
        // The SHARED walk/strafe (hero.legChain): crowd it so it kites, catch it mid-backpedal.
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var w2: i32 = 0;
        while (w2 < 60) : (w2 += 1) _ = a.update(dt, mathx.ground(0, 3), game.PLAY_HALF, .{}); // hero crowds → back off
        shootFoe(g, a, "shots/45_archer_kite.png", 90, 0.09, 5.4);
        // THE BACKSTEP: crowd it inside sword reach to trigger the panic leap, then catch the apex and the landing absorb.
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var bs: i32 = 0;
        while (bs < 400 and !a.airborne()) : (bs += 1) _ = a.update(dt, mathx.ground(0, 2.2), game.PLAY_HALF, .{});
        var bp: i32 = 0;
        while (bp < 7) : (bp += 1) _ = a.update(dt, mathx.ground(0, 2.2), game.PLAY_HALF, .{}); // …on to the apex
        shootFoe(g, a, "shots/45b_archer_backstep.png", 90, 0.06, 6.0);
        var bl: i32 = 0;
        while (bl < 18) : (bl += 1) _ = a.update(dt, mathx.ground(0, 2.2), game.PLAY_HALF, .{});
        shootFoe(g, a, "shots/45c_archer_backstep_land.png", 90, 0.06, 6.0);
        // Lock-on onto a SKELETON — the reticle rides ANY foe now (FoeRef over both groups).
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var lk: i32 = 0;
        while (lk < 24) : (lk += 1) _ = a.update(dt, mathx.ground(0, 60), game.PLAY_HALF, .{}); // settle to idle
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

    // A PORTRAIT SPOT NEEDS THE CAMERA'S ROOM, NOT JUST THE SUBJECT'S.
    {
        const o = &g.grief.ogres[0];
        const oc = mathx.ground(-26.0, 14.0);
        const far = v3(oc.x, 0, oc.z + 80.0); // sensed hero far ahead → holds state, faces +Z

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 54, far); // settle into idle, landing mid weight-shift (one leg relaxed)
        // Idle — a CLEAN standing read (hero shoved out of frame), pitched down a touch to see the full stooped-but-towering silhouette and the legs on the ground.
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
        // The approach — the shared gait, side-on, to judge the LUMBER (trunk roll + swagger + footfall catch) and the ARM SWING.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 100, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/56_ogre_walk.png", 90, 0.06, 12.0);
        // …and b/c from yaw 270 — the OFF profile.
        stepFoe(o, 34, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/57_ogre_walk_b.png", 270, 0.06, 12.0);
        stepFoe(o, 69, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/58_ogre_walk_c.png", 270, 0.06, 12.0);
        stepFoe(o, 17, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/59_ogre_walk_3q.png", 320, 0.08, 12.5); // front-left 3/4: free arm, lit
        // THE HEAD CRANE — the sensed hero sits hard off his LEFT while his body still points +Z, so the eye is craned to the neck's limit a beat before the slow body can follow.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 14, v3(oc.x + 9.0, 0, oc.z + 1.0)); // 14 frames: the head is AT its 55 deg
        // clamp while the ponderous body has only come round ~30 — any later and the body has caught up and there is no lead left to see.
        shootFoe(g, o, "shots/60_ogre_headtrack.png", 20, 0.20, 11.0);

        // Face close-up — the single eye + heavy sad brow.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 30, far);
        g.rig.yaw = mathx.radians(182);
        g.rig.pitch = 0.16;
        g.rig.dist = 3.2;
        g.rig.follow(o.headWorld());
        shoot(g, "shots/55_ogre_face.png");

        // The overhead slam: windup (club reared high) → crash (impact dust) → spent recovery.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugSlam();
        stepFoe(o, 64, far); // f64: deep in the loaded peak HOLD — club overhead, arched back, trembling
        shootFoe(g, o, "shots/49_ogre_windup.png", 55, 0.00, 13.0);
        stepFoe(o, 21, far); // f85: one frame past IMPACT — club at the crater, the dust burst still tight
        shootFoe(g, o, "shots/50_ogre_slam.png", 60, 0.06, 13.0);
        stepFoe(o, 25, far); // f110: ~0.4 s into recovery — doubled over the buried club, wide open
        shootFoe(g, o, "shots/51_ogre_recover.png", 48, 0.10, 12.5);

        // The SIDE SWIPE — his fast answer to a hero who won't stand in front of him.
        {
            // Derived like the slam's, off debugSwipe entering .swipewind at t=0: at 1/60 the cock-back ends / the sweep begins at frame 28, the club crosses his centre line (impact) at 34, and the sweep ends at 40.
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

    // questions: does the shared BODY read as a doglike animal (the muzzle, the ears, the ruff, the tail, the fur, and a stature short of a man's), and does each ROLE read as its own job from its kit and its pose alone?
    {
        const kc = mathx.ground(-26.0, 30.0); // open ground west of the ogre's spot, clear of ruins
        // camera where the hero is; and `LIT_YAW` says which bearing is lit.
        const litB = LIT_BACK; // the XZ bearing of backDir(LIT_YAW) — where the camera sits
        const far = v3(kc.x + litB.x * 80.0, 0, kc.z + litB.z * 80.0); // …far enough off that each holds its idle
        const near = v3(kc.x + litB.x * 1.2, 0, kc.z + litB.z * 1.2); // …and in reach, for the attack beats
        g.band.n = 3;
        const zerk = &g.band.band[0];
        const priest = &g.band.band[1];
        const sling = &g.band.band[2];

        // SCALE AND SILHOUETTE FIRST, all three together with the hero beside them: the one shot that says whether "somewhat shorter than a man" landed, and whether the three are distinguishable at a glance without labels.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x - 1.7, kc.z), 0, 1.0, 0.15);
        priest.* = koboldmod.Kobold.spawnAs(.priest, kc, 0, 1.0, 0.55);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, mathx.ground(kc.x + 1.7, kc.z), 0, 1.0, 0.85);
        for ([_]*koboldmod.Kobold{ zerk, priest, sling }) |k| stepFoe(k, 30, far);
        standHero(g, kc.x + 3.2, kc.z - 3.4, mathx.radians(-140));
        shootAt(g, "shots/64_kobold_band.png", v3(kc.x + 0.6, kc.y + 1.0, kc.z), LIT_YAW, 0.10, 7.6);
        // …and the same three CLOSE, to judge the heads as a group.
        shootAt(g, "shots/64b_kobold_heads.png", v3(kc.x, kc.y + 1.30, kc.z), LIT_YAW, 0.03, 4.2);
        // …and ONE head, close and three-quarter, which is the only framing that can actually settle the doglike read: the muzzle LENGTH against the skull, the pricked ears, the amber eye set forward.
        shootPortrait(g, "shots/64c_kobold_head.png", v3(kc.x + 1.7, kc.y + 1.42, kc.z), LIT_YAW + 12, -0.05, 2.3);
        // …and the TAIL.
        const back = v3(kc.x - litB.x * 80.0, 0, kc.z - litB.z * 80.0);
        for ([_]*koboldmod.Kobold{ zerk, priest, sling }) |k| stepFoe(k, 40, back);
        shootPortrait(g, "shots/64d_kobold_tail.png", v3(kc.x - 1.7, kc.y + 0.74, kc.z), LIT_YAW - 34, 0.14, 2.7);

        // Hero out of frame for the role portraits.
        g.hero.pos = mathx.ground(kc.x, kc.z - 26.0);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        // …AND THE OTHER TWO, or a role portrait has two spectators standing in it.
        const away = mathx.ground(kc.x - 40.0, kc.z + 40.0);
        const park = struct {
            fn it(k: *koboldmod.Kobold, role: koboldmod.Role, at: rl.Vector3) void {
                k.* = koboldmod.Kobold.spawnAs(role, at, 0, 1.0, 0.5);
            }
        }.it;
        park(priest, .priest, away);
        park(sling, .slinger, away);

        // THE BERSERKER mid-chop, two frames one beat apart.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        var zf: i32 = 0;
        while (zerk.state != .chop and zf < 600) : (zf += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(zerk, 5, near); // ~u 0.20: the top of the raise, axe cocked over the shoulder
        shootFoe(g, zerk, "shots/65_kobold_chop.png", LIT_YAW + 20, 0.06, 3.4);
        stepFoe(zerk, 8, near); // ~u 0.50: mid-strike, the axe crossing his centre line
        shootFoe(g, zerk, "shots/65b_kobold_chop_b.png", LIT_YAW + 20, 0.06, 3.4);
        // …and the HEAVE, which is the opening the whole design rests on: doubled over at the waist, axes dragging.
        var guard: i32 = 0;
        while (zerk.state != .heave and guard < 600) : (guard += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(zerk, 12, near); // …into the hold, where the fold is deepest
        shootFoe(g, zerk, "shots/66_kobold_heave.png", LIT_YAW + 62, 0.04, 3.6); // side-on: a FOLD is a profile read

        // …and THE POUNCE, in PROFILE and in three beats, because a leap is a shape over TIME and no single frame can show that the coil happens before the launch.
        {
            const dside = v3(kc.x - litB.z * 5.0, 0, kc.z + litB.x * 5.0); // inside the dash band
            const dyaw = mathx.headingXZ(mathx.subV(dside, kc));
            const beats = [_]struct { name: [:0]const u8, at: f32 }{
                .{ .name = "shots/66d_kobold_dash_coil.png", .at = 0.10 }, // the gather: both knees loaded
                .{ .name = "shots/66e_kobold_dash_fly.png", .at = 0.30 }, // the leap: ONE knee up, one leg trailing
                .{ .name = "shots/66f_kobold_dash_land.png", .at = 0.56 }, // arriving: knees giving under him
            };
            for (beats) |b| {
                zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, dyaw, 1.0, 0.15);
                zerk.dashCd = 0;
                var df: i32 = 0;
                while (zerk.state != .dash and df < 600) : (df += 1) _ = zerk.update(SHOT_DT, dside, game.PLAY_HALF, .{});
                // …then to the beat itself, in whole harness frames off the state clock.
                while (zerk.t < b.at) _ = zerk.update(SHOT_DT, dside, game.PLAY_HALF, .{});
                shootPortrait(g, b.name, zerk.centerWorld(), LIT_YAW, 0.06, 5.0);
            }
        }

        // …and THE REACTIONS, which had no shots at all — which is how six leg bones came to be handed to `drawMesh` as UNDEFINED matrices on every death in the game without anybody seeing it.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        zerk.debugStagger(true);
        stepFoe(zerk, 10, far); // deep in the stance-break: knees buckled, arms flung, muzzle up
        shootFoe(g, zerk, "shots/66b_kobold_stagger.png", LIT_YAW + 22, 0.06, 3.8);
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        zerk.debugKill();
        stepFoe(zerk, 34, far); // folded onto the ground, before the motes take him
        shootFoe(g, zerk, "shots/66c_kobold_death.png", LIT_YAW + 30, 0.16, 3.6);

        // THE PRIEST casting: staff up two-handed, gold gathering into the head.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x - 1.6, kc.z + 0.4), 0, 1.0, 0.15);
        zerk.vit.hp = 20; // …somebody worth healing, or the priest has nothing to cast for
        priest.* = koboldmod.Kobold.spawnAs(.priest, kc, 0, 1.0, 0.55);
        priest.healWanted = true;
        priest.castCd = 0;
        var cf: i32 = 0;
        while (cf < 64) : (cf += 1) _ = g.band.update(SHOT_DT, far, game.PLAY_HALF, .{}, g, game.spawnStone);
        shootFoe(g, priest, "shots/67_kobold_cast.png", LIT_YAW + 16, 0.10, 4.4);
        shootFoe(g, priest, "shots/67b_kobold_cast_far.png", LIT_YAW + 16, 0.14, 13.0);

        // THE SLINGER: the sling round overhead (the tell), then the teeth close in.
        park(zerk, .berserker, away);
        park(priest, .priest, away);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, 0, 1.0, 0.85);
        sling.slingCd = 0;
        const band8 = v3(kc.x + litB.x * 8.0, 0, kc.z + litB.z * 8.0); // inside its range band, on the lit bearing
        var g2: i32 = 0;
        while (sling.state != .whirl and g2 < 600) : (g2 += 1) _ = sling.update(SHOT_DT, band8, game.PLAY_HALF, .{});
        stepFoe(sling, 16, band8); // …a third of the way round the cone
        shootFoe(g, sling, "shots/68_kobold_whirl.png", LIT_YAW + 18, 0.10, 3.8);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, 0, 1.0, 0.85);
        sling.biteCd = 0;
        var g3: i32 = 0;
        while (sling.state != .bite and g3 < 600) : (g3 += 1) _ = sling.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(sling, 10, near); // …inside the snap, where the jaw is open
        shootFoe(g, sling, "shots/69_kobold_bite.png", LIT_YAW + 14, 0.04, 2.6);
        // …and the SAME beat in PROFILE, which is the only angle that shows what a snap is made of: the waist folding over planted legs and the muzzle leading it.
        const side = v3(kc.x - litB.z * 1.2, 0, kc.z + litB.x * 1.2);
        // SPAWNED ALREADY FACING IT.
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, mathx.headingXZ(mathx.subV(side, kc)), 1.0, 0.85);
        sling.biteCd = 0;
        var g4: i32 = 0;
        while (sling.state != .bite and g4 < 600) : (g4 += 1) _ = sling.update(SHOT_DT, side, game.PLAY_HALF, .{});
        stepFoe(sling, 4, side); // the CHAMBER — the rock back that gives the snap its crack
        // …CENTRED (`shootPortrait`), not `shootFoe`: the rig's shoulder offset is 0.55 m and this subject is 1.3 m tall, so a followed framing at snap distance puts half of it out of frame.
        shootPortrait(g, "shots/69d_kobold_bite_coil.png", sling.centerWorld(), LIT_YAW, 0.06, 4.4);
        stepFoe(sling, 6, side); // …and the snap itself, a tenth of a second later
        shootPortrait(g, "shots/69c_kobold_bite_side.png", sling.centerWorld(), LIT_YAW, 0.06, 4.4);
        // …and the OPEN JAW itself, head-on and close.
        shootPortrait(g, "shots/69e_kobold_bite_jaw.png", sling.lockPoint(), LIT_YAW, 0.02, 1.9);

        // …and the WALK, side on, at three phases a quarter-stride apart: the shared gait under a narrower trunk, and the one thing a single frame provably cannot verify.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x - litB.x * 9.0, kc.z - litB.z * 9.0), 0, 1.0, 0.15);
        const walkTo = v3(kc.x + litB.x * 40.0, 0, kc.z + litB.z * 40.0);
        const walkNames = [_][:0]const u8{ "shots/69b_kobold_walk.png", "shots/69c_kobold_walk.png", "shots/69d_kobold_walk.png" };
        for ([_]i32{ 26, 9, 9 }, 0..) |adv, wi| {
            stepFoe(zerk, adv, walkTo); // hero far ahead on the sun's bearing → walks toward it, LIT
            shootFoe(g, zerk, walkNames[wi], LIT_YAW + 58, 0.06, 4.6);
        }
        g.band.n = 0; // …and the field is empty again: the band is not on the shipped map
    }

    // the scene shader grew point lights.
    {
        // The avenue from the start, looking north up the processional way into the city.
        standHero(g, 0, 12, std.math.pi);
        shootAt(g, "shots/70_avenue_north.png", g.hero.shoulderPoint(), 180, 0.16, 9.0);
        // A high, wide vista north — the whole depth of the world in one frame: avenue, plaza, city wall, the colossal gate, and the cliffs behind it dissolving into haze.
        shootAt(g, "shots/71_vista_north.png", mathx.ground(0, 6), 180, 0.30, 9.0);
        // THE BONFIRE, close.
        standHero(g, 1.4, 7.4, mathx.radians(120));
        shootAt(g, "shots/71b_bonfire.png", v3(3.0, 0.55, 6.5), 300, 0.07, 3.1);
        // THE GUITAR, on its own — the one manufactured object in the world, and small enough that the camp framing above cannot judge it.
        standHero(g, 0.0, 3.4, mathx.radians(200));
        shootPortrait(g, "shots/71c_guitar.png", v3(1.38, 0.68, 7.34), 20, 0.06, 2.7);
        standHero(g, 3.0, 8.4, mathx.radians(200));
        game.beginRestForShot(g);
        for ([_]i32{ 165, 55, 60 }, [_][:0]const u8{ "shots/71e_rest.png", "shots/71f_rest_play.png", "shots/71g_rest_play2.png" }) |adv, name| {
            var k: i32 = 0;
            while (k < adv) : (k += 1) game.tickRestForShot(g, SHOT_DT);
            shoot(g, name);
        }
        game.endRestForShot(g);

        // THE SMOKE COLUMN against the horizon — the framing that judges the veil pass.
        standHero(g, 4.4, 6.2, mathx.radians(120));
        shootAt(g, "shots/71d_plume.png", v3(3.0, 2.3, 6.5), LIT_YAW, 0.14, 9.0);

        // THE FALLEN CITY: the plaza, then the chapel from the road, then INSIDE it.
        standHero(g, 2.0, -66.0, std.math.pi);
        shootAt(g, "shots/72_city_plaza.png", mathx.ground(0, -74), 180, 0.26, 9.0);
        // The chapel sits at (-30, -66) turned to yaw 270, which maps its local +Z (the altar end) to world −X and its doorway to world +X: the nave runs along X from -33.6 (altar) to -26.4 (door).
        standHero(g, -22.0, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/73_chapel_outside.png", mathx.ground(-30, -66), 270, 0.22, 17.0);
        // Looking WEST down the nave from the doorway: the roofed altar end gets NO sun, so what you can see of it is the standing torches — the whole reason gfx grew point lights.
        standHero(g, -29.6, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/74_chapel_torchlit.png", v3(-30.7, 1.4, -66.0), 270, 0.05, 4.4);
        // …and closer on the altar itself, still outside its 1.25 m half-depth.
        standHero(g, -30.6, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/75_chapel_altar.png", v3(-32.6, 1.0, -66.0), 270, 0.10, 4.8);

        // A watchtower: the drum with its door brazier, then the dark room inside it.
        standHero(g, 34.0, -95.0, mathx.radians(20));
        shootAt(g, "shots/76_watchtower.png", mathx.ground(36, -88), 20, 0.16, 27.0);
        // Inside the drum: the camera must sit within the 2.35 m wall radius, so target the middle and keep dist under it or the eye ends up embedded in masonry.
        standHero(g, 36.4, -88.4, 0);
        shootAt(g, "shots/77_watchtower_inside.png", v3(35.7, 1.7, -87.6), 200, 0.06, 2.0);

        // THE TARN. gfx.SUN_DIR points from the surface TOWARD the sun, which is low in the WEST — so the glitter path only exists looking WEST across the water, and the west shore looking east is the one angle guaranteed to show none of it.
        standHero(g, 130.0, 14.0, -std.math.pi * 0.5);
        shootAt(g, "shots/78_tarn.png", mathx.ground(122, 12), 268, 0.10, 13.0);
        standHero(g, 70.0, 8.0, std.math.pi * 0.5);
        shootAt(g, "shots/79_tarn_causeway.png", mathx.ground(78, 8), 100, 0.18, 12.0);

        // THE OLD WOOD: under the canopy, then one great tree whole (for judging the model), then the stone circle and the woodcutter's cottage with its fire.
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

        // THE EDGE: the cliff wall the movement clamp hides behind.
        const rimZ = g.map.half - 20.0;
        standHero(g, 40.0, rimZ, 0);
        shootAt(g, "shots/85_cliffs.png", mathx.ground(40, rimZ + 12), 4, 0.22, 22.0);
        // …and a long raking view ALONG the wall, which is the angle that shows whether it reads as one escarpment or as a row of separate rocks.
        standHero(g, 10.0, rimZ + 10, std.math.pi * 0.5);
        shootAt(g, "shots/85b_cliffs_along.png", mathx.ground(30, rimZ + 18), 80, 0.16, 26.0);
        // THE START ARC — the only place the cliff CHARACTERS stand side by side close enough to compare.
        standHero(g, 0.0, 6.0, 0);
        shootAt(g, "shots/85c_arc_ivied.png", mathx.ground(0, 21), 0, 0.16, 22.0);
        // the east flank sits at yaw 85 (face toward −X), so the eye goes WEST of it looking +X (camera yaw 90).
        standHero(g, 22.0, 3.0, mathx.radians(90));
        shootAt(g, "shots/85d_arc_collapsed.png", mathx.ground(36, 2), 90, 0.14, 20.0);

        // MAP SHOTS — one steep overhead per region.
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

        // PERF READOUT — the debug Stats overlay from ground level in the two busiest places, so the culling numbers are captured, not assumed.
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

    // Retro filters + menu verification: two filter stacks over the current framing, then the menu cards over the veiled scene.
    g.retro.applyPreset(&gfx.PRESET_CRT);
    shoot(g, "shots/10_retro_crt.png");

    g.retro.applyPreset(&gfx.PRESET_PS1);
    shoot(g, "shots/11_retro_ps1.png");
    g.retro.allOff();

    g.menu.screen = .main;
    g.menu.cursor = 0;
    drawScene(g);
    hud(g, SHOT_DT);
    g.menu.draw(&g.retro, &g.bag);
    snap("shots/12_menu_main.png");

    g.retro.values[gfx.RF_GAMEBOY] = 1.0; // show a live gauge on the retro card
    g.menu.screen = .retro;
    g.menu.cursor = gfx.RF_GAMEBOY;
    drawScene(g);
    hud(g, SHOT_DT);
    g.menu.draw(&g.retro, &g.bag);
    snap("shots/13_menu_retro.png");
    g.menu.screen = .closed;

    // The owner-tuned default stack — the look the game actually launches with.
    g.retro.values = gfx.RETRO_DEFAULTS;
    shoot(g, "shots/14_retro_default.png");
    g.retro.allOff();

    chestShots(g);
    editorShots(g);
}

fn chestShots(g: *Game) void {
    const cx: f32 = 12.0;
    const cz: f32 = 10.0;
    const saved = g.map.nops;
    if (saved >= worldfmt.MAX_OPS) return; // …and never write off the end of a map that is already full
    var op = worldfmt.defaults(.at);
    op.kind = .chest;
    op.x = cx;
    op.z = cz;
    // THE FRONT FACES THE LIT CAMERA, and this is derived rather than guessed: `drawModelEx` turns the model about +Y, which sends local +Z to (sin yaw, 0, cos yaw), and the camera at yaw 53 (the sun's bearing — see the kobold block) sits toward (−0.794, 0, −0.608).
    op.yaw = 233;
    op.loot[0] = .golden_seed;
    op.loot[1] = .rune_arc;
    op.loot[2] = .mushroom_jerky; // …the one item in the game that DOES anything, so the inventory
    op.loot[3] = .kobold_fang; //     shot below is of a list with a usable row in it and not just names
    op.nloot = 4;
    g.map.ops[g.map.nops] = op;
    g.map.nops += 1;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
    g.bag = .{};

    // CLOSED, with the hero in reach so the PROMPT is in frame.
    const gy = mathx.ground(cx, cz).y;
    const right = v3(-LIT_BACK.z, 0, LIT_BACK.x); // square to the boom, on the ground
    const hx = cx + right.x * 1.8;
    const hz = cz + right.z * 1.8;
    const aim = v3(cx, gy + 0.55, cz);
    standHero(g, hx, hz, mathx.headingXZ(v3(cx - hx, 0, cz - hz)));
    g.chests.update(SHOT_DT, g.hero.pos);
    shootPortrait(g, "shots/106_chest_closed.png", aim, LIT_YAW, 0.16, 4.4);

    // …OPENING, three frames across the swing, because a hinge is the one thing a single frame provably cannot show.
    _ = game.openChestForShot(g);
    const names = [_][:0]const u8{ "shots/106b_chest_opening.png", "shots/106c_chest_opening.png", "shots/106d_chest_open.png" };
    for ([_]i32{ 8, 10, 34 }, 0..) |adv, i| {
        var f: i32 = 0;
        while (f < adv) : (f += 1) g.chests.update(SHOT_DT, g.hero.pos);
        shootPortrait(g, names[i], aim, LIT_YAW, 0.16, 4.4);
    }

    // …and THE INVENTORY the four items landed in, which is the other end of the loop.
    g.menu.onStartButton();
    g.menu.cursor = 0;
    _ = g.menu.update(&g.retro, SHOT_DT, &g.bag);
    drawScene(g);
    g.menu.draw(&g.retro, &g.bag);
    snap("shots/106e_character_menu.png");
    g.menu.screen = .inventory;
    g.menu.cursor = 0;
    drawScene(g);
    g.menu.draw(&g.retro, &g.bag);
    snap("shots/106f_inventory.png");
    g.menu.screen = .closed;

    // …and PUT THE WORLD BACK.
    g.map.nops = saved;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
}

// THE EDITOR — its whole job is legibility and none of that can be judged from the game shots, so it gets a frame per room: the Props layer at rest, a generator selected (its gizmo plus a marker on every instance it owns — the thing that makes a scatter editable), a Decor belt mid-drag, the Ground layer with soil painted, painted WATER low and overhead, a marquee, the Open dialog, the object viewer's two levels, the Interactables layer and the jukebox.
fn editorShots(g: *Game) void {
    g.editor.enter(mathx.ground(0, -66)); // the chapel end of the processional way
    g.editor.setLayer(.props);
    g.editor.dist = 46;
    g.editor.pitch = -0.65;
    g.editor.applyCamForShot();

    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/95_editor_props.png");

    // Select the wood's canopy belt — the biggest generator in the map, and the one whose ownership markers say most about what selection means here.
    g.editor.setLayer(.props);
    for (g.map.slice(), 0..) |o, i| {
        if (o.op == .belt and o.nmix > 3) {
            g.editor.sel = i;
            g.editor.focusOnForShot(&g.map, i);
            break;
        }
    }
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/96_editor_selected.png");

    // A Decor scatter drag in progress over the start meadow.
    g.editor.enter(mathx.ground(0, 0));
    g.editor.setLayer(.decor);
    g.editor.brush[@intFromEnum(editormod.Layer.decor)] = @intFromEnum(editormod.DecorBrush.scatter);
    g.editor.decorKind = .foxglove;
    g.editor.focus = mathx.ground(0, 0);
    g.editor.pitch = -0.95;
    g.editor.yaw = 0;
    g.editor.dist = 44;
    g.editor.applyCamForShot();
    g.editor.dragging = true;
    g.editor.dragFrom = mathx.ground(-16, -12);
    g.editor.dragTo = mathx.ground(14, 16);
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/97_editor_drag.png");
    g.editor.dragging = false;

    // THE GROUND LAYER with real paint down: a worn dirt track along the avenue and a stone apron at the arch, so the shader's soil override is captured rather than assumed.
    const before = g.map.soil;
    const beforeCov = g.map.soilCov;
    g.editor.setLayer(.ground);
    g.editor.brush[@intFromEnum(editormod.Layer.ground)] = @intFromEnum(editormod.GroundBrush.dirt);
    g.editor.radius = 5;
    var z: f32 = 22;
    while (z > -40) : (z -= 3) _ = g.map.paintSoil(0.6, z, 4.5, .dirt, 1);
    _ = g.map.paintSoil(0, -30, 9, .stone, 1);
    // …and the moss at HALF strength, so the capture carries the coverage system as well as the ids: a patch laid down faint is the thing a screenshot can prove and a comment cannot.
    _ = g.map.paintSoil(-13.5, 3, 6, .moss, 0.5);
    g.env.uploadSoil(&g.map);
    g.editor.focus = mathx.ground(0, -10);
    g.editor.pitch = -0.85;
    g.editor.yaw = std.math.pi;
    g.editor.dist = 46;
    g.editor.applyCamForShot();
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/98_editor_ground.png");

    g.map.soil = before;
    g.map.soilCov = beforeCov;
    g.env.uploadSoil(&g.map);

    // PAINTED WATER, the same way: a pond swept in with the brush and shot from low down, which is the angle that judges the thing it is FOR — the coast fading into wet sand with no hand-blending and no mesh authored for the outline.
    const beforeWater = g.map.water;
    g.editor.setLayer(.ground);
    g.editor.brush[@intFromEnum(editormod.Layer.ground)] = @intFromEnum(editormod.GroundBrush.water);
    g.editor.radius = 7;
    // A bay with a headland: two overlapping sweeps and a bite taken out, so the shot shows what the field does with a shape nobody could have authored as a disc.
    var wz: f32 = -6;
    while (wz < 26) : (wz += 2.5) _ = g.map.paintWater(-26 + wz * 0.35, wz, 9.5, true);
    var wx: f32 = -34;
    while (wx < -8) : (wx += 2.5) _ = g.map.paintWater(wx, 14, 7.5, true);
    _ = g.map.paintWater(-21, 9, 4.6, false); // the headland
    g.env.uploadWater(&g.map);
    // …and RE-SOW, which is what a real stroke does on release: the scatter reads `inWater`, so without this the capture shows grass standing in the middle of the new lake and misrepresents the tool.
    g.env.materialize(&g.map);
    g.editor.focus = mathx.ground(-24, 10);
    g.editor.pitch = -0.34;
    g.editor.yaw = 2.4;
    g.editor.dist = 34;
    g.editor.applyCamForShot();
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/98b_editor_water.png");
    // …and once from overhead, where the SHAPE is what you judge: the shoreline should read as one continuous coast, not as the discs it was swept from.
    g.editor.pitch = -1.15;
    g.editor.dist = 58;
    g.editor.applyCamForShot();
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/98c_editor_water_map.png");

    g.map.water = beforeWater;
    g.env.uploadWater(&g.map);

    // MARQUEE + CLIPBOARD: a shift-drag box over the avenue with the Props inside it marked, so the selection ring on each and the box itself are both captured.
    g.editor.setLayer(.props);
    g.editor.focus = mathx.ground(0, -12);
    g.editor.pitch = -0.8;
    g.editor.yaw = std.math.pi;
    g.editor.dist = 40;
    g.editor.applyCamForShot();
    g.editor.selectForShot(&g.map, mathx.ground(-20, -30), mathx.ground(20, 6));
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/99_editor_marquee.png");

    // The OPEN dialog over the same frame — the file list is chrome and can't be judged from any of the above.
    g.editor.openForShot();
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/99b_editor_open.png");

    // THE OBJECT VIEWER, both levels.
    g.editor.objectsForShot(.props, 0, null);
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/99c_editor_objects.png");

    g.editor.objectsForShot(.props, 0, .well);
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/99d_editor_object_one.png");

    g.editor.objectsForShot(.decor, 0, null);
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/99e_editor_objects_decor.png");

    // THE INTERACTABLES LAYER — its own brush strip (a hand tool and an eraser, no scatters) and its own one-shelf palette.
    g.editor.modal = .none;
    g.editor.setLayer(.interact);
    g.editor.selecting = false;
    g.editor.focus = mathx.ground(0, -12);
    g.editor.pitch = -0.7;
    g.editor.yaw = std.math.pi;
    g.editor.dist = 34;
    g.editor.applyCamForShot();
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/99f_editor_interact.png");

    // THE JUKEBOX.
    g.editor.soundsForShot(.ogre_slam);
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/99g_editor_sounds.png");
    g.editor.modal = .none;

    g.editor.on = false;
    elevationShots(g);
}

// LAST, and self-contained, because it is the one block that changes the SHAPE of the world: it sculpts a hill and a hollow into the live map, photographs them from the ground and from above, walks the hero up the slope, and puts the map back exactly as it found it.
fn elevationShots(g: *Game) void {
    const before = g.map.height;
    var span: [4]usize = undefined;
    // A ridge NW of the start with a shoulder you can walk and a face you cannot, plus a hollow beside it.
    _ = g.map.sculpt(-34, -6, 26, .raise, 11.0, &span);
    _ = g.map.sculpt(-20, -24, 18, .raise, 6.0, &span);
    _ = g.map.sculpt(-48, 14, 14, .raise, 4.0, &span);
    _ = g.map.sculpt(6, -22, 15, .lower, 5.0, &span);
    var s: usize = 0;
    while (s < 3) : (s += 1) {
        _ = g.map.sculpt(-34, -6, 30, .smooth, 1.0, &span);
        _ = g.map.sculpt(6, -22, 18, .smooth, 1.0, &span);
    }
    // The world REPLAYED onto the new ground: every prop plants at the height under it, and this is the path the editor takes when a sculpt stroke is released.
    g.env.uploadHeight(&g.map);
    g.env.materialize(&g.map);

    // From the flat ground below, looking up the ridge: the framing that judges whether a hill reads as a hill — its own shading, its silhouette against the haze, and the flora standing ON it rather than sunk through it.
    standHero(g, -6, 6, mathx.radians(215));
    plantHeroForShot(g);
    shootAt(g, "shots/100_hill_from_below.png", g.hero.shoulderPoint(), 215, 0.06, 9.0);

    // …and from ON the ridge looking back down over the avenue, which is where a badly-lit heightfield gives itself away: the sunward faces bright, the leeward ones dark, and the far ground BELOW you.
    standHero(g, -30, -8, mathx.radians(75));
    plantHeroForShot(g);
    shootAt(g, "shots/101_hill_from_above.png", g.hero.shoulderPoint(), 75, 0.30, 11.0);

    // WALKING IT.
    standHero(g, -14, -2, mathx.radians(215));
    plantHeroForShot(g);
    const uphill = mathx.headingDir(mathx.radians(215));
    var k: i32 = 0;
    while (k < 360) : (k += 1) {
        const stepped = g.env.walkStep(g.hero.pos, uphill, heromod.WALK_SPEED * SHOT_DT);
        g.hero.pos.x = stepped.x;
        g.hero.pos.z = stepped.z;
        plantHeroForShot(g);
        g.hero.slopePitch = heromod.slopeLean(g.env.slopeAlong(g.hero.pos.x, g.hero.pos.z, uphill));
        g.hero.update(SHOT_DT, heromod.WALK_SPEED * SHOT_DT, heromod.WALK_SPEED, mathx.radians(215));
        g.hero.pose();
    }
    // PITCHED WELL DOWN, and that is the lesson rather than a preference: a camera behind a hero on a 34 deg slope is looking INTO a rising wedge of ground, so at a gameplay pitch the hillside fills the frame and the hero is behind it.
    shootClear(g, "shots/102_hill_climb.png", 215, 0.62, 8.0);
    g.menu.stats = true;
    shootClear(g, "shots/103_hill_stats.png", 215, 0.62, 8.0);
    g.menu.stats = false;

    // THE WHOLE SHAPE AT ONCE, from a long way back and only moderately steep.
    standHero(g, -4, 22, mathx.radians(215));
    plantHeroForShot(g);
    shootAt(g, "shots/104_hill_profile.png", v3(-24, 6, -8), 215, 0.42, 92.0);

    // THE SCULPT TOOL ITSELF: the Ground layer with Raise armed over the ridge, so the brush ring lying ON the slope, the shape/surface split in the strip, the SCULPT panel's height + slope + walkable readout and the minimap's relief are all in one frame.
    g.editor.enter(g.hero.pos);
    g.editor.setLayer(.ground);
    g.editor.brush[@intFromEnum(editormod.Layer.ground)] = @intFromEnum(editormod.GroundBrush.raise);
    g.editor.radius = 14;
    // The focus rides the GROUND, like the live editor's does: left at y = 0 over an 11 m ridge it aims inside the hill, the eye clamp shoves the camera up off the slope, and the framing you get is of the flat land past it.
    g.editor.focus = v3(-30, g.env.groundAt(-30, -8), -8);
    g.editor.pitch = -0.42;
    g.editor.yaw = 2.5;
    g.editor.dist = 62;
    g.editor.applyCamForShot();
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap("shots/105_editor_sculpt.png");
    g.editor.on = false;

    // …and PUT IT BACK.
    g.map.height = before;
    g.env.uploadHeight(&g.map);
    g.env.materialize(&g.map);
}

/// Stand the hero ON the ground, with no easing — the harness has no frame loop to ease across, and a hero left at the datum on a sculpted map is photographed knee-deep in his own hill.
fn plantHeroForShot(g: *Game) void {
    g.hero.pos.y = g.env.groundAt(g.hero.pos.x, g.hero.pos.z);
    g.hero.pose();
}
