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
const mapart = @import("ui/mapart.zig");
const countermod = @import("play/counter.zig");
const counterui = @import("ui/counterui.zig");
const frogmod = @import("foes/frog.zig");
const foemod = @import("foes/foe.zig");
const foestat = @import("foes/foestat.zig");
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
const owlbearmod = @import("foes/owlbear.zig");
const druidmod = @import("foes/druidess.zig");
const mimicmod = @import("foes/mimic.zig");
const mastodonmod = @import("foes/mastodon.zig");
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
const tune = @import("play/tune.zig");
const sfx = @import("core/audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

const PAD = rumblemod.PAD;
const padPressed = rumblemod.padPressed;
const padDown = rumblemod.padDown;

pub const SCREEN_W = 1280;
pub const SCREEN_H = 800;

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
fn blowHeaviest() f32 {
    return @max(ogremod.SLAM_HIT.raw(), knightmod.FALL_HIT.raw());
}
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
const SHAKE_TOLL = 0.26;
const SHAKE_ROUSE = 0.28;
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
/// Radians, 0 level and positive DOWN.
fn depression(eyeY: f32, mark: rl.Vector3, flat: f32) f32 {
    return std.math.atan2(eyeY - mark.y, flat);
}

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
/// TEMP DEV: `--bright` drops the sky and clears MAGENTA, so every hole in the world reads as a hole.
pub var dbgBright = false;

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
    perch: owlbearmod.Perch,
    coven: druidmod.Coven,
    hoard: mimicmod.Hoard,
    drove: mastodonmod.Drove,
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
    introK: f32 = 0,
    audioK: f32 = 0,
    bossBits: savemod.BossBits = NO_BOSSES,
    seenMap: mapart.Seen = .{},
    bossK: [hud_.BOSS_SLOTS]f32 = [_]f32{0} ** hud_.BOSS_SLOTS,
    bossFrac: [hud_.BOSS_SLOTS]f32 = [_]f32{0} ** hud_.BOSS_SLOTS,
    arenaShut: [worldfmt.MAX_ARENAS]bool = [_]bool{false} ** worldfmt.MAX_ARENAS,
    gateWalk: ?GateWalk = null,
    climb: ?Climb = null,
    mantle: ?Mantle = null,
    counter: countermod.Counter = .{},
    counterT: f32 = 0,
    counterNpc: ?usize = null,
    heroDeck: ?f32 = null,
    lensGroundY: f32 = 0,
    spiritK: f32 = 0,
    spiritHp: f32 = 0,
    day: daynight.Clock = .{},
    wetNow: f32 = 0,
    fogNow: f32 = 0,
    sporeNow: f32 = 0,
    emberNow: f32 = 0,
    /// A shot's override on the location's own ember level; null in the game.
    emberForce: ?f32 = null,
    hourLit: f32 = std.math.nan(f32),
    wetLit: f32 = std.math.nan(f32),
    fogLit: f32 = std.math.nan(f32),
    sporeLit: f32 = std.math.nan(f32),
    emberLit: f32 = std.math.nan(f32),
    souls: soulsmod.Souls,
    weather: weathermod.Weather,
    rainfall: weathermod.Rain,
    mist: weathermod.Mist,
    skein: weathermod.Skein,
    sporefall: weathermod.Spore,
    emberfall: weathermod.Ember,
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
    rockModel: rl.Model,
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
    dropRng: mathx.Rng = mathx.Rng.init(0),
    liquidRng: mathx.Rng = mathx.Rng.init(0),
    saveT: f32 = 0,
    boltGas: [BOLT_GAS_CAP]knightmod.Gas = undefined,
    boltGasHead: usize = 0,
    boltGasT: f32 = 0,
    illusionMotes: [ILLUSION_MOTES]foemod.Particle = [_]foemod.Particle{.{}} ** ILLUSION_MOTES,
    illusionHead: usize = 0,
    illusionRng: mathx.Rng = mathx.Rng.init(0x1117A11),
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
        g.perch = owlbearmod.Perch.init(g.scene.shader);
        g.coven = druidmod.Coven.init(g.scene.shader);
        g.hoard = mimicmod.Hoard.init(g.scene.shader);
        g.drove = mastodonmod.Drove.init(g.scene.shader);
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
        g.introK = 0;
        g.audioK = 0;
        g.bossK = [_]f32{0} ** hud_.BOSS_SLOTS;
        g.bossFrac = [_]f32{0} ** hud_.BOSS_SLOTS;
        leavePlace(g);
        g.counter = .{};
        g.counterT = 0;
        g.counterNpc = null;
        g.lensGroundY = 0;
        g.spiritK = 0;
        g.spiritHp = 0;
        g.wetNow = 0;
        g.fogNow = 0;
        g.sporeNow = 0;
        g.emberNow = 0;
        g.emberForce = null;
        g.hourLit = std.math.nan(f32);
        g.wetLit = std.math.nan(f32);
        g.fogLit = std.math.nan(f32);
        g.sporeLit = std.math.nan(f32);
        g.emberLit = std.math.nan(f32);
        g.souls = soulsmod.Souls.init(g.scene.shader);
        g.weather = weathermod.Weather.init(0x5701_A17E);
        g.rainfall = weathermod.Rain.build(g.scene.shader);
        g.mist = weathermod.Mist.build(g.scene.shader);
        g.skein = weathermod.Skein.build(g.scene.shader);
        g.sporefall = weathermod.Spore.build(g.scene.shader);
        g.emberfall = weathermod.Ember.build(g.scene.shader);
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
        g.rockModel = delvermod.rockModel(g.scene.shader);
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
        g.illusionMotes = [_]foemod.Particle{.{}} ** ILLUSION_MOTES;
        g.illusionHead = 0;
        g.illusionRng = mathx.Rng.init(0x1117A11);
        g.dropRng = mathx.Rng.init(0xD0DEC0DE);
        g.bossBits = NO_BOSSES;
        g.seenMap = .{};
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


// Owner: away from the tower. The old mark (-104, 18) drifted under the watchtower at (-119, 23); the wooded downs here have the well, the graves and the big trees, and nothing tall for seventy metres.
const BOOT_AT_X: f32 = -60.0;
const BOOT_AT_Z: f32 = 60.0;
const BOOT_DRIFT_R: f32 = 26.0;
const BOOT_DRIFT_RATE: f32 = 0.036;
const BOOT_LOOK_UP: f32 = 6.0;

pub const BOOT_YAW_MID: f32 = 53.0;
const BOOT_YAW_SWEEP: f32 = 38.0;
const BOOT_YAW_T: f32 = 41.0;
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

const INTRO_FADE_IN: f32 = 14.0;
const INTRO_FADE_OUT: f32 = 1.2;
const INTRO_VOL: f32 = 0.55;
const AUDIO_FADE_IN: f32 = 4.5;

/// `menu.booting()` is the boot screen, the slot picker and Options; the editor is asked separately because entering it leaves `screen` where it was.
/// The ambience ramp is ONE-WAY — the bed belongs to the world and only ever comes UP. Apart from the stream, so both directions can be measured without a device.
fn introRamp(k: f32, want: bool, dt: f32) f32 {
    return mathx.clampF(k + (if (want) dt / INTRO_FADE_IN else -dt / INTRO_FADE_OUT), 0, 1);
}

fn tickAudioFades(g: *Game, dt: f32) void {
    g.audioK = mathx.clampF(g.audioK + dt / AUDIO_FADE_IN, 0, 1);
    sfx.ambienceFade(g.audioK);

    const want = g.menu.booting() and !g.editor.on;
    if (want) sfx.introOn(true);
    g.introK = introRamp(g.introK, want, dt);
    sfx.introLevel(g.introK * g.audioK * INTRO_VOL);
    if (!want and g.introK <= 0) sfx.introOn(false);
}

pub fn bootCam(g: *Game, t: f32) void {
    g.rig.yaw = mathx.radians(BOOT_YAW_MID + BOOT_YAW_SWEEP * mathx.sinf(t * std.math.tau / BOOT_YAW_T));
    g.rig.pitch = BOOT_PITCH + BOOT_SWOOP_PITCH * mathx.sinf(t * std.math.tau / BOOT_SWOOP_T);
    g.rig.dist = BOOT_DIST + BOOT_SWOOP_DIST * mathx.sinf(t * std.math.tau / BOOT_PUSH_T + 1.1);
    g.rig.followCentred(bootLook(g, t));
}

fn beginGame(g: *Game) void {
    var start = g.map.start.at();
    plantActor(g, &start);
    g.hero.setSpawn(start, g.map.start.facing());
    g.hero.souls = .{};
    g.hero.gold = .{};
    // The rack holds four DISTINCT armaments (`tidyHands`), so the two stowed cells are the other melee class and a torch — nothing in the off hand that would fight the sword for the one held bone.
    g.hero.arm = .sword;
    g.hero.armAlt = .dagger;
    g.hero.off = .shield;
    g.hero.offAlt = .torch;
    g.hero.spell = .bolt;
    g.hero.mem = .{ .slots = [_]?combat.Spell{null} ** combat.MEM_SLOTS };
    g.hero.quick = .{};
    g.hero.quiver = .{};
    g.hero.worn = .{};

    g.hero.flasks = .{};
    g.day = .{};
    dropRunHud(g);
    leavePlace(g);
    g.counter = .{};
    g.counterT = 0;
    g.counterNpc = null;
    g.bag = .{};
    g.award = .{};
    for (STARTING_KIT) |k| {
        g.bag.add(k, 1);
        g.award.markKnown(k);
    }
    g.tree = .{};
    applyTree(g);
    g.hero.respawnNow();
    seedChart(g);
    g.bossBits = NO_BOSSES;
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
    seedChart(g);
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

/// A SLOT ONLY EVER DESCRIBES THE START MAP: `savemod.readFrom` refuses a file whose `map:` differs, so wiring `Enter.map` up without giving this the map actually loaded writes a save labelled with one map and holding another's hero position.
fn saveMap(g: *const Game) []const u8 {
    _ = g;
    return worldfmt.startMap();
}

comptime {
    if (BOSS_RAILS.len > savemod.BOSS_RAILS) @compileError("game: more boss rails than the save file has rows for");
}

/// A RAIL ONLY EVER GAINS A BIT, AND THE RUN'S START IS WHAT CLEARS IT (`beginGame`). The bonfire empties every group (`clearFoes`) BEFORE `saveNow`, so re-derived off the live bodies a killed knight was written back alive.
fn snapRail(bits: *savemod.BossBits, i: usize, bodies: anytype) void {
    for (bodies, 0..) |*k, j| {
        if (j < worldfmt.MAX_PER_KIND and k.vit.dead) bits[i][j] = true;
    }
}

fn applyRail(bits: *const savemod.BossBits, i: usize, bodies: anytype) void {
    for (bodies, 0..) |*k, j| {
        if (j < worldfmt.MAX_PER_KIND and bits[i][j]) k.markSlain();
    }
}

fn snapBosses(g: *Game) void {
    inline for (BOSS_RAILS, 0..) |row, i| snapRail(&g.bossBits, i, @field(g, row.field).liveConst());
}

fn applyBosses(g: *Game) void {
    inline for (BOSS_RAILS, 0..) |row, i| applyRail(&g.bossBits, i, @field(g, row.field).live());
}

test "A BOSS THE BONFIRE CLEARED IS STILL DOWN — the rail ACCUMULATES, it is never re-derived off the bodies" {
    var bits: savemod.BossBits = NO_BOSSES;
    var slain = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var standing = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    slain.markSlain();
    const pair = [_]*const knightmod.Knight{ &slain, &standing };
    for (pair, 0..) |k, j| {
        if (k.vit.dead) bits[0][j] = true;
    }
    try std.testing.expect(bits[0][0] and !bits[0][1]);

    snapRail(&bits, 0, &[_]knightmod.Knight{});
    try std.testing.expect(bits[0][0]);

    var fresh = [_]knightmod.Knight{knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3)};
    snapRail(&bits, 0, fresh[0..]);
    try std.testing.expect(bits[0][0]);
    applyRail(&bits, 0, fresh[0..]);
    try std.testing.expect(fresh[0].vit.dead);
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
        .seenMap = &g.seenMap,
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

fn aggroRing(comptime M: type) *const fn () f32 {
    return struct {
        fn f() f32 {
            return M.AGGRO_R;
        }
    }.f;
}

const FoeGroup = struct {
    field: []const u8,
    kind: ?FoeKind,
    aggro: *const fn () f32,
    vsHero: bool = true,
    vs: []const []const u8 = &.{},
};
pub const FOE_GROUPS = [_]FoeGroup{
    .{ .field = "warren", .kind = .toad, .aggro = aggroRing(frogmod), .vs = &.{"herd"} },
    .{ .field = "line", .kind = .archer, .aggro = aggroRing(archermod), .vs = &.{"warren"} },
    .{ .field = "grief", .kind = .ogre, .aggro = aggroRing(ogremod), .vsHero = false },
    .{ .field = "band", .kind = null, .aggro = aggroRing(koboldmod) },
    .{ .field = "brood", .kind = null, .aggro = aggroRing(broodmod) },
    .{ .field = "muster", .kind = null, .aggro = aggroRing(warriormod), .vs = &.{"line"} },
    .{ .field = "haunt", .kind = null, .aggro = aggroRing(shademod), .vs = &.{ "warren", "line", "muster" } },
    .{ .field = "swarm", .kind = .leechfly, .aggro = aggroRing(leechmod) },
    .{ .field = "grove", .kind = .rooted, .aggro = aggroRing(rootedmod), .vsHero = false },
    .{ .field = "cluster", .kind = .shroom, .aggro = aggroRing(shroommod), .vs = &.{"herd"} },
    .{ .field = "warrens", .kind = .delver, .aggro = aggroRing(delvermod) },
    .{ .field = "rite", .kind = .necromancer, .aggro = aggroRing(necromod), .vs = &.{ "line", "muster" } },
    .{ .field = "herd", .kind = .fungal_deer, .aggro = aggroRing(deermod) },
    .{ .field = "ring", .kind = .mushroom_mage, .aggro = aggroRing(magemod) },
    .{ .field = "host", .kind = .spore_golem, .aggro = aggroRing(golemmod) },
    .{ .field = "marsh", .kind = .fen_lurker, .aggro = aggroRing(fenmod), .vsHero = false },
    .{ .field = "clatter", .kind = .bone_skitterer, .aggro = aggroRing(skittermod), .vs = &.{ "crypt", "belfry" } },
    .{ .field = "crypt", .kind = .ancient_priest, .aggro = aggroRing(priestmod) },
    .{ .field = "belfry", .kind = .tolling_hollow, .aggro = aggroRing(hollowmod) },
    .{ .field = "bed", .kind = .slumber_bloom, .aggro = aggroRing(bloommod), .vsHero = false },
    .{ .field = "scorch", .kind = .cinder_wake, .aggro = aggroRing(cindermod) },
    .{ .field = "gorge", .kind = .rotgorger, .aggro = aggroRing(gorgermod) },
    .{ .field = "stand", .kind = .birchwight, .aggro = aggroRing(birchmod) },
    .{ .field = "pan", .kind = .salt_husk, .aggro = aggroRing(huskmod) },
    .{ .field = "shoal", .kind = null, .aggro = aggroRing(fishmod) },
    .{ .field = "roost", .kind = .blinkbat, .aggro = aggroRing(batmod) },
    .{ .field = "perch", .kind = .owlbear, .aggro = aggroRing(owlbearmod) },
    .{ .field = "coven", .kind = .druidess, .aggro = aggroRing(druidmod), .vs = &WAVE_FIELDS },
    .{ .field = "hoard", .kind = .bone_mimic, .aggro = aggroRing(mimicmod) },
    .{ .field = "drove", .kind = .mastodon, .aggro = aggroRing(mastodonmod), .vsHero = false, .vs = &.{ "warren", "line", "band" } },
    .{ .field = "vigil", .kind = .bone_knight, .aggro = aggroRing(knightmod), .vsHero = false, .vs = &.{ "line", "muster" } },
    .{ .field = "vanguard", .kind = .fungal_swordsman, .aggro = aggroRing(duomod), .vs = &.{ "cluster", "ring" } },
    .{ .field = "conclave", .kind = .fungal_magus, .aggro = aggroRing(duomod), .vs = &.{ "cluster", "ring" } },
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

const NO_PARRY = [_]struct { field: []const u8, why: []const u8 }{
    .{ .field = "cluster", .why = "the sporeling FLINGS ITSELF — a leap, and its cloud is not a blow at all" },
    .{ .field = "rite", .why = "the necromancer never melees" },
    .{ .field = "ring", .why = "the mushroom mage lobs, and a bouncing fireball is answered sideways" },
    .{ .field = "host", .why = "a disc at your feet, a leap-slam that throws you, and a thrown sac: no strokes" },
    .{ .field = "crypt", .why = "the ancient priest never melees; the breath is a cone you walk out of" },
    .{ .field = "bed", .why = "the slumber bloom has no blow at all — the gas is a ring you walk out of" },
    .{ .field = "conclave", .why = "the fungal magus never melees; the orbs and the bunches are not strokes" },
    .{ .field = "coven", .why = "the druidess never melees; the vines are things on the ground you walk out of, and the spear is a line you step off" },
};

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

test "EVERY FOE_GROUPS ROW IS ACTUALLY UPDATED BY `run` — a row nothing drives is a creature standing still" {
    const src = try worldfmt.readForTest(std.testing.allocator, "src/game.zig", 1 << 22);
    defer std.testing.allocator.free(src);
    var missing: usize = 0;
    inline for (FOE_GROUPS) |gr| {
        const byGroup = "g." ++ gr.field ++ ".update(";
        const byBody = "g." ++ gr.field ++ ".live()";
        if (std.mem.indexOf(u8, src, byGroup) == null and std.mem.indexOf(u8, src, byBody) == null) {
            std.debug.print("  FOE_GROUPS row `{s}` is never driven by run — no `{s}` and no `{s}` in game.zig\n", .{ gr.field, byGroup, byBody });
            missing += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), missing);
    std.debug.print("\n  all {d} foe groups are driven from run\n", .{FOE_GROUPS.len});
}

/// Seated by a call that writes the WHOLE struct rather than by a plain `g.<field> =`, with the call named so the next reader can check it still does that.
const SEATED_BY = [_]struct { field: []const u8, by: []const u8 }{
    .{ .field = "trig", .by = "armScript -> trigger.Runtime.arm, which opens with `self.* = .{}`" },
};

comptime {
    for (SEATED_BY) |row| {
        if (!@hasField(Game, row.field)) @compileError("game: SEATED_BY names `" ++ row.field ++ "`, which is not a Game field");
    }
}

test "EVERY DEFAULTED FIELD ON `Game` IS ASSIGNED — `= .{}` never runs on an `alloc.create`" {
    // It has bitten twice: `pack.n` came up as the fill byte, and `g.day` was never assigned (rate 0 is a held clock, and a NaN hour renders as the anchor hour).
    const src = try worldfmt.readForTest(std.testing.allocator, "src/game.zig", 1 << 22);
    defer std.testing.allocator.free(src);
    var defaulted: usize = 0;
    var missing: usize = 0;
    inline for (@typeInfo(Game).@"struct".fields) |f| {
        if (f.default_value_ptr != null) {
            defaulted += 1;
            const plain = "g." ++ f.name ++ " =";
            const indexed = "g." ++ f.name ++ "[";
            var seated = std.mem.indexOf(u8, src, plain) != null or std.mem.indexOf(u8, src, indexed) != null;
            for (SEATED_BY) |row| {
                if (std.mem.eql(u8, row.field, f.name)) seated = true;
            }
            if (!seated) {
                std.debug.print("\n  `Game.{s}` has a default and nothing in game.zig assigns it — it comes up as the fill byte\n", .{f.name});
                missing += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), missing);
    std.debug.print("\n  {d} of Game's {d} fields carry a default, all assigned — {d} through a call ({s})\n", .{
        defaulted,
        @typeInfo(Game).@"struct".fields.len,
        SEATED_BY.len,
        SEATED_BY[0].by,
    });
}

test "A UNIT WALKS ITS ORDERS — every creature that takes them, not just the one it was written on" {
    const dt: f32 = 1.0 / 60.0;
    const home = mathx.ground(0, 0);
    const AT_POST: f32 = 2.0;
    var worst: f32 = 1e9;
    var worstName: []const u8 = "";
    var homiest: f32 = 0;
    var homiestName: []const u8 = "";
    std.debug.print("\n", .{});
    inline for (FOE_GROUPS) |gr| {
        const T = memberOf(gr.field);
        if (comptime @hasField(T, "post")) {
            const far = mathx.ground(0, gr.aggro() * 6);
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
    try std.testing.expect(homiest < 0.35);
}

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
        const ring = gr.aggro();
        for (@field(g, gr.field).liveConst()) |*f| {
            if (foeFights(f, g.hero.pos, ring)) return true;
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
    try std.testing.expect(i - landings - airborne <= 2);
    try std.testing.expectEqual(@as(u32, 1), landings);
}

test "EVERY GROUP HOLDS EVERYTHING THE MAP CAN PLACE — the per-kind limit is gone, not raised" {
    var total: usize = 0;
    inline for (FOE_GROUPS) |gr| {
        try std.testing.expect(comptime groupCap(gr.field) >= worldfmt.MAX_FOES);
        total += @sizeOf(@FieldType(Game, gr.field));
    }
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
    try std.testing.expectEqual(@as(usize, 2), bombs);
    try std.testing.expect(detonates(.emberball) and detonates(.rock));
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

test "THE AIM IS THE OFF HAND'S AND THE LOOSE IS THE WEAPON HAND'S — a bow holds both, and they may not share a button" {
    const none = HandIn{ .press1 = false, .press2 = false, .held1 = false, .held2 = false };
    var right = Acts{};
    handActs(.bow, .{ .press1 = false, .press2 = true, .held1 = false, .held2 = true }, &right);
    try std.testing.expect(right.aimed and !right.aim);

    inline for (.{ "held1", "held2" }) |f| {
        var in = none;
        @field(in, f) = true;
        var a = Acts{};
        skillActs(.bow, in, &a);
        try std.testing.expect(a.aim and !a.aimed and !a.quick);
    }

    var quick = Acts{};
    handActs(.bow, .{ .press1 = true, .press2 = false, .held1 = true, .held2 = false }, &quick);
    try std.testing.expect(quick.quick and !quick.aimed);

    inline for (@typeInfo(heromod.Armament).@"enum".fields) |f| {
        const a: heromod.Armament = @enumFromInt(f.value);
        var out = Acts{};
        skillActs(a, .{ .press1 = true, .press2 = true, .held1 = true, .held2 = true }, &out);
        if (!heromod.armTwoHanded(a)) try std.testing.expect(!out.aim);
        try std.testing.expect(!out.light and !out.heavy and !out.quick and !out.aimed and !out.guard and !out.parry);
    }
}

test "ONE BUTTON, ONE ORDER — and the enum's own order is what the press goes through" {
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(Reach.souls));
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.talk));
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.chest));
    inline for (@typeInfo(Reach).@"enum".fields) |f| _ = @as(Reach, @enumFromInt(f.value)).prompt();
}

test "the ranges the fight is judged at are each GROUP'S OWN, never one figure for the field" {
    try std.testing.expect(frogmod.AGGRO_R < archermod.AGGRO_R);
    inline for (FOE_GROUPS) |gr| try std.testing.expect(gr.aggro() > 0);
}

const Sighted = enum { blind, seen };

fn rehomeFoes(g: *Game, sighted: Sighted) void {
    g.env.openWards();
    foemod.clearTurned();
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

fn foePlacementStamp(m: *const worldfmt.Map) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(std.mem.asBytes(&m.nfoes));
    for (m.foes[0..m.nfoes]) |f| {
        h.update(std.mem.asBytes(&f));
        const y = m.heightAt(f.x, f.z);
        h.update(std.mem.asBytes(&y));
    }
    h.update(std.mem.asBytes(&foestat.mult));
    return h.final();
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

var frameWasPos: [FOE_GROUPS.len][FOE_CAP]rl.Vector3 = undefined;

comptime {
    for (FOE_GROUPS) |f| {
        if (groupCap(f.field) < worldfmt.MAX_PER_KIND) {
            @compileError("game: foe group '" ++ f.field ++ "' is narrower than worldfmt.MAX_PER_KIND — " ++
                "a map that places more than it holds loses the difference without a word");
        }
    }
    for (FOE_GROUPS) |f| {
        if (!@hasField(objviewmod.CharSet, f.field)) {
            @compileError("game: FOE_GROUPS row '" ++ f.field ++ "' has no objview.CharSet field of that name");
        }
        if (@FieldType(objviewmod.CharSet, f.field) != @FieldType(Game, f.field)) {
            @compileError("game: FOE_GROUPS row '" ++ f.field ++ "' is a different group in objview.CharSet");
        }
    }
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
            const sp = if (sprint) heromod.SPRINT_SPEED else s.mag * heromod.RUN_SPEED;
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
        const sp: f32 = if (sprint) heromod.SPRINT_SPEED else heromod.RUN_SPEED;
        return .{ .fx = kx, .fz = kz, .speed = sp };
    }
    return .{};
}

fn sprintingMove(mv: Move) bool {
    return mv.speed > heromod.RUN_SPEED + 0.01 and (mv.fx * mv.fx + mv.fz * mv.fz) > 1e-6;
}

/// The knee on the H=1.8 rig (0.278·H).
const WADE_KNEE: f32 = 0.50;
const WADE_DEEP: f32 = envmod.WADE_MAX;
const WADE_SLOWEST: f32 = 0.8;

/// HE STARTS WITH NOTHING BUT WHAT IS IN HIS HANDS: every scroll was granted here, so a fresh run opened the book already holding the whole spell list.
const STARTING_KIT = [_]item.Kind{};

comptime {
    std.debug.assert(@abs(envmod.WADE_MAX - 0.760 * heromod.H) < 0.005);
    std.debug.assert(envmod.HERO_R_PIN == foemod.HERO_R);
}

const BOSS_RAILS = [_]struct { field: []const u8, kind: FoeKind }{
    .{ .field = "vigil", .kind = .bone_knight },
    .{ .field = "vanguard", .kind = .fungal_swordsman },
    .{ .field = "conclave", .kind = .fungal_magus },
    .{ .field = "coven", .kind = .druidess },
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

    try std.testing.expectEqual(@as(?bool, false), gateEntered(e, m, .fungal_swordsman));
    try std.testing.expectEqual(@as(?bool, false), gateEntered(e, m, .fungal_magus));
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

    const inside = mathx.ground(4, 4);
    const blinked = holdInRoom(m, &shut, inside, mathx.ground(60, 4), R);
    try std.testing.expect(m.arenas[0].contains(blinked.x, blinked.z));
    try std.testing.expectApproxEqAbs(@as(f32, 20.0 - R), blinked.x, 1e-4);

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
        const gated = gateEntered(&g.env, &g.map, row.kind) orelse true;
        const ring = aggroOfRail(i);
        for (if (gated) @field(g, row.field).liveConst() else &.{}) |*k| {
            if (!k.alive()) continue;
            if (!(sealed or k.leash.roused() or mathx.distXZ(k.pos, g.hero.pos) <= ring)) continue;
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

fn aggroOfRail(comptime i: usize) f32 {
    var out: f32 = 0;
    inline for (FOE_GROUPS) |gr| {
        if (comptime std.mem.eql(u8, gr.field, BOSS_RAILS[i].field)) out = gr.aggro();
    }
    return out;
}

fn wadeDrag(g: *const Game) f32 {
    return wadeDragAt(g.env.wadeDepth(g.hero.pos.x, g.hero.pos.z));
}

test "wading costs the run first and never roots him" {
    try std.testing.expectEqual(@as(f32, 1.0), wadeDragAt(0.2));
    try std.testing.expect(wadeDragAt(WADE_DEEP) * heromod.WALK_SPEED < heromod.WALK_SPEED);
    try std.testing.expect(wadeDragAt(WADE_DEEP * 3) * heromod.WALK_SPEED > 0.1);
    try std.testing.expect(wadeDragAt(0.7) > wadeDragAt(0.9));
}

fn wadeDragAt(d: f32) f32 {
    if (d <= WADE_KNEE) return 1.0;
    return mathx.lerpF(1.0, WADE_SLOWEST, mathx.smoothstep(WADE_KNEE, WADE_DEEP, d));
}

const Mark = struct { swing: f32, out: f32, lo: f32, hi: f32 };

fn markSwing(f: anytype, hero: rl.Vector3) Mark {
    return markSwingAt(f, hero, 0);
}

fn markSwingAt(f: anytype, hero: rl.Vector3, part: u8) Mark {
    var m = Mark{ .swing = 0, .out = 0, .lo = 1e9, .hi = -1e9 };
    var i: u32 = 0;
    while (i < 300) : (i += 1) {
        _ = f.update(1.0 / 60.0, hero, PLAY_HALF, .{});
        const at = lockPointOf(f, part);
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

test "EVERY OTHER POINT A BODY OFFERS RIDES IT THE SAME WAY — the ogre's head and the hollow's rider" {
    const hero = v3(0, 0, 1.7);
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    var belled = hollowmod.Hollow.spawn(mathx.zero3, 0, 1.0, 0.3);
    inline for (.{ .{ "ogre head", &giant }, .{ "hollow rider", &belled } }) |row| {
        try std.testing.expectEqual(@as(u8, 2), partsOf(row[1]));
        const m = markSwingAt(row[1], hero, 1);
        std.debug.print("\n  {s}: point swings {d:.2} m, sits {d:.2}..{d:.2} m up, worst {d:.2} m out of the standing box", .{ row[0], m.swing, m.lo, m.hi, m.out });
        try std.testing.expect(m.swing > 0.02);
        try std.testing.expect(m.out <= 0.60);
    }
    std.debug.print("\n", .{});
    var plain = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(@as(u8, 1), partsOf(&plain));
    try std.testing.expectEqual(plain.lockPoint(), lockPointOf(&plain, 0));
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
    try std.testing.expect(heromod.SPRINT_SPEED * heromod.JUMP_AIR > heromod.ROLL_DIST);
    // A painted face on the default lattice is a wall to the jump too: his feet plus the walk's allowance stop under the least drop that cuts.
    const step = 2.0 * worldfmt.DEFAULT_HALF / @as(f32, @floatFromInt(worldfmt.HEIGHT_N - 1));
    std.debug.print("\n  jump reach {d:.2} m against the least cut {d:.2} m; melee reach refused over {d:.2} m\n", .{ heromod.JUMP_APEX + envmod.STEP_UP, worldfmt.cliffMinDrop(step), foemod.REACH_RISE });
    try std.testing.expect(heromod.JUMP_APEX + envmod.STEP_UP < worldfmt.cliffMinDrop(step));
    try std.testing.expect(foemod.REACH_RISE < worldfmt.cliffMinDrop(step));
    try std.testing.expect(foemod.REACH_RISE > heromod.JUMP_APEX);
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

fn heroFooting(g: *Game, was_: rl.Vector3) void {
    const h = &g.hero;
    if (h.onLadder() or h.dead) {
        g.heroDeck = null;
        return;
    }
    const under = g.env.standAt(h.pos.x, h.pos.z, h.footY());
    if (g.heroDeck) |was| {
        if (!h.airborne() and under < was - envmod.STEP_UP) h.startFall(was, mathx.dirXZ(was_, h.pos), h.speedS);
    } else if (!h.airborne() and under < h.pos.y - envmod.STEP_UP) {
        // The LAND cannot drop this far in one step unless a cliff cut it; a bilinear ramp is bounded by MAX_SLOPE.
        h.startFall(h.pos.y, mathx.dirXZ(was_, h.pos), h.speedS);
    }
    g.heroDeck = if (h.airborne()) null else g.env.deckAt(h.pos.x, h.pos.z, h.pos.y);
}

pub fn envGroundAt(e: *const envmod.Env, x: f32, z: f32) f32 {
    return e.groundAt(x, z);
}

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

fn holdInRoom(m: *const worldfmt.Map, shut: []const bool, was: rl.Vector3, p: rl.Vector3, r: f32) rl.Vector3 {
    const i = m.arenaIndexAt(was.x, was.z) orelse return p;
    if (i >= shut.len or !shut[i]) return p;
    return m.arenas[i].hold(p, r);
}

fn gateTerrain(g: *const Game, foes: anytype, was: []const rl.Vector3, group: ?FoeKind, crossesWards: bool) void {
    const T = @typeInfo(@TypeOf(foes)).pointer.child;
    for (foes, 0..) |*f, i| {
        if (i >= was.len) continue;
        if (comptime @hasDecl(T, "alive")) {
            if (!f.alive()) continue;
        }
        if (mathx.distXZ(was[i], f.pos) < 1e-5) continue;
        if (!crossesWards and g.env.wardCrossed(was[i], f.pos) != null) {
            f.pos.x = was[i].x;
            f.pos.z = was[i].z;
            continue;
        }
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
        if (g.env.brink(was[i], stepped)) {
            const kept = brinkStep(g, was[i], stepped, statureOf(f));
            f.pos.x = kept.x;
            f.pos.z = kept.z;
            continue;
        }
        f.pos.x = stepped.x;
        f.pos.z = stepped.z;
    }
}

const DROP_FRAC: f32 = 0.7;

/// A BRINK IS PACED, NOT STOOD AT: the step's share toward the drop is removed and the rest taken along the lip. A body may CHOOSE the drop when it is short against its own stature and the hero stands below it — a position read.
fn brinkStep(g: *const Game, was: rl.Vector3, to: rl.Vector3, stature: f32) rl.Vector3 {
    // Off `standAt`, the surface `brink` itself measured: read off the LAND, a body on a deck weighs its own drop against the ground under the deck.
    const gFrom = g.env.standAt(was.x, was.z, was.y);
    const gTo = g.env.standAt(to.x, to.z, was.y);
    const drop = gFrom - gTo;
    if (drop <= DROP_FRAC * stature and g.hero.pos.y < gFrom - drop * 0.5) return to;
    const gr = g.env.gradAt((was.x + to.x) * 0.5, (was.z + to.z) * 0.5);
    const gl = @sqrt(gr[0] * gr[0] + gr[1] * gr[1]);
    if (gl < 1e-5) return was;
    const ux = -gr[0] / gl;
    const uz = -gr[1] / gl;
    const dx = to.x - was.x;
    const dz = to.z - was.z;
    const along = dx * ux + dz * uz;
    if (along <= 0) return was;
    const tx = dx - ux * along;
    const tz = dz - uz * along;
    const d = @sqrt(dx * dx + dz * dz);
    const tl = @sqrt(tx * tx + tz * tz);
    if (tl < 1e-5) return was;
    const slid = v3(was.x + tx / tl * d, was.y, was.z + tz / tl * d);
    if (g.env.brink(was, slid)) return was;
    return slid;
}

fn bodyRadiusOf(f: anytype) f32 {
    const T = std.meta.Child(@TypeOf(f));
    if (comptime @hasDecl(T, "bodyR")) return @max(f.bodyR(), 0.1);
    return HERO_R;
}

fn statureOf(f: anytype) f32 {
    const T = std.meta.Child(@TypeOf(f));
    if (comptime @hasDecl(T, "stature")) return @max(f.stature(), 0.2);
    return @max(f.topWorld().y - f.pos.y, 0.2);
}

fn gateHeroTerrain(g: *Game, was: rl.Vector3) void {
    if (g.env.wardRefusing(was, g.hero.pos, if (g.gateWalk) |gw| gw.ward else null) != null) {
        g.hero.pos.x = was.x;
        g.hero.pos.z = was.z;
        return;
    }
    const out = gatedXZ(&g.env, was, g.hero.pos, g.hero.airborne());
    g.hero.pos.x = out.x;
    g.hero.pos.z = out.z;
    const room = holdInRoom(&g.map, &g.arenaShut, was, g.hero.pos, HERO_R);
    g.hero.pos.x = room.x;
    g.hero.pos.z = room.z;
    markWardStep(g, was);
    g.seenMap.walked(heroEye(g), g.map.half, &g.env);
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
    try worldfmt.loadForTest(worldfmt.DIR ++ "/test_ladder" ++ worldfmt.EXT, m, &ln);
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.adoptHeight(m);
    e.materialize(m);

    const fl = propsmod.WATCH_FLOORS;
    const want = [_]struct { x: f32, z: f32, at: f32 = 0, top: ?f32 }{
        .{ .x = 7.2, .z = 0, .top = 7.00 },
        .{ .x = 7.2, .z = -14, .top = null },
        .{ .x = -29.8, .z = 20, .top = 3.00 },
        .{ .x = -29.8, .z = 26, .top = null },
        .{ .x = -20, .z = 1.4, .top = fl[0] },
        .{ .x = -20, .z = -1.4, .at = fl[0], .top = fl[1] },
        .{ .x = -18.6, .z = 0, .at = fl[1], .top = fl[2] },
        .{ .x = -21.4, .z = 0, .at = fl[2], .top = fl[3] },
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
            try std.testing.expect(head - x.y <= envmod.LADDER_PROUD and x.y - head <= envmod.STEP_UP);
            const haul = mantleAt(r, x.y);
            std.debug.print("      hauls from {d:5.2} of {d:5.2} — {d:.2} m of run he no longer rides\n", .{ haul, r.run, r.run - haul });
            try std.testing.expectApproxEqAbs(x.y - MANTLE_RISE, r.foot.y + haul, 0.02);
            try std.testing.expect(haul <= r.run and haul >= r.run - MANTLE_LOOK);
        } else {
            try std.testing.expectEqual(@as(?rl.Vector3, null), exit);
        }
    }
    try std.testing.expectEqual(want.len, found);
}

test "THE ROLL OBEYS THE GROUND — a committed move may not take him up what a walk refuses" {
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightAny = true;
    e.heightHalf = 100.0;
    // One lattice pitch is 2*half/(N-1) ≈ 0.90 m, so the riser is far past `STEP_UP` and its slope far past `MAX_SLOPE` (tan 40).
    const pitch = 2 * e.heightHalf / @as(f32, @floatFromInt(worldfmt.HEIGHT_N - 1));
    for (0..worldfmt.HEIGHT_N) |zi| {
        for (0..worldfmt.HEIGHT_N) |xi| {
            const x = @as(f32, @floatFromInt(xi)) * pitch - e.heightHalf;
            e.heightField[zi * worldfmt.HEIGHT_N + xi] = if (x < 0) worldfmt.HEIGHT_ZERO else worldfmt.HEIGHT_ZERO + 24;
        }
    }
    const rise = e.groundAt(2.0, 0) - e.groundAt(-2.0, 0);
    try std.testing.expect(rise > 4.0);

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

const AIM_FADE: f32 = 0.0;
fn heroFade(g: *const Game) f32 {
    return mathx.lerpF(1.0, AIM_FADE, mathx.clampF(g.hero.aimB, 0, 1));
}

fn shows(g: *const Game, l: editormod.Layer) bool {
    return !g.editor.on or g.editor.visible(l);
}

fn drawCasters(g: *Game, cull: envmod.Cull) void {
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
fn slotBlack(g: *const Game) f32 {
    const dying: f32 = if (g.hero.dead) 1.0 else mathx.clampF(g.deathFade / RESPAWN_FADE, 0, 1);
    return mathx.maxF(g.rest.fade(), dying);
}

pub fn takeSlotShot(g: *Game) void {
    if (!g.shotOwed or slotBlack(g) > SHOT_CLEAR) return;
    g.shotOwed = false;
    _ = savemod.writeShot(g.slot);
}

pub fn drawBonfireForShot(g: *Game) void {
    restmod.drawScreen(&g.rest, restView(g));
}

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
pub fn forceEmberForShot(g: *Game, level: ?f32) void {
    g.emberForce = level;
    g.emberNow = level orelse 0;
}
pub fn forceMistForShot(g: *Game, ahead: f32) void {
    const p = v3(g.hero.pos.x, g.env.groundAt(g.hero.pos.x, g.hero.pos.z), g.hero.pos.z);
    g.mist.stageOne(p, ahead, g.hero.facing);
}
pub fn forceSkeinForShot(g: *Game, across: f32) void {
    g.skein.stageOne(g.hero.pos, g.env.groundAt(g.hero.pos.x, g.hero.pos.z), g.hero.facing + across);
}
pub fn skeinLeadForShot(g: *const Game) rl.Vector3 {
    return g.skein.leadAt();
}
pub fn openCounterForShot(g: *Game, t: countermod.Trade) void {
    g.counter.begin(t);
    g.counterT = counterui.RAISE;
    g.folk.update(SHOT_STEP, g.hero.pos, PLAY_HALF);
    g.counterNpc = g.talk.npc orelse g.folk.near orelse (if (g.folk.n > 0) @as(?usize, 0) else null);
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

pub fn counterPortrait(g: *Game) ?dialogmod.Portrait {
    const i = g.counterNpc orelse return null;
    const p = g.folk.at(i) orelse return null;
    return .{
        .scene = &g.scene,
        .face = p.facePoint(),
        .facing = p.facing,
        .ctx = @ptrCast(g),
        .drawFn = drawCounterNpc,
    };
}

fn drawCounterNpc(ctx: *const anyopaque) void {
    const g: *const Game = @ptrCast(@alignCast(ctx));
    const i = g.counterNpc orelse return;
    g.folk.drawOne(i);
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
    mimic,
    chest,
    ladder,
    gate,

    fn prompt(self: Reach) hud_.Hint {
        return .{ .glyph = .{ .face = hud_.BTN_INTERACT }, .label = switch (self) {
            .souls => "Reclaim",
            .rest => "Rest",
            .pickup => "Take",
            .talk => "Speak",
            // THE SAME WORD AS THE CHEST'S, or the prompt is the tell.
            .mimic, .chest => "Open",
            .ladder => "Climb",
            .gate => "Enter",
        } };
    }
};

const REACH_RISE: f32 = 2.0 * envmod.STEP_UP;
comptime {
    std.debug.assert(REACH_RISE < propsmod.WATCH_FLOORS[0]);
}

fn onSameFloor(deck: ?f32, thingY: f32) bool {
    const d = deck orelse return true;
    return @abs(thingY - d) <= REACH_RISE;
}

fn atHisLevel(g: *const Game, y: f32) bool {
    return onSameFloor(g.heroDeck, y);
}

test "A REACH IS REFUSED THROUGH A FLOOR, AND NEVER REFUSED ACROSS THE LAND" {
    const floor = propsmod.WATCH_FLOORS[0];
    const roof = propsmod.WATCH_FLOORS[propsmod.WATCH_FLOORS.len - 1];
    try std.testing.expect(onSameFloor(null, 0));
    try std.testing.expect(onSameFloor(null, -40));
    try std.testing.expect(onSameFloor(null, roof));
    try std.testing.expect(onSameFloor(roof, roof));
    try std.testing.expect(onSameFloor(roof, roof + envmod.STEP_UP));
    try std.testing.expect(!onSameFloor(roof, 0));
    try std.testing.expect(!onSameFloor(roof, floor));
    try std.testing.expect(!onSameFloor(floor, 0));

    const m = try std.testing.allocator.create(worldfmt.Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    try worldfmt.loadForTest(worldfmt.START_MAP, m, &ln);
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.adoptHeight(m);
    e.materialize(m);

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
        .mimic => if (g.hoard.near) |i| atHisLevel(g, g.hoard.band[i].pos.y) else false,
        .chest => if (g.chests.near) |i| atHisLevel(g, g.chests.list[i].pos.y) else false,
        .ladder => ladderAt(g) != null,
        .gate => gateAt(g) != null,
    };
}

const GATE_MARGIN: f32 = 1.15;
comptime {
    std.debug.assert(envmod.WARD_CLEAR > GATE_MARGIN);
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
        .mimic => _ = g.hoard.wakeNear(),
        .chest => openChest(g),
        .ladder => mountLadder(g),
        .gate => enterGate(g),
    }
}

pub const LADDER_REACH: f32 = 1.5;
const LADDER_EXIT: f32 = 1.60;
/// Chest on the 1.8 m rig: where a body stops climbing and gets a knee up instead.
const MANTLE_RISE: f32 = 1.30;
const MANTLE_LOOK: f32 = MANTLE_RISE + envmod.LADDER_PROUD;
const MANTLE_STEP_FROM: f32 = 0.34;

comptime {
    std.debug.assert(MANTLE_STEP_FROM >= 0 and MANTLE_STEP_FROM < heromod.MANTLE_PRESS);
}
/// Metres of run he covers in the beat between one hand-over-hand voice and the next.
const CLIMB_STEP_EVERY: f32 = 0.62;
const LADDER_KNOCK_APEX: f32 = 0.35;

const Climb = struct {
    rung: envmod.Rung,
    axis: rl.Vector3,
    at: f32,
    face: f32,
    beat: f32 = 0,
};

const Mantle = struct {
    from: rl.Vector3,
    to: rl.Vector3,
    face: f32,
    t: f32 = 0,
};

fn syncLensLift(g: *Game) void {
    if (@abs(g.hero.pos.y - g.lensGroundY) > GROUND_SNAP * 0.5) g.rig.lift = liftShare(&g.hero) * g.hero.lift;
    g.lensGroundY = g.hero.pos.y;
}

fn liftShare(h: *const heromod.Hero) f32 {
    if (h.onLadder() or h.lift > heromod.JUMP_APEX) return 1.0;
    return cameramod.LIFT_SHARE;
}

fn ladderAt(g: *const Game) ?envmod.Rung {
    if (g.climb != null or g.mantle != null or g.gateWalk != null or !g.hero.bodyFree()) return null;
    return g.env.ladderNear(g.hero.pos, g.hero.footY(), LADDER_REACH);
}

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

fn leaveLadder(g: *Game) void {
    g.climb = null;
    g.mantle = null;
    g.hero.endClimb();
}

fn leavePlace(g: *Game) void {
    g.gateWalk = null;
    leaveLadder(g);
    g.heroDeck = null;
}

fn footOffLadder(g: *Game) void {
    const c = &(g.climb orelse return);
    const at = c.rung.foot.y;
    g.hero.pos.y = g.env.standAt(c.axis.x, c.axis.z, at);
    g.heroDeck = g.env.deckAt(c.axis.x, c.axis.z, g.hero.pos.y);
    leaveLadder(g);
}

fn dropOffLadder(g: *Game) void {
    if (g.climb == null and g.mantle == null) return;
    const face = g.hero.facing;
    const from = g.hero.footY();
    leaveLadder(g);
    g.hero.startFall(from, mathx.headingDir(face + std.math.pi), heromod.WALK_SPEED);
}

fn knockOffLadder(g: *Game, b: foemod.Blow) void {
    if (g.climb == null and g.mantle == null) return;
    const from = g.hero.footY();
    const away = mathx.dirXZ(b.from, g.hero.pos);
    leaveLadder(g);
    _ = g.hero.launchFrom(away, LADDER_KNOCK_APEX, from);
}

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
        const on = e.standAt(x + out.x * k, z + out.z * k, y);
        if (y - on <= envmod.STEP_UP) return v3(x, y, z);
        if (ledge == null) ledge = v3(x, y, z);
    }
    return ledge;
}

fn tryTopOut(g: *Game, c: *const Climb) bool {
    if (c.at < c.rung.run - MANTLE_LOOK) return false;
    const at = ladderExit(&g.env, c.rung) orelse return false;
    if (c.at < mantleAt(c.rung, at.y)) return false;
    startMantle(g, at);
    return true;
}

fn mantleAt(r: envmod.Rung, lipY: f32) f32 {
    return mathx.clampF(lipY - MANTLE_RISE - r.foot.y, 0, r.run);
}

fn startMantle(g: *Game, to: rl.Vector3) void {
    const c = &(g.climb orelse return);
    const from = v3(g.hero.pos.x, c.rung.foot.y + c.at, g.hero.pos.z);
    const face = c.face;
    const lift = from.y - g.hero.pos.y;
    leaveLadder(g);
    g.mantle = .{ .from = from, .to = to, .face = face };
    g.hero.startMantle(lift, face);
    sfx.playAt(.step_hard, 0.75);
}

fn updateMantle(g: *Game, dt: f32) void {
    const mn = &(g.mantle orelse return);
    mn.t = mathx.minF(mn.t + dt / heromod.MANTLE_DUR, 1.0);
    const up = mathx.smoothstep(0, 1, mathx.minF(mn.t / heromod.MANTLE_PRESS, 1.0));
    const out = mathx.smoothstep(0, 1, mathx.maxF((mn.t - MANTLE_STEP_FROM) / (1.0 - MANTLE_STEP_FROM), 0));
    g.hero.pos.x = mathx.lerpF(mn.from.x, mn.to.x, out);
    g.hero.pos.z = mathx.lerpF(mn.from.z, mn.to.z, out);
    g.hero.facing = mn.face;
    g.hero.tickMantle(dt, mathx.lerpF(mn.from.y, mn.to.y, up) - g.hero.pos.y, mn.t);
    g.hero.pose();
    if (mn.t >= 1.0) finishMantle(g);
}

fn finishMantle(g: *Game) void {
    const at = (g.mantle orelse return).to;
    leaveLadder(g);
    g.hero.pos = at;
    g.heroDeck = g.env.deckAt(at.x, at.z, at.y);
    sfx.play(.land);
}

fn updateClimb(g: *Game, dt: f32, mv: Move) void {
    const c = &(g.climb orelse return);
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
    if (moved > 0 and tryTopOut(g, c)) return;
    if (moved < 0 and c.at <= 1e-4) return footOffLadder(g);
}

pub const GATE_SPEED: f32 = heromod.WALK_SPEED_BANK * 0.66;

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
    g.hero.pose();
    gw.motes += dt * heromod.FOG_WAKE_RATE;
    var n: u32 = 0;
    while (gw.motes >= 1.0 and n < heromod.FOG_WAKE_CAP) : (n += 1) gw.motes -= 1.0;
    if (n > 0) g.hero.fogWake(g.hero.shoulderPoint(), gw.dir, n);
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
        if (w.navWant(g.hero.pos)) |want| markWay(&g.env, &w.nav, w.pos, w.bodyR(), want) else w.nav.dir = null;
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
    g.award.gainCoin(got.gold);
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
        if (item.class(it) == .flask) {
            _ = g.hero.flasks.found();
            g.award.gain(.empty_flask);
            continue;
        }
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
                var buf: [pickupmod.DROP_MAX]item.Kind = undefined;
                const loot = dropsmod.roll(k, self.g.hero.sheet.at(.luck), &self.g.dropRng, &buf);
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

const WARD_FADE: f32 = 2.6;

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
        const standing = worldfmt.sealStanding(seal, &alive);
        const shut = g.env.wardIn[i] and standing and g.env.wardClear(@intCast(i), g.hero.pos, HERO_R);
        if (shut and !g.env.wardShut[i]) sfx.play(.fog_seal);
        g.env.wardShut[i] = shut;
        if (g.env.wardIn[i] and seal.len > 0 and !standing) {
            if (g.env.wardLife[i] >= 1.0) sfx.play(.fog_felled);
            g.env.wardLife[i] = mathx.maxF(0, g.env.wardLife[i] - dt / WARD_FADE);
        }
        pr.shrink = g.env.wardLife[i];
        pr.gone = g.env.wardLife[i] <= 0;
    }
}

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

fn voiceFolk(g: *Game) void {
    for (g.folk.live()) |*p| {
        if (!p.struck) continue;
        const ear = v3(g.hero.pos.x, g.hero.pos.y + foemod.HERO_EYE, g.hero.pos.z);
        const anvil = v3(p.pos.x, p.pos.y + ANVIL_EAR, p.pos.z);
        sfx.worldThrough(.smith_ring, p.pos, 1.0, if (g.env.sees(ear, anvil)) 1.0 else 0.0);
    }
}

const ANVIL_EAR: f32 = propsmod.info(.anvil).top;

test "A CLIFF TURNS THE ANVIL INTO A HINT — the ring carries in the open and is muffled through rock" {
    const m = try worldfmt.testMap(std.testing.allocator, worldfmt.TEST_HEAD ++ "at: cliff 18 0 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(envmod.Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);

    const ear = v3(0, foemod.HERO_EYE, 0);
    // The cliff's colliders are its five lobes, 10.4 m across the run (`props.partsOf`).
    const behindTheCliff = v3(34, ANVIL_EAR, 0);
    const sameSide = v3(3, ANVIL_EAR, 0);
    try std.testing.expect(!e.sees(ear, behindTheCliff));
    try std.testing.expect(e.sees(ear, sameSide));
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
    if (g.hero.dead or g.gateWalk != null or g.climb != null or g.mantle != null) return;
    g.counter.begin(trade);
    g.counterT = 0;
    g.counterNpc = g.talk.npc orelse g.folk.near;
    g.hero.held = true;
    sfx.play(.flask_cycle);
}

fn tickCounter(g: *Game, dt: f32) void {
    g.counterT += dt;
    var rowBuf: [countermod.MAX_ROWS]countermod.Row = undefined;
    const len = g.counter.rows(&g.hero, &g.bag, &rowBuf).len;
    if (navPressed(.up)) {
        g.counter.move(-1, len);
        if (len > 1) sfx.play(.menu_move);
    }
    if (navPressed(.down)) {
        g.counter.move(1, len);
        if (len > 1) sfx.play(.menu_move);
    }
    if (confirmPressed()) {
        g.counter.take(&g.hero, &g.bag);
        if (countermod.Counter.refused(g.counter.said)) {
            sfx.play(.refused);
        } else switch (g.counter.said) {
            .bought, .sold => sfx.play(.item_get),
            .forged => sfx.play(.smith_ring),
            else => {},
        }
    }
    if (g.counter.trade == .shop and (rl.isKeyPressed(.q) or padPressed(hud_.padOf(hud_.BTN_QUICK)))) {
        g.counter.selling = !g.counter.selling;
        g.counter.sel = 0;
        g.counter.said = .none;
        sfx.play(.menu_pick);
    }
    if (rl.isKeyPressed(.escape) or padPressed(hud_.padOf(hud_.BTN_BACK))) {
        g.counter.close();
        g.hero.held = false;
        sfx.play(.menu_back);
    }
    g.hero.gold.tick(dt);
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
const PARRY_KEY: rl.KeyboardKey = .c;
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
        g.hero.setSpawn(at, s.facing);
        saveNow(g, .withShot);
    }
    if (g.rest.justLeft) {
        g.retro.values = g.restRetro;
        g.hero.sit(false, g.hero.pos, g.hero.facing);
        rehomeFoes(g, .blind);
        applyBosses(g);
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
    return .{ .tree = &g.tree, .souls = g.hero.souls.total, .mem = &g.hero.mem, .bag = &g.bag, .flasks = &g.hero.flasks };
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
        .allot => |n| {
            g.hero.flasks.allot(n);
            g.rest.screen = .list;
        },
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

fn bankTint(g: *const Game) rl.Color {
    return weathermod.bankTint(daynight.mistTint(g.day.hour, g.wetNow), g.sporeNow, g.emberNow);
}

fn applyStow(g: *Game) void {
    g.env.stowed = g.hero.resting;
}

fn applyHour(g: *Game) void {
    const wet = @round(g.wetNow * WET_STEPS) / WET_STEPS;
    const fog = hazeK(g);
    const spore = @round(g.sporeNow * WET_STEPS) / WET_STEPS;
    const ember = @round(g.emberNow * WET_STEPS) / WET_STEPS;
    if (g.day.hour == g.hourLit and wet == g.wetLit and fog == g.fogLit and spore == g.sporeLit and ember == g.emberLit) return;
    g.hourLit = g.day.hour;
    g.wetLit = wet;
    g.fogLit = fog;
    g.sporeLit = spore;
    g.emberLit = ember;
    g.scene.setHour(g.day.hour, wet, fog, spore, ember);
    g.sky.setHour(g.day.hour, wet, spore, ember);
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

pub fn pinSkyForShot(g: *Game) void {
    const here = g.map.weatherAt(g.hero.pos.x, g.hero.pos.z);
    g.wetNow = mathx.clampF(if (here) |l| l.wet orelse g.weather.rain() else g.weather.rain(), 0, 1);
    g.fogNow = mathx.clampF(if (here) |l| l.fog orelse 0 else 0, 0, 1);
    g.sporeNow = mathx.clampF(if (here) |l| l.spore orelse 0 else 0, 0, 1);
    g.emberNow = mathx.clampF(g.emberForce orelse (if (here) |l| l.ember orelse 0 else 0), 0, 1);
    if (g.sporeNow > weathermod.MIST_MIN or g.emberNow > weathermod.MIST_MIN) {
        g.mist.tick(SHOT_SETTLE, g.hero.pos, g.env.groundAt(g.hero.pos.x, g.hero.pos.z), fogAmt(g));
    }
    applyHour(g);
}

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

const WHISPER_R: f32 = 1.1;

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


const STRIKE_RISE: f32 = 1.7;
const STRIKE_LEAN: f32 = 0.9;
const STRIKE_R: f32 = 0.30;

fn strikeSegment(g: *const Game, at: rl.Vector3, topY: f32) [2]rl.Vector3 {
    var away = mathx.dirXZ(g.hero.pos, at);
    if (mathx.lenXZ(away) < 1e-4) away = mathx.headingDir(g.hero.facing);
    return .{ v3(at.x - away.x * STRIKE_LEAN, topY + STRIKE_RISE, at.z - away.z * STRIKE_LEAN), at };
}

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
            if (@abs(a.pos.y - g.hero.pos.y) > foemod.REACH_RISE) continue;
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
    g.hero.siphonDrain(hit.at, g.hero.casts);
    _ = g.hero.drinkSiphon(hit.took * combat.SIPHON_SHARE);
}

/// THE ONE PLACE THE COLD TAKES THE FEET — a post-step gate over the whole frame's travel, like the terrain's beside it. A mover that scales its own step by `CHILL_TRAVEL` as well bills the hold twice.
fn gateChill(foes: anytype, was: []const rl.Vector3) void {
    const T = @typeInfo(@TypeOf(foes)).pointer.child;
    if (comptime !@hasField(T, "chill")) return;
    for (foes, 0..) |*f, i| {
        if (i >= was.len or !f.chill.held()) continue;
        // A BLINK IS NOT TRAVEL, so the ones that WARP say so: the delta is a set and not a step, and scaling it stood the body 45% short of a flank it had already solved.
        if (comptime @hasDecl(T, "warped")) {
            if (f.warped()) continue;
        }
        f.pos.x = was[i].x + (f.pos.x - was[i].x) * combat.CHILL_TRAVEL;
        f.pos.z = was[i].z + (f.pos.z - was[i].z) * combat.CHILL_TRAVEL;
    }
}

test "THE COLD TAKES THE FEET, AND A BLINK HAS NONE — the gate bills a step, never a set" {
    const home = mathx.ground(0, 0);
    var bats = [_]batmod.Bat{ batmod.Bat.spawn(home, 0, 1.0, 0.3), batmod.Bat.spawn(home, 0, 1.0, 0.3) };
    const was = [_]rl.Vector3{ home, home };
    for (&bats) |*b| b.chill.breathe(1.0 / 60.0);
    bats[0].pos = mathx.ground(0, 1.0);
    bats[1].pos = mathx.ground(0, 12.0);
    bats[1].warp = true;
    const live: []batmod.Bat = &bats;
    gateChill(live, was[0..]);
    try std.testing.expectApproxEqAbs(combat.CHILL_TRAVEL, bats[0].pos.z, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), bats[1].pos.z, 1e-4);
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
            if (disguised(f)) continue; // aim may not converge on a body no blade of his reaches
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
            planted(g, ar, true);
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

fn sightR() f32 {
    var widest: f32 = 0;
    inline for (FOE_GROUPS) |f| widest = @max(widest, f.aggro());
    return widest + 1.0;
}

fn heroEye(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, g.hero.pos.y + foemod.HERO_EYE, g.hero.pos.z);
}

fn markSight(g: *Game) void {
    const eye = heroEye(g);
    const reach = sightR();
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            if (!foemod.corporeal(f)) continue;
            if (mathx.distXZ(g.hero.pos, f.pos) > reach) continue;
            if (g.env.sees(f.lockPoint(), eye)) f.leash.noteSeen();
        }
    }
}

const WAY_PROBE: f32 = 2.0;
const WAY_FAN = [_]f32{ 0.45, 0.90, 1.40, 1.95, 2.50 };
const WAY_TRUE: f32 = 0.98;
/// Metres of overlap forgiven: blocked iff the gap closes past `r + s.r - WAY_SLACK`, asked without solving for where the body would end up.
const WAY_SLACK: f32 = 1e-3;

fn wayClear(env: *const envmod.Env, at: rl.Vector3, r: f32, dir: rl.Vector3) bool {
    const reach = WAY_PROBE + r;
    const went = mathx.dirXZ(at, env.walkStep(at, dir, reach));
    if (mathx.lenXZ(went) < 1e-4) return false;
    if (went.x * dir.x + went.z * dir.z < WAY_TRUE) return false;
    for ([2]f32{ 0.5, 1.0 }) |u| {
        const p = v3(at.x + dir.x * reach * u, at.y, at.z + dir.z * reach * u);
        if (env.blockedNear(p, r - WAY_SLACK, r + 1.0)) return false;
    }
    return true;
}

/// The prop grid is all it ever wanted off the `Game`; taking the whole thing kept the most expensive per-frame walk out of a headless test.
fn markWay(env: *const envmod.Env, nav: *foemod.Nav, at: rl.Vector3, r: f32, want: rl.Vector3) void {
    const straight = mathx.dirXZ(at, want);
    if (mathx.lenXZ(straight) < 1e-4 or wayClear(env, at, r, straight)) {
        nav.dir = null;
        return;
    }
    const yaw = mathx.headingXZ(straight);
    for (WAY_FAN) |off| {
        for ([2]f32{ nav.side, -nav.side }) |s| {
            const d = mathx.headingDir(yaw + off * s);
            if (!wayClear(env, at, r, d)) continue;
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
            markWay(&g.env, &f.nav, f.pos, f.bodyR(), want);
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
            f.threat.charmed = f.vit.ailOn(.charm);
            f.threat.confused = f.vit.ailOn(.confusion);
            if (f.threat.charmed or f.threat.confused) {
                if (nearestOther(g, f.pos, TURN_R)) |o| {
                    f.threat.atFoe = o.at;
                    f.threat.distFoe = o.dist;
                    f.threat.hasFoe = true;
                } else {
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

const TURN_R: f32 = 22.0;

const Nearest = struct { at: rl.Vector3, dist: f32 };

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

fn spendTurnedBlows(g: *Game) void {
    const blows = foemod.takeTurned();
    defer foemod.clearTurned();
    for (blows) |b| {
        const at = b.at;
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

const TURNED_R: f32 = 0.45;
const TURNED_SELF: f32 = 0.30;

/// The hour onto every body: its own window (`foe.Win`) and, for the creatures whose BEHAVIOUR turns on the clock, the night itself.
fn markHour(g: *Game) void {
    const day = daynight.dayShare(g.day.hour);
    inline for (FOE_GROUPS) |gr| {
        const M = std.meta.Child(@TypeOf(@field(g, gr.field).live()));
        for (@field(g, gr.field).live()) |*f| {
            const share = foemod.Win.shareOf(f.leash.win.when, day);
            // A FIGHT IN PROGRESS OUTRANKS THE HOUR, as it outranks the tether: a body cannot go unhittable
            // mid-stroke and bill the blow out of nothing.
            f.leash.win.in = if (f.leash.roused()) mathx.maxF(share, foemod.WIN_SOLID) else share;
            if (comptime @hasField(M, "sky")) f.sky.night = 1.0 - day;
        }
    }
}

/// ONLY THE FLAME HE CARRIES. A brazier the map placed is scenery: letting a fixed light hold a camp off would silently retune every encounter standing near one.
fn markGlare(g: *Game) void {
    const flame = g.hero.torchLight();
    inline for (FOE_GROUPS) |gr| {
        const M = std.meta.Child(@TypeOf(@field(g, gr.field).live()));
        if (comptime !@hasField(M, "glare")) continue;
        for (@field(g, gr.field).live()) |*f| {
            const t = flame orelse {
                f.glare = .{ .at = f.pos };
                continue;
            };
            f.glare.k = mathx.clampF(1.0 - mathx.distXZ(f.pos, t.pos) / t.radius, 0, 1);
            f.glare.at = t.pos;
            f.glare.shy = f.glare.k >= (if (f.glare.shy) foemod.SHY_OFF else foemod.SHY_ON);
        }
    }
}

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

/// Every priest against every skitterer, every frame, no distance gate: both groups cap at `wf.MAX_PER_KIND`, so the worst case is 262,144 `distXZ` a frame, about a millisecond. Squaring the test would drop the sqrt but moves a body sitting on `RAISE_KEEP_R` by an ulp.
fn markFlock(g: *Game) void {
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
    // A wrapping `if` and not a `continue`: `gi` is comptime and `ref.group` is not, so skipping an `inline for` iteration is comptime control flow in a runtime block, which Zig refuses.
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

fn envDepthAt(ctx: *const anyopaque, x: f32, z: f32) f32 {
    const e: *const envmod.Env = @ptrCast(@alignCast(ctx));
    return e.wadeDepth(x, z);
}

/// THE ROOM A BODY FIGHTS IN IS STAMPED, NOT ASKED FOR: any creature with a `room` field gets a copy of the arena it stands in each frame (null on open ground), and one with a `ground` field gets the world's water to ask, so its own moves can keep to dry ground inside the walls before the hold ever has to.
fn stampRooms(g: *Game) void {
    inline for (FOE_GROUPS) |gr| {
        const M = memberOf(gr.field);
        if (comptime !@hasField(M, "room") and !@hasField(M, "ground")) continue;
        for (@field(g, gr.field).live()) |*f| {
            if (comptime @hasField(M, "room")) f.room = if (g.map.arenaIndexAt(f.pos.x, f.pos.z)) |i| g.map.arenas[i] else null;
            if (comptime @hasField(M, "ground")) f.ground = .{ .ctx = &g.env, .depthAt = envDepthAt };
        }
    }
}

/// The group each of the druidess's waves comes up in — the same four she fights beside (`FOE_GROUPS`' coven row). Checked at comptime against `druidess.waveKind`, so the two cannot drift.
const WAVES = [_]struct { wave: druidmod.Wave, field: []const u8 }{
    .{ .wave = .deer, .field = "herd" },
    .{ .wave = .sporelings, .field = "cluster" },
    .{ .wave = .wights, .field = "stand" },
    .{ .wave = .frogs, .field = "warren" },
};
const WAVE_FIELDS = blk: {
    var out: [WAVES.len][]const u8 = undefined;
    for (WAVES, 0..) |row, i| out[i] = row.field;
    break :blk out;
};

comptime {
    @setEvalBranchQuota(20000);
    for (@typeInfo(druidmod.Wave).@"enum".fields) |f| {
        const w: druidmod.Wave = @enumFromInt(f.value);
        var rows: usize = 0;
        for (WAVES) |row| {
            if (row.wave != w) continue;
            rows += 1;
            var kind: ?FoeKind = null;
            for (FOE_GROUPS) |gr| {
                if (std.mem.eql(u8, gr.field, row.field)) kind = gr.kind;
            }
            if (kind == null or kind.? != druidmod.waveKind(w)) @compileError("game: WAVES sends `" ++ f.name ++ "` to `" ++ row.field ++ "`, which is not the kind `druidess.waveKind` names");
        }
        if (rows != 1) @compileError("game: the druidess's wave `" ++ f.name ++ "` needs exactly one row in WAVES");
    }
}

/// THE CREATURE ONLY REPORTS IT (the necromancer's rule): the wave comes up on the ground under each spot, in the groups those kinds already live in.
fn summonWave(g: *Game, d: *const druidmod.Druidess, w: druidmod.Wave) void {
    const n = druidmod.waveCount(w);
    var i: u8 = 0;
    while (i < n) : (i += 1) {
        const spot = d.summonSpot(i, n);
        const at = v3(spot.x, g.env.groundAt(spot.x, spot.z), spot.z);
        const yaw = mathx.headingXZ(mathx.dirXZ(at, g.hero.pos));
        const seed = 0.17 + 0.23 * @as(f32, @floatFromInt(i));
        inline for (WAVES) |row| {
            if (w == row.wave) @field(g, row.field).summon(at, yaw, seed);
        }
    }
    g.rumble.play(rumblemod.hit_heavy);
    g.rig.addShake(SHAKE_RAISE);
}

fn canSee(g: *const Game, r: FoeRef) bool {
    return g.env.sees(heroEye(g), foeLockPoint(g, r));
}

fn pierceFoes(g: *Game, blade: foemod.Blade) bool {
    var hit = false;
    inline for (FOE_GROUPS) |f| {
        if (!hit or blade.through) {
            if (@field(g, f.field).pierce(blade)) hit = true;
        }
    }
    return hit;
}

const ARROW_QUERY_PAD: f32 = 1.5;
var arrow_cover_buf: [envmod.MAX_NEAR]collision.Solid = undefined;
pub fn arrowCover(g: *const Game, ar: *const archermod.Arrow, dt: f32) []const collision.Solid {
    if (ar.stuck) return &.{};
    return g.env.nearSolids(ar.pos, mathx.lenV(ar.vel) * dt + ARROW_QUERY_PAD, &arrow_cover_buf);
}

fn quivers(g: *Game) [2][]archermod.Arrow {
    return .{ &g.arrows, &g.shafts };
}

fn justLanded(ar: *const archermod.Arrow) bool {
    return ar.stuck and ar.age == 0;
}

fn planted(g: *Game, ar: *const archermod.Arrow, his: bool) void {
    if (!justLanded(ar)) return;
    if (ar.shot != .venom) sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
    if (his) {
        if (g.env.illusionTouched(ar.pos, ILLUSION_ARROW_R)) |i| dispelIllusion(g, i, ar.pos);
    }
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
        .sac => {
            sfx.world(.shroom_puff, ar.pos);
            g.cluster.spawnCloud(ground);
        },
        .powder => powderBurst(g, ground),
        .rock => rockBurst(g, ground),
        .arrow, .firearrow, .wisp, .crock, .spark => {},
    }
}

/// THE DELVER'S STONE COMES DOWN: a ring about where it lands, billed once whether it met him in the air or on the ground (`detonates`), and a roll through it is a roll through it.
fn rockBurst(g: *Game, ground: rl.Vector3) void {
    sfx.world(.ogre_slam, ground);
    g.rig.addShake(SHAKE_HIT_HEAVY);
    g.hero.dustPuff(ground, delvermod.ROCK_SPLASH_R, foemod.DUST, g.hero.casts);
    if (g.hero.iFramed()) return;
    if (mathx.distXZ(ground, g.hero.pos) > delvermod.ROCK_SPLASH_R + HERO_R) return;
    _ = heroTakes(g, .{ .hit = delvermod.ROCK_HIT, .from = ground }, true, true);
}

fn spawnRock(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, mathx.addV(g.hero.pos, v3(0, 0.3, 0)), delvermod.ROCK_SPEED, delvermod.ROCK_HIT, true, .rock));
}

fn shotBuildup(s: archermod.Shot) f32 {
    return switch (s) {
        .venom => broodmod.M_SPIT_BUILD,
        .arrow, .firearrow, .clump, .crock, .bolt, .wisp, .emberball, .sac, .spark, .powder, .rock => 0,
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
    try std.testing.expectEqual(broodmod.M_SPIT_BUILD, shotBuildup(.venom));
    try std.testing.expect(shotBuildup(.venom) * 3.0 >= combat.POISON_MAX);
    inline for (@typeInfo(archermod.Shot).@"enum".fields) |f| {
        const s: archermod.Shot = @enumFromInt(f.value);
        if (s != .venom) try std.testing.expectEqual(@as(f32, 0), shotBuildup(s));
    }
}

fn detonates(s: archermod.Shot) bool {
    return s == .emberball or s == .rock;
}

const BLAST_R: f32 = 3.1;
const BLAST_FLOOR: f32 = 0.30;

fn emberBlast(g: *Game, ar: *const archermod.Arrow) void {
    if (ar.shot != .emberball or g.hero.dead) return;
    const d = mathx.distXZ(ar.pos, g.hero.pos);
    if (d > BLAST_R) return;
    const k = mathx.lerpF(1.0, BLAST_FLOOR, mathx.clampF(d / BLAST_R, 0, 1));
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
                .rock => &g.rockModel,
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

fn drawFar(g: *const Game) f32 {
    if (g.editor.on) return mathx.clampF(g.editor.dist * 2.0 + CLIP_FAR, CLIP_FAR, FAR_MAX);
    if (g.menu.booting()) return FAR_MAX;
    return CLIP_FAR;
}

/// Every per-kind LOD reach is lifted to at least this on the boot screen, so what culls is the frustum and the far plane.
fn viewFloorOf(g: *const Game) f32 {
    if (g.editor.on or g.menu.booting()) return drawFar(g);
    return 0;
}

const FAR_MAX: f32 = 2600.0;

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
    if (g.weather.thunder()) |gain| sfx.playAt(.thunder, gain);
    const under = g.env.groundAt(g.hero.pos.x, g.hero.pos.z);
    g.mist.tick(dt, g.hero.pos, under, fogAmt(g));
    if (g.menu.takeBirds()) g.skein.stageOne(g.hero.pos, under, g.hero.facing + std.math.pi * 0.5);
    g.skein.tick(dt, g.hero.pos, under, g.wetNow);
}

fn settleSky(g: *Game, dt: f32) void {
    settleSkyAt(g, dt, g.hero.pos);
}

fn hazeK(g: *const Game) f32 {
    if (!g.editor.on) return g.menu.fogK();
    return if (g.editor.showFog) g.menu.fogK() else 0;
}

fn skyLive(g: *const Game) bool {
    if (!g.editor.on) return true;
    return g.editor.showWeather and g.editor.visible(.locations);
}

fn settleSkyAt(g: *Game, dt: f32, at: rl.Vector3) void {
    if (!skyLive(g)) {
        g.wetNow = 0;
        g.fogNow = 0;
        g.sporeNow = 0;
        g.emberNow = 0;
        return;
    }
    const here = g.map.weatherAt(at.x, at.z);
    const wantWet = if (here) |l| l.wet orelse g.weather.rain() else g.weather.rain();
    const wantFog = if (here) |l| l.fog orelse 0 else 0;
    const wantSpore = if (here) |l| l.spore orelse 0 else 0;
    const wantEmber = g.emberForce orelse (if (here) |l| l.ember orelse 0 else 0);
    if (g.editor.on) {
        g.wetNow = mathx.clampF(wantWet, 0, 1);
        g.fogNow = mathx.clampF(wantFog, 0, 1);
        g.sporeNow = mathx.clampF(wantSpore, 0, 1);
        g.emberNow = mathx.clampF(wantEmber, 0, 1);
        return;
    }
    const secs = if (here) |l| l.blend else SKY_SETTLE;
    const rate = 1.0 / mathx.maxF(secs, 0.05);
    g.wetNow = mathx.approach(g.wetNow, mathx.clampF(wantWet, 0, 1), rate * dt);
    g.fogNow = mathx.approach(g.fogNow, mathx.clampF(wantFog, 0, 1), rate * dt);
    g.sporeNow = mathx.approach(g.sporeNow, mathx.clampF(wantSpore, 0, 1), rate * dt);
    g.emberNow = mathx.approach(g.emberNow, mathx.clampF(wantEmber, 0, 1), rate * dt);
}

const SKY_SETTLE: f32 = 6.0;

fn fogAmt(g: *const Game) f32 {
    if (!skyLive(g)) return 0;
    return mathx.maxF(mathx.maxF(g.menu.fogAmt(g.wetNow), g.fogNow), mathx.maxF(g.sporeNow * SPORE_BANKS, g.emberNow * EMBER_BANKS));
}

const SPORE_BANKS: f32 = 0.45;
/// The smoke over an ember field is the mist banks under `bankTint`'s smoke tone — light, so the coals still read through it.
const EMBER_BANKS: f32 = 0.35;

fn drawWeatherOverlay(g: *Game) void {
    if (g.editor.on) return;
    weathermod.drawOverlay(rl.getScreenWidth(), rl.getScreenHeight(), weathermod.dimOf(g.wetNow), g.weather.flash());
}

pub fn drawScene(g: *Game) void {
    g.env.resetStats();
    applyStow(g);
    const cam = sceneCam(g);
    foemod.setLens(cam.position, mathx.normV(mathx.subV(cam.target, cam.position)));
    // Eye AND target on the lens is the "no occlusion" idiom (`markOccluders` returns on a zero-length look, easing every fade back to opaque).
    const seeThrough = g.editor.on or g.menu.booting();
    g.env.markOccluders(cam.position, if (seeThrough) cam.position else heroAimPoint(g), g.drawDt);
    rl.gl.rlSetClipPlanes(CLIP_NEAR, drawFar(g));
    const casting = !g.editor.on or g.editor.showShadows;
    if (casting) {
        const focus = sunFocus(g);
        g.scene.beginShadowPass(focus, shadowSpanOf(g));
        setCasterShaders(g, g.scene.depthShader);
        drawCasters(g, .{ .sun = focus });
        g.env.drawCliffCasters(focus);
        rl.gl.rlSetCullFace(@intFromEnum(rl.gl.rlCullMode.rl_cull_face_front));
        g.env.drawGroundCasters(focus);
        rl.gl.rlSetCullFace(@intFromEnum(rl.gl.rlCullMode.rl_cull_face_back));
        setCasterShaders(g, g.scene.shader);
        g.scene.endShadowPass();
    }

    rl.beginDrawing();
    const filtered = if (g.editor.on) false else g.retro.begin();
    rl.clearBackground(if (dbgBright) rgba(255, 0, 255, 255) else CLEAR);
    if (!dbgBright) g.sky.draw(cam);

    const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
    var view = envmod.View.fromCamera(cam, aspect);
    view.floor = viewFloorOf(g);

    rl.beginMode3D(cam);
    g.scene.bind(cam.position);
    if (!casting) g.scene.shadowsOff();
    var lightBuf: [RESERVED_LIGHTS]gfx.Light = undefined;
    g.env.uploadLights(&g.scene, &view, @floatCast(rl.getTime()), reservedLights(g, &lightBuf));
    g.scene.setGround(true);
    g.env.drawGround(&view);
    g.scene.setGround(false);
    g.env.drawCliffFaces(&view);
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
    foemod.drawParticles(&g.illusionMotes);
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
    if (skyLive(g)) {
        if (!g.editor.on) g.rainfall.draw(&g.scene, cam.position, g.hero.pos, g.wetNow, g.weather.t);
        if (!g.editor.on) g.mist.draw(&g.scene, cam.position, fogAmt(g), bankTint(g));
        g.sporefall.draw(&g.scene, cam.position, if (g.editor.on) cam.position else g.hero.pos, g.sporeNow, g.weather.slowSecs());
        g.emberfall.draw(&g.scene, cam.position, if (g.editor.on) cam.position else g.hero.pos, g.emberNow, g.weather.slowSecs());
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
    if (speed >= heromod.SPRINT_SPEED - GAIT_SLACK) return .sprint;
    if (speed >= heromod.RUN_SPEED - GAIT_SLACK) return .run;
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

/// `arrowCover` queries a radius of `speed * dt` against a `MAX_NEAR` pinned over a 2x2 cell window: at 40 m/s a 0.35 s stall asks for a 3-wide one and the overflow DROPS SILENTLY.
const DT_MAX: f32 = 1.0 / 30.0;

pub fn run(mode: Mode) void {
    const shot = mode != .play;
    var runTimer = std.time.Timer.start() catch unreachable;
    const stamp = struct {
        fn ms(t: *std.time.Timer, name: []const u8) void {
            std.debug.print("INIT: {s: <10} {d:.1} ms\n", .{ name, @as(f64, @floatFromInt(t.lap())) / 1e6 });
        }
    }.ms;
    // VSYNC, not `setTargetFPS`: that is a CPU-side frame LIMITER and never tells the driver to swap during vblank, so fullscreen tears.
    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true, .window_hidden = shot, .window_resizable = true });
    rl.initWindow(SCREEN_W, SCREEN_H, "Gloamfall");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    stamp(&runTimer, "window");

    hud_.init();
    defer hud_.deinit();
    stamp(&runTimer, "fonts");

    tune.init();
    if (!shot) {
        tune.load();
        sfx.init();
        stamp(&runTimer, "audio bake");
    }
    defer if (!shot) sfx.deinit();
    defer objviewmod.unload();
    defer bookmod.unload();
    defer hud_.unloadPortrait();
    defer menumod.unload();
    defer editormod.unloadMinimap();

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
    var homedStamp: u64 = 0;
    var wasEditing = false;
    defer g.rumble.stop();
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime();
        const dt = mathx.minF(rawDt, DT_MAX) * g.menu.timeScale;
        g.drawDt = rawDt;
        PLAY_HALF = playHalfOf(g.map.half);
        // The hour holds while he rests or talks; the weather does NOT — a frozen sheet hung in the air over the bonfire scene and the bed stopped answering the storm.
        if (!g.editor.on and !g.menu.isOpen() and !g.rest.active() and !g.talk.active() and !g.award.carding()) g.day.tick(dt);
        if (!g.editor.on and !g.menu.isOpen()) {
            tickWeather(g, dt);
        } else if (g.editor.on) {
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
        // ONE DRIVER, above every branch that `continue`s: the editor and the boot menu did not pump the streams, so a title track fading out under either stalled.
        tickAudioFades(g, rawDt);
        sfx.tickStreams();

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
            const placed = foePlacementStamp(&g.map);
            if (!wasEditing or placed != homedStamp) {
                rehomeFoes(g, .blind);
                homedStamp = placed;
            }
            wasEditing = true;
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
        wasEditing = false;

        g.hero.held = g.menu.isOpen();
        if (g.menu.isOpen()) {
            switch (g.menu.update(&g.retro, &g.day, &g.weather, rawDt, bookView(g), &g.shelf)) {
                .quit => break,
                .editor => {
                    g.lock = null;
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
            drawScene(g);
            takeSlotShot(g);
            hud(g, rawDt);
            restmod.drawScreen(&g.rest, restView(g));
            saveMark(g, rawDt);
            rl.endDrawing();
            continue;
        }
        if (g.counter.open) {
            tickCounter(g, rawDt);
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
            drawScene(g);
            counterui.draw(&g.counter, &g.hero, &g.bag, g.counterT, counterPortrait(g));
            rl.endDrawing();
            continue;
        }
        if (g.talk.active()) {
            tickTalk(g, rawDt);
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
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

        const lockPressed = !g.hero.aiming and (rl.isMouseButtonPressed(.middle) or padPressed(.right_thumb));
        if (lockPressed) {
            if (g.lock != null) {
                g.lock = null;
            } else {
                g.lock = acquireLock(g);
                if (g.lock == null and rl.isGamepadAvailable(PAD)) g.rig.recenter(g.hero.facing);
            }
        }
        if (g.lock) |*li| {
            // The rider is shot off: the point it rode is gone, and the lock falls back onto the body that carried it.
            if (refInBounds(g, li.*) and li.part >= foeParts(g, li.*)) li.part = 0;
        }
        if (g.lock) |li| {
            if (!lockValid(g, li)) {
                g.lock = null;
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
        if (useReq and !g.hero.dead and !g.hero.onLadder() and g.gateWalk == null) interact(g);

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
        const leftIn = HandIn{ .press1 = l1Press, .press2 = l2Press, .held1 = l1Held, .held2 = l2Held };
        if (leftHeld) |la| handActs(la, leftIn, &acts) else skillActs(rightHeld, leftIn, &acts);
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
        if (!g.hero.stam.canSprint()) mv.speed = @min(mv.speed, heromod.RUN_SPEED);
        const wade = wadeDrag(g);
        if (wade < 1.0) mv.speed = @min(mv.speed, heromod.WALK_SPEED * wade);
        g.hero.vit.tick(dt);
        g.hero.regen.tick(dt, &g.hero.vit);
        g.hero.tickTimed(dt);
        g.hero.tickFlash(dt);
        g.hero.quick.dropEmpty(&g.bag);
        const jumpReq = rl.isKeyPressed(JUMP_KEY) or padPressed(JUMP_PAD);
        if ((g.climb != null or g.mantle != null) and (jumpReq or rollReq)) dropOffLadder(g);
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
        if (g.hero.guarding) mv.speed = @min(mv.speed, heromod.WALK_SPEED * heromod.GUARD_SPEED * g.hero.guardWalk());
        if (g.hero.aiming) mv.speed = @min(mv.speed, heromod.WALK_SPEED * heromod.BOW_AIM_SPEED);
        if (g.hero.drinking) mv.speed = @min(mv.speed, heromod.WALK_SPEED * heromod.DRINK_SPEED);

        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        const faceYaw: ?f32 = if (g.hero.aiming) g.rig.yaw else lockYaw;
        g.hero.aimAtPitch(meleePitch(g));
        leanToGround(g, dt);
        const heroWas = g.hero.pos;
        const heroAfoot = !g.hero.dead;
        if (g.hero.dead or g.hero.staggered()) {
            g.gateWalk = null;
            dropOffLadder(g);
        }
        if (g.hero.dead) {
            g.hero.updateDeath(dt);
            if (!g.hero.dead) {
                resetFoes(g);
                saveNow(g, .withShot);
            }
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt);
        } else if (g.gateWalk != null) {
            updateGateWalk(g, dt);
        } else if (g.climb != null) {
            updateClimb(g, dt, mv);
        } else if (g.mantle != null) {
            updateMantle(g, dt);
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
        if (heroAfoot and !g.hero.onLadder()) gateHeroTerrain(g, heroWas);
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
        markHour(g);
        markGlare(g);
        markSight(g);
        markThreat(g, dt);
        markWays(g);
        markWade(g);
        markParry(g);
        markVigil(g);
        markFlock(g);
        const bladeNow = heroBlade(g);
        revealIllusions(g, bladeNow);
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= ogremod.SLAM_HIT.stance, true);
        }
        for (g.line.live()) |*a| {
            if (a.update(dt, a.threat.aim(g.hero.pos), PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), heroAimPoint(g));
            }
            if (a.heroHit) |h| _ = heroTakes(g, .{ .hit = h, .from = a.pos, .on = a.threat.on }, false, true);
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
        for (g.warrens.live()) |*d| {
            if (d.threw) {
                sfx.world(.delver_claw, d.throwFrom);
                spawnRock(g, d.throwFrom);
            }
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
        if (g.shoal.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        g.hero.snareFor(g.shoal.takeSnare());
        if (g.roost.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            g.roost.fedOn(heroTakes(g, b, b.hit.heavy(), true) == .taken);
        }
        if (g.roost.anyDrank()) {
            g.rumble.play(rumblemod.hurt);
            g.rig.addShake(SHAKE_HURT);
        }
        if (g.perch.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.perch.anyWoke()) g.rig.addShake(SHAKE_ROUSE);
        _ = g.crypt.update(dt, g.hero.pos, PLAY_HALF, bladeNow);
        if (g.crypt.breathDose(dt, g.hero.pos)) |b| {
            _ = heroTakes(g, b, false, false);
        }
        for (g.crypt.live()) |*p| {
            if (p.called) sfx.world(.priest_call, p.pos);
            if (p.drewBreath) sfx.world(.priest_breath, p.muzzleWorld());
            if (p.yelped) sfx.world(.bone_hurt, p.pos);
            if (p.justDied) sfx.world(.bone_die, p.pos);
            if (p.raised) {
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
            if (h.unseated) sfx.world(.kobold_die, h.riderWorld());
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
        if (g.vanguard.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.launch > 0, true);
        }
        if (g.conclave.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.launch > 0, true);
        }
        stampRooms(g);
        if (g.coven.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        g.hero.snareFor(g.coven.takeSnare());
        if (g.coven.holdDose(dt)) |b| _ = heroTakes(g, b, false, false);
        for (g.coven.live()) |*d| {
            if (d.summoned) |w| summonWave(g, d, w);
        }
        if (g.hoard.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        for (g.hoard.live()) |*m| {
            if (m.justWoke) {
                sfx.world(.chest_open, m.pos);
                sfx.world(.skitter_clack, m.pos);
                g.rumble.play(rumblemod.hit_heavy);
                g.rig.addShake(SHAKE_ROUSE);
            }
            if (m.snapped) sfx.world(.toad_chomp, m.headWorld());
            if (m.swept) sfx.world(.ogre_swipe, m.headWorld());
            if (m.justDied) sfx.world(.bone_die, m.pos);
        }
        if (g.drove.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.launch > 0, true);
        }
        for (g.drove.live()) |*m| {
            if (m.bellowed) sfx.world(.ogre_roar, m.pos);
            if (m.swept) sfx.world(.ogre_swipe, m.pos);
            if (m.snapped) sfx.world(.toad_chomp, m.lockPoint());
            if (m.stamped) {
                sfx.world(.ogre_step, m.pos);
                g.rig.addShake(SHAKE_HIT_LIGHT);
            }
            if (m.landed) {
                sfx.world(.ogre_slam, m.pos);
                g.rumble.play(rumblemod.hit_heavy);
                g.rig.addShake(SHAKE_RAISE);
            }
            if (m.justDied) sfx.world(.ogre_die, m.pos);
        }
        tickBoltGas(g, dt);
        tickIllusions(g, dt);
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
        spendTurnedBlows(g);
        g.hero.poisonBy(g.brood.burn(dt, g.hero.pos));
        g.hero.poisonBy(g.cluster.spores(dt, g.hero.pos));
        g.hero.doseSelf(.sleep, g.bed.breath(g.hero.pos) * dt);
        g.hero.doseSelf(.sleep, g.conclave.breath(g.hero.pos, dt));
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
                planted(g, ar, false);
                emberBlast(g, ar);
            }
        }
        if (allHits(g) > hitsBefore) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.hit_heavy else rumblemod.hit_light);
            g.rig.addShake(if (g.hero.atkHeavy) SHAKE_HIT_HEAVY else SHAKE_HIT_LIGHT);
            sfx.play(if (g.hero.atkHeavy) .hit_heavy else .hit_light);
            if (g.hero.attacking) _ = g.hero.drinkLeech();
        }
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
        if (!g.hero.onLadder()) {
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
        g.rig.followClear(g.hero.shoulderPoint(), camFloor(g), CamFloor.at, dt);
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
        takeSlotShot(g);
        hud(g, rawDt);
        saveMark(g, rawDt);
        tickEnter(g, rawDt);
        drawEnterFade(g);
        rl.endDrawing();
    }
}

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
    const vol = mathx.clampF(0.45 + 0.55 * h.speed / heromod.SPRINT_SPEED, 0.35, 1.0);
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

const LIQUID_EAR: f32 = 34.0;
/// Cells inside `LIQUID_EAR` that make a bed full. At 2.5 m a cell, 40 is a pond about 18 m across.
const LIQUID_FULL: f32 = 40.0;
const POP_EVERY: f32 = 1.15;
const SEAR_EVERY: f32 = 1.0;

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
            std.debug.assert(i == @intFromEnum(worldfmt.Liquid.water) and v.pop == null);
            continue;
        };
        std.debug.assert(std.mem.eql(u8, @tagName(bed), tag ++ "_bed"));
        std.debug.assert(std.mem.eql(u8, @tagName(v.pop.?), tag ++ "_pop"));
        std.debug.assert(sfx.LIQUID_BEDS[i - 1] == bed);
        beds += 1;
    }
    std.debug.assert(beds == sfx.LIQUID_BEDS.len);
}

fn tickLiquid(g: *Game, dt: f32) void {
    const N = worldfmt.Liquid.N;
    var weight = [_]f32{0} ** N;
    var seen = [_]f32{0} ** N;
    var pick = [_]rl.Vector3{mathx.zero3} ** N;
    if (g.env.waterAny) {
        const n = worldfmt.WATER_N;
        const cell = g.map.cellSize(n);
        const half = g.map.half;
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
    g.hero.doseSelf(bill.ail, bill.amt);
    if (bill.dmgFrac <= 0) {
        g.searT = 0;
        return;
    }
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
        .world = .{ .map = &g.map, .env = &g.env, .seen = &g.seenMap, .at = g.hero.pos, .facing = g.hero.facing },
    };
}

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

/// A TWO-HANDED ARM HOLDS BOTH HANDS, so the left hand's buttons are its own skill slot: `offInHand` is false with a bow up, so `handActs` never sees the left group.
/// And the aim may not sit on the same button as the aimed loose, or `requestShot(true)` is asked before `setAim` has run and is refused on the one frame the press exists.
fn skillActs(a: heromod.Armament, in: HandIn, out: *Acts) void {
    switch (a) {
        .bow => out.aim = out.aim or in.held1 or in.held2,
        .sword, .dagger, .club, .bell, .shield, .wand, .torch => {},
    }
}

fn handActs(a: heromod.Armament, in: HandIn, out: *Acts) void {
    switch (a) {
        .sword, .dagger, .club => {
            out.light = out.light or in.press1;
            out.heavy = out.heavy or in.press2;
        },
        .bow => {
            out.quick = out.quick or in.press1;
            out.aimed = out.aimed or in.press2;
        },
        .bell => out.ring = out.ring or in.press1,
        .shield => {
            out.guard = out.guard or in.held1;
            out.parry = out.parry or in.press2;
        },
        .wand => out.cast = out.cast or in.press1,
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

fn doseRing(g: *Game, at: rl.Vector3, r: f32, a: combat.Ail, amt: f32) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            if (!foemod.corporeal(f)) continue;
            if (disguised(f)) continue; // the breath cone's rule: a cloud is poured over the field, not under it
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
            if (g.climb != null or g.mantle != null) knockOffLadder(g, b);
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
    if (b.hit.shove > 0) heroShoved(g, b.from, b.hit.shove, out);
    return out;
}

comptime {
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
    const w = mathx.clampF(h.raw() / blowHeaviest(), BLOCK_FELT_MIN, 1.0);
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
const BOLT_GAS_HIT = combat.Hit{ .elem = combat.elems(.{ .chaos = 7 }) };

fn tickBoltGas(g: *Game, dt: f32) void {
    var any = false;
    for (&g.boltGas) |*c| {
        c.update(dt);
        if (c.live) any = true;
    }
    if (!any) {
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

/// One reveal is the worst frame: every solid of the face puffed on a `ILLUSION_PUFF_COLS` x `ILLUSION_PUFF_ROWS` grid, `ILLUSION_PUFF_N` motes a puff. The ring is that arithmetic, not a round number.
const ILLUSION_PUFF_COLS: usize = 5;
const ILLUSION_PUFF_ROWS: usize = 4;
const ILLUSION_PUFF_N: i32 = 6;
const ILLUSION_MOTES: usize = propsmod.FIT_CAP * ILLUSION_PUFF_COLS * ILLUSION_PUFF_ROWS * @as(usize, @intCast(ILLUSION_PUFF_N));
/// A roll that brushes the face counts, as does an arrow planted in it; a blade has to reach the stone.
const ILLUSION_ROLL_REACH: f32 = 0.35;
const ILLUSION_ARROW_R: f32 = 0.30;
const VEIL_MOTE = mathx.rgba(168, 176, 214, 200);
const VEIL_MOTE_THIN = mathx.rgba(214, 220, 244, 0);
const VEIL_PUFF = foemod.Puff{ .blast = foemod.Blast.of(foemod.DUST_DRAG, 0.7, 1.4), .spdLo = 0.35, .upLo = 0.6, .upHi = 1.8, .rLo = 0.08, .rHi = 0.20, .col = VEIL_MOTE, .col1 = VEIL_MOTE_THIN };

fn revealIllusions(g: *Game, blade: foemod.Blade) void {
    if (blade.active) {
        if (g.env.illusionStruck(blade.a, blade.b, blade.r)) |i| dispelIllusion(g, i, mathx.scaleV(mathx.addV(blade.a, blade.b), 0.5));
    }
    if (g.hero.rolling) {
        if (g.env.illusionTouched(g.hero.pos, HERO_R + ILLUSION_ROLL_REACH)) |i| dispelIllusion(g, i, g.hero.pos);
    }
}

fn dispelIllusion(g: *Game, i: u8, at: rl.Vector3) void {
    if (!g.env.dispelIllusion(i)) return;
    sfx.world(.veil_break, at);
    for (g.env.illusionSolids(i)) |s| {
        var k: usize = 0;
        while (k < ILLUSION_PUFF_COLS) : (k += 1) {
            const t = (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, @floatFromInt(ILLUSION_PUFF_COLS));
            const x = mathx.lerpF(s.a.x, s.b.x, t);
            const z = mathx.lerpF(s.a.z, s.b.z, t);
            const base = g.env.groundAt(x, z);
            const top = @min(s.h, base + 6.5);
            var j: usize = 0;
            while (j < ILLUSION_PUFF_ROWS) : (j += 1) {
                const y = mathx.lerpF(base + 0.5, top, (@as(f32, @floatFromInt(j)) + 0.5) / @as(f32, @floatFromInt(ILLUSION_PUFF_ROWS)));
                foemod.puff(&g.illusionMotes, &g.illusionHead, &g.illusionRng, v3(x, y, z), ILLUSION_PUFF_N, 1.4, 0.9, 1.0, VEIL_PUFF);
            }
        }
    }
}

fn tickIllusions(g: *Game, dt: f32) void {
    g.env.tickIllusions(dt);
    foemod.tickParticles(&g.illusionMotes, dt, -1e9);
}

fn inBounds(p: rl.Vector3) rl.Vector3 {
    return mathx.clampXZ(p, PLAY_HALF);
}

fn collideActors(g: *Game, dt: f32) void {
    const step = COLLIDE_RATE * dt;
    var hp = g.hero.pos;
    if (!g.hero.onLadder()) {
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

/// n² inside the group, every frame, no distance gate: `MAX_PER_KIND` is 512, and 512 in one group is 261,632 pairs a frame, about a millisecond.
/// `bodyOf(o)` MAY NOT BE HOISTED OUT OF THE INNER LOOP: `a.pos` is written at the END of each outer pass, so body i settles against 0..i-1 at their NEW positions — Gauss-Seidel, not Jacobi.
fn settleGroup(g: *Game, comptime gr: FoeGroup, step: f32) void {
    const foes = @field(g, gr.field).live();
    for (foes, 0..) |*a, i| {
        if (!foemod.corporeal(a) or phased(a)) continue;
        const r = a.bodyR();
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
/// `part` is WHICH POINT on the body the lock rides: 0 is its `lockPoint`, the rest are what `lockPointAt` offers (the ogre's head, the hollow's rider). A body offers `lockParts` of them; one without the decl offers one.
const FoeRef = struct { kind: FoeKind, idx: usize, part: u8 = 0 };

fn partsOf(f: anytype) u8 {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "lockParts")) return f.lockParts();
    return 1;
}

fn lockPointOf(f: anytype, part: u8) rl.Vector3 {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "lockPointAt")) return f.lockPointAt(part);
    return f.lockPoint();
}

/// The flick walks a LINE: every point on this body in part order, then the next body over. Null is "off this body".
fn stepPart(part: u8, parts: u8, dir: f32) ?u8 {
    if (dir > 0) return if (part + 1 < parts) part + 1 else null;
    return if (part > 0) part - 1 else null;
}

test "THE FLICK WALKS THE BODY BEFORE IT LEAVES IT — up in part order, back down the same way, one body at a time" {
    try std.testing.expectEqual(@as(?u8, 1), stepPart(0, 2, 1));
    try std.testing.expectEqual(@as(?u8, null), stepPart(1, 2, 1));
    try std.testing.expectEqual(@as(?u8, 0), stepPart(1, 2, -1));
    try std.testing.expectEqual(@as(?u8, null), stepPart(0, 2, -1));
    try std.testing.expectEqual(@as(?u8, null), stepPart(0, 1, 1));
    try std.testing.expectEqual(@as(?u8, null), stepPart(0, 1, -1));
}
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
        if (roleIdx(rg[1], r)) |i| return ask(&@field(g, rg[0]).liveConst()[i], r);
    }
    if (r.kind == .brood_sac) return ask(&g.brood.liveSacsConst()[r.idx], r);
    inline for (SOLO_GROUPS) |s| {
        if (r.kind == s.kind) return ask(&@field(g, s.field).liveConst()[r.idx], r);
    }
    unreachable; // the comptime partition above is what makes this dead
}
fn foePos(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype, _: FoeRef) rl.Vector3 {
            return f.pos;
        }
    }.ask);
}
fn foeResists(g: *const Game, r: FoeRef) combat.Resists {
    return askFoe(combat.Resists, g, r, struct {
        fn ask(f: anytype, _: FoeRef) combat.Resists {
            return f.vit.res;
        }
    }.ask);
}
fn foeLockPoint(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype, ref: FoeRef) rl.Vector3 {
            return lockPointOf(f, ref.part);
        }
    }.ask);
}
fn foeParts(g: *const Game, r: FoeRef) u8 {
    return askFoe(u8, g, r, struct {
        fn ask(f: anytype, _: FoeRef) u8 {
            return partsOf(f);
        }
    }.ask);
}
fn foeTopWorld(g: *const Game, r: FoeRef) rl.Vector3 {
    return askFoe(rl.Vector3, g, r, struct {
        fn ask(f: anytype, _: FoeRef) rl.Vector3 {
            return f.topWorld();
        }
    }.ask);
}
fn foeLockable(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype, _: FoeRef) bool {
            return foemod.corporeal(f);
        }
    }.ask);
}
fn foeStaggered(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype, _: FoeRef) bool {
            return f.staggered();
        }
    }.ask);
}
fn foeDisguised(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype, _: FoeRef) bool {
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
    if (foemod.offField(f)) return true;
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "hidden")) return f.hidden();
    return false;
}

fn phased(f: anytype) bool {
    if (foemod.offField(f)) return true;
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "phased")) return f.phased();
    return false;
}

fn bodyOf(f: anytype) collision.Solid {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "bodySeg")) {
        if (f.bodySeg()) |s| return collision.capsule(s[0].x, s[0].z, s[1].x, s[1].z, f.bodyR());
    }
    return collision.circle(f.pos.x, f.pos.z, f.bodyR());
}

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
    if (stepPart(cur.part, foeParts(g, cur), dir)) |p| {
        g.lock = .{ .kind = cur.kind, .idx = cur.idx, .part = p };
        return;
    }
    const body = FoeRef{ .kind = cur.kind, .idx = cur.idx };
    const curX = lockScreenX(g, body) orelse return;
    var ctx = CycleCtx{ .g = g, .cur = body, .curX = curX, .dir = dir };
    eachTarget(g, &ctx, CycleCtx.visit);
    if (ctx.best) |b| g.lock = .{ .kind = b.kind, .idx = b.idx, .part = if (dir > 0) 0 else foeParts(g, b) - 1 };
}

fn resetFoes(g: *Game) void {
    rehomeFoes(g, .blind);
    applyBosses(g);
    clearQuivers(g);
    g.lock = null;
    g.pack.clear();
    dropRunHud(g);
}

// The mask is cells of THIS map, and the sheet has to show where he is STANDING before he has taken a step.
fn seedChart(g: *Game) void {
    g.seenMap.clear();
    g.seenMap.walked(heroEye(g), g.map.half, &g.env);
}

fn dropRunHud(g: *Game) void {
    g.bossK = [_]f32{0} ** hud_.BOSS_SLOTS;
    g.bossFrac = [_]f32{0} ** hud_.BOSS_SLOTS;
    g.spiritK = 0;
    g.spiritHp = 0;
    hud_.dropBossBars();
    hud_.dropSpiritFace();
    hud_.dropStatusFlash();
    hud_.dropVitalsChip();
}

const HURT_BAR_WINDOW = 5.0;

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


test "the editor's re-home stamp trips on every edit a placed body can take, and holds still otherwise" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(worldfmt.Map);
    defer alloc.destroy(m);
    var line: usize = 0;
    try worldfmt.load(worldfmt.DIR ++ "/01_fallen_plain" ++ worldfmt.EXT, m, &line);
    try std.testing.expect(m.nfoes > 0);

    const at0 = foePlacementStamp(m);
    try std.testing.expectEqual(at0, foePlacementStamp(m));

    const was = m.foes[0];
    m.foes[0].x += 0.25;
    try std.testing.expect(foePlacementStamp(m) != at0);
    m.foes[0] = was;
    try std.testing.expectEqual(at0, foePlacementStamp(m));

    m.foes[0].yaw += 1;
    try std.testing.expect(foePlacementStamp(m) != at0);
    m.foes[0] = was;

    m.foes[0].scale += 0.1;
    try std.testing.expect(foePlacementStamp(m) != at0);
    m.foes[0] = was;

    m.foes[0].ai = if (m.foes[0].ai == .hold) .roam else .hold;
    try std.testing.expect(foePlacementStamp(m) != at0);
    m.foes[0] = was;

    m.foes[0].wp[0].x += 1;
    try std.testing.expect(foePlacementStamp(m) != at0);
    m.foes[0] = was;

    const n = m.nfoes;
    m.nfoes = n - 1;
    try std.testing.expect(foePlacementStamp(m) != at0);
    m.nfoes = n;
    try std.testing.expectEqual(at0, foePlacementStamp(m));

    const hb = m.height;
    for (&m.height) |*c| c.* += 3;
    try std.testing.expect(foePlacementStamp(m) != at0);
    m.height = hb;
    try std.testing.expectEqual(at0, foePlacementStamp(m));

    const k = @intFromEnum(m.foes[0].kind);
    foestat.mult[k].hp = 2.0;
    try std.testing.expect(foePlacementStamp(m) != at0);
    foestat.mult[k] = .{};
    try std.testing.expectEqual(at0, foePlacementStamp(m));
}

// The CEILING, not the live figure: `markWays` asks only the bodies whose `navWant` is non-null. At ~0.9 us a body it is the dearest walk in the loop by 50x — each ask is a `walkStep` plus two `blockedNear` against the prop grid, and the fan is ten more.
test "WHAT THE WAY-FINDING COSTS A FRAME — every placed body asking the prop grid for a way past it" {
    const ta = std.testing.allocator;
    const m = try ta.create(worldfmt.Map);
    defer ta.destroy(m);
    const e = try ta.create(envmod.Env);
    defer ta.destroy(e);
    var line: usize = 0;
    try worldfmt.loadForTest(worldfmt.START_MAP, m, &line);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);

    const BODY_R: f32 = 0.42;
    var navs: [worldfmt.MAX_FOES]foemod.Nav = undefined;
    @memset(navs[0..m.nfoes], foemod.Nav{});

    const ROUNDS = 40;
    var fanned: usize = 0;
    var timer = try std.time.Timer.start();
    for (0..ROUNDS) |_| {
        for (m.foes[0..m.nfoes], 0..) |f, i| {
            const at = v3(f.x, m.heightAt(f.x, f.z), f.z);
            markWay(e, &navs[i], at, BODY_R, mathx.zero3);
            if (navs[i].dir != null) fanned += 1;
        }
    }
    const us = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, @floatFromInt(ROUNDS));
    std.debug.print("\n  ways: {d} bodies asked every frame costs {d:.1} us — {d:.3}% of a 16.7 ms frame ({d} took a fan)\n", .{
        m.nfoes, us, 100.0 * us / 16700.0, fanned / ROUNDS,
    });
    try std.testing.expect(m.nfoes > 0);
    try std.testing.expect(us < 16700.0 * 0.05);
}

test "THE TITLE TRACK SWELLS IN AND IS GONE BEFORE THE WORLD IS — both ends of the one ramp, in seconds" {
    const dt: f32 = 1.0 / 60.0;
    var k: f32 = 0;
    var t: f32 = 0;
    while (k < 1.0 and t < 60) : (t += dt) k = introRamp(k, true, dt);
    try std.testing.expectApproxEqAbs(INTRO_FADE_IN, t, 2 * dt);

    var out: f32 = 0;
    while (k > 0 and out < 60) : (out += dt) k = introRamp(k, false, dt);
    try std.testing.expectApproxEqAbs(INTRO_FADE_OUT, out, 2 * dt);
    try std.testing.expect(out * 4 < t);

    k = introRamp(0, true, 1.0);
    var quick: f32 = 0;
    while (k > 0 and quick < 60) : (quick += dt) k = introRamp(k, false, dt);
    try std.testing.expect(quick < INTRO_FADE_OUT);
    try std.testing.expectEqual(@as(f32, 0), k);
    std.debug.print("  title track: {d:.1} s in, {d:.1} s out, {d:.2} s out from one second in\n", .{ t, out, quick });
}
