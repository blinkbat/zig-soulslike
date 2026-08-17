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
const shroommod = @import("shroom.zig");
const knightmod = @import("knight.zig");
const delvermod = @import("delver.zig");
const necromod = @import("necro.zig");
const soulsmod = @import("souls.zig");
const koboldmod = @import("kobold.zig");
const broodmod = @import("brood.zig");
const warriormod = @import("warrior.zig");
const shademod = @import("shade.zig");
const leechmod = @import("leechfly.zig");
const rootedmod = @import("rooted.zig");
const npcmod = @import("npc.zig");
const wolfmod = @import("wolf.zig");
const dialogmod = @import("dialog.zig");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const stats = @import("stats.zig");
const ptree = @import("passivetree.zig");
const restmod = @import("rest.zig");
const item = @import("item.zig");
const bookmod = @import("book.zig");
const savemod = @import("save.zig"); // for the boot screen's shelf — staged, never read off the disk
const sfx = @import("audio.zig"); // for the SOUND FILTER cards alone — `--shot` runs with no audio device
const worldfmt = @import("worldfmt.zig");

const Game = game.Game;
const v3 = mathx.v3;

const drawScene = game.drawScene;
const hud = game.hud;
const hudmod = @import("hud.zig"); // the MODULE — `hud` above is the game's own HUD-drawing pass
const heroBlade = game.heroBlade;
const HERO_CENTER_Y = game.HERO_CENTER_Y;
const arrowCover = game.arrowCover;
const WALK_SPEED = heromod.WALK_SPEED;
const RUN_SPEED = heromod.RUN_SPEED;
const SPRINT_SPEED = heromod.SPRINT_SPEED;

pub const SHOT_DT: f32 = 1.0 / 60.0;
/// The DRAWING clock, one shot at a time: every camera here TELEPORTS, and a still frame cannot show a
/// fade — so the occluder fade is handed a step big enough to arrive within the one frame we capture.
pub const SETTLE_DT: f32 = 10.0;
/// Where every projectile here is aimed — down `stepWorld`'s own −Z travel line, far enough to be a flight and
/// not a lob. Shared by shafts and bolts so the four in-flight stills stay comparable.
const SHOT_DOWNRANGE = mathx.ground(0, -22);
fn stepWorld(g: *Game, dt: f32, speed: f32) void {
    const moved = speed * dt;
    g.hero.pos.z = mathx.clampF(g.hero.pos.z - moved, -game.PLAY_HALF, game.PLAY_HALF); // travel −Z
    g.hero.facing = std.math.pi; // face −Z (no turning)
    g.hero.update(dt, moved, speed, if (moved > 0) std.math.pi else null);
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
}

fn stepLocked(g: *Game, dt: f32, speed: f32, dir: rl.Vector3, faceYaw: f32) void {
    const moved = speed * dt;
    g.hero.pos.x = mathx.clampF(g.hero.pos.x + dir.x * moved, -game.PLAY_HALF, game.PLAY_HALF);
    g.hero.pos.z = mathx.clampF(g.hero.pos.z + dir.z * moved, -game.PLAY_HALF, game.PLAY_HALF);
    g.hero.facing = faceYaw;
    g.hero.update(dt, moved, speed, mathx.headingXZ(dir));
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
}

/// THE SCREENSHOT MUST HAPPEN BEFORE `endDrawing`, which SWAPS the buffers: `takeScreenshot` reads the
/// CURRENT framebuffer, so after the swap it reads the PREVIOUS frame.
fn snap(name: [:0]const u8) void {
    rl.gl.rlDrawRenderBatchActive();
    rl.takeScreenshot(name);
    rl.endDrawing();
}

fn shoot(g: *Game, name: [:0]const u8) void {
    drawScene(g);
    hud(g, SHOT_DT); // the fixed harness timestep — the HP chip trail stays reproducible
    snap(name);
}

/// …and the same frame with the FIRE'S chrome on it. The bonfire's list and its wheel are drawn in the loop's
/// rest branch, which `--shot` never runs, so `shoot` alone photographs a man sitting in front of nothing.
fn bonfireShoot(g: *Game, name: [:0]const u8) void {
    drawScene(g);
    game.takeSlotShot(g); // the loop's own order: the slot's thumbnail comes off the BARE frame
    hud(g, SHOT_DT);
    game.drawBonfireForShot(g);
    snap(name);
}

fn advanceAttack(g: *Game, dt: f32, frames: i32) void {
    var k: i32 = 0;
    while (k < frames and g.hero.attacking) : (k += 1) {
        g.hero.updateAttack(dt, game.PLAY_HALF, null);
        g.rig.follow(g.hero.shoulderPoint());
    }
}

fn stepFoe(f: anytype, frames: i32, hero: rl.Vector3) void {
    var k: i32 = 0;
    while (k < frames) : (k += 1) _ = f.update(SHOT_DT, hero, game.PLAY_HALF, .{});
}

/// `stepFoe` for a WARBAND AND WHAT IT THREW: the band drives its own projectiles through `spawnClump`, so
/// a shot of one in flight has to advance both together or the clump never leaves the pouch.
fn stepBandAndShots(g: *Game, frames: i32, hero: rl.Vector3) void {
    var k: i32 = 0;
    while (k < frames) : (k += 1) {
        _ = g.band.update(SHOT_DT, hero, game.PLAY_HALF, .{}, g, game.spawnClump);
        game.stepArrowsForShot(g, SHOT_DT);
    }
}

/// A STAGE THAT DID NOT TAKE IS A SHOT OF THE WRONG THING, silently: a `swapArm` the harness refused
/// leaves every "bow" frame below it photographing a man with a sword.
fn must(ok: bool, what: []const u8) void {
    if (ok) return;
    std.debug.print("--shot: {s}\n", .{what});
    @panic("shot harness: a staged action was refused");
}

/// PUT A NAMED ARMAMENT IN A NAMED HAND. **STRAIGHT INTO THE SLOT, NEVER BY WALKING THE SWAP** — a hand is
/// a PAIR now (`hero.HAND_SLOTS`), so a thing in neither of its two slots never comes round however many
/// times you press it, and the walk this used to do could not terminate.
fn armTo(g: *Game, want: heromod.Armament) void {
    if (g.hero.arm == want) return;
    must(g.hero.equip(heromod.RIGHT, 0, want), "the armament would not go in the right hand");
}

fn offTo(g: *Game, want: heromod.Armament) void {
    if (g.hero.off == want) return;
    must(g.hero.equip(heromod.LEFT, 0, want), "the armament would not go in the left hand");
}

/// THE CAMERA YAW WITH THE SUN BEHIND IT
pub const LIT_YAW: f32 = 53.0;
/// …and its XZ bearing, DERIVED (`camera.backDir` at pitch 0). Hand-rounded it was already 0.45° out, so
/// moving `LIT_YAW` left every "lit" framing in the file pointing the old way.
pub const LIT_BACK = v3(-mathx.sinf(mathx.radians(LIT_YAW)), 0, -mathx.cosf(mathx.radians(LIT_YAW)));

/// `m` metres from `from` along `dir`, on the ground.
fn along(from: rl.Vector3, dir: rl.Vector3, m: f32) rl.Vector3 {
    return v3(from.x + dir.x * m, 0, from.z + dir.z * m);
}

fn standHero(g: *Game, x: f32, z: f32, faceYaw: f32) void {
    g.hero.pos = mathx.ground(x, z);
    g.hero.facing = faceYaw;
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
}

/// **STANDING HIM ON SCULPTED GROUND TAKES MORE THAN ONE FRAME**, and the reason is written at `delverShots`'
/// own copy of this: `hero.respawnNow` starts a pose CROSS-FADE against a world-space snapshot, `--shot` runs no
/// loop to advance it, and one update leaves him blended toward that snapshot — drawn back at the map's spawn,
/// out of frame. Settled out here, then planted on the ground that is actually there (`mathx.ground` is y = 0).
fn standSettled(g: *Game, x: f32, z: f32, faceYaw: f32) void {
    standHero(g, x, z, faceYaw);
    var k: i32 = 0;
    while (k < 12) : (k += 1) g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pos.y = game.envGroundAt(&g.env, x, z);
    g.hero.pose();
}

fn shootAt(g: *Game, name: [:0]const u8, at: rl.Vector3, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.follow(at);
    shoot(g, name);
}

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

fn shootFoe(g: *Game, f: anytype, name: [:0]const u8, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.follow(f.centerWorld());
    shoot(g, name);
}

fn stagedAttack(g: *Game, kind: heromod.Attack) void {
    g.hero.stam.reset();
    g.hero.startAttack(kind);
}

fn stagedRoll(g: *Game, dir: rl.Vector3) void {
    g.hero.stam.reset();
    g.hero.startRoll(dir);
}

/// A CAST FOR THE CAMERA — the pool is refilled first for `stagedAttack`'s reason: five casts back to back
/// would drain the FP and the last frames would quietly be pictures of a man standing still.
fn stagedCast(g: *Game) void {
    g.hero.fp.reset();
    must(g.hero.requestCast(), "the cast would not start");
}

/// Frames on man AND rod: a raised cast is half a body taller than the body, so aiming at the shoulder alone
/// runs the rod off the top of the picture.
fn wandFrame(g: *Game) rl.Vector3 {
    return mathx.lerpV(g.hero.shoulderPoint(), g.hero.wandTipWorld(), 0.5);
}

/// The last frame BEFORE the bolt leaves — the only one the gather's ramp and the light's swell can be judged
/// on, since the throw is what spends the charge.
fn castToCharged(g: *Game, dt: f32) void {
    var k: i32 = 0;
    while (k < 120) : (k += 1) {
        if (g.hero.chargeFill() >= 0.92) return;
        g.hero.updateCast(dt, null);
        must(!g.hero.thrown, "the charge never topped out before the throw");
    }
    must(false, "the cast never charged");
}

/// Drive a live cast to the frame the bolt leaves and stop there — the one frame that has to prove the arm
/// is over his head. Returns having ALREADY advanced past the throw, so `thrown` is spent.
fn castToThrow(g: *Game, dt: f32) void {
    var k: i32 = 0;
    while (k < 120) : (k += 1) {
        g.hero.updateCast(dt, null);
        if (g.hero.thrown) return;
    }
    must(false, "the cast never threw the bolt");
}

// The world tour judges REGIONS; retuning one MODEL needs the model by itself.
pub fn runPropShots(g: *Game) void {
    std.fs.cwd().makePath("shots/props") catch {};
    g.drawDt = SETTLE_DT;
    g.menu.screen = .closed;
    g.retro.allOff();
    // No foes in the portraits — a toad idling into a wide framing reads as part of the model.
    game.clearFoesForShot(g);
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
    if (g.warren.n == 0 or g.line.n == 0 or g.grief.n == 0) {
        std.debug.print(
            "--shot needs at least one of each foe in {s} (have {d} toads, {d} archers, {d} ogres)\n",
            .{ worldfmt.START_MAP, g.warren.n, g.line.n, g.grief.n },
        );
        @panic("shot harness: the map posts no foes to photograph");
    }
    const dt: f32 = SHOT_DT;
    g.drawDt = SETTLE_DT;
    g.menu.screen = .closed;
    g.retro.allOff();
    // THE HOUR IS PINNED AND THE CLOCK IS STOPPED. Every frame below is framed off the sun's bearing
    // (`LIT_YAW`) and the palette was measured against that one light; a running clock re-lights the
    // sequence as it goes and no two judgements are made under the same sky.
    game.pinHourForShot(g, game.daynight.SHOT_HOUR);

    g.hero.pos = mathx.ground(0, 26); // long runway of −Z travel ahead
    var i: i32 = 0;
    while (i < 40) : (i += 1) stepWorld(g, dt, WALK_SPEED); // warm up: moving→1, phase settles

    // (name, yaw°, pitch, dist, frames before the shot, speed). yaw 90 = profile, 0 = front, 180 = back.
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

    // Locked-on footing: facing HOLDS on −Z while travel goes sideways/backward.
    const lockedStages = [_]struct { name: [:0]const u8, yaw: f32, pitch: f32, dist: f32, phTgt: f32, dx: f32, dz: f32 }{
        .{ .name = "shots/38a_strafe_stepout.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.50, .dx = 1, .dz = 0 }, // the out-step LANDS: right foot wide, widest straddle
        .{ .name = "shots/38b_strafe_apart.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.57, .dx = 1, .dz = 0 }, // double support, planted APART, weight transferring
        .{ .name = "shots/38c_strafe_crossing.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.81, .dx = 1, .dz = 0 }, // LEFT leg airborne mid-CROSS: hip flexed, knee up, passing in FRONT
        .{ .name = "shots/38d_strafe_crossed.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.02, .dx = 1, .dz = 0 }, // CROSSED: left foot planted PAST the right — the X
        .{ .name = "shots/38e_strafe_uncross.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.31, .dx = 1, .dz = 0 }, // the UNCROSS: right leg airborne, passing BEHIND the crossed leg
        .{ .name = "shots/38f_strafe_crossed_3q.png", .yaw = 40, .pitch = 0.13, .dist = 4.2, .phTgt = 0.02, .dx = 1, .dz = 0 }, // the X again from three-quarters — the cross must read off-axis too
        .{ .name = "shots/38g_strafe_crossing_3q.png", .yaw = 40, .pitch = 0.13, .dist = 4.2, .phTgt = 0.81, .dx = 1, .dz = 0 },
        .{ .name = "shots/39a_backpedal_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .phTgt = 0.05, .dx = 0, .dz = 1 }, // backpedal: the toe-reach plant
        .{ .name = "shots/39b_backpedal_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .phTgt = 0.55, .dx = 0, .dz = 1 },
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

    // Shot off a FIXED camera, which is most of the test: a camera that followed him up would hold him
    // dead centre and photograph a world sliding down. Pinned to the ground he left, the arc is the
    // subject. Down the field from the fire, or the wanderer at it fills a third of the frame.
    standHero(g, 0, -2, std.math.pi);
    g.rig.yaw = mathx.radians(90); // the roll's own framing: he travels −Z, so 90 is a clean profile
    g.rig.pitch = 0.06; // near level: height reads against the horizon, and from above it reads as nothing
    g.rig.dist = 6.4;
    // …AIMED AT THE MIDDLE OF THE ARC: he covers RUN_SPEED × JUMP_AIR, so a lens pinned to the takeoff
    // walks him out of frame by the landing.
    const jumpGround = mathx.addV(
        g.hero.shoulderPoint(),
        v3(0, 0, -RUN_SPEED * heromod.JUMP_AIR * 0.5),
    );
    must(g.hero.startJump(v3(0, 0, -1), RUN_SPEED), "the jump would not start");
    // AIMED OFF THE ARC'S OWN NUMBERS, never literal frames: each stage is a FRACTION of the flight, and
    // the apex is 0.5 because that is where v passes through zero (t = v0/g = JUMP_AIR/2). As frame counts
    // these stop bracketing the arc the moment `JUMP_AIR` or `SHOT_DT` moves.
    const jumpStages = [_]struct { name: [:0]const u8, at: f32 }{
        .{ .name = "shots/9a_jump_drive.png", .at = 0.15 }, // leaving: legs extended behind, arms thrown up
        .{ .name = "shots/9b_jump_apex.png", .at = 0.50 }, // the top — knees tucked, the one frame v = 0
        .{ .name = "shots/9c_jump_reach.png", .at = 0.80 }, // coming down: legs under him, toes up to receive
    };
    var flown: f32 = 0;
    for (jumpStages) |st| {
        const want = st.at * heromod.JUMP_AIR;
        while (flown < want and g.hero.airborne()) : (flown += dt) game.stepAirForShot(g, dt);
        g.rig.follow(jumpGround); // …the ground he LEFT, not the shoulder he is on
        shoot(g, st.name);
    }
    // …and the ABSORB, which is the whole weight of the thing: run him down to the deck, then on to where the
    // sink is at its LOWEST (`hero.LAND_SINK_AT` of `LAND_DUR`) rather than the frame it started arriving on.
    while (g.hero.airborne()) game.stepAirForShot(g, dt);
    var landT: f32 = 0;
    while (landT < heromod.LAND_SINK_DEEPEST) : (landT += dt) {
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
    }
    g.rig.follow(jumpGround);
    shoot(g, "shots/9d_jump_land.png");

    // Light slash from the SWORD side — the left hides the windup behind the torso.
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

    // **THE SAME SWING FROM THE OTHER SHOULDER** (`hero.placeSword`). The blade is a rig BONE that used to be
    // welded to the right wrist, so this is the shot that says the mirror is real: the sword has to be IN the
    // left fist and the arc has to come across the other way, off the same keys and the same clocks. Shot from
    // the mirrored bearing, or the swing hides behind the torso exactly as the right-hand one does at 270.
    g.hero.arm = .shield;
    g.hero.off = .sword;
    g.rig.yaw = mathx.radians(-30);
    stagedAttack(g, .light);
    advanceAttack(g, dt, 10);
    shoot(g, "shots/15L_atk_left_wind.png");
    advanceAttack(g, dt, 7); // through the whip peak, where the blade is level and the capsule is live
    shoot(g, "shots/15L_atk_left_peak.png");
    advanceAttack(g, dt, 999);
    g.hero.arm = .sword;
    g.hero.off = .shield;

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

    {
        var k: i32 = 0;
        while (k < 45) : (k += 1) stepWorld(g, dt, 0); // out of the last swing's recovery first
        g.hero.pos = mathx.ground(0, 4);
        g.hero.stam.reset();
        g.hero.facing = mathx.headingXZ(LIT_BACK);
        g.hero.setGuard(true);
        k = 0;
        while (k < 16) : (k += 1) { // let the stance blend settle (guardB eases in over ~0.1 s)
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20a_guard_front.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20b_guard_3q.png", g.hero.shoulderPoint(), LIT_YAW + 42, 0.09, 3.0);
        shootPortrait(g, "shots/20c_guard_side.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.09, 3.0);
        // The frame right after the recoil fires — the one that has to say HELD rather than hurt.
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
        g.hero.setGuard(false);
        g.hero.stam.reset();
        g.hero.hurtFlash = 0;
        g.hero.vit = heromod.freshVitals(g.hero.sheet);
        k = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
    }

    {
        // Started COLD, from no guard at all: L2 is the shield's own skill and never asks whether the
        // boards were already up.
        var k: i32 = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
        g.hero.pos = mathx.ground(0, 4);
        g.hero.stam.reset();
        g.hero.facing = mathx.headingXZ(LIT_BACK);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        must(g.hero.requestParry(), "the parry would not start");
        while (g.hero.parrying and g.hero.parryT < heromod.PARRY_DUR * heromod.PARRY_PUNCH_AT) {
            g.hero.updateParry(dt, null);
        }
        must(g.hero.parryLive(), "the shove peaked outside its own catch window");
        shootPortrait(g, "shots/20l_parry_front.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        // …and the CATCH. Shot four frames in, not one: on the frame `noteParry` fires, every spark and the
        // bloom are still at the same point and read as a single puff.
        g.hero.noteParry();
        k = 0;
        while (k < 4) : (k += 1) g.hero.updateParry(dt, null);
        shootPortrait(g, "shots/20m_parry_catch.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20n_parry_catch_3q.png", g.hero.shoulderPoint(), LIT_YAW + 42, 0.09, 3.0);
        while (g.hero.parrying) g.hero.updateParry(dt, null);
        // THE ARC ITSELF, AND IT TAKES THREE FRAMES FROM STRAIGHT DOWN. A swipe is a LATERAL sweep, so one
        // frame cannot show it and the front view foreshortens it to nothing: these are the coil, the crossing
        // (which is the frame that catches) and the follow-through, off the same run.
        k = 0;
        while (k < 20) : (k += 1) stepWorld(g, dt, 0);
        g.hero.pos = mathx.ground(0, 4);
        g.hero.facing = mathx.headingXZ(LIT_BACK);
        g.hero.stam.reset();
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        must(g.hero.requestParry(), "the parry would not start for the arc");
        for ([_]struct { u: f32, name: [:0]const u8 }{
            .{ .u = heromod.PARRY_COIL_AT, .name = "shots/20o_parry_arc_coil.png" },
            .{ .u = heromod.PARRY_PUNCH_AT, .name = "shots/20p_parry_arc_cross.png" },
            .{ .u = heromod.PARRY_SWEEP_END, .name = "shots/20q_parry_arc_follow.png" },
        }) |step| {
            while (g.hero.parrying and g.hero.parryT < heromod.PARRY_DUR * step.u) g.hero.updateParry(dt, null);
            shootPortrait(g, step.name, g.hero.shoulderPoint(), LIT_YAW, 1.32, 3.4);
        }
        while (g.hero.parrying) g.hero.updateParry(dt, null);
        g.hero.stam.reset();
        k = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
    }

    {
        var k: i32 = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
        g.hero.pos = mathx.ground(0, 4);
        g.hero.stam.reset();
        g.hero.facing = mathx.headingXZ(LIT_BACK); // looking down the lens — the FRONT view
        armTo(g, .bow);
        // THE LOW CARRY first: bow in the right fist, string slack, and NO SHIELD on the left arm — which is the whole mechanic, and the one thing a single frame can prove.
        k = 0;
        while (k < 20) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20f_bow_carry.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20g_bow_carry_side.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.09, 3.0);
        g.hero.setAim(true);
        k = 0;
        while (k < 24) : (k += 1) { // let the stance blend settle (aimB eases in, like guardB)
            g.hero.setAim(true);
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20h_bow_aim_front.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20i_bow_aim_3q.png", g.hero.shoulderPoint(), LIT_YAW + 42, 0.09, 3.0);
        // The SIDE is the one that shows the draw length — how far back the hand actually is.
        shootPortrait(g, "shots/20j_bow_aim_side.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.08, 3.2);
        shootPortrait(g, "shots/20k_bow_string.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.02, 1.5);
        // THE AIMED LOOSE, caught on the frame the string snaps home: the shaft is gone, the bow arm has bounced forward off the release, and the nocked arrow is no longer drawn.
        g.hero.requestShot(true);
        var fired = false;
        k = 0;
        while (k < 90 and !fired) : (k += 1) {
            g.hero.setAim(true);
            g.hero.updateShot(dt, null);
            if (g.hero.loosed) fired = true;
        }
        must(fired, "the aimed loose never let the shaft go");
        g.hero.updateShot(dt, null);
        shootPortrait(g, "shots/20l_bow_loose.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.08, 3.2);
        g.hero.setAim(false);
        k = 0;
        while (k < 40) : (k += 1) {
            g.hero.setAim(false);
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        g.hero.stam.reset();
        g.hero.requestShot(false);
        k = 0;
        while (k < 5) : (k += 1) g.hero.updateShot(dt, null);
        shootPortrait(g, "shots/20m_bow_snap.png", g.hero.shoulderPoint(), LIT_YAW + 60, 0.09, 3.2);
        while (g.hero.shooting) g.hero.updateShot(dt, null);
        g.hero.stam.reset();
        g.hero.setAim(true);
        k = 0;
        while (k < 24) : (k += 1) {
            g.hero.setAim(true);
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        game.shootShaftForShot(g, SHOT_DOWNRANGE, .plain);
        k = 0;
        while (k < 7) : (k += 1) game.stepShaftsForShot(g, dt);
        shootPortrait(g, "shots/20n_bow_shaft.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.06, 6.0);
        // THE FIRE ARROW, in the SAME framing as the plain shaft above so the two are comparable, and
        // then cropped onto the head itself — the flame wad is 10 cm of the frame at 6 m.
        game.clearShaftsForShot(g);
        game.shootShaftForShot(g, SHOT_DOWNRANGE, .fire);
        k = 0;
        while (k < 7) : (k += 1) game.stepShaftsForShot(g, dt);
        shootPortrait(g, "shots/20s_fire_shaft.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.06, 6.0);
        // …from the FRONT QUARTER, not side-on: the streak lies down the flight line, so a broadside crop
        // is mostly trail with the head buried in it.
        if (game.flyingPointForShot(g, .firearrow)) |at| shootPortrait(g, "shots/20t_fire_head.png", at, LIT_YAW + 20, 0.04, 1.3);
        game.clearShaftsForShot(g);
        shootClear(g, "shots/20o_bow_hud.png", LIT_YAW + 150, 0.18, 4.6);
        // …AND THE SAME CORNER AFTER DARK, which is the only frame the clock dial's MOON face is ever visible
        // in: everything else here is pinned at the golden anchor, so without this the night half of the dial is
        // drawn by nobody's eye. Back to the anchor straight after — every shot below is judged under it.
        game.pinHourForShot(g, 23.4);
        shootClear(g, "shots/20o2_bow_hud_night.png", LIT_YAW + 150, 0.18, 4.6);
        game.pinHourForShot(g, game.daynight.SHOT_HOUR);
        g.hero.setAim(true);
        k = 0;
        while (k < 24) : (k += 1) {
            g.hero.setAim(true);
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        g.rig.aimB = g.hero.aimB;
        shootClear(g, "shots/20p_bow_aimcam.png", LIT_YAW + 150, 0.18, 4.6);
        shootClear(g, "shots/20q_bow_ammo.png", LIT_YAW + 150, 0.18, 4.6);
        const hadArrows = g.hero.quiver.ready();
        g.hero.quiver.arrows = 0;
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootClear(g, "shots/20r_bow_ammo_dry.png", LIT_YAW + 150, 0.18, 4.6);
        g.hero.quiver.arrows = hadArrows;
        // …and the ammo box carrying the OTHER arrow: the count is the fire quiver's and the icon burns.
        must(g.hero.cycleArrow(), "the arrow would not cycle");
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootClear(g, "shots/20u_fire_ammo.png", LIT_YAW + 150, 0.18, 4.6);
        must(g.hero.cycleArrow(), "the arrow would not cycle back");
        g.rig.aimB = 0;
        // PUT IT AWAY, and leave the field as the rest of the harness expects to find it.
        g.hero.setAim(false);
        while (g.hero.shooting) g.hero.updateShot(dt, null);
        armTo(g, .sword);
        game.clearShaftsForShot(g);
        g.hero.stam.reset();
        g.hero.vit = heromod.freshVitals(g.hero.sheet);
        k = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
    }

    // The pair of sweeps is shot because "it alternates" is the one claim a single frame cannot make.
    {
        var k: i32 = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
        g.hero.pos = mathx.ground(0, 4);
        g.hero.facing = mathx.headingXZ(LIT_BACK); // down the lens, and lit from over the camera's shoulder
        offTo(g, .wand);
        k = 0;
        while (k < 20) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20v_wand_carry.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        // …from the WAND's side. At +78 the camera is off his sword shoulder and the torso hides the whole arm.
        shootPortrait(g, "shots/20w_wand_carry_side.png", g.hero.shoulderPoint(), LIT_YAW - 78, 0.09, 3.0);
        // The raise partway up — the anticipation has to read as an arm going somewhere.
        stagedCast(g);
        k = 0;
        while (k < 9) : (k += 1) g.hero.updateCast(dt, null);
        shootPortrait(g, "shots/20y_wand_raise.png", wandFrame(g), LIT_YAW + 30, 0.12, 3.2);
        // The charge topped out. WIDE and SHALLOW rather than a portrait: what is judged here is how far the
        // violet reaches across the ground and whether his front takes it, and a portrait crops the pool off.
        castToCharged(g, dt);
        shootPortrait(g, "shots/20y2_wand_charged.png", wandFrame(g), LIT_YAW + 30, 0.05, 6.5);
        // …and the same instant CLOSE, for the gather itself: the motes are 2 cm across.
        shootPortrait(g, "shots/20y3_wand_gather.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.25);
        castToThrow(g, dt);
        shootPortrait(g, "shots/20z_wand_throw.png", wandFrame(g), LIT_YAW + 30, 0.16, 3.4);
        // The release on that same frame, with the flash, the collar and the flare that fire on it.
        game.clearShaftsForShot(g);
        game.throwBoltForShot(g, SHOT_DOWNRANGE);
        shootPortrait(g, "shots/20z3_wand_release.png", wandFrame(g), LIT_YAW + 30, 0.05, 6.5);
        shootPortrait(g, "shots/20z4_wand_release_head.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.6);
        game.clearShaftsForShot(g);
        // The rod's head is a couple of centimetres, so it needs a crop. Taken OVERHEAD rather than off the
        // carry: down there the tip is at knee height, which buries the camera in dirt and the head in shadow.
        shootPortrait(g, "shots/20x_wand_crop.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.25);
        shootPortrait(g, "shots/20za_wand_throw_front.png", wandFrame(g), LIT_YAW, 0.16, 3.4);
        const firstSide = g.hero.castAlt;
        while (g.hero.casting) g.hero.updateCast(dt, null);
        // Same instant of the stroke, same camera — the pair IS the comparison.
        stagedCast(g);
        castToThrow(g, dt);
        must(g.hero.castAlt != firstSide, "the second cast did not sweep the other way");
        shootPortrait(g, "shots/20zb_wand_throw_alt.png", wandFrame(g), LIT_YAW + 30, 0.16, 3.4);
        shootPortrait(g, "shots/20zc_wand_throw_alt_front.png", wandFrame(g), LIT_YAW, 0.16, 3.4);
        // Thrown WITHOUT letting the cast finish, so the pose is still the throw and the shaft leaves the stone
        // over his head — out of the carry it comes off a wand at knee height and skids away at ankle height.
        game.clearShaftsForShot(g);
        game.throwBoltForShot(g, SHOT_DOWNRANGE);
        k = 0;
        while (k < 9) : (k += 1) game.stepShaftsForShot(g, dt);
        // Framed on the BOLT, not on him: at 30 m/s it has already left any framing that tracks the caster.
        if (game.flyingPointForShot(g, .bolt)) |at| {
            shootPortrait(g, "shots/20zd_wand_bolt.png", at, LIT_YAW + 78, 0.06, 5.0);
            shootPortrait(g, "shots/20ze_wand_bolt_head.png", at, LIT_YAW + 20, 0.04, 1.1);
        }
        game.clearShaftsForShot(g);
        while (g.hero.casting) g.hero.updateCast(dt, null);
        // The HUD cross: a rod in the left slot and the bolt in the sorcery slot, then the same short of FP.
        k = 0;
        while (k < 12) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootClear(g, "shots/20zf_wand_hud.png", LIT_YAW + 150, 0.18, 4.6);
        g.hero.fp.cur = combat.BOLT_FP - 1;
        g.hero.fpRefused = combat.STAM_REFUSE_FLASH; // …and the refusal ring on the FP bar, not the stamina one
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootClear(g, "shots/20zg_wand_hud_dry.png", LIT_YAW + 150, 0.18, 4.6);

        // THE ROOTS — the rod's other sorcery. Same rod, same sweep, and what changes is what comes out of the
        // ground `ROOT_THROW` metres down his facing. The mark is DERIVED (`castRootsForShot` hands it back)
        // rather than written out here, or a retune of the throw distance photographs bare earth.
        g.hero.fp.cur = g.hero.fp.max; // the dry-HUD shot above emptied him
        g.hero.fpRefused = 0;
        must(g.hero.cycleSpell(), "the rod would not change spell");
        // The cross with ROOTS in the sorcery slot, before anything is cast — the picture has to differ.
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootClear(g, "shots/20zg2_roots_hud.png", LIT_YAW + 150, 0.18, 4.6);
        stagedCast(g);
        castToThrow(g, dt);
        const rootsAt = game.castRootsForShot(g);
        // The eruption itself, on the frame the earth goes up.
        shootPortrait(g, "shots/20zg3_roots_erupt.png", rootsAt, LIT_YAW, 0.10, 5.5);
        // …and once they are FULLY UP, which is the only frame the tendrils' shape can be judged on: at the
        // throw they are still scaling out of the dirt. Stepped through `update`, since the sites are aged in
        // the shared prologue and a cast that has ended stops calling `updateCast`.
        k = 0;
        while (k < 26) : (k += 1) {
            if (g.hero.casting) g.hero.updateCast(dt, null) else g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20zg4_roots_stand.png", rootsAt, LIT_YAW, 0.09, 5.8);
        // Thin geometry needs a CROP (AGENTS.md): a tendril is ~4 cm through, so at 1:1 the blunt tip and the
        // side stubs are two pixels each and "it reads as spikes" cannot be judged from the wide shot.
        shootPortrait(g, "shots/20zg5_roots_crop.png", v3(rootsAt.x, rootsAt.y + 0.70, rootsAt.z), LIT_YAW + 34, 0.06, 2.7);
        // Down on the deck, where the split ground meets the tendrils — the read that says they came THROUGH it.
        shootPortrait(g, "shots/20zg6_roots_low.png", v3(rootsAt.x, rootsAt.y + 0.35, rootsAt.z), LIT_YAW - 40, 0.02, 4.0);
        while (g.hero.casting) g.hero.updateCast(dt, null);

        // THE RIME BREATH — the rod's third, and the first thing in the game bar a swing that reaches more
        // than one body. Every frame here is SIDE-ON (`LIT_YAW + 90`) while he faces down `LIT_BACK`, for
        // the ogre's swipe's reason: a cone is a LATERAL fact and head-on it foreshortens to a blob on his
        // face. Framed on the MIDDLE of the cone rather than on him — a lens pinned to the mouth photographs
        // the first metre of a six-metre effect.
        must(g.hero.cycleSpell(), "the rod would not change to the rime");
        g.hero.fp.cur = g.hero.fp.max;
        // ON OPEN GROUND, and this is part of the test rather than housekeeping: the wand block stands him in
        // the ruin avenue, where a six-metre cone is thrown straight into a column — the first pass framed a
        // pillar with a man behind it. The kobolds' own clearing, which is the nearest open ground with the
        // sun on it.
        const rimeAt = mathx.ground(-26.0, 30.0);
        standSettled(g, rimeAt.x, rimeAt.z, mathx.headingXZ(LIT_BACK));
        shootClear(g, "shots/20zj_rime_hud.png", LIT_YAW + 150, 0.18, 4.6);
        const coneMid = v3(
            g.hero.pos.x + LIT_BACK.x * combat.RIME_REACH * 0.45,
            g.hero.pos.y + 1.15,
            g.hero.pos.z + LIT_BACK.z * combat.RIME_REACH * 0.45,
        );
        stagedCast(g);
        castToThrow(g, dt); // …to the frame the cone OPENS, which for this spell throws nothing
        shootPortrait(g, "shots/20zk_rime_open.png", coneMid, LIT_YAW + 90, 0.10, 7.0);
        // …and then at three points ACROSS THE POUR, off `breathU` rather than off frame counts: the stream
        // has to be shown building, at full, and running out, and as literal frames these stop bracketing it
        // the moment `RIME_DUR` moves.
        for ([_]struct { u: f32, name: [:0]const u8 }{
            .{ .u = 0.35, .name = "shots/20zl_rime_pour.png" },
            .{ .u = 0.75, .name = "shots/20zm_rime_reach.png" },
        }) |step| {
            while (g.hero.casting and g.hero.breathU() < step.u) g.hero.updateCast(dt, null);
            must(g.hero.breathLive(), "the pour ended before the beat it was aimed at");
            shootPortrait(g, step.name, coneMid, LIT_YAW + 90, 0.10, 7.0);
        }
        // THIN GEOMETRY NEEDS A CROP: a mote is a couple of centimetres, so whether the stream leaves the
        // ROD'S TIP — and not his hand, his chest or his face — cannot be judged from seven metres out.
        shootPortrait(g, "shots/20zn_rime_nozzle.png", g.hero.breathMouth(), LIT_YAW + 90, 0.06, 1.5);
        // …and the FRONT, which is the one framing that shows the cone's WIDTH rather than its length.
        shootPortrait(g, "shots/20zo_rime_front.png", coneMid, LIT_YAW, 0.16, 6.0);
        while (g.hero.casting) g.hero.updateCast(dt, null);
        // …and the frame after it, which has to say the fold came BACK: the trunk overshoots its rest here.
        var bk: i32 = 0;
        while (bk < 8) : (bk += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20zp_rime_after.png", g.hero.shoulderPoint(), LIT_YAW + 90, 0.10, 3.4);
        // …AND THE COLD ON A BODY: the hold's two faces — the frost coat on the mesh (`gfx.setFrost` off
        // `Chill.frac`) and the rime strip under its floating bar. Stamped directly (`Chill.touch` is the
        // stamp the breath itself uses), and hurt zero seconds ago so the bar is up.
        g.muster.n = 1;
        const chilled = &g.muster.band[0];
        chilled.* = warriormod.Warrior.spawnAs(.shieldman, along(rimeAt, LIT_BACK, 3.2), mathx.headingXZ(mathx.scaleV(LIT_BACK, -1)), 1.0, 0.3);
        chilled.chill.touch();
        chilled.vit.sinceHurt = 0;
        shootFoe(g, chilled, "shots/20zq_rime_chilled.png", LIT_YAW, 0.10, 4.6);
        g.muster.n = 0;
        g.hero.fp.cur = g.hero.fp.max;

        // THE LEVIN STRIKE — the rod's fourth, and the one that DOES NOT TRAVEL. There is no flight to
        // photograph, so the whole spell is the frame it lands on: the stroke down its own segment and the burst
        // where it ends. Shot SIDE-ON like the cone, because a stroke is a vertical fact and head-on it is a dot.
        must(g.hero.cycleSpell(), "the rod would not change to the levin");
        standSettled(g, rimeAt.x, rimeAt.z, mathx.headingXZ(LIT_BACK));
        shootClear(g, "shots/20zr_levin_hud.png", LIT_YAW + 150, 0.18, 4.6);
        // **A BODY TO STRIKE, or the picture has nothing to end on.** The segment is derived off the victim
        // (`game.strikeSegment`), so with the field empty the stroke is drawn on open air at half the reach and
        // the one thing this frame exists to show — that it lands on somebody — is exactly what is missing.
        g.muster.n = 1;
        const struck = &g.muster.band[0];
        struck.* = warriormod.Warrior.spawnAs(.shieldman, along(rimeAt, LIT_BACK, 5.0), mathx.headingXZ(mathx.scaleV(LIT_BACK, -1)), 1.0, 0.3);
        stagedCast(g);
        castToThrow(g, dt);
        game.releaseSpellForShot(g);
        shootFoe(g, struck, "shots/20zs_levin_strike.png", LIT_YAW + 90, 0.10, 6.4);
        // THIN GEOMETRY NEEDS A CROP: a spark is two centimetres and dead in a twentieth of a second, so whether
        // the stroke is a TORN line or a straight run of dots cannot be judged from six metres out.
        shootPortrait(g, "shots/20zt_levin_crop.png", struck.centerWorld(), LIT_YAW + 90, 0.06, 2.6);
        while (g.hero.casting) g.hero.updateCast(dt, null);

        // THE SIPHON — the fifth, and the only effect in the game that runs the wrong way up the line: motes off
        // the BODY, solved to arrive at the stone. Hurt him first, or a full bar has nothing to give back into
        // and the one thing the spell is for cannot be seen to have happened.
        must(g.hero.cycleSpell(), "the rod would not change to the siphon");
        g.hero.fp.cur = g.hero.fp.max;
        g.hero.vit.hp = g.hero.vit.hpMax * 0.45;
        stagedCast(g);
        castToThrow(g, dt);
        game.releaseSpellForShot(g);
        // Framed on the GAP between the two, since the drain is the line and not either end of it.
        shootPortrait(g, "shots/20zu_siphon_draw.png", mathx.lerpV(g.hero.shoulderPoint(), struck.centerWorld(), 0.5), LIT_YAW + 90, 0.10, 5.2);
        shootClear(g, "shots/20zv_siphon_hud.png", LIT_YAW + 150, 0.18, 4.6);
        while (g.hero.casting) g.hero.updateCast(dt, null);
        g.muster.n = 0;
        g.hero.vit.hp = g.hero.vit.hpMax;
        g.hero.fp.reset();
        must(g.hero.cycleSpell(), "the rod would not change back"); // …and the block below expects the bolt
        // Walking, at two points HALF A STRIDE apart: one frame cannot show that the carry damps the arm's swing
        // without welding it. LAST in the block, because `stepWorld` forces travel down −Z and takes the lit
        // facing every shot above depends on. Started at z=6 rather than the gait block's z=26 — that end of the
        // runway sits in a cliff's shadow and a warm-up this short never walks out of it.
        g.hero.pos = mathx.ground(0, 6);
        k = 0;
        while (k < 40) : (k += 1) stepWorld(g, dt, heromod.WALK_SPEED);
        shootPortrait(g, "shots/20zh_wand_walk.png", g.hero.shoulderPoint(), LIT_YAW, 0.16, 4.2);
        // Measured off the phase, which WRAPS — a bare `< 0.5` test can already be satisfied and shoot twice.
        const ph0 = g.hero.phase;
        k = 0;
        while (k < 240) : (k += 1) {
            stepWorld(g, dt, heromod.WALK_SPEED);
            if (@mod(g.hero.phase - ph0 + 1.0, 1.0) >= 0.5) break;
        }
        shootPortrait(g, "shots/20zi_wand_walk_b.png", g.hero.shoulderPoint(), LIT_YAW, 0.16, 4.2);
        // **THE SAME ROD IN THE OTHER HAND** — every armament may sit in either (`hero.Armament`), and this
        // is the pass that says so about the one whose whole picture is a point in the world. Three things
        // had to be handed and only the first two were: the MESH (`drawHand`), the CARRY ARM
        // (`poseWandArm`), and the TIP everything actually comes out of (`wandTipWorld`) plus the throw that
        // moves it (`poseCast`). So a rod equipped right looked entirely correct standing still and then
        // gathered, threw and breathed out of the empty left fist — which no left-handed frame can show.
        g.hero.fp.reset();
        g.hero.fpRefused = 0;
        offTo(g, .sword);
        armTo(g, .wand);
        must(g.hero.wandOut() and !g.hero.wandLeft(), "the rod would not go in the right hand");
        standSettled(g, 0, 4, mathx.headingXZ(LIT_BACK));
        // From the ROD's side, which is now the other one: at LIT_YAW − 78 the torso hid the left arm, so the
        // right arm's mirror is read from LIT_YAW + 78.
        shootPortrait(g, "shots/20zr_wand_right_carry.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.09, 3.0);
        stagedCast(g);
        castToCharged(g, dt);
        // THE ONE FRAME THE BUG WAS: the gather is a shell of motes on the stone, so a tip read off the wrong
        // wrist puts the whole charge in his other hand and this crop is empty.
        shootPortrait(g, "shots/20zs_wand_right_gather.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.25);
        castToThrow(g, dt);
        shootPortrait(g, "shots/20zt_wand_right_throw.png", wandFrame(g), LIT_YAW - 30, 0.16, 3.4);
        game.clearShaftsForShot(g);
        game.throwBoltForShot(g, SHOT_DOWNRANGE);
        shootPortrait(g, "shots/20zu_wand_right_release.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.6);
        game.clearShaftsForShot(g);
        while (g.hero.casting) g.hero.updateCast(dt, null);

        // …AND THE BOARDS IN THE OTHER HAND, the same three-part failure one armament along: the guard and
        // the parry both mimed the LEFT arm, and the sparks came off a hub welded to that wrist.
        armTo(g, .shield);
        offTo(g, .sword);
        must(g.hero.canGuard() and !g.hero.shieldLeft(), "the boards would not go in the right hand");
        standSettled(g, 0, 4, mathx.headingXZ(LIT_BACK));
        g.hero.setGuard(true);
        k = 0;
        while (k < 24) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20zv_guard_right.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 3.4);
        g.hero.setGuard(false);
        must(g.hero.requestParry(), "the parry was refused in the right hand");
        while (!g.hero.parryLive()) g.hero.updateParry(dt, null);
        g.hero.noteParry(); // the shower, off `shieldFaceWorld` — the half that was reading the other wrist
        k = 0;
        while (k < 3) : (k += 1) g.hero.updateParry(dt, null);
        shootPortrait(g, "shots/20zw_parry_right.png", g.hero.shieldFaceWorld().at, LIT_YAW, 0.10, 2.4);
        while (g.hero.parrying) g.hero.updateParry(dt, null);

        // …and the BELL, which fails the other way round: its ring was welded to the RIGHT arm, so the one
        // hand to photograph it in is the left.
        armTo(g, .sword);
        offTo(g, .bell);
        must(g.hero.bellOut() and g.hero.bellLeft(), "the bell would not go in the left hand");
        standSettled(g, 0, 4, mathx.headingXZ(LIT_BACK));
        g.hero.fp.reset(); // a ringing is the biggest single bill in the game and the rod above spent the pool
        must(g.hero.requestRing(), "the ring was refused in the left hand");
        // Shot at the NOTE, which is where the flick is — `rang` is that one frame.
        while (g.hero.ringing and !g.hero.rang) g.hero.updateRing(dt, null);
        shootPortrait(g, "shots/20zx_bell_left.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 3.2);
        while (g.hero.ringing) g.hero.updateRing(dt, null);

        // PUT IT ALL AWAY and leave the field as the rest of the harness expects to find it.
        g.hero.fp.reset();
        g.hero.fpRefused = 0;
        armTo(g, .sword);
        offTo(g, .shield);
        g.hero.stam.reset();
        k = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
    }

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
        g.hero.facing = mathx.headingXZ(mathx.subV(mathx.zero3, g.hero.pos)); // face the toad at origin
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();

        const behind = mathx.ground(0, -60); // "hero" down the hop heading (−Z): coil re-aim ≈ heading
        const front = mathx.ground(0, 60); // "hero" out front (+Z): idle/gape keep facing the camera side

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z; profiled from the side
        stepFoe(f, 8, front); // settle to idle (far → won't wake)
        shootFoe(g, f, "shots/20_frog_idle.png", 90, 0.10, 2.7);
        shootFoe(g, f, "shots/21_frog_scale.png", 35, 0.16, 4.7); // with the hero, for size read

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -2.2), game.PLAY_HALF, false);
        stepFoe(f, 6, behind); // mid coil (loaded, knees stacked)
        shootFoe(g, f, "shots/22_frog_coil.png", 90, 0.08, 3.0);
        stepFoe(f, 22, behind); // arc apex (stretched, airborne)
        shootFoe(g, f, "shots/23_frog_leap.png", 90, 0.05, 3.4);
        stepFoe(f, 22, behind); // landing splat
        shootFoe(g, f, "shots/24_frog_land.png", 90, 0.09, 3.1);

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -3.6), game.PLAY_HALF, true);
        stepFoe(f, 26, behind); // deep into the long telegraph coil (loaded, dust flying, throat charged)
        shootFoe(g, f, "shots/25_frog_lunge_wind.png", 55, 0.09, 3.3);
        stepFoe(f, 60, behind); // through flight + heavy landing, ~0.3 s into recovery
        shootFoe(g, f, "shots/26_frog_recover.png", 70, 0.13, 3.2);

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.startChomp();
        stepFoe(f, 22, front); // near full gape (charge gathering, drool stringing)
        shootFoe(g, f, "shots/27_frog_gape.png", 162, 0.06, 2.2); // front 3/4, close — peer into the maw
        stepFoe(f, 6, front); // jaws slamming
        shootFoe(g, f, "shots/28_frog_snap.png", 162, 0.06, 2.2);

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

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        stepFoe(f, 8, front);
        g.hero.pos = mathx.ground(1.7, 3.6);
        g.hero.facing = mathx.headingXZ(mathx.subV(mathx.zero3, g.hero.pos));
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.lock = .{ .kind = .toad, .idx = 0 };
        g.rig.yaw = mathx.headingXZ(mathx.subV(mathx.zero3, g.hero.pos));
        g.rig.pitch = 0.16;
        g.rig.dist = 5.4;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/30_lockon.png");
        g.lock = null;
    }

    {
        const f = &g.warren.frogs[0];
        const front = mathx.ground(0, 60); // "hero" out front so a reeling toad faces the camera

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
        // MID-FADE, which is the only frame that shows the chrome going rather than gone: stepped in SECONDS
        // off the hero's own death clock so it stays on the same beat if `HUD_FADE_DUR` is ever retuned.
        sk = 0;
        while (@as(f32, @floatFromInt(sk)) * dt < game.HUD_FADE_DUR * 0.5) : (sk += 1) g.hero.updateDeath(dt);
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/36a_hero_death_hudfade.png");
        while (sk < 130) : (sk += 1) g.hero.updateDeath(dt); // deep into the card: heap + YOU DIED full
        g.rig.pitch = 0.22;
        g.rig.dist = 5.2;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/36_hero_death.png");
        while (g.hero.dead) g.hero.updateDeath(dt); // run out → respawn (restores clean state)

        g.hero.hurtFlash = 0; // clear any leftover flash from the death shot (harness never ticks it)
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.vit.hp = f.vit.hpMax * 0.45;
        f.vit.sinceHurt = 0;
        stepFoe(f, 4, front);
        g.hero.pos = mathx.ground(2.4, 4.2);
        g.hero.facing = mathx.headingXZ(mathx.subV(mathx.zero3, g.hero.pos));
        g.hero.vit.hp = g.hero.vit.hpMax * 0.55;
        g.hero.stam.spend(combat.STAM_ROLL + combat.STAM_HEAVY);
        g.hero.souls.gain(ogremod.SOULS + 2 * frogmod.SOULS);
        var rk: i32 = 0;
        while (rk < 14) : (rk += 1) g.hero.souls.tick(SHOT_DT);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.rig.yaw = mathx.radians(202);
        g.rig.pitch = 0.16;
        g.rig.dist = 6.4;
        g.rig.follow(f.centerWorld());
        shoot(g, "shots/37_hp_bars.png");

        g.hero.stam.spend(combat.STAM_MAX);
        g.hero.startRoll(v3(0, 0, -1));
        std.debug.assert(!g.hero.rolling); // the whole point: an empty pool cannot roll
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shoot(g, "shots/37b_stam_locked.png");

        var st: usize = 0;
        while (g.hero.stam.frac() < 0.2 and st < 600) : (st += 1) g.hero.stam.tick(SHOT_DT, false, false);
        std.debug.assert(g.hero.stam.cur > 0 and !g.hero.stam.canSprint());
        g.hero.stamRefused = 0; // no refusal flash — the mark has to carry this on its own
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shoot(g, "shots/37c_stam_winded.png");

        g.hero.vit.hp = g.hero.vit.hpMax;
        g.hero.stam.reset();
        g.hero.stamRefused = 0;
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
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
        g.arrows[0] = archermod.launchArrow(a.nockWorld(), mathx.ground(0, 15));
        var m: i32 = 0;
        while (m < 8) : (m += 1) archermod.stepArrow(&g.arrows[0], mathx.ground(0, 15), HERO_CENTER_Y, g.env.groundAt(g.arrows[0].pos.x, g.arrows[0].pos.z), false, arrowCover(g, &g.arrows[0], dt), dt);
        shootFoe(g, a, "shots/44_archer_loose.png", 90, 0.05, 5.2); // side-on: the shaft crosses the frame
        g.arrows[0] = .{};
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var j: i32 = 0;
        while (j < 20) : (j += 1) _ = a.update(dt, mathx.ground(0, 60), game.PLAY_HALF, .{}); // hero far → stays idle
        shootFoe(g, a, "shots/43_archer_idle_side.png", 90, 0.08, 4.6);
        // The SHARED walk/strafe (hero.legChain): crowd it so it kites, catch it mid-backpedal.
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var w2: i32 = 0;
        while (w2 < 60) : (w2 += 1) _ = a.update(dt, mathx.ground(0, 3), game.PLAY_HALF, .{}); // hero crowds → back off
        shootFoe(g, a, "shots/45_archer_kite.png", 90, 0.09, 5.4);
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var bs: i32 = 0;
        while (bs < 400 and !a.airborne()) : (bs += 1) _ = a.update(dt, mathx.ground(0, 2.2), game.PLAY_HALF, .{});
        var bp: i32 = 0;
        while (bp < 7) : (bp += 1) _ = a.update(dt, mathx.ground(0, 2.2), game.PLAY_HALF, .{});
        shootFoe(g, a, "shots/45b_archer_backstep.png", 90, 0.06, 6.0);
        var bl: i32 = 0;
        while (bl < 18) : (bl += 1) _ = a.update(dt, mathx.ground(0, 2.2), game.PLAY_HALF, .{});
        shootFoe(g, a, "shots/45c_archer_backstep_land.png", 90, 0.06, 6.0);
        // THE BODY GOING (`foe.dissipate`) — caught well past `DEATH_DUR` so the bone-dust and the bonfire
        // motes are up, which is the whole point of the frame: this is the one skeleton that used to fade
        // out into nothing while its twin shed bone.
        const ac = mathx.ground(-26.0, 30.0);
        a.* = archermod.Archer.spawn(ac, 0, 1.0, 0.0);
        a.debugKill();
        stepFoe(a, 95, mathx.ground(0, 60)); // ~1.58 s: the collapse is over and the cloud is at full
        standHero(g, ac.x + 2.2, ac.z - 1.4, std.math.pi);
        shootFoe(g, a, "shots/45d_archer_dissolve.png", LIT_YAW, 0.42, 3.4);
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var lk: i32 = 0;
        while (lk < 24) : (lk += 1) _ = a.update(dt, mathx.ground(0, 60), game.PLAY_HALF, .{}); // settle to idle
        g.hero.pos = mathx.ground(1.8, 6.0);
        g.hero.facing = mathx.headingXZ(mathx.subV(mathx.zero3, g.hero.pos));
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        g.lock = .{ .kind = .archer, .idx = 0 };
        g.rig.yaw = mathx.headingXZ(mathx.subV(mathx.zero3, g.hero.pos));
        g.rig.pitch = 0.16;
        g.rig.dist = 6.2;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/46_archer_lockon.png");
        g.lock = null;
        // Every foe back to its home so none intrudes on the shots below
        game.rehomeFoesForShot(g);
    }

    // A PORTRAIT SPOT NEEDS THE CAMERA'S ROOM, NOT JUST THE SUBJECT'S.
    {
        const o = &g.grief.ogres[0];
        const oc = mathx.ground(-26.0, 14.0);
        const far = v3(oc.x, 0, oc.z + 80.0); // sensed hero far ahead → holds state, faces +Z

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 54, far); // settle into idle, landing mid weight-shift (one leg relaxed)
        g.hero.pos = mathx.ground(oc.x - 22.0, oc.z);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootFoe(g, o, "shots/47_ogre_idle.png", 55, 0.14, 13.0);
        // The framing `hud.FOE_CEIL` exists for: unclamped, the ogre's crown is off the top of the screen
        // from here and the bar goes with it.
        {
            _ = o.vit.hit(.{ .dmg = 90 }); // …so the bar is up at all (`HURT_BAR_WINDOW`)
            g.hero.facing = mathx.headingXZ(mathx.scaleV(LIT_BACK, -1)); // squared up on it
            // TWO RANGES, because the bar has two behaviours: out where the whole giant is in frame it rides
            // the crown untouched, and toe to toe — where the crown is over the top of the screen and can even
            // be BEHIND the eye — the ceiling has to hold it in frame.
            for ([_]struct { m: f32, name: [:0]const u8 }{
                .{ .m = 9.0, .name = "shots/47b_ogre_bar_far.png" },
                .{ .m = 2.6, .name = "shots/47c_ogre_bar_close.png" },
            }) |shot| {
                g.hero.pos = along(oc, LIT_BACK, shot.m);
                g.hero.update(dt, 0, 0, null);
                g.hero.pose();
                shootClear(g, shot.name, LIT_YAW, 0.10, 5.0);
            }
            o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
            stepFoe(o, 54, far);
        }
        // …AND WHERE THE RETICLE SITS (`ogre.LOCK_AT`): the bar rides `topWorld` and the dot rides the POSED
        // CHEST, so they answer different questions. Toe to toe, the range the seat was chosen against.
        {
            g.hero.pos = along(oc, LIT_BACK, 4.2);
            g.hero.facing = mathx.headingXZ(mathx.scaleV(LIT_BACK, -1));
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
            g.lock = .{ .kind = .ogre, .idx = 0 };
            shootClear(g, "shots/47d_ogre_lock.png", LIT_YAW, 0.10, 6.4);
            g.lock = null;
        }
        // Scale — the hero standing clearly to the ogre's side (it looms ~1.9x over him).
        g.hero.pos = mathx.ground(oc.x + 4.8, oc.z + 1.4);
        g.hero.facing = mathx.headingXZ(mathx.subV(oc, g.hero.pos)); // face the ogre
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootFoe(g, o, "shots/48_ogre_scale.png", 30, 0.16, 15.5);
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 100, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/56_ogre_walk.png", 90, 0.06, 12.0);
        stepFoe(o, 34, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/57_ogre_walk_b.png", 270, 0.06, 12.0);
        stepFoe(o, 69, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/58_ogre_walk_c.png", 270, 0.06, 12.0);
        stepFoe(o, 17, v3(oc.x, 0, oc.z + 15.0));
        shootFoe(g, o, "shots/59_ogre_walk_3q.png", 320, 0.08, 12.5); // front-left 3/4: free arm, lit
        // THE HEAD CRANE — the sensed hero sits hard off his LEFT while his body still points +Z, so the eye is craned to the neck's limit a beat before the slow body can follow.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 14, v3(oc.x + 9.0, 0, oc.z + 1.0)); // 14 frames: the head is AT its 55 deg
        shootFoe(g, o, "shots/60_ogre_headtrack.png", 20, 0.20, 11.0);

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 30, far);
        g.rig.yaw = mathx.radians(182);
        g.rig.pitch = 0.16;
        g.rig.dist = 3.2;
        g.rig.follow(o.headWorld());
        shoot(g, "shots/55_ogre_face.png");

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugSlam();
        stepFoe(o, 64, far); // f64: deep in the loaded peak HOLD — club overhead, arched back, trembling
        shootFoe(g, o, "shots/49_ogre_windup.png", 55, 0.00, 13.0);
        stepFoe(o, 21, far); // f85: one frame past IMPACT — club at the crater, the dust burst still tight
        shootFoe(g, o, "shots/50_ogre_slam.png", 60, 0.06, 13.0);
        stepFoe(o, 25, far); // f110: ~0.4 s into recovery — doubled over the buried club, wide open
        shootFoe(g, o, "shots/51_ogre_recover.png", 48, 0.10, 12.5);

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

        {
            // THE RETURN — judged from above like the swipe (a lateral arc foreshortens to nothing head-on).
            const ahead = v3(oc.x, 0, oc.z + 3.4); // dead ahead, mid-band — where a chained hero stands
            o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
            o.debugBackswipe();
            stepFoe(o, 20, ahead); // f20: the DRAG — club dying low on his left, about to be ripped back
            shootFoe(g, o, "shots/63b_ogre_backwind.png", 35, 0.50, 14.0); // from above — the drag is a lateral fact, like the arcs
            stepFoe(o, 9, ahead); // f29: one frame past the return's impact — the rising cut mid-front
            shootFoe(g, o, "shots/63c_ogre_backswipe.png", 35, 0.12, 12.0);
            shootFoe(g, o, "shots/63d_ogre_backswipe_top.png", 35, 0.60, 15.0); // same frame, from above
        }

        {
            // THE DRIVE — tell, surge and crash. debugDrive enters .drivewind at t=0: the coil peaks at
            // f43, the surge runs f43..f72 (impact), the whole move ends at f80.
            const mark = v3(oc.x, 0, oc.z + 6.5); // mid-band, dead ahead — what the lunge is for
            o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
            o.debugDrive();
            stepFoe(o, 40, mark); // f40: the coil — folded FORWARD over loaded legs (not the slam's arch)
            shootFoe(g, o, "shots/64_ogre_drive_tell.png", 55, 0.10, 13.0);
            stepFoe(o, 18, mark); // f58: mid-surge — legs churning, club coming over the top
            shootFoe(g, o, "shots/64b_ogre_drive_surge.png", 90, 0.08, 13.5);
            stepFoe(o, 15, mark); // f73: one frame past impact — the crash at the end of the run
            shootFoe(g, o, "shots/64c_ogre_drive_crash.png", 55, 0.08, 13.0);
        }

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugStagger(false);
        stepFoe(o, 13, far); // flinch peak (recoiled back, arm flung up)
        shootFoe(g, o, "shots/52_ogre_flinch.png", 55, 0.04, 12.5);
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugStagger(true);
        stepFoe(o, 42, far); // deep in the stance-break — sagged onto a knee, wide open
        shootFoe(g, o, "shots/53_ogre_stagger.png", 50, 0.10, 13.0);
        // STAGGERED OUT OF A RAISED CLUB: interrupted at the top of a windup the posture channels have 163
        // degrees of shoulder to unwind, and at four degrees a second he reels with the club still overhead.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugSlam();
        stepFoe(o, 64, far); // the loaded peak: club overhead (this is 49_ogre_windup's own frame)
        o.debugStagger(true);
        stepFoe(o, 10, far); // …and a sixth of a second later the arm is already on its way down
        shootFoe(g, o, "shots/53b_ogre_stagger_armed.png", 50, 0.10, 13.0);
        stepFoe(o, 32, far); // …and by the deep hold it is back under him, not still raised
        shootFoe(g, o, "shots/53c_ogre_stagger_armed_late.png", 50, 0.10, 13.0);

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugKill();
        stepFoe(o, 72, far); // the slow topple, well into the collapse
        shootFoe(g, o, "shots/54_ogre_death.png", 55, 0.12, 13.5);

        // Restore it to its home deep in the ruins so it doesn't loom over the retro/menu shots.
        o.* = ogremod.Ogre.spawn(mathx.ground(3.0, -50.0), 0, 1.0, 0.4);
    }

    {
        const kc = mathx.ground(-26.0, 30.0); // open ground west of the ogre's spot, clear of ruins
        const litB = LIT_BACK; // the XZ bearing of backDir(LIT_YAW) — where the camera sits
        const far = v3(kc.x + litB.x * 80.0, 0, kc.z + litB.z * 80.0);
        const near = v3(kc.x + litB.x * 1.2, 0, kc.z + litB.z * 1.2);
        g.band.n = 3;
        const zerk = &g.band.band[0];
        const priest = &g.band.band[1];
        const sling = &g.band.band[2];

        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x - 1.7, kc.z), 0, 1.0, 0.15);
        priest.* = koboldmod.Kobold.spawnAs(.priest, kc, 0, 1.0, 0.55);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, mathx.ground(kc.x + 1.7, kc.z), 0, 1.0, 0.85);
        for ([_]*koboldmod.Kobold{ zerk, priest, sling }) |k| stepFoe(k, 30, far);
        standHero(g, kc.x + 3.2, kc.z - 3.4, mathx.radians(-140));
        shootAt(g, "shots/64_kobold_band.png", v3(kc.x + 0.6, kc.y + 1.0, kc.z), LIT_YAW, 0.10, 7.6);
        shootAt(g, "shots/64b_kobold_heads.png", v3(kc.x, kc.y + 1.30, kc.z), LIT_YAW, 0.03, 4.2);
        shootPortrait(g, "shots/64c_kobold_head.png", v3(kc.x + 1.7, kc.y + 1.42, kc.z), LIT_YAW + 12, -0.05, 2.3);
        const back = v3(kc.x - litB.x * 80.0, 0, kc.z - litB.z * 80.0);
        for ([_]*koboldmod.Kobold{ zerk, priest, sling }) |k| stepFoe(k, 40, back);
        shootPortrait(g, "shots/64d_kobold_tail.png", v3(kc.x - 1.7, kc.y + 0.74, kc.z), LIT_YAW - 34, 0.14, 2.7);

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

        // THE CHARGE. He closes at a RUN now, and `advanceGait` picks the leg curves off the ground speed it
        // is handed — so what has to be photographed is that this reads as a RUN and not as a fast walk: a
        // real flight phase, the deep lean, arms pumping. Shot from far enough out that he is still charging
        // (past `walkInR`), and stepped until the gait has settled rather than for a literal frame count.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x, kc.z - 9.0), 0, 1.0, 0.15);
        var chf: i32 = 0;
        while (zerk.state != .approach and chf < 600) : (chf += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(zerk, 26, near);
        shootFoe(g, zerk, "shots/64e_kobold_charge.png", LIT_YAW + 30, 0.06, 3.8);

        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        var zf: i32 = 0;
        while (zerk.state != .chop and zf < 600) : (zf += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        // AIMED OFF THE CHOP'S OWN CLOCK, never off literal frames: the raise is what `CHOP_HIT_A` bounds,
        // so lengthening the swing must not slide both beats back into it (which it did, once).
        const chopAt = struct {
            fn frames(u: f32) i32 {
                return @intFromFloat(@round(u * koboldmod.CHOP_DUR / SHOT_DT));
            }
        }.frames;
        const raiseTop = chopAt(koboldmod.CHOP_HIT_A * 0.62); // near the top of the raise, axe cocked back
        stepFoe(zerk, raiseTop, near);
        shootFoe(g, zerk, "shots/65_kobold_chop.png", LIT_YAW + 20, 0.06, 3.4);
        // …and a beat INSIDE the hit window, where the axe is actually crossing his centre line.
        stepFoe(zerk, chopAt(koboldmod.CHOP_HIT_A + 0.10) - raiseTop, near);
        shootFoe(g, zerk, "shots/65b_kobold_chop_b.png", LIT_YAW + 20, 0.06, 3.4);
        var guard: i32 = 0;
        while (zerk.state != .heave and guard < 600) : (guard += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(zerk, 12, near);
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
                // …then to the beat itself, in whole harness frames off the state clock. GUARDED, like the
                // wait above it: a creature that never entered the state never reaches the beat either, and
                // an unbounded wait for one turns a behaviour change into a hung build.
                var bf: i32 = 0;
                while (zerk.t < b.at and bf < 600) : (bf += 1) _ = zerk.update(SHOT_DT, dside, game.PLAY_HALF, .{});
                shootPortrait(g, b.name, zerk.centerWorld(), LIT_YAW, 0.06, 5.0);
            }
        }

        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        zerk.debugStagger(true);
        stepFoe(zerk, 10, far); // deep in the stance-break: knees buckled, arms flung, muzzle up
        shootFoe(g, zerk, "shots/66b_kobold_stagger.png", LIT_YAW + 22, 0.06, 3.8);
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        zerk.debugKill();
        stepFoe(zerk, 34, far); // folded onto the ground, before the motes take him
        shootFoe(g, zerk, "shots/66c_kobold_death.png", LIT_YAW + 30, 0.16, 3.6);

        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x - 1.6, kc.z + 0.4), 0, 1.0, 0.15);
        zerk.vit.hp = 20;
        priest.* = koboldmod.Kobold.spawnAs(.priest, kc, 0, 1.0, 0.55);
        priest.healWanted = true;
        priest.castCd = 0;
        var cf: i32 = 0;
        while (cf < 64) : (cf += 1) _ = g.band.update(SHOT_DT, far, game.PLAY_HALF, .{}, g, game.spawnClump);
        shootFoe(g, priest, "shots/67_kobold_cast.png", LIT_YAW + 16, 0.10, 4.4);
        shootFoe(g, priest, "shots/67b_kobold_cast_far.png", LIT_YAW + 16, 0.14, 13.0);

        park(zerk, .berserker, away);
        park(priest, .priest, away);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, 0, 1.0, 0.85);
        sling.slingCd = 0;
        const band8 = v3(kc.x + litB.x * 8.0, 0, kc.z + litB.z * 8.0); // inside its range band, on the lit bearing
        var g2: i32 = 0;
        while (sling.state != .whirl and g2 < 600) : (g2 += 1) _ = sling.update(SHOT_DT, band8, game.PLAY_HALF, .{});
        stepFoe(sling, 16, band8);
        shootFoe(g, sling, "shots/68_kobold_whirl.png", LIT_YAW + 18, 0.10, 3.8);
        // …and a CROP of the loaded pouch, because a 3 cm flame is unjudgeable in a whole-body frame.
        shootPortrait(g, "shots/68b_kobold_sling_lit.png", sling.slingPoint(), LIT_YAW + 18, 0.04, 1.1);
        // THE THROW ITSELF: run the band until the clump is in the air, then fly it clear of the pouch, so
        // the shot holds the burning lump, its ember streak AND the sparks the release left behind.
        var g5: i32 = 0;
        while (game.flyingPointForShot(g, .clump) == null and g5 < 900) : (g5 += 1) stepBandAndShots(g, 1, band8);
        must(game.flyingPointForShot(g, .clump) != null, "the slinger never threw a clump");
        stepBandAndShots(g, 5, band8); // …far enough out of the pouch to be its own subject
        if (game.flyingPointForShot(g, .clump)) |at| shootPortrait(g, "shots/68c_kobold_clump.png", at, LIT_YAW + 18, 0.05, 1.6);
        shootFoe(g, sling, "shots/68d_kobold_sling_sparks.png", LIT_YAW + 18, 0.10, 4.2);
        game.clearShaftsForShot(g); // clears BOTH pools — see `clearQuivers`
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, 0, 1.0, 0.85);
        sling.biteCd = 0;
        var g3: i32 = 0;
        while (sling.state != .bite and g3 < 600) : (g3 += 1) _ = sling.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(sling, 10, near);
        shootFoe(g, sling, "shots/69_kobold_bite.png", LIT_YAW + 14, 0.04, 2.6);
        // …and the SAME beat in PROFILE, which is the only angle that shows what a snap is made of: the waist folding over planted legs and the muzzle leading it.
        const side = v3(kc.x - litB.z * 1.2, 0, kc.z + litB.x * 1.2);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, mathx.headingXZ(mathx.subV(side, kc)), 1.0, 0.85);
        sling.biteCd = 0;
        var g4: i32 = 0;
        while (sling.state != .bite and g4 < 600) : (g4 += 1) _ = sling.update(SHOT_DT, side, game.PLAY_HALF, .{});
        stepFoe(sling, 4, side); // the CHAMBER — the rock back that gives the snap its crack
        // …CENTRED (`shootPortrait`), not `shootFoe`: the rig's shoulder offset is 0.55 m and this subject is 1.3 m tall, so a followed framing at snap distance puts half of it out of frame.
        shootPortrait(g, "shots/69d_kobold_bite_coil.png", sling.centerWorld(), LIT_YAW, 0.06, 4.4);
        stepFoe(sling, 6, side);
        shootPortrait(g, "shots/69c_kobold_bite_side.png", sling.centerWorld(), LIT_YAW, 0.06, 4.4);
        shootPortrait(g, "shots/69e_kobold_bite_jaw.png", sling.lockPoint(), LIT_YAW, 0.02, 1.9);

        // …and the WALK, side on, at three phases a quarter-stride apart: the shared gait under a narrower trunk, and the one thing a single frame provably cannot verify.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x - litB.x * 9.0, kc.z - litB.z * 9.0), 0, 1.0, 0.15);
        const walkTo = v3(kc.x + litB.x * 40.0, 0, kc.z + litB.z * 40.0);
        const walkNames = [_][:0]const u8{ "shots/69b_kobold_walk.png", "shots/69c_kobold_walk.png", "shots/69d_kobold_walk.png" };
        for ([_]i32{ 26, 9, 9 }, 0..) |adv, wi| {
            stepFoe(zerk, adv, walkTo); // hero far ahead on the sun's bearing → walks toward it, LIT
            shootFoe(g, zerk, walkNames[wi], LIT_YAW + 58, 0.06, 4.6);
        }
        game.rehomeFoesForShot(g);
    }

    {
        standHero(g, 0, 12, std.math.pi);
        shootAt(g, "shots/70_avenue_north.png", g.hero.shoulderPoint(), 180, 0.16, 9.0);
        shootAt(g, "shots/71_vista_north.png", mathx.ground(0, 6), 180, 0.30, 9.0);

        // EVERY EDGE SHAPE IN ONE FRAME, since the value of having eight is telling them apart. STEEP AND
        // LIT: an edge is a line on the GROUND, so a grazing angle foreshortens one disc into the next.
        {
            const wasSoil = g.map.soil;
            const wasCov = g.map.soilCov;
            const wasEdge = g.map.soilEdge;
            g.map.soil = [_]u8{0} ** worldfmt.SOIL_CELLS;
            g.map.soilCov = [_]u8{worldfmt.COV_FULL} ** worldfmt.SOIL_CELLS;
            // ON THE OPEN DOWNS, not the ruin avenue: over the avenue every disc was under a pillar's
            // shadow or a cliff's, and a shadow crossing an edge is indistinguishable from the edge.
            const EX: f32 = 0;
            const EZ: f32 = 96;
            var ei: usize = 0;
            while (ei < worldfmt.Edge.N) : (ei += 1) {
                const col: f32 = @floatFromInt(ei % 4);
                const row: f32 = @floatFromInt(ei / 4);
                _ = g.map.paintSoil(EX + (col - 1.5) * 30.0, EZ + (row - 0.5) * 30.0, 13.0, .stone, 1, @enumFromInt(ei));
            }
            g.env.uploadSoil(&g.map);
            // …AND AT NOON: the anchor hour lays metre-long shadows across exactly the lines being judged.
            game.pinHourForShot(g, 12.0);
            // The hero is the SCALE and the shadow ortho box tracks him, so he stands in the middle of it.
            standHero(g, EX, EZ, std.math.pi);
            // Yaw 180 like every other overhead map shot — at noon the sun is straight up, so the 53-degree
            // sun-over-the-shoulder rule has nothing to say here and the grid may as well sit square.
            shootAt(g, "shots/98a_soil_edges.png", mathx.ground(EX, EZ), 180, 1.12, 74.0);
            game.pinHourForShot(g, game.daynight.SHOT_HOUR);
            g.map.soil = wasSoil;
            g.map.soilCov = wasCov;
            g.map.soilEdge = wasEdge;
            g.env.uploadSoil(&g.map);
        }
        standHero(g, 1.4, 7.4, mathx.radians(120));
        shootAt(g, "shots/71b_bonfire.png", v3(3.0, 0.55, 6.5), 300, 0.07, 3.1);
        standHero(g, 0.0, 3.4, mathx.radians(200));
        shootPortrait(g, "shots/71c_guitar.png", v3(1.38, 0.68, 7.34), 20, 0.06, 2.7);
        standHero(g, 3.0, 8.4, mathx.radians(200));
        game.beginRestForShot(g);
        for ([_]i32{ 165, 55, 60 }, [_][:0]const u8{ "shots/71e_rest.png", "shots/71f_rest_play.png", "shots/71g_rest_play2.png" }) |adv, name| {
            var k: i32 = 0;
            while (k < adv) : (k += 1) game.tickRestForShot(g, SHOT_DT);
            bonfireShoot(g, name);
        }
        // Staged with the warrior arm two deep so ring 1 has opened, and carrying enough to afford the next.
        const treeSouls = g.hero.souls.total;
        _ = g.tree.take(ptree.armFirst(.warrior), 1_000_000);
        _ = g.tree.take(ptree.armFirst(.warrior) + 1, 1_000_000);
        g.hero.souls.total = 900;
        g.hero.souls.shown = 900;
        game.applyTree(g);
        restmod.debugShow(&g.rest, .list, 0, 0, 1.0);
        bonfireShoot(g, "shots/71h_bonfire_list.png");
        restmod.debugShow(&g.rest, .tree, 0, ptree.armFirst(.warrior) + 3, 1.0);
        bonfireShoot(g, "shots/71i_bonfire_tree.png");
        restmod.debugShow(&g.rest, .tree, 0, ptree.armFirst(.warrior) + 3, 2.3);
        bonfireShoot(g, "shots/71j_bonfire_tree_zoom.png");
        g.tree = .{};
        game.applyTree(g);
        g.hero.souls.total = treeSouls;
        g.hero.souls.shown = @floatFromInt(treeSouls);
        game.endRestForShot(g);

        // THE SMOKE COLUMN against the horizon — the framing that judges the veil pass.
        standHero(g, 4.4, 6.2, mathx.radians(120));
        shootAt(g, "shots/71d_plume.png", v3(3.0, 2.3, 6.5), LIT_YAW, 0.14, 9.0);

        standHero(g, 2.0, -66.0, std.math.pi);
        shootAt(g, "shots/72_city_plaza.png", mathx.ground(0, -74), 180, 0.26, 9.0);
        // The chapel sits at (-30, -66) turned to yaw 270, which maps its local +Z (the altar end) to world −X and its doorway to world +X: the nave runs along X from -33.6 (altar) to -26.4 (door).
        standHero(g, -22.0, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/73_chapel_outside.png", mathx.ground(-30, -66), 270, 0.22, 17.0);
        standHero(g, -29.6, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/74_chapel_torchlit.png", v3(-30.7, 1.4, -66.0), 270, 0.05, 4.4);
        // …and closer on the altar itself, still outside its 1.25 m half-depth.
        standHero(g, -30.6, -66.0, -std.math.pi * 0.5);
        shootAt(g, "shots/75_chapel_altar.png", v3(-32.6, 1.0, -66.0), 270, 0.10, 4.8);

        standHero(g, 34.0, -95.0, mathx.radians(20));
        shootAt(g, "shots/76_watchtower.png", mathx.ground(36, -88), 20, 0.16, 27.0);
        standHero(g, 36.4, -88.4, 0);
        shootAt(g, "shots/77_watchtower_inside.png", v3(35.7, 1.7, -87.6), 200, 0.06, 2.0);

        standHero(g, 130.0, 14.0, -std.math.pi * 0.5);
        shootAt(g, "shots/78_tarn.png", mathx.ground(122, 12), 268, 0.10, 13.0);
        standHero(g, 70.0, 8.0, std.math.pi * 0.5);
        shootAt(g, "shots/79_tarn_causeway.png", mathx.ground(78, 8), 100, 0.18, 12.0);

        standHero(g, -84.0, 4.0, -std.math.pi * 0.5);
        shootAt(g, "shots/80_wood.png", mathx.ground(-90, 4), 260, 0.12, 11.0);
        shootAt(g, "shots/81_bigtree.png", v3(-90.0, 5.0, 6.0), 300, -0.10, 17.0);
        standHero(g, -90.0, -16.0, -std.math.pi * 0.5);
        shootAt(g, "shots/82_stone_circle.png", mathx.ground(-98, -16), 265, 0.14, 15.0);
        standHero(g, -66.0, 30.0, -std.math.pi * 0.5);
        shootAt(g, "shots/83_cottage.png", mathx.ground(-72, 30), 258, 0.10, 12.0);

        standHero(g, 22.0, 82.0, 0);
        shootAt(g, "shots/84_downs.png", mathx.ground(22, 92), 8, 0.14, 14.0);

        const rimZ = g.map.half - 20.0;
        standHero(g, 40.0, rimZ, 0);
        shootAt(g, "shots/85_cliffs.png", mathx.ground(40, rimZ + 12), 4, 0.22, 22.0);
        standHero(g, 10.0, rimZ + 10, std.math.pi * 0.5);
        shootAt(g, "shots/85b_cliffs_along.png", mathx.ground(30, rimZ + 18), 80, 0.16, 26.0);
        // THE START ARC — the only place the cliff CHARACTERS stand side by side close enough to compare.
        standHero(g, 0.0, 6.0, 0);
        shootAt(g, "shots/85c_arc_ivied.png", mathx.ground(0, 21), 0, 0.16, 22.0);
        standHero(g, 22.0, 3.0, mathx.radians(90));
        shootAt(g, "shots/85d_arc_collapsed.png", mathx.ground(36, 2), 90, 0.14, 20.0);

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

        // DEEP WATER: the wall (`env.WADE_MAX`) and the tone the DIG darkens the sheet to (`env.digTone`).
        standHero(g, 46.0, -24.0, std.math.pi);
        shootAt(g, "shots/90a_map_deepwater.png", mathx.ground(46, -24), 180, 1.02, 55.0);
        standHero(g, 44.0, -22.0, mathx.radians(200));
        shootAt(g, "shots/90b_deepwater_bank.png", mathx.ground(50, -32), 53, 0.14, 17.0);

        g.menu.stats = true;
        standHero(g, 2.0, -72.0, std.math.pi);
        shootAt(g, "shots/91_stats_city.png", g.hero.shoulderPoint(), 180, 0.22, 8.0);
        standHero(g, -88.0, 8.0, -std.math.pi * 0.5);
        shootAt(g, "shots/92_stats_wood.png", g.hero.shoulderPoint(), 265, 0.20, 8.0);
        g.menu.stats = false;

        // THE OCCLUDER FADE: him seen THROUGH a great tree, which is the only framing that shows it.
        const trunk = g.env.nearestFading(v3(-118.0, 0, -14.0), 600.0);
        must(trunk != null, "no fadeable prop in the world to stand behind");
        const tp = trunk.?;
        // Him 2.4 m the far side of the trunk on a 7 m boom: any longer and the camera is up inside the
        // canopy, where what you photograph is foliage rather than the thing standing in the way.
        standHero(g, tp.x - LIT_BACK.x * 2.4, tp.z - LIT_BACK.z * 2.4, mathx.radians(LIT_YAW + 180.0));
        shootAt(g, "shots/93_occlude_fade.png", g.hero.shoulderPoint(), LIT_YAW, 0.06, 7.0);
        g.retro.values = gfx.RETRO_DEFAULTS;
        shootAt(g, "shots/93b_occlude_filtered.png", g.hero.shoulderPoint(), LIT_YAW, 0.06, 7.0);
        g.retro.allOff();
        // …and the same tree with the line clear of it, which is what proves it goes back to solid.
        standHero(g, tp.x + 7.0, tp.z + 7.0, mathx.radians(LIT_YAW + 180.0));
        shootAt(g, "shots/94_occlude_clear.png", g.hero.shoulderPoint(), LIT_YAW, 0.06, 7.0);
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

    g.retro.applyPreset(&gfx.PRESET_CRT);
    shoot(g, "shots/10_retro_crt.png");

    g.retro.applyPreset(&gfx.PRESET_PS1);
    shoot(g, "shots/11_retro_ps1.png");
    g.retro.allOff();

    // A SHELF WITH SOMETHING ON IT, for every card below that reads one. The empty one is staged where the
    // greying is what is being judged.
    var shelf = savemod.Shelf{};
    shelf.head[0] = .{ .level = 7, .souls = 1240, .playtime = 8100 };
    shelf.head[2] = .{ .level = 1, .souls = 0, .playtime = 95 };
    const bare = savemod.Shelf{};
    // …and a shelf with NOWHERE LEFT TO PUT ONE, which is New Game's own greyed state (owner: gray out new
    // game if no slots avail). Three filled is the only staging that shows it.
    var packed_ = savemod.Shelf{};
    packed_.head[0] = .{ .level = 7, .souls = 1240, .playtime = 8100 };
    packed_.head[1] = .{ .level = 3, .souls = 210, .playtime = 2400 };
    packed_.head[2] = .{ .level = 1, .souls = 0, .playtime = 95 };

    g.menu.screen = .main;
    g.menu.cursor = 0;
    drawScene(g);
    hud(g, SHOT_DT);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &shelf);
    snap("shots/12_menu_main.png");

    // THE BOOT SCREEN, framed the way the LOOP frames it (`game.BOOT_*`) — the card is only half of what is
    // being judged and the other half is what stands behind it. Sun over the shoulder at yaw 53, or the
    // world it is drawn over is its own shadow. NO HUD: nothing has been started, so there are no bars.
    g.rig.yaw = mathx.radians(53);
    g.rig.pitch = game.BOOT_PITCH;
    g.rig.dist = game.BOOT_DIST;
    g.rig.follow(g.hero.shoulderPoint());
    g.menu.screen = .boot;
    g.menu.home = .boot;
    g.menu.cursor = 1; // ON Load, which is the only row whose two states differ
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &bare);
    snap("shots/12a_menu_boot.png");

    drawScene(g);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &shelf);
    snap("shots/12b_menu_boot_save.png");

    // …AND THE PICKER. Two slots filled and one empty, which is the one staging that shows all three of a
    // row's states at once: taken, taken, and the greyed Empty a Load may not press.
    g.menu.showSlotsForShot(.load, 1);
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &shelf);
    snap("shots/12c_menu_slots.png");

    // The same three under NEW, and the greying is the exact INVERSE of Load's: a new character needs an
    // EMPTY slot, so the two taken rows are the refused ones and the empty one is the only press.
    g.menu.showSlotsForShot(.new, 1);
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &shelf);
    snap("shots/12d_menu_slots_new.png");

    // …AND THE BOOT ROW ITSELF, greyed, when there is nowhere to put one: with all three written there is no
    // such thing as starting a character until one is deleted, so the row says so rather than opening a
    // picker on which every row is refused.
    g.menu.screen = .boot;
    g.menu.cursor = 0; // ON New Game, which is the row whose two states differ here
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &packed_);
    snap("shots/12ca_menu_boot_full.png");
    g.menu.showSlotsForShot(.load, 1);

    // …AND THE QUESTION IT ASKS BEFORE IT THROWS A CHARACTER AWAY. The only press in the game that destroys
    // anything, so the row stops saying what the character IS and says what is about to happen to it — and
    // the crib under it drops to the two answers, because every other button there is refused.
    g.menu.showSlotsForShot(.load, 0);
    g.menu.armDeleteForShot();
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &shelf);
    snap("shots/12e_menu_slot_delete.png");

    g.menu.onEscape(); // …and OUT through the picker's own door, which is what drops its three textures
    g.menu.home = .main;
    g.rig.yaw = mathx.radians(300);
    g.rig.pitch = 0.14;
    g.rig.dist = 3.4;
    g.rig.follow(g.hero.shoulderPoint());

    g.retro.values[gfx.RF_GAMEBOY] = 1.0; // show a live gauge on the retro card
    g.menu.screen = .retro;
    g.menu.cursor = gfx.RF_GAMEBOY;
    drawScene(g);
    hud(g, SHOT_DT);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), null, &shelf);
    snap("shots/13_menu_retro.png");
    g.menu.screen = .closed;

    // The owner-tuned default stack — the look the game actually launches with.
    g.retro.values = gfx.RETRO_DEFAULTS;
    shoot(g, "shots/14_retro_default.png");
    g.retro.allOff();

    broodShots(g);
    warriorShots(g);
    shadeShots(g);
    leechShots(g);
    rootedShots(g);
    shroomShots(g);
    delverShots(g);
    necroShots(g);
    pickupShots(g);
    knightShots(g);
    soulsShots(g);
    campfireShots(g);
    chestShots(g);
    folkShots(g);
    soundFilterShots(g);
    wolfShots(g);
    dayShots(g);
    editorShots(g);
    editorGapShots(g);
}

/// THE SOUND FILTER RACK, which now lives in the EDITOR beside the jukebox (it moved out of the game's
/// debug menu — it is an authoring tool, and the one place a voice can be played on demand is that list).
fn soundFilterShots(g: *Game) void {
    const was = g.menu.screen;
    const wasCursor = g.menu.cursor;
    // With a preset ON: an all-zero rack proves the layout and nothing about the dials.
    sfx.applyFxPreset(.combat, &sfx.FX_VINYL);
    g.menu.screen = .closed;
    editorJukeShot(g, "shots/115a_sound_rack.png");

    // …and put the bank back exactly as it was — the harness must not leave a filtered build behind.
    sfx.resetFx(.combat);
    g.menu.screen = was;
    g.menu.cursor = wasCursor;
}

fn broodShots(g: *Game) void {
    const bc = mathx.ground(-30.0, 14.0);
    // The sensed hero is put BEHIND her in +Z terms, so she turns to face −Z and the lit camera band (yaw ~55, the sun over its shoulder) is looking at her FRONT — which on this creature is the whole point.
    const far = v3(bc.x, 0, bc.z - 80.0);
    game.clearFoesForShot(g);
    g.hero.pos = mathx.ground(bc.x - 26.0, bc.z);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();

    g.brood.band[0] = broodmod.Spider.spawnAs(.mother, bc, std.math.pi, 1.0, 0.3);
    g.brood.n = 1;
    const m = &g.brood.band[0];
    stepFoe(m, 40, far);
    shootFoe(g, m, "shots/107_brood_mother.png", 55, 0.12, 9.0);
    shootFoe(g, m, "shots/107b_brood_mother_3q.png", 20, 0.16, 8.0); // front-left 3/4, lit
    shootFoe(g, m, "shots/107c_brood_mother_side.png", 300, 0.10, 8.5);

    g.hero.pos = mathx.ground(bc.x + 3.4, bc.z + 1.2);
    g.hero.facing = mathx.headingXZ(mathx.subV(bc, g.hero.pos));
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    shootFoe(g, m, "shots/108_brood_scale.png", 30, 0.14, 11.0);
    g.hero.pos = mathx.ground(bc.x - 26.0, bc.z);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();

    m.* = broodmod.Spider.spawnAs(.mother, bc, std.math.pi, 1.0, 0.3);
    stepFoe(m, 34, v3(bc.x, 0, bc.z - 11.0));
    shootFoe(g, m, "shots/109_brood_spit_wind.png", 40, 0.10, 8.0);
    stepFoe(m, 8, v3(bc.x, 0, bc.z - 11.0));
    shootFoe(g, m, "shots/109b_brood_spit_throw.png", 40, 0.10, 8.0);

    m.* = broodmod.Spider.spawnAs(.mother, bc, std.math.pi, 1.0, 0.3);
    const near = v3(bc.x, 0, bc.z - 8.0); // a sensed hero in her lay band, held for the whole sequence
    var k: i32 = 0;
    while (k < 260) : (k += 1) _ = g.brood.update(SHOT_DT, near, game.PLAY_HALF, .{}, g, game.spawnVenom);
    shootFoe(g, m, "shots/110_brood_laying.png", 45, 0.12, 9.5);
    while (k < 560) : (k += 1) _ = g.brood.update(SHOT_DT, near, game.PLAY_HALF, .{}, g, game.spawnVenom);
    shootFoe(g, m, "shots/110b_brood_clutch.png", 45, 0.16, 10.5);
    // …and what comes out of it — the hatch runs on its own clock, so this is simply later.
    const hatched = 240 + @as(i32, @intFromFloat((broodmod.SAC_HATCH + 1.0) / SHOT_DT));
    while (k < hatched) : (k += 1) _ = g.brood.update(SHOT_DT, near, game.PLAY_HALF, .{}, g, game.spawnVenom);
    // …framed on THE HATCHLINGS, not on her: by now they have scattered off her and a shot centred on the mother is a shot of the mother with something out of frame.
    if (g.brood.n > 1) {
        const b = &g.brood.band[g.brood.n - 1];
        shootFoe(g, b, "shots/111_broodlings.png", 45, 0.14, 8.0);
        shootFoe(g, b, "shots/111b_broodling.png", 40, 0.08, 3.4); // one alone: her young, not a beetle
    }

    // Staged CLEAR of the cliff ring's shadow: a corpse is a low, dark thing, and lying inside that
    // wedge it had a black ground behind it and no silhouette at all. The offset runs ACROSS the
    // shadow's long axis (which follows the sun's own bearing away from the cliffs), not along it.
    const dc = mathx.ground(bc.x + 6.0, bc.z - 8.0);
    m.* = broodmod.Spider.spawnAs(.mother, dc, std.math.pi, 1.0, 0.3);
    g.brood.n = 1;
    m.debugKill();
    stepFoe(m, 9, near); // the convulsion, legs starting to cramp
    shootFoe(g, m, "shots/112a_brood_death_rear.png", 55, 0.14, 9.0);
    stepFoe(m, 17, near); // mid-fall, past the balance point
    shootFoe(g, m, "shots/112b_brood_death_flip.png", 55, 0.14, 9.0);
    stepFoe(m, 10, near); // the crash — carried past flat, about to rock back
    shootFoe(g, m, "shots/112c_brood_death_crash.png", 55, 0.12, 9.0);
    stepFoe(m, 26, near); // settled and clenched, a beat before the motes take it
    shootFoe(g, m, "shots/112d_brood_death_curl.png", 55, 0.12, 9.0);
    g.brood.band[0] = broodmod.Spider.spawnAs(.broodling, dc, std.math.pi, 1.0, 0.55);
    g.brood.band[0].debugKill();
    stepFoe(&g.brood.band[0], 62, near);
    shootFoe(g, &g.brood.band[0], "shots/112e_broodling_death.png", 45, 0.10, 3.6);

    game.clearFoesForShot(g);
    g.brood.splash(bc);
    var p: i32 = 0;
    while (p < 40) : (p += 1) {
        for (&g.brood.pools) |*pool| pool.update(SHOT_DT);
    }
    g.hero.pos = mathx.ground(bc.x, bc.z + 0.6);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    shootAt(g, "shots/112_acid_pool.png", g.hero.shoulderPoint(), 45, 0.34, 7.0);

    game.clearFoesForShot(g);
    game.rehomeFoesForShot(g);
}

/// THE SKELETAL WARRIORS (`113…`). Everything here is shot from `LIT_YAW` with the sensed hero put out
/// on the SUN's bearing, because a foe turns to face him — park him anywhere else and both of these
/// photograph their own shadow (see AGENTS.md, A SUBJECT MUST BE LIT).
fn warriorShots(g: *Game) void {
    game.clearFoesForShot(g);
    const wc = mathx.ground(-24.0, 34.0); // open ground west, the kobolds' patch, clear of ruins
    const near = along(wc, LIT_BACK, 1.4);
    const far = along(wc, LIT_BACK, 90.0);
    g.muster.n = 2;
    const sm = &g.muster.band[0];
    const gs = &g.muster.band[1];
    // SPAWNED FACING THE LENS. A foe only turns to face a hero inside its aggro range, so parking the
    // sensed hero 90 m out on the sun's bearing (which is what makes these shots LIT) leaves it standing
    // on its spawn yaw — and every reaction portrait comes back photographing its spine.
    const faceCam = mathx.headingXZ(LIT_BACK);
    const spawnSm = struct {
        fn it(w: *warriormod.Warrior, at: rl.Vector3, yaw: f32) void {
            w.* = warriormod.Warrior.spawnAs(.shieldman, at, yaw, 1.0, 0.25);
        }
    }.it;
    const spawnGs = struct {
        fn it(w: *warriormod.Warrior, at: rl.Vector3, yaw: f32) void {
            w.* = warriormod.Warrior.spawnAs(.greatsword, at, yaw, 1.0, 0.65);
        }
    }.it;
    const away = mathx.ground(wc.x - 60.0, wc.z + 60.0); // park the other one out of every portrait

    // THE PAIR, so the two silhouettes can be told apart at a glance — which is the whole point of them.
    spawnSm(sm, mathx.ground(wc.x - 1.3, wc.z), faceCam);
    spawnGs(gs, mathx.ground(wc.x + 1.4, wc.z), faceCam);
    for ([_]*warriormod.Warrior{ sm, gs }) |w| stepFoe(w, 30, far);
    standHero(g, wc.x + 3.0, wc.z - 3.2, mathx.radians(-140));
    shootAt(g, "shots/113_warriors_pair.png", v3(wc.x, wc.y + 1.15, wc.z), LIT_YAW, 0.08, 7.4);

    g.hero.pos = mathx.ground(wc.x, wc.z - 30.0); // hero out of the portraits below
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();

    spawnGs(gs, away, faceCam);
    spawnSm(sm, wc, faceCam);
    stepFoe(sm, 40, near); // in reach, boards up
    shootFoe(g, sm, "shots/113a_shield_guard.png", LIT_YAW, 0.04, 4.0);
    shootFoe(g, sm, "shots/113b_shield_guard_side.png", LIT_YAW + 62, 0.04, 4.2); // …and in profile
    // A CROP of the boards themselves: a kite shield's planks, rim and boss are unjudgeable at 1:1.
    shootPortrait(g, "shots/113c_shield_boards.png", sm.centerWorld(), LIT_YAW + 16, 0.02, 2.1);

    // THE MACE, in FOUR beats. It was retuned from "too fast" to a real overarm blow, and a swing is a
    // shape over TIME — the gather is the part a single frame provably cannot show.
    const mc = warriormod.moveClock(.shieldman, 0);
    const maceBeats = [_]struct { name: [:0]const u8, at: f32 }{
        .{ .name = "shots/113d_mace_gather.png", .at = mc.wind * 0.22 }, // the sink back: anticipation
        .{ .name = "shots/113e_mace_cock.png", .at = mc.wind * 0.92 }, // over the skull, boards STILL up
        .{ .name = "shots/113f_mace_strike.png", .at = mc.wind + mc.swing * 0.47 }, // crossing his line
        .{ .name = "shots/113g_mace_follow.png", .at = mc.wind + mc.swing * 0.88 }, // the overswing
    };
    for (maceBeats) |b| {
        spawnSm(sm, wc, faceCam);
        var mf: i32 = 0;
        while (sm.state != .wind and mf < 600) : (mf += 1) _ = sm.update(SHOT_DT, near, game.PLAY_HALF, .{});
        var clock: f32 = 0;
        while (clock < b.at) : (clock += SHOT_DT) _ = sm.update(SHOT_DT, near, game.PLAY_HALF, .{});
        shootPortrait(g, b.name, sm.centerWorld(), LIT_YAW + 18, 0.06, 4.4);
    }

    spawnSm(sm, wc, faceCam);
    sm.debugBreak();
    stepFoe(sm, 20, far); // on the knee, shield arm flung wide, skull hanging
    // FRAMED LOW ON PURPOSE: `centerWorld` is chest height on a STANDING man, and he is not standing —
    // shot off that, a kneel comes back as an empty patch of grass with a skull at the bottom of it.
    const kneelAt = v3(sm.pos.x, sm.pos.y + 0.55, sm.pos.z);
    shootPortrait(g, "shots/113h_shield_kneel.png", kneelAt, LIT_YAW + 12, 0.02, 4.0);
    shootPortrait(g, "shots/113i_shield_kneel_side.png", kneelAt, LIT_YAW + 66, 0.02, 4.0); // a kneel is a PROFILE read
    var bf: i32 = 0;
    while (sm.state == .guardbreak and bf < 900) : (bf += 1) _ = sm.update(SHOT_DT, far, game.PLAY_HALF, .{});
    stepFoe(sm, 30, near);
    shootFoe(g, sm, "shots/113j_shield_broken.png", LIT_YAW, 0.06, 4.2);

    // THE GREATSWORD. The blade's LENGTH is the read, so it gets a full-body framing, not a portrait.
    spawnSm(sm, away, faceCam);
    spawnGs(gs, wc, faceCam);
    stepFoe(gs, 40, far);
    shootFoe(g, gs, "shots/113k_greatsword_carry.png", LIT_YAW, 0.06, 5.2);

    const beat = struct {
        fn at(gg: *Game, w: *warriormod.Warrior, home: rl.Vector3, face: f32, which: usize, clock: f32, name: [:0]const u8, toward: rl.Vector3, yaw: f32, dist: f32) void {
            w.* = warriormod.Warrior.spawnAs(.greatsword, home, face, 1.0, 0.65);
            w.debugSwing(which);
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) _ = w.update(SHOT_DT, toward, game.PLAY_HALF, .{});
            shootPortrait(gg, name, w.centerWorld(), yaw, 0.06, dist);
        }
    }.at;

    // THE DIAGONAL SLAM, in three beats, because a diagonal is a shape over TIME: one frame cannot
    // show that it comes down ACROSS him rather than straight down in front of him.
    const sc = warriormod.moveClock(.greatsword, 0);
    beat(g, gs, wc, faceCam, 0, sc.wind * 0.88, "shots/113l_slam_cock.png", near, LIT_YAW + 20, 6.0); // top of the tell
    beat(g, gs, wc, faceCam, 0, sc.wind + sc.swing * 0.57, "shots/113m_slam_through.png", near, LIT_YAW + 20, 6.0); // crossing his line
    beat(g, gs, wc, faceCam, 0, sc.wind + sc.swing * 0.97, "shots/113n_slam_end.png", near, LIT_YAW + 20, 6.0); // point in the dirt
    beat(g, gs, wc, faceCam, 0, sc.wind + sc.swing + sc.recover * 0.32, "shots/113o_slam_spent.png", near, LIT_YAW + 34, 5.6);

    // THE LUNGE — the quick INTERRUPTIBLE combo, and the little LEAP is most of what it is. Four beats:
    // the coil, the leap (ONE knee up, the other leg trailing), the thrust landing, and the return cut.
    const lc = warriormod.moveClock(.greatsword, 1);
    const stroke2 = lc.wind + lc.swing + lc.chain; // …the follow-up runs on `chainWind`, not on a new tell
    beat(g, gs, wc, faceCam, 1, lc.wind * 0.88, "shots/113p_lunge_coil.png", near, LIT_YAW + 26, 5.6);
    beat(g, gs, wc, faceCam, 1, lc.wind + lc.swing * 0.38, "shots/113q_lunge_leap.png", near, LIT_YAW + 26, 5.6);
    beat(g, gs, wc, faceCam, 1, lc.wind + lc.swing * 0.92, "shots/113r_lunge_thrust.png", near, LIT_YAW + 26, 5.6);
    beat(g, gs, wc, faceCam, 1, stroke2 + lc.swing * 0.5, "shots/113s_lunge_return.png", near, LIT_YAW + 26, 5.6);

    spawnGs(gs, away, faceCam);
    spawnSm(sm, wc, faceCam);
    sm.debugStagger(true);
    stepFoe(sm, 14, far);
    shootFoe(g, sm, "shots/113t_shield_stagger.png", LIT_YAW + 22, 0.06, 4.2);
    spawnSm(sm, away, faceCam);
    spawnGs(gs, wc, faceCam);
    gs.debugKill();
    stepFoe(gs, 34, far);
    shootFoe(g, gs, "shots/113u_greatsword_death.png", LIT_YAW + 28, 0.14, 5.0);

    // THE WALK AND THE RUN — he RUNS the gap down and walks the last of it in, so both are reads that have
    // to be judged, and a still can prove neither on its own. A GAIT IS A PROFILE READ, so he travels
    // ACROSS the sun's bearing rather than along it: side-on to a camera at `LIT_YAW`, and still lit by the
    // sun over that camera's shoulder — travelling along the bearing instead put the lens behind him.
    // AND THE SENSED HERO HAS TO BE INSIDE HIS AGGRO RANGE or he does not move at all: this block used to
    // park him 49 m out, which is `Choice.hold` — three "walk" shots of a skeleton standing still.
    spawnGs(gs, away, faceCam);
    const gaitAcross = mathx.perpXZ(LIT_BACK);
    const gaitFrom = mathx.ground(wc.x - gaitAcross.x * 5.0, wc.z - gaitAcross.z * 5.0);
    spawnSm(sm, gaitFrom, mathx.headingXZ(gaitAcross));
    const walkNames = [_][:0]const u8{ "shots/113v_shield_walk.png", "shots/113w_shield_walk.png", "shots/113x_shield_walk.png" };
    for ([_]i32{ 20, 9, 9 }, 0..) |adv, wi| {
        stepFoe(sm, adv, along(gaitFrom, gaitAcross, 4.0));
        shootFoe(g, sm, walkNames[wi], LIT_YAW, 0.06, 4.8);
    }
    spawnSm(sm, gaitFrom, mathx.headingXZ(gaitAcross));
    const runNames = [_][:0]const u8{ "shots/113y_shield_run.png", "shots/113z_shield_run.png" };
    for ([_]i32{ 40, 11 }, 0..) |adv, wi| {
        stepFoe(sm, adv, along(gaitFrom, gaitAcross, 19.0));
        shootFoe(g, sm, runNames[wi], LIT_YAW, 0.06, 5.2);
    }

    game.clearFoesForShot(g);
    game.rehomeFoesForShot(g);
}

/// THE ROOTED. Every frame here is about the DISGUISE and the staged tell: asleep beside a real snag, the
/// lids up, the unfold, and each of the three limbs mid-arc. A creature whose whole point is that you cannot
/// tell it from scenery has to be photographed NEXT TO the scenery.
fn rootedShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(-88.0, 3.0);
    const near = along(sc, LIT_BACK, 3.0);
    const far = along(sc, LIT_BACK, 90.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.grove.n = 2;
    const t = &g.grove.trees[0];
    const spawn = struct {
        fn it(tt: *rootedmod.Rooted, at: rl.Vector3, yaw: f32, seed: f32) void {
            tt.* = rootedmod.Rooted.spawn(at, yaw, 1.0, seed);
        }
    }.it;
    const away = mathx.ground(sc.x - 60.0, sc.z + 60.0);
    spawn(&g.grove.trees[1], away, faceCam, 0.5);

    // ASLEEP, AND THE WHOLE TEST IS THAT YOU CANNOT PICK IT OUT. `nearestFading` finds a real tree to stand
    // it beside; a portrait of it alone proves nothing about a disguise.
    spawn(t, sc, faceCam, 0.21);
    stepFoe(t, 30, far);
    standHero(g, sc.x + 5.0, sc.z - 5.0, mathx.radians(-140));
    shootAt(g, "shots/118_rooted_hidden.png", v3(sc.x, sc.y + 3.2, sc.z), LIT_YAW, 0.10, 15.0);

    // …AND THE LIDS UP, which is the warning and happens a metre and a half outside its reach. Cropped, since
    // two embers down two knot-holes are unjudgeable at 1:1 (the thin-geometry rule).
    var k: f32 = 0;
    while (k < 3.0) : (k += SHOT_DT) _ = t.update(SHOT_DT, near, game.PLAY_HALF, .{});
    shootAt(g, "shots/118a_rooted_eyes.png", t.lockPoint(), LIT_YAW, 0.05, 3.2);
    shootAt(g, "shots/118b_rooted_watching.png", v3(sc.x, sc.y + 3.0, sc.z), LIT_YAW, 0.08, 9.0);

    spawn(t, sc, faceCam, 0.21);
    t.debugWake();
    stepFoe(t, 28, near);
    shootAt(g, "shots/118c_rooted_wake.png", v3(sc.x, sc.y + 3.0, sc.z), LIT_YAW, 0.08, 10.0);
    stepFoe(t, 40, near);
    shootAt(g, "shots/118d_rooted_open.png", v3(sc.x, sc.y + 3.2, sc.z), LIT_YAW, 0.08, 11.0);

    // THE THREE MOVES, each at its own strike. The hook is shot WITH THE HERO IN FRAME: a limb reaching for
    // nobody is a branch waving.
    const beat = struct {
        fn at(gg: *Game, tt: *rootedmod.Rooted, home: rl.Vector3, face: f32, which: usize, clock: f32, name: [:0]const u8, toward: rl.Vector3, dist: f32) void {
            tt.* = rootedmod.Rooted.spawn(home, face, 1.0, 0.21);
            tt.debugMove(which);
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) _ = tt.update(SHOT_DT, toward, game.PLAY_HALF, .{});
            shootAt(gg, name, v3(home.x, home.y + 2.6, home.z), LIT_YAW + 18, 0.10, dist);
        }
    }.at;
    const slam = rootedmod.moveClock(rootedmod.SLAM);
    const swp = rootedmod.moveClock(rootedmod.SWEEP);
    const hk = rootedmod.moveClock(rootedmod.HOOK);
    standHero(g, near.x, near.z, mathx.radians(LIT_YAW + 180));
    beat(g, t, sc, faceCam, rootedmod.SLAM, slam.wind * 0.9, "shots/118e_rooted_slam_cock.png", near, 11.0);
    beat(g, t, sc, faceCam, rootedmod.SLAM, slam.wind + slam.strike * 0.8, "shots/118f_rooted_slam.png", near, 11.0);
    beat(g, t, sc, faceCam, rootedmod.SWEEP, swp.wind + swp.strike * 0.6, "shots/118g_rooted_sweep.png", near, 11.0);
    const hookAt = along(sc, LIT_BACK, 4.2); // inside the hook's own (measured) band
    standHero(g, hookAt.x, hookAt.z, mathx.radians(LIT_YAW + 180));
    beat(g, t, sc, faceCam, rootedmod.HOOK, hk.wind + hk.strike * 0.7, "shots/118h_rooted_hook.png", hookAt, 13.0);

    g.hero.pos = mathx.ground(sc.x, sc.z - 40.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    spawn(t, sc, faceCam, 0.21);
    t.debugStagger(true);
    stepFoe(t, 16, far);
    shootAt(g, "shots/118i_rooted_stagger.png", v3(sc.x, sc.y + 2.8, sc.z), LIT_YAW + 20, 0.10, 11.0);

    spawn(t, sc, faceCam, 0.21);
    t.debugKill();
    stepFoe(t, 70, far);
    shootAt(g, "shots/118j_rooted_death.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW + 24, 0.12, 12.0);
    game.clearFoesForShot(g);
}

fn shroomShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(-24.0, 34.0); // the open patch west — small and low, it wants clean ground
    const far = along(sc, LIT_BACK, 90.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.cluster.n = 2;
    const m = &g.cluster.shrooms[0];
    const away = mathx.ground(sc.x - 60.0, sc.z + 60.0);
    const spawn = struct {
        fn it(s: *shroommod.Shroom, at: rl.Vector3, yaw: f32, seed: f32) void {
            s.* = shroommod.Shroom.spawn(at, yaw, 1.0, seed);
        }
    }.it;
    spawn(&g.cluster.shrooms[1], mathx.ground(sc.x + 1.1, sc.z + 0.8), faceCam, 0.72);

    spawn(m, sc, faceCam, 0.23);
    stepFoe(m, 40, far);
    stepFoe(&g.cluster.shrooms[1], 40, far);
    standHero(g, sc.x + 2.2, sc.z - 2.2, mathx.radians(-140));
    shootAt(g, "shots/119_shroom_pair.png", v3(sc.x, sc.y + 0.6, sc.z), LIT_YAW, 0.10, 4.6);

    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0); // out of the portraits below
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    spawn(&g.cluster.shrooms[1], away, faceCam, 0.5);

    const mark = along(sc, LIT_BACK, 3.4);
    spawn(m, sc, faceCam, 0.23);
    m.debugFling(mark);
    stepFoe(m, 32, mark);
    shootAt(g, "shots/119b_shroom_gather.png", v3(sc.x, sc.y + 0.5, sc.z), LIT_YAW, 0.06, 4.2);

    stepFoe(m, 22, mark); // gather ends at f38; f54 is just past the apex
    shootAt(g, "shots/119c_shroom_fling.png", v3(m.pos.x, m.pos.y + 1.2, m.pos.z), LIT_YAW, 0.06, 4.6);

    spawn(m, sc, faceCam, 0.23);
    m.debugFling(mark);
    var k: i32 = 0;
    while (k < 132) : (k += 1) _ = g.cluster.update(SHOT_DT, mark, game.PLAY_HALF, .{}); // landing + a second of bloom
    shootAt(g, "shots/119d_shroom_cloud.png", v3(mark.x, mark.y + 0.9, mark.z), LIT_YAW, 0.10, 7.0);

    // Shot from HIGH: from ground level the cap hides everything that says pratfall.
    spawn(m, sc, faceCam, 0.23);
    m.debugTrip(mark);
    stepFoe(m, 38 + 15 + 30, mark); // gather + the fall + deep in the sprawl
    shootAt(g, "shots/119e_shroom_trip.png", v3(sc.x, sc.y + 0.3, sc.z), LIT_YAW + 40, 0.45, 4.2);

    // …AND WHAT THE CLOUD IS ACTUALLY FOR: the status meter (`combat.Status`). THREE frames, because the
    // bar means three different things and only the colour and the direction tell them apart — filling is a
    // threat, full is a thing that has happened, and draining is the clock running out.
    poisonShots(g, mark);

    game.clearFoesForShot(g);
}

/// THE DELVER. Most of what it does is BELOW the frame, so every one of these is shot down onto the ground
/// rather than level at a body: a mound photographed at eye height is a bump you cannot see, and the burst
/// arrives from a direction the level camera has nothing to point at.
fn delverShots(g: *Game) void {
    game.clearFoesForShot(g);
    // ON THE GROUND THAT IS ACTUALLY THERE. `mathx.ground` is y = 0 and this patch is sculpted, so a body
    // staged with it stands BELOW the terrain — which is exactly how the hero went missing out of the frame
    // he was the whole point of.
    const sc = v3(-30.0, game.envGroundAt(&g.env, -30.0, 26.0), 26.0);
    const far = along(sc, LIT_BACK, 100.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.warrens.n = 1;
    const d = &g.warrens.delvers[0];
    const spawn = struct {
        fn it(dd: *delvermod.Delver, at: rl.Vector3, yaw: f32) void {
            dd.* = delvermod.Delver.spawn(at, yaw, 1.0, 0.37);
        }
    }.it;
    // Beats are named in SECONDS off the creature's own clocks, never in frame counts: a beat pinned to a
    // literal frame silently photographs somewhere else the next time a timing moves.
    const run = struct {
        fn secs(dd: *delvermod.Delver, clock: f32, toward: rl.Vector3) void {
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) _ = dd.update(SHOT_DT, toward, game.PLAY_HALF, .{});
        }
    }.secs;
    // **STANDING HIM TAKES MORE THAN ONE FRAME, and that is why he was missing from every frame here.**
    const stand = standSettled; // ONE copy now — see its own note for why a single update is not enough

    // THE STANDING PORTRAIT. A low body, so the lens comes down to it and in close, or it is a dark smudge
    // on grass — which is also the albedo question this frame exists to answer.
    spawn(d, sc, faceCam);
    stand(g, sc.x, sc.z - 40.0, 0);
    stepFoe(d, 30, far);
    shootAt(g, "shots/122_delver.png", v3(sc.x, sc.y + 0.7, sc.z), LIT_YAW, 0.16, 4.6);

    // THE DIVE'S TELL — up on its hind legs with both forelimbs overhead, the biggest silhouette it has and
    // the only frame of it readable from across a field.
    spawn(d, sc, faceCam);
    d.debugDive();
    run(d, DIVE_TELL_AT, far);
    shootAt(g, "shots/122b_delver_dive.png", v3(sc.x, sc.y + 0.9, sc.z), LIT_YAW, 0.12, 4.8);

    // THE MOUND, and it is the whole creature for most of the fight: nothing of the body is drawn, so what
    // this has to prove is that the ridge of earth reads as a ridge of earth. Shot down onto it.
    const mark = along(sc, LIT_BACK, 6.0);
    spawn(d, sc, faceCam);
    d.debugDive();
    run(d, 2.4, mark); // past the wind, past the drill, and a second of travelling under
    shootAt(g, "shots/122c_delver_mound.png", v3(d.pos.x, d.pos.y + 0.3, d.pos.z), LIT_YAW, 0.42, 5.0);

    // THE SURGE — the tell, at full swell, WITH THE HERO STANDING ON IT. That pairing is the shot: a dome of
    // earth beside an empty patch of ground says nothing about whether a player could read it.
    spawn(d, sc, faceCam);
    stand(g, sc.x, sc.z, mathx.radians(LIT_YAW + 180));
    d.state = .surge;
    d.t = 0;
    d.depth = delvermod.UNDER_DEPTH;
    run(d, SURGE_TELL_AT, g.hero.pos);
    shootAt(g, "shots/122d_delver_surge.png", v3(sc.x, sc.y + 0.7, sc.z), LIT_YAW, 0.20, 7.2);

    // …AND THE HOLE OPENING, three frames into the rise: the clods are up, the claws are through, and the
    // body is coming out of the ground it was under.
    run(d, (delvermod.SURGE_DUR - SURGE_TELL_AT) + delvermod.BURST_RISE * 0.9, g.hero.pos);
    shootAt(g, "shots/122e_delver_burst.png", v3(sc.x, sc.y + 0.9, sc.z), LIT_YAW, 0.22, 5.4);

    // THE CLAW at its crossing. Judged from ABOVE — a lateral arc off a low body foreshortens to nothing
    // head-on, which is the ogre's parry lesson at a fifth the size.
    spawn(d, sc, faceCam);
    stand(g, mark.x, mark.z, mathx.radians(LIT_YAW + 180));
    d.debugClaw();
    run(d, CLAW_TELL_AT, g.hero.pos);
    shootAt(g, "shots/122f_delver_claw.png", mathx.lerpV(v3(sc.x, sc.y + 0.9, sc.z), g.hero.pos, 0.5), LIT_YAW + 30, 0.40, 6.4);

    // …AND THE RETURN, at ITS crossing. The pair is the shot: the backhand has to read as the SAME limb
    // coming back rather than a second stroke, so it is framed exactly as the opener is.
    spawn(d, sc, faceCam);
    stand(g, mark.x, mark.z, mathx.radians(LIT_YAW + 180));
    d.debugRake();
    run(d, RAKE_TELL_AT, g.hero.pos);
    shootAt(g, "shots/122g_delver_rake.png", mathx.lerpV(v3(sc.x, sc.y + 0.9, sc.z), g.hero.pos, 0.5), LIT_YAW + 30, 0.40, 6.4);

    // THE PLOUGH'S TELL, and it is the one frame that has to be told apart from the surge's: this ridge is
    // STRETCHED down a heading where that one is a dome standing still. Shot down onto it from the same
    // height the mound was, so the two frames can be laid side by side.
    spawn(d, sc, faceCam);
    d.debugPlough();
    run(d, PLOUGH_TELL_AT, far);
    shootAt(g, "shots/122h_delver_plough_tell.png", v3(d.pos.x, d.pos.y + 0.4, d.pos.z), LIT_YAW + 70, 0.46, 8.5);

    // …AND THE FURROW RUNNING AT A MAN STANDING ON THE LINE. That pairing is the shot, the surge's own
    // reason: a ridge of earth beside an empty patch of ground says nothing about whether a player could
    // have read it in time to step off.
    spawn(d, sc, faceCam);
    const onLine = along(sc, LIT_BACK, 9.0);
    stand(g, onLine.x, onLine.z, mathx.headingXZ(mathx.dirXZ(onLine, sc))); // …facing what is coming at him
    d.facing = mathx.headingXZ(mathx.dirXZ(d.pos, g.hero.pos)); // committed, as the wind leaves it
    d.debugPlough();
    run(d, delvermod.PLOUGH_WIND + 0.34, g.hero.pos);
    const mid = mathx.lerpV(d.pos, g.hero.pos, 0.45);
    shootAt(g, "shots/122i_delver_plough.png", v3(mid.x, mid.y + 1.0, mid.z), LIT_YAW + 70, 0.30, 11.0);

    game.clearFoesForShot(g);
}

// The beats above, as FRACTIONS of the creature's own clocks — deep in the wind for the dive, near the top of
// the swell for the surge, and at the crossing for the claw. Written as seconds they were a second copy of
// every timing in `delver.zig`, so a retune there left the harness photographing a different moment and
// saying nothing about it.
const DIVE_TELL_AT: f32 = delvermod.DIVE_WIND * 0.84;
const SURGE_TELL_AT: f32 = delvermod.SURGE_DUR * 0.91;
const CLAW_TELL_AT: f32 = delvermod.CLAW_WIND + 0.08;
const RAKE_TELL_AT: f32 = delvermod.RAKE_WIND + 0.06;
/// Deep in the stretch, where the ridge has straightened and has not yet moved — the one frame that has to
/// be told apart from the surge's dome.
const PLOUGH_TELL_AT: f32 = delvermod.PLOUGH_WIND * 0.88;

// THE NECROMANCER'S BEATS, as FRACTIONS of its own clocks (the delver's rule above). The two GATHERS are shot
// near the top of their hauls, which is where each one is a picture rather than a body standing still.
const RAISE_TELL_AT: f32 = necromod.RAISE_WIND * 0.93;
const FROST_TELL_AT: f32 = necromod.FROST_WIND * 0.90;
/// …and the FUSE just over halfway down, which is the frame that shows the BAND whole with the runes part
/// way round it: at the cast none of them have caught and at the burst the whole mark is coming apart.
const FUSE_AT: f32 = necromod.FROST_FUSE * 0.58;

/// **THE HOUR ANYTHING THAT GLOWS HAS TO BE JUDGED AT.** Shared with `dayShots`' own night frame rather than
/// written out at each: two strips disagreeing about what night is would put a light past on one and fail it
/// on the other, and neither would be wrong about its own number.
pub const NIGHT_HOUR: f32 = 1.5;

fn necroShots(g: *Game) void {
    game.clearFoesForShot(g);
    // The delver's own clearing, which is the one patch out here with room BEHIND the subject as well as in
    // front: this creature backs away for its own hem shot and needs a corpse laid 2.6 m off it. The first
    // pass staged it at (-46, 4) and put the camera inside a ruin wall — FRAMING IS PART OF THE TEST, and a
    // spot is only open if the point `target + LIT_BACK * dist` is open too.
    const sc = v3(-30.0, game.envGroundAt(&g.env, -30.0, 24.0), 24.0);
    const far = along(sc, LIT_BACK, 100.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.rite.n = 1;
    const k = &g.rite.band[0];
    const spawn = struct {
        fn it(kk: *necromod.Necro, at: rl.Vector3, yaw: f32) void {
            kk.* = necromod.Necro.spawn(at, yaw, 1.0, 0.41);
        }
    }.it;
    const run = struct {
        fn secs(kk: *necromod.Necro, clock: f32, toward: rl.Vector3) void {
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) _ = kk.update(SHOT_DT, toward, game.PLAY_HALF, .{});
        }
    }.secs;
    const stand = standSettled; // see its own note: settling the cross-fade is why this is not `standHero`

    // **THE STANDING PORTRAIT**, and it is the one frame the whole brief is judged on: tall, skinny, the robe
    // dragging, the bone helm, the crooked staff. Framed on the CHEST rather than the middle, because on a rig
    // 2.4 m tall the middle puts the helm out of the top of the shot — and pulled back far enough that the
    // HEIGHT is what reads, which is the whole point of the creature.
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 6.0, 0);
    stepFoe(k, 30, far);
    shootAt(g, "shots/123_necro.png", v3(sc.x, sc.y + 1.5, sc.z), LIT_YAW, 0.06, 7.4);

    // …AND ITS HEM, which needs its own frame: the drag is a lag on the CLOTH against the body above it, so it
    // only exists while the thing is walking, and it is read from the SIDE. Close and low, on the hem itself.
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 3.0, 0);
    run(k, 1.6, v3(sc.x, sc.y, sc.z - 3.0)); // it backs away from him, which is when the hem trails
    shootAt(g, "shots/123b_necro_hem.png", v3(k.pos.x, k.pos.y + 0.55, k.pos.z), LIT_YAW + 62, 0.10, 4.2);

    // **THE RAISE'S GATHER** — the longest tell in the game, and the frame that has to carry it: the staff
    // planted, the free arm hauled up and back over the shoulder, the trunk arched off the body, and the helm
    // down on the corpse. Shot with a real skeleton lying at its feet, or the pose is a man pointing at grass.
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 7.0, 0);
    g.muster.n = 1;
    const body = &g.muster.band[0];
    body.* = warriormod.Warrior.spawnAs(.greatsword, along(sc, LIT_BACK, -2.6), faceCam, 1.0, 0.3);
    body.pos.y = game.envGroundAt(&g.env, body.pos.x, body.pos.z);
    body.debugKill();
    // HELD BEFORE IT IS STEPPED, or the picture is of a corpse part-way to gold: `foe.dissipate` starts fading
    // at `DEATH_DUR`, so stamping the hold afterwards froze it 14% dissolved and slightly shrunk. Set first, the
    // body falls, comes to rest and stops there — which is what the mechanic actually does on the field.
    body.heldOpen = true;
    // Let it fall and COME TO REST: `raisable` refuses a body still toppling, so a corpse photographed
    // mid-collapse is one the necromancer would not be reaching for. The archer's own figure, because the
    // warriors share it (their `DEATH_DUR` is that constant, one file along).
    stepFoe(body, @as(i32, @intFromFloat(archermod.DEATH_DUR / SHOT_DT)) + 8, far);
    k.vigil.at = body.pos;
    k.debugRaise(body.pos);
    run(k, RAISE_TELL_AT, g.hero.pos);
    shootAt(g, "shots/123c_necro_raise_tell.png", v3(k.pos.x, k.pos.y + 1.3, k.pos.z), LIT_YAW, 0.10, 6.6);

    // …and the TURN, where the arm is thrown down over the corpse and the gold pours into it. Framed to hold
    // BOTH bodies: what the move is about is the thing on the ground, not the thing casting.
    run(k, (necromod.RAISE_WIND - RAISE_TELL_AT) + 0.10, g.hero.pos);
    const between = mathx.lerpV(k.pos, body.pos, 0.5);
    shootAt(g, "shots/123d_necro_raise.png", v3(between.x, between.y + 1.0, between.z), LIT_YAW, 0.16, 7.0);
    g.muster.n = 0;

    // **THE FROST'S CAST**, and the reason it has its own frame is that it must not be mistakable for the
    // raise at a glance: the staff comes UP where the raise plants it, and the free hand goes out over the
    // ground rather than up behind the shoulder.
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 9.0, 0);
    k.debugFrost();
    run(k, FROST_TELL_AT, g.hero.pos);
    shootAt(g, "shots/123e_necro_frost_tell.png", v3(k.pos.x, k.pos.y + 1.4, k.pos.z), LIT_YAW, 0.10, 6.4);

    // **THE SIGIL BURNING DOWN AT HIS FEET** — the band, the runes taking round it, and the rime creeping. The
    // camera comes DOWN onto the ground, because this is the one thing in the game the player has to look at
    // his own boots to read, and a portrait pitch shows it as a smudge under him.
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 9.0, 0);
    k.debugLay(g.hero.pos);
    run(k, FUSE_AT, g.hero.pos);
    // Back and UP far enough to hold the WHOLE ring: at 5.6 m the rim ran off three sides of the frame, and a
    // countdown you have to infer from an arc of it is not the thing being tested.
    shootAt(g, "shots/123f_necro_sigil.png", v3(g.hero.pos.x, g.hero.pos.y + 0.35, g.hero.pos.z), LIT_YAW, 0.60, 10.5);

    // …and the BURST, one frame after the fuse runs out: the ring thrown outward past its own rim and the
    // shards off the ground. The one moment the move actually costs him something.
    run(k, (necromod.FROST_FUSE - FUSE_AT) + 0.06, g.hero.pos);
    shootAt(g, "shots/123g_necro_burst.png", v3(g.hero.pos.x, g.hero.pos.y + 0.5, g.hero.pos.z), LIT_YAW, 0.50, 10.0);

    // **AND THE SAME TWO AT NIGHT, WHICH IS WHERE THE MARK'S LIGHT IS THE WHOLE PICTURE** (`necro.SIGIL_LIT`).
    game.pinHourForShot(g, NIGHT_HOUR);
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 9.0, 0);
    k.debugLay(g.hero.pos);
    run(k, FUSE_AT, g.hero.pos);
    shootAt(g, "shots/123h_necro_sigil_night.png", v3(g.hero.pos.x, g.hero.pos.y + 0.35, g.hero.pos.z), LIT_YAW, 0.60, 10.5);
    run(k, (necromod.FROST_FUSE - FUSE_AT) + 0.06, g.hero.pos);
    shootAt(g, "shots/123i_necro_burst_night.png", v3(g.hero.pos.x, g.hero.pos.y + 0.5, g.hero.pos.z), LIT_YAW, 0.50, 10.0);
    // BACK TO THE ANCHOR: everything after this is judged under it (`dayShots`' own rule).
    game.pinHourForShot(g, game.daynight.SHOT_HOUR);

    game.clearFoesForShot(g);
}

/// THE ITEM PICKUP — the glow on the ground, the prompt over it, and the two ways it says what you got.
fn pickupShots(g: *Game) void {
    const saved = g.map.nops;
    if (saved + 1 > worldfmt.MAX_OPS) return;
    // The delver's clearing again: open, and open BEHIND the subject too (see `necroShots`).
    const cx: f32 = -28.0;
    const cz: f32 = 30.0;
    var op = worldfmt.defaults(.at);
    op.kind = .pickup;
    op.x = cx;
    op.z = cz;
    op.scale = 1;
    // 1+ ITEMS, which is the whole ask — and a REPEAT among them, so the toast's own count has something to say.
    op.loot[0] = .mushroom_jerky;
    op.loot[1] = .nameless_soul;
    op.loot[2] = .nameless_soul;
    op.nloot = 3;
    g.map.ops[g.map.nops] = op;
    g.map.nops += 1;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g); // …which re-homes the pickups too, and that is what we came for

    const gy = mathx.ground(cx, cz).y;
    // **STOOD IN REACH**, so the prompt is in the frame: the glow's whole job is to be walked up to, and a
    // portrait of it with no prompt is a picture of a prop rather than of an interactable.
    standSettled(g, cx, cz - 1.6, 0);
    game.stepPickupsForShot(g);
    shootAt(g, "shots/124_pickup.png", v3(cx, gy + 0.45, cz), LIT_YAW, 0.10, 4.2);

    // **THE FIRST-TIME CARD.** Fed by hand rather than by pressing the prompt: `--shot` runs no loop, so the
    // interact would need the whole input path — and what this frame is testing is the CARD, which is a pure
    // function of the queue.
    game.awardForShot(g, .grave_warbow, .first);
    game.awardForShot(g, .grave_warbow, .again);
    game.awardForShot(g, .grave_warbow, .again);
    game.awardForShot(g, .mushroom_jerky, .again);
    drawScene(g);
    hud(g, SHOT_DT);
    game.drawAwardCardForShot(g);
    snap("shots/124b_pickup_card.png");

    // …AND THE HELD TOAST ARRIVING once the card is read, which is the other half of the same rule: it was
    // owed, so it was not dropped. Dismissed through the queue's own path, not by clearing it.
    game.dismissAwardForShot(g);
    game.tickAwardForShot(g, 0.5);
    shoot(g, "shots/124b2_pickup_card_toast_after.png");

    // …AND THE TOASTS, stacked: three kinds already known, one of them twice, so the count reads too.
    game.awardForShot(g, .grave_warbow, .clear);
    game.awardForShot(g, .mushroom_jerky, .again);
    game.awardForShot(g, .nameless_soul, .again);
    game.awardForShot(g, .nameless_soul, .again);
    game.awardForShot(g, .iron_key, .again);
    // Past the slide-in and well short of the fade: the stack STANDING, which is the state worth a picture.
    game.tickAwardForShot(g, 0.5);
    shoot(g, "shots/124c_pickup_toasts.png");
    game.awardForShot(g, .iron_key, .clear);

    g.map.nops = saved;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
}

/// THE BONE KNIGHT. Five of the frames are the FALL, because that move is five distinct pictures and no one
/// of them says what it is: the tell (his back coming round to you), the topple, the strip landing, the roll
/// onto his front, and the rise. The strokes are shot from the LIT bearing with the hero on the sun's side;
/// the FALL is shot from ABOVE — a topple down the camera foreshortens to a man standing still. The CROUCH,
/// the STOMP and the CHARGE get a tell-and-arrival pair each, the same way the strokes do.
fn knightShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(3.0, -60.0); // the open avenue south, past the ogre — he needs room to lie down
    const far = along(sc, LIT_BACK, 120.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    // THE BOSS BAR fades in over a quarter second of LIVE frames, and a shot is one frame — primed here so
    // every knight frame carries the furniture the fight actually has. Dropped again at the bottom, or the
    // ghost of it fades across the next forty shots.
    g.bossK = 1.0;
    g.vigil.n = 1;
    const k = &g.vigil.knights[0];
    const spawn = struct {
        fn it(kk: *knightmod.Knight, at: rl.Vector3, yaw: f32) void {
            kk.* = knightmod.Knight.spawn(at, yaw, 1.0, 0.37);
        }
    }.it;
    // Beats are named in SECONDS off the creature's own clocks and stepped here — a beat pinned to a literal
    // frame count silently photographs somewhere else the next time a timing is tuned.
    const run = struct {
        fn secs(kk: *knightmod.Knight, clock: f32, toward: rl.Vector3) void {
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) _ = kk.update(SHOT_DT, toward, game.PLAY_HALF, .{});
        }
    }.secs;

    // THE STANDING PORTRAIT, SHOT THREE-QUARTER — and the hero parked OUT OF AGGRO: the sentinel brain
    // attacks anything staged inside its own bands, and a "standing portrait" of a windup is a lie with a
    // caption. Turned 42 deg off the lens so the door foreshortens and the body reads beside it.
    spawn(k, sc, mathx.headingXZ(mathx.headingDir(mathx.headingXZ(LIT_BACK) + mathx.radians(42.0))));
    standHero(g, far.x, far.z, mathx.radians(LIT_YAW + 180));
    stepFoe(k, 30, far); // settle the carry
    shootAt(g, "shots/121_knight.png", v3(sc.x, sc.y + 2.5, sc.z), LIT_YAW, 0.14, 12.0);

    // …AND FROM BEHIND, which is the picture of what the fight is about: no door on that side. Shot from the
    // SAME lit bearing — `LIT_YAW + 180` puts the sun in the lens and his front in his own shadow, so turning
    // the creature is the way to photograph its back.
    spawn(k, sc, mathx.headingXZ(mathx.scaleV(LIT_BACK, -1)));
    stepFoe(k, 30, far);
    shootAt(g, "shots/121a_knight_back.png", v3(sc.x, sc.y + 2.5, sc.z), LIT_YAW, 0.14, 12.0);

    g.hero.pos = mathx.ground(sc.x, sc.z - 44.0); // out of the beats below
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();

    // THE BASH — the door driven forward. Its own tell, then the frame it arrives on. Also three-quarter:
    // a shield coming straight down the lens does not travel across the frame at all.
    const near = along(sc, mathx.headingDir(mathx.headingXZ(LIT_BACK) + mathx.radians(38.0)), 4.0);
    const atHero = mathx.headingXZ(mathx.dirXZ(sc, near)); // squared onto him, so the stroke is aimed at him
    const bash = knightmod.moveClock(knightmod.BASH_I);
    spawn(k, sc, atHero);
    k.debugBash();
    run(k, bash.wind * 0.9, near);
    shootAt(g, "shots/121b_knight_bash_wind.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);
    run(k, bash.wind * 0.1 + bash.strike * 0.8, near);
    shootAt(g, "shots/121c_knight_bash.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);

    // THE QUICK SIDE ANSWERS and the LEAP, all shot in PROFILE — every one of them is a body moving
    // SIDEWAYS or BACKWARD, and a move that travels across the frame reads as nothing down the lens.
    spawn(k, sc, atHero);
    k.debugSwat(false);
    run(k, knightmod.moveClock(knightmod.SWAT_I).wind + knightmod.moveClock(knightmod.SWAT_I).strike * 0.55, near);
    shootAt(g, "shots/121v_knight_swat_sword.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW, 0.12, 12.0);
    spawn(k, sc, atHero);
    k.debugSwat(true);
    run(k, knightmod.moveClock(knightmod.SWAT_I).wind + knightmod.moveClock(knightmod.SWAT_I).strike * 0.55, near);
    shootAt(g, "shots/121w_knight_swat_shield.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW, 0.12, 12.0);
    // PHASE TWO'S AWAKENING, at the top of the hold — the blade over the helm with the chaos on it.
    spawn(k, sc, atHero);
    k.debugAwaken();
    run(k, knightmod.awakenPeak(), near);
    shootAt(g, "shots/121t_knight_awaken.png", v3(sc.x, sc.y + 3.2, sc.z), LIT_YAW, 0.18, 14.0);
    // …AND WHAT IT LEAVES ON THE GROUND from then on. Driven through the GROUP rather than the knight,
    // because the clouds are the Vigil's — a knight stepped one frame at a time lays none of them.
    spawn(k, sc, atHero);
    k.lit = true;
    k.debugSweep();
    {
        var gc: f32 = 0;
        // Just past the sweep's own impact: ONE cloud at full bloom, not the three a longer run stacks.
        const until = knightmod.moveClock(knightmod.SWEEP_I);
        while (gc < until.wind + until.strike + 0.75) : (gc += SHOT_DT) {
            _ = g.vigil.update(SHOT_DT, near, game.PLAY_HALF, .{});
        }
    }
    shootAt(g, "shots/121ta_knight_gas.png", v3(sc.x, sc.y + 1.4, sc.z), LIT_YAW, 0.10, 12.0);
    // …AND THE SAME CLOUD LATE IN ITS LIFE. "It does not dissipate" is unprovable from one frame, so the
    // pair is the test: full hang, then past `GAS_HANG` where the rate, the alpha and the radius all go out
    // together. Stepped through the GROUP so the clouds tick, with the hero out of reach so nothing new is
    // laid on top of the one being watched.
    {
        var gc: f32 = 0;
        const away = along(sc, mathx.headingDir(mathx.headingXZ(LIT_BACK)), 40.0);
        while (gc < knightmod.GAS_LIFE * 0.86) : (gc += SHOT_DT) {
            _ = g.vigil.update(SHOT_DT, away, game.PLAY_HALF, .{});
        }
    }
    shootAt(g, "shots/121tb_knight_gas_late.png", v3(sc.x, sc.y + 1.4, sc.z), LIT_YAW, 0.10, 12.0);
    // THE LEAP at the top of its arc — the one frame where he is genuinely off the earth.
    spawn(k, sc, atHero);
    k.debugLeap();
    run(k, knightmod.leapPeak(), near);
    shootAt(g, "shots/121y_knight_leap.png", v3(sc.x, sc.y + 2.8, sc.z), LIT_YAW, 0.16, 14.0);
    // …and the PIVOT STEP mid-drive, which is how he answers a flank on the ground.
    spawn(k, sc, atHero);
    k.debugStepTurn();
    run(k, knightmod.stepTurnMid(), near);
    shootAt(g, "shots/121z_knight_stepturn.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.14, 12.0);

    // THE SHOVE — the same row hauled onto whichever flank you are standing on. Shot at the gather and at
    // the drive, because what has to read is the door TRAVELLING; and shot BOTH WAYS, because the two are
    // one row with opposite signs and a picture of one says nothing about the other.
    spawn(k, sc, atHero);
    k.debugShove(false);
    run(k, bash.wind * 0.92, near);
    shootAt(g, "shots/121t_knight_shove_wind.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);
    run(k, bash.wind * 0.08 + bash.strike * 0.85, near);
    shootAt(g, "shots/121u_knight_shove.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);
    spawn(k, sc, atHero);
    k.debugShove(true);
    run(k, bash.wind + bash.strike * 0.85, near);
    shootAt(g, "shots/121ua_knight_shove_shield.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);

    // THE SWEEP — the big swipe, thrown from BEHIND THE WALL: the wind is the blade cocked level behind
    // him with the door still square, then the arc mid-stroke.
    const sweep = knightmod.moveClock(knightmod.SWEEP_I);
    spawn(k, sc, atHero);
    k.debugSweep();
    run(k, sweep.wind * 0.92, near);
    shootAt(g, "shots/121d_knight_sweep_cock.png", v3(sc.x, sc.y + 3.0, sc.z), LIT_YAW, 0.16, 13.0);
    run(k, sweep.wind * 0.08 + sweep.strike * 0.55, near);
    shootAt(g, "shots/121e_knight_sweep.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW, 0.10, 12.0);

    // THE OVERHEAD — steel standing above the helm, the one silhouette that reads at any range; shot at the
    // held top (the delayed downswing's hang) and again with the blade buried in its own follow-through.
    const over = knightmod.moveClock(knightmod.OVER_I);
    spawn(k, sc, atHero);
    k.debugOverhead();
    run(k, over.wind * 0.92, near);
    shootAt(g, "shots/121p_knight_over_cock.png", v3(sc.x, sc.y + 3.4, sc.z), LIT_YAW, 0.18, 13.0);
    run(k, over.wind * 0.08 + over.strike + over.recover * 0.20, near);
    shootAt(g, "shots/121q_knight_over_buried.png", v3(sc.x, sc.y + 2.0, sc.z), LIT_YAW, 0.14, 12.0);

    // THE THRUST — the chambered point (and the door risen a hand: the off-arm tell), then the full lunge.
    const thr = knightmod.moveClock(knightmod.THRUST_I);
    spawn(k, sc, atHero);
    k.debugThrust();
    run(k, thr.wind * 0.9, near);
    shootAt(g, "shots/121r_knight_thrust_cock.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);
    run(k, thr.wind * 0.1 + thr.strike * 0.9, near);
    shootAt(g, "shots/121s_knight_thrust.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 12.0);

    // THE SLAM — the door hauled overhead (his front standing open under it), then driven into the earth
    // with its crater dust going out.
    spawn(k, sc, atHero);
    k.debugSlam();
    const slam = knightmod.slamClock();
    run(k, slam.wind * 0.9, near);
    shootAt(g, "shots/121l_knight_slam_haul.png", v3(sc.x, sc.y + 3.2, sc.z), LIT_YAW, 0.16, 13.0);
    run(k, slam.wind * 0.1 + slam.strike * 0.65, near);
    // FRAMED ON THE CRATER, NOT ON HIM. The door lands a body-length AHEAD of his axis, so a camera aimed
    // at his own centre put the whole point of the move off the bottom of the frame — the shot showed his
    // back and no shield at all, which is how "the slam is busted" survived several passes of looking at it.
    {
        const mark = k.slamMarkOf();
        shootAt(g, "shots/121m_knight_slam.png", v3(mark.x, sc.y + 1.1, mark.z), LIT_YAW, 0.30, 12.0);
    }

    // THE CHARGE — the dig behind the door, then the wall at full tilt. The dig is shot square (what a
    // player standing off actually sees loading); the TRAVEL is shot in PROFILE, the fall's own rule: a
    // charge coming down the lens is a knight standing still, and the wake only reads behind a body that is
    // visibly crossing the frame.
    const chg = knightmod.chargeClock();
    spawn(k, sc, atHero);
    k.debugCharge();
    run(k, chg.wind * 0.9, near);
    shootAt(g, "shots/121n_knight_charge_dig.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW, 0.12, 11.0);
    const across2 = mathx.headingXZ(LIT_BACK) + mathx.radians(94.0);
    const farHero = along(sc, mathx.headingDir(across2), 16.0);
    spawn(k, sc, across2);
    k.debugCharge();
    run(k, chg.wind + 1.0, farHero);
    shootAt(g, "shots/121o_knight_charge.png", v3(k.pos.x, sc.y + 2.4, k.pos.z), LIT_YAW, 0.14, 13.0);
    // …and the SKID: reared over his heels with the door swung off the line — the opening the sidestep
    // earns, and the End Pose the recover then holds. A FRESH, SHORTER run: chasing the 16 m hero to the
    // travel's end parks him inside the cliffs east of the court, and a camera in a fade-thinned rock pile
    // photographs the rocks. A hero 7 m out is a 9.6 m line (the overrun), ~1.44 s of travel; +0.30 lands
    // a third into the brake, in the open.
    const skidWay = across2 + std.math.pi; // back the OTHER way — the court's own columns eat the first line
    const skidHero = along(sc, mathx.headingDir(skidWay), 7.0);
    spawn(k, sc, skidWay);
    k.debugCharge();
    run(k, chg.wind + 1.74, skidHero);
    shootAt(g, "shots/121o2_knight_charge_skid.png", v3(k.pos.x, sc.y + 2.2, k.pos.z), LIT_YAW, 0.14, 12.0);

    // THE FALL, all five beats, SHOT IN PROFILE FROM ABOVE. He is stood across the lens (facing 90 deg off
    // the camera's bearing) with the hero dead behind him, so the topple sweeps ACROSS the frame — pointed
    // toward or away from the lens the whole move foreshortens into a man standing still. `sc + back*L` is
    // where his body ends up, and that, not his feet, is what the later frames are aimed at.
    const across = mathx.headingXZ(LIT_BACK) + mathx.radians(90.0);
    const backDir = mathx.scaleV(mathx.headingDir(across), -1);
    const behind = along(sc, backDir, 3.6); // the hero, dead behind him: what makes the strip worth throwing
    const lying = along(sc, backDir, 2.6); // …and where the middle of the body comes to rest
    const fc = knightmod.fallClock();
    spawn(k, sc, across);
    k.debugFall();
    run(k, fc.wind * 0.88, behind);
    shootAt(g, "shots/121f_knight_fall_tell.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.20, 12.0);
    run(k, fc.wind * 0.12 + fc.drop * 0.55, behind);
    shootAt(g, "shots/121g_knight_falling.png", v3(lying.x, sc.y + 1.8, lying.z), LIT_YAW, 0.34, 12.0);
    run(k, fc.drop * 0.45 + 0.10, behind);
    shootAt(g, "shots/121h_knight_landed.png", v3(lying.x, sc.y + 0.9, lying.z), LIT_YAW, 0.40, 11.0);
    // Mid-roll: the one frame that says the body is turning over rather than lying still.
    run(k, fc.down - 0.10 + fc.roll * 0.55, behind);
    shootAt(g, "shots/121i_knight_rollover.png", v3(lying.x, sc.y + 0.8, lying.z), LIT_YAW, 0.36, 10.0);
    // …and coming up off the door, which is the last of the punish window.
    run(k, fc.roll * 0.45 + fc.rise * 0.58, behind);
    shootAt(g, "shots/121j_knight_rise.png", v3(lying.x, sc.y + 1.4, lying.z), LIT_YAW, 0.28, 11.0);

    // The death — FORWARD onto his face, which is what separates it from the fall he does on purpose.
    spawn(k, sc, faceCam);
    k.debugKill();
    stepFoe(k, 96, far);
    shootAt(g, "shots/121k_knight_death.png", v3(sc.x, sc.y + 1.2, sc.z), LIT_YAW + 26, 0.30, 12.0);

    knightStrokeStrips(g, sc, spawn, run);
    game.clearFoesForShot(g);
    g.bossK = 0; // see the prime at the top: the bar may not haunt the shots after this one
}

/// EVERY FRAME OF ALL THREE STROKES, IN PROFILE — a swing is a shape over TIME and the two-frame wind/impact
/// pair above cannot show one. He is stood ACROSS the lens with the hero out on the side he is swinging at, so
/// the arc travels across the frame instead of foreshortening down it; the whole wind AND the whole strike are
/// walked at a fixed step, so a stroke that snaps, windmills or arrives somewhere the body is not shows up as
/// a break between two adjacent frames rather than as a feeling.
fn knightStrokeStrips(
    g: *Game,
    sc: rl.Vector3,
    spawn: fn (*knightmod.Knight, rl.Vector3, f32) void,
    run: fn (*knightmod.Knight, f32, rl.Vector3) void,
) void {
    const k = &g.vigil.knights[0];
    const across = mathx.headingXZ(LIT_BACK) + mathx.radians(90.0);
    // The hero out on his STRIKING side, so the stroke is aimed across the lens rather than into it.
    const side = along(sc, mathx.headingDir(across), 4.2);
    // **THE FRAMES ARE SPENT WHERE THE MOTION IS, NOT SPREAD EVENLY OVER THE MOVE.** The sweep is 1.10 s of
    // wind and 0.38 s of strike, so an even walk lands most frames in the wind and one in the stroke — which
    // reads as a swing that never travels when what it actually shows is the held shiver at the top. Two
    // frames establish the gather; the remaining six are the STRIKE, which is the only part that sweeps.
    const NW = 2;
    const NS = 6;
    const strokes = [_]struct { i: usize, tag: []const u8, pitch: f32, dist: f32, lift: f32 }{
        .{ .i = knightmod.SWEEP_I, .tag = "x", .pitch = 0.20, .dist = 15.0, .lift = 3.2 },
        .{ .i = knightmod.BASH_I, .tag = "y", .pitch = 0.16, .dist = 13.0, .lift = 2.6 },
        .{ .i = knightmod.OVER_I, .tag = "z", .pitch = 0.18, .dist = 15.0, .lift = 3.2 },
        .{ .i = knightmod.THRUST_I, .tag = "w", .pitch = 0.14, .dist = 13.0, .lift = 2.6 },
    };
    inline for (strokes) |st| {
        const cl = knightmod.moveClock(st.i);
        var f: usize = 0;
        while (f < NW + NS) : (f += 1) {
            const at = if (f < NW)
                cl.wind * (0.45 + 0.40 * @as(f32, @floatFromInt(f)))
            else
                cl.wind + cl.strike * (@as(f32, @floatFromInt(f - NW)) + 0.5) / @as(f32, @floatFromInt(NS));
            // Re-spawned and re-run from zero each frame: stepping one clip and shooting as it goes would
            // photograph a body that has already been shoved down the field by the frames before it.
            spawn(k, sc, mathx.headingXZ(mathx.dirXZ(sc, side)));
            switch (st.i) {
                knightmod.SWEEP_I => k.debugSweep(),
                knightmod.OVER_I => k.debugOverhead(),
                knightmod.THRUST_I => k.debugThrust(),
                else => k.debugBash(),
            }
            run(k, at, side);
            var name: [64]u8 = undefined;
            const p = std.fmt.bufPrintZ(&name, "shots/121{s}{d}_knight_stroke.png", .{ st.tag, f }) catch continue;
            shootAt(g, p, v3(sc.x, sc.y + st.lift, sc.z), LIT_YAW, st.pitch, st.dist);
        }
    }
}

/// THE POISON METER, FILL → PROC → DRAIN. Shot with the hero STANDING IN the cloud rather than through a
/// debug poke, so what is photographed is the wiring the game actually runs (`game.tickPoisonForShot`).
fn poisonShots(g: *Game, mark: rl.Vector3) void {
    const soak = struct {
        fn it(gg: *Game, frames: i32) void {
            var k: i32 = 0;
            while (k < frames) : (k += 1) {
                _ = gg.cluster.update(SHOT_DT, gg.hero.pos, game.PLAY_HALF, .{});
                game.tickPoisonForShot(gg, SHOT_DT);
            }
        }
    }.it;

    g.hero.respawnNow(); // a clean bar, and full HP to watch the poison take off it
    game.clearFoesForShot(g);
    g.cluster.n = 1;
    const m = &g.cluster.shrooms[0];
    m.* = shroommod.Shroom.spawn(mathx.ground(mark.x - 6.0, mark.z), 0, 1.0, 0.23);
    standHero(g, mark.x, mark.z, mathx.headingXZ(LIT_BACK));

    m.debugFling(g.hero.pos);
    soak(g, 46 + 34); // its gather, then its flight — the cloud pops under him
    soak(g, 90);
    shootClear(g, "shots/119f_poison_filling.png", LIT_YAW, 0.10, 5.2);

    m.* = shroommod.Shroom.spawn(mathx.ground(mark.x - 6.0, mark.z), 0, 1.0, 0.23);
    m.debugFling(g.hero.pos);
    var k: i32 = 0;
    while (k < 60 * 6 and !g.hero.poison.active()) : (k += 1) {
        _ = g.cluster.update(SHOT_DT, g.hero.pos, game.PLAY_HALF, .{});
        game.tickPoisonForShot(g, SHOT_DT);
    }
    shootClear(g, "shots/119g_poison_proc.png", LIT_YAW, 0.10, 5.2);

    game.clearFoesForShot(g); // no cloud left: the meter is running on its own clock
    var d: i32 = 0;
    while (d < 60 * 6) : (d += 1) game.tickPoisonForShot(g, SHOT_DT);
    shootClear(g, "shots/119h_poison_draining.png", LIT_YAW, 0.10, 5.2);
    g.hero.respawnNow(); // …and nothing downstream inherits a poisoned hero
}

fn leechShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(-24.0, 34.0); // the same open patch west the shades and warriors are shot on
    const near = along(sc, LIT_BACK, 1.1);
    const far = along(sc, LIT_BACK, 90.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.swarm.n = 3;
    const f = &g.swarm.flies[0];
    const away = mathx.ground(sc.x - 60.0, sc.z + 60.0); // the other two, parked out of every portrait
    const spawn = struct {
        fn it(fly: *leechmod.Leechfly, at: rl.Vector3, yaw: f32, seed: f32) void {
            fly.* = leechmod.Leechfly.spawn(at, yaw, 1.0, seed);
        }
    }.it;

    // THE SWARM — three, because the wingbeat, the leg dangle and the abdomen's swing are all seeded and a
    // single portrait cannot show that no two of them are on the same frame of it.
    spawn(f, mathx.ground(sc.x - 1.5, sc.z), faceCam, 0.18);
    spawn(&g.swarm.flies[1], mathx.ground(sc.x + 0.4, sc.z + 1.3), faceCam, 0.61);
    spawn(&g.swarm.flies[2], mathx.ground(sc.x + 2.0, sc.z - 0.6), faceCam, 0.89);
    for (g.swarm.live()) |*fly| stepFoe(fly, 30, far);
    standHero(g, sc.x + 3.0, sc.z - 3.2, mathx.radians(-140));
    shootAt(g, "shots/117_swarm.png", v3(sc.x, sc.y + 1.5, sc.z), LIT_YAW, 0.04, 7.0);

    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0); // out of the portraits below
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    for ([_]usize{ 1, 2 }) |i| spawn(&g.swarm.flies[i], away, faceCam, 0.5);

    spawn(f, sc, faceCam, 0.18);
    stepFoe(f, 30, far);
    shootFoe(g, f, "shots/117a_leech_idle.png", LIT_YAW, 0.04, 3.4);
    // A PROFILE READ: the beak's tuck, the abdomen's droop and the wings' sweep are all invisible head-on.
    shootFoe(g, f, "shots/117b_leech_side.png", LIT_YAW + 68, 0.03, 3.4);
    // …and from ABOVE, which is the only angle the wings are a shape rather than an edge.
    shootFoe(g, f, "shots/117c_leech_top.png", LIT_YAW + 20, 0.85, 3.2);
    // …and a CROP of the head. Two dark beads and a beak are unjudgeable at 1:1 (the thin-geometry rule).
    shootAt(g, "shots/117d_leech_head.png", f.lockPoint(), LIT_YAW + 30, 0.02, 1.3);

    // WITH THE HERO IN FRAME: a drain photographed without the man it is taken from is an insect hovering.
    const beat = struct {
        fn at(gg: *Game, fly: *leechmod.Leechfly, home: rl.Vector3, face: f32, clock: f32, name: [:0]const u8, toward: rl.Vector3, dist: f32) void {
            fly.* = leechmod.Leechfly.spawn(home, face, 1.0, 0.18);
            fly.debugFeedFrom(clock);
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) _ = fly.update(SHOT_DT, toward, game.PLAY_HALF, .{});
            const mid = mathx.lerpV(fly.centerWorld(), v3(toward.x, toward.y + 1.15, toward.z), 0.5);
            shootAt(gg, name, mid, LIT_YAW + 84, 0.05, dist);
        }
    }.at;
    standHero(g, near.x, near.z, mathx.radians(LIT_YAW + 180));
    const fc = leechmod.feedClock();
    beat(g, f, sc, faceCam, fc.wind * 0.92, "shots/117e_leech_rear.png", near, 3.6);
    beat(g, f, sc, faceCam, fc.wind + fc.stab * 0.70, "shots/117f_leech_stab.png", near, 3.6);
    beat(g, f, sc, faceCam, fc.wind + fc.stab + 0.55, "shots/117g_leech_drink.png", near, 3.2);
    shootAt(g, "shots/117h_leech_eyes.png", f.lockPoint(), LIT_YAW + 20, 0.02, 1.2);

    // THE CLIMB — the whole creature in one frame. Shot from the GROUND looking up, because a flyer
    // photographed level with itself has not gone anywhere.
    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    spawn(f, sc, faceCam, 0.18);
    f.debugClimb();
    stepFoe(f, 26, near);
    standHero(g, sc.x + 0.5, sc.z - 2.4, mathx.radians(LIT_YAW + 180));
    // Level with the GAP between them, not above it: from overhead the man is a hat and the four metres it
    // has put between itself and his sword are foreshortened to nothing.
    shootAt(g, "shots/117i_leech_climb.png", v3(sc.x, sc.y + 3.1, sc.z), LIT_YAW, 0.12, 7.6);

    spawn(f, sc, faceCam, 0.18);
    f.debugStagger(true);
    stepFoe(f, 14, far);
    shootFoe(g, f, "shots/117j_leech_stagger.png", LIT_YAW + 20, 0.05, 3.6);

    spawn(f, sc, faceCam, 0.18);
    f.debugKill();
    stepFoe(f, 30, far);
    shootFoe(g, f, "shots/117k_leech_death.png", LIT_YAW + 24, 0.16, 3.8);
    game.clearFoesForShot(g);
}

fn shadeShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(-24.0, 34.0); // the same open patch west the warriors are shot on
    const near = along(sc, LIT_BACK, 1.4);
    const far = along(sc, LIT_BACK, 90.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.haunt.n = 3;
    const s = &g.haunt.shades[0];
    const away = mathx.ground(sc.x - 60.0, sc.z + 60.0); // the other two, parked out of every portrait
    const spawn = struct {
        fn it(sh: *shademod.Shade, at: rl.Vector3, yaw: f32, seed: f32) void {
            sh.* = shademod.Shade.spawn(at, yaw, 1.0, seed);
        }
    }.it;

    // THE HAUNTING — three of them, because the variation is authored BETWEEN the instances and a single
    // portrait cannot show that the hem, the hood and the lean differ from one to the next.
    spawn(s, mathx.ground(sc.x - 1.6, sc.z), faceCam, 0.18);
    spawn(&g.haunt.shades[1], mathx.ground(sc.x + 0.2, sc.z + 1.1), faceCam, 0.63);
    spawn(&g.haunt.shades[2], mathx.ground(sc.x + 1.9, sc.z - 0.4), faceCam, 0.87);
    for (g.haunt.live()) |*sh| stepFoe(sh, 40, far);
    standHero(g, sc.x + 3.0, sc.z - 3.2, mathx.radians(-140));
    shootAt(g, "shots/116_haunting.png", v3(sc.x, sc.y + 1.05, sc.z), LIT_YAW, 0.06, 7.6);

    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0); // out of the portraits below
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    for ([_]usize{ 1, 2 }) |i| spawn(&g.haunt.shades[i], away, faceCam, 0.5);

    spawn(s, sc, faceCam, 0.18);
    stepFoe(s, 40, far);
    shootFoe(g, s, "shots/116a_shade_idle.png", LIT_YAW, 0.04, 4.4);
    // A PROFILE READ: the hem's droop and the cowl's forward tip are both invisible head-on.
    shootFoe(g, s, "shots/116b_shade_side.png", LIT_YAW + 66, 0.04, 4.4);
    // …and a CROP of the cowl, since two self-lit eyes inside a hole are unjudgeable at 1:1. Framed off
    // `lockPoint` (the head) and not `centerWorld` (the chest), or the whole plate is skirt.
    shootAt(g, "shots/116c_shade_cowl.png", s.lockPoint(), LIT_YAW, 0.02, 1.9);

    // THE TOUCH, in two beats. The arms go WIDE first — that spread is the whole tell, and a single frame
    // of the closing pose is a move that came out of nowhere.
    const beat = struct {
        fn at(gg: *Game, sh: *shademod.Shade, home: rl.Vector3, face: f32, which: usize, clock: f32, name: [:0]const u8, toward: rl.Vector3, yaw: f32, dist: f32) void {
            sh.* = shademod.Shade.spawn(home, face, 1.0, 0.18);
            sh.debugMove(which);
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) {
                _ = sh.update(SHOT_DT, toward, game.PLAY_HALF, .{});
                game.stepArrowsForShot(gg, SHOT_DT); // …or the thrown wisp never leaves the hands
            }
            shootPortrait(gg, name, sh.centerWorld(), yaw, 0.05, dist);
        }
    }.at;
    const gc = shademod.moveClock(shademod.GRASP);
    beat(g, s, sc, faceCam, shademod.GRASP, gc.wind * 0.94, "shots/116d_grasp_wide.png", near, LIT_YAW + 16, 4.2);
    beat(g, s, sc, faceCam, shademod.GRASP, gc.wind + gc.strike * 0.62, "shots/116e_grasp_close.png", near, LIT_YAW + 16, 4.2);

    // THE WISP: the gather between the hands, and the frame it lets go on. Both are the same arm shape a
    // second apart, so the SHOT is what proves the ball is there before the throw and gone after it.
    const wc = shademod.moveClock(shademod.WISP);
    beat(g, s, sc, faceCam, shademod.WISP, wc.wind * 0.96, "shots/116f_wisp_gather.png", near, LIT_YAW + 16, 4.0);
    beat(g, s, sc, faceCam, shademod.WISP, wc.wind + wc.strike + 0.10, "shots/116g_wisp_thrown.png", near, LIT_YAW + 16, 5.4);
    game.clearShaftsForShot(g);

    // THE BLINK, caught halfway out and halfway back in — one frame of each, because the whole move is
    // over in under half a second and the thing it has to prove is that it THINS rather than popping.
    spawn(s, sc, faceCam, 0.18);
    s.debugBlink(near);
    var t: f32 = 0;
    while (t < shademod.BLINK_OUT * 0.62) : (t += SHOT_DT) _ = s.update(SHOT_DT, near, game.PLAY_HALF, .{});
    shootFoe(g, s, "shots/116h_blink_out.png", LIT_YAW, 0.05, 4.4);
    while (t < shademod.BLINK_OUT + shademod.BLINK_IN * 0.45) : (t += SHOT_DT) _ = s.update(SHOT_DT, near, game.PLAY_HALF, .{});
    shootFoe(g, s, "shots/116i_blink_in.png", LIT_YAW, 0.05, 4.4);

    spawn(s, sc, faceCam, 0.18);
    s.debugStagger(true);
    stepFoe(s, 16, far);
    shootFoe(g, s, "shots/116j_shade_stagger.png", LIT_YAW + 20, 0.06, 4.4);

    spawn(s, sc, faceCam, 0.18);
    s.debugKill();
    stepFoe(s, 22, far);
    shootFoe(g, s, "shots/116k_shade_death.png", LIT_YAW + 24, 0.10, 4.8);

    game.clearFoesForShot(g);
    game.rehomeFoesForShot(g);
}

/// THE TWO CAMPFIRES (`114`), side by side and in ONE frame, because the only thing that matters about
/// them is that you can tell which one you can sit at.
fn campfireShots(g: *Game) void {
    const saved = g.map.nops;
    if (saved + 2 > worldfmt.MAX_OPS) return;
    // OPEN GROUND, west, the same patch the warriors are shot on. Sited by eye instead, the first
    // attempt put both fires inside a cliff and came back as a frame of solid rock.
    const cx: f32 = -24.0;
    const cz: f32 = 40.0;
    for ([_]struct { k: props.Kind, dx: f32 }{
        .{ .k = .campfire, .dx = -1.8 },
        .{ .k = .campfire_lit, .dx = 1.8 },
    }) |row| {
        var op = worldfmt.defaults(.at);
        op.kind = row.k;
        op.x = cx + row.dx;
        op.z = cz;
        op.scale = 1;
        g.map.ops[g.map.nops] = op;
        g.map.nops += 1;
    }
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g); // …which re-homes the REST SITES too, and that is what we came for

    const gy = mathx.ground(cx, cz).y;
    g.hero.pos = mathx.ground(cx, cz - 24.0); // out of frame: this shot is about the two fires
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    shootPortrait(g, "shots/114_campfires.png", v3(cx, gy + 0.5, cz), LIT_YAW, 0.16, 6.4);
    // …and a CROP of the dead one, where the ash drift and the unburnt log ends actually read.
    shootPortrait(g, "shots/114b_campfire_dead.png", v3(cx - 1.8, gy + 0.30, cz), LIT_YAW, 0.20, 2.6);
    // THE PROMPT: stand him in reach of the LIT one, which is the whole of "it is an interactable".
    const right = v3(-LIT_BACK.z, 0, LIT_BACK.x);
    const hx = cx + 1.8 + right.x * 1.7;
    const hz = cz + right.z * 1.7;
    standHero(g, hx, hz, mathx.headingXZ(v3(cx + 1.8 - hx, 0, cz - hz)));
    g.rest.look(g.hero.pos);
    shootAt(g, "shots/114c_campfire_prompt.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 4.6);

    g.map.nops = saved;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g); // …which re-homes the REST SITES too, and that is what we came for
}

/// WHAT A DEATH LEAVES ON THE GROUND. Photographed at THREE moments, because the whole read of the thing is
/// that it is a growing, turning, breathing bloom and not a decal: half way out of the earth, fully up with
/// the prompt on it, and with the man standing in its ring.
fn soulsShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(-14.0, 30.0); // the open ground west — a bloom of light wants nothing behind it
    const gy = mathx.ground(sc.x, sc.z).y;
    const aim = v3(sc.x, gy + soulsmod.H * 0.55, sc.z);
    // SQUARE TO THE BOOM rather than on the sun's line, so both he and the gold are in frame. SCREEN-RIGHT
    // of the gold at yaw 53 — `camera.rightXZ`, not the boom's own perpendicular.
    const screenRight = v3(-mathx.cosf(mathx.radians(LIT_YAW)), 0, mathx.sinf(mathx.radians(LIT_YAW)));
    const hero = v3(sc.x + screenRight.x * 2.1, 0, sc.z + screenRight.z * 2.1);
    standHero(g, hero.x, hero.z, mathx.headingXZ(v3(sc.x - hero.x, 0, sc.z - hero.z)));
    // …AND THE STANCE BLENDS SETTLED. `standHero` steps ONE frame, and `heroFade` is driven off `aimB`, so
    // an unsettled aim draws him FULLY TRANSPARENT and the picture comes out with nobody in it.
    g.hero.setAim(false);
    g.hero.setGuard(false);
    var settle: u32 = 0;
    while (settle < 40) : (settle += 1) g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    const between = v3((sc.x + hero.x) * 0.5, gy + 0.9, (sc.z + hero.z) * 0.5);

    g.souls.clear();
    g.souls.spill(v3(sc.x, gy, sc.z), 4820);
    var t: f32 = 0;
    while (t < 0.22) : (t += SHOT_DT) g.souls.update(SHOT_DT);
    shootAt(g, "shots/120_souls_rising.png", aim, LIT_YAW, 0.10, 4.2);
    while (t < 2.4) : (t += SHOT_DT) g.souls.update(SHOT_DT);
    shootAt(g, "shots/120a_souls_bloom.png", aim, LIT_YAW, 0.10, 4.2);
    g.souls.look(g.hero.pos);
    shootAt(g, "shots/120b_souls_prompt.png", aim, LIT_YAW, 0.16, 5.4);
    _ = g.souls.take(g.hero.pos);
    t = 0;
    while (t < 0.12) : (t += SHOT_DT) g.souls.update(SHOT_DT);
    shootAt(g, "shots/120c_souls_reclaim.png", between, LIT_YAW, 0.12, 5.6);
    g.souls.clear();
}

fn chestShots(g: *Game) void {
    const cx: f32 = 12.0;
    const cz: f32 = 10.0;
    const saved = g.map.nops;
    if (saved >= worldfmt.MAX_OPS) return;
    var op = worldfmt.defaults(.at);
    op.kind = .chest;
    op.x = cx;
    op.z = cz;
    // Derived, not guessed: `drawModelEx` turns about +Y, sending local +Z to (sin yaw, 0, cos yaw), and
    // the camera at yaw 53 sits toward (−0.794, 0, −0.608).
    op.yaw = 233;
    op.loot[0] = .golden_seed;
    op.loot[1] = .rune_arc;
    op.loot[2] = .mushroom_jerky;
    op.loot[3] = .kobold_fang; // shot below is of a list with a usable row in it and not just names
    op.nloot = 4;
    g.map.ops[g.map.nops] = op;
    g.map.nops += 1;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
    g.bag = .{};

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

    // THE CHARACTER BOOK — a frame per page, and the pages are the whole reason it exists, so each one is
    // staged on the state that has something to show: a picker OPEN over its delta column, a bag with
    // enough in it to fill a grid, an attribute that owns a bar.
    for ([_]item.Kind{ .mushroom_jerky, .bloodgrass, .kobold_fang, .rune_arc, .golden_seed, .smithing_stone, .iron_key, .fire_tallow, .thundercrock, .nameless_soul, .toadflesh_broth, .spirit_scroll_wolf }) |k| {
        if (g.bag.count(k) == 0) g.bag.add(k, if (k == .bloodgrass) 12 else 3);
    }
    // …AND EVERY PIECE OF GEAR, WALKED rather than listed: the doll's whole job is showing what fills its sockets,
    // and a hand-written list is what left the five newest pieces out of the one frame that would have shown them.
    for (0..item.NK) |i| {
        const k: item.Kind = @enumFromInt(i);
        if (item.wearable(k) and g.bag.count(k) == 0) g.bag.add(k, 1);
    }
    g.menu.onStartButton();
    bookShot(g, "shots/106e_book_equipment.png", .equipment, bookmod.slotOrdinal(.right), null, 0);
    bookShot(g, "shots/106f_book_swap.png", .equipment, bookmod.slotOrdinal(.right), bookmod.slotOrdinal(.right), 1);
    // …AND THE BELL PRICED, the one candidate that does not swing (`hero.armSwings`): light, heavy, poise,
    // stance and both stamina rows go to NOTHING beside the sword's. They read the sword's own numbers before,
    // which priced a swing the arm does not have — and its socket drew a sword in his fist to match.
    bookShot(g, "shots/106f3_book_bell.png", .equipment, bookmod.slotOrdinal(.right), bookmod.slotOrdinal(.right), 2);
    // cursor sits on the jerky — the one row that is not a flask.
    bookShot(g, "shots/106f2_book_quickbar.png", .equipment, bookmod.slotOrdinal(.q2), bookmod.slotOrdinal(.q2), 3);
    bookShot(g, "shots/106g_book_inventory.png", .inventory, 0, null, 0);
    // …AND THE PAGE THE NEWEST GEAR IS ON. A bag with every kind in it runs past one grid, so the frame staged at
    // cursor 0 shows the oldest twenty rows and nothing else — which is exactly the page a new item is never on.
    bookShot(g, "shots/106g2_book_inventory_p2.png", .inventory, item.NK - 1, null, 0);
    bookShot(g, "shots/106h_book_stats.png", .stats, @intFromEnum(stats.Attr.endurance), null, 0);
    // …AND A SKILL, which answers in a MULTIPLE rather than a bar's length (`stats.scaleFor`). Both kinds of row
    // need a frame: the one staged on endurance cannot show the line the other three print.
    bookShot(g, "shots/106h2_book_stats_skill.png", .stats, @intFromEnum(stats.Attr.strength), null, 0);
    // THE PASSIVE TREE in the book, which is READ-ONLY — the fire's own copy (`71i`) is the one that spends.
    bookShot(g, "shots/106i_book_tree.png", .tree, ptree.armFirst(.wizard) + ptree.PER_ARM - 1, null, 0);

    // **AND THE PAGE WITH THE SUIT ACTUALLY ON**, which is the one frame every socket and every row exists for:
    // staged bare, the doll is seven empty holes and the NOW column reads the plain sword's figures whatever is
    // in the bag, so nothing here could ever show a filled socket or a number that moved with it.
    const wornWas = g.hero.worn;
    for ([_]item.Kind{ .greatclub, .tower_shield, .quilted_gambeson, .pitted_helm, .marchboots, .banded_warbelt, .ashen_amulet, .leech_signet, .deft_signet }) |k| {
        _ = g.hero.wear(item.wearSlot(k).?, k);
    }
    bookShot(g, "shots/106e2_book_geared.png", .equipment, bookmod.slotOrdinal(.chest), null, 0);
    // …and the picker over a filled socket, where the delta column is priced against what he already has on.
    bookShot(g, "shots/106e3_book_geared_pick.png", .equipment, bookmod.slotOrdinal(.right), bookmod.slotOrdinal(.right), 0);
    // PUT BACK THROUGH THE SAME DOOR (`save.scatter`'s own idiom), never by assignment: `wear` is what carries
    // the sheet and the three bar lengths back with it, and the signet was eating into the red one.
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        const w: item.Wear = @enumFromInt(f.value);
        _ = g.hero.wear(w, wornWas.at(w));
    }
    g.menu.screen = .closed;

    g.map.nops = saved;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
}

/// Turn him to the LENS and re-pose, without stepping his behaviour. "Stand the hero on the sun's bearing"
/// collapses for a body that TURNS: the sun's bearing IS the camera's, so the hero ends up in the lens.
fn faceLens(p: *npcmod.Wanderer) void {
    p.facing = mathx.headingXZ(LIT_BACK);
    p.wantYaw = p.facing;
    p.pose();
}

/// Park the hero far enough out that he is neither in frame nor inside `npc.NOTICE_R`.
fn heroAside(g: *Game, from: rl.Vector3) void {
    standHero(g, from.x + 34, from.z + 34, 0);
    plantHeroForShot(g);
}

/// THE FOLK AND WHAT THEY SAY. Two things here cannot be judged from one frame and so get several: the staff
/// PLANT, which happens once a stride, and the panel, which has a different shape for answers and for a plain
/// Continue. The `need:` gate needs two frames by definition — the same node before and after it opens.
fn folkShots(g: *Game) void {
    if (g.folk.n == 0) {
        std.debug.print("--shot needs at least one npc posted in {s}\n", .{worldfmt.START_MAP});
        @panic("shot harness: the map posts nobody to photograph");
    }
    const p = &g.folk.list[0];
    const post = p.pos;
    const eye = v3(post.x, post.y + 1.02, post.z);
    const face = v3(post.x, post.y + 1.50, post.z);

    heroAside(g, post);
    var k: i32 = 0;
    while (k < 90) : (k += 1) game.stepFolkForShot(g, SHOT_DT); // let the idle clocks settle somewhere
    p.pos = post;

    faceLens(p);
    shootPortrait(g, "shots/108_npc_hooded.png", eye, LIT_YAW, 0.10, 3.4);
    shootPortrait(g, "shots/108b_npc_hood_face.png", face, LIT_YAW, 0.06, 1.30);

    p.variant = 1;
    shootPortrait(g, "shots/108c_npc_bare.png", eye, LIT_YAW, 0.10, 3.4);
    shootPortrait(g, "shots/108d_npc_bare_face.png", face, LIT_YAW, 0.06, 1.30);
    p.variant = 0;

    // A PORTRAIT OF EACH OF THE FOLK, framed the way the CONVERSATION PANEL frames one — off the posed skull
    // (`facePoint`), not off a height above the feet, and three-quarters on. One per body: "the wanderer" is
    // more than one head, and a single shot of the first of them says nothing about the second.
    for (g.folk.live(), 0..) |*q, i| {
        var nameBuf: [64]u8 = undefined;
        const path = std.fmt.bufPrintZ(&nameBuf, "shots/108p_npc_portrait_{d}.png", .{i}) catch continue;
        faceLens(q);
        shootPortrait(g, path, q.facePoint(), LIT_YAW + hudmod.PORTRAIT_YAW, hudmod.PORTRAIT_PITCH, npcmod.PORTRAIT_DIST);
    }
    faceLens(p);

    p.greet();
    k = 0;
    while (k < 17) : (k += 1) game.stepFolkForShot(g, SHOT_DT); // ~half of the gesture
    p.pos = post;
    faceLens(p);
    shootPortrait(g, "shots/108e_npc_beckon.png", eye, LIT_YAW, 0.10, 3.7);

    // THE AMBLE, IN PROFILE, at the plant and at the carry. A GAIT IS READ IN PROFILE and nothing else will do,
    // so his heading is chosen BACKWARD off the framing: `LIT_YAW` less a quarter turn, which puts the sun on
    // him and the camera square to his travel at the same time. Left to his own errands he walks wherever the
    // seed sends him, which the first pass proved is into the cliff shadow, where nothing can be judged.
    const laneYaw = mathx.radians(LIT_YAW - 90.0);
    // OUT ON THE DOWNS. The framing has to be CLEAR as well as lit: at the bonfire the boom at four metres ends
    // up inside the rubble and the frame is a picture of the inside of a rock.
    const lane = mathx.ground(14, 70);
    p.home = lane;
    p.pos = lane;
    p.roamR = worldfmt.NPC_ROAM_MAX;
    p.dwell = 0;
    p.facing = laneYaw;
    const lead = mathx.headingDir(laneYaw);
    var seen: i32 = 0;
    while (seen < 2) : (seen += 1) {
        const want: f32 = if (seen == 0) 0.50 else 0.02;
        var guard: i32 = 0;
        while (guard < 2400) : (guard += 1) {
            // Held on ONE heading by re-aiming the errand each step, so he neither arrives nor re-decides.
            p.target = along(p.pos, lead, 8.0);
            game.stepFolkForShot(g, SHOT_DT);
            const d = @abs(p.phase - want);
            if (p.moving > 0.9 and @min(d, 1.0 - d) < 0.02) break;
        }
        must(p.moving > 0.9, "the wanderer never set off, so there is no gait to photograph");
        const at = v3(p.pos.x, p.pos.y + 1.0, p.pos.z);
        shootPortrait(g, if (seen == 0) "shots/108f_npc_staff_plant.png" else "shots/108g_npc_carry.png", at, LIT_YAW, 0.08, 4.0);
    }

    // The hero stands OFF the boom by `TALK_OFF` degrees so the camera at `LIT_YAW` has the pair side by
    // side; behind him on the sun's bearing the wanderer is a hood over his shoulder.
    const TALK_OFF: f32 = 52.0;
    const stand = along(post, mathx.headingDir(mathx.headingXZ(LIT_BACK) + mathx.radians(TALK_OFF)), 2.0);
    p.pos = post;
    standHero(g, stand.x, stand.z, mathx.headingXZ(mathx.subV(post, stand)));
    plantHeroForShot(g);
    game.stepFolkForShot(g, SHOT_DT);
    const pair = mathx.lerpV(eye, g.hero.shoulderPoint(), 0.5);
    // THE PROMPT FIRST: it is the only thing that says a body in this world is one you can speak to rather
    // than one you have to kill.
    shootPortrait(g, "shots/108h_npc_prompt.png", pair, LIT_YAW, 0.12, 4.6);

    must(game.openTalkForShot(g, "wanderer"), "the wanderer's dialog would not open");
    talkShot(g, "shots/108i_dialog_root.png", pair, 20, .{});
    talkShot(g, "shots/108j_dialog_cursor.png", pair, 1, .{ .down = true });
    talkShot(g, "shots/108k_dialog_continue.png", pair, 4, .{ .pick = 1 });
    // …and back at the root the GATED line is offered, because that node's `act:` opened it. Three answers
    // where there were two — the whole point of `need:`, and unprovable from one frame.
    talkShot(g, "shots/108l_dialog_gate_open.png", pair, 4, .{ .confirm = true });

    var bail: i32 = 0;
    while (g.talk.active() and bail < 40) : (bail += 1) game.stepTalkForShot(g, .{ .pick = 3 });
    must(!g.talk.active(), "the conversation would not close");
    g.folk.hush();

    // FOUND, not indexed: `trigs[0].acts[1]` is two magic numbers into an authoring table anybody may
    // reorder, and a `do:` inserted above the text photographs a switch.
    g.trig.apply(&g.map, firstTextAct(&g.map) orelse {
        must(false, "the map has no `text` action to photograph");
        return;
    });
    shootPortrait(g, "shots/108m_trigger_banner.png", pair, LIT_YAW, 0.12, 4.6);

    g.trig.arm(&g.map);
    g.folk.reset(&g.map);
}

/// The first `text` action the map authors, wherever it sits — the banner shot needs a real line and does not
/// care whose trigger it belongs to.
fn firstTextAct(m: *const worldfmt.Map) ?*const worldfmt.Act {
    for (m.trigSlice()) |*t| {
        for (t.actSlice()) |*a| {
            if (a.kind == .text) return a;
        }
    }
    return null;
}

/// One frame of the panel: press `in`, settle `frames`, then scene + panel. `hud` is deliberately NOT called —
/// the live loop suppresses it behind a conversation, and a harness that drew it would be photographing a
/// screen the game never shows.
fn talkShot(g: *Game, name: [:0]const u8, at: rl.Vector3, frames: i32, in: dialogmod.Input) void {
    game.stepTalkForShot(g, in);
    var k: i32 = 0;
    while (k < frames) : (k += 1) game.stepTalkForShot(g, .{});
    g.rig.yaw = mathx.radians(LIT_YAW);
    g.rig.pitch = 0.12;
    g.rig.dist = 4.6;
    g.rig.followCentred(at);
    drawScene(g);
    game.drawTalkForShot(g);
    snap(name);
}

// THE EDITOR — its whole job is legibility, and none of that can be judged from the game shots.
fn editorSnap(g: *Game, name: [:0]const u8) void {
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, SHOT_DT);
    snap(name);
}

/// The editor with the JUKEBOX modal up — the sound rack's own frame. Its own helper because the modal is
/// opened through the editor's real entry point (`editor.soundsForShot`), never by poking `modal` from here:
/// the panel reads state that entering sets up.
fn editorJukeShot(g: *Game, name: [:0]const u8) void {
    g.editor.enter(mathx.ground(0, -66));
    g.editor.applyCamForShot();
    g.editor.soundsForShot(.ogre_slam); // a combat voice, so the rack beside it is the one being turned
    g.editor.rackMix = .combat;
    editorSnap(g, name);
    g.editor.on = false;
}

/// THE TWO PANELS THAT REACH WHAT NO BRUSH COULD — the map's own size/runway/rim, and what a zone grows.
fn editorGapShots(g: *Game) void {
    g.editor.enter(mathx.ground(0, -66));
    g.editor.applyCamForShot();
    g.editor.worldForShot();
    editorSnap(g, "shots/116a_editor_world.png");

    g.editor.zoneMixForShot(&g.map, 0);
    editorSnap(g, "shots/116b_editor_zonemix.png");

    // …and the DENSITY GRADIENT rows, which live in the belt inspector rather than in a modal: select a
    // belt, turn a gradient on, and photograph the panel that had no control for it at all until now.
    g.editor.closeModalForShot();
    for (g.map.slice(), 0..) |o, i| {
        if (o.op == .belt) {
            g.editor.gradientForShot(&g.map, i); // …which sets the layer the op actually lives on
            break;
        }
    }
    editorSnap(g, "shots/116c_editor_gradient.png");
    g.editor.on = false;
}

fn editorShots(g: *Game) void {
    g.editor.enter(mathx.ground(0, -66)); // the chapel end of the processional way
    g.editor.setLayer(.props);
    g.editor.dist = 46;
    g.editor.pitch = -0.65;
    g.editor.applyCamForShot();

    editorSnap(g, "shots/95_editor_props.png");

    g.editor.setLayer(.props);
    for (g.map.slice(), 0..) |o, i| {
        if (o.op == .belt and o.nmix > 3) {
            g.editor.sel = i;
            g.editor.focusOnForShot(&g.map, i);
            break;
        }
    }
    editorSnap(g, "shots/96_editor_selected.png");

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
    editorSnap(g, "shots/97_editor_drag.png");
    g.editor.dragging = false;

    const before = g.map.soil;
    const beforeCov = g.map.soilCov;
    const beforeEdge = g.map.soilEdge;
    g.editor.setLayer(.ground);
    g.editor.brush[@intFromEnum(editormod.Layer.ground)] = @intFromEnum(editormod.GroundBrush.dirt);
    g.editor.radius = 5;
    var z: f32 = 22;
    while (z > -40) : (z -= 3) _ = g.map.paintSoil(0.6, z, 4.5, .dirt, 1, .natural);
    _ = g.map.paintSoil(0, -30, 9, .stone, 1, .tiled);
    _ = g.map.paintSoil(-13.5, 3, 6, .moss, 0.5, .natural);
    g.env.uploadSoil(&g.map);
    g.editor.focus = mathx.ground(0, -10);
    g.editor.pitch = -0.85;
    g.editor.yaw = std.math.pi;
    g.editor.dist = 46;
    g.editor.applyCamForShot();
    editorSnap(g, "shots/98_editor_ground.png");

    g.map.soil = before;
    g.map.soilCov = beforeCov;
    g.map.soilEdge = beforeEdge;
    g.env.uploadSoil(&g.map);

    const beforeWater = g.map.water;
    g.editor.setLayer(.ground);
    g.editor.brush[@intFromEnum(editormod.Layer.ground)] = @intFromEnum(editormod.GroundBrush.water);
    g.editor.radius = 7;
    var wz: f32 = -6;
    while (wz < 26) : (wz += 2.5) _ = g.map.paintWater(-26 + wz * 0.35, wz, 9.5, true, .natural);
    var wx: f32 = -34;
    while (wx < -8) : (wx += 2.5) _ = g.map.paintWater(wx, 14, 7.5, true, .natural);
    _ = g.map.paintWater(-21, 9, 4.6, false, null); // the headland
    g.env.uploadWater(&g.map);
    g.env.materialize(&g.map);
    g.editor.focus = mathx.ground(-24, 10);
    g.editor.pitch = -0.34;
    g.editor.yaw = 2.4;
    g.editor.dist = 34;
    g.editor.applyCamForShot();
    editorSnap(g, "shots/98b_editor_water.png");
    g.editor.pitch = -1.15;
    g.editor.dist = 58;
    g.editor.applyCamForShot();
    editorSnap(g, "shots/98c_editor_water_map.png");

    g.map.water = beforeWater;
    g.env.uploadWater(&g.map);
    g.env.materialize(&g.map); // the paint re-sowed the world against a lake that is no longer there

    g.editor.setLayer(.props);
    g.editor.focus = mathx.ground(0, -12);
    g.editor.pitch = -0.8;
    g.editor.yaw = std.math.pi;
    g.editor.dist = 40;
    g.editor.applyCamForShot();
    g.editor.selectForShot(&g.map, mathx.ground(-20, -30), mathx.ground(20, 6));
    editorSnap(g, "shots/99_editor_marquee.png");

    g.editor.openForShot();
    editorSnap(g, "shots/99b_editor_open.png");

    g.editor.objectsForShot(.props, 0, null);
    editorSnap(g, "shots/99c_editor_objects.png");

    g.editor.objectsForShot(.props, 0, .well);
    editorSnap(g, "shots/99d_editor_object_one.png");

    g.editor.objectsForShot(.decor, 0, null);
    editorSnap(g, "shots/99e_editor_objects_decor.png");

    g.editor.modal = .none;
    g.editor.setLayer(.interact);
    g.editor.selecting = false;
    g.editor.focus = mathx.ground(0, -12);
    g.editor.pitch = -0.7;
    g.editor.yaw = std.math.pi;
    g.editor.dist = 34;
    g.editor.applyCamForShot();
    editorSnap(g, "shots/99f_editor_interact.png");

    g.editor.soundsForShot(.ogre_slam);
    editorSnap(g, "shots/99g_editor_sounds.png");
    g.editor.modal = .none;

    g.editor.on = false;
    elevationShots(g);
}

/// Eight frames of the SAME view under eight hours, so what is judged is the ARC and not any one sky.
fn dayShots(g: *Game) void {
    const at = mathx.ground(0, -14.0);
    standHero(g, at.x, at.z, mathx.radians(game.daynight.SHOT_HOUR * 0)); // facing +Z, square to the lens
    plantHeroForShot(g);
    game.clearFoesForShot(g);
    game.clearShaftsForShot(g);
    const hours = [_]struct { h: f32, name: [:0]const u8 }{
        .{ .h = NIGHT_HOUR, .name = "shots/140_day_night.png" },
        .{ .h = 5.2, .name = "shots/141_day_firstlight.png" },
        .{ .h = 6.2, .name = "shots/142_day_sunrise.png" },
        .{ .h = 8.5, .name = "shots/143_day_morning.png" },
        .{ .h = 12.0, .name = "shots/144_day_noon.png" },
        .{ .h = game.daynight.SHOT_HOUR, .name = "shots/145_day_golden.png" },
        .{ .h = 19.4, .name = "shots/146_day_sunset.png" },
        // …AND THE LAST ROW IS THE HOUR THE FIRE HANDS YOU (`EVENING_HOUR`), not a number beside it: the strip
        // is the only eye on "Rest until evening", so it photographs that hour exactly.
        .{ .h = game.daynight.EVENING_HOUR, .name = "shots/147_day_dusk.png" },
    };
    // The sun's bearing at the anchor, as a CAMERA yaw: `camera.backDir` puts the lens behind the hero on the
    // yaw's own bearing, so pointing it down the sun's bearing is the yaw that faces INTO the light.
    const intoSun: f32 = 232.5 + 180.0;
    for (hours) |row| {
        game.pinHourForShot(g, row.h);
        shootAt(g, row.name, at, intoSun, 0.02, 7.0);
    }
    // …AND THE SHADOWS, which are the half of this that is not the sky: a steep overhead of the same ground at
    // three hours, where the only thing in the frame is which way and how far everything is throwing.
    for ([_]struct { h: f32, name: [:0]const u8 }{
        .{ .h = 7.0, .name = "shots/148_day_shadows_morning.png" },
        .{ .h = 12.0, .name = "shots/148b_day_shadows_noon.png" },
        .{ .h = 19.0, .name = "shots/148c_day_shadows_evening.png" },
    }) |row| {
        game.pinHourForShot(g, row.h);
        shootAt(g, row.name, at, 90, 0.62, 26.0);
    }
    // BACK TO THE ANCHOR, and the harness expects to find it there: everything below this is judged under it.
    game.pinHourForShot(g, game.daynight.SHOT_HOUR);
}

fn elevationShots(g: *Game) void {
    const before = g.map.height;
    var span: [4]usize = undefined;
    _ = g.map.sculpt(-34, -6, 26, .raise, 11.0, &span);
    _ = g.map.sculpt(-20, -24, 18, .raise, 6.0, &span);
    _ = g.map.sculpt(-48, 14, 14, .raise, 4.0, &span);
    _ = g.map.sculpt(6, -22, 15, .lower, 5.0, &span);
    var s: usize = 0;
    while (s < 3) : (s += 1) {
        _ = g.map.sculpt(-34, -6, 30, .smooth, 1.0, &span);
        _ = g.map.sculpt(6, -22, 18, .smooth, 1.0, &span);
    }
    g.env.uploadHeight(&g.map);
    g.env.materialize(&g.map);

    standHero(g, -6, 6, mathx.radians(215));
    plantHeroForShot(g);
    shootAt(g, "shots/100_hill_from_below.png", g.hero.shoulderPoint(), 215, 0.06, 9.0);

    standHero(g, -30, -8, mathx.radians(75));
    plantHeroForShot(g);
    shootAt(g, "shots/101_hill_from_above.png", g.hero.shoulderPoint(), 75, 0.30, 11.0);

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
    // PITCHED WELL DOWN: a camera behind a hero on a 34 deg slope looks INTO a rising wedge of ground, so
    // at a gameplay pitch the hillside fills the frame and the hero is behind it.
    shootClear(g, "shots/102_hill_climb.png", 215, 0.62, 8.0);
    g.menu.stats = true;
    shootClear(g, "shots/103_hill_stats.png", 215, 0.62, 8.0);
    g.menu.stats = false;

    standHero(g, -4, 22, mathx.radians(215));
    plantHeroForShot(g);
    shootAt(g, "shots/104_hill_profile.png", v3(-24, 6, -8), 215, 0.42, 92.0);

    g.editor.enter(g.hero.pos);
    g.editor.setLayer(.ground);
    g.editor.brush[@intFromEnum(editormod.Layer.ground)] = @intFromEnum(editormod.GroundBrush.raise);
    g.editor.radius = 14;
    // The focus rides the GROUND: left at y = 0 over an 11 m ridge it aims inside the hill, and the eye
    // clamp shoves the camera up off the slope.
    g.editor.focus = v3(-30, g.env.groundAt(-30, -8), -8);
    g.editor.pitch = -0.42;
    g.editor.yaw = 2.5;
    g.editor.dist = 62;
    g.editor.applyCamForShot();
    editorSnap(g, "shots/105_editor_sculpt.png");
    g.editor.on = false;

    g.map.height = before;
    g.env.uploadHeight(&g.map);
    g.env.materialize(&g.map);
}

/// One page of the character book, staged and photographed. The `update` is what plants the cursor on
/// the slot before the frame is drawn: in play it is EASED there, and `debugShow` only says where to.
fn bookShot(g: *Game, name: [:0]const u8, page: bookmod.Page, cursor: usize, pickSlot: ?usize, row: usize) void {
    g.menu.book.debugShow(page, cursor, pickSlot, row);
    const shelf = savemod.Shelf{}; // the book knows nothing about slots; it is the same card either way
    _ = g.menu.update(&g.retro, &g.day, SHOT_DT, game.bookView(g), &shelf);
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, game.bookView(g), .{ .hero = &g.hero, .scene = &g.scene }, &shelf);
    snap(name);
}

/// A GAIT IS JUDGED FROM THE SIDE — head-on a stride foreshortens to a creature bobbing on the spot. The
/// trot runs at four phases a quarter-cycle apart, and the diagonal pairs are what has to read (`lag` 0.50,
/// so fore-right lands with hind-left).
fn wolfShots(g: *Game) void {
    g.hero.arm = .bell;
    standHero(g, 6.0, 4.0, std.math.pi * 0.5);
    plantHeroForShot(g);
    // THE BELL IN HIS HAND, close and at the sun's own bearing — a 9 cm object at 4 m is the thin-geometry
    // rule's problem, so it is framed tight or it is not being looked at.
    const chest = v3(g.hero.pos.x, game.heroCenterY(g), g.hero.pos.z);
    shootPortrait(g, "shots/130_bell_carry.png", chest, 53, 0.06, 2.2);
    game.ringForShot(g, heromod.RING_AT);
    shootPortrait(g, "shots/131_bell_ring.png", chest, 53, 0.06, 2.4);

    const at = mathx.ground(9.0, 4.0);
    // FACING ACROSS THE LENS, not down it: pointed at the camera every angle the IK solves is in the plane
    // you cannot see. Gait shots are yaw 90, so it stands at 0.
    game.callWolfForShot(g, at, 0);
    // STANDING first — a rig that sags at zero speed sags at every other one.
    game.poseWolfForShot(g, 0, 0);
    shootAt(g, "shots/132_wolf_stand.png", at, 53, 0.10, 3.4);
    shootAt(g, "shots/133_wolf_stand_side.png", at, 90, 0.06, 3.2);
    const phases = [_]f32{ 0.0, 0.25, 0.5, 0.75 };
    const names = [_][:0]const u8{
        "shots/134a_wolf_trot_q0.png",
        "shots/134b_wolf_trot_q1.png",
        "shots/134c_wolf_trot_q2.png",
        "shots/134d_wolf_trot_q3.png",
    };
    for (phases, names) |ph, nm| {
        game.poseWolfForShot(g, wolfmod.TROT_SPEED, ph);
        shootAt(g, nm, at, 90, 0.05, 3.4);
    }
    // The GALLOP is a different creature — duty factor under 0.5, so there are frames with nothing on the
    // ground at all, and the spine bows once a stride. Shot at the phase the bow is deepest.
    game.poseWolfForShot(g, wolfmod.GALLOP_SPEED, 0.25);
    shootAt(g, "shots/135_wolf_gallop.png", at, 90, 0.05, 3.8);
    // Judge the gather on the PAWS: it sinks the body and FOLDS the legs, so the feet stay where the animal
    // was standing. Read the other way round it reached past its own span and stood 20 cm into the earth.
    game.poseWolfGatherForShot(g, 0.5);
    shootAt(g, "shots/135b_wolf_gather.png", at, 90, 0.05, 3.4);
    game.poseWolfForShot(g, 0, 0);
    shootPortrait(g, "shots/136_wolf_head.png", mathx.addV(at, v3(0, wolfmod.W * 1.0, 0)), 40, 0.02, 1.5);

    // THE SPIRIT TOAST — its face and its life under HIS bars. The fade is the game's, so it is wound to
    // full here rather than waited out: a shot of a panel halfway in says nothing about either end of it.
    g.bag.add(.spirit_scroll_wolf, 1);
    game.showSpiritToastForShot(g);
    shootClear(g, "shots/137_spirit_toast.png", 53, 0.14, 4.6);
    g.pack.clear();
    g.hero.arm = .sword;
}

/// No easing — the harness has no frame loop to ease across, and a hero left at the datum on a sculpted
/// map is photographed knee-deep in his own hill.
fn plantHeroForShot(g: *Game) void {
    g.hero.pos.y = g.env.groundAt(g.hero.pos.x, g.hero.pos.z);
    g.hero.pose();
}
