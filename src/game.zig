const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const gfx = @import("gfx.zig");
const envmod = @import("env.zig");
const worldfmt = @import("worldfmt.zig");
const editormod = @import("editor.zig");
const objviewmod = @import("objview.zig"); // its two off-screen preview targets are freed on the way out
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
const leechmod = @import("leechfly.zig");
const shademod = @import("shade.zig");
const chestmod = @import("chest.zig");
const restmod = @import("rest.zig");
const soulsmod = @import("souls.zig"); // WHAT A DEATH LEAVES ON THE GROUND, and the walk back for it
const npcmod = @import("npc.zig");
const trigmod = @import("trigger.zig");
const dialogmod = @import("dialog.zig");
const item = @import("item.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

const PAD = rumblemod.PAD;

const SCREEN_W = 1280;
const SCREEN_H = 800;

const WALK_SPEED = heromod.WALK_SPEED; // keyboard walk / gentle left-stick tilt
const RUN_SPEED = heromod.RUN_SPEED; // full left-stick tilt (light tilt scales down toward walk)
const SPRINT_SPEED = heromod.SPRINT_SPEED; // hold Circle/B (or Shift): dash/sprint
const TURN_RATE = 12.0; // rad/sec the hero yaws toward its heading (souls turn briskly)
const STRAFE_SPEED = heromod.STRAFE_SPEED; // LOCKED-ON sideways travel, as a fraction of forward
const STICK_DEADZONE = 0.16; // left-stick move deadzone
const LOOK_DEADZONE = 0.14;
const LOOK_CLAIM = 0.40;
// Pixels of mouse travel in one frame that count as the player REACHING FOR THE MOUSE — see the look-device latch.
const MOUSE_WAKE: f32 = 2.0;
// YAW is unbounded and a full turn at this rate takes ~2.3 s.
const LOOK_RATE_YAW = 3.4; // rad/sec orbit at full right-stick deflection
const LOOK_RATE_PITCH = 2.0;
const LOOK_CURVE = 1.7;
/// WHAT THE LOOK IS WORTH WITH THE BOW UP, mouse and stick alike.
const AIM_LOOK_SCALE = 0.42;
const ROLL_TAP_MAX = 0.22; // Circle/B released before this (real seconds) = a dodge tap; longer = a sprint hold
// NO run-unlock hold, ever (owner's rule, see AGENTS.md): the stick IS the speed — tilt maps straight to ground speed every frame, and keyboard movement runs immediately.

// Impact shake fed to the camera rig (trauma² response in `camera.zig`).
const SHAKE_HIT_LIGHT = 0.09;
const SHAKE_HIT_HEAVY = 0.15;
const SHAKE_KILL = 0.26;
/// The bolt LEAVING — the one shake here fired by something that has not hit anything, so it sits under
/// the lightest one that has.
const SHAKE_CAST = 0.07;
/// …and the ROOTS closing on something: heavier than a stone leaving a rod, lighter than the blow it is
/// buying you. It holds, it does not hit.
const SHAKE_ROOTS_BITE = 0.20;
const SHAKE_HURT = 0.42;
const SHAKE_HURT_HEAVY = 0.62;
// A CAUGHT blow cracks the frame less than one that lands — he HELD, and the shake says so.
const SHAKE_BLOCK = 0.40;
/// …and a blow REFUSED cracks it harder than one merely eaten. Over the heaviest block and under the break:
/// same weight of iron either way, but this one bought him a punish window and the break cost him one.
const SHAKE_PARRY = 0.56;
const SHAKE_GUARD_BREAK = 0.72;
const BLOW_HEAVIEST = ogremod.SLAM_HIT.raw(); // the whole blow, elements included — see `heroBlockBeat`
const BLOCK_FELT_MIN = 0.25;
const BLOCK_FELT_HEAVY = 0.5;
const SHAKE_DEATH = 0.85;
const SHAKE_CHEST = 0.12;
/// The debug corner's AMMO row, in its own warmer ink so the count reads apart from the stats above it.
const STAT_WARN = mathx.rgba(206, 150, 110, 255);
/// A GREATSWORD SKELETON LEAVING THE GROUND at you (owner: the lunge does not look as dangerous as it is).
/// It has to be FELT before it lands — but it is a whiff until it connects, so it stays under a landed blow.
const SHAKE_SKEL_LEAP = 0.24;
// A SAC SPLITTING is bad news arriving; a sac BURST is you having stopped it.
const SHAKE_HATCH = 0.30;
const SHAKE_SAC_BURST = 0.34;
const RESPAWN_HOLD = 0.55; // seconds of FULL black after the respawn…
const RESPAWN_FADE = 0.9;
/// THE YOU DIED CARD'S LETTERBOX BAND, as fractions of screen height — the caption's own centre is derived
/// off these, not written out again beside them.
const DEATH_BAND_TOP: f32 = 0.35;
const DEATH_BAND_H: f32 = 0.30;

pub var PLAY_HALF: f32 = worldfmt.DEFAULT_HALF - envmod.PLAY_INSET;

const HERO_R = foemod.HERO_R;

const MAX_ARROWS = 24;
const MAX_SHAFTS = 12;
/// The hero's centre of mass ABOVE HIS OWN FEET — not a world height.
pub const HERO_CENTER_Y = 1.0;

const COLLIDE_RATE = 11.0; // world units / sec

const GROUND_RISE_RATE = 9.0; // m/s the body climbs onto higher ground…
const GROUND_FALL_RATE = 16.0;
/// Past this the ease is abandoned and the actor is planted: a teleport (respawn, F5 playtest, the shot harness) must not spend a second sliding up out of the earth, and no real step is anywhere near it.
const GROUND_SNAP: f32 = 2.5;

const CLIP_NEAR = 0.55;
const CLIP_FAR = 320.0;

const MAX_LOCK_R = 17.0; // won't acquire, and drops, a foe beyond this
/// …and how far PAST that a HELD lock survives. START FAR, STOP NEAR is the leash's rule read the other way
/// round: without the gap, a foe hovering on the ring drops and re-acquires every other frame.
const LOCK_KEEP_SLACK: f32 = 2.0;
const LOCK_CAM_EASE = 9.0; // exponential ease rate for the lock-on camera swing (quick, snap-free)
/// The framing pitch while locked onto something at chest height at ordinary range — the fallback when the
/// geometry has nothing to say (he is standing inside it) and the value `lockPitch` settles near on a toad.
const LOCK_PITCH = 0.24;
/// …AND THE RIG TILTS ONTO WHAT IT IS LOCKED TO (owner's call). The boom's pitch IS the view's, so the right
/// number is the angle from the EYE down to the mark: a toad at your boots tips the camera down, an ogre
/// whose chest is two and a half metres up tips it back. A fixed pitch framed the grass under a giant and
/// the sky over a toad, and both of those are the one thing you are trying to look at.
///
/// Measured off the LIVE eye rather than solved, which makes it a feedback loop — and a convergent one: the
/// loop gain is `boom / (boom + distance to the mark)`, under 1 everywhere the guard below does not fire,
/// and `camera.aim`'s ease damps it the rest of the way. The clamps are the rig's own.
const LOCK_PITCH_NEAR: f32 = 0.5; // metres of horizontal separation under which the angle stops meaning anything
fn lockPitch(g: *const Game, r: FoeRef) f32 {
    const mark = foeLockPoint(g, r);
    const eye = g.rig.cam.position;
    const flat = mathx.distXZ(eye, mark);
    if (flat < LOCK_PITCH_NEAR) return LOCK_PITCH;
    return std.math.atan2(eye.y - mark.y, flat);
}
const LOCK_FLICK = 0.65; // right-stick |x| past this cycles to the next target
/// HOW LONG A LOCK SURVIVES WITH NO SIGHT OF ITS TARGET. You cannot FIX on what you cannot see, but a
/// lock that dropped the instant a pillar crossed the line would be unusable anywhere in these ruins —
/// so it is a fade, not a switch, and it is long enough to cover a foe stepping behind its own cover.
const LOCK_BLIND_HOLD: f32 = 1.1;

const CLEAR = rgba(80, 76, 69, 255);

/// What the two look devices said this frame, which one owns the camera, and what the camera actually DID with them.
const LookProbe = struct {
    mdx: f32 = 0,
    mdy: f32 = 0,
    rx: f32 = 0,
    ry: f32 = 0,
    mag: f32 = 0, // RAW stick magnitude, 0..1 — vs LOOK_DEADZONE (turns) and LOOK_CLAIM (claims)
    dyaw: f32 = 0, // degrees of yaw applied this frame, whichever device did it
    pad: bool = false,
};

/// A hook that landed this frame and has not been paid out yet — see `noteYank`.
const Hook = struct { from: rl.Vector3, pull: f32 };

pub const Game = struct {
    scene: gfx.Scene,
    sky: gfx.Sky,
    vignette: gfx.Vignette,
    retro: gfx.Retro,
    menu: menumod.Menu,
    map: worldfmt.Map, // THE WORLD, as data: env materializes this and the editor edits it
    editor: editormod.Editor,
    env: envmod.Env,
    hero: heromod.Hero,
    warren: frogmod.Knot, // the knot of gaping toads
    line: archermod.Line, // the skeletal archers perched in the ruins
    grief: ogremod.Grief, // the lone one-eyed ogre, deep in the ruins
    band: koboldmod.Warband, // the kobold warband — berserkers, priests and slingers, mixed
    brood: broodmod.Brood, // the brood mothers, their egg sacs, their hatchlings and their acid
    muster: warriormod.Muster, // the skeletal warriors — shieldmen and greatswords, mixed
    grove: rootedmod.Grove, // the Rooted — dead trees that are not, one per clearing
    cluster: shroommod.Cluster, // the sporelings — squat mushrooms that fling themselves and burst spore clouds
    swarm: leechmod.Swarm, // the leechflies — fast flyers that drink his life and zoom out of sword reach
    haunt: shademod.Haunt, // the shades — a flanking pack that drains focus and teleports
    chests: chestmod.Chests, // the openable boxes — props with a lid and a state (chest.zig)
    folk: npcmod.Folk, // the NPCs the map posts — bodies with a name and a conversation, not a foe contract
    /// Which `editor.mapGen` the folk on the field were posted from, so an editor frame re-homes them when the
    /// MAP changes and leaves their idle clocks running when it does not.
    folkGen: u32 = 0,
    /// THE SCRIPT LAYER. `trig` is every switch, counter, timer and one-shot latch in the world; `talk` is the
    /// one conversation that may be on screen. Both read the map's own tables and neither is authored in Zig.
    trig: trigmod.Runtime = .{},
    talk: dialogmod.Session = .{},
    /// The folk's positions, INDEX-ALIGNED with the map's records, refreshed once a frame for a `near npc=`
    /// condition. A field rather than a local: `triggerWorld` is asked from the dialog branch too, which does
    /// not run the trigger pass that would rebuild it.
    npcPos: [npcmod.CAP]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** npcmod.CAP,
    nNpcPos: usize = 0,
    rest: restmod.Rest = .{}, // sitting at a bonfire: the state machine and the fade (rest.zig)
    souls: soulsmod.Souls, // THE DROP — one, standing where he last died until he walks back for it
    /// The player's own retro stack, parked while a rest borrows the screen for its VHS look.
    restRetro: [gfx.RETRO_COUNT]f32 = [_]f32{0} ** gfx.RETRO_COUNT,
    bag: item.Bag = .{},
    arrowModel: rl.Model, // shared arrow mesh, drawn per live/stuck arrow with its own matrix
    clumpModel: rl.Model,
    venomModel: rl.Model,
    fireArrowModel: rl.Model,
    boltModel: rl.Model,
    wispModel: rl.Model,
    arrows: [MAX_ARROWS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_ARROWS,
    shafts: [MAX_SHAFTS]archermod.Arrow = [_]archermod.Arrow{.{}} ** MAX_SHAFTS,
    rig: cameramod.CamRig,
    lock: ?FoeRef = null, // ER lock-on: which foe (toad or skeleton) is locked, or null
    lockBlind: f32 = 0, // …and how long it has been since he could see it (see LOCK_BLIND_HOLD)
    /// The Rooted's hook, waiting on the blow's own fate (`noteYank` → `applyYank`).
    hook: ?Hook = null,
    rumble: rumblemod.Rumble = .{}, // controller vibration, keyed to combat beats
    deathFade: f32 = 0, // post-respawn fade-from-black seconds remaining (armed while dead)
    probe: LookProbe = .{},
    /// The REAL frame time the DRAWING layer needs — the occluder fade's clock, and nothing else, since a
    /// fade paced off the time-scaled dt would crawl in slow motion. `--shot` parks it at a settle-size
    /// step (`shots.SETTLE_DT`): a still frame cannot show a fade, so a capture wants its END state.
    drawDt: f32 = 1.0 / 60.0,

    fn init(g: *Game) void {
        // THE STARTUP LEDGER — one INFO line per phase, so "what is slow to launch" is read off the console
        // and never guessed. The editor is deliberately on it: it is a struct default, and proving that is free.
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
        g.menu = .{}; // opens on the main screen: Continue / Debug / Quit
        phase(&initTimer, "gfx");
        worldfmt.loadOrPanic(worldfmt.START_MAP, &g.map);
        PLAY_HALF = g.map.half - envmod.PLAY_INSET; // before anything spawns against it
        phase(&initTimer, "map");
        g.env.build(&g.scene);
        g.env.uploadSoil(&g.map);
        g.env.uploadWater(&g.map);
        g.env.uploadHeight(&g.map);
        g.env.materialize(&g.map);
        phase(&initTimer, "world");
        g.hero = heromod.Hero.init(g.scene.shader);
        g.hero.pos = mathx.ground(0, 4); // start just south of the ruin avenue
        plantActor(g, &g.hero.pos);
        g.hero.facing = std.math.pi; // facing -Z, into the columns
        g.hero.setSpawn(g.hero.pos, g.hero.facing); // where a death returns him
        g.hero.pose();
        phase(&initTimer, "hero");
        g.warren = frogmod.Knot.init(g.scene.shader);
        g.line = archermod.Line.init(g.scene.shader);
        g.grief = ogremod.Grief.init(g.scene.shader);
        g.band = koboldmod.Warband.init(g.scene.shader);
        g.brood = broodmod.Brood.init(g.scene.shader);
        g.muster = warriormod.Muster.init(g.scene.shader);
        g.grove = rootedmod.Grove.init(g.scene.shader);
        g.cluster = shroommod.Cluster.init(g.scene.shader);
        g.swarm = leechmod.Swarm.init(g.scene.shader);
        g.haunt = shademod.Haunt.init(g.scene.shader);
        g.chests = chestmod.Chests.init(g.scene.shader);
        g.folk = npcmod.Folk.init(g.scene.shader);
        g.souls = soulsmod.Souls.init(g.scene.shader);
        phase(&initTimer, "foes");
        rehomeFoes(g, .blind);
        g.rest = .{};
        rehomeChests(g);
        armScript(g);
        g.bag = .{};
        g.arrowModel = archermod.arrowMesh(g.scene.shader);
        g.clumpModel = koboldmod.clumpMesh(g.scene.shader);
        g.venomModel = broodmod.venomMesh(g.scene.shader);
        g.fireArrowModel = archermod.fireArrowMesh(g.scene.shader);
        g.boltModel = heromod.boltMesh(g.scene.shader);
        g.wispModel = shademod.wispMesh(g.scene.shader);
        g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
        g.arrows = [_]archermod.Arrow{.{}} ** MAX_ARROWS;
        g.shafts = [_]archermod.Arrow{.{}} ** MAX_SHAFTS;
        phase(&initTimer, "pools");
        g.editor = .{};
        phase(&initTimer, "editor");
        g.folkGen = g.editor.mapGen;
        g.lock = null;
        g.lockBlind = 0;
        g.hook = null;
        g.rumble = .{};
        g.deathFade = 0;
        g.restRetro = [_]f32{0} ** gfx.RETRO_COUNT;
        // …the look probe included: `Game` is built in place from `alloc.create`, so a field this block misses never gets its default at all — and `pad` is a bool, where raw heap bytes are illegal behaviour rather than merely a wrong caption.
        g.probe = .{};
        g.npcPos = [_]rl.Vector3{mathx.zero3} ** npcmod.CAP;
        g.nNpcPos = 0;
        g.drawDt = 1.0 / 60.0;
    }
};

/// The foe groups written down ONCE, including what the actor-vs-actor settle needs (`collideActors`). As six
/// hand-written call sites, a seventh group drew, spawned, locked and took hits — and was the only thing in the
/// world nothing pushed out of a wall.
const FoeGroup = struct {
    field: []const u8,
    kind: ?FoeKind,
    /// The widest range anything in this group notices him at — what `SIGHT_R` is folded from. No default,
    /// so a seventh group cannot be added without saying how far it sees: as a hand-written list of six
    /// modules beside a table of six rows, the two drifted the moment one grew and the new group's members
    /// quietly stopped being asked `markSight` at all.
    aggro: f32,
    /// Shouldered by the HERO. The ogre is not: he is too big to be walked out of the way.
    vsHero: bool = true,
    /// …and by the members of these OTHER groups. DELIBERATELY ONE-WAY — the group named here yields to
    /// the one it names, never both ways, or two bodies each half-correcting jitter between them.
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
    // IT IS NEVER SHOULDERED AND IT SHOULDERS NOTHING: it is in the air, and `airborne` is what says so.
    .{ .field = "swarm", .kind = .leechfly, .aggro = leechmod.AGGRO_R },
    // IT IS A FIXTURE: nothing shoulders it off its spot and it shoulders nothing, because it never moves.
    .{ .field = "grove", .kind = .rooted, .aggro = rootedmod.AGGRO_R, .vsHero = false },
    .{ .field = "cluster", .kind = .shroom, .aggro = shroommod.AGGRO_R },
};

/// **IS A FIGHT ON.** The one predicate, and the only thing allowed to answer it. Nothing about the HERO is
/// in it: swinging at air in an empty field is not combat, and standing still in front of a roused ogre is.
///
/// A creature counts if it is ROUSED, or if he is inside the range it notices him at — **and that range is
/// the GROUP'S OWN NUMBER** (`FoeGroup.aggro`), never a radius invented here. Sight is deliberately NOT
/// asked: it flickers as he rounds a corner, and a state that decides whether a menu works may not blink.
/// A CORPSE DOES NOT COUNT (`foe.corporeal`). …AND A BOSS ZONE, the day `worldfmt` has a record for one.
pub fn inCombat(g: *const Game) bool {
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).liveConst()) |*f| {
            if (foeFights(f, g.hero.pos, gr.aggro)) return true;
        }
    }
    return false;
}

/// The single creature's answer `inCombat` folds. Split out because the rule is worth a test and standing up
/// a whole `Game` to reach one is not.
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

    // ROUSED REACHES ANYWHERE: hit it and walk off, and you are still in a fight with it.
    toad.leash.provoke();
    try std.testing.expect(foeFights(&toad, far, frogmod.AGGRO_R));

    // …AND A CORPSE IS NOT A COMBATANT, though it stays `alive()` for seconds while it dissipates.
    toad.debugKill();
    try std.testing.expect(toad.alive()); // still on the field, still going out
    try std.testing.expect(!foeFights(&toad, near, frogmod.AGGRO_R));
}

test "the ranges the fight is judged at are each GROUP'S OWN, never one figure for the field" {
    try std.testing.expect(frogmod.AGGRO_R < archermod.AGGRO_R);
    inline for (FOE_GROUPS) |gr| try std.testing.expect(gr.aggro > 0);
}

/// Whether a re-homed field starts with EYES on the hero. A freshly loaded world is `.blind` — a foe behind a
/// wall must not know he is there until `markSight` says so. The shot harness is `.seen`: no game loop runs to
/// stamp eyes there, and a blind foe stands still, which is not what a portrait of a charge shows.
const Sighted = enum { blind, seen };

fn rehomeFoes(g: *Game, sighted: Sighted) void {
    inline for (FOE_GROUPS) |f| {
        @field(g, f.field).reset(&g.map);
        if (sighted == .blind) {
            for (@field(g, f.field).live()) |*x| x.leash.blindNow();
        }
    }
}

/// EVERY LIST THE GAME TARGETS, walked ONCE: every row of `FOE_GROUPS`, plus any SECOND list a group keeps on the field (`liveExtraConst` — the brood's sacs, which are real targets with their own HP). Spliced in by hand per site instead, the answers drift apart: four sites had the sacs and `rayFoeDist` never did, so an aimed shaft converged straight past a clutch.
fn eachTarget(g: *const Game, ctx: anytype, comptime visit: anytype) void {
    inline for (FOE_GROUPS) |gr| {
        visit(ctx, @field(g, gr.field).liveConst(), gr.kind);
        // The extra list answers for its own members' kinds (`Sac.kind()`), so the row carries none.
        if (comptime @hasDecl(@FieldType(Game, gr.field), "liveExtraConst")) {
            visit(ctx, @field(g, gr.field).liveExtraConst(), @as(?FoeKind, null));
        }
    }
}

/// The array `live()` slices, found by MATCHING ITS ELEMENT TYPE, not by "the first array of structs with a
/// `pos`" — off the shape alone, re-ordering the brood's fields to put `pools` above `band` sizes the snapshot
/// to `POOL_CAP` and a full clutch slices past the end of it.
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
    // …and the gap has to clear a real resting deflection.
    const WORN_STICK_REST: f32 = 0.25;
    try std.testing.expect(LOOK_CLAIM > WORN_STICK_REST);
    try std.testing.expect(LOOK_CLAIM < 0.7);
    const drift = stickRadial(WORN_STICK_REST, 0, LOOK_DEADZONE, LOOK_CURVE);
    try std.testing.expect(drift.mag < 0.10);
    try std.testing.expectEqual(@as(f32, 0), stickRadial(0, 0, LOOK_DEADZONE, LOOK_CURVE).mag);
}

test "the look curve is fine near centre and still reaches full rate at the rim" {
    // A curve that changed the TOP speed would be a sensitivity change wearing a curve's clothes.
    try std.testing.expectApproxEqAbs(@as(f32, 1), stickRadial(1.0, 0.0, LOOK_DEADZONE, LOOK_CURVE).mag, 1e-4);
    const half = stickRadial(0.5 * (1.0 - LOOK_DEADZONE) + LOOK_DEADZONE, 0.0, LOOK_DEADZONE, LOOK_CURVE);
    try std.testing.expect(half.mag < 0.5); // half throw gives LESS than half rate — that is the point
    try std.testing.expect(half.mag > 0.2);
}

fn gatherMove() Move {
    var sprint = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    if (rl.isGamepadAvailable(PAD)) {
        if (rl.isGamepadButtonDown(PAD, .right_face_right)) sprint = true;
        const s = stickRadial(
            rl.getGamepadAxisMovement(PAD, .left_x),
            rl.getGamepadAxisMovement(PAD, .left_y),
            STICK_DEADZONE,
            1.0,
        );
        if (s.mag > 0.001) {
            const sp = if (sprint) SPRINT_SPEED else s.mag * RUN_SPEED; // tilt IS the speed, this frame
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

const WADE_KNEE: f32 = 0.75; // mid-thigh on the H=1.8 rig — where a leg starts pushing instead of swinging
const WADE_DEEP: f32 = 1.5;
const WADE_SLOWEST: f32 = 0.8;

fn wadeDrag(g: *const Game) f32 {
    return wadeDragAt(g.env.wadeDepth(g.hero.pos.x, g.hero.pos.z));
}

test "wading costs the run first and never roots him" {
    // Ankle-deep is FREE — the shallows must not read as glue.
    try std.testing.expectEqual(@as(f32, 1.0), wadeDragAt(0.2));
    try std.testing.expect(wadeDragAt(WADE_DEEP) * WALK_SPEED < WALK_SPEED);
    try std.testing.expect(wadeDragAt(WADE_DEEP * 3) * WALK_SPEED > 0.1);
    try std.testing.expect(wadeDragAt(0.7) > wadeDragAt(0.9));
}

fn wadeDragAt(d: f32) f32 {
    if (d <= WADE_KNEE) return 1.0;
    return mathx.lerpF(1.0, WADE_SLOWEST, mathx.smoothstep(WADE_KNEE, WADE_DEEP, d));
}

/// How far a creature's LOCK MARK swings OFF ITS OWN STANDING AXIS over five seconds of it fighting.
/// Measured horizontally, not vertically: a mark pinned to a height off the feet still rises and falls when
/// the creature hops, so a vertical test passes whatever the reticle is bolted to. Zero for a fixed mark.
fn markSwing(f: anytype, hero: rl.Vector3) f32 {
    var worst: f32 = 0;
    var i: u32 = 0;
    while (i < 300) : (i += 1) {
        _ = f.update(1.0 / 60.0, hero, PLAY_HALF, .{});
        worst = @max(worst, mathx.distXZ(f.lockPoint(), f.pos));
    }
    return worst;
}

// THE UNIVERSAL PIN FOR `foe.markOn`. Here rather than in seven creature files because the rule is the
// CONTRACT's, and the only honest way to check "on every creature" is to walk every creature. The egg sac is
// deliberately absent: it is one membrane on the ground with no part that moves on its own.
test "THE MARK RIDES THE BODY, on every creature that has one" {
    const hero = v3(0, 0, 1.7); // inside every notice ring in the game, so all of them come for him
    const MIN: f32 = 0.02; // two centimetres off the axis — a very low bar, and a fixed mark gives zero

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

/// THE POST-STEP TERRAIN GATE. Its rule is about the FEET and nothing else, which is why it takes anything
/// with a `pos` — the folk go through it too, and they carry no foe contract. `alive`/`airborne` are asked
/// only of whatever HAS them: a body that cannot die and cannot leave the ground answers both by construction.
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
    // …and the ROOTS, which are opaque WOOD standing in the ground and not FX. Through HERE, so they go through
    // both passes and THROW A SHADOW like anything else standing in the sun (the caster contract, AGENTS.md) —
    // drawn only in the lit pass they were lit geometry with no weight on the ground under them.
    g.hero.drawRoots();
    g.scene.setFlash(0.6 * g.hero.hurtFlash);
    // LIT PASS ONLY — the depth pass has no alpha, and his shadow is still his.
    const fade = heroFade(g);
    const seeThrough = cull == .view and fade < 0.999;
    // …and once the fade has reached the floor there is nothing left to submit: the shader's last line is
    // `outA*fade`, so at 0 every one of his ~20 meshes draws a fully transparent fragment over a masked-off
    // depth buffer. Skipped, not drawn invisibly — the sun pass above still has him, so the shadow stays.
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
    g.scene.setFlash(0);
    inline for (FOE_GROUPS) |f| @field(g, f.field).draw(&g.scene);
    // The folk go through HERE like anything else standing in the sun, so they cast in the depth pass too.
    g.folk.draw();
}

fn setCasterShaders(g: *Game, sh: rl.Shader) void {
    g.env.setShader(sh);
    g.hero.setShader(sh);
    g.souls.setShader(sh);
    inline for (FOE_GROUPS) |f| @field(g, f.field).setShader(sh);
    g.chests.setShader(sh);
    g.folk.setShader(sh);
}

pub fn heroCenterY(g: *const Game) f32 {
    return g.hero.pos.y + HERO_CENTER_Y;
}

fn heroAimPoint(g: *const Game) rl.Vector3 {
    return v3(g.hero.pos.x, heroCenterY(g), g.hero.pos.z);
}

/// A POINT `reach` METRES DOWN HIS FACING, off that same centre — what a quick shot and a bolt are thrown at
/// when nothing is locked. ONE body: as two functions it was the same four lines with a different constant.
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

/// LOFTED like every other thrown thing here, so its arc is the tell you read it by.
pub fn spawnWisp(g: *Game, from: rl.Vector3) void {
    poolPut(g, archermod.launchShaft(from, heroAimPoint(g), shademod.WISP_SPEED, shademod.WISP_HIT, true, .wisp));
}

/// THE HOOK LANDED AND IT WANTS TO PULL — noted here and SPENT AFTER `heroTakes` (`applyYank`), because
/// whether it moves him is the BLOW's fate and the blow has not been resolved yet: `Grove.update` calls this
/// from inside its own walk, before anything has asked what the shield did with it.
pub fn noteYank(g: *Game, from: rl.Vector3, pull: f32) void {
    g.hook = .{ .from = from, .pull = pull };
}

/// …and the drag itself. Through `env.walkStep` like his own movement, so it cannot haul him up a cliff or
/// through a wall, and clamped to the play area the way `moveHero` clamps it.
/// BLOCKED, HE KEEPS HIS GROUND — the boards are the one answer to a hook, and the only place a shield beats
/// walking away. A guard that BROKE under it is not an answer, so that one travels.
fn applyYank(g: *Game, out: combat.HitOutcome) void {
    const h = g.hook orelse return;
    g.hook = null;
    switch (out) {
        .blocked, .ignored => return, // caught on the boards, or rolled clean through it
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

/// THE SCRIPT LAYER, BACK TO A FRESH WORLD: the folk on their posts and every switch, counter, timer and
/// one-shot latch cleared. Called wherever the MAP itself changes — a load, and every way out of the editor.
/// NOT on a death: the story he has already heard is not undone by dying, any more than his bag is.
fn armScript(g: *Game) void {
    g.folk.reset(&g.map);
    g.trig.arm(&g.map);
    g.talk = .{};
    // …AND THE DROP, which a DEATH must not clear and a new WORLD must: where it is standing means nothing
    // in a map it was not left in. This is the one place the map itself changes, which is exactly the split.
    g.souls.clear();
}

fn rehomeChests(g: *Game) void {
    var sites: [chestmod.CAP]chestmod.Site = undefined;
    const n = g.env.chestSites(&sites);
    g.chests.reset(sites[0..n]);
    var fires: [restmod.CAP]restmod.Site = undefined;
    g.rest.reset(fires[0..g.env.restSites(&fires)]);
}

pub fn rehomeChestsForShot(g: *Game) void {
    rehomeChests(g);
}

/// EMPTY THE FIELD — through each group's own `clear()` where it has one, because zeroing `n` leaves everything a group owns BESIDES its members (the brood's sacs and acid) standing on the ground.
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
/// …and the wand's bolt WITH its release burst. The harness drives the pose past the `thrown` edge without
/// going through `throwBolt`, so without this every "the throw" still had none of the FX that fire on it.
pub fn throwBoltForShot(g: *Game, at: rl.Vector3) void {
    launchBolt(g, at, false);
}

pub fn stepShaftsForShot(g: *Game, dt: f32) void {
    stepShafts(g, dt);
}
/// ONE FRAME OF THE STATUS, exactly as `run` bills it: every source's dose, then the meter. Its own hook
/// because the loop does this inline and the harness has no loop — and because the ORDER is the mechanic
/// (dose, then resolve), so a copy of it in `shots.zig` would be a copy that can go out of step.
pub fn tickPoisonForShot(g: *Game, dt: f32) void {
    g.hero.poisonBy(g.brood.burn(dt, g.hero.pos));
    g.hero.poisonBy(g.cluster.spores(dt, g.hero.pos));
    _ = g.hero.tickPoison(dt);
}
/// Where something in flight actually IS — a crop of a burning head or a slung clump has to be aimed at it, not guessed. Both quivers, because the hero's shafts are in one and everything thrown AT him is in the other.
pub fn flyingPointForShot(g: *Game, kind: archermod.Shot) ?rl.Vector3 {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (ar.live and ar.shot == kind) return ar.pos;
        }
    }
    return null;
}

/// ONE FRAME OF FLIGHT for one thing thrown AT him, and the ONE place `stepArrow`'s six arguments are gathered — transcribed at each caller, a seventh would reach only one of them.
fn flyArrow(g: *Game, ar: *archermod.Arrow, dt: f32) void {
    ar.hit = false;
    // The GROUND under the shaft, so it plants in a hillside instead of diving through it to find y = 0 — and the hero's centre measured from HIS ground, not from the datum, or an archer shooting up a bank aims at the hero's knees.
    archermod.stepArrow(ar, g.hero.pos, heroCenterY(g), g.env.groundAt(ar.pos.x, ar.pos.z), g.hero.iFramed(), arrowCover(g, ar, dt), dt);
}

/// One frame of flight for everything thrown AT him — the harness's own hook, since the game does this inline.
pub fn stepArrowsForShot(g: *Game, dt: f32) void {
    for (&g.arrows) |*ar| {
        if (!ar.live) continue;
        flyArrow(g, ar, dt);
    }
}
pub fn clearShaftsForShot(g: *Game) void {
    clearQuivers(g);
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
pub fn openChestForShot(g: *Game) bool {
    const had = g.chests.near != null;
    interact(g);
    return had;
}

/// THE HARNESS HAS TO DRIVE THE PANEL ITSELF: `tickTalk` reads live buttons and `triggerWorld` is private.
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
    g.talk.draw(&g.map, &g.trig, triggerWorld(g));
}
pub fn tickTriggersForShot(g: *Game, dt: f32) void {
    tickTriggers(g, dt);
}
pub fn stepFolkForShot(g: *Game, dt: f32) void {
    g.folk.update(dt, g.hero.pos, PLAY_HALF);
    for (g.folk.live()) |*p| plantActor(g, &p.pos);
}

/// A nominal step for the staging above — THE HARNESS'S OWN, not a second copy of the same literal.
/// `shots.zig` is imported lazily here, and one constant is the whole of what these hooks need from it.
const SHOT_STEP: f32 = @import("shots.zig").SHOT_DT;

/// WHAT THE BUTTON WOULD REACH THIS FRAME, and in what order — what he DROPPED, then a bonfire, then whoever
/// is standing there, then a box. ONE list, because the press and the PROMPT are the same question.
///
/// THE DROP IS FIRST and its ring is the smallest of the four: you can die at a grace, and on the frame you
/// walk back in there is exactly one thing you came for. One press clears it and the fire is offered again.
const Reach = enum {
    souls,
    rest,
    talk,
    chest,

    /// The prompt each one puts up — the BUTTON drawn, and the verb. Keyed off the enum rather than spelled
    /// at the call site, and off `hud.BTN_INTERACT` rather than a letter, so a rebind moves both at once.
    fn prompt(self: Reach) hud_.Hint {
        return .{ .glyph = .{ .face = hud_.BTN_INTERACT }, .label = switch (self) {
            .souls => "Reclaim",
            .rest => "Rest",
            .talk => "Speak",
            .chest => "Open",
        } };
    }
};

fn reachable(g: *const Game) ?Reach {
    if (g.souls.near) return .souls;
    if (g.rest.near != null) return .rest;
    if (talkable(g)) return .talk;
    if (g.chests.near != null) return .chest;
    return null;
}

/// ONE BUTTON, ONE PRIORITY ORDER (`reachable`) — you can be in reach of two of them, and the answer must not
/// depend on which system happened to be asked first.
fn interact(g: *Game) void {
    switch (reachable(g) orelse return) {
        .souls => reclaimSouls(g),
        .rest => _ = g.rest.begin(),
        .talk => _ = startTalk(g),
        .chest => openChest(g),
    }
}

/// HE DIED HERE CARRYING THIS. The RING GIVES FIRST (DS's Ring of Sacrifice): one snaps, he keeps the lot,
/// and there is nothing on the ground to come back for. Otherwise everything comes off him onto the spot he
/// fell on — and whatever was standing there already is GONE, which is the whole of the mechanic.
fn spillSouls(g: *Game) void {
    if (bindingInBag(&g.bag)) |ring| {
        _ = g.bag.take(ring, 1);
        g.hero.quick.dropEmpty(&g.bag); // …and the bar sheds it like anything else he has run out of
        sfx.play(.ring_snap);
        g.trig.say("The Soul Binding Ring snaps.");
        return;
    }
    const had = g.hero.runes.dropAll();
    if (had == 0) return; // nothing to spill: no stain, and no walk back for one
    g.souls.spill(g.hero.pos, had);
    sfx.play(.souls_spill);
}

/// The first binding charm he is carrying, asked of the ITEM rather than by kind (`item.bindsSouls`) — a
/// second one is a row in `item.zig` and no edit here.
fn bindingInBag(bag: *const item.Bag) ?item.Kind {
    for (0..item.NK) |i| {
        const k: item.Kind = @enumFromInt(i);
        if (item.bindsSouls(k) and bag.count(k) > 0) return k;
    }
    return null;
}

/// …AND IT IS INSTANT (owner's call). No committed action and no animation on the man: the runes are on the
/// counter the frame he presses, and the rush of gold that crosses to his chest is the effect catching up
/// with something that has already happened.
fn reclaimSouls(g: *Game) void {
    const got = g.souls.take(g.hero.pos) orelse return;
    g.hero.runes.gain(got);
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

fn openChest(g: *Game) void {
    const got = g.chests.openNear(&g.map) orelse return;
    for (got.loot) |it| g.bag.add(it, 1);
    if (got.loot.len > 0) sfx.world(.item_get, got.at);
    g.rig.addShake(SHAKE_CHEST);
    g.rumble.play(rumblemod.hit_light);
}

/// WHAT THE CONDITIONS ARE ALLOWED TO SEE, gathered once and handed IN. The machine never reaches into the
/// game for a foe list, for the same reason a creature reads its stamped `Leash` instead of asking `env` what
/// it can see: the owner of a list is the one who walks it.
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

/// Every foe that died THIS FRAME, billed to SC1's Deaths. One walk, through `eachTarget`, so a seventh group
/// is counted the day it is added. `justDied` is the contract's one-frame edge and the only honest source for
/// a COUNT — a latch like the sac's `killed` reads true every frame after; the brood counts its own instead.
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

/// ONE TRIGGER PASS A FRAME, and the conversation it may ask for opened here rather than inside the machine —
/// a dialog needs a SPEAKER's name, and the machine has no business knowing what an NPC is.
fn tickTriggers(g: *Game, dt: f32) void {
    g.nNpcPos = g.folk.positions(&g.map, &g.npcPos).len;
    billDeaths(g);
        // A GRACE IS BUSY TOO. `run` checks the rest branch BEFORE the talk one, so a conversation opened on
        // the frame a rest begins would be frozen rather than deferred if the machine were not told.
    const want = g.trig.tick(&g.map, triggerWorld(g), dt, g.talk.active() or g.rest.active()) orelse return;
    // NO SPEAKER: nobody is standing in front of him, so the panel is named by the node's own `who:`.
    // A REFUSED OPEN IS A CONVERSATION THAT CLOSED AT ONCE: the machine latched the trigger the moment it
    // handed the id up, and only a close lets go — so a tree with no nodes would wedge that action list.
    if (!g.talk.open(&g.map, &g.trig, want, "", null)) g.trig.dialogClosed();
}

/// SPEAK TO WHOEVER IS IN REACH. Refused — and the prompt is not offered — when the map gave him no
/// conversation: a "Talk" that does nothing is worse than no prompt at all.
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

/// …and whether anyone in reach HAS one, which is the same question the prompt asks.
fn talkable(g: *const Game) bool {
    const i = g.folk.near orelse return false;
    const rec = g.folk.list[i].rec;
    return rec < g.map.nnpcs and g.map.npcs[rec].dlg != worldfmt.NO_DIALOG;
}

/// The conversation on screen, and the world held still behind it. A dialog is a MENU as far as the loop is
/// concerned: the hero is `held`, nothing decides anything, and the only clocks that run are the panel's own.
fn tickTalk(g: *Game, dt: f32) void {
    const in = dialogmod.Input{
        .up = navPressed(.up),
        .down = navPressed(.down),
        .confirm = talkConfirmPressed(),
        .pick = digitPressed(),
    };
    g.talk.update(&g.map, &g.trig, triggerWorld(g), dt, in);
    if (g.talk.justClosed) {
        // He inclines his head as you go, and stops attending to a conversation that is over.
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

/// A dialog's own navigation, through `menumod`'s helpers: a third private copy of "is Down pressed" is a
/// third thing to get out of step with the other two.
fn navPressed(dir: menumod.NavDir) bool {
    return menumod.navPressed(dir);
}
fn confirmPressed() bool {
    return menumod.confirmPressed();
}

/// THE INTERACT BUTTON. On the pad it is **Y** (owner's call) — the one face button ER leaves free, since A
/// is reserved for the jump, B is the roll and X is the quick item. The keyboard mirrors it letter for
/// letter: pressing Y does what the Y glyph on the prompt says, so no crib ever has to name a key.
const INTERACT_PAD: rl.GamepadButton = .right_face_up;
const INTERACT_KEY: rl.KeyboardKey = .y;
/// …and the QUIVER, turned off Y to make room for it. On the pad it stays the character book's ammo slot.
const ARROW_KEY: rl.KeyboardKey = .u;
/// L2 ON THE KEYBOARD — see the L2 block in `run` for why the mouse cannot carry it.
const PARRY_KEY: rl.KeyboardKey = .c;

/// …and the panel takes the INTERACT button on top of the menu confirm, so the button that opened a
/// conversation is also the one that walks through it. It cannot go into `menumod.confirmPressed`: that is
/// the book's own Confirm, and a panel naming a button the press ignores is the prompt rule broken again.
fn talkConfirmPressed() bool {
    return confirmPressed() or rl.isKeyPressed(INTERACT_KEY) or
        (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, INTERACT_PAD));
}

/// 1-9, for picking a line straight off its number the way BG2's list does.
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
        // THE PLAYER'S OWN FILTERS STAY (owner: keep our normal retro filters here, amp up warmth only).
        g.restRetro = g.retro.values;
        g.retro.values[gfx.RF_SEPIA] = mathx.maxF(g.retro.values[gfx.RF_SEPIA], REST_WARMTH);
        const s = g.rest.seat();
        var at = s.pos;
        plantActor(g, &at);
        g.hero.sit(true, at, s.facing);
    }
    if (g.rest.justLeft) {
        g.retro.values = g.restRetro;
        g.hero.sit(false, g.hero.pos, g.hero.facing);
        rehomeFoes(g, .blind);
    }
    if (rl.isKeyPressed(.escape) or rl.getKeyPressed() != .null or rl.isMouseButtonPressed(.left) or
        (rl.isGamepadAvailable(PAD) and rl.getGamepadButtonPressed() != .unknown))
    {
        g.rest.leave();
    }
    if (g.rest.scene()) {
        g.hero.poseRest(dt);
        restCamera(g);
    } else {
        g.hero.pose();
    }
    g.rig.tickShake(dt);
    g.rumble.update(dt, false);
}

fn applyDim(g: *Game) void {
    const d = g.rest.dim();
    g.scene.setDim(d);
    g.sky.setDim(d);
    // …and the propped guitar goes off the rock for exactly as long as he is holding one.
    g.env.stowed = g.hero.resting;
}

const REST_WARMTH: f32 = 0.14;

/// THE REST'S CAMERA, to the owner's own plan sketch: the lens stands PAST the fire and off to one side, so the fire is the near thing on one half of the frame and the man the far thing on the other — and since he is looking at the fire, that puts him three-quarters on.
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
    // Aimed between them and biased toward the man, so the fire sits off to one side of frame rather than dead centre with him crowded against the edge.
    g.rig.cam.target = v3(s.pos.x + axis.x * 0.90, s.pos.y + 0.60, s.pos.z + axis.z * 0.90);
    g.rig.cam.up = v3(0, 1, 0);
}

fn poolPut(g: *Game, a: archermod.Arrow) void {
    putIn(&g.arrows, a);
}

/// A FULL POOL OVERWRITES ITS OLDEST, and a PLANTED shaft goes before one still in the air: a stuck arrow is
/// scenery on a fade timer, where one in flight is a blow that has not landed. Slot 0 is not the oldest of
/// anything — refilling the first hole first made a full pool as likely to eat the shaft loosed two frames ago.
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
    g.rumble.play(rumblemod.swing_light); // the string going is a tick in the grip, not a swing
}

/// THE ONE FRAME A CAST LETS GO, routed by which sorcery the rod is set to. EXHAUSTIVE, so a third spell is a
/// compile error here rather than a cast that plays its whole animation and throws nothing.
fn releaseSpell(g: *Game) void {
    switch (g.hero.spell) {
        .bolt => throwBolt(g),
        .roots => castRoots(g),
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

/// WHERE THE GROUND SPLITS: under the LOCKED foe's own feet, or `ROOT_THROW` metres down his facing when
/// nothing is fixed — the bolt's own fallback, on the ground rather than at chest height, because roots come
/// out of the earth and the earth is what the mark has to be on.
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

/// WHICH ONE BODY THE GRIP CLOSES ON: the LOCKED foe when he is holding a lock, the nearest corporeal thing to
/// the mark otherwise. A row of `FOE_GROUPS` and an index, not a `FoeRef`: a ref only answers questions.
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

/// THE ROOTS ERUPT, AND THEY TAKE EXACTLY ONE FOE — a swing is the only thing in the game that reaches more
/// than one body. It ROUSES the one it takes, because a foe held by the feet that then strolls home is the anti-cheese rule read backwards.
/// Returns the earth it actually split — the victim's own feet, not the thrown mark — or null on bare ground.
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
        // A GRIP THAT CLOSED ON SOMETHING IS FELT; one that closed on bare earth is the lightest thing the wand does.
    g.rig.addShake(if (bit) SHAKE_ROOTS_BITE else SHAKE_CAST);
}

/// …and the harness's hook, `throwBoltForShot`'s twin: the pose is driven past the `thrown` edge without going through `releaseSpell`.
pub fn castRootsForShot(g: *Game) rl.Vector3 {
    const at = rootMark(g);
    return seedRoots(g, at) orelse at;
}

/// The GEOMETRY of a release, which is the part the shot harness reproduces too (`throwBoltForShot`). Sound,
/// pad and shake stay with the caller: those are live-loop only, and a shake in `--shot` costs determinism.
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
            // The perpendicular gap, SQUARED throughout — `lenV(oc)*lenV(oc)` took two square roots to arrive back at the dot product it started from.
            const oc2 = oc.x * oc.x + oc.y * oc.y + oc.z * oc.z;
            if (oc2 - along * along > r * r) continue; // the ray misses it
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
            // It STOPPED this frame — into cover or into the earth, and that gets the surface's own voice.
            if (ar.stuck and ar.age == 0) {
                sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
                splashOf(g, ar); // …and whatever it leaves behind, the foes' pool's own rule
            }
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
        archermod.plantShaft(ar); // spent on the first thing it reached — stands in it and fades
        splashOf(g, ar);
        sfx.world(.arrow_hit, ar.pos);
        g.rumble.play(rumblemod.hit_light);
        g.rig.addShake(SHAKE_HIT_LIGHT);
    }
}

// The look runs from the foe's own lock point to the hero's eye and is stamped on its leash. Asked HERE, once a
// frame, not by the creatures: the prop grid it tests against belongs to `env`.

/// Past the widest notice ring in the game. FOLDED OVER `FOE_GROUPS` rather than a hand-written list of
/// modules — a creature given a wider ring later would quietly stop being asked and see through walls again.
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

/// THE HERO'S SHIELD, STAMPED ON EVERYTHING THAT MIGHT BE CAUGHT ON IT — `markSight`'s pattern, and asked here
/// once a frame for its reason: the arc, the window and the beat all belong to the hero's side of the fight, and
/// six creatures reaching out for them would be six copies of one rule.
///
/// FOLDED OVER `FOE_GROUPS` AND KEYED OFF THE GROUP'S OWN `setParry`, so a creature GAINING windows is a field, a predicate and two group methods — never an edit here.
fn markParry(g: *Game) void {
    const p = foemod.Parry{ .live = g.hero.parryLive(), .at = g.hero.pos, .facing = g.hero.facing };
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "setParry")) @field(g, f.field).setParry(p);
    }
}

/// …and whether ANY of them was caught this frame. ONE answer for the whole field, because `parryBeat` is the
/// hero's own beat: two creatures caught on one frame is still one shield, one recoil and one shower of sparks.
fn anyParried(g: *const Game) bool {
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "anyParried")) {
            if (@field(g, f.field).anyParried()) return true;
        }
    }
    return false;
}

/// A PARRY LANDING — the biggest beat the shield has, and deliberately over the block's: a block is a cost
/// paid, this is a blow REFUSED. `hero.noteParry` throws the sparks and the recoil; the rest is frame and pad.
fn parryBeat(g: *Game) void {
    g.hero.noteParry();
    g.rumble.play(rumblemod.parry);
    g.rig.addShake(SHAKE_PARRY);
    sfx.play(.parry);
}

/// …and the same question for the LOCK: you cannot fix on what you cannot see either.
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

/// WHAT A LANDED PROJECTILE LEAVES BEHIND, asked in ONE place because the two callers (it reached him / it
/// reached anything else) were already drifting apart.
fn splashOf(g: *Game, ar: *const archermod.Arrow) void {
    const ground = v3(ar.pos.x, g.env.groundAt(ar.pos.x, ar.pos.z), ar.pos.z);
    switch (ar.shot) {
        .venom => g.brood.splash(ground),
        .clump => g.band.splash(ar.pos), // at the CONTACT, not the floor: it can burst against a chest
        // …and the bolt bursts at the CONTACT for the clump's reason — it goes off against a wall at the
        // height it struck one, not down at that wall's foot.
        .bolt => g.hero.boltBurst(ar.pos, g.hero.casts),
        // A wisp is a piece of the creature and it leaves nothing on the ground: it is spent arriving.
        .arrow, .firearrow, .wisp => {},
    }
}

fn drawArrows(g: *Game) void {
    for (quivers(g)) |pool| {
        for (pool) |*ar| {
            if (!ar.live) continue;
            const m = switch (ar.shot) {
                .arrow => &g.arrowModel,
                .clump => &g.clumpModel,
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

pub fn drawScene(g: *Game) void {
    g.env.resetStats(); // culling counters for the debug overlay, both passes together
    applyDim(g); // before the depth pass: the uniform is read by every draw below it
    const cam = sceneCam(g);
    // WHAT STANDS BETWEEN THE LENS AND HIM, before either pass, since the marks are read by the draw
    // loop both of them go through. In the editor the line is degenerate on purpose — see markOccluders.
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
    g.env.uploadLights(&g.scene, &view, @floatCast(rl.getTime()), g.hero.wandLight());
    g.scene.setGround(true);
    g.env.drawGround(&view); // sculpted terrain is tiled, so it culls against the same frustum
    g.scene.setGround(false);
    g.env.drawWater();
    if (g.menu.wireframe) rl.gl.rlEnableWireMode();
    drawCasters(g, .{ .view = view });
    g.scene.setWind(true);
    g.env.drawFlora(&view);
    g.scene.setWind(false);
    drawArrows(g);
    // WHAT HE DROPPED, with the arrows: it is made of light and lays no shadow, so it stays out of the depth
    // pass and off `drawCasters` entirely.
    g.souls.draw();
    // …and the thinned occluders LAST, so their alpha mattes the hero standing behind them (`Env.drawThinned`).
    g.env.drawThinned(&view);
    if (g.menu.wireframe) rl.gl.rlDisableWireMode();
    g.env.drawVeils(&view);
    // Unlit spheres over the opaque geometry.
    inline for (FOE_GROUPS) |f| {
        if (comptime @hasDecl(@FieldType(Game, f.field), "drawFx")) @field(g, f.field).drawFx();
    }
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
        rl.drawRectangleGradientV(0, by, w, third, bclear, bcol); // feathered band edges
        rl.drawRectangle(0, by + third, w, bh - 2 * third, bcol);
        rl.drawRectangleGradientV(0, by + bh - third, w, third, bcol, bclear);
        const ta = mathx.pulse(u, 0.16, 0.48, 0.90, 1.0);
        if (ta > 0.01) {
            const size = 0.115 * hf * (0.97 + 0.06 * u);
            const spacing = 0.22 * size; // ER's wide tracking (between glyphs only — measured exactly)
            const cx = 0.5 * wf;
            const cy = bandTop + bandH * 0.5; // band centre, DERIVED — three literals had to agree for the caption to sit in it
            const glow = rgba(120, 14, 10, mathx.u8f(44.0 * ta));
            hud_.bigCentered("YOU DIED", cx - 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx + 3, cy, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy - 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy + 3, size, spacing, glow);
            hud_.bigCentered("YOU DIED", cx, cy, size, spacing, rgba(156, 22, 16, mathx.u8f(232.0 * ta)));
        }
        // …reaching FULL black a little BEFORE the respawn rather than on the same frame, so the hold starts while the card is still up and the cut itself is buried inside it.
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
    const t: i32 = @intFromFloat(0.16 * @as(f32, @floatFromInt(h))); // edge band thickness
    const edge = rgba(150, 20, 16, mathx.u8f(f * 150));
    const clear = rgba(150, 20, 16, 0);
    rl.drawRectangle(0, 0, w, h, rgba(150, 18, 14, mathx.u8f(f * 26)));
    rl.drawRectangleGradientV(0, 0, w, t, edge, clear);
    rl.drawRectangleGradientV(0, h - t, w, t, clear, edge);
    rl.drawRectangleGradientH(0, 0, t, h, edge, clear);
    rl.drawRectangleGradientH(w - t, 0, t, h, clear, edge);
}

pub fn hud(g: *Game, dt: f32) void {
    // THE WORLD'S HUD GOES AWAY BEHIND A CONVERSATION, as it does at a bonfire: the panel takes the bottom of
    // the screen, which is exactly where the cross and the prompt live.
    if (g.rest.active() or g.talk.active()) return;
    if (!g.menu.isOpen() and !g.hero.dead) {
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
        const bowUp = g.hero.bowOut();
        const wandUp = g.hero.wandOut();
        hud_.equipment(
            // LEFT: what that hand actually has — boards, the rod, or nothing at all behind a bow.
            if (bowUp) .empty else if (wandUp) .wand else .shield,
            if (bowUp) .bow else .sword,
            // …and UP fills only while something in his hands could cast one; behind a bow or a shield, empty.
            if (wandUp) (switch (g.hero.spell) {
                .bolt => hud_.Slot.spell,
                .roots => hud_.Slot.roots,
            }) else .empty,
            g.hero.fp.cur >= g.hero.castCost(),
            // DOWN: whatever the quick bar is turned to, and how many. A flask counts charges, anything else the bag.
            g.hero.quick.selected(),
            quickLeft(g),
            if (bowUp) hud_.Ammo{ .n = g.hero.quiver.ready(), .fire = heromod.arrowBurns(g.hero.quiver.sel) } else null,
        );
        hud_.reticle(g.hero.aimB);
        hud_.runes(g.hero.runes.display()); // the ROLLING value, not the banked total
        // THE SAME `reachable` THE PRESS GOES THROUGH: a prompt naming a different thing is worse than none.
        if (reachable(g)) |r| hud_.prompt(r.prompt());
    }
    // A `text` ACTION'S LINE — SC1's Display Text Message. Under the menu and over everything else, because a
    // trigger firing while the pause card is up still has something to say when it comes down.
    const line = g.trig.bannerText();
    if (line.len > 0) hud_.banner(line);
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

    // THE ARROW ON THE STRING, and — while something is locked — WHAT IT WOULD LAND ON. The four resistances
    // are only legible against a named target, so the row reads the lock rather than the hero.
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
    // VSYNC is why fullscreen was tearing. setTargetFPS is a CPU-side frame LIMITER — it paces how often we draw but never tells the driver to swap during vblank, so the swap lands mid-scan and the seam shows.
    rl.setConfigFlags(.{ .msaa_4x_hint = true, .vsync_hint = true, .window_hidden = shot, .window_resizable = true });
    rl.initWindow(SCREEN_W, SCREEN_H, "zig-soulslike");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    // No setTargetFPS alongside vsync: the two limiters fight on any display that isn't 60 Hz (vsync paces to the refresh, then raylib's own busy-wait throttles on top, which reads as judder).

    hud_.init();
    defer hud_.deinit();

    // NO AUDIO UNDER --shot.
    if (!shot) {
        var bakeTimer = std.time.Timer.start() catch unreachable;
        sfx.init();
        std.debug.print("INIT: {s: <10} {d:.1} ms\n", .{ "audio bake", @as(f64, @floatFromInt(bakeTimer.read())) / 1e6 });
    }
    defer if (!shot) sfx.deinit();
    defer objviewmod.unload();
    defer bookmod.unload();

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
    defer g.rumble.stop();
    while (!rl.windowShouldClose()) {
        const rawDt = rl.getFrameTime(); // wall-clock dt: feel systems (shake, rumble, fades, tap windows)
        const dt = rawDt * g.menu.timeScale;
        g.drawDt = rawDt; // …including the occluder fade, which every branch below draws through
        PLAY_HALF = g.map.half - envmod.PLAY_INSET;
        // THE WORLD GOES QUIET IN THE EDITOR.
        sfx.mute(g.editor.on and !g.editor.auditioning());
        // …and a moved SOUND FILTER dial re-renders its family once it has settled (Menu > Debug > Sound
        // Filters). Before every branch, because the settle has to run out under the menu that armed it.
        sfx.tickFx(rawDt);

        // Pad SELECT opens the GAME menu, pad START the CHARACTER one; TAB is START's keyboard twin.
        // A CONVERSATION HAS TO BE FINISHED, not escaped out of (see dialog.zig), so it swallows both.
        if (!g.editor.on and !g.rest.active() and !g.talk.active()) {
            if (rl.isKeyPressed(.escape)) g.menu.onEscape();
            if (rl.isKeyPressed(.tab)) g.menu.onStartButton();
            if (rl.isGamepadAvailable(PAD)) {
                if (rl.isGamepadButtonPressed(PAD, .middle_left)) g.menu.onSelectButton();
                if (rl.isGamepadButtonPressed(PAD, .middle_right)) g.menu.onStartButton();
            }
        }

        if (rl.isKeyPressed(.enter) and (rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt))) {
            rl.toggleBorderlessWindowed();
            g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());
        }
        if (rl.isWindowResized()) g.retro.resize(rl.getScreenWidth(), rl.getScreenHeight());

        if (g.editor.on) {
            rl.showCursor();
            switch (g.editor.update(&g.map, &g.env, rawDt)) {
                .none => {},
                .leave => {
                    // The last edit's rebuild may still be inside its quiet window, and nothing is going
                    // to draw the editor again to service it.
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    g.menu.screen = .main;
                    rl.hideCursor(); // back to the gameplay rule: the mouse IS the camera
                    armScript(g);
                },
                .playtest => {
                    g.editor.flushRebuild(&g.map, &g.env);
                    g.editor.on = false;
                    rl.hideCursor();
                    armScript(g); // the world he is about to test is a FRESH one: no switch already thrown
                    g.hero.pos = mathx.ground(g.editor.cam.target.x, g.editor.cam.target.z);
                    g.hero.pos = g.env.resolveActor(g.hero.pos, HERO_R);
                    plantActor(g, &g.hero.pos);
                    g.hero.setSpawn(g.hero.pos, g.hero.facing);
                    g.rig = cameramod.newCamRig(g.hero.shoulderPoint(), g.hero.facing);
                    wasInside = false; // swallow the mouse delta the editor's look accumulated
                },
            }
            g.hero.held = true;
            g.hero.setGuard(false);
            g.hero.pose();
            // Re-home the foes from the map every frame the editor is up, so moving a spawn moves the thing you
            // can SEE. NOT gated on `mapGen` like the folk: the Units layer moves spawns five different ways.
            rehomeFoes(g, .blind);
            rehomeChests(g);
            // …AND THE FOLK, but ONLY WHEN THE MAP ITSELF IS REPLACED (`editor.mapGen`). Re-homed every frame,
            // `Folk.reset` restarts their three idle clocks, so the pose the camera is pointed at freezes.
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
            switch (g.menu.update(&g.retro, rawDt, bookView(g))) {
                .quit => break,
                .editor => {
                    // Drop the lock on the way in: the reticle rides a FoeRef into groups the editor re-homes from the map every frame, so a held lock survives into a world where its index means something else.
                    g.lock = null;
                    g.editor.enter(g.hero.pos);
                },
                // AN ITEM USED FROM THE BAG, or a swap made in the character book.
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
            g.rig.follow(g.hero.shoulderPoint());
            g.rumble.update(rawDt, false); // motors silent while paused (envelopes still decay)
            // THE WIND KEEPS BLOWING UNDER THE PAUSE CARD.
            sfx.ambience(rawDt);
            drawScene(g);
            hud(g, rawDt);
            g.menu.draw(&g.retro, bookView(g), .{ .hero = &g.hero, .scene = &g.scene });
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
            hud(g, rawDt);
            rl.endDrawing();
            continue;
        }
        // …and a CONVERSATION holds the world exactly as the pause card does — read at wall-clock time, since
        // a debug time-scale has no business slowing down a menu.
        if (g.talk.active()) {
            tickTalk(g, rawDt);
            bWasDown = true;
            bHeldT = ROLL_TAP_MAX;
            wasInside = false;
            sfx.ambience(rawDt);
            sfx.tickStreams();
            drawScene(g);
            hud(g, rawDt);
            g.talk.draw(&g.map, &g.trig, triggerWorld(g));
            rl.endDrawing();
            continue;
        }

        g.rest.update(rawDt);
        g.rest.look(g.hero.pos);
        // WHAT HE DROPPED, on the world's own clock — it is scenery with a prompt, like a bonfire, so it
        // ticks here beside one rather than inside the combat block.
        g.souls.update(dt);
        g.souls.look(g.hero.pos);
        sfx.tickStreams();

        const lockPressed = !g.hero.aiming and (rl.isMouseButtonPressed(.middle) or
            (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .right_thumb)));
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
                // SIGHT GOES SOFT, NOT OFF (ER's own feel): a pillar passing between you mid-circle must not
                // throw the camera off it. The lock lets go only after `LOCK_BLIND_HOLD`.
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
        // The yaw BEFORE any look input lands, so the probe can report what the camera actually turned this frame rather than what the devices claimed.
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
            if (inside and wasInside and @abs(md.x) > 40) flick = std.math.sign(md.x);
            if (@abs(padRX) > LOCK_FLICK) flick = std.math.sign(padRX);
            if (flick != 0 and lockCycleReady) {
                cycleLock(g, flick);
                lockCycleReady = false;
            } else if (@abs(md.x) < 12 and @abs(padRX) < 0.3) {
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
            // …the RAW magnitude, not the unlocked path's local copy of it.
            .mag = padMag,
            // Wrapped: yaw lives in (−pi, pi] so a turn across the seam is a small delta, not a full circle.
            .dyaw = mathx.degrees(mathx.wrapPi(g.rig.yaw - yawBefore)),
            .pad = lookPad,
        };
        wasInside = inside;
        if (wheel != 0) g.rig.zoom(wheel);

        // D-PAD RIGHT / Q: cycle the right-hand armament.
        var swapReq = rl.isKeyPressed(.q);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .left_face_right)) swapReq = true;
        if (swapReq and g.hero.swapArm()) sfx.play(.flask_cycle);

        // D-PAD LEFT / F: cycle the LEFT-hand armament — shield or wand. ER's own binding for that slot.
        // and the last free direction on the pad's D-pad now that Right, Up and Down are all spent.
        var offReq = rl.isKeyPressed(.f);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .left_face_left)) offReq = true;
        if (offReq and g.hero.swapOff()) sfx.play(.flask_cycle);

        var drinkReq = rl.isKeyPressed(.r);
        var cycleReq = rl.isKeyPressed(.t);
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .right_face_left)) drinkReq = true;
            if (rl.isGamepadButtonPressed(PAD, .left_face_down)) cycleReq = true;
        }
        if (cycleReq and !g.hero.dead) {
            g.hero.cycleQuick();
            sfx.play(.flask_cycle);
        }

        // D-PAD UP / G: cycle the SPELL. Up is the cross's SORCERY slot, so the button that changes it is the
        // slot it is shown in — the D-pad's "belongs to what it points at" rule.
        // arm on Right and the off hand on Left.
        var spellReq = rl.isKeyPressed(.g);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, .left_face_up)) spellReq = true;
        if (spellReq and g.hero.cycleSpell()) sfx.play(.flask_cycle);

        // …and the ARROW keeps a KEY OF ITS OWN. The cross is four directions and the spell has taken Up
        // (owner's call), so on the pad the quiver is changed in the character book's ammo slot instead.
        const arrowReq = rl.isKeyPressed(ARROW_KEY);
        if (arrowReq and g.hero.cycleArrow()) sfx.play(.flask_cycle);

        // Y everywhere (owner's call). A is left alone for the jump ER reserves it for.
        var useReq = rl.isKeyPressed(INTERACT_KEY);
        if (rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, INTERACT_PAD)) useReq = true;
        if (useReq and !g.hero.dead) interact(g);

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

        // L1/RMB belongs to the HAND, not the shield (the R1/R2 rule from the other side): boards block on a
        // held LEVEL, a wand casts on a pressed EDGE, so both are read here and neither swallows the other.
        var l1Held = rl.isMouseButtonDown(.right);
        var l1Press = rl.isMouseButtonPressed(.right);
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonDown(PAD, .left_trigger_1)) l1Held = true;
            if (rl.isGamepadButtonPressed(PAD, .left_trigger_1)) l1Press = true;
        }
        const bow = g.hero.bowOut();
        const wandUp = g.hero.wandOut();
        const guardHeld = l1Held and !wandUp;
        const castReq = l1Press and wandUp;

        // …AND L2 IS THAT HAND'S SKILL SLOT, ER's own, ROUTED THE SAME WAY: a raised bow AIMS on a held level,
        // boards PARRY on a pressed edge. On the pad it is one trigger; on the mouse the halves part company,
        // because RMB is already the guard's level and Shift+RMB would fire a parry on every sprinting block.
        var l2Held = rl.isMouseButtonDown(.right);
        var l2Press = rl.isKeyPressed(PARRY_KEY);
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonDown(PAD, .left_trigger_2)) l2Held = true;
            if (rl.isGamepadButtonPressed(PAD, .left_trigger_2)) l2Press = true;
        }
        const aimHeld = l2Held;
        const parryReq = l2Press and !bow;

        // R1/RB or LMB, and R2/RT or Shift+LMB.
        var r1 = false;
        var r2 = false;
        if (rl.isMouseButtonPressed(.left)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) r2 = true else r1 = true;
        }
        if (rl.isGamepadAvailable(PAD)) {
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_1)) r1 = true;
            if (rl.isGamepadButtonPressed(PAD, .right_trigger_2)) r2 = true;
        }
        const lightReq = r1 and !bow;
        const heavyReq = r2 and !bow;
        const quickReq = r1 and bow;
        const aimedReq = r2 and bow;

        // STAMINA GATES THE SPRINT AT THE SOURCE.
        var mv = gatherMove();
        if (!g.hero.stam.canSprint()) mv.speed = @min(mv.speed, RUN_SPEED);
        const wade = wadeDrag(g);
        if (wade < 1.0) mv.speed = @min(mv.speed, WALK_SPEED * wade);
        // Poise and stance regenerate every frame.
        g.hero.vit.tick(dt);
        // …and anything he ATE drips HP back.
        g.hero.regen.tick(dt, &g.hero.vit);
        g.hero.tickWard(dt); // the sporeling cap's chaos ward, running out beside it
        g.hero.tickFlash(dt); // fade the red damage flash
        // …and the QUICK BAR sheds whatever he has run out of, once a frame rather than at each site that can empty the bag.
        // empty the bag (a use, a drip, whatever spends one next): a per-site list is a list to forget one from.
        g.hero.quick.dropEmpty(&g.bag);
        // Action input is dead while staggered or dead (a reaction is committed).
        if (!g.hero.dead and !g.hero.staggered()) {
            if (rollReq) {
                g.hero.requestRoll(rollDir(g, mv));
            } else if (parryReq) {
                // ABOVE THE ATTACKS: L2 and R2 are separate buttons, so a frame carrying both is a player who
                // wants the defensive one. The shove is MOVED AIR; the CLANG belongs to the catch alone.
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
            }
            g.hero.steerQueuedRoll(rollDir(g, mv));
            if (drinkReq) quickUse(g);
        }
        // NO COMMITTED ACTION IS A SPRINT — ONE predicate, not a list of them. Written out as four named states
        // it had already forgotten two: the loose, and the parry, whose keyboard binding billed every parry as
        // a sprint.
        g.hero.sprinting = sprintingMove(mv) and !g.hero.committed() and !g.hero.dead and !g.hero.staggered();
        // …and the shield, AFTER the sprint (there is no running block — see hero.setGuard).
        g.hero.setGuard(guardHeld);
        g.hero.setAim(aimHeld);
        // BEHIND THE SHIELD HE SHUFFLES.
        if (g.hero.guarding) mv.speed = @min(mv.speed, WALK_SPEED * heromod.GUARD_SPEED);
        // …AND BEHIND A RAISED BOW HE BARELY MOVES AT ALL.
        if (g.hero.aiming) mv.speed = @min(mv.speed, WALK_SPEED * heromod.BOW_AIM_SPEED);
        // …AND A DRAUGHT IS A SHUFFLE, not a stop (owner's call). Denied at the SOURCE like the other two.
        if (g.hero.drinking) mv.speed = @min(mv.speed, WALK_SPEED * heromod.DRINK_SPEED);

        // While locked the hero faces the foe (so it strafes/backpedals around it), ER-style.
        const lockYaw: ?f32 = if (g.lock) |li| blk: {
            const d = mathx.dirXZ(g.hero.pos, foePos(g, li));
            break :blk if (mathx.lenXZ(d) > 0.001) mathx.headingXZ(d) else null;
        } else null;
        const faceYaw: ?f32 = if (g.hero.aiming) g.rig.yaw else lockYaw;
        // …AND HOW FAR DOWN (or up) THE THING HE IS SWINGING AT ACTUALLY IS.
        g.hero.aimAtPitch(meleePitch(g));
        // The slope under him, eased into the rig BEFORE it poses — every branch below ends in a `pose()`, so this has to be settled first or the lean is always one frame stale.
        leanToGround(g, dt);
        if (g.hero.dead) {
            g.hero.updateDeath(dt);
            // The frame he returns, the WORLD reloads with him (ER-style): every foe re-homed at full health, arrows cleared, lock dropped.
            if (!g.hero.dead) resetFoes(g);
        } else if (g.hero.staggered()) {
            g.hero.updateStun(dt);
        } else if (g.hero.rolling) {
            g.hero.updateRoll(dt, PLAY_HALF); // committed — ignores move input
        } else if (g.hero.drinking) {
            // COMMITTED, NOT PLANTED: the clock first, then the shuffle — either way through `moveHero`, so the
            // shared clocks advance exactly ONCE this frame (`tickClocks`).
            g.hero.tickDrink(dt);
            moveHero(g, dt, if (g.hero.drinking) mv else .{}, faceYaw);
        } else if (g.hero.attacking) {
            g.hero.updateAttack(dt, PLAY_HALF, faceYaw);
        } else if (g.hero.parrying) {
            g.hero.updateParry(dt, faceYaw); // PLANTED, like the cast — catching a blow is a standing job
        } else if (g.hero.shooting) {
            g.hero.updateShot(dt, faceYaw);
        } else if (g.hero.casting) {
            g.hero.updateCast(dt, faceYaw); // PLANTED, like a quick shot — both hands are busy
            // Pulsed EVERY frame, since a `rumble.Event` can only decay from its peak (`rumble.castCharge`).
            g.rumble.play(rumblemod.castCharge(g.hero.chargeFill()));
        } else {
            moveHero(g, dt, mv, faceYaw);
        }
        // WHERE EVERY FOE STOOD BEFORE IT MOVED — taken AFTER the hero's own branch, because a respawn re-homes
        // the whole field inside it and the gate would drag each fresh spawn back to where the last one died.
        var wasPos: [FOE_GROUPS.len][FOE_CAP]rl.Vector3 = undefined;
        // …AND HOW MANY OF EACH ROW IS REAL.
        var wasN: [FOE_GROUPS.len]usize = undefined;
        inline for (FOE_GROUPS, 0..) |f, gi| {
            const row = @field(g, f.field).live();
            wasN[gi] = row.len;
            snapshotPos(row, &wasPos[gi]);
        }
        // THE SHAFT LEAVES on the one frame the loose says so.
        if (g.hero.loosed) looseShaft(g);
        // …and THE SPELL on the one frame the cast does — whichever the rod is set to.
        if (g.hero.thrown) releaseSpell(g);
        const hitsBefore = allHits(g);
        markSight(g); // WHO CAN SEE HIM — stamped before anything decides what to do about him
        markParry(g); // …and WHAT HIS SHIELD IS DOING, before anything swings at him
        // ONE snapshot of the blade for every group this frame — re-derived per group, the three would disagree.
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
        // THE SHADES. Only the touch is a blow they deal in person — the wisp goes through the quiver like
        // every other thrown thing. It carries no stance at all, so it is never the heavy beat.
        if (g.haunt.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, spawnWisp)) |b| {
            // The same split every other group uses, not a hardcoded `false`: the touch carries no stance today.
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // THE LEECHFLIES. TWO CHANNELS: the beak going in is a BLOW (blockable), and the swallow after it is a
        // HOLD that goes through `hero.burn`. A shield answers the first and only the roll the second.
        if (g.swarm.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, leechSip)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
        }
        // THE ROOTED. Its hook hands the DRAG over rather than applying it — only this side knows whether the
        // blow was blocked, and a hook the boards caught must not move him. Spent AFTER `heroTakes`, since
        // that is the call that decides it.
        g.hook = null;
        if (g.grove.update(dt, g.hero.pos, PLAY_HALF, bladeNow, g, noteYank)) |b| {
            applyYank(g, heroTakes(g, b, b.hit.heavy(), true));
        }
        // THE SPORELINGS. The bonk is a blow; the cloud it leaves is a HOLD, billed further down beside
        // the mother's acid — two channels for the leechfly's reason.
        if (g.cluster.update(dt, g.hero.pos, PLAY_HALF, bladeNow)) |b| {
            _ = heroTakes(g, b, b.hit.heavy(), true);
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
        // THE TWO MOMENTS OF HERS THAT THE FRAME SHOULD FEEL.
        if (g.brood.hatches != hatchesBefore) {
            g.rumble.play(rumblemod.hit_heavy);
            g.rig.addShake(SHAKE_HATCH);
        }
        if (g.brood.bursts != burstsBefore) {
            g.rumble.play(rumblemod.kill);
            g.rig.addShake(SHAKE_SAC_BURST);
            // …and the sac's own death, billed here because a sac carries no `justDied` edge for `billDeaths`
            // to read. Her counter is the edge.
            var burst = burstsBefore;
            while (burst < g.brood.bursts) : (burst += 1) g.trig.died(.brood_sac);
        }
        // …AND THE MOMENTS THE SHIELD IS ALLOWED TO SIMPLY CANCEL. Read AFTER every group has updated, so one
        // beat covers the whole field: club, mace, greatsword and fangs are one catch as far as his arm knows.
        if (anyParried(g)) parryBeat(g);
        // THE VENOM ON THE GROUND AND IN THE AIR — neither is DAMAGE any more: both fill the one meter
        // (`combat.Status`). Standing in spores and acid at once is two bad decisions and doses as both,
        // which is the whole reason they are two `add` calls and not a max.
        g.hero.poisonBy(g.brood.burn(dt, g.hero.pos));
        g.hero.poisonBy(g.cluster.spores(dt, g.hero.pos));
        // …and the meter resolves LAST, after every source has had its say this frame, so a bar that filled
        // on this frame goes off on this frame rather than a frame late.
        // THE DRAIN ITSELF IS SILENT: it runs for fourteen seconds, and a beat on every tick of it would be
        // a rattle nobody can hear past. The PROC gets the whole of the feedback, once.
        _ = g.hero.tickPoison(dt);
        if (g.hero.poison.justProcced) {
            sfx.play(.acid_burn);
            g.rig.addShake(SHAKE_HURT);
            g.rumble.play(rumblemod.hurt);
            g.hero.hurtFlash = mathx.maxF(g.hero.hurtFlash, 0.7); // the ONE flash the poison gets
        }
        g.chests.update(dt, g.hero.pos);
        // THE FOLK, and the same terrain gate the foes get — a wanderer ambling about his post has no more
        // business walking up a cliff than a kobold has.
        var wasFolk: [npcmod.CAP]rl.Vector3 = undefined;
        const nFolk = g.folk.n;
        snapshotPos(g.folk.live(), &wasFolk);
        g.folk.update(dt, g.hero.pos, PLAY_HALF);
        gateTerrain(g, g.folk.live(), wasFolk[0..nFolk]);
        inline for (FOE_GROUPS, 0..) |f, gi| gateTerrain(g, @field(g, f.field).live(), wasPos[gi][0..wasN[gi]]);
        // Arrows in flight: gentle homing + arc, then a strike lands a chomp-weight blow.
        for (&g.arrows) |*ar| {
            if (!ar.live) continue;
            flyArrow(g, ar, dt);
            if (ar.hit) {
                const blow = foemod.Blow{
                    .hit = ar.blow,
                    .from = mathx.addV(g.hero.pos, mathx.scaleV(ar.vel, -1)),
                };
                // The BEAT is skipped on a corpse. `heavy` comes off the BLOW like every group's does — nothing
                // thrown carries stance today, so it reads false either way, and stays right when one gets some.
                const out: combat.HitOutcome = if (g.hero.dead) .ignored else heroTakes(g, blow, blow.hit.heavy(), false);
                // …and WHAT IT STRUCK picks that voice: boards if the shield caught it, flesh if not.
                if (out == .taken or out == .ignored) sfx.play(.arrow_hit);
                splashOf(g, ar);
            } else if (ar.stuck and ar.age == 0) {
                // ONLY THE GLOB IS SILENT HERE, because `brood.splash` plays its own voice. A clump keeps
                // the thunk the stone it replaced had — dropping it lost the landing its sound entirely.
                if (ar.shot != .venom) sfx.world(sfx.arrowImpact(ar.struck), ar.pos);
                splashOf(g, ar);
            }
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
            // The kill beat: a THUD, and nothing else (owner's call — no bell, no jingle).
            sfx.play(.kill);
        }
        // …and the kill PAYS.
        g.hero.runes.gain(allRunes(g));
        // ER lock-on across a kill: the lock leaves a corpse the FRAME it dies, snapping to the next valid target.
        if (g.lock) |li| {
            if (!foeLockable(g, li)) g.lock = acquireLock(g);
        }
        collideActors(g, dt);
        groundActor(g, &g.hero.pos, dt);
        inline for (FOE_GROUPS) |f| {
            for (@field(g, f.field).live()) |*a| groundActor(g, &a.pos, dt);
        }
        for (g.folk.live()) |*p| groundActor(g, &p.pos, dt);
        // THE SCRIPT LAYER LAST, so `deaths` and `alive` are this frame's answers and not the previous one's.
        tickTriggers(g, dt);
        g.rig.tickShake(rawDt);
        // THE AIM PULLS THE EYE IN PAST HIM, off the hero's own stance blend — set before the follow, so this frame's boom is already the aim's (see `camera.boom`).
        g.rig.aimB = g.hero.aimB;
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
        if (g.hero.swings != wasSwings) {
            g.rumble.play(if (g.hero.atkHeavy) rumblemod.swing_heavy else rumblemod.swing_light);
            sfx.play(if (g.hero.atkHeavy) .swing_heavy else .swing_light);
            wasSwings = g.hero.swings;
        }
        if (g.hero.aiming and !wasAiming) sfx.play(.bow_draw);
        wasAiming = g.hero.aiming;
        // A REFUSED action is heard as well as seen.
        if (g.hero.stamRefused > wasRefused) sfx.play(.refused);
        wasRefused = g.hero.stamRefused;
        // The stagger is its own beat: the blow that caused it already played, this is his footing going.
        if (g.hero.stun == .heavy and wasStun != .heavy) sfx.play(.stagger);
        wasStun = g.hero.stun;
        if (g.hero.dead and !wasDead) {
            g.rumble.play(rumblemod.death);
            g.rig.addShake(SHAKE_DEATH);
            sfx.play(.death);
            // …AND EVERYTHING HE WAS CARRYING GOES ONTO THE GROUND, on the frame he DIES rather than on the
            // respawn: the spill plays under the YOU DIED card, which is the one moment nothing else is.
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
        rl.endDrawing();
    }
}

fn footsteps(g: *Game, last: *f32) void {
    const h = &g.hero;
    if (h.moving < 0.45 or h.rolling or h.dead or h.staggered()) {
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

/// EVERYTHING THE CHARACTER BOOK READS, gathered in one place. It borrows the live state rather than a
/// copy, so nothing on those pages can be a frame behind what the game is playing with.
pub fn bookView(g: *Game) bookmod.View {
    return .{
        .bag = &g.bag,
        .sheet = &g.hero.sheet,
        .res = &g.hero.vit.res,
        .flasks = &g.hero.flasks,
        .quick = &g.hero.quick,
        .quiver = &g.hero.quiver,
        .inCombat = inCombat(g),
        .arm = g.hero.arm,
        .off = g.hero.off,
        .spell = g.hero.spell,
        .fp = g.hero.fp.cur,
        .runes = g.hero.runes.display(),
    };
}

/// A SWAP MADE IN THE BOOK. The same three moves the D-pad makes in play, so they go through the same
/// hero methods and pick up the same refusals — a menu may not put a bow in his hands mid-roll.
fn bookAct(g: *Game, a: bookmod.Action) void {
    switch (a) {
        .none => {},
        .use => |k| useItem(g, k),
        .arm => |want| if (g.hero.arm != want) {
            _ = g.hero.swapArm();
        },
        .off => |want| if (g.hero.off != want) {
            _ = g.hero.swapOff();
        },
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

fn quickLeft(g: *const Game) u8 {
    const k = g.hero.quick.selected() orelse return 0;
    return combat.quickCount(k, &g.hero.flasks, &g.bag);
}

/// SPEND THE THING THE QUICK BAR IS TURNED TO — the cross's DOWN press, and in combat the ONLY way anything
/// gets consumed. A flask goes down the committed draught; everything else is instant, because an edible is not a draught.
/// own `useItem`, which is instant and costs no animation, because an edible is not a draught.
fn quickUse(g: *Game) void {
    const k = g.hero.quick.selected() orelse return; // an empty bar: nothing to reach for
    if (combat.flaskOf(k)) |f| {
        // STAMPED HERE AND NOT ONLY AT THE CYCLE. `dropEmpty` can move the selection on any frame, and left to
        // the cycle alone the cross showed crimson while he drank the blue one.
        g.hero.flasks.sel = f;
        if (g.hero.startDrink()) sfx.play(.flask_drink);
        return;
    }
    useItem(g, k);
}

/// A flask never comes through here — its charges are `combat.Flasks`, refilled at a grace, and the bag has
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
        // THE CANDLE FLIES THE SLINGER'S OWN WAD (`.clump` — one fire in this world), thrown at the point the
        // reticle converges on, through the hero's shaft pool. ONE victim — nothing thrown here is a blast.
        .lob => |l| {
            if (g.bag.take(k, 1) == 0) return;
            const from = mathx.addV(heroAimPoint(g), mathx.scaleV(mathx.headingDir(g.hero.facing), 0.4));
            const hit = combat.Hit{ .dmg = l.dmg, .poise = l.poise, .elem = combat.elems(.{ .fire = l.fire }) };
            putIn(&g.shafts, archermod.launchShaft(from, camAimPoint(g), koboldmod.CLUMP_SPEED, hit, true, .clump));
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
    }
}

fn heroTakes(g: *Game, b: foemod.Blow, heavy: bool, voice: bool) combat.HitOutcome {
    const out = g.hero.takeHit(b.hit, mathx.dirXZ(g.hero.pos, b.from));
    switch (out) {
        .ignored => {}, // rolled through it, or he was already gone
        .taken => heroHurtBeat(g, heavy, voice),
        .blocked => heroBlockBeat(g, b.hit),
        .guardBroken => {
            g.rumble.play(rumblemod.guard_break);
            g.rig.addShake(SHAKE_GUARD_BREAK);
            sfx.play(.guard_break);
        },
    }
    return out;
}

fn heroBlockBeat(g: *Game, h: combat.Hit) void {
    // OFF THE RAW BLOW, like the stamina bill it is paid beside: a blow with no physical half at all — the
    // mother's spit, the sling's burning clump — read as the lightest thing in the game when this measured `dmg`.
    const w = mathx.clampF(h.raw() / BLOW_HEAVIEST, BLOCK_FELT_MIN, 1.0);
    g.rumble.play(if (w >= BLOCK_FELT_HEAVY) rumblemod.guard_block_heavy else rumblemod.guard_block);
    g.rig.addShake(SHAKE_BLOCK * w);
    sfx.play(.guard_block);
}

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
fn allRunes(g: *const Game) u32 {
    var n: u32 = 0;
    inline for (FOE_GROUPS) |f| n += @field(g, f.field).runesDropped();
    return n;
}

/// HOW FAR THE HERO MUST FOLD TO PUT A FLAT CUT THROUGH WHAT IS IN FRONT OF HIM — degrees below his own eye line, or null for "nothing worth stooping for".
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

/// THE PLAY SQUARE, named once — `mathx.clampXZ` with this world's own half-extent already in it.
fn inBounds(p: rl.Vector3) rl.Vector3 {
    return mathx.clampXZ(p, PLAY_HALF);
}

fn collideActors(g: *Game, dt: f32) void {
    const step = COLLIDE_RATE * dt; // max correction this frame — bigger pushes ease in (no warp)
    var hp = g.env.resolveActor(g.hero.pos, HERO_R);
    inline for (FOE_GROUPS) |gr| {
        for (@field(g, gr.field).live()) |*a| {
            if (foemod.corporeal(a) and !a.airborne()) hp = collision.pushOutCircle(hp, HERO_R, a.pos, a.bodyR());
        }
    }
    // A PERSON IS A BODY. You walk INTO a wanderer, never through one.
    for (g.folk.liveConst()) |*p| hp = collision.pushOutCircle(hp, HERO_R, p.pos, p.bodyR());
    g.hero.pos = mathx.approachV(g.hero.pos, inBounds(hp), step);

    inline for (FOE_GROUPS) |gr| settleGroup(g, gr, step);

    // …and they yield to HIM and to the world's solids, one way only (the FOE_GROUPS `vs` rule): two bodies
    // each half-correcting is jitter between them.
    for (g.folk.live()) |*p| {
        const r = p.bodyR();
        var q = g.env.resolveActor(p.pos, r);
        q = collision.pushOutCircle(q, r, g.hero.pos, HERO_R);
        p.pos = mathx.approachV(p.pos, inBounds(q), step);
    }
}

fn settleGroup(g: *Game, comptime gr: FoeGroup, step: f32) void {
    const foes = @field(g, gr.field).live();
    for (foes, 0..) |*a, i| {
        if (!foemod.corporeal(a)) continue;
        const r = a.bodyR();
        // Airborne exempts a jump from the terrain rule and from being shouldered — NEVER from the world's
        // solids, or a pounce leaves the arena through a wall. Full strength: a leap into stone stops at it.
        if (a.airborne()) {
            a.pos = inBounds(g.env.resolveActor(a.pos, r));
            continue;
        }
        var p = g.env.resolveActor(a.pos, r);
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
/// ASK ONE QUESTION OF WHATEVER A `FoeRef` POINTS AT.
fn askFoe(comptime T: type, g: *const Game, r: FoeRef, comptime ask: anytype) T {
    inline for (ROLE_GROUPS) |rg| {
        if (roleIdx(rg[1], r)) |i| return ask(&@field(g, rg[0]).band[i]);
    }
    if (r.kind == .brood_sac) return ask(&g.brood.sacs[r.idx]);
    return switch (r.kind) {
        .toad => ask(&g.warren.frogs[r.idx]),
        .archer => ask(&g.line.archers[r.idx]),
        .ogre => ask(&g.grief.ogres[r.idx]),
        .shade => ask(&g.haunt.shades[r.idx]),
        .leechfly => ask(&g.swarm.flies[r.idx]),
        .rooted => ask(&g.grove.trees[r.idx]),
        .shroom => ask(&g.cluster.shrooms[r.idx]),
        .berserker, .priest, .slinger => unreachable,
        .brood_mother, .broodling, .brood_sac => unreachable,
        .shieldman, .greatsword => unreachable,
    };
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
// A live, non-dissipating foe (both a fresh acquire and a held lock require this).
fn foeLockable(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype) bool {
            return f.alive() and !f.dying();
        }
    }.ask);
}
/// …and the same disguise test through a `FoeRef`: a Rooted that FOLDS BACK is scenery again, and a lock that
/// survived the fold would leave the reticle sitting on a dead tree.
fn foeDisguised(g: *const Game, r: FoeRef) bool {
    return askFoe(bool, g, r, struct {
        fn ask(f: anytype) bool {
            return disguised(f);
        }
    }.ask);
}
/// Every group is fixed storage plus a LIVE COUNT, so its tail is `undefined`: an index that outlived a re-home
/// is a read of undefined memory. `rehomeFoes` runs four ways and only three drop the lock, so the bound is here.
fn refInBounds(g: *const Game, r: FoeRef) bool {
    inline for (ROLE_GROUPS) |rg| {
        if (roleIdx(rg[1], r)) |i| return i < @field(g, rg[0]).liveConst().len;
    }
    if (r.kind == .brood_sac) return r.idx < g.brood.liveSacsConst().len;
    return switch (r.kind) {
        .toad => r.idx < g.warren.liveConst().len,
        .archer => r.idx < g.line.liveConst().len,
        .ogre => r.idx < g.grief.liveConst().len,
        .shade => r.idx < g.haunt.liveConst().len,
        .leechfly => r.idx < g.swarm.liveConst().len,
        .rooted => r.idx < g.grove.liveConst().len,
        .shroom => r.idx < g.cluster.liveConst().len,
        // …every kind handled by the three group checks above, named so a new one cannot slip past.
        .berserker, .priest, .slinger, .brood_mother, .broodling, .brood_sac, .shieldman, .greatsword => false,
    };
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

/// IS IT STILL IN DISGUISE? A dormant Rooted is a dead tree until something wakes it (`rooted.hidden`), and a
/// reticle offered on one gives the disguise away for nothing. Keyed off `@hasDecl` like every other optional
/// half of the foe contract, so a creature with nothing to hide simply never declares it.
fn disguised(f: anytype) bool {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "hidden")) return f.hidden();
    return false;
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
            if (!canSee(self.g, r)) continue; // the flick skips what the acquire would not have taken
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
}

const HURT_BAR_WINDOW = 5.0;

// Floating HP bars over EVERY target (shared foe contract, one walk for all).
const BarCtx = struct {
    cam: rl.Camera3D,
    /// THE FIXED FOE'S BAR IS ALWAYS UP, hit lately or not: the reticle is already on it. It goes with the
    /// RETICLE rather than with `g.lock`, so a suspended lock takes the bar down with the dot.
    lock: ?FoeRef,

    fn visit(self: *const BarCtx, foes: anytype, kind: ?FoeKind) void {
        for (foes, 0..) |*f, i| {
            if (!f.alive() or f.dying()) continue; // no bar over a corpse dissolving out
            const fixed = if (self.lock) |l| l.idx == i and l.kind == memberKind(f, kind) else false;
            // `sinceHurt`, not `sinceHit`: a spell that only takes HP — the bolt, and the roots' own grip —
            // counts as a hit for the bar's purposes, which is the whole question the bar is asking.
            if (!fixed and f.vit.sinceHurt > HURT_BAR_WINDOW) continue;
            // OVER ITS HEAD — and A HEAD CAN GO BEHIND THE EYE, which `projectToScreen` rightly refuses. The
            // CHEST is always in front of you, so the fallback projects that and the ceiling does the rest.
            const s = projectToScreen(self.cam, f.topWorld()) orelse
                projectToScreen(self.cam, f.centerWorld()) orelse continue;
            hud_.foeBar(s.x, s.y, f.vit.hpFrac(), f.staggered()); // size/colour/lift/CEILING all live in hud
        }
    }
};

fn drawFoeBars(g: *const Game) void {
    const ctx = BarCtx{ .cam = g.rig.cam, .lock = activeLock(g) };
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

