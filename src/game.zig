const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const gfx = @import("gfx.zig");
pub const daynight = @import("daynight.zig");
const envmod = @import("env.zig");
const worldfmt = @import("worldfmt.zig");
const editormod = @import("editor.zig");
const objviewmod = @import("objview.zig");
const heromod = @import("hero.zig");
const cameramod = @import("camera.zig");
const hud_ = @import("hud.zig");
const menumod = @import("menu.zig");
const bookmod = @import("book.zig");
const frogmod = @import("frog.zig");
const foemod = @import("foe.zig");
const combat = @import("combat.zig");
const collision = @import("collision.zig");
const rumblemod = @import("rumble.zig");
const archermod = @import("archer.zig");
const ogremod = @import("ogre.zig");
const shroommod = @import("shroom.zig");
const koboldmod = @import("kobold.zig");
const broodmod = @import("brood.zig");
const warriormod = @import("warrior.zig");
const rootedmod = @import("rooted.zig");
const knightmod = @import("knight.zig");
const delvermod = @import("delver.zig");
const necromod = @import("necro.zig");
const ravagermod = @import("ravager.zig");
const magemod = @import("shroommage.zig");
const fenmod = @import("fenlurker.zig");
const leechmod = @import("leechfly.zig");
const shademod = @import("shade.zig");
const chestmod = @import("chest.zig");
const pickupmod = @import("pickup.zig");
const awardmod = @import("award.zig");
const restmod = @import("rest.zig");
const soulsmod = @import("souls.zig");
const ptree = @import("passivetree.zig");
const npcmod = @import("npc.zig");
const wolfmod = @import("wolf.zig");
const trigmod = @import("trigger.zig");
const dialogmod = @import("dialog.zig");
const item = @import("item.zig");
const savemod = @import("save.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

const PAD = rumblemod.PAD;
const padPressed = rumblemod.padPressed;
const padDown = rumblemod.padDown;

const SCREEN_W = 1280;
const SCREEN_H = 800;

const WALK_SPEED = heromod.WALK_SPEED;
const RUN_SPEED = heromod.RUN_SPEED;
const SPRINT_SPEED = heromod.SPRINT_SPEED;
const TURN_RATE = 12.0; // rad/sec
const STRAFE_SPEED = heromod.STRAFE_SPEED;
const STICK_DEADZONE = 0.16;
const LOOK_DEADZONE = 0.14;
const LOOK_CLAIM = 0.40;
const MOUSE_WAKE: f32 = 2.0; // pixels of mouse travel in one frame
const LOOK_RATE_YAW = 3.4; // rad/sec at full right-stick deflection
const LOOK_RATE_PITCH = 2.0;
const LOOK_CURVE = 1.7;
const AIM_LOOK_SCALE = 0.42;
const ROLL_TAP_MAX = 0.22; // REAL seconds: shorter = dodge tap, longer = sprint hold
// No run-unlock hold, ever (owner's law): tilt maps straight to ground speed every frame.

// Impact shake fed to the camera rig; `camera.zig` responds trauma².
const SHAKE_HIT_LIGHT = 0.09;
const SHAKE_HIT_HEAVY = 0.15;
const SHAKE_KILL = 0.26;
const SHAKE_CAST = 0.07;
const SHAKE_ROOTS_BITE = 0.20;
const SHAKE_LAND = 0.08;
const SHAKE_HURT = 0.42;
const SHAKE_HURT_HEAVY = 0.62;
const SHAKE_BLOCK = 0.40;
const SHAKE_PARRY = 0.56;
const SHAKE_GUARD_BREAK = 0.72;
/// THE HEAVIEST THING IN THE GAME, which is what a block's felt weight is graded against. A `@max` rather
const BLOW_HEAVIEST = @max(ogremod.SLAM_HIT.raw(), knightmod.FALL_HIT.raw());
const BLOCK_FELT_MIN = 0.25;
const BLOCK_FELT_HEAVY = 0.5;
const SHAKE_DEATH = 0.85;
const SHAKE_CHEST = 0.12;
const STAT_WARN = mathx.rgba(206, 150, 110, 255);
const SHAKE_SKEL_LEAP = 0.24;
const SHAKE_HATCH = 0.30;
const SHAKE_SAC_BURST = 0.34;
const SHAKE_SURGE = 0.26;
const SHAKE_RAISE = 0.30;
const SHAKE_SIGIL = 0.16;
const RESPAWN_HOLD = 0.55; // seconds of FULL black after the respawn…
const RESPAWN_FADE = 0.9;
/// Fractions of screen height; the caption's centre is derived off these.
const DEATH_BAND_TOP: f32 = 0.35;
const DEATH_BAND_H: f32 = 0.30;

pub var PLAY_HALF: f32 = playHalfOf(worldfmt.DEFAULT_HALF);

fn playHalfOf(half: f32) f32 {
    return half - envmod.PLAY_INSET;
}

const HERO_R = foemod.HERO_R;

const MAX_ARROWS = 24;
const MAX_SHAFTS = 12;
/// The hero's centre of mass ABOVE HIS OWN FEET — not a world height.
pub const HERO_CENTER_Y = 1.0;

const COLLIDE_RATE = 11.0; // world units / sec

const GROUND_RISE_RATE = 9.0; // m/s
const GROUND_FALL_RATE = 16.0;
/// Past this the ease is abandoned and the actor planted — a teleport must not slide up out of the earth.
const GROUND_SNAP: f32 = 2.5;

const CLIP_NEAR = 0.55;
const CLIP_FAR = 320.0;

const MAX_LOCK_R = 17.0;
/// How far PAST `MAX_LOCK_R` a HELD lock survives — without the gap a foe on the ring re-acquires every other frame.
const LOCK_KEEP_SLACK: f32 = 2.0;
const LOCK_CAM_EASE = 9.0;
/// Fallback framing pitch, for when the geometry has nothing to say (he is standing inside the target).
const LOCK_PITCH = 0.24;
const LOCK_PITCH_NEAR: f32 = 0.5; // metres of horizontal separation
/// Tilting UP is gated on reach off the creature's own feet (`topWorld`), so a kobold on a rise stays a kobold.
const LOCK_TILT_TALL: f32 = 3.2; // over the shade's 2.4 and under the ogre's 4.4
/// A ramp, not a threshold: the leechfly climbs through this height, and a step here is one the rig's ease chases.
const LOCK_TILT_TALLER: f32 = 3.6;
/// …and closeness earns it too: past `FAR` a creature is framed whole from the default pitch anyway.
const LOCK_TILT_NEAR: f32 = 7.0;
const LOCK_TILT_FAR: f32 = 17.0;
fn lockPitch(g: *const Game, r: FoeRef) f32 {
    const mark = foeLockPoint(g, r);
    const eye = g.rig.cam.position;
    const flat = mathx.distXZ(eye, mark);
    if (flat < LOCK_PITCH_NEAR) return LOCK_PITCH;
    const want = std.math.atan2(eye.y - mark.y, flat);
    if (want >= LOCK_PITCH) return want;
    return mathx.lerpF(LOCK_PITCH, want, lockTiltShare(g, r, flat));
}

/// How much of the up-tilt this target has earned, 0..1 — the PRODUCT, since either alone is a reason not to tilt.
fn lockTiltShare(g: *const Game, r: FoeRef, flat: f32) f32 {
    const rise = foeTopWorld(g, r).y - foePos(g, r).y;
    const tall = mathx.smoothstep(LOCK_TILT_TALL, LOCK_TILT_TALLER, rise);
    const near = 1.0 - mathx.smoothstep(LOCK_TILT_NEAR, LOCK_TILT_FAR, flat);
    return tall * near;
}
const LOCK_FLICK = 0.65; // right-stick |x| past this cycles to the next target
const LOCK_FLICK_MOUSE: f32 = 40.0; // pixels of travel in one frame
/// Debounce: travel must come back under these before another flick is armed, or a held diagonal cycles every frame.
const LOCK_REARM_MOUSE: f32 = 12.0;
const LOCK_REARM_STICK: f32 = 0.3;
/// Seconds a lock survives with no sight of its target — a fade, not a switch, or a pillar drops it.
const LOCK_BLIND_HOLD: f32 = 1.1;

const CLEAR = rgba(80, 76, 69, 255);

const LookProbe = struct {
    mdx: f32 = 0,
    mdy: f32 = 0,
    rx: f32 = 0,
    ry: f32 = 0,
    mag: f32 = 0, // RAW stick magnitude, 0..1
    dyaw: f32 = 0, // DEGREES of yaw applied this frame, whichever device did it
    pad: bool = false,
};

/// A hook that landed this frame and has not been paid out yet (`noteYank` → `applyYank`).
const Hook = struct { from: rl.Vector3, pull: f32 };

const Enter = union(enum) {
    fresh: usize,
    load: usize,
    map: struct { path: []const u8, at: rl.Vector3, facing: f32 },
};
/// How long the screen takes to go down over the menu…
const ENTER_OUT: f32 = 0.40;
const ENTER_IN: f32 = 0.85;

pub const Game = struct {
    scene: gfx.Scene,
    sky: gfx.Sky,
    vignette: gfx.Vignette,
    retro: gfx.Retro,
    menu: menumod.Menu,
    map: worldfmt.Map,
    editor: editormod.Editor,
    env: envmod.Env,
    hero: heromod.Hero,
    warren: frogmod.Knot,
    line: archermod.Line,
    grief: ogremod.Grief,
    band: koboldmod.Warband,
    brood: broodmod.Brood,
    muster: warriormod.Muster,
    grove: rootedmod.Grove,
    cluster: shroommod.Cluster,
    warrens: delvermod.Warrens,
    rite: necromod.Rite,
    thicket: ravagermod.Thicket,
    ring: magemod.Ring,
    marsh: fenmod.Marsh,
    vigil: knightmod.Vigil,
    swarm: leechmod.Swarm,
    haunt: shademod.Haunt,
    chests: chestmod.Chests,
    pickups: pickupmod.Pickups = .{},
    /// …and HOW EITHER OF THEM SAYS WHAT YOU GOT — the first-time card and the toast stack.
    award: awardmod.Award = .{},
    folk: npcmod.Folk,
    /// Deliberately NOT in `FOE_GROUPS`: everything folded over that list is about things trying to kill him.
    pack: wolfmod.Pack = .{},
    /// Which `editor.mapGen` the folk were posted from, so an editor frame re-homes them only when the map changes.
    folkGen: u32 = 0,
    trig: trigmod.Runtime = .{},
    talk: dialogmod.Session = .{},
    npcPos: [npcmod.CAP]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** npcmod.CAP,
    nNpcPos: usize = 0,
    rest: restmod.Rest = .{},
    bootT: f32 = 0,
    bossK: f32 = 0,
    bossFrac: f32 = 0,
    spiritK: f32 = 0,
    spiritHp: f32 = 0,
    /// Survives a death AND a load — the hour is a fact about the world, not about the map file.
    day: daynight.Clock = .{},
    hourLit: f32 = std.math.nan(f32),
    souls: soulsmod.Souls,
    /// Survives a death: what a death takes is the souls on the counter, never what they were spent on.
    tree: ptree.Tree = .{},
    /// The player's own retro stack, parked while a rest borrows the screen for its VHS look.
    restRetro: [gfx.RETRO_COUNT]f32 = [_]f32{0} ** gfx.RETRO_COUNT,
    bag: item.Bag = .{},
    arrowModel: rl.Model,
    clumpModel: rl.Model,
    crockModel: rl.Model,
    venomModel: rl.Model,
    fireArrowModel: rl.Model,
    boltModel: rl.Model,
    emberModel: rl.Model,
    wispModel: rl.Model,
    arrows: [MAX_ARROWS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_ARROWS,
    shafts: [MAX_SHAFTS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_SHAFTS,
    rig: cameramod.CamRig,
    lock: ?FoeRef = null,
    lockBlind: f32 = 0, // seconds since he could last see it (see LOCK_BLIND_HOLD)
    hook: ?Hook = null,
    rumble: rumblemod.Rumble = .{},
    deathFade: f32 = 0, // seconds of post-respawn fade-from-black remaining
    probe: LookProbe = .{},
    /// Cached rather than surveyed per frame; writing a file is the only thing that puts anything on it.
    shelf: savemod.Shelf = .{},
    /// Decided once when the character is started; a fire writes over it without asking. There is no Save row.
    slot: usize = 0,
    /// `rest.justEntered` fires where the screen is still black, so the grab waits for a frame with a picture.
    shotOwed: bool = false,
    enterOut: f32 = 0,
    enterIn: f32 = 0,
    enterAct: ?Enter = null,
    /// The UNSCALED frame time the drawing layer needs — the occluder fade would crawl on a time-scaled dt.
    drawDt: f32 = 1.0 / 60.0,

    fn init(g: *Game) void {
        var initTimer = std.time.Timer.start() catch unreachable;
        const phase = struct {
            fn ms(t: *std.time.Timer, name: []const u8) void {
                std.debug.print("INIT: {s: <10} {d:.1} ms\n", .{ name, @as(f64, @floatFromInt(t.lap())) / 1e6 });
            }
        }.ms;
        g.scene = gfx.Scene.init();
        g.sky = gfx.Sky.init();
        g.vignette = gfx.Vignette.init();
        g.retro = gfx.Retro.init(rl.getScreenWidth(), rl.getScreenHeight());
        g.menu = .{};
        phase(&initTimer, "gfx");
        worldfmt.loadOrPanic(worldfmt.startMap(), &g.map);
        PLAY_HALF = playHalfOf(g.map.half); // before anything spawns against it
        phase(&initTimer, "map");
        g.env.build(&g.scene);
        g.env.uploadSoil(&g.map);
        g.env.uploadWater(&g.map);
        g.env.uploadHeight(&g.map);
        g.env.materialize(&g.map);
        phase(&initTimer, "world");
        g.hero = heromod.Hero.init(g.scene.shader);
        phase(&initTimer, "hero");
        g.warren = frogmod.Knot.init(g.scene.shader);
        g.line = archermod.Line.init(g.scene.shader);
        g.grief = ogremod.Grief.init(g.scene.shader);
        g.band = koboldmod.Warband.init(g.scene.shader);
        g.brood = broodmod.Brood.init(g.scene.shader);
        g.muster = warriormod.Muster.init(g.scene.shader);
        g.grove = rootedmod.Grove.init(g.scene.shader);
        g.cluster = shroommod.Cluster.init(g.scene.shader);
        g.warrens = delvermod.Warrens.init(g.scene.shader);
        g.rite = necromod.Rite.init(g.scene.shader);
        g.thicket = ravagermod.Thicket.init(g.scene.shader);
        g.ring = magemod.Ring.init(g.scene.shader);
        g.marsh = fenmod.Marsh.init(g.scene.shader);
        g.vigil = knightmod.Vigil.init(g.scene.shader);
        g.swarm = leechmod.Swarm.init(g.scene.shader);
        g.haunt = shademod.Haunt.init(g.scene.shader);
        g.chests = chestmod.Chests.init(g.scene.shader);
        g.folk = npcmod.Folk.init(g.scene.shader);
        // EVERY DEFAULTED FIELD ON `Game` MUST BE ASSIGNED HERE: it is built from `alloc.create`, so a struct
        // default never runs and the field comes up as the fill byte. Silent, and it has bitten twice.
        g.pack = .{};
        g.pack.load(g.scene.shader);
        g.pickups = .{};
        g.award = .{};
        g.day = .{};
        g.bootT = 0;
        g.bossK = 0;
        g.bossFrac = 0;
        g.spiritK = 0;
        g.spiritHp = 0;
        g.hourLit = std.math.nan(f32); // …and its guard, which as the fill byte would pin the light on frame one
        g.souls = soulsmod.Souls.init(g.scene.shader);
        phase(&initTimer, "foes");
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.clumpModel = koboldmod.clumpMesh(g.scene.shader);
        g.crockModel = archermod.crockMesh(g.scene.shader);
        g.venomModel = broodmod.venomMesh(g.scene.shader);
        g.fireArrowModel = archermod.fireArrowMesh(g.scene.shader);
        g.boltModel = heromod.boltMesh(g.scene.shader);
        g.emberModel = magemod.emberMesh(g.scene.shader);
        g.wispModel = shademod.wispMesh(g.scene.shader);
        g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
        g.shafts = [_]archermod.Arrow{.{}} ** MAX_SHAFTS;
        phase(&initTimer, "pools");
        g.editor = .{};
        phase(&initTimer, "editor");
        g.folkGen = g.editor.mapGen;
        g.rumble = .{};
        g.deathFade = 0;
        g.restRetro = [_]f32{0} ** gfx.RETRO_COUNT;
        g.probe = .{};
        g.npcPos = [_]rl.Vector3{mathx.zero3} ** npcmod.CAP;
        g.nNpcPos = 0;
        g.drawDt = 1.0 / 60.0;
        g.shelf = savemod.survey(saveMap(g));
        g.slot = 0;
        g.shotOwed = false;
        g.enterOut = 0;
        g.enterIn = 0;
        g.enterAct = null;
        beginGame(g);
    }
};

const SHOT_CLEAR: f32 = 0.02;

// THE BOOT SCREEN IS AN AERIAL PASS OVER THE WOOD (owner: aerial, scenic, trees, looking somewhat down,
// swooping) — not a turntable on the hero's shoulder. Nothing has been started when this is on screen, so
// there is no character to be looking at and no reason to be standing in a runway: what the title card wants
// behind it is the WORLD.
//
// **THE WHOLE PATH IS A PURE FUNCTION OF ONE CLOCK** (`bootCam`), which is what lets the harness photograph
// the exact framing the loop draws by handing it a time — where two copies of the arithmetic would be a shot
// of a framing nobody ever sees.

/// Where the pass is centred: deep in the WOOD (`zone: wood` runs west of x = -52 at 0.98 density), well off
/// the runway and well off the village, so what is under the lens is canopy.
const BOOT_AT_X: f32 = -104.0;
const BOOT_AT_Z: f32 = 18.0;
/// How far the look-at wanders about that centre. The drift is what makes it a PASS rather than a turntable:
/// the ground under the camera changes, so new trees keep arriving instead of the same ring going by.
const BOOT_DRIFT_R: f32 = 26.0;
const BOOT_DRIFT_RATE: f32 = 0.036; // rad/s on the drift's own circle — slower than the turn
/// …and how far above the ground the pass is AIMED. Off the terrain rather than a fixed Y, or the look-at
/// sinks into a hillside and the horizon rolls.
const BOOT_LOOK_UP: f32 = 6.0;

/// **THE PASS SWEEPS, IT DOES NOT ORBIT — AND THAT IS A LIGHTING DECISION, NOT A TASTE ONE.** `gfx.SUN_DIR`
/// puts the sun over the shoulder of a camera at yaw 53 and INTO THE LENS of one at 233, so a turntable spends
/// half its cycle looking at the shaded side of everything: the first pass came back at a mean background luma
/// of 24 of 255, which is not scenery, it is murk. Swept about the lit bearing instead, the canopy is front-lit
/// the whole way round and the motion is still a camera in flight.
const BOOT_YAW_MID: f32 = 53.0; // degrees — the sun's own over-the-shoulder bearing
const BOOT_YAW_SWEEP: f32 = 38.0; // …and how far either side of it the pass is allowed, which keeps 15..91
const BOOT_YAW_T: f32 = 41.0; // seconds for the sweep to go and come back — the slowest clock in the move
/// **LOOKING SOMEWHAT DOWN**, and this is the dial that says so: 0.44 rad is about 25 degrees under the
/// horizon, which keeps the horizon and its sky in the upper third while the canopy fills the rest. At 35 the
/// frame was all shaded crown and no distance — a map rather than a view.
pub const BOOT_PITCH: f32 = 0.44;
pub const BOOT_DIST: f32 = 46.0;
/// **THE SWOOP.** The pass rises and falls and pushes in and out on clocks SLOWER than the turn and prime to
/// each other, so the path never repeats on the beat the orbit does and the motion reads as flight rather
/// than as a mechanism. Amplitudes, and the periods in seconds.
const BOOT_SWOOP_PITCH: f32 = 0.17;
const BOOT_SWOOP_DIST: f32 = 9.0;
const BOOT_SWOOP_T: f32 = 17.0;
const BOOT_PUSH_T: f32 = 26.0;

/// WHERE THE PASS IS LOOKING at `t` seconds in — a slow drift about the wood's centre, laid on the ground it
/// is actually over.
fn bootLook(g: *const Game, t: f32) rl.Vector3 {
    const a = t * BOOT_DRIFT_RATE;
    // The two axes on different multiples, so the drift is a slow figure rather than a second circle.
    const x = BOOT_AT_X + mathx.cosf(a) * BOOT_DRIFT_R;
    const z = BOOT_AT_Z + mathx.sinf(a * 1.7) * BOOT_DRIFT_R * 0.7;
    return v3(x, g.env.groundAt(x, z) + BOOT_LOOK_UP, z);
}

/// …and the whole camera for that instant. ONE function, so the loop and the harness cannot frame it two
/// different ways.
pub fn bootCam(g: *Game, t: f32) void {
    g.rig.yaw = mathx.radians(BOOT_YAW_MID + BOOT_YAW_SWEEP * mathx.sinf(t * std.math.tau / BOOT_YAW_T));
    g.rig.pitch = BOOT_PITCH + BOOT_SWOOP_PITCH * mathx.sinf(t * std.math.tau / BOOT_SWOOP_T);
    g.rig.dist = BOOT_DIST + BOOT_SWOOP_DIST * mathx.sinf(t * std.math.tau / BOOT_PUSH_T + 1.1);
    // CENTRED, not `follow`: that one is the over-the-shoulder rig and its boom gives way to terrain, which
    // on a camera this high is a hard zoom every time a bank passes under it.
    g.rig.followCentred(bootLook(g, t));
}

fn beginGame(g: *Game) void {
    var start = mathx.ground(0, 4);
    plantActor(g, &start);
    g.hero.setSpawn(start, std.math.pi); // …and where a death returns him
    g.hero.souls = .{};
    g.hero.arm = .sword;
    g.hero.armAlt = .bell; // the BELL, not the bow: it is what the starting scroll is for
    g.hero.off = .shield;
    g.hero.offAlt = .wand;
    g.hero.spell = .bolt;
    g.hero.quick = .{};
    g.hero.quiver = .{};
    g.hero.worn = .{}; // A NEW GAME IS BARE-HANDED — an assigned field, the defaulted-field law

    g.hero.flasks = .{};
    g.day = .{};
    g.bossK = 0;
    g.bossFrac = 0;
    g.spiritK = 0;
    g.spiritHp = 0;
    g.bag = .{};
    g.award = .{};
    for (STARTING_KIT) |k| {
        g.bag.add(k, 1);
        g.award.markKnown(k);
    }
    g.tree = .{};
    applyTree(g); // the sheet and the perks FIRST: the respawn below sizes his bars off them
    g.hero.respawnNow();
    rehomeFoes(g, .blind);
    g.rest = .{};
    rehomeChests(g);
    armScript(g);
    clearQuivers(g);
    g.pack.clear(); // NOT `= .{}` — that struct holds the wolf's meshes, and the reset made it invisible
    g.deathFade = 0;
    g.restRetro = [_]f32{0} ** gfx.RETRO_COUNT;
    g.lock = null;
    g.lockBlind = 0;
    g.hook = null;
    g.shotOwed = false;
    g.hero.pose();
    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
    applyHour(g);
}

fn beginEnter(g: *Game, act: Enter) void {
    if (g.enterAct != null) return;
    g.enterAct = act;
    g.enterOut = ENTER_OUT;
    g.enterIn = 0;
}

fn enterNow(g: *Game, act: Enter) void {
    switch (act) {
        .fresh => |i| {
            beginGame(g);
            g.slot = i;
            g.menu.started();
        },
        .load => |i| {
            if (loadGame(g, i)) {
                g.slot = i;
                g.menu.started();
            } else {
                g.shelf.head[i] = null; // …and the row goes dead, so it cannot be pressed again
                std.debug.print("LOAD FAILED: {s} is not a save this build can read\n", .{savemod.path(i)});
            }
        },
        .map => |m| enterMap(g, m.path, m.at, m.facing),
    }
    g.enterIn = ENTER_IN;
}

fn enterMap(g: *Game, path: []const u8, at: rl.Vector3, facing: f32) void {
    worldfmt.loadOrPanic(path, &g.map);
    PLAY_HALF = playHalfOf(g.map.half); // before anything is placed against it
    g.env.uploadSoil(&g.map);
    g.env.uploadWater(&g.map);
    g.env.uploadHeight(&g.map);
    g.env.materialize(&g.map);
    g.hero.pos = inBounds(mathx.ground(at.x, at.z));
    g.hero.facing = facing;
    plantActor(g, &g.hero.pos); // …on the ground the NEW map sculpts under him, not the old one's
    g.hero.pos = g.env.resolveActor(g.hero.pos, HERO_R, g.hero.pos.y);
    g.hero.setSpawn(g.hero.pos, facing);
    rehomeFoes(g, .blind);
    rehomeChests(g);
    armScript(g);
    clearQuivers(g);
    g.pack.clear(); // a spirit does not follow him through a door — it is called again on the other side
    g.lock = null;
    g.lockBlind = 0;
    g.hook = null;
    g.hero.pose();
    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
    applyHour(g);
}

fn drawEnterFade(g: *const Game) void {
    const k = if (g.enterAct != null)
        1.0 - mathx.clampF(g.enterOut / ENTER_OUT, 0, 1) // going down…
    else
        mathx.clampF(g.enterIn / ENTER_IN, 0, 1); // …and coming back up
    if (k <= 0.002) return;
    rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), rgba(0, 0, 0, mathx.u8f(255.0 * k)));
}

/// One frame of the cut, wherever the loop happens to be. Returns whether the world is still held behind it.
fn tickEnter(g: *Game, dt: f32) void {
    if (g.enterAct) |act| {
        g.enterOut = mathx.maxF(0, g.enterOut - dt);
        if (g.enterOut > 0) return;
        g.enterAct = null;
        enterNow(g, act);
        return;
    }
    g.enterIn = mathx.maxF(0, g.enterIn - dt);
}

fn saveMap(g: *const Game) []const u8 {
    _ = g; // one map today; the parameter is where a per-`Game` current map goes when there is more than one
    return worldfmt.startMap();
}

fn slotOf(g: *Game) savemod.Slot {
    return .{
        .hero = &g.hero,
        .bag = &g.bag,
        .tree = &g.tree,
        .souls = &g.souls,
        .day = &g.day,
        .trig = &g.trig,
        .chests = &g.chests,
        .pickups = &g.pickups,
        .award = &g.award,
        .map = saveMap(g),
    };
}

fn loadGame(g: *Game, i: usize) bool {
    beginGame(g);
    if (!savemod.read(i, slotOf(g))) return false;
    applyTree(g);
    plantActor(g, &g.hero.pos); // …back onto the ground, in case the map has been sculpted under him
    g.hero.pose();
    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
    applyHour(g); // into both shaders and the shadow camera, before anything draws
    return true;
}

/// The foe groups written down ONCE — everything folded over this list picks up a new group for free.
const FoeGroup = struct {
    field: []const u8,
    kind: ?FoeKind,
    aggro: f32,
    /// Shouldered by the HERO. The ogre is not: he is too big to be walked out of the way.
    vsHero: bool = true,
    /// …and by these OTHER groups. DELIBERATELY ONE-WAY, or two bodies each half-correct and jitter.
    vs: []const []const u8 = &.{},
};
pub const FOE_GROUPS = [_]FoeGroup{
    .{ .field = "warren", .kind = .toad, .aggro = frogmod.AGGRO_R, .vs = &.{"thicket"} },
    .{ .field = "line", .kind = .archer, .aggro = archermod.AGGRO_R, .vs = &.{"warren"} },
    .{ .field = "grief", .kind = .ogre, .aggro = ogremod.AGGRO_R, .vsHero = false },
    .{ .field = "band", .kind = null, .aggro = koboldmod.AGGRO_R },
    .{ .field = "brood", .kind = null, .aggro = broodmod.AGGRO_R },
    .{ .field = "muster", .kind = null, .aggro = warriormod.AGGRO_R, .vs = &.{"line"} },
    .{ .field = "haunt", .kind = .shade, .aggro = shademod.AGGRO_R, .vs = &.{ "warren", "line", "muster" } },
    .{ .field = "swarm", .kind = .leechfly, .aggro = leechmod.AGGRO_R },
    // A fixture: nothing shoulders it off its spot and it shoulders nothing, because it never moves.
    .{ .field = "grove", .kind = .rooted, .aggro = rootedmod.AGGRO_R, .vsHero = false },
    .{ .field = "cluster", .kind = .shroom, .aggro = shroommod.AGGRO_R, .vs = &.{"thicket"} },
    .{ .field = "warrens", .kind = .delver, .aggro = delvermod.AGGRO_R },
    .{ .field = "rite", .kind = .necromancer, .aggro = necromod.AGGRO_R, .vs = &.{ "line", "muster" } },
    // A PACK, and it shoulders the small things aside: a hound this size walks through a sporeling. **THE
    // ROW THAT YIELDS IS THE ROW THAT NAMES THE OTHER** — `vs` is who shoulders ME, so listed here the
    // 1.34 m hound was the one being shoved off its line by a knee-high mushroom.
    .{ .field = "thicket", .kind = .florid_ravager, .aggro = ravagermod.AGGRO_R },
    // It is small and it is squishy: everything on this list walks through it, and it walks through nothing.
    .{ .field = "ring", .kind = .mushroom_mage, .aggro = magemod.AGGRO_R },
    // A FIXTURE IN ITS POOL, and it is anchored the way the rooted is: nothing shoulders it off its bed and
    // it shoulders nothing, because it never travels.
    .{ .field = "marsh", .kind = .fen_lurker, .aggro = fenmod.AGGRO_R, .vsHero = false },
    .{ .field = "vigil", .kind = .bone_knight, .aggro = knightmod.AGGRO_R, .vsHero = false, .vs = &.{ "line", "muster" } },
};

const BLOW_GROUPS = [_][]const u8{
    "warren", "grief",  "line",    "band",    "muster", "haunt",
    "swarm",  "grove",  "cluster", "warrens", "vigil",  "brood",
    "rite",   "thicket", "ring",    "marsh",
};

comptime {
    // All three cross-checks below are O(groups^2) or worse over string compares — with sixteen groups the
    // default thousand branches is not enough to finish them.
    @setEvalBranchQuota(30000);
    if (BLOW_GROUPS.len != FOE_GROUPS.len) @compileError("game: BLOW_GROUPS and FOE_GROUPS disagree on how many groups there are");
    for (FOE_GROUPS) |gr| {
        var seen = false;
        for (BLOW_GROUPS) |b| {
            if (std.mem.eql(u8, b, gr.field)) seen = true;
        }
        if (!seen) @compileError("game: `" ++ gr.field ++ "` is in FOE_GROUPS but not in BLOW_GROUPS — " ++
            "give it its `update(...) |b| heroTakes(...)` call in `run` and name it here, or it will never land a blow");
    }
    for (BLOW_GROUPS) |b| {
        var seen = false;
        for (FOE_GROUPS) |gr| {
            if (std.mem.eql(u8, b, gr.field)) seen = true;
        }
        if (!seen) @compileError("game: BLOW_GROUPS names `" ++ b ++ "`, which is not a FOE_GROUPS field");
    }
    // **`vs` IS WHO SHOULDERS ME, AND IT IS ONE-WAY** — `settleGroup` pushes MY members out of THEIRS, so the
    // row that yields is the row that names the other. Written down in `FoeGroup.vs` and checked by nothing:
    // a pair that names each other is the jitter the field doc forbids, and getting the direction backwards
    // (the ravager listing the sporelings it was supposed to walk through) compiles and simply reads wrong.
    for (FOE_GROUPS) |gr| {
        for (gr.vs) |other| {
            if (std.mem.eql(u8, other, gr.field)) @compileError("game: `" ++ gr.field ++ "` shoulders itself");
            var known = false;
            for (FOE_GROUPS) |o| {
                if (!std.mem.eql(u8, o.field, other)) continue;
                known = true;
                for (o.vs) |back| {
                    if (std.mem.eql(u8, back, gr.field)) @compileError("game: `" ++ gr.field ++ "` and `" ++
                        other ++ "` each shoulder the other — `vs` is one-way, or both bodies half-correct and jitter");
                }
            }
            if (!known) @compileError("game: `" ++ gr.field ++ "` names `" ++ other ++ "` in `vs`, which is not a FOE_GROUPS field");
        }
    }
}

pub fn inCombat(g: *const Game) bool {
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).liveConst()) |*f| {
            if (foeFights(f, g.hero.pos, gr.aggro)) return true;
        }
    }
    return false;
}

fn foeFights(f: anytype, hero: rl.Vector3, aggro: f32) bool {
    if (!foemod.corporeal(f)) return false;
    return f.leash.roused() or mathx.distXZ(hero, f.pos) <= aggro;
}

test "A FIGHT IS ON while something is roused OR simply near, and is over when the last body stops" {
    var toad = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, 0.3);
    const near = v3(0, 0, frogmod.AGGRO_R - 1.0);
    const far = v3(0, 0, frogmod.AGGRO_R + 40.0);
    try std.testing.expect(foeFights(&toad, near, frogmod.AGGRO_R));
    try std.testing.expect(!foeFights(&toad, far, frogmod.AGGRO_R));

    toad.leash.provoke();
    try std.testing.expect(foeFights(&toad, far, frogmod.AGGRO_R));

    toad.debugKill();
    try std.testing.expect(toad.alive()); // still dissipating
    try std.testing.expect(!foeFights(&toad, near, frogmod.AGGRO_R));
}

test "A BUTTON IS NAMED ONCE — the press the loop reads IS the letter the cribs draw" {
    try std.testing.expectEqual(INTERACT_PAD, hud_.padOf(hud_.BTN_INTERACT));
    try std.testing.expectEqual(QUICK_PAD, hud_.padOf(hud_.BTN_QUICK));
    const named = [_]hud_.PadBtn{ hud_.BTN_INTERACT, hud_.BTN_CONFIRM, hud_.BTN_BACK, hud_.BTN_QUICK };
    for (named, 0..) |a, i| {
        for (named[i + 1 ..]) |b| try std.testing.expect(hud_.padOf(a) != hud_.padOf(b));
    }
    try std.testing.expectEqual(rl.KeyboardKey.y, INTERACT_KEY);
}

test "ONE BUTTON, ONE ORDER — and the enum's own order is what the press goes through" {
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(Reach.souls)); // the walk back for souls outranks all
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.talk)); // TAKE BEATS TALK (owner's)
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.chest));
    inline for (@typeInfo(Reach).@"enum".fields) |f| _ = @as(Reach, @enumFromInt(f.value)).prompt();
}

test "the ranges the fight is judged at are each GROUP'S OWN, never one figure for the field" {
    try std.testing.expect(frogmod.AGGRO_R < archermod.AGGRO_R);
    inline for (FOE_GROUPS) |gr| try std.testing.expect(gr.aggro > 0);
}

const Sighted = enum { blind, seen };

fn rehomeFoes(g: *Game, sighted: Sighted) void {
    inline for (FOE_GROUPS) |f| {
        @field(g, f.field).reset(&g.map);
        if (sighted == .blind) {
            for (@field(g, f.field).live()) |*x| x.leash.blindNow();
        }
    }
}

fn eachTarget(g: *const Game, ctx: anytype, comptime visit: anytype) void {
    inline for (FOE_GROUPS) |gr| {
        visit(ctx, @field(g, gr.field).liveConst(), gr.kind);
        // The extra list answers for its own members' kinds (`Sac.kind()`), so the row carries none.
        if (comptime @hasDecl(@FieldType(Game, gr.field), "liveExtraConst")) {
            visit(ctx, @field(g, gr.field).liveExtraConst(), @as(?FoeKind, null));
        }
    }
}

fn groupCap(comptime field: []const u8) usize {
    const G = @FieldType(Game, field);
    const Member = @typeInfo(@typeInfo(@TypeOf(G.live)).@"fn".return_type.?).pointer.child;
    for (@typeInfo(G).@"struct".fields) |f| {
        const info = @typeInfo(f.type);
        if (info == .array and info.array.child == Member) return info.array.len;
    }
    @compileError("game: " ++ field ++ " has no [_]" ++ @typeName(Member) ++ " to size a position snapshot from");
}

const FOE_CAP = blk: {
    var w: usize = 0;
    for (FOE_GROUPS) |f| w = @max(w, groupCap(f.field));
    break :blk w;
};

const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

const Stick = struct { x: f32 = 0, y: f32 = 0, mag: f32 = 0 };

fn stickRadial(x: f32, y: f32, dz: f32, curve: f32) Stick {
    const m = @sqrt(x * x + y * y);
    if (m < dz) return .{};
    // Clamped, because a real pad reports past 1 on the diagonals (a square gate on a round stick).
    const t = mathx.minF((m - dz) / (1.0 - dz), 1.0);
    return .{ .x = x / m, .y = y / m, .mag = std.math.pow(f32, t, curve) };
}

test "a radial stick keeps the thumb's ANGLE and does not favour the cardinals" {
    const ang = 0.26;
    const s = stickRadial(mathx.cosf(ang), mathx.sinf(ang), LOOK_DEADZONE, 1.0);
    try std.testing.expectApproxEqAbs(ang, std.math.atan2(s.y, s.x), 1e-5);
    const diag = stickRadial(0.7071, 0.7071, LOOK_DEADZONE, 1.0);
    const card = stickRadial(1.0, 0.0, LOOK_DEADZONE, 1.0);
    try std.testing.expectApproxEqAbs(card.mag, diag.mag, 1e-4);
    try std.testing.expectEqual(@as(f32, 0), stickRadial(0.05, -0.05, LOOK_DEADZONE, 1.0).mag);
    try std.testing.expectApproxEqAbs(@as(f32, 1), stickRadial(1.0, 1.0, LOOK_DEADZONE, 1.0).mag, 1e-4);
}

test "A DRIFTING STICK CANNOT CLAIM THE CAMERA — the two look thresholds are not the same number" {
    try std.testing.expect(LOOK_CLAIM > LOOK_DEADZONE);
    const WORN_STICK_REST: f32 = 0.25;
    try std.testing.expect(LOOK_CLAIM > WORN_STICK_REST);
    try std.testing.expect(LOOK_CLAIM < 0.7);
    const drift = stickRadial(WORN_STICK_REST, 0, LOOK_DEADZONE, LOOK_CURVE);
    try std.testing.expect(drift.mag < 0.10);
    try std.testing.expectEqual(@as(f32, 0), stickRadial(0, 0, LOOK_DEADZONE, LOOK_CURVE).mag);
}

test "the look curve is fine near centre and still reaches full rate at the rim" {
    try std.testing.expectApproxEqAbs(@as(f32, 1), stickRadial(1.0, 0.0, LOOK_DEADZONE, LOOK_CURVE).mag, 1e-4);
    const half = stickRadial(0.5 * (1.0 - LOOK_DEADZONE) + LOOK_DEADZONE, 0.0, LOOK_DEADZONE, LOOK_CURVE);
    try std.testing.expect(half.mag < 0.5);
    try std.testing.expect(half.mag > 0.2);
}

fn gatherMove() Move {
    const sprint = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift) or padDown(hud_.padOf(hud_.BTN_BACK));
    if (rl.isGamepadAvailable(PAD)) {
        const s = stickRadial(
            rl.getGamepadAxisMovement(PAD, .left_x),
            rl.getGamepadAxisMovement(PAD, .left_y),
            STICK_DEADZONE,
            1.0,
        );
        if (s.mag > 0.001) {
            const sp = if (sprint) SPRINT_SPEED else s.mag * RUN_SPEED;
            return .{ .fx = s.x, .fz = -s.y, .speed = sp }; // stick up (−y) = forward
        }
    }
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

fn sprintingMove(mv: Move) bool {
    return mv.speed > RUN_SPEED + 0.01 and (mv.fx * mv.fx + mv.fz * mv.fz) > 1e-6;
}

/// The knee on the H=1.8 rig (0.285·H).
const WADE_KNEE: f32 = 0.50;
const WADE_DEEP: f32 = envmod.WADE_MAX;
const WADE_SLOWEST: f32 = 0.8;

const STARTING_KIT = [_]item.Kind{
    .spirit_scroll_wolf,
};

comptime {
    std.debug.assert(@abs(envmod.WADE_MAX - 0.760 * heromod.H) < 0.005);
    std.debug.assert(envmod.HERO_R_PIN == foemod.HERO_R);
}

fn wadeDrag(g: *const Game) f32 {
    return wadeDragAt(g.env.wadeDepth(g.hero.pos.x, g.hero.pos.z));
}

test "wading costs the run first and never roots him" {
    try std.testing.expectEqual(@as(f32, 1.0), wadeDragAt(0.2));
    try std.testing.expect(wadeDragAt(WADE_DEEP) * WALK_SPEED < WALK_SPEED);
    try std.testing.expect(wadeDragAt(WADE_DEEP * 3) * WALK_SPEED > 0.1);
    try std.testing.expect(wadeDragAt(0.7) > wadeDragAt(0.9));
}

fn wadeDragAt(d: f32) f32 {
    if (d <= WADE_KNEE) return 1.0;
    return mathx.lerpF(1.0, WADE_SLOWEST, mathx.smoothstep(WADE_KNEE, WADE_DEEP, d));
}

fn markSwing(f: anytype, hero: rl.Vector3) f32 {
    var worst: f32 = 0;
    var i: u32 = 0;
    while (i < 300) : (i += 1) {
        _ = f.update(1.0 / 60.0, hero, PLAY_HALF, .{});
        worst = @max(worst, mathx.distXZ(f.lockPoint(), f.pos));
    }
    return worst;
}

// The egg sac is deliberately absent: one membrane on the ground with no part that moves on its own.
test "THE MARK RIDES THE BODY, on every creature that has one" {
    const hero = v3(0, 0, 1.7); // inside every notice ring in the game
    const MIN: f32 = 0.02; // metres off the axis — a fixed mark gives zero

    var toad = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&toad, hero) > MIN);
    var bowman = archermod.Archer.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&bowman, hero) > MIN);
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&giant, hero) > MIN);
    var zerk = koboldmod.Kobold.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&zerk, hero) > MIN);
    var mother = broodmod.Spider.spawnAs(.mother, mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&mother, hero) > MIN);
    var boards = warriormod.Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&boards, hero) > MIN);
    var ghost = shademod.Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&ghost, hero) > MIN);
    var cap = shroommod.Shroom.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&cap, hero) > MIN);
    var knight = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(markSwing(&knight, hero) > MIN);
}

const Chase = struct { turned: ?f32, out: f32, gap: f32 };
fn chase(f: anytype, lead: f32, secs: f32) Chase {
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var hero = v3(0, 0, 0.5);
    while (t < secs) : (t += dt) {
        hero.z += (if (t < secs * 0.5) lead else heromod.SPRINT_SPEED) * dt;
        f.leash.noteSeen();
        _ = f.update(dt, hero, PLAY_HALF, .{});
        if (f.leash.goingHome()) {
            return .{ .turned = t, .out = mathx.distXZ(f.pos, f.home), .gap = mathx.distXZ(f.pos, hero) };
        }
    }
    return .{ .turned = null, .out = mathx.distXZ(f.pos, f.home), .gap = mathx.distXZ(f.pos, hero) };
}

test "A SPIRIT'S JAWS MUST REACH INTO WHAT IT IS SET ON — the BOTTOM of a giant's sphere is a window she keeps falling out of" {
    var w = wolfmod.Wolf.spawn(mathx.zero3, 0);
    w.pose();
    const rest = w.jawPoint().y - w.pos.y + 0.20 * w.scale; // the teeth, plus the blade's own radius
    // …AND THE SAME MEASUREMENT AT THE TOP OF THE POUNCE, which is the one that has to clear anything: the
    // blade is only live across the strike, and the leap is what the strike is thrown off (owner: she has to
    // jump and reach higher). Posed rather than derived — the lift and the nose-up are two contributions and
    // solving them by hand is how the number and the animation part company.
    w.stagePounce(1.0);
    const full = w.jawPoint().y - w.pos.y + 0.20 * w.scale;
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    var snag = rootedmod.Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    var plate = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    std.debug.print("\n  wolf teeth reach {d:.2} m standing, {d:.2} m at a full pounce\n", .{ rest, full });
    try std.testing.expect(full > rest + 0.4); // the leap is a LEAP, not a hop with a new name
    // THE TWO ENDS OF THE DIAL ARE WHAT `pounceFor` INTERPOLATES, and they are written down in `wolf.zig` where
    // it can read them. Measured here, because both come out of the posed rig and adding the lift and the
    // nose-up together by hand is exactly how a number and an animation part company.
    try std.testing.expectApproxEqAbs(wolfmod.TEETH_REST, rest, 0.04);
    try std.testing.expectApproxEqAbs(wolfmod.TEETH_POUNCE, full, 0.04);

    inline for (.{ .{ "ogre", &giant }, .{ "rooted", &snag }, .{ "knight", &plate } }) |row| {
        const f = row[1];
        const mid = f.centerWorld().y - f.pos.y;
        const r = f.hurtRadius();
        const floor = mid - r;
        const held = f.bodyR() + w.bodyR();
        const trigger = wolfmod.triggerR(f.bodyR()); // the gate as `update` actually asks it
        // …AND THE LEAP THIS BODY IS ACTUALLY WORTH (`wolf.pounceFor`), never the full one: a pounce sized for
        // a giant's chest sails clean over a snag, which is the same complaint one creature along.
        w.stagePounce(wolfmod.pounceFor(mid));
        const jaw = w.jawPoint().y - w.pos.y + 0.20 * w.scale;
        // HOW WIDE THE SPHERE IS AT THE HEIGHT SHE ACTUALLY BITES AT — the window her snout has to find, and
        // the number that says whether "reachable" means anything. Grazing the floor it is nearly zero.
        const dy = @abs(mid - jaw);
        const window: f32 = if (dy >= r) 0 else @sqrt(r * r - dy * dy);
        std.debug.print("  {s}: sphere {d:.2}..{d:.2} centre {d:.2} | pounce {d:.2}, teeth at {d:.2} ({d:.2} into it), window {d:.2} m against a hold of {d:.2}\n", .{
            row[0], floor, mid + r, mid, wolfmod.pounceFor(mid), jaw, jaw - floor, window, held,
        });
        try std.testing.expect(held < trigger);
        // **NOT MERELY REACHABLE — REACHABLE WITH ROOM, ON BOTH SIDES.** `floor < jaw` was the old bar and every
        // one of them passed it while she bit air, because a sphere is a point at its floor; and a leap that
        // clears the top of a low one fails the same way from above.
        try std.testing.expect(@abs(mid - jaw) <= (1.0 - wolfmod.POUNCE_INTO) * r);
        // …and the window she has to find has to be worth more than the collider holding her out of it.
        try std.testing.expect(window > held * 0.55);
    }
}

test "THE BERSERKER IS THE FASTEST THING ON FOOT — and he closes at a RUN, not a stroll" {
    const zerk = koboldmod.Kobold.spawnAs(.berserker, mathx.zero3, 0, 1.0, 0.3);
    const far = koboldmod.AGGRO_R * 0.9; // inside his world: past it he is drifting home, not charging
    const charge = zerk.approachSpeed(far);
    std.debug.print("\n  berserker charges at {d:.2} m/s (hero runs {d:.2}, sprints {d:.2})\n", .{
        charge, heromod.RUN_SPEED, heromod.SPRINT_SPEED,
    });
    inline for (.{ warriormod.Role.shieldman, warriormod.Role.greatsword }) |role| {
        var w = warriormod.Warrior.spawnAs(role, mathx.zero3, 0, 1.0, 0.3);
        const skel = w.approachSpeed(warriormod.AGGRO_R);
        std.debug.print("  {s} charges at {d:.2} m/s\n", .{ @tagName(role), skel });
        try std.testing.expect(charge > skel);
    }
    try std.testing.expect(charge > heromod.RUN_SPEED);
    try std.testing.expect(charge < heromod.SPRINT_SPEED);
    try std.testing.expect(zerk.approachSpeed(0.0) < charge);
    try std.testing.expect(zerk.approachSpeed(koboldmod.AGGRO_R * 0.5) > heromod.RUN_SPEED);
    try std.testing.expect(zerk.approachSpeed(koboldmod.AGGRO_R + 2.0) < heromod.RUN_SPEED);
    inline for (.{ koboldmod.Role.priest, koboldmod.Role.slinger }) |role| {
        const k = koboldmod.Kobold.spawnAs(role, mathx.zero3, 0, 1.0, 0.3);
        try std.testing.expect(k.approachSpeed(far) < heromod.RUN_SPEED);
    }
}

test "NOTHING CHASES FOREVER — every creature turns round at its own tether, not five times past it" {
    const SLACK: f32 = 1.5;
    var toad = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, 0.3);
    var bowman = archermod.Archer.spawn(mathx.zero3, 0, 1.0, 0.3);
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    var zerk = koboldmod.Kobold.spawn(mathx.zero3, 0, 1.0, 0.3);
    var boards = warriormod.Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    var ghost = shademod.Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    var cap = shroommod.Shroom.spawn(mathx.zero3, 0, 1.0, 0.3);
    var knight = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    inline for (.{
        .{ &toad, frogmod.AGGRO_R },
        .{ &bowman, archermod.AGGRO_R },
        .{ &giant, ogremod.AGGRO_R },
        .{ &zerk, koboldmod.AGGRO_R },
        .{ &boards, warriormod.AGGRO_R },
        .{ &ghost, shademod.AGGRO_R },
        .{ &cap, shroommod.AGGRO_R },
        .{ &knight, knightmod.AGGRO_R },
    }) |row| {
        const c = chase(row[0], heromod.WALK_SPEED, 90.0);
        try std.testing.expect(c.turned != null);
        try std.testing.expect(c.out <= foemod.leashR(row[1]) * SLACK);
    }
    var mother = broodmod.Spider.spawnAs(.mother, mathx.zero3, 0, 1.0, 0.3);
    const m = chase(&mother, heromod.WALK_SPEED, 90.0);
    try std.testing.expect(m.out < foemod.leashR(broodmod.AGGRO_R));
    var fly = leechmod.Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    const f = chase(&fly, heromod.WALK_SPEED, 90.0);
    try std.testing.expect(f.turned != null);
    try std.testing.expect(f.turned.? < 45.0 + LEASH_LETGO);
}
/// The sprint in `chase` starts at the halfway mark; this is how long after it a creature may still be coming.
const LEASH_LETGO: f32 = foemod.LEASH_CALM + 1.5;

test "STEERING IS ALL-OR-NOTHING PER CREATURE — the field and the question that stamps it cannot part company" {
    inline for (FOE_GROUPS) |gr| {
        const Ret = @typeInfo(@TypeOf(@FieldType(Game, gr.field).live)).@"fn".return_type.?;
        const M = @typeInfo(Ret).pointer.child;
        try std.testing.expectEqual(@hasField(M, "nav"), @hasDecl(M, "navWant"));
        if (comptime @hasField(M, "nav")) try std.testing.expect(@hasDecl(M, "airborne"));
    }
    try std.testing.expect(!@hasField(leechmod.Leechfly, "nav"));
    try std.testing.expect(!@hasField(rootedmod.Rooted, "nav"));
    try std.testing.expect(@hasField(wolfmod.Wolf, "nav") and @hasDecl(wolfmod.Wolf, "navWant"));
}

test "THE JUMP IS SIZED AGAINST THE TERRAIN IT EXISTS TO CROSS, not against a number that looked right" {
    try std.testing.expect(heromod.JUMP_APEX > 3.0 * worldfmt.HEIGHT_STEP);
    try std.testing.expect(heromod.JUMP_APEX > envmod.STEP_UP);
    try std.testing.expect(heromod.JUMP_APEX < 6.0 * worldfmt.HEIGHT_STEP);
    try std.testing.expect(SPRINT_SPEED * heromod.JUMP_AIR > heromod.ROLL_DIST);
}

fn standHeight(f: anytype) f32 {
    return f.topWorld().y - f.pos.y;
}

test "ONLY SOMETHING THAT TOWERS TILTS THE LENS UP — everything else is framed flat" {
    const giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    const snag = rootedmod.Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    const knight = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    for ([_]f32{ standHeight(&giant), standHeight(&snag), standHeight(&knight) }) |h| {
        try std.testing.expect(h >= LOCK_TILT_TALL);
    }
    const toad = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, 0.3);
    const bowman = archermod.Archer.spawn(mathx.zero3, 0, 1.0, 0.3);
    const zerk = koboldmod.Kobold.spawn(mathx.zero3, 0, 1.0, 0.3);
    const boards = warriormod.Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    const ghost = shademod.Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const cap = shroommod.Shroom.spawn(mathx.zero3, 0, 1.0, 0.3);
    const mother = broodmod.Spider.spawnAs(.mother, mathx.zero3, 0, 1.0, 0.3);
    for ([_]f32{
        standHeight(&toad),  standHeight(&bowman), standHeight(&zerk),   standHeight(&boards),
        standHeight(&ghost), standHeight(&cap),    standHeight(&mother),
    }) |h| {
        try std.testing.expect(h < LOCK_TILT_TALL);
    }
    var fly = leechmod.Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(standHeight(&fly) < LOCK_TILT_TALL);
    var t: f32 = 0;
    var high: f32 = 0;
    while (t < 6.0) : (t += 1.0 / 60.0) {
        _ = fly.update(1.0 / 60.0, v3(0, 0, 1.6), PLAY_HALF, .{});
        high = @max(high, standHeight(&fly));
    }
    try std.testing.expect(high >= LOCK_TILT_TALL);
}

test "A GIANT ONLY BRINGS THE LENS DOWN WHEN IT IS ON TOP OF YOU, and it arrives smoothly" {
    const OGRE: f32 = 4.4; // comfortably past LOCK_TILT_TALLER
    const share = struct {
        fn at(rise: f32, flat: f32) f32 {
            const tall = mathx.smoothstep(LOCK_TILT_TALL, LOCK_TILT_TALLER, rise);
            const near = 1.0 - mathx.smoothstep(LOCK_TILT_NEAR, LOCK_TILT_FAR, flat);
            return tall * near;
        }
    }.at;

    try std.testing.expectApproxEqAbs(@as(f32, 1), share(OGRE, LOCK_TILT_NEAR - 1), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), share(OGRE, LOCK_TILT_FAR + 1), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), share(2.4, 1.0), 1e-4);

    var prev = share(OGRE, LOCK_TILT_FAR + 4);
    var d = LOCK_TILT_FAR + 4;
    while (d > 0) : (d -= 0.05) {
        const s = share(OGRE, d);
        try std.testing.expect(s >= prev - 1e-4); // monotone: closing never gives the tilt BACK
        try std.testing.expect(s - prev < 0.05);
        prev = s;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1), prev, 1e-4);
}

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

fn plantActor(g: *const Game, pos: *rl.Vector3) void {
    pos.y = g.env.groundAt(pos.x, pos.z);
}

pub fn envGroundAt(e: *const envmod.Env, x: f32, z: f32) f32 {
    return e.groundAt(x, z);
}

fn snapshotPos(foes: anytype, out: []rl.Vector3) void {
    for (foes, 0..) |*f, i| {
        if (i >= out.len) return;
        out[i] = f.pos;
    }
}

fn gateTerrain(g: *const Game, foes: anytype, was: []const rl.Vector3) void {
    const T = @typeInfo(@TypeOf(foes)).pointer.child;
    for (foes, 0..) |*f, i| {
        if (i >= was.len) continue;
        if (comptime @hasDecl(T, "alive")) {
            if (!f.alive()) continue;
        }
        if (comptime @hasDecl(T, "airborne")) {
            if (f.airborne()) continue;
        }
        const dx = f.pos.x - was[i].x;
        const dz = f.pos.z - was[i].z;
        const d = @sqrt(dx * dx + dz * dz);
        if (d < 1e-5) continue;
        const stepped = g.env.walkStep(was[i], v3(dx / d, 0, dz / d), d);
        f.pos.x = stepped.x;
        f.pos.z = stepped.z;
    }
}

fn gateHeroWater(g: *Game, was: rl.Vector3) void {
    if (!g.env.deepRefused(was.x, was.z, g.hero.pos.x, g.hero.pos.z)) return;
    g.hero.pos.x = was.x;
    g.hero.pos.z = was.z;
}

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
        g.hero.pos = inBounds(g.env.walkStep(g.hero.pos, dir, moved));
    }
    if (faceYaw != null and !sprinting) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, faceYaw.?, TURN_RATE * dt);
    } else if (isMoving) {
        g.hero.facing = mathx.approachAngle(g.hero.facing, moveYaw.?, TURN_RATE * dt);
    }
    g.hero.update(dt, moved, speed, moveYaw);
    g.hero.pose();
}

fn moveHeroAir(g: *Game, dt: f32, mv: Move, faceYaw: ?f32) void {
    g.hero.steerAir(dt, if (mv.speed > 0.001) rollDir(g, mv) else mathx.zero3);
    const dir = mathx.headingDir(g.hero.airYaw);
    g.hero.pos = inBounds(g.env.flyStep(g.hero.pos, dir, g.hero.airSpeed * dt, g.hero.footY()));
    g.hero.updateAir(dt, faceYaw);
}

fn leanToGround(g: *Game, dt: f32) void {
    const face = mathx.headingDir(g.hero.facing);
    const want = heromod.slopeLean(g.env.slopeAlong(g.hero.pos.x, g.hero.pos.z, face));
    g.hero.slopePitch = mathx.approach(g.hero.slopePitch, want, heromod.SLOPE_LEAN_RATE * dt);
}

fn rollDir(g: *Game, mv: Move) rl.Vector3 {
    const fwd = g.rig.forwardXZ();
    const right = g.rig.rightXZ();
    const d = v3(fwd.x * mv.fz + right.x * mv.fx, 0, fwd.z * mv.fz + right.z * mv.fx);
    if (mathx.lenXZ(d) > 0.01) return d;
    return mathx.headingDir(g.hero.facing);
}

/// Off the VISUAL stance blend, so he dissolves over the ~0.1 s the bow takes to come up.
const AIM_FADE: f32 = 0.0;
fn heroFade(g: *const Game) f32 {
    return mathx.lerpF(1.0, AIM_FADE, mathx.clampF(g.hero.aimB, 0, 1));
}

fn drawCasters(g: *Game, cull: envmod.Cull) void {
    g.env.drawProps(cull);
    g.chests.draw();
    // The seam light is not a caster and `setFade` is the scene shader's — lit pass only (`drawGlow`'s own note).
    if (cull == .view) g.chests.drawGlow(&g.scene);
    // The roots are opaque WOOD, not FX — through here so they go through both passes and cast.
    g.hero.drawRoots();
    const fade = heroFade(g);
    const seeThrough = cull == .view and fade < 0.999;
    if (cull == .view) g.scene.setFlash(0.6 * g.hero.hurtFlash);
    if (!(seeThrough and fade <= 0.001)) {
        if (seeThrough) {
            g.scene.setFade(fade);
            rl.gl.rlDisableDepthMask();
        }
        g.hero.draw();
        if (seeThrough) {
            rl.gl.rlEnableDepthMask();
            g.scene.setFade(1);
        }
    }
    if (cull == .view) g.scene.setFlash(0);
    const flashPass: ?*gfx.Scene = if (cull == .view) &g.scene else null;
    inline for (FOE_GROUPS) |f| @field(g, f.field).draw(flashPass);
    g.folk.draw();
    // The spirit is thinned in the LIT pass only, so the sun pass still draws it solid and it CASTS.
    if (cull == .view) {
        g.scene.setFade(wolfmod.SPIRIT_FADE);
        g.pack.draw();
        g.scene.setFade(1);
    } else {
        g.pack.draw();
    }
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
    g.souls.setShader(sh);
    inline for (FOE_GROUPS) |f| @field(g, f.field).setShader(sh);
    g.chests.setShader(sh);
    g.folk.setShader(sh);
    g.pack.setShader(sh);
}

pub fn heroCenterY(g: *const Game) f32 {
    return g.hero.pos.y + HERO_CENTER_Y;
}

fn heroAimPoint(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, heroCenterY(g), g.hero.pos.z);
}

fn forwardPoint(g: *const Game, reach: f32) rl.Vector3 {
    return mathx.addV(heroAimPoint(g), mathx.scaleV(mathx.headingDir(g.hero.facing), reach));
}

fn spawnArrow(g: *Game, from: rl.Vector3, target: rl.Vector3) void {
    poolPut(g, archermod.launchArrow(from, target));
}

pub fn spawnClump(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), koboldmod.CLUMP_SPEED, koboldmod.CLUMP_HIT, true, .clump));
}

pub fn spawnVenom(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), broodmod.SPIT_SPEED, broodmod.M_SPIT_HIT, true, .venom));
}

pub fn spawnWisp(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), shademod.WISP_SPEED, shademod.WISP_HIT, true, .wisp));
}

/// **THE FIREBALL, LOBBED** — `loft` is the whole point of it: aimed flat a slow ball is a thing you sidestep
/// once and forget, and lobbed it arrives on a tall arc you have to read the LANDING of. Where it goes after
/// that is `archer.bouncesOf`'s business and nothing here has an opinion about it.
fn spawnEmber(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), magemod.EMBER_SPEED, magemod.EMBER_HIT, true, .emberball));
}

pub fn noteYank(g: *Game, from: rl.Vector3, pull: f32) void {
    g.hook = .{ .from = from, .pull = pull };
}

/// Through `env.walkStep` like his own movement, so it cannot haul him up a cliff or through a wall.
fn applyYank(g: *Game, out: combat.HitOutcome) void {
    const h = g.hook orelse return;
    g.hook = null;
    switch (out) {
        .blocked, .ignored => return,
        .taken, .guardBroken => {},
    }
    const dir = mathx.dirXZ(g.hero.pos, h.from);
    if (mathx.lenXZ(dir) < 1e-3) return;
    g.hero.pos = inBounds(g.env.walkStep(g.hero.pos, mathx.normV(dir), h.pull));
    g.rig.addShake(SHAKE_GUARD_BREAK);
    g.rumble.play(rumblemod.hit_heavy);
}

pub fn leechSip(g: *Game, h: combat.Hit) void {
    _ = g.hero.burn(h);
}

fn armScript(g: *Game) void {
    g.folk.reset(&g.map);
    g.trig.arm(&g.map);
    g.talk = .{};
    // The drop goes too: where it is standing means nothing in a map it was not left in.
    g.souls.clear();
}

fn rehomeChests(g: *Game) void {
    var sites: [chestmod.CAP]chestmod.Site = undefined;
    const n = g.env.chestSites(&sites);
    g.chests.reset(sites[0..n]);
    var glows: [pickupmod.CAP]pickupmod.Site = undefined;
    g.pickups.reset(glows[0..g.env.pickupSites(&glows)]);
    var fires: [restmod.CAP]restmod.Site = undefined;
    g.rest.reset(fires[0..g.env.restSites(&fires)]);
}

pub fn rehomeChestsForShot(g: *Game) void {
    rehomeChests(g);
}

pub fn stepPickupsForShot(g: *Game) void {
    g.pickups.update(SHOT_STEP, g.hero.pos);
    hidePickups(g);
}

/// `first` shows the card (an undiscovered kind), `again` toasts one (a known kind), `clear` takes it away.
pub const AwardShot = enum { first, again, clear };
pub fn awardForShot(g: *Game, k: item.Kind, how: AwardShot) void {
    switch (how) {
        .first => {
            g.award.seen[@intFromEnum(k)] = false;
            g.award.gain(k);
        },
        .again => {
            g.award.seen[@intFromEnum(k)] = true;
            g.award.gain(k);
        },
        .clear => g.award.clearPending(),
    }
}

pub fn drawAwardCardForShot(g: *Game) void {
    g.award.drawCard();
}

pub fn dismissAwardForShot(g: *Game) void {
    g.award.dismiss();
}

pub fn tickAwardForShot(g: *Game, secs: f32) void {
    g.award.update(secs);
}

fn clearFoes(g: *Game) void {
    inline for (FOE_GROUPS) |f| {
        const G = @FieldType(Game, f.field);
        if (comptime @hasDecl(G, "clear")) @field(g, f.field).clear() else @field(g, f.field).n = 0;
    }
}

pub fn clearFoesForShot(g: *Game) void {
    clearFoes(g);
}
pub fn rehomeFoesForShot(g: *Game) void {
    rehomeFoes(g, .seen);
}

pub fn shootShaftForShot(g: *Game, at: rl.Vector3, kind: combat.ArrowKind) void {
    const blow = heromod.arrowBlow(kind, true);
    putIn(&g.shafts, archermod.launchShaft(g.hero.nockWorld(), at, heromod.BOW_AIMED_SPEED, blow, false, heromod.arrowShot(kind)));
}
pub fn throwBoltForShot(g: *Game, at: rl.Vector3) void {
    // The BOLT'S blow, whatever the rod is currently turned to — the harness photographs this one spell and a
    // `castBlow` read here would come back null the moment a shot set the rod to the roots.
    launchBolt(g, at, false, combat.BOLT_HIT);
}

pub fn stepShaftsForShot(g: *Game, dt: f32) void {
    stepShafts(g, dt);
}
pub fn tickPoisonForShot(g: *Game, dt: f32) void {
    g.hero.poisonBy(g.brood.burn(dt, g.hero.pos));
    g.hero.poisonBy(g.cluster.spores(dt, g.hero.pos));
    _ = g.hero.tickPoison(dt);
}
/// Both quivers: the hero's shafts are in one and everything thrown AT him is in the other.
pub fn flyingPointForShot(g: *Game, kind: archermod.Shot) ?rl.Vector3 {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (ar.live and ar.shot == kind) return ar.pos;
        }
    }
    return null;
}

/// The ONE place `stepArrow`'s six arguments are gathered.
fn flyArrow(g: *Game, ar: *archermod.Arrow, dt: f32) void {
    ar.hit = false;
    archermod.stepArrow(ar, g.hero.pos, heroCenterY(g), g.env.groundAt(ar.pos.x, ar.pos.z), g.hero.iFramed(), arrowCover(g, ar, dt), dt);
}

pub fn stepAirForShot(g: *Game, dt: f32) void {
    moveHeroAir(g, dt, .{}, null);
}

pub fn stepArrowsForShot(g: *Game, dt: f32) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) continue;
        flyArrow(g, ar, dt);
        // **THE HARNESS STILL HAS TO SPEND THE ONE-FRAME FLAG** even though it deliberately skips the voice
        // and the embers (`emberBounces` — a shot must not play a sound). A one-frame flag with a reset on
        // only ONE of its two drive paths is `justDied`'s own hazard: left set it latches for the rest of
        // the run and every later frame reads a bounce that already happened.
        ar.bounced = false;
    }
}
pub fn clearShaftsForShot(g: *Game) void {
    clearQuivers(g);
}

/// Stage a ringing at a point through it, `u` in 0..1 — the harness has no frame loop to press a button across.
pub fn ringForShot(g: *Game, u: f32) void {
    g.hero.stageRing(u);
}

pub fn callWolfForShot(g: *Game, at: rl.Vector3, facing: f32) void {
    g.pack.clear();
    _ = g.pack.call(at, facing);
}

/// Speed and phase are what the pose is a function of, so setting the two and posing IS the frame.
pub fn poseWolfForShot(g: *Game, speed: f32, phase: f32) void {
    for (g.pack.live()) |*w| {
        w.speed = speed;
        w.speedS = speed;
        w.phase = phase;
        w.state = if (speed > 0.05) .move else .idle;
        plantActor(g, &w.pos);
        w.pose();
    }
}

pub fn poseWolfGatherForShot(g: *Game, u: f32) void {
    for (g.pack.live()) |*w| {
        plantActor(g, &w.pos);
        w.stageGather(u);
    }
}

/// …and the LEAP at its top, which is the frame the whole move is for.
pub fn poseWolfPounceForShot(g: *Game, amt: f32) void {
    for (g.pack.live()) |*w| {
        plantActor(g, &w.pos);
        w.stagePounce(amt);
    }
}

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
    rehomeFoes(g, .blind);
}
pub fn takeSlotShot(g: *Game) void {
    if (!g.shotOwed or g.rest.fade() > SHOT_CLEAR) return;
    g.shotOwed = false;
    _ = savemod.writeShot(g.slot);
}

pub fn drawBonfireForShot(g: *Game) void {
    restmod.drawScreen(&g.rest, &g.tree, g.hero.souls.total);
}
pub fn openChestForShot(g: *Game) bool {
    const had = g.chests.near != null;
    interact(g);
    return had;
}

/// The harness drives the panel itself: `tickTalk` reads live buttons and `triggerWorld` is private.
pub fn openTalkForShot(g: *Game, name: []const u8) bool {
    const dlg = g.map.findDialog(name) orelse return false;
    g.folk.update(SHOT_STEP, g.hero.pos, PLAY_HALF);
    const npc: ?usize = g.folk.near;
    const who: []const u8 = if (npc) |i| npcmod.nameOf(&g.map, g.folk.list[i].rec) else "";
    if (!g.talk.open(&g.map, &g.trig, dlg, who, npc)) return false;
    if (npc) |i| g.folk.list[i].talking = true;
    return true;
}
pub fn stepTalkForShot(g: *Game, in: dialogmod.Input) void {
    g.talk.update(&g.map, &g.trig, triggerWorld(g), SHOT_STEP, in);
    g.folk.update(SHOT_STEP, g.hero.pos, PLAY_HALF);
}
pub fn drawTalkForShot(g: *Game) void {
    g.talk.draw(&g.map, &g.trig, triggerWorld(g), talkPortrait(g));
}

fn talkPortrait(g: *Game) ?dialogmod.Portrait {
    const i = g.talk.npc orelse return null;
    if (i >= g.folk.n) return null;
    const p = &g.folk.list[i];
    return .{
        .scene = &g.scene,
        .face = p.facePoint(),
        .facing = p.facing,
        .ctx = @ptrCast(g),
        .drawFn = drawTalkingNpc,
    };
}
fn spiritPortrait(g: *Game) ?hud_.LivePortrait {
    const w = g.pack.firstConst() orelse return null;
    return .{
        .scene = &g.scene,
        .focus = w.facePoint(),
        // Off ITS OWN facing, the speaker's rule — three-quarters from the front wherever it is standing.
        .yaw = w.facing + mathx.radians(hud_.PORTRAIT_YAW),
        .pitch = hud_.PORTRAIT_PITCH,
        .dist = wolfmod.PORTRAIT_DIST,
        .fov = hud_.PORTRAIT_FOV,
        .ctx = @ptrCast(g),
        .drawFn = drawSpiritHead,
    };
}
fn drawSpiritHead(ctx: *const anyopaque) void {
    const g: *const Game = @ptrCast(@alignCast(ctx));
    g.pack.drawFirst();
}

fn drawTalkingNpc(ctx: *const anyopaque) void {
    const g: *const Game = @ptrCast(@alignCast(ctx));
    const i = g.talk.npc orelse return;
    g.folk.drawOne(i);
}
pub fn showSpiritToastForShot(g: *Game) void {
    g.spiritK = 1.0;
    g.spiritHp = if (g.pack.firstConst()) |w| w.vit.hpFrac() else 1.0;
}

pub fn stepFolkForShot(g: *Game, dt: f32) void {
    g.folk.update(dt, g.hero.pos, PLAY_HALF);
    for (g.folk.live()) |*p| plantActor(g, &p.pos);
}

const SHOT_STEP: f32 = @import("shots.zig").SHOT_DT;

const Reach = enum {
    souls,
    rest,
    pickup,
    talk,
    chest,

    /// Off `hud.BTN_INTERACT` rather than a letter, so a rebind moves the press and the glyph at once.
    fn prompt(self: Reach) hud_.Hint {
        return .{ .glyph = .{ .face = hud_.BTN_INTERACT }, .label = switch (self) {
            .souls => "Reclaim",
            .rest => "Rest",
            .pickup => "Take",
            .talk => "Speak",
            .chest => "Open",
        } };
    }
};

fn inReach(g: *const Game, r: Reach) bool {
    return switch (r) {
        .souls => g.souls.near,
        .rest => g.rest.near != null,
        .pickup => g.pickups.near != null,
        .talk => talkable(g),
        .chest => g.chests.near != null,
    };
}

fn reachable(g: *const Game) ?Reach {
    inline for (@typeInfo(Reach).@"enum".fields) |f| {
        const r: Reach = @enumFromInt(f.value);
        if (inReach(g, r)) return r;
    }
    return null;
}

fn interact(g: *Game) void {
    switch (reachable(g) orelse return) {
        .souls => reclaimSouls(g),
        .rest => _ = g.rest.begin(),
        .pickup => takePickup(g),
        .talk => _ = startTalk(g),
        .chest => openChest(g),
    }
}

fn ringBell(g: *Game) void {
    if (!g.hero.canRing()) return;
    // What he can call is what he is CARRYING — no second state that could disagree with the bag.
    if (g.bag.count(combat.scrollFor(g.hero.spirit)) == 0) {
        g.trig.say("The bell rings on nothing. You carry no scroll for it.");
        sfx.play(.refused);
        return;
    }
    if (!g.pack.room()) {
        g.trig.say("One already answers.");
        sfx.play(.refused);
        return;
    }
    if (g.hero.requestRing()) sfx.play(.wand_charge);
}

fn summonSpirit(g: *Game) void {
    const at = spiritSpot(g);
    if (!g.pack.call(at, g.hero.facing)) return;
    // At the SPIRIT rather than on the camera, so it tells him which shoulder to look over.
    sfx.world(.wolf_howl, at);
    g.rig.addShake(SHAKE_LAND);
    g.rumble.play(rumblemod.cast_throw);
}

const SUMMON_BEARING: f32 = 2.5; // radians off his facing
const SUMMON_R: f32 = 1.9;

fn spiritSpot(g: *Game) rl.Vector3 {
    const back = mathx.headingDir(g.hero.facing + SUMMON_BEARING);
    var at = mathx.addV(g.hero.pos, mathx.scaleV(back, SUMMON_R));
    at = inBounds(g.env.resolveActor(at, wolfmod.BODY_R, at.y));
    plantActor(g, &at); // …standing on the ground it arrived over, not on the datum
    return at;
}

fn rematerialize(g: *Game, w: *wolfmod.Wolf) void {
    const at = spiritSpot(g);
    w.reappear(at, g.hero.facing);
    sfx.world(.wolf_growl, at);
}

fn tickPack(g: *Game, dt: f32) void {
    if (g.pack.n == 0) return;
    for (g.pack.live()) |*w| {
        if (w.yelped) sfx.world(.wolf_hurt, w.pos);
        if (w.justDied) sfx.world(.wolf_die, w.pos);
    }
    for (g.pack.live()) |*w| if (w.lost()) rematerialize(g, w);
    for (g.pack.live()) |*w| {
        w.quarry = huntFor(g, w);
        if (w.navWant(g.hero.pos)) |want| markWay(g, &w.nav, w.pos, w.bodyR(), want) else w.nav.dir = null;
    }
    g.pack.update(dt, g.hero.pos, PLAY_HALF);
    var was: [combat.SUMMON_MAX]rl.Vector3 = undefined;
    for (g.pack.liveConst(), 0..) |*w, i| was[i] = w.wasAt; // …read off the creature, so the indices align
    gateTerrain(g, g.pack.live(), was[0..g.pack.n]);
    for (g.pack.live()) |*w| {
        if (w.bit) sfx.world(.wolf_bite, w.pos);
        if (w.growled) sfx.world(.wolf_growl, w.pos);
        w.jaw1 = w.jawPoint();
        const b = w.blade();
        if (b.active and !w.hitLatch and pierceFoes(g, b)) {
            w.hitLatch = true; // one bite, one body
            sfx.play(.hit_light);
        }
    }
}

fn quarryKey(kind: FoeKind, idx: usize) u32 {
    return (@as(u32, @intFromEnum(kind)) << 16) | @as(u32, @intCast(@min(idx, 0xFFFF)));
}

/// **HOW HIGH UP A BODY ITS MASS ACTUALLY IS**, off its own feet — what a spirit aims its leap at
/// (`wolf.Quarry.aim`). The hurt sphere's CENTRE and not its top: the top of an ogre is above anything with
/// four legs, and biting the middle of a thing is what a wolf does anyway.
fn aimOf(f: anytype) f32 {
    return f.centerWorld().y - f.pos.y;
}

fn huntFor(g: *const Game, w: *const wolfmod.Wolf) ?wolfmod.Quarry {
    const from = w.pos;
    if (mathx.distXZ(from, g.hero.pos) > wolfmod.RECALL_R) return null;
    const Ctx = struct {
        from: rl.Vector3,
        hero: rl.Vector3,
        /// What it walked in already committed to, and the answer if that body is still worth holding.
        held: u32,
        keep: ?wolfmod.Quarry = null,
        best: f32 = wolfmod.HUNT_R,
        at: ?wolfmod.Quarry = null,
        fn visit(self: *@This(), foes: anytype, kind: ?FoeKind) void {
            const T = @typeInfo(@TypeOf(foes)).pointer.child;
            for (foes, 0..) |*f, i| {
                if (!foemod.corporeal(f)) continue;
                if (disguised(f)) continue;
                if (comptime @hasDecl(T, "airborne")) {
                    if (f.airborne()) continue;
                }
                const key = quarryKey(memberKind(f, kind), i);
                const d = mathx.distXZ(self.from, f.pos);
                const out = mathx.distXZ(self.hero, f.pos);
                if (key == self.held and d <= wolfmod.HUNT_R * wolfmod.HUNT_KEEP and out <= wolfmod.TETHER_R * wolfmod.HUNT_KEEP) {
                    self.keep = .{ .at = f.pos, .r = f.bodyR(), .aim = aimOf(f), .key = key };
                    continue;
                }
                if (out > wolfmod.TETHER_R) continue;
                if (d >= self.best) continue;
                self.best = d;
                self.at = .{ .at = f.pos, .r = f.bodyR(), .aim = aimOf(f), .key = key };
            }
        }
    };
    var ctx = Ctx{ .from = from, .hero = g.hero.pos, .held = w.quarryKey() };
    eachTarget(g, &ctx, Ctx.visit);
    return ctx.keep orelse ctx.at;
}

fn spillSouls(g: *Game) void {
    if (bindingInBag(&g.bag)) |ring| {
        _ = g.bag.take(ring, 1);
        g.hero.quick.dropEmpty(&g.bag);
        sfx.play(.ring_snap);
        g.trig.say("The Soul Binding Ring snaps.");
        return;
    }
    const had = g.hero.souls.dropAll();
    g.souls.spill(g.hero.pos, had);
    if (had > 0) sfx.play(.souls_spill);
}

/// Asked of the ITEM rather than by kind (`item.bindsSouls`) — a second charm is a row in `item.zig`.
fn bindingInBag(bag: *const item.Bag) ?item.Kind {
    for (0..item.NK) |i| {
        const k: item.Kind = @enumFromInt(i);
        if (item.bindsSouls(k) and bag.count(k) > 0) return k;
    }
    return null;
}

fn reclaimSouls(g: *Game) void {
    const got = g.souls.take(g.hero.pos) orelse return;
    g.hero.souls.gain(got);
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

fn openChest(g: *Game) void {
    const got = g.chests.openNear(&g.map) orelse return;
    awardLoot(g, got.loot, got.at);
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

/// …AND THE GLOW, which is the box's own body of code with no lid on it.
fn takePickup(g: *Game) void {
    const got = g.pickups.takeNear(&g.map) orelse return;
    awardLoot(g, got.loot, got.at);
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

fn hidePickups(g: *Game) void {
    for (g.pickups.live(), 0..) |*p, i| g.env.setPickupDraw(i, p.sizeLeft(), p.spent());
}

fn awardLoot(g: *Game, loot: []const item.Kind, at: rl.Vector3) void {
    for (loot) |it| {
        g.bag.add(it, 1);
        g.award.gain(it);
    }
    if (loot.len > 0) sfx.world(.item_get, at);
}

fn triggerWorld(g: *const Game) trigmod.World {
    var w = trigmod.World{ .heroPos = g.hero.pos, .npcs = g.npcPos[0..g.nNpcPos] };
    const Ctx = struct {
        alive: *[@typeInfo(FoeKind).@"enum".fields.len]u32,
        fn visit(self: *const @This(), foes: anytype, kind: ?FoeKind) void {
            for (foes) |*f| {
                if (!f.alive() or f.dying()) continue;
                self.alive[@intFromEnum(memberKind(f, kind))] += 1;
            }
        }
    };
    var ctx = Ctx{ .alive = &w.alive };
    eachTarget(g, &ctx, Ctx.visit);
    return w;
}

fn billDeaths(g: *Game) void {
    const Ctx = struct {
        rt: *trigmod.Runtime,
        fn visit(self: *const @This(), foes: anytype, kind: ?FoeKind) void {
            const T = @typeInfo(@TypeOf(foes)).pointer.child;
            if (comptime !@hasField(T, "justDied")) return;
            for (foes) |*f| {
                if (f.justDied) self.rt.died(memberKind(f, kind));
            }
        }
    };
    var ctx = Ctx{ .rt = &g.trig };
    eachTarget(g, &ctx, Ctx.visit);
}

fn tickTriggers(g: *Game, dt: f32) void {
    g.nNpcPos = g.folk.positions(&g.map, &g.npcPos).len;
    billDeaths(g);
    const want = g.trig.tick(&g.map, triggerWorld(g), dt, g.talk.active() or g.rest.active()) orelse return;
    if (!g.talk.open(&g.map, &g.trig, want, "", null)) g.trig.dialogClosed();
}

fn startTalk(g: *Game) bool {
    if (g.talk.active()) return false;
    const i = g.folk.near orelse return false;
    const p = &g.folk.list[i];
    if (p.rec >= g.map.nnpcs) return false;
    const dlg = g.map.npcs[p.rec].dlg;
    if (dlg == worldfmt.NO_DIALOG) return false;
    if (!g.talk.open(&g.map, &g.trig, dlg, npcmod.nameOf(&g.map, p.rec), i)) return false;
    p.talking = true;
    return true;
}

fn talkable(g: *const Game) bool {
    const i = g.folk.near orelse return false;
    const rec = g.folk.list[i].rec;
    return rec < g.map.nnpcs and g.map.npcs[rec].dlg != worldfmt.NO_DIALOG;
}

fn tickTalk(g: *Game, dt: f32) void {
    const in = dialogmod.Input{
        .up = navPressed(.up),
        .down = navPressed(.down),
        .confirm = talkConfirmPressed(),
        .pick = digitPressed(),
    };
    g.talk.update(&g.map, &g.trig, triggerWorld(g), dt, in);
    if (g.talk.justClosed) {
        if (g.talk.npc) |i| {
            if (i < g.folk.n) g.folk.list[i].farewell();
        }
        g.folk.hush();
    }
    g.hero.pose();
    g.folk.update(dt, g.hero.pos, PLAY_HALF);
    g.rig.tickShake(dt);
    g.rumble.update(dt, false);
}

fn navPressed(dir: menumod.NavDir) bool {
    return menumod.navPressed(dir);
}
fn confirmPressed() bool {
    return menumod.confirmPressed();
}

const INTERACT_PAD: rl.GamepadButton = hud_.padOf(hud_.BTN_INTERACT);
const INTERACT_KEY: rl.KeyboardKey = .y;
const QUICK_PAD: rl.GamepadButton = hud_.padOf(hud_.BTN_QUICK);
const ARROW_KEY: rl.KeyboardKey = .u;
/// L2 ON THE KEYBOARD — see the L2 block in `run` for why the mouse cannot carry it.
const PARRY_KEY: rl.KeyboardKey = .c;
/// The keyboard cannot mirror the pad's A here — A is strafe-left — so the jump takes a key of its own.
const JUMP_PAD: rl.GamepadButton = hud_.padOf(hud_.BTN_JUMP);
const JUMP_KEY: rl.KeyboardKey = .v;

fn talkConfirmPressed() bool {
    return confirmPressed() or rl.isKeyPressed(INTERACT_KEY) or padPressed(INTERACT_PAD);
}

fn digitPressed() ?usize {
    const keys = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight, .nine };
    for (keys, 0..) |k, i| {
        if (rl.isKeyPressed(k)) return i + 1;
    }
    return null;
}

fn tickRest(g: *Game, dt: f32) void {
    g.rest.update(dt);
    if (g.rest.justEntered) {
        clearFoes(g);
        clearQuivers(g);
        g.lock = null;
        // The player's own filters stay (owner: amp up warmth only).
        g.restRetro = g.retro.values;
        g.retro.values[gfx.RF_SEPIA] = mathx.maxF(g.retro.values[gfx.RF_SEPIA], REST_WARMTH);
        const s = g.rest.seat();
        var at = s.pos;
        plantActor(g, &at);
        g.hero.sit(true, at, s.facing);
        if (savemod.write(g.slot, slotOf(g))) {
            g.shelf = savemod.survey(saveMap(g));
            g.shotOwed = true;
        } else {
            std.debug.print("SAVE FAILED: could not write {s}\n", .{savemod.path(g.slot)});
        }
    }
    if (g.rest.justLeft) {
        g.retro.values = g.restRetro;
        g.hero.sit(false, g.hero.pos, g.hero.facing);
        rehomeFoes(g, .blind);
    }
    if (g.rest.listening()) bonfireInput(g, dt);
    if (g.rest.scene()) {
        g.hero.poseRest(dt);
        restCamera(g);
    } else {
        g.hero.pose();
    }
    g.rig.tickShake(dt);
    g.rumble.update(dt, false);
}

fn bonfireInput(g: *Game, dt: f32) void {
    const onWheel = g.rest.screen == .tree;
    const nav = menumod.navFor(onWheel);
    if (nav(.up)) restmod.navigate(&g.rest, 0, -1);
    if (nav(.down)) restmod.navigate(&g.rest, 0, 1);
    if (nav(.left)) restmod.navigate(&g.rest, -1, 0);
    if (nav(.right)) restmod.navigate(&g.rest, 1, 0);
    // On the WHEEL the left stick is the thumb's own bearing rather than one of four — see `menu.stickPush`.
    if (menumod.stickPush(dt, onWheel)) |d| restmod.navigate(&g.rest, d.x, d.y);
    restmod.pan(&g.rest, menumod.stickPan(), dt);
    restmod.zoom(&g.rest, menumod.dpadZoom(), dt);
    if (menumod.confirmPressed()) bonfirePick(g, restmod.confirm(&g.rest, &g.tree, g.hero.souls.total));
    // Esc is routed by the loop rather than by `backPressed`, and at a fire the loop leaves it free.
    if (menumod.backPressed() or rl.isKeyPressed(.escape)) restmod.back(&g.rest);
}

/// The bonfire holds neither the souls nor the tree, so this is the one place either is moved by it.
fn bonfirePick(g: *Game, pick: restmod.Pick) void {
    switch (pick) {
        .none => {},
        .leave => g.rest.leave(),
        .take => |i| {
            const paid = g.tree.take(i, g.hero.souls.total) orelse return;
            g.hero.souls.total -= paid;
            g.hero.souls.shown = @floatFromInt(g.hero.souls.total); // it went DOWN: nothing rolls to a smaller number
            applyTree(g);
            sfx.play(.souls_take);
        },
        .wait => |u| {
            g.day.set(g.day.hour + daynight.hoursUntil(g.day.hour, u.hour()));
            applyHour(g);
            sfx.play(.menu_pick);
            g.rest.leave();
        },
    }
}

fn applyStow(g: *Game) void {
    g.env.stowed = g.hero.resting;
}

fn applyHour(g: *Game) void {
    // **AND ONLY WHEN THE HOUR HAS ACTUALLY MOVED.** The loop asks this every frame down every branch, and
    // what it costs is not small: TWO full `paletteAt` walks (a table search plus a fourteen-field blend
    // each), three `keyDir`-class solves for the caster, its reach and the two discs, and EIGHTEEN
    // `setShaderValue` calls — each of which is a `glUseProgram` and a `glUniform` at the driver. Under a
    // menu, at a bonfire, inside a conversation, in the editor and under a frozen clock (`--shot`) the
    // answer cannot have changed, and the guard is the value itself rather than a flag anybody has to
    // remember to raise. Nothing else writes these uniforms, so a skipped frame leaves them exactly right.
    if (g.day.hour == g.hourLit) return;
    g.hourLit = g.day.hour;
    g.scene.setHour(g.day.hour);
    g.sky.setHour(g.day.hour);
    sfx.setDaylight(daynight.dayAmt(g.day.hour));
}

pub fn bootCamForShot(g: *Game, t: f32) void {
    g.bootT = t;
    bootCam(g, t);
}

pub fn pinHourForShot(g: *Game, hour: f32) void {
    g.day.set(hour);
    g.day.freeze(true);
    applyHour(g);
}

const REST_WARMTH: f32 = 0.14;
const REST_PAN: f32 = 0.70;

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
    g.rig.cam.target = v3(s.pos.x + axis.x * 0.90, s.pos.y + 0.60, s.pos.z + axis.z * 0.90);
    g.rig.cam.up = v3(0, 1, 0);
    const fwd = mathx.subV(g.rig.cam.target, g.rig.cam.position);
    const right = mathx.normV(v3(-fwd.z, 0, fwd.x));
    const shove = mathx.scaleV(right, -REST_PAN);
    g.rig.cam.position = mathx.addV(g.rig.cam.position, shove);
    g.rig.cam.target = mathx.addV(g.rig.cam.target, shove);
}

fn poolPut(g: *Game, a: archermod.Arrow) void {
    putIn(&g.arrows, a);
}

fn putIn(pool: []archermod.Arrow, a: archermod.Arrow) void {
    var worst: usize = 0;
    for (pool, 0..) |*ar, i| {
        if (!ar.live) {
            ar.* = a;
            return;
        }
        const w = &pool[worst];
        if ((ar.stuck and !w.stuck) or (ar.stuck == w.stuck and ar.age > w.age)) worst = i;
    }
    pool[worst] = a;
}

fn looseShaft(g: *Game) void {
    const aimed = g.hero.shotAimed;
    const from = g.hero.nockWorld();
    const locked: ?rl.Vector3 = if (aimed) null else if (activeLock(g)) |li| foeLockPoint(g, li) else null;
    const target = locked orelse if (aimed) camAimPoint(g) else forwardPoint(g, heromod.BOW_AIM_REACH);
    const loft = locked != null or aimed;
    const speed: f32 = if (aimed) heromod.BOW_AIMED_SPEED else heromod.BOW_QUICK_SPEED;
    // The blow AND the shaft that carries it both come off what he actually drew (see `Hero.shotArrow`).
    putIn(&g.shafts, archermod.launchShaft(from, target, speed, g.hero.shotBlow(), loft, g.hero.shotShaft()));
    sfx.play(.bow_loose);
    g.rumble.play(rumblemod.swing_light);
}

fn releaseSpell(g: *Game) void {
    switch (g.hero.spell) {
        .bolt => throwBolt(g),
        .roots => castRoots(g),
        .rime => openBreath(g),
        .levin => strikeLevin(g),
        .siphon => drawSiphon(g),
        .lance => throwLance(g),
        .sunder => strikeSunder(g),
    }
}

/// **THE LANCE GOES THROUGH.** One segment out of the rod along his facing (or at the lock), handed to every
/// group ONCE as a `pierce` blade — the same door an arrow already comes through (`pierceFoes`), so every body
/// standing on the line earns its own flinch, flash, blood, threat and death without this knowing what any of
/// them is. A `pierce` blade sets no swing latch (`foe.strike`), so one cast is one blow per body by
/// construction rather than by a list of who has been hit.
fn throwLance(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const reach = combat.spellReach(g.hero.spell) orelse return;
    const from = g.hero.wandTipWorld();
    // AIMED AT THE LOCK IF THERE IS ONE, and the line runs THROUGH that mark rather than stopping on it — a
    // lance that ended at its target would be the levin with a longer arm.
    var dir = mathx.headingDir(g.hero.facing);
    if (activeLock(g)) |li| {
        const to_lock = mathx.dirXZ(from, foeLockPoint(g, li));
        if (mathx.lenXZ(to_lock) > 1e-4) dir = to_lock;
    }
    const to = v3(from.x + dir.x * reach, from.y, from.z + dir.z * reach);
    sfx.play(.wand_cast);
    g.rumble.play(rumblemod.cast_throw);
    g.rig.addShake(SHAKE_CAST);
    _ = pierceFoes(g, .{
        .active = true,
        .pierce = true,
        .r = combat.LANCE_R,
        .a = from,
        .b = to,
        .a0 = from,
        .b0 = to,
        .hit = blow,
    });
    g.hero.lanceBeam(from, to, g.hero.casts);
}

/// **SUNDER — the levin's exact plumbing at a quarter of its reach.** One named body, delivered through that
/// creature's own `tryHit` (`strikeOne`), so a shield that would stop it stops it: a guard-breaker the guard
/// cannot answer is not a guard-breaker, it is a rule.
fn strikeSunder(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const reach = combat.spellReach(g.hero.spell) orelse return;
    sfx.play(.wand_cast);
    const pick = strikeVictim(g, reach) orelse {
        // NOTHING THERE, AND HE STILL PAID FOR IT — the levin's own courtesy, on the same mark in front of him.
        g.hero.sunderBurst(strikeMissAt(g, reach), false, g.hero.casts);
        g.rumble.play(rumblemod.cast_throw);
        g.rig.addShake(SHAKE_CAST);
        return;
    };
    const hit = strikeOne(g, pick, blow) orelse return;
    g.hero.sunderBurst(v3(hit.at.x, g.env.groundAt(hit.at.x, hit.at.z), hit.at.z), true, g.hero.casts);
    // THE HEAVIEST STANCE THE ROD THROWS lands as the heaviest beat it throws — the levin's own pairing, and
    // this one arrives INSIDE reach rather than from across the room.
    g.rumble.play(rumblemod.hit_heavy);
    g.rig.addShake(SHAKE_ROOTS_BITE);
}

fn throwBolt(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const locked: ?rl.Vector3 = if (activeLock(g)) |li| foeLockPoint(g, li) else null;
    // Loft only against a REAL point, `looseShaft`'s rule: it is solved against the distance to the target.
    launchBolt(g, locked orelse forwardPoint(g, heromod.BOLT_REACH), locked != null, blow);
    sfx.play(.wand_cast);
    g.rumble.play(rumblemod.cast_throw);
    g.rig.addShake(SHAKE_CAST);
}

const ROOT_THROW: f32 = 7.0;
fn rootMark(g: *const Game) rl.Vector3 {
    if (activeLock(g)) |li| {
        const p = foePos(g, li);
        return v3(p.x, g.env.groundAt(p.x, p.z), p.z);
    }
    const d = mathx.headingDir(g.hero.facing);
    const x = g.hero.pos.x + d.x * ROOT_THROW;
    const z = g.hero.pos.z + d.z * ROOT_THROW;
    return v3(x, g.env.groundAt(x, z), z);
}

/// A row of `FOE_GROUPS` and an index, not a `FoeRef`: a ref only answers questions.
const RootPick = struct { group: usize, idx: usize };
fn rootVictim(g: *const Game, at: rl.Vector3) ?RootPick {
    const locked = activeLock(g);
    var pick: ?RootPick = null;
    var near: f32 = combat.ROOT_R;
    inline for (FOE_GROUPS, 0..) |f, gi| {
        for (@field(g, f.field).liveConst(), 0..) |*a, i| {
            if (!foemod.corporeal(a)) continue;
            if (locked) |l| if (l.idx == i and l.kind == memberKind(a, f.kind)) return .{ .group = gi, .idx = i };
            const d = mathx.distXZ(a.pos, at);
            if (d < near) {
                near = d;
                pick = .{ .group = gi, .idx = i };
            }
        }
    }
    return pick;
}

fn seedRoots(g: *Game, at: rl.Vector3) ?rl.Vector3 {
    const pick = rootVictim(g, at) orelse {
        g.hero.rootsBurst(at, false);
        return null;
    };
    var mark = at;
    inline for (FOE_GROUPS, 0..) |f, gi| {
        if (gi == pick.group) {
            const a = &@field(g, f.field).live()[pick.idx];
            a.root.grab();
            a.leash.provoke();
            mark = v3(a.pos.x, g.env.groundAt(a.pos.x, a.pos.z), a.pos.z);
        }
    }
    g.hero.rootsBurst(mark, true);
    return mark;
}

fn castRoots(g: *Game) void {
    const bit = seedRoots(g, rootMark(g)) != null;
    sfx.play(.wand_cast);
    g.rumble.play(if (bit) rumblemod.hit_heavy else rumblemod.cast_throw);
    g.rig.addShake(if (bit) SHAKE_ROOTS_BITE else SHAKE_CAST);
}

fn openBreath(g: *Game) void {
    sfx.play(.wand_cast);
    g.rumble.play(rumblemod.cast_throw);
    g.rig.addShake(SHAKE_CAST);
}

fn rimeBreathe(g: *Game, dt: f32) void {
    const apex = g.hero.breathMouth();
    const facing = g.hero.facing;
    inline for (FOE_GROUPS) |f| {
        for (@field(g, f.field).live()) |*a| {
            if (!foemod.corporeal(a)) continue;
            const d = mathx.distXZ(a.pos, apex);
            const r = a.bodyR();
            if (d - r > combat.RIME_REACH) continue;
            const to = mathx.dirXZ(apex, a.pos);
            if (mathx.lenXZ(to) > 1e-4) {
                const spread = if (d > r) combat.subtendedArc(r, d) else 180.0;
                if (!combat.withinArc(mathx.headingXZ(to), facing, combat.RIME_ARC + spread)) continue;
            }
            a.chill.breathe(dt);
            a.leash.provoke(); // breathed on IS being fought, whatever it was doing before
        }
    }
}

// THE TWO SORCERIES THAT DO NOT CROSS THE GROUND (`combat.LEVIN_*`, `combat.SIPHON_*`)
//
// **A STRIKE IS AIMED AT A BODY, NOT THROWN AT A PLACE.** The bolt is a stone the arrow pool carries and the
// roots are a hold seeded at a mark; these two land on ONE body on the frame they are cast. So there is no
// flight to intercept, and SIGHT is what stands in for one: a wall is still a wall (`env.sees`), and the
// picture is drawn down the blow's own segment so the flash cannot land where the blade did not.

/// How far above the crown the stroke starts, and how far it LEANS back toward him across the drop. The lean is
/// not decoration: `foe.strike` takes the shove and the facing snap off the segment's own XZ bearing, and a
/// plumb line has none — the fallback would then push the body along contact-toward-centre, which is nothing.
/// MEASURED, not picked: at 2.6 m above a skeleton's crown the stroke started at 4.5 m, which is off the top of
/// the frame at every distance this fight is actually fought at — the picture was above the camera.
const STRIKE_RISE: f32 = 1.7;
const STRIKE_LEAN: f32 = 0.9;
/// The swept capsule is only as fat as it has to be to be certain of a body already picked — it cannot miss and
/// is not allowed to reach a neighbour instead.
const STRIKE_R: f32 = 0.30;

/// THE ONE PLACE THE STROKE'S GEOMETRY IS WORKED OUT: the blow's swept segment AND the flash down it are these
/// same two points, handed to both.
fn strikeSegment(g: *const Game, at: rl.Vector3, topY: f32) [2]rl.Vector3 {
    var away = mathx.dirXZ(g.hero.pos, at);
    if (mathx.lenXZ(away) < 1e-4) away = mathx.headingDir(g.hero.facing);
    return .{ v3(at.x - away.x * STRIKE_LEAN, topY + STRIKE_RISE, at.z - away.z * STRIKE_LEAN), at };
}

/// **WHAT ONE IS AIMED AT** — the locked body, else the NEAREST inside the spell's own reach and a narrow arc of
/// his facing (`combat.STRIKE_ARC`). Reach is measured off the target's HIDE and not its centre, the range-gate
/// law, or the broad creatures are unstrikable at the distance the colliders hold you at. A lock is the aim, so
/// it skips the arc — but never the reach and never the sight: a body across the map or behind a wall is not a
/// target because the reticle is on it.
fn strikeVictim(g: *const Game, reach: f32) ?RootPick {
    const eye = heroEye(g);
    const locked = activeLock(g);
    var pick: ?RootPick = null;
    var near: f32 = reach;
    inline for (FOE_GROUPS, 0..) |f, gi| {
        for (@field(g, f.field).liveConst(), 0..) |*a, i| {
            if (!foemod.corporeal(a)) continue;
            // …AND NOT AT SOMETHING THAT IS NOT THERE (`disguised`, the reticle's and the melee aim's own
            // question). A sunk lurker or a burrowed delver inside the reach took the pick off a real target
            // and then refused the blow in its own `tryHit`, so the cast was spent on water.
            if (disguised(a)) continue;
            const d = mathx.distXZ(a.pos, g.hero.pos) - a.bodyR();
            if (d > reach) continue;
            if (!g.env.sees(eye, a.lockPoint())) continue;
            if (locked) |l| {
                if (l.idx == i and l.kind == memberKind(a, f.kind)) return .{ .group = gi, .idx = i };
                continue; // …and with a lock UP, nothing else is a candidate: he is pointing at somebody
            }
            const to = mathx.dirXZ(g.hero.pos, a.pos);
            if (mathx.lenXZ(to) > 1e-4) {
                const spread = if (d > 0) combat.subtendedArc(a.bodyR(), d + a.bodyR()) else 180.0;
                if (!combat.withinArc(mathx.headingXZ(to), g.hero.facing, combat.STRIKE_ARC + spread)) continue;
            }
            if (d < near) {
                near = d;
                pick = .{ .group = gi, .idx = i };
            }
        }
    }
    return pick;
}

/// What one landed: where it struck, the segment it struck down, and the HP THE BODY ACTUALLY LOST — which is
/// the only figure the siphon may feed off, since it is what the creature's own resistances left of the blow.
const Struck = struct { at: rl.Vector3, from: rl.Vector3, took: f32 };

/// **DELIVERED THROUGH THE CREATURE'S OWN `tryHit`** (`seedRoots`' shape), so a strike earns every reaction a
/// swing does — the flinch, the flash, the blood, the threat, the shield that might stop it, and a death only
/// the creature knows how to enter. Nothing here reaches inside a body except to read what it had before.
fn strikeOne(g: *Game, pick: RootPick, blow: combat.Hit) ?Struck {
    var out: ?Struck = null;
    inline for (FOE_GROUPS, 0..) |f, gi| {
        if (gi == pick.group) {
            const a = &@field(g, f.field).live()[pick.idx];
            const seg = strikeSegment(g, a.centerWorld(), a.topWorld().y);
            const before = a.vit.hp;
            a.tryHit(.{
                .active = true,
                .pierce = true, // A PROJECTILE'S DOOR: no swing latch to set, and the facing snaps down the line
                .r = STRIKE_R,
                .a = seg[0],
                .b = seg[1],
                .a0 = seg[0],
                .b0 = seg[1],
                .hit = blow,
            });
            out = .{ .at = seg[1], .from = seg[0], .took = mathx.maxF(0, before - a.vit.hp) };
        }
    }
    return out;
}

/// **WHERE A STRIKE THAT FOUND NOBODY IS DRAWN** — on the ground in front of him, half the spell's own reach out.
/// Both strikes owe the player this (a cast that shows nothing reads as the button not having worked) and both
/// were spelling the same three lines of arithmetic out at their own miss.
fn strikeMissAt(g: *const Game, reach: f32) rl.Vector3 {
    const d = mathx.headingDir(g.hero.facing);
    const x = g.hero.pos.x + d.x * reach * 0.5;
    const z = g.hero.pos.z + d.z * reach * 0.5;
    return v3(x, g.env.groundAt(x, z), z);
}

fn strikeLevin(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    // THE SPELL'S OWN REACH, off `combat.spellReach` rather than named here: with the constant written at the
    // call site there are two places that decide how far a strike carries, and the second one to be retuned wins.
    const reach = combat.spellReach(g.hero.spell) orelse return;
    sfx.play(.wand_cast);
    const pick = strikeVictim(g, reach) orelse {
        // NOTHING THERE, AND HE STILL PAID FOR IT. The stroke is drawn on the air in front of him at the reach
        // it would have had, because a cast that shows nothing at all reads as the button not having worked.
        const on = strikeMissAt(g, reach);
        const seg = strikeSegment(g, on, on.y);
        g.hero.levinStroke(seg[0], seg[1], on.y, g.hero.casts);
        g.rumble.play(rumblemod.cast_throw);
        g.rig.addShake(SHAKE_CAST);
        return;
    };
    const hit = strikeOne(g, pick, blow) orelse return;
    g.hero.levinStroke(hit.from, hit.at, g.env.groundAt(hit.at.x, hit.at.z), g.hero.casts);
    // The heaviest poise the rod throws lands as the heaviest beat it throws: `SHAKE_ROOTS_BITE` is what the
    // grip closing already earns, and this arrives on a body rather than under one.
    g.rumble.play(rumblemod.hit_heavy);
    g.rig.addShake(SHAKE_ROOTS_BITE);
}

fn drawSiphon(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const reach = combat.spellReach(g.hero.spell) orelse return;
    sfx.play(.wand_cast);
    g.rumble.play(rumblemod.cast_throw);
    g.rig.addShake(SHAKE_CAST);
    const pick = strikeVictim(g, reach) orelse {
        // DREW ON NOTHING, AND HE STILL PAID FOR IT — the levin's own courtesy, because a spell that shows
        // literally nothing on a miss reads as the button not having worked. Off empty air at half the reach (the
        // stroke's own mark, lifted to where a chest would have been): the motes still arrive at the stone, and
        // what says it failed is that none of them came off a body.
        const on = strikeMissAt(g, reach);
        g.hero.siphonDrain(v3(on.x, on.y + heromod.H * 0.55, on.z), g.hero.casts);
        return;
    };
    const hit = strikeOne(g, pick, blow) orelse return;
    // **A SHARE OF WHAT THE BODY ACTUALLY LOST**, never of what was thrown at it: resisted damage is resisted
    // healing, which is what keeps the wand's chaos trade honest on the one spell that could have voided it.
    // Capped by what it took, so an overkill cannot be milked for a body's worth of HP it never had.
    g.hero.siphonDrain(hit.at, g.hero.casts);
    _ = g.hero.drinkSiphon(hit.took * combat.SIPHON_SHARE);
}

fn gateChill(foes: anytype, was: []const rl.Vector3) void {
    const T = @typeInfo(@TypeOf(foes)).pointer.child;
    if (comptime !@hasField(T, "chill")) return;
    for (foes, 0..) |*f, i| {
        // THE CLOCK IS NOT RUN HERE. `foe.grip` ticks it at the top of the creature's own update, where the
        // bite it owes can be billed and can KILL — run again here it would decay at twice the rate and
        // swallow a frame of cold on its way past.
        if (i >= was.len or !f.chill.held()) continue;
        f.pos.x = was[i].x + (f.pos.x - was[i].x) * combat.CHILL_TRAVEL;
        f.pos.z = was[i].z + (f.pos.z - was[i].z) * combat.CHILL_TRAVEL;
    }
}

/// `throwBoltForShot`'s twin: the pose is driven past the `thrown` edge without going through `releaseSpell`.
pub fn castRootsForShot(g: *Game) rl.Vector3 {
    const at = rootMark(g);
    return seedRoots(g, at) orelse at;
}

/// …AND THE SAME DOOR FOR THE TWO STRIKES (`throwBoltForShot`'s reason, written at `castToThrow`): the harness
/// drives the POSE past the throw without going through `releaseSpell`, so the mechanic — and every spark that
/// fires on that exact frame — has to be fired by hand or the picture is a pose with the spell missing from it.
pub fn releaseSpellForShot(g: *Game) void {
    releaseSpell(g);
}

fn launchBolt(g: *Game, target: rl.Vector3, loft: bool, blow: combat.Hit) void {
    const from = g.hero.wandTipWorld();
    putIn(&g.shafts, archermod.launchShaft(from, target, heromod.BOLT_SPEED, blow, loft, .bolt));
    var dir = mathx.subV(target, from);
    if (mathx.lenV(dir) > 1e-3) dir = mathx.normV(dir) else dir = mathx.headingDir(g.hero.facing);
    g.hero.castSparks(dir);
}

fn camAimPoint(g: *const Game) rl.Vector3 {
    const ray = g.rig.centreRay();
    var reach = heromod.BOW_AIM_REACH;
    if (rayFoeDist(g, ray.origin, ray.dir)) |d| {
        reach = d;
    } else if (g.env.rayGround(ray.origin, ray.dir)) |hitPoint| {
        // …else the ground it would land on, so a shot at the earth in front of you lands there.
        reach = mathx.minF(reach, mathx.lenV(mathx.subV(hitPoint, ray.origin)));
    }
    // Never converge INSIDE him: a target closer than the bow is a shaft aimed backwards.
    reach = mathx.maxF(reach, AIM_CONVERGE_MIN);
    return mathx.addV(ray.origin, mathx.scaleV(ray.dir, reach));
}

const AIM_CONVERGE_MIN: f32 = 3.0;

const RayCtx = struct {
    origin: rl.Vector3,
    dir: rl.Vector3,
    best: ?f32 = null,

    fn visit(self: *RayCtx, foes: anytype, _: ?FoeKind) void {
        for (foes) |*f| {
            if (!f.alive() or f.dying()) continue;
            const oc = mathx.subV(f.centerWorld(), self.origin);
            const along = oc.x * self.dir.x + oc.y * self.dir.y + oc.z * self.dir.z;
            if (along <= 0) continue; // behind the eye
            const r = f.hurtRadius();
            // The perpendicular gap, SQUARED throughout — no square roots.
            const oc2 = oc.x * oc.x + oc.y * oc.y + oc.z * oc.z;
            if (oc2 - along * along > r * r) continue;
            if (self.best == null or along < self.best.?) self.best = along;
        }
    }
};

fn rayFoeDist(g: *const Game, origin: rl.Vector3, dir: rl.Vector3) ?f32 {
    var ctx = RayCtx{ .origin = origin, .dir = dir };
    eachTarget(g, &ctx, RayCtx.visit);
    return ctx.best;
}

fn stepShafts(g: *Game, dt: f32) void {
    for (&g.shafts) |*ar| {
        if (!ar.live) continue;
        const seg = archermod.stepShaft(ar, g.env.groundAt(ar.pos.x, ar.pos.z), arrowCover(g, ar, dt), dt) orelse {
            planted(g, ar);
            continue;
        };
        const blade = foemod.Blade{
            .active = true,
            .pierce = true,
            .r = archermod.SHAFT_R,
            .a = seg[0],
            .b = seg[1],
            .a0 = seg[0],
            .b0 = seg[1],
            .hit = ar.blow,
        };
        if (!pierceFoes(g, blade)) continue;
        archermod.plantShaft(ar);
        splashOf(g, ar);
        sfx.world(.arrow_hit, ar.pos);
        g.rumble.play(rumblemod.hit_light);
        g.rig.addShake(SHAKE_HIT_LIGHT);
    }
}

/// Past the widest notice ring in the game. Folded over `FOE_GROUPS` rather than hand-written, or a creature
/// given a wider ring later quietly stops being asked and sees through walls again.
const SIGHT_R: f32 = blk: {
    var widest: f32 = 0;
    for (FOE_GROUPS) |f| widest = @max(widest, f.aggro);
    break :blk widest + 1.0;
};

fn heroEye(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, g.hero.pos.y + foemod.HERO_EYE, g.hero.pos.z);
}

fn markSight(g: *Game) void {
    const eye = heroEye(g);
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            if (!f.alive() or f.dying()) continue;
            if (mathx.distXZ(g.hero.pos, f.pos) > SIGHT_R) continue;
            if (g.env.sees(f.lockPoint(), eye)) f.leash.noteSeen();
        }
    }
}

/// Metres ahead a creature looks for something in the way, past its own radius — about a walking second.
const WAY_PROBE: f32 = 2.0;
const WAY_FAN = [_]f32{ 0.45, 0.90, 1.40, 1.95, 2.50 };
const WAY_TRUE: f32 = 0.98;

fn wayClear(g: *const Game, at: rl.Vector3, r: f32, dir: rl.Vector3) bool {
    const reach = WAY_PROBE + r;
    const went = mathx.dirXZ(at, g.env.walkStep(at, dir, reach));
    if (mathx.lenXZ(went) < 1e-4) return false; // the terrain (or the deep) refused it outright…
    if (went.x * dir.x + went.z * dir.z < WAY_TRUE) return false; // …or slid it somewhere it did not ask for
    for ([2]f32{ 0.5, 1.0 }) |u| {
        const p = v3(at.x + dir.x * reach * u, at.y, at.z + dir.z * reach * u);
        if (mathx.distXZ(g.env.resolveActor(p, r, at.y), p) > 1e-3) return false;
    }
    return true;
}

fn markWay(g: *const Game, nav: *foemod.Nav, at: rl.Vector3, r: f32, want: rl.Vector3) void {
    const straight = mathx.dirXZ(at, want);
    if (mathx.lenXZ(straight) < 1e-4 or wayClear(g, at, r, straight)) {
        nav.dir = null;
        return;
    }
    const yaw = mathx.headingXZ(straight);
    // Width OUTSIDE, side INSIDE: the narrowest angle that works wins whichever side it is on, and the side
    // only settles a TIE — which is the anti-dither `Nav.side` is for.
    for (WAY_FAN) |off| {
        for ([2]f32{ nav.side, -nav.side }) |s| {
            const d = mathx.headingDir(yaw + off * s);
            if (!wayClear(g, at, r, d)) continue;
            nav.dir = d;
            nav.side = s;
            return;
        }
    }
    nav.dir = null; // BOXED IN: nowhere to go, so it presses on into the thing and the gate holds its feet
}

fn markWays(g: *Game) void {
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            const M = @TypeOf(f.*);
            if (comptime !@hasField(M, "nav")) continue;
            if (!foemod.corporeal(f) or f.airborne()) {
                f.nav.dir = null;
                continue;
            }
            const want = f.navWant(f.threat.aim(g.hero.pos)) orelse {
                f.nav.dir = null;
                continue;
            };
            markWay(g, &f.nav, f.pos, f.bodyR(), want);
        }
    }
}

fn markThreat(g: *Game, dt: f32) void {
    const spirit: ?rl.Vector3 = blk: {
        const w = g.pack.firstConst() orelse break :blk null;
        if (!foemod.corporeal(w)) break :blk null;
        break :blk w.pos;
    };
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            const M = @TypeOf(f.*);
            const mine: ?rl.Vector3 = blk: {
                if (comptime @hasDecl(M, "airborne")) {
                    if (f.airborne()) break :blk null;
                }
                break :blk spirit;
            };
            f.threat.at = mine orelse g.hero.pos;
            f.threat.tick(
                dt,
                mathx.distXZ(f.pos, g.hero.pos),
                // …and with no spirit to measure, INFINITELY FAR (`mathx.LONG_AGO`).
                if (mine) |s| mathx.distXZ(f.pos, s) else mathx.LONG_AGO,
                mine != null,
            );
        }
    }
}

/// **HOW DEEP THE WATER IS, STAMPED ONTO WHATEVER LIVES IN IT** (`foe.Wade`) — `markParry`'s arrangement, and
/// the reason it is a pass rather than a lookup inside the creature: `env`'s water field belongs to `env`, and
/// a creature that reached for it would be a creature that knows what an `Env` is.
///
/// **THE FIELD IS THE OPT-IN** (`markWays`' `@hasField` rule), so the fifteen groups that never touch water
/// compile to nothing here and pay nothing for a creature they have no relationship with.
fn markWade(g: *Game) void {
    const quarry = g.env.wadeDepth(g.hero.pos.x, g.hero.pos.z);
    const Depth = struct {
        fn at(e: *const envmod.Env, p: rl.Vector3) f32 {
            return e.wadeDepth(p.x, p.z);
        }
    };
    inline for (FOE_GROUPS) |gr| {
        const M = std.meta.Child(@TypeOf(@field(g, gr.field).live()));
        if (comptime @hasField(M, "wade")) {
            foemod.setWade(@field(g, gr.field).live(), &g.env, quarry, Depth.at);
        }
    }
}

fn markParry(g: *Game) void {
    const p = foemod.Parry{ .live = g.hero.parryLive(), .at = g.hero.pos, .facing = g.hero.facing, .arc = g.hero.guardArc() };
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "setParry")) @field(g, f.field).setParry(p);
    }
}

/// One answer for the whole field: two creatures caught on one frame is still one shield and one recoil.
fn anyParried(g: *const Game) bool {
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "anyParried")) {
            if (@field(g, f.field).anyParried()) return true;
        }
    }
    return false;
}

/// Deliberately over the block's beat: a block is a cost paid, this is a blow REFUSED.
fn parryBeat(g: *Game) void {
    g.hero.noteParry();
    g.rumble.play(rumblemod.parry);
    g.rig.addShake(SHAKE_PARRY);
    sfx.play(.parry);
}

fn markVigil(g: *Game) void {
    // Nothing on the field is held until something earns it this frame.
    eachRaisable(g, {}, struct {
        fn v(_: void, f: anytype) void {
            f.heldOpen = false;
        }
    }.v);
    for (g.rite.live()) |*k| {
        k.vigil.at = null;
        if (!foemod.corporeal(k)) continue;
        const from = if (k.casting()) k.raiseAt else k.pos;
        const reach = if (k.casting()) necromod.RAISE_MATCH_R else necromod.RAISE_R;
        const ref = nearestRaisable(g, from, reach, .skip) orelse continue;
        k.vigil.at = ref.at;
        withRaisable(g, ref, {}, struct {
            fn v(_: void, f: anytype) void {
                f.heldOpen = true;
            }
        }.v);
    }
}

const BodyRef = struct { group: usize, idx: usize, at: rl.Vector3 };

fn eachRaisable(g: *Game, ctx: anytype, comptime visit: anytype) void {
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            if (comptime !@hasDecl(@TypeOf(f.*), "raisable")) continue;
            visit(ctx, f);
        }
    }
}

const Claimed = enum { skip, take };
fn nearestRaisable(g: *Game, at: rl.Vector3, within: f32, claimed: Claimed) ?BodyRef {
    var best: f32 = within;
    var ref: ?BodyRef = null;
    inline for (FOE_GROUPS, 0..) |gr, gi| {
        for (@field(g, gr.field).live(), 0..) |*f, i| {
            if (comptime !@hasDecl(@TypeOf(f.*), "raisable")) continue;
            if (!f.raisable()) continue;
            if (claimed == .skip and f.heldOpen) continue;
            const d = mathx.distXZ(at, f.pos);
            if (d > best) continue;
            best = d;
            ref = .{ .group = gi, .idx = i, .at = f.pos };
        }
    }
    return ref;
}

fn withRaisable(g: *Game, ref: BodyRef, ctx: anytype, comptime visit: anytype) void {
    // The group test is a runtime `if` WRAPPING the body rather than a `continue` — `gi` is comptime and
    // `ref.group` is not, so skipping an `inline for` iteration on it is comptime control flow inside a runtime
    // block, which Zig refuses outright.
    inline for (FOE_GROUPS, 0..) |gr, gi| {
        if (gi == ref.group) {
            for (@field(g, gr.field).live(), 0..) |*f, i| {
                if (comptime !@hasDecl(@TypeOf(f.*), "raisable")) continue;
                if (i == ref.idx) visit(ctx, f);
            }
        }
    }
}

fn applyRaises(g: *Game) void {
    for (g.rite.live()) |*k| {
        if (!k.raised) continue;
        const ref = nearestRaisable(g, k.raiseAt, necromod.RAISE_MATCH_R, .take) orelse continue;
        withRaisable(g, ref, {}, struct {
            fn v(_: void, f: anytype) void {
                f.reraise(necromod.RAISE_HP_FRAC);
            }
        }.v);
        g.rumble.play(rumblemod.hit_heavy);
        g.rig.addShake(SHAKE_RAISE);
    }
}

fn canSee(g: *const Game, r: FoeRef) bool {
    return g.env.sees(heroEye(g), foeLockPoint(g, r));
}

fn pierceFoes(g: *Game, blade: foemod.Blade) bool {
    var hit = false;
    inline for (FOE_GROUPS) |f| {
        if (!hit and @field(g, f.field).pierce(blade)) hit = true;
    }
    return hit;
}

const ARROW_QUERY_PAD: f32 = 1.5;
var arrow_cover_buf: [envmod.MAX_NEAR]collision.Solid = undefined;
pub fn arrowCover(g: *const Game, ar: *const archermod.Arrow, dt: f32) []const collision.Solid {
    return g.env.nearSolids(ar.pos, mathx.lenV(ar.vel) * dt + ARROW_QUERY_PAD, &arrow_cover_buf);
}

fn quivers(g: *Game) [2][]archermod.Arrow {
    return .{ &g.arrows, &g.shafts };
}

/// One body for BOTH quivers.
fn planted(g: *Game, ar: *const archermod.Arrow) void {
    if (!ar.stuck or ar.age != 0) return;
    // Only the glob is silent, because `brood.splash` carries the voice for that one.
    if (ar.shot != .venom) sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
    splashOf(g, ar);
}

fn splashOf(g: *Game, ar: *const archermod.Arrow) void {
    const ground = v3(ar.pos.x, g.env.groundAt(ar.pos.x, ar.pos.z), ar.pos.z);
    switch (ar.shot) {
        .venom => g.brood.splash(ground),
        .clump => g.band.splash(ar.pos), // at the CONTACT, not the floor: it can burst against a chest
        .bolt => g.hero.boltBurst(ar.pos, ground.y, g.hero.casts),
        // THE FIREBALL GOING OUT — this is the LAST touch only, because `planted` is what calls this and a
        // ball with budget left never plants (`archer.plantGround`). The bounces get their own, smaller
        // voice and puff below.
        .emberball => {
            sfx.world(.ember_burst, ar.pos);
            g.ring.splash(ar.pos);
        },
        // The crock's gap is deliberate, until the owner picks what lightning landing looks like.
        .arrow, .firearrow, .wisp, .crock => {},
    }
}

/// **AND THE BOUNCES, WHICH ARE THE MOVE.** Walked over both quivers after they have flown, because the flag
/// is one frame wide and set inside `archer`'s own step — the creature that threw it is long out of the
/// conversation and may well be dead. The RHYTHM is the cue: one thud per touch, so a player who has heard
/// the pattern once knows where the next one is landing without looking down at it.
fn emberBounces(g: *Game) void {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (!ar.bounced) continue;
            ar.bounced = false;
            sfx.world(.ember_bounce, ar.pos);
            g.ring.bounce(ar.pos);
        }
    }
}

fn drawArrows(g: *Game) void {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (!ar.live) continue;
            const m = switch (ar.shot) {
                .arrow => &g.arrowModel,
                .clump => &g.clumpModel,
                .crock => &g.crockModel,
                .venom => &g.venomModel,
                .firearrow => &g.fireArrowModel,
                .bolt => &g.boltModel,
                .emberball => &g.emberModel,
                .wisp => &g.wispModel,
            };
            rl.drawMesh(m.meshes[0], m.materials[0], archermod.arrowXform(ar));
        }
    }
}

fn clearQuivers(g: *Game) void {
    for (quivers(g)) |pool| {
        for (pool) |*ar| ar.* = .{};
    }
}

fn sceneCam(g: *const Game) rl.Camera3D {
    return if (g.editor.on) g.editor.cam else g.rig.cam;
}

fn sunFocus(g: *const Game) rl.Vector3 {
    // **THE SHADOW BOX FOLLOWS THE LENS WHEREVER THE LENS IS NOT ON HIM.** It tracks the hero because that is
    // where the fight is; on the boot screen there is no fight and the camera is a hundred metres away over
    // the wood, so anchored to him the whole pass renders with no cast shadow in frame at all — which on a
    // canopy is most of what there is to look at. The editor's branch below is the same rule, older.
    if (g.menu.booting()) {
        const at = bootLook(g, g.bootT);
        return v3(at.x, g.env.groundAt(at.x, at.z), at.z);
    }
    if (!g.editor.on) return g.hero.pos;
    const t = g.editor.cam.target;
    return v3(t.x, g.env.groundAt(t.x, t.z), t.z);
}

const RESERVED_LIGHTS = gfx.MAX_LIGHTS / 2;

fn reservedLights(g: *const Game, out: *[RESERVED_LIGHTS]gfx.Light) []const gfx.Light {
    var n: usize = 0;
    if (g.hero.wandLight()) |w| {
        out[n] = w;
        n += 1;
    }
    n += g.rite.markLights(out[n..]);
    return out[0..n];
}

pub fn drawScene(g: *Game) void {
    g.env.resetStats();
    applyStow(g); // before the depth pass: what is stowed is not a caster
    const cam = sceneCam(g);
    g.env.markOccluders(cam.position, if (g.editor.on) cam.position else heroAimPoint(g), g.drawDt);
    const focus = sunFocus(g);
    g.scene.beginShadowPass(focus);
    setCasterShaders(g, g.scene.depthShader);
    drawCasters(g, .{ .sun = focus });
    setCasterShaders(g, g.scene.shader);
    g.scene.endShadowPass();

    rl.beginDrawing();
    const filtered = if (g.editor.on) false else g.retro.begin();
    rl.clearBackground(CLEAR);
    g.sky.draw(cam);

    const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
    const view = envmod.View.fromCamera(cam, aspect);

    rl.beginMode3D(cam);
    g.scene.bind(cam.position);
    var lightBuf: [RESERVED_LIGHTS]gfx.Light = undefined;
    g.env.uploadLights(&g.scene, &view, @floatCast(rl.getTime()), reservedLights(g, &lightBuf));
    g.scene.setGround(true);
    g.env.drawGround(&view);
    g.scene.setGround(false);
    g.env.drawWater();
    if (g.menu.wireframe) rl.gl.rlEnableWireMode();
    drawCasters(g, .{ .view = view });
    g.scene.setWind(true);
    g.env.drawFlora(&view);
    g.scene.setWind(false);
    drawArrows(g);
    // The drop is made of light and lays no shadow, so it stays off `drawCasters` entirely.
    g.souls.draw();
    // …and the thinned occluders LAST, so their alpha mattes the hero standing behind them (`Env.drawThinned`).
    g.env.drawThinned(&view);
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
    g.env.drawVeils(&view);
    // Unlit spheres over the opaque geometry.
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "drawFx")) @field(g, f.field).drawFx();
    }
    // …and the spirit's own, which needs its own line because it is not in `FOE_GROUPS`.
    g.pack.drawFx();
    g.souls.drawFx();
    g.hero.drawTrail();
    for (quivers(g)) |pool| archermod.drawArrowTrails(pool);
    if (g.menu.hitboxes and g.hero.attacking) {
        const col = if (g.hero.hitActive()) rl.Color.red else mathx.withAlpha(rl.Color.red, 90);
        rl.drawCapsuleWires(g.hero.bladeA, g.hero.bladeB, heromod.BLADE_R, 6, 3, col);
    }
    if (g.menu.hitboxes) {
        inline for (FOE_GROUPS) |gr| {
            for (@field(g, gr.field).live()) |*f| {
                if (!f.alive()) continue;
                const col = if (f.flash > 0) rl.Color.orange else mathx.withAlpha(rl.Color.yellow, 80);
                rl.drawSphereWires(f.centerWorld(), f.hurtRadius(), 8, 10, col);
            }
        }
    }
    if (g.editor.on) g.editor.draw3D(&g.map, &g.env);
    rl.endMode3D();

    if (filtered) g.retro.end();
    if (g.editor.on) return;
    g.vignette.draw();
    drawRestFade(g);
    drawHurtFlash(g);
    drawFoeBars(g);
    drawLockDot(g);
    drawDeathOverlay(g);
}

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
        rl.drawRectangle(0, 0, w, h, rgba(6, 3, 3, mathx.u8f(120.0 * dim)));
        const bandK = mathx.smoothstep(0.10, 0.34, u);
        const bandTop = DEATH_BAND_TOP * hf;
        const bandH = DEATH_BAND_H * hf;
        const bh: i32 = @intFromFloat(bandH);
        const by: i32 = @intFromFloat(bandTop);
        const third = @divTrunc(bh, 3);
        const bcol = rgba(0, 0, 0, mathx.u8f(170.0 * bandK));
        const bclear = rgba(0, 0, 0, 0);
        rl.drawRectangleGradientV(0, by, w, third, bclear, bcol);
        rl.drawRectangle(0, by + third, w, bh - 2 * third, bcol);
        rl.drawRectangleGradientV(0, by + bh - third, w, third, bcol, bclear);
        const ta = mathx.pulse(u, 0.16, 0.48, 0.90, 1.0);
        if (ta > 0.01) {
            const size = 0.115 * hf * (0.97 + 0.06 * u);
            const spacing = 0.22 * size; // ER's wide tracking (between glyphs only — measured exactly)
            const cx = 0.5 * wf;
            const cy = bandTop + bandH * 0.5; // band centre, DERIVED
            const glow = rgba(120, 14, 10, mathx.u8f(44.0 * ta));
            hud_.bigCentered("YOU DIED", cx - 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx + 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy - 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy + 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy, size, spacing, rgba(156, 22, 16, mathx.u8f(232.0 * ta)));
        }
        // Full black a little BEFORE the respawn, so the cut is buried inside the card.
        const blackK = mathx.smoothstep(0.82, 0.94, u);
        if (blackK > 0.001) rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * blackK)));
    } else if (g.deathFade > 0) {
        const k = if (g.deathFade > RESPAWN_FADE) 1.0 else mathx.clampF(g.deathFade / RESPAWN_FADE, 0, 1);
        rl.drawRectangle(0, 0, w, h, rgba(0, 0, 0, mathx.u8f(255.0 * k)));
    }
}

fn drawHurtFlash(g: *Game) void {
    const f = g.hero.hurtFlash;
    if (f <= 0.001) return;
    const w = rl.getScreenWidth();
    const h = rl.getScreenHeight();
    const t: i32 = @intFromFloat(0.16 * @as(f32, @floatFromInt(h)));
    const edge = rgba(150, 20, 16, mathx.u8f(f * 150));
    const clear = rgba(150, 20, 16, 0);
    rl.drawRectangle(0, 0, w, h, rgba(150, 18, 14, mathx.u8f(f * 26)));
    rl.drawRectangleGradientV(0, 0, w, t, edge, clear);
    rl.drawRectangleGradientV(0, h - t, w, t, clear, edge);
    rl.drawRectangleGradientH(0, 0, t, h, edge, clear);
    rl.drawRectangleGradientH(w - t, 0, t, h, clear, edge);
}

pub const HUD_FADE_DUR: f32 = 0.55;

/// …and what the chrome is worth this frame: 1 alive, easing to 0 across the fade once he is down.
fn chromeFade(g: *const Game) f32 {
    if (!g.hero.dead) return 1;
    return 1.0 - mathx.smoothstep(0, HUD_FADE_DUR, g.hero.deathT);
}

pub fn hud(g: *Game, dt: f32) void {
    // A conversation takes the bottom of the screen, which is where the cross and the prompt live.
    if (g.rest.active() or g.talk.active()) return;
    const chrome = chromeFade(g);
    const wantChrome = !g.menu.isOpen() and chrome > 0.001;
    // **THE SPIRIT'S FACE IS TAKEN BEFORE THE CHROME TARGET OPENS.** `endTextureMode` restores the DEFAULT
    // framebuffer rather than the target that was bound before it, so rendering a portrait inside the chrome
    // scope would send every HUD draw after it at the backbuffer, to be overwritten by the chrome's own blit.
    // Taken here, the toast below only has a quad to mount (`hud.renderPortrait`).
    const spiritFace = wantChrome and if (spiritPortrait(g)) |lp| hud_.renderPortrait(lp) else false;
    // **THE CLOSE IS A `defer` IN ITS OWN SCOPE, NOT A LINE AT THE BOTTOM.** An open `beginTextureMode` that
    // never closes does not lose the chrome, it eats the WHOLE REST OF THE FRAME into an offscreen buffer —
    // so a `return` added anywhere in the block below would blank the screen, and nothing about the edit
    // would look wrong. The scope also ends BEFORE the banner, which is not chrome.
    {
        const veiled = wantChrome and hud_.beginChrome(chrome);
        defer if (veiled) hud_.endChrome(chrome);
        if (wantChrome) {
            hud_.vitals(
                dt,
                g.hero.vit.hpFrac(),
                g.hero.fp.frac(),
                g.hero.stam.frac(),
                g.hero.stamRefused / combat.STAM_REFUSE_FLASH,
                g.hero.fpRefused / combat.STAM_REFUSE_FLASH,
                g.hero.stam.windedTo(),
                .{ .frac = g.hero.poison.frac(), .on = g.hero.poison.active() },
            );
            hud_.dayDial(g.day.hour);
            const bowUp = g.hero.bowOut();
            const wandUp = g.hero.wandOut();
            hud_.equipment(
                // LEFT: what that hand actually has — boards, the rod, or nothing at all behind a bow.
                if (!g.hero.offInHand()) .empty else armSlot(g.hero.off),
                armSlot(g.hero.armInHand()),
                // UP fills only while something in his hands could cast; behind a bow or a shield, empty. The
                // CELL CARRIES THE SPELL (`hud.Slot.sorcery`), so which picture it is stays `itemart`'s one answer.
                if (wandUp) hud_.Slot{ .sorcery = g.hero.spell } else .empty,
                g.hero.fp.cur >= g.hero.castCost(),
                g.hero.quick.selected(),
                quickLeft(g),
                if (bowUp) hud_.Ammo{ .n = g.hero.quiver.ready(), .fire = heromod.arrowBurns(g.hero.quiver.sel) } else null,
            );
            if (g.pack.firstConst()) |w| {
                g.spiritK = mathx.approach(g.spiritK, 1.0, dt * 5.0);
                g.spiritHp = w.vit.hpFrac();
            } else {
                g.spiritK = mathx.approach(g.spiritK, 0, dt * 2.2);
            }
            hud_.spiritPanel(spiritFace, combat.spiritName(g.hero.spirit), g.spiritHp, g.spiritK);
            hud_.reticle(g.hero.aimB);
            hud_.souls(g.hero.souls.display()); // the ROLLING value, not the banked total
            if (g.vigil.boss(g.hero.pos)) |bi| {
                const b = &g.vigil.liveConst()[bi];
                g.bossFrac = b.vit.hpFrac();
                g.bossK = mathx.approach(g.bossK, 1.0, dt * 4.0);
                hud_.bossBar(dt, worldfmt.foeName(.bone_knight), g.bossFrac, b.staggered(), g.bossK);
            } else {
                g.bossK = mathx.approach(g.bossK, 0, dt * 1.4);
                hud_.bossBar(dt, worldfmt.foeName(.bone_knight), g.bossFrac, false, g.bossK);
            }
            // The same `reachable` the PRESS goes through: a prompt naming a different thing is worse than none.
            if (reachable(g)) |r| hud_.prompt(r.prompt());
        }
    }
    const line = g.trig.bannerText();
    if (line.len > 0) hud_.banner(line);
    g.award.drawToasts();
    if (g.menu.stats) debugCorner(g);
}

const DBG_ROW = 200;

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
    else if (g.hero.parrying)
        (if (g.hero.parryLive()) "PARRY" else "parry recovery")
    else if (g.hero.shooting)
        (if (g.hero.shotAimed) "loosing" else "snapshot")
    else if (g.hero.aiming)
        "aiming"
    else
        gaitLabel(g.hero.moving, g.hero.speed);
    dbgRow(std.fmt.bufPrintZ(&buf, "{s}   {d:.1} m/s", .{ label, g.hero.speed }) catch "", y, hud_.BODY, rgba(150, 156, 164, 255));
    y += hud_.lineH(hud_.BODY) + 4;

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

    const h = &g.hero;
    const foesLeft = allAlive(g);
    const foeHits = allHits(g);
    dbgRow(std.fmt.bufPrintZ(&buf, "hero  hp {d:.0}/{d:.0}  poise {d:.0}/{d:.0}  stance {d:.0}/{d:.0}  stam {d:.0}/{d:.0}   foes {d} left  hits {d}", .{
        h.vit.hp,   h.vit.hpMax, h.vit.poise, h.vit.poiseMax, h.vit.stance, h.vit.stanceMax,
        h.stam.cur, h.stam.max,  foesLeft,    foeHits,
    }) catch "", y, hud_.SMALL, rgba(150, 180, 190, 255));
    y += step;

    // The four resistances are only legible against a named target, so the row reads the LOCK, not the hero.
    const sel = h.quiver.sel;
    const rider: [:0]const u8 = if (sel == .fire) "  +fire" else "";
    if (g.lock) |li| {
        const r = foeResists(g, li);
        dbgRow(std.fmt.bufPrintZ(&buf, "arrow  {s} {d}/{d}{s}   lock res  fire {d:.0}  cold {d:.0}  lgt {d:.0}  chaos {d:.0}", .{
            @tagName(sel), h.quiver.ready(), combat.Quiver.cap(sel), rider,
            r.raw(.fire),  r.raw(.cold),     r.raw(.lightning),      r.raw(.chaos),
        }) catch "", y, hud_.SMALL, STAT_WARN);
    } else {
        dbgRow(std.fmt.bufPrintZ(&buf, "arrow  {s} {d}/{d}{s}", .{
            @tagName(sel), h.quiver.ready(), combat.Quiver.cap(sel), rider,
        }) catch "", y, hud_.SMALL, STAT_WARN);
    }
    y += step;

    dbgRow(std.fmt.bufPrintZ(&buf, "world  props {d}  solids {d}  fires {d}   drawn {d} in {d} cells (both passes)", .{
        g.env.propCount(), g.env.solidCount(), g.env.lightCount(), g.env.stat_draws, g.env.stat_cells,
    }) catch "", y, hud_.SMALL, rgba(150, 175, 195, 255));
    y += step;

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

fn dbgRow(s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    hud_.textRight(s, hud_.MARGIN, y, size, col);
}

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
    var runTimer = std.time.Timer.start() catch unreachable;
    const stamp = struct {
        fn ms(t: *std.time.Timer, name: []const u8) void {
            std.debug.print("INIT: {s: <10} {d:.1} ms\n", .{ name, @as(f64, @floatFromInt(t.lap())) / 1e6 });
        }
    }.ms;
    // VSYNC, not `setTargetFPS`: that is a CPU-side frame LIMITER and never tells the driver to swap during
    // vblank, so the swap lands mid-scan and fullscreen tears.
    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true, .window_hidden = shot, .window_resizable = true });
    rl.initWindow(SCREEN_W, SCREEN_H, "zig-soulslike");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    // …and no `setTargetFPS` alongside it: the two limiters fight on any display that is not 60 Hz.
    stamp(&runTimer, "window");

    hud_.init();
    defer hud_.deinit();
    stamp(&runTimer, "fonts");

    if (!shot) {
        sfx.init();
        stamp(&runTimer, "audio bake");
    }
    defer if (!shot) sfx.deinit();
    defer objviewmod.unload();
    defer bookmod.unload();
    defer hud_.unloadPortrait(); // the one live-portrait target: the panel's speaker AND the spirit toast
    defer menumod.unload();

    const alloc = std.heap.c_allocator;
    const g = alloc.create(Game) catch return;
    defer alloc.destroy(g);
    g.init();

    rl.gl.rlSetClipPlanes(CLIP_NEAR, CLIP_FAR);

    if (mode == .shots) {
        // A MAP THAT IS NOT THE AUTHORED ONE GETS THE DEV PASS. `runShots` photographs a fixed sequence and
        // needs that world's exact cast; a test map posts whatever it posts.
        if (std.mem.eql(u8, worldfmt.startMap(), worldfmt.START_MAP)) {
            @import("shots.zig").runShots(g);
        } else {
            @import("shots.zig").runMapShots(g);
        }
        return;
    }
    if (mode == .props) {
        @import("shots.zig").runPropShots(g);
        return;
    }

    rl.hideCursor();
    var wasInside = false;
    var bWasDown = false; // gamepad Circle/B: a TAP rolls, a HOLD sprints
    var bHeldT: f32 = 0;
    var lockCycleReady = true; // debounce so one flick cycles the lock-on target once
    var lookPad = false;
    // Rising-edge trackers for rumble: pulse the frame an action BEGINS.
    var wasRolls: u32 = 0;
    var wasSwings: u32 = 0;
    var wasDead = false;
    var wasRefused: f32 = 0;
    var wasAiming = false;
    var wasStun: combat.StunKind = .none;
    var lastPhase: f32 = 0.75;
    var bankT: f32 = 0; // seconds finishing the bank behind the menu; -1 once reported
    defer g.rumble.stop();
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime(); // wall-clock dt: feel systems (shake, rumble, fades, tap windows)
        const dt = rawDt * g.menu.timeScale;
        g.drawDt = rawDt; // …including the occluder fade, which every branch below draws through
        PLAY_HALF = playHalfOf(g.map.half);
        // The clock runs on `dt`, not `rawDt`, so the debug time scale slows the sun with everything else.
        if (!g.editor.on and !g.menu.isOpen() and !g.rest.active() and !g.talk.active() and !g.award.carding()) g.day.tick(dt);
        applyHour(g);
        sfx.mute(g.editor.on and !g.editor.auditioning());
        sfx.tickFx(rawDt);
        const paused = g.menu.isOpen() or g.rest.active() or g.talk.active() or g.editor.on;
        const budget: u64 = if (paused) 3 * std.time.ns_per_ms else 1 * std.time.ns_per_ms;
        if (sfx.pump(budget, paused)) bankT += rawDt else if (bankT > 0) {
            std.debug.print("INIT: {s: <10} {d:.1} ms (behind the menu)\n", .{ "audio rest", bankT * 1000.0 });
            bankT = -1;
        }

        if (!g.editor.on and !g.rest.active() and !g.talk.active()) {
            if (rl.isKeyPressed(.escape)) g.menu.onEscape();
            if (rl.isKeyPressed(.tab)) g.menu.onStartButton();
            if (padPressed(.middle_left)) g.menu.onSelectButton();
            if (padPressed(.middle_right)) g.menu.onStartButton();
        }

        if (rl.isKeyPressed(.enter) and (rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt))) {
            rl.toggleBorderlessWindowed();
            g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());
        }
        if (rl.isWindowResized()) g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());

        if (g.editor.on) {
            rl.showCursor();
            switch (g.editor.update(&g.map, &g.env, &g.day, rawDt)) {
                .none => {},
                .leave => {
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    g.menu.screen = g.menu.home;
                    rl.hideCursor(); // the mouse IS the camera again
                    armScript(g);
                },
                .playtest => {
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    g.menu.started(); // F5 IS a started world, whichever card the editor was opened from
                    rl.hideCursor();
                    armScript(g); // the world he is about to test is a FRESH one: no switch already thrown
                    g.hero.pos = mathx.ground(g.editor.cam.target.x, g.editor.cam.target.z);
                    plantActor(g, &g.hero.pos);
                    g.hero.pos = g.env.resolveActor(g.hero.pos, HERO_R, g.hero.pos.y);
                    g.hero.setSpawn(g.hero.pos, g.hero.facing);
                    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
                    wasInside = false; // swallow the mouse delta the editor's look accumulated
                },
            }
            g.hero.held = true;
            g.hero.setGuard(false);
            g.hero.pose();
            rehomeFoes(g, .blind);
            rehomeChests(g);
            if (g.folkGen != g.editor.mapGen) {
                g.folk.reset(&g.map);
                g.folkGen = g.editor.mapGen;
            }
            g.folk.update(rawDt, g.hero.pos, PLAY_HALF);
            g.rumble.update(rawDt, false);
            drawScene(g);
            editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, rawDt);
            rl.endDrawing();
            continue;
        }

        g.hero.held = g.menu.isOpen();
        if (g.menu.isOpen()) {
            switch (g.menu.update(&g.retro, &g.day, rawDt, bookView(g), &g.shelf)) {
                .quit => break,
                .editor => {
                    g.lock = null;
                    g.editor.enter(g.hero.pos);
                },
                // Nothing torn down and nothing written: the character is saved as of the last fire.
                .toTitle => g.menu.toTitle(),
                .newGame => |i| beginEnter(g, .{ .fresh = i }),
                .loadGame => |i| beginEnter(g, .{ .load = i }),
                .deleteSlot => |i| {
                    if (savemod.erase(i)) {
                        g.shelf = savemod.survey(saveMap(g));
                        g.menu.slotsChanged();
                    } else std.debug.print("DELETE FAILED: could not remove {s}\n", .{savemod.path(i)});
                },
                .use => |k| useItem(g, k),
                .arm => |a| bookAct(g, a),
                .none => {},
            }
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false; // swallow the mouse delta accumulated while in the menu
            g.hero.update(rawDt, 0, 0, null);
            g.hero.pose();
            g.rig.tickShake(rawDt);
            const booting = g.menu.booting();
            if (booting) {
                g.bootT += rawDt;
                bootCam(g, g.bootT);
            } else g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false); // motors silent while paused (envelopes still decay)
            sfx.ambience(rawDt);
            drawScene(g);
            // No HUD behind the BOOT screen: there is no character yet whose bars those would be.
            if (!booting) hud(g, rawDt);
            g.menu.draw(&g.retro, &g.day, bookView(g), .{ .hero = &g.hero, .scene = &g.scene }, &g.shelf);
            // LAST, over the menu itself: the cut has to cover the card the press came off.
            tickEnter(g, rawDt);
            drawEnterFade(g);
            rl.endDrawing();
            continue;
        }

        if (g.award.carding()) {
            g.hero.held = true;
            var pressed = rl.getKeyPressed() != .null;
            if (rl.isMouseButtonPressed(.left) or rl.isMouseButtonPressed(.right)) pressed = true;
            inline for (.{ .right_face_down, .right_face_right, .right_face_left, .right_face_up, .middle_right, .middle_left }) |b| {
                if (rl.isGamepadButtonPressed(0, b)) pressed = true;
            }
            if (pressed) g.award.dismiss();
            bWasDown = true; // poison the pad-B tap window, exactly as the menu and the fire branches do
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            g.hero.update(rawDt, 0, 0, null); // the breathing bob alone — the pause card's own rule
            g.hero.pose();
            g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false);
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            hud(g, rawDt);
            g.award.drawCard();
            rl.endDrawing();
            continue;
        }

        if (g.enterAct != null) {
            g.hero.held = true;
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            g.hero.update(rawDt, 0, 0, null);
            g.hero.pose();
            g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false);
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            hud(g, rawDt);
            tickEnter(g, rawDt);
            drawEnterFade(g);
            rl.endDrawing();
            continue;
        }

        if (g.rest.active()) {
            tickRest(g, rawDt);
            bWasDown = true; // poison the pad-B tap window, exactly as the menu branch does
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            takeSlotShot(g);
            hud(g, rawDt);
            restmod.drawScreen(&g.rest, &g.tree, g.hero.souls.total);
            rl.endDrawing();
            continue;
        }
        // A conversation holds the world as the pause card does, at WALL-CLOCK time.
        if (g.talk.active()) {
            tickTalk(g, rawDt);
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            hud(g, rawDt);
            g.talk.draw(&g.map, &g.trig, triggerWorld(g), talkPortrait(g));
            rl.endDrawing();
            continue;
        }

        g.rest.update(rawDt);
        g.rest.look(g.hero.pos);
        g.souls.update(dt);
        g.souls.look(g.hero.pos);
        sfx.tickStreams();

        const lockPressed = !g.hero.aiming and (rl.isMouseButtonPressed(.middle) or padPressed(.right_thumb));
        if (lockPressed) {
            if (g.lock != null) {
                g.lock = null;
            } else {
                g.lock = acquireLock(g);
                if (g.lock == null and rl.isGamepadAvailable(PAD)) g.rig.recenter(g.hero.facing);
            }
        }
        if (g.lock) |li| {
            if (!lockValid(g, li)) {
                g.lock = null;
            } else if (canSee(g, li)) {
                g.lockBlind = 0;
            } else {
                g.lockBlind += rawDt;
                if (g.lockBlind >= LOCK_BLIND_HOLD) g.lock = null;
            }
        } else {
            g.lockBlind = 0;
        }

        const inside = rl.isWindowFocused() and rl.isCursorOnScreen();
        const md = rl.getMouseDelta();
        const wheel = rl.getMouseWheelMove();
        const padRX: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_x) else @as(f32, 0);
        const padRY: f32 = if (rl.isGamepadAvailable(PAD)) rl.getGamepadAxisMovement(PAD, .right_y) else @as(f32, 0);
        const yawBefore = g.rig.yaw;
        // RAW stick magnitude, before any deadzone.
        const padMag = @sqrt(padRX * padRX + padRY * padRY);
        // …and the whole look SLOWS as the bow comes up, eased on the same blend the view rides in on.
        const lookScale = mathx.lerpF(1.0, AIM_LOOK_SCALE, mathx.clampF(g.rig.aimB, 0, 1));
        if (activeLock(g)) |li| {
            const dir = mathx.dirXZ(g.hero.pos, foePos(g, li));
            if (mathx.lenXZ(dir) > 0.001) {
                g.rig.aim(mathx.headingXZ(dir), lockPitch(g, li), dt, LOCK_CAM_EASE);
            }
            var flick: f32 = 0;
            if (inside and wasInside and @abs(md.x) > LOCK_FLICK_MOUSE) flick = std.math.sign(md.x);
            if (@abs(padRX) > LOCK_FLICK) flick = std.math.sign(padRX);
            if (flick != 0 and lockCycleReady) {
                cycleLock(g, flick);
                lockCycleReady = false;
            } else if (@abs(md.x) < LOCK_REARM_MOUSE and @abs(padRX) < LOCK_REARM_STICK) {
                lockCycleReady = true;
            }
        } else {
            // …and the two devices are latched apart: a mouse-emulation layer can put a stick on the OS cursor.
            const look = stickRadial(padRX, padRY, LOOK_DEADZONE, LOOK_CURVE);
            const mouseLook = inside and wasInside and (@abs(md.x) + @abs(md.y)) > MOUSE_WAKE;
            // …and CLAIMING needs more than merely clearing the deadzone, or a worn stick pins the latch to PAD.
            const padClaim = padMag > LOOK_CLAIM;
            // …and LAST DEVICE WINS has to be resolved as a TIE, not by statement order.
            if (padClaim and !mouseLook) lookPad = true;
            if (mouseLook and !padClaim) lookPad = false;
            if (lookPad) {
                g.rig.orbit(
                    -look.x * look.mag * LOOK_RATE_YAW * lookScale * rawDt,
                    look.y * look.mag * LOOK_RATE_PITCH * lookScale * rawDt,
                );
            } else if (inside and wasInside) {
                g.rig.rotate(md.x * lookScale, md.y * lookScale);
            }
        }
        g.probe = .{
            .mdx = md.x,
            .mdy = md.y,
            .rx = padRX,
            .ry = padRY,
            .mag = padMag,
            // Wrapped: yaw lives in (−pi, pi] so a turn across the seam is a small delta, not a full circle.
            .dyaw = mathx.degrees(mathx.wrapPi(g.rig.yaw - yawBefore)),
            .pad = lookPad,
        };
        wasInside = inside;
        if (wheel != 0) g.rig.zoom(wheel);

        // D-PAD RIGHT / Q: cycle the right-hand armament.
        const swapReq = rl.isKeyPressed(.q) or padPressed(.left_face_right);
        if (swapReq and g.hero.swapArm()) sfx.play(.flask_cycle);

        // D-PAD LEFT / F: cycle the LEFT-hand armament — shield or wand.
        const offReq = rl.isKeyPressed(.f) or padPressed(.left_face_left);
        if (offReq and g.hero.swapOff()) sfx.play(.flask_cycle);

        const drinkReq = rl.isKeyPressed(.r) or padPressed(QUICK_PAD);
        const cycleReq = rl.isKeyPressed(.t) or padPressed(.left_face_down);
        if (cycleReq and !g.hero.dead) {
            g.hero.cycleQuick();
            sfx.play(.flask_cycle);
        }

        // D-PAD UP / G: cycle the SPELL — every cross direction changes the slot it is shown in.
        const spellReq = rl.isKeyPressed(.g) or padPressed(.left_face_up);
        if (spellReq and g.hero.cycleSpell()) sfx.play(.flask_cycle);

        const arrowReq = rl.isKeyPressed(ARROW_KEY);
        if (arrowReq and g.hero.cycleArrow()) sfx.play(.flask_cycle);

        const useReq = rl.isKeyPressed(INTERACT_KEY) or padPressed(INTERACT_PAD);
        if (useReq and !g.hero.dead) interact(g);

        // Dodge roll: Space, or a short TAP of Circle/B (holding B sprints instead).
        var rollReq = rl.isKeyPressed(.space);
        const bDown = padDown(hud_.padOf(hud_.BTN_BACK)); // B is the roll/sprint button, named once in hud
        if (bDown) {
            bHeldT += rawDt; // REAL time: tap-vs-hold is a wall-clock decision, unaffected by debug time-scale
        } else {
            if (bWasDown and bHeldT < ROLL_TAP_MAX) rollReq = true;
            bHeldT = 0;
        }
        bWasDown = bDown;

        const l1Held = rl.isMouseButtonDown(.right) or padDown(.left_trigger_1);
        const l1Press = rl.isMouseButtonPressed(.right) or padPressed(.left_trigger_1);
        const l2Held = rl.isMouseButtonDown(.right) or padDown(.left_trigger_2);
        const l2Press = rl.isKeyPressed(PARRY_KEY) or padPressed(.left_trigger_2);
        const shiftDown = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
        const lmbPress = rl.isMouseButtonPressed(.left);
        const lmbDown = rl.isMouseButtonDown(.left);
        const r1 = padPressed(.right_trigger_1) or (lmbPress and !shiftDown);
        const r2 = padPressed(.right_trigger_2) or (lmbPress and shiftDown);
        const r1Held = padDown(.right_trigger_1) or (lmbDown and !shiftDown);
        const r2Held = padDown(.right_trigger_2) or (lmbDown and shiftDown);

        const rightHeld: heromod.Armament = g.hero.armInHand();
        const leftHeld: ?heromod.Armament = if (g.hero.offInHand()) g.hero.off else null;

        var acts = Acts{};
        handActs(rightHeld, .{ .press1 = r1, .press2 = r2, .held1 = r1Held, .held2 = r2Held }, &acts);
        if (leftHeld) |la| handActs(la, .{ .press1 = l1Press, .press2 = l2Press, .held1 = l1Held, .held2 = l2Held }, &acts);
        const lightReq = acts.light;
        const heavyReq = acts.heavy;
        const quickReq = acts.quick;
        const aimedReq = acts.aimed;
        const ringReq = acts.ring;
        const castReq = acts.cast;
        const guardHeld = acts.guard;
        const aimHeld = acts.aim;
        const parryReq = acts.parry;

        // Stamina gates the sprint at the SOURCE, so `sprintingMove` stays the one definition of a sprint.
        var mv = gatherMove();
        if (!g.hero.stam.canSprint()) mv.speed = @min(mv.speed, RUN_SPEED);
        const wade = wadeDrag(g);
        if (wade < 1.0) mv.speed = @min(mv.speed, WALK_SPEED * wade);
        g.hero.vit.tick(dt);
        g.hero.regen.tick(dt, &g.hero.vit);
        g.hero.tickTimed(dt);
        g.hero.tickFlash(dt);
        // Once a frame rather than at each site that can empty the bag: a per-site list is one to forget from.
        g.hero.quick.dropEmpty(&g.bag);
        const jumpReq = rl.isKeyPressed(JUMP_KEY) or padPressed(JUMP_PAD);
        // Action input is dead while staggered or dead (a reaction is committed).
        if (!g.hero.dead and !g.hero.staggered()) {
            if (rollReq) {
                g.hero.requestRoll(rollDir(g, mv));
            } else if (jumpReq) {
                if (g.hero.startJump(rollDir(g, mv), mv.speed)) sfx.play(.jump);
            } else if (parryReq) {
                if (g.hero.requestParry()) sfx.play(.swing_light);
            } else if (heavyReq) {
                g.hero.requestAttack(.heavy);
            } else if (lightReq) {
                g.hero.requestAttack(.light);
            } else if (aimedReq) {
                g.hero.requestShot(true);
            } else if (quickReq) {
                g.hero.requestShot(false);
            } else if (castReq) {
                // At the RAISE, not the throw: `wand_charge` climbs, and resolves about where the bolt goes.
                if (g.hero.requestCast()) sfx.play(.wand_charge);
            } else if (ringReq) {
                ringBell(g);
            }
            g.hero.steerQueuedRoll(rollDir(g, mv));
            if (drinkReq) quickUse(g);
        }
        g.hero.sprinting = sprintingMove(mv) and !g.hero.committed() and !g.hero.dead and !g.hero.staggered();
        // …and the shield AFTER the sprint (there is no running block — see `hero.setGuard`).
        g.hero.setGuard(guardHeld);
        g.hero.setAim(aimHeld);
        // Shield, bow and draught are each a SHUFFLE rather than a stop, denied at the SOURCE like the sprint.
        // …and a DOOR is slower to walk behind than a small shield (`item.Arm.walk`).
        if (g.hero.guarding) mv.speed = @min(mv.speed, WALK_SPEED * heromod.GUARD_SPEED * g.hero.guardWalk());
        if (g.hero.aiming) mv.speed = @min(mv.speed, WALK_SPEED * heromod.BOW_AIM_SPEED);
        if (g.hero.drinking) mv.speed = @min(mv.speed, WALK_SPEED * heromod.DRINK_SPEED);

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        const faceYaw: ?f32 = if (g.hero.aiming) g.rig.yaw else lockYaw;
        g.hero.aimAtPitch(meleePitch(g));
        leanToGround(g, dt);
        const heroWas = g.hero.pos;
        const heroAfoot = !g.hero.dead;
        if (g.hero.dead) {
            g.hero.updateDeath(dt);
            // The frame he returns, the WORLD reloads with him (ER-style).
            if (!g.hero.dead) resetFoes(g);
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt);
        } else if (g.hero.airborne()) {
            moveHeroAir(g, dt, mv, faceYaw);
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.drinking) {
            g.hero.tickDrink(dt);
            moveHero(g, dt, if (g.hero.drinking) mv else .{}, faceYaw);
        } else if (g.hero.attacking) {
            g.hero.updateAttack(dt, PLAY_HALF, faceYaw);
        } else if (g.hero.parrying) {
            g.hero.updateParry(dt, faceYaw); // PLANTED, like the cast — catching a blow is a standing job
        } else if (g.hero.shooting) {
            g.hero.updateShot(dt, faceYaw);
        } else if (g.hero.ringing) {
            g.hero.updateRing(dt, faceYaw); // PLANTED, like the cast — calling something is a standing job
        } else if (g.hero.casting) {
            g.hero.updateCast(dt, faceYaw); // PLANTED, like a quick shot — both hands are busy
            // Pulsed EVERY frame, since a `rumble.Event` can only decay from its peak (`rumble.castCharge`).
            g.rumble.play(rumblemod.castCharge(g.hero.chargeFill()));
        } else {
            moveHero(g, dt, mv, faceYaw);
        }
        // Deep water is a wall, taken ONCE here rather than at each of the eight branches above.
        if (heroAfoot) gateHeroWater(g, heroWas);
        var wasPos: [FOE_GROUPS.len][FOE_CAP]rl.Vector3 = undefined;
        var wasN: [FOE_GROUPS.len]usize = undefined;
        inline for (FOE_GROUPS, 0..) |f, gi| {
            const row = @field(g, f.field).live();
            wasN[gi] = row.len;
            snapshotPos(row, &wasPos[gi]);
        }
        // Each on the ONE frame its own edge says so. The bell's is the NOTE, not the arm coming down.
        if (g.hero.loosed) looseShaft(g);
        if (g.hero.thrown) releaseSpell(g);
        if (g.hero.rang) summonSpirit(g);
        const hitsBefore = allHits(g);
        markSight(g);
        markThreat(g, dt);
        markWays(g);
        markWade(g);
        markParry(g);
        markVigil(g);
        // ONE snapshot of the blade for every group this frame — re-derived per group, the three disagree.
        const bladeNow = heroBlade(g);
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            // The lunge carries stance damage; the chomp doesn't — split the felt blow by that.
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= ogremod.SLAM_HIT.stance, true);
        }
        for (g.line.live()) |*a| {
            if (a.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), heroAimPoint(g));
            }
        }
        if (g.band.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnClump)) |b| {
            _ = heroTakes(g, b, b.hit.poise >= koboldmod.ZERK_HIT.poise, true);
        }
        // The skeletal warriors. Only the greatsword's diagonal carries stance, so that is the split.
        if (g.muster.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // The shade's touch is the only blow it deals in person — the wisp goes through the quiver.
        if (g.haunt.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnWisp)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.swarm.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, leechSip)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        g.hook = null;
        if (g.grove.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, noteYank)) |b| {
            applyYank(g, heroTakes(g, b, b.hit.heavy(), true));
        }
        // The sporeling's bonk is a blow; its cloud is a HOLD, billed further down beside the mother's acid.
        if (g.cluster.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.warrens.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= delvermod.BURST_HIT.stance, true);
        }
        if (g.warrens.anySurged()) {
            g.rumble.play(rumblemod.hit_heavy);
            g.rig.addShake(SHAKE_SURGE);
        }
        if (g.rite.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.thicket.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // **THE CREATURE SAYS WHEN AND THIS SAYS IT** (the spirit's arrangement) — a creature that called
        // `sfx` itself would be one that plays through the pause card and the shot harness. Five one-frame
        // edges, cleared at the top of its own update.
        for (g.thicket.live()) |*r| {
            if (r.opened) sfx.world(.ravager_bloom, r.pos);
            if (r.leapt) sfx.world(.ravager_leap, r.pos);
            if (r.snapped) sfx.world(.ravager_snap, r.pos);
            if (r.yelped) sfx.world(.ravager_hurt, r.pos);
            if (r.justDied) sfx.world(.ravager_die, r.pos);
        }
        if (g.ring.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // **THE MAGE'S BLOW IS NOT ITS OWN** — the ball goes into the shared pool and arrives seconds later,
        // so the creature's `update` above can only ever return null. What it hands over here is the FLAG and
        // the point it left from; everything after that belongs to `archer`.
        for (g.ring.live()) |*k| {
            if (k.kindled) sfx.world(.mage_kindle, k.pos);
            if (k.yelped) sfx.world(.mage_hurt, k.pos);
            if (k.justDied) sfx.world(.mage_die, k.pos);
            if (k.lobbed) {
                sfx.world(.mage_throw, k.lobFrom);
                spawnEmber(g, k.lobFrom);
            }
        }
        if (g.marsh.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // …and its FIVE one-frame edges. The creature says WHEN; `game.zig` owns the speaker.
        for (g.marsh.live()) |*l| {
            if (l.broke) sfx.world(.lurker_break, l.pos);
            if (l.lashed) sfx.world(.lurker_lash, l.pos);
            if (l.sank) sfx.world(.lurker_sink, l.pos);
            if (l.yelped) sfx.world(.lurker_hurt, l.pos);
            if (l.justDied) sfx.world(.lurker_die, l.pos);
        }
        applyRaises(g);
        if (g.rite.anyLaid()) {
            g.rumble.play(rumblemod.swing_light);
            g.rig.addShake(SHAKE_SIGIL);
        }
        if (g.vigil.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= knightmod.CHARGE_HIT.stance, true);
        }
        if (g.vigil.gasDose(dt, g.hero.pos)) |b| {
            _ = heroTakes(g, b, false, false);
            sfx.play(.acid_burn);
        }
        {
            const q = g.vigil.quakeAmt();
            if (q > 0) {
                g.rumble.play(rumblemod.hit_heavy);
                g.rig.addShake(q);
            }
        }
        // …and the one moment of theirs the frame should feel BEFORE it is hit by it.
        if (g.muster.anyLeapt()) {
            g.rumble.play(rumblemod.swing_heavy);
            g.rig.addShake(SHAKE_SKEL_LEAP);
        }
        const hatchesBefore = g.brood.hatches;
        const burstsBefore = g.brood.bursts;
        if (g.brood.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnVenom)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.brood.hatches != hatchesBefore) {
            g.rumble.play(rumblemod.hit_heavy);
            g.rig.addShake(SHAKE_HATCH);
        }
        if (g.brood.bursts != burstsBefore) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_SAC_BURST);
            // A sac carries no `justDied` edge for `billDeaths` to read; her counter is the edge.
            var burst = burstsBefore;
            while (burst < g.brood.bursts) : (burst += 1) g.trig.died(.brood_sac);
        }
        // Read AFTER every group has updated, so one beat covers the whole field.
        if (anyParried(g)) parryBeat(g);
        // Two `add` calls and not a max: standing in spores and acid at once is two bad decisions.
        g.hero.poisonBy(g.brood.burn(dt, g.hero.pos));
        g.hero.poisonBy(g.cluster.spores(dt, g.hero.pos));
        _ = g.hero.tickPoison(dt);
        if (g.hero.poison.justProcced) {
            sfx.play(.acid_burn);
            g.rig.addShake(SHAKE_HURT);
            g.rumble.play(rumblemod.hurt);
            g.hero.hurtFlash = mathx.maxF(g.hero.hurtFlash, 0.7); // the ONE flash the poison gets
        }
        tickPack(g, dt);
        g.chests.update(dt, g.hero.pos);
        g.pickups.update(dt, g.hero.pos);
        hidePickups(g); // …and a taken glow stops being drawn as it shrinks out
        g.award.update(dt);
        // The folk take the same terrain gate the foes do.
        var wasFolk: [npcmod.CAP]rl.Vector3 = undefined;
        const nFolk = g.folk.n;
        snapshotPos(g.folk.live(), &wasFolk);
        g.folk.update(dt, g.hero.pos, PLAY_HALF);
        gateTerrain(g, g.folk.live(), wasFolk[0..nFolk]);
        inline for (FOE_GROUPS, 0..) |f, gi| gateTerrain(g, @field(g, f.field).live(), wasPos[gi][0..wasN[gi]]);
        inline for (FOE_GROUPS, 0..) |f, gi| gateChill(@field(g, f.field).live(), wasPos[gi][0..wasN[gi]]);
        if (g.hero.breathLive()) rimeBreathe(g, dt);
        for (&g.arrows) |*ar| {
            if (!ar.live) continue;
            flyArrow(g, ar, dt);
            if (ar.hit) {
                const blow = foemod.Blow{
                    .hit = ar.blow,
                    .from = mathx.addV(g.hero.pos, mathx.scaleV(ar.vel, -1)),
                };
                const out: combat.HitOutcome = if (g.hero.dead) .ignored else heroTakes(g, blow, blow.hit.heavy(), false);
                // …and WHAT IT STRUCK picks that voice: boards if the shield caught it, flesh if not.
                if (out == .taken or out == .ignored) sfx.play(.arrow_hit);
                splashOf(g, ar);
            } else planted(g, ar);
        }
        // Blade connected this frame (a foe's hit count climbed) → pulse + frame crack sized to the swing.
        if (allHits(g) > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
            sfx.play(if (g.hero.atkHeavy) .hit_heavy else .hit_light);
            // **THE SIGNET FEEDS OFF A SWING OF HIS, AND `attacking` IS WHAT SAYS IT WAS HIS.** This edge is a
            // SUM over every foe's hit count, and inside this window exactly two things can move it: his own
            // blade and the WOLF'S JAWS (a shaft's hit lands after `stepShafts`, below, so it is never in here).
            // Ungated, the signet healed him every time his spirit bit something while he stood still.
            if (g.hero.attacking) _ = g.hero.drinkLeech();
        }
        stepShafts(g, dt);
        // **AFTER BOTH QUIVERS HAVE FLOWN**, so one pass covers every ball in the sky whoever threw it — the
        // flag is one frame wide and set inside `archer`'s own step, so a pass that ran before `stepShafts`
        // would silently miss anything bouncing out of HIS hands the day he gets one.
        emberBounces(g);
        if (anyFoeDied(g)) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_KILL);
            // A THUD, and nothing else (owner's call — no bell, no jingle).
            sfx.play(.kill);
        }
        g.hero.souls.gain(allSouls(g));
        // The lock leaves a corpse the FRAME it dies, snapping to the next valid target.
        if (g.lock) |li| {
            if (!foeLockable(g, li)) g.lock = acquireLock(g);
        }
        collideActors(g, dt);
        groundActor(g, &g.hero.pos, dt);
        inline for (FOE_GROUPS) |f| {
            for (@field(g, f.field).live()) |*a| groundActor(g, &a.pos, dt);
        }
        for (g.folk.live()) |*p| groundActor(g, &p.pos, dt);
        for (g.pack.live()) |*w| groundActor(g, &w.pos, dt);
        // THE SCRIPT LAYER LAST, so `deaths` and `alive` are this frame's answers and not the previous one's.
        tickTriggers(g, dt);
        g.rig.tickShake(rawDt);
        // Both BEFORE the follow, or the eye is a frame behind the man it is pointed at.
        g.rig.aimB = g.hero.aimB;
        g.rig.tickLift(g.hero.lift, dt);
        g.rig.followClear(g.hero.shoulderPoint(), &g.env, envGroundAt);
        sfx.listen(g.rig.cam.position, g.rig.rightXZ());
        sfx.ambience(rawDt);
        footsteps(g, &lastPhase);

        // Rising-edge action pulses: roll whump, swing effort (heavy > light), death swell.
        if (g.hero.rolls != wasRolls) {
            g.rumble.play(rumblemod.roll);
            sfx.play(.roll);
            wasRolls = g.hero.rolls;
        }
        if (g.hero.landed) {
            g.rumble.play(rumblemod.land);
            g.rig.addShake(SHAKE_LAND);
            sfx.playAt(.land, 1.0);
            if (stepOverlay(g, g.hero.pos.x, g.hero.pos.z)) |over| sfx.playAt(over, 1.0);
        }
        if (g.hero.swings != wasSwings) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.swing_heavy else rumblemod.swing_light);
            sfx.play(if (g.hero.atkHeavy) .swing_heavy else .swing_light);
            wasSwings = g.hero.swings;
        }
        if (g.hero.aiming and !wasAiming) sfx.play(.bow_draw);
        wasAiming = g.hero.aiming;
        if (g.hero.stamRefused > wasRefused) sfx.play(.refused);
        wasRefused = g.hero.stamRefused;
        // The stagger is its own beat: the blow that caused it already played, this is his footing going.
        if (g.hero.stun == .heavy and wasStun != .heavy) sfx.play(.stagger);
        wasStun = g.hero.stun;
        if (g.hero.dead and !wasDead) {
            g.rumble.play(rumblemod.death);
            g.rig.addShake(SHAKE_DEATH);
            sfx.play(.death);
            // On the frame he DIES rather than on the respawn, so the spill plays under the YOU DIED card.
            spillSouls(g);
        }
        if (!g.hero.dead and wasDead) sfx.play(.respawn);
        // The YOU DIED tail: armed while dead, drains after the respawn (fade from black).
        if (g.hero.dead) {
            g.deathFade = RESPAWN_HOLD + RESPAWN_FADE;
        } else if (g.deathFade > 0) {
            g.deathFade -= rawDt;
        }
        wasDead = g.hero.dead;
        g.rumble.update(rawDt, rl.isGamepadAvailable(PAD));

        drawScene(g);
        hud(g, rawDt);
        tickEnter(g, rawDt);
        drawEnterFade(g);
        rl.endDrawing();
    }
}

fn footsteps(g: *Game, last: *f32) void {
    const h = &g.hero;
    if (h.moving < 0.45 or h.rolling or h.airborne() or h.dead or h.staggered()) {
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
    const vol = mathx.clampF(0.45 + 0.55 * h.speed / SPRINT_SPEED, 0.35, 1.0);
    sfx.playAt(id, vol);
    if (stepOverlay(g, h.pos.x, h.pos.z)) |over| sfx.playAt(over, vol);
}

/// WHAT HE IS STANDING ON, as an extra voice STACKED on the boot rather than a boot of its own.
fn stepOverlay(g: *const Game, x: f32, z: f32) ?sfx.Id {
    if (g.env.inWater(x, z, 1.0)) return .step_water;
    const i = g.map.soilIndex(x, z) orelse return null;
    const v = g.map.soil[i];
    if (v >= worldfmt.Soil.N) return null;
    return switch (@as(worldfmt.Soil, @enumFromInt(v))) {
        .stone => .step_stone,
        .none, .dirt, .turf, .silt, .ash, .moss => null, // the plain boot carries all of these
    };
}

fn heroHurtBeat(g: *Game, heavy: bool, voice: bool) void {
    g.rumble.play(if (heavy) rumblemod.hurt_heavy else rumblemod.hurt);
    g.rig.addShake(if (heavy) SHAKE_HURT_HEAVY else SHAKE_HURT);
    if (voice) sfx.play(if (heavy) .hurt_heavy else .hurt);
}

/// Borrows the live state rather than a copy, so nothing on those pages can be a frame behind.
pub fn bookView(g: *Game) bookmod.View {
    return .{
        .bag = &g.bag,
        .sheet = &g.hero.sheet,
        .res = &g.hero.vit.res,
        .flasks = &g.hero.flasks,
        .quick = &g.hero.quick,
        .quiver = &g.hero.quiver,
        .tree = &g.tree,
        .inCombat = inCombat(g),
        .arm = g.hero.arm,
        .off = g.hero.off,
        .armAlt = g.hero.armAlt,
        .offAlt = g.hero.offAlt,
        .spell = g.hero.spell,
        .fp = g.hero.fp.cur,
        .souls = g.hero.souls.display(),
        .worn = g.hero.worn,
    };
}

/// **A HAND ROW IS TWO DECISIONS AND BOTH ARE TAKEN HERE** — what kind of thing is in that fist, and which one
/// of it he owns (`book.Hand`). The armament may be REFUSED (`hero.equip` says no mid-swing); the variant is not
/// a thing in his hands changing, so it goes through regardless — otherwise picking the club while committed
/// would leave the socket saying club and the fist swinging a sword.
fn takeHand(g: *Game, hand: usize, slot: usize, h: bookmod.Hand) void {
    _ = g.hero.equip(hand, slot, h.a);
    if (heromod.wearFor(h.a)) |w| _ = g.hero.wear(w, h.kind);
}

fn bookAct(g: *Game, a: bookmod.Action) void {
    switch (a) {
        .none => {},
        .use => |k| useItem(g, k),
        .arm => |h| takeHand(g, heromod.RIGHT, 0, h),
        .armAlt => |h| takeHand(g, heromod.RIGHT, 1, h),
        .off => |h| takeHand(g, heromod.LEFT, 0, h),
        .offAlt => |h| takeHand(g, heromod.LEFT, 1, h),
        .wear => |wr| _ = g.hero.wear(wr.slot, wr.kind),
        .ammo => |k| while (g.hero.quiver.sel != k) {
            if (!g.hero.cycleArrow()) break;
        },
        .quick => |q| {
            g.hero.quick.put(q.slot, q.kind);
            g.hero.syncFlask();
        },
    }
}

pub fn applyTree(g: *Game) void {
    g.hero.applyPerks(g.tree.bonus());
}

/// ONE HAND'S TWO BUTTONS, as levels and edges — the pair is the same shape whichever hand it is.
const HandIn = struct { press1: bool, press2: bool, held1: bool, held2: bool };

const Acts = struct {
    light: bool = false,
    heavy: bool = false,
    quick: bool = false,
    aimed: bool = false,
    ring: bool = false,
    cast: bool = false,
    guard: bool = false,
    parry: bool = false,
    aim: bool = false,
};

fn handActs(a: heromod.Armament, in: HandIn, out: *Acts) void {
    switch (a) {
        .sword => {
            out.light = out.light or in.press1;
            out.heavy = out.heavy or in.press2;
        },
        .bow => {
            out.quick = out.quick or in.press1;
            out.aimed = out.aimed or in.press2;
            out.aim = out.aim or in.held2;
        },
        // R2 IS DELIBERATELY DEAD ON THE BELL (owner's call): not having an attack IS what it costs to carry.
        .bell => out.ring = out.ring or in.press1,
        .shield => {
            out.guard = out.guard or in.held1;
            out.parry = out.parry or in.press2;
        },
        .wand => out.cast = out.cast or in.press1,
    }
}

fn armSlot(a: heromod.Armament) hud_.Slot {
    return switch (a) {
        .sword => .sword,
        .bow => .bow,
        .bell => .bell,
        .shield => .shield,
        .wand => .wand,
    };
}

fn quickLeft(g: *const Game) u8 {
    const k = g.hero.quick.selected() orelse return 0;
    return combat.quickCount(k, &g.hero.flasks, &g.bag);
}

fn quickUse(g: *Game) void {
    const k = g.hero.quick.selected() orelse return;
    if (combat.flaskOf(k)) |f| {
        g.hero.flasks.sel = f;
        if (g.hero.startDrink()) sfx.play(.flask_drink);
        return;
    }
    useItem(g, k);
}

fn useItem(g: *Game, k: item.Kind) void {
    if (g.hero.dead) return;
    switch (item.use(k)) {
        .none => {},
        // The POTENCY comes off the effect, so a second edible brings its own (see `item.Use`).
        .regen => |r| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.regen.start(g.hero.vit.hpMax * r.frac, r.secs);
            sfx.play(.eat);
        },
        .lob => |l| {
            if (g.bag.take(k, 1) == 0) return;
            const from = mathx.addV(heroAimPoint(g), mathx.scaleV(mathx.headingDir(g.hero.facing), 0.4));
            const hit = combat.Hit{ .dmg = l.dmg, .poise = l.poise, .elem = combat.elems(.{ .fire = l.fire, .lightning = l.lightning }) };
            const shot: archermod.Shot = if (l.lightning > 0) .crock else .clump;
            putIn(&g.shafts, archermod.launchShaft(from, camAimPoint(g), koboldmod.CLUMP_SPEED, hit, true, shot));
            sfx.play(.wand_cast);
        },
        .ward => |w| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.startWard(w.chaos, w.secs);
            sfx.play(.eat);
        },
        .wind => |w| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.stam.secondWind(w.share);
            sfx.play(.flask_drink);
        },
        .grease => |gr| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.startGrease(gr.frac, gr.secs);
            sfx.play(.eat);
        },
        .souls => |s| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.souls.gain(s.n);
            sfx.play(.souls_take);
        },
        .brew => |b| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.stam.startBrew(b.mult, b.secs);
            sfx.play(.flask_drink);
        },
        // **SPENT EVEN ON A CLEAN MAN**, which is the flask's own rule and not an oversight: a leaf that
        // refused unless you were already poisoned would be a leaf you can only ever use too late, since the
        // meter you want to answer is the one that is still filling.
        .purge => {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.purgePoison();
            sfx.play(.eat);
        },
        .steady => |s| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.startSteady(s.mult, s.secs);
            sfx.play(.flask_drink);
        },
    }
}

fn heroTakes(g: *Game, b: foemod.Blow, heavy: bool, voice: bool) combat.HitOutcome {
    if (b.on == .spirit) return spiritTakes(g, b, heavy);
    const out = g.hero.takeHit(b.hit, mathx.dirXZ(g.hero.pos, b.from));
    switch (out) {
        .ignored => {}, // rolled through it, or he was already gone
        .taken => heroHurtBeat(g, heavy, voice),
        .blocked => heroBlockBeat(g, b.hit),
        .guardBroken => {
            g.hero.blockSparks(1.0);
            g.rumble.play(rumblemod.guard_break);
            g.rig.addShake(SHAKE_GUARD_BREAK);
            sfx.play(.guard_break);
        },
    }
    return out;
}

fn spiritTakes(g: *Game, b: foemod.Blow, heavy: bool) combat.HitOutcome {
    for (g.pack.live()) |*w| {
        if (!foemod.corporeal(w)) continue;
        const out = w.takeHit(b.hit);
        if (out == .taken) {
            const dir = mathx.dirXZ(b.from, w.pos);
            if (mathx.lenXZ(dir) > 1e-3) {
                w.shove = mathx.scaleV(mathx.normV(dir), if (heavy) wolfmod.SHOVE.heavy else wolfmod.SHOVE.light);
            }
        }
        break; // one spirit, and `SUMMON_MAX` is what says so
    }
    return .ignored;
}

fn heroBlockBeat(g: *Game, h: combat.Hit) void {
    const w = mathx.clampF(h.raw() / BLOW_HEAVIEST, BLOCK_FELT_MIN, 1.0);
    g.rumble.play(if (w >= BLOCK_FELT_HEAVY) rumblemod.guard_block_heavy else rumblemod.guard_block);
    g.rig.addShake(SHAKE_BLOCK * w);
    g.hero.blockSparks(w);
    sfx.playAt(.guard_block, mathx.lerpF(BLOCK_VOICE_MIN, 1.0, w));
}
/// How quiet the lightest thing the boards ever stop is, against the heaviest.
const BLOCK_VOICE_MIN: f32 = 0.55;

fn allHits(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f.field).totalHits();
    return n;
}
fn allAlive(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f.field).aliveCount();
    return n;
}
fn anyFoeDied(g: *const Game) bool {
    inline for (FOE_GROUPS) |f| {
        if (@field(g, f.field).anyDied()) return true;
    }
    return false;
}
fn allSouls(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f.field).soulsDropped();
    return n;
}

/// Metres: how far out something is still worth folding a flat cut down onto.
const MELEE_AIM_R: f32 = 3.6;
/// A FIXED target is worth stooping for from further out than a swept one: he has SAID which body he means.
const MELEE_AIM_LOCKED: f32 = 2.0 * MELEE_AIM_R;
/// …and it must be in FRONT: cos of the half-angle off his facing.
const MELEE_AIM_DOT: f32 = 0.35;
/// The eye line the pitch is measured FROM — his shoulders, which is roughly where the flat arc lives.
const MELEE_AIM_EYE: f32 = 1.35;

const MarkCtx = struct {
    g: *const Game,
    fwd: rl.Vector3,
    best: ?rl.Vector3 = null,
    bestD: f32 = MELEE_AIM_R,

    fn visit(self: *MarkCtx, foes: anytype, _: ?FoeKind) void {
        for (foes) |*f| {
            if (!f.alive() or f.dying()) continue;
            if (disguised(f)) continue;
            const d = mathx.distXZ(self.g.hero.pos, f.pos);
            if (d >= self.bestD) continue;
            const to = mathx.dirXZ(self.g.hero.pos, f.pos);
            if (d > 0.2 and to.x * self.fwd.x + to.z * self.fwd.z < MELEE_AIM_DOT) continue;
            self.bestD = d;
            self.best = f.lockPoint();
        }
    }
};

fn meleeMark(g: *const Game) ?rl.Vector3 {
    if (activeLock(g)) |li| {
        if (mathx.distXZ(g.hero.pos, foePos(g, li)) <= MELEE_AIM_LOCKED) return foeLockPoint(g, li);
    }
    var ctx = MarkCtx{ .g = g, .fwd = mathx.headingDir(g.hero.facing) };
    eachTarget(g, &ctx, MarkCtx.visit);
    return ctx.best;
}

fn meleePitch(g: *const Game) ?f32 {
    const mark = meleeMark(g) orelse return null;
    const flat = mathx.distXZ(g.hero.pos, mark);
    if (flat < 0.35) return null;
    return mathx.degrees(std.math.atan2(g.hero.pos.y + MELEE_AIM_EYE - mark.y, flat));
}

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

fn inBounds(p: rl.Vector3) rl.Vector3 {
    return mathx.clampXZ(p, PLAY_HALF);
}

fn collideActors(g: *Game, dt: f32) void {
    const step = COLLIDE_RATE * dt; // max correction this frame — bigger pushes ease in (no warp)
    var hp = g.env.resolveActor(g.hero.pos, HERO_R, g.hero.footY());
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*a| {
            if (foemod.corporeal(a) and !a.airborne() and !phased(a) and g.hero.footY() < a.topWorld().y) {
                hp = collision.pushOutCircle(hp, HERO_R, a.pos, a.bodyR());
            }
        }
    }
    // A person is a BODY: you walk into a wanderer, never through one, and no jump in this game clears a man.
    for (g.folk.liveConst()) |*p| hp = collision.pushOutCircle(hp, HERO_R, p.pos, p.bodyR());
    // …and so is a spirit: one you can stand inside reads as a projection rather than as a body.
    for (g.pack.liveConst()) |*w| {
        if (foemod.corporeal(w)) hp = collision.pushOutCircle(hp, HERO_R, w.pos, w.bodyR());
    }
    g.hero.pos = mathx.approachV(g.hero.pos, inBounds(hp), step);

    inline for (FOE_GROUPS) |gr| settleGroup(g, gr, step);

    for (g.folk.live()) |*p| {
        const r = p.bodyR();
        var q = g.env.resolveActor(p.pos, r, p.pos.y); // a wanderer never leaves the ground
        q = collision.pushOutCircle(q, r, g.hero.pos, HERO_R);
        p.pos = mathx.approachV(p.pos, inBounds(q), step);
    }
    for (g.pack.live()) |*w| {
        if (!foemod.corporeal(w)) continue;
        const r = w.bodyR();
        var q = g.env.resolveActor(w.pos, r, w.pos.y);
        q = collision.pushOutCircle(q, r, g.hero.pos, HERO_R);
        w.pos = mathx.approachV(w.pos, inBounds(q), step);
    }
}

fn settleGroup(g: *Game, comptime gr: FoeGroup, step: f32) void {
    const foes = @field(g, gr.field).live();
    for (foes, 0..) |*a, i| {
        // …AND A BODY UNDER THE WATER IS NOT ONE EITHER (`phased`): it is not pushed and it pushes nothing.
        if (!foemod.corporeal(a) or phased(a)) continue;
        const r = a.bodyR();
        if (a.airborne()) {
            a.pos = inBounds(g.env.resolveActor(a.pos, r, a.pos.y));
            continue;
        }
        var p = g.env.resolveActor(a.pos, r, a.pos.y);
        if (gr.vsHero) p = collision.pushOutCircle(p, r, g.hero.pos, HERO_R);
        for (foes, 0..) |*o, j| {
            if (i == j or !foemod.corporeal(o) or o.airborne() or phased(o)) continue;
            p = collision.pushOutCircle(p, r, o.pos, o.bodyR());
        }
        inline for (gr.vs) |other| {
            for (@field(g, other).live()) |*o| {
                if (foemod.corporeal(o) and !o.airborne() and !phased(o)) p = collision.pushOutCircle(p, r, o.pos, o.bodyR());
            }
        }
        a.pos = mathx.approachV(a.pos, inBounds(p), step);
    }
}

const FoeKind = worldfmt.FoeKind;
const FoeRef = struct { kind: FoeKind, idx: usize };
const ROLE_GROUPS = .{
    .{ "band", koboldmod },
    .{ "brood", broodmod },
    .{ "muster", warriormod },
};

fn roleIdx(comptime mod: type, r: FoeRef) ?usize {
    return if (mod.roleOf(r.kind) != null) r.idx else null;
}

const SOLO_GROUPS = blk: {
    var n: usize = 0;
    for (FOE_GROUPS) |gr| {
        if (gr.kind != null) n += 1;
    }
    var out: [n]struct { kind: FoeKind, field: []const u8 } = undefined;
    var i: usize = 0;
    for (FOE_GROUPS) |gr| {
        if (gr.kind) |k| {
            out[i] = .{ .kind = k, .field = gr.field };
            i += 1;
        }
    }
    break :blk out;
};

comptime {
    for (@typeInfo(FoeKind).@"enum".fields) |f| {
        const k: FoeKind = @enumFromInt(f.value);
        var claims: usize = 0;
        for (ROLE_GROUPS) |rg| {
            if (rg[1].roleOf(k) != null) claims += 1;
        }
        if (k == .brood_sac) claims += 1;
        for (SOLO_GROUPS) |s| {
            if (s.kind == k) claims += 1;
        }
        if (claims != 1) @compileError("game: FoeKind." ++ f.name ++ " is claimed by " ++
            std.fmt.comptimePrint("{d}", .{claims}) ++ " groups — a `FoeRef` needs exactly one");
    }
    var nulls: usize = 0;
    for (FOE_GROUPS) |gr| {
        if (gr.kind == null) nulls += 1;
    }
    if (nulls != ROLE_GROUPS.len) @compileError("game: ROLE_GROUPS and the `kind = null` rows of FOE_GROUPS disagree");
    for (ROLE_GROUPS) |rg| {
        var seen = false;
        for (FOE_GROUPS) |gr| {
            if (!std.mem.eql(u8, gr.field, rg[0])) continue;
            if (gr.kind != null) @compileError("game: ROLE_GROUPS names `" ++ rg[0] ++ "`, which FOE_GROUPS gives a single kind");
            seen = true;
        }
        if (!seen) @compileError("game: ROLE_GROUPS names `" ++ rg[0] ++ "`, which is not a FOE_GROUPS field");
    }
}

/// Through `liveConst()` rather than the raw storage array: the tail past `n` is undefined memory.
fn askFoe(comptime T: type, g: *const Game, r: FoeRef, comptime ask: anytype) T {
    inline for (ROLE_GROUPS) |rg| {
        if (roleIdx(rg[1], r)) |i| return ask(&@field(g, rg[0]).liveConst()[i]);
    }
    if (r.kind == .brood_sac) return ask(&g.brood.liveSacsConst()[r.idx]);
    inline for (SOLO_GROUPS) |s| {
        if (r.kind == s.kind) return ask(&@field(g, s.field).liveConst()[r.idx]);
    }
    unreachable; // the comptime partition above is what makes this dead
}
fn foePos(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype) rl.Vector3 {
            return f.pos;
        }
    }.ask);
}
fn foeResists(g: *const Game, r: FoeRef) combat.Resists {
    return askFoe(combat.Resists, g, r, struct {
        fn ask(f: anytype) combat.Resists {
            return f.vit.res;
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
fn foeTopWorld(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype) rl.Vector3 {
            return f.topWorld();
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
/// A Rooted that FOLDS BACK is scenery again, and a lock surviving the fold sits the reticle on a dead tree.
fn foeDisguised(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype) bool {
            return disguised(f);
        }
    }.ask);
}
fn refInBounds(g: *const Game, r: FoeRef) bool {
    inline for (ROLE_GROUPS) |rg| {
        if (roleIdx(rg[1], r)) |i| return i < @field(g, rg[0]).liveConst().len;
    }
    if (r.kind == .brood_sac) return r.idx < g.brood.liveSacsConst().len;
    inline for (SOLO_GROUPS) |s| {
        if (r.kind == s.kind) return r.idx < @field(g, s.field).liveConst().len;
    }
    unreachable;
}
fn lockValid(g: *const Game, r: FoeRef) bool {
    if (!refInBounds(g, r)) return false;
    if (foeDisguised(g, r)) return false;
    return foeLockable(g, r) and mathx.distXZ(g.hero.pos, foePos(g, r)) <= MAX_LOCK_R + LOCK_KEEP_SLACK;
}

/// THE LOCK THE GAME IS ACTING ON — none of it while the bow is up.
fn activeLock(g: *const Game) ?FoeRef {
    return if (g.hero.aiming) null else g.lock;
}

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

fn acquireLock(g: *const Game) ?FoeRef {
    var ctx = LockCtx{ .g = g, .cx = @as(f32, @floatFromInt(rl.getScreenWidth())) * 0.5 };
    eachTarget(g, &ctx, LockCtx.visit);
    return ctx.best;
}

fn memberKind(f: anytype, group: ?FoeKind) FoeKind {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "kind")) return f.kind();
    return group.?;
}

fn disguised(f: anytype) bool {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "hidden")) return f.hidden();
    return false;
}

/// **IS THIS BODY OUT OF THE WAY** — `disguised`'s twin, and DELIBERATELY NOT THE SAME QUESTION. That one is
/// about being seen (the reticle, the bar); this one is about being solid, and the rooted is exactly why they
/// cannot share a predicate: a dormant snag is not a creature to look at and is still a tree you walk into.
/// An opt-in decl (`markWays`' rule), so the seventeen groups that are always solid pay a comptime-false.
fn phased(f: anytype) bool {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "phased")) return f.phased();
    return false;
}

/// How chilled a target is, for its bar — a body opts into the cold by carrying the field (`markWays`' rule).
fn chillOf(f: anytype) f32 {
    if (comptime @hasField(std.meta.Child(@TypeOf(f)), "chill")) return f.chill.frac();
    return 0;
}

test "THE BURROW TAKES THE LOCK OFF YOU, and gives it back when it surfaces" {
    var d = delvermod.Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.2); // stood right over him, so the surge commits at `UNDER_MIN` rather than waiting out
    try std.testing.expect(!disguised(&d)); // on the surface he is an ordinary target

    d.debugDive();
    var t: f32 = 0;
    var wasHidden = false;
    var sawMound = false;
    while (t < 12.0) : (t += 1.0 / 60.0) {
        _ = d.update(1.0 / 60.0, hero, PLAY_HALF, .{});
        try std.testing.expectEqual(d.deep(), disguised(&d));
        if (disguised(&d)) {
            wasHidden = true;
            // …and it is not a creature that has left the field: the ridge of earth is still there to read.
            if (d.mounded()) sawMound = true;
        }
        if (wasHidden and !disguised(&d)) break;
    }
    try std.testing.expect(wasHidden); // it did go under…
    try std.testing.expect(sawMound); // …and it was never invisible, only untargetable
    try std.testing.expect(!disguised(&d)); // …and it came back up a target again
    try std.testing.expect(t < 12.0); // it does not stay down forever (`UNDER_MAX`)
}

// A fresh acquire: nearest to screen-centre, across every target list.
const LockCtx = struct {
    g: *const Game,
    cx: f32,
    best: ?FoeRef = null,
    bestScore: f32 = 1e9,

    fn visit(self: *LockCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            if (!f.alive() or f.dying() or mathx.distXZ(self.g.hero.pos, f.pos) > MAX_LOCK_R) continue;
            if (disguised(f)) continue; // a tree is not a target until it stops being a tree
            const r = FoeRef{ .kind = memberKind(f, kind), .idx = i };
            if (!canSee(self.g, r)) continue; // no fixing on a shape behind a wall
            const sx = lockScreenX(self.g, r) orelse continue;
            const score = @abs(sx - self.cx);
            if (score < self.bestScore) {
                self.bestScore = score;
                self.best = r;
            }
        }
    }
};

// …and the flick: the nearest target PAST the current one, in the flicked direction.
const CycleCtx = struct {
    g: *const Game,
    cur: FoeRef,
    curX: f32,
    dir: f32,
    best: ?FoeRef = null,
    bestGap: f32 = 1e9,

    fn visit(self: *CycleCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            const r = FoeRef{ .kind = memberKind(f, kind), .idx = i };
            if ((self.cur.kind == r.kind and self.cur.idx == i) or !f.alive() or f.dying()) continue;
            if (disguised(f)) continue; // the flick skips what the acquire would not have taken
            if (mathx.distXZ(self.g.hero.pos, f.pos) > MAX_LOCK_R) continue;
            if (!canSee(self.g, r)) continue;
            const sx = lockScreenX(self.g, r) orelse continue;
            const gap = (sx - self.curX) * self.dir;
            if (gap > CYCLE_MIN_GAP and gap < self.bestGap) {
                self.bestGap = gap;
                self.best = r;
            }
        }
    }
};

/// Screen pixels a candidate must sit PAST the current target to count as "the next one".
const CYCLE_MIN_GAP: f32 = 5.0;

fn cycleLock(g: *Game, dir: f32) void {
    const cur = g.lock orelse return;
    const curX = lockScreenX(g, cur) orelse return;
    var ctx = CycleCtx{ .g = g, .cur = cur, .curX = curX, .dir = dir };
    eachTarget(g, &ctx, CycleCtx.visit);
    if (ctx.best) |b| g.lock = b;
}

// The world-reload half of a hero death (ER: dying resets the field).
fn resetFoes(g: *Game) void {
    rehomeFoes(g, .blind);
    clearQuivers(g);
    g.lock = null;
    g.pack.clear();
}

const HURT_BAR_WINDOW = 5.0;

// Floating HP bars over EVERY target (shared foe contract, one walk for all).
const BarCtx = struct {
    cam: rl.Camera3D,
    /// Goes with the RETICLE rather than with `g.lock`, so a suspended lock takes the bar down with the dot.
    lock: ?FoeRef,
    boss: ?usize,

    fn visit(self: *const BarCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            if (!f.alive() or f.dying()) continue; // no bar over a corpse dissolving out
            if (self.boss) |bi| {
                if (bi == i and memberKind(f, kind) == .bone_knight) continue;
            }
            if (disguised(f)) continue;
            const fixed = if (self.lock) |l| l.idx == i and l.kind == memberKind(f, kind) else false;
            if (!fixed and f.vit.sinceHurt > HURT_BAR_WINDOW) continue;
            const s = projectToScreen(self.cam, f.topWorld()) orelse
                projectToScreen(self.cam, f.centerWorld()) orelse continue;
            hud_.foeBar(s.x, s.y, f.vit.hpFrac(), f.staggered(), chillOf(f)); // size/colour/lift/CEILING all live in hud
        }
    }
};

fn drawFoeBars(g: *const Game) void {
    const ctx = BarCtx{ .cam = g.rig.cam, .lock = activeLock(g), .boss = g.vigil.boss(g.hero.pos) };
    eachTarget(g, &ctx, BarCtx.visit);
}

// The glowing white reticle on the locked foe (ER's dot) — 2D + crisp, drawn after the 3D pass.
fn drawLockDot(g: *Game) void {
    const li = activeLock(g) orelse return;
    const s = projectToScreen(g.rig.cam, foeLockPoint(g, li)) orelse return;
    const x: i32 = @intFromFloat(s.x);
    const y: i32 = @intFromFloat(s.y);
    rl.drawCircleGradient(x, y, 15, rgba(255, 255, 255, 175), rgba(255, 255, 255, 0));
    rl.drawCircle(x, y, 2, rl.Color.white);
}
