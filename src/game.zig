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
/// than one creature's name: the ogre's slam held it until five metres of iron started falling over.
const BLOW_HEAVIEST = @max(ogremod.SLAM_HIT.raw(), knightmod.FALL_HIT.raw());
const BLOCK_FELT_MIN = 0.25;
const BLOCK_FELT_HEAVY = 0.5;
const SHAKE_DEATH = 0.85;
const SHAKE_CHEST = 0.12;
const STAT_WARN = mathx.rgba(206, 150, 110, 255);
const SHAKE_SKEL_LEAP = 0.24;
const SHAKE_HATCH = 0.30;
const SHAKE_SAC_BURST = 0.34;
/// The delver committing to a burst — a TELL and not a hit, so it sits under everything that has actually
/// landed on him and over the beats that are only scenery.
const SHAKE_SURGE = 0.26;
/// A body getting back up. Sized against the surge deliberately: both are things happening to the WORLD
/// rather than to him, and this one is the heavier of the two because it undoes work he has already done.
const SHAKE_RAISE = 0.30;
/// …and a ring going into the ground at his feet, which is a TELL: it sits under both of the above and over
/// the beats that are only scenery, because nothing has touched him yet.
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
/// The tilt is measured off the LIVE eye rather than solved, so it is a feedback loop — convergent because
/// the gain is `boom / (boom + distance to the mark)`, under 1 everywhere the guard below does not fire.
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

/// WHICH WORLD THE BLACK FRAME IS ABOUT TO BUILD. **EVERY WAY INTO ONE GOES THROUGH THIS UNION** — a fresh
/// character, a slot off the disk, and walking from one map into the next (an indoor one, a cellar, a hall).
/// As three separate transitions they would be three places to forget the fade from; as one variant each,
/// gaining a way in is a row here and a case in `enterNow`.
const Enter = union(enum) {
    fresh: usize,
    load: usize,
    /// The map file to walk into, and where he stands when he arrives. The path is BORROWED from the map
    /// table's own storage, which outlives the transition.
    map: struct { path: []const u8, at: rl.Vector3, facing: f32 },
};
/// How long the screen takes to go down over the menu…
const ENTER_OUT: f32 = 0.40;
/// …and to come back up on the finished world. LONGER than the way out: arriving somewhere is worth more
/// time than leaving a menu is.
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
    vigil: knightmod.Vigil,
    swarm: leechmod.Swarm,
    haunt: shademod.Haunt,
    chests: chestmod.Chests,
    /// THE GLOWS — the second thing on the field that holds loot. No `init`: it owns no mesh (the prop grid
    /// draws the wisp), so unlike `chests` it is a plain defaulted field.
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
    /// INDEX-ALIGNED with the map's records. A field rather than a local: the dialog branch asks `triggerWorld`
    /// too, and it does not run the trigger pass that would rebuild it.
    npcPos: [npcmod.CAP]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** npcmod.CAP,
    nNpcPos: usize = 0,
    rest: restmod.Rest = .{},
    /// THE BOSS BAR'S FADE AND LAST-KNOWN FILL. The fill is kept because the bar outlives the body — it
    /// lingers, drains and fades over the corpse going to gold, when there is nothing left to read it off.
    bossK: f32 = 0,
    bossFrac: f32 = 0,
    /// …and THE SPIRIT TOAST'S, on exactly the boss bar's rule and for its reason: the panel outlives the
    /// body, so the life it shows has to be held here or the bar snaps to zero as the wolf goes.
    spiritK: f32 = 0,
    spiritHp: f32 = 0,
    /// Survives a death AND a load — the hour is a fact about the world, not about the map file.
    day: daynight.Clock = .{},
    /// THE HOUR THE TWO SHADERS WERE LAST SOLVED FOR. A NaN until one has been, so the first ask always lands
    /// (NaN compares equal to nothing, itself included) — see `applyHour` for what it saves.
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
    /// **THE CUT INTO A WORLD.** The screen goes black FIRST, the whole build happens on a frame nothing can be
    /// seen on, and only then does the picture come back. Two clocks and one act: fading OUT over the menu,
    /// the black frame the work happens on, and fading IN on a world that is already finished.
    enterOut: f32 = 0,
    enterIn: f32 = 0,
    enterAct: ?Enter = null,
    /// The UNSCALED frame time the drawing layer needs — the occluder fade would crawl on a time-scaled dt.
    /// `--shot` parks it at `shots.SETTLE_DT`: a still frame cannot show a fade, so a capture wants its END state.
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
        worldfmt.loadOrPanic(worldfmt.START_MAP, &g.map);
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

/// How far off black the fade has to be before a slot's thumbnail is worth taking — read off the fire's own
/// fade rather than a second clock beside it.
const SHOT_CLEAR: f32 = 0.02;

const BOOT_SPIN: f32 = 0.07; // radians a second
pub const BOOT_PITCH: f32 = 0.34; // …the two the HARNESS has to match, or it photographs a framing nobody sees
pub const BOOT_DIST: f32 = 7.2;

/// The one answer to "what is a fresh game" — `Game.init` and New Game both come through here. It touches no
/// mesh, material or model: those are built once and outlive any number of games.
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
    g.hero.flasks = .{};
    g.day = .{};
    g.bossK = 0;
    g.bossFrac = 0;
    g.spiritK = 0;
    g.spiritHp = 0;
    g.bag = .{};
    // **THE STARTING KIT IS ALREADY KNOWN**, and it goes in as KNOWN rather than through `awardLoot`: he begins
    // holding these, so the first one found in the world is the second he has owned. Without this, walking up to
    // a chest with a flask in it stops the game to introduce him to the flask on his own belt — and the whole
    // discovery set is a fact about the character, so it is set where the character is made.
    g.award = .{};
    for (STARTING_KIT) |k| {
        g.bag.add(k, 1);
        g.award.markKnown(k);
    }
    g.tree = .{};
    applyTree(g); // the sheet and the perks FIRST: the respawn below sizes his bars off them
    // Through the hero's own respawn, not `pos = …`: from a running game he may be mid-swing, mid-roll, in
    // the air, staggered or dying, and every one of those fields would survive into the new character.
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

/// **ARM THE CUT.** Nothing happens on the frame the button is pressed except the screen starting to go
/// down; the world is built once it is fully black (`enterNow`). Refused while one is already running, so a
/// second press during the fade cannot queue a second world behind the first.
fn beginEnter(g: *Game, act: Enter) void {
    if (g.enterAct != null) return;
    g.enterAct = act;
    g.enterOut = ENTER_OUT;
    g.enterIn = 0;
}

/// **THE BLACK FRAME.** Everything a world costs happens here, where nothing can be seen: the map read, the
/// ground and water uploaded, the props materialized, the spawns re-homed, the hero planted, the camera
/// placed and the hour pushed into both shaders. Only then does `enterIn` start lifting the black — so the
/// first frame the player sees is a world that is already finished, which is the whole of the rule.
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
                // A load that fails leaves you on the boot screen: dropping into the world anyway would be a
                // fresh character wearing a loaded game's name. The black lifts back onto the menu.
                g.shelf.head[i] = null; // …and the row goes dead, so it cannot be pressed again
                std.debug.print("LOAD FAILED: {s} is not a save this build can read\n", .{savemod.path(i)});
            }
        },
        .map => |m| enterMap(g, m.path, m.at, m.facing),
    }
    g.enterIn = ENTER_IN;
}

/// **WALKING FROM ONE MAP INTO THE NEXT.** The world is replaced and the CHARACTER is not: his bag, his
/// sheet, his souls, his flasks and his hour all come with him — what changes is the ground under him and
/// everything standing on it. `armScript` is what makes it a different world's script rather than the last
/// one's switches replayed against new indices.
///
/// It is deliberately NOT `loadGame`: that restores a character FROM a file, and this carries the one that is
/// already standing here into a different room.
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

/// **THE BLACK ITSELF, AND IT IS DRAWN OVER EVERYTHING.** Last in every branch that draws, chrome and menu
/// included: a fade with the HUD floating on top of it is a cut you can see through.
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

/// Which world a save belongs to, named ONCE — the shelf and the load have to agree or a slot lists as
/// loadable and then refuses.
fn saveMap(g: *const Game) []const u8 {
    _ = g; // one map today; the parameter is where a per-`Game` current map goes when there is more than one
    return worldfmt.START_MAP;
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

/// A load lands in a fresh world and then overwrites it, so an unreadable file leaves a startable world
/// behind rather than half of two. The order is the whole of it: `beginGame` sizes `chests.n` off the map
/// and rebuilds the trigger ORDER, both of which the file writes into and neither of which it carries.
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
    /// The widest range anything in this group notices him at. NO DEFAULT, so a new group cannot be added
    /// without saying how far it sees and silently stop being asked `markSight`.
    aggro: f32,
    /// Shouldered by the HERO. The ogre is not: he is too big to be walked out of the way.
    vsHero: bool = true,
    /// …and by these OTHER groups. DELIBERATELY ONE-WAY, or two bodies each half-correct and jitter.
    vs: []const []const u8 = &.{},
};
const FOE_GROUPS = [_]FoeGroup{
    .{ .field = "warren", .kind = .toad, .aggro = frogmod.AGGRO_R },
    .{ .field = "line", .kind = .archer, .aggro = archermod.AGGRO_R, .vs = &.{"warren"} },
    .{ .field = "grief", .kind = .ogre, .aggro = ogremod.AGGRO_R, .vsHero = false },
    .{ .field = "band", .kind = null, .aggro = koboldmod.AGGRO_R },
    .{ .field = "brood", .kind = null, .aggro = broodmod.AGGRO_R },
    .{ .field = "muster", .kind = null, .aggro = warriormod.AGGRO_R, .vs = &.{"line"} },
    .{ .field = "haunt", .kind = .shade, .aggro = shademod.AGGRO_R, .vs = &.{ "warren", "line", "muster" } },
    .{ .field = "swarm", .kind = .leechfly, .aggro = leechmod.AGGRO_R },
    // A fixture: nothing shoulders it off its spot and it shoulders nothing, because it never moves.
    .{ .field = "grove", .kind = .rooted, .aggro = rootedmod.AGGRO_R, .vsHero = false },
    .{ .field = "cluster", .kind = .shroom, .aggro = shroommod.AGGRO_R },
    .{ .field = "warrens", .kind = .delver, .aggro = delvermod.AGGRO_R },
    // It gives way to the bodies it is raising rather than the other way round: whatever it puts back up
    // has to be able to stand where it fell, and the caster is the one thing here that can afford to move.
    .{ .field = "rite", .kind = .necromancer, .aggro = necromod.AGGRO_R, .vs = &.{ "line", "muster" } },
    // The ogre's `vsHero`: far too much of him to be walked out of the way. The `vs` list is his own — the
    // skeletons keep the vigil with him, so they give way to him and he gives way to nothing.
    .{ .field = "vigil", .kind = .bone_knight, .aggro = knightmod.AGGRO_R, .vsHero = false, .vs = &.{ "line", "muster" } },
};

/// **THE ONE PASS OVER `FOE_GROUPS` THAT IS NOT A FOLD.** Everything else a group needs comes free from
/// `inline for (FOE_GROUPS)`; the blow it deals HIM cannot, because several groups take a spawn callback on
/// top of the blade and each sizes its felt beat off its own "was that the heavy" figure. So the calls are
/// hand-written one per row in `run` — and a NEW group would pick up every other pass and simply never hurt
/// the player, SILENTLY. The comptime block below is what holds the two tables level.
///
/// **A ROW PROMISES THE GROUP HAS A DAMAGE CHANNEL, not that it has a `heroTakes` call.** `line` is the one
/// that does not, and it is not an oversight: an archer's `update` hands back "it loosed", and the blow lands
/// where the ARROW does, off `g.arrows` in `run`.
const BLOW_GROUPS = [_][]const u8{
    "warren", "grief",  "line",    "band",    "muster", "haunt",
    "swarm",  "grove",  "cluster", "warrens", "vigil",  "brood",
    "rite",
};

comptime {
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
}

/// Is a fight on — the one predicate, and the only thing allowed to answer it. Sight is deliberately NOT
/// asked: it flickers as he rounds a corner, and a state that decides whether a menu works may not blink.
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
    // Meaningful only because `reachable` walks the fields rather than repeating them: pinning the order here
    // pins the PRESS, which it did not when the two were written out separately.
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(Reach.souls)); // the walk back for souls outranks all
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.talk)); // TAKE BEATS TALK (owner's)
    try std.testing.expect(@intFromEnum(Reach.pickup) < @intFromEnum(Reach.chest));
    // …and every row answers `inReach`, so a new one cannot be added without saying what reaches it.
    inline for (@typeInfo(Reach).@"enum".fields) |f| _ = @as(Reach, @enumFromInt(f.value)).prompt();
}

test "the ranges the fight is judged at are each GROUP'S OWN, never one figure for the field" {
    try std.testing.expect(frogmod.AGGRO_R < archermod.AGGRO_R);
    inline for (FOE_GROUPS) |gr| try std.testing.expect(gr.aggro > 0);
}

/// Whether a re-homed field starts with EYES on the hero. A loaded world is `.blind`; the shot harness is
/// `.seen`, since no game loop runs there to stamp eyes and a blind foe stands still.
const Sighted = enum { blind, seen };

fn rehomeFoes(g: *Game, sighted: Sighted) void {
    inline for (FOE_GROUPS) |f| {
        @field(g, f.field).reset(&g.map);
        if (sighted == .blind) {
            for (@field(g, f.field).live()) |*x| x.leash.blindNow();
        }
    }
}

/// Every list the game targets, walked ONCE: every row of `FOE_GROUPS` plus any SECOND list a group keeps on
/// the field (`liveExtraConst` — the brood's sacs, which are real targets with their own HP).
fn eachTarget(g: *const Game, ctx: anytype, comptime visit: anytype) void {
    inline for (FOE_GROUPS) |gr| {
        visit(ctx, @field(g, gr.field).liveConst(), gr.kind);
        // The extra list answers for its own members' kinds (`Sac.kind()`), so the row carries none.
        if (comptime @hasDecl(@FieldType(Game, gr.field), "liveExtraConst")) {
            visit(ctx, @field(g, gr.field).liveExtraConst(), @as(?FoeKind, null));
        }
    }
}

/// The array `live()` slices, found by MATCHING ITS ELEMENT TYPE — "the first array of structs with a `pos`"
/// sizes the snapshot to `POOL_CAP` the moment the brood's fields are re-ordered.
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
/// The drag reaches its slowest exactly at the wall — a second figure here would top out early or keep
/// deepening past the last step he can take.
const WADE_DEEP: f32 = envmod.WADE_MAX;
const WADE_SLOWEST: f32 = 0.8;

/// The SCROLL is here because the bell is an armament he starts able to equip: a summon he can select in the
/// book and then not use until he has walked to a chest is a slot that reads as broken.
const STARTING_KIT = [_]item.Kind{
    .spirit_scroll_wolf,
};

comptime {
    // `env` sits below `hero` in the import graph and writes both figures out literally; this file sees both
    // ends. 0.760·H is the thorax on the rig — the wading wall is chest height on him.
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

/// How far a creature's LOCK MARK swings off its own standing axis. Measured HORIZONTALLY: a mark pinned to
/// a height off the feet still rises and falls on a hop, so a vertical check passes whatever it is bolted to.
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

/// Two phases: he LEADS it at a pace it can follow, then he RUNS. `markSight` is stamped every frame — a
/// leash that only lets go when the hero happens to duck behind something is not a leash.
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

// Before this measured how far from its POST a creature got, every one ran to 2–5 times its own tether
// (the ogre 33.5 m on a 24 m leash, the shieldman 89.6 m on 26, the kobold 82.1 m on 22).
test "A SPIRIT'S JAWS MUST REACH THE BOTTOM OF WHAT IT IS SET ON — one sphere at a giant's chest is out of a wolf's world" {
    // Owner: the wolf struggles to get in range, things are too tall. `foe.reached` tests the biter's segment
    // against ONE hurt SPHERE at `centerWorld()`, so what decides whether a low animal can touch a tall
    // creature is entirely where the bottom of that sphere sits. Measured against the jaw's own height rather
    // than argued: the wolf's teeth are the blade, and they ride at wolf height whatever it is biting.
    var w = wolfmod.Wolf.spawn(mathx.zero3, 0);
    w.pose();
    const jaw = w.jawPoint().y - w.pos.y + 0.20 * w.scale; // the teeth, plus the blade's own radius
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    var snag = rootedmod.Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    var plate = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    std.debug.print("\n  wolf teeth reach {d:.2} m\n", .{jaw});
    inline for (.{ .{ "ogre", &giant }, .{ "rooted", &snag }, .{ "knight", &plate } }) |row| {
        const f = row[1];
        const floor = f.centerWorld().y - f.pos.y - f.hurtRadius();
        // …AND THE RANGE GATE IS THE OTHER HALF, which is the one that actually bites. `BITE_R` is a FLAT
        // number measured centre-to-centre, but the colliders hold the wolf `bodyR + its own` out — so on
        // anything broad the closest it can legally stand is already outside the range its bite asks for, and
        // it circles a creature it can never trigger on.
        const held = f.bodyR() + w.bodyR();
        const trigger = wolfmod.triggerR(f.bodyR()); // the gate as `update` actually asks it
        std.debug.print("  {s}: sphere floor {d:.2} (jaw gap {d:.2}) | held {d:.2} m out, bite triggers at {d:.2}\n", .{
            row[0], floor, floor - jaw, held, trigger,
        });
        try std.testing.expect(floor < jaw); // reachable in HEIGHT — every one of them is
        // …and the gate must be satisfiable from where the colliders let it stand. This is the half that fails.
        try std.testing.expect(held < trigger);
    }
}

test "THE BERSERKER IS THE FASTEST THING ON FOOT — and he closes at a RUN, not a stroll" {
    // Owner: the skel berserker should always run unless he is very close to you, and be faster than the
    // other skels too. He was the SLOWEST of them: a flat `WALK_SPEED * 1.22` = 2.07 m/s against a shieldman
    // charging at 2.92, so the one creature whose whole design is closing the gap could be walked away from.
    // Measured across the pair rather than argued, because the two speeds live in different files.
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
    // BACKING OFF ON FOOT MUST NOT SHAKE HIM, and a SPRINT must — that pair is the whole point of a rusher.
    try std.testing.expect(charge > heromod.RUN_SPEED);
    try std.testing.expect(charge < heromod.SPRINT_SPEED);
    // …AND HE WALKS THE LAST STRIDE IN. A charge carried to contact overshoots the swing it is closing for.
    try std.testing.expect(zerk.approachSpeed(0.0) < charge);
    // …which is what "very close" has to mean: inside his own reach and a stride, and no further out.
    try std.testing.expect(zerk.approachSpeed(koboldmod.AGGRO_R * 0.5) > heromod.RUN_SPEED);
    // …and out past his own world he is drifting home, which is a walk.
    try std.testing.expect(zerk.approachSpeed(koboldmod.AGGRO_R + 2.0) < heromod.RUN_SPEED);
    // The kiters keep their walk — a priest and a slinger are not trying to reach you.
    inline for (.{ koboldmod.Role.priest, koboldmod.Role.slinger }) |role| {
        const k = koboldmod.Kobold.spawnAs(role, mathx.zero3, 0, 1.0, 0.3);
        try std.testing.expect(k.approachSpeed(far) < heromod.RUN_SPEED);
    }
}

test "NOTHING CHASES FOREVER — every creature turns round at its own tether, not five times past it" {
    // It is still walking while it decides, so it cannot stop ON the line.
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
    // The BROOD MOTHER is slower than a walk, so she never leaves her post at all.
    var mother = broodmod.Spider.spawnAs(.mother, mathx.zero3, 0, 1.0, 0.3);
    const m = chase(&mother, heromod.WALK_SPEED, 90.0);
    try std.testing.expect(m.out < foemod.leashR(broodmod.AGGRO_R));
    // …and the LEECHFLY rides him the whole way because it is FEEDING: `noteCombat` is stamped every bite,
    // and a tether may not pull a creature off a fight in progress. What it owes is a prompt let-go after.
    var fly = leechmod.Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    const f = chase(&fly, heromod.WALK_SPEED, 90.0);
    try std.testing.expect(f.turned != null);
    try std.testing.expect(f.turned.? < 45.0 + LEASH_LETGO);
}
/// The sprint in `chase` starts at the halfway mark; this is how long after it a creature may still be coming.
const LEASH_LETGO: f32 = foemod.LEASH_CALM + 1.5;

test "STEERING IS ALL-OR-NOTHING PER CREATURE — the field and the question that stamps it cannot part company" {
    // Both failures are SILENT: a field with no `navWant` is never asked, and a `navWant` with no field
    // answers a question nobody puts to it.
    inline for (FOE_GROUPS) |gr| {
        const Ret = @typeInfo(@TypeOf(@FieldType(Game, gr.field).live)).@"fn".return_type.?;
        const M = @typeInfo(Ret).pointer.child;
        try std.testing.expectEqual(@hasField(M, "nav"), @hasDecl(M, "navWant"));
        // …and a steered creature is a GROUNDED one: the probe asks `walkStep`, which is the rule for feet.
        if (comptime @hasField(M, "nav")) try std.testing.expect(@hasDecl(M, "airborne"));
    }
    // The flyer is out BY DESIGN — see `markWays`. Pinned, or somebody reads it as an oversight and adds one.
    try std.testing.expect(!@hasField(leechmod.Leechfly, "nav"));
    try std.testing.expect(!@hasField(rootedmod.Rooted, "nav"));
    // The spirit is not in `FOE_GROUPS` and is stamped by hand in `tickPack`, so it is pinned by hand too.
    try std.testing.expect(@hasField(wolfmod.Wolf, "nav") and @hasDecl(wolfmod.Wolf, "navWant"));
}

test "THE JUMP IS SIZED AGAINST THE TERRAIN IT EXISTS TO CROSS, not against a number that looked right" {
    // `HEIGHT_STEP` is 0.25 m and a WALK takes two risers (`env.STEP_UP` 0.55), so the apex has to clear a
    // THIRD — and stay well under the wall the walk is rightly refused by, or it deletes the step rule.
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
    // The flyer answers both ways: flat on the deck, and tall once it has climbed out of sword reach.
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

/// The post-step terrain gate. Its rule is about the FEET and nothing else, so it takes anything with a
/// `pos` — the folk go through it too, and they carry no foe contract.
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

/// Deep water is a wall for him too, as a POST-STEP gate: the ROLL and the attack LUNGE travel by
/// `mathx.stepXZ` and never see `walkStep`, so without this a dive carries him into the deep. A HOLD, not a
/// slide — what reaches here is committed. Y is left alone; `groundActor` owns it.
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

/// The stick may bend the heading and nothing else — the speed was committed at takeoff — and the step goes
/// through `env.flyStep`, so he flies over what he is above.
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
    // LIT PASS ONLY: in the sun pass the materials are on the DEPTH shader, so this pushes a uniform at a
    // shader nothing is drawing with — and raylib re-binds the program to write one.
    if (cull == .view) g.scene.setFlash(0.6 * g.hero.hurtFlash);
    // At fade 0 every one of his ~20 meshes would draw a fully transparent fragment over a masked-off depth
    // buffer. Skipped, not drawn invisibly — the sun pass above still has him, so the shadow stays.
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
    // Null in the sun pass, for the hero's reason above: ten groups is ten wasted `glUseProgram` pairs a
    // frame before anything is even hit, and the brood adds one per sac and per spider on top.
    const flashPass: ?*gfx.Scene = if (cull == .view) &g.scene else null;
    inline for (FOE_GROUPS) |f| @field(g, f.field).draw(flashPass);
    g.folk.draw();
    // The spirit is thinned in the LIT pass only, so the sun pass still draws it solid and it CASTS.
    // The DEPTH MASK STAYS ON, unlike the see-through hero: he is thinned for a frame or two, where a spirit
    // is thinned for its whole life — with depth writes off, 27 bones blend over each other into a pile of
    // glass shards. Writing depth costs the far side of him and buys one silhouette.
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

/// A point `reach` metres down his facing, off that same centre — what a quick shot and a bolt are thrown at
/// when nothing is locked.
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

/// Noted here and SPENT AFTER `heroTakes` (`applyYank`): whether it moves him is the BLOW's fate, and
/// `Grove.update` calls this from inside its own walk, before anything has asked what the shield did.
pub fn noteYank(g: *Game, from: rl.Vector3, pull: f32) void {
    g.hook = .{ .from = from, .pull = pull };
}

/// Through `env.walkStep` like his own movement, so it cannot haul him up a cliff or through a wall.
/// Blocked, he keeps his ground — the boards are the one answer to a hook. A guard that BROKE travels.
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

/// Called wherever the MAP itself changes — a load, and every way out of the editor. NOT on a death: the
/// story he has already heard is not undone by dying, any more than his bag is.
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
    // …AND THE GLOWS, off the same index and on the same frames: both are props the editor can move, and a
    // pickup left homed to a world that has been re-materialized under it stands where nothing is.
    var glows: [pickupmod.CAP]pickupmod.Site = undefined;
    g.pickups.reset(glows[0..g.env.pickupSites(&glows)]);
    var fires: [restmod.CAP]restmod.Site = undefined;
    g.rest.reset(fires[0..g.env.restSites(&fires)]);
}

pub fn rehomeChestsForShot(g: *Game) void {
    rehomeChests(g);
}

/// The harness's own hooks. `--shot` runs no loop, so the pickup's reach ring and the award's queue have to be
/// driven by hand — and driven through the SAME calls the loop makes, or a portrait is of code nothing runs.
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

/// Read the front card, through the queue's own path — `clearPending` throws the held toasts away with it,
/// which is the one thing the shot after this is trying to photograph.
pub fn dismissAwardForShot(g: *Game) void {
    g.award.dismiss();
}

/// **THE TOASTS HAVE TO BE TICKED BEFORE THEY CAN BE PHOTOGRAPHED.** They slide in over `award.TOAST_IN`, so at
/// `t = 0` every one of them is parked exactly one width off the right edge — the first pass shot them the frame
/// they were made and came back with an empty screen and no error anywhere.
pub fn tickAwardForShot(g: *Game, secs: f32) void {
    g.award.update(secs);
}

/// Through each group's own `clear()` where it has one: zeroing `n` leaves everything a group owns besides
/// its members (the brood's sacs and acid) standing on the ground.
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
/// …and the wand's bolt WITH its release burst: the harness drives the pose past the `thrown` edge without
/// going through `throwBolt`, so it would otherwise capture a throw with none of the FX that fire on it.
pub fn throwBoltForShot(g: *Game, at: rl.Vector3) void {
    launchBolt(g, at, false);
}

pub fn stepShaftsForShot(g: *Game, dt: f32) void {
    stepShafts(g, dt);
}
/// One frame of the status, exactly as `run` bills it. The ORDER is the mechanic — dose, then resolve — so
/// a copy of it in `shots.zig` would be one that can go out of step.
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
    // The GROUND under the shaft, so it plants in a hillside instead of diving through to find y = 0 — and
    // the hero's centre off HIS ground, or an archer shooting up a bank aims at the hero's knees.
    archermod.stepArrow(ar, g.hero.pos, heroCenterY(g), g.env.groundAt(ar.pos.x, ar.pos.z), g.hero.iFramed(), arrowCover(g, ar, dt), dt);
}

/// Through the REAL mover: `hero.updateAir` is only the clocks and the pose, and the TRAVEL is
/// `moveHeroAir`'s, because what a jump may fly over is a question about the ground.
pub fn stepAirForShot(g: *Game, dt: f32) void {
    moveHeroAir(g, dt, .{}, null);
}

pub fn stepArrowsForShot(g: *Game, dt: f32) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) continue;
        flyArrow(g, ar, dt);
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
/// Called AFTER the world is down and BEFORE any chrome goes over it, so the picker shows him at the fire
/// rather than a menu. A post-draw gate rather than a decision at `justEntered`, because that edge is at the
/// bottom of the fade-in where the screen is still black.
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

/// THE FACE IN THE PANEL — built here rather than reached for by `dialog.zig`, which never learns what a
/// wanderer is (the `Leash`/`Root` rule: cross-cutting state is stamped IN). Null when a TRIGGER opened the
/// conversation rather than a body, because then there is nobody standing there to photograph.
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
/// THE SPIRIT'S FACE for the toast. Null once the body has gone, which is why the toast keeps its own fade
/// and its own last life: the panel outlives its subject by design.
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
/// Wind the spirit toast to FULL for the harness. Its fade is a live-loop clock, and `--shot` draws one
/// frame — waited out it photographs a panel halfway in, which says nothing about either end of it.
pub fn showSpiritToastForShot(g: *Game) void {
    g.spiritK = 1.0;
    g.spiritHp = if (g.pack.firstConst()) |w| w.vit.hpFrac() else 1.0;
}

pub fn stepFolkForShot(g: *Game, dt: f32) void {
    g.folk.update(dt, g.hero.pos, PLAY_HALF);
    for (g.folk.live()) |*p| plantActor(g, &p.pos);
}

const SHOT_STEP: f32 = @import("shots.zig").SHOT_DT;

/// What the button would reach this frame, in ORDER — the press and the PROMPT are the same question, and the
/// rings overlap. The DROP is first because you can die at a bonfire, and on the frame you walk back in there
/// is exactly one thing you came for; its ring is in fact the more generous of the two (`souls.REACH` 2.6 vs
/// `chest.REACH` 2.1).
///
/// **THE DECLARATION ORDER IS THE PRIORITY, AND IT IS THE ONLY PLACE THE PRIORITY IS WRITTEN.** `reachable`
/// walks these fields in order rather than repeating them as an if-chain: written twice, the list that reads
/// like the rule and the list that IS the rule can disagree without either looking wrong — which is exactly
/// what had happened, the comment here claiming the glow was last because its ring was the widest when the
/// bonfire's is wider. Moving a row moves the press now.
const Reach = enum {
    souls,
    rest,
    /// **TAKE BEATS TALK** (owner's call). A glow and a wanderer answer at exactly the same 2.4 m
    /// (`pickup.REACH`, `npc.REACH`), so standing between them the order is the whole of the answer — and
    /// picking a thing up off the ground is over in one press, where a conversation you did not mean to start
    /// has to be backed out of.
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

/// Is THIS one in reach — one row, one answer, and the switch is exhaustive so a new kind of interaction
/// cannot be added without saying what puts it in reach.
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

/// One button, one priority order (`reachable`): you can be in reach of two, and the answer must not depend
/// on which system happened to be asked first.
fn interact(g: *Game) void {
    switch (reachable(g) orelse return) {
        .souls => reclaimSouls(g),
        .rest => _ = g.rest.begin(),
        .pickup => takePickup(g),
        .talk => _ = startTalk(g),
        .chest => openChest(g),
    }
}

/// Three things have to be true and they live in three places — the SCROLL is in the bag (game's), there is
/// ROOM (the field's), the FOCUS covers it (his) — asked in that order so the pool is never spent on a
/// ringing that was going to be refused. Only the focus refusal may light the focus bar; the other two are
/// facts nowhere on the HUD, so they are SAID.
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

/// On the frame the bell actually sounds (`hero.rang`). It comes up BESIDE him and a little behind — in front
/// and it is standing in the swing he is about to take.
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

/// Taken BEFORE `Pack.update`, so the frame it arrives on is one it walks normally out of — done after, the
/// terrain gate measures the whole jump as one step and refuses it. No shake or rumble, unlike the bell:
/// those are the receipt for thirty focus, and nothing was spent here.
fn rematerialize(g: *Game, w: *wolfmod.Wolf) void {
    const at = spiritSpot(g);
    w.reappear(at, g.hero.facing);
    sfx.world(.wolf_growl, at);
}

/// The spirit never reaches for the foe list — the quarry is STAMPED. The creature owns a point; only this
/// file knows what is on the field.
fn tickPack(g: *Game, dt: f32) void {
    if (g.pack.n == 0) return;
    // READ BEFORE `pack.update` WIPES THEM: `Wolf.update` clears every one-frame edge at the top of its body,
    // so `yelped`/`justDied` are always false below it. `bit`/`growled` are set inside it and survive.
    for (g.pack.live()) |*w| {
        if (w.yelped) sfx.world(.wolf_hurt, w.pos);
        if (w.justDied) sfx.world(.wolf_die, w.pos);
    }
    for (g.pack.live()) |*w| if (w.lost()) rematerialize(g, w);
    for (g.pack.live()) |*w| {
        w.quarry = huntFor(g, w);
        // Stamped here rather than in `markWays`: the spirit is not in `FOE_GROUPS` and its errand is not the
        // hero's position — but it is the same prober, and a second would be a second answer to "walkable".
        if (w.navWant(g.hero.pos)) |want| markWay(g, &w.nav, w.pos, w.bodyR(), want) else w.nav.dir = null;
    }
    g.pack.update(dt, g.hero.pos, PLAY_HALF);
    var was: [combat.SUMMON_MAX]rl.Vector3 = undefined;
    for (g.pack.liveConst(), 0..) |*w, i| was[i] = w.wasAt; // …read off the creature, so the indices align
    gateTerrain(g, g.pack.live(), was[0..g.pack.n]);
    for (g.pack.live()) |*w| {
        // NOT GROUNDED HERE: `pos.y` has ONE writer, `groundActor` at the end of the frame. Taken a second
        // time here the spirit climbs rising ground at twice `GROUND_RISE_RATE`.
        if (w.bit) sfx.world(.wolf_bite, w.pos);
        if (w.growled) sfx.world(.wolf_growl, w.pos);
        w.jaw1 = w.jawPoint();
        // The jaws go through the same swept test the hero's sword does — a summon with its own hit path
        // would be a second definition of what "reached" means.
        const b = w.blade();
        if (b.active and !w.hitLatch and pierceFoes(g, b)) {
            w.hitLatch = true; // one bite, one body
            sfx.play(.hit_light);
        }
    }
}

/// **A BODY'S IDENTITY AS ONE NUMBER** — the same `(kind, index)` pair a `FoeRef` is, packed so a spirit can
/// carry it without learning what a `FoeKind` is. `game.zig` mints it and `game.zig` reads it back; the
/// creature only holds it (`wolf.Quarry.key`, the `foe.Leash` arrangement).
fn quarryKey(kind: FoeKind, idx: usize) u32 {
    return (@as(u32, @intFromEnum(kind)) << 16) | @as(u32, @intCast(@min(idx, 0xFFFF)));
}

/// The thing worth killing, or null to heel — **AND IT PREFERS THE FIGHT IT IS ALREADY IN.** What it is on is
/// re-found by KEY and kept at `wolf.HUNT_KEEP` × the rings; only when that body is gone does the
/// nearest-search run. `foe.Threat`'s hysteresis on the other side of the field — without it two bodies at
/// similar range trade the target every frame, and a quarry dropped to null means HEEL, which is the animal
/// turning to look at the player mid-chase.
///
/// Written against the SPIRIT and not the wolf, so a second one inherits it by carrying a `quarry` field.
fn huntFor(g: *const Game, w: *const wolfmod.Wolf) ?wolfmod.Quarry {
    const from = w.pos;
    // HE COMES FIRST: past the recall ring there is no quarry at all. Asked before the walk rather than as
    // another rejection inside it — this is "I am too far from him", not "is that body worth it".
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
                // Never a tree that is still a tree: biting a dormant Rooted gives the disguise away for
                // nothing, and `foe.reached` rouses it on the way.
                if (disguised(f)) continue;
                // …and never a FLYER (owner's call): jaws are not the answer to something that leaves the
                // ground, and a wolf hopping under a leechfly reads as broken.
                if (comptime @hasDecl(T, "airborne")) {
                    if (f.airborne()) continue;
                }
                const key = quarryKey(memberKind(f, kind), i);
                const d = mathx.distXZ(self.from, f.pos);
                const out = mathx.distXZ(self.hero, f.pos);
                // THE BODY IT IS ALREADY ON, held to the WIDER rings. It is still standing, it is still
                // reachable, and it is still in the player's fight — so it stays its fight.
                if (key == self.held and d <= wolfmod.HUNT_R * wolfmod.HUNT_KEEP and out <= wolfmod.TETHER_R * wolfmod.HUNT_KEEP) {
                    self.keep = .{ .at = f.pos, .r = f.bodyR(), .key = key };
                    continue;
                }
                // …and a body the HERO has walked away from is not this spirit's problem either.
                if (out > wolfmod.TETHER_R) continue;
                if (d >= self.best) continue;
                self.best = d;
                // …AND HOW BROAD IT IS, which is what the bite gate is measured off.
                self.at = .{ .at = f.pos, .r = f.bodyR(), .key = key };
            }
        }
    };
    var ctx = Ctx{ .from = from, .hero = g.hero.pos, .held = w.quarryKey() };
    eachTarget(g, &ctx, Ctx.visit);
    // THE COMMITMENT WINS. Only when the body it was on has died, dissolved, gone under or left the fight
    // does the search below it get to say anything.
    return ctx.keep orelse ctx.at;
}

/// The RING GIVES FIRST (DS's Ring of Sacrifice): one snaps and he keeps the lot. Otherwise everything comes
/// off him onto the spot he fell on, and whatever was standing there already is GONE.
fn spillSouls(g: *Game) void {
    if (bindingInBag(&g.bag)) |ring| {
        _ = g.bag.take(ring, 1);
        g.hero.quick.dropEmpty(&g.bag);
        sfx.play(.ring_snap);
        g.trig.say("The Soul Binding Ring snaps.");
        return;
    }
    // ALWAYS through `spill`, even carrying nothing: 0 clears the drop, where returning early left the
    // PREVIOUS death's stain standing.
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

/// Instant (owner's call): no committed action and no animation. The gold crossing to his chest is the
/// effect catching up with something that has already happened.
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

/// **THE GLOW'S PICTURE, STAMPED ONTO ITS PROP.** The runtime pickup owns the state and the prop grid owns the
/// drawing, and the two are the same slot (`env.setPickupDraw`) — so this is the `markSight` arrangement one
/// more time: the thing that knows says, and the thing that draws is told.
fn hidePickups(g: *Game) void {
    for (g.pickups.live(), 0..) |*p, i| g.env.setPickupDraw(i, p.sizeLeft(), p.spent());
}

/// **EVERYTHING THAT HANDS THE PLAYER ITEMS COMES THROUGH HERE.** The bag and the NOTICE are one act: a chest
/// that added to the bag without telling the award set would silently spend a kind's one first-time card, and
/// the next copy found would card instead — which is the same fact said in the wrong order, months later.
///
/// The voice fires ONCE for the whole handful rather than per item: three runes out of one box is one sound.
fn awardLoot(g: *Game, loot: []const item.Kind, at: rl.Vector3) void {
    for (loot) |it| {
        g.bag.add(it, 1);
        g.award.gain(it);
    }
    if (loot.len > 0) sfx.world(.item_get, at);
}

/// What the conditions are allowed to see, gathered once and handed IN — the machine never reaches into the
/// game for a foe list.
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

/// `justDied` is the contract's one-frame edge and the only honest source for a COUNT — a latch like the
/// sac's `killed` reads true every frame after, so the brood counts its own instead.
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

/// The conversation the machine may ask for is opened HERE rather than inside it — a dialog needs a SPEAKER's
/// name, and the machine has no business knowing what an NPC is.
fn tickTriggers(g: *Game, dt: f32) void {
    g.nNpcPos = g.folk.positions(&g.map, &g.npcPos).len;
    billDeaths(g);
    // A bonfire counts as busy too: `run` checks the rest branch BEFORE the talk one, so a conversation
    // opened on the frame a rest begins would be frozen rather than deferred.
    const want = g.trig.tick(&g.map, triggerWorld(g), dt, g.talk.active() or g.rest.active()) orelse return;
    // A refused open is a conversation that closed at once — the machine latched the trigger when it handed
    // the id up and only a close lets go, so a tree with no nodes would wedge that action list.
    if (!g.talk.open(&g.map, &g.trig, want, "", null)) g.trig.dialogClosed();
}

/// Refused — and the prompt not offered — when the map gave him no conversation: a "Talk" that does nothing
/// is worse than no prompt at all.
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

/// A dialog is a MENU as far as the loop is concerned: the hero is `held`, and the only clocks that run are
/// the panel's own.
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

/// Every pad binding is DERIVED from the name the cribs draw (`hud.BTN_*` → `hud.padOf`), so a rebind moves
/// the press and the glyph together. The keyboard mirrors the pad letter for letter where it can.
const INTERACT_PAD: rl.GamepadButton = hud_.padOf(hud_.BTN_INTERACT);
const INTERACT_KEY: rl.KeyboardKey = .y;
const QUICK_PAD: rl.GamepadButton = hud_.padOf(hud_.BTN_QUICK);
const ARROW_KEY: rl.KeyboardKey = .u;
/// L2 ON THE KEYBOARD — see the L2 block in `run` for why the mouse cannot carry it.
const PARRY_KEY: rl.KeyboardKey = .c;
/// The keyboard cannot mirror the pad's A here — A is strafe-left — so the jump takes a key of its own.
const JUMP_PAD: rl.GamepadButton = hud_.padOf(hud_.BTN_JUMP);
const JUMP_KEY: rl.KeyboardKey = .v;

/// The panel takes INTERACT on top of the menu confirm, so the button that opened a conversation walks
/// through it. It cannot go into `menumod.confirmPressed`: that is the book's own Confirm.
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
        // Sitting down IS the save, and this is the only line that writes one. AFTER `sit`, never before:
        // `sit` runs `makeWhole`, so the file is written by a character already full — which is why
        // `save.Data` carries no bars, flasks or quivers.
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
        // The tree hands back what it charged rather than reaching for the counter itself; this is the only
        // line in the game that spends souls.
        .take => |i| {
            const paid = g.tree.take(i, g.hero.souls.total) orelse return;
            g.hero.souls.total -= paid;
            g.hero.souls.shown = @floatFromInt(g.hero.souls.total); // it went DOWN: nothing rolls to a smaller number
            applyTree(g);
            sfx.play(.souls_take);
        },
        // A jump, not a fast-forward: nothing in the world runs while he sits. Always FORWARD (`hoursUntil`),
        // so asking for the hour you are already on costs a whole day. Nothing is restocked — `hero.sit` made
        // him whole the moment he sat down.
        .wait => |u| {
            g.day.set(g.day.hour + daynight.hoursUntil(g.day.hour, u.hour()));
            applyHour(g);
            sfx.play(.menu_pick);
            g.rest.leave();
        },
    }
}

/// A rest no longer touches the LIGHT (owner's call) — the only thing at a bonfire that moves it is the row
/// that asks for an hour.
fn applyStow(g: *Game) void {
    g.env.stowed = g.hero.resting;
}

/// Taken BEFORE the depth pass every frame: `Scene.setHour` moves `gfx.sun` and the shadow box is built off
/// that, so pushed after it a frame's shadows are cast by the previous frame's sun.
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
    // …AND THE AMBIENCE, which is the same fact reaching a third consumer: the crickets belong to the night
    // and the birds to the day. `audio.zig` knows nothing about an hour, so it is handed the one number.
    sfx.setDaylight(daynight.dayAmt(g.day.hour));
}

/// The harness never runs the loop that pushes the hour, so setting the clock without this photographs a
/// sequence under whatever the last frame was lit by.
pub fn pinHourForShot(g: *Game, hour: f32) void {
    g.day.set(hour);
    g.day.freeze(true);
    applyHour(g);
}

const REST_WARMTH: f32 = 0.14;
/// Metres the seat view pans left, MEASURED AGAINST THE MAN at ~4.4 m — not against the FIRE at 2.6 m, which
/// slides more than twice as far for the same pan. Solved off the fire, 1.55 m carried him off the edge.
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
    // A PAN — eye AND target by the same vector, since swinging the target alone turns the camera and shears
    // the composition. Screen-right on this handedness is world (−fwd.z, 0, fwd.x) — `camera.rightXZ`'s law.
    const fwd = mathx.subV(g.rig.cam.target, g.rig.cam.position);
    const right = mathx.normV(v3(-fwd.z, 0, fwd.x));
    const shove = mathx.scaleV(right, -REST_PAN);
    g.rig.cam.position = mathx.addV(g.rig.cam.position, shove);
    g.rig.cam.target = mathx.addV(g.rig.cam.target, shove);
}

fn poolPut(g: *Game, a: archermod.Arrow) void {
    putIn(&g.arrows, a);
}

/// A full pool overwrites its OLDEST, and a PLANTED shaft goes before one still in the air: a stuck arrow is
/// scenery on a fade timer, where one in flight is a blow that has not landed.
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

/// EXHAUSTIVE, so a third spell is a compile error here rather than a cast that plays its whole animation and
/// throws nothing.
fn releaseSpell(g: *Game) void {
    switch (g.hero.spell) {
        .bolt => throwBolt(g),
        .roots => castRoots(g),
        // …and the third does not RELEASE anything: the edge opens a window, and `rimeBreathe` bills it for
        // as long as the cone is open.
        .rime => openBreath(g),
    }
}

/// At the LOCKED foe if there is one, down his facing otherwise — the QUICK shot's rule, since there is no
/// aimed cast and so no camera ray to converge on.
fn throwBolt(g: *Game) void {
    const locked: ?rl.Vector3 = if (activeLock(g)) |li| foeLockPoint(g, li) else null;
    // Loft only against a REAL point, `looseShaft`'s rule: it is solved against the distance to the target.
    launchBolt(g, locked orelse forwardPoint(g, heromod.BOLT_REACH), locked != null);
    sfx.play(.wand_cast);
    g.rumble.play(rumblemod.cast_throw);
    g.rig.addShake(SHAKE_CAST);
}

/// Metres down his facing the ground splits when nothing is locked — on the GROUND rather than at chest
/// height, unlike the bolt's fallback, because roots come out of the earth.
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

/// Takes exactly ONE foe — a swing is the only thing in the game that reaches more than one body — and
/// ROUSES it. Returns the earth it actually split, the victim's own feet rather than the thrown mark.
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

/// THE BREATH OPENS — and that is ALL this does. The other two spells throw something on this edge and are
/// finished with; the rime's edge is the start of a WINDOW, and what the window does is billed a frame at a
/// time in `rimeBreathe` for as long as `hero.breathLive()` says the cone is open.
fn openBreath(g: *Game) void {
    sfx.play(.wand_cast);
    g.rumble.play(rumblemod.cast_throw);
    g.rig.addShake(SHAKE_CAST);
}

/// **ONE FRAME OF THE CONE, ON EVERY BODY STANDING IN IT — AND IT IS THE FIRST THING IN THE GAME BAR A SWING
/// THAT REACHES MORE THAN ONE** (owner's call; it overturns the standing law and AGENTS.md is written to
/// match). What makes that fair is that it is not a blast at a mark: it is a direction he is holding, in
/// front of him, for the better part of a second — so it is aimed, it is dodged by not being in front of
/// him, and a body walks out of it exactly the way a body walks out of a swing.
///
/// **TESTED IN XZ, LIKE EVERY OTHER REACH IN THE GAME.** `hero.breathDir` is level for this reason: the
/// picture may not promise an up or down the mechanic does not have.
fn rimeBreathe(g: *Game, dt: f32) void {
    const apex = g.hero.breathMouth();
    const facing = g.hero.facing;
    inline for (FOE_GROUPS) |f| {
        for (@field(g, f.field).live()) |*a| {
            if (!foemod.corporeal(a)) continue;
            // **THE BODY'S OWN WIDTH COUNTS**, at both ends of the test: a giant whose centre is a foot past
            // the reach is still standing in the stream, and one whose centre is just outside the arc is
            // still four feet of creature inside it. Measured off `bodyR` rather than a fudge, so a scaled
            // creature is answered at the size it was actually posted at.
            const d = mathx.distXZ(a.pos, apex);
            const r = a.bodyR();
            if (d - r > combat.RIME_REACH) continue;
            const to = mathx.dirXZ(apex, a.pos);
            if (mathx.lenXZ(to) > 1e-4) {
                // How much of the arc this body subtends from where he is standing — degrees, `withinArc`'s
                // unit. Stood inside him there is no bearing to be wrong about and the breath simply takes
                // him, which is the delver's zero-bearing rule one mechanic along.
                const spread = if (d > r) combat.subtendedArc(r, d) else 180.0;
                if (!combat.withinArc(mathx.headingXZ(to), facing, combat.RIME_ARC + spread)) continue;
            }
            // THE COLD AND THE COLD'S DAMAGE ARE ONE STAMP (`combat.Chill.breathe`), collected by the body
            // itself through `foe.grip` — a bite that kills has to arrive down the creature's own path.
            a.chill.breathe(dt);
            a.leash.provoke(); // breathed on IS being fought, whatever it was doing before
        }
    }
}

/// **THE CHILL'S POST-STEP GATE — the roots' law, applied by fractions.** `foe.grip` takes the feet outright;
/// this takes part of them, and it is the same gate in the same place for the same reason: a creature grows
/// movements, and a per-site multiplier is a list of sites to forget one from.
///
/// **IT TAKES THE FEET AND NOTHING ELSE.** The state machine still runs, the kit still swings at its own
/// speed and the blows land as hard — a chilled creature is not a slowed creature, it is one that cannot
/// close. That is deliberately NOT time dilation: this game does not take time away from anybody.
///
/// Keyed off the creature's own `chill` field (`markWays`' rule), so a creature gains it by carrying the
/// field and never by an edit here. **AND IT IS NOT SKIPPED FOR A FLYER**, which is the one place it parts
/// company with the terrain gate beside it: cold does not care whether you are standing on anything, and
/// that is exactly what makes it the answer to a leechfly the roots cannot touch.
fn gateChill(foes: anytype, was: []const rl.Vector3) void {
    const T = @typeInfo(@TypeOf(foes)).pointer.child;
    if (comptime !@hasField(T, "chill")) return;
    for (foes, 0..) |*f, i| {
        // THE CLOCK IS NOT RUN HERE. `foe.grip` ticks it at the top of the creature's own update, where the
        // bite it owes can be billed and can KILL — run again here it would decay at twice the rate and
        // swallow a frame of cold on its way past.
        if (i >= was.len or !f.chill.held()) continue;
        // What it actually travelled this frame, scaled back to what a cold body manages. Y is left alone —
        // `groundActor` owns it, and a chilled foe stands on its own ground like a held one.
        f.pos.x = was[i].x + (f.pos.x - was[i].x) * combat.CHILL_TRAVEL;
        f.pos.z = was[i].z + (f.pos.z - was[i].z) * combat.CHILL_TRAVEL;
    }
}

/// `throwBoltForShot`'s twin: the pose is driven past the `thrown` edge without going through `releaseSpell`.
pub fn castRootsForShot(g: *Game) rl.Vector3 {
    const at = rootMark(g);
    return seedRoots(g, at) orelse at;
}

/// The GEOMETRY of a release only. Sound, pad and shake stay with the caller: those are live-loop only, and a
/// shake in `--shot` costs determinism.
fn launchBolt(g: *Game, target: rl.Vector3, loft: bool) void {
    const from = g.hero.wandTipWorld();
    putIn(&g.shafts, archermod.launchShaft(from, target, heromod.BOLT_SPEED, g.hero.castBlow(), loft, .bolt));
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
///
/// **AND IT IS ONE RING FOR EVERY CREATURE ON PURPOSE, WHICH IS WHAT IT COSTS.** At 25 m (the archer's 24 plus
/// one) a dormant Rooted whose whole world is 6.8 m still pays a full `env.sees` — an AABB sweep of the solid
/// grid from the eye to its skull — every frame, for a distance `foe.sensedDist` then throws away. Narrowing it
/// to each group's own `aggro` is one line and is NOT free: `Leash.blind` is a MEMORY (`SIGHT_MEMORY`), so a
/// creature that watched him walk past from out here would start going blind out here instead. The ring is the
/// correctness half; this is the bill.
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
/// RADIANS it will give up off the line it wanted, TRIED NEAREST-FIRST. The last is past square, which is
/// what lets a body walk back out of a pocket instead of standing in the corner of one.
const WAY_FAN = [_]f32{ 0.45, 0.90, 1.40, 1.95, 2.50 };
/// How straight a step must come out to count as TAKEN: `env.walkStep` answers a refusal by SLIDING along the
/// slope, and that slide travels the full distance asked for, so a distance-only probe calls it clear.
const WAY_TRUE: f32 = 0.98;

fn wayClear(g: *const Game, at: rl.Vector3, r: f32, dir: rl.Vector3) bool {
    const reach = WAY_PROBE + r;
    const went = mathx.dirXZ(at, g.env.walkStep(at, dir, reach));
    if (mathx.lenXZ(went) < 1e-4) return false; // the terrain (or the deep) refused it outright…
    if (went.x * dir.x + went.z * dir.z < WAY_TRUE) return false; // …or slid it somewhere it did not ask for
    // …and the world's SOLIDS, which the terrain rule knows nothing about. Sampled at the MIDDLE of the probe
    // as well as its end, or anything thinner than the reach sits between the two and is walked through.
    for ([2]f32{ 0.5, 1.0 }) |u| {
        const p = v3(at.x + dir.x * reach * u, at.y, at.z + dir.z * reach * u);
        if (mathx.distXZ(g.env.resolveActor(p, r, at.y), p) > 1e-3) return false;
    }
    return true;
}

/// The straight line is tried first and nearly always wins, in which case the stamp is cleared — this can
/// only ever bend a heading the world has already refused.
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

/// Keyed off the creature's own `nav` field, so gaining steering is a field and a `navWant` and never an edit
/// here. A FLYER IS NEVER STEERED: the probe asks `walkStep`, which is the rule for feet, and it would refuse
/// a leechfly the bank it is entitled to fly straight over.
fn markWays(g: *Game) void {
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            const M = @TypeOf(f.*);
            if (comptime !@hasField(M, "nav")) continue;
            if (!foemod.corporeal(f) or f.airborne()) {
                f.nav.dir = null;
                continue;
            }
            // Asked about whoever it is actually FIGHTING (`Threat.aim`), never about the hero: one that had
            // gone for the spirit would be steered on a line to a man it stopped chasing.
            const want = f.navWant(f.threat.aim(g.hero.pos)) orelse {
                f.nav.dir = null;
                continue;
            };
            markWay(g, &f.nav, f.pos, f.bodyR(), want);
        }
    }
}

/// Who every creature on the field is fighting, STAMPED — run BEFORE anything decides what to do about
/// anybody, with the sight and the shield.
fn markThreat(g: *Game, dt: f32) void {
    const spirit: ?rl.Vector3 = blk: {
        const w = g.pack.firstConst() orelse break :blk null;
        // A DYING spirit has stopped being worth fighting — without this the field swings at motes for a
        // second and a half.
        if (!foemod.corporeal(w)) break :blk null;
        break :blk w.pos;
    };
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            const M = @TypeOf(f.*);
            // A FLYER IS NEVER HANDED THE SPIRIT: the wolf cannot reach it (`wolf.blade` stops at the hop's
            // own height), so a leechfly that chose it would be drinking from something that never answers.
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

/// Keyed off the group's own `setParry`, so a creature gaining windows is a field, a predicate and two group
/// methods — never an edit here.
fn markParry(g: *Game) void {
    const p = foemod.Parry{ .live = g.hero.parryLive(), .at = g.hero.pos, .facing = g.hero.facing };
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

/// **WHICH CORPSES ARE BEING HELD OPEN, and by whom.** Stamped once a frame, before anything decides — the
/// `markSight`/`markParry` arrangement and for their reason: a corpse is in another group's array, and a
/// creature may never reach out for the world.
///
/// Keyed off `@hasDecl(Member, "raisable")`, so a third raisable body is a `raisable`/`reraise` pair on that
/// creature and never an edit here (`markWays`' rule); a test pins both halves, which fail silently.
///
/// **A PLACE, NOT A RESERVATION.** Every flag is cleared first and re-earned from where the bodies lie, so
/// walking the fight out of a necromancer's reach releases the corpses on the frame it happens. **AND TWO
/// CANNOT CLAIM ONE BODY** — a corpse already stamped this frame is skipped, so the flag IS the claim.
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
        // **MID-CAST IT HOLDS THE BODY IT COMMITTED TO** rather than re-picking the nearest every frame. The
        // spot was latched when the gather began (`necro.enter`), so the search is a tight one about THAT
        // point: a 1.9 s tell that swung onto a fresher corpse would be a tell that lied about where.
        const from = if (k.casting()) k.raiseAt else k.pos;
        const reach = if (k.casting()) necromod.RAISE_MATCH_R else necromod.RAISE_R;
        const ref = nearestRaisable(g, from, reach, .skip) orelse continue;
        k.vigil.at = ref.at;
        // …and THAT body is flagged, by SLOT: `heldOpen` is also the claim, so the next necromancer's own
        // search skips it and a pair cannot spend two casts on one skeleton.
        withRaisable(g, ref, {}, struct {
            fn v(_: void, f: anytype) void {
                f.heldOpen = true;
            }
        }.v);
    }
}

/// **A BODY ON THE FIELD, BY SLOT** — which row of `FOE_GROUPS` and which member of it. An INDEX and not a
/// pointer, because the member types differ per row and no one variable can hold two of them; and not a
/// POSITION, because matching a corpse back by where it lies flags both of two that fell on the same spot.
const BodyRef = struct { group: usize, idx: usize, at: rl.Vector3 };

/// Every body a necromancer could use, visited once. Keyed off `@hasDecl(Member, "raisable")`, so a third
/// raisable creature is a `raisable`/`reraise` pair on that creature and never an edit here (`markWays`' rule).
fn eachRaisable(g: *Game, ctx: anytype, comptime visit: anytype) void {
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*f| {
            if (comptime !@hasDecl(@TypeOf(f.*), "raisable")) continue;
            visit(ctx, f);
        }
    }
}

/// **THE NEAREST UNCLAIMED BODY TO A POINT, and the ONE definition of that search.** `markVigil` (hold it open)
/// and `applyRaises` (stand it up) are the same question asked at two moments, and as two copies they had
/// already drifted apart in both directions: one re-found its answer by comparing POSITIONS afterwards, and the
/// other raised whichever corpse it happened to meet first while carefully tracking a distance it then ignored.
/// `claimed` is the one thing the two callers disagree about, so it is an ARGUMENT rather than two functions:
///   `.skip` — `markVigil` looking for a body to take, where a held one is somebody else's already
///   `.take` — `applyRaises` reading back the body this necromancer is itself holding
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

/// …and the one body that ref names, handed to a visitor. The slot walk mirrors `nearestRaisable`'s exactly,
/// which is what makes a ref mean the same thing to both.
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

/// **THE RAISE ITSELF, and it happens HERE because it cannot happen anywhere else.** The necromancer reports
/// a one-frame `raised` and the point it was standing over (`necro.raiseAt`); the body is in another group,
/// in another array, of another type, and this is the only place that can see both.
///
/// It is `justDied`'s arrangement exactly, one direction along: the creature says what happened and the game
/// does what that means.
fn applyRaises(g: *Game) void {
    for (g.rite.live()) |*k| {
        if (!k.raised) continue;
        // The body it was POINTING AT — the nearest to its own mark, which is the same search `markVigil` ran
        // to claim it. `.take`, because the body this necromancer is holding is precisely the one that IS
        // claimed: with `.skip` the raise would look straight past its own corpse at whatever lay behind it.
        //
        // **A CAST THAT FOUND NOTHING IS STILL SPENT** (the cooldown was stamped at the turn), and that is the
        // reading the player is owed: the body it was reaching for was already gone, so the gather they watched
        // bought nothing. Nothing to report and nothing to correct.
        const ref = nearestRaisable(g, k.raiseAt, necromod.RAISE_MATCH_R, .take) orelse continue;
        withRaisable(g, ref, {}, struct {
            fn v(_: void, f: anytype) void {
                f.reraise(necromod.RAISE_HP_FRAC);
            }
        }.v);
        // A DEAD THING STANDING UP IS FELT. Under the beats a landed blow gets — nothing has hit him — and
        // over the scenery, because what just happened is the last thirty seconds coming back.
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

/// What a landed projectile leaves behind, asked in ONE place: the two callers — it reached him, it reached
/// anything else — were already drifting apart.
fn splashOf(g: *Game, ar: *const archermod.Arrow) void {
    const ground = v3(ar.pos.x, g.env.groundAt(ar.pos.x, ar.pos.z), ar.pos.z);
    switch (ar.shot) {
        .venom => g.brood.splash(ground),
        .clump => g.band.splash(ar.pos), // at the CONTACT, not the floor: it can burst against a chest
        .bolt => g.hero.boltBurst(ar.pos, ground.y, g.hero.casts),
        // The crock's gap is deliberate, until the owner picks what lightning landing looks like.
        .arrow, .firearrow, .wisp, .crock => {},
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
    if (!g.editor.on) return g.hero.pos;
    const t = g.editor.cam.target;
    return v3(t.x, g.env.groundAt(t.x, t.z), t.z);
}

/// **THE LIGHTS THAT ARE NOT IN THE WORLD**, gathered in the order they matter — the wand in his hand first,
/// then every rune ring standing on the ground. `env.uploadLights` gives these reserved slots so a brazier
/// cannot evict them, and takes at most half the rack, so ORDER is what decides on a crowded field: what he
/// is holding outranks what is being done to him.
///
/// **SIZED TO WHAT CAN BE USED, NOT TO WHAT CAN EXIST.** `uploadLights` keeps at most half the rack whatever
/// it is handed, so a buffer holding one per possible necromancer (25) spent twenty-four `sigilLight` calls a
/// frame building lights nobody could ever be shown. Filling exactly the half means the same eight win —
/// order is what decides either way — for a third of the work and none of the stack.
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
    // Before either pass, since the marks are read by the draw loop both go through. In the editor the line
    // is degenerate on purpose — see `markOccluders`.
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

/// HOW LONG THE CHROME TAKES TO GO once he is dead (owner: fade it away instead of removing it immediately).
/// Read off `hero.deathT`, which is the clock the YOU DIED card itself is drawn from — an effect's clock is
/// DERIVED from the mechanic's, never parallel to it, or the two eventually disagree about when he died.
/// Short of the card's own first beat (`smoothstep(0.03, 0.30)` of `DEATH_DUR`), so the bars are on their way
/// out before the screen starts to dim rather than fading underneath it.
pub const HUD_FADE_DUR: f32 = 0.55;

/// …and what the chrome is worth this frame: 1 alive, easing to 0 across the fade once he is down.
fn chromeFade(g: *const Game) f32 {
    if (!g.hero.dead) return 1;
    return 1.0 - mathx.smoothstep(0, HUD_FADE_DUR, g.hero.deathT);
}

pub fn hud(g: *Game, dt: f32) void {
    // A conversation takes the bottom of the screen, which is where the cross and the prompt live.
    if (g.rest.active() or g.talk.active()) return;
    // THE CHROME IS COMPOSITED AS ONE PICTURE while it is going out (`hud.beginChrome`) — every element in
    // the block below carries its own literal colours, and a per-element alpha is one call site away from
    // leaving a slot solid over a HUD that has gone.
    const chrome = chromeFade(g);
    const wantChrome = !g.menu.isOpen() and chrome > 0.001;
    // **THE SPIRIT'S FACE IS TAKEN BEFORE THE CHROME TARGET OPENS.** `endTextureMode` restores the DEFAULT
    // framebuffer rather than the target that was bound before it, so rendering a portrait inside the chrome
    // scope would send every HUD draw after it at the backbuffer, to be overwritten by the chrome's own blit.
    // Taken here, the toast below only has a quad to mount (`hud.renderPortrait`).
    const spiritFace = wantChrome and if (spiritPortrait(g)) |lp| hud_.renderPortrait(lp) else false;
    // The target is only taken while a fade is actually running: at full chrome `beginChrome` refuses and
    // every draw below goes straight at the backbuffer exactly as it always did.
    //
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
                // RIGHT: off the ENUM rather than off `bowUp` — as nested ifs the bell drew a sword. And off
                // `armInHand`, the input's own rule: a bow set in the LEFT slot is worked from this hand.
                armSlot(g.hero.armInHand()),
                // UP fills only while something in his hands could cast; behind a bow or a shield, empty.
                if (wandUp) (switch (g.hero.spell) {
                    .bolt => hud_.Slot.spell,
                    .roots => hud_.Slot.roots,
                    .rime => hud_.Slot.rime,
                }) else .empty,
                g.hero.fp.cur >= g.hero.castCost(),
                g.hero.quick.selected(),
                quickLeft(g),
                if (bowUp) hud_.Ammo{ .n = g.hero.quiver.ready(), .fire = heromod.arrowBurns(g.hero.quiver.sel) } else null,
            );
            // **WHAT IS STANDING WITH HIM**, under his own bars. The fade is held on `Game` and not read off
            // the pack, because the body is gone before the toast has finished leaving — and the LAST life
            // it had is held with it, so the bar drains to where it died instead of snapping to zero.
            if (g.pack.firstConst()) |w| {
                g.spiritK = mathx.approach(g.spiritK, 1.0, dt * 5.0);
                g.spiritHp = w.vit.hpFrac();
            } else {
                g.spiritK = mathx.approach(g.spiritK, 0, dt * 2.2);
            }
            hud_.spiritPanel(spiritFace, combat.spiritName(g.hero.spirit), g.spiritHp, g.spiritK);
            hud_.reticle(g.hero.aimB);
            hud_.souls(g.hero.souls.display()); // the ROLLING value, not the banked total
            // THE BOSS BAR (ER's): named, bottom-centre, faded in when a knight is fighting and held while
            // the bar drains and the body goes to gold. The floating bar over the same body is suppressed
            // (`drawFoeBars`) — one number may not be read in two places.
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
    // Under the menu and over everything else: a trigger firing while the pause card is up still has
    // something to say when it comes down.
    const line = g.trig.bannerText();
    if (line.len > 0) hud_.banner(line);
    // **THE TOASTS ARE NOT CHROME EITHER**, and for the banner's own reason: what you just picked up is a thing
    // the world is telling you, not part of the character's own readout, so it does not go out with the bars on
    // the frame he dies. Drawn OVER the chrome block and outside its target for the same reason.
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
    // The startup ledger starts HERE, not at `Game.init`: the window, the GL context and the font atlases are
    // the better part of a second and were invisible to a measurement that began after them.
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
        // TAKE 0 OF EVERY ROW ONLY — the variants come in through `sfx.pump` below. The whole bank was 4.4 s
        // here, in front of a window that is already up and blank.
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
        @import("shots.zig").runShots(g);
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
        // **THE FIRST-TIME CARD IS ONE OF THE HOLDS.** `award.carding()` IS "the world is held" and its own
        // branch says so — but the guard here listed the four screens and not the card, so the sun kept
        // walking for as long as it took to read one, and at the debug day speeds that is a quarter of an
        // hour a card. Every hold that stops the field has to stop the clock with it.
        if (!g.editor.on and !g.menu.isOpen() and !g.rest.active() and !g.talk.active() and !g.award.carding()) g.day.tick(dt);
        applyHour(g);
        sfx.mute(g.editor.on and !g.editor.auditioning());
        // BEFORE every branch, because a moved sound-filter dial's settle has to run out under the menu that
        // armed it — and its re-bake decides what take 0 is before `pump` starts appending variants.
        sfx.tickFx(rawDt);
        // The budget is sized to be INVISIBLE, not to finish fast: at 12 ms of a 16.7 ms frame the menu ran
        // at half rate for four seconds, and time to a SMOOTH first frame did not move.
        const paused = g.menu.isOpen() or g.rest.active() or g.talk.active() or g.editor.on;
        const budget: u64 = if (paused) 3 * std.time.ns_per_ms else 1 * std.time.ns_per_ms;
        if (sfx.pump(budget, paused)) bankT += rawDt else if (bankT > 0) {
            std.debug.print("INIT: {s: <10} {d:.1} ms (behind the menu)\n", .{ "audio rest", bankT * 1000.0 });
            bankT = -1;
        }

        // Pad SELECT opens the GAME menu, pad START the CHARACTER one; TAB is START's keyboard twin. A
        // conversation has to be FINISHED rather than escaped out of, and neither menu opens at a fire.
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
                    // The last edit's rebuild may still be inside its quiet window, and nothing is going
                    // to draw the editor again to service it.
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    // Back to whichever card opened it: entered off the boot screen there is no world to
                    // pause, and a hard `.main` dropped you into the pause menu of a game nobody started.
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
                    // PLANTED BEFORE HE IS PUSHED OUT, so the push-out has a real foot height to compare
                    // against rather than the datum a sculpted map is metres above.
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
            // Every frame, so moving a spawn moves the thing you can SEE. NOT gated on `mapGen` like the
            // folk: the Units layer moves spawns five different ways.
            rehomeFoes(g, .blind);
            rehomeChests(g);
            // The FOLK only when the map is replaced: `Folk.reset` restarts their three idle clocks, so done
            // every frame the pose the camera is pointed at freezes.
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
                    // The editor re-homes every group from the map each frame, so a held `FoeRef` survives
                    // into a world where its index means something else.
                    g.lock = null;
                    g.editor.enter(g.hero.pos);
                },
                // Nothing torn down and nothing written: the character is saved as of the last fire.
                .toTitle => g.menu.toTitle(),
                // NEITHER HAPPENS ON THE PRESS. Both arm the cut and the world is built once the screen is
                // black (`beginEnter` → `enterNow`), so nothing is ever swapped under the player's eyes.
                .newGame => |i| beginEnter(g, .{ .fresh = i }),
                .loadGame => |i| beginEnter(g, .{ .load = i }),
                // The picker ASKED before this arrived (`menu.askDelete`), so there is nothing left to
                // confirm here — only the two files to remove, the shelf to re-survey off the disk, and the
                // pictures to re-read, which are the menu's own.
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
            // ASKED AFTER `update`, NEVER BEFORE: `dist` and `pitch` are the PLAYER's zoom and tilt and
            // nothing in play resets them, so stamping the title framing on the frame New Game was pressed
            // hands the new character a camera seven metres back he cannot undo except by scrolling.
            const booting = g.menu.booting();
            if (booting) {
                g.rig.orbit(BOOT_SPIN * rawDt, 0);
                g.rig.pitch = BOOT_PITCH;
                g.rig.dist = BOOT_DIST;
            }
            g.rig.follow(g.hero.shoulderPoint());
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

        // **THE FIRST-TIME ITEM CARD HOLDS THE WORLD** (owner's call) — the menu's own branch, one screen along.
        // It sits AFTER the menu (a pause card must be able to come up over it is not a thing we want; the menu
        // is the outer shell) and BEFORE the fire, because you can open a chest and be handed something new
        // without ever sitting down. Nothing in the world ticks: no foe, no clock, no toast.
        if (g.award.carding()) {
            g.hero.held = true;
            // ANY KEY, and that is the whole of the input. `getKeyPressed` drains the queue and the pad's face
            // buttons are asked beside it, so there is no wrong press and no button to name in the footer.
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

        // **THE CUT HOLDS THE WORLD WHILE IT GOES DOWN.** A map change fades out from inside the world, and a
        // man still walking through it arrives on the other side somewhere he did not choose. Nothing but the
        // fade's own clock runs — the menu's branch, one screen along.
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
                // Sight goes SOFT, not off: a pillar passing between you mid-circle must not throw the
                // camera off it.
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
        // BEFORE any look input lands, so the probe reports what the camera turned rather than what the
        // devices claimed.
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

        // The ARROW keeps a KEY OF ITS OWN: the cross is four directions and the spell has taken Up, so on
        // the pad the quiver is changed in the character book's ammo slot instead.
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

        // L1/RMB belongs to the HAND, not the shield (the R1/R2 rule from the other side): boards block on a
        // held LEVEL, a wand casts on a pressed EDGE, so both are read here and neither swallows the other.
        // **A BUTTON PAIR BELONGS TO A HAND; WHAT IT DOES BELONGS TO THE ARMAMENT** (ER's routing, and the
        // whole point of letting either hand hold anything). R1/R2 work the RIGHT hand, L1/L2 the LEFT, and
        // each armament says what its own two buttons mean.
        const l1Held = rl.isMouseButtonDown(.right) or padDown(.left_trigger_1);
        const l1Press = rl.isMouseButtonPressed(.right) or padPressed(.left_trigger_1);
        // On the mouse the L2 halves part company — RMB is already the L1 level, and Shift+RMB would fire a
        // parry on every sprinting block, so the pressed edge takes a key of its own.
        const l2Held = rl.isMouseButtonDown(.right) or padDown(.left_trigger_2);
        const l2Press = rl.isKeyPressed(PARRY_KEY) or padPressed(.left_trigger_2);
        const shiftDown = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
        const lmbPress = rl.isMouseButtonPressed(.left);
        const lmbDown = rl.isMouseButtonDown(.left);
        const r1 = padPressed(.right_trigger_1) or (lmbPress and !shiftDown);
        const r2 = padPressed(.right_trigger_2) or (lmbPress and shiftDown);
        const r1Held = padDown(.right_trigger_1) or (lmbDown and !shiftDown);
        const r2Held = padDown(.right_trigger_2) or (lmbDown and shiftDown);

        // **A TWO-HANDER CLAIMS THE PRIMARY PAIR WHICHEVER SLOT IT SITS IN.** The bow is worked with both
        // hands and the rig nocks it at the right wrist, so which slot it was equipped to is bookkeeping —
        // and the other hand has nothing in it while it is up.
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
                // Under the roll, above everything else: a frame carrying both A and B is a player who wants
                // the one with i-frames, and a swing can wait for the queue.
                if (g.hero.startJump(rollDir(g, mv), mv.speed)) sfx.play(.jump);
            } else if (parryReq) {
                // Above the attacks: a frame carrying both L2 and R2 is a player who wants the defensive one.
                // The shove is MOVED AIR; the CLANG belongs to the catch alone.
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
        // ONE predicate, not a list of them: written out as four named states it had already forgotten the
        // loose and the parry, whose keyboard binding billed every parry as a sprint.
        g.hero.sprinting = sprintingMove(mv) and !g.hero.committed() and !g.hero.dead and !g.hero.staggered();
        // …and the shield AFTER the sprint (there is no running block — see `hero.setGuard`).
        g.hero.setGuard(guardHeld);
        g.hero.setAim(aimHeld);
        // Shield, bow and draught are each a SHUFFLE rather than a stop, denied at the SOURCE like the sprint.
        if (g.hero.guarding) mv.speed = @min(mv.speed, WALK_SPEED * heromod.GUARD_SPEED);
        if (g.hero.aiming) mv.speed = @min(mv.speed, WALK_SPEED * heromod.BOW_AIM_SPEED);
        if (g.hero.drinking) mv.speed = @min(mv.speed, WALK_SPEED * heromod.DRINK_SPEED);

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        const faceYaw: ?f32 = if (g.hero.aiming) g.rig.yaw else lockYaw;
        g.hero.aimAtPitch(meleePitch(g));
        // BEFORE the branch: every one below ends in a `pose()`, so the lean has to be settled first or it is
        // always one frame stale.
        leanToGround(g, dt);
        // For the water gate under the branch. Taken only while he is ALIVE: the death branch respawns him,
        // and a hold across that would drag him back off his own bonfire.
        const heroWas = g.hero.pos;
        const heroAfoot = !g.hero.dead;
        if (g.hero.dead) {
            g.hero.updateDeath(dt);
            // The frame he returns, the WORLD reloads with him (ER-style).
            if (!g.hero.dead) resetFoes(g);
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt);
        } else if (g.hero.airborne()) {
            // Under the stagger — a blow in the air still flinches him — and over everything else, since a
            // jump is `committed()` and nothing below can be running.
            moveHeroAir(g, dt, mv, faceYaw);
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.drinking) {
            // COMMITTED, NOT PLANTED: the clock first, then the shuffle — either way through `moveHero`, so
            // the shared clocks advance exactly ONCE this frame (`tickClocks`).
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
        // Taken AFTER the hero's branch: a respawn re-homes the whole field inside it, and the gate would drag
        // each fresh spawn back to where the last one died.
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
        // All five stamped before anything decides what to do about him, or moves, or swings. The VIGIL is
        // last of them because it is the only one that reads a creature's own state back (`casting`), so it
        // wants the field as the previous frame left it and not half-updated.
        markSight(g);
        markThreat(g, dt);
        markWays(g);
        markParry(g);
        markVigil(g);
        // ONE snapshot of the blade for every group this frame — re-derived per group, the three disagree.
        const bladeNow = heroBlade(g);
        if (g.warren.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            // The lunge carries stance damage; the chomp doesn't — split the felt blow by that.
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        if (g.grief.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            // NOT `hit.heavy()`, on purpose: all four of his blows carry stance, so that test would call the
            // side swipe a slam. The split is "was it THE SLAM", which is its own stance figure.
            _ = heroTakes(g, b, b.hit.stance >= ogremod.SLAM_HIT.stance, true);
        }
        for (g.line.live()) |*a| {
            if (a.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) {
                spawnArrow(g, a.nockWorld(), heroAimPoint(g));
            }
        }
        if (g.band.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnClump)) |b| {
            // NOT `hit.heavy()`, on purpose: nothing a kobold throws carries stance, so that test reads false
            // for the whole band. The berserker's CHOP is the heavy one here and POISE is what separates it.
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
        // The leechfly is TWO CHANNELS: the beak going in is a BLOW (blockable), the swallow after it a HOLD
        // through `hero.burn`. A shield answers the first and only the roll the second.
        if (g.swarm.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, leechSip)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // The Rooted hands its DRAG over rather than applying it: only this side knows whether the blow was
        // blocked, so it is spent AFTER `heroTakes`.
        g.hook = null;
        if (g.grove.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, noteYank)) |b| {
            applyYank(g, heroTakes(g, b, b.hit.heavy(), true));
        }
        // The sporeling's bonk is a blow; its cloud is a HOLD, billed further down beside the mother's acid.
        if (g.cluster.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // The delver. NOT `hit.heavy()`: the claw carries stance too, so that test would call a swipe the
        // ground opening under you. The split is "was it THE BURST", its own stance figure.
        if (g.warrens.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= delvermod.BURST_HIT.stance, true);
        }
        // …AND THE THIRD CHANNEL OF ITS TELL. The mound and the noise are no use to a player whose camera is
        // pointed at the horizon, and this is the one move in the game that arrives from a direction the lens
        // cannot be turned toward: the ground going under your own feet is a thing you should FEEL.
        if (g.warrens.anySurged()) {
            g.rumble.play(rumblemod.hit_heavy);
            g.rig.addShake(SHAKE_SURGE);
        }
        // The necromancer. Its only blow is the SIGIL, so there is no "was that the heavy" split to make —
        // one move, one weight, and `hit.heavy()` answers it because the ring is the only thing it throws.
        if (g.rite.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // …and the raise, which is the one beat here that is not a blow at all: the game does the raising
        // because the body belongs to another group (`applyRaises`).
        applyRaises(g);
        // A FUSE LIT AT HIS FEET IS FELT AS WELL AS SEEN. It is drawn on the ground in a colour nothing else
        // in the world is, but the ground is exactly where a player fighting two other things is not looking.
        if (g.rite.anyLaid()) {
            g.rumble.play(rumblemod.swing_light);
            g.rig.addShake(SHAKE_SIGIL);
        }
        // The Bone Knight. NOT `hit.heavy()`: every blow he owns carries stance, so that test would call a
        // shield bash a five-metre body landing on you. The split is "was it the BODY or the WALL" — the
        // fall and the charge, keyed off the lighter of their two stance figures.
        if (g.vigil.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.stance >= knightmod.CHARGE_HIT.stance, true);
        }
        // …and PHASE TWO'S GAS, billed the same way the field's other floors are (`brood.burn`,
        // `cluster.spores`) — a dose on its own clock, never a stroke, so it is always the light beat.
        if (g.vigil.gasDose(dt, g.hero.pos)) |b| {
            _ = heroTakes(g, b, false, false);
            sfx.play(.acid_burn);
        }
        // …AND THE GROUND HE MOVES IS FELT ON THE MISS TOO: the fall landing, the stomp's ring and the
        // charge's skid all shake the frame off the knight's own one-frame quake (the delver's surge rule —
        // these arrive where the lens may not be pointed).
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
        // The meter resolves LAST, after every source has had its say, so a bar that filled this frame goes
        // off this frame. The DRAIN is silent — it runs fourteen seconds; the PROC gets all the feedback.
        _ = g.hero.tickPoison(dt);
        if (g.hero.poison.justProcced) {
            sfx.play(.acid_burn);
            g.rig.addShake(SHAKE_HURT);
            g.rumble.play(rumblemod.hurt);
            g.hero.hurtFlash = mathx.maxF(g.hero.hurtFlash, 0.7); // the ONE flash the poison gets
        }
        // AFTER every creature has moved, so what the spirit is handed to go for is where that body is this
        // frame rather than last one.
        tickPack(g, dt);
        g.chests.update(dt, g.hero.pos);
        g.pickups.update(dt, g.hero.pos);
        hidePickups(g); // …and a taken glow stops being drawn as it shrinks out
        // THE TOASTS RUN ON THE WORLD'S OWN CLOCK, here and nowhere else: behind a first-time card everything
        // is held, and a notice that expired while you were reading one would never have been seen.
        g.award.update(dt);
        // The folk take the same terrain gate the foes do.
        var wasFolk: [npcmod.CAP]rl.Vector3 = undefined;
        const nFolk = g.folk.n;
        snapshotPos(g.folk.live(), &wasFolk);
        g.folk.update(dt, g.hero.pos, PLAY_HALF);
        gateTerrain(g, g.folk.live(), wasFolk[0..nFolk]);
        inline for (FOE_GROUPS, 0..) |f, gi| gateTerrain(g, @field(g, f.field).live(), wasPos[gi][0..wasN[gi]]);
        // …and the COLD's gate straight after the terrain's, off the same snapshot: both are post-step rules
        // about the feet, and the chill's is the roots' law by fractions (`gateChill`).
        inline for (FOE_GROUPS, 0..) |f, gi| gateChill(@field(g, f.field).live(), wasPos[gi][0..wasN[gi]]);
        // THE CONE, tested AFTER everything has moved: what it takes is where the bodies actually ARE this
        // frame, not where they were when he started breathing.
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
        }
        stepShafts(g, dt);
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
        // The jump's one beat goes on the LANDING, never the takeoff: nothing has happened until the ground
        // stops him.
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
        // …and the same cut in the world's own branch: the fade IN after a load runs here, and a map change
        // (`Enter.map`) fades out from here too.
        tickEnter(g, rawDt);
        drawEnterFade(g);
        rl.endDrawing();
    }
}

fn footsteps(g: *Game, last: *f32) void {
    const h = &g.hero;
    // NOT while his feet are off the ground: the gait phase keeps running through a jump so he lands back
    // into the stride he left with, and a boot on every half-cycle of it is a man walking on air.
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
    };
}

/// Through the same hero methods the D-pad uses, so a swap picks up the same refusals — a menu may not put a
/// bow in his hands mid-roll.
fn bookAct(g: *Game, a: bookmod.Action) void {
    switch (a) {
        .none => {},
        .use => |k| useItem(g, k),
        // STRAIGHT INTO THE SLOT. It used to WALK the swap round until the hand held what was picked, which
        // was only ever safe while a hand cycled its whole enum — against a two-slot hand a thing in neither
        // slot is a swap that never arrives, and the loop would not have ended.
        .arm => |want| _ = g.hero.equip(heromod.RIGHT, 0, want),
        .armAlt => |want| _ = g.hero.equip(heromod.RIGHT, 1, want),
        .off => |want| _ = g.hero.equip(heromod.LEFT, 0, want),
        .offAlt => |want| _ = g.hero.equip(heromod.LEFT, 1, want),
        .ammo => |k| while (g.hero.quiver.sel != k) {
            if (!g.hero.cycleArrow()) break;
        },
        // `syncFlask` follows: what the bar is turned to is what `flasks.sel` has to be for the draught and
        // the HUD tint to agree with it.
        .quick => |q| {
            g.hero.quick.put(q.slot, q.kind);
            g.hero.syncFlask();
        },
    }
}

/// The one place the tree reaches the hero — called wherever a node is taken AND once at startup, so the
/// bars can never be sized off a stale sheet.
pub fn applyTree(g: *Game) void {
    g.hero.applyPerks(g.tree.bonus());
}

/// ONE HAND'S ARMAMENT AS THE HUD'S OWN CELL. Exhaustive, so a sixth armament is a row here — and it is
/// asked of a HAND rather than of a side, since either may hold any of them.
/// ONE HAND'S TWO BUTTONS, as levels and edges — the pair is the same shape whichever hand it is.
const HandIn = struct { press1: bool, press2: bool, held1: bool, held2: bool };

/// EVERYTHING EITHER HAND CAN ASK FOR THIS FRAME. Gathered rather than assigned, because two hands may ask
/// for different things and the branch below has to see both — a sword left and a bow right is a frame with
/// a swing and a shot in it, and whichever the state machine takes, neither may be silently dropped.
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

/// **WHAT ONE ARMAMENT'S OWN TWO BUTTONS MEAN.** Exhaustive, so a sixth armament has to say what it does
/// with a hand before it can be equipped to one. `press1`/`press2` are the edges and `held1`/`held2` the
/// levels — a guard and an aim are LEVELS, everything else is an edge.
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

/// A flask goes down the committed draught; everything else takes its own `useItem`, which is instant and
/// costs no animation, because an edible is not a draught.
fn quickUse(g: *Game) void {
    const k = g.hero.quick.selected() orelse return;
    if (combat.flaskOf(k)) |f| {
        // Stamped here and not only at the cycle: `dropEmpty` can move the selection on any frame, and the
        // cross showed crimson while he drank the blue one.
        g.hero.flasks.sel = f;
        if (g.hero.startDrink()) sfx.play(.flask_drink);
        return;
    }
    useItem(g, k);
}

/// A flask never comes through here — its charges are `combat.Flasks`, refilled at a bonfire, and the bag has
/// none of them (`quickUse`).
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
        // The candle flies the slinger's own wad, thrown at the point the reticle converges on. ONE victim —
        // nothing thrown here is a blast.
        .lob => |l| {
            if (g.bag.take(k, 1) == 0) return;
            const from = mathx.addV(heroAimPoint(g), mathx.scaleV(mathx.headingDir(g.hero.facing), 0.4));
            const hit = combat.Hit{ .dmg = l.dmg, .poise = l.poise, .elem = combat.elems(.{ .fire = l.fire, .lightning = l.lightning }) };
            // The jar says its element in the sky (`archer.trailCol`) — a lightning lob on the fire wad's
            // streak would be the second-kind-of-fire lie the brood's rule forbids.
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
    }
}

/// Every blow the field deals comes through here, and the FIRST thing it asks is who it was aimed at — a
/// creature swinging at the spirit must not land on a man standing six metres away.
fn heroTakes(g: *Game, b: foemod.Blow, heavy: bool, voice: bool) combat.HitOutcome {
    if (b.on == .spirit) return spiritTakes(g, b, heavy);
    const out = g.hero.takeHit(b.hit, mathx.dirXZ(g.hero.pos, b.from));
    switch (out) {
        .ignored => {}, // rolled through it, or he was already gone
        .taken => heroHurtBeat(g, heavy, voice),
        .blocked => heroBlockBeat(g, b.hit),
        .guardBroken => {
            // The boards ate it on the way to failing, so they still throw what a block throws — at full
            // weight, because whatever did this was the heaviest thing they saw.
            g.hero.blockSparks(1.0);
            g.rumble.play(rumblemod.guard_break);
            g.rig.addShake(SHAKE_GUARD_BREAK);
            sfx.play(.guard_break);
        },
    }
    return out;
}

/// Its beats are DELIBERATELY quieter than his: the camera shake and the pad belong to things happening to
/// the PLAYER. Returns `.ignored` so nothing downstream treats it as his — most of all `applyYank`, where a
/// hook that caught the wolf has no business dragging the man.
fn spiritTakes(g: *Game, b: foemod.Blow, heavy: bool) combat.HitOutcome {
    for (g.pack.live()) |*w| {
        if (!foemod.corporeal(w)) continue;
        const out = w.takeHit(b.hit);
        if (out == .taken) {
            const dir = mathx.dirXZ(b.from, w.pos);
            if (mathx.lenXZ(dir) > 1e-3) {
                w.shove = mathx.scaleV(mathx.normV(dir), if (heavy) wolfmod.SHOVE.heavy else wolfmod.SHOVE.light);
            }
            // NO impact voice: `hit_light`/`hit_heavy` mean "YOUR BLADE LANDED", and borrowing them for a club
            // hitting the wolf tells the player he connected when he did not. `takeHit` sets the yelp.
        }
        break; // one spirit, and `SUMMON_MAX` is what says so
    }
    return .ignored;
}

fn heroBlockBeat(g: *Game, h: combat.Hit) void {
    // Off the RAW blow: measured on `dmg`, a blow with no physical half at all — the mother's spit, the
    // sling's burning clump — read as the lightest thing in the game.
    const w = mathx.clampF(h.raw() / BLOW_HEAVIEST, BLOCK_FELT_MIN, 1.0);
    g.rumble.play(if (w >= BLOCK_FELT_HEAVY) rumblemod.guard_block_heavy else rumblemod.guard_block);
    g.rig.addShake(SHAKE_BLOCK * w);
    // GRIT OFF THE BOARDS, not the catch's struck iron (`hero.blockSparks`) — off the SAME `w` the shake and
    // the pad are, so all three channels say the same thing about how hard the thing that arrived was.
    g.hero.blockSparks(w);
    // …AND THE VOICE IS THE BLOW'S TOO. One flat `guard_block` meant a bite and a slam stopped on the same
    // boards sounded identical, which is most of why a block read as "meh" — the parry has always had a
    // voice of its own, and this is the other half of telling the two apart.
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
            // …and a swing does not stoop for what it cannot reach: the flat cut folded DOWN at a delver
            // riding under his own boots, aiming the one stroke that could not have landed at the floor.
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
    // HIS FEET, not the ground under him: a jump clears a low collider for the same reason it clears a low
    // riser and a short creature, and off the same height (`hero.footY`). A wall is still a wall.
    var hp = g.env.resolveActor(g.hero.pos, HERO_R, g.hero.footY());
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*a| {
            // He clears what he is OVER, off the creature's own crown: a jump passes above a toad and is
            // stopped dead by an ogre.
            if (foemod.corporeal(a) and !a.airborne() and g.hero.footY() < a.topWorld().y) {
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

    // The folk and the spirit yield to HIM and to the world's solids, ONE WAY only (the `vs` rule): two
    // bodies each half-correcting is jitter between them, and the one that gives way is never the player.
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
        if (!foemod.corporeal(a)) continue;
        const r = a.bodyR();
        // Airborne exempts a creature from the terrain rule and from being shouldered — NEVER from the
        // world's solids, or a pounce leaves the arena through a wall. Measured AT ITS FEET, not at the
        // height it is flying at: nothing here has the hero's `lift` law yet, so handing the real height
        // over would sail a leechfly at 4.6 m through architecture.
        if (a.airborne()) {
            a.pos = inBounds(g.env.resolveActor(a.pos, r, a.pos.y));
            continue;
        }
        var p = g.env.resolveActor(a.pos, r, a.pos.y);
        if (gr.vsHero) p = collision.pushOutCircle(p, r, g.hero.pos, HERO_R);
        for (foes, 0..) |*o, j| {
            if (i == j or !foemod.corporeal(o) or o.airborne()) continue;
            p = collision.pushOutCircle(p, r, o.pos, o.bodyR());
        }
        inline for (gr.vs) |other| {
            for (@field(g, other).live()) |*o| {
                if (foemod.corporeal(o) and !o.airborne()) p = collision.pushOutCircle(p, r, o.pos, o.bodyR());
            }
        }
        a.pos = mathx.approachV(a.pos, inBounds(p), step);
    }
}

const FoeKind = worldfmt.FoeKind;
const FoeRef = struct { kind: FoeKind, idx: usize };
/// THE GROUPS WHOSE MEMBERS ARE ROLES OF ONE CREATURE, written down ONCE: `roleOf` says whether a map kind is
/// one of its roles, and every one of them keeps its members in a field called `band`.
const ROLE_GROUPS = .{
    .{ "band", koboldmod },
    .{ "brood", broodmod },
    .{ "muster", warriormod },
};

fn roleIdx(comptime mod: type, r: FoeRef) ?usize {
    return if (mod.roleOf(r.kind) != null) r.idx else null;
}

/// Every group whose members are one kind — a pure projection of `FOE_GROUPS`, so it is taken as one. As its
/// own table a mistyped field resolved a `FoeRef` into the wrong group's array and still compiled.
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
    // Every kind is answered for EXACTLY once, so a new `FoeKind` is a compile error until one group claims
    // it — and a kind claimed twice is one too.
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
    // `ROLE_GROUPS` cannot be derived — it carries a module handle `FoeGroup` has no business holding — so
    // the one thing it restates, the field name, is checked against the table instead.
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
/// An index that outlived a re-home reads undefined memory, and `rehomeFoes` runs four ways of which only
/// three drop the lock. Off the SAME table `askFoe` dispatches on, so the two cannot disagree.
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

/// **A THING YOU CANNOT SEE IS NOT A THING YOU CAN AIM AT.** A dormant Rooted is a dead tree until something
/// wakes it, and a reticle offered on one gives the disguise away for nothing; a submerged DELVER is two and a
/// half metres of earth. Keyed off `@hasDecl`, so a creature with nothing to hide never declares it — and read
/// at every site that TAKES a target (`acquireLock`, `cycleLock`, `lockValid`), every site that DRAWS one
/// (`BarCtx`), the swing's own stoop (`MarkCtx`) and the spirit's quarry (`huntFor`).
fn disguised(f: anytype) bool {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "hidden")) return f.hidden();
    return false;
}

/// How chilled a target is, for its bar — a body opts into the cold by carrying the field (`markWays`' rule).
fn chillOf(f: anytype) f32 {
    if (comptime @hasField(std.meta.Child(@TypeOf(f)), "chill")) return f.chill.frac();
    return 0;
}

test "THE BURROW TAKES THE LOCK OFF YOU, and gives it back when it surfaces" {
    // Owner: the mole should lock you off when he is underground. What that costs him is the camera — and the
    // whole of the move is that you have to find the mound yourself.
    var d = delvermod.Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.2); // stood right over him, so the surge commits at `UNDER_MIN` rather than waiting out
    try std.testing.expect(!disguised(&d)); // on the surface he is an ordinary target

    d.debugDive();
    var t: f32 = 0;
    var wasHidden = false;
    var sawMound = false;
    // THE PREDICATE AND THE PICTURE ARE THE SAME ANSWER: `Model.draw` hides the body behind `deep()`, so a
    // reticle may never sit on air and a drilling body may never be untargetable. Checked EVERY frame of the
    // whole burrow rather than at its ends, which is where a clock of its own would drift.
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
    // A spirit is bound to the man who rang for it: it does not outlive his death standing in the fresh
    // world with the FP already spent.
    g.pack.clear();
}

const HURT_BAR_WINDOW = 5.0;

// Floating HP bars over EVERY target (shared foe contract, one walk for all).
const BarCtx = struct {
    cam: rl.Camera3D,
    /// Goes with the RETICLE rather than with `g.lock`, so a suspended lock takes the bar down with the dot.
    lock: ?FoeRef,
    /// THE BOSS'S NUMBER IS READ OFF THE BOTTOM OF THE SCREEN (`hud.bossBar`), so his floating bar is
    /// suppressed — the same figure hanging in two places is one of them wrong the day they disagree.
    boss: ?usize,

    fn visit(self: *const BarCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            if (!f.alive() or f.dying()) continue; // no bar over a corpse dissolving out
            if (self.boss) |bi| {
                if (bi == i and memberKind(f, kind) == .bone_knight) continue;
            }
            // …NOR OVER A BODY THAT IS NOT THERE TO SEE. A bar is drawn in 2D off a projected world point with
            // no depth test behind it, so a delver that took a blow and then went under left its bar hanging
            // over open grass at the screen height of a crown two and a half metres inside the earth. Same
            // predicate the lock and the reticle drop on, asked in the one other place a target is DRAWN.
            if (disguised(f)) continue;
            const fixed = if (self.lock) |l| l.idx == i and l.kind == memberKind(f, kind) else false;
            // `sinceHurt`, not `sinceHit`: a spell that only takes HP — the bolt, and the roots' own grip —
            // counts as a hit for the bar's purposes, which is the whole question the bar is asking.
            if (!fixed and f.vit.sinceHurt > HURT_BAR_WINDOW) continue;
            // A head can go BEHIND THE EYE, which `projectToScreen` rightly refuses; the CHEST is always in
            // front of you, so the fallback projects that and the ceiling does the rest.
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
