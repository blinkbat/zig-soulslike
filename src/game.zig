const std = @import("std");
const rl = @import("raylib");
const mathx = @import("core/mathx.zig");
const gfx = @import("gfx/gfx.zig");
pub const daynight = @import("world/daynight.zig");
const envmod = @import("world/env.zig");
const propsmod = @import("props/props.zig");
const worldfmt = @import("world/worldfmt.zig");
const editormod = @import("ui/editor.zig");
const objviewmod = @import("ui/objview.zig");
const heromod = @import("play/hero.zig");
const cameramod = @import("core/camera.zig");
const hud_ = @import("ui/hud.zig");
const menumod = @import("ui/menu.zig");
const bookmod = @import("ui/book.zig");
const countermod = @import("play/counter.zig");
const counterui = @import("ui/counterui.zig");
const frogmod = @import("foes/frog.zig");
const foemod = @import("foes/foe.zig");
const combat = @import("play/combat.zig");
const liquidmod = @import("play/liquid.zig");
const collision = @import("core/collision.zig");
const rumblemod = @import("core/rumble.zig");
const archermod = @import("foes/archer.zig");
const ogremod = @import("foes/ogre.zig");
const shroommod = @import("foes/shroom.zig");
const koboldmod = @import("foes/kobold.zig");
const broodmod = @import("foes/brood.zig");
const warriormod = @import("foes/warrior.zig");
const rootedmod = @import("foes/rooted.zig");
const knightmod = @import("foes/knight.zig");
const duomod = @import("foes/fungalduo.zig");
const delvermod = @import("foes/delver.zig");
const necromod = @import("foes/necro.zig");
const deermod = @import("foes/fungaldeer.zig");
const magemod = @import("foes/shroommage.zig");
const golemmod = @import("foes/sporegolem.zig");
const fenmod = @import("foes/fenlurker.zig");
const skittermod = @import("foes/skitterer.zig");
const priestmod = @import("foes/ancientpriest.zig");
const hollowmod = @import("foes/hollow.zig");
const bloommod = @import("foes/slumberbloom.zig");
const cindermod = @import("foes/cinderwake.zig");
const gorgermod = @import("foes/rotgorger.zig");
const birchmod = @import("foes/birchwight.zig");
const huskmod = @import("foes/salthusk.zig");
const fishmod = @import("foes/fishman.zig");
const batmod = @import("foes/blinkbat.zig");
const leechmod = @import("foes/leechfly.zig");
const shademod = @import("foes/shade.zig");
const chestmod = @import("play/chest.zig");
const pickupmod = @import("play/pickup.zig");
const awardmod = @import("play/award.zig");
const restmod = @import("play/rest.zig");
const soulsmod = @import("play/souls.zig");
const ptree = @import("play/passivetree.zig");
const npcmod = @import("foes/npc.zig");
const wolfmod = @import("foes/wolf.zig");
const trigmod = @import("world/trigger.zig");
const dialogmod = @import("world/dialog.zig");
const item = @import("play/item.zig");
const dropsmod = @import("play/drops.zig");
const weathermod = @import("world/weather.zig");
const savemod = @import("save.zig");
const sfx = @import("core/audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

const PAD = rumblemod.PAD;
const padPressed = rumblemod.padPressed;
const padDown = rumblemod.padDown;

pub const SCREEN_W = 1280;
pub const SCREEN_H = 800;

const WALK_SPEED = heromod.WALK_SPEED;
const RUN_SPEED = heromod.RUN_SPEED;
const SPRINT_SPEED = heromod.SPRINT_SPEED;
const TURN_RATE = 12.0;
const STRAFE_SPEED = heromod.STRAFE_SPEED;
const STICK_DEADZONE = 0.16;
const LOOK_DEADZONE = 0.14;
const LOOK_CLAIM = 0.40;
const MOUSE_WAKE: f32 = 2.0;
const LOOK_RATE_YAW = 3.4;
const LOOK_RATE_PITCH = 2.0;
const LOOK_CURVE = 1.7;
const AIM_LOOK_SCALE = 0.42;
const ROLL_TAP_MAX = 0.22;

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
/// The bell is struck 34 m from bodies that answer it, so the SHAKE is the weight of the bronze and not a hit — under the raise's, over the sigil's.
const SHAKE_TOLL = 0.26;
const RESPAWN_HOLD = 0.55;
const RESPAWN_FADE = 0.9;
const DEATH_BAND_TOP: f32 = 0.35;
const DEATH_BAND_H: f32 = 0.30;

pub var PLAY_HALF: f32 = playHalfOf(worldfmt.DEFAULT_HALF);

fn playHalfOf(half: f32) f32 {
    return half - envmod.PLAY_INSET;
}

const HERO_R = foemod.HERO_R;

const MAX_ARROWS = 24;
const MAX_SHAFTS = 12;
pub const HERO_CENTER_Y = 1.0;

const COLLIDE_RATE = 11.0;

const GROUND_RISE_RATE = 9.0;
const GROUND_FALL_RATE = 16.0;
const GROUND_SNAP: f32 = 2.5;

const CLIP_NEAR = 0.55;
const CLIP_FAR = 320.0;

const MAX_LOCK_R = 17.0;
const LOCK_KEEP_SLACK: f32 = 2.0;
const LOCK_CAM_EASE = 9.0;
const LOCK_PITCH = 0.24;
const LOCK_PITCH_NEAR: f32 = 0.5;
const LOCK_TILT_TALL: f32 = 3.2; // over the shade's 2.4 and under the ogre's 4.4
const LOCK_TILT_TALLER: f32 = 3.6;
const LOCK_TILT_NEAR: f32 = 7.0;
const LOCK_TILT_FAR: f32 = 17.0;
/// Radians, 0 level and positive DOWN. `mathx.tiltDeg`'s complement: that asks how far a segment leans off
/// world UP, this how far a look leans off the HORIZON.
fn depression(eyeY: f32, mark: rl.Vector3, flat: f32) f32 {
    return std.math.atan2(eyeY - mark.y, flat);
}

/// **A BODY ON THE GROUND IS LOOKED AT, NOT STOOD OVER.** The mark rides the body, so a felled giant drops his
/// to his own boots; chasing it dived the lens to 57 deg at three metres and put the hero own back between the
/// player and the punish window he just earned. The mark is floored at the HERO shoulder for the pitch only —
/// the reticle still sits on the body.
fn lockPitch(g: *const Game, r: FoeRef) f32 {
    var mark = foeLockPoint(g, r);
    mark.y = mathx.maxF(mark.y, g.hero.shoulderPoint().y);
    const eye = g.rig.cam.position;
    const flat = mathx.distXZ(eye, mark);
    if (flat < LOCK_PITCH_NEAR) return LOCK_PITCH;
    const want = depression(eye.y, mark, flat);
    if (want >= LOCK_PITCH) return want;
    return mathx.lerpF(LOCK_PITCH, want, lockTiltShare(g, r, flat));
}

fn tiltShare(rise: f32, flat: f32) f32 {
    const tall = mathx.smoothstep(LOCK_TILT_TALL, LOCK_TILT_TALLER, rise);
    const near = 1.0 - mathx.smoothstep(LOCK_TILT_NEAR, LOCK_TILT_FAR, flat);
    return tall * near;
}

fn lockTiltShare(g: *const Game, r: FoeRef, flat: f32) f32 {
    return tiltShare(foeTopWorld(g, r).y - foePos(g, r).y, flat);
}
const LOCK_FLICK = 0.65;
const LOCK_FLICK_MOUSE: f32 = 40.0;
const LOCK_REARM_MOUSE: f32 = 12.0;
const LOCK_REARM_STICK: f32 = 0.3;
const LOCK_BLIND_HOLD: f32 = 1.1;

const CLEAR = rgba(80, 76, 69, 255);

const LookProbe = struct {
    mdx: f32 = 0,
    mdy: f32 = 0,
    rx: f32 = 0,
    ry: f32 = 0,
    mag: f32 = 0,
    dyaw: f32 = 0,
    pad: bool = false,
};

const Hook = struct { from: rl.Vector3, pull: f32 };

const Enter = union(enum) {
    fresh: usize,
    load: usize,
    map: struct { path: []const u8, at: rl.Vector3, facing: f32 },
};
const ENTER_OUT: f32 = 0.40;
const ENTER_IN: f32 = 0.85;

/// Every rail standing. Spelled once: the field's default never runs (`Game` comes off `alloc.create`), so
/// `init` and `snapBosses` both have to write it and three copies of the literal is three chances to
/// size one of them off the wrong count.
const NO_BOSSES: savemod.BossBits = [_][worldfmt.MAX_PER_KIND]bool{[_]bool{false} ** worldfmt.MAX_PER_KIND} ** savemod.BOSS_RAILS;

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
    herd: deermod.Herd,
    ring: magemod.Ring,
    host: golemmod.Host,
    marsh: fenmod.Marsh,
    clatter: skittermod.Clatter,
    crypt: priestmod.Crypt,
    belfry: hollowmod.Belfry,
    bed: bloommod.Bed,
    scorch: cindermod.Scorch,
    gorge: gorgermod.Gorge,
    stand: birchmod.Stand,
    pan: huskmod.Pan,
    shoal: fishmod.Shoal,
    roost: batmod.Roost,
    vigil: knightmod.Vigil,
    vanguard: duomod.Vanguard,
    conclave: duomod.Conclave,
    swarm: leechmod.Swarm,
    haunt: shademod.Haunt,
    chests: chestmod.Chests,
    pickups: pickupmod.Pickups = .{},
    award: awardmod.Award = .{},
    folk: npcmod.Folk,
    pack: wolfmod.Pack = .{},
    folkGen: u32 = 0,
    trig: trigmod.Runtime = .{},
    talk: dialogmod.Session = .{},
    npcPos: [npcmod.CAP]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** npcmod.CAP,
    nNpcPos: usize = 0,
    rest: restmod.Rest = .{},
    bootT: f32 = 0,
    /// **THE SCRATCH THE SAVE READS AND WRITES**, one row per `BOSS_RAILS` row. It is a `Game` field and not a
    /// local because `save.Slot` holds a pointer to it across both directions of the trip.
    bossBits: savemod.BossBits = NO_BOSSES,
    /// **ONE RAIL PER BOSS, AND THE RAIL IS ASSIGNED WHERE IT IS DRAWN.** Held per SLOT, not per creature: the
    /// knight's bar and the duo's swordsman both called the old `bossBar`, which meant rail 0 — so every frame
    /// each overwrote the other's frac, its fade and its chip tail, and the two drew on top of each other at
    /// the same y whether or not either was awake.
    bossK: [hud_.BOSS_SLOTS]f32 = [_]f32{0} ** hud_.BOSS_SLOTS,
    bossFrac: [hud_.BOSS_SLOTS]f32 = [_]f32{0} ** hud_.BOSS_SLOTS,
    /// **IS EACH ROOM STILL HOLDING**, one flag per `map.arenas`, solved once a frame in `markWards` off the
    /// same `alive` tally the fog gate's own seal is solved from. A DEFAULTED FIELD: assigned in `init`.
    arenaShut: [worldfmt.MAX_ARENAS]bool = [_]bool{false} ** worldfmt.MAX_ARENAS,
    /// A DEFAULTED FIELD: assigned in `init` and in `beginGame` — `Game` comes off `alloc.create`, so the
    /// `= null` here never runs.
    gateWalk: ?GateWalk = null,
    climb: ?Climb = null,
    /// **THE TRADE COUNTER** (`play/counter.zig`), opened by a `shop`/`smithy` trigger act. A DEFAULTED FIELD:
    /// assigned in `init` and in `beginGame`, because `Game` comes off `alloc.create`.
    counter: countermod.Counter = .{},
    counterT: f32 = 0,
    /// The deck he stood on LAST frame, or null. Walking off one is a fall and needs to know there was a floor.
    heroDeck: ?f32 = null,
    /// His `pos.y` last frame, and nothing else reads it: `syncLensLift` is the one customer.
    lensGroundY: f32 = 0,
    spiritK: f32 = 0,
    spiritHp: f32 = 0,
    day: daynight.Clock = .{},
    /// The eased result of the world's storm clock and a `worldfmt.Location`; every read site takes THESE.
    wetNow: f32 = 0,
    fogNow: f32 = 0,
    sporeNow: f32 = 0,
    hourLit: f32 = std.math.nan(f32),
    wetLit: f32 = std.math.nan(f32),
    fogLit: f32 = std.math.nan(f32),
    sporeLit: f32 = std.math.nan(f32),
    souls: soulsmod.Souls,
    weather: weathermod.Weather,
    rainfall: weathermod.Rain,
    mist: weathermod.Mist,
    skein: weathermod.Skein,
    sporefall: weathermod.Spore,
    tree: ptree.Tree = .{},
    restRetro: [gfx.RETRO_COUNT]f32 = [_]f32{0} ** gfx.RETRO_COUNT,
    bag: item.Bag = .{},
    arrowModel: rl.Model,
    clumpModel: rl.Model,
    crockModel: rl.Model,
    powderModel: rl.Model,
    venomModel: rl.Model,
    fireArrowModel: rl.Model,
    boltModel: rl.Model,
    emberModel: rl.Model,
    sacModel: rl.Model,
    wispModel: rl.Model,
    sparkModel: rl.Model,
    arrows: [MAX_ARROWS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_ARROWS,
    shafts: [MAX_SHAFTS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_SHAFTS,
    rig: cameramod.CamRig,
    lock: ?FoeRef = null,
    lockBlind: f32 = 0,
    hook: ?Hook = null,
    rumble: rumblemod.Rumble = .{},
    deathFade: f32 = 0,
    probe: LookProbe = .{},
    shelf: savemod.Shelf = .{},
    slot: usize = 0,
    shotOwed: bool = false,
    enterOut: f32 = 0,
    enterIn: f32 = 0,
    enterAct: ?Enter = null,
    /// **SEEDED ONCE AT STARTUP AND NEVER REWOUND.** A seeded `Rng` rather than wall time because `--shot` has
    /// to stay reproducible; in `init` rather than `beginGame`, or a reload hands you the same answer forever.
    dropRng: mathx.Rng = mathx.Rng.init(0),
    /// **NOT `dropRng`.** The liquid layer draws once per wet cell near him and once per pop clock, so sharing
    /// the drop stream would make what a corpse yields depend on how much lava he happened to be standing by —
    /// and `--shot` would stop being reproducible. Its own stream, seeded on the same rule.
    liquidRng: mathx.Rng = mathx.Rng.init(0),
    saveT: f32 = 0,
    boltGas: [BOLT_GAS_CAP]knightmod.Gas = undefined,
    boltGasHead: usize = 0,
    boltGasT: f32 = 0,
    /// One per `wf.Liquid`, and water's stays at zero: a tarn has no status and no pop of its own.
    liquidSoak: foemod.Soak = .{},
    popT: [worldfmt.Liquid.N]f32 = [_]f32{0} ** worldfmt.Liquid.N,
    searT: f32 = 0,
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
        PLAY_HALF = playHalfOf(g.map.half);
        phase(&initTimer, "map");
        g.env.build(&g.scene);
        g.env.replay(&g.map);
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
        g.herd = deermod.Herd.init(g.scene.shader);
        g.ring = magemod.Ring.init(g.scene.shader);
        g.host = golemmod.Host.init(g.scene.shader);
        g.marsh = fenmod.Marsh.init(g.scene.shader);
        g.clatter = skittermod.Clatter.init(g.scene.shader);
        g.crypt = priestmod.Crypt.init(g.scene.shader);
        g.belfry = hollowmod.Belfry.init(g.scene.shader);
        g.bed = bloommod.Bed.init(g.scene.shader);
        g.scorch = cindermod.Scorch.init(g.scene.shader);
        g.gorge = gorgermod.Gorge.init(g.scene.shader);
        g.stand = birchmod.Stand.init(g.scene.shader);
        g.pan = huskmod.Pan.init(g.scene.shader);
        g.shoal = fishmod.Shoal.init(g.scene.shader);
        g.roost = batmod.Roost.init(g.scene.shader);
        g.vigil = knightmod.Vigil.init(g.scene.shader);
        g.vanguard = duomod.Vanguard.init(g.scene.shader);
        g.conclave = duomod.Conclave.init(g.scene.shader);
        g.swarm = leechmod.Swarm.init(g.scene.shader);
        g.haunt = shademod.Haunt.init(g.scene.shader);
        g.chests = chestmod.Chests.init(g.scene.shader);
        g.folk = npcmod.Folk.init(g.scene.shader);
        g.pack = .{};
        g.pack.load(g.scene.shader);
        g.pickups = .{};
        g.award = .{};
        g.day = .{};
        g.bootT = 0;
        g.bossK = [_]f32{0} ** hud_.BOSS_SLOTS;
        g.bossFrac = [_]f32{0} ** hud_.BOSS_SLOTS;
        leavePlace(g);
        g.counter = .{};
        g.counterT = 0;
        g.lensGroundY = 0;
        g.spiritK = 0;
        g.spiritHp = 0;
        g.wetNow = 0;
        g.fogNow = 0;
        g.sporeNow = 0;
        g.hourLit = std.math.nan(f32);
        g.wetLit = std.math.nan(f32);
        g.fogLit = std.math.nan(f32);
        g.sporeLit = std.math.nan(f32);
        g.souls = soulsmod.Souls.init(g.scene.shader);
        // **THE WEATHER IS SEEDED ONCE AND NEVER REWOUND** (`dropRng`'s reason).
        g.weather = weathermod.Weather.init(0x5701_A17E);
        g.rainfall = weathermod.Rain.build(g.scene.shader);
        g.mist = weathermod.Mist.build(g.scene.shader);
        g.skein = weathermod.Skein.build(g.scene.shader);
        g.sporefall = weathermod.Spore.build(g.scene.shader);
        phase(&initTimer, "foes");
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.clumpModel = koboldmod.clumpMesh(g.scene.shader);
        g.crockModel = archermod.crockMesh(g.scene.shader);
        g.powderModel = archermod.powderMesh(g.scene.shader);
        g.venomModel = broodmod.venomMesh(g.scene.shader);
        g.fireArrowModel = archermod.fireArrowMesh(g.scene.shader);
        g.boltModel = heromod.boltMesh(g.scene.shader);
        g.emberModel = magemod.emberMesh(g.scene.shader);
        g.sacModel = golemmod.sacMesh(g.scene.shader);
        g.wispModel = shademod.wispMesh(g.scene.shader);
        g.sparkModel = hollowmod.sparkMesh(g.scene.shader);
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
        g.saveT = 0;
        g.boltGas = [_]knightmod.Gas{.{}} ** BOLT_GAS_CAP;
        g.boltGasHead = 0;
        g.boltGasT = 0;
        g.dropRng = mathx.Rng.init(0xD0DEC0DE);
        g.bossBits = NO_BOSSES;
        g.arenaShut = [_]bool{false} ** worldfmt.MAX_ARENAS;
        g.liquidRng = mathx.Rng.init(0x11C0D5EA);
        g.liquidSoak = .{};
        g.popT = [_]f32{0} ** worldfmt.Liquid.N;
        g.searT = 0;
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


/// Deep in the WOOD (`zone: wood` runs west of x = -52 at 0.98 density), well off the runway and the village.
const BOOT_AT_X: f32 = -104.0;
const BOOT_AT_Z: f32 = 18.0;
const BOOT_DRIFT_R: f32 = 26.0;
const BOOT_DRIFT_RATE: f32 = 0.036;
const BOOT_LOOK_UP: f32 = 6.0;

const BOOT_YAW_MID: f32 = 53.0; // degrees — the sun's own over-the-shoulder bearing
const BOOT_YAW_SWEEP: f32 = 38.0;
const BOOT_YAW_T: f32 = 41.0;
/// 0.44 rad is about 25 degrees under the horizon, which keeps the horizon and its sky in the upper third.
pub const BOOT_PITCH: f32 = 0.44;
pub const BOOT_DIST: f32 = 46.0;
const BOOT_SWOOP_PITCH: f32 = 0.17;
const BOOT_SWOOP_DIST: f32 = 9.0;
const BOOT_SWOOP_T: f32 = 17.0;
const BOOT_PUSH_T: f32 = 26.0;

fn bootLook(g: *const Game, t: f32) rl.Vector3 {
    const a = t * BOOT_DRIFT_RATE;
    const x = BOOT_AT_X + mathx.cosf(a) * BOOT_DRIFT_R;
    const z = BOOT_AT_Z + mathx.sinf(a * 1.7) * BOOT_DRIFT_R * 0.7;
    return v3(x, g.env.groundAt(x, z) + BOOT_LOOK_UP, z);
}

/// ONE function, so the loop and the harness cannot frame it two different ways.
pub fn bootCam(g: *Game, t: f32) void {
    g.rig.yaw = mathx.radians(BOOT_YAW_MID + BOOT_YAW_SWEEP * mathx.sinf(t * std.math.tau / BOOT_YAW_T));
    g.rig.pitch = BOOT_PITCH + BOOT_SWOOP_PITCH * mathx.sinf(t * std.math.tau / BOOT_SWOOP_T);
    g.rig.dist = BOOT_DIST + BOOT_SWOOP_DIST * mathx.sinf(t * std.math.tau / BOOT_PUSH_T + 1.1);
    g.rig.followCentred(bootLook(g, t));
}

fn beginGame(g: *Game) void {
    // **THE MAP SAYS WHERE HE STANDS UP** (`worldfmt.Start`). Hard-coded at (0, 4) facing south, every test map
    // had to be built around that one spot whatever its own shape was.
    var start = g.map.start.at();
    plantActor(g, &start);
    g.hero.setSpawn(start, g.map.start.facing());
    g.hero.souls = .{};
    g.hero.gold = .{};
    g.hero.arm = .sword;
    g.hero.armAlt = .bell;
    g.hero.off = .shield;
    g.hero.offAlt = .wand;
    g.hero.spell = .bolt;
    g.hero.mem = .{};
    g.hero.quick = .{};
    g.hero.quiver = .{};
    g.hero.worn = .{};

    g.hero.flasks = .{};
    g.day = .{};
    dropRunHud(g);
    leavePlace(g);
    g.counter = .{};
    g.counterT = 0;
    g.bag = .{};
    g.award = .{};
    for (STARTING_KIT) |k| {
        g.bag.add(k, 1);
        g.award.markKnown(k);
    }
    g.tree = .{};
    applyTree(g);
    g.hero.respawnNow();
    rehomeFoes(g, .blind);
    g.rest = .{};
    rehomeChests(g);
    armScript(g);
    clearQuivers(g);
    g.pack.clear();
    g.deathFade = 0;
    g.saveT = 0;
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
                g.shelf.head[i] = null;
                std.debug.print("LOAD FAILED: {s} is not a save this build can read\n", .{savemod.path(i)});
            }
        },
        .map => |m| enterMap(g, m.path, m.at, m.facing),
    }
    g.enterIn = ENTER_IN;
}

fn enterMap(g: *Game, path: []const u8, at: rl.Vector3, facing: f32) void {
    worldfmt.loadOrPanic(path, &g.map);
    PLAY_HALF = playHalfOf(g.map.half);
    g.env.replay(&g.map);
    leavePlace(g);
    g.hero.pos = inBounds(mathx.ground(at.x, at.z));
    g.hero.facing = facing;
    plantActor(g, &g.hero.pos);
    g.hero.pos = g.env.resolveHeroSide(g.hero.pos, HERO_R, g.hero.pos.y);
    g.hero.setSpawn(g.hero.pos, facing);
    rehomeFoes(g, .blind);
    rehomeChests(g);
    armScript(g);
    clearQuivers(g);
    g.pack.clear();
    dropRunHud(g);
    g.lock = null;
    g.lockBlind = 0;
    g.hook = null;
    g.hero.pose();
    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
    applyHour(g);
}

fn drawEnterFade(g: *const Game) void {
    const k = if (g.enterAct != null)
        1.0 - mathx.clampF(g.enterOut / ENTER_OUT, 0, 1)
    else
        mathx.clampF(g.enterIn / ENTER_IN, 0, 1);
    if (k <= 0.002) return;
    rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), rgba(0, 0, 0, mathx.u8f(255.0 * k)));
}

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
    _ = g;
    return worldfmt.startMap();
}

comptime {
    if (BOSS_RAILS.len > savemod.BOSS_RAILS) @compileError("game: more boss rails than the save file has rows for");
}

/// **EVERY RAIL'S DEAD, INTO THE SCRATCH THE FILE IS WRITTEN FROM.** `vit.dead` and not `gone`: the mechanic is
/// the killing blow, and the dissolve is only the picture catching up with it.
fn snapBosses(g: *Game) void {
    g.bossBits = NO_BOSSES;
    inline for (BOSS_RAILS, 0..) |row, i| {
        for (@field(g, row.field).liveConst(), 0..) |*k, j| {
            if (j < worldfmt.MAX_PER_KIND) g.bossBits[i][j] = k.vit.dead;
        }
    }
}

fn applyBosses(g: *Game) void {
    inline for (BOSS_RAILS, 0..) |row, i| {
        for (@field(g, row.field).live(), 0..) |*k, j| {
            if (j < worldfmt.MAX_PER_KIND and g.bossBits[i][j]) k.markSlain();
        }
    }
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
        .bosses = &g.bossBits,
        .award = &g.award,
        .map = saveMap(g),
    };
}

fn loadGame(g: *Game, i: usize) bool {
    beginGame(g);
    if (!savemod.read(i, slotOf(g))) return false;
    applyBosses(g);
    hidePickups(g);
    applyTree(g);
    plantActor(g, &g.hero.pos);
    g.hero.pose();
    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
    applyHour(g);
    return true;
}

const FoeGroup = struct {
    field: []const u8,
    kind: ?FoeKind,
    aggro: f32,
    vsHero: bool = true,
    vs: []const []const u8 = &.{},
};
/// **A ROW HERE OWES `run` AN `update(...) |b| heroTakes(...)` CALL**, or the creature swings and nothing lands.
/// NOTHING CHECKS THAT — `_ =` discards a returned blow just as legally as taking it, which is exactly what the
/// crypt's own row does on purpose. There WAS a second list (`BLOW_GROUPS`); every check it could make was a
/// restatement of this table, and both `bed` and `crypt` sat in it swinging nothing at the hero at all.
pub const FOE_GROUPS = [_]FoeGroup{
    .{ .field = "warren", .kind = .toad, .aggro = frogmod.AGGRO_R, .vs = &.{"herd"} },
    .{ .field = "line", .kind = .archer, .aggro = archermod.AGGRO_R, .vs = &.{"warren"} },
    .{ .field = "grief", .kind = .ogre, .aggro = ogremod.AGGRO_R, .vsHero = false },
    .{ .field = "band", .kind = null, .aggro = koboldmod.AGGRO_R },
    .{ .field = "brood", .kind = null, .aggro = broodmod.AGGRO_R },
    .{ .field = "muster", .kind = null, .aggro = warriormod.AGGRO_R, .vs = &.{"line"} },
    .{ .field = "haunt", .kind = null, .aggro = shademod.AGGRO_R, .vs = &.{ "warren", "line", "muster" } },
    .{ .field = "swarm", .kind = .leechfly, .aggro = leechmod.AGGRO_R },
    .{ .field = "grove", .kind = .rooted, .aggro = rootedmod.AGGRO_R, .vsHero = false },
    .{ .field = "cluster", .kind = .shroom, .aggro = shroommod.AGGRO_R, .vs = &.{"herd"} },
    .{ .field = "warrens", .kind = .delver, .aggro = delvermod.AGGRO_R },
    .{ .field = "rite", .kind = .necromancer, .aggro = necromod.AGGRO_R, .vs = &.{ "line", "muster" } },
    // **THE ROW THAT YIELDS IS THE ROW THAT NAMES THE OTHER** — `vs` is who shoulders ME.
    .{ .field = "herd", .kind = .fungal_deer, .aggro = deermod.AGGRO_R },
    .{ .field = "ring", .kind = .mushroom_mage, .aggro = magemod.AGGRO_R },
    .{ .field = "host", .kind = .spore_golem, .aggro = golemmod.AGGRO_R },
    .{ .field = "marsh", .kind = .fen_lurker, .aggro = fenmod.AGGRO_R, .vsHero = false },
    // **THE LITTLE BODY IS THE ONE THAT GIVES WAY** — a 0.62 m cage shouldering a priest off its line is the picture arguing with the weights.
    .{ .field = "clatter", .kind = .bone_skitterer, .aggro = skittermod.AGGRO_R, .vs = &.{ "crypt", "belfry" } },
    .{ .field = "crypt", .kind = .ancient_priest, .aggro = priestmod.AGGRO_R },
    .{ .field = "belfry", .kind = .tolling_hollow, .aggro = hollowmod.AGGRO_R },
    .{ .field = "bed", .kind = .slumber_bloom, .aggro = bloommod.AGGRO_R, .vsHero = false },
    .{ .field = "scorch", .kind = .cinder_wake, .aggro = cindermod.AGGRO_R },
    .{ .field = "gorge", .kind = .rotgorger, .aggro = gorgermod.AGGRO_R },
    .{ .field = "stand", .kind = .birchwight, .aggro = birchmod.AGGRO_R },
    .{ .field = "pan", .kind = .salt_husk, .aggro = huskmod.AGGRO_R },
    .{ .field = "shoal", .kind = null, .aggro = fishmod.AGGRO_R },
    .{ .field = "roost", .kind = .blinkbat, .aggro = batmod.AGGRO_R },
    .{ .field = "vigil", .kind = .bone_knight, .aggro = knightmod.AGGRO_R, .vsHero = false, .vs = &.{ "line", "muster" } },
    // **THE PAIR IS ONE GROUP AND ANSWERS FOR ITS OWN MEMBERS** — the kobold warband's arrangement, because
    // the two of them are one encounter and the ground they put down belongs to neither body.
    .{ .field = "vanguard", .kind = .fungal_swordsman, .aggro = duomod.AGGRO_R, .vs = &.{ "cluster", "ring" } },
    .{ .field = "conclave", .kind = .fungal_magus, .aggro = duomod.AGGRO_R, .vs = &.{ "cluster", "ring" } },
};

comptime {
    @setEvalBranchQuota(30000);
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

/// **THE BODIES WITH NO PARRY WINDOW, AND WHY EACH ONE HAS NONE.** Every other group in `FOE_GROUPS` must
/// offer `setParry`, or a creature can carry a melee stroke the boards silently cannot catch — invisible in
/// play and indistinguishable from a mistimed press. The shared rule: **A SHIELD IS BRACED AGAINST A STROKE.**
/// A body arriving through the air is not one, nor a disc at your feet, nor a thing thrown from across the
/// field. **A LARGE SLAM IS NOT ONE EITHER** — it THROWS him (`combat.Hit.launch`), and footwork is its answer.
const NO_PARRY = [_]struct { field: []const u8, why: []const u8 }{
    .{ .field = "cluster", .why = "the sporeling FLINGS ITSELF — a leap, and its cloud is not a blow at all" },
    .{ .field = "rite", .why = "the necromancer never melees" },
    .{ .field = "ring", .why = "the mushroom mage lobs, and a bouncing fireball is answered sideways" },
    .{ .field = "host", .why = "a disc at your feet, a leap-slam that throws you, and a thrown sac: no strokes" },
    .{ .field = "crypt", .why = "the ancient priest never melees; the breath is a cone you walk out of" },
    .{ .field = "bed", .why = "the slumber bloom has no blow at all — the gas is a ring you walk out of" },
    .{ .field = "conclave", .why = "the fungal magus never melees; the orbs and the bunches are not strokes" },
};

/// **WHAT IS ROOTED, AND WHY** — the only creatures with no `foe.Post`, because standing still IS their
/// design. Enforced BOTH WAYS below, `NO_PARRY`'s rule: which units get orders is the AUTHOR's call, made per
/// unit in the editor, so every creature that CAN move must be able to take them. One that cannot, and has no
/// line here, is an order the editor lets you assign that silently does nothing.
const NO_ORDERS = [_]struct { field: []const u8, why: []const u8 }{
    .{ .field = "grove", .why = "the snag-mimic is a FIXTURE — it opens its eyes and strikes, and never moves" },
    .{ .field = "marsh", .why = "the fen lurker never leaves its water; dry land is the whole counter to it" },
    .{ .field = "bed", .why = "the slumber bloom is rooted and cannot follow — that is the fight" },
};

fn memberOf(comptime field: []const u8) type {
    return @typeInfo(@typeInfo(@TypeOf(@FieldType(Game, field).live)).@"fn".return_type.?).pointer.child;
}

comptime {
    @setEvalBranchQuota(30000);
    for (NO_ORDERS) |x| {
        var known = false;
        for (FOE_GROUPS) |gr| {
            if (!std.mem.eql(u8, gr.field, x.field)) continue;
            known = true;
            if (@hasField(memberOf(gr.field), "post")) @compileError("game: NO_ORDERS names `" ++ x.field ++
                "`, which HAS a post — take it off the list rather than leaving two answers");
        }
        if (!known) @compileError("game: NO_ORDERS names `" ++ x.field ++ "`, which is not a FOE_GROUPS field");
    }
    for (FOE_GROUPS) |gr| {
        if (@hasField(memberOf(gr.field), "post")) continue;
        var excused = false;
        for (NO_ORDERS) |x| {
            if (std.mem.eql(u8, x.field, gr.field)) excused = true;
        }
        if (!excused) @compileError("game: `" ++ gr.field ++ "` has no `foe.Post`, so the `ai=` and `wp=` the " ++
            "editor paints on it do nothing. Give it one and a `foe.postStep` from its idle, or say why not in NO_ORDERS");
    }
}

// **EVERY CREATURE THAT TAKES ORDERS HAS TO WALK THEM.** The comptime block above only pins that each group
// HAS a `foe.Post`; `warrior.zig` then pinned that ITS dog roams, and nothing asked the other twenty-five.
// MEASURED: twelve of them tested the go-home arm against `self.home` instead of `foe.homeFor`, and their own
// `HOME_R` is 1.5-3.0 m against `foe.ROAM_R`'s 9 — eight never got further than 1.9-3.4 m off the post, and
// the other four reached the mark and were walked straight back off it again instead of standing there.
// Four minutes each, hero six aggro rings away, so nothing here is a fight.
test "A UNIT WALKS ITS ORDERS — every creature that takes them, not just the one it was written on" {
    const dt: f32 = 1.0 / 60.0;
    const home = mathx.ground(0, 0);
    // Marks are drawn from 3 m out (`foe.ROAM_STEP_LO`), so a dog that stands its dwell where it arrived is
    // near its post only in transit; one that is dragged back the moment it gets there lives at the pin.
    const AT_POST: f32 = 2.0;
    var worst: f32 = 1e9;
    var worstName: []const u8 = "";
    var homiest: f32 = 0;
    var homiestName: []const u8 = "";
    std.debug.print("\n", .{});
    inline for (FOE_GROUPS) |gr| {
        const T = memberOf(gr.field);
        if (comptime @hasField(T, "post")) {
            const far = mathx.ground(0, gr.aggro * 6);
            var f = if (comptime @hasDecl(T, "spawn"))
                T.spawn(home, 0, 1.0, 0.37)
            else
                T.spawnAs(@enumFromInt(0), home, 0, 1.0, 0.37);
            f.post.arm(.roam, home, &.{}, 0.37);
            var strayed: f32 = 0;
            var atPost: u32 = 0;
            var frames: u32 = 0;
            var t: f32 = 0;
            while (t < 240.0) : (t += dt) {
                _ = callUpdate(&f, dt, far, 400.0);
                const d = mathx.distXZ(f.pos, home);
                strayed = @max(strayed, d);
                frames += 1;
                if (d <= AT_POST) atPost += 1;
            }
            const share = @as(f32, @floatFromInt(atPost)) / @as(f32, @floatFromInt(frames));
            std.debug.print("  {s: <10} roams {d:.1} m off its post, and spends {d:.0}% of the round back at it\n", .{ gr.field, strayed, share * 100.0 });
            if (strayed < worst) {
                worst = strayed;
                worstName = gr.field;
            }
            if (share > homiest) {
                homiest = share;
                homiestName = gr.field;
            }
        }
    }
    std.debug.print("  worst reach: {s} at {d:.1} m against a leash of {d:.1} m; most homebound: {s} at {d:.0}%\n", .{ worstName, worst, foemod.ROAM_R, homiestName, homiest * 100.0 });
    try std.testing.expect(worst > foemod.ROAM_R * 0.5);
    // A dog that never stands out its dwell is one that walks home and back for four minutes.
    try std.testing.expect(homiest < 0.35);
}

/// The two creatures whose update carries one more argument than the rest: the fishman reads its band's blood
/// and the rotgorger the nearest corpse. Neither is anything a body standing its round has.
fn callUpdate(f: anytype, dt: f32, hero: rl.Vector3, bounds: f32) void {
    const P = @typeInfo(@TypeOf(@TypeOf(f.*).update)).@"fn".params;
    if (P.len == 5) {
        _ = f.update(dt, hero, bounds, .{});
    } else {
        _ = f.update(dt, hero, bounds, .{}, if (P[5].type.? == bool) false else null);
    }
}

comptime {
    @setEvalBranchQuota(30000);
    for (NO_PARRY) |x| {
        var known = false;
        for (FOE_GROUPS) |gr| {
            if (!std.mem.eql(u8, gr.field, x.field)) continue;
            known = true;
            if (@hasDecl(@FieldType(Game, gr.field), "setParry")) @compileError("game: NO_PARRY names `" ++
                x.field ++ "`, which HAS a parry window — take it off the list rather than leaving two answers");
        }
        if (!known) @compileError("game: NO_PARRY names `" ++ x.field ++ "`, which is not a FOE_GROUPS field");
    }
    for (FOE_GROUPS) |gr| {
        if (@hasDecl(@FieldType(Game, gr.field), "setParry")) continue;
        var excused = false;
        for (NO_PARRY) |x| {
            if (std.mem.eql(u8, x.field, gr.field)) excused = true;
        }
        if (!excused) @compileError("game: `" ++ gr.field ++ "` has no `setParry`, so nothing it swings can " ++
            "ever be caught. Give it `parryable`/`takeParry` off `foe.inParryWindow`, or say why not in NO_PARRY");
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

test "WHAT THE FRAME COSTS — the group slabs, the biggest bodies, and one Game" {
    const KB = 1024.0;
    var total: f64 = 0;
    inline for (FOE_GROUPS) |gr| {
        const T = @FieldType(Game, gr.field);
        const M = std.meta.Child(@TypeOf(@as(*T, undefined).liveConst()));
        total += @as(f64, @floatFromInt(@sizeOf(T)));
        std.debug.print("  {s:<9} {d:>7.0} KB slab, {d:>6} B a body\n", .{ gr.field, @as(f64, @floatFromInt(@sizeOf(T))) / KB, @sizeOf(M) });
    }
    std.debug.print("  ---- {d:.1} MB of foe slabs, {d:.1} MB for the whole Game\n", .{ total / KB / KB, @as(f64, @floatFromInt(@sizeOf(Game))) / KB / KB });
    // ONE `alloc.create` at startup, never touched again: the slabs are `wf.MAX_PER_KIND` deep by construction and nothing here is per-frame.
    try std.testing.expect(@sizeOf(Game) < 512 * 1024 * 1024);
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
    try std.testing.expect(toad.alive());
    try std.testing.expect(!foeFights(&toad, near, frogmod.AGGRO_R));
}

test "A LANDED SHOT DETONATES ONCE, not once a frame for the 1.4 s it lies there" {
    const dt: f32 = 1.0 / 60.0;
    var a = archermod.launchShaft(v3(0, 1.15, 0), v3(0, 1.0, 11.0), magemod.EMBER_SPEED, .{}, true, .emberball);

    var landings: u32 = 0;
    var airborne: u32 = 0;
    var i: usize = 0;
    while (i < 900 and a.live) : (i += 1) {
        _ = archermod.stepShaft(&a, 0, &.{}, dt);
        a.bounced = false;
        if (justLanded(&a)) landings += 1 else if (!a.stuck) airborne += 1;
    }
    std.debug.print("\n  ember: {d} landing frame(s) over {d} of flight and {d} of rest\n", .{ landings, airborne, i - landings - airborne });
    try std.testing.expect(!a.live);
    try std.testing.expect(airborne > 10);
    // A ball that has DETONATED does not lie on the grass afterwards (`archer.lingerOf`): the landing frame is billed once and the body is gone within a frame of it.
    try std.testing.expect(i - landings - airborne <= 2);
    try std.testing.expectEqual(@as(u32, 1), landings);
}

test "EVERY GROUP HOLDS EVERYTHING THE MAP CAN PLACE — the per-kind limit is gone, not raised" {
    var total: usize = 0;
    inline for (FOE_GROUPS) |gr| {
        try std.testing.expect(comptime groupCap(gr.field) >= worldfmt.MAX_FOES);
        total += @sizeOf(@FieldType(Game, gr.field));
    }
    // OFF THE TABLE'S OWN LENGTH: written out as a literal the count read 17 against twenty rows, in the one print the memory figure is judged on.
    std.debug.print("\n  foes: {d} slabs {d:.1} MB, Game {d:.1} MB, frame scratch {d:.0} KB - any {d} of one kind fits\n", .{
        FOE_GROUPS.len,
        @as(f64, @floatFromInt(total)) / (1024.0 * 1024.0),
        @as(f64, @floatFromInt(@sizeOf(Game))) / (1024.0 * 1024.0),
        @as(f64, @floatFromInt(@sizeOf(@TypeOf(frameWasPos)))) / 1024.0,
        worldfmt.MAX_FOES,
    });
    try std.testing.expect(worldfmt.MAX_PER_KIND >= worldfmt.MAX_FOES);
}

test "WHICH CREATURES OBEY THEIR ORDERS — every group that carries a `post`, and every one that does not yet" {
    // **THE COVERAGE IS PRINTED, NOT ASSUMED.** `ai=` and `wp=` are authored per unit and painted in the
    // editor for every kind; a creature that has not grown a `foe.Post` takes the orders, saves them, redraws
    // them and stands still — which is the one failure of this feature that nothing else would show.
    var carries: usize = 0;
    var stands: usize = 0;
    inline for (FOE_GROUPS) |gr| {
        const G = @FieldType(Game, gr.field);
        const Member = @typeInfo(@typeInfo(@TypeOf(G.live)).@"fn".return_type.?).pointer.child;
        if (comptime @hasField(Member, "post")) {
            carries += 1;
        } else {
            stands += 1;
            std.debug.print("\n  no orders yet: {s}", .{gr.field});
        }
    }
    std.debug.print("\n  orders: {d} of {d} groups walk them\n", .{ carries, carries + stands });
    // The standard is `foe.Post` plus one call from the idle branch; this only ever goes UP.
    try std.testing.expect(carries > 0);
}

test "A DETONATOR RESOLVES ONE WAY — caught on the chest and rolled to a stop bill the SAME blow" {
    const full = mathx.lerpF(1.0, BLAST_FLOOR, 0.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), full, 1e-6);
    const rim = mathx.lerpF(1.0, BLAST_FLOOR, 1.0);
    try std.testing.expectApproxEqAbs(BLAST_FLOOR, rim, 1e-6);
    try std.testing.expect(rim > 0 and rim < 0.5);

    var bombs: usize = 0;
    inline for (@typeInfo(archermod.Shot).@"enum".fields) |f| {
        if (detonates(@enumFromInt(f.value))) bombs += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), bombs);
    try std.testing.expect(detonates(.emberball));
    try std.testing.expect(!detonates(.arrow) and !detonates(.firearrow) and !detonates(.bolt));

    const dt: f32 = 1.0 / 60.0;
    var a = archermod.launchShaft(v3(0, 1.15, 0), v3(0, 1.0, 11.0), magemod.EMBER_SPEED, .{}, true, .emberball);
    var flight: f32 = 0;
    while (a.live and !a.stuck) : (flight += dt) _ = archermod.stepShaft(&a, 0, &.{}, dt);
    std.debug.print("\n  ember: {d:.2} s of flight against a {d:.1} s life\n", .{ flight, archermod.EMBER_LIFE_S });
    try std.testing.expect(a.stuck);
    try std.testing.expect(flight < archermod.EMBER_LIFE_S);
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
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(Reach.souls));
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.talk));
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.chest));
    inline for (@typeInfo(Reach).@"enum".fields) |f| _ = @as(Reach, @enumFromInt(f.value)).prompt();
}

test "the ranges the fight is judged at are each GROUP'S OWN, never one figure for the field" {
    try std.testing.expect(frogmod.AGGRO_R < archermod.AGGRO_R);
    inline for (FOE_GROUPS) |gr| try std.testing.expect(gr.aggro > 0);
}

const Sighted = enum { blind, seen };

fn rehomeFoes(g: *Game, sighted: Sighted) void {
    g.env.openWards();
    // A swing left in the sink across a tear-down bills into a body that has since been re-homed.
    foemod.clearTurned();
    // **AND THE GROUND THE RUN LAID GOES WITH THE BODIES** — every group that leaves a hazard clears it in its
    // own `reset` (`knight.Vigil.clearGas`, `shroom.Cluster.clearClouds`, `cinderwake.Scorch.clearTrail`); the
    // hero's bolt cloud is the one of them that lives on `Game` and had nobody to clear it. MEASURED:
    // `knight.GAS_LIFE` 4.2 s against `hero.DEATH_DUR` 3.6 s, so 0.6 s of the dead run's cloud hung at the old
    // spot dosing the re-homed field — and a bonfire or a map cut has no card at all, so there it was all 4.2.
    g.boltGas = [_]knightmod.Gas{.{}} ** BOLT_GAS_CAP;
    g.boltGasHead = 0;
    g.boltGasT = 0;
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

/// LAST FRAME'S FOE POSITIONS — **MODULE SCRATCH, NOT A STACK ARRAY AND NOT A `Game` FIELD.** On the stack it
/// was 15 KB and would be 157 KB now; on `Game` it cannot go at all, because `FOE_CAP` is measured FROM `Game`.
/// Deliberately uninitialised: rewritten head-first every frame and only read back as `[gi][0..wasN[gi]]`.
var frameWasPos: [FOE_GROUPS.len][FOE_CAP]rl.Vector3 = undefined;

comptime {
    // **NO GROUP MAY BE NARROWER THAN THE MAP CAN PLACE** — `sporegolem` was 8 wide against a map that could
    // place 24, and `foe.resetGroup` dropped the rest in silence.
    for (FOE_GROUPS) |f| {
        if (groupCap(f.field) < worldfmt.MAX_PER_KIND) {
            @compileError("game: foe group '" ++ f.field ++ "' is narrower than worldfmt.MAX_PER_KIND — " ++
                "a map that places more than it holds loses the difference without a word");
        }
    }
    // **THE ROSTER IS WRITTEN TWICE** — here and as `objview.CharSet`, because the viewer draws a creature
    // through its own group.
    if (FOE_GROUPS.len != objviewmod.CHAR_GROUPS) {
        @compileError("game: FOE_GROUPS and objview.CharSet no longer hold the same roster");
    }
}

const Move = struct { fx: f32 = 0, fz: f32 = 0, speed: f32 = 0 };

const Stick = struct { x: f32 = 0, y: f32 = 0, mag: f32 = 0 };

fn stickRadial(x: f32, y: f32, dz: f32, curve: f32) Stick {
    const m = @sqrt(x * x + y * y);
    if (m < dz) return .{};
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
            return .{ .fx = s.x, .fz = -s.y, .speed = sp };
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

/// The knee on the H=1.8 rig (0.278·H).
const WADE_KNEE: f32 = 0.50;
const WADE_DEEP: f32 = envmod.WADE_MAX;
const WADE_SLOWEST: f32 = 0.8;

const STARTING_KIT = [_]item.Kind{
    .spirit_scroll_wolf,
    // The seven sheets from the first frame; the SLOTS are the only limit. Where a scroll is FOUND is the map's call.
    .scroll_bolt,
    .scroll_roots,
    .scroll_rime,
    .scroll_levin,
    .scroll_siphon,
    .scroll_lance,
    .scroll_sunder,
};

comptime {
    std.debug.assert(@abs(envmod.WADE_MAX - 0.760 * heromod.H) < 0.005);
    std.debug.assert(envmod.HERO_R_PIN == foemod.HERO_R);
}

/// **EVERY BOSS ON THE FIELD, IN ONE PASS, EACH ON ITS OWN RAIL.** A boss group owes this list a row and
/// nothing else. The rail is the ROW'S index, so it is stable while a fight lasts and never shared: the duo's
/// swordsman and the knight both used to mean rail 0, and each spent the frame wiping the other's chip tail.
///
/// **A DUO IS TWO ROWS, NOT ONE POOLED ONE.** They die separately and the fight is which of them you spend the
/// window on, so a bar summing both would hide the only decision in it. Each fades on its own clock, so a
/// survivor's bar stays up alone.
const BOSS_RAILS = [_]struct { field: []const u8, kind: FoeKind }{
    .{ .field = "vigil", .kind = .bone_knight },
    .{ .field = "vanguard", .kind = .fungal_swordsman },
    .{ .field = "conclave", .kind = .fungal_magus },
};

comptime {
    if (BOSS_RAILS.len > hud_.BOSS_SLOTS) @compileError("game: more boss rails than the HUD has rails for");
    for (BOSS_RAILS) |r| {
        var known = false;
        for (FOE_GROUPS) |gr| {
            if (std.mem.eql(u8, gr.field, r.field)) known = true;
        }
        if (!known) @compileError("game: BOSS_RAILS names `" ++ r.field ++ "`, which is not a FOE_GROUPS field");
    }
    // **A RAIL AND `foe.isBoss` ARE ONE SET, ENFORCED BOTH WAYS.** The rail is what gets a bar; `isBoss` is what
    // a fog gate offers to be sealed on (`editor`'s Sealed by...). A boss with a bar and no seal is a door the
    // author cannot hang on it, and a seal with no bar is a fight with nothing on screen.
    for (BOSS_RAILS) |r| {
        if (!foemod.isBoss(r.kind)) @compileError("game: BOSS_RAILS names " ++ @tagName(r.kind) ++ ", which foe.isBoss says is not a boss");
    }
    for (@typeInfo(FoeKind).@"enum".fields) |f| {
        if (!foemod.isBoss(@enumFromInt(f.value))) continue;
        var railed = false;
        for (BOSS_RAILS) |r| {
            if (@intFromEnum(r.kind) == f.value) railed = true;
        }
        if (!railed) @compileError("game: foe.isBoss says " ++ f.name ++ " is a boss, but it has no row in BOSS_RAILS");
    }
}

/// **A NAMED GATE OWNS ITS BOSS'S BAR** — has the hero walked through a fog gate sealed on `k`? `null` is
/// nobody asking: no ward in this map names that creature, so the bar falls back to the aggro ring it has
/// always used. Authored per gate in the editor (Sealed by...), never a list in here — which is the whole
/// point: the arena, and therefore where the bar comes up, is the MAP's to say.
fn gateEntered(e: *const envmod.Env, m: *const worldfmt.Map, k: FoeKind) ?bool {
    var named = false;
    for (0..e.nwards) |i| {
        const pr = &e.props[e.wardProps[i]];
        if (pr.op >= m.nops or !m.ops[pr.op].sealsOn(k)) continue;
        named = true;
        if (e.wardIn[i]) return true;
    }
    return if (named) false else null;
}

test "A BOSS BAR BELONGS TO ITS FOG GATE, and a boss no gate names keeps the ring it always had" {
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    const m = try std.testing.allocator.create(worldfmt.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Gate");
    var op = worldfmt.defaults(.at);
    op.kind = .foggate;
    op.boss[0] = .fungal_swordsman;
    op.boss[1] = .fungal_magus;
    op.nboss = 2;
    const oi = try m.add(op);
    e.nprops = 1;
    e.props[0] = .{ .kind = .foggate, .pos = mathx.zero3, .yaw = 0, .scale = 1, .op = @intCast(oi) };
    e.nwards = 1;
    e.wardProps[0] = 0;
    e.wardIn[0] = false;

    // Both halves of the pair wait on the ONE gate, which is what a two-name seal buys.
    try std.testing.expectEqual(@as(?bool, false), gateEntered(e, m, .fungal_swordsman));
    try std.testing.expectEqual(@as(?bool, false), gateEntered(e, m, .fungal_magus));
    // …and a boss nothing gates is nobody's business here: `null` hands the bar back to the aggro ring.
    try std.testing.expectEqual(@as(?bool, null), gateEntered(e, m, .bone_knight));
    e.wardIn[0] = true;
    try std.testing.expectEqual(@as(?bool, true), gateEntered(e, m, .fungal_swordsman));
    try std.testing.expectEqual(@as(?bool, true), gateEntered(e, m, .fungal_magus));
    try std.testing.expectEqual(@as(?bool, null), gateEntered(e, m, .bone_knight));
}

test "A SEALED ROOM HOLDS WHAT IS IN IT AND LETS EVERYTHING ELSE ALONE" {
    const m = try std.testing.allocator.create(worldfmt.Map);
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    var a = worldfmt.Arena{ .n = 4, .nboss = 1 };
    a.boss[0] = .fungal_magus;
    const pts = [_][2]f32{ .{ -20, -20 }, .{ 20, -20 }, .{ 20, 20 }, .{ -20, 20 } };
    for (pts, 0..) |p, i| {
        a.vx[i] = p[0];
        a.vz[i] = p[1];
    }
    m.arenas[0] = a;
    m.narenas = 1;
    const R: f32 = 0.6;
    var shut = [_]bool{true} ** worldfmt.MAX_ARENAS;

    // **A MAGUS THAT DISSOLVED OUT OF THE FIGHT** — no segment was travelled, so only the destination answers.
    const inside = mathx.ground(4, 4);
    const blinked = holdInRoom(m, &shut, inside, mathx.ground(60, 4), R);
    try std.testing.expect(m.arenas[0].contains(blinked.x, blinked.z));
    try std.testing.expectApproxEqAbs(@as(f32, 20.0 - R), blinked.x, 1e-4);

    // **ASKED ON THE STEP'S START.** A body walking past OUTSIDE is not dragged in through the wall — the bug
    // this would have if it read where the body ended up instead of where it set off from.
    const passing = holdInRoom(m, &shut, mathx.ground(60, 60), mathx.ground(0, 0), R);
    try std.testing.expectApproxEqAbs(@as(f32, 0), passing.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), passing.z, 1e-5);

    const walk = holdInRoom(m, &shut, inside, mathx.ground(5, 5), R);
    try std.testing.expectApproxEqAbs(@as(f32, 5), walk.x, 1e-5);

    shut[0] = false;
    const out = holdInRoom(m, &shut, inside, mathx.ground(60, 4), R);
    try std.testing.expectApproxEqAbs(@as(f32, 60), out.x, 1e-5);
}

test "AND THE ROOM'S SEAL IS SOLVED OFF THE SAME TALLY THE GATE'S IS" {
    const m = try std.testing.allocator.create(worldfmt.Map);
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    var a = worldfmt.Arena{ .n = 3, .nboss = 2 };
    a.boss[0] = .fungal_swordsman;
    a.boss[1] = .fungal_magus;
    a.vx[1] = 10;
    a.vz[2] = 10;
    m.arenas[0] = a;
    m.arenas[1] = .{ .n = 3, .nboss = 0 };
    m.narenas = 2;

    var alive = [_]u32{0} ** @typeInfo(FoeKind).@"enum".fields.len;
    var shut = [_]bool{false} ** worldfmt.MAX_ARENAS;
    // HALF THE FIGHT STANDING STILL HOLDS THE ROOM, which is the whole reason the seal is a list.
    alive[@intFromEnum(FoeKind.fungal_magus)] = 1;
    solveArenaSeals(m, alive, &shut);
    try std.testing.expect(shut[0] and !shut[1]);
    alive[@intFromEnum(FoeKind.fungal_swordsman)] = 1;
    solveArenaSeals(m, alive, &shut);
    try std.testing.expect(shut[0]);
    alive = [_]u32{0} ** @typeInfo(FoeKind).@"enum".fields.len;
    solveArenaSeals(m, alive, &shut);
    try std.testing.expect(!shut[0] and !shut[1]);
}

/// **BEING SHUT IN WITH SOMETHING IS THE FIGHT, WHATEVER THE RANGE** — the one thing a radius cannot say
/// (owner: "he tele'd out of the arena and his hp bar vanished"). The magus stood itself 29 m off against a bar
/// gated at 26 (`fungalduo`'s own comptime block has the arithmetic), and `Leash.roused` is a 14 s timer topped
/// up only by being HIT, so chasing the swordsman let it lapse and the bar faded out mid-fight.
fn sealedInWith(g: *const Game, k: FoeKind) bool {
    const i = g.map.arenaIndexAt(g.hero.pos.x, g.hero.pos.z) orelse return false;
    if (i >= g.arenaShut.len or !g.arenaShut[i]) return false;
    return g.map.arenas[i].sealsOn(k);
}

fn bossBars(g: *Game, dt: f32) void {
    inline for (BOSS_RAILS, 0..) |row, i| {
        var frac: f32 = 0;
        var stag = false;
        var up = false;
        const sealed = sealedInWith(g, row.kind);
        // **THE BAR IS THE FOG GATE'S, WHEN A FOG GATE CLAIMS IT.** A boss you have not been sealed in with is
        // a boss whose bar has no business on screen: the pair were visible across half a canyon, so both rails
        // came up while he was still walking toward the door.
        const gated = gateEntered(&g.env, &g.map, row.kind) orelse true;
        for (if (gated) @field(g, row.field).liveConst() else &.{}) |*k| {
            if (!k.alive()) continue;
            if (!(sealed or k.leash.roused() or mathx.distXZ(k.pos, g.hero.pos) <= AGGRO_OF[i])) continue;
            frac = k.vit.hpFrac();
            stag = k.staggered();
            up = true;
            break;
        }
        if (up) {
            g.bossFrac[i] = frac;
            g.bossK[i] = mathx.approach(g.bossK[i], 1.0, dt * 4.0);
        } else g.bossK[i] = mathx.approach(g.bossK[i], 0, dt * 1.4);
        hud_.bossBarAt(i, dt, worldfmt.foeName(row.kind), g.bossFrac[i], stag, g.bossK[i]);
    }
}

/// The aggro ring for each rail, taken off `FOE_GROUPS` rather than written again — a bar that wakes at a
/// different range from the creature it is showing is a bar that lies about whether the fight has started.
const AGGRO_OF = blk: {
    var out: [BOSS_RAILS.len]f32 = undefined;
    for (BOSS_RAILS, 0..) |r, i| {
        for (FOE_GROUPS) |gr| {
            if (std.mem.eql(u8, gr.field, r.field)) out[i] = gr.aggro;
        }
    }
    break :blk out;
};

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

const Mark = struct { swing: f32, out: f32, lo: f32, hi: f32 };

/// **HOW FAR THE MARK RIDES, AND HOW FAR IT WANDERS OFF THE BODY.** `swing` is the travel a lock dot needs to
/// look attached; `out` is the worst the mark ever pokes out of the body's own standing box — sideways past
/// `bodyR`, or over the crown.
fn markSwing(f: anytype, hero: rl.Vector3) Mark {
    var m = Mark{ .swing = 0, .out = 0, .lo = 1e9, .hi = -1e9 };
    var i: u32 = 0;
    while (i < 300) : (i += 1) {
        _ = f.update(1.0 / 60.0, hero, PLAY_HALF, .{});
        const at = f.lockPoint();
        m.swing = @max(m.swing, mathx.distXZ(at, f.pos));
        m.out = @max(m.out, mathx.distXZ(at, f.pos) - f.bodyR());
        m.out = @max(m.out, at.y - f.topWorld().y);
        m.out = @max(m.out, f.pos.y - at.y);
        m.lo = @min(m.lo, at.y - f.pos.y);
        m.hi = @max(m.hi, at.y - f.pos.y);
    }
    return m;
}

test "THE MARK RIDES THE BODY, on every creature that has one" {
    const hero = v3(0, 0, 1.7);
    const MIN: f32 = 0.02;

    var toad = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, 0.3);
    var bowman = archermod.Archer.spawn(mathx.zero3, 0, 1.0, 0.3);
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    var zerk = koboldmod.Kobold.spawn(mathx.zero3, 0, 1.0, 0.3);
    var mother = broodmod.Spider.spawnAs(.mother, mathx.zero3, 0, 1.0, 0.3);
    var boards = warriormod.Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    var ghost = shademod.Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    var cap = shroommod.Shroom.spawn(mathx.zero3, 0, 1.0, 0.3);
    var knight = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var blade = duomod.Swordsman.spawn(mathx.zero3, 0, 1.0, 0.3);
    var staff = duomod.Magus.spawn(mathx.zero3, 0, 1.0, 0.3);

    // **AND IT RIDES IT — IT DOES NOT ORBIT THE WORLD.** `foe.markOn` takes a point in the BONE'S frame; the
    // duo handed it the world centre instead, so both marks landed a body-length past the far side of the map.
    // Nothing could SEE that point, which cost the pair their lock-on AND made `markSight` cast at open
    // ground — so a fog gate stopped blocking their aggro. One assertion here would have caught all of it.
    inline for (.{
        .{ "toad", &toad },      .{ "archer", &bowman },   .{ "ogre", &giant },
        .{ "berserker", &zerk },  .{ "mother", &mother },   .{ "shieldman", &boards },
        .{ "shade", &ghost },     .{ "sporeling", &cap },   .{ "knight", &knight },
        .{ "fungal sword", &blade }, .{ "fungal magus", &staff },
    }) |row| {
        const m = markSwing(row[1], hero);
        std.debug.print("\n  {s}: mark swings {d:.2} m, sits {d:.2}..{d:.2} m up, worst {d:.2} m out of its own standing box", .{ row[0], m.swing, m.lo, m.hi, m.out });
        try std.testing.expect(m.swing > MIN);
        try std.testing.expect(m.out <= 0.60);
    }
    std.debug.print("\n", .{});
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
    const rest = w.jawPoint().y - w.pos.y + 0.20 * w.scale;
    w.stagePounce(1.0);
    const full = w.jawPoint().y - w.pos.y + 0.20 * w.scale;
    w.stageBiteAt(wolfmod.STOOP_LOW * 0.5);
    const down = w.jawPoint().y - w.pos.y + 0.20 * w.scale;
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    var snag = rootedmod.Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    var plate = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var spore = shroommod.Shroom.spawn(mathx.zero3, 0, 1.0, 0.3);
    var hatch = broodmod.Spider.spawnAs(.broodling, mathx.zero3, 0, 1.0, 0.3);
    var toad = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, 0.3);
    std.debug.print("\n  wolf teeth reach {d:.2} m standing, {d:.2} m at a full pounce, {d:.2} m at a full stoop\n", .{ rest, full, down });
    try std.testing.expect(full > rest + 0.4);
    try std.testing.expectApproxEqAbs(wolfmod.TEETH_REST, rest, 0.04);
    try std.testing.expectApproxEqAbs(wolfmod.TEETH_POUNCE, full, 0.04);

    inline for (.{
        .{ "ogre", &giant },
        .{ "rooted", &snag },
        .{ "knight", &plate },
        .{ "sporeling", &spore },
        .{ "broodling", &hatch },
        .{ "toad", &toad },
    }) |row| {
        const f = row[1];
        const mid = f.centerWorld().y - f.pos.y;
        const r = f.hurtRadius();
        const floor = mid - r;
        const held = f.bodyR() + w.bodyR();
        const trigger = wolfmod.triggerR(f.bodyR());
        w.stageBiteAt(mid);
        const jaw = w.jawPoint().y - w.pos.y + 0.20 * w.scale;
        const dy = @abs(mid - jaw);
        const window: f32 = if (dy >= r) 0 else @sqrt(r * r - dy * dy);
        std.debug.print("  {s}: sphere {d:.2}..{d:.2} centre {d:.2} | pounce {d:.2} stoop {d:.2}, teeth at {d:.2} ({d:.2} into it), window {d:.2} m against a hold of {d:.2}\n", .{
            row[0], floor, mid + r, mid, wolfmod.pounceFor(mid), wolfmod.stoopFor(mid), jaw, jaw - floor, window, held,
        });
        try std.testing.expect(held < trigger);
        try std.testing.expect(@abs(mid - jaw) <= (1.0 - wolfmod.POUNCE_INTO) * r);
        // **A TARGET SMALLER THAN SHE IS HAS NO CHORD TO SPARE, so it answers the other bar.** A broodling's
        // hurt sphere is 0.38 m wide against colliders that hold her 0.79 m off its centre.
        const snout = w.jawPoint().z - w.pos.z;
        if (r >= held * 0.55) {
            try std.testing.expect(window > held * 0.55);
        } else {
            std.debug.print("    …and it is smaller than she is: snout reaches {d:.2} m forward against a hold of {d:.2}\n", .{ snout, held });
            try std.testing.expect(snout + r > held);
        }
    }
    try std.testing.expectApproxEqAbs(wolfmod.TEETH_STOOP, down, 0.06);
}

test "THE BERSERKER IS THE FASTEST THING ON FOOT — and he closes at a RUN, not a stroll" {
    const zerk = koboldmod.Kobold.spawnAs(.berserker, mathx.zero3, 0, 1.0, 0.3);
    const far = koboldmod.AGGRO_R * 0.9;
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
    const OGRE: f32 = 4.4;
    const share = tiltShare;

    try std.testing.expectApproxEqAbs(@as(f32, 1), share(OGRE, LOCK_TILT_NEAR - 1), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), share(OGRE, LOCK_TILT_FAR + 1), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), share(2.4, 1.0), 1e-4);

    var prev = share(OGRE, LOCK_TILT_FAR + 4);
    var d = LOCK_TILT_FAR + 4;
    while (d > 0) : (d -= 0.05) {
        const s = share(OGRE, d);
        try std.testing.expect(s >= prev - 1e-4);
        try std.testing.expect(s - prev < 0.05);
        prev = s;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1), prev, 1e-4);
}

fn groundActor(g: *const Game, pos: *rl.Vector3, dt: f32) void {
    groundActorFrom(g, pos, pos.y, dt);
}

/// **A FALLING BODY IS MEASURED FROM ITS FEET, NOT FROM `pos.y`.** `pos.y` is already the floor he is heading
/// for, so asked with itself the deck he is about to land ON is refused by its own `STEP_UP` gate and he drops
/// straight through it. Handed his real height, the answer walks DOWN the decks as he falls.
fn groundActorFrom(g: *const Game, pos: *rl.Vector3, refY: f32, dt: f32) void {
    const want = g.env.standAt(pos.x, pos.z, refY);
    const d = want - pos.y;
    if (@abs(d) > GROUND_SNAP) {
        pos.y = want;
        return;
    }
    const rate: f32 = if (d > 0) GROUND_RISE_RATE else GROUND_FALL_RATE;
    pos.y = mathx.approach(pos.y, want, rate * dt);
}

fn plantActor(g: *const Game, pos: *rl.Vector3) void {
    pos.y = g.env.standAt(pos.x, pos.z, pos.y);
}

/// **A DECK HAS AN EDGE, AND WALKING OFF ONE IS A FALL AND NOT A SNAP.** `groundActor` plants past
/// `GROUND_SNAP`, which off a five-metre floor is a teleport with a footstep on the end of it. Only a DECK does
/// this — the land keeps the snap it has always had, because terrain has no lip a body can be standing over.
fn heroFooting(g: *Game, was_: rl.Vector3) void {
    const h = &g.hero;
    if (h.climbing or h.dead) {
        g.heroDeck = null;
        return;
    }
    // **THE FLOOR GIVING WAY IS ONE QUESTION, AND WALKING OFF AN EDGE IS ONLY HALF OF IT.** Stepping into a
    // hatch drops him onto the floor below, not to the ground, so what is compared is the SURFACE either side
    // of the step rather than whether a deck is under him at all.
    const under = g.env.standAt(h.pos.x, h.pos.z, h.footY());
    if (g.heroDeck) |was| {
        // **HE CARRIES THE WAY HE WAS GOING, NOT THE WAY HE IS LOOKING.** Off his facing, a lock-on strafe or
        // a backpedal over the lip threw him forward off the deck — the one direction he was not travelling.
        if (!h.airborne() and under < was - envmod.STEP_UP) h.startFall(was, mathx.dirXZ(was_, h.pos), h.speedS);
    }
    g.heroDeck = if (h.airborne()) null else g.env.deckAt(h.pos.x, h.pos.z, h.pos.y);
}

pub fn envGroundAt(e: *const envmod.Env, x: f32, z: f32) f32 {
    return e.groundAt(x, z);
}

/// **THE LENS CLEARS THE FLOOR HE IS ON, NOT THE LAND UNDER IT.** `followClear` was handed `groundAt`, which on
/// the watchtower's roof is eleven metres below his boots — so the boom paid nothing, the eye sank through the
/// boards and the shot was the inside of the shaft. Off `standAt` the deck is the floor; past its edge the same
/// call answers with the land again, which is what a camera hanging out over a drop should see. Plumb ground is
/// unchanged: `standAt` IS `groundAt` wherever no deck is within the walk's own riser of him.
pub const CamFloor = struct {
    e: *const envmod.Env,
    footY: f32,

    pub fn at(c: CamFloor, x: f32, z: f32) f32 {
        return c.e.standAt(x, z, c.footY);
    }
};

pub fn camFloor(g: *const Game) CamFloor {
    return .{ .e = &g.env, .footY = g.hero.footY() };
}

fn snapshotPos(foes: anytype, out: []rl.Vector3) void {
    for (foes, 0..) |*f, i| {
        if (i >= out.len) return;
        out[i] = f.pos;
    }
}

/// **A SEALED ROOM IS A WALL FOR EXACTLY WHAT IS ALREADY IN IT**, and it is asked on the step's START and never
/// on where the body ended up — `Arena.hold` pushes an outside point IN, so asked about the destination it
/// would reach out and drag a creature walking past into the fight through its own wall.
///
/// **AND IT IS A PUSH-OUT RATHER THAN THE WARD'S REFUSAL** (`env.wardRefusing`). A body that blinks or
/// dissolves and comes back up (`fungalduo`'s magus, the shade, the blinkbat) never travels through its wall,
/// so there is no segment to refuse — only being stood back on the near side of the line answers it.
fn holdInRoom(m: *const worldfmt.Map, shut: []const bool, was: rl.Vector3, p: rl.Vector3, r: f32) rl.Vector3 {
    const i = m.arenaIndexAt(was.x, was.z) orelse return p;
    if (i >= shut.len or !shut[i]) return p;
    return m.arenas[i].hold(p, r);
}

/// **AND NOTHING ON FOOT WALKS INTO THE DEEP AFTER HIM** (`foe.wadeLimit`) — a creature turns back at its own hips, not the hero's waterline.
fn gateTerrain(g: *const Game, foes: anytype, was: []const rl.Vector3, group: ?FoeKind, crossesWards: bool) void {
    const T = @typeInfo(@TypeOf(foes)).pointer.child;
    for (foes, 0..) |*f, i| {
        if (i >= was.len) continue;
        if (comptime @hasDecl(T, "alive")) {
            if (!f.alive()) continue;
        }
        if (mathx.distXZ(was[i], f.pos) < 1e-5) continue;
        // …AND THE FOG GATE IS THE ONE REFUSAL A FLYER AND A BLINK ANSWER TO, so the whole travelled segment is
        // asked here. ABOVE the terrain skip, because a ward is not ground.
        if (!crossesWards and g.env.wardCrossed(was[i], f.pos) != null) {
            f.pos.x = was[i].x;
            f.pos.z = was[i].z;
            continue;
        }
        // ABOVE the airborne skip as well as the terrain one: a room is a wall to the full height of it, and
        // the flyers are the creatures a segment refusal was never going to hold.
        const held = holdInRoom(&g.map, &g.arenaShut, was[i], f.pos, bodyRadiusOf(f));
        f.pos.x = held.x;
        f.pos.z = held.z;
        if (comptime @hasDecl(T, "airborne")) {
            if (f.airborne()) continue;
        }
        const wade = if (comptime @hasDecl(T, "kind"))
            foemod.wadeLimit(f.kind(), statureOf(f))
        else if (group) |k|
            foemod.wadeLimit(k, statureOf(f))
        else
            foemod.WADE_FRAC * statureOf(f);
        const stepped = g.env.walkSegmentPast(was[i], f.pos, wade);
        f.pos.x = stepped.x;
        f.pos.z = stepped.z;
    }
}

/// What a wall stands the body back off, in metres. `bodyR` is `foe.zig`'s contract; the fallback is the hero's.
fn bodyRadiusOf(f: anytype) f32 {
    const T = std.meta.Child(@TypeOf(f));
    if (comptime @hasDecl(T, "bodyR")) return @max(f.bodyR(), 0.1);
    return HERO_R;
}

/// **THE BODY'S OWN HEIGHT, WHICH IS NOT ALWAYS THE BAR'S.** The bone skitterer's `topWorld` sits at 2.23 m
/// over a body 0.62 m tall, and read off the bar it would wade into a metre of water with the cage submerged.
fn statureOf(f: anytype) f32 {
    const T = std.meta.Child(@TypeOf(f));
    if (comptime @hasDecl(T, "stature")) return @max(f.stature(), 0.2);
    return @max(f.topWorld().y - f.pos.y, 0.2);
}

/// The ROLL and the LUNGE step through `mathx.stepXZ`, a clamp to the play square and nothing else, so 3.5 m
/// of roll crossed ground a walk refuses: `GROUND_RISE_RATE`'s 9 m/s over a 0.70 s roll is a 61 degree climb
/// against the walk's 40 cap. **AIRBORNE KEEPS ONLY THE WATER HALF** (`env.flyStep`) — no arc may end in the deep.
fn gateHeroTerrain(g: *Game, was: rl.Vector3) void {
    // Refused on the SEGMENT (`env.wardRefusing`) rather than left to the push-out: a roll is 3.5 m in one step and the sheet is 0.8 m thick.
    if (g.env.wardRefusing(was, g.hero.pos, if (g.gateWalk) |gw| gw.ward else null) != null) {
        g.hero.pos.x = was.x;
        g.hero.pos.z = was.z;
        return;
    }
    const out = gatedXZ(&g.env, was, g.hero.pos, g.hero.airborne());
    g.hero.pos.x = out.x;
    g.hero.pos.z = out.z;
    // **AND THE ROOM IS THE REST OF THE WALL THE GATE IS THE DOOR IN** (owner: I should not be able to exit a
    // fog until its bosses are killed). The ward refuses one line 0.8 m thick; on open ground that is a door
    // you stroll round. Held after the terrain gate — but NOT for the last time this frame: `collideActors`
    // runs 300 lines later and a boss with a SHOVE pressed him straight back out, so it holds him again there.
    const room = holdInRoom(&g.map, &g.arenaShut, was, g.hero.pos, HERO_R);
    g.hero.pos.x = room.x;
    g.hero.pos.z = room.z;
    markWardStep(g, was);
}

fn gatedXZ(e: *const envmod.Env, was: rl.Vector3, to: rl.Vector3, airborne: bool) rl.Vector3 {
    if (mathx.distXZ(was, to) < 1e-5) return to;
    if (airborne) {
        if (e.deepRefused(was.x, was.z, to.x, to.z)) return v3(was.x, to.y, was.z);
        return to;
    }
    const stepped = e.walkSegment(was, to);
    return v3(stepped.x, to.y, stepped.z);
}

test "EVERY LADDER ON THE BENCH TOPS OUT WHERE IT WAS AUTHORED TO, AND THE THREE THAT CANNOT REFUSE" {
    const m = try std.testing.allocator.create(worldfmt.Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    worldfmt.load("worlds/test_ladder.world", m, &ln) catch return error.SkipZigTest;
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    // The field goes in by hand: `uploadHeight` rebuilds the terrain MESHES, and there is no GL here.
    e.heightField = m.height;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
    e.materialize(m);

    const floor = propsmod.info(.watchtower).decks[0].y;
    const roof = propsmod.info(.watchtower).decks[2].y;
    // Authored foot (x, z), the height a body stands beside it at, and the ground it must put him down on —
    // null for a run that serves nothing and has to be refused.
    const want = [_]struct { x: f32, z: f32, at: f32 = 0, top: ?f32 }{
        .{ .x = 7.2, .z = 0, .top = 7.00 },
        .{ .x = 7.2, .z = -14, .top = null },
        .{ .x = -29.8, .z = 20, .top = 3.00 },
        .{ .x = -29.8, .z = 26, .top = null },
        .{ .x = -20, .z = 1.4, .top = floor },
        .{ .x = -20, .z = -1.4, .at = floor, .top = roof },
        .{ .x = -8, .z = -34, .top = null },
    };
    var found: usize = 0;
    std.debug.print("\n", .{});
    for (want) |w| {
        const r = e.ladderNear(v3(w.x, 0, w.z), w.at, LADDER_REACH + 0.4) orelse {
            std.debug.print("  ladder ({d:.1}, {d:.1}): NOT FOUND\n", .{ w.x, w.z });
            return error.TestUnexpectedResult;
        };
        found += 1;
        const head = r.foot.y + r.run;
        const exit = ladderExit(e, r);
        std.debug.print("  ladder ({d:6.1},{d:6.1}) foot {d:5.2} run {d:5.2} head {d:5.2} -> {s}\n", .{
            w.x, w.z, r.foot.y, r.run, head,
            if (exit) |x| blk: {
                var buf: [48]u8 = undefined;
                break :blk std.fmt.bufPrint(&buf, "steps off at {d:.2} m ({d:.2} off the head)", .{ x.y, x.y - head }) catch "?";
            } else "no exit — he rides the top rung",
        });
        if (w.top) |t| {
            const x = exit orelse return error.TestUnexpectedResult;
            try std.testing.expectApproxEqAbs(t, x.y, 0.02);
            // …and it is a step he could have taken on foot, in the band the exit is allowed to accept.
            try std.testing.expect(head - x.y <= envmod.LADDER_PROUD and x.y - head <= envmod.STEP_UP);
        } else {
            try std.testing.expectEqual(@as(?rl.Vector3, null), exit);
        }
    }
    try std.testing.expectEqual(want.len, found);
}

test "THE SHIPPED MAP'S WATCHTOWER IS CLIMBABLE TO ITS ROOF, in two flights" {
    const m = try std.testing.allocator.create(worldfmt.Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    worldfmt.load(worldfmt.START_MAP, m, &ln) catch return error.SkipZigTest;
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightField = m.height;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
    e.materialize(m);

    // The tower north-west of the colossal gate, and the ground under all of it is flat. The two floors are
    // read off the WORLD rather than off the kind's table, so what is asserted is the deck a body would find.
    const base = e.groundAt(-52, -104);
    const floor = e.deckAt(-52, -104, 5.0) orelse return error.TestUnexpectedResult;
    const roof = e.deckAt(-52, -104, 12.0) orelse return error.TestUnexpectedResult;
    try std.testing.expect(roof - floor > 6.5);
    const lower = e.ladderNear(v3(-52.479, 0, -105.316), base, LADDER_REACH) orelse return error.TestUnexpectedResult;
    const upper = e.ladderNear(v3(-51.521, 0, -102.684), floor, LADDER_REACH) orelse return error.TestUnexpectedResult;
    const outLo = ladderExit(e, lower) orelse return error.TestUnexpectedResult;
    const outHi = ladderExit(e, upper) orelse return error.TestUnexpectedResult;
    std.debug.print("\n  fallen plain watchtower: ground {d:.2} -> floor {d:.2} ({d:.2} m off the axis) -> roof {d:.2} ({d:.2} m off)\n", .{
        base, outLo.y, mathx.distXZ(outLo, v3(-52, 0, -104)), outHi.y, mathx.distXZ(outHi, v3(-52, 0, -104)),
    });
    try std.testing.expectApproxEqAbs(floor, outLo.y, 0.02);
    try std.testing.expectApproxEqAbs(roof, outHi.y, 0.02);
    // **HE STEPS OFF INBOARD, NOT THROUGH THE WALL AND NOT ONTO THE MERLONS.** Both exits must land inside the
    // shaft's clear radius: below, stone refuses the wall side; on the roof, the ledge test does.
    try std.testing.expect(mathx.distXZ(outLo, v3(-52, 0, -104)) < propsmod.TOWER_CLEAR);
    try std.testing.expect(mathx.distXZ(outHi, v3(-52, 0, -104)) < propsmod.TOWER_CLEAR);

    // **AND HE CAN GET IN AT ALL.** Not a straight line — the forecourt has a brazier in it and a body walks
    // round that — so this is a FLOOD over the floor at ankle height, from outside the door to the foot of the
    // lower ladder. It is the whole question the lintel broke: the course over the doorway is a wall to a body
    // on a deck and has to be nothing at all to one on the ground.
    const G: f32 = 0.15;
    const SPAN: usize = 96;
    const org = v3(-52 - 0.5 * G * SPAN, 0, -104 - 0.5 * G * SPAN);
    var open = [_]bool{false} ** (SPAN * SPAN);
    var seen = [_]bool{false} ** (SPAN * SPAN);
    for (0..SPAN) |iz| {
        for (0..SPAN) |ix| {
            const at = v3(org.x + G * @as(f32, @floatFromInt(ix)), base + 0.20, org.z + G * @as(f32, @floatFromInt(iz)));
            open[iz * SPAN + ix] = !e.blockedNear(at, HERO_R, 1.2);
        }
    }
    const cellOfXZ = struct {
        fn go(o: rl.Vector3, x: f32, z: f32) usize {
            const ix: usize = @intFromFloat(@round((x - o.x) / G));
            const iz: usize = @intFromFloat(@round((z - o.z) / G));
            return @min(iz, SPAN - 1) * SPAN + @min(ix, SPAN - 1);
        }
    }.go;
    const th = mathx.radians(200.0);
    const face = v3(-mathx.sinf(th), 0, -mathx.cosf(th));
    const from = cellOfXZ(org, -52 + face.x * 6.6, -104 + face.z * 6.6);
    const want = cellOfXZ(org, lower.axis.x, lower.axis.z);
    try std.testing.expect(open[from] and open[want]);
    var queue: [SPAN * SPAN]usize = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = from;
    seen[from] = true;
    while (head < tail) : (head += 1) {
        const c = queue[head];
        const cx = c % SPAN;
        const cz = c / SPAN;
        for ([_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |d| {
            const nx = @as(i32, @intCast(cx)) + d[0];
            const nz = @as(i32, @intCast(cz)) + d[1];
            if (nx < 0 or nz < 0 or nx >= SPAN or nz >= SPAN) continue;
            const n = @as(usize, @intCast(nz)) * SPAN + @as(usize, @intCast(nx));
            if (seen[n] or !open[n]) continue;
            seen[n] = true;
            queue[tail] = n;
            tail += 1;
        }
    }
    std.debug.print("  doorway: {d} of {d} cells reachable on foot from outside; foot of the ladder {s}\n", .{
        tail, SPAN * SPAN, if (seen[want]) "REACHED" else "WALLED OFF",
    });
    if (!seen[want]) {
        var iz: usize = 0;
        while (iz < SPAN) : (iz += 2) {
            var line: [SPAN / 2]u8 = undefined;
            var ix: usize = 0;
            while (ix < SPAN) : (ix += 2) {
                const c = iz * SPAN + ix;
                line[ix / 2] = if (c == want) 'L' else if (c == from) 'S' else if (seen[c]) '.' else if (open[c]) 'o' else '#';
            }
            std.debug.print("    {s}\n", .{line[0..]});
        }
    }
    try std.testing.expect(seen[want]);

    // …and the same walk at deck height is stopped, because up there the doorway is wall like every other side.
    try std.testing.expect(e.blockedNear(v3(-52 + face.x * 2.35, floor + 0.20, -104 + face.z * 2.35), HERO_R, 1.2));
}

test "THE ROLL OBEYS THE GROUND — a committed move may not take him up what a walk refuses" {
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightAny = true;
    e.heightHalf = 100.0;
    // One lattice pitch is 2*half/(N-1) ≈ 0.90 m, so the riser is far past `STEP_UP` (0.55) and its slope far past `MAX_SLOPE` (tan 40).
    const pitch = 2 * e.heightHalf / @as(f32, @floatFromInt(worldfmt.HEIGHT_N - 1));
    for (0..worldfmt.HEIGHT_N) |zi| {
        for (0..worldfmt.HEIGHT_N) |xi| {
            const x = @as(f32, @floatFromInt(xi)) * pitch - e.heightHalf;
            e.heightField[zi * worldfmt.HEIGHT_N + xi] = if (x < 0) worldfmt.HEIGHT_ZERO else worldfmt.HEIGHT_ZERO + 24;
        }
    }
    const rise = e.groundAt(2.0, 0) - e.groundAt(-2.0, 0);
    try std.testing.expect(rise > 4.0);

    // ONE FRAME OF A ROLL at its peak — `hero.ROLL_DIST` over its own duration, braked, is about 7 m/s.
    const was = v3(-0.30, 0, 0);
    const step = heromod.ROLL_DIST / (0.70 * 0.5 * 1.42) / 60.0;
    const raw = v3(was.x + step, 0, was.z);
    try std.testing.expect(raw.x > was.x);
    const walked = gatedXZ(e, was, raw, false);
    try std.testing.expectApproxEqAbs(was.x, walked.x, 1e-4);
    const flown = gatedXZ(e, was, raw, true);
    try std.testing.expectApproxEqAbs(raw.x, flown.x, 1e-4);
    std.debug.print(
        "\n  hero gate: wall rises {d:.2} m over {d:.2} m; a {d:.3} m roll step is held at x {d:.3}\n",
        .{ rise, pitch, step, walked.x },
    );
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
    const sprinting = isMoving and sprintingMove(mv);
    if (isMoving) {
        dir = v3(dir.x / l, 0, dir.z / l);
        speed = mv.speed * g.hero.moveRate();
        moveYaw = mathx.headingXZ(dir);
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

/// Always true in play — the eyes are an authoring view and the game may not be able to tell they exist.
fn shows(g: *const Game, l: editormod.Layer) bool {
    return !g.editor.on or g.editor.visible(l);
}

fn drawCasters(g: *Game, cull: envmod.Cull) void {
    // GATED IN BOTH PASSES, because this function is the depth pass too (`drawCasters`): a prop hidden in colour but still laid into the shadow map is a shadow with nothing casting it.
    if (shows(g, .props)) g.env.drawProps(cull);
    if (shows(g, .interact)) {
        g.chests.draw();
        if (cull == .view) g.chests.drawGlow(&g.scene);
    }
    g.hero.drawRoots();
    const fade = heroFade(g);
    const seeThrough = cull == .view and fade < 0.999;
    if (cull == .view) g.scene.setFlash(0.6 * g.hero.hurtFlash);
    if (!(seeThrough and fade <= 0.001)) {
        if (seeThrough) {
            g.scene.setFade(fade);
            rl.gl.rlDisableDepthMask();
        }
        g.hero.draw(cull == .view);
        if (seeThrough) {
            rl.gl.rlEnableDepthMask();
            g.scene.setFade(1);
        }
    }
    if (cull == .view) g.scene.setFlash(0);
    const flashPass: ?*gfx.Scene = if (cull == .view) &g.scene else null;
    inline for (FOE_GROUPS) |f| @field(g, f.field).draw(flashPass);
    g.folk.draw();
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

/// The volley's stagger is the creature's own clock; all this does is put each shot in the pool as it leaves the fists.
fn spawnSpark(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), hollowmod.SPARK_SPEED, hollowmod.SPARK_HIT, true, .spark));
}

pub fn spawnWisp(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), shademod.WISP_SPEED, shademod.WISP_HIT, true, .wisp));
}

fn spawnEmber(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), magemod.EMBER_SPEED, magemod.EMBER_HIT, true, .emberball));
}

fn spawnSac(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), golemmod.SAC_SPEED, golemmod.SAC_HIT, true, .sac));
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

/// THE YANK IN REVERSE (`applyYank`, same walk). Only on a blow that actually landed — a guard that ate it holds its ground.
fn heroShoved(g: *Game, from: rl.Vector3, push: f32, out: combat.HitOutcome) void {
    switch (out) {
        .blocked, .ignored => return,
        .taken, .guardBroken => {},
    }
    const dir = mathx.dirXZ(from, g.hero.pos);
    if (mathx.lenXZ(dir) < 1e-3) return;
    g.hero.pos = inBounds(g.env.walkStep(g.hero.pos, mathx.normV(dir), push));
}

pub fn leechSip(g: *Game, h: combat.Hit) void {
    _ = g.hero.burn(h);
}

fn armScript(g: *Game) void {
    g.folk.reset(&g.map);
    g.trig.arm(&g.map);
    g.talk = .{};
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
    const blow = heromod.arrowBlow(kind, true, g.hero.perk);
    putIn(&g.shafts, archermod.launchShaft(g.hero.nockWorld(), at, heromod.BOW_AIMED_SPEED, blow, false, heromod.arrowShot(kind)));
}
pub fn throwBoltForShot(g: *Game, at: rl.Vector3) void {
    launchBolt(g, at, false, combat.BOLT_HIT);
}

pub fn stepShaftsForShot(g: *Game, dt: f32) void {
    stepShafts(g, dt);
}
pub fn tickPoisonForShot(g: *Game, dt: f32) void {
    g.hero.poisonBy(g.brood.burn(dt, g.hero.pos));
    g.hero.poisonBy(g.cluster.spores(dt, g.hero.pos));
    g.hero.doseSelf(.burning, g.scorch.scorching(dt, g.hero.pos));
    _ = g.hero.tickPoison(dt);
}
pub fn flyingPointForShot(g: *Game, kind: archermod.Shot) ?rl.Vector3 {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (ar.live and ar.shot == kind) return ar.pos;
        }
    }
    return null;
}

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
        // **THE HARNESS STILL HAS TO SPEND THE ONE-FRAME FLAG.** A flag reset on only ONE of its two drive paths latches for the rest of the run.
        ar.bounced = false;
    }
}
pub fn clearShaftsForShot(g: *Game) void {
    clearQuivers(g);
}

pub fn ringForShot(g: *Game, u: f32) void {
    g.hero.stageRing(u);
}

pub fn callWolfForShot(g: *Game, at: rl.Vector3, facing: f32) void {
    g.pack.clear();
    _ = g.pack.call(at, facing);
}

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
    restmod.drawScreen(&g.rest, restView(g));
}

/// Takes no `Game`: `saveMark` ticks a clock the shot loop never runs, and the frame worth photographing is a chosen one (`pinHourForShot`).
pub fn drawSaveMarkForShot(left: f32) void {
    hud_.saveTree(left);
}

pub fn forceWeatherForShot(g: *Game, k: weathermod.Kind, flashAt: f32) void {
    g.weather.force(k, 600.0);
    g.weather.flashT = flashAt;
    g.weather.nextFlash = 1e9;
}
pub fn clearWeatherForShot(g: *Game) void {
    g.weather = weathermod.Weather.init(0x5701_A17E);
}

pub fn forceFogForShot(g: *Game, on: bool) void {
    g.menu.forceFog(on);
}
pub fn forceMistForShot(g: *Game, ahead: f32) void {
    const p = v3(g.hero.pos.x, g.env.groundAt(g.hero.pos.x, g.hero.pos.z), g.hero.pos.z);
    g.mist.stageOne(p, ahead, g.hero.facing);
}
/// **THE BIRDS COME BY ONCE EVERY FEW MINUTES**, so a harness that waited for one would never take the picture.
/// `across` is the bearing off his facing, since what the shot is of is a skein crossing his sky and not one
/// flying at the lens.
pub fn forceSkeinForShot(g: *Game, across: f32) void {
    g.skein.stageOne(g.hero.pos, g.env.groundAt(g.hero.pos.x, g.hero.pos.z), g.hero.facing + across);
}
pub fn skeinLeadForShot(g: *const Game) rl.Vector3 {
    return g.skein.leadAt();
}
pub fn openCounterForShot(g: *Game, t: countermod.Trade) void {
    g.counter.begin(t);
    g.counterT = counterui.RAISE;
}

pub fn counterSellForShot(g: *Game) void {
    g.counter.selling = true;
    g.counter.sel = 0;
}

pub fn closeCounterForShot(g: *Game) void {
    g.counter.close();
    g.hero.held = false;
}

pub fn openChestForShot(g: *Game) bool {
    const had = g.chests.near != null;
    interact(g);
    return had;
}

pub fn openTalkForShot(g: *Game, name: []const u8) bool {
    const dlg = g.map.findDialog(name) orelse return false;
    g.folk.update(SHOT_STEP, g.hero.pos, PLAY_HALF);
    const npc: ?usize = g.folk.near;
    const who: []const u8 = if (npc) |i| npcmod.nameOf(&g.map, (g.folk.at(i) orelse return false).rec) else "";
    if (!g.talk.open(&g.map, &g.trig, dlg, who, npc)) return false;
    if (npc) |i| {
        if (g.folk.at(i)) |p| p.talking = true;
    }
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
    const p = g.folk.at(i) orelse return null;
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
        .yaw = w.facing + mathx.radians(hud_.PORTRAIT_YAW),
        .pitch = hud_.PORTRAIT_PITCH,
        .dist = wolfmod.PORTRAIT_DIST,
        .fov = hud_.PORTRAIT_FOV,
        .ctx = @ptrCast(g),
        .drawFn = drawSpiritHead,
    };
}
fn spiritFaceFor(g: *Game) bool {
    if (spiritPortrait(g)) |lp| {
        if (!hud_.hasSpiritFace()) _ = hud_.takeSpiritFace(lp);
        return hud_.hasSpiritFace();
    }
    if (g.spiritK <= 0.004) hud_.dropSpiritFace();
    return hud_.hasSpiritFace();
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
/// Stage a sorcery for the harness: the rack holds three, so the sixth spell cannot be reached by cycling.
pub fn selectSpellForShot(g: *Game, s: combat.Spell) void {
    g.hero.memorize(0, s);
    g.hero.spell = s;
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
    ladder,
    gate,

    fn prompt(self: Reach) hud_.Hint {
        return .{ .glyph = .{ .face = hud_.BTN_INTERACT }, .label = switch (self) {
            .souls => "Reclaim",
            .rest => "Rest",
            .pickup => "Take",
            .talk => "Speak",
            .chest => "Open",
            .ladder => "Climb",
            .gate => "Enter",
        } };
    }
};

/// **A REACH IS A CIRCLE IN THE GROUND PLANE, AND A FLOOR IS NOT.** Every `near` ring — the drop, the bonfire,
/// the glow, the box, the folk — is `mathx.Nearest`, which is XZ and pinned to be (its own test offers a body
/// forty metres up and expects it taken). That was the whole truth while every body stood on the land; with
/// decks a man on the watchtower's roof stands 11.9 m over its yard and inside all five rings, so he reclaimed
/// his souls, opened a box and sat down at a bonfire through the boards.
///
/// **AND THE BAND IS ONLY EVER ASKED OF A BODY UP ON A DECK** (`Game.heroDeck`). Sculpted LAND inside a ring
/// can be nearly the ring's own width away in height, because the walk allows a riser per lattice cell —
/// MEASURED on the shipped map, one glow has 1.65 m of hillside inside its 2.4 m ring — so a band over the
/// TERRAIN would take prompts off a map that has always worked. A deck is flat and the shortest storey is
/// 4.69 m, so up there the band is only ever asked to tell one floor from another, and twice the walk's own
/// riser does that with room to spare.
const REACH_RISE: f32 = 2.0 * envmod.STEP_UP;
comptime {
    std.debug.assert(REACH_RISE < propsmod.info(.watchtower).decks[0].y);
}

/// Is the thing on the floor he is standing on? `null` is the LAND, which is never gated.
fn onSameFloor(deck: ?f32, thingY: f32) bool {
    const d = deck orelse return true;
    return @abs(thingY - d) <= REACH_RISE;
}

fn atHisLevel(g: *const Game, y: f32) bool {
    return onSameFloor(g.heroDeck, y);
}

test "A REACH IS REFUSED THROUGH A FLOOR, AND NEVER REFUSED ACROSS THE LAND" {
    const floor = propsmod.info(.watchtower).decks[0].y;
    const roof = propsmod.info(.watchtower).decks[2].y;
    // **ON THE LAND THERE IS NO GATE AT ALL**, whatever the hillside is doing — that is the whole shape of the
    // rule, and the ring walk below is why.
    try std.testing.expect(onSameFloor(null, 0));
    try std.testing.expect(onSameFloor(null, -40));
    try std.testing.expect(onSameFloor(null, roof));
    // Up on a floor, neither the yard below nor the other storey is his.
    try std.testing.expect(onSameFloor(roof, roof));
    try std.testing.expect(onSameFloor(roof, roof + envmod.STEP_UP));
    try std.testing.expect(!onSameFloor(roof, 0));
    try std.testing.expect(!onSameFloor(roof, floor));
    try std.testing.expect(!onSameFloor(floor, 0));

    const m = try std.testing.allocator.create(worldfmt.Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    worldfmt.load(worldfmt.START_MAP, m, &ln) catch return error.SkipZigTest;
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightField = m.height;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
    e.materialize(m);

    // **WHY THE GATE MAY NOT BE ASKED OF THE TERRAIN.** This walks the ring round every placed interactable on
    // the shipped map and takes the worst standing height on it. The number is most of the ring's own width —
    // the walk allows a riser per lattice cell — so a band over the LAND would have taken working prompts off
    // a map that has always worked, which is what sent the gate to the DECK.
    var boxes: [chestmod.CAP]chestmod.Site = undefined;
    var fires: [restmod.CAP]restmod.Site = undefined;
    var glows: [pickupmod.CAP]pickupmod.Site = undefined;
    const nb = e.chestSites(&boxes);
    const nf = e.restSites(&fires);
    const ng = e.pickupSites(&glows);
    std.debug.print("\n  reach band +/-{d:.2} m, asked only on a deck; a storey is {d:.2} m\n", .{ REACH_RISE, floor });
    inline for (.{
        .{ "chest ", chestmod.REACH, boxes[0..nb] },
        .{ "rest  ", restmod.REACH, fires[0..nf] },
        .{ "pickup", pickupmod.REACH, glows[0..ng] },
    }) |ring| {
        var worst: f32 = 0;
        for (ring[2]) |site| {
            var k: usize = 0;
            while (k < 32) : (k += 1) {
                const a = std.math.tau * @as(f32, @floatFromInt(k)) / 32.0;
                const gx = site.pos.x + mathx.cosf(a) * ring[1];
                const gz = site.pos.z + mathx.sinf(a) * ring[1];
                worst = mathx.maxF(worst, @abs(e.standAt(gx, gz, site.pos.y) - site.pos.y));
            }
            // …and every one of them keeps its prompt, because none of them stands on a deck.
            try std.testing.expect(onSameFloor(e.deckAt(site.pos.x, site.pos.z, site.pos.y), site.pos.y));
        }
        std.debug.print("  {s}: {d:3} sites, worst land {d:.2} m off the site inside its {d:.1} m ring\n", .{
            ring[0], ring[2].len, worst, ring[1],
        });
    }
}

fn inReach(g: *const Game, r: Reach) bool {
    return switch (r) {
        .souls => g.souls.near and atHisLevel(g, g.souls.drop.at.y),
        .rest => if (g.rest.near) |i| atHisLevel(g, g.rest.list[i].pos.y) else false,
        .pickup => if (g.pickups.near) |i| atHisLevel(g, g.pickups.list[i].pos.y) else false,
        .talk => talkable(g),
        .chest => if (g.chests.near) |i| atHisLevel(g, g.chests.list[i].pos.y) else false,
        .ladder => ladderAt(g) != null,
        .gate => gateAt(g) != null,
    };
}

const GATE_MARGIN: f32 = 1.15;
comptime {
    // HE MAY NOT STEP OUT OF A GATE INTO ITS OWN PROMPT: the crossing lands him `WARD_CLEAR` past the sheet and the prompt reaches `GATE_MARGIN`, both off the same capsule.
    std.debug.assert(envmod.WARD_CLEAR > GATE_MARGIN);
    // …and `props` sits UNDER `foes/`, so the body's radius in `props.TOWER_CLEAR` is a copy. Pinned here, the
    // one file that sees both, or the shaft's clear standing room drifts off the body it was solved for.
    std.debug.assert(propsmod.HERO_R_HERE == HERO_R);
}

fn gateAt(g: *const Game) ?u8 {
    if (g.gateWalk != null or g.hero.committed() or g.hero.dead) return null;
    return g.env.nearWard(g.hero.pos, GATE_MARGIN + HERO_R);
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
        .ladder => mountLadder(g),
        .gate => enterGate(g),
    }
}

/// How far from a ladder's climbing line he may stand and still get on it. Between `chest.REACH` 2.1 and the
/// pickup's 2.4 would be far too generous for a thing 0.5 m wide: this is a reach for the RAILS.
pub const LADDER_REACH: f32 = 1.5;
/// The step off the head of a ladder onto whatever holds him. **PAST THE LIP AND NOT ONTO IT** — a heightfield
/// cliff ramps over one lattice cell (0.54 m at the shipped map's spacing), so a shorter stride lands him
/// halfway up the ramp, reads as not solid ground, and refuses the exit.
const LADDER_EXIT: f32 = 1.20;
/// Metres of run he covers in the beat between one hand-over-hand voice and the next.
const CLIMB_STEP_EVERY: f32 = 0.62;
/// Apex of the peel-off when a blow lands on him up there. Small: he is knocked LOOSE, and the drop does the
/// rest — there is no fall damage in this game, so the price is the climb and the ground he lands in front of.
const LADDER_KNOCK_APEX: f32 = 0.35;

/// **A LADDER HE IS ON.** Solved once at the mount — the axis never moves and the run never changes — so no
/// frame of the climb re-derives which prop he is standing on.
const Climb = struct {
    rung: envmod.Rung,
    /// The world line his BODY stands on, `LADDER_STANDOFF` off the rung plane on the ladder's open side.
    axis: rl.Vector3,
    /// Metres of run under his feet: 0 at the foot, `rung.run` at the head.
    at: f32,
    face: f32,
    /// Run since the last hand-over-hand, so the voice is spent by DISTANCE like every other footfall here.
    beat: f32 = 0,
};

/// **A CLIMB AND A FALL OFF A FLOOR ARE NOT A JUMP** — the lens takes all of those, where it takes just over
/// half a hop (`camera.LIFT_SHARE`). Split on the height itself and not on the state, so the knock-off's own
/// arc, which starts as a launch and ends as a plain landing, never changes rule mid-flight.
/// **THE LENS FOLLOWS HIS FEET AND NOT HIS `pos.y`.** Both jump — `groundActor` PLANTS past `GROUND_SNAP`, and
/// a mount or a top-out moves `pos.y` and `lift` the opposite way in one frame — while `pos.y + lift` is
/// continuous through every one of those. The rig eases only the lift, so a frame where the ground under him
/// moved a whole plant re-seeds it rather than chasing a discontinuity it should never have been shown.
fn syncLensLift(g: *Game) void {
    if (@abs(g.hero.pos.y - g.lensGroundY) > GROUND_SNAP * 0.5) g.rig.lift = liftShare(&g.hero) * g.hero.lift;
    g.lensGroundY = g.hero.pos.y;
}

fn liftShare(h: *const heromod.Hero) f32 {
    if (h.climbing or h.lift > heromod.JUMP_APEX) return 1.0;
    return cameramod.LIFT_SHARE;
}

fn ladderAt(g: *const Game) ?envmod.Rung {
    if (g.climb != null or g.gateWalk != null or !g.hero.bodyFree()) return null;
    return g.env.ladderNear(g.hero.pos, g.hero.footY(), LADDER_REACH);
}

/// The ladder's own +Z: the open side he mounts from, and the side his body hangs on all the way up.
fn ladderOut(r: envmod.Rung) rl.Vector3 {
    return mathx.headingDir(mathx.radians(r.yaw));
}

fn mountLadder(g: *Game) void {
    const r = ladderAt(g) orelse return;
    const out = ladderOut(r);
    const axis = r.axis;
    g.hero.pos.x = axis.x;
    g.hero.pos.z = axis.z;
    g.hero.pos.y = g.env.groundAt(axis.x, axis.z);
    const face = mathx.headingXZ(mathx.scaleV(out, -1));
    g.climb = .{
        .rung = r,
        .axis = axis,
        .at = mathx.clampF(g.hero.footY() - r.foot.y, 0, r.run),
        .face = face,
    };
    g.lock = null;
    g.hero.startClimb(r.foot.y + g.climb.?.at - g.hero.pos.y, face);
    sfx.play(.step_soft);
}

/// **HE COMES OFF THE WAY HE WENT ON, OR HE FALLS.** Nothing else clears the state: a climb abandoned with the
/// hero left holding a `lift` is a man standing in the air.
fn leaveLadder(g: *Game) void {
    g.climb = null;
    g.hero.endClimb();
}

/// **EVERY DOOR OUT OF A PLACE LETS GO OF THAT PLACE.** A crossing, a run up a ladder and the floor under his
/// boots all name somewhere in the map being left, and spelled out at each door a fifth one forgets one of the
/// three. The run goes through `leaveLadder` and never through `g.climb = null`: that field is HALF of a climb,
/// and the half in the BODY (`hero.climbing`, and the `lift` carrying him up the run) is what strands a man in
/// the air, permanently `committed()`. Both `beginGame`'s callers — new game and load — are reachable from the
/// pause menu with him eight metres up a ladder, and both cleared only the field.
fn leavePlace(g: *Game) void {
    g.gateWalk = null;
    leaveLadder(g);
    g.heroDeck = null;
}

/// **STEPPING OFF THE BOTTOM PUTS HIM ON WHATEVER THE BOTTOM STANDS ON.** `endClimb` only drops the `lift`, and
/// `pos.y` has been the ground under the ladder's FOOT the whole climb — which for the flight that stands on a
/// floor is a storey below where he is. Asked at the foot's own height, `standAt` answers with that floor.
fn footOffLadder(g: *Game) void {
    const c = &(g.climb orelse return);
    const at = c.rung.foot.y;
    g.hero.pos.y = g.env.standAt(c.axis.x, c.axis.z, at);
    g.heroDeck = g.env.deckAt(c.axis.x, c.axis.z, g.hero.pos.y);
    leaveLadder(g);
}

fn dropOffLadder(g: *Game) void {
    if (g.climb == null) return;
    const face = g.hero.facing;
    const from = g.hero.footY();
    leaveLadder(g);
    g.hero.startFall(from, mathx.headingDir(face + std.math.pi), heromod.WALK_SPEED);
}

/// **A BLOW UP THERE TAKES THE LADDER AWAY.** Routed through the launch, so the arc, the pose and the landing
/// beat are the ones a slam already gives — the only new thing is the height it starts from.
fn knockOffLadder(g: *Game, b: foemod.Blow) void {
    if (g.climb == null) return;
    const from = g.hero.footY();
    const away = mathx.dirXZ(b.from, g.hero.pos);
    leaveLadder(g);
    _ = g.hero.launchFrom(away, LADDER_KNOCK_APEX, from);
}

/// Where the head of the ladder puts him down. **THE WALL SIDE IS ASKED FIRST** — that is topping out over a
/// lip, which is what a ladder up a cliff is for; the open side is the answer inside a shaft, where he comes up
/// through a hatch and steps off onto the floor he just passed. Neither holding him is a ladder to nowhere, and
/// he simply stays on it.
fn ladderExit(e: *const envmod.Env, r: envmod.Rung) ?rl.Vector3 {
    const head = r.foot.y + r.run;
    const out = ladderOut(r);
    const step = LADDER_EXIT * r.scale;
    var ledge: ?rl.Vector3 = null;
    for ([_]f32{ -step, step }) |k| {
        const x = r.axis.x + out.x * k;
        const z = r.axis.z + out.z * k;
        const y = e.standAt(x, z, head);
        if (head - y > envmod.LADDER_PROUD or y - head > envmod.STEP_UP) continue;
        if (e.blockedNear(v3(x, y + 0.4, z), HERO_R, 1.4)) continue;
        // **AND IT MAY NOT BE A LEDGE.** One more stride the same way has to hold him too, or topping out
        // lands him with his heels over the drop. Stone is what refuses the wall side inside a shaft; on a
        // ROOF both sides are the same deck and there is no wall left to do it — this is what tells them apart,
        // and it is why he steps off a parapet ladder inboard rather than onto the merlons.
        const on = e.standAt(x + out.x * k, z + out.z * k, y);
        if (y - on <= envmod.STEP_UP) return v3(x, y, z);
        if (ledge == null) ledge = v3(x, y, z);
    }
    return ledge;
}

fn topOutLadder(g: *Game) void {
    const c = &(g.climb orelse return);
    const at = ladderExit(&g.env, c.rung) orelse return;
    leaveLadder(g);
    g.hero.pos = at;
    g.heroDeck = g.env.deckAt(at.x, at.z, at.y);
    sfx.play(.land);
}

/// Driven by the distance he actually covers, like the gate walk and the gait — a fixed clock over a run that
/// varies by metres is a climb that is sometimes a sprint.
fn updateClimb(g: *Game, dt: f32, mv: Move) void {
    const c = &(g.climb orelse return);
    // **THE STICK IS THE LADDER'S, NOT THE CAMERA'S.** Forward is up whichever way the lens is pointing, or a
    // camera swung round to look at the wall would send him back down it.
    const drive = mathx.clampF(mv.fz, -1, 1);
    const down = if (sprintingMove(mv)) heromod.CLIMB_SLIDE_SPEED else heromod.CLIMB_DOWN_SPEED;
    const rate: f32 = if (drive >= 0) heromod.CLIMB_SPEED else down;
    const want = drive * rate * dt;
    const was = c.at;
    c.at = mathx.clampF(c.at + want, 0, c.rung.run);
    const moved = c.at - was;
    g.hero.pos.x = c.axis.x;
    g.hero.pos.z = c.axis.z;
    g.hero.facing = c.face;
    g.hero.tickClimb(dt, c.rung.foot.y + c.at - g.hero.pos.y, moved);
    g.hero.pose();
    c.beat += @abs(moved);
    if (c.beat >= CLIMB_STEP_EVERY) {
        c.beat = 0;
        sfx.playAt(.step_hard, 0.62);
    }
    if (moved > 0 and c.at >= c.rung.run - 1e-4) return topOutLadder(g);
    if (moved < 0 and c.at <= 1e-4) return footOffLadder(g);
}

/// The whole line comes off the sheet (`env.wardCross`), not his facing, so entering at an angle still puts him
/// out square. A SPEED and not a duration — a fixed clock over a distance that varies by metres is a walk that is sometimes a run.
pub const GATE_SPEED: f32 = heromod.WALK_SPEED * 0.66;

const GateWalk = struct {
    ward: u8,
    from: rl.Vector3,
    to: rl.Vector3,
    dir: rl.Vector3,
    dur: f32,
    t: f32 = 0,
    motes: f32 = 0,
};

fn enterGate(g: *Game) void {
    const w = gateAt(g) orelse return;
    const x = g.env.wardCross(w, g.hero.pos, HERO_R) orelse return;
    g.gateWalk = .{
        .ward = w,
        .from = g.hero.pos,
        .to = x.to,
        .dir = x.dir,
        .dur = mathx.maxF(mathx.distXZ(g.hero.pos, x.to) / GATE_SPEED, 0.35),
    };
    g.hero.sprinting = false;
    g.hero.setGuard(false);
    g.hero.setAim(false);
    g.lock = null;
    sfx.play(.fog_pass);
}

/// Driven by the distance he is actually covering rather than by a speed handed in, so the feet cannot skate (the rig's law).
fn updateGateWalk(g: *Game, dt: f32) void {
    const gw = &(g.gateWalk orelse return);
    const was = g.hero.pos;
    gw.t = mathx.minF(gw.t + dt / gw.dur, 1.0);
    const at = mathx.lerpV(gw.from, gw.to, mathx.smoothstep(0, 1, gw.t));
    g.hero.pos.x = at.x;
    g.hero.pos.z = at.z;
    const moved = mathx.distXZ(was, g.hero.pos);
    const face = mathx.headingXZ(gw.dir);
    g.hero.facing = face;
    g.hero.update(dt, moved, if (dt > 0) moved / dt else 0, face);
    // Replayed HERE like every other branch of the loop's state chain: `hero.update` only advances the clocks and the gait phase.
    g.hero.pose();
    gw.motes += dt * heromod.FOG_WAKE_RATE;
    var n: u32 = 0;
    while (gw.motes >= 1.0 and n < heromod.FOG_WAKE_CAP) : (n += 1) gw.motes -= 1.0;
    if (n > 0) g.hero.fogWake(g.hero.shoulderPoint(), gw.dir, n);
    // **HELD AT FULL FOR THE WHOLE CROSSING, NOT ARMED AT THE END OF IT.** `hero.tickFogGrace` spends the tail
    // on GROUND SPEED, and the walk is the one movement that is not his — re-held each frame, he is untouchable
    // from the sheet to the far side and the tail starts on the first step he takes himself.
    g.hero.startFogGrace();
    if (gw.t >= 1.0) g.gateWalk = null;
}

fn ringBell(g: *Game) void {
    if (!g.hero.canRing()) return;
    if (g.bag.count(combat.scrollFor(g.hero.spirit)) == 0) {
        g.trig.say("No spirit scroll.");
        sfx.play(.refused);
        return;
    }
    if (!g.pack.room()) {
        g.trig.say("A spirit is already out.");
        sfx.play(.refused);
        return;
    }
    if (g.hero.requestRing()) sfx.play(.wand_charge);
}

/// A rod with an empty rack SAYS SO (`ringBell`'s shape one hand along) rather than eating the press.
fn castWand(g: *Game) void {
    if (!g.hero.castReady()) return;
    if (!g.hero.armed()) {
        g.trig.say("Nothing memorized.");
        sfx.play(.refused);
        return;
    }
    if (g.hero.requestCast()) sfx.play(.wand_charge);
}

fn summonSpirit(g: *Game) void {
    const at = spiritSpot(g);
    if (!g.pack.call(at, g.hero.facing)) return;
    sfx.world(.wolf_howl, at);
    g.rig.addShake(SHAKE_LAND);
    g.rumble.play(rumblemod.cast_throw);
}

const SUMMON_BEARING: f32 = 2.5; // radians off his facing
const SUMMON_R: f32 = 1.9;

fn spiritSpot(g: *Game) rl.Vector3 {
    const back = mathx.headingDir(g.hero.facing + SUMMON_BEARING);
    var at = mathx.addV(g.hero.pos, mathx.scaleV(back, SUMMON_R));
    at = inBounds(g.env.resolveHeroSide(at, wolfmod.BODY_R, at.y));
    plantActor(g, &at);
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
    for (g.pack.liveConst(), 0..) |*w, i| was[i] = w.wasAt;
    gateTerrain(g, g.pack.live(), was[0..g.pack.n], null, true);
    for (g.pack.live()) |*w| {
        if (w.bit) sfx.world(.wolf_bite, w.pos);
        if (w.growled) sfx.world(.wolf_growl, w.pos);
        w.jaw1 = w.jawPoint();
        const b = w.blade();
        if (b.active and !w.hitLatch and pierceFoes(g, b)) {
            w.hitLatch = true;
            sfx.play(.hit_light);
        }
    }
}

fn quarryKey(kind: FoeKind, idx: usize) u32 {
    return (@as(u32, @intFromEnum(kind)) << 16) | @as(u32, @intCast(@min(idx, 0xFFFF)));
}

fn aimOf(f: anytype) f32 {
    return f.centerWorld().y - f.pos.y;
}

fn huntFor(g: *const Game, w: *const wolfmod.Wolf) ?wolfmod.Quarry {
    const from = w.pos;
    if (mathx.distXZ(from, g.hero.pos) > wolfmod.RECALL_R) return null;
    const Ctx = struct {
        from: rl.Vector3,
        hero: rl.Vector3,
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
    if (bindingWorn(g.hero.worn)) |w| {
        const ring = g.hero.worn.at(w).?;
        _ = g.hero.wear(w, null);
        _ = g.bag.take(ring, 1);
        sfx.play(.ring_snap);
        g.trig.say("The Soul Binding Ring snaps.");
        return;
    }
    const had = g.hero.souls.dropAll();
    g.souls.spill(g.hero.pos, had);
    if (had > 0) sfx.play(.souls_spill);
}

fn bindingWorn(worn: heromod.Worn) ?item.Wear {
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        const w: item.Wear = @enumFromInt(f.value);
        if (worn.at(w)) |k| {
            if (item.bindsSouls(k)) return w;
        }
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
    g.hero.gold.gain(got.gold);
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

fn takePickup(g: *Game) void {
    const got = g.pickups.takeNear(&g.map) orelse return;
    awardLoot(g, got.loot, got.at);
    if (got.gold > 0) {
        g.hero.gold.gain(got.gold);
        g.award.gainCoin(got.gold);
        if (got.loot.len == 0) sfx.world(.item_get, got.at);
    }
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

fn hidePickups(g: *Game) void {
    for (g.pickups.mappedOnes(), 0..) |*p, i| g.env.setPickupDraw(i, p.sizeLeft(), p.spent());
}

/// These have no prop behind them, so the loop draws them off `env`'s own pickup model — and NOT AT ALL once
/// spent, rather than as a zero-sized glow. Off `drawCasters` entirely: a thing made of light lays no shadow.
fn drawDrops(g: *Game) void {
    const mdl = g.env.pickupModel();
    for (g.pickups.droppedOnes()) |*p| {
        if (p.spent()) continue;
        const left = p.sizeLeft();
        const s = p.scale * left;
        if (s <= 0.001) continue;
        const thin = left < 1.0;
        if (thin) g.scene.beginFade(left);
        rl.drawModelEx(mdl, p.pos, v3(0, 1, 0), p.yaw, v3(s, s, s), rl.Color.white);
        if (thin) g.scene.endFade();
    }
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
                if (!foemod.corporeal(f)) continue;
                self.alive[@intFromEnum(memberKind(f, kind))] += 1;
            }
        }
    };
    var ctx = Ctx{ .alive = &w.alive };
    eachTarget(g, &ctx, Ctx.visit);
    return w;
}

/// `justDied` is a one-frame edge, so this must run exactly once a frame (`tickTriggers`).
fn billDeaths(g: *Game) void {
    const Ctx = struct {
        g: *Game,
        fn visit(self: *const @This(), foes: anytype, kind: ?FoeKind) void {
            const T = @typeInfo(@TypeOf(foes)).pointer.child;
            if (comptime !@hasField(T, "justDied")) return;
            for (foes) |*f| {
                if (!f.justDied) continue;
                const k = memberKind(f, kind);
                self.g.trig.died(k);
                self.g.gorge.noteCorpse(f.pos);
                // **IT GOES ON THE GROUND WHERE IT FELL**, not into his hands. The roll is spent whatever died, so the stream cannot become a function of what you chose to fight.
                var buf: [pickupmod.DROP_MAX]item.Kind = undefined;
                const loot = dropsmod.roll(k, self.g.hero.sheet.at(.luck), &self.g.dropRng, &buf);
                // **AND SO DOES THE PURSE** (owner: gold should drop as an item, not auto-add like souls) — on
                // the SAME glow as the loot, so a body leaves one thing to walk over. Drawn from the same
                // stream in the same order as before, which is what the determinism rests on.
                self.g.pickups.spawn(f.pos, loot, dropsmod.rollGold(k, &self.g.dropRng));
                if (self.g.hero.perk.onKill > 0 and !self.g.hero.dead) {
                    _ = self.g.hero.vit.heal(self.g.hero.perk.onKill);
                }
            }
        }
    };
    var ctx = Ctx{ .g = g };
    eachTarget(g, &ctx, Ctx.visit);
}

fn tickTriggers(g: *Game, dt: f32) void {
    g.nNpcPos = g.folk.positions(&g.map, &g.npcPos).len;
    billDeaths(g);
    const world = triggerWorld(g);
    markWards(g, world.alive, dt);
    const want = g.trig.tick(&g.map, world, dt, g.talk.active() or g.rest.active()) orelse return;
    if (!g.talk.open(&g.map, &g.trig, want, "", null)) g.trig.dialogClosed();
}

/// A gate may not shut on the man IN it (`wardClear`), or a push-out seals him inside with nothing left able to open it.
/// How long a spent gate takes to go.
const WARD_FADE: f32 = 2.6;

/// **THE ROOM ANSWERS THE SAME QUESTION THE DOOR DOES, OFF THE SAME TALLY, ON THE SAME FRAME.** Solved once
/// beside the gate's own seal rather than at the two chokepoints that read it, so a wall and the gate standing
/// in it can never disagree about whether the fight is over. **ANY NAME ON IT HOLDS IT**, which is the duo's rule.
fn solveArenaSeals(m: *const worldfmt.Map, alive: [@typeInfo(FoeKind).@"enum".fields.len]u32, shut: []bool) void {
    for (m.arenas[0..m.narenas], 0..) |*a, i| {
        if (i >= shut.len) return;
        shut[i] = worldfmt.sealStanding(a.seal(), &alive);
    }
}

fn markWards(g: *Game, alive: [@typeInfo(FoeKind).@"enum".fields.len]u32, dt: f32) void {
    solveArenaSeals(&g.map, alive, &g.arenaShut);
    for (0..g.env.nwards) |i| {
        const pr = &g.env.props[g.env.wardProps[i]];
        const seal = if (pr.op < g.map.nops) g.map.ops[pr.op].seal() else &.{};
        // **ANY NAME ON THE GATE HOLDS IT** (`worldfmt.sealStanding`, the room's own question too). A duo is
        // two, and a door that let go with half the fight standing let you walk out of an arena you were sealed into.
        const standing = worldfmt.sealStanding(seal, &alive);
        const shut = g.env.wardIn[i] and standing and g.env.wardClear(@intCast(i), g.hero.pos, HERO_R);
        if (shut and !g.env.wardShut[i]) sfx.play(.fog_seal);
        g.env.wardShut[i] = shut;
        if (g.env.wardIn[i] and seal.len > 0 and !standing) {
            // One shot off the first frame of the door letting go — past it `wardLife` is already under 1, so the edge cannot come round twice.
            if (g.env.wardLife[i] >= 1.0) sfx.play(.fog_felled);
            g.env.wardLife[i] = mathx.maxF(0, g.env.wardLife[i] - dt / WARD_FADE);
        }
        pr.shrink = g.env.wardLife[i];
        pr.gone = g.env.wardLife[i] <= 0;
    }
}

/// Taken off the step he actually travelled — the same segment question `gateTerrain` asks on a foe's behalf.
fn markWardStep(g: *Game, was: rl.Vector3) void {
    const w = g.env.wardCrossed(was, g.hero.pos) orelse return;
    g.env.wardIn[w] = true;
}

fn startTalk(g: *Game) bool {
    if (g.talk.active()) return false;
    const i = g.folk.near orelse return false;
    const p = g.folk.at(i) orelse return false;
    if (p.rec >= g.map.nnpcs) return false;
    const dlg = g.map.npcs[p.rec].dlg;
    if (dlg == worldfmt.NO_DIALOG) return false;
    if (!g.talk.open(&g.map, &g.trig, dlg, npcmod.nameOf(&g.map, p.rec), i)) return false;
    p.talking = true;
    return true;
}

fn talkable(g: *const Game) bool {
    const i = g.folk.near orelse return false;
    const p = g.folk.atConst(i) orelse return false;
    if (!atHisLevel(g, p.pos.y)) return false;
    return p.rec < g.map.nnpcs and g.map.npcs[p.rec].dlg != worldfmt.NO_DIALOG;
}

fn tickTalk(g: *Game, dt: f32) void {
    const in = dialogmod.Input{
        .up = navPressed(.up),
        .down = navPressed(.down),
        .confirm = talkConfirmPressed(),
        .pick = digitPressed(),
    };
    g.talk.update(&g.map, &g.trig, triggerWorld(g), dt, in);
    // **A COUNTER ASKED FOR INSIDE A CONVERSATION OPENS FROM INSIDE IT.** The main loop's own drain sits past
    // the `g.talk.active()` branch's `continue`, so a `gets: shop` on a choice set `wantCounter` and nothing
    // read it — the stall opened whenever the talk happened to end, which could be several lines later.
    // `run` already orders the counter branch AHEAD of the talk branch for exactly this case.
    if (g.trig.takeCounter()) |k| openCounter(g, k);
    if (g.talk.justClosed) {
        if (g.talk.npc) |i| {
            if (g.folk.at(i)) |p| p.farewell();
        }
        g.folk.hush();
    }
    g.hero.pose();
    g.folk.update(dt, g.hero.pos, PLAY_HALF);
    voiceFolk(g);
    g.rig.tickShake(dt);
    g.rumble.update(dt, false);
}

/// **THE BODY SAYS WHEN AND THIS SAYS IT** — the same split every creature's voice is on, so an anvil cannot
/// ring through the pause card or into the shot harness. Called from BOTH folk steps the live game has: a
/// conversation branch `continue`s the frame, and the smith across the field is still visibly hammering in it.
fn voiceFolk(g: *Game) void {
    for (g.folk.live()) |*p| {
        if (!p.struck) continue;
        // **A CLIFF MAKES THE ANVIL A HINT** (owner). The ring carries across open ground and comes through
        // rock as a dull knock, so a forge is something you hear before you find. Asked off HIS ears and not
        // the lens: the listener is the camera, which can be the far side of a wall from the body doing the
        // exploring, and what this decides is what the PLAYER has learnt.
        const ear = v3(g.hero.pos.x, g.hero.pos.y + foemod.HERO_EYE, g.hero.pos.z);
        const anvil = v3(p.pos.x, p.pos.y + ANVIL_EAR, p.pos.z);
        sfx.worldThrough(.smith_ring, p.pos, 1.0, if (g.env.sees(ear, anvil)) 1.0 else 0.0);
    }
}

/// Where the ring comes from: the anvil's own face, not his crown. A line drawn from the top of a 3.24 m body
/// clears low walls the sound itself would not. Off the PROP rather than spelled here, so re-solving the anvil
/// against his stroke — which already moved it once, 0.88 to 0.98 — carries the sound with it.
const ANVIL_EAR: f32 = propsmod.info(.anvil).top;

test "A CLIFF TURNS THE ANVIL INTO A HINT — the ring carries in the open and is muffled through rock" {
    const m = try worldfmt.testMap(std.testing.allocator, worldfmt.TEST_HEAD ++ "at: cliff 18 0 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);

    // Ear height to the anvil's face, the same two points `voiceFolk` asks about.
    const ear = v3(0, foemod.HERO_EYE, 0);
    // The cliff's own capsule is 10.8 m long with a 2.9 m girth, so "the same side of it" has to be well
    // clear of the rock itself — measured off `props.cliffParts`, not guessed at.
    const behindTheCliff = v3(34, ANVIL_EAR, 0);
    const sameSide = v3(3, ANVIL_EAR, 0);
    try std.testing.expect(!e.sees(ear, behindTheCliff));
    try std.testing.expect(e.sees(ear, sameSide));
    // …and the muffle is a CUT AND A DROOP, small enough to stay placeable and deep enough to stop being the
    // same sound. A gain that only halved would read as further off rather than as through something.
    try std.testing.expect(sfx.MUFFLE_GAIN < 0.5 and sfx.MUFFLE_GAIN > 0.15);
    try std.testing.expect(sfx.MUFFLE_DROOP > 0 and sfx.MUFFLE_DROOP < 0.15);
    std.debug.print("\n  anvil through rock: {d:.0}% of its open level, pitched down {d:.0}% — a hint, not a location\n", .{
        100.0 * sfx.MUFFLE_GAIN, 100.0 * sfx.MUFFLE_DROOP,
    });
}

fn openCounter(g: *Game, k: worldfmt.ActKind) void {
    const trade: countermod.Trade = switch (k) {
        .shop => .shop,
        .smithy => .smithy,
        else => return,
    };
    // A counter may not open over a crossing, a climb or a death — every other door here refuses the same way.
    if (g.hero.dead or g.gateWalk != null or g.climb != null) return;
    g.counter.begin(trade);
    g.counterT = 0;
    g.hero.held = true;
    sfx.play(.flask_cycle);
}

/// **THE STICK AND FOUR BUTTONS, AND NOTHING ELSE TICKS.** The world is held (`hero.held`) exactly as a
/// conversation holds it, so nothing walks, swings or bleeds while he is haggling.
fn tickCounter(g: *Game, dt: f32) void {
    g.counterT += dt;
    var rowBuf: [countermod.MAX_ROWS]countermod.Row = undefined;
    const len = g.counter.rows(&g.hero, &g.bag, &rowBuf).len;
    if (navPressed(.up)) g.counter.move(-1, len);
    if (navPressed(.down)) g.counter.move(1, len);
    if (confirmPressed()) g.counter.take(&g.hero, &g.bag);
    // The QUICK button flips a shop between its two lists; a smithy has only the one.
    if (g.counter.trade == .shop and (rl.isKeyPressed(.q) or padPressed(hud_.padOf(hud_.BTN_QUICK)))) {
        g.counter.selling = !g.counter.selling;
        g.counter.sel = 0;
        g.counter.said = .none;
    }
    if (rl.isKeyPressed(.escape) or padPressed(hud_.padOf(hud_.BTN_BACK))) {
        g.counter.close();
        g.hero.held = false;
    }
    g.hero.pose();
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
        g.restRetro = g.retro.values;
        g.retro.values[gfx.RF_SEPIA] = mathx.maxF(g.retro.values[gfx.RF_SEPIA], REST_WARMTH);
        const s = g.rest.seat();
        var at = s.pos;
        plantActor(g, &at);
        g.hero.sit(true, at, s.facing);
        // **THE FIRE HE SAT AT IS WHERE HE COMES BACK.** Stamped at the seat, which is where standing up puts
        // him anyway, and the save below carries it — so a death after a reload still returns to this fire and
        // not to the spot the map was entered at.
        g.hero.setSpawn(at, s.facing);
        saveNow(g, .withShot);
    }
    if (g.rest.justLeft) {
        g.retro.values = g.restRetro;
        g.hero.sit(false, g.hero.pos, g.hero.facing);
        rehomeFoes(g, .blind);
        dropRunHud(g);
        saveNow(g, .noShot);
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
    const v = restView(g);
    if (g.rest.screen == .spells) {
        if (nav(.up)) restmod.navigateSpells(&g.rest, -1, v);
        if (nav(.down)) restmod.navigateSpells(&g.rest, 1, v);
        if (menumod.stickPush(dt, false)) |d| restmod.navigateSpells(&g.rest, d.y, v);
    } else {
        if (nav(.up)) restmod.navigate(&g.rest, 0, -1);
        if (nav(.down)) restmod.navigate(&g.rest, 0, 1);
        if (nav(.left)) restmod.navigate(&g.rest, -1, 0);
        if (nav(.right)) restmod.navigate(&g.rest, 1, 0);
        if (menumod.stickPush(dt, onWheel)) |d| restmod.navigate(&g.rest, d.x, d.y);
    }
    restmod.pan(&g.rest, menumod.stickPan(), dt);
    restmod.zoom(&g.rest, menumod.dpadZoom(), dt);
    if (menumod.confirmPressed()) bonfirePick(g, restmod.confirm(&g.rest, v));
    if (menumod.backPressed() or rl.isKeyPressed(.escape)) restmod.back(&g.rest);
}

pub fn restView(g: *Game) restmod.View {
    return .{ .tree = &g.tree, .souls = g.hero.souls.total, .mem = &g.hero.mem, .bag = &g.bag };
}

fn bonfirePick(g: *Game, pick: restmod.Pick) void {
    switch (pick) {
        .none => {},
        .leave => g.rest.leave(),
        .take => |i| {
            const paid = g.tree.take(i, g.hero.souls.total) orelse return;
            g.hero.souls.total -= paid;
            g.hero.souls.shown = @floatFromInt(g.hero.souls.total);
            applyTree(g);
            sfx.play(.souls_take);
        },
        .wait => |u| {
            g.day.set(g.day.hour + daynight.hoursUntil(g.day.hour, u.hour()));
            applyHour(g);
            sfx.play(.menu_pick);
            g.rest.leave();
        },
        .memorize => |m| g.hero.memorize(m.slot, m.spell),
    }
    if (std.meta.activeTag(pick) != .none and g.rest.listening()) saveNow(g, .noShot);
}

const SaveShot = enum { withShot, noShot };

fn saveNow(g: *Game, shot: SaveShot) void {
    snapBosses(g);
    if (!savemod.write(g.slot, slotOf(g))) {
        std.debug.print("SAVE FAILED: could not write {s}\n", .{savemod.path(g.slot)});
        return;
    }
    g.shelf = savemod.survey(saveMap(g));
    if (shot == .withShot) g.shotOwed = true;
    g.saveT = hud_.SAVE_SHOW;
}

fn saveMark(g: *Game, dt: f32) void {
    if (g.saveT <= 0) return;
    g.saveT = mathx.maxF(0, g.saveT - dt);
    hud_.saveTree(g.saveT);
}

fn applyStow(g: *Game) void {
    g.env.stowed = g.hero.resting;
}

fn applyHour(g: *Game) void {
    // **ONLY WHEN SOMETHING HAS ACTUALLY MOVED**: two `paletteAt` walks, three `keyDir`-class solves and
    // EIGHTEEN `setShaderValue` calls, each a `glUseProgram` plus a `glUniform`. The guard is the VALUE, not a
    // flag, and nothing else writes these uniforms. **THE WEATHER TERMS ARE QUANTIZED TO A SIXTY-FOURTH AND THE
    // HOUR IS NOT**, so on a running clock this reloads every frame and only a HELD clock (`--shot`, the pause,
    // the editor) is spared. Deliberate: a `@round` on the hour is a step in the sun's own bearing, and light
    // here is never stepped. The cost is 18 uniform uploads a frame on a path already drawing hundreds.
    const wet = @round(g.wetNow * WET_STEPS) / WET_STEPS;
    const fog = hazeK(g);
    const spore = @round(g.sporeNow * WET_STEPS) / WET_STEPS;
    if (g.day.hour == g.hourLit and wet == g.wetLit and fog == g.fogLit and spore == g.sporeLit) return;
    g.hourLit = g.day.hour;
    g.wetLit = wet;
    g.fogLit = fog;
    g.sporeLit = spore;
    g.scene.setHour(g.day.hour, wet, fog, spore);
    g.sky.setHour(g.day.hour, wet, spore);
    sfx.setDaylight(daynight.dayAmt(g.day.hour));
}

const WET_STEPS: f32 = 64.0;

pub fn bootCamForShot(g: *Game, t: f32) void {
    g.bootT = t;
    bootCam(g, t);
}

pub fn pinHourForShot(g: *Game, hour: f32) void {
    g.day.set(hour);
    g.day.freeze(true);
    applyHour(g);
}

/// **THE SKY THE MAN IS ACTUALLY STANDING IN, WITH NO BLEND** — `settleSky` walks toward a region's weather over `blend` seconds and the harness renders single frames.
pub fn pinSkyForShot(g: *Game) void {
    const here = g.map.weatherAt(g.hero.pos.x, g.hero.pos.z);
    g.wetNow = mathx.clampF(if (here) |l| l.wet orelse g.weather.rain() else g.weather.rain(), 0, 1);
    g.fogNow = mathx.clampF(if (here) |l| l.fog orelse 0 else 0, 0, 1);
    g.sporeNow = mathx.clampF(if (here) |l| l.spore orelse 0 else 0, 0, 1);
    if (g.sporeNow > weathermod.MIST_MIN) {
        g.mist.tick(SHOT_SETTLE, g.hero.pos, g.env.groundAt(g.hero.pos.x, g.hero.pos.z), fogAmt(g));
    }
    applyHour(g);
}

/// One tick long enough to seed the mist field and get it past its own fade-in ramp.
const SHOT_SETTLE: f32 = 1.0 / 60.0;

const REST_WARMTH: f32 = 0.14;
const REST_PAN: f32 = 0.70;

fn restCamera(g: *Game) void {
    const s = g.rest.seat();
    const axis = mathx.headingDir(s.axis);
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
        .babble, .bidding => whisperAt(g),
    }
}

/// **THE TWO DOSERS SHARE ONE CAST** — they differ only in the `SPELLS` row, and the delivery is the sunder's
/// (`strikeOne`, so a body's own `tryHit` bills it). No damage, poise or stance lands, so the burst at its feet
/// and the meter on its bar are the whole tell, and a MISS has to say so too.
fn whisperAt(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const reach = combat.spellReach(g.hero.spell) orelse return;
    sfx.play(.wand_cast);
    g.rumble.play(rumblemod.cast_throw);
    g.rig.addShake(SHAKE_CAST);
    const tint = whisperTint(g.hero.spell);
    const pick = strikeVictim(g, reach) orelse {
        g.hero.dustPuff(strikeMissAt(g, reach), WHISPER_R, tint, g.hero.casts);
        return;
    };
    const hit = strikeOne(g, pick, blow) orelse return;
    g.hero.dustPuff(v3(hit.at.x, g.env.groundAt(hit.at.x, hit.at.z), hit.at.z), WHISPER_R, tint, g.hero.casts);
    sfx.play(.hollow_toll);
}

/// Tight — this lands ON a body, where the powder's ring lands on a crowd.
const WHISPER_R: f32 = 1.1;

/// The burst has to agree with the meter it fills, so it reads the spell's OWN dose (`combat.spellDose`)
/// rather than a second copy of the pairing — spelled out here, a third doser silently got confusion's green.
fn whisperTint(s: combat.Spell) rl.Color {
    return hud_.ailTint(combat.spellDose(s) orelse .confusion);
}

fn throwLance(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const reach = combat.spellReach(g.hero.spell) orelse return;
    const from = g.hero.wandTipWorld();
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
        .through = true,
        .r = combat.LANCE_R,
        .a = from,
        .b = to,
        .a0 = from,
        .b0 = to,
        .hit = blow,
    });
    g.hero.lanceBeam(from, to, g.hero.casts);
}

/// **SUNDER — the levin's exact plumbing at a quarter of its reach.** Delivered through the creature's own `tryHit` (`strikeOne`), so a shield that would stop it stops it.
fn strikeSunder(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const reach = combat.spellReach(g.hero.spell) orelse return;
    sfx.play(.wand_cast);
    const pick = strikeVictim(g, reach) orelse {
        g.hero.sunderBurst(strikeMissAt(g, reach), false, g.hero.casts);
        g.rumble.play(rumblemod.cast_throw);
        g.rig.addShake(SHAKE_CAST);
        return;
    };
    const hit = strikeOne(g, pick, blow) orelse return;
    g.hero.sunderBurst(v3(hit.at.x, g.env.groundAt(hit.at.x, hit.at.z), hit.at.z), true, g.hero.casts);
    g.rumble.play(rumblemod.hit_heavy);
    g.rig.addShake(SHAKE_ROOTS_BITE);
}

fn throwBolt(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const locked: ?rl.Vector3 = if (activeLock(g)) |li| foeLockPoint(g, li) else null;
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

comptime {
    std.debug.assert(dropsmod.MAX_PER_BODY == pickupmod.DROP_MAX);
}

const RootPick = struct { group: usize, idx: usize };
fn rootVictim(g: *const Game, at: rl.Vector3) ?RootPick {
    const locked = activeLock(g);
    var pick: ?RootPick = null;
    var near: f32 = combat.ROOT_R;
    inline for (FOE_GROUPS, 0..) |f, gi| {
        for (@field(g, f.field).liveConst(), 0..) |*a, i| {
            if (!foemod.corporeal(a)) continue;
            // A BODY THAT IS NOT ON THE FIELD IS NOT A TARGET: a burrowed delver, a sunk lurker and a dormant snag were all grippable through the ground.
            if (disguised(a)) continue;
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
    const dose = g.hero.breathDose(dt);
    inline for (FOE_GROUPS) |f| {
        for (@field(g, f.field).live()) |*a| {
            if (!foemod.corporeal(a)) continue;
            if (disguised(a)) continue; // `rootVictim`'s rule: the cone is poured over the field, not under it
            const d = mathx.distXZ(a.pos, apex);
            const r = a.bodyR();
            if (d - r > combat.RIME_REACH) continue;
            const to = mathx.dirXZ(apex, a.pos);
            if (mathx.lenXZ(to) > 1e-4) {
                const spread = if (d > r) combat.subtendedArc(r, d) else 180.0;
                if (!combat.withinArc(mathx.headingXZ(to), facing, combat.RIME_ARC + spread)) continue;
            }
            a.chill.breathe(dose);
            a.leash.provoke();
        }
    }
}

// THE TWO SORCERIES THAT DO NOT CROSS THE GROUND (`combat.LEVIN_*`, `combat.SIPHON_*`). They land on ONE body
// on the frame they are cast, so SIGHT stands in for a flight to intercept (`env.sees`).

/// The LEAN is not decoration: `foe.strike` takes the shove and the facing snap off the segment's own XZ
/// bearing and a plumb line has none. MEASURED: at 2.6 m above a skeleton's crown the stroke started at 4.5 m, off the top of frame.
const STRIKE_RISE: f32 = 1.7;
const STRIKE_LEAN: f32 = 0.9;
/// Only as fat as it has to be to be certain of a body already picked — it cannot miss and may not reach a neighbour.
const STRIKE_R: f32 = 0.30;

fn strikeSegment(g: *const Game, at: rl.Vector3, topY: f32) [2]rl.Vector3 {
    var away = mathx.dirXZ(g.hero.pos, at);
    if (mathx.lenXZ(away) < 1e-4) away = mathx.headingDir(g.hero.facing);
    return .{ v3(at.x - away.x * STRIKE_LEAN, topY + STRIKE_RISE, at.z - away.z * STRIKE_LEAN), at };
}

/// The locked body, else the NEAREST inside the spell's reach and a narrow arc of his facing (`combat.STRIKE_ARC`).
/// Reach is measured off the target's HIDE, not its centre. A lock is the aim, so it skips the arc — never the reach and never the sight.
fn strikeVictim(g: *const Game, reach: f32) ?RootPick {
    const eye = heroEye(g);
    const locked = activeLock(g);
    var pick: ?RootPick = null;
    var near: f32 = reach;
    inline for (FOE_GROUPS, 0..) |f, gi| {
        for (@field(g, f.field).liveConst(), 0..) |*a, i| {
            if (!foemod.corporeal(a)) continue;
            if (disguised(a)) continue;
            const d = mathx.distXZ(a.pos, g.hero.pos) - a.bodyR();
            if (d > reach) continue;
            if (!g.env.sees(eye, a.lockPoint())) continue;
            if (locked) |l| {
                if (l.idx == i and l.kind == memberKind(a, f.kind)) return .{ .group = gi, .idx = i };
                continue;
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

const Struck = struct { at: rl.Vector3, from: rl.Vector3, took: f32 };

fn strikeOne(g: *Game, pick: RootPick, blow: combat.Hit) ?Struck {
    var out: ?Struck = null;
    inline for (FOE_GROUPS, 0..) |f, gi| {
        if (gi == pick.group) {
            const a = &@field(g, f.field).live()[pick.idx];
            const seg = strikeSegment(g, a.centerWorld(), a.topWorld().y);
            const before = a.vit.hp;
            a.tryHit(.{
                .active = true,
                .pierce = true,
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

fn strikeMissAt(g: *const Game, reach: f32) rl.Vector3 {
    const d = mathx.headingDir(g.hero.facing);
    const x = g.hero.pos.x + d.x * reach * 0.5;
    const z = g.hero.pos.z + d.z * reach * 0.5;
    return v3(x, g.env.groundAt(x, z), z);
}

fn strikeLevin(g: *Game) void {
    const blow = g.hero.castBlow() orelse return;
    const reach = combat.spellReach(g.hero.spell) orelse return;
    sfx.play(.wand_cast);
    const pick = strikeVictim(g, reach) orelse {
        const on = strikeMissAt(g, reach);
        const seg = strikeSegment(g, on, on.y);
        g.hero.levinStroke(seg[0], seg[1], on.y, g.hero.casts);
        g.rumble.play(rumblemod.cast_throw);
        g.rig.addShake(SHAKE_CAST);
        return;
    };
    const hit = strikeOne(g, pick, blow) orelse return;
    g.hero.levinStroke(hit.from, hit.at, g.env.groundAt(hit.at.x, hit.at.z), g.hero.casts);
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
        const on = strikeMissAt(g, reach);
        g.hero.siphonDrain(foemod.heroChest(on), g.hero.casts);
        return;
    };
    const hit = strikeOne(g, pick, blow) orelse return;
    // **A SHARE OF WHAT THE BODY ACTUALLY LOST**, never of what was thrown at it: resisted damage is resisted healing. Capped by what it took, so an overkill cannot be milked.
    g.hero.siphonDrain(hit.at, g.hero.casts);
    _ = g.hero.drinkSiphon(hit.took * combat.SIPHON_SHARE);
}

fn gateChill(foes: anytype, was: []const rl.Vector3) void {
    const T = @typeInfo(@TypeOf(foes)).pointer.child;
    if (comptime !@hasField(T, "chill")) return;
    for (foes, 0..) |*f, i| {
        // THE CLOCK IS NOT RUN HERE. `foe.grip` ticks it at the top of the creature's own update, where the bite it owes can KILL; run again here it would decay at twice the rate.
        if (i >= was.len or !f.chill.held()) continue;
        f.pos.x = was[i].x + (f.pos.x - was[i].x) * combat.CHILL_TRAVEL;
        f.pos.z = was[i].z + (f.pos.z - was[i].z) * combat.CHILL_TRAVEL;
    }
}

pub fn castRootsForShot(g: *Game) rl.Vector3 {
    const at = rootMark(g);
    return seedRoots(g, at) orelse at;
}

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
        reach = mathx.minF(reach, mathx.lenV(mathx.subV(hitPoint, ray.origin)));
    }
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
            if (!foemod.corporeal(f)) continue;
            const oc = mathx.subV(f.centerWorld(), self.origin);
            const along = oc.x * self.dir.x + oc.y * self.dir.y + oc.z * self.dir.z;
            if (along <= 0) continue;
            const r = f.hurtRadius();
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

const SIGHT_R: f32 = blk: {
    var widest: f32 = 0;
    for (FOE_GROUPS) |f| widest = @max(widest, f.aggro);
    break :blk widest + 1.0;
};

fn heroEye(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, g.hero.pos.y + foemod.HERO_EYE, g.hero.pos.z);
}

/// **THE RAY IS CAST AT THE CREATURE'S OWN MARK**, so a mark that does not ride the body is a body no wall can
/// hide from — a fog gate stopped blocking the duo's aggro because theirs sat off in open ground. Pinned by
/// "THE MARK RIDES THE BODY".
fn markSight(g: *Game) void {
    const eye = heroEye(g);
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            if (!foemod.corporeal(f)) continue;
            if (mathx.distXZ(g.hero.pos, f.pos) > SIGHT_R) continue;
            if (g.env.sees(f.lockPoint(), eye)) f.leash.noteSeen();
        }
    }
}

const WAY_PROBE: f32 = 2.0;
const WAY_FAN = [_]f32{ 0.45, 0.90, 1.40, 1.95, 2.50 };
const WAY_TRUE: f32 = 0.98;
/// Metres of overlap forgiven: blocked iff the gap closes past `r + s.r - WAY_SLACK`, asked without solving for where the body would end up.
const WAY_SLACK: f32 = 1e-3;

/// **A PROBE ASKS WHETHER A POINT IS BLOCKED, SO IT ASKS THAT** (`env.blockedNear`). `resolveActor` is a SOLVER
/// and on an overlapping point runs its whole second settling pass, so every blocked probe cost two full visits
/// of every nearby solid for one bit — and `markWay` tries ten headings at two probes each.
fn wayClear(g: *const Game, at: rl.Vector3, r: f32, dir: rl.Vector3) bool {
    const reach = WAY_PROBE + r;
    const went = mathx.dirXZ(at, g.env.walkStep(at, dir, reach));
    if (mathx.lenXZ(went) < 1e-4) return false;
    if (went.x * dir.x + went.z * dir.z < WAY_TRUE) return false;
    for ([2]f32{ 0.5, 1.0 }) |u| {
        const p = v3(at.x + dir.x * reach * u, at.y, at.z + dir.z * reach * u);
        if (g.env.blockedNear(p, r - WAY_SLACK, r + 1.0)) return false;
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
    for (WAY_FAN) |off| {
        for ([2]f32{ nav.side, -nav.side }) |s| {
            const d = mathx.headingDir(yaw + off * s);
            if (!wayClear(g, at, r, d)) continue;
            nav.dir = d;
            nav.side = s;
            return;
        }
    }
    nav.dir = null;
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
            // STAMPED, not looked up: `foe.Threat` cannot see a `Vitals` and must not.
            f.threat.charmed = f.vit.ailOn(.charm);
            f.threat.confused = f.vit.ailOn(.confusion);
            if (f.threat.charmed or f.threat.confused) {
                if (nearestOther(g, f.pos, TURN_R)) |o| {
                    f.threat.atFoe = o.at;
                    f.threat.distFoe = o.dist;
                    f.threat.hasFoe = true;
                } else {
                    // **NOTHING TO TURN ON, SO IT TURNS ON NOTHING.** Its own feet: `Threat.aim` hands the
                    // creature a point it is already standing on, so it stops closing on the hero, and the
                    // swing it takes there is dropped for being aimed at itself.
                    f.threat.atFoe = f.pos;
                    f.threat.distFoe = 0;
                    f.threat.hasFoe = false;
                }
            } else {
                f.threat.hasFoe = false;
            }
            f.threat.tick(
                dt,
                mathx.distXZ(f.pos, g.hero.pos),
                if (mine) |s| mathx.distXZ(f.pos, s) else mathx.LONG_AGO,
                mine != null,
            );
        }
    }
}

/// **HOW FAR A TURNED BODY WILL GO LOOKING**, past which it stands. A charmed body crossing the field spends its
/// whole clock walking, which reads as the charm having done nothing.
const TURN_R: f32 = 22.0;

const Nearest = struct { at: rl.Vector3, dist: f32 };

/// The nearest live body that is NOT the one asking. **IDENTITY IS BY POSITION, EXACT AND NOT NEAR**: `from` is
/// the caller's own `pos` verbatim, and `collideActors` is what stops two bodies sharing coordinates.
fn nearestOther(g: *const Game, from: rl.Vector3, r: f32) ?Nearest {
    var best: ?Nearest = null;
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).liveConst()) |*o| {
            if (!foemod.corporeal(o)) continue;
            if (o.pos.x == from.x and o.pos.z == from.z) continue;
            const d = mathx.distXZ(from, o.pos);
            if (d > r) continue;
            if (best == null or d < best.?.dist) best = .{ .at = o.lockPoint(), .dist = d };
        }
    }
    return best;
}

/// **DRAINED AFTER EVERY GROUP HAS UPDATED, NEVER DURING** — a turned swing has to reach a group not yet stepped.
/// Delivered as a PIERCING blade on the body aimed at: `tryHit` is every creature's own door (so the flash, the
/// stagger, the death and the drop are the blow's own), and `pierce` is the one mode that leaves `hitLatch` — the
/// HERO's sword's — alone.
fn spendTurnedBlows(g: *Game) void {
    const blows = foemod.takeTurned();
    defer foemod.clearTurned();
    for (blows) |b| {
        const at = b.at;
        // **A SWING AIMED AT ITS OWN FEET LANDS ON NOBODY.** That is what a charmed body with no neighbour does
        // (`markThreat`), and billed it would open its own throat on a blade centred on itself.
        if (mathx.dist2XZ(at, b.from) < TURNED_SELF * TURNED_SELF) continue;
        if (pierceFoes(g, .{
            .active = true,
            .pierce = true,
            .r = TURNED_R,
            .a = at,
            .b = at,
            .a0 = at,
            .b0 = at,
            .hit = b.hit,
            .by = .foe,
        })) {
            sfx.playAt(.hit_light, 0.7);
        }
    }
}

/// Tight on the body it was aimed at, so a turned swing cannot sweep up a third party standing behind it.
const TURNED_R: f32 = 0.45;
/// Inside this of its own feet, a turned swing was aimed at nothing. Under `TURNED_R`, so a blow that would have
/// hit the striker is dropped before the blade is ever built.
const TURNED_SELF: f32 = 0.30;

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

/// Stamped onto every priest (`ancientpriest.flock`). The creature reads the field and never reaches into another group's array — the `Leash` law.
fn markFlock(g: *Game) void {
    // O(priests x skitterers) and both are usually zero: two loads beat the walk.
    if (g.crypt.n == 0) return;
    for (g.crypt.live()) |*p| {
        var n: u32 = 0;
        for (g.clatter.liveConst()) |*sk| {
            if (!foemod.corporeal(sk)) continue;
            if (mathx.distXZ(sk.pos, p.pos) > priestmod.RAISE_KEEP_R) continue;
            n += 1;
        }
        p.flock = n;
    }
}

/// **EVERY BODY WITHIN EARSHOT OF A STRUCK BELL COMES** (`hollow.TOLL_R`). One pass over every group.
fn rouseAll(g: *Game, at: rl.Vector3, r: f32) void {
    inline for (FOE_GROUPS) |gr| _ = foemod.rouseWithin(@field(g, gr.field).live(), at, r);
}

fn markParry(g: *Game) void {
    const p = foemod.Parry{ .live = g.hero.parryLive(), .at = g.hero.pos, .facing = g.hero.facing, .arc = g.hero.guardArc() };
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "setParry")) @field(g, f.field).setParry(p);
    }
}

fn anyParried(g: *const Game) bool {
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "anyParried")) {
            if (@field(g, f.field).anyParried()) return true;
        }
    }
    return false;
}

fn parryBeat(g: *Game) void {
    g.hero.noteParry();
    g.rumble.play(rumblemod.parry);
    g.rig.addShake(SHAKE_PARRY);
    sfx.play(.parry);
}

fn markVigil(g: *Game) void {
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
    // The group test is a runtime `if` WRAPPING the body rather than a `continue`: `gi` is comptime and
    // `ref.group` is not, so skipping an `inline for` iteration on it is comptime control flow inside a runtime block, which Zig refuses.
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
        // `through` is what carries the blade past a body it already found. A WRAPPING `if` rather than a `continue`, for `withRaisable`'s reason.
        if (!hit or blade.through) {
            if (@field(g, f.field).pierce(blade)) hit = true;
        }
    }
    return hit;
}

const ARROW_QUERY_PAD: f32 = 1.5;
var arrow_cover_buf: [envmod.MAX_NEAR]collision.Solid = undefined;
/// **A PLANTED SHAFT ASKS THE GRID FOR NOTHING.** `archer.flying` early-returns on `stuck` and the argument is
/// evaluated first, so a landed shot bought a cell sweep and up to `env.MAX_NEAR` `Solid` copies every frame of the 1.4 s it lies there.
pub fn arrowCover(g: *const Game, ar: *const archermod.Arrow, dt: f32) []const collision.Solid {
    if (ar.stuck) return &.{};
    return g.env.nearSolids(ar.pos, mathx.lenV(ar.vel) * dt + ARROW_QUERY_PAD, &arrow_cover_buf);
}

fn quivers(g: *Game) [2][]archermod.Arrow {
    return .{ &g.arrows, &g.shafts };
}

/// **THE LANDING FRAME, NOT THE `ARROW_STICK_FADE` IT LIES THERE.** A planted shot stays `live` for 1.4 s with
/// `stepArrow` early-returning, so unguarded `splashOf` re-detonated at 60 Hz and `emberBlast` billed its whole `EMBER_HIT` once a frame.
fn justLanded(ar: *const archermod.Arrow) bool {
    return ar.stuck and ar.age == 0;
}

fn planted(g: *Game, ar: *const archermod.Arrow) void {
    if (!justLanded(ar)) return;
    if (ar.shot != .venom) sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
    splashOf(g, ar);
}

fn splashOf(g: *Game, ar: *const archermod.Arrow) void {
    const ground = v3(ar.pos.x, g.env.groundAt(ar.pos.x, ar.pos.z), ar.pos.z);
    switch (ar.shot) {
        .venom => g.brood.splash(ground),
        .clump => g.band.splash(ar.pos),
        .bolt => {
            g.hero.boltBurst(ar.pos, ground.y, g.hero.casts);
            if (g.hero.perk.boltCloud) layBoltGas(g, ground);
        },
        .emberball => {
            sfx.world(.ember_burst, ar.pos);
            g.ring.splash(ar.pos);
        },
        // ONE CLOUD POOL AND ONE POISON METER: the golem's sac lays the SPORELING'S cloud, so there is no second
        // soak to keep in step. And the burst is `shroom_puff`, NOT `shroom_fling` — the fling is the LAUNCH,
        // already played where the sac leaves the cap.
        .sac => {
            sfx.world(.shroom_puff, ar.pos);
            g.cluster.spawnCloud(ground);
        },
        // **THE TWIST BURSTS WHERE IT LANDS AND BILLS NOTHING** — the ring is the whole weapon.
        .powder => powderBurst(g, ground),
        .arrow, .firearrow, .wisp, .crock, .spark => {},
    }
}

/// `brood.M_SPIT_BUILD` was authored, tested and wired to NOTHING: a glob that hit you did 2 damage and no
/// venom, while the puddle it missed you with poisoned at 40/s. Only on a blow that landed, and off the `Shot`
/// rather than the creature, so a second poisoning missile says so here and nowhere else.
fn shotBuildup(s: archermod.Shot) f32 {
    return switch (s) {
        .venom => broodmod.M_SPIT_BUILD,
        .arrow, .firearrow, .clump, .crock, .bolt, .wisp, .emberball, .sac, .spark, .powder => 0,
    };
}

fn shotStatus(g: *Game, s: archermod.Shot, out: combat.HitOutcome) void {
    switch (out) {
        .blocked, .ignored => return,
        .taken, .guardBroken => {},
    }
    const amt = shotBuildup(s);
    if (amt > 0) g.hero.poisonBy(amt);
}

test "A GLOB THAT LANDS CARRIES ITS VENOM — the constant the meter is written in has a consumer" {
    // The bug this pins: `M_SPIT_BUILD` was declared, asserted against `POISON_MAX` by its own test, and read by NOTHING.
    try std.testing.expectEqual(broodmod.M_SPIT_BUILD, shotBuildup(.venom));
    try std.testing.expect(shotBuildup(.venom) * 3.0 >= combat.POISON_MAX);
    inline for (@typeInfo(archermod.Shot).@"enum".fields) |f| {
        const s: archermod.Shot = @enumFromInt(f.value);
        if (s != .venom) try std.testing.expectEqual(@as(f32, 0), shotBuildup(s));
    }
}

/// **A DETONATOR HAS NO DIRECT HIT — IT ONLY EVER EXPLODES.** At point blank `k` is 1.0, so catching one bills exactly what a direct hit already did.
fn detonates(s: archermod.Shot) bool {
    return s == .emberball;
}

/// Falls off to nothing at the rim rather than ending at a wall. A blast this size dropped from overhead is undodgeable, which is why the arc went flat (`archer.EMBER_LOFT`).
const BLAST_R: f32 = 3.1;
const BLAST_FLOOR: f32 = 0.30;

fn emberBlast(g: *Game, ar: *const archermod.Arrow) void {
    if (ar.shot != .emberball or g.hero.dead) return;
    const d = mathx.distXZ(ar.pos, g.hero.pos);
    if (d > BLAST_R) return;
    const k = mathx.lerpF(1.0, BLAST_FLOOR, mathx.clampF(d / BLAST_R, 0, 1));
    // THROUGH `Hit.scaled`, NOT THREE FIELDS BY HAND: written out it scaled `dmg`, `poise` and `elem` and left
    // `stance` and `fp` at full — a rim-of-the-blast guard-break at point-blank strength.
    const blow = foemod.Blow{ .hit = ar.blow.scaled(k), .from = ar.pos };
    _ = heroTakes(g, blow, false, false);
}

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
                .powder => &g.powderModel,
                .venom => &g.venomModel,
                .firearrow => &g.fireArrowModel,
                .bolt => &g.boltModel,
                .emberball => &g.emberModel,
                .sac => &g.sacModel,
                .wisp => &g.wispModel,
                .spark => &g.sparkModel,
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

/// **THE EDITOR SEES AS FAR AS IT IS PULLED BACK.** Play keeps its 320 m wall; zoomed out over a map 624 m a
/// side the wall is what would eat the far half of the screen, so it opens with the orbit distance.
fn drawFar(g: *const Game) f32 {
    if (!g.editor.on) return CLIP_FAR;
    return mathx.clampF(g.editor.dist * 2.0 + CLIP_FAR, CLIP_FAR, EDITOR_CLIP_FAR);
}

const EDITOR_CLIP_FAR: f32 = 2600.0;

/// How wide the shadow box opens. The editor's ground footprint is about 2.6 x the orbit distance at fovy 55
/// and a middling pitch, so the box tracks that and every caster on screen lands in the depth map — coarser
/// with every metre out, which is the trade the zoom asks for.
fn shadowSpanOf(g: *const Game) f32 {
    if (!g.editor.on) return gfx.SHADOW_ORTHO;
    return mathx.clampF(g.editor.dist * 2.6, gfx.SHADOW_ORTHO, gfx.SHADOW_SPAN_MAX);
}

fn sunFocus(g: *const Game) rl.Vector3 {
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
    if (g.hero.torchLight()) |t| {
        out[n] = t;
        n += 1;
    }
    n += g.rite.markLights(out[n..]);
    return out[0..n];
}

fn tickWeather(g: *Game, dt: f32) void {
    g.weather.tick(dt);
    settleSky(g, dt);
    sfx.setRain(g.wetNow);
    sfx.setTorch(if (g.hero.torchLit()) 1.0 else 0.0);
    // THE LIGHTNING STAYS THE WORLD'S: a location sets how wet it is, but the storm that throws bolts is the sky's own event.
    if (g.weather.thunder()) |gain| sfx.playAt(.thunder, gain);
    const under = g.env.groundAt(g.hero.pos.x, g.hero.pos.z);
    g.mist.tick(dt, g.hero.pos, under, fogAmt(g));
    // **THE BIRDS ARE THE DRY SKY'S** (owner: infrequently, just to feel alive) — the same wet level the
    // sheet reads, so a region that is raining on him has nothing flying over it either.
    // …and the debug row sends one ACROSS his view rather than at him, since what he is checking is whether a
    // flock crossing the sky reads at all.
    if (g.menu.takeBirds()) g.skein.stageOne(g.hero.pos, under, g.hero.facing + std.math.pi * 0.5);
    g.skein.tick(dt, g.hero.pos, under, g.wetNow);
}

/// **A REGION'S WEATHER IS A CROSS-FADE, NEVER A SWITCH** — one sky, one sun, one rain sheet round the camera. Outside every weather location the target is the world clock's own.
fn settleSky(g: *Game, dt: f32) void {
    settleSkyAt(g, dt, g.hero.pos);
}

/// **THE DISTANCE HAZE IS ITS OWN SWITCH, NOT THE WEATHER EYE'S** (Editor Options > distance fog, on by
/// default). The eye is about rain and mist over the ground being sculpted; the haze is the clear-air falloff
/// the 560 m world is sized for, and hanging it off the eye meant the editor always looked at a flat far edge.
fn hazeK(g: *const Game) f32 {
    if (!g.editor.on) return g.menu.fogK();
    return if (g.editor.showFog) g.menu.fogK() else 0;
}

/// Always true in play. In the editor it answers to two eyes: the sky's own, and the LOCATIONS layer's — weather is a property of those rectangles.
fn skyLive(g: *const Game) bool {
    if (!g.editor.on) return true;
    return g.editor.showWeather and g.editor.visible(.locations);
}

fn settleSkyAt(g: *Game, dt: f32, at: rl.Vector3) void {
    // **SHUT MEANS GONE THIS FRAME, NOT FADING** (owner: make sure it hides/shows weather instantly).
    if (!skyLive(g)) {
        g.wetNow = 0;
        g.fogNow = 0;
        g.sporeNow = 0;
        return;
    }
    const here = g.map.weatherAt(at.x, at.z);
    const wantWet = if (here) |l| l.wet orelse g.weather.rain() else g.weather.rain();
    const wantFog = if (here) |l| l.fog orelse 0 else 0;
    const wantSpore = if (here) |l| l.spore orelse 0 else 0;
    // **AND THE EDITOR NEVER RAMPS** — its camera jumps across the map, so a blend is weather arriving over somewhere you have already left.
    if (g.editor.on) {
        g.wetNow = mathx.clampF(wantWet, 0, 1);
        g.fogNow = mathx.clampF(wantFog, 0, 1);
        g.sporeNow = mathx.clampF(wantSpore, 0, 1);
        return;
    }
    const secs = if (here) |l| l.blend else SKY_SETTLE;
    const rate = 1.0 / mathx.maxF(secs, 0.05);
    g.wetNow = mathx.approach(g.wetNow, mathx.clampF(wantWet, 0, 1), rate * dt);
    g.fogNow = mathx.approach(g.fogNow, mathx.clampF(wantFog, 0, 1), rate * dt);
    g.sporeNow = mathx.approach(g.sporeNow, mathx.clampF(wantSpore, 0, 1), rate * dt);
}

/// Seconds to come back to the world's own weather once he walks out of a region.
const SKY_SETTLE: f32 = 6.0;

/// **A BLOOM BRINGS ITS OWN BANKS.** The mist field is the only cloud volume there is, so sporefall borrows it at `SPORE_BANKS` of its strength.
fn fogAmt(g: *const Game) f32 {
    if (!skyLive(g)) return 0;
    return mathx.maxF(mathx.maxF(g.menu.fogAmt(g.wetNow), g.fogNow), g.sporeNow * SPORE_BANKS);
}

/// Under half: a wall of banks buries the motes, which are what says "alive".
const SPORE_BANKS: f32 = 0.45;

fn drawWeatherOverlay(g: *Game) void {
    if (g.editor.on) return;
    weathermod.drawOverlay(rl.getScreenWidth(), rl.getScreenHeight(), weathermod.dimOf(g.wetNow), g.weather.flash());
}

pub fn drawScene(g: *Game) void {
    g.env.resetStats();
    applyStow(g);
    const cam = sceneCam(g);
    foemod.setLens(cam.position, mathx.normV(mathx.subV(cam.target, cam.position)));
    g.env.markOccluders(cam.position, if (g.editor.on) cam.position else heroAimPoint(g), g.drawDt);
    rl.gl.rlSetClipPlanes(CLIP_NEAR, drawFar(g));
    // **THE DEPTH PASS IS A WHOLE SECOND DRAW OF EVERY CASTER**, so the editor's switch skips the pass rather
    // than dimming its result — and `shadowsOff` after `bind` is what stops the colour pass sampling the map
    // it did not lay this frame (`gfx.Scene.shadowsOff`: the scale-to-zero, not the translate).
    const casting = !g.editor.on or g.editor.showShadows;
    if (casting) {
        const focus = sunFocus(g);
        g.scene.beginShadowPass(focus, shadowSpanOf(g));
        setCasterShaders(g, g.scene.depthShader);
        drawCasters(g, .{ .sun = focus });
        setCasterShaders(g, g.scene.shader);
        g.scene.endShadowPass();
    }

    rl.beginDrawing();
    const filtered = if (g.editor.on) false else g.retro.begin();
    rl.clearBackground(CLEAR);
    g.sky.draw(cam);

    const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
    var view = envmod.View.fromCamera(cam, aspect);
    if (g.editor.on) view.floor = drawFar(g);

    rl.beginMode3D(cam);
    g.scene.bind(cam.position);
    if (!casting) g.scene.shadowsOff();
    var lightBuf: [RESERVED_LIGHTS]gfx.Light = undefined;
    g.env.uploadLights(&g.scene, &view, @floatCast(rl.getTime()), reservedLights(g, &lightBuf));
    g.scene.setGround(true);
    g.env.drawGround(&view);
    g.scene.setGround(false);
    if (shows(g, .ground)) g.env.drawWater();
    if (g.menu.wireframe) rl.gl.rlEnableWireMode();
    drawCasters(g, .{ .view = view });
    if (shows(g, .decor)) {
        g.scene.setWind(true);
        g.env.drawFlora(&view);
        g.scene.setWind(false);
    }
    drawArrows(g);
    g.souls.draw();
    drawDrops(g);
    for (&g.boltGas) |*c| c.drawFx();
    if (shows(g, .props)) g.env.drawThinned(&view);
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
    if (shows(g, .interact)) g.env.drawVeils(&view);
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "drawFx")) @field(g, f.field).drawFx();
    }
    g.pack.drawFx();
    g.souls.drawFx();
    g.hero.drawTrail();
    for (quivers(g)) |pool| archermod.drawArrowTrails(pool);
    if (g.menu.hitboxes and g.hero.attacking) {
        const col = if (g.hero.hitActive()) rl.Color.red else mathx.withAlpha(rl.Color.red, 90);
        rl.drawCapsuleWires(g.hero.bladeA, g.hero.bladeB, g.hero.bladeR(), 6, 3, col);
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
        // **ONE PREDICATE FOR ALL THREE SHEETS** (`skyLive`). The SPOREFALL was the thick one and was not routed through it, so the eye had nothing to shut.
    if (skyLive(g)) {
        if (!g.editor.on) g.rainfall.draw(&g.scene, cam.position, g.hero.pos, g.wetNow, g.weather.t);
        if (!g.editor.on) g.mist.draw(&g.scene, cam.position, fogAmt(g), weathermod.sporeTint(g.sporeNow));
        g.sporefall.draw(&g.scene, cam.position, if (g.editor.on) cam.position else g.hero.pos, g.sporeNow, g.weather.slowSecs());
        if (!g.editor.on) g.skein.draw(&g.scene);
    }
    rl.endMode3D();

    drawWeatherOverlay(g);
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
            const cy = bandTop + bandH * 0.5;
            const glow = rgba(120, 14, 10, mathx.u8f(44.0 * ta));
            hud_.bigCentered("YOU DIED", cx - 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx + 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy - 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy + 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy, size, spacing, rgba(156, 22, 16, mathx.u8f(232.0 * ta)));
        }
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

fn chromeFade(g: *const Game) f32 {
    if (!g.hero.dead) return 1;
    return 1.0 - mathx.smoothstep(0, HUD_FADE_DUR, g.hero.deathT);
}

pub fn hud(g: *Game, dt: f32) void {
    if (g.rest.active() or g.talk.active()) return;
    const chrome = chromeFade(g);
    const wantChrome = !g.menu.isOpen() and chrome > 0.001;
    const spiritFace = wantChrome and spiritFaceFor(g);
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
                hudAils(&g.hero.vit),
            );
            hud_.dayDial(g.day.hour);
            const bowUp = g.hero.bowOut();
            const wandUp = g.hero.wandOut();
            hud_.equipment(
                if (!g.hero.offInHand()) .empty else armSlot(g, g.hero.off),
                armSlot(g, g.hero.armInHand()),
                if (wandUp and g.hero.armed()) hud_.Slot{ .sorcery = g.hero.spell } else .empty,
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
            hud_.souls(g.hero.souls.display());
            hud_.gold(g.hero.gold.display());
            bossBars(g, dt);
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

pub const Mode = enum { play, shots, props, land, art };

/// **A HITCH IS NOT SIMULATED IN FULL.** `arrowCover` queries a radius of `speed * dt` and `MAX_NEAR` is pinned
/// over a 2x2 cell window — at 40 m/s a 0.35 s stall asks for a 3-wide one and the overflow DROPS SILENTLY,
/// which is an arrow through a wall. `drawDt`, the editor and the audio pump keep the raw figure.
const DT_MAX: f32 = 1.0 / 30.0;

pub fn run(mode: Mode) void {
    const shot = mode != .play;
    var runTimer = std.time.Timer.start() catch unreachable;
    const stamp = struct {
        fn ms(t: *std.time.Timer, name: []const u8) void {
            std.debug.print("INIT: {s: <10} {d:.1} ms\n", .{ name, @as(f64, @floatFromInt(t.lap())) / 1e6 });
        }
    }.ms;
    // VSYNC, not `setTargetFPS`: that is a CPU-side frame LIMITER and never tells the driver to swap during vblank, so the swap lands mid-scan and fullscreen tears.
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
    defer hud_.unloadPortrait();
    defer menumod.unload();
    defer editormod.unloadMinimap();

    // BEFORE `init`, which surveys the shelf: a `--map` or `--shot` run gets `devsave<n>` and cannot reach the played files at all.
    savemod.useDevShelf(shot or !std.mem.eql(u8, worldfmt.startMap(), worldfmt.START_MAP));

    const alloc = std.heap.c_allocator;
    const g = alloc.create(Game) catch @panic("game: could not allocate Game");
    defer alloc.destroy(g);
    g.init();

    rl.gl.rlSetClipPlanes(CLIP_NEAR, CLIP_FAR);

    if (mode == .shots) {
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
    if (mode == .land) {
        @import("shots.zig").runLandShots(g);
        return;
    }
    if (mode == .art) {
        @import("shots.zig").runArtShots(g);
        return;
    }

    rl.hideCursor();
    var wasInside = false;
    var bWasDown = false;
    var bHeldT: f32 = 0;
    var lockCycleReady = true;
    var lookPad = false;
    var wasRolls: u32 = 0;
    var wasSwings: u32 = 0;
    var wasDead = false;
    var wasRefused: f32 = 0;
    var wasAiming = false;
    var wasStun: combat.StunKind = .none;
    var lastPhase: f32 = 0.75;
    var bankT: f32 = 0;
    defer g.rumble.stop();
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime();
        const dt = mathx.minF(rawDt, DT_MAX) * g.menu.timeScale;
        g.drawDt = rawDt;
        PLAY_HALF = playHalfOf(g.map.half);
        if (!g.editor.on and !g.menu.isOpen() and !g.rest.active() and !g.talk.active() and !g.award.carding()) {
            g.day.tick(dt);
            tickWeather(g, dt);
        } else if (g.editor.on) {
            // **A PAINTED WEATHER HAS TO SHOW WHILE HE IS PAINTING IT** — the sky settles against the CURSOR rather than the man.
            settleSkyAt(g, dt, g.editor.cursor orelse g.hero.pos);
        }
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
                    rl.hideCursor();
                    armScript(g);
                },
                .playtest => {
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    g.menu.started();
                    rl.hideCursor();
                    armScript(g);
                    g.hero.pos = mathx.ground(g.editor.cam.target.x, g.editor.cam.target.z);
                    plantActor(g, &g.hero.pos);
                    g.hero.pos = g.env.resolveHeroSide(g.hero.pos, HERO_R, g.hero.pos.y);
                    g.hero.setSpawn(g.hero.pos, g.hero.facing);
                    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
                    wasInside = false;
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
            editormod.drawOverlay(&g.editor, &g.map, &g.env, &g.scene, &g.day, rawDt);
            rl.endDrawing();
            continue;
        }

        g.hero.held = g.menu.isOpen();
        if (g.menu.isOpen()) {
            switch (g.menu.update(&g.retro, &g.day, &g.weather, rawDt, bookView(g), &g.shelf)) {
                .quit => break,
                .editor => {
                    g.lock = null;
                    // **THE EDITOR IS A DOOR LIKE THE REST.** `.playtest` stands him at the camera's target; a
                    // climb left armed drives his XZ straight back onto the axis of a ladder that is a hundred
                    // metres away, or one the edit has since deleted.
                    leavePlace(g);
                    g.editor.enter(g.hero.pos);
                },
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
            wasInside = false;
            g.hero.update(rawDt, 0, 0, null);
            g.hero.pose();
            g.rig.tickShake(rawDt);
            const booting = g.menu.booting();
            if (booting) {
                g.bootT += rawDt;
                bootCam(g, g.bootT);
            } else g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false);
            sfx.ambience(rawDt);
            drawScene(g);
            if (!booting) hud(g, rawDt);
            g.menu.draw(&g.retro, &g.day, &g.weather, bookView(g), .{ .hero = &g.hero, .scene = &g.scene }, &g.shelf);
            tickEnter(g, rawDt);
            drawEnterFade(g);
            rl.endDrawing();
            continue;
        }

        if (g.award.carding()) {
            var pressed = rl.getKeyPressed() != .null;
            if (rl.isMouseButtonPressed(.left) or rl.isMouseButtonPressed(.right)) pressed = true;
            inline for (.{ .right_face_down, .right_face_right, .right_face_left, .right_face_up, .middle_right, .middle_left }) |b| {
                if (rl.isGamepadButtonPressed(PAD, b)) pressed = true;
            }
            if (pressed) g.award.dismiss();
            heldFrame(g, rawDt, &bWasDown, &bHeldT, &wasInside);
            g.award.drawCard();
            rl.endDrawing();
            continue;
        }

        if (g.enterAct != null) {
            heldFrame(g, rawDt, &bWasDown, &bHeldT, &wasInside);
            tickEnter(g, rawDt);
            drawEnterFade(g);
            rl.endDrawing();
            continue;
        }

        if (g.rest.active()) {
            tickRest(g, rawDt);
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            takeSlotShot(g);
            hud(g, rawDt);
            restmod.drawScreen(&g.rest, restView(g));
            saveMark(g, rawDt);
            rl.endDrawing();
            continue;
        }
        // **A COUNTER TAKES THE FRAME, LIKE A CONVERSATION DOES.** Before `g.talk`, because a shop opened from
        // inside a dialog's own act list would otherwise be drawn under the panel that opened it.
        if (g.counter.open) {
            tickCounter(g, rawDt);
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            counterui.draw(&g.counter, &g.hero, &g.bag, g.counterT);
            rl.endDrawing();
            continue;
        }
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
                // **A BODY KNOCKED DOWN IN FRONT OF YOU IS NOT HIDING.** `collision.blocksSight` takes the LOWER
                // of the two ends, so a mark that has fallen to 0.4 m is stopped by any knee-high rubble on the
                // line, and the lock was dropped 1.1 s into the punish window it had just bought.
            } else if (canSee(g, li) or foeStaggered(g, li)) {
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
        const padMag = @sqrt(padRX * padRX + padRY * padRY);
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
            const look = stickRadial(padRX, padRY, LOOK_DEADZONE, LOOK_CURVE);
            const mouseLook = inside and wasInside and (@abs(md.x) + @abs(md.y)) > MOUSE_WAKE;
            const padClaim = padMag > LOOK_CLAIM;
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
            .dyaw = mathx.degrees(mathx.wrapPi(g.rig.yaw - yawBefore)),
            .pad = lookPad,
        };
        wasInside = inside;
        if (wheel != 0) g.rig.zoom(wheel);

        const swapReq = rl.isKeyPressed(.q) or padPressed(.left_face_right);
        if (swapReq and g.hero.swapArm()) sfx.play(.flask_cycle);

        const offReq = rl.isKeyPressed(.f) or padPressed(.left_face_left);
        if (offReq and g.hero.swapOff()) sfx.play(.flask_cycle);

        const drinkReq = rl.isKeyPressed(.r) or padPressed(QUICK_PAD);
        const cycleReq = rl.isKeyPressed(.t) or padPressed(.left_face_down);
        if (cycleReq and !g.hero.dead) {
            g.hero.cycleQuick();
            sfx.play(.flask_cycle);
        }

        const spellReq = rl.isKeyPressed(.g) or padPressed(.left_face_up);
        if (spellReq and g.hero.cycleSpell()) sfx.play(.flask_cycle);

        const arrowReq = rl.isKeyPressed(ARROW_KEY);
        if (arrowReq and g.hero.cycleArrow()) sfx.play(.flask_cycle);

        const useReq = rl.isKeyPressed(INTERACT_KEY) or padPressed(INTERACT_PAD);
        // **NOT FROM A RUNG.** Every other reach is measured in XZ, so eight metres up a ladder he was still
        // beside the bonfire he had climbed away from and could sit down at it.
        if (useReq and !g.hero.dead and g.climb == null) interact(g);

        var rollReq = rl.isKeyPressed(.space);
        const bDown = padDown(hud_.padOf(hud_.BTN_BACK));
        if (bDown) {
            bHeldT += rawDt;
        } else {
            if (bWasDown and bHeldT < ROLL_TAP_MAX) rollReq = true;
            bHeldT = 0;
        }
        bWasDown = bDown;

        const l1Held = rl.isMouseButtonDown(.right) or padDown(.left_trigger_1);
        const l1Press = rl.isMouseButtonPressed(.right) or padPressed(.left_trigger_1);
        const l2Held = rl.isKeyDown(PARRY_KEY) or padDown(.left_trigger_2);
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

        var mv = gatherMove();
        if (!g.hero.stam.canSprint()) mv.speed = @min(mv.speed, RUN_SPEED);
        const wade = wadeDrag(g);
        if (wade < 1.0) mv.speed = @min(mv.speed, WALK_SPEED * wade);
        g.hero.vit.tick(dt);
        g.hero.regen.tick(dt, &g.hero.vit);
        g.hero.tickTimed(dt);
        g.hero.tickFlash(dt);
        g.hero.quick.dropEmpty(&g.bag);
        const jumpReq = rl.isKeyPressed(JUMP_KEY) or padPressed(JUMP_PAD);
        // **THE ONE INPUT A LADDER ANSWERS BESIDES THE STICK.** Everything else is refused by `committed()`, so
        // this has to be read before the block that asks it.
        if (g.climb != null and (jumpReq or rollReq)) dropOffLadder(g);
        if (!g.hero.dead and !g.hero.staggered() and g.gateWalk == null) {
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
                castWand(g);
            } else if (ringReq) {
                ringBell(g);
            }
            g.hero.steerQueuedRoll(rollDir(g, mv));
            if (drinkReq) quickUse(g);
        }
        g.hero.sprinting = sprintingMove(mv) and !g.hero.committed() and !g.hero.dead and !g.hero.staggered();
        g.hero.setGuard(guardHeld);
        g.hero.setAim(aimHeld);
        if (g.hero.guarding) mv.speed = @min(mv.speed, WALK_SPEED * heromod.GUARD_SPEED * g.hero.guardWalk());
        if (g.hero.aiming) mv.speed = @min(mv.speed, WALK_SPEED * heromod.BOW_AIM_SPEED);
        if (g.hero.drinking) mv.speed = @min(mv.speed, WALK_SPEED * heromod.DRINK_SPEED);

        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        const faceYaw: ?f32 = if (g.hero.aiming) g.rig.yaw else lockYaw;
        g.hero.aimAtPitch(meleePitch(g));
        leanToGround(g, dt);
        const heroWas = g.hero.pos;
        const heroAfoot = !g.hero.dead;
        // **A CROSSING IS ABANDONED, NOT SUSPENDED.** A walk left standing resumes against a line drawn before the interruption, which is a teleport either way.
        // **AND A LADDER IS LET GO OF, NOT DELETED.** `leaveLadder` drops the `lift` where it stands, so a
        // stagger that arrives from INSIDE the body — the stun and sleep procs and the berserk bargain coming
        // due (`hero.tickPoison`), none of which go through the blow path's own `knockOffLadder` — put him at
        // the foot of a twelve-metre run in one frame with no fall at all.
        if (g.hero.dead or g.hero.staggered()) {
            g.gateWalk = null;
            dropOffLadder(g);
        }
        if (g.hero.dead) {
            g.hero.updateDeath(dt);
            if (!g.hero.dead) resetFoes(g);
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt);
        } else if (g.gateWalk != null) {
            updateGateWalk(g, dt);
        } else if (g.climb != null) {
            updateClimb(g, dt, mv);
        } else if (g.hero.airborne()) {
            moveHeroAir(g, dt, mv, faceYaw);
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF);
        } else if (g.hero.drinking) {
            g.hero.tickDrink(dt);
            moveHero(g, dt, if (g.hero.drinking) mv else .{}, faceYaw);
        } else if (g.hero.attacking) {
            g.hero.updateAttack(dt, PLAY_HALF, faceYaw);
        } else if (g.hero.parrying) {
            g.hero.updateParry(dt, faceYaw);
        } else if (g.hero.shooting) {
            g.hero.updateShot(dt, faceYaw);
        } else if (g.hero.ringing) {
            g.hero.updateRing(dt, faceYaw);
        } else if (g.hero.casting) {
            g.hero.updateCast(dt, faceYaw);
            g.rumble.play(rumblemod.castCharge(g.hero.chargeFill()));
        } else {
            moveHero(g, dt, mv, faceYaw);
        }
        if (heroAfoot and !g.hero.climbing) gateHeroTerrain(g, heroWas);
        const wasPos = &frameWasPos;
        var wasN: [FOE_GROUPS.len]usize = undefined;
        inline for (FOE_GROUPS, 0..) |f, gi| {
            const row = @field(g, f.field).live();
            wasN[gi] = row.len;
            snapshotPos(row, &wasPos[gi]);
        }
        if (g.hero.loosed) looseShaft(g);
        if (g.hero.rang) summonSpirit(g);
        const hitsBefore = allHits(g);
        markSight(g);
        markThreat(g, dt);
        markWays(g);
        markWade(g);
        markParry(g);
        markVigil(g);
        markFlock(g);
        const bladeNow = heroBlade(g);
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= ogremod.SLAM_HIT.stance, true);
        }
        // **THREAD BY HAND AND IT GOES OUT OF STEP**: `markWays` steers every creature at `threat.aim`, so an
        // archer handed the hero here kited round the wolf while it ranged on the man. The arrow still flies at
        // him — no projectile in the game takes the spirit (`spawnClump`'s shape).
        for (g.line.live()) |*a| {
            if (a.update(dt, a.threat.aim(g.hero.pos), PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), heroAimPoint(g));
            }
            if (a.heroHit) |h| {
                const out = heroTakes(g, .{ .hit = h, .from = a.pos, .on = a.threat.on }, false, true);
                heroShoved(g, a.pos, archermod.BUTT_SHOVE, out);
            }
        }
        if (g.band.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnClump)) |b| {
            _ = heroTakes(g, b, b.hit.poise >= koboldmod.ZERK_HIT.poise, true);
        }
        if (g.muster.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
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
        if (g.herd.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // **THE CREATURE SAYS WHEN AND THIS SAYS IT** — a creature calling `sfx` itself would play through the pause card and the shot harness.
        for (g.herd.live()) |*d| {
            if (d.opened) sfx.world(.deer_bloom, d.pos);
            if (d.spat) sfx.world(.deer_spit, d.pos);
            if (d.charged) sfx.world(.deer_charge, d.pos);
            if (d.gored) sfx.world(.deer_gore, d.pos);
            if (d.yelped) sfx.world(.deer_hurt, d.pos);
            if (d.justDied) sfx.world(.deer_die, d.pos);
        }
        if (g.ring.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        for (g.ring.live()) |*k| {
            if (k.kindled) sfx.world(.mage_kindle, k.pos);
            if (k.yelped) sfx.world(.mage_hurt, k.pos);
            if (k.justDied) sfx.world(.mage_die, k.pos);
            if (k.lobbed) {
                sfx.world(.mage_throw, k.lobFrom);
                spawnEmber(g, k.lobFrom);
            }
        }
        if (g.host.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        for (g.host.live()) |*h| {
            if (h.burst) |at| {
                sfx.world(.ember_burst, at);
                g.ring.splash(at);
                g.rig.addShake(SHAKE_HIT_HEAVY);
            }
            if (h.lobFrom) |from| {
                sfx.world(.shroom_fling, from);
                spawnSac(g, from);
            }
        }
        if (g.marsh.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        for (g.marsh.live()) |*l| {
            if (l.broke) sfx.world(.lurker_break, l.pos);
            if (l.lashed) sfx.world(.lurker_lash, l.pos);
            if (l.sank) sfx.world(.lurker_sink, l.pos);
            if (l.yelped) sfx.world(.lurker_hurt, l.pos);
            if (l.justDied) sfx.world(.lurker_die, l.pos);
        }
        if (g.clatter.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        for (g.clatter.live()) |*sk| {
            if (sk.reared) sfx.world(.skitter_clack, sk.pos);
            if (sk.sliced) sfx.world(.skitter_slice, sk.pos);
            if (sk.yelped) sfx.world(.bone_hurt, sk.pos);
            if (sk.justDied) sfx.world(.bone_die, sk.pos);
        }
        // **NOR DOES THE BLOOM** — its gas is taken below, beside the sporeling's spores.
        g.bed.update(dt, g.hero.pos, PLAY_HALF, bladeNow);
        for (g.bed.live()) |*b| {
            if (b.swelled) sfx.world(.shroom_puff, b.centerWorld());
            if (b.vented) sfx.world(.shroom_fling, b.ventWorld());
            if (b.yelped) sfx.world(.shroom_hurt, b.pos);
            if (b.justDied) sfx.world(.shroom_die, b.pos);
        }
        if (g.scorch.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.gorge.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.stand.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.pan.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // **THE NET IS NOT A HEAVY BLOW** — four damage and no stance, so it must not fire the heavy hurt
        // beat and voice the way the trident does. `Hit.heavy` is what every other group already asks.
        if (g.shoal.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // **THE NET TAKES HIS FEET AND NOTHING ELSE** — taken after the group, beside the other things a
        // creature does to him that is not a blow.
        g.hero.snareFor(g.shoal.takeSnare());
        // **THE BAT LEARNS WHETHER ITS OWN JAWS DREW BLOOD, AND NOTHING ELSE.** `heroTakes` already knows —
        // every other group throws the answer away with `_ =`. Blood puts it into a planted drink; a shield
        // denies the heal outright and repels it. Nothing here reads an input: the outcome of ITS blow is a
        // fact about the world, the same channel the leechfly's drink and the fishman's snare come down.
        if (g.roost.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            g.roost.fedOn(heroTakes(g, b, b.hit.heavy(), true) == .taken);
        }
        if (g.roost.anyDrank()) {
            g.rumble.play(rumblemod.hurt);
            g.rig.addShake(SHAKE_HURT);
        }
        // **THE PRIEST NEVER RETURNS A BLOW** — no melee, and its cold is a per-frame DRIP on its own channel, so it cannot voice and shake the hero sixty times a second.
        _ = g.crypt.update(dt, g.hero.pos, PLAY_HALF, bladeNow);
        if (g.crypt.breathDose(dt, g.hero.pos)) |b| {
            _ = heroTakes(g, b, false, false);
        }
        for (g.crypt.live()) |*p| {
            if (p.called) sfx.world(.priest_call, p.pos);
            if (p.drewBreath) sfx.world(.priest_breath, p.muzzleWorld());
            if (p.yelped) sfx.world(.bone_hurt, p.pos);
            if (p.justDied) sfx.world(.bone_die, p.pos);
            // The creature cannot do it: the skitterers are another array of another type (the necromancer's `applyRaises` law).
            if (p.raised) {
                // **ON THE GROUND UNDER THE SPOT, NOT AT THE CASTER'S OWN FEET**: the priest carries its own
                // `pos.y` into `raiseAt`, so on a bank the body came up buried. And INSIDE THE MOVEMENT CLAMP
                // first — `RAISE_OUT` is 5.6 m out, and a body whose `home` is outside `PLAY_HALF` never walks.
                const spot = mathx.clampXZ(p.raiseAt, PLAY_HALF);
                const at = v3(spot.x, g.env.groundAt(spot.x, spot.z), spot.z);
                g.clatter.raise(at, mathx.headingXZ(mathx.dirXZ(at, g.hero.pos)));
                sfx.world(.sac_hatch, at);
                g.rumble.play(rumblemod.hit_heavy);
                g.rig.addShake(SHAKE_RAISE);
            }
        }
        if (g.belfry.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        for (g.belfry.live()) |*h| {
            if (h.gaped) sfx.world(.toad_gape, h.pos);
            if (h.snapped) sfx.world(.toad_chomp, h.pos);
            if (h.heaved) sfx.world(.ogre_heave, h.pos);
            if (h.clanked) sfx.world(.hollow_clank, h.bellWorld());
            if (h.sparked) {
                const at = h.sparkWorld();
                spawnSpark(g, at);
                sfx.world(.gremlin_spark, at);
            }
            if (h.yelped) sfx.world(.bone_hurt, h.pos);
            if (h.justDied) sfx.world(.bone_die, h.pos);
            if (h.tolled) {
                const at = h.bellWorld();
                sfx.world(.hollow_toll, at);
                rouseAll(g, at, hollowmod.TOLL_R);
                g.rumble.play(rumblemod.hit_heavy);
                g.rig.addShake(SHAKE_TOLL);
            }
        }
        applyRaises(g);
        if (g.rite.anyLaid()) {
            g.rumble.play(rumblemod.swing_light);
            g.rig.addShake(SHAKE_SIGIL);
        }
        if (g.vigil.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= knightmod.CHARGE_HIT.stance, true);
        }
        // **A `FOE_GROUPS` ROW OWES `run` THIS CALL AND NOTHING CHECKS THAT** (the table's own note). Without
        // it the pair spawned, drew, and showed two boss bars while never once taking a step: `update` is what
        // ticks the leash, so a creature that is never updated can never notice anybody.
        if (g.vanguard.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.launch > 0, true);
        }
        if (g.conclave.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.launch > 0, true);
        }
        tickBoltGas(g, dt);
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
            var burst = burstsBefore;
            while (burst < g.brood.bursts) : (burst += 1) g.trig.died(.brood_sac);
        }
        if (anyParried(g)) parryBeat(g);
        // AFTER EVERY GROUP AND BEFORE ANYTHING READS A BODY'S HP (`foe.takeTurned`).
        spendTurnedBlows(g);
        g.hero.poisonBy(g.brood.burn(dt, g.hero.pos));
        g.hero.poisonBy(g.cluster.spores(dt, g.hero.pos));
        // THE GAS, ON THE SPORES' OWN CHANNEL: unblockable, unparryable, and rate-gated in `Vitals.build`.
        g.hero.doseSelf(.sleep, g.bed.breath(g.hero.pos) * dt);
        // …AND THE MAGUS'S VANISH LEAVES THE SAME METER BEHIND IT, through the cloud's soak rather than a rate:
        // the mist is something you walk into, so clipping its rim costs the bolus and nothing more.
        g.hero.doseSelf(.sleep, g.conclave.breath(g.hero.pos, dt));
        // **BURNT GROUND BILLS THE SAME WAY A CLOUD DOES** — a soak, not a blow, so a shield answers neither.
        g.hero.doseSelf(.burning, g.scorch.scorching(dt, g.hero.pos));
        tickLiquid(g, dt);
        _ = g.hero.tickPoison(dt);
        if (g.hero.vit.ailProcced(.poison)) {
            sfx.play(.acid_burn);
            g.rig.addShake(SHAKE_HURT);
            g.rumble.play(rumblemod.hurt);
            g.hero.hurtFlash = mathx.maxF(g.hero.hurtFlash, 0.7);
        }
        tickPack(g, dt);
        g.chests.update(dt, g.hero.pos);
        g.pickups.update(dt, g.hero.pos);
        hidePickups(g);
        g.award.update(dt);
        var wasFolk: [npcmod.CAP]rl.Vector3 = undefined;
        const nFolk = g.folk.n;
        snapshotPos(g.folk.live(), &wasFolk);
        g.folk.update(dt, g.hero.pos, PLAY_HALF);
        voiceFolk(g);
        gateTerrain(g, g.folk.live(), wasFolk[0..nFolk], null, false);
        inline for (FOE_GROUPS, 0..) |f, gi| gateTerrain(g, @field(g, f.field).live(), wasPos[gi][0..wasN[gi]], f.kind, false);
        inline for (FOE_GROUPS, 0..) |f, gi| gateChill(@field(g, f.field).live(), wasPos[gi][0..wasN[gi]]);
        if (g.hero.breathLive()) rimeBreathe(g, dt);
        for (&g.arrows) |*ar| {
            if (!ar.live) continue;
            flyArrow(g, ar, dt);
            if (ar.hit) {
                // A BOMB'S BLOW IS ITS BLAST AND NOTHING ELSE (`detonates`), so the generic direct bill is skipped and `emberBlast` owns the whole event.
                if (!detonates(ar.shot)) {
                    const blow = foemod.Blow{
                        .hit = ar.blow,
                        .from = mathx.addV(g.hero.pos, mathx.scaleV(ar.vel, -1)),
                    };
                    const out: combat.HitOutcome = if (g.hero.dead) .ignored else heroTakes(g, blow, blow.hit.heavy(), false);
                    if (out == .taken or out == .ignored) sfx.play(.arrow_hit);
                    shotStatus(g, ar.shot, out);
                }
                splashOf(g, ar);
                emberBlast(g, ar);
            } else if (justLanded(ar)) {
                planted(g, ar);
                emberBlast(g, ar);
            }
        }
        if (allHits(g) > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
            sfx.play(if (g.hero.atkHeavy) .hit_heavy else .hit_light);
            if (g.hero.attacking) _ = g.hero.drinkLeech();
        }
        // **DAMAGE MAY NOT LAND BEFORE THE BODIES UPDATE.** `justDied` is a one-frame edge each creature clears
        // at the top of its own update, so a kill cast before that loop was dead with nothing paid for it — no souls, no drop, no `trig.died`, no kill sound.
        if (g.hero.thrown) releaseSpell(g);
        stepShafts(g, dt);
        emberBounces(g);
        if (anyFoeDied(g)) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_KILL);
            sfx.play(.kill);
        }
        g.hero.souls.gain(allSouls(g));
        if (g.lock) |li| {
            if (!foeLockable(g, li)) g.lock = acquireLock(g);
        }
        collideActors(g, dt);
        heroFooting(g, heroWas);
        if (!g.hero.climbing) {
            groundActorFrom(g, &g.hero.pos, g.hero.footY(), dt);
            g.hero.syncLift();
        }
        syncLensLift(g);
        inline for (FOE_GROUPS) |f| {
            for (@field(g, f.field).live()) |*a| groundActor(g, &a.pos, dt);
        }
        for (g.folk.live()) |*p| groundActor(g, &p.pos, dt);
        for (g.pack.live()) |*w| groundActor(g, &w.pos, dt);
        tickTriggers(g, dt);
        if (g.trig.takeCounter()) |k| openCounter(g, k);
        g.rig.tickShake(rawDt);
        g.rig.aimB = g.hero.aimB;
        g.rig.tickLift(g.hero.lift, liftShare(&g.hero), dt);
        g.rig.followClear(g.hero.shoulderPoint(), camFloor(g), CamFloor.at);
        sfx.listen(g.rig.cam.position, g.rig.rightXZ());
        sfx.ambience(rawDt);
        footsteps(g, &lastPhase);

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
        if (g.hero.stun == .heavy and wasStun != .heavy) sfx.play(.stagger);
        wasStun = g.hero.stun;
        if (g.hero.dead and !wasDead) {
            g.rumble.play(rumblemod.death);
            g.rig.addShake(SHAKE_DEATH);
            sfx.play(.death);
            spillSouls(g);
        }
        if (!g.hero.dead and wasDead) sfx.play(.respawn);
        if (g.hero.dead) {
            g.deathFade = RESPAWN_HOLD + RESPAWN_FADE;
        } else if (g.deathFade > 0) {
            g.deathFade -= rawDt;
        }
        wasDead = g.hero.dead;
        g.rumble.update(rawDt, rl.isGamepadAvailable(PAD));

        drawScene(g);
        hud(g, rawDt);
        saveMark(g, rawDt);
        tickEnter(g, rawDt);
        drawEnterFade(g);
        rl.endDrawing();
    }
}

/// **ONE FRAME WITH THE WORLD HELD** — the award card's and the map cut's. The three loop-locals go by pointer
/// because they belong to `run`'s own frame: `bWasDown`/`bHeldT` POISON the pad-B tap window so releasing B on
/// the frame the card closes cannot come out as a roll, and `wasInside` swallows the held frame's mouse delta.
fn heldFrame(g: *Game, rawDt: f32, bWasDown: *bool, bHeldT: *f32, wasInside: *bool) void {
    g.hero.held = true;
    bWasDown.* = true;
    bHeldT.* = ROLL_TAP_MAX;
    wasInside.* = false;
    g.hero.update(rawDt, 0, 0, null);
    g.hero.pose();
    g.rig.follow(g.hero.shoulderPoint());
    g.rumble.update(rawDt, false);
    sfx.ambience(rawDt);
    sfx.tickStreams();
    drawScene(g);
    hud(g, rawDt);
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

fn stepOverlay(g: *const Game, x: f32, z: f32) ?sfx.Id {
    if (g.env.inWater(x, z, 1.0)) return LIQUID_VOICE[@intFromEnum(g.env.liquidAt(x, z))].step;
    const i = g.map.soilIndex(x, z) orelse return null;
    const v = g.map.soil[i];
    if (v >= worldfmt.Soil.N) return null;
    return switch (@as(worldfmt.Soil, @enumFromInt(v))) {
        .stone => .step_stone,
        .none, .dirt, .turf, .silt, .ash, .moss, .bone, .cinder, .spore, .bloom => null,
    };
}

/// **HOW FAR A POOL IS HEARD FROM**, in metres, and what bounds the scan that finds one.
const LIQUID_EAR: f32 = 34.0;
/// Cells inside `LIQUID_EAR` that make a bed full. At 2.5 m a cell, 40 is a pond about 18 m across.
const LIQUID_FULL: f32 = 40.0;
/// **TEXTURE IS THINNED IN COUNT, NOT JUST IN LEVEL.** The surface pops far more often than it is heard to.
const POP_EVERY: f32 = 1.15;
/// …and the same rule on the bite: lava bills every frame, and says so once a second.
const SEAR_EVERY: f32 = 1.0;

/// **A LIQUID'S THREE VOICES, IN ITS OWN ORDER** — the footfall it overlays, the bed it holds and the pop it
/// throws. Water has no bed and no pop (the wind is its bed); the rest carry all three. Pinned TAG-FOR-TAG at
/// comptime below, so a fifth liquid is one row here and a compile error until its voices are named after it.
const Voices = struct { step: sfx.Id, bed: ?sfx.Id = null, pop: ?sfx.Id = null };
const LIQUID_VOICE = [worldfmt.Liquid.N]Voices{
    .{ .step = .step_water },
    .{ .step = .step_oil, .bed = .oil_bed, .pop = .oil_pop },
    .{ .step = .step_fungal, .bed = .fungal_bed, .pop = .fungal_pop },
    .{ .step = .step_lava, .bed = .lava_bed, .pop = .lava_pop },
};

comptime {
    var beds: usize = 0;
    for (LIQUID_VOICE, 0..) |v, i| {
        const tag = @tagName(@as(worldfmt.Liquid, @enumFromInt(i)));
        std.debug.assert(std.mem.eql(u8, @tagName(v.step), "step_" ++ tag));
        const bed = v.bed orelse {
            // The one without a bed is water, and it is also the one without a pop.
            std.debug.assert(i == @intFromEnum(worldfmt.Liquid.water) and v.pop == null);
            continue;
        };
        std.debug.assert(std.mem.eql(u8, @tagName(bed), tag ++ "_bed"));
        std.debug.assert(std.mem.eql(u8, @tagName(v.pop.?), tag ++ "_pop"));
        // …and the bed sits in the slot `setLiquidBed` will be handed for this liquid.
        std.debug.assert(sfx.LIQUID_BEDS[i - 1] == bed);
        beds += 1;
    }
    std.debug.assert(beds == sfx.LIQUID_BEDS.len);
}

/// **THE PAINTED SHEET'S OWN FRAME**: what it soaks into him, what it costs him, and what it sounds like. The
/// scan is bounded by `LIQUID_EAR` — 27 cells a side of a 224² grid — and it does three jobs in one walk: the
/// bed level per liquid, a reservoir-sampled cell to pop from, and nothing at all when no pool is near.
fn tickLiquid(g: *Game, dt: f32) void {
    const N = worldfmt.Liquid.N;
    var weight = [_]f32{0} ** N;
    var seen = [_]f32{0} ** N;
    var pick = [_]rl.Vector3{mathx.zero3} ** N;
    if (g.env.waterAny) {
        const n = worldfmt.WATER_N;
        const cell = g.map.cellSize(n);
        const half = g.map.half;
        // THE BOX IS SOLVED, NOT WALKED TO: 27 cells a side out of 224, so the ear costs 729 tests and not 50,176.
        // Off `worldfmt`'s own axis cast, so the rim cell this lands on is the one `gridIndex` would name.
        const cz0 = worldfmt.cellAxis(half, n, g.hero.pos.z - LIQUID_EAR);
        const cz1 = worldfmt.cellAxis(half, n, g.hero.pos.z + LIQUID_EAR);
        const cx0 = worldfmt.cellAxis(half, n, g.hero.pos.x - LIQUID_EAR);
        const cx1 = worldfmt.cellAxis(half, n, g.hero.pos.x + LIQUID_EAR);
        for (cz0..cz1 + 1) |cz| {
            const wz = worldfmt.cellCentre(half, cell, cz);
            for (cx0..cx1 + 1) |cx| {
                const i = cz * n + cx;
                if (g.map.water[i] == 0) continue;
                const at = mathx.ground(worldfmt.cellCentre(half, cell, cx), wz);
                const d = mathx.dist2XZ(at, g.hero.pos);
                if (d > LIQUID_EAR * LIQUID_EAR) continue;
                const k = @min(g.map.waterKind[i], N - 1);
                weight[k] += 1.0 - @sqrt(d) / LIQUID_EAR;
                seen[k] += 1;
                // RESERVOIR OF ONE: every wet cell of a kind is equally likely to be the one that pops, in one
                // pass and with no list of candidates held anywhere.
                if (g.liquidRng.float() * seen[k] < 1.0) pick[k] = at;
            }
        }
    }
    for (LIQUID_VOICE, 0..) |v, k| {
        if (v.bed != null) sfx.setLiquidBed(k - 1, mathx.clampF(weight[k] / LIQUID_FULL, 0, 1));
        const voice = v.pop orelse continue;
        g.popT[k] -= dt;
        if (g.popT[k] > 0) continue;
        g.popT[k] = POP_EVERY * g.liquidRng.range(0.55, 1.65);
        if (seen[k] > 0) sfx.world(voice, pick[k]);
    }

    const wet = g.env.inWater(g.hero.pos.x, g.hero.pos.z, 1.0);
    const in: ?worldfmt.Liquid = if (wet) g.env.liquidAt(g.hero.pos.x, g.hero.pos.z) else null;
    const bill = liquidmod.tick(&g.liquidSoak, in, dt) orelse {
        g.searT = 0;
        return;
    };
    // A SOAK, NOT A BLOW — the shroom cloud's channel, so nothing blocks it and nothing parries it.
    g.hero.doseSelf(bill.ail, bill.amt);
    if (bill.dmgFrac <= 0) {
        // …AND THE SEAR CLOCK IS THE LAVA'S ALONE. Left running through a wade in the fungal soup, stepping
        // back into the lava owed a part-spent clock and the first bite went unheard.
        g.searT = 0;
        return;
    }
    // A SHARE OF THE BAR, IN THE AIL'S OWN ELEMENT — so fire resistance answers the lava and a levelled body
    // does not walk it off. A DRIP (`hero.burn`), so it never builds the meter a second time.
    _ = g.hero.burn(combat.ailPulse(combat.ailRow(bill.ail), bill.dmgFrac * g.hero.vit.hpMax));
    g.searT -= dt;
    if (g.searT > 0) return;
    g.searT = SEAR_EVERY;
    sfx.play(.lava_sear);
    g.rumble.play(rumblemod.hurt);
}

fn heroHurtBeat(g: *Game, heavy: bool, voice: bool) void {
    g.rumble.play(if (heavy) rumblemod.hurt_heavy else rumblemod.hurt);
    g.rig.addShake(if (heavy) SHAKE_HURT_HEAVY else SHAKE_HURT);
    if (voice) sfx.play(if (heavy) .hurt_heavy else .hurt);
}

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
        .mem = g.hero.mem,
        .fp = g.hero.fp.cur,
        .souls = g.hero.souls.display(),
        .gold = g.hero.gold.display(),
        .worn = g.hero.worn,
        .tiers = g.hero.tiers,
    };
}

/// **ONE ACTION, NOT TWO HALVES.** The row names an armament AND the thing standing in its socket, and `equip`
/// refuses while he is committed, staggered, dead or seated where `wear` does not — so ungated the refused hand
/// still socketed the weapon. Asked ONCE up front, because `equip` also returns false for a hand ALREADY
/// holding that armament, which is exactly the case that must still re-socket (one dirk swapped for the other).
fn takeHand(g: *Game, hand: usize, slot: usize, h: bookmod.Hand) void {
    if (!g.hero.bodyFree()) return;
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
        // R1 AND R2 ARE THE WHOLE MELEE KIT (owner's call). Which stroke a press plays is the armament's own answer (`hero.moveOf`), not this file's.
        .sword, .dagger, .club => {
            out.light = out.light or in.press1;
            out.heavy = out.heavy or in.press2;
        },
        .bow => {
            out.quick = out.quick or in.press1;
            out.aimed = out.aimed or in.press2;
            out.aim = out.aim or in.held2;
        },
        .bell => out.ring = out.ring or in.press1,
        .shield => {
            out.guard = out.guard or in.held1;
            out.parry = out.parry or in.press2;
        },
        .wand => out.cast = out.cast or in.press1,
        // A LIT BRAND HAS NO ACTION OF ITS OWN; what it costs is the hand.
        .torch => {},
    }
}

fn armSlot(g: *const Game, a: heromod.Armament) hud_.Slot {
    return .{ .held = .{ .arm = bookmod.armPic(a), .gear = heromod.heldGear(a, g.hero.worn) } };
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
        .regen => |r| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.regen.start(g.hero.vit.hpMax * r.frac, r.secs);
            sfx.play(.eat);
        },
        .lob => |l| {
            if (g.bag.take(k, 1) == 0) return;
            const from = mathx.addV(heroAimPoint(g), mathx.scaleV(mathx.headingDir(g.hero.facing), 0.4));
            // A dose is not scaled (`Hit.scaled`'s law), so the twist rides `thrownDmg` for a zero either way.
            const hit = (combat.Hit{ .dmg = l.dmg, .poise = l.poise, .elem = combat.elems(.{ .fire = l.fire, .lightning = l.lightning }) }).scaled(g.hero.perk.thrownDmg * g.hero.perk.dmg);
            const shot: archermod.Shot = if (l.dose != null) .powder else if (l.lightning > 0) .crock else .clump;
            putIn(&g.shafts, archermod.launchShaft(from, camAimPoint(g), koboldmod.CLUMP_SPEED, hit, true, shot));
            sfx.play(.wand_cast);
        },
        .ward => |w| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.startWard(combat.elemOf(w.elem), w.amount, w.secs);
            sfx.play(.eat);
        },
        .wind => |w| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.stam.secondWind(w.share);
            sfx.play(.flask_drink);
        },
        // **A FULL BANK REFUSES THE SHEAF** rather than eating it — `hero.startDrink`'s rule for the cerulean
        // flask, one item along. `Quiver.add` caps, so ungated the whole sheaf vanished out of the bag.
        .arrows => |a| {
            const bank: combat.ArrowKind = if (a.fire) .fire else .plain;
            if (g.hero.quiver.count(bank) >= combat.Quiver.cap(bank)) return;
            if (g.bag.take(k, 1) == 0) return;
            g.hero.quiver.add(bank, a.n);
            sfx.play(.eat);
        },
        .grease => |gr| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.startGrease(combat.elemOf(gr.elem), gr.frac, gr.secs);
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
        .dose => |d| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.doseSelf(combat.ailOfName(d.ail), d.amt);
            sfx.play(.flask_drink);
        },
        .coat => |c| {
            if (g.bag.take(k, 1) == 0) return;
            g.hero.startCoat(combat.ailOfName(c.ail), c.amt, c.secs);
            sfx.play(.eat);
        },
        // **THE BELL IS NOT SPENT, SO THERE IS NO `take` HERE** — the focus IS the charge.
        .toll => |t| {
            if (!g.hero.fp.spend(t.fp)) return;
            const n = doseRing(g, g.hero.pos, t.r, combat.ailOfName(t.ail), t.amt);
            const at = v3(g.hero.pos.x, g.env.groundAt(g.hero.pos.x, g.hero.pos.z), g.hero.pos.z);
            g.hero.sunderBurst(at, n > 0, g.hero.casts);
            sfx.play(.hollow_toll);
            g.rumble.play(rumblemod.cast_throw);
            g.rig.addShake(SHAKE_CAST);
        },
    }
}

/// **THE POWDER'S OWN ROW IS THE ONLY PLACE ITS NUMBERS LIVE** — read back off `item.use`, the way the sac's
/// cloud belongs to the sporeling.
fn powderBurst(g: *Game, ground: rl.Vector3) void {
    const row = switch (item.use(.madcap_powder)) {
        .lob => |l| l,
        else => return,
    };
    const d = row.dose orelse return;
    const a = combat.ailOfName(d.ail);
    sfx.world(.shroom_puff, ground);
    g.hero.dustPuff(ground, row.r, hud_.ailTint(a), g.hero.casts);
    _ = doseRing(g, ground, row.r, a, d.amt);
}

/// **ONE DOSE INTO EVERY BODY IN A RING**, and `Vitals.build`'s side gate decides which can carry it — a charm
/// reaching the hero is refused there and not by a list here. Returns how many took it.
fn doseRing(g: *Game, at: rl.Vector3, r: f32, a: combat.Ail, amt: f32) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            if (!foemod.corporeal(f)) continue;
            if (mathx.distXZ(at, f.pos) - f.bodyR() > r) continue;
            const was = f.vit.ail(a).meter;
            f.vit.build(a, amt);
            if (f.vit.ail(a).meter > was) n += 1;
        }
    }
    return n;
}

fn heroTakes(g: *Game, b: foemod.Blow, heavy: bool, voice: bool) combat.HitOutcome {
    if (b.on == .spirit) return spiritTakes(g, b, heavy);
    const out = g.hero.takeHit(b.hit, mathx.dirXZ(g.hero.pos, b.from));
    switch (out) {
        .ignored => {},
        .taken => {
            // **BEFORE THE BEAT** — the knock-off has to read his climb height, and the beat does not care.
            if (g.climb != null) knockOffLadder(g, b);
            heroHurtBeat(g, heavy, voice);
        },
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

comptime {
    // **THE BLOW NAMES A VICTIM, NOT AN INDEX**, so the first corporeal spirit is the only one it can land on.
    // At two out, every blow aimed at the pack would bill the same animal.
    if (combat.SUMMON_MAX != 1) @compileError("game: `spiritTakes` bills the FIRST live spirit — a second one " ++
        "needs `foe.Blow` to carry which, not just that it was a spirit");
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
        break;
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

const MELEE_AIM_R: f32 = 3.6;
const MELEE_AIM_LOCKED: f32 = 2.0 * MELEE_AIM_R;
const MELEE_AIM_DOT: f32 = 0.35;
/// The eye line the pitch is measured FROM — his shoulders, which is roughly where the flat arc lives.
const MELEE_AIM_EYE: f32 = 1.35;
/// **TOO CLOSE TO HAVE A BEARING**, and TWO numbers because they answer two questions. `MELEE_AIM_BLANK` exempts
/// a body from the front cone: something standing on his boots is not behind him. `MELEE_AIM_FLAT` refuses a
/// PITCH, which is an arctangent over a flat distance and is meaningless as that distance goes to nothing.
const MELEE_AIM_BLANK: f32 = 0.2;
const MELEE_AIM_FLAT: f32 = 0.35;

const MarkCtx = struct {
    g: *const Game,
    fwd: rl.Vector3,
    best: ?rl.Vector3 = null,
    bestD: f32 = MELEE_AIM_R,

    fn visit(self: *MarkCtx, foes: anytype, _: ?FoeKind) void {
        for (foes) |*f| {
            if (!foemod.corporeal(f)) continue;
            if (disguised(f)) continue;
            const d = mathx.distXZ(self.g.hero.pos, f.pos);
            if (d >= self.bestD) continue;
            const to = mathx.dirXZ(self.g.hero.pos, f.pos);
            if (d > MELEE_AIM_BLANK and to.x * self.fwd.x + to.z * self.fwd.z < MELEE_AIM_DOT) continue;
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
    if (flat < MELEE_AIM_FLAT) return null;
    return mathx.degrees(depression(g.hero.pos.y + MELEE_AIM_EYE, mark, flat));
}

const BOLT_GAS_CAP: usize = 8;
comptime {
    const casts = combat.FP_MAX / combat.BOLT_FP;
    std.debug.assert(@as(f32, @floatFromInt(BOLT_GAS_CAP)) >= casts * 0.9);
}
/// Per dose. **ALL CHAOS, and NO POISE AND NO STANCE** — a hazard that staggers can kill something while it is
/// not allowed to walk out. Small against the bolt's own 25: what the keystone sells is GROUND, never a bigger bolt.
const BOLT_GAS_HIT = combat.Hit{ .elem = combat.elems(.{ .chaos = 7 }) };

fn tickBoltGas(g: *Game, dt: f32) void {
    var any = false;
    for (&g.boltGas) |*c| {
        c.update(dt);
        if (c.live) any = true;
    }
    if (!any) {
        // Due the moment a cloud exists, for the same reason `knight.Vigil.gasDose` is (`foe.Soak`).
        g.boltGasT = knightmod.GAS_DOSE_EVERY;
        return;
    }
    g.boltGasT += dt;
    if (g.boltGasT < knightmod.GAS_DOSE_EVERY) return;
    g.boltGasT -= knightmod.GAS_DOSE_EVERY;
    for (&g.boltGas) |*c| {
        if (!c.live) continue;
        _ = pierceFoes(g, .{
            .active = true,
            .pierce = true,
            .through = true,
            .r = c.radius(),
            .a = c.pos,
            .b = c.pos,
            .a0 = c.pos,
            .b0 = c.pos,
            .hit = BOLT_GAS_HIT,
        });
    }
}

fn layBoltGas(g: *Game, at: rl.Vector3) void {
    g.boltGas[g.boltGasHead] = .{
        .pos = v3(at.x, g.env.groundAt(at.x, at.z), at.z),
        .scale = 1.0,
        .live = true,
        .fxRng = foemod.fxStream(at.x + at.z, 641.0, 0x8017),
    };
    g.boltGasHead = (g.boltGasHead + 1) % BOLT_GAS_CAP;
}

pub fn heroBlade(g: *const Game) foemod.Blade {
    return .{
        .active = g.hero.hitActive(),
        .r = g.hero.bladeR(),
        .a = g.hero.bladeA,
        .b = g.hero.bladeB,
        .a0 = g.hero.bladeA0,
        .b0 = g.hero.bladeB0,
        .hit = g.hero.attackHit(),
        .cullAt = g.hero.perk.cull,
    };
}

fn inBounds(p: rl.Vector3) rl.Vector3 {
    return mathx.clampXZ(p, PLAY_HALF);
}

fn collideActors(g: *Game, dt: f32) void {
    const step = COLLIDE_RATE * dt;
    // **A BODY ON A LADDER IS NOT PUSHED.** It stands hard against the wall the thing leans on, and one frame
    // of push-out is what takes him off it; the climb owns his XZ outright, exactly as the gate walk does.
    var hp = g.hero.pos;
    if (!g.hero.climbing) {
        hp = g.env.resolveHeroSide(g.hero.pos, HERO_R, g.hero.footY());
        inline for (FOE_GROUPS) |gr| {
            for (@field(g, gr.field).live()) |*a| {
                if (foemod.corporeal(a) and !a.airborne() and !phased(a) and g.hero.footY() < a.topWorld().y) {
                    hp = collision.pushOut(hp, HERO_R, bodyOf(a));
                }
            }
        }
        for (g.folk.liveConst()) |*p| hp = collision.pushOutCircle(hp, HERO_R, p.pos, p.bodyR());
        for (g.pack.liveConst()) |*w| {
            if (foemod.corporeal(w)) hp = collision.pushOutCircle(hp, HERO_R, w.pos, w.bodyR());
        }
    }
    // **THE WALL IS THE LAST WORD, AND THIS IS THE LAST HAND ON THE POSITION.** `gateHeroTerrain` holds him in
    // 300 lines earlier, and then a boss with a SHOVE presses him through it here — a sealed room you can be
    // squeezed out of is not sealed. His pre-push position is the step's start, which the room already vetted.
    const heroWasIn = g.hero.pos;
    g.hero.pos = mathx.approachV(g.hero.pos, inBounds(hp), step);
    const heroHeld = holdInRoom(&g.map, &g.arenaShut, heroWasIn, g.hero.pos, HERO_R);
    g.hero.pos.x = heroHeld.x;
    g.hero.pos.z = heroHeld.z;

    inline for (FOE_GROUPS) |gr| settleGroup(g, gr, step);

    for (g.folk.live()) |*p| {
        const r = p.bodyR();
        var q = g.env.resolveActor(p.pos, r, p.pos.y);
        q = collision.pushOutCircle(q, r, g.hero.pos, HERO_R);
        p.pos = mathx.approachV(p.pos, inBounds(q), step);
    }
    for (g.pack.live()) |*w| {
        if (!foemod.corporeal(w)) continue;
        const r = w.bodyR();
        var q = g.env.resolveHeroSide(w.pos, r, w.pos.y);
        q = collision.pushOutCircle(q, r, g.hero.pos, HERO_R);
        w.pos = mathx.approachV(w.pos, inBounds(q), step);
    }
}

/// **THE ONE THING IN THE FRAME THAT SCALES QUADRATICALLY** — n² inside the group, every frame, no distance
/// gate. The shipped map's widest group is 24 (`cluster`), so 552 `pushOut` for it and ~2,000 across all
/// `FOE_GROUPS` rows: nothing. `worldfmt.MAX_PER_KIND` is 512 though, and 512 in one group is 261,632 pairs a
/// frame and about a millisecond. Left alone on purpose; the answer is an actor grid, not an edit here.
///
/// **AND `bodyOf(o)` MAY NOT BE HOISTED OUT OF THE INNER LOOP.** `a.pos` is written at the END of each outer
/// pass, so body i settles against 0..i-1 at their NEW positions and the rest at their old ones: Gauss-Seidel.
/// A pre-pass of solids makes everyone see the old ones — Jacobi, a different and looser settle. Order-dependent
/// on purpose, so the pairs cannot be batched without changing how a crowd packs.
fn settleGroup(g: *Game, comptime gr: FoeGroup, step: f32) void {
    const foes = @field(g, gr.field).live();
    for (foes, 0..) |*a, i| {
        if (!foemod.corporeal(a) or phased(a)) continue;
        const r = a.bodyR();
        // …AND IT MATTERS MORE FOR A BODY: `holdInRoom` asks whether the step STARTED inside, so a creature
        // settled one metre out is a creature the room lets go of for good.
        const wasIn = a.pos;
        if (a.airborne()) {
            a.pos = inBounds(g.env.resolveActor(a.pos, r, a.pos.y));
            a.pos = holdInRoom(&g.map, &g.arenaShut, wasIn, a.pos, r);
            continue;
        }
        var p = g.env.resolveActor(a.pos, r, a.pos.y);
        if (gr.vsHero) p = collision.pushOutCircle(p, r, g.hero.pos, HERO_R);
        for (foes, 0..) |*o, j| {
            if (i == j or !foemod.corporeal(o) or o.airborne() or phased(o)) continue;
            p = collision.pushOut(p, r, bodyOf(o));
        }
        inline for (gr.vs) |other| {
            for (@field(g, other).live()) |*o| {
                if (foemod.corporeal(o) and !o.airborne() and !phased(o)) p = collision.pushOut(p, r, bodyOf(o));
            }
        }
        a.pos = mathx.approachV(a.pos, inBounds(p), step);
        a.pos = holdInRoom(&g.map, &g.arenaShut, wasIn, a.pos, r);
    }
}

const FoeKind = worldfmt.FoeKind;
const FoeRef = struct { kind: FoeKind, idx: usize };
const ROLE_GROUPS = .{
    .{ "band", koboldmod },
    .{ "haunt", shademod },
    .{ "brood", broodmod },
    .{ "muster", warriormod },
    .{ "shoal", fishmod },
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
    // Kinds x groups, both of which grow every time a creature is added.
    @setEvalBranchQuota(30000);
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
fn foeLockable(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype) bool {
            return foemod.corporeal(f);
        }
    }.ask);
}
fn foeStaggered(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype) bool {
            return f.staggered();
        }
    }.ask);
}
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

fn activeLock(g: *const Game) ?FoeRef {
    return if (g.hero.aiming) null else g.lock;
}

const PROJECT_NEAR = CLIP_NEAR;
fn projectToScreen(cam: rl.Camera3D, p: rl.Vector3) ?rl.Vector2 {
    const to = mathx.subV(p, cam.position);
    const fwd = mathx.normV(mathx.subV(cam.target, cam.position));
    const depth = to.x * fwd.x + to.y * fwd.y + to.z * fwd.z;
    if (depth < PROJECT_NEAR) return null;
    return rl.getWorldToScreen(p, cam);
}

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

/// **IS THIS BODY OUT OF THE WAY** — `disguised`'s twin, and DELIBERATELY NOT THE SAME QUESTION: that one is
/// about being seen, this one about being solid. A dormant snag is not a creature to look at and is still a
/// tree you walk into. An opt-in decl (`markWays`' rule), so the always-solid groups pay a comptime-false.
fn phased(f: anytype) bool {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "phased")) return f.phased();
    return false;
}

/// **WHAT A BODY HOLDS ON THE GROUND.** A circle at the feet is the whole of a creature that STANDS; one that
/// can be put on its back is metres of it lying behind them, and only the creature knows where
/// (`knight.bodySeg`). `pushOut` on a degenerate segment IS `pushOutCircle`, so nothing else changes.
fn bodyOf(f: anytype) collision.Solid {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "bodySeg")) {
        if (f.bodySeg()) |s| return collision.capsule(s[0].x, s[0].z, s[1].x, s[1].z, f.bodyR());
    }
    return collision.circle(f.pos.x, f.pos.z, f.bodyR());
}

/// **THE BODY'S METERS AS A BAR WANTS THEM, IN ONE PLACE** — so his strip and a creature's rows cannot disagree
/// about what filling and running look like. Reads the meters and not the effects they drive: the chill's own
/// hold (`combat.Chill`) is what takes the feet, but the METER is what the row is about.
fn hudAils(v: *const combat.Vitals) hud_.Ails {
    var out: hud_.Ails = undefined;
    for (&out, 0..) |*s, i| {
        const a: combat.Ail = @enumFromInt(i);
        s.* = .{ .frac = v.ailFrac(a), .on = v.ailOn(a) };
    }
    return out;
}

test "THE BURROW TAKES THE LOCK OFF YOU, and gives it back when it surfaces" {
    var d = delvermod.Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.2);
    try std.testing.expect(!disguised(&d));

    d.debugDive();
    var t: f32 = 0;
    var wasHidden = false;
    var sawMound = false;
    while (t < 12.0) : (t += 1.0 / 60.0) {
        _ = d.update(1.0 / 60.0, hero, PLAY_HALF, .{});
        try std.testing.expectEqual(d.deep(), disguised(&d));
        if (disguised(&d)) {
            wasHidden = true;
            if (d.mounded()) sawMound = true;
        }
        if (wasHidden and !disguised(&d)) break;
    }
    try std.testing.expect(wasHidden);
    try std.testing.expect(sawMound);
    try std.testing.expect(!disguised(&d));
    try std.testing.expect(t < 12.0);
}

const LockCtx = struct {
    g: *const Game,
    cx: f32,
    best: ?FoeRef = null,
    bestScore: f32 = 1e9,

    fn visit(self: *LockCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            if (!foemod.corporeal(f) or mathx.distXZ(self.g.hero.pos, f.pos) > MAX_LOCK_R) continue;
            if (disguised(f)) continue;
            const r = FoeRef{ .kind = memberKind(f, kind), .idx = i };
            if (!canSee(self.g, r)) continue;
            const sx = lockScreenX(self.g, r) orelse continue;
            const score = @abs(sx - self.cx);
            if (score < self.bestScore) {
                self.bestScore = score;
                self.best = r;
            }
        }
    }
};

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
            if ((self.cur.kind == r.kind and self.cur.idx == i) or !foemod.corporeal(f)) continue;
            if (disguised(f)) continue;
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

const CYCLE_MIN_GAP: f32 = 5.0;

fn cycleLock(g: *Game, dir: f32) void {
    const cur = g.lock orelse return;
    const curX = lockScreenX(g, cur) orelse return;
    var ctx = CycleCtx{ .g = g, .cur = cur, .curX = curX, .dir = dir };
    eachTarget(g, &ctx, CycleCtx.visit);
    if (ctx.best) |b| g.lock = b;
}

fn resetFoes(g: *Game) void {
    rehomeFoes(g, .blind);
    clearQuivers(g);
    g.lock = null;
    g.pack.clear();
    dropRunHud(g);
}

/// **EVERY BAR THE RUN LEFT ON SCREEN GOES WHILE THE SCREEN IS BLACK** (owner) — the death card's black and the
/// bonfire's are the two doors, and both already re-home the field behind them.
///
/// `bossK` and `spiritK` only tick inside `hud`, which the chrome fade and `rest.active()` both stop calling, so
/// they FROZE at full: the rail came back up carrying the dead run's HP and the dead run's chip tail and then
/// faded out in front of him, as the black lifted, instead of behind it.
fn dropRunHud(g: *Game) void {
    g.bossK = [_]f32{0} ** hud_.BOSS_SLOTS;
    g.bossFrac = [_]f32{0} ** hud_.BOSS_SLOTS;
    g.spiritK = 0;
    g.spiritHp = 0;
    hud_.dropBossBars();
    hud_.dropSpiritFace();
}

const HURT_BAR_WINDOW = 5.0;

/// A kind with a rail in `BOSS_RAILS` never gets a floating bar — the rail is its ONLY bar, duo included.
fn onBossRail(k: FoeKind) bool {
    inline for (BOSS_RAILS) |r| {
        if (k == r.kind) return true;
    }
    return false;
}

const BarCtx = struct {
    cam: rl.Camera3D,
    lock: ?FoeRef,

    fn visit(self: *const BarCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            if (!foemod.corporeal(f)) continue;
            if (onBossRail(memberKind(f, kind))) continue;
            if (disguised(f)) continue;
            const fixed = if (self.lock) |l| l.idx == i and l.kind == memberKind(f, kind) else false;
            if (!fixed and f.vit.sinceHurt > HURT_BAR_WINDOW) continue;
            const s = projectToScreen(self.cam, f.topWorld()) orelse
                projectToScreen(self.cam, f.centerWorld()) orelse continue;
            hud_.foeBar(s.x, s.y, f.vit.hpFrac(), f.staggered(), hudAils(&f.vit));
        }
    }
};

fn drawFoeBars(g: *const Game) void {
    const ctx = BarCtx{ .cam = g.rig.cam, .lock = activeLock(g) };
    eachTarget(g, &ctx, BarCtx.visit);
}

fn drawLockDot(g: *Game) void {
    const li = activeLock(g) orelse return;
    const s = projectToScreen(g.rig.cam, foeLockPoint(g, li)) orelse return;
    const x: i32 = @intFromFloat(s.x);
    const y: i32 = @intFromFloat(s.y);
    rl.drawCircleGradient(x, y, 15, rgba(255, 255, 255, 175), rgba(255, 255, 255, 0));
    rl.drawCircle(x, y, 2, rl.Color.white);
}

test "A RING IN THE BAG SAVES NOTHING — the snap is asked of the FINGER" {
    var worn = heromod.Worn{};
    try std.testing.expect(bindingWorn(worn) == null);
    worn.put(.ring, .leech_signet);
    try std.testing.expect(bindingWorn(worn) == null);
    worn.put(.ring, .soul_binding_ring);
    try std.testing.expectEqual(item.Wear.ring, bindingWorn(worn).?);
    worn.put(.ring, null);
    try std.testing.expect(bindingWorn(worn) == null);
}

