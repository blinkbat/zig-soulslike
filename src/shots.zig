const std = @import("std");
const rl = @import("raylib");

const game = @import("game.zig");
const combat = @import("play/combat.zig");
const gfx = @import("gfx/gfx.zig");
const editormod = @import("ui/editor.zig");
const heromod = @import("play/hero.zig");
const frogmod = @import("foes/frog.zig");
const archermod = @import("foes/archer.zig");
const ogremod = @import("foes/ogre.zig");
const shroommod = @import("foes/shroom.zig");
const knightmod = @import("foes/knight.zig");
const delvermod = @import("foes/delver.zig");
const necromod = @import("foes/necro.zig");
const soulsmod = @import("play/souls.zig");
const koboldmod = @import("foes/kobold.zig");
const broodmod = @import("foes/brood.zig");
const warriormod = @import("foes/warrior.zig");
const shademod = @import("foes/shade.zig");
const leechmod = @import("foes/leechfly.zig");
const rootedmod = @import("foes/rooted.zig");
const npcmod = @import("foes/npc.zig");
const countermod = @import("play/counter.zig");
const counterui = @import("ui/counterui.zig");
const wolfmod = @import("foes/wolf.zig");
const dialogmod = @import("world/dialog.zig");
const mathx = @import("core/mathx.zig");
const camera = @import("core/camera.zig");
const props = @import("props/props.zig");
const stats = @import("play/stats.zig");
const ptree = @import("play/passivetree.zig");
const restmod = @import("play/rest.zig");
const item = @import("play/item.zig");
const bookmod = @import("ui/book.zig");
const savemod = @import("save.zig"); // for the boot screen's shelf — staged, never read off the disk
const sfx = @import("core/audio.zig");
const worldfmt = @import("world/worldfmt.zig");
const env = @import("world/env.zig");

const Game = game.Game;
const v3 = mathx.v3;

const drawScene = game.drawScene;
const hud = game.hud;
const hudmod = @import("ui/hud.zig");
const heroBlade = game.heroBlade;
const HERO_CENTER_Y = game.HERO_CENTER_Y;
const arrowCover = game.arrowCover;

const BOOT_SHOT_T: f32 = 11.0;

/// **THE TREE THIS FILE CREATES, NAMED ONCE.** The SHOT NAMES below carry their own `shots/`: those are data, and a `DIR ++` on every one of several hundred is noise.
pub const DIR = "shots";
const DIR_PROPS = DIR ++ "/props";
const DIR_MAP = DIR ++ "/map";
const DIR_LAND = DIR ++ "/land";

comptime {
    // …SO MOVING `DIR` MAY NOT BE SILENT: the tree is made from it and 510 names are written against the
    // literal, so changed here alone the harness creates one directory and fills another.
    std.debug.assert(std.mem.eql(u8, DIR, "shots"));
}

pub const SHOT_DT: f32 = 1.0 / 60.0;
/// The DRAWING clock, one shot at a time: every camera here TELEPORTS and a still frame cannot show a fade, so the occluder fade is handed a step big enough to arrive within the one frame we capture.
pub const SETTLE_DT: f32 = 10.0;
const SHOT_DOWNRANGE = mathx.ground(0, -22);
fn stepWorld(g: *Game, dt: f32, speed: f32) void {
    const moved = speed * dt;
    g.hero.pos.z = mathx.clampF(g.hero.pos.z - moved, -game.PLAY_HALF, game.PLAY_HALF);
    g.hero.facing = std.math.pi;
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

fn snap(name: [:0]const u8) void {
    rl.gl.rlDrawRenderBatchActive();
    rl.takeScreenshot(name);
    rl.endDrawing();
}

fn shoot(g: *Game, name: [:0]const u8) void {
    // A filtered run still SIMULATES every stage — only the render and the write are skipped, so nothing a later
    // stage depends on goes unbuilt.
    if (!stageOn(name)) return;
    drawScene(g);
    hud(g, SHOT_DT);
    snap(name);
}

/// The fire's list and wheel are drawn in the loop's rest branch, which `--shot` never runs, so `shoot` alone photographs a man sitting in front of nothing.
fn bonfireShoot(g: *Game, name: [:0]const u8) void {
    drawScene(g);
    game.takeSlotShot(g);
    hud(g, SHOT_DT);
    game.drawBonfireForShot(g);
    game.drawSaveMarkForShot(hudmod.SAVE_SHOW - hudmod.SAVE_GROW * 0.78);
    snap(name);
}

fn advanceAttack(g: *Game, dt: f32, frames: i32) void {
    var k: i32 = 0;
    while (k < frames and g.hero.attacking) : (k += 1) {
        g.hero.updateAttack(dt, game.PLAY_HALF, null);
        g.rig.follow(g.hero.shoulderPoint());
    }
}

/// …AND THE SAME BY FRACTION OF THE MOVE, the only way to aim at the same BEAT across six strokes whose durations are all different (`hero.MOVES`).
fn advanceTo(g: *Game, dt: f32, u: f32) void {
    const dur = g.hero.atkDur(g.hero.atkHeavy);
    while (g.hero.attacking and g.hero.atkT / dur < u) {
        g.hero.updateAttack(dt, game.PLAY_HALF, null);
        g.rig.follow(g.hero.shoulderPoint());
    }
}

/// The middle of a move's LIVE WINDOW, so a shot aimed at "the blow" follows the table when it is retuned instead of quietly drifting off the frame it was picked for.
fn liveMid(b: heromod.Blade, heavy: bool) f32 {
    const t = heromod.moveOf(b, heavy).t;
    return 0.5 * (t.hitA + t.hitB);
}

fn stepFoe(f: anytype, frames: i32, hero: rl.Vector3) void {
    var k: i32 = 0;
    while (k < frames) : (k += 1) _ = f.update(SHOT_DT, hero, game.PLAY_HALF, .{});
}

fn stepBandAndShots(g: *Game, frames: i32, hero: rl.Vector3) void {
    var k: i32 = 0;
    while (k < frames) : (k += 1) {
        _ = g.band.update(SHOT_DT, hero, game.PLAY_HALF, .{}, g, game.spawnClump);
        game.stepArrowsForShot(g, SHOT_DT);
    }
}

fn must(ok: bool, what: []const u8) void {
    if (ok) return;
    std.debug.print("--shot: {s}\n", .{what});
    @panic("shot harness: a staged action was refused");
}

/// **STRAIGHT INTO THE SLOT, NEVER BY WALKING THE SWAP** — a hand is a PAIR (`hero.RIGHT`/`hero.LEFT`), so a thing in neither slot never comes round and the walk this used to do could not terminate.
fn armTo(g: *Game, want: heromod.Armament) void {
    if (g.hero.arm == want) return;
    must(g.hero.equip(heromod.RIGHT, 0, want), "the armament would not go in the right hand");
}

fn offTo(g: *Game, want: heromod.Armament) void {
    if (g.hero.off == want) return;
    must(g.hero.equip(heromod.LEFT, 0, want), "the armament would not go in the left hand");
}

pub const LIT_YAW: f32 = 53.0;
comptime {
    // The boot camera stands on the same sun at the same anchor hour. Two literals for one bearing, so the
    // one that is not retuned fails the build rather than lighting the boot screen off the old path.
    if (LIT_YAW != game.BOOT_YAW_MID) @compileError("shots: LIT_YAW and game.BOOT_YAW_MID are one bearing");
}
/// DERIVED (`camera.backDir` at pitch 0). Hand-rounded it was already 0.45° out, so moving `LIT_YAW` left every "lit" framing in the file pointing the old way.
pub const LIT_BACK = v3(-mathx.sinf(mathx.radians(LIT_YAW)), 0, -mathx.cosf(mathx.radians(LIT_YAW)));

fn along(from: rl.Vector3, dir: rl.Vector3, m: f32) rl.Vector3 {
    return v3(from.x + dir.x * m, 0, from.z + dir.z * m);
}

fn standHero(g: *Game, x: f32, z: f32, faceYaw: f32) void {
    g.hero.pos = mathx.ground(x, z);
    g.hero.facing = faceYaw;
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
}

/// **PHOTOGRAPHED WHERE THE MAP ACTUALLY PUT ONE** — found through `env.wardProps` rather than at copied
/// coordinates, so moving the gate in the editor moves the shot. TWO FRAMES a second apart, because "it undulates" is the one claim a single frame cannot make.
fn fogGateShots(g: *Game, dt: f32) void {
    if (g.env.nwards == 0) {
        std.debug.print("shots: no fog gate in {s} — skipping the gate stage\n", .{worldfmt.startMap()});
        return;
    }
    const pr = &g.env.props[g.env.wardProps[0]];
    const at = pr.pos;
    // DERIVED FROM THE GATE'S OWN SIZE, never hand-picked: the editor's `scale` runs from a half-door to several.
    const tall = props.info(.foggate).top * pr.scale;
    const back = mathx.headingDir(mathx.radians(LIT_YAW)); // off the SUN's bearing, or the sheet is in its own shadow
    const step = tall * 0.5;
    standSettled(g, at.x - back.x * step, at.z - back.z * step, mathx.headingXZ(back));
    // AIMED LOW ON PURPOSE. `follow` sets the eye at the AIM POINT's height, and an eye at mid-sheet looks over the top of a thing whose alpha is fading out up there.
    shootAt(g, "shots/156_foggate.png", v3(at.x, at.y + tall * 0.20, at.z), LIT_YAW, 0.06, tall * 0.84);
    shootAt(g, "shots/156b_foggate_head.png", v3(at.x, at.y + tall * 0.62, at.z), LIT_YAW, 0.16, tall * 0.90);
    var k: i32 = 0;
    while (k < 60) : (k += 1) stepWorld(g, dt, 0);
    standSettled(g, at.x - back.x * step, at.z - back.z * step, mathx.headingXZ(back));
    shootAt(g, "shots/156c_foggate_moved.png", v3(at.x, at.y + tall * 0.20, at.z), LIT_YAW, 0.06, tall * 0.84);
    shootAt(g, "shots/156d_foggate_side.png", v3(at.x, at.y + tall * 0.20, at.z), LIT_YAW + 62, 0.06, tall * 0.84);
    // Stamped directly rather than by walking him through it, because the seal wants a live boss.
    g.env.wardShut[0] = true;
    shootAt(g, "shots/156e_foggate_shut.png", v3(at.x, at.y + tall * 0.20, at.z), LIT_YAW, 0.06, tall * 0.84);
    g.env.wardShut[0] = false;
}

/// **STANDING HIM ON SCULPTED GROUND TAKES MORE THAN ONE FRAME**: `hero.respawnNow` starts a pose CROSS-FADE
/// against a world-space snapshot, `--shot` runs no loop to advance it, and one update leaves him blended toward that snapshot — drawn back at the map's spawn, out of frame.
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

/// **FRAMES DRAWN AND THROWN AWAY.** The HUD keeps clocks of its own — the status caption's fade is one — and
/// they only advance on a DRAWN frame, so a caption cannot be photographed by soaking the simulation alone:
/// the shot on the proc frame catches it at zero alpha, which is what it is supposed to look like there.
fn soakDrawn(g: *Game, frames: i32) void {
    var k: i32 = 0;
    while (k < frames) : (k += 1) {
        drawScene(g);
        hud(g, SHOT_DT);
        rl.gl.rlDrawRenderBatchActive();
        rl.endDrawing();
    }
}

fn shootClear(g: *Game, name: [:0]const u8, yaw: f32, pitch: f32, dist: f32) void {
    g.rig.yaw = mathx.radians(yaw);
    g.rig.pitch = pitch;
    g.rig.dist = dist;
    g.rig.followClear(g.hero.shoulderPoint(), game.camFloor(g), game.CamFloor.at);
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

fn stagedCast(g: *Game) void {
    g.hero.fp.reset();
    must(g.hero.requestCast(), "the cast would not start");
}

fn wandFrame(g: *Game) rl.Vector3 {
    return mathx.lerpV(g.hero.shoulderPoint(), g.hero.wandTipWorld(), 0.5);
}

fn castToCharged(g: *Game, dt: f32) void {
    var k: i32 = 0;
    while (k < 120) : (k += 1) {
        if (g.hero.chargeFill() >= 0.92) return;
        g.hero.updateCast(dt, null);
        must(!g.hero.thrown, "the charge never topped out before the throw");
    }
    must(false, "the cast never charged");
}

fn castToThrow(g: *Game, dt: f32) void {
    var k: i32 = 0;
    while (k < 120) : (k += 1) {
        g.hero.updateCast(dt, null);
        if (g.hero.thrown) return;
    }
    must(false, "the cast never threw the bolt");
}

pub fn runPropShots(g: *Game) void {
    std.fs.cwd().makePath(DIR_PROPS) catch {};
    g.drawDt = SETTLE_DT;
    g.menu.screen = .closed;
    g.retro.allOff();
    game.clearFoesForShot(g);
    for (props.INFO, 0..) |row, i| {
        g.env.stageOne(row.kind);
        // Off the STAGED instance, not the kind's table: a stacking kind stands taller than its own mesh.
        const staged = &g.env.props[0];
        const r = mathx.maxF(env.reachOf(staged, &row), 0.9);
        const top = env.runOf(staged, &row);
        standHero(g, -(r + 1.1), 0.35 * r + 0.9, mathx.radians(115));
        const aim = v3(0, mathx.clampF(top * 0.45, 0.4, 9.0), 0);
        const dist = mathx.clampF(mathx.maxF(r * 2.1, top * 1.7), 3.2, 60.0);
        var buf: [96]u8 = undefined;
        const name = std.fmt.bufPrintZ(&buf, DIR_PROPS ++ "/{d:0>2}_{s}.png", .{ i, @tagName(row.kind) }) catch unreachable;
        shootAt(g, name, aim, 35, 0.30, dist);
    }
}

pub fn runMapShots(g: *Game) void {
    std.fs.cwd().makePath(DIR_MAP) catch {};
    g.drawDt = SETTLE_DT;
    g.menu.screen = .closed;
    g.retro.allOff();
    game.pinHourForShot(g, game.daynight.SHOT_HOUR);

    var n: usize = 0;
    var shot = [_]bool{false} ** @typeInfo(worldfmt.FoeKind).@"enum".fields.len;
    inline for (game.FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            const T = @TypeOf(f.*);
            const kindOf: worldfmt.FoeKind = if (comptime gr.kind) |k| k else f.kind();
            if (shot[@intFromEnum(kindOf)]) continue;
            shot[@intFromEnum(kindOf)] = true;
            const top = f.topWorld().y - f.pos.y;
            const r = mathx.maxF(f.bodyR(), 0.6);
            // **THE HERO STANDS ON THE SUN'S BEARING** (AGENTS: photograph its front = the sensed hero SW,
            // the lens at ~53). Stood NE, every body that turns to face him gave the camera its back.
            standHero(g, f.pos.x - 4.5, f.pos.z - 3.4, mathx.radians(35));
            f.pose();
            const aim = v3(f.pos.x, f.pos.y + top * 0.55, f.pos.z);
            const dist = mathx.clampF(mathx.maxF(r * 7.0, top * 4.2), 4.0, 34.0);
            var buf: [96]u8 = undefined;
            const stand = std.fmt.bufPrintZ(&buf, DIR_MAP ++ "/{d:0>2}_{s}_stand.png", .{ n, @tagName(kindOf) }) catch unreachable;
            shootAt(g, stand, aim, 53, 0.16, dist);
            // **AND THE GRIP, CLOSE, FROM TWO QUARTERS** — how a body holds its kit is judged at arm's
            // length (`knightDoorShots`' lesson); the house portrait at 12 m answers nothing about a fist.
            // Hero-scaffold rigs only: on any other bone count, 17 is not the held slot.
            if (comptime @hasField(T, "xf")) {
                if (comptime @typeInfo(@TypeOf(f.xf)).array.len == heromod.N) {
                    const grip = rl.math.vector3Transform(mathx.zero3, f.xf[heromod.HELD]);
                    // A rig that never poses its held bone leaves undefined memory there (the cinder wake's
                    // rake is its own two hands) — refuse a grip that is not on the body.
                    if (mathx.distXZ(grip, f.pos) < 5.0 and grip.y > f.pos.y - 1.0 and grip.y < f.pos.y + 8.0) {
                        const gaim = v3(grip.x, grip.y + 0.12, grip.z);
                        // The body faces the stood hero (bearing ~53), so 53 is its FRONT and 323 its sword flank.
                        for ([_]struct { yaw: f32, tag: []const u8 }{ .{ .yaw = 53, .tag = "kit0" }, .{ .yaw = 323, .tag = "kit1" } }) |kv| {
                            var kb: [96]u8 = undefined;
                            const km = std.fmt.bufPrintZ(&kb, DIR_MAP ++ "/{d:0>2}_{s}_{s}.png", .{ n, @tagName(kindOf), kv.tag }) catch unreachable;
                            shootAt(g, km, gaim, kv.yaw, 0.12, 4.2);
                        }
                    }
                }
            }
            // …AND THE HEAD, for a creature whose head IS the read. The same `facePoint` frame the folk already
            // get, keyed off `@hasDecl` like everything else here. TWICE — at rest and again on the signature
            // move — because for a creature whose signature is worn on its head the two faces are the fight.
            const face = struct {
                fn portrait(gg: *Game, ff: anytype, idx: usize, kk: worldfmt.FoeKind, rr: f32, tag: []const u8) void {
                    var nb: [96]u8 = undefined;
                    const nm = std.fmt.bufPrintZ(&nb, DIR_MAP ++ "/{d:0>2}_{s}_{s}.png", .{ idx, @tagName(kk), tag }) catch unreachable;
                    shootAt(gg, nm, ff.facePoint(), 53, 0.06, mathx.clampF(rr * 2.6, 1.1, 3.4));
                }
            }.portrait;
            if (comptime @hasDecl(T, "facePoint")) face(g, f, n, kindOf, r, "face");
            // ONE NAME FOR THE MOVE, WHICHEVER MOVE IT IS. A pounce and a gather are the same slot, and the two branches spelled the filename out separately.
            var b2: [96]u8 = undefined;
            const move = std.fmt.bufPrintZ(&b2, DIR_MAP ++ "/{d:0>2}_{s}_move.png", .{ n, @tagName(kindOf) }) catch unreachable;
            if (comptime @hasDecl(T, "stagePounce")) {
                f.stagePounce(1.0);
                shootAt(g, move, aim, 90, 0.10, dist * 1.1);
            } else if (comptime @hasDecl(T, "stageGather")) {
                f.stageGather(1.0);
                shootAt(g, move, aim, 53, 0.16, dist);
            }
            if (comptime @hasDecl(T, "facePoint")) face(g, f, n, kindOf, r, "facemove");
            n += 1;
        }
    }
    // …AND THE FOLK, which the loop above cannot reach: an NPC is not in `FOE_GROUPS`. One per KIND, framed off
    // its own `topWorld` like a creature, so a new npc kind is inspectable the moment a map posts one.
    var npcShot = [_]bool{false} ** @typeInfo(worldfmt.NpcKind).@"enum".fields.len;
    for (g.folk.live()) |*f| {
        const ki = @intFromEnum(f.kind);
        if (npcShot[ki]) continue;
        npcShot[ki] = true;
        const top = f.topWorld().y - f.pos.y;
        standHero(g, f.pos.x + 4.5, f.pos.z + 3.4, mathx.radians(215));
        f.pose();
        const aim = v3(f.pos.x, f.pos.y + top * 0.55, f.pos.z);
        const dist = mathx.clampF(mathx.maxF(f.bodyR() * 7.0, top * 4.2), 4.0, 34.0);
        var buf: [96]u8 = undefined;
        const stand = std.fmt.bufPrintZ(&buf, DIR_MAP ++ "/{d:0>2}_{s}_stand.png", .{ n, @tagName(f.kind) }) catch unreachable;
        shootAt(g, stand, aim, 53, 0.16, dist);
        // …and the FACE, off its own `facePoint`, because a head is where a new npc kind lives or dies.
        var b2: [96]u8 = undefined;
        const face = std.fmt.bufPrintZ(&b2, DIR_MAP ++ "/{d:0>2}_{s}_face.png", .{ n, @tagName(f.kind) }) catch unreachable;
        shootAt(g, face, f.facePoint(), 53, 0.02, 1.35);
        n += 1;
    }
    std.debug.print("MAP SHOTS: {d} body(s) into " ++ DIR_MAP ++ "/\n", .{n});
}

/// **PHOTOGRAPH THE PLACE, NOT THE CREATURES IN IT.** Seven frames off any map `--map` can load: one steep
/// overhead for the layout (AGENTS.md's own `dist` near 55, scaled to the map's half), and six at eye level on
/// a ring, every one shot from **yaw 53** — the bearing that puts `gfx.SUN_DIR` over the camera's shoulder.
pub fn runLandShots(g: *Game) void {
    std.fs.cwd().makePath(DIR_LAND) catch {};
    g.drawDt = SETTLE_DT;
    g.menu.screen = .closed;
    g.retro.allOff();
    game.pinHourForShot(g, game.daynight.SHOT_HOUR);
    game.rehomeFoesForShot(g);

    const path = worldfmt.startMap();
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse std.mem.lastIndexOfScalar(u8, path, '\\');
    const from: usize = if (slash) |i| i + 1 else 0;
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse path.len;
    const stem = path[from..@max(dot, from)];

    const half = g.map.half;
    var buf: [256]u8 = undefined;

    standHero(g, 0, 6, std.math.pi);
    const wide = std.fmt.bufPrintZ(&buf, DIR_LAND ++ "/{s}_00_layout.png", .{stem}) catch unreachable;
    // AT THE GROUND, NOT AT y = 0. A sculpted map stands up to 47 m off the datum, and a target under the terrain is the framing failure AGENTS.md names outright.
    const wideZ = -half * 0.28;
    game.pinSkyForShot(g);
    shootAt(g, wide, v3(0, g.env.groundAt(0, wideZ), wideZ), LIT_YAW, 0.98, mathx.clampF(half * 0.85, 40, 150));

    // …AND SIX FROM INSIDE IT. AGENTS.md: `standHero` near your subject or there are no cast shadows.
    const ring = [_][2]f32{
        .{ 0, 10 }, .{ 0, -half * 0.22 }, .{ -half * 0.20, -half * 0.42 },
        .{ half * 0.20, -half * 0.36 }, .{ 0, -half * 0.62 }, .{ -half * 0.34, half * 0.10 },
    };
    for (ring, 0..) |at, i| {
        standHero(g, at[0], at[1], std.math.pi);
        g.hero.pos.y = g.env.groundAt(at[0], at[1]);
        g.hero.pose();
        game.pinSkyForShot(g);
        const name = std.fmt.bufPrintZ(&buf, DIR_LAND ++ "/{s}_{d:0>2}_eye.png", .{ stem, i + 1 }) catch unreachable;
        const aim = v3(at[0], g.env.groundAt(at[0], at[1]) + 1.4, at[1]);
        shootAt(g, name, aim, LIT_YAW, 0.16, 13.0);
    }
    std.debug.print("LAND SHOTS: {s} - 7 frames, {d} props / {d} solids / {d} lights into " ++ DIR_LAND ++ "/\n", .{ stem, g.env.propCount(), g.env.solidCount(), g.env.lightCount() });
}

/// DEV ONLY: `--shot-only <substr>` names one stage, because a full harness run is 3m38s and an eye pass is a
/// LOOP. Empty means every stage, which is what the harness is for.
pub var onlyStage: []const u8 = "";
fn stageOn(tag: []const u8) bool {
    if (onlyStage.len == 0) return true;
    return std.mem.indexOf(u8, tag, onlyStage) != null;
}

pub fn runShots(g: *Game) void {
    std.fs.cwd().makePath(DIR) catch {};
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
    // THE HOUR IS PINNED AND THE CLOCK IS STOPPED. Every frame below is framed off the sun's bearing (`LIT_YAW`) and the palette was measured against that one light.
    game.pinHourForShot(g, game.daynight.SHOT_HOUR);

    g.hero.pos = mathx.ground(0, 26);
    var i: i32 = 0;
    while (i < 40) : (i += 1) stepWorld(g, dt, heromod.WALK_SPEED);

    // **THE CULLER COUNTS, CAPTURED** (AGENTS.md says the harness takes them and nothing here was turning them
    // on). If `drawn` closes on `props` a culler has been defeated, and that is not something the eye can spot.
    g.menu.stats = true;
    shootAt(g, "shots/0_stats.png", v3(g.hero.pos.x, 1.15, g.hero.pos.z), LIT_YAW, 0.10, 6.0);
    g.menu.stats = false;

    const stages = [_]struct { name: [:0]const u8, yaw: f32, pitch: f32, dist: f32, adv: i32, speed: f32 }{
        .{ .name = "shots/1_walk_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .adv = 0, .speed = heromod.WALK_SPEED },
        .{ .name = "shots/2_walk_front.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .adv = 22, .speed = heromod.WALK_SPEED },
        .{ .name = "shots/3_run_side.png", .yaw = 90, .pitch = 0.06, .dist = 4.9, .adv = 24, .speed = heromod.RUN_SPEED },
        .{ .name = "shots/4_run_threequarter.png", .yaw = 45, .pitch = 0.16, .dist = 4.9, .adv = 12, .speed = heromod.RUN_SPEED },
        .{ .name = "shots/5_sprint_side.png", .yaw = 90, .pitch = 0.04, .dist = 5.4, .adv = 16, .speed = heromod.SPRINT_SPEED },
        .{ .name = "shots/6_sprint_back.png", .yaw = 180, .pitch = 0.22, .dist = 5.2, .adv = 14, .speed = heromod.SPRINT_SPEED },
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

    // **THE HIP JOINT, CLOSE, WITH THE LEG SWUNG** (owner: the tops of his legs cut off, he has no hips). The
    // house walk frames are shot at 4 m on the whole man, where a hand's width of geometry at the hip is four
    // pixels. Three phases of the stride, because the fault only shows once the thigh has left the pelvis.
    for ([_]struct { tag: []const u8, adv: i32, yaw: f32 }{
        .{ .tag = "a", .adv = 0, .yaw = 270 },
        .{ .tag = "b", .adv = 7, .yaw = 270 },
        .{ .tag = "c", .adv = 5, .yaw = 180 },
    }) |hp| {
        // Re-planted on open ground each time: at a 2.4 m boom the camera is inside whatever he has walked past.
        standHero(g, 2.0, -18.0, std.math.pi);
        var k: i32 = 0;
        while (k < hp.adv) : (k += 1) stepWorld(g, dt, heromod.RUN_SPEED);
        var name: [64]u8 = undefined;
        const p = std.fmt.bufPrintZ(&name, "shots/7{s}_hero_hip.png", .{hp.tag}) catch continue;
        shootAt(g, p, v3(g.hero.pos.x, g.hero.pos.y + 0.92, g.hero.pos.z), hp.yaw, 0.05, 2.4);
    }

    const lockedStages = [_]struct { name: [:0]const u8, yaw: f32, pitch: f32, dist: f32, phTgt: f32, dx: f32, dz: f32 }{
        .{ .name = "shots/38a_strafe_stepout.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.50, .dx = 1, .dz = 0 },
        .{ .name = "shots/38b_strafe_apart.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.57, .dx = 1, .dz = 0 },
        .{ .name = "shots/38c_strafe_crossing.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.81, .dx = 1, .dz = 0 },
        .{ .name = "shots/38d_strafe_crossed.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.02, .dx = 1, .dz = 0 },
        .{ .name = "shots/38e_strafe_uncross.png", .yaw = 0, .pitch = 0.16, .dist = 4.2, .phTgt = 0.31, .dx = 1, .dz = 0 },
        .{ .name = "shots/38f_strafe_crossed_3q.png", .yaw = 40, .pitch = 0.13, .dist = 4.2, .phTgt = 0.02, .dx = 1, .dz = 0 },
        .{ .name = "shots/38g_strafe_crossing_3q.png", .yaw = 40, .pitch = 0.13, .dist = 4.2, .phTgt = 0.81, .dx = 1, .dz = 0 },
        .{ .name = "shots/39a_backpedal_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .phTgt = 0.05, .dx = 0, .dz = 1 },
        .{ .name = "shots/39b_backpedal_side.png", .yaw = 90, .pitch = 0.10, .dist = 4.0, .phTgt = 0.55, .dx = 0, .dz = 1 },
    };
    for (lockedStages) |st| {
        g.rig.yaw = mathx.radians(st.yaw);
        g.rig.pitch = st.pitch;
        g.rig.dist = st.dist;
        var k: i32 = 0;
        while (k < 14) : (k += 1) stepLocked(g, dt, heromod.WALK_SPEED, v3(st.dx, 0, st.dz), std.math.pi);
        var seek: i32 = 0;
        while (seek < 90) : (seek += 1) {
            const d = @abs(g.hero.phase - st.phTgt);
            if (@min(d, 1.0 - d) < 0.022) break;
            stepLocked(g, dt, heromod.WALK_SPEED, v3(st.dx, 0, st.dz), std.math.pi);
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
        .{ .name = "shots/7_roll_tuck.png", .adv = 6 }, // ~u 0.14
        .{ .name = "shots/8_roll_over.png", .adv = 8 }, // ~u 0.33
        .{ .name = "shots/9_roll_recover.png", .adv = 19 }, // ~u 0.79
    };
    for (rollStages) |st| {
        var k: i32 = 0;
        while (k < st.adv) : (k += 1) {
            if (g.hero.rolling) g.hero.updateRoll(dt, game.PLAY_HALF) else stepWorld(g, dt, heromod.WALK_SPEED);
            g.rig.follow(g.hero.shoulderPoint());
        }
        shoot(g, st.name);
    }

    while (g.hero.rolling) {
        g.hero.updateRoll(dt, game.PLAY_HALF);
        g.rig.follow(g.hero.shoulderPoint());
    }

    standHero(g, 0, -2, std.math.pi);
    g.rig.yaw = mathx.radians(90);
    g.rig.pitch = 0.06;
    g.rig.dist = 6.4;
    const jumpGround = mathx.addV(
        g.hero.shoulderPoint(),
        v3(0, 0, -heromod.RUN_SPEED * heromod.JUMP_AIR * 0.5),
    );
    must(g.hero.startJump(v3(0, 0, -1), heromod.RUN_SPEED), "the jump would not start");
    // AIMED OFF THE ARC'S OWN NUMBERS, never literal frames: each stage is a FRACTION of the flight, and the apex is 0.5 because that is where v passes through zero (t = v0/g = JUMP_AIR/2).
    const jumpStages = [_]struct { name: [:0]const u8, at: f32 }{
        .{ .name = "shots/9a_jump_drive.png", .at = 0.15 },
        .{ .name = "shots/9b_jump_apex.png", .at = 0.50 },
        .{ .name = "shots/9c_jump_reach.png", .at = 0.80 },
    };
    var flown: f32 = 0;
    for (jumpStages) |st| {
        const want = st.at * heromod.JUMP_AIR;
        while (flown < want and g.hero.airborne()) : (flown += dt) game.stepAirForShot(g, dt);
        g.rig.follow(jumpGround);
        shoot(g, st.name);
    }
    while (g.hero.airborne()) game.stepAirForShot(g, dt);
    var landT: f32 = 0;
    while (landT < heromod.LAND_SINK_DEEPEST) : (landT += dt) {
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
    }
    g.rig.follow(jumpGround);
    shoot(g, "shots/9d_jump_land.png");

    // **THE THROW, BESIDE THE JUMP IT IS MEASURED AGAINST** (`hero.startLaunch`). Same three fractions and the
    // same framing: the question is whether it reads as being KNOCKED OVER rather than as a leap, which is a comparison.
    g.hero.pos = mathx.ground(0, 0);
    g.hero.facing = 0;
    g.hero.clearForShot();
    const launchAir = heromod.launchAirFor(combat.SLAM_LAUNCH);
    const launchGround = mathx.addV(g.hero.shoulderPoint(), v3(0, 0, heromod.LAUNCH_BACK * 0.5));
    // Thrown toward -Z while still facing +Z: he goes backwards and goes on facing what hit him.
    must(g.hero.startLaunch(v3(0, 0, -1), combat.SLAM_LAUNCH), "the launch would not start");
    const launchStages = [_]struct { name: [:0]const u8, at: f32 }{
        .{ .name = "shots/9e_launch_off_feet.png", .at = 0.18 },
        .{ .name = "shots/9f_launch_apex.png", .at = 0.50 },
        .{ .name = "shots/9g_launch_fall.png", .at = 0.82 },
    };
    var thrown: f32 = 0;
    for (launchStages) |st| {
        const want = st.at * launchAir;
        while (thrown < want and g.hero.airborne()) : (thrown += dt) game.stepAirForShot(g, dt);
        g.rig.follow(launchGround);
        shoot(g, st.name);
    }
    while (g.hero.airborne()) game.stepAirForShot(g, dt);
    g.rig.follow(launchGround);
    shoot(g, "shots/9h_launch_down.png");
    g.hero.clearForShot();

    g.hero.pos = mathx.ground(0, 4);
    g.rig.yaw = mathx.radians(30);
    g.rig.pitch = 0.13;
    g.rig.dist = 4.2;
    stagedAttack(g, .light);
    advanceAttack(g, dt, 10); // ~u 0.28: windup apex
    shoot(g, "shots/15a_atk_light_wind.png");
    advanceAttack(g, dt, 5); // ~u 0.42: mid-arc
    shoot(g, "shots/15_atk_light_strike.png");
    advanceAttack(g, dt, 4); // ~u 0.53: the whip PEAK
    shoot(g, "shots/15p_atk_light_peak.png");
    advanceAttack(g, dt, 3); // ~u 0.61: follow-through
    shoot(g, "shots/15b_atk_light_thru.png");
    g.hero.stam.reset();
    g.hero.requestAttack(.light);
    advanceAttack(g, dt, 12); // chain fires at ~u 0.80, then into the backhand WINDUP
    shoot(g, "shots/15r_atk_return_wind.png");
    advanceAttack(g, dt, 10); // ~u 0.42 into the return swipe
    shoot(g, "shots/15c_atk_light_return.png");
    advanceAttack(g, dt, 999);

    g.hero.arm = .shield;
    g.hero.off = .sword;
    g.rig.yaw = mathx.radians(-30);
    stagedAttack(g, .light);
    advanceAttack(g, dt, 10);
    shoot(g, "shots/15L_atk_left_wind.png");
    advanceAttack(g, dt, 7);
    shoot(g, "shots/15L_atk_left_peak.png");
    advanceAttack(g, dt, 999);
    g.hero.arm = .sword;
    g.hero.off = .shield;

    g.rig.yaw = mathx.radians(0);
    g.rig.pitch = 1.48;
    g.rig.dist = 6.5;
    stagedAttack(g, .light);
    advanceAttack(g, dt, 17); // ~u 0.47, deep in the active window
    shoot(g, "shots/15t_atk_light_top.png");
    advanceAttack(g, dt, 999);
    g.rig.pitch = 0.13;
    g.rig.yaw = mathx.radians(90);
    stagedAttack(g, .heavy);
    advanceAttack(g, dt, 20); // ~u 0.33: overhead windup apex
    shoot(g, "shots/16_atk_heavy_windup.png");
    advanceAttack(g, dt, 14); // ~u 0.57: buried impact
    shoot(g, "shots/17_atk_heavy_impact.png");
    advanceAttack(g, dt, 999);
    g.menu.hitboxes = true;
    stagedAttack(g, .heavy);
    advanceAttack(g, dt, 28); // ~u 0.47: inside the active window
    shoot(g, "shots/18_atk_hitbox.png");
    advanceAttack(g, dt, 999);
    g.menu.hitboxes = false;

    // **THE OTHER TWO CLASSES' STROKES** — aimed at fractions of each move's OWN clock rather than at frame
    // counts, because the four durations are all different (`hero.MOVES`), and the beats that have a name in the
    // table are taken from it (`liveMid`, `hitA`/`hitB`). Yaw 53 puts the sun over the lens's shoulder.
    const meleeWorn = g.hero.worn;
    g.rig.yaw = mathx.radians(53);
    g.rig.pitch = 0.13;
    g.rig.dist = 4.2;

    g.hero.arm = .dagger;
    must(g.hero.wear(.hand_dagger, .fang_dirk), "the dirk would not go in its own socket");
    stagedAttack(g, .light);
    advanceTo(g, dt, 0.16); // the cock — IN at the far ribs, not back
    shoot(g, "shots/15x_dagger_flick_cock.png");
    advanceTo(g, dt, liveMid(.dagger, false)); // accelerating through the live window
    shoot(g, "shots/15y_dagger_flick_through.png");
    advanceTo(g, dt, 0.58); // and the carry-past
    shoot(g, "shots/15z_dagger_flick_past.png");
    advanceAttack(g, dt, 999);

    stagedAttack(g, .heavy);
    advanceTo(g, dt, 0.30); // THE HELD COIL, which is the bait
    shoot(g, "shots/16x_dagger_thrust_coil.png");
    advanceTo(g, dt, liveMid(.dagger, true)); // the point out, trunk squared rather than turned
    shoot(g, "shots/16y_dagger_thrust_out.png");
    advanceAttack(g, dt, 999);

    g.hero.arm = .club;
    must(g.hero.wear(.hand_club, .greatclub), "the club would not go in its own socket");
    g.rig.dist = 5.6; // 1.44 m of bog-oak needs the room
    stagedAttack(g, .light);
    advanceTo(g, dt, 0.29); // the wind, held at the far end of itself
    shoot(g, "shots/15c1_club_sweep_wind.png");
    advanceTo(g, dt, liveMid(.club, false)); // through, hips already round
    shoot(g, "shots/15c2_club_sweep_through.png");
    advanceTo(g, dt, 0.71); // and a long way past
    shoot(g, "shots/15c3_club_sweep_past.png");
    advanceAttack(g, dt, 999);

    g.rig.pitch = 0.02;
    g.rig.dist = 7.0; // the head stands 3.3 m up at the hang (measured), well outside the sweep's framing
    stagedAttack(g, .heavy);
    advanceTo(g, dt, 0.38); // THE HANG — 0.17 s of a club dead still overhead, inside its own `.hold`
    shoot(g, "shots/16c1_club_smash_hang.png");
    advanceTo(g, dt, heromod.moveOf(.club, true).t.hitA); // the frame the capsule goes live, half way down
    shoot(g, "shots/16c2_club_smash_falling.png");
    advanceTo(g, dt, heromod.moveOf(.club, true).t.hitB); // into the ground at his feet
    shoot(g, "shots/16c3_club_smash_ground.png");
    advanceAttack(g, dt, 999);

    g.menu.hitboxes = true;
    stagedAttack(g, .heavy);
    advanceTo(g, dt, liveMid(.club, true));
    shoot(g, "shots/18c_club_smash_hitbox.png");
    advanceAttack(g, dt, 999);
    g.menu.hitboxes = false;

    g.hero.arm = .sword;
    g.hero.off = .shield;
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        const w: item.Wear = @enumFromInt(f.value);
        _ = g.hero.wear(w, meleeWorn.at(w));
    }
    g.rig.yaw = mathx.radians(0);
    g.rig.pitch = 0.13;
    g.rig.dist = 4.2;

    {
        var k: i32 = 0;
        while (k < 45) : (k += 1) stepWorld(g, dt, 0);
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
        _ = g.hero.takeHit(ogremod.SWIPE_HIT, mathx.headingDir(g.hero.facing));
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootPortrait(g, "shots/20d_guard_block.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
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
        // Started COLD, from no guard at all: L2 is the shield's own skill and never asks whether the boards were already up.
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
        g.hero.noteParry();
        k = 0;
        while (k < 4) : (k += 1) g.hero.updateParry(dt, null);
        shootPortrait(g, "shots/20m_parry_catch.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20n_parry_catch_3q.png", g.hero.shoulderPoint(), LIT_YAW + 42, 0.09, 3.0);
        while (g.hero.parrying) g.hero.updateParry(dt, null);
        // THREE FRAMES FROM STRAIGHT DOWN. A swipe is a LATERAL sweep, so the front view foreshortens it to nothing: the coil, the crossing (the frame that catches) and the follow-through.
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
        g.hero.facing = mathx.headingXZ(LIT_BACK);
        armTo(g, .bow);
        k = 0;
        while (k < 20) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20f_bow_carry.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20g_bow_carry_side.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.09, 3.0);
        g.hero.setAim(true);
        k = 0;
        while (k < 24) : (k += 1) {
            g.hero.setAim(true);
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20h_bow_aim_front.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20i_bow_aim_3q.png", g.hero.shoulderPoint(), LIT_YAW + 42, 0.09, 3.0);
        shootPortrait(g, "shots/20j_bow_aim_side.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.08, 3.2);
        shootPortrait(g, "shots/20k_bow_string.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.02, 1.5);
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
        // In the SAME framing as the plain shaft above so the two are comparable, then cropped onto the head: the flame wad is 10 cm of the frame at 6 m.
        game.clearShaftsForShot(g);
        game.shootShaftForShot(g, SHOT_DOWNRANGE, .fire);
        k = 0;
        while (k < 7) : (k += 1) game.stepShaftsForShot(g, dt);
        shootPortrait(g, "shots/20s_fire_shaft.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.06, 6.0);
        if (game.flyingPointForShot(g, .firearrow)) |at| shootPortrait(g, "shots/20t_fire_head.png", at, LIT_YAW + 20, 0.04, 1.3);
        game.clearShaftsForShot(g);
        shootClear(g, "shots/20o_bow_hud.png", LIT_YAW + 150, 0.18, 4.6);
        // …AND THE SAME CORNER AFTER DARK, the only frame the clock dial's MOON face is ever visible in. Back to the anchor straight after.
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
        must(g.hero.cycleArrow(), "the arrow would not cycle");
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootClear(g, "shots/20u_fire_ammo.png", LIT_YAW + 150, 0.18, 4.6);
        must(g.hero.cycleArrow(), "the arrow would not cycle back");
        g.rig.aimB = 0;
        g.hero.setAim(false);
        while (g.hero.shooting) g.hero.updateShot(dt, null);
        armTo(g, .sword);
        game.clearShaftsForShot(g);
        g.hero.stam.reset();
        g.hero.vit = heromod.freshVitals(g.hero.sheet);
        k = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
    }

    {
        var k: i32 = 0;
        while (k < 30) : (k += 1) stepWorld(g, dt, 0);
        g.hero.pos = mathx.ground(0, 4);
        g.hero.facing = mathx.headingXZ(LIT_BACK);
        offTo(g, .wand);
        k = 0;
        while (k < 20) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20v_wand_carry.png", g.hero.shoulderPoint(), LIT_YAW, 0.09, 3.0);
        shootPortrait(g, "shots/20w_wand_carry_side.png", g.hero.shoulderPoint(), LIT_YAW - 78, 0.09, 3.0);
        stagedCast(g);
        k = 0;
        while (k < 9) : (k += 1) g.hero.updateCast(dt, null);
        shootPortrait(g, "shots/20y_wand_raise.png", wandFrame(g), LIT_YAW + 30, 0.12, 3.2);
        castToCharged(g, dt);
        shootPortrait(g, "shots/20y2_wand_charged.png", wandFrame(g), LIT_YAW + 30, 0.05, 6.5);
        shootPortrait(g, "shots/20y3_wand_gather.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.25);
        castToThrow(g, dt);
        shootPortrait(g, "shots/20z_wand_throw.png", wandFrame(g), LIT_YAW + 30, 0.16, 3.4);
        game.clearShaftsForShot(g);
        game.throwBoltForShot(g, SHOT_DOWNRANGE);
        shootPortrait(g, "shots/20z3_wand_release.png", wandFrame(g), LIT_YAW + 30, 0.05, 6.5);
        shootPortrait(g, "shots/20z4_wand_release_head.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.6);
        game.clearShaftsForShot(g);
        shootPortrait(g, "shots/20x_wand_crop.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.25);
        shootPortrait(g, "shots/20za_wand_throw_front.png", wandFrame(g), LIT_YAW, 0.16, 3.4);
        const firstSide = g.hero.castAlt;
        while (g.hero.casting) g.hero.updateCast(dt, null);
        stagedCast(g);
        castToThrow(g, dt);
        must(g.hero.castAlt != firstSide, "the second cast did not sweep the other way");
        shootPortrait(g, "shots/20zb_wand_throw_alt.png", wandFrame(g), LIT_YAW + 30, 0.16, 3.4);
        shootPortrait(g, "shots/20zc_wand_throw_alt_front.png", wandFrame(g), LIT_YAW, 0.16, 3.4);
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
        k = 0;
        while (k < 12) : (k += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootClear(g, "shots/20zf_wand_hud.png", LIT_YAW + 150, 0.18, 4.6);
        g.hero.fp.cur = combat.BOLT_FP - 1;
        g.hero.fpRefused = combat.STAM_REFUSE_FLASH;
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootClear(g, "shots/20zg_wand_hud_dry.png", LIT_YAW + 150, 0.18, 4.6);

        g.hero.fp.cur = g.hero.fp.max;
        g.hero.fpRefused = 0;
        game.selectSpellForShot(g, .roots);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootClear(g, "shots/20zg2_roots_hud.png", LIT_YAW + 150, 0.18, 4.6);
        stagedCast(g);
        castToThrow(g, dt);
        const rootsAt = game.castRootsForShot(g);
        shootPortrait(g, "shots/20zg3_roots_erupt.png", rootsAt, LIT_YAW, 0.10, 5.5);
        k = 0;
        while (k < 26) : (k += 1) {
            if (g.hero.casting) g.hero.updateCast(dt, null) else g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20zg4_roots_stand.png", rootsAt, LIT_YAW, 0.09, 5.8);
        // Thin geometry needs a CROP (AGENTS.md): a tendril is ~4 cm through, so at 1:1 the blunt tip and the side stubs are two pixels each.
        shootPortrait(g, "shots/20zg5_roots_crop.png", v3(rootsAt.x, rootsAt.y + 0.70, rootsAt.z), LIT_YAW + 34, 0.06, 2.7);
        shootPortrait(g, "shots/20zg6_roots_low.png", v3(rootsAt.x, rootsAt.y + 0.35, rootsAt.z), LIT_YAW - 40, 0.02, 4.0);
        while (g.hero.casting) g.hero.updateCast(dt, null);

        game.selectSpellForShot(g, .rime);
        g.hero.fp.cur = g.hero.fp.max;
        const rimeAt = mathx.ground(-26.0, 30.0);
        standSettled(g, rimeAt.x, rimeAt.z, mathx.headingXZ(LIT_BACK));
        shootClear(g, "shots/20zj_rime_hud.png", LIT_YAW + 150, 0.18, 4.6);
        const coneMid = v3(
            g.hero.pos.x + LIT_BACK.x * combat.RIME_REACH * 0.45,
            g.hero.pos.y + 1.15,
            g.hero.pos.z + LIT_BACK.z * combat.RIME_REACH * 0.45,
        );
        stagedCast(g);
        castToThrow(g, dt);
        shootPortrait(g, "shots/20zk_rime_open.png", coneMid, LIT_YAW + 90, 0.10, 7.0);
        for ([_]struct { u: f32, name: [:0]const u8 }{
            .{ .u = 0.35, .name = "shots/20zl_rime_pour.png" },
            .{ .u = 0.75, .name = "shots/20zm_rime_reach.png" },
        }) |step| {
            while (g.hero.casting and g.hero.breathU() < step.u) g.hero.updateCast(dt, null);
            must(g.hero.breathLive(), "the pour ended before the beat it was aimed at");
            shootPortrait(g, step.name, coneMid, LIT_YAW + 90, 0.10, 7.0);
        }
        // THIN GEOMETRY NEEDS A CROP: a mote is a couple of centimetres, so whether the stream leaves the ROD'S TIP cannot be judged from seven metres out.
        shootPortrait(g, "shots/20zn_rime_nozzle.png", g.hero.breathMouth(), LIT_YAW + 90, 0.06, 1.5);
        shootPortrait(g, "shots/20zo_rime_front.png", coneMid, LIT_YAW, 0.16, 6.0);
        while (g.hero.casting) g.hero.updateCast(dt, null);
        var bk: i32 = 0;
        while (bk < 8) : (bk += 1) {
            g.hero.update(dt, 0, 0, null);
            g.hero.pose();
        }
        shootPortrait(g, "shots/20zp_rime_after.png", g.hero.shoulderPoint(), LIT_YAW + 90, 0.10, 3.4);
        g.muster.n = 1;
        const chilled = &g.muster.band[0];
        chilled.* = warriormod.Warrior.spawnAs(.shieldman, along(rimeAt, LIT_BACK, 3.2), mathx.headingXZ(mathx.scaleV(LIT_BACK, -1)), 1.0, 0.3);
        chilled.chill.touch();
        chilled.vit.sinceHurt = 0;
        shootFoe(g, chilled, "shots/20zq_rime_chilled.png", LIT_YAW, 0.10, 4.6);
        g.muster.n = 0;
        g.hero.fp.cur = g.hero.fp.max;

        game.selectSpellForShot(g, .levin);
        standSettled(g, rimeAt.x, rimeAt.z, mathx.headingXZ(LIT_BACK));
        shootClear(g, "shots/20zr_levin_hud.png", LIT_YAW + 150, 0.18, 4.6);
        g.muster.n = 1;
        const struck = &g.muster.band[0];
        struck.* = warriormod.Warrior.spawnAs(.shieldman, along(rimeAt, LIT_BACK, 5.0), mathx.headingXZ(mathx.scaleV(LIT_BACK, -1)), 1.0, 0.3);
        stagedCast(g);
        castToThrow(g, dt);
        game.releaseSpellForShot(g);
        shootFoe(g, struck, "shots/20zs_levin_strike.png", LIT_YAW + 90, 0.10, 6.4);
        // THIN GEOMETRY NEEDS A CROP: a spark is two centimetres and dead in a twentieth of a second.
        shootPortrait(g, "shots/20zt_levin_crop.png", struck.centerWorld(), LIT_YAW + 90, 0.06, 2.6);
        while (g.hero.casting) g.hero.updateCast(dt, null);

        // Motes off the BODY, solved to arrive at the stone. Hurt him first, or a full bar has nothing to give back into.
        game.selectSpellForShot(g, .siphon);
        g.hero.fp.cur = g.hero.fp.max;
        g.hero.vit.hp = g.hero.vit.hpMax * 0.45;
        stagedCast(g);
        castToThrow(g, dt);
        game.releaseSpellForShot(g);
        shootPortrait(g, "shots/20zu_siphon_draw.png", mathx.lerpV(g.hero.shoulderPoint(), struck.centerWorld(), 0.5), LIT_YAW + 90, 0.10, 5.2);
        shootClear(g, "shots/20zv_siphon_hud.png", LIT_YAW + 150, 0.18, 4.6);
        while (g.hero.casting) g.hero.updateCast(dt, null);
        g.muster.n = 0;
        g.hero.vit.hp = g.hero.vit.hpMax;
        g.hero.fp.reset();
        game.selectSpellForShot(g, .bolt);
        // Walking, at two points HALF A STRIDE apart. LAST in the block, because `stepWorld` forces travel down
        // −Z and takes the lit facing every shot above depends on. Started at z=6: that end of the runway sits in a cliff's shadow.
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
        g.hero.fp.reset();
        g.hero.fpRefused = 0;
        offTo(g, .sword);
        armTo(g, .wand);
        must(g.hero.wandOut() and !g.hero.wandLeft(), "the rod would not go in the right hand");
        standSettled(g, 0, 4, mathx.headingXZ(LIT_BACK));
        shootPortrait(g, "shots/20zr_wand_right_carry.png", g.hero.shoulderPoint(), LIT_YAW + 78, 0.09, 3.0);
        stagedCast(g);
        castToCharged(g, dt);
        shootPortrait(g, "shots/20zs_wand_right_gather.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.25);
        castToThrow(g, dt);
        shootPortrait(g, "shots/20zt_wand_right_throw.png", wandFrame(g), LIT_YAW - 30, 0.16, 3.4);
        game.clearShaftsForShot(g);
        game.throwBoltForShot(g, SHOT_DOWNRANGE);
        shootPortrait(g, "shots/20zu_wand_right_release.png", g.hero.wandTipWorld(), LIT_YAW + 40, 0.08, 1.6);
        game.clearShaftsForShot(g);
        while (g.hero.casting) g.hero.updateCast(dt, null);

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
        g.hero.noteParry();
        k = 0;
        while (k < 3) : (k += 1) g.hero.updateParry(dt, null);
        shootPortrait(g, "shots/20zw_parry_right.png", g.hero.shieldFaceWorld().at, LIT_YAW, 0.10, 2.4);
        while (g.hero.parrying) g.hero.updateParry(dt, null);

        armTo(g, .sword);
        offTo(g, .bell);
        must(g.hero.bellOut() and g.hero.bellLeft(), "the bell would not go in the left hand");
        standSettled(g, 0, 4, mathx.headingXZ(LIT_BACK));
        g.hero.fp.reset();
        must(g.hero.requestRing(), "the ring was refused in the left hand");
        while (g.hero.ringing and !g.hero.rang) g.hero.updateRing(dt, null);
        shootPortrait(g, "shots/20zx_bell_left.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 3.2);
        while (g.hero.ringing) g.hero.updateRing(dt, null);

        armTo(g, .sword);
        offTo(g, .torch);
        must(g.hero.torchOut() and g.hero.torchLeft(), "the torch would not go in the left hand");
        standSettled(g, 0, 4, mathx.headingXZ(LIT_BACK));
        shootPortrait(g, "shots/20zy_torch_left.png", g.hero.torchFlameWorld(), LIT_YAW + 150, 0.10, 2.6);
        // …AND AFTER DARK, which is the only frame that shows what the thing is FOR. Anchor hour straight back.
        game.pinHourForShot(g, 23.4);
        shootPortrait(g, "shots/20zz_torch_night.png", g.hero.shoulderPoint(), LIT_YAW + 150, 0.10, 4.4);
        game.pinHourForShot(g, game.daynight.SHOT_HOUR);

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
        g.hero.pos = mathx.ground(2.0, 0.9);
        g.hero.facing = mathx.headingXZ(mathx.subV(mathx.zero3, g.hero.pos));
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();

        const behind = mathx.ground(0, -60);
        const front = mathx.ground(0, 60);

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        stepFoe(f, 8, front);
        shootFoe(g, f, "shots/20_frog_idle.png", 90, 0.10, 2.7);
        shootFoe(g, f, "shots/21_frog_scale.png", 35, 0.16, 4.7);

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -2.2), game.PLAY_HALF, false);
        stepFoe(f, 6, behind);
        shootFoe(g, f, "shots/22_frog_coil.png", 90, 0.08, 3.0);
        stepFoe(f, 22, behind);
        shootFoe(g, f, "shots/23_frog_leap.png", 90, 0.05, 3.4);
        stepFoe(f, 22, behind);
        shootFoe(g, f, "shots/24_frog_land.png", 90, 0.09, 3.1);

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), std.math.pi, 1.0, 0.0);
        f.startHop(mathx.ground(0, -3.6), game.PLAY_HALF, true);
        stepFoe(f, 26, behind);
        shootFoe(g, f, "shots/25_frog_lunge_wind.png", 55, 0.09, 3.3);
        stepFoe(f, 60, behind); // through flight + heavy landing, ~0.3 s into recovery
        shootFoe(g, f, "shots/26_frog_recover.png", 70, 0.13, 3.2);

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.startChomp();
        stepFoe(f, 22, front);
        shootFoe(g, f, "shots/27_frog_gape.png", 162, 0.06, 2.2);
        stepFoe(f, 6, front);
        shootFoe(g, f, "shots/28_frog_snap.png", 162, 0.06, 2.2);

        g.menu.hitboxes = true;
        g.menu.stats = true;
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        g.hero.pos = mathx.ground(0, 0.85);
        g.hero.facing = std.math.pi;
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        stagedAttack(g, .light);
        var hk: i32 = 0;
        while (hk < 999 and g.hero.attacking) : (hk += 1) {
            g.hero.updateAttack(dt, game.PLAY_HALF, null);
            _ = f.update(dt, mathx.ground(0, 60), game.PLAY_HALF, heroBlade(g));
            if (hk == 15) {
                g.rig.yaw = mathx.radians(60);
                g.rig.pitch = 0.12;
                g.rig.dist = 3.6;
                g.rig.follow(f.centerWorld());
                shoot(g, "shots/29_frog_hit.png");
            }
        }
        g.menu.hitboxes = false;
        g.menu.stats = false;

        // THE WOUND, TWICE — the streaked blood a few frames after the blade lands, and the stains it leaves on the ground once the flight is over.
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        g.hero.pos = mathx.ground(0, 0.85);
        g.hero.facing = std.math.pi;
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        stagedAttack(g, .light);
        var wk: i32 = 0;
        var landed: i32 = -1;
        while (wk < 999 and g.hero.attacking) : (wk += 1) {
            g.hero.updateAttack(dt, game.PLAY_HALF, null);
            _ = f.update(dt, mathx.ground(0, 60), game.PLAY_HALF, heroBlade(g));
            if (f.hits > 0 and landed < 0) landed = wk;
            if (landed >= 0 and wk == landed + 5) shootFoe(g, f, "shots/29b_frog_wound.png", 60, 0.10, 2.6);
        }
        must(landed >= 0, "the wound shot's swing never landed");
        var ws: i32 = 0;
        while (ws < 12) : (ws += 1) _ = f.update(dt, mathx.ground(0, 60), game.PLAY_HALF, .{});
        shootFoe(g, f, "shots/29c_frog_wound_after.png", 60, 0.30, 2.4);

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
        const front = mathx.ground(0, 60);

        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.stagger(false);
        stepFoe(f, 13, front);
        shootFoe(g, f, "shots/31_frog_flinch.png", 70, 0.12, 3.2);
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.stagger(true);
        stepFoe(f, 24, front);
        shootFoe(g, f, "shots/32_frog_stagger.png", 55, 0.12, 3.4);
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        f.debugKill();
        stepFoe(f, 42, front);
        shootFoe(g, f, "shots/33_frog_death.png", 60, 0.10, 3.4);

        g.hero.pos = mathx.ground(0, 4);
        g.hero.facing = std.math.pi;
        // …UNDIRECTED (a zero `fromDir`): a blow with no direction cannot be caught on the shield however he is standing (`hero.guardCovers`).
        _ = g.hero.takeHit(.{ .poise = 999 }, mathx.zero3);
        var sk: i32 = 0;
        while (sk < 13) : (sk += 1) g.hero.updateStun(dt);
        g.rig.yaw = mathx.radians(60);
        g.rig.pitch = 0.12;
        g.rig.dist = 4.6;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/34_hero_flinch.png");
        while (g.hero.staggered()) g.hero.updateStun(dt);

        _ = g.hero.takeHit(.{ .stance = 999 }, mathx.zero3);
        sk = 0;
        while (sk < 26) : (sk += 1) g.hero.updateStun(dt);
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/35_hero_stagger.png");
        while (g.hero.staggered()) g.hero.updateStun(dt);

        _ = g.hero.takeHit(.{ .dmg = 999 }, mathx.zero3);
        // MID-FADE, the only frame that shows the chrome going rather than gone: stepped in SECONDS off the hero's own death clock so it stays on the same beat if `HUD_FADE_DUR` is retuned.
        sk = 0;
        while (@as(f32, @floatFromInt(sk)) * dt < game.HUD_FADE_DUR * 0.5) : (sk += 1) g.hero.updateDeath(dt);
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/36a_hero_death_hudfade.png");
        while (sk < 130) : (sk += 1) g.hero.updateDeath(dt);
        g.rig.pitch = 0.22;
        g.rig.dist = 5.2;
        g.rig.follow(g.hero.shoulderPoint());
        shoot(g, "shots/36_hero_death.png");
        while (g.hero.dead) g.hero.updateDeath(dt);

        g.hero.hurtFlash = 0;
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
        std.debug.assert(!g.hero.rolling);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shoot(g, "shots/37b_stam_locked.png");

        var st: usize = 0;
        while (g.hero.stam.frac() < 0.2 and st < 600) : (st += 1) g.hero.stam.tick(SHOT_DT, false, false);
        std.debug.assert(g.hero.stam.cur > 0 and !g.hero.stam.canSprint());
        g.hero.stamRefused = 0;
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shoot(g, "shots/37c_stam_winded.png");

        g.hero.vit.hp = g.hero.vit.hpMax;
        g.hero.stam.reset();
        g.hero.stamRefused = 0;
        f.* = frogmod.Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    }

    {
        g.warren.frogs[0] = frogmod.Frog.spawn(mathx.ground(0, 60), 0, 1.0, 0.0);
        const a = &g.line.archers[0];
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        g.hero.pos = mathx.ground(3.0, 2.5);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        var k: i32 = 0;
        while (k < 140 and a.drawAmt < 0.98) : (k += 1) _ = a.update(dt, mathx.ground(0, 12), game.PLAY_HALF, .{});
        shootFoe(g, a, "shots/40_archer_aim_side.png", 90, 0.06, 4.8);
        shootFoe(g, a, "shots/41_archer_aim_front.png", 6, 0.12, 4.4);
        shootFoe(g, a, "shots/42_archer_aim_3q.png", 48, 0.10, 4.8);
        g.arrows[0] = archermod.launchArrow(a.nockWorld(), mathx.ground(0, 15));
        var m: i32 = 0;
        while (m < 8) : (m += 1) archermod.stepArrow(&g.arrows[0], mathx.ground(0, 15), HERO_CENTER_Y, g.env.groundAt(g.arrows[0].pos.x, g.arrows[0].pos.z), false, arrowCover(g, &g.arrows[0], dt), dt);
        shootFoe(g, a, "shots/44_archer_loose.png", 90, 0.05, 5.2);
        g.arrows[0] = .{};
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var j: i32 = 0;
        while (j < 20) : (j += 1) _ = a.update(dt, mathx.ground(0, 60), game.PLAY_HALF, .{});
        shootFoe(g, a, "shots/43_archer_idle_side.png", 90, 0.08, 4.6);
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var w2: i32 = 0;
        while (w2 < 60) : (w2 += 1) _ = a.update(dt, mathx.ground(0, 3), game.PLAY_HALF, .{});
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
        const ac = mathx.ground(-26.0, 30.0);
        a.* = archermod.Archer.spawn(ac, 0, 1.0, 0.0);
        a.debugKill();
        stepFoe(a, 95, mathx.ground(0, 60)); // ~1.58 s: the collapse is over and the cloud is at full
        standHero(g, ac.x + 2.2, ac.z - 1.4, std.math.pi);
        shootFoe(g, a, "shots/45d_archer_dissolve.png", LIT_YAW, 0.42, 3.4);
        a.* = archermod.Archer.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        var lk: i32 = 0;
        while (lk < 24) : (lk += 1) _ = a.update(dt, mathx.ground(0, 60), game.PLAY_HALF, .{});
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
        game.rehomeFoesForShot(g);
    }

    {
        const o = &g.grief.ogres[0];
        const oc = mathx.ground(-26.0, 14.0);
        const far = v3(oc.x, 0, oc.z + 80.0);

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        stepFoe(o, 54, far);
        g.hero.pos = mathx.ground(oc.x - 22.0, oc.z);
        g.hero.update(dt, 0, 0, null);
        g.hero.pose();
        shootFoe(g, o, "shots/47_ogre_idle.png", 55, 0.14, 13.0);
        {
            _ = o.vit.hit(.{ .dmg = 90 });
            g.hero.facing = mathx.headingXZ(mathx.scaleV(LIT_BACK, -1));
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
        g.hero.facing = mathx.headingXZ(mathx.subV(oc, g.hero.pos));
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
        shootFoe(g, o, "shots/59_ogre_walk_3q.png", 320, 0.08, 12.5);
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
        stepFoe(o, 64, far);
        shootFoe(g, o, "shots/49_ogre_windup.png", 55, 0.00, 13.0);
        stepFoe(o, 21, far);
        shootFoe(g, o, "shots/50_ogre_slam.png", 60, 0.06, 13.0);
        stepFoe(o, 25, far); // f110: ~0.4 s into recovery
        shootFoe(g, o, "shots/51_ogre_recover.png", 48, 0.10, 12.5);

        {
            const flank = v3(oc.x + 3.6, 0, oc.z - 1.2); // ~108 deg off his facing, inside SWIPE_R
            o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
            o.debugSwipe();
            stepFoe(o, 24, flank);
            shootFoe(g, o, "shots/61_ogre_swipewind.png", 35, 0.12, 12.0);
            stepFoe(o, 11, flank);
            shootFoe(g, o, "shots/62_ogre_swipe.png", 35, 0.12, 12.0);
            shootFoe(g, o, "shots/63_ogre_swipe_top.png", 35, 0.60, 15.0);
        }

        {
            const ahead = v3(oc.x, 0, oc.z + 3.4);
            o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
            o.debugBackswipe();
            stepFoe(o, 20, ahead);
            shootFoe(g, o, "shots/63b_ogre_backwind.png", 35, 0.50, 14.0);
            stepFoe(o, 9, ahead);
            shootFoe(g, o, "shots/63c_ogre_backswipe.png", 35, 0.12, 12.0);
            shootFoe(g, o, "shots/63d_ogre_backswipe_top.png", 35, 0.60, 15.0);
        }

        {
            const mark = v3(oc.x, 0, oc.z + 6.5);
            o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
            o.debugDrive();
            stepFoe(o, 40, mark);
            shootFoe(g, o, "shots/64_ogre_drive_tell.png", 55, 0.10, 13.0);
            stepFoe(o, 18, mark);
            shootFoe(g, o, "shots/64b_ogre_drive_surge.png", 90, 0.08, 13.5);
            stepFoe(o, 15, mark);
            shootFoe(g, o, "shots/64c_ogre_drive_crash.png", 55, 0.08, 13.0);
        }

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.stagger(false);
        stepFoe(o, 13, far);
        shootFoe(g, o, "shots/52_ogre_flinch.png", 55, 0.04, 12.5);
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.stagger(true);
        stepFoe(o, 42, far);
        shootFoe(g, o, "shots/53_ogre_stagger.png", 50, 0.10, 13.0);
        // STAGGERED OUT OF A RAISED CLUB: interrupted at the top of a windup the posture channels have 163 degrees of shoulder to unwind, and at four degrees a second he reels with the club still overhead.
        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugSlam();
        stepFoe(o, 64, far);
        o.stagger(true);
        stepFoe(o, 10, far);
        shootFoe(g, o, "shots/53b_ogre_stagger_armed.png", 50, 0.10, 13.0);
        stepFoe(o, 32, far);
        shootFoe(g, o, "shots/53c_ogre_stagger_armed_late.png", 50, 0.10, 13.0);

        o.* = ogremod.Ogre.spawn(oc, 0, 1.0, 0.4);
        o.debugKill();
        stepFoe(o, 72, far);
        shootFoe(g, o, "shots/54_ogre_death.png", 55, 0.12, 13.5);

        o.* = ogremod.Ogre.spawn(mathx.ground(3.0, -50.0), 0, 1.0, 0.4);
    }

    {
        const kc = mathx.ground(-26.0, 30.0);
        const litB = LIT_BACK;
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
        const away = mathx.ground(kc.x - 40.0, kc.z + 40.0);
        const park = struct {
            fn it(k: *koboldmod.Kobold, role: koboldmod.Role, at: rl.Vector3) void {
                k.* = koboldmod.Kobold.spawnAs(role, at, 0, 1.0, 0.5);
            }
        }.it;
        park(priest, .priest, away);
        park(sling, .slinger, away);

        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x, kc.z - 9.0), 0, 1.0, 0.15);
        var chf: i32 = 0;
        while (zerk.state != .approach and chf < 600) : (chf += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(zerk, 26, near);
        shootFoe(g, zerk, "shots/64e_kobold_charge.png", LIT_YAW + 30, 0.06, 3.8);

        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        var zf: i32 = 0;
        while (zerk.state != .chop and zf < 600) : (zf += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        const chopAt = struct {
            fn frames(u: f32) i32 {
                return @intFromFloat(@round(u * koboldmod.CHOP_DUR / SHOT_DT));
            }
        }.frames;
        const raiseTop = chopAt(koboldmod.CHOP_HIT_A * 0.62);
        stepFoe(zerk, raiseTop, near);
        shootFoe(g, zerk, "shots/65_kobold_chop.png", LIT_YAW + 20, 0.06, 3.4);
        stepFoe(zerk, chopAt(koboldmod.CHOP_HIT_A + 0.10) - raiseTop, near);
        shootFoe(g, zerk, "shots/65b_kobold_chop_b.png", LIT_YAW + 20, 0.06, 3.4);
        var guard: i32 = 0;
        while (zerk.state != .heave and guard < 600) : (guard += 1) _ = zerk.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(zerk, 12, near);
        shootFoe(g, zerk, "shots/66_kobold_heave.png", LIT_YAW + 62, 0.04, 3.6);

        {
            const dside = v3(kc.x - litB.z * 5.0, 0, kc.z + litB.x * 5.0);
            const dyaw = mathx.headingXZ(mathx.subV(dside, kc));
            const beats = [_]struct { name: [:0]const u8, at: f32 }{
                .{ .name = "shots/66d_kobold_dash_coil.png", .at = 0.10 },
                .{ .name = "shots/66e_kobold_dash_fly.png", .at = 0.30 },
                .{ .name = "shots/66f_kobold_dash_land.png", .at = 0.56 },
            };
            for (beats) |b| {
                zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, dyaw, 1.0, 0.15);
                zerk.dashCd = 0;
                var df: i32 = 0;
                while (zerk.state != .dash and df < 600) : (df += 1) _ = zerk.update(SHOT_DT, dside, game.PLAY_HALF, .{});
                var bf: i32 = 0;
                while (zerk.t < b.at and bf < 600) : (bf += 1) _ = zerk.update(SHOT_DT, dside, game.PLAY_HALF, .{});
                shootPortrait(g, b.name, zerk.centerWorld(), LIT_YAW, 0.06, 5.0);
            }
        }

        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        zerk.stagger(true);
        stepFoe(zerk, 10, far);
        shootFoe(g, zerk, "shots/66b_kobold_stagger.png", LIT_YAW + 22, 0.06, 3.8);
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, kc, 0, 1.0, 0.15);
        zerk.debugKill();
        stepFoe(zerk, 34, far);
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
        const band8 = v3(kc.x + litB.x * 8.0, 0, kc.z + litB.z * 8.0);
        var g2: i32 = 0;
        while (sling.state != .whirl and g2 < 600) : (g2 += 1) _ = sling.update(SHOT_DT, band8, game.PLAY_HALF, .{});
        stepFoe(sling, 16, band8);
        shootFoe(g, sling, "shots/68_kobold_whirl.png", LIT_YAW + 18, 0.10, 3.8);
        shootPortrait(g, "shots/68b_kobold_sling_lit.png", sling.slingPoint(), LIT_YAW + 18, 0.04, 1.1);
        var g5: i32 = 0;
        while (game.flyingPointForShot(g, .clump) == null and g5 < 900) : (g5 += 1) stepBandAndShots(g, 1, band8);
        must(game.flyingPointForShot(g, .clump) != null, "the slinger never threw a clump");
        stepBandAndShots(g, 5, band8);
        if (game.flyingPointForShot(g, .clump)) |at| shootPortrait(g, "shots/68c_kobold_clump.png", at, LIT_YAW + 18, 0.05, 1.6);
        shootFoe(g, sling, "shots/68d_kobold_sling_sparks.png", LIT_YAW + 18, 0.10, 4.2);
        game.clearShaftsForShot(g);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, 0, 1.0, 0.85);
        sling.biteCd = 0;
        var g3: i32 = 0;
        while (sling.state != .bite and g3 < 600) : (g3 += 1) _ = sling.update(SHOT_DT, near, game.PLAY_HALF, .{});
        stepFoe(sling, 10, near);
        shootFoe(g, sling, "shots/69_kobold_bite.png", LIT_YAW + 14, 0.04, 2.6);
        const side = v3(kc.x - litB.z * 1.2, 0, kc.z + litB.x * 1.2);
        sling.* = koboldmod.Kobold.spawnAs(.slinger, kc, mathx.headingXZ(mathx.subV(side, kc)), 1.0, 0.85);
        sling.biteCd = 0;
        var g4: i32 = 0;
        while (sling.state != .bite and g4 < 600) : (g4 += 1) _ = sling.update(SHOT_DT, side, game.PLAY_HALF, .{});
        stepFoe(sling, 4, side);
        // …CENTRED (`shootPortrait`), not `shootFoe`: the rig's shoulder offset is 0.55 m against a 1.3 m subject.
        shootPortrait(g, "shots/69d_kobold_bite_coil.png", sling.centerWorld(), LIT_YAW, 0.06, 4.4);
        stepFoe(sling, 6, side);
        shootPortrait(g, "shots/69c_kobold_bite_side.png", sling.centerWorld(), LIT_YAW, 0.06, 4.4);
        shootPortrait(g, "shots/69e_kobold_bite_jaw.png", sling.lockPoint(), LIT_YAW, 0.02, 1.9);

        // …and the WALK, side on, at three phases a quarter-stride apart.
        zerk.* = koboldmod.Kobold.spawnAs(.berserker, mathx.ground(kc.x - litB.x * 9.0, kc.z - litB.z * 9.0), 0, 1.0, 0.15);
        const walkTo = v3(kc.x + litB.x * 40.0, 0, kc.z + litB.z * 40.0);
        const walkNames = [_][:0]const u8{ "shots/69b_kobold_walk.png", "shots/69c_kobold_walk.png", "shots/69d_kobold_walk.png" };
        for ([_]i32{ 26, 9, 9 }, 0..) |adv, wi| {
            stepFoe(zerk, adv, walkTo);
            shootFoe(g, zerk, walkNames[wi], LIT_YAW + 58, 0.06, 4.6);
        }
        game.rehomeFoesForShot(g);
    }

    {
        standHero(g, 0, 12, std.math.pi);
        shootAt(g, "shots/70_avenue_north.png", g.hero.shoulderPoint(), 180, 0.16, 9.0);
        shootAt(g, "shots/71_vista_north.png", mathx.ground(0, 6), 180, 0.30, 9.0);

        {
            const wasSoil = g.map.soil;
            const wasCov = g.map.soilCov;
            const wasEdge = g.map.soilEdge;
            g.map.soil = [_]u8{0} ** worldfmt.SOIL_CELLS;
            g.map.soilCov = [_]u8{worldfmt.COV_FULL} ** worldfmt.SOIL_CELLS;
            const EX: f32 = 0;
            const EZ: f32 = 96;
            var ei: usize = 0;
            while (ei < worldfmt.Edge.N) : (ei += 1) {
                const col: f32 = @floatFromInt(ei % 4);
                const row: f32 = @floatFromInt(ei / 4);
                _ = g.map.paintSoil(EX + (col - 1.5) * 30.0, EZ + (row - 0.5) * 30.0, 13.0, .stone, 1, @enumFromInt(ei));
            }
            g.env.uploadSoil(&g.map);
            game.pinHourForShot(g, 12.0);
            standHero(g, EX, EZ, std.math.pi);
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
        const memWas = g.hero.mem;
        g.hero.mem.put(1, .levin);
        restmod.debugMemory(&g.rest, 1, null);
        bonfireShoot(g, "shots/71k_bonfire_memory.png");
        restmod.debugMemory(&g.rest, 2, 4);
        bonfireShoot(g, "shots/71l_bonfire_memory_pick.png");
        g.hero.mem = memWas;
        restmod.debugShow(&g.rest, .list, 0, 0, 1.0);
        g.tree = .{};
        game.applyTree(g);
        g.hero.souls.total = treeSouls;
        g.hero.souls.shown = @floatFromInt(treeSouls);
        game.endRestForShot(g);

        standHero(g, 4.4, 6.2, mathx.radians(120));
        shootAt(g, "shots/71d_plume.png", v3(3.0, 2.3, 6.5), LIT_YAW, 0.14, 9.0);

        standHero(g, 2.0, -66.0, std.math.pi);
        shootAt(g, "shots/72_city_plaza.png", mathx.ground(0, -74), 180, 0.26, 9.0);
        // The chapel at (-30, -66) turned to yaw 270 maps its local +Z (the altar end) to world −X, so the nave runs along X from -33.6 (altar) to -26.4 (door).
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

        const trunk = g.env.nearestFading(v3(-118.0, 0, -14.0), 600.0);
        must(trunk != null, "no fadeable prop in the world to stand behind");
        const tp = trunk.?;
        // Him 2.4 m the far side of the trunk on a 7 m boom: any longer and the camera is up inside the canopy, photographing foliage.
        standHero(g, tp.x - LIT_BACK.x * 2.4, tp.z - LIT_BACK.z * 2.4, mathx.radians(LIT_YAW + 180.0));
        shootAt(g, "shots/93_occlude_fade.png", g.hero.shoulderPoint(), LIT_YAW, 0.06, 7.0);
        g.retro.values = gfx.RETRO_DEFAULTS;
        shootAt(g, "shots/93b_occlude_filtered.png", g.hero.shoulderPoint(), LIT_YAW, 0.06, 7.0);
        g.retro.allOff();
        standHero(g, tp.x + 7.0, tp.z + 7.0, mathx.radians(LIT_YAW + 180.0));
        shootAt(g, "shots/94_occlude_clear.png", g.hero.shoulderPoint(), LIT_YAW, 0.06, 7.0);

        // **THE WEATHER**, which no unforced run would ever catch. Three, because the thing to judge is the LADDER — dry, the gentle wash, the moderate sheet — and then the strike.
        standHero(g, 2.0, -18.0, std.math.pi);
        game.clearWeatherForShot(g);
        shootAt(g, "shots/150_weather_dry.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 7.5);
        game.forceWeatherForShot(g, .gentle, -1);
        stepWorld(g, dt, 0);
        shootAt(g, "shots/151_rain_gentle.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 7.5);
        game.forceWeatherForShot(g, .moderate, -1);
        stepWorld(g, dt, 0);
        shootAt(g, "shots/152_rain_moderate.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 7.5);
        game.forceWeatherForShot(g, .moderate, 0.02);
        shootAt(g, "shots/153_lightning.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 7.5);
        game.clearWeatherForShot(g);

        game.forceFogForShot(g, true);
        game.forceMistForShot(g, 16.0);
        stepWorld(g, dt, 0);
        shootAt(g, "shots/154_fog.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 7.5);
        shootAt(g, "shots/155_mist_bank.png", g.hero.shoulderPoint(), LIT_YAW, 0.16, 22.0);
        game.forceFogForShot(g, false);

        // **THE BIRDS** — a dry sky's own, pitched UP because that is the only place they are. Two, because the
        // brief was packs of DIFFERENT sizes from DIFFERENT angles and one frame cannot say that.
        // Aimed AT the skein, because the point of the frame is whether a speck 70 m up reads as a bird; and
        // then from the man, at the distance he will actually see one, which is the other half of the question.
        game.forceSkeinForShot(g, mathx.radians(24.0));
        stepWorld(g, dt, 0);
        shootAt(g, "shots/157_birds.png", v3(g.hero.pos.x, g.hero.pos.y + 26.0, g.hero.pos.z), LIT_YAW, -0.52, 26.0);
        game.forceSkeinForShot(g, mathx.radians(-58.0));
        stepWorld(g, dt, 0);
        shootAt(g, "shots/157a_birds_across.png", game.skeinLeadForShot(g), LIT_YAW, -0.30, 46.0);
        // **AND THE ONE THAT ACTUALLY ANSWERS IT: THE CAMERA WHERE IT RESTS.** Both frames above hold the lens
        // UP at the flock, which is exactly why nobody noticed that at the pitch the game is played at they
        // were all above the top of the screen. No aiming, no lift — the shot a player gets.
        game.forceSkeinForShot(g, mathx.radians(38.0));
        stepWorld(g, dt, 0);
        // Turned toward the flock, because a player would; the PITCH and the boom are the resting rig's own and
        // they are the thing under test. The camera yaw is the back-bearing, so it is the look bearing plus 180.
        const toFlock = mathx.headingXZ(mathx.dirXZ(g.hero.pos, game.skeinLeadForShot(g)));
        shootAt(g, "shots/157b_birds_resting.png", g.hero.shoulderPoint(), mathx.degrees(toFlock) + 180.0, camera.DEFAULT_PITCH, camera.DEFAULT_DIST);
    }

    fogGateShots(g, dt);

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

    var shelf = savemod.Shelf{};
    shelf.head[0] = .{ .level = 7, .souls = 1240, .playtime = 8100 };
    shelf.head[2] = .{ .level = 1, .souls = 0, .playtime = 95 };
    const bare = savemod.Shelf{};
    var packed_ = savemod.Shelf{};
    packed_.head[0] = .{ .level = 7, .souls = 1240, .playtime = 8100 };
    packed_.head[1] = .{ .level = 3, .souls = 210, .playtime = 2400 };
    packed_.head[2] = .{ .level = 1, .souls = 0, .playtime = 95 };

    g.menu.screen = .main;
    g.menu.cursor = 0;
    drawScene(g);
    hud(g, SHOT_DT);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &shelf);
    snap("shots/12_menu_main.png");

    game.bootCamForShot(g, BOOT_SHOT_T);
    g.menu.screen = .boot;
    g.menu.home = .boot;
    g.menu.cursor = 1;
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &bare);
    snap("shots/12a_menu_boot.png");

    drawScene(g);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &shelf);
    snap("shots/12b_menu_boot_save.png");

    g.menu.showSlotsForShot(.load, 1);
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &shelf);
    snap("shots/12c_menu_slots.png");

    g.menu.showSlotsForShot(.new, 1);
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &shelf);
    snap("shots/12d_menu_slots_new.png");

    g.menu.screen = .boot;
    g.menu.cursor = 0;
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &packed_);
    snap("shots/12ca_menu_boot_full.png");
    g.menu.showSlotsForShot(.load, 1);

    g.menu.showSlotsForShot(.load, 0);
    g.menu.armDeleteForShot();
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &shelf);
    snap("shots/12e_menu_slot_delete.png");

    g.menu.onEscape();
    g.menu.home = .main;
    g.rig.yaw = mathx.radians(300);
    g.rig.pitch = 0.14;
    g.rig.dist = 3.4;
    g.rig.follow(g.hero.shoulderPoint());

    g.retro.values[gfx.RF_GAMEBOY] = 1.0;
    g.menu.screen = .retro;
    g.menu.cursor = gfx.RF_GAMEBOY;
    drawScene(g);
    hud(g, SHOT_DT);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), null, &shelf);
    snap("shots/13_menu_retro.png");
    g.menu.screen = .closed;

    g.retro.values = gfx.RETRO_DEFAULTS;
    shoot(g, "shots/14_retro_default.png");
    g.retro.allOff();

    if (stageOn("brood")) broodShots(g);
    if (stageOn("warrior")) warriorShots(g);
    if (stageOn("shade")) shadeShots(g);
    if (stageOn("leech")) leechShots(g);
    if (stageOn("rooted")) rootedShots(g);
    if (stageOn("shroom")) shroomShots(g);
    if (stageOn("delver")) delverShots(g);
    if (stageOn("necro")) necroShots(g);
    if (stageOn("pickup")) pickupShots(g);
    if (stageOn("knight")) knightShots(g);
    if (stageOn("souls")) soulsShots(g);
    if (stageOn("campfire")) campfireShots(g);
    if (stageOn("chest")) chestShots(g);
    if (stageOn("folk")) folkShots(g);
    if (stageOn("counter")) counterShots(g);
    if (stageOn("sound")) soundFilterShots(g);
    if (stageOn("stats")) statsShots(g);
    if (stageOn("wolf")) wolfShots(g);
    if (stageOn("day")) dayShots(g);
    if (stageOn("editor")) editorShots(g);
    if (stageOn("editorgap")) editorGapShots(g);
}

/// **THE STATS BENCH**, on the sheet with the most shape to it: a consumable draws only the dials its own
/// payload has, which is the whole claim the panel makes.
fn statsShots(g: *Game) void {
    const was = g.menu.screen;
    g.menu.screen = .closed;
    g.editor.enter(mathx.ground(0, -66));
    g.editor.applyCamForShot();
    g.editor.statsForShot("Spells", 0);
    editorSnap(g, "shots/117a_stats_spells.png");
    g.editor.statsForShot("Bag", 1);
    editorSnap(g, "shots/117b_stats_consumables.png");
    g.editor.statsForShot("Foes", 2);
    editorSnap(g, "shots/117c_stats_foes.png");
    g.editor.statsForShot("Blows", 18);
    editorSnap(g, "shots/117e_stats_blows.png");
    g.editor.statsForShot("Hero", 0);
    editorSnap(g, "shots/117f_stats_hero.png");
    g.editor.statsForShot("Passives", 3);
    editorSnap(g, "shots/117g_stats_passives.png");
    g.editor.closeModalForShot();
    // …and the other half of the ask: the picture of the thing with its own dials beside it.
    g.editor.itemForShot(.tower_shield);
    editorSnap(g, "shots/117d_stats_item.png");
    g.editor.closeModalForShot();
    g.editor.on = false;
    g.menu.screen = was;
}

fn soundFilterShots(g: *Game) void {
    const was = g.menu.screen;
    const wasCursor = g.menu.cursor;
    sfx.applyFxPreset(.combat, &sfx.FX_VINYL);
    g.menu.screen = .closed;
    editorJukeShot(g, "shots/115a_sound_rack.png");

    sfx.resetFx(.combat);
    g.menu.screen = was;
    g.menu.cursor = wasCursor;
}

fn broodShots(g: *Game) void {
    const bc = mathx.ground(-30.0, 14.0);
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
    shootFoe(g, m, "shots/107b_brood_mother_3q.png", 20, 0.16, 8.0);
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
    const near = v3(bc.x, 0, bc.z - 8.0);
    var k: i32 = 0;
    while (k < 260) : (k += 1) _ = g.brood.update(SHOT_DT, near, game.PLAY_HALF, .{}, g, game.spawnVenom);
    shootFoe(g, m, "shots/110_brood_laying.png", 45, 0.12, 9.5);
    while (k < 560) : (k += 1) _ = g.brood.update(SHOT_DT, near, game.PLAY_HALF, .{}, g, game.spawnVenom);
    shootFoe(g, m, "shots/110b_brood_clutch.png", 45, 0.16, 10.5);
    const hatched = 240 + @as(i32, @intFromFloat((broodmod.SAC_HATCH + 1.0) / SHOT_DT));
    while (k < hatched) : (k += 1) _ = g.brood.update(SHOT_DT, near, game.PLAY_HALF, .{}, g, game.spawnVenom);
    if (g.brood.n > 1) {
        const b = &g.brood.band[g.brood.n - 1];
        shootFoe(g, b, "shots/111_broodlings.png", 45, 0.14, 8.0);
        shootFoe(g, b, "shots/111b_broodling.png", 40, 0.08, 3.4);
    }

    const dc = mathx.ground(bc.x + 6.0, bc.z - 8.0);
    m.* = broodmod.Spider.spawnAs(.mother, dc, std.math.pi, 1.0, 0.3);
    g.brood.n = 1;
    m.debugKill();
    stepFoe(m, 9, near);
    shootFoe(g, m, "shots/112a_brood_death_rear.png", 55, 0.14, 9.0);
    stepFoe(m, 17, near);
    shootFoe(g, m, "shots/112b_brood_death_flip.png", 55, 0.14, 9.0);
    stepFoe(m, 10, near);
    shootFoe(g, m, "shots/112c_brood_death_crash.png", 55, 0.12, 9.0);
    stepFoe(m, 26, near);
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

/// THE SKELETAL WARRIORS (`113…`). Shot from `LIT_YAW` with the sensed hero put out on the SUN's bearing, because a foe turns to face him (AGENTS.md, A SUBJECT MUST BE LIT).
fn warriorShots(g: *Game) void {
    game.clearFoesForShot(g);
    const wc = mathx.ground(-24.0, 34.0);
    const near = along(wc, LIT_BACK, 1.4);
    const far = along(wc, LIT_BACK, 90.0);
    g.muster.n = 2;
    const sm = &g.muster.band[0];
    const gs = &g.muster.band[1];
    // SPAWNED FACING THE LENS. A foe only turns to face a hero inside its aggro range, so the sensed hero 90 m out leaves it on its spawn yaw.
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
    const away = mathx.ground(wc.x - 60.0, wc.z + 60.0);

    spawnSm(sm, mathx.ground(wc.x - 1.3, wc.z), faceCam);
    spawnGs(gs, mathx.ground(wc.x + 1.4, wc.z), faceCam);
    for ([_]*warriormod.Warrior{ sm, gs }) |w| stepFoe(w, 30, far);
    standHero(g, wc.x + 3.0, wc.z - 3.2, mathx.radians(-140));
    shootAt(g, "shots/113_warriors_pair.png", v3(wc.x, wc.y + 1.15, wc.z), LIT_YAW, 0.08, 7.4);

    g.hero.pos = mathx.ground(wc.x, wc.z - 30.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();

    spawnGs(gs, away, faceCam);
    spawnSm(sm, wc, faceCam);
    stepFoe(sm, 40, near);
    shootFoe(g, sm, "shots/113a_shield_guard.png", LIT_YAW, 0.04, 4.0);
    shootFoe(g, sm, "shots/113b_shield_guard_side.png", LIT_YAW + 62, 0.04, 4.2);
    shootPortrait(g, "shots/113c_shield_boards.png", sm.centerWorld(), LIT_YAW + 16, 0.02, 2.1);

    const mc = warriormod.moveClock(.shieldman, 0);
    const maceBeats = [_]struct { name: [:0]const u8, at: f32 }{
        .{ .name = "shots/113d_mace_gather.png", .at = mc.wind * 0.22 },
        .{ .name = "shots/113e_mace_cock.png", .at = mc.wind * 0.92 },
        .{ .name = "shots/113f_mace_strike.png", .at = mc.wind + mc.swing * 0.47 },
        .{ .name = "shots/113g_mace_follow.png", .at = mc.wind + mc.swing * 0.88 },
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
    stepFoe(sm, 20, far);
    const kneelAt = v3(sm.pos.x, sm.pos.y + 0.55, sm.pos.z);
    shootPortrait(g, "shots/113h_shield_kneel.png", kneelAt, LIT_YAW + 12, 0.02, 4.0);
    shootPortrait(g, "shots/113i_shield_kneel_side.png", kneelAt, LIT_YAW + 66, 0.02, 4.0);
    // THE HURT SPHERE OVER THE POSE IT IS SUPPOSED TO COVER. A kneeling body is the case that caught the old flat
    // 0.95·H centre — it stayed standing while the man went down — so the wire goes on the KNEEL and not the idle.
    g.menu.hitboxes = true;
    shootPortrait(g, "shots/113h2_shield_kneel_hurt.png", kneelAt, LIT_YAW + 66, 0.02, 4.2);
    g.menu.hitboxes = false;
    var bf: i32 = 0;
    while (sm.state == .guardbreak and bf < 900) : (bf += 1) _ = sm.update(SHOT_DT, far, game.PLAY_HALF, .{});
    stepFoe(sm, 30, near);
    shootFoe(g, sm, "shots/113j_shield_broken.png", LIT_YAW, 0.06, 4.2);

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

    const sc = warriormod.moveClock(.greatsword, 0);
    beat(g, gs, wc, faceCam, 0, sc.wind * 0.88, "shots/113l_slam_cock.png", near, LIT_YAW + 20, 6.0);
    beat(g, gs, wc, faceCam, 0, sc.wind + sc.swing * 0.57, "shots/113m_slam_through.png", near, LIT_YAW + 20, 6.0);
    beat(g, gs, wc, faceCam, 0, sc.wind + sc.swing * 0.97, "shots/113n_slam_end.png", near, LIT_YAW + 20, 6.0);
    beat(g, gs, wc, faceCam, 0, sc.wind + sc.swing + sc.recover * 0.32, "shots/113o_slam_spent.png", near, LIT_YAW + 34, 5.6);

    const lc = warriormod.moveClock(.greatsword, 1);
    const stroke2 = lc.wind + lc.swing + lc.chain;
    beat(g, gs, wc, faceCam, 1, lc.wind * 0.88, "shots/113p_lunge_coil.png", near, LIT_YAW + 26, 5.6);
    beat(g, gs, wc, faceCam, 1, lc.wind + lc.swing * 0.38, "shots/113q_lunge_leap.png", near, LIT_YAW + 26, 5.6);
    beat(g, gs, wc, faceCam, 1, lc.wind + lc.swing * 0.92, "shots/113r_lunge_thrust.png", near, LIT_YAW + 26, 5.6);
    beat(g, gs, wc, faceCam, 1, stroke2 + lc.swing * 0.5, "shots/113s_lunge_return.png", near, LIT_YAW + 26, 5.6);

    spawnGs(gs, away, faceCam);
    spawnSm(sm, wc, faceCam);
    sm.stagger(true);
    stepFoe(sm, 14, far);
    shootFoe(g, sm, "shots/113t_shield_stagger.png", LIT_YAW + 22, 0.06, 4.2);
    spawnSm(sm, away, faceCam);
    spawnGs(gs, wc, faceCam);
    gs.debugKill();
    stepFoe(gs, 34, far);
    shootFoe(g, gs, "shots/113u_greatsword_death.png", LIT_YAW + 28, 0.14, 5.0);

    // A GAIT IS A PROFILE READ, so he travels ACROSS the sun's bearing rather than along it. AND THE SENSED HERO
    // HAS TO BE INSIDE HIS AGGRO RANGE or he does not move at all — 49 m out is `Choice.hold`.
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

    spawn(t, sc, faceCam, 0.21);
    stepFoe(t, 30, far);
    standHero(g, sc.x + 5.0, sc.z - 5.0, mathx.radians(-140));
    shootAt(g, "shots/118_rooted_hidden.png", v3(sc.x, sc.y + 3.2, sc.z), LIT_YAW, 0.10, 15.0);

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
    t.stagger(true);
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
    const sc = mathx.ground(-24.0, 34.0);
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

    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    spawn(&g.cluster.shrooms[1], away, faceCam, 0.5);

    const mark = along(sc, LIT_BACK, 3.4);
    spawn(m, sc, faceCam, 0.23);
    m.debugFling(mark);
    stepFoe(m, 32, mark);
    shootAt(g, "shots/119b_shroom_gather.png", v3(sc.x, sc.y + 0.5, sc.z), LIT_YAW, 0.06, 4.2);

    stepFoe(m, 22, mark);
    shootAt(g, "shots/119c_shroom_fling.png", v3(m.pos.x, m.pos.y + 1.2, m.pos.z), LIT_YAW, 0.06, 4.6);

    spawn(m, sc, faceCam, 0.23);
    m.debugFling(mark);
    var k: i32 = 0;
    while (k < 132) : (k += 1) _ = g.cluster.update(SHOT_DT, mark, game.PLAY_HALF, .{});
    shootAt(g, "shots/119d_shroom_cloud.png", v3(mark.x, mark.y + 0.9, mark.z), LIT_YAW, 0.10, 7.0);

    spawn(m, sc, faceCam, 0.23);
    m.debugTrip(mark);
    stepFoe(m, 38 + 15 + 30, mark);
    shootAt(g, "shots/119e_shroom_trip.png", v3(sc.x, sc.y + 0.3, sc.z), LIT_YAW + 40, 0.45, 4.2);

    poisonShots(g, mark);

    game.clearFoesForShot(g);
}

/// THE DELVER. Most of what it does is BELOW the frame, so every one of these is shot down onto the ground: a mound photographed at eye height is a bump you cannot see.
fn delverShots(g: *Game) void {
    game.clearFoesForShot(g);
    // ON THE GROUND THAT IS ACTUALLY THERE. `mathx.ground` is y = 0 and this patch is sculpted, so a body staged with it stands BELOW the terrain.
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
    const stand = standSettled;

    spawn(d, sc, faceCam);
    stand(g, sc.x, sc.z - 40.0, 0);
    stepFoe(d, 30, far);
    shootAt(g, "shots/122_delver.png", v3(sc.x, sc.y + 0.7, sc.z), LIT_YAW, 0.16, 4.6);

    spawn(d, sc, faceCam);
    d.debugDive();
    run(d, DIVE_TELL_AT, far);
    shootAt(g, "shots/122b_delver_dive.png", v3(sc.x, sc.y + 0.9, sc.z), LIT_YAW, 0.12, 4.8);

    const mark = along(sc, LIT_BACK, 6.0);
    spawn(d, sc, faceCam);
    d.debugDive();
    run(d, 2.4, mark);
    shootAt(g, "shots/122c_delver_mound.png", v3(d.pos.x, d.pos.y + 0.3, d.pos.z), LIT_YAW, 0.42, 5.0);

    spawn(d, sc, faceCam);
    stand(g, sc.x, sc.z, mathx.radians(LIT_YAW + 180));
    d.state = .surge;
    d.t = 0;
    d.depth = delvermod.UNDER_DEPTH;
    run(d, SURGE_TELL_AT, g.hero.pos);
    shootAt(g, "shots/122d_delver_surge.png", v3(sc.x, sc.y + 0.7, sc.z), LIT_YAW, 0.20, 7.2);

    run(d, (delvermod.SURGE_DUR - SURGE_TELL_AT) + delvermod.BURST_RISE * 0.9, g.hero.pos);
    shootAt(g, "shots/122e_delver_burst.png", v3(sc.x, sc.y + 0.9, sc.z), LIT_YAW, 0.22, 5.4);

    spawn(d, sc, faceCam);
    stand(g, mark.x, mark.z, mathx.radians(LIT_YAW + 180));
    d.debugClaw();
    run(d, CLAW_TELL_AT, g.hero.pos);
    shootAt(g, "shots/122f_delver_claw.png", mathx.lerpV(v3(sc.x, sc.y + 0.9, sc.z), g.hero.pos, 0.5), LIT_YAW + 30, 0.40, 6.4);

    spawn(d, sc, faceCam);
    stand(g, mark.x, mark.z, mathx.radians(LIT_YAW + 180));
    d.debugRake();
    run(d, RAKE_TELL_AT, g.hero.pos);
    shootAt(g, "shots/122g_delver_rake.png", mathx.lerpV(v3(sc.x, sc.y + 0.9, sc.z), g.hero.pos, 0.5), LIT_YAW + 30, 0.40, 6.4);

    spawn(d, sc, faceCam);
    d.debugPlough();
    run(d, PLOUGH_TELL_AT, far);
    shootAt(g, "shots/122h_delver_plough_tell.png", v3(d.pos.x, d.pos.y + 0.4, d.pos.z), LIT_YAW + 70, 0.46, 8.5);

    spawn(d, sc, faceCam);
    const onLine = along(sc, LIT_BACK, 9.0);
    stand(g, onLine.x, onLine.z, mathx.headingXZ(mathx.dirXZ(onLine, sc)));
    d.facing = mathx.headingXZ(mathx.dirXZ(d.pos, g.hero.pos));
    d.debugPlough();
    run(d, delvermod.PLOUGH_WIND + 0.34, g.hero.pos);
    const mid = mathx.lerpV(d.pos, g.hero.pos, 0.45);
    shootAt(g, "shots/122i_delver_plough.png", v3(mid.x, mid.y + 1.0, mid.z), LIT_YAW + 70, 0.30, 11.0);

    game.clearFoesForShot(g);
}

const DIVE_TELL_AT: f32 = delvermod.DIVE_WIND * 0.84;
const SURGE_TELL_AT: f32 = delvermod.SURGE_DUR * 0.91;
const CLAW_TELL_AT: f32 = delvermod.CLAW_WIND + 0.08;
const RAKE_TELL_AT: f32 = delvermod.RAKE_WIND + 0.06;
const PLOUGH_TELL_AT: f32 = delvermod.PLOUGH_WIND * 0.88;

const RAISE_TELL_AT: f32 = necromod.RAISE_WIND * 0.93;
const FROST_TELL_AT: f32 = necromod.FROST_WIND * 0.90;
const FUSE_AT: f32 = necromod.FROST_FUSE * 0.58;

pub const NIGHT_HOUR: f32 = 1.5;

fn necroShots(g: *Game) void {
    game.clearFoesForShot(g);
    // FRAMING IS PART OF THE TEST, and a spot is only open if the point `target + LIT_BACK * dist` is open
    // too: the first pass staged this at (-46, 4) and put the camera inside a ruin wall.
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
    const stand = standSettled;

    // **THE STANDING PORTRAIT.** Framed on the CHEST rather than the middle, because on a rig 2.4 m tall
    // the middle puts the helm out of the top of the shot.
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 6.0, 0);
    stepFoe(k, 30, far);
    shootAt(g, "shots/123_necro.png", v3(sc.x, sc.y + 1.5, sc.z), LIT_YAW, 0.06, 7.4);

    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 3.0, 0);
    run(k, 1.6, v3(sc.x, sc.y, sc.z - 3.0));
    shootAt(g, "shots/123b_necro_hem.png", v3(k.pos.x, k.pos.y + 0.55, k.pos.z), LIT_YAW + 62, 0.10, 4.2);

    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 7.0, 0);
    g.muster.n = 1;
    const body = &g.muster.band[0];
    body.* = warriormod.Warrior.spawnAs(.greatsword, along(sc, LIT_BACK, -2.6), faceCam, 1.0, 0.3);
    body.pos.y = game.envGroundAt(&g.env, body.pos.x, body.pos.z);
    body.debugKill();
    // HELD BEFORE IT IS STEPPED, or the picture is a corpse part-way to gold: `foe.dissipate` starts fading
    // at `DEATH_DUR`, so stamping the hold afterwards froze it 14% dissolved and slightly shrunk.
    body.heldOpen = true;
    stepFoe(body, @as(i32, @intFromFloat(archermod.DEATH_DUR / SHOT_DT)) + 8, far);
    k.vigil.at = body.pos;
    k.debugRaise(body.pos);
    run(k, RAISE_TELL_AT, g.hero.pos);
    shootAt(g, "shots/123c_necro_raise_tell.png", v3(k.pos.x, k.pos.y + 1.3, k.pos.z), LIT_YAW, 0.10, 6.6);

    run(k, (necromod.RAISE_WIND - RAISE_TELL_AT) + 0.10, g.hero.pos);
    const between = mathx.lerpV(k.pos, body.pos, 0.5);
    shootAt(g, "shots/123d_necro_raise.png", v3(between.x, between.y + 1.0, between.z), LIT_YAW, 0.16, 7.0);
    g.muster.n = 0;

    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 9.0, 0);
    k.debugFrost();
    run(k, FROST_TELL_AT, g.hero.pos);
    shootAt(g, "shots/123e_necro_frost_tell.png", v3(k.pos.x, k.pos.y + 1.4, k.pos.z), LIT_YAW, 0.10, 6.4);

    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 9.0, 0);
    k.debugLay(g.hero.pos);
    run(k, FUSE_AT, g.hero.pos);
    // Back and UP far enough to hold the WHOLE ring: at 5.6 m the rim ran off three sides of the frame.
    shootAt(g, "shots/123f_necro_sigil.png", v3(g.hero.pos.x, g.hero.pos.y + 0.35, g.hero.pos.z), LIT_YAW, 0.60, 10.5);

    run(k, (necromod.FROST_FUSE - FUSE_AT) + 0.06, g.hero.pos);
    shootAt(g, "shots/123g_necro_burst.png", v3(g.hero.pos.x, g.hero.pos.y + 0.5, g.hero.pos.z), LIT_YAW, 0.50, 10.0);

    game.pinHourForShot(g, NIGHT_HOUR);
    spawn(k, sc, faceCam);
    stand(g, sc.x, sc.z - 9.0, 0);
    k.debugLay(g.hero.pos);
    run(k, FUSE_AT, g.hero.pos);
    shootAt(g, "shots/123h_necro_sigil_night.png", v3(g.hero.pos.x, g.hero.pos.y + 0.35, g.hero.pos.z), LIT_YAW, 0.60, 10.5);
    run(k, (necromod.FROST_FUSE - FUSE_AT) + 0.06, g.hero.pos);
    shootAt(g, "shots/123i_necro_burst_night.png", v3(g.hero.pos.x, g.hero.pos.y + 0.5, g.hero.pos.z), LIT_YAW, 0.50, 10.0);
    game.pinHourForShot(g, game.daynight.SHOT_HOUR);

    game.clearFoesForShot(g);
}

fn pickupShots(g: *Game) void {
    const saved = g.map.nops;
    if (saved + 1 > worldfmt.MAX_OPS) return;
    const cx: f32 = -28.0;
    const cz: f32 = 30.0;
    var op = worldfmt.defaults(.at);
    op.kind = .pickup;
    op.x = cx;
    op.z = cz;
    op.scale = 1;
    op.loot[0] = .mushroom_jerky;
    op.loot[1] = .nameless_soul;
    op.loot[2] = .nameless_soul;
    op.nloot = 3;
    g.map.ops[g.map.nops] = op;
    g.map.nops += 1;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);

    const gy = mathx.ground(cx, cz).y;
    standSettled(g, cx, cz - 1.6, 0);
    game.stepPickupsForShot(g);
    shootAt(g, "shots/124_pickup.png", v3(cx, gy + 0.45, cz), LIT_YAW, 0.10, 4.2);

    game.awardForShot(g, .grave_warbow, .first);
    game.awardForShot(g, .grave_warbow, .again);
    game.awardForShot(g, .grave_warbow, .again);
    game.awardForShot(g, .mushroom_jerky, .again);
    drawScene(g);
    hud(g, SHOT_DT);
    game.drawAwardCardForShot(g);
    snap("shots/124b_pickup_card.png");

    game.dismissAwardForShot(g);
    game.tickAwardForShot(g, 0.5);
    shoot(g, "shots/124b2_pickup_card_toast_after.png");

    game.awardForShot(g, .grave_warbow, .clear);
    game.awardForShot(g, .mushroom_jerky, .again);
    game.awardForShot(g, .nameless_soul, .again);
    game.awardForShot(g, .nameless_soul, .again);
    game.awardForShot(g, .iron_key, .again);
    game.tickAwardForShot(g, 0.5);
    shoot(g, "shots/124c_pickup_toasts.png");
    game.awardForShot(g, .iron_key, .clear);

    g.map.nops = saved;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
}

fn knightShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(3.0, -60.0);
    const far = along(sc, LIT_BACK, 120.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    // Rail 0 is the knight's row in `game.BOSS_RAILS`; the bar is per-rail now, not one scalar.
    g.bossK[0] = 1.0;
    g.vigil.n = 1;
    const k = &g.vigil.knights[0];
    const spawn = struct {
        fn it(kk: *knightmod.Knight, at: rl.Vector3, yaw: f32) void {
            kk.* = knightmod.Knight.spawn(at, yaw, 1.0, 0.37);
        }
    }.it;
    const run = struct {
        fn secs(kk: *knightmod.Knight, clock: f32, toward: rl.Vector3) void {
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) _ = kk.update(SHOT_DT, toward, game.PLAY_HALF, .{});
        }
    }.secs;

    // THE STANDING PORTRAIT, SHOT THREE-QUARTER — and the hero parked OUT OF AGGRO: the sentinel brain
    // attacks anything staged inside its own bands. Turned 42 deg off the lens so the door foreshortens.
    spawn(k, sc, mathx.headingXZ(mathx.headingDir(mathx.headingXZ(LIT_BACK) + mathx.radians(42.0))));
    standHero(g, far.x, far.z, mathx.radians(LIT_YAW + 180));
    stepFoe(k, 30, far);
    shootAt(g, "shots/121_knight.png", v3(sc.x, sc.y + 2.5, sc.z), LIT_YAW, 0.14, 12.0);

    spawn(k, sc, mathx.headingXZ(mathx.scaleV(LIT_BACK, -1)));
    stepFoe(k, 30, far);
    shootAt(g, "shots/121a_knight_back.png", v3(sc.x, sc.y + 2.5, sc.z), LIT_YAW, 0.14, 12.0);

    g.hero.pos = mathx.ground(sc.x, sc.z - 44.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();

    const near = along(sc, mathx.headingDir(mathx.headingXZ(LIT_BACK) + mathx.radians(38.0)), 4.0);
    const atHero = mathx.headingXZ(mathx.dirXZ(sc, near));
    const bash = knightmod.moveClock(knightmod.BASH_I);
    spawn(k, sc, atHero);
    k.debugBash();
    run(k, bash.wind * 0.9, near);
    shootAt(g, "shots/121b_knight_bash_wind.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);
    run(k, bash.wind * 0.1 + bash.strike * 0.8, near);
    shootAt(g, "shots/121c_knight_bash.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);

    spawn(k, sc, atHero);
    k.debugSwat(false);
    run(k, knightmod.moveClock(knightmod.SWAT_I).wind + knightmod.moveClock(knightmod.SWAT_I).strike * 0.55, near);
    shootAt(g, "shots/121v_knight_swat_sword.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW, 0.12, 12.0);
    spawn(k, sc, atHero);
    k.debugSwat(true);
    run(k, knightmod.moveClock(knightmod.SWAT_I).wind + knightmod.moveClock(knightmod.SWAT_I).strike * 0.55, near);
    shootAt(g, "shots/121w_knight_swat_shield.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW, 0.12, 12.0);
    spawn(k, sc, atHero);
    k.debugAwaken();
    run(k, knightmod.awakenPeak(), near);
    shootAt(g, "shots/121t_knight_awaken.png", v3(sc.x, sc.y + 3.2, sc.z), LIT_YAW, 0.18, 14.0);
    spawn(k, sc, atHero);
    k.lit = true;
    k.debugSweep();
    {
        var gc: f32 = 0;
        const until = knightmod.moveClock(knightmod.SWEEP_I);
        while (gc < until.wind + until.strike + 0.75) : (gc += SHOT_DT) {
            _ = g.vigil.update(SHOT_DT, near, game.PLAY_HALF, .{});
        }
    }
    shootAt(g, "shots/121ta_knight_gas.png", v3(sc.x, sc.y + 1.4, sc.z), LIT_YAW, 0.10, 12.0);
    {
        var gc: f32 = 0;
        const away = along(sc, mathx.headingDir(mathx.headingXZ(LIT_BACK)), 40.0);
        while (gc < knightmod.GAS_LIFE * 0.86) : (gc += SHOT_DT) {
            _ = g.vigil.update(SHOT_DT, away, game.PLAY_HALF, .{});
        }
    }
    shootAt(g, "shots/121tb_knight_gas_late.png", v3(sc.x, sc.y + 1.4, sc.z), LIT_YAW, 0.10, 12.0);
    spawn(k, sc, atHero);
    k.debugLeap();
    run(k, knightmod.leapPeak(), near);
    shootAt(g, "shots/121y_knight_leap.png", v3(sc.x, sc.y + 2.8, sc.z), LIT_YAW, 0.16, 14.0);
    spawn(k, sc, atHero);
    k.debugStepTurn();
    run(k, knightmod.stepTurnMid(), near);
    shootAt(g, "shots/121z_knight_stepturn.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.14, 12.0);

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

    const sweep = knightmod.moveClock(knightmod.SWEEP_I);
    spawn(k, sc, atHero);
    k.debugSweep();
    run(k, sweep.wind * 0.92, near);
    shootAt(g, "shots/121d_knight_sweep_cock.png", v3(sc.x, sc.y + 3.0, sc.z), LIT_YAW, 0.16, 13.0);
    run(k, sweep.wind * 0.08 + sweep.strike * 0.55, near);
    shootAt(g, "shots/121e_knight_sweep.png", v3(sc.x, sc.y + 2.2, sc.z), LIT_YAW, 0.10, 12.0);

    const over = knightmod.moveClock(knightmod.OVER_I);
    spawn(k, sc, atHero);
    k.debugOverhead();
    run(k, over.wind * 0.92, near);
    shootAt(g, "shots/121p_knight_over_cock.png", v3(sc.x, sc.y + 3.4, sc.z), LIT_YAW, 0.18, 13.0);
    run(k, over.wind * 0.08 + over.strike + over.recover * 0.20, near);
    shootAt(g, "shots/121q_knight_over_buried.png", v3(sc.x, sc.y + 2.0, sc.z), LIT_YAW, 0.14, 12.0);

    const thr = knightmod.moveClock(knightmod.THRUST_I);
    spawn(k, sc, atHero);
    k.debugThrust();
    run(k, thr.wind * 0.9, near);
    shootAt(g, "shots/121r_knight_thrust_cock.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 11.0);
    run(k, thr.wind * 0.1 + thr.strike * 0.9, near);
    shootAt(g, "shots/121s_knight_thrust.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.12, 12.0);

    spawn(k, sc, atHero);
    k.debugSlam();
    const slam = knightmod.slamClock();
    run(k, slam.wind * 0.9, near);
    shootAt(g, "shots/121l_knight_slam_haul.png", v3(sc.x, sc.y + 3.2, sc.z), LIT_YAW, 0.16, 13.0);
    run(k, slam.wind * 0.1 + slam.strike * 0.65, near);
    {
        const mark = k.slamMarkOf();
        shootAt(g, "shots/121m_knight_slam.png", v3(mark.x, sc.y + 1.1, mark.z), LIT_YAW, 0.30, 12.0);
    }

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
    // …and the SKID. A FRESH, SHORTER run: chasing the 16 m hero to the travel's end parks him inside the
    // cliffs east of the court. A hero 7 m out is a 9.6 m line (the overrun), ~1.44 s of travel; +0.30
    // lands a third into the brake, in the open.
    const skidWay = across2 + std.math.pi;
    const skidHero = along(sc, mathx.headingDir(skidWay), 7.0);
    spawn(k, sc, skidWay);
    k.debugCharge();
    run(k, chg.wind + 1.74, skidHero);
    shootAt(g, "shots/121o2_knight_charge_skid.png", v3(k.pos.x, sc.y + 2.2, k.pos.z), LIT_YAW, 0.14, 12.0);

    // THE FALL, all five beats, SHOT IN PROFILE FROM ABOVE. He is stood across the lens (facing 90 deg off
    // the camera's bearing) with the hero dead behind him, so the topple sweeps ACROSS the frame.
    // `sc + back*L` is where his body ends up, and that, not his feet, is what the later frames aim at.
    const across = mathx.headingXZ(LIT_BACK) + mathx.radians(90.0);
    const backDir = mathx.scaleV(mathx.headingDir(across), -1);
    const behind = along(sc, backDir, 3.6);
    const lying = along(sc, backDir, 2.6);
    const fc = knightmod.fallClock();
    spawn(k, sc, across);
    k.debugFall();
    run(k, fc.wind * 0.88, behind);
    shootAt(g, "shots/121f_knight_fall_tell.png", v3(sc.x, sc.y + 2.4, sc.z), LIT_YAW, 0.20, 12.0);
    run(k, fc.wind * 0.12 + fc.drop * 0.55, behind);
    shootAt(g, "shots/121g_knight_falling.png", v3(lying.x, sc.y + 1.8, lying.z), LIT_YAW, 0.34, 12.0);
    run(k, fc.drop * 0.45 + 0.10, behind);
    shootAt(g, "shots/121h_knight_landed.png", v3(lying.x, sc.y + 0.9, lying.z), LIT_YAW, 0.40, 11.0);
    run(k, fc.down - 0.10 + fc.roll * 0.55, behind);
    shootAt(g, "shots/121i_knight_rollover.png", v3(lying.x, sc.y + 0.8, lying.z), LIT_YAW, 0.36, 10.0);
    run(k, fc.roll * 0.45 + fc.rise * 0.58, behind);
    shootAt(g, "shots/121j_knight_rise.png", v3(lying.x, sc.y + 1.4, lying.z), LIT_YAW, 0.28, 11.0);

    spawn(k, sc, faceCam);
    k.debugKill();
    stepFoe(k, 96, far);
    shootAt(g, "shots/121k_knight_death.png", v3(sc.x, sc.y + 1.2, sc.z), LIT_YAW + 26, 0.30, 12.0);

    knightDoorShots(g, sc, faceCam, far, spawn, run);
    knightStrokeStrips(g, sc, spawn, run);
    game.clearFoesForShot(g);
    g.bossK[0] = 0;
}

/// **HOW HE HOLDS IT, FROM ALL FOUR SIDES.** The one thing the owner keeps having to say out loud, and the
/// three-quarter portrait cannot answer it: at 12 m the door covers the whole creature and the arm behind it is
/// four grey pixels. Framed off his own crown instead, and turned rather than orbited so the sun stays over the
/// lens shoulder (`LIT_YAW`).
fn knightDoorShots(
    g: *Game,
    sc: rl.Vector3,
    faceCam: f32,
    far: rl.Vector3,
    spawn: fn (*knightmod.Knight, rl.Vector3, f32) void,
    run: fn (*knightmod.Knight, f32, rl.Vector3) void,
) void {
    const k = &g.vigil.knights[0];
    const bossWas = g.bossK[0];
    g.bossK[0] = 0;
    // The crown is what the boom is solved against, so a re-scaled knight re-frames itself.
    spawn(k, sc, faceCam);
    const crown = k.topWorld().y - k.pos.y;
    const lift = crown * 0.5 - 0.15;
    // The DOOR stands forward of him, so it is nearer the lens than his crown and overflows a boom solved off it.
    const dist = (crown * 0.5) * 1.55 / 0.5206;
    const sides = [_]struct { tag: []const u8, turn: f32 }{
        .{ .tag = "a_front", .turn = 0 },
        .{ .tag = "b_swordside", .turn = 90 },
        .{ .tag = "c_back", .turn = 180 },
        .{ .tag = "d_doorside", .turn = 270 },
    };
    for (sides) |s| {
        spawn(k, sc, faceCam + mathx.radians(s.turn));
        run(k, 0.60, far);
        var name: [64]u8 = undefined;
        const p = std.fmt.bufPrintZ(&name, "shots/122{s}_knight_carry.png", .{s.tag}) catch continue;
        shootAt(g, p, v3(sc.x, sc.y + lift, sc.z), LIT_YAW, 0.12, dist);
    }
    g.bossK[0] = bossWas;
}

/// **THE STRIP'S BOOM IS SOLVED AGAINST THE ARC, NOT PICKED.** `lift` is the measured mid of everything the
/// stroke moves — sword AND door, feet to crown — and `dist` is what puts that span across `STRIP_FILL` of the
/// frame. Its own test re-measures and re-solves, because the arcs get re-authored under it: framed for the old
/// ones at 13-15 m the four strokes filled 40% of a frame aimed a metre over where the action had moved to.
const STRIP_FILL: f32 = 1.0 / 1.30;
const KNIGHT_STRIP = [_]struct { i: usize, tag: []const u8, pitch: f32, dist: f32, lift: f32 }{
    .{ .i = knightmod.SWEEP_I, .tag = "x", .pitch = 0.20, .dist = 8.5, .lift = 2.53 },
    .{ .i = knightmod.BASH_I, .tag = "y", .pitch = 0.16, .dist = 7.7, .lift = 2.88 },
    .{ .i = knightmod.OVER_I, .tag = "z", .pitch = 0.18, .dist = 10.7, .lift = 3.41 },
    .{ .i = knightmod.THRUST_I, .tag = "w", .pitch = 0.14, .dist = 8.7, .lift = 2.53 },
};

/// EVERY FRAME OF ALL THREE STROKES, IN PROFILE — stood ACROSS the lens so the arc travels the frame instead
/// of foreshortening down it, walked at a fixed step so a stroke that snaps breaks between two frames.
fn knightStrokeStrips(
    g: *Game,
    sc: rl.Vector3,
    spawn: fn (*knightmod.Knight, rl.Vector3, f32) void,
    run: fn (*knightmod.Knight, f32, rl.Vector3) void,
) void {
    const k = &g.vigil.knights[0];
    const across = mathx.headingXZ(LIT_BACK) + mathx.radians(90.0);
    const side = along(sc, mathx.headingDir(across), 4.2);
    // **THE FRAMES ARE SPENT WHERE THE MOTION IS, NOT SPREAD EVENLY OVER THE MOVE.** The sweep is 1.15 s of
    // wind and 0.42 s of strike, so an even walk lands most frames in the wind and one in the stroke. Two
    // frames establish the gather; the remaining six are the STRIKE.
    const NW = 2;
    const NS = 6;
    inline for (KNIGHT_STRIP) |st| {
        const cl = knightmod.moveClock(st.i);
        var f: usize = 0;
        while (f < NW + NS) : (f += 1) {
            const at = if (f < NW)
                cl.wind * (0.45 + 0.40 * @as(f32, @floatFromInt(f)))
            else
                cl.wind + cl.strike * (@as(f32, @floatFromInt(f - NW)) + 0.5) / @as(f32, @floatFromInt(NS));
            spawn(k, sc, mathx.headingXZ(mathx.dirXZ(sc, side)));
            // EVERY INDEX THE TABLE CAN HAND IT IS NAMED. As `else => debugBash()` the two rows not in
            // `strokes` today would photograph a BASH under their own caption the day one is added.
            switch (st.i) {
                knightmod.SWEEP_I => k.debugSweep(),
                knightmod.SWEEP2_I => k.debugSweep2(),
                knightmod.OVER_I => k.debugOverhead(),
                knightmod.THRUST_I => k.debugThrust(),
                knightmod.BASH_I => k.debugBash(),
                knightmod.SWAT_I => k.debugSwat(true),
                else => unreachable,
            }
            run(k, at, side);
            var name: [64]u8 = undefined;
            const p = std.fmt.bufPrintZ(&name, "shots/121{s}{d}_knight_stroke.png", .{ st.tag, f }) catch continue;
            shootAt(g, p, v3(sc.x, sc.y + st.lift, sc.z), LIT_YAW, st.pitch, st.dist);
        }
    }
}

test "THE STRIP FRAMES THE ARC IT IS A STRIP OF — solved against the swept kit, not against the old poses" {
    // He stands ACROSS the lens, so screen-vertical is world Y and screen-horizontal is his own FACING axis.
    // The box is everything the stroke moves — sword, DOOR, and the body under them — and the frame must both
    // CONTAIN it and be FILLED by it: nothing clipped, and no postage stamp in a picture of the sky.
    const dt = 1.0 / 60.0;
    const aspect = @as(f32, game.SCREEN_W) / @as(f32, game.SCREEN_H);
    const halfFov = mathx.radians(camera.FOVY * 0.5);
    const tanHalf = mathx.sinf(halfFov) / mathx.cosf(halfFov);
    for (KNIGHT_STRIP) |st| {
        var k = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.37);
        const side = v3(0, 0, 4.2);
        switch (st.i) {
            knightmod.SWEEP_I => k.debugSweep(),
            knightmod.BASH_I => k.debugBash(),
            knightmod.OVER_I => k.debugOverhead(),
            knightmod.THRUST_I => k.debugThrust(),
            else => unreachable,
        }
        var loY: f32 = 0;
        var hiY: f32 = k.topWorld().y - k.pos.y;
        var wideF: f32 = 0;
        const cl = knightmod.moveClock(st.i);
        var c: f32 = 0;
        while (c < cl.wind + cl.strike) : (c += dt) {
            _ = k.update(dt, side, 400.0, .{});
            const fw = mathx.headingDir(k.facing);
            const sword = k.weaponSeg();
            const plank = k.shieldSeg();
            for ([_]rl.Vector3{ sword[0], sword[1], plank[0], plank[1] }) |p| {
                loY = mathx.minF(loY, p.y - k.pos.y);
                hiY = mathx.maxF(hiY, p.y - k.pos.y);
                wideF = mathx.maxF(wideF, @abs((p.x - k.pos.x) * fw.x + (p.z - k.pos.z) * fw.z));
            }
        }
        const halfH = st.dist * tanHalf;
        const span = hiY - loY;
        const fill = span / (2.0 * halfH);
        std.debug.print("\n  strip {s}: arc {d:.2}..{d:.2} m up, {d:.2} m out along him; frame {d:.2} m tall at {d:.1} m — fills {d:.0}%\n", .{ st.tag, loY, hiY, wideF, 2.0 * halfH, st.dist, fill * 100.0 });
        try std.testing.expect(@abs(st.lift + camera.TARGET_RAISE - (loY + hiY) * 0.5) <= 0.25);
        try std.testing.expect(wideF + camera.SHOULDER <= halfH * aspect);
        try std.testing.expect(fill >= STRIP_FILL * 0.85 and fill <= STRIP_FILL * 1.13);
    }
}

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

    g.hero.respawnNow();
    game.clearFoesForShot(g);
    g.cluster.n = 1;
    const m = &g.cluster.shrooms[0];
    m.* = shroommod.Shroom.spawn(mathx.ground(mark.x - 6.0, mark.z), 0, 1.0, 0.23);
    standHero(g, mark.x, mark.z, mathx.headingXZ(LIT_BACK));

    m.debugFling(g.hero.pos);
    soak(g, 46 + 34);
    soak(g, 90);
    shootClear(g, "shots/119f_poison_filling.png", LIT_YAW, 0.10, 5.2);

    m.* = shroommod.Shroom.spawn(mathx.ground(mark.x - 6.0, mark.z), 0, 1.0, 0.23);
    m.debugFling(g.hero.pos);
    var k: i32 = 0;
    while (k < 60 * 6 and !g.hero.vit.ailOn(.poison)) : (k += 1) {
        _ = g.cluster.update(SHOT_DT, g.hero.pos, game.PLAY_HALF, .{});
        game.tickPoisonForShot(g, SHOT_DT);
    }
    shootClear(g, "shots/119g_poison_proc.png", LIT_YAW, 0.10, 5.2);
    // …AND THE WORD IT SAYS, half a second later. On the proc frame itself the caption is still fading IN, so
    // the shot above photographs it at zero alpha by design; this is the one that shows it.
    soakDrawn(g, 30);
    shootClear(g, "shots/119g2_status_word.png", LIT_YAW, 0.10, 5.2);

    game.clearFoesForShot(g);
    var d: i32 = 0;
    while (d < 60 * 6) : (d += 1) game.tickPoisonForShot(g, SHOT_DT);
    shootClear(g, "shots/119h_poison_draining.png", LIT_YAW, 0.10, 5.2);
    g.hero.respawnNow();
}

fn leechShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(-24.0, 34.0);
    const near = along(sc, LIT_BACK, 1.1);
    const far = along(sc, LIT_BACK, 90.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.swarm.n = 3;
    const f = &g.swarm.flies[0];
    const away = mathx.ground(sc.x - 60.0, sc.z + 60.0);
    const spawn = struct {
        fn it(fly: *leechmod.Leechfly, at: rl.Vector3, yaw: f32, seed: f32) void {
            fly.* = leechmod.Leechfly.spawn(at, yaw, 1.0, seed);
        }
    }.it;

    spawn(f, mathx.ground(sc.x - 1.5, sc.z), faceCam, 0.18);
    spawn(&g.swarm.flies[1], mathx.ground(sc.x + 0.4, sc.z + 1.3), faceCam, 0.61);
    spawn(&g.swarm.flies[2], mathx.ground(sc.x + 2.0, sc.z - 0.6), faceCam, 0.89);
    for (g.swarm.live()) |*fly| stepFoe(fly, 30, far);
    standHero(g, sc.x + 3.0, sc.z - 3.2, mathx.radians(-140));
    shootAt(g, "shots/117_swarm.png", v3(sc.x, sc.y + 1.5, sc.z), LIT_YAW, 0.04, 7.0);

    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    for ([_]usize{ 1, 2 }) |i| spawn(&g.swarm.flies[i], away, faceCam, 0.5);

    spawn(f, sc, faceCam, 0.18);
    stepFoe(f, 30, far);
    shootFoe(g, f, "shots/117a_leech_idle.png", LIT_YAW, 0.04, 3.4);
    shootFoe(g, f, "shots/117b_leech_side.png", LIT_YAW + 68, 0.03, 3.4);
    shootFoe(g, f, "shots/117c_leech_top.png", LIT_YAW + 20, 0.85, 3.2);
    shootAt(g, "shots/117d_leech_head.png", f.lockPoint(), LIT_YAW + 30, 0.02, 1.3);

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

    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    spawn(f, sc, faceCam, 0.18);
    f.debugClimb();
    stepFoe(f, 26, near);
    standHero(g, sc.x + 0.5, sc.z - 2.4, mathx.radians(LIT_YAW + 180));
    shootAt(g, "shots/117i_leech_climb.png", v3(sc.x, sc.y + 3.1, sc.z), LIT_YAW, 0.12, 7.6);

    spawn(f, sc, faceCam, 0.18);
    f.stagger(true);
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
    const sc = mathx.ground(-24.0, 34.0);
    const near = along(sc, LIT_BACK, 1.4);
    const far = along(sc, LIT_BACK, 90.0);
    const faceCam = mathx.headingXZ(LIT_BACK);
    g.haunt.n = 3;
    const s = &g.haunt.shades[0];
    const away = mathx.ground(sc.x - 60.0, sc.z + 60.0);
    const spawn = struct {
        fn it(sh: *shademod.Shade, at: rl.Vector3, yaw: f32, seed: f32) void {
            sh.* = shademod.Shade.spawn(at, yaw, 1.0, seed);
        }
    }.it;

    spawn(s, mathx.ground(sc.x - 1.6, sc.z), faceCam, 0.18);
    spawn(&g.haunt.shades[1], mathx.ground(sc.x + 0.2, sc.z + 1.1), faceCam, 0.63);
    spawn(&g.haunt.shades[2], mathx.ground(sc.x + 1.9, sc.z - 0.4), faceCam, 0.87);
    for (g.haunt.live()) |*sh| stepFoe(sh, 40, far);
    standHero(g, sc.x + 3.0, sc.z - 3.2, mathx.radians(-140));
    shootAt(g, "shots/116_haunting.png", v3(sc.x, sc.y + 1.05, sc.z), LIT_YAW, 0.06, 7.6);

    g.hero.pos = mathx.ground(sc.x, sc.z - 30.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    for ([_]usize{ 1, 2 }) |i| spawn(&g.haunt.shades[i], away, faceCam, 0.5);

    spawn(s, sc, faceCam, 0.18);
    stepFoe(s, 40, far);
    shootFoe(g, s, "shots/116a_shade_idle.png", LIT_YAW, 0.04, 4.4);
    shootFoe(g, s, "shots/116b_shade_side.png", LIT_YAW + 66, 0.04, 4.4);
    shootAt(g, "shots/116c_shade_cowl.png", s.lockPoint(), LIT_YAW, 0.02, 1.9);

    const beat = struct {
        fn at(gg: *Game, sh: *shademod.Shade, home: rl.Vector3, face: f32, which: usize, clock: f32, name: [:0]const u8, toward: rl.Vector3, yaw: f32, dist: f32) void {
            sh.* = shademod.Shade.spawn(home, face, 1.0, 0.18);
            sh.debugMove(which);
            var c: f32 = 0;
            while (c < clock) : (c += SHOT_DT) {
                _ = sh.update(SHOT_DT, toward, game.PLAY_HALF, .{});
                game.stepArrowsForShot(gg, SHOT_DT);
            }
            shootPortrait(gg, name, sh.centerWorld(), yaw, 0.05, dist);
        }
    }.at;
    const gc = shademod.moveClock(shademod.GRASP);
    beat(g, s, sc, faceCam, shademod.GRASP, gc.wind * 0.94, "shots/116d_grasp_wide.png", near, LIT_YAW + 16, 4.2);
    beat(g, s, sc, faceCam, shademod.GRASP, gc.wind + gc.strike * 0.62, "shots/116e_grasp_close.png", near, LIT_YAW + 16, 4.2);

    const wc = shademod.moveClock(shademod.WISP);
    beat(g, s, sc, faceCam, shademod.WISP, wc.wind * 0.96, "shots/116f_wisp_gather.png", near, LIT_YAW + 16, 4.0);
    beat(g, s, sc, faceCam, shademod.WISP, wc.wind + wc.strike + 0.10, "shots/116g_wisp_thrown.png", near, LIT_YAW + 16, 5.4);
    game.clearShaftsForShot(g);

    spawn(s, sc, faceCam, 0.18);
    s.debugBlink(near);
    var t: f32 = 0;
    while (t < shademod.BLINK_OUT * 0.62) : (t += SHOT_DT) _ = s.update(SHOT_DT, near, game.PLAY_HALF, .{});
    shootFoe(g, s, "shots/116h_blink_out.png", LIT_YAW, 0.05, 4.4);
    while (t < shademod.BLINK_OUT + shademod.BLINK_IN * 0.45) : (t += SHOT_DT) _ = s.update(SHOT_DT, near, game.PLAY_HALF, .{});
    shootFoe(g, s, "shots/116i_blink_in.png", LIT_YAW, 0.05, 4.4);

    spawn(s, sc, faceCam, 0.18);
    s.stagger(true);
    stepFoe(s, 16, far);
    shootFoe(g, s, "shots/116j_shade_stagger.png", LIT_YAW + 20, 0.06, 4.4);

    spawn(s, sc, faceCam, 0.18);
    s.debugKill();
    stepFoe(s, 22, far);
    shootFoe(g, s, "shots/116k_shade_death.png", LIT_YAW + 24, 0.10, 4.8);

    game.clearFoesForShot(g);
    game.rehomeFoesForShot(g);
}

fn campfireShots(g: *Game) void {
    const saved = g.map.nops;
    if (saved + 2 > worldfmt.MAX_OPS) return;
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
    game.rehomeChestsForShot(g);

    const gy = mathx.ground(cx, cz).y;
    g.hero.pos = mathx.ground(cx, cz - 24.0);
    g.hero.update(SHOT_DT, 0, 0, null);
    g.hero.pose();
    shootPortrait(g, "shots/114_campfires.png", v3(cx, gy + 0.5, cz), LIT_YAW, 0.16, 6.4);
    shootPortrait(g, "shots/114b_campfire_dead.png", v3(cx - 1.8, gy + 0.30, cz), LIT_YAW, 0.20, 2.6);
    const right = v3(-LIT_BACK.z, 0, LIT_BACK.x);
    const hx = cx + 1.8 + right.x * 1.7;
    const hz = cz + right.z * 1.7;
    standHero(g, hx, hz, mathx.headingXZ(v3(cx + 1.8 - hx, 0, cz - hz)));
    g.rest.look(g.hero.pos);
    shootAt(g, "shots/114c_campfire_prompt.png", g.hero.shoulderPoint(), LIT_YAW, 0.10, 4.6);

    g.map.nops = saved;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
}

fn soulsShots(g: *Game) void {
    game.clearFoesForShot(g);
    const sc = mathx.ground(-14.0, 30.0);
    const gy = mathx.ground(sc.x, sc.z).y;
    const aim = v3(sc.x, gy + soulsmod.H * 0.55, sc.z);
    const screenRight = v3(-mathx.cosf(mathx.radians(LIT_YAW)), 0, mathx.sinf(mathx.radians(LIT_YAW)));
    const hero = v3(sc.x + screenRight.x * 2.1, 0, sc.z + screenRight.z * 2.1);
    standHero(g, hero.x, hero.z, mathx.headingXZ(v3(sc.x - hero.x, 0, sc.z - hero.z)));
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
    op.loot[3] = .kobold_fang;
    op.nloot = 4;
    g.map.ops[g.map.nops] = op;
    g.map.nops += 1;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
    g.bag = .{};

    const gy = mathx.ground(cx, cz).y;
    const right = v3(-LIT_BACK.z, 0, LIT_BACK.x);
    const hx = cx + right.x * 1.8;
    const hz = cz + right.z * 1.8;
    const aim = v3(cx, gy + 0.55, cz);
    standHero(g, hx, hz, mathx.headingXZ(v3(cx - hx, 0, cz - hz)));
    g.chests.update(SHOT_DT, g.hero.pos);
    shootPortrait(g, "shots/106_chest_closed.png", aim, LIT_YAW, 0.16, 4.4);

    _ = game.openChestForShot(g);
    const names = [_][:0]const u8{ "shots/106b_chest_opening.png", "shots/106c_chest_opening.png", "shots/106d_chest_open.png" };
    for ([_]i32{ 8, 10, 34 }, 0..) |adv, i| {
        var f: i32 = 0;
        while (f < adv) : (f += 1) g.chests.update(SHOT_DT, g.hero.pos);
        shootPortrait(g, names[i], aim, LIT_YAW, 0.16, 4.4);
    }

    for ([_]item.Kind{ .mushroom_jerky, .bloodgrass, .kobold_fang, .rune_arc, .golden_seed, .smithing_stone, .iron_key, .fire_tallow, .thundercrock, .nameless_soul, .toadflesh_broth, .spirit_scroll_wolf }) |k| {
        if (g.bag.count(k) == 0) g.bag.add(k, if (k == .bloodgrass) 12 else 3);
    }
    for (0..item.NK) |i| {
        const k: item.Kind = @enumFromInt(i);
        if (item.wearable(k) and g.bag.count(k) == 0) g.bag.add(k, 1);
        // …AND EVERY TOOL, ASKED FOR RATHER THAN LISTED. The hand-written row above it is the curiosities that
        // do nothing (`usable` is false for those); a new consumable added to the game photographed itself as
        // nothing at all until this line, because it was not in anybody's list.
        if (item.usable(k) and !item.isFlask(k) and g.bag.count(k) == 0) g.bag.add(k, 3);
    }
    // …AND EVERY SORCERY SCROLL, or the spell page photographs seven dimmed rows and says 0 of 7 carried.
    for (combat.SPELLS) |row| {
        if (g.bag.count(row.scroll) == 0) g.bag.add(row.scroll, 1);
    }
    g.menu.onStartButton();
    bookShot(g, "shots/106e_book_equipment.png", .equipment, bookmod.slotOrdinal(.right), null, 0);
    bookShot(g, "shots/106f_book_swap.png", .equipment, bookmod.slotOrdinal(.right), bookmod.slotOrdinal(.right), 1);
    bookShot(g, "shots/106f3_book_bell.png", .equipment, bookmod.slotOrdinal(.right), bookmod.slotOrdinal(.right), 2);
    bookShot(g, "shots/106f2_book_quickbar.png", .equipment, bookmod.slotOrdinal(.q2), bookmod.slotOrdinal(.q2), 3);
    bookShot(g, "shots/106g_book_inventory.png", .inventory, 0, null, 0);
    // …AND THE PAGE THE NEWEST GEAR IS ON. A bag with every kind in it runs past one grid, so the frame
    // staged at cursor 0 shows the oldest twenty rows and nothing else.
    bookShot(g, "shots/106g2_book_inventory_p2.png", .inventory, item.NK - 1, null, 0);
    // …AND THE LONGEST ROW IN THE GAME, which is the one that proves the panel WRAPS it: four dials plus a dose
    // (`item.effect` of the envenomed dirk) runs past the pane's width and used to draw out through the frame.
    bookShot(g, "shots/106g3_book_longest_row.png", .inventory, bagOrdinalOf(g, .envenomed_dagger), null, 0);
    bookShot(g, "shots/106h_book_stats.png", .stats, @intFromEnum(stats.Attr.endurance), null, 0);
    // …AND A SKILL, which answers in a MULTIPLE rather than a bar's length (`stats.scaleFor`).
    bookShot(g, "shots/106h2_book_stats_skill.png", .stats, @intFromEnum(stats.Attr.strength), null, 0);
    bookShot(g, "shots/106i_book_tree.png", .tree, ptree.armFirst(.wizard) + ptree.PER_ARM - 1, null, 0);

    const memWas = g.hero.mem;
    g.hero.mem.put(1, .levin);
    g.hero.mem.put(2, .rime);
    bookShot(g, "shots/106k_book_spells.png", .spells, @intFromEnum(combat.Spell.rime), null, 0);
    // …and a rung he has no scroll for, which is the one row the page dims.
    const hadLance = g.bag.count(combat.spellScroll(.lance));
    _ = g.bag.take(combat.spellScroll(.lance), hadLance);
    bookShot(g, "shots/106k2_book_spells_missing.png", .spells, @intFromEnum(combat.Spell.lance), null, 0);
    g.bag.add(combat.spellScroll(.lance), hadLance);
    g.hero.mem = memWas;

    // **AND THE PAGE WITH THE SUIT ACTUALLY ON.** Staged bare, the doll is seven empty holes and the NOW
    // column reads the plain sword's figures whatever is in the bag.
    const wornWas = g.hero.worn;
    const armWas = g.hero.arm;
    for ([_]item.Kind{ .greatclub, .tower_shield, .quilted_gambeson, .pitted_helm, .marchboots, .banded_warbelt, .ashen_amulet, .leech_signet, .deft_signet }) |k| {
        _ = g.hero.wear(item.wearSlot(k).?, k);
    }
    // THE CLUB IN ITS SOCKET IS NOT THE CLUB IN HIS FIST: the NOW column prices whatever `swingSocket` says
    // is held, so staged without this the page showed a club on the doll and the plain sword's figures.
    g.hero.arm = .club;
    bookShot(g, "shots/106e2_book_geared.png", .equipment, bookmod.slotOrdinal(.chest), null, 0);
    bookShot(g, "shots/106e3_book_geared_pick.png", .equipment, bookmod.slotOrdinal(.right), bookmod.slotOrdinal(.right), 0);
    // A WORN socket as well as a held one: the compare panel's plate rows (armour, the one resistance, the two
    // multipliers) share nothing with a weapon's but the loop that draws them.
    bookShot(g, "shots/106e4_book_wear_pick.png", .equipment, bookmod.slotOrdinal(.chest), bookmod.slotOrdinal(.chest), 2);
    // **THE TALLEST CARD AND THE SHORTEST, BOTH WITH NO PICKER OPEN** — browsing is what the card is for, and
    // the two ends of it are where it can run out of its box: a coated edge carries six rows over the sheet's
    // own ten, and the ammo cell is gear-less so the sheet has to take the whole column back.
    _ = g.hero.wear(.hand_dagger, .envenomed_dagger);
    g.hero.arm = .dagger;
    bookShot(g, "shots/106e5_book_card_tall.png", .equipment, bookmod.slotOrdinal(.right), null, 0);
    bookShot(g, "shots/106e6_book_no_card.png", .equipment, bookmod.slotOrdinal(.arrows), null, 0);
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        const w: item.Wear = @enumFromInt(f.value);
        _ = g.hero.wear(w, wornWas.at(w));
    }
    g.hero.arm = armWas;
    g.menu.screen = .closed;

    g.map.nops = saved;
    g.env.materialize(&g.map);
    game.rehomeChestsForShot(g);
}

fn faceLens(p: *npcmod.Wanderer) void {
    p.facing = mathx.headingXZ(LIT_BACK);
    p.wantYaw = p.facing;
    p.pose();
}

fn heroAside(g: *Game, from: rl.Vector3) void {
    standHero(g, from.x + 34, from.z + 34, 0);
    plantHeroForShot(g);
}

/// THE FOLK AND WHAT THEY SAY. The staff PLANT happens once a stride and the panel has a different shape
/// for answers and for a plain Continue; the `need:` gate needs two frames by definition — the same node
/// before and after it opens.
/// **BOTH COUNTERS, WITH SOMETHING IN THE PURSE AND SOMETHING IN THE BAG.** A shop photographed broke shows
/// every row refused and every price in the cannot-afford tone, which is the one state that says least about it.
fn counterShots(g: *Game) void {
    game.clearFoesForShot(g);
    // **THE MENU AND THE EDITOR BOTH HAVE TO BE SHUT.** A filtered run still simulates every stage, so whatever
    // an earlier one left open is still up — the retro rack was, and it photographed itself over this panel.
    g.menu.screen = .closed;
    g.editor.on = false;
    g.hero.gold.total = 1450;
    g.hero.gold.shown = 1450;
    g.bag.add(.smithing_stone, 6);
    g.bag.add(.mushroom_jerky, 3);
    g.hero.tiers[@intFromEnum(heromod.Armament.sword)] = 4;
    counterSnap(g, .shop, false, "shots/109_counter_shop_buy.png");
    counterSnap(g, .shop, true, "shots/109b_counter_shop_sell.png");
    counterSnap(g, .smithy, false, "shots/109c_counter_smithy.png");
    game.closeCounterForShot(g);
}

/// One counter, drawn over a live scene and snapped BEFORE `endDrawing` (`snap`'s own rule) — `editorSnap`'s
/// shape, because this is the same case: a panel over a running frame.
fn counterSnap(g: *Game, t: countermod.Trade, selling: bool, name: [:0]const u8) void {
    game.openCounterForShot(g, t);
    if (selling) game.counterSellForShot(g);
    drawScene(g);
    counterui.draw(&g.counter, &g.hero, &g.bag, counterui.RAISE, game.counterPortrait(g));
    snap(name);
}

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
    while (k < 90) : (k += 1) game.stepFolkForShot(g, SHOT_DT);
    p.pos = post;

    faceLens(p);
    shootPortrait(g, "shots/108_npc_hooded.png", eye, LIT_YAW, 0.10, 3.4);
    shootPortrait(g, "shots/108b_npc_hood_face.png", face, LIT_YAW, 0.06, 1.30);

    p.variant = 1;
    shootPortrait(g, "shots/108c_npc_bare.png", eye, LIT_YAW, 0.10, 3.4);
    shootPortrait(g, "shots/108d_npc_bare_face.png", face, LIT_YAW, 0.06, 1.30);
    p.variant = 0;

    for (g.folk.live(), 0..) |*q, i| {
        var nameBuf: [64]u8 = undefined;
        const path = std.fmt.bufPrintZ(&nameBuf, "shots/108p_npc_portrait_{d}.png", .{i}) catch continue;
        faceLens(q);
        shootPortrait(g, path, q.facePoint(), LIT_YAW + hudmod.PORTRAIT_YAW, hudmod.PORTRAIT_PITCH, npcmod.PORTRAIT_DIST);
    }
    faceLens(p);

    p.greet();
    k = 0;
    while (k < 17) : (k += 1) game.stepFolkForShot(g, SHOT_DT);
    p.pos = post;
    faceLens(p);
    shootPortrait(g, "shots/108e_npc_beckon.png", eye, LIT_YAW, 0.10, 3.7);

    const laneYaw = mathx.radians(LIT_YAW - 90.0);
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
    shootPortrait(g, "shots/108h_npc_prompt.png", pair, LIT_YAW, 0.12, 4.6);

    must(game.openTalkForShot(g, "wanderer"), "the wanderer's dialog would not open");
    talkShot(g, "shots/108i_dialog_root.png", pair, 20, .{});
    talkShot(g, "shots/108j_dialog_cursor.png", pair, 1, .{ .down = true });
    talkShot(g, "shots/108k_dialog_continue.png", pair, 4, .{ .pick = 1 });
    talkShot(g, "shots/108l_dialog_gate_open.png", pair, 4, .{ .confirm = true });

    var bail: i32 = 0;
    while (g.talk.active() and bail < 40) : (bail += 1) game.stepTalkForShot(g, .{ .pick = 3 });
    must(!g.talk.active(), "the conversation would not close");
    g.folk.hush();

    g.trig.apply(&g.map, firstTextAct(&g.map) orelse {
        must(false, "the map has no `text` action to photograph");
        return;
    });
    shootPortrait(g, "shots/108m_trigger_banner.png", pair, LIT_YAW, 0.12, 4.6);

    g.trig.arm(&g.map);
    g.folk.reset(&g.map);
}

fn firstTextAct(m: *const worldfmt.Map) ?*const worldfmt.Act {
    for (m.trigSlice()) |*t| {
        for (t.actSlice()) |*a| {
            if (a.kind == .text) return a;
        }
    }
    return null;
}

/// One frame of the panel: press `in`, settle `frames`, then scene + panel. `hud` is deliberately NOT called
/// — the live loop suppresses it behind a conversation, and drawing it photographs a screen the game never
/// shows.
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

fn editorSnap(g: *Game, name: [:0]const u8) void {
    drawScene(g);
    editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, &g.day, SHOT_DT);
    snap(name);
}

/// The editor with the JUKEBOX modal up. Its own helper because the modal is opened through the editor's
/// real entry point (`editor.soundsForShot`), never by poking `modal`: the panel reads state entering sets up.
fn editorJukeShot(g: *Game, name: [:0]const u8) void {
    g.editor.enter(mathx.ground(0, -66));
    g.editor.applyCamForShot();
    g.editor.soundsForShot(.ogre_slam);
    g.editor.rackMix = .combat;
    editorSnap(g, name);
    g.editor.on = false;
}

fn editorGapShots(g: *Game) void {
    g.editor.enter(mathx.ground(0, -66));
    g.editor.applyCamForShot();
    g.editor.worldForShot();
    editorSnap(g, "shots/116a_editor_world.png");

    g.editor.zoneMixForShot(&g.map, 0);
    editorSnap(g, "shots/116b_editor_zonemix.png");

    g.editor.closeModalForShot();
    for (g.map.slice(), 0..) |o, i| {
        if (o.op == .belt) {
            g.editor.gradientForShot(&g.map, i);
            break;
        }
    }
    editorSnap(g, "shots/116c_editor_gradient.png");
    g.editor.on = false;
}

fn editorShots(g: *Game) void {
    g.editor.enter(mathx.ground(0, -66));
    g.editor.setLayer(.props);
    g.editor.dist = 46;
    g.editor.pitch = -0.65;
    g.editor.applyCamForShot();

    editorSnap(g, "shots/95_editor_props.png");

    // **THE EYES, AS A PAIR OF SHOTS.** Standing on Ground so nothing is force-shown (`Editor.visible` keeps
    // the layer you are working in on screen whatever its eye says), then everything else shut.
    // **THE ROOMS PANEL, WITH A ROOM UP AND A CORNER GRABBED** — the whole of what an author can do to a boss
    // arena is on this one face, and a corner that does not read as picked is a Delete you cannot aim.
    if (g.map.narenas > 0) {
        g.editor.setLayer(.locations);
        g.editor.selectArenaForShot(&g.map, 0, 3);
        const mid = g.map.arenas[0].middle();
        g.editor.focus = mid;
        g.editor.dist = 62;
        g.editor.pitch = -0.85;
        g.editor.applyCamForShot();
        editorSnap(g, "shots/95e_editor_rooms.png");
        g.editor.setLayer(.props);
        g.editor.focus = mathx.ground(0, -66);
        g.editor.dist = 46;
        g.editor.pitch = -0.65;
        g.editor.applyCamForShot();
    }

    // **THE SCRIPT MODAL** — the one layer the editor could never author, so its face is worth a frame.
    if (g.map.ntrigs > 0) {
        g.editor.openScriptForShot(&g.map);
        editorSnap(g, "shots/95f_editor_script.png");
        // **AND ONE WITH A LIST DOWN.** The panel is the whole of what a dropdown adds over the button it
        // replaced, and it is the one part a still frame cannot reach by clicking.
        uimod.openDropdownForShot(uimod.ddId(1, g.editor.trigSelForShot() orelse 0, 0));
        editorSnap(g, "shots/95g_editor_script_open.png");
        uimod.closeDropdown();
        g.editor.closeModalForShot();
    }

    g.editor.optionsForShot();
    editorSnap(g, "shots/95h_editor_options.png");
    g.editor.closeModalForShot();

    // Both faces of it: the AUTHORING form, and the notice a hand-written tree gets instead.
    for (0..g.map.nnpcs) |ni| {
        g.editor.talkForShot(&g.map, ni);
        editorSnap(g, if (g.editor.talkIsFlatForShot()) "shots/95i_editor_talk.png" else "shots/95j_editor_talk_tree.png");
        g.editor.closeModalForShot();
    }

    g.editor.setLayer(.ground);
    for (&g.editor.shown) |*s| s.* = false;
    g.editor.showWeather = false;
    editorSnap(g, "shots/95b_editor_hidden.png");
    for (&g.editor.shown) |*s| s.* = true;
    g.editor.showWeather = true;
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
    while (wz < 26) : (wz += 2.5) _ = g.map.paintWater(-26 + wz * 0.35, wz, 9.5, true, .natural, .water);
    var wx: f32 = -34;
    while (wx < -8) : (wx += 2.5) _ = g.map.paintWater(wx, 14, 7.5, true, .natural, .water);
    _ = g.map.paintWater(-21, 9, 4.6, false, null, null);
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
    g.env.materialize(&g.map);

    // **THE UNITS PALETTE, BOTH TABS.** Thirty-eight icon rows in one column did not fit the side panel and the
    // tail of it was drawn off the bottom of the window; the Foes tab files by kingdom and the Folk tab is its
    // own list. One shot per tab, because the point of the pair is that they are DIFFERENT lists.
    g.editor.setLayer(.units);
    g.editor.focus = mathx.ground(0, -12);
    g.editor.pitch = -0.8;
    g.editor.yaw = std.math.pi;
    g.editor.dist = 40;
    g.editor.applyCamForShot();
    g.editor.unitsForShot(.foes, .bone);
    editorSnap(g, "shots/98d_editor_units_foes.png");
    g.editor.unitsForShot(.folk, .bone);
    editorSnap(g, "shots/98e_editor_units_folk.png");

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

    // THE PAIR, BIG AND ALONE. A body at fighting range is judged by its silhouette and nothing else, and the
    // land shots have them 30 m off behind a pillar.
    g.editor.charForShot(.fungal_swordsman);
    editorSnap(g, "shots/99f_char_duo_sword.png");
    g.editor.charForShot(.fungal_magus);
    editorSnap(g, "shots/99g_char_duo_magus.png");
    // …and the deer, which is the one body whose whole silhouette is a thing on its BACK.
    g.editor.charForShot(.fungal_deer);
    editorSnap(g, "shots/99h_char_fungal_deer.png");

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

fn dayShots(g: *Game) void {
    const at = mathx.ground(0, -14.0);
    standHero(g, at.x, at.z, 0);
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
        .{ .h = game.daynight.EVENING_HOUR, .name = "shots/147_day_dusk.png" },
    };
    const intoSun: f32 = 232.5 + 180.0;
    for (hours) |row| {
        game.pinHourForShot(g, row.h);
        shootAt(g, row.name, at, intoSun, 0.02, 7.0);
    }
    for ([_]struct { h: f32, name: [:0]const u8 }{
        .{ .h = 7.0, .name = "shots/148_day_shadows_morning.png" },
        .{ .h = 12.0, .name = "shots/148b_day_shadows_noon.png" },
        .{ .h = 19.0, .name = "shots/148c_day_shadows_evening.png" },
    }) |row| {
        game.pinHourForShot(g, row.h);
        shootAt(g, row.name, at, 90, 0.62, 26.0);
    }
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

/// The bag CURSOR for a kind. The panel is staged by ordinal, and a kind's ordinal is where it falls among what
/// he is CARRYING — never its place in the enum (`item.Bag.nth`'s own rule).
fn bagOrdinalOf(g: *const Game, want: item.Kind) usize {
    var i: usize = 0;
    while (g.bag.nth(i)) |k| : (i += 1) {
        if (k == want) return i;
    }
    return 0;
}

fn bookShot(g: *Game, name: [:0]const u8, page: bookmod.Page, cursor: usize, pickSlot: ?usize, row: usize) void {
    g.menu.book.debugShow(page, cursor, pickSlot, row);
    const shelf = savemod.Shelf{};
    _ = g.menu.update(&g.retro, &g.day, &g.weather, SHOT_DT, game.bookView(g), &shelf);
    drawScene(g);
    g.menu.draw(&g.retro, &g.day, &g.weather, game.bookView(g), .{ .hero = &g.hero, .scene = &g.scene }, &shelf);
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
    // rule's problem.
    const chest = v3(g.hero.pos.x, game.heroCenterY(g), g.hero.pos.z);
    shootPortrait(g, "shots/130_bell_carry.png", chest, 53, 0.06, 2.2);
    game.ringForShot(g, heromod.RING_AT);
    shootPortrait(g, "shots/131_bell_ring.png", chest, 53, 0.06, 2.4);

    const at = mathx.ground(9.0, 4.0);
    // FACING ACROSS THE LENS, not down it: pointed at the camera every angle the IK solves is in the plane
    // you cannot see. Gait shots are yaw 90, so it stands at 0.
    game.callWolfForShot(g, at, 0);
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
    game.poseWolfGatherForShot(g, 0.5);
    shootAt(g, "shots/135b_wolf_gather.png", at, 90, 0.05, 3.4);
    game.poseWolfPounceForShot(g, 1.0);
    shootAt(g, "shots/135c_wolf_pounce.png", mathx.addV(at, v3(0, wolfmod.W * 0.8, 0)), 90, 0.10, 4.0);
    game.poseWolfForShot(g, 0, 0);
    shootPortrait(g, "shots/136_wolf_head.png", mathx.addV(at, v3(0, wolfmod.W * 1.0, 0)), 40, 0.02, 1.5);

    g.bag.add(.spirit_scroll_wolf, 1);
    game.showSpiritToastForShot(g);
    shootClear(g, "shots/137_spirit_toast.png", 53, 0.14, 4.6);
    g.pack.clear();
    g.hero.arm = .sword;
}

fn plantHeroForShot(g: *Game) void {
    g.hero.pos.y = g.env.groundAt(g.hero.pos.x, g.hero.pos.z);
    g.hero.pose();
}

const icons = @import("ui/icons.zig");
const itemart = @import("ui/itemart.zig");
const uimod = @import("ui/ui.zig");
const DIR_ART = DIR ++ "/art";

/// **THE WHOLE 2D SET ON CONTACT SHEETS** — every editor glyph at the 18 px it is drawn at and at 3x, every item
/// picture at its 34 px bag cell and at a plate size, the spells, the ailments and the pad kit. No world, no
/// camera: `--shot-art` is the one harness that can judge a glyph set as a set.
pub fn runArtShots(g: *Game) void {
    _ = g;
    std.fs.cwd().makePath(DIR_ART) catch {};
    const W: f32 = @floatFromInt(game.SCREEN_W);
    const ICON_N = @typeInfo(icons.Icon).@"enum".fields.len;

    const sheet = struct {
        fn begin() void {
            rl.beginDrawing();
            rl.clearBackground(uimod.PANEL_FILL);
        }
        fn cellBg(x: f32, y: f32, w: f32, h: f32) void {
            rl.drawRectangleRec(.{ .x = x, .y = y, .width = w, .height = h }, uimod.IDLE_FILL);
            rl.drawRectangleLinesEx(.{ .x = x, .y = y, .width = w, .height = h }, 1, mathx.withAlpha(uimod.TRIM, 80));
        }
    };

    // Editor glyphs at real size, in the button they actually sit in.
    {
        sheet.begin();
        const cols: usize = 5;
        const cw = W / @as(f32, @floatFromInt(cols));
        const rh: f32 = 30;
        var i: usize = 0;
        while (i < ICON_N) : (i += 1) {
            const ic: icons.Icon = @enumFromInt(i);
            const x = @as(f32, @floatFromInt(i % cols)) * cw + 8;
            const y = @as(f32, @floatFromInt(i / cols)) * rh + 8;
            sheet.cellBg(x, y, cw - 16, rh - 4);
            icons.draw(ic, x + 8 + 9, y + (rh - 4) * 0.5, 18, uimod.VALUE);
            hudmod.mono(@tagName(ic), @intFromFloat(x + 8 + 18 + 7), @intFromFloat(y + 4), hudmod.MONO, uimod.VALUE);
        }
        snap(DIR_ART ++ "/00_icons_18.png");
    }
    // …and at 3x, where the construction can be read.
    {
        sheet.begin();
        const cols: usize = 10;
        const cw = W / @as(f32, @floatFromInt(cols));
        const rh: f32 = 96;
        var i: usize = 0;
        while (i < ICON_N) : (i += 1) {
            const ic: icons.Icon = @enumFromInt(i);
            const x = @as(f32, @floatFromInt(i % cols)) * cw + 6;
            const y = @as(f32, @floatFromInt(i / cols)) * rh + 6;
            sheet.cellBg(x, y, cw - 12, rh - 8);
            icons.draw(ic, x + (cw - 12) * 0.5, y + 38, 54, uimod.VALUE);
            var buf: [24]u8 = undefined;
            const name = @tagName(ic);
            const short = std.fmt.bufPrintZ(&buf, "{s}", .{name[0..@min(name.len, 12)]}) catch unreachable;
            hudmod.mono(short, @intFromFloat(x + 4), @intFromFloat(y + rh - 30), 14, uimod.LABEL);
        }
        snap(DIR_ART ++ "/01_icons_54.png");
    }
    // Item pictures at the bag cell and at a plate.
    inline for (.{ .{ 34.0, 12, 60.0, "02_items_34.png" }, .{ 90.0, 8, 130.0, "03_items_90.png" } }) |row| {
        const px: f32 = row[0];
        const cols: usize = row[1];
        const rh: f32 = row[2];
        const cw = W / @as(f32, @floatFromInt(cols));
        var page: usize = 0;
        var i: usize = 0;
        while (i < item.NK) {
            sheet.begin();
            var k: usize = 0;
            while (i < item.NK and @as(f32, @floatFromInt(k / cols)) * rh + rh < @as(f32, @floatFromInt(game.SCREEN_H))) : ({
                i += 1;
                k += 1;
            }) {
                const kind: item.Kind = @enumFromInt(i);
                const x = @as(f32, @floatFromInt(k % cols)) * cw + 4;
                const y = @as(f32, @floatFromInt(k / cols)) * rh + 4;
                sheet.cellBg(x, y, cw - 8, rh - 8);
                itemart.draw(kind, x + (cw - 8) * 0.5, y + (rh - 8) * 0.5 - 6, px);
                const name = item.displayName(kind);
                var buf: [32]u8 = undefined;
                const short = std.fmt.bufPrintZ(&buf, "{s}", .{name[0..@min(name.len, if (cols == 12) 11 else 18)]}) catch unreachable;
                hudmod.mono(short, @intFromFloat(x + 3), @intFromFloat(y + rh - 8 - 16), 13, uimod.LABEL);
            }
            var nb: [64]u8 = undefined;
            const nm = std.fmt.bufPrintZ(&nb, DIR_ART ++ "/{s}_{d}.png", .{ row[3][0 .. row[3].len - 4], page }) catch unreachable;
            snap(nm);
            page += 1;
        }
    }
    // Spells lit and unlit, ailments, and the pad kit.
    {
        sheet.begin();
        const spells = @typeInfo(combat.Spell).@"enum".fields;
        inline for (spells, 0..) |f, i| {
            const sp: combat.Spell = @enumFromInt(f.value);
            const x: f32 = 20 + @as(f32, @floatFromInt(i)) * 136;
            sheet.cellBg(x, 20, 120, 120);
            itemart.spellArt(sp, x + 60, 74, 90, true);
            sheet.cellBg(x, 150, 120, 60);
            itemart.spellArt(sp, x + 30, 180, 34, true);
            itemart.spellArt(sp, x + 90, 180, 34, false);
            hudmod.mono(f.name, @intFromFloat(x), 214, 14, uimod.LABEL);
        }
        const ails = @typeInfo(combat.Ail).@"enum".fields;
        inline for (ails, 0..) |f, i| {
            const a: combat.Ail = @enumFromInt(f.value);
            const x: f32 = 20 + @as(f32, @floatFromInt(i)) * 124;
            sheet.cellBg(x, 260, 110, 110);
            hudmod.ailGlyph(a, x + 55, 310, 60, hudmod.ailTint(a));
            hudmod.ailGlyph(a, x + 20, 355, 13, hudmod.ailTint(a));
            hudmod.ailGlyph(a, x + 45, 355, 13, uimod.VALUE);
            hudmod.mono(f.name, @intFromFloat(x), 374, 14, uimod.LABEL);
        }
        var i: i32 = 0;
        inline for (.{ hudmod.PadBtn.a, hudmod.PadBtn.b, hudmod.PadBtn.x, hudmod.PadBtn.y }) |b| {
            hudmod.padFace(60 + i * 60, 460, hudmod.GLYPH_R, b);
            hudmod.padFace(60 + i * 60, 520, 20, b);
            i += 1;
        }
        inline for (.{ hudmod.Dir.up, hudmod.Dir.down, hudmod.Dir.left, hudmod.Dir.right, hudmod.Dir.updown, hudmod.Dir.leftright }) |d| {
            hudmod.padDpad(60 + i * 60, 460, hudmod.GLYPH_R, d);
            hudmod.padDpad(60 + i * 60, 520, 20, d);
            i += 1;
        }
        hudmod.padMenu(60 + i * 60, 460);
        hudmod.padBumper(60 + (i + 1) * 60, 460, "LB");
        hudmod.padBumper(60 + (i + 2) * 60, 460, "RT");
        hudmod.dayDial(9.5);
        snap(DIR_ART ++ "/04_spells_ails_pads.png");
    }
}
